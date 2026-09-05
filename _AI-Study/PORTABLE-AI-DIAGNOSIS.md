# Portable AI 0.3.2 → 0.4: where the remaining 9.7 points are

Written 2026-09-05 from the traces already in `generated/` (no new battles were run).
Companion to `PORTABLE-AI-REBORN.md`, which ends with 0.3.2 at **210/300 (70.0%)**
against a fair Reborn-Normal ceiling of **239/300 (79.7%)** and three open questions:
bulky is the weakest archetype, move selection inside an agreed attack is the largest
shadow disagreement class, and agreement is lowest when the foe is below 25% HP.

This document answers those three with numbers, reads the matching Reborn-Normal
code for each, and turns the result into an ordered list of core rules. Everything
here reproduces with `tools/policy_gaps.py` (new) plus `tools/compare_arms.py`.

**The switch programme is done. The remaining gap is three missing move rules, and
one of them — recovery clicked on a turn the healer then dies — is on its own the
size of the whole gap.**

---

## 1. Where the gap sits, by matchup

Measured seat (rows) vs the left Reborn-Normal team (columns), wins out of 25 per
cell over all five rosters. `P` is Portable 0.3.2, `R` is Reborn-Normal in the same
seat (`generated/reborn_6v6_v032_set_*.ndjson`,
`generated/reborn_6v6_normal_baseline_fairceiling_set_*.ndjson`).

| pilots ↓ / vs → | offense | balance | bulky | speed | total /75 |
|---|---|---|---|---|---|
| offense | — | P 23 / R 24 | P 25 / R 25 | P 18 / R 20 | **66 / 69** |
| balance | **P 9 / R 18** | — | P 23 / R 24 | P 19 / R 22 | **51 / 64** |
| bulky | P 7 / R 9 | P 16 / R 19 | — | **P 15 / R 21** | **38 / 49** |
| speed | P 17 / R 19 | P 15 / R 19 | P 23 / R 19 | — | **55 / 57** |

Two things the archetype totals hid:

- **Bulky is hard for Reborn too** (49/75). Portable's bulky deficit is 11 battles,
  the same size as balance's 13. The single worst cell in the study is **balance
  piloted against offense: 9/25 vs 18/25**.
- Portable's balance and bulky teams are being **out-traded, not swept**. In
  `offense_vs_balance` the KOs Portable suffers come from unboosted wallbreakers
  (107 unboosted vs 27 boosted) and the KO exchange per battle on set_a–c is
  balance-vs-offense R 4.4 dealt / 4.2 taken against P 4.0 / 4.5, bulky-vs-offense
  R 4.4 / 4.3 against **P 3.6 / 4.5**. The defensive teams deal fewer KOs than Reborn
  does with the same six Pokémon. That is a "how are the walls spending turns"
  problem, and §2 is most of it.

Decision mix on the three rosters where both arms have full traces
(`compare_arms.py generated/reborn_6v6_fairdiff_set_*.ndjson generated/reborn_6v6_v032_set_[abc].ndjson`):

| share of turns | Reborn-Normal | Portable 0.3.2 |
|---|---:|---:|
| attack | 73.8% | 71.9% |
| switch | 4.0% | 9.6% |
| recover | 9.6% | 9.1% |
| status | 3.8% | 3.8% |
| setup | 3.3% | 2.8% |
| phaze | 1.0% | 0.2% |
| hazard | 1.1% | 0.2% |
| protect | 1.0% | 0.7% |

Recovery volume is identical. What differs is *when* it is clicked.

---

## 2. Heal-deaths: the biggest single defect

A **heal-death** is a recovery move chosen on a turn at the end of which the healer
is no longer on the field (phazes excluded, so this is a KO). `policy_gaps.py heal`:

| heals that were heal-deaths | Reborn-Normal (180 battles) | Portable 0.3.2 (300 battles) |
|---|---:|---:|
| all recovery clicks | 53 / 404 (**13%**) | 143 / 575 (**25%**) |
| clicked below 25% HP | 23 / 70 (33%) | 103 / 168 (**61%**) |
| clicked at 25–50% HP | 26 / 173 (15%) | 37 / 215 (17%) |
| healer estimated slower | 49 / 265 (18%) | 102 / 262 (**39%**) |
| healer estimated faster | 4 / 139 (3%) | 41 / 313 (13%) |

