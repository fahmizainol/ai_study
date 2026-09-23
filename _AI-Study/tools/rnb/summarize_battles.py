#!/usr/bin/env python3
"""Summarise generated/rnb/results.ndjson -- the table and correlations in RNB-STUDY.md §5.

A pairing's result is its latest clean attempt (run_battles.py's definition). Tate and
Liza are excluded everywhere: the sheet lists them as two 4-mon [Boss] entries, but in the
game they are one double battle, so as singles they played 4-v-6 and measure nothing.

The per-boss metrics are the ones team_synergy.py reports (coverage profile, role counts),
correlated with each boss's win rate to ask whether any of them predicts it.

    python3 tools/rnb/summarize_battles.py
"""
import collections
import json
import math
import random
import statistics as st

import team_synergy as SY
from paths import out, read_results

EXCLUDED = ("Leader_Tate", "Leader_Liza")
METRICS = ["bst", "cap", "blind", "stacked", "holes", "reach",
           "setup", "recovery", "hazards", "priority", "pivot"]


def clean_results():
    latest = {}
    for r in read_results(out("results.ndjson")):
        if r["boss"].startswith(EXCLUDED):
            continue
        if not r["error"] and r["turns"] > 0 and r["winner"]:
            latest[r["tag"]] = r
    return list(latest.values())


def pearson(x, y):
    mx, my = st.mean(x), st.mean(y)
    sx = math.sqrt(sum((a - mx) ** 2 for a in x))
    sy = math.sqrt(sum((b - my) ** 2 for b in y))
    return sum((a - mx) * (b - my) for a, b in zip(x, y)) / (sx * sy) if sx and sy else float("nan")


def binom_tail(k, n, p, upper=True):
    """P(X >= k) (or <= k) for X ~ Binomial(n, p): how surprising one boss's record is."""
    ks = range(k, n + 1) if upper else range(0, k + 1)
    return sum(math.comb(n, i) * p ** i * (1 - p) ** (n - i) for i in ks)


def boss_metrics(pairs):
    SP, CH, MV, _ = SY.load_dex()
    teams = SY.rnb_teams(SP, MV)
    pop = SY.bodies([t for t in teams if t["mons"]], key=lambda t: (t["gen"], t["format"]))
    meta = {}
    for p in pairs:
        if p["boss"] in meta or p["boss"].startswith(EXCLUDED):
            continue
        # by trainer index (the slug's suffix), NOT by name: two Vitos and two Maxies share
        # a name, and a name lookup silently scores one fight with the other's team
        t = teams[int(p["boss"].rsplit("_", 1)[1])]
        assert t["name"] == p["boss_name"], (t["name"], p["boss_name"])
        prof = SY.AC.profile(t, CH, MV, pop)
        rc = SY.ts.role_counts(t["mons"])
        meta[p["boss"]] = {"bst": p["boss_bst"], "cap": p["cap"], **{k: prof[k] for k in
                           ("blind", "stacked", "holes", "reach")},
                           **{k: rc[k] for k in ("setup", "recovery", "hazards", "priority", "pivot")}}
    return meta


def main():
    with open(out("pairs.json")) as fh:
        pairs = json.load(fh)
    V = clean_results()
    n, w = len(V), sum(r["winner"] == "rnb" for r in V)
    p = w / n
    se = math.sqrt(p * (1 - p) / n)
    print("Run & Bun wins %d/%d = %.1f%% (95%% CI %.0f-%.0f%%)" % (w, n, 100 * p, 100 * (p - 1.96 * se),
                                                               100 * (p + 1.96 * se)))
    for label, test in (("National Dex", lambda r: r["opp_fmt"] == "gen9nationaldex"),
                        ("Ubers/AG", lambda r: r["opp_fmt"] != "gen9nationaldex")):
        L = [r for r in V if test(r)]
        print("  vs %-13s %d/%d" % (label, sum(r["winner"] == "rnb" for r in L), len(L)))
    for side in ("rnb", "smogon"):
        print("  mean turns when %s wins: %.0f" % (side, st.mean(r["turns"] for r in V if r["winner"] == side)))

    meta = boss_metrics(pairs)
    by = collections.defaultdict(list)
    for r in V:
        by[r["boss"]].append(r)
    for b, rs in by.items():
        meta[b]["n"] = len(rs)
        meta[b]["wins"] = sum(r["winner"] == "rnb" for r in rs)
        meta[b]["win"] = meta[b]["wins"] / len(rs)

    print("\n%-38s%4s%5s %6s %5s %9s" % ("boss", "cap", "BST", "W-L", "win%", "P(luck)"))
    order = []
    for pr in pairs:
        if pr["boss"] not in order and not pr["boss"].startswith(EXCLUDED):
            order.append(pr["boss"])
    for b in order:
        m = meta[b]
        tail = min(binom_tail(m["wins"], m["n"], p), binom_tail(m["wins"], m["n"], p, upper=False))
        print("%-38s%4d%5d %3d-%-2d %4.0f%% %9.3f" % (b[:38], m["cap"], m["bst"], m["wins"],
                                                     m["n"] - m["wins"], 100 * m["win"], tail))

    ks = list(meta)
    print("\ncorrelation of boss win rate with each metric (n = %d bosses):" % len(ks))
    wins = [meta[k]["win"] for k in ks]
    for metric in METRICS:
        print("  %-9s r = %+.2f" % (metric, pearson([meta[k][metric] for k in ks], wins)))
    # What |r| does pure binomial noise produce with these sample sizes?
    rng = random.Random(0)
    noise = []
    for _ in range(2000):
        fake = [sum(rng.random() < p for _ in range(meta[k]["n"])) / meta[k]["n"] for k in ks]
        noise.append(abs(pearson([meta[k]["bst"] for k in ks], fake)))
    noise.sort()
    print("  (95th percentile |r| under pure luck: %.2f)" % noise[int(0.95 * len(noise))])


if __name__ == "__main__":
    main()
