#!/usr/bin/env python3
"""Does a monotype team cover the weaknesses its theme type hands it?

A Water team is weak to Grass and Electric before it picks a single Pokemon. The
question this asks is whether real teams answer that -- with a second type
(Water/Ground eats Electric), an ability (Sap Sipper, Volt Absorb), an item (Air
Balloon, a resist berry) or a defensive Tera -- and whether they do it more than the
species pool would give them for free.

Two nulls, because "they cover it" can mean two different things:

  pool  each theme's legal species drawn uniformly. Tests whether the species
        monotype players actually use cover better than the ones they could use.
  team  the theme's own species drawn with their observed frequency, each carrying
        one of its own observed sets. Marginals are preserved exactly, so this tests
        per-team coordination only: whether a builder who already has five members
        reaches for the sixth that patches the hole.

Type/ability/move facts come from the pokemon-showdown checkout via
dump_showdown_dex.js, not from tools/realidea_data.py: that PBS is one gen-6-era
16-type dex with a fangame's edits, and this corpus is gens 7-9 with Fairy, gen 9
species and gen 9 abilities.

  python3 tools/mono_synergy.py                  # the whole report, gen 9
  python3 tools/mono_synergy.py --gen 7 8 9      # stability across generations
  python3 tools/mono_synergy.py --theme Water    # one theme, with its answer species
  python3 tools/mono_synergy.py --json out.json  # per-team records
"""
import argparse
import collections
import json
import math
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "..", "extracted", "smogon-dump")
CACHE = os.path.join(HERE, "..", "generated", "showdown_dex.json")

# NEITHER the filename's tier NOR its generation can be taken at face value.
#
#   gen6monotype.json is not monotype at all: its 30 teams are one "Any Ability"
#   thread (Barraskewda, Zapdos-Galar on a gen 6 list), and 30 of 30 have no type
#   shared by all six members.
#
#   gen9monotype.json is not gen 9. It is the monotype subforum's whole history --
#   posts dated from 2014-03, 1827 teams holding a mega stone, and 2428 of 4337
#   containing a species that does not exist in gen 9. Grouping it by filename would
#   have scored gen 6 and gen 7 teams against the gen 9 dex, which is how a Mega
#   Swampert ends up reported as a gen 9 Water answer.
#
# So the tier is validated structurally (all six members share a type) and the
# generation is inferred per team from the post date, vetoed by legality.
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



def read_teams(gens):
    """(gen, theme, [set]) per monotype team whose six species all resolve.

    Theme is the type shared by every member. Where a listed forme breaks that -- a
    Mega whose typing differs from its base, which is how Monotype allows Charizard-
    Mega-X on Fire -- the base formes decide the theme while the listed forme keeps
    its own typing for every multiplier below, because the listed forme is what takes
    the hit."""
    d = dex()
    check_names(d)
    out, stats = [], collections.Counter()
    for fname in ("gen7monotype.json", "gen8monotype.json", "gen9monotype.json"):
        for team in json.load(open(os.path.join(DUMP, fname), encoding="utf-8")):
            data = team.get("data") or []
            stats["scraped records"] += 1
            if len(data) != 6:
                stats["not six mons"] += 1
                continue
            gen, how = infer_gen(team, d)
            if gen is None:
                stats["no legal generation"] += 1
                continue
            stats["gen%d (%s)" % (gen, how)] += 1
            if gen not in gens:
                continue
            species, items = d["gen%d" % gen]["species"], d["gen%d" % gen]["items"]
            mons = []
            for m in data:
                s = species.get(tid(m["species"]))
                if not s:
                    break
                s = mega_forme(s, m.get("item"), species, items, stats)
                base = species[s["base"]]
                ability = forme_ability(m.get("ability") or "", s, stats)
                mons.append({
                    "species": s["name"], "types": s["types"],
                    # Gastrodon-East and Gastrodon are one answer, not two: merge a
                    # forme back into its base only when typing and BST are identical,
                    # which keeps Swampert-Mega separate from Swampert.
                    "display": base["name"] if (s["types"] == base["types"]
                                                and s["bst"] == base["bst"]) else s["name"],
                    "base_types": base["types"],
                    "ability": ability, "item": m.get("item") or "",
                    "tera": tera_type(m.get("teraType"), gen, d, stats),
                    "item_legal": not (d["gen%d" % gen]["items"].get(tid(m.get("item") or ""), {}) or {}).get("nonstandard"),
                    "moves": [tid(x) for x in m.get("moves") or ()],
                })
            if len(mons) != 6:
                stats["species unresolved"] += 1
                continue
            for key in ("types", "base_types"):
                theme = set(mons[0][key]).intersection(*[set(x[key]) for x in mons[1:]])
                if theme:
                    break
            if len(theme) != 1:
                stats["no single shared type" if not theme else "ambiguous theme"] += 1
                continue
            out.append({"gen": gen, "how": how, "theme": theme.pop(), "mons": mons,
                        "url": team.get("url", ""), "name": team.get("name", "")})
            stats["usable"] += 1
    return out, stats


