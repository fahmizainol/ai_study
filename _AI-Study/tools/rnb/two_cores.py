#!/usr/bin/env python3
"""Two anchors instead of one: core-first's proposed split, read off real Smogon teams.

The teambuilding guide the generator's core-first build follows builds TWO mini-cores in
its bring-6-pick-3 format: a second anchor with "nothing to do with" the first, for when
the opponent handles the first (RNB-STUDY.md §10). This reads that split off the real teams
already played here, mainstream gen 7 and monotype gen 7-9:

  anchor 1   on an attacking set, best attacking stat counting a mega (anchor_test.py)
  enabler 1  the teammate resisting the most of anchor 1's weaknesses
  anchor 2   another attacking-set member that hits super-effectively the types resisting
             every attack anchor 1 carries -- what anchor 1 struggles against
  enabler 2  from what is left, the teammate resisting the most of anchor 2's weaknesses

and checks whether the team's real top KO-getter is one of the two anchors, against anchor 1
alone and against two members drawn at random.

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/two_cores.py
"""
import collections
import itertools
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import deck_slots as DS  # noqa: E402
import core_on_real as CR  # noqa: E402
import anchor_test as AT  # noqa: E402
from make_battle_teams import Exporter  # noqa: E402
from paths import pokedex  # noqa: E402

GROUPS = {"mainstream gen 7": ("rnb_vs_gen7_25ms", "rnb_vs_gen7_10ms"),
          "monotype gen 7-9": ("rnb_vs_mono_10ms", "rnb_vs_mono8_10ms", "rnb_vs_mono7_10ms")}


def atk(m):
    return max(m["form"]["atk"], m["form"]["spa"])


def attack_types(m):
    return {CR.C.MV[x]["type"] for x in m["moves"] if CR.C.MV.get(x, {}).get("bp")}


def walls_of(m):
    """Types that resist or are immune to every attack this set carries."""
    hits = attack_types(m)
    if not hits:
        return []
    return [t for t in CR.TYPES if all(CR.eff(h, [t]) < 1 for h in hits)]


def enabler(anchor, pool):
    weak = [t for t in CR.TYPES if CR.eff(t, anchor["types"]) > 1]
    shields = lambda m: [w for w in weak if CR.eff(w, m["types"]) < 1]  # noqa: E731
    best = max(pool, key=lambda m: len(shields(m)), default=None)
    return (best, shields(best)) if best and shields(best) else (None, [])


def split(ms, kd):
    attackers = [m for m in ms if AT.attacking(m, kd.get(m["sp"]))] or list(ms)
    a1 = max(attackers, key=lambda m: (atk(m), sum(m["form"].values())))
    rest = [m for m in ms if m is not a1]
    e1, s1 = enabler(a1, rest)
    walls = walls_of(a1)
    cover = lambda m: [t for t in walls if any(CR.eff(h, [t]) > 1 for h in attack_types(m))]  # noqa: E731
    cand = [m for m in attackers if m is not a1 and m is not e1]
    a2 = max(cand, key=lambda m: (len(cover(m)), atk(m)), default=None)
    left = [m for m in rest if m not in (e1, a2)]
    e2, s2 = enabler(a2, left) if a2 else (None, [])
    return a1, e1, s1, walls, a2, cover(a2) if a2 else [], e2, s2


def main():
    per, kinds, record = DS.collect()
    ex = Exporter(pokedex())
    fmt = lambda m: f"{m['name']}{' (mega)' if m['mega'] else ''} @ {m['item'] or '-'}" if m else "none"  # noqa: E731
    for label, arms in GROUPS.items():
        rows, shown = [], []
        for arm in arms:
            for team in sorted({t for (t, sp) in per.get(arm, {})}):
                path = os.path.join(DS.G, arm, "teams", "smogon", team)
                if not os.path.exists(path):
                    continue
                ms = CR.typed(AT.members(path, ex), ex)
                if any(per[arm][team, m["sp"]]["battles"] < 2 for m in ms):
                    continue
                kpb = {m["sp"]: per[arm][team, m["sp"]]["kos"] / per[arm][team, m["sp"]]["battles"] for m in ms}
                a1, e1, s1, walls, a2, cov, e2, s2 = split(ms, kinds.get((arm, team), {}))
                top = max(kpb.values())
                pair = [x for x in (a1, a2) if x]
                rand2 = st.mean(max(kpb[a["sp"]], kpb[b["sp"]]) == top for a, b in itertools.combinations(ms, 2))
                rows.append({"a1_top": kpb[a1["sp"]] == top, "pair_top": any(kpb[x["sp"]] == top for x in pair),
                             "rand2": rand2, "a2": a2 is not None, "a2_covers": bool(cov),
                             "kos_pair": sum(kpb[x["sp"]] for x in pair), "kos_team": sum(kpb.values()),
                             "e1": e1 is not None, "e2": e2 is not None})
                if len(shown) < 5 and arm in ("rnb_vs_gen7_25ms", "rnb_vs_mono_10ms") and len(rows) % 9 == 1:
                    shown.append((team, record[arm][team, True], record[arm][team, False], kpb, ms,
                                  (a1, e1, s1, walls, a2, cov, e2, s2)))
        n = len(rows)
        pct = lambda k: 100 * sum(r[k] for r in rows) / n  # noqa: E731
        print(f"\n## {label}: {n} teams")
        print(f"   second anchor found {pct('a2'):.0f}% (hits what anchor 1 cannot: {pct('a2_covers'):.0f}%); "
              f"enabler 1 {pct('e1'):.0f}%, enabler 2 {pct('e2'):.0f}%")
        print(f"   top KO-getter is anchor 1: {pct('a1_top'):.0f}%   is one of the two anchors: {pct('pair_top'):.0f}%   "
              f"two random members: {100 * st.mean(r['rand2'] for r in rows):.0f}%")
        print(f"   share of the team's KOs made by the two anchors: "
              f"{100 * sum(r['kos_pair'] for r in rows) / sum(r['kos_team'] for r in rows):.0f}% (two of six members = 33%)")
        for team, w, l, kpb, ms, (a1, e1, s1, walls, a2, cov, e2, s2) in shown:
            top = max(ms, key=lambda m: kpb[m["sp"]])
            print(f"\n   {team} ({w}-{l}); top KO-getter {top['name']} {kpb[top['sp']]:.1f}")
            print(f"      core 1: {fmt(a1)} [{kpb[a1['sp']]:.1f}] + {fmt(e1)}{' (resists ' + '/'.join(s1) + ')' if e1 else ''}")
            print(f"      anchor 1 is walled by: {'/'.join(walls) or 'nothing'}")
            if a2:
                print(f"      core 2: {fmt(a2)} [{kpb[a2['sp']]:.1f}]{' hits ' + '/'.join(cov) if cov else ''} + {fmt(e2)}{' (resists ' + '/'.join(s2) + ')' if e2 else ''}")
            others = [m for m in ms if m not in (a1, e1, a2, e2)]
            print(f"      support: {', '.join(fmt(m) for m in others) or '-'}")


if __name__ == "__main__":
    main()
