# Portable AI for Realidea

Implementation status: installed and verified, opt-in, version 0.1.0 (2026-09-04).

> **This adapter is stranded at core 0.1.0 and the core is now at 0.6.2.** Everything
> below still describes what is installed in Realidea today — it has not been rebuilt
> since. Two things block a rebuild, and neither is hard, just ungated work: the full
> re-gate this file specifies (163/163 probe + paired gauntlet) has to be re-run against
> the new core, and the Realidea adapter does not yet export the evidence fields added
> from 0.2.0 onward (they default to 0 via `Model.number`, so the rules that consume them
> are silently inert here). Development since 2026-09-04 has all happened on the Reborn
> adapter — see `PORTABLE-AI-REBORN.md`, and `README.md` for the current state.

## What is installed

Realidea loads battle code from `Realidea V4.1/Data/Scripts.rxdata`. The build adds one
`Portable_AI` section at index 332, after `AI_Probe`, `Team_Overrides`, and `Level_Cap`,
and immediately before `Main`.

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
ruby _AI-Study/tests/test_portable_ai.rb
ruby _AI-Study/tests/test_realidea_adapter.rb
```

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

The full Realidea corpus contains 126 scenarios and 169 assertions. Five Reborn-field
scenarios are explicitly skipped, leaving 163 applicable assertions:

| AI | Tier-1 | Spearman vs Reborn | Action-type agreement |
|---|---:|---:|---:|
| Stock v16 + Clara | 143/163 | baseline | baseline |
| Portable AI 0.1.0 | **163/163** | **0.913** | **117/121 (96.7%)** |

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
4. Run the complete in-engine probe. All 163 applicable assertions must still pass, with
   five explicit field skips and zero missing/error/degenerate records.
5. Run the paired seeded gauntlet with no portable marker. Reject changes that reduce
   singles or doubles strength without a documented, reviewed reason.
6. Remove all `ai_probe.txt`, `ai_gauntlet.txt`, and `portable_ai.txt` trigger files, then
   smoke-test the normal title path.
7. Update `generated/portable_ai_results.json` hashes and metrics only from the exact
   artifacts used for the report.

At this handoff, all trigger files are absent, the injected section is installed but
inactive, the normal title path boots, and no high-severity review findings remain.
The working tree also contains pre-existing team-generation and study edits; future
agents should inspect the diff and avoid reverting unrelated work.
