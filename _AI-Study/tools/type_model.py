#!/usr/bin/env python3
"""Type facts, set resolution and nulls shared by the coverage analyses.

`mono_synergy.py` asks whether a monotype team answers the weaknesses its theme hands it;
`archetype_coverage.py` asks the same of a normal team, where the weakness list comes from
the six picks rather than from a theme. Neither question is the other, but both need the
same things underneath, and every one of them cost a wrong answer before it was fixed:

  * a per-generation dex (typing, abilities, items, moves) out of the pokemon-showdown
    clone, because Realidea's PBS is one gen-6-era 16-type fangame dex
  * the forme a set will actually PLAY as -- a base species plus its stone resolved to the
    Mega, and the pre-mega ability Showdown's export writes replaced by the forme's own
  * which generation a scraped team belongs to, since the dump's filenames lie
  * damage multipliers with abilities, items and Tera folded in
  * the attacking type of a move that does not carry one (Tera Blast, Weather Ball, ...)
  * one null-draw generator, so "above the null" means the same thing in both analyses

Nothing here knows what a theme or an archetype is.
"""
import collections
import json
import math
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "..", "extracted", "smogon-dump")
CACHE = os.path.join(HERE, "..", "generated", "showdown_dex.json")

GENS = (6, 7, 8, 9)
ERA = ((9, "2022-11-18"), (8, "2019-11-15"), (7, "2016-11-18"), (6, "2013-10-12"))

tid = lambda s: re.sub(r"[^a-z0-9]", "", (s or "").lower())

# ---------------------------------------------------------------- defensive effects
# Multiplicative factors an ability or item applies on top of the type chart. Only
# entries that change a damage multiplier are here: Ice Scales (special), Multiscale
# (full HP) and Filter/Solid Rock (0.75 on any SE hit) are real but not type-specific,
# so they cannot turn one named weakness into a resistance and would only blur the
# mechanism split. Each name is checked against the dex at load time -- a typo here
# would otherwise read as "no team uses this".
ABILITY_FACTOR = {
    "Volt Absorb": {"Electric": 0.0}, "Lightning Rod": {"Electric": 0.0},
    "Motor Drive": {"Electric": 0.0},
    "Water Absorb": {"Water": 0.0}, "Storm Drain": {"Water": 0.0},
    "Dry Skin": {"Water": 0.0, "Fire": 1.25},
    "Flash Fire": {"Fire": 0.0}, "Well-Baked Body": {"Fire": 0.0},
    "Sap Sipper": {"Grass": 0.0},
    "Levitate": {"Ground": 0.0}, "Earth Eater": {"Ground": 0.0},
    "Thick Fat": {"Fire": 0.5, "Ice": 0.5},
    "Heatproof": {"Fire": 0.5}, "Water Bubble": {"Fire": 0.5},
    "Purifying Salt": {"Ghost": 0.5},
    "Fluffy": {"Fire": 2.0},               # a weakness-worsener, kept for that reason
}
# Wonder Guard (Shedinja, a Bug-team regular) and Tera Shell (Terapagos, a Normal-team
# one) are not per-type and are applied in code.
ABILITY_SPECIAL = ("Wonder Guard", "Tera Shell")
ITEM_FACTOR = {"Air Balloon": {"Ground": 0.0}}
BERRY = {"Occa Berry": "Fire", "Passho Berry": "Water", "Wacan Berry": "Electric",
         "Rindo Berry": "Grass", "Yache Berry": "Ice", "Chople Berry": "Fighting",
         "Kebia Berry": "Poison", "Shuca Berry": "Ground", "Coba Berry": "Flying",
         "Payapa Berry": "Psychic", "Tanga Berry": "Bug", "Charti Berry": "Rock",
         "Kasib Berry": "Ghost", "Haban Berry": "Dragon", "Colbur Berry": "Dark",
         "Babiri Berry": "Steel", "Roseli Berry": "Fairy"}
PIVOT_MOVES = {"uturn", "voltswitch", "flipturn", "teleport", "partingshot", "batonpass",
               "chillyreception", "shedtail"}
HAZARD_REMOVAL = {"defog", "rapidspin", "courtchange", "tidyup", "mortalspin"}
RECOVERY_MOVES = {"recover", "roost", "softboiled", "milkdrink", "slackoff", "synthesis",
                  "moonlight", "morningsun", "rest", "shoreup", "strengthsap", "wish",
                  "healorder", "lifedew", "junglehealing", "matchagotcha", "aquaring",
                  "leechseed", "painsplit"}
