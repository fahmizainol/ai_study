# What to run a search on: four boards, measured

Companion to `PORTABLE-AI-REALIDEA.md`. That document is the adapter's history; this one
answers the question 0.8.0 raised and could not settle inside itself: **if the board was
the problem and not the search, what boards are actually available, what do they cost,
and which of them can do doubles?** Measured 2026-09-09 on the study machine (WSL2, 6
cores, Node 24.11.1, Ruby 3.2.3), except where a figure is cited from the notes.

Everything below is a feasibility measurement. Nothing here is installed, and no arm in
the study currently uses Showdown.

## The four boards

A "board" here is whatever a search steps forward when it asks *what happens if I do
this*. Four candidates exist for this study, and they differ by three orders of magnitude.

| Board | One simulated turn | Clone a position | 5000-iteration decision | Doubles |
|---|---|---|---|---|
| Essentials' own engine, RGSS Ruby 1.8 | ~50 ms | **not possible** | not possible | it *is* doubles |
| Our Ruby projection (`portable_ai/search.rb`), Ruby 3.2 | 0.03 ms | 0.006 ms | 987 ms | no |
| Pokémon Showdown, Node 24 | 0.64 ms (0.33 patched) | 0.6 ms | ~4 s | **yes** |
| poke-engine (Rust), through the sidecar | ~2 µs implied | in-engine undo | **10 ms** | **no** |

**Essentials' number is derived, not benchmarked.** The 0.8.0 driver log gives wall clock
per roster and the records give turns per battle: gen5ru_a 102 s / 1803 turns, gen5uu_a
171 s / 3323 turns, so 51 to 57 ms a turn including game boot, both sides' AI and the
harness. No animations run in the gauntlet. The disqualifying column is the second one:
Essentials cannot copy a battle, so its engine can only ever be the leaf of a one-ply
lookahead, never a tree. That is the one viable shape for it and it remains untried.

**The Ruby projection is fast and that was never the problem.** Per-turn 0.03 ms, a board
copy 0.006 ms, a leaf 0.006 ms; the maximin is 1.01 ms at depth 1 and 13.3 ms at depth 2;
the tree is 171 ms at 1000 iterations and 987 ms at 5000, which is 0.2 ms an *iteration*.
So the tree's cost is its own bookkeeping, not the board. Modern Ruby and RGSS Ruby 1.8
land within about 10% of each other here (the notes record ~894 ms at 5000 in 1.8), so the
interpreter was never the bottleneck either. What 0.8.0 established is that this board is
*wrong*, not slow. Bench: `tools/search_bench.rb`, run with plain `ruby`.

## Showdown as a search board

Clone: `pokemon-showdown` at the repo root, shallow, commit `6b4bc34` (2026-09-06), built
with `node build`. 297 MB, so it is in `.gitignore` and not committed.

**It can do the three things a search board must.**

1. **Doubles, triples and more** are first-class (`format.gameType`); a gen 5 doubles
   custom game plays two-target move strings without complaint.
2. **A position can be constructed mid-battle.** There is a full serializer in
   `sim/state.ts` (`State.serializeBattle` / `deserializeBattle`, exposed as
   `Battle.toJSON` / `Battle.fromJSON`, resumed with `restart(send)`), and beyond that the
   live battle is plain mutable JavaScript: setting HP, status, boosts and a side
   condition directly on the objects and continuing works. It also enforces rules on the
   way in, which is the point: an attempt to burn a Fire type was silently refused.
   This corrects an earlier assessment in this study that said Showdown could not start
   mid-battle. It can. Mapping a Realidea position onto it is the same kind of job as the
   0.8.0 poke-engine adapter, with more fields.
3. **It is deterministic** given a seed, which is what makes the patch work below
   verifiable. Its log carries `|t:|` timestamp lines; strip those before hashing.

### Optimising it

Profile of stock play (`--cpu-prof`): event dispatch ~45%, of which `getCallback` alone is
26.5%; garbage collection 14.7%, mostly the temporary handler arrays; `deepClone` on move
activation 7.2%; module loading ~8%, one-time. The cost is architectural. Every event
walks every ability, item, status, volatile, side and field condition on every active
Pokémon and asks each one whether it implements `onX`, by dynamic key. That dynamic key
against many object shapes is a megamorphic property access, which V8 cannot inline-cache.

Three patches were applied to the built `dist`, each verified against a byte-for-byte hash
of 50 battles / 497 turns (singles and doubles, gen 5, timestamps stripped). **All three
preserve the logs exactly.** Steady-state singles, best of three runs:

| Build | ms per turn |
|---|---|
| Stock | 0.636 |
| `prio`: hoist `resolvePriority`'s per-call object literal, cache its three template-string keys | 0.592 |
| `move`: shallow copy instead of `deepClone` in `getActiveMove` | 0.527 |
| **`cb`: per-effect handler Map in a WeakMap, so `effect[callbackName]` stops being a megamorphic miss** | **0.327** |
| `cb` + `move` | 0.551 |
| `prio` + `cb` | 0.625 |

**The bottom two rows are the finding.** Both other patches help alone and both cancel the
big one when stacked, so these do not compose and each must be measured on top of the
others rather than assumed additive. Reading, measured but not proven: `move` mints a
fresh object per move use, so every use builds a new handler Map and the cache thrashes;
and `prio` adds a Map lookup to the hottest loop, which only paid for itself while the
property read after it was still slow.

Two levers need no code change at all:

- `--max-semi-space-size=128` (bigger V8 young generation) takes about 15% off, since the
  temporary handler arrays were most of the garbage.
- Process parallelism scales to **4.0x at four processes** on six cores, flattening at
  4.26x by six. Combined with `cb` that is roughly 0.08 ms a turn of aggregate throughput
  against 0.64 stock.

Caveat on all of it: three-Pokémon teams, random play, gen 5, and run-to-run spread on
this machine is around ±20%, so treat these as ratios rather than absolutes.

### What a search actually costs on it

Measured with an iteration shaped like Foul Play's: reconstruct the node's state, apply one
joint action, evaluate a static leaf, no rollout (`tools/showdown_mcts_cost.js`).

| Budget | Singles | Doubles |
|---|---|---|
| 1000 iterations | 0.7 to 0.8 s | 0.8 to 0.9 s |
| 5000 iterations | 3.4 to 4.2 s | 4.1 to 4.5 s |

Roughly 0.7 to 0.9 ms an iteration, and **doubles is barely worse than singles** because
the cost is dominated by rebuilding state, not by resolving the turn. Two consequences
worth carrying forward:

- **The `cb` patch barely helps a search.** It halves the turn, but the turn is only about
  a third of an iteration, so 5000 goes from ~4.1 s to ~3.9 s. For a search workload the
  target is state reconstruction, not event dispatch. That reorders the optimisation list
  above for this use case.
- **Memory is the harder constraint.** A retained node costs 66 KB (singles) or 97 KB
  (doubles), so a 5000-node tree is 320 to 470 MB. Holding clones is what keeps an
  iteration at one clone regardless of depth; replaying from the root instead is nearly
  free on memory but costs an extra turn per ply, about 1.8 ms an iteration at depth 4,
  roughly 9 s for 5000.

### The log trap, which anyone building this will hit

Every battle deserialized from **the same parsed state object shares one `log` array by
reference**, so stepping one clone appends to all of them, and Showdown's log-length guard
(`log.length - sentLogPos > 1e3` in `singleEvent`) throws `Error: Infinite loop`. It broke
after 56 clones here. Keep the snapshot as a **string** and let `fromJSON` parse it fresh
each time. The state object itself is *not* mutated by `fromJSON`; an earlier note in this
session said it was and that was wrong.

The log is also dead weight in a search and grows with the battle: stripping it from the
snapshot cut an iteration from 0.64 to 0.48 ms on a short battle, with the gain shrinking
as the rest of the state grows relative to it. A fork would disable the log outright.

## Doubles in poke-engine: a core rewrite, and someone already wrote it

Asked because poke-engine is the only board fast enough to be interesting. The answer from
the source at the pinned commit `f4e224c` is that doubles is a rewrite of the engine core,
and what survives is the data tables, not the mechanics. **That rewrite exists** — as a
closed, unreviewed PR, audited below on 2026-09-12; read the source audit first, because it
is what the PR had to pay for.

- **The active Pokémon's own state lives on the side, not the Pokémon.** `Side` holds one
  `active_index`, the seven boost stages, the volatile bitset, substitute health, last used
  move and damage dealt. Correct in singles, where boosts die on switch; per slot in
  doubles. About 660 use sites, `volatile_statuses` alone 357.
- **Every instruction addresses a side, never a slot.** `DamageInstruction { side_ref,
  damage_amount }`, `BoostInstruction { side_ref, stat, amount }`, and so on for all fifty
  or so variants. The undo system reads them, so each needs a slot plus every construction
  site and both the apply and reverse arms.
- **Targeting has two values.** `MoveTarget` is `User | Opponent`. No ally, no position, no
  spread multiplier, no redirection, so Follow Me, Rage Powder, Lightning Rod, Storm Drain,
  Ally Switch, Helping Hand, Wide Guard and the 0.75x spread reduction are absent, not
  weakened.
- **A turn is a pair, structurally.** `generate_instructions_from_move_pair` takes one move
  per side and makes one ordering decision. Doubles resolves four actions, re-orders as
  bodies faint mid-turn, and redirects targets that vanished.
- **The search gets worse too.** Singles is ~9 options a side, 81 joint pairs at a node.
  Doubles is ~17 a slot once targets count, near 250 a side, so tens of thousands of joint
  pairs. The 10 ms decision does not survive that even in Rust.

The mechanics needing re-audit under a slot-aware model are ~14,000 lines, mostly
`genx/generate_instructions.rs` (10,904).

### PR #10 "Main doubles": what it actually is

Upstream has one PR, #10, opened 2026-06-19 14:04Z and **closed by pmariglia 64 minutes
later with zero comments and zero review comments**. "Unmerged the same day" was recorded
here before anyone read it. Read now, it is not an abandoned sketch: **9,214 insertions and
3,869 deletions across 55 files** (`genx/generate_instructions.rs` 2665+/1425-,
`genx/state.rs` 921+, `state.rs` 826+, `instruction.rs` 171+, every generation's
`state`/`evaluate`/`choice_effects`, and the Python binding at 246+). Three commits by
`jagobainda` and `joseramidev`, from fork `0neCr1t/engine` branch `main-doubles` at
`bf863be3a`. **Both fork and branch are alive**, and the head is also reachable from
upstream as `refs/pull/10/head`, so it is fetchable either way.

**It pays the four costs above, and the way it pays them is the interesting part:**

- **Per-slot state, by moving state off the side and onto the Pokemon.** The diff deletes
  `substitute_health`, all seven boosts, `volatile_statuses`, `volatile_status_durations`
  and `last_used_move` from `Side` and re-adds them on `Pokemon` — "in singles only the
  active slot-0 Pokemon's copy is ever read/written". `active_index` becomes
  `active_indices: [PokemonIndex; ACTIVE_PER_SIDE]`. Switch semantics survive on the
  existing explicit `reset_boosts` / volatile-clear instructions emitted before a switch
  (`src/state.rs:1440`, `:1795`).
- **A compile-time slot count, not a runtime one.** `ACTIVE_PER_SIDE` is 2 under the
  feature and 1 without it (`src/state.rs:14`), plus a new `BattlePosition { side, slot }`
  as "the single abstraction used for targeting", with `opposing_slots()` and `ally(slot)`.
- **A Cargo feature, so singles cannot regress.** `doubles = []` in the crate and
  `doubles = ["poke-engine/doubles"]` in the binding, explicitly "does not imply any
  generation". A `slotted_instruction!` macro adds `slot: u8` only in a doubles build, so
  "behavior and the in-memory layout stay bit-for-bit identical to before"; a new
  `src/decision.rs` (115 lines) aliases `SideChoice` and dispatches, so `mcts`,
  `mcts_threaded`, `search` and `io` are written once for both formats and collapse to the
  singles path at zero cost. **That claim is the thing to verify first, and it is cheap.**
- **A turn as a pair becomes a turn as a pair of `SideAction`s.**
  `SideAction { actions: [MoveChoice; ACTIVE_PER_SIDE] }` (`genx/state.rs:208`), the
  cartesian product of a side's slots minus cross-slot illegals (both slots switching to
  the same benched body); CLI syntax `move;move` with an optional `,<slot>` target suffix.
- **`MoveTarget` goes from 2 variants to 8**: `User, Opponent, Ally, BothFoes, AllAdjacent,
  AllAdjacentFoes, AllOthers, UserSide`, with spread targets backfilled across the move
  table.

**Its tests cover exactly the list this document called "absent, not weakened".** 1,646
lines, 47 cases: `follow_me_redirects_single_target`,
`rage_powder_ignored_by_grass_attacker`, `lightning_rod_redirects_nullifies_and_boosts`,
`storm_drain_...`, `ally_switch_swaps_slots`, `helping_hand_boosts_ally_damage`,
`wide_guard_blocks_spread`, `earthquake_spread_reduction`, plus
`four_actors_resolve_in_speed_order`, `four_actor_speed_tie_branches`,
`trick_room_reverses_order`, `spread_move_faints_both_opposing_actives`,
`double_faint_enumerates_distinct_replacements`, `replacement_lands_in_correct_slot`,
`uturn_sets_per_slot_force_switch`, `snipe_shot_ignores_follow_me`,
`telepathy_avoids_ally_spread`, `friend_guard`/`battery`/`power_spot`,
`intimidate_hits_both_foes`, `mcts_returns_valid_combined_actions`, and
`deserializes_singles_format_state`.

**Coverage is not correctness: two of those 47 fixtures assert rules Showdown contradicts.**
`intimidate_hits_both_foes`' lib-side twin `test_switching_in_with_intimidate` hand-writes a
single-slot expectation and fails in every doubles build — the engine loops both slots and is
right. And `storm_drain_redirects_nullifies_and_boosts` (`tests/test_doubles.rs:1402`) uses
**Surf** — a spread move — and asserts zero damage to *both* side-two slots, which is the
whole-move-redirect model; Storm Drain should absorb for its **holder** only. Its Lightning Rod
twin passes only because it uses Thunderbolt, where redirecting onto the holder legitimately
leaves nothing else hit. Adjudicated against Showdown rather than argued, via the stage-0 case
`storm_drain_does_not_shield_partner`: Showdown redirects the nominal target, boosts the holder,
**and damages its partner** (`|-damage|p2a: Snorlax|400/461`). It began failing in run 3, not
run 4 — established by reversing run 4's two redirect hunks and re-running that one test, which
fails identically. So the current patched tree is 46 pass / 1 fail in `test_doubles`, and in both
cases the fixture is wrong, not the engine. Neither has been rewritten here: correcting another
project's test assertions on the strength of my own fix is a change to flag, not to make quietly.

**Built and run, 2026-09-12** (cargo 1.91.1, the clone above, no rebase, no patches):

| build | lib | `test_battle_mechanics` | `test_doubles` |
|---|---|---|---|
| upstream base `60e1cf8a2`, `--features gen5` | 220 pass | 611 pass | (absent) |
| the fork, `--features gen5` | **220 pass** | **611 pass** | 0 (gated out) |
| the fork, `--features doubles,gen5` | 216 pass, **1 fail** | **0 — gated out** | **47 pass** |

It compiles clean in 15.6 s. Three things this settles:

- **The "singles is unchanged" claim holds at the unit level.** The fork's singles build
  runs the *same test counts as upstream's* — 220 lib and 611 mechanics — and passes all of
  them. The refactor that moved boosts and volatiles from `Side` onto `Pokemon` did not
  break a single upstream singles expectation. That is not the same as bit-for-bit identical
  output on our 180-battle set, which remains measurement 1 below, but it is much stronger
  evidence than an unreviewed PR description.
- **The doubles build's safety net is thin, and this is the real coverage answer.** The
  611-case `test_battle_mechanics` suite is `cfg`-gated *out* of a doubles build entirely
  (48 `cfg(not(feature = "doubles"))` sites against 116 `cfg(feature = "doubles")`). So the
  doubles configuration is guarded by **47 doubles cases plus 216 lib cases, where the
  singles configuration is guarded by 831**. The singles mechanics are not re-asserted
  under a slot-aware board anywhere. That is the gap to close before trusting a doubles arm,
  and it is closed by porting fixtures, not by writing engine code.
- **The one failure is a stale fixture, not an engine bug.**
  `test_switching_in_with_intimidate` (`genx/generate_instructions.rs:9306`) expects one
  `Boost SideTwo Attack: -1`; the doubles build emits **two**, because with
  `ACTIVE_PER_SIDE = 2` Intimidate correctly hits both foes — which is exactly what the
  passing `test_doubles_intimidate_hits_both_foes` asserts. 216 sibling fixtures were
  updated for the slot argument and this one was missed. It is a one-line fix, and it is
  also a fair sample of what a rebase will consist of.

**Why it was closed is not recorded anywhere, and the diff is not the likely reason.**
Five days *before* the PR, pmariglia's own `79f8186f` (2026-06-14) reads: "Remove allocs
from sample_node — **Passing some learnings from doubles back onto singles**." He was
already doing doubles himself. No public branch carries it (all six upstream branches
checked — `somecrap`, `somecrap-multi`, `somecrap-multi-thread`, `hashing`,
`threaded-search`, `test-remove-vloss-fix-ucb`: no `doubles` feature, no `test_doubles.rs`,
no `decision.rs`), so it is local or unpushed. That is inference. What is visible in the PR
and would get it closed on sight regardless: committed Windows build artifacts
(`poke_engine.cp313-win_amd64.pyd`, `cp314-win_amd64.pyd`, `poke_engine.pdb`), a
merge-from-`main` commit in the branch history, a commit message in Spanish, and a 9.2k-line
unsolicited refactor touching every generation from a first-time contributor
(`author_association: NONE`) with no prior issue.

**What is genuinely against it.** It is unreviewed by anyone, including its own upstream.
Its base `60e1cf8a2` (2026-06-14) is **43 commits and 32 files behind** our pinned
`f4e224c`, so it needs a rebase. And it does **nothing** about the combinatorics above:
~250 options a side still means tens of thousands of joint pairs, so a 5000-iteration
budget covers far less of a doubles tree than of a singles one, whatever the mechanics do.

### Is this another Ruby projection?

The reasonable fear, since eight versions of our own board bought parity and never a lead.
The answer is no, and the reason is worth stating precisely, because it is not about
coverage.

**What killed the Ruby projection was not low coverage.** It was two uncalibrated error
sources at once: a hand-written board *plus* evaluation constants borrowed from poke-engine,
where `SUBSTITUTE_VALUE = 75` and `STAGE_VALUE = 30` sit on real mechanisms — a real HP pool
the instruction generator breaks, a real stat multiplier in a real damage formula every ply.
That is why *fixing* coverage made it worse (48 → 41/60 at 0.7.9): pricing attacks correctly
re-priced them against a setup term that was still fake. The board was a **lie** that
evaluate believed, and more search amplified it.

**This fork is not an approximation of poke-engine; it is poke-engine with a slot
dimension** — the same instruction generator, the same damage calc. Its `genx/evaluate.rs`
diff (19+/43-) looks alarming and is **purely mechanical**: every term and every constant
unchanged, re-pointed from `side.attack_boost` to `pkmn.attack_boost` and the active test
widened from `== active_index` to `any(slot)`. The net -24 lines is verbose
`state.side_one.volatile_statuses.contains(...)` chains collapsing to `pkmn....`. Nothing
added, nothing removed.

So the real risk is one thing and it is narrower: **evaluate is singles-calibrated and
doubles-blind.** There is no term for spread coverage, ally support, redirection, Follow Me
denial, or for two healthy actives being worth more than their summed HP. That is a **gap,
not a lie** — and the distinction is the whole lesson of 0.7.9: search papers over gaps and
amplifies lies.

