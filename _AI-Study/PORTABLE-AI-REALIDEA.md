# Portable AI for Realidea

Implementation status: **installed at core 0.6.2 (2026-09-06), awaiting in-engine
re-verification.** Opt-in, and inert until its marker file exists.

> **The bundle in `Realidea V4.1/Data/Scripts.rxdata` is 0.6.2; the numbers further down
> this page are still 0.1.0's.** The adapter reached key parity with the shared core on
> 2026-09-06 (five commits, one per core version step), the whole automated gate passes,
> and `pack_rxdata --selftest` round-trips byte-identical — but every in-engine step
> needs Windows and has NOT been run against this build. Until it has, the probe and
> gauntlet tables in *Measured result* describe the 0.1.0 install and nothing else. The
> corpus was regenerated at the same time: **208 scenarios / 275 assertions, of which 198
> scenarios and 260 assertions are applicable here.** The old 126 / 163 figures are
> retired.

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

> Everything in this section is the **0.1.0** install measured on 2026-09-04, against the
> old 126-scenario corpus. It is kept as the baseline the 0.6.2 run has to be compared
> against, not as a description of what is installed now.

The corpus at the time contained 126 scenarios and 169 assertions. Five Reborn-field
scenarios were explicitly skipped, leaving 163 applicable assertions:

| AI | Tier-1 | Spearman vs Reborn | Action-type agreement |
|---|---:|---:|---:|
| Stock v16 + Clara | 143/163 | baseline | baseline |
| Portable AI 0.1.0 | **163/163** | **0.913** | **117/121 (96.7%)** |

The 0.6.2 corpus is **208 scenarios / 275 assertions**. Ten scenarios are skipped with a
reason — seven pin a Reborn field id, three pin a mechanic this engine does not have —
leaving **198 scenarios / 260 applicable assertions**. Five of the 213 Reborn cards
cannot be built against a v16 PBS at all (Heavy-Duty Boots, Clear Amulet) and are
dropped by `make_scenarios.py --drop-unresolved`, which prints each one.

The frozen gauntlet ran eight matchups at five identical seeds in stock and portable mode
(80 battles total, no errors):

| AI | Overall | Singles | Doubles |
|---|---:|---:|---:|
| Stock | 20/40 (50.0%) | 14/30 | 6/10 |
| Portable | **28/40 (70.0%)** | **20/30** | **8/10** |

Hashes and machine-readable totals are recorded in
`generated/portable_ai_results.json`; the pre-expansion stock baseline is preserved in
`generated/portable_ai_baseline.json`.

The checks establish decision and frozen-gauntlet improvement. They do not replace a
manual campaign playthrough of scripted bosses and unusual custom mechanics; the
fail-safe stock fallback remains enabled for that reason.

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

Everything above the in-engine line is done and committed. Outstanding, in order, and
all of it needs Windows:

1. Probe under Portable AI, then under stock, and grade both with `check_scenarios.py`
   against `scenarios_realidea.json`. This is the first time the 0.6.2 build meets the
   208-card corpus, so treat unexpected results as findings to read rather than as
   failures to patch around.
2. Paired gauntlet, then the ablation controls.
3. Rewrite *Measured result* from those artifacts and refresh
   `generated/portable_ai_results.json`.

At this handoff, all trigger files are absent, the injected section is installed but
inactive, and `pack_rxdata --selftest` round-trips byte-identical. The pre-change bundle
is `backups/realidea_Scripts.rxdata.pre-0.6.2`. The working tree also contains
pre-existing team-generation and study edits from other sessions; future agents should
inspect the diff and avoid reverting unrelated work.
