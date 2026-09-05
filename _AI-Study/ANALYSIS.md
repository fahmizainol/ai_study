# Pokémon Fangame Battle AI — Code Analysis

Comparative teardown of the battle AI in eight local games plus one remote repo, across
**two engines**: RPG Maker XP / Pokémon Essentials (Ruby) and CFRU (C, GBA binary hack).
All findings are from **reading source code, not playtesting** — team quality and level
curves also drive felt difficulty and are largely out of scope here.

Analysis date: 2026-09-03; Pokémon Z V2.13 added 2026-09-04. Paths are relative to
`/mnt/c/Users/kny/Documents/Games/Norm`.

For which Essentials version each game runs and what it would take to ship one AI across
all of them, see `AI-PORTABILITY.md`.

---

## TL;DR ranking

**Raw opponent strength:**
Reborn Yang (Intense) ≈ Unbound (Expert/Insane) > Rejuvenation (Intense) > Reborn Yang (Normal) ≈ Phantombass 9.0 ≈ Hegemony PBAI > Ancient Platinum > Consistent AI > Unbound (Vanilla) ≈ Rejuvenation (Easy) > **Pokémon Z** > Realidea

Pokémon Z and Realidea run *the same scorer* — 124 differing lines, all of them custom
abilities and items, none of them logic. Z sits above Realidea purely because it puts 181
of 196 trainer types at skill 100 and Realidea puts zero there. That pair is the cleanest
A/B in this study for what stock v16 skill gating is worth.

Unbound and Reborn Yang (Intense) top it on **cheat surface**. Unbound is the only one that
also hands its team free perfect IVs / max PP / 252 EVs; Reborn Yang gives no free stats but
reads more of your turn and is the better *player*. Cross-engine placement of Unbound is
softer than the rest of this list — see the caveat in its section.

**Quality of reasoning (cheats aside): Reborn Yang wins.** It is the only AI here that
combines all four of: real per-move-effect scoring (~200 hand-written handlers), team-role
archetypes, deep field-effect reasoning, and *calibrated* opponent prediction — cheats
deliberately softened with a dice roll so they read as inference rather than omniscience.
It also ships the only **exploitable** habit model in the study: bait its redirection
counter and it will keep flinching at a Follow Me you never clicked.

The Phantombass family is the runner-up and the only *other* AI that models player habits.
Rejuvenation is deep in its own domain but its 35k lines are breadth of hand-tuned cases
rather than deeper inference — and Reborn Yang beats it on field reasoning per line despite
being half the size. CFRU is the best-engineered (real damage calc, fight classes, doubles
spread tables) and the only one whose cheating is *deliberately concealed from the player*.

---

## A. Core logic

| AI | Game | Status | Engine | Lines | Move choice | Skill gating | Roles | Cross-turn pattern detection |
|---|---|---|---|---|---|---|---|---|
| **Consistent AI 1.0.1** (DemICE) | Ashen Frost | **live** | v20.1 | 8,966 / 4 files | Exact-max only, random among ties; randomness gates commented out | 161 checks (98 high / 54 med / 7 best) | none | none |
| **Phantombass 9.0** | Ashen Frost | **dormant** | v20.1 | 15,415 / 9 files | Deterministic — sort desc, take top | **ignores skill entirely** | ~25 | **yes** — 15 flags |
| **Phantombass 1.0.0** | Hegemony | live | v19 | 15,456 / 9 files | Deterministic | ignores skill | ~25 | **yes** — 15 flags |
| **Phantombass 1.0.0** | Ancient Platinum | live | v21.1 | 4,840 / 9 files | Prune dominated → weighted random | v21 skill flags; 105/107 types at 100 | ~25 | none (7 static flags only) |
| **Stock Essentials** | Realidea V4.1 | live | v16 | 4,360 | **Weighted roulette** | 4 tiers; **0 trainers at best** | none | none |
| **Stock Essentials** | Pokémon Z V2.13 | live | v16.2 | 4,418 (124 lines ≠ Realidea, **all content, no logic**) | **Weighted roulette** — identical code to Realidea | 4 tiers; **181/196 types at 100** | none | none |
| **Custom** | Rejuvenation v13 | live | modified v16-era | **35,652** | Deterministic — exact max, accuracy tiebreak | 5 tiers; 86% at 90+ | 21 (incl. `FIELDSETTER`) | none |
| **Custom (Reborn E19 + Yang)** | Reborn Yang | live | Reborn E19.16 (mkxp-z) | 17,647 / 1 file | Compress dominated → roulette over top 5% (top move double-weighted); Intense tightens to 2% | 5 tiers; **219/306 types (72%) at 100** | 18, computed only at `HIGHSKILL`+ | **yes (Intense)** — Wide Guard + redirection counters, swap history |
| **CFRU Battle AI** | Pokémon Unbound v2.1.1.1 | live | **CFRU** — GBA binary hack, C | 20,353 / 7 files † | Exact max only, random among ties | 3 flag bits per trainer, **rewritten by difficulty** | 18 fight classes | **yes** — anti-cheese switch history |

† Line count is public CFRU @ `b637a27` (2025-01-24), **not** the shipped 2023 build. See caveat below.

## B. Information access and cheating

| AI | Sees your moves/items/abilities | Peeks at your bench | Reads your locked-in turn choice | Stat cheats | Difficulty scales the AI |
|---|---|---|---|---|---|
| **Consistent AI** (AF live) | yes | no | **yes** — Wide Guard dodge + Sucker Punch prediction, 30/50/70% | none found | **yes** (`$PokemonGlobal.difficulty`) |
| **Phantombass 9.0** (AF dormant) | yes (`OMNISCIENT_AI = true`) | no | no — mechanic emulation only | none found | no |
| **Phantombass 1.0.0** (Hegemony) | **no** (`OMNISCIENT_AI = false`) | no | no | none | no (Insane Mode restricts *you*) |
| **Phantombass 1.0.0** (Ancient Plat.) | yes (no revealed-filtering) | no | no | none found | no |
| **Stock v16** (Realidea) | yes | no | no | none found | no |
| **Stock v16.2** (Pokémon Z) | yes | no | no | none found | no (no battle difficulty system exists) |
| **Custom** (Rejuvenation) | yes (758 ability reads, 0 filtering) | **yes** — 60 sites, ~11 read hidden types/abilities | **no** (1 `@choices` site = own side) | **yes** | partly (Easy disables switch AI) |
| **Reborn Yang — Normal** | **no** — real earned memory model | barely (4 sites, `skill>=BEST` only) | **doubles only** — your item use + priority move | none found | — |
| **Reborn Yang — Intense** | **yes** — memory bypassed wholesale | same 4 sites | **yes** — Sucker Punch 100%, Counter 75%, switch target, Follow Me 67% | **no free stats**, but enemy gets **unlimited Mega Evolutions** | **yes** — all trainers forced to skill 100 |
| **CFRU** (Unbound) | yes — `REALLY_SMART_AI` on unconditionally | **yes** — hazard scoring walks your whole party | **yes — re-picks its move, then hides that it did** | **yes** — 31 IVs, max PP, 252 EVs at Expert+ | **yes** — 4 tiers rewrite the flag set |