def typing_answer_possible(theme, atk, chart):
    """Can ANY second type take `theme`'s x2 weakness to `atk` below neutral?

    Derived, not assumed. A monotype member's multiplier is 2 x m(atk -> U) for its
    second type U, and the chart only ever contributes 2, 1, 0.5 or 0 -- so the product
    is under 1 only when m is 0. Every typing-based answer on a monotype team is
    therefore an IMMUNITY, and for the ten attacking types nothing is immune to, no
    second type helps at all and an ability or item is the only route. This returns the
    immune types so the claim is read off the chart each run instead of trusted."""
    return [u for u in chart if multiplier(atk, [theme, u], chart) < 1]


def weaknesses(theme, chart):
    return sorted(a for a, v in chart[theme].items() if v == 1)


# -------------------------------------------------------------------------- scoring
def score(team, chart):
    """Per theme weakness: how many members switch in, and by what mechanism.

    `answers` is the count that takes less than neutral damage -- the mon you can
    actually click a switch to. `neutral_only` is the weakness where the best the team
    can do is take x1, which on a 2x theme still means every member is a liability."""
    out = {}
    for atk in weaknesses(team["theme"], chart):
        rows = []
        for m in team["mons"]:
            rows.append({"species": m["species"],
                         # typing only -- the one the pool null is comparable to
                         "type_only": multiplier(atk, m["types"], chart),
                         "no_item": taken(atk, m, chart, use_item=False),
                         "full": taken(atk, m, chart),
                         "mech": mechanism(atk, m, chart), "mon": m})
        hard = [r for r in rows if r["full"] < 1]
        out[atk] = {
            "answers": len(hard),
            "answers_no_item": sum(1 for r in rows if r["no_item"] < 1),
            "answers_typing": sum(1 for r in rows if r["type_only"] < 1),
            "best": min(r["full"] for r in rows),
            "still_weak": sum(1 for r in rows if r["full"] >= 2),
            "mechs": collections.Counter(r["mech"] for r in hard),
            "who": [(r["species"], r["mech"], r["full"]) for r in hard],
            "rows": rows,
        }
    return out


def switchin_quality(mon):
    mv = set(mon["moves"])
    return {"pivot": bool(mv & PIVOT_MOVES),
            "recovery": bool(mv & RECOVERY_MOVES) or mon["ability"] in RECOVERY_ABILITIES
                        or mon["item"] == "Leftovers",
            "removal": bool(mv & HAZARD_REMOVAL)}


