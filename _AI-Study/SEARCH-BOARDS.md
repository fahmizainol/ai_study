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

**Result as first run: 11 of 12 agree. Now 13 of 13, zero disagreements** (2026-09-13): the
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
> charging the engine for 57 turns it cannot represent, and defect 5 was still open. The
> numbers to quote are in the next section: 74.1% → **87.7%**, 83% of the gap closed.

### The instrument was charging the engine for 57 turns it cannot represent

Found in run 2, and it inflates every figure above. `pe_doubles_corpus.py` skipped repeated
**Protect** under Showdown's stall counter — but gated that skip on `id == "protect"` alone.
Wide Guard and Quick Guard *also* call `onHitSide -> source.addVolatile('stall')`
(`data/moves.ts:20816`, `:14498`), so a body that Wide Guarded last turn and does so again
**fails** under the always-max PRNG, while poke-engine — which has no stall counter at all,
defect 12 — succeeds. **57 such turns were compared and charged to the engine.** The skip is now
keyed on `STALL_MOVES = {protect, detect, endure, wideguard, quickguard}` and `compared` drops
373 → 316.

A changed instrument invalidates the old baseline, so the baseline was re-measured under the new
one by reversing the patch and rebuilding — and re-applying it reproduced the fixed numbers
exactly (277/316, 273/316), which doubles as a build-integrity check.

| corrected instrument, 316 turns | bodies damaged | boosts |
|---|---|---|
| baseline (patch reversed) | 74.1% (234/316) | 85.8% |
| **defects 15 + 5 fixed** | **87.7%** (277/316) | 86.4% |
| spread-held-out ceiling (166) | 90.4% (150/166) | 92.8% |
| holding out Wide Guard (250) | 85.2% (213/250) | 86.8% |

**Together the two fixes are worth +13.6 points / 43 turns, closing 83% of the spread gap.**
Holding out spread turns makes the ceiling independent of these fixes, so baseline and fixed
share the same 90.4% — which puts the residual spread gap at **2.7 points**, down from ~16.3.
`--without wideguard` returns 213/250 on *both* instruments, as it must: those 57 skipped turns
are all Wide-Guard-tagged, so that row cannot move. A consistency check worth keeping.

**Spread is no longer the dominant source of disagreement.** The top bucket is now `protect` at
26/73 (35.6%) — first-use Protect, since repeated Protect is skipped — ahead of spread's 23/150
(15.3%). `allyswitch` has the highest rate at 5/11 (45.5%, small n). Storm Drain 14/110 and
Friend Guard 10/95 remain, both untouched by these fixes: redirection is not modelled at all,
and Friend Guard needs the **target's partner's** ability, a lookup `ability_modify_attack_against`
has no way to express.

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
87.7% on the corrected instrument; this measurement predates the fixes), and mis-binds an
action across Ally Switch. **So 73.9% is a floor, not a ceiling.** What it does **not** say is
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
size and the run prints its pool split. **The 63-17 should be re-run before it is quoted
further.**

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

Two more panics, neither gen-6-specific:

- `assertion left != right failed: get_two_actives called with...` (5 times) — a doubles-only
  internal assertion, presumably the same slot passed twice.
- `Invalid boost value: -7 / -8`, `Invalid boost number: 8` — the same ±6 escape as gen 6, so it
  is not a generation artefact.

**Two translator facts worth keeping**, both invisible under the synthetic pool:

- **A Choice lock is not a volatile in poke-engine**, it is `last_used_move` serialized as
  `move:<index into that body's own move list>`; Showdown enforces it through
  `pokemon.lastMove`, which the snapshot now carries.
- `flashfire`, `mustrecharge` and `slowstart` **do** exist as poke-engine volatiles and are
  mapped; `disable` and `lockedmove` do not and remain counted skips.

## Backlog

Recorded, not done. In the order they are worth doing.

### 1. Harvest Showdown's own doubles suite as the bug-finding corpus

The 12 stage 0 positions were authored from the fork's own `tests/test_doubles.rs` names, so
by construction they can only confirm mechanics it already knows about — which is exactly why
11 of 12 passed while the random corpus agreed on 73.2% — and the asymmetry survived both
fixes, which is the point: stage 0 is now 13 of 13 while the corpus sits at 87.7%. Cases I
author pass because I authored them. Showdown's suite is the independent
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
figures come from.

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

### 3. Fix the fifteen confirmed defects — 2 done (5 and 15), 13 open

Every line number below was read out of the `main-doubles` clone, not remembered. Three are
crashes, so they stop a bridge outright; eight are silent wrong answers, which is worse to ship;
two are cosmetic-but-blinding, in that they make the search's own decision unreadable; one wastes
the search's own budget; and one has no site yet, which is why it is the largest. The first
thirteen are small and localized. All
are doubles-only — the singles board is byte-identical (§ measurement 1), so nothing
here is a regression, only unfinished work.