**Our own numbers say coverage is not the binding variable.** poke-engine's *singles*
coverage is already worse than Showdown's and 0.8.0 measured how much: 67–85% of damage
rolls within 3% of this engine's, Knock Off wrong by x3.2, Return by x3.5. It beat the rule
engine by 19 games (p = 0.005). Then closing that gap — the gen 5 build, 78% → 93% within
3% — **did not move the score** (p = 0.80). Internal consistency decided those runs, not
fidelity.

**And the trap in choosing Showdown for its coverage:** Showdown is a complete board with
**no evaluation and no tree**. Picking it for doubles means hand-writing an evaluation
function again — the exact work that failed in Ruby — on a board 400x slower. This fork
offers an evaluation that has already beaten the rules and is merely naive about doubles.

**Three measurements turn the fear into a number, cheapest first:**

1. ~~The singles-identity check by replaying the 0.8.0 180-battle set~~ — **the wrong
   shape, and done properly instead.** A battle replay cannot be a bit-for-bit check here:
   `monte_carlo_tree_search` is unseeded (pmariglia's `79f8186f` passes an RNG through
   precisely so it *could* be seeded "later on if I want to"), which is why 0.8.0 recorded a
   +/-3 run-to-run spread on a 60-battle set. The deterministic check is at the instruction
   level, needs no game, and **passed on 2026-09-12**:

   Both the fork's singles build and its own base `60e1cf8a2` were built `--release
   --features gen9` and run over the 102 states in `data/gen9randombattle.txt`. For each
   state the root option lists were read off `monte-carlo-tree-search` (deterministic even
   though the visit counts are not) and every legal joint pair was passed to
   `generate-instructions`, whose output is fully deterministic:

   | | base `60e1cf8a2` vs fork `bf863be3a`, both singles |
   |---|---|
   | root option lists (both sides, incl. switch targets) | **102 of 102 identical** |
   | instruction sets over every legal joint pair | **4,546 of 4,546 identical** |

   Zero divergence. Moving boosts, volatiles, substitute health and last-used-move off
   `Side` and onto `Pokemon` changes neither what the engine offers nor what it emits, on
   ~4.5k position/action combinations covering damage, status, switches, hazards and end of
   turn. Combined with the 220 + 611 unit tests, the "singles is bit-for-bit unchanged"
   claim is now evidence rather than assertion. Driver: `tools/pe_identity.py`.
2. **A differential test against Showdown on doubles positions** — the `--check`
   methodology of 0.8.0 (median ratio, % within 3%, % within 10%) with Showdown as the
   reference instead of `pbRoughDamage`. This is the only way to get a number for
   "coverage against Showdown", and 0.8.0 already set the bar: within 10% is enough to win.
   **Stage 0 of it is built and run, below. The corpus stage is still open.**

### Stage 0 of the Showdown differential: 13 hand-authored doubles positions

Run 2026-09-12. `tools/showdown_doubles_cases.js` authors 12 positions, one per doubles
mechanic the fork claims, plays each on Showdown as the reference and dumps the position,
the joint action and the outcome to `generated/showdown_doubles_cases.json`;
`tools/pe_doubles_diff.py` rebuilds each position as a poke-engine doubles `State` **using
the exact stats Showdown computed**, runs the same joint action through
`generate_instructions`, and compares. No Realidea doubles harness is involved: Showdown is
both the oracle and the position generator, which is what makes this cheap.

**Three method decisions that the first run forced, and that any repeat must keep:**

- **Determinism by pinning Showdown's PRNG to always-max**, one rule that covers everything:
  the damage roll lands on its maximum, `randomChance(1,16)` for a crit is false,
  secondaries never fire, and speed ties resolve identically every run. The consequence to
  respect is that `randomChance(acc,100)` is then only true when `acc > 99`, so **every case
  move must be 100% accurate with no secondary** — hence Shock Wave rather than Thunderbolt,
  Surf rather than Rock Slide. A miss shows up as zero damage rather than as noise.
- **Absolute damage is not comparable and is not compared.** poke-engine branches on the
  roll and returns weighted outcomes; its most probable branch measures **median 0.879 of
  Showdown's max roll (range 0.343-1.107, only 24% within 10%)** over the 25 hits the two
  engines share. That is a roll model difference and says nothing about doubles. Reading it
  as disagreement is the trap; the first run of this harness fell into it. What stage 0
  compares instead is roll-independent and is the actual doubles question: **which bodies
  took damage at all** (targeting, spread, redirection, Protect-class blocks) and **which
  bodies got which boosts**. A max-roll comparison would need `calculate_damage`, which
  returns the max roll first, exactly as the 0.8.0 `--check` used it.
- **Bodies are keyed by species, never by slot**, or Ally Switch moving a body between slots
  reads as a damage disagreement. The first run showed `('s1', 0): -79`, a body "healing",
  for precisely this reason.

**Result as first run: 11 of 12 agree. Now 19 of 19, zero disagreements** (2026-09-13): the
sole failure was Wide Guard (defect 5, since fixed), and a thirteenth case
`wide_guard_blocks_own_ally_spread` was added to cover a path stage 0 never tested — see
"Own-side area protection" below. Follow Me and Rage Powder redirection, Lightning Rod
redirect + nullify + the SpA boost, the 0.75 spread reduction, Earthquake hitting its own
ally, Telepathy exempting the ally, Quick Guard against priority, Helping Hand, Friend Guard,
Ally Switch and Intimidate's double drop all match Showdown exactly. **Redirection and spread
are not broken, so the stop-rule says proceed.**

**One confirmed engine bug, with its root cause** — the first of fifteen; all fifteen are
tabulated under [Backlog item 3](#3-fix-the-ten-confirmed-defects), nine of them with verified
line numbers, and this section and those following hold the evidence for each. `wide_guard_blocks_spread`: Surf is
`AllAdjacent`, so in gen 5 it hits the attacker's own partner as well as both foes
(confirmed against PokemonDB). Showdown blocks only the guarded side and still damages the
attacker's ally; poke-engine damages nobody. The cause is
`src/genx/generate_instructions.rs:1744-1758`, which applies the guard to the **`Choice`**
rather than to the resolved target list:

```rust
let blocked = (choice.target.hits_multiple_targets() && target_conditions.wide_guard > 0)
    || (choice.priority > 0 && target_conditions.quick_guard > 0);
