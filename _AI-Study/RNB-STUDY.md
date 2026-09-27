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
not what costs it. What the shuffle breaks is SET-level co-authorship, not species
pairing: gen 7 teams are built from a few staples, so shuffled teams still carry 9.4 of
15 species pairs seen together on 3+ real gen 7 teams (intact 12.7, generator gyms 2.8,
non-gym 1.7). Cores are nonetheless not the lever here — a separate check found the generator already
fields the species cores real teams use wherever the dex and band allow them (gym4 all
of its Ice cores; gyms 1, 6 and 8 have none to use). What remains is **the sets
themselves**: at the same BST, the sets the generator ends with are weaker than real
teams' sets. One thing the shuffle cannot rule out: it keeps the POOL's mix (about 46%
defensive items, 23% one-attack walls), so a team may still need a typical balance of
roles, and the generator's sets have a different balance.

Composition before and after the shuffle (sets classed as attacker: 3-4 attacks or a
Choice/Life Orb item; wall/support: at most 1 attack, or a defensive item with recovery
and at most 2; in between: the rest):

| | attacker | in between | wall/support | defensive item | teams with no wall | removal | setup |
|---|--:|--:|--:|--:|--:|--:|--:|
| gen 7 intact | 51% | 17% | 32% | 47% | 27% | 79% | 44% |
| gen 7 shuffled | 51% | 17% | 32% | 47% | 5% | 58% | 45% |
| generator gyms | 52% | 33% | 15% | 26% | 44% | 11% | 100% |
| generator non-gym | 52% | 27% | 22% | 23% | 10% | 30% | 100% |
| Run & Bun bosses | 84% | 12% | 4% | 18% | 75% | 0% | 80% |

The shuffle averages real teams' distinct styles (hyper offense, balance, 4-6-wall
stall) into 1-3 walls each and still wins as often, and it costs some type synergy
(types nobody resists 1.5 -> 2.2, holes 0.17 -> 0.26; gyms 7.2 and 2.2, non-gym 3.5 and
0.5). Offensive coverage is flat everywhere (15-16 of 18 types). What separates the
generator is the KIND of set: a third are two-attack in-betweens, half as many walls
on half as many defensive items, setup on every team, almost no removal.

**The generator's sets are weaker, and now it is measured directly** (`make_injected.py`,
`injected_sets.py`). Each of the 78 gen 7 teams had 2 of its sets swapped for generator
sets of similar BST (108 of the 114 generator sets used), same pairings, 2 rounds:

| | wins |
|---|--:|
| gen 7 teams, intact | 106/156 (67.9%) |
| the same teams with 2 generator sets each | 90/156 (57.7%) |

Battle for battle: 38 lost that the intact teams won, 22 won that they lost (sign test
p = 0.052). About 5 points a set; six would land near 38%, close to the published-set
arm's 34% and the generator's own 27%. Each generator set against the real set it
replaced, same team and bosses, from the logs:

| | KOs per battle | fainted | turns in |
|---|--:|--:|--:|
| generator sets (156 slots, 318 slot-battles) | 0.53 | 59% | 4.4 |
| the real sets they replaced | 0.57 | 47% | 4.8 |
| generator attackers / real attackers | 0.51 / **0.80** | 62% / 57% | 3.1 / 4.1 |
| generator walls-support / real walls-support | 0.53 / 0.39 | **60% / 32%** | 7.2 / 5.9 |

Why, from the swapped sets:
- **The generator's walls are offensive species in wall sets.** Higher BST (534 v 502)
  but less bulk (HP+Def+SpD 287 v 311), the rest spent on offence (100 v 80) and Speed
  (76 v 55); 16 of 28 on a defensive item v 41 of 53. Real walls are Chansey on
  Eviolite, Mandibuzz, Toxapex: species built for it.
- **The generator's attackers carry setup and weaker items.** 27 of 78 carry a setup
  move (real 8 of 74) -- a slot not spent attacking, and the logs show setup is used in
  about a third of battles; 19 hold a type booster (real 0); half the megas (6 v 12).
  Their stats are close (offence 114 v 119, Speed 90 v 94).

So the fix is at the SET level, and concrete: pick bulky species for defensive slots,
put defensive items on them, cap setup (every generator team carries it; 44% of real
teams do), and do not trade Leftovers or Choice items for type boosters (gyms 1-3's
early-item rule does exactly that).

**Those fixes, applied, do not measurably help** (`generate_bosses.py` switches
SET_FIT / SETUP_CAP / ITEM_PURPOSE, default off; `gen_fixes.py`). Gyms and trainers
regenerated from the same code with the switches off and on (SETUP_CAP 1), same
pairings, 3 rounds:

| | fixes off | fixes on | battle for battle |
|---|--:|--:|---|
| gyms | 22/108 (20.4%) | 26/108 (24.1%) | on gained 16, lost 12 |
| bosses + rivals | 42/117 (35.9%) | 42/117 (35.9%) | on gained 20, lost 20 |
| pooled | 64/225 (28.4%) | 68/225 (30.2%) | 36 v 32, p = 0.72 |

They changed too little to show: 16 of 54 gym sets and 19 of 60 trainer sets, often only
an item or a move (setup users per team 1.56 -> 0.89 and 1.80 -> 1.20; type boosters
10 -> 7 and 16 -> 7; non-bulky walls 4 -> 2 and 10 -> 7). The larger finding -- the
generator's attackers KO 0.51 a battle v a real attacker's 0.80 -- is about WHICH
species and sets it picks (by BST closeness, theme and role, never by evidence that a
set is strong), which set-level tweaks do not reach. The switches stay off.
(The CLI baseline, 20.4% for the gyms, is below the committed Boss Studio gyms' 25.9%;
arms must come from the same generation. The non-gym teams went the other way, 27.5%
committed v 35.9% regenerated: all 10 teams differ, and about half the pairings drew
other bosses. The spread between two draws of the same generator is about 8 points.)

**Every run, cut by archetype, tier and team traits** (`archetypes.py`, `tiers.py`,
`team_profile.py`; 2026-09-24). All 11 battle runs pooled: 76 generator team-runs, the 78
gen 7 and 80 gen 9 real teams. A team's battles are not independent, so every test is
at TEAM level -- each team scored by wins minus what the same bosses gave up to §5's gen 9
teams ("points" below), p from permuting the trait across teams. About a dozen tests
were run; read p ~ 0.03 as soft.

