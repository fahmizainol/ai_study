# Portable AI for Reborn Yang

Implementation status: installed and corpus-validated, opt-in, core version 0.2.0
(2026-09-04). This is the second engine adapter for the portable core (first: Realidea,
`PORTABLE-AI-REALIDEA.md`) and the groundwork for the head-to-head benchmark the port
exists to enable: **portable AI vs Reborn's own AI (Normal and Intense), in Reborn's
engine** — the first strength number against the study's reference-quality AI rather
than a decision-agreement number.

> **Every gauntlet win count recorded before 2026-09-05 is wrong, and the corrected
> numbers are in "Corrected baseline" below — read that before any table in this file.**
> The left seat — Reborn's own AI in every default arm — was disobedient in every
> battle ever run, losing about one move attempt in six to naps, self-inflicted
> confusion damage and ignored orders, because `PokeBattle_Battle#initialize`
> overwrites `obedient` on `@party1`. On the fixed harness the reference scores
> **158/300 (52.7%)**, not the 239/300 (79.7%) this file called a "fair ceiling";
> Portable 0.4.1 scores **142/300 (47.3%)**, not 217/300. The gap is 16 battles,
> p = 0.11. Re-measured on the fixed harness the 0.4.x rules are worth **+19 battles
> over 0.3.2 at p = 0.012**, where the handicap had shown +7 at p = 0.38 — so this
> file's standing conclusion that no rule ever moved wins was an artifact too. The
> 79.7% ceiling, the seat audit's "large positional effect" and the finding that the
> bulky archetype carries the deficit were all artifacts of the handicap. What does
> survive is "Intense buys nothing" (−7 vs Normal, p = 0.54) — though the same cheat
> set costs *Portable* 23 battles, p = 0.017.

## What is installed

Reborn Yang loads plaintext scripts per `Data/!script_order.csv`. The install adds:

| File | Change |
|---|---|
| `Scripts/Portable_AI.rb` | **new** — generated bundle: `portable_ai/{model,effects,core}.rb` + `adapters/reborn/Portable_AI_Adapter.rb` |
| `Data/!script_order.csv` | `Portable_AI` inserted between `AI_Harness` and `Main` |
| `Scripts/AI_Harness.rb` | probe mode now labels records (`"ai"` field) and reads the portable plan's score vector when the portable AI made the decisions |

Hook point: `PokeBattle_AI#chooseAction` — Reborn's single registration site. Its
per-battler loop starts with `next if @battle.choices[i][0] != 0`, so the portable side
registers its choices first and the host AI skips those battlers naturally. No other
Reborn code is touched.

## Enable and disable

Disabled by default. Enable by creating `Data/portable_ai.txt` (or setting
`$PORTABLE_AI_ENABLED = true`); the portable AI then drives the **trainer/AI side**
(odd battler indices). Delete the marker to restore Reborn's AI everywhere.

## Design decisions that differ from the Realidea adapter

1. **No silent fallback — errors re-raise.** In Realidea, errors fall back to the stock
   selector, which is safe because stock IS the baseline. Here fallback would mean
   letting Reborn's own AI decide, silently contaminating any head-to-head result.
   Failures append to `Data/portable_ai_error.txt` and re-raise; a benchmark battle or
   probe scenario that errors is recorded as an error, never as a quiet substitution.
2. **Neutral base score (100), not the host scorer.** The Realidea build consumes stock
   v16 `pbGetMoveScore` as base evidence. Reborn has no stock scorer left — its
   replacement is the 17k-line AI this benchmark measures against, so consuming it is
   forbidden by construction. The gap this opened (status immunities, Belly Drum's HP
   cost, Solar Beam's charge turn, phaze value) was closed with canonical knowledge in
   `effects.rb`/`core.rb` plus adapter-computed facts — see version 0.2.0 below.
3. **Intense cheats are masked during snapshot building.** `pbRoughDamage` and
   `pbTypeModNoMessages` are legitimate engine primitives (damage/type belong to the
   adapter per AI-PORTABILITY.md §4), but Reborn's damage path reads
   `$game_switches[3000]` (Intense: 100% Sucker Punch prediction, player-choice and
   mega reads) and `@swappredicted`. The adapter stashes and neutralizes both while
   estimating, so the portable side always sees fair information even in an Intense
   benchmark arm — that separation is the point of the benchmark.
4. **Faint replacements stay with the engine** (`pbDefaultChooseNewEnemy`) for both
   sides, matching what the Realidea gauntlet did (stock replacement logic for both
   modes). Mega/Z registration is likewise left to the host paths; benchmark fixtures
   carry no mega stones or Z-crystals.

## Core version 0.2.0 (was 0.1.0)

Closing the neutral-base gap produced portable improvements, keyed canonically:

- `effects.rb`: status moves now carry kind tags (`paralyze`/`burn`/`poison`/`sleep`/
  `confuse`, `powder`, `typed_status`); `BELLYDRUM` gains `hp_cost_half`;
  `SOLARBEAM`/`SOLARBLADE` gain `charge_solar`.
- `core.rb`: four new rules — reject unaffordable half-HP-cost setup (≤50%), penalize
  solar charge moves outside sun (−120), value phazing by foe hazard layers and target
  boosts (`foe_hazard_layers`·15 + `target_positive_stages`·25), and **hard-reject
  non-damaging moves aimed at the partner** unless tagged as support.
- The partner rule fixed a real doubles bug found by the corpus: with both foes asleep,
  0.1.0 registered Spore at its own partner (fresh-status bonus, and the friendly-fire
  rejection only covered damaging moves).
- Adapter evidence: `status_blocked?` (type-based immunity facts + the engine's own
  type verdict for `typed_status`), `foe_hazard_layers`, `target_positive_stages`,
  `friendly_target` now set for non-damaging partner targets too.

**The installed Realidea section is still 0.1.0.** The new core rules fire from tags
alone (`hp_cost_half`, `charge_solar`), so rebuilding for Realidea requires the full
gate in `PORTABLE-AI-REALIDEA.md` (163/163 probe + paired gauntlet) before reinstall.
The Realidea adapter also does not yet supply the new evidence fields (inert there —
`Model.number` defaults them to 0).

## Measured result

Corpus: the full 126 scenarios / 169 assertions resolved for Reborn
(`Data/ai_scenarios.txt`). Nothing is skipped — Reborn implements the five field
scenarios Realidea had to skip, and the adapter's engine primitives are field-aware.

| Check | Result |
|---|---|
| Stock regression (portable section loaded, inert) | **169/169** — identical grader outcome to the archived reference run |
| Portable Tier-1 (0.2.0) | **169/169**, 0 errors, 0 adapter failures |
| Tier-2 vs Realidea-portable (adapter-vs-adapter) | mean ρ **0.941** (median 1.000, 118 comparable), action-type agreement **120/121 (99.2%)** |
| Tier-2 vs Reborn reference | mean ρ **0.889** (median 1.000, 124 comparable), action-type agreement **121/126 (96.0%)** |

The adapter-vs-adapter ρ sits below the 0.99 bar AI-PORTABILITY.md §7 sets for
identical-by-construction adapters — expected and documented: the two builds are *not*
identical by construction (stock-base vs neutral-base, different damage engines). The
low-ρ scenarios are dominated by sub-ranking noise below a decisive top pick (lethal
+500 collapses ordering among the losing moves; Spearman over 4 moves is coarse), which
is why action agreement is 99.2% while mean ρ is 0.941.

Artifacts: `generated/probe_results_reborn_portable.ndjson`,
`generated/probe_results_reborn_stockcheck.ndjson`,
`generated/tier2_reborn_portable_vs_realidea_portable.json`,
`generated/tier2_reborn_portable_vs_reference.json`.

## Build and install

```bash
python3 _AI-Study/tools/build_portable_ai.py --target reborn
cp _AI-Study/generated/Portable_AI_Reborn.rb "Reborn Yang/Reborn Yang/Scripts/Portable_AI.rb"
# Data/!script_order.csv already lists Portable_AI before Main; nothing else to do.
```

Verification loop (per run: ~3 min, window appears via WSL interop, exits by itself):

```bash
cd "Reborn Yang/Reborn Yang"
printf 'mode=probe\nout=Data/ai_probe_results_portable.ndjson\n' > Data/ai_harness.txt
touch Data/portable_ai.txt        # omit for a stock/reference run
./Game.exe
cd ../../_AI-Study
python3 tools/check_scenarios.py scenarios.json \
  "../Reborn Yang/Reborn Yang/Data/ai_probe_results_portable.ndjson"
```

Remove `Data/ai_harness.txt` and `Data/portable_ai.txt` afterwards. Both were removed
at this handoff and a normal boot reaches the title path cleanly.

Unit tests: `ruby _AI-Study/tests/test_reborn_adapter.rb` (plus the existing
`test_portable_ai.rb`, `test_realidea_adapter.rb` — all green at 0.2.0).

## Run gauntlets in PARALLEL — this is the default, not an optimisation

**Any time you are about to run more than one roster, use the parallel runner.** Four
workers is ~4x, verified byte-identical to serial on 480 battles. Running a sweep
serially is the single easiest way to waste half an hour, and it has been done in this
study more than once *after* reading a note saying parallelism existed — so this is an
instruction, not a fact:

```bash
cd _AI-Study
bash tools/setup_gauntlet_workers.sh 4          # once per checkout; ~119 MB each
cat > /tmp/cfg.txt <<'EOF'
mode=gauntlet
schedule=normal_baseline
party_size=6
arms=normal_portable
EOF
bash tools/run_gauntlet_parallel.sh generated/reborn_6v6_v050 /tmp/cfg.txt \
     set_a set_b set_c set_d set_e set_f set_g
```

The config file must NOT contain a `teams=` line — the rosters are the arguments, and
results land at `<OUT_PREFIX>_<roster>.ndjson`. Each worker is a private game directory
under `.gauntlet-workers/w*` with Audio and Graphics as NTFS junctions; `Scripts/` is
re-synced from the master on every run, so a worker can never execute a stale
`Portable_AI.rb` after a rebuild — but you must still `cp generated/Portable_AI_Reborn.rb`
into the master first. `Game.exe` is a *Windows* process (~250 MB, ~0.7 core each), so
the ceiling is Windows free RAM, not WSL CPU; 4 is right on this machine.

Serial is correct for exactly two things: a single roster, and the probe
(`mode=probe`), which is one ~90-second run over the whole corpus.

## Traps for future agents

- **Reborn runs modern Ruby (mkxp-z)** — keyword arguments and `Float#round(n)` are
  fine here, unlike the Realidea (RGSS 1.8-era) injection. Don't copy that constraint
  across; don't copy modern syntax back into Realidea either.
- `pbTypeModNoMessages` neutral is **4** (two type slots ×2), not Realidea's 8, and
  returns **−1** for absorb abilities — treat ≤0 as immune. Scale conversions in the
  adapter (`switch_matchup` ×8, hazard rock damage /4) exist so the core sees
  Realidea-equivalent magnitudes; keep them in sync if you touch either.
- `pbRoughDamage` requires `ai.mondata` to be staged and consults `@swappredicted` and
  the Intense switch — never call it without `with_neutral_estimation`.
- The probe's stock records are roulette-sampled: Reborn picks randomly among top-window
  scores, so re-runs legitimately differ in `action` on tied vectors. Grade with
  `check_scenarios.py`; don't diff raw records and call it a regression.
- `chooseAction` loops over all four battlers itself. Do not try to call it per-index,
  and do not register for a battler whose `choices[i][0] != 0` — locked turns
  (Outrage/recharge) keep their prior choice, same trap as Realidea.
- **`PokeBattle_Battle#initialize` rewrites `obedient` on the left party** from the
  badge count (`PokeBattle_Battle.rb:525`), so anything the party builder set is gone
  by the time the battle starts. Any new harness that builds parties by hand must set
  it *after* construction, or the left seat quietly disobeys. Two more fields reset at
  moments a wrapper would not expect: `successStates` is cleared by `updateSkill` at
  the end of every `pbUseMove`, and `damagestate` is reset on several paths before
  `pbProcessMoveAgainstTarget` returns (a reset looks exactly like an immunity, since
  neutral `typemod` is 4).
- **The gauntlet's trainers run at `BESTSKILL` (100), in both Normal and Intense.**
  Trainer type 0's skill column is blank in `trainertypes.txt` and the compiler
  substitutes the base-money column, which is 100. Nothing in the harness sets it, and
  nothing looks like it sets it — check `Data/trainertypes.dat`, not the PBS text.
- **Runs parallelise ~4x with no code change**: `tools/setup_gauntlet_workers.sh` builds
  private game directories (Audio/Graphics as NTFS junctions, ~120 MB each) and
  `tools/run_gauntlet_parallel.sh` drives one roster per worker. Verified identical to
  serial on 480 battles. `Game.exe` is a Windows process (~250 MB, ~0.7 core each), so
  the limit is Windows free RAM, not the WSL VM.
- `Data/ai_probe_results.ndjson` is the archived reference basis — probe to a different
  `out=` filename, as the runs above do.

## The head-to-head gauntlet — built and run (2026-09-04)

`adapters/reborn/Portable_AI_Gauntlet.rb`, part of the installed bundle, invoked via
`Data/ai_harness.txt` with `mode=gauntlet` (optional `arms=` comma-list). Same fixture
teams, matchups and five seeds as Realidea's frozen gauntlet; field 0 pinned; 500-round
decision-on-time cap ($DEBUG path in the test loop); no items/megas.

Layout: the LEFT team is always Reborn's AI; the RIGHT team is the test seat — Reborn's
AI in the `*_reborn` calibration arms, the portable AI in the `*_portable` arms.
`$PORTABLE_AI_TRAINER` marks the right trainer because the test environment drives both
sides through the same odd-side AI path by physically swapping the battle's halves
(`switchTrainers`) — index parity points at both teams, one per call, so the portable
side is identified by trainer object, not by index. Intense arms set
`$game_switches[3000]` for the whole battle: Reborn gets its full cheat set (including
reading the portable side's already-registered choices — the same information flow real
Intense has against a player), while `with_neutral_estimation` keeps the portable side's
own snapshot fair.

### Results (160 battles, 0 errors, right-seat perspective)

| Arm | Right seat driven by | Wins | Rate |
|---|---|---:|---:|
| normal_reborn (calibration) | Reborn-Normal | 30/40 | 75.0% |
| normal_portable | **Portable 0.2.0** | 22/40 | 55.0% |
| intense_reborn (calibration) | Reborn-Intense | 25/40 | 62.5% |
| intense_portable | **Portable 0.2.0** | 26/40 | 65.0% |

The right-only frozen schedule is retained for comparison with Realidea, but it is not
a fair standalone strength estimate. Reborn-vs-Reborn calibration and the audit below
show a large positional effect. Within this schedule, same-seat paired outcomes were
2 better / 11 worse / 27 tied against Normal and 8 better / 7 worse / 25 tied against
Intense. The apparent Intense parity does not survive balancing both physical seats.

Artifacts: `generated/reborn_gauntlet_results.ndjson`,
`generated/reborn_gauntlet_summary.txt`. Reproduce with
`printf 'mode=gauntlet\nlog_decisions=false\n' > Data/ai_harness.txt` and a launch;
~160 battles in two ~8-minute halves if split with `arms=`.

### Balanced seat audit and home-and-away result

The original frozen schedule is intentionally comparable with Realidea, but it is not
balanced: only two team pairs occur in both directions, and it includes two one-way
doubles fixtures. `schedule=seat_audit` instead runs all 12 ordered, non-mirror singles
pairings of offense/balance/bulky/speed. Every team occupies each seat 15 times per arm,
using the same five seeds.

The audit also found and repaired a concrete `switchTrainers` defect:
`AI_MonData#index` remained attached to its old battler slot after the data objects were
swapped. The final native calibration is:

| Arm | Right wins | Left wins | Draws | Right rate |
|---|---:|---:|---:|---:|
| Reborn-Normal vs itself | 51 | 8 | 1 | 85.0% |
| Reborn-Intense vs itself | 40 | 20 | 0 | 66.7% |

An additional 100-seed identical-team control (Offense vs the same Offense) finished
72 right / 28 left. Initial move-score vectors were identical across perspectives, and
reversing command-selection order changed the result only to 71/29. A one-Pokémon
control tracked the effect to slot-coupled RNG/turn order: the right battler moved first
61/100 and won 62/100. Reborn's global RNG stream and player/opponent assumptions make
raw seat win rates unsuitable as strength measurements.

The corrected comparison therefore assigns Portable AI to each physical seat equally.
The measured side always chooses first, preserving Intense's authentic ability to read
the already-registered action regardless of which seat Portable occupies:

| Opponent | Portable right | Portable left | Combined |
|---|---:|---:|---:|
| Reborn-Normal | 34/60 | 10/60 | **44/120 (36.7%)** |
| Reborn-Intense | 34/60 | 5/60 | **39/120 (32.5%)** |

Naive two-sided binomial p-values are approximately 0.0045 (Normal) and 0.00016
(Intense), but those treat all battles as independent even though five seeds are reused
across matchups; they are descriptive, not final significance claims. By
Portable-piloted archetype, records were Normal:
balance 7/30, offense 10/30, bulky 21/30, speed 6/30; Intense: balance 10/30,
offense 8/30, bulky 17/30, speed 4/30.

Honest corrected summary: **Portable 0.2.0 is materially weaker than Reborn's native AI
in a seat- and team-balanced head-to-head: 36.7% against Normal and 32.5% against
Intense.** The earlier right-only Intense parity was a positional artifact.

Two paired Normal losses illustrate concrete policy gaps:

- **`bulky_vs_offense`, seed 130363:** both right-side AIs opened Garchomp with Swords
  Dance and lost it to Umbreon's boosted Foul Play. Reborn's replacement Magnezone used
  Thunder Wave once, then attacked. Portable used Thunder Wave on two consecutive turns
  against the same Umbreon, then attempted a low-HP switch that sacrificed Gengar; its
  offense was gone after four completed rounds. The original trace did not record
  status, so the first Thunder Wave may have missed; the confirmed gap is the poor
  emergency-switch valuation.
- **`balance_vs_speed`, seed 196613:** Reborn's Alakazam repeatedly attacked Skarmory,
  accepted the trade, then used Weavile/Crobat to finish in nine rounds. Portable
  recovered, switched Alakazam→Weavile→Alakazam on consecutive rounds, later
  ping-ponged Crobat and Weavile, and spent three rounds Roosting Crobat under Snorlax
  pressure before switching again. The loss is a commitment failure: excessive
  recovery and switch churn replaced productive damage.

Full command/state traces are archived as
`generated/trace_bulky_vs_offense_130363.ndjson` and
`generated/trace_balance_vs_speed_196613.ndjson`.

Two additional status-aware logs show where Portable can be stronger:

- **Both won — `balance_vs_bulky`, seed 130363:** Reborn's Umbreon alternated Foul
  Play with Moonlight/Protect and needed 26 rounds, eventually winning with Ferrothorn.
  Portable committed to Foul Play, removed Skarmory by round 6, used only two Moonlights
  against Snorlax, and swept in 10 completed rounds with all three Pokémon surviving.
- **Portable-only win — `offense_vs_balance`, seed 104729:** both Skarmory variants
  opened Brave Bird then Whirlwind. Portable placed Stealth Rock on round 3 before
  phazing again; Reborn used Whirlwind twice. Portable's Snorlax then committed to
  Crunch and survived on 44 HP, while Reborn selected a futile Rest in KO range and
  lost. Portable retained Snorlax and untouched Starmie.

These logs are `generated/trace_balance_vs_bulky_130363.ndjson` and
`generated/trace_offense_vs_balance_104729.ndjson`.

Artifacts: `generated/reborn_seat_audit_results.ndjson` and
`generated/reborn_seat_audit_summary.txt` contain native calibration;
`generated/reborn_home_away_portable_results.ndjson` and its summary contain the
balanced comparison. Reproduce the latter with `mode=gauntlet`,
`schedule=seat_audit`, and
`arms=normal_portable,normal_portable_left,intense_portable,intense_portable_left`.

### Six-Pokémon benchmark

A separate benchmark extended each fixture archetype from three deliberately ordered
Pokémon to six, while retaining the original lead trio. It used the same 12 ordered
singles matchups and five seeds. Native mirrors used 60 battles per difficulty;
Portable comparisons used both seats for 120 per difficulty, and a Portable mirror
used 60 more: 420 battles, 0 errors. Configure it with `party_size=6`; the default
remains 3.

| Portable comparison | Right seat | Left seat | Combined |
|---|---:|---:|---:|
| 3v3 vs Normal | 34/60 | 10/60 | **44/120 (36.7%)** |
| 6v6 vs Normal | 39/60 | 5/60 | **44/120 (36.7%)** |
| 3v3 vs Intense | 34/60 | 5/60 | **39/120 (32.5%)** |
| 6v6 vs Intense | 34/60 | 2/60 | **36/120 (30.0%)** |

Mirror calibration still shows the engine's positional effect:

| 6v6 mirror | Right wins | Left wins | Draws |
|---|---:|---:|---:|
| Reborn-Normal vs itself | 48 | 12 | 0 |
| Reborn-Intense vs itself | 54 | 6 | 0 |
| Portable vs itself | 42 | 18 | 0 |

The stable aggregates do not mean the formats are interchangeable. Against Normal,
40/120 paired battles changed winner (20 in each direction); against Intense, 37/120
changed (17 losses became wins, 20 wins became losses). Mean battle length rose from
about 13 turns in 3v3 to 28–31 turns in 6v6. Six-member play materially changes
individual battles but did not improve Portable's overall strength, and balancing
physical seats remains mandatory.

Compact artifact: `generated/reborn_6v6_summary.json`. The raw run is
`Reborn Yang/Reborn Yang/Data/ai_6v6_results.ndjson`.

### Fixed Normal baseline

Because every mirror calibration retained a large physical-seat effect, the next
comparison fixes Reborn-Normal on the left and measures only the right seat. It compares
Portable and Reborn-Intense against that same opponent, team schedule, five seeds, and
chooser order. Reborn's Intense switch is enabled only during the marked right trainer's
AI pass; the left baseline remains Normal. This is distinct from the earlier
`intense_reborn` mirror arm, which enabled Intense globally for both sides.

| Right-seat AI vs left Reborn-Normal | Wins | Rate | Mean turns |
|---|---:|---:|---:|
| Portable | 39/60 | **65.0%** | 29.9 |
| Reborn-Intense | 52/60 | **86.7%** | 30.9 |

Paired by matchup and seed, both won 31 battles, Intense alone won 21, and Portable
alone won 8; neither lost the same paired battle. The 29 disagreements are the useful
trace-analysis set. Full command/state traces are in
`generated/reborn_6v6_normal_baseline_set_a.ndjson` (archived from
`Reborn Yang/Reborn Yang/Data/ai_normal_baseline_results.ndjson`); compact counts are
`generated/reborn_6v6_normal_baseline_summary.json`.

### Roster sensitivity of the fixed-Normal baseline

The 65.0/86.7 result above was measured on a single hand-picked fixture of 24 Pokemon.
To separate "property of the AIs" from "property of those 24 mons", two alternate
rosters were generated and the identical baseline was rerun on each.

Rosters come from `tools/make_gauntlet_teams.py` into
`generated/gauntlet_teams_reborn.rb`, selected at run time with `teams=` (default
`set_a`). `set_a` is the original fixture, byte-identical, and is the control.
`set_b`/`set_c` are seeded draws (`DRAW_SEED = 20260904`) from curated per-archetype
pools, disjoint from `set_a` and from each other. `set_d`/`set_e` were added later from
enlarged pools under their own `DRAW_SEED_DE = 20260905`, drawn in a second stage that
consumes only the newly added candidates, so `set_b`/`set_c` still reproduce
byte-identically and every run recorded before they existed stays comparable. Pools
exclude legendaries (set_a
averages ~520 BST; a Mew/Jirachi/Latios draw would confound "different mons" with
"stronger mons") and any mon whose identity needs a non-slot-0 ability, because
`make_party` calls `setAbility(0)` — Azumarill would arrive with Thick Fat, not Huge
Power. Every species and move is checked against `PBS/PBS/` before emission; a typo
would otherwise surface as an exception minutes into a launch.

**The control reproduced exactly** — 39/60 and 52/60, mean turns 29.9 and 30.9 — so
roster selection is inert and the three runs are comparable.

| Roster | Portable | Intense | Gap | Portable mean turns |
|---|---:|---:|---:|---:|
| set_a (control) | 39/60 (65.0%) | 52/60 (86.7%) | 21.7 | 29.9 |
| set_b | 31/60 (51.7%) | 49/60 (81.7%) | 30.0 | 19.8 |
| set_c | 32/60 (53.3%) | 39/60 (65.0%) | 11.7 | 24.3 |
| **pooled** | **102/180 (56.7%)** | **140/180 (77.8%)** | **21.1** | — |

What survives and what does not:

- **The Portable/Intense gap survives.** Pooled over 180 battles per arm, Intense is
  ahead 77.8% to 56.7% (z = −4.27). set_a's 21.7-point gap is close to the pooled
  21.1, so the earlier headline was directionally right.
- **The absolute rates do not.** set_a is the friendliest roster in the study for
  *both* AIs. Intense's rate is significantly roster-dependent (86.7% on set_a vs
  65.0% on set_c, z = +2.77; set_b vs set_c, z = +2.06). Portable's spread
  (65.0/51.7/53.3) is directionally similar but not significant at n = 60 — per-set
  95% CIs are roughly ±12 points and all overlap. Do not quote a single-roster rate
  as Portable's strength.
