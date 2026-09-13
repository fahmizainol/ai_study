"""The three "unrepresentable" volatiles were a translator gap, and two of the three are inert.

Run 11. `disable`, `lockedmove` and `twoturnmove` were counted skips: a position carrying one
could not be built, so the search never ran and greedy took the decision. They were 6 of the 7
remaining fallbacks after run 10. None of them needed an engine change.

THE UNDERLYING BUG, which made the whole class invisible: `pe_doubles_corpus.py`'s `mon()`
validated `d["volatiles"]` against its `VOLATILE` table and then **never passed them** -- the
`Pokemon(...)` call had no `volatile_statuses` argument at all. So every volatile the table
claimed to map was silently dropped, and the only ones that showed up as problems were the
handful that raised Skip. Latent for the corpus (0 of 456 turns carry a volatile on an active or
a bench body, checked) and expensive for the play harness.

WHY TWO OF THE THREE ARE INERT, not mapped:

  * `disable` -- poke-engine HAS a DISABLE volatile, but nothing reads it to restrict a choice.
    Its only non-application use site is an Aroma Veil gate (`genx/state.rs:780`), while
    `move_is_selectable` reads the per-move `Move.disabled` flag. Run 9 already fills that from
    Showdown's own per-move `disabled`, so the EFFECT is modelled and the volatile is redundant.
  * `twoturnmove` -- Showdown's condition does `attacker.addVolatile(effect.id)` inside its own
    onStart (`data/conditions.ts:294`), so a charging body carries BOTH `twoturnmove` and a
    volatile named after the move. poke-engine reads the move-named one, through
    `active_is_charging_move_slot`'s CHARGE_VOLATILES table (`genx/state.rs:1134`). Mapping the
    generic marker to an engine name would have been wrong; mapping its siblings is the fix.
    Cell C is the control that proves the marker alone does nothing.

`lockedmove` maps to the engine's LOCKEDMOVE, which TRAPS but does not by itself force the move
(cell D1); the forcing comes from the whitelist, because Showdown sends a locked body a
single-entry move list (cell D2). It is passed with NO duration, which is a recorded
approximation: the engine counts lockedmove UP (0, 1, then at 2 it removes the volatile and
applies confusion, `generate_instructions.rs:3898`) while Showdown counts a hidden `trueDuration`
DOWN from random(2,4), and the snapshot carries no counter. A lock therefore always looks FRESH,
so the search over-estimates how long the body stays locked.

TWO TRAPS THIS RUN AVOIDED, both recorded because passing volatiles is what exposed them:

  * `slowstart` used to be mapped and is now deliberately NOT (cell G). The end-of-turn block
    does `slowstart -= 1` and then tests `== 0` (`:3880`), so the duration 0 the snapshot would
    supply goes to -1 and the volatile is NEVER removed -- a permanently halved-Attack body.
    Inert beats wrong. Free here: Slow Start is 0 bodies in all 183 gen5doublesou teams.
  * `substitute` needed its HEALTH plumbed alongside (cell F). Showdown keeps it on the volatile
    (`effectState.hp`); poke-engine keeps it on the Pokemon (`substitute_health`). Sending the
    volatile without the number models a barrier that absorbs min(damage, 0), which is worse
    than the skip it replaces -- so `body()` in `showdown_doubles_lib.js` now emits `subHp`.

An unmapped name must still raise Skip rather than be passed through (cell H), because
`PokemonVolatileStatus::from_str` ends in `_ => Ok(default)` (`src/lib.rs:65`): an unrecognised
name does not error, it silently becomes NONE and is inserted into the bitset.

Prevalence in the play pool, which is why this was worth a run at all -- the scan's controls
landed exactly (Protect 174/183, Encore 33/183), so its zeroes are trustworthy:

    charge (two-turn)   46/183 teams    of which skydrop alone is 43
    taunt               71/183          mapped all along and silently dropped until now
    lockedmove           6/183
    disable              3/183
    recharge             2/183
    slowstart / truant / partiallytrapped   0/183
"""
import sys
from pathlib import Path

sys.path.insert(0, "tools")
CORPUS = Path("tools/pe_doubles_corpus.py"); _ns = {}
exec(compile(CORPUS.read_text().split("# ---- run")[0], str(CORPUS), "exec"),
     dict(_ns, __file__=str(CORPUS)) if False else _ns)
mon, build_side, State, Skip = _ns["mon"], _ns["build_side"], _ns["State"], _ns["Skip"]
from poke_engine import Side, SideConditions, monte_carlo_tree_search

MOVES = ["solarbeam", "outrage", "tackle", "protect"]


def sd_body(species, moves, volatiles=(), sub_hp=0, last=None, hp=400):
    """One body in the shape `showdown_doubles_lib.js`'s `body()` emits, so this exercises the
    real translator rather than a hand-built Pokemon -- the translator is what changed."""
    return {
        "species": species, "ability": "none", "item": "", "types": ["Normal"],
        "weightkg": 50.0, "hp": hp, "maxhp": 400, "status": "none", "fainted": hp <= 0,
        "stats": {"atk": 200, "def": 200, "spa": 200, "spd": 200, "spe": 100},
        "boosts": {}, "volatiles": list(volatiles), "subHp": sub_hp, "lastMove": last,
        "moves": [{"id": m, "pp": 16} for m in moves],
    }