*Archetype.* The generator records none, so it is read off the team: wall/support sets
per team (composition.py's classes), 0 hyper offense, 1 offense, 2-3 balance, 4+ stall.

| points v the gen 9 baseline (win %) | hyper offense | offense | balance | stall |
|---|--:|--:|--:|--:|
| real teams (gen 7 + 9) | −7 (54%) | +1 (64%) | +1 (69%) | **+14 (79%)** |
| generator teams | −30 (33%) | −37 (29%) | −38 (28%) | 1 team |

- Against these bosses (84% attackers) defence pays for real teams: gen 7 stall won 35 of
  40, +32 over the rest of gen 7 (p = 0.001; in gen 7 OU alone 26 of 30), gen 7 hyper
  offense −22 (p = 0.025). Gen 9 shows none of it (stall +1, p = 0.96).
- The generator almost never builds stall (1 of 76), and its gap is 30-40 points
  inside EVERY archetype: its balance teams win 28%, real balance 69%. Archetype does
  not explain it.
- Weather, hazard removal and team speed separate nothing, for either side.

*Species tier* (gen 7 Showdown tier, `SC.tier`, the generator's own; a mega as its
forme). The generator fields 0.8 Uber/OU species a team (real gen 7: 3.0) and 34% of its
slots are PU or below (13%). Each team fights the bosses nearest its mean BST, so the
test that matters is at the same BST, by the slot's own BST:

| slot BST | real gen 7: Uber+OU | generator: Uber+OU | real: PU and below | generator: PU and below |
|---|--:|--:|--:|--:|
| under 450 | 4% | 11% | 67% | 84% |
| 450-500 | **60%** | **0%** | 15% | 42% |
| 500-550 | 27% | 5% | 9% | 24% |
| 550+ | 73% | 48% | 1% | 9% |

At the same BST real players pick species that are strong for it (Toxapex, Ferrothorn at
450-500); the generator, choosing by BST closeness, theme and role, lands on ZU species
(45 of its 228 slots) and unevolved ones (18 NFE/LC, real 2). Its sets follow: 13 of the
114 committed sets are Little Cup sets and 15 are PU sets. Smogon's tier is the evidence
of strength the generator's picking never consults -- the "which species" of the
ablation, measured directly. Within a pool it predicts less: real teams win as often
with 0-1 Uber/OU species as with 4-6 (UU teams still field their tier's best), and
generator teams with any PU-or-below species run 14 points under those without
(p = 0.043, 38 teams).

*boss7*, the one generator team that holds up: 28-20 over the four runs it appears in
(5-7, 9-3, 7-5, 7-5; same core, one or two slots differ), −10 against the baseline where
the other generator teams are −36. It swept both Vitos 3-0, Vito 2 being among the harder
late bosses (5-3 against gen 9 teams).

| per team | boss7 | other generator | real gen 7 | real gen 9 | r with result, generator team-runs |
|---|--:|--:|--:|--:|---|
| setup users | 1.0 | 1.8 | 0.6 | 1.7 | −0.43 (p < 0.001) |
| Choice / Life Orb / Sash | 3.5 | 1.6 | 1.6 | 0.8 | +0.29 (p = 0.006) |
| type boosters / gems | 0 | 1.1 | 0.1 | 0.3 | −0.20 (p = 0.08) |
| PU-and-below species | 0.5 | 2.1 | 0.8 | 0.5* | −0.20 (p = 0.09) |
| Uber + OU species | 1.5 | 0.8 | 3.0 | 2.0* | +0.11 |
| types nobody resists | 2.0 | 5.0 | 1.5 | 1.2 | −0.16 |
| wall/support sets | 0 | 1.1 | 1.9 | 1.8 | −0.16 |
| mean Speed (Scarf ×1.5) | 100 | 81 | 85 | 81 | +0.08 |

\* gen 7 tiers miss the gen 8-9 species, 2.7 of a gen 9 team's 6.

Among generator teams, setup and offensive items track the result, but gen 9 rules both
out as causes: real gen 9 teams carry as much setup (1.7) and the fewest offensive items
(0.8) and still win 65%. Setup marks the generator's weak way of building (as SETUP_CAP
changing nothing already said). What boss7 shares with real teams is the rest: strong
species, no low-tier ones, no type boosters, real-team type coverage. Its lack of walls
and its item load are its own style.

*Teams with no wall/support set* make up for it with speed and momentum -- when they are
real. Spread of the team's mean Speed (Scarf ×1.5):

| | min | p25 | median | p75 | max | fastest mon, min | pivot users | Scarf users |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| generator, no walls (24) | **58** | 69 | 85 | 98 | 104 | **70** | 0.58 | 0.29 |
| generator, 1+ walls (52) | 49 | 68 | 78 | 98 | 108 | 70 | 0.69 | 0.31 |
| real gen 7, no walls (21) | **75** | 93 | 100 | 102 | 111 | **120** | 2.05 | 0.95 |
| real gen 7, 1+ walls (57) | 49 | 65 | 80 | 91 | 113 | 61 | 1.16 | 0.35 |
| real gen 9, no walls (23) | 58 | 81 | 94 | 107 | 116 | **110** | 1.52 | 0.52 |
| real gen 9, 1+ walls (57) | 44 | 57 | 75 | 88 | 119 | 67 | 0.91 | 0.32 |

Every real gen 7 no-wall team averages Speed 75+ and has a mon at 120+; they carry nearly
twice the pivots of teams with walls, and gen 7's three times the Scarves. The
generator's no-wall teams are no faster than its others and carry no extra pivots or
Scarves: they are wall-less by accident (gym1: Joltik, Skorupi, Anorith, Kricketune,
Vespiquen, Heracross; nothing over 85). Inside every pool the faster half of the no-wall
teams does better -- generator −37 v −24, gen 7 −24 v −3, gen 9 −19 v +2 (small groups,
untested). The slow extremes are partly by design: the slow gen 9 no-wall teams that won
are Trick Room (Hatterene, Torkoal), and gym3 (Politoed, Gorebyss, Mantine), the least bad
slow generator team, may be rain; base Speed misses both.

So two concrete rules to test, in order: pick species by tier RELATIVE to BST (prefer
species ranked above what their BST suggests, at the build, not as KEEP_MIN_BAND's
after-the-fact filter), and check a wall-less team as hyper offense -- a 120+ top end,
few slow mons unless it runs Trick Room or weather, pivots or a Scarf. boss7 passes the
second already (Scarf Galvantula 162, Froslass and Latias 110).

**Monotype gyms: what their type pool can field** (2026-09-24). At each gym's level, the
legal on-type pool is the limit for two themes only: Bug at 20 (50 of 56 legal species
PU or below, nothing strong in its band) and Ice (no OU at all, its three UU already on
the team). The deep themes skip strong on-type bodies inside their band -- Steel fields
Steelix with Ferrothorn, Skarmory and Scizor legal; Normal fields Regigigas and Slaking
with Chansey and Porygon-Z legal, though those two sit far under a 597 target, and the
eBST curve, not the theme, keeps them out. So the theme rules changed in
`generate_bosses.py`, and the change is being tested before it ships:

- `ON_THEME_MIN` 6 -> 5, and `THEME_MIN` caps Bug and Ice at 4 (the smaller wins, so a
  preset still saying 6 loosens only those two).
- `OFF_THEME_COVER` (on): an off-theme slot must resist a theme weakness nothing on the
  team resists yet, higher tier first; co-occurrence (MIN_CORR) no longer qualifies a
  pick alone. On the nine: Starmie onto Ice (Fighting/Steel/Fire), Dragonite onto Steel
  (Fighting/Ground/Fire), Magnezone onto Dark.
- `TIER_BAND` (off, 40 in the test): inside 40 eBST of the ideal, tier before distance.

`gen_fixes.py off` rebuilds the fixes-off gyms byte for byte, so that arm is the old
rules exactly. **Played on the Linux machine (Steam Deck), all three arms there, at
100 ms search** (Foul Play's own default; every earlier run used 500 ms, so these
numbers compare with each other and with nothing else in this study): 4 workers, 3
rounds, arms interleaved round by round, 324 battles, 0 errors. Bots searched a median
21k iterations a decision (123k at 500 ms, 3 workers, measured on the same machine).

| arm (`generated/`) | wins | boss-adjusted | v baseline, 95% CI (resampling gyms) |
|---|--:|--:|---|
| old rules (`rnb_vs_gen_deckoff`) | 21/108 (19.4%) | −2.8 | |
| theme rules (`rnb_vs_gen_theme`) | 32/108 (29.6%) | +5.7 | **+8.5** [−0.8, +17.3] |
| theme + TIER_BAND 40 (`rnb_vs_gen_tier`) | 22/108 (20.4%) | −2.9 | −0.0 [−13.6, +14.6] |

Boss-adjusted: each battle against the pooled win rate of all three arms on that boss,
since new teams drew partly different bosses. On the 93 battles the arms share
(`compare_runs.py`), theme won 28 to the baseline's 19 (19 gained, 10 lost, p = 0.14).

- **The theme rules help, probably.** +8.5 points, 97% of resamples above zero, the
  interval just touching it. The gain is the off-theme slot doing its job, one swap at a
  time: gym 8 Lopunny -> Moltres (0-12 -> 5-7), gym 2 Klefki -> Arcanine (0-12 -> 3-9),
  gym 5 Honchkrow -> Charizard (2-10 -> 4-8), gym 1 Joltik/Kricketune -> Slowpoke/Minun
  (0-12 -> 2-10). Gyms 6, 7 and 9 did not move.
- **TIER_BAND adds nothing, and undoes the theme gain** (−8.6 against theme alone,
  interval [−19.2, +4.2]). Ranking tier before distance inside 40 eBST lands on higher-
  tier species (Blaziken, Celesteela, Landorus, Zygarde) whose sets do no better, and
  moves gyms 8 and 9 onto worse draws. It stays off.
- Weak bots make single battles noisier, which blurs small effects -- a reason to read
  the theme result as "likely helps" rather than a measured size. The theme rules stay
  on; ship them by setting the Studio preset's ON_THEME_MIN to 5 and regenerating.

**The rest of the proposals, all on at once, make things worse** (2026-09-25, same
machine and settings, 348 battles, 0 errors). Four new switches in `generate_bosses.py`,
all off by default: SET_TIER_MATCH (a species prefers a set from its own tier; Little
Cup and monotype sets last), USAGE_BAND 30 (inside 30 eBST, prefer the higher Smogon
viability ceiling), SHAPE_CHECK (rebuild on fresh seeds, up to 8 tries, until the wall
count fits the archetype and a wall-less team has a fast top end, few slow mons and a
pivot or Scarf) and GYM_MODES (Water gets rain, Ground sand). The swap of type boosters
for offensive items was dropped: before the unlock the pool holds no offensive item.
They did what they say -- gym sets from their own tier 19 -> 34 of 54, Little Cup and
monotype sets 27 -> 9 across gyms and trainers, every gym passing the shape check (5
rebuilt), rain on gym 3, sand on gym 6 -- and lost:

| on top of the theme rules | theme rules | all four on | difference, 95% CI |
|---|--:|--:|---|
| gyms (`rnb_vs_gen_all`) | 32/108 | 23/108 | −8.3 [−15.9, +0.1] |
| trainers (`rnb_vs_gen_trainers_all`, baseline `_trainers_theme`) | 44/120 | 35/120 | −3.3 [−16.4, +9.3] |

Shared pairings: gyms 16 lost v 7 gained (p = 0.09), trainers 17 v 10 (p = 0.25). The
gyms fall back to the old rules' level; the losses sit on gym 6 (sand, 5-7 -> 2-10), gym
7 (rebuilt, 5-7 -> 2-10) and gym 1. One arm cannot say which switch cost it; all four
stay off. What this batch adds to the picture: making the generator's teams LOOK like
real teams -- own-tier sets, archetype-shaped, weather-built -- does not make them play
like them.

**Design choices, then walls** (2026-09-25, same machine and settings). Chosen as
defaults without a test: sets from the standard ladders only (SET_FORMATS: ubers, ou,
uu, ru, nu, AG, National Dex, National Dex AG; out go pu, zu, lc and monotype, which
leaves 9 of 54 gym mons on learnset moves against 2), no early item cap
(EARLY_ITEM_CAP 0; stones stay off before the unlock), SHAPE_CHECK, SET_FIT and
SETUP_CAP 1 -- `gen_fixes.py choices`. Their composition (`composition.py`, which now
takes extra pools as LABEL=EXPERIMENT:SIDE) fixed boosters (1.4 -> 0.1 a gym team),
setup (2.3 -> 0.9) and gym typing (types nobody resists 7.2 -> 3.8) but went all-out
offence: 78% attacker sets, 0.6 walls a gym team, hazard removal on 22%.

So a wall ROLE: a wall/support set on a species built for it (HP+Def+SpD >= 55% of BST).
WALL_MIN 2 chases two per fight and lifts SHAPE_CHECK's wall floor; REMOVAL_MIN 1 chases
a Rapid Spin or Defog user; both go first in the floor order. They could not bite at
first: walls are low-BST species (Chansey 450, Skarmory 465, Toxapex 495) and the band
shut them out of every late fight -- the plain reason the generator had none. WALL_SLACK
lets a bulky body in 100 under the band floor. Result (`gen_fixes.py defense`): walls
26% of gym sets (real 32%), defensive items 48% (47%), no wall-less team, removal on
every gym -- at a price, gyms 36 eBST under target on average against 14.

| gyms, 108 battles each | wins | v theme rules, 95% CI |
|---|--:|---|
| theme rules (`rnb_vs_gen_theme`) | 32 (29.6%) | |
| + the choices (`rnb_vs_gen_choices`) | 22 (20.4%) | −8.6 [−17.7, +0.7] |
| + the choices + walls (`rnb_vs_gen_defense`) | **41 (38.0%)** | **+12.6** [−1.8, +27.7] |

Walls against the choices alone, on the 66 shared battles: 12 gained, 3 lost (p = 0.035);
gym 7 went 11-1, gym 2 0-12 -> 5-7. The choices cost the theme gain; the walls bought it
back and more, on teams 36 eBST lighter -- the stall finding again, from the other side.
Trainers did not move (theme 44/120, choices 38, walls 43): with three to five of their
own mons kept, only 4 of 18 reach two walls. WALL_MIN 2 and REMOVAL_MIN 1 are now on.

**Search depth, on the real teams** (`rnb_vs_gen7_25ms`, 2026-09-25): the same 80 gen 7
pairings, 2 rounds, at 25 ms search on the Linux machine against the 500 ms Windows run.
Real teams win 93/156 (59.6%) against 106/156 (67.9%); on the 158 shared battles 35 lost
v 22 gained (p = 0.11). Shallower search pulls the stronger side toward a coin flip, so
the bots at 25 ms blur team strength -- about 8 points here, not significant. A battle
takes ~20 s (160 in ~15 min at 4 workers). 100 ms, used for the rule tests above, sits
between: ~25k iterations a search against ~88-123k at 500 ms.

**Every slot, every arm** (`deck_slots.py`, 2026-09-26). Showdown's logs for the 100 ms
arms, each log assigned to its arm by the attempt's start time (the bot username carries
it; `read_battles.py`'s tag matching over-reads once arms share pairing numbers), so each
arm reads exactly its battle count. Per set kind (`composition.kind`), per battle:

| gyms, 100 ms | won | attackers: KO / fainted / turns in | walls: KO / fainted / turns in | wall slots |
|---|--:|---|---|--:|
| old rules | 19.4% | 0.46 / 93% / 3.4 | 0.22 / 86% / 6.6 | 6 of 54 |
| theme rules | 29.6% | 0.57 / 85% / 3.8 | 0.27 / 81% / 6.7 | 8 |
| theme + tier | 20.4% | 0.50 / 91% / 3.9 | 0.23 / 94% / 7.9 | 9 |
| all four rules | 21.3% | 0.44 / 93% / 3.3 | 0.24 / 91% / 5.1 | 8 |
| the choices | 20.4% | 0.50 / 91% / 3.9 | 0.27 / 93% / 5.2 | 5 |
| the choices + walls | **38.0%** | **0.59 / 73% / 3.6** | **0.38 / 68% / 6.5** | 14 |
| real gen 7, 25 ms | 59.6% | 0.82 / 71% / 3.8 | 0.41 / 55% / 6.7 | 152 of 468 |

Trainers (theme 36.7%, all 29.2%, choices 31.7%, walls 35.8%): attackers 0.51-0.61 KO
and 79-85% fainted in every arm; the walls arm's trainer walls are the weakest (0.25 KO,
80% fainted) -- what a trainer can fit within its band are poor walls.

