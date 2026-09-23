# Run & Bun: Difficulty Curve, Team-Building, and Boss Teams vs Smogon

Companion to `BOSS-CURVE.md` (Reborn's power curve), `TEAM-CORPUS.md` and
`MONOTYPE-SYNERGY.md` (what real Smogon teams do). This one takes a finished,
well-regarded hard fangame, **Pokémon Run & Bun**, and asks three questions:

1. How does its difficulty progress, boss and filler, against the level cap?
2. How are its teams built, measured with the same code as the Smogon corpus?
3. Do the boss teams hold up against real Smogon teams when stats and AI are equal?

**The answer, in one paragraph.** Run & Bun's difficulty is carried by stats, not by
team-building. Levels barely move (fillers sit 2-4 under the cap all game, bosses at it);
perfect IVs are worth about four levels; what climbs is BST, items, team size, then
legendaries and megas. Its teams are coverage-heavy hyper offense — setup at the Smogon
rate, almost no utility, **zero hazard removal on any trainer in the game** — and
defensively no better arranged than random draws from their own pool, where Smogon teams
are clearly better than random. Put on equal terms (level 100, no EVs, 31 IVs, no Tera,
Foul Play piloting both sides), **the singles bosses win 56 of 160 (35%)** against
BST-matched gen 9 Smogon teams. And none of the static metrics — BST, coverage holes,
role counts — predicts which bosses do well: every correlation sits inside what luck
alone produces at this sample size.

Everything regenerates from `tools/rnb/` (§8).

## 1. Data

Source: the game's public documentation (`extracted/runandbun-MANIFEST.txt`) — the
trainer sheet's ten tabs as CSV plus `Mechanic Changes.txt`. Parsed: **436 trainers,
1,832 Pokémon**, every species and move resolving in Showdown's gen 9 dex.

- **Story order** is the tab order, which the sheet never states; it was read off the
  boss level caps in `Mechanic Changes.txt` (23 cap-raising fights, 12 → 99).
- A **segment** is the run of trainers fought under one cap; each trainer takes the cap
  of the next boss that raises it.
- **Base stats are Showdown's gen 9 numbers.** The docs carry none, so any species Run &
  Bun rebalanced is off.
- Run & Bun has **no EVs**, and every opponent runs **31 IVs**. A trainer's stats are
  therefore fully determined by base stats, level and nature, and the power index below
  is exact rather than a guess.

**Power index** = mean of a team's six-stat total (its level, 31 IV, its nature, 0 EV) ÷
the same for a reference player mon at the cap (BST 500, 15 IV, neutral). 1.00 is stat
parity with a sensible player mon.

## 2. The difficulty curve

`python3 tools/rnb/difficulty_curve.py`

| Segment (cap) | Filler lv − cap | Filler BST | Filler size | Filler items* | **Filler power** | **Boss power** | Boss BST |
|---|--:|--:|--:|--:|--:|--:|--:|
| R104 Grunt (12) | −3.8 | 298 | 2.7 | 19% | 0.60 | 0.78 | 310 |
| Museum (17) | −2.9 | 330 | 3.2 | 60% | 0.71 | 0.80 | 347 |
| Brawly (21) | −2.8 | 367 | 3.0 | 60% | 0.77 | 0.89 | 410 |
| Roxanne (25) | −2.2 | 424 | 3.1 | 54% | 0.88 | 1.01 | 485 |
| Chelle (32) | −4.0 | 480 | 4.0 | 37% | 0.92 | 1.02 | 488 |
| **Wattson (35)** | −2.9 | 440 | 3.9 | 48% | 0.92 | **1.13** | 540 |
| Rival Cycling Rd (38) | −3.3 | 476 | 3.3 | 71% | 0.95 | 1.04 | 505 |
| Norman (42) | −3.3 | 496 | 4.4 | 68% | 0.99 | 1.05 | 501 |
| Vito 1 (48) | −3.5 | 493 | 3.5 | 61% | 0.99 | 1.07 | 508 |
| Maxie Chimney (54) | −3.6 | 488 | 3.4 | 84% | 0.99 | 1.11 | 528 |
| Flannery (57) | −3.5 | 503 | 3.8 | 87% | 1.02 | 1.13 | 525 |
| Shelly (65) | −3.9 | 478 | 4.1 | 86% | 0.98 | 1.16 | 558 |
| Winona (69) | −1.9 | 486 | 4.2 | 92% | 1.03 | 1.16 | 549 |
| Rival Lilycove (73) | −2.9 | 496 | 4.2 | 88% | 1.03 | 1.18 | 570 |
| Archie Mt. Pyre (76) | −2.6 | 491 | 4.1 | 88% | 1.03 | 1.16 | 549 |
| Maxie Hideout (79) | −3.5 | 500 | 4.8 | 100% | 1.04 | 1.23 | 591 |
| Matt (81) | −2.3 | 499 | 5.1 | 98% | 1.05 | 1.19 | 571 |
| **Tate & Liza (85)** | −2.2 | 497 | 5.8 | 92% | 1.06 | **1.27** | 618 |
| Archie Seafloor (89) | −2.2 | 521 | 5.1 | 92% | 1.09 | 1.23 | 591 |
| Juan (91) | −1.8 | 510 | 5.8 | 92% | 1.07 | 1.19 | 563 |
| **Vito 2 (95)** | −0.7 | 531 | 6.0 | 89% | 1.12 | **1.15** | 533 |
| Elite Four + Wallace (99) | — | — | — | — | — | 1.25 | 595 (Wallace 629) |

\*Share of mons holding anything better than Oran/Sitrus/Lum/status berries or Berry Juice.

- **Levels are not the lever.** Fillers sit 2-4 under the cap all game; bosses at it, the
  ace +1 from Flannery on (+2 for Juan and Vito 2).
- **Perfect IVs are worth ~4 levels.** 31 vs 15 IV is ×1.08 on every stat at any level;
  fillers running ~3 under the cap roughly cancels it, which is why filler power hovers
  at 1.00 from Norman to Juan.
- **The early game is the steep part.** Filler BST 298 → 480 from cap 12 to 32; fully
  evolved share 7% → 100% by Chelle.
- **Then filler quality plateaus.** Caps 32-89: filler BST flat at ~480-520. What grows
  is team size (≈3.5 → 6), items (≈50% → 92%) and doubles (82% of the fillers before
  Tate & Liza).
- **The boss curve is a sawtooth.** Spikes at Roxanne (485 BST at L25), Wattson (first
  mega + legendary at L35), Maxie Hideout and Tate & Liza — 1.27, above the Elite Four.
  Dips at the Cycling Road rival and a slide from Archie through Juan to Vito 2.
- **The boss-filler gap opens then closes:** ≈0.1 early, 0.15-0.2 mid, **0.03 at Victory
  Road**, where full-six fillers at the cap nearly match Vito.
- Densest stretches: Shelly (30 fillers), Vito 1 (26), Chimney (23).

Fillers above the cap, worth checking in the sheet: Wally's L43 Kirlia at cap 35 (beside
a L7 Zigzagoon — a typo or scripted fight); Fisherman Phil's L70/80/90 Luvdisc at cap 65;
L100 mons on Victory Road Triathlete Darren (a Pikachu) and optional Ninja Boy Jack.
Optional trainers come in flat blocks (L50, 75, 80, 95-96), 2-3 mons and below the cap
until the post-Victory Road full sixes.

