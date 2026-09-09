# Portable AI for Realidea

Implementation status: **installed at core 0.6.2 (2026-09-06), probe and tier gauntlet
both measured.** Opt-in, and inert until its marker file exists.

> **Decision quality:** Portable scores **240/256** applicable probe assertions against
> stock v16 + clara's **202/256**, and there is no card Portable fails that stock passes
> (stock fails 48 cards, Portable 14, and the 14 are a subset).
>
> **Strength:** Portable wins on both benchmarks, and both now run clean end to end.
> On 240 paired battles over real gen 6 OU sample teams it takes **66.9%** against stock's
> **50.0%**; on 320 battles of the frozen archetype fixture, **64.4%** against **51.2%**.
> Stock-versus-stock at exactly 58W/58L on the tier schedule is the control that says
> it is fair. See *Tier suite* and *Archetype gauntlet*.
>
> The hang that blocked this page's strength numbers is **fixed**: it was never a
> deadlock. See *The gauntlet hang, and what it actually was*.

## What is installed

Realidea loads battle code from `Realidea V4.1/Data/Scripts.rxdata`. The build adds one
`Portable_AI` section at index 332, after `AI_Probe`, `Team_Overrides`, and `Level_Cap`,
and immediately before `Main`.

Section 332 `Portable_AI` is **9032 lines** at `PortableAI::VERSION = "0.8.0"` (the
0.1.0 install was 1511, 0.6.2 was 3754). Section 329 `AI_Probe` is replaced at the same time.

The generated section contains:

1. `portable_ai/model.rb` — normalized Hash/Array interface.
2. `portable_ai/effects.rb` — move-ID-keyed behavior tags.
3. `portable_ai/core.rb` — engine-independent scoring and side-level planning.
4. `adapters/realidea/Portable_AI_Adapter.rb` — Essentials v16 snapshot, legality,
   registration, skill correction, memory, and stock fallback.
5. `adapters/realidea/Portable_AI_Gauntlet.rb` — opt-in seeded strength benchmark.

The core sees no `PokeBattle_*`, `PBMoves`, `PBEffects`, or battle objects. In doubles it
plans both opposing battlers together, rejects targeted friendly fire, penalizes lethal
spread damage to a partner, avoids duplicate switches, and assigns finishable targets.

## Config overrides

`Data/ai_harness.txt` sets run-level knobs for the gauntlet and the probe, one
`key=value` per line, `#` comments allowed. Since 0.8.1 a *played* battle reads it too,
but only when `Data/portable_ai.txt` is present — the gauntlet and the probe run with
that marker absent, so their config still comes solely from `Harness.with_config`. It is the same file and the same twenty-eight
core keys the Reborn harness uses, so an ablation reads identically in both studies —
which is what lets a single installed build play both sides of a policy A/B instead of
rebuilding between arms.

```text
# 0.6.1 control: every 0.6.2 rule off
spread_target_hp=false
lethal_flat=false
entry_death=false
wish_pending=false
setup_stage=false
move_memory=false
yawn_gate=false
```

