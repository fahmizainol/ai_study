#!/usr/bin/env python3
"""Decision-level diff of two right-seat AIs on the same matchup, seed and roster.

Both arms start from the same parties with the same srand(seed), so while the two
battles hold identical state they are a controlled comparison: any difference in the
measured seat's choice at such a turn is a pure policy difference, not a consequence
of drift. Once a choice differs — or once the engines' RNG streams part — the states
separate and later turns are only descriptive.

The tool therefore reports two different things and never mixes them:

  controlled region   turns where both battles are in *byte-identical* state.
                      Decision agreement here is the real policy comparison.
  full trajectory     the whole battle, side by side, for reading one match.

Only the measured seat (battler index 1) is compared; index 0 is the shared
Reborn-Normal opponent.

Usage:
    python3 diff_battles.py generated/reborn_6v6_fairdiff_set_*.ndjson
    python3 diff_battles.py <ndjson...> --show bulky_vs_speed:196613:set_a
    python3 diff_battles.py <ndjson...> --arch bulky --limit 5
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


def load_names():
    """move id -> internal name, species id -> internal name."""
    moves = {}
    for line in (PBS / "moves.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split(",")
        if len(parts) > 4 and parts[0].strip().isdigit():
            moves[int(parts[0])] = parts[1].strip()
    species = {}
    current = None
    for line in (PBS / "pokemon.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            current = int(line[1:-1])
        elif line.startswith("InternalName=") and current is not None:
            species[current] = line.split("=", 1)[1].strip()
    if not moves or not species:
        raise SystemExit(f"could not parse PBS at {PBS}")
    return moves, species


def commands(record):
    return [e for e in (record.get("commands") or []) if e.get("phase") == "command"]


def by_index(entry):
    return {a["index"]: a for a in entry.get("actors", [])}


def state_key(entry):
    """Everything about the position, excluding the choices made from it."""
    out = []
    for actor in sorted(entry.get("actors", []), key=lambda a: a["index"]):
        out.append((actor["index"], actor["species"], actor["party_slot"],
                    actor["hp"], actor["totalhp"], actor["status"],
                    actor["status_count"], tuple(actor.get("stages") or [])))
    return tuple(out)


def decision(actor, moves):
    """Compact, comparable description of one battler's chosen action."""
    if actor is None:
        return "-"
    choice = actor.get("choice")
    if choice == 1:
        return "move:" + moves.get(actor.get("move_id") or -1, f"?{actor.get('move_id')}")
    if choice == 2:
        return f"switch:{actor.get('switch_slot')}"
    return f"choice{choice}"


def hp_str(actor):
    if not actor or not actor.get("totalhp"):
        return "  - "
    return f"{actor['hp'] / actor['totalhp'] * 100:3.0f}%"


def stage_str(actor):
    """Non-zero stat stages as +2Atk/-1Spe, or blank."""
    names = [None, "Atk", "Def", "Spe", "SpA", "SpD", "Acc", "Eva"]
    stages = (actor or {}).get("stages") or []
    parts = [f"{stages[i]:+d}{names[i]}"
             for i in range(1, min(len(stages), 8))
             if isinstance(stages[i], int) and stages[i] != 0]
    return "/".join(parts)


class Pair:
    """One matchup+seed+roster seen under both arms."""

    def __init__(self, key, a_rec, b_rec):
        self.key = key
        self.a = a_rec
        self.b = b_rec
        self.a_cmds = commands(a_rec)
        self.b_cmds = commands(b_rec)
        self.controlled = 0        # turns of identical state
        self.agreed = 0            # identical-state turns where both chose the same
        self.first_split = None    # (turn_index, a_decision, b_decision, state)

    def analyse(self, moves):
        for i in range(min(len(self.a_cmds), len(self.b_cmds))):
            ea, eb = self.a_cmds[i], self.b_cmds[i]
            if state_key(ea) != state_key(eb):
                break
            self.controlled += 1
            da = decision(by_index(ea).get(MEASURED), moves)
            db = decision(by_index(eb).get(MEASURED), moves)
            if da == db:
                self.agreed += 1
            elif self.first_split is None:
                self.first_split = (i, da, db, ea)
        return self


def collect(paths, arm_a, arm_b, moves):
    records = defaultdict(dict)
    for path in paths:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if not rec.get("commands"):
                continue
            key = (rec.get("team_set", "set_a"), rec["id"], rec["seed"])
            records[key][rec["arm"]] = rec
    pairs = []
    for key, arms in sorted(records.items()):
        if arm_a in arms and arm_b in arms:
            pairs.append(Pair(key, arms[arm_a], arms[arm_b]).analyse(moves))
    return pairs


