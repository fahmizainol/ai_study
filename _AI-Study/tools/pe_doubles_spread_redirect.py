"""Does an absorb ability REDIRECT a spread move, and what happens to the rest of it?

Corpus battle 5 turn 10 is the last boosts row that is neither a faint artefact nor the
absorb-through-Protect defect, and its instruction dump is the puzzle:

    p2 slot0 Blastoise Surf (AllAdjacent), p2 slot1 Gastrodon (Storm Drain) Calm Mind,
    p1 slot0 Gengar Protect, p1 slot1 Raichu Shock Wave

    Showdown : Surf damages Raichu (kills it), is blocked by Gengar's Protect, and is
               ABSORBED by the attacker's own ally Gastrodon -> spa +1 on top of Calm Mind
    engine   : Surf produces NOTHING AT ALL -- no damage to Raichu, no absorb boost; the only
               instructions are Calm Mind's spa+1/spd+1 and Raichu's own Shock Wave

WHAT READING THE SOURCE ESTABLISHED, and where it stopped. `redirect_target`
(`generate_instructions.rs:2266`) takes `choice` IMMUTABLY and returns only a position, so it
cannot rewrite `choice.target` and cannot flip `resolves_per_target`. But its single-target
guard at `:2324` gates only the VOLATILE redirection (Follow Me / Rage Powder): the ability
scan above it runs for every move, spread moves included. Showdown forbids that -- its
`priorityEvent('RedirectTarget')` sits inside the `default:` branch of the target switch
(`sim/pokemon.ts:835`), which spread targets never reach. So a spread Surf here is redirected
onto the attacker's OWN ALLY. The missing spread guard predates run 4; run 4's field-wide
scan is what made the attacker's own side reachable, so this is a blast radius I widened.

That explains the redirect. It does NOT explain the missing damage on Raichu, who is neither
protected nor the redirect target, and whom the per-target loop should hit normally
(`spread_target_positions` correctly returns three living targets here). Rather than build a
fourth chain of inference, this probe asks the engine, varying the two suspects independently:

    ally ability  in {stormdrain, none}   x   foe slot 0  in {protect, tackle}

Four cells. If the damage vanishes only when the ally holds Storm Drain, the redirect is
swallowing the whole move; if it vanishes only under Protect, the whole-move cancel is
reachable after all; if it needs both, they interact. Full instruction lists are printed, not
just boosts, because "where did the damage go" is the question.

The ally uses SWORDS DANCE so that it is not idle and its own boost cannot be confused with an
absorbed one: Swords Dance is atk, the Storm Drain absorb is spa. Every body is Normal-typed
with explicit stats, so Water is neutral everywhere and no type chart enters the picture.
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"), _ns)
build_side, State = _ns["build_side"], _ns["State"]
from poke_engine import generate_instructions


def b(species, moves, ability="none", spa=200, hp=400, spe=100):
    return dict(species=species, hp=hp, maxhp=hp, types=["Normal"], fainted=False,
                ability=ability, item=None, status="none", volatiles=[], lastMove=None,
                boosts={}, weightkg=50,
                stats=dict(atk=200, **{"def": 200}, spa=spa, spd=200, spe=spe),
                moves=[dict(id=m, pp=16) for m in moves])


def run(label, ally_ability, foe0_move, expect):
    """side two slot 0 Surfs (AllAdjacent). Its ally is slot 1; the foes are side one."""
    s1 = dict(active=[b("Gengar", ["protect", "tackle"]), b("Raichu", ["tackle"])],
              bench=[], conditions={})
    s2 = dict(active=[b("Blastoise", ["surf"]),
                      b("Gastrodon", ["swordsdance"], ability=ally_ability)],
              bench=[], conditions={})
    st = State(side_one=build_side(s1, True), side_two=build_side(s2, True))
    print(f"\n{label}")
    print(f"   ally (s2 slot1) ability={ally_ability!r}   foe slot0 uses {foe0_move!r}")
    print(f"   expected: {expect}")
    try:
        branches = generate_instructions(st, f"{foe0_move},0;tackle,0", "surf;swordsdance")
    except Exception as exc:                      # a panic here is a finding, not a crash
        print(f"      RAISED {type(exc).__name__}: {exc}")
        return
    br = max(branches, key=lambda x: x.percentage)
    print(f"      top branch {br.percentage:.1f}% of {len(branches)}:")
    for ins in br.instruction_list:
        print("       ", ins)


print("=" * 88)
print("A. does the attacker's own Storm Drain ally swallow a SPREAD move?")
print("=" * 88)
run("(A1) the corpus shape: ally holds Storm Drain AND foe slot 0 Protects.",
    "stormdrain", "protect",
    "Damage on Raichu (foe slot 1, unprotected), nothing on Gengar, and spa +1 on the "
    "Gastrodon ally. The corpus says the engine produces NO Surf effect at all")
run("(A2) ally ability removed, Protect kept -- isolates the redirect.",
    "none", "protect",
    "Damage on Raichu AND on the ally Gastrodon (Surf is AllAdjacent), nothing on Gengar")
run("(A3) Storm Drain kept, Protect removed -- isolates the protect path.",
    "stormdrain", "tackle",
    "Damage on Gengar and Raichu, spa +1 on the ally, no damage to the ally")
run("(A4) CONTROL: neither. Plain spread Surf into two foes and one ally.",
    "none", "tackle",
    "Damage on all three of Gengar, Raichu and the ally Gastrodon")