# ----------------------------------------------------------------------------- nulls
def null_pool(theme, gen, d, n, rng):
    """Uniform draw from every species of `theme` legal in `gen` -- the pool-level null.

    Typing only: a legal species has no chosen ability or item, so comparing it to real
    teams' full coverage would compare two different measurements. Real teams are
    scored the same way (bare typing) wherever this null is quoted."""
    species = d["gen%d" % gen]["species"]
    legal = [s for s in species.values() if theme in s["types"] and not s["nonstandard"]]
    chart = d["gen%d" % gen]["chart"]
    weak = weaknesses(theme, chart)
    hits = collections.Counter(); counts = collections.defaultdict(list)
    for _ in range(n):
        pick = rng.sample(legal, 6) if len(legal) >= 6 else [rng.choice(legal) for _ in range(6)]
        for atk in weak:
            c = sum(1 for s in pick if multiplier(atk, s["types"], chart) < 1)
            hits[atk] += c > 0
            counts[atk].append(c)
    return {a: _spread(hits[a], counts[a], n) for a in weak}


def _spread(hit, counts, n):
    mean = sum(counts) / n
    var = sum((c - mean) ** 2 for c in counts) / n
    return {"share": hit / n, "mean": mean, "var": var,
            "exactly1": sum(1 for c in counts if c == 1) / n}


def null_team(theme, gen, teams, chart, n, rng):
    """Draw six sets from this theme's own observed pool, species-weighted.

    Species frequency and each species' own ability/item/tera distribution are both
    preserved -- a drawn species carries one of the sets it was really given -- so the
    only thing this destroys is which sets appeared together. Species Clause is kept:
    a redraw that repeats a species is rejected, as real teams cannot repeat one."""
    pool = collections.defaultdict(list)
    for t in teams:
        if t["theme"] != theme or t["gen"] != gen:
            continue
        for m in t["mons"]:
            pool[m["species"]].append(m)
    if len(pool) < 6:
        return None
    names = list(pool)
    wt = [len(pool[k]) for k in names]
    weak = weaknesses(theme, chart)
    hits = collections.Counter(); counts = collections.defaultdict(list)
    for _ in range(n):
        pick, seen = [], set()
        while len(pick) < 6:
            k = rng.choices(names, wt)[0]
            if k in seen:
                continue
            seen.add(k); pick.append(rng.choice(pool[k]))
        for atk in weak:
            c = sum(1 for m in pick if taken(atk, m, chart) < 1)
            hits[atk] += c > 0
            counts[atk].append(c)
    return {a: _spread(hits[a], counts[a], n) for a in weak}


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


def summarise(teams, d, gen, theme, trials, rng):
    """One row per weakness of `theme`, with both nulls beside the observed share."""
    chart = d["gen%d" % gen]["chart"]
    ts = [t for t in teams if t["gen"] == gen and t["theme"] == theme]
    if not ts:
        return []
    scored = [score(t, chart) for t in ts]
    npool = null_pool(theme, gen, d, trials, rng)
    nteam = null_team(theme, gen, teams, chart, trials, rng)
    rows = []
    for atk in weaknesses(theme, chart):
        n = len(ts)
        res = sum(1 for s in scored if s[atk]["answers"] > 0) / n
        bare = sum(1 for s in scored if s[atk]["answers_typing"] > 0) / n
        mech = collections.Counter()
        for s in scored:
            mech.update(s[atk]["mechs"])
        # Tera counts only where nothing else answers: a defensive Tera is a real out,
        # but a team with Swampert did not need it, and counting both would double-count
        # the same weakness.
        # A Tera that resists is not proof of defensive intent: Tera Poison on Toxapex
        # resists Grass and is also its own STAB. Only an OFF-TYPE Tera -- one the set
        # does not already have -- is a typing chosen for the matchup, so the two are
        # counted apart and never added together.
        tera_any = tera_off = 0
        for s in scored:
            if s[atk]["answers"]:
                continue
            fix = [r["mon"] for r in s[atk]["rows"]
                   if r["mon"]["tera"] and taken(atk, r["mon"], chart, use_tera=True) < 1]
            tera_any += bool(fix)
            tera_off += any(m["tera"] not in m["types"] for m in fix)
        tera_only, tera_offtype = tera_any / n, tera_off / n
        counts = [s[atk]["answers"] for s in scored]
        omean = sum(counts) / n
        ovar = sum((c - omean) ** 2 for c in counts) / n
        rows.append({
            "gen": gen, "theme": theme, "atk": atk, "n": n,
            "resist": res, "bare": bare,
            "mean": sum(s[atk]["answers"] for s in scored) / n,
            "neutral_only": sum(1 for s in scored if s[atk]["answers"] == 0
                                and s[atk]["best"] <= 1) / n,
            "nothing": sum(1 for s in scored if s[atk]["best"] >= 2) / n,
            "weak_mons": sum(s[atk]["still_weak"] for s in scored) / n,
            "pool": npool[atk]["share"], "team": nteam[atk]["share"] if nteam else None,
            "p_pool": ztest(bare, n, npool[atk]["share"], trials),
            "p_team": ztest(res, n, nteam[atk]["share"], trials) if nteam else 1.0,
            "tera_only": tera_only, "tera_offtype": tera_offtype, "mech": mech,
            "immune_types": typing_answer_possible(theme, atk, chart),
            "var": ovar, "exactly1": sum(1 for c in counts if c == 1) / n,
            "team_mean": nteam[atk]["mean"] if nteam else None,
            "team_var": nteam[atk]["var"] if nteam else None,
            "team_ex1": nteam[atk]["exactly1"] if nteam else None,
        })
    return rows


