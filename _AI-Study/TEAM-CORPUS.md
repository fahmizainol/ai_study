# What 54,522 Real Teams Say About Generated Ones

Companion to `TEAM-DESIGN.md` and `BOSS-CURVE.md`. Those two answer *what a boss
carries* and *how strong it is*. Neither asks whether the result looks like a team
anyone would build, because until this corpus existed there was nothing to ask.

Provenance, per-tier pools, parser traps and tag validation live in
`extracted/smogon-dump/SOURCE.md` and are not repeated here. This file is the
findings: what the corpus measured, what it changed, and — as much of the value —
which readings did **not** survive checking.

Regenerate everything here with:

    python3 tools/team_shape.py --refresh      # the corpus reference
    python3 tools/boss_diagnostic.py           # score the shipped teams
    python3 tools/boss_diagnostic.py --matrix  # gym x archetype feasibility (slow)
    python3 tools/boss_studio.py               # tweak the knobs live, 127.0.0.1:8731

## 1. Why this corpus and not the ones already vendored

`smogon-formats/`, `smogon-sets/` and `smogon-stats/` are all **marginals**: what one
species does, averaged over every team it appeared on. `smogon-dump/` is the only
**joint** — whole six-mon teams exactly as their authors posted them. Marginals can
tell you Landorus-T is popular and pairs with Heatran. Only the joint can tell you what
a *balance team* carries that a *hyper offense team* does not, which is the entire
subject of this document.

| | six-mon teams |
|---|---|
| all records scraped | 64,240 |
| complete six-mon teams | 60,969 |
| singles (doubles excluded — every figure below) | **54,522** |
| carrying an author's archetype label | 1,959 |

The 1,959 labelled teams are the bridge: the author's own word on 4% of the corpus is
what turns the other 96% into a reference an unlabelled team can be measured against.
No classifier is involved in anything below — the per-archetype columns are a report of
what authors who wrote "stall" in the title actually built.

## 2. Archetype separates roles, and almost nothing else does

Share of teams carrying at least one set that does the job:

| role | all | stall | balance | bulky off | offense | hyper off |
|---|---|---|---|---|---|---|
| hazards | 91% | 93 | 98 | 95 | 94 | 87 |
| removal | 68% | 86 | 85 | 84 | 64 | **38** |
| setup | 79% | **64** | 79 | 81 | 82 | **97** |
| pivot | 69% | **25** | 73 | 78 | 70 | **35** |
| recovery | 78% | **99** | 98 | 95 | 72 | **48** |
| status | 63% | **92** | 85 | 74 | 61 | **34** |
| priority | 49% | **15** | 38 | 39 | 60 | **66** |
| protect | 40% | 62 | 47 | 29 | 40 | 37 |
| phaze | 17% | 27 | 29 | 20 | 11 | 15 |
| screens | 6% | 4 | 2 | 2 | 1 | **24** |
| speed control | 30% | 12 | 26 | 38 | 31 | 34 |
| **EV offence share** | 56% | **15** | 42 | 50 | 62 | **78** |
| n | 54,522 | 336 | 452 | 416 | 255 | 500 |

**Only hazards is universal.** Every other role is archetype-specific, and the ordering
is monotone along the offence axis for removal, recovery, status, priority and EV share
— which is what makes the axis usable rather than merely descriptive.

The axis is stable across gen 5 through gen 9 (stall ~10-15% of labelled teams, balance
~41-43%, hyper offense ~77% offensive EVs in every generation). That stability is the
argument for applying it to a gen-6-era fangame at all: it is structural, not a feature
of one metagame.

### Presence is the wrong question; counts are the right one

Mean sets per team covering the role:

| role | stall | balance | bulky off | offense | hyper off |
|---|---|---|---|---|---|
| recovery | **4.76** | 3.03 | 2.54 | 1.54 | **0.88** |
| setup | 0.96 | 1.12 | 1.34 | 1.79 | **3.06** |
| status | 2.19 | 1.57 | 1.19 | 0.81 | 0.50 |
| pivot | 0.31 | 1.20 | 1.39 | 1.34 | 0.44 |
| removal | 1.15 | 0.95 | 0.91 | 0.69 | 0.43 |

