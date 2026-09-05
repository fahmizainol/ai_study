#!/usr/bin/env python3
"""Generate the Reborn gauntlet's archetype roster sets as a Ruby data module.

Why this exists: the fixed-Normal baseline (PORTABLE-AI-REBORN.md, "Fixed Normal
baseline") measured Portable at 65% and Reborn-Intense at 86.7% against one
hand-picked fixture of 24 Pokemon. That gap may be a property of those 24 mons
rather than of the two AIs. Alternate rosters test roster-invariance.

set_a is the original fixture, carried verbatim so it remains a true control.
set_b and set_c are drawn from curated per-archetype pools with a fixed seed, so
set composition is not chosen post-hoc. The two draws are disjoint from each
other and from set_a, which maximizes contrast between sets.

set_d and set_e were added later, to settle whether 0.3.2's switch-risk gain is
roster-general (it was +11 pooled at p = 0.063, concentrated in set_a). They are
drawn in a second stage, from the candidates set_b/set_c did not take plus
POOLS_EXTRA, under their own seed. That two-stage shape is deliberate: a
single-stage draw from an enlarged pool would re-roll set_b and set_c, since
random.sample depends on the population size, and every recorded run on those
two rosters would stop being comparable. Stage one therefore consumes the RNG
exactly as it did before set_d/set_e existed.

Every species and move name is checked against Reborn's PBS before emission: a
typo here would otherwise surface as a mid-run exception ~25 minutes into a
launch, so validation is deliberately fail-loud and offline.

Pool constraints, and the reasoning behind them:
  - No legendaries/mythicals. set_a averages ~520 BST; a draw of Mew + Jirachi +
    Latios would confound "different mons" with "stronger mons".
  - No mon whose archetype identity depends on a non-slot-0 ability. The gauntlet's
    make_party calls setAbility(0), so e.g. Azumarill gets Thick Fat, not Huge
    Power, and would enter an offense team with 50 base Attack.
  - Each species appears in exactly one archetype pool.

Usage:
    python3 make_gauntlet_teams.py                 # writes generated/gauntlet_teams_reborn.rb
    python3 make_gauntlet_teams.py --report        # also print each set's stat profile
"""

import argparse
import random
import sys
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
PBS = STUDY.parent / "Reborn Yang" / "Reborn Yang" / "PBS" / "PBS"
OUT = STUDY / "generated" / "gauntlet_teams_reborn.rb"

# Draw seed. Fixed so regeneration is reproducible; changing it re-rolls set_b/set_c
# and invalidates any comparison against previously recorded runs.
DRAW_SEED = 20260904

# Second-stage seed for set_d/set_e. Separate from DRAW_SEED so the two stages cannot
# perturb each other; changing it re-rolls only set_d/set_e.
DRAW_SEED_DE = 20260905

# Third-stage seed for set_f/set_g, the DRESSED rosters (0.5.0). Separate again so
# set_b..set_e cannot move: every recorded run is keyed to those exact 96 mons.
DRAW_SEED_FG = 20260906

ARCHETYPES = ["offense", "balance", "bulky", "speed"]

