#!/usr/bin/env python3
"""Gym-boss team generator (TEAM-DESIGN.md §6.5 lever 1).

Rebuilds the nine gym-leader / champion teams to hit BOSS-CURVE.md's effective-BST
ladder using REAL species power, never inflated EVs: every set stays inside the legal
510-EV budget, so `cheat_tier` is false and the difficulty comes from the roster.

Four inputs decide each team:

  target eBST   the curve below -- Reborn Yang Intense's measured ladder, stretched
                so the Champion lands on 600 (BOSS-CURVE.md §2)
  level         Realidea's own cap remapped onto Unbound's expert curve, so every
                boss meets the player at parity instead of 6-10 levels under
  theme        the leader's type, as a MINIMUM of four slots, not a maximum
  sets          published Smogon sets, intersected with what the species can
                actually learn at that level (extracted/smogon-sets/)
  plan          the fight's archetype, and optionally a MODE the whole team is built
                around (sun, sand, Trick Room...). Derived by fight_context.py and
                chosen in generated/fight_plans.json; see TEAM-DESIGN.md §6.8.

assemble() below is shared with generate_trainers.py -- it is the one team-assembly
loop, and the differences between a gym leader and a rival are its spec fields.

Usage:
    generate_bosses.py                     # preview table
    generate_bosses.py Bay Lilliana        # + full rosters for those leaders
    generate_bosses.py --json out.json     # emit teams for validate_team.py
    generate_bosses.py --stats-only ...    # drop Smogon's copyrighted dex sets
"""
import collections
import functools
import json
import os
import random
import re
import sys

import realidea_data as D
import smogon_corpus as SC
import team_shape as TS

HERE = os.path.dirname(os.path.abspath(__file__))
STUDY = os.path.dirname(HERE)
GEN = os.path.join(STUDY, "generated")
EXTRACTED = os.path.join(STUDY, "extracted")

# Every Mega Evolution and both Primals are exactly +100 BST over the base form, and
# Realidea keeps mega stats in MultipleForms.rb rather than pokemon.txt -- so the
# base species' PBS BST understates a mega holder by exactly this much.
MEGA_BONUS = 100

# ------------------------------------------------------------- the progression
# Everything below is a SCHEDULE: a value that changes with the badge count, or the
# badge at which something switches on. They are gathered here because that is the
# one axis they share -- a change to any of them moves where the difficulty arrives,
# and reading them apart from each other is how gym 4 ended up with megas it could
# not use. Nothing here is per-fight taste; THEME and the archetype/mode plans are.
# Target eBST per badge. Reborn Yang Intense's measured curve (BOSS-CURVE.md §2)
# linearly stretched to land the Champion on 600. The dip at badge 5 is Reborn's own
# shape -- its Shelly (487) outweighs its Shade (472) -- and is kept deliberately.
TARGET = [397, 487, 504, 551, 525, 583, 593, 597, 600]
# Measured BST spread within each Reborn fight; the band is target +- spread/2.
SPREAD = [190, 190, 230, 61, 110, 140, 45, 85, 100]
# Ubers unlock at gym 7 -- the user wants them to arrive, but as the late escalation.
UBER_FROM = 6
# Legendaries and pseudo-legends unlock at gym 6, one step before the Ubers. Detected
# by BST rather than by name, because Realidea's dex is not the official one: it holds
# fakemon (MEGUMIN 618, TARTAGLIA 232) that no name list would ever cover, and the one
# thing a legendary reliably is is overstatted for where it stands.
#
# 580 is where the dex itself cuts. Every species in 580-599 is a legendary and there
# are eighteen of them with no ordinary Pokemon among them -- the birds, the beasts,
# the genies, the Regis, the lake trio, the musketeers -- and 600 is the pseudo-legend
# cliff, where Dragonite, Tyranitar, Metagross, Garchomp, Hydreigon, Goodra and
# Salamence sit EXACTLY alongside Manaphy, Jirachi, Latios, Cresselia and Diancie. So
# the test is `>=` and not `>`: at `> 600` it catches not one pseudo-legend.
#
# Drawing it at 600 instead (the user's first suggestion) is a real option and one
# slider click away, but it does not deliver what was asked for: it leaves Uxie on
# gym 3 and Regice on gym 4, so the rule "no legendary before gym 6" would still be
# broken by two legendaries. Moving 600 -> 580 costs 0.8 BST of curve MAD and removes
# exactly those two.
#
# The floor is 580 and not 570 on purpose. 570-579 is the Ultra Beasts and Silvally,
# nothing else, and the user wants them available: "xurkitrees beast boost work and
# they should be in the generator." The Tapus are 570 too and are gone anyway, but
# for a different and permanent reason -- see DEAD_PRIMARY.
#
# This gates eligible(), which is only consulted for GENERATED picks. A leader who
# already owns a legendary keeps it at any badge -- Cintia's Garchomp and Teresa's
# Manaphy are the dev's own casting decisions, and this knob is about what we add.
LEGEND_BST = 580
LEGEND_FROM = 5
# Gym 4's town, Ciudad Anatasa (map 96), is where strong held items and mega stones
# become purchasable. Before it, a boss may only carry gear an early player plausibly
# has: berries and type-boost items, and no mega at all.
#
# THIS ASSUMES TWO GAME EDITS THAT DO NOT EXIST YET (both on the backlog):
#   1. a shop in Ciudad Anatasa selling the strong items. Today the only megastone
#      source in the game is a mart in Centro Comercial P3, the mall in Ciudad
#      Amatista -- gym SEVEN's city -- and Choice items, Focus Sash, Assault Vest and
#      Rocky Helmet have no source anywhere at all.
#   2. moving game switch 512. Realidea commented out the stock Mega Ring check in
#      PokeBattle_Battle#pbCanMegaEvolve? and replaced it with
#      `$game_switches[512]==false && $game_switches[234]==false`. Switch 512 is set
#      once, by Simon's "Sistema Realidea" event on Map333 / Ruta 13 (its own
#      trainers are level 38 -- gym 5's cap). Until that set moves to Ciudad Anatasa,
#      NOBODY can mega at gyms 4-5 however many stones they own, and the megas this
#      generator places there will not fire. The check sits above the ownership test,
#      so it gates trainers exactly as it gates the player.
# (Switch 234 is a separate temporary enable, toggled on and back off inside the
# Battle Arena for its set-piece fights.)
UNLOCK_STAGE = 3
# Early-game move-power ceiling. TM legality has NO level test -- tm.txt says which
# species CAN learn a machine, never when -- so with nothing to stop it a level-19
# Dwebble is handed Earthquake and a level-25 Wigglytuff Fire Blast.
#
# 70 leaves a boss a real attacking move (it is also exactly U-turn and Volt Switch,
# the only two pivot moves there are) while keeping the 90-110 BP nukes out of a
# fight the player meets at level 20. It lifts entirely after gym 3: by then the
# player has the Anatasa shop, megas and level ~36, and a published Smogon set
# should apply as written.
BP_CAP = 70
BP_CAP_UNTIL = 3          # stages 0-2 = gyms 1-3

# Badge from which a fight may be given a MODE (sun, sand, Trick Room...). 0 means
# any fight may have one; the plan that assigns them is fight_context.py, and this
# only says from where they are allowed to arrive.
MODE_FROM = 0

# ------------------------------------------------------------- per fight
# Type theme per leader, from their existing roster.
THEME = {"Abi": "BUG", "Aimi": "FAIRY", "Kenn": "WATER", "Douglas": "ICE",
         "Ciara": "DARK", "Dhara": "GROUND", "Lawrence": "PSYCHIC",
         "Bay": "NORMAL", "Lilliana": "STEEL"}
ON_THEME_MIN = 4          # of 6; the rest may be off-theme (user: "1,2 can differ")
TEAM_SIZE = 6
# Off-theme picks must earn the slot: this much Smogon co-occurrence with the core,
# or a resistance to what the theme is weak to. Ungated, correlation alone drags in
# mons that merely share a metagame (a Mandibuzz onto a Steel champion).
MIN_CORR = 25.0
# How many of the dev's own Pokemon a fight may SPEND to cover a floor nothing else
# can reach. 0 is the shipped behaviour: every original that fits the band is kept and
# a floor no remaining body covers is simply reported missed. Raising it trades the
# least useful kept mon for one that does the job -- see assemble() step 5 for the two
# things it will never trade away, neither of which is a setting.
KEEP_DROP = 0
# Competence tests for the dev's OWN Pokemon, both OFF by default because a fangame
# roster is a design choice before it is a competitive one -- a level-31 water gym is
# SUPPOSED to be low tier. Measured across the nine gyms: the published-set test drops
# 3 of 37 kept mons (Vespiquen, Pyukumuku, Mightyena, all of which fall through to
# fallback() and are written from the learnset); the UU floor drops 28 of 37, taking
# every kept mon in gyms 1, 2, 3 and 7, which is not "drop the incompetent ones", it
# is "replace the rosters". They are separate knobs for that reason.
# Which published-set FORMATS a build may draw from -- SC.set_tier of a set's
# provenance ("ou", "uu", "ubers", "monotype", ...). Empty means all 14, which is
# today's behaviour. This filters the SET pool, not the species pool: it is a
# different question from a tier ceiling, which asks what a species is ranked.
SET_FORMATS = ()
# 1 keeps the learnset LEVEL gate: a published move the species has not reached yet is
# dropped and the slot topped up from filler. 0 lets the set keep it. The species gate
# is not optional either way -- a mon that can never learn a move never gets it.
EARLY_MOVES = 0
# Reroll seeds. 0 is off on both, and off is today's behaviour byte-for-byte.
#
# They are two knobs because they reroll two different decisions and one of them is
# far cheaper than the other. SET_SEED changes only WHICH published set a species
# gets, so the roster is untouched and every mon is still a mon the dev chose or the
# curve asked for. PICK_SEED changes WHICH SPECIES get picked, which rewrites the
# team. Measured over the nine gyms: a set seed moves 11-18 of 54 mons' sets and
# almost no species; a pick seed moves 32-41 of 54 species.
SET_SEED = 0
PICK_SEED = 0
# Per-fight overrides a person made on a Builder card, keyed by fight:
#   {"keep": {SPECIES: bool}, "sets": {SPECIES: [label, ...]}}
# `keep` is a TRISTATE by omission -- absent means "whatever this fight does by
# default", True pins a species onto the roster, False drops one the roster has. That
# is why it is a dict of bools and not a list of names: "not mentioned" and "turned
# off" are different instructions, and a list cannot say the second.
PICKS = {}


def picks_for(key):
    got = PICKS.get(key) or {}
    return got.get("keep") or {}, got.get("sets") or {}

KEEP_NEED_SET = 0   # 1 = drop a kept original with no published set usable at its level
KEEP_MIN_BAND = 0   # 0 = off; else how many tier bands from the top a kept original may
                    # sit in, over SC.BANDS -- 3 is "Uber, OU or UU"

# ------------------------------------------------------------- the early item pool
# What a boss may hold before UNLOCK_STAGE. Type-boost items are the classic 17
# 20%-boosters; intersecting with the extracted source list keeps even this pool
# honest, so nothing here is something the player cannot already find.
TYPE_BOOST = {"MIRACLESEED", "CHARCOAL", "MYSTICWATER", "MAGNET", "NEVERMELTICE",
              "BLACKBELT", "POISONBARB", "SOFTSAND", "SHARPBEAK", "TWISTEDSPOON",
              "SILVERPOWDER", "HARDSTONE", "SPELLTAG", "DRAGONFANG", "BLACKGLASSES",
              "METALCOAT", "SILKSCARF"}