---

## Per-game detail

### Ashen Frost — the plugin/bundle mismatch

**Key finding: the AI that runs is not the AI the source folder advertises.**

`Plugins/` contains five AI plugins. Essentials treats `meta.txt` as enabled and
`meta.txts` as disabled:

| Plugin | meta file | State |
|---|---|---|
| Phantombass AI | `meta.txt` | enabled |
| Consistent AI | `meta.txts` | disabled |
| [Edited] Consistent AI | `meta.txts` | disabled |
| Goat AI | `meta.txts` | disabled |
| Rejuv AI | `meta.txts` | disabled |

But the compiled `Data/PluginScripts.rxdata` (34 plugins) contains **Consistent AI v1.0.1
by DemICE** — 4 scripts, 8,966 lines — and **no Phantombass code at all**. The only
"Phantombass" strings in the bundle are author credits on *Better Speed Up* and
*Customizable Level Cap*.

This matters because of the loader in `Data/Scripts/001_Technical/005_PluginManager.rb`:

```ruby
def self.needCompiling?(order, plugins)
  return false if !$DEBUG || safeExists?("Game.rgssad")   # ← exits here in a release build
```

`runPlugins` then loads the bundle and **evals every entry unconditionally** — folder
registration does not filter execution. `$DEBUG = true` sits commented out in
`Data/Scripts/001_Settings.rb` beside the dev's note *"Make sure to set this to false
before releasing the game."* The mkxp `patch` overlay folder is empty.

**So Consistent AI runs; the `meta.txt` state is cosmetic unless launched in debug mode.**

*Unverified:* this is inferred from the bundle plus the `$DEBUG` check, not from watching
the game boot. Launching and reading the `Loaded plugin: ==<name>==` console lines would
settle it outright.

**Consistent AI characteristics:**
- Near-deterministic: `preferredMoves.push(c) if c[1] == maxScore` (exact max only). The
  vanilla stdev/10%-random gate is commented out with DemICE's own `# DemICE removing randomness`.
- Skill-gated: 161 tier checks — unlike Phantombass, which ignores skill.
- **Cheats via turn prediction**, 9 `@battle.choices[]` sites in `AI Move.rb`. Two are real:
  - L31–32: checks whether you have chosen Wide Guard, avoids multi-target moves
  - L219–229: reads your chosen move + priority to decide whether Sucker Punch will fail
  - Both gated at 30/50/70% by `$PokemonGlobal.difficulty`. Dev comments call it
    *"Try play 'mind games' instead of just getting baited every time"* and `'Predicting'`.
- `Difficulty Modes` plugin only scales levels (×1.1 hard) and swaps teams; its
  `skill_proc` is commented out. AI difficulty scaling comes from Consistent AI itself.

**Phantombass AI 9.0 (dormant here, but this is the strongest build of it):**
- `OMNISCIENT_AI = true`, `AI_KNOWS_ABILITY = true`
- `PBAI.move_choice` sorts descending, takes index 0 — no randomness
- Real damage calc (`get_damage_by_move`, `calculate_hits_to_kill_with_best_move`)
- ~25 roles auto-assigned from moves/abilities/items
- Per-turn threat scoring
- **Spam block** — the differentiator. Persists across turns: `triple_switch`, `same_move`,
  `double_recover`, `double_intimidate`, `initiative_flag`, `protect_switch`,
  `fake_out_ghost_flag`, `yawn`, `choiced_flag`, `haze_flag`, `has_setup`, `setup_fodder`, …
- Its `battle.choices[]` reads are **faithful mechanic emulation**, not cheating —
  Stakeout genuinely doubles damage vs switchers; Zoom Lens genuinely keys off turn order.

### Realidea V4.1 — stock v16, broken in your favour

> **Read this first: `085_PokeBattle_AI.rb` is not the AI that runs.** Script section
> `275_AI edit clara` reopens `PokeBattle_Battle` and redefines `pbChooseMoves` wholesale,
> 190 sections later, so it wins. The two copies agree on the parts cited below, but any
> conclusion drawn from 085 alone is a conclusion about dead code — the same trap as Ashen
> Frost's plugin folder.

**Confirmed by running it** (Phase 4 probe, 68 positions — `SIM-SPEC.md` §9.6):

- Tier 1 **81/85**, and Spearman **ρ = 0.887** against Reborn Yang (top-1 91.7%) — it ties
  Hegemony's PBAI on assertions and correlates *more* closely with the reference than PBAI
  does. The static reading below (weighted roulette, dead `bestSkill` branches) is about
  how it behaves *in the game's own trainer data*, not about the scoring function's quality;
  probed at skill 100 the scoring itself is respectable.
- **It evaluates switching every single turn** (68/68 positions) and declines every time.
  "Never switches" and "never considers switching" are different claims; this is the former.
- Fails the same two heal assertions as PBAI, and declines the same forced switches.

- Scores moves then rolls a weighted die: `randnum = pbAIRandom(totalscore)`. Can pick a
  move it correctly scored as bad.
- Loose preferred pool (`>= maxscore*0.8`) behind `stdev>=40 && pbAIRandom(10)!=0` —
  a 10% chance to ignore its own best move.
- **Skill bug:** `skill` reads `trainertypes[8]`, blank for 108 of 118 entries, defaulting
  to base money. Result: 68 types medium (32–47), 45 high (mostly 60), 5 low, **zero at
  `bestSkill`**. Every `skill >= PBTrainerAI.bestSkill` branch is dead code in trainer
  battles. The intended `100` was placed in the *skillCode* column (index 9) instead of
  SkillLevel (index 8).