Below 25% HP, Portable's recovery click is a coin flip that it dies on the spot;
when it is also slower, it is worse than a coin flip. It is not rare: **112 of the
300 battles contain at least one**, and they track the result — battles with none
are won at 80% (188), with exactly one at 50% (86), with two or more at 62% (26).
Some of that is "losing positions produce desperate heals", but the four examples
below are all winnable positions thrown away on turn 8–17 of a 6v6.

```
set_a offense_vs_balance 104729 t8:  Clefable   48/352 (14%) Soft-Boiled  vs Gengar 247/282   Sludge Bomb -> died
set_a offense_vs_balance 130363 t9:  Dragonite  40/344 (12%) Roost        vs Garchomp 247/378 Dragon Claw -> died
set_a offense_vs_bulky   130363 t4:  Umbreon    28/352 ( 8%) Moonlight    vs Greninja 306/306 Ice Beam    -> died
set_a offense_vs_bulky   155921 t11: Hippowdon  15/378 ( 4%) Slack Off    vs Greninja 306/306 Ice Beam    -> died
```

Every one of these scored the heal at 290–335 (`portable_trace`), which is exactly
what `core.rb:104-119` says it should: at ≤35% HP the heal gets `220 + 3·(35−hp)`,
and the only thing pulling the other way is `heal_under_lethal_threat −80`. A
300-point heal beats any non-lethal attack, so a battler at 8% HP heals into a
Greninja that does 100% to it, twice if it survives the first.

**Reborn's `recovercode` (`PokeBattle_AI_2.rb:7558`) asks the one question
Portable does not:** does healing change whether I die?

```ruby
maxdam = incoming damage from the foe's best known move
if maxdam > @attacker.hp                      # I die this turn without a heal
  return 0 if maxdam > recoverhp              # ...and also WITH one: heal is worthless
  miniscore *= 5                              # the heal is what keeps me alive
  miniscore *= 6 if hasgreatmoves()           # even over a KO move
else
  miniscore *= 0.2 if maxdam > amount         # losing race: I heal less than I take
  miniscore *= 2   if maxdam*1.5 > hp         # a second hit would kill: pre-empt
  miniscore *= 5   if !faster && maxdam*2 > hp
end
miniscore *= 0.3 if foe is on its last mon && I have a KO move
miniscore *= 0.7 if the foe carries a setup move
miniscore  = 0   if hp > 80%; *= 0.6 if hp > 60%; *= 2 if hp < 25%
```

**Correction (2026-09-05, decision-log run):** Reborn *does* check speed here — the
"not going to die yet" branch calls `pbAIfaster?` and, when slower and `maxdam*2 > hp`,
heals pre-emptively (×5). What it does **not** do is refuse a heal for being slower:
once in KO range it heals ×5 whenever the heal would take it back out of range,
regardless of speed, and its 18% slower-healer death rate is the price of that gamble.
0.4.0's `heal_cannot_resolve` (−400 when slower) is therefore not a copy of Reborn but a
reversal of it. `PORTABLE-AI-REBORN.md` §"Decision-log run" measures the reversal: it is
right 85% of the time when the threatening move is 100%-accurate and the foe is awake,
and wrong 72% of the time otherwise.

**The evidence Portable needs is already in the snapshot.** `incoming_damage_pct`
is computed per actor by the adapter (`Portable_AI_Adapter.rb:558`) and is what
`threatened_lethal?` reads. Missing: the heal amount (a tag — `heal` is 50%, Rest is
100%, Moonlight/Synthesis/Morning Sun are weather-scaled, Pain Split is variable)
and the actor's speed order. `battler_view` already exports the foe's `speed`;
`build_actor` needs to export its own so the core can compare, or the adapter can
hand over a `faster` boolean directly.

Rule shape for `core.rb`, replacing the flat `heal_under_lethal_threat −80`:

