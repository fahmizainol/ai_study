#!/usr/bin/env python3
"""Where two shadow runs of the same battles answer differently, turn by turn.

A shadow run has the stock AI play and the portable planner answer every position
without registering, so two shadow runs under different config keys (say foe_oracle
off and on) see the IDENTICAL sequence of boards and differ only in what the planner
would have clicked. That makes every turn a controlled comparison of the two configs
-- the thing a pair of live arms cannot give, because they diverge after a turn.

The check that the boards were identical is enforced, not assumed: both runs must
record the same host (stock) choice at every paired turn and the same verdict and
turn count per battle. A mismatch voids the comparison.

Usage:
    python3 shadow_pair_diff.py A.ndjson B.ndjson [--label-a off --label-b oracle]
    python3 shadow_pair_diff.py A.ndjson B.ndjson --examples 30
"""

import argparse
import json
import sys
from collections import Counter


def load(path):
    out = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if rec.get("mode") != "shadow":
                continue
            out[(rec.get("teams"), rec.get("id"), rec.get("seed"))] = rec
    return out


def label(choice):
    if not choice:
        return "-"
    if choice.get("type") == "switch":
        return "switch:%s" % choice.get("slot")
    return "%s" % (choice.get("move_id") or choice.get("move") or choice.get("type"))


# In a single battle the sole foe is written as -1 by the engine's own choice record
# and as None by the portable planner, which names a target only when it has one to
# name. Comparing them raw made every stock-vs-portable move comparison false -- 441
# of 933 turns on the 0.7.6 shadow pair had the identical move_id scored as a
# disagreement -- so the "which side matched the host" table could only ever credit a
# switch. The two spellings are one target.
def target_of(choice):
    target = choice.get("target")
    return None if target is None or target == -1 else target


def same(a, b):
    if a is None or b is None:
        return None
    if a.get("type") != b.get("type"):
        return False
    if a.get("type") == "switch":
        return a.get("slot") == b.get("slot")
    return a.get("move_id") == b.get("move_id") and target_of(a) == target_of(b)


def top(cands, n=3):
    out = []
    for c in (cands or [])[:n]:
        score = float(c.get("score") or 0)
        # Two planners on two scales: the maximin scores a board in HP points (tens to
        # hundreds), the tree scores it as a probability in 0..1. Printing both at %.0f
        # rounded every MCTS row to "1" or "0" and hid the whole ordering.
        out.append("%s=%s" % (
            "switch:%s(%s)" % (c.get("slot"), c.get("species")) if c.get("type") == "switch"
            else c.get("move_id"),
            "%.3f" % score if abs(score) < 10 else "%.0f" % score))
    return " ".join(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("a")
    parser.add_argument("b")
    parser.add_argument("--label-a", default="A")
    parser.add_argument("--label-b", default="B")
    parser.add_argument("--examples", type=int, default=12)
    args = parser.parse_args()

    a_runs, b_runs = load(args.a), load(args.b)
    shared = sorted(set(a_runs) & set(b_runs), key=lambda k: tuple(str(p) for p in k))
    print("shadow battles : %s=%d %s=%d paired=%d" % (
        args.label_a, len(a_runs), args.label_b, len(b_runs), len(shared)))
    if not shared:
        sys.exit("nothing paired")

    board_bad = []
    compared = differ = unscored = 0
    kinds = Counter()
    vs_stock = Counter()
    examples = []
    for key in shared:
        ra, rb = a_runs[key], b_runs[key]
        if (ra.get("decision"), ra.get("turns")) != (rb.get("decision"), rb.get("turns")):
            board_bad.append((key, "verdict"))
            continue
        ta, tb = ra.get("shadow") or [], rb.get("shadow") or []
        if len(ta) != len(tb):
            board_bad.append((key, "length %d vs %d" % (len(ta), len(tb))))
            continue
        for ea, eb in zip(ta, tb):
            if (ea.get("turn"), ea.get("actor")) != (eb.get("turn"), eb.get("actor")):
                board_bad.append((key, "turn order"))
                break
            if same(ea.get("stock"), eb.get("stock")) is False:
                board_bad.append((key, "host choice differs at turn %s" % ea.get("turn")))
                break
            pa, pb = ea.get("portable"), eb.get("portable")
            verdict = same(pa, pb)
            if verdict is None:
                unscored += 1
                continue
            compared += 1
            if verdict:
                continue
            differ += 1
            kinds["%s -> %s" % (pa.get("type"), pb.get("type"))] += 1
            stock = ea.get("stock")
            sa, sb = same(pa, stock), same(pb, stock)
            if sa and not sb:
                vs_stock[args.label_a] += 1
            elif sb and not sa:
                vs_stock[args.label_b] += 1
            else:
                vs_stock["neither"] += 1
            if len(examples) < args.examples:
                examples.append((key, ea, eb))

    if board_bad:
        print("\nBOARDS WERE NOT IDENTICAL -- %d battles:" % len(board_bad))
        for key, why in board_bad[:20]:
            print("  %s: %s" % (key, why))
        print("Observation perturbed one run, or the runs are not the same battles. "
              "The figures below cover only the battles that paired cleanly.")

    print("\nturns compared : %d (%d unscorable)" % (compared, unscored))
    if compared:
        print("same answer    : %d (%.1f%%)" % (compared - differ,
                                              (compared - differ) * 100.0 / compared))
        print("different      : %d (%.1f%%)" % (differ, differ * 100.0 / compared))
    if kinds:
        print("\nby kind (%s -> %s):" % (args.label_a, args.label_b))
        for name, count in kinds.most_common():
            print("  %-20s %4d" % (name, count))
    if vs_stock:
        print("\nof the different turns, which side matched the stock host's own click:")
        for name, count in vs_stock.most_common():
            print("  %-10s %4d" % (name, count))
    if examples:
        print("\nexamples:")
        for key, ea, eb in examples:
            view = eb.get("view") or {}
            foe = (view.get("targets") or [{}])[0]
            pf = view.get("predicted_foe") or {}
            declared = ", ".join("%s" % (v.get("move_id") or v.get("type"))
                                 for v in pf.values()) or "-"
            print("  %s %s t%s %s@%s%% vs %s@%s%% | foe declared: %s (hit %s, worst %s)" % (
                key[1], key[2], ea.get("turn"), view.get("species"), view.get("hp_pct"),
                foe.get("species"), foe.get("hp_pct"), declared,
                view.get("predicted_incoming_damage_pct"), view.get("incoming_damage_pct")))
            print("      %s: %-18s %s" % (args.label_a, label(ea.get("portable")),
                                         top(ea.get("candidates"))))
            print("      %s: %-18s %s" % (args.label_b, label(eb.get("portable")),
                                         top(eb.get("candidates"))))
            print("      stock clicked: %s" % label(ea.get("stock")))
    return 1 if board_bad else 0


if __name__ == "__main__":
    sys.exit(main())