# The original fixture, verbatim from adapters/reborn/Portable_AI_Gauntlet.rb as of
# the 2026-09-04 baseline. Do not reorder: the 3v3 benchmark uses .first(3), so the
# lead trio is load-bearing for comparability with the earlier runs.
SET_A = {
    "offense": [
        ("GARCHOMP",   ["EARTHQUAKE", "DRAGONCLAW", "SWORDSDANCE", "PROTECT"]),
        ("MAGNEZONE",  ["THUNDERBOLT", "FLASHCANNON", "THUNDERWAVE", "PROTECT"]),
        ("GENGAR",     ["SHADOWBALL", "SLUDGEBOMB", "WILLOWISP", "DESTINYBOND"]),
        ("VOLCARONA",  ["FIERYDANCE", "BUGBUZZ", "GIGADRAIN", "QUIVERDANCE"]),
        ("GRENINJA",   ["HYDROPUMP", "ICEBEAM", "DARKPULSE", "UTURN"]),
        ("SCIZOR",     ["BULLETPUNCH", "XSCISSOR", "SWORDSDANCE", "ROOST"]),
    ],
    "balance": [
        ("SKARMORY",   ["BRAVEBIRD", "ROOST", "STEALTHROCK", "WHIRLWIND"]),
        ("SNORLAX",    ["BODYSLAM", "CRUNCH", "REST", "SLEEPTALK"]),
        ("STARMIE",    ["SURF", "PSYCHIC", "RECOVER", "THUNDERBOLT"]),
        ("GLISCOR",    ["EARTHQUAKE", "UTURN", "TOXIC", "ROOST"]),
        ("CLEFABLE",   ["MOONBLAST", "FLAMETHROWER", "THUNDERWAVE", "SOFTBOILED"]),
        ("DRAGONITE",  ["DRAGONCLAW", "EARTHQUAKE", "EXTREMESPEED", "ROOST"]),
    ],
    "bulky": [
        ("UMBREON",    ["FOULPLAY", "TOXIC", "MOONLIGHT", "PROTECT"]),
        ("FERROTHORN", ["POWERWHIP", "GYROBALL", "LEECHSEED", "STEALTHROCK"]),
        ("TOXAPEX",    ["SCALD", "RECOVER", "TOXIC", "HAZE"]),
        ("HIPPOWDON",  ["EARTHQUAKE", "STONEEDGE", "SLACKOFF", "ROAR"]),
        ("CHANSEY",    ["SEISMICTOSS", "TOXIC", "SOFTBOILED", "PROTECT"]),
        ("SLOWBRO",    ["SCALD", "PSYCHIC", "THUNDERWAVE", "SLACKOFF"]),
    ],
    "speed": [
        ("ALAKAZAM",   ["PSYCHIC", "SHADOWBALL", "DAZZLINGGLEAM", "RECOVER"]),
        ("CROBAT",     ["BRAVEBIRD", "CROSSPOISON", "UTURN", "ROOST"]),
        ("WEAVILE",    ["ICICLECRASH", "KNOCKOFF", "ICESHARD", "SWORDSDANCE"]),
        ("JOLTEON",    ["THUNDERBOLT", "SHADOWBALL", "SIGNALBEAM", "VOLTSWITCH"]),
        ("AERODACTYL", ["ROCKSLIDE", "EARTHQUAKE", "AERIALACE", "ROOST"]),
        ("INFERNAPE",  ["CLOSECOMBAT", "FLAREBLITZ", "MACHPUNCH", "UTURN"]),
    ],
}