| situation | value | Reborn analogue |
|---|---|---|
| slower **and** `incoming ≥ hp` | heal cannot resolve: −400 | none (Reborn's blind spot) |
| `incoming ≥ hp + heal_amount` | heal does not change the outcome: −400 | `return 0` |
| faster, `incoming ≥ hp`, `incoming < hp + heal` | heal is what saves me: +150 | `×5` |
| `incoming > heal_amount` (not lethal) | losing race: −120 | `×0.2` |
| foe reserves 0 **and** I have a lethal move | −200 | `×0.3` |

Keep the existing low-HP bonus underneath so `heal_when_low`, `heal_at_low_hp`,
`heal_beats_weak_attack` and `kill_over_heal` keep passing.

**Corrected 2026-09-05 (measured, not assumed):** the claim that none of those four
puts the healer under lethal threat was wrong. Instrumenting the probe gives
`heal_at_low_hp` a Blissey at **12.1% HP against an 18.8% Psychic, slower** — it dies
on every damage roll before it can heal, so the card was asserting that healing into
certain death is correct, and stock Reborn passed it only through the `recovercode`
blind spot described above. The card was repaired to 24% HP (what it always meant:
low, threatened, and worth healing) rather than the rule weakened. `heal_when_low`
(14.9% vs 31.5%) is the same shape but is a `must_choose_any` card, so it constrains
nothing. Verify a card's numbers before trusting it to constrain a rule. The corpus has
**no scenario for heal-into-death**; add two (slower + lethal, faster + lethal-even-
after-heal) before measuring. Fair-information caveat unchanged: `incoming_damage_pct`
reads the foe's real moves, as it already does for switching.

---

## 3. The finishing tiebreak: accuracy, priority, self-cost

Of 4318 controlled shadow decisions (`reborn_6v6_v031_set_*.ndjson`, 0.3.1 planner),
Portable scored its pick as lethal (≥600) on 1114 turns. Reborn-Normal chose the
same move on 767. The 343 disagreements (`policy_gaps.py finish`):

| Reborn-Normal picked… | n |
|---|---:|
| a different KO move — mostly its roulette among equal 110s | 154 |
| a **status or recovery** move instead | 64 |
| the **more accurate** KO move | **60** |
| a **priority** KO move | **59** |
| a KO move without a **self-stat-drop / self-KO** cost | **24** |
| the *less* accurate KO move | 12 |

The top pairs are the whole story: `SUCKERPUNCH vs KNOCKOFF` (14), `AQUAJET vs
WATERFALL` (12), `EARTHQUAKE vs STONEEDGE` (10), `EXTREMESPEED vs DRAGONCLAW` (8),
`ICESHARD vs ICICLECRASH` (8), `SHADOWBALL vs FIREBLAST` (7). The 154 "other" is
Reborn picking at random among moves it scored equal (`chooseAction` prefers
≥95% of max, doubly weights the max) and is not a policy.

Why Portable gets these wrong is visible in `core.rb:85-101`. A lethal move gets a
flat +500; `expected_damage` is *not* added for lethal moves; the only remaining
terms are `super_effective +35·eff`, `resisted −45`, and the `action_key` sort —
**move slot order**. So among two KO moves the tiebreak is "is it super-effective,
else the lower slot". Accuracy, priority, speed and self-cost do not exist in the
scorer: `priority` is exported by the adapter (`action_for_target`) and tagged in
`effects.rb`, but no rule reads it; the actor has no speed; there is no accuracy
field at all; Draco Meteor, Close Combat, Superpower and Explosion are untagged.

Reborn-Normal's damaging-move scale, for contrast (`buildMoveScores` singles path,
`PokeBattle_AI_2.rb:1470-1535`, then `getMoveScore`):

- base = `damage · 100 / foe.current_hp`, capped at **110**; if that hits the cap
  and accuracy < 100, **109.5** — every KO move loses to an accurate KO move;
- every move is then multiplied by **`(accuracy + 100) / 200`** (`:3349`) — Stone
  Edge is worth 0.9 of itself, Focus Blast 0.85, Hurricane 0.85;
- a priority move that KOs is **×1.3 when faster, ×2 when slower**, and gets
  **+150** when the user is slower and the foe's best move would KO it (`:2855-2923`);
- self-stat-drop moves are ×0.9 when they do not KO and **×0.6 whenever a KO move
  exists elsewhere** (`selfstatdrop`, `:6118`); Explosion is ×0.7·(1 − hp%),
  i.e. ×0.14 at full HP (`deathcode`, `:7779`).

