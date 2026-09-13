"""Where does a status land, whose immunity is consulted, and whose berry is eaten?

`get_instructions_from_status_effects` (`genx/generate_instructions.rs:815`) resolves the
target SLOT correctly (`def_pos.slot`) and then ignores it three times over:

    let target_side_active = target_side.active_indices[0];   // slot 0's party index
    let target_pkmn = target_side.get_active();               // slot 0's body

so the status is written to slot 0 and reported as slot 0's party index. Those two agree with
each other, which is why this is a wrong-body bug rather than a state/instruction mismatch --
EXCEPT on the Lum / Chesto Berry path, which emits `ChangeItem` with the correct `target_slot`
while consuming slot 0's item. That one genuinely breaks the apply/reverse invariant.

A CORRECTION this probe exists to pin down. An earlier note in SEARCH-BOARDS.md said "the
immunity check reads the RIGHT target while the write goes to the wrong one, so Thunder Wave
can paralyze a Ground type". That is wrong twice. `immune_to_status` (`:732`) takes no slot at
all -- both `target_pkmn` and `attacking_pkmn` are `get_active_immutable()`, i.e. slot 0 -- so
the immunity check reads the wrong body too. And Ground's immunity to Thunder Wave is nowhere
in that function: in gen 5 its PARALYZE arm is only `ability == LIMBER` (the Electric-type
immunity is gen 6+). Section C asks the engine what it actually does about a Ground target
instead of assuming an answer either way.

Why this cannot be priced by the corpus: `showdown_doubles_corpus.js`'s curated POOL contains
no status-inflicting move at all (Tackle / Earthquake / Protect / Swords Dance / Surf / Aqua
Jet / Shock Wave / Swift / Calm Mind / Follow Me / Helping Hand / Rage Powder / Vine Whip /
Wide Guard / Quick Guard / Ally Switch / Mach Punch), so across 456 turns the only status
transition is `none -> fnt`, which is fainting. Regenerating the corpus with status moves would
re-baseline every figure in the document, so the measurable home for this defect is stage 0,
whose per-case verdicts cannot be disturbed by adding a projection.

Whole instruction lists are printed, never grepped: in B2 and C1 the finding is an instruction
that is ABSENT.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions


def b(species, moves=("thunderwave", "recover"), status="none", types=("Psychic",), item=None,
      spe=100):
    """Psychic by default so Thunder Wave has no type argument to make -- the point is the
    SLOT, and a Ground type would confound it. Section C overrides `types` deliberately.

    `spe` matters more than it looks. The first version of this probe gave every body spe=100,
    which produced a SPEED TIE and split every scenario into two 50/50 branches
    (`generate_instructions.rs:4717`). That made the Lum Berry case read as though the engine
    modelled the berry probabilistically, which it does not: side one is given a strictly
    higher speed below and each scenario collapses to a single 100% branch. A tie is a
    confound here, not a mechanic."""
    return dict(species=species, hp=300, maxhp=300, types=list(types), fainted=False,
                ability="none", item=item, status=status, volatiles=[], lastMove=None,
                boosts={}, weightkg=50,
                stats=dict(atk=200, **{"def": 200}, spa=250, spd=200, spe=spe),
                moves=[dict(id=m, pp=16) for m in moves])


def run(label, s2_bodies, action="thunderwave,1", expect=""):
    """Side one always attacks; side two holds the two bodies under test. Side one is strictly
    faster so no speed tie splits the output -- see the note in `b`."""
    s1 = dict(active=[b("Togekiss", spe=150), b("Togekiss2", spe=150)], bench=[], conditions={})
    s2 = dict(active=list(s2_bodies), bench=[], conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    print(f"\n{label}")
    print("   side two: " + " | ".join(
        f"slot {i} {p['species']} types={'/'.join(p['types'])} status={p['status']} "
        f"item={p['item'] or '-'}" for i, p in enumerate(s2_bodies)))
    print(f"   s1 action: {action!r}")
    if expect:
        print(f"   expected: {expect}")
    try:
        branches = generate_instructions(st, f"{action};none", "recover,0;none")
    except Exception as exc:                      # a panic here is a finding, not a crash
        print(f"      RAISED {type(exc).__name__}: {exc}")
        return
    for i, br in enumerate(branches):
        lines = [ln.strip() for ln in str(br).splitlines() if ln.strip()]
        body = [ln for ln in lines
                if not ln.lower().startswith(("percentage", "instructions"))]
        print(f"      branch {i}: {body if body else 'NO INSTRUCTIONS'}")


print("=" * 82)
print("A. which BODY gets the status -- party order is P0 = slot 0, P1 = slot 1")
print("=" * 82)
run("(A1) aimed at SLOT 0 -- the case that was always right",
    [b("Latios"), b("Cresselia")], "thunderwave,0",
    "ChangeStatus SideTwo-P0 (Latios)")
run("(A2) aimed at SLOT 1 -- the defect: it still lands on P0",
    [b("Latios"), b("Cresselia")], "thunderwave,1",
    "ChangeStatus SideTwo-P1 (Cresselia); before the fix it says P0")

print()
print("=" * 82)
print("B. WHOSE immunity is consulted, and whose berry is eaten")
print("=" * 82)
run("(B1) slot 0 is ALREADY paralyzed, and slot 1 is aimed at."
    "\n     `immune_to_status` reads slot 0, so an already-statused slot 0 makes the engine"
    "\n     think the move is pointless and emit nothing at all.",
    [b("Latios", status="par"), b("Cresselia")], "thunderwave,1",
    "slot 1 paralyzed; before the fix there are NO INSTRUCTIONS")
run("(B2) slot 0 holds a LUM BERRY and slot 1 is aimed at."
    "\n     The ChangeItem path emits the CORRECT target_slot while consuming slot 0's item:"
    "\n     the apply/reverse divergence, and the only place this defect is more than"
    "\n     a wrong body.",
    [b("Latios", item="lumberry"), b("Cresselia")], "thunderwave,1",
    "slot 1 paralyzed and NO berry consumed; before the fix slot 0's berry goes")
run("(B3) slot 1 holds the Lum Berry and is aimed at -- the berry SHOULD be eaten",
    [b("Latios"), b("Cresselia", item="lumberry")], "thunderwave,1",
    "ChangeItem on SideTwo:1 and no status")

print()
print("=" * 82)
print("C. the Ground question -- asked, not assumed")
print("=" * 82)
run("(C1) slot 1 is GROUND and is aimed at. Ground is immune to Thunder Wave in the real"
    "\n     game, but that is a TYPE immunity and `immune_to_status` has no Ground arm"
    "\n     (gen 5's PARALYZE arm is only Limber). So: does the engine block it elsewhere?",
    [b("Latios"), b("Golem", types=("Ground", "Rock"))], "thunderwave,1",
    "nothing at all if type immunity is honoured somewhere; a paralyzed Golem if not")
run("(C2) slot 0 is GROUND and slot 1 is a legal target -- the mirror of C1, which"
    "\n     separates 'reads the wrong body' from 'ignores type immunity'",
    [b("Golem", types=("Ground", "Rock")), b("Cresselia")], "thunderwave,1",
    "Cresselia paralyzed either way, but WHICH body the engine consulted shows here")