# Candidate pools for the drawn sets. Disjoint from SET_A and from each other.
POOLS = {
    # High Atk/SpA, offensive movesets, most carry a setup or priority option.
    "offense": [
        ("SALAMENCE",  ["DRAGONCLAW", "EARTHQUAKE", "FIREBLAST", "DRAGONDANCE"]),
        ("LUCARIO",    ["CLOSECOMBAT", "METEORMASH", "EXTREMESPEED", "SWORDSDANCE"]),
        ("HERACROSS",  ["CLOSECOMBAT", "MEGAHORN", "ROCKSLIDE", "SWORDSDANCE"]),
        ("DARMANITAN", ["FLAREBLITZ", "SUPERPOWER", "ROCKSLIDE", "UTURN"]),
        ("KINGDRA",    ["HYDROPUMP", "DRACOMETEOR", "ICEBEAM", "DRAGONDANCE"]),
        ("METAGROSS",  ["METEORMASH", "EARTHQUAKE", "ZENHEADBUTT", "BULLETPUNCH"]),
        ("HYDREIGON",  ["DARKPULSE", "DRACOMETEOR", "FLAMETHROWER", "UTURN"]),
        ("MAMOSWINE",  ["EARTHQUAKE", "ICICLECRASH", "ICESHARD", "STONEEDGE"]),
        ("CHANDELURE", ["FIREBLAST", "SHADOWBALL", "ENERGYBALL", "CALMMIND"]),
        ("TYRANITAR",  ["STONEEDGE", "CRUNCH", "EARTHQUAKE", "DRAGONDANCE"]),
        ("EXCADRILL",  ["EARTHQUAKE", "IRONHEAD", "ROCKSLIDE", "SWORDSDANCE"]),
        ("NIDOKING",   ["EARTHPOWER", "SLUDGEWAVE", "ICEBEAM", "FLAMETHROWER"]),
        ("SHARPEDO",   ["WATERFALL", "CRUNCH", "ICEFANG", "PROTECT"]),
        ("RHYPERIOR",  ["EARTHQUAKE", "STONEEDGE", "MEGAHORN", "ROCKBLAST"]),
        ("BISHARP",    ["IRONHEAD", "KNOCKOFF", "SUCKERPUNCH", "SWORDSDANCE"]),
    ],
    # Mixed offense/utility: recovery, hazards, pivots, status.
    "balance": [
        ("TENTACRUEL", ["SCALD", "SLUDGEBOMB", "TOXICSPIKES", "RAPIDSPIN"]),
        ("MANDIBUZZ",  ["FOULPLAY", "ROOST", "TOXIC", "DEFOG"]),
        ("EMPOLEON",   ["SCALD", "FLASHCANNON", "STEALTHROCK", "ICEBEAM"]),
        ("GOODRA",     ["DRAGONPULSE", "FIREBLAST", "THUNDERBOLT", "REST"]),
        ("TANGROWTH",  ["GIGADRAIN", "KNOCKOFF", "LEECHSEED", "SLEEPPOWDER"]),
        ("VAPOREON",   ["SCALD", "ICEBEAM", "WISH", "PROTECT"]),
        ("GARDEVOIR",  ["MOONBLAST", "PSYCHIC", "WILLOWISP", "CALMMIND"]),
        ("LANTURN",    ["SCALD", "THUNDERBOLT", "ICEBEAM", "HEALBELL"]),
        ("WHIMSICOTT", ["MOONBLAST", "LEECHSEED", "ENCORE", "UTURN"]),
        ("ROSERADE",   ["GIGADRAIN", "SLUDGEBOMB", "TOXICSPIKES", "SLEEPPOWDER"]),
        ("FLYGON",     ["EARTHQUAKE", "DRAGONCLAW", "UTURN", "ROOST"]),
        ("MILOTIC",    ["SCALD", "ICEBEAM", "RECOVER", "HAZE"]),
        ("ALTARIA",    ["DRAGONPULSE", "FLAMETHROWER", "ROOST", "HAZE"]),
        ("BLASTOISE",  ["SCALD", "ICEBEAM", "RAPIDSPIN", "DARKPULSE"]),
        ("SYLVEON",    ["MOONBLAST", "WISH", "PROTECT", "CALMMIND"]),
        ("ARCANINE",   ["FLAREBLITZ", "EXTREMESPEED", "WILLOWISP", "MORNINGSUN"]),
        ("LUDICOLO",   ["SCALD", "GIGADRAIN", "ICEBEAM", "LEECHSEED"]),
        ("CLAYDOL",    ["EARTHQUAKE", "PSYCHIC", "STEALTHROCK", "RAPIDSPIN"]),
        ("SWAMPERT",   ["EARTHQUAKE", "WATERFALL", "STEALTHROCK", "ICEBEAM"]),
    ],
    # Walls: high HP/Def/SpD, recovery, status, hazard control.
    "bulky": [
        ("QUAGSIRE",   ["EARTHQUAKE", "SCALD", "RECOVER", "TOXIC"]),
        ("AMOONGUSS",  ["GIGADRAIN", "SLUDGEBOMB", "SPORE", "SYNTHESIS"]),
        ("MANTINE",    ["SCALD", "ROOST", "TOXIC", "DEFOG"]),
        ("GASTRODON",  ["SCALD", "EARTHPOWER", "RECOVER", "TOXIC"]),
        ("BRONZONG",   ["GYROBALL", "EARTHQUAKE", "STEALTHROCK", "TOXIC"]),
        ("REGISTEEL",  ["IRONHEAD", "SEISMICTOSS", "TOXIC", "PROTECT"]),
        ("WEEZING",    ["SLUDGEBOMB", "WILLOWISP", "PAINSPLIT", "FLAMETHROWER"]),
        ("DUSKNOIR",   ["SHADOWBALL", "WILLOWISP", "PAINSPLIT", "EARTHQUAKE"]),
        ("CHESNAUGHT", ["WOODHAMMER", "DRAINPUNCH", "LEECHSEED", "SPIKES"]),
        ("ALOMOMOLA",  ["SCALD", "WISH", "PROTECT", "TOXIC"]),
        ("PORYGON2",   ["TRIATTACK", "RECOVER", "TOXIC", "ICEBEAM"]),
        ("TORKOAL",    ["LAVAPLUME", "STEALTHROCK", "WILLOWISP", "EARTHQUAKE"]),
        ("FORRETRESS", ["GYROBALL", "SPIKES", "RAPIDSPIN", "TOXIC"]),
        ("DONPHAN",    ["EARTHQUAKE", "ICESHARD", "STEALTHROCK", "RAPIDSPIN"]),
        ("MUK",        ["GUNKSHOT", "PAINSPLIT", "FIREPUNCH", "TOXIC"]),
    ],
    # Fast attackers and pivots.
    "speed": [
        ("STARAPTOR",  ["BRAVEBIRD", "CLOSECOMBAT", "UTURN", "DOUBLEEDGE"]),
        ("SCEPTILE",   ["LEAFBLADE", "XSCISSOR", "ROCKSLIDE", "SWORDSDANCE"]),
        ("ELECTRODE",  ["THUNDERBOLT", "VOLTSWITCH", "THUNDERWAVE", "EXPLOSION"]),
        ("FLOATZEL",   ["WATERFALL", "ICEPUNCH", "CRUNCH", "AQUAJET"]),
        ("TALONFLAME", ["BRAVEBIRD", "FLAREBLITZ", "ROOST", "UTURN"]),
        ("NOIVERN",    ["HURRICANE", "DRACOMETEOR", "FLAMETHROWER", "UTURN"]),
        ("DUGTRIO",    ["EARTHQUAKE", "STONEEDGE", "SUCKERPUNCH", "PROTECT"]),
        ("SWELLOW",    ["BRAVEBIRD", "UTURN", "QUICKATTACK", "PROTECT"]),
        ("MISMAGIUS",  ["SHADOWBALL", "THUNDERBOLT", "DAZZLINGGLEAM", "NASTYPLOT"]),
        ("LOPUNNY",    ["RETURN", "CLOSECOMBAT", "ICEPUNCH", "FAKEOUT"]),
        ("ESPEON",     ["PSYCHIC", "SHADOWBALL", "DAZZLINGGLEAM", "MORNINGSUN"]),
        ("ACCELGOR",   ["BUGBUZZ", "SLUDGEBOMB", "FOCUSBLAST", "SPIKES"]),
        ("ARCHEOPS",   ["ROCKSLIDE", "EARTHQUAKE", "UTURN", "ACROBATICS"]),
        ("NINETALES",  ["FLAMETHROWER", "DARKPULSE", "WILLOWISP", "ENERGYBALL"]),
        ("MANECTRIC",  ["THUNDERBOLT", "FLAMETHROWER", "VOLTSWITCH", "THUNDERWAVE"]),
        ("GALVANTULA", ["THUNDERBOLT", "BUGBUZZ", "ENERGYBALL", "VOLTSWITCH"]),
        ("ZOROARK",    ["DARKPULSE", "FLAMETHROWER", "FOCUSBLAST", "NASTYPLOT"]),
        ("KROOKODILE", ["EARTHQUAKE", "KNOCKOFF", "STONEEDGE", "SWORDSDANCE"]),
    ],
}

