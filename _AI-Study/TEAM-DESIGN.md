# Trainer Team Design — Reborn Yang vs Realidea V4.1

Companion to `ANALYSIS.md`. That document compares battle **AI**; this one compares
what the AI is given to work with — **trainer team composition** — and ends with a
generation spec (§6) an LLM can follow to produce competent, progression-appropriate
replacement teams for Realidea. Motivation: a strong AI driving a bad team is still a
pushover, and Realidea's teams are the weakest input in the study.

> **Spoiler note.** This file names Realidea boss trainers and their rosters (that's
> the data), but deliberately contains no plot: no story events, no character
> relationships, no outcomes. Gym leaders are referred to by fight order.

All conclusions from data extraction, not playtesting. Extraction date 2026-09-03.

---

## 1. Where each game keeps its teams (method)

**Reborn Yang** — one authoritative compiled table: `Data/trainers.dat`
(Marshal; 294 populated trainer-type slots → name → partyId). Structure:
`dat[type_id][name][pid] = [[mon...], [trainer items]]`, where `pid ≥ 100` is the
Intense-mode variant of `pid − 100` (matches `$game_switches[3000]` in ANALYSIS.md).
Each mon record carries species, level, item, 4 explicit moves, ability slot, gender,
form, nature, a single IV value, and 6 EVs. `PBS/PBS/trainers.txt` (19,950 lines) is
the readable mirror but does **not** contain the story-fight parties (`pid 0`) — read
the `.dat` (decoder: `tools/dump_reborn_full.py` → `extracted/reborn-trainers-full.json`,
1,957 parties).

**Realidea V4.1** — almost nothing in `Data/trainers.dat` (1,158 bytes, **16
trainers**, all early-route filler). The real teams are inline Ruby in **map-event
scripts**: `createPokemon("SPECIES", level)` … `createTrainer(type_id, "Name", party)`
… `customTrainerBattle(...)`, defined in `265_Entrenadores.rb:105-184` (script index
from the extracted `Scripts.rxdata`). Marshal stores each event-script line as a plain
string in file order, so the roster is recoverable without a full map parse
(`tools/extract_realidea_battles.py` → `extracted/realidea-battles.json`,
178 battles / 406 mons across `Map*.rxdata` + `CommonEvents.rxdata`).

Realidea quirks that matter later:
- `createPokemon` **accepts an optional moveset** (`265_Entrenadores.rb:105`,
  `convertMoves` at `:150`) — and not one of the 406 call sites uses it.
- `PokeBattle_Pokemon` exposes every tuning lever: `setNature`
  (`123_PokeBattle_Pokemon.rb:328`), `iv` array accessor (`:12`), `ev` array,
  `setItem` (`:663`), `setAbility` (`:266`). `createTrainer` takes an `items=[]`
  4th arg for in-battle healing items. **Competent teams need zero engine changes.**
- Default construction (`PokeBattle_Pokemon.new(species, level)`): random IVs
  (`123_PokeBattle_Pokemon.rb:941`), nature from random personalID, ability slot from
  personalID (never hidden), last-4 level-up moves, no item, no EVs. This is what
  every Realidea enemy actually gets.
- A level-scaling mode exists (`$game_switches[289]/[290]` → `pbBalancedLevel−4+rand(5)`,
  `265_Entrenadores.rb:107-120`) — when on, enemies track the *player's* level with a
  −4 handicap and random moves/species "locke" options. The handicap direction is
  telling: the scaling mode makes enemies *weaker* than the player by construction.

## 2. Headline numbers

