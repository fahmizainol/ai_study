# One AI, Many Essentials Versions

Feasibility study and design thesis for a **drop-in battle AI that installs across
Essentials versions** using the engine's own plugin framework.

Companion to `ANALYSIS.md` (what each game's AI does) and `SIM-SPEC.md` (how to measure an
AI's decisions). This document answers a different question: *if we had a better AI, could
one package ship it to all of these games?*

Written 2026-09-04. All version claims below are read out of the local installs, not from
the Essentials changelog.

> **New here?** Skip to [Appendix A — the whole thing in plain terms](#appendix-a--the-whole-thing-in-plain-terms-realidea) for a jargon-free walkthrough of how the AI gets in and how we prove it's better, using Realidea as the worked example. The sections below are the technical backing for that story.

> **Implementation update (2026-09-04):** the engine-free core and first v16 adapter are
> now implemented and injected into Realidea as an opt-in `Portable_AI` section. The full
> applicable corpus passes **163/163** (stock: 143/163), and the frozen seeded gauntlet
> improves from **20/40 to 28/40 wins**. See `PORTABLE-AI-REALIDEA.md`. The v19/v20/v21
> adapters described below remain future work.
>
> **Second adapter (2026-09-04, later the same day): Reborn Yang.** Despite Reborn being
> out of scope as a *port target*, an adapter was built into it as a *benchmark arena* —
> it is the only engine where the portable core and the study's reference AI can fight
> head-to-head. Core bumped to 0.2.0 (status-kind tags, phaze/charge/HP-cost rules,
> partner-hostility rejection — a real doubles bug the corpus caught). Full corpus
> **169/169 with zero skips** (the five field scenarios run natively), Tier-2 vs the
> Realidea portable build ρ = 0.941 / 99.2% action agreement. See
> `PORTABLE-AI-REBORN.md`; the head-to-head gauntlet itself is the next artifact.

---

## Thesis

**Yes — but the portable unit is a decision core plus a per-era adapter, not an AI file.**

Three findings drive the whole design:

1. **The plugin framework covers three of the five versions here.** v16 and v17 have no
   `PluginManager` at all, so those games need script injection instead. Same core, second
   delivery path — and that path already exists in this repo for Realidea.
2. **v19 → v20 is nearly free; v20 → v21 is a rewrite.** v19 and v20 expose the same AI
   method names with the same signatures and the same 100-point baseline. v21 replaced the
   entire structure with wrapper objects and a handler registry.
3. **The thing that actually breaks portability is the move-effect namespace, and it is
   avoidable.** Key the effect table on **move ID**, not on the engine's function code, and
   three renames stop mattering at once.

The honest cost estimate: the core is written once, each adapter is 200–400 lines, and the
per-move effect table is the bulk of the work regardless of how many versions you target.

---

## 1. Engine census

Every Essentials game in `../`, by what it actually declares:

| Game | Version | Evidence | Script layout | Plugin framework |
|---|---|---|---|---|
| Realidea V4.1 | **v16-era** | no version constant; 529 `PBSpecies` refs | monolithic `Data/Scripts.rxdata`, 333 sections | **none** |
| Pokémon Z V2.13 | **v16.2-era** | same; `Essentials 16.2` in ported plugin comments | monolithic, 235 sections | **none** |
| Pokemon Empire | **v17.2** | `ESSENTIALSVERSION = "17.2"` (`Win32API` section) | monolithic, 229 sections | **none** — no `PluginScripts.rxdata` |
| Pokemon Empire Expanded | **v17.2** | same bundle | monolithic, 229 sections | none |
| Pokemon Hegemony | **v19.1** | `001_Settings.rb:449` `module Essentials; VERSION = "19.1"` | `Data/Scripts/` folder | yes |
| Ashen Frost | **v20.1** | `001_Settings.rb:413` | `Data/Scripts/` folder | yes |
| Grueling Gold (both copies) | **v20.1** | `001_Settings.rb:436` | `Data/Scripts/` folder | yes |
| Ancient Platinum | **v21.1** | `001_Settings.rb:544` | `Data/Scripts/` folder | yes |
| Reborn Yang | Reborn E19.16 fork, v16-era base | no version constant; `PBSpecies` | plaintext `Scripts/` + loader stub | n/a |
| Rejuvenation v13 | v16-era fork | no version constant; `PBSpecies` | plaintext `Scripts/` | n/a |

Reborn and Rejuvenation are **out of scope** by decision — they are diverged forks with
their own field-effect systems and 17k–35k-line AIs. Nothing below assumes them.

---

## 2. The three interface eras

|  | v16 / v17 | v19.1 | v20.1 | v21.1 |
|---|---|---|---|---|
| AI owner | `class PokeBattle_Battle` | `class PokeBattle` + `module PBTrainerAI` | `class Battle::AI` + `module PBTrainerAI` | `Battle::AI` + `AIBattler` / `AIMove` / `AITrainer` |
| Scoring entry | `pbGetMoveScore(move, attacker, opponent, skill = 100)` | `pbGetMoveScore(move, user, target, skill = 100)` | **identical to v19** | `pbGetMoveScore(targets = nil)` on the move wrapper |
| Selection | `pbChooseMoves(index)` | `pbChooseMoves(idxBattler)` | `pbChooseMoves(idxBattler)` | `pbChooseMove(choices)` + `pbGetMoveScores` |
| Effect dispatch | `case move.function` / `when 0x0A` — **hex ints** | `when "000"` — **numeric strings** | `when "AddSpikesToFoeSide"` — **descriptive strings** | **handler registry**, keyed by the same descriptive names |
| Skill model | numeric tiers 1 / 32 / 48 / 100 | numeric tiers | numeric tiers | `has_skill_flag?("PredictMoveFailure")` |
| Switch entry | `pbEnemyShouldWithdraw?` | same | same | `Handlers::ShouldSwitch.add` |
| Base score | 100 | 100 | 100 | `MOVE_BASE_SCORE = 100` (`005_AI_ChooseMove.rb:7`) |
| Size | 4,360 (Realidea) / 4,418 (Z) | 4,444 / 6 files | 4,897 / 8 files | 4,940 / 12 files **+ 8,328** in `006_AI MoveEffects/` |

v21's registry, by call site count in Ancient Platinum — this is the only version with a
*designed* extension surface for AI:

| Handler | Registrations |
|---|---|
| `Battle::AI::Handlers::MoveEffectAgainstTargetScore` | 145 |
| `Battle::AI::Handlers::MoveEffectScore` | 116 |
| `Battle::AI::Handlers::MoveFailureAgainstTargetCheck` | 82 |
| `Battle::AI::Handlers::MoveFailureCheck` | 80 |
| `Battle::AI::Handlers::ItemRanking` | 48 |
| `Battle::AI::Handlers::MoveBasePower` | 46 |
| `Battle::AI::Handlers::AbilityRanking` | 20 |
| `Battle::AI::Handlers::GeneralMoveAgainstTargetScore` | 15 |
| `Battle::AI::Handlers::ShouldSwitch` | 11 |
| `Battle::AI::Handlers::GeneralMoveScore` | 7 |

Registration form:

```ruby
Battle::AI::Handlers::MoveEffectScore.add("RaiseUserAttack1",
  proc { |score, move, user, ai, battle|
    next ai.get_score_for_target_stat_raise(score, user, move.statUp)
  }
)
```

**What is genuinely portable across all four eras:** score-each-move-then-pick, a 100-point
baseline, a switch decision hook, per-trainer skill, and the concept of a per-move-effect
adjustment. That is enough to hang a shared core on.

**What is not:** class names, the effect-code namespace (renamed twice), the skill
representation, and — in v21 only — the battler API, which goes through wrappers
(`has_type?`, `rough_end_of_round_damage`, `base_stat`) rather than the battler itself.

---

## 3. The move-ID trick

The effect table is the expensive part of any AI, and it is the part that looks
unportable: `0x0A` → `"000"` → `"AddSpikesToFoeSide"` is two renames across four versions.

**Key the table on move ID instead.** `:THUNDERWAVE` is `:THUNDERWAVE` in every version
back to v16 (as `PBMoves::THUNDERWAVE`, trivially mapped). The function codes were renamed;
the moves were not. So:

- one canonical effect taxonomy, authored once, keyed `move_id → effect_descriptor`
- adapters resolve the engine's move object to an ID, nothing more
- unrecognised moves fall back to a generic damage/status heuristic

This buys a second thing for free. Every game in this study adds custom moves, abilities
and items — Pokémon Z alone adds a `HEMORRAGIA` status and ~10 custom abilities. A
function-code-keyed table has nothing to say about those; a move-ID-keyed table with a
sane fallback degrades to "score it as a damaging move with a status rider" instead of
failing. The cost is that you must enumerate the moves you care about — roughly 250
competitively relevant ones covers real play.

---

## 4. Architecture

```
plugin/
  001_core_*.rb        pure Ruby, ZERO engine calls
                       - role/archetype assignment
                       - switch policy
                       - prediction + memory model
                       - difficulty knobs
                       - score aggregation (max / roulette / compression)
                       - move-ID → effect scoring table
  002_adapter_v19.rb   } version-guarded; see the eval constraint below
  003_adapter_v20.rb   }
  004_adapter_v21.rb   }
  005_hook_*.rb        per-era override that installs the core
```

The **core** consumes a normalized snapshot and returns a decision. It never touches
`@battle`, a battler, or a move object.

Each **adapter** supplies the same ~12–15 primitives, and that list is the real contract:

| Primitive | v19 / v20 source | v21 source |
|---|---|---|
| rough damage | `pbRoughDamage` | `AIMove#rough_damage` |
| type effectiveness | `pbCalcTypeMod` | `ai.effectiveness_of_type_against_battler` |
| stat with stages | `pbRoughStat` | `AIBattler#rough_stat` |
| status / effects | battler directly | `AIBattler#status`, `#effects` |
| side hazards | `@battle.sides[]` | same, via `ai.battle` |
| move category / priority / PP | move object | `AIMove` wrapper |
| party contents | `@battle.pbParty` | `AIBattler#pb` |
| skill / difficulty | numeric `skill` | `has_skill_flag?` |
| RNG | `pbAIRandom` | `pbAIRandom` |

The **hook** is where each era differs:

| Version | Install method |
|---|---|
| v16 / v17 | inject a script section into `Data/Scripts.rxdata`, reopen `PokeBattle_Battle`, alias `pbGetMoveScore` / `pbChooseMoves` |
| v19 / v20 | plugin script reopening the same two methods (`class Battle::AI` in v20, `class PokeBattle` in v19) |
| v21 | plugin registering `Handlers::GeneralMoveScore` / `ShouldSwitch`, or overriding `pbGetMoveScores` for full control |

---

## 5. Packaging in the plugin framework

Good news, verified in all three loaders:

- **v19 does not check the Essentials version at all.** `readMeta` has no `ESSENTIALS`
  case; unknown meta keys fall through to `meta[property.downcase.to_sym] = data[0]`
  (`Pokemon-Hegemony-Release/…/005_PluginManager.rb:522`). An `Essentials = 19.1,20,21`
  line is stored and ignored.
- **v20 and v21 parse it as a comma list and only warn on mismatch**:
  `Console.echo_warn "…may not be compatible… Trying to load anyway."`
  (v20 `:638`, v21 `:619`). It is not a gate.

So **one plugin folder can legitimately declare `Essentials = 19.1,20,20.1,21,21.1`** and
load everywhere. Two constraints to design around:

1. **Every script in the plugin is eval'd, unconditionally.** Folder-level `meta.txt`
   enable/disable only affects recompilation, not execution — this is the Ashen Frost trap
   in `ANALYSIS.md`. An adapter file that names `Battle::AI::AIBattler` at load time will
   raise on v19. Guard by string-resolving constants, or wrap each adapter in
   `if Essentials::VERSION.start_with?("21")`.
2. **Load order is alphabetical by plugin folder, adjusted by `REQUIRES`**
   (`sortLoadOrder`, `005_PluginManager.rb:573`). If another AI plugin loads after yours,
   it wins.

For v16/v17 there is no framework and no folder — the plugin becomes an injected script
section. That pipeline already exists here (`tools/emit_registry.py`, `tools/pack_rxdata.py`,
with `ruby -c` syntax verification on the injected section), built for Realidea, and
applies unchanged to Pokémon Z and to Empire.

---

## 6. The real obstacle is contention, not versions

**All four** plugin-capable games have already replaced their AI. Not one of them would
receive this plugin onto stock Essentials:

| Game | Installed AI | Size |
|---|---|---|
| Hegemony (v19.1) | Phantombass 1.0.0, live | 15,456 / 9 files |
| Ashen Frost (v20.1) | Consistent AI 1.0.1 live; Phantombass 9.0 in the folder but not in the bundle | 8,966 / 4 |
| Grueling Gold (v20.1) | **Phantombass AI 1.0** in the compiled bundle, **plus** Deluxe Battle Kit, two of whose scripts define `pbChooseMoves` / `pbGetMoveScore` themselves | 15,145 / 8, + 10,078 DBK |
| Ancient Platinum (v21.1) | Phantombass 1.0.0 (the v21 rewrite) | 4,840 / 9 |

Grueling Gold is the worst case and the instructive one: **three layers already contend**
for the same methods — stock `011_Battle/005_AI/`, Phantombass, and Deluxe Battle Kit's
Essentials patches — resolved only by plugin load order. A fourth arriving without a
declared position is a coin flip.

So in practice a portable AI is not overriding stock Essentials — it is contending with an
installed plugin that overrode it first, and load order decides. Required behaviour:

- detect a foreign AI at boot (does `pbGetMoveScore` still have the stock arity? is
  `PBAI` defined?) and report which one is live in the console
- either defer with a loud warning, or re-alias on top deliberately
- declare `CONFLICTS` / `INCOMPATIBLE` in `meta.txt` for the known families

Silently double-overriding is how you end up debugging an AI that is half yours.

---

## 7. This is measurable, and that is the point

The reason to build this here rather than anywhere else: the corpus and the comparison
tooling already exist, so a port that is normally unfalsifiable — "feels about the same" —
gets a number instead.

**What is already built** (`SIM-SPEC.md`, `tools/`):

| Artifact | State |
|---|---|
| `scenarios.json` | **126 scenarios / 169 assertions, 169/169 on the reference AI** |
| `probe_results_reference.ndjson` | 115 probed positions — Reborn Yang, the reference |
| `probe_results_hegemony.ndjson` | 115 — PBAI on v19; 134/163 assertions over 121 probeable |
| `probe_results_realidea.ndjson` | 73 — stock v16 at skill 100; ρ = 0.887, top-1 91.7% |
| `adapters/realidea/AI_Probe.rb` | the only engine-side probe written so far (v16) |
| `tools/check_scenarios.py` | Tier 1 — property assertions, gates correctness |
| `tools/ai_diff.py` | Tier 2 — Spearman ρ on the score *ordering*, not the chosen action |

**The corpus is per-game, and that matters for this project.** `make_scenarios.py` takes a
scenario set written in readable names and resolves it against *that game's own PBS*,
emitting an engine-readable `Data/ai_scenarios.txt` (IDs only) plus the JSON with
assertions. Move and species IDs differ per install, so each adapter is probed on its own
build of the same corpus — the scenarios are shared, the ID files are not:

```bash
python3 tools/make_scenarios.py --pbs "<game>/PBS" \
    --out-engine "<game>/Data/ai_scenarios.txt" --out-json scenarios_<game>.json
```

**The acceptance test for a portable AI**, stated concretely:

1. Tier 1 must not regress per adapter — the core's assertion pass rate on v21 must match
   its rate on v20, or the adapter is dropping information the core needs.
2. Tier 2 **adapter-vs-adapter**: run the same core through the v19/v20/v21 adapters and
   correlate their score vectors against each other. This is the check that does not exist
   yet in the study, because until now every AI compared was a *different* AI. Here the AI
   is identical by construction, so anything below ρ ≈ 0.99 is an adapter bug, not a
   difference of opinion — a far sharper instrument than cross-engine comparison.
3. Tier 2 against `probe_results_reference.ndjson` for absolute quality, same as every
   other AI in `ANALYSIS.md`.

**Not yet built:** an engine-side probe for v19, v20 or v21. `adapters/realidea/AI_Probe.rb`
is v16-only, installed by inserting an `AI_Probe` section before `Main` and patching `Main`
(`SIM-SPEC.md:697`). On v19+ the same probe becomes a plugin instead of an injected
section, which is strictly easier — and it is the first thing to write, before any AI code,
because it is what makes every later claim checkable.

**Pokémon Z is the cheapest first probe target.** It is v16, so `AI_Probe.rb` applies with
the injection path already proven on Realidea; it runs a near-identical scorer; and its
shipped skill values are 100 where Realidea's are 32–60. Probing it answers "what is stock
v16 skill gating worth?" against data already collected — and it exercises the whole
probe → assertions → ρ pipeline on a second game before any portable-AI code exists.

---

## 8. Recommended scope

**Target v20.1 + v21.1 first.** That covers Ashen Frost, both Grueling Gold copies, and
Ancient Platinum — 4 of the 5 plugin-capable installs — and spans the one genuine
architectural break, so nothing later invalidates the core's shape. Develop against
**Grueling Gold**, because its three-way contention (stock + Phantombass + Deluxe Battle
Kit) is the hardest install target in the set; anything that survives there installs
cleanly elsewhere. v19 follows almost free
from v20 (same method names, same signatures; only the effect-code namespace differs, and
the move-ID keying makes that a non-issue).

Fold v16/v17 in last, as an injector build over the same core: Realidea, Pokémon Z, and
both Empire builds. Those four are also where a better AI changes the most, since three of
them ship the stock scorer.

Build order that follows from §7: **probe first, AI second.** Write the v20 probe plugin,
derive a Grueling Gold corpus with `make_scenarios.py`, and collect
`probe_results_gruelinggold.ndjson` for the AI that is *already installed* there
(Phantombass 1.0). That baseline costs one game launch, gives the study its first v20
datapoint, and means the portable AI can be measured against the thing it would replace
from its first commit.

## 9. Build or fork?

The obvious shortcut is to fork an AI that already works — Phantombass is installed on three
of the four plugin-capable games here. **Don't.** Write the decision core fresh, and harvest
the move-effect knowledge from stock v21.

**The census already refutes the fork.** Phantombass ships as 15,145 lines / 8 files on
v19–v20 and 4,840 lines / 9 files on v21 (§6). Those are not the same codebase — its own
answer to the v20→v21 break was a rewrite. Forking it does not yield a portable artifact; it
yields the porting problem already answered by duplication, and two divergent forks to
maintain from day one.

Three further reasons, in descending force:

1. **Portability is an architectural property none of the candidates have.** §4 requires a
   core with zero engine calls fed by a normalized snapshot. Every existing AI is entangled
   with its engine by construction — `@battle`, battler objects, move objects, throughout.
   Disentangling 15k lines someone else wrote costs more than writing the ~1k fresh.
2. **A fork would be blind.** No v19/v20/v21 probe exists yet (§7), so Phantombass's
   behaviour is currently unmeasured here. There is no way to tell which of its lines are
   load-bearing.
3. **It would contend with itself.** Shipping a Phantombass derivative into Hegemony,
   Grueling Gold or Ancient Platinum puts two descendants of the same AI on `pbGetMoveScore`,
   resolved only by load order — the §6 failure mode, self-inflicted.

Consistent AI is a worse donor again: its edge is substantially *cheating* (reading the
player's registered choice at 30/50/70% by difficulty, `ANALYSIS.md`). That is a difficulty
knob, not a decision engine.

**But "from scratch" applies only to the core.** The expensive part of any battle AI is the
per-move effect table (§3), and one donor is already decomposed into exactly the needed
shape: stock v21's `006_AI MoveEffects/` — 8,328 lines across ~600 handler registrations
(§2), one handler per effect, keyed on a descriptive effect name. Re-keying those from
`"AddSpikesToFoeSide"` to `:SPIKES` is §3's trick applied to a corpus already written and
debugged, and v21 is the only version in the census authored against a deliberate extension
surface rather than by monkey-patching.

| Piece | Source | Why |
|---|---|---|
| Decision core (roles, switch policy, aggregation, difficulty) | **fresh** | must be engine-free; nothing existing is |
| Move-effect table | **harvested from stock v21**, re-keyed to move ID | ~600 handlers, already one-per-effect |
| Adapters (v16 / v19 / v20 / v21) | **fresh**, 200–400 lines each | this *is* the portability work |
| Phantombass / Consistent AI / Reborn | **oracles, not donors** | probe and measure against; do not fork |

That last row is what the tooling makes cheap. `probe_results_reference.ndjson` already
treats Reborn Yang as the quality target without borrowing a line of it. Existing AIs are
worth more as measured baselines — "the thing the port must beat on the corpus" — than as
source, and that use carries no licensing question at all.

**Gate before harvesting anything: licensing.** Confirm what Essentials' terms permit for
redistributing `006_AI MoveEffects/` inside a plugin, and confirm separately for Phantombass
before borrowing even a heuristic. **Unverified — neither has been checked.**

This decision does not change §8's build order. The v20 probe plugin is still the first
artifact, because "harvest v21's table" only becomes checkable once a corpus can be scored
on v20 and v21.

## Open questions

- **Does the core need doubles?** v16's doubles path scores each move against both
  opponents and scales by partner impact; v21 handles targets natively through
  `pbGetMoveScoreAgainstTarget`. Deciding whether the core models targets or the adapter
  does is the first real design fork.
- **How much of `PBTrainerAI`'s skill scale survives?** v21's flag-based model does not map
  onto 0–100 cleanly in either direction. Proposal: the core owns a small ordered set of
  capability flags, each adapter derives them from whatever the engine has.
- **Unverified:** everything here is read from source. No adapter has been booted in v19,
  v20, or v21 yet — only the Realidea (v16) injection path has actually run.

---

## Appendix A — the whole thing in plain terms (Realidea)

A jargon-free version of §4–§7, grounded in one game. If you can only explain this to
someone once, explain it like this.

**The goal.** Realidea's trainers make dumb moves — using Earthquake on a Flying-type it
can't even hit, buffing when they should just KO you. We want to drop in a smarter "brain"
that picks better moves, *without* rewriting the game.

### Part 1: how the new brain gets in

Realidea's whole game logic is one big file — picture a **stack of index cards** the game
reads top to bottom. There's a golden rule:

> If two cards define the same thing, the **last one wins.**

So we don't erase the game's original AI card. We slip a **new card near the bottom** that
says "actually, choose moves like *this*." The game reads the old way, then reads ours last
— and ours is the one that sticks. The original is still sitting there untouched, so undoing
it is just pulling our card back out. Clean revert, nothing broken.

This isn't a wild idea — two things in the game already work exactly this way (a level-cap
tweak and a trainer-team swap; see `adapters/realidea/Level_Cap.rb` and `Team_Overrides`).
The AI upgrade is the same trick pointed at a different spot.

Why cards and not a normal "mod"? Newer fangames (v19+) have a proper plugin folder you
drop mods into. Realidea is older (v16) — no folder, so injecting a card into that one file
*is* how you mod it. It's also built to **fail safe**: if the new brain ever hits something
it doesn't understand, it quietly falls back to the original behaviour instead of crashing.

### Part 2: how we prove the new brain is actually better

If we swap in a "smarter" AI, how do we know it's smarter and didn't just break something?
We can't hand-play 178 battles. So instead of *playing*, we give the AI a **flash-card
exam.**

Each flash card is one frozen battle moment with an obviously-right answer:

- Garchomp knows Earthquake, facing a Skarmory that's immune to it → **don't pick Earthquake.**
- AI can KO this turn or waste the turn buffing → **KO.**
- AI is at full HP with a healing move → **don't heal.**

There are well over a hundred of these cards (`scenarios.json` — 126, of which ~73 apply to
Realidea once Reborn-only field scenarios are skipped), each with its own answer key. A probe tool
(`adapters/realidea/AI_Probe.rb`) builds each position, asks the AI "what would you do
here?" — *without actually playing the turn* — writes down its answer, then moves on. A
grader (`tools/check_scenarios.py`) marks the answers and prints a score like "63/80."

So the process is: **exam the current AI (baseline) → slip in the new card → exam again →
compare.** Two guardrails keep it honest:

- The **current** AI has to ace the exam first. If it flunks a card, we assume *our card* is
  wrong, not the AI — a test the normal AI can't pass is a bad test.
- The new AI only counts as better if it flips FAILs into PASSes **without** breaking any
  card that used to pass. No regressions hiding behind a higher total.

### The punchline

> We're not asking anyone to *trust* that it's smarter. We inject one new AI card, run the
> exam before and after, and can say: **"stock AI got 63/80, our version got 80/80 — here
> are the exact situations that flipped."** And because the original was never touched,
> uninstalling is just deleting the card.

**One honest footnote:** this full inject-and-exam loop is done and working for Realidea
(v16). The newer-engine games can take the same brain, but their exam-runner (an engine-side
probe for v19/v20/v21) isn't built yet — that's the next piece, and per §7 it's the first
thing to write.
