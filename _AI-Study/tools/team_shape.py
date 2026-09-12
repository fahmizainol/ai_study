#!/usr/bin/env python3
"""What a team actually DOES -- the structural counterpart to team_tags.py.

team_tags reads the label the author typed. This module reads the team itself: which
jobs its six sets cover, and how its EVs are split. Neither is ground truth on its
own, which is the point -- put together, the author's word on 2k teams turns the
other 52k into a reference an unlabelled team can be measured against.

Two consumers, and they must agree or the measurement is circular:

    generate_bosses.py   chases roles when it builds a team
    boss_diagnostic.py   scores the built team against the corpus

so ROLE_MOVES lives here and both import it. It used to live in generate_bosses.py
with a second, wider copy in the analysis scripts; the wider copy is what is below,
because the four roles the generator never chases (priority, status, protect, phaze,
screens) turn out to be exactly the ones that separate the archetypes.

A role is a claim about intent, read off a move name, and it is coarse by design:
Rest is "recovery" on a stall Skarmory and a status-absorber's sleep timer on an
offensive one, and nothing here can tell them apart. Counts of teams carrying >=1 of
a role hold up across 54k teams and five generations; finer readings do not.
"""
import collections
import json
import os
import random
import statistics

import realidea_data as D
import smogon_corpus as SC

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "..", "generated")
PROFILE = os.path.join(GEN, "archetype_role_profile.json")
SAMPLE_N = 2000
# Bumped whenever the shape of the cached file changes. v2 widened ROLES with the
# five mode roles -- which moves every column of `sample.rows` -- and added `mode`.
# v3 added `mode.*.payoff` and `mode.*.abuser_mean`. A stale file read by newer code
# does not fail, it silently answers the wrong question, so the check is not optional.
PROFILE_VERSION = 3

# Roles overlap on purpose -- Thunder Wave is both speed control and status, and a
# team that runs it gets credit for both. They are not a partition of the move pool.
ROLE_MOVES = {
    "hazards": {"STEALTHROCK", "SPIKES", "TOXICSPIKES", "STICKYWEB"},
    "removal": {"RAPIDSPIN", "DEFOG"},
    "setup": {"SWORDSDANCE", "NASTYPLOT", "DRAGONDANCE", "CALMMIND", "SHELLSMASH",
              "QUIVERDANCE", "BULKUP", "SHIFTGEAR", "COIL", "GROWTH", "WORKUP",
              "CURSE", "AGILITY", "ROCKPOLISH", "TAILGLOW"},
    "pivot": {"UTURN", "VOLTSWITCH", "BATONPASS", "PARTINGSHOT", "TELEPORT"},
    "recovery": {"ROOST", "RECOVER", "SOFTBOILED", "SYNTHESIS", "MOONLIGHT",
                 "MORNINGSUN", "WISH", "SLACKOFF", "REST", "MILKDRINK",
                 "STRENGTHSAP", "LEECHSEED"},
    "speed": {"THUNDERWAVE", "ICYWIND", "STICKYWEB", "TAILWIND", "TRICKROOM",
              "GLARE", "STUNSPORE"},
    "priority": {"SUCKERPUNCH", "AQUAJET", "BULLETPUNCH", "MACHPUNCH", "ICESHARD",
                 "SHADOWSNEAK", "EXTREMESPEED", "ACCELEROCK"},
    "status": {"TOXIC", "WILLOWISP", "THUNDERWAVE", "YAWN"},
    "protect": {"PROTECT", "SUBSTITUTE", "DETECT"},
    "phaze": {"ROAR", "WHIRLWIND", "DRAGONTAIL", "CIRCLETHROW"},
    "screens": {"REFLECT", "LIGHTSCREEN", "AURORAVEIL"},
    # Modes: a team-wide plan one set turns on and the other five are chosen for.
    # Appended at the END because ROLES is the column order of `sample.rows`, and a
    # cached profile written against the old width would be silently misread.
    "sun": {"SUNNYDAY"},
    "rain": {"RAINDANCE"},
    "sand": {"SANDSTORM"},
    "snow": {"HAIL"},
    "trickroom": {"TRICKROOM"},
}
ROLES = list(ROLE_MOVES)

