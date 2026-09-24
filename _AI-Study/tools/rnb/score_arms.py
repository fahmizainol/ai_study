#!/usr/bin/env python3
"""Score generator arms whose pairings only partly overlap (new teams, new mean BST, so
some bosses change) against each other.

Each battle is scored against the pooled win rate of ALL the listed arms' teams on that
same boss, so an arm that drew easier bosses gets no credit for it; arms are compared on
that boss-adjusted score, with a 95% interval from resampling each arm's teams (a team's
battles are not independent). The first arm is the baseline.

    python3 tools/rnb/score_arms.py rnb_vs_gen_deckoff rnb_vs_gen_theme rnb_vs_gen_tier

compare_runs.py is the battle-for-battle check on the pairings the arms share.
"""
import collections
import os
import random
import sys

from paths import STUDY, read_results

N_BOOT = 4000


def battles(exp):
    last = {}
    for r in read_results(os.path.join(STUDY, "generated", exp, "results.ndjson")):
        if not r["error"] and r["turns"] > 0 and r["winner"]:
            last[r["tag"]] = r
    return [(r["opp"], r["boss"], r["winner"] != "rnb") for r in last.values()]


def main(exps):
    B = {e: battles(e) for e in exps}
    pooled = collections.defaultdict(list)
    for v in B.values():
        for _, boss, won in v:
            pooled[boss].append(won)
    rate = {b: sum(x) / len(x) for b, x in pooled.items()}

    def adj(v):
        return 100 * sum(w - rate[b] for _, b, w in v) / len(v)

    def by_team(v):
        g = collections.defaultdict(list)
        for x in v:
            g[x[0]].append(x)
        return g

    print("%-32s %9s %7s %9s" % ("arm", "wins", "win %", "adjusted"))
    for e, v in B.items():
        w = sum(x[2] for x in v)
        print("%-32s %4d/%-4d %6.1f%% %+8.1f" % (e, w, len(v), 100 * w / len(v), adj(v)))

    random.seed(3)
    base = exps[0]
    print("\ndifference from %s, 95%% interval by resampling teams" % base)
    for e in exps[1:]:
        g1, g2 = by_team(B[base]), by_team(B[e])
        ds = []
        for _ in range(N_BOOT):
            s1 = [x for k in random.choices(list(g1), k=len(g1)) for x in g1[k]]
            s2 = [x for k in random.choices(list(g2), k=len(g2)) for x in g2[k]]
            ds.append(adj(s2) - adj(s1))
        ds.sort()
        print("  %-30s %+5.1f  [%+.1f, %+.1f]  resamples at or below 0: %.2f" % (
            e, adj(B[e]) - adj(B[base]), ds[int(.025 * N_BOOT)], ds[int(.975 * N_BOOT)],
            sum(d <= 0 for d in ds) / N_BOOT))

    print("\nper team: W-L (adjusted)")
    teams = sorted({x[0] for v in B.values() for x in v},
                   key=lambda t: (t.rstrip("0123456789"), int(t[len(t.rstrip("0123456789")):] or 0)))
    for t in teams:
        cells = []
        for v in B.values():
            g = [x for x in v if x[0] == t]
            w = sum(x[2] for x in g)
            cells.append("%2d-%-2d %+4.0f" % (w, len(g) - w, adj(g)) if g else "%12s" % "-")
        print("  %-7s" % t + "   ".join(cells))


if __name__ == "__main__":
    main(sys.argv[1:])