RECOVERY_ABILITIES = {"Regenerator", "Poison Heal", "Water Absorb", "Volt Absorb",
                      "Dry Skin", "Ice Body", "Rain Dish", "Earth Eater"}
# ------------------------------------------------------------------------- dex access
def dex(force=False):
    """{gen: {species, chart, moves}} from the showdown checkout, cached.

    The cache is a build product of a gitignored clone, so it is gitignored too and
    rebuilt on demand rather than vendored."""
    if force or not os.path.exists(CACHE):
        js = os.path.join(HERE, "dump_showdown_dex.js")
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        with open(CACHE, "w") as fh:
            subprocess.run(["node", js], stdout=fh, check=True)
    with open(CACHE) as fh:
        return json.load(fh)


def check_names(d):
    """Every ability/item/move name this module keys on must exist in the dex.

    Not decoration: an ability whose name drifted (Well-Baked Body, Earth Eater) would
    silently contribute zero coverage and read as "nobody does this"."""
    abil = {a["name"] if isinstance(a, dict) else a for g in d.values()
            for s in g["species"].values() for a in s["abilities"]}
    missing = [n for n in list(ABILITY_FACTOR) + list(ABILITY_SPECIAL) + sorted(RECOVERY_ABILITIES)
               if n not in abil]
    moves = {m for g in d.values() for m in g["moves"]}
    missing += [m for m in PIVOT_MOVES | HAZARD_REMOVAL | RECOVERY_MOVES if m not in moves]
    if missing:
        raise SystemExit("names absent from the dex (typo or renamed): %s" % missing)


def multiplier(atk, types, chart):
    m = 1.0
    for t in types:
        v = chart[t].get(atk, 0)
        m *= 2 if v == 1 else 0.5 if v == 2 else 0.0 if v == 3 else 1.0
    return m


def taken(atk, mon, chart, use_item=True, use_tera=False):
    """What `atk` does to this set: chart, then ability, then item, then optional Tera.

    `use_item` is separable because Air Balloon and a resist berry answer a weakness
    exactly once, and a reader has to be able to see the coverage without them."""
    types = mon["tera"] and use_tera and [mon["tera"]] or mon["types"]
    m = multiplier(atk, types, chart)
    ab = mon["ability"]
    if ab == "Wonder Guard":
        m = m if m >= 2 else 0.0
    elif ab == "Tera Shell":
        m = min(m, 0.5)
    m *= ABILITY_FACTOR.get(ab, {}).get(atk, 1.0)
    if use_item:
        m *= ITEM_FACTOR.get(mon["item"], {}).get(atk, 1.0)
        if BERRY.get(mon["item"]) == atk and m >= 2:
            m *= 0.5
    return m


def mechanism(atk, mon, chart):
    """Why this set is not weak to `atk` -- the answer to "typing, or Sap Sipper?".

    Ordered because they stack: a Water/Ground with Levitate would otherwise be filed
    under whichever branch came first. Typing wins when typing alone is enough."""
    if multiplier(atk, mon["types"], chart) < 1:
        return "type2" if len(mon["types"]) > 1 else "type1"
    if taken(atk, mon, chart, use_item=False) < 1:
        return "ability"
    if taken(atk, mon, chart) < 1:
        return "item"
    if mon["tera"] and taken(atk, mon, chart, use_tera=True) < 1:
        return "tera"
    return None


# ----------------------------------------------------------------------- corpus load
def mega_forme(s, item, species, items, stats):
    """The forme that will be on the field, resolving a base species holding its stone.

    Both spellings are in the corpus -- 1,401 sets name the Mega forme outright and 449
    write "Venusaur @ Venusaurite" -- and only the resolved forme has the right typing and
    ability. It is not cosmetic: base Gyarados is Water/Flying and takes Electric at x4,
    Mega Gyarados is Water/Dark and takes it at x2, and Mega Venusaur's Thick Fat is a Fire
    and Ice resistance a Grass team has almost no other way to buy. The base species is
    kept separately, because Monotype reads the team's type off the base forme."""
    it = items.get(tid(item or ""))
    forme = species.get((it or {}).get("mega_map", {}).get(tid(s["name"]), ""))
    if not forme:
        return s
    stats["base species + stone resolved to the Mega forme"] += 1
    return forme