## 3. Gym themes: two strict monotypes

| Leader | On-theme | Off-theme members |
|---|---|---|
| Brawly (Fighting) | 4/6 | Lopunny, Poliwhirl |
| Roxanne (Rock) | 4/6 | Bisharp, Zygarde-10% |
| **Wattson (Electric)** | **6/6** | — |
| Norman (Normal) | 5/6 | Azumarill |
| **Flannery (Fire)** | **6/6** | — |
| Winona (Flying) | 4/6 | Volcarona, Altaria-Mega (Dragon/Fairy once it evolves) |
| Tate / Liza (Psychic) | 3/4, 4/4 | Zoroark |
| **Juan (Water)** | **2/6** | Sneasler, Glalie-Mega, Salamence, Glastrier |

Juan is effectively a hail team — his gym's underground has permanent Hail. The Elite
Four and Wallace are 4-5 of 6 on theme, the rest legendary coverage.

## 4. Team-building, measured like the Smogon corpus

`python3 tools/rnb/team_synergy.py` — roles are `team_shape.ROLE_MOVES`, coverage is
`archetype_coverage.profile`, theme weaknesses `mono_synergy.score`; the corpus rows are
800 gen 9 OU and 800 National Dex teams through the same code. 34 boss fights (rival
variants counted once; 9 are doubles or tag battles), 62 six-mon fillers.