- **Inverted difficulty:** patch script (`WILD_AI_LEVEL = 25`, `WILD_AI_SWITCH = 346`)
  gives wild Pokémon `skill = 255 - (rareness-1)`. Rare wilds outthink gym leaders, while
  wilds below level 25 pick moves at random.
- Scripts live in `Data/Scripts.rxdata` (300 sections) — v16 predates the Plugins folder,
  so there is nothing separate to decompile.

### Pokémon Z V2.13 — the Realidea control group

Spanish-language fangame, `POKEMON Z V2.13/Pokemon Z V2.13/`. Essentials **v16.2-era**,
same generation as Realidea: no `Essentials::VERSION` constant, `PBSpecies` data layer,
hex-int move function codes (`case move.function` / `when 0x0A`). RGSS104E + mkxp-z.
235 script sections, 160,753 lines. No Plugins folder — v16 predates the framework.

> **Three script bundles ship, one runs.** `Game.ini` sets `Scripts=Data\Scripts.rxdata`
> (235 sections). `Data/ScriptsBackup.rxdata` (255 sections, the same 160,753 lines) and a
> root-level `Scripts.rxdata` (1 section, 45 lines) are inert. Same class of trap as Ashen
> Frost's plugin folder — read `Game.ini` before picking a file.

**Unlike Realidea, the file you read is the file that runs.** Section 75 `PokeBattle_AI`
(4,418 lines) is the only definition of `pbChooseMoves` / `pbGetMoveScore` in the bundle;
no later section reopens them. The only other `pbEnemyShouldWithdraw?` definitions are
`PokeBattle_BattlePalace` (80) and `PokeBattle_BattleArena` (81), both stock facility AI.
There is no equivalent of Realidea's `275_AI edit clara` override.

**The AI is stock v16 with content patches and nothing else.** Diffed against Realidea's
`PokeBattle_AI` with line endings normalized: **124 changed lines, zero logic changes.**
Every one hangs a custom mechanic off the existing scorer:

- abilities — `EARTHEATER`, `MAGNETISMO`, `CORTANTE`, `ACOMETIDA`, `CAMORRISTA`,
  `PURIFYINGSALT`, `CONTRAGUARDIA`, `SOBRECARGA`, `DESPIERTALLAMA`, `CUERPOHORNEADO`
- items — `SUPEREVIOLITE`, `CLEARAMULET`, `PUNZASFERA`, `MASCARACRUEL`, `TABLANEUTRA`
- a custom `HEMORRAGIA` (bleed) status, threaded through `PokeBattle_BattlerEffects` (5),
  `PokeBattle_Battler` (2), `PokeBattle_Move` (2), `PItem_ItemEffects` (2), and read by the
  AI's damage estimate via `MASCARACRUEL`

Selection is stock v16 verbatim: dominated-move compression at `mediumSkill`+
(threshold 1.5 / floor 5 once at `bestSkill`), then the preferred pool
`scores[i] >= maxscore*0.8` behind `stdev>=40 && pbAIRandom(10)!=0`, then a weighted
roulette over raw scores. Including the same 10% chance to discard its own best move.
No roles, no memory model (0 hits for `pbGetMonRole` / `getAIMemory`), no bench peeking,
no added cheats. No battle difficulty system — `difficulty` appears only in
`PMinigame_SlotMachine` and `PScreen_Options`. A `Nuzlocke` section exists.

**The difference from Realidea is one PBS column, and it is the whole story.** Confirmed
in the compiled `Data/trainertypes.dat` (196 records), not just the PBS text:

| skill | Pokémon Z | Realidea |
|---|---|---|
| **100 (`bestSkill`)** | **181** types | **0** |
| 250 | 1 (`URANO`) | 0 |
| 90–99 / 48–99 high | 0 | 45 (mostly 60, via money fallback) |
| 32–47 medium | 0 | 68 |
| ≤31 low | 2 (at 10) | 5 |
| blank → money fallback | 12 (all player types, → 60) | 108 |

Z writes `100` into SkillLevel (index 8); Realidea wrote its `100`s into the skillCode
column (index 9) and left index 8 blank, so every `skill >= PBTrainerAI.bestSkill` branch
is dead code there. Z runs those branches, and the tightest dominated-move compression, in
almost every trainer battle — including route filler like `CAMPESINO` and `BURGUES`, not
just the eight `LIDER` gyms.

**Teams** (`PBS/trainers.txt`): 411 trainers, 993 Pokémon. Party sizes skew small — 285 of
411 field one or two, only 30 field six. 73% of entries are full 13-field lines (through
the IV field), 33% set explicit movesets, 24% hold items. Levels 1–100, mean 59.7.

**Why it earns a section:** Z and Realidea are the same scorer at two skill settings, on
the same engine, with the same data layer. Every other pair in this study changes the
scorer too, so none of them isolate what skill gating alone is worth. Probing Z with the
existing `adapters/realidea/AI_Probe.rb` at its shipped skill values, against the already
collected `probe_results_realidea.ndjson`, would answer that with the harness already
built — Realidea probed at skill 100 scored ρ = 0.887 against Reborn Yang, so the scoring
function is respectable and the gating is the variable.

### Rejuvenation v13 — biggest and least honest

- **35,652 lines in one file** (`Scripts/PokeBattle_AI.rb`). Ships extracted scripts in a
  plain `Scripts/` folder.
- Five skill tiers, with `highSkill` raised from 48 to 90:
  `1 / 32 / 48 (averageSkill, new) / 90 (highSkill) / 100`
- Skill distribution from `Data/trainertypes.dat` (222 types): **119 at best (100+)**,
  72 at high (90–99), 9 average, 14 medium, 8 low → **86% at 90 or above**.
- **Deterministic:** preferred pool is `@scores[i] >= (maxscore * 1)` — *exactly* the top
  score. The vanilla `stdev`/randomness gate was deleted; `stdev` is computed at L29519 and
  never read again. Ties break by **highest accuracy**, not randomly. The trailing weighted
  roulette is effectively unreachable.
- 21 roles (`SWEEPER`, `PHAZER`, `REVENGEKILLER`, `HAZARDLEAD`, `ACE`, `FIELDSETTER`, …)
- `pbDamageToParty` projects damage across your **whole party** before switching;
  ~4,300 lines of switching logic.

**Field effects are native to the AI** — 1,466 references branching on all 46 field IDs:

