#!/usr/bin/env python3
"""The tier of what each team fields, and whether it predicts the result against Run & Bun.

Two different tiers, as the generator itself separates them (smogon_corpus.py):
  species tier  SC.tier -- gen 7 Showdown ranking, Realidea's own generation; a mega is
                ranked as its mega forme. Grouped into SC.BAND (Uber OU UU RU NU low).
  set tier      the format a published set was written for (SC.set_tier of the generator's
                `src`); for a real team, the team's own format. Only the committed
                generator teams keep `src` (the fixes arms were written elsewhere).

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/tiers.py
"""
import collections
import os
import sys

import archetypes as A
import composition as C
from paths import STUDY, TOOLS

sys.path.insert(0, TOOLS)
import smogon_corpus as SC  # noqa: E402

G = os.path.join(STUDY, "generated")
BANDS = SC.BANDS + ["?"]


def slot_bands(path):
    out = []
    for b in open(path, encoding="utf-8").read().strip().split("\n\n"):
        sp, _, item = b.splitlines()[0].partition(" @ ")
        e = C.DEX[C.tid(sp)]
        e = C.MEGA.get((C.tid(e.get("baseSpecies", e["name"])), C.tid(item)), e)
        t = SC.tier(e["name"])
        out.append(SC.BAND.get(t, "?") if t != "?" else "?")
    return out


def slot_bst(path):
    """(gen 7 tier, BST) per slot, a mega as its mega forme."""
    out = []
    for b in open(path, encoding="utf-8").read().strip().split("\n\n"):
        sp, _, item = b.splitlines()[0].partition(" @ ")
        e = C.DEX[C.tid(sp)]
        e = C.MEGA.get((C.tid(e.get("baseSpecies", e["name"])), C.tid(item)), e)
        out.append((SC.tier(e["name"]), sum(e["baseStats"].values())))
    return out


def top(bands):
    """Uber + OU slots: the species Smogon's own top tier would field."""
    n = sum(b in ("Uber", "OU") for b in bands)
    return "0-1" if n <= 1 else "2-3" if n <= 3 else "4-6"


def gen_sources():
    """{(run group, team name): [set tier of each slot]} for the committed generator teams."""
    import make_gen_battles as MG
    out = {}
    for trainers, grp in ((False, "gyms"), (True, "non-gym")):
        for name, t in MG.fights(trainers):
            out[grp, name] = [SC.set_tier((m.get("src") or "none/").split("/")[0]) or "none"
                              for m in t["mons"]]
    return out


def main():
    rate = A.boss_rate()
    rows, per_team = [], {}
    for label, exp, side in A.RUNS:
        if not os.path.exists(os.path.join(G, exp, "results.ndjson")):
            continue
        for r, p in A.battles(exp, side):
            if (label, r["opp"]) not in per_team:
                per_team[label, r["opp"]] = slot_bands(p)
            rows.append((label, per_team[label, r["opp"]], r["winner"] != "rnb", rate[r["boss"]]))

    groups = {"all generator": [l for l, _, s in A.RUNS if s == "gen"],
              "all real": [l for l, _, s in A.RUNS if s == "smogon"]}
    labels = [l for l, _, _ in A.RUNS] + list(groups)

    print("## Species tier per slot (gen 7 Showdown tier; share of slots, one count per team)")
    print("%-24s" % "" + "".join("%7s" % b for b in BANDS) + "   Uber+OU per team")
    for label in labels:
        src = groups.get(label, [label])
        T = [v for (l, _), v in per_team.items() if l in src]
        if not T:
            continue
        c = collections.Counter(b for t in T for b in t)
        n = sum(c.values())
        print("%-24s" % label + "".join("%6.0f%%" % (100 * c[b] / n) for b in BANDS)
              + "   %.1f" % (sum(b in ("Uber", "OU") for t in T for b in t) / len(T)))

    print("\n## By Uber+OU slots per team  (wins/battles, win%, points above what the bosses gave gen 9 teams)")
    keys = ["0-1", "2-3", "4-6"]
    print("%-24s" % "" + "".join("%18s" % k for k in keys) + "   teams")
    for label in labels:
        src = groups.get(label, [label])
        rs = [x for x in rows if x[0] in src]
        if not rs:
            continue
        cells = []
        for k in keys:
            g = [x for x in rs if top(x[1]) == k]
            if not g:
                cells.append("%18s" % "-")
                continue
            w, n = sum(x[2] for x in g), len(g)
            cells.append("%3d/%-3d %3.0f%% %+4.0f" % (w, n, 100 * w / n, 100 * (w - sum(x[3] for x in g)) / n))
        cnt = collections.Counter(top(v) for (l, _), v in per_team.items() if l in src)
        print("%-24s" % label + "".join(cells) + "   " + " ".join(str(cnt[k]) for k in keys))

    print("\n## At matched BST: species tier by the slot's own BST (real gen 7 v generator committed + fixes off)")
    keep = set(os.listdir(os.path.join(G, "rnb_vs_gen7_collage", "teams", "smogon")))   # the pilotable 78
    pools = {"real gen 7": [("rnb_vs_gen7", "smogon")],
             "generator": [("rnb_vs_gen", "gen"), ("rnb_vs_gen_trainers", "gen"),
                           ("rnb_vs_gen_off", "gen"), ("rnb_vs_gen_trainers_off", "gen")]}
    for name, src in pools.items():
        S = []
        for exp, side in src:
            d = os.path.join(G, exp, "teams", side)
            for f in os.listdir(d):
                if side == "gen" or f in keep:
                    S += slot_bst(os.path.join(d, f))
        raw = collections.Counter(t for t, _ in S)
        print("%s, %d slots; below NU: %s" % (name, len(S), ", ".join(
            "%s %d" % (k, raw[k]) for k in ("PUBL", "PU", "ZUBL", "ZU", "NFE", "LC"))))
        for lo, hi in ((0, 450), (450, 500), (500, 550), (550, 999)):
            g = [SC.BAND.get(t, "?") for t, b in S if lo <= b < hi]
            print("  BST %3d-%-3s %4d slots  Uber+OU %3.0f%%  UU-NU %3.0f%%  PU and below %3.0f%%" % (
                lo, hi if hi < 999 else "", len(g), 100 * sum(x in ("Uber", "OU") for x in g) / len(g),
                100 * sum(x in ("UU", "RU", "NU") for x in g) / len(g), 100 * sum(x == "low" for x in g) / len(g)))

    print("\n## Committed generator sets: which format each set was written for, by species band")
    S = gen_sources()
    cross = collections.Counter()
    for (grp, name), fmts in S.items():
        exp = "rnb_vs_gen" if grp == "gyms" else "rnb_vs_gen_trainers"
        bands = slot_bands(os.path.join(G, exp, "teams", "gen", name))
        for b, f in zip(bands, fmts):
            cross[b, f] += 1
    fmts = [f for f, _ in collections.Counter(f for _, f in cross.elements()).most_common()]
    print("%-8s" % "" + "".join("%10s" % f[:9] for f in fmts))
    for b in BANDS:
        if any(cross[b, f] for f in fmts):
            print("%-8s" % b + "".join("%10d" % cross[b, f] for f in fmts))


if __name__ == "__main__":
    main()
