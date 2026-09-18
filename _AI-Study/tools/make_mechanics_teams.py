#!/usr/bin/env python3
"""Generate the mechanics suite: rosters built to EXERCISE mechanics, not to win.

A third suite, deliberately separate from the other two:

  archetype  set_a..set_g   roster-invariance     make_gauntlet_teams.py
  tier       gen5ou_a..     metagame competence   make_tier_teams.py
  mechanics  mech_a         bridge faithfulness   this file

The tier suite draws real Smogon sample teams, which is right for its question and
useless for this one: measured 2026-09-19, those rosters carry ZERO Dig, Fly, Dive,
Bounce, Solar Beam, King's Shield, Spiky Shield or Autotomize between them. Competitive
teams do not run charge moves. A traced gauntlet on them exercises none of the bridge
defects fixed in 0.8.5/0.8.6 and would come back clean while proving nothing -- the
same trap that let a gen 5 pool vouch for Belly Drum and let gen5doublesou's zero
move-slot sets vouch for the parser.

So the roster is chosen by MECHANIC. Each slot is a species that genuinely learns the
move in question, checked against this game's own PBS (level-up, egg AND tm.txt --
reading only the learnset misses Ice Beam on Starmie), with filler picked from what
that species can actually learn. Nothing here is hand-typed, so it cannot drift out of
legality the way a hand-written roster silently does.

Results from this suite are NEVER pooled with the others: these teams are not trying to
win, and their win rate is meaningless. What they produce is traffic through the
mechanics, for tools/check_outcomes.py to audit.
"""

import re
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
GAME = STUDY.parent / "Realidea V4.1"
OUT = STUDY / "generated" / "mechanics_teams_realidea.rb"

# The mechanic each slot exists to exercise, and who may carry it. Order is preference;
# the first species that can legally learn the move in THIS game's dex wins.
SLOTS = [
    ("DIG",           ["EXCADRILL", "DUGTRIO", "SANDSLASH", "KROOKODILE"]),
    ("FLY",           ["SKARMORY", "STARAPTOR", "BRAVIARY", "PIDGEOT", "CROBAT"]),
    ("DIVE",          ["EMPOLEON", "LAPRAS", "SAMUROTT", "KINGDRA", "GYARADOS"]),
    ("BOUNCE",        ["TOGEKISS", "AERODACTYL", "LOPUNNY", "GIRAFARIG", "AMBIPOM", "GRANBULL", "SUDOWOODO", "HITMONTOP"]),
    ("SOLARBEAM",     ["VENUSAUR", "SHIFTRY", "LILLIGANT", "ROSERADE"]),
    ("KINGSSHIELD",   ["AEGISLASH"]),
    ("SPIKYSHIELD",   ["CHESNAUGHT", "TOGEDEMARU"]),
    ("BANEFULBUNKER", ["TOXAPEX"]),
    ("AUTOTOMIZE",    ["SKARMORY", "STEELIX", "FORRETRESS", "AGGRON", "BRONZONG"]),
    ("REST",          ["SNORLAX", "SUICUNE", "MILOTIC", "SLOWBRO"]),
    ("BATONPASS",     ["CELEBI", "NINJASK", "SMEARGLE"]),
    ("FUTURESIGHT",   ["REUNICLUS", "XATU", "JIRACHI", "GARDEVOIR", "ALAKAZAM"]),
]

# Filler must carry no mechanic of its own, or a slot meant to test Dig quietly becomes
# a slot testing something else and the attribution is lost. Essentials encodes that
# directly: function code "000" is a plain damaging move with no added effect, which
# excludes charge moves, recharge moves (Hyper Beam, Giga Impact) and the self-KO
# moves (Explosion, Self-Destruct) that a naive sort by power puts straight in.
PLAIN_FUNCTION_CODE = "000"
# Anything enormous is a one-shot that ends the battle before mechanics get traffic.
FILLER_POWER = (40, 120)
# Filler must not miss. Measured on the first run: Focus Blast at 70% accuracy produced
# three "predicted to land, did nothing" rows that were simply misses, and a detector
# whose rule is "read the repeats" cannot afford filler that manufactures them.
FILLER_MIN_ACCURACY = 100
# NO held item. The first run gave everything Leftovers and 22 of 32 flagged rows were
# one stall loop: Skarmory's Fly is resisted by Steelix (Flying into Steel/Ground is
# x0.5) for about 12% every two turns, against 12.5% of recovery over the same two
# turns, so the target oscillated between 88% and 96% for twenty-four turns and never
# died. Damage exactly cancelled by recovery reads identically to damage that never
# landed. An item is a mechanic too, and this suite is meant to isolate one at a time.
HELD_ITEM = None
# Not every species has three plain moves -- Toxapex has almost none -- so filler falls
# back to effect-bearing moves, minus the codes that carry a MECHANIC. Those codes are
# read off these exemplars rather than guessed, so they stay correct for this game's
# own moves.txt instead of encoding my assumptions about Essentials' numbering.
CODE_EXEMPLARS = ["DIG", "FLY", "DIVE", "BOUNCE", "SOLARBEAM", "RAZORWIND", "SKYATTACK",
                  "SKULLBASH", "HYPERBEAM", "GIGAIMPACT", "EXPLOSION", "SELFDESTRUCT",
                  "FOCUSPUNCH", "KINGSSHIELD", "SPIKYSHIELD", "BANEFULBUNKER",
                  # Conditional damage: zero unless the target is asleep, so it would
                  # flag on every use and drown the signal it is meant to leave alone.
                  "DREAMEATER"]