### Roles: pure offense

| role | singles bosses | doubles bosses | 6-mon filler | gen9 OU | gen9 NatDex |
|---|--:|--:|--:|--:|--:|
| hazards | 36% | 0% | 39% | 81% | 90% |
| **removal** | **0%** | 0% | **0%** | 58% | 67% |
| setup | 72% | 11% | 81% | 79% | 83% |
| pivot | 20% | 0% | 6% | 68% | 73% |
| recovery | 64% | 33% | 39% | 73% | 84% |
| status | 16% | 0% | 13% | 50% | 67% |
| Taunt | 0% | 11% | 2% | 21% | 25% |
| speed control | 24% | **89%** | 44% | 27% | 21% |
| protect | 32% | **78%** | 50% | 40% | 40% |

Setup is the one role at the Smogon rate. That is TEAM-CORPUS §2's **hyper offense**
shape. The doubles bosses are genuinely built for doubles (Tailwind/Icy Wind/Trick Room,
Protect, 26% of all bosses carry Fake Out). Broader move lists barely move it: adding
Flip Turn / Chilly Reception / Shore Up takes boss pivoting from 15% to 18%; sleep and
paralysis moves take status to 38% of bosses — still under the corpus.

### Moves: more attacks, wider coverage

| per mon | bosses | filler | gen9 OU | gen9 NatDex |
|---|--:|--:|--:|--:|
| damaging moves | **77%** | 72-74% | 64% | 62% |
| attack types | **2.85** | 2.7 | 2.36 | 2.24 |
| single attacking type | 6% | 7-9% | 15% | 19% |

Offensive reach (share of the game's own defending typings a team hits ×2) is 91%,
level with the corpus's 92%.

### Defence: arranged no better than chance

Raw, and in brackets the residual against 150 shuffles of the same pool (negative =
better arranged than random):

| | bosses | 6-mon filler | gen9 OU | gen9 NatDex |
|---|--:|--:|--:|--:|
| blind (types nobody resists) | 3.53 (+0.71) | 2.82 (−0.27) | 1.15 (−0.77) | 0.71 (−0.80) |
| stacked (≥3 weak) | 1.97 (±0.00) | 1.63 (−0.08) | 1.49 (−0.50) | 1.32 (−0.49) |
| **holes** (stacked, nobody resists) | **0.68** (+0.09) | 0.37 (−0.15) | 0.21 (−0.26) | 0.07 (−0.30) |

The corpus is better than its null on every axis; Run & Bun sits at or above its own.
The bosses' +0.71 blind is the price of type themes. Worst holes: Glacia (Fire, Rock,
Steel), Brawly (Fairy, Flying), Roxanne (Fighting, Water), Flannery (Rock and Water — all
six weak to each), Drake (Dragon, Fairy), Tate (Bug), Liza (Ghost).

### Theme weaknesses

| | Run & Bun gyms/E4/Champion (50 pairs) | Smogon monotype, gen 9 |
|---|--:|--:|
| ≥1 member resists or is immune | **50%** | 31% |
| best is neutral | 46% | 61% |
| nothing under ×2 | 4% | 8% |
| members still weak (per 6) | 3.58 | 4.18 |

Run & Bun answers its themes *better* than real monotype — by breaking the theme
(Bisharp on Roxanne, Nidoking on Sidney, Goodra-H and Swampert-Mega on Wallace).
Uncovered: Flannery's Rock and Water, Liza's everything, Glacia's Fire/Rock/Steel,
Drake's Dragon/Fairy.

### Modes

Few bosses build a weather or terrain *team*: Wallace (rain, 3 abusers), Seafloor Archie
(rain, 2), Maxie at the Magma Hideout (sun: Tangrowth, Houndoom-Mega), Maxie & Tabitha
(sand: Garchomp-Mega), Glacia (snow: Arctovish). Flannery's sun, and the Psychic Terrain
on Liza, Vito 2 and the Cycling Road rival, have no abuser. 49 of 304 fillers set any
mode. Area weather from `Mechanic Changes.txt` is not counted.

## 5. The battles: Run & Bun bosses vs Smogon teams

