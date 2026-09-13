"""Which bodies does a spread move damage, by target class and by what is standing there?

Defect 10 is the spread divergence, and the corpus that found it only ever contained
AllAdjacent moves (Earthquake, Surf) -- no AllAdjacentFoes move (Heat Wave, Blizzard, Rock
Slide) was in the pool at all, and no move had a secondary. So the divergence is specifically
about ally-hitting spread, which is what this enumerates: expected set against emitted set.
"""
import sys
from pathlib import Path
sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions
import re
DMG = re.compile(r"^Damage (SideOne|SideTwo):(\d+): (-?\d+)$")

def b(species, types, moves, ability="none"):
    return dict(species=species, hp=400, maxhp=400, types=types, fainted=False,
                ability=ability, item=None, status="none", volatiles=[], lastMove=None,
                boosts={}, weightkg=50, stats=dict(atk=200, **{"def": 200}, spa=200, spd=200, spe=100),
                moves=[dict(id=m, pp=16) for m in moves])

MOVES = ["earthquake", "surf", "heatwave", "blizzard", "rockslide"]

def run(label, ally, foe0, foe1):
    s1 = dict(active=[b("Attacker", ["Normal"], MOVES), ally], bench=[], conditions={})
    s2 = dict(active=[foe0, foe1], bench=[], conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    print(f"\n{label}")
    print(f"   ally={ally['species']}({'/'.join(ally['types'])},{ally['ability']})  "
          f"foes={foe0['species']}({'/'.join(foe0['types'])},{foe0['ability']}), "
          f"{foe1['species']}({'/'.join(foe1['types'])},{foe1['ability']})")
    for mv in MOVES:
        try:
            ins = generate_instructions(st, f"{mv},0;none", "none;none")
        except ValueError as e:
            print(f"      {mv:11} -> not a move id this build knows ({e})")
            continue
        hit = {}
        for x in ins:
            if x.percentage < 50:   # read the dominant branch only
                continue
            for i in x.instruction_list:
                m = DMG.match(str(i))
                if m:
                    hit[("ally" if m[2] == "1" else "SELF") if m[1] == "SideOne" else f"foe{m[2]}"] = int(m[3])
        print(f"      {mv:11} -> {hit if hit else 'NOTHING'}")

plain = lambda n, t="Normal", a="none": b(n, [t], ["tackle"], a)
run("(1) plain 2v2, nothing immune or exempt",
    plain("Ally"), plain("Foe0"), plain("Foe1"))
run("(2) ally is FLYING, so immune to Earthquake but not Surf",
    plain("AllyFly", "Flying"), plain("Foe0"), plain("Foe1"))
run("(3) ally has TELEPATHY, exempt from the partner's spread move entirely",
    plain("AllyTele", "Normal", "telepathy"), plain("Foe0"), plain("Foe1"))
run("(4) one FOE has LEVITATE (ability immunity) in slot 0",
    plain("Ally"), plain("FoeLev", "Normal", "levitate"), plain("Foe1"))
run("(5) one FOE is FLYING (type immunity, not ability) in slot 0",
    plain("Ally"), plain("FoeFly", "Flying"), plain("Foe1"))
run("(6) the immune FOE is in slot 1 instead -- does it depend on the slot?",
    plain("Ally"), plain("Foe0"), plain("FoeLev", "Normal", "levitate"))
run("(7) ally immune by ABILITY rather than type",
    plain("AllyLev", "Normal", "levitate"), plain("Foe0"), plain("Foe1"))
