"""Can a doubles side end up with NO legal actions at all, and crash the search?

Run 9's roster re-run panicked once at `src/mcts.rs:135:57`:

    index out of bounds: the len is 0 but the index is 0
    let s1_move = &self.s1_options.as_ref().unwrap()[s1_move_index].move_choice;

So a side's root option list was EMPTY. Two candidate sources were ruled out by reading:

  * `slot_options_doubles` (`genx/state.rs:1626`) cannot return an empty per-slot list -- it ends
    with `if options.is_empty() { options.push(MoveChoice::None); }` (`:1680`). An earlier note of
    mine claimed this guard was absent; that was wrong, and it was wrong because I grepped for
    `push(MoveChoice::None)` with `head -20` and the doubles hit fell outside the truncation. Run
    4's lesson -- grep before declaring a mechanic absent -- applies to truncated greps too.
  * `replacement_options_doubles` (`:1589`) survives scarcity: with both slots needing a
    replacement and one bench mon available, `fill = 1` keeps `(Switch, None)` and
    `(None, Switch)`.

What is NOT guarded is the FILTER in `combine_slot_options` (`:1790`). It builds the cartesian
product of the per-slot lists and then drops every combination where two slots switch to the same
body (`has_duplicate_switch`, `:1819`) -- with no fallback if that empties the list:

    combos.into_iter().filter(|combo| !Self::has_duplicate_switch(combo)) ... .collect()

So if BOTH slots' only option is a switch, and only ONE bench body is available to switch to, the
single combination `(Switch(b), Switch(b))` is a duplicate, it is filtered, and the side's option
list comes back empty. A slot's options reduce to switches alone when no move is selectable --
`move_is_selectable` rejects `pp <= 0` and `disabled` -- so PP exhaustion is the ordinary route in,
and the engine's own Choice-lock disabling is another. Singles cannot express this at all: it has
no pairs, so it has no duplicate-switch filter.

That also explains why the panic appeared in the roster run and in none of the earlier ones: it
needs a late, depleted position (16491 mean visits against 3762) and a small team that reaches a
single-bench-mon endgame (size-4 teams are 158 of the 171).

WHAT IS ASKED. Three cells, varying only what keeps the option list non-empty:

    (A) two slots with no usable moves, ONE bench body      -> predicted EMPTY -> panic
    (B) two slots with no usable moves, TWO bench bodies    -> two distinct switches, fine
    (C) one slot keeps a usable move,   ONE bench body      -> that move survives the filter, fine

`monte_carlo_tree_search` is the instrument because the panic lives in the search, and because the
binding exposes no option generator of its own. A budget of a few ms is plenty: root options are
enumerated before any search happens. A panic here is the FINDING, not a failure, so each cell
catches `BaseException` -- pyo3 surfaces a Rust panic as `PanicException`, which does NOT subclass
`Exception` and would otherwise kill the probe.

Every body is Normal-typed with explicit stats; "no usable move" is spelled as `pp=0` rather than
as a disabled flag, so the cell does not depend on run 9's whitelist fix being present.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
State = _ns["State"]
from poke_engine import Move, Pokemon, Side, SideConditions, monte_carlo_tree_search


def body(species, moves, pp=16):
    return Pokemon(
        id=species.lower(), level=100, types=("Normal", "typeless"),
        hp=400, maxhp=400, attack=200, defense=200, special_attack=200,
        special_defense=200, speed=100, ability="none", item="none",
        status="none", weight_kg=50.0,
        moves=[Move(id=m, pp=pp, disabled=False) for m in moves],
    )


def run(label, side_one_party, expect):
    s1 = Side(active_indices=["0", "1"], pokemon=side_one_party,
              side_conditions=SideConditions())
    s2 = Side(active_indices=["0", "1"],
              pokemon=[body("Gengar", ["tackle"]), body("Gastrodon", ["tackle"]),
                       body("Snorlax", ["tackle"])],
              side_conditions=SideConditions())
    print(f"\n{label}")
    print(f"   side one: {len(side_one_party)} bodies, "
          f"actives = {side_one_party[0].id}/{side_one_party[1].id}")
    print(f"   expected: {expect}")
    try:
        result = monte_carlo_tree_search(State(side_one=s1, side_two=s2), duration_ms=40)
    except BaseException as exc:                  # PanicException is not an Exception
        print(f"      PANICKED: {type(exc).__name__}: {str(exc).splitlines()[0][:90]}")
        return
    opts = [str(o.move_choice) for o in result.side_one]
    print(f"      {len(opts)} root options for side one: {opts[:6]}"
          + (f" ... +{len(opts) - 6}" if len(opts) > 6 else ""))


print("=" * 88)
print("Does the duplicate-switch filter leave a doubles side with zero legal actions?")
print("=" * 88)
print("\n'No usable move' is spelled pp=0, so move_is_selectable rejects every move and the")
print("slot's options reduce to switches alone.")

run("(A) both actives out of PP, exactly ONE bench body -- the predicted crash.",
    [body("Blastoise", ["tackle"], pp=0), body("Raichu", ["swift"], pp=0),
     body("Vileplume", ["tackle"])],
    "both slots offer only Switch(Vileplume); the one combination is a duplicate, is "
    "filtered, and the list is EMPTY -> index out of bounds at mcts.rs:135")
run("(B) CONTROL: same, but TWO bench bodies -- distinct switches exist.",
    [body("Blastoise", ["tackle"], pp=0), body("Raichu", ["swift"], pp=0),
     body("Vileplume", ["tackle"]), body("Mienshao", ["tackle"])],
    "two distinct switch combinations survive the filter; no panic")
run("(C) CONTROL: ONE bench body, but slot 0 keeps a usable move.",
    [body("Blastoise", ["tackle"], pp=16), body("Raichu", ["swift"], pp=0),
     body("Vileplume", ["tackle"])],
    "slot 0 contributes a move, so (move, switch) survives the filter; no panic")
