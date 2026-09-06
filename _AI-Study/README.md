# Pokémon Fangame Battle AI — Study Folder

Self-contained workspace for comparing battle AI across the games in `../`, and for
building one portable AI good enough to beat them. Started 2026-09-03. Covers **two
engines**: Essentials (Ruby) and CFRU (C, GBA).

The study has two phases, and they are still both live:

- **Phase 1 — teardown.** Read every game's AI out of its shipped build and write down
  what it actually does. Static analysis only, no playtesting. → `ANALYSIS.md`,
  `AI-PORTABILITY.md`, `TEAM-DESIGN.md`.
- **Phase 2 — build and measure.** One engine-independent core (`portable_ai/`) plus a
  thin per-game adapter, installed into a real game, then measured against that game's
  own AI in its own engine. → `SIM-SPEC.md` (the method), `PORTABLE-AI-REBORN.md` (the
  main log), `PORTABLE-AI-REALIDEA.md` (the first adapter).

## Where the project is — 2026-09-06

| | |
|---|---|
| Portable core | **0.6.2**, installed in Reborn Yang (opt-in, off by default) |
| Second adapter | Realidea v16, still at core **0.1.0** — needs the full re-gate before reinstall |
| Corpus | **213 cards / 281 assertions** in `scenarios.json` — 275 graded and passing, 6 N/A on the Portable side (`switch_score_gt` needs Reborn's party-indexed score array) |
| Unit tests | **161** green — `test_portable_ai.rb` 108, `test_reborn_adapter.rb` 53, `test_realidea_adapter.rb` 6 |
| Benchmark frame | 7 rosters × 60 = **420 battles**, `arms=normal_portable`, `schedule=normal_baseline`, `party_size=6` |
| Standing | 0.6.0 **197/420** → 0.6.1 **205/420** → 0.6.2 **203/420 (48.3%)** |

**How to read that 48.3%.** The schedule is balanced all-pairs, so the `normal_reborn`
arm — Reborn's own AI in *both* seats — must sit near 50% by construction, and measures
**52.7%** on the older 300-battle frame. Portable is therefore still a few points behind
Reborn-Normal, and the honest summary of the last three versions is: 0.6.1's Leech Seed
fix was a real +8 (p = 0.043), and 0.6.2's seven-fix batch is **flat on wins** (−2,
p = 0.83) while changing the course of 30% of battles. It is a behaviour-correctness
release, not a strength release.

Two older results that stay true and matter: **Intense's cheat set is worth nothing**
to Reborn (−7 vs its own Normal, p = 0.54) but costs *Portable* 23 battles (p = 0.017);
and **every win count in this repo recorded before 2026-09-05 is wrong** — see the
obedience banner at the top of `PORTABLE-AI-REBORN.md` before you quote any old table.

## Start here — reading order for a new contributor

1. **This file**, to the end. The traps section below is the part that saves days.
2. `PORTABLE-AI-REBORN.md` — the working log and the only doc that is current. Read its
   banner, "What is installed", "Run gauntlets in PARALLEL", "Traps for future agents",
   then jump to the newest `## Core version` section and read backwards as far as you
   care to. It is 2,500 lines and strictly append-forward: the newest section is the
   truth, earlier ones are the record of how it got there.
3. `ANALYSIS.md` — what each game's AI does, with `file:line` citations. This is the
   source of every idea the portable core has borrowed.
4. `SIM-SPEC.md` — why the probe/corpus/gauntlet method is shaped the way it is.
5. `AI-PORTABILITY.md` §4 — the line between core and adapter. Any new rule has to
   respect it or the core stops being portable.

`PORTABLE-AI-DIAGNOSIS.md` and `PORTABLE-AI-REALIDEA.md` are history; both carry
banners saying what in them has since been superseded.

## Folder map

```
_AI-Study/
├── README.md                      you are here
├── ANALYSIS.md                    the teardown — tables, per-game detail, file:line citations
├── AI-PORTABILITY.md              engine census + the core/adapter contract (§4)
├── SIM-SPEC.md                    the probe/corpus/differential method
├── TEAM-DESIGN.md                 trainer team composition + LLM team-generation spec
├── PORTABLE-AI-REBORN.md          THE working log: every version, every measurement, the backlog
├── PORTABLE-AI-REALIDEA.md        first adapter (core 0.1.0) — history
├── PORTABLE-AI-DIAGNOSIS.md       0.3.2 → 0.4 gap analysis — history, numbers superseded
│
├── portable_ai/                   the engine-independent core — this is the product
│   ├── model.rb                     snapshot/plan value types, Model.number defaults
│   ├── effects.rb                   canonical move knowledge as tags (no engine calls)
│   └── core.rb                      the scorer: score_move, score_switch, config keys
├── adapters/
│   ├── reborn/Portable_AI_Adapter.rb    snapshot builder — the only file that may touch Reborn
│   ├── reborn/Portable_AI_Gauntlet.rb   benchmark driver + CONFIG_OVERRIDE_KEYS
│   ├── reborn/AI_Harness.rb             the game-side batch runner (installed into Scripts/)
│   └── realidea/                        the v16 adapter, probe, level cap, team overrides
├── tools/                         build, corpus, run, compare, render (see below)
├── tests/                         ruby unit tests + test_tooling.py
├── generated/                     build output and ALL measurement artifacts (ndjson, readouts)
├── extracted/                     phase-1 evidence: manifests + dumped plugin source
└── backups/                       .orig copies of anything this study overwrote in a game
```

