#!/usr/bin/env python3
"""Where Portable would have deviated from Reborn-Normal, turn by turn.

The shadow_reborn arm has Reborn-Normal play the battle while the portable planner
answers from the same position every turn without registering anything. Unlike two
live arms — which hold identical state for a median of 2 turns before becoming
different battles — every single turn here is a controlled comparison.

Reborn-Normal wins 79.4% of these battles and Portable 64.4%, so a disagreement is
not automatically a Portable error. But disagreements are where the entire 15-point
gap lives, and their distribution says which situations to look at.

The shadow does NOT carry portable memory (it never moved, so it recorded no setup
repeats), so shadow "setup" choices are slightly over-represented relative to a live
portable run. Everything else is exact.

Usage:
    python3 shadow_diff.py generated/reborn_6v6_v031_set_*.ndjson
    python3 shadow_diff.py <ndjson...> --context
"""

import argparse
import json
import sys
from collections import defaultdict, Counter
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
PBS = STUDY.parent / "Reborn Yang" / "Reborn Yang" / "PBS" / "PBS"

MEASURED = 1
OPPONENT = 0
SHADOW_ARM = "shadow_reborn"


def load_moves():
    """numeric id -> (internal name, base power), plus name -> power.

    The two traces speak different dialects: the engine's command trace stores the
    numeric move id (514), while the portable plan stores the internal name
    ("BRAVEBIRD"). Everything is compared as names.
    """
    table = {}
    for line in (PBS / "moves.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split(",")
        if len(parts) > 4 and parts[0].strip().isdigit():
            table[int(parts[0])] = (parts[1].strip(), int(parts[4] or 0))
    if not table:
        raise SystemExit(f"could not parse {PBS/'moves.txt'}")
    power = {name: pw for name, pw in table.values()}
    return table, power


PHAZE = {"HAZE", "WHIRLWIND", "ROAR", "CLEARSMOG", "DRAGONTAIL", "CIRCLETHROW"}
RECOVERY = {"RECOVER", "ROOST", "SOFTBOILED", "SLACKOFF", "MOONLIGHT", "MORNINGSUN",
            "SYNTHESIS", "REST", "WISH", "PAINSPLIT", "HEALBELL"}
HAZARD = {"STEALTHROCK", "SPIKES", "TOXICSPIKES"}
SETUP = {"SWORDSDANCE", "QUIVERDANCE", "DRAGONDANCE", "CALMMIND", "NASTYPLOT",
         "BELLYDRUM"}
STATUS_MOVE = {"TOXIC", "THUNDERWAVE", "WILLOWISP", "SPORE", "SLEEPPOWDER"}


def kind(name, power_by_name):
    power = power_by_name.get(name, 0)
    if name in PHAZE:
        return "phaze"
    if name in RECOVERY:
        return "recover"
    if name in HAZARD:
        return "hazard"
    if name in SETUP:
        return "setup"
    if name in STATUS_MOVE:
        return "status"
    if name in ("PROTECT", "SPIKYSHIELD", "DETECT"):
        return "protect"
    return "attack" if power > 0 else "other"


def boost_sum(stages):
    if not stages:
        return 0
    return sum(s for s in stages[1:6] if isinstance(s, int) and s > 0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="+", type=Path)
    parser.add_argument("--context", action="store_true",
                        help="break disagreements down by situation")
    args = parser.parse_args()

    moves, power_by_name = load_moves()

    battles = 0
    compared = 0
    agreed = 0
    pairs = Counter()             # (host kind, shadow kind) on disagreement
    by_arch = defaultdict(lambda: [0, 0])
    ctx = defaultdict(lambda: [0, 0])   # situation -> [compared, agreed]
    switch_slot_mismatch = 0
    shadow_only_turns = 0

    for path in args.results:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if rec.get("arm") != SHADOW_ARM or not rec.get("commands"):
                continue
            shadow = {}
            for entry in rec.get("portable_shadow") or []:
                if entry.get("actor") == MEASURED:
                    shadow[entry["turn"]] = entry
            if not shadow:
                continue
            battles += 1
            arch = rec.get("right_test_team")

            for entry in rec["commands"]:
                if entry.get("phase") != "command":
                    continue
                actors = {a["index"]: a for a in entry.get("actors", [])}
                me, foe = actors.get(MEASURED), actors.get(OPPONENT)
                if not me or not foe:
                    continue
                plan = shadow.get(entry.get("turn"))
                if not plan:
                    # Turns the planner was never asked about: forced moves, Struggle,
                    # post-KO replacement. Not decisions, so not comparable.
                    continue
                host_choice = me.get("choice")
                if host_choice not in (1, 2):
                    continue
                compared += 1
                shadow_only_turns += 0

                if host_choice == 1:
                    host_name = moves.get(me.get("move_id") or -1, ("?", 0))[0]
                    host_kind = kind(host_name, power_by_name)
                    host_sig = ("move", host_name)
                else:
                    host_kind = "switch"
                    host_sig = ("switch", me.get("switch_slot"))
                if plan["type"] == "move":
                    shadow_name = plan.get("move_id")
                    shadow_kind = kind(shadow_name, power_by_name)
                    shadow_sig = ("move", shadow_name)
                else:
                    shadow_kind = "switch"
                    shadow_sig = ("switch", plan.get("slot"))

                same = host_sig == shadow_sig
                if same:
                    agreed += 1
                else:
                    pairs[(host_kind, shadow_kind)] += 1
                    if host_kind == "switch" and shadow_kind == "switch":
                        switch_slot_mismatch += 1

                by_arch[arch][0] += 1
                by_arch[arch][1] += 1 if same else 0

                if args.context:
                    my_frac = me["hp"] / me["totalhp"] if me["totalhp"] else 0
                    foe_boost = boost_sum(foe.get("stages"))
                    my_neg = sum(s for s in (me.get("stages") or [])[1:6]
                                 if isinstance(s, int) and s < 0)
                    buckets = []
                    buckets.append("foe boosted >= +2" if foe_boost >= 2
                                   else "foe unboosted")
                    buckets.append("me below 30% HP" if my_frac < 0.30
                                   else "me above 30% HP")
                    if my_neg <= -2:
                        buckets.append("my stats dropped >= 2")
                    if foe["hp"] / max(1, foe["totalhp"]) < 0.25:
                        buckets.append("foe below 25% HP")
                    for b in buckets:
                        ctx[b][0] += 1
                        ctx[b][1] += 1 if same else 0

    if not compared:
        raise SystemExit("no shadow_reborn records with traces found")

    print(f"{battles} shadow battles, {compared} controlled decision points.\n")
    print(f"Reborn-Normal and Portable chose the same action "
          f"{agreed}/{compared} = {agreed/compared*100:.1f}% of the time.")
    print(f"They differ on {compared-agreed} turns — that is where the whole gap "
          f"has to live.\n")

    print("Disagreements, host choice vs what Portable would have done:")
    print(f"  {'Reborn-Normal did':<20} {'Portable would':<20} {'n':>5} {'%':>6}")
    total_diff = max(1, compared - agreed)
    for (hk, sk), n in pairs.most_common(18):
        print(f"  {hk:<20} {sk:<20} {n:>5} {n/total_diff*100:5.1f}%")
    if switch_slot_mismatch:
        print(f"\n  ({switch_slot_mismatch} of the switch/switch rows are the same "
              f"decision to leave, disagreeing only on which mon comes in.)")

    print("\nAgreement by measured-seat archetype:")
    for arch in sorted(by_arch):
        c, a = by_arch[arch]
        print(f"  {arch:<10} {a:>5}/{c:<5} = {a/max(1,c)*100:5.1f}%")

    if args.context:
        print("\nAgreement by situation (low agreement = Portable's blind spots):")
        for name in sorted(ctx, key=lambda k: ctx[k][1] / max(1, ctx[k][0])):
            c, a = ctx[name]
            print(f"  {name:<24} {a:>5}/{c:<5} = {a/max(1,c)*100:5.1f}%")
    return 0


if __name__ == "__main__":
    sys.exit(main())