- **The archetype ranking inverts, and this is the actionable finding.** Portable
  piloting *bulky* went 13/15 → 6/15 → 2/15 across the three rosters. Its apparent
  competence at bulky was an artifact of set_a's specific stall roster
  (Toxapex/Chansey/Umbreon/Ferrothorn), which largely plays itself; on rosters that
  ask a bulky team to actually make decisions it collapses. Offense moved the other
  way (10 → 12 → 13).

Pooled per-archetype, measured seat, 45 battles each:

| Archetype | Portable | Intense |
|---|---:|---:|
| offense | 35/45 (78%) | 40/45 (89%) |
| balance | 29/45 (64%) | 38/45 (84%) |
| bulky | **21/45 (47%)** | 29/45 (64%) |
| speed | **17/45 (38%)** | 33/45 (73%) |

Speed is Portable's genuinely worst archetype and the one result stable across all
three rosters (7/15, 4/15, 6/15). Bulky is the largest hidden weakness. Balance, which
the previous run flagged as a priority, is mid-table once the roster varies.

Mean battle length fell from ~30 turns on set_a to ~19–24 on the drawn rosters, so
set_a was also an unusually long-game fixture; any conclusion that depends on turn
count should be re-checked per roster.

Artifacts: `generated/reborn_6v6_normal_baseline_{set_a,set_b,set_c}.ndjson` (full
traces), matching `.json` summaries, and the cross-set table
`generated/reborn_6v6_normal_baseline_by_teamset.json`. Regenerate summaries with
`tools/summarize_baseline.py <ndjson...>`. Reproduce a run with:

```bash
cd "Reborn Yang/Reborn Yang"
printf 'mode=gauntlet\nschedule=normal_baseline\nparty_size=6\narms=normal_portable,intense_vs_normal\nteams=set_b\ntrace=true\nlog_decisions=false\n' > Data/ai_harness.txt
./Game.exe          # ~4 min for 120 battles
```

Two traps this run cost time on:

- Do **not** create `Data/portable_ai.txt` for these runs. `PortableAIReborn.requested?`
  falls back to that file, which would force the portable AI on during the
  `intense_vs_normal` arm and silently corrupt the comparison; the gauntlet sets
  `$PORTABLE_AI_ENABLED` per arm instead.
- Archive `Data/ai_normal_baseline_results.ndjson` into `generated/` immediately after
  each run. It is the only copy, git does not track it, and the next run overwrites it.

### Policy lessons for the next Portable version

Six high-divergence traces were inspected: two Intense-only wins
(`bulky_vs_speed`/196613, `offense_vs_bulky`/262147), two Portable-only wins
(`balance_vs_speed`/104729, `offense_vs_bulky`/130363), and two shared wins
(`bulky_vs_offense`/104729, `balance_vs_bulky`/155921). No paired run had the same
complete measured-side move sequence; the longest common prefix was four commands.
Treat the findings below as candidate policies to scenario-test, not proof from six
battles.

What is worth learning from Intense:

1. **Explicit setup-threat response.** Intense successfully answered boosted Scizor
   with Toxapex's Haze, then Recover/Scald, and used Chansey to stop Volcarona. Portable
   sometimes continued Scald while boosts accumulated. When positive foe stages become
   dangerous, prioritize a credible KO, Haze/phazing, or a safe counter-switch over
   ordinary pressure.
2. **Switch for the next turn, not merely this hit.** Score both expected incoming
   damage and the candidate's ability to threaten or stabilize on the following turn.
   Portable's repeated Jolteon/Aerodactyl entries into Hippowdon's
   Earthquake/Roar/Slack Off cycle were safe-looking one-turn choices with no path to
   progress.
3. **Switch hysteresis and loop memory.** Penalize returning to a recently abandoned
   matchup unless HP, status, boosts, hazards, or available party members changed
   materially. This should break Jolteon↔Aerodactyl and Crobat↔Jolteon cycles without
   banning legitimate pivots.
4. **Coordinate defensive actions as short plans.** Haze, recovery, and attack should
   be evaluated as a sequence: remove the boost, recover only if the next hit is
   survivable and the net gain is useful, then resume pressure. Isolated per-turn
   scoring misses this relationship.
5. **Accept productive sacrifices.** Intense's fast `bulky_vs_speed` win allowed
   Infernape and Alakazam to deal decisive damage before fainting. Portable should not
   spend several turns preserving a weak Pokémon when one committed attack creates a
   clearly superior position.
6. **Detect lack of progress.** Track recent damage, KOs, status, stage changes,
   hazards, and matchup changes. After several low-progress turns, penalize the current
   action/matchup and force reevaluation.

Do **not** copy Intense wholesale. Its losing/shared-win traces exposed repeated
Stealth Rock after hazards were already active, Swords Dance/Roost into repeated Haze,
late recovery in KO range, and its own pivot loops. Portable was strongest when it
converted a favorable matchup into sustained damage. Preserve its hard rejection of
redundant hazards and avoid optimizing battle length at the expense of win rate.

Recommended implementation order: setup-threat response; switch hysteresis; two-turn
switch destination value; recovery/tempo gating; then a general progress detector.
Add focused scenarios for each rule before rerunning the fixed-Normal baseline. Faint
replacements use the shared engine policy, so trace reviews must distinguish explicit
`choice=2` switches from automatic post-KO send-ins.

### Measured behaviour across all 360 traced battles (supersedes the ordering above)

The six lessons were induced from six hand-read set_a battles. `tools/compare_arms.py`
recomputes them over every traced battle in all three rosters. Only explicit
`choice==2` switches count; index 1 is the measured seat.

| Pooled, 180 battles/arm | Portable | Intense |
|---|---:|---:|
| win rate | 56.7% | 77.8% |
| **switch rate (of all turns)** | **25.2%** | **5.2%** |
| A→B→A returns per battle | 1.07 | 0.09 |
| explicit switches below 30% HP, per battle | 2.09 | **0.00** |
| mean HP lost on the switch-in turn | 39.7% | 25.2% |
| switch *into* a mon last seen under 40% HP | 15.9% of switches | 3.5% |
| recover, then switch that mon out within 2 turns | 18.0% of recoveries | 8.4% |
| turns removing no HP, status or stage | 62.0% | 55.4% |
| foe HP removed per turn | 12.3% | 14.2% |

**One defect dominates: Portable switches roughly five times as often as Intense, and
its switches are worse.** The rate is stable across rosters (21.0/28.7/27.4 vs
6.0/5.2/3.8), so it is a property of the AI, not of a fixture. Intense never once
switched a battler out below 30% HP in 180 battles; Portable did so about twice per
battle.

This reprioritizes lesson 1. Intense does **not** answer a boosted foe by phazing —
with the foe at ≥ +2 total stages it attacks 83.9% of the time and phazes 6.7%.
Portable attacks 54.4% and *switches 29.9%* (Intense: 3.1%). The gap is not missing
Haze logic; it is flinching. Lessons 2, 3 and 5 are three faces of this same defect
and should be treated as one work item.

Not a "losing positions cause switching" artifact. Restricted to the first six turns,
before the position is decided, Portable switches 32.7% in battles it goes on to lose
versus 25.3% in battles it wins (z = −2.66); paired, 31.1% in the 52 battles Intense
won and it lost versus 24.4% in the 88 both won. Intense runs the other way (7.5% in
wins, 5.8% in losses), so early switching is specifically Portable's failure mode.

The cost concentrates exactly where the archetype needs commitment:

| Measured archetype | Portable rate | Portable switch % | Intense switch % | Portable dmg/turn | Intense dmg/turn |
|---|---:|---:|---:|---:|---:|
| offense | 77.8% | 25.8% | 4.1% | 12.6% | 14.8% |
| balance | 64.4% | 20.2% | 5.0% | 12.9% | 12.9% |
| bulky | 46.7% | 21.9% | 7.2% | 11.9% | 11.9% |
| speed | **37.8%** | **33.7%** | 3.4% | 11.7% | **18.5%** |

On speed the mean switch-in damage is nearly identical (44.4% vs 44.7%) — Portable is
not picking worse destinations there, it is simply switching frail mons far too often,
and Intense converts the same team into 18.5% damage per turn against Portable's 11.7%.

