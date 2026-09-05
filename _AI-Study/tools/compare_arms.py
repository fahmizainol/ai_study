#!/usr/bin/env python3
"""Behavioural comparison of the two right-seat AIs from fixed-Normal baseline traces.

The six policy lessons in PORTABLE-AI-REBORN.md were induced from six hand-read
set_a battles. This measures each of them across every traced battle instead, so a
"lesson" either shows up as a real behavioural difference or it does not.

Layout assumption (checked against the run config, not assumed blindly): the left
battler, index 0, is always Reborn-Normal; index 1 is the arm's AI. Both arms face
the same left team on the same seed, so index-1 behaviour is directly comparable.

Only explicit choice==2 switches are counted as switches. Post-KO replacements go
through the shared engine policy for both sides and are not decisions either AI made.

Usage:
    python3 compare_arms.py generated/reborn_6v6_normal_baseline_set_*.ndjson
    python3 compare_arms.py ... --by-archetype
"""

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
PBS = STUDY.parent / "Reborn Yang" / "Reborn Yang" / "PBS" / "PBS"

ARMS = {"normal_portable": "portable", "intense_vs_normal": "intense",
        "normal_reborn": "reborn"}

PHAZE = {"HAZE", "WHIRLWIND", "ROAR", "CLEARSMOG", "DRAGONTAIL", "CIRCLETHROW"}
RECOVERY = {"RECOVER", "ROOST", "SOFTBOILED", "SLACKOFF", "MOONLIGHT", "MORNINGSUN",
            "SYNTHESIS", "REST", "WISH", "PAINSPLIT", "HEALBELL"}
HAZARD = {"STEALTHROCK", "SPIKES", "TOXICSPIKES"}
SETUP = {"SWORDSDANCE", "QUIVERDANCE", "DRAGONDANCE", "CALMMIND", "NASTYPLOT",
         "BELLYDRUM"}
STATUS_MOVE = {"TOXIC", "THUNDERWAVE", "WILLOWISP", "SPORE", "SLEEPPOWDER"}


