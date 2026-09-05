#!/usr/bin/env python3
"""Deterministic filler-team generator (TEAM-DESIGN.md §6.5 lever 3).

For every 1-2 mon generic battle in extracted/realidea-battles.json, build a
replacement party from the trainer class's archetype + the stage-table knobs.
Everything is picked from parsed PBS data, so output is legal by construction;
run validate_team.py (slack 0) over the result anyway.

Skips: boss-class battles (LLM tier), battles with non-integer (scaled) levels,
battles with empty parties. Seeded per battle -> reproducible.

Usage: generate_filler.py <out_teams.json>
"""
import json, sys, os, random, hashlib
import realidea_data as D

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "..", "generated")
EXTRACTED = os.path.join(HERE, "..", "extracted")

BOSS = {'LIDER','CAMUS','LILLIANA','FINALILLIANA','JEREMIAH','JEREBUZO','SILVER','KENN',
        'AIMI','ALBA','TERESA','OWEN1','OWEN2','DANTE','DOUGLAS','CIARA','DHARA','MESPRIT',
        'ATLAS','CINTIA','ELLIOT','EDWARD','ARDILLO','BAY','SIMON','FANTASMA','OWENCHUNGO',
        'OWENPARTNERFINAL','BEA','NATASHA','ASTER','SARA','PRIMS'}

# stage bands = gym caps (§6.2); band index = fights before that gym
BANDS = [14, 20, 26, 33, 38, 40, 45, 48, 51, 100]
# generic-tier knobs per band (a step below bosses, per §6.5 / Intense aggregate)
IV_BY_BAND   = [12, 14, 16, 18, 20, 22, 24, 26, 28, 31]
EVB_BY_BAND  = [0, 0, 0, 120, 120, 240, 240, 300, 300, 400]   # EV budget
ITEM_BY_BAND = [None, None, None, "ORANBERRY", "ORANBERRY",
                "SITRUSBERRY", "SITRUSBERRY", "SITRUSBERRY", "SITRUSBERRY", "SITRUSBERRY"]
# soft move-power ceiling per band — filler gets TM access now, but the best moves
# unlock with the curve so an early-route grunt can't open with a 95-BP nuke. If a
# mon has no damaging move under the cap, its weakest available is used instead.
BP_CAP_BY_BAND = [50, 58, 66, 72, 78, 84, 90, 96, 105, 999]
# party size (min, max) per band — Reborn's generics grow 1-2 early to 3-4 late
# (mined avgs: lv1-20 1.8, lv21-35 2.6, lv71+ 2.9); never shrinks an original party
N_BY_BAND = [(1, 2), (1, 2), (2, 2), (2, 3), (2, 3),
             (3, 3), (3, 3), (3, 4), (3, 4), (3, 4)]

# status/setup worth a slot even for filler (a future smart AI can leverage all of
# these). Deliberately excludes single-shot enemy stat-drops (Growl/Leer/Tail Whip/
# Sand Attack) and marginal self-buffs (Withdraw/Harden) — those just waste a slot.
STATUS_PRIORITY = ["THUNDERWAVE", "WILLOWISP", "STUNSPORE", "SLEEPPOWDER", "HYPNOSIS",
                   "CONFUSERAY", "SWORDSDANCE", "NASTYPLOT", "DRAGONDANCE", "BULKUP",
                   "CALMMIND", "WORKUP", "HOWL", "SCREECH"]

def band_of(level):
    for i, cap in enumerate(BANDS):
        if level <= cap:
            return i
    return len(BANDS) - 1

def seed_for(battle):
    key = f"{battle['map']}|{battle['type']}|{battle['name']}|{len(battle['party'])}"
    return int(hashlib.sha1(key.encode()).hexdigest()[:8], 16)

