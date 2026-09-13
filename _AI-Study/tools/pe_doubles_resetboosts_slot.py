"""Whose boosts does a switch, Clear Smog or Haze actually clear? (defect 11)

`Side::reset_boosts` (state.rs:1795) took no slot. It read `get_active()` -- slot 0 -- and
emitted a BoostInstruction naming slot 0. Both halves agreed with each other, so apply/reverse
stayed sound and nothing ever crashed; the function simply described the WRONG POKEMON
whenever the slot in question was 1. Three callers want three different bodies:

    switch      the body LEAVING the field       -> `actor_slot()`
    Clear Smog  the RESOLVED TARGET              -> `defender_position()`
    Haze        EVERY living active: four slots in doubles, not two

THE FAULT IS SYMMETRICAL, and a probe that shows only one half understates it. "Cleared the
wrong body" and "failed to clear the right body" are two bugs sharing one line:

    boosts on slot 0, slot 1 switches out  ->  slot 0's boosts are WIPED   (it never left)
    boosts on slot 1, slot 1 switches out  ->  slot 1's boosts SURVIVE     (nothing cleared)

WHAT EACH INSTRUMENT CAN SEE. The corpus can price only the switch caller:
showdown_doubles_lib.js's POOL contains neither Haze nor Clear Smog, so those two are
unmeasurable there by construction -- run 5's lesson, check whether the instrument can see a
thing before building a projection for it -- and they are adjudicated in stage 0 against
Showdown instead. The switch half IS visible, and the reason is worth recording:
pe_doubles_corpus.py:289 restricts the boosts comparison to bodies active in BOTH snapshots,
so the departing body's own legitimate clear is filtered out on both sides. What survives the
filter is exactly the boost wrongly applied to the body that STAYED. That is why corpus
battle 0 turn 10 (p2 playing 'move 1 1, switch 3' -- the SLOT 1 body leaves) reads as
"poke-engine only: Gengar spa -1, spd -1": Gengar is slot 0 and never moved. Note what this
means for A2 below -- the "boosts survive on the departing body" half is invisible to the
corpus by design, so the probe is the only instrument that can show it at all.

SPELLING, twice learned the hard way. A switch is the incoming body's SPECIES in the engine's
action string (pe_doubles_corpus.py:144), not "switch N"; `pid()` lowercases it, so it is
"gengar", not "Gengar". And it must be a REAL species, because the parser resolves the token
against the engine's dex -- the invented bodies this probe first used ("Bench", "Pivot") raise
ValueError: Invalid move and silently cost all three switch sections. Invented names remain
perfectly fine for ATTACKERS, whose stats and types are passed explicitly, which is why the
Ally Switch probe never hit this. Every body below is therefore a real species carrying
explicit stats, ability "none" and type Normal, so nothing varies but the slot under test.
Side one attacks with Tackle rather than passing, because "none" is for an empty or fainted
slot; its Damage lines are filtered out of the verdict below.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions


def b(species, moves, boosts=None, spe=100, hp=400, ability="none"):
    return dict(species=species, hp=hp, maxhp=hp, types=["Normal"], fainted=False,
                ability=ability, item=None, status="none", volatiles=[], lastMove=None,
                boosts=dict(boosts or {}), weightkg=50,
                stats=dict(atk=200, **{"def": 200}, spa=200, spd=200, spe=spe),
                moves=[dict(id=m, pp=16) for m in moves])


def run(label, s1_active, s2_active, a1, a2, expect, s1_bench=(), s2_bench=()):
    """Print only the Boost instructions: they name the slot, and the slot is the verdict."""
    s1 = dict(active=list(s1_active), bench=list(s1_bench), conditions={})
    s2 = dict(active=list(s2_active), bench=list(s2_bench), conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    print(f"\n{label}")
    for tag, act in (("side one", s1_active), ("side two", s2_active)):
        print(f"   {tag}: " + " | ".join(
            f"slot{i} {p['species']}{'' if not p['boosts'] else ' ' + str(p['boosts'])}"
            for i, p in enumerate(act)))
    print(f"   actions: s1={a1!r}  s2={a2!r}")
    print(f"   expected: {expect}")
    try:
        branches = generate_instructions(st, a1, a2)
    except Exception as exc:                      # a panic here is a finding, not a crash
        print(f"      RAISED {type(exc).__name__}: {exc}")
        return
    br = max(branches, key=lambda x: x.percentage)
    boosts = [str(i) for i in br.instruction_list if str(i).startswith("Boost ")]
    print(f"      Boost instructions: {boosts if boosts else 'NONE'}")


FILLERS = lambda: [b("Snorlax", ["tackle"]), b("Machamp", ["tackle"])]
BENCH = lambda: [b("Gengar", ["tackle"])]

print("=" * 88)
print("A. SWITCH: reset_boosts must clear the slot that is LEAVING")
print("=" * 88)
run("(A1) boosts sit on slot 0; the SLOT 1 body switches out.",
    FILLERS(),
    [b("Gyarados", ["tackle"], boosts={"atk": 2}), b("Seaking", ["tackle"])],
    "tackle,0;tackle,0", "tackle,0;gengar",
    "NONE -- Seaking, the body leaving slot 1, carried no boosts. Before the fix: "
    "Boost SideTwo:0 Attack: -2, wiping Gyarados, which never left the field",
    s2_bench=BENCH())
run("(A2) the other half, which the corpus cannot see: boosts sit on slot 1, and SLOT 1 "
    "is the body switching out.",
    FILLERS(),
    [b("Gyarados", ["tackle"]), b("Seaking", ["tackle"], boosts={"atk": 2})],
    "tackle,0;tackle,0", "tackle,0;gengar",
    "Boost SideTwo:1 Attack: -2. Before the fix: NONE -- the departing body took its "
    "boosts with it, so they would come back with it later",
    s2_bench=BENCH())
run("(A3) CONTROL: boosts on slot 0 and SLOT 0 switches out -- the common case, and the "
    "one the old code got right by accident.",
    FILLERS(),
    [b("Gyarados", ["tackle"], boosts={"atk": 2}), b("Seaking", ["tackle"])],
    "tackle,0;tackle,0", "gengar;tackle,0",
    "Boost SideTwo:0 Attack: -2, identical before and after the fix",
    s2_bench=BENCH())

print()
print("=" * 88)
print("B. CLEAR SMOG: reset_boosts must clear the RESOLVED TARGET, not the target's slot 0")
print("=" * 88)
run("(B1) Clear Smog aimed at slot 1, and slot 1 is the body carrying boosts.",
    [b("Amoonguss", ["clearsmog"]), b("Snorlax", ["tackle"])],
    [b("Gyarados", ["tackle"]), b("Seaking", ["tackle"], boosts={"atk": 2})],
    "clearsmog,1;tackle,0", "tackle,0;tackle,0",
    "Boost SideTwo:1 Attack: -2. Before the fix: NONE emitted for slot 1, because it "
    "cleared slot 0 -- which had nothing to clear")
run("(B2) CONTROL: Clear Smog aimed at slot 0, which carries the boosts.",
    [b("Amoonguss", ["clearsmog"]), b("Snorlax", ["tackle"])],
    [b("Gyarados", ["tackle"], boosts={"atk": 2}), b("Seaking", ["tackle"])],
    "clearsmog,0;tackle,0", "tackle,0;tackle,0",
    "Boost SideTwo:0 Attack: -2, identical before and after the fix")

print()
print("=" * 88)
print("C. HAZE: four slots, not two")
print("=" * 88)
run("(C1) every one of the four actives carries a DIFFERENT boost, so each cleared slot "
    "is identifiable by its magnitude alone; side one slot 0 Hazes.",
    [b("Koffing", ["haze"], boosts={"atk": 1}), b("Machamp", ["tackle"], boosts={"atk": 2})],
    [b("Golem", ["tackle"], boosts={"atk": 3}), b("Seaking", ["tackle"], boosts={"atk": 4})],
    "haze;tackle,0", "tackle,0;tackle,0",
    "four Boosts: SideOne:0 -1, SideOne:1 -2, SideTwo:0 -3, SideTwo:1 -4. Before the fix "
    "only the two slot-0 bodies were cleared (-1 and -3), and both slot-1 bodies kept theirs")