# Second-stage candidates, for set_d/set_e. Same constraints as POOLS (no legendaries,
# no archetype identity that needs a non-slot-0 ability, disjoint from everything
# above). Kept in a separate table rather than appended to POOLS so that stage one's
# rng.sample population is byte-identical to the one that produced set_b/set_c.
# Third-stage additions, for set_f/set_g only.
#
# WHY THEY EXIST. set_a..set_e were built for a study that only ever asked about
# per-turn move policy, and the gauntlet builds every mon with setAbility(0) and no
# held item -- so across those 120 mons, Unaware, Contrary, Justified, Regenerator,
# Magic Guard, Magic Bounce, Multiscale, Mold Breaker and EVERY item row of the 0.5.0
# tables can never fire even once. Half of 0.5.0 is unmeasurable there, which is why
# f/g exist and why a..e and f..g are never pooled.
#
# These entries are additions the pools genuinely lacked: a Magic Guard user, a
# Multiscale user, and the Trick Room / Tailwind / Fake Out users that no pool
# carried. Everything else f/g needs is already in the leftovers.
POOLS_FG = {
    "offense": [
        ("HAWLUCHA",    ["ACROBATICS", "CLOSECOMBAT", "SWORDSDANCE", "ROOST"]),
        ("MEDICHAM",    ["DRAINPUNCH", "ZENHEADBUTT", "ICEPUNCH", "FAKEOUT"]),
        ("MIENSHAO",    ["CLOSECOMBAT", "KNOCKOFF", "UTURN", "FAKEOUT"]),
        ("AEGISLASH",   ["SHADOWBALL", "FLASHCANNON", "SHADOWSNEAK", "SWORDSDANCE"]),
        ("MAGMORTAR",   ["FIREBLAST", "THUNDERBOLT", "FOCUSBLAST", "PSYCHIC"]),
        ("LUXRAY",      ["WILDCHARGE", "CRUNCH", "ICEFANG", "SUPERPOWER"]),
        ("RAMPARDOS",   ["ROCKSLIDE", "EARTHQUAKE", "ZENHEADBUTT", "SUPERPOWER"]),
        ("GOLURK",      ["EARTHQUAKE", "SHADOWPUNCH", "ICEPUNCH", "STONEEDGE"]),
        ("MALAMAR",     ["PSYCHOCUT", "KNOCKOFF", "SUPERPOWER", "REST"]),
        ("ENTEI",       ["SACREDFIRE", "STONEEDGE", "EXTREMESPEED", "BULLDOZE"]),
        ("MOLTRES",     ["FIREBLAST", "AIRSLASH", "HEATWAVE", "ROOST"]),
        ("TORTERRA",    ["WOODHAMMER", "EARTHQUAKE", "STONEEDGE", "SYNTHESIS"]),
    ],
    "balance": [
        ("SIGILYPH",    ["PSYCHIC", "AIRSLASH", "HEATWAVE", "ROOST"]),
        ("MEOWSTIC",    ["PSYCHIC", "THUNDERWAVE", "LIGHTSCREEN", "REFLECT"]),
        ("TOGEKISS",    ["AIRSLASH", "DAZZLINGGLEAM", "THUNDERWAVE", "ROOST"]),
        ("ZAPDOS",      ["THUNDERBOLT", "HEATWAVE", "ROOST", "TOXIC"]),
        ("SUICUNE",     ["SCALD", "ICEBEAM", "CALMMIND", "REST"]),
        ("AZUMARILL",   ["WATERFALL", "PLAYROUGH", "AQUAJET", "SUPERPOWER"]),
        ("ROTOM",       ["THUNDERBOLT", "SHADOWBALL", "VOLTSWITCH", "WILLOWISP"]),
        ("KLEFKI",      ["FLASHCANNON", "THUNDERWAVE", "REFLECT", "LIGHTSCREEN"]),
        ("DIGGERSBY",   ["EARTHQUAKE", "RETURN", "KNOCKOFF", "SWORDSDANCE"]),
        ("YANMEGA",     ["BUGBUZZ", "AIRSLASH", "GIGADRAIN", "PROTECT"]),
        ("DRIFBLIM",    ["SHADOWBALL", "HEX", "WILLOWISP", "DESTINYBOND"]),
        ("GLACEON",     ["ICEBEAM", "SHADOWBALL", "WISH", "PROTECT"]),
    ],
    "bulky": [
        ("REUNICLUS",   ["PSYCHIC", "FOCUSBLAST", "RECOVER", "TRICKROOM"]),
        ("BLISSEY",     ["SEISMICTOSS", "TOXIC", "SOFTBOILED", "PROTECT"]),
        ("GOURGEIST",   ["SEEDBOMB", "SHADOWSNEAK", "WILLOWISP", "LEECHSEED"]),
        ("TREVENANT",   ["WOODHAMMER", "SHADOWCLAW", "WILLOWISP", "LEECHSEED"]),
        ("MUSHARNA",    ["PSYCHIC", "MOONLIGHT", "TOXIC", "TRICKROOM"]),
        ("HYPNO",       ["PSYCHIC", "SEISMICTOSS", "TOXIC", "TRICKROOM"]),
        ("ABOMASNOW",   ["BLIZZARD", "GIGADRAIN", "EARTHQUAKE", "LEECHSEED"]),
        ("BASTIODON",   ["IRONHEAD", "STEALTHROCK", "TOXIC", "PROTECT"]),
        ("TANGELA",     ["GIGADRAIN", "SLUDGEBOMB", "LEECHSEED", "SYNTHESIS"]),
        ("ARTICUNO",    ["ICEBEAM", "HURRICANE", "ROOST", "TOXIC"]),
        ("LUGIA",       ["AEROBLAST", "PSYCHIC", "ROOST", "TOXIC"]),
        ("WOBBUFFET",   ["COUNTER", "MIRRORCOAT", "ENCORE", "DESTINYBOND"]),
    ],
    "speed": [
        ("PERSIAN",     ["FAKEOUT", "KNOCKOFF", "PLAYROUGH", "UTURN"]),
        ("GYARADOS",    ["WATERFALL", "EARTHQUAKE", "ICEFANG", "DRAGONDANCE"]),
        ("RAIKOU",      ["THUNDERBOLT", "AURASPHERE", "EXTRASENSORY", "CALMMIND"]),
        ("FLAREON",     ["FLAREBLITZ", "SUPERPOWER", "QUICKATTACK", "WISH"]),
        ("LEAFEON",     ["LEAFBLADE", "KNOCKOFF", "XSCISSOR", "SWORDSDANCE"]),
        ("CINCCINO",    ["TAILSLAP", "BULLETSEED", "ROCKBLAST", "UTURN"]),
        ("TOXICROAK",   ["GUNKSHOT", "DRAINPUNCH", "SUCKERPUNCH", "SWORDSDANCE"]),
        ("SHIFTRY",     ["LEAFBLADE", "KNOCKOFF", "SUCKERPUNCH", "SWORDSDANCE"]),
        ("LIEPARD",     ["KNOCKOFF", "PLAYROUGH", "UTURN", "ENCORE"]),
        ("DRAPION",     ["POISONJAB", "KNOCKOFF", "EARTHQUAKE", "SWORDSDANCE"]),
        ("SPIRITOMB",   ["SHADOWSNEAK", "SUCKERPUNCH", "WILLOWISP", "PAINSPLIT"]),
        ("EELEKTROSS",  ["THUNDERBOLT", "FLAMETHROWER", "GIGADRAIN", "COIL"]),
    ],
}