### Setup

Two Foul Play bots (pmariglia/foul-play, poke-engine 0.0.48, 500 ms MCTS per decision)
on a local Showdown 0.11.11 server, in a custom format `gen9nationaldexrnb`: gen 9 with
NatDex Mod (megas, past items), **no learnset validation** (Run & Bun movesets are not
Showdown-legal), Terastal Clause, level 100.

- **Both sides on Run & Bun's rules:** level 100, **0 EVs** (Smogon spreads dropped,
  natures kept), 31 IVs, no Tera. What differs is the six sets and how they fit together.
- **22 singles bosses** (doubles and tag fights excluded; grunts have 3 mons) × **4
  Smogon teams each**, matched on mean BST (drawn from the 20 nearest), **× 2 rounds**.
- **Tate and Liza are excluded from every result.** The sheet lists them as separate
  4-mon `[Boss]` entries with no `[Double]` tag, but they are one double battle; as
  singles they played 4-v-6. Final sample: **20 bosses, 160 battles**.
- **Opponent pool: 1,688 genuine gen 9 teams** (1,111 Ubers, 483 National Dex, 94 AG) —
  see §7 for why the file names could not be trusted.
- Each bot infers the other's unseen sets from Smogon data (National Dex Ubers usage,
  EV spreads included — so each overestimates the other's stats equally). Run & Bun's
  odd sets fool the Smogon-side bot more than standard sets fool the Run & Bun side:
  a small edge to Run & Bun.

### Results

`python3 tools/rnb/summarize_battles.py`

**Run & Bun wins 56/160 = 35% (95% CI 28-42%)** — 31/94 against National Dex, 25/66
against Ubers/AG. Wins and losses both average 32 turns.

| Boss | Cap | BST | W-L | P(this extreme by luck) |
|---|--:|--:|:-:|--:|
| Brawly | 21 | 410 | **0-8** | 0.03 |
| Roxanne | 25 | 485 | **6-2** | 0.03 |
| Chelle | 32 | 488 | 1-7 | 0.17 |
| Wattson | 35 | 540 | 1-7 | 0.17 |
| Rival, Cycling Road | 38 | 499 | 2-6 | 0.43 |
| Norman | 42 | 501 | **6-2** | 0.03 |
| Vito 1 | 48 | 508 | 2-6 | 0.43 |
| Maxie, Mt. Chimney | 54 | 528 | **0-8** | 0.03 |
| Shelly | 65 | 558 | 3-5 | 0.57 |
| Winona | 69 | 549 | 2-6 | 0.43 |
| Rival, Lilycove | 73 | 569 | 4-4 | 0.29 |
| Maxie, Magma Hideout | 79 | 591 | 2-6 | 0.43 |
| Matt | 81 | 571 | 3-5 | 0.57 |
| Archie, Seafloor | 89 | 570 | 3-5 | 0.57 |
| Vito 2 | 95 | 533 | 5-3 | 0.11 |
| Sidney | 99 | 584 | 4-4 | 0.29 |
| Phoebe | 99 | 569 | 3-5 | 0.57 |
| Glacia | 99 | 598 | 3-5 | 0.57 |
| Drake | 99 | 605 | 5-3 | 0.11 |
| Wallace | 99 | 629 | 1-7 | 0.17 |

### Nothing static predicts a boss's win rate

Correlation of win rate with each metric across the 20 bosses:

| BST | cap | blind | stacked | holes | reach | setup | recovery | hazards | priority | pivot |
|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| +0.16 | +0.25 | −0.09 | +0.05 | +0.07 | −0.00 | +0.16 | +0.10 | +0.09 | +0.15 | −0.26 |

Pure binomial noise at these sample sizes reaches |r| = **0.44** at its 95th percentile
(simulated in the script). Every metric is inside it. Wallace has the game's highest BST
(629) and goes 1-7; Vito 2, one of the lowest late BSTs (533), goes 5-3.

Four records are individually unlikely at a 35% base rate (p ≈ 0.03 each): Roxanne and
Norman at 6-2, Brawly and Mt. Chimney Maxie at 0-8. Across 20 bosses about one such
record is expected by chance, so there is a little real spread — not much. Brawly's is
partly the pairing: at BST 410 (half his team is unevolved) the only Smogon teams that
low are stall built on Chansey/Clodsire/Mega Sableye, which burn and wall an all-physical
Fighting team.