def forme_ability(recorded, species, stats):
    """The ability that will actually be on the field for this listed forme.

    4.4% of sets name an ability the listed forme cannot have, from two causes that look
    identical in the file and need opposite handling:

      Showdown's export writes the PRE-MEGA ability, because that is what the team sheet
      carries -- "Venusaur-Mega / Chlorophyll" will play as Thick Fat, and "Houndoom-Mega
      / Flash Fire" as Solar Power. A mega forme has exactly one ability, so the real one
      is unambiguous: substituting it both found the Fire/Ice resistance Thick Fat grants
      a gen 6-7 Grass team and removed a Flash Fire that was never going to fire.

      The rest are author error or a set written for another generation (Gengar with
      Levitate, which it lost in gen 7; Glimmora with Earth Eater). The forme has several
      abilities and nothing says which was meant, so the ability is dropped rather than
      guessed -- 52 answer slots in the first run rested on one of these.
    """
    legal = species["abilities"]
    if not recorded or recorded in legal:
        return recorded
    if len(legal) == 1:
        stats["ability replaced by the forme's own (pre-mega export)"] += 1
        return legal[0]
    stats["ability illegal for the forme, dropped"] += 1
    return ""


def tera_type(raw, gen, d, stats):
    """A usable defensive Tera type, or None.

    Three ways this is None and each one matters: the scrape keeps the author's casing
    ("ground"), pre-gen-9 sets have no Tera at all, and **Tera Stellar leaves the
    holder's types alone** -- counting it as a re-typing would invent resistances that
    the mechanic does not grant."""
    if gen != 9 or not raw:
        return None
    t = str(raw).strip().title()
    if t == "Stellar":
        stats["tera Stellar (no type change)"] += 1
        return None
    if t not in d["gen9"]["chart"]:
        stats["tera unparsed: %s" % raw] += 1
        return None
    return t


def gen_from_date(date):
    for gen, start in ERA:
        if (date or "") >= start:
            return gen
    return 6


def legal_in(gen, sets, d):
    """Could this team have been built in `gen`? Species and items only.

    Moves are deliberately not part of the veto: the scrape carries mangled move lines
    (an author's note parsed as a move), and one bad line would otherwise disqualify a
    generation for the whole team. Move legality is reported as a cross-check instead."""
    species, items = d["gen%d" % gen]["species"], d["gen%d" % gen]["items"]
    for m in sets:
        s = species.get(tid(m["species"]))
        if not s or s["nonstandard"]:
            return False
        if m.get("item"):
            it = items.get(tid(m["item"]))
            if it and it["nonstandard"]:
                return False
    return True


def infer_gen(team, d):
    """(gen, how) for one scraped team, or (None, why) if no generation fits.

    The post date leads because almost every gen 6 team is also legal in gen 7 -- megas
    survived the transition -- so "latest generation everything is legal in" would file
    the whole gen 6 era as gen 7. Legality only vetoes: a 2024 post holding Victini is
    an older team re-posted, or a National Dex team in the same subforum."""
    cands = [g for g in GENS if legal_in(g, team["data"], d)]
    if not cands:
        return None, "no legal generation"
    dg = gen_from_date(team.get("date", ""))
    if dg in cands:
        return dg, "date"
    below = [g for g in cands if g < dg]
    return (max(below) if below else min(cands)), "legality veto"



def switchin_quality(mon):
    mv = set(mon["moves"])
    return {"pivot": bool(mv & PIVOT_MOVES),
            "recovery": bool(mv & RECOVERY_MOVES) or mon["ability"] in RECOVERY_ABILITIES
                        or mon["item"] == "Leftovers",
            "removal": bool(mv & HAZARD_REMOVAL)}


def _spread(hit, counts, n):
    mean = sum(counts) / n
    var = sum((c - mean) ** 2 for c in counts) / n
    return {"share": hit / n, "mean": mean, "var": var,
            "exactly1": sum(1 for c in counts if c == 1) / n}


def null_draws(teams, n, rng):
    """`n` random six-set teams from this theme's own observed pool, species-weighted.

    Species frequency and each species' own set distribution are both preserved -- a drawn
    species carries one of the sets it was really given -- so the only thing this destroys
    is which sets appeared together. Species Clause is kept: a draw that repeats a species
    is rejected, as real teams cannot repeat one. Shared by the defensive and offensive
    nulls so that "above the null" means the same thing in both halves."""
    pool = collections.defaultdict(list)
    for t in teams:
        for m in t["mons"]:
            pool[m["species"]].append(m)
    if len(pool) < 6:
        return
    names = list(pool)
    wt = [len(pool[k]) for k in names]
    for _ in range(n):
        pick, seen = [], set()
        while len(pick) < 6:
            k = rng.choices(names, wt)[0]
            if k in seen:
                continue
            seen.add(k)
            pick.append(rng.choice(pool[k]))
        yield pick


