#!/usr/bin/env python3
"""Export Run & Bun's singles bosses and BST-matched Smogon gen 9 teams for Foul Play.

Writes Showdown-export team files to generated/rnb/teams/{rnb,smogon}/ and the schedule
to generated/rnb/pairs.json: every singles boss against K Smogon teams whose mean BST is
closest to its own (drawn from the 5K nearest, so one boss does not face K near-copies).

Both sides are put on Run & Bun's rules, so the battles compare team-building and nothing
else: level 100, NO EVs (the Smogon spreads are dropped, natures kept), 31 IVs, no Tera.
Megas and Primals are exported as the base species holding the stone/orb.

The smogon-dump file names do not guarantee the generation (MONOTYPE-SYNERGY.md §10 hit
the same trap): of gen9ubers.json's teams, 2,004 were posted before gen 9 existed and 935
more are not gen-9 legal -- one "gen 9 Ubers" opponent was a gen 1 team with no abilities.
The pool therefore keeps only teams posted on/after 2022-11-18 that pass
type_model.legal_in(9) (National Dex is exempt from that check: it allows past species),
with an ability on every set.

    python3 tools/rnb/make_battle_teams.py [K=4]
    RNB_OUT=generated/rnb_vs_gen7 python3 tools/rnb/make_battle_teams.py 4 --gen7

--gen7 draws the opponents from gen 7 instead -- the ceiling the boss generator works
under (Realidea's dex stops at gen 7), so it is the fair baseline for generator teams.
Same filters with gen 7's launch date and legality, and every team carrying a Z-crystal
is DROPPED (80% of them): Realidea has no Z-move engine, and swapping the crystal for
another item would quietly weaken four teams in five. Tate and Liza are left out of the
schedule rather than played and discarded.
"""
import collections
import json
import os
import random
import re
import sys

from paths import DUMP, OUT, RNB, TOOLS, out, pokedex

sys.path.insert(0, TOOLS)
import type_model as TM  # noqa: E402

GEN9_START = "2022-11-18"
POOL_FORMATS = ("gen9nationaldex", "gen9ubers", "gen9anythinggoes")
GEN7_START = "2016-11-18"
GEN7_FORMATS = ("gen7ou", "gen7ubers", "gen7uu", "gen7anythinggoes")
EXCLUDED = ("Leader_Tate", "Leader_Liza")
# Species gen 9 National Dex refuses although the client pokedex flags them exactly like a
# legal mega; validate_teams.js is the authority and found this one in the gen 7 pool.
UNPLAYABLE = {"greninjaash"}
ALIAS = {"enamorust": "enamorustherian"}


def first_option(s):
    """A scraped set can record a SLOT -- "Focus Blast/Dragon Pulse", "Chople Berry /
    Leftovers" -- which Showdown reads as one garbage name. Play the first option, as the
    doubles bridge does. No real move or item name contains a slash."""
    return s.split("/")[0].strip()


