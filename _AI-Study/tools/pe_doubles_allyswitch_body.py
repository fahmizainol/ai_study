"""After Ally Switch, WHICH BODY executes the partner's queued move?

Ally Switch was the top remaining corpus disagreement (4 of 11 turns, 36.4%) and stage 0's
`ally_switch_swaps_slots` passed throughout, so the fault needed a sharper instrument than
"did the slots swap". This is defect 7: a sub-action is bound to the SLOT rather than the
body, so when Ally Switch moves a body mid-turn the wrong Pokemon executes its move.

THE MEASUREMENT THAT SETTLED IT. Asking "which slot took damage" is not enough, because a
spread move excludes whichever slot the engine believes is acting -- so re-pointing the actor
merely moves which body is spared, and the output looks the same either way. Damage MAGNITUDE
is the independent channel: give the two bodies wildly different Special Attack and the number
names the attacker outright.

    slot 0 = Surfer,   SpA 400, uses Surf
    slot 1 = Switcher, SpA 100, uses Ally Switch

    with Ally Switch : Damage 27   <- the SWITCHER's SpA 100 -- slot-bound, the defect
    without it       : Damage 111  <- the SURFER's SpA 400   -- body-bound, correct

Same bodies, same move, one difference. 111 vs 27 is the defect stated in a single number.

WHY THE FIRST ATTEMPT AT THE FIX DID NOTHING. `Actor` gained a `body: PokemonIndex` and
`resolve_ordered_actors` re-resolved the slot from it -- and every figure stayed identical.
The reason is timing, not logic: `generate_instructions_from_move` applies its
`incoming_instructions` to `state` itself (`generate_instructions.rs:2436`), so at the point
where the actor loop set `state.acting_slot` the branch's `SwapActiveSlots` had NOT been
applied and the reverse lookup found the body exactly where it started. `choice_effects.rs`
does swap `active_indices` live while Ally Switch resolves, but that mutation is reversed
before the next actor is reached, so the swap only ever exists inside the produced branch --
which this probe confirms: `SwapActiveSlots(SideTwo)` is the FIRST instruction of every
branch, ahead of the damage. The lookup therefore has to run per-branch, with that branch's
instructions applied, not once per actor beforehand.

Targets are deliberately NOT re-resolved by body. The corpus shows a foe's single-target move
follows the SLOT through a swap -- Gengar's Shock Wave aimed at slot 0 hits whoever ends up in
slot 0 (battle 24 turn 3, battle 39 turn 1) -- which is the opposite rule from the actor's.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions


def b(species, moves, spa=200, hp=400, spe=100, types=("Normal",)):
    return dict(species=species, hp=hp, maxhp=hp, types=list(types), fainted=False,
                ability="none", item=None, status="none", volatiles=[], lastMove=None,
                boosts={}, weightkg=50,
                stats=dict(atk=200, **{"def": 200}, spa=spa, spd=200, spe=spe),
                moves=[dict(id=m, pp=16) for m in moves])


def run(label, s2_bodies, s2_action, expect):
    """Side one only uses Swords Dance, so nothing it does moves anyone's HP and every
    Damage line below is attributable to side two's Surf."""
    s1 = dict(active=[b("P1a", ["swordsdance"]), b("P1b", ["swordsdance"])],
              bench=[], conditions={})
    s2 = dict(active=list(s2_bodies), bench=[], conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    print(f"\n{label}")
    print("   side two: " + " | ".join(
        f"slot{i} {p['species']} spa={p['stats']['spa']}" for i, p in enumerate(s2_bodies)))
    print(f"   s2 action: {s2_action!r}")
    print(f"   expected: {expect}")
    try:
        branches = generate_instructions(st, "swordsdance;swordsdance", s2_action)
    except Exception as exc:                      # a panic here is a finding, not a crash
        print(f"      RAISED {type(exc).__name__}: {exc}")
        return
    br = max(branches, key=lambda x: x.percentage)
    body = [str(i) for i in br.instruction_list]
    print(f"      top branch: {body if body else 'NO INSTRUCTIONS'}")


SURFER = lambda: b("SurferHigh", ["surf", "allyswitch"], spa=400)
SWITCH = lambda: b("SwitcherLow", ["allyswitch", "surf"], spa=100)

print("=" * 84)
print("A. damage MAGNITUDE names the attacker, where the damaged slot alone cannot")
print("=" * 84)
run("(A1) slot 0 Surfs, slot 1 Ally Switches. The swap puts the Surfer in slot 1.",
    [SURFER(), SWITCH()], "surf;allyswitch",
    "~111 (the Surfer's SpA 400). Before the fix: 27, the SWITCHER's SpA 100")
run("(A2) CONTROL: identical bodies, no Ally Switch (slot 1 passes).",
    [SURFER(), SWITCH()], "surf;none",
    "~111 -- establishes what the Surfer's own SpA produces")
run("(A3) the mirror: slot 0 Ally Switches, slot 1 Surfs.",
    [SWITCH(), SURFER()], "allyswitch;surf",
    "~111 again: the Surfer still Surfs after being moved to slot 0")

print()
print("=" * 84)
print("B. which BODY is spared by its own spread move")
print("=" * 84)
run("(B1) slot 0 Surfs, slot 1 Ally Switches -- Surf is AllAdjacent, so it must hit the"
    "\n     ALLY it swapped past and never the user itself.",
    [SURFER(), SWITCH()], "surf;allyswitch",
    "Damage on the SWITCHER, not on the Surfer. Before the fix: Damage SideTwo:1, the Surfer")
run("(B2) CONTROL: no Ally Switch, so the ally in slot 1 takes it normally.",
    [SURFER(), SWITCH()], "surf;none",
    "Damage SideTwo:1 -- correct both before and after, since nothing moved")
