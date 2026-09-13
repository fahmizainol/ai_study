"""Is the unenforced Choice lock (defect 4) the engine's fault, or my harness's?

Defect 4 was recorded as "doubles option generation does not enforce the Choice lock it is
given", on the evidence that the search proposed Choice-locked moves 35 times in the gen 5 run
and Showdown refused them. Reading the code first, before probing, moved the blame:

  * `move_is_selectable` (`genx/state.rs:500`) is the shared legality predicate for singles
    (`add_available_moves`) and doubles (`add_available_moves_doubles`). It checks `mv.disabled`,
    `mv.pp`, Encore, Bloodmoon / Gigaton Hammer, and Assault Vest / Taunt for status moves.
    It does NOT look at the held item, so no Choice item is consulted anywhere.
  * UPSTREAM poke-engine (`bf863be^2`) has no such check either -- PR #10 only refactored the
    predicate out of `add_available_moves`. So this is not a doubles regression, and the engine
    never claimed to DERIVE a Choice lock.
  * What the engine offers instead is `Move.disabled`, a serialized per-move field with its own
    `DisableMove` / `EnableMove` instructions, exposed to Python as `Move(id, pp, disabled)`.
    The caller is expected to fill it. `tools/foul_play_sidecar.py:173` -- the SINGLES bridge
    that plays live -- does exactly that, gated on whether the body is on the field.
  * `tools/pe_doubles_corpus.py`'s `mon()` builds `Move(id=..., pp=...)` and never passes it, so
    every move reached the engine with `disabled=False`. `pe_doubles_play.py` imports that same
    `mon`, and then uses Showdown's `disabled` flags only to JUDGE the result (`usable()`).

So the engine was handed "nothing is disabled" and correctly offered everything. `last_used_move`
carries Encore and the Bloodmoon / Gigaton Hammer repeat ban, not the Choice lock -- the comment
in `mon()` asserting otherwise is simply wrong, and this probe exists to settle it by experiment
rather than by my reading of two Rust functions.

WHAT IS ASKED. One doubles position, built twice, identical but for the flag:

    A  slot 0 holds four usable moves                      -> every move should be offered
    B  slot 0 holds the same four, three flagged disabled   -> only the locked move should be

The instrument is the MCTS root option list (`result.side_one`), because the binding exposes no
option generator of its own -- `mcts`, `id`, `generate_instructions` and `calculate_damage` are
the only pyfunctions. A tiny budget is enough: root options are enumerated before any search
happens, and this asks only WHICH options exist, never which is best.

If B's labels still mention the disabled moves, the flag is ignored and defect 4 is the engine's.
If they do not, defect 4 is mine, the fix belongs in `mon()`, and the engine has been carrying
blame for a field I never filled.

Every body is Normal-typed with explicit stats so no type chart enters the picture, and both
slots keep a living ally so no option disappears for want of a target.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import Move, Pokemon, Side, SideConditions, monte_carlo_tree_search

MOVES = ["tackle", "watergun", "ember", "vinewhip"]


def body(species, moves, disabled=()):
    """One body. `disabled` names the move ids to flag -- the field mon() never filled."""
    return Pokemon(
        id=species.lower(), level=100, types=("Normal", "typeless"),
        hp=400, maxhp=400, attack=200, defense=200, special_attack=200,
        special_defense=200, speed=100, ability="none", item="choiceband",
        status="none", weight_kg=50.0,
        moves=[Move(id=m, pp=16, disabled=(m in disabled)) for m in moves],
        last_used_move="move:0",
    )


def options_for(disabled):
    """Root option labels for side one, with `disabled` flagged on slot 0's moves."""
    s1 = Side(active_indices=["0", "1"],
              pokemon=[body("Blastoise", MOVES, disabled), body("Raichu", ["tackle"])],
              side_conditions=SideConditions())
    s2 = Side(active_indices=["0", "1"],
              pokemon=[body("Gengar", ["tackle"]), body("Gastrodon", ["tackle"])],
              side_conditions=SideConditions())
    result = monte_carlo_tree_search(State(side_one=s1, side_two=s2), duration_ms=60)
    return [str(o.move_choice) for o in result.side_one]


print("=" * 88)
print("Does Move(disabled=True) remove a move from DOUBLES option generation?")
print("=" * 88)
print(f"\nslot 0 knows: {', '.join(MOVES)}   (item choiceband, last_used_move move:0 = tackle)")

for label, disabled, expect in [
    ("(A) nothing flagged -- the state mon() actually builds today",
     (), "all four move ids appear; the Choice lock is invisible to the engine"),
    ("(B) the three non-locked moves flagged, as Showdown reports them",
     ("watergun", "ember", "vinewhip"), "only tackle appears among the moves"),
]:
    labels = options_for(disabled)
    seen = sorted({m for m in MOVES if any(m in x for x in labels)})
    print(f"\n{label}")
    print(f"   expected: {expect}")
    print(f"   flagged disabled: {disabled or '(none)'}")
    print(f"   move ids reachable in {len(labels)} root options: {seen}")
    for x in labels[:8]:
        print(f"       {x}")
    if len(labels) > 8:
        print(f"       ... {len(labels) - 8} more")
