# Portable AI doubles work

## 0.7.0 first coordination batch — 2026-09-06

This version moves doubles policy into the joint planner, where the value of one
Pokemon's action can depend on its partner's action. Four rules are independently
switchable from `Data/ai_harness.txt`:

The four rules are **disabled by default** while `REBORN-DOUBLES-AI.md` is completed
and their behavior is checked against traced Reborn decisions. They remain available
as experimental arms for A/B runs.

| key | paired action |
|---|---|
| `protect_spread_combo` | Protect refunds the friendly-fire cost of the partner's spread move |
| `partner_support_combo` | Helping Hand, Coaching, or Decorate gains value from the partner's damage |
| `redirect_setup_combo` | Follow Me or Rage Powder protects setup, Tailwind, or Trick Room |
| `fakeout_speed_combo` | Fake Out buys a turn for the partner's Tailwind or Trick Room |

The source fixture is `adapters/reborn/Doubles_Teams.rb`. Its sets are adapted for the
Reborn engine from Pokemon Showdown's Gen 8 Doubles OU set data. It includes rain,
redirection plus setup, sand plus speed control, and Trick Room cores. It is named
`doubles_a` and does not alter historical `set_a` through `set_g`.

### First paired run

Frame: two frozen double matchups, five fixed seeds, 6v6, Portable on the right against
Reborn Normal. This is a smoke-sized frame, not a strength conclusion.

| arm | wins | losses | mean turns |
|---|---:|---:|---:|
| all four rules off | 5 | 5 | 9.3 |
| all four rules on | 5 | 5 | 9.9 |

One battle was gained and one was lost. The result is deliberately reported as flat:
ten battles cannot estimate strength, and the four rules still need per-key ablations
and traced action readouts before tuning their weights.

## Experimental joint outcome planner

`doubles_outcomes=true` replaces the independent damage part of two move scores with
one shared turn simulation. It tracks HP per target, priority, speed, Trick Room,
accuracy branches, Focus Sash/Sturdy, Protect, friendly spread damage, and the loss of
an action when a battler faints earlier in the turn. Spread damage is kept per foe, so
two 60% hits cannot be mistaken for one 120% knockout. Two allies can focus their hits
for a real knockout, while two individually secured knockouts are split between foes.
Duplicate switches into the same reserve slot are rejected as illegal pairs.

The Reborn adapter also supplies a plausible response from each opponent. Each foe's
strongest known attack is tried against either ally. The visible fraction of damaging
moves weights whether that foe attacks at all, so a four-attack set and a support set
do not create the same incoming-damage forecast.

The outcome evaluator and adversarial planner are **enabled by default for the 0.8.1
playtest build**. `tests/check_doubles_outcomes.rb` is a dependency-free regression
check that runs through Reborn's bundled Ruby DLL with `tools/run_embedded_ruby.py`
when a system Ruby is unavailable. The weaker opponent-utility, Fake Out timeline,
root-search, and Foul Play leaf variants remain independently switchable and off.

### Measurement sequence

The first 40-battle mixed frame contained only ten doubles battles. The initial exact
outcome implementation removed too much of the individual move scorer and was
discarded. Preserving that scorer and replacing only its damage/KO term stayed flat at
5/10 doubles. Adding opponent responses reached 8/10, compared with 5/10 in the frozen
control, but the frame was too small to support a strength claim.

The broader `doubles_audit` schedule runs all 12 ordered, non-mirror pairings of the
four `doubles_a` archetypes at five fixed seeds: 60 battles per arm. This first table
is the pre-pull result on the 0.6.2-based working tree.

| arm | wins | losses | mean turns |
|---|---:|---:|---:|
| `doubles_outcomes=false` | 29 | 31 | 9.42 |
| `doubles_outcomes=true`, attack-set weighting | 35 | 25 | 10.93 |

The enabled arm gained 13 cells and lost 7, a net gain of six wins. Exact McNemar
`p=0.263`; this is encouraging but not statistically significant. Results by portable
team archetype were:

| portable archetype | control | enabled | change |
|---|---:|---:|---:|
| balance | 14/15 | 11/15 | -3 |
| bulky | 3/15 | 4/15 | +1 |
| offense | 5/15 | 11/15 | +6 |
| speed | 7/15 | 9/15 | +2 |

Traced `speed_vs_balance` losses showed the remaining limitation: the response model
still reduces a foe to its strongest attack plus a moveset-level attack probability.
It does not yet predict the particular utility move, switch, redirection, Fake Out,
or status action selected on that board. Opposing spread attacks are also represented
as targeted attacks, and target assignments are weighted equally. Because the balance
regression remains and the sample is one fixture set, the outcome planner stays opt-in.

### Post-0.6.4 integration experiments

After rebasing the doubles work onto the upstream 0.6.4 singles core, two extensions
were implemented and measured independently over the same 60 battle cells.

The pull changed the singles baseline to 0.6.4, so both doubles arms were rerun rather
than comparing with the stale pre-pull control.

| 0.6.4-based arm | wins | losses | mean turns |
|---|---:|---:|---:|
| `doubles_outcomes=false` | 29 | 31 | 9.65 |
| attack-set outcome baseline | 33 | 27 | 10.42 |