A presence quota scores stall's 4.76 recovery sets and hyper offense's 0.88 as the same
tick in the same box. This is the single most important thing the corpus added, and the
reason `team_shape.role_plan()` emits counts.

## 3. What it said about the nine shipped boss teams

`generate_bosses.py` chased a flat `QUOTA = [hazards, recovery, setup, pivot, mega]` for
every fight — which, measured here, is a *balance* recipe applied nine times.

Mean pairwise L1 distance between the teams' role vectors, against nine real teams drawn
from the corpus (4,000 bootstrap draws). **This split is against the historical flat
`QUOTA`**, so `boss_diagnostic.py` no longer reproduces the row labels — it now holds out
whatever `generate_bosses.CHASED_ROLES` currently names. The shipped teams still score
1.7% overall and 0.0% on the chased half, whichever set is held out:

| measured over | the nine bosses | nine random real teams | percentile |
|---|---|---|---|
| the 4 roles `QUOTA` named | 1.28 | 4.56 | **0.0%** |
| the 7 roles it did not | 5.17 | 4.02 | 93% |
| all 11 | 6.44 | 8.58 | 1.7% |

**Nine random ladder teams differ from each other more than nine themed gym leaders
did — but only across the roles the generator was told to fill.** That decomposition is
the finding. Undecomposed, "these teams are samey" would have been blamed on the level
caps, the type themes or the dex; split this way, those are exonerated (93rd percentile
where the generator stayed silent) and the instruction is convicted.

## 4. Readings that did not survive their null

Recorded because each one looked like a finding and cost real time to disprove.

| claim | what it looked like | the null | verdict |
|---|---|---|---|
| "roles and EV split disagree" | 7 of 9 bosses | real teams disagree **67%** of the time under the same two crude readers | noise |
| "`removal` 0/9 vs 68% is a generator bug" | a missing quota entry | only **0-7 species per type theme** can learn Defog/Rapid Spin in Realidea; Skarmory and Latias cannot Defog here | ~80% engine fact, ~20% omission (forcing it reached 4/9) |
| "archetype coherence got worse, 9.2 → 11.0" | a regression I introduced | **random** archetype assignment scores 19.8; every version scores 9-11 | noise at n=9; all ≈2x chance |
| "more floors buy more variety" | obviously true | see §5 | **false** |
| "CHASE 0.7 gives curve MAD 46.7" | a cliff | a race in `boss_studio.py` — a browser tab regenerating concurrently corrupted the shared globals mid-build | measurement artefact; real value 5.4, now serialised behind a lock |

The general lesson, which cost the most: **a metric computed on nine teams needs its
null printed beside it**, or it will be read as signal. `boss_diagnostic.py` now prints
the baseline next to every rate it reports.

## 5. The sweep that set the default

`team_shape.CHASE` is the threshold: a role becomes a floor for an archetype when that
share of its teams carry one. Lower = more roles forced.

| CHASE | floors/fight | curve MAD | variety percentile |
|---|---|---|---|
| 0.6 | 6.0 | 7.3 BST | 0.0% |
| 0.7 | 4.6 | 5.4 | 1.3% |
| 0.8 | 3.1 | 3.4 | 1.4% |
| **0.90 (default)** | **1.6** | **1.9** | **8.3%** |
| off (>1.0) | 0.0 | 1.4 | 2.0% |

(Percentiles here are `boss_studio.py`'s 3,000-draw bootstrap; `boss_diagnostic.py` uses
4,000 and reports 8.4% for the default. The ±0.1 is the bootstrap, not a disagreement.)

More floors are strictly worse on **both** axes. Past roughly two per team they compete
for six slots, each gets satisfied by whatever in-band species happens to carry the role,
and the teams converge again — while the curve pays for the constraint the whole way.
Note that heavy floors are *worse than no floors at all* for variety. With n=9 and a
bootstrap percentile the exact peak at 0.90 should not be over-read; "a small number of
floors beats both extremes" is the durable claim.

