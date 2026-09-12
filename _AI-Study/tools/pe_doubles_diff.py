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
masquerade as a damage disagreement.

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
        status=pid(d["status"]), weight_kg=float(d.get("weightkg") or 0),
        moves=[Move(id=pid(m["id"]), pp=m["pp"]) for m in d["moves"]],
    )

def side(s):
    # actives first so their indices are 0 and 1, matching active_indices
    return Side(active_indices=["0", "1"],
                pokemon=[mon(p) for p in s["active"] if p] + [mon(p) for p in s["bench"]])

# ---- the two projections being compared -------------------------------------------------

def showdown_outcome(case):
    """HP and boost deltas Showdown actually produced, keyed by (side, species)."""
    dmg, boost = collections.Counter(), collections.Counter()
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
    return dmg, boost

PE_STAT = {"Attack": "atk", "Defense": "def", "SpecialAttack": "spa",
           "SpecialDefense": "spd", "Speed": "spe", "Accuracy": "accuracy", "Evasion": "evasion"}
DMG = re.compile(r"^Damage (SideOne|SideTwo):(\d+): (-?\d+)$")
BST = re.compile(r"^Boost (SideOne|SideTwo):(\d+) (\w+): (-?\d+)$")

def pe_outcome(branch, names):
    """Same projection off poke-engine's instruction list. `names` maps (side, slot) to the
    species standing there, so both sides of the comparison are keyed by body."""
    dmg, boost = collections.Counter(), collections.Counter()
    for ins in branch.instruction_list:
        s = str(ins)
        m = DMG.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            dmg[(who, names[(who, int(m[2]))])] += int(m[3]); continue
        m = BST.match(s)
        if m:
            who = "s1" if m[1] == "SideOne" else "s2"
            boost[(who, names[(who, int(m[2]))], PE_STAT.get(m[3], m[3]))] += int(m[4])
    return dmg, boost

# ---- run --------------------------------------------------------------------------------

cases = json.load(open(CASES, encoding="utf8"))
agree, disagree, ratios = [], [], []
for case in cases:
    st = State(side_one=side(case["before"][0]), side_two=side(case["before"][1]))
    names = {}
    for who, s_ in (("s1", case["before"][0]), ("s2", case["before"][1])):
        for slot, p in enumerate([x for x in s_["active"] if x]):
            names[(who, slot)] = p["species"]
    try:
        branches = generate_instructions(st, case["pe"]["s1"], case["pe"]["s2"])
    except Exception as exc:
        disagree.append((case, f"poke-engine refused the action: {exc}", None, None))
        continue
    branches = sorted(branches, key=lambda b: -b.percentage)
    sd_d, sd_b = showdown_outcome(case)
    pe_d, pe_b = pe_outcome(branches[0], names)
    notes = []
    if set(sd_d) != set(pe_d):
        only_sd = sorted(set(sd_d) - set(pe_d))
        only_pe = sorted(set(pe_d) - set(sd_d))
        notes.append("bodies damaged differ:" +
                     (f" Showdown hit {only_sd} and poke-engine did not." if only_sd else "") +
                     (f" poke-engine hit {only_pe} and Showdown did not." if only_pe else ""))
    if sd_b != pe_b:
        notes.append(f"boosts differ: Showdown {dict(sd_b)} vs poke-engine {dict(pe_b)}")
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