`scenarios.json` is the corpus with assertions; `scenarios_*.json` are the per-game
engine-readable variants. `probe_results_*.ndjson` / `tier2_*.json` at top level are
phase-1 artifacts; everything produced since lives in `generated/`.

## Requirements

- **Python 3** (3.12 here, 3.8+ fine) — **stdlib only**, by design. Nothing in `tools/`
  imports a third-party package, so there is no `requirements.txt`; keep it that way.
- **Ruby** (3.2 here) — runs `tests/*.rb` and the `ruby -c` check inside
  `build_portable_ai.py` (skippable with `--no-ruby-check`). The tests need `test/unit`,
  a bundled gem in Ruby 3.x; `gem install test-unit` if yours lacks it.
- **The game installs** and **Windows**, for anything that runs a battle — see
  "What is NOT in git" at the end of this file.

The system Ruby is *not* the Ruby the AI runs on: Reborn is mkxp-z (modern), Realidea is
RGSS 1.8-era. A test passing locally says the logic is right, not that the syntax is legal
in the host — that is what the corpus run in the real game is for.

## The measurement loop

This is the workflow. Every version in the log went through all of it; skipping steps 5
or 8 is how the two retracted findings in this repo happened.

```bash
cd _AI-Study

# 1. edit portable_ai/*.rb (rules) or adapters/reborn/*.rb (engine facts)
# 2. unit tests — seconds, run them constantly
ruby tests/test_portable_ai.rb && ruby tests/test_reborn_adapter.rb

# 3. build the single-file bundle and install it (also installs/repairs the harness)
python3 tools/install_reborn.py

# 4. corpus run (~90 s, serial, one pass over all 213 cards)
cd "../Reborn Yang/Reborn Yang"
printf 'mode=probe\nout=Data/ai_probe_results_portable.ndjson\n' > Data/ai_harness.txt
touch Data/portable_ai.txt          # omit this for a stock/reference run
./Game.exe
cd ../../_AI-Study
python3 tools/check_scenarios.py scenarios.json \
    "../Reborn Yang/Reborn Yang/Data/ai_probe_results_portable.ndjson"

# 5. THE CONTROL RUN. Same build, your new keys forced false, must reproduce the
#    previous version battle-for-battle — not "the same win total", the same battles.
#    Nothing below this line means anything without it.
printf 'mode=gauntlet\nschedule=normal_baseline\nparty_size=6\narms=normal_portable\n%s\n' \
    'your_new_key=false' > /tmp/cfg.txt
bash tools/run_gauntlet_parallel.sh generated/reborn_6v6_vNNNcontrol /tmp/cfg.txt set_c

# 6. the real sweep — 7 rosters, 4 workers, ~4x, verified byte-identical to serial
bash tools/setup_gauntlet_workers.sh 4          # once per checkout, ~119 MB each
printf 'mode=gauntlet\nschedule=normal_baseline\nparty_size=6\narms=normal_portable\n' > /tmp/cfg.txt
bash tools/run_gauntlet_parallel.sh generated/reborn_6v6_vNNN /tmp/cfg.txt \
     set_a set_b set_c set_d set_e set_f set_g

# 7. paired comparison against the previous version, over the identical frame
python3 tools/compare_versions.py \
    --before 'generated/reborn_6v6_v062_set_*.ndjson' \
    --after  'generated/reborn_6v6_vNNN_set_*.ndjson' \
    --arm normal_portable --label-before 0.6.2 --label-after NNN

# 8. find the NEXT round of bugs by reading battles, not source
printf 'mode=gauntlet\nschedule=normal_baseline\nparty_size=6\n%s\ntrace=true\n' \
    'arms=normal_reborn,normal_portable' > /tmp/cfg.txt   # both arms, same run
bash tools/run_gauntlet_parallel.sh generated/reborn_6v6_vNNNtrace /tmp/cfg.txt set_c
python3 tools/render_battle.py generated/reborn_6v6_vNNNtrace_set_c.ndjson \
    balance_vs_bulky 196613 --arm=normal_portable > generated/readouts/vNNN_....txt
```