def report(teams, d, gens, themes, trials, rng, verbose_theme=None):
    for gen in gens:
        chart = d["gen%d" % gen]["chart"]
        present = sorted({t["theme"] for t in teams if t["gen"] == gen})
        rows = [th for th in present if not themes or th in themes]
        if not rows:
            continue
        print("\n=== gen %d — %d teams, %d themes ===" % (
            gen, sum(1 for t in teams if t["gen"] == gen and t["theme"] in rows), len(rows)))
        struct = collections.defaultdict(list)
        for th in rows:
            for atk in weaknesses(th, chart):
                struct[bool(typing_answer_possible(th, atk, chart))].append((th, atk))
        print("  structure, read off the type chart: of %d theme-weakness pairs, %d can be "
              "answered by a second type and %d cannot."
              % (len(struct[True]) + len(struct[False]), len(struct[True]), len(struct[False])))
        print("  a second type helps only where it is IMMUNE (2 x 0.5 is still neutral), so the "
              "%d unanswerable pairs are exactly those whose attacker nothing is immune to: %s"
              % (len(struct[False]), ", ".join(sorted({a for _, a in struct[False]}))))
        print("%-8s %4s %-8s | %5s %4s %5s %5s | %5s %5s %6s | %5s %5s %6s | %5s %5s | %4s %4s | %s" % (
            "theme", "n", "weak to", "res%", "mean", "neu%", "no%",
            "bare%", "pool%", "p", "res%", "team%", "p", "=1%", "null", "ter", "off", "mechanism"))
        allrows = []
        for th in rows:
            for r in summarise(teams, d, gen, th, trials, rng):
                allrows.append(r)
                tot = sum(r["mech"].values()) or 1
                ms = " ".join("%s %.0f" % (k, 100 * v / tot) for k, v in r["mech"].most_common(3))
                if not typing_answer_possible(th, r["atk"], chart):
                    ms = (ms + "  [no typing answer exists]").strip()
                print("%-8s %4d %-8s | %5.0f %4.2f %5.0f %5.0f | %5.0f %5.0f %6.3f | %5.0f %5.0f %6.3f | %5.0f %5.0f | %4.0f %4.0f | %s" % (
                    th, r["n"], r["atk"], 100 * r["resist"], r["mean"], 100 * r["neutral_only"],
                    100 * r["nothing"], 100 * r["bare"], 100 * r["pool"], r["p_pool"],
                    100 * r["resist"], 100 * (r["team"] or 0), r["p_team"],
                    100 * r["exactly1"], 100 * (r["team_ex1"] or 0),
                    100 * r["tera_only"], 100 * r["tera_offtype"], ms))
        digest(allrows, gen)
    if verbose_theme:
        for gen in gens:
            detail(teams, d, verbose_theme, gen)