# The roles above that are MODES rather than jobs. A job is something a set does for
# its team whatever else is going on; a mode is a claim about the whole battle, and
# the other five sets are picked to exploit it. They are kept out of role_plan() for
# that reason: an archetype has an opinion about how much recovery it wants and none
# at all about sun, so a single incidental Sunny Day must not read as "at cap".
MODE_ROLES = ("sun", "rain", "sand", "snow", "trickroom", "screens")
WEATHER_MODES = ("sun", "rain", "sand", "snow")
# An ability that sets the weather IS the setter -- Hippowdon carries no Sandstorm.
WEATHER_ROLE_OF_ABILITY = {"DROUGHT": "sun", "DRIZZLE": "rain",
                           "SANDSTREAM": "sand", "SNOWWARNING": "snow"}
WEATHER_ABILITY = frozenset(WEATHER_ROLE_OF_ABILITY)
# Abilities that only pay off once the mode is up. These are what makes a mode a team
# plan rather than one set's move: the lift measured in the corpus (see build_profile)
# is mostly these species arriving together.
#
# Counted over the agreement-validated teams, which is why three abilities that belong
# here on paper are not here:
#
#   SANDVEIL    5 uses of 172 sand abusers      SNOWCLOAK  0 of 31
#   LEAFGUARD   0 of 126 sun abusers
#
# The two evasion abilities are the ones that matter. A boss handed Sand Veil is a
# boss the player misses one attack in five against, for no counterplay -- and the
# corpus says nobody builds sand that way either (Sand Rush is 95% of it). Leaf Guard
# blocks status in sun and does nothing offensive; nobody uses it. Listing an ability
# here is what lets build() reassign a species onto it, so an unused one is not
# harmless: it is an instruction to go and find it.
#
# SLUSH RUSH is absent for a fourth and different reason: the corpus loves it (29 of
# 31 snow abusers) but REALIDEA'S ENGINE NEVER READS IT. The speed block in
# PokeBattle_Battler#pbSpeed has a RAINDANCE/HEAVYRAIN branch for Swift Swim, a
# SUNNYDAY/HARSHSUN branch for Chlorophyll and a SANDSTORM branch for Sand Rush, and
# no HAIL branch at all; `SLUSHRUSH` appears nowhere else in the scripts. Listing it
# would let a snow plan satisfy its abuser floor with an ability that does nothing,
# which is exactly the un-abused "rain team" this gate exists to stop -- so snow is
# left with ICE BODY, passive healing and not a wincon, and in practice is now very
# hard to propose. That is the honest state of snow on this engine: Aurora Veil is
# unlearnable here too (0 species), and Blizzard gets no hail accuracy exemption.
MODE_ABUSER_ABILITY = {
    "sun": {"CHLOROPHYLL", "SOLARPOWER", "FLOWERGIFT", "HARVEST"},
    "rain": {"SWIFTSWIM", "RAINDISH", "DRYSKIN", "HYDRATION"},
    "sand": {"SANDRUSH", "SANDFORCE"},
    "snow": {"ICEBODY"},
}
# Which ATTACKING stat a setup move raises, for the sets that raise exactly one.
# Growth, Work Up and Shell Smash raise both and are absent on purpose: they decide
# nothing. Agility and Rock Polish raise neither. Nor does SHIFT GEAR, which is +1
# Attack and +2 SPEED -- a special Magearna runs it for the speed and its three
# special attacks beside it are a real published set, not a mistake to be corrected.
#
# Used when a build has to invent filler moves: a setup move that survived into the set
# says what the set is FOR, which a base-stat comparison cannot when the two are equal.
SETUP_BOOSTS = {
    "special": {"NASTYPLOT", "CALMMIND", "TAILGLOW", "QUIVERDANCE"},
    "physical": {"SWORDSDANCE", "DRAGONDANCE", "BULKUP", "COIL", "CURSE"},
}
# Base speed at or under which a mon is a Trick Room beneficiary rather than a victim.
TR_SLOW = 50
# How much a mode must over-represent a type in the corpus before carrying that type
# counts as exploiting the mode. 1.5x is comfortably clear of the 1.0-1.2 that every
# type shows on every mode simply from sampling.
LIFT_MIN = 1.5