# Items the dressed rosters carry, applied by draw position so the spread is fixed by
# construction rather than chosen per species. Six entries over 48 mons is eight of
# each, which clears the coverage floor the 0.5.0 plan asked for (>= 6 Boots, >= 6
# Leftovers, >= 4 Choice, >= 3 Sash) without anyone picking who gets what.
ITEM_CYCLE = ["HEAVYDUTYBOOTS", "LEFTOVERS", "CHOICESCARF", "FOCUSSASH",
              "LIFEORB", "ASSAULTVEST"]

POOLS_EXTRA = {
    "offense": [
        ("HAXORUS",     ["DRAGONCLAW", "EARTHQUAKE", "POISONJAB", "DRAGONDANCE"]),
        ("CONKELDURR",  ["DRAINPUNCH", "MACHPUNCH", "STONEEDGE", "BULKUP"]),
        ("HONCHKROW",   ["BRAVEBIRD", "SUCKERPUNCH", "NIGHTSLASH", "ROOST"]),
        ("ESCAVALIER",  ["MEGAHORN", "IRONHEAD", "DRAINPUNCH", "SWORDSDANCE"]),
        ("FERALIGATR",  ["WATERFALL", "CRUNCH", "ICEPUNCH", "DRAGONDANCE"]),
        ("EMBOAR",      ["FLAREBLITZ", "SUPERPOWER", "WILDCHARGE", "SUCKERPUNCH"]),
        ("SAMUROTT",    ["HYDROPUMP", "ICEBEAM", "GRASSKNOT", "AQUAJET"]),
        ("KABUTOPS",    ["STONEEDGE", "WATERFALL", "AQUAJET", "SWORDSDANCE"]),
        ("GALLADE",     ["CLOSECOMBAT", "PSYCHOCUT", "NIGHTSLASH", "SWORDSDANCE"]),
        ("MACHAMP",     ["CLOSECOMBAT", "KNOCKOFF", "STONEEDGE", "BULKUP"]),
        ("ELECTIVIRE",  ["WILDCHARGE", "ICEPUNCH", "CROSSCHOP", "EARTHQUAKE"]),
    ],
    "balance": [
        ("VENUSAUR",    ["GIGADRAIN", "SLUDGEBOMB", "LEECHSEED", "SYNTHESIS"]),
        ("MEGANIUM",    ["GIGADRAIN", "BODYSLAM", "LEECHSEED", "SYNTHESIS"]),
        ("SLOWKING",    ["SCALD", "PSYCHIC", "ICEBEAM", "SLACKOFF"]),
        ("POLITOED",    ["SCALD", "ICEBEAM", "TOXIC", "PROTECT"]),
        ("JELLICENT",   ["SCALD", "SHADOWBALL", "RECOVER", "WILLOWISP"]),
        ("BRAVIARY",    ["BRAVEBIRD", "SUPERPOWER", "UTURN", "ROOST"]),
    ],
    "bulky": [
        ("CRADILY",     ["GIGADRAIN", "ROCKSLIDE", "RECOVER", "TOXIC"]),
        ("CARRACOSTA",  ["SCALD", "ROCKSLIDE", "TOXIC", "PROTECT"]),
        ("DRAGALGE",    ["SLUDGEBOMB", "DRAGONPULSE", "TOXIC", "PROTECT"]),
        ("STEELIX",     ["IRONHEAD", "EARTHQUAKE", "STEALTHROCK", "ROAR"]),
        ("COFAGRIGUS",  ["SHADOWBALL", "WILLOWISP", "PAINSPLIT", "TOXIC"]),
        ("MILTANK",     ["BODYSLAM", "MILKDRINK", "TOXIC", "PROTECT"]),
        ("AGGRON",      ["HEAVYSLAM", "EARTHQUAKE", "STEALTHROCK", "ROAR"]),
        ("SEISMITOAD",  ["EARTHQUAKE", "SCALD", "TOXIC", "PROTECT"]),
        ("LICKILICKY",  ["BODYSLAM", "EARTHQUAKE", "TOXIC", "PROTECT"]),
        ("TSAREENA",    ["POWERWHIP", "PLAYROUGH", "SYNTHESIS", "LEECHSEED"]),
    ],
    "speed": [
        ("TAUROS",      ["BODYSLAM", "EARTHQUAKE", "ROCKSLIDE", "WILDCHARGE"]),
        ("RAPIDASH",    ["FLAREBLITZ", "WILDCHARGE", "MEGAHORN", "MORNINGSUN"]),
        ("PYROAR",      ["FIREBLAST", "HYPERVOICE", "DARKPULSE", "WILLOWISP"]),
        ("SCOLIPEDE",   ["MEGAHORN", "POISONJAB", "ROCKSLIDE", "SWORDSDANCE"]),
        ("ZEBSTRIKA",   ["THUNDERBOLT", "OVERHEAT", "VOLTSWITCH", "THUNDERWAVE"]),
        ("SALAZZLE",    ["FIREBLAST", "SLUDGEWAVE", "DRAGONPULSE", "NASTYPLOT"]),
        ("DODRIO",      ["BRAVEBIRD", "DOUBLEEDGE", "KNOCKOFF", "ROOST"]),
    ],
}