- Generated attackers faint in 85-93% of their battles in every arm but one. Real
  attackers faint 71%.
- **The walls helped the attackers**, not only the walls: against the choices arm (the
  same settings minus walls) attackers went 0.50 KO / 91% fainted -> 0.59 / 73%. Walls
  absorb hits and the attackers get turns. The walls themselves (0.38, 68%) approach
  real walls (0.41, 55%).
- Attackers remain the gap: 0.59 v 0.82 KO a battle; damage dealt 71% of an opposing
  mon's max HP a battle v 92%, 19.6% a turn on the field v 24.1% at about the same time
  in (3.6 v 3.8 turns).
- Caveat on the walls arm: gym 7's Xerneas (Geomancy, Power Herb) scored 5.08 KO a battle
  alone and gym 7 went 11-1 against 5-7 in the theme arm; without gym 7 the arms are 30/96
  v 27/96. Two low-BST walls raise the deficit for the slots after them, so the picker
  reaches for an Uber -- most of the +9 wins is one mon.
- The slot list said why the attackers are weak. A third of the "attacker" slots were
  not attackers: learnset filler with three weak attacks (Wigglytuff Round / Echoed Voice /
  Snore / Rest, 0 KOs; Pyukumuku Facade / Bide / Fling / Grass Knot, 0) or Rapid Spin
  utility sets (three Claydols, Donphan, Forretress, 0-0.25). The real attackers carried
  filler where a published move failed the level gate: Giga Impact on Weavile, Bisharp,
  Zoroark, Mamoswine, Gallade and Hippowdon; Facade, Round, Swift; Starmie at gym 2 on
  Rapid Spin / Recover / Bubble Beam / Swift. And low-tier species in attacking slots
  (Vespiquen, Anorith, Frogadier, Poliwrath, Pineco). The attackers that were real
  attackers on real sets did fine: Weavile 1.17, Malamar 1.25, Starmie 1.2-1.3, Arceus
  0.92 -- at or above the real average.