# What one set has to do with a mode. FOUR tiers, not three, and the split between
# ABUSER and ON_TYPE is the whole point: a Swift Swim Kingdra and a merely part-Flying
# Vespiquen were both scoring 1, so nothing downstream could tell "this team abuses
# rain" from "this team contains a type rain teams happen to run". That is how gym 1
# came to be offered a `balance + rain` plan whose only rain content was Vespiquen's
# secondary type -- and a Volbeat holding Sunny Day.
SETTER, ABUSER, ON_TYPE, NONE = 3, 2, 1, 0

# The same question for MOVES, measured rather than listed: which moves does a mode
# over-represent, once its own setter move is excluded? A hand-written table for rain
# would have named Scald and Hydro Pump (the lift does not support either) and missed
# Weather Ball at 15.9x and Flip Turn at 5.4x.
#
# Weather only. Trick Room and screens boost no move -- they change turn order and
# damage taken -- and running the same derivation on them yields their staple mons'
# incidental moves (Magic Coat 21x, Memento 9x), which is noise wearing a lift. Their
# payoff is slow base speed and setup respectively, both already in affinity().
#
# PAYOFF_LIFT is set by a control, not by taste: SAND has no move payoff at all (its
# gains are the Rock special-defence boost and Sand Rush), and sand's highest surviving
# lift is 4.31x. Any threshold at or under that would invent a payoff for sand. 5.0 is
# the smallest round number above it, and it keeps every move a player would name.
PAYOFF_LIFT = 5.0
PAYOFF_MIN_SETS = 8
# ... and on at least this many distinct species, which is what separates a real
# payoff from one popular Pokemon: Bolt Beak lifts 129x on snow and is one Dracovish.
PAYOFF_MIN_SPECIES = 3

# Ordered weakest-offence to strongest; the axis is ordinal, so "one class out" is a
# much smaller error than the class names suggest. semi-stall folds into stall: only
# 47 teams carry the tag and no feature separates them.
ARCHETYPES = ["stall", "balance", "bulky offense", "offense", "hyper offense"]
_FOLD = {"stall": "stall", "semi-stall": "stall", "balance": "balance",
         "bulky offense": "bulky offense", "offense": "offense",
         "hyper offense": "hyper offense"}


def abuse_role(mode):
    """The role name for "cashes in on `mode`", as opposed to turning it on.

    A derived name rather than a ROLE_MOVES entry on purpose: the moves that count are
    measured per mode (see PAYOFF_LIFT) instead of listed, and adding six more columns
    to ROLES would move every column of `sample.rows` for a role no archetype has an
    opinion about. The floor/chase/dedupe machinery is generic over role names, so
    this costs nothing but the string."""
    return mode + "_abuse"


def payoff_moves(mode, prof=None):
    """Moves this mode over-represents, from the profile. Empty for TR and screens."""
    m = (prof or profile())["mode"].get(mode) or {}
    return frozenset(m.get("payoff") or ())


def roles_of(moves, item=None, ability=None, megastones=()):
    """The jobs one set covers. Moves may be PBS or Showdown spellings."""
    have = {SC.norm(m) for m in moves}
    r = {k for k, v in ROLE_MOVES.items() if have & v}
    if SC.norm(ability) in WEATHER_ABILITY:
        r.add("weather")
        r.add(WEATHER_ROLE_OF_ABILITY[SC.norm(ability)])
    if item and item in megastones:
        r.add("mega")
    return r


def role_counts(sets_, moves_of=lambda s: s.get("moves") or ()):
    """{role: how many of the six sets cover it}."""
    covered = [{SC.norm(m) for m in moves_of(s)} for s in sets_]
    return {k: sum(1 for c in covered if c & v) for k, v in ROLE_MOVES.items()}


def offence_pct(evs):
    """Share of a set's EV budget spent on offence, 0-100.

    The cheapest honest read of intent that survives the corpus's messiness: it needs
    no species data, no tier and no level, so a level-19 Dwebble and a level-100
    Landorus are on the same scale. 252/252 offensive reads 100, a Chansey reads 0."""
    off = evs.get("atk", 0) + evs.get("spa", 0) + evs.get("spe", 0)
    dfn = evs.get("hp", 0) + evs.get("def", 0) + evs.get("spd", 0)
    return 100.0 * off / max(off + dfn, 1)


def team_offence(evs_list):
    return statistics.mean([offence_pct(e or {}) for e in evs_list])


