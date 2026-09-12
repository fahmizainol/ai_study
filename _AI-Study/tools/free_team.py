#!/usr/bin/env python3
"""Build a team around Pokemon you choose, rather than around a story slot.

The boss generator answers "what should gym 4 field". This answers "I want these
three, fill the rest" -- and, unlike that one, it is expected to give a DIFFERENT
answer each time you ask.

Why it is a separate module rather than a flag on generate_bosses: the two want
opposite things from the same assembly loop. A gym team is pinned to an eBST curve
that is a contract with the player's level cap, and its picks are an argmin against
that curve -- which is exactly why every gym plan returns the same six Pokemon. Here
the curve is a band to stay inside, and the picks are decided by CONSTRAINTS, which
have many solutions where an optimum has one:

    no two members sharing a type combination   (92.9% of real teams; see team_shape)
    cover a type nothing on the team resists
    fill a role floor the pool can actually supply

generate_bosses.assemble() is still the builder -- sets, items, the power ceiling,
role floors and dedupe are all its work, and duplicating them here is how the two
generators would drift apart. What this module owns is the SPEC handed to it, the
corpus evidence used to break ties, and the loop that asks for N of them.

Usage:
    free_team.py --cores AZUMARILL,KLEFKI --n 5
    free_team.py --cores GARCHOMP --target 520 --archetype offense --n 3
"""
import argparse
import collections
import json
import os
import random
import sys
from functools import lru_cache

import generate_bosses as G
import realidea_data as D
import smogon_corpus as SC
import showdown_names as SN
import team_shape as TS


# ---------------------------------------------------------------- corpus evidence
@lru_cache(maxsize=1)
def rosters():
    """Every scraped six-mon team whose whole roster exists in Realidea, as a tuple
    of internal names.

    Filtered by RESOLVABILITY, never by the filename's generation. smogon_corpus
    warns that the tier in a dump filename is the forum thread and not the format --
    gen6monotype.json is entirely gen 8 teams -- and the same cuts the other way:
    over half the usable teams here come from gen8/gen9 threads that happen to be
    built entirely from Pokemon this game has. Trusting the stem would have thrown
    13,964 of them away and kept some gen 8 teams anyway.

    29,956 of the dump's 54,522 complete singles teams survive. ~1.8 s cold, then
    cached for the process."""
    game = SN.Realidea()
    out = []
    for _stem, team in SC.dump_teams():
        names = [game.fold_species(d["species"]) for d in team["data"]]
        if all(names):
            out.append(tuple(names))
    return out


@lru_cache(maxsize=1)
def _postings():
    """{SPECIES: frozenset(roster indices)} -- the inverted index behind support()."""
    idx = collections.defaultdict(set)
    for i, roster in enumerate(rosters()):
        for name in roster:
            idx[name].add(i)
    return {k: frozenset(v) for k, v in idx.items()}


def fold(name):
    """A user-typed or corpus species name -> the key the index is built on, or None.

    The same folding the corpus went through, applied to the query, because the two
    must agree on granularity or a lookup silently finds nothing. Realidea models
    Rotom's appliances as FORMES of ROTOM, so the index has no ROTOMW to match and
    "Rotom-Wash", "rotom-w" and "ROTOM" all have to arrive as ROTOM."""
    return SN.Realidea().fold_species(name)


def support(cores):
    """(Counter{species: teams}, n_matching) over real teams containing every core.

    RAW conditional support, not lift. TEAM-CORPUS.md section 7 established that lift
    measures surprise rather than quality: it recovers weather, stall and screens
    cores and can NEVER recover a standard balance core, because a core assembled
    from staples is statistically invisible by construction. "Who actually gets built
    alongside these" is the question here, and staples are a perfectly good answer to
    it -- so the count is the score."""
    cores = [fold(c) for c in cores]
    if any(c is None for c in cores):
        return collections.Counter(), 0
    idx = _postings()
    if not cores:
        hits = range(len(rosters()))
    else:
        sets_ = [idx.get(c) for c in cores]
        if any(s is None for s in sets_):
            return collections.Counter(), 0
        hits = frozenset.intersection(*sets_)
    out = collections.Counter()
    all_rosters = rosters()
    for i in hits:
        for name in all_rosters[i]:
            if name not in cores:
                out[name] += 1
    return out, len(hits)


