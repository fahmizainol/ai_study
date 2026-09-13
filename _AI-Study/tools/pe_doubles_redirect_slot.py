"""Does an absorbing ability on the ATTACKER'S OWN SIDE draw the move, and where does
the boost land?

`boosts` was the one corpus metric that never moved across runs 1-3 (85.8% -> 86.4% ->
86.4%), and its buckets pointed at `ability stormdrain` 25/110 and `ability lightningrod`
15/44. I had told the user the fork "does not model redirection at all"; that was WRONG --
`generate_instructions.rs:2196 redirect_target` implements it thoroughly (Snipe Shot,
Propeller Tail / Stalwart, powder immunity, volatile-over-ability precedence). The faults
are narrower and there are two of them.

WHAT THIS FOUND (2026-09-13), from corpus rows rather than from reasoning:

  * DEFECT A, redirection scope. `redirect_target` set `target_side = nominal.side` and
    scanned ONLY that side for Lightning Rod / Storm Drain. In Showdown both register
    `onAnyRedirectTarget` (data/abilities.ts:2352, :4645) -- field-wide -- so a holder
    draws a matching move from ANY source, including its own ally's move aimed at a foe.
    Corpus battle 1 turn 0 is the shape: p1a Gengar aims Shock Wave at a foe and its
    partner p1b Seaking (Lightning Rod) pulls it in, for +1 SpA. Showdown gave spa +2
    that turn (two Electric moves drawn, one from the ally and one from a foe); the engine
    gave +1, and in the isolated battle 1 turn 3 -- a single ally-sourced Electric move --
    the engine produced NO boost at all. Follow Me / Rage Powder / Spotlight are the
    contrast: they register `onFoeRedirectTarget` (data/moves.ts), so they draw only a
    FOE's move, and scanning the target's side was already right for them.

  * DEFECT B, boost/heal side resolution. `get_instructions_from_boosts:1000` and
    `get_instructions_from_heal:1164` took the SLOT from `defender_position` (right) but
    the SIDE from `target.affected_side(attacker)` (wrong). Every absorbing handler
    hardcodes `target: MoveTarget::Opponent`, which resolves to the far side
    unconditionally -- correct in singles, where the absorber is always the opponent, and
    wrong in doubles whenever the absorber is the attacker's own ally. The signature is a
    boost on the MIRRORED SLOT OF THE WRONG SIDE: corpus battle 2 turn 0 has Blastoise
    (p2b) Surf into its ally Gastrodon's Storm Drain, Showdown boosts s2 Gastrodon, and
    the engine boosted s1 Gothitelle. Ten abilities share the convention -- Lightning Rod,
    Sap Sipper, Motor Drive, Wind Rider, Well-Baked Body, Storm Drain (boost) and Earth
    Eater, Water Absorb, Dry Skin, Volt Absorb (heal).

The two compose: A1 below only lands correctly if redirection finds the ally (A) AND the
boost is then sent to the ally's side (B). A2/A3/B3 are the controls that must not move.

The harness can only aim a move at a FOE slot (`action()` emits `id,<foe slot>`), which is
exactly the interesting case: the attacker aims at a foe and its own ally draws the move.

Whole instruction lists are printed rather than grepped, for the reason the Protect probe
learned: an ABSENT instruction is half of each finding.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions

# FOUR moves maximum. The engine indexes moves M0-M3, so a fifth entry is rejected with
# "Invalid move" -- which silently killed the A4 control the first time this probe ran. A
# control that does not execute is worse than no control, so the cap is respected here and
# a body that needs a different move gets its own list rather than a fifth slot.
MOVES = ("thunderbolt", "surf", "tackle", "followme")


def b(species, ability="none", spe=100, hp=400, types=("Normal",), moves=MOVES):
    """A plain body. Types stay Normal so nothing resists the Electric/Water probes;
    what makes a move absorbable is the MOVE's type, not the target's."""
    return dict(species=species, hp=hp, maxhp=400, types=list(types), fainted=False,
                ability=ability, item=None, status="none", volatiles=[], lastMove=None,
                boosts={}, weightkg=50,
                stats=dict(atk=200, **{"def": 200}, spa=200, spd=200, spe=spe),
                moves=[dict(id=m, pp=16) for m in moves])


def run(label, s1_bodies, s2_bodies, s1_action, s2_action, expect):
    s1 = dict(active=list(s1_bodies), bench=[], conditions={})
    s2 = dict(active=list(s2_bodies), bench=[], conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    print(f"\n{label}")
    print("   s1: " + " | ".join(f"{p['species']}({p['ability']})" for p in s1_bodies))
    print("   s2: " + " | ".join(f"{p['species']}({p['ability']})" for p in s2_bodies))
    print(f"   actions  s1={s1_action!r}  s2={s2_action!r}")
    print(f"   expected: {expect}")
    try:
        branches = generate_instructions(st, s1_action, s2_action)
    except Exception as exc:                      # a panic here is a finding, not a crash
        print(f"      RAISED {type(exc).__name__}: {exc}")
        return
    for i, br in enumerate(branches):
        lines = [ln.strip() for ln in str(br).splitlines() if ln.strip()]
        pct = next((ln for ln in lines if ln.lower().startswith("percentage")), "?")
        body = [ln for ln in lines
                if not ln.lower().startswith(("percentage", "instructions"))]
        print(f"      branch {i} ({pct}): {body if body else 'NO INSTRUCTIONS'}")


print("=" * 80)
print("A. DEFECT A -- is an absorbing ability on the ATTACKER'S OWN SIDE field-wide?")
print("=" * 80)
run("(A1) s1 slot 0 Thunderbolts a FOE; its own ally (s1 slot 1) has Lightning Rod."
    "\n     The corpus battle 1 turn 3 shape, and the case that needs BOTH fixes.",
    [b("Att0"), b("RodAlly", "lightningrod")], [b("Foe0"), b("Foe1")],
    "thunderbolt,0;none", "none;none",
    "no damage to s2; Boost SideOne:1 SpecialAttack +1 (NOT SideTwo:1)")
run("(A2) CONTROL: Lightning Rod on the FOE side, the case that already worked."
    "\n     Matches tests/test_doubles.rs:687, which must stay green.",
    [b("Att0"), b("Ally1")], [b("Foe0"), b("RodFoe", "lightningrod")],
    "thunderbolt,0;none", "none;none",
    "no damage to s2; Boost SideTwo:1 SpecialAttack +1 -- unchanged by this fix")
run("(A3) CONTROL: the ATTACKER itself holds Lightning Rod."
    "\n     Showdown's onTryHit guards `target !== source`, so it must not draw its own move.",
    [b("AttRod", "lightningrod"), b("Ally1")], [b("Foe0"), b("Foe1")],
    "thunderbolt,0;none", "none;none",
    "the foe IS damaged and the attacker gets NO boost")
run("(A4) CONTROL: Follow Me on the attacker's OWN side must not draw an ally's move."
    "\n     Follow Me is onFoeRedirectTarget -- foe-only -- unlike the abilities above.",
    [b("Att0"), b("Drawer")], [b("Foe0"), b("Foe1")],
    "tackle,0;followme", "none;none",
    "s2 slot 0 is damaged; the Follow Me user on s1 is NOT hit by its own ally")

print()
print("=" * 80)
print("B. DEFECT B -- which SIDE does the absorbed boost/heal land on?")
print("=" * 80)
run("(B1) SPREAD Water: s2 slot 1 Surfs; its own ally s2 slot 0 has Storm Drain."
    "\n     The corpus battle 2 turn 0 shape. Surf hits the ally, so this reaches the"
    "\n     per-target absorb path rather than redirection -- defect B alone.",
    [b("P1a"), b("P1b")], [b("DrainAlly", "stormdrain"), b("Surfer")],
    "none;none", "none;surf",
    "Boost SideTwo:0 SpecialAttack +1 -- before the fix it landed on SideOne")
run("(B2) the HEAL half: spread Water into an ally with Water Absorb."
    "\n     Water Absorb / Volt Absorb / Dry Skin / Earth Eater share the convention.",
    [b("P1a"), b("P1b")], [b("AbsorbAlly", "waterabsorb", hp=200), b("Surfer")],
    "none;none", "none;surf",
    "Heal SideTwo:0 -- before the fix the heal went to SideOne's mirrored slot")
run("(B3) CONTROL: single-target Water at a FOE holding Storm Drain.",
    [b("Att0"), b("Ally1")], [b("Foe0"), b("DrainFoe", "stormdrain")],
    "surf,1;none", "none;none",
    "Boost SideTwo:1 SpecialAttack +1 -- unchanged by this fix")
run("(B4) CONTROL: Helping Hand is MoveTarget::Ally and routes through the volatile"
    "\n     resolver, which this run deliberately did NOT change. It must be unmoved.",
    [b("Att0"), b("Helper", moves=("helpinghand", "tackle", "surf", "thunderbolt"))],
    [b("Foe0"), b("Foe1")],
    "none;helpinghand", "none;none",
    "the HELPINGHAND volatile still lands on SideOne, not across the field")