def options(volatiles=(), usable=None, sub_hp=0):
    """Root option labels for side one slot 0, translated through mon()/build_side().

    A tiny budget is enough: root options are enumerated before any search happens, and this
    asks only WHICH options exist, never which is best.
    """
    s1 = build_side(
        {"conditions": {},
         "active": [sd_body("Blastoise", MOVES, volatiles, sub_hp),
                    sd_body("Raichu", ["tackle"])],
         "bench": [sd_body("Snorlax", ["tackle"])]},
        allow_fainted=True, usable={0: usable} if usable is not None else None)
    s2 = build_side(
        {"conditions": {},
         "active": [sd_body("Gengar", ["tackle"]), sd_body("Gastrodon", ["tackle"])],
         "bench": []}, allow_fainted=True)
    result = monte_carlo_tree_search(State(side_one=s1, side_two=s2), duration_ms=60)
    return [str(o.move_choice) for o in result.side_one]


def show(label, expect, volatiles=(), usable=None, sub_hp=0):
    print(f"\n{label}")
    print(f"   volatiles={list(volatiles) or '(none)'}"
          + (f"  whitelist={sorted(usable)}" if usable is not None else "")
          + (f"  subHp={sub_hp}" if sub_hp else ""))
    print(f"   expected: {expect}")
    try:
        labels = options(volatiles, usable, sub_hp)
    except Skip as exc:
        print(f"      SKIPPED: {exc}   <-- the position could not be built at all")
        return
    slot0 = sorted({m for m in MOVES if any(m in x.split(";")[0] for x in labels)})
    switches = sum(1 for x in labels if "switch" in x.split(";")[0].lower())
    print(f"      {len(labels)} root options; slot 0 reaches moves {slot0}"
          f"; slot 0 switch options {switches}")


print("=" * 88)
print("Do the three 'unrepresentable' volatiles need an engine change? (run 11)")
print("=" * 88)
print(f"\nSide one slot 0 knows: {', '.join(MOVES)}, and has one body on the bench.")

show("(A) BASELINE: no volatiles. All four moves selectable, switching allowed.",
     "four moves reachable and at least one switch option")

show("(B) THE FIX: a charging Solar Beam, as Showdown reports it -- the generic marker AND "
     "the move-named sibling it adds.",
     "exactly ONE move reachable, solarbeam, and no switch: the engine's charge path "
     "(`active_is_charging_move_slot`) now fires. Before run 11 this whole position raised "
     "Skip and greedy took the decision",
     ("twoturnmove", "solarbeam"))

show("(C) CONTROL for (B): the generic marker ALONE, with no sibling.",
     "unchanged from (A) -- proof that `twoturnmove` is inert and that mapping IT to an engine "
     "name would have been the wrong fix",
     ("twoturnmove",))

show("(D1) `lockedmove` alone: LOCKEDMOVE traps but does not force the move.",
     "all four moves still reachable, but ZERO switch options -- `trapped_slot` reads "
     "LOCKEDMOVE (`genx/state.rs:1178`)",
     ("lockedmove",))

show("(D2) `lockedmove` as Showdown actually presents it: volatile PLUS the single-entry "
     "move list run 9's whitelist derives.",
     "only outrage reachable, and still no switch -- the two halves together reproduce "
     "Showdown's own restriction",
     ("lockedmove",), usable={"outrage"})

show("(E) `disable`: inert volatile, whitelist does the work.",
     "the position BUILDS (no Skip) and solarbeam is gone because the whitelist omits it -- "
     "the engine never needed its DISABLE volatile",
     ("disable",), usable={"outrage", "tackle", "protect"})

show("(F) `substitute` with its health, now that `body()` emits subHp.",
     "builds, and the substitute reaches the engine with real health rather than 0",
     ("substitute",), sub_hp=100)

show("(G) `slowstart`: mapped to None ON PURPOSE. It must NOT reach the engine.",
     "builds and behaves exactly like (A). If it were passed with duration 0 the end-of-turn "
     "`-= 1` would take it to -1 and it would never be removed",
     ("slowstart",))

show("(H) An unmapped name must still SKIP, not be passed through.",
     "Skip. `from_str` would silently turn it into NONE rather than erroring, so validation "
     "in the translator is the only thing standing between a typo and a wrong state",
     ("partiallytrapped",))

print("\n" + "=" * 88)
print("substitute_health actually delivered (F's body, read back off the translated Pokemon):")
p = mon(sd_body("Blastoise", MOVES, ("substitute",), sub_hp=100))
print(f"   substitute_health={p.substitute_health}   volatile_statuses={sorted(p.volatile_statuses)}")
p0 = mon(sd_body("Blastoise", MOVES, ("slowstart", "twoturnmove", "disable")))
print("   slowstart/twoturnmove/disable body -> volatile_statuses="
      f"{sorted(p0.volatile_statuses) or '(empty, as intended)'}")