The outcome baseline gained 13 cells and lost 9 against its matching control: +4 wins,
exact McNemar `p=0.523`. Its archetype wins were balance 11/15, speed 9/15, bulky 3/15,
and offense 10/15.

| additional experiment | wins | change from 33/60 outcome baseline | decision |
|---|---:|---:|---|
| opponent utility response | 34/60 | +1 | retain as `opponent_utility=false` |
| exact Fake Out flinch timeline | 31/60 | -2 | retain as `fakeout_timeline=false` |

The utility branch predicts one visible non-damaging response such as Tailwind,
Trick Room, Protect, team protection, redirection, status, setup, or a screen. It
changed choices in the traced support matchup and improved bulky from 3/15 to 8/15,
but reduced speed from 9/15 to 6/15. It gained eight cells and lost seven; the large
archetype redistribution for one net win is not evidence to enable it.

The Fake Out timeline correctly removes a struck foe's later action and passes an
isolated regression where that preserves the partner's speed-control action. In the
battle sweep it changed six cells relative to the outcome baseline, gaining two and
losing four. Until target prediction is strong enough to know which opposing action
Fake Out actually prevents, its exact downstream credit is also disabled.

The accepted experimental baseline remains attack-set weighting with both flags off:
33/60 versus its matching control's 29/60. The next implementation should predict opponent targets
and utility choices from board state before either rejected timeline feature is
re-enabled.

### Stage A: shallow adversarial joint search

`doubles_adversarial=true` adds the first Foul Play-inspired search layer without
embedding a full battle engine. For each allied active, it keeps at most five actions.
The highest raw-scoring action is always retained, while the remaining beam reserves
room for a switch, Protect or team protection, redirection, field speed control, and a
first-turn move when those categories are available. This avoids losing the joint
plans that make doubles distinct merely because their support half has a low individual
score.

Every retained allied pair is evaluated against the existing weighted opponent target
combinations. Tie-order variants are averaged within each response. The final response
value is 60% probability-weighted expectation, 30% worst credible response, and 10%
best response. Branches with zero probability are excluded from the extrema. The
weights deliberately make the planner cautious without allowing a rare bad branch to
erase all expected value.

The same 60 paired `doubles_audit` cells produced:

| arm | wins | losses | mean turns |
|---|---:|---:|---:|
| attack-set outcome baseline | 33 | 27 | 10.42 |
| adversarial beam + robust response value | 37 | 23 | 10.60 |

The adversarial arm gained seven cells and lost three, net +4. Exact McNemar `p=0.343`,
so this is a promising engineering result rather than a strength claim. By portable
team archetype, offense improved 10/15 to 12/15 and bulky improved 3/15 to 5/15;
balance stayed 11/15 and speed stayed 9/15. After rebasing onto the 0.8.0 singles
search, the same adversarial control reached 38/60 and remained the strongest stable
configuration. It is therefore the 0.8.1 playtest default; broader rosters remain the
next validation step.

Artifacts: `generated/doubles_audit_adversarial.ndjson` and
`generated/doubles_audit_adversarial_summary.txt`.

### Rebase onto the 0.8.0 singles search

Upstream 0.8.0 contains two distinct singles search results. The native Ruby
maximin/MCTS planner reached 135/180 against the rule planner's 140/180 at roughly
100 times the decision cost. The external Foul Play sidecar, using poke-engine on a
more complete board, reached 162/180 against the rules' 143/180 (`p=0.005`). The
sidecar and poke-engine state generator decline doubles, so its code path cannot be
enabled directly for this project.

The transferable design was tested in two independently switchable parts on the
rebased 0.8.0 core. Both runs used full traces and the same 60 paired cells:

| arm | wins | losses | mean turns | paired change |
|---|---:|---:|---:|---:|
| adversarial 60/30/10 control | 38 | 22 | 11.0 | — |
| 50/50 worst + expected reply, Foul Play HP/alive leaf | 29 | 31 | 11.6 | -9 |
| 50/50 worst + expected reply, calibrated doubles scale | 38 | 22 | 12.3 | 0 |

The failed leaf arm gained seven cells and lost sixteen (`p=0.095`). A named trace
shows the scale mismatch directly: full-health Kingdra switched away from a guaranteed
Draco Meteor knockout on Garchomp because the rule planner's +318 switch term was mixed
with a leaf where a knockout is only remaining HP plus 30. The leaf is therefore kept
as `doubles_search_leaf=false`; it should be reconsidered only inside a standalone
state evaluator that also projects support, setup, redirection, speed control, weather,
and field effects.

The isolated root policy gained three cells and lost three (`p=0.683`). Offense and
bulky were unchanged, speed gained one, and balance lost one. This establishes that
the singles search's response aggregation is viable but not stronger on this frame.
`doubles_search=false` remains the default.

The next search step should use the rule planner as the leaf evaluator inside a
decoupled simultaneous-move tree. Before that tree can model the opposing side rather
than a coarse response, the adapter must export every visible opposing move with its
damage, accuracy, priority, targeting mode, and support effect. Joint foe actions can
then be pruned and searched by the same role-aware beam used for allied actions.

Every future simulation should run with `trace=true` and then execute:

```text
python tools/render_all_battles.py generated/<run>.ndjson generated/<run>_logs
```

The output contains one Pokémon-named, turn-by-turn text file per battle plus
`INDEX.txt`; battler indexes remain only in the raw NDJSON for joining records.