The same four blind spots show outside the finishing decision. Across all 459
attack-vs-different-attack shadow disagreements, Portable's pick had higher raw
STAB-power at equal effectiveness 213 times and better type effectiveness 141 times
— it is a "highest number wins" scorer — while Reborn's was more accurate 90 vs 42
and priority 73 vs 29. Live usage per 1,000 measured turns (set_a–c, both arms):

| move | Reborn-Normal | Portable | note |
|---|---:|---:|---|
| Draco Meteor | 5.3 | 12.0 | `DARKPULSE vs DRACOMETEOR` is the #1 shadow pair (27) |
| Close Combat | 7.4 | 15.2 | |
| Superpower | 0.5 | 4.4 | |
| Overheat | 0.0 | 1.6 | |
| Fire Blast | 4.9 | 13.5 | over Flamethrower/Shadow Ball |
| Hurricane | 9.0 | 4.5 | Reborn prefers it *over* Draco Meteor on Noivern |
| Explosion | 1.6 | 1.9 | Portable exploded at **100% HP 15 of 21 times** |
| Volt Switch | 3.0 | **0.0** | never chosen: 70 BP always loses to Thunderbolt |
| Stealth Rock | 8.3 | 1.6 | |
| Whirlwind / Roar | 6.5 / 3.0 | 1.2 / 0.9 | |
| Haze | 0.5 | 2.8 | `phaze_value` over-rewards Haze; Reborn-Normal barely uses it |

Rules for `core.rb`, in the order they pay:

1. **Accuracy.** Adapter exports `accuracy` from `pbRoughAccuracy` (an engine
   primitive under AI-PORTABILITY §4; it needs `@mondata` staged, which
   `with_neutral_estimation` already does). Core: scale `expected_damage` by
   `(acc+100)/200`, and scale the lethal bonus the same way so a 100%-accurate KO
   strictly beats an 80% one. Covers 60 of 343 finishing disagreements and the
   Fire Blast / Stone Edge / Hydro Pump / Focus Blast over-use.
2. **Priority vs speed.** Actor exports `speed` (mirror of `battler_view`). Core:
   when `priority > 0` and the move is lethal, +60 if faster, +150 if slower; when
   slower and `threatened_lethal?`, a lethal priority move gets a further +200 and
   non-priority lethal moves lose their lethal bonus (the KO never lands). 59
   finishing disagreements. Note the corpus scenario `priority_secures_kill_when_slower`
   **does not test this** — Azumarill's Play Rough is resisted by Gengar's Poison
   typing, so the `resisted −45` rule picks Aqua Jet for the wrong reason. Write a
   real one (Ice Shard vs Icicle Crash into a faster foe at 20% HP).
3. **Self-cost tags** in `effects.rb`: `self_drop` (Draco Meteor, Overheat, Leaf
   Storm, Superpower, Close Combat, V-create, Psycho Boost, Fleur Cannon),
   `self_ko` (Explosion, Self-Destruct, Final Gambit, Memento, Healing Wish). Core:
   `self_drop` −40 when not lethal, −15 when lethal (so it stays the pick when it is
   the only KO); `self_ko` −400 unless `hp_pct < 30` or own reserves are 0. The
   existing `fail_explosion_vs_ghost` scenario tests immunity only — add
   "don't explode at full HP with a KO alternative".
4. **Pivot value** (`pivot` tag exists, unused): +40 when a bench mon exists and the
   user is slower, +25 when faster; −200 when own reserves are 0. Lowest
   confidence of the four — Reborn's `pivotcode` (`:7934`) is elaborate and the
   traces only show Portable never clicks Volt Switch, not that it should.

The deeper option, worth considering rather than adopting now: **Reborn's whole
damaging-move scale is "% of the foe's *current* HP, capped at 110".** Portable's is
`0.8 × % of total HP` plus a flat 500 for lethal. Reborn's makes finishing
continuous (a 60%-of-remaining move is worth 60 whether the foe is at 100% or 30%)
and the 10-point cap band is where its accuracy/priority/self-cost tiebreaks live.
Portable's flat 500 is why every KO looks identical to it. Moving to Reborn's scale
is a one-line change in `score_move` but shifts every scenario's score vector;
it is the kind of change to A/B on all five rosters, not to slip in.

---

## 4. Why walls leave — RETRACTED (the switch gate is finished)

