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
import re
import sys

import realidea_data as D
import smogon_corpus as SC

HERE = os.path.dirname(os.path.abspath(__file__))
STUDY = os.path.dirname(HERE)
GEN = os.path.join(STUDY, "generated")
EXTRACTED = os.path.join(STUDY, "extracted")
PBS_TYPES = os.path.join(D.PBS, "types.txt")

# Every Mega Evolution and both Primals are exactly +100 BST over the base form, and
# Realidea keeps mega stats in MultipleForms.rb rather than pokemon.txt -- so the
# base species' PBS BST understates a mega holder by exactly this much.
MEGA_BONUS = 100

# ---------------------------------------------------------------- the ladder
# Target eBST per badge. Reborn Yang Intense's measured curve (BOSS-CURVE.md §2)
# linearly stretched to land the Champion on 600. The dip at badge 5 is Reborn's own
# shape -- its Shelly (487) outweighs its Shade (472) -- and is kept deliberately.
TARGET = [397, 487, 504, 551, 525, 583, 593, 597, 600]
# Measured BST spread within each Reborn fight; the band is target +- spread/2.
SPREAD = [190, 190, 230, 61, 110, 140, 45, 85, 100]
# Type theme per leader, from their existing roster.
THEME = {"Abi": "BUG", "Aimi": "FAIRY", "Kenn": "WATER", "Douglas": "ICE",
         "Ciara": "DARK", "Dhara": "GROUND", "Lawrence": "PSYCHIC",
         "Bay": "NORMAL", "Lilliana": "STEEL"}
# Ubers unlock at gym 7 -- the user wants them to arrive, but as the late escalation.
UBER_FROM = 6
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
ON_THEME_MIN = 4          # of 6; the rest may be off-theme (user: "1,2 can differ")
TEAM_SIZE = 6
# Off-theme picks must earn the slot: this much Smogon co-occurrence with the core,
# or a resistance to what the theme is weak to. Ungated, correlation alone drags in
# mons that merely share a metagame (a Mandibuzz onto a Steel champion).
MIN_CORR = 25.0

# ---------------------------------------------------------------- roles
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
}
WEATHER_ABILITY = {"DRIZZLE", "DROUGHT", "SANDSTREAM", "SNOWWARNING"}
# Roles worth filling, in the order the generator chases them. Mined from 110 Smogon
# sample teams: hazards 110/110, setup 75%, recovery 69%, pivot 66%.
QUOTA = ["hazards", "recovery", "setup", "pivot", "mega"]
# ...and how many of each a team may carry. Uncapped, incidental duplicates pile up:
# three Stealth Rock setters on one champion team, all of them redundant after turn 1.
ROLE_CAP = {"hazards": 1, "removal": 1, "mega": 1, "weather": 1}


def roles_of(moves, item, ability):
    r = {k for k, v in ROLE_MOVES.items() if set(moves) & v}
    if SC.norm(ability) in WEATHER_ABILITY:
        r.add("weather")
    if item and item in MEGASTONE:
        r.add("mega")
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


def _type_chart():
    weak, res, imm, cur = {}, {}, {}, None
    for line in open(PBS_TYPES, encoding="utf-8-sig", errors="replace"):
        line = line.strip()
        if line.startswith("InternalName="):
            cur = line.split("=", 1)[1]
        elif cur and line.startswith("Weaknesses="):
            weak[cur] = line.split("=", 1)[1].split(",")
        elif cur and line.startswith("Resistances="):
            res[cur] = line.split("=", 1)[1].split(",")
        elif cur and line.startswith("Immunities="):
            imm[cur] = line.split("=", 1)[1].split(",")
    return weak, res, imm