**Crashes.** A panic in the planner is not recoverable from the caller's side, and
`PanicException` subclasses `BaseException`, so a driver that catches `Exception` dies with it.

| # | site | trigger |
|---|---|---|
| 1 | `genx/generate_instructions.rs:4289` `mega_evolve` | computes `act_slot`, discards it, then reads `side.get_active()` — slot 0 — and panics at `:4301` on any held item that is not a mega stone (`RHYPERIOR`/`ASSAULTVEST`, `TALONFLAME`/`CHOICEBAND`, …). Note the second, quieter half: were slot 0 *also* holding a stone, this would mega-evolve the wrong body and not panic at all |
| 2 | `genx/evaluate.rs:107` | `Invalid boost value: -7 / -8 / **-11 / -12**`. Boosts escape the ±6 clamp somewhere upstream and only blow up at evaluation. Seen in gen 6 **and** gen 5, so not generation-specific. The −12 (`doubles_play_logs_gen5_seed23/002`, turn 1) matters: it is exactly **double** the legal floor, so this is not a clamp that is off by one or two but drops being stacked with no bound at all — look for a per-slot drop applied once per target |
| 3 | `state.rs:1722` `get_two_actives` | `assert_ne!(a_idx, b_idx, "get_two_actives called with the same position")` — reached in ordinary play (×5 in the gen 5 run) |

**Silent wrong answers.** These return a plausible result that is wrong, which the differential
caught only because Showdown was sitting next to it.