# ---------------------------------------------------------------- type coverage
# The axis the corpus work never looked at. Roles say what a team DOES; these say
# what it can take and what it can hit, and they are a different question -- a team
# can cover all six roles and still have four members folding to the same attack.
#
# Measured against 6,607 real gen6/7 teams (median, p10-p90):
#   nobody_resists 1 (0-4) | worst_shared 3 (2-4) | off_se 17 (14-18)
#   atk_types 10 (8-12)    | bst_sd 45 (26-72)    | spe_sd 23 (15-32)
#   dup_types 0 (0-0)      -- 92.9% of real teams repeat NO type combination
#
# `dup_types` counts distinct type COMBINATIONS, not first-listed types. The first
# cut used `types[0]`, which is a PBS ordering artifact and not a game concept: it
# scored Azumarill (WATER/FAIRY) and Florges (FAIRY) as different where the real
# question is whether two members share a defensive profile.
COVERAGE_AXES = ("nobody_resists", "worst_shared", "off_se", "atk_types",
                 "bst_sd", "spe_sd", "dup_types")


def type_multiplier(atk, types, chart=None):
    """Damage multiplier of attacking type `atk` into a defender with `types`."""
    weak, res, imm = chart or D.type_chart()
    mult = 1.0
    for t in types:
        if atk in imm.get(t, ()):
            return 0.0
        if atk in weak.get(t, ()):
            mult *= 2
        elif atk in res.get(t, ()):
            mult *= 0.5
    return mult


def coverage(mons):
    """Type coverage of a whole team.

    `mons` is [{"types": [...], "base_stats": [6, PBS order], "moves": [...]}].
    Members whose species could not be resolved are the caller's problem -- pass
    what you could resolve and read `n` back to know how much of the team that was.

    Move types come from Realidea's own moves.txt, so a corpus set carrying a gen 8
    move contributes no attacking type. That undercounts `off_se`/`atk_types` for
    gen 8+ teams and is harmless for the gen 5-7 pool this is used on."""
    chart = D.type_chart()
    mv = D.moves()
    types = [m["types"] for m in mons]
    bst = [sum(m["base_stats"]) for m in mons]
    spe = [m["base_stats"][3] for m in mons]      # PBS order: HP ATK DEF SPD SPA SPDEF

    atk_types = set()
    for m in mons:
        for name in m.get("moves") or ():
            rec = mv.get(SC.norm(name))
            if rec and rec["power"] > 0:
                atk_types.add(rec["type"])

    defending = sorted(chart[0])
    return {
        "n": len(mons),
        # types no member resists: the team's blind spots on defence
        "nobody_resists": sum(1 for a in defending
                              if not any(type_multiplier(a, t, chart) < 1
                                         for t in types)),
        # most members weak to a single attacking type
        "worst_shared": max((sum(1 for t in types
                                 if type_multiplier(a, t, chart) > 1)
                             for a in defending), default=0),
        # types the team can hit super-effectively with a damaging move it owns
        "off_se": sum(1 for d in defending
                      if any(a in chart[0].get(d, ()) for a in atk_types)),
        "atk_types": len(atk_types),
        "bst_sd": statistics.pstdev(bst) if len(bst) > 1 else 0.0,
        "spe_sd": statistics.pstdev(spe) if len(spe) > 1 else 0.0,
        "dup_types": len(mons) - len({frozenset(t) for t in types}),
    }


