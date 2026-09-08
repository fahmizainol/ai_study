#!/usr/bin/env python3
"""Does a control run reproduce its predecessor battle-for-battle?

Every version's gate is the same: with the new keys off, the build must play every
(roster, matchup, seed, mode) battle to the same verdict in the same number of turns as
the version before it, and where both runs carry a decision trace, the same decision at
every turn. That equality is what makes any NEW number from the version mean anything
-- a control that drifts has changed something it was not supposed to.

Two files, possibly with different coverage: the predecessor's full result set has no
traces and its traced subset has few seeds. Pair on the record key and compare what
both sides carry.

Usage:
    python3 control_check.py --before generated/realidea_tier_gen5ru_a_0_6_5.ndjson \
        --before generated/realidea_tiertrace_gen5ru_a_0_6_5.ndjson \
        --after  generated/realidea_tier_gen5ru_a_0_6_6_control.ndjson
"""

import argparse
import json
import sys


def load(paths):
    out = {}
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                key = (rec.get("teams"), rec.get("id"), rec.get("seed"), rec.get("mode"))
                prior = out.get(key)
                # A traced record outranks a compact one for the same battle.
                if prior is None or (rec.get("trace") and not prior.get("trace")):
                    out[key] = rec
    return out


def decision_key(entry):
    if entry.get("type") == "switch":
        return ("switch", entry.get("slot"), round(float(entry.get("score") or 0), 3))
    return ("move", entry.get("move_id"), entry.get("target"),
            round(float(entry.get("score") or 0), 3))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", action="append", required=True)
    parser.add_argument("--after", action="append", required=True)
    parser.add_argument("--examples", type=int, default=10)
    args = parser.parse_args()

    before = load(args.before)
    after = load(args.after)
    shared = sorted(set(before) & set(after), key=lambda k: tuple(str(p) for p in k))
    print("before records : %d" % len(before))
    print("after records  : %d" % len(after))
    print("paired         : %d" % len(shared))
    if not shared:
        sys.exit("nothing to compare")

    outcome_bad = []
    trace_pairs = 0
    trace_bad = []
    decisions = 0
    for key in shared:
        b, a = before[key], after[key]
        if (b.get("result"), b.get("turns"), b.get("decision")) != \
           (a.get("result"), a.get("turns"), a.get("decision")):
            outcome_bad.append((key, b, a))
        if b.get("trace") is None or a.get("trace") is None:
            continue
        trace_pairs += 1
        bt, at = b["trace"], a["trace"]
        for i in range(max(len(bt), len(at))):
            decisions += 1
            x = decision_key(bt[i]) if i < len(bt) else None
            y = decision_key(at[i]) if i < len(at) else None
            if x != y:
                trace_bad.append((key, i, bt[i] if i < len(bt) else None,
                                  at[i] if i < len(at) else None))
                break

    print("outcomes       : %d/%d identical (result, turns, decision)" %
          (len(shared) - len(outcome_bad), len(shared)))
    print("traced pairs   : %d, %d decisions compared, %d battles diverge" %
          (trace_pairs, decisions, len(trace_bad)))
    for key, b, a in outcome_bad[:args.examples]:
        print("  OUTCOME %s: before %s/%s turns, after %s/%s turns" % (
            key, b.get("result"), b.get("turns"), a.get("result"), a.get("turns")))
    for key, i, x, y in trace_bad[:args.examples]:
        print("  DECISION %s at index %d turn %s: before %s, after %s" % (
            key, i, (x or y or {}).get("turn"),
            decision_key(x) if x else None, decision_key(y) if y else None))
    ok = not outcome_bad and not trace_bad
    print("\nCONTROL %s" % ("REPRODUCES" if ok else "DRIFTED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
