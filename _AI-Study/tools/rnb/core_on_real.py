#!/usr/bin/env python3
"""Core-first's anchor / enabler / patch, read off REAL Smogon monotype teams.

The generator builds a gym as anchor -> enabler -> patch -> glue (RNB-STUDY.md §10). This
applies the same three tests to a real monotype team of each gym's type (the teams played
on the gyms' own bosses, generated/rnb_vs_mono*_10ms), so the generated cores can be read
against what real builders field:

  anchor   the member with the best attacking stat, counting a mega (anchor_test.py: the
           best of the rankings tried)
  enabler  the teammate resisting the most of the anchor's weaknesses; its job is the
           first of removal / hazards / pivot its set carries
  patch    a teammate that resists a type hitting both, and carries a move hitting it back

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/core_on_real.py
"""
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import deck_slots as DS  # noqa: E402
import composition as C  # noqa: E402
from anchor_test import members, tid  # noqa: E402
from make_battle_teams import Exporter  # noqa: E402
from paths import pokedex  # noqa: E402

TYPES = [t for t in C.CHART if t != "Stellar"]
JOBS = [("removal", {"defog", "rapidspin", "courtchange", "mortalspin", "tidyup"}),
        ("hazards", {"stealthrock", "spikes", "toxicspikes", "stickyweb"}),
        ("pivot", {"uturn", "voltswitch", "flipturn", "partingshot", "teleport", "chillyreception"})]
THEMES = ["Bug", "Fairy", "Water", "Ice", "Dark", "Ground", "Psychic", "Normal", "Steel"]


def eff(atk, types):
    m = 1.0
    for d in types:
        m *= {0: 1, 1: 2, 2: 0.5, 3: 0}[C.CHART[d].get(atk, 0)]
    return m


ATTACK_ITEMS = {"choiceband", "choicespecs", "choicescarf", "lifeorb", "expertbelt", "loadeddice"}


def typed(ms, ex):
    for m in ms:
        e = ex.entry(m["sp"])
        base = tid(e.get("baseSpecies", e["name"]))
        mega = next((v for (b, it), v in ex.mega.items() if b == base), None) if m["mega"] else None
        m["types"] = (mega or e)["types"]
        m["name"] = e["name"]
    return ms


def core(ms):
    """-> anchor, weak, enabler, shields, job, lose, patch, answers"""
    anchor = max(ms, key=lambda m: (max(m["form"]["atk"], m["form"]["spa"]), sum(m["form"].values())))
    weak = [t for t in TYPES if eff(t, anchor["types"]) > 1]
    rest = [m for m in ms if m is not anchor]
    shields = lambda m: [w for w in weak if eff(w, m["types"]) < 1]  # noqa: E731
    enabler = max(rest, key=lambda m: len(shields(m))) if any(shields(m) for m in rest) else None
    job = next((j for j, mv in JOBS if enabler and set(enabler["moves"]) & mv), None) if enabler else None
    pair = [anchor] + ([enabler] if enabler else [])
    lose = [t for t in TYPES if all(eff(t, m["types"]) > 1 for m in pair)]

    def answers(m):
        hits = {C.MV[x]["type"] for x in m["moves"] if C.MV.get(x, {}).get("bp")}
        return [t for t in lose if eff(t, m["types"]) < 1 and any(eff(h, [t]) > 1 for h in hits)]
    cand = [m for m in ms if m not in pair and answers(m)]
    patch = max(cand, key=lambda m: len(answers(m))) if cand else None
    return anchor, weak, enabler, (shields(enabler) if enabler else []), job, lose, patch, (answers(patch) if patch else [])


def main():
    per, kinds, record = DS.collect()
    ex = Exporter(pokedex())
    groups = {"monotype (gen 7-9)": ("rnb_vs_mono_10ms", "rnb_vs_mono8_10ms", "rnb_vs_mono7_10ms"),
              "mainstream gen 7 (OU, UU, Ubers...)": ("rnb_vs_gen7_25ms", "rnb_vs_gen7_10ms")}
    summary = {}
    examples = []
    for label, arms in groups.items():
        rows = []
        for arm in arms:
            teams = {t for (t, sp) in per.get(arm, {})}
            for team in sorted(teams):
                path = os.path.join(DS.G, arm, "teams", "smogon", team)
                if not os.path.exists(path):
                    continue
                ms = typed(members(path, ex), ex)
                if any(per[arm][team, m["sp"]]["battles"] < 2 for m in ms):
                    continue
                kpb = {m["sp"]: per[arm][team, m["sp"]]["kos"] / per[arm][team, m["sp"]]["battles"] for m in ms}
                a, weak, en, sh, job, lose, pa, ans = core(ms)
                top = max(kpb.values())
                rows.append({"enabler": en is not None, "job": job is not None, "lose": bool(lose),
                             "patch": pa is not None, "anchor_top": kpb[a["sp"]] == top,
                             "anchor_item": a["item"] in ATTACK_ITEMS or a["mega"],
                             "anchor_kos": kpb[a["sp"]], "team_best": top})
                if label.startswith("mainstream") and arm == "rnb_vs_gen7_25ms":
                    examples.append((team, ms, kpb, (a, weak, en, sh, job, lose, pa, ans)))
        summary[label] = rows
    n = lambda rows, k: 100 * sum(r[k] for r in rows) / len(rows)  # noqa: E731
    print(f"{'':40s} {'teams':>6s} {'enabler':>8s} {'+job':>6s} {'a type hits both':>17s} {'patch':>6s} {'anchor on attack item':>22s} {'anchor = top KO':>16s}")
    for label, rows in summary.items():
        print(f"{label:40s} {len(rows):6d} {n(rows,'enabler'):7.0f}% {n(rows,'job'):5.0f}% {n(rows,'lose'):16.0f}% {n(rows,'patch'):5.0f}% {n(rows,'anchor_item'):21.0f}% {n(rows,'anchor_top'):15.0f}%")
    fmt = lambda m: f"{m['name']}{' (mega)' if m['mega'] else ''}"  # noqa: E731
    print("\n# mainstream gen 7 examples")
    examples.sort(key=lambda e: e[0])
    for team, ms, kpb, (a, weak, en, sh, job, lose, pa, ans) in examples[:: max(1, len(examples) // 9)][:9]:
        top = max(ms, key=lambda m: kpb[m["sp"]])
        print(f"\n{team}   top KO-getter: {fmt(top)} {kpb[top['sp']]:.2f}/battle")
        print(f"   anchor  : {fmt(a)} @ {a['item']} (weak to {'/'.join(weak)}) {kpb[a['sp']]:.2f} KOs/battle")
        print(f"   enabler : {fmt(en) + ' shields ' + '/'.join(sh) + (', ' + job if job else '') if en else 'none'}")
        print(f"   patch   : {fmt(pa) + ' answers ' + '/'.join(ans) if pa else ('none (nothing hits both)' if not lose else 'none')}")
        print(f"   team    : {', '.join(fmt(m) for m in ms)}")


if __name__ == "__main__":
    main()
