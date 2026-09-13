#!/usr/bin/env python3
"""Stage 0 of the doubles differential test: replay Showdown's doubles cases on poke-engine.

Reads generated/showdown_doubles_cases.json (written by tools/showdown_doubles_cases.js,
with Showdown as the reference and its PRNG pinned to always-max), rebuilds each position
as a poke-engine doubles State using the *exact* stats Showdown computed -- so no stat
formula difference can masquerade as a mechanics disagreement -- runs the same joint action
through generate_instructions, and compares the two engines' per-slot outcomes.

What is compared, and what deliberately is not. poke-engine branches on the damage roll and
returns a set of weighted outcomes, while Showdown is pinned to one (its max roll). So the
absolute numbers are NOT comparable -- poke-engine's most probable branch runs about 0.86 of
Showdown's max roll, which is a roll model difference and says nothing about doubles. What
stage 0 asks instead is roll-independent and is the whole doubles question:

  * WHICH bodies took damage at all (targeting, spread, redirection, Protect-class blocks)
  * WHICH bodies got which boosts (Intimidate, Lightning Rod, setup)
  * and, separately reported as a number rather than a verdict, the per-body damage RATIO
    poke-engine/Showdown, in the format of the 0.8.0 --check (median, % within 10%)

Bodies are keyed by species, not by slot, so Ally Switch moving a body between slots cannot
masquerade as a damage disagreement. Crucially, slot occupancy is tracked *through* the
instruction list: `Switch` and `SwapActiveSlots` change who stands in a slot mid-turn, so a
`Damage SideOne:0` before and after one of them refers to different bodies. Reading the
occupancy off the pre-turn snapshot instead -- the first version of this script -- reports
the body that left as the one that was hit, and invents two disagreements that are not there.

Needs a doubles build of the bindings:
    cd <clone>/poke-engine-py && maturin develop --no-default-features \\
        --features="poke-engine/gen5,doubles"
The --no-default-features is required: the default is poke-engine/gen4, and two generation
features at once fails to compile with duplicate definitions.

Also needs patches/poke_engine_doubles_debug_slot.patch applied to the clone, without which
Damage and Boost instructions do not print which slot they hit and nothing here is decidable.

    python3 tools/pe_doubles_diff.py [cases.json]
"""
import json, re, sys, collections
from poke_engine import State, Side, Pokemon, Move, generate_instructions

CASES = sys.argv[1] if len(sys.argv) > 1 else "generated/showdown_doubles_cases.json"
pid = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())

def mon(d):
    t = [pid(x) for x in d["types"]]
    return Pokemon(
        id=pid(d["species"]), level=100,
        types=(t[0], t[1] if len(t) > 1 else "typeless"),
        hp=d["hp"], maxhp=d["maxhp"],
        attack=d["stats"]["atk"], defense=d["stats"]["def"],
        special_attack=d["stats"]["spa"], special_defense=d["stats"]["spd"],
        speed=d["stats"]["spe"],
        ability=pid(d["ability"]), item=pid(d["item"]) if d["item"] else "none",
        # Showdown's code ("par", "brn", ...) is not poke-engine's enum name, and passing one
        # through panics the binding with "Invalid PokemonStatus". Latent until a case starts
        # a body already statused, which the status-targeting cases make possible.
        status=SD_STATUS.get(pid(d["status"]), pid(d["status"])).lower(),
        weight_kg=float(d.get("weightkg") or 0),
        moves=[Move(id=pid(m["id"]), pp=m["pp"]) for m in d["moves"]],
    )

def side(s):
    # actives first so their indices are 0 and 1, matching active_indices
    return Side(active_indices=["0", "1"],
                pokemon=[mon(p) for p in s["active"] if p] + [mon(p) for p in s["bench"]])

# ---- the two projections being compared -------------------------------------------------

def showdown_outcome(case):
    """HP, boost and status deltas Showdown actually produced, keyed by (side, species)."""
    dmg, boost, status = collections.Counter(), collections.Counter(), {}
    for b, a in zip(case["before"], case["after"]):
        who = "s1" if b["side"] == "p1" else "s2"
        was = {p["species"]: p for p in b["active"] + b["bench"] if p}
        for p in [x for x in a["active"] + a["bench"] if x]:
            pb = was.get(p["species"])
            if not pb:
                continue
            if pb["hp"] - p["hp"]:
                dmg[(who, p["species"])] = pb["hp"] - p["hp"]
            for stat, v in p["boosts"].items():
                if v - pb["boosts"].get(stat, 0):
                    boost[(who, p["species"], stat)] = v - pb["boosts"].get(stat, 0)
            # A body that fainted this turn is marked "fnt", which is not a status poke-engine
            # can express (it uses hp 0), so it must not read as a status disagreement.
            old, new = SD_STATUS.get(pb.get("status", "none"), "NONE"), \
                SD_STATUS.get(p.get("status", "none"), "NONE")
            if old != new and not p.get("fainted") and p["hp"] > 0:
                status[(who, p["species"])] = new
    return dmg, boost, status

PE_STAT = {"Attack": "atk", "Defense": "def", "SpecialAttack": "spa",
           "SpecialDefense": "spd", "Speed": "spe", "Accuracy": "accuracy", "Evasion": "evasion"}