| metric (all extracted trainers) | Reborn Normal (pid 0) | Reborn Intense (pid ≥ 100) | Realidea V4.1 |
|---|---|---|---|
| trainer parties | 647 | 820 | 178 |
| enemy mons | 2,355 | 3,331 | 406 |
| holds an item | **70%** | **80%** | **7%** (29 mons) |
| has custom moves (all 4) | 75% (77% any) | **84%** | **0%** |
| nature chosen | 100% (stored per mon) | 100% | 0% — random |
| IVs chosen | 100% (tuned, see ramp §4) | 100% (31 on bosses from badge 1) | 0% — random 0–31 |
| EVs assigned | staged by progression (§4) | full spreads from badge 1; **>510 late** | ~1% (6 assignments game-wide) |
| hidden ability used | routinely (ability slot stored) | routinely | 2 mons game-wide |
| trainer healing items | bosses carry 2 (Potion→Hyper) | same | none via `createTrainer` items arg |
| modal party size | 6 for every boss | 6 | **2** (129 of 178 battles) |

## 3. Boss ladder, side by side

Reborn (Yang, Normal mode, `pid 0` story fights; n = party size):

| badge | leader | n | levels | items | 4 custom moves | avg IV | avg EV total | hidden abil. |
|---|---|---|---|---|---|---|---|---|
| 1 | Julia | 6 | 15–17 | 5/6 | 6/6 | 16 | 0 | 3 |
| 2 | Florinia | 6 | 23–25 | 6/6 | 6/6 | 24 | 0 | 0 |
| 3 | Corey | 6 | 27–29 | 5/6 | 6/6 | 17 | 0 | 1 |
| 4 | Shelly | 6 | 32–35 | 6/6 | 6/6 | 25 | 0 | 1 |
| 5 | Shade | 6 | 38–40 | 6/6 | 6/6 | 26 | 0 | 1 |
| 6 | Kiki | 6 | 42–44 | 6/6 | 6/6 | 31 | 169 | 2 |
| 7 | Aya | 6 | 43–46 | 6/6 | 6/6 | 31 | 140 | 2 |
| 8 | Serra | 6 | 48–50 | 6/6 | 6/6 | 31 | 85 | 0 |
| 9 | Noel | 6 | 54–55 | 6/6 | 6/6 | 31 | 339 | 2 |
| 10 | Radomus | 6 | 58–60 | 6/6 | 6/6 | 32 | 508 | 1 |
| 11 | Luna | 6 | 63–65 | 6/6 | 6/6 | 31 | 508 | 0 |
| 12 | Samson | 6 | 68–71 | 6/6 | 6/6 | 30 | 508 | 2 |
| 13 | Charlotte | 6 | 70–72 | 6/6 | 6/6 | 31 | 508 | 0 |
| 14 | Ciel | 6 | 75–78 | 6/6 | 6/6 | 31 | 508 | 2 |
| 15 | Adrienn | 6 | 78–81 | 6/6 | 6/6 | 31 | 508 | 1 |
| 17 | Hardy | 6 | 90–95 | 6/6 | 6/6 | 31 | 508 | 0 |
| 18 | Saphira | 6 | 95–100 | 6/6 | 6/6 | 31 | 676 | 1 |
| E4 | Heather/Elias/Anna | 6 | 100 | 6/6 | ≥5/6 | 31 | ~500 | 1–2 |
| final | Lin | 6 | 100 | 6/6 | 6/6 | 31 | **1512** | 1 |

(Titania and Amaria `pid 0` are 1-mon scripted events, real gym fights sit in other
pids; Terra `pid 0` is a lv-120 variant — Yang renumbered some fights. 508 EV total =
a full competitive 252/252/4 spread; 1512 = 252 in *all six stats*, an explicit
stat-cheat reserved for the final antagonist, same design honesty tier as the
Intense-mode switch documented in ANALYSIS.md.)

Reborn **Intense** (`pid 100+` variants of the same fights — the mode that also
forces AI skill 100 via `$game_switches[3000]`, ANALYSIS.md):