`set_a bulky_vs_speed` seed 104729 is the archetypal case (both traces in the archived
ndjson). Intense switched once on turn 0, then attacked nearly every turn, spending
Infernape from 61% → 11% → 2% and Crobat to 16% to remove Umbreon and break Hippowdon;
it won in 19 turns with 2 alive. Portable switched six times in eleven turns, cycling
Crobat at 46%, Weavile at 30% and Jolteon at 52% without committing, Roosted Aerodactyl
to 40% and then immediately switched it out, moved Hippowdon only 100% → 60% in eleven
turns, and lost in 57 turns with nothing alive.

Revised implementation order:

1. **Suppress switching.** Raise the bar a switch must clear: require a concrete
   expected gain over attacking, hard-block switching a battler out below ~30% HP
   absent a specific reason, and hard-block switching *in* a party member already
   below ~40%. This single change addresses lessons 2, 3 and 5 and is where the win
   rate is.
2. **Do not treat a boosted foe as a reason to flee.** See "How Intense actually
   handles a boosted foe" below — the fix is structural, not a new heuristic.
3. **Gate recovery on staying in** — 18% of Portable's recoveries were thrown away by
   switching out within two turns.
4. Progress detector (lesson 6) — supported, but worth less than the above: the stall
   gap is 62.0% vs 55.4%, far smaller than the switch gap.

Reproduce with `python3 tools/compare_arms.py generated/reborn_6v6_normal_baseline_set_*.ndjson --by-archetype`.

### How Intense actually handles a boosted foe

Read from `Scripts/PokeBattle_AI_2.rb`, not inferred from traces. The answer is that
**it does not handle it in the switch decision at all**, and that is the whole trick.

Switch rate against foe boost level is flat for Intense and escalates for Portable:

| Foe positive stages | Portable switch % | Intense switch % |
|---|---:|---:|
| 0 | 25.0% (1079/4323) | 5.3% (219/4157) |
| +2/+3 | **34.7%** (74/213) | 2.5% (5/201) |
| +4 or more | 14.7% (10/68) | 9.1% (2/22) |

The two AIs make the switch decision in structurally different ways:

- **Non-Intense Reborn** (`PokeBattle_AI_2.rb:1576`) compares scores, like Portable:
  `shouldswitchscore > maxmovescore && switchscore.max > 100`.
- **Intense** (`:1571-1575`) replaces that with a boolean gate:
  `next if shouldSwitchintense?`. The switch branch is *skipped entirely* when the gate
  is false, so it falls through to attacking. Switching is never scored against moves.

`shouldSwitchintense?` (`:13713`) builds its score only from affirmative escape
reasons: Leech Seed, Curse, Perish Song, Attract, Confusion, Yawn, Salt Cure, Toxic
counter, and its **own** debuffs. All 34 `.stages[` reads in the function are
`@attacker.stages[` — the opponent's stages are never read. A boosted foe is simply
not on the list of reasons to leave.

Foe boosts instead re-rank *moves*, in ~104 sites. Representative:

- **Sweep Disrupt** (`:1199`): if the foe has positive Atk/SpA/Spe *and* a
  sweep-enabling ability or setup move (Moxie, Speed Boost, Contrary, Unburden,
  Quiver/Dragon Dance, Shell Smash…), multiply the competing score by 0.6.
- **boostercount** (`:3046`): if the foe has boosted defences, raise the score of
  high-crit moves by `1.05**boosts` — crits ignore the foe's defensive stages.
- (`:6095`) it also refuses to set up *itself* into a foe holding Haze/Clear
  Smog/Topsy-Turvy (×0.2).

So Intense's answer is "change which attack you throw", never "leave". Its 6.7% phaze
rate under boosts is a mild elevation over its 1.7% baseline, not the main response.

**Portable does not have an explicit flee-on-boost rule either — the behaviour is
emergent, and that is the actual bug.** `Core.score_switch` (`portable_ai/core.rb:262`)
reads only its own `negative_stage_total`, same as Reborn. The escalation comes from
scale mismatch: `switch_matchup` (`adapters/reborn/Portable_AI_Adapter.rb:445`) is pure
type effectiveness of the candidate's damaging moves against the current foe, `×8`,
and the switch `base_score` is `20 + hp_pct*0.35 - hazard`. Both are essentially
*situation-blind constants*. Move scores, by contrast, degrade sharply when a boosted
foe makes every attack look bad — and `no_effective_move` (+260) and
`weak_current_attacks` (+120) push switching further. Switching therefore wins by
default, not because anything judged the switch to be good.

That also explains two measured defects directly. `switch_matchup` never consults the
candidate's bulk, its HP beyond a 0.35 coefficient, or the damage it will take on
entry — so a 30%-HP mon with super-effective coverage outscores a healthy mon with
neutral coverage. Hence "switch into a mon last seen under 40% HP" at 15.9% of switches
and 39.7% mean switch-in damage, and hence speed being the worst archetype: frail fast
mons have excellent type coverage and keep winning the switch bid, then die.

Note the sharpest correction to lesson 1: **Portable already has the phazing rule that
lesson recommended adding** — `core.rb:168-176` scores `force_switch` moves as
`foe_hazard_layers*15 + target_positive_stages*25`. Set_a rosters carry Whirlwind, Roar
and Haze. The rule fires and is simply outbid by the switch score. Adding more
setup-threat heuristics will not help until switching stops competing on a blind scale.

Concrete fix implied: make switching clear a bar rather than win a comparison — either
port Intense's gate shape (require an affirmative escape reason), or make
`switch_matchup` situation-aware (expected incoming damage and survival on entry, not
just the type chart). Prefer the first; it is smaller and it is the design that
measured 77.8%.

### Switch gate implemented and measured (0.3.0)

`Core.score_switch` now gates voluntary switching on an affirmative escape reason
instead of letting it win a score comparison — the shape of Intense's
`next if shouldSwitchintense?`. Config key `switch_gate` (default true); set false to
restore 0.2.0 behaviour for A/B runs. Gate-opening reasons are in
`SWITCH_ESCAPE_REASONS`; forced switches (Perish Song) bypass it, and `trapped` still
hard-rejects.

**The first attempt was a null, and the reason is the useful part.** Including
`escape_lethal_threat` in the reason list changed almost nothing: 102/180 → 102/180,
switch rate 25.2% → 23.3%, and switches-below-30%-HP unchanged at exactly 2.09/battle.
`threatened_lethal?` is `incoming_damage_pct >= hp_pct`, which is true for nearly any
weakened battler, so it licensed precisely the switches the gate existed to stop.
(Artifacts kept as `generated/reborn_6v6_normal_baseline_gate_set_*.ndjson`.)

Removing it outright then failed the scenario `switch_out_vs_fresh_ohko_counter` — a
**full-HP** Garchomp facing Lapras, which is a legitimate pivot. That failure located
the real distinction: `threatened_lethal?` conflates "this matchup OHKOs me" (a matchup
problem worth switching over) with "I am nearly dead so everything OHKOs me" (not a
matchup problem). The gate now opens on lethal threat only at or above
`HEALTHY_PIVOT_HP_PCT` (50%). Below that it remains a score bonus but cannot open the
gate alone — matching Intense, which subtracts 100 from the switch score below 30% HP
for non-sweepers and spends the weakened battler attacking.

Scenario corpus: **169/169**, same as 0.2.0 (23 of the 126 scenarios involve switching).

| Pooled, 180 battles | 0.2.0 | 0.3.0 | Intense |
|---|---:|---:|---:|
| **wins** | 102 (56.7%) | **116 (64.4%)** | 139 (77.2%) |
| switch rate | 25.2% | **10.5%** | 5.2% |
| A→B→A returns/battle | 1.07 | 0.28 | 0.09 |
| switches below 30% HP/battle | 2.09 | 0.13 | 0.00 |
| switch-in damage | 39.7% | 32.9% | 25.2% |
| stall turns | 62.0% | 56.8% | 55.3% |
| foe HP removed/turn | 12.3% | **14.8%** | 14.3% |

Every behavioural metric moved toward Intense, and damage per turn now matches it. The
gap to Intense narrowed from 21.1 to 12.8 points.

Per roster and per archetype (portable wins):

| Roster | 0.2.0 | 0.3.0 | | Archetype | 0.2.0 | 0.3.0 |
|---|---:|---:|---|---|---:|---:|
| set_a | 39/60 | 38/60 (−1) | | speed | 17/45 | **25/45 (+8)** |
| set_b | 31/60 | **40/60 (+9)** | | offense | 35/45 | **40/45 (+5)** |
| set_c | 32/60 | **38/60 (+6)** | | bulky | 21/45 | 23/45 (+2) |
| | | | | balance | 29/45 | 28/45 (−1) |

Two things worth noting. **Speed gained most (+8), exactly as the diagnosis predicted** —
it had the highest pre-fix switch rate (33.7%, now 14.0%) and its damage per turn rose
11.7% → 16.6%. Offense now ties Intense outright at 40/45. And **set_a, the fixture the
whole study was built on, showed nothing (−1)**; the entire gain is on the drawn
rosters. Had we only had set_a we would have concluded the fix does not work.

Honest read on significance: paired by (roster, matchup, seed), the fix gained 33
battles and lost 19. McNemar χ² = 3.25 (z = +1.94), just short of p < 0.05. The
behavioural change is unambiguous and the direction is consistent across two of three
rosters, but **the win-rate gain itself is marginal at n = 180** — it needs the 20–30
seeds follow-up before being quoted as established.

Reproduce: `teams=set_a|set_b|set_c` with `schedule=normal_baseline`, artifacts
`generated/reborn_6v6_normal_baseline_gate2_set_*.ndjson`.

Open anomaly: the `intense_vs_normal` control is Reborn-vs-Reborn and should be
unaffected by portable changes. set_b and set_c reproduced bit-identically across all
three builds, but set_a's `balance_vs_speed` seed 262147 flipped (win 57t → loss 46t)
in both gated builds. `$ai_log_data` is reset per battle in
`PokeBattle_TestEnvironment.rb`, so that is not the cause; something else carries
across battles in long games. It is 1/180 and does not affect any conclusion here, but
the intense arm is therefore not a perfect control.

### The fair-play ceiling: Intense's cheat set is worth nothing

The whole study has treated Reborn-Intense as the strong reference. It is not. Running
the `normal_reborn` arm on the same fixed-Normal schedule — Reborn-Normal in the right
seat against Reborn-Normal in the left, no cheats on either side — gives:

| Right-seat AI vs left Reborn-Normal, 180 battles | Wins | Rate |
|---|---:|---:|
| Reborn-Normal (fair) | 143/180 | **79.4%** |
| Reborn-Intense (full cheat set) | 139/180 | 77.2% |
| Portable 0.3.0 (fair) | 116/180 | 64.4% |
| Portable 0.2.0 (fair) | 102/180 | 56.7% |

Per roster the fair ceiling is 48/60, 49/60, 46/60 on set_a/set_b/set_c and 46/60,
50/60 on set_d/set_e — **239/300 (79.7%)** pooled over all five. The ceiling is far more
roster-stable than either AI's absolute rate, which is why it is the right target.

**Enabling Intense on the right seat does not help it** — 77.2% vs 79.4%, a difference
well inside noise but certainly not an advantage. The forced skill 100, opponent choice
reads, full-moveset `getAIMemory` and Sucker Punch prediction buy nothing here, and the
extra machinery they unlock plausibly costs a little: Intense is the only arm that sets
redundant hazards (0.16/battle) and it uses status moves most, which measures negative
for both arms (Intense 69.0% with vs 84.4% without).

Three consequences:

1. **The information-asymmetry caveat on this benchmark is void.** It was reasonable to
   worry that Portable was being measured against an opponent that reads its choices
   while its own snapshot is kept fair. That worry is now answered empirically: the
   cheat set confers no measurable edge, so Portable's deficit is policy quality, not
   handicap.
2. **The target is 79.4%, not 77.2%**, and it is a *fair* target. Portable 0.3.0 is
   15.0 points short of it, having closed 7.8 of the original 22.7.
3. **The six policy lessons were mined from the weaker of the two Reborn AIs.** They
   were induced from Intense traces; Reborn-Normal scores higher. Re-mine divergences
   against `normal_reborn` rather than `intense_vs_normal` from here on. This does not
   invalidate the switch-gate result — that was derived from a behavioural gap Intense
   and Normal both share (Normal's switch decision is the score comparison at
   `PokeBattle_AI_2.rb:1576`, but it still switches far less than 0.2.0 Portable did).

Note this is also a seat measurement: 79.4% is what the right seat is worth against an
identical opponent, so it is the correct ceiling for any right-seat AI on this schedule.

Artifacts: `generated/reborn_6v6_normal_baseline_fairceiling_set_*.ndjson`.

### What the logs ruled out

Negative results worth not re-deriving:

- **Hazards are not the gap.** Portable sets Stealth Rock/Spikes in 5.7% of battles
  where its team carries them; Intense in 43.8%. But Intense wins 69.6% when it sets
  them and 67.8% when it does not. No effect — do not build hazard logic on this
  evidence.
- **Status moves are not the gap.** Portable 3.5% of turns vs Intense 5.0%, but using
  status correlates with *lower* win rate for both arms (Portable 52.1% vs 72.5%;
  Intense 69.0% vs 84.4%). Same direction for both, so it reads as selection — you
  reach for Toxic when you cannot simply kill.
- **Switching is closed.** Portable's residual early switching no longer predicts
  losing (z = −1.54, versus −2.66 before the gate). Further tightening has no evidence
  behind it.
- **There is no "turn it goes wrong".** The first turn at which Portable's choice
  differs from Intense's is 1.07 in wins and 1.08 in losses — they diverge immediately
  regardless of outcome.

What the gate did to the exchange rate, with damage attributed across switches (the
naive per-turn version undercounts Portable, whose switch-in damage lands on a turn
where `party_slot` changes):

| | dealt/turn | taken/turn | net | survivors on win |
|---|---:|---:|---:|---:|
| Portable 0.2.0 | 20.37% | 16.72% | +3.65% | 3.76 |
| Portable 0.3.0 | 23.18% | 18.46% | **+4.73%** | 2.97 |
| Intense | 23.50% | 17.82% | +5.68% | 3.14 |

Portable now takes more damage and deals much more — the correct trade. Its wins also
got less lopsided (3.76 → 2.97 survivors): pre-fix it won blowouts and lost close games,
now it converts close ones. Losses got closer too — foe HP removed before dying rose
60.6% → 72.2%, with balance gaining most (57.0% → 75.2%).

### The shadow arm, and why decision-level diffing needed one (2026-09-05)

Two live arms are only comparable while they hold identical state, and they do not
hold it for long: across 60 paired `normal_reborn`/`normal_portable` battles the median
identical-state prefix is **2 turns** (max 6), because the two AIs disagree almost at
once — mean turn of first disagreement 0.74. Everything after that is a different
battle and cannot be read as a decision comparison. `tools/diff_battles.py` reports the
controlled prefix and refuses to blur the line, printing `*` on every row after the
split.

To get a real sample, `shadow_reborn` was added: Reborn-Normal plays the battle, and
each turn the portable planner is asked what it would do from the same position and the
answer is recorded without being registered (`PortableAIReborn.shadow?`, gate on
`$PORTABLE_AI_SHADOW`). This is only sound because the planner is side-effect free at
BESTSKILL — it draws from `BattleRNG` solely for difficulty noise, which is off when
deterministic, and `with_neutral_estimation` restores every host field it stages. The
validity check is built into the arm: **shadow_reborn returned 48/49/46 per roster,
identical to normal_reborn's 48/49/46**, so observation costs the battle nothing.

That yields 4318 controlled decision points instead of ~120.

    Reborn-Normal and Portable choose the same action 2524/4318 = 58.5%

**Disagreement does not mean error, and this must not be used as if it did.** The
per-battle disagreement rate is 39.3% in battles Reborn won and 39.5% in battles it
lost — no signal. Worse for the naive reading, `offense` is simultaneously the
*highest*-disagreement archetype (46.2%) and Portable's *best* one (40/45 = 88.9%).
Making Portable agree with Reborn more is not the objective; the shadow says where the
policies differ, not where one is wrong.

Where they differ, by class (1794 disagreements):

| Reborn-Normal did | Portable would | n | share |
|---|---|---:|---:|
| attack | attack (a **different** move) | 459 | 25.6% |
| attack | switch | 233 | 13.0% |
| attack | recover | 173 | 9.6% |
| recover | attack | 140 | 7.8% |
| attack | status | 88 | 4.9% |
| recover | switch | 78 | 4.3% |
| attack | setup | 76 | 4.2% |
| switch | switch (**different mon**) | 50 | 2.8% |

The single largest class is neither switching nor stalling: both AIs agree to attack
and pick a different move. Agreement is lowest when **the foe is below 25% HP (49.2%)**
— the finishing decision — and, after the 0.3.1 fix below, highest when the foe is
boosted (67.0%).

Caveat carried by the method: the shadow never moved, so it accumulated no portable
memory, and its `setup` choices therefore miss the repeated-setup penalty a live run
would apply. Everything else is exact.

