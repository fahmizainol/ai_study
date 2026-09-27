#!/usr/bin/env python3
"""Real gen 8 monotype teams against real gen 8 UU (or OU) teams, Foul Play in both seats.

The gym runs ask how a gym does against what a real team of its TYPE does on the same
draw (make_mono_battles.py). This asks the question underneath: what does being monotype
cost a real team against an ordinary one? Up to PER_TYPE monotype teams of each type
(a team sharing two types counts once), each against K random gen 8 UU teams.

    python3 tools/rnb/make_mono_uu_battles.py [PER_TYPE=4] [K=2]   # -> generated/mono8_vs_uu8_10ms/
    python3 tools/rnb/make_mono_uu_battles.py --tier=ou --mono-from=generated/mono8_vs_uu8_10ms
                                                     # -> mono8_vs_ou8_10ms, the same monotype teams
    RNB_OUT=generated/mono8_vs_uu8_10ms python3 tools/rnb/run_battles.py 4 1 10

The monotype team plays side a (teams/rnb/, "rnb" in results), the UU team side b.
"""
import collections
import json
import os
import random
import shutil
import sys

sys.argv.append("--gen8")                    # make_mono_battles reads its gen at import
import make_mono_battles as MM  # noqa: E402
from make_battle_teams import Exporter, first_option, tid, UNPLAYABLE  # noqa: E402
from paths import DUMP, STUDY, TOOLS, pokedex  # noqa: E402

sys.path.insert(0, TOOLS)
import type_model as TM  # noqa: E402

OPTS = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
TIER = OPTS.get("tier", "uu")
OUT = os.environ.get("RNB_OUT", os.path.join(STUDY, "generated", "mono8_vs_%s8_10ms" % TIER))
GEN8_START = "2019-11-15"


def tier_pool(ex):
    dex9, pool = TM.dex(), []
    with open(os.path.join(DUMP, "gen8%s.json" % TIER), encoding="utf-8") as fh:
        raw = json.load(fh)
    for team in raw:
        data = team.get("data") or []
        if (team.get("date") or "") < GEN8_START or len(data) != 6 or not TM.legal_in(8, data, dex9):
            continue
        if any(tid(m["species"]) in UNPLAYABLE or tid(m["species"]) not in ex.dex
               or "baseStats" not in ex.dex[tid(m["species"])] for m in data):
            continue
        if any((m.get("ability") or "").lower() in ("", "no ability", "none") for m in data):
            continue
        if len({tid(m["species"]) for m in data}) < 6:
            continue
        mons, bst = [], 0
        for m in data:
            species = m["species"].replace("-Gmax", "")
            bst += sum(ex.dex[tid(species)]["baseStats"].values())
            mons.append({"sp": species, "item": first_option(m.get("item") or ""),
                         "ability": m.get("ability") or ex.dex[tid(species)]["abilities"]["0"],
                         "nature": m.get("nature") or "",
                         "moves": [first_option(mv) for mv in m.get("moves") or [] if mv]})
        if any(not x["moves"] for x in mons):
            continue
        pool.append({"name": team.get("name") or "", "url": team.get("url", ""), "bst": bst / 6, "mons": mons})
    print("%s pool" % TIER, len(pool))
    return pool


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    per_type = int(args[0]) if args else 4
    k = int(args[1]) if len(args) > 1 else 2
    ex = Exporter(pokedex())
    for side in ("rnb", "smogon"):
        d = os.path.join(OUT, "teams", side)
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
    mono, uu = MM.mono_pool(ex), tier_pool(ex)
    rng, pairs, taken = random.Random(42), [], set()
    types = sorted({t for p in mono for t in p["types"]})
    fixed = None
    if "mono-from" in OPTS:                   # replay another run's monotype teams, in its order
        prev = json.load(open(os.path.join(STUDY, OPTS["mono-from"], "pairs.json"), encoding="utf-8"))
        fixed = list(dict.fromkeys((p["theme"], int(p["boss"].rsplit("_", 1)[1])) for p in prev))
    for theme in types:
        typed = [j for j, p in enumerate(mono) if theme in p["types"] and j not in taken]
        picks = ([j for t, j in fixed if t == theme] if fixed is not None
                 else rng.sample(typed, min(per_type, len(typed))))
        for j in picks:
            taken.add(j)
            slug = "mono%s_%d" % (theme.lower(), j)
            with open(os.path.join(OUT, "teams", "rnb", slug), "w", encoding="utf-8") as fh:
                fh.write(ex.export(mono[j]["mons"]))
            for u in rng.sample(range(len(uu)), k):
                uslug = "%s_%d" % (TIER, u)
                with open(os.path.join(OUT, "teams", "smogon", uslug), "w", encoding="utf-8") as fh:
                    fh.write(ex.export(uu[u]["mons"]))
                pairs.append({"boss": slug, "boss_name": mono[j]["name"], "boss_bst": round(mono[j]["bst"]),
                              "theme": theme, "opp": uslug, "opp_fmt": "gen8" + TIER, "opp_bst": round(uu[u]["bst"]),
                              "opp_name": uu[u]["name"], "opp_url": uu[u]["url"]})
    with open(os.path.join(OUT, "pairs.json"), "w", encoding="utf-8") as fh:
        json.dump(pairs, fh, indent=1)
    print("%d monotype teams, %d pairings -> %s" % (len(taken), len(pairs), OUT),
          dict(collections.Counter(p["theme"] for p in pairs)))


if __name__ == "__main__":
    main()