| Function | Field refs |
|---|---|
| `pbGetMoveScore` | 446 |
| `pbRoughDamage` | 77 |
| `pbDamageToParty` | 70 |
| `pbGetMonRole` | 48 |
| `pbSwitchTo` / `pbShouldSwitch?` | 65 |
| `pbSpeedChangingSwitch` | 20 |
| `pbEnemyShouldMegaEvolve?` | 6 |

It reasons about *changing* the field based on its own bench — e.g. on Murkwater/Water
Surface it scans its reserves for Ice/Water/Poison types before deciding whether freezing
the field is worth it. Multi-turn, team-level planning.

**Intense mode is confirmed present in v13** — `$game_variables[200]`: `1` = Easy,
`2` = Intense. 75 gates across the scripts. (The devs removed it in later versions.)

| Intense effect | Location |
|---|---|
| Enemy Atk **and** SpAtk ×1.1 after 12 badges | `PokeBattle_Move.rb:3376` |
| Enemy accuracy ×1.1, **plus ×1.2** on damaging moves after 11 badges (~32% compounded) | `PokeBattle_Move.rb:1433` |
| Enemy Megas keep held item *and* Mega Evolve | `PokeBattle_Battle.rb:3634` |
| Enemy Aegislash: Blade Atk ×1.1, Shield Def ×1.1 | `PokeBattle_Move.rb:3237, 3602` |
| Player barred from items in trainer/boss battles | `PokeBattle_ActualScene.rb:3495` |
| Alternate stronger teams (`idJump 200`) + levels ×1.1 | `Difficulty Modes.rb` |
| Wild encounters arrive pre-statused | `PokemonEncounterModifiers.rb` |

The AI mirrors its own buffs in its estimates (`PokeBattle_AI.rb:22761`, `24751`), so it
plays consistently with them. Note the inverse gate: the advanced switching AI requires
`skill>=bestSkill && $game_variables[200]!=1` — **Easy mode disables it**; Normal and
Intense both get it.

**Always-on cheats (any difficulty):**
- `Move.rb:402` — enemy Silvally gets **Scrappy for free** (hits Ghosts with Normal/Fighting).
  Yours needs the actual ability.
- `Move.rb:4573` / `Battler.rb:631` — enemy Silvally gets the **Crest ×1.2 damage boost free**;
  you need `SILVCREST` in your bag.

**Likely bug:** `Move.rb:3241` grants **the player's** Aegislash Blade-form SpAtk ×1.1 on
Intense. The three surrounding blocks all check `!pbOwnedByPlayer` — polarity appears flipped.

**Proof of deliberate asymmetry:** the engine defines
`attr_accessor(:revealedMoves) # moves revealed by enemy pokemon` — it tracks only what the
AI has shown *you*, feeding your UI in `PokeBattle_Scene.rb`. There is no equivalent array
for your moves, and the AI references it **zero** times.

**What it does not do:** read your current-turn choice. Exactly one `@choices[]` access in
35,652 lines, and it is `@choices[1]` — its own side, checking whether it already used an item.

### Reborn Yang — honest by default, and the best-calibrated cheater on Intense

Pokémon Reborn **E19.16** (the engine Rejuvenation forked) plus the **Yang** rebalance mod
(`Changelog.txt`, v1.0 Oct 2023 → Nov 2024). mkxp-z. All AI lives in one file:
`Scripts/PokeBattle_AI_2.rb`, **17,647 lines**.

**Loading is verified, not inferred.** `Data/Scripts.rxdata` is only 4,011 bytes — a single
368-line section called *"script yeetifier pro"* that reads `Data/!script_order.csv` and
`eval`s the plaintext `Scripts/*.rb` files (`PokeBattle_AI_2` is entry 74). Extracted with
`tools/extract_rxdata.py` to confirm. **This is the opposite situation to Ashen Frost:**
here the bundle is the stub and the folder is authoritative, and we checked rather than
assumed.

**Architecture** — closest thing here to a purpose-built engine rather than a scoring
patch. An `AI_MonData` object per battler (`:1`) carries roles, party roles, a 4×4 score
array, a rough-damage array, item scores and switch scores. Move scoring dispatches to
**~200 hand-written per-effect handlers** (`sleepcode`, `suckercode`, `hazardcode`,
`pivotcode`, `perishcode`, …) rather than a switch of generic cases.

- Skill tiers `1 / 10 / 30 / 60 / 100` (`:62-66`). **219 of 306 trainer types sit at 100**
  (72%) in `PBS/trainertypes.txt` — the mirror image of Realidea's bug.
- **18 roles** (`pbGetMonRoles:9484`) from EVs, nature, item, ability, moveset *and* the
  mod's entrance effects. Computed only at `HIGHSKILL`+ (`:124`), used in ~100 places.
- Move choice (`:1658-1676`): scores below `max/threshold` are crushed to a floor (threshold
  tightens 3 → 2 → 1.5 as skill rises), then a roulette over everything within 5% of max
  with **the best move pushed twice**. Intense tightens the window to 2% once scores exceed
  110 — *"more precise for accuracy/roll purposes"*.
- **Two separate switching engines.** Normal scores switches (`shouldSwitch?:13344` →
  `getSwitchingScore:11351`); Intense skips that entirely (`:156`) and runs a different
  boolean routine (`shouldSwitchintense?:13713`). `getSwitchInScoresParty:11363` alone is
  ~2,000 lines.
- Ships a real debug harness (`PokeBattle_AI_Info:17533`, `$ai_log_data`) that logs every
  move score and switch decision.

**Field effects beat Rejuvenation on its own metric.** 704 `PBFields::` references across
50 distinct fields — **4.0% of all lines**, versus Rejuvenation's 811 refs in 35,652 lines
(**2.3%**). Reborn invented the mechanic and its AI is nearly twice as field-dense per line.

**Normal mode runs a genuine knowledge model** — the only Essentials AI here besides
Hegemony that does. `@aiMoveMemory` is keyed by trainer and `personalID`, and is populated
*only* by things the AI legitimately observed:

| Memory gained from | Location |
|---|---|
| You send a Pokémon out (existence only) | `PokeBattle_Battle.rb:2021` |
| You use a move | `PokeBattle_Battler.rb:6339` |
| Forewarn | `PokeBattle_Battler.rb:2714` |
| Mimic / Sketch / Transform copies | `PokeBattle_MoveEffects.rb:3168-3169` |