# ------------------------------------------------------------------------- the offence
# A theme's weakness list doubles as its threat list: in this tier the Grass attacks that
# hit a Water team come from a Grass TEAM, so "can we answer Grass" also asks whether we
# can hit Grass back. That second half is not symmetric with the first -- a coverage move
# costs one of four slots on any member, where a defensive answer costs a team slot and a
# species that exists -- and the two interact: the theme's own STAB is resisted by some of
# the very types that threaten it (Ice into Steel, Water into Grass), which is when a
# coverage move stops being optional.
WEATHER_BALL = {"Drought": "Fire", "Orichalcum Pulse": "Fire", "Drizzle": "Water",
                "Primordial Sea": "Water", "Snow Warning": "Ice", "Sand Stream": "Rock",
                "Sand Spit": "Rock", "Desolate Land": "Fire"}
# Moves whose type follows the user's own forme rather than the move: on a monotype team
# these are STAB by construction and can never be the off-type coverage this section is
# looking for, which is worth stating rather than leaving them miscounted as Normal.
SELF_TYPED = {"judgment", "multiattack", "revelationdance", "ragingbull", "aurawheel"}
DYNAMIC_UNRESOLVED = {"terrainpulse", "technoblast", "naturalgift"}
def attack_types(name, mon, team, moves, unresolved=None):
    """Attacking types a move can actually come out as, [] if it does no damage.

    Five moves do not carry their own type and all five are in this corpus: Tera Blast
    becomes the declared Tera type (that is the entire point of the move), Ivy Cudgel
    Ogerpon's non-Grass half, Weather Ball the weather a TEAMMATE sets, and Judgment,
    Multi-Attack, Revelation Dance, Raging Bull and Aura Wheel the user's own typing."""
    rec = moves.get(name)
    if not rec or rec["bp"] <= 0:
        return []
    if name == "terablast":
        return [mon["tera"]] if mon["tera"] else [rec["type"]]
    if name == "ivycudgel":
        return [t for t in mon["types"] if t != "Grass"] or [rec["type"]]
    if name == "weatherball":
        setters = {WEATHER_BALL[m["ability"]] for m in team["mons"]
                   if m["ability"] in WEATHER_BALL}
        return sorted(setters) or [rec["type"]]
    if name in SELF_TYPED:
        return list(mon["types"])
    if name in DYNAMIC_UNRESOLVED:
        if unresolved is not None:
            unresolved[name] += 1
        return []
    return [rec["type"]]


def best_into(target, mon, team, chart, moves, off_type_only=False):
    """Best multiplier this set can put into a defender typed `target` (a type or list)."""
    types = [target] if isinstance(target, str) else list(target)
    best = 0.0
    for name in mon["moves"]:
        for at in attack_types(name, mon, team, moves):
            if off_type_only and at == team["theme"]:
                continue
            best = max(best, multiplier(at, types, chart))
    return best


def bodies(teams, key=lambda t: (t["gen"], t["theme"])):
    """{(gen, theme): Counter of type-combination -> appearances}.

    The realistic defender. "Ice Beam is super effective on Grass" is true of a pure Grass
    body and false of Ferrothorn, so coverage measured against the bare threatening type
    overstates what a move does to the team that actually shows up."""
    out = collections.defaultdict(collections.Counter)
    for t in teams:
        for m in t["mons"]:
            out[key(t)][tuple(m["types"])] += 1
    return out


# ---------------------------------------------------------------------------- report
def ztest(p_obs, n_obs, p_null, n_null):
    """Two-sided p for "this share differs from the null's share".

    The null's own sampling error is in the denominator: it is a Monte Carlo estimate,
    not a known probability, and with 4000 draws against 40-odd teams it is the smaller
    of the two errors but not zero."""
    if not n_obs or p_null in (0.0, 1.0) and p_obs == p_null:
        return 1.0
    v = p_null * (1 - p_null) * (1 / n_obs + 1 / max(n_null, 1))
    if v <= 0:
        return 1.0
    z = abs(p_obs - p_null) / math.sqrt(v)
    return math.erfc(z / math.sqrt(2))