# ---------------------------------------------------------------- the reference
def build_profile(gens=None):
    """Scan the dump and reduce it to per-archetype role frequencies.

    Only the author-tagged teams feed the per-archetype columns -- no classifier is
    involved, so the numbers are a report of what authors who said "stall" actually
    built. The tagged subset is NOT a sample of the metagame (it over-represents
    stall roughly 2:1, because a stall team is the kind its author bothers to name),
    but that skew is in the class SIZES, which conditioning throws away."""
    import realidea_data as D
    import team_tags

    # Corpus species -> the types Realidea gives them. Only species the game HAS can
    # say anything about which types a mode wants here, and the ~17% that do not map
    # (cross-gen forms, Showdown spellings with no Realidea entry) are dropped rather
    # than guessed at -- a lift is a ratio, and dropping the same rows from both
    # halves of it leaves the ratio alone.
    types_of = {SC.norm(n): sp["types"] for n, sp in D.species().items()}
    speed_of = {SC.norm(n): sp["base_stats"][3] for n, sp in D.species().items()}

    def type_freq(rows):
        """Mean count of each type per mapped set -- the P(type | these teams) that
        type_lift divides. Dual types contribute to both, so this sums past 1.0."""
        n = collections.Counter()
        total = 0
        for sets_ in rows:
            for st in sets_:
                ts = types_of.get(SC.norm(st.get("species")))
                if not ts:
                    continue
                total += 1
                n.update(ts)
        return {t: c / total for t, c in n.items()}, total

    tagged = collections.defaultdict(list)
    by_mode = collections.defaultdict(list)
    every, every_sets = [], []
    for _stem, team in SC.dump_teams(gens=gens):
        rc = role_counts(team["data"])
        off = team_offence([s.get("evs") for s in team["data"]])
        every.append((rc, off))
        every_sets.append(team["data"])
        tag = team_tags.tags(team["name"])
        arch = tag["archetype"]
        if arch:
            tagged[_FOLD[arch]].append((rc, off))
        # A mode tag is the author's word; agreement() checks it against the moves and
        # abilities the team actually runs, and only tags that survive that count. The
        # dropped tags (webs, spikes, baton pass, para, spam) are real team plans that
        # this generator has no role for -- and webs is unbuildable in Realidea at all,
        # since no species in its dex learns Sticky Web.
        for t in tag["weather"] + tag["mode"]:
            role = {"trick room": "trickroom"}.get(t, t)
            if role in MODE_ROLES and team_tags.agreement(t, team["data"]) is True:
                by_mode[role].append(team["data"])

    all_freq, all_mapped = type_freq(every_sets)

    def reduce(rows):
        return {
            "n": len(rows),
            "carry": {k: round(sum(1 for rc, _ in rows if rc[k]) / len(rows), 4)
                      for k in ROLES},
            "mean": {k: round(statistics.mean([rc[k] for rc, _ in rows]), 3)
                     for k in ROLES},
            "offence": round(statistics.mean([o for _, o in rows]), 1),
        }

    # A team's roles are correlated (recovery and status travel together; screens and
    # pivot do not), so questions about whole teams -- "are these nine more alike than
    # nine random ones?" -- cannot be answered from the marginals above. Carrying a
    # fixed-seed sample of real vectors keeps those answerable without the 86 MB.
    rng = random.Random(20260911)
    sample = [[rc[k] for k in ROLES] + [round(off, 1)]
              for rc, off in rng.sample(every, min(SAMPLE_N, len(every)))]

    def move_freq(rows):
        """(sets carrying each move, species carrying it, sets seen)."""
        n = collections.Counter()
        who = collections.defaultdict(set)
        total = 0
        for sets_ in rows:
            for st in sets_:
                total += 1
                for m in {SC.norm(x) for x in (st.get("moves") or ())}:
                    n[m] += 1
                    who[m].add(SC.norm(st.get("species")))
        return n, who, total

    all_mv, _all_who, all_mv_n = move_freq(every_sets)

    def payoff_for(role, rows):
        """Moves `role` over-represents, its own setter move excluded. See
        PAYOFF_LIFT for why the bar is where it is, and why only weather gets one."""
        if role not in WEATHER_MODES:
            return frozenset()
        mv, who, n = move_freq(rows)
        return frozenset(
            m for m, k in mv.items()
            if k >= PAYOFF_MIN_SETS and len(who[m]) >= PAYOFF_MIN_SPECIES
            and m not in ROLE_MOVES[role] and all_mv.get(m)
            and (k / n) / (all_mv[m] / all_mv_n) >= PAYOFF_LIFT)

    def abusers_per_six(role, sets_, payoff):
        """Sets that CASH `role`, normalised to a six-mon team.

        Setter evidence is stripped before asking, so a slow Trick Room user is
        counted once -- as the setter it is -- rather than as both. Without that,
        Trick Room's 2.65 setters swallow its abusers and the rate reads 1.08 where
        the honest figure is 2.0 of six.

        Normalised rather than a per-team mean because Trick Room is judged on base
        speed, and only the corpus sets Realidea has a dex entry for can be judged at
        all. Counting the unjudgeable ones as non-abusers would understate it by the
        coverage gap."""
        part = {"mode": {role: {"payoff": payoff, "type_lift": {}}}}
        hit = seen = 0
        for st in sets_:
            spd = speed_of.get(SC.norm(st.get("species")))
            if role == "trickroom" and spd is None:
                continue              # no base stats for it here; do not guess
            seen += 1
            mv = st.get("moves") or ()
            hit += abuses(role, (), [st.get("ability")], spd, mv, roles_of(mv),
                          prof=part)
        return 6.0 * hit / max(seen, 1)

    flat_every = [st for sets_ in every_sets for st in sets_]

    def reduce_mode(role, rows):
        # Counted through affinity, not role_counts: a sand team's setter is usually
        # Sand Stream and not a Sandstorm move at all, and counting moves alone puts
        # sand's setter_mean at 0.00 -- which would floor a sand plan at one
        # Sandstorm USER and leave the ability holder optional, exactly backwards.
        freq, _n = type_freq(rows)
        payoff = payoff_for(role, rows)
        # affinity() reads its payoff list out of a profile, which is what is being
        # built here, so it is handed the one entry it needs. type_lift is left empty
        # because types are not passed -- this counts setters and abusers, and the
        # ON_TYPE tier is exactly what must not be counted as either.
        part = {"mode": {role: {"payoff": payoff, "type_lift": {}}}}
        setters = [sum(1 for st in team
                       if affinity(role, (), [st.get("ability")], None,
                                   st.get("moves") or (), prof=part) == SETTER)
                   for team in rows]
        return {
            "n": len(rows),
            "setter_mean": round(statistics.mean(setters), 3),
            "abuser_mean": round(abusers_per_six(role, [st for t in rows
                                                        for st in t], payoff), 3),
            # The same count over the WHOLE corpus -- what a team that is not trying
            # would have. It is ~0 for weather (Swift Swim is rare) and 1.3 for Trick
            # Room, because 22% of everything is slow. Without it, one slow Pokemon
            # reads as Trick Room evidence and Trick Room proposes on 19 of 27 fights.
            "abuser_base": round(abusers_per_six(role, flat_every, payoff), 3),
            "payoff": sorted(payoff),
            "type_lift": {t: round(freq[t] / all_freq[t], 2)
                          for t in sorted(freq) if all_freq.get(t)},
        }

    return {
        "version": PROFILE_VERSION,
        "_doc": "Per-archetype role frequencies from extracted/smogon-dump. "
                "`carry` = share of teams with >=1 set covering the role; `mean` = "
                "sets per team; `offence` = mean EV offence share (team_shape."
                "offence_pct). Archetype columns are AUTHOR-TAGGED teams only "
                "(team_tags.py), singles only, six-mon teams only. `mode` columns "
                "are author-tagged AND agreement-validated teams (team_tags."
                "agreement): `setter_mean` = sets per team carrying the mode's own "
                "move, `abuser_mean` = sets per six that CASH the mode (setter "
                "evidence stripped) and `abuser_base` the same over the whole corpus, "
                "`payoff` move, `payoff` = moves the mode over-represents by "
                f"{PAYOFF_LIFT}x (weather only), `type_lift` = P(type | mode teams) "
                "/ P(type | all teams) over "
                f"the {100 * all_mapped // max(sum(len(t) for t in every_sets), 1)}% "
                "of corpus sets whose species exists in Realidea's dex.",
        "gens": sorted(gens) if gens else "all",
        "all": reduce(every),
        "all_type_freq": {t: round(v, 5) for t, v in sorted(all_freq.items())},
        "mode": {m: reduce_mode(m, by_mode[m]) for m in MODE_ROLES if by_mode[m]},
        "sample": {"_doc": f"{len(sample)} real teams drawn from `all`, each "
                           f"[{', '.join(ROLES)}, offence]. Fixed seed.",
                   "rows": sample},
        "archetype": {a: reduce(tagged[a]) for a in ARCHETYPES if tagged[a]},
    }


