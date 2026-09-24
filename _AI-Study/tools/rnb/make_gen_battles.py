#!/usr/bin/env python3
"""Pair the boss generator's nine gym teams against Run & Bun's singles bosses.

Writes generated/rnb_vs_gen/: teams/gen/ (the gyms, exported for Foul Play), teams/rnb/
(copies of the Run & Bun bosses used) and pairs.json -- every gym against the K Run & Bun
bosses nearest its mean BST. Run with the study's harness:

    python3 tools/rnb/make_gen_battles.py [K=4] [--trainers]
    RNB_OUT=generated/rnb_vs_gen python3 tools/rnb/run_battles.py 4 2

--published is the ablation: the same species, each on the published set the generator
started from, UNMODIFIED -- no level-legality move swaps, no role re-sets (written to
<dir>_published/, same pairings, so tags line up with the generator run). Its ability and
item come along too, unless the set was borrowed from a relative's entry (`inherited`) or
the item is a Z-crystal (Realidea has no Z-move engine); then the generator's stand. A
slot with no published source (a Studio custom set, a "generated" fallback) keeps the
generator's set.

--from DIR --name NAME exports a generator run written elsewhere (tools/rnb/gen_fixes.py
writes DIR/gyms.json and DIR/trainers.json) to generated/rnb_vs_gen[_trainers]_NAME/.

--trainers exports the non-gym fights instead (teams_trainers.json -> generated/
rnb_vs_gen_trainers/). A rival team holding an engine-filled starter slot (`owenpoke2`
and friends: a Realidea fakemon Showdown does not know, with no moveset) is skipped --
played 5-v-6 it would measure nothing, the Tate & Liza mistake.

Same rules as RNB-STUDY.md §5, so the two runs compare: level 100, NO EVs (the
generator's spreads are dropped, natures kept), 31 IVs, no Tera, megas exported as the
base species holding the stone. The generator writes Essentials internal names; moves,
items and natures map to Showdown by id, and the ability index is resolved against
Realidea's own pokemon.txt (index 2 = HiddenAbility), so a hidden ability is the one the
game would give.

Teams are named gym1..gym9 (or boss1.., rival1.. in file order) only: Realidea's
trainer names are spoilers, so they are kept out of every file this experiment writes.
"""
import collections
import json
import os
import re
import shutil
import sys

from make_battle_teams import Exporter, first_option, tid
from paths import RNB, STUDY, TOOLS, pokedex

sys.path.insert(0, TOOLS)
import smogon_corpus as SC  # noqa: E402

GYMS = os.path.join(STUDY, "generated", "teams_bosses_gyms.json")
TRAINERS = os.path.join(STUDY, "generated", "teams_trainers.json")
PBS = os.path.join(STUDY, "..", "Realidea V4.1", "PBS", "pokemon.txt")
SHOWDOWN_DEX = os.path.join(STUDY, "generated", "showdown_dex.json")
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


def published(m, dex):
    """The published set a generator slot started from, or None. `src` is
    "<fmt>/<source>/<set name>" plus the generator's own suffixes."""
    src = re.sub(r"( \((dev set was [^)]*|-\w+)\))+$", "", m["src"])
    key = tuple(src.split("/", 2))
    st = SC.sets().get(SC.norm(m.get("inherited") or m["species"]), {}).get(key)
    if st is None:
        return None
    out = {"moves": [first_option(mv) for mv in st["moves"] if mv], "nature": st.get("nature")}
    own = {tid(a) for a in dex[tid(m["species"])]["abilities"].values()}
    if not m.get("inherited") and tid(st.get("ability") or "") in own:
        out["ability"] = st["ability"]
    item = first_option(st.get("item") or "")
    if not m.get("inherited") and item and not item.endswith(" Z"):
        out["item"] = item
    return out


