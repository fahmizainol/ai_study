#!/usr/bin/env python3
"""Summarise generated/rnb_vs_gen/results.ndjson: the boss generator's gyms vs Run & Bun.

Pooled and per-gym records, then the paired comparison with the Smogon run
(generated/rnb/results.ndjson): each battle a Run & Bun boss played here is scored
against that SAME boss's win rate versus Smogon teams. If the gyms were exactly as
strong as Smogon teams, Run & Bun would win the sum of those rates; fewer wins means
the gyms are stronger. This removes the "different mix of bosses" confound.

    python3 tools/rnb/summarize_gen_battles.py [--uncontended]

--uncontended drops the battles listed in contended.txt: played while another job held
the CPU, so both bots searched less than in the Smogon run.
"""
import collections
import json
import math
import os
import sys

from paths import RNB, STUDY

GEN = os.path.join(STUDY, "generated", "rnb_vs_gen")


def clean(path):
    """Latest clean attempt per tag, as run_battles.py defines clean."""
    latest = {}
    with open(path) as fh:
        for line in fh:
            r = json.loads(line)
            if not r["error"] and r["turns"] > 0 and r["winner"]:
                latest[r["tag"]] = r
    return list(latest.values())


def contended():
    """Tags played while another job starved the CPU (contended.txt); see main()."""
    path = os.path.join(GEN, "contended.txt")
    if not os.path.exists(path):
        return set()
    with open(path) as fh:
        return {ln.strip() for ln in fh if ln.strip() and not ln.startswith("#")}


def main():
    V = clean(os.path.join(GEN, "results.ndjson"))
    if "--uncontended" in sys.argv:
        skip = contended()
        V = [r for r in V if r["tag"] not in skip]
        print("excluding %d battles played under CPU contention" % len(skip))
    n, gen_w = len(V), sum(r["winner"] != "rnb" for r in V)
    p = gen_w / n
    se = math.sqrt(p * (1 - p) / n)
    print("generator gyms win %d/%d = %.1f%% (95%% CI %.0f-%.0f%%)"
          % (gen_w, n, 100 * p, 100 * (p - 1.96 * se), 100 * (p + 1.96 * se)))

    smog = collections.defaultdict(list)
    for r in clean(os.path.join(RNB, "results.ndjson")):
        smog[r["boss"]].append(r["winner"] == "rnb")
    rate = {b: sum(x) / len(x) for b, x in smog.items()}

    print("\n%-6s%5s %5s   opponents (Run & Bun boss: W-L for the gym)" % ("gym", "BST", "W-L"))
    by = collections.defaultdict(list)
    for r in V:
        by[r["opp"]].append(r)
    for g in sorted(by, key=lambda g: int(g[3:])):
        rs = by[g]
        w = sum(r["winner"] != "rnb" for r in rs)
        per = collections.Counter()
        for r in rs:
            per[r["boss"], r["winner"] != "rnb"] += 1
        opps = ", ".join("%s %d-%d" % (b.rsplit("_", 1)[0], per[b, True], per[b, False])
                         for b in dict.fromkeys(r["boss"] for r in rs))
        print("%-6s%5d %2d-%-2d   %s" % (g, rs[0]["opp_bst"], w, len(rs) - w, opps))

    # paired: expected Run & Bun wins if every gym were a typical Smogon team for that boss
    exp = sum(rate[r["boss"]] for r in V)
    var = sum(rate[r["boss"]] * (1 - rate[r["boss"]]) for r in V)
    obs = n - gen_w
    z = (obs - exp) / math.sqrt(var)
    pz = math.erfc(abs(z) / math.sqrt(2))
    print("\npaired with the Smogon run (same Run & Bun bosses):")
    print("  Run & Bun wins vs gyms: %d/%d; expected vs Smogon-strength teams: %.1f" % (obs, n, exp))
    print("  => gyms win %.1f%% where Smogon teams would win %.1f%%  (z = %+.2f, two-sided p = %.3f)"
          % (100 * gen_w / n, 100 * (n - exp) / n, z, pz))


if __name__ == "__main__":
    main()
