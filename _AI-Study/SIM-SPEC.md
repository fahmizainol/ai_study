# AI Decision Probe & Differential Harness — Specification

Draft 1, 2026-09-03. Companion to `ANALYSIS.md`.

**Purpose.** Drive each game's battle AI over a shared corpus of battle positions, log its
decisions in a canonical form, and compare across AIs — so that porting a stronger AI into
a host game (Realidea first) can be *validated* rather than eyeballed.

---

## 0. Prior art — do not build this from zero

Reborn Yang already ships two thirds of it. Read these before writing anything:

| Component | Location | What it gives you |
|---|---|---|
| Headless battle harness | `Reborn Yang/Scripts/PokeBattle_TestEnvironment.rb` (1,928 lines) | `pbCommandPhaseTEST` / `pbAttackPhaseTEST` replace the interactive phases so both sides are AI-driven; `pbSetSeen` and the display calls are neutered |
| Mass AI-vs-AI runner | **`allTrainersBattle:613`** | Round-robins trainer lists, writes CSV, survives exceptions mid-run. **Use this one** — `bestTrainersBattle:653` calls `load_data("battle")` and no such file ships (§0.1) |
| Battle primitive | `idontwanttobreakperryscode:469` | Builds a `PokeBattle_Battle` from two trainer records and runs it to completion. **Forces every mon to level 100** — ideal for the frozen gauntlet, removes the level-curve confound |
| Field sweep | `pbAllFields:872`, `$game_variables[:Forced_Field_Effect]` | Re-runs a matchup under every field |
| **Structured decision record** | `PokeBattle_AI_2.rb:17533` `PokeBattle_AI_Info` | Per battler: `move_names`, `init_score_moves`, `final_score_moves`, `switch_scores`, `items_scores`, `should_switch_score`, `expected_damage`, `chosen_action`, `field_effect`, `battler_hp_percentage` |

**Known gap to close first:** the two systems are currently mutually exclusive. Both
`bestTrainersBattle:654` and `allTrainersBattle:614` set `$INTERNAL=false`, and
`logAIScorings` opens with `return if !$INTERNAL`. So today you get *either* mass outcomes
*or* per-decision scores, never both. Decoupling the log gate from `$INTERNAL` is the first
code change.

The canonical log schema in §4 is deliberately shaped to match `PokeBattle_AI_Info`, so the
Reborn adapter is close to a field rename.

### 0.1 Verified against real data (Phase 0 spike, 2026-09-03)

`Reborn Yang/Data/debuglog.txt` already contains **1.15 MB of real AI decisions** from prior
play. `tools/parse_reborn_log.py` parses it into §4 records:

```
decision blocks      : 417        switch scores : 1228
  with move scores   : 417        item scores   : 395
  with chosen action : 354        moves rescored init->final : 982
chose own top-ranked move  : 303/354 (85.6%)
```

Two results worth keeping:

- **The schema survives contact with real data.** Init *and* final scores, per move, per
  target, plus item scores, switch scores and chosen action — all already emitted. The
  Reborn adapter is a format translation, not new instrumentation.
- **85.6% top-1 agreement independently confirms the static reading.** `PokeBattle_AI_2.rb:1658-1676`
  roulettes over moves within 5% of max with the best pushed twice; ~86% is what that
  predicts. Log-derived behaviour and source-derived behaviour agree.

**Log-ordering trap (cost an hour, will cost you one too).** `[Prefer X]` and the
switch-candidate blocks are written by `PBDebug.log` *immediately*, while `logAIScorings()`
buffers an entire block and dumps it afterwards. **Both therefore precede the
`Scoring for battler` block they belong to.** Naive sequential parsing attaches them to the
previous decision and silently reports ~38% top-1 agreement and zero switch scores. Attach
forward, not backward.

---

## 1. Goals / non-goals

**Goals**
- G1 — Given a battle position, capture *why* an AI chose what it chose (full score vectors,
  not just the action).
- G2 — Compare two AIs on the same position and quantify divergence.
- G3 — Validate a port: assert the uplifted host AI reaches reference-quality decisions.
- G4 — Measure whether the port actually made the game *harder*, independent of similarity.

**Non-goals**
- N1 — A standalone cross-engine battle simulator. That is writing Pokémon Showdown; the
  AIs are welded to their own engine's object model and are not liftable.
- N2 — Full turn resolution for Tiers 1–2. **The probe scores a position and stops.** It
  never advances the battle. Only the §7 strength benchmark needs real battles.
- N3 — Comparing across engine *families* on exact equality. See §3.

---

## 2. The constraint that shapes everything

The AIs are not portable *between* engines, so the harness cannot host two AIs in one
process. Class names, constants and effect indices all differ by generation:

| | Realidea | Hegemony | Ashen Frost | Ancient Plat. | Reborn Yang |
|---|---|---|---|---|---|
| Essentials | v16 | v19 | v20.1 | v21.1 | Reborn E19 |
| Battle class | `PokeBattle_Battle` | `PokeBattle_Battle` | `Battle` | `Battle` | `PokeBattle_Battle` |
| Move constants | `PBMoves::TACKLE` | `PBMoves::TACKLE` | `:TACKLE` | `:TACKLE` | `PBMoves::TACKLE` |
| Plugin system | **none** | yes | yes | yes | none (plaintext `Scripts/`) |

So the architecture is **N in-engine probes + 1 shared corpus + 1 shared differ**. Each game
gets a thin adapter; everything expensive is shared.

**Dependency:** Realidea is v16 with all code inside `Data/Scripts.rxdata` and no plugin
folder. The loader-stub work (Phase 0 of the porting plan) is a hard prerequisite — you
cannot install a probe into Realidea until you can write code into it.

---

## 3. Success criteria — three tiers, and why "matches the reference" is the wrong bar alone

The intuition behind this project — *if the ported AI decides what the harder AI decides,
the port worked* — is right in spirit but is a **regression test applied to a
cross-engine problem**. Exact match is not achievable across games, for four reasons that
have nothing to do with port quality:

1. **Different game data.** Realidea's movesets, TM access, ability spreads and species
   roster differ from Hegemony's. Some positions cannot be instantiated in both.
2. **Different mechanics.** v16 → v21 changed crit tables, burn damage, sleep counters and
   damage rounding. A *correct* port still faces a different board.
3. **Stochastic selection.** Reborn roulettes over the top 5% with the best move
   double-weighted; Realidea rolls a weighted die over everything; PBAI 9.0 is
   deterministic. Same position, different action, same AI.
4. **PBAI ignores skill entirely** while Realidea's trainers carry skill values — so gating
   diverges by design.

Hence three tiers, used for different questions:

### Tier 1 — Property assertions *(primary; portable across all engines)*
Hand-authored positions with an unambiguous correct answer. Assert **properties**, not
equality:

- lethal move available and AI moves first → must pick a lethal move
- target immune to type X → must not pick an X move
- lethal incoming priority, bench holds a resist → `should_switch_score` must exceed best move score
- opponent cannot damage it and it holds a setup move → must set up
- hazards up, opponent bench is grounded and hazard-weak → must not spin them away

This is what actually validates a port, and it is the only tier that is engine-neutral by
construction. **Build this first.**

### Tier 2 — Rank correlation *(cross-engine comparison)*
Do not compare chosen actions. Compare the **ordering** of the score vector: Spearman ρ
between the reference AI's move ranking and the candidate's on the same position. Tolerant
of numeric drift, sensitive to structural divergence. Report per-position ρ, flag
ρ < 0.6, and always report the top-1 agreement rate alongside it.