# which type each of those boosts, for substitute_item()
_TYPE_OF_BOOST = {"MIRACLESEED": "GRASS", "CHARCOAL": "FIRE", "MYSTICWATER": "WATER",
                  "MAGNET": "ELECTRIC", "NEVERMELTICE": "ICE", "BLACKBELT": "FIGHTING",
                  "POISONBARB": "POISON", "SOFTSAND": "GROUND", "SHARPBEAK": "FLYING",
                  "TWISTEDSPOON": "PSYCHIC", "SILVERPOWDER": "BUG", "HARDSTONE": "ROCK",
                  "SPELLTAG": "GHOST", "DRAGONFANG": "DRAGON", "BLACKGLASSES": "DARK",
                  "METALCOAT": "STEEL", "SILKSCARF": "NORMAL"}
# ---------------------------------------------------------------- roles
# The role table itself lives in team_shape.py, so that what the generator CHASES and
# what boss_diagnostic.py MEASURES cannot drift apart.
#
# Only these six are chased. team_shape carries five more (priority, status, protect,
# phaze, screens) that exist to tell archetypes apart, and they must stay out of the
# exemption below: a priority or screens user is still an attacker, and folding e.g.
# Extreme Speed (80 BP) into ROLE_MOVE would walk it straight through BP_CAP into a
# level-19 fight, as well as hiding it from the coverage count.
CHASED = ("hazards", "removal", "setup", "pivot", "recovery", "speed")
CHASED_SET = frozenset(CHASED)
ROLE_MOVES = {r: TS.ROLE_MOVES[r] for r in CHASED}
# The power ceiling is about damage output, and a role move's point is not its
# damage: of the moves that carry a role at all, only three deal any (U-turn and
# Volt Switch at 70, Icy Wind 55, Rapid Spin 20), and the two pivot moves are the
# ONLY two there are -- capping them cost gyms 1 and 2 the pivot role outright.
ROLE_MOVE = set().union(*[set(v) for v in ROLE_MOVES.values()])

# Which playstyle each fight is built as, gym 1 -> Champion. THE design knob here:
# everything below is derived from the corpus, but this line is a choice about the
# game, and nothing in the data can make it.
#
# It exists because the old flat QUOTA did not. Measured against 54k real teams, the
# nine shipped bosses sat in the 0.0th percentile for variety ACROSS EXACTLY THE FOUR
# ROLES THE QUOTA NAMED, and the 93rd across the seven it did not -- i.e. the teams
# were not samey by accident or because of the level caps, they were samey precisely
# where they were told what to carry. Nine random ladder teams differ more from each
# other than nine themed gym leaders did. See boss_diagnostic.py.
# Chosen off the gym x archetype feasibility matrix (boss_diagnostic.py --matrix),
# which settles two things guessing could not:
#
#   STALL IS NOT BUILDABLE HERE, on any theme. It wants five of six sets carrying
#   recovery; Realidea's dex, filtered to a 4/6 type theme and a BST band, tops out
#   at 67% of that on its two best themes (Ground, Normal) and 33% on the other
#   seven. It stays in team_shape.ARCHETYPES -- it is a real thing 336 corpus authors
#   built -- and out of this list.
#
#   GYM 6 CANNOT REACH ITS TARGET, and not because of anything here: every archetype
#   lands it between -11 and -28, and the old flat-quota generator missed it by -13
#   too. Ground at eBST 583 is the hole; `offense` is merely its least-bad cell.
#   Fixing it means TARGET[5], the theme, or the band -- see BOSS-CURVE.md.
ARCHETYPE = ["offense", "balance", "bulky offense", "hyper offense", "offense",
             "offense", "balance", "bulky offense", "bulky offense"]
# The other half of a fight's plan: a MODE the whole team is built around, or None.
# Static default is None everywhere -- a mode is a claim that one fight is about sun
# or Trick Room, and nothing in the corpus can make that claim for a particular gym.
# fight_context.py derives candidates and writes the chosen ones to PLANS_PATH.
MODE = [None] * 9
# Mechanical caps -- these are not about playstyle. A second Stealth Rock does
# nothing on any team ever built, and the mega and weather budgets are one apiece.
# They override the archetype's own (softer) cap wherever they are tighter.
ROLE_CAP = {"hazards": 1, "removal": 1, "mega": 1, "weather": 1}


# generate_trainers.py builds the rivals and named route trainers, which have no
# archetype and are not trying to be ladder teams: an ordinary trainer gets the flat
# presence quota the bosses used to share. Kept here, next to what replaced it, so
# the difference is a decision on the page rather than two copies drifting apart.
FLAT_QUOTA = ["hazards", "recovery", "setup", "pivot", "mega"]

# Where the CHOSEN plans live, once fight_context.py has derived and someone has
# picked them. Absent, every fight falls back to the static defaults above -- which
# is what keeps both generators dump-free and reproducible from the repo alone.
PLANS_PATH = os.path.join(GEN, "fight_plans.json")


def load_plans():
    """{fight id: {"archetype": .., "mode": ..}} — the user's choices, or {}."""
    if not os.path.exists(PLANS_PATH):
        return {}
    with open(PLANS_PATH, encoding="utf-8") as fh:
        return json.load(fh).get("fights") or {}


def plan_of(fight_id):
    """(archetype|None, mode|None) for any fight, gym or not. None = the default.

    An ABSENT entry means the static default, never "ask the deriver": the
    generators must produce the same teams from a clean checkout as they do after
    fight_context.py has run, or nothing downstream is reproducible."""
    entry = load_plans().get(fight_id) or {}
    return entry.get("archetype"), entry.get("mode")


def plan_for(archetype, mega_ok, mode=None):
    """(floors, caps) for a fight: what it must carry, and at most.

    `archetype` None is the flat presence quota above -- what a named trainer with no
    playstyle assigned gets. An archetype replaces it with COUNTS from the corpus,
    and a mode adds its own setter floor on top. The three never contradict each
    other because they name disjoint roles: role_plan() never returns a mode role
    (team_shape.MODE_ROLES) and FLAT_QUOTA names neither."""
    if archetype:
        plan = TS.role_plan(archetype)
        floor, cap = dict(plan["floor"]), dict(plan["cap"])
    else:
        floor, cap = {r: 1 for r in FLAT_QUOTA if r != "mega"}, {}
    if mega_ok:
        floor["mega"] = 1
    caps = {r: min(cap.get(r, 99), ROLE_CAP.get(r, 99))
            for r in set(cap) | set(ROLE_CAP)}
    if mode:
        mp = TS.mode_plan(mode)
        floor.update(mp["floor"])
        caps.update(mp["cap"])
    # A floor the cap forbids is a generator that spins: hazards floors at 1 and the
    # mechanical cap is 1, which is fine, but nothing guarantees that in general.
    return floor, {r: max(c, floor.get(r, 0)) for r, c in caps.items()}


@functools.lru_cache(maxsize=None)
def root(name):
    """The bottom of `name`'s evolution line -- one key per family.

    Here rather than in fight_context because it is a fact about the dex, and because
    generate_trainers.recurring() needs it to say which families a rival always
    brings."""
    cur, seen = name, set()
    while cur not in seen:
        seen.add(cur)
        pre = sorted(p for p, sp in _sp.items()
                     if any(c[0] == cur for c in sp["evolutions"]))
        if not pre:
            break
        cur = pre[0]
    return cur


def mode_evidence(species, mode):
    """Is this species part of WHY a fight reads as a `mode` fight?

    A bare species, every ability it could have, no set yet -- the same question
    fight_context asks of the dev's roster before proposing the mode. It is asked
    again at build time for one reason: a mon that supplied the evidence must not
    then be dropped to make room for the plan it justified. That would leave a sand
    team whose entire reason for being a sand team has been deleted, which is the
    same shape of error as counting a type lift below 1.0 in a mode's favour."""
    sp = _sp.get(species)
    if not sp or not mode:
        return False
    abil = list(sp["abilities"]) + [sp["hidden_ability"]]
    spd = sp["base_stats"][3]
    return (TS.affinity(mode, sp["types"], abil, spd, ()) == TS.SETTER
            or TS.abuses(mode, sp["types"], abil, spd, ()))


def ability_name(mon):
    """The ability string for a built mon. Slot 2 is the hidden one unless the
    species happens to list three, which is how build() encoded it either way."""
    sp = _sp.get(mon["species"])
    if not sp:
        return None
    if mon["ability"] < len(sp["abilities"]):
        return sp["abilities"][mon["ability"]]
    return sp["hidden_ability"] or None


def roles_of(moves, item, ability, mode=None, sp=None):
    """The jobs one set covers, plus `<mode>_abuse` when the set CASHES the mode.

    The abuse role is derived here rather than in team_shape because it needs the
    species -- types and base speed -- as well as the set. It goes through
    TS.affinity so the role the builder chases and the tier fight_context scores are
    the same test: a mon the scorer calls an abuser but the builder will not chase
    would make the evidence self-confirming.

    Without it the plan asks for a setter and nothing else, which is how a rain team
    came to be six Bugs and a lone Rain Dance nobody on the team can use."""
    r = TS.roles_of(moves, item, ability, MEGASTONE)
    if mode and sp is not None and TS.abuses(
            mode, sp["types"], [ability], sp["base_stats"][3], moves, r):
        r.add(TS.abuse_role(mode))
    return r


# ---------------------------------------------------------------- PBS-derived
_sp = D.species()
_floor = D.min_level()
_mv = D.moves()
_items = D.items()

# Mega stones, mapped to the species they evolve. Realidea's spellings are irregular
# (GLALITE, HERACRONITE, BLASTOISINITE), so match on longest common prefix rather
# than trying to strip a suffix. EVIOLITE and EVERSTONE also end in ITE and are not
# stones -- a plain endswith("ITE") test silently spends the one-mega budget on an
# Eviolite holder.
def _stone_owner(stone):
    """Longest common prefix, tie-broken toward the name that IS the stem.

    Breaking ties by nearness to the stone's own length instead picks the wrong
    member of an evolution line: PIDGEOTITE and PIDGEOTTO share the same 7-character
    prefix as PIDGEOT, and PIDGEOTTO (9) is closer to the 10-character stone -- which
    silently cost Bay her Mega Pidgeot. The owner's name ends where the prefix ends,
    so prefer the shortest overhang."""
    def lcp(name):
        i = 0
        while i < len(name) and i < len(stone) and name[i] == stone[i]:
            i += 1
        return i
    best = max(_sp, key=lambda n: (lcp(n), -(len(n) - lcp(n))))
    return best if lcp(best) >= 4 else None


MEGASTONE = {}      # stone -> species
for _i in _items:
    if _i.endswith(("ITE", "ITEX", "ITEY")) and _i not in ("EVERSTONE", "EVIOLITE"):
        _owner = _stone_owner(_i)
        if _owner:
            MEGASTONE[_i] = _owner
MEGA_OF = collections.defaultdict(set)      # species -> its stones
for _stone, _owner in MEGASTONE.items():
    MEGA_OF[_owner].add(_stone)


WEAK, RESIST, IMMUNE = D.type_chart()


@functools.lru_cache(maxsize=1)
def item_sources():
    """{ITEM: [how the player can get it]} from extract_item_sources.py."""
    path = os.path.join(GEN, "realidea_item_sources.json")
    if not os.path.exists(path):
        raise SystemExit(f"missing {path} — run tools/extract_item_sources.py first")
    return json.load(open(path, encoding="utf-8"))


