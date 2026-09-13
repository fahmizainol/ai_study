"""Does Protect block the move aimed at the body that used it, in every slot?

`protect` is the top remaining corpus disagreement (26 of 73 turns, 35.6%) and it did not
move at all when defects 15 and 5 were fixed, so it is an independent fault. Corpus battle
33 turn 8 is the shape to reproduce: side two Protects with BOTH bodies, side one aims one
move at each, and Showdown leaves both untouched while poke-engine damages the slot-1 body
only. That asymmetry -- slot 0 honoured, slot 1 missed -- is what this enumerates.

WHAT THIS FOUND (2026-09-13). Three separate faults, and neither of my two starting
hypotheses -- a wrong slot on the WRITE, or a wrong body on the READ -- was the main one:

  * DEFECT 16, the one that explains battle 33. `volatile_status_can_be_applied`
    (`genx/state.rs:760`) gates `PROTECT` on `first_move`, fed from `attacker_choice
    .first_move` at `:653`. `first_move` is per-SIDE, so at most one sub-action a side
    carries it and **only the first-ACTING body on a side can Protect** -- the second one's
    volatile is dropped silently and that body takes the hit. Section E proves it is the
    first-acting body and not slot 0 (E1 makes slot 1 faster and slot 1 wins), that the gate
    is per-side rather than global (E2/E3: being outsped by both opponents changes nothing),
    and that a lone Protect always works (E4). Section D5 is the control that rules out "one
    self-action per side": two Swords Dances both land. Showdown's real rule is
    `onTry: !!this.queue.willAct()` -- Protect fails only when nothing is left to act -- so
    `first_move` is a singles proxy that is quietly destructive in doubles.

  * DEFECT 17. The end-of-turn protect cleanup scanned `side.get_active()` and hardcoded
    slot 0 in its `RemoveVolatileStatus`, so a protect volatile on slot 1 was never cleared
    and persisted for the rest of the battle -- permanently immune in the search's model.
    Visible here as the missing `RemoveVolatileStatus` in E1/E4 against the slot-0 cases.

  * DEFECT 5's mechanism, applied to a per-body volatile. `before_move:1842` checks the
    NOMINAL target and calls `remove_effects_for_protect()`, cancelling the WHOLE move.
    Scenarios (4)(5)(6) measure all three symptoms: slot-0 Protect + Earthquake does nothing
    at all, slot-1 Protect leaves the Protecting body damaged along with everyone else, and a
    Protecting ALLY is damaged because `defending_side` can never see it.

Printing whole instruction lists rather than grepping for Damage: a wrong regex would hide
exactly the instruction that explains the bug -- and here the *absent* RemoveVolatileStatus
was half the finding.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions


def b(species, moves, types=("Normal",), ability="none"):
    return dict(species=species, hp=400, maxhp=400, types=list(types), fainted=False,
                ability=ability, item=None, status="none", volatiles=[], lastMove=None,
                boosts={}, weightkg=50,
                stats=dict(atk=200, **{"def": 200}, spa=200, spd=200, spe=100),
                moves=[dict(id=m, pp=16) for m in moves])


ATT = ["tackle", "earthquake", "protect"]


def run(label, s1_action, s2_action, expect):
    """One joint action. `expect` is prose -- the point is to read the instructions."""
    s1 = dict(active=[b("Att0", ATT), b("Att1", ATT)], bench=[], conditions={})
    s2 = dict(active=[b("Def0", ATT), b("Def1", ATT)], bench=[], conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    print(f"\n{label}")
    print(f"   s1={s1_action!r}  s2={s2_action!r}")
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


print("=" * 78)
print("A. single-target moves into Protect, one aimed at each slot")
print("=" * 78)
run("(1) BOTH defenders Protect; s1 aims one move at each (corpus battle 33 turn 8)",
    "tackle,0;tackle,1", "protect;protect",
    "no damage to either defender")
run("(2) only SLOT 0 Protects", "tackle,0;tackle,1", "protect;none",
    "slot 1 damaged, slot 0 spared")
run("(3) only SLOT 1 Protects", "tackle,0;tackle,1", "none;protect",
    "slot 0 damaged, slot 1 spared")

print()
print("=" * 78)
print("B. a spread move into Protect -- the defect-5 shape, per position")
print("=" * 78)
run("(4) slot 0 Protects, Earthquake from s1 slot 0",
    "earthquake,0;none", "protect;none",
    "slot 1 AND the attacker's ally damaged; slot 0 spared (NOT a whole-move cancel)")
run("(5) slot 1 Protects, Earthquake from s1 slot 0",
    "earthquake,0;none", "none;protect",
    "slot 0 AND the attacker's ally damaged; slot 1 spared")
run("(6) the ATTACKER'S ALLY Protects, Earthquake from s1 slot 0",
    "earthquake,0;protect", "none;none",
    "both foes damaged; the ally spared -- unreachable via `defending_side`")


# ---------------------------------------------------------------------------------------
# Sections C-E: what actually explains "only one Protect landed". Speeds matter here, so
# these build their own bodies rather than reusing `run` above.
# ---------------------------------------------------------------------------------------

def bs(species, spe, moves=("tackle", "protect", "detect", "swordsdance", "earthquake")):
    return dict(species=species, hp=400, maxhp=400, types=["Normal"], fainted=False,
                ability="none", item=None, status="none", volatiles=[], lastMove=None,
                boosts={}, weightkg=50,
                stats=dict(atk=200, **{"def": 200}, spa=200, spd=200, spe=spe),
                moves=[dict(id=m, pp=16) for m in moves])


def run_spe(label, s1_action, s2_action, att=(120, 110), dfn=(100, 90), expect=""):
    s1 = dict(active=[bs("Att0", att[0]), bs("Att1", att[1])], bench=[], conditions={})
    s2 = dict(active=[bs("Def0", dfn[0]), bs("Def1", dfn[1])], bench=[], conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    print(f"\n{label}")
    print(f"   s1={s1_action!r} s2={s2_action!r}   Att {att[0]}/{att[1]}  Def {dfn[0]}/{dfn[1]}")
    if expect:
        print(f"   expected: {expect}")
    try:
        for i, br in enumerate(generate_instructions(st, s1_action, s2_action)):
            print(f"      {i}: {str(br).strip()}")
    except Exception as exc:
        print(f"      RAISED {type(exc).__name__}: {exc}")


print()
print("=" * 78)
print("C. was 'only one Protect applies' a SPEED-TIE artifact?  (no -- C2 has no tie)")
print("=" * 78)
print("   Labels below describe what these showed BEFORE the fix; all now show both.")
run_spe("(C1) both Protect, IDENTICAL speed -- was: a tie branching over who acts first,"
        " each branch protecting only that body",
        "tackle,0;tackle,1", "protect;protect", dfn=(100, 100),
        expect="both protected, in either tie order")
run_spe("(C2) both Protect, DISTINCT speeds -- was: no tie at all and still only one landed,"
        " which is what killed the speed-tie theory",
        "tackle,0;tackle,1", "protect;protect", dfn=(100, 90),
        expect="both protected, no damage")
run_spe("(C3) both Protect, nothing aimed at them -- isolates it from the damage path",
        "none;none", "protect;protect", dfn=(100, 90),
        expect="two ApplyVolatileStatus lines; before the fix slot 1's was missing entirely")

print()
print("=" * 78)
print("D. same volatile deduped per side, or one self-action per side?  (neither)")
print("=" * 78)
run_spe("(D1) both Protect -- same volatile", "none;none", "protect;protect")
run_spe("(D2) Protect + DETECT -- a different volatile, so not same-volatile dedup",
        "none;none", "protect;detect")
run_spe("(D5) both Swords Dance -- CONTROL: a self boost, not a volatile",
        "none;none", "swordsdance;swordsdance",
        expect="BOTH bodies boost -- so joint resolution runs both sub-actions fine")

print()
print("=" * 78)
print("E. the `first_move` gate (genx/state.rs:760) -- it is ORDER, not slot")
print("=" * 78)
run_spe("(E1) slot 1 is the FASTER body", "none;none", "protect;protect", dfn=(90, 100),
        expect="if the gate is first_move, SLOT 1's Protect lands and slot 0's is dropped")
run_spe("(E2) both defenders outsped by both attackers", "tackle,0;tackle,1",
        "protect;protect", att=(300, 290), dfn=(100, 90),
        expect="the faster DEFENDER still protects -- so the gate is per-side, not global")
run_spe("(E3) same, nothing aimed at them", "none;none", "protect;protect",
        att=(300, 290), dfn=(100, 90))
run_spe("(E4) only slot 1 Protects, and it is the slower body", "none;none", "none;protect",
        att=(300, 290), dfn=(100, 90),
        expect="lands -- a lone Protect always works; and note the ABSENT "
               "RemoveVolatileStatus, which is defect 17")