### Tier 3 — Exact match against golden logs *(same engine only)*
Byte-identical score vectors, same seed, same engine, before vs after a change. This is a
**regression** guarantee — "my Phase-2 layer port didn't disturb Phase-1 behaviour" — and it
is the only place exact equality is the right bar.

---

## 4. Canonical decision record

One JSON object per AI decision. Field names chosen to map onto `PokeBattle_AI_Info`.

```json
{
  "schema": 1,
  "scenario_id": "lethal_priority_01",
  "engine": "realidea-v16",
  "ai": "stock-v16",
  "ai_version": "4.1",
  "seed": 20260903,
  "skill": 100,
  "difficulty": "normal",
  "actor": {
    "side": "opponent", "index": 1, "species": "GARCHOMP",
    "hp_pct": 64.2, "item": "LIFEORB", "ability": "ROUGHSKIN",
    "status": null, "stages": {"atk": 1, "spe": 0}
  },
  "context": { "field": "NONE", "weather": "NONE", "turn": 3 },
  "move_scores": [
    {"move": "EARTHQUAKE", "init": 142, "final": 142, "rank": 1,
     "expected_damage_pct": 88.0, "target": 0},
    {"move": "SWORDSDANCE", "init": 90, "final": 5, "rank": 3}
  ],
  "switch_scores": [{"slot": 2, "species": "ROTOM", "score": 88}],
  "item_scores":   [{"item": "HYPERPOTION", "score": 40}],
  "should_switch_score": -40,
  "chosen": {"type": "move", "move": "EARTHQUAKE", "target": 0}
}
```

Rules:
- `move_scores` is **mandatory and is the primary artifact**. `chosen` is secondary because
  it is stochastic in three of the five AIs.
- Record both `init` and `final` where the AI has a compression/adjustment pass (Reborn
  `:1658-1676`, `checkCounter`). Divergence between the two is itself a useful signal.
- Species/move/item are canonical uppercase internal names. Per-game alias maps
  (`adapters/<game>/aliases.json`) resolve renames; an unresolvable name marks the scenario
  `skipped`, never silently dropped.
- Unsupported concepts are `null`, not `0` — `field: null` for a non-Reborn engine must not
  compare equal to `field: "NONE"`.

---

## 5. Scenario format

Engine-neutral, minimal, explicit. Stats are given as final computed values wherever
possible so cross-generation stat formula drift cannot contaminate the comparison.

```json
{
  "id": "lethal_priority_01",
  "tags": ["tier1", "switching", "priority"],
  "format": "single",
  "context": { "field": null, "weather": "NONE", "turn": 3 },
  "sides": {
    "ai":     { "active": {...}, "bench": [{...}], "hazards": [], "screens": [] },
    "player": { "active": {...}, "bench": [{...}], "hazards": ["STEALTHROCK"] }
  },
  "ai_skill": 100,
  "assertions": [
    {"kind": "must_switch"},
    {"kind": "must_not_choose_move", "value": "EARTHQUAKE"}
  ]
}
```

`assertions` are only read by Tier 1. Tier 2/3 ignore them.

**Corpus sizing.** Target ~60 hand-written Tier-1 positions covering: lethal/kill priority,
type immunity, switching under threat, hazard set/removal, setup timing, status usage,
item usage, doubles targeting and redirection. Hand-written beats generated here — the value
is in the assertion, and assertions cannot be generated.

---

## 6. Per-engine adapter contract

Each game gets a probe of roughly two files. It must expose exactly three entry points:

```ruby
module AIProbe
  # Materialise a scenario hash into this engine's battle objects.
  # Returns a battle in a state where the AI is about to choose for the AI-side active mon.
  def self.load_scenario(hash) -> battle

  # Run ONLY the AI's scoring pass. MUST NOT execute the action or advance the turn.
  # Returns a decision record hash matching §4.
  def self.probe(battle) -> Hash

  # Iterate a corpus file, emit newline-delimited JSON.
  def self.run_corpus(in_path, out_path)
end
```

Per-game notes:

| Game | Effort | Notes |
|---|---|---|
| **Reborn Yang** | lowest | `PokeBattle_AI_Info` already *is* the record; reuse `processAIturn`'s per-battler loop. Decouple logging from `$INTERNAL` first |
| **Hegemony / Ashen Frost** | low | PBAI's `PBAI.move_choice` already builds a full score list before selection |
| **Ancient Platinum** | low | v21 `Battle::AI` exposes scores natively |
| **Realidea** | **highest** | Blocked on the v16 loader stub. Scoring and selection are entangled around `085_PokeBattle_AI.rb:3937-4000`; the probe needs a score-only path that stops before `pbAIRandom(totalscore)` |

That Realidea entanglement is not wasted work — splitting scoring from selection is
**exactly** the Phase-1 refactor the porting plan already calls for. Do it once, get both.

---

## 7. Metrics

Two independent signals. Similarity is a proxy; strength is the actual goal.

**Similarity (Tiers 1–3)**
- Tier 1: assertion pass rate. Target 100% on the reference AI first — *if the reference
  fails an assertion, the assertion is wrong*, and that is a valuable finding about the
  reference.
- Tier 2: mean Spearman ρ, top-1 agreement rate, and a list of worst-divergence positions.
- Tier 3: exact-match rate against golden logs; any mismatch is a build failure.

**Strength (independent of similarity)**
Reuse `bestTrainersBattle` directly: round-robin the modified AI against a **fixed frozen
gauntlet** of trainer teams, N runs with logged seeds, report win rate and mean turns-to-win.
Run it before and after each change.

This matters because the stated goal is "make Realidea harder", and decision-similarity is
only a proxy for that. A port can match the reference closely and still lose more, or diverge
and win more. **Win rate against a frozen gauntlet is the metric that answers the actual
question.** Similarity tells you *why* it moved.

---

## 8. Determinism

- Seed the RNG explicitly per scenario; record the seed in every log line.
- `move_scores` must be captured **before** any stochastic selection step.
- Damage rolls must be pinned during probing — Ashen Frost exposes
  `$PokemonGlobal.damage_variance`; elsewhere force the roll to its midpoint in probe mode.
- Probe mode must be a distinct global from `$DEBUG`/`$INTERNAL`, since those also gate
  plugin recompilation (see the Ashen Frost finding) and mass-run logging.

---

## 9. Phasing

| Phase | Deliverable | Gate |
|---|---|---|
| **0** ✅ | **DONE 2026-09-03 — verdict: GO.** See §9.1 | **Go/no-go for the whole project** |
| **1** 🟡 | **Batch runner + decision logging DONE 2026-09-03** (§9.2). `probe()` still open | A real log from a real position — **met** |
| **2** ✅ | **DONE 2026-09-03 — 73 scenarios, 89/89 on reference, incl. 2 forced switches (§9.3)** | 100% pass on reference — **met** |
| **3** ✅ | **DONE 2026-09-03 — `ai_diff.py` + Hegemony/PBAI adapter; ρ=0.852 (§9.4)** | Two AIs compared on one corpus — **met** |
| **4** ✅ | **DONE 2026-09-03 — Marshal writer + Realidea adapter; 3 AIs on one corpus (§9.6)** | Realidea probeable — **met** |
| **5** | Frozen gauntlet + win-rate benchmark; baseline Realidea before any AI change | Baseline recorded |