def tid(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


class Exporter:
    def __init__(self, dex):
        self.dex = dex
        self.mega = {(tid(e["baseSpecies"]), e["requiredItem"]): e for e in dex.values()
                     if e.get("requiredItem") and e.get("forme", "").startswith(("Mega", "Primal"))}

    def entry(self, sp):
        return self.dex[ALIAS.get(tid(sp), tid(sp))]

    def export(self, mons):
        blocks = []
        for m in mons:
            e = self.entry(m["sp"])
            name, ability = e["name"], m["ability"]
            if e.get("forme", "").startswith(("Mega", "Primal")):
                base = self.dex[tid(e["baseSpecies"])]
                name, ability = base["name"], base["abilities"]["0"]
            lines = [f"{name} @ {m['item']}" if m["item"] else name, f"Ability: {ability}", "Level: 100"]
            if m.get("nature"):
                lines.append(f"{m['nature']} Nature")
            lines += [f"- {mv}" for mv in m["moves"]]
            blocks.append("\n".join(lines))
        return "\n\n".join(blocks) + "\n"

    def bst(self, mons):
        return sum(sum(self.entry(m["sp"])["baseStats"].values()) for m in mons) / len(mons)


def singles_bosses(trainers, rows):
    """Six-mon singles bosses, one rival variant per fight. Tate and Liza are listed as
    separate 4-mon [Boss] entries but are one double battle in the game; they are exported
    (the battles were run) and excluded from every result in summarize_battles.py."""
    out_, seen = [], set()
    for t, r in zip(trainers, rows):
        if r["kind"] != "boss" or r["dbl"] or "Tag" in t["name"] or len(t["mons"]) < 4:
            continue
        if "Rival" in t["name"]:
            if r["seg"] in seen:
                continue
            seen.add(r["seg"])
        slug = re.sub(r"[^A-Za-z0-9]+", "_", t["name"].replace("[Boss]", "")).strip("_") + f"_{r['i']}"
        out_.append((slug, t, r))
    return out_


def smogon_pool(ex, gen=9):
    dex9 = TM.dex()
    formats, start = (GEN7_FORMATS, GEN7_START) if gen == 7 else (POOL_FORMATS, GEN9_START)
    dropped, pool = collections.Counter(), []
    for fmt in formats:
        with open(os.path.join(DUMP, fmt + ".json"), encoding="utf-8") as fh:
            raw = json.load(fh)
        for team in raw:
            data = team.get("data") or []
            if (team.get("date") or "") < start:
                dropped[fmt + ": posted before gen %d" % gen] += 1
                continue
            if fmt != "gen9nationaldex" and not TM.legal_in(gen, data, dex9):
                dropped[fmt + ": not gen-%d legal" % gen] += 1
                continue
            if gen == 7 and any((m.get("item") or "").endswith(" Z") for m in data):
                dropped[fmt + ": carries a Z-crystal"] += 1
                continue
            if any(tid(m["species"]) in UNPLAYABLE for m in data):
                dropped[fmt + ": species the format refuses"] += 1
                continue
            if any((m.get("ability") or "").lower() in ("", "no ability", "none") for m in data):
                dropped[fmt + ": missing ability"] += 1
                continue
            if len(data) != 6 or any(tid(m["species"]) not in ex.dex
                                     or "baseStats" not in ex.dex[tid(m["species"])] for m in data):
                continue
            if len({tid(m["species"]) for m in data}) < 6:
                continue
            mons, bst = [], 0
            for m in data:
                e = ex.dex[tid(m["species"])]
                e = ex.mega.get((tid(e.get("baseSpecies", e["name"])), m.get("item")), e)
                bst += sum(e["baseStats"].values())
                species = m["species"].replace("-Gmax", "")   # cosmetic; foul-play cannot match it
                mons.append({"sp": species, "item": first_option(m.get("item") or ""),
                             "ability": m.get("ability") or ex.dex[tid(species)]["abilities"]["0"],
                             "nature": m.get("nature") or "",
                             "moves": [first_option(mv) for mv in m.get("moves") or [] if mv]})
            if any(not x["moves"] for x in mons):
                continue
            pool.append({"fmt": fmt, "name": team.get("name") or "", "url": team.get("url", ""),
                         "bst": bst / 6, "mons": mons})
    print("dropped", dict(dropped))
    print("pool", len(pool), dict(collections.Counter(p["fmt"] for p in pool)))
    return pool


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    k = int(args[0]) if args else 4
    gen = 7 if "--gen7" in sys.argv else 9
    with open(os.path.join(RNB, "trainers.json"), encoding="utf-8") as fh:
        trainers = json.load(fh)
    with open(os.path.join(RNB, "rows.json")) as fh:
        rows = json.load(fh)
    ex = Exporter(pokedex())
    tdir = {side: os.path.join(OUT, "teams", side) for side in ("rnb", "smogon")}
    for d in tdir.values():
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(d):
            os.remove(os.path.join(d, f))

    bosses = []
    for slug, t, r in singles_bosses(trainers, rows):
        if gen == 7 and slug.startswith(EXCLUDED):
            continue
        with open(os.path.join(tdir["rnb"], slug), "w") as fh:
            fh.write(ex.export(t["mons"]))
        bosses.append({"slug": slug, "name": t["name"], "cap": r["cap"], "bst": ex.bst(t["mons"])})

    pool = smogon_pool(ex, gen)
    rng, used, pairs = random.Random(42), set(), []
    for b in bosses:
        near = sorted((p for i, p in enumerate(pool) if i not in used),
                      key=lambda p: abs(p["bst"] - b["bst"]))[:k * 5]
        for p in rng.sample(near, k):
            idx = pool.index(p)
            used.add(idx)
            slug = f"{p['fmt']}_{idx}"
            with open(os.path.join(tdir["smogon"], slug), "w") as fh:
                fh.write(ex.export(p["mons"]))
            pairs.append({"boss": b["slug"], "boss_name": b["name"], "cap": b["cap"],
                          "boss_bst": round(b["bst"]), "opp": slug, "opp_fmt": p["fmt"],
                          "opp_bst": round(p["bst"]), "opp_name": p["name"], "opp_url": p["url"]})
    with open(out("pairs.json"), "w") as fh:
        json.dump(pairs, fh, indent=1)
    print("%d bosses, %d pairings -> %s" % (len(bosses), len(pairs), out("pairs.json")))


if __name__ == "__main__":
    main()