| badge | leader | n | levels | avg IV | avg EV total | Δlv vs Normal |
|---|---|---|---|---|---|---|
| 1 | Julia | 6 | 17–19 | **31** | **504** | +2 |
| 2 | Florinia | 6 | 23–25 | 31 | 353 | 0 |
| 3 | Corey | 6 | 28–30 | 31 | 471 | +1 |
| 4 | Shelly | 6 | 34–37 | 31 | 491 | +2 |
| 5 | Shade | 6 | 39–42 | 31 | 468 | +1 |
| 6 | Kiki | 6 | 44–47 | 31 | 546 | +2 |
| 7 | Aya | 6 | 45–47 | 31 | 537 | +1 |
| 8 | Serra | 6 | 49–53 | 31 | **669** | +2 |
| 9 | Noel | 6 | 55–57 | 31 | 582 | +1 |
| 10 | Radomus | 6 | 60–63 | 31 | 531 | +2 |
| 11 | Luna | 6 | 65–69 | 31 | 736 | +3 |
| 12 | Samson | 6 | 69–72 | 31 | 681 | +1 |
| 13 | Charlotte | 6 | 70–74 | 31 | 762 | +1 |
| 14 | Ciel | 6 | 75–77 | 31 | 801 | 0 |
| 15 | Adrienn | 6 | 81–85 | 31 | **1010** | +3 |
| 17 | Hardy | 6 | 90–94 | 31 | 512 | 0 |
| 18 | Saphira | 6 | 95–100 | 31 | **1406** | 0 |
| E4 | Heather/Elias/Anna | 6 | 101–105 | 31 | 1194–1376 | +1–5 |
| final | Lin | 6 | 105 | 31 | **1457** | +5 |

Intense's curve is a different philosophy from Normal's, and the distinction matters
for §6: levels barely move (+0–5), items and movesets are the same craft — the mode
is **stats-first**. Bosses open at the competitive ceiling (31 IV / ~508 EV at badge
1) and, from Serra on, quietly walk *past* the legal 510 cap into outright stat
cheating that a player cannot match (Charlotte 762, Adrienn 1010, endgame ~1400).
Across all 3,331 Intense mons the over-cap share grows from 3% under lv 20 to 59% in
the 51–70 band and 80% above 70. Difficulty therefore comes in two layers: a *fair*
layer (perfect tuning from the start) and an *unfair* layer (super-legal EVs late),
stacked on the forced skill-100 AI.

Realidea (all boss-class battles; gym leaders by fight order):

| fight | n | levels | items | custom moves | EVs/natures/IVs |
|---|---|---|---|---|---|
| gym 1 | 3 | 14 | 0 | 0 | none/random/random |
| gym 2 | 3 | 19–20 | 1 | 0 | " |
| gym 3 | 3 | 25–26 | 1 | 0 | " |
| gym 4 | 4 | 32–33 | 2 | 0 | " |
| gym 5 | 4 | 37–38 | 0 | 0 | " |
| gym 6 | 4 | 39–40 | 1 | 0 | " |
| gym 7 | 5 | 44–45 | 2 | 0 | " |
| gym 8 | 5 | 47–48 | 2 | 0 | " |
| villain-arc finale | **6** | 50–51 | **0** | 0 | " |
| optional superboss (Cintia) | 6 | 64–66 | **0** | 0 | " |
| recurring rivals (3) | 3–5 | tracks story | 0–2 | 0 | " |

Two things jump out. First, **the level curves are nearly identical** through the
mid-game (gym 4: Reborn 32–35 vs Realidea 32–33; gym 8: 48–50 vs 47–48). Realidea is
not easy because of levels — it's easy because every other slider is at zero. Second,
Realidea's *finale* carries no held items and default movesets: its climactic boss is
mechanically a route trainer with six slots. Its superboss — a borrowed Sinnoh
champion, correct species list (Spiritomb/Garchomp/Milotic/Lucario/Roserade/Gastrodon)
— is the same: no items, no Swords Dance, random nature Garchomp.