### Boosted-foe switching: found, fixed, measured (0.3.1)

Measured over the 180 fair-baseline battles, Reborn-Normal switched **0 times out of
173** while the foe held >= +2 stages. Portable 0.3.0 took **49 of its 451** switches
there — 10.9% of its switching inside 5.8% of its turns, so a boost made it *more*
likely to leave.

The cause was self-inflicted by 0.3.0. A foe at +2 roughly doubles its output, so it
flips `threatened_lethal?` (`incoming_damage_pct >= hp_pct`) on without the matchup
having changed at all — and `HEALTHY_PIVOT_HP_PCT`, added in 0.3.0 to protect genuine
hard-counter pivots, then licensed the switch precisely while the battler was healthy.
That is the worst moment to leave: the switch-in eats a free boosted hit and the boost
is still there afterwards.

0.3.1 suppresses **only** the lethal-threat escape reason when the foe is at
`BOOST_SUPPRESSES_LETHAL_ESCAPE` (>= +2). `no_effective_move`, crushed stats, Yawn and
residual chip are untouched — those are facts about this battler that a foe's boosts did
not manufacture, and a boosted foe does not get to veto them. `battler_view` now carries
`positive_stages` because switch scoring, unlike a move action, has no scoring target to
read the foe's boosts from.

| vs a foe at >= +2 | 0.3.0 | 0.3.1 | Reborn-Normal |
|---|---:|---:|---:|
| attacks | 64.5% | 79.8% | 91.4% |
| switches | 19.5% | **2.5%** | 0.0% |
| share of all its switches taken there | 10.9% | **1.5%** | 0.0% |

Overall switch rate barely moved (10.5% -> 9.6%), confirming the change was surgical
rather than a general tightening.

| Right-seat AI vs left Reborn-Normal, 180 battles | Wins | Rate |
|---|---:|---:|
| Reborn-Normal (fair) | 143/180 | 79.4% |
| Portable 0.3.1 | 120/180 | **66.7%** |
| Portable 0.3.0 | 116/180 | 64.4% |
| Portable 0.2.0 | 102/180 | 56.7% |

0.3.1 alone is +4 (36 gained, 32 lost pairwise vs 0.3.0; McNemar z = 1.06) — the right
direction but not independently significant, which is expected from a change that
touches ~49 decisions out of 4300. The switch-gate programme **as a whole** is:
0.2.0 -> 0.3.1 is 36 gained / 18 lost, net +18, chi2 = 5.35, **z = 2.31, p ~ 0.021**.

Per archetype (each 45 battles): offense 40 (88.9%), balance 30 (66.7%), speed 26
(57.8%), bulky 24 (53.3%). Bulky remains the weakest and did not move.

### Defensive switch scoring (0.3.2): mechanism general, win conversion set_a-only

`switch_matchup` scored a switch candidate purely on offence — the type effectiveness
of its damaging moves into the foe, x8. Nothing asked what the incoming Pokemon would
*eat*, which is why Portable's switch-ins took 33.5% of their HP on the entry turn
against Reborn-Normal's 26.5%.

`switch_incoming_risk` is the mirror: the foe's own types against the candidate's, same
units (neutral 32). Core weighs it symmetrically around neutral at `SWITCH_RISK_WEIGHT
= 1.0`, so resisting the foe is worth exactly what threatening it is worth rather than a
guessed ratio. It is scored off the foe's **types, not its moveset**, which keeps it
inside the fair-information contract — a player can see the opposing species and infer
its STAB without having been shown its moves. It only ever chooses *who* goes in; it
never argues for or against leaving, and it no-ops when the field is absent (pinned by
`test_switch_risk_is_ignored_when_the_adapter_omits_it`, so older adapters and forced
switches score exactly as before).

Switch-in damage fell on **every one of the five rosters**, and oscillation on four:

| | set_a | set_b | set_c | set_d | set_e |
|---|---:|---:|---:|---:|---:|
| switch-in damage 0.3.1 -> 0.3.2 | 31.7% -> 30.0% | 37.1% -> **33.3%** | 32.5% -> 29.1% | 33.6% -> **27.5%** | 36.6% -> 35.8% |
| oscillations/battle | 0.28 -> 0.17 | 0.20 -> 0.15 | 0.28 -> **0.10** | 0.08 -> 0.15 | 0.13 -> 0.12 |
| wins gained | **+10** | +0 | +1 | **−1** | +0 |

On set_a/set_b/set_c oscillation landed at Reborn-Normal's level (0.14 vs 0.12) —
picking a survivable switch-in stops the flip-flopping, as expected. set_d was already
below that (0.08) and rose to 0.15, still at parity.

**The win conversion was set_a-only on the first three rosters, and two fresh rosters
confirm it.** Across set_a/b/c the change was +11 (11 gained / 1 lost on set_a; 9 gained
/ 8 lost across set_b and set_c), McNemar z = 1.86, p = 0.063 — suggestive but short of
significance, and roster variance was the larger term. So `set_d`/`set_e` were drawn and
0.3.1 and 0.3.2 rerun on both. They settle it:

| paired, `normal_portable` | 0.3.1 | 0.3.2 | net |
|---|---:|---:|---|
| set_d | 34/60 | 33/60 | −1 |
| set_e | 46/60 | 46/60 | +0 |
| **set_d + set_e (120 battles)** | **80/120** | **79/120** | **−1** — 3 gained, 4 lost, p = 1.00 |
| **pooled set_a–set_e (300 battles)** | **200/300** | **210/300** | **+10** — 23 gained, 13 lost, chi2 = 2.25, z = 1.50, **p = 0.134** |

Two new rosters, 120 paired battles, seven discordant pairs, net zero. And `set_d` is
the sharpest case in the study: its switch-in damage fell 6.1 points, the **largest**
mechanical improvement any roster showed, and it won one battle *fewer*. The chain
"less switch-in damage -> more wins" breaks at the second link. Record 0.3.2 as **a
mechanism that works and a win rate that does not move**; its entire +10 is one roster,
and per archetype over the two new rosters it is flat everywhere (balance −1, bulky +1,
offense +0, speed −1).

Keep the change anyway — it is strictly better play by its own metric, it is bounded,
it reads no new information and draws no extra RNG. What it is not is evidence that
entry-turn survival is the binding constraint: on four of five rosters something else
is.

`switch_risk_weight=` in `Data/ai_harness.txt` overrides that core config key for a
whole run, so this A/B is two runs rather than two builds, and `switch_risk_weight=0`
is 0.3.1's policy exactly. That equivalence is verified, not assumed: a control run of
`switch_risk_weight=0` on set_a reproduced the recorded 0.3.1 result **battle for
battle** — all 60 identical in outcome and turn count, 41/60 — archived as
`generated/reborn_6v6_riskweight0_control_set_a.ndjson`. The set_d/set_e 0.3.1 column
above was produced by the knob on that basis. Artifacts:
`generated/reborn_6v6_{v031,v032}_set_{d,e}.ndjson`,
`generated/reborn_6v6_normal_baseline_fairceiling_set_{d,e}.ndjson`; reproduce the
comparison with `tools/compare_versions.py --before 'generated/reborn_6v6_v031_set_*.ndjson'
--after 'generated/reborn_6v6_v032_set_*.ndjson'`.

Cumulatively, though, the three switch fixes are solid:

| Right-seat AI vs left Reborn-Normal, 180 battles | Wins | Rate |
|---|---:|---:|
| Reborn-Normal (fair) | 143/180 | 79.4% |
| Portable 0.3.2 | 131/180 | **72.8%** |
| Portable 0.3.1 | 120/180 | 66.7% |
| Portable 0.3.0 | 116/180 | 64.4% |
| Portable 0.2.0 | 102/180 | 56.7% |

0.2.0 -> 0.3.2 is 42 gained / 13 lost, net **+29**, chi2 = 14.25, **z = 3.78,
p = 0.0002**. That table is set_a/set_b/set_c only — 0.2.0 and 0.3.0 were never run on
set_d/set_e — and about a third of the +29 is 0.3.2's set_a windfall, so read it as the
switch-gate *programme's* result, not as 0.3.2's.

Measured on all five rosters, 0.3.2 is 210/300 (70.0%) against a fair ceiling of 239/300
(79.7%): a **9.7-point** gap, not the 6.6 the three-roster set showed, with 56 battles
Reborn wins that Portable does not against 27 the other way (chi2 = 9.45, z = 3.07).
set_a is the only roster where Portable is *ahead* of the fair ceiling (51 vs 48); on
set_d it is 13 battles behind (33 vs 46). **Quote 9.7.**

### Two dead ends closed on the way

- **Stall loops are not the gap.** One vivid set_a battle (`balance_vs_bulky`/104729)
  has Portable's Umbreon spend nine straight turns on Foul Play into a roosting
  Skarmory — the worst possible move into that wall, since Foul Play uses the target's
  Attack (80) against its Defense (140) — while Reborn pivoted to Chansey and used
  Seismic Toss, whose fixed damage ignores Defense. Measured at scale it is not the
  pattern: counting runs of >= 3 repeats that make no **net** progress, Portable loops
  *less* than Reborn (0.14 vs 0.21 per battle, 2.3% vs 3.2% of turns) and still loses.
  Reborn's repetitions are deliberate stalls the metric mislabels.
- The first version of that metric was itself wrong and is worth remembering: it tested
  per-turn damage, so a wall that roosts back more than it takes scored as "progress"
  and broke the run — the exact case it was written to catch. Judge repetition on net
  HP across the whole run, not per turn.

### Follow-ups this run motivates

1. ~~**Confirm or kill 0.3.2 on more rosters.**~~ **Done, and killed as a win claim.**
   `set_d`/`set_e` were drawn and 0.3.1/0.3.2 rerun on both: net −1 over 120 paired
   battles, pooled p = 0.134 (above). The transferable lesson is the method — a +11
   concentrated on one of three rosters is a roster artifact until fresh rosters say
   otherwise, and drawing two more rosters costs ~10 minutes of runs against a claim
   that would otherwise have been quoted for the rest of the study.
2. **Bulky is the weakest archetype** and stayed weakest as the roster count grew: at
   0.3.2 over all five rosters it is 38/75 (50.7%), against offense 66/75 (88.0%),
   speed 55/75 (73.3%) and balance 51/75 (68.0%). It barely moved across the three
   switch fixes (21 -> 23 -> 24 -> 25 per 45 on set_a/b/c). Switching, hazards, status
   and stall loops are all ruled out for bulky, so diagnose it fresh — a shadow run
   filtered to bulky is the tool. This is now the largest known deficit.
3. **Move selection inside an agreed attack** is the largest shadow disagreement class
   (459 turns, 25.6%), and agreement is lowest with the **foe below 25% HP** (49.2%) —
   the finishing decision. Neither has a mechanism yet. Note `dmg/t` is already at parity
   (15.1% vs Reborn's 15.2%), so the loss is not throughput but which of its own mons
   Portable spends.
4. Do **not** treat shadow disagreement as error. It does not predict outcome (39.3% in
   won battles, 39.5% in lost), and the highest-disagreement archetype is the
   best-performing one. Use it to locate candidate mechanisms, then A/B them live.
5. `SWITCH_RISK_WEIGHT = 1.0` was chosen for symmetry with the offensive term, not
   tuned. The sweep was made conditional on 0.3.2 replicating; it did not, so sweeping
   now would fit a knob to an effect indistinguishable from zero on four of five
   rosters — it can only find set_a noise. Revisit only if a later change makes
   entry-turn survival matter for outcomes; `switch_risk_weight=` then makes it a
   one-line run per point.
2. Implement and scenario-test the policy lessons above, then rerun the fixed-Normal
   baseline before increasing sample size.
3. Increase to 20–30 seeds before treating either format's exact rate as stable.
   Roster variance is now known to be at least as large as seed variance, so prefer
   spending the next battles on more rosters over more seeds on one roster. Five
   rosters now exist; `set_f`+ is another pool enlargement plus a new `DRAW_SEED_DE`.
4. A with-fields arm (explicitly unfair to the portable side) to quantify what the
   missing field model costs.
5. Re-derive the six policy lessons on a non-`set_a` roster. They were induced from
   six set_a traces, and set_a is now known to be the outlier fixture — in particular
   the Hippowdon/Toxapex stall dynamics that motivated the Haze and switch-loop rules
   may not generalize.

### Move policy implemented and measured (0.4.0)

Four of the five rules `PORTABLE-AI-DIAGNOSIS.md` proposed are in as **0.4.0**, each
behind its own config key so any one is a one-line A/B (`heal_gate`, `accuracy_weight`,
`priority_gate`, `self_cost` in `Data/ai_harness.txt`). The fifth, the wall gate, was
**dropped before implementation** — its evidence inverted on inspection (that document's
section 4). New evidence the core reads: an `accuracy` field per move action
(`pbRoughAccuracy`) and the actor's own speed order (`faster`, Reborn's strict-`<`
convention, Trick Room inverted).

**Control first.** With all four keys off, set_a reproduces 0.3.2 battle-for-battle:
51/60, gained 0, lost 0. Every difference below is the rules, not the refactor.

Pooled over five rosters, 300 paired battles, fixed-Normal baseline:

| | 0.3.2 | 0.4.0 | fair ceiling |
|---|---:|---:|---:|
| wins | 210/300 (70.0%) | **219/300 (73.0%)** | 239/300 (79.7%) |
| gap to ceiling | 29 battles | **20 battles** | — |

gained 29, lost 20, net **+9**; McNemar chi2 = 1.31, **p = 0.25 — not significant**.

| archetype | 0.3.2 | 0.4.0 | delta | | roster | 0.3.2 | 0.4.0 | delta |
|---|---:|---:|---:|---|---|---:|---:|---:|
| balance | 51 | 59 | **+8** | | set_a | 51 | 50 | −1 |
| offense | 66 | 70 | +4 | | set_b | 41 | 41 | +0 |
| speed | 55 | 55 | +0 | | set_c | 39 | 40 | +1 |
| bulky | 38 | 35 | **−3** | | set_d | 33 | 37 | +4 |
| | | | | | set_e | 46 | 51 | +5 |

Balance was the worst archetype in the study (the balance-vs-offense 9/25 cell) and it
moved most. Bulky went the other way. Set_a, the known outlier, again disagrees with the
other four — the same pattern 0.3.2 showed.

**The heal gate delivered its mechanism completely, and then some** (`policy_gaps.py
heal`):

| heals that were heal-deaths | Reborn-Normal | Portable 0.3.2 | **Portable 0.4.0** |
|---|---:|---:|---:|
| all recovery clicks | 13% | 25% | **7%** |
| clicked below 25% HP | 33% | 61% | **24%** |
| healer estimated slower | 18% | 39% | **9%** |

Portable now throws away recovery turns at half Reborn-Normal's rate, and the
slower-healer case is the best number in the table. (An earlier draft of this paragraph
said Reborn "never asks whether it moves first"; that is wrong — see the decision-log
section below. Reborn heals *pre-emptively* when slower and, once in KO range, heals
whenever the heal exits the range, speed or not. The 0.4.0 rule reverses that, and the
low death rate is partly the reversal refusing heals that would have landed.)

**Which rule carries the wins: only the heal gate, and weakly.** One-key ablations on
set_b + set_d (120 battles each, the rule turned off against full 0.4.0):

| rule off | wins | vs full 0.4.0 | gained / lost |
|---|---:|---:|---|
| `heal_gate` | 75/120 | **−3** | 6 / 3 |
| `accuracy_weight` | 78/120 | +0 | 1 / 1 |
| `priority_gate` | 79/120 | +1 | 4 / 5 |
| `self_cost` | 78/120 | +0 | 2 / 2 |

No contribution is distinguishable from zero at this sample size, and the honest reading
is that **accuracy and self-cost change which move is clicked without changing who wins,
and the priority gate may cost a battle**. They were adopted on Reborn-code fidelity and
on the 143 measured finishing disagreements, not on a win-rate effect — the corpus cards
(`accurate_ko_over_inaccurate_ko`, `no_self_drop_when_alternative_kills`,
`no_explosion_at_full_hp_with_alternative`, `priority_ko_when_slower_real`) show they do
what they say. Keeping them is a bet that correct finishing pays off at larger n; the
keys exist so that bet stays falsifiable.

**One rule is inert by construction.** `finish_instead_of_heal` (−200 when the foe has no
reserves and a KO is in hand) can never change a decision: any lethal move already scores
≥ 600 and any heal ≤ ~425. It is implemented for fidelity to Reborn's `×0.3` and traced,
but it decides nothing under the current score scale. Reborn's continuous
"% of the foe's *current* HP, capped at 110" scale — the deeper option §3 of the diagnosis
raises — is what would make it bite.

**Thresholds are damage-roll aware.** A −400 penalty fires only where the *minimum* roll
(85%) still kills, so the rule never punishes a heal that some roll would rescue; the
+150 bonus uses the point estimate. This was not cosmetic: at the estimate alone the rule
killed the `heal_at_low_hp` corpus card, and measuring that card is what exposed both the
threshold and a false claim in the diagnosis (see its §2 correction).

