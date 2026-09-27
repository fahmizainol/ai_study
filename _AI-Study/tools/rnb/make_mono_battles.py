#!/usr/bin/env python3
"""Real Smogon monotype teams against the bosses a generated gym fights, type for type.

The gyms are monotype by construction and the real teams in every other run are not, so a
gym's record says nothing about what a real team of its TYPE could do on its draw (§10:
gym 7, Psychic, 0-3 against Sidney's three Dark attackers). This pairs each gym's bosses
with gen 9 Smogon monotype teams of the gym's theme, nearest in mean BST, from the same
dump the §4 theme analysis used.

    python3 tools/rnb/make_mono_battles.py GYM_ARM [K=2] [--gen7]   # -> generated/rnb_vs_mono_10ms/
                                                                     # (--gen7 / --gen8: that gen's monotype, rnb_vs_mono7_10ms / mono8)
    RNB_OUT=generated/rnb_vs_mono_10ms python3 tools/rnb/run_battles.py 4 2 10

GYM_ARM is a generated/rnb_vs_gen_* folder whose pairs.json says which bosses each gym
fought; the themes come from generate_bosses.THEME in gym order. A monotype team's type is
the one every member shares (a mega counted as its mega forme); teams sharing two types
count for both.
"""
import collections
import json
import os
import random
import shutil
import sys

from make_battle_teams import Exporter, first_option, tid, GEN7_START, GEN9_START, UNPLAYABLE
from paths import DUMP, STUDY, TOOLS, pokedex

sys.path.insert(0, TOOLS)
import type_model as TM  # noqa: E402

GEN = 7 if "--gen7" in sys.argv else 8 if "--gen8" in sys.argv else 9
GEN_START = {7: GEN7_START, 8: "2019-11-15", 9: GEN9_START}
OUT = os.environ.get("RNB_OUT", os.path.join(STUDY, "generated", "rnb_vs_mono%s_10ms" % ("" if GEN == 9 else GEN)))
THEMES = ["Bug", "Fairy", "Water", "Ice", "Dark", "Ground", "Psychic", "Normal", "Steel"]


def mono_pool(ex):
    dex9 = TM.dex()
    pool = []
    with open(os.path.join(DUMP, "gen%dmonotype.json" % GEN), encoding="utf-8") as fh:
        raw = json.load(fh)
    for team in raw:
        data = team.get("data") or []
        if (team.get("date") or "") < GEN_START[GEN] or len(data) != 6:
            continue
        if not TM.legal_in(GEN, data, dex9):
            continue
        if GEN == 7 and any((m.get("item") or "").endswith(" Z") for m in data):
            continue                          # Realidea has no Z-move engine
        if any(tid(m["species"]) in UNPLAYABLE or tid(m["species"]) not in ex.dex
               or "baseStats" not in ex.dex[tid(m["species"])] for m in data):
            continue
        if any((m.get("ability") or "").lower() in ("", "no ability", "none") for m in data):
            continue
        if len({tid(m["species"]) for m in data}) < 6:
            continue
        mons, bst, shared = [], 0, None
        for m in data:
            e = ex.dex[tid(m["species"])]
            e = ex.mega.get((tid(e.get("baseSpecies", e["name"])), m.get("item")), e)
            bst += sum(e["baseStats"].values())
            shared = set(e["types"]) if shared is None else shared & set(e["types"])
            mons.append({"sp": m["species"], "item": first_option(m.get("item") or ""),
                         "ability": m.get("ability") or e["abilities"]["0"],
                         "nature": m.get("nature") or "",
                         "moves": [first_option(mv) for mv in m.get("moves") or [] if mv]})
        if not shared or any(not x["moves"] for x in mons):
            continue
        pool.append({"types": shared, "name": team.get("name") or "", "url": team.get("url", ""),
                     "bst": bst / 6, "mons": mons})
    print("monotype pool", len(pool), dict(collections.Counter(t for p in pool for t in p["types"])))
    return pool


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    gym_arm = args[0]
    k = int(args[1]) if len(args) > 1 else 2
    src = os.path.join(STUDY, "generated", gym_arm)
    gym_pairs = json.load(open(os.path.join(src, "pairs.json"), encoding="utf-8"))
    ex = Exporter(pokedex())
    for side in ("rnb", "smogon"):
        d = os.path.join(OUT, "teams", side)
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
    pool = mono_pool(ex)
    rng, pairs, used = random.Random(42), [], set()
    for i, theme in enumerate(THEMES):
        gym = "gym%d" % (i + 1)
        bosses = [p for p in gym_pairs if p["opp"] == gym]
        typed = [j for j, p in enumerate(pool) if theme in p["types"]]
        for b in bosses:
            shutil.copy(os.path.join(src, "teams", "rnb", b["boss"]), os.path.join(OUT, "teams", "rnb", b["boss"]))
            near = sorted((j for j in typed if j not in used), key=lambda j: abs(pool[j]["bst"] - b["boss_bst"]))[:k * 4]
            for j in rng.sample(near, min(k, len(near))):
                used.add(j)
                slug = "mono%s_%d" % (theme.lower(), j)
                with open(os.path.join(OUT, "teams", "smogon", slug), "w", encoding="utf-8") as fh:
                    fh.write(ex.export(pool[j]["mons"]))
                pairs.append({"boss": b["boss"], "boss_name": b["boss_name"], "cap": b["cap"],
                              "boss_bst": b["boss_bst"], "opp": slug, "opp_fmt": "gen%dmonotype" % GEN,
                              "opp_bst": round(pool[j]["bst"]), "opp_name": pool[j]["name"],
                              "opp_url": pool[j]["url"], "gym": gym, "theme": theme})
    with open(os.path.join(OUT, "pairs.json"), "w", encoding="utf-8") as fh:
        json.dump(pairs, fh, indent=1)
    print("%d pairings -> %s" % (len(pairs), OUT))


if __name__ == "__main__":
    main()
