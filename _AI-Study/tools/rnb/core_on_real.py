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


def main():
    per, kinds, record = DS.collect()
    ex = Exporter(pokedex())
    for arm in ("rnb_vs_mono_10ms", "rnb_vs_mono8_10ms"):
        pairs = json.load(open(os.path.join(DS.G, arm, "pairs.json")))
        by_theme = collections.defaultdict(list)
        for p in pairs:
            by_theme[p["theme"]].append(p["opp"])
        print(f"\n# {arm}: one real team per type (the one played most)")
        for theme in THEMES:
            teams = by_theme.get(theme)
            if not teams:
                continue
            team = max(set(teams), key=lambda t: (sum(record[arm][t, w] for w in (True, False)), t))
            path = os.path.join(DS.G, arm, "teams", "smogon", team)
            ms = members(path, ex)
            for m in ms:
                e = ex.entry(m["sp"])
                meg = ex.mega.get((tid(e.get("baseSpecies", e["name"])), open(path).read() and ""))
                m["types"] = e["types"] if not m["mega"] else [
                    x for x in next(v for (b, it), v in ex.mega.items() if tid(v["baseSpecies"]) == tid(e.get("baseSpecies", e["name"])))["types"]]
                m["name"] = e["name"]
            won = record[arm][team, True]
            lost = record[arm][team, False]
            kpb = {m["sp"]: per[arm][team, m["sp"]]["kos"] / max(per[arm][team, m["sp"]]["battles"], 1) for m in ms}
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
            top = max(ms, key=lambda m: kpb[m["sp"]])
            fmt = lambda m: f"{m['name']}{' (mega)' if m['mega'] else ''}"  # noqa: E731
            print(f"\n{theme:8s} {team}  {won}-{lost} on the gym's bosses; top KO-getter: {fmt(top)} {kpb[top['sp']]:.2f}/battle")
            print(f"   anchor  : {fmt(anchor)}  (atk {max(anchor['form']['atk'], anchor['form']['spa'])}; weak to {'/'.join(weak)}) {kpb[anchor['sp']]:.2f} KOs/battle")
            print(f"   enabler : {fmt(enabler) + ' shields ' + '/'.join(shields(enabler)) + (', ' + job if job else '') if enabler else 'none'}")
            print(f"   patch   : {fmt(patch) + ' answers ' + '/'.join(answers(patch)) if patch else ('none (nothing hits both)' if not lose else 'none: nobody resists and hits back ' + '/'.join(lose))}")
            print(f"   team    : {', '.join(fmt(m) + ' @ ' + m['item'] for m in ms)}")


if __name__ == "__main__":
    main()