def digest(rows, gen):
    """The three headline questions, over every (theme, weakness) pair in this gen."""
    n = len(rows)
    if not n:
        return
    wt = sum(r["n"] for r in rows)
    mean = lambda k: sum(r[k] * r["n"] for r in rows) / wt
    print("  -- %d theme-weakness pairs, team-weighted: resist %.0f%% | neutral-only %.0f%% "
          "| nothing %.0f%% | mean answers %.2f | mean members still weak %.2f of 6"
          % (n, 100 * mean("resist"), 100 * mean("neutral_only"), 100 * mean("nothing"),
             mean("mean"), mean("weak_mons")))
    beats_pool = [r for r in rows if r["bare"] > r["pool"] and r["p_pool"] < 0.05]
    under_pool = [r for r in rows if r["bare"] < r["pool"] and r["p_pool"] < 0.05]
    beats_team = [r for r in rows if r["resist"] > r["team"] and r["p_team"] < 0.05]
    under_team = [r for r in rows if r["resist"] < r["team"] and r["p_team"] < 0.05]
    print("  -- vs pool null (typing only): %d pairs above, %d below, %d indistinguishable (p>=0.05)"
          % (len(beats_pool), len(under_pool), n - len(beats_pool) - len(under_pool)))
    print("  -- vs team null (co-occurrence): %d above, %d below, %d indistinguishable"
          % (len(beats_team), len(under_team), n - len(beats_team) - len(under_team)))
    worst = sorted(rows, key=lambda r: -r["nothing"])[:6]
    print("  -- weaknesses teams most often cannot switch into at all:")
    for r in worst:
        print("       %-8s vs %-8s %3.0f%% of %d teams have every member at x2 or worse"
              % (r["theme"], r["atk"], 100 * r["nothing"], r["n"]))
    slot = [r for r in rows if r["team"] is not None and r["resist"] > r["team"]
            and r["var"] < r["team_var"] and r["p_team"] < 0.05]
    print("  -- designated-slot signature (more teams covered than the team null AND a "
          "tighter spread, i.e. nearly always exactly one answer): %d of %d pairs" % (len(slot), n))
    if gen == 9:
        ta = sum(r["tera_only"] * r["n"] for r in rows) / wt
        to = sum(r["tera_offtype"] * r["n"] for r in rows) / wt
        print("  -- Tera on uncovered weaknesses: %.0f%% of teams hold a Tera that would resist, "
              "but only %.0f%% is an OFF-TYPE Tera (the rest is the set's own STAB, which resists "
              "as a side effect)" % (100 * ta, 100 * to))
    law = [r for r in rows if not r["immune_types"]]
    if law:
        print("  -- no typing answer CAN exist (nothing is immune to the attacker, and a resist "
              "only brings x2 back to x1): %d pairs, %s" % (
                  len(law), ", ".join("%s/%s" % (r["theme"], r["atk"]) for r in law)))
    gap = [r for r in rows if r["immune_types"] and r["pool"] == 0]
    if gap:
        print("  -- the immunity exists but no legal species of the theme has it, so the answer is "
              "on paper only: %s" % ", ".join(
                  "%s/%s (would need %s/%s)" % (r["theme"], r["atk"], r["theme"],
                                                "|".join(r["immune_types"])) for r in gap))
    strict = 0.05 / max(n, 1)
    print("  -- Bonferroni over %d pairs (alpha %.4f): %d still above the pool null, %d above the "
          "team null" % (n, strict,
                         sum(1 for r in rows if r["bare"] > r["pool"] and r["p_pool"] < strict),
                         sum(1 for r in rows if r["team"] is not None and r["resist"] > r["team"]
                             and r["p_team"] < strict)))


