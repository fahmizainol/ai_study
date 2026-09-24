#!/usr/bin/env python3
"""Team-level traits against the result: the tests behind RNB-STUDY.md §10's archetype,
boss7 and no-wall sections.

Every test here is at TEAM level: a team's battles are not independent, so each team is
one unit, scored by its wins minus what the same bosses gave up to the study's gen 9 teams
(§5), and p-values come from permuting the trait across teams.

  1. archetype / setup tests (permutation: group v rest)
  2. per-team trait averages for boss7, other generator teams, real gen 7, real gen 9, and
     which traits track the result across all generator team-runs (weighted r)
  3. teams with no wall/support set: speed spread, pivots, Scarf, priority; slower v faster
     half; the extreme teams

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/team_profile.py
"""
import random
import re
import statistics as st

import archetypes as A
import composition as C
import tiers as T
from team_shape import ROLE_MOVES

random.seed(7)
N_PERM = 5000
BOOST = re.compile(r"(plate|gem|powder|charcoal|mysticwater|magnet|miracleseed|nevermeltice|blackbelt|"
                   r"poisonbarb|softsand|sharpbeak|twistedspoon|hardstone|spelltag|dragonfang|"
                   r"blackglasses|metalcoat|silkscarf)$")
REAL7, REAL9 = "gen 7 intact", "gen 9 Smogon (§5)"


def feats(path):
    t, raw, bands = C.team(path), A.raw_sets(path), T.slot_bands(path)
    bst, spe, names = [], [], []
    for b, m in zip(open(path, encoding="utf-8").read().strip().split("\n\n"), t):
        sp, _, item = b.splitlines()[0].partition(" @ ")
        e = C.DEX[C.tid(sp)]
        e = C.MEGA.get((C.tid(e.get("baseSpecies", e["name"])), C.tid(item)), e)
        s = e["baseStats"]
        v = s["spe"] * (1.5 if m["item"] == "choicescarf" else 1)   # Scarf as effective speed
        bst.append(sum(s.values()))
        spe.append(v)
        names.append("%s%s %d" % (e["name"].replace("-Mega", "-M"), "(S)" if m["item"] == "choicescarf" else "", v))
    role = lambda r: sum(bool(set(x["moves"]) & ROLE_MOVES[r]) for x in raw)  # noqa: E731
    return {
        "setup users": role("setup"),
        "Choice/LO/Sash": sum(m["item"] in ("choicescarf", "choiceband", "choicespecs", "lifeorb", "focussash") for m in t),
        "type boosters/gems": sum(bool(BOOST.search(m["item"])) for m in t),
        "PU-and-below": sum(b == "low" for b in bands),
        "Uber+OU": sum(b in ("Uber", "OU") for b in bands),
        "unranked (gen 8-9)": sum(b == "?" for b in bands),
        "types unresisted": C.typing(t)[0],
        "walls": sum(C.kind(m) == "wall/support" for m in t),
        "mean BST": st.mean(bst),
        "mean speed": st.mean(spe),
        "fastest": max(spe),
        "slowest": min(spe),
        "at 100+": sum(v >= 100 for v in spe),
        "under 60": sum(v < 60 for v in spe),
        "pivot users": role("pivot"),
        "priority users": role("priority"),
        "Scarf users": sum(m["item"] == "choicescarf" for m in t),
        "arch": A.archetype(t),
        "names": names,
    }


def load():
    """{(run, team): {"f": traits, "w": wins, "n": battles, "e": expected wins}}."""
    rate, out = A.boss_rate(), {}
    for label, exp, side in A.RUNS:
        for r, p in A.battles(exp, side):
            k = (label, r["opp"])
            if k not in out:
                out[k] = {"f": feats(p), "w": 0, "n": 0, "e": 0.0, "gen": side == "gen"}
            out[k]["w"] += r["winner"] != "rnb"
            out[k]["n"] += 1
            out[k]["e"] += rate[r["boss"]]
    return out


def excess(ts):
    return 100 * sum(t["w"] - t["e"] for t in ts) / sum(t["n"] for t in ts)


def perm_group(ts, pred):
    """Excess of the group minus the rest, and its permutation p."""
    def diff(lab):
        a = [t for t, x in zip(ts, lab) if x]
        b = [t for t, x in zip(ts, lab) if not x]
        return excess(a) - excess(b)
    lab = [pred(t["f"]) for t in ts]
    d0, hits = diff(lab), 0
    for _ in range(N_PERM):
        random.shuffle(lab)
        hits += abs(diff(lab)) >= abs(d0)
    return sum(pred(t["f"]) for t in ts), d0, hits / N_PERM