@functools.lru_cache(maxsize=1)
def early_items():
    obtainable = set(item_sources())
    return ({i for i in _items if i.endswith("BERRY")} | TYPE_BOOST
            | {"EVIOLITE", "BERRYJUICE"}) & obtainable


def bp_cap(stage):
    """The power ceiling for a fight in `stage`, or None once it lifts."""
    return BP_CAP if stage < BP_CAP_UNTIL else None


def bst(name):
    return _sp[name]["bst"]


def potential_bst(name, mega_available=True):
    """BST this species could bring, counting a mega stone it can actually hold.

    Only while the one-mega budget is still open: once it is spent, a Camerupt is a
    460, not a 560, and ranking it as a 560 skews every later pick."""
    return bst(name) + (MEGA_BONUS if mega_available and MEGA_OF.get(name) else 0)


def ebst(mon):
    """Effective BST of a built mon -- base, plus the mega it is actually holding."""
    return bst(mon["species"]) + (MEGA_BONUS if mon.get("item") in MEGASTONE else 0)


# ---------------------------------------------------------------- level remap
def _remap_anchors(mode=None):
    """Anchors for remap(). `mode` overrides the curve file's own active_mode, which
    is what lets a caller preview the other level ladder without editing the file."""
    caps = json.load(open(os.path.join(GEN, "realidea_level_caps.json")))
    curve = json.load(open(os.path.join(GEN, "realidea_level_curve.json")))
    prog = {p["stage"]: p for p in curve["progression"]}
    mode = mode or curve["active_mode"]
    xs = [0] + [c["cap"] for c in caps] + [66]
    ys = ([0] + [prog[c["badges"]][mode] for c in caps]
          + [curve["champion"][mode]])
    return caps, xs, ys


CAPS, _AX, _AY = _remap_anchors()


def gym_id(idx):
    """The id `as_team_record` emits for gym `idx`, and the key plans are filed under."""
    cap = CAPS[idx]
    return f"gym{idx + 1}_{cap['trainer_type']}_{cap['trainer']}"


# Apply the chosen plans. This sits here, and not next to ARCHETYPE, only because
# gym_id needs CAPS -- but it must still land before CHASED_ROLES below, which is a
# statement about what the nine fights are actually told to carry.
for _i in range(len(CAPS)):
    _a, _m = plan_of(gym_id(_i))
    if _a:
        ARCHETYPE[_i] = _a
    if _m:
        MODE[_i] = _m

# Every role some fight is told to carry -- what boss_diagnostic.py must hold out to
# ask whether being told is what makes the nine teams alike.
CHASED_ROLES = sorted({r for a in set(ARCHETYPE) for r in TS.role_plan(a)["floor"]})


def remap(level):
    """Realidea's own level -> the Unbound expert cap for the same story point.

    Piecewise-linear through the boss ladder, so every anchor lands exactly on its
    cap and everything between it interpolates. Without this the player fights every
    boss 6-10 levels over-levelled, and closing that gap with BST alone would need
    +378 BST at gym 1 -- more than Reborn's entire nine-badge climb."""
    for i in range(len(_AX) - 1):
        if _AX[i] <= level <= _AX[i + 1]:
            span = _AX[i + 1] - _AX[i]
            return max(2, round(_AY[i] + (level - _AX[i]) / span * (_AY[i + 1] - _AY[i])))
    return level


# ------------------------------------------------------ where a fight sits in the story
# MapInfos grouping nodes: folders in the editor's tree, not places in the world, so
# they carry no story position and the walk below must stop at them.
_FOLDER = {"Localizaciones", "Rutas", "Otros"}


def stage_of(level):
    """Badge band a level belongs to -- picks its eBST target and item pool."""
    for i, c in enumerate(CAPS):
        if level <= c["cap"]:
            return i
    return len(CAPS) - 1


@functools.lru_cache(maxsize=1)
def _map_tree():
    import marshal_rb
    mi = marshal_rb.load(os.path.join(os.path.dirname(D.PBS), "Data", "MapInfos.rxdata"))
    name, parent, kids = {}, {}, collections.defaultdict(list)
    for key, info in mi.items():
        key = int(key)
        name[key] = info.get("@name")
        parent[key] = info.get("@parent_id") or 0
        kids[parent[key]].append(key)
    level = collections.defaultdict(list)
    for b in json.load(open(os.path.join(EXTRACTED, "realidea-battles.json"),
                            encoding="utf-8")):
        fixed = [m["level"] for m in b["party"] if isinstance(m["level"], int)]
        if fixed:
            level[b["map"]].append(max(fixed))
    return name, parent, kids, level


def _route_no(map_name):
    m = re.match(r"Ruta (\d+)$", map_name or "")
    return int(m.group(1)) if m else None


def story_level(map_id):
    """The level the game itself pins to this place, and how that was established.

    A `balanceo` fight scales to the player's party, so it carries no level of its
    own -- but its eBST target and item pool still have to come from somewhere. Take
    it from the nearest map the developer DID pin: the fight's own map first, then
    the area it hangs under in MapInfos (Fabrica Rocket sits under Ciudad Anatasa,
    whose gym pins it at 33), then -- for a numbered route, which hangs off the flat
    `Rutas` folder and so has no area to inherit -- the routes either side of it."""
    name, parent, kids, level = _map_tree()

    def subtree_max(m):
        got, stack = [], [m]
        while stack:
            x = stack.pop()
            got += level.get(x, [])
            stack += kids.get(x, [])
        return max(got) if got else None

    own = subtree_max(map_id)
    if own:
        return own, "own map"
    up = parent.get(map_id, 0)
    while up and name.get(up) not in _FOLDER:
        got = subtree_max(up)
        if got:
            return got, "area %s" % name[up]
        up = parent.get(up, 0)
    here = _route_no(name.get(map_id))
    if here:
        near = {}
        for k, nm in name.items():
            n = _route_no(nm)
            if n and level.get(k):
                near[n] = max(near.get(n, 0), max(level[k]))
        lo = max((n for n in near if n < here), default=None)
        hi = min((n for n in near if n > here), default=None)
        seen = [near[n] for n in (lo, hi) if n is not None]
        if seen:
            return round(sum(seen) / len(seen)), "between Ruta %s and Ruta %s" % (lo, hi)
    raise ValueError("no story level for map %s (%s)" % (map_id, name.get(map_id)))


def area_of(map_id):
    """The place a map belongs to -- its outermost non-folder ancestor, else itself.

    Fabrica Rocket's interior maps all resolve to Ciudad Anatasa; a numbered route
    hangs straight off the `Rutas` folder and so is its own area."""
    name, parent, _kids, _lvl = _map_tree()
    here = map_id
    up = parent.get(map_id, 0)
    while up and name.get(up) not in _FOLDER:
        here, up = up, parent.get(up, 0)
    return here


def map_stage(map_id):
    level, how = story_level(map_id)
    return stage_of(level), how


# ---------------------------------------------------------------- set building
def legal_moves(species, level, cap=None):
    """Every move the species can have at `level`, TMs included.

    `cap` is a SOFT power ceiling: damaging moves above it are dropped, unless that
    would leave the species with no attack at all, in which case its weakest one is
    kept. Status moves are never capped -- they have no power to cap."""
    known = [m for m in _mv if D.learnable(species, m, level, 0) in ("levelup", "tm")]
    if cap is None:
        return known
    damaging = [m for m in known if _mv[m]["power"] > 0 and m not in ROLE_MOVE]
    under = [m for m in damaging if _mv[m]["power"] <= cap]
    if damaging and not under:
        under = [min(damaging, key=lambda m: (_mv[m]["power"], m))]
    keep = set(under)
    return [m for m in known
            if _mv[m]["power"] == 0 or m in ROLE_MOVE or m in keep]


# Which role a support slot should go to first, if the species has one available.
SUPPORT_ORDER = ["setup", "recovery", "hazards", "pivot", "speed", "removal"]


def best_moves(species, level, k=4, support=True, cap=None):
    """Fallback moveset when no published set survives the level filter.

    Damaging moves are ranked by the mon's own attacking bias, then STAB, then
    power x accuracy -- without that an alphabetical scan hands everything Aerial
    Ace / Attract / Blizzard / Bubble. One slot is then reserved for the best
    support move the species actually has, because ranking purely on power gives a
    30-Attack Pyukumuku a Dig/Brick Break/Facade/Fling set instead of the Recover it
    exists to use, and hands Cloyster Giga Impact over Shell Smash."""
    s = _sp[species]
    physical = s["base_stats"][1] >= s["base_stats"][4]
    known = legal_moves(species, level, cap)
    def score(m):
        d = _mv[m]
        # The level-up list is the game's own statement about what this mon should
        # know here, so it breaks ties -- but only ties. Ranked ABOVE power it hands
        # Azumarill a Tackle and leaves Wigglytuff on Sing/Disable/Defense Curl,
        # because every junk move a species learns naturally then outranks the real
        # attack it needs a machine for.
        return ((d["category"] == "Physical") == physical,
                d["type"] in s["types"],
                d["power"] * (d["accuracy"] or 100) / 100,
                D.learnable(species, m, level, 0) == "levelup")
    damaging = sorted((m for m in known if _mv[m]["power"] > 0),
                      key=score, reverse=True)
    picked = damaging[:k - 1] if support else damaging[:k]
    if support:
        for role in SUPPORT_ORDER:
            # ROLE_MOVES holds sets, whose iteration order shifts with Python's
            # per-process string hash seed -- iterating one directly would make the
            # generated teams differ between runs. Sort, preferring a move the
            # species learns natively over the same effect off a TM.
            hit = sorted((m for m in ROLE_MOVES[role]
                          if m in known and m not in picked),
                         key=lambda m: (D.learnable(species, m, level, 0) != "levelup", m))
            if hit:
                picked.append(hit[0])
                break
    # top up from whatever is left (a status-only mon has no damaging moves at all)
    picked += [m for m in sorted(known, key=score, reverse=True) if m not in picked]
    return picked[:k]


def family(name):
    """The species plus its evolutions and pre-evolutions.

    NFE mids have almost no published sets of their own, so a Dewpider inherits
    Araquanid's, a Paras inherits Parasect's -- filtered afterwards by what the
    younger form can actually learn."""
    out = [name] + [c[0] for c in _sp[name]["evolutions"]]
    out += [p for p, s in _sp.items() if any(c[0] == name for c in s["evolutions"])]
    return [x for x in out if x in _sp]


_EV_ORDER = {"hp": 0, "atk": 1, "def": 2, "spe": 3, "spa": 4, "spd": 5}


def substitute_item(species, moves, pool):
    """An in-pool stand-in for a held item the early game cannot supply.

    Prefers the type-boost item matching the mon's strongest STAB, so a Life Orb
    attacker keeps being an attacker; falls back to a Sitrus Berry."""
    types = _sp[species]["types"]
    stab = [m for m in moves
            if _mv.get(m, {}).get("power", 0) > 0 and _mv[m]["type"] in types]
    if stab:
        best = max(stab, key=lambda m: _mv[m]["power"])
        for item in TYPE_BOOST & pool:
            if _mv[best]["type"] == _TYPE_OF_BOOST.get(item):
                return item
    return "SITRUSBERRY" if "SITRUSBERRY" in pool else None


# How far a set's offence split may miss the archetype's before it counts as a worse
# fit. Wide, because offence_pct over a published set is a coarse read (it ignores the
# item and the nature) and a 10-point difference between two Azumarill sets is noise.
OFFENCE_BAND = 20


