#!/usr/bin/env python3
"""Render one traced Realidea gauntlet battle as readable text.

Deliberately NOT part of tools/render_battle.py. That renderer is built around three
things the Reborn gauntlet records and this one does not: per-turn `commands` (both
actors' state at choice time), `events` (what the engine actually executed, so a miss or
a Protect does not read as "hit for nothing"), and per-candidate `reasons` (the score
breakdown). Realidea's trace is a thinner record -- the chosen action plus the view the
core saw -- so sharing one function would mean branching on almost every line for no
shared logic.

What that means when reading the output, and it is worth keeping in mind:

  * A mode=portable record traces the Portable arm ALONE -- it is the arm that played,
    so there is no stock answer to the same board and no turn-by-turn diff. For that,
    run the shadow arm (modes=shadow), where stock plays and Portable answers from the
    identical position every turn without registering; those records carry both answers
    per turn and are rendered side by side here. Check such a run with shadow_check.py
    first: the comparison means nothing unless observation was free.
  * These are DECISIONS, not OUTCOMES. The line says what Portable chose and the
    evidence it chose on. It does not say whether the move hit, crit, or was Protected.
  * A turn with no line is a turn Portable did not decide: the adapter fell through to
    the stock path, or the actor could not act.

Usage:
    python3 render_realidea_battle.py <ndjson> [matchup_id] [seed]
    python3 render_realidea_battle.py <ndjson> --list
"""

import json
import sys
from pathlib import Path

# One owner for "did these two choose the same thing": moves compare on numeric id,
# switches on party slot. Restating that rule here would let the readout and the
# statistics drift apart, which is exactly the kind of disagreement no one notices.
from shadow_check import label, same_choice


def load(path):
    return [json.loads(l) for l in Path(path).read_text(encoding="utf-8").splitlines()
            if l.strip()]


def party_names(party):
    return ", ".join((m or {}).get("species", "-") for m in party)


def slot_name(party, slot):
    try:
        return (party[slot] or {}).get("species") or "slot%s" % slot
    except Exception:
        return "slot%s" % slot


def render_shadow(record):
    """Both AIs' answers to the same board, turn by turn.

    The stock arm is the one that played: every `stock` line below actually happened,
    and every `portable` line is what the portable planner would have done instead,
    computed from the identical position and registered nowhere.
    """
    trace = record.get("shadow") or []
    right = (record.get("parties") or [[], []])[1]
    for entry in trace:
        portable, stock = entry.get("portable"), entry.get("stock")
        verdict = same_choice(portable, stock)
        mark = {True: "", False: "   <- DIFFERENT", None: "   (not comparable)"}[verdict]
        print("\nTurn %-3s actor %s%s" % (entry.get("turn"), entry.get("actor"), mark))
        print("    stock   : %s" % describe(stock, right))
        print("    portable: %-28s score %8.1f" % (
            describe(portable, right), (portable or {}).get("score") or 0))
        render_view(entry.get("view") or {})


def describe(choice, party):
    """A choice as text. Switches name the party member; the slot IS a party index."""
    if not choice:
        return "-"
    if choice.get("type") == "switch":
        return "switch -> %s" % slot_name(party, choice.get("slot"))
    text = label(choice)
    if choice.get("target") is not None and choice.get("target") != -1:
        text += " @%s" % choice["target"]
    return text


def render_view(view):
    if not view:
        return
    print("    view: hp %.0f%%  speed %s (%s)  incoming max %.0f%%  "
          "certain %s  threatened_lethal=%s" % (
              view.get("hp_pct") or 0, view.get("speed"),
              "faster" if view.get("faster") else "slower",
              view.get("incoming_damage_pct") or 0,
              ("%.0f%%" % view["certain_incoming_damage_pct"])
              if view.get("certain_incoming_damage_pct") is not None else "n/a",
              view.get("threatened_lethal")))
    # The damage race: turns to kill each way, as the core counted them. Keyed by
    # BATTLER index, which is a seat, not a party slot -- the record carries no per-turn
    # foe identity, so the seat is named and not guessed at. (A switch entry's `slot` IS
    # a party index and is resolved to a species.)
    for index, race in sorted((view.get("race") or {}).items()):
        if not race:      # the core declines a race it cannot compute
            print("    race vs foe@%s: not computed" % index)
            continue
        print("    race vs foe@%s: mine %s turns, theirs %s, winning=%s%s" % (
            index, race.get("mine"), race.get("theirs"), race.get("winning"),
            " (ties on speed)" if race.get("last_hit_first") else ""))


def render(record):
    parties = record.get("parties") or [[], []]
    left, right = parties[0], parties[1]   # left = stock seat, right = Portable seat
    print("%s  seed %s  %s   %s in %d turns   [portable %s, mega=%s, teams=%s]" % (
        record.get("id"), record.get("seed"), record.get("format"),
        str(record.get("result")).upper(), record.get("turns") or 0,
        record.get("portable_version", "?"), record.get("mega"), record.get("teams")))
    if record.get("timed_out"):
        print("  hit the 100-round cap; the engine discarded its verdict, which was: %s"
              % record.get("timeout_result"))
    if record.get("error"):
        print("  ENGINE ERROR: %s" % record["error"])
        if record.get("where"):
            print("    at: %s" % record["where"])
        print("    turns below are what Portable decided BEFORE the engine raised.")
    # .get throughout: an error record is built by run_one's rescue and is thin.
    print("  left  (%s): %s" % (record.get("left_stock_team", "?"), party_names(left)))
    # In a shadow run BOTH seats are stock-piloted; the right seat is merely the one the
    # portable planner was asked about. Calling it "PORTABLE" there would misreport who
    # played the battle.
    print("  %s (%s): %s" % (
        "observed" if record.get("shadow") else "PORTABLE",
        record.get("right_test_team", "?"), party_names(right)))
    print("=" * 104)

    if record.get("shadow"):
        print("  shadow arm: stock played BOTH seats; 'portable' lines were computed "
              "and never registered.")
        render_shadow(record)
        return

    trace = record.get("trace") or []
    if not trace:
        print("  (no trace on this record -- the run was not made with trace=true, "
              "or this is the stock arm)")
        return
    for entry in trace:
        view = entry.get("view") or {}
        if entry.get("type") == "switch":
            action = "switch -> %s" % slot_name(right, entry.get("slot"))
        else:
            action = entry.get("move_id") or "move%s" % entry.get("slot")
            if entry.get("target") is not None:
                action += " @%s" % entry["target"]
        print("\nTurn %-3s actor %s   %-28s score %8.1f" % (
            entry.get("turn"), entry.get("actor"), action, entry.get("score") or 0))
        render_view(view)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    records = load(sys.argv[1])
    if "--list" in sys.argv:
        for r in records:
            entries = r.get("trace") or r.get("shadow")
            if entries:
                print("%-18s seed=%-10s %-6s %-5s turns=%-4s decisions=%d" % (
                    r.get("id"), r.get("seed"), r.get("mode"), r.get("result"),
                    r.get("turns") or 0, len(entries)))
        return
    args = [a for a in sys.argv[2:] if not a.startswith("--")]
    wanted = [r for r in records
              if (not args or r.get("id") == args[0])
              and (len(args) < 2 or str(r.get("seed")) == args[1])
              and (r.get("trace") or r.get("shadow"))]
    if not wanted:
        sys.exit("no traced battle matched; try --list")
    for record in wanted:
        render(record)
        print()


if __name__ == "__main__":
    main()