_MEMO = {}


def profile(refresh=False):
    """The reference, cached to generated/archetype_role_profile.json.

    Cached on disk because the scan reads all 86 MB of the dump, and because the
    result is small, stable and worth committing even when the corpus itself is not.
    Cached in memory as well because affinity() asks it for a type lift once per
    candidate set per sort -- re-parsing 200 KB of JSON there took one rival fight
    from 0.2 s to 80 s."""
    if not refresh and _MEMO.get("prof") is not None:
        return _MEMO["prof"]
    if not refresh and os.path.exists(PROFILE):
        with open(PROFILE, encoding="utf-8") as fh:
            cached = json.load(fh)
        if cached.get("version") == PROFILE_VERSION:
            _MEMO["prof"] = cached
            return cached
    prof = build_profile()
    os.makedirs(GEN, exist_ok=True)
    with open(PROFILE, "w", encoding="utf-8") as fh:
        json.dump(prof, fh, indent=1)
        fh.write("\n")
    _MEMO["prof"] = prof
    return prof


# How many sets must cover a role before a team of this kind looks normal.
#
# Swept against generate_bosses (nine gyms, variety measured as the percentile of the
# teams' mean pairwise role distance against nine real teams; curve as mean absolute
# deviation from the BOSS-CURVE.md target):
#
#   CHASE   floors/gym   floors met   curve MAD   variety pctile   removal
#    0.70       4.7          82%        6.6 BST        2.3%          4/9
#    0.80       3.3          78%        6.4 BST        4.2%          4/9
#    0.90       1.8          87%        3.8 BST        5.4%          1/9
#    none       0.0           --        1.5 BST        2.0%          0/9
#
# The result that decides it: MORE floors do not buy more variety. Past ~2 per team
# the floors start competing with each other for six slots, every one of them gets
# filled by whichever in-band species happens to carry the role, and the teams
# converge again -- while the curve pays for the constraint the whole way. 0.90 keeps
# only the roles a class almost always has (stall's recovery, hyper offence's setup)
# and leaves the rest to the caps.
#
# Raise it to 0.80 if removal specifically matters: no archetype carries removal 90%
# of the time, so at 0.90 nothing forces it and only 1 of 9 bosses ends up with any.
CHASE = 0.90


