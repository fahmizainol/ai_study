"""Does Fake Out's first-turn-out check read the ACTING slot's history, or slot 0's?

poke-engine models the restriction through last_used_move (choice_effects.rs:213): a body whose
last_used_move is Move(_) has already acted, so Fake Out loses its effects. In doubles both the
read and the write go through get_active() -- slot 0. This reproduces seed23/004 turn 3, where
Scrafty in SLOT 1 had been out and acting while Crobat in slot 0 had just switched in: Showdown
failed the Fake Out, poke-engine kept it, and the search ranked it top.
"""
import sys
from pathlib import Path
sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions

def b(species, moves, last=None):
    return dict(species=species, hp=300, maxhp=300, types=["Normal"], fainted=False,
                ability="none", item=None, status="none", volatiles=[], lastMove=last,
                boosts={}, weightkg=50, stats=dict(atk=200, **{"def": 200}, spa=200, spd=200, spe=100),
                moves=[dict(id=m, pp=16) for m in moves])

def run(slot0_last, slot1_last):
    s1 = dict(active=[b("Crobat", ["bravebird"], slot0_last),
                      b("Scrafty", ["fakeout", "crunch"], slot1_last)], bench=[], conditions={})
    s2 = dict(active=[b("Victini", ["blueflare"]), b("Togekiss", ["flamethrower"])],
              bench=[], conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    ins = generate_instructions(st, "none;fakeout,1", "none;none")
    flinch = any("FLINCH" in str(i) for x in ins for i in x.instruction_list)
    print(f"  slot0 last={slot0_last or 'just switched in':>18}  "
          f"slot1(Scrafty) last={slot1_last or 'just switched in':>18}  ->  "
          f"Fake Out {'FLINCHES (live)' if flinch else 'has no effect (correctly dead)'}")

print("Scrafty is in SLOT 1 and is the one using Fake Out. Only its own history should matter.")
run(None, None)            # both fresh: Fake Out should work
run(None, "crunch")        # Scrafty HAS acted -> must be dead. Slot 0 fresh.
run("bravebird", None)     # Scrafty fresh -> must work. Slot 0 has acted.
run("bravebird", "crunch") # both acted -> dead