WEAK, RESIST, IMMUNE = _type_chart()


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
def _remap_anchors():
    caps = json.load(open(os.path.join(GEN, "realidea_level_caps.json")))
    curve = json.load(open(os.path.join(GEN, "realidea_level_curve.json")))
    prog = {p["stage"]: p for p in curve["progression"]}
    mode = curve["active_mode"]
    xs = [0] + [c["cap"] for c in caps] + [66]
    ys = ([0] + [prog[c["badges"]][mode] for c in caps]
          + [curve["champion"][mode]])
    return caps, xs, ys


CAPS, _AX, _AY = _remap_anchors()


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
def legal_moves(species, level):
    return [m for m in _mv if D.learnable(species, m, level, 0) in ("levelup", "tm")]


# Which role a support slot should go to first, if the species has one available.
SUPPORT_ORDER = ["setup", "recovery", "hazards", "pivot", "speed", "removal"]


def best_moves(species, level, k=4, support=True):
    """Fallback moveset when no published set survives the level filter.

    Damaging moves are ranked by the mon's own attacking bias, then STAB, then
    power x accuracy -- without that an alphabetical scan hands everything Aerial
    Ace / Attract / Blizzard / Bubble. One slot is then reserved for the best
    support move the species actually has, because ranking purely on power gives a
    30-Attack Pyukumuku a Dig/Brick Break/Facade/Fling set instead of the Recover it
    exists to use, and hands Cloyster Giga Impact over Shell Smash."""
    s = _sp[species]
    physical = s["base_stats"][1] >= s["base_stats"][4]
    known = legal_moves(species, level)
    def score(m):
        d = _mv[m]
        return ((d["category"] == "Physical") == physical,
                d["type"] in s["types"],
                d["power"] * (d["accuracy"] or 100) / 100)
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


def build(species, level, banned_items=(), want=None, avoid=(), allow_items=None):
    """Best level-legal published set for `species`, or None if none survives.

    want:        prefer a set that provides this role.
    avoid:       prefer a set that does NOT provide these roles (already at cap).
    allow_items: if given, the only held items this stage may carry. A set whose item
                 is outside it is still usable -- the moveset is the valuable part --
                 but the item is swapped for an in-pool stand-in.
    """
    is_lc = level <= 25
    cands = []
    for src in family(species):
        for (fmt, source, setname), st in SC.sets().get(SC.norm(src), {}).items():
            # `m in _mv` is not redundant with learnable(): learnable() answers from
            # pokemon.txt learnsets and tm.txt, so it can report a move legal that
            # moves.txt does not define. Emitting one would fail validation downstream.
            ok = [m for m in (SC.norm(x) for x in st["moves"])
                  if m in _mv and D.learnable(species, m, level, 0) in ("levelup", "tm")]
            item = SC.norm(st.get("item"))
            if item and (item not in _items or item.endswith("IUMZ")):
                continue                      # Realidea has no Z-move engine
            if item in banned_items:
                continue                      # one mega per team
            if item in MEGASTONE and MEGASTONE[item] != species:
                continue                      # can't hold another mon's stone
            ability = SC.norm(st.get("ability"))
            r = roles_of(ok, item if item in _items else None, ability)
            in_pool = allow_items is None or not item or item in allow_items
            # `want` outranks move fidelity deliberately. Ranked below it, a 4-move
            # set with no role always beat a 3-move set with one, so asking for a
            # role returned the same set as not asking -- which silently disabled
            # every role-chasing caller. The len(ok) < 3 floor below still holds, so
            # this trades a filler move for a role, never a whole set.
            cands.append(((-len(r & set(avoid)), bool(want and want in r), len(ok),
                           in_pool, src == species, fmt.endswith("lc") == is_lc,
                           source == "dex"),
                          ok, item, st, src, r, f"{fmt}/{source}/{setname}"))
    if not cands:
        return None
    cands.sort(key=lambda x: x[0], reverse=True)
    _, ok, item, st, src, _r, label = cands[0]
    # An inherited set that only contributes two moves is not really that set any
    # more; hand back None so the caller falls through to best_moves().
    if len(ok) < (3 if src == species else 2):
        return None

    s = _sp[species]
    physical = s["base_stats"][1] >= s["base_stats"][4]
    def score(m):
        d = _mv[m]
        return ((d["category"] == "Physical") == physical,
                d["type"] in s["types"],
                d["power"] * (d["accuracy"] or 100) / 100)
    # top a short set up to four. Prefer a type the set does not already hit: ranking
    # on raw score alone hands a Steelix that already has Earthquake a second Ground
    # move (Dig) for its free slot.
    covered = {_mv[m]["type"] for m in ok if _mv[m]["power"] > 0}
    filler = sorted((m for m in legal_moves(species, level) if m not in ok),
                    key=lambda m: (_mv[m]["type"] not in covered, score(m)),
                    reverse=True)
    moves = ok + filler[:4 - len(ok)]

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

    nature = SC.norm(st.get("nature")) or "HARDY"
    return {"species": species, "level": level, "moves": moves[:4],
            "item": item or None, "ability": slot,
            "nature": nature if nature in D.NATURES else "HARDY",
            "iv": 31, "ev": ev,
            "roles": roles_of(moves, item, ability), "src": label,
            "fidelity": len(ok), "inherited": None if src == species else src}


