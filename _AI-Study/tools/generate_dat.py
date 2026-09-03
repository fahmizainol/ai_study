#!/usr/bin/env python3
"""Generate replacement teams for Realidea's trainers.dat trainers — the ~16
early-game / rival fights invoked via pbTrainerBattle -> pbLoadTrainer, the path
the inline-createTrainer pipeline (generate_filler.py) does NOT cover.

Reuses generate_filler's archetype + stage logic. Output keys each team by
[type_id, name, partyid] so the pbLoadTrainer override matches the same tuple
pbLoadTrainer itself uses to find the trainer in trainers.dat.

Usage: generate_dat.py <out_teams_dat.json>
"""
import json, sys, os, random, hashlib
import realidea_data as D
import generate_filler as G

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "..", "generated")

def main(out_path):
    import marshal_rb
    RB = "/mnt/c/Users/kny/Documents/Games/Norm/Realidea V4.1/Data"
    sid = D.species_by_id()
    tt = marshal_rb.load(os.path.join(RB, "trainertypes.dat"))
    tname = {i: (r[1] if r and len(r) > 1 else str(i)) for i, r in enumerate(tt)}
    dat = marshal_rb.load(os.path.join(RB, "trainers.dat"))
    arch = json.load(open(os.path.join(GEN, "archetypes.json")))
    defaults = arch["_defaults"]

    teams, skipped = [], {"no_arch": 0, "no_pool": 0}
    for e in dat:
        tid, name, items, party, pid = e[0], e[1], e[2], e[3], e[4]
        cls = tname.get(tid)
        levels = [m[1] for m in party]
        a = arch.get(cls)
        if a is None:
            skipped["no_arch"] += 1
            print(f"no archetype for {cls} ({name!r}) — left as original")
            continue
        # seed on the dat identity so regeneration is reproducible
        rng = random.Random(int(hashlib.sha1(
            f"dat|{tid}|{name}|{pid}".encode()).hexdigest()[:8], 16))
        band = G.band_of(max(levels))
        # keep original party size (dat fights are small, early — no growth here)
        bst_cap = 380 + 15 * band + a.get("bst_bonus", defaults["bst_bonus"])
        curve = a.get("curveball", defaults["curveball"])
        themed, anyt = G.pool_for(a["theme"], max(levels), bst_cap, rng, curve)
        if not (themed or anyt):
            skipped["no_pool"] += 1; continue
        mons, used = [], set()
        for lvl in levels:
            pool = anyt if (not a["theme"] or rng.random() < curve or not themed) else themed
            cand = [n for n in pool if n not in used and D.min_level()[n] <= lvl] or \
                   [n for n in (themed + anyt) if D.min_level()[n] <= lvl]
            nm = rng.choice(cand); used.add(nm)
            moves = G.pick_moves(nm, lvl, rng)
            ev, nature, iv = G.spread_for(nm, band, moves)
            mons.append({"species": nm, "level": lvl, "moves": moves, "item": None,
                         "ability": rng.choice([0, 0, 1]) if len(D.species()[nm]["abilities"]) > 1 else 0,
                         "nature": nature, "iv": iv, "ev": ev})
        if G.ITEM_BY_BAND[band]:
            mons[-1]["item"] = G.ITEM_BY_BAND[band]
        teams.append({"id": f"dat_{cls}_{name}_{pid}".replace(" ", "_"),
                      "type_id": tid, "class": cls, "name": name, "partyid": pid,
                      # encoding-proof match key: numeric species ids of the ORIGINAL
                      # party (sorted) + ace level. pbLoadTrainer builds this party
                      # first; the override matches on it, sidestepping mojibake
                      # names/placeholders. Ace level separates same-species re-fights.
                      "orig_species_ids": sorted(m[0] for m in party),
                      "orig_ace_level": max(levels),
                      "orig_species": [sid.get(m[0], m[0]) for m in party],
                      "cheat_tier": False, "trainer_items": [], "mons": mons})
    json.dump(teams, open(out_path, "w"), indent=1)
    print(f"{len(teams)} dat teams generated; skipped: {skipped}")

if __name__ == "__main__":
    main(sys.argv[1])
