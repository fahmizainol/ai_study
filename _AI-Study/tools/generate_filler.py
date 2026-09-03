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

STATUS_PRIORITY = ["THUNDERWAVE", "WILLOWISP", "STUNSPORE", "SLEEPPOWDER", "HYPNOSIS",
                   "CONFUSERAY", "SCREECH", "GROWL", "LEER", "TAILWHIP", "SANDATTACK",
                   "WITHDRAW", "HARDEN", "HOWL", "WORKUP"]

def band_of(level):
    for i, cap in enumerate(BANDS):
        if level <= cap:
            return i
    return len(BANDS) - 1

def seed_for(battle):
    key = f"{battle['map']}|{battle['type']}|{battle['name']}|{len(battle['party'])}"
    return int(hashlib.sha1(key.encode()).hexdigest()[:8], 16)

def pool_for(theme, level, bst_cap, rng, curveball):
    sp, floor = D.species(), D.min_level()
    def ok(name, want_theme):
        s = sp[name]
        if not s["types"] or s["bst"] > bst_cap or floor[name] > level:
            return False
        # skip stage-1 mons whose evolution level is far behind (stale pick like lv40 Caterpie)
        evolvable = [p for p in s["evolutions"] if p[1] == "Level" and p[2].isdigit()]
        if evolvable and level > int(min(int(e[2]) for e in evolvable)) + 6:
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

def pick_moves(name, level, rng):
    s = D.species()[name]
    mv = D.moves()
    known = {}
    for lv, m in s["learnset"]:
        if lv <= level:
            known[m] = mv.get(m, {"power": 0, "type": "?", "category": "?", "accuracy": 0})
    dmg = sorted((m for m in known if known[m]["power"] > 0),
                 key=lambda m: (known[m]["power"] * (known[m]["accuracy"] or 100) / 100),
                 reverse=True)
    out = []
    # 1) best STAB
    stab = [m for m in dmg if known[m]["type"] in s["types"]]
    if stab: out.append(stab[0])
    # 2) best coverage (different type from slot 1)
    cov = [m for m in dmg if m not in out and known[m]["type"] not in
           {known[o]["type"] for o in out}]
    if cov: out.append(cov[0])
    # 3) utility/status by priority list
    for st in STATUS_PRIORITY:
        if st in known and st not in out:
            out.append(st); break
    # 4) next best damaging (different type if possible), else any known
    rest = [m for m in dmg if m not in out and known[m]["type"] not in
            {known[o]["type"] for o in out}] or [m for m in dmg if m not in out] \
           or [m for m in known if m not in out]
    if rest: out.append(rest[0])
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
    teams, skipped = [], {"boss": 0, "scaled": 0, "empty": 0, "no_arch": 0, "no_pool": 0}
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
        band = band_of(max(levels))
        bst_cap = 380 + 15 * band + a.get("bst_bonus", defaults["bst_bonus"])
        curve = a.get("curveball", defaults["curveball"])
        themed, anyt = pool_for(a["theme"], max(levels), bst_cap, rng, curve)
        if not (themed or anyt): skipped["no_pool"] += 1; continue
        mons, used = [], set()
        for lvl in levels:
            pool = anyt if (not a["theme"] or rng.random() < curve or not themed) else themed
            cand = [n for n in pool if n not in used and D.min_level()[n] <= lvl] or \
                   [n for n in (themed + anyt) if D.min_level()[n] <= lvl]
            name = rng.choice(cand)
            used.add(name)
            moves = pick_moves(name, lvl, rng)
            ev, nature, iv = spread_for(name, band, moves)
            mons.append({"species": name, "level": lvl, "moves": moves,
                         "item": None, "ability": rng.choice([0, 0, 1]) if len(D.species()[name]["abilities"]) > 1 else 0,
                         "nature": nature, "iv": iv, "ev": ev})
        if ITEM_BY_BAND[band]:
            mons[-1]["item"] = ITEM_BY_BAND[band]
        teams.append({"id": f"map{b['map']:03d}_{b['type']}_{b['name'] or 'x'}"
                            .replace(" ", "_"),
                      "map": b["map"], "type_id": b["type_id"], "class": b["type"],
                      "name": b["name"], "orig_ace_level": max(levels),
                      "cheat_tier": False, "trainer_items": [], "mons": mons})
    json.dump(teams, open(out_path, "w"), indent=1)
    print(f"{len(teams)} filler teams generated; skipped: {skipped}")

if __name__ == "__main__":
    main(sys.argv[1])