def fallback(species, level):
    """Last resort for a species with no usable published set anywhere in its family.

    Still gets a real spread: 252/252/4 into the two stats its own moveset actually
    uses, within the legal 510 budget. A boss mon left on HARDY and zero EVs is
    strictly below the curve the rest of the team is built to -- the eBST policy is
    "don't exceed 510", not "don't spend any"."""
    moves = best_moves(species, level)
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
def dedupe_roles(team, level):
    """Strip moves that duplicate an already-covered capped role.

    Set preference cannot always avoid this: kept originals never get a second
    candidate species, and some mons carry Stealth Rock on every published set they
    have (Steelix and Aggron both do, which is how the Steel champion ended up
    setting the same hazard twice). The move is redundant after turn one either way,
    so the later holder trades it for the best legal move it does not already know.
    Ability- and item-driven roles are left alone -- there is nothing to edit."""
    for role, limit in ROLE_CAP.items():
        movepool = ROLE_MOVES.get(role)
        if not movepool:
            continue
        holders = [m for m in team if set(m["moves"]) & movepool]
        for m in holders[limit:]:
            known = m["moves"]
            capped_moves = set().union(*(ROLE_MOVES[r] for r in ROLE_CAP
                                         if r in ROLE_MOVES))
            covered = {_mv[x]["type"] for x in known if _mv[x]["power"] > 0}
            spare = [x for x in best_moves(m["species"], m["level"], k=12,
                                           support=False)
                     if x not in known and x not in capped_moves]
            # prefer a type the set does not already hit -- swapping Stealth Rock for
            # a second Ground move next to Earthquake is not an upgrade
            spare.sort(key=lambda x: _mv[x]["type"] in covered)
            m["moves"] = [spare.pop(0) if x in movepool and spare else x
                          for x in known]
            m["moves"] = [x for x in m["moves"] if x not in movepool] or m["moves"]
            m["roles"] = roles_of(m["moves"], m["item"], None) | (
                m["roles"] & {"weather", "mega"})
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


def evolve_into_band(name, level, lo, hi, mega_ok):
    """The cheapest evolution of `name` that is legal at `level` and clears the band.

    A dev-chosen mon whose own evolution fits should be evolved, not discarded --
    Aimi's Marill is 250 BST against a 392 floor, but Azumarill is 410, (OU), and
    evolves at 18. Cheapest rather than strongest: the point is to rescue the line
    with the least deviation from what the dev picked, not to upgrade it."""
    fits = [c for c in descendants(name)
            if _floor[c] <= level
            and potential_bst(c, mega_ok) >= lo and bst(c) <= hi]
    return min(fits, key=bst) if fits else None


