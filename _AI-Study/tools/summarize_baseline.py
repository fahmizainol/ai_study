#!/usr/bin/env python3
"""Summarize fixed-Normal baseline runs and compare them across roster sets.

Input: one or more ai_normal_baseline_results.ndjson files (schedule=normal_baseline,
arms=normal_portable,intense_vs_normal). Records are grouped by their team_set field,
so passing several files at once is fine and mixing sets in one file is safe.

Output per roster set, matching the shape of the original
generated/reborn_6v6_normal_baseline_summary.json:
  wins/losses/win_rate for each right-seat AI, by_team breakdown keyed on the
  measured seat's archetype, and paired outcomes over (matchup, seed).

The paired counts are the point of the whole design: because both arms face the same
left Reborn-Normal team on the same seed, every battle has an exact counterpart, so
"Intense won where Portable lost" is a per-battle fact rather than a rate difference.

Usage:
    python3 summarize_baseline.py generated/baseline_set_a.ndjson ...
    python3 summarize_baseline.py --out-dir generated *.ndjson
"""

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]

# arm name in the ndjson -> label used in the summary
ARMS = {"normal_portable": "portable", "intense_vs_normal": "reborn_intense"}


def load(paths):
    by_set = defaultdict(list)
    for path in paths:
        for line_no, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}:{line_no}: bad JSON: {exc}")
            # team_set is absent in runs recorded before roster selection existed;
            # those were all the original fixture.
            by_set[record.get("team_set", "set_a")].append(record)
    return by_set


def summarize(records):
    arms = defaultdict(dict)      # label -> (id, seed) -> record
    unknown = set()
    for record in records:
        label = ARMS.get(record.get("arm"))
        if not label:
            unknown.add(record.get("arm"))
            continue
        arms[label][(record.get("id"), record.get("seed"))] = record

    results, errors = {}, 0
    for label, battles in sorted(arms.items()):
        wins = losses = draws = turns = 0
        by_team = defaultdict(lambda: {"wins": 0, "battles": 0})
        for record in battles.values():
            outcome = record.get("result")
            team = record.get("right_test_team")
            if outcome == "error":
                errors += 1
                continue
            by_team[team]["battles"] += 1
            turns += int(record.get("turns") or 0)
            if outcome == "win":
                wins += 1
                by_team[team]["wins"] += 1
            elif outcome == "loss":
                losses += 1
            else:
                draws += 1
        finished = wins + losses + draws
        results[label] = {
            "wins": wins,
            "losses": losses,
            "win_rate": round(wins / finished, 10) if finished else 0,
            "mean_turns": round(turns / finished, 1) if finished else 0,
            "by_team": {k: dict(v) for k, v in sorted(by_team.items())},
        }

    paired = {"both_won": 0, "portable_lost_intense_won": 0,
              "portable_won_intense_lost": 0, "both_lost": 0}
    portable, intense = arms.get("portable", {}), arms.get("reborn_intense", {})
    shared = sorted(set(portable) & set(intense))
    for key in shared:
        p = portable[key].get("result") == "win"
        i = intense[key].get("result") == "win"
        if p and i:
            paired["both_won"] += 1
        elif i and not p:
            paired["portable_lost_intense_won"] += 1
        elif p and not i:
            paired["portable_won_intense_lost"] += 1
        else:
            paired["both_lost"] += 1

    any_record = records[0] if records else {}
    matchups = sorted({r.get("id") for r in records if r.get("id")})
    seeds = sorted({r.get("seed") for r in records if r.get("seed") is not None})
    summary = {
        "baseline": "reborn_normal_left",
        "measured_seat": any_record.get("measured_seat", "right"),
        "party_size": any_record.get("party_size"),
        "team_set": any_record.get("team_set", "set_a"),
        "matchups": len(matchups),
        "seeds": len(seeds),
        "battles_per_ai": len(portable) or len(intense),
        "errors": errors,
        "results": results,
        "paired_outcomes": paired,
        "paired_battles": len(shared),
    }
    if unknown:
        summary["ignored_arms"] = sorted(a for a in unknown if a)
    return summary


def compare(summaries):
    """Cross-set table. The question is whether the Portable/Intense gap is a
    property of the AIs or of the original 24-mon fixture."""
    rows = []
    for set_name in sorted(summaries):
        s = summaries[set_name]
        p = s["results"].get("portable", {})
        i = s["results"].get("reborn_intense", {})
        n = s["battles_per_ai"] or 1
        rows.append({
            "team_set": set_name,
            "portable_wins": p.get("wins", 0),
            "portable_rate": round(p.get("wins", 0) / n, 4),
            "intense_wins": i.get("wins", 0),
            "intense_rate": round(i.get("wins", 0) / n, 4),
            "gap_points": round((i.get("wins", 0) - p.get("wins", 0)) / n * 100, 1),
            "battles_per_ai": n,
            "paired": s["paired_outcomes"],
        })
    return rows


def print_table(rows, summaries):
    print(f"\n{'set':8} {'portable':>14} {'intense':>14} {'gap':>7}   paired (both/int-only/port-only)")
    print("-" * 78)
    for r in rows:
        n = r["battles_per_ai"]
        pd = r["paired"]
        print(f"{r['team_set']:8} {r['portable_wins']:>4}/{n:<3} "
              f"{r['portable_rate']*100:5.1f}% {r['intense_wins']:>4}/{n:<3} "
              f"{r['intense_rate']*100:5.1f}% {r['gap_points']:>6.1f}   "
              f"{pd['both_won']:>3} / {pd['portable_lost_intense_won']:>3} / "
              f"{pd['portable_won_intense_lost']:>3}")
    print("\nby measured-seat archetype (portable wins / battles):")
    archetypes = sorted({a for s in summaries.values()
                         for a in s["results"].get("portable", {}).get("by_team", {})})
    print(f"{'set':8} " + " ".join(f"{a:>12}" for a in archetypes))
    for set_name in sorted(summaries):
        bt = summaries[set_name]["results"].get("portable", {}).get("by_team", {})
        cells = []
        for a in archetypes:
            v = bt.get(a)
            cells.append(f"{v['wins']:>5}/{v['battles']:<6}" if v else f"{'-':>12}")
        print(f"{set_name:8} " + " ".join(cells))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results", nargs="+", type=Path)
    parser.add_argument("--out-dir", type=Path, default=STUDY / "generated")
    parser.add_argument("--no-write", action="store_true")
    args = parser.parse_args()

    by_set = load(args.results)
    if not by_set:
        raise SystemExit("no records found")

    summaries = {name: summarize(records) for name, records in by_set.items()}
    args.out_dir.mkdir(parents=True, exist_ok=True)
    for name, summary in sorted(summaries.items()):
        if args.no_write:
            continue
        path = args.out_dir / f"reborn_6v6_normal_baseline_{name}.json"
        path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {path}")

    rows = compare(summaries)
    if len(summaries) > 1 and not args.no_write:
        path = args.out_dir / "reborn_6v6_normal_baseline_by_teamset.json"
        path.write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {path}")
    print_table(rows, summaries)
    return 0


if __name__ == "__main__":
    sys.exit(main())