def pool_for(theme, level, bst_cap, rng, curveball):
    """Species pool for GENERATED growth slots only (originals are kept as-is).
    Excludes mons that should have evolved by now, so extras aren't babies."""
    sp, floor = D.species(), D.min_level()
    def ok(name, want_theme):
        s = sp[name]
        if not s["types"] or s["bst"] > bst_cap or floor[name] > level:
            return False
        # skip stage-1 mons whose evolution level is far behind (stale pick like lv40 Caterpie)
        evolvable = [p for p in s["evolutions"] if p[1] == "Level" and p[2].isdigit()]
        if evolvable and level > int(min(int(e[2]) for e in evolvable)) + 6:
            return False
        # non-level evolutions (item/happiness/trade/move) carry no level floor, so a
        # baby like Bonsly/Jigglypuff would otherwise pass at lv50. From mid-game on,
        # skip any still-evolvable mon that is clearly weaker than the band ceiling.
        if s["evolutions"] and level >= 30 and s["bst"] < bst_cap - 40:
            return False
        if want_theme and theme and not (set(s["types"]) & set(theme)):
            return False
        # needs at least 2 damaging level-up moves at this level
        dmg = [m for lv, m in s["learnset"] if lv <= level
               and D.moves().get(m, {}).get("power", 0) > 0]
        return len(set(dmg)) >= 2
    themed = [n for n in sp if ok(n, True)]
    anyt   = [n for n in sp if ok(n, False)]
    return themed, anyt

def pick_moves(name, level, rng, band=None):
    """Best legal set from level-up AND TM moves (filler now gets TM access), with a
    per-band BP ceiling so power scales with the curve. No over-level moves (slack 0)."""
    s = D.species()[name]
    mv = D.moves()
    known = {}
    for m in mv:
        how = D.learnable(name, m, level, slack=0)
        if how and not (isinstance(how, str) and how.startswith("levelup+")):
            known[m] = mv[m]
    cap = BP_CAP_BY_BAND[band] if band is not None else 999
    dmg_all = [m for m in known if known[m]["power"] > 0]
    dmg_capped = [m for m in dmg_all if known[m]["power"] <= cap]
    # rank damaging moves by (matches the mon's attacking bias, then power*acc). This
    # stops universal Normal TMs (Facade/Retaliate/Strength) from crowding out a
    # special attacker's real STAB and skewing the EV spread toward the wrong stat.
    phys_bias = s["base_stats"][1] >= s["base_stats"][4]   # Atk vs SpA
    def score(m):
        pw = known[m]["power"] * (known[m]["accuracy"] or 100) / 100
        matches = (known[m]["category"] == "Physical") == phys_bias
        return (matches, pw)
    dmg = sorted(dmg_capped or dmg_all, key=score, reverse=True)
    out = []
    stab = [m for m in dmg if known[m]["type"] in s["types"]]
    # 1) best STAB
    if stab: out.append(stab[0])
    # 2) second STAB of the OTHER type (dual-type mons show both STABs, e.g. a
    #    Ground/Rock mon gets Dig + Rock Slide instead of Dig + Normal filler)
    if len(s["types"]) > 1 and out:
        stab2 = [m for m in stab if m not in out and known[m]["type"] != known[out[0]]["type"]]
        if stab2: out.append(stab2[0])
    # 3) best coverage (type not yet present)
    if len(out) < 3:
        cov = [m for m in dmg if m not in out and known[m]["type"] not in
               {known[o]["type"] for o in out}]
        if cov: out.append(cov[0])
    # 4) one genuinely useful status/setup move by priority
    for st in STATUS_PRIORITY:
        if st in known and st not in out and len(out) < 4:
            out.append(st); break
    # 5) fill any remaining slots with the next best damaging move
    while len(out) < 4:
        rest = [m for m in dmg if m not in out]
        if not rest: break
        out.append(rest[0])
    return out[:4] or list(known)[:1]