@lru_cache(maxsize=1)
def marginal():
    """Support against EVERY team: how often a species is played at all.

    The backoff, and it is not optional. Joint support collapses exactly where the
    question gets interesting: two cores leave a basis of 88 teams, and 92% of a
    354-species pool appears in none of them, so 92% tie at zero and the jitter --
    not the corpus -- picks among them. The more precisely you name what you want,
    the less the evidence can say, which is backwards.

    Ranked strictly BELOW joint support, so a mon that really was built alongside
    your cores always beats one that is merely popular. It only orders the mass of
    species the joint basis cannot distinguish at all."""
    got, n = support(())
    return {k: 100 * v / max(n, 1) for k, v in got.items()}


# ---------------------------------------------------------------- judging a team
# Reduced to breakpoints rather than kept as rows: the scan is ~10 s over 29,956
# teams and all any caller wants is "where does this team sit", so the artifact is
# a percentile ladder per axis and ~2 KB. Bump VERSION whenever `coverage()` changes
# what an axis MEANS -- a stale ladder does not fail, it silently answers the wrong
# question, the same trap team_shape.PROFILE_VERSION exists for.
REFERENCE_VERSION = 1
REFERENCE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "generated", "team_coverage_reference.json")
_MEMO = {}


def _team_mons(names, moves_by_name=None):
    """[{types, base_stats, moves}] for species this game has, skipping those it does not."""
    sp = D.species()
    out = []
    for n in names:
        rec = sp.get(n)
        if rec:
            out.append({"types": rec["types"], "base_stats": rec["base_stats"],
                        "moves": (moves_by_name or {}).get(n, [])})
    return out


def build_reference():
    """Percentile ladder per coverage axis, over every resolvable scraped team."""
    game = SN.Realidea()
    sp = D.species()
    rows = []
    for _stem, team in SC.dump_teams():
        mons = []
        for d in team["data"]:
            key = game.fold_species(d["species"])
            rec = sp.get(key) if key else None
            if not rec:
                break
            mons.append({"types": rec["types"], "base_stats": rec["base_stats"],
                         "moves": d.get("moves") or []})
        if len(mons) == 6:
            rows.append(TS.coverage(mons))
    ladder = {}
    for axis in TS.COVERAGE_AXES:
        vals = sorted(r[axis] for r in rows)
        ladder[axis] = [vals[int(p / 100 * (len(vals) - 1))] for p in range(101)]
    return {"version": REFERENCE_VERSION, "teams": len(rows), "ladder": ladder}


def reference(refresh=False):
    if not refresh and "ref" in _MEMO:
        return _MEMO["ref"]
    if not refresh and os.path.exists(REFERENCE):
        with open(REFERENCE, encoding="utf-8") as fh:
            got = json.load(fh)
        if got.get("version") == REFERENCE_VERSION:
            _MEMO["ref"] = got
            return got
    got = build_reference()
    os.makedirs(os.path.dirname(REFERENCE), exist_ok=True)
    with open(REFERENCE, "w", encoding="utf-8") as fh:
        json.dump(got, fh, indent=1)
    _MEMO["ref"] = got
    return got


def judge(mons):
    """coverage() plus where each axis sits against real teams, as a percentile.

    The percentile is positional only. Four of the seven axes have no good direction
    -- a team is not better for having more distinct attacking types than 90% of the
    corpus -- so this says "unusual", never "worse", and reading it as a score is how
    a metric starts steering toward the middle of a distribution nobody checked."""
    got = TS.coverage(mons)
    ladder = reference()["ladder"]
    out = {}
    for axis in TS.COVERAGE_AXES:
        steps = ladder[axis]
        pct = sum(1 for s in steps if s < got[axis])
        out[axis] = {"value": got[axis], "pctile": pct,
                     "p10": steps[10], "median": steps[50], "p90": steps[90]}
    return {"n": got["n"], "axes": out}