`getAIKnownParty:15617` likewise filters your bench to mons it has actually seen.

**Intense mode is the cheat switch.** One global — `$game_switches[3000]`, set from
Options → Difficulty (`PokemonOptions.rb:243` *"0=normal, 1=intense"*, wired at `:492-503`
and `DependentEvents.rb:201`):

| Intense effect | Location |
|---|---|
| **Every trainer forced to skill 100**, regardless of PBS | `PokeBattle_AI_2.rb:26` |
| **Memory model bypassed** — reads your full moveset | `:15596` |
| **Sucker Punch predicted 100%** of the time | `:15854-15858` |
| Reads your **switch target** and scores against the incoming mon | `checkSwapPrediction:201` |
| Reads whether you picked **Counter / Mirror Coat / Metal Burst** | `checkCounter:1936` |
| Reads your **Follow Me / Rage Powder** | `:2757-2762` |
| Tracks consecutive **Wide Guard / Protect** presses | `wideGuardCount:225` |
| Reads your **party's types** for Jump Kick crash risk | `:4722-4726` |
| **Enemy may Mega Evolve more than once per battle** — you may not | `PokeBattle_Battle.rb:2467, 2482` |
| Bosses get **84** scripted entrance effects instead of 27 | `PBS/entranceeffects.txt` |
| No mon is flagged `ACE`, so nothing is held back | `:9500` |

The omniscience is admitted in the source:

```ruby
return battler.moves.find_all {...} if $game_switches[3000] && !legal
# we read the opponent's movesets anyway, why not make it consistent throughout?
```

**The interesting part: the cheats are deliberately miscalibrated.** Almost every read of
your locked-in choice is wrapped in a dice roll, so it plays as a read rather than an oracle:

- Counter: acts on what it sees **75%** of the time, and *ignores* a real Counter 25% of the
  time (`:1936-1941`)
- Follow Me: believes you **2/3** of the time (`rand(3)<2`)
- Switch prediction: only fires if you have already switched repeatedly, only against a
  species it has **already seen**, and then on `rand(10) < 2.5 × swapcount` (`:207-214`)
- Sucker Punch is the exception at 100% — flagged in-code as provisional
  (*"may revert"*)

And the redirection model is **exploitable in your favour**:

```ruby
@opponent = battler if @aimondata[battler.index].redirectcounter > rand(5)
# AI can be coerced into believing player clicks follow me forever
```

Bait it with a few Follow Mes and it will keep playing around one you never pressed. No
other AI in this study ships a habit model you can deliberately poison.

**Caveat on "Normal is honest":** in **doubles** it is not, quite. `buildMoveScores` reads
your locked-in **item use** (`:493-497`) and whether you chose a **priority move**
(`:745-756`) with no Intense gate. Both are narrow and doubles-only; singles on Normal is
clean. Separately, `Outrage`/`Thrash` peek at your party's Fairy/Ghost types at
`skill>=BESTSKILL` (`:4386, 4389`) — gated on skill, not difficulty, so ~72% of trainers do
it on Normal too. Four sites total, versus Rejuvenation's sixty.

**Not a cheat:** Intense's EV changes actually favour *you* — a level-scaled EV cap, Macho
Brace ×16 instead of ×8, Power items +64 instead of +32 (`PokeBattle_Battle.rb:2805-2820,
2895-2925`). AI item use is also honest: it spends the trainer's real defined inventory
(`getItemScore:11067`), scored against move scores rather than granted freely.

**Verdict:** on Normal this is the strongest *honest* AI in the study — real memory model,
no stat cheats, no free mechanics, and still 72% max-skill with roles and field reasoning.
On Intense it acquires nearly the full cheat set but spends real effort making those cheats
feel like reads. Rejuvenation buffs its damage; Reborn Yang buffs its *information* and then
adds noise to it.

### Hegemony — the only non-omniscient one

- Public repo: `github.com/phantombass/Pokemon-Hegemony`, default branch `Release`
  (also `master`, `mobile` — all three have byte-identical AI files).
- `HegemonySetup/` locally is only the C# WPF launcher, not the game.
- **The plugin source folder is not uploaded**, but `Data/PluginScripts.rxdata` (745 KB) is
  committed and contains PBAI. `Data/Scripts/011_Battle/004_AI/` is stock Essentials v19 —
  a decoy if you only look there.
- PBAI `1.0.0`, 15,456 lines, same feature set as Ashen Frost's 9.0 (spam block, threat
  scores, learned flags, roles). Version numbering differs; it is the same generation.
- **`OMNISCIENT_AI = false`** — Ashen Frost's port turned it on. Nothing in Hegemony flips it.
- "Insane Mode" restricts the *player* (ability/move bans, tighter level caps via
  `INSANE_LEVEL_CAP`), it does not buff the AI.

**Confirmed by running it** (Phase 3 probe, 68 positions — see `SIM-SPEC.md` §9.4):

- **Everything hangs off roles.** `Pokemon#roles` is assigned at trainer-load time
  (`03_AI_Roles.rb:64`) and defaults to `[:NONE]` otherwise. Two gates dead-end on `:NONE`:
  `get_move_score:2184` zeroes **every status move**, and `get_switch_score:1769` returns
  before evaluating **any** switch. A Pokémon PBAI cannot classify plays as a purely
  offensive, never-switching automaton. This is the first thing to fix or preserve in a
  port — and the easiest thing to get silently wrong, since nothing errors.
- **The tie-break is dead code.** `determine_move_choice` intends to coin-flip between
  equal top scores but compares `s_ind[0][1] == s_ind[1][1]` — the two entries' *array
  indices*, never equal by construction. So `rand(2)` never fires. PBAI is deterministic,
  as recorded above, but for a different reason than "no randomness was written".
- **It discards its own ranking before choosing.** `determine_move_choice` mutates the
  score array in place and zeroes every entry except the winner, so the vector that reaches
  selection is `[0,…,X,…,0]`. Only the pre-pass scores carry an ordering.
- **Healing is gated bluntly.** `target_has_killing_move?:2726` compares incoming damage to
  **current** HP and never asks whether the heal would lift it out of KO range; any such hit
  zeroes all status moves bar Destiny Bond. Reborn Yang scores Recover 297 in a position
  where PBAI scores it 0.