def learnsets():
    """Every move each species can end up with: level-up, egg, and TM/tutor."""
    text = (GAME / "PBS/pokemon.txt").read_text(encoding="utf-8-sig", errors="replace")
    pools = {}
    for block in re.split(r"\n(?=\[)", text):
        fields = dict(re.findall(r"^(\w+)=(.*)$", block, re.M))
        name = fields.get("InternalName")
        if not name:
            continue
        level = fields.get("Moves", "").split(",")
        pool = {level[i + 1].strip() for i in range(0, len(level) - 1, 2)}
        pool |= {m.strip() for m in fields.get("EggMoves", "").split(",") if m.strip()}
        pools[name.upper()] = pool
    machine = (GAME / "PBS/tm.txt").read_text(encoding="utf-8-sig", errors="replace")
    move = None
    for line in machine.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("["):
            move = line.strip("[]").upper()
            continue
        for species in line.split(","):
            species = species.strip().upper()
            if species in pools:
                pools[species].add(move)
    return pools


def filler_moves():
    """(plain, fallback): name -> power. Plain is preferred; fallback is anything
    damaging that does not carry a mechanic of its own."""
    text = (GAME / "PBS/moves.txt").read_text(encoding="utf-8-sig", errors="replace")
    rows = {}
    for line in text.splitlines():
        parts = line.split(",")
        if len(parts) > 6 and parts[0].strip().isdigit():
            try:
                rows[parts[1].strip().upper()] = (parts[3].strip(), int(parts[4]),
                                                  int(parts[7]))
            except ValueError:
                pass
    banned = {rows[m][0] for m in CODE_EXEMPLARS if m in rows}
    plain, fallback = {}, {}
    for name, (code, strength, accuracy) in rows.items():
        if (not FILLER_POWER[0] <= strength <= FILLER_POWER[1] or code in banned
                or accuracy < FILLER_MIN_ACCURACY):
            continue
        fallback[name] = strength
        if code == PLAIN_FUNCTION_CODE:
            plain[name] = strength
    return plain, fallback


def build():
    pools, (plain, fallback) = learnsets(), filler_moves()
    picked, used = [], set()
    for mechanic, candidates in SLOTS:
        for species in candidates:
            if species in used or mechanic not in pools.get(species, ()):
                continue
            def best(table):
                return sorted((m for m in pools[species] if m != mechanic and m in table),
                              key=lambda m: (-table[m], m))
            filler = best(plain)[:3]
            if len(filler) < 3:
                filler += [m for m in best(fallback) if m not in filler][:3 - len(filler)]
            if len(filler) < 3:
                continue
            picked.append((species, [mechanic] + filler, mechanic))
            used.add(species)
            break
        else:
            raise SystemExit(f"no legal carrier for {mechanic}")
    return picked


def main():
    picked = build()
    teams = [picked[:6], picked[6:12]]
    lines = [
        "# Mechanics suite -- generated by tools/make_mechanics_teams.py; do not hand-edit.",
        "#",
        "# Rosters built to EXERCISE mechanics rather than to win. The tier suite's real",
        "# Smogon teams carry zero charge moves and zero shields, so they cannot test the",
        "# bridge's handling of them; these can. Win rate here is meaningless and must",
        "# never be pooled with the archetype or tier suites -- the output that matters is",
        "# the decision trace, audited by tools/check_outcomes.py.",
        "#",
        "# Each slot's FIRST move is the mechanic it exists to exercise.",
        "",
        "module PortableAIRealideaMechanics",
        "  SETS = {",
        '    "mech_a" => {',
    ]
    for index, team in enumerate(teams, start=1):
        lines.append(f'      "team{index}" => [')
        for species, moves, mechanic in team:
            lines.append(
                f'        ["{species}", %w[{" ".join(moves)}], '
                f'{{ "item" => nil, "ability" => 0, "nature" => 0, '
                f'"evs" => [0, 252, 0, 252, 0, 4] }}],  # {mechanic}')
        lines.append("      ],")
    lines += [
        "    }",
        "  }",
        "end",
        "",
        "# Merged into the archetype suite's lookup so teams= resolves it by name, exactly",
        "# as the tier suite does; the bundle concatenates the gauntlet (which declares",
        "# SETS) first. SUITES is appended to rather than redeclared, because the tier",
        "# file has already defined it by the time this runs.",
        "PortableAIRealideaTeams::SETS.merge!(PortableAIRealideaMechanics::SETS)",
        'PortableAIRealideaTeams::SUITES["mechanics"] = %w[mech_a]',
        "",
    ]
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUT}")
    for species, moves, mechanic in picked:
        print(f"  {mechanic:<14} {species:<12} {' '.join(moves[1:])}")


if __name__ == "__main__":
    main()