# ---------------------------------------------------------------- the build
# Every term above the jitter is QUANTIZED, and that is not a detail. A jitter placed
# under a continuous term never fires, because two candidates essentially never tie on
# a real-valued key -- which is the whole disease being treated here: the boss
# generator's `abs(projected - deficit)` is continuous, so it has exactly one winner
# and returns the same six Pokemon for every archetype. Banding turns "nearest" into
# "near enough", and only then does anything below it get a vote. AFFINITY_BAND = 30
# in generate_bosses is the same idea already in the codebase.
SUPPORT_BAND = 5      # percentage points of corpus co-occurrence
BST_BAND = 25         # eBST; ~half of AFFINITY_BAND's job, at half its width
TRACE_TOP = 10        # shortlist kept per pick when explaining a build


def _combos(team):
    return {frozenset(D.species()[m["species"]]["types"])
            for m in team if m["species"] in D.species()}


def _uncovered(team):
    """Attacking types nothing on the team resists yet."""
    chart = D.type_chart()
    sp = D.species()
    types = [sp[m["species"]]["types"] for m in team if m["species"] in sp]
    return [a for a in sorted(chart[0])
            if not any(TS.type_multiplier(a, t, chart) < 1 for t in types)]


def rank_for(sup, basis, seed):
    """Build the spec["rank"] hook: constraints first, corpus second, curve third.

    The inversion this whole module exists for. The boss generator ranks on distance
    from an eBST target, an OPTIMUM, which has one winner. These are CONSTRAINTS --
    "don't repeat a type combination", "resist something nobody here resists" -- and
    a constraint has many winners, which is where variety comes from. The eBST band
    is still honoured, but as a filter on the pool and a coarse bucket here, never as
    the deciding term."""
    sp = D.species()
    chart = D.type_chart()
    marg_pct = marginal()

    def make(state, tail):
        def key(n):
            types = sp[n]["types"]
            team = state["team"]
            seen = _combos(team)
            gaps = _uncovered(team)

            repeat = 1 if frozenset(types) in seen else 0
            closes = sum(1 for a in gaps
                         if TS.type_multiplier(a, types, chart) < 1)
            pct = 100 * sup.get(n, 0) / max(basis, 1)
            marg = marg_pct.get(n, 0.0)

            real = [m for m in team if not G.is_dynamic(m["species"])]
            left = max(state["size"] - len(real), 1)
            want = (state["target"] * state["size"]
                    - sum(G.ebst(m) for m in real)) / left
            gap = abs(state["projected"](n) - want)

            # random.Random over a STRING seed, never hash(): hash() is salted per
            # process by PYTHONHASHSEED, so "variation 3" would quietly be a
            # different team on every run. This file's own generators are checked
            # across three seeds precisely because that bug has bitten here before.
            rng = random.Random(f"{seed}:{n}")
            # The noise goes INSIDE the band, not after it. A lexicographic key
            # hands the decision to whichever term is finest-grained, so a jitter
            # appended last fires only when every term above it ties exactly --
            # which, with support measured in percentage points, is almost never.
            # Perturbing by about one band width instead means candidates within a
            # band of each other genuinely swap order between seeds, and candidates
            # a band apart never do. That is the difference between "sample among
            # the ones that are near enough" and "argmin with extra steps".
            noise = rng.uniform(0, SUPPORT_BAND)
            jitter = rng.random()

            # BINARY, not -closes. Ranking by "closes the MOST gaps" is an
            # optimum with one winner -- the exact shape this module exists to get
            # away from -- and it was picking Sawsbuck and Cacturne over Landorus
            # for closing three holes instead of two, with no corpus support at all.
            # A constraint is satisfied or it is not; among everyone who satisfies
            # it, the corpus and the curve decide.
            covers = 0 if closes else 1
            return (repeat, covers, -int(pct + noise) // SUPPORT_BAND,
                    -int(marg + noise) // SUPPORT_BAND,
                    int(gap) // BST_BAND, jitter) + tail(n)
        return key
    return make


def trace_rank(spec, sup, basis, out):
    """Wrap spec["rank"] so every candidate it scores is recorded, for `explain`.

    A wrapper rather than a flag inside rank_for: the key function is called once per
    candidate per sort by pool.sort(), which is exactly the hook a trace wants, and
    threading a collector through the ranking would put reporting inside the thing
    being reported on."""
    inner = spec["rank"]
    marg = marginal()

    def hook(state, tail):
        key = inner(state, tail)
        rows = {}
        # The roster as it stood when this sort ran. assemble() re-sorts the finished
        # team so the setter leads (generate_bosses.py:1569), so the RETURNED order is
        # not the pick order -- reading it as one mis-attributes every pick. Diffing
        # consecutive snapshots recovers who was actually taken.
        out.append({"had": [m["species"] for m in state["team"]], "rows": rows})

        def wrapped(n):
            k = key(n)
            real = [m for m in state["team"] if not G.is_dynamic(m["species"])]
            left = max(state["size"] - len(real), 1)
            want = (state["target"] * state["size"]
                    - sum(G.ebst(m) for m in real)) / left
            rows[n] = {"name": n, "repeat": k[0], "covers": k[1],
                       "sup": 100 * sup.get(n, 0) / max(basis, 1), "sup_band": k[2],
                       "marg": marg.get(n, 0.0), "marg_band": k[3],
                       "gap": abs(state["projected"](n) - want), "gap_band": k[4],
                       "jitter": k[5], "tier": SC.band(n), "_key": k}
            return k
        return wrapped

    spec["rank"] = hook


def explain(picks, team, top=TRACE_TOP):
    """[{slot, took, why, n, rows}] -- the ranked shortlist behind each pick.

    Truncated to `top` because the interesting fact is where the taken mon sat, not
    the tail: the ranker scores the whole pool (~370 species) at every slot, and the
    pick is usually NOT rank 1 -- take() walks this order and takes the first
    candidate that can actually do the job the floor asked for. When the taken mon
    falls outside the shortlist it is appended, so the row is always present."""
    why = {m["species"]: m["why"] for m in team}
    snaps = [p["had"] for p in picks] + [[m["species"] for m in team]]
    out = []
    for i, p in enumerate(picks):
        new = [n for n in snaps[i + 1] if n not in snaps[i]]
        took = new[0] if new else None
        order = sorted(p["rows"], key=lambda n: p["rows"][n]["_key"])
        shown = order[:top]
        if took and took in p["rows"] and took not in shown:
            shown.append(took)
        out.append({"slot": len(snaps[i]) + 1, "took": took, "n": len(p["rows"]),
                    "why": why.get(took, ""),
                    "rows": [dict({k: v for k, v in p["rows"][n].items()
                                   if k != "_key"},
                                  rank=order.index(n) + 1, took=(n == took))
                             for n in shown]})
    return out


def pool_filter_for(filters):
    """Who is allowed in the pool at all: band, generation, tier ceiling, types."""
    sp = D.species()
    by_id = D.species_by_id()
    gen_of = {name: _gen_for(num) for num, name in by_id.items()}
    lo, hi = filters["lo"], filters["hi"]
    gens = set(filters.get("gens") or ())
    ceiling = filters.get("tier_ceiling")
    types = set(filters.get("types") or ())

    def keep(n):
        # The band is judged on the species' OWN weight, never its mega weight.
        # Only one mon on a team can hold a stone, but potential_bst() credits the
        # mega's +100 to every mega-capable species, so a 600 Tyranitar reads as 700
        # and falls out of a 409-631 band it belongs in the middle of -- taking the
        # canonical Sand Stream setter, and Excadrill's most common real partner at
        # 38.7%, out of the pool before the ranking ever saw it. Whether a mega is
        # WORTH its slot is a ranking question, and assemble()'s projected() already
        # discounts the bonus once the team's one mega is spoken for.
        if not (lo <= G.potential_bst(n, False) <= hi):
            return False
        if gens and gen_of.get(n) not in gens:
            return False
        if ceiling and SC.rank(n) < SC.RANK.index(ceiling):
            return False
        if types and not (set(sp[n]["types"]) & types):
            return False
        return True
    return keep


def sets_for(species, level, allow_mega=True):
    """The published sets a core could be built from, for the picker.

    Same legality rules the builder applies, because it is literally the builder's
    own enumeration -- a set offered here that build() would refuse is a checkbox
    that silently does nothing."""
    banned = frozenset() if allow_mega else frozenset(G.MEGASTONE)
    out = []
    for c in G.usable_sets(species, level, banned, None, None):
        out.append({"label": c["label"], "fmt": c["fmt"], "source": c["source"],
                    "setname": c["setname"], "item": c["item"],
                    "ability": c["ability"], "moves": list(c["ok"]),
                    "inherited": None if c["src"] == species else c["src"],
                    "roles": sorted(c["roles"])})
    out.sort(key=lambda x: (x["source"] != "dex", x["fmt"], x["setname"]))
    return out


GENERATIONS = [1, 2, 3, 4, 5, 6, 7, "fangame"]


@lru_cache(maxsize=1)
def dex():
    """Species names a core box will accept. Only what the game can actually field:
    a species with no types is a PBS placeholder, not a Pokemon."""
    return sorted(n for n, s in D.species().items() if s["types"])


GEN_LAST = [(1, 151), (2, 251), (3, 386), (4, 493), (5, 649), (6, 721), (7, 803)]


def _gen_for(num):
    """National dex number -> generation. Realidea's pokemon.txt section ids ARE the
    national dex through 803; everything above is this game's own (Alolan entries,
    then fakemon), which is a real category a filter should be able to name."""
    for gen, last in GEN_LAST:
        if num <= last:
            return gen
    return "fangame"


# What the archetype/mode boxes send when the user has no opinion. Not None and not
# "": mode already uses "" to mean "explicitly no mode", which is a different answer
# from "surprise me" and must stay distinguishable.
ANY = "any"


def plan_for_seed(filters, seed):
    """(archetype, mode) for one variation, sweeping whatever was left unspecified.

    A deterministic walk over the combinations rather than a random draw, so asking
    for N variations covers N different plans instead of rolling the same one twice
    before it has shown you the others. With both boxes on `any` that is 5
    archetypes x 7 mode choices = 35 combinations, in a fixed order."""
    arch, mode = filters["archetype"], filters["mode"]
    archs = list(TS.ARCHETYPES) if arch == ANY else [arch]
    modes = ([None] + list(TS.MODE_ROLES)) if mode == ANY else [mode or None]
    combos = [(a, m) for a in archs for m in modes]
    return combos[(seed - 1) % len(combos)]


def spec_for(filters, seed, sup, basis):
    """The one place a filter dict becomes an assemble() spec."""
    level, stage = filters["level"], filters["stage"]
    mega_ok = stage >= G.UNLOCK_STAGE
    archetype, mode = plan_for_seed(filters, seed)
    floors, caps = G.plan_for(archetype, mega_ok, mode)
    fallback = filters.get("fallback_picks", True)

    # Everything plan_for() hands back is MANDATORY by default -- that is what a
    # floor is -- and `mega` is one of them, added for any fight past the item
    # unlock, which is why a mega kept appearing unasked. For a gym that is right:
    # the curve counts the mega's 100 eBST and the fight is balanced around it. For
    # a team you are designing it is just an opinion, so every floor is droppable
    # here. Dropping one only ever removes a requirement; it never forbids the role,
    # so a team may still end up with a mega because a mega was the best pick.
    notes = []
    if not filters.get("allow_mega", True):
        floors.pop("mega", None)
        notes.append("megas off — stones banned, and no mega bonus in the eBST band")
    for role in filters.get("drop_floors") or ():
        if floors.pop(role, None) is not None:
            notes.append(f"{role} not required")

    # Drop floors nothing in the pool can be asked for, rather than spending every
    # slot searching for them and silently falling through -- 1,156 such asks across
    # the nine gyms bought 11 roles. The reading ignores the band/generation filters,
    # so it is an UPPER bound on supply: it can keep a floor that turns out
    # unmeetable (today's behaviour, no worse) but never drops one that was meetable.
    supply = G.role_supply(level, stage, frozenset(floors), mode)
    for role in list(floors):
        pub, lrn = supply.get(role, (0, 0))
        if pub or (fallback and lrn):
            continue
        del floors[role]
        notes.append(f"dropped the {role} floor — nothing at level {level} "
                     f"in this pool provides it")

    spec = {
        "level": level, "ace_level": None, "stage": stage,
        "target": filters["target"], "lo": filters["lo"], "hi": filters["hi"],
        # No theme, deliberately. Setting one switches on assemble()'s off-theme
        # gate, whose MIN_CORR half TEAM-CORPUS.md section 8 measures as a no-op
        # (~95% of eligibility arrives by the resistance path, which it never
        # gates). The type filter is expressed in pool_filter instead, where it
        # actually filters.
        "theme": None, "on_theme_min": 0,
        "kept": [{"species": c, "level": level} for c in filters["cores"]],
        "keep_band": False, "note_unknown": True,
        "floors": floors, "caps": caps, "mode": mode, "mega_ok": mega_ok,
        "ubers_ok": True, "project_spent_mega": True,
        "why_theme": ("%s", "pick"), "why_open": ("for %s", "fills out the team"),
        "reequip": True, "dedupe": True, "keep_drop": 0, "protected": [],
        "size": filters["size"],
        # The half of an archetype that is NOT a role floor. Without it "stall" and
        # "hyper offense" hand a core the same set whenever it fills no floor.
        "offence": TS.profile()["archetype"][archetype]["offence"],
        "pool_filter": pool_filter_for(filters),
        "set_formats": filters.get("set_formats"),
        "early_moves": filters.get("early_moves"),
        "fallback_picks": fallback,
        "no_mega": not filters.get("allow_mega", True),
        # Vary the SET as well as the roster. Without it a pinned core is byte-
        # identical in every variation, so pinning three of six freezes half the
        # team and "variations" only ever means "different filler".
        "set_seed": seed,
        "set_filter": filters.get("set_filter") or {},
        "rank": rank_for(sup, basis, seed),
    }
    return spec, notes, {"archetype": archetype, "mode": mode}


# How many seeds to draw per variation asked for before accepting that the filters
# genuinely do not admit that many teams. Duplicates are cheap to make and useless to
# look at, so it is better to spend a few builds than to show the same six Pokemon
# twice and call it a variation.
SEED_BUDGET = 8
# Consecutive fruitless draws before accepting that the filters have no more to give.
# Without it, a core pinned to ONE set burns the whole budget re-deriving it.
STALE_LIMIT = 25


def build(filters, count=5):
    """`count` DISTINCT variations, each reproducible from its seed.

    Keeps drawing seeds until it has `count` different rosters or runs out of budget.
    It used to return one team per seed and label the duplicates "repeat", which is
    just asking the reader to do the deduplication. When the filters admit fewer
    teams than asked for, `tried` says how hard it looked so the shortfall reads as
    a fact about the filters rather than a glitch."""
    sup, basis = support(filters["cores"])
    per_set = filters.get("per_set") or count
    # The cap has to bite while DRAWING, not while selecting. Picking from a finished
    # sample can only ever take as many teams as a bucket happens to hold, so one
    # prolific core set fills the list and the rarer ones starve -- 25 of set A, 5 of
    # set B, no room for C. Refusing a team whose set is already full and spending
    # the seed on another draw is what actually leaves room for the rest.
    buckets, seen, notes_of = {}, set(), {}
    seed = total = stale = 0
    budget = count * SEED_BUDGET
    while total < count and seed < budget and stale < STALE_LIMIT:
        seed += 1
        spec, notes, plan = spec_for(filters, seed, sup, basis)
        picks = []
        if filters.get("explain"):
            trace_rank(spec, sup, basis, picks)
        built = G.assemble(spec)
        team = built["team"]
        key = tuple(sorted((m["species"], m["item"], tuple(m["moves"])) for m in team))
        ckey = core_build(team, set(filters["cores"])) if filters["cores"] else ()
        if key in seen or len(buckets.get(ckey, ())) >= per_set:
            stale += 1                 # a duplicate, or a set that is already full
            continue
        stale = 0
        seen.add(key)
        buckets.setdefault(ckey, []).append(
            {"seed": seed, "team": team, "roles": built["roles"],
             "plan": plan, "notes": notes + built["notes"],
             "trace": explain(picks, team) if filters.get("explain") else None})
        total += 1

    groups = [{"core": list(k), "teams": t} for k, t in buckets.items()]
    groups.sort(key=lambda g: (-len(g["teams"]), g["teams"][0]["seed"]))
    return {"groups": groups,
            "variations": [v for g in groups for v in g["teams"]],
            "distinct": total, "asked": count, "core_sets": len(groups),
            "per_set": per_set, "tried": seed, "basis": basis,
            "support": dict(sup), "marginal": marginal(),
            "cores": filters["cores"]}


def core_build(team, cores):
    """The identity of the CORE half of a team: what your own picks are running.

    The ABILITY is part of that identity, not a label on it. A Swift Swim Kingdra and
    a Sniper Kingdra carrying the same four moves are not the same build -- under rain
    they are barely the same Pokemon -- so they belong in different groups, and a
    reader comparing two sets needs to see which one they are looking at."""
    return tuple(sorted((m["species"], m["item"], G.ability_name(m) or "",
                         tuple(m["moves"]))
                        for m in team if m["species"] in cores))


def group_by_core(variations, cores):
    """[{core, teams}] -- one group per distinct build of the cores.

    Without cores there is nothing to group by and everything lands in one group,
    which is the right answer rather than a special case at the call site."""
    buckets = {}
    for v in variations:
        key = core_build(v["team"], set(cores)) if cores else ()
        buckets.setdefault(key, []).append(v)
    return [{"core": list(k), "teams": t} for k, t in buckets.items()]


def _display():
    """{NORMALISED: the spelling Showdown uses}, harvested from the set corpus.

    Title-casing an internal name does not produce importable text: CHOICEBAND
    becomes "Choiceband", which Showdown does not know. The published sets already
    carry every item and move spelled the way Showdown spells it, so the mapping is
    read out of them rather than guessed. Anything absent -- this game's own species
    and items -- falls back to title case and will not import, which is honest: no
    spelling exists for those."""
    out = {}
    for sets_ in SC.sets().values():
        for st in sets_.values():
            for val in [st.get("item")] + list(st.get("moves") or ()):
                if isinstance(val, str) and val:
                    out.setdefault(SC.norm(val), val)
    return out


def _spell(name):
    return _display().get(SC.norm(name), name.title())


def showdown_paste(team):
    """Showdown export text.

    Species keep their internal name: this game's own Pokemon have no Showdown
    spelling, and inventing one would produce a paste that imports as a DIFFERENT
    Pokemon, which is worse than one that fails to import."""
    order = ["hp", "atk", "def", "spe", "spa", "spd"]     # PBS ev array order
    lines = []
    for m in team:
        head = m["species"].title()
        if m.get("item"):
            head += f" @ {_spell(m['item'])}"
        lines.append(head)
        evs = " / ".join(f"{v} {k.title()}" for k, v in zip(order, m["ev"]) if v)
        if evs:
            lines.append(f"EVs: {evs}")
        if m.get("nature"):
            lines.append(f"{m['nature'].title()} Nature")
        lines += [f"- {_spell(mv)}" for mv in m["moves"]]
        lines.append("")
    return "\n".join(lines).strip()


SHIPPED = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                       "..", "generated", "teams_bosses_gyms.json")