Phases 1–3 are useful on their own even if the Realidea port never happens — they turn the
study from static reading into measurement.

### 9.1 Phase 0 spike result — **GO**

Every prerequisite verified empirically on this machine. Nothing in the game install was
modified.

| Check | Result |
|---|---|
| Display available | ✅ WSLg (`DISPLAY=:0`, `/mnt/wslg` present) |
| WSL → Windows interop | ✅ launches `.exe` from WSL |
| **Engine boots** | ✅ mkxp-z, RGSS v1, real GL context (Radeon RX 6700 XT). Ran 45 s clean; exit 124 = killed by timeout, not a crash |
| Console capture from WSL | ✅ engine stdout reaches the WSL shell |
| File log sink | ✅ `Data/debuglog.txt` via `PBDebug.log` — no stdout dependency needed |
| Decision logging works | ✅ 1.15 MB of real logs already on disk; 417 decisions parsed (§0.1) |
| `unhashTRlist` | ✅ defined at `Reborn/RebornScripts.rb:875`, reads `Data/trainers.dat` (517 KB, present) |
| `$Trainer` for the harness | ✅ save present — `Saved Games/Reborn Yang/`, 192 h / 16 badges |
| Injection point | ✅ `mkxp.json` supports `customScript` / `preloadScript`; neither currently active |
| `bestTrainersBattle` | ❌ **dead** — `load_data("battle")`, no such file ships. Use `allTrainersBattle` |

**Windows-only build.** No Linux AppImage ships despite the Readme mentioning one, so the
runner executes `Game.exe` through WSL interop. A real window appears — acceptable, since
nothing here needs true offscreen rendering. Treat WSL as the analysis side and Windows as
the execution side.

**The one genuine gap, and it is Phase 1 not Phase 0.** `idontwanttobreakperryscode:469`
calls `pbNewBattleScene` and `$Trainer.party`, so the harness only runs from an
**already-loaded game state** — it cannot be invoked at boot. Automating it needs a script
that loads a save programmatically, calls `allTrainersBattle`, and exits. That is the first
Phase 1 task and it requires writing into the install, so it wants explicit sign-off.

---

### 9.2 Phase 1 result — batch runner live

**Working end to end:** boot → N AI-vs-AI battles → outcomes CSV **and** structured
decision records → parsed JSON with real names.

Changes to the Reborn Yang install (3, all revertible; backup at `Reborn Yang bak/`):

| File | Change |
|---|---|
| `Scripts/AI_Harness.rb` | **new** — the runner |
| `Scripts/Main.rb` | boot loop wrapped in `if AIHarness.requested? … else … end` |
| `Data/!script_order.csv` | `AI_Harness` inserted before `Main` |

**Opt-in by file existence.** No `Data/ai_harness.txt` → the game boots normally
(verified: clean title screen, zero harness output). Config is `key=value`:
`pairs`, `doubles`, `log_decisions`, `seed`, `field`, `filter`, `out`.

Measured: 1,957 eligible trainers; battles run 0.5–6.4 s each; 5 battles produced
**102 structured scoring blocks**; parse yields 97 records, 46 with full move vectors and
112 init→final rescores.

**Five defects found and fixed along the way** — all of the "silently wrong" kind:

1. **Inverted win column.** `idontwanttobreakperryscode(x, y)` passes **y** as party1 and
   returns `decision==1`, which `PokeBattle_Battle.rb:4633` defines as *party1* winning —
   so it means "**y** won". Labelling it `a_won` inverts every result. A strength benchmark
   built on that would have been perfectly backwards. Now commented at the call site.
2. **`logAIScorings` never fires in the test path.** It is called from
   `PokeBattle_Battle.rb:5147` in the normal command phase; `pbCommandPhaseTEST` replaces
   that phase and its equivalents are commented out (`PokeBattle_TestEnvironment.rb:196-201`)
   with a stale signature that would raise. The harness re-attaches it by aliasing
   `pbCommandPhaseTEST`, and logs **both** sides (unlike the normal flow, which skips
   player-owned battlers).
3. **Unguarded nil map.** `PokeBattle_Field.rb:55` guards `$game_map`, `:63` does not —
   fatal with no map loaded. Supplied `AIHarnessNullMap` rather than patching their file.
4. **All names blank.** `PBMoves/PBSpecies.getName` go through MessageTypes' *indexed*
   tables, populated only by `pbSetTextMessages` (compile path; it raises here because the
   compiler tables are absent). Hashed lookups like `TrainerNames` work, which is the
   misleading part — trainer names resolve while move names do not. Fix: the harness logs
   `mv:243` / `spc:471` / `itm:543` and `parse_reborn_log.py --pbs` resolves them offline
   from plaintext PBS. Verified: `spc:471`→Glaceon, `itm:543`→Assault Vest, `mv:243`→Ice Beam.
5. **`def f(*a) 0 end` is a Ruby SyntaxError** (needs `;`). The whole script failed to eval,
   so even the `Main.rb` rescue saw nothing — symptom was a silent early exit with no
   output. If the harness ever produces *zero* output, suspect a syntax error first.

**Still open in Phase 1:**

- `probe()` — score a constructed position without advancing the battle. Not started; it
  is what Phase 2's scenario corpus needs.
- `chosen` action is blank in harness logs. `[Prefer X]` is built from
  `battler.moves[i].name` inside the AI's own logging, which hits the same blank-name
  problem; the ID repopulation covers `move_names` but not that line. Move *rankings* are
  intact, so Tier-2 rank correlation already works — only top-1 agreement is affected.
- `logAISwitching` never fires: it is called from `PokeBattle_ActualScene.rb:3577`, which
  the test path bypasses. Switch scores still appear in raw PBDebug lines.
- No system Ruby on this machine, so scripts cannot be syntax-checked before launching the
  engine. Worth installing one.

### 9.3 Phase 2 result — probe + Tier-1 corpus live

`probe()` is built and the assertion pipeline runs end to end:

```
make_scenarios.py  →  Data/ai_scenarios.txt  →  [engine probe]  →  ai_probe_results.ndjson
                   ↘  scenarios.json (assertions) ────────────→  check_scenarios.py
```

**`probe()` scores a position and stops.** `processAIturn` ends in `chooseAction`, which
only *registers* intent into `@battle.choices` — nothing executes. So the decision is read
straight from `battle.choices[1]`, which also **solves the blank-`chosen` problem** from
Phase 1: no log scraping, no name resolution needed for the action.

**Result: 19/19 assertions pass on the reference AI**, and a negative control (demanding
Earthquake into a Flying target) correctly fails 2/2 and exits 1 — so the gate is
sensitive, not vacuous.

Reference behaviour is archived in `probe_results_reference.ndjson`. Highlights, all
consistent with the static reading in `ANALYSIS.md`:

| Scenario | Evidence |
|---|---|
| Earthquake into Skarmory | scores **0**; picks Dragon Claw (15) |
| Thunderbolt into Garchomp | scores **0**; picks Flash Cannon (37) |
| Body Slam into Gengar | scores **0**; picks Earthquake (91) |
| Recover at 15% HP | scores **297** vs Body Slam 80 |
| Swords Dance vs a foe that cannot hurt it | 55 vs Body Slam 16 |
| Will-O-Wisp on an already-burned target | scores **0** |
| Same position, field 6 vs no field | Earthquake **110 → 51** |