def load_ability_slots():
    """species -> [ability0, ability1, hidden], the slot layout setAbility indexes."""
    out, current = {}, None
    for line in (PBS / "pokemon.txt").read_text(encoding="utf-8",
                                                errors="replace").splitlines():
        line = line.strip()
        if line.startswith("InternalName="):
            current = line.split("=", 1)[1].strip()
            out.setdefault(current, [None, None, None])
        elif current and line.startswith("Abilities="):
            regs = [a.strip() for a in line.split("=", 1)[1].split(",") if a.strip()]
            for i in range(min(2, len(regs))):
                out[current][i] = regs[i]
        elif current and line.startswith("HiddenAbility"):
            hidden = [a.strip() for a in line.split("=", 1)[1].split(",") if a.strip()]
            out[current][2] = hidden[0] if hidden else None
    return out


def load_pbs():
    """Internal species names -> base stats [HP, Atk, Def, Spe, SpA, SpD], and move names."""
    species, current = {}, None
    for line in (PBS / "pokemon.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if line.startswith("InternalName="):
            current = line.split("=", 1)[1]
        elif line.startswith("BaseStats=") and current:
            species[current] = [int(x) for x in line.split("=", 1)[1].split(",")]
    moves = set()
    for line in (PBS / "moves.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split(",")
        if len(parts) > 3 and parts[0].strip().isdigit():
            moves.add(parts[1].strip())
    if not species or not moves:
        raise SystemExit(f"could not parse PBS at {PBS}")
    return species, moves


def validate(species, moves):
    """Fail loudly and completely: report every problem, not just the first."""
    errs = []
    seen = {}
    for source, table in (("SET_A", SET_A), ("POOLS", POOLS),
                          ("POOLS_EXTRA", POOLS_EXTRA), ("POOLS_FG", POOLS_FG)):
        for archetype, entries in table.items():
            if archetype not in ARCHETYPES:
                errs.append(f"{source}: unknown archetype {archetype!r}")
            for name, movelist in entries:
                where = f"{source}/{archetype}/{name}"
                if name not in species:
                    errs.append(f"{where}: species not in pokemon.txt")
                if len(movelist) != 4:
                    errs.append(f"{where}: {len(movelist)} moves, expected 4")
                if len(set(movelist)) != len(movelist):
                    errs.append(f"{where}: duplicate moves")
                for move in movelist:
                    if move not in moves:
                        errs.append(f"{where}: move {move} not in moves.txt")
                prior = seen.get(name)
                if prior:
                    errs.append(f"{where}: species already used in {prior}")
                else:
                    seen[name] = where
    for archetype in ARCHETYPES:
        pool = POOLS.get(archetype, [])
        if len(pool) < 12:
            errs.append(f"POOLS/{archetype}: {len(pool)} candidates, need >= 12 "
                        "for two disjoint draws of 6")
        available = len(pool) - 12 + len(POOLS_EXTRA.get(archetype, []))
        if available < 12:
            errs.append(f"POOLS_EXTRA/{archetype}: {available} candidates left after "
                        "set_b/set_c, need >= 12 for set_d/set_e")
        remaining = available - 12 + len(POOLS_FG.get(archetype, []))
        if remaining < 12:
            errs.append(f"POOLS_FG/{archetype}: {remaining} candidates left after "
                        "set_d/set_e, need >= 12 for set_f/set_g")
    if errs:
        raise SystemExit("roster validation failed:\n  " + "\n  ".join(errs))


def draw_sets(seed, seed_de):
    """Four disjoint 6-mon draws per archetype, in two independent stages.

    Stage one is exactly the original draw and must stay that way: same seed, same
    population, same call order, so set_b and set_c come out identical to the rosters
    every recorded run used. Stage two draws set_d/set_e from what stage one left
    behind plus POOLS_EXTRA, under its own RNG.
    """
    rng = random.Random(seed)
    set_b, set_c = {}, {}
    leftovers = {}
    for archetype in ARCHETYPES:
        picked = rng.sample(POOLS[archetype], 12)
        set_b[archetype] = picked[:6]
        set_c[archetype] = picked[6:]
        taken = {name for name, _ in picked}
        leftovers[archetype] = [entry for entry in POOLS[archetype]
                                if entry[0] not in taken] + POOLS_EXTRA[archetype]

    rng_de = random.Random(seed_de)
    set_d, set_e = {}, {}
    rest = {}
    for archetype in ARCHETYPES:
        picked = rng_de.sample(leftovers[archetype], 12)
        set_d[archetype] = picked[:6]
        set_e[archetype] = picked[6:]
        taken = {name for name, _ in picked}
        rest[archetype] = [entry for entry in leftovers[archetype]
                           if entry[0] not in taken] + POOLS_FG[archetype]
    return set_b, set_c, set_d, set_e, rest


def draw_dressed_sets(rest, seed_fg, species_abilities):
    """set_f and set_g: a third-stage draw, then DRESSED with an ability and an item.

    The dressing is mechanical, not chosen:
      * ability = the species' HIGHEST-numbered non-empty ability slot. Slot 0 is
        what the gauntlet already builds, and it is exactly why Regenerator, Unaware,
        Magic Guard, Magic Bounce, Multiscale, Mold Breaker and Contrary are inert on
        set_a..e; taking the last slot moves as far from that as a species allows.
        "Non-empty" matters: setAbility indexes [slot0, slot1, hidden] directly, so
        naming an empty slot would hand the engine a nil ability.
      * item = ITEM_CYCLE by draw position.
    Both are reproducible from the seed alone and neither is a per-species judgement.
    """
    rng = random.Random(seed_fg)
    set_f, set_g = {}, {}
    position = 0
    for archetype in ARCHETYPES:
        picked = rng.sample(rest[archetype], 12)
        for target, entries in ((set_f, picked[:6]), (set_g, picked[6:])):
            dressed = []
            for name, movelist in entries:
                slots = species_abilities.get(name) or [None, None, None]
                ability_slot = 0
                for index in (2, 1):
                    if slots[index]:
                        ability_slot = index
                        break
                dressed.append((name, movelist,
                                {"item": ITEM_CYCLE[position % len(ITEM_CYCLE)],
                                 "ability": ability_slot}))
                position += 1
            target[archetype] = dressed
    return set_f, set_g


def ruby_literal(sets):
    lines = [
        "# Gauntlet archetype rosters — generated by tools/make_gauntlet_teams.py;",
        "# do not hand-edit. Regenerate to change; the draw seed is fixed in that tool.",
        "#",
        "# set_a is the original 2026-09-04 baseline fixture and is the control.",
        "# set_b..set_e are seeded draws from curated pools, disjoint from set_a and",
        "# from each other. Selected at run time via teams= in Data/ai_harness.txt.",
        "",
        "module PortableAIRebornTeams",
        "  SETS = {",
    ]
    for set_name in sorted(sets):
        lines.append(f'    "{set_name}" => {{')
        for archetype in ARCHETYPES:
            lines.append(f'      "{archetype}" => [')
            for entry in sets[set_name][archetype]:
                name, movelist = entry[0], entry[1]
                joined = " ".join(movelist)
                extra = entry[2] if len(entry) > 2 else None
                if extra:
                    lines.append(
                        f'        ["{name}", %w[{joined}], '
                        f'{{ "item" => "{extra["item"]}", '
                        f'"ability" => {extra["ability"]} }}],')
                else:
                    lines.append(f'        ["{name}", %w[{joined}]],')
            lines[-1] = lines[-1].rstrip(",")
            lines.append("      ],")
        lines[-1] = lines[-1].rstrip(",")
        lines.append("    },")
    lines[-1] = lines[-1].rstrip(",")
    lines += ["  }", "end", ""]
    return "\n".join(lines)


def report(sets, species):
    for set_name in sorted(sets):
        print(f"\n=== {set_name} ===")
        for archetype in ARCHETYPES:
            team = sets[set_name][archetype]
            stats = [species[n] for n, _ in team]
            bst = sum(sum(s) for s in stats) / len(stats)
            spe = sum(s[3] for s in stats) / len(stats)
            off = sum(max(s[1], s[4]) for s in stats) / len(stats)
            bulk = sum(s[0] + s[2] + s[5] for s in stats) / len(stats)
            print(f"  {archetype:8} BST {bst:5.1f}  Spe {spe:5.1f}  "
                  f"bestOff {off:5.1f}  bulk {bulk:5.1f}")
            print(f"           {', '.join(n for n, _ in team)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--seed", type=int, default=DRAW_SEED)
    parser.add_argument("--seed-de", type=int, default=DRAW_SEED_DE)
    parser.add_argument("--seed-fg", type=int, default=DRAW_SEED_FG)
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args()

    species, moves = load_pbs()
    validate(species, moves)
    set_b, set_c, set_d, set_e, rest = draw_sets(args.seed, args.seed_de)
    set_f, set_g = draw_dressed_sets(rest, args.seed_fg, load_ability_slots())
    sets = {"set_a": SET_A, "set_b": set_b, "set_c": set_c,
            "set_d": set_d, "set_e": set_e, "set_f": set_f, "set_g": set_g}

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(ruby_literal(sets), encoding="utf-8", newline="\n")
    print(f"wrote {args.out} (seed {args.seed}, set_d/set_e seed {args.seed_de})")
    if args.report:
        report(sets, species)
    return 0


if __name__ == "__main__":
    sys.exit(main())
