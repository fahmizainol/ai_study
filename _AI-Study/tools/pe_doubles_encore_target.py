"""Encore swaps the move but not its TARGET, so a foe-targeting move hit its own user.

This is defect 3's mechanism -- `get_two_actives called with the same position`, 19 of the 23
engine panics in run 9's roster re-run and the single largest reason a decision was not the
search's. It took four discarded hypotheses to find, so the route is recorded with the answer.

WHAT IT IS NOT. Each of these was committed to and then refuted:

  * `get_instructions_from_drag`'s pool comes from `get_alive_pkmn_indices`, which excludes only
    `active_indices[0]` -- so in doubles it includes the body standing in slot 1, and dragging it
    in would duplicate the indices. A REAL latent defect, but not this one: **0 of 183
    gen5doublesou teams carry a drag move** (positive control on the same scan: Protect 174,
    Fake Out 117), so no team can use one.
  * Self-redirection: `redirect_target` skips the attacker outright (`if pos == attacker_pos {
    continue; }`), citing Showdown's `target !== source`.
  * A stale default: `State::default()` and the binding both set `target_position` to
    `(SideTwo, 0)` -- but the assert fires with `left: 1, right: 1` as readily as `0, 0`, and the
    `:5276` fallback is `.opposing()`, which correctly flips the side.
  * State corruption: the enriched assert prints `active_indices=[P0, P1]`. The indices are
    healthy; the party indices matched because attacker and target were THE SAME POSITION.

WHAT IT IS. `generate_instructions_from_move` (`genx/generate_instructions.rs:2504`) holds the
only whole-`Choice` replacement in `src/genx/`:

    if choice.move_index != last_used_move {
        *choice = MOVES.get(&...moves[&last_used_move].id).unwrap().clone();
        choice.move_index = last_used_move;
    }

An Encore-locked body's choice is swapped for the encored move -- `target` class included -- while
`state.target_position` still holds what the per-actor setup (`:5276`) computed for the move the
player actually chose. Choosing RECOVER (`MoveTarget::User`, whose nominal target correctly IS the
user's own position) while locked into EARTH POWER (`MoveTarget::Opponent`) therefore leaves a
damaging foe-move aimed at its own user, and the damage path calls `get_two_actives(attacker,
attacker)`. Found by instrumenting the engine rather than reading it; the decisive output was:

    DBG setup self-target: move=RECOVER   acting_slot=1 tp=SideTwo slot 1 lum=Move(M3)
    DBG same-body damage:  move=EARTHPOWER target_class=Opponent attacker=SideTwo slot 1
                                                                  target=SideTwo slot 1

Singles never needed a refresh: its `defender_position` ignores `target_position` and returns the
opposing slot 0, so a substituted move always targeted the foe. An unfinished doubles conversion,
the same family as defects 6, 14, 20, 23 and 26.

ADJUDICATED AGAINST SHOWDOWN, not assumed. `sim/battle-actions.ts:228` runs the `OverrideAction`
event and then **re-derives the target for the replacement move**:

    target = this.battle.getRandomTarget(pokemon, baseMove);

So re-deriving is correct behaviour. The fix uses `legal_targets` -- the same primitive option
generation uses -- and takes the first living target where Showdown picks at RANDOM among them.
That deterministic choice is a recorded simplification, like `redirect_target`'s speed-tie note.

WHY A PROBE AND NOT THE CORPUS. Encore, Recover and Earth Power appear **0 times** in the corpus
pool and Encore in no stage-0 case, so a byte-identical corpus is a no-leak control and NOT
evidence the fix works. The evidence is this probe plus 12 captured real positions (panicking 5/5
before, 0/6 after). The play pool is where it lives: 33 of 183 teams carry Encore and all 33 also
carry a self-targeting move.

A TRAP THIS PROBE HIT FIRST, worth keeping: `pe_doubles_corpus.py`'s `mon()` **validates**
volatiles against its `VOLATILE` map and then never passes them to the engine -- its `Pokemon(...)`
call has no `volatile_statuses` argument at all. The first version of this probe set
`volatiles=["encore"]` through `mon()` and every cell came back identical, because the volatile was
silently dropped. Bodies are therefore constructed directly here, as
`tools/pe_doubles_choicelock.py` does. The lock needs no two-turn setup: the ENCORE volatile plus a
`last_used_move` pointing at a different index is the whole precondition, so one
`generate_instructions` call reproduces it with no search and no PRNG.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
State = _ns["State"]
from poke_engine import Move, Pokemon, Side, SideConditions, generate_instructions

GASTRODON = ["scald", "recover", "icywind", "earthpower"]   # M0 M1 M2 M3


def body(species, moves, hp=400, volatiles=(), last="move:none"):
    return Pokemon(
        id=species.lower(), level=100, types=("Normal", "typeless"),
        hp=hp, maxhp=400, attack=200, defense=200, special_attack=200,
        special_defense=200, speed=100, ability="none", item="none",
        status="none", weight_kg=50.0,
        moves=[Move(id=m, pp=16, disabled=False) for m in moves],
        volatile_statuses=set(volatiles), last_used_move=last,
    )


def run(label, volatiles, last, s2_action, expect, foe1_hp=400):
    """Side two slot 1 is the encored body; slot 0 is a fainted, unreplaceable partner.

    Side one's bodies use Swords Dance so they neither block nor damage anything: the only
    instructions that matter come from side two, and Earth Power's damage is visible.
    """
    s1 = Side(active_indices=["0", "1"],
              pokemon=[body("Gengar", ["swordsdance"]),
                       body("Raichu", ["swordsdance"], hp=foe1_hp)],
              side_conditions=SideConditions())
    s2 = Side(active_indices=["0", "1"],
              pokemon=[body("Weavile", ["icepunch"], hp=0),
                       body("Gastrodon", GASTRODON, volatiles=volatiles, last=last)],
              side_conditions=SideConditions())
    print(f"\n{label}")
    print(f"   slot1 volatiles={sorted(volatiles) or '(none)'}  last_used_move={last!r}  "
          f"chooses {s2_action!r}"
          + ("   [foe slot 1 is FAINTED]" if foe1_hp == 0 else ""))
    print(f"   expected: {expect}")
    try:
        branches = generate_instructions(State(side_one=s1, side_two=s2),
                                         "swordsdance;swordsdance", f"none;{s2_action}")
    except BaseException as exc:                 # a panic here IS the finding
        print(f"      PANICKED {type(exc).__name__}: {str(exc).splitlines()[0][:110]}")
        return
    br = max(branches, key=lambda x: x.percentage)
    print(f"      top branch {br.percentage:.1f}% of {len(branches)}:")
    for ins in br.instruction_list:
        print("       ", ins)


print("=" * 88)
print("Does an Encore-substituted move keep the target of the move it replaced?")
print("=" * 88)
print(f"\nGastrodon (side two slot 1) knows: {', '.join(GASTRODON)}")
print("Its partner in slot 0 is fainted, so side two has exactly one body that can act.")

run("(A) THE DEFECT: locked into EARTH POWER (M3) while choosing RECOVER (M1).",
    {"encore"}, "move:3", "recover",
    "Earth Power is swapped in and its target re-derived, so Damage lands on SIDE ONE. "
    "Before the fix target_position still pointed at Gastrodon and the engine panicked with "
    "'get_two_actives called with the same position'")
run("(B) CONTROL: same last_used_move, NOT encored -- nothing is substituted.",
    set(), "move:3", "recover",
    "Recover resolves as Recover: a Heal on SideTwo slot 1 and no damage anywhere")
run("(C) CONTROL: encored into EARTH POWER and choosing it -- substitution is a no-op.",
    {"encore"}, "move:3", "earthpower,0",
    "Earth Power resolves against the chosen foe. Should match (A): the lock must not change "
    "WHERE the move lands")
run("(D) CONTROL: the mirror direction -- locked into RECOVER while choosing a foe move.",
    {"encore"}, "move:1", "earthpower,0",
    "Recover is swapped in and targets the user: a Heal on SideTwo slot 1, no damage. This "
    "direction never panicked, because a self-target is legal for a User-class move")
run("(E) WHY `legal_targets` AND NOT `.opposing()`: the directly-opposite foe is fainted.",
    {"encore"}, "move:3", "recover",
    "Earth Power must hit the LIVING foe in SideOne slot 0. The `.opposing()` default that "
    "the per-actor setup uses would aim at SideOne slot 1, which is a corpse",
    foe1_hp=0)