Tier 1 is clean on both arms over the enlarged 133-scenario corpus (seven new cards,
`CORPUS_V8`): **Reborn-Normal 179/179, Portable 0.4.0 179/179**.

**Instrumentation added with this version**, because the retracted wall rule was a
reading failure and not a reasoning one:

- Gauntlet mode honours `log_decisions=true` (it forced `$INTERNAL = false`, so Reborn's
  own score vectors never reached `debuglog.txt` in *any* gauntlet run, whatever the
  config said). Each battle writes a `=== <id> seed <seed> arm <arm> ===` header so
  debuglog lines join back to the ndjson. Off by default; the file grows fast.
- `portable_trace` stores the top 5 candidates with their `reasons` per turn under
  `trace=true`, not just the chosen action. `policy_gaps.py leave`'s 226 "unattributed"
  turns exist only because that was missing.

### Decision-log run: what the "certain death" rules actually see (2026-09-05)

The two 0.4.0 instrumentation pieces were used for the first time on `set_c`, the
roster where bulky lost most (3 lost / 1 gained). One `normal_portable` run with
`trace=true log_decisions=true`, plus two adapter-only trace fields added for it
(`view.incoming_by_move`, the estimate for *every* foe move, and `view.faster`/
`hp_pct`/`incoming_damage_pct`). Core untouched; the run reproduces the archived 0.4.0
set_c outcomes 60/60. Files: `generated/reborn_6v6_v040log_set_c.ndjson`,
`generated/debuglog_v040log_set_c.txt`; tools: `tools/debuglog_join.py` (splits the
log by the `=== id seed arm ===` headers and `***Round N***` banners; Round N is
turncount N−1) and `tools/threat_audit.py`.

**Three things the log taught about itself first.** The test environment never loads
message strings, so every name in `debuglog.txt` is blank — species and moves survive
only as `spc:N` / `mv:N` ids, `[Prefer ]` is empty, and there are no per-hit damage
lines; actual damage has to come from the trace's `round_end` HP. Second, the
per-battler scoring blocks with numbers are Reborn scoring **Portable's** Pokémon (an
incidental shadow), while Reborn's own battler gets a blank block — and that
incidental shadow is not trustworthy: it scores Roost 51 at 100% HP where
`recovercode` returns 0 above 80%. A real shadow needs `arms=shadow_reborn`. Third,
the file rotates itself at 10 MB on every `PBDebug.log` call, mid-run; one roster
writes ~3.7 MB, so chunk by `seeds=` beyond two rosters.

**The damage estimator is not the problem.** For foe moves that actually executed and
landed on an awake target, actual damage ÷ Portable's per-move estimate has median
0.93 with quartiles 0.87–1.00 — the engine's 85–100% roll band. Reborn's own
"Expected Damage taken" for the same battler agrees with Portable's estimate (median
ratio 1.03). What the estimate cannot know is whether the move *happens*: a quarter
of executed damaging moves did zero (misses, Protect, Sucker Punch failing, immunity).

**The false positives have two causes the predicate ignores.** `certain_lethal_threat?`
fires when the foe's *highest-estimate* move kills at the minimum roll. On the turns it
refused a heal (`heal_cannot_resolve`) or stripped a KO (`ko_never_lands`):

| firing, set_c | died that turn | survived | rule right |
|---|---:|---:|---:|
| refused heal, threat move 100%-accurate **and** foe awake | 23 | 4 | 85% |
| refused heal, threat move <100% accurate **or** foe asleep/frozen | 7 | 18 | 28% |
| KO stripped, 100%-accurate and awake | 26 | 4 | 87% |
| KO stripped, <100% or asleep/frozen | 5 | 8 | 38% |

Eight of the survivals were Amoonguss or Mantine refusing Synthesis/Roost while the
foe *slept* (Spore) — the threat model has no status term at all — and Stone Edge,
Hurricane and Rock Slide misses supplied most of the rest. Both are cheap to test for:
the sleeping/frozen foe from the target view's `status`, the move's accuracy from the
per-move map (the adapter already exports `accuracy` for the actor's own moves).

**What this does and does not say about the bulky decline.** Where the actor survived
a refused heal, it also KO'd the foe 7 times out of 22 — the attack was the better
click there, not the heal — so the fix is narrowing the certainty, not removing the
rule. Reborn's shadow scoring of Portable's low-HP turns agreed with *attacking* on 33
of the 36 turns Portable attacked at ≤50% HP and died, so "should have healed" is
not the reference's reading of those turns either. The paired effect of the narrowed
predicate is still unmeasured; it is the obvious next A/B: `certain_lethal_threat?`
requires the threatening move at 100% accuracy and a foe that is awake, else fall
through to the soft branch (`heal_saves_battler`), five rosters, McNemar as usual.

### Strict threat (0.4.1): the A/B the log asked for — null on wins

The predicate was narrowed as recommended: under `strict_threat` (new key, default on)
the −400 rules read `certain_incoming_damage_pct`, the largest hit from a foe move the
engine rates 100% accurate while the foe is awake (asleep with sleep left to serve, or
frozen, contributes nothing). The adapter computes it from the per-move map already in
the trace; the loose maximum still feeds the soft rules. `strict_threat=false`
in `Data/ai_harness.txt` is 0.4.0.

Five rosters, fixed-Normal, paired against 0.4.0:

| | 0.4.0 | 0.4.1 | 0.3.2 | ceiling |
|---|---:|---:|---:|---:|
| wins / 300 | 219 | **217** | 210 | 239 |

Against 0.4.0: gained 1, lost 3, McNemar p = 0.62. Against 0.3.2: +7, p = 0.38. Bulky
unchanged at 35. Only 33 of the 300 battles contain a single different Portable
decision, and they split 13 win/win, 15 loss/loss, 3 lost, 1 gained.

What actually moved: `heal_cannot_resolve` fired on 312 turns instead of 361,
`ko_never_lands` was clicked 172 times instead of 198, `heal_saves_battler` 307
instead of 272. Of the 20 heals 0.4.0 would have refused and 0.4.1 clicked while
slower, 8 survived and 12 died — and the 12 are the inaccurate lethal move *landing*
(Stone Edge at 80% hits four times in five). That is the branch where nothing the
actor clicks resolves, so the deaths are not evidence against the heal; they are the
cost of a gamble the loose rule declined and the strict rule takes, and the paired
result says the gamble is worth about nothing either way.

Kept on, as a behavioural correction only (the same standing as 0.3.2's switch
scoring): refusing Synthesis against a Spore-slept foe is wrong on its face whatever
the win column says. Files: `generated/reborn_6v6_v041_set_{a..e}.ndjson`.

**Where this leaves the study.** Three consecutive versions have moved the heal and
finish rules toward Reborn's logic, each with a visible mechanism change and none
with a win effect the sample can see. The 20-battle gap to the ceiling is 14 bulky
battles, and neither switching (0.3.x) nor recovery timing (0.4.x) is where bulky
loses them. The next diagnosis should start from the bulky losses themselves — the
3 lost / 1 gained on set_c are traced with full candidate lists and threat views — and
ask what Reborn's bulky team does over a whole battle that Portable's does not,
rather than proposing another per-turn rule from aggregate rates.

### Per-move event log (2026-09-05) — and the left seat has been disobeying all along

The command trace records the *registered* choice and end-of-turn HP, so a miss, a
Protect, an immunity, a failed Sucker Punch and a blocked user were all
indistinguishable from "hit for nothing". The gauntlet now also records what the
engine executed, as a flat `events` list on each traced record (one entry per move
execution, each carrying its own `turn`; flat rather than per-turn because the test
loop breaks out of the round before `pbEndOfRoundPhase` once the battle is decided,
so a per-turn flush would drop the deciding turn). `tools/render_battle.py` prints
them under each turn's registered actions.

An event is `{turn, user, species, move, outcome, use_state, targets, hp_delta}`,
plus `status`/`status_count`/`flinch`/`confusion` when the user carried one into the
attempt. `move` is read back from `choice[2]` *after* the call, because the engine
substitutes it in place for a continuing multi-turn move, an Encore and an
Encore-forced Struggle. Each target carries `hp_lost` and a `hits` list —
`{damage, typemod, crit, substitute, endured}` per connecting hit.

**Nothing here re-derives a fail branch.** There are dozens, scattered through
Reborn's modified move code, and a copy of them would rot; every verdict is the
engine's own, read at the moment it is computed:

| signal | source | what it settles |
|---|---|---|
| `pbTryUseMove` → false | — | could not move at all (sleep, flinch, paralysis, confusion, Disable, Taunt, recharge, Truant) |
| `pbSuccessCheck` → false | — | did not connect |
| `pbAccuracyCheck` → false | scoped to the enclosing success check | specifically a miss |
| `successStates[i]` | `useState` 0/1/2 + `protected`, Reborn's Battle Arena bookkeeping | reached the attack section / the Protect family |
| `effects[Tantrum]` | `damage == -1` (Battler:5085), kept for Stomping Tantrum | the move's own effect failed |
| `damagestate` at `pbReduceHPDamage` | per hit | damage, effectiveness, crit, Sturdy/Sash |

Two traps found while building it, both of which produce silently wrong readings if
you sample at the obvious place. `updateSkill` **resets** `useState` and `protected`
at the end of every `pbUseMove` (`PokeBattle_Battle.rb:82`), so a wrapper reading them
on return sees 0 for every move ever played; the verdict has to be stashed as
`updateSkill` consumes it. And `damagestate` is reset on several paths before
`pbProcessMoveAgainstTarget` returns — a reset reads as `typemod` 0, which is
indistinguishable from an immunity because Reborn's neutral is **4**. Sampling per hit
inside `pbReduceHPDamage` (as this backlog item originally proposed) avoids both.

Two limits, both degrading toward a vaguer label and never toward a wrong "hit".
`useState` is only maintained on the targeted path, so a move that targets its own
side (Swords Dance, Roost, Stealth Rock) or is charging a two-turn attack is reported
`untargeted`, with its effect visible in the state trace's `stages` and in `hp_delta`.
And six move subclasses override `pbAccuracyCheck` (Struggle, Confusion, OHKO 0x070,
0x0A5, 0x157, 0x159), bypassing that hook; all either always hit or appear in no
gauntlet roster, and a miss they made would read as `no_connect`.

**What the log found on its first run.** The two turns the readouts could not
explain — set_c `speed_vs_bulky 196613` turn 1 (Swellow registers U-turn; nothing
lands, no switch happens) and `offense_vs_bulky 104729` turn 3 (Salamence registers
Dragon Dance and ends the turn asleep with a fresh counter of 4) — were neither a
side-swap defect nor a recorder defect. The executed move matched the registered move
on **all 326 events**. Both turns are `could_not_move`, and the cause is
`pbObedienceCheck?`:

> `PokeBattle_Battle#initialize` (`PokeBattle_Battle.rb:525`) overwrites `obedient` on
> every `@party1` member with `level <= LEVELCAPS[numbadges]`. The harness has no
> badges, `LEVELCAPS[0]` is 20, and the fixture teams are level 100 — so the entire
> **left** party was disobedient in every gauntlet battle ever run, however
> `make_party` had set the flag beforehand. The right seat is never
> `pbOwnedByPlayer?` and was exempt.

The Realidea gauntlet is not affected: it sets `battle.internalbattle = false`, and
`pbObedienceCheck?` gates on that. The Reborn gauntlet sets it `true`.

Salamence's "fresh sleep counter of 4" is `pbSleepSelf` — the disobedience nap. In a
10-battle sample before the fix, **41 of 42** `could_not_move` events were the left
seat, most with no status to explain them; the roll costs a disobedient level-100
mon its turn about 17% of the time, plus the follow-on turns lost to the nap.

`run_one` now restores `obedient = true` on both parties after construction, where
nothing resets it again. After the fix the same sample has 10 `could_not_move` events,
**all** explained by the user's own state (9 asleep, 1 confused), and the seat
asymmetry is gone.

**This invalidates the archived win counts.** LEFT is Reborn's AI in every default
arm, so the reference has been playing one turn in six with a hand tied — the 0.2.0
→ 0.4.1 gauntlet numbers, the seat audit's "large positional effect", and the fair
ceiling of 239 were all measured against a handicapped opponent, and the true gap to
Reborn-Normal is wider than any of them say. Nothing before this entry is safe to
compare against anything after it. Re-running the five 6v6 rosters on the fixed
harness is the next step, and it should be done before any further policy A/B.

### Corrected baseline (2026-09-05) — the reference is 52.7%, not 79.7%

Both arms re-run on the fixed harness, all five rosters, `schedule=normal_baseline`
(every ordered non-mirror pairing of the four archetypes) × 5 seeds, 6v6, 300 battles
per arm, 0 errors. Files: `generated/reborn_6v6_v041obey_set_{a..e}.ndjson`, both arms
in each file, traced with events.

| right seat | wins / 300 | | was (disobedient left) |
|---|---:|---|---:|
| Reborn-Normal (`normal_reborn`) | **158** (52.7%) | | 239 (79.7%) |
| Portable 0.4.1 (`normal_portable`) | **142** (47.3%) | | 217 (72.3%) |

Paired on the same 300 battles, Portable gained 36 and lost 52 against the reference:
**−16, McNemar p = 0.11**. Not significant at 300 battles — the honest statement is
that Portable 0.4.1 and Reborn-Normal are not clearly separated by this schedule, with
Portable the more likely of the two to be behind.

`normal_reborn` is Reborn's AI in *both* seats, so on an all-pairs schedule it must sit
at 50% by construction; 158/300 is z = 0.92 from that, and the schedule is balanced
within noise. **That also disposes of the seat audit's "large positional effect"** —
the effect was the handicap, not the seat. The mirror arm is now a schedule-sanity
check, and Portable's distance from 50% is the strength statement.

**The bulky archetype is not the gap, and never was.** Per archetype, right seat:

| archetype | Reborn-Normal | Portable 0.4.1 | delta |
|---|---:|---:|---:|
| offense | 60/75 | 57/75 | −3 |
| speed | 40/75 | 38/75 | −2 |
| balance | 38/75 | 29/75 | **−9** |
| bulky | 20/75 | 18/75 | −2 |

Bulky is a weak archetype *for both AIs* on this schedule (Reborn manages 20/75 with
it), not a Portable weakness. The old reading — "14 of the 20-battle gap is bulky" —
was the disobedient left seat handing Reborn's bulky teams grinding wins that
Portable's could not get. **The largest deficit is now `balance`**, and it is 9
battles. Roster spread stays larger than the AI difference: Portable *beats* the
reference on `set_a` (+6) and `set_e` (+3) and loses `set_b` by 12.

**The 0.4.x work is worth more than this file ever managed to measure.** The same
five rosters with all four 0.4.0 rules off plus `strict_threat=false` — the verified
0.3.2 reproduction — run on the fixed harness
(`generated/reborn_6v6_v032obey_set_{a..e}.ndjson`):

| | wins / 300 | | on the broken harness |
|---|---:|---|---:|
| Portable 0.3.2 | 123 (41.0%) | | 210 (70.0%) |
| Portable 0.4.1 | **142** (47.3%) | | 217 (72.3%) |
| Reborn-Normal | 158 (52.7%) | | 239 (79.7%) |

Paired: gained 35, lost 16, **+19, McNemar p = 0.012** — significant, where the same
comparison on the handicapped harness read +7 at p = 0.38. So this file's most-repeated
conclusion, *"a mechanism improving does not mean wins improve — every version changed
behaviour visibly and none moved wins detectably"*, was itself an artifact: an opponent
throwing away one turn in six injects noise into every paired comparison and compresses
real differences into the margin. The heal gate and its successors close 19 of the 35
battles that separated 0.3.2 from the reference. The gain is concentrated in **offense**
(+10), not in bulky (+3) — again the opposite of what the diagnosis was aiming at.

What this still costs the record above: absolute win rates, the "fair ceiling", the
Intense-buys-nothing finding, the seat audit's positional effect, and every
archetype-level claim in `PORTABLE-AI-DIAGNOSIS.md`. The mechanisms remain real (each
was verified in traces, not only in win counts) and now demonstrably pay; but any
specific *number* above this section should be re-measured before it is trusted, and
the one-key ablations should be re-run to see which of the four rules the +19 belongs to.

### Intense, re-measured (2026-09-05) — worth nothing against Reborn, worth 23 against Portable

All three Intense arms re-run on the fixed harness, same schedule, seeds and rosters as
the table above, so every arm pairs battle-for-battle. 300 battles per arm, 0 errors.
Files: `generated/reborn_6v6_intenseobey_set_{a..e}.ndjson`.

| right seat | left opponent | wins / 300 | |
|---|---|---:|---|
| Reborn-Normal | Reborn-Normal | 158 | 52.7% |
| Reborn-**Intense** | Reborn-Normal | 151 | 50.3% |
| Portable 0.4.1 | Reborn-Normal | 142 | 47.3% |
| Reborn-Intense | Reborn-**Intense** | 155 | 51.7% |
| Portable 0.4.1 | Reborn-**Intense** | **119** | **39.7%** |

**The cheat set buys Reborn nothing — that claim survives the harness fix.** Against
the same Reborn-Normal opponent, with Intense scoped to the marked trainer's AI pass,
Intense scores 151 where Normal scores 158: **−7, McNemar p = 0.54**. It was previously
"true" at 77.2% vs 79.4%, both inflated by the handicap; it is now true at rates that
mean something. Both mirror arms land where a mirror must (158 and 155 of 300).

**But the same cheat set costs Portable 23 battles.** Same right seat, same schedule,
opponent switched from Normal to Intense: 142 → **119**, gained 31, lost 54,
**p = 0.017**. This is the sharpest asymmetry in the study: Intense's advantages are
choice-reading and 100% Sucker Punch prediction, and against another Reborn those
predictions apparently buy nothing that Reborn's ordinary modelling did not already
have — while Portable's policy is different enough to be *readable*. Being predictable
to an opponent that can read you is a cost Portable pays and Reborn does not.

The confound runs the safe way. `$game_switches[3000]` has two non-AI effects in
battle — Sleep Talk's move choice (`PokeBattle_MoveEffects.rb:4921`) and multi-hit
`pbNumHits` (`:5240`, `:10779`) — and both are gated on `!pbOwnedByPlayer?`, i.e. the
**right** seat, which is Portable in `intense_portable`. If anything they flatter
Portable, so the −23 is a floor.

**Both arms already run at BESTSKILL, so "Normal" here is Reborn at full strength.**
The gauntlet builds its trainers as `PokeBattle_Trainer.new(name, 0)`, and trainer type
0 leaves the skill column of `trainertypes.txt` blank — whereupon the compiler falls
back to the *base money* column (`Compiler.rb`: `record[8]=record[3] if !record[8]`),
which is 100 for "PkMn Trainer". Confirmed in the compiled `Data/trainertypes.dat` the
game loads: `[0, 'PkMnTRAINER_Male', 'PkMn Trainer', 100, nil, nil, nil, 0, 100]`.
Skill 100 is `BESTSKILL`, the top tier, so every `skill >= MEDIUMSKILL/HIGHSKILL/
BESTSKILL` gate in the 17k-line AI is already open under Normal. Intense's own
`@skill = 100` line (`PokeBattle_AI_2.rb:26`) is a no-op in this harness.

That explains why Intense buys nothing here, and the explanation is more interesting
than the result: with the skill tiers already maxed, all Intense adds is the
*information* cheats — swap prediction, reading whether the opponent registered a
switch (`:4722`), full moveset knowledge (`:15596`), 100% Sucker Punch guessing
(`:15854`) — and it **removes** several things Normal does. `getSwitchingScore()` runs
only when the switch is off (`:156`), as do the ACE-role party logic (`:9500`,
`:13322`), the last-ace switch guard (`:11459`) and `checkAIMovePlusDamage` (`:15828`).
Intense is not a superset of Normal; it trades Normal's switching and party heuristics
for opponent information. Against another Reborn that trade is a wash; against Portable
the information wins.

Worth stating plainly for anyone quoting these numbers: the reference is Reborn's
strongest legitimate configuration, not the AI an average in-game trainer runs.

One comparison this schedule cannot make cleanly: what facing Intense costs *Reborn*.
The only both-sides-Intense arm gives its right seat the cheat set too, so 158 → 155 is
a mirror-to-mirror move, not "Reborn-Normal against an Intense opponent". An arm with
Normal on the right and Intense on the left would be needed, and none exists.

Validation of the fixed harness itself, over set_a's 6,841 recorded move executions:
220 `could_not_move` events, **every one** explained by the user's own state
(`status`/`flinch`/`confusion`) — zero unexplained, against 41-of-42 unexplained
before the fix.

Validation, on the 10-battle set_c subset (`generated/reborn_6v6_events_set_c_smoke.ndjson`,
`matchups=offense_vs_bulky,speed_vs_bulky teams=set_c trace=true`): with the
disobedience fix reverted the run reproduced the archived 0.4.1 set_c outcomes and
turn counts 10/10, so the hooks themselves change nothing; per-hit damage sums equal
the observed `hp_lost` on all 235 damaged targets; all 23 status moves classified
`hit` left the target holding exactly that status at round end; and `failed` picks out
Sucker Punch failing and Leech Seed re-clicked on a seeded target (the next item).

**Backlog: Leech Seed re-clicked on a seeded target.** Set_c `offense_vs_bulky 262147`
turns 8–9: Chesnaught seeds Heracross (the drain is visible in the HP), then clicks
Leech Seed again with `fresh_status+25`. `LEECHSEED` carries the `status` tag, and the
core's only guard is the target's major status plus `status_immune`; the target view
exports no `LeechSeed` effect, so a seeded foe looks fresh. Fix: export
`target["seeded"]` (`effects[LeechSeed] >= 0`) and Grass-type immunity from the adapter,
and have the core reject the move on either (same −450 as `target_already_statused`).
Small; needs a unit test and a corpus card.

**Backlog: whole-battle habits seen in the Reborn-right readout** (set_c
`offense_vs_bulky 262147`, `generated/readouts/set_c_REBORNRIGHT_*`). Reborn's Bronzong
sets Stealth Rock into three Dragon Dances because nothing physical Salamence has
threatens it, and its Chesnaught adds Spikes; the hazards then take a large bite out of
Mamoswine and the rest. Reborn switched three times in 28 turns, Portable eight. Reborn
played Amoonguss as the closer with Spore and Synthesis. These are the candidate
subjects for the next diagnosis: hazard value when the foe's boosts cannot reach the
actor, staying in when the matchup is safe, and closing with sleep plus recovery.

**Backlog: a damage race, not just a one-hit threat.** Reborn has no explicit
turns-to-KO comparison, but it approximates one piecewise: its damaging score is
percent of the target's *current* HP capped at 110 (a 2HKO scores 50, a 3HKO 33),
`checkAIdamage` gives the foe's best hit, `maxdam*2 > hp` means "dead in two hits",
`hpGainPerTurn` folds Leftovers/residual into survival, `notOHKO?` covers Sturdy and
Sash, and `pbAIfaster?` orders it all; recovery, setup, Protect and switching all read
these. Portable reads only one-hit questions: `threatened_lethal?`, the certain
variant, `heal_losing_race` (incoming vs heal) and `residual_damage_pct` for switch
escape. Nothing asks "it kills me in two, I kill it in three" — which is exactly the
question a bulky team plays by. The race must be settled in *move order*, not hit
counts alone: with equal hits-to-KO the faster side lands the last hit first, and a
priority move (Ice Shard, Sucker Punch, Bullet Punch, Extreme Speed) on either side
rewrites the order for the final hit — the actor's own priority can steal a race it
would lose on speed, and the foe's priority can take one it would win. Speed order,
each side's priority moves and their damage are already in the snapshot (`faster`,
`priority`, `incoming_by_move`), so the race can be computed from what is exported.
Candidate for the next core version alongside the whole-battle habits above. Radical Red's post-KO switch-in score is the most compact
statement of the same idea (`ANALYSIS.md`, "Radical Red"): outspeed +14, player
4HKOs-or-worse +17, 3HKO +2, 2HKO −1, OHKO −14 — a hits-to-KO ladder that Portable's
`matchup` term could adopt directly.