def judge_shipped(refresh=False):
    """The checkpoint: score teams we already know before scoring any we invent."""
    ref = reference(refresh)
    print(f"reference: {ref['teams']} real teams\n")
    with open(SHIPPED, encoding="utf-8") as fh:
        shipped = json.load(fh)

    head = "  ".join(f"{a[:9]:>9}" for a in TS.COVERAGE_AXES)
    print(f"{'fight':26} {head}")
    zero_dup = 0
    for t in shipped:
        mons = _team_mons([m["species"] for m in t["mons"]],
                          {m["species"]: m.get("moves") or [] for m in t["mons"]})
        got = judge(mons)
        cells = "  ".join(f"{got['axes'][a]['value']:6.1f}/{got['axes'][a]['pctile']:>2}"
                          for a in TS.COVERAGE_AXES)
        zero_dup += got["axes"]["dup_types"]["value"] == 0
        print(f"{t['id'][:26]:26} {cells}")
    print("\n  value/percentile against real teams. Percentile is POSITION, not merit:")
    print("  only dup_types has a direction real teams agree on.")

    steps = ref["ladder"]["dup_types"]
    real = sum(1 for s in steps if s == 0)
    print(f"\nsix distinct type combos: shipped {zero_dup}/{len(shipped)}, "
          f"real teams ~{real}%")
    return 0