That last row is the useful one: it empirically confirms the 704 `PBFields::` references
found by static analysis actually move scores, and it is why §5 pins `field` explicitly.

**Two traps found building this:**

1. **The AI must exist before `pbSendOut`.** Send-out calls `@ai.addMonToMemory`
   (`PokeBattle_Battle.rb:2021`) to populate the knowledge model; constructing
   `PokeBattle_AI` afterwards gives `NoMethodError … for nil`.
2. **An unpinned field silently contaminates every scenario.** With no map loaded, battle
   setup derives a field from the null map's battleback and lands on field **35**, not 0.
   Scores shifted (Ice Beam 111 → 105) once pinned. Any corpus built without pinning the
   field would have been quietly measuring the wrong position.

**Corpus scaled to 70 scenarios / 86 assertions, 86/86 passing** (2026-09-03). Coverage:
kill recognition 6, type immunity 13, ability immunity (Levitate) 1, effectiveness
ordering 12, status immunity 5, redundant status 5, setup/healing 11, switching 9,
field sensitivity 5, misc 3.

| Assertion kind | Count |
|---|---|
| `score_gt` | 33 |
| `must_not_choose_move` | 31 |
| `must_choose_any` (documentary, no constraint) | 7 |
| `must_choose_move_in` | 6 |
| `must_not_switch` | 5 |
| `must_consider_switch` | 4 |

Negative control on the full suite (inverting three immunity assertions) fails 3/3 and
exits 1, so the enlarged gate is still sensitive.

**Six assertions were wrong, not the AI.** Every failure in the scale-up was my error, and
two failure modes are worth remembering because both *look* like AI bugs:

1. **Degenerate scenarios (5 of 6).** Four redundant-status scenarios gave the AI a backup
   move the target was immune to (Shadow Ball into a Normal-type), so *every* move scored
   0 and selection was a coin flip. A fifth v1 scenario had the identical flaw and had been
   **passing by luck** in the earlier 19/19. `check_scenarios.degenerate()` now warns
   whenever all moves tie and a choice-assertion is present. **Always give the AI a viable
   alternative, or `must_not_choose_move` tests nothing.**
2. **Over-specified kill assertions.** `kill_recognised_raises_score` demanded Earthquake;
   the AI took Dragon Claw. Both scored **121** — once a move is lethal the AI does not
   score extra damage, which is correct (overkill has no value). Fixed by adding Protect
   and asserting "take *a* kill, do not Protect".

And one where the AI was simply right: `heal_beats_weak_attack` scored Recover **0** on a
Starmie at 10% facing Power Whip — 2× into a frail target kills through the heal, so
healing is futile. Contrast `heal_at_low_hp`, where Blissey at 12% vs Psychic scores
Recover **297**. The AI distinguishes survivable from unsurvivable damage. My scenario had
called a super-effective hit "weak".

**Forced switches — gap closed.** Corpus is now **73 scenarios / 89 assertions, 89/89
passing**, including two `must_switch` scenarios where the AI genuinely switches out.

Switching needs *both* conditions at `chooseAction:1577` —
`shouldswitchscore > best move score` **and** `switchscore.max > 100`:

| Scenario | sss | pivot score | action |
|---|---|---|---|
| `switch_forced_snorlax_to_ghost` | 325 | 104.3 | **switch** |
| `switch_forced_tyranitar_to_ghost` | 405 | 104.3 | **switch** |
| `switch_wanted_but_pivot_below_gate` | 100 | 93.8 | move |

The recipe: cripple the active mon's offence with `-6` stages (`shouldSwitch?` pays
−25/stage, `:13394`), keep HP **above 30%** (below that it subtracts 100, `:13378`), and
give the bench a pivot that is **immune to the foe's attack**. Merely "fine" pivots stall
around 94–99 and never clear the gate — "wants to switch" and "switches" are two
different bars, which the third row documents deliberately.

**A pivot must be safe against the foe's STAB TYPES, not just its known moves.** A Levitate
Flygon pivoting into a Garchomp that only has Earthquake scored **−300**, not the expected
strong positive. Reason: when the AI has no known damaging move for a foe it invents an
80-BP STAB move of the foe's *type* (`PokeBattle_Move_FFF`, `PokeBattle_AI_2.rb:17454`),
so it assumed a Dragon attack — and Flygon is 2× weak to Dragon. That is the AI hedging
against unseen moves rather than assuming the foe has only what it has shown, and it is
the third time in this corpus that an apparent AI failure turned out to be a correct
behaviour I had not accounted for.

### 9.4 Phase 3 result — two AIs on one corpus

`tools/ai_diff.py` (Tier 2) and a full Hegemony/PBAI adapter are live.

**Hegemony is the right PBAI target, not Ashen Frost.** AF ships PBAI 9.0 in its plugin
*folder* but the compiled bundle runs Consistent AI (ANALYSIS.md "plugin/bundle mismatch");
Hegemony's `Data/PluginScripts.rxdata` contains Phantombass AI 1.0.0 and the boot log shows
`[Phantombass AI]` loading — observed, not inferred.

**Adapter is 2 files, ~330 lines, opt-in via `Data/ai_probe.txt`:**
`Data/Scripts/999_Main/998_AI_Probe.rb` (new) + a 14-line branch in `999_Main.rb`.
Backup: `_AI-Study/backups/hegemony_999_Main.rb.orig`.