def perm_r(ts, key):
    """Battle-weighted correlation of a trait with per-battle excess, and its permutation p."""
    ys = [(t["w"] - t["e"]) / t["n"] for t in ts]
    w = [t["n"] for t in ts]

    def r(xs):
        mx = sum(a * c for a, c in zip(xs, w)) / sum(w)
        my = sum(b * c for b, c in zip(ys, w)) / sum(w)
        sx = sum(c * (a - mx) ** 2 for a, c in zip(xs, w)) ** .5
        sy = sum(c * (b - my) ** 2 for b, c in zip(ys, w)) ** .5
        return sum(c * (a - mx) * (b - my) for a, b, c in zip(xs, ys, w)) / (sx * sy) if sx and sy else 0.0
    xs = [t["f"][key] for t in ts]
    r0, hits = r(xs), 0
    for _ in range(N_PERM // 2):
        random.shuffle(xs)
        hits += abs(r(xs)) >= abs(r0)
    return r0, hits / (N_PERM // 2)


def main():
    D = load()
    gen = [v for v in D.values() if v["gen"]]
    of = lambda *labels: [v for (l, _), v in D.items() if l in labels]  # noqa: E731
    committed_off = of("gen gyms", "gen non-gym", "gen gyms, fixes off", "gen non-gym, fixes off")

    print("## 1. Group v rest, team level (points above the gen 9 baseline; permutation p)")
    for name, ts, pred in (
            ("real gen 7 + 9: stall", of(REAL7, REAL9), lambda f: f["arch"] == "stall"),
            ("real gen 7 + 9: 2+ walls", of(REAL7, REAL9), lambda f: f["walls"] >= 2),
            ("gen 7: stall", of(REAL7), lambda f: f["arch"] == "stall"),
            ("gen 9: stall", of(REAL9), lambda f: f["arch"] == "stall"),
            ("gen 7: hyper offense", of(REAL7), lambda f: f["arch"] == "hyper offense"),
            ("generator (committed + fixes off): 2+ setup", committed_off, lambda f: f["setup users"] >= 2),
            ("generator (committed + fixes off): 2+ walls", committed_off, lambda f: f["walls"] >= 2),
            ("generator (committed + fixes off): any PU-and-below", committed_off, lambda f: f["PU-and-below"] >= 1)):
        n, d, p = perm_group(ts, pred)
        print("  %-52s %3d/%-3d teams  %+5.1f  p = %.3f" % (name, n, len(ts), d, p))

    print("\n## 2. Per team: boss7, the other generator teams, real teams; r with the result over all generator team-runs")
    groups = {"boss7": [v for (l, t), v in D.items() if v["gen"] and t == "boss7"],
              "other gen": [v for (l, t), v in D.items() if v["gen"] and t != "boss7"],
              "real gen 7": of(REAL7), "real gen 9": of(REAL9)}
    keys = ["setup users", "Choice/LO/Sash", "type boosters/gems", "PU-and-below", "Uber+OU",
            "unranked (gen 8-9)", "types unresisted", "mean speed", "walls", "mean BST"]
    print("%-20s" % "" + "".join("%12s" % g for g in groups) + "   r (p)")
    for k in keys:
        r, p = perm_r(gen, k)
        print("%-20s" % k + "".join("%12.1f" % st.mean(v["f"][k] for v in g) for g in groups.values())
              + "   %+.2f (%.3f)" % (r, p))
    print("%-20s" % "teams" + "".join("%12d" % len(g) for g in groups.values()))
    for name, g in groups.items():
        print("  %-11s %d/%d, %+.1f v the gen 9 baseline" % (name, sum(v["w"] for v in g), sum(v["n"] for v in g), excess(g)))

    print("\n## 3. Teams with no wall/support set v the rest: spread (min p25 median p75 max, mean)")
    pools = {"generator": gen, "real gen 7": of(REAL7), "real gen 9": of(REAL9)}

    def q(xs):
        xs = sorted(xs)
        at = lambda f: xs[min(len(xs) - 1, int(f * len(xs)))]  # noqa: E731
        return "%5.0f %5.0f %5.0f %5.0f %5.0f  %5.2f" % (xs[0], at(.25), at(.5), at(.75), xs[-1], st.mean(xs))
    for k in ("mean speed", "fastest", "slowest", "at 100+", "under 60", "pivot users", "Scarf users", "priority users"):
        print("  %s" % k)
        for pn, ts in pools.items():
            for wn, cond in (("no walls", lambda w: w == 0), ("1+ walls", lambda w: w >= 1)):
                v = [t["f"][k] for t in ts if cond(t["f"]["walls"])]
                print("    %-11s %-9s n=%-3d %s" % (pn, wn, len(v), q(v)))
    for pn, ts in pools.items():
        nw = sorted([(k, v) for k, v in D.items() if v in ts and v["f"]["walls"] == 0], key=lambda kv: kv[1]["f"]["mean speed"])
        h = len(nw) // 2
        half = lambda g: "%d/%d %+.0f" % (sum(v["w"] for _, v in g), sum(v["n"] for _, v in g), excess([v for _, v in g]))  # noqa: E731
        print("\n  %s no-wall teams: slower half %s | faster half %s" % (pn, half(nw[:h]), half(nw[h:])))
        for (l, t), v in nw[:3] + nw[-3:]:
            f = v["f"]
            print("    %-22s %-24s speed %5.1f  %2d-%-2d %+4.0f  pivot %d  | %s" % (
                t, l, f["mean speed"], v["w"], v["n"] - v["w"], 100 * (v["w"] - v["e"]) / v["n"],
                f["pivot users"], ", ".join(f["names"])))


if __name__ == "__main__":
    main()