if blocked {
    choice.remove_effects_for_protect();   // cancels the whole move, not the guarded targets
```

`remove_effects_for_protect` zeroes the move outright, so the half of a spread move that was
never aimed at the guarded side disappears with it. **The same line governs Quick Guard**, so
a priority `AllAdjacent` move is wrong in the same way; stage 0 missed that only because its
Quick Guard case uses single-target Mach Punch.

**A second disagreement, on a channel this comparison deliberately ignores.** In the Ally
Switch case, Showdown has **Snorlax** execute the Tackle that Snorlax chose, from whichever
position it ends up in (70 damage). poke-engine has **Gothitelle** execute it: the same probe
with no Ally Switch gives 24 and 61 damage for slots 0 and 1 (matching their Attack stats,
146 and 256), and with Ally Switch it gives 24 — the slot-1 sub-action performed by the body
the swap moved *into* slot 1. So **poke-engine binds a sub-action to the slot, Showdown binds
it to the body.** Showdown is right: a Pokemon executes its own chosen move regardless of
where it has been moved. This is invisible to the set-based comparison, which asks only who
was hit, and it is the whole of the 0.343 low end of the ratio range. It is also the reason a
future corpus run must compare *which body acted*, not only which body was hit.

**Two of the three disagreements in the first version of this section were the harness, not
the engine.** They are recorded because the mistake is easy to repeat: the projection keyed
slot occupancy off the **pre-turn** snapshot, so after a `Switch` or a `SwapActiveSlots`
mid-stream it attributed damage to the body that had left. That made correct poke-engine
behaviour look like two bugs — damage landing on the body that switched out, and Ally Switch
failing to redirect. `pe_outcome` now replays occupancy through the instruction list, and both
cases agree. A doubles differential must track who stands where *as the turn resolves*.

**A blocker fixed on the way, which anyone doing this work needs.** None of the fork's 19
slotted instruction types print their slot in Debug output (`instruction.rs` was 171+/2-, so
the existing arms were never revised): `Damage SideTwo: 72` is ambiguous between the two
actives, and nothing above is decidable without it. `patches/poke_engine_doubles_debug_slot.patch`
adds a `slot_tag` helper that is empty in a singles build and `:<slot>` in a doubles build,
so **singles Debug output stays byte-identical and the 220 singles unit tests still pass**.
The same ambiguity affects the MCTS root option labels, where `('ember;ember', 12.5, 50)`
appears repeatedly because the `,<slot>` target suffix is not rendered — worth fixing before
anyone tries to read a doubles search trace.

### The corpus stage: 456 random doubles turns, and where the divergence actually lives

Run 2026-09-12. `tools/showdown_doubles_corpus.js` plays 40 random `gen5doublescustomgame`
battles with the same always-max PRNG and dumps every joint-action turn — position, choices,
outcome — to `generated/showdown_doubles_corpus.ndjson` (456 turns).
`tools/pe_doubles_corpus.py` replays each on poke-engine and compares the same
roll-independent projections as stage 0. **Choices are random; movesets are curated**, which
is what keeps the comparison sound: every move in the pool is 100% accurate with no status
and no secondary, because under the pinned PRNG `randomChance(acc,100)` is only true above 99
and a sub-100% move would silently miss on one side while the other branched on its accuracy.

| | compared | bodies damaged agree | boosts agree |
|---|---|---|---|
| all turns | 373 | **73.2%** | **87.1%** |
| holding out Wide Guard turns | 250 | 74.8% | 87.2% |
| **holding out spread-move turns** | 199 | **92.0%** | **93.0%** |
| holding out spread + the absorb abilities | 134 | 91.8% | 95.5% |

**Spread moves are where doubles diverges, and Wide Guard is only one instance of it.**
Holding out the confirmed Wide Guard bug moves bodies-damaged by 1.6 points; holding out
spread moves moves it by **19**. Outside spread, the two engines agree on who was hit in 92%
of turns and on boosts in 93%.

Drilling into the spread turns: the disagreement does **not** depend on which slot attacks
(from slot 0, 49 of 97 turns differ; from slot 1, 69 of 143 — the same rate), so it is not the
slot generalisation. In **39** of the disagreeing turns the body poke-engine fails to damage
is *the attacker's own ally*. Since the isolated stage 0 cases for both Surf and Earthquake
hit the ally correctly, something about the fuller positions suppresses it.

**Re-measured 2026-09-13 with defect 15 fixed** (`patches/poke_engine_doubles_spread_per_target.patch`,
below). Same 456-turn reference `.ndjson`, so only the engine changed:

| | compared | bodies damaged | boosts |
|---|---|---|---|
| all turns | 373 | 73.2% → **80.4%** | 87.1% → 86.9% |
| holding out Wide Guard turns | 250 | 74.8% → **85.2%** | 87.2% → 86.8% |
| **holding out spread-move turns** (control) | 199 | 92.0% → **92.0%** | 93.0% → **93.0%** |
| holding out spread + the absorb abilities (control) | 134 | 91.8% → **91.8%** | 95.5% → **95.5%** |

**The fix is worth 7.2 points of the ~18.8-point spread gap — 38% of it — and both held-out
controls are pinned to the digit** (183/199 and 123/134 bodies, unchanged), which is the
evidence that it moves spread turns and nothing else. Boosts end flat (−1 turn); see the absorb
note under defect 15 for why that number is not an improvement.

> **Both figures in this table are superseded.** The instrument used to produce them was
> charging the engine for 57 turns it cannot represent, and defects 5, 16 and 17 were all
> still open. The numbers to quote are in the next section: bodies 74.1% → **96.8%** and boosts
> 88.0% → **99.7%** across runs 1–8, on the fainted-guarded instrument run 8 introduced.

### The instrument was charging the engine for 57 turns it cannot represent

Found in run 2, and it inflates every figure above. `pe_doubles_corpus.py` skipped repeated
**Protect** under Showdown's stall counter — but gated that skip on `id == "protect"` alone.
Wide Guard and Quick Guard *also* call `onHitSide -> source.addVolatile('stall')`
(`data/moves.ts:20816`, `:14498`), so a body that Wide Guarded last turn and does so again
**fails** under the always-max PRNG, while poke-engine branches on a probability instead
(see the correction to defect 12 below) — so the two are not comparable in either
direction. **57 such turns were compared and charged to the engine.** The skip is now
keyed on `STALL_MOVES = {protect, detect, endure, wideguard, quickguard}` and `compared` drops
373 → 316.

A changed instrument invalidates the old baseline, so the baseline was re-measured under the new
one by reversing the patch and rebuilding — and re-applying it reproduced the fixed numbers
exactly (277/316, 273/316), which doubles as a build-integrity check.

| corrected instrument, 316 turns | bodies damaged | boosts (**superseded in run 8**) |
|---|---|---|
| baseline (patch reversed) | 74.1% (234/316) | 85.8% |
| defects 15 + 5 fixed (run 1 + 2) | 87.7% (277/316) | 86.4% |
| + defects 16 + 17 + Protect-in-spread (run 3) | 95.6% (302/316) | 86.4% |
| + defects 18 + 19 (run 4, redirection + absorb side) | 95.9% (303/316) | 93.4% (295/316) |
| + defect 20 + 23 (run 5, status targeting) | 95.9% (303/316) | 93.4% (295/316) |
| + defect 7 (run 6, Ally Switch body binding) | **96.8%** (306/316) | 93.4% (295/316) |
| **+ defect 6 (run 7, `reset_boosts` slot)** | 96.8% (306/316) | **95.6%** (302/316) |
| spread-held-out ceiling (166) | 90.4% → **97.6%** (162/166) | 92.8% → **98.2%** (163/166) |
| holding out Wide Guard (250) | 85.2% → **96.4%** (241/250) | 86.8% → **95.6%** (239/250) |
| holding out both absorb abilities (172) | **96.5%** (166/172) | **97.1%** (167/172) |

**Runs 1–7 together: bodies-damaged 74.1% → 96.8%, +22.7 points / 72 turns; boosts 85.8% →
95.6%, +9.8 points / 31 turns — the boosts half measured on the instrument run 8 superseded.** Of the bodies figure, +13.6 came from the two spread fixes,
+7.9 from the Protect fixes, +0.3 from run 4 and +0.9 from run 6. Of the boosts figure, +7.0
came from run 4's redirection pair and +2.2 from run 7's `reset_boosts` slot. Run 5 moved neither
headline by design: it fixed status targeting, which this instrument cannot see at all.

**Run 7 moved only boosts, and that is the control working rather than a shortfall.**
`reset_boosts` emits nothing but `Boost` instructions, so a bodies column that does not budge is
the prediction, not the disappointment — and it did not budge anywhere: 306/316 overall, all ten
bodies buckets byte-identical, and all three held-out bodies rows unchanged to the digit
(162/166, 241/250, 166/172). The three held-out **boosts** rows all rose, which is the other half
of the same control.

### Run 8 replaced the boosts instrument, and 12 of the 14 remaining rows were never comparable

Run 7 left 14 disagreeing boosts turns and I characterised three "shapes" among them. Reading the
actual snapshots showed something simpler and worse: **Showdown zeroes a fainted body's boosts**
inside `faintMessages` (`sim/battle.ts:2563` calls `clearVolatile(false)`, which resets `boosts`
outright), while poke-engine keeps them until the replacement switch clears them. Comparing a
dead body's boosts therefore charged the engine for a bookkeeping difference — on **12 of the 14
rows**. My own tool was already inconsistent about this: the **status** projection has always
carried a fainted guard (`pe_doubles_diff.py:89`), and the boosts projection never did.

The divergence is real but **inert**, which is why the instrument is what changed and not the
engine: `evaluate.rs` puts every boost read behind `pkmn.hp > 0` (`:165`, `:198`), so a dead
body's boosts are never scored, and the replacement switch clears them through the now
slot-correct `reset_boosts`. The guard is deliberately **boosts-only** — a body that fainted
genuinely *did* take damage, so applying it to bodies-damaged would hide real disagreements
(battle 5 turn 10 is exactly that shape).

A changed instrument invalidates the old baseline again, so the boosts column was re-measured
under the new one by reversing the patch and rebuilding; re-applying it reproduced the fixed
figures exactly, which doubles as a build-integrity check.

| guarded instrument (run 8), 316 turns | bodies damaged | boosts |
|---|---|---|
| baseline (patch reversed) | 74.1% (234/316) | 88.0% (278/316) |
| runs 1–7 applied | 96.8% (306/316) | 99.4% (314/316) |
| **+ defect 27 (run 8, absorb bypassed both protect gates)** | 96.8% (306/316) | **99.7%** (315/316) |
| spread-held-out ceiling (166) | 97.6% (162/166) | **100.0%** (166/166) |
| holding out Wide Guard (250) | 96.4% (241/250) | **99.6%** (249/250) |
| holding out both absorb abilities (172) | 96.5% (166/172) | **100.0%** (172/172) |

Bodies is bit-identical to the old instrument in every row, which is the proof the guard touched
only boosts. **Boosts is now closed**: the single remaining row is battle 5 turn 10, and holding
out spread turns gives 100.0%, which independently places that row on a spread turn — it is the
KO-threshold artefact described below, not a defect.

**The annotation that found this had a bug of its own, and hand-reading caught it.** The
`--all-fails` fainted marker first reported "0 of 14", contradicting six rows I had already read
by hand. The cause: bodies-damaged entries are plain keys `(who, species)` while boosts entries
are **pairs** `((who, species, stat), amount)` from `dict.items()`, so `k[:2]` returned the whole
pair and no boosts row could ever match — while the bodies rows tagged correctly the entire time.
Had I trusted the tool over the snapshots, the finding would have been inverted.

**Boosts were flat for three runs (85.8% → 86.4% → 86.4%) and moved only in run 4.** I had told
the user that was because the fork "does not model redirection at all". **That was wrong** —
`redirect_target` (`generate_instructions.rs:2196`) implements it thoroughly, and it is wired
correctly. The real faults were two narrow ones, defects 18 and 19 below, and the lesson is to
grep before declaring a mechanic absent.

**Attribution, taken from diffing the two corpus runs rather than asserted.** The tags the fix
targets moved hard — boosts `ability lightningrod` 15/44 → out of the top ten, `ability
stormdrain` 25/110 → 11/110, `ability telepathy` 6/47 → gone, `ability friendguard` 5/95 → gone.
The tags it must not touch are pinned to the digit **as run 4 measured them** (`allyswitch` has
since fallen to 1/11, with defect 7 fixed in run 6): bodies `allyswitch` 4/11, `switch from slot 1`
4/105, `ability friendguard` 3/95 and `protect` 1/73 are all identical before and after.

**Why the spread-held-out control moved in run 3, and why that is not a leak.** For runs 1 and 2
it was pinned to the digit (183/199, then 150/166) and that was the evidence those fixes touched
spread turns and nothing else. Defects 16 and 17 are *not* spread mechanics — they change
single-target Protect turns — so the subset legitimately moves, 90.4% → 97.6%. The control did
its job in both directions: it stayed still when the fix was spread-only and moved when the fix
was not. What it reported then was a higher ceiling, putting the **residual spread gap at 2.0
points** as of run 3. Runs 4–6 raised the ceiling again: it is **0.8 points** today
(corpus 96.8% against a 97.6% spread-held-out ceiling). On the **boosts** metric the same control
read 95.6% against 98.2% as of run 7, which suggested 2.6 points of boosts residual sitting on
spread turns. Run 8's guarded instrument dissolved almost all of it: boosts is **99.7% against a
100.0% spread-held-out ceiling**, so 0.3 points — one row — remain, and that row is the
KO-threshold artefact rather than a mechanic. Bodies is the only metric with a real gap left.

`--without wideguard` returned 213/250 on both instruments in run 2, as it had to: those 57
skipped turns are all Wide-Guard-tagged, so the row could not move. It moves in run 3 for the
same reason the ceiling does.

**Spread is no longer the dominant source of disagreement.** After runs 1–2 the top bucket was
`protect` at 26/73 (35.6%) — first-use Protect, since repeated Protect is skipped — ahead of
spread's 23/150 (15.3%), with `allyswitch` the highest rate at 5/11.

**Run 3 then took Protect apart as well (26/73 → 1/73), and runs 4–6 superseded its successors
in turn.** Run 3 left `allyswitch` 4/11, spread 10/150, `ability stormdrain` 7/110 and Friend
Guard 3/95; after run 6 the bodies standing is **`a body carries boosts` 6/127, spread 6/150,
`ability stormdrain` 4/110, Friend Guard 3/95, `allyswitch` 1/11** — no bucket above 6 turns, and
boosts — 14 turns after run 7 — is still the larger metric of the two. See backlog item 4. Friend Guard stays hard for the same reason throughout: it needs the
**target's partner's** ability, a lookup `ability_modify_attack_against` has no way to express.

### Own-side area protection: verified against Showdown, not reasoned

The fix keys area protection on the *target's* side, which introduces a behaviour the old code
could not express — it only ever read `get_other_side()`. Since a side's own Wide Guard
plausibly protects it from its own partner's Earthquake (Showdown's `condition.onTryHit` has no
check on where the move came from), that had to be measured rather than assumed. New stage 0
case `wide_guard_blocks_own_ally_spread` is built to be decisive: p2 aims both Tackles at p1
**slot 1**, never at the guarder, so slot 0's HP after the turn answers exactly one question.

    p1a Mienshao  271 -> 271   took 0      <- Wide Guarded; spared its OWN partner's Earthquake
    p1b Golem     301 -> 259   took 42     <- the Earthquake user, took the two Tackles
    p2a Snorlax   461 -> 337   took 124    <- no guard on this side
    p2b Machamp   321 -> 216   took 105

Own-side protection is real. Two traps cleared on the way: `hits_multiple_targets()` is exactly
Showdown's `allAdjacent || allAdjacentFoes` in this build (no move assigns `BothFoes` or
`AllOthers` — the only references to either are inside that function), and `flags.protect` is
`true` for Earthquake, Surf and Heat Wave, so mirroring `checkMoveBypassesProtect` narrows
nothing that should be blocked.

**A second confirmed bug, found by the boost comparison.** `Side::reset_boosts`
(`src/state.rs:1795`) reads `get_side(side_ref).get_active()` — slot 0 — and emits
`BoostInstruction::new(side_ref, 0, ...)`, with no slot parameter anywhere. So when a
**slot-1** body switches out carrying boosts, poke-engine clears **slot 0's** boosts instead.
Its own comment says this is deliberate:

```rust
// NOTE (doubles): this resets slot 0's boosts, matching the still-slot-0
// switch mechanic (`switch()` sets `active_indices[0]`). Per-slot boost
// reset on switch/Haze is deferred together with the switch generalization.
```

**The comment is stale in a way worth knowing: `switch()` *was* generalised.** It now finds
the slot holding the outgoing body and replaces there (`state.rs:1933-1957`, with the
matching `reverse_switch`). So the deferral this note justifies itself by no longer applies,
and `reset_boosts` is simply left behind. `reset_boosts` is also what Haze uses
(`genx/choice_effects.rs:1388`), so Haze in doubles clears the wrong body too.

**Two limits of this measurement, both recorded because they look solvable and are not.**

- **"Which body acted" cannot be measured from the instruction stream.** `DecrementPP` is
  only emitted when a move is below 10 PP (`generate_instructions.rs:2488`, an optimisation),
  and `SetLastUsedMove` does not appear for an ordinary move either. So the slot-versus-body
  action binding found in stage 0's Ally Switch case has to be probed case by case through
  damage magnitude. The corpus is blind to it.
- **Showdown's `stall` counter is not inert and cannot be ignored.** It is the only volatile
  the corpus produces (226 occurrences), and its success check is `randomChance(1, counter)`,
  which under an always-max PRNG makes a *repeated* Protect fail. Those 54 turns are skipped
  rather than mistranslated. The other 29 skips are fainted actives.

**Build gotcha:** the bindings need `maturin develop --no-default-features
--features="poke-engine/gen5,doubles"`. Without `--no-default-features` the default
`poke-engine/gen4` is added to `gen5` and the crate fails to compile with duplicate
definitions — which looks like a fork defect and is not one.
3. ~~Its own doubles tests~~ — **done, above**: 47/47 pass, and they say the mechanics work
   as their author believed, not that they agree with Showdown. Measurement 2 is the only
   one that speaks to agreement.

What a replay would still add is statistical, not structural: that a wheel built from the
fork scores within the sampler's spread of the 0.8.0 control. Worth doing when a doubles arm
is actually proposed, not before. Its cost is already known to be more than a rebase of the
engine: **`patches/poke_engine_permanent_fields.patch` does not apply to the fork** (it
fails on `tests/test_battle_mechanics.rs:27`, whose imports moved in the 43 upstream commits
since the fork's base), so the sidecar's own patch has to be re-cut as part of any rebase.

## Where this leaves the study

| Want | Board | Cost a decision |
|---|---|---|
| Singles, today, beats the rules | poke-engine via the sidecar | 10 ms |
| Singles on a second opinion | Showdown | ~4 s at 5000 |
| **Doubles** | Showdown, installed-and-measured | ~4 s at 5000, or well under 1 s for a one-ply maximin |
| **Doubles**, if PR #10 rebases | poke-engine + `--features doubles` | 10 ms *per joint pair budget*, and the pair count is the problem |
| A shippable in-game search | none of these | Essentials one-ply maximin is the only shape, untried |

Showdown is ~400x slower than poke-engine for an identical budget, so it buys nothing for
singles, where the sidecar already wins. It is worth the cost only for doubles, and there
its competition is now PR #10 rather than nothing — a rebase and an unreviewed engine
against a complete board with no evaluation and no tree. The one-ply doubles maximin is comfortably sub-second
on the stock build and is the cheapest real experiment available.

The prerequisite for any of it is on our side, not Showdown's: **a doubles roster, a
doubles harness and a doubles position export out of Realidea do not exist yet.** The
adapter's search and Foul Play paths both decline doubles by design.

### Running PR #10's search before building a bridge: it beats a greedy baseline

Run 2026-09-12. The question was whether a doubles search is worth the adapter work a real
`foul_play` doubles arm would need, and it can be answered without any of it.
**Showdown adjudicates every turn and poke-engine only plans**, so the board is correct by
construction and a loss is the planner's fault rather than the board's — the one thing that
could never be said of the Ruby projection. `tools/showdown_doubles_server.js` holds one
doubles battle behind a JSON-line protocol; `tools/pe_doubles_play.py` drives it with a policy
per side (`mcts` = `monte_carlo_tree_search` on the translated position, most-visited root
action; `greedy` = highest-base-power damaging move at the lowest-HP foe, computed from the
dex data the server reports so it shares no code with the engine under test; `random`).
`tools/showdown_doubles_lib.js` holds the snapshot, PRNG and team pool both harnesses share.

| matchup | result | two-sided exact p |
|---|---|---|
| MCTS as p1 vs greedy | **40-19** (67.8%) | 0.0086 |
| MCTS as p2 vs greedy | **48-12** (80.0%) | 3.2e-06 |
| **pooled, both seats** | **88-31 (73.9%)** | **1.7e-07** |
| greedy vs greedy — the seat control | 28-30 (48.3%) | 0.9 |
| greedy vs random — the baseline control | 32-19 (62.7%) | 0.092 |

60 battles per orientation, ~16,000 visits a decision at 300 ms, zero rejected choices. The
seat control is flat, so running both orientations was necessary and the gap is not a seat
artefact. **The doubles search beats the baseline decisively, in both seats.**

**What this does and does not establish.** It says the search produces coherent doubles play —
worth the bridge — and it says so *despite* the defects above: the planner is working from a
board that agreed with Showdown on 73.2% of turns, mispriced Wide Guard (both since fixed —
96.8% on the corrected instrument after runs 1–8; this measurement predates all of them), and
mis-binds an action across Ally Switch. **So 73.9% is a floor, not a ceiling.** What it does **not** say is
that a doubles `foul_play` arm would beat this study's rule engine. Greedy is a weak opponent —
it only manages 32-19 against random, with nine turn-limit draws — while the Reborn rule
planner at 38/60 is a far stronger heuristic. Beating greedy is a necessary result, not a
sufficient one. The narrowness is also real: 14 curated species, every move 100% accurate with
no secondary, no weather or terrain.

**Two more defects had to be fixed before the search's own decision could be read**, and both
would make any doubles search trace unreadable too:

- **`MoveChoice::to_string` named every sub-action using `side.get_active_immutable()` — slot
  0.** So slot 1's decision was reported with slot 0's moveset: on the shipped example state,
  whose slot 1 knows `watergun/tackle/helpinghand`, the engine reported choosing `ember` and
  `protect`, moves that body does not have. The engine's own API could not say what it had
  decided for its second slot.
- **The target slot was dropped from the label**, so two sub-actions aiming the same move at
  different foes rendered identically — the duplicate `('ember;ember', …)` rows in the MCTS
  output.

`patches/poke_engine_doubles_choice_labels.patch` adds `to_string_slot(side, acting_slot)` with
a `,<slot>` suffix in doubles builds, and teaches the parser to accept `switch <species>` —
which the CLI and the binding both print and neither could read back, **in singles as well**.
After it: 35 root options, 35 distinct labels, **35/35 parse back**, with the 220 singles and
47 doubles tests still passing.

**Harness traps worth keeping**, all found by this run: Showdown reports `battle.winner` as the
player *name*, not the side id; a rejected choice explains itself in `side.choice.error` and
nowhere else; Helping Hand needs an explicit negative ally index (`move 2 -2`) or the whole
choice is rejected; a late-game **fainted active** on a side with an empty bench is a legal
position that the differential translator rightly refuses, and refusing it here silently handed
19 of 107 decisions to the fallback policy — `mon(allow_fainted=True)` now represents it, and
Showdown's `fnt` status must become `none` because poke-engine encodes a faint as `hp=0`.

### Gen 6 with real scraped teams: the search panics, so the measurement cannot be made yet

Run 2026-09-13, after the synthetic-roster objection above. The teams are real:
`extracted/smogon-dump/gen6doublesou.json` holds **425 records, 338 of them complete six-mon
teams**, in the schema `showdown_names.resolve_set` already reads — species, item, ability,
moves, nature, EVs, IVs. The dump also carries `gen9doublesou` (6,136 records, 5,869 complete),
`gen8doublesou` (194), `gen7doublesou` (50) and `gen5doublesou` (183, but only **13** complete
sixes — the gen 5 scene there is largely 2v2 with four-mon teams). `TEAM-CORPUS.md`'s
"doubles excluded" line means they were set aside, not that they are missing.

The harness now plays them: `--teams gen6doublesou` converts each set to Showdown import text
and runs `gen6doublescustomgame`. **The always-max PRNG is dropped for real teams** — it would
turn every Hurricane into a miss — so Showdown's own seeded PRNG resolves accuracy, crits and
secondaries, which is correct for a play measurement and is what the search plans under
natively. With cheap policies it works cleanly: greedy beats random **15-5 over 20 battles,
zero rejections**.

**With the search it does not work, and that is the finding.** On real gen 6 positions
poke-engine panics, repeatedly and on ordinary input:

| panic | what triggers it |
|---|---|
| `cannot mega evolve RHYPERIOR with ASSAULTVEST`, `MEW with ROCKYHELMET`, `TALONFLAME with CHOICEBAND`, `PACHIRISU with SITRUSBERRY`, `LUDICOLO with LEFTOVERS` | a held item that is **not a mega stone**, on a species with **no mega**. The engine attempts a mega evolution anyway and panics on the invalid pair. Present whether the dump's mega species are kept verbatim (`Gardevoir-Mega` holding Gardevoirite) or stripped |
| `Invalid boost value: -11`, `-10`, `-7`, `12`; `Invalid boost number: 14` | thrown from `src/genx/evaluate.rs:107`, i.e. the **state already holds a boost outside ±6** when evaluation reads it. `get_boost_amount` (`generate_instructions.rs:868`) is slot-aware and clamps correctly, so a write path bypasses it. Cause not isolated; `reset_boosts` (slot-0 hardcoded, above) and the switch-time `swap_active_state` are the suspects |

So **PR #10's doubles build is not usable on real gen 6 doubles teams as it stands**, and no
score from it would mean anything: a panicked turn falls back to greedy, so the "search" arm is
partly the baseline. `PanicException` subclasses `BaseException`, so the driver had to catch
that explicitly — an `except Exception` lets an engine panic kill the whole run.

**Two smaller gaps the synthetic pool had hidden**, both now visible as counted fallbacks:
`volatile choicelock` (17 in twelve battles — Choice items are everywhere in real teams, and
poke-engine models the lock as `last_used_move` rather than a volatile, so the translator needs
to set that field instead), plus `flashfire` and `mustrecharge`. And Showdown's status codes are
not poke-engine's names: `slp/par/brn/psn/tox/frz` must become `sleep/paralyze/burn/poison/
toxic/freeze` or the binding panics with `Invalid PokemonStatus`. The pool inflicts no status,
so only real teams reach it.

**Also worth knowing: runs with the search are not reproducible.** `monte_carlo_tree_search` is
unseeded, so the same battle seed produces different lines on each invocation — which is why
one twelve-battle run showed thirteen panics and the next showed none. Any real measurement
here needs enough battles to swamp that, and the panic rate itself varies run to run.

**What this changes upstream in this document.** The 88-31 result stands as what it was — the
search beating a toy opponent on toy teams under a pinned PRNG — but the path to a meaningful
number now runs through fixing these panics first, not through swapping the roster. Real teams
were the cheap part; they took an afternoon and they broke the engine.

### Gen 5 with real scraped teams: 63-17, and the search is only ~85% of it

> **Superseded by run 9's re-run** on a clean equal-size pool with the Choice lock enforced:
> **64-16 (80.0%)**, fallback down to 7.0% and now almost entirely engine panics. The figures
> below are kept as history; the numbers to quote are in "Run 9 re-ran the roster" further down.

Run 2026-09-13. Gen 5 has no mega evolution, so `can_mega_evolve` is never true and the
`mega_evolve` crash above cannot fire — which is what made gen 5 the way through. It also has
the better team supply for this purpose once four-mon brings are allowed:
`gen5doublesou.json` holds **158 four-mon teams** (Smogon's gen 5 doubles scene is largely
**2v2**) against 13 complete sixes, so `--team-sizes 4,6` gives **171 real teams** rather than
13. A four-mon bring is legal in a custom game: team preview's `team 1234` puts two out and
benches two.

| matchup | result | two-sided exact p |
|---|---|---|
| MCTS as p1 vs greedy | **32-8** (80.0%) | 0.00018 |
| MCTS as p2 vs greedy | **31-9** (77.5%) | 0.00068 |
| **pooled, both seats** | **63-17 (78.8%)** | **2.3e-07** |
| greedy vs greedy — seat control | 22-18 (55.0%) | 0.64 |

40 battles per orientation, ~8,000 visits a decision, zero rejected choices, and the two seats
agree to within 2.5 points against a flat control. **On real gen 5 doubles teams the search
beats the baseline decisively.** That is a better-founded version of the 88-31 toy-team figure:
real items, real EV spreads, real accuracy and crits (Showdown's own seeded PRNG, not the
always-max pin), 171 authored teams instead of a 14-species pool.

**But the arm is not purely the search, and the honest figure is on the fallback line.**
`policy_mcts` falls back to greedy whenever the search cannot be used, and it had to:
**about 17% of turns in the first orientation and 7% in the second were decided by the baseline,
not by the search.** Any reading of 78.8% has to carry that.

**A flaw in the instrument, not in PR #10, that this number carries.** `--team-sizes 4,6`
accepted both sizes and then paired at random, and the format is a custom game with no bring-N
team preview — so a four-mon team fielded four against a six-mon team's six. With 13 sixes among
171 teams that is about **14% of battles decided by a two-Pokémon handicap before a move was
chosen**, roughly 11 of the 80. The mismatch is random with respect to which seat holds the
search and both orientations were run, so its expected contribution to the pooled score is
about zero and the seat agreement (32-8 against 31-9) and the flat 22-18 control were subject
to the same noise — the headline is probably not wrong. But it is extra variance that should
not be there, and 11 of 80 battles were not clean. Fixed 2026-09-13: pairing now requires equal
size and the run prints its pool split. **Re-run in run 9 on a clean pool — 64-16 (80.0%), so
the headline survived both corrections rather than depending on them.**

**Why it fell back — a new defect, and the most consequential one for a bridge.** Thirty-five
times in the first orientation the search proposed a move Showdown had **disabled**. The
diagnostic distinguishes the two possible causes deliberately, and it is not the wrong-slot
enumeration: these moves *are* in the body's own move list. They are Choice-locked
(`dracometeor`, `earthpower`, `icebeam`, `psychic`, `outrage`, `boltstrike`, …), and the lock was
handed to the engine explicitly — `mon()` now sets `last_used_move` to `move:<index>` from
Showdown's `pokemon.lastMove`, which is how poke-engine represents a Choice lock and is exactly
what lifted MCTS decisions from 90 to 166 of ~180 when it was wired in. **So doubles option
generation does not enforce the Choice lock it is given**, and a bridge would be handing the
game illegal actions on roughly one turn in six.

**CORRECTED in run 9, and the fault was mine, not the engine's.** poke-engine does not read a
Choice lock off `last_used_move` at all — it reads `Move.disabled`, a field this translator never
filled. The engine was told nothing was disabled and correctly offered everything. The rate is
now zero with no engine change; see defect 4 in the table below and the run 9 section.

Two more panics, neither gen-6-specific:

- `assertion left != right failed: get_two_actives called with...` (5 times) — a doubles-only
  internal assertion, presumably the same slot passed twice.
- `Invalid boost value: -7 / -8`, `Invalid boost number: 8` — the same ±6 escape as gen 6, so it
  is not a generation artefact.

**Two translator facts worth keeping**, both invisible under the synthetic pool:

- **A Choice lock is not a volatile in poke-engine** — but it is **not `last_used_move` either**,
  which is what this bullet used to claim, and the claim cost 22 illegal proposals in 195
  decisions before run 9 caught it. `last_used_move` (serialized `move:<index into that body's
  own move list>`) carries Encore and the Bloodmoon / Gigaton Hammer repeat ban, nothing else.
  The lock rides on **`Move.disabled`**, which the caller fills from Showdown's per-move
  `disabled` flags — as `tools/foul_play_sidecar.py:173` had been doing for singles all along.
- **`mon()` dropped every volatile it claimed to map** (found in run 10, **fixed in run 11**). The
  `VOLATILE` table sent `substitute`, `leechseed`, `taunt`, `encore`, `confusion`, `flashfire`,
  `mustrecharge` and `slowstart` to engine names — implying they were passed — but the
  `Pokemon(...)` call had no `volatile_statuses` argument at all, so the loop over
  `d["volatiles"]` only *validated* them and then discarded them. The binding accepts them
  (`PyPokemon.volatile_statuses`, a real constructor parameter defaulting to empty). **Latent, not
  a measurement error: 0 of the 456 corpus turns carry a volatile at all** — re-checked in run 11
  across bench bodies as well as actives, and the corpus is byte-identical after the fix
  (306/316, 315/316), which is the control that proves it. It cost the *play* harness far more
  than the corpus, since that is where charging and locked bodies live, and it bit run 10's first
  probe, which set `volatiles=["encore"]` through `mon()` and produced four identical cells
  because the Encore never existed.
- **The three unmapped volatiles are retired (run 11), and two of the three needed no mapping at
  all.** `disable` and `lockedmove` were guessed in run 9 to be "cheap to retire"; that was right
  for the first and half-right for the second, and **`twoturnmove` — the largest of the three at 9
  skips — turned out to be inert for a reason worth keeping.**
  - `disable` → **inert**. poke-engine *has* a DISABLE volatile, but nothing reads it to restrict
    a choice: its only non-application use site is an Aroma Veil gate (`genx/state.rs:780`), while
    `move_is_selectable` reads the per-move `Move.disabled` flag that run 9's whitelist already
    fills. The effect was modelled; the volatile was redundant.
  - `twoturnmove` → **inert, and mapping it would have been wrong.** Showdown's condition does
    `attacker.addVolatile(effect.id)` in its own `onStart` (`data/conditions.ts:294`), so a
    charging body carries **both** `twoturnmove` and a volatile named after the move — and it is
    the move-named one poke-engine reads, via `active_is_charging_move_slot`'s `CHARGE_VOLATILES`
    table (`genx/state.rs:1134`). So the fix was to map the **siblings** (`solarbeam`, `fly`,
    `dig`, `dive`, `bounce`, `skullbash`, `skyattack`, `razorwind`, `freezeshock`, `iceburn`,
    `shadowforce`, `skydrop`, plus four later-gen names), each of which is the same string in both
    engines. Once present, `slot_options_doubles` (`:1648`) returns the single charge option,
    which is exactly what Showdown's single-entry request says.
  - `lockedmove` → **mapped, with a recorded approximation.** LOCKEDMOVE *traps* but does not by
    itself force the move; the forcing comes from the whitelist. It is passed with **no duration**,
    because the engine counts lockedmove **up** (0, 1, then at 2 it removes the volatile and
    applies confusion, `generate_instructions.rs:3898`) while Showdown counts a hidden
    `trueDuration` **down** from `random(2,4)`, and the snapshot carries no counter. A lock
    therefore always looks *fresh*, so the search over-estimates how long the body stays locked.
- **Two traps that only became visible once volatiles were actually passed**, both avoided:
  `slowstart` **lost** its mapping (a downgrade from the old table), because the end-of-turn block
  does `slowstart -= 1` and then tests `== 0` (`:3880`) — the duration 0 the snapshot supplies
  goes to −1 and the volatile is **never removed**, a permanently halved-Attack body. Inert beats
  wrong, and it costs nothing: Slow Start is **0 bodies in all 183 gen5doublesou teams**. And
  `substitute` needed its **health** plumbed alongside, since Showdown keeps it on the volatile
  (`effectState.hp`) and poke-engine on the Pokemon (`substitute_health`); sending the volatile
  alone would model a barrier absorbing `min(damage, 0)`, so `body()` in
  `showdown_doubles_lib.js` now emits `subHp`.
- **An unmapped name must keep raising Skip rather than being passed through**, and this is not
  defensive style: `PokemonVolatileStatus::from_str` ends in `_ => Ok(default)` (`src/lib.rs:65`),
  so an unrecognised name does **not** error — it silently becomes `NONE` and is inserted into the
  bitset. The translator's own validation is the only thing between a typo and a wrong state.
  `partiallytrapped` is the remaining unmapped name and is **0/183 teams**.

### Run 9 retired defect 4, and it was never the engine's defect at all

Defect 4 was the one recorded as most consequential for a bridge: the search proposed
Choice-locked moves, so a bridge would hand the game an illegal action roughly one turn in six.
It is now zero — and **no engine code changed**, because the fault was in my translator.

**What the code says, read before probing anything.** `move_is_selectable` (`genx/state.rs:500`)
is the shared legality predicate for singles (`add_available_moves`) and doubles
(`add_available_moves_doubles`). It checks `mv.disabled`, `mv.pp`, Encore, the Bloodmoon /
Gigaton Hammer repeat ban, and Assault Vest / Taunt against status moves — and never looks at the
held item. Neither does upstream: `bf863be^2` has no Choice check and no `move_is_selectable` at
all, since PR #10 only refactored the predicate out of `add_available_moves`. **So this was never
a PR #10 defect, and the engine never claimed to *derive* a Choice lock.** What it offers instead
is `Move.disabled` — a serialized per-move field with its own `DisableMove` / `EnableMove`
instructions, surfaced to Python as `Move(id, pp, disabled)`. Filling it is the caller's job, and
`tools/foul_play_sidecar.py:173`, the singles bridge that plays live, had been doing it correctly
the whole time. `pe_doubles_corpus.py`'s `mon()` built `Move(id=…, pp=…)`, so every move reached
the engine enabled and the engine faithfully offered all of them.

The comment sitting directly beneath that line asserted the opposite — "poke-engine reads the
Choice lock off last_used_move" — and defect 4 was that comment's consequence rather than the
engine's behaviour.

**Settled by experiment rather than by my reading of two Rust functions**
(`tools/pe_doubles_choicelock.py`): one doubles position built twice, identical but for the flag.
Nothing flagged → **16 root options, all four moves reachable**. The three non-locked moves
flagged → **4 options, only the locked move**. The engine honours the field; it was never given
it.

**The fix.** `mon(…, usable=…)` and `build_side(…, usable=…)` take the set of move ids Showdown
will accept and flag the rest; `slot_whitelists()` in `pe_doubles_play.py` derives them from the
server request that arrives with the same position snapshot. Matched **by id, not by index**,
because the two request shapes differ: a Choice lock lists all four moves with `disabled` flags,
while a *locked* move — Outrage, a charging Solar Beam, a Hyper Beam recharge — sends a
single-entry list with the other three absent entirely. Treating "absent from the request" as
unusable lets one rule cover Choice, Taunt, Assault Vest, Disable and locked moves together.
**Both sides' requests are passed, not only the acting one**: the tree models the foe, and a foe
whose lock is ignored is a foe with three options it does not have. Bench bodies are never
constrained — the same `on_field` gate the singles bridge spells out. And a guard leaves a slot
unconstrained *and counted* if request and snapshot move ids turn out disjoint, because disabling
every move on a naming mismatch would be a worse bug than the one being fixed.

**Priced on a fresh 24-battle gen-5 baseline with the engine held constant** (`--teams
gen5doublesou --battles 24 --ms 150 --seed 23`, mcts as p1 against greedy):

| | decisions | illegal Choice-lock proposals |
|---|---|---|
| before | 195 | **22 (11.3%)** |
| after | 207 | **0** |

All 22 carried the "disabled by Showdown" label and none the "not in this body's move list" one,
which rules out defect 8's wrong-slot enumeration as a contributor here; and every affected move
was a damaging one (`icebeam` 8, `uturn` 5, `stoneedge` 4, `dracometeor` 2, `superpower`,
`earthquake`, `closecombat`), so Taunt cannot explain any of them either.

**The no-regression controls.** The corpus is byte-identical — 306/316 bodies, 315/316 boosts,
every bucket unchanged — which is exactly what a change to the shared `mon()` must show, since
the corpus passes no whitelist and calls `generate_instructions` with explicit actions, so
legality never gates it. Stage 0 stays 19/19. No engine code changed, so
`patches/poke_engine_doubles_spread_per_target.patch` is untouched at 1012 lines.

**Two figures that moved and must not be misread.** The win rate went 19-5 → 17-7: that is noise
at n=24 over a changed action space, not a regression — the fix alters which actions exist, so
the games diverge from turn one and the seeds are no longer comparable battle-for-battle. Mean
visits rose 3164 → 5010, the one real side benefit, since fewer illegal options per node buys
depth on the same budget. The `lockedmove` (12 → 11) and `disable` (10 → 8) volatile skips are
unrelated, still unmapped, and cost about 10% of decisions between them.

**A cheap pool that found nothing, worth recording as method.** The Tailwind-filtered pool run 6
recommended for bug-hunting produced **zero** illegal proposals in 8 battles — only 2 of 183
`gen5doublesou` teams carry Tailwind at size 6, so the pool was nearly degenerate. The unfiltered
pool holds 82 Choice items, with 78 of 183 teams carrying at least one. A filter that accelerates
one hunt can erase the mechanic of the next.

**What remains is the engine's half, and it is defect 29.** The engine *does* model a Choice lock
— a holder using a move disables its other moves — but `get_choice_move_disable_instructions`
(`genx/items.rs:260`) stamps the instruction with a hard-coded slot 0, carrying the fork's own
`FIXME(doubles)`, so a slot-1 Choice user locks its **partner**. That was always reachable, since
the engine sets `disabled` itself; this run's fix makes the flag common rather than rare. Neither
it nor its switch-out mirror (`re_enable_disabled_moves`) is visible to the measured instruments,
so both want the probe as their instrument, not the corpus.

### Run 9 re-ran the roster: 64-16 on a clean pool, and the blocker is now panics

The 63-17 headline carried two contaminants: a 4-v-6 pairing handicap in ~14% of battles, and
~17% / ~7% of turns decided by greedy after the search proposed an illegal action. Both are gone —
equal-size pairing, and defect 4 fixed — so this is the first measurement in which the arm is
actually the search. Three arms, one seed, one pool, run **sequentially**, because the MCTS budget
is wall-clock and parallel arms would have silently cut visits per decision.

| arm | result | p (two-sided binomial) |
|---|---|---|
| MCTS as p1 vs greedy | **32-8** (80.0%) | 1.8e-04 |
| greedy vs MCTS as p2 | **32-8** (80.0%) | 1.8e-04 |
| **pooled, both seats** | **64-16 (80.0%)** | **5.9e-08** |
| greedy vs greedy — the seat control | 23-17 (57.5%) | 0.43 |

40 battles an arm, 300 ms a decision, `gen5doublesou`, `--team-sizes 4,6` with equal-size pairing:
**158 teams of size 4 and 13 of size 6**, so 12,403 legal pairings against the 78 a size-6-only
pool allows. **The 78.8% survived its corrections rather than depending on them** — 80.0% now,
both seats landing on an identical 32-8, against a seat control that is a weak 23-17. The same-seat
comparison (MCTS-p1 32-8 against greedy-p1 23-17) is Fisher p=0.053, which is the honest way to
read it: the pooled figure is overwhelming against a coin, and merely suggestive against greedy
*in the same seat*.

**Zero illegal proposals across all 488 decisions in the three arms** — defect 4's fix holding at
scale on real teams.

**The fallback rate is down to 7.0% (34 of 488), and it is now almost entirely engine panics** —
23 of the 34, so **4.7% of all decisions crash the search**:

| panic site | events | status |
|---|---|---|
| `state.rs:1724` `get_two_actives` assert | **19** | defect 3, previously recorded as ×5 |
| `genx/state.rs:43` `Invalid boost number: 7` | 2 | defect 2 — but a **second site**; that row named only `evaluate.rs:107` |
| `state.rs:1946` `attempt to add with overflow` | 1 | **new — defect 31** |
| `mcts.rs:134` / `:135` index out of bounds, len 0 | 1 | **new — defect 30**, since reproduced deterministically |

The remaining 11 fallbacks are unmapped-volatile skips: `twoturnmove` 9 — a third one, previously
unrecorded — and `lockedmove` 2. `disable` did not appear at all.

**The panics track search VOLUME, not team size, and that is the part that matters for a bridge.**
No earlier run panicked once: size-6 pools at 150 ms gave zero both before and after the
Choice-lock fix, and an attribution run on **size-4 teams only at 150 ms produced 0 panics in 122
decisions** (17-3). The roster run differs chiefly in budget — mean visits 16491 against 3762 — so
depth is what reaches the pathological states. The honest caveat is that it also had 3.7× the
decisions, so volume and depth are not fully separated; what is established is that small teams
alone do not produce them, and that **a realistic bridge budget would make this rate worse, not
better.**

**A counting trap in my own reporting, worth keeping.** `grep -c 'engine panic'` counts the
aggregated counter *lines*, not the events, and told me 6 where the true figure is 23 — the stats
block prints `<count>  engine panic: <message>`, so events must be summed from the counts. The
same artefact makes the illegal-proposal figure read 9 instead of 22. A count of a summary is not
a count of the thing.

### Run 10 fixed the dominant crash, and it took four wrong hypotheses to find

Defect 3 — `get_two_actives called with the same position` — was 19 of the 23 panics in run 9's
roster re-run and the largest single reason a decision was not the search's. It is fixed, and the
route matters as much as the answer, because **everything I inferred from reading the source was
wrong and the engine's own output settled it in one step.**

**Four discarded hypotheses**, each internally plausible:

1. **`get_instructions_from_drag`.** Its pool comes from `get_alive_pkmn_indices`, which excludes
   only `active_indices[0]`, so in doubles it includes the body standing in slot 1 — dragging it in
   would duplicate the indices. A **real latent defect**, but not this one: **0 of 183
   gen5doublesou teams carry a drag move** (positive control on the same scan: Protect 174, Fake
   Out 117), so no team can ever use one. I had built a confident chain on it.
2. **Self-redirection.** `redirect_target` skips the attacker outright (`if pos == attacker_pos {
   continue; }`), citing Showdown's `target !== source`.
3. **A stale default.** `State::default()` and the binding both set `target_position` to
   `(SideTwo, 0)` — but the assert fires with `left: 1, right: 1` as readily as `0, 0`, and the
   `:5276` fallback is `.opposing()`, which correctly flips the side.
4. **State corruption / duplicate `active_indices`.** The enriched assert prints
   `active_indices=[P0, P1]`. The indices were healthy the whole time.

**What ended the guessing was instrumenting the engine.** Two temporary `eprintln!`s plus an
enriched assert message produced the answer immediately:

```
DBG setup self-target: move=RECOVER   acting_slot=1 tp=SideTwo slot 1 lum=Move(M3)
DBG same-body damage:  move=EARTHPOWER target_class=Opponent attacker=SideTwo slot 1
                                                              target=SideTwo slot 1
```

Recover legitimately sets `target_position` to its own position (`MoveTarget::User` →
`vec![user_pos]`), and Earth Power is then resolved reading that stale value, never having had a
setup of its own — because the Encore block at `:2504` replaces the whole `Choice` without
refreshing the transient. **The enriched assert is kept**; its absence is what cost four
hypotheses, and it now names both positions and `active_indices`.

**Getting there needed evidence capture, not more reading.** No ply-1 action pair panicked (81 p1
actions × a double pass, then 9 p2 actions — all clean), which proved the fault accumulates across
plies inside the tree. A new `--dump-panics` flag writes the root position whenever the search
panics; 12 states were captured from real play and 4 of them reproduced at 5/5, which turned a
probabilistic bug into a deterministic one.

**Ablation, with its own control.** Removing any one of Encore, Recover, Earth Power, the fainted
slot-0 partner, or p2's empty bench dropped the rate to 0/5. That pattern looked too neat — six
independently necessary ingredients — so I checked whether it was really measuring *reachability*:
at 2500 ms, 8× the budget, the 0/8 variants still never panicked while the control stayed 8/8. The
ablation survived its own control.

| identical arm, seed 101, same pool and budget | before | after |
|---|---|---|
| `get_two_actives` panics | **11** | **0** |
| other panics (`Invalid boost number`, defect 2) | 1 | 1 |
| volatile skips (lockedmove / disable / twoturnmove) | 4 / 3 / 2 | 2 / 3 / 1 |
| **total fallbacks** | 21 of 242 (**8.7%**) | 7 of 235 (**3.0%**) |
| result (p2 = MCTS) | 29-11 | 33-7 |

**The win rate is not the result.** MCTS is unseeded, so 72.5% → 82.5% at n=40 is not attributable
to this fix; what *is* attributable is that 11 decisions previously handed to greedy are now the
search's. Mean visits moved 8787 → 7127, which is positional noise.

**Controls.** Corpus byte-identical at 306/316 and 315/316 — and that is a **no-leak check, not
validation**: Encore, Recover and Earth Power appear **0 times** in the corpus pool and Encore in no
stage-0 case, so neither measured instrument can see this fix at all (run 5's lesson again). Stage 0
re-run and unchanged at 19/19. cargo unchanged from baseline: doubles 216/1 + 46/1 (the two
known-wrong fixtures), **singles fully green at 220 + 611 + 15**, which is the control that matters
for a change that also altered a shared method's visibility. Deliverable patch 1012 → **1081 lines,
still 12 files**, now extracting **two** hunks from `src/genx/state.rs` (the `PROTECT => true` fix
and `legal_targets`' visibility) while the unshipped bindings hunks stay out; it reverse-applies
cleanly.

**Three instrument slips of my own this run, all caught before they reached a conclusion.** A
`maturin` build failed while the wrapping pipe reported exit 0, so a diagnostic run silently used
the *old* module — caught only by printing the real exit code. An `awk /\bside\b/` query matched
nothing because in awk `\b` is a backspace, not a word boundary. And a frequency-sorted `head -10`
of the diagnostic hid whether EARTHPOWER ever appeared at setup — the same truncation error as the
earlier `grep … | head -20` that made me declare a guard absent when `slot_options_doubles:1680`
has one.

### Run 11 retired the last three unmapped volatiles, and two of the three needed no mapping

After run 10 the fallback rate was 3.0% and **6 of the 7 remaining fallbacks were my own
translator**: positions carrying `disable`, `lockedmove` or `twoturnmove` could not be built, so the
search never ran and greedy took the decision. This is the second run in a row whose headline defect
was mine rather than the engine's (run 9's defect 4 was the first), and **no engine code changed**.

**The root cause was one missing constructor argument.** `mon()` validated `d["volatiles"]` against
its `VOLATILE` table and then never passed them — the `Pokemon(...)` call had no
`volatile_statuses` argument at all — so every volatile the table *claimed* to map was silently
dropped, and only the three that raised `Skip` were visible as a problem. The rest were invisible,
including **`taunt`, which is 71 of 183 teams in the play pool**.

**Two of the three needed no engine name, and one of those would have been actively wrong to map.**
`disable` is redundant: poke-engine has a DISABLE volatile but nothing reads it to restrict a
choice, and `move_is_selectable` reads the per-move `Move.disabled` flag run 9 already fills.
`twoturnmove` is a *marker*: Showdown's condition does `attacker.addVolatile(effect.id)` in its own
`onStart` (`data/conditions.ts:294`), so a charging body carries both the marker and a volatile
named after the move — and the **move-named sibling** is what poke-engine reads, via
`active_is_charging_move_slot`'s `CHARGE_VOLATILES` (`genx/state.rs:1134`). Mapping the marker
would have modelled nothing; mapping its siblings was the fix. `lockedmove` does map, and *traps*
without forcing the move — the forcing comes from the whitelist. Full reasoning, prevalence and the
two traps avoided (`slowstart`, `substitute`) are in the translator-facts bullets above.

**Adjudicated the same way as run 10**: against Showdown's source, not against what seemed
reasonable. The probe is `tools/pe_doubles_volatiles.py`, and it runs through `mon()`/`build_side()`
rather than constructing `Pokemon` directly, because **the translator is the thing under test**:

| cell | volatiles given | root options for slot 0 | reading |
|---|---|---|---|
| A | none | 23 options, 4 moves, 2 switches | baseline |
| **B** | `twoturnmove` + `solarbeam` | **3 options, solarbeam only, 0 switches** | the fix: the charge path fires |
| **C** | `twoturnmove` alone | **identical to A** | the marker is inert — mapping it would have been wrong |
| D1 | `lockedmove` | 21 options, 4 moves, **0 switches** | LOCKEDMOVE traps but does not force |
| D2 | `lockedmove` + whitelist `{outrage}` | 6 options, outrage only, 0 switches | both halves reproduce Showdown |
| E | `disable` + whitelist | builds; the omitted move is gone | the whitelist already carried it |
| F | `substitute`, `subHp=100` | builds; `substitute_health=100` read back | health plumbed, not faked |
| G | `slowstart` | identical to A | deliberately unmapped, and must stay so |
| H | `partiallytrapped` | **Skip** | validation intact — see the `from_str` trap |

**Priced on the identical arm** (seed 101, same pool, same 300 ms, engine untouched, so run 10's
"after" column *is* this run's "before"):

| identical arm, seed 101 | run 10 (before) | run 11 (after) |
|---|---|---|
| volatile skips (lockedmove / disable / twoturnmove) | 2 / 3 / 1 | **0 / 0 / 0** |
| engine panics (`Invalid boost number: 7`, defect 2) | 1 | 1 |
| **total fallbacks** | 7 of 235 (**3.0%**) | **1 of 263 (0.4%)** |
| result (p2 = MCTS) | 33-7 | 27-13 |
| mean visits | 7127 | 10450 |

**The fix was on the hot path, not theoretical.** Across the 40 saved transcripts the newly-mapped
states actually occur: **Sky Drop ×8, Outrage with `[[from] lockedmove]` ×3, Taunt ×15** — and Sky
Drop alone is 43 of the 46 charge-carrying teams, which is why `twoturnmove` was the largest of the
three skips.

**The score column went DOWN, and I am not going to launder that.** 33-7 → 27-13 on the same seed
and pool. It is not attributable to this change — MCTS is unseeded, and across three runs at n=40
this same arm has read 29-11 → 33-7 → 27-13, twice moving on changes that could only *reduce*
fallbacks — so the column is noise-dominated at this sample size and the attributable figure is the
fallback count. But there is one mechanism that could genuinely cost play strength and deserves a
control rather than a shrug: the **fresh-lock approximation** means a `lockedmove` body always looks
as though it has the maximum remaining turns, so the search may over-value staying locked. Worth a
seeded or larger-n arm before anyone reads the win rate either way.

**Controls.** Corpus **byte-identical** at 306/316 and 315/316 with identical skip counts — and
here that is a genuine no-leak check rather than validation, because **0 of the 456 corpus turns
carry a volatile on an active *or* a bench body** (re-checked this run, both locations). Stage 0
re-run and unchanged at **19/19, 0 disagree**. No Rust changed, so cargo and the 1081-line patch
are untouched by construction and were not re-run.

**One new defect and one sharpened row.** Passing `taunt` for the first time exposed **defect 32**:
`re_enable_disabled_moves` re-enables *every* disabled move, so a Taunt expiring unlocks a Choice
item — correct on switch-out, wrong on the Taunt path, and **not doubles-specific**, since upstream
singles encodes the lock the same way. And the single remaining panic dumped its root state: **all
seven boosts are zero on all four bodies**, so defect 2's ±6 escape is generated *inside* the tree
rather than handed to it by the translator, which removes my own instrument as a suspect there.

### Run 12 root-caused defect 2 by instrumenting the one mutator

**Status, 2026-09-16: the fix is IN the patch, re-established from a clean clone, and the arm
is re-priced — run 13 below closes both of this run's open ends.** The scratchpad worktree holding the engine
source, the build and the venv was destroyed between sessions before the patch could be
regenerated — the run-12 write-up below was made under that loss and its "not in the patch"
warnings no longer apply. That the write-up was specific enough to rebuild from is the reason
this survived: two file:line sites, the exact replacement text, and a named tracked log to
reproduce against.

**What the defect is.** `ability_end_of_turn` (`genx/abilities.rs:1170`) and `item_end_of_turn`
(`genx/items.rs:880`) both open with `let owner_slot = state.actor_slot();`. That is a **transient
set per actor during move resolution** (`generate_instructions.rs:5295`), so by end of turn it names
whichever body happened to act *last*. Meanwhile every read in both functions goes through
`attacking_side.get_active()` — slot 0 — and there is **not one `get_active_slot` call in either**.
So all twelve `owner_slot` emissions in `ability_end_of_turn` stamped instructions with one slot
while the state they described belonged to another. That breaks apply/reverse: the reversal
subtracts from the slot the *instruction* names, while generation mutated the slot the *read* named.

**Speed Boost turns that into a two-way runaway.** Its `< 6` guard bounds slot 0 while the emitted
instruction accumulates elsewhere, so neither body is bounded:

```
slot 0 Speed 1 +6 -> 7   ...  6 +6 -> 12      in-memory +1 per generation, never reversed
slot 1 Speed -6 -1 -> -7 ... -11 -1 -> -12    one reversal per cycle, never applied
```

and the readers then panic — `evaluate.rs:107` `Invalid boost value: -11`, `genx/state.rs:43`
`Invalid boost number: 7`. **Both signs come from one defect**, which is what defeated four turns of
source reading: I kept looking for an unclamped *negative* write, and there isn't one — all four
emits that bypass the clamp (`SPEEDBOOST`, `INTREPIDSWORD`, `DAUNTLESSSHIELD`, `BELLYDRUM`) **add**.
The negatives are reversals of a positive stamped on the wrong body.

**This also retires a wrong reading that sat in row 2 for four runs.** "The −12 is exactly double the
legal floor, so look for a per-slot drop applied once per target" was mine, and it is wrong twice
over: −7/−8 are one or two steps past the limit rather than doubled, and the −12 is the far end of a
walk, not a doubled application. Belly Drum, the one site that really can emit ±12 in one step, is
**0/183 teams** in this pool and cannot have produced it.

**The method is the transferable part, and it is run 10's lesson applied on purpose.** Reading the
callers produced a closed, correct audit — `Side::apply_boost` (`state.rs:2039`) is the sole mutator
and has no clamp; `get_boost_amount` has exactly two callers; everything else routes through
`apply_boost_instruction`, which clamps against the same slot it mutates — and that audit still
explained only half the evidence. **Instrumenting the single chokepoint found it in one run**: an
`eprintln!` in `apply_boost` that fires on any write leaving ±6 catches every path *by
construction*, including the one the audit missed, and reports the first out-of-range write rather
than whichever reader later trips over it.

**The repro is evidence, not a construction**, and getting it wrong once is worth recording.
`generated/doubles_play_logs_gen5_tailwind/000` is a tracked log where this panic fires on the very
first decision of battle 0, so the opening position alone suffices — no depth to reach. My first
probe built the teams in dump order and reported a confident **0/5**; that log was made with
`--require-move tailwind`, which *rotates the carrier to the lead*, and in both teams the carrier
sits at index 3. Going through `load_dump_teams` with the same `require` reproduces the real leads,
and then it is **12/12**.

| `tools/pe_doubles_boost_range.py`, opening position of the tracked log | before | after |
|---|---|---|
| panics in 12 attempts | **12/12** | **0/12** |
| `DBG boost out of range` writes | many per attempt | **none** |

**The fix**, to be re-applied to a fresh worktree: in **both** `ability_end_of_turn`
(`genx/abilities.rs:1175`) and `item_end_of_turn` (`genx/items.rs:885`), replace
`let owner_slot = state.actor_slot();` with `let owner_slot = 0;` — the slot the functions actually
read. That makes state and instruction agree, which is the condition `reset_boosts` documents as
keeping apply/reverse sound. **Singles is bit-for-bit identical by construction**, since
`actor_slot()` is defined as `0` under `cfg(not(doubles))`, so no `cfg` gate is needed.

**Controls, all run and all green before the loss.** cargo doubles **216/1 + 46/1** — exactly the
recorded baseline, both failures being the known-wrong fixtures
(`test_switching_in_with_intimidate`, `storm_drain_redirects_nullifies_and_boosts`), so no new
failure; singles **fully green at 220 + 611 + 15**, which is the control that matters for a change
in a shared code path. Corpus **byte-identical** at 306/316 and 315/316 with identical skip counts;
stage 0 **19/19, 0 disagree**. **Outstanding at the time: the arm was never re-priced** — it had one fallback
left at seed 101 (defect 2's own panic), so the expected result is 0, and that is a prediction, not
a measurement. **Run 13 measured it: 0.** 

**A separate instrument fact worth keeping: `--ms` can be inert.** `run_mcts_loop` (`mcts.rs:276`)
runs a hard-coded `for _ in 0..1000` batch **before it checks the clock at all**, so any budget
cheaper than one batch buys exactly one batch. At this position 100, 300 and 1200 ms all produced
identically 1000 visits and ~2.2 s of wall time. The probe therefore reproduced 12/12 while
searching ~1000 iterations against the arm's 10450 mean — and it means a small `--ms` in any
measurement here is not the knob it appears to be. Consistent with the older note that 5000
iterations is not a knob either.

### Run 13 re-applied the fix from a clean clone and re-priced the arm — the fallback rate is now 0.0%

Run 12 was a verified fix with no surviving artefact. This run's only job was to make it durable,
and the method generalises: **when an environment is lost, re-establish the finding rather than
trust the write-up.** The write-up was right, but that was not knowable until the control ran.

A fresh `--depth 6` clone of `main-doubles` (head `bf863be`, the same commit) took
`patches/poke_engine_doubles_spread_per_target.patch` cleanly, and the two sites were still at
the recorded line numbers — `genx/abilities.rs:1175` and `genx/items.rs:885`, both still
`let owner_slot = state.actor_slot();`. The patch is regenerated and now **1115 lines** (was
1081), applies and reverses cleanly on a pristine clone, and `debug_slot` and `choice_labels`
still stack on top of it.

**The paired control is what makes 0/12 mean anything**, and the probe's own docstring says so:
a clean run is not evidence, because the panic is probabilistic under an unseeded MCTS. So both
builds were made from the same clone at the same commit with the same wheel recipe, differing
only in those two lines:

| `tools/pe_doubles_boost_range.py 12 300`, opening position of `doubles_play_logs_gen5_tailwind/000` | control (`actor_slot()`) | fixed (`0`) |
|---|---|---|
| attempts panicking | **12/12** — ten `Invalid boost value: -11`, two `-12` | **0/12** |

Every recorded control reproduced to the digit: cargo doubles **216/1 + 46/1** with the two
known-wrong fixtures (`test_switching_in_with_intimidate`,
`test_doubles_storm_drain_redirects_nullifies_and_boosts`) and no third failure; singles
**220 + 611 + 15** (+17 +1) fully green; `cargo check` green for gen1/2/3/4/6, the generations
the patch touches only through `reset_boosts`'s signature; corpus **306/316 bodies (96.8%) and
315/316 boosts (99.7%)**, byte-identical; stage 0 **19/19, 0 disagree**.

**Reading the caller confirmed the fix independently, and that is worth doing before trusting
a two-line change.** The end-of-turn loop (`genx/generate_instructions.rs:3806`) iterates
**sides**, not slots, and gates on `side.get_active()` — slot 0 — so both functions are slot-0
functions by construction. `owner_slot = 0` is the only self-consistent value available to them
*while that loop stands*. It is not the generally correct one: see the defect 23 note below.

**One incidental repair, recorded because it was not intended.** The old patch's `src/genx/state.rs`
hunks carried **new-side** line numbers 25 higher than their own content justifies (`+757` and
`+1705` against old-side `-732` and `-1664`), so it had been exported from a tree holding ~25 lines
in that file that the patch itself never shipped. `git apply` never cared — it matches on the
old-side coordinates and context — which is why this survived unnoticed since run 10. What those
25 lines were is not recoverable and is not guessed at here; what is checkable is that **nothing was
lost**: the per-file hunk inventory is identical except for the two new fix hunks, both
`genx/state.rs` hunks keep the same old-side ranges and sizes, and the behavioural controls
(corpus 306/316 + 315/316, stage 0 19/19) reproduce to the digit. The regenerated patch is
self-consistent, and `debug_slot` and `choice_labels` still stack on it.

**The arm is re-priced, and the prediction held.** Run 12 predicted the last fallback would go to
0; that is now measured. Both arms were run from this session's builds, **sequentially** — the MCTS
budget is wall-clock, so parallel arms would silently cut visits per decision (run 9's rule) — over
the same 40 battles at seed 101, `--teams gen5doublesou --team-sizes 4 --ms 300`, p1 greedy vs p2
mcts. Battle 0's pairing reproduces run 11's transcripts exactly, which is how the arm was confirmed
to be the same one before anything was read off it.

| identical arm, seed 101, 40 battles | control (`actor_slot()`) | fixed (`0`) |
|---|---|---|
| mcts decisions | 247 | 275 |
| engine panics — defect 2, `Invalid boost number: 7` at `genx/state.rs:43` | **1** | **0** |
| **total fallbacks** | 1 (0.4%) | **0 (0.0%)** |
| result (p2 = MCTS) | 29-11 (72.5%) | 30-10 (75.0%) |
| mean visits | 147,660 | 108,480 |

Transcripts are tracked at `generated/doubles_play_logs_gen5_run13{,_control}`; no transcript in
either arm records a fallback the summary does not.

**Three things not to over-read here.** First, **this is not literally run 11's build**: mean visits
are 108k–148k against run 11's 10,450, which is a release build against what must have been a
`maturin develop` debug one. Same source, seed, pool and budget flag; different optimisation level.
That makes it a *harder* test rather than a softer one — run 9 established that **panics track search
volume, not team size** — and the control still panicked at 14x the visits while the fixed build did
not. It is also why the control was re-run here instead of comparing against run 11's recorded 1-of-263.
Second, **the win column is noise** and has now read 29-11, 33-7, 27-13 and 29-11 / 30-10 on this same
arm; the 2.5-point gap is not a result. Third, **the decision counts differ** (247 vs 275) because MCTS
is unseeded and the games diverge from the first decision, so the comparable figure is the fallback
*rate*, not the raw count.

**What remains: defect 1** — `mega_evolve` panicking at `genx/generate_instructions.rs:4301` on any
held item that is not a mega stone — is now the leading known crash, and it did not fire in this gen 5
pool (megas are gen 6).

## Backlog

Recorded, not done. In the order they are worth doing.

### 1. Harvest Showdown's own doubles suite as the bug-finding corpus

The 12 stage 0 positions were authored from the fork's own `tests/test_doubles.rs` names, so
by construction they can only confirm mechanics it already knows about — which is exactly why
11 of 12 passed while the random corpus agreed on 73.2%. Cases I author pass because I authored
them.

**The honest update, after four runs of fixes, is that this argument is now weaker than when it
was written.** Stage 0 is 19 of 19 and the corpus is 96.8%, so the gap between hand-authored and
random has narrowed from ~27 points to ~3.2. The asymmetry is real but no longer dramatic, and
the case for harvesting no longer rests on a large measured gap — it rests on **coverage**: 328
tests exercising mechanics stage 0 never names at all. Showdown's suite is the independent
alternative: **328 individual doubles tests across 113 files** (`test/sim/moves` 150,
`test/sim/abilities` 108, `test/sim/misc` 29, `test/sim` 25, `test/sim/items` 16), authored by
people who have never seen this engine.

By generation: **gen 9 281**, gen 8 19, gen 4 8, gen 7 6, gen 3 5, gen 6 5, **gen 5 only 4**.
So one `--features poke-engine/gen9,doubles` build reaches 281 of 328 and the other six
generations are 47 tests between them — almost certainly not worth six more builds. Note the
study's own rosters are gen 5, where their suite has four doubles tests; this corpus is for
finding bugs, not for measuring the board our arms would actually play on.

**Method: hook the harness, do not parse the files.** A mocha `--require` shim wrapping
`common.createBattle` and `battle.makeChoices` dumps (position before, choices, position
after) for every doubles test as it runs; their assertions still execute and are irrelevant.
`tools/pe_doubles_corpus.py`'s projections then consume it unchanged.

**Costs and limits, from reading five cases:**

- **Terastal and G-Max are out of scope by decision** (2026-09-12). Commander (14 cases),
  Dragon Darts (13) and Sky Drop (9) remain unrepresentable anyway.
- **Triples must be excluded, permanently.** The densest Follow Me case is
  `gameType: 'triples'`, which poke-engine can never do. The `gameType: 'doubles'` count is
  already the ceiling.
- **Choice syntax the current translator does not handle**: ally targets (`move pollenpuff -2`),
  `mega` (`move pursuit mega -2`), and `'auto'`. Ally targeting is the one needing thought,
  since poke-engine resolves allies through `MoveTarget::Ally` rather than a slot suffix.
- **Roughly two in five sampled cases assert on `battle.getDebugLog()` or an `onEvent` hook
  rather than on end state** (Dancer's activation order, Neutralizing Gas's ability message).
  The HP/boost projections would score those "agree" while missing what the author cared
  about, so a harvested case measures less than its author intended. Do not claim otherwise.
- **Yield will be well below 328.** Of five sampled cases only one (Follow Me) targets a
  mechanic poke-engine plausibly implements. The skip accounting is the headline output, not
  an inconvenience.

Their suite and the random corpus answer different questions and neither replaces the other:
theirs is adversarial and independently authored, so it finds bugs; ours is ordinary play over
normal positions, which is what a search actually encounters, and is where the 73.2%/92.0%
figures come from — those being the *original* corpus measurement, before the corrected
instrument and runs 1–8 took it to 96.8% against a 97.6% ceiling.

### 2. Replace the play harness's synthetic roster with `doubles_a`

**The teams in the 88-31 run are not taken from anywhere — they were authored for that harness
and they are its weakest part.** `POOL` in `tools/showdown_doubles_lib.js` is 14 species picked
for mechanic coverage (Seaking for Lightning Rod, Gastrodon for Storm Drain, Clefable for
Friend Guard and Follow Me, Musharna for Telepathy, Mienshao for the two area guards,
Gothitelle for Ally Switch), built as `Level: 100 / EVs: 0 HP / Serious Nature` with **no items**
and four moves each drawn from a pool restricted to 100%-accurate secondary-free moves by the
always-max PRNG. So two of the things that decide real doubles — items and speed control — are
absent, along with weather, status and residual damage. The search beat a toy opponent on toy
teams; nobody should read 73.9% as "it plays good doubles".

The study already has the right fixture: **`adapters/reborn/Doubles_Teams.rb` (`doubles_a`)**,
24 sets across offense/balance/bulky/speed, *"derived from the public Pokemon Showdown Gen 8
Doubles OU set data"* — Sitrus Berry, Life Orb, Assault Vest, Weakness Policy, Fake Out,
Tailwind, Quiver Dance, Rage Powder. Because they come *from* Showdown data they translate back
to Showdown sets almost directly. Two known obstacles:

- the fixture's `ability` field is an **index**, not a name, so it needs a dex lookup per species;
- real sets carry sub-100% moves (Muddy Water, Hurricane, Heat Wave), which the always-max PRNG
  turns into silent misses. Either the determinism scheme relaxes to a seeded PRNG compared
  against poke-engine's branch *set* rather than one outcome, or those sets play with known
  misses and the harness says so.

Doing this is what would make the play result mean something: same referee, same search, real
teams. It is more valuable than re-running the toy version with transcripts attached.

### 3. Fix the thirty-three confirmed defects — 16 resolved (2, 3, 4, 5, 6, 7, 10, 11, 15, 16, 17, 18, 19, 20, 23, 27 — rows 10 and 11 are symptom-level and were closed by the site-level fixes; row 2 is now in the patch and re-established from a clean clone, see run 13), 17 open

Every line number below was read out of the `main-doubles` clone, not remembered. Three are
crashes, so they stop a bridge outright; seventeen are silent wrong answers, which is worse to ship;
two are cosmetic-but-blinding, in that they make the search's own decision unreadable; one wastes
the search's own budget; and one has no site yet, which is why it is the largest. Most
are small and localized. All
are doubles-only — the singles board is byte-identical (§ measurement 1), so nothing
here is a regression, only unfinished work.

**Crashes.** A panic in the planner is not recoverable from the caller's side, and
`PanicException` subclasses `BaseException`, so a driver that catches `Exception` dies with it.

| # | site | trigger |
|---|---|---|
| 1 | `genx/generate_instructions.rs:4289` `mega_evolve` | computes `act_slot`, discards it, then reads `side.get_active()` — slot 0 — and panics at `:4301` on any held item that is not a mega stone (`RHYPERIOR`/`ASSAULTVEST`, `TALONFLAME`/`CHOICEBAND`, …). Note the second, quieter half: were slot 0 *also* holding a stone, this would mega-evolve the wrong body and not panic at all |
| 2 | `genx/evaluate.rs:107` **and `genx/state.rs:43`** | `Invalid boost value: -7 / -8 / **-11 / -12**` at the first site, `Invalid boost number: 7 / 8` at the second. Boosts escape the ±6 clamp somewhere upstream and blow up at whichever reader reaches them first — **run 9's roster re-run panicked twice at `genx/state.rs:43`, so evaluation is not the only victim and "only blow up at evaluation" was too narrow**. Seen in gen 6 **and** gen 5, so not generation-specific. The −12 (`doubles_play_logs_gen5_seed23/002`, turn 1) matters: it is exactly **double** the legal floor, so this is not a clamp that is off by one or two but drops being stacked with no bound at all — look for a per-slot drop applied once per target. **Run 11 narrowed where to look**: `--dump-panics` captured the root state of the surviving `Invalid boost number: 7` and **all seven boosts are zero on all four bodies**, so the escape is generated *during the search* and not supplied by the translator — which also clears my own instrument as a candidate. **ROOT-CAUSED AND FIXED 2026-09-14 (run 12); IN THE PATCH AND RE-ESTABLISHED FROM A CLEAN CLONE 2026-09-16 (run 13), with a paired control 12/12 → 0/12 built from the same commit differing only in these two lines.** Cause: `ability_end_of_turn` (`genx/abilities.rs:1175`) and `item_end_of_turn` (`genx/items.rs:885`) both derive `owner_slot` from `state.actor_slot()` — a transient set per actor during move resolution, hence by end of turn a leftover naming whichever body acted LAST — while every read in both functions is `attacking_side.get_active()`, slot 0, with not one `get_active_slot` call between them. So instructions were stamped with one body and described another, which breaks apply/reverse: the reversal subtracts from the slot the instruction names while generation mutated the slot the read named. Speed Boost makes it a runaway because its `< 6` guard bounds slot 0 while the instruction accumulates elsewhere (`slot 0: 1 +6 -> 7 … 6 +6 -> 12`, `slot 1: -6 -1 -> -7 … -11 -1 -> -12`). **Both signs come from this one defect**, which is why source-reading failed: all four emits that bypass the clamp ADD, and the negatives are *reversals of a positive stamped on the wrong body*. **The "exactly double the floor" reading above was mine and is wrong** — −7/−8 are one or two steps past the limit, and Belly Drum, the only site that can emit ±12 at once, is 0/183 teams here. Found by instrumenting `Side::apply_boost`, the sole mutator, after a correct-but-insufficient caller audit; deterministic repro `tools/pe_doubles_boost_range.py` on the opening position of the tracked `doubles_play_logs_gen5_tailwind/000`, **12/12 panics → 0/12**. Controls green: cargo 216/1 + 46/1 (baseline), singles 220 + 611 + 15, corpus 306/316 and 315/316 byte-identical, stage 0 19/19. Fix: `let owner_slot = 0;` in both functions; singles identical by construction — and confirmed independently in run 13 by reading the caller, which iterates SIDES behind a slot-0 hp guard, so slot 0 is the only self-consistent value while that loop stands. **RE-PRICED 2026-09-16 (run 13) on the identical arm, and the prediction held: the last fallback is gone — control 1 panic in 247 decisions (this exact site, `genx/state.rs:43`) vs fixed 0 in 275, total fallbacks 0.4% → 0.0%** |
| 3 | **FIXED 2026-09-14 (run 10)** — cause at `genx/generate_instructions.rs:2504`, assert at `state.rs:1722` | `assert_ne!(a_idx, b_idx, "get_two_actives called with the same position")` — reached in ordinary play (×5 in the gen 5 run). **Run 9's roster re-run makes this the dominant crash by a wide margin: 19 of the 23 panics across 488 decisions, panicking at `state.rs:1724` with `left: 0, right: 0` — both positions resolving to party index 0.** Once the Choice lock stopped masking turns, this became the single largest reason a decision is not the search's. **Root cause, found by instrumenting the engine after four wrong hypotheses: Encore substitutes the move but not its TARGET.** `generate_instructions_from_move` holds the only whole-`Choice` replacement in `src/genx/` — `*choice = MOVES.get(…).clone()` — which swaps in the encored move, `target` class included, while `state.target_position` still holds what the per-actor setup (`:5276`) computed for the move the player actually *chose*. Choosing RECOVER (`MoveTarget::User`, whose nominal target correctly **is** the user's own position) while locked into EARTH POWER (`MoveTarget::Opponent`) therefore leaves a damaging foe-move aimed at its own user, and the damage path calls `get_two_actives(attacker, attacker)`. The state is **not** corrupt — the enriched assert prints `active_indices=[P0, P1]`; the party indices matched because attacker and target were the *same position*. Singles never needed a refresh: its `defender_position` ignores `target_position` and returns the opposing slot 0, so a substituted move always targeted the foe — an unfinished doubles conversion, the family of defects 6, 14, 20, 23 and 26. **Adjudicated against Showdown, not assumed:** `sim/battle-actions.ts:228` runs the `OverrideAction` event and then re-derives the target with `target = this.battle.getRandomTarget(pokemon, baseMove)`. Fix re-derives via `legal_targets` (now `pub(crate)`), the same primitive option generation uses, so the swapped-in move gets a **living** foe — which matters rather than being theoretical, since in the captured state the directly-opposite slot is the fainted one and `.opposing()` would have aimed at a corpse. Showdown picks at random among legal targets where this takes the first: a recorded simplification, like `redirect_target`'s speed-tie note. Priced on the identical arm (seed 101, same pool and budget): **11 `get_two_actives` panics → 0**, total fallbacks 21 of 242 (8.7%) → 7 of 235 (**3.0%**). Probe `tools/pe_doubles_encore_target.py`; 12 captured real positions went 5/5 → 0/6 |

**Silent wrong answers.** These return a plausible result that is wrong, which the differential
caught only because Showdown was sitting next to it.

| # | site | defect |
|---|---|---|
| 4 | **FIXED 2026-09-13 (run 9)** — *my own translator*, `tools/pe_doubles_corpus.py` `mon()` | **The Choice lock was never enforced because I never passed it.** This row used to read "`last_used_move` is supplied and is exactly how poke-engine encodes the lock"; that claim is wrong in both halves. `last_used_move` carries Encore and the Bloodmoon / Gigaton Hammer repeat ban and nothing else, and `move_is_selectable` (`genx/state.rs:500`) never consults the held item — in the fork **or upstream**, since `bf863be^2` has no such check either, so this was never a PR #10 defect. What the engine actually reads is `Move.disabled`, a serialized per-move field with its own `DisableMove` / `EnableMove` instructions, exposed to Python as `Move(id, pp, disabled)`. `mon()` built `Move(id=…, pp=…)`, so every move reached the engine enabled and the engine correctly offered all of them; `tools/foul_play_sidecar.py:173` — the **singles** bridge that plays live — had been passing it correctly the whole time. Fix: `mon(…, usable=…)` and `build_side(…, usable=…)` take the set of ids Showdown will accept and flag the rest, threaded from the server request by `slot_whitelists()` in `pe_doubles_play.py`, matched by **id rather than index** because a Choice lock lists all four moves with `disabled` flags while a *locked* move (Outrage, a charging move, a Hyper Beam recharge) sends a single-entry list instead. Both sides are passed, not only the acting one, since the tree models the foe too. Priced on a fresh 24-battle gen-5 baseline with the engine held constant: **22 illegal proposals in 195 decisions (11.3%) → 0 in 207**, with the corpus byte-identical (306/316, 315/316) and stage 0 unchanged at 19/19. Probe `tools/pe_doubles_choicelock.py`. **The engine half that remains is defect 29** |
| 5 | **FIXED 2026-09-13** — `genx/generate_instructions.rs:1744` | Wide Guard / Quick Guard was applied to the shared `Choice` via `remove_effects_for_protect()`, cancelling the **whole** move. But both are *side conditions* and cannot protect anyone on the other side, so the half aimed at the attacker's own ally was thrown away. Was the one stage 0 disagreement (`wide_guard_blocks_spread`); **stage 0 went to 13/13** (19/19 today — runs 4, 5 and 6 each added a case, run 7 two, run 8 one). Fix: `area_protection_blocks(state, choice, pos)` keyed on **`pos.side`**, applied per position in the spread loop, with the whole-move cancel kept only for the single-target case where it is correct. **Extended in run 3:** that first fix covered only the *side conditions*, and the identical mechanism at `:1842` applies to the per-body **protect volatiles** — so slot-0 Protect + Earthquake still did nothing at all, slot-1 Protect still left the protecting body damaged, and a protecting **ally** was still damaged. `area_protection_blocks` now also checks PROTECT / SPIKYSHIELD / BANEFULBUNKER / BURNINGBULWARK / SILKTRAP — deliberately *not* `PROTECT_VOLATILES`, which also contains ENDURE, and Endure does not stop damage, it survives it at 1 HP |
| 6 | **FIXED 2026-09-13 (run 7)** — `state.rs:1795` `reset_boosts` | read `get_active()` — slot 0 — and emitted `BoostInstruction::new(side_ref, 0, …)`, with no slot parameter anywhere. Both halves agreed with each other, so apply/reverse stayed sound and nothing crashed; the function simply described the **wrong Pokémon** whenever the slot was 1. **Symmetrical, and both halves matter:** with boosts on slot 0 a slot-1 switch *wiped a body that never left the field*, and with boosts on slot 1 that body's own switch *cleared nothing, so its boosts came back with it later*. **Three callers wanting three different bodies** is why the parameter belongs to the caller: a switch means the slot that is LEAVING (`actor_slot()`, now hoisted so the reset and the `Switch` instruction read one expression), Clear Smog means the RESOLVED TARGET (`def_pos`, the same target-class-versus-resolved-position error as defect 19), and Haze means EVERY living active — four slots in doubles, not two, reusing `living_positions_on_side` so a body that fainted earlier in the turn keeps its boosts exactly as Showdown's `getAllActive()` leaves it. Priced: boosts 93.4% → **95.6%** (302/316) with `switch from slot 1` 9/105 → **2/105**, while all ten *bodies* buckets stayed byte-identical — the correct no-leak control, since this function emits nothing but `Boost`. Stage 0 16 → **18/18** via two new cases, the only instrument that can see Haze or Clear Smog at all. Probe `tools/pe_doubles_resetboosts_slot.py`. The `NOTE (doubles)` comment justified the deferral by "the still-slot-0 switch mechanic", and that had already stopped being true: `switch()` was generalised at `state.rs:1933` |
| 7 | **FIXED 2026-09-13 (run 6)** — `genx/generate_instructions.rs:4832` and `:5218` | **A sub-action was bound to the slot rather than the body**, so when Ally Switch moved a body mid-turn the *wrong Pokémon executed its move*. `Actor` carried only a `position`; it now also carries `body: PokemonIndex`, and the slot is re-resolved from it at execution time. **Targets deliberately still follow the slot** — the corpus proves a foe's single-target move follows the position through a swap (Gengar's Shock Wave aimed at slot 0 hits whoever ends up in slot 0: battle 24 turn 3, battle 39 turn 1), the opposite rule from the actor's — and ordering stays pre-swap, as Showdown locks it at turn start. Priced: the `allyswitch` bucket went 7/11 → 10/11 and the corpus 95.9% → **96.8%**; stage 0 15/15 → **16/16** via the new case `ally_switch_moves_the_body_not_the_action`. **The measurement that worked:** "which slot took damage" is useless here, because a spread move excludes whichever slot the engine *believes* is acting, so re-pointing the actor merely moves which body is spared. Damage **magnitude** is the independent channel — slot 0 Surfer at SpA 400 beside slot 1 Switcher at SpA 100 gives **27 damage with Ally Switch against 111 without**, same bodies, same move. Probe `tools/pe_doubles_allyswitch_body.py` |
| 15 | `genx/abilities.rs:2633` + `genx/generate_instructions.rs:1731` / `:2551` | **The root cause of defect 10.** Ability immunity is applied by *zeroing the shared `Choice`*, once, against the **nominal** target: Levitate sets `attacker_choice.base_power = 0.0`, `ability_modify_attack_against` runs once inside `before_move`, `damage_calc.rs:588` turns zero base power into `Some((0, 0))`, and `check_move_hit_or_miss` turns that into `percent_hit = 0.0` — all of it at `:2551`, **before** the spread expansion at `:2609`. Two consequences, in opposite directions: **(A)** an immune body in the nominal slot makes the entire spread move miss, so its *ally and the other foe take nothing*; **(B)** ability immunity is never consulted for any other position, so an immune body in slot 1, or an ability-immune ally, **takes full damage**. Type immunity escapes (A) only because it lives inside `calculate_damage`, which the per-target loop re-calls with `state.target_position` set — `damage_calc.rs` contains no `LEVITATE` at all. Measured with `tools/pe_doubles_spread_classes.py` |
| 14 | `genx/choice_effects.rs:213` + `genx/generate_instructions.rs:5145` | **Fake Out and First Impression read and write slot 0's move history, not the acting body's.** The restriction is modelled through `last_used_move` — `Move(_)` means the body has already acted, so the move loses its effects — but both the check (`attacking_side.get_active_immutable()`) and the reset (`get_side(…).get_active().last_used_move = Switch(P0)`) go through `get_active()`, which is slot 0. `tools/pe_doubles_fakeout_slot.py` shows the outcome depends *entirely* on slot 0's history and not at all on the user's, wrong in **both** directions: a slot-1 body that has been out for turns keeps a live Fake Out, and a freshly switched-in one loses it. Seen in play (`seed23/004` turn 3): Crobat had just switched into slot 0, so the search ranked Scrafty's dead Fake Out **top**, Showdown failed it, and Scrafty died that turn. The write is the worse half — using Fake Out from slot 1 stamps `Switch(P0)` over **slot 0's** history, and since defect 4's Choice lock is read from the same field, that is a candidate contributor to it |
| 12 | **CORRECTED 2026-09-13** — `genx/generate_instructions.rs:2143` | **The counter is NOT absent, as this row previously said: it is modelled per-SIDE and probabilistically.** `side_conditions.protect` feeds `CONSECUTIVE_PROTECT_CHANCE.powi(count)` (1/2 in gen 5, `:89`) and increments at end of turn (`:11528`). Two faults follow. (a) It is a **side** condition, so in doubles both bodies share one counter — one body Protecting twice and two bodies Protecting once are indistinguishable. (b) Showdown under the always-max PRNG fails the repeat *deterministically* while poke-engine emits a probability branch, so such turns are not comparable in either direction (why 57 + 54 corpus turns are skipped). The play consequence below stands unchanged: **the search loops on a move that cannot work.** In `doubles_play_logs_gen5_seed11/002` Metagross Protects on **fifteen consecutive turns** (11–25), and Showdown fails every second one (`Protect [[still]]` / `IT FAILED`). The search puts 8266 of 14000 visits on it on turn 14 — a turn on which it had already failed — and re-picks it at the same weight the next turn and the next, while Metagross is ground from 364 to 19 and then loses. Known before as a *measurement* nuisance (it is why 164 corpus turns were skipped); these logs show it is a **play** defect that throws games |
| 16 | **FIXED 2026-09-13** — `genx/state.rs:760` | **Only the first-ACTING body on a side could Protect.** `volatile_status_can_be_applied` gated `PROTECT` on `first_move` (fed from `attacker_choice.first_move`, `generate_instructions.rs:653`), which is a per-**side** notion — so at most one sub-action a side carries it, and when both bodies Protect the second one's volatile is **dropped silently** and that body takes the hit. Showdown's actual rule is `onTry: !!this.queue.willAct()` (Protect fails only when nothing is left to act), so `first_move` was a singles proxy that is quietly destructive in doubles. Isolated by `tools/pe_doubles_protect_slot.py`: it is **order, not slot** (E1 makes slot 1 the faster body and slot 1 wins), the gate is per-side not global (E2/E3 — being outsped by both foes changes nothing), a lone Protect always worked (E4), and D5 is the control that rules out "one self-action per side" since two Swords Dances both land. Found from corpus battle 33 turn 8, where Showdown protects both bodies and poke-engine protects one. Fixed doubles-gated to `true` |
| 17 | **FIXED 2026-09-13** — `genx/generate_instructions.rs:3992` | **A protect volatile on slot 1 was never removed at end of turn.** The cleanup scanned only `side.get_active()` — slot 0 — and hardcoded slot `0` in its `RemoveVolatileStatus` (`:4005`, `:4009`), so a slot-1 Protect persisted for the rest of the battle: a body **permanently immune** in the search's model, and one that never fed the consecutive-protect counter. Visible as the *absent* `RemoveVolatileStatus SideTwo:1` in probes E1/E4 against the slot-0 cases — the missing instruction was half the finding, which is why that probe prints whole instruction lists rather than grepping for `Damage`. Fixed by looping slots; needs no `cfg` because `ACTIVE_PER_SIDE == 1` makes singles identical by construction. The counter stays per-side on purpose — that is defect 12(a) and needs a per-body field |
| 18 | **FIXED 2026-09-13** — `genx/generate_instructions.rs:2214` | **Ability redirection was not field-wide.** `redirect_target` set `target_side = nominal.side` and scanned only that side for Lightning Rod / Storm Drain. In Showdown both register **`onAnyRedirectTarget`** (`data/abilities.ts:2352`, `:4645`), not `onFoeRedirectTarget`, so a holder draws a matching move from **any** source — including its own ally's move aimed at a foe. Found from corpus battle 1 turn 0: p1a Gengar aims Shock Wave at a foe and its partner p1b Seaking (Lightning Rod) pulls it in; Showdown gave `spa +2` (one drawn from the ally, one from a foe) where the engine gave `+1`, and in the isolated battle 1 turn 3 — a single ally-sourced Electric move — the engine produced **no boost at all**, which is what ruled out a pure wrong-side explanation. Follow Me / Rage Powder / Spotlight are the deliberate contrast: they register `onFoeRedirectTarget`, so scanning the target's side was already correct for them, and run 4 added that guard explicitly. Showdown's `onTryHit` guards `target !== source`, so the fix skips the attacker's own position. Precedence when both sides hold one is a documented simplification (target's side first; Showdown resolves it by holder speed) |
| 19 | **FIXED 2026-09-13** — `genx/generate_instructions.rs:1000` and `:1164` | **The absorbed boost/heal's SIDE came from the target class, not the resolved target.** Both resolvers took the **slot** from `defender_position` (correct) but the **side** from `target.affected_side(attacker)` (wrong). Every absorbing handler hardcodes `target: MoveTarget::Opponent`, which is right in singles — the absorber is always the opponent — and wrong in doubles whenever the absorber is the attacker's own **ally**, reached by a spread move or by defect 18's redirection. The signature is a boost on the **mirrored slot of the wrong side**: corpus battle 2 turn 0 has Blastoise (p2b) Surf into its ally Gastrodon's Storm Drain, Showdown boosts s2 Gastrodon, the engine boosted s1 Gothitelle. **Ten abilities share the convention** — Lightning Rod, Sap Sipper, Motor Drive, Wind Rider, Well-Baked Body, Storm Drain (boost) and Earth Eater, Water Absorb, Dry Skin, Volt Absorb (heal). The fix keeps user-side classes (`User`/`UserSide`/**`Ally`**) on `affected_side`, because an `Ally` move's resolved position defaults to `position.opposing()` (`:5081`) and trusting it would send Helping Hand across the field. Singles is identical by construction, since `defender_position` there is a hardcoded opposing slot 0 |
| 20 | **FIXED 2026-09-13 (run 5)** — `genx/generate_instructions.rs:815` | **A status aimed at slot 1 landed on slot 0 — and so did the immunity check.** `get_instructions_from_status_effects` emits with `target_slot` but reads and mutates through `target_side.get_active()` and `active_indices[0]`, both hardcoded slot 0. On the `ChangeStatus` path those two agree with each other — it mutates slot 0 *and* reports slot 0's party index — so that half is a wrong-body bug, not a state/instruction mismatch; the apply/reverse break is the Lum/Chesto branch alone, below. (An earlier draft of this row claimed the mismatch for the whole resolver; reading the code corrected it.) Related to the older "every status move applies to slot 0" finding; this is the specific site. **It was three faults, and the reason run 4 left it alone was sound**: `immune_to_status` (`:732`) took **no slot at all**, so fixing only the write would have checked slot 0's immunity and then written slot 1 — a failure that did not previously exist. So the two landed together, the function gaining a `target_slot`. Probed with `tools/pe_doubles_status_target.py`: (A2) a status aimed at slot 1 now emits `ChangeStatus SideTwo-P1`; (B1) an already-statused slot 0 used to make the move emit **no instructions at all** and now paralyzes slot 1; (B2/B3) the Lum/Chesto branch used to consume **slot 0's** berry when slot 1 was aimed at, and to leave slot 1's own berry uneaten — the one place this defect broke apply/reverse rather than merely hitting the wrong body. **Adjudicated by Showdown**, not by reasoning: new stage-0 case `thunder_wave_lands_on_the_slot_aimed_at` disagreed before the fix (Showdown paralyzed Gengar, poke-engine paralyzed Blastoise) and agrees after, taking stage 0 to 15/15 |
| 21 | open — `genx/generate_instructions.rs:628` | **The volatile resolver shares defect 19's side convention.** `get_instructions_from_volatile_statuses` resolves the side via `affected_side` while taking the slot from `defender_position`, so a spread move's `Opponent`-target volatile secondary landing on the attacker's own ally goes to the wrong side. Left unfixed in run 4 because the corpus compares damage and boosts only, and an unmeasurable change would have blurred that run's attribution. **Half-closed in run 5**: because `immune_to_status` gained a slot, Yawn's sleep-immunity check now consults the body actually being put to sleep instead of slot 0. The remaining half is the SIDE, still taken from the target class, and still unpriced — stage 0 compares statuses now but not volatiles |
| 22 | open — `genx/abilities.rs:1412` | **`ability_on_switch_in` computes `def_pos` and never uses it** — the signature of an unfinished conversion. It then reads the foe as `defending_side.get_active_slot_immutable(owner_slot)`, indexing the *opposing* side by the *switcher's own* slot number, so the Neutralizing Gas check and Trace's copy both read whichever body happens to sit in the mirrored slot rather than a real target. Intimidate, two lines below, is correctly converted (it loops both slots), which is why the failing `test_switching_in_with_intimidate` fixture is stale rather than a live bug |
| 23 | **FIXED 2026-09-13 (run 5)** — `genx/items.rs:923` and `:949` | **Flame Orb and Toxic Orb statused slot 0, not their holder.** Both arms wrote `active_indices[0]` and `side.get_active()` while `owner_slot` — the holder — was already in scope and already used by the `Damage` and `Heal` arms of the same function a few lines away. So a slot-1 holder burned or badly-poisoned its own partner. Fixed with `owner_slot`; found only because these are two of the five callers of `immune_to_status`, whose signature change forced every call site to say which body it meant. **Qualify this FIXED as of run 12: the fix is now inert, and will stay inert until defect 33 is fixed.** It resolves `owner_slot`, which run 12 pinned to `0` — the slot the enclosing `item_end_of_turn` actually reads and dispatches on — so both orb arms now read and write the same body and the apply/reverse break this row fixed is genuinely gone, but only slot 0's orb is ever processed at all (defect 33). This is not a regression: before run 12 `owner_slot` was `actor_slot()`, whichever body acted LAST, which was not the holder either. **The instruction for whoever fixes 33: the loop must pass a real slot into both functions, and `owner_slot = 0` must become that parameter — not a revert to `actor_slot()`, which is what caused defect 2.** Defect 24 had already noticed the staleness at exactly these call sites in run 5 ("Flame Orb and Toxic Orb call this at end of turn … where `actor_slot()` is stale") without connecting it to the crash |
| 24 | open — `genx/generate_instructions.rs:748` | **`immune_to_status`'s *attacker* read is still slot 0.** Used only by the POISON/TOXIC arm's Corrosion check. Left deliberately: its correct owner differs by caller — for a move it is the actor, but Flame Orb and Toxic Orb call this at end of turn with `MoveTarget::User`, where `actor_slot()` is stale and "attacking side" merely means the other side. Changing it blind would alter item behaviour, so it is recorded rather than guessed at. Narrow: a slot-1 body's Corrosion is read off slot 0 |
| 25 | open — `choices.rs:357` | **Ally Switch's priority is wrong for gen 5 and gen 6.** The table declares a flat `priority: 2` with no gen gate, and `modify_choice_priority` has no arm for it, but gen 5 inherits gen 6's `priority: 1` (`data/mods/gen6/moves.ts`). Found in run 6 while reading Showdown's move data for the Ally Switch fix, and **deliberately not fixed there**: changing turn order could move other corpus rows, which would have blurred that run's attribution. It changes nothing in the corpus's own Ally Switch turns, where only priority-0 moves oppose it, so it is latent — it would bite against Quick Guard (+3), Fake Out (+3), Mach Punch (+1) or Protect |
| 26 | open — `genx/generate_instructions.rs:4469` | **`after_move_finish` consumes White Herb on slot 0 only.** It reads `side.get_active_immutable()` and emits its `ChangeItem` with a hardcoded `0`, carrying the author's own `// FIXME(doubles): slot`. So a slot-1 body's White Herb neither triggers nor is consumed, and a slot-0 body's can be consumed for its partner's negative boosts. Same family as defects 20/23; unpriced, because the corpus compares boosts by body and this affects *which* body's boosts are reset |
| 27 | **FIXED 2026-09-13 (run 8)** — `genx/generate_instructions.rs:1867` | **An absorbed move slipped past BOTH doubles protect gates, and the reason is that the absorb erases the fields they test.** Every absorbing ability calls `remove_all_effects()`, which sets `category = Status` *and* calls `flags.clear_all()` (`choices.rs:20741`). The area guard is gated on `choice.category != MoveCategory::Status` (`:1890`) and the per-body Protect stanza on `choice.flags.protect` (`:1952`) — so once the ability had run, neither fired, `remove_effects_for_protect()` never ran, and that function is the only thing that clears `choice.boost` (`choices.rs:20735`). A Protecting Lightning Rod holder therefore still banked **+1 SpA**, and Wide Guard missed absorbable moves for the same root cause. **Showdown's order is the opposite and that is the fix**: Protect's condition carries `onTryHitPriority: 3` and blocks, while the absorb's boost sits in an unprioritised `onTryHit` on the same event (`data/abilities.ts:2344`), so a blocked move never reaches the ability. The defender's ability and item are now consulted only when the move is **not** blocked; skipping the defensive modifiers costs nothing there, since `remove_effects_for_protect` zeroes `base_power` anyway. Singles is identical by construction (`blocked_before_ability` is `false` under `cfg(not(doubles))`). Priced: the last genuine boosts row closed, 314 → **315/316**, and stage 0 18 → **19/19** via `protect_blocks_the_absorb_boost_too`, where Showdown leaves the holder at 301→301 with no boost and logs `\|-activate\|… move: Protect`. Bodies unchanged at 306/316, and probe `tools/pe_doubles_spread_redirect.py` is byte-identical across all four cells |
| 28 | open — `genx/generate_instructions.rs:2324` | **Ability redirection is applied to SPREAD moves, which Showdown never does.** The single-target guard in `redirect_target` gates only the *volatile* redirection (Follow Me / Rage Powder / Spotlight); the Lightning Rod / Storm Drain scan above it runs for every move. In Showdown the redirect event is unreachable for spread moves — `priorityEvent('RedirectTarget')` sits inside the `default:` branch of the target switch (`sim/pokemon.ts:835`), which `allAdjacent` / `allAdjacentFoes` / `allies` never reach, and it is additionally skipped for charging moves and when `activePerHalf <= 1`. The missing guard **predates run 4**; what run 4 changed by making the ability scan field-wide is that a spread move can now be drawn onto the attacker's **own ally**. Recorded rather than fixed because it has **no measured consequence**: probe `tools/pe_doubles_spread_redirect.py` varies the ally's Storm Drain and the foe's Protect independently and the engine is correct in all four cells (the ally absorbs its partner's Surf, which is right — it is a legitimate target of the spread move — and every other body takes its normal damage). So the divergence is currently latent, living in `state.target_position` rather than in any outcome |
| 29 | open — `genx/items.rs:260` `get_choice_move_disable_instructions` | **A Choice lock is stamped on slot 0, whichever body used the move.** The engine *does* model the lock — a Choice holder using a move disables that body's other moves — but the helper takes `&Pokemon` + `&SideReference` and has no `State` to ask which slot is acting, so it carries the fork's own `0, // FIXME(doubles): slot (no State access in this fn)`. Three doubles-reachable call sites pass through it: `items.rs:761` (the CHOICEBAND / CHOICESPECS / CHOICESCARF arm), `choice_effects.rs:1005`, `abilities.rs:673`. A **slot-1** Choice user therefore locks its **partner** and keeps all four of its own moves. Probe `tools/pe_doubles_choicedisable_slot.py`: with both bodies Choice Banded and each using its own M0, a correct engine emits six disables (`M1 M2 M3` twice over) — four appear, and one of them is **`M0`, the move just used**, which can only happen if the second actor wrote onto the first body. Note the probe cannot read the slot directly: `DisableMove`'s Display omits it (`DisableMove SideOne: M1`) even though the apply path uses it (`state.rs:2149` → `get_active_slot(slot)`), so the evidence is the index set, not a slot number. **Not newly exposed by defect 4's fix** — the engine sets `disabled` itself, so this was always reachable; filling `Move.disabled` makes it common rather than rare. `state.rs:1890` `re_enable_disabled_moves` is the mirror image on switch-out, same hard-coded slot 0, already recorded and still unfixed. Neither is visible to the measured instruments: the corpus projects damage, boosts and statuses but never move availability, and the play harness rebuilds the root state from Showdown every turn, so a wrong lock inside the tree never reaches a submitted action |
| 30 | open — `genx/state.rs:1790` `combine_slot_options` | **A doubles side can end up with ZERO legal actions, and the search indexes the empty list.** `mcts.rs:134` (side one) and `:135` (side two) do `self.sN_options.as_ref().unwrap()[idx]` with no emptiness check, so an empty list aborts the search with `index out of bounds: the len is 0 but the index is 0`. The emptiness comes from a **filter, not a missing guard** — per-slot lists cannot be empty (`slot_options_doubles` ends `if options.is_empty() { push(None) }`, `:1680`) and `replacement_options_doubles` survives scarcity (`needing=[0,1]`, `available=1` → `fill=1` keeps `(Switch, None)` and `(None, Switch)`) — but `combine_slot_options` builds the cartesian product and then drops every combination where two slots switch to the same body (`has_duplicate_switch`, `:1819`) **with nothing to fall back on if that empties the result**. So when both slots' only option is a switch (no move selectable — `move_is_selectable` rejects `pp <= 0` and `disabled`) and exactly **one** bench body is available, the sole combination `(Switch(b), Switch(b))` is filtered away and the side has no action at all. **Reproduced deterministically in a three-body state**, no search depth required: `tools/pe_doubles_empty_options.py` cell A panics while both controls — two bench bodies, or one slot keeping a usable move — return 2 options. Singles cannot express this: no pairs, so no duplicate-switch filter. Seen once in run 9's roster re-run (on the `:135` side). The fix is a post-filter fallback, either one all-`None` action or letting one slot switch while the other passes |
| 31 | open — `state.rs:1946` `heal` | **`attempt to add with overflow`.** `fn heal` does `active.hp += amount` on an `i16`, so an `amount` big enough to carry hp past 32767 aborts the search. It is slot-correct (`get_active_slot(slot)`), so this is **not** a slot defect but an unbounded magnitude. Seen once in run 9's roster re-run at 300 ms and **not root-caused.** Two candidates, neither confirmed: run 4's fix made a spread move apply its `heal` **per target** (so this may be my own blast radius), and defect 2's `-11 / -12` boosts are the same family of accumulation with no clamp. Wants a probe before a fix — giving `hp` a saturating add would hide the cause rather than remove it |
| 32 | open — `state.rs:1895` `re_enable_disabled_moves`, called from `genx/generate_instructions.rs:2612` | **A Taunt expiring unlocks a Choice item.** The function re-enables **every** move whose `disabled` flag is set, and it cannot distinguish *why* a move was disabled. On **switch-out** that is correct — Showdown clears a Choice lock on switch-out too — but the Taunt path is a divergence: poke-engine encodes the Choice lock as `Move.disabled` (defect 29, and the same channel run 9's whitelist fills), whereas Showdown never does, enforcing the lock through `lastMove` instead. So Showdown's `taunt` `onEnd` leaves a Choice-locked body locked, and poke-engine hands it all four moves back. **Not doubles-specific** — it is reachable in upstream singles, where the sidecar bridge encodes the lock the same way — which makes it the first row here that is not a doubles conversion fault. Newly *reachable from the root* in run 11, since `taunt` is 71 of 183 gen5doublesou teams and was being silently dropped by the translator before now; previously it needed the tree to apply and expire a Taunt on its own. Related to row 29's note that this function is also hard-coded to slot 0, which is a separate fault in the same three lines. Unpriced: the corpus never projects move availability, and the play harness rebuilds the root from Showdown every turn, so a wrong unlock inside the tree only degrades the plan, it never reaches a submitted action |
| 33 | open — `genx/abilities.rs:1170` `ability_end_of_turn` and `genx/items.rs:880` `item_end_of_turn` | **Only slot 0's end-of-turn ability and item are ever considered.** Both functions are called once per **side** (`genx/generate_instructions.rs:3807`) behind a slot-0 hp guard, and neither contains a single `get_active_slot` call — every read is `attacking_side.get_active()`. So a slot-1 body's Speed Boost never ticks, its Black Sludge never heals or hurts it, its Sitrus/Lum/Chesto berry never fires, and a slot-1 Morpeko never flips forme. Found in run 12 while root-causing defect 2, which lives in the same two lines: that run fixed the **state/instruction divergence** (the crash) by naming the slot the functions actually read, and deliberately did **not** convert them to a per-slot loop. The reasons are attribution and risk: the loop is a wrong-**outcome** bug rather than a crash, it needs the borrow structure of a ~230-line match restructured, and no instrument here prices it — the corpus projects damage, boosts and statuses but never end-of-turn ability firing on slot 1 specifically. Bundling it would have blurred a verified crash fix exactly as runs 4 and 5 warn. Same unfinished `get_active()` conversion family as defects 6, 14, 20, 23 and 26 |
| 11 | **SUPERSEDED by defect 20 — same fault, and fixed there in run 5** | this is the symptom-level entry, written before the site was known; row 20 is the same bug at `genx/generate_instructions.rs:815` and carries the fix. Kept because its evidence is still the clearest statement of the symptom, and because run 6's backlog text mistakenly used *this* number for `reset_boosts` (which is defect **6**) — a slip corrected in run 7. **Every status move applies its status to slot 0, whatever it was aimed at.** `thunderwave,0` and `thunderwave,1` both emit `ChangeStatus SideTwo-P0` (`tools/pe_doubles_status_target.py`, two Psychic-type foes so neither is immune and only the index can differ). Damage does *not* have this bug — `airslash,0` and `airslash,1` correctly emit `Damage SideTwo:0` and `:1` — so it is the status write specifically. Worse, the immunity check reads the **right** target while the write goes to the wrong one, so Thunder Wave aimed at a Psychic ally-of-a-Ground-type paralyzes the **Ground type** |

**Wasted search.** Not a wrong answer — a budget spent on nothing.

| # | site | defect |
|---|---|---|
| 13 | doubles option generation | **A move with no target is enumerated once per target slot, and the variants are the same action.** `generate_instructions` returns byte-identical lists for `trickroom,0` and `trickroom,1` (`ToggleTrickRoom … ; DecrementTrickRoomTurnsRemaining`) and for `recover,0` and `recover,1` (both empty at full HP). Because each combines with the *other* slot's actions, the duplication multiplies through the joint space. Observed cost: with Jellicent holding Trick Room, six of fifteen root options were `trickroom`, splitting its visits six ways and leaving it ranked 10th–15th. This also bears on the "~250 options a side" combinatorics objection, which may be partly self-inflicted |

**Unreadable, not wrong.** Both are fixed locally by
`patches/poke_engine_doubles_choice_labels.patch`, which is why the transcripts are legible;
neither fix is upstream.

| # | site | defect |
|---|---|---|
| 8 | `MoveChoice::to_string` | names every sub-action out of **slot 0's** moveset, so slot 1's decision is reported with the wrong Pokémon's moves |
| 9 | same | the target slot is dropped from the label entirely, so `surf` and `surf at the ally` print identically |

**Not localized.** Listed here because it is the largest confirmed defect of the ten and
omitting it from the list would make the list look complete when it is not — but it has no
`file:line`, so it cannot be fixed the way the nine above can. It gets its own backlog item.

| # | site | defect |
|---|---|---|
| 10 | **FIXED — defects 15 + 5 + 16 + 17 (and 18 + 19 in run 4, 20 + 23 in run 5, 7 in run 6), `patches/poke_engine_doubles_spread_per_target.patch`; residual 0.8 points** | **Was the single largest source of disagreement with Showdown.** Bodies-damaged agreed on 73.2% of 373 corpus turns; holding out spread-move turns gave **92.0%**, so spread accounted for ~19 of the 27 points. Not the attacking slot (49 of 97 turns differ from slot 0 against 69 of 143 from slot 1 — the same rate), and in 39 disagreeing turns the undamaged body was the attacker's **own ally**. **Root-caused as defect 15 — three faults, not one — plus defect 5; both fixed 2026-09-13, and Protect (defects 16, 17 and defect 5's volatile half) fixed the same day. On the corrected instrument 74.1% → 87.7% → 95.6% → 95.9% → 96.8%, +22.7 points / 72 turns over runs 1–6, leaving a residual spread gap of 0.8 points.** Spread is no longer the dominant disagreement; `allyswitch` at 4/11 was, until defect 7 was fixed in run 6. One caveat that belongs with the original figure: **57 of those 373 turns were never comparable at all** — my harness, not the engine, see the stall-counter section |