## 6. What it means for team-building

1. **Run & Bun's bosses borrow their strength from stats.** Equal stats, equal AI: they
   lose two in three to real teams. In the game they are at the cap against a capped,
   random-IV player with no bag. Stats and structure are separate difficulty knobs, and
   Run & Bun turned the first — the "bolted-on" difficulty the top-level README describes.
2. **Don't fix a Run & Bun-style team by ticking the Smogon checklist.** The corpus shows
   the checklist *describes* strong teams (§4); here it does not *rank* them. Adding
   Defog or a pivot to every boss may help — this data cannot say it will. It is
   TEAM-CORPUS §4's lesson again: a metric that describes Smogon teams is not
   automatically what wins.
3. **A hypothesis worth testing, not a finding:** the losing end is heavy with
   *conditional* sets. Wallace: Choice Band Barraskewda with two moves, Curse/Rest
   Goodra-H, Tail Glow Manaphy, the lowest reach of any boss (77%). Chelle: two-move
   Normalize Delcatty, crit gimmicks. Mt. Chimney Maxie: Red Card Crustle, Shadow Tag
   Wobbuffet on Counter/Mirror Coat/Encore, Iron Defense/Dragon Tail Kommo-o. Roxanne,
   Norman and Vito 2 run plainer, self-sufficient sets. If it holds, the rule is: every
   slot should be worth clicking in most matchups.
4. **For this project:** a generator should be judged by *playing* its teams, as here,
   not by its role and coverage scores. And since both sides here had a strong search
   AI while Run & Bun's own AI is far weaker, better piloting may matter more than
   better teams.

The next step is the method that has worked elsewhere in this repo: render Wallace's
seven losses and Mt. Chimney Maxie's eight next to Roxanne's and Norman's wins, and read
what decided them.

## 7. What did not survive checking

- **`gen9ubers.json` is mostly not gen 9.** 2,004 of its teams predate gen 9 and 935 more
  are not gen-9 legal. The first run used it unfiltered, and Wattson's one early win was
  over a gen 1 team with "No Ability". Those 34 battles were discarded
  (`generated/rnb/results_mislabelled_pool.ndjson`). The README trap that a normal
  format file "really is that format" does not hold for this file.
- **Mid-run readings that died:** "the legendary-heavy mid-game bosses cannot win" was a
  round-1 artifact (Shelly, Winona, Maxie Hideout and Matt all won in round 2), and the
  late bosses caught up (Elite Four 15-17).
- **A name lookup scored the wrong teams.** Two Vitos and two Maxies share a name; keyed
  by name, the per-boss metrics for one fight were computed from the other's team. The
  first correlations reported were wrong in detail (not in conclusion). Metrics are now
  keyed by trainer index, with an assert.
- **Mt. Chimney Maxie is not a sun team** — that is the Hideout Maxie. Swapped once in
  discussion for the same reason.
- **Stalled battles were Showdown's per-IP throttle**, not the teams or the login: 12
  "battles and team validations" per IP per 3 minutes, refused with a popup the bots
  ignore, so both wait forever. Two earlier fixes (local login without the public login
  server; waiting for the rename to be confirmed) are kept but were not the cause.
  `nothrottle`/`noipchecks` in the server config fixed it.
- **0-turn "wins" are abandoned rooms**, from bots re-using usernames across a restart;
  both sides logged themselves the winner. Now errors, with fresh usernames per attempt.
- One battle (19 turns) took 40 minutes wall-clock across a session restart; both logs
  agree on the winner and show no error, so it counts.

Foul Play needed four crash fixes for this format (`tools/rnb/foul_play_rnb.patch`).
None changes a decision in a battle that completed — each replaces a crash with the
behaviour every surviving battle already had.

## 8. Reproduce

```
python3 tools/rnb/parse_trainers.py        # sheet CSVs -> generated/rnb/trainers.json
python3 tools/rnb/difficulty_curve.py      # §2   (-> rows.json)
python3 tools/rnb/team_synergy.py          # §4   (needs generated/showdown_dex.json:
                                           #       SHOWDOWN_DIR=... node tools/dump_showdown_dex.js)
python3 tools/rnb/make_battle_teams.py 4   # §5 schedule + team files (byte-identical to the run's)

# the battles: Windows Python, NOT from WSL (a full run in WSL crashed the machine)
python tools/rnb/setup_battles.py          # foul-play + patch + engine, showdown + format
python tools/rnb/start_server.py           # (own window; leave it running)
node tools/rnb/validate_teams.js           # every team must pass the custom format
python tools/rnb/run_battles.py 3 2        # 3 at a time, 2 rounds; resumable, retries failures
python3 tools/rnb/summarize_battles.py     # §5
```