| # | site | defect |
|---|---|---|
| 4 | *option generation* | **A Choice lock is not enforced.** `last_used_move` is supplied and is exactly how poke-engine encodes the lock, yet the search proposes moves Showdown has disabled — 35 times in the gen 5 run (`dracometeor`, `earthpower`, `icebeam`, `psychic`, `outrage`, `boltstrike`). The single most consequential one for a bridge: it hands the game an illegal action on roughly one turn in six. Reproduced in two later batches on `hydropump`, `icebeam`, `dracometeor`, `vcreate` and `thunderbolt`, so it is not one move's data — and the proposed move **is** in the body's own move list, which rules out the wrong-slot enumeration of defect 8 as the cause |
| 5 | **FIXED 2026-09-13** — `genx/generate_instructions.rs:1744` | Wide Guard / Quick Guard was applied to the shared `Choice` via `remove_effects_for_protect()`, cancelling the **whole** move. But both are *side conditions* and cannot protect anyone on the other side, so the half aimed at the attacker's own ally was thrown away. Was the one stage 0 disagreement (`wide_guard_blocks_spread`); **stage 0 is now 13/13**. Fix: `area_protection_blocks(state, choice, pos)` keyed on **`pos.side`**, applied per position in the spread loop, with the whole-move cancel kept only for the single-target case where it is correct |
| 6 | `state.rs:1795` `reset_boosts` | reads `get_side(side_ref).get_active()` — slot 0 — so when a **slot 1** body switches out carrying boosts, slot 0's boosts are cleared instead. Haze goes through the same path. The `NOTE (doubles)` comment above it is accurate and calls the fix deferred, so this is known, not overlooked |
| 7 | Ally Switch | a sub-action is bound to the **slot** rather than the body, so it follows the position across the swap instead of the Pokémon that moved |
| 15 | `genx/abilities.rs:2633` + `genx/generate_instructions.rs:1731` / `:2551` | **The root cause of defect 10.** Ability immunity is applied by *zeroing the shared `Choice`*, once, against the **nominal** target: Levitate sets `attacker_choice.base_power = 0.0`, `ability_modify_attack_against` runs once inside `before_move`, `damage_calc.rs:588` turns zero base power into `Some((0, 0))`, and `check_move_hit_or_miss` turns that into `percent_hit = 0.0` — all of it at `:2551`, **before** the spread expansion at `:2609`. Two consequences, in opposite directions: **(A)** an immune body in the nominal slot makes the entire spread move miss, so its *ally and the other foe take nothing*; **(B)** ability immunity is never consulted for any other position, so an immune body in slot 1, or an ability-immune ally, **takes full damage**. Type immunity escapes (A) only because it lives inside `calculate_damage`, which the per-target loop re-calls with `state.target_position` set — `damage_calc.rs` contains no `LEVITATE` at all. Measured with `tools/pe_doubles_spread_classes.py` |
| 14 | `genx/choice_effects.rs:213` + `genx/generate_instructions.rs:5145` | **Fake Out and First Impression read and write slot 0's move history, not the acting body's.** The restriction is modelled through `last_used_move` — `Move(_)` means the body has already acted, so the move loses its effects — but both the check (`attacking_side.get_active_immutable()`) and the reset (`get_side(…).get_active().last_used_move = Switch(P0)`) go through `get_active()`, which is slot 0. `tools/pe_doubles_fakeout_slot.py` shows the outcome depends *entirely* on slot 0's history and not at all on the user's, wrong in **both** directions: a slot-1 body that has been out for turns keeps a live Fake Out, and a freshly switched-in one loses it. Seen in play (`seed23/004` turn 3): Crobat had just switched into slot 0, so the search ranked Scrafty's dead Fake Out **top**, Showdown failed it, and Scrafty died that turn. The write is the worse half — using Fake Out from slot 1 stamps `Switch(P0)` over **slot 0's** history, and since defect 4's Choice lock is read from the same field, that is a candidate contributor to it |
| 12 | *stall counter absent* | **Showdown's consecutive-Protect counter is not modelled, so the search loops on a move that cannot work.** In `doubles_play_logs_gen5_seed11/002` Metagross Protects on **fifteen consecutive turns** (11–25), and Showdown fails every second one (`Protect [[still]]` / `IT FAILED`). The search puts 8266 of 14000 visits on it on turn 14 — a turn on which it had already failed — and re-picks it at the same weight the next turn and the next, while Metagross is ground from 364 to 19 and then loses. Known before as a *measurement* nuisance (it is why 164 corpus turns were skipped); these logs show it is a **play** defect that throws games |
| 11 | status application | **Every status move applies its status to slot 0, whatever it was aimed at.** `thunderwave,0` and `thunderwave,1` both emit `ChangeStatus SideTwo-P0` (`tools/pe_doubles_status_target.py`, two Psychic-type foes so neither is immune and only the index can differ). Damage does *not* have this bug — `airslash,0` and `airslash,1` correctly emit `Damage SideTwo:0` and `:1` — so it is the status write specifically. Worse, the immunity check reads the **right** target while the write goes to the wrong one, so Thunder Wave aimed at a Psychic ally-of-a-Ground-type paralyzes the **Ground type** |

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
| 10 | **FIXED — defects 15 + 5 together, `patches/poke_engine_doubles_spread_per_target.patch`; 83% of the gap closed** | **Was the single largest source of disagreement with Showdown.** Bodies-damaged agreed on 73.2% of 373 corpus turns; holding out spread-move turns gave **92.0%**, so spread accounted for ~19 of the 27 points. Not the attacking slot (49 of 97 turns differ from slot 0 against 69 of 143 from slot 1 — the same rate), and in 39 disagreeing turns the undamaged body was the attacker's **own ally**. **Root-caused as defect 15 — three faults, not one — plus defect 5; both fixed 2026-09-13. On the corrected instrument 74.1% → 87.7%, +13.6 points / 43 turns, leaving a residual spread gap of 2.7 points.** Spread is no longer the dominant disagreement; `protect` at 26/73 is. One caveat that belongs with the original figure: **57 of those 373 turns were never comparable at all** — my harness, not the engine, see the stall-counter section |

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

### 4. ~~Close the rest of the spread-move divergence~~ — DONE 2026-09-13, 83% closed

Defects 15 and 5 are both fixed in `patches/poke_engine_doubles_spread_per_target.patch`
(216 lines, 2 files; reverses cleanly, leaves the other three patched files untouched).
**Bodies-damaged 74.1% → 87.7% on the corrected instrument, +13.6 points / 43 turns, closing
83% of the spread gap. Stage 0 went 11-of-12 → 13-of-13.** The residual spread gap is 2.7
points and spread is no longer the dominant source of disagreement.

What is left, now in descending size — note the top item is no longer a spread problem:

1. **Protect** — 26 of 73 turns (35.6%), the largest remaining bucket. These are *first-use*
   Protects; repeated Protect is skipped as unrepresentable. Related to but distinct from
   defect 12 (no stall counter), which is what makes the repeats unrepresentable in the first
   place. Not investigated.
2. **Storm Drain / Lightning Rod redirection** — 14 of 110 turns. These abilities *redirect*
   single-target moves to the absorber; the fork models absorption by rewriting the `Choice`
   and does not model redirection at all. Not a per-target problem, a targeting one.
3. **Ally Switch** — 5 of 11 turns, the highest *rate* in the corpus though the sample is
   small. Already known from stage 0 to bind a sub-action to the slot rather than the body.
4. **Friend Guard** — 10 of 95 turns. Needs the **target's partner's** ability, and no lookup
   for "the ally of the body being hit" exists anywhere in the damage path.

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
