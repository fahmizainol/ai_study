"""When a SLOT 1 body uses a Choice move, whose moves does the engine lock?

`tools/pe_doubles_choicelock.py` settled that defect 4's illegal proposals were my own
translator's fault -- `Move.disabled` was never filled. Reading the engine to confirm that
turned up the other half, which is real and is the engine's:

    src/genx/items.rs:260  get_choice_move_disable_instructions(pkmn, side_ref, move_name)
        ...
        moves_to_disable.push(Instruction::DisableMove(DisableMoveInstruction::new(
            *side_ref,
            0, // FIXME(doubles): slot (no State access in this fn)
            iter.pokemon_move_index,
        )));

So the engine DOES model a Choice lock -- it disables the holder's other moves as the move is
used -- but it stamps the instruction with a hard-coded slot 0, because the helper takes a
`&Pokemon` and a `&SideReference` and has no `State` to ask which slot is acting. Three
doubles-reachable call sites pass through it: `genx/items.rs:761` (the CHOICEBAND / CHOICESPECS
/ CHOICESCARF arm), `genx/choice_effects.rs:1005`, and `genx/abilities.rs:673`.

This matters in two directions at once, and both are asked below:

    slot 1 uses a Choice move -> slot 0's moves are disabled instead of slot 1's, so the
                                 partner loses three moves it still has, and the Choice user
                                 keeps four it should not
    slot 0 uses a Choice move -> correct by coincidence, which is why singles never sees this

WHY THE MEASURED INSTRUMENTS CANNOT SEE IT. The corpus projects damage, boosts and statuses --
never move availability -- and the play harness rebuilds the root state from Showdown every
turn, so a wrong lock inside the tree never reaches a submitted action. That is exactly the
reasoning that left `re_enable_disabled_moves`'s identical slot-0 bug recorded and unfixed. But
`DisableMove` IS an instruction, so `generate_instructions` can be asked directly, which is what
this probe does: no projection, no metric, just the emitted instruction list.

Note this defect was ALREADY reachable before the `Move.disabled` fix -- the engine sets the
flag itself, so filling the field did not activate anything new. It makes the flag common rather
than rare.

Both bodies hold a Choice Band and know four moves each, all Normal-typed with explicit stats so
no type chart enters the picture.

HOW TO READ THE OUTPUT -- and a limit of this probe that I got wrong when writing it. I designed
it to read the slot off the instruction, but `DisableMove`'s Display prints only
`DisableMove SideOne: M1`: the slot is carried in the instruction and used when it is applied
(`state.rs:2149` -> `get_active_slot(slot)`), but never printed. So the slot number cannot be
read here at all.

What settles it instead is the COUNT and the indices. Both bodies use their own M0, so if each
locked its own body the list would be six entries, `M1 M2 M3` twice over. Four appear -- and one
of them is `M0`, the move that was just used. No body should ever have its own used move
disabled. It happens because the second actor writes onto the FIRST body, where M0 was used and
left enabled, and then disables it for not being the second actor's move. That stray `M0` is the
evidence of cross-body writing; the three-versus-six count corroborates it.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
State = _ns["State"]
from poke_engine import Move, Pokemon, Side, SideConditions, generate_instructions

SLOT0_MOVES = ["tackle", "watergun", "ember", "vinewhip"]
SLOT1_MOVES = ["swift", "gust", "bubble", "spark"]


def body(species, moves, item="choiceband"):
    return Pokemon(
        id=species.lower(), level=100, types=("Normal", "typeless"),
        hp=400, maxhp=400, attack=200, defense=200, special_attack=200,
        special_defense=200, speed=100, ability="none", item=item,
        status="none", weight_kg=50.0,
        moves=[Move(id=m, pp=16, disabled=False) for m in moves],
    )


def run(label, s1_action, expect):
    s1 = Side(active_indices=["0", "1"],
              pokemon=[body("Blastoise", SLOT0_MOVES), body("Raichu", SLOT1_MOVES)],
              side_conditions=SideConditions())
    s2 = Side(active_indices=["0", "1"],
              pokemon=[body("Gengar", ["tackle"], item="none"),
                       body("Gastrodon", ["tackle"], item="none")],
              side_conditions=SideConditions())
    state = State(side_one=s1, side_two=s2)
    print(f"\n{label}")
    print(f"   side one plays {s1_action!r}")
    print(f"   expected: {expect}")
    branches = generate_instructions(state, s1_action, "tackle,0;tackle,0")
    br = max(branches, key=lambda x: x.percentage)
    disables = [str(i) for i in br.instruction_list if "DisableMove" in str(i)]
    print(f"      DisableMove instructions ({len(disables)}):")
    for d in disables or ["       (none emitted)"]:
        print(f"       {d}")


print("=" * 88)
print("Which slot does a Choice lock land on? (src/genx/items.rs:260, the FIXME)")
print("=" * 88)
print(f"\nslot 0 Blastoise knows {', '.join(SLOT0_MOVES)}")
print(f"slot 1 Raichu     knows {', '.join(SLOT1_MOVES)}")
print("both hold a Choice Band")

run("(A) SLOT 1 uses its Choice move. The defect: the lock is stamped on slot 0.",
    "tackle,0;swift",
    "correct would be three DisableMove on SideOne:1 (Raichu's gust/bubble/spark). "
    "The FIXME predicts SideOne:0 instead -- Blastoise loses moves it still has")
run("(B) SLOT 0 uses its Choice move -- the singles-shaped case, correct by coincidence.",
    "watergun,0;swift",
    "three DisableMove on SideOne:0, which is right because slot 0 IS the actor here "
    "(slot 1 also acts, so its own lock is stamped on slot 0 too -- both land in one place)")