def fights(trainers):
    """(anonymous id, team) for every playable fight in the chosen file."""
    if not trainers:
        # "gym3_<CLASS>_<Name>" -> "gym3"
        return [(g["id"].split("_", 1)[0], g) for g in json.load(open(GYMS, encoding="utf-8"))]
    out, n = [], collections.Counter()
    for t in json.load(open(TRAINERS, encoding="utf-8")):
        if any(m["species"].islower() for m in t["mons"]):   # engine-filled starter slot
            continue
        kind = t["id"].split("_", 1)[0]                      # "boss" / "rival"
        n[kind] += 1
        out.append(("%s%d" % (kind, n[kind]), t))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    k = int(args[0]) if args else 4
    trainers = "--trainers" in sys.argv
    pub = "--published" in sys.argv
    base = "rnb_vs_gen_trainers" if trainers else "rnb_vs_gen"
    if "--from" in sys.argv:
        # a generator run written elsewhere (gen_fixes.py): DIR/gyms.json, DIR/trainers.json,
        # exported to generated/<base>_<NAME>
        global GYMS, TRAINERS
        src, name = sys.argv[sys.argv.index("--from") + 1], sys.argv[sys.argv.index("--name") + 1]
        args = [a for a in args if a not in (src, name)]
        k = int(args[0]) if args else 4
        GYMS, TRAINERS = os.path.join(src, "gyms.json"), os.path.join(src, "trainers.json")
        base += "_" + name
    OUT = os.path.join(STUDY, "generated", base + ("_published" if pub else ""))
    used = collections.Counter()
    dex = pokedex()
    sd = json.load(open(SHOWDOWN_DEX, encoding="utf-8"))["gen9"]
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
    for gid, g in fights(trainers):
        mons, bst = [], 0
        for m in g["mons"]:
            item = name(items, m["item"], "item") if m["item"] else ""
            mon = {"sp": m["species"], "item": item,
                   "ability": name(abilities, ability_name(m["species"], m["ability"], pbs), "ability"),
                   "nature": m["nature"].capitalize(),
                   "moves": [name(moves, mv, "move") for mv in m["moves"]]}
            p = published(m, dex) if pub else None
            if pub:
                used["published" if p else "no published source: generator set kept"] += 1
            if p:
                mon["moves"] = [name(moves, mv, "move") for mv in p["moves"]]
                mon["nature"] = p["nature"] or mon["nature"]
                if "ability" in p:
                    mon["ability"] = name(abilities, p["ability"], "ability")
                if "item" in p:
                    mon["item"] = item = name(items, p["item"], "item")
            mons.append(mon)
            e = ex.entry(m["species"])
            e = ex.mega.get((tid(e.get("baseSpecies", e["name"])), item), e)
            bst += sum(e["baseStats"].values())
        with open(os.path.join(tdir["gen"], gid), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(ex.export(mons))
        gyms.append({"id": gid, "bst": bst / len(mons)})

    # the Run & Bun bosses and their BSTs, exactly as the Smogon run paired them
    bosses = {}
    for p in json.load(open(os.path.join(RNB, "pairs.json"), encoding="utf-8")):
        if not p["boss"].startswith(EXCLUDED):
            bosses.setdefault(p["boss"], p)
    pairs = []
    for g in gyms:
        for b in sorted(bosses.values(), key=lambda b: abs(b["boss_bst"] - g["bst"]))[:k]:
            shutil.copy(os.path.join(RNB, "teams", "rnb", b["boss"]), tdir["rnb"])
            pairs.append({"boss": b["boss"], "boss_name": b["boss_name"], "cap": b["cap"],
                          "boss_bst": b["boss_bst"], "opp": g["id"], "opp_side": "gen",
                          "opp_bst": round(g["bst"])})
    with open(os.path.join(OUT, "pairs.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(pairs, fh, indent=1)
    for p in pairs:
        print("%-6s %4d  vs  %-40s %4d" % (p["opp"], p["opp_bst"], p["boss"], p["boss_bst"]))
    print("%d teams, %d pairings -> %s" % (len(gyms), len(pairs), OUT))
    if pub:
        print(dict(used))


if __name__ == "__main__":
    main()
