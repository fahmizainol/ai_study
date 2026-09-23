#!/usr/bin/env python3
"""Pair the boss generator's nine gym teams against Run & Bun's singles bosses.

Writes generated/rnb_vs_gen/: teams/gen/ (the gyms, exported for Foul Play), teams/rnb/
(copies of the Run & Bun bosses used) and pairs.json -- every gym against the K Run & Bun
bosses nearest its mean BST. Run with the study's harness:

    python3 tools/rnb/make_gen_battles.py [K=4]
    RNB_OUT=generated/rnb_vs_gen python3 tools/rnb/run_battles.py 4 2

Same rules as RNB-STUDY.md §5, so the two runs compare: level 100, NO EVs (the
generator's spreads are dropped, natures kept), 31 IVs, no Tera, megas exported as the
base species holding the stone. The generator writes Essentials internal names; moves,
items and natures map to Showdown by id, and the ability index is resolved against
Realidea's own pokemon.txt (index 2 = HiddenAbility), so a hidden ability is the one the
game would give.

Gyms are named gym1..gym9 only: Realidea's trainer names are spoilers, so they are kept
out of every file this experiment writes.
"""
import json
import os
import shutil
import sys

from make_battle_teams import Exporter, tid
from paths import RNB, STUDY, pokedex

GYMS = os.path.join(STUDY, "generated", "teams_bosses_gyms.json")
PBS = os.path.join(STUDY, "..", "Realidea V4.1", "PBS", "pokemon.txt")
SHOWDOWN_DEX = os.path.join(STUDY, "generated", "showdown_dex.json")
OUT = os.path.join(STUDY, "generated", "rnb_vs_gen")
EXCLUDED = ("Leader_Tate", "Leader_Liza")   # one double battle in the game; see summarize_battles


def pbs_abilities():
    out, cur = {}, None
    with open(PBS, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            key, _, val = line.strip().partition("=")
            if key == "InternalName":
                cur = out.setdefault(val, {})
            elif cur is not None and key in ("Abilities", "HiddenAbility"):
                cur[key] = val.split(",")
    return out


def ability_name(species, index, pbs):
    rec = pbs[species]
    slots = rec["Abilities"]
    if index == 2 and rec.get("HiddenAbility"):
        return rec["HiddenAbility"][0]
    # Essentials falls back to the first ability when the index names an empty slot
    return slots[index] if index < len(slots) else slots[0]


def main():
    k = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    dex = pokedex()
    sd = json.load(open(SHOWDOWN_DEX))["gen9"]
    abilities = {tid(a): a for e in dex.values() for a in e.get("abilities", {}).values()}

    def name(table, internal, what):
        n = table.get(tid(internal))
        assert n, "%s %s has no Showdown name" % (what, internal)
        return n

    moves = {k_: v["name"] for k_, v in sd["moves"].items()}
    items = {k_: v["name"] for k_, v in sd["items"].items()}
    pbs, ex = pbs_abilities(), Exporter(dex)

    tdir = {side: os.path.join(OUT, "teams", side) for side in ("gen", "rnb")}
    for d in tdir.values():
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)

    gyms = []
    for g in json.load(open(GYMS)):
        gid = g["id"].split("_", 1)[0]          # "gym3_<CLASS>_<Name>" -> "gym3"
        mons, bst = [], 0
        for m in g["mons"]:
            item = name(items, m["item"], "item") if m["item"] else ""
            mons.append({"sp": m["species"], "item": item,
                         "ability": name(abilities, ability_name(m["species"], m["ability"], pbs), "ability"),
                         "nature": m["nature"].capitalize(),
                         "moves": [name(moves, mv, "move") for mv in m["moves"]]})
            e = ex.entry(m["species"])
            e = ex.mega.get((tid(e.get("baseSpecies", e["name"])), item), e)
            bst += sum(e["baseStats"].values())
        with open(os.path.join(tdir["gen"], gid), "w") as fh:
            fh.write(ex.export(mons))
        gyms.append({"id": gid, "bst": bst / len(mons)})

    # the Run & Bun bosses and their BSTs, exactly as the Smogon run paired them
    bosses = {}
    for p in json.load(open(os.path.join(RNB, "pairs.json"))):
        if not p["boss"].startswith(EXCLUDED):
            bosses.setdefault(p["boss"], p)
    pairs = []
    for g in gyms:
        for b in sorted(bosses.values(), key=lambda b: abs(b["boss_bst"] - g["bst"]))[:k]:
            shutil.copy(os.path.join(RNB, "teams", "rnb", b["boss"]), tdir["rnb"])
            pairs.append({"boss": b["boss"], "boss_name": b["boss_name"], "cap": b["cap"],
                          "boss_bst": b["boss_bst"], "opp": g["id"], "opp_side": "gen",
                          "opp_bst": round(g["bst"])})
    with open(os.path.join(OUT, "pairs.json"), "w") as fh:
        json.dump(pairs, fh, indent=1)
    for p in pairs:
        print("%-6s %4d  vs  %-40s %4d" % (p["opp"], p["opp_bst"], p["boss"], p["boss_bst"]))
    print("%d gyms, %d pairings -> %s" % (len(gyms), len(pairs), OUT))


if __name__ == "__main__":
    main()