## 6. Feasibility: what Realidea's dex will and will not build

From `boss_diagnostic.py --matrix` (nine fights x five archetypes, 45 teams):

| archetype | themes it is feasible on | curve cost |
|---|---|---|
| balance, bulky offense, offense, hyper offense | 9 of 9 | ≈0 |
| **stall** | **0 of 9** — 67% of floors met on Ground and Normal, 33% on the other seven | — |

**Stall is not buildable here.** It wants five of six sets carrying recovery; the dex
filtered to a 4/6 type theme and a BST band cannot supply it. Assign it anyway and the
fight silently comes out as a worse balance team. It stays in `team_shape.ARCHETYPES`
(336 corpus authors built one) and out of `generate_bosses.ARCHETYPE`.

The matrix also surfaced a **pre-existing** defect it had nothing to do with: gym 6
cannot reach its eBST target under any archetype (-11 to -28), and the old flat-quota
generator missed it by -13 too. Ground at target 583 is the hole; the fix is `TARGET[5]`,
the theme, or the band — see `BOSS-CURVE.md`, not this file.

## 7. Cores, and the hard limit on what co-occurrence can find

Mined against the gen7ou pool, cross-checked against a Smogon thread that used the same
data source (so: external ground truth, not self-confirmation). Both failure modes that
thread warned about reproduced exactly, and a balanced `lift x log(support)` metric
independently recovered its named rain, sun and stall cores.

Then the trio test:

| core | teams | lift³ | pairwise lifts |
|---|---|---|---|
| Chansey + Sableye + Skarmory | 58 | **171.5** | 8.1 – 12.6 |
| Landorus-T + Magearna + Rotom-W | 116 | 2.43 | 1.24 – 1.49 |
| Heatran + Scizor + Tapu Fini | 25 | 1.60 | 1.04 – 1.36 |

**Lift measures surprise, not quality.** The second and third rows are perfectly good
cores that appear on more teams than the first; they are statistically invisible because
they are assembled from ubiquitous staples. A core made of staples is silent *by
construction*.

Consequences, both load-bearing:

- Co-occurrence mining will find weather, stall and screens cores and will **never**
  find a standard balance core. Any "grow a team from a mined core" design works for the
  distinctive archetypes and produces nothing for the common case.
- `smogon_corpus.teammates()` has exactly this blind spot, and it is what
  `generate_bosses.MIN_CORR` runs on — see §8.

## 8. What the corpus does NOT feed

The most misread thing about this work. The scrape informs *which jobs a team must
cover*. It informs nothing about *which Pokémon or which sets the generator picks from*.

| decision | source | from the scrape? |
|---|---|---|
| which roles a fight must carry, and how many | `smogon-dump/` (54,522 teams) | **yes** |
| the variety metric and its null | `smogon-dump/` | **yes** |
| which species are eligible, and their tier | `smogon-formats/gen7-formats-data.ts` | no |
| every set: moves, EVs, nature, item | `smogon-sets/gen{6,7,8,9}.json` | no |
| `MIN_CORR`, the off-theme gate | `smogon-stats/gen7*.txt` usage files | no |

### MIN_CORR is a binary switch, not a dial

An off-theme slot must clear `MIN_CORR`% co-occurrence **or** resist a type the theme is
weak to. That `or` decides it:

| fight | off-theme candidates in band | admitted by correlation | admitted by resistance |
|---|---|---|---|
| gym 1 (Bug) | 387 | 7 | **208** |
| gym 5 (Dark) | 258 | 17 | **158** |
| gym 9 (Steel) | 106 | 10 | **89** |

~95% of eligibility arrives through the resistance path, which `MIN_CORR` does not
touch — so 10, 25, 50 and 80 all produce identical teams, and only 0 differs (it opens
the gate to everything). It also runs on raw co-occurrence from short top-N lists:
Heatran's partners are Venusaur-Mega 51.6%, Keldeo 46.8%, Bisharp 46.6%, Skarmory 46.6%,
Chansey 44.3%, then a cliff to 10.6%. Five species clear 25%, total. This is §7's blind
spot sitting in the generator's weakest input.

