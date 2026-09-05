#!/usr/bin/env python3
"""Paired win/loss comparison of two runs of the same schedule.

Every arm plays a fixed set of (roster, matchup, seed) battles, so two runs pair
exactly on that key and McNemar's test applies — the right test here, because the
unpaired two-proportion test throws away the pairing and badly understates a change
that only touches a few dozen decisions.

Usage:
    python3 compare_versions.py --before 'generated/reborn_6v6_v031_set_*.ndjson' \
                                --after  'generated/reborn_6v6_v032_set_*.ndjson'
    ... --arm normal_portable --label-before 0.3.1 --label-after 0.3.2
"""

import argparse
import glob
import json
import math
import sys
from collections import defaultdict


def load(pattern, arm):
    out = {}
    paths = glob.glob(pattern)
    if not paths:
        raise SystemExit(f"no files matched {pattern!r}")
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                if rec.get("arm") != arm:
                    continue
                key = (rec.get("team_set"), rec["id"], rec["seed"])
                out[key] = (rec["result"], rec.get("right_test_team"),
                            rec.get("team_set"))
    if not out:
        raise SystemExit(f"no {arm!r} records in {pattern!r}")
    return out


def mcnemar(gained, lost):
    """Continuity-corrected McNemar chi-square, and the two-sided normal p."""
    if gained + lost == 0:
        return 0.0, 0.0, 1.0
    chi = (abs(gained - lost) - 1) ** 2 / (gained + lost)
    z = math.sqrt(chi)
    p = 2 * (1 - 0.5 * (1 + math.erf(z / math.sqrt(2))))
    return chi, z, p


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--arm", default="normal_portable")
    parser.add_argument("--label-before", default="before")
    parser.add_argument("--label-after", default="after")
    args = parser.parse_args()

    before = load(args.before, args.arm)
    after = load(args.after, args.arm)
    keys = sorted(set(before) & set(after))
    if not keys:
        raise SystemExit("the two runs share no battles")
    missing = len(set(before) ^ set(after))
    if missing:
        print(f"note: {missing} battles appear in only one run and are excluded\n")

    b_wins = sum(1 for k in keys if before[k][0] == "win")
    a_wins = sum(1 for k in keys if after[k][0] == "win")
    gained = sum(1 for k in keys if before[k][0] != "win" and after[k][0] == "win")
    lost = sum(1 for k in keys if before[k][0] == "win" and after[k][0] != "win")
    chi, z, p = mcnemar(gained, lost)

    n = len(keys)
    print(f"{args.arm} over {n} paired battles")
    print(f"  {args.label_before:<10} {b_wins:>4}/{n}  = {b_wins/n*100:5.1f}%")
    print(f"  {args.label_after:<10} {a_wins:>4}/{n}  = {a_wins/n*100:5.1f}%"
          f"   ({a_wins-b_wins:+d})")
    print(f"  gained {gained}, lost {lost}, net {gained-lost:+d}")
    print(f"  McNemar chi2={chi:.2f}  z={z:.2f}  two-sided p={p:.3f}"
          f"{'' if p < 0.05 else '   (not significant)'}")

    for field, title in ((1, "archetype"), (2, "roster")):
        rows = defaultdict(lambda: [0, 0, 0])
        for k in keys:
            row = rows[before[k][field]]
            row[0] += 1
            row[1] += 1 if before[k][0] == "win" else 0
            row[2] += 1 if after[k][0] == "win" else 0
        print(f"\n  {title:<10} {'n':>4} {args.label_before:>8} {args.label_after:>8}"
              f" {'delta':>6}")
        for name in sorted(rows):
            total, bw, aw = rows[name]
            print(f"  {str(name):<10} {total:>4} {bw:>8} {aw:>8} {aw-bw:>+6d}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