def role_plan(archetype, prof=None):
    """{"floor": {role: min sets}, "cap": {role: max sets}} for an archetype.

    Derived, not typed in -- floors are the corpus mean rounded, kept only for roles
    a clear majority of that archetype carries at all. The distinction the old flat
    QUOTA could not draw is a COUNT one: hyper offence does not merely "have setup",
    it averages 3.06 setup sets and 0.88 recovery, while stall averages 4.76 recovery
    and 0.31 pivot. Presence quotas score both of those as a tick in the same box.

    Caps are mean+1. They are what stops a published-set generator from drifting back
    to the middle: left uncapped, a hyper-offence team still collects recovery,
    because most published sets for a bulky mon carry some, and the team ends up
    balance with a Swords Dance on it."""
    prof = prof or profile()
    a = prof["archetype"][archetype]
    # Modes are excluded from BOTH halves. The floor half is obvious -- no archetype
    # carries sun 90% of the time. The cap half is the load-bearing one: a cap is
    # read as "already covered, prefer sets without it", so an archetype cap of 1 on
    # a mode would make one incidental Sunny Day steer every later pick, and would
    # fight mode_plan() head-on whenever a mode IS set.
    job = [k for k in ROLES if k not in MODE_ROLES]
    return {
        "floor": {k: round(a["mean"][k]) for k in job
                  if a["carry"][k] >= CHASE and round(a["mean"][k]) >= 1},
        "cap": {k: round(a["mean"][k]) + 1 for k in job},
    }


def abuses(mode, types, abilities, base_speed, moves, roles=(), prof=None):
    """Does this set CASH `mode`? Setter evidence is set aside before asking.

    The tiers in affinity() are exclusive -- a set is scored as the best thing it is
    -- but the two JOBS are not. A Swift Swim Kingdra holding Rain Dance both turns
    rain on and wins under it, and answering "setter, therefore not an abuser" is
    what would make a mode plan cost two slots where the dex offers one body that
    does both. Every caller that asks "is this an abuser" comes through here, so the
    builder and the scorer cannot drift apart on the answer."""
    if not mode:
        return False
    mv = [m for m in moves if SC.norm(m) not in ROLE_MOVES[mode]]
    ab = [a for a in abilities if SC.norm(a or "") not in WEATHER_ABILITY]
    return affinity(mode, types, ab, base_speed, mv, roles, prof) == ABUSER