## 9. Where it stands, and what is still wrong

The archetype work reaches **variety 1.7th → 8.4th percentile at curve MAD 1.9 BST,
unchanged**, with the assignment read off the feasibility matrix rather than chosen by
flavour. But reviewing the actual rosters rather than the metrics: one fight clearly
better, two clearly worse, the rest lateral. **It has not been regenerated or injected**
— `generated/teams_bosses_gyms.json` still holds the flat-quota teams, which is what the
game runs.

The blocking defect is in the design of the floor, not its tuning:

> **A floor is satisfied by a move's NAME.** Calm Mind on a defensive cleric scores
> identically to Shell Smash on a sweeper. That is how gym 4 met `setup >= 3` while
> losing both its Light Clay screens lead — the actual hyper-offense signature, 24% of
> HO teams against 6% overall — and its mega evolution, on the fight where megas debut.

Two contained fixes: floors that test the **set** (setup counts only on a set with ≥50%
offensive EVs), and the mega floor ranked above the archetype floors so it stops losing
the slot race.

Independent of any of the above, and worth doing to the **shipped** teams regardless:

- **Teleport is a dead move in this engine.** Realidea's PBS gives it function code
  `0EA` — flee a *wild* battle; it fails outright in a trainer fight. U-turn and Volt
  Switch are `0EE`. Teleport only became a pivot move in gen 8. It sits in
  `team_shape.ROLE_MOVES["pivot"]`, so the generator counts it as filling the role, and
  it is on the Champion's ace in the team that is currently in the game.
- **A set's nature and EVs survive a moveset rebuild.** When level-legality strips most
  of a published set's moves, `build()` tops the moveset back up from `best_moves()` but
  keeps the original spread — producing a Modest Poliwrath whose four damaging moves are
  all physical. 2 of 54 sets in the archetype build, 0 of 54 in the shipped one.

## 10. Modes: what a team is *about*, and which types want it

§2's archetype axis says how six sets divide the work. It says nothing about the other
thing real teams are organised around — a **mode**: sun, rain, sand, snow, Trick Room,
screens, one set turning something on and the other five chosen to exploit it. The dump
can measure this the same way it measured archetype, and better, because a mode leaves
evidence in the team itself: `team_tags.agreement()` checks the author's tag against the
moves and abilities the team actually runs, and only tags that survive that are counted.

| mode | teams | setters/team | floor..cap | the types it over-represents |
|---|---|---|---|---|
| sun | 103 | 1.40 | 1..2 | Fire **3.1x**, Grass 2.4x, Poison 2.3x |
| rain | 141 | 1.23 | 1..2 | Water **2.9x**, Flying 1.9x, Grass 1.7x |
| sand | 171 | 1.02 | 1..2 | Rock **2.5x**, Ground 2.3x, Steel 1.9x |
| snow | 33 | 0.97 | 1..2 | Ice **5.7x**, Fire 2.0x, Water 1.5x |
| trick room | 89 | **2.65** | **2..4** | Psychic **2.2x**, Rock 2.0x, Normal 1.8x |
| screens | 109 | 1.05 | 1..2 | Electric **2.3x**, Fairy 1.7x |

Lift is P(type | mode teams) / P(type | all teams), over the ~83% of corpus sets whose
species exists in Realidea's dex. Dropping the rest costs nothing: a lift is a ratio and
the same rows leave both halves of it.

**Trick Room is the one that is not like the others.** Every weather mode runs about one
setter — a second Drought is a wasted slot — and TR runs 2.65, because the mode lasts
five turns and has to be re-set. That is the whole reason the floors are measured rather
than typed in: a single "how many setters does a mode want" constant would have been
wrong by a factor of nearly three on one of the six, and nothing in the flavour of the
mechanic makes that obvious. Weather's cap is clamped to 2 regardless.