Remove `Data/ai_harness.txt` and `Data/portable_ai.txt` from the game when you are done;
a normal boot should reach the title screen cleanly.

**Step 8 is the method that has actually worked.** Every one of the seven fixes in 0.6.2
was read off a turn-by-turn readout of a real battle, not proposed from the source; the
fixes proposed from source in earlier versions moved nothing. Render both arms from the
*same* traced run so the stock-Reborn readout is a same-run baseline, and prefix the
files with the version (`v061_`, `v062_`) — unversioned readouts have already been
mistaken for current ones once.

### Conventions the log enforces

- **One key per change.** Every new rule gets a `CONFIG_OVERRIDE_KEYS` entry in
  `adapters/reborn/Portable_AI_Gauntlet.rb`, so it can be ablated from
  `Data/ai_harness.txt` without a rebuild, and so all-off reproduces the prior version.
- **A corpus card that fails on the previous build.** A card that passes on both builds
  measures nothing. Two `entry_death` drafts did exactly that before the third one
  discriminated; the same lesson is written up under `leech_dead_into_a_grass_type`.
- **Unit tests build the adapter's own state**, not a hand-rolled stub, and assert both
  directions: the fix, and that the key off restores the old behaviour.
- **One roster is not a measurement.** 60 battles cannot see an effect this size. The
  0.6.2 batch looked like +1 on set_c alone and was −2 over all seven rosters.
- **Ship a batch, measure once.** Single rules have never moved wins detectably; 0.5.0
  and 0.6.2 are both deliberate batches with one paired number at the end.

## Traps that produce confidently wrong answers

Phase-2 traps (the full list is under "Traps for future agents" in
`PORTABLE-AI-REBORN.md` — read it, it is longer than this):

- **`PokeBattle_Battle#initialize` rewrites `obedient` on the left party** from the badge
  count. Every gauntlet ever run before 2026-09-05 had a disobedient reference seat, and
  every win count from before then is wrong. Any new harness that builds parties by hand
  must set `obedient` *after* construction.
- **The probe's stock records are roulette-sampled.** Reborn picks randomly among
  top-window scores, so re-runs legitimately differ. Grade with `check_scenarios.py`;
  never diff raw records and call it a regression.
- **The gauntlet's trainers run at skill 100** in Normal *and* Intense — trainer type 0's
  skill column is blank in the PBS text and the compiler substitutes the money column.
  Check `Data/trainertypes.dat`, not the PBS.
- **Reborn runs modern Ruby (mkxp-z); Realidea is RGSS 1.8-era.** Do not carry syntax in
  either direction.
- **`pbRoughDamage` reads the Intense cheat switch.** Never call it outside
  `with_neutral_estimation` — fair information is the entire point of the benchmark.
- **Run gauntlets in parallel.** This has been rediscovered the hard way more than once
  *after* reading a note saying the parallel driver existed.

Phase-1 traps:

- **The plugin folder is not what runs.** `PluginManager.needCompiling?` opens with
  `return false if !$DEBUG`, and `runPlugins` then evals every entry in
  `Data/PluginScripts.rxdata` unconditionally. In a release build the compiled bundle is
  authoritative and the folder is cosmetic — Ashen Frost's folder advertises Phantombass
  AI, and the shipped bundle contains Consistent AI and no Phantombass code at all.
  Always check the manifest in `extracted/`.
- **Do not scan for zlib headers.** `.rxdata` is Ruby Marshal 4.8. A header scan looks
  like it works and silently drops sections — it missed an entire 15,000-line plugin on
  the first pass. Use `tools/marshal_rb.py`.
- **GBA hacks need a completely different route.** Don't decompile the ROM; clone the
  engine (CFRU) and find the undefined `extern`s, which are the only parts the hack keeps
  private. See `extracted/unbound-MANIFEST.txt`.
- **Before calling something a cheat, read the enclosing handler.** An AI reading
  `battle.choices` may be emulating a mechanic that legitimately depends on turn order
  (Stakeout, Zoom Lens). Phantombass's reads are all of that kind; Consistent AI's are
  not — it checks whether you picked Wide Guard at 30/50/70% by difficulty.

```bash
# phase-1 recipes
cd tools
python3 extract_rxdata.py "../../Ashen Frost - Windows/Data/PluginScripts.rxdata" /tmp/x --list
python3 extract_rxdata.py "../../Realidea V4.1/Data/Scripts.rxdata" ./out   # v16: one bundle
```

| Grep pattern | Tells you |
|---|---|
| `OMNISCIENT_AI` | Phantombass-family knowledge switch |
| `PBTrainerAI\.` / `has_skill_flag?` | skill gating (v16-v20 / v21 style) |
| `pbAIRandom` | is move choice deterministic or a roulette |
| `@battle.choices[` | possible turn-prediction cheat — **verify, see caveat above** |
| `!pbOwnedByPlayer` | asymmetric enemy-favouring mechanics |
| `revealedMoves` | whether a knowledge model exists and who it serves |