- Against Reborn Yang on the shared 73-position corpus: **mean Spearman ρ = 0.812, top-1
  agreement 91.5%**; Tier-1 **80/85** vs Reborn's 91/91 (5 positions pin Reborn field IDs
  and are skipped). The two AIs largely agree on move ordering. Where they part company is
  **healing under threat** and **switching**: PBAI declines two forced switches Reborn
  takes, and never evaluates switching at all once it has any killing move
  (`choose_move`'s `skip_switch`).
- **Status discipline is fine.** An earlier draft of this section reported PBAI re-applying
  burn/poison/sleep/paralysis to already-statused targets. That was a harness defect — the
  probe silently failed to apply the status, so the target was healthy and the status move
  was the correct choice. PBAI does not make that mistake.

### Ancient Platinum — newest Phantombass rewrite, not the hardest

- Essentials v21.1. `class Battle::AI` **extends** the native framework rather than replacing
  it — which is why it is 4,840 lines vs 15,415, not because it is simpler in behaviour.
- Omniscient (reads `target.moves` directly, no revealed-filtering).
- Move choice: prunes dominated options, then `randNum = pbAIRandom(total_score)` — slightly
  more variance than AF's strict top-score pick.
- Skill-gated via stock v21 flags (`ScoreMoves`, `PredictMoveFailure`, `ConsiderSwitching`,
  `HPAware`, `ReserveLastPokemon`, `UsePokemonInOrder`), but **105 of 107 trainer types sit
  at skill 100**, so gating is effectively moot. No custom AI flags on any type.
- Keeps 7 *static* knowledge flags: `choice_locked`, `haze_flag`, `no_attacking`,
  `should_taunt`, `setup_fodder`, `no_priority`, `flags_set`.
- **Dropped the entire spam-block layer** — no repetition or turn-history tracking anywhere.
  It knows *what your Pokémon is*, not *what you keep doing*.
- Gains `ReserveLastPokemon` (ace preservation), which AF's 9.0 lacks.
- `Data/trainers.dat` ships as an empty 4-byte hash in this build; skill values come from
  `Data/trainer_types.dat`.

**Verdict: newer codebase, softer opponent.** Cleaner and more portable as engineering;
weaker as an adversary than Phantombass 9.0.

### Pokémon Unbound — different engine, and the one that hides its cheating

**This entry is not directly comparable to the five above.** Unbound is not an Essentials
game: it is a binary hack of Pokémon FireRed (`.gba`, header game code `BPRE`, 32 MB —
expanded from 16 MB), running the **Complete FireRed Upgrade (CFRU)** battle engine in C.
There is no Unbound decompilation and there will not be one; it was never built from a
source tree. What follows is read from the public CFRU repo, which *is* the engine
Unbound compiles.

Source read: `github.com/Skeli789/Complete-Fire-Red-Upgrade` @ `b637a27` (2025-01-24),
`src/Battle_AI/` — 7 files, 20,353 lines. Citations below are `file:line` in that repo,
**not** in anything under `../`.

**How much of Unbound is actually in the public source.** More than expected, but the
boundary is exact and measurable: nine functions are declared `extern` in CFRU and
**never defined anywhere in the repo**. That set *is* Unbound's private code:

| Undefined extern | Declared at | What it gates |
|---|---|---|
| `GetChanceOfPredictingPlayerNormalSwitch` | `ai_master.c:1617` | % chance the AI predicts your switch |
| `AISaveSweeperForLaterDifficultyCheck` | `ai_switching.c:48` | whether sweeper-preservation is allowed |
| `ShouldGiveTrainerMonBestStatsMaxEVs` | `build_pokemon.c:1129` | which trainer classes get 252 EVs |
| `ShouldGiveTrainerMonMaxFriendship` | `build_pokemon.c:1130` | Frustration/Return tuning |
| `GetEVSpreadNumForUnboundRivalChallenge` | `build_pokemon.c` | rival-challenge spreads |
| `TryGiveSpecialTrainerHiddenPower` | `build_pokemon.c` | scripted Hidden Power types |
| `TryGiveSpecialTrainerStatusCondition` | `build_pokemon.c` | pre-statused trainer mons |
| `TryReplaceUnboundNormalTrainerSpecies` | `build_pokemon.c:1541` | difficulty species swaps |
| `GetCurrentLevelCap` | `build_pokemon.c` | *"Must be implemented yourself"* |

So the *logic* is fully readable; the *numbers* on two AI knobs and five team-building
knobs are not. Everything below is logic, not numbers.

**Omniscient, and not configurably so.** The knowledge model lives in one function,
`GetBattleMonMove` (`ai_util.c:2138`):

```c
#ifdef REALLY_SMART_AI
    move = gBattleMons[bank].moves[i];              // reads your actual moveset
#else
    break_func(BATTLE_HISTORY->usedMoves)           // "Should throw error. We never want this to exist"
    if (SIDE(bank) == B_SIDE_PLAYER && ...)
        move = BATTLE_HISTORY->usedMoves[bank][i];  // only moves you have already used
```

A real revealed-moves model exists — and is dead. `REALLY_SMART_AI` is defined
**unconditionally** at `defines_battle.h:42`, not in `config.h`, with the comment
*"The vanilla FR AI memory system sucks so this should always be defined."* The `#else`
branch opens with a deliberate compile-breaker. This is the same axis as Phantombass's
`OMNISCIENT_AI`, except it is welded on: there is no supported way to turn it off.

**It peeks at your bench — but only for hazards.** `ai_positives.c:1283` (`EFFECT_SPIKES`)
loads `defParty` via `LoadPartyRange(bankDef, …)` and walks all six slots, reading species,
current HP, egg status, grounding and — for Sticky Web — **base speed of your benched mons
against its own**, before deciding the hazard is worth setting. 28 `defParty[]` reads, all
in this one file. Narrower than Rejuvenation's 60 sites, and it never uses bench knowledge
for switching or move choice. But it is unambiguously hidden information.

**Reads your locked-in turn choice — and then conceals that it did.** This is the finding
with no equivalent in any Essentials game here.

Most `gChosenMovesByBanks` reads across the AI are `bankAtkPartner` — its own doubles
partner, which is legitimate. The cheats are the `gChosenActionByBank[playerBank]` reads:

- `ai_master.c:1572` `RechooseAIMoveAfterSwitchIfNecessary` — fires when **you** switch,
  after the AI has already chosen.
- `ai_master.c:1601` `IsPlayerTryingToCheeseWithRepeatedSwitches` — flags you if
  `switchesInARow >= 3` or `secondPreviousMonIn == current` (a double-switch). Backing
  state is real per-battler history: `switchingCooldown`, `switchesInARow`,
  `secondPreviousMonIn` (`battle.h:1006-1010`).
- `ai_master.c:1613` `IsPlayerTryingToCheeseChoiceLockFirstTurn` — catches lead-and-switch
  against a Choice item on turn 0.
- `ai_util.c:1911` — the AI declines to value a flinch when it can see you chose to switch
  or use an item.

On a hit, `PickNewAIMove` (`ai_master.c:1649`) re-runs the whole scoring pass and
**replaces the already-chosen move**. The concealment is explicit in the code:

```c
if (!allowPursuit && gBattleMoves[chosenMove].effect == EFFECT_PURSUIT)
    allow = FALSE;   //"Using Pursuit after a switch would make the anti-abuse obvious"
else if (!allowHostileMove && ...)
    if (moveTarget == MOVE_TARGET_SELECTED)
        allow = FALSE;   //"Be subtle and only allow picking a new move if it's not reliant on the foe that switched in"
    ...
        allow = FALSE;   //"Only one target so it's obvious this move was changed"
```

The AI will only take the new move if you *cannot tell* it changed its mind. Every other
game in this study either cheats openly or does not cheat; this one launders it.

Gating: the whole layer is wrapped in `#ifdef VAR_GAME_DIFFICULTY`, which is **not defined
in public CFRU** — 21 `#ifdef VAR_GAME_DIFFICULTY` sites in `src/Battle_AI/` compile out of
a stock build. Unbound defines it, so the anti-cheese layer is effectively Unbound-specific.
The blatant-cheese path additionally requires `>= OPTIONS_EXPERT_DIFFICULTY`.

**Skill gating is three bits, not a 0-100 scale.** `GetAIFlags` (`ai_master.c`) reads
`gTrainers[opponent].aiFlags` and then rewrites it by difficulty
(`global.h:169-172` — `NORMAL, EASY, HARD, EXPERT`):

| Difficulty | Effect on flags |
|---|---|
| Easy | strips `CHECK_GOOD_MOVE` → `SEMI_SMART`; plain trainers forced to `CHECK_BAD_MOVE` only |
| Hard | every ordinary trainer gains `SEMI_SMART` |
| Expert | as Hard, **plus wild Pokémon become smart** |

Easy also cuts the go-for-the-kill rate fivefold: `killRate = AI_TRY_TO_KILL_RATE / 5`
(`ai_negatives.c:164-168`; base rate 50 at `config.h:152`).

Note the count mismatch: CFRU exposes four levels, Unbound's UI advertises four
(Vanilla / Difficult / Expert / Insane). The mapping between the two is **not verified** —
it depends on the var values Unbound writes, which are ROM data, not source.

**Stat cheats are real and live in team building, not the AI.** All gated on
`>= OPTIONS_EXPERT_DIFFICULTY`:

| Cheat | Location |
|---|---|
| Trainer mons get **31 IVs** across the board (player's partner excluded) | `build_pokemon.c:784-786` |
| Trainer moves get **max PP** (`0xFF` PP bonus) | `build_pokemon.c:1221-1226` |
| **252 EVs in the two best base stats**, for classes Unbound picks | `build_pokemon.c:1131-1135`, `GiveMon2BestBaseStatEVs` at `:1500` |
| Max friendship / zeroed friendship to power Return or Frustration | `build_pokemon.c:1137` |

Unlike Rejuvenation, none of these are raw damage multipliers — they are legal stat
values the AI could in principle have earned. The AI is not told about them separately;
its damage calc simply reads the inflated mons.

**What it does well, cheats aside.** Real damage calculation with caching
(`UpdateStrongestMoves`, `damageByMove`), 18 fight classes (`ai_advanced.c:25-49`,
11 singles + 7 doubles) with per-class doubles damage-priority tables driven by a written
design doc (`src/Battle_AI/Doubles AI Strategy.txt`), temporary Mega Evolution of every
battler so damage estimates use post-Mega stats (`TryTempMegaEvolveAllBanks`), and
`PredictMovesForBanks`, which runs the full scoring script *for every battler including
yours* to guess what each will do.

Move choice is strict: `ChooseMoveOrAction_Singles` keeps only exact top-score moves and
picks `AIRandom() % numOfBestMoves` among them — same discipline as Consistent AI and
Rejuvenation, no roulette, no Realidea-style chance of picking a move it scored as bad.

**Caveat — the version gap.** Unbound v2.1.1.1 shipped March 2023 (ROM mtime); the CFRU
commit read here is January 2025. Skeli maintains both, and Unbound was built against a
pinned private snapshot. **Nothing above is verified against the shipped binary.** This is
the same class of gap as the Ashen Frost `meta.txt`/bundle problem, and it is unresolved
in the same way: the fix is Ghidra + `GhidraGBA` on the ROM, or mGBA's debugger at runtime.
Treat the *logic* as high-confidence and any *specific line* as indicative.

---

### Radical Red — from the community write-up, not decompiled (added 2026-09-05)

Not analysed from the binary; recorded here because it is the one AI in the set with
a **documented hits-to-KO formula**, which is the gap the portable core has
(`PORTABLE-AI-REBORN.md`, backlog "damage race"). Source: the player-facing AI
description as relayed by the study's author. Treat as secondary until checked
against the CFRU-family source the way Unbound was.

- **Information:** knows the player's moves, abilities and items. Same omniscience
  class as Reborn Intense / Rejuvenation.
- **Anti-abuse switch counter** (the "cheat" is bounded and announced): starts at 0,
  +3 every time the player switches, −1 every turn, never below 0. At ≥9 there is a
  25% chance the anti-abuse AI activates on a turn the player switches; at ≥12, 33%;
  at ≥16, 50%. Any KO on either side resets it to 0. In other words the cheat is a
  *rate-limited switch predictor* keyed to how often the player has been pivoting —
  a design the other games never bother with (Reborn Intense predicts switches
  unconditionally via `swappredicted`).
- **Post-KO switch-in score** — simple and explicit, ties are coin flips except at 0:

  | condition | score |
  |---|---:|
  | the AI's candidate outspeeds | +14 |
  | the player's best move is a 4HKO or worse on it | +17 |
  | player 3HKOs it | +2 |
  | player 2HKOs it | −1 |
  | player OHKOs it | −14 |

  That is a damage race in five lines: speed order plus hits-to-KO from the
  opponent's side. The reverse side (how fast the switch-in kills the player's mon)
  is presumably in the move scoring, as in Reborn's %-of-current-HP scale.
- **Move-score bonuses** (the "priority" picture from the same write-up; these sit on
  top of a damage score where "most damaging moves" get +0, so the ladder is the
  whole tiebreak):

  | condition | bonus |
  |---|---:|
  | Explosion-type move, if the player's mon is faster, can 2HKO the AI mon, and the AI is not already dying to other moves | +10 |
  | fast kill (KO while faster) | +9 |
  | slow kill (KO while slower) | +6 |
  | speed setup move when the AI is slower | +6 |
  | other setup move | +5 |
  | Knock Off, or Thunder Wave when the AI is slower | +3 |
  | speed control (Bulldoze, Icy Wind and the like) | +2 |
  | most damaging move | +0 |

  General setup rule: if the AI does not see a kill and is faster and not OHKOed, it
  sets up; or if it does not see a kill, is slower and is not 2HKOed, it sets up.

  Read against the portable core: fast kill above slow kill is 0.4.0's priority/speed
  rule in one line; "set up when you cannot kill but they cannot kill you either" is
  a hits-to-KO condition Portable's `first_setup +55 / unsafe_setup −240` does not
  express (Portable asks only whether the *next* hit is lethal); speed control as its
  own tier and Knock Off as a tiebreak have no Portable equivalent.
- The hard-switch logic exists in the same write-up but was not captured here.

## Method notes (for repeating this)

- **v16 games** (Realidea, Pokémon Z): all code in `Data/Scripts.rxdata`. No Plugins folder
  exists — nothing separate to decompile. But **read `Game.ini` first**: v16 games often
  ship several bundles (Pokémon Z has `Data/Scripts.rxdata`, `Data/ScriptsBackup.rxdata`,
  and a root `Scripts.rxdata`), and only the one named in `Scripts=` is live.
- **In a monolithic v16 bundle, grep every section for the method you care about, in order.**
  Section order is load order, so the last definition wins. Realidea redefines
  `pbChooseMoves` 190 sections after the AI file; Pokémon Z does not. You cannot tell which
  case you are in without listing all definition sites.
- **v20/v21 games**: plugin source in `Plugins/<name>/`, compiled bundle in
  `Data/PluginScripts.rxdata`. **Always check the bundle, not just the folder** — see the
  Ashen Frost finding above.
- **Reborn-family games** (Reborn, Rejuvenation): a plaintext `Scripts/` folder with a
  *tiny* `Data/Scripts.rxdata` beside it. Don't ignore the stub — extract it and read it.
  In Reborn Yang it is 4 KB of loader ("script yeetifier pro") that evals `Scripts/*.rb` in
  the order given by `Data/!script_order.csv`, which is what proves the folder is live.
  A game with a **large** `Scripts.rxdata` and a plaintext folder is the dangerous case:
  the folder may be stale export, so compare before trusting it.
- `.rxdata` is Ruby Marshal 4.8. A zlib-header scan is unreliable and silently skips
  sections (it missed Phantombass entirely on first pass). Use a real Marshal parser.
  `PluginScripts.rxdata` structure: `[[plugin_name, meta_hash, [[script_name, deflated_code], …]], …]`.
- Useful greps: `OMNISCIENT_AI`, `PBTrainerAI\.`, `has_skill_flag?`, `pbAIRandom`,
  `@battle.choices[` (turn-prediction cheats), `!pbOwnedByPlayer` (asymmetric mechanics),
  `revealedMoves` (knowledge model).
- Distinguish **cheating** from **mechanic emulation**: an AI reading `battle.choices` may
  just be replicating Stakeout or Zoom Lens, which legitimately depend on turn order.
  Check the enclosing handler before calling it a cheat.

### GBA binary hacks (CFRU family — Unbound, and by extension most FireRed hacks)

Different engine, different method. **Do not try to decompile the ROM** — read the engine.

1. Identify the engine before touching the ROM. `xxd -l 192 rom.gba | tail -4` shows the
   game code at offset `0xAC`; `BPRE` = FireRed US. A 32 MB FireRed hack with Gen 8
   mechanics is almost certainly CFRU.
2. `git clone --depth 1 https://github.com/Skeli789/Complete-Fire-Red-Upgrade` — the AI is
   `src/Battle_AI/` (7 files, ~20k lines of C). This is the real logic, not a proxy.
3. **Find the private surface first.** Grep for `extern` declarations that have no
   definition in the repo; that set is exactly what the hack keeps to itself, and it is
   usually the tuning constants rather than the logic. Nine of them in Unbound's case.
4. `#ifdef <HACKNAME>` marks hack-specific branches — but filter false positives first:
   most `UNBOUND` hits are `SPECIES_HOOPA_UNBOUND`. Only 3 of 8 were real.
5. **`#ifdef VAR_GAME_DIFFICULTY` is the tell for a difficulty system.** It is undefined in
   stock CFRU, so anything inside it exists only in hacks that add one — including the
   entire anti-cheese/move-rechoosing layer.

Grep vocabulary for this engine:

| Pattern | Tells you |
|---|---|
| `REALLY_SMART_AI` | omniscience switch (CFRU's `OMNISCIENT_AI`) |
| `gChosenActionByBank[playerBank]` | turn-choice cheat — **the real one**; `bankAtkPartner` reads are legitimate |
| `LoadPartyRange(bankDef` / `defParty[` | bench peeking |
| `VAR_GAME_DIFFICULTY` | difficulty system exists; everything inside is hack-added |
| `gTrainers[...].aiFlags` | per-trainer skill (3 bits, not a 0-100 scale) |
| `build_pokemon.c` + difficulty | stat cheats live here, not in the AI |

Verifying against the shipped ROM (not done here) needs [Ghidra](https://ghidra-sre.org/)
plus the [GhidraGBA loader](https://github.com/SiD3W4y/GhidraGBA) — maps the ROM at
`0x8000000`. Set the `TMode` register context to 1 on functions or the decompiler emits
garbage; GBA game code is mostly THUMB. No symbols survive, so matching back to CFRU
function names is done by structure and string references. mGBA's debugger is the
runtime option.
