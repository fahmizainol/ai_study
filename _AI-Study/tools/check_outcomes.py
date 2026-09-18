#!/usr/bin/env python3
"""Flag turns where a damaging move was predicted to land and nothing happened.

The existing --check compares poke-engine's calculate_damage against Essentials'
pbRoughDamage. Both are PREDICTIONS made from the same pre-turn state, so a mechanic
neither of them models -- a semi-invulnerable target, a King's Shield -- makes them
agree with each other and disagree with the battle. Two real defects hid in exactly
that gap.

This compares a prediction against what the game then DID, which needs no knowledge
of which mechanic is missing. That is the point: every audit so far could only find
mechanics someone thought to look for.

It reads the battle log alone -- a decision row carries the chosen move's `damaging`
flag and `expected_damage_pct`, and the NEXT row carries the target's hp, so before
and after are already on disk. No adapter change, and it runs on logs already
recorded.

Output is candidates, not defects, and the first run made that concrete: 26 rows, of
which 17 were the instrument's own blind spots rather than the engine's. Two are
filtered here -- a user knocked out before it acted, and a target that out-healed the
hit -- and a third cannot be, because the log records a DECISION and never says
whether it was carried out. A slower user that is flinched, frozen, fully paralysed
or asleep produces a perfect zero and looks identical to a mechanic nobody exported.
Rock Slide flinching Croagunk was exactly that.

So read the repeats first. A miss is random and a mechanic is not: the same move
doing nothing to the same body turn after turn is worth opening, and a singleton is
usually weather. On the logs recorded to 2026-09-19 the top cluster was FACADE into a
DIGging Excadrill, three times -- which is how this instrument found, from logs
alone and with no knowledge that two-turn moves existed, the defect that had already
been fixed by hand.
"""

import argparse
import collections
import json
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
DEFAULT_LOG = STUDY.parent / "Realidea V4.1" / "Data" / "ai_foulplay_battles.ndjson"


def rows_by_battle(path):
    battles = collections.OrderedDict()
    with open(path, errors="replace") as handle:
        for line in handle:
            if line.strip():
                row = json.loads(line)
                battles.setdefault(row.get("battle_id"), []).append(row)
    return battles


def target_of(row):
    targets = (row.get("view") or {}).get("targets") or []
    return targets[0] if targets else None


def divergences(battles, floor):
    for battle_id, rows in battles.items():
        for row, nxt in zip(rows, rows[1:]):
            if row.get("type") != "move":
                continue
            chosen = next((c for c in row.get("candidates") or []
                           if c.get("move_id") == row.get("move_id")
                           and c.get("type") == "move"), None)
            if not chosen or not chosen.get("damaging"):
                continue
            expected = chosen.get("expected_damage_pct")
            if not expected or expected < floor:
                continue
            # The user was slower and was knocked out before it acted, so its move
            # never executed. The log records a DECISION, not an execution, and this
            # was the single largest false-positive class on the first run.
            view, next_view = row.get("view") or {}, nxt.get("view") or {}
            if (view.get("faster") is False and nxt.get("turn") == row.get("turn")
                    and nxt.get("type") == "switch" and not next_view.get("hp_pct")):
                continue
            before, after = target_of(row), target_of(nxt)
            if not before or not after:
                continue
            # A different body is a switch, not a failure to damage; 0 hp means the
            # move did everything it could.
            if before.get("species") != after.get("species") or not after.get("hp_pct"):
                continue
            observed = (before.get("hp_pct") or 0) - (after.get("hp_pct") or 0)
            if observed > 0.5:
                continue
            # A target that ends the turn with MORE hp drained or healed; the move may
            # well have landed and been out-healed. Net zero cannot distinguish that
            # from a move that did nothing, so it is not evidence either way.
            if observed < -0.5:
                continue
            yield {
                "battle": battle_id,
                "turn": row.get("turn"),
                "user": (row.get("view") or {}).get("species"),
                "move": row.get("move_id"),
                "target": before.get("species"),
                "expected_pct": round(expected, 1),
                "observed_pct": round(observed, 1),
                "foe_did": "; ".join(str(d.get("move_id") or d.get("type"))
                                     for d in (row.get("foe") or {}).values()) or "?",
            }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default=str(DEFAULT_LOG))
    ap.add_argument("--floor", type=float, default=5.0,
                    help="ignore predictions below this %% of the target's hp")
    args = ap.parse_args()

    found = list(divergences(rows_by_battle(args.log), args.floor))
    if not found:
        print("no divergences: every damaging move that was predicted to land, landed")
        return

    # A repeat is the signal. One whiff is an accuracy roll; the same move doing
    # nothing to the same body turn after turn is a mechanic nobody exported.
    repeats = collections.Counter((f["move"], f["target"]) for f in found)
    print(f"{len(found)} turns where a damaging move was predicted to land and did not\n")
    for f in sorted(found, key=lambda f: (-repeats[(f["move"], f["target"])],
                                          f["battle"], f["turn"])):
        n = repeats[(f["move"], f["target"])]
        mark = f"  <-- x{n} vs the same body" if n > 1 else ""
        print(f"  {f['battle'][:15]} t{f['turn']:<3} {f['user']:<11} {f['move']:<13}"
              f" -> {f['target']:<11} expected {f['expected_pct']:>5.1f}%  got"
              f" {f['observed_pct']:>5.1f}%   (foe: {f['foe_did']}){mark}")


if __name__ == "__main__":
    main()