**What a real gen 7 attacker is** (`attacker_profile.py`, 237 attacker slots of 468).
Items: Choice 33% (Scarf 39 slots, Band/Specs 39), Assault Vest 12%, Life Orb / Expert
Belt 14%, mega 11%, Leftovers 7%. Moves: four attacks 55%, U-turn or Volt Switch 34%,
setup 8%, priority 14%. Stats: BST 548, best attacking stat 119, Speed 100 with a Scarf
counted x1.5, 48% at 100+. Tier: Uber/OU 49%, PU and below 14%. Species: Landorus-Therian
on 22 of the 78 teams, Tapu Koko 11, Charizard, Greninja and Magearna 7 each; the top 12
species fill 39% of the attacker slots -- real teams repeat the proven few, the opposite
of what REPEAT_BAND asks for. How each group did at 25 ms: Band/Specs 1.06 KO a battle
(114% dealt), mega 0.94, Scarf 0.88, Life Orb 0.75 (2.6 turns in), Leftovers 0.53, Sash
0.45; setup attackers 1.19 at 53% fainted, but only 18 slots; Speed 100+ v under (0.86 v
0.79) and STAB count (0.83 v 0.82) split nothing; the best-attack-under-100 group scores
the MOST, 1.12 at 5.0 turns and 53% fainted -- the Assault Vest Tangrowths and Amoonguss,
four attacks, built to stay in. The generator's attackers at 100 ms (walls arm) split
exactly where the real ones do not: Speed 100+ 0.82 v under 100 0.51; best attack 120+
0.97 v under 100 0.38; PU and below 0.28 (39% dealt). A real weak-stat attacker is a
bulky pivot that lasts five turns; the generator's is a frail low-tier species that deals
39% of a health bar and faints. The tier rows for real teams are confounded by boss draw
(low-tier real attackers sit on low-BST teams that face the early bosses).