@functools.lru_cache(maxsize=4096)
def _knows(species, move, level, early):
    """Can this species bring this move? `early` forgives the level, never the species.

    learnable() already distinguishes the two: it returns "levelup+N" for a move the
    species does learn but N levels from now, which is exactly "cannot YET". Truthy
    covers levelup / tm / levelup+N; the strict reading keeps only the first two."""
    kind = D.learnable(species, move, level, 0)
    return bool(kind) if early else kind in ("levelup", "tm")


def usable_sets(species, level, banned=frozenset(), cap=None, mode=None,
                formats=None, early=False):
    """Every published set `species` could actually bring at `level`, as dicts.

    `early` drops the LEVEL half of the learnset gate: a move the species will learn
    later still counts, so a published set keeps its own moves instead of losing them
    to filler. The SPECIES half always holds -- a mon that can never learn a move does
    not get it -- so this makes a boss precocious, not illegal in kind. The engine
    does not check a trainer's learnset, but validate_team.py does, so builds made
    this way are expected to raise "cannot learn" there.

    `formats` is the set of FORMAT tiers a set may come from ("ou", "uu", "ubers" --
    SC.set_tier of its provenance), None meaning all of them. It is a parameter and
    not a module global read in here on purpose: this function is lru_cached, and a
    global would be invisible to the cache key, so a studio request that changed it
    would be served the previous request's answer.

    Pulled out of build() when a third caller appeared: build() RANKS these, the
    studio LISTS them so a set can be picked by name, and the role-supply reading
    counts them. All three were answering "which sets survive this level" and only
    one of them owned the answer.

    The fidelity floor lives here, not in the ranking. A set that cannot survive the
    level is not a weak candidate, it is not a candidate -- and checking it after the
    sort, on the winner alone, is how a two-move Spikes set could beat Ferrothorn's
    four-move Bulky Pivot and take the whole species down with it, returning None
    while perfectly good sets sat unexamined.
    """
    sp = _sp[species]
    out = []
    for src in family(species):
        for (fmt, source, setname), st in SC.sets().get(SC.norm(src), {}).items():
            if formats and SC.set_tier(fmt) not in formats:
                continue
            # `m in _mv` is not redundant with learnable(): learnable() answers from
            # pokemon.txt learnsets and tm.txt, so it can report a move legal that
            # moves.txt does not define. Emitting one would fail validation
            # downstream. Two different questions, so two lists. `legal` is how much
            # of this published set the species could know at all -- that is what
            # decides whether the set still counts as itself. `ok` is what it may
            # actually bring: the level says a mon CANNOT know a move, the ceiling
            # only says it should not know it YET, and a set that loses one move to
            # the ceiling is still that set and gets topped up from filler.
            legal = [m for m in (SC.norm(x) for x in st["moves"])
                     if m in _mv and _knows(species, m, level, early)]
            if len(legal) < (3 if src == species else 2):
                continue
            ok = [m for m in legal
                  if cap is None or _mv[m]["power"] <= cap or m in ROLE_MOVE]
            item = SC.norm(st.get("item"))
            if item and (item not in _items or item.endswith("IUMZ")):
                continue                      # Realidea has no Z-move engine
            if item in banned:
                continue                      # one mega per team
            if item in MEGASTONE and MEGASTONE[item] != species:
                continue                      # can't hold another mon's stone
            ability = SC.norm(st.get("ability"))
            out.append({
                "fmt": fmt, "source": source, "setname": setname,
                "label": f"{fmt}/{source}/{setname}",
                "st": st, "ok": ok, "legal": len(legal), "item": item,
                "ability": ability, "src": src,
                "roles": roles_of(ok, item if item in _items else None,
                                  ability, mode, sp),
            })
    return out


