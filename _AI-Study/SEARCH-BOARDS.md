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

## Doubles in poke-engine: not feasible

Asked because poke-engine is the only board fast enough to be interesting. The answer from
the source at the pinned commit `f4e224c` is that doubles is a rewrite of the engine core,
and what survives is the data tables, not the mechanics.

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
`genx/generate_instructions.rs` (10,904). Upstream has not done it: one PR, #10 "Main
doubles", opened and closed unmerged the same day in June 2026.

## Where this leaves the study

| Want | Board | Cost a decision |
|---|---|---|
| Singles, today, beats the rules | poke-engine via the sidecar | 10 ms |
| Singles on a second opinion | Showdown | ~4 s at 5000 |
| **Doubles** | **Showdown, the only candidate** | ~4 s at 5000, or well under 1 s for a one-ply maximin |
| A shippable in-game search | none of these | Essentials one-ply maximin is the only shape, untried |

Showdown is ~400x slower than poke-engine for an identical budget, so it buys nothing for
singles, where the sidecar already wins. It is worth the cost only for doubles, and there
it is not competing with anything. The one-ply doubles maximin is comfortably sub-second
on the stock build and is the cheapest real experiment available.

The prerequisite for any of it is on our side, not Showdown's: **a doubles roster, a
doubles harness and a doubles position export out of Realidea do not exist yet.** The
adapter's search and Foul Play paths both decline doubles by design.

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

Add `--max-semi-space-size=128` to any `node` invocation to include the GC lever.