**Core strength: measured, not inferred** (`core_strength.py`, 2026-09-27). The dev's own
(kept) Pokemon are on the team in every arm, so each has 48-72 slot-battles on its own
fight across the 100 ms runs. Kept v generated, all arms pooled: gym kept attackers 0.46
KO / 59% dealt / 88% fainted / 3.2 turns in against generated 0.55 / 75% / 88% / 4.0;
trainer kept attackers 0.58 / 63% against 0.51 / 77%; trainer kept walls 0.42 KO against
generated 0.31. The core as a group is a little weaker than the picks; the problem is
its tail. Per species -- weakest: Wigglytuff (gym 2) 0.07 KO / 11% dealt, Finneon
(Teresa) 0.10 / 8%, Pyukumuku (gym 3) 0.12 / 20% at 3.1 turns in and 86% fainted (it
fails as a wall too), Dwebble 0.15, Camerupt (gym 6's mega ace) 0.15 / 20%, Karrablast
0.17, Steelix (gym 9) 0.17, Anorith 0.18 at 99% fainted, Braixen 0.19, Reuniclus 0.19,
Hippowdon (UU) 0.19 / 33%, then Leavanny, Spiritomb, Lumineon twice, Vespiquen 0.22.
Strongest: Lucario 1.23, Weavile 1.04, Gengar 0.98, Gardevoir 0.94, Houndoom 0.92,
Gallade 0.88 at 57% fainted, Electrode 0.88, Mamoswine 0.83-0.85 (real attackers: 0.82).
Tier misjudges it: Electrode (ZU) 0.88 and Mega Houndoom (PUBL) 0.92 against Hippowdon
(UU) 0.19 and Reuniclus (RUBL) 0.19; of the gyms' mega aces Gallade and Pidgeot pull their
weight and Camerupt does not, so a tier-based drop (KEEP_MIN_BAND) would cut the wrong
mons. Keep-or-replace should be decided on measured contribution -- a KEEP_MEASURED test,
being built -- after the set is fixed first (KEPT_ANY_FORMAT: Pyukumuku spent these arms
on learnset filler, Hippowdon on an attacking set), and with walls judged on turns in and
faint rate, never KOs. Proposed rule: an attacker is replaceable under ~35% dealt and at
most 0.2 KO a battle (half what the generated attackers on the same teams deal); a wall
under 4 turns in and over 85% fainted. About 14 flagged today, 5 of them rival core
families (Finneon, Lumineon twice, Braixen, Reuniclus), which every drop test protects --
a design call, not a strength one.

**The limiters, released** (2026-09-26/27, each a switch in `generate_bosses.py`, all on;
measured on builds, NOT yet in battle). In order:
- `EARLY_MOVES` 1: a published set keeps a move the mon has not reached at its level (the
  species gate stays); `FILLER_AVOID`: no recharge or gimmick move as filler (Giga Impact,
  Hyper Beam, Last Resort, Facade, Snore, Bide, Fling ...).
- `SET_FORMATS` back to every format, then `SET_FORMATS_OFF` = battlespotsingles +
  monotype + nationaldexmonotype + pu + zu + lc: the standard ladders, AG and National Dex.
- `PICK_FLOOR` 0: no band floor on generated picks; deficit() still steers the mean.
- `PICK_NO_LOW` 1: no PU-and-below species as a generated pick; the theme minimum outranks
  it (Bug at level 20 has three species above PU, so gym 1 relaxes to reach 4 of 6).
- `KEEP_NEED_SET` 1: a dev mon with no published set at its level is dropped (Brionne at
  gym 3). `KEPT_ANY_FORMAT` 1: a dev mon may take a set from any format, so the rivals'
  Glaceon, Pumpkaboo, Gourgeist, Finneon and Lumineon keep real sets.
- `REPEAT_BAND` 1 -> 3.
- The attacker rules, from the profile above: `ATTACKER_SHAPE` (inside the coverage band,
  a body with a best attacking stat under 105 and HP+Def+SpD under 265 ranks after the
  rest), `ATTACKER_ITEM` (an attacking set on a Choice item, Life Orb, Expert Belt,
  Assault Vest or mega stone ranks above one on Leftovers or a Sash), `PIVOT_MIN` 1.

What the rosters did, walls arm -> current: learnset-written slots gyms 7 -> 2 and
trainers 13 -> 0 (9 again while the PU/LC sets were out, 0 once KEPT_ANY_FORMAT came in);
recharge/gimmick filler moves 18 -> 1 (gyms) and 21 -> 0 (trainers); gym mean eBST v
target -36 -> -12 before the attacker rules, the current build spreading gym 1 +47 over
and gyms 4 and 6 about 45-51 under; PU-and-below species gyms 24 -> 5 and trainers 43 ->
29, the remainder kept dev mons. Attackers now: Choice 27%, Life Orb / Belt 35%,
Leftovers 15%, four attacks 54%, pivot 16%, best attacking stat 107, Speed 100+ 36%,
Uber/OU 12%, PU and below 27% (real: 33 / 14 / 7 / 55 / 34 / 119 / 48 / 49 / 14). A
pivot user on 21 of 27 fights (real teams 72%). The most-used generated species are on 5
fights instead of 6 (Starmie, Excadrill, Dhelmise, the Slowpoke line): with the pool above
PU thin, the variety penalty has little to choose among. Xerneas is back, on gym 9 with
Genesect beside it.

**The 10 ms baseline** (2026-09-27, `generated/rnb_vs_*_10ms/`): real gen 7 (2 rounds),
the walls arm and the new roster, gyms and trainers, all at 10 ms search on the Deck --
~3,000 iterations a search, against ~7,000 at 25 ms and ~25,000 at 100 ms; a battle still
takes ~26 s, since the fixed overhead dominates, so the shallow search buys no time. It is
the reference for what follows. 616 battles, the only errors the unpilotable two-Arceus
pairing (three hangs, ended by the new idle watchdog in run_battles.py: two live bots
with no CPU for 120 s is a dead battle).

| at 10 ms | wins | v the walls arm, 95% CI | shared battles |
|---|--:|---|---|
| real gen 7 teams | 100/156 (64.1%) | | |
| walls arm, gyms | 34/108 (31.5%) | | |
| **new roster, gyms** | **38/108 (35.2%)** | +8.3 [−9.3, +27.4] | 27 gained v 14 lost, p = 0.06 |
| walls arm, trainers | 34/120 (28.3%) | | |
| **new roster, trainers** | **42/120 (35.0%)** | +9.3 [−3.3, +22.2] | 27 gained v 13 lost, **p = 0.039** |

The real teams land where they did at 500 ms (64.1% v 67.9%), so 10 ms flattens less
than 25 ms did (59.6%). The walls arm itself reads lower here than at 100 ms (31.5% v
38.0%): its gym 7 Xerneas carried less with the shallow search. The new roster gains
on both sides -- the first change since the theme rules to move the TRAINERS, whose kept
originals limit everything else -- but the gym gain rides on gym 1 (0-12 -> 9-3, the one
47 eBST over its target) and gym 4 (5-7 -> 8-4), against gym 5 (8-4 -> 1-11, its Slowbro
wall gone) and gym 7 (5-7 -> 2-10, Xerneas moved to gym 9). Pooled, gyms and trainers,
80/228 (35.1%) against 68/228 (29.8%).

The measured core table from these four arms (`core_strength.py --write`, 24 battles a
kept mon) flags five: Karrablast, Wigglytuff, Aggron (gym 9's mega ace: 0.12 KO, 11%
dealt, 2.2 turns), and Teresa's Duosion and Finneon, which are protected rival cores. The
100 ms table (48-72 battles a mon) flagged seven, Wigglytuff and Karrablast on both;
Pyukumuku, on its real wall set now, passes.

**KEEP_MEASURED on, pooled table** (2026-09-27, `rnb_vs_gen_measured_10ms`,
`rnb_vs_gen_trainers_measured_10ms`). The table pooled over the 100 ms and 10 ms arms
(72-96 battles a kept mon) drops five: Wigglytuff (0.08 KO, 11% dealt), Pyukumuku (0.16,
22% -- mostly on the filler sets it ran in the 100 ms arms; the 10 ms arms alone pass
it), Mega Steelix (0.20, 26%), Karrablast (2.6 turns, 92% fainted, 0.12 KO) and Dwebble
(0.18, 22%). Aggron, Anorith, Camerupt and Vespiquen pass the pooled table. Gym 9's mega
moves to Mewtwo X and Xerneas leaves; Camus gets Vivillon, Scarf Rotom and Miltank;
Alba's map164 fight takes Eviolite Chansey because Camus took Miltank. An explicit card
tick now outranks every competence knob, as an untick already outranked protection.

| at 10 ms | walls arm | new roster | + KEEP_MEASURED |
|---|--:|--:|--:|
| gyms | 34/108 (31.5%) | 38/108 (35.2%) | **41/108 (38.0%)**, +10.5 v walls [−7.6, +29.6] |
| trainers | 34/120 (28.3%) | 42/120 (35.0%) | **59/120 (49.2%)**, +23.6 v walls [+10.0, +37.5] |

Against the new roster on shared battles: gyms 19 gained v 11 lost (p = 0.20), trainers
35 v 17 (p = 0.018). But only ONE battled trainer team changed (Camus, 2-10 -> 7-5); the
other nine, identical rosters against identical bosses, went from 40/108 to 52/108
between the two runs. That is the 10 ms noise floor showing itself: about 11 points on
108 battles from nothing at all, which is the size of every generator-v-generator
difference measured at this depth so far, the new roster's +8/+9 included. An identical
replay of the new-roster arms (`rnb_vs_gen_atk_10ms_b`, `_trainers_atk_10ms_b`) measured
it directly: same teams, same pairings, gyms 38 -> 47 of 108, trainers 42 -> 50 of 120
(24 flips one way v 15 the other, and 26 v 18). **Two runs of one arm differ by 7-8
points at 10 ms**, so every generator-v-generator difference of that size above -- the
new roster's +8/+9 over the walls arm, KEEP_MEASURED's +3 on the gyms -- is not
established, and its +14 on the trainers is about half noise and half Camus. What the
10 ms baseline does establish: pooling the two identical runs, the new roster sits at
gyms 85/216 (39.4%) and trainers 92/240 (38.3%), against real gen 7 teams at 64.1%;
the gap is ~25 points and shrinking slowly. A difference has to reach ~15 points on 108
battles, or be replayed, before it means anything at this depth.

**What the weak rosters showed, and the fixes** (2026-09-27, `rnb_vs_gen_fix_10ms`,
`_trainers_fix_10ms`). Per-slot reading of the 10 ms losers (gym 9 1-11, gyms 3 and 7
2-10, Jerebuzo 4-32) against how real gen 7 teams did on the same bosses: gym 3's draw is
EASY for real teams (81%; Norman 88% v the generator's 15%), gym 9's and 7's about
average (59%, 53%), only Jerebuzo's hard (44%). So "hard boss" mostly meant hard for the
generator -- Sidney and Norman beat 85-88% of generated teams and 12% of real ones. Four
causes were visible in the slots: (1) support sets written for a plan the fight is not
running -- Uxie's Memento (0.06 KO, 4% dealt), Cresselia's Trick Room + Lunar Dance
(0.19, twice), Vaporeon's Baton Pass, all slots that dealt nothing and removed themselves;
(2) the 70-power move cap at gyms 2-3, which stripped Play Rough, Hydro Pump and Waterfall
and filled with Covet, Rollout, Swift and Bubble Beam -- Choice Band Azumarill with Aqua
Jet / Bulldoze / Covet / Rollout; (3) a set arriving bare when its stone went to a
teammate (gym 9's Aggron, 0.08 KO, 5% dealt); (4) frail Life Orb attackers lasting two
turns, where the real-attacker profile had Band/Specs best. The fixes, all switches:
NO_PLAN_SETS (screens stay), BP_CAP_UNTIL 3 -> 1, ITEM_FALLBACK (Leftovers or Life Orb,
never a Choice item), ATTACKER_ITEM 2 (Band/Specs > Scarf/mega/Vest > Life Orb, and a
Choice item counts only on a set that is all attacks or carries Trick, since the lock
wastes any other move). 23 of 27 teams changed.

| at 10 ms | measured roster | + the four fixes | difference |
|---|--:|--:|---|
| gyms | 41/108 (38.0%) | **55/108 (50.9%)** | +13.3 [−4.3, +31.6]; shared battles 25 gained v 10 lost, **p = 0.017** |
| trainers | 59/120 (49.2%) | 58/120 (48.3%) | −0.8; 22 v 23 |

The first generator result over 50% at any depth, and the first gym difference to clear
the 7-8 point replay floor with a significant sign test. Gym 2 went 4-8 -> 11-1 and gym 4
8-4 -> 11-1 (the cap lifted), gym 9 1-11 -> 5-7 (Aggron on Leftovers, Genesect on a Band,
Ho-Oh and Mega Metagross in for Jirachi and Mewtwo), gym 3 2-10 -> 4-8, gym 6 5-7 -> 7-5;
gym 8 fell 6-6 -> 3-9 and gym 7 stayed 2-10. Trainers did not move: the cap never applied
to them and they carried one plan set. Real gen 7 teams at this depth: 64.1%.

**The item has to agree with the moves** (2026-09-27, `rnb_vs_gen_fix2_10ms`,
`_trainers_fix2_10ms`). Left in the fixed roster: an Assault Vest Ho-Oh with Recover (the
Vest blocks it), a Scarf Honchkrow with Sucker Punch and the two-turn Sky Attack, Solar
Beam on a Cresselia with no sun, Round on a Specs Rotom. SET_COHERENCE replaces a status
move on a Vest set with an attack the species has (or the Vest with Leftovers), turns a
Choice set with a status move and no Trick into Life Orb, and ranks a Scarf set with a
priority move last; FILLER_AVOID gains the 40-60 power fillers and the two-turn attacks;
SETUP_CAP goes 1 -> 2 because a kept Swords Dance user was blocking every other setup set
(Xerneas still did not get Geomancy at gym 7: Gallade and a Calm Mind Cresselia fill
both). 20 of 27 teams changed a slot. Played: gyms 52/108 (48.1%) v 55/108, trainers
66/120 (55.0%) v 58/120 -- −2.8 and +7.3, both inside the replay floor. A cleanup with no
measured cost or gain; the roster is what the previous run established, about half the
battles won against these bosses, real gen 7 teams at 64%.

Where the generator stands at 10 ms, in order of change:

| roster | gyms | trainers |
|---|--:|--:|
| walls arm (2026-09-25 rules) | 31.5% | 28.3% |
| limiters released + attacker rules (two identical runs) | 35.2% / 43.5% | 35.0% / 41.7% |
| + KEEP_MEASURED | 38.0% | 49.2% |
| + the four weak-roster fixes | **50.9%** | 48.3% |
| + set coherence | 48.1% | **55.0%** |
| real gen 7 teams | 64.1% | |

**Real monotype teams on the gyms' own draws** (2026-09-27, `make_mono_battles.py`,
`generated/rnb_vs_mono_10ms` gen 9, `_mono8_10ms` gen 8, `_mono7_10ms` gen 7). The gyms
are monotype and every real team played so far is not, so the 64% yardstick was never
theirs. Smogon monotype teams of each gym's type, nearest in BST, against the gym's own
four bosses, 2 a boss, 2 rounds, 10 ms: gen 9 1,414 legal teams (72 pairings), gen 8 174
(65), gen 7 only 11 once Z-crystals and legality are applied (11, five types).

| type | generated gym | gen 9 mono | gen 8 mono | gen 7 mono |
|---|--:|--:|--:|--:|
| Bug | 58% | **88%** | 86% | |
| Fairy | **100%** | 94% | 69% | |
| Water | 67% | 69% | 71% | 8-0 |
| Ice | 58% | 75% | 62% | 0-2 |
| Dark | **17%** | **81%** | 90% | |
| Ground | 42% | 43% | 44% | 2-4 |
| Psychic | 25% | 25% | 6% | |
| Normal | 25% | 12% | 40% | 0-2 |
| Steel | 42% | 31% | 44% | 2-2 |
| all | **48%** | **58%** | **55%** | 55% |

Against real teams of their own type the gyms sit 7-10 points back, not the 16 the
balanced gen 7 teams showed: the monotype constraint itself costs real teams too. Gym 7's
draw is what beats Psychic -- real Psychic monotypes go 0-4 v Matt's Kartana in both gens
and 0-4 / 1-3 v Sidney -- and Ground, Steel and Normal gyms match their real counterparts.
The under-built gyms are Dark (17% v 81-90%) and Bug (58% v 86-88%), Ice less so (58% v
62-75%); Fairy and Water are at parity or ahead. The real monotype teams carry a hazard
setter and a remover, one or two setup sweepers, a pivot, Choice or Vest items, and their
type's off-type answers (the Psychic team's Knock Off, Focus Blast, Draco Meteor and
Earthquake); the gen 8 Psychic team is a four-member Trick Room plan, the shape
NO_PLAN_SETS strips from the generator because there the setter has no team behind it.

A first version drew replacements instead of swapping and favoured some sets: the
sets it left out had KO'd 0.79 a battle in the intact run against 0.64 for the ones it
used, which would have made collages look weak for the wrong reason.

**What real monotype teams have in common, and per type** (2026-09-27, 1,588 gen 8+9
Smogon monotype team-types from the same dump, against the nine fix2 gyms; a team of two
shared types counts for both). The universal habits, mean per team or share of teams:

| | real mono | gyms (fix2) |
|---|--:|--:|
| offensive setup users | 1.47 | 1.22 |
| priority users | 0.81 | 0.67 |
| hazard setter on the team | 83% | 67% |
| hazard removal on the team | 56% | 89% |
| pivots | 1.01 | 0.89 |
| walls | 1.44 | 1.44 |
| dual-typed members | 5.36 | 4.33 |
| Choice items | 1.46 | 1.56 |
| Leftovers | 0.96 | 1.89 |
| Assault Vest | 0.22 | 0.78 |

Fighting is the universal off-type coverage (a top-three attacking type on every theme but
Normal's own), Dark and Ice the next. The types have shapes: Bug, Fairy, Ice and Dark are
offensive (2.5 / 1.9 / 1.7 / 1.8 setup users, 0.6-1.2 walls, 1.2-1.7 priority users) and
Ground, Water and Normal bulky (0.6-1.2 setup, 1.8-2.6 walls, 0.1-0.6 priority); Psychic
sets up (1.7) and runs almost no priority (0.2). The fix2 gyms had the same flat shape on
every type -- WALL_MIN 2, no priority floor -- so the offensive gyms carried too many walls
(Bug 2.0 against 0.6) and the bulky ones too few (Ground 1.0 against 2.1).

The cores are concentrated: the top species of a type sit on 60-85% of its teams (Volcarona +
Scizor on 73% of Bug, Ting-Lu on 71% of Dark, Heatran on 76% of Steel, Klefki + Azumarill
on Fairy), the gyms carry almost none of them, and about half of the core species are gen
8-9 and outside Realidea's dex -- so co-occurrence cannot be copied, only the FUNCTION of
the partners. iStarlyTV's singles teambuilding guide (`pgz_aHzdWtw`) defines a core that
way: an anchor, an enabler that removes the anchor's specific weakness (Focus Sash
Hydreigon with Stealth Rock + Taunt so a rocks-weak Mega Charizard X can work), then a
patch for the one threat the pair both lose to (Corviknight for the Garchomp that beats
both), and afterwards the explicit question "how does this team lose?" answered with a
slot. Partners are chosen because they let the anchor use its strengths, resist what it is
weak to, or answer a named threat -- never because they appear together a lot ("common
teammates" mostly echo the usage leaders, he says, which is what §4 found too). His
"two independent 3-mon cores" relies on Champions' bring-6-pick-3; a 6v6 gym fight wants
one core and glue.

**Core first, and per-type floors** (2026-09-27, `rnb_vs_gen_core_10ms`, both switches in
`generate_bosses.py`, pinned off for every earlier arm in `gen_fixes.py`; the trainers
have no theme and are byte-identical to fix2, so only the gyms were replayed, on fix2's
exact boss draw via `make_gen_battles.py --pairs-from`):
- `CORE_FIRST` builds a themed fight's first free on-theme slots by function. The anchor
  is the dev's strongest kept attacker (with nothing kept, the strongest attacker-shaped
  on-theme body the curve allows). The enabler is an on-theme body that RESISTS a type the
  anchor is weak to, asked in order for hazard removal (a Rock-weak anchor), hazards (a
  setup anchor), a pivot, then any unmet floor. The patch is an on-theme body that resists
  a type both lose to AND can learn a move that hits it back. Each step gates the pool by
  the job and lets the eBST curve choose among the bodies that qualify, the way the
  off-theme slot already gates by uncovered weaknesses; a step nothing on-theme can do is
  noted and left to that slot. The theme minimum, the floors and the glue fill as before.
- `THEME_FLOORS` gives a themed fight its type's measured shape (`THEME_SHAPE`): the type's
  own wall count in place of WALL_MIN's flat 2 (Bug/Fairy/Ice/Psychic 1, the rest 2), a
  hazard setter, and the setup and priority users a typical team of the type runs (setup
  2 on the offensive types and Psychic, 1 on Normal and Steel; priority 1 on Bug, Fairy,
  Ice and Dark), inside SETUP_CAP. SHAPE_CHECK's wall floor follows it.
- `ITEM_FALLBACK 2` judges a bare set as a wall as if it already held Leftovers: the first
  build gave a Toxic / Rest / two-attack Aegislash a Life Orb.

What changed on the roster: seven of nine gyms. Gym 2's Whimsicott is now the enabler
(shields Azumarill from Electric/Grass, pivots) and Klefki the patch (resists and hits the
Poison that beats both). Gym 7 loses Bronzong and Xerneas for a Stealth Rock Metagross
(shields Gallade from Fairy/Flying), Meloetta as the Ghost patch, and a Specs Volcanion
off-theme. Gym 5 trades Mega Sharpedo for a Choice Scarf U-turn Greninja (Fire shield for
Bisharp; Greninja is a top-six species on real Dark monotype). Gym 8 trades Porygon-Z for
a Specs Heliolisk (Electric shield for Pidgeot) and puts Stealth Rock on Arceus. Gym 9
takes Aegislash (Fighting shield for Aggron) and Lucario over Mega Metagross and Registeel.
Gym 1 takes Durant (Steel shield for Anorith) and a Sash Kartana off-theme; gym 3 Quagsire
(Electric shield for Brionne) and Forretress. Gyms 4 and 6 are unchanged: Douglas keeps
four originals so no slot was free, and nothing on Ground resists Grass, Ice or Water.

Result, gyms, 3 rounds on fix2's draw: **51/108 (47.2%) against fix2's 52/108** -- no
change (adjusted -0.9, 95% interval -15 to +14; shared battles 13 won / 14 lost, sign test
p = 1.0). Per gym: Dark went 2-10 to 5-7 (the Scarf U-turn Greninja enabler made 1.17 KOs a
battle and dealt 139%), Bug 7-5 to 10-2 (the Sash Kartana the off-theme slot drew made
2.83 KOs -- an OU Ultra Beast on a level-20 first gym, which the curve permitted because
five light bodies left a deficit), Ice 7-5 to 9-3 and Ground 5-7 to 1-11 on UNCHANGED
rosters, which is the noise floor in one line. The new functional slots: Whimsicott 1.00
KOs, Heliolisk 0.75, Durant 0.75, Metagross 0.42, Meloetta 0.42, Quagsire 0.25; the Mega
Lucario the Steel gym took over Mega Metagross made 0.08 at 1.2 turns in, and Steel went
5-7 to 3-9. The build is more like a real monotype team in shape (walls per type, a hazard
setter everywhere, the partners chosen for what they resist) and the sims cannot tell it
apart from the roster before it.

**Evolving toward the target, and a real bar for the originals** (2026-09-27,
`rnb_vs_gen_core2_10ms` and `_trainers_core2_10ms`, both on fix2's draws):
- `GROW_TO_TARGET 3`: a dev's own Pokemon may evolve up to three levels ahead of its
  evolution level when the evolved form sits nearer the fight's eBST target. Kenn's
  Brionne (420, Primarina wants level 34 and the fight is 31) anchored gym 3 at 60 SpA
  against a 504 target; it is now a Specs Primarina (530), and Abi's Dewpider (269, dropped
  under the band before) comes in as an Assault Vest Araquanid (454). Owen's Eevee and
  Teresa's Braixen evolve the same way.
- The measured bar rises from 0.2 KOs / 35% dealt to **0.6 KOs / 60% dealt** (the user's
  call, with a real attacker slot at 0.82 / 92% and an in-between set at 0.66): Anorith,
  Vespiquen, Wigglytuff, Pyukumuku, Zoroark, Camerupt (Dhara's mega ace), Aggron and
  Steelix leave the gyms; Leavanny, Roserade, Poliwrath and Duosion the trainers. Rival
  core families and mode evidence stay (Hippowdon at 0.25 KOs is gym 6's Sand Stream, so it
  stays). Gym 9 keeps nothing and takes Heatran as the anchor the curve allows; gym 6 puts
  the mega on Swampert, gym 5 gets Mega Sharpedo back beside Greninja.

Result: **gyms 49/108 (45.4%), trainers 63/120 (52.5%)**, against fix2's 52 and 66 --
both inside the noise (adjusted -2.8 and -2.5, intervals -17 to +13 and -15 to +9; sign
tests p = 0.74 and 0.76). The new bodies did their jobs -- Primarina 1.08 KOs / 147%
dealt, Mega Swampert 1.08 / 102%, Heracross 1.50, Forretress 0.83, Araquanid 0.75 --
and the total did not move: gym 7 went 0-12 (Psychic against Matt's Kartana and Sidney,
the draw the real Psychic teams also lose 0-4), Normal 2-10, the rest within a game or
two of fix2. Mega Sharpedo made 0.08 KOs on a Protect set. Three arms in a row now sit at
45-51% on the gyms and 48-55% on the trainers under quite different rosters, which says
the remaining gap to the real teams (64% balanced, 55-58% own-type monotype) is not in
which six bodies are chosen by these rules. What has not been tried: the second off-theme
slot gym 7's draw needs, and speed / EV spreads, which the sims play at zero EVs.


**The off-theme slot, and shipping** (2026-09-27, no sims -- three rosters in a row sat
inside the noise of each other, so these were judged on the roster). Three switches:
- `OFF_THEME_CAP` holds an off-theme pick under the fight's band ceiling, the ceiling kept
  originals already obey. It removes the level-20 Kartana from the Bug gym (Minior and
  Klefki cover Flying/Fire and Flying/Rock instead) and Ho-Oh (680 against a 650 ceiling)
  from the Champion, who takes a Band Dragonite (Fighting/Ground/Fire) instead.
- `OFF_THEME_MOST` gives the slot to the bodies that resist the MOST theme weaknesses still
  open, then lets the curve choose among them. Psychic's slot goes from a Fire/Water
  Volcanion (Bug only) to Magearna (Bug and Dark); Dark's from Dhelmise (Fighting) to
  Toxapex (Fighting, Bug and Fairy -- all three); Ice's from Slowking to Quagsire (Rock,
  Steel, Fire). Ghost stays open on gym 7: no legal body resists all three, and the floors
  protect every on-theme slot (see next).
- `OFF_THEME_EXTRA` spends a second slot off-theme, down to four on-theme, when a theme
  weakness is still unresisted after the build -- giving up the lightest generated
  on-theme body that is not a floor's last holder. It fires on the Ground gym only (Water
  was open; Celebi comes in for Donphan, whose Rapid Spin Excadrill already carries). On the
  Psychic gym every on-theme body is the last holder of a floor, so it does not fire.