One Realidea structural bug worth fixing during regeneration: gym 1 fields a
**Vespiquen at level 14** (evolves at 21). Under-evolved species aren't inherently
wrong, but an *over*-evolved species at an impossible level breaks the stat budget in
the wrong direction too — it has worse stats than tuning a Combee line properly and
reads as an oversight, not a design choice.

## 4. What Reborn actually does — the difficulty ramp

Reborn's design insight, visible only in aggregate, is that **team quality is itself
the progression system**. Levels rise linearly; everything else is staged:

| band (lv) | IV avg | EV total avg | items | what unlocks |
|---|---|---|---|---|
| 1–20 | 10 | 0 | 20% | full parties, custom moves, natures, forms, hidden abilities |
| 21–35 | 12 | ~0 | 21% | berries/seeds everywhere on bosses |
| 36–50 | 17 | 18 | 39% | IVs climb; first EV investment on aces |
| 51–70 | 18 | 178 | 48% | half-spreads standard on bosses |
| 71–100 | 28 | 573 | 89% | full 252/252/4; choice/leftovers items; 31 IVs |

(2,355 Normal-mode mons, generic trainers included — boss-only numbers in §3 are
higher at every band.)

So a badge-1 Julia is *fair*: her mons have 10–22 IVs, no EVs, and hold Oran Berries,
not Choice Specs — but she already plays like a trainer: her Morpeko leads with
Parting Shot pivoting, Electroweb speed control, and an Adrenaline Orb punishes
Intimidate leads. The *shape* of a competitive team arrives at badge 1; the *stats*
arrive over 18 badges. Compare badge-4 Shelly (from `reborn-trainers-full.json`):

```
ILLUMISE   lv34 DAMPROCK     MODEST  HA  RAINDANCE/FLUTTERINGSCALES/DAZZLINGGLEAM/TAILWIND
ARAQUANID  lv33 SITRUSBERRY  -           STICKYWEB/BUBBLEBEAM/ICYWIND/LUNGE
ANORITH    lv33 TELLURICSEED ADAMANT     AQUAJET/BRICKBREAK/KNOCKOFF/ROCKSLIDE
RABSCA     lv32 GROUNDGEM    BOLD        FLUTTERINGSCALES/PSYBEAM/MUDSHOT/REFLECT
YANMEGA    lv33 CHARTIBERRY  MODEST      FLUTTERINGSCALES/GIGADRAIN/AIRCUTTER/ANCIENTPOWER
LEAVANNY   lv35 WIDELENS     ADAMANT     TRAILBLAZE/FELLSTINGER/SHADOWCLAW/GRASSWHISTLE
+ trainer items: 2× Hyper Potion
```

