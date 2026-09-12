"""Isolate the status-target question with no immunity confound: both foes are Psychic-types
that Thunder Wave can legally paralyze, and they differ only in party/slot position."""
import sys
from pathlib import Path
sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions

def b(species, moves, status="none"):
    return dict(species=species, hp=300, maxhp=300, types=["Psychic"], fainted=False,
                ability="none", item=None, status=status, volatiles=[], lastMove=None,
                boosts={}, weightkg=50, stats=dict(atk=200, **{"def": 200}, spa=250, spd=200, spe=100),
                moves=[dict(id=m, pp=16) for m in moves])

s1 = dict(active=[b("Togekiss", ["thunderwave"]), b("Togekiss", ["thunderwave"])],
          bench=[], conditions={})
s2 = dict(active=[b("Latios", ["recover"]), b("Cresselia", ["recover"])], bench=[], conditions={})
state = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
print("side two party order: P0=Latios (slot 0), P1=Cresselia (slot 1)")
for a in ("thunderwave,0", "thunderwave,1"):
    ins = generate_instructions(state, f"{a};none", "recover,0;none")
    print(f"  {a}  ->  " + "; ".join(str(i) for x in ins for i in x.instruction_list))