## What is open

**Next up — the five valuation A/Bs**, items 7-11 of the readout-pass backlog in
`PORTABLE-AI-REBORN.md`. They were deliberately held out of 0.6.2 because they are
valuation changes, not bugs, and mixing them in would have made the batch unmeasurable.
Each needs its own key and its own A/B: sleep and Toxic priced +25 like any status;
Stealth Rock a flat 100; the heal loop at low HP; `boosted_foe_holds_ground` blocking the
one switch that saves the mon; a faster 2HKO race abandoned on the one-hit flag.

**Also queued, in the same file:**

- A **per-key ablation of the seven 0.6.2 fixes** over the 420-battle frame. Seven moved
  together for −2, so none of them can be attributed. `entry_death` is the prime suspect:
  the only one of the seven that was tuned rather than copied from the engine, and the
  only one that can refuse a switch outright.
- **Whole-battle habits** — hazard value when the foe's boosts cannot reach the actor,
  staying in when the matchup is safe, closing with sleep plus recovery. Read off the
  Reborn-right readouts, where Reborn switched 3 times in 28 turns to Portable's 8.
- **The damage race as a hits-to-KO ladder** settled in move order, including priority.
  0.6.0 built the helper; the `matchup` term still does not consult it. Radical Red's
  post-KO switch-in score is the most compact statement of the same idea.
- **Breadth as tables, round two** — the remaining `effects.rb` / ability rows sketched
  at the end of the 0.5.0 backlog.
- **Realidea is stranded at core 0.1.0.** Rebuilding it needs the full gate in
  `PORTABLE-AI-REALIDEA.md` (163/163 probe + paired gauntlet), and its adapter does not
  yet export the evidence fields added since 0.2.0.

**Phase-1 threads still open:**

- **Unconfirmed:** "Ashen Frost runs Consistent AI" is inferred from the bundle plus the
  `$DEBUG` check, not observed. Booting it and reading the `Loaded plugin: ==<name>==`
  console lines would settle it in one line.
- **Unconfirmed:** the Unbound write-up reads public CFRU @ `b637a27` (Jan 2025), but the
  ROM is from Mar 2023 and was built against a private pinned snapshot. Also unresolved:
  how Unbound's four UI difficulties map onto CFRU's `OPTIONS_*_DIFFICULTY`, which
  several cheats key off.
- **Grueling Gold** (partially examined 2026-09-04): v20.1, compiled bundle contains
  Phantombass AI 1.0 — the full 15,145-line build — plus Deluxe Battle Kit, two of whose
  scripts define `pbChooseMoves`/`pbGetMoveScore`. Three layers contend for the same
  methods. Deserves a proper `ANALYSIS.md` section.
- Not yet examined: Bloodborne, Pokemon Empire (+ Expanded, both v17.2), Slipstream RL.

## What is NOT in git — read this before cloning somewhere else

The root `.gitignore` is an allowlist: only `_AI-Study/` and the two Realidea files this
study modifies are tracked. Everything else in `../` — every game install, including
`Reborn Yang/` — is deliberately out.

What you still need locally:

1. **The game installs**, at the paths `../` uses today. Tool defaults are relative to
   them (`render_battle.py` reads `../Reborn Yang/Reborn Yang/PBS/PBS`).
2. **`.gauntlet-workers/`**, rebuilt locally with `tools/setup_gauntlet_workers.sh 4`.
   Never copied — the driver re-syncs `Scripts/` from the master on every run precisely
   so a worker cannot execute a stale bundle.

Everything the study *wrote* is in the repo, including the game-side pieces, so a fresh
checkout only has to be pointed at a game:

```bash
python3 tools/install_reborn.py                  # or --game "/path/to/Reborn Yang"
python3 tools/install_reborn.py --check          # report only, changes nothing
```

That builds the bundle and installs four things: `Scripts/AI_Harness.rb` (the batch
runner — canonical copy lives at `adapters/reborn/AI_Harness.rb`), `Scripts/Portable_AI.rb`
(built from `portable_ai/` + `adapters/reborn/`), two entries in `Data/!script_order.csv`
before `Main`, and one opt-in hook in `Scripts/Main.rb`. It is idempotent, so re-run it
after every rebuild; the host files' pristine originals are in `backups/`, and both edits
are inert until `Data/ai_harness.txt` exists.

**`adapters/reborn/AI_Harness.rb` is the canonical copy — edit it there, not in the game
tree, and re-run the installer.** The game copy is a build artifact like `Portable_AI.rb`.

`generated/` **is** tracked, so all the measurement artifacts, readouts and ndjson from
every run are in the repo alongside the code that produced them.