**This section originally proposed a fifth rule, and it was wrong. Reading the actual
logs inverted its evidence, so no wall rule was implemented.** It is kept, corrected,
because the mistake is instructive: every number in it was right and the conclusion was
still false.

The measurement stands. Portable's live switch rate is 2.4x Reborn-Normal's (9.6% vs
4.0%), and `policy_gaps.py leave` attributes the 494 shadow turns where Portable would
have switched and Reborn stayed:

| gate reason (estimated) | all | offense | balance | bulky | speed |
|---|---:|---:|---:|---:|---:|
| `no_effective_move` | 98 | 0 | 0 | **98** | 0 |
| `lethal_while_healthy` | 139 | 28 | 35 | 17 | **59** |
| `weak_current_attacks` | 22 | 2 | 1 | 16 | 3 |
| `bad_stats` | 13 | 3 | 0 | 0 | 10 |
| unattributed (Leech Seed / Yawn / Toxic chip; offline estimate) | 226 | 66 | 41 | 96 | 23 |

All 98 `no_effective_move` turns are Chansey against Gengar. The original claim was that
Chansey should stay and Toxic-stall, and that Portable leaving was the defect.

**Gengar is Ghost/Poison.** Seismic Toss is immune *and so is Toxic*. Chansey has
nothing to do in that matchup, and the logs say so plainly: Reborn-Normal's Chansey sat
there for 30 turns (seed 130363: a Protect/Soft-Boiled loop against a 10-HP Gengar;
seed 155921: 30 turns of immune Seismic Toss and immune Toxic until it died and the
battle was lost). Portable's shadow answer — switch to Slowbro, whose Psychic is
super-effective — was the better move. **Reborn's staying is a Reborn weakness, and the
98 turns are evidence for Portable, not against it.**

The live 0.3.2 bulky switches are not walls fleeing either. They are diffuse
type-disadvantage pivots — Chesnaught vs Salamence, Quagsire vs Ludicolo, Forretress vs
Noivern, Tsareena vs Emboar — which is `lethal_while_healthy`, the reason the switch
programme already decided to leave alone.

Two lessons worth more than the rule would have been:

- The claim "Chansey stayed and Toxic-stalled every time" was never checked against a
  decision log, because gauntlet runs did not keep one (`$INTERNAL` was forced false
  regardless of `log_decisions=`). Both halves of that are now fixed — see "0.4.0" in
  `PORTABLE-AI-REBORN.md`.
- A type line is part of the evidence. Poison's immunity to Toxic decided this section.

**Conclusion: the switch gate is finished. Do not add a wall rule.** `no_effective_move`
stays exactly as it is, and `lethal_while_healthy` stays untightened (Reborn's own
battler dies 61-78% of the time when it stays there).

## 5. What this does and does not claim

- The heal-death and finishing numbers are **measured behaviour**; the win-rate
  effect of fixing them is an inference. The doc's own rule applies: implement,
  scenario-test, rerun `normal_baseline` on all five rosters, quote the pooled
  paired McNemar, and expect set_a to disagree with the others.
- Speed order in §2 and §4 is estimated from base stats and stages (L100, 31/85
  neutral, the gauntlet's `make_party`); paralysis and Choice items are absent from
  the rosters, so the estimate is close but not exact.
- The 226 unattributed would-switch turns are the offline estimator's limit — it
  cannot see Leech Seed or Yawn in the trace. A `reasons` field on the shadow trace
  entry (the planner already computes it) would close that at zero cost.
- Hazards and phazing are 5× under-used relative to Reborn-Normal, but
  `PORTABLE-AI-REBORN.md` already showed hazards do not move Intense's win rate.
  Left as a candidate with no claim.

Recommended order: §2 heal gate → §3.1 accuracy → §3.2 priority/speed → §3.3
self-cost tags → §3.4 pivots. (§4's wall gate was retracted before implementation.)

**Status (2026-09-05): §2, §3.1, §3.2 and §3.3 are implemented as Portable 0.4.0 and
measured; §3.4 pivots remain untouched. The heal gate delivered its mechanism in full —
heal-deaths 25% → 7%, past Reborn-Normal's 13% — and is the only one of the four that
moved battles. See "0.4.0" in `PORTABLE-AI-REBORN.md`.** The first three each touch one rule
and one adapter field; together they address ~260 of the 343 finishing
disagreements and every heal-death in the table.