def min_roster_abusers(mode, prof=None):
    """How many mons on the DEV's own roster must cash `mode` before it is proposed.

    One more than a team that is not trying would carry. For weather that is 1 --
    Swift Swim and Drought are rare enough that one is a statement. For Trick Room it
    is 2, because 22% of the whole dex is slow and a single slow Pokemon is not
    evidence of anything; read as 1 it proposed Trick Room on 19 of 27 fights."""
    base = (prof or profile())["mode"][mode]["abuser_base"]
    return max(1, round(base) + 1)


def mode_plan(mode, prof=None):
    """{"floor": ..., "cap": ...} for the mode role itself, from the corpus.

    How many setters a real team of this kind runs, +-1. The asymmetry between
    weather and Trick Room is the whole reason this is measured rather than typed
    in: one Drought is the entire sun plan and a second is a wasted slot, while TR
    teams average 2.91 Trick Room users because the mode lasts five turns and has to
    be re-set. Weather is clamped to 2 regardless of what the mean rounds to."""
    prof = prof or profile()
    mean = prof["mode"][mode]["setter_mean"]
    cap = round(mean) + 1
    if mode in WEATHER_MODES:
        cap = min(cap, 2)
    # A setter with nothing to cash it is not a mode team, it is a wasted slot. Every
    # rain team in the corpus carries an abuser or a rain-boosted attack -- 141 of
    # 141, none carry neither -- and the same holds at 97-100% for the other three.
    # Floored at one because that is what the thinnest of them (sand, 1.01/team)
    # actually runs; rain and sun average 1.28 and 1.22 and could argue for two, but
    # that costs a slot and is not worth claiming before it is measured.
    return {"floor": {mode: max(1, round(mean) - 1), abuse_role(mode): 1},
            "cap": {mode: cap}}


def affinity(mode, types, abilities, base_speed, moves, roles=(), prof=None):
    """How much one set has to do with `mode`: SETTER, ABUSER, ON_TYPE or NONE.

    Lives here rather than in the generator because generate_bosses CHASES this and
    fight_context SCORES it, and a mon the scorer calls an abuser but the builder
    does not would make the evidence self-confirming.

    ON_TYPE is deliberately its own tier and not a weak ABUSER. Sharing a type a mode
    over-represents is a fact about the metagame the mode lives in, not about this
    set: sand teams run a lot of Steel, so six Steels score for sand while abusing
    nothing. Callers that RANK may treat the tiers as one ordinal scale -- they are
    monotone -- but callers that make a CLAIM ("this is a rain fight") must require
    ABUSER or better."""
    if not mode:
        return NONE
    ab = {SC.norm(a) for a in abilities if a}
    mv = {SC.norm(m) for m in moves}
    if mv & ROLE_MOVES[mode] or any(WEATHER_ROLE_OF_ABILITY.get(a) == mode
                                    for a in ab):
        return SETTER
    if ab & MODE_ABUSER_ABILITY.get(mode, set()) or mv & payoff_moves(mode, prof):
        return ABUSER
    if mode == "trickroom":
        return ABUSER if base_speed is not None and base_speed <= TR_SLOW else NONE
    if mode == "screens":
        # Screens buy turns; what spends them is a sweeper setting up behind them.
        return ABUSER if "setup" in roles else NONE
    lift = (prof or profile())["mode"][mode]["type_lift"]
    return ON_TYPE if any(lift.get(t, 0) >= LIFT_MIN for t in types) else NONE


if __name__ == "__main__":
    import sys
    p = profile(refresh="--refresh" in sys.argv)
    print(f"corpus n={p['all']['n']}   archetype-tagged "
          f"{sum(a['n'] for a in p['archetype'].values())}\n")
    print(f"{'role':<10}{'all':>7}   " + "".join(f"{a[:11]:>12}" for a in ARCHETYPES))
    for k in ROLES:
        print(f"{k:<10}{100 * p['all']['carry'][k]:>6.0f}%   " + "".join(
            f"{100 * p['archetype'][a]['carry'][k]:>11.0f}%" for a in ARCHETYPES))
    print(f"{'offence':<10}{p['all']['offence']:>6.0f}%   " + "".join(
        f"{p['archetype'][a]['offence']:>11.0f}%" for a in ARCHETYPES))
    print(f"{'n':<10}{p['all']['n']:>7}   " + "".join(
        f"{p['archetype'][a]['n']:>12}" for a in ARCHETYPES))