Every slot has a *job*: weather-setter lead (Damp Rock extends her rain, Tailwind
speed control), Sticky Web support, rain-abusing sweepers behind it, Reflect glue, an
anti-counter pick (Anorith's Rock Slide/Knock Off punishes the Fire types that
"should" beat Bug), and item-assisted accuracy on the sleep move. This is the
community-documented pattern — leaders build *around a win condition*, exploit their
field, and pre-punish the obvious counter-type
([TV Tropes catalog](https://tvtropes.org/pmwiki/pmwiki.php/ThatOneBoss/PokemonReborn),
[player discussion](https://www.rebornevo.com/forums/topic/23611-why-are-gym-leaders-so-hard-in-this-game/)).
Reborn pairs this with hard level caps (disobedience above cap), so the player can
never out-level the ladder — Realidea has no equivalent pressure, which makes team
quality matter even more.

The same pattern, pushed further, is the norm in the difficulty-hack canon:
[Run & Bun](https://www.pokecommunity.com/threads/pok%C3%A9mon-run-bun-v1-07.493223/)
(~500 battles, every one with custom movesets and synergistic parties; removes EVs
*symmetrically* so tuning is pure moveset/item/nature craft) and
[Radical Red](https://nuzlocketracker.org/guides/radical-red) (bosses get full
competitive EV spreads, optimal natures, items, meta-aware coverage). The shared core
across all three, and the thing Realidea lacks entirely: **hand-picked movesets and
items on synergistic parties, scaled by stage — never raw level inflation.**

## 5. Realidea's deficiency list (ranked by impact)

1. **No custom moves (0/406).** Last-4 level-up moves means no coverage, no setup,
   no hazards, no speed control, no recovery — the AI (already stock-v16, already
   skill-bugged per ANALYSIS.md) has nothing to select *between*.
2. **No held items (93% missing, 100% of the finale).** Berries/boost items are the
   cheapest legal power knob and the main comeback mechanic for an outnumbered boss.
3. **Boss parties too small** (3 at gym 1–3, 6 only at the finale). A 3v6 with no
   items is arithmetic, not a fight.
4. **Random natures/IVs, zero EVs.** Bosses can roll −Atk on a physical ace; there
   is no late-game stat growth to offset the player's EV-trained team.
5. **No roles/synergy.** Teams are "N mons of my type at the cap level" — no lead,
   no win condition, no anti-counter slot.
6. **No trainer healing items** despite engine support.
7. Cosmetic but real: over-evolved species at illegal levels (gym 1 Vespiquen).

## 6. Generation spec — LLM-produced replacement teams for Realidea

Target: teams matching **Reborn-Intense's curve** — perfect tuning (31 IV, full EV
spreads, items, hidden abilities) from gym 1, difficulty carried by craft rather
than level inflation, with Intense's late-game over-cap EV escalation available as a
deliberate, clearly-labeled cheat tier. Emitted in Realidea's own event-script
dialect so they are drop-in replacements for the existing
`createPokemon`/`createTrainer` blocks.

Two planning assumptions, both from the user:
1. **Curve = Intense.** A gentler Reborn-Normal ramp (stats grow with badges, §4
   band table) remains valid as an easy-mode knob, but the default schedule below
   is Intense-shaped: stats start at the ceiling, teams get *smarter* rather than
   *statier* as the game progresses.
2. **The AI will be upgraded.** Realidea currently runs stock v16 AI with the
   skillCode bug (ANALYSIS.md), but an improved AI (Reborn-style, probe-measured
   against the SIM-SPEC corpus) is planned. Teams are therefore generated for the
   *future* AI, not the current one — see the AI rule in §6.2. The probe harness can
   then measure team quality and AI quality as separable variables, which is the
   point of the study.

### 6.1 Output format (drop-in, engine-verified API)

```ruby
p0 = createPokemon("ILLUMISE", 33, [:RAINDANCE, :STRUGGLEBUG, :DAZZLINGGLEAM, :TAILWIND])
p0.setNature(:MODEST)
p0.iv = [31,0,25,25,25,31]          # HP,Atk,Def,Spd,SpA,SpDef — v16 order
p0.ev = [0,0,0,0,120,80]
p0.item = PBItems::DAMPROCK
p0.setAbility(2)                     # 2 = hidden ability slot
# ... p1..pN ...
party = [p0, p1, p2, p3]
trainer = createTrainer(33, "Abi", party, [PBItems::SUPERPOTION, PBItems::SUPERPOTION])
result = customTrainerBattle(trainer, "...")
```

Every call above exists today (`265_Entrenadores.rb:105/165`,
`123_PokeBattle_Pokemon.rb:12/266/328/663`). The moveset argument takes `:SYMBOL`s
(see `convertMoves`). Keep the surrounding event lines (speech, `pbSet`) untouched.

### 6.2 Stage table (the knob schedule, Intense-shaped)

Realidea's own level curve is fine — keep it (Intense barely raises levels either,
+0–5 across 18 badges; the mode is stats-and-craft-first). Bosses field **6 mons
from gym 1** — Reborn's rule at every difficulty, and the single cheapest fix to
Realidea's 3-mon gyms. Everything else opens at the ceiling and escalates only in
set sophistication and — late, and only if the Intense-style cheat tier is wanted —
EVs past the legal cap:

| stage | boss n | generic n | IV (boss) | EV total (boss) | items | moves | abilities | trainer items |
|---|---|---|---|---|---|---|---|---|
| gym 1 (lv ~14) | **6** | 2 | 31 | ~460–508 | 6/6 on boss (berries/seeds) | 4 custom, ≤1 setup move | HA where it matters | 2 Potion |
| gym 2 (~20) | 6 | 2 | 31 | ~460–508 | " | 4 custom | " | 2 Super |
| gym 3 (~26) | 6 | 2–3 | 31 | 508 | + first boost items | full sets, + hazards/screens | " | 2 Super |
| gym 4 (~33) | 6 | 2–3 | 31 | 508 | Leftovers/Choice OK | + weather/room cores | " | 2 Hyper |
| gym 5 (~38) | 6 | 3 | 31 | 508 | " | full competitive | " | 2 Hyper |
| gym 6 (~40) | 6 | 3 | 31 | 508 *(cheat tier: ~550–650)* | " | " | " | 2 Hyper |
| gym 7 (~45) | 6 | 3 | 31 | 508 *(cheat tier: ~650–750)* | " | " | " | 2 Hyper |
| gym 8 (~48) | 6 | 3 | 31 | 508 *(cheat tier: ~700–800)* | " | " | " | 2 Hyper |
| finale (~51) | 6 | — | 31 | 508 *(cheat tier: ~800–1000)* | 6/6 mandatory | " | " | 2 Full Restore |
| superboss (~65) | 6 | — | 31 | 508 *(cheat tier: ~1400)* | canonical champion sets | " | " | 2 Full Restore |

Generic-trainer stats stay a step behind the bosses (Intense's own aggregate: avg IV
18–29, half-spreads) so bosses remain the spikes in the difficulty profile.

Hard rules regardless of stage:
- **Legality:** species must be obtainable at that level (no lv-14 Vespiquen — use
  the pre-evo, or raise the gym's cap); moves must be in the species' learnset/TM
  pool at that gen; item must exist in Realidea's `items.txt`. Validate every
  generated identifier against `PBS`/extracted data — a typo'd `:SYMBOL` raises at
  event-run time, not compile time.
- **The cheat tier is a decision, not a default.** Legal ceiling = IV ≤ 31, EV total
  ≤ 510, ≤ 252 per stat. The italicized over-cap values mirror what Intense actually
  ships (Serra 669 → Lin 1457, §3) and are what "matching Intense's curve" means
  late-game — but generate both variants (legal + cheat) per boss from gym 6 on, so
  the choice stays revertible and testable. Never exceed the cap silently: every
  over-cap mon gets a `# CHEAT-TIER` comment in the emitted Ruby.
- **Design for the future AI, not the current one.** Sets should be fully
  competitive — pivots (U-turn/Parting Shot), hazards + removal, redirection,
  Trick Room sequencing, setup sweepers — i.e. the toolkit Reborn's AI demonstrably
  uses (ANALYSIS.md, SIM-SPEC §9.8–9.9). Until the AI upgrade actually lands, tag
  sets whose value depends on AI competence with `# AI-DEP:<feature>` (prediction
  moves like Counter/Mirror Coat, Wish-tect loops, sac-and-pivot lines, doubles
  redirection): stock v16 AI has no accuracy model, no stat-stage floor, and
  near-vestigial switching (SIM-SPEC §9.7–9.8), so those sets underperform today and
  the tags mark exactly which teams to re-probe after integration. Greedy-good moves
  (strong STAB, setup, high-accuracy status) need no tag — they work under both AIs.

### 6.3 Composition rubric (what "competent" means per team)

Every boss team must answer six questions — this is the Shelly pattern from §4:
1. **Win condition** — which mon or engine closes the game (setup sweeper, weather
   core, Trick Room bruiser)? Name it in a comment.
2. **Lead with a job** — hazards, weather, screens, or speed control on turn 1.
3. **Coverage skeleton** — team's STABs + coverage hit every type for at least
   neutral; no mono-attacking teams.
4. **Anti-counter slot** — one mon that punishes the type that "should" beat this
   gym (Shelly's Rock Slide Anorith vs Fire).
5. **Glue** — one support set: screens, status, Knock Off, or healing.
6. **Item logic** — each item states its purpose (extend win condition, patch speed,
   emergency berry). No itemless boss mons at any stage (Intense curve).

Generic trainers get a lighter pass: 2–3 mons, custom moves, thematic coherence with
their trainer class, items only on the last mon from mid-game. They exist to drain
resources, not to wall progress — Run & Bun's "you're just another trainer in the
world" framing.

### 6.4 LLM prompt skeleton

```
You are generating a replacement team for one trainer in Pokémon Realidea V4.1
(Essentials v16, gen-7-era dex — verify every species/move/item/ability symbol
against the attached lists).

Context: <stage row from §6.2> · trainer class/theme: <type, personality>
· fight format: <single/double> · player's likely roster: <starters + gift mons
+ strong route encounters available by this stage>

Produce: (a) a party matching the §6.2 knobs and §6.3 rubric, (b) one comment
line per mon naming its role, (c) the exact Ruby block in §6.1 format —
from gym 6 on, emit BOTH the legal-EV variant and the cheat-tier variant,
marking over-cap mons with # CHEAT-TIER, (d) # AI-DEP:<feature> tags on any
set that needs the upgraded AI (§6.2), (e) a self-check list confirming
legality of every symbol used.
```

Feed it `extracted/realidea-battles.json` (what the team replaces),
`extracted/reborn-trainers-full.json` (1,957 exemplar parties — few-shot gold), and
the game's PBS lists as ground truth. Generate → validate symbols mechanically
(script the check; don't trust the self-check) → drop into the event script →
re-probe the AI on the SIM-SPEC corpus with the new team as context.

### 6.5 Scaling to all 178 battles (tiering + cost control)

Gyms and the finale are not the whole difficulty surface — rivals, villain-team
admins, and named one-offs are "important fights" too. But per-fight LLM craft for
178 battles is neither affordable nor necessary. The extraction sorts the problem:

| tier | count | what | generation strategy |
|---|---|---|---|
| S — bosses | **32** | 8 gyms, villain admins/execs (Lilliana, Jeremiah, Silver, Atlas, …), 3 recurring rivals (Owen ×5, Alba ×4, Teresa ×3), finale, superboss, named one-offs | full §6.3 rubric, LLM-crafted |
| A — minis | 3 | non-boss fights already fielding 3+ | Tier-S treatment, batched in |
| B — filler | 143 | 1–2 mon route trainers | **never individually LLM-generated** — archetype templates |

Four cost levers, in order of impact:

1. **Rivals are arcs, not fights.** Owen/Alba/Teresa account for 12 of the 32 boss
   battles, and Realidea already keeps their species identity across encounters
   (§3). Generate each rival **once**: a 6-mon endgame team plus a growth timeline
   (evolution stages, when each slot joins, when items/EVs appear per §6.2), then
   *slice* it per encounter. 12 generations become 3, and the rival's team develops
   coherently alongside the player's — which is also just better storytelling.
2. **The villain org gets one shared identity pool.** A single generation defines
   the org's species pools and signature tactics (grunt pool, admin pools, boss
   aces); every admin fight draws from it. Admins stay distinct (each gets a
   personal win condition) but the org reads as one faction, and one call sets up
   ~8 fights.
3. **Filler comes from templates, not the LLM.** One generation writes an archetype
   per trainer *class* (METISO, ESTUDIANTE, MEDIUM, NADADORA, …): theme species
   pool, item policy, 2–3 set skeletons. A deterministic script then instantiates
   all 143 fights from the stage table + parsed learnsets — legal by construction,
   zero marginal LLM cost, and regenerable for free when the dex or curve changes.
4. **A mechanical validator makes generation one-shot.** The expensive part of the
   gym-1 pilot was hand-verifying every symbol against PBS. Script it
   (species-in-dex, move-in-learnset/TM, item-exists, ability-slot, EV/IV caps,
   evolution-level legality) and the LLM loop becomes: generate cheap → validate →
   regenerate only the failures. No trusted self-checks, no manual audits.

Net cost: ~20 generation units for all of Tier S (8 gyms + ~8 villain fights + 3
rival arcs + finale/superboss/one-offs), batchable 4–6 per call ≈ **4–5 LLM calls**,
plus one archetype call for all 143 filler fights. Versus 178 per-fight sessions.

**Deployment without touching 30+ maps.** The teams live in one generated Ruby file
(a registry hash), injected into `Scripts.rxdata` as a single section — the same
proven method as the probe adapter (`adapters/realidea/AI_Probe.rb`). A small patch
to `createTrainer` looks up the registry by `(type_id, trainer_name, original ace
level)` — the ace level disambiguates recurring rivals — and swaps in the curated
party, falling back to the original for anything unregistered. Map events stay
byte-identical: fully diffable, fully revertible, one injection point.

---

## 7. Files

| file | what |
|---|---|
| `tools/extract_realidea_battles.py` | map-event roster extractor (strings-scan method, §1) |
| `tools/dump_reborn_full.py` | trainers.dat → JSON decoder (type/name/pid, Intense = pid+100) |
| `extracted/realidea-battles.json` | 178 battles / 406 mons, per-battle map + party |
| `extracted/reborn-trainers-full.json` | 1,957 decoded parties, Normal + Intense + postgame |
| `tools/realidea_data.py` | parsed PBS tables: dex, learnsets, TM lists, items, evolution floors |
| `tools/validate_team.py` | §6.5 lever 4 — mechanical legality gate for team JSONs |
| `generated/archetypes.json` | §6.5 lever 3 — per-class themes (mined from Reborn analogues) |
| `tools/generate_filler.py` | seeded generator: archetype + stage knobs → 123 filler teams |
| `tools/emit_registry.py` | teams JSON → `Team_Overrides.rb` (Ruby 1.8, fail-safe fallback) |
| `generated/teams_boss.json` / `teams_filler.json` | canonical team data (validator-clean) |
| `adapters/realidea/Team_Overrides.rb` | the injected section: registry + `createTrainer` patch |

Deployment state (2026-09-03): `Team_Overrides` is injected into Realidea's
`Data/Scripts.rxdata` (section 330, before `Main`), carrying the gym-1 team +
101 deduped overrides. Pre-injection backup:
`backups/realidea_Scripts.rxdata.pre-teams`; pristine original:
`backups/realidea_Scripts.rxdata.orig`. The patch is untested at runtime
(no Ruby available in the analysis environment) — boot the game once before
trusting it; revert = copy the backup over `Data/Scripts.rxdata`.

Sources: [TV Tropes — That One Boss: Pokémon Reborn](https://tvtropes.org/pmwiki/pmwiki.php/ThatOneBoss/PokemonReborn) ·
[Reborn forums — gym difficulty thread](https://www.rebornevo.com/forums/topic/23611-why-are-gym-leaders-so-hard-in-this-game/) ·
[Run & Bun design thread](https://www.pokecommunity.com/threads/pok%C3%A9mon-run-bun-v1-07.493223/) ·
[Radical Red boss data](https://nuzlocketracker.org/guides/radical-red) ·
[GamesRadar on Run & Bun difficulty](https://www.gamesradar.com/this-might-be-the-hardest-pokemon-game-ever-and-only-two-people-have-ever-beaten-it/)