**Counting setters by move alone gives the wrong answer.** A sand team's setter is
usually Sand Stream and not a Sandstorm move at all: counted over moves, sand's
setter_mean is **0.00**, which would floor a sand plan at one Sandstorm *user* and leave
the ability holder optional — exactly backwards. `reduce_mode` therefore counts through
`team_shape.roles_of()`, the same reader the generator uses, which reads the ability.

### Two caveats, one of them a correction

**Snow's n=33 is the thinnest column here** and carries the largest single lift in the
table (Ice 5.7x). The `MODE_MIN_N = 20` gate admits it; at 33 agreement-validated teams
the lift is real but the setter count is one rounding away from a different floor.
Planning notes for this work recorded snow at n=3 and excluded it as noise; that does not
reproduce against the current dump, and 33 is the measured figure.

**Sub-threshold lifts used to contribute to evidence, and it mattered.** The first
version of `fight_context.evidence()` added `type_lift[theme]` raw, whatever it was. A
lift under 1.0 means the mode carries *less* of that type than average — evidence
*against* — and it was being added in favour. The claim first written here, that it
"has never changed a proposal", was wrong: **it changed 21 of them across the 27
fights.** The signature is exact. A fight with a single on-type Pokemon scores exactly
1.0, so any theme term in the 0.7-1.1 range pushes it over the 1.5 threshold by itself:

> Aimi's **Fairy** gym proposed **rain** at 1.76 = one part-Water Marill (1.0) + 0.76
> for Fairy, a type rain teams carry *less* of than average. Nothing else on the team
> has anything to do with rain.

That is most of why rain and sand appeared nearly everywhere in the first derivation
(rain on 8 of 27 fights). The theme term is now held to the same `LIFT_MIN` bar a
Pokemon's own types are held to — `affinity()` had always used it, and `evidence()`
using a different bar for the same quantity was the bug. Modes clearing the threshold
across all 27 fights, before and after: sand 13 → 5, snow 18 → 11, rain 19 → 16,
sun 12 → 10, trick room 14 → 13, screens 1 → 1. Gym 2 now reads **trick room 4.6**
(all three kept mons are slow) and **screens 1.7** (Fairy genuinely is a screens type),
which is a description of Aimi's actual team rather than an artefact.

### What it changed

Nine gym fights and eighteen named ones can now be assigned a mode that their own
roster and 546 real mode teams argue for, rather than none at all because no vocabulary
existed. See `TEAM-DESIGN.md` §6.8 for the deriver, the evidence rule, and the two
places the mode had to be protected from the machinery that was already there.

Measured the same way §3 and §5 were — mean pairwise L1 distance between the nine gym
teams' role vectors against nine real teams, 4,000 draws, now over the widened
16-role vocabulary so the three columns below are comparable to each other and **not**
to §3's eleven-role figures:

| the nine gyms built as | all 16 roles | the roles it chases | curve MAD |
|---|---|---|---|
| flat `QUOTA` (what shipped) | 6.67 → **2.4%** | 1.06 → **0.0%** | 1.7 BST |
| archetype, no mode | 7.89 → 19.9% | 2.56 → 9.2% | 1.9 BST |
| archetype + mode, raw theme term | 9.61 → 76.8% | 3.22 → 42.2% | 3.1 BST |
| + theme term held to `LIFT_MIN` | **10.00 → 84.5%** | 3.22 → 42.2% | 3.1 BST |
| **+ synergy gate (§11)** | 8.89 → **53.2%** | 2.78 → 18.0% | 3.8 BST |

The last row is a **trade, not a free win, and the earlier draft of it was wrong** — it
was measured off a stale `teams_bosses_gyms.json` (`generate_bosses.py` only writes with
`--json`, so a run without it prints and discards). Making the modes real costs variety:
three of the nine gyms lose their mode entirely, and **five of the six that keep one get
`trickroom`**. That is §3 running forwards again — told the same thing they converge —
and it is now the largest open question here, not the gate itself.

This is the first version where the answer to §3's question is yes: nine generated gym
leaders are now as unalike as nine teams drawn at random from the corpus, and the half
the generator is explicitly told to fill — which was the half convicted in §3, at the
0.0th percentile — is no longer distinguishable from chance either.