A full run is ~2 hours at 3 workers on 5 cores. Search is time-based, so oversubscribing
the CPU does not slow the run — it quietly weakens both bots.

## 9. Files

| | |
|---|---|
| `extracted/runandbun/` | the ten sheet tabs (story order) and `Mechanic Changes.txt` |
| `generated/rnb/trainers.json`, `rows.json` | parsed trainers; per-trainer curve rows |
| `generated/rnb/pairs.json`, `teams/` | the 88 pairings and the 110 exported team files |
| `generated/rnb/results.ndjson` | every battle attempt (latest clean one per tag counts) |
| `generated/rnb/results_mislabelled_pool.ndjson` | the discarded first 34 battles (§7) |
| `tools/rnb/` | the scripts above, `foul_play_rnb.patch`, `FOUL_PLAY_COMMIT`, the Showdown format |

Raw bot logs (~120 MB) are not kept.

## 10. The boss generator's teams against the same bosses

Follow-up, 2026-09-23. The question: do the teams `generate_bosses.py` builds for Realidea
hold up where real Smogon teams do? Same rules as §5 (L100, 0 EV, 31 IV, natures kept, no
Tera, Foul Play v Foul Play at 500 ms); each generator team plays the 4 Run & Bun singles
bosses nearest its mean BST, 3 rounds. **Realidea's trainer names are spoilers**, so
teams are `gym1..9`, `boss1..7`, `rival1..3` everywhere.

| Opponent of the Run & Bun bosses | battles | wins | same bosses v gen 9 Smogon (§5) | paired z |
|---|--:|--:|--:|--:|
| generator gyms (monotype, 9 teams) | 108 | **25.9%** | 62.8% | +9.1 |
| generator bosses + rivals (no theme, 10 teams) | 120 | **27.5%** | 66.2% | +10.2 |
| gen 7 Smogon teams (80 teams, Z-crystal teams dropped) | 156 | **67.9%** | 64.6% | −1.0 |

"Paired" scores each battle against that same boss's record v gen 9 Smogon teams, so the
mix of bosses a pool happened to draw cancels out.

**Ruled out:**
- **The monotype theme.** Generator teams with no theme lose as often as the gyms, in
  every BST band (7/24 v 7/24 under 500, 5/16 v 7/24 at 500-550, 7/32 v 8/32 above).
- **The gen 7 ceiling** (Realidea's dex stops at gen 7; Run & Bun and §5's teams do not).
  Real gen 7 teams, held to the same ceiling, beat these bosses as often as gen 9 teams.
- **Stat spread.** At matched BST the generator's species average base Speed 82-83,
  best attacking stat 109, 35% at Speed ≥ 100 — the same as either Smogon pool (81,
  108-110, 31-32%). Bulk is 10-25 points lower.
- **Passengers.** Slots that never contribute (no KO, under 2 turns on the field) are
  21.8% / 18.8% of generator slots and 21.1% of real gen 7 slots.
- **Attack count.** 62-63% of generator moves attack, v 57-62% for Smogon teams.