def detail(teams, d, theme, gen):
    """Who answers, by what, and whether the answer is built to switch in."""
    chart = d["gen%d" % gen]["chart"]
    ts = [t for t in teams if t["theme"] == theme and t["gen"] == gen]
    if not ts:
        return
    print("\n--- gen %d %s (n=%d teams) ---" % (gen, theme, len(ts)))
    for atk in weaknesses(theme, chart):
        who = collections.Counter(); qual = collections.Counter(); per = collections.Counter()
        teras = collections.Counter()
        for t in ts:
            s = score(t, chart)[atk]
            per[s["answers"]] += 1
            for r in s["rows"]:
                if r["full"] < 1:
                    who["%-22s %-7s x%g" % (r["mon"]["display"], r["mech"], r["full"])] += 1
                    q = switchin_quality(r["mon"])
                    qual["total"] += 1
                    for k, v in q.items():
                        qual[k] += bool(v)
                if r["mon"]["tera"] and r["full"] >= 1 and \
                        taken(atk, r["mon"], chart, use_tera=True) < 1:
                    teras["%s -> Tera %s" % (r["mon"]["display"], r["mon"]["tera"])] += 1
        tot = qual["total"] or 1
        print("  vs %-8s answers per team %s" % (atk, dict(sorted(per.items()))))
        print("     %d answer slots: %.0f%% recovery, %.0f%% pivot move, %.0f%% hazard removal"
              % (qual["total"], 100 * qual["recovery"] / tot, 100 * qual["pivot"] / tot,
                 100 * qual["removal"] / tot))
        for name, k in who.most_common(8):
            print("       %-44s %3d teams (%2.0f%%)" % (name, k, 100 * k / len(ts)))
        if not who:
            neu = collections.Counter()
            for t in ts:
                for r in score(t, chart)[atk]["rows"]:
                    if r["full"] == 1:
                        neu[r["mon"]["display"]] += 1
            print("       (nothing resists; the best switch-ins are neutral bodies)")
            for name, k in neu.most_common(5):
                print("       %-44s %3d teams (%2.0f%%)" % (name + "  x1", k, 100 * k / len(ts)))
        for name, k in teras.most_common(3):
            print("       [tera] %-37s %3d teams (%2.0f%%)" % (name, k, 100 * k / len(ts)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gen", nargs="*", type=int, default=[9], choices=GENS)
    ap.add_argument("--theme", nargs="*", default=None)
    ap.add_argument("--trials", type=int, default=4000, help="null-model draws per theme")
    ap.add_argument("--seed", type=int, default=20260919)
    ap.add_argument("--json", help="write per-team coverage records here")
    ap.add_argument("--rebuild-dex", action="store_true")
    a = ap.parse_args()
    if a.rebuild_dex:
        dex(force=True)
    d = dex()
    teams, stats = read_teams(GENS)
    print("corpus:", dict(stats))
    report(teams, d, a.gen, a.theme, a.trials, random.Random(a.seed),
           verbose_theme=(a.theme[0] if a.theme else None))
    if a.json:
        recs = []
        for t in teams:
            chart = d["gen%d" % t["gen"]]["chart"]
            s = score(t, chart)
            recs.append({"gen": t["gen"], "theme": t["theme"], "url": t["url"],
                         "species": [m["species"] for m in t["mons"]],
                         "weaknesses": {k: {kk: vv for kk, vv in v.items() if kk != "rows"}
                                        for k, v in s.items()}})
        with open(a.json, "w") as fh:
            json.dump(recs, fh, indent=1, default=lambda o: list(o.elements()) if isinstance(o, collections.Counter) else str(o))
        print("wrote", a.json, len(recs), "records")


if __name__ == "__main__":
    main()