Setup is trivial here because PBAI does the wiring itself: it aliases
`PokeBattle_Battle#initialize` (`01_AI_Main.rb:3124`) to build `@battleAI` and register both
parties, and `PokeBattle_Battler#pbInitialize` (`:3229`) to register each projection. So
construct a battle, create two battlers, call `AI_Learn#choose_move`. **The null scene
recorded zero calls across all 68 probes** — direct evidence the probe scores without
advancing the turn (§10's stated risk).

**`ai_diff.py` validated against three controls before use:** identity → ρ=+1.000,
negated scores → ρ=−1.000, shuffled → ρ=−0.164. 12 of 73 correctly report ρ *undefined*
(flat vectors, or 2-move sets where ρ is ±1 by construction) rather than a fake 1.0.

**Result: mean ρ = 0.852, top-1 agreement 93.9%, action-type agreement 97.1%.**
5 scenarios pin Reborn field IDs and are **skipped**, not failed — `check_scenarios.py`
gained `skipped` handling, without which a skip was miscounted as an AI failure.

#### The load-bearing finding: PBAI is hard-gated on roles

`Pokemon#roles` defaults to `[:NONE]` for any Pokémon built outside trainer loading
(`014_Pokemon/001_Pokemon.rb:556`); real trainer Pokémon get `pkmn.roles = pkmn.assign_roles`
at `03_AI_Roles.rb:64`. Two separate parts of PBAI dead-end on `:NONE`:

| Gate | Effect when role is `:NONE` |
|---|---|
| `get_move_score:2184` — `score = 0 if self.has_role?(:NONE)` | **every status move scores 0** |
| `get_switch_score:1769` — `switch = has_role?(:NONE) ? false : ai_should_switch?(...)` | **switching is never evaluated at all** |

A Pokémon PBAI cannot classify becomes a purely offensive, never-switching automaton. That
is a real structural property and the single most important thing to know before porting
PBAI — but it also **contaminated this corpus three separate times**:

1. Probe Pokémon initially had no roles at all → *every* status move scored 0 → looked like
   "PBAI refuses to heal". Fixed by mirroring the real trainer path.
2. After the fix, 24/68 still resolve to `:NONE` because the corpus deliberately uses
   minimal 1–2 move sets that `assign_roles` cannot classify.
3. All three forced-switch scenarios give the AI a single crippled move → `:NONE` →
   `get_switch_score` returns `[0,0]` before looking at the bench. **The "PBAI never
   switches" reading is not supported**; it was never asked.

**This was fixed, not deferred.** `make_scenarios.py` now pads every AI-side Pokémon
(active and bench) to a full 4-move set via `pad_to_four`. `assign_roles` awards
`:PHYSICALBREAKER` for `physical_moves >= 2` and ignores type, so two weak physical fillers
are sufficient; they are deliberately chosen from outside every role-trigger list, because a
setup move would suppress `:TANK` and Toxic/Taunt/Thunder Wave each mint a role of their own.

Result: **`:NONE` eliminated — 0 of 68.** PBAI now switches where it previously never did.

### 9.5 The corpus fix, and what it cost to get an honest number

Padding changed both sides' numbers, and **not in PBAI's favour** — the contaminated run had
been flattering it.

| | Reborn Yang | PBAI | mean ρ | top-1 |
|---|---|---|---|---|
| before padding (contaminated) | 89/89 | 78/84 | 0.852 | 93.9% |
| after padding, before status fix | 91/91 | 76/85 | 0.729 | 82.5% |
| **final (valid)** | **91/91** | **80/85** | **0.812** | **91.5%** |

Two further defects surfaced, both of the silently-wrong kind:

1. **Four Reborn assertions were over-specified.** `must_choose_move_in(['EARTHQUAKE'])`
   against a 5–7% HP target demands one *particular* lethal move — but a 40 BP filler also
   kills, and Reborn scores every lethal move identically at 121 because it does not rank
   overkill. Padding exposed this; a fifth (`kill_over_status`) had three moves tied at the
   top and was **passing by luck at 1-in-3**. All five now assert the real property —
   "take a kill, don't set up / don't Protect" — via `must_not_choose_move` + `score_gt`.
   Reborn is 91/91, not 89/89, because each rewrite became two assertions.
2. **The Hegemony adapter never applied status.** v19 status IDs are UPPERCASE
   (`010_Status.rb:61`); `apply_state` lowercased them, `try_get` returned nil, and the
   status was skipped **silently**. Every "don't re-apply a status the target already has"
   scenario therefore ran against a *healthy* target, where using the status move is
   correct. This produced five confident false failures — PBAI was reported as
   re-paralysing, re-burning, re-poisoning and re-sleeping targets. **It does none of
   these.** Now `.upcase`, and it raises rather than rescuing; target status is recorded in
   every result so the mistake cannot recur unseen. Reborn was never affected — its
   `STATUS_KEYS` table is keyed lowercase and matches the generator.

#### Genuine divergences that survive

- **Healing under threat** (2 assertions). `target_has_killing_move?` (`:2726`) tests
  incoming damage against **current** HP and never asks whether the heal would lift it out
  of range; any hit that would KO now zeroes every status move except Destiny Bond. Reborn
  scores Recover 297 where PBAI scores it 0. PBAI's rule is right whenever the heal cannot
  outpace the damage and wrong when it can — blunter, not simply worse.
- **Forced switches** (2). PBAI now evaluates switching and takes it in one position, but
  still declines the two where Reborn switches.
- **`switch_when_outmatched_low_hp`** (1). `get_switch_score` is never called: `choose_move`
  sets `skip_switch` as soon as the AI has any killing move, so it never asks whether
  switching would be better than trading.

**Four separate harness artifacts were caught and fixed in this phase** (no roles, sparse
movesets, over-specified assertions, unapplied status). Every one of them initially looked
like a finding about the AI. The rule that caught all four: when the measurement makes an AI
look stupid, suspect the measurement first.

### 9.6 Batch A scale-up + the nil-ability harness bug (2026-09-03)

**Corpus is now 88 scenarios / 112 assertions, 112/112 on the reference** (Hegemony/PBAI:
99/106 over 83 probeable, 5 field scenarios skipped). Tier-2 on the enlarged corpus:
mean ρ = 0.807, top-1 90.5%, action-type agreement 97.6% — consistent with the 73-scenario
run. Assertion mix: 48 must_not_choose_move, 45 score_gt, 7 must_choose_any,
5 must_consider_switch, 5 must_not_switch, 2 must_switch.

Fifteen new scenarios (`CORPUS_V3`): absorbing abilities (3), moves that fail
mechanically — Belly Drum <50%, Substitute <25%, Dream Eater on awake, Explosion into a
ghost, Rest at full (5), redundant debuff at −6 (1), priority-secures-kill-when-slower (1),
and role decisions — Toxic-the-wall, Haze at +6 / no-Haze unboosted, no-setup at 8% vs a
lethal foe, Counter vs a pure special attacker (5). Role-kit mons carry full 4-move real
kits so `pad_to_four` no-ops and PBAI mints the *intended* role — roles are now a measured
variable, not a padded-away confound.

#### The fifth silently-wrong harness artifact: every probe Pokémon had a nil ability

`PokeBattle_TestEnvironment.rb:1024` reopens `PokeBattle_Pokemon` with
`attr_accessor :ability` (so `random_battles` can write `mon.ability=`), which **replaces
the computed #ability with a plain nil-returning @ability reader**. The harness loads the
test environment for its battle machinery, so every Pokémon in every probe run to date —
including the archived reference — had `battler.ability == nil`. The AI's
`pbTypeModNoMessages` ability case (`PokeBattle_AI_2.rb:10277`) matched nothing, and every
ability-based immunity silently degraded to a plain type matchup:

| Scenario | before fix | after fix |
|---|---|---|
| EQ into Levitate Flygon | scored **55** (passed only because Dragon Claw's 87 kept it out of the roulette) | **0** |
| Waterfall into Water Absorb | 24 | **−1** |
| Thunderbolt into Volt Absorb | 24 — **and the AI chose it** | **−1** |

The fix (AI_Harness.rb `load_test_environment`) restores a reader that prefers a written
`@ability` (so `random_battles` still works) and falls back to the computed chain. The
diagnosis path is worth remembering: the failure was found only because a new assertion
was tight enough (Flash Cannon 22 vs Thunderbolt 24), and the probe now records the
target's runtime ability + per-move typemod verdicts so position-vs-AI confusion can't
recur. `imm_ground_vs_levitate` had been "passing" against a position that did not contain
Levitate at all — a reminder that a green assertion validates the *position* only as far
as some assertion actually depends on it.

#### Determinism holes closed in the same pass

An unpinned Essentials Pokémon rolls **nature** and **ability slot** from `personalID` —
Reborn's `personalID%3` can even land the hidden-ability slot. Reborn's probe already
pinned nature (HARDY) but not ability; Hegemony's pinned neither. Both now pin
nature=HARDY / ability slot 0 by default, and the generator + all three adapters accept
`nature:`, `ability:` (name, resolved to Reborn's slot index against PBS) and `ev_*:` keys
for scenarios that need specific values (the absorb targets pin their ability by name —
Vaporeon/Jolteon/Flareon each have TWO possible abilities, so an unpinned target makes
those assertions a coin flip on mon generation).

#### New genuine divergences (join the 9.5 list)

- **Phazing** (2). PBAI scores Haze **0** into a +6 attacker where Reborn scores it top;
  inverted, PBAI marginally *prefers* Haze (6 vs Scald 5) when nothing is boosted. PBAI
  effectively does not model boost-clearing value.
- Absorb abilities, move-fails family, redundant debuff, priority-secures-kill, setup
  timing, Toxic-the-wall and Counter-vs-special all **pass on PBAI** — the new families
  discriminate less than feared outside phazing.

#### Also confirmed from Hegemony's own copy

- `OMNISCIENT_AI = false` (`01_AI_Main.rb:9`) — matches ANALYSIS.
- `@skill = (wild ...) ? 0 : 200` (`:706`) — skill is hardcoded; trainer skill is ignored.
- **PBAI's tie-break is dead code.** `determine_move_choice` means to coin-flip on a tie but
  compares `s_ind[0][1] == s_ind[1][1]`, which are the two entries' *indices*, never equal by
  construction. The intended `rand(2)` never fires, so PBAI is deterministic — correct
  conclusion, different reason than assumed.
- `determine_move_choice` **collapses its own ranking**: it zeroes every entry except the
  winner, in place. Only the pre-pass (init) score vector is usable for Tier 2; the adapter
  emits it as `score` and keeps the collapsed one as `score_final`.

---

### 9.6 Phase 4 result — Realidea probeable; three AIs on one corpus

**The blocker was write access, not the AI.** Realidea is v16: no plugin system, no plaintext
`Scripts/`, everything inside a 1 MB `Data/Scripts.rxdata`. `tools/pack_rxdata.py` is the
Marshal *writer* that unblocks it (and unblocks the porting programme generally).

It does **not** re-serialise the bundle. Realidea's was written by a Ruby 1.9+ Marshal, so
its strings are ivar-wrapped (`I"…" :E T`) with 21 of them reaching that `:E` by symbol
backreference; naive round-tripping silently rewrites all 1 MB. Instead existing elements
are copied as **verbatim byte slices** and only the element count and the new section are
written. Safe here because the bundle contains no `@` object backreferences (verified by tag
scan). `--selftest` round-trips four real bundles — Realidea, Hegemony ×2, Reborn — **byte
for byte**; it caught the ivar issue on the first run.

Install = insert an `AI_Probe` section before `Main` + replace `Main` with a patched copy
(scene loop wrapped in the opt-in branch). **All 329 other sections verified byte-identical.**
Backup: `_AI-Study/backups/realidea_Scripts.rxdata.orig`.

**The AI being probed is not the one in the file everyone reads.** `085_PokeBattle_AI.rb`
defines `pbChooseMoves`, but section `275_AI edit clara` reopens `PokeBattle_Battle` and
redefines it wholesale 190 sections later — so 085's copy is dead code. Same class of trap as
Ashen Frost's plugin folder. Both copies share the shape the probe needs, so the split the
spec asked for was already there and needed no edit to their AI:

```
scores[i] = pbGetMoveScore(...)     <- init vector (aliased; this is what we capture)
... skill-gated minmax compression  <- final vector (local; DERIVED in the record, not read)
if $INTERNAL ... PBDebug.log        <- their own log point
... pbAIRandom(totalscore)          <- selection begins
```

#### Results — all three engines, one corpus

| | Tier 1 | vs Reborn ρ | vs Reborn top-1 |
|---|---|---|---|
| **Reborn Yang** (reference) | **91/91** | — | — |
| **Hegemony / PBAI** | **81/85** | 0.828 | 96.5% |
| **Realidea** | **81/85** | 0.887 | 91.7% |

PBAI vs Realidea: ρ = 0.887, top-1 96.4%. All three skip the same 5 field-pinned scenarios.

**Realidea is not the pushover the static reading suggested.** It ties PBAI on Tier 1 and
correlates *more* closely with Reborn. It also **evaluates switching on every single turn**
(68/68) — and declines every time.

#### Two more defects found, both mine

1. **`should_switch_score` was hardcoded null**, so six `must_consider_switch` assertions
   reported "never considered switching" for an AI that considers it every turn. v16
   switching is a *predicate* (`pbEnemyShouldWithdrawEx?`), not a score, so the field now
   carries three states: 1 = switched, 0 = evaluated and declined, null = never evaluated.
   Realidea's real score is 81/85, not the 75/85 the broken adapter reported.
2. **A scenario was non-portable.** `immunity_normal_vs_ghost` compared Earthquake against
   Body Slam on Gengar — but Gengar keeps **Levitate** in pre-Gen-7 data, so on Realidea
   *both* score 0 and the assertion compared two immunities. Now uses Shadow Ball, which
   hits Gengar in every generation. A sixth over-specified kill assertion
   (`lethal_prefer_kill_over_setup`) surfaced the same way — a 40 BP filler kills at 8% HP
   on Realidea but fell just short on Reborn, so the assertion had been holding on one
   engine by a damage-roll margin.

Engine-specific gotcha: this build's Ruby has **1.8 semantics** — `Float#round` takes no
argument, so `.round(1)` raises `wrong number of arguments (1 for 0)`.

#### Divergences common to both non-reference AIs

Both PBAI and Realidea fail exactly the same two heal assertions and decline the forced
switches Reborn takes. Two independently-written AIs agreeing against the reference is
weak evidence the *reference* is the unusual one here — Reborn's willingness to heal and to
switch is the outlier behaviour, not their reluctance. Worth resolving with a damage
calculation before treating Reborn's answer as ground truth.

---

### 9.7 Batch B — hazards, screens and weather become probe state (2026-09-03)

**Corpus is now 99 scenarios / 130 assertions, 130/130 on the reference** (Hegemony/PBAI:
112/124 over 94 probeable, the same 5 field scenarios skipped). Tier-2: mean ρ = 0.794,
median 0.949, top-1 87.7%, action-type 97.9% — steady vs Batch A's 0.807/90.5/97.6.

Three new scenario-format keys, applied identically by all three adapters:

```
weather=rain                     # rain | sun | sand | hail
ai_side=reflect:5                # the AI's half of the field (its own screens)
player_side=spikes:3             # the player's half (where AI-laid hazards go)
```

Side keys: `spikes` (0–3), `toxicspikes` (0–2), `stealthrock` (0/1 — boolean in both
engines), `reflect`/`lightscreen` (rounds). One mechanism serves both engines because
PBAI's `AI_Side#effects` delegates straight to `battle.sides[n].effects`
(01_AI_Main.rb:3037); weather is set directly (`battle.weather` on v16,
`battle.field.weather` on v19 — *not* `pbStartWeather`, which would run animations and
form checks). Both probes record the weather the AI actually saw, per the 9.5 rule.

Eleven new scenarios (`CORPUS_V4`): redundant hazards at cap (Spikes 3, Toxic Spikes 2,
Stealth Rock up), redundant screens (Reflect/Light Screen already active), redundant
weather (Rain Dance in rain, Sunny Day in sun), and weather-flipped move quality
(Thunder vs Thunderbolt in/out of rain, Solar Beam vs Energy Ball in/out of sun).

The checker gained **`score_gte`** for positions where the stronger move can only *tie*:
in sun both 4x grass moves land in the same capped band (110 = 110 — the engine does not
rank overkill), so the honest property is "sun must erase Solar Beam's charge penalty",
not a strict ordering. The out-of-sun half keeps strict `score_gt`.

#### New genuine divergences (join the 9.5/9.6 list)

- **Redundant Reflect** (2 assertions). PBAI treats an already-up screen as a soft −3
  (02_AI_Score.rb:1345) where Reborn hard-zeroes it (PokeBattle_AI_2.rb:6973). Against a
  physical foe the bonuses elsewhere outweigh the −3 and PBAI **picks Reflect while
  Reflect is up** (6 vs Moonblast 5) — a move that fails outright. Light Screen passes
  only because its base landed lower (1 vs 5); same defect, thinner margin.
- **Accuracy is not modelled** (2 assertions). Thunder = Thunderbolt = 16 for PBAI both
  in and out of rain — no accuracy weighting, no rain never-miss. Reborn passes both
  orderings (expected-damage weighting + `nevermisscode`, treating Thunder as 100-acc in
  rain at :9979). PBAI is *indifferent*, not inverted.
- **Stat-stage floor is not modelled.** `redundant_debuff_at_min` — PBAI scores Charm
  **9** into a Machamp already at −6 Atk (Moonblast 5) and picks it, deterministically.
  Root cause: `AI_Move#statDown` is captured (01_AI_Main.rb:3194) but **no ScoreHandler
  ever reads it** — debuff moves are scored with zero awareness of the target's current
  stages. (§9.6 recorded this scenario as passing; that note was wrong or predated the
  roles-ordering fix — today's score vector is deterministic, `random_fallback=false`.)
- Hazard caps, redundant weather and the Solar Beam pair all **pass on PBAI** — it zeroes
  capped hazards (02_AI_Score.rb:816-822) and skips redundant weather bonuses just as its
  source promised.

---

### 9.8 Switching, second pass (2026-09-03)

**Corpus is now 104 scenarios / 135 assertions, 135/135 on the reference** (Hegemony/PBAI:
115/129 over 99 probeable). Tier-2: mean ρ = 0.788, median 0.949, top-1 89.3%,
action-type 94.9% (the drop from 97.9% is the new switch scenarios — see below).

Both switch systems were read end-to-end before writing scenarios. Reborn
`shouldSwitch?` (PokeBattle_AI_2.rb:13344) is `pro − anti`: pro = statuses/effects
(Leech Seed +65, Perish-1 +220, Toxic ×15 — *effects*, not yet probe-settable), negative
stages (25-30/stage), all-moves-immune +140, fresh-foe-would-OHKO +185; anti = own boosts,
**own-side hazards 15/layer** (:13655) plus hazard-KO terms, pivot-move-in-kit +150,
fresh-mon bonus +50, and a hardcoded `+999 if opponent.name=="Priscilla"` (never switch vs
one specific trainer). The action gate needs BOTH `sss > best move score` AND a bench mon
whose switch-in score beats 100 — and switch-in scoring charges candidates hazard damage
against effective HP for *survival* only (:11829), not against the score itself.

Five new scenarios (`CORPUS_V5`), all verified against the recorded gate numbers:

- `switch_out_all_moves_immune` — four Normal moves into a Ghost, Umbreon bench:
  **must_switch, reference passes** (sss 70 > 0, pivot 112).
- `switch_out_vs_fresh_ohko_counter` — Lapras Ice Beam 4x into full-HP Garchomp, Empoleon
  bench: **must_switch, reference passes** (sss 155 > 41, pivot 142.1 — the +185
  counter-switch term is live and the probe's turncount==0 satisfies it by construction).
- `no_switch_when_set_up` — +2/+2 Gyarados: **must_not_switch, both AIs pass**
  (Reborn sss −170; PBAI has a matching set-up handler).
- `switch_stay_hazards_deter` — the forced-switch position + own-side Spikes 3 + rocks.
  Reference **still switches**: sss collapses 325 → 65 (−80%, the deterrence is real) but
  65 still beats the crippled mon's move score of 7, and the pivot stays at exactly 104.3
  because the hazard charge feeds survival, not score. Switching through hazards there is
  defensible play, so the scenario documents the measured delta (`must_choose_any`)
  rather than constraining.
- `switch_out_to_absorb_pivot` — **documented near-miss #2**. Volt Absorb Jolteon blanks
  everything Magnezone has shown; the reference *wants* out (sss 135 vs move 40) but the
  pivot scores 63.7 < 100: the FFF hedge assumes the unshown STEEL STAB, which Jolteon
  takes neutrally. **An ability immunity is measurably worth less than a type resistance**
  (Empoleon 142.1 vs Jolteon 63.7 in structurally identical positions). Also: first draft
  gave Gyarados Earthquake (4x into Magnezone, scored 110) and the reference correctly
  stayed in to kill first — a reminder that a switch scenario must first prove staying is
  bad.

#### PBAI's switching is close to vestigial (measured)

PBAI **skips switch evaluation entirely whenever it has a killing move**
(01_AI_Main.rb:1276 `skip_switch`), and otherwise compares small-integer SwitchHandler
triggers (+2/+3 apiece, 04_AI_Switch.rb) against its best move score — with a live
`rand(2)` on exact ties (:1755, unlike its dead move-choice tie-break). Across all seven
switch-pressure scenarios in the corpus it has **never switched once**. The extreme case
is `switch_out_all_moves_immune`: PBAI scores all four of its own moves **0** — it knows
they are all immune — and still clicks Quick Attack into the Ghost with a super-effective
Umbreon on the bench (switch-out score 0). Since the position cannot change, a real battle
would loop this no-op until Struggle. Reborn switches in 4 of the same 7.

---

### 9.9 Party awareness (2026-09-03)

**Corpus is now 110 scenarios / 145 assertions, 145/145 on the reference — first try**
(Hegemony/PBAI: 114/139 over 105 probeable). Tier-2: mean ρ = 0.749, median 0.949,
top-1 83.9%, action-type 95.2% — the drop is real signal: the new family is the most
discriminating yet.

New machinery: the generator emits `player_bench=` lines (extra dict key
`player_bench`, unpadded — like the player active, their movesets are the AI's threat
model), and bench mons in all three adapters honour `hp_pct`, **including `hp_pct:0` =
fainted**, which is how "last able mon" positions are built. The active mon's on-field
`apply_state` still clamps to ≥ 1; only bench mons may be at 0.

Six scenarios (`CORPUS_V6`), each resting on verified party-reading code:
Roar vs a benchless player (Reborn `phasecode:7916` returns 0), phazing a +6 foe into
player-side triple Spikes + rocks (phasecode ×~3.4 boosts ×~2.2 hazards — the Batch B
side keys composing with a bench), Baton Pass with no own bench (`pivotcode` → 0),
Spikes/Toxic Spikes into teams with no vulnerable member (the hazard scorers loop the
actual player party, :4600-4671), and the forced-switch position with a **fainted** bench
(shouldSwitch? −1000 when only one able mon — the scenario doubles as an end-to-end guard
on the bench-hp extension).

#### PBAI fails every party-awareness property (5 scenarios, 9 assertions)

PBAI reads party *size* where Reborn reads party *contents*:

| Scenario | PBAI | Reborn |
|---|---|---|
| Roar vs last player mon | **picks Whirlwind (9)** — nothing to drag in | 0, attacks |
| Phaze +6 foe into 3×Spikes+SR | **Whirlwind = 0**, attacks | Whirlwind top |
| Baton Pass, no own bench | **picks Baton Pass (9)** — passes to nobody | 0, attacks |
| Spikes vs all-airborne team | **picks Spikes (10)** | 0 (`nonimmunecount==0`) |
| Toxic Spikes vs all-immune team | **picks Toxic Spikes (10)** | 0 |

The phazing rows are a clean inversion: PBAI zeroes Roar exactly when it is brilliant and
clicks it when it does nothing — its phaze handler (02_AI_Score.rb:1042) checks neither
the target's bench nor the target-side hazards, only `user.bad_against?(target)` and a
role bonus. Its hazard handler counts `opposing_side.party.size` with no
immunity/grounded check — and subtracts its OWN side's faint count from the opponent's
party size (:824-828, a cross-side bug, unmeasurable per-scenario but visible in the
logged "+N pokemon to be sent out" reasons). `no_switch_bench_all_fainted` passes on PBAI
only because PBAI never switches at all (§9.8).

Honesty note: `redundant_lightscreen` flipped between runs (Light Screen scored 1, 1,
then 6 across three otherwise-identical probe runs; Reflect scored 6 every time) — PBAI's
screen scoring is run-to-run unstable in the probe, cause not yet attributed (its final
pick is weighted-random by skill, but a *score* changing suggests global-flag leakage
across probes or a rand inside a handler). The structural finding — an already-up screen
is −3, not a veto — stands regardless of where the base lands; treat the per-run
pass/fail of the two screen scenarios as noise until attributed.

---

### 9.10 Effects-driven switching — and PBAI's first switches (2026-09-03)

**Corpus is now 115 scenarios / 150 assertions, 150/150 on the reference** (Hegemony/PBAI:
117/144 over 110 probeable). Tier-2: mean ρ = 0.736, median 0.949, top-1 84.5%,
action-type 92.7%.

New mon keys, all three adapters: `effects={name: value}` (perishsong, leechseed,
confusion, toxic, yawn, substitute, curse — plus **choiceband**, whose value is the locked
move's NAME, resolved to the numeric id on v16 and the symbol on v19) and `pp_all=` (0 =
every move out of PP). Effects apply on-field in `apply_state`; unknown names raise.

Five scenarios (`CORPUS_V7`) built on one shared position (Snorlax + Body Slam vs bulky
Suicune, Ferrothorn quarter-resist pivot at 208.6) so the trigger is the only variable.
Reference passes all five as **must_switch**, and the recorded sss ladder is a measured
ranking of Reborn's trigger strengths on identical terrain:

| Trigger | sss | vs best move |
|---|---|---|
| Choice-locked into an immune move (+70+160+250 cumulative) | **635** | 0 |
| Perish Song count 1 (+220) | 170 | 29 |
| No PP on any move (+200) | 150 | 2 |
| Leech Seed + Toxic count 4 (+65+60) | 75 | 29 |
| Yawn (+95) | 45 | 29 |

(The yawn/chip entries were drafted as doc scenarios expecting sub-gate totals; Body Slam
into Suicune scored only 29, so both cleared and were upgraded to must_switch on the
recorded actions.)

#### PBAI switched for the first time — and stayed in for certain death

After seven switch-pressure scenarios with zero switches, PBAI finally switched **twice**:
choice-locked (switch-out score 20) and no-PP (3.75 — with no scoreable moves it goes
straight to the switch path). But it **stayed in on Perish count 1**, the only position of
the five where staying loses outright, despite its own +20 Perish trigger
(04_AI_Switch.rb:524) — its matchup-based negative handlers ("we have slow kill" −5 etc.)
eat the bonus, and the recorded switch score came back 0. It also stays on yawn and
chip-stack (both sss 0 — its Toxic trigger is +2, it has no Leech Seed/Yawn switch
triggers at all). Net: PBAI's switch triggers are calibrated an order of magnitude below
its move scores, so only positions with *no usable moves at all* (locked/immune, no PP)
actually produce a switch — pressure that merely makes staying bad never does.

---

### 9.11 The screen-score "instability" attributed: PBAI's scores are stochastic by design

The §9.9 honesty note is resolved, and the answer corrects a §9.6 claim. Two sources,
both in PBAI's own code:

1. **Damage rolls.** Every damage projection multiplies in a live 85–100% roll
   (08_AI_Damage_Calc.rb:311 `random = 85 + @battle.pbRandom(16)`), so any handler
   comparing damage to an HP threshold can branch differently per evaluation. PBAI ships
   its own pin — `random = 92 if $game_switches[Settings::NO_ROLLS]` — which the probe
   bootstrap now sets defensively (rescue-guarded; 92 ≈ the 92.5 roll mean, i.e. measure
   the policy, not the roll).
2. **Score handlers literally roll dice.** 06_AI_Misc.rb seeds score bonuses on raw
   chance: `next 1 if battle.pbRandom(100) < 20`, several `>= 30` gates, a randomly
   chosen stat at :681, etc. These fire per *evaluation*, so the init score vector
   changes run to run even with damage pinned.

Verified with a two-run back-to-back diff on the identical corpus: 7/115 scenarios
changed score vectors — Reflect 0 vs 6 (the redundant-Reflect verdict flips with it),
Dazzling Gleam 6 vs 13, Toxic Spikes 5 vs 10, Body Slam 7 vs 3. So the §9.6 line "PBAI
is deterministic" is wrong as stated: its *choice given scores* is deterministic (the
tie-break is dead code), but the scores themselves are stochastic. Consequences:

- **Any Hegemony Tier-1 verdict with a margin ≤ ~5 points is a distribution, not a
  verdict.** That covers the two redundant-screen scenarios (6 vs 5) — report them as
  "fails in some runs" — while the load-bearing findings all have roll-proof margins:
  phazing inversions (9 vs 5 / 0 vs 16), hazards-vs-airborne (10 vs 5), Charm-at-−6
  (9 vs 5, and its −3-not-a-veto mechanism is structural), no-accuracy (16 = 16 always),
  and every party-awareness result.
- Proper protocol for marginal PBAI scenarios: N probe runs and per-assertion pass
  rates. Not yet implemented; single-run numbers for Hegemony should be read with this
  caveat. The reference is unaffected — Reborn's probe scores have been bit-identical
  across all reruns.

---

## 10. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| **Headless execution** — mkxp-z wants a window; these are Windows builds on a WSL mount | **high** | Phase 0 spike. Try `SDL_VIDEODRIVER=dummy`, else run on the Windows side and treat WSL as analysis-only. Reborn's harness runs in-process with a scene, so a real window may simply be acceptable |
| Realidea scoring/selection entanglement | medium | Already required by the porting plan; do it once |
| Scenario not instantiable in every game | medium | Mark `skipped` with a reason; never silently drop — a shrinking corpus that still reports 100% is the failure mode to avoid |
| Corpus overfits to Reborn (schema built there first) | medium | Add the PBAI adapter at Phase 3, before the corpus grows past ~60 |
| Reading score vectors changes behaviour | low | `probe()` is score-only and must not advance state; assert battle state unchanged after probing |

---

## 11. Open questions

- Does mkxp-z run offscreen on this setup, or must the whole harness live on Windows?
- Reborn's `load_data("battle")` in `bestTrainersBattle` — what is that file, and can the
  frozen gauntlet reuse its format?
- Doubles: worth including in the corpus at Phase 2, or defer? (Reborn's AI has substantial
  doubles-only logic, including the only Normal-mode turn-choice reads.)