**What the full battle logs show** (round 3 and the last ~150 gen 7 battles, from
Showdown's own logs via `read_battles.py`): every generator slot is less effective, not a
few of them. KOs per slot per battle: generator 0.41 / 0.45, real gen 7 0.67. The setup
users are the sharpest case — generator teams put a setup move on 32-39% of slots (gen 7
Smogon 10%, gen 9 Smogon ~30%: 1.82 setup mons a team), use it about as often (32-33% of
battles v 38%), and get **half the KOs** from it (0.51-0.53 v 0.99 per battle).

**Not settled.** Why each slot is weaker. One generator-specific candidate is `fidelity`:
the generator starts from a published set and replaces the moves a species cannot know
at its in-game level, which at L100 are just worse moves. Intact sets (4 of 4 kept) do
KO more, 0.50 per battle v ~0.34 for 2-3 kept (456 slot-battles), but the trend is not
monotone and strong species may simply be the ones whose sets survive — a minor factor
at most.

**The ablation settles it: the species, not the sets.** Same generator species on the
**unmodified published sets** the generator started from (`make_gen_battles.py
--published`; 112 of 114 slots have one, and it changes 0.6-0.7 of 4 moves per slot),
identical pairings and rounds, played on Windows at 4 workers:

| | generator sets | published sets |
|---|--:|--:|
| gyms | 28/108 (25.9%) | 35/108 (32.4%) |
| bosses + rivals | 33/120 (27.5%) | 42/120 (35.0%) |
| pooled | 61/228 (26.8%) | 77/228 (33.8%) |

Battle for battle, published sets won 44 the generator lost and lost 28 the generator
won (sign test p = 0.076): the generator's move swaps cost about **7 points**, suggestive
but not significant here. Real teams win ~65% against the same bosses, so the move
swaps explain at most a quarter of the ~38-point gap. **The rest is which species, and
which sets, the generator puts together** — the published sets it picks are not bad on
their own, but six of them chosen this way do not make a team that wins.

**Cohesion is not it either** (`make_collage.py`). The 78 gen 7 teams were shuffled
into collages: repeated swaps of similar-BST sets between teams, so every one of the
468 sets is used exactly once, only 9 stay on their own team, and each team's mean BST
moves 2.4 on average (max 5). Same pairings, 2 rounds:

| | wins |
|---|--:|
| gen 7 teams, intact | 106/156 (67.9%) |
| the same sets, shuffled | 102/156 (65.4%) |

Battle for battle the collages lost 29 the intact teams won and won 25 they lost (sign
test p = 0.68). Six sets do not need to have been written together: six sets from six
different real teams are as strong. So the generator assembling slots independently is
not what costs it, and neither are cores — a separate check found the generator already
fields the species cores real teams use wherever the dex and band allow them (gym4 all
of its Ice cores; gyms 1, 6 and 8 have none to use). What remains is **the sets
themselves**: at the same BST, the sets the generator ends with are weaker than real
teams' sets. One thing the shuffle cannot rule out: it keeps the POOL's mix (about 46%
defensive items, 23% one-attack walls), so a team may still need a typical balance of
roles, and the generator's sets have a different balance.

A first version drew replacements instead of swapping and favoured some sets: the
sets it left out had KO'd 0.79 a battle in the intact run against 0.64 for the ones it
used, which would have made collages look weak for the wrong reason.

**Traps met on the way** (all fixed in the tools):
- On a machine where 127.0.0.1 has no rDNS and something listens on port 80, Showdown
  calls localhost an open proxy and locks every bot (`setup_battles.py` now declares
  loopback residential).
- Foul Play indexed a revealed 5th move as `move:4` after truncating the moveset to 4 —
  a poke-engine panic (fixed in `foul_play_rnb.patch`).
- Foul Play cannot pilot a team holding two formes of one species (gen 7 AG allows three
  Arceus); such pairings are dropped whole, not kept where the crash happened not to fire.
- Scraped sets record move/item SLOTS ("Focus Blast/Dragon Pulse"); the first option plays.
- Showdown's `config.js` hot-reloads, so turning on `logchallenges` mid-run logged the
  rest of that run too.
- Load spikes to 13+ on 6 cores came from 4 battles searching at once (each decision
  forks two searches per bot), not from other jobs; iteration counts track the position,
  not the load, so no measurable weakening was found. 11 gym battles that overlapped a
  real other-session job are listed in `generated/rnb_vs_gen/contended.txt`; dropping
  them moves the gyms from 25.9% to 23.7%.

```
python3 tools/rnb/make_gen_battles.py 4 [--trainers]          # -> generated/rnb_vs_gen[_trainers]/
RNB_OUT=generated/rnb_vs_gen7 python3 tools/rnb/make_battle_teams.py 4 --gen7
RNB_OUT=generated/rnb_vs_gen python3 tools/rnb/run_battles.py 4 3
RNB_OUT=generated/rnb_vs_gen python3 tools/rnb/summarize_gen_battles.py [--uncontended]
python3 tools/rnb/read_battles.py generated/rnb_vs_gen [--pool]   # needs logchallenges
```