| Key | Type |
|---|---|
| `switch_risk_weight`, `accuracy_weight` | float |
| `heal_gate`, `priority_gate`, `self_cost`, `strict_threat` | boolean |
| `side_effects`, `ability_rules`, `entry_rules`, `format_rules` | boolean (0.5.0) |
| `damage_race`, `damage_race_switch` | boolean (0.6.0) |
| `spread_target_hp`, `lethal_flat`, `entry_death`, `wish_pending`, `setup_stage`, `move_memory`, `yawn_gate` | boolean (0.6.2) |
| `race_switch_to_winner`, `heal_outpace`, `escape_needs_hitter` | boolean (0.6.3) — all three false reproduces 0.6.2 battle-for-battle |
| `switchin_race_grade`, `escape_wall_margin`, `switch_estimate_pp` | boolean (0.6.4) — all three false reproduces 0.6.3 battle-for-battle |
| `party_matrix`, `sole_answer`, `setup_matrix` | boolean (0.6.5) — all three false reproduces 0.6.4 battle-for-battle, and so does `party_matrix` alone. All three ship **on** |
| `airborne_immunity`, `no_hit_needs_threat`, `foe_oracle` | boolean (0.6.6) — all three false reproduces 0.6.5 battle-for-battle. The first two ship **on**; `foe_oracle` is the experiment arm and is **never on by default** (it reads the far seat's registered choice, which against a human player is cheating) |
| `dead_before_moving` | boolean (0.6.7) — false reproduces 0.6.6 battle-for-battle. Ships **on**: a non-priority move clicked by an actor that is slower and certain to die keeps a quarter of its score |
| `search_planner` | boolean (0.7.0) — false reproduces 0.6.7 battle-for-battle. Chooses **which planner runs**, not which rules are on: false is the rule engine, true asks the one-ply search planner first. **Measured and it loses**: 31/60 at 0.7.0, **36/60 at 0.7.1** (leaf, accuracy, trapping and candidate fixes from the source audit), **39/60 at 0.7.2** (setup, heal, Protect, Substitute, status, hazards and move costs projected), **40/60 at 0.7.3** (a second ply, `search_depth=2`), **40/60 at 0.7.4** (each move priced against the foe's bench; the root-stage double count and the leaf's verdict term removed), **46/60 at 0.7.5** with `foe_stock_model` (the opponent model at the root: `search_foe_mix` 0.5 over the reply stock's own AI would make; −2 against the rule engine's 48/60, p = 0.82) against stock's 39/60. Ships **off** |
| `search_depth` | float (0.7.3), default 2 — plies the search planner looks ahead; 1 is the 0.7.2 grid. Read only when `search_planner` is on. Depth 2 changes 28% of decisions and is +1 over depth 1 (p = 1.0) |
| `search_foe_mix` | float (0.7.5), default 0.5 — the search's opponent model in one number, applied to the root rows only: 0 is the original's `pick_safest` (an action is worth the foe's worst reply), 1 values it at the expected reply under the predicted weights (`foe_oracle` or `foe_stock_model`; uniform when neither is on, which measured badly: 29/60). Below the root every ply stays maximin. Read only when `search_planner` is on; 0 reproduces 0.7.4 |
| `foe_stock_model` | boolean (0.7.5) — predict the foe's reply with the engine's own AI: `pbEnemyShouldWithdrawEx?`'s triggers read as a chance instead of a roll, its switch target, and the move `pbGetMoveScore` puts first; exported through the oracle's fields (`predicted_foe`, `predicted_incoming_damage_pct`), so every consumer reads it alike. Reads no registered choice, draws no random number. With the search at mix 0.5: **46/60**, the same number as the oracle ceiling (46). It is a model of stock v16, and a human does not switch on stock's triggers — ships **off** |
| `search_foe_prior` | boolean (0.7.8), default false — an opponent model with **no producer behind it**: the foe's columns are weighted by how hard each of its moves hits, a number `matrix_cell` already computed and handed the planner as `in_moves`. On the maximin it redistributes `column_weights`' stay mass (switch/stay split untouched); on the tree it adds AlphaZero's PUCT term `c·P(j)·sqrt(N)/(1+n)` to UCB1 on the foe axis only — **added, not substituting**, so a column the prior prices at zero is still explored on merit. **Measured: it pays on the maximin and not on the tree** — 35 → **41** with zero regressions (p = 0.031), against 45 for the hand-built `foe_stock_model` (p = 0.50, indistinguishable); the tree at 5000 is 48 → 46 (p = 0.73, null). **The maximin result does NOT replicate at that size** — pooled over three rosters it is 119 → 127/180 (5 / 13, p = 0.096), with the zero-regression property gone (gen5uu_a gives back 2, gen6uu_a 3). Read only when `search_planner` is on. Ships **off**
| `search_mcts` | boolean (0.7.6) — false reproduces 0.7.5 decision for decision. Chooses **which search** runs under `search_planner`: false is the maximin grid over the joint payoff (`pick_safest`), true is a decoupled simultaneous-move MCTS on the same board (poke-engine's `src/mcts.rs`, the path Foul Play runs today) — UCB1 per side, chance outcomes as sampled children, no playout, `sigmoid(eval − root_eval)`, the most-visited root option. Neither `search_foe_mix` nor the predicted reply is read on that path; the tree is its own opponent model. **Measured, and 0.7.6's write-up of it was wrong twice** (see that section's retractions). Against the only maximin holding the same information — the uniform arm at 29, since the tree cannot consume `foe_stock_model` by construction — MCTS is **+12 (p = 0.025)**. On the 0.7.7 foe move axis with a budget that can resolve it, it scores 48 / 46 / 44 at 5000 / 5000-seed-1 / 15000: **~46, the number the maximin needs the stock-trigger table to reach, with no opponent model at all**. Still ~2 behind the rules (48), not significant at n = 60. Ships **off**
| `search_iterations` | float (0.7.6), default 1000 — the MCTS budget as an iteration count, not a time, so a paired run and its shadow twin decide alike whatever the machine. Costs ~195 ms a decision at 1000 and ~894 ms at 5000 on RGSS's Ruby 1.8 (the maximin is ~10 ms). Read only when `search_mcts` is on
| `search_seed` | float (0.7.6), default 0 — mixed into the per-decision seed of the MCTS chance sampler. The seed is otherwise the position itself (turn, both slots, every body's HP), so a decision replays from its snapshot alone and nothing is drawn from `pbAIRandom`. Read only when `search_mcts` is on
| `foul_play` | boolean (0.8.0), ships **off** — hands every voluntary decision to the real Foul Play search (poke-engine gen 6) through `tools/foul_play_sidecar.py`; declines to the rules on doubles, a silent sidecar or an unmappable reply, each logged to `Data/ai_foulplay_log.txt`. **Pooled 162/180 against the rules' 143 (p = 0.005)**, the first arm to beat them. A study instrument: needs the sidecar process beside the game. Never on with `search_planner`
| `foul_play_iterations` | float (0.8.0), default 5000 — the sidecar's MCTS budget; ~10 ms a decision at 5000, 2-4 ms at 1000. **Leave it at 5000: 1000 measures 146/180 against 5000's 162 (p = 0.017), which is a tie with the rules** (see the 0.8.0 budget addendum). Read only when `foul_play` is on
| *(matrix version 4)* | 0.7.9 — both move lists carry EVERY move (status moves at pct 0) with `acc`, `priority`, `damaging` and the `effect` triple; the side table carries `status`, `item`, `ability` and `entry_damage_pct` per body. No new key: the search planner reads it whenever it runs, and the rule engine reads none of it (its cell reads are `out`, `in`, the categories and `faster`, all unchanged — stock and rules arms byte-identical). **Measured with the whole 0.7.9 board: the tree at 5000 falls from 48 to 41/60** (see that section) |
| *(matrix version 3)* | 0.7.7 — the cell gains `in_moves`, the foe's own per-move rolls beside our `out_moves`, so the search's foe axis is one column per move it owns instead of a single "it attacks, at worst". No new engine calls (the rolls were already made to find `in`) and built only when `search_planner` is on, since that is its only reader. Worth **+6** to a maximin with a uniform prior (29 → 35), **−1** to one with a real prior (46 → 45), and **−2 to +9** to the tree depending entirely on whether the budget can resolve the wider foe (39 at 1000, 48 at 5000)

Three keys are the harness's own rather than the core's:

| Key | Default | Effect |
|---|---|---|
| `trace` | `false` | record the per-turn portable decision trace, including what the actor believed about the board and the hits-to-KO race per target. It was unconditional through 0.1.0 and dominated the results file. |
| `seeds` | the five frozen seeds | comma-separated replacement list |
| `append` | `false` | append to `ai_gauntlet_results.ndjson` instead of truncating it |

Every gauntlet and probe record carries `portable_version`, and every portable record
carries the `config_overrides` it ran under. Read a results file by those stamps, never
by mtime — the readouts were once rendered from a stale baseline because nothing in the
record said which run it belonged to.

`move_memory` is inert on Realidea whatever this file says; see the handoff below.

### Run keys (not core config)

`Data/ai_harness.txt` also carries keys the gauntlet reads directly. Unlike the twenty-five
config overrides these do not touch core policy — they choose what runs.

| key | default | meaning |
|---|---|---|
| `teams=NAME` | `archetype` | roster set: `archetype` (frozen 3-mon fixture), or a tier set — `gen6ou_a`, `gen6ou_b`, `gen6uu_a`, `gen5ou_a`, `gen5ou_b`, `gen5uu_a`, `gen5uu_b`, `gen5ru_a` |
| `schedule=tier` | frozen | every ordered non-mirror pairing of the set's four teams (12 matchups), written to `Data/ai_tier_results.ndjson` so tier numbers can never pool with the frozen benchmark |
| `matchups=x,y` | all | run only these named matchups — for smoke-testing a roster, or resuming past one that stalled |
| `mega=false` | on | suppress Mega Evolution (see *Mega Evolution*) |
| `seeds=a,b,c` | five | replace the default seeds |
| `trace=true` | off | record the per-turn portable decision trace, plus `parties` (see *Turn-by-turn traces*) |
| `modes=a,b` | `stock,portable` | which arms to run: `stock`, `portable`, `shadow` (see *The shadow arm*) |
| `replacement=portable` | `stock` | who picks the Portable arm's post-KO replacement: `stock` keeps the convention every run before 0.6.3 used (the engine's type-chart chooser on both sides, so strength differences stay attributable to turn decisions); `portable` routes it through the core's forced-switch scorer, which is what a Portable install does in play. Stamped on every record (see *0.6.3*) |
| `append=true` | off | append rather than truncate |

Progress goes to `Data/ai_gauntlet_progress.txt` (one line per battle, flushed) and any
crash outside a battle to `Data/ai_gauntlet_error.txt`.

## Enable and disable

The installed code is disabled by default. To enable it, create:

```text
Realidea V4.1/Data/portable_ai.txt
```

Delete that marker to return immediately to the previously live `AI edit clara`
`pbChooseMoves`. Exceptions and failed registrations also fall back to that stock method
and are written once to `Data/portable_ai_error.txt`.

Wild battles remain on the original policy (`ENABLE_WILD = false`). Trainer skill uses
the larger of `Trainer#skill` and a wholly numeric `skillCode`, repairing Realidea's
misplaced `100` without interpreting real script-like skill codes as levels.

## Build and install

Run from the repository root:

```bash
python3 _AI-Study/tools/build_portable_ai.py
python3 _AI-Study/tools/pack_rxdata.py \
  --insert "Realidea V4.1/Data/Scripts.rxdata" \
  --script _AI-Study/generated/Portable_AI.rb \
  --name Portable_AI --before Main --upsert \
  --replace AI_Probe \
  --replace-with _AI-Study/adapters/realidea/AI_Probe.rb \
  --out "Realidea V4.1/Data/Scripts.rxdata"
python3 _AI-Study/tools/pack_rxdata.py \
  --selftest "Realidea V4.1/Data/Scripts.rxdata"
```

`--upsert` makes repeated installation byte-identical instead of adding duplicate
sections. Existing sections are copied as verbatim Marshal byte slices. The packer
validates the rebuilt bytes first, writes a same-directory temporary file, fsyncs it, and
atomically replaces the destination, so in-place install does not truncate the live
bundle on a failed write.

To remove the AI behavior while preserving every other currently installed section:

```bash
python3 _AI-Study/tools/pack_rxdata.py \
  --remove "Realidea V4.1/Data/Scripts.rxdata" \
  --name Portable_AI \
  --out "Realidea V4.1/Data/Scripts.rxdata"
```

Installation also updates `AI_Probe` to the current probe source. Removing
`Portable_AI` does not restore an older probe body; use a separately retained bundle or
version-control copy when a byte-for-byte pre-install rollback is required.

## Verification

Unit tests:

```bash
ruby _AI-Study/tests/test_portable_ai.rb        # 209 tests
ruby _AI-Study/tests/test_reborn_adapter.rb     # 53 tests
ruby _AI-Study/tests/test_realidea_adapter.rb   # 126 tests
python3 _AI-Study/tests/test_tooling.py
python3 _AI-Study/tools/check_move_codes.py
```

`test_realidea_adapter.rb` carries a **snapshot contract test**: the list of keys the
shared core reads at each level (top level / actor / move action / switch action /
target), asserted against a snapshot built from a stub board. When a future core rule
adds a read, the key goes on that list and this test fails until the Realidea export
exists. That test is the answer to how this adapter came to sit five minor versions
behind without anything noticing.

`check_move_codes.py` asserts every Essentials function code named in the adapter's
tables exists in `Realidea V4.1/PBS/moves.txt`, and prints every code the two adapters
disagree about. It currently reports exactly the three known divergences.

In-engine decision probe:

1. Create `Realidea V4.1/Data/ai_probe.txt`.
2. Leave `portable_ai.txt` absent for stock, or create it for Portable AI.
3. Launch `Game.exe`.
4. Grade the corresponding output:

```bash
python3 _AI-Study/tools/check_scenarios.py \
  _AI-Study/scenarios_realidea.json \
  "Realidea V4.1/Data/ai_probe_results_portable.ndjson"
```

Frozen strength gauntlet:

1. Delete `portable_ai.txt` so the runner can control stock/portable mode independently.
2. Create `Realidea V4.1/Data/ai_gauntlet.txt`.
3. Launch `Game.exe`.
4. Read `Data/ai_gauntlet_summary.txt` and `Data/ai_gauntlet_results.ndjson`.

Remove all trigger files after testing. With no trigger present, a normal boot reached the
title path successfully.

## Measured result

### 0.6.4 probe — 2026-09-06

**251/267** on the 219-card corpus (267 gradeable after the same ten skips and four N/A);
the five 0.6.4 cards all pass and the same sixteen 0.6.2 failures remain. See *0.6.4* below.

### 0.6.3 probe — 2026-09-06

**246/262** on the 214-card corpus (262 gradeable after the same ten skips and four N/A);
the six 0.6.3 cards all pass and the same sixteen 0.6.2 failures remain. See *0.6.3* below.

### 0.6.2 probe — 2026-09-06

Corpus 208 scenarios / 275 assertions. Ten scenarios are skipped with a reason (seven
pin a Reborn field, three pin a mechanic this engine does not have) and four assertions
are N/A (`switch_score_gt` needs a party-indexed switch score array, and v16 switching is
a predicate with no numeric scale), leaving **256 gradeable**:

| AI | assertions | cards failed |
|---|---:|---:|
| Stock v16 + Clara | 202/256 | 48 |
| Portable AI 0.6.2 | **240/256** | 14 |

Re-measured after the `$ItemData` fix; the 204 figure this table carried earlier is
superseded (see below).

**No card fails under Portable that passes under stock** — Portable's 14 failing cards are
a strict subset of stock's 48, and Portable fixes 34.

Those remaining failures are one structural fact, not fourteen bugs. **This adapter feeds stock's own
`pbGetMoveScore` as base evidence; the Reborn adapter feeds a flat 100** (deliberately —
see its header). A card written as "core delta X beats core delta Y" cannot survive a
base that has already loaded tens of points onto whichever move deals more damage:

| card | wanted | stock gap | portable gap |
|---|---|---:|---:|
| `a_kill_is_chosen_on_accuracy_not_type` | DRAGONCLAW | −45.0 | −7.5 |
| `d_priority_flat_in_doubles` | AQUAJET | −90.0 | −30.0 |
| `recoil_flat_penalty_vs_equal_power` | BRAVEBIRD | −12.0 | −1.9 |
| `leech_live_on_a_fresh_target` | LEECHSEED | −42.0 | −39.9 |
| `knockoff_vs_leftovers` | KNOCKOFF | −3.0 | −18.9 |
| `flinch_ignored_when_slower` | ROCKTOMB | −73.0 | −77.2 |

The last two move the WRONG way and are the only two worth reading as findings. Do not
close these by inflating core deltas: the same cards pass on Reborn, where the base is
flat, so a delta large enough to win here would distort them there.

Two real gaps the run found, both fixed: ability absorbs were invisible to the damage
estimate (v16's `pbTypeModifier` is ability-blind and `pbTypeImmunityByAbility` cannot be
called from an AI — it is the live effect), and `switch_score_gt` was being scored as a
failure on an engine that has no switch scores.

#### The stock probe figure moved: 204 → 202

The 204 recorded earlier on 2026-09-06 was measured with `$ItemData` `nil`, so stock's
`pbGetMoveScore` read no item data at all. **Confirmed rather than assumed:** re-running
the stock probe with the fix reverted reproduces 204 exactly. Five cards fail and three
pass once item data is loaded, netting −2. Portable totals 240 either way, though its
per-card results also move, and it still has zero Portable-only regressions.

`202/256` is the figure measured on an engine that has its item data. Prefer it.

### Mega Evolution — yes, fully

Realidea supports it completely, and the tier gauntlet uses it.

| | |
|---|---|
| species | **46 mega forms + 2 primal reversions** (Kyogre, Groudon), `Pokemon_MegaEvolution.rb`. Charizard and Mewtwo carry both X and Y. |
| items | all the mega stones are in `PBS/items.txt` and each forme is keyed off holding its own |
| trigger | `pbCanMegaEvolve?` / `pbRegisterMegaEvolution` / `pbMegaEvolve`, `PokeBattle_Battle.rb:1961-2062` |
| AI | `pbEnemyShouldMegaEvolve?` (`PokeBattle_AI.rb:4022`) is *"simple: always should if possible"* |

**It is policy-neutral between the two arms.** Portable's `pbDefaultChooseEnemyCommand`
override calls `pbRegisterMegaEvolution(index) if pbEnemyShouldMegaEvolve?(index)` on
exactly the same line the stock path does, so both arms mega whenever it is legal.
Enabling it changes the *teams*, never the policy.

**Two gates a save-less harness has to know about**, both in `pbCanMegaEvolve?`:

```ruby
return false if $game_switches[NO_MEGA_EVOLUTION]                        # switch 34
return false if !@battlers[index].hasMega?                               # holds the stone?
return false if $game_switches[512]==false && $game_switches[234]==false # story gates
```

A fresh `Game_Switches` has every switch false, so **512 and 234 both being false blocks
every mega evolution in the game**. The gauntlet therefore sets 512, controlled by the
`mega=` harness key (default on) and stamped on every record. Switch **234 is deliberately
left alone**: it triggers a scripted Lilliana cut-in that calls `Kernel.pbMessage` and
`Graphics.update` in a wait loop, which in a headless run is an unbreakable block.

Defaulting it on is provably inert for the archetype fixture, whose mons hold no stone —
`pbCanMegaEvolve?` tests `hasMega?` *before* it reaches either switch.

Verified in the engine, not just read: the same matchup on the same seed with `mega=true`
and `mega=false` diverges (stock loss in 20 turns vs 17; portable win in 16 vs 19).

### Tier suite

Real gen 6 OU sample teams from Smogon's threads, two disjoint sets of four, every
ordered non-mirror pairing over five seeds. `teams=gen6ou_a schedule=tier`.

| set | stock | portable | gap |
|---|---|---|---|
| gen6ou_a | 56.1% | 69.5% (74.6% resolved) | **+13.4pt** (+18.4 resolved) |
| gen6ou_b | 44.1% | 64.4% | **+20.3pt** |
| **pooled (240 battles)** | **50.0%** | **66.9% (69.5% resolved)** | **+16.9pt** (+19.5 resolved) |

**Stock-versus-stock landed on exactly 58W/58L.** The schedule runs every pairing in both
directions, so a policy-neutral right seat should sit at 50% — and does. The gap is the
seat swap, not the schedule. Read with `tools/summarize_tier.py`.

**Why not gen 7.** Realidea carries the gen 7 dex and all 29 Z-crystals as items and
implements **no Z-move engine at all** — so 24 of gen7ou's 26 sample teams would import
holding an inert item, and gen 7 is not offered. It is a mega-era engine with a gen 7
Pokédex bolted on. Of gen6ou's 14 teams, 11 are eligible; the other three ask for an
ability Realidea did not give that species (its **Zapdos has Lightningrod, not Static**;
its **Diancie has Magic Bounce, not Clear Body**). Battle Bond is vetoed for the same
reason as the Z-crystals: the ability is in `PBS/abilities.txt` and nothing in the engine
reads it.

**Hidden Power had to be solved, not dropped.** v16 has no `hptype` field — the type comes
from IV parities — and Realidea's pool is **17 wide, not 16**, because `pbHiddenPower`
enumerates every non-pseudo type except `NORMAL` and `SHADOW` and this game has `FAIRY`.
A Showdown spread therefore lands on the wrong type: **7 of gen6ou's 13 Hidden Power sets
mistype**, four of them Hidden Power Ice becoming *Dragon* on exactly the
Zapdos/Thundurus/Charizard whose job is checking Landorus. `showdown_names.Realidea`
solves the IVs against Realidea's own formula, flipping only low bits so every IV keeps
its author's band and each change is worth one stat point at level 100.

#### Five tiers, two generations — 2026-09-07

The suite was gen 6 OU alone because that was the only pool vendored. Four more tiers
were fetched and drawn, taking it from 2 sets to 8. **720 new battles.**

| set | stock (control) | portable | gap | McNemar |
|---|---|---|---|---|
| gen6uu_a | 50.0% | 75.4% (77.2% res.) | **+25.4pt** | p = 0.0066 |
| gen5ou_a | 50.9% | 77.2% | **+26.3pt** | p = 0.00027 |
| gen5ou_b | 47.4% | 75.0% | **+27.6pt** | p = 0.00073 |
| gen5uu_a | 43.3% | 78.6% | **+35.2pt** | p = 0.00016 |
| gen5uu_b | 57.6% | 82.8% | **+25.1pt** | p = 0.00027 |
| gen5ru_a | 65.0% | 79.3% | **+14.3pt** | p = 0.21 |
| **pooled (720)** | **52.4%** | **78.1% (78.4% res.)** | **+25.6pt** | **p = 4.1e-15** |

Paired on (set, matchup, seed), 334 usable pairs: portable wins 105 that stock loses,
stock wins 20 that portable loses. Five of six sets clear on their own; **gen5ru_a does
not** (+14.3pt, p = 0.21) — the smallest pool, and the one set to treat as a lead rather
than a result.

**This replicates gen6ou rather than beating it.** The same rosters re-measured at 0.6.5
give gen6ou +23.7pt (+26.3 resolved) against a 50.0% control, and the six new sets pool
to +25.6 (+25.9). The portable core's margin over stock v16 is a stable ~25 points across
five tiers and two generations, not a property of one metagame.

**The mega confound does not apply here.** Gen 5 teams carry no mega stones and gen 6 ones
do, which would matter on an engine where only one arm megas — but on Realidea both arms
call `pbRegisterMegaEvolution` on the same line (see *Mega Evolution*), so the gen 5 and
gen 6 numbers are measuring the same thing.

**Portable errored 18 times to stock's 9, and that is exposure, not a regression.** Every
fault is inside `085:PokeBattle_AI` — the engine's own scorer, reached through
`portable_ai_stock_pbChooseMoves` — and 16 of the 23 ZeroDivisionErrors are the known
`pbRoughDamage` divide-by-zero. The matrix-off control shows the same ~2:1 split, so it
predates 0.6.5; the portable arm simply plays longer battles (22.3 turns vs 19.7) and
reaches the buggy function more often. The paired test drops any pair where either arm
errored, so none of it touches the significance figures.

**Gen 5 is played under ORAS rules and the result must be read that way.** This is a v16
engine: Steel keeps neither its Dark nor its Ghost resistance, Knock Off hits for 65 not
20, and Fairy-typed species are Fairy. Both sides are equally affected so the comparison
stays fair, but a gen 5 set measures *can the AI pilot this structure*, never *is this a
faithful BW game*.

**gen6ru was attempted and cannot be built.** Three of its five sample teams are
unrepresentable on this dex — two want Clear Body on a Diancie whose PBS entry reads
`Abilities=MAGICBOUNCE` and nothing else, one wants a Glalitite that is absent while 44
other mega stones are present — and two teams cannot fill a four-team set. The pool is
vendored anyway so the attempt is on record.

#### The BOM that ate the first row of every PBS file

Found while drawing gen 5: four teams were dropped as **"unknown move Megahorn"**, and
Megahorn is `1,MEGAHORN,...` on line 1 of `moves.txt`. Realidea's PBS files carry a UTF-8
BOM, and `\ufeff` is not whitespace to Python's `str.strip()` — so `"\ufeff1".strip()
.isdigit()` is False and the id-prefixed first line of every csv was skipped in silence.
Cost: `MEGAHORN` from moves, `REPEL` from items, `STENCH` from abilities. Species survived
by luck, because `_ini_records` accumulates into the *next* `[n]` header.

It went unseen for as long as it did because the three casualties are the first entries
and nothing had asked for them. Both readers in `showdown_names.py` and all three in
`make_scenarios.py` now open `utf-8-sig`; `PbsByteOrderMarkTest` in `tests/test_tooling.py`
pins the recovered rows and was verified to fail with the bug reintroduced. The scenario
corpus re-emits **byte-identical**, so no probe result moved.

Two other generator facts settled at the same time: **Keldeo-Resolute is cosmetic here**
(no forme is registered, base Keldeo has Justified, Secret Sword is teachable) and is now
whitelisted as it already was on Reborn, which recovered gen5ou's thirteenth team; and
`gen6ou_a`/`gen6ou_b` are **byte-identical** after the regeneration, because new tiers are
appended to the draw order rather than inserted, so no recorded result was invalidated.

**Provenance, previously unrecorded.** The vendored pools come from
`https://pkmn.github.io/smogon/data/teams/<tier>.json`; the four original files were
confirmed byte-identical to it. That URL appeared in no commit, doc or tool, and is now in
`extracted/smogon-teams/SOURCE.md`.

#### Three pre-existing engine bugs this run found

Six battles of 240 ended with no verdict. All three faults are in Realidea's own code, and
none can be reached by the archetype fixture — it has no items, no hazards and no
Intimidate.

| fault | where | reached by |
|---|---|---|
| `ZeroDivisionError` | `pbRoughDamage:3557` | an `atk/defense` with defense 0 |
| `NoMethodError` | `pbEnemyShouldWithdrawEx?:4226` | calls `hasWorkingAbility`, a **battler** method, on a party `PokeBattle_Pokemon` — whenever the AI weighs a switch under Spikes |
| `NameError` | `pbIncreaseStatWithCause:766` | an undefined `upanim`, reached from **Intimidate on switch-in** |

They are excluded from the rates and reported separately: scoring an engine crash as a
policy failure would flatter whichever arm reaches the broken code less often. Portable
inherits the `ZeroDivisionError` because this adapter still calls stock `pbGetMoveScore`
for base scores; the `hasWorkingAbility` one is stock-only, because Portable replaces the
switch evaluator that contains it.

#### Timeouts are not draws

The 100-round cap computes a verdict on remaining count then HP total — and
`pbStartBattle` **throws it away**, because the cap raises through `pbAbort` and the
rescue that catches it overwrites `@decision` with 0 (`PokeBattle_Battle.rb:2753-2755`).
Every capped battle therefore arrives as an undecided draw no matter who was winning.

All six in this run are portable battles in the stall matchups. The gauntlet now stashes
the verdict on the way past — behaviour-neutral, the same value is still returned — and
records it as `timeout_result` **beside** the raw decision rather than folded into it, so
no previously recorded number changes meaning. Three were wins, three losses.

### Turn-by-turn traces

`trace=true` records the Portable arm's per-turn decisions into each record's `trace`
key, and `tools/render_realidea_battle.py` prints one battle as text. A traced 120-battle
set is about 880 KB and takes the same ~65 seconds.

A matchup id and seed do **not** name one battle: both roster sets call their matchups
`team1_vs_team2`, and each battle is recorded once per mode, so a tier trace holds four
records under the same pair. `--teams=` and `--mode=` narrow it to one; `--list` shows
both columns. Same collision that once halved the shadow sample.

```
python3 tools/render_realidea_battle.py generated/realidea_tiertrace_gen6ou_a.ndjson --list
python3 tools/render_realidea_battle.py generated/realidea_tiertrace_gen6ou_a.ndjson \
    team1_vs_team4 104729 --teams=gen6ou_a --mode=portable
```

```
Turn 8   actor 1   SUCKERPUNCH @0               score    194.0
    board   : Bisharp 25%  vs  Scizor 88%
    foe     : Scizor -> BULLETPUNCH
    view: hp 25%  speed 239 (faster)  incoming max 210%  certain 210%  threatened_lethal=True
    race vs Scizor: mine 2 turns, theirs 1, winning=False
    options considered:
         194.0  SUCKERPUNCH (bp 80, 49% dmg, x1)       engine_base +155, expected_damage +39
         155.8  IRONHEAD (bp 80, 20% dmg, x0.5)        engine_base +183, expected_damage +16, resisted -45
         145.3  KNOCKOFF (bp 20, 13% dmg, x1)          engine_base +135, expected_damage +10
        -103.0  SWORDSDANCE (0% dmg, x1)               engine_base +137, unsafe_setup -240
         VETO   switch -> Azumarill                    escape_lethal_threat +130, no_escape_reason -1000000
```

**What a per-turn record carries.** Two tiers, because one of them is bulky:

| always | with `trace=true` |
|---|---|
| the actor's **species, HP, status, ability, item and stage totals**, and the same for every foe on the field — the board as the core saw it, at the moment of the decision |
| **what the other side chose that turn** (`foe`), read back from `battle.choices` after it registered — present on 100% of turns in both arms | `candidates`: **every option the actor had** — up to ten, which is four moves and five bench slots, so nothing is cut (the cap was six through 0.6.2, and a readout could not say what the third bench Pokemon scored) — each with its score and the `reasons` breakdown that produced it |
| speed and speed order, incoming-damage estimates, `threatened_lethal`, and the per-foe damage race | for moves: base power, type effectiveness, expected damage %, immunity |

None of that is newly computed — the shared core already ranks and explains every
candidate (`portable_ai/core.rb` builds `diagnostics.rankings` and attaches `reasons`),
and the snapshot already carries species and HP for both sides. Until 2026-09-06 the
Realidea exporter simply recorded six scalars and the chosen action, which is why its
readouts were so much thinner than Reborn's; the data was there the whole time.

**The `foe` line is a choice, not an outcome.** `PortableAIGauntlet.command_phase` drives
all four seats through `pbDefaultChooseEnemyCommand` in index order, so seat 0 has
registered by the time the measured seat's entry is written — that ordering is the whole
reason it can be attached. But it is what the opponent *selected* before the turn ran: it
may have missed, been Protected, or never fired because its user fainted first, and the
seats execute in priority and speed order, not the order they were asked. For what the
engine actually *did*, there is still no record — see the limits table.

Species reach the trace **named**. The snapshot keeps the engine's numeric id, because
that is what the core wants; `species_name` converts on the way out only, through the
same `PBSpecies.getName` `party_snapshot` uses, so a trace and a record's `parties` agree
on spelling.

**Tracing is observation-free**, and that is checked rather than assumed: the traced
`gen6ou_a` run reproduces the untraced one exactly — 41/12/6/1 and 32/25/0/3, same win
rates, same mean turn counts.

Four things to know before reading one:

| | |
|---|---|
| **One arm per record** | a `mode=portable` record traces the arm that *played*, so it holds no stock answer to the same board. For a turn-by-turn diff of the two AIs, run the **shadow arm** below; those records carry both. |
| **Decisions, not outcomes** | the line says what Portable chose, the board it faced and every option it weighed. It still does *not* say what the engine then **did** — whether the move hit, crit, was Protected, or what the foe's move actually did. Reborn's gauntlet hooks the engine's `events` stream for that; this one has no such hook, and that is the one real gap left between the two readouts. |
| **A missing turn is a fall-through** | no line means Portable did not decide that turn — the adapter deferred to the stock path, or the actor could not act. A turn the *observer* crashed on is **not** missing: it is recorded with a null answer and an `observer_error`, and counted as unscorable, because an absent turn would quietly shrink the denominator of every agreement figure. All 6 in 3,033 turns are the same case, and it is benign: `ArgumentError: actor 1 has no usable actions` on a **Struggle** turn — every move out of PP, which the core has no candidate to represent. The host still played; only the comparison is lost. |
| **`race` is keyed by battler seat, not party slot** | a seat is not a party index. Records written since the view carried `targets` resolve the seat to the species that was actually standing there; older ones have no per-turn foe identity and still print the bare `foe@0` rather than guessing. A *switch* entry's `slot` **is** a party index and is always resolved to a name. |

`parties` (species and final HP per side) is written alongside any per-turn record —
`trace=true`, or a shadow record, whose per-turn pairing *is* the arm's output. A switch
is recorded by party slot and a renderer has no other way to learn what lives there.
With neither, the record stays the compact one every earlier run used.

Error records carry their partial trace too, since the battle that crashed is the one
most worth reading; before that they were the only records that threw it away.

### The shadow arm

`modes=shadow` runs the battle on the **stock** AI while the portable planner is asked,
every turn, what it would have done from the identical position — and registers nothing.
That is the only way to compare two policies turn by turn: two live arms hold the same
board for about one turn, and everything after that is a different battle, so a live
stock/portable pair can be compared on outcomes and nothing finer.

```bash
# modes=stock,portable,shadow  schedule=tier  teams=gen6ou_a   (then gen6ou_b, append=true)
python3 tools/shadow_check.py generated/realidea_tier_shadow_0_6_2.ndjson
python3 tools/render_realidea_battle.py generated/realidea_shadowtrace_gen6ou.ndjson \
    team1_vs_team4 104729 --teams=gen6ou_a --mode=shadow
```

Three rendered battles are committed under `generated/readouts/` so the format can be
read without a re-render: `team1_vs_team2 196613` and `team3_vs_team2 155921` pair with
the single-arm readouts already there, and `team2_vs_team1 104729` is the one carrying
observer failures. Rendering all 360 at once gives an 86,000-line, 6 MB file; that is
deliberately **not** committed, being a pure derivation of a tracked trace.

```bash
python3 tools/render_realidea_battle.py generated/realidea_shadowtrace_gen6ou.ndjson > readout.txt
```

Two artifacts, on Reborn's convention: **`realidea_tier_shadow_0_6_2.ndjson`** (1.6 MB) is
the lean measurement, and **`realidea_shadowtrace_gen6ou.ndjson`** (14 MB, `trace=true`)
is the same 360 battles carrying the full per-candidate scoring. Rendering the second
gives ~80,000 lines of readable turn-by-turn text. Both report identical numbers, which
is itself the check that recording more changed nothing.

```
Turn 1   actor 1   <- DIFFERENT
    stock   : INFESTATION
    portable: switch -> Scizor             score    307.3
    view: hp 100%  speed 46 (slower)  incoming max 32%  certain 32%  threatened_lethal=False
    race vs foe@0: mine 8 turns, theirs 4, winning=False
```

**The arm is only valid if observation was free, so that is checked, not asserted.** A
shadow battle and a stock battle on the same matchup and seed must agree on decision and
turn count — same battle, same AI, differing only in whether anything was watching.
Over the full 120-battle tier run they agree on all 120, down to an identical engine-error
profile (4 errors each, same three causes). `shadow_check.py` refuses to report a single
disagreement figure until that holds.

Three things make it free, and the third was found the hard way:

1. **Nothing is registered.** The planner's action is recorded and discarded; the host
   still chooses. The hook also *skips* the portable pre-steps rather than falling
   through them, because the host method runs `pbEnemyShouldUseItem?`, `pbAutoFightMenu`
   and `pbRegisterMegaEvolution` itself — a fall-through would do each twice.
2. **Rolls are diverted.** `pbAIRandom` is the single choke point every AI roll passes
   through, planner and engine alike, and during an observation it draws from a private
   LCG instead of the battle. In practice it diverts 0 rolls at bestSkill: the planner is
   deterministic there, and the engine helpers the snapshot calls take no rolls (all 21
   `pbAIRandom` calls in `PokeBattle_AI` sit in the *choosing* machinery, not the scorer).
   It matters below bestSkill, where planner noise is live.
3. **`fake_battler` no longer frees trapped foes** — see below.

#### What the equality check caught

The first shadow run failed it: 14 of 60 battles did not reproduce their unobserved
twins, and all 14 were the matchups whose *observed* team was the one carrying
Infestation. Bisecting the observation (each cycle is a 5-battle, 8-second repro via
`matchups=`) walked it down to `fake_battler`'s constructor.

`PokeBattle_Battler#initialize` runs `pbInitEffects`, which reaches across to every other
battler and clears whatever points at the index being built. The adapter knew about
three such writes — Lock-On, Attract, Mean Look — because those are the three stock
Essentials makes. **Realidea makes a fourth**: it clears `MultiTurn`/`MultiTurnUser`, the
partial-trapping state. So every time the AI *weighed a switch* while holding a foe in
Infestation, Wrap or Fire Spin, merely thinking about the switch set that foe free.

That bug is older than the shadow arm and was never shadow-specific — it sat in the live
Portable arm too. It had simply never had anything to contradict it: with no unobserved
twin to compare against, a freed foe is just what happened. Adding the pair to
`RESTORED_ON_FAKE` fixes it, and a regression test asserts the list matches the engine.

**It did not move any published number.** Re-measuring the full tier suite after the fix
reproduces Portable 66.9% / 69.5% resolved and stock 50.0% exactly. The reason is
measurable rather than lucky: across 3,027 compared turns the stock AI chose Infestation
**30** times and the portable planner **0**, so in a live portable run the trap the bug
needed was never set in the first place. It took a stock-piloted trapper — which is
exactly what the shadow arm creates — to expose it.

#### What the two policies actually disagree about

Over 3,027 turns where both answered: **58.3% agreement, 41.7% disagreement.** Of the
disagreements, 943 are move-vs-move, 278 are Portable switching where stock attacked, 32
the reverse, and 10 are two different switches. Disagreement is not error — stock wins
its share of these battles — but this is where the whole 16.9-point gap lives.

The largest single cluster is Portable declining stock's hazard/status turns in a losing
damage race: `switch->4 vs INFESTATION` (23), `SOFTBOILED vs SEISMICTOSS` (25),
`ROOST vs HIDDENPOWER` (22).

Known limits of the arm: the shadow does **not** carry portable memory (it never moved,
so it recorded no repeated setup), so its setup choices are slightly over-represented
against a live portable run. Everything else is exact.

### 0.6.3 — three rules read off the shadow readout, 2026-09-06

Three battles in the 0.6.2 shadow readout were flagged by a person as wrong, and all
three turned out to be one flaw: **a reason to leave never asked who was coming in.**

| battle | what happened | what was missing |
|---|---|---|
| `team1_vs_team2 104729` t0-5 | Quagsire stayed in front of a Calm Mind Clefable, losing the race 6 hits to 3, with Magnezone on the bench | the switch rule that exists for this (`damage_race_switch`, 0.6.0) is off because it opened the gate for *any* bench — and the readout could not even show Magnezone, cut by a six-candidate cap |
| `team3_vs_team1 155921` t23-28 | Zapdos at 13% Roosted +50 into a 57% Lava Plume five turns running, credited `heal_saves_battler` +150 each time, while `switch → Chansey` was vetoed for being under 50% HP | a heal that loses ground is not a save; the gate's HP floor said "stay and attack", the heal rule said "stay and heal", and nothing said "leave for the body that wins" |
| `team3_vs_team2 155921` t29 | Scizor sent into a Heatran that removes it in one hit | never Portable's decision: faint replacements went through the engine's type-chart chooser on both sides, by convention |

**Three core rules, three keys** (`portable_ai/core.rb`; all three false reproduces 0.6.2
battle for battle — Realidea's stock arm is bit-identical 120/120 either way, and the
Reborn control on set_c is 26/26, +0):

| key | rule |
|---|---|
| `race_switch_to_winner` | leave a race lost **by a whole hit** for a bench candidate that **wins its own race** — computed from the two estimates the adapter already puts on the switch action, after paying the free entry hit, by a whole hit, not on a speed tiebreak; not when a recovery move the actor carries covers two of the foe's hits; and never for a candidate at the 8-hit race cap, which is walling, not winning. No HP floor (a chipped battler that is losing has less to preserve) and no boost suppression (the foe's stages are already inside the candidate's incoming estimate) |
| `heal_outpace` | a heal that restores less than the next hit takes, in a race already lost, is charged `heal_only_delays` −120 instead of credited +150 |
| `escape_needs_hitter` | `no_effective_move` and `weak_current_attacks` count only for a bench candidate whose own best hit clears the 10% line. Found while checking the first 0.6.3 run: 168 of its 193 switch-backs against an unchanged foe were Zapdos and Suicune trading places in front of a Chansey, each leaving because its attacks were weak and each replaced by one whose attacks were as weak |

Two things the probe corrected before the rules shipped, both recorded in the corpus:
a speed tie reads as "slower" on both sides, so a Snorlax mirror was a race both Snorlax
"lost" (hence *by a whole hit*); and a Gengar immune to Body Slam "won" a race it needed
fifteen hits to finish (hence the cap clause). And two things the rule's own arithmetic
refused that the readout had suggested: Eviolite Chansey ties Heatran on hit count once
the free entry hit is paid, and so does Slowbro against Fire Blast — neither is a winner,
and the Zapdos card benches Quagsire, whose Earthquake is one hit.

**Faint replacement** (`replacement=` run key, adapter `choose_replacement`): the
engine's chooser sums the type chart over each candidate's moves and reads nothing about
what the candidate takes coming in. A Portable-driven side now routes it through the
core's forced-switch scorer — entry damage, the switch-in race, `dies_on_entry` — and
that is what a Portable install does in play. The **gauntlet defaults to `stock`**
(every earlier number keeps its convention) and measures the variant by name.

#### Measured

Probe **246/262** (208 → 214 cards, +6, every new card passes; the same sixteen
assertions fail that failed on 0.6.2). Tier suite, 240 battles, gen6ou_a + gen6ou_b:

| arm | 0.6.2 | 0.6.3 | |
|---|---|---|---|
| stock | 58-58, 4 errors, 50.0% | 58-58, 4 errors, 50.0% | **identical, 120/120 battles** |
| portable | 79-33-6, 2 errors, **66.9%** | 82-30-4, 4 errors, **70.7%** | paired: 36 identical, gained 16, lost 13 |
| portable, `replacement=portable` | — | 80-33-5, 2 errors, 67.8% | vs default: gained 16, lost 18 — noise |
| mean turns, portable | 26.1 | 27.9 | |

Shadow arm, 120/120 observation-free: agreement **58.3% → 54.3%** over the same 3,027
turns, the whole move being switch-vs-move (278 → 544) — which is the point, not a
problem. The turns the readout was written about:

- Quagsire t0: `switch → Magnezone (hits 78%, takes 21%, faster) 389.6 … losing_race_bench_wins +110`, over Scald 163.5 — and Magnezone is now line 1 of a ten-line list.
- Zapdos t23: `switch → Chansey 533.6` over `ROOST 327.4 (… heal_only_delays −120)`; t24 onward Slowbro joins once Heatran is paralysed and the tie goes Slowbro's way.
- Heal-loop turns (a heal chosen while lethal-threatened, into a bigger hit, in a lost race): **42 → 3**.

The cost, stated plainly: voluntary switching **2.47 → 4.64 per battle**, and switch-backs
within three turns **75 → 133**, 120 of them against an unchanged foe. `escape_needs_hitter`
took that from 193 to 133 and no further: 62 of the remaining are still
`weak_current_attacks`, because a candidate can clear the 10% line on the bench estimate
and fall below it on the field's — the two estimates disagree across the line. That is
the next item, and the fix has the same shape (require the candidate to *beat the actor's
own best hit*, not a fixed line).

The four Portable-arm errors are three `ZeroDivisionError`s at `pbRoughDamage:3557` and
the `upanim` NameError — the pre-existing engine crashes, met more often because a
switching AI calls into stock `pbGetMoveScore` more often.

**Reborn, same core, full protocol** (`PORTABLE-AI-REBORN.md` → *Core version 0.6.3*):
probe 281/281; control 26/26 +0; sweep **203 → 231 / 420, +28, p = 0.002**, on six
rosters of seven and every archetype. The first Reborn win-count movement since 0.3, and
the first rule batch not proposed from the source.

Artifacts: `realidea_shadowtrace_gen6ou_0_6_3.ndjson` (traced, both variants' default),
`realidea_shadowtrace_gen6ou_0_6_3_replportable.ndjson` (traced) and its lean twin
`realidea_tier_0_6_3_replportable.ndjson`, `ai_probe_results_portable.ndjson` (0.6.3; the
0.6.2 record kept as `ai_probe_results_portable_0_6_2.ndjson`), and under `readouts/` the
five shadow battles above plus one live `replacement=portable` battle (`replacement → X`
lines). The 0.6.2 traces and readouts are untouched, so the two versions can be diffed
turn by turn. The probe now writes every option's score and reasons (`ranking`) — the
first 0.6.3 probe run spent a rebuild finding out that a candidate's race had never been
computed, and that is not happening again.

### 0.6.4 — the switch-backs were a PP bug, and kill order does not pay, 2026-09-06

Two refinements of the 0.6.3 rules were agreed off the 0.6.3 readout, and both went in
behind their own keys. One of them found something else on the way.

| key | rule | default |
|---|---|---|
| `escape_wall_margin` | `no_effective_move` and `weak_current_attacks` open the gate only for a bench candidate that **beats the actor at the actor's own game**: two whole hits fewer to the knockout and no more than four of its own, on the same foe HP (`candidate_can_hit?`). Refines `escape_needs_hitter`, inert without it | on |
| `switch_estimate_pp` | a bench candidate's outgoing estimate **skips a move with no PP left**, as the field view already does (adapter `switch_outgoing_damage`, both engines) | on |
| `switchin_race_grade` | every switch candidate, the post-KO replacement included, is graded on **who lands the last hit once it is in** — `candidate_race` after hazards and the free entry hit, by the margin in hits: +150 / +110 / +70 (tiebreak) / −30 / −70 / −110 (`kill_order_grade`). `losing_race_bench_wins` keeps its gate and gives up its flat 110 | **off** |

**All three false reproduces 0.6.3 battle for battle** — Realidea's stock arm is
bit-identical 120/120 either way, and the Reborn control on set_c is 60/60 with the three
keys off.

**What the wall margin found.** The first 0.6.4 run still had 125 switch-backs, 114 of
them against an unchanged foe, and the wall reason was still the driver. The trace
explained it: at turn 89 of `team1_vs_team2 196613` Quagsire's candidates were Recover,
Haze and Toxic — **Scald was out of PP** — and Chansey's were Soft-Boiled, Stealth Rock
and Toxic, Seismic Toss spent. Both had "no damaging move" on the field, and both hit
"for 27%" on the bench, because `switch_outgoing_damage` walked `pokemon.moves` without
looking at PP. The 0.6.3 note that "the bench estimate and the field estimate disagree
across the 10% line" was right about the symptom and wrong about the size: they disagreed
by a whole move. The margin rule is kept (it is right on its own terms, and the corpus
cards say so) but the PP fix is what ended the loop:

| | 0.6.3 | 0.6.4 |
|---|---:|---:|
| voluntary switches per battle | 4.64 | **3.52** |
| switch-backs within three turns | 133 | **40** |
| … against an unchanged foe | 120 | 29 |
| … driven by `weak_current_attacks` | 62 | **3** |
| heal-loop turns (shadow) | 3 | 3 |

**What the kill-order grade found.** It does exactly what it says — the probe and the
five cards below pass, the Scizor-into-Heatran replacement now reads `kill_order −110`
against Slowbro's +110 — and it **costs wins on both gauntlets**, so it ships off:

| arm (grade on) | Realidea, paired vs 0.6.3 | Reborn, 420 paired |
|---|---|---|
| full grades, wall on, no PP fix | 80-28, gained 4 lost 6 | 220 (−11, p = 0.10) |
| full grades alone (wall off) | 80-29, gained 5 lost 7 | **219 (−12, p = 0.07)** |
| penalties removed (+150/+110/+70 only), wall + PP | 83-27, gained 4 lost 3 | 224 (−7, p = 0.12) |
| wall margin alone | 83-28, gained 1 lost 0 | 230 (−1) |
| **shipped: wall + PP, grade off** | **83-28-4, gained 2 lost 1** | **230 (−1, p = 1.0)** |

The loss sits in one Reborn roster (set_c, −8 and −6), and a traced pair of that roster
is committed (`reborn_6v6_v064trace_set_c.ndjson` at defaults, 28/60 and identical to the
sweep; `reborn_6v6_v064gradetrace_set_c.ndjson` with the grade on, 21/60). The grade does
not change how often the AI switches (3.0 against 2.83 per battle); it changes **who**
comes in and **whether**: in `offense_vs_speed 130363` t2 every bench body is graded −70
or −110, the switch the default takes at 223 drops to 113, the actor stays in to Brave
Bird and loses; in `balance_vs_offense 130363` t9 the grade prefers the −70 body over the
−110 one and that body loses. A bench body that "loses its race" on a point estimate is
often still the right pivot — the entry cost is already charged, and the actor was leaving
for a reason. Same disposition as `damage_race_switch` in 0.6.0: the A/B can turn it on;
the default cannot.

**Faint replacement**, now that the grade is measured: `replacement=portable` scores
88-29-2 (73.9%) against the default's 83-28-4 — gained 20, lost 15 paired, still within
noise, and the gauntlet default stays `stock`.

#### Measured

Probe **251/267** (214 → 219 cards, +5, every new card passes; the same sixteen
assertions fail that failed on 0.6.2). Tier suite, 240 battles, gen6ou_a + gen6ou_b:

| arm | 0.6.3 | 0.6.4 | |
|---|---|---|---|
| stock | 58-58, 4 errors, 50.0% | 58-58, 4 errors, 50.0% | **identical, 120/120 battles** |
| portable | 82-30-4, 4 errors, 70.7% | 83-28-4, 5 errors, **72.2%** | paired: 103 identical, gained 2, lost 1 |
| portable, `replacement=portable` | 80-33-5, 67.8% | 88-29-2, 1 error, 73.9% | vs default: gained 20, lost 15 — noise |
| mean turns, portable | 27.9 | 27.6 | |

Shadow arm, 120/120 observation-free, agreement **54.3% → 54.9%** over 3,027 turns
(switch-vs-move 544 → 498). The fifth Portable-arm error is a fourth `pbRoughDamage`
ZeroDivision, the pre-existing engine crash.

**Reborn, same core, full protocol** (`PORTABLE-AI-REBORN.md` → *Core version 0.6.4*):
probe 286/286; control 60/60 +0; sweep **231 → 230 / 420** (−1, p = 1.0) at the shipped
defaults. The switching fix is a Realidea result — Reborn's 6v6 battles rarely run a
move out of PP — and the Reborn sweep is the control that it costs nothing there.

The corpus cards (`CORPUS_064`): `no_effective_move_needs_a_body_that_breaks_the_wall`
and its control `a_body_that_only_clears_the_line_is_not_worth_the_free_turn` (Alakazam
in front of an Umbreon that carries no attack, Politoed's Scald at 24% clears 0.6.3's
line and not the margin, Machamp's Close Combat does — four moves each side so no filler
pads the set); `a_reason_to_leave_does_not_send_in_the_body_that_dies_first` (Yawned
Zapdos, Slowbro over Scizor into Heatran — passes at 0.6.3 too, it is the fixture for the
complaint); and the pair `a_winning_bench_body_is_still_a_winner_off_the_rocks` /
`the_rocks_turn_the_same_body_into_a_loser` (Charizard's Earthquake two-shots Heatran and
Flare Blitz is a third of Charizard: off rocks a win by one hit, on rocks in at half and
a loss by one — the entry-damage arithmetic was in `candidate_race` at 0.6.3, this is the
proof that was asked for). That last pair took four probe runs to tune, and the reason is
worth keeping: **Realidea's chart has Steel resisting Dark** (Crunch on Heatran, 18.7%
here against Reborn's 23.5%), and its Charizard hits half again as hard as Reborn's
(Earthquake 91.6% against 77.1%), so a move that three-shots on one engine five-shots on
the other. A card that has to hold on both engines has to be read off both engines'
`ranking` records, not calculated.

Artifacts: `realidea_shadowtrace_gen6ou_0_6_4.ndjson` (traced, all three arms, the
shipped defaults), `realidea_shadowtrace_gen6ou_0_6_4_replportable.ndjson` and its lean
twin `realidea_tier_0_6_4_replportable.ndjson`, the ablation arms as lean files
(`realidea_tier_0_6_4_grade_on.ndjson`, `_switchin_race_grade_off`,
`_escape_wall_margin_off`, `_exp_positive_only`), `ai_probe_results_portable.ndjson`
(0.6.4; 0.6.3's kept as `ai_probe_results_portable_0_6_3.ndjson`), and under `readouts/`
the same five shadow battles and the one live `replacement=portable` battle as 0.6.3,
under the `0_6_4` stamp, so the two versions diff turn by turn.

### 0.6.5 — the party × party damage matrix, 2026-09-07

Every rule through 0.6.4 scores against the **active foe**. That is the whole board a
move sees; it is not the whole board a switch decides. Read against the 0.6.4 shadow
trace, the remaining losses sit there: stock spent its only answer to their Scizor into
an Azumarill it loses to, with the answer to the Azumarill on the bench
(`team4_vs_team1 130363`, stock arm, a 19-turn loss), and the setup block paid a flat 55
for any first boost whether it won the game or wasted the turn.

This version adds **one snapshot field and two rules that read it**.

| key | rule | default |
|---|---|---|
| `party_matrix` | adapter-side (`rule_enabled?`): build `snapshot["matrix"]` — best damaging hit each way for every live pair of party slots, both parties, with the damage category, the move, and the speed order — and put the derived grid in the trace and on the probe record. Built only when something would READ it: either consumer, or a run recording a trace (`matrix_wanted?`) | on |
| `sole_answer` | the only body that beats a foe still on their bench is not spent in front of a foe it loses to (`sole_answer_exposed`, −150 per unique foe, cap −300) and not sent when another body also handles the board (`sole_answer_reserved`, −45, cap −135) | **on**, on the paired gauntlet |
| `setup_matrix` | the first boost is priced by **what it flips** across their whole live party — `L→W` and `S→W` +55, `L→S` +25, cap +220 — in place of the flat `first_setup` 55. Three answers, not two: it pays for flips, it pays 0 for a boost that moves no number anywhere (`setup_no_flip`) or that the foe in front leaves no turn to buy (`setup_no_budget`), and **in between it says nothing at all** — a boost that shortens a race without flipping it returns nil and the flat 55 stands, exactly as at 0.6.4 | **on**, after the budget fix below |

**All three false reproduces 0.6.4 battle for battle, and so does `party_matrix` alone**:
the matrix is data, and no rule reads it unless its own key is on. The 0.6.4 switch
estimators (`switch_incoming_damage`, `switch_outgoing_damage`, `switch_candidate_faster`)
are deliberately untouched and still feed `candidate_race` and the defensive bands — they
carry Intimidate and the Choice lock, which the cells do not, so leaving them alone is
what makes that claim true by construction rather than by measurement.

**Shape.** `snapshot["matrix"]` is keyed by **party slot** on both sides, never by seat: a
benched body has no seat, and a seat is not a party index. Two side tables carry `slot`,
`index` (the seat, `nil` on the bench), `hp_pct`, `alive`, `speed` and `types`; `cells`
holds `"<own slot>:<foe slot>" → {out, out_cat, out_move, out_moves, in, in_cat, in_move, faster}`, (`out_moves`, matrix version 2 at 0.7.4: every damaging move the row body rolled, `{MOVE → {pct, cat}}`, a 0 for one that does nothing to the column body)
where `out`/`in` are percentages of the **defender's** max HP — the unit every other
estimate here already uses. `nil` is a pair the engine refused to price (`pbRoughDamage`
divides by the defender's defence, 085:3557) and is a different fact from `0.0`, which is
"nothing this body has lands"; the readout prints them as `?` and `0%`.

**What is not in a cell, on purpose:** HP, Intimidate, the Choice lock, entry hazards,
and **priority** — the last one cost a battle before it was written down here
(`team2_vs_team1` 262147 t2: Scizor wins that race on Bullet Punch and the matrix reads
it as lost, because a cell is a damage number and `damage_race` is the thing that orders
the final hit). The
core derives its hit counts and verdicts from the side tables, which are rebuilt every
snapshot, so a verdict decays from `S` to `L` as a body is chipped without a single cell
being re-rolled. Defender-side screens **are** in the numbers, because the engine's own
estimate reads them, so they are in the dirty signature.

**Verdicts.** `W` this body wins the pair, `L` it loses, `S` neither finishes inside
`MATRIX_STALL_HITS` = 6, `nil` unknown. Six, not `RACE_MAX_HITS` = 8, because 8 is a
*cap*: "both at the cap" would need ≤12.5% a hit on both sides and the band would be all
but unreachable. Six each way is a stall decided by crits and status, which these cells do
not carry. There is no free-hit convention — the turn a switch costs belongs to
`candidate_race`, which already charges it.

**Cost.** One save/restore of the board for the whole build (`preserving_board`, factored
out of `fake_battler`), one battler per slot rather than one per pair — the real battler
for a body on the field, so its stages, Mega form and item are in the number, a fake at
its own side's seat for one on the bench, so `pbOwnSide` resolves the screens correctly.
Cells are cached against a per-slot signature (`species, form, ability, item, status,
alive, [move, has PP], stages, seat` — deliberately **no HP**) plus a field signature
(weather, Trick Room, both sides' screens, skill), so a Calm Mind re-rolls one column and
a turn that only moved HP re-rolls nothing. Measured on a full 6v6 board in the stub
harness, where the call count is structural (pairs × directions × moves) and so the same
in the engine: **288 `pbRoughDamage` calls at battle start, 0 on an unchanged board, 48
for one boosted foe**. For comparison the 0.6.4 per-candidate estimators spend 56 on
every decision of that board, unconditionally.

In the engine that is **+27% of decision wall time** — 60 tier battles, portable arm,
trace off: 57.2 s with the grid off against 72.6 s with it on. That is over the 25% the
plan set as the line for reconsidering the default, and reconsidering it produced a
better answer than a number: **the grid follows its readers.** `matrix_wanted?` builds it
when either consumer is on, or when the run is recording a trace (the gauntlet's decision
trace, the shadow observer, the probe), and not otherwise — the same 60 battles come back
at **56.2 s** with the consumers off and nothing recording.

Since both consumers ended up shipping on, the shipped default does pay the 27%; what
the gate buys is that an ablation arm with the consumers off no longer pays for a grid it
never reads, and that `party_matrix=false` — the control run's setting — costs exactly
what 0.6.4 cost. In play the 27% is a few milliseconds a decision; it is batch runs where
it is worth having a switch for. The snapshot key is present either way, `nil` when
unbuilt, because "the core reads this key" is a contract the adapter test holds it to. The known approximation the HP-free signature buys: a move whose power depends
on current HP (Super Fang, Endeavor, Flail, Water Spout) keeps the number it had when the
signature last changed.

**The readout.** `render_realidea_battle.py` prints the grid under every decision, rows our
party and columns theirs, verdicts from the HP both bodies were standing on:

```text
    matrix (own rows x foe cols, verdict from current HP; * = on the field):
                     Heatran*  Gyarados  Latias
      Zapdos*    62% L         W         S
      Magnezone 100% L         W         -
      Slowbro   100% W         S         L
```

`--cells` adds the two damage numbers behind each verdict (trace=true runs only, which is
where the cells are recorded); a switch candidate that is the last answer to something
prints `sole answer to X`. The compact grid is what a plain shadow run carries, which is
what keeps the lean tier file near its 1.6 MB.

**Corpus: no cards, and that is the finding.** Four were written and all four were
dropped after the probe measured them, because none could do the one thing a card has to
do — fail with its key off and pass with it on.

The two `sole_answer` cards **could not be posed at all**. Every lever that makes a body
lose its race against the foe in front — taking more per hit, needing more hits — is a
lever the 0.6.4 switch terms already read and already punish (`entry_incoming_damage`,
the `switchin_race` band, `matchup`). So at a single probe position this rule almost
always agrees with the scoring it refines, and the positions where it disagrees are the
ones the shadow trace shows: four candidates inside twenty-five points of each other,
where which body is worth keeping is a fact about the next four turns. The probe poses
one turn. The two `setup_matrix` cards died to the same arithmetic from the other side: a
setup move's engine base sits ~110 above its attacks on the boards where the boost is
interesting, so adding or withholding 55 cannot move the pick there, and on the boards
where 55 *is* the margin the boost flips nothing.

What pins these rules instead: fourteen core unit tests and twelve adapter tests, both
directions each; the tier suite measured per consumer against a control that reproduces
0.6.4 battle for battle; and the readouts. A card that could hold this needs the probe to
pose a two-body choice where the 0.6.4 terms are within 150 points **and** the matrix
verdicts differ — worth building, and it is the first item of 0.6.6.

The machinery for a Realidea-only card is in place either way, because both rules read a
field only this adapter exports: `make_scenarios.py` grew an `engine` key in the extra
dict and a `--install` argument for it, a card written for one install is printed at
generation time rather than skipped in silence, and the Reborn corpus is byte-identical
with the flag absent. Regenerate the Realidea corpus with:

```bash
python3 _AI-Study/tools/make_scenarios.py --pbs "Realidea V4.1/PBS" --install realidea \
  --out-engine "Realidea V4.1/Data/ai_scenarios.txt" \
  --out-json _AI-Study/scenarios_realidea.json --drop-unresolved
```

#### Measured

**Controls first, because nothing else means anything without them.**

| control | claim | result |
|---|---|---|
| A — all three keys false, tier, both sets, all three arms | reproduces 0.6.4 battle for battle | **360/360 records identical** to `realidea_shadowtrace_gen6ou_0_6_4.ndjson`: every result, every turn count, and every one of the traced decisions. The only textual differences anywhere are the heap addresses inside the two pre-existing engine crash messages |
| A — the published table | the arms come back where 0.6.4 left them | stock 58-58, 4 errors, **50.0%**; portable 83-28-4, 5 errors, **72.2%**; `shadow_check.py` **120/120 observation-free, 54.9% agreement** — 0.6.4's own three figures |
| B — `party_matrix=true` alone | building the grid decides nothing | gen6ou_a **180/180 identical, 4,534 traced decisions identical**, `shadow_check.py` 60/60. The fakes built at both seats perturbed nothing |

**Probe at the shipped defaults: 253/271** (223 cards, four new). The same sixteen
assertions fail that failed at 0.6.4 and 0.6.2, and nothing else moved.

**The two consumers, measured apart.** Tier suite, 240 battles, gen6ou_a + gen6ou_b,
portable arm, paired against the control on (roster, matchup, seed). The stock arm is
bit-identical in every one of these — the required condition before a portable number
means anything.

| arm | record | rate | paired vs control |
|---|---|---|---|
| control (all three off) | 83-28-4, 5 errors | 72.2% | — |
| `sole_answer` alone | 84-26-4, 6 errors | **73.7%** | **gained 2, lost 0** (p = 0.48) |
| `setup_matrix` alone, as first written | 82-29-4, 5 errors | 71.3% | gained 1, lost 2 |
| `setup_matrix` alone, budget fixed | 84-27-4, 5 errors | **73.0%** | **gained 1, lost 0** |
| both, as first written | 82-29-3, 6 errors | 71.9% | gained 2, lost 2 |
| **both, budget fixed — the shipped defaults** | **84-27-3**, 6 errors | **73.7%** | **gained 2, lost 0** (p = 0.48) |

**The shipped build, traced, both sets** (`realidea_shadowtrace_gen6ou_0_6_5.ndjson`):
portable **84-27-3, 6 errors, 73.7%**, stock 58-58 with 4 errors and **50.0% —
bit-identical to the control**, and the shadow arm **120/120 observation-free** at 54.6%
agreement over 3,027 turns (54.9% at 0.6.4). That file is twice the size of its 0.6.4
twin, because every traced decision now carries the grid and, under `trace=true`, the
cells behind it.

**The archetype suite still runs, and both rules are inert on it.** 80 battles in 19
seconds, no errors, portable 24-16 (60.0%) against stock's 20-20 — and paired against the
all-keys-false control it is **identical on all 80**, with exactly one battle's decisions
changing at all (`balance_vs_offense` 262147, a win either way, 14 turns → 8). That is
structural rather than surprising: the frozen fixture is three mons a side, so a decision
sees at most one live benched foe and two own bodies off the field, which is never enough
for "the only answer to a foe still on their bench", and no team in the fixture carries a
setup move at all. Both rules are about bench depth; an eight-slot benchmark of three-mon
teams has none.

It is also where the **doubles** path was exercised for the first time — the tier suite is
singles only. 73 decisions carried a grid, 57 of them with two active foes, and both
seats (1 and 3) decided through it, so one matrix shared by two own actives and
`matrix_slot` resolving seat 3 are checked in the engine rather than only in the unit
tests. The doubles branch of `sole_answer` (take the harsher target) was called on 26
switch candidates and returned nil on every one, for the reason above — so that branch is
still pinned by its unit test alone.

**Reborn, same core, its own control**: one `set_c` sweep at the new defaults is
**60/60 identical to 0.6.4** — same results, same turn counts, and all 2,654 command
records byte-identical. That is the claim "the other study is untouched" measured
rather than asserted: the Reborn adapter exports no `matrix`, so both consumers return
nil on their first line there.

**Both ship on**, which is the disposition rule stated in the plan and the one
`escape_wall_margin` shipped under at +1/−0 in 0.6.4: a consumer ships on when it gains
more paired battles than it loses with the stock arm bit-identical. Read the evidence
for what it is — two battles out of 120 paired, p = 0.48, both in gen6ou_a — and note
what limits the downside: **Reborn exports no matrix**, so neither rule can reach the
other study at all, and either key set false restores 0.6.4 exactly. The probe at the
new defaults is **251/267**, 0.6.4's own number with 0.6.4's own sixteen failures: both
rules together change no card outcome.

The two rules do not interact: the full arm's gains are `sole_answer`'s two battles and
its losses are `setup_matrix`'s two, unchanged. 310 of 3,382 traced decisions differ from
the control, so this is not a rule that never fires — `sole_answer_reserved` is charged
771 times and `sole_answer_exposed` 255 times on gen6ou_a alone, and 124 boosts are
priced above zero by the flip table.

**What the `party_matrix` grid looks like in a readout**, which is the other half of
what this version ships — `team1_vs_team2 104729` t0, Quagsire deciding whether to leave:

```text
    matrix (own rows x foe cols, verdict from current HP; * = on the field):
                     Clefable*  Chansey    Gastrodon  Scizor     Slowbro    Zapdos
      Quagsire* 100% L          L          L          L          L          W
      Altaria   100% L          L          S          S          L          L
      Chansey   100% W          S          W          L          W          W
      Magnezone 100% W          L          L          W          W          L
      Suicune   100% W          L          W          W          S          L
      Zapdos    100% W          L          L          W          W          W
```

Six rows and six columns say in one glance what six turns of reading a candidate list
could not: Quagsire beats exactly one of their six, their Chansey is answered only by
Suicune's stall and their Scizor only by three bodies. `--cells` prints the two damage
numbers behind every verdict.

**What `sole_answer` won**, and it is the case the rule was written from: at
`team2_vs_team1 130363` t15 Chansey is leaving on residual chip and four bodies handle
the Quagsire in front. Scizor is the only one that beats their Chansey, is charged −45,
and drops from 440.8 to 395.8 — behind Clefable and Zapdos, which handle the board just
as well and are worth nothing later. Same shape at `team2_vs_team3 155921` t19. The
charge changed which option ranked first on 12 turns of gen6ou_a.

**What `setup_matrix` lost, and the fix.** Both losses were the same line: the budget
test refused a boost at exactly `post + 1 == theirs` — the boosted attack needing the
same number of turns the foe needs, counting the setup turn — and refusing it as a
**0** silently withdrew the flat 55 that 0.6.4 paid. Scizor's Swords Dance in front of a
Metagross it was in fact winning against on Bullet Punch priority (`team2_vs_team1`
262147 t2; the cells carry no priority term, so the matrix reads that race as lost), and
Clefable's Calm Mind against a Gliscor at 76% (`team3_vs_team1` 104729 t52). The rule
now refuses only what it can see is unaffordable — strictly more turns than the foe
needs — and leaves the tie to the four safety branches that run before it and to the
flat bonus. That is the same principle as the middle answer above: **where this rule has
nothing better to say than the flat 55, it says nothing.**

**Artifacts.** `realidea_tier_0_6_5.ndjson` (the shipped defaults, written with the
three keys named explicitly so the record's `config_overrides` stamp says what it ran
under),
`_control` (all three keys false), `_sole_answer`, `_setup_matrix` and
`_setup_matrix_prefix` (the same key before the budget fix, kept so the two battles it
lost can be read), `realidea_shadowtrace_gen6ou_0_6_5.ndjson` (traced, all three arms, the
shipped defaults), `ai_probe_results_portable.ndjson` (0.6.5; 0.6.4's kept as
`ai_probe_results_portable_0_6_4.ndjson`), and `reborn_6v6_v065trace_set_c.ndjson` for the
Reborn control. The 0.6.5 control run is byte-for-byte the same decisions as
`realidea_shadowtrace_gen6ou_0_6_4.ndjson`, so that file is the control's artifact and is
not duplicated.

### 0.6.6 — the AI can see Levitate, a wall keeps its job, and the oracle says what a perfect read is worth, 2026-09-07

Read off the user's pass over the 0.6.5 gen 5 traces (`realidea_tiertrace_gen5ru_a`,
`gen5uu_a`, `gen6uu_a`). Five root causes were diagnosed there; this version fixes the
first, builds the plumbing the second needs and measures its ceiling, and records the
other three for the version after.

| key | rule | default |
|---|---|---|
| `airborne_immunity` | adapter-side. Ground into a body that is not on the ground does nothing. The engine decides that in `pbSuccessCheck` (080:2710, off `isAirborne?` 080:647 — Levitate, Air Balloon, Magnet Rise, Telekinesis; minus Iron Ball, Ingrain, Smack Down, Gravity), **after** the type modifier every damage estimate reads, so all four were invisible to every estimate this adapter makes. One predicate, `ground_into_airborne?`, now sits under both `type_effectiveness` and `rough_damage_pct!`, so the actor's moves, the incoming map, the bench estimates and the matrix cells all agree. Ring Target, Smack Down/Thousand Arrows (0x11C) and Mold Breaker are the engine's own exceptions | **on** |
| `no_hit_needs_threat` | core. "I cannot hurt it" (`no_effective_move`, `weak_current_attacks`) opens the switch gate only if it can hurt me — the foe needs fewer than four hits, residual included — or the actor has nothing that works on the foe or the field: a status, a hazard below its cap, a phaze, a disruption, a stage reset or an item trick (`walled_but_safe?`, reason `walled_but_safe` 0). A boost, a heal, a Substitute or a Protect does not count | **on** |
| `foe_oracle` | adapter-side. The foe's **registered choice** is read back as its intent and exported as `predicted_incoming_damage_pct` / `predicted_incoming_accuracy` / `predicted_foe` on the actor and `predicted_incoming_damage_pct` on every bench candidate. The core prices the entry hit on the declared move (`entry_hit_pct`: `entry_incoming_damage`, `dies_on_entry`, `safe`, the free hit in `candidate_race`) and decides "you die whatever you click" on it (`certain_lethal_threat?`: the declared hit on its minimum roll, discounted by its hit chance). The worst case stays what the race after entry runs on. A forced replacement never reads it: between turns the registered choices are the ones that have just executed | **off** |

**All three false reproduces 0.6.5 battle for battle**: `realidea_tier_gen5ru_a_0_6_6_control3.ndjson`
against `realidea_tier_gen5ru_a_0_6_5` and the traced subset, 120/120 outcomes and all
204 traced decisions identical (`tools/control_check.py`, new). The stock arm is
bit-identical across every run below (65.0% on gen5ru_a, forty-two times over). The probe
at the shipped defaults is **251/267 with 0.6.5's own sixteen failures**.

**What Levitate cost, and what fixing it cost.** Steelix clicked Earthquake into a
Levitate Rotom on consecutive turns at +500 (`team3_vs_team4 104729` t4–5; stock scored
the same move 0). With the fix alone the shadow arm changes 42 of 933 gen5ru_a decisions
and the live arm goes **46 → 44 of 60, gained 2, lost 4** — and all four losses are the
same body: Steelix, walling a Levitate Uxie at 18% a hit with Toxic, Stealth Rock and
Roar in hand, now leaving at turn 0 on `no_effective_move` +260 and
`weak_current_attacks` +120, because its one attack had finally been priced at the
nothing it always was (`team3_vs_team4 196613` t0: switch → Uxie 664 over Toxic 151).
Stock stayed and laid rocks. That is the second key: a wall that cannot be hurt in a
hurry and has work to do stays.

The first draft of that rule counted any non-damaging move as work, and the probe said
no: it dropped to 250/267, failing the 0.6.3 card
`no_effective_move_needs_a_body_that_breaks_the_wall` — Alakazam with Calm Mind, Recover
and Substitute in front of a Toxic Umbreon, which must leave for Machamp. Boosting an
attack that does nothing, healing and hiding are not a job; Toxic, rocks and Roar are.
The rule that shipped keys on the move's tags (`WALL_WORK_TAGS`), holds the card, and
keeps Steelix in.

**The shipped pair, paired against 0.6.5 over three rosters (180 battles):**

| roster | 0.6.5 | 0.6.6 | gained | lost |
|---|---|---|---|---|
| gen5ru_a | 46/60 | 45/60 | 2 | 3 |
| gen5uu_a | 44/60 | 45/60 | 1 | 0 |
| gen6uu_a | 43/60 | 44/60 | 2 | 1 |
| pooled | 133/180 (73.9%) | 134/180 (74.4%) | 5 | 4 |

Net +1, McNemar p = 1.0: an estimate fix that changes 30 of 933 shadow decisions (13
switch → move, 7 move → switch) and no outcome you can measure. That is the right shape
for a bug fix — the wins it should buy are in battles a Levitate body decides, and
gen5ru_a has two of them on one team.

**The oracle: what a perfect one-turn read is worth to *these* rules.** The user's
question was whether an input-read cheat would teach anything, and the honest answer at
0.6.5 was no — the core had no consumer for "the foe will click X"; every rule read the
collapsed worst case. So the consumer was built first (the three `predicted_*` fields
above and the two places the core reads them), with the oracle as its first producer.
The same consumer takes a predictor's output unchanged, which is the point: a model that
guesses the move will be judged against this number.

On identical boards (`shadow_ship` → `shadow_oracle2`, gen5ru_a, 933 turns) the oracle
changes **79 decisions (8.5%)**, 63 of them move → switch — a bench body that the
worst-case estimate called dead on entry is alive under the declared move. The
declared move was **below the worst case on 328 turns (35.2%)**, by 50.8 points on
average, and was a status move, a switch or an immune hit on 147 (15.8%); of 480
worst-case lethal alarms, 45 (9%) were not backed by the declared move. Live, paired
against 0.6.5:

| roster | 0.6.5 | oracle | gained | lost |
|---|---|---|---|---|
| gen5ru_a | 46/60 | 50/60 | 6 | 2 |
| gen5uu_a | 44/60 | 51/60 | 9 | 2 |
| gen6uu_a | 43/60 | 42/60 | 8 | 9 |
| pooled | 133/180 (73.9%) | 143/180 (79.4%) | 23 | 13 |

**+10 net, +5.6 points, p = 0.13**, and against the shipped 0.6.6 itself +9 (22/13,
p = 0.18). Read it as a ceiling with two caveats. First, it is uneven: both gen 5
rosters gain 4 and 7, gen6uu_a nets nothing on 17 flips — its battles run 39 turns and
the same oracle measured 47/60 on that roster one build earlier (before the wall rule,
`_live_oracle`), so five wins there are inside the noise. Second, it is the ceiling of
**this consumer**, not of perfect information: on 162 of the 933 turns the actor was
slower and certain to die under the declared move, and on 131 of them the oracle still
clicked an attack (`ko_never_lands` strips the +500 and leaves `engine_base` and
`expected_damage` standing — root cause 3 of the readout), and a declared Sucker Punch
is priced as a full hit on a switch-in the engine would fail it against. Both are
consumers the perfect read is not yet allowed to reach.

What that settles for the next step: a real predictor is worth building only as a
producer for this consumer, and its value is bounded by roughly +5 points times its
accuracy against the oracle. The 0.6.5 traces put the damage-argmax at 54.9% and a
lock → repeat → argmax ladder at 57.6%; a distribution (damage-weighted, a status lump,
the exact-information layer from Choice lock / Encore / Outrage / two-turn moves) feeds
the same fields as an expectation and a death probability, and its number is judged
here.

**Tools.** `tools/control_check.py` (a run reproduces its predecessor: outcomes per
battle, decisions per traced turn), `tools/shadow_pair_diff.py` (two shadow runs of the
same battles, turn by turn, with the boards checked identical first),
`tools/compare_versions.py` now reads the Realidea schema (`mode`/`teams`), and
`render_realidea_battle.py` prints the declared move and the per-candidate declared hit
when a run read one.

**Artifacts** (all gen5ru_a unless named): `_control` (Levitate off, oracle off, before
the wall rule existed), `_control2`, `_control3` (all three keys off; the last is the
shipped build), `_live_default` × 3 rosters (Levitate on, no wall rule — the run that
found the Steelix regression), `_live_oracle` × 3 (same build, oracle on),
`_ship` × 3 and `_oracle` × 3 (the shipped build), `_shadow_base` / `_shadow_air` /
`_shadow_ship` / `_shadow_oracle` / `_shadow_oracle2` (traced; the last two are the
oracle before and after the wall rule), and `ai_probe_results_portable_0_6_6.ndjson`
(0.6.5's kept as `_0_6_5`). Per-run summaries and the engine error files are under
`generated/readouts/`; every error is the known `pbRoughDamage` ZeroDivision or a
Struggle turn.

**Reborn is not the control for this version and has not been re-run.** `airborne_immunity`
and `foe_oracle` are Realidea-adapter-side and cannot reach it, but `no_hit_needs_threat`
is a core rule that Reborn's own exports (`no_effective_move`, `incoming_damage_pct`)
do reach. The installed Reborn bundle is still 0.6.5; rebuilding it is a measurement,
not a formality.

### 0.6.7 — a hit that never lands is not worth its score, 2026-09-07

Read off the user's question on the 0.6.6 oracle trace: `gen5ru_a team3_vs_team4 104729`
t10, a Sceptile at 100%, slower by one point, facing a **declared** Acrobatics of 198%,
clicked its own Acrobatics at 410 over a switch to Uxie at 234. The core knew it was dead:
`ko_never_lands` fired and stripped the +500 kill call. It stripped nothing else —
`engine_base` +260, `expected_damage` +80 and `super_effective` +70 stayed on a hit the
actor does not live to throw — while on the switch side the same fact was worth exactly
`escape_lethal_threat` +130. That was the "131 of 162" consumer gap the 0.6.6 write-up
closed on, and it is the whole of this version.

| key | rule | default |
|---|---|---|
| `dead_before_moving` | core, in `score_move` after every other term. When the actor is slower (`faster == false`; unknown is not slower), the move has no priority, and `certain_lethal_threat?` holds — the declared hit on its minimum roll discounted by its hit chance under the oracle, the strict worst-case figure otherwise — the move's whole score is scaled to a quarter (`DEAD_BEFORE_MOVING_SCALE`, reason `dead_before_moving` with the amount removed). Every non-priority move is scaled alike, so the **order among the moves is what it was**: the rule never changes which move is clicked, only whether a switch that has its own reason to exist wins over it. A priority move keeps its whole score, because it lands. Under `priority_gate`, like `ko_never_lands` | **on** |

Not zero, for two reasons. The death is certain only on an estimate, and a quarter keeps
the moves ranked among themselves on the turns where no switch is allowed — a trapped
actor, or one below the 50% pivot line where `escape_lethal_threat_while_healthy` does
not open the gate — so those turns play exactly as before. What the rule does NOT do is
judge the sack: Uxie switching in on that turn eats the declared 44% and then loses the
race two hits to two on speed, while a Uxie that comes in free after Sceptile dies wins it
two to three. The `switchin_race` +10 on that candidate is the durability band (three of
the foe's hits), not a race verdict; the consumer that asks who lands the last hit after
entry (`kill_order`) has been off since 0.6.4 measured it, and `losing_race_bench_wins`
read the same race and correctly did not fire. Whether to preserve a 100% body or spend
it for a free entry is the open question the rule leaves where it found it.

**Key off reproduces 0.6.6 battle for battle**: `realidea_tier_gen5ru_a_0_6_7_control.ndjson`
against `_0_6_6_ship`, 60/60 portable outcomes and all 894 traced decisions identical
(`tools/control_check.py`). The stock arm is identical to 0.6.5 on all three rosters
(paired 0/0). Probe **251/267, the same sixteen failures**. The four new core cards cover
the Sceptile turn, the preserved move order, a Quick Attack that now outranks the attack
that never happens, and the trapped / low-HP actor keeping its click; the first draft of
the rule failed `priority_gate_off_restores_slot_order_among_knockouts` and is the reason
it sits under `priority_gate`.

**Shipped (oracle off), 180 paired battles, 0.6.6 → 0.6.7:**

| roster | 0.6.6 | 0.6.7 | gained | lost |
|---|---|---|---|---|
| gen5ru_a | 45 | 48 | 5 | 2 |
| gen5uu_a | 45 | 47 | 3 | 1 |
| gen6uu_a | 44 | 45 | 3 | 2 |
| **pooled** | **134 (74.4%)** | **140 (77.8%)** | **11** | **5** — McNemar p = 0.21 |

Against 0.6.5 the shipped build is now +7 net (gained 15, lost 8, p = 0.21). The gains are
the pattern the rule was built for: `team1_vs_team3` on gen5ru_a is won on three seeds
where a Qwilfish or Rhydon in front of a Magneton's Volt Switch, or a Kabutops' Waterfall,
now leaves for the Rotom or Sceptile that answers it instead of clicking an attack it
never throws. One of the five losses is the Sceptile battle itself, on this arm without
the oracle: at t14 Aerodactyl at 90% is "certain dead" on the worst-case figure (Rotom's
Shadow Ball 125%, faster), leaves for Steelix, Steelix leaves for Uxie, and the foe had
not attacked at all — 0.6.6 stayed, hit, and won in 28 turns. That is a wrong *certainty*,
not a wrong rule, and the oracle arm wins the same battle in 19 turns.

**Oracle (foe_oracle on), 180 paired battles, 0.6.6 → 0.6.7:**

| roster | 0.6.6 | 0.6.7 | gained | lost |
|---|---|---|---|---|
| gen5ru_a | 50 | 51 | 4 | 3 |
| gen5uu_a | 51 | 52 | 2 | 1 |
| gen6uu_a | 42 | 47 | 6 | 1 |
| **pooled** | **143 (79.4%)** | **150 (83.3%)** | **12** | **5** — p = 0.15 |

Oracle over ship at 0.6.7: 140 → 150, gained 21, lost 11, p = 0.11 — the ceiling a perfect
read is worth is still about +10, now on top of a higher floor. **Oracle over 0.6.5:
133 → 150, gained 29, lost 12, p = 0.012**, the first pooled comparison in this study to
clear 0.05. The gen6uu_a oracle arm, which had been the odd one out at 0.6.6 (42 of 60,
one build after 47), is back to 47.

**What the rule reaches** (`tools/dead_slower_turns.py`, new: the core's own predicate over
a traced run). Slower-and-certain-dead turns on the three oracle rosters went 344 → 371 (the
rule keeps bodies alive into more such turns), attacked 252 → 210, switched 92 → 161; on
gen5ru_a 58 of the 60 turns with a switch the gate allowed now switch. The 210 that still
attack are turns with no open switch — trapped, or under the 50% pivot line — which is
the gate's decision, not this rule's. The shadow pair (`_0_6_6_shadow_oracle2` →
`_0_6_7_shadow_oracle`, 933 identical boards) changes 49 decisions: 36 move → switch and
13 move → move, every one of the thirteen a priority move that now outranks the attack —
Aqua Jet on Kabutops and Feraligatr, and **Endure on Escavalier**, seven times, twice on
consecutive turns where the second one fails. Endure at 112 there is the stock engine's
base score for a move that only delays the same death by a turn; it belongs with the
Protect item in *outstanding* rather than here. The shipped shadow pair changes 50
(34 → switch, 16 move → move, same shapes).

**Reborn has not been re-run for this version either.** `dead_before_moving` is a core
rule and reaches Reborn's exports (`faster`, `incoming_damage_pct`, `priority`); the
installed Reborn bundle is still 0.6.5, so there are now two core rules whose Reborn
number is unmeasured.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_6_7_control.ndjson`, `_ship` × 3
rosters, `_oracle` × 3, `_shadow_ship` and `_shadow_oracle` (gen5ru_a, traced),
`ai_probe_results_portable_0_6_7.ndjson` (0.6.6's kept as `_0_6_6`), summaries and error
files under `generated/readouts/` (every error the known `pbRoughDamage` ZeroDivision).
Backup of the pre-install bundle: `backups/realidea_Scripts.rxdata.pre-0.6.7`.

### 0.7.0 — a second planner behind the same seam, 2026-09-07

Every version to here tuned one scorer. `score_move` and `score_switch` sum 107 reason
terms over the actions available *this turn*, and the twenty-six config keys switch those
terms on and off. The matrix (0.6.5) and the oracle (0.6.6) widened what a term may read,
but the shape never changed: score each action, click the best one.

0.7.0 adds a **second planner** that answers a different question — what is the board
worth after the turn — and puts it behind the seam the adapter already went through.
Nothing about the rule engine changes. `search_planner` picks which planner runs, it is
**off**, and with it off this build reproduces 0.6.7 battle for battle.

**Where the idea comes from.** Foul Play (https://github.com/pmariglia/foul-play, GPL-3.0)
over poke-engine (https://github.com/pmariglia/poke-engine). Three ideas are borrowed and
**no code is** — nothing here is derived from either repository, so the GPL does not
attach:

| borrowed | as implemented here |
|---|---|
| `safest` — maximin over the joint grid | an action is worth the **worst** the foe can do to it, not its average or its best. Ties in the minimum break on the mean, then on a stable key |
| a state-value leaf | the board after the turn is scored, not the move that produced it: `±2.0` a faint, `±1.0` the `cell_verdict` on the pair left standing, `±0.2` the HP differential. The faint band sits outside the verdict band on purpose, so a kill outranks every standing position |
| simultaneous moves (DUCT) | the foe is a **set** of options resolved at the same time — keep attacking, or bring in any live bench body — never one predicted move |

Deliberately **not** borrowed this version: damage-roll grouping by faint threshold (a
cell carries one expected roll), reversible instructions (unnecessary — the snapshot is a
plain Hash and `Model.copy_hash` is the whole undo), and Smogon-corpus set prediction,
which is the predictor backlog item and feeds the same snapshot fields either way.

**Structure.** The matrix readers moved out of `core.rb` into `portable_ai/matrix.rb`
verbatim — `matrix_cell`, `cell_verdict`, `matrix_answers`, `hits_needed` and the rest,
still under `PortableAI.`, so every caller and every existing test is unchanged. The two
planners now share exactly one thing, the board readers, and none of the scoring. Load
order is `model → effects → matrix → core → search`, and both new files are in the
bundler's engine-free check. The adapter's two `PortableAI.plan` call sites became one
`run_planner`, which is the only code that knows there are two planners.

**What the search planner declines.** It returns `nil` — and the adapter falls through to
the rule engine — on doubles, on any snapshot without a matrix, and on any board it cannot
resolve. That last one covers the forced-replacement path with no special case: the actor
there is fainted, a fainted body holds no matrix seat, so there is no board.

**Reborn is inert by construction, not by config.** Its adapter still calls
`PortableAI.plan` directly — it was not edited, and `run_planner` exists only in the
Realidea adapter — so `search.rb` ships in its bundle and is unreachable from it. Even if
it were reached, Reborn exports no matrix and the planner would decline. That is what
keeps the Reborn gauntlet a clean control for this version.

**One honest limit, documented in the code.** A cell is one number — the best that body
has against that one — so against a *switching* foe every move we could click is credited
the same damage. That is what the snapshot carries, not an approximation to tighten:
per-move damage exists only against the body on the field. The consequence is that the
foe-switch column cannot order our moves against each other, only moves against switches,
and it is why the tiebreak on the mean exists. Without it the collapse would fall through
to the action key and the planner would click move slot 0 in every position where a foe
switch is the worst case.

**Key off reproduces 0.6.7 battle for battle**: `realidea_tier_gen5ru_a_0_7_0_control.ndjson`
against `_0_6_7_ship`, 120/120 battles identical in result, turns and decision
(`tools/control_check.py`), stamp `0.7.0`. The shadow arm gives the decision-level half:
`_0_7_0_shadow_control` against `_0_6_7_shadow_ship`, 60 paired battles, **933 of 933
turns the same answer** (`tools/shadow_pair_diff.py`) — the same 933 boards 0.6.7 was
measured on. All 332 Ruby tests pass (163 core, 116 Realidea adapter, 53 Reborn adapter)
and 28 Python tooling tests.

**Measured, and it loses badly.** gen5ru_a, 60 paired battles, `search_planner=true`
against the same build with it off:

| arm | wins / 60 | |
|---|---|---|
| rule engine (0.7.0 control) | **48 (80.0%)** | |
| search planner | **31 (51.7%)** | −17, gained 4 lost 21, McNemar p = 0.001 |
| stock v16 engine AI | 39 (65.0%) | identical in both runs — the control that says the rosters did not move |

It is beaten by the rule engine decisively and **it is also beaten by the stock engine AI
it was meant to improve on**. On the shadow arm it answers differently on 408 of 933 turns
(43.7%), and the shape of the disagreement is one-directional: 216 move → switch against
39 switch → switch. It flees.

**Two bugs were found and fixed by measuring it, and both are worth writing down.**

1. **A foe switch-in inherited the outgoing body's HP.** `project` moved `foe_slot` and
   left `foe_hp`, so with the active foe chipped every one of its switches read as a free
   kill — five of six foe options scoring +2, and maximin choosing between fictions.
   Fixing it moved individual battles and **not the total** (25 → 25): the errors were
   symmetric across the arms.
2. **The matrix cells were used as a per-turn damage number, which is exactly what they
   are not.** A cell deliberately carries no Choice lock, no Intimidate, no hazards and no
   priority — it answers "does this body beat that body". Read as "what happens this turn"
   it said a Choice-Scarf Galvantula locked into a 24% move would hit Sceptile for a 174%
   Bug Buzz, so a healthy Sceptile scored every move as a certain death and switched out.
   The board now carries the actor view's own `incoming_damage_pct` and `faster` for the
   pair **on the field** — the Choice-aware numbers every rule in `core.rb` already reads
   — and falls back to cells only for hypothetical pairs. That fix is worth **+6** (25 →
   31). Its lesson generalises past this planner: **the wide, thin view and the narrow,
   thick one are not interchangeable, and the section header in `matrix.rb` says so.**

**What is left is the design, not the bugs.** The remaining gap is structural and visible
in the payoff rows (`search_row`, exported on every candidate): on 38% of turns every move
ties on the worst case, because 41% of worst cases come from a foe switch and against a
switch every move is credited the same cell damage. One ply also means a switch is judged
on the turn after entry and no further, which is the half of the matchup argument the rule
engine's `sole_answer` and `candidate_race` cover and this does not. A second ply and a
per-move estimate against off-field bodies are the two things that would change the shape;
neither is cheap, and neither is worth doing before someone wants the number.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_7_0_control.ndjson`, `_search`,
`_shadow_control`, `_shadow_search`. Backup of the pre-install bundle:
`backups/realidea_Scripts.rxdata.pre-0.7.0`.

### 0.7.1 — the search planner audited against its source, 2026-09-07

The 0.7.0 planner was read side by side with the code it was modelled on
(`pmariglia/poke-engine` `src/search.rs` and `src/genx/evaluate.rs`, `pmariglia/foul-play`
`fp/search/main.py`, cloned at their 2026-09 heads). Two corrections to the provenance
first: the ancestor is poke-engine's **legacy** `expectiminimax_search` + `pick_safest`
path, which Foul Play no longer calls — the bot runs the engine's MCTS (decoupled UCT with
a sigmoid over `evaluate`) — and "DUCT" in the 0.7.0 header named that MCTS, not the
maximin grid. What matches the original: maximin, the 50/50 speed-tie branch, switches
before moves, a switching side dealing nothing, priority over speed.

**Four deviations explained the fleeing, and all four are fixed.** Key unchanged
(`search_planner`, still **off**); false still reproduces 0.6.7 — verified below.

1. **The leaf had the original's weighting inside out.** poke-engine's `evaluate` is a
   *party-wide* sum — every live body is worth 100 × its HP fraction plus 30 for being
   alive, boosts 15–30 a stage, Substitute 75, hazards and status subtract — and it has
   **no matchup term at all**. HP is the currency. 0.7.0 made the pair verdict worth 1.0
   and HP a 0.002-per-point tiebreak with a flat 2.0 faint, so any W-verdict bench body
   beat attacking whatever hit it ate on entry, and losing a 5% body cost the same as
   losing a full one. The leaf is now the original's shape: one point per HP percent on
   every live body of both parties, `BODY_ALIVE` 30 per body, the verdict kept as a
   ±25 tilt (under one alive bonus, so it can never buy a switch that eats a real hit),
   and `BATTLE_OVER` ±1000 when a side has nothing left (the original's `100 × depth`).
2. **Accuracy was a damage multiplier; the original branches hit and miss.** Because
   the leaf is a step at 0 HP, a 70% move that kills outright read as a certain 70% hit
   that left the foe standing, and a 90% move that kills by three points read as no
   kill at all. `payoff` now averages the hit leaf and the miss leaf at the move's
   accuracy, the same way it already averaged the two speed orders. The test that
   codified "half accuracy lands half its damage" is replaced by one that pins both
   directions of the error.
3. **A trapped foe still had a switch column.** The original's option generator respects
   trapping; the adapter computed `has_legal_switch?` but exported `trapped` on the actor
   only. `battler_view` now exports it on targets (the rule engine never reads it there,
   which is what keeps the control clean) and `foe_options` returns only `stay` when it
   is true. Since 41% of worst cases came from a foe switch, a trapper's whole advantage
   was invisible.
4. **Own switch candidates read the wide, thin cell for the hit they eat** although the
   action already carried the Intimidate-aware, every-foe-move `incoming_damage_pct` from
   the fake-battler roll. Same class as 0.7.0's bug 2, unfixed for candidates. `foe_damage`
   now reads the candidate's own number and falls back to the cell only for a pair nothing
   else priced.

**Control.** `realidea_tier_gen5ru_a_0_7_1_control.ndjson` against `_0_7_0_control`: 120/120
identical (result, turns, decision; `tools/control_check.py`). 167 core tests (two new, five
rewritten), 116 Realidea, 53 Reborn, 28 tooling; bundle rebuild byte-identical.

**Measured.** gen5ru_a, 60 paired battles, `search_planner=true`:

| arm | wins / 60 | |
|---|---|---|
| rule engine (0.7.1 control) | **48 (80.0%)** | identical to 0.7.0 |
| search planner 0.7.1 | **36 (60.0%)** | vs 0.7.0 search: +5 (gained 15, lost 10, p = 0.42); vs rules: −12 (gained 7, lost 19, p = 0.031) |
| search planner 0.7.0 | 31 (51.7%) | |
| stock v16 | 39 (65.0%) | identical in every run |

**The fleeing is gone.** Shadow arm, same 933 boards: 0.7.1 differs from 0.7.0 on 259
turns and **205 of them are switch → move**, 6 the other way. Against the rule engine it now
differs on 322 turns split 67 move → switch against 53 switch → move — balanced — and the
largest class is **167 move → move**: same decision to stay, a different click. The
losses cluster in team3/team4 (−5, −4); the search arm's battles run 15.5 turns to the
rules' 13.9.

**What the 167 say is what is left, and it is still design.** Read off the examples: two
moves that both kill tie at `BATTLE_OVER` and fall to the key (no margin, no side effect,
no self-cost — Superpower ties X-Scissor); against a foe switch every move is still one
cell number; a non-damaging move (setup, heal, Protect, status) still projects as a wasted
turn, the one 0.7.0 limit the audit found undocumented. The original models all of those
through its instruction generator and `evaluate` (boosts 30 a stage, Substitute 75). Those
are the next three, in that order, and the first is cheap: `matrix_transform_cell` and the
exported `effect_kind`/`effect_stat`/`drain_fraction` already carry what a boost or heal
projection needs. The planner still ships off.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_7_1_control.ndjson`, `_search`,
`_shadow_search`. Backup of the pre-install bundle: `backups/realidea_Scripts.rxdata.pre-0.7.1`.

### 0.7.2 — what a turn changes besides HP, 2026-09-07

The audit's one undocumented 0.7.0 limit: a non-damaging move projected as a wasted turn,
so the search planner could never click a setup, heal, Protect, Substitute, status or
hazard move on purpose, and it priced Superpower's kill exactly like X-Scissor's. The
original's instruction generator models every one of those and its `evaluate` prices them
(boosts 30 a stage of offence or speed and 15 of defence through a diminishing multiplier,
Substitute 75, Toxic 30, burn 25, paralysis 25, sleep 25, freeze 40, Stealth Rock 10 a
body, Spikes 7 a layer a body, Sticky Web 25). 0.7.2 projects them at those numbers. Key
unchanged, still **off**; false reproduces 0.7.1 (120/120, `tools/control_check.py`).

**The turn is now two acts in speed order** (`project` → `act_own`, `act_foe`), after both
switches resolve. Our act deals the damage and then applies what the move does besides:
recoil and drain off the damage dealt, a self-KO, setup stages (Belly Drum fails at or
below half and pays half above it), a self-drop's stages (`Effects::SELF_DROP_STAGES`, the
same shape as `SETUP_STAGES`, a row for every `self_drop` id and a test that says so), a
certain self-raise, a heal (`Effects.heal_amount`, hoisted out of the core), Protect
(which **fails on a repeat** — the planner now leaves the same memory record the rule
planner does, `Effects.memory_updates`, also hoisted, because the projection reads the
counter back), Substitute (a quarter of HP, and it absorbs the foe's hit whole and breaks
unless the hit was under its own HP), a hazard (per live foe body, only below the layer
cap), and a status or stat drop on the foe **at the chance the adapter exported** — 100 for
a status move the engine says can land, 0 for one it says cannot, the secondary rate for a
damaging move, so Scald's burn is worth 25 × 0.3 and Toxic into a Steel type nothing. A
miss applies none of it. The foe's act is its hit, taken whole by Protect or a standing
Substitute.

**The board carries the terms the leaf reads**: the actor's own stages (decoded from the
engine's PBStats array), which empty on a switch and transform the pair's cell through
`matrix_transform_cell` so a Dragon Dance flips the verdict as well as paying its 60; the
foe's boost as its exported positive-stage count at 25 each, zeroed when it switches; and
the deltas this turn makes — status landed, hazard laid, Substitute standing, Rest's sleep.
A body's existing status is deliberately not re-counted: every row carries it alike.

**Measured.** gen5ru_a, 60 paired, `search_planner=true`:

| arm | wins / 60 | |
|---|---|---|
| rule engine (0.7.2 control) | **48** | identical to 0.7.0 and 0.7.1 |
| search 0.7.2 | **39 (65.0%)** | vs 0.7.1 search +3 (gained 6, lost 3, p = 0.51); vs rules −9 (gained 6, lost 15, p = 0.081) |
| search 0.7.1 | 36 | |
| stock v16 | 39 | |

31 → 36 → 39 across the two fixes. It now equals the stock AI it was meant to improve on
and is nine behind the rule engine, no longer significantly. Shadow arm: 189 of 933 turns
differ from 0.7.1, **162 of them move → move** (20 switch → move, 7 the reverse — the
switching is settled); against the rules 378 differ, 227 move → move, 61/60 on switches.

**What the 227 are.** 107 both damaging, and there the rules' pick deals more damage on 63
to the search's 31 — the foe-switch collapse: 190 of the 227 had a foe switch column, and
on 91 the rules' pick ties the search's exactly on the worst case, so the click fell to the
mean or the key. A guaranteed kill on an 11% Golurk is never the worst case because the
foe can dodge it for free by switching, and a 20% Defence-drop secondary that lands on the
switch-in outranks it (Feraligatr 130363 t2: Crunch over Aqua Jet). 72 are the rules
attacking where the search sets up or lays a status — the new terms being used, net
positive on the total — and 32 both status. **The remaining gap is one ply**: the original
runs this same grid to depth 3 and more under iterative deepening, and at depth 1 its own
`pick_safest` has the identical collapse. Nothing cheaper than a second ply changes it; a
tempo cost on the foe's switch would be inventing a term the original does not have.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_7_2_control.ndjson`, `_search`,
`_shadow_search`. Backup: `backups/realidea_Scripts.rxdata.pre-0.7.2`. Tests: 175 core (8
new), 116 Realidea, 53 Reborn, 28 tooling.

### 0.7.3 — the second ply, 2026-09-07

`search_depth` (default 2). A cell's value at depth two is no longer the leaf of the
projected board but the **safest reply grid from it** — the original's expectiminimax,
which scores a sub-game by `pick_safest`, with its row pruning (a row whose running
minimum has fallen to the best row's cannot win, so the rest of it is never projected).
Below the root the options follow the bodies on the field: while the same two stand
there the root's exported moves and switches are the truth and are reused; any other
pair has only the matrix, one attack worth the cell and the bench off the side table.
After a faint the ply is a replacement — the side that lost a body picks from its bench
and the other side does nothing, the original's `force_switch` shape — and a finished
battle is worth `BATTLE_OVER` plus 100 a ply left, the original's `100 × depth`. A
projected Attack or Special Attack stage scales the next ply's damage by the category of
the body's best hit into that foe (`out_cat`), a defence stage divides what comes in, a
speed stage decides who moves first, Protect fails on the ply after a Protect, and one
status per body. Cost: 14 ms a decision at depth 2 against 1 ms at depth 1 in modern
Ruby; the tier run took 101 s against the usual 60.

**The bug the second ply exposed, and the number it produced first: 15/60.** The board
carried one HP per side — the body on the field. At depth one a damaged body never left
the field before the leaf, so it never mattered. At depth two a body that took a hit and
switched out came back at its side-table HP, and since the foe's worst case is usually a
switch, **every hit we landed was erased** and only stages, hazards and status survived a
ply. The planner clicked Rock Polish and Stealth Rock everywhere (shadow: 575 of 933
decisions changed, 167 move → switch) and won 15 of 60. It is the mirror image of 0.7.0's
first bug, where a foe switch-in inherited the outgoing body's HP. The board now carries a
per-slot HP map for both sides (`own_hps` / `foe_hps`), every projection writes the on-field
body back into it, a switch-in reads it before the table, and the leaf sums it. Test:
`test_search_remembers_the_hp_of_a_body_that_left_the_field`.

**Measured, with the map.** gen5ru_a, 60 paired, `search_planner=true`:

| arm | wins / 60 | |
|---|---|---|
| rule engine (0.7.3 control) | **48** | 120/120 identical to 0.7.2 |
| search depth 2 (0.7.3) | **40 (66.7%)** | vs depth 1: +1 (gained 10, lost 9, p = 1.0); vs rules: −8 (gained 7, lost 15, p = 0.14) |
| search depth 1 (0.7.2) | 39 | |
| stock v16 | 39 | |

**Depth does not pay on this picture.** The second ply changes 260 of 933 shadow decisions
(148 move → move, 65 switch → move, 31 the reverse) and the total does not move. That is
the answer to the question 0.7.2 left open, and it is the one this file predicted a version
early: looking further through the same thin picture finds the same picture's plan. The
collapse that decides most of the 259 move → move disagreements with the rules is not a
depth problem — against a foe switch every move is still credited the one cell number, at
every ply — so the next thing worth building is the per-move estimate against the foe's
bench bodies (the audit's third item), an adapter export off the fake bodies the matrix
pass already builds. Until then depth 2 stays the default because it is not worse and it
is the shape the original runs; `search_depth=1` is the ablation.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_7_3_control.ndjson`, `_search`,
`_shadow_search` (both with the map; the 15/60 run was not kept). Backup:
`backups/realidea_Scripts.rxdata.pre-0.7.3`. Tests: 181 core (6 new), 116 Realidea, 53
Reborn, 28 tooling.

### 0.7.4 — each move against the bench, and two terms that were wrong, 2026-09-07

**The export.** `matrix_cell` (adapter) already rolled every damaging move the row body has
to find its best; it now keeps them all on the cell as `out_moves` (`{MOVE → {pct, cat}}`,
`MATRIX_VERSION` 2), a 0 for a move that does nothing to that body. No new engine calls,
no new fakes, and the cache reuses the list with the cell. The search's `own_damage` reads
the clicked move's own number against a foe switch-in (`cell_move`), falling back to the
one best number for a cell without the list, and takes the move's own category for the
stage multiplier. Test: `test_search_prices_the_clicked_move_against_a_foe_switch_in`,
`test_search_prefers_the_move_their_bench_cannot_wall` (two 40s on the field, one of them
walled by the bench: the list decides, slot order no longer does).

**Two things found on the way, both real.**

*The root's stages were counted twice.* Every number the root exports — `expected_damage_pct`,
the live pair's cell, the side table's Speed — is rolled through the actor's real stages
(`pbRoughStat` applies `stagemul`/`stagediv` unconditionally, 085:2930). `offence_multiplier`,
`defence_divisor` and the speed transform then scaled them by `own_stages` again, so a +2
body read as +4 from 0.7.1 on. The board now carries `stage_base` (the root's real stages,
cleared with a switch) and `projected_stages` (stages less base) is what scales a number;
the leaf's boost term still reads the whole stack, because a switch really does lose it.
Test: `test_search_does_not_scale_the_root_numbers_by_stages_they_already_carry`.

*The leaf's verdict term.* Through 0.7.3 the leaf added ±25 for the pair left standing
(matrix.rb's W / L) — a term the original does not have, kept "small on purpose" after
0.7.0 had it at the top of the scale. Removed. The pair's matchup is already in the sum,
as the HP each side stands to lose at the next ply, which is where the original keeps it.

**Measured, in steps.** gen5ru_a, 60 paired, `search_planner=true`, depth 2, rules 48 and
stock 39 throughout; the key-off control reproduces 0.7.3 on all 120 battles.

| build | wins / 60 | |
|---|---|---|
| 0.7.3 | 40 | |
| + stage fix only (per-move off, verdict on) | 41 | vs 0.7.3: gained 1, lost 0 |
| + per-move (verdict on) | **35** | vs stage-only: −6 (gained 7, lost 13, p = 0.26); 4 errors, 1 draw |
| + per-move, verdict off = **0.7.4** | **40** | vs 35: +5 (gained 14, lost 9, p = 0.40); vs 0.7.3: gained 11, lost 11, p = 0.83; vs rules: −8 (gained 6, lost 14, p = 0.12) |

The two ablation arms were scratch patches of the built file (`priced = nil`;
`VERDICT_VALUE` zeroed), each reinstalled over by the real build and byte-checked; their
runs are kept as `_0_7_4_ablate_permove_search` and `_0_7_4_ablate_verdict_search`, and the
shipped 0.7.4 search arm is decision-identical to the verdict-off arm (60 battles, 1024
decisions, `control_check`).

**What the honest column does under maximin.** With every move priced on its own, an
attack's worst case is the bench body that walls it, so an attack the bench can wall reads
as a poor row at every ply — Sceptile's Earthquake into Magneton went from +35 to −63,
because their Flying-type can come in for nothing. That is the original's own shape and it
is the reason its author moved to MCTS: pure `pick_safest` is passive against an opponent
that does not actually make the safest reply, and stock v16 switches on triggers, not on
walls. With the verdict term still in, the passivity had somewhere to go — the pre-emptive
switch to the W-verdict body — and that cost five wins (46 move → switch on the shadow arm
at 35/60). Without it the search attacks again and the total returns to 40. The shadow arm
against 0.7.3: 223 of 933 decisions differ (159 move → move, 46 move → switch, 15 the
reverse), and the wins are the same 40 with eleven battles swapped each way.

**Where this leaves the search.** The three audit items are built (leaf, accuracy branch,
per-move against the bench), the two projection bugs are fixed, depth is a key, and the
planner is 40/60 against the rules' 48 on every build since 0.7.2. The picture is no longer
thin; what remains is the opponent model. Maximin assumes the foe makes the reply that is
worst for us, and the measured foe does not — so the next thing that could move this number
is not another term but a weighting over the foe's replies (the original's MCTS answers
exactly this; a cheaper first step is scoring a row by its worst *likely* reply, with the
foe's switch columns weighted by whether stock v16 would actually take them). Cost is flat:
12 ms a decision at depth 2 in modern Ruby (`bench.rb`), the tier run 101 s. Ships **off**.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_7_4_control.ndjson`, `_search`,
`_shadow_search`, `_ablate_permove_search`, `_ablate_verdict_search`. Backup:
`backups/realidea_Scripts.rxdata.pre-0.7.4`. Tests: 184 core (3 new, 4 restated without
the verdict), 117 Realidea (1 new), 53 Reborn, 28 tooling.

### 0.7.5 — the opponent model, 2026-09-08

0.7.4 left the search at 40/60 with the picture no longer thin and maximin named as the
limit: an attack's worst case is the bench body that walls it, and the measured foe does
not make that reply. This version puts a number on the opponent model and builds two
producers of it, one honest and one not.

**The search side: `search_foe_mix`.** A root row is scored `(1 − mix) × min + mix × E`,
where E is the row's expectation under one weight per foe column (`column_weights`): the
predicted switch chance on the predicted slot (or shared over every switch column when the
slot is unknown), the rest on the stay column; uniform when nothing was predicted. 0 is the
original's `pick_safest` and reproduces 0.7.4. The board carries the prediction as
`foe_reply`, this turn's only (`project` drops it), and every ply below the root stays
maximin — see the ablation.

**The adapter side: `foe_stock_model`.** The oracle (0.6.6) reads the foe's registered
choice — a perfect one-turn read, and cheating. This is the second producer on the same
path (`foe_intents` → `predicted_incoming` → `predicted_foe`): what stock v16 would do,
read from its own code without the dice. `stock_switch_chance` is `pbEnemyShouldWithdrawEx?`
(085:4116) with each `pbAIRandom` roll read as its probability — 30% / 20% after a
super-effective hit of base power > 70 / > 50, 80% on a Toxic about to kill, 80% on an
Encore into a move scoring ≤ 20, certain on Perish count 1 or on no usable move after turn
5, ×0.2 into a Hyper Beam or Truant turn; `stock_switch_slot` is the slot its list puts
first (party order, an immune body ahead, a resisting one when it is also super-effective
on us); `stock_move` is the top of `pbGetMoveScore`. Nothing registers, nothing draws, so
a run with the key on still reproduces its own dice; every foe is rescued on its own
because `pbGetMoveScore` is the scorer that divides by zero (085:3557). The intent grew
`switch_chance` / `switch_slot` (a model's) and `slot` (a declared switch's), and the
search reads them through `predicted_reply`. What the triggers say about the measured foe:
it switches after a super-effective hit, on Toxic, Encore or Perish, and otherwise never.

**Measured.** gen5ru_a, 60 paired, `search_planner=true`, depth 2; rules 48, stock 39,
0.7.4 search 40. Every arm's key-off control reproduces 0.7.4 on all 120 battles.

| weights | mix | both plies blended | root only |
|---|---|---|---|
| uniform (no producer) | 0.5 | 43 | 29 |
| uniform | 1.0 | **24** (−16 vs 0.7.4, p = 0.005) | 28 |
| stock model | 0.5 | 42 | **46** (+6, p = 0.24; vs rules −2, p = 0.82) |
| stock model | 1.0 | 30 | 44 |
| oracle (cheating) | 1.0 | 34 | **46** |

The both-ply arms were the first build (the mix reached `safest` with uniform weights below
the root); the root-only arms were a scratch patch of it, reinstalled over by the real
build and byte-checked. Root-only is the shipped semantics, and the shipped 0.7.5 search arm
is decision-identical to the root-only stock arm at 0.5 (`control_check`, 1024 decisions).

**What the table says.** Three things, each clean.

1. *The weights are the model, and a uniform prior is the wrong one.* Uniform says "it
   switches five turns in six"; at the root that loses 11 on its own (29 against 40) and
   at mix 1 it is the worst number this planner has produced since 0.7.0 (24, below stock).
   The stock model's weights, which say "it stays unless one of five things happened", win
   it back and six more.
2. *The stock model is as good as the oracle.* 46 and 46, root-only at mix 1 / 0.5. A
   one-turn read of stock's actual choice buys the search nothing a model of its triggers
   does not, which is the honest producer earning the cheating one's ceiling.
3. *The blend belongs at the root.* Below it there is no prediction, and blending the
   sub-grids with a uniform expectation is item 1 again one ply down: 42 against 46 for
   the stock model, 34 against 46 for the oracle.

Against 0.7.4 the shadow arm changes 78 of 933 decisions (38 move → move, 22 move →
switch, 12 the reverse) — the fewest of any version, because the model only moves a row
whose worst column was a switch the foe would not make. Sceptile's Earthquake into Magneton,
the 0.7.4 example: −63 and a pre-emptive switch then, −1 and the click now.

**Where this leaves the search, and the question it raises.** 46 against the rules' 48 is
inside the noise for the first time (p = 0.82), on a planner that was 31 at 0.7.0. But the
number is bought by a model of stock v16, and the AI's opponent in the game is the player,
who does switch to the wall. `foe_stock_model` is a benchmark instrument and ships off;
`search_foe_mix` at 0.5 without a producer is the uniform arm (43 both-ply, 29 root-only)
and should not be read as a default that helps — it is the default because the mix is
meaningless at 0 with a producer on. The honest next step against a human is the
opponent model the original built, MCTS, which mixes over the foe's replies by their
value to the foe instead of by a table; against stock it would be the predicted move's own
damage in the stay column, which this version does not read (the stay column is still the
foe's best hit). Neither is started. Ships **off**.

**Also fixed on the way.** `Search.plan` read the raw overrides, not the merged config,
so a search default that the harness did not spell out was never in play; the first shipped
0.7.5 arm reproduced 0.7.4 to the decision. It merges through `Model.config` now, as the
rule engine always did (`test_search_reads_its_defaults_under_the_overrides`). The
`depth` default was never affected (it has its own constant); `search_foe_mix` was.

**The two checks, 2026-09-08.** Does 46 hold off this roster, and does the fair model lift
the rule engine the way the oracle did? Seven runs, no code: the other two rosters' key-off
controls (each reproduces its 0.6.7 ship run battle-for-battle, so the rules are the same
rules), the search with the stock model on each, and the rules with the stock model on all
three.

| roster | rules | search + stock model | rules + stock model | 0.6.7 oracle |
|---|---|---|---|---|
| gen5ru_a | 48 | 46 (−2, p = 0.82) | 47 (−1, p = 1.0) | 50 |
| gen5uu_a | 47 | 47 (0, p = 0.77) | 51 (+4, p = 0.29) | 51 |
| gen6uu_a | 45 | 44 (−1, p = 1.0) | 50 (+5, p = 0.27) | 49 |
| pooled | **140/180** | **137/180** (gained 24, lost 27, p = 0.78) | **148/180** (gained 19, lost 11, p = 0.20) | 150/180 |

*Check one:* the search is level with the rules on every roster and better on none. 46 was
real but it was parity, not a lead, and parity is where it stays at three times the sample.
*Check two:* the stock model lifts the rules by eight pooled — not significant at 180, but
the same direction on all three rosters and within two of the cheating oracle's 150. A model
of the foe's triggers is worth what a perfect read of its choice was worth, on the planner
that ships as well as on the one that does not. It stays **off** for the reason the oracle
does: it is a model of stock v16, and against a human it reads switches that will not come
and misses the ones that will. If the AI's opponent were this engine, it would ship on.

**Artifacts** (`generated/`, all `realidea_tier_gen5ru_a_0_7_5_`): `control`, `search`,
`shadow_search`, `rules_stock`; `realidea_tier_{gen5uu_a,gen6uu_a}_0_7_5_{control,search,rules_stock}`; both-ply arms `search_u50`, `search_u100`, `search_s50`, `search_s100`,
`search_oracle100`; root-only arms `rootonly_u50`, `rootonly_u100`, `rootonly_s50`,
`rootonly_s100`, `rootonly_oracle100`. Backup: `backups/realidea_Scripts.rxdata.pre-0.7.5`.
Tests: 188 core (4 new), 118 Realidea (1 new), 53 Reborn, 28 tooling. The extra errors in
the mixed arms are the stock side's own `pbRoughDamage` division (`where` shows
`portable_ai_stock_pbChooseMoves`); they rise with game length.

### 0.7.6 — MCTS in Ruby, 2026-09-08

0.7.5 ended with the search at parity and a named suspect: 46/60 was bought by a *table*
— the foe's columns weighted by what stock v16's triggers say it does — and the AI's real
opponent is the player. The honest next step named there was the opponent model the
original built: MCTS, which mixes over the foe's replies by their value to the foe instead
of by a table. This version builds it, in Ruby, to find out whether it is worth building
in Rust.

**The bet.** Native speed is not needed to answer the question. The gauntlet is a study
harness, not a 100 ms move clock, so a Ruby tree can be given thousands of iterations per
decision and the sweep can simply take longer. If it cannot beat 46 with a generous
budget, a Rust DLL would not have saved it; if it holds or wins, `Win32API` to a 32-bit
cdylib is the way to ship it.

**What was built** (`portable_ai/search.rb`, section THE TREE). A third planner path on
the same board — `opening_board`, `own_options`, `foe_options`, `project`, `moves_first`,
`hit_chance`, `leaf` and `battle_over` are reused unchanged, and `plan` dispatches to it
after the guards it already ran. Four ideas from poke-engine's `src/mcts.rs` (GPL-3.0, the
path Foul Play runs today), no code:

* **Decoupled** simultaneous-move MCTS: one node, two independent option lists, each side
  selecting its own by UCB1 `avg + sqrt(2 ln N / n)` without seeing the other's pick
  (Tak, Lanctot & Winands 2014). A sequential tree here would let one side answer a move
  it cannot see.
* Chance outcomes **enumerated** into children with their probabilities — the speed order
  when nothing establishes it, times the accuracy branch, at most four summing to one —
  then one sampled by weight per iteration. The same branching `payoff` already does, kept
  as nodes instead of averaged away.
* **No playout**: the board is scored by the static leaf relative to the root,
  `sigmoid(eval − root_eval)` with `sigmoid(x) = 1/(1+exp(−0.0125x))`. A battle-over board
  is 1.0 / 0.0.
* The foe credited `1 − score`, and the pick being the **most-visited** root option.

Ours and not the original's: a **horizon** of 8 plies (`project` does not always change HP
— a Protect, a stage-only turn, two switches — so a tree without one can descend forever),
a per-cell tally so `search_row` can still print what a *row* scored (decoupled statistics
cannot reconstruct it), and a private LCG seeded per decision from the position itself
(turn, both slots, every body's HP) rather than from `pbAIRandom`, so a paired run and its
shadow twin agree and any decision replays from its snapshot alone. The budget is an
**iteration count**, not a time, for the same reason.

`foe_reply` / `column_weights` — 0.7.5's table — are deliberately **not** read on this
path. The whole point is what the foe's own payoff says when nothing tells it what to do.

**Measured.** gen5ru_a, 60 paired battles, `search_planner=true`. The key-off control
reproduces 0.7.5 on all 120 battles and all 915 traced decisions (`control_check`: 0
diverge), so the maximin and the rules are untouched.

| arm | wins | vs rules 48 | vs maximin 46 |
|---|---|---|---|
| rules 0.6.7 (control) | **48** | — | |
| maximin 0.7.5 (root mix + stock model) | **46** | −2, p = 0.82 | — |
| **MCTS, 5000 iterations** | **43** | −5, p = 0.302 | −3, p = 0.628 |
| **MCTS, 1000 iterations** | **41** | −7, p = 0.146 | −5, p = 0.383 |
| stock | 39 | | |
| 0.7.5 uniform prior at the root (the collapse reference) | 29 | | |

**It does not collapse, and it does not win.** 41 and 43 sit above stock and eleven clear
of the uniform prior that had no opponent model at all, and every gap to the rules and to
the maximin is inside the noise at this sample.

> **RETRACTED BY 0.7.7 — THE COMPARISON ABOVE IS NOT LIKE FOR LIKE.** The 46 in that table
> is `foe_stock_model=true`: a maximin holding a hand-built model of stock v16's withdraw
> triggers, which the tree **structurally cannot consume** (it reads no `column_weights` by
> design). The only maximin with the same information as the tree is the uniform arm, at
> **29**. Against that, MCTS at 1000 is **+12 (p = 0.025)** and at 5000 **+14**. The search
> was doing real work and this section called it a loss. See 0.7.7.

**The budget was never the bottleneck**, which is the finding the Rust question hangs on.
Five times the iterations buys +2 (p = 0.814) — and not because the extra work is wasted:
the tree measurably converges harder with it.

| | 1000 | 5000 |
|---|---|---|
| top option's share of the budget (median) | 27.1% | 38.1% |
| top-vs-second visit margin (median, % of budget) | 6.2% | 15.4% |
| decisions where that margin is under 2% | 26% | 19% |
| cost per decision, RGSS Ruby 1.8 | ~195 ms | ~894 ms |
| the whole 120-battle arm | ~4 min | ~15 min |

The search converges more, is more decisive, and wins two more games out of sixty. A
native port makes iterations cheap; iterations are not what is missing.

> **ALSO RETRACTED BY 0.7.7.** This was measured on a tree with nothing to search: the foe
> had ONE column ("it attacks, at worst"), so extra iterations had no opponent to resolve.
> Give the foe a real move axis and the same budget step is worth **+9** rather than +2
> (39 → 48). The claim that survives is narrower and was re-measured three times: strength
> rises to about 5000 iterations and then **flattens** — 15000 scores 44, and a seed
> replicate at 5000 scores 46 against 48, so 44/46/48 is one number. Iterations buy
> something, then stop buying. What that leaves for Rust is a SHIPPING argument (5000
> iterations is ~1 s a decision in Ruby and would be ~10 ms native, which is the difference
> between a study harness and a real move clock), not a STRENGTH argument.

**Nor is the evaluation flat.** The obvious suspect for a tree that will not separate is
the sigmoid squashing the leaf, and it is not that: across 964 decisions the spread between
the best and worst option's average is a median of 0.22, the full 0..1 range is used, and
the most-visited option is also the best-average one on 99% of decisions. The tree finds
what it should — on the kill snapshot it clicks the kill, and on turn 1 of
`team1_vs_team2` 104729 it clicks Earthquake where the maximin, holding a three-way −88
tie, clicked Rock Polish.

**What the readouts show.** Against the 0.7.5 shadow twin, 256 of 933 turns differ (27.4%)
— 150 move → move, 77 switch → move, 23 move → switch, 6 switch → switch. So the tree
attacks where the maximin left. Of those 256, the maximin matched the stock host's own
click on 24 and the tree on 19.

The failure is visible on the turn that opens `team2_vs_team1` 130363, one of the four
games the rules win and both MCTS budgets lose. Galvantula faces Golurk, which is immune
to Electric. Nine options; the tree ranks them:

```
     0.459  GIGADRAIN (bp 75, 89% dmg, x2)             search_visits +229
     0.396  BUGBUZZ (bp 90, 40% dmg, x0.5)             search_visits +146
     0.373  THUNDER (bp 120, 0% dmg, x0, IMMUNE)       search_visits +127
     0.346  switch -> Druddigon (hits 135%, takes 94%) search_visits +107
     0.308  VOLTSWITCH (bp 70, 0% dmg, x0, IMMUNE)     search_visits +88
```

The order is right — the move that does 89% is first — but two moves that *cannot do
anything* sit third and fifth, one of them above the switch to the body that beats Golurk
135%/94%. Galvantula takes 144% either way, so every line loses it, and once both branches
end with the same body dead the only remaining difference is Golurk's HP.

**The sigmoid is not what flattens that**, and the first draft of this section said it was.
Checked against the source (2026-09-08): poke-engine's scale is `0.0125` over an evaluate
whose constants this leaf already matches exactly — `POKEMON_ALIVE 30`, `POKEMON_HP 100 ×
hp/maxhp`, boosts 30/15, multipliers 1.0/2.0/2.5/3.0/3.15/3.3, Substitute 75, hazards
10/7/7/25, status 40/25/25/30/10/25. At a *single leaf* an 89-point difference is
`sigmoid(89) − sigmoid(0)` = 0.753 − 0.500 = **0.253**, which is not compression at all.
The 0.086 above is a gap between *root averages*, thinned by averaging over the many
sampled lines in which the difference does not survive. The squash is real but it lives at
the top of the range — 200 points reads 0.924 and a full party 0.9999, so past about a body
and a half of advantage every board does look alike — and that is the original's deliberate
tuning ("~200 points is very close to 1.0"), which Foul Play wins with.

So the lever is **not** `SIGMOID_SCALE`, and it is not iterations either.

**What Foul Play has that this does not is a foe with moves** (source read 2026-09-08).
Its Smogon usage data does *not* enter the tree as a prior — the MCTS is uniform-prior UCB1
over a fully specified state. The data enters one step earlier, at *state sampling*
(`fp/search/standard_battles.py`): for each opponent body it draws a concrete set — moves,
item, ability, spread — from the usage corpus filtered by what has been revealed, and where
there is no team preview it invents the unrevealed slots from teammate co-occurrence counts
(`predict_team_likelihood`). It then runs N independent searches, one per sampled state, and
aggregates the root policies, `final_policy[move] += (1/N) × (visits / total_visits)` — the
likelihood shapes *which* teams get drawn, not the weights — keeps every choice within 75%
of the best, and picks among those at random rather than taking the argmax.

Half of that machinery answers a problem this study does not have: the party matrix already
exports every foe body and real damage rolls both ways, off their real movesets, so there is
nothing to guess about *which* Pokémon are there. **The other half is exactly what is
missing.** A sampled state hands poke-engine the opponent's actual four moves, so the tree's
foe side chooses among ~9 concrete options — Earthquake, Toxic, a setup move, five switches —
each with its own damage, status and priority. Ours is `stay` plus one column per bench body
(`foe_options`), and `stay` collapses every move the foe owns into a single worst-case damage
number. **A tree whose entire thesis is "let the foe's line be shaped by its own payoff" was
given a foe with one way to act.** That is the likeliest reason the tree buys nothing the
maximin did not already have: against a one-option foe, per-side UCB has almost nothing to
discover, and the decoupled selection that is the whole point of the design degenerates.

The concrete arm is the mirror of 0.7.4's `out_moves`: an `in_moves` breakdown on the cell
(the foe's per-move rolls, which the adapter already computes to find `in`), and a real foe
move axis built from it.

> **0.7.7 BUILT THIS AND THE PREDICTION WAS HALF RIGHT.** The axis alone, at this budget,
> moves the tree by −2 (41 → 39): a wider foe spreads the same 1000 iterations thinner. It
> only pays WITH the budget to resolve it (39 → 48 at 5000). And on the maximin it is worth
> +6 against a uniform prior but −1 against a real one, which says the axis is a partial
> substitute for an opponent model and no substitute at all for a good one.

**Where this leaves the search line.** Two versions have now put the search level with the
rules and neither has put it ahead. The budget lever is spent and the leaf's scale is not a
lever at all; what remains is the foe's option axis — the tree cannot model an opponent the
snapshot only lets it model as "attacks, at worst". Both new keys ship
**off**; `search_mcts=false` is 0.7.5 decision for decision.

**One divergence from the original worth recording.** Foul Play does not set an iteration
count: its budget is `--search-time-ms`, default **100 ms** per state, and it logs
`total_visits` afterwards as "Iterations". What it configures is breadth — `--search-parallelism`
(default 1) sampled opponent teams, doubled at team preview or when the opponent has shown
fewer than three moves. The count here is deliberate instead, because a paired run and its
shadow twin have to decide identically whatever the machine — so 1000 and 5000 have no
counterpart in the original to be measured against. Its root pick is
`max(side_one, key=visits)`, which is the convention ported.

**Also fixed on the way**, both in the readout tools, both found by reading 0.7.6 output.
`shadow_pair_diff.py` compared a move's target raw, and the engine writes the sole foe of a
single battle as `-1` where the portable planner writes `None` — so 441 of 933 turns on
which both sides clicked the *identical move* were scored as a disagreement, and the "which
side matched the host" table could only ever credit a switch (it read `neither 254,
maximin 2`; it reads `neither 213, maximin 24, mcts 19` now). And both that tool and
`render_realidea_battle.py` printed the score column at `%.0f` / `%8.1f`, which is right
for the rule engine's HP points and renders every MCTS row as `1`, `0` or `0.5`; they pick
the precision from the magnitude now. The `search_visits` field also reaches the trace
(`candidate_trace`), without which no readout can explain a pick the tree ranks by visits.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_7_6_{control,mcts_1000,mcts_5000,shadow_mcts_1000}.ndjson`;
readouts `readouts/portable_ai_0_7_6_{pairdiff_maximin_vs_mcts,gen5ru_a_mcts1000_team2_vs_team1_130363,gen5ru_a_rules_team2_vs_team1_130363}.txt`.
Backup: `backups/realidea_Scripts.rxdata.pre-0.7.6`. Tests: 195 core (7 new), 119 Realidea
(1 new), 53 Reborn, 28 tooling. No errors in either MCTS arm (the control's 2 are stock's
own `pbRoughDamage` division, as always).

### 0.7.7 — the foe gets moves, 2026-09-08

0.7.6 concluded that MCTS did not pay and that iterations were not the bottleneck. Both
conclusions were wrong, and this version is what found that out. The cause was one line the
adapter never wrote.

**The hole.** `matrix_cell` is called twice per pair — once for our damage into them, once
for theirs into us — and each call returns every move it rolled. 0.7.4 kept ours
(`out_moves`) and it was worth real points. **Nobody ever kept theirs.** The cell carried
`in`, one number: the biggest hit the foe owns. So `foe_options` was one `stay` column plus
one per bench body, and every planner here modelled the opponent as *"it attacks, at worst"*.
For the maximin that is nearly harmless — the worst case IS the biggest hit. For a tree
whose entire thesis is that the foe's line should be shaped by the foe's own payoff, it is
fatal: 0.7.6 ran a simultaneous-move search against an opponent with one way to act, so the
decoupled selection that is the whole point of the design had nothing to discover.

**What was built.** `in_moves` on the cell (matrix version 3, no new engine calls — the
rolls were already being made and discarded), and a real foe move axis on top of it:
`foe_moves` emits one column per move sorted by id (a Ruby 1.8 Hash has no order, and a
column list that moved between two runs of one position would make every paired arm
unrepeatable); `foe_damage` reads the named move's number **against whatever body is
standing after our switch resolves**, mirroring how `own_damage` prices our move against
their switch-in; `defence_divisor` takes the category of the move actually being taken;
`column_weights` shares the non-switch mass over every move column. A cell without the list
— an older adapter, a pair the matrix never rolled, and every Reborn run — is one `stay`
column at the best hit, which is 0.7.6 exactly.

`in_moves` **follows its reader**, as `matrix_wanted?` does one level up: it is built only
when `search_planner` is on, because `foe_moves` is the only thing that opens it and the
search ships off. Unconditionally it cost every shipped decision the allocation and every
traced run 28% of its size (9.7 → 12.4 MB on a 60-battle control; 9.9 gated).

**Measured.** gen5ru_a, 60 paired battles. Controls reproduce 0.7.6 on all 120 battles and
915 decisions, twice — before and after the gate.

| planner | foe axis | budget | opponent model | wins |
|---|---|---|---|---|
| rules 0.6.7 | — | — | — | **48** |
| maximin | one column | depth 2 | uniform | 29 |
| maximin | move axis | depth 2 | uniform | **35** |
| maximin | one column | depth 2 | stock model | **46** |
| maximin | move axis | depth 2 | stock model | 45 |
| MCTS | one column | 1000 | none (the tree itself) | 41 |
| MCTS | one column | 5000 | none | 43 |
| MCTS | move axis | 1000 | none | 39 |
| MCTS | move axis | 5000 | none | **48** |
| MCTS | move axis | 5000, seed 1 | none | **46** |
| MCTS | move axis | 15000 | none | 44 |
| stock v16 | | | | 39 |

**Read it as three findings, in order of how much they cost to learn.**

1. *0.7.6's headline was a mis-baselined comparison, and the error was mine.* The 46 that
   MCTS "lost" to is a maximin carrying `foe_stock_model` — a hand-built table of stock's
   withdraw triggers that the tree cannot consume by construction. Against the only maximin
   holding the same information, the uniform arm at 29, MCTS is **+12 (p = 0.025)**. The
   like-for-like ladder is 29 → 35 (axis) → 41 (tree) → 46-48 (tree + axis + budget).
2. *The axis and the budget only pay together.* Axis alone at 1000: 41 → 39. Budget alone
   on one column: 41 → 43. Both: **48**. Widening the foe's options makes each iteration
   worth less until there are enough of them to resolve the wider tree — which is exactly
   why 0.7.6 measured "iterations don't matter" and why that measurement did not generalise
   one line of code later.
3. *And then it flattens, which the seed replicate is what proves.* 15000 scores 44, below
   5000's 48. Re-running 5000 with `search_seed=1` — identical battles, identical budget,
   a different sampling of the tree's own chance branches — scores **46**, changing 6
   outcomes of 60. So the tree's own randomness is worth about ±2 wins here, and 44 / 46 /
   48 is one number. **MCTS on the move axis is ~46 at any budget from 5000 up.**

**What that number means.** 46 is the score the maximin needs `foe_stock_model` to reach —
a model of stock v16's own code, which is a benchmark instrument and ships off because a
human does not switch on stock's triggers. **The tree gets there with no opponent model at
all**, deriving one per position from the foe's own payoff. That is the first result in this
line that is worth something against a player rather than against this engine. It is still
about two behind the rule engine (48), and at n = 60 that gap is not significant either.

**The Rust question, answered narrowly.** Strength plateaus by 5000 iterations, so a native
port finds no more wins — 0.7.6's conclusion survives for the reason it gave, on numbers it
did not have. What a port would buy is the plateau at a real move clock: 5000 iterations is
~1 s a decision in Ruby (15000 is ~3 s, and a 120-battle arm takes 40 minutes) against an
estimated ~10 ms native. That is the difference between a study harness and something that
could ship in a game. It is a shipping argument and should never again be written up as a
strength one.

**Everything ships off.** `search_mcts=false` is 0.7.5 decision for decision; `in_moves` is
not even built without `search_planner`.

**Where the line goes next.** The remaining lever is the one that has paid every time it has
been pulled: the opponent model. Two arms, both cheap, neither needing Rust — concentrate
`column_weights`' stay mass on the predicted move rather than sharing it (`stock_move` is
already exported and unused), and seed the tree's foe root statistics with those same
weights, which is the one way the stock model's +17 can reach a planner that currently
refuses to look at it.

**Artifacts** (`generated/`, all `realidea_tier_gen5ru_a_0_7_7_`): `control`,
`control_gated`, `maximin`, `maximin_stock`, `mcts_1000`, `mcts_5000`, `mcts_5000_seed1`,
`mcts_15000`. Readouts `readouts/portable_ai_0_7_7_{mcts5000,mcts1000,rules}_*` over eight
battles on all five seeds. Backup `backups/realidea_Scripts.rxdata.pre-0.7.7`. Tests: 200
core (5 new), 119 Realidea, 53 Reborn, 28 tooling.

**A process note worth keeping.** One arm in this batch silently did not run: Game.exe
exited without starting the gauntlet and the script copied the PREVIOUS arm's results, which
produced a "15000" artifact byte-identical to the 5000 one and reporting the same 48. It was
caught only because the record's own `config_overrides` said `search_iterations: 5000.0`.
Every run script now records the results file's mtime before launching and refuses to copy
anything if the file was not touched. **Read the config off the artifact, not off the
harness file you think you wrote.**

### 0.7.8 — the opponent model that was already in the box, 2026-09-08

0.7.7 left one lever: the opponent model, and two arms to pull it with — concentrate
`column_weights`' stay mass on a predicted move, and seed the tree's foe root statistics with
the same weights. Both arms name a *producer* for that prediction, and the only one on hand
was `stock_move`, a model of this engine's own AI. Before building either, one diagnostic:
**is the tree's foe budget already landing on the moves the foe really plays?** If it were,
seeding buys nothing and the idea would have been wrong a third time.

**The diagnostic.** `foe_visits` was already in the MCTS diagnostics and the trace already
records what the foe then did; the only new code was one adapter helper (`search_trace`)
writing the first next to the second. Run on the 5000-iteration arm — 925 decisions, and all
120 battles identical to the un-instrumented arm, so the hook is inert.

| measure | value |
|---|---|
| tree's budget spent on the move the foe actually played | 32.3% |
| the same budget spread evenly (uniform baseline) | 22.9% |
| tree's most-visited foe option, as a share of budget | 47.0% |
| that option **was** the foe's actual choice | 399/925 = **43.1%** |
| foe played a move not on the tree's option list | 107/925 = 11.6% |
| foe switched | 17/925 |

So the tree does beat uniform, and the answer to the diagnostic's question was "partly". But
the comparison that mattered was the one it made possible. The cell's max-damage `in_move` —
**already computed, already handed to the tree as its input, costing nothing** — predicts the
foe's actual move **478/925 = 51.7%**, against the tree's own 43.1%. Both right 339 (36.6%),
both wrong 387 (41.8%). *The tree's opponent model is worse than the one sitting in its
input.* That killed the `stock_move` arms before they were written: the prior to seed with is
free, and a model of stock's code — a benchmark instrument that cannot ship — was never
needed for this.

**It is not a sharper prior, it is a differently-aimed one.** Off the control's own traces,
840 decisions with two or more foe stay columns, cell resolved in all 840:

| | mean share on its own top foe column |
|---|---|
| the free damage prior | 56.2% |
| the tree's budget | 55.5% |
| uniform at the same widths | 35.5% |

Same concentration, different column. So this was never "spread the budget less evenly" — it
is "spend the same concentration somewhere better", which also means a null result here would
be real evidence against the prediction-to-play link rather than an effect too small to see.

**What was built.** `foe_prior` normalises the stay columns by their `pct` and returns nil
when there is no usable mass; `spread_stays` splits the stay group's share by that prior
instead of evenly. **The prior only ever moves mass BETWEEN stay columns** — it says which
move the foe picks, never whether it stays — so the switch/stay split its caller already
computed survives untouched. On the tree the same vector enters `ucb_pick` as AlphaZero's
PUCT term `MCTS_PRIOR_C · P(j) · sqrt(N) / (1 + n)` **added to UCB1 rather than replacing
it**, on the foe axis only. Three alternatives were rejected: bare PUCT starves any column
priced at zero (a Volt Switch off a Choice Specs set, a status move), progressive bias
`P/(1+n)` has decayed to nothing by N = 5000, and virtual visits run backwards — more visits
would *lower* the bonus.

**Measured.** gen5ru_a, 60 paired battles, everything against 0.7.7's own arms. The key-off
control reproduces 0.7.7 on **all 120 rows byte-identically**, so the 0.7.8 install with the
key off is the 0.7.7 build exactly.

| planner | budget | opponent model | wins | vs. |
|---|---|---|---|---|
| rules 0.6.7 | — | — | **48** | |
| maximin | depth 2 | uniform | 35 | |
| maximin | depth 2 | **free damage prior** | **41** | vs uniform: 0 / 6, **p = 0.031** |
| maximin | depth 2 | `foe_stock_model` | 45 | vs prior: 12 / 8, p = 0.50 |
| MCTS | 5000 | none (control) | **48** | row-identical to 0.7.7 |
| MCTS | 5000 | **free damage prior** (PUCT) | 46 (+1 error) | vs control: 5 / 3, p = 0.73 |
| stock v16 | | | 39 | |

**Two findings.**

1. *On the maximin the free prior pays — on this roster.* 35 → 41
   with **zero regressions**: every battle the uniform maximin won, the priored one also won,
   plus six more (p = 0.031). It closes six of the ten points that `foe_stock_model` bought
   and is not distinguishable from that hand-built stock-trigger table (p = 0.50) — at no
   cost, from numbers the planner was already being handed. An opponent model does not have
   to model the opponent; here, pricing its moves by damage is most of the value.
2. *On the tree it buys nothing.* 48 → 46, p = 0.73, inside the ±2 the seed replicate already
   established as one number. Consistent with 0.7.7's plateau: the tree at 5000 is not
   budget-starved on the foe axis, so aiming that budget better changes nothing it could not
   already find. **The prior helps the planner that needs a distribution to take an
   expectation over, and not the one that derives its own.**

The prior maximin at 41 is still behind the rule engine's 48 (p = 0.19), which remains true
of every search arm in this study.

**One error, and it is not ours.** The priored tree arm lost a battle to
`ZeroDivisionError` in **Realidea's own** `PokeBattle_AI:3557:in 'pbRoughDamage'`, reached
through the stock chooser. The control ran the same seed to turn 20; the priored arm diverged
and reached turn 13 in a state that trips a pre-existing divide-by-zero in the engine's
scoring routine. No portable code is on that backtrace. It is counted as a non-win above.

**Everything ships off.** `search_foe_prior=false` is the default and reproduces 0.7.7 row for
row on both planners.

**Replication on the other two rosters, 2026-09-08 — and it changes two of the claims above.**
Everything up to this point was measured on gen5ru_a alone, which the rules-vs-stock table
shows is the *weakest* of the three rosters for this engine (48 vs 39, p = 0.078 on its own;
the other two are p = 0.0002 and p = 0.0025). Four arms were re-run on gen5uu_a and gen6uu_a.
Both new controls reproduce their 0.7.5 counterparts **row for row**, so the 0.7.8 install is
sound on rosters it had never touched.

| arm | gen5ru_a | gen5uu_a | gen6uu_a | pooled | draws | errors |
|---|---|---|---|---|---|---|
| rules 0.6.7 | 48 | 47 | 45 | **140/180 (77.8%)** | 3 | 5 |
| maximin, uniform | 35 | 40 | 44 | 119/180 (66.1%) | 3 | 6 |
| maximin + prior | 41 | 43 | 43 | 127/180 (70.6%) | 6 | 6 |
| MCTS 5000 | 48 | 44 | 43 | **135/180 (75.0%)** | 2 | 6 |
| stock v16 | 39 | 26 | 29 | 94/180 (52.2%) | | |

| pooled | rules-only | arm-only | p |
|---|---|---|---|
| rules vs uniform maximin | 43 | 22 | **0.013** |
| rules vs priored maximin | 37 | 24 | 0.12 |
| rules vs MCTS 5000 | 30 | 25 | **0.59** |
| uniform maximin vs MCTS | 22 | 38 | 0.052 |

1. *The prior's effect is real but far smaller than one roster suggested, and I over-read it.*
   Pooled 119 → 127 (5 / 13, p = 0.096) — same direction on two of three rosters, not
   significant, and **the zero-regression property does not survive**: gen5uu_a gives back 2
   battles and gen6uu_a 3, ending level there. "35 → 41 with zero regressions, p = 0.031" was
   true and is now plainly the favourable tail of an effect nearer +4 points than +10. The
   prior's value tracks *how much headroom the uniform model was leaving*, and that varies
   more between rosters than the prior does: on gen6uu_a the uniform maximin is already 44
   against the rules' 45, so there is nothing left for an opponent model to recover.
2. *The tree's tie with the rules survives widening, but the 48/48 headline does not.* MCTS is
   135 vs 140 pooled, 30 / 25 discordant, **p = 0.59** — a genuine statistical tie on 180
   battles. But gen5ru_a was its best roster; it scores 44 and 43 on the others. The claim
   this line can defend is *"level with the rules within the noise"*, never *"matches the
   rules"*. It does beat the maximin it was meant to (38 / 22 over uniform, p = 0.052), so
   0.7.7's ladder survives.

**Two accounting caveats, both running against the search.** (a) The `error` bucket is
Realidea's own `pbRoughDamage` divide-by-zero reached through the stock chooser, and the
errored battles are **not the same battles in each arm** — on gen5uu_a, 12 distinct battles
errored somewhere and none errored in all four arms, so it is not an offset that cancels.
Search arms steer into states that trip it more often (6 pooled vs the rules' 5; 5 vs 2 on
gen5uu_a alone), and each one costs a battle the rules got scored on. Counting every error as
a win instead moves rules 140 → 145, uniform 119 → 125, prior 127 → 133 — the ordering
survives either way, but a 3-win gap with a 2-error difference inside it should never be
quoted as though it were clean. (b) gen6uu_a is the only roster that produces **draws**, and
the priored maximin produces 6 of them against the control's 2 — it is not losing those
battles, it is failing to close them, which is the shape you would expect from weighting the
foe's columns by damage (an AI more inclined to avoid the big hit than to end the game).
**The engine bug is a known one-line fault left in place since 0.7.4; fixing it would remove
this bias rather than bound it, and that is now the cheapest measurement improvement
available.**

**Where the line goes next.** The lever that has paid twice is now spent on the cheap side:
the maximin has an opponent model that costs nothing, and the tree has been shown not to want
one. What is left is the gap to the rule engine, which no search arm has closed at any budget,
model, axis or depth — and that gap, not the search's internals, is the thing worth explaining
next.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_7_8_{mcts_5000_control,mcts_5000_prior,maximin_prior}`; the replication as `realidea_tier_{gen5uu_a,gen6uu_a}_0_7_8_{control,maximin,maximin_prior,mcts_5000}`; the diagnostic ran on `0_7_7_mcts_5000_foevisits`.
Backups `backups/realidea_Scripts.rxdata.pre-0.7.7-foevisits` and `pre-0.7.8`. Tests: 204
core (4 new), 120 Realidea (1 new), 53 Reborn, 28 tooling.

### The gauntlet hang, and what it actually was

**Fixed 2026-09-06.** It was a crash, not a deadlock, and every symptom that made it
look like one was the engine hiding it.

Realidea runs `pbCommandPhase` and `pbAttackPhase` inside `PBDebug.logonerr`, and the
`$INTERNAL` guard around that method's `pbPrintException` call **is commented out**
(`PBDebug.rb:11-13`). `pbPrintException` ends in RGSS's `print`, which is a modal box. So
an exception in either phase was caught by `logonerr`'s rescue, turned into a dialog with
nobody there to dismiss it, and **never reached `run_one`'s own rescue** — which is why no
error record was ever written. The process then sat in the window message pump at the
0.015 CPU-seconds per 5 wall seconds that reads exactly like a deadlock.

The engine did log it, to an `errorlog.txt` that `RTP.getSaveFileName` redirects into
`C:\Users\<user>\Saved Games\Realidea System\` — which is why it was not where anyone
looked.

The exception: **`$ItemData` was `nil`**, so `pbIsBerry?` raised on `$ItemData[item]`
(`PItem_Items.rb:63`) the moment `pbGetMoveScore` scored Bug Bite or Pluck at high skill,
and the gauntlet trainer's skill is 100. Item data is read by the load and save screens,
which a save-less harness never opens; `bootstrap` asked for `pbLoadItems`, a **later
Essentials' name that does not exist in v16**, and its `rescue` swallowed the `NameError`
and kept the `nil`. It had been `nil` since the harness was written and cost nothing for
as long as no fixture Pokémon held an item. The tier rosters are the first that do.

Three changes, because fixing only the first would leave the next such crash just as
invisible:

| change | where | why |
|---|---|---|
| load `$ItemData` with `readItemList` | `AI_Probe.bootstrap` | the way this engine does it |
| replace `pbPrintException` so it re-raises | `AIProbe.install_exception_capture` | `run_one` records the error and the run continues to the next battle |
| write a per-battle progress file | `PortableAIGauntlet.note` | the results file only gains a record when a battle *finishes*, so a run that stopped mid-battle looked identical to one that never started. This file is how the above was found. |

**A caution for anyone extending this harness.** Silence from this engine is not evidence
of success. Before the exception capture, three separate pre-existing engine bugs
(*Tier suite*, below) were running invisibly.

### Archetype gauntlet — 0.6.2, 2026-09-06

The frozen benchmark: eight matchups, the three-mon fixture, `teams=archetype`. First
completion since the port — the 0.6.2 attempt earlier today stopped at 36 of 80 records.
**Zero errors in both arms**, which is itself the result: the `$ItemData` crash is gone.

| | stock | portable | gap |
|---|---:|---:|---:|
| frozen 5 seeds (80 battles) | 20/40 (50.0%) | 26/40 (**65.0%**) | +15.0pt |
| extended 20 seeds (320 battles) | 82/160 (51.2%) | 103/160 (**64.4%**) | +13.1pt |

Singles/doubles at 20 seeds: stock 56/120 and 26/40, Portable 73/120 and 30/40 — the gain
is in singles (+14.1pt) and doubles (+10.0pt) alike.

**The extended seeds are an addition, not a replacement.** The five frozen seeds are the
comparable number; the other fifteen are there because 40 battles per arm cannot separate
a five-point difference from noise. The frozen-seed subset of the 320-battle run is
**outcome-identical** to the standalone 80-battle run, so the seeds do not interact and
both tables describe the same build.

#### Against the 0.1.0 baseline

> The 0.1.0 install was measured on 2026-09-04 against the old 126-scenario corpus. Kept
> as the baseline, not as a description of what is installed now.

| | 0.1.0 | 0.6.2 (same 5 seeds) |
|---|---:|---:|
| Stock | 20/40 (50.0%), singles 14/30, doubles 6/10, mean 7.1 turns | **identical on every figure** |
| Portable | 28/40 (70.0%), singles 20/30, doubles 8/10 | 26/40 (65.0%), singles 18/30, doubles 8/10 |

**Stock reproducing 0.1.0 exactly — win/loss, both format splits, and mean turn count to
one decimal — is the control.** The fixture, the seeds and the stock path are unchanged,
so the Portable column is the only thing being compared. It also shows the `$ItemData`
fix did not perturb this fixture, which is expected: none of its Pokémon hold an item.

**Portable is two battles below 0.1.0, both in singles.** That is 5 points on n=40, where
the standard error is about 7.2 — it is not a result in either direction. The 20-seed run
puts 0.6.2's rate at 64.4% ± 3.8, and 0.1.0's 70.0% ± 7.2 overlaps it; 0.1.0 was never run
at 20 seeds, so the two cannot be separated.

**The gate's actual regression check could not be run.** It asks for *"losses that the
previous version won on the same seed — list them by seed and read the traces"*, and that
needs 0.1.0's per-battle records. Only their SHA-256 was kept
(`b91feba3…` in `portable_ai_results.json`); the ndjson lived at
`Realidea V4.1/Data/ai_gauntlet_results.ndjson` and has been overwritten. **Every gauntlet
artifact is now copied into `generated/` so this cannot recur.** Re-running the check
means rebuilding 0.1.0 from git and re-measuring it, which is cheap now that a set takes
under a minute — it is on the outstanding list.

The corpus at 0.1.0 was 126 scenarios / 169 assertions, five Reborn-field scenarios
skipped, leaving 163 applicable:

| AI | Tier-1 | Spearman vs Reborn | Action-type agreement |
|---|---:|---:|---:|
| Stock v16 + Clara | 143/163 | baseline | baseline |
| Portable AI 0.1.0 | **163/163** | **0.913** | **117/121 (96.7%)** |

That 163/163 is not comparable to 0.6.2's 240/256: the corpus roughly doubled, and the
cards added since are the ones that discriminate. Hashes and machine-readable totals for
both are in `generated/portable_ai_results.json`; the pre-expansion stock baseline is
preserved in `generated/portable_ai_baseline.json`.

None of this replaces a manual campaign playthrough of scripted bosses and unusual custom
mechanics; the fail-safe stock fallback remains enabled for that reason.

### 0.7.9 — the search's board audited against the original's, and it loses more, 2026-09-08

**Why.** Eight versions of search had bought parity with the rule engine and never a
lead, and the 0.7.8 write-up left one idea untried. Before spending it, the tree was
cross-checked line by line against the original it claims as provenance
(`pmariglia/poke-engine` `src/mcts.rs`, `genx/evaluate.rs`, the damage-branching part of
`genx/generate_instructions.rs`; `pmariglia/foul-play` `fp/search/main.py`; all cloned
fresh at their 2026-09 heads). The MCTS mechanics matched: decoupled UCB1 at the same
constant, unvisited-first, `sigmoid(eval − root_eval)` at 0.0125, terminal 1/0, the foe
credited `1 − score`, chance children re-sampled by weight on every descent, the
most-visited root pick (Foul Play's 75%-band randomisation and its multi-set averaging are
deliberately absent). **The board the tree plays on did not match, and every gap erred the
same way — toward damage being bigger and more certain than it is:**

1. **Every damage number is the MAX roll.** `pbRoughDamage` (`085:3147`, "Critical hits
   - n/a", "Random variance - n/a") applies no random factor; the engine then rolls
   85..100% (`082:1140`). core.rb has always known this (`MIN_DAMAGE_ROLL` on every kill
   test). search.rb's header said "we carry one expected roll per cell" and took the
   number as it came, so with a step leaf at 0 HP a kill that lands one roll in sixteen
   read as certain, on both axes, at every ply. The original's `should_branch_on_damage`
   is exactly the answer, and it was the one thing the header listed as "deliberately not
   borrowed".
2. **The foe could only attack or switch.** `matrix_cell` listed `pbIsDamaging?` moves
   only, so the tree's foe never set up, healed, laid a hazard, Protected or landed a
   status, while our root row was priced for all of those (0.7.2). Our own switch-in below
   the root had one attack. The original enumerates every move for both sides.
3. **The foe never missed**, and neither did our below-root attack. "The foe's hit stays
   certain" was a maximin choice that carried into a tree where it no longer meant worst
   case.
4. **No end of turn.** The original applies `add_end_of_turn_instructions` every ply;
   `project` applied none, so a Toxic was thirty points forever and never HP.
5. Smaller: no paralysis/sleep/freeze act chance; below-root switch-ins paid no hazards;
   a foe's priority move was invisible (the cell carried no bracket).

**What was built (all of it, unconditional under `search_planner`; the rule engine reads
none of it).** `roll_outcomes`: the original's arithmetic — kill branch at the fraction
of the sixteen rolls that reach HP plus the crit rate (1/16, x1.5, v16), the rest at the
mean surviving roll; a crit branch when every roll falls short; the average roll (0.925)
below the root's children. `outcomes`: one enumeration of a joint pair's chances — speed
order, each side's accuracy times its status act chance (a miss and a full paralysis are
the same board), the roll — shared by `payoff` (the maximin averages it) and the tree
(`branches` keeps it as children, projected lazily on first descent, `child_node`).
`foe_hit_chance`, `act_chance`. `act_foe` rebuilt as the mirror of `act_own`: setup,
self-drop, heal, Protect (the bracket now read on both sides in `moves_first`), Substitute,
hazards on our side, a status or drop on us, through our Protect and Substitute; and
`act_own` through theirs. `foe_stages` on the board, read by `foe_damage`, `own_damage`
(their defence), `boosted_cell` (their speed) and the leaf. `residual`: Leftovers, Black
Sludge, burn, poison, the Toxic ladder, sand and hail with their type and ability
immunities, Leech Seed both ways, Magic Guard, Poison Heal. `resolve_switches` split out of
`project`; both sides' switch-ins pay `entry_damage_pct` from the side table below the
root. `cell_actions`: our below-root options from `out_moves`. Matrix version 4 (adapter):
every move in both lists with `acc`, `priority`, `damaging`, `effect`; the side table with
`status`, `item`, `ability`, `entry_damage_pct`. Tests: 209 core (six new, five re-pinned
against the roll model with the arithmetic spelled out), 120 adapter.

**Measured.** gen5ru_a, 60 paired, `search_planner=true search_mcts=true
search_iterations=5000`, on the engine build with the fainted-target floors (`_aifix`
arms are the comparators). Stock arm byte-identical 60/60 to `0_7_8_control_aifix`.

| arm | wins | vs 0.7.9 tree |
|---|---|---|
| rules (0.7.8 control_aifix) | 50/60 | gained 7, lost 16, **−9**, p = 0.095 |
| MCTS 5000, 0.7.8 board | 48/60 | gained 3, lost 10, **−7**, p = 0.096 |
| **MCTS 5000, 0.7.9 board** | **41/60** | |
| stock | 39/60 | |

Down on all four teams against both comparators. Not significant at n = 60, but the
direction is the opposite of the one the audit predicted, and it is the same on every
team.

**What the trace says.** 988 tree decisions (0.7.8: 931). The tree's own picks moved
where the board moved: **status-move clicks doubled, 55 → 122 of ~800 moves** —
Substitute 6 → 32, Swords Dance 4 → 19, Calm Mind 13 → 23, Spikes 2 → 10, Toxic 4 → 8.
Losses carry 2.9 such clicks a battle against 1.6 in wins; the ten battles the 0.7.8 tree
won and this one lost hold 7, 9 and 3 of them. Battles run a turn longer (15.6 vs 14.7).
The budget is thinner but not starved: 7.0 foe columns a decision (5.6), the top own
option holds 42% of the root's visits (47%). Cost unchanged (~22 min for the 120-battle
set, the same as 0.7.8).

**The reading.** The roll model made attacking *worth less and less certain* — an attack
that killed for sure now kills at a probability, lands at 0.925 on average, and can miss
on both sides — while the leaf's terms for a setup stage (30, undiminished for the second)
and a standing Substitute (75, for 25 HP) stayed at the original's numbers. Those terms
are banked for certain at every leaf the tree reaches, and an eight-ply tree reaches many
leaves with the Substitute still up. The 0.7.8 tree over-attacked on a board where attacks
were over-valued and won 48; the 0.7.9 tree over-sets-up on a board where attacks are
priced right and the alternatives are not, and wins 41. The original carries the same
evaluate numbers, but its Substitute is a real HP pool the instruction generator breaks,
its setup is applied to real stats in a real damage formula every ply, and its opponent
answers with every move it has at real accuracies — so those constants are calibrated to
a board this one still only approximates. **The next arm is not more search: it is the
leaf's non-HP terms re-priced against this board** (SUBSTITUTE_VALUE and STAGE_VALUE
first, since they moved the picks), with 0.7.9's roll and opponent model kept, because
those are now correct and were not before. A 15000-iteration arm is the other ablation
(the top-visit share fell), and it costs three times the run.

**Process.** Another session's Game.exe was mid-run in the master game folder when this
run was ready, so it ran from a private worker (`.gauntlet-workers/realidea-w1`: Data, PBS,
Fonts, the exe and dlls copied; Audio and Graphics junctioned, 62 MB), which is the Reborn
parallel layout applied to Realidea. Read the version stamp off the artifact: the master
bundle became 0.7.9 at 17:27 and any run launched from it after that is 0.7.9 whatever
its harness file says.

**Artifacts** (`generated/`): `realidea_tier_gen5ru_a_0_7_9_mcts_5000.ndjson` (traced;
the stock half is the control). Backup of the pre-install bundle:
`backups/realidea_Scripts.rxdata.pre-0.7.9`.

### 0.8.0 — the real Foul Play, playing inside this engine, 2026-09-08

**Why.** 0.7.9 ended with the search's board audited against poke-engine's and the tree
losing more, and the question it could not settle was whether search itself was worth
anything here or only our approximation of the board was. So the approximation was
taken out of the comparison: every voluntary decision an actor faces is serialised as a
poke-engine `State` (`Data/ai_foulplay_state.json`: both full parties with raw stats,
moves with PP and the engine's own disabled flags, items, abilities, natures, EVs,
statuses, boosts, the side's hazards, screens and volatiles with their durations,
weather, terrain, Trick Room, the Choice lock as `last_used_move`), a Python sidecar
(`tools/foul_play_sidecar.py`, running pmariglia's `poke_engine` package built for gen 6
at commit `f4e224c`, the same clone 0.7.9 audited against) runs
`monte_carlo_tree_search` on it for the requested iterations and writes back the
most-visited root choice as a slot (`Data/ai_foulplay_reply.txt`), and the adapter maps
that onto one of the actions the snapshot already built and registers it through the
same path as every other planner (`FoulPlay` module in the adapter; `plan_for` runs it
first when `foul_play` is on and falls through to the rules on any decline). Forced
replacements stay with the rules, as they do for the search planner. The handoff is two
files through temp names and renames, polled every 4 ms; the whole exchange including
5000 iterations costs ~10 ms a decision, so a 120-battle set takes **1 min 40 s**
against the Ruby tree's ~22 min.

**What it scores.** Same three rosters, same seeds, same stock control (the stock half of
every set byte-identical to the 0.7.8 control's):

| roster | stock | rules (0.7.8) | MCTS 5000 (0.7.8) | **Foul Play 5000** |
|---|---|---|---|---|
| gen5ru_a | 39 | 50 | 48 | **53** (a first run of the same set scored 50: gained 6 lost 6 against the rules, then 7/4 — run-to-run spread of the sampler is about ±3) |
| gen5uu_a | 26 | 47 | 48 | **55** |
| gen6uu_a | 31 | 46 | 44 | **54** |
| **pooled** | 96 | 143 (79.4%) | 140 | **162 (90.0%)** |

Paired over 180: Foul Play **+19 over the rules, gained 30 lost 11, McNemar p = 0.005**;
**+22 over the 0.7.8 tree, gained 34 lost 12, p = 0.002**. Every roster is positive
against both (per-roster p = 0.06–0.08 against the rules, n = 60 each). This is the
first arm in the study to beat the rule engine at all, and it does so after eight
versions of our own search could not get past parity. **The search was never the
problem; the board was.** Foul Play plays on poke-engine's real instruction generator
and evaluation, and the only thing it shares with 0.7.9 is the tree.

**How it plays.** 4614 of 4619 portable decisions went through the bridge (the rest are
replacements). Status moves are **29.2% of its move picks** (Roost 312, Calm Mind 169,
Toxic 119, Stealth Rock 99, Slack Off 92, Roar 80, Protect 58), against ~15% for the
rules and 0.7.9's "doubled" status rate that the write-up there read as the failure. It
was not: a search that values setting up and recovering wins here when its board is
right and loses when its board is not.

**The mechanics gap, measured (the milestone the plan asked for first).** With
`--check` the sidecar prices the on-field pair's damaging moves both ways with
poke-engine's `calculate_damage` (max roll, no crit — the first of the two values it
returns; the second is the crit) and pairs each with the adapter's own cell, which is
the same quantity from `pbRoughDamage`. `generated/realidea_foulplay_check_<roster>_0_8_0.ndjson`,
~4000 rows a roster:

| roster | median ratio engine/cell | within 3% | within 10% |
|---|---|---|---|
| gen5ru_a | 0.995 | 78% | 92% |
| gen5uu_a | 1.000 | 85% | 97% |
| gen6uu_a | 1.000 | 67% | 79% |

Every systematic offset is a **generation difference, not an engine bug**: Realidea's
PBS carries gen 5 numbers and poke-engine plays gen 6. Thunderbolt/Ice Beam 0.945
(95 → 90), Fire Blast 0.917 (120 → 110), Thunder 0.917, Heat Wave 0.95, Leaf Storm
0.929 (140 → 130), Dragon Pulse 0.944, Meteor Mash 0.90; the gems at 0.866 (Rock Gem
and Flying Gem are ×1.5 here, ×1.3 in gen 6, so Kabutops' Stone Edge and Sceptile's
Acrobatics); Knock Off **×3.2** on gen6uu_a (gen 6 made it 65 base and ×1.5 on a held
item; this engine's is 20) — poke-engine overvalues Knock Off here, and still won that
roster; Return **×3.5** (poke-engine assumes full happiness, 102 base; a trainer's mon
here has its species' base happiness, so Escavalier's Return is 28). Rock Blast 0.32
and Psywave 0 are checker artefacts (the engine prices one hit and a special case).
Cells under 1% against an engine zero are `pbRoughDamage`'s 1-HP floor on an immune
hit (085:3608), flagged `cell_floor`. The gap is real, small, and costs the arm less
than it gains: a build of poke-engine with gen 5 numbers would close most of it and is
one Cargo feature away (`--features poke-engine/gen5`).

**Addendum, the gen 5 build (same day).** The offsets above are one Cargo feature away,
so the wheel was rebuilt with `--features poke-engine/gen5` (crit ×2 there, which is how
the build was confirmed to have taken) and the two gen 5 rosters rerun with it,
same seeds, same control (`realidea_tier_<roster>_0_8_0_foul_play_5000_gen5build.ndjson`,
`realidea_foulplay_check_<roster>_0_8_0_gen5build.ndjson`). **The damage gap closes and
the score does not move:**

| roster | within 3% (gen 6 build → gen 5 build) | within 10% | Foul Play gen 6 build | **gen 5 build** | rules |
|---|---|---|---|---|---|
| gen5ru_a | 78% → **93%** | 92% → 95% | 53 | **54** | 50 |
| gen5uu_a | 85% → **94%** | 97% → 98% | 55 | **56** | 47 |

Pooled over the 120: gen 5 build 110, gen 6 build 108, rules 97; gen 5 against gen 6
gained 9 lost 7, p = 0.80 — a tie; gen 5 against the rules +13, p = 0.021. What is left
in the check is Return (poke-engine assumes full happiness in every generation) and
Rock Blast (the checker prices one hit). So the ~11-point lead over the rules is not an
artefact of gen 6 numbers flattering or hurting the search; the search is that good on
a board that is right to within a few percent, and a board that is right to within ten
percent is already enough. Use the gen 5 wheel for gen 5 rosters from here (the build
script takes the generation as its second argument); the gen 6 roster keeps the gen 6
wheel, which is the one that knows megas and Fairy.

**Things that went wrong on the way.** (1) The first gen5ru_a run lost two turns to
`Errno::EACCES` on the reply file — Windows refusing a delete or open while the sidecar's
rename landed; `retrying` now waits 4 ms and tries again. (2) The gen6uu_a run killed the
sidecar on its 68th battle: poke-engine **panics** (a Rust `panic!`, surfacing as a
`PanicException` that `except Exception` does not catch) when a live Taunt carries
duration 3, because it counts turns *elapsed* (0..2) and Essentials counts turns
*remaining*. Encore, locked moves and Yawn have the same shape. `durations_for` converts,
the sidecar now catches `BaseException`, keeps the state that did it and answers
`type=error` so the turn goes to the rules at once instead of after the 60 s timeout;
that roster was rerun clean. (3) poke-engine's string parsers map an unknown species,
move, ability or item to `NONE`/`UNKNOWNITEM` silently, so every id is checked against
`generated/poke_engine_ids_gen6.json` (extracted from the enum source) and logged;
across the three rosters the only unknowns are Eject Button, Mental Herb and Light Clay.

**The iteration budget is load-bearing: 1000 is not enough, 2026-09-09.** The same
three rosters and the same seeds at `foul_play_iterations=1000`, nothing else changed
(and the budget verified off the trace, not the config: root visits median exactly 1000
a decision against 5000). Pooled **146/180 against the 5000 arm's 162** — gained 12 lost
28, p = 0.017 — and against the rules' 143 it is gained 24 lost 21, p = 0.77, a **tie**.
Every roster moved the same way: 46, 52, 48 against 53, 55, 54. So the ~11-point lead is
a property of the budget as much as of the board — at a fifth of the iterations the
search lands exactly where every Ruby arm landed, level with the rules. Nothing is
bought by the cheaper budget either: the sidecar drops from ~10 ms a decision to 2-4 ms,
but the engine at ~50 ms a turn dominates and the three rosters took 406 s against 463 s.
The bridge stayed clean over 4800 decisions — one decline, an unmapped switch reply on
gen6uu_a turn 39, which falls through to the rules by design. Caveat: the scratchpad had
been wiped, so the wheel was rebuilt by `tools/build_poke_engine.sh` at the same pinned
commit rather than being the literal binary the 162 was measured with.

**What this means for the study.** The 0.7.x line's conclusion inverts: a correct
board plus search beats the rules by ~11 points on these rosters, so the leaf
re-pricing 0.7.9 proposed is worth doing only if one wants a *shippable* search — this
one is a study instrument (a Python process beside the game) and can never run for a
player. The rule engine is not "near the ceiling"; it is ~11 points under a ceiling that
a 5000-iteration tree on the right board reaches in 10 ms. The untried 0.7.0 idea (rules
as the leaf) is now measured against a real number rather than a hope.

**Which board, and doubles.** The four boards a search could step here (Essentials'
own engine, this Ruby projection, Pokémon Showdown, poke-engine) were measured against
each other on 2026-09-09: see `SEARCH-BOARDS.md`. Short version, because it settles two
recurring questions: poke-engine cannot be made to do doubles without rewriting its core
(boosts and volatiles live on the *side*, every instruction addresses a side and not a
slot, `MoveTarget` is `User | Opponent`), and Showdown can, at ~4 s a decision for 5000
iterations against this bridge's 10 ms. Nothing in that document is installed.

**Reproduce.** `tools/build_poke_engine.sh` (clones and builds the gen 6 wheel into
`generated/foul_play/venv`, git-ignored); `generated/foul_play/venv/bin/python
tools/foul_play_sidecar.py --game <game dir> --check` in one terminal;
`Data/ai_harness.txt` with `schedule=tier`, `teams=<roster>`, `trace=true`,
`foul_play=true`, `foul_play_iterations=5000`; the trigger; `Game.exe`. Start the
sidecar first — a decision with no sidecar costs its 60 s timeout. Ran from
`.gauntlet-workers/realidea-w1` (its bundle is 0.8.0, as is the master's; `foul_play`
ships off, so a run without the key is 0.7.9 decision for decision).

**Artifacts** (`generated/`): `realidea_tier_<roster>_0_8_0_foul_play_5000.ndjson`
(three rosters, traced; candidates carry `foul_play_visits`, the search block carries the
foe's visit split), `realidea_foulplay_check_<roster>_0_8_0.ndjson`; the 1000-iteration
arm as `realidea_tier_<roster>_0_8_0_foul_play_1000.ndjson` and
`realidea_foulplay_check_<roster>_0_8_0_1000.ndjson`. Backup of the
pre-install bundle: `backups/realidea_Scripts.rxdata.pre-0.8.0`. Tests: core 209 (one
0.7.9 expectation re-pinned: a bare foe `stay` carries no move on that board),
adapter 126 (six new: the state shape, decline, reply mapping, silent-sidecar
fallback, a stand-in sidecar round trip, the JSON), tooling 34 (six new, two of them
engine-backed and skipped where `poke_engine` is absent).

### 0.8.1 — the bridge reaches a played battle, 2026-09-09

0.8.0 could only be switched on inside the gauntlet and the probe. `foul_play` is a
`Data/ai_harness.txt` key, the harness file was read only by `Harness.with_config`, and
nothing wraps a battle a *player* walks into — so a normal battle installed no overrides
at all and the enemy always fell to the rule engine, whatever the file said.

`Harness.live_overrides` reads the same file for that case, and only for that case: it
is gated on `Data/portable_ai.txt` being present, not on `requested?`. The gauntlet and
the probe run with the marker absent and set `$PORTABLE_AI_ENABLED` themselves, so every
measured run still takes its config solely from `with_config` and is untouched by this
path; and a run that did install overrides still wins outright. The read is memoised for
the session, so editing the file mid-session cannot apply to half a battle.

The other half is a live-play failure mode the harness never felt. A silent sidecar costs
one 60 s timeout per decision, which is invisible in a batch and unplayable at the
keyboard. A timeout now sets `@portable_ai_foul_play_off` on the battle: the bridge is
asked once per battle, not once per turn, and the next battle asks again. An `error`
reply is not silence and disables nothing — poke-engine panics on particular positions
(the duration bug in the 0.8.0 addendum), not on a whole battle.

**Measurement is unchanged.** With the marker absent `live_overrides` returns `{}`, so
0.8.1 is 0.8.0 decision for decision on every gauntlet and probe run; the version stamp
moves so records still say which bundle produced them. The one behavioural difference is
confined to a *degraded* run: where 0.8.0 retried a dead sidecar every turn, 0.8.1 stops
for the rest of that battle. Both fall to the rules either way, and the log says so.

**How to play against it.** In this order:

Double-click **`Realidea V4.1/Play with Foul Play.bat`**. It writes the two trigger
files if they are missing, starts the sidecar, launches the game, and stops the sidecar
when you quit. That is the whole thing.

It is the only file tracked inside the game folder besides `Data/Scripts.rxdata`. The
triggers it creates are deliberately *not* committed: a `Data/portable_ai.txt` in the
repo would be copied into the gauntlet workers, and a measured run with the marker
present makes both arms portable and invalidates the stock/portable pairing.

**First run on a machine that has never built the bridge** is not just a double-click.
The search is a Rust crate compiled into a Python wheel, so it needs, once:

1. WSL2 with a Linux distro,
2. `uv` and a Rust toolchain (`cargo`) inside it,
3. `tools/build_poke_engine.sh _AI-Study/generated/foul_play gen5` — about 30 s once the
   toolchain exists, and it records the distro it built in so the `.bat` can find it.

The venv is git-ignored, so a fresh clone always needs step 3; the sidecar window prints
that exact command when the wheel is missing. Everything after that is the double-click.
Nothing about the *game* needs a first-run step — `Data/Scripts.rxdata` carries the
installed sections and is tracked.

`tools/foul_play_sidecar.bat` is the sidecar alone, for when the game is already running
or a different copy is being served. It takes no arguments for the campaign copy.

```bat
foul_play_sidecar.bat                      the campaign copy, gen 5 wheel
foul_play_sidecar.bat "C:\path\to\game"    another copy (a gauntlet worker)
foul_play_sidecar.bat "" gen6              the gen 6 wheel
```

The game is a Windows process and the search is a Linux wheel, so the `.bat` runs the
sidecar through `wsl.exe`; the two halves only ever meet in `Data/`, which is the same
arrangement the 0.8.0 measurement ran on. It hardcodes `-d UbuntuWork` because the
venv's `python` symlinks into that distro's home — the default distro cannot run it and
fails with a bare "No such file or directory". It resolves its own paths, checks the
wheel is built, and clears a leftover sidecar **for that game directory only**, so a
gauntlet worker's sidecar is left alone. Closing the console window does not reliably
reach the Linux process, which is why clearing a stale one is automatic rather than an
error. By hand, the equivalent is:

```bash
tools/build_poke_engine.sh _AI-Study/generated/foul_play gen5   # once
generated/foul_play/venv-gen5/bin/python tools/foul_play_sidecar.py \
  --game "Realidea V4.1"
```

`Realidea V4.1/Data/portable_ai.txt` (any content) and a `Data/ai_harness.txt` holding
`foul_play=true` and `foul_play_iterations=5000`, then launch and fight any trainer in
singles. Kill the sidecar with `pgrep -f "foul_play_side[c]ar.py --game"` — a plain
`pkill` on the name kills the calling shell.

Limits to know before playing, none of them new:

- The bot sees your whole team, the same fair-information the Portable AI is given.
- Singles only. Doubles decline to the rule engine, as the search planner does.
- A forced replacement after a KO stays with the rule engine: `pbDefaultChooseNewEnemy`
  never reaches `plan_for`.
- Wild battles are untouched (`ENABLE_WILD = false`).
- No sidecar means one 60 s stall per battle, then the rules, logged to
  `Data/ai_foulplay_log.txt`.
- It is a study instrument — a Python process running beside the game — not a shippable
  AI. Delete the marker to go back to stock.

**Tests.** Core 209, adapter 128 (two new: the marker gate on `live_overrides` with
`with_config` still winning, and the silent sidecar being dropped for the battle but not
the process), Reborn 53, tooling 34. Install backup:
`backups/realidea_Scripts.rxdata.pre-0.8.1`.

## Future-agent handoff

### 0.6.2 port (2026-09-06)

Five commits, one per core version step, each with its own tests and rebuild. What the
adapter learned about this engine along the way, and where it deliberately refuses to
copy Reborn:

**Function codes agree below 0x100 and diverge above it.** The base v16 space
(0x05-0x21 status secondaries, 0x42-0x4F target drops, 0xBD-0xC1 multi-hit, 0xDD/0xDE
drain, 0xFA-0xFE recoil) was checked move by move against `PBS/moves.txt` and is shared
verbatim. Everything Reborn carries above 0x100 was pruned. The divergences that would
have silently mislabelled moves:

| Code | Reborn | Realidea |
|---|---|---|
| `0x139` | 3/4 drain (Draining Kiss) | Play Nice — an Attack drop |
| `0x13B` | SpAtk drop | Hyperspace Fury — a Defense drop |
| `0x13F` | Speed drop | Flower Shield — raises ally Defense |
| `0x14F` | *(unused)* | the 3/4 drain |
| `0x15A` | *(unused)* | First Impression |
| `0xCF19` | *(unused)* | Pollen Puff — **heals** a targeted partner |

`tools/check_move_codes.py` is the guard; run it in the gate.

**There is no `pbMakeFakeBattler`, and the two-line equivalent is not pure.**
`PokeBattle_Battler.new(battle, index)` runs `pbInitEffects(false)`, which reaches
across to every *other* battler and clears whatever points at the index being built:
Lock-On and its position (`080:338-345`), infatuation (`:374-378`) and Mean Look
(`:418-424`). Building a fake at the actor's own index therefore cancels real board
state the estimate is only supposed to be measuring. All four slots are snapshotted and
restored around the construction; `pbInitPokemon` itself (`:203-241`) only copies stats
and builds move objects through `pbFromPBMove`, which takes `(battle, move)` here — no
user argument.

**`move_memory` cannot work on this engine, and the key is deliberately not exported.**
Realidea declares `PBEffects::LastMoveFailed = 4` in the *move-usage* namespace
(`075_PBEffects.rb:170`), which is the same index as the *battler* effect
`BideDamage = 4` (`:8`). The battler's copy is initialised to `false` (`080:415`) and
**nothing in the build ever sets it true** — the only writes to index 4 are Bide's damage
accumulator — so this engine's own Stomping Tantrum doubling (`083:10383`) is dead code.
`successStates[i].useState` is not a substitute either: it is set to 2 only on the
damaging path (`080:3223`), so a status move that worked perfectly reads back as
`1 = failed`. With no key exported, `Model.truthy` reads nil and the core rule is inert,
which is the honest answer; exporting it from either source would take 200 points off
the wrong moves. A negative contract test keeps the decision from being quietly undone.

**Three Reborn behaviours are absent here and are not modelled.**

- Prankster is a priority modifier and nothing else (`084:1108`, `080:2618`). There is
  no Dark-type immunity to it anywhere in the build, so the Reborn clause that kills a
  Prankster status move into a Dark type would make the AI refuse a move that lands.
- Psychic Terrain is *set* by move `0x169` and read by nothing, so a priority move under
  it keeps its bracket. `effective_priority` replicates only the three ability rows the
  engine actually brackets on (`084:1105-1113`).
- Magic Bounce reflects only moves carrying the Magic Coat flag (flag `c`,
  `082:236`) and yields to Mold Breaker (`080:2433`) — narrower than Reborn's blanket
  reflect, and it does not read the partner's ability.

The corpus cards for the first two, and the pair that tests move memory, are skipped by
name in `AI_Probe::UNSUPPORTED` with the reason attached, so they report SKIP rather
than a spurious failure.

**Damage estimates changed, on purpose.** `rough_damage_pct` now does the same
base-damage preparation stock v16 does before `pbRoughDamage` (`085:2802-2810`):
`basedamage == 1` is the variable-power sentinel and scores as 60, and
`pbBetterBaseDamage` resolves the ~30 codes that compute their own power (Seismic Toss,
Super Fang, Night Shade, Endeavor, Gyro Ball, Grass Knot). Through 0.1.0 every one of
those was priced at its sentinel. Expect the in-engine probe to move on cards involving
them; that is a correction, not a regression, but read each one.

**Two exports Reborn has were skipped as having no consumer**: switch-candidate
`ability`/`item` and actor `types`. Nothing in `portable_ai/core.rb` reads them. If a
future core rule does, the contract test will say so.

### Important findings and traps

- Realidea is Essentials v16 with one Marshal bundle and no plugin loader. Section
  `085_PokeBattle_AI` still supplies scoring, but its `pbChooseMoves` is dead:
  `275_AI edit clara` redefines the method later and is the live stock selector.
  `Portable_AI` must remain after section 275 and before `Main`.
- Hooking only `pbChooseMoves` is insufficient for a complete switching policy.
  Stock `pbDefaultChooseEnemyCommand` tries `pbEnemyShouldWithdraw?` first. The portable
  adapter therefore owns the enabled trainer command path and uses stock code only for
  items, locked/unsupported states, or explicit fallback.
- A doubles plan must be created once for the whole opposing side and cached for the
  command phase. Planning each battler independently caused duplicate targets and cannot
  prevent two battlers selecting the same switch slot.
- `PBTargets::SingleNonUser` permits targeting a partner. Do not treat it as
  “single opponent.” Targeted friendly fire must be rejected, while spread friendly
  fire must be scored against the partner rather than rejected unconditionally.
- Locked turns (`Outrage`, two-turn attacks, recharge, Rollout, and similar states)
  preserve the prior choice. A headless runner must not replace those choices with
  Struggle. It must also clear `PBEffects::SkipTurn` and reset pending Mega Evolution
  choices exactly as the normal command phase does.
- Run the gauntlet with `Data/portable_ai.txt` absent. The gauntlet toggles
  `$PORTABLE_AI_ENABLED` itself to produce paired stock/portable runs. Leaving the marker
  present makes both halves portable and invalidates the comparison.
- The stock doubles probe records a complete per-target score matrix, but its flattened
  move vector uses the best target per move. Clara's live selector stochastically chooses
  one target score before roulette, and that local vector is not observable. Do not use
  the flattened stock doubles vector as exact golden behavior; use the matrix, action,
  property assertions, and full-battle results.
- Ruby in the game follows 1.8-era behavior. In particular, do not use
  `Float#round(ndigits)`, modern keyword arguments, safe navigation, or external JSON
  libraries in injected code.
- Never rewrite the whole Marshal bundle from decoded objects. Existing script elements
  contain encoding metadata and symbol backreferences. `pack_rxdata.py` preserves
  existing elements as byte slices and writes replacements atomically.
- `generated/Portable_AI.rb` is generated output. Edit the module/adapter sources and
  rerun `tools/build_portable_ai.py`.
- **`PokeBattle_Battler.new` is not a pure query, and Realidea clears one more effect
  than stock Essentials does.** `pbInitEffects` wipes `MultiTurn`/`MultiTurnUser` on the
  battler that points at the index being constructed, on top of Lock-On, Attract and Mean
  Look. Anything that builds a throwaway battler at a live index — `fake_battler` does,
  once per switch candidate — must snapshot and restore all six slots or it will cancel a
  real partial trap while merely estimating. Read the list off the engine; do not carry
  stock Essentials' list across.
- `check_scenarios.py` intentionally fails on missing, errored, or degenerate records.
  Explicit unsupported-field skips are allowed and remain visible.

### Remaining work, in priority order

1. **Manual campaign validation.** Play representative route trainers, each implemented
   gym/boss, scripted battles, item-using trainers, Mega Evolution, switching loops, and
   both single and double battles. Exercise save/load before and after battles. Capture
   any `Data/portable_ai_error.txt` and convert every reproducible issue into a scenario.
2. **Expand the frozen gauntlet.** The current benchmark uses four synthetic three-Pokémon
   teams. Add validator-clean real boss teams as they become available, mirror matchup
   orientation, increase seed count, and report confidence intervals rather than relying
   only on 40 outcomes per AI.
3. **Broaden move knowledge.** `effects.rb` covers the corpus and common competitive
   families, not every custom Realidea move. Add move-ID descriptors only with a scenario
   or observed battle motivating them; unknown moves must continue to use the generic
   stock-score fallback.
4. **Improve fair-information memory.** Incoming-damage estimates currently inspect the
   active foe's available move objects. Replace this with a revealed-move memory model
   once the scenario format can state which moves are known, then add first-turn and
   revealed-after-use tests.
5. **Refine difficulty mapping.** Verify numeric `skillCode` correction across all
   trainer types and decide whether multi-trainer doubles should derive capabilities per
   owner instead of using the lower shared skill.
6. **Port to other Essentials eras.** Keep the core unchanged; add and measure v20/v21
   adapters first, then v19 and v17/v16 games. Each new adapter needs its own engine-side
   probe and per-game scenario resolution before claiming parity.
7. **Longer-term team integration.** Keep AI, team overrides, and level-cap changes as
   separately switchable variables so strength changes remain attributable.
8. **Foul Play for live play — done in 0.8.1 (2026-09-09).** See the 0.8.1 section
   for the recipe and the limits. What remains is a played campaign against it: nobody
   has yet fought the bridge through real trainers, so its behaviour outside the tier
   rosters (item-using trainers, scripted battles, Mega Evolution, mid-battle saves) is
   unobserved.

### Required gate for future changes

Before replacing the installed section:

1. Run all Ruby and Python tests.
2. Rebuild `generated/Portable_AI.rb`; do not hand-edit it.
3. Run `pack_rxdata.py --selftest` and verify upsert remains byte-idempotent.
4. Run `python3 tools/check_move_codes.py`. Every code in the adapter's tables must
   exist in `PBS/moves.txt`; read every advisory before ignoring it.
5. Run the complete in-engine probe. It must reproduce **246/262** with ten scenarios
   skipped by the engine and four assertions this AI cannot answer (it reports no numeric
   switch scale), and zero missing/error/degenerate records. Those four are counted as
   failures by `check_scenarios.py`, which is why the figure is 246 and not 250. The
   sixteen failing assertions are the same sixteen 0.6.2 failed; a change that moves any
   of them is a finding, not noise.
6. Run the paired seeded gauntlet with no portable marker. The only meaningful
   regression signal is **losses that the previous version won on the same seed** —
   list them by seed and read the traces. Do not expect a win-rate gain; Reborn showed
   none across 0.3 -> 0.6.
7. Run the ablation controls from `Data/ai_harness.txt` and check each reproduces its
   predecessor version's decisions per seed, verified from the `portable_version` and
   `config_overrides` stamps on the records rather than from file times.
8. Remove all `ai_probe.txt`, `ai_gauntlet.txt`, `ai_harness.txt`, and `portable_ai.txt`
   trigger files, then smoke-test the normal title path and confirm
   `Data/portable_ai_error.txt` is absent.
9. Update `generated/portable_ai_results.json` hashes and metrics only from the exact
   artifacts used for the report.

### What is outstanding right now

The probe is done, the hang is fixed, the tier gauntlet is measured, 0.6.3 shipped the
switching rules, 0.6.4 closed the switch-back loop, 0.6.5 added the matrix, 0.6.6
fixed Levitate and measured the oracle, 0.6.7 stopped crediting a hit the actor does
not live to throw, and 0.7.0 put a second planner behind the same seam without touching
the first — which 0.7.1-0.7.8 then took from 31/60 to 48/60 without ever passing the rule
engine it was meant to replace. Outstanding, in priority order:

-2. **Decide whether the search planner is worth a second ply.** It is measured and it
   loses: 31/60 against the rule engine's 48 and stock's 39 (see *0.7.0*). The two bugs
   the run exposed are fixed; what remains is the design. The two changes that would move
   it are a **second ply** and a **per-move damage estimate against off-field bodies**
   (without which the foe-switch column cannot order moves at all, and it supplies 41% of
   the worst cases). Neither is cheap. The honest reading of the number is that a search
   planner needs a leaf that is at least as good as the rules it replaces, and
   `cell_verdict` is not — so the more promising direction is the reverse of this
   version: keep the rule engine as the leaf evaluator and search over it. Do not spend
   more on the current shape without deciding that first.

   **Update, 2026-09-08, after 0.7.1-0.7.8.** The planner was taken from 31 to 48 across
   eight versions — leaf and candidate fixes, a second ply, turn effects, per-move bench
   pricing, an opponent model, MCTS, a foe move axis, a budget that can resolve it, and a
   free damage prior. **It has never beaten the rule engine at any point on that path**, and
   on three rosters and 180 battles its best arm (MCTS 5000) is 135/180 against the rules'
   140/180, 30 / 25 discordant, p = 0.59 — a statistical tie, at ~100x the cost per decision
   (~1 s vs ~10 ms in Ruby). Every lever named above has now been pulled; the one in this item — *keep the
   rule engine as the leaf evaluator and search over it* — is the only one never tried, and
   it is the recommendation this line ends on rather than one it disproved.

-1. **Build the predictor.** 0.6.7 closed the dead-slower-attacker half of the oracle's
   consumer (see *0.6.7*); the oracle now sits at 150/180 against the shipped 140, and
   against 0.6.5 it is the first pooled result past p = 0.05. What is left on the consumer
   side is small: a declared Sucker Punch is still a full hit on a switch-in it would fail
   against, and Endure / Protect at their stock base score win the scaled turn seven times
   on one roster. The distribution producer (damage-argmax 54.9%, lock → repeat → argmax
   57.6% on the 0.6.5 traces) is the next thing to build, exporting the same fields, and
   its number is judged against the oracle's. The remaining readout items — `strict_
   threat`'s 95% cliff is closed only under the oracle; Toxic flat +25, Stealth Rock
   engine-base only, Substitute a flinch guard — are in the memory file. The gate below
   the 50% pivot line (a dying actor under 50% may not leave, so it attacks at a quarter)
   is a design choice the rule leaves alone; the 210 turns it still attacks on are there.
-0. **Re-run Reborn.** `no_hit_needs_threat` (0.6.6) and `dead_before_moving` (0.6.7) both
   reach it; the installed Reborn bundle is still 0.6.5 and its control status for either
   version is unmeasured.

0. **The core has no model of foe recovery and no value for Protect** (see *0.6.3*,
   *0.6.4*). `damage_race` counts hits with no heal term and targets export no moves —
   both adapters *read* the foe's moves to build `incoming_by_move`, they just export the
   damage and not the list — so "mine 6 turns" against a Soft-Boiled Clefable is fiction,
   and no rule values Protect (scouting, stalling a poisoned foe, receiving a Wish); foes
   chose it 31 times in 3,033 turns. Step one is a target-level export (`heals_pct`,
   `has_protect`, `has_status`, `has_setup`), which is fair information because the stock
   AIs read the same moves. The wall switch-backs that sat here at 0.6.3 are closed: they
   were a PP bug in the bench estimate (*0.6.4*).
0b. **The kill-order grade** (`switchin_race_grade`, off) cost wins on one Reborn roster
   and a traced pair of that roster is committed; the first divergences are written up
   under *0.6.4*. Whether a bench body that loses its race on a point estimate should be
   charged at all, or only relative to the actor's own race, is the open design question.
1. **Re-measure 0.1.0 so the regression check can actually run.** The gate asks for
   losses the previous version won on the same seed; 0.1.0's per-battle records were not
   kept, only their hash, so that comparison is currently impossible (see *Against the
   0.1.0 baseline*). Rebuilding 0.1.0 from git and re-running it at the same 20 seeds is
   now under a minute of box time and would settle whether Portable's two-battle singles
   deficit is real. Every gauntlet artifact is now copied into `generated/`, so the loss
   cannot recur.
2. **Run the ablation controls** from `Data/ai_harness.txt` — each 0.6.2 key off in turn,
   checked against its predecessor's decisions per seed. Cheap now, and untouched.
3. **Report the three engine bugs upstream, or work around them.** Six battles of 240 end
   with no verdict. The `hasWorkingAbility` one is a one-word fix (`hasAbility?` on a
   party Pokémon) and it is stock-only, so leaving it in place makes the stock arm look
   slightly worse than its policy deserves.
4. **Use the shadow arm on the archetype fixture too.** The 41.7% disagreement figure is
   measured on the tier rosters only; the frozen 3-mon fixture is a different distribution
   and would say whether the switching gap is roster-specific.
5. **A second tier draw is not available.** gen6ou's eligible pool is 11 teams and both
   sets are already drawn from it; a third set would overlap. Widening the corpus means
   adding another gen 6 source to `extracted/smogon-teams/`, not re-rolling the seed.

**Correcting the 2026-09-06 cost estimate for this port,** which was wrong in three ways
worth recording, since all three were wrong in the direction of discouraging the work:

| estimated | actual |
|---|---|
| "reuse `tier_teams_reborn.rb` verbatim, except `HIJUMPKICK` → `HIGHJUMPKICK`" | gen 7 is unusable here (Z-crystals), gen 6 needed three teams dropped for ability slots, and the rosters needed their own draw |
| "`hptype`: **drop it**" | wrong call — dropping it silently retypes 7 of 13 Hidden Power sets. It had to be *solved* against this engine's 17-type formula |
| "~480 battles, roughly 1.5-2.5 h serial" | 240 battles, **~64 seconds per 120-battle set**. The estimate was off by about two orders of magnitude, and no parallel path was needed |

The argument recorded against doing this at all — that Reborn's tier suite produced a
negative result and stock v16 is "a weaker and less pointed question" — did not survive
contact either. Against this engine the suite is the *most* pointed measurement on this
page: +16.9 points with a 50.0% stock-versus-stock control, and it is what surfaced three
engine bugs and the `$ItemData` fault that had been silently breaking the harness.

At this handoff, all trigger files are absent, the injected section is installed but
inactive, and `pack_rxdata --selftest` round-trips byte-identical. The pre-change bundle
is `backups/realidea_Scripts.rxdata.pre-0.6.2`, and the bundle from before the tier port
is `backups/realidea_Scripts.rxdata.pre-tier`. The working tree also contains
pre-existing team-generation and study edits from other sessions; future agents should
inspect the diff and avoid reverting unrelated work.
