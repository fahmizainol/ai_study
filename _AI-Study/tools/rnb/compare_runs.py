#!/usr/bin/env python3
"""Two experiments battle for battle: same boss, same opponent team name, same round.

For runs built from the same pairings with the teams changed (intact v collage, intact v
injected, generator sets v published sets). Tags cannot be compared directly -- a run
that drops a pairing renumbers the rest -- so battles are matched on (boss, opp, round).

    python tools/rnb/compare_runs.py rnb_vs_gen7 rnb_vs_gen7_injected
"""
import math
import os
import sys

from paths import STUDY, read_results


def clean(exp):
    out = {}
    for r in read_results(os.path.join(STUDY, "generated", exp, "results.ndjson")):
        if not r["error"] and r["turns"] > 0 and r["winner"]:
            out[r["boss"], r["opp"], r["tag"].split("x")[1]] = r["winner"] != "rnb"
    return out


def main(a_exp, b_exp):
    a, b = clean(a_exp), clean(b_exp)
    keys = a.keys() & b.keys()
    if not keys:
        sys.exit("no battles in common")
    wa, wb = sum(a[k] for k in keys), sum(b[k] for k in keys)
    lost = sum(a[k] and not b[k] for k in keys)
    gained = sum(b[k] and not a[k] for k in keys)
    n = lost + gained
    p = min(1.0, 2 * sum(math.comb(n, i) for i in range(max(lost, gained), n + 1)) / 2 ** n) if n else 1.0
    print("matched battles %d: %s won %d (%.1f%%), %s won %d (%.1f%%)"
          % (len(keys), a_exp, wa, 100 * wa / len(keys), b_exp, wb, 100 * wb / len(keys)))
    print("%s lost %d that %s won, won %d it lost; sign test p = %.4f" % (b_exp, lost, a_exp, gained, p))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
