#!/usr/bin/env python3
"""Read out a Realidea tier-suite run: win rate per arm, per set, with the caveats.

Three things about this engine's results do not survive a naive tally, and all three
are visible only because the harness now records them:

  Errors are not losses. Realidea's own AI raises in two places these rosters reach --
  a ZeroDivisionError in pbRoughDamage and a hasWorkingAbility call on a party
  Pokemon in pbEnemyShouldWithdrawEx? -- and the battle ends with no verdict. Those
  records are excluded from the rate and reported separately, because counting them
  as losses would score an engine crash as a policy failure.

  Timeouts are not draws. The 100-round cap computes a verdict on remaining count then
  HP total, and pbStartBattle discards it (PokeBattle_Battle.rb:2753). The gauntlet
  stashes it, so `timeout_result` says who was ahead. Reported both ways: the strict
  rate treats a timeout as a draw, the resolved rate uses the stashed verdict.

  Sets are not pooled by default. gen6ou_a and gen6ou_b are disjoint draws answering
  "does this hold for other teams", so they are shown apart; --pooled adds the total.

Usage:
    python3 summarize_tier.py generated/realidea_tier_gen6ou_*.ndjson
    python3 summarize_tier.py ... --pooled
"""

import argparse
import json
from collections import defaultdict
from pathlib import Path


def load(paths):
    rows = []
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if line.strip():
                rows.append(json.loads(line))
    return rows


def tally(rows):
    """-> {mode: counts}. `resolved` re-reads timeouts through their stashed verdict."""
    out = defaultdict(lambda: dict.fromkeys(
        ("win", "loss", "draw", "error", "timed_out",
         "rwin", "rloss", "rdraw", "turns", "n"), 0))
    for row in rows:
        bucket = out[row["mode"]]
        result = row.get("result")
        bucket[result] = bucket.get(result, 0) + 1
        bucket["turns"] += int(row.get("turns") or 0)
        bucket["n"] += 1
        if result == "error":
            continue
        if row.get("timed_out"):
            bucket["timed_out"] += 1
            resolved = row.get("timeout_result", "draw")
        else:
            resolved = result
        bucket["r" + resolved] += 1
    return out


def rate(win, loss, draw):
    total = win + loss + draw
    return 100.0 * win / total if total else 0.0


def report(label, rows):
    counts = tally(rows)
    print(f"\n{label}  ({len(rows)} records)")
    print(f"  {'arm':10} {'W':>3} {'L':>3} {'D':>3} {'err':>4} {'t/o':>4} "
          f"{'strict':>8} {'resolved':>9} {'turns':>7}")
    for mode in sorted(counts):
        c = counts[mode]
        strict = rate(c["win"], c["loss"], c["draw"])
        resolved = rate(c["rwin"], c["rloss"], c["rdraw"])
        mean_turns = c["turns"] / c["n"] if c["n"] else 0
        print(f"  {mode:10} {c['win']:3} {c['loss']:3} {c['draw']:3} {c['error']:4} "
              f"{c['timed_out']:4} {strict:7.1f}% {resolved:8.1f}% {mean_turns:7.1f}")
    if "stock" in counts and "portable" in counts:
        s, p = counts["stock"], counts["portable"]
        gap = rate(p["win"], p["loss"], p["draw"]) - rate(s["win"], s["loss"], s["draw"])
        rgap = (rate(p["rwin"], p["rloss"], p["rdraw"])
                - rate(s["rwin"], s["rloss"], s["rdraw"]))
        print(f"  {'portable -':10} {'':16} {gap:+7.1f}pt {rgap:+8.1f}pt")
    errors = [r for r in rows if r.get("result") == "error"]
    if errors:
        seen = defaultdict(list)
        for row in errors:
            seen[row["error"]].append(row["mode"])
        print("  engine errors (excluded above):")
        for message, modes in sorted(seen.items()):
            tags = ", ".join(f"{modes.count(m)}x {m}" for m in sorted(set(modes)))
            print(f"    {tags:24} {message}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+")
    parser.add_argument("--pooled", action="store_true",
                        help="also print every set together (they are disjoint draws;"
                             " pooling answers a different question)")
    args = parser.parse_args()

    everything = []
    for path in sorted(args.files):
        rows = load([path])
        stamps = {r.get("portable_version") for r in rows}
        megas = {r.get("mega") for r in rows}
        sets = {r.get("teams") for r in rows}
        report(f"{Path(path).name}  portable={'/'.join(sorted(str(s) for s in stamps))}"
               f"  mega={'/'.join(sorted(str(m) for m in megas))}"
               f"  teams={'/'.join(sorted(str(s) for s in sets))}", rows)
        everything += rows
    if args.pooled and len(args.files) > 1:
        report("pooled", everything)


if __name__ == "__main__":
    main()