**One hypothesis ruled out, recorded so it is not chased twice.** Jellicent was seen choosing
Recover at full HP and failing, which looked like defect 11 on the heal path. It is not: at
404/404 the engine emits **no heal instruction at all**, correctly. The choice itself was noise
— in that position the top four options sat at 178/177/173/147 visits against a 133 average.

**`disable` is a translator gap with a play cost, not just a skip.** `volatile disable` (and
`lockedmove`) have no poke-engine equivalent, so the position cannot be built and the search
never runs: three decisions in `doubles_play_logs_gen5_seed23/004` went to greedy for this
reason. Recorded above as a counted skip for the corpus; the play harness pays for it in
decisions, which is the more expensive currency.

**The search does not value field or side setup, and a targeted pool is what showed it.**
`--require-move` keeps only dump teams carrying a named move *and* rotates the carrier to the
front so it leads — both halves are needed, because on a four-mon team the carrier is usually
third or fourth and arrives after the game is decided, which is why Tailwind went unused across
the first fifteen battles despite six of them carrying it. With the filter on (25 of 171 teams
carry Tailwind; the lead was verified to be the carrier in all five battles) **Tailwind was
still used zero times and reached a printed ranking once.** Trick Room is the same picture from
the other direction: its setter was active from turn 1 and it sat 10th-15th of 15 options. Two
setup moves, opportunity guaranteed, never chosen — so this is not a sampling artefact.
**The cause is the evaluation's weights, not missing code, and not Foul Play** — Foul Play only
consumes this search; `mcts.rs` and `evaluate.rs` are poke-engine's own. `grep doubles
src/genx/evaluate.rs` returns nothing: PR #10 left the singles evaluation verbatim, and its
245 lines of hand-tuned constants say

| term | weight |
|---|---|
| `POKEMON_HP` | 100.0 |
| `SUBSTITUTE` | 40.0 |
| `POKEMON_ATTACK_BOOST`, `POKEMON_ALIVE` | 30.0 |
| `REFLECT`, `LIGHT_SCREEN` | 20.0 |
| `TAILWIND` | **7.0** |
| Trick Room, weather, terrain | **no term at all** |

So Tailwind is worth about 7% of one body's HP — less than a layer of Spikes, a quarter of one
Attack boost. Defensible in singles, where Tailwind is mediocre; in BW doubles Prankster
Tailwind is close to the defining strategy of the format. Trick Room scores zero, so setting it
is pure cost. Note also that the eval rewards Reflect and Light Screen at 20-40 while **0 of 171
teams carry either**, and ignores the three field effects the format actually turns on.

Rollouts do not rescue this: Tailwind's payoff *is* speed order, which only materialises through
later damage exchanges, while the cost (a turn not attacking) is visible at ply one — at a few
thousand visits against a doubles branching factor near 250 it never surfaces. Defect 13 makes
it worse by splitting a setup move's visits across duplicate enumerations, but the weights are
the bigger lever and the cheaper fix. `evaluate.rs:107` is also defect 2's panic site, which
makes this file the most defect-dense 245 lines in the fork.

**Filtered pools find defects faster than random ones.** The Tailwind pool produced 2 panics and
2 Choice-lock fallbacks in 5 battles, against roughly 1 per 5 in the general pool — fast
offensive teams reach the breaking states more often. Worth preferring for bug-hunting; worth
avoiding for anything quoted as a win rate, since the pool is no longer representative.

**That lead on defect 10 is dead — and killing it narrowed the search usefully.** I had written
that defect 11 put the *secondaries* of spread moves under suspicion, since a secondary is a
status write and status writes ignore the target slot. It cannot be the explanation: the corpus
pool is **secondary-free by construction** (`showdown_doubles_lib.js:48` — every move 100%
accurate, no status, no secondary, so the always-max PRNG pin is sound). No secondary was ever
in the measured turns.

Reading the pool for that turned up something better — though the first version of this note
overstated it, and the corrected form is the one to trust. **The pool's spread moves are
overwhelmingly `AllAdjacent`**, the class that hits the attacker's own ally: Earthquake in 121
turns and Surf in 126, against exactly one `AllAdjacentFoes` move — Swift — in **3**. Counted
off the `.ndjson`: 247 of 250 spread sub-actions are ally-hitting. An earlier version of this
paragraph said no `AllAdjacentFoes` move appeared in the pool *at all*, which is simply wrong
(Swift is on Raichu and Musharna, and poke-engine classes it `MoveTarget::AllAdjacentFoes` at
`choices.rs:16882`).

The conclusion survives, now resting on the counts rather than on that false premise: the
73.2%-against-92.0% gap is **about ally-hitting spread**, which is exactly consistent with the
39 disagreeing turns whose undamaged body is the attacker's own ally. And at 3 turns the
`AllAdjacentFoes` class is untested *in practice* even though it is present — so the original
warning was right in substance and wrong in letter. The probe covers that class directly
instead, via Heat Wave and Blizzard, which are correct in all seven scenarios both before and
after the fix.

Plain targeting by class is *correct*, so the fault is in the complications rather than the
dispatch (`tools/pe_doubles_spread_classes.py`): in an unobstructed 2v2, Earthquake and Surf
damage both foes **and the ally**, while Heat Wave and Blizzard damage only the two foes. The
complications are where it breaks, and one probe found it — Earthquake into a 2v2, varying only
who is immune and where they stand:

| position | expected | poke-engine emitted | after the fix |
|---|---|---|---|
| nothing immune | both foes + ally | both foes + ally ✓ | ✓ |
| ally is **Flying** | both foes, ally spared | both foes, ally spared ✓ | ✓ |
| ally has **Telepathy** | both foes, ally exempt | both foes, ally exempt ✓ | ✓ |
| **slot-0 foe has Levitate** | foe 1 + ally, foe 0 spared | **nothing at all** ✗ | ✓ |
| **slot-0 foe is Flying** | foe 1 + ally, foe 0 spared | **nothing at all** ✗ | ✓ |
| **slot-1 foe has Levitate** | foe 0 + ally, foe 1 spared | **all three, the immune body included** ✗ | ✓ |
| **ally has Levitate** | both foes, ally spared | **all three, the immune ally included** ✗ | ✓ |

That is defect 15. It is **three faults**, not one, and only two of them are about abilities:

1. **The pre-spread accuracy gate.** `:2551` calls `calculate_damage` against the *nominal*
   target and hands the result to `check_move_hit_or_miss`, whose `Some((0,0)) → percent_hit
   = 0.0` declares the **whole move** a miss. This is what produces "nothing at all", and it
   fires for **type** immunity too (row 5 is a Flying foe, no ability involved) — so the
   one-line summary "immunity zeroes the shared `Choice`" was only two-thirds right.
2. **Both defender-facing modifiers run once, on the shared `Choice`.**
   `ability_modify_attack_against` and `item_modify_attack_against` are called once in
   `before_move` (`:1731`, `:1734`), so no other position's ability or item is ever consulted.
   Same shape as defect 5, thirteen lines away in the same function (`:1731` against `:1744`).
3. **`ability_modify_attack_against` reads the target from the wrong side.** It resolved the
   body as `defending_side.get_active_slot_immutable(def_slot)` — always the foe side — but
   `defender_position` can point at the attacker's **own** side, because a spread move hits the
   ally. An ally's ability could therefore never be seen, whatever else was fixed.
   `item_modify_attack_against` is worse still: `defending_side.get_active_immutable()`, slot 0
   unconditionally, not even slot-aware.

The fix (`patches/poke_engine_doubles_spread_per_target.patch`) is one helper,
`resolves_per_target` — true exactly when a spread move has more than one living target —
which (1) passes `None` to the accuracy gate so a nominal-target zero cannot cancel the move,
(2) skips both `_against` modifiers in `before_move`, and (3) re-applies them inside the
existing per-target loop on a per-target `Choice` clone, so one body's immunity cannot leak
onto the next. Singles is unreachable by construction: the helper is `false` there.

**The absorb abilities are not secondaries — they are whole-move rewrites, and that is a
sharper statement of the same bug.** Storm Drain, Lightning Rod and Motor Drive each call
`remove_all_effects()`, force `target = Opponent`, set `category = Status` and install
`choice.boost` (`abilities.rs:2384, 2588, 2778`). On a shared `Choice` one absorber in any slot
converts Earthquake into a Status move *for every target*. Because `run_move` consumes
`choice.boost` exactly once (`:4079`), deferring them cost the absorber's boost until the loop
also applied each target's own boost while `target_position` still pointed at it —
`get_instructions_from_boosts` reads the slot from `defender_position` (`:1006`), so that lands
correctly. Boosts end **flat, not better** (−1 turn), and that is expected: redirection, which
is most of what Storm Drain and Lightning Rod do in real doubles, is untouched by this fix.

**A claim retracted, corrected in place above:** the pool does contain an `AllAdjacentFoes`
move (Swift, 3 turns), so "no `AllAdjacentFoes` move appears anywhere in it" was wrong;
`pe_doubles_corpus.py` counts Swift in its `SPREAD` tag. See the corrected counts under "That
lead on defect 10 is dead".

**One test fails in the doubles build, and the test is wrong, not the engine.**
`test_switching_in_with_intimidate` hand-writes a single `BoostInstruction::new(SideTwo, 0, …)`;
a doubles build correctly lowers **both** foes. 216 passed / 1 failed before and after this fix,
same single test — it is a singles-era fixture, already noted in the PR #10 audit, and not a
defect in the engine.

**How defect 11 was found, since it is the pattern to reuse.** Not by reading the source: by
noticing in a transcript that the search chose Thunder Wave against the same foe **thirteen
turns running** while a kill sat available, reconstructing that position through the harness's
own translator, and diffing the instruction list against a variant where only the target index
changed. The play logs are the instrument; the engine is small enough to interrogate directly
once a transcript says where to look.

### 4. ~~Close the rest of the spread-move divergence~~ — DONE 2026-09-13, residual 0.8 points

Defects 15, 5, 16, 17, 18, 19, 20, 23, 7, 6 and 27 are all fixed in
`patches/poke_engine_doubles_spread_per_target.patch` (1115 lines, 12 files; reverses cleanly).
**Bodies-damaged 74.1% → 96.8% across runs 1–8, and boosts 88.0% → 99.7% on the fainted-guarded
instrument run 8 introduced. Stage 0 went 11-of-12 → 19-of-19.** The residual spread gap is 0.8
points on bodies and 0.3 on boosts — one row, and an artefact — so spread is no longer the
dominant source of disagreement on either metric.

**The patch grew from 4 files to 12 in run 7, which earns a line of its own.** `reset_boosts`
lives in `src/state.rs`, a file the patch did not previously touch at all, and giving it a `slot`
parameter changed its signature — so all nine call sites had to follow it, six of them in
`src/gen1`, `src/gen2` and `src/gen3`. Those six pass a literal `0` and are behaviour-identical
by construction, but they have to ship with the patch or the tree stops compiling for those
features. That is why `cargo check` was run for gen1, gen2 and gen3 separately: the measured
build is `gen5,doubles` and would never have caught them.

**Protect is done too (run 3): 26 of 73 turns → 1 of 73.** It was three faults — defects 16 and
17, both new, plus defect 5's mechanism applied to the per-body volatile, which the run-2 patch
had missed.

**And the absorb abilities are done (run 4), which is what finally moved boosts.** Not by adding
redirection — it was already there — but by making ability redirection field-wide (defect 18) and
by resolving the absorbed boost/heal's **side** from the move's resolved target instead of its
target class (defect 19). A third fault was mine: my own run-1 spread loop applied the per-target
`boost` but not the per-target `heal`, so on a spread move an ally's Water Absorb heal was dropped
entirely — probe B2 emitted no `Heal` instruction at all until that was fixed.

What is left, in descending size. Nothing here is a spread problem any more:

**Bodies-damaged is the smaller problem: 10 disagreeing turns against boosts' 14.** After
run 6 no bodies bucket exceeds 6 turns or a 6.2% rate, and the list is flat enough that ranking
it by rate and by count disagree — which is itself the signal that the large single causes are
gone. Ally Switch is down to 1 of 11, and that one turn is the branch-spread artefact described
above, not a defect. Run 7 left this column untouched, every bucket included.

**Run 7 took the boosts target, and it was defect 6 — not defect 11. The numbering slip is
worth recording.** The run-6 text here named "defect 11" for `Side::reset_boosts`; the table
numbers that site **6**, and row 11 is the older symptom-level entry for *status application*,
which run 5 had already fixed at site level as defect 20. The fingerprint reading was right and
the label was wrong. Fixing `reset_boosts` took `switch from slot 1` on boosts from 9 of 105 to
**2 of 105** and the metric 93.4% → **95.6%**.

**`switch from slot 0` was co-occurrence, not a second cause — measured, not assumed.** It fell
only 7 → 5 of 125, and held out on its own that bucket is 120/125 (96.0%). Two of its five
surviving rows have the switch on the **opposite side** from the body that disagrees (battle 22
turn 7, battle 33 turn 6), which is what co-occurrence looks like and what a second cause would
not look like.

**Run 8 took those 14 rows apart, and two of the three "shapes" I named above were wrong.**
Recorded in full, because both errors came from reading *deltas* instead of snapshots:

1. **"An Intimidate-on-switch-in with the wrong sign … the shape of defect 22"** — wrong, and it
   was the basis of the recommendation I gave for the next run. Battle 9 turn 8's Blastoise had
   `atk −1` and **fainted**; Showdown zeroed a dead body's boosts, so the delta read `+1`. Both
   engines applied Gyarados's Intimidate correctly, and the partner Gengar shows `atk −1` in
   both. Nothing to do with `ability_on_switch_in`.
2. **"A clear-on-switch mismatch I have not isolated"** (battle 33 turn 6) — the same faint
   artefact. So were battles 10/10, 12/11, 20/13, 22/7, 23/9, 25/3, 30/12, 39/11 and 3/6 and
   3/12: **12 of the 14**.
3. **"An absorb boost of the wrong magnitude"** (battle 5 turn 10) — also wrong, and this one I
   first escalated to "an entire spread move is being lost, the defect-15 family resurfacing".
   The probe refuted it: the engine is correct in all four cells of
   `tools/pe_doubles_spread_redirect.py`. Re-reading the dump with that in hand, the engine deals
   `Damage SideTwo:0: 126` into Blastoise's **exactly 126 HP** — it kills the Surf user with
   Raichu's Shock Wave before Surf resolves, where Showdown's max roll dealt 116 and left it at
   10. It is the **KO-threshold artefact** already recorded below, and it is the one boosts row
   left.

Only one of the three shapes survived contact with the evidence, and it was the one I had not
tried to explain: battle 16 turn 10, now **defect 27**, fixed.

**So boosts is closed and bodies-damaged is the only metric with a real residual: 10 turns.** No
bodies bucket exceeds 6 turns or a 6.2% rate, ranking by rate and by count disagree, and the
remaining named causes are `ability stormdrain` 4/110, `ability friendguard` 3/95 and
`redirection move` 2/77. Friend Guard stays the hardest of them for the reason it always has
been: it needs the **target's partner's** ability, a lookup the damage path cannot express.
Defect 22 remains open and worth doing — `ability_on_switch_in` really does index the opposing
side by the switcher's own slot — but it should now be justified by *reading that code*, not by
the corpus row I wrongly attributed to it.

The remaining bodies rows, for completeness:

1. **`a body carries boosts`** — 6 of 127, and **`spread move`** 6 of 150. Both are partly
   consequence tags: once a boost lands on the wrong body it is carried into later turns.
2. **Storm Drain** — 4 of 110 for bodies and 11 of 110 for boosts, down from 7 and 25. What
   remains is no longer the redirection or the side; the likely candidate is that one absorber
   still influences what its *partner* takes.
3. **Friend Guard** — 3 of 95 turns. Needs the **target's partner's** ability, and no lookup
   for "the ally of the body being hit" exists anywhere in the damage path.

**A gap in the instrument — and run 4's proposed fix for it was the wrong one.** The corpus
compares damage, boosts and which body acted, **not statuses**, which is why defect 20 never
appeared in any of these percentages. Run 4 called adding a status projection to the corpus the
cheapest next move. It is not: `showdown_doubles_corpus.js`'s curated `POOL` contains **no
status-inflicting move at all**, so across 456 turns the only status transition is `none → fnt`,
which is fainting. A projection there would measure exactly nothing, and giving the pool status
moves means regenerating the corpus, which re-baselines every figure in this document.

**Stage 0 is the right home, and it was extended in run 5 instead.** Its verdict is per-case
agreement and none of the existing cases changes a status, so adding a projection cannot disturb
a single previous figure — the asymmetry that makes it safe where the corpus is not.
`pe_doubles_diff.py` now compares statuses (keyed through `roster`, since `ChangeStatus` is the
one compared instruction addressed by **party index** rather than slot), case
`thunder_wave_lands_on_the_slot_aimed_at` went from the only disagreement to agreeing, and stage 0
reached **15 of 15** (it is **19 of 19** today). The corpus stays the no-regression control:
unchanged at 303/316 and 295/316 across run 5, exactly as a status-blind instrument should be.

**Run 7 hit the same wall twice more, and one grep settled it.** Two of `reset_boosts`' three
callers are **Haze and Clear Smog**, and the corpus `POOL` contains *neither move* — so no
number there could have moved for either one whatever the engine did. Both went to stage 0 as
`haze_clears_all_four_slots` and `clear_smog_clears_the_slot_aimed_at`; both disagreed before the
fix and agree after, taking stage 0 16 → **18 of 18**. The switch caller is the one the corpus
*can* price, and the reason is a filter written for an unrelated purpose: the boosts comparison
keeps only bodies active in **both** snapshots (`pe_doubles_corpus.py:289`), so the departing
body's own legitimate clear is excluded on both sides and what survives is exactly the boost
wrongly applied to the body that **stayed**. That also means the "boosts survive on the body
that left" half of defect 6 is invisible to the corpus by construction, and only the probe shows
it (section A2).

**A second, structural limit of the instrument, found in run 6 and confirmed twice more in run
8.** It compares only the single most probable branch, so it can never agree on a row where a KO
sits inside the branch spread. Run 8's one surviving boosts row is the same shape: in battle 5
turn 10 the engine's top branch deals `Damage SideTwo:0: 126` into Blastoise's *exactly* 126 HP,
killing the Surf user before Surf resolves, where Showdown's max roll dealt 116 and left it at
10 — so an entire spread move happens in one engine and not the other. Both instances were
initially mistaken for mechanics defects, which is the tell: a row of this shape reads like a
targeting bug and is arithmetic.
The one Ally Switch turn still disagreeing after defect 7 was fixed is exactly that and **not a
defect**: in battle 24 turn 3 the engine's top branch deals `Damage SideOne:0: 114` against
Blastoise's *exactly* 114 HP — a knife-edge KO — where Showdown's max roll dealt 104 and left it
at 10, so Blastoise never gets to Surf and three bodies go undamaged at once. The engine itself
branches 41/59 either side of that threshold, so one of its two branches agrees. Any row of this
shape will read as a mechanics disagreement when it is a roll-model one.

## Reproduce

`git clone --depth 1 https://github.com/smogon/pokemon-showdown` at the repo root,
`npm install`, `node build`. Then from `tools/`:

- `node showdown_bench.js` — construct, per-turn and clone, singles and doubles.
- `node showdown_turnbench.js` — steady state, turns separated from construction and clone.
- `node showdown_mcts_cost.js [singles|doubles]` — iteration cost and memory per node.
- `node showdown_logcheck.js` — the determinism hash (strip `|t:|`; expect a stable digest).
- `node showdown_patch.js [prio] [cb] [move]` applies any subset to the built `dist` and
  backs up the originals; `node showdown_patch.js revert` restores them. Always re-run
  `showdown_logcheck.js` after a patch.
- `showdown_teams.js` holds the two gen 5 teams the others share.
- `ruby ../tools/search_bench.rb` for the Ruby projection numbers.

For PR #10: `git clone --single-branch --branch main-doubles --depth 6
https://github.com/0neCr1t/engine` (or `git fetch origin refs/pull/10/head` against
upstream), then `cargo test --features doubles,gen5` and `cargo test --features gen5` for
the two rows above. Nothing in it is installed and nothing in the study depends on it.

For the stage 0 differential, in that clone: apply
`patches/poke_engine_doubles_debug_slot.patch`, then
`cd poke-engine-py && maturin develop --no-default-features --features="poke-engine/gen5,doubles"`
into a venv of its own (**not** `generated/foul_play/venv-gen5`, which is the measured 0.8.0
instrument). Then `node tools/showdown_doubles_cases.js > generated/showdown_doubles_cases.json`
and `python3 tools/pe_doubles_diff.py` with that venv's python.

Add `--max-semi-space-size=128` to any `node` invocation to include the GC lever.