def spread_for(name, band, chosen_moves):
    """EV spread + nature following the picked moveset's dominant damage category
    (falls back to base stats for all-status sets); IV from band."""
    s = D.species()[name]
    bs = s["base_stats"]          # PBS order: HP, Atk, Def, Spd, SpA, SpDef
    mv = D.moves()
    phys_pw = sum(mv[m]["power"] for m in chosen_moves
                  if mv.get(m, {}).get("category") == "Physical")
    spec_pw = sum(mv[m]["power"] for m in chosen_moves
                  if mv.get(m, {}).get("category") == "Special")
    physical = phys_pw >= spec_pw if (phys_pw or spec_pw) else bs[1] >= bs[4]
    budget = EVB_BY_BAND[band]
    ev = [0] * 6
    if budget:
        atk_i = 1 if physical else 4
        ev[atk_i] = min(252, budget // 2)
        ev[3] = min(252, budget - ev[atk_i])
    nature = ("ADAMANT" if physical else "MODEST") if budget else "HARDY"
    return ev, nature, IV_BY_BAND[band]

def main(out_path):
    battles = json.load(open(os.path.join(EXTRACTED, "realidea-battles.json")))
    arch = json.load(open(os.path.join(GEN, "archetypes.json")))
    defaults = arch["_defaults"]
    sp = D.species()
    teams, skipped = [], {"boss": 0, "scaled": 0, "empty": 0, "no_arch": 0,
                          "no_pool": 0, "unknown_species": 0}
    for b in battles:
        if b["type"] in BOSS: skipped["boss"] += 1; continue
        if not b["party"]: skipped["empty"] += 1; continue
        if not all(isinstance(m["level"], int) for m in b["party"]):
            skipped["scaled"] += 1; continue
        if len(b["party"]) >= 3: continue   # mini tier -> LLM batch
        a = arch.get(b["type"])
        if a is None: skipped["no_arch"] += 1; print("no archetype:", b["type"]); continue
        rng = random.Random(seed_for(b))
        levels = [m["level"] for m in b["party"]]
        ace_level = max(levels)
        band = band_of(ace_level)

        # 1) KEEP the original species; just re-equip them for the band (moves/item/
        #    IV/EV/nature). Original picks are guaranteed available + level-appropriate,
        #    which also sidesteps the baby-at-high-level problem entirely.
        def build(name, lvl, kept):
            moves = pick_moves(name, lvl, rng, band)
            ev, nature, iv = spread_for(name, band, moves)
            return {"species": name, "level": lvl, "moves": moves, "item": None,
                    "ability": rng.choice([0, 0, 1]) if len(sp[name]["abilities"]) > 1 else 0,
                    "nature": nature, "iv": iv, "ev": ev, "kept": kept}
        mons, used = [], set()
        for m in b["party"]:
            if m["species"] not in sp:      # typo'd/placeholder species -> can't upgrade
                continue
            used.add(m["species"])
            mons.append(build(m["species"], m["level"], True))   # kept original
        if not mons: skipped["unknown_species"] += 1; continue

        # 2) Only if the band wants a bigger party, GENERATE extra mons (themed pool +
        #    evolution guard) at ace level - 1, so the original ace stays the ace.
        lo, hi = N_BY_BAND[band]
        target = max(len(mons), rng.randint(lo, hi))
        if target > len(mons):
            bst_cap = 380 + 15 * band + a.get("bst_bonus", defaults["bst_bonus"])
            curve = a.get("curveball", defaults["curveball"])
            xlvl = max(2, ace_level - 1)
            themed, anyt = pool_for(a["theme"], xlvl, bst_cap, rng, curve)  # floor<=build lvl
            while len(mons) < target and (themed or anyt):
                pool = anyt if (not a["theme"] or rng.random() < curve or not themed) else themed
                cand = [n for n in pool if n not in used and D.min_level()[n] <= xlvl] or \
                       [n for n in (themed + anyt) if n not in used and D.min_level()[n] <= xlvl]
                if not cand: break
                name = rng.choice(cand); used.add(name)
                mons.append(build(name, xlvl, False))   # generated growth slot

        mons.sort(key=lambda m: m["level"])      # ace (highest) last
        if ITEM_BY_BAND[band]:
            mons[-1]["item"] = ITEM_BY_BAND[band]
        teams.append({"id": f"map{b['map']:03d}_{b['type']}_{b['name'] or 'x'}"
                            .replace(" ", "_"),
                      "map": b["map"], "type_id": b["type_id"], "class": b["type"],
                      "name": b["name"], "orig_ace_level": ace_level,
                      "cheat_tier": False, "trainer_items": [], "mons": mons})
    json.dump(teams, open(out_path, "w"), indent=1)
    print(f"{len(teams)} filler teams generated; skipped: {skipped}")

if __name__ == "__main__":
    main(sys.argv[1])