**Backlog: breadth as tables, shipped as one version.** Reborn's 17.6k lines are
mostly per-move and per-ability branches (494 move-function branches, 1,287 ability
mentions of which 1,161 are decision logic, not damage). The portable answer is facts,
stored once, consumed by a few generic rules, and measured as a batch because single
rules have never moved wins detectably:

- *Move side effects* (`effects.rb`, ~60 rows): `secondary:<kind>:<chance>` (Scald,
  Thunderbolt, Sludge Bomb…) valued as the status rule × chance, only when the status
  matters; `flinch:<chance>` worth something only when faster; `recoil:<pct>` scaled by
  own HP and waived on a KO; `drain` (already tagged, unused) as a partial heal;
  `charge` for two-turn moves; Knock Off/Trick need "target holds an item" from the
  adapter. Sucker Punch, Fake Out, Focus Punch, Counter wait for a foe-intent model.
- *Abilities* (~30 rows): immunities come free from `pbCanBurn?/pbCanPoison?/
  pbCanParalyze?/pbCanSleep?`; a table for the rest — benefits-from-status (Guts,
  Poison Heal, Flare Boost, Marvel Scale, Quick Feet), inverts drops (Contrary),
  ignores indirect damage (Magic Guard), ignores boosts (Unaware), absorbs a type
  (Motor Drive, Volt/Water Absorb, Lightning Rod, Flash Fire, Sap Sipper), Prankster,
  Wonder Guard — with about six generic rules. Numeric abilities (Huge Power,
  Adaptability, Technician, Multiscale…) are already in the engine's damage numbers.
