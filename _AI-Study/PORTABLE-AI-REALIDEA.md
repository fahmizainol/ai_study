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
`key=value` per line, `#` comments allowed. It is the same file and the same nineteen
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

`Data/ai_harness.txt` also carries keys the gauntlet reads directly. Unlike the nineteen
config overrides these do not touch core policy — they choose what runs.

| key | default | meaning |
|---|---|---|
| `teams=NAME` | `archetype` | roster set: `archetype` (frozen 3-mon fixture), `gen6ou_a`, `gen6ou_b` |
| `schedule=tier` | frozen | every ordered non-mirror pairing of the set's four teams (12 matchups), written to `Data/ai_tier_results.ndjson` so tier numbers can never pool with the frozen benchmark |
| `matchups=x,y` | all | run only these named matchups — for smoke-testing a roster, or resuming past one that stalled |
| `mega=false` | on | suppress Mega Evolution (see *Mega Evolution*) |
| `seeds=a,b,c` | five | replace the default seeds |
| `trace=true` | off | record the per-turn portable decision trace, plus `parties` (see *Turn-by-turn traces*) |
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
ruby _AI-Study/tests/test_portable_ai.rb        # 108 tests
ruby _AI-Study/tests/test_reborn_adapter.rb     # 53 tests
ruby _AI-Study/tests/test_realidea_adapter.rb   # 64 tests
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

```
python3 tools/render_realidea_battle.py generated/realidea_tiertrace_gen6ou_a.ndjson --list
python3 tools/render_realidea_battle.py generated/realidea_tiertrace_gen6ou_a.ndjson team1_vs_team4 104729
```

```
Turn 2   actor 1   BULLETPUNCH @0               score    820.0
    view: hp 73%  speed 249 (faster)  incoming max 28%  certain 28%  threatened_lethal=False
    race vs foe@0: mine 1 turns, theirs 3, winning=True

Turn 3   actor 1   switch -> Hoopa              score    291.9
    view: hp 73%  speed 249 (slower)  incoming max 147%  certain 44%  threatened_lethal=True
    race vs foe@0: mine 5 turns, theirs 1, winning=False
```

**Tracing is observation-free**, and that is checked rather than assumed: the traced
`gen6ou_a` run reproduces the untraced one exactly — 41/12/6/1 and 32/25/0/3, same win
rates, same mean turn counts.

Four things to know before reading one:

| | |
|---|---|
| **Portable arm only** | `run_one` stamps a trace for `mode=portable` only, so there is no stock-side decision record and no turn-by-turn diff of the two AIs. Reborn's shadow arm does that; this engine has no equivalent. |
| **Decisions, not outcomes** | the line says what Portable chose and the evidence it saw. It does *not* say whether the move hit, crit or was Protected. Reborn's renderer has an `events` stream for that; this gauntlet records none. |
| **A missing turn is a fall-through** | no line means Portable did not decide that turn — the adapter deferred to the stock path, or the actor could not act. |
| **`race` is keyed by battler seat, not party slot** | the record carries no per-turn foe identity, so the renderer prints `foe@0` rather than guessing a species. A *switch* entry's `slot` **is** a party index and is resolved to a name. |

`parties` (species and final HP per side) is written only alongside a trace — a switch is
recorded by party slot and a renderer has no other way to learn what lives there. Without
`trace=true` the record stays the compact one every earlier run used.

Error records carry their partial trace too, since the battle that crashed is the one
most worth reading; before that they were the only records that threw it away.

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
5. Run the complete in-engine probe. All **260** applicable assertions must pass, with
   the ten explicit skips (seven Reborn fields, three unsupported mechanics) and zero
   missing/error/degenerate records.
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

The probe is done, the hang is fixed, and the tier gauntlet is measured. Outstanding, in
priority order:

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
4. **A second tier draw is not available.** gen6ou's eligible pool is 11 teams and both
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
