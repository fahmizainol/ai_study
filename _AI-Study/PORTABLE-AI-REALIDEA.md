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

Section 332 `Portable_AI` is **3754 lines** at `PortableAI::VERSION = "0.6.2"` (the
0.1.0 install was 1511). Section 329 `AI_Probe` is replaced at the same time.

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
`key=value` per line, `#` comments allowed. It is the same file and the same twenty-eight
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
| `teams=NAME` | `archetype` | roster set: `archetype` (frozen 3-mon fixture), `gen6ou_a`, `gen6ou_b` |
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
ruby _AI-Study/tests/test_portable_ai.rb        # 149 tests
ruby _AI-Study/tests/test_reborn_adapter.rb     # 53 tests
ruby _AI-Study/tests/test_realidea_adapter.rb   # 105 tests
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

**Why gen 6 only.** Realidea carries the gen 7 dex and all 29 Z-crystals as items and
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
holds `"<own slot>:<foe slot>" → {out, out_cat, out_move, in, in_cat, in_move, faster}`,
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
switching rules and 0.6.4 closed the switch-back loop. Outstanding, in priority order:

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