- *Entry/exit effects* for switch scoring: Intimidate vs a physical foe, Regenerator as
  a discount on leaving, weather setters. *Sturdy/Focus Sash*: cap both lethal checks
  at 1 HP (Reborn's `notOHKO?`).
- *Tempo abilities* (Speed Boost, Moxie, Unburden, weather speed) and *boost valuation*
  (does +1 turn a 3HKO into a 2HKO, does +1 Spe flip the order → `speed_setup`) belong
  to the damage-race version, not this one.

Pipeline per tag: declare in `effects.rb` → export any engine fact from the adapter →
one core rule with a named reason → unit test + corpus card stock Reborn passes → ship
the whole table as one version and A/B it on five rosters.

## Core version 0.5.0 — breadth as tables (2026-09-05)

0.3.0 through 0.4.1 each added one per-turn rule and none moved wins detectably.
0.5.0 is the other kind of change: Reborn's per-move, per-ability and per-item
valuations shipped as **data tables** read by a few generic rules, measured as one
batch. Phase A (the section below) wrote the probe corpus first; this is Phase B.

**Four config keys, all defaulting true, each with its own off switch in
`Data/ai_harness.txt`:** `side_effects`, `ability_rules`, `entry_rules`,
`format_rules`. **Control run: all four false reproduces 0.4.1 battle-for-battle** —
60/60 identical results AND identical turn counts on set_c
(`generated/reborn_6v6_v050control_set_c.ndjson` against
`reborn_6v6_v041obey_set_c.ndjson`).

### What is in the tables

| where | what |
|---|---|
| `adapters/reborn/Portable_AI_Adapter.rb` | `MOVE_EFFECT_CODES` — one lookup on the engine's own Essentials function code gives every secondary's kind and stat, replacing ~80 hand-tagged move names and covering moves nobody listed. `MOVE_RECOIL_CODES`, `MOVE_DRAIN_CODES`, `MULTI_HIT_CODES`, `TERRAIN_FIELDS`. Per-action: `move_type`, `category`, `contact`, `effect_kind/stat/chance`, `multi_hit`, `recoil_fraction`, `drain_fraction`, engine-aware `priority`. Per-battler: `ability`, `item`, `full_hp`, `physical_attacker`, `special_attacker`, `substitute`, `partner_ability`, `choice_locked_move`, `mold_breaker`, `turncount`, `slower_bench_count`, `partner_*`. Snapshot: `terrain`, `trick_room_active`, `tailwind_active`. |
| `portable_ai/effects.rb` | `setup` gains the defensive boosts it never had (Iron Defense, Amnesia, Cosmic Power, Acid Armor, Barrier, Stockpile, Hone Claws, Curse); new tags `speed_control`, `field_speed`, `first_turn_only`, `delayed_damage`, `partner_heal`, `item_removal`; `Effects.kind_of` for adapters with no function codes. |
| `portable_ai/core.rb` | The rules that read them, each with a named reason. |

**Delta mapping.** Reborn multiplies a damage-percent score by a per-move `miniscore`;
Portable adds. The quantity that multiplier scales is the move's DAMAGE score, so
`multiplier_delta` scales the same thing — the lethal bonus when the move kills, the
capped damage term when it does not. `reduce_when_kills` is Reborn's own
`pbReduceWhenKills` (:9887): once the score is at the cap the multiplier is
square-rooted, so bonuses and costs soften alike.

### Three deliberate departures from the reference

Each is a place Phase A measured stock Reborn NOT doing something, and 0.5.0 does it
anyway. They are marked as departures in the code because a future agent comparing
against Reborn will otherwise read them as bugs.

1. **Secondaries are scaled by their chance.** `burncode`/`paracode`/`poisoncode`/
   `freezecode` never read `move.addlEffect`, so Reborn prices Scald's 30% burn and
   Will-O-Wisp's 100% burn identically. `chance_scaled` fixes that.
2. **A choice-locked foe is a one-move threat.** `incoming_damage_by_move` restricts
   the map to the locked move. Reborn reads `PBEffects::ChoiceBand` when it scores
   switch-ins (:11377) and not when it scores moves — measured, Skarmory scored Roost
   at **0** behind a Heatran locked into a move it was immune to.
3. **The Boots exclusion applies to every hazard.** Reborn's Spikes and Toxic Spikes
   branches skip Heavy-Duty Boots holders; its Stealth Rock branch does not look at
   the opposing party at all. On one all-Boots board stock scored Spikes **0** and
   Stealth Rock **45**; 0.5.0 scores both at −500.

### One row was written, measured, and withdrawn before release

The first 0.5.0 draft cancelled the kill call against Sturdy and Focus Sash —
`lethal = false`, `damage := target_hp - 1`. It is gone, and the reasoning is in a
comment at the site so it is not re-derived from scratch:

* **Reborn does not do it.** `notOHKO?` (:17401) exists to pay a MULTI-HIT move ×1.3
  for beating the guard (:7389); it never removes a single-hit move's kill score. The
  multi-hit row is that same fact, and it is what the corpus cards actually decide on.
* **The cost was out of proportion to the information.** Cancelling `lethal` takes
  ~420 points off the strongest move — far more than "you will need a second hit" is
  worth, when breaking the guard is what makes the next hit lethal.
* **It measured badly, and it was the only ability row that could.** On set_a..e,
  Unaware, Contrary, Justified and Regenerator are all inert, so `ability_rules` there
  was essentially this row plus the status-deterrent table.

### Measured (2026-09-05)

Reported as **two separate populations, never pooled** — the rosters differ in kind.

**set_a..set_e (120 mons, slot-0 abilities, no held items):**

```
normal_portable over 300 paired battles
  0.4.1  142/300 = 47.3%
  0.5.0  135/300 = 45.0%   (-7)   gained 13, lost 20
  McNemar chi2=1.09  z=1.04  two-sided p=0.296   (not significant)
```

**set_f/set_g (48 mons, dressed with an item and a non-slot-0 ability):**

```
normal_portable over 120 paired battles
  0.4.1   49/120 = 40.8%
  0.5.0   56/120 = 46.7%   (+7)   gained 11, lost 4
  McNemar chi2=2.40  z=1.55  two-sided p=0.121   (not significant)

  archetype     n    0.4.1    0.5.0  delta
  bulky        30        0        4     +4
  balance      30       10       12     +2
  offense      30       18       19     +1
  speed        30       21       21     +0
```

**Neither result is significant on its own, and the contrast between them is the
finding, not either number.** 0.5.0 costs a little where its tables cannot fire and
gains where they can — including the first movement in `bulky`, the archetype the
whole 0.4.x diagnosis chain was aimed at. It is a hypothesis with 120 battles behind
it, not a result: the honest next step is more f/g-shaped rosters, not another rule.

**Why a..e cannot judge this version.** The gauntlet builds every mon with
`setAbility(0)` and no held item, so across those 120 mons **every item row and most
ability rows can never fire even once** — no Knock Off target holds an item, no Focus
Sash exists to break, no Choice lock ever forms, and Unaware, Contrary, Justified,
Regenerator, Magic Guard, Magic Bounce, Multiscale and Mold Breaker are all non-slot-0.
That is what set_f/set_g exist for.

**One-key ablations** (set_a + set_c, 120 battles, against 0.5.0's own 56/120):

| run | wins | vs 0.5.0 |
|---|---:|---:|
| 0.4.1 (all four off) | 60/120 | +4 |
| 0.5.0 (all four on) | 56/120 | — |
| minus `side_effects` | 55/120 | −1 |
| minus `ability_rules` | 59/120 | +3 |
| minus `entry_rules` | 57/120 | +1 |
| minus `format_rules` | 56/120 | ±0 |

`format_rules` at exactly ±0 is a control on the ablation machinery itself: the 6v6
`normal_baseline` schedule is 100% singles, so that key is inert by construction and
anything other than 0 would have meant the harness was not doing what it claimed.

### Corpus and tests

* Stock Reborn on the 184-scenario corpus: **238/238**.
* Portable 0.5.0 on the same corpus: **234/234**, with 4 assertions reported `N/A`.
  Those four are the `switch_score_gt` entry cards: Reborn emits a party-indexed
  score array and Portable's probe record emits the plan's ranking, which is **sorted
  by score**, so index 0 is whichever candidate won rather than a party slot. Before
  `check_scenarios.py` learned to say so, all four silently PASSED against Portable —
  the best candidate is always first, whichever bench slot it came from. A positional
  assertion against an unlabelled sorted array is not unreliable, it is meaningless.
* `tests/test_portable_ai.rb` 77 tests, `tests/test_reborn_adapter.rb` 33,
  `tests/test_realidea_adapter.rb`, `tests.test_tooling` — all green. One pair per
  table row (fires / correctly silent) plus the four off-switches.

### The bug that hid half the version

The first 0.5.0 build resolved ability and item names through `PBAbilities.getName` /
`PBItems.getName`. **Those return an empty string in the test environment the probe and
the gauntlet both run in** — it has no compiled message data, which is the same reason
debuglog.txt shows blank species names. So `ability_key` returned `""` for everything
and every ability and item row in all four tables silently did nothing: 22 corpus cards
failed under Portable while passing under stock. Both now resolve through the CONSTANT
tables (`PBAbilities.constants`, as `move_key` already did for moves), which are
compiled into the module and always present. **Never use a `getName` for a fact the AI
branches on.**

## 0.5.0 Phase A: what stock Reborn does on each table row (2026-09-05)

0.5.0 ships Reborn's per-move / per-ability / per-item valuations as **data tables**
rather than as another per-turn rule (the "breadth as tables" backlog entry above).
Phase A writes one probe card per intended table row and runs **stock Reborn** against
it, so a row is only written as a rule where the reference agrees. This is the
`heal_at_low_hp` discipline from `PORTABLE-AI-DIAGNOSIS.md`: a rule derived from a
reading of the source, with no measurement, encoded a term Reborn does not have.

**Corpora.** `CORPUS_V9` (18 cards, move side effects), `CORPUS_V10` (23 cards,
abilities / items / entry / terrain), `CORPUS_D3` (10 cards, doubles) in
`tools/make_scenarios.py`. Corpus 133 -> 184 scenarios, 236 -> 238 assertions.

**Result.** `generated/probe_results_v050_stock.ndjson`, stock Reborn, 184/184
scenarios built, **238/238 assertions pass**, 0 errors, 0 degenerate, 0 skipped. The
133 pre-existing cards were unaffected. Reproduce with the Build-and-install loop
above, `out=Data/ai_probe_results_v050_stock.ndjson` and NO `Data/portable_ai.txt`.

Three cards took four probe runs to settle, and each of the three misfires is
recorded in the card's own comment, because the failure mode recurs: **a card can pass
or fail for a reason that has nothing to do with the row it names.** Icicle Spear lost
to Ice Beam on the target's 120 Def / 60 SpD split; then lost to Icicle Crash because
the comparator was quietly collecting `flinchcode`'s own x1.3; Spikes could not beat a
2x Brave Bird because `hazardcode` scales with bench size and the party had two mons on
it. Match the comparator's category, secondary and speed relationship, or the number
measures something else.

### Harness changes this needed (A1)

| File | Change |
|---|---|
| `adapters/reborn/Portable_AI_Gauntlet.rb` | Override parsing extracted to `PortableAIRebornGauntlet.config_overrides_from(cfg)`, and attached to `AIHarness.run_probe` by alias at load time (`install_probe_config_patch`). `mode=probe` returns from `AIHarness.run` (:218) before the gauntlet's parse ran, so a probe could never be told which core rules to switch off — which is how a single table row gets ablated in Phase B without a 4-minute battle run. `AI_Harness.rb` is game-side and was not edited; `!script_order.csv` loads it before `Portable_AI`, so the alias always finds it. |
| `tools/make_scenarios.py` | Unresolved species/move/ability/item names and unknown `extra` keys now **abort with a non-zero exit and write nothing**. Both used to print a `WARNING` and exit 0, so an unresolved ability silently left the mon on slot 0 and the probe graded a position nobody wrote. New `EXTRA_KEYS` vocabulary. Also emits `ai_party_species` / `ai_actives` for the assertion below. |
| `tools/check_scenarios.py` | New assertion kind `switch_score_gt <ref_a> <ref_b>`, where a ref is a species name or `bench<k>`. `benchN` exists because the cards that isolate an ability or an item bench **two of one species**, which is the only way to price one without a typing or bulk difference paying for it. Reads `switch_scores`, telling Reborn's party-indexed array from Portable's switchable-only array by length, and failing loudly when neither fits. |

### Rows Reborn confirms (kept as guardrails)

| row | card | measured (stock) |
|---|---|---|
| recoil is a flat penalty, not a fraction | `recoil_flat_penalty_vs_equal_power` | Brave Bird 42 / Drill Peck 31 — `recoilcode` is 0.9 and 120 BP still wins |
| don't click the suicidal KO | `recoil_move_that_kills_self_still_clicked` | Brave Bird 74 / Drill Peck 82; every lethal move ties at 82 |
| recoil cheaper in the 10-40% band | `recoil_cheaper_when_low_hp` | Brave Bird 42 -> 33 at 30% HP; Drill Peck unchanged at 31 |
| drain is worth HP when damaged | `drain_valued_when_damaged` | Giga Drain 137 / Energy Ball 110 (4x target) |
| drain is worth nothing at full HP when faster | `drain_worthless_at_full_hp_when_faster` | Giga Drain 15 / Energy Ball 19 |
| flinch only counts when faster | `flinch_valued_when_faster` / `flinch_ignored_when_slower` | 38/24 faster, 29/43 slower — the ranking inverts |
| burn is worth more into a physical attacker | `secondary_burn_vs_physical_attacker` / `..._special_attacker` | Scald 38 / Surf 35 vs Machamp; 31 / 41 vs Alakazam |
| paralysis is worth the speed flip | `secondary_para_valued_when_it_flips_the_order` | Body Slam 43 / Strength 35 |
| status immunity comes from the engine's can-status check | `secondary_burn_dropped_vs_fire_type` | Scald 67 / Surf 75 — `pbCanBurn?` collapses the term |
| Sheer Force deletes the secondary | `secondary_dropped_by_sheer_force` | Sludge Bomb 10 / Earth Power 86 |
| SpA drop valued into a special attacker | `stat_drop_spa_vs_special_attacker` | Moonblast 53 / Dazzling Gleam 43 |
| Knock Off values the item | `knockoff_vs_leftovers` / `..._no_item` / `..._focus_sash...` | Knock Off **75 / 39 / 58** against a flat Night Slash 42 |
| multi-hit answers Sturdy and Sash | `multihit_breaks_sash`, `sturdy_blocks_the_kill_call`, `focus_sash_same_as_sturdy` | Icicle Spear 59 / Icicle Crash 46 at full HP |
| ...and only at full HP | `sash_ignored_when_not_full_hp` | 51 / 52 at 90% — the x1.3 is gone |
| Intimidate is worth a switch-in | `intimidate_switchin_lowers_incoming` (+ `..._order_swapped`) | see the Intimidate block below |
| Magic Bounce makes status unusable | `magic_bounce_blocks_hazards` | Stealth Rock **-1**, Toxic **-1**, Earthquake 76 |
| Prankster status fails into Dark | `prankster_status_fails_vs_dark` | Will-O-Wisp **0**, Foul Play 27 |
| Misty Terrain blocks status | `misty_terrain_blocks_status` / `toxic_valued_on_open_field` | Toxic **0** on field 3, **30** on field 0 |
| Natural Cure devalues status | `natural_cure_devalues_status` | Toxic 30 -> **9** (x0.3), same Blissey, ability the only change |
| Guts devalues burn | `guts_devalues_burn` | Will-O-Wisp 3 / Seismic Toss 27 |
| Unaware devalues setup | `unaware_devalues_setup` | Dragon Dance **1** / Dragon Claw 40 |
| Contrary inverts the self-drop | `contrary_flips_leaf_storm` | Leaf Storm **310** / Giga Drain 61 |
| hazards are worthless against an all-Boots party | `spikes_hit_nobody_with_boots` / `spikes_valued_without_boots` | Spikes **0** vs **45**, same board |
| Psychic Terrain kills priority | `psychic_terrain_blocks_priority` / `priority_ko_valued_on_open_field` | Aqua Jet **0** on field 37, **242** on field 0 (Waterfall 121 in both) |
| doubles: spread with an airborne partner | `d_eq_with_airborne_partner` | EQ 63.0 summed vs Dragon Claw 38 |
| doubles: spread into an absorbing partner | `d_spread_into_absorbing_partner` | Discharge **280.0** summed vs Thunderbolt 112 |
| doubles: the foe's Lightning Rod redirects | `d_redirect_by_foe_partner` | Thunderbolt **-1**, Ice Beam 22 |
| doubles: priority is worth less than in singles | `d_priority_flat_in_doubles` | Aqua Jet 157 / Waterfall 121, against **242** / 121 in singles |
| doubles: Fake Out on turn 0 | `d_fakeout_turn_one` | Fake Out 139 / Flare Blitz 102 |
| doubles: Tailwind and Trick Room when slower | `d_tailwind_when_slower` / `d_trick_room_when_slower` | Tailwind 56, Trick Room 70, Power Whip 11 |
| doubles: spread speed control | `d_icy_wind_speed_control` | Icy Wind **81** summed vs Ice Beam 66 |

### Rows Reborn does NOT have (findings, not guardrails)

These cards are in the corpus as `must_choose_any` — the position is kept and its
numbers are recorded, but nothing is asserted, because an assertion the reference
fails is a claim about good play that has not been justified. Each is a candidate for
a 0.5.0 rule plus a unit test in `tests/test_portable_ai.rb`, NOT a corpus guardrail.

1. **A choice-locked foe is still treated as its whole moveset.**
   `choice_locked_foe_threat_is_one_move`: Heatran is locked into Earth Power, which
   Skarmory is immune to. Roost at 20% HP scores **0** and the AI clicks a 0.25x Brave
   Bird at 11 — `recovercode` zeroes the heal because it still fears Flamethrower.
   `getSwitchInScoresParty` reads `PBEffects::ChoiceBand` as the expected incoming move
   (:11377); the move scorer four thousand lines away does not. Feeds `strict_threat`.

2. **The AI's OWN partner's Lightning Rod is not priced.**
   `d_own_partner_rod_steals_move`: Thunderbolt 33 / Ice Beam 22, and the AI clicks
   Thunderbolt into a board where its own Seaking absorbs it. `d_redirect_by_foe_partner`
   passes on the same mechanic pointed the other way, so this is one direction of a
   symmetric rule being absent rather than a missing concept.

3. **Regenerator's switch-out bonus can never fire.** `healscore += 40` at :13415 and
   `+= 50` at :13792 are both guarded by `hp/totalhp < (2/3)`, and `(2/3)` is Ruby
   **integer division = 0**. No probe card: the condition is unreachable for any HP
   value, so there is nothing to measure. 0.5.0 may implement the intent (+50 to
   `score_switch` under 66% HP, score only, never an escape reason) but must not cite
   Reborn as having it.

4. **`totalHazardDamage` cannot return anything for Spikes, Stealth Rock or Dragon
   Crystals.** All three branches (:10456, :10464, :10483) are guarded by
   `!pkmn.ability == PBAbilities::MAGICGUARD`, which Ruby parses as
   `(!pkmn.ability) == PBAbilities::MAGICGUARD` — `false == <Integer>` — so the
   conjunction is **always false** (verified: `ruby -e 'p(1 > 0 && !5 == 4 && true)'`
   prints `false`). Only the skill-gated Corrosive / Icy / Cave field branches below
   them, which use the correct `!=`, can contribute. This explains CORPUS_V5's
   `switch_stay_hazards_deter` finding that the :11829 hazard charge left the pivot's
   switch-in score unchanged. **Open question**, see the Boots block below.

5. **Stealth Rock is scored without looking at the party it would hit.** The 0x103
   Spikes and 0x104 Toxic Spikes branches walk the opposing party, skip Boots holders
   and zero the score when nobody is left (:4600-4668). The 0x105 Stealth Rock branch
   (:4670) has no such walk at all. `stealth_rock_ignores_boots` and
   `spikes_hit_nobody_with_boots` are the SAME all-Boots board: Spikes **0**, Stealth
   Rock **45**. Asserted in the Stealth Rock direction, so the asymmetry is a
   guardrail rather than a wish.

6. **Status secondaries are not scaled by their chance.** `burncode`, `paracode`,
   `poisoncode` and `freezecode` never read `move.addlEffect`, so Scald's 30% burn and
   Will-O-Wisp's 100% burn get the same 1.2 base. Only `flinchcode` and the stat-drop
   rows go through `pbSereneGraceCheck`. The plan's delta mapping assumed
   `m = 1 + (m-1) x chance/100` mirrored Reborn; it does not, and 0.5.0 has to choose
   between copying Reborn and correcting it — the correction is defensible, but it is
   a **departure**, and must be labelled as one in the version notes.

7. **Doubles switch-in scoring is not reachable from the probe.** The doubles twin of
   the Intimidate card measured `shouldSwitch?` at **-40** and **-30** for the two
   actors, so `switchscore` stayed empty (:11358 gates filling it on a positive score).
   Reborn's doubles switch path does not go positive while a partner is standing. The
   :11590 loop over both opponents is read from the source only; the doubles half of
   the Intimidate row has no measurement behind it.

### Two corrections to the plan's coverage audit

**Clear Body IS handled, through the engine and not through Reborn's list.** The audit
predicted `intimidate_ignored_vs_clear_body` would fail because :11594 exempts only
White Herb / Contrary / Mirror Armor / Defiant. It does — but the drop goes through
`pbCanReduceStatStage?` (`PokeBattle_Effects.rb:686`), which refuses for Clear Body,
White Smoke, Full Metal Body, **Clear Amulet** and Hyper Cutter as well. Measured with
two Arcanine identical but for the ability, against the same Mamoswine:

| board | Intimidate Arcanine | Flash Fire Arcanine |
|---|---|---|
| bench order [Intimidate, Flash Fire] | **18** | -43.2 |
| bench order [Flash Fire, Intimidate] | **10.8** | -72 |
| foe holds a Clear Amulet | **-72** | -43.2 |

Bench slot carries roughly 29 points of its own, which is why both orders were run.
Read down the columns: with the Clear Amulet on, the Intimidate mon scores exactly
what a non-Intimidate mon scores in that slot (-72 in slot 1, -43.2 in slot 2). The
exemption is complete. 0.5.0's `switch_actions` should therefore ask the engine, not
carry the extended immunity list the plan proposed.

**Heavy-Duty Boots does change the switch-in score, and the mechanism is not
identified.** `heavy_duty_boots_entry` and its order-swapped twin, two identical
Charizard differing only in the item, with Stealth Rock on the AI's own side:

| board | Boots Charizard | bare Charizard |
|---|---|---|
| bench order [Boots, bare] | **-4** | -20.4 |
| bench order [bare, Boots] | **-2.4** | -34 |

Boots is worth 18-30 points in both orders, so the effect is real and not an artifact
of evaluation order. But it cannot be coming from `totalHazardDamage`, which finding 4
shows is unreachable, and a scan of the switch scorer (:11363-11960) finds no other
`HEAVYDUTYBOOTS` reference. **B1 must locate the term before the adapter tries to
reproduce it**; the plan's `entry_hazard_pct = 0 for Boots holders` may be right for
the wrong reason, and shipping it as "what Reborn does" would repeat the
`heal_at_low_hp` mistake in the opposite direction.

### Rows dropped for want of harness support

`AI_Harness.rb` is game-side and outside this study's sources, so three rows the plan
listed have no card and no measurement:

- `future_sight_not_stacked` — needs a `futuresight` entry in `EFFECT_KEYS`.
- `d_tailwind_already_active` — needs a `tailwind` entry in `SIDE_EFFECT_KEYS`.
- the "0 after turn 1" half of Fake Out — no scenario field sets `turncount`; only the
  turn-0 half (`d_fakeout_turn_one`) is measured.

`d_eq_with_grounded_partner` was also dropped: CORPUS_D2's `d_spread_kills_own_partner`
already occupies that position and passes.

### One weak card, flagged

`stat_drop_speed_when_slower` passes on Icy Wind 5 against Ice Beam 4 — a one-point
margin on a position where both padded fillers outscore both real moves (Peck 15 wins
the choice). It documents the direction and nothing more. The doubles twin,
`d_icy_wind_speed_control` (Icy Wind 81 summed against Ice Beam 66), is the version of
this row with a real margin behind it, and is what the 0.5.0 speed-drop rule should be
calibrated against.

### Phase B

Phase B shipped as core 0.5.0 — see the section above this one. Its inputs were this
table, the two corrections, and the open question about Boots, which is still open:
0.5.0 zeroes the entry cost for a Boots holder because that is what the item does, not
because the term Reborn uses for it was ever located.

## Core version 0.6.0 — the damage race (2026-09-06)

Every rule through 0.5.0 asks a **one-hit** question: does the next hit kill me
(`threatened_lethal?`, `certain_lethal_threat?`), does my next hit kill it (`lethal`,
`has_lethal_move?`). 0.6.0 adds the **two-hit** question a bulky team plays by — *it
kills me in two, I kill it in three* — as one pure helper that three rules read.

**Two config keys.** `damage_race` (default **true**) is the helper and the two rules
that reproduce measured Reborn behaviour. `damage_race_switch` (default **false**) is
the switch escape reason, off because Phase A measured stock Reborn refusing to leave
a race it loses. `damage_race=false` reproduces 0.5.0 **exactly**: 60/60 identical
results *and* identical turn counts on set_c
(`generated/reborn_6v6_v060control_set_c.ndjson` against `reborn_6v6_v050_set_c.ndjson`,
`tools/compare_versions.py` 0/0).

### The helper

`PortableAI.damage_race(snapshot, actor, target, config)` returns
`{"mine", "theirs", "faster", "last_hit_first", "winning"}` or **nil**. It is pure — it
reads the snapshot and nothing else, so `view_trace` calls it on the snapshot the
adapter has just built and every traced turn carries its counts under `view.race`.

- `mine = ceil(target_hp / my best hit on it)`, `theirs = ceil(actor_hp / (foe's best
  hit + my residual))`, both capped at 8. Sturdy and Focus Sash cost `mine` one extra
  hit — the one place in the core that guard belongs, since 0.5.0 deliberately left the
  kill call alone (cancelling `lethal` deletes the move's value; spending a hit is what
  the guard actually does).
- `mine < theirs` wins and `mine > theirs` loses **whatever the speed**: a hit-count gap
  cannot be closed by moving first.
- Equal counts are decided by who lands the **final** hit — a priority move that is big
  enough to finish the job, on either side, and otherwise the per-foe speed flag. This
  is `pbAIfaster?(attackermove, opponentmove)` (`:10051`) restricted to the last
  exchange.
- **nil** whenever an input is missing: no `threats_by_foe` (the Realidea adapter
  exports none, so the whole feature is inert there and its tests are untouched), or no
  damaging move of the actor's own. Same "a missing field never penalises the actor"
  contract as `faster_flag`.

Point estimates, not low rolls, and accuracy is ignored — as Reborn's own `maxdam`
ignores it. The consumers only ever withhold a bonus or add an escape reason, never a
−400.

### The export it needed

`threats_by_foe` on the actor (`Portable_AI_Adapter.rb`), built from the same
`incoming_map` the threat rules already pay for: per foe, its best hit, its best hit
that moves first, and the speed order **against that foe**. `actor["faster"]` is against
the *fastest* foe only, which is the wrong flag for the slower target in doubles and
would make a doubles race simply wrong. `incoming_by_move`, `faster` and
`incoming_damage_pct` are unchanged, so `debuglog_join.py`, `threat_audit.py` and
`render_battle.py` still read what they always did. Switch candidates additionally
carry `outgoing_damage_pct` and `faster`, built on the same fake battler and under the
same rescue-to-nil contract as 0.5.0's `incoming_damage_pct`.

### The three consumers

| rule | what it does | where it comes from |
|---|---|---|
| `setup_into_2hko` (−180) | refuses a setup when the foe needs ≤ 2 hits **and the actor is slower** | Reborn's ×0.4 at `:6007`, against a ~450-point setup score |
| `switchin_race` (+85 / +10 / −5 / −70, and +70 for outspeeding) | ranks *who comes in*, so it applies to forced switches too — the post-KO replacement Radical Red designed the table for | Phase A measured both halves in stock: 257 vs −175.8 for one Assault Vest, 193 vs 115.8 for 252 Speed EVs |
| `losing_damage_race` (+110, **off**) | a switch escape reason when the race is lost at full health | Radical-Red-cited only; see below |

Three departures from the reference, marked in the code so a future agent does not read
them as bugs:

1. **`setup_into_2hko` applies to any setup move.** Reborn's own gate additionally
   requires `stats[PBStats::ATTACK]==1`, and `stats` holds *stages*, so its rule
   silently skips every +2 move (Swords Dance, Nasty Plot) and only ever reaches +1
   moves. That is a quirk of how the gate was written, not a claim about play.
2. **The `faster == false` clause is kept, and it is a measurement not an inference.**
   The Phase A card `race_setup_when_2hkoed_but_faster` is the same board as its
   predecessor with +2 Speed and nothing else: stock Reborn's Swords Dance went from
   **9 to 46**. What refuses the setup is the speed order, not the race.
3. **`losing_damage_race` ships off.** `race_leave_when_losing_2hko_vs_3hko` put a
   healthy Donphan in front of an Espeon that 2HKOs it, with a Psychic-**immune** bench
   available, and `shouldSwitch?` came back **−50** with the bench never scored. The
   switch programme was closed on evidence (`PORTABLE-AI-DIAGNOSIS.md` §4) and this must
   not reopen it by default.

### The bug the portable probe caught

The first build had `setup_into_2hko` silently inert on **every** card. A setup move is
a *status* move and the adapter gives it no scoring target, so `target` was nil and the
race returned nil — and the unit test had been written with a target on the setup move,
so it passed. The rule now falls back to `worst_race`, the foe the actor is doing worst
against. The unit test was rewritten to export the setup move the way the adapter
actually does. **A unit test that does not build its input the way the adapter builds
it will pass a rule that never fires.**

### Measured

Probe: **243/243** (`generated/probe_results_v060_portable.ndjson`), 1 degenerate record
— `switch_out_all_moves_immune`, the same one 0.5.0 had, and degenerate by construction.
Six `switch_score_gt` assertions come back N/A against a Portable record for the reason
0.5.0 recorded: Portable's `switch_scores` is a score-ordered ranking, not a
party-indexed array. Both new switch cards still pick the intended candidate
(1081.3 vs 1043.4, and 1185.2 vs 1115.2 — the second gap is exactly the +70).

Gauntlet, `schedule=normal_baseline` 6v6, `arms=normal_portable`, measured **separately**
because the two roster families cannot judge the same thing (a..e are itemless with
slot-0 abilities):

| rosters | 0.5.0 | 0.6.0 | delta | McNemar |
|---|---:|---:|---:|---|
| set_a..e (300 battles) | 135 | 137 | **+2** | gained 13 / lost 11, p = 0.838 |
| set_f..g (120 battles) | 56 | 60 | **+4** | gained 6 / lost 2, p = 0.289 |

Neither is significant, which is now the expected shape: 0.3.0 through 0.5.0 each
changed a mechanism visibly and none moved wins detectably. Per archetype on a..e:
bulky **16 → 18**, offense 52 → 56, balance 31 → 32, speed 36 → 31. Bulky is the
archetype the race was aimed at and it moved the right way, by two battles, which is
noise at this n.

**The behavioural effect is what is actually measurable**, and `tools/policy_gaps.py
race` measures it — two traced runs of set_c differing only in `damage_race`:

| run | race | order | n | set up | stayed | left |
|---|---|---|---:|---:|---:|---:|
| `damage_race=false` | 2HKO | slower | 231 | **3** | 222 | 6 |
| `damage_race=true` | 2HKO | slower | 229 | **0** | 223 | 6 |
| `damage_race=false` | 2HKO | faster | 192 | 10 | 180 | 2 |
| `damage_race=true` | 2HKO | faster | 185 | 16 | 167 | 2 |

The rule fires exactly where it was designed to — three refusals, all of them
2HKOed-and-slower — and nowhere else. The 1HKO rows are unchanged because
`unsafe_setup` already owns them.

### Not in 0.6.0, and listed here rather than rediscovered

Foe-side residual (Leftovers, the foe's own toxic — the adapter exports the actor's
only); boost valuation (does +1 turn my 3HKO into a 2HKO — needs a damage-at-stage
export); Sitrus and pinch berries; Protect and stall reading the race; and a
current-HP damage scale to replace the linear `0.8 x damage` (Reborn's %-of-current-HP
scale is already the same ordering, so changing it would re-tune every threshold in the
core for no new information).

## 0.6.0 Phase A: the damage race in stock Reborn (2026-09-05)

Eleven cards (`CORPUS_R1` in `tools/make_scenarios.py`, corpus 184 → 195), graded
against **stock** Reborn before any 0.6.0 rule exists — the same protocol as 0.5.0
Phase A. Artifact `generated/probe_results_v060_stock.ndjson`; the whole corpus is
**249/249**, so nothing here is a regression report, it is a measurement.

### Three engine facts the positions had to be built on

These were read from source and then confirmed against the archived 0.5.0 probe
artifacts. Any of them wrong and a card measures a different position than the one on
the page, so they are recorded here rather than only in the corpus header.

1. **The AI discounts its own damage by 15% and the foe's by nothing.**
   `pbRoughDamage` ends `damage=(damage*random/100.0).floor` with `random=85` at
   `BESTSKILL` — but only inside `if ai_mon_attacking` (`:16833-16838`), a branch keyed
   on battler indices. So Reborn scores what it deals at a low roll and what is coming
   at a max roll, and is therefore **systematically pessimistic about the race**: at
   equal real damage it will believe it needs more hits than the foe does. Reproducing
   this exactly turned a 0.83 mean ratio error into an exact match on **91** clean
   neutral rows of `ai_probe_results_v050_portable.ndjson` (the portable score inverts
   to the engine's own number: `(score − 100) / 0.8` for a plain damaging move). The
   remaining 31 rows are all explained by abilities the model does not carry
   (Intimidate on entry, Thick Fat, Levitate).

2. **On turn 1 the foe's threat is an invented move, not its moveset.** `maxdam` comes
   from `checkAIMovePlusDamage` (`:15671`), which at `HIGHSKILL` tops up an incomplete
   memory with `PokeBattle_Move_FFF` (`:17454`) — an 80 BP STAB move of *each of the
   foe's types*, physical iff the foe's Attack exceeds its Special Attack, priority 0.
   A probe builds a fresh battle, `addMonToMemory` seeds an **empty** array (`:15589`),
   and the probe runs **Normal** (`AI_Harness.rb:84` makes a blank `Game_Switches`, so
   the Intense "read the whole moveset" shortcut at `:15596` is off). On every probe
   card in this corpus, therefore, the foe's *listed* moves are invisible to stock and
   only its typing and its higher attacking stat decide what it threatens. Every foe
   in `CORPUS_R1` is consequently mono-type and carries exactly one attack that
   reproduces its own invented threat move, so stock and Portable see the same number;
   `race_no_setup_into_priority_finisher` breaks that on purpose.

   This is also a **knowledge asymmetry in Portable's favour that predates 0.6.0**:
   `Portable_AI_Adapter.rb:912` builds `incoming_by_move` from `foe.moves`, so Portable
   knows the opponent's real moveset from turn 1 while Reborn-Normal learns it as the
   battle goes. It is bounded (memory fills after the first move) and it is not what
   0.6.0 is about, but it is not currently written down anywhere and the `"knowledge"
   => "fair"` config key is declared and never read.

3. **The ×0.4 setup gate cannot reach Swords Dance.** `:6007` requires
   `stats[PBStats::ATTACK]==1 || stats[PBStats::SPATK]==1`, and `stats` holds the
   number of **stages** (`selfstatboost`, `:5831`). Swords Dance passes
   `[2,0,0,0,0,0,0]` (`:3645`), Dragon Dance `[1,0,1,0,0,0,0]` (`:3615`). So Reborn's
   only explicit "I am being 2HKOed, do not set up" multiplier applies to +1 moves and
   silently skips every +2 move. Measured below.

### What each card measured

| card | position | stock result | reading |
|---|---|---|---|
| `race_setup_when_3hkoed_and_slower` | Garchomp (slower) 3HKOs Espeon and is 3HKOed | **Swords Dance 42 > Strength 40** | pass. `maxdam < hp/2` pays setup ×1.1 (`:5993`); a losing-by-nothing race is a fine time to set up |
| `race_no_setup_when_2hkoed_and_slower` | same foe, bulkier/slower Donphan, 2HKOed | **Swords Dance 9, Strength 37** | pass. ×0.8 for a status move plus ×0.3 for having no damaging move that outruns the foe (`:5999`) |
| `race_setup_when_2hkoed_but_faster` | the same board with **+2 Speed and nothing else** | **Swords Dance 46 > Strength 37**, and the AI clicks it | **the finding.** 9 → 46 with the damage in both directions untouched: what refused the setup was the *speed order*, not the race. Reborn will happily set up while being 2HKOed as long as it moves first |
| `race_no_setup_when_2hkoed_one_stage` | same board, Dragon Dance instead | **Dragon Dance 6** against Swords Dance's 9 | fact 3 confirmed. The +1 move takes a further ~×0.4 that the +2 move on the identical board never sees |
| `race_no_setup_into_priority_finisher` | Garchomp 45%, faster; Snorlax's Ice Shard is 102% of what it has left | Earthquake 42 > Dragon Dance 22 | passes **for the wrong reason**: stock's threat is an 80 BP *Normal* move worth 33.9%, so it refuses the setup as a 2HKO and never sees the priority kill at all |
| `race_stay_when_winning_on_speed` | dead heat, AI faster, healthy | stays; `shouldSwitch? = −10` | pass |
| `race_leave_when_losing_2hko_vs_3hko` | full HP, loses the race by a whole turn, **immune** bench available | `shouldSwitch? = −50`, `switch_scores` empty | **expected FAIL confirmed.** `shouldSwitch?` (`:13344`) has no matchup term; Reborn stays in a race it cannot win when nothing else is wrong with it |
| `race_switchin_prefers_bulkier_target` | Perish Song 1; two identical Mamoswine, one with an Assault Vest | **257 vs −175.8** | a 433-point gap from an item that only changes incoming special damage. The switch-in ladder reads the race hard |
| `race_switchin_outspeed_bonus` | two identical Ampharos, one with 252 Speed EVs (107 vs 75, foe 88) | **193 vs 115.8** | **+77** for outspeeding alone (`:11755-11764`, ×1.5 against ×0.75). Radical Red pays +14 for the same fact |
| `race_priority_steals_equal_race` | both at 25%, both AI moves lethal, AI slower | **Sucker Punch 569, Crunch 121** | priority as the tie-break of an equal race is the one part of the race Reborn already prices, and it prices it enormously (`priokill` `:598` + `suckercode` ×1.4 `:8342`) |
| `race_residual_counts_against_me` | 40% HP, badly poisoned (3/16), foe hits 30% | **Recover 148 > Strength 44** | `hpGainPerTurn` (`:10112`) is folded into the same gate as `maxdam`: here Reborn counts **turns**, not hits |

### What this decides for Phase B

- **Keep the `faster == false` clause on `setup_into_2hko`.** The plan left it open;
  `race_setup_when_2hkoed_but_faster` answers it. Reborn's refusal is a speed test, and
  a faster mon setting up into a 2HKO is behaviour the reference actively endorses (46,
  higher than the safe 3HKO board's 42).
- **Ship `losing_damage_race` OFF by default.** `race_leave_when_losing_2hko_vs_3hko`
  shows the reference does not leave, so the escape reason is Radical-Red-cited, not
  Reborn-cited. The plan pre-committed to this, and the switch programme was declared
  finished on evidence (`PORTABLE-AI-DIAGNOSIS.md` §4); it must not reopen by default.
- **The switch-in ladder is the best-supported consumer.** Both switch cards passed
  with large, clean margins, and the measured outspeed premium (+77 in Reborn's units)
  is within rounding of the +70 the plan proposed for `switchin_race`.
- **The setup rule should read the +1/+2 distinction as a Reborn quirk, not a rule.**
  Portable has no `stats[ATTACK]==1` equivalent and should not grow one; `setup_into_2hko`
  applies to any setup tag, which is a deliberate departure to record alongside the
  three 0.5.0 departures.
- **One card cannot be honoured as written.** The plan's `race_no_setup_into_priority_finisher`
  assumed "`maxdam` is the max over all moves so Shard is in it". On turn 1 it is not
  (fact 2). The rule can still be built — Portable's `incoming_by_move` carries the real
  move — but it is a place where Portable will be *more* informed than the reference,
  not a place where it is catching up.

Phase B shipped as core 0.6.0 — see the section above this one.

### Continued in `PORTABLE-AI-DIAGNOSIS.md` (2026-09-05)

Follow-ups 2 and 3 above are answered there from the existing traces: the remaining
gap is missing move rules, not switching. Headline: Portable clicks a recovery
move and dies that same turn on 25% of its heals (61% when below 25% HP) against
Reborn-Normal's 13%, and among KO moves it tiebreaks on slot order, never on accuracy,
priority or self-cost. A third candidate — `no_effective_move` letting walls leave —
was **retracted** on inspection: see that document's section 4. Reproduce with
`tools/policy_gaps.py {heal,finish,leave}`.