DMG = re.compile(r"^Damage (SideOne|SideTwo):(\d+): (-?\d+)$")
BST = re.compile(r"^Boost (SideOne|SideTwo):(\d+) (\w+): (-?\d+)$")
SWI = re.compile(r"^Switch (SideOne|SideTwo): P(\d+) -> P(\d+)$")
SWP = re.compile(r"^SwapActiveSlots\((SideOne|SideTwo)\)$")
# ChangeStatus is the one compared instruction keyed by PARTY INDEX rather than slot
# (`instruction.rs:181` prints `c.pokemon_index`), so it resolves through `roster`, not
# `names`. Keying it by slot would silently mis-attribute every status on a swapped field.
STA = re.compile(r"^ChangeStatus (SideOne|SideTwo)-P(\d+): (\w+) -> (\w+)$")
# Showdown's status codes are not poke-engine's enum names.
SD_STATUS = {"": "NONE", "none": "NONE", "fnt": "NONE", "slp": "SLEEP", "par": "PARALYZE",
             "brn": "BURN", "psn": "POISON", "tox": "TOXIC", "frz": "FREEZE"}

def pe_outcome(branch, names, roster):
    """Same projection off poke-engine's instruction list, keyed by body.

    `names` maps (side, slot) -> species at the start of the turn and is updated as the
    stream goes: a Switch replaces a slot's occupant, SwapActiveSlots exchanges slots 0 and
    1. `roster` maps (side, party index) -> species so a Switch can be resolved."""
    names = dict(names)
    dmg, boost, status = collections.Counter(), collections.Counter(), {}
    for ins in branch.instruction_list:
        s = str(ins)
        m = STA.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            status[(who, roster[(who, int(m[2]))])] = m[4]
            continue
        m = SWI.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            leaving = roster[(who, int(m[2]))]
            slot = next((sl for (w, sl), n in names.items() if w == who and n == leaving), 0)
            names[(who, slot)] = roster[(who, int(m[3]))]
            continue
        m = SWP.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            names[(who, 0)], names[(who, 1)] = names[(who, 1)], names[(who, 0)]
            continue
        m = DMG.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            dmg[(who, names[(who, int(m[2]))])] += int(m[3]); continue
        m = BST.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            boost[(who, names[(who, int(m[2]))], PE_STAT.get(m[3], m[3]))] += int(m[4])
    return dmg, boost, status

# ---- run --------------------------------------------------------------------------------

cases = json.load(open(CASES, encoding="utf8"))
agree, disagree, ratios = [], [], []
for case in cases:
    st = State(side_one=side(case["before"][0]), side_two=side(case["before"][1]))
    names, roster = {}, {}
    for who, s_ in (("s1", case["before"][0]), ("s2", case["before"][1])):
        party = [x for x in s_["active"] if x] + list(s_["bench"])
        for idx, p in enumerate(party):
            roster[(who, idx)] = p["species"]
        for slot, p in enumerate([x for x in s_["active"] if x]):
            names[(who, slot)] = p["species"]
    try:
        branches = generate_instructions(st, case["pe"]["s1"], case["pe"]["s2"])
    except Exception as exc:
        disagree.append((case, f"poke-engine refused the action: {exc}", None, None))
        continue
    branches = sorted(branches, key=lambda b: -b.percentage)
    sd_d, sd_b, sd_s = showdown_outcome(case)
    pe_d, pe_b, pe_s = pe_outcome(branches[0], names, roster)
    notes = []
    if set(sd_d) != set(pe_d):
        only_sd = sorted(set(sd_d) - set(pe_d))
        only_pe = sorted(set(pe_d) - set(sd_d))
        notes.append("bodies damaged differ:" +
                     (f" Showdown hit {only_sd} and poke-engine did not." if only_sd else "") +
                     (f" poke-engine hit {only_pe} and Showdown did not." if only_pe else ""))
    if sd_b != pe_b:
        notes.append(f"boosts differ: Showdown {dict(sd_b)} vs poke-engine {dict(pe_b)}")
    if sd_s != pe_s:
        notes.append(f"statuses differ: Showdown {sd_s} vs poke-engine {pe_s}")
    for k in set(sd_d) & set(pe_d):
        if sd_d[k]:
            ratios.append((case["name"], k, pe_d[k] / sd_d[k]))
    (agree if not notes else disagree).append((case, notes, sd_d, pe_d))

import statistics
print(f"cases: {len(cases)}   agree: {len(agree)}   disagree: {len(disagree)}")
if ratios:
    vals = [r for _, _, r in ratios]
    print(f"damage ratio poke-engine(top branch)/Showdown(max roll) over {len(vals)} shared hits: "
          f"median {statistics.median(vals):.3f}, within 10% {100*sum(0.9<=v<=1.1 for v in vals)/len(vals):.0f}%, "
          f"range {min(vals):.3f}-{max(vals):.3f}   (a roll model difference, not a mechanics one)")
print()
for case, notes, *_ in disagree:
    print(f"  DISAGREE  {case['name']}")
    print(f"            {case['why']}")
    for n in (notes if isinstance(notes, list) else [notes]):
        print(f"            - {n}")
for case, *_ in agree:
    print(f"  agree     {case['name']}")
