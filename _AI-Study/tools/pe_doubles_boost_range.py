"""Defect 2: find the write that drives a boost outside +-6, by instrumenting the only mutator.

Run 12. `Invalid boost value: -7 / -8 / -11 / -12` (`genx/evaluate.rs:107`) and `Invalid boost
number: 7 / 8` (`genx/state.rs:43`) are both READERS with a bare `_ => panic!`. Reading the
writers explained half the evidence and not the other half, which is why this probe exists.

WHAT READING THE SOURCE ESTABLISHED, and it is a closed set. `Side::apply_boost`
(`state.rs:2039`) is the SOLE boost mutator and has no clamp -- a bare `+=`. `get_boost_amount`
(the clamp) has exactly TWO callers, both in `generate_instructions.rs`, and everything else
routes through `apply_boost_instruction`, which clamps against the same slot it mutates and
emits. Only FOUR emit sites bypass that helper:

    abilities.rs:1324   SPEEDBOOST      end of turn, +1
    abilities.rs:1523   INTREPIDSWORD   switch-in, +1   (gen 8: 0/183 teams here)
    abilities.rs:1669   DAUNTLESSSHIELD switch-in, +1   (gen 8: 0/183 teams here)
    choice_effects.rs:1279  BELLYDRUM   up to +12       (0/183 teams here)

SPEEDBOOST is the one real inconsistency: `ability_end_of_turn` (`abilities.rs:1170`) derives
`owner_slot = state.actor_slot()` -- the STALE acting slot left over from the last move resolved
-- while reading and mutating `attacking_side.get_active()`, which is always slot 0. So the
`< 6` guard bounds slot 0 while the emitted instruction accumulates on whichever slot acted
last, and nothing bounds that one. That is a coherent account of **+7 / +8**. The same function
is called once per SIDE (`generate_instructions.rs:3807`) behind a slot-0 hp guard, so a slot-1
body's end-of-turn ability never fires at all -- the same unfinished `get_active()` conversion
as defects 6, 14, 20, 23 and 26. `item_end_of_turn` on the line above shares the shape.

WHAT IT DID NOT EXPLAIN, and the reason this is a probe and not a fix: **every negative path
found is correctly clamped.** All four unclamped emits ADD. Draco Meteor's -2 self-drop
(109/183 teams), Download (28/183) and Defiant (28/183) all go through the clamping helper;
Moxie, Competitive and Contrary are 0/183. So nothing found accounts for -11 or -12, and run
10's lesson was explicit about what to do when source-reading runs out: instrument the engine
instead of reasoning forward from it. Four wrong hypotheses cost that run a day.

WHY THE MUTATOR AND NOT THE CALLERS. A print inside `apply_boost` catches every path by
construction, including the one this audit missed, and it fires on the FIRST out-of-range write
rather than on whichever one a reader happens to reach later -- the readers are downstream and
say nothing about provenance. The instrumentation is temporary and is removed before the patch
(unlike run 10's enriched assert, which was kept on purpose).

THE REPRO IS EVIDENCE, NOT A CONSTRUCTION. `generated/doubles_play_logs_gen5_tailwind/000` is a
tracked log in which this panic fires on the very FIRST decision of battle 0, and again at turn
3, so the opening position alone is enough -- no battle loop, no depth to reach. Both teams are
named here rather than indexed so the provenance is readable; both are size 4 and both LEAD with
Genesect (Download), the switch-in ability that reads and writes through the stale `actor_slot`.
The panic is probabilistic because MCTS is unseeded, so each budget is attempted several times.

    python3 tools/pe_doubles_boost_range.py [attempts] [ms]
"""
import json, sys
from pathlib import Path

sys.path.insert(0, "tools")
PLAY = Path("tools/pe_doubles_play.py")
_ns = {"__file__": str(PLAY), "__name__": "_probe"}
exec(compile(PLAY.read_text(), str(PLAY), "exec"), _ns)
Server, to_state = _ns["Server"], _ns["to_state"]
load_dump_teams = _ns["load_dump_teams"]
from poke_engine import monte_carlo_tree_search

ATTEMPTS = int(sys.argv[1]) if len(sys.argv) > 1 else 12
MS = int(sys.argv[2]) if len(sys.argv) > 2 else 300

# The two teams from the tracked log's battle 0, by NAME.
#
# The LEAD ORDER MATTERS and the first version of this probe got it wrong, which is worth
# recording because the wrong version produced a confident "0/5 panicked". That log was made
# with `--require-move tailwind`, and `load_dump_teams` ROTATES the carrier to the front so it
# leads (see its docstring). In both of these teams the Tailwind carrier sits at dump index 3 --
# Tornadus and Latios -- so the authored order leads Genesect+Politoed / Genesect+Blaziken while
# the log's actual position leads Tornadus+Genesect / Latios+Genesect. Going through
# `load_dump_teams` with the same `require` reproduces the rotation instead of re-deriving it.
P1_NAME, P2_NAME = "Perfect Rain", "Untitled 525"
teams = load_dump_teams("gen5doublesou", sizes=(4,), require=("tailwind",))
picked = {}
for text_, label, _size in teams:
    name = label.split(":")[0]
    if name in (P1_NAME, P2_NAME) and name not in picked:
        picked[name] = (text_, label)
missing = {P1_NAME, P2_NAME} - set(picked)
if missing:
    sys.exit(f"teams not found among tailwind-carrying size-4 teams: {sorted(missing)}")

print("=" * 88)
print("Which write drives a boost outside +-6? (defect 2, run 12)")
print("=" * 88)
for name in (P1_NAME, P2_NAME):
    print(f"\n{picked[name][1]}")
print("\n(carrier rotated to the lead by --require-move tailwind, as in the tracked log)")

text = {n: picked[n][0] for n in (P1_NAME, P2_NAME)}

server = Server()
try:
    # Exactly the log's battle 0: real PRNG (pinPrng False) and seed [0, 2, 3, 4].
    r = server.send({"cmd": "new", "p1": text[P1_NAME], "p2": text[P2_NAME],
                     "format": "gen5doublescustomgame", "pinPrng": False, "seed": [0, 2, 3, 4]})
    if not r.get("ok"):
        sys.exit(f"server refused the position: {r.get('error')}")
    position, reqs = r["position"], r["requests"]
    print("\nOpening position built. Actives:")
    for s in position["sides"]:
        print(f"   {s['side']}: " + ", ".join(
            f"{p['species']} {p['hp']}/{p['maxhp']} boosts={ {k: v for k, v in p['boosts'].items() if v} or '{}' }"
            for p in s["active"] if p))

    state = to_state(position, reqs)
    print(f"\nRunning the search {ATTEMPTS}x at {MS} ms. Any `DBG boost out of range` line below")
    print("comes from the instrumented mutator and names the side, slot, stat and amount.\n")
    panics = 0
    for i in range(ATTEMPTS):
        try:
            result = monte_carlo_tree_search(state, duration_ms=MS)
            print(f"   attempt {i + 1}: ok, {result.total_visits} visits")
        except BaseException as exc:          # PanicException subclasses BaseException
            panics += 1
            print(f"   attempt {i + 1}: PANICKED -- {str(exc).splitlines()[0][:90]}")
    print(f"\n{panics}/{ATTEMPTS} attempts panicked.")
    if panics == 0:
        print("A clean run is NOT evidence the defect is absent: the panic is probabilistic")
        print("because MCTS is unseeded. Re-run with more attempts or a larger budget.")
finally:
    server.close()