def eligible(level, stage, theme=None, exclude_theme=None):
    """Species this leader could legally and sensibly field at `level`."""
    out = []
    for name, s in _sp.items():
        if not s["types"] or _floor[name] > level:
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


def make_gym(idx):
    """Build one gym team. idx is the badge count (0 = gym 1, 8 = Champion)."""
    cap = CAPS[idx]
    leader = cap["trainer"]
    theme = THEME[leader]
    level = remap(cap["cap"])
    target = TARGET[idx]
    lo, hi = target - SPREAD[idx] / 2, target + SPREAD[idx] / 2

    # Before UNLOCK_STAGE a boss carries only what an early player could hold, and
    # no mega at all: an unusable stone costs its holder a real item AND credits the
    # team 100 eBST it never receives (that alone had gyms 1-5 ~16 BST under target).
    mega_ok = idx >= UNLOCK_STAGE
    allow = None if mega_ok else early_items()
    quota = QUOTA if mega_ok else [r for r in QUOTA if r != "mega"]
    team, have, used, notes = [], collections.Counter(), set(), []
    banned = set() if mega_ok else set(MEGASTONE)

    def capped():
        return {r for r, n in ROLE_CAP.items() if have[r] >= n}

    def add(name, mon, why, kept):
        mon["kept"], mon["why"] = kept, why
        if mon["item"] in MEGASTONE:
            banned.update(MEGASTONE)
        team.append(mon)
        have.update(mon["roles"])
        used.add(name)

    def deficit():
        """The eBST that would put the running mean exactly on target."""
        return target * (len(team) + 1) - sum(ebst(m) for m in team)

    def projected(name):
        return potential_bst(name, mega_available=mega_ok and not have["mega"])

    # 1) keep every original that fits the band.
    #
    #    Kept originals get BOTH bounds; generated picks get only the floor. That
    #    asymmetry is deliberate: a generated pick is chosen against deficit(), which
    #    already steers the running mean onto target, so a ceiling on top of it just
    #    starves the late game (it locks every Uber out of the Champion). A kept
    #    original has no such correction -- Bay's Slaking (670) on its own pushes gym
    #    8 forty BST over target -- so it is the one place the ceiling earns its keep.
    #    The floor is load-bearing everywhere: without it the champion team fills with
    #    chaff the curve was written to remove.
    originals = [m["species"] for m in cap["team"] if m["species"] in _sp]
    for name in sorted(originals, key=lambda n: -potential_bst(n, mega_ok)):
        pick, why = name, "original"
        if not (lo <= potential_bst(name, mega_ok) and bst(name) <= hi):
            # a dev-chosen mon whose own evolution fits the band is evolved, not lost
            grown = evolve_into_band(name, level - 1, lo, hi, mega_ok)
            if grown is None:
                notes.append(f"dropped {name} ({bst(name)} BST, "
                             f"band {lo:.0f}-{hi:.0f})")
                continue
            notes.append(f"evolved {name} ({bst(name)}) -> {grown} ({bst(grown)}, "
                         f"{SC.tier(grown)}) to reach the band")
            pick, why = grown, "evolved original"
        add(pick, build(pick, level - 1, banned, avoid=capped(), allow_items=allow)
            or fallback(pick, level - 1), why, True)

    def take(pool, role, why, kept=False):
        """Pick the best candidate from `pool` for `role` (None = any).

        Two passes. The first refuses any set that would push a capped role past its
        limit; only if the whole pool fails does the second accept one. Asking
        build() to merely *prefer* avoiding a capped role is not enough when every
        published set for a species carries it -- that is how a second Stealth Rock
        reached the champion team even after the preference was added."""
        for strict in (True, False):
            full = capped()
            for name in pool:
                if name in used:
                    continue
                mon = build(name, level - 1, banned, want=role, avoid=full,
                            allow_items=allow)
                if not mon or (role is not None and role not in mon["roles"]):
                    continue
                if strict and mon["roles"] & full:
                    continue
                pool.remove(name)
                add(name, mon, why, kept)
                return True
        return False

    # 2) top the on-theme core up to its MINIMUM, chasing unmet roles first and
    #    otherwise steering the running mean onto target.
    # pools are built at level - 1: that is the level every generated mon is created
    # at, and only the ace is promoted to the cap afterwards. Filtering at `level`
    # instead lets through mons whose evolution floor is exactly the cap, which then
    # get placed one level under it (an illegal lv19 Ninjask, floor 20).
    core = [n for n in eligible(level - 1, idx, theme=theme)
            if n not in used and potential_bst(n, mega_ok) >= lo]

    def on_theme():
        return sum(1 for m in team if theme in _sp[m["species"]]["types"])

    while on_theme() < ON_THEME_MIN and len(team) < TEAM_SIZE and core:
        unmet = [r for r in quota if not have[r]]
        core.sort(key=lambda n: (abs(projected(n) - deficit()), SC.rank(n)))
        if not any(take(core, r, f"theme:{r}") for r in unmet) \
                and not take(core, None, "theme"):
            break

    # 3) fill what is left off-theme -- but only with mons that earn it, either by
    #    Smogon co-occurrence with the core or by covering the theme's weakness.
    weaknesses = WEAK.get(theme, [])

    def resisted(name):
        types = _sp[name]["types"]
        return [w for w in weaknesses
                if any(w in RESIST.get(t, []) + IMMUNE.get(t, []) for t in types)]

    correlation = collections.Counter()
    for m in team:
        for mate, pct in SC.teammates(m["species"]).items():
            correlation[mate] = max(correlation[mate], pct)

    off = [n for n in eligible(level - 1, idx, exclude_theme=theme)
           if n not in used and potential_bst(n, mega_ok) >= lo
           and (correlation[SC.norm(n)] >= MIN_CORR or resisted(n))]

    while len(team) < TEAM_SIZE and off:
        unmet = [r for r in quota if not have[r]]
        # Correlation and coverage already decided who is ELIGIBLE for an off-theme
        # slot; among those, the target decides who gets it. Ranking by correlation
        # instead put a 600 Jirachi and a mega Lucario on the level-20 first gym.
        off.sort(key=lambda n: (abs(projected(n) - deficit()),
                                -correlation[SC.norm(n)], -len(resisted(n))))
        picked = any(take(off, r, "off-theme") for r in unmet) \
            or take(off, None, "off-theme")
        if not picked:
            break
        m = team[-1]
        corr = correlation[SC.norm(m["species"])]
        if corr >= MIN_CORR:
            notes.append(f"{m['species']} off-theme: {corr:.0f}% Smogon co-occurrence")
        else:
            notes.append(f"{m['species']} off-theme: resists "
                         f"{'/'.join(resisted(m['species']))}")

    dedupe_roles(team, level)
    # the strongest mon is the ace and is the only one at the cap itself
    team.sort(key=ebst)
    if team:
        team[-1]["level"] = level
    return {"idx": idx, "cap": cap, "leader": leader, "theme": theme, "level": level,
            "target": target, "band": (lo, hi), "team": team, "roles": have,
            "notes": notes}


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
        nrole = sum(1 for r in QUOTA[:4] if g["roles"][r])
        on = sum(1 for m in team if g["theme"] in _sp[m["species"]]["types"])
        mix = collections.Counter(SC.band(m["species"]) for m in team)
        out.append(
            f'{g["cap"]["next_battle"]:10}{g["level"]:>4}{mean:>6.0f}{g["target"]:>5}'
            f'{mean - g["target"]:>+6.0f}{f"{fid}/{len(team) * 4}":>8}'
            f'  {nrole}/4{"+M" if g["roles"]["mega"] else "  "}'
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