The Boss Studio import is repaired: `team_load` un-pins an imported evolution in favour of
the original that grows into it but left that original un-asked, so the slot trim dropped
the original and the evolution reached the team by neither route (the shipped gym 2's
Azumarill). The original is now ticked, and a tick covers the line the way an untick does.

Shipping: the generator's current defaults are what the sims measured; the shipped
companion preset still carries pre-study settings (six on-theme, KEEP_MIN_BAND 5, hand
edits to a gym 2 roster that no longer exists), so the install should run from the
defaults, not the preset. `Install into game` in the Studio, or
`boss_studio.install_game({}, "all")`, validates the 27 fights, writes
teams_bosses_gyms.json / teams_trainers.json / Team_Overrides.rb and replaces the
Team_Overrides section of `Realidea V4.1/Data/Scripts.rxdata`; on the Deck the in-repo
bundle is byte-identical to the game's, so the game copy needs the same file afterwards.

**Realidea's learnsets were gen 5, and the generator refused egg moves** (2026-09-27).
Weavile's shipped set was Swords Dance / Aerial Ace / Ice Shard / Focus Punch: a gen 9 set
(the only ones carrying the Swords Dance the Ice floors asked for), Triple Axel replaced by
the strongest legal filler. Chasing why led to two facts about the game data rather than
the generator. Realidea's `pokemon.txt` carries Black/White egg lists (Sneasel's stops
before the gen 6 Icicle Crash and gen 7 Throat Chop) and its `tm.txt` has 171 of the gen 7
TM+tutor moves; and `realidea_data.learnable()` skipped the `EggMoves=` line on purpose.
- `tools/learnset_merge.py` brings the learnsets to gen 7 from Showdown's USUM data
  (`generated/showdown_learnsets_gen7.json`), additively and only for species and moves
  Realidea already defines: 646 level-up moves on 381 species, 302 egg moves (base stage),
  5,991 TM / tutor compatibilities (23 new `tm.txt` sections). Only `Moves=` / `EggMoves=`
  lines change. Excluded: Aurora Veil (below), Power Trip (function code 0 here), and Beak
  Blast, Revelation Dance, Solar Blade (no `PokeBattle_Move_` class in the scripts).
  Every other added move's function code has a handler, checked against the 382 effect
  classes in `Scripts.rxdata`; 415 of the 432 moves used are already taught to someone.
  Installed into the game's PBS with `.pre-gen7-*.bak` beside the originals; the game
  needs one debug-mode start to recompile. Reborn Yang's PBS was pulled to the Deck as a
  format reference and turned out to be gen 8/9 in its `tm.txt`, so it is not the source.