def show_battle(pair, moves, species):
    """Full side-by-side trajectory of one match."""
    team_set, mid, seed = pair.key
    print(f"\n{'=' * 100}")
    print(f"{mid}  seed={seed}  {team_set}")
    print(f"  A = {pair.a['arm']:20} -> {pair.a['result']:5} in {pair.a['turns']} turns")
    print(f"  B = {pair.b['arm']:20} -> {pair.b['result']:5} in {pair.b['turns']} turns")
    print(f"  identical state for {pair.controlled} turns; "
          f"agreed on {pair.agreed} of them")
    print(f"{'=' * 100}")
    head = (f"{'t':>3} | {'foe':<12} {'hp':>4} {'stages':<14} | "
            f"{'A: mine':<12} {'hp':>4} {'A chose':<22} | "
            f"{'B: mine':<12} {'hp':>4} {'B chose':<22}")
    print(head)
    print("-" * len(head))
    for i in range(max(len(pair.a_cmds), len(pair.b_cmds))):
        ea = pair.a_cmds[i] if i < len(pair.a_cmds) else None
        eb = pair.b_cmds[i] if i < len(pair.b_cmds) else None
        aa = by_index(ea).get(MEASURED) if ea else None
        ab = by_index(eb).get(MEASURED) if eb else None
        fa = by_index(ea).get(OPPONENT) if ea else None
        fb = by_index(eb).get(OPPONENT) if eb else None
        same = ea and eb and state_key(ea) == state_key(eb)
        # Once states differ the two columns describe different battles; show A's foe
        # and flag it, rather than pretending one shared opponent column is valid.
        foe = fa or fb
        mark = " " if same else "*"
        foe_name = species.get((foe or {}).get("species", -1), "-")[:12]
        a_name = species.get((aa or {}).get("species", -1), "-")[:12]
        b_name = species.get((ab or {}).get("species", -1), "-")[:12]
        if not same and fb and fa and fa["species"] != fb["species"]:
            foe_name = f"{foe_name[:5]}/{species.get(fb['species'],'-')[:5]}"
        print(f"{i:>3}{mark}| {foe_name:<12} {hp_str(foe)} {stage_str(foe):<14} | "
              f"{a_name:<12} {hp_str(aa)} {decision(aa, moves):<22} | "
              f"{b_name:<12} {hp_str(ab)} {decision(ab, moves):<22}")
    print("* = states have diverged; the two columns are no longer the same battle.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="+", type=Path)
    parser.add_argument("--arm-a", default="normal_reborn")
    parser.add_argument("--arm-b", default="normal_portable")
    parser.add_argument("--show", help="matchup:seed[:team_set] to print in full")
    parser.add_argument("--arch", help="restrict to a measured-seat archetype")
    parser.add_argument("--limit", type=int, default=0,
                        help="print this many full battles, worst-outcome first")
    args = parser.parse_args()

    moves, species = load_names()
    pairs = collect(args.results, args.arm_a, args.arm_b, moves)
    if not pairs:
        raise SystemExit(f"no battles carried both {args.arm_a} and {args.arm_b} "
                         f"with traces")
    if args.arch:
        pairs = [p for p in pairs if p.b.get("right_test_team") == args.arch]

    if args.show:
        parts = args.show.split(":")
        want_set = parts[2] if len(parts) > 2 else None
        hits = [p for p in pairs
                if p.key[1] == parts[0] and str(p.key[2]) == parts[1]
                and (want_set is None or p.key[0] == want_set)]
        if not hits:
            raise SystemExit(f"no battle matched {args.show}")
        for pair in hits:
            show_battle(pair, moves, species)
        return 0

    print(f"{args.arm_a} (A) vs {args.arm_b} (B), {len(pairs)} paired battles.\n")
    print("Controlled region = leading turns where both battles hold identical state.")
    print("Only there is a choice difference a pure policy difference.\n")

    ctrl = [p.controlled for p in pairs]
    total_ctrl = sum(ctrl)
    total_agree = sum(p.agreed for p in pairs)
    print(f"  controlled turns: {total_ctrl} total, "
          f"median {sorted(ctrl)[len(ctrl)//2]}, max {max(ctrl)}")
    print(f"  agreement inside controlled region: {total_agree}/{total_ctrl} "
          f"= {total_agree/max(1,total_ctrl)*100:.1f}%")
    zero = sum(1 for c in ctrl if c == 0)
    if zero:
        print(f"  {zero} pairs diverged before turn 0 (state differs immediately)")

    # What does each AI do differently at the very first point they disagree?
    print("\nFirst disagreement at an identical state (what each AI picked instead):")
    kinds = Counter()
    for p in pairs:
        if p.first_split:
            _, da, db, _ = p.first_split
            kinds[(da.split(":")[0], db.split(":")[0])] += 1
    print(f"  {'A (' + args.arm_a + ')':<28} {'B (' + args.arm_b + ')':<28} {'n':>4}")
    for (ka, kb), n in kinds.most_common():
        print(f"  {ka:<28} {kb:<28} {n:>4}")
    split_turn = [p.first_split[0] for p in pairs if p.first_split]
    if split_turn:
        print(f"  mean turn of first disagreement: "
              f"{sum(split_turn)/len(split_turn):.2f}")

    # Outcome split: pairs where the fair opponent won and Portable did not are the
    # ones worth reading by hand.
    buckets = Counter((p.a["result"], p.b["result"]) for p in pairs)
    print("\nOutcomes (A result, B result):")
    for (ra, rb), n in buckets.most_common():
        print(f"  A={ra:<5} B={rb:<5} {n:>4}")

    print("\nPer measured-seat archetype:")
    per = defaultdict(lambda: [0, 0, 0, 0])   # a_wins, b_wins, ctrl, agree
    for p in pairs:
        row = per[p.b.get("right_test_team")]
        row[0] += 1 if p.a["result"] == "win" else 0
        row[1] += 1 if p.b["result"] == "win" else 0
        row[2] += p.controlled
        row[3] += p.agreed
    print(f"  {'archetype':<10} {'A wins':>7} {'B wins':>7} {'agree in ctrl':>14}")
    for arch in sorted(per):
        aw, bw, c, ag = per[arch]
        print(f"  {arch:<10} {aw:>7} {bw:>7} "
              f"{ag}/{c} = {ag/max(1,c)*100:5.1f}%")

    if args.limit:
        worst = [p for p in pairs if p.a["result"] == "win" and p.b["result"] != "win"]
        worst.sort(key=lambda p: -p.controlled)
        for pair in worst[:args.limit]:
            show_battle(pair, moves, species)
    return 0


if __name__ == "__main__":
    sys.exit(main())