def load_moves():
    """move id -> (internal name, base power)."""
    table = {}
    for line in (PBS / "moves.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split(",")
        if len(parts) > 4 and parts[0].strip().isdigit():
            table[int(parts[0])] = (parts[1].strip(), int(parts[4] or 0))
    if not table:
        raise SystemExit(f"could not parse {PBS/'moves.txt'}")
    return table


def category(name, power):
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
    """Positive stat stages only, Atk/Def/Spe/SpA/SpD (skip the null slot and acc/eva)."""
    if not stages:
        return 0
    return sum(s for s in stages[1:6] if isinstance(s, int) and s > 0)


class Stats:
    def __init__(self):
        self.battles = 0
        self.wins = 0
        self.commands = 0
        self.switches = 0
        self.oscillations = 0
        self.low_hp_switches = 0
        self.switch_in_damage = []       # HP fraction lost on the switch turn
        self.stall_turns = 0
        self.turns = 0
        self.redundant_hazards = 0
        self.cat = defaultdict(int)
        # decisions taken while the foe is meaningfully boosted (>= +2 total)
        self.vs_boost = defaultdict(int)
        self.vs_boost_turns = 0
        self.foe_hp_removed = 0.0        # total foe HP fraction removed
        self.recover_at_full = 0         # recovery chosen above 80% HP
        # A stall loop is the same move repeated into the same foe while that foe's
        # HP does not fall: the wall out-heals the attack. Portable's only escape
        # hatch for this is best_damage_pct < 10, which a mid-power move clears even
        # when the target roosts back more than it takes.
        self.loop_runs = 0               # runs of >= 3 unproductive repeats
        self.loop_turns = 0              # turns spent inside those runs
        self.longest_loop = 0
        self.foe_healed_turns = 0        # turns where the foe ENDED with more HP


def analyse(record, moves, stats):
    stats.battles += 1
    stats.wins += 1 if record.get("result") == "win" else 0
    stats.turns += int(record.get("turns") or 0)

    entries = record.get("commands") or []
    # index the round_end state that follows each command entry
    active_seq = []
    hazards_used = set()
    prev_foe_hp = None
    # run = consecutive turns spending the same move, same attacker, same target.
    # Judged on NET foe HP across the whole run, not per turn: a wall that roosts back
    # more than it takes loses HP every turn and still never dies, which a per-turn
    # damage test scores as progress.
    run = {"key": None, "len": 0, "start_hp": None, "end_hp": None}

    def close_run():
        if run["len"] >= 3 and run["start_hp"] is not None and run["end_hp"] is not None:
            if run["end_hp"] >= run["start_hp"] - 0.05:
                stats.loop_runs += 1
                stats.loop_turns += run["len"]
                stats.longest_loop = max(stats.longest_loop, run["len"])

    for pos, entry in enumerate(entries):
        if entry.get("phase") != "command":
            continue
        actors = {a["index"]: a for a in entry.get("actors", [])}
        me, foe = actors.get(1), actors.get(0)
        if not me or not foe:
            continue
        stats.commands += 1

        # the state right after this turn resolves
        after = None
        for later in entries[pos + 1:]:
            if later.get("phase") == "round_end":
                after = {a["index"]: a for a in later.get("actors", [])}
                break

        foe_frac = foe["hp"] / foe["totalhp"] if foe["totalhp"] else 0
        foe_after = after.get(0) if after else None
        foe_frac_after = (foe_after["hp"] / foe_after["totalhp"]
                          if foe_after and foe_after["totalhp"] else None)

        # progress: did this turn remove foe HP, land status, or change stages?
        removed = 0.0
        if foe_frac_after is not None and foe_after["party_slot"] == foe["party_slot"]:
            removed = max(0.0, foe_frac - foe_frac_after)
        stats.foe_hp_removed += removed
        progressed = removed > 0.01
        if foe_after and foe_after["party_slot"] == foe["party_slot"]:
            if foe_after.get("status") != foe.get("status"):
                progressed = True
            if foe_after.get("stages") != foe.get("stages"):
                progressed = True
        if not progressed:
            stats.stall_turns += 1

        my_frac = me["hp"] / me["totalhp"] if me["totalhp"] else 0
        foe_boost = boost_sum(foe.get("stages"))

        choice = me.get("choice")
        if choice == 2:
            label = "switch"
            stats.switches += 1
            if my_frac < 0.30:
                stats.low_hp_switches += 1
            target = me.get("switch_slot")
            # oscillation: returning to a slot that was active two actives ago
            if len(active_seq) >= 2 and target == active_seq[-2]:
                stats.oscillations += 1
            if target is not None and (not active_seq or active_seq[-1] != target):
                active_seq.append(target)
            me_after = after.get(1) if after else None
            if me_after and me_after["totalhp"]:
                stats.switch_in_damage.append(
                    max(0.0, 1.0 - me_after["hp"] / me_after["totalhp"]))
        elif choice == 1:
            name, power = moves.get(me.get("move_id") or -1, ("?", 0))
            label = category(name, power)
            if label == "hazard":
                if name in hazards_used:
                    stats.redundant_hazards += 1
                hazards_used.add(name)
            if label == "recover" and my_frac > 0.80:
                stats.recover_at_full += 1
        else:
            label = "other"
        stats.cat[label] += 1

        # Unproductive repetition: same attacker, same move, same target, and the
        # target did not end the turn with less HP than it started.
        same_foe = (foe_after is not None
                    and foe_after["party_slot"] == foe["party_slot"])
        if same_foe and foe_frac_after is not None and foe_frac_after > foe_frac + 0.01:
            stats.foe_healed_turns += 1
        if choice == 1:
            key = (me.get("move_id"), me["party_slot"], foe["party_slot"])
            if key == run["key"]:
                run["len"] += 1
            else:
                close_run()
                run.update(key=key, len=1, start_hp=foe_frac)
            run["end_hp"] = foe_frac_after if same_foe else None
        else:
            close_run()
            run.update(key=None, len=0, start_hp=None, end_hp=None)

        if not active_seq:
            active_seq.append(me.get("party_slot"))
        elif choice != 2 and active_seq[-1] != me.get("party_slot"):
            active_seq.append(me.get("party_slot"))

        if foe_boost >= 2:
            stats.vs_boost_turns += 1
            stats.vs_boost[label] += 1
        prev_foe_hp = foe_frac

    close_run()


def row(label, s):
    n = max(1, s.commands)
    b = max(1, s.battles)
    swin = (sum(s.switch_in_damage) / len(s.switch_in_damage) * 100
            if s.switch_in_damage else 0)
    return (f"{label:22} {s.wins:>3}/{s.battles:<3} "
            f"{s.wins/b*100:5.1f}% {s.turns/b:5.1f} "
            f"{s.switches/n*100:6.1f}% {s.oscillations/b:5.2f} "
            f"{s.low_hp_switches/b:5.2f} {swin:5.1f}% "
            f"{s.stall_turns/n*100:6.1f}% {s.redundant_hazards/b:5.2f} "
            f"{s.foe_hp_removed/max(1,s.turns)*100:5.1f}% "
            f"{s.loop_runs/b:5.2f} {s.loop_turns/n*100:6.1f}% "
            f"{s.longest_loop:>4} {s.foe_healed_turns/n*100:6.1f}%")


HEADER = (f"{'arm':22} {'wins':>7} {'rate':>6} {'turns':>5} "
          f"{'switch':>7} {'osc/b':>5} {'lowHP':>5} {'swDmg':>6} "
          f"{'stall':>7} {'rdHaz':>5} {'dmg/t':>6} "
          f"{'loop/b':>5} {'inLoop':>6} {'max':>4} {'foeHeal':>7}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="+", type=Path)
    parser.add_argument("--by-archetype", action="store_true")
    args = parser.parse_args()

    moves = load_moves()
    pooled = defaultdict(Stats)
    per_set = defaultdict(Stats)
    per_arch = defaultdict(Stats)

    for path in args.results:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            arm = ARMS.get(record.get("arm"))
            if not arm or not record.get("commands"):
                continue
            team_set = record.get("team_set", "set_a")
            arch = record.get("right_test_team")
            for stats in (pooled[arm], per_set[(team_set, arm)],
                          per_arch[(arch, arm)]):
                analyse(record, moves, stats)

    print("Measured seat (index 1) behaviour. osc/b = A->B->A returns per battle;")
    print("lowHP = explicit switches below 30% HP per battle; swDmg = mean HP lost")
    print("on the switch-in turn; stall = turns removing no HP/status/stage.\n")
    print(HEADER)
    print("-" * len(HEADER))
    for arm in ("reborn", "portable", "intense"):
        if arm in pooled:
            print(row(f"POOLED {arm}", pooled[arm]))
    print()
    for key in sorted(per_set):
        print(row(f"{key[0]} {key[1]}", per_set[key]))

    if args.by_archetype:
        print("\nBy measured-seat archetype:")
        print(HEADER)
        print("-" * len(HEADER))
        for arch in sorted({k[0] for k in per_arch}):
            for arm in ("reborn", "portable", "intense"):
                if (arch, arm) in per_arch:
                    print(row(f"{arch} {arm}", per_arch[(arch, arm)]))
            print()

    print("\nDecision mix when the FOE is boosted >= +2 total stages")
    print("(the 'explicit setup-threat response' lesson):")
    labels = ["attack", "switch", "phaze", "recover", "status", "setup",
              "hazard", "protect", "other"]
    print(f"{'arm':22} {'turns':>6} " + " ".join(f"{l[:7]:>7}" for l in labels))
    for arm in ("reborn", "portable", "intense"):
        s = pooled.get(arm)
        if not s:
            continue
        tot = max(1, s.vs_boost_turns)
        cells = " ".join(f"{s.vs_boost.get(l,0)/tot*100:6.1f}%" for l in labels)
        print(f"{'POOLED '+arm:22} {s.vs_boost_turns:>6} {cells}")
    # Share of each AI's switching that happens specifically while the foe is boosted.
    # A foe at +2 roughly doubles incoming damage, so it turns threatened_lethal? on by
    # itself; if that is where the switches cluster, the boost is causing the flight.
    print("\nShare of all explicit switches taken while the foe is boosted >= +2:")
    for arm in ("reborn", "portable", "intense"):
        s = pooled.get(arm)
        if not s:
            continue
        print(f"  {arm:10} {s.vs_boost.get('switch', 0):>4}/{s.switches:<4} "
              f"= {s.vs_boost.get('switch',0)/max(1,s.switches)*100:5.1f}%  "
              f"(boosted turns are {s.vs_boost_turns/max(1,s.commands)*100:4.1f}% "
              f"of all turns)")

    print("\nOverall decision mix (all turns):")
    print(f"{'arm':22} {'turns':>6} " + " ".join(f"{l[:7]:>7}" for l in labels))
    for arm in ("reborn", "portable", "intense"):
        s = pooled.get(arm)
        if not s:
            continue
        tot = max(1, s.commands)
        cells = " ".join(f"{s.cat.get(l,0)/tot*100:6.1f}%" for l in labels)
        print(f"{'POOLED '+arm:22} {s.commands:>6} {cells}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