The mechanism is not subtle, and it is the same one §3 identified working in the other
direction. Told the same thing nine times, the teams converged; told nine *different*
things, they diverge. What §5 established is that you cannot buy this with more floors
of the same kind — past ~2 per fight they compete for six slots and the teams converge
again. A mode is a different kind: it adds one floor and changes what every *other*
slot is ranked for.

The cost is 1.2 BST of curve accuracy (MAD 1.9 → 3.1), which is the mode floor taking a
slot the deficit would otherwise have chosen. Gym 6 remains −11 and remains unfixable
here (§6). Nothing about the 76.8% should be over-read at n=9 and one bootstrap; the
durable claim is the ordering of the three rows, which is monotone on both variety
columns and reproduces the §5 finding that the curve pays for every constraint.

## 11. A mode is a setter AND abusers

§10 gave a mode a setter floor and stopped. That was not what a mode team is, and the
corpus is unambiguous about it.

### The composition rule, measured

| mode | n | setters/team | abusers/team | ≥1 payoff | on-plan sets /6 |
|---|---|---|---|---|---|
| rain | 141 | 1.23 | 1.28 ability, 3.41 move | **100%** | 3.53 |
| sun | 103 | 1.40 | 1.22 / 2.82 | **100%** | 2.93 |
| snow | 33 | 1.03 | 0.94 / 2.03 | 97% | 2.06 |
| sand | 171 | 1.02 | 1.01 / 1.08 | 97% | 1.77 |

**141 of 141 rain teams carry an abuser ability or a rain-boosted attack. None carry
neither.** The 31 with no Swift Swim run Thunder, Hurricane or Hydro Pump instead —
26 of the 31 run Thunder. Trick Room runs 2.65 setters (it lasts five turns) and its
payoff is slow mons: 33% of its resolvable sets are ≤50 base speed against a 22%
baseline, a 1.53× lift. Screens is the tightest rule in the corpus — 1.05 screen users,
**94% put both screens on one mon**, and 99% carry at least one setup set to spend them.

Sand is the one to remember: 1.77 on-plan sets of six, lowest of the four, because sand
boosts no attacks. Its payoff is Sand Rush and the Rock special-defence boost, so a sand
team legitimately looks less themed than a rain team.

### Payoff moves are derived, and sand is the control

`P(move | mode teams) / P(move | all teams)`, setter moves excluded, ≥8 sets on ≥3
distinct species:

```
rain    WEATHERBALL 15.9x  LIQUIDATION 9.1x  THUNDER 7.0x  WATERFALL 6.8x
        HURRICANE 6.5x (14% of its sets)  FLIPTURN 5.4x  SURF 5.2x
sun     GROWTH 57.5x  WEATHERBALL 33.2x  SOLARBEAM 23.3x  ERUPTION 8.4x
snow    AURORAVEIL 43.8x  BLIZZARD 31.6x  FREEZEDRY 19.5x
sand    nothing above 4.31x
```

A hand-written rain list would have named Scald and Hydro Pump, which the lift does not
support, and missed Weather Ball and Flip Turn. `PAYOFF_LIFT = 5.0` is set by sand
rather than by taste: sand has no move payoff, its highest surviving lift is 4.31x, and
any threshold at or under that invents one. The ≥3-species rule is what removes one
popular Pokémon wearing a lift — Bolt Beak is 129× on snow and is a single Dracovish.

Trick Room and screens get **no** payoff table. They boost no move; running the same
derivation on them returns their staple mons' incidental moves (Magic Coat 21×, Memento
9×). Their payoff is slow base speed and setup, which `affinity()` already reads.

### Three abuser abilities were in the table by assumption

Counted over the validated teams: **Sand Veil 5 uses of 172** sand abusers, **Snow Cloak
0 of 31**, **Leaf Guard 0 of 126** sun abusers. Sand Rush alone is 95% of sand. The two
evasion abilities are the ones that mattered — listing an ability is what lets the
builder reassign a species onto it, so an unused one is not harmless, it is an
instruction to go and find it. A boss handed Sand Veil is a boss the player misses one
attack in five against, for no counterplay, and nobody builds sand that way either.