- `EGG_MOVES` (on): the generator accepts a move on the species' or a pre-evolution's egg
  list, as it does TMs. With both, set fidelity across the 54 gym slots rose 182 -> 201
  surviving published moves; every gym's roster moves (Araquanid takes the gen 7 OU Sticky
  Web lead set). Weavile still lands on the gen 8 set through the setup floor, so the
  filler avoid-list and a gen cap on sets remain open.
- Sticky Web WORKS in this engine (setter, switch-in Speed drop, Defog / Rapid Spin
  clearing, AI scoring all present); the study's exclusion was that no species learned
  it, which the merge fixes (Galvantula, Shuckle, Ribombee, Kartana by level).
- Aurora Veil was a stub: setter only, no `PBEffects::AuroraVeil` constant (using it
  raised an error), no damage hook, no countdown, no clearing. `tools/patch_aurora_veil.py`
  mirrors Reflect at every site (eight script sections, +55 lines: constant, side init,
  damage calc for both categories without stacking on the covering screen, end-of-round
  countdown, Defog / Brick Break / Shadow Shed clearing, stock AI, the study's probe) and
  stages the result at `generated/aurora_veil/Scripts.rxdata`; installing it is a copy the
  person makes. After that, `learnset_merge.py --with-aurora-veil` adds the move's
  learnsets (Alolan Vulpix / Ninetales and the other gen 7 learners).

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
# archetype / tier / team-trait cuts over every run; composition.py needs the game's PBS
REALIDEA_PBS=<game>/PBS python3 tools/rnb/archetypes.py
REALIDEA_PBS=<game>/PBS python3 tools/rnb/tiers.py
REALIDEA_PBS=<game>/PBS python3 tools/rnb/team_profile.py
# per-slot KOs / damage / faints from this machine's Showdown logs, by arm (SCHEDULE inside)
REALIDEA_PBS=<game>/PBS python3 tools/rnb/deck_slots.py            # DETAIL=<arm> lists its attacker slots
REALIDEA_PBS=<game>/PBS python3 tools/rnb/attacker_profile.py [NEW_ARM]
REALIDEA_PBS=<game>/PBS [GEN_ARMS=dir] python3 tools/rnb/core_strength.py
# the theme test: build an arm, export it, play it (Windows)
python3 tools/rnb/gen_fixes.py theme|tier OUTDIR
python3 tools/rnb/make_gen_battles.py 4 --from OUTDIR --name theme|tier
python3 tools/rnb/make_mono_battles.py rnb_vs_gen_fix2_10ms 2 [--gen7|--gen8]   # real monotype on the gyms' draws
RNB_OUT=generated/rnb_vs_gen_theme python3 tools/rnb/run_battles.py 4 3 100   # 100 ms, as played
python3 tools/rnb/score_arms.py rnb_vs_gen_deckoff rnb_vs_gen_theme rnb_vs_gen_tier
python3 tools/rnb/compare_runs.py rnb_vs_gen_deckoff rnb_vs_gen_theme
# on Linux: Python 3.12 for setup_battles.py (uv), cargo (rustup); add
# exports.repl = false (socket path too long) and exports.bindaddress = "127.0.0.1"
# to the local Showdown config.js
```