def run_build(cores, args):
    gens = set()
    for tok in (t.strip() for t in args.gens.split(",") if t.strip()):
        gens.add(int(tok) if tok.isdigit() else tok)
    filters = {
        "cores": cores, "level": args.level, "stage": args.stage,
        "size": args.size, "target": args.target,
        "lo": args.target - args.spread / 2, "hi": args.target + args.spread / 2,
        "archetype": args.archetype, "mode": args.mode or None,
        "gens": gens,
        "types": {t.strip().upper() for t in args.types.split(",") if t.strip()},
    }
    got = build(filters, args.n)
    print(f"{got['distinct']} distinct of {args.n} variations"
          + (f" · {got['basis']} real teams contain {cores}" if cores else ""))

    for v in got["variations"]:
        mons = _team_mons([m["species"] for m in v["team"]],
                          {m["species"]: m["moves"] for m in v["team"]})
        scored = judge(mons)
        dup = scored["axes"]["dup_types"]["value"]
        unc = scored["axes"]["nobody_resists"]["value"]
        tag = " (repeat)" if v["repeat"] else ""
        print(f"\n--- variation {v['seed']}{tag} · "
              f"dup_types {dup} · nobody_resists {unc}")
        for m in v["team"]:
            thin = " · no published set" if m["fidelity"] == 0 else ""
            item = f" @ {m['item']}" if m["item"] else ""
            print(f"  {m['species']:14} L{m['level']}{item}{thin}")
            print(f"     {' / '.join(m['moves'])}")
        for note in v["notes"]:
            print(f"  note: {note}")

    if args.paste:
        pick = [v for v in got["variations"] if v["seed"] == args.paste]
        if pick:
            print("\n" + showdown_paste(pick[0]["team"]))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cores", default="",
                    help="comma-separated species to build around")
    ap.add_argument("--top", type=int, default=15,
                    help="how many corpus teammates to list")
    ap.add_argument("--build", action="store_true",
                    help="build teams around --cores")
    ap.add_argument("--n", type=int, default=5, help="how many variations")
    ap.add_argument("--level", type=int, default=50)
    ap.add_argument("--target", type=int, default=520, help="eBST to centre on")
    ap.add_argument("--spread", type=int, default=160, help="width of the eBST band")
    ap.add_argument("--size", type=int, default=6)
    ap.add_argument("--stage", type=int, default=8,
                    help="story stage; gates megas, Ubers and the power ceiling")
    ap.add_argument("--archetype", default="balance")
    ap.add_argument("--mode", default="")
    ap.add_argument("--gens", default="", help="e.g. 1,2,3 or 7,fangame")
    ap.add_argument("--types", default="", help="restrict the pool to these types")
    ap.add_argument("--paste", type=int, default=0,
                    help="print variation N as a Showdown paste")
    ap.add_argument("--judge", action="store_true",
                    help="score the shipped gym teams against real teams")
    ap.add_argument("--refresh", action="store_true",
                    help="rebuild the coverage reference from the corpus")
    args = ap.parse_args(argv)

    if args.judge:
        return judge_shipped(args.refresh)

    cores = [c.strip() for c in args.cores.split(",") if c.strip()]
    unknown = [c for c in cores if fold(c) is None]
    if unknown:
        print(f"not in Realidea's dex: {', '.join(unknown)}")
        return 1
    print(f"{len(rosters())} usable teams in the corpus")
    shown = [fold(c) for c in cores]
    if shown != [SC.norm(c) for c in cores]:
        print(f"cores resolved to {shown}")
    if args.build:
        return run_build(cores, args)

    got, n = support(cores)
    if not n:
        print(f"no real team contains all of {cores}")
        return 1
    print(f"{n} of them contain {cores or 'anything'}\n")
    for name, count in got.most_common(args.top):
        print(f"  {100 * count / n:5.1f}%  {count:6}  {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