### Weather is set by an ability, and it leads

| mode | ability setter | move setter | who |
|---|---|---|---|
| sand | **100%** | 0% | Tyranitar 95 + Mega 22, Hippowdon 44 |
| snow | 91% | 6% | Ninetales-Alola 22 of 33 |
| rain | 82% | 15% | **Pelipper 110 of 141** |
| sun | 60% | 30% | Torkoal 34, Jumbao 12, Groudon 9 |

Slot occupancy is uniform 17%, so anything above it is signal — validated on Sticky Web
(52% at slot 0) and Focus Sash (35%), with Stealth Rock at 16% as the control that says
the ordering is not just noise. **Ability setters lead: snow 62%, rain 58%, sun 53%,
sand 30%.** Move setters do not — rain 20%, sun 32%, i.e. flat. Drizzle fires on
switch-in, so leading with it means never spending a turn on weather.

### What Realidea can field

Thirteen weather-ability holders in the entire dex. **Pelipper and Torkoal are in the
game without their weather abilities** — its PBS is gen-6 era, and Drizzle-Pelipper and
Drought-Torkoal are gen-7 changes. Kyogre and Groudon (670) are above every band ceiling
in the game. Band coverage across the 27 fights: **sand 27, snow 18, sun 10, rain 10** —
and from gym 7 on (band 550+) sand is the only weather with a setter, because Tyranitar
is the only holder that fits.

### A fourth ability was in the table because the *engine* cannot read it

The three above were removed on corpus evidence. **Slush Rush was removed on engine
evidence, and it points the other way**: the corpus loves it — **29 of 31 snow abusers**
— but Realidea never reads it. `PokeBattle_Battler#pbSpeed` branches on
RAINDANCE/HEAVYRAIN (Swift Swim), SUNNYDAY/HARSHSUN (Chlorophyll) and SANDSTORM (Sand
Rush), and has **no HAIL branch at all**; `SLUSHRUSH` appears nowhere else in the 336
decompiled scripts.

That is a corpus-vs-engine split worth naming, because every other rule in this document
is derived from the corpus alone. Leaving Slush Rush listed would have let a snow plan
clear its abuser floor with an ability that does nothing — the same un-abused "rain team"
the synergy gate was built to stop, arriving through a door the corpus could not see.

It came out of an audit of all 241 ability names against all 336 scripts: **sixteen have
no handler**, and ten species *lead* with one of them (Solgaleo, Lunala, Necrozma, the
four Tapus, Alolan Raichu, and two fakemon). Those ten are excluded from generation
outright — see TEAM-DESIGN §6.8. Realidea is a **gen-6 engine carrying a gen-7 dex**, and
this is what that costs.

Snow's remaining payoff on this engine: Ice Body (passive healing, not a wincon), Aurora
Veil (**0 species learn it here**), and Blizzard, which gets no hail accuracy exemption —
the weather damage block only scales Fire and Water, in rain and sun. **Snow is a mode
this engine can barely express.**

### Other modes the corpus has and this generator does not

Eleven mode/weather tags are scraped; six are modelled. Of the rest:

| tag | titled | agrees | buildable in Realidea |
|---|---|---|---|
| **spikes** | 193 | 193 | yes — Stealth Rock 151 species, Toxic Spikes 18, Spikes 9 |
| spam | 189 | untestable | it is type stacking, which `THEME` already does |
| **webs** | 160 | 159 | **no — 0 species learn Sticky Web** |
| **para** | 44 | 43 | yes — Thunder Wave on 204 species |
| baton pass | 4 | 4 | 31 species, but n=4 is below any threshold |

`spikes` is the largest tag in the corpus and its setter is already a job role
(`hazards`); `para` has the same shape as screens — buy speed control, cash it with
setup. Both are additions rather than fixes. Note also that **0 Realidea species learn
Aurora Veil**, so the screens mode is Reflect and Light Screen only.