def build(species, level, banned_items=(), want=None, avoid=(), allow_items=None,
          cap=None, mode=None, offence=None, seed=None, only=None,
          formats=None, early=False):
    """Best level-legal published set for `species`, or None if none survives.

    want:        prefer a set that provides this role.
    avoid:       prefer a set that does NOT provide these roles (already at cap).
    mode:        the team's mode, if it has one. Sets that set it or exploit it win
                 ties. Ranked BELOW `want` and ABOVE move fidelity: choosing the
                 Chlorophyll set over the Overgrow one costs nothing at all, while
                 letting it outrank `want` would quietly disable role chasing again.
    only:    restrict the choice to these "fmt/source/setname" labels, or None for
                 every usable set. Lets a caller say "build this mon from THESE
                 published sets" without reimplementing the legality rules.
    seed:    vary the CHOICE among near-equal sets, reproducibly, or None for the
                 single best. A species usually has several sets that answer the same
                 question equally well -- Azumarill has eight usable ones -- and
                 without this a caller sees exactly one of them forever. Seeded off
                 the species and the set label, never hash(), which is salted per
                 process.

                 Like the pool ranking, the noise goes INSIDE the offence band and
                 not after every other term: appended last it fires only on exact
                 ties, and the top tie group is one to three sets, so stall would get
                 no variation at all.
    offence: the archetype's EV offence share, 0-100, or None. Ranked BELOW `want`
                 and above move fidelity, so it chooses between sets that are
                 otherwise equal and never costs a role. Without it an archetype
                 reaches a set ONLY through a role floor, which means it does not
                 reach it at all for a species whose sets fill no floor: Azumarill
                 came back on the same Choice Band set for balance and for hyper
                 offense, because it provides neither `recovery` nor `setup` and
                 every want failed. Banded, because offence_pct is a coarse read.
    allow_items: if given, the only held items this stage may carry. A set whose item
                 is outside it is still usable -- the moveset is the valuable part --
                 but the item is swapped for an in-pool stand-in.
    cap:         power ceiling for this stage. Applied HARD to a published set: a set
                 built around a nuke the curve has not reached yet is not that set
                 without it, so it loses moves, falls under the len(ok) floor, and
                 the caller drops through to best_moves() -- which caps softly.
    """
    is_lc = level <= 25
    sp = _sp[species]
    cands = []
    for c in usable_sets(species, level, frozenset(banned_items), cap, mode,
                         formats, early):
        fmt, source, setname = c["fmt"], c["source"], c["setname"]
        st, ok, src, r = c["st"], c["ok"], c["src"], c["roles"]
        item, ability, legal = c["item"], c["ability"], c["legal"]
        if only is not None and c["label"] not in only:
            continue
        in_pool = allow_items is None or not item or item in allow_items
        # `want` outranks move fidelity deliberately. Ranked below it, a 4-move
        # set with no role always beat a 3-move set with one, so asking for a
        # role returned the same set as not asking -- which silently disabled
        # every role-chasing caller. The len(ok) < 3 floor below still holds, so
        # this trades a filler move for a role, never a whole set.
        rng = (None if seed is None else
               random.Random(f"{seed}:{species}:{fmt}:{source}:{setname}"))
        if offence is None:
            fit = 0
        else:
            miss = abs(TS.offence_pct(st.get("evs") or {}) - offence)
            if rng:
                miss += rng.uniform(0, OFFENCE_BAND)
            fit = -(int(miss) // OFFENCE_BAND)
        jitter = 0 if rng is None else rng.random()
        cands.append(((-len(r & set(avoid)), bool(want and want in r), fit,
                       TS.affinity(mode, sp["types"], [ability],
                                   sp["base_stats"][3], ok, r),
                       legal,
                       in_pool, src == species, fmt.endswith("lc") == is_lc,
                       source == "dex", jitter),
                      ok, item, st, src, r, c["label"], legal))
    if not cands:
        return None
    cands.sort(key=lambda x: x[0], reverse=True)
    _, ok, item, st, src, _r, label, n_legal = cands[0]

    s = _sp[species]
    physical = s["base_stats"][1] >= s["base_stats"][4]
    # A setup move that survived into the set says which attacking stat this build is
    # FOR, and outranks the base-stat comparison -- which can be a flat tie. Manaphy is
    # 100 in every stat, so `>=` chose physical, and a Tail Glow (+3 SPECIAL Attack)
    # sweeper whose own attacks had all been cut by the power ceiling was topped up
    # with Aqua Jet / U-turn / Facade: three physical moves and not one special, with
    # Bubble Beam sitting unused. Only moves that raise exactly one of the two vote.
    boosts = {SC.norm(m) for m in ok}
    if boosts & TS.SETUP_BOOSTS["special"]:
        physical = False
    elif boosts & TS.SETUP_BOOSTS["physical"]:
        physical = True
    def score(m):
        d = _mv[m]
        return ((d["category"] == "Physical") == physical,
                d["type"] in s["types"],
                d["power"] * (d["accuracy"] or 100) / 100,
                D.learnable(species, m, level, 0) == "levelup")
    # top a short set up to four. Prefer a type the set does not already hit: ranking
    # on raw score alone hands a Steelix that already has Earthquake a second Ground
    # move (Dig) for its free slot.
    # Top a short set up to four, one slot at a time.
    #
    # Damaging first: a set that lost its nuke to the ceiling needs a weaker ATTACK
    # in that slot, and ranking on uncovered-type alone gives it Tail Whip instead --
    # a status move has a type too, and an unused one always wins that key.
    #
    # A ROLE move does not claim its type. Volt Switch is taken for the switch, not
    # as Jolteon's answer in Electric, and counting it as coverage left Jolteon with
    # no Electric attack at all.
    #
    # And `covered` grows as we pick, rather than being fixed up front: static, it
    # gave Wigglytuff Round + Echoed Voice + Snore, three Normal sound moves, because
    # nothing the first pick did was visible to the second.
    covered = {_mv[m]["type"] for m in ok
               if _mv[m]["power"] > 0 and m not in ROLE_MOVE}
    spare = [m for m in legal_moves(species, level, cap) if m not in ok]
    moves = list(ok)
    while len(moves) < 4 and spare:
        pick = max(spare, key=lambda m: (_mv[m]["power"] > 0,
                                         _mv[m]["type"] not in covered, score(m)))
        spare.remove(pick)
        moves.append(pick)
        if _mv[pick]["power"] > 0:
            covered.add(_mv[pick]["type"])

    if item not in _items:
        item = None
    if item == "EVIOLITE" and not s["evolutions"]:
        item = None                            # nothing left to evolve into
    if allow_items is not None and item not in allow_items:
        item = substitute_item(species, moves, allow_items)

    ev = [0] * 6
    for k, v in (st.get("evs") or {}).items():
        if k in _EV_ORDER:
            ev[_EV_ORDER[k]] = min(252, v)
    while sum(ev) > 510:                       # never cheat the budget
        ev[ev.index(max(ev))] -= 4

    ability = SC.norm(st.get("ability"))
    listed = [SC.norm(a) for a in s["abilities"]]
    if ability and ability == SC.norm(s["hidden_ability"]):
        slot = 2
    elif ability in listed:
        slot = listed.index(ability)
    else:
        slot = 0

    # A published set's ABILITY is not what makes it that set -- the moves are, and
    # the moves are the half this generator is careful with. So when the team has a
    # mode and this species could hold an ability that CASHES it, take that one.
    # Every player building sand gives Probopass Sand Force over Magnet Pull.
    #
    # Without this the abuser floor is unreachable wherever the ability is a HIDDEN
    # one, because published sets almost never use those: gym 6 is Dhara's Ground gym,
    # fields a Sand Stream Hippowdon, and could not build sand. The only two species
    # in its band that can abuse sand at all -- Hippowdon and Probopass -- carry Sand
    # Force hidden, so the floor failed on the one fight the whole mechanism is for.
    #
    # Never overrides an ability that already SETS the mode (Hippowdon keeps Sand
    # Stream; it is the setter) or one that already cashes it.
    if mode and TS.WEATHER_ROLE_OF_ABILITY.get(ability) != mode \
            and ability not in TS.MODE_ABUSER_ABILITY.get(mode, ()):
        want_ab = TS.MODE_ABUSER_ABILITY.get(mode, ())
        swap = next((i for i, a in enumerate(listed) if a in want_ab), None)
        if swap is None and SC.norm(s["hidden_ability"] or "") in want_ab:
            swap, ability = 2, SC.norm(s["hidden_ability"])
        elif swap is not None:
            ability = listed[swap]
        if swap is not None:
            slot = swap

    nature = SC.norm(st.get("nature")) or "HARDY"
    return {"species": species, "level": level, "moves": moves[:4],
            "item": item or None, "ability": slot,
            "nature": nature if nature in D.NATURES else "HARDY",
            "iv": 31, "ev": ev,
            "roles": roles_of(moves, item, ability, mode, s), "src": label,
            "fidelity": len(ok), "inherited": None if src == species else src}


def fallback(species, level, cap=None):
    """Last resort for a species with no usable published set anywhere in its family.

    Still gets a real spread: 252/252/4 into the two stats its own moveset actually
    uses, within the legal 510 budget. A boss mon left on HARDY and zero EVs is
    strictly below the curve the rest of the team is built to -- the eBST policy is
    "don't exceed 510", not "don't spend any"."""
    moves = best_moves(species, level, cap=cap)
    stats = _sp[species]["base_stats"]
    power = collections.Counter()
    for m in moves:
        power[_mv[m]["category"]] += _mv[m]["power"]
    physical = (power["Physical"] >= power["Special"]
                if power["Physical"] or power["Special"] else stats[1] >= stats[4])
    ev = [0] * 6
    ev[1 if physical else 4] = 252     # PBS stat order: HP ATK DEF SPD SPA SPDEF
    ev[3] = 252                        # speed
    ev[0] = 4
    return {"species": species, "level": level, "moves": moves,
            "item": None, "ability": 0,
            "nature": "ADAMANT" if physical else "MODEST", "iv": 31, "ev": ev,
            "roles": roles_of(moves, None, None),
            "src": "generated (no published set fits)",
            "fidelity": 0, "inherited": None}


# ---------------------------------------------------------------- team assembly
def dedupe_roles(team, caps, cap=None, mode=None):
    """Strip moves that duplicate an already-covered capped role.

    Set preference cannot always avoid this: kept originals never get a second
    candidate species, and some mons carry Stealth Rock on every published set they
    have (Steelix and Aggron both do, which is how the Steel champion ended up
    setting the same hazard twice). The move is redundant after turn one either way,
    so the later holder trades it for the best legal move it does not already know.
    Ability- and item-driven roles are left alone -- there is nothing to edit.

    The team's own MODE move is exempt, because the mode roles are not disjoint from
    the chased ones: Trick Room is a `speed` move, so a Trick Room team met its speed
    cap on the first Thunder Wave and then deleted the Trick Room off the set it had
    just chosen for it -- the mode arrived and was cut in the same build."""
    exempt = TS.ROLE_MOVES.get(mode, frozenset())
    for role, limit in caps.items():
        movepool = ROLE_MOVES.get(role, frozenset()) - exempt
        if not movepool:
            continue
        holders = [m for m in team if set(m["moves"]) & movepool]
        for m in holders[limit:]:
            known = m["moves"]
            capped_moves = set().union(*(ROLE_MOVES[r] for r in caps
                                         if r in ROLE_MOVES))
            covered = {_mv[x]["type"] for x in known if _mv[x]["power"] > 0}
            spare = [x for x in best_moves(m["species"], m["level"], k=12, cap=cap,
                                           support=False)
                     if x not in known and x not in capped_moves]
            # prefer a type the set does not already hit -- swapping Stealth Rock for
            # a second Ground move next to Earthquake is not an upgrade
            spare.sort(key=lambda x: _mv[x]["type"] in covered)
            m["moves"] = [spare.pop(0) if x in movepool and spare else x
                          for x in known]
            m["moves"] = [x for x in m["moves"] if x not in movepool] or m["moves"]
            # roles_of is re-run with no ability, so an ability-derived role would
            # vanish here -- but only the weather ones can BE ability-derived, and
            # only on a set that already reads as "weather". A stripped Sandstorm
            # must still lose its `sand`, so the carry-over is gated on that.
            # The ability IS threaded through now, so weather and mode-abuse roles
            # re-derive on their own; `keep` stays as the belt for the braces.
            keep = {"weather", "mega"}
            if "weather" in m["roles"]:
                keep |= set(TS.WEATHER_ROLE_OF_ABILITY.values())
            m["roles"] = roles_of(m["moves"], m["item"], ability_name(m), mode,
                                  _sp.get(m["species"])) | (m["roles"] & keep)
            m["src"] += f" (-{role})"
    return team


def descendants(name):
    """Every form `name` can eventually evolve into, at any depth."""
    out, stack = [], [c[0] for c in _sp[name]["evolutions"] if c[0] in _sp]
    while stack:
        c = stack.pop()
        if c in out:
            continue
        out.append(c)
        stack += [x[0] for x in _sp[c]["evolutions"] if x[0] in _sp]
    return out


def excluded(name, stage):
    """Species the generator may never CHOOSE at `stage`, whatever else fits.

    The one predicate behind both gates, so that eligible() (what we shop from) and
    evolve_into_band() (where we push a dev's mon) cannot disagree -- Cosmog's line
    ends in Solgaleo and Lunala, and evolving into one is still picking one."""
    return (name in DEAD_PRIMARY
            or (_sp[name]["bst"] >= LEGEND_BST and stage < LEGEND_FROM))


def evolve_into_band(name, level, stage, lo, hi, mega_ok):
    """The cheapest evolution of `name` that is legal at `level` and clears the band.

    A dev-chosen mon whose own evolution fits should be evolved, not discarded --
    Aimi's Marill is 250 BST against a 392 floor, but Azumarill is 410, (OU), and
    evolves at 18. Cheapest rather than strongest: the point is to rescue the line
    with the least deviation from what the dev picked, not to upgrade it."""
    fits = [c for c in descendants(name)
            if _floor[c] <= level and not excluded(c, stage)
            and potential_bst(c, mega_ok) >= lo and bst(c) <= hi]
    return min(fits, key=bst) if fits else None


# Species whose FIRST ability is one the engine never reads. Measured, not assumed:
# every internal name in abilities.txt was searched across all 336 decompiled scripts
# (excluding our own injected Portable_AI.rb), and 16 abilities have no handler at
# all. These ten are the species that LEAD with one.
#
# The user's rule, and the reason it is the primary slot and not "every slot": "tapu
# koko the terrain surge doesnt work but the poke is there so i dun think i wanna put
# them in the generator. xurkitrees beast boost work and they should be in the
# generator." The Tapus each have a working hidden ability (Telepathy), so an
# any-slot test would keep them -- but a Tapu Koko that sets no Electric Terrain is
# not the Pokemon the player is being shown, and handing one to a boss is a promise
# the engine does not keep. Xurkitree and the other Ultra Beasts stay: Beast Boost
# has a real handler.
#
# Permanent, like the Sticky Web and Aurora Veil exclusions -- a fact about this
# build's engine, not a difficulty setting, so it is not badge-gated and has no knob.
# (The four terrain MOVES do work; it is only the surge abilities that are unwired.)
DEAD_PRIMARY = frozenset({
    "SOLGALEO",   # FULLMETALBODY
    "LUNALA",     # SHADOWSHIELD
    "MEGUMIN",    # ACAPARAEXP (fakemon)
    "NECROZMA",   # PRISMARMOR
    "TAPUKOKO", "TAPULELE", "TAPUBULU", "TAPUFINI",   # the four terrain surges
    "ARAICHU",    # SURGESURFER -- doubles speed in Electric Terrain, which no
                  # ability can set here anyway
    "TARTAGLIA",  # NOTENGOATARGALIA (fakemon)
})


def eligible(level, stage, theme=None, exclude_theme=None):
    """Species this leader could legally and sensibly field at `level`."""
    out = []
    for name, s in _sp.items():
        if not s["types"] or _floor[name] > level:
            continue
        if excluded(name, stage):
            continue
        if theme and theme not in s["types"]:
            continue
        if exclude_theme and exclude_theme in s["types"]:
            continue
        # a mon that should have evolved several levels ago reads as a mistake
        evo = [int(e[2]) for e in s["evolutions"]
               if e[1] == "Level" and str(e[2]).isdigit()]
        if evo and level > min(evo) + 6:
            continue
        if SC.band(name) == "Uber" and stage < UBER_FROM:
            continue
        out.append(name)
    return out


@functools.lru_cache(maxsize=None)
def role_supply(level, stage, roles, mode=None, theme=None):
    """{role: (species with a published set for it, species that merely learn it)}.

    Which roles this level's pool can actually be ASKED for. Nothing calls this from
    the boss path: it exists because asking is not free and failure is silent.
    Instrumented across the nine gyms, `take()` made 1,434 build probes of which
    1,156 were Trick Room requests that came back without Trick Room and 11
    succeeded -- the floor was unmeetable at that level and every slot paid for the
    search anyway before falling through to an unroled pick.

    `theme` matters as much as the level: at L24 the OPEN pool has 27 species with a
    published Trick Room set, and Aimi's Fairy core has none. A supply reading taken
    without the theme says a floor is meetable that the fight cannot meet.

    The two counts are the two build paths, and they differ by exactly the escape
    hatch: build() chooses among PUBLISHED sets, so with `fallback_picks` off only
    the first number is the honest one; fallback() writes a set from the learnset,
    so with it on the second is. A caller that trims floors on the wrong column
    either drops a floor it could have met or keeps one it cannot."""
    published, learns = collections.Counter(), collections.Counter()
    move_roles = {r: TS.ROLE_MOVES[r] for r in roles if r in TS.ROLE_MOVES}
    abuse = TS.abuse_role(mode) if mode else None

    # The move pool of the roles ASKED ABOUT, not this module's ROLE_MOVE -- that is
    # only the six roles the boss generator chases, so asking about `protect` against
    # it reported 0 species able to learn Protect.
    asked = set().union(*move_roles.values()) if move_roles else set()

    for name in eligible(level, stage, theme=theme):
        sp = _sp[name]
        legal = {m for m in asked
                 if m in _mv and D.learnable(name, m, level, 0) in ("levelup", "tm")}
        for role, pool in move_roles.items():
            if legal & pool:
                learns[role] += 1

        # A published set only counts if the moves it brings SURVIVE this level --
        # the same test build() applies, so a role counted here is one that can
        # actually be asked for and not merely one the species owns on paper.
        got = set()
        for src in family(name):
            for st in SC.sets().get(SC.norm(src), {}).values():
                ok = [m for m in (SC.norm(x) for x in st["moves"])
                      if m in _mv
                      and D.learnable(name, m, level, 0) in ("levelup", "tm")]
                got |= roles_of(ok, SC.norm(st.get("item")),
                                SC.norm(st.get("ability")), mode, sp)
        for role in roles:
            if role in got:
                published[role] += 1
        if abuse and abuse in roles and abuse in got:
            learns[abuse] += 1

    return {r: (published[r], learns[r]) for r in roles}


# How far apart two candidates' distance-from-target may be before mode affinity is
# allowed to choose between them. The eBST curve is the contract and affinity is a
# preference, so affinity is a TIEBREAK inside a band and never a term that can
# outweigh the target: ranked ahead of the deficit, a 2-point mode preference buys
# 100 BST off curve, which is the same failure that put a 600 Jirachi and a mega
# Lucario on the level-20 first gym when correlation outranked it.
AFFINITY_BAND = 30


def is_dynamic(species):
    """An engine-resolved slot, e.g. `owenpoke2`: a method in the Pokes Rivales script
    that resolves at battle time to the starter matching the player's. Real internal
    names are uppercase, so the case test is unambiguous."""
    return species[:1].islower()


def keep_filter(keep):
    """A fight's keep_test: the card's own drops first, then the competence knobs.

    Drops are checked against the name the card SHOWED, which is the evolved one --
    gym 2's roster holds Marill and the card says Azumarill, so a test against the
    raw original would never match what anyone unticked. That is why this is a
    keep_test and not a filter on spec["kept"]: by the time assemble() calls it,
    evolve_into_band() has already resolved the species.

    An explicit untick also outranks `protected`. Protection exists to stop the
    generator deleting the reason a fight is what it is; it is not there to overrule
    a person who has looked at the card and said no."""
    def test(name, mon, protect=()):
        if keep.get(name) is False:
            return "unticked on the card"
        return keep_competent(name, mon, protect)
    return test


def keep_competent(name, mon, protect=()):
    """Why this dev-chosen Pokemon should not be kept, or None to keep it.

    Both tests are off by default, so this returns None and assemble() behaves exactly
    as it always has. `protect` is honoured for the same reason keep_drop honours it:
    a rival's core family is the character, and no competence score outranks that.

    `fidelity` is the count of moves a published set actually supplied. 0 means no
    published set survived the level filter and fallback() wrote the moves from the
    learnset -- which is the difference between "this Pokemon is weak" and "nobody has
    ever published a way to play it here", and only the second is a build problem.
    """
    if SC.norm(name) in {SC.norm(n) for n in protect}:
        return None
    if KEEP_NEED_SET and not (mon or {}).get("fidelity"):
        return "no published set survives its level"
    if KEEP_MIN_BAND:
        allowed = SC.BANDS[:KEEP_MIN_BAND]
        if SC.band(name) not in allowed:
            return f"{SC.tier(name)} is below {allowed[-1]}"
    return None


def _why(pair, role):
    """The `why` annotation for a pick: `pair` is (with-a-role, without-one)."""
    fmt, plain = pair
    if role is None:
        return plain
    return fmt % role if "%s" in fmt else fmt


def assemble(spec):
    """Build one fight's team. THE assembly loop -- gyms and named trainers share it.

    The two used to be near-duplicate copies, and the difference between them was
    never written down anywhere: it was whatever the two bodies happened to do. Every
    fix to one (the strict/loose take, the spent-mega projection, the power ceiling,
    the ability-derived roles) then had to be re-applied to the other by hand, or
    silently was not. Here the differences ARE the spec, and there is exactly one
    list of them:

      level, stage      what generated picks are built at, and where in the story
      target, lo, hi    the eBST the running mean is steered onto, and the band
      theme             the type at least `on_theme_min` of six must carry, or None.
                        A theme also switches on the off-theme gate, because "earns
                        an off-theme slot" is not a question a themeless fight has.
      kept              the dev's own roster, in build order: [{species, level,
                        moves?, dynamic?}]. `keep_band` drops or evolves the ones
                        outside the band; without it every one is kept as it is.
      note_unknown      say so when a kept species is not in pokemon.txt, or filter
                        it silently
      floors, caps      what this fight must carry and at most, in chase order
      mode              the team-wide plan (sun, sand, trickroom...) or None
      ubers_ok          whether eligible()'s Uber gate is the only one
      project_spent_mega  rank candidates as 100 BST lighter once the mega is spent
      why_theme, why_open  (with-role, without-role) annotations for the two phases
      reequip           re-set a kept mon toward a missing role (the only lever a
                        fight with five dev-chosen mons has)
      keep_drop         how many kept mons this fight may SPEND on a floor nothing
                        else can cover. 0 keeps every one of them, which is what
                        shipped
      protected         species keep_drop will never spend, whatever the budget
      dedupe            strip moves that duplicate an already-capped role
      ace_level         promote the strongest to this level, or None
      mega_ok           past the item/mega unlock. Decides the item pool and the
                        stone ban with it -- they are the same question.
    """
    level, stage, target = spec["level"], spec["stage"], spec["target"]
    lo, hi = spec["lo"], spec["hi"]
    theme, mode = spec["theme"], spec["mode"]
    floors, caps, mega_ok = spec["floors"], spec["caps"], spec["mega_ok"]
    ceiling = bp_cap(stage)
    allow = None if mega_ok else early_items()
    banned = set() if mega_ok else set(MEGASTONE)
    # `mega_ok` answers "is this fight past the item unlock", and decides the item
    # pool and the stone ban together because for a gym they ARE the same question.
    # For a team somebody is designing they are not: "full item pool, no megas" is a
    # perfectly ordinary thing to want and mega_ok=False would also drag the item
    # pool back to Potions. So the stone ban gets its own switch, and the eBST
    # projection has to follow it -- otherwise a mega species is still ranked as
    # though it were 100 BST heavier than it can now become.
    mega_av = mega_ok and not spec.get("no_mega")
    if spec.get("no_mega"):
        banned |= set(MEGASTONE)
    team, have, used, notes = [], collections.Counter(), set(), []
    # Optional, and absent for every fight this repo ships. Each one defaults to the
    # expression it replaced, so a spec without them takes the same path it always
    # did -- which is checked by rebuilding the gyms and the trainers byte-for-byte.
    size = spec.get("size") or TEAM_SIZE
    off = spec.get("offence")
    sset = spec.get("set_seed")
    pseed = spec.get("pick_seed")
    # Which published-set FORMATS this build may draw from. A parameter all the
    # way down rather than a global, because usable_sets() is lru_cached.
    fmts = frozenset(spec.get("set_formats") or ()) or None
    early = bool(spec.get("early_moves"))
    # {SPECIES: {"fmt/source/setname", ...}} -- restrict a KEPT mon to named sets.
    # Only the kept half: a generated pick is chosen by the generator, so naming its
    # sets would be naming a mon you did not choose.
    sfilter = spec.get("set_filter") or {}
    keep = spec.get("pool_filter") or (lambda n: True)

    def capped():
        return {r for r, n in caps.items() if have[r] >= n}

    def add(name, mon, why, kept):
        mon["kept"], mon["why"] = kept, why
        if mon["item"] in MEGASTONE:
            banned.update(MEGASTONE)
        team.append(mon)
        have.update(mon["roles"])
        used.add(name)

    def deficit():
        """The eBST that would put the running mean exactly on target.

        Over the real mons only: an engine-resolved starter slot has no species here
        and so no BST, and counting it as a zero would drag every later pick upward
        to compensate for a mon that is not actually weak."""
        real = [m for m in team if not is_dynamic(m["species"])]
        return target * (len(real) + 1) - sum(ebst(m) for m in real)

    def projected(name):
        spent = mega_av and not have["mega"] if spec["project_spent_mega"] else mega_av
        return potential_bst(name, mega_available=spent)

    def species_affinity(name):
        """What this species could do for the mode, before a set is chosen for it."""
        sp = _sp[name]
        return TS.affinity(mode, sp["types"],
                           list(sp["abilities"]) + [sp["hidden_ability"]],
                           sp["base_stats"][3], ())

    def ranked(tail):
        """Sort key: distance from target first, then `tail`.

        A caller may replace this ordering wholesale with spec["rank"], which is
        handed the live `state` below and the same `tail`. ONE hook rather than a
        knob per term on purpose: every alternative -- jitter, a seed, a coverage
        constraint, spreading the deficit over the remaining slots -- is a term in a
        sort key, and four independently-toggled terms is sixteen orderings, fifteen
        of which nobody measures, inside the file that builds the shipped teams.
        This way the module gains exactly one concept and the policy lives with the
        caller that wants it.

        With a mode set, the distance is bucketed and affinity chooses within the
        bucket. `screens` is the weak case -- its abusers are recognised from a built
        set's roles, not from the species -- so under screens this is today's order
        with a coarser first term, and the setter still arrives through its floor."""
        if spec.get("rank"):
            return spec["rank"](state, tail)

        def key(n):
            gap = abs(projected(n) - deficit())
            if not pseed:
                if mode:
                    return (gap // AFFINITY_BAND, -species_affinity(n)) + tail(n)
                return (gap,) + tail(n)
            # Seeded: the noise goes INSIDE the band and the jitter goes ABOVE the
            # tail, and both of those placements are the whole feature.
            #
            # Inside, because a lexicographic key hands the decision to whichever
            # term is finest-grained: a jitter appended after a continuous `gap`
            # fires only on an exact tie and reranks nothing. Perturbing by one band
            # width instead means candidates within a band of each other genuinely
            # swap between seeds and candidates a band apart never do -- "sample
            # among the ones near enough", not "argmin with extra steps".
            #
            # Above the tail, because the tail is total and deterministic (tier rank,
            # or co-occurrence off-theme), so anything under it never fires. That
            # does cost the tail its vote while a seed is set, which is the trade:
            # a reroll that always returns the best-ranked body in the band is not
            # a reroll. The band, the theme and the mode all still hold.
            rng = random.Random(f"{pseed}:{n}")
            band = int(gap + rng.uniform(0, AFFINITY_BAND)) // AFFINITY_BAND
            if mode:
                return (band, -species_affinity(n), rng.random()) + tail(n)
            return (band, rng.random()) + tail(n)
        return key

    def take(pool, role, why):
        """Pick the best candidate from `pool` for `role` (None = any).

        Two passes. The first refuses any set that would push a capped role past its
        limit; only if the whole pool fails does the second accept one. Asking
        build() to merely *prefer* avoiding a capped role is not enough when every
        published set for a species carries it -- that is how a second Stealth Rock
        reached the champion team even after the preference was added.

        The second pass drops `avoid` as well as the rejection, and has to: inside
        build() the avoid-capped term outranks `want`, so while a role is capped every
        set it asks for comes back WITHOUT the role it asked for and the loose pass
        rejects it too, exactly like the strict one. The live case is Trick Room,
        which is also a `speed` move -- one Thunder Wave caps speed and the mode then
        cannot be filled by anyone, which is 49 of the candidate plans missing
        `trickroom`. Same failure the `want`-above-fidelity comment in build()
        describes, one key higher up."""
        for strict in (True, False):
            full = capped()
            for name in pool:
                if name in used:
                    continue
                mon = build(name, level, banned, want=role,
                            avoid=full if strict else (),
                            allow_items=allow, cap=ceiling, mode=mode, offence=off,
                            seed=sset, formats=fmts, early=early,
                            only=sfilter.get(name))
                # A published set is always preferred; this only catches the species
                # build() dropped entirely for want of one that survives the level.
                # It widens the pool and it also REMOVES A FLOOR -- with it on, no
                # eligible species can fail to produce a set, so the ranking is the
                # only thing left deciding. fallback() takes no mode and no item
                # pool and returns item None, so such a pick can never break the item
                # rules or claim a mode role, and both rejections below still run.
                if not mon and spec.get("fallback_picks"):
                    mon = fallback(name, level, ceiling)
                if not mon or (role is not None and role not in mon["roles"]):
                    continue
                if strict and mon["roles"] & full:
                    continue
                pool.remove(name)
                add(name, mon, why, False)
                return True
        return False

    def unmet():
        return [r for r in floors if have[r] < floors[r]]

    # Handed to spec["rank"]. Deliberately the LIVE objects: `team` and `have` are
    # mutated as the team grows, and a rank hook that cannot see what has already
    # been picked cannot express "no second Water/Fairy" or "cover what nothing here
    # resists" -- which is the whole reason the hook exists.
    state = {"team": team, "have": have, "used": used, "notes": notes,
             "deficit": deficit, "projected": projected, "unmet": unmet,
             "capped": capped, "species_affinity": species_affinity,
             "level": level, "stage": stage, "target": target, "lo": lo, "hi": hi,
             "size": size, "theme": theme, "mode": mode, "floors": floors}

    # 1) the dev's own roster, in the order the caller gave it.
    #
    #    Kept originals get BOTH bounds where `keep_band` is on; generated picks get
    #    only the floor. That asymmetry is deliberate: a generated pick is chosen
    #    against deficit(), which already steers the running mean onto target, so a
    #    ceiling on top of it just starves the late game (it locks every Uber out of
    #    the Champion). A kept original has no such correction -- Bay's Slaking (670)
    #    on its own pushes gym 8 forty BST over target -- so it is the one place the
    #    ceiling earns its keep. A rival is the other way round: their roster IS the
    #    character, so nothing is dropped for sitting under the curve and the padding
    #    slots carry the power instead.
    for k in spec["kept"]:
        name, at = k["species"], k["level"]
        if k.get("dynamic"):
            team.append({"species": name, "level": at, "moves": [], "item": None,
                         "ability": 0, "nature": "HARDY", "iv": 31, "ev": [0] * 6,
                         "roles": set(), "src": "engine (Pokes Rivales starter slot)",
                         "fidelity": 0, "inherited": None,
                         "kept": True, "why": "starter slot"})
            used.add(name)
            notes.append(f"{name} left to the engine — resolves to the starter "
                         f"matching the player's")
            continue
        if name not in _sp:
            if spec["note_unknown"]:
                notes.append(f"skipped {name} — not in pokemon.txt")
            continue
        # A pin is kept, but it is not one of the dev's own: the card has to be
        # able to tell "this is the game's Pokemon" from "this is yours", and
        # `kept` alone cannot, now that both arrive through spec["kept"].
        pick, why = name, "pinned on the card" if k.get("pinned") else "original"
        if spec["keep_band"] and not (lo <= potential_bst(name, mega_ok)
                                      and bst(name) <= hi):
            # a dev-chosen mon whose own evolution fits the band is evolved, not lost
            grown = evolve_into_band(name, at, stage, lo, hi, mega_ok)
            if grown is None:
                notes.append(f"dropped {name} ({bst(name)} BST, "
                             f"band {lo:.0f}-{hi:.0f})")
                continue
            notes.append(f"evolved {name} ({bst(name)}) -> {grown} ({bst(grown)}, "
                         f"{SC.tier(grown)}) to reach the band")
            pick, why = grown, "evolved original"
        # A kept mon keeps its SPECIES, not its set -- so the set is the only lever the
        # plan has on it, and it went unused: build() was called with want=None, which
        # leaves the choice to move fidelity alone and hands Dhara's Hippowdon the same
        # four moves whether the fight is a sand fight or not. The choice was there to
        # spend (23 published sets survive the level filter for that Hippowdon, 36 for
        # Ciara's Bisharp); it was simply never asked for. Mirrors take()'s semantics:
        # try each unmet floor in order, accept the first set that really provides one,
        # otherwise fall back to the best set outright.
        #
        # It also closes a promise the band test was making and the build was not.
        # An original is kept on potential_bst -- counting a mega stone it COULD hold
        # -- and was then built with whatever set had the most surviving moves, stone
        # or no stone. Lawrence's Gallade cleared a 570 floor as a 618 and then walked
        # in as a 518 while a generated Metagross took the stone.
        # Mode FIRST, then the rest. A kept mon is a fixed candidate -- if it does not
        # take the job, this fight cannot go shopping for someone who will -- so the
        # scarce floor gets first refusal. Hazards is cheap: most of the pool carries
        # Stealth Rock. A mode setter is not: 112 species in the whole dex learn Trick
        # Room and five have a weather ability.
        #
        # Two gates decide whether this can do anything for a given mon, and both are
        # facts rather than policy knobs: the species must LEARN the move, and some
        # published set must CARRY it, because build() chooses among published sets and
        # never writes one. Ciara's Bisharp clears both (Stealth Rock by TM, 3 sets
        # carry it) and duly swaps Swords Dance for it. Aimi's Wigglytuff clears
        # neither for Trick Room -- Realidea does not give it the move at all -- so a
        # Trick Room plan can never reach her kept mons, only the slots around them.
        mon = None
        for role in sorted(unmet(), key=lambda r: r != mode):
            mon = build(pick, at, banned, want=role, avoid=capped(),
                        allow_items=allow, cap=ceiling, mode=mode, offence=off,
                        seed=sset, formats=fmts, early=early, only=sfilter.get(pick))
            if mon and role in mon["roles"]:
                break
            mon = None
        mon = mon or build(pick, at, banned, avoid=capped(), allow_items=allow,
                           cap=ceiling, mode=mode, offence=off, seed=sset, formats=fmts, early=early,
                           only=sfilter.get(pick)) \
            or fallback(pick, at, ceiling)
        # A named set that cannot survive this level looks identical to "nothing was
        # published" on the card -- both read fidelity 0 -- so say which happened.
        if sfilter.get(pick) and not mon["fidelity"]:
            notes.append(f"{pick}: no set you named survives level {at}, so its "
                         f"moves were written from the learnset")
        mon["pinned"] = bool(k.get("pinned"))
        if k.get("moves"):
            mon["src"] += f" (dev set was {'/'.join(k['moves'])})"
        # Runs AFTER the build because the published-set test is a fact about the
        # built set, not about the species: Pyukumuku is droppable at level 31 and
        # not at level 100, and only build() knows which.
        gone = (spec.get("keep_test") or (lambda *_: None))(
            pick, mon, spec["protected"] or ())
        if gone:
            notes.append(f"dropped {pick} -- {gone}")
            continue
        add(pick, mon, why, True)

    # 2) top the on-theme core up to its MINIMUM, chasing unmet roles first and
    #    otherwise steering the running mean onto target.
    # pools are built at `level`: that is the level every generated mon is created
    # at, and only the ace is promoted to the cap afterwards. Filtering at the cap
    # instead lets through mons whose evolution floor is exactly the cap, which then
    # get placed one level under it (an illegal lv19 Ninjask, floor 20).
    def on_theme():
        return sum(1 for m in team if not is_dynamic(m["species"])
                   and theme in _sp[m["species"]]["types"])

    core = []
    if theme:
        core = [n for n in eligible(level, stage, theme=theme)
                if n not in used and potential_bst(n, mega_ok) >= lo and keep(n)]
        while on_theme() < spec["on_theme_min"] and len(team) < size and core:
            todo = unmet()
            core.sort(key=ranked(lambda n: (SC.rank(n),)))
            if not any(take(core, r, _why(spec["why_theme"], r)) for r in todo) \
                    and not take(core, None, _why(spec["why_theme"], None)):
                break

    # 3) fill what is left from the open pool. With a theme, a pick there is going
    #    OFF it and has to earn the slot, either by Smogon co-occurrence with the
    #    core or by covering a weakness of the theme; ungated, correlation alone
    #    drags in mons that merely share a metagame (Mandibuzz onto a Steel champion).
    correlation = collections.Counter()
    if theme:
        for m in team:
            for mate, pct in SC.teammates(m["species"]).items():
                correlation[mate] = max(correlation[mate], pct)

    def resisted(name):
        types = _sp[name]["types"]
        return [w for w in WEAK.get(theme, [])
                if any(w in RESIST.get(t, []) + IMMUNE.get(t, []) for t in types)]

    pool = [n for n in eligible(level, stage, exclude_theme=theme)
            if n not in used and potential_bst(n, mega_ok) >= lo
            and (spec["ubers_ok"] or SC.band(n) != "Uber")
            and (not theme or correlation[SC.norm(n)] >= MIN_CORR or resisted(n))
            and keep(n)]
    # Correlation and coverage already decided who is ELIGIBLE for an off-theme slot;
    # among those, the target decides who gets it.
    open_tail = ((lambda n: (-correlation[SC.norm(n)], -len(resisted(n)))) if theme
                 else (lambda n: (SC.rank(n),)))

    while len(team) < size and pool:
        todo = unmet()
        pool.sort(key=ranked(open_tail))
        if not (any(take(pool, r, _why(spec["why_open"], r)) for r in todo)
                or take(pool, None, _why(spec["why_open"], None))):
            break
        if theme:
            m = team[-1]
            corr = correlation[SC.norm(m["species"])]
            if corr >= MIN_CORR:
                notes.append(f"{m['species']} off-theme: {corr:.0f}% Smogon "
                             f"co-occurrence")
            else:
                notes.append(f"{m['species']} off-theme: resists "
                             f"{'/'.join(resisted(m['species']))}")

    # 4) a fight with five dev-chosen mons has only one free slot, so a missing role
    #    cannot be covered by adding a body. The set is the other lever: re-equip a
    #    kept mon toward it. That changes what it does, never which mon it is.
    if spec["reequip"]:
        for role in floors:
            if have[role] >= floors[role]:
                continue
            for i, m in enumerate(team):
                # "does only one job" -- counted against the roles this generator
                # CHASES, not every role team_shape can name. Against the full
                # vocabulary a Mantine that merely knows Substitute and Toxic reads
                # as three-role and is skipped, so widening the table would silently
                # stop re-equipping mons it had always re-equipped.
                if not m["kept"] or is_dynamic(m["species"]) \
                        or len(m["roles"] & CHASED_SET) > 1:
                    continue
                alt = build(m["species"], m["level"], banned, want=role,
                            avoid=capped(), allow_items=allow, cap=ceiling,
                            mode=mode, offence=off, seed=sset, formats=fmts, early=early)
                if alt and role in alt["roles"]:
                    alt["kept"], alt["why"] = True, f"original, re-set for {role}"
                    have.subtract(m["roles"])
                    have.update(alt["roles"])
                    team[i] = alt
                    notes.append(f"{m['species']} re-equipped to cover {role}")
                    break

    # 5) and if re-setting a kept mon cannot cover the floor either, trade one away.
    #    This is the end of the escalation: fill an empty slot (2, 3), re-equip a mon
    #    we already have (4), and only then give one up. `keep_drop` is 0 by default,
    #    so none of this runs unless someone asks for it.
    #
    #    Two things are never traded, and neither is a setting:
    #
    #      a `protected` species -- a rival's core family (Alba without Beldum and
    #      Pumpkaboo is not Alba, she is a generic Grass trainer), and any mon that
    #      supplied the evidence for the mode (see mode_evidence: dropping Dhara's
    #      Hippowdon to make room for her sand plan deletes the reason it is a sand
    #      plan). Make either one a knob and someone eventually turns the bug on.
    #
    #    Among the rest, least useful first: how many floors it is the last holder of,
    #    then eBST. A mon whose jobs are all covered elsewhere goes before one doing
    #    something nobody else does.
    if spec["keep_drop"]:
        budget = spec["keep_drop"]
        protect = {SC.norm(n) for n in (spec["protected"] or ())}

        def spend(role):
            droppable = [m for m in team
                         if m["kept"] and not is_dynamic(m["species"])
                         and SC.norm(m["species"]) not in protect]
            droppable.sort(key=lambda m: (sum(1 for r, k in floors.items()
                                              if r in m["roles"] and have[r] <= k),
                                          ebst(m)))
            for victim in droppable:
                i = team.index(victim)
                team.pop(i)
                have.subtract(victim["roles"])
                used.discard(victim["species"])
                # Spending a kept mon must not quietly break the theme minimum the
                # fight was given. Dropping an on-theme original and refilling from
                # the OFF-theme pool is how Douglas's Ice gym came back with a
                # Venusaur and a Jolteon at ON_THEME_MIN 6 -- the knob was honoured
                # everywhere except here. Below the minimum, only the core may fill.
                short = theme and on_theme() < spec["on_theme_min"]
                if take(core, role, _why(spec["why_theme"], role)) if short else (
                        take(pool, role, _why(spec["why_open"], role))
                        or (theme and take(core, role,
                                           _why(spec["why_theme"], role)))):
                    notes.append(f"spent {victim['species']} — nothing else left "
                                 f"could cover {role}")
                    return True
                team.insert(i, victim)          # nobody could; put it back
                have.update(victim["roles"])
                used.add(victim["species"])
            return False

        # Mode floors first. A mode setter is scarce -- two species in the whole dex
        # have Drizzle -- where hazards is not, so the scarce floor gets the budget.
        mine = {mode, TS.abuse_role(mode)} if mode else set()
        for role in sorted(floors, key=lambda r: r not in mine):
            if budget and have[role] < floors[role] and spend(role):
                budget -= 1

    if spec["dedupe"]:
        dedupe_roles(team, caps, ceiling, mode)
        # A rewrite changes what the team covers, so the running tally is stale the
        # moment it runs. Recount: `have` is what preview(), the studio and
        # fight_context all read "floors met" off, and a floor reported as met by a
        # move that was then stripped is exactly the reading that must not happen.
        have.clear()
        for m in team:
            have.update(m["roles"])
    # weakest first, engine slots last -- they have no BST to sort on. The ace is the
    # strongest real mon and the only one at the cap itself.
    team.sort(key=lambda m: (is_dynamic(m["species"]),
                             0 if is_dynamic(m["species"]) else ebst(m)))
    if spec["ace_level"] is not None and team:
        team[-1]["level"] = spec["ace_level"]
    # The setter leads. In Essentials the party order IS the send-out order, and
    # weakest-first was sending gym 1's Rain Dance user out FIFTH -- the weather
    # realistically never went up. Real teams lead with it: the corpus puts the
    # ability setter in slot 0 on 58% of rain teams and 62% of snow ones against a
    # 17% uniform baseline (validated on Sticky Web 52% and Focus Sash 35%; Stealth
    # Rock reads 16%, i.e. is not a lead marker, which is the control).
    #
    # The ace is left alone: it is the strongest mon and the last thing a player
    # sees, and a setter that IS the ace stays where it is.
    if mode:
        for i, m in enumerate(team[:-1]):
            if mode in m["roles"]:
                team.insert(0, team.pop(i))
                break
    return {"team": team, "roles": have, "notes": notes, "band": (lo, hi)}


def make_gym(idx):
    """Build one gym team. idx is the badge count (0 = gym 1, 8 = Champion).

    ARCHETYPE[idx] and MODE[idx] are read HERE rather than captured at import, so a
    caller that wants to try a different plan -- boss_diagnostic.matrix,
    fight_context.score, boss_studio -- swaps the global and calls this."""
    _keep, _sets = picks_for(gym_id(idx))
    cap = CAPS[idx]
    leader = cap["trainer"]
    theme = THEME[leader]
    level = remap(cap["cap"])
    target = TARGET[idx]
    mode = MODE[idx]
    # Before UNLOCK_STAGE a boss carries only what an early player could hold, and
    # no mega at all: an unusable stone costs its holder a real item AND credits the
    # team 100 eBST it never receives (that alone had gyms 1-5 ~16 BST under target).
    mega_ok = idx >= UNLOCK_STAGE
    floors, caps = plan_for(ARCHETYPE[idx], mega_ok,
                            mode if idx >= MODE_FROM else None)
    originals = [m["species"] for m in cap["team"] if m["species"] in _sp]
    built = assemble({
        "level": level - 1, "ace_level": level, "stage": idx,
        "target": target, "lo": target - SPREAD[idx] / 2,
        "hi": target + SPREAD[idx] / 2,
        "theme": theme, "on_theme_min": ON_THEME_MIN,
        # A Builder card can pin a species onto this fight or drop one of its own,
        # and can name which published sets a species may use. Pins are appended
        # after the originals so the roster order -- heaviest first -- still decides
        # who gets the mega, which is a property of the dev's roster and not of a
        # tick box.
        "kept": [{"species": n, "level": level - 1} for n in
                 sorted(originals, key=lambda n: -potential_bst(n, mega_ok))]
                + [{"species": n, "level": level - 1, "pinned": True}
                   for n, on in _keep.items()
                   if on and n not in originals and n in _sp],
        "set_filter": _sets,
        "keep_band": True, "note_unknown": False,
        "floors": floors, "caps": caps, "mode": mode, "mega_ok": mega_ok,
        "ubers_ok": True, "project_spent_mega": True,
        "why_theme": ("theme:%s", "theme"), "why_open": ("off-theme", "off-theme"),
        # The re-equip pass is a no-op on the nine today (all 19 floors are met by
        # filling), and it rescues 2 of the 352 candidate plans in fight_context --
        # a floor that no remaining body can cover, covered by re-setting a kept mon.
        "reequip": True, "dedupe": True,
        # A gym leader fights once, so no family is "the character" -- THEME is what
        # makes the fight theirs, and it survives losing a Pokemon. Only the mode's
        # own evidence is held back.
        "keep_drop": KEEP_DROP, "keep_test": keep_filter(_keep),
        "set_formats": SET_FORMATS, "early_moves": EARLY_MOVES,
        "set_seed": SET_SEED or None, "pick_seed": PICK_SEED or None,
        "protected": [n for n in originals if mode_evidence(n, mode)],
    })
    return {"idx": idx, "cap": cap, "leader": leader, "theme": theme, "level": level,
            "target": target, "band": built["band"], "team": built["team"],
            "roles": built["roles"], "archetype": ARCHETYPE[idx], "mode": mode,
            "floors": floors, "notes": built["notes"]}


# ---------------------------------------------------------------- output
def _type_ids():
    """{trainer class: type_id} from the extracted battle list -- the same numeric id
    the Ruby registry keys on. realidea_level_caps.json records the class name only,
    which is why emit_registry.py could not key the boss teams before."""
    battles = json.load(open(os.path.join(EXTRACTED, "realidea-battles.json")))
    return {b["type"]: b["type_id"] for b in battles}


def as_team_record(gym, type_ids):
    """One gym result -> the team JSON shape validate_team.py and emit_registry.py
    both consume."""
    cap = gym["cap"]
    mons = []
    for m in gym["team"]:
        mons.append({k: (sorted(v) if isinstance(v, set) else v)
                     for k, v in m.items()})
    return {"id": f"gym{gym['idx'] + 1}_{cap['trainer_type']}_{gym['leader']}",
            "map": cap["map"], "type_id": type_ids.get(cap["trainer_type"]),
            "class": cap["trainer_type"], "name": gym["leader"],
            "orig_ace_level": max(m["level"] for m in cap["team"]),
            "cheat_tier": False, "trainer_items": [], "mons": mons,
            "design": {"target_ebst": gym["target"], "level": gym["level"],
                       "theme": gym["theme"], "notes": gym["notes"]}}


def preview(gyms):
    out = [f'{"fight":10}{"lv":>4}{"mean":>6}{"tgt":>5}{"gap":>6}{"sets":>8}'
           f'  roles  theme  tier mix']
    for g in gyms:
        team = g["team"]
        mean = sum(ebst(m) for m in team) / len(team)
        fid = sum(m["fidelity"] for m in team)
        # against this fight's OWN floors, not a fixed four: a stall gym needing
        # five recovery sets and a hyper-offence gym needing three setup ones are
        # not comparable on a single denominator.
        floors = g["floors"]
        nrole = sum(1 for r, n in floors.items() if r != "mega" and g["roles"][r] >= n)
        need = sum(1 for r in floors if r != "mega")
        on = sum(1 for m in team if g["theme"] in _sp[m["species"]]["types"])
        mix = collections.Counter(SC.band(m["species"]) for m in team)
        out.append(
            f'{g["cap"]["next_battle"]:10}{g["level"]:>4}{mean:>6.0f}{g["target"]:>5}'
            f'{mean - g["target"]:>+6.0f}{f"{fid}/{len(team) * 4}":>8}'
            f'  {nrole}/{need}{"+M" if g["roles"]["mega"] else "  "}'
            f' {on}/{len(team)} {g["theme"][:5]:<6}'
            + " ".join(f"{b}:{mix[b]}" for b in SC.BANDS if mix[b]))
    means = [sum(ebst(m) for m in g["team"]) / len(g["team"]) for g in gyms]
    mad = sum(abs(m - g["target"]) for m, g in zip(means, gyms)) / len(gyms)
    out.append(f"\nmean absolute deviation from target: {mad:.1f} BST")
    return "\n".join(out)


def roster(g):
    out = [f'\n#### {g["cap"]["next_battle"]} — {g["leader"]} ({g["theme"]})'
           f'  lv {g["cap"]["cap"]}→{g["level"]}'
           f'  target eBST {g["target"]}  band {g["band"][0]:.0f}-{g["band"][1]:.0f}']
    for m in g["team"]:
        n = m["species"]
        mark = "●" if g["theme"] in _sp[n]["types"] else "○"
        mega = f' (mega {ebst(m)})' if ebst(m) != bst(n) else ""
        out.append(f'  {mark} {"keep" if m["kept"] else "NEW "} {n:13}{bst(n):>4}'
                   f'{mega:<12} {SC.tier(n):>5}  lv{m["level"]:<3} '
                   f'{"/".join(m["moves"])}')
        out.append(f'{"":26}{m["item"] or "—":<14}{m["nature"]:<9}'
                   f'{",".join(sorted(m["roles"])) or "attacker":<34}'
                   f'[{m["src"]}' + (f' ←{m["inherited"]}' if m["inherited"] else "") + ']')
    for note in g["notes"]:
        out.append(f'     · {note}')
    return "\n".join(out)


def main(argv):
    args = list(argv)
    if "--stats-only" in args:
        args.remove("--stats-only")
        SC.stats_only()
    out_path = None
    if "--json" in args:
        i = args.index("--json")
        out_path = args[i + 1]
        del args[i:i + 2]

    gyms = [make_gym(i) for i in range(len(CAPS))]
    print(preview(gyms))
    for g in gyms:
        if g["leader"] in args or g["cap"]["next_battle"] in args:
            print(roster(g))

    if out_path:
        type_ids = _type_ids()
        records = [as_team_record(g, type_ids) for g in gyms]
        missing = [r["id"] for r in records if r["type_id"] is None]
        json.dump(records, open(out_path, "w"), indent=1)
        print(f"\n{len(records)} boss teams -> {out_path}")
        if missing:
            print(f"WARNING: no type_id for {missing} — "
                  f"emit_registry.py cannot key these")


if __name__ == "__main__":
    main(sys.argv[1:])
