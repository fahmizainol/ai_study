# What Monotype Teams Do About The Weakness Their Theme Hands Them

A Water team is weak to Grass and Electric before it picks a single Pokémon. Companion
to `TEAM-CORPUS.md`, which asks whether a generated team looks like a team someone would
build; this asks a narrower question that monotype is the only tier able to answer
cleanly, because the theme fixes the weakness list in advance and every team faces the
same one.

Regenerate everything below with:

    python3 tools/mono_synergy.py --gen 6 7 8 9        # the whole report, both halves
    python3 tools/mono_synergy.py --theme Water        # one theme, naming the answers
    python3 -m unittest tests.test_tooling.MonoSynergyTypeMathTest

The dex, the forme a set will actually play as, generation inference, the multipliers and
the null draws live in `tools/type_model.py`, shared with `tools/archetype_coverage.py` —
the same question asked of normal teams, where the weakness list comes from the six picks
instead of from a theme (`TEAM-CORPUS.md` §12). Any refactor of that module should be
checked by re-running this report to byte-identical output, which is how the extraction was
proved.

Type, ability and item facts come from the `pokemon-showdown` checkout via
`tools/dump_showdown_dex.js` (cached in `generated/showdown_dex.json`, gitignored like
any build product of that clone), **not** from `tools/realidea_data.py`: that PBS is one
gen-6-era 16-type dex with a fangame's own edits, and this corpus spans gens 6-9.

## 1. The answer, in one paragraph

Monotype builders cover the weaknesses that *can* be covered, aggressively and with a
dedicated slot — and simply eat the rest. Team-weighted over 51 theme-weakness pairs in
gen 9, **31% of pairs have at least one member that resists or is immune, 61% have
nothing better than a neutral body, and 8% have no switch-in at all** (every member
takes ×2 or worse). The mean team has **4.18 of its 6 members still weak** to any given
theme weakness. Where coverage exists it is deliberate: 12 of 51 pairs beat a
random-legal-species null, 9 of 51 beat a null that holds species popularity fixed, and
the shape is stable across four generations (resist 28/30/30/31% in gens 6/7/8/9). Where it does not exist, that is usually
not a choice — **for 32 of the 51 pairs no second type can help at all.**

So the premise in the question ("Water teams are weak to Grass and Electric, do they
carry Water/Ground or Sap Sipper") is right about the mechanism and half right about the
scope: Electric is answered almost universally, Grass is barely answered at all, and the
reason is structural rather than a lapse in team-building.

## 2. Why a resist is never an answer, and every typing answer is an immunity

A monotype member always carries the theme type, so its multiplier against the theme's
weakness is `2 × m(atk → second type)`, and the chart only ever contributes 2, 1, 0.5 or
0. To land under ×1 the second factor must be **0**. A second type that merely resists
brings ×2 back to ×1 and nothing more.

This is read off the chart each run (`typing_answer_possible`), not asserted:

| | |
|---|---|
| theme-weakness pairs, 18 themes | 51 |
| answerable by a second type — i.e. some type is immune to the attacker | **19** |
| not answerable by any typing | **32** |

The 32 are exactly the pairs whose attacking type nothing is immune to: **Bug, Dark,
Fairy, Fire, Flying, Grass, Ice, Rock, Steel, Water**. Only eight attacking types have a
type immunity (Normal and Fighting → Ghost, Poison → Steel, Ground → Flying, Ghost →
Normal, Psychic → Dark, Dragon → Fairy, Electric → Ground), and those eight are where
every typing answer in the corpus comes from. `Water/Grass` Ludicolo does not resist
Grass; `Water/Ground` Gastrodon *is immune* to Electric. Four more pairs are answerable
on paper but not in the dex — gen 9 has no Dragon/Fairy, Grass/Steel, Poison/Flying or
Rock/Ghost, so Dragon/Dragon, Grass/Poison, Poison/Ground and Rock/Fighting have to be
solved by ability or item too.

One exception the corpus found rather than the chart: **a Mega that loses the theme type
escapes the theme's weaknesses outright.** Mega Aggron is Steel/Rock → pure Steel, so on
a gen 6 Rock team it resists Grass and Steel while its five teammates do not. Eight
answer slots across four teams; it is the only case where a member is not paying the
theme's ×2.

## 3. Per theme, gen 9 (n = 1,431 teams)

`res%` share of teams with ≥1 member under ×1 · `neu%` best is exactly ×1 · `no%` every
member ≥×2 · `pool%` random legal species of that theme · `team%` that theme's own
species at their observed frequency, co-occurrence destroyed · `=1%` teams with exactly
one answer.

| theme | n | weak to | res% | mean | neu% | no% | pool% | team% | =1% (null) | answered by |
|---|--:|---|--:|--:|--:|--:|--:|--:|--:|---|
| Water | 122 | Electric | **93** | 0.94 | 6 | 1 | 33 | 70 | 93 (47) | type2 98, ability 2 |
| Water | 122 | Grass | 2 | 0.02 | 98 | 0 | — | 2 | 2 (2) | ability 100 · *no typing answer* |
| Flying | 98 | Electric | **100** | 1.34 | 0 | 0 | 19 | 86 | 68 (43) | type2 80, ability 20 |
| Flying | 98 | Ice / Rock | 0 | 0.00 | 100 / 99 | 0 / 1 | — | 0 | — | *no typing answer* |
| Steel | 88 | Ground | **98** | 2.08 | 1 | 1 | 19 | 94 | 25 (26) | item 54, type2 39, ability 7 |
| Steel | 88 | Fighting | **91** | 0.91 | 9 | 0 | 12 | 72 | 91 (72) | type2 100 |
| Steel | 88 | Fire | 76 | 0.76 | 17 | 7 | — | 66 | 76 (66) | ability 100 · *no typing answer* |
| Electric | 62 | Ground | **97** | 2.08 | 0 | 3 | 45 | 95 | 18 (25) | type2 49, ability 40, item 12 |
| Poison | 79 | Psychic | **97** | 1.04 | 3 | 0 | 43 | 74 | 91 (51) | type2 100 |
| Poison | 79 | Ground | **90** | 1.25 | 8 | 3 | — | 80 | 59 (43) | ability 53, item 47 |
| Fairy | 71 | Poison | **96** | 1.13 | 4 | 0 | 54 | 84 | 79 (54) | type2 100 |
| Fairy | 71 | Steel | 0 | 0.00 | 100 | 0 | — | 0 | — | *no typing answer* |
| Ground | 102 | Water | **92** | 0.96 | 4 | 4 | — | 70 | 88 (60) | ability 100 |
| Ground | 102 | Ice | 51 | 0.51 | 47 | 2 | — | 48 | 51 (48) | ability 100 |
| Ground | 102 | Grass | 0 | 0.00 | 100 | 0 | — | 0 | — | *no typing answer* |
| Fire | 73 | Ground | **89** | 1.10 | 11 | 0 | 39 | 75 | 68 (45) | type2 44, item 44, ability 12 |
| Fire | 73 | Water | 41 | 0.41 | 53 | 5 | — | 40 | 41 (40) | ability 100 |
| Fire | 73 | Rock | 0 | 0.00 | 68 | **32** | — | 0 | — | *no typing answer* |
| Normal | 52 | Fighting | **83** | 0.92 | 15 | 2 | 12 | 70 | 73 (59) | type2 88, ability 12 |
| Rock | 43 | Ground | 67 | 0.72 | 30 | 2 | **62** | 57 | 63 (45) | item 90, type2 10 |
| Dark | 128 | Fighting | 52 | 0.52 | 45 | 3 | 18 | 48 | 52 (47) | type2 100 |
| Dark | 128 | Bug / Fairy | 0 | 0.00 | 99 / 84 | 1 / 16 | — | 0 | — | *no typing answer* |
| Psychic | 81 | Ghost | 48 | 0.49 | 42 | 10 | 38 | 46 | 47 (41) | type2 100 |
| Bug | 51 | Fire | 47 | 0.47 | 49 | 4 | — | 50 | 47 (50) | ability 100 |
| Fighting | 85 | Psychic | 36 | 0.36 | 35 | **28** | 25 | 39 | 36 (34) | type2 100 |
| Ghost | 78 | Ghost | 35 | 0.35 | 14 | **51** | 18 | 38 | 35 (38) | type2 100 |
| Ice | 51 | Fighting | 27 | 0.27 | 63 | 10 | 13 | 29 | 27 (29) | type2 100 |
| Ice | 51 | Rock / Steel | 0 | 0.00 | 69 / 71 | **31 / 29** | — | 0 | — | *no typing answer* |
| Dragon | 116 | Ice / Fairy / Dragon | 0 | 0.00 | 100 / 96 / 85 | 0 / 4 / 15 | — | 0 | — | *no typing answer* |
| Grass | 51 | Flying | 0 | 0.00 | 45 | **55** | — | 0 | — | *no typing answer* |
| Grass | 51 | Ice | 0 | 0.00 | 61 | **39** | — | 0 | — | *no typing answer* |

**Worst off:** Grass vs Flying (55% of teams have no switch-in at all), Ghost vs Ghost
(51%), Grass vs Ice (39%), Fire vs Rock (32%), Ice vs Rock (31%) and Ice vs Steel (29%).
Dragon and Grass are the themes with nothing to click: Dragon resists none of Ice, Fairy
or Dragon on any member in any of 116 teams.

### One team, derived

    python3 tools/mono_synergy.py --gen 9 --theme Water --example

picks the team closest to its theme's own means and walks both halves member by member. The
gen 9 Water pick is an SV sample team — Kingdra, **Swampert**, Ogerpon-Wellspring, Pelipper,
Primarina, Urshifu-Rapid-Strike:

| weak to | resist | neutral | weak | hits it back |
|---|--:|--:|--:|--:|
| Electric | 1 (Swampert, ×0) | 2 | 3 (Pelipper ×4) | 1 — Swampert's Earthquake |
| Grass | 0 | 3 | 3 (**Swampert ×4**) | 3 — Hurricane, Ice Beam, Ice Spinner |

Every result in this document is visible in those two rows. Swampert is the designated
Electric slot (§4) and the *only* member that threatens Electric back, so it is the two-way
answer of §8; it is also the member that is ×4 to Grass, which is §6's cost; and the Grass row
has no resist at all because nothing is immune to Grass (§2), so three neutral bodies and Ice
coverage are the whole plan.

The same command on `--theme Ice` and `--theme Ground` shows the two extremes. The Ice team
resists **nothing** across all four of its weaknesses — 6 of 6 members weak to Rock, Alolan
Ninetales ×4 to Steel — while hitting all four back with 1-4 members, and it runs the §7 snow
package (Snow Warning, Aurora Veil, Light Clay, Slush Rush Cetitan). The Ground team is the
mirror: Clodsire's Water Absorb walls Water outright and **no member can hit Water back at
all**, which is §8's one real blind spot (only 41% of Ground teams can).

## 4. The answer is a designated slot, not redundancy

Ten pairs in gen 9 cover *more* than the co-occurrence null **and** with a tighter
spread — the signature of a slot reserved for the job rather than luck of the draw:

| pair | res% (null) | exactly one answer (null) | variance (null) | p |
|---|--:|--:|--:|--:|
| Water vs Electric | 93 (69) | **93 (47)** | 0.07 (0.62) | 0.0000 |
| Poison vs Psychic | 97 (75) | 91 (53) | 0.09 (0.54) | 0.0000 |
| Ground vs Water | 92 (70) | 88 (61) | 0.12 (0.36) | 0.0000 |
| Steel vs Fighting | 91 (72) | 91 (72) | 0.08 (0.20) | 0.0001 |
| Flying vs Electric | 100 (85) | 68 (44) | 0.26 (0.73) | 0.0000 |
| Fairy vs Poison | 96 (83) | 79 (57) | 0.20 (0.47) | 0.0040 |
| Fire vs Ground | 89 (75) | 68 (45) | 0.31 (0.73) | 0.0074 |
| Steel vs Fire | 76 (65) | 76 (65) | 0.18 (0.23) | 0.0296 |
| Poison vs Ground | 90 (81) | 59 (44) | 0.49 (0.80) | 0.0421 |

All nine hold across five different null seeds. A tenth, Normal vs Fighting, appears in
three of five and is not counted.

Water vs Electric is the clearest: **93% of teams carry exactly one** Electric answer
where the null — same species, same frequencies, only the pairings shuffled — manages
one in 47% and lands on zero or two the rest of the time. Five of the nine survive
Bonferroni at α = 0.05/51.

The two exceptions run the other way and are just as informative. **Electric vs Ground
and Steel vs Ground carry a mean of 2.1 answers** and are the only pairs where redundancy
is the norm (exactly-one is 18% and 25%) — Ground is the attacking type those themes
cannot afford to lose to, and they stack Levitate, Air Balloon and a Flying secondary
together. And **Rock vs Ground is the one pair where real teams do *worse* than a random
legal draw** (7% typing coverage against the pool's 62%, p < 0.0001): the pool is full of
Ground-immune Rock/Flying, and real teams skip them and hang an **Air Balloon** on
something else instead (90% of their answers). Gen 7 shows the same inversion for Rock
vs Ground and for Steel vs Fighting.

## 5. What provides the answer, and is it built to switch in

Every answer slot in the corpus, by mechanism:

| gen | slots | type immunity | ability | item | carries recovery | a pivot move | removal |
|---|--:|--:|--:|--:|--:|--:|--:|
| 6 | 437 | 59% (+3% mega) | 31% | 7% | 46% | 12% | 7% |
| 7 | 1,429 | 57% | 33% | 10% | 48% | 17% | 10% |
| 8 | 831 | 57% | 37% | 6% | 56% | 19% | 10% |
| 9 | 1,514 | 56% | 29% | **15%** | 52% | 14% | 9% |

Abilities do a third of the work, and the corpus uses the ones the question named:
Levitate 1,207 sets, Water Absorb 490, Thick Fat 423, Flash Fire 345, Volt Absorb 237,
Storm Drain 204, Water Bubble 85, Lightning Rod 63, **Sap Sipper 57**, Earth Eater 20.
Defensive items are 1,019 slots, and 559 of them are one item: **Air Balloon**, followed
by Colbur 170, Shuca 60, Babiri 57, Chople 42.

On "for pivoting": the answers are built to *come in and stay*, not to pivot out. About
half carry recovery — for gen 9 Water vs Electric, 79% do — but only 12-19% carry
U-turn, Volt Switch, Flip Turn, Teleport or Parting Shot, and under 11% carry hazard
removal. The designated answer is a wall or a regenerator, not a pivot.

## 6. The cover deepens the other hole

The type that grants the immunity brings its own weaknesses, and they often land on
another of the theme's weaknesses:

- **98% of gen 9 Water teams that answer Electric do it with a member that is ×4 to
  Grass** (112 of 114). Gastrodon is immune to Electric *because* it is Water/Ground, and
  Water/Ground is double weak to Grass — the answer to one of the theme's two weaknesses
  is the worst case of the other.
- Across the whole corpus, a member that answers a weakness is **×4 to another theme
  weakness 33% of the time (4,211 slots), against 23% for the other 63,931.**
- Same shape elsewhere: Flying answers Electric with Ground and goes ×4 to Ice (105
  slots), Steel answers Fire and goes ×4 to Ground (67), Fire answers Ground and goes ×4
  to Rock (35), Fighting answers Psychic and goes ×4 to Fairy (31).

## 7. When nothing can be bought, a theme buys untyped defence instead

Ranked by the share of its own weakness list it answers, gen 9:

| best | | worst | |
|---|--:|---|--:|
| Electric (1 weakness, 1 answerable) | 97% | Dragon (3, 1) | **0%** |
| Poison (2, 2) | 94% | Grass (5, 1) | 1% |
| Steel (3, 2) | 88% | **Ice (4, 1)** | **8%** |
| Normal (1, 1) | 83% | Fighting (3, 1) | 12% |
| Fairy / Ground / Water | 48% | Rock (5, 2) | 13% |

**Ice is the clean case of a theme with nothing to click.** Over all 183 Ice teams in the
corpus, gens 6 through 9: **not one has a single member that resists Rock, and not one
resists Steel.** Fighting is answered only by Ice/Ghost Froslass (27% of gen 9 teams,
against a 13% pool null, p = 0.002) and Fire only by Water/Ice with Thick Fat, 15 teams in
183. Alolan Sandslash is the one member neutral to both Rock and Steel and pays ×4 to Fire
*and* ×4 to Fighting for it.

What Ice does instead is buy a **damage multiplier that has no type at all**:

| gen | n | Snow Warning | Aurora Veil | Slush Rush / Ice Body | Icy Rock | all three |
|---|--:|--:|--:|--:|--:|--:|
| 7 | 67 | 91% | 88% | 48% | 10% | 43% |
| 8 | 55 | 80% | 73% | 29% | 7% | 16% |
| 9 | 51 | **94%** | **84%** | 59% | 31% | 45% |

Aurora Veil on the other 17 gen 9 themes: **1%**. Veil halves damage from everything,
including the Rock and Steel moves no Ice typing can touch, and in gen 9 snow adds +50%
Defence to Ice types on top — so the substitute for a resist is a blanket, and it is
bought by nearly every team rather than by a slot. It is not a gen 9 invention: 88% of gen
7 Ice teams already ran the veil.

### It does not generalise, and popularity does not follow it either

The section title above is an overgeneralisation from Ice, and testing it across all
eighteen themes says so. Auto-weather uptake against the theme's own defensive resist rate,
gens 6-9 pooled (1 auto-setter ability anywhere on the team):

| theme | resist rate | weather | | theme | resist rate | weather |
|---|--:|--:|---|---|--:|--:|
| Ice | 8% | **89%** | | Grass | 1% | 10% |
| Rock | 13% | **85%** | | Dragon | 0% | **0%** |
| Fire | 43% | 76% | | Fighting | 12% | **0%** |
| Ground | 48% | 47% | | Psychic | 16% | **0%** |
| Dark | 17% | 42% | | Ghost | 17% | **0%** |
| Water | 48% | 36% | | Bug | 16% | **0%** |
| Flying | 33% | 25% | | Steel / Poison / Electric / Normal | 83-97% | **0%** |

**Spearman = −0.05.** "Themes that cannot resist buy a blanket instead" is true of Ice and
Rock and false of Bug, Dragon, Fighting, Ghost and Psychic, which resist 0-17% of their
weaknesses and run no weather at all. What actually explains the column is **availability**:
every theme at 0% is one with no auto-setter of its own type, and every theme above 0% has
one (Ninetales-Alola, Tyranitar, Torkoal, Hippowdon, Pelipper, Politoed, Abomasnow). Uptake
then ranges 4-89% and is highest where the theme has nothing else, but Grass at 10% and
Fairy at 4% have setters and decline them. So Ice's snow package is real and the mechanism
class is real; the *rule* is not.

**Popularity does not follow weather either** — the hypothesis is worth recording because it
is the obvious one. Ranked by teams posted, gens 6-9 pooled: Water 391, Flying 317, Psychic
313, Dark 286, Steel 284, Ground 261, Dragon 252, Ghost 214, Fairy 207, Fighting 202, Fire
187, Ice 183, Bug/Normal/Poison 180, Electric 165, Grass 153, Rock 137. Spearman against
auto-weather share is **−0.06**: the three themes that run weather on more than half their
teams (Ice, Rock, Fire) average 169 teams where the other fifteen average 239, and the two
most posted themes run it on 36% and 25%. Nothing else measured predicts it either — number
of weaknesses +0.01, resist rate +0.10, legal species available +0.19, all at n=18 themes.
And the ranking is **not stable**: Psychic leads gen 6 and leaves the top five by gen 9, Dark
arrives at number one in gen 9, and only Water is top-two in all four generations. Whatever
drives it is metagame-specific and outside this corpus — and note the proxy is **teams posted
to a forum, not ladder usage**, which no vendored file covers.

**This is a limit of everything above, not a footnote.** Every number in §3-§6 is a type
multiplier, so screens, weather, terrain, bulk and Regenerator are all invisible to it. An
8% coverage score and a 94% weather package are both true of the same 51 teams. Where a
theme lands on the §3 table says what its *typing* can do; it does not say the team has no
plan.

## 8. The offensive half: they can nearly always hit back, and it costs them nothing

A theme's weakness list doubles as its **threat list** — in this tier the Grass attacks
that hit a Water team come from a Grass *team* — so the same 51 pairs can be asked the
other question. Effectiveness is measured against the **real member population** of the
threatening theme, weighted by how often each body appears, not against the bare type:
"Ice Beam is super effective on Grass" is true of a pure Grass body and false of
Ferrothorn.

| | defence | offence |
|---|--:|--:|
| pairs where ≥1 member handles the threat (gen 9, team-weighted) | **31%** | **91%** |
| share of the threat's real bodies hit for ×2 | — | **92%** |
| share reachable at neutral or better | — | **100%** |
| mean members contributing | 0.38 of 6 | 1.0-4.7 of 6 |
| pairs beating the co-occurrence null | 9 of 51 | **0-5 of 51** |

**The null is the point.** Defensive coverage beats a shuffled team because it needs a
particular species, so it becomes a reserved slot (§4). Offensive coverage does not beat
the shuffle in any generation, because a coverage move costs one of four slots on *any*
member — it is bought everywhere at once, by 2 to 5 members of a six-mon team, and
shuffling cannot break it. Stable across gens: 92/92/90/91% in gens 6/7/8/9.

Four shuffles of each pool make the difference concrete. Water resisting Electric scatters
— 0, 1, 2, 1 answers, because the answer is three species out of the whole pool — while
real teams put **113 of 122 on exactly one**. Ice hitting Steel comes out 5, 2, 2, 3: every
shuffle works, and real teams span the same 2-to-5 range. **You cannot draw an Ice team that
fails to hit Steel**, which is why 100% there is not evidence of anything.

**A null-equal result does not mean the choice was not deliberate**, and reading it that way
is the trap this design invites. Earthquake on Mamoswine is a deliberate pick; it is in the
null because *every* Ice team makes it. The null preserves which species are popular and
which sets they run, and destroys only which sets were put together — so it is blind by
construction to any decision the whole metagame makes identically, and can only detect
coordination BETWEEN slots. "Coverage is so universal that composition is irrelevant to it"
is the claim §8 supports; "Ice players do not think about Steel" is not.

**35 of the 51 pairs have the theme's own STAB resisted or nullified by the type attacking
it**, and that is where coverage stops being optional. In essentially every one of them,
~100% of teams carry an off-type move anyway:

| theme | threat | own STAB | teams with SE coverage | real bodies hit | by STAB alone | coverage used |
|---|---|--:|--:|--:|--:|---|
| **Ice** | **Steel** | **×0.5** | **100%** | **84%** | **0%** | Ground 65, Fighting 34 |
| Ice | Fire | ×0.5 | 100% | 93% | 0% | Ground 63, Rock 22, Water 15 |
| Water | Grass | ×0.5 | 100% | 99% | 0% | Ice 39, Poison 26, Bug 18 |
| Electric | Ground | **×0** | 100% | 94% | 0% | Ice 45, Water 37, Grass 17 |
| Fire | Rock | ×0.5 | 100% | 92% | 0% | Grass 34, Ground 30, Fighting 26 |
| Flying | Rock | ×0.5 | 100% | 99% | 0% | Ground 43, Fighting 34, Steel 15 |
| Steel | Fire | ×0.5 | 98% | 95% | 0% | Ground 67, Rock 28 |
| Dragon | Fairy | **×0** | **77%** | 89% | 0% | Steel 81, Poison 19 |

So the Ice/Steel case is emphatic: **Ice cannot resist Steel on a single team in 183, and
every single team can hit Steel super-effectively** — Earthquake and High Horsepower on 65%
of the coverage slots, Close Combat and Low Kick on 34%.

**The blind spots are few and they are offensive, not defensive.** Threats that over a
quarter of gen 9 teams cannot hit super-effectively at all:

| pair | teams with SE coverage | and defensively |
|---|--:|---|
| Ground vs Water | **41%** (15-30% in gens 7-8) | 92% resist — walls it, cannot kill it |
| Dark vs Bug | 51% | 0% resist |
| Steel vs Fighting | 65% | 91% resist |
| Steel vs Ground | 73% | 98% resist |
| **Dragon vs Fairy** | **77%** | **0% resist**, and STAB is ×0 |

Dragon vs Fairy is the worst matchup in the tier on both axes at once: Fairy is immune to
Dragon's STAB, no Dragon body resists Fairy, and roughly a quarter of Dragon teams have no
super-effective answer either.

### One mon doing both jobs

The strongest form of the question is whether the member that walls the threat can also
threaten it. Over all 51 gen 9 pairs: resist 30%, hit 92% of pairs-weighted-equally,
**both on the same member 14%**,
and **31 of 51 pairs have no two-way answer on any team**. Where it does happen, the
measurement names the tier's famous answers without being told about them:

| pair | two-way | who |
|---|--:|---|
| Poison vs Psychic | 96% | Muk-Alola 66%, Overqwil 18%, Skuntank 9% |
| Water vs Electric | 89% | Swampert 38%, Gastrodon 29%, Quagsire 20% |
| Flying vs Electric | 84% | Landorus 53%, Gliscor 51% |
| Electric vs Ground | 77% | Rotom-Wash 71% |
| Steel vs Fire | 75% | Heatran 75% |
| Bug vs Fire | 47% | Araquanid 47% |
| Rock vs Ground | 44% | Drednaw 35%, Glimmora 12% |

Swampert is not just the Electric-immune slot from §4; it is the Electric-immune slot that
clicks Earthquake. That is why one slot is enough for 93% of Water teams.

## 9. Tera is not the coverage tool it looks like

Gen 9 sets record a Tera type on 13,306 of 28,749 sets, and on the face of it Tera
rescues the uncoverable pairs: 36% of teams facing a weakness nothing resists hold a Tera
that *would* resist it — 65% of Water teams against Grass, 86% of Dragon teams against
Ice.

**Almost none of it is a defensive choice.** Only **4%** is an off-type Tera, i.e. a type
the set does not already have. The rest is the set's own STAB — Toxapex going Tera Poison
resists Grass as a side effect of an offensive click (73 of the 122 Water teams), Ogerpon-
Hearthflame's Tera Fire against Ice, Rotom-Wash's Tera Electric. Counting "the Tera
resists it" as coverage would have turned an offensive habit into a defensive plan.
`Tera Stellar` is excluded outright (31 sets): it does not change the holder's types.

## 10. Corpus, and two files whose names lie

4,092 usable teams from 5,109 scraped records. A team is usable when all six species
resolve, all six share exactly one type, and one generation's dex can hold the whole
team.

| | |
|---|---|
| scraped records | 5,109 |
| not six Pokémon | 241 |
| species unresolved (author lines parsed as a Pokémon) | 124 |
| no single shared type | 55 |
| no legal generation — see below | 721 |
| **usable** | **4,092** (gen 6: 452, gen 7: 1,390, gen 8: 819, gen 9: 1,431) |

All 18 themes appear in all four generations, 10-157 teams per theme-generation.

**`gen6monotype.json` is not monotype.** Its 30 teams are one "Any Ability" OM thread
the scraper filed under the wrong tier — Barraskewda and Zapdos-Galar on a supposed gen 6
list — and 30 of 30 have no type shared by all six members. Excluded by name so the
exclusion is visible. Every gen 6 team counted above comes from the file below.

**`gen9monotype.json` is not gen 9.** It is the monotype subforum's whole history: posts
dated from 2014-03, 1,827 teams holding a mega stone, and 2,428 of 4,337 containing a
species that does not exist in gen 9. Taking the filename at face value would have
scored gen 6 and gen 7 teams against the gen 9 dex and reported **Mega Swampert as a gen
9 Water answer** — which is how the first run of this analysis read. So the generation is
inferred per team: the post date leads, and legality only vetoes. The date has to lead
because megas survived into gen 7, so "latest generation everything is legal in" would
file the entire gen 6 era as gen 7. 334 of 4,092 teams are dated outside the generation
they are legal in and take the veto.

The 721 with no legal generation are mostly **National Dex monotype** — a mega stone
beside a post-gen-7 species, or gen 8+ items like Heavy-Duty Boots on Buzzwole. That is a
real tier with megas *and* the modern dex; it needs a merged dex this tool does not build,
and it is the obvious next pool to run.

## 11. What this says to Realidea's team generator

`generate_bosses.py` sets `ON_THEME_MIN = 6`, so **the nine gym teams are monotype teams by
construction** and §2-§8 apply to them literally rather than by analogy. Everything below is
re-measured on **Realidea's own PBS chart, dex, learnsets and engine** — none of it is
carried over from the Smogon corpus, because the corpus cannot know what this build can hold.

### Defence: eight of the twenty-four pairs are answerable, and one of those is a mirage

The nine themes carry 24 weaknesses between them. Reading immunities off Realidea's own
`types.txt` and then asking whether a species with both types exists below the gym's level:

| gym | theme | answerable weaknesses | the species that answers it |
|---|---|---|---|
| Aimi | FAIRY | Poison (needs Fairy/Steel) | Mawile, Klefki, Magearna, Faemie |
| Kenn | WATER | Electric (Water/Ground) | Wooper, Quagsire, Marshtomp, Barboach |
| Douglas | ICE | Fighting (Ice/Ghost) | **Froslass only** |
| Ciara | DARK | Fighting (Dark/Ghost) | Sableye, Spiritomb |
| Lawrence | PSYCHIC | Ghost (Psychic/Normal) | Girafarig, Meloetta, Oranguru |
| Bay | NORMAL | Fighting (Normal/Ghost) | **none — no Normal/Ghost exists** |
| Lilliana | STEEL | Fighting (Steel/Ghost), Ground (Steel/Flying) | Honedge/Doublade/Aegislash, Skarmory/Celesteela |
| Abi | BUG | none of its three | — |
| Dhara | GROUND | none of its three | — |

**Sixteen of the 24 can never be answered by typing** and no amount of searching will find a
body for them — Bug, Dark, Fairy, Fire, Flying, Grass, Ice, Rock, Steel and Water have no
immune type. Bay's single pair is the on-paper-only case from §2, and it reproduces here
exactly as it did in gens 6-8. A generator that scores "resists what the theme is weak to"
as a soft goal will fail 17 of 24 pairs forever and should not be penalised for it.

What real teams do instead, and the numbers to aim at (§3, §4):

- **Exactly one answer, not two.** 93% of real Water teams carry one Electric answer where a
  shuffle of the same species gets one only 47% of the time. Redundancy appears only where
  the threat is existential (Electric-vs-Ground, Steel-vs-Ground, mean 2.1).
- **For the unanswerable sixteen, target a neutral body and nothing more.** 61% of real
  theme-weakness pairs sit at "best case ×1" and that is the correct build; the state to
  avoid is every member at ×2, which real teams reach only 8% of the time.
- **Abilities are 30% of real answers and they work here.** All eleven damage-negating
  abilities — Levitate, Water Absorb, Volt Absorb, Sap Sipper, Flash Fire, Storm Drain,
  Thick Fat, Motor Drive, Lightning Rod, Dry Skin, Heatproof — are referenced by 7-11 of the
  decompiled scripts, so unlike the terrain surges of `DEAD_PRIMARY` they have real handlers.
  This is the only route for the sixteen unanswerable pairs (Steel-vs-Fire is 100% ability on
  real teams).
- **Expect the answer to cost a ×4 elsewhere** (§6) and do not treat it as a bug: 98% of real
  Water teams that answer Electric hold a member that is ×4 to Grass. On a boss that is a
  designed exploit, not a flaw.

### Offence: the generated teams fail 4 of 24, and every failure is one move swap

This is the half that is currently wrong. Scoring `generated/teams_bosses_gyms.json` the way
§8 scores real teams:

| gym | cannot hit | own STAB into it | members resisting it |
|---|---|--:|--:|
| **Aimi** (Fairy) | **Poison** | ×0.5 | 1 |
| **Aimi** (Fairy) | **Steel** | ×0.5 | 0 |
| Douglas (Ice) | Fighting | ×1 | 1 |
| Lawrence (Psychic) | Bug | ×1 | 0 |

Real monotype teams carry super-effective coverage on **100% of teams** wherever their STAB
is resisted (§8, 35 of 51 pairs). Aimi is the worst shape in the study: Fairy STAB is
resisted by both Poison and Steel, the team can hit neither, and **nothing on it resists
Steel** — a Steel opponent walls all six members while taking nothing worse than neutral.
That is the Dragon-vs-Fairy pattern, and it is the one matchup type this corpus shows real
players never accept.

**All 24 pairs are buildable**: every gym/threat pair has 22 to 132 on-theme Realidea species
that can learn a super-effective move at the gym's level. So this is a **set-selection**
failure, not a species-selection one, and each of the four is one slot on a member already
present:

| gym | needs | member already on the team that can learn it |
|---|---|---|
| Aimi vs Poison | Ground or Psychic | Granbull → Earthquake; Ribombee → Psychic; Klefki → Psychic |
| Aimi vs Steel | Fighting, Fire or Ground | Granbull → Focus Blast/Overheat; Ribombee → Fire Blast |
| Douglas vs Fighting | Fairy, Flying or Psychic | Froslass → Psychic; Weavile → Aerial Ace |
| Lawrence vs Bug | Fire, Flying or Rock | Azelf → Fire Blast; Gallade → Stone Edge/Rock Slide |

**The root cause is not too few attacking moves — that hypothesis was measured and refuted.**
The generated gyms carry **2.93 damaging moves per set against real monotype teams' 2.56-2.64**,
and 0.3 members per team with one or fewer against real teams' 0.8-1.1. They are *more*
offensive than the real thing. What is low is which types those moves are: 8.4 distinct
attacking types per team against 9.3-9.4, and in the failing cases the moves simply do not
line up with the threats — Aimi fields seven attacking types and not one of Ground, Psychic,
Fighting or Fire; Lawrence seven and none of Fire, Flying or Rock. The generator is choosing
attacking moves by power and role, where a real builder chooses one of them by threat.

So the rule worth adding is narrow: **for each type the theme's STAB is resisted by, require
one damaging move on the team that hits it for ×2, and satisfy it from the learnset when the
published set does not carry one.** That is a per-team gate on 1-2 move slots, not a rebuild,
and the feasibility table above says it can always be met.

### Hazards and Taunt, and why the gen 6-7 rows are the ones to copy

Over the 4,092 monotype teams: **hazard setter 87%** (3,554 teams, 4,698 sets), **remover 59%**
(2,423 teams, 2,583 sets), **Taunt 25%** (1,030 teams, 1,144 sets), Heavy-Duty Boots 33%.
Against normal teams (`TEAM-CORPUS.md` §12-§13) monotype does less of all three — setter 87 vs
92%, remover 59 vs 69%, Taunt 25 vs 29% — and Defog and Rapid Spin are nearly even here
(1,322 vs 1,163) where normal teams run 2:1 Defog, because a monotype team takes whichever
remover its own theme happens to own.

**Removal per theme is decided by species supply, one generation at a time, and the swings are
enormous in both directions.** Boots do not exist before gen 8, so the left column is the clean
measurement and the one Realidea's gen-6-era dex should be compared against:

| theme | gens 6-7 | gen 8 | gen 9 | what changed |
|---|--:|--:|--:|---|
| Fire | 96% | 93% | 86% | — |
| Ice | 96% | 95% | 73% | — |
| **Psychic** | **68%** | 31% | **0%** | Latios/Latias Defog (81 sets) left the dex; nothing replaced them |
| **Dragon** | 80% | 59% | **21%** | the same Lati twins (58 sets), part-replaced by Cyclizar |
| **Dark** | 66% | 71% | **16%** | Mandibuzz Defog 61 sets → 17 |
| Water | 88% | 73% | 49% | Tentacruel/Pelipper → Quaquaval |
| **Fairy** | 18% | 13% | **0%** | Tapu Fini/Klefki Defog gone |
| **Fighting** | **3%** | 16% | **74%** | **Great Tusk Rapid Spin, 59 of 85 teams** |
| **Rock** | 7% | 67% | **86%** | Coalossal Rapid Spin, then Glimmora Mortal Spin |
| **Grass** | 6% | 23% | **61%** | Brambleghast and Toedscruel Rapid Spin |
| Steel | 44% | 61% | 80% | Excadrill → Iron Treads + Corviknight |
| pooled | **63%** | 58% | 55% | Boots 0% → 47% → 67% |

The pooled column looks like Heavy-Duty Boots quietly replacing removal. **Per theme it is
nothing of the kind**: five themes gain 40-70 points while five lose 50-68, and every single
move is a species arriving or leaving. Two Pokemon, Latios and Latias, account for Psychic
going to *zero* and most of Dragon's collapse. Any target taken from a pooled removal figure is
an average over a mechanism that does not operate at the pooled level.

**Realidea's own supply, on-theme species that can learn Defog or Rapid Spin at the gym's level:**

| gym | theme | carriers | who |
|---|---|--:|---|
| Kenn | WATER | 8 of 135 | Squirtle line, Staryu/Starmie, Ducklett … |
| Dhara | GROUND | 7 of 67 | Sandshrew/Sandslash, Donphan, Baltoy/Claydol, Drilbur … |
| Douglas | ICE | 4 of 36 | Cryogonal, Bergmite/Avalugg, A-Sandshrew |
| Bay | NORMAL | 4 of 113 | Rufflet/Braviary, Komala, A-Sandslash |
| Lilliana | STEEL | 4 of 50 | Forretress, Excadrill, Kartana, A-Sandshrew |
| Abi | BUG | 3 of 77 | Pineco/Forretress, Pheromosa |
| Lawrence | PSYCHIC | 3 of 85 | Starmie, Baltoy/Claydol |
| Ciara | DARK | 2 of 55 | Vullaby, Mandibuzz |
| **Aimi** | **FAIRY** | **1 of 55 — and it is excluded** | **Tapu Fini, which is in `DEAD_PRIMARY`** |

So **the Fairy gym cannot have hazard removal at all**: its only Defog carrier is a Tapu, whose
terrain surge has no handler in this engine. That is the same outcome gen 9 Fairy monotype
reaches at 0%, by an unrelated route. Every other gym has 2-8 bodies, which is thin but real,
so removal is a reachable floor for eight of nine and an impossible one for the ninth — worth
knowing before a quota charges Aimi for missing it.

**Taunt is the substitute where removal is impossible, and the corpus agrees.** Monotype Taunt
by theme runs Fighting 53%, Ghost 50%, Dark 42%, Fire 41%, Steel 40% against Bug 3%, Grass 7%,
Ground 8% — and Fighting and Ghost are exactly the two themes that could not remove hazards in
the pre-gen-9 dex (3% and 27%). They stop hazards being set instead of clearing them. Taunt is
a 0 BP Dark move in Realidea's PBS referenced by 13 decompiled scripts, and it is in **no
`ROLE_MOVES` role**, so nothing in the generator can currently ask for it.

### The Taunt role, as a spec

Adding it is four lines and one version bump, and it buys a **cap, not a floor** — which is
the correct outcome and worth knowing before anyone is surprised by it.

    # team_shape.py, among the job roles and BEFORE the modes
    "disrupt": {"TAUNT"},

`ROLES` is the column order of `sample.rows` and the file already warns that a cached profile
written against the old width is silently misread, so **`PROFILE_VERSION` must go 4 → 5** in the
same change; that is what forces the regeneration rather than a wrong read. Add it to `CHASED`
only if a floor is wanted — see below.

What the corpus puts in each half, from `TEAM-CORPUS.md` §13:

| archetype | teams carrying | per team | floor at CHASE 0.90 | cap = mean+1 |
|---|--:|--:|---|--:|
| stall | 16% | 0.17 | none | 1 |
| balance | 26% | 0.29 | none | 1 |
| bulky offense | 26% | 0.27 | none | 1 |
| offense | 43% | 0.50 | none | 1 |
| hyper offense | **56%** | **0.73** | none | **2** |

**No archetype carries Taunt 90% of the time, so `CHASE = 0.90` floors it nowhere** — exactly
the situation the `CHASE` comment already describes for removal. The cap alone is still worth
having: it stops a balance team collecting three Taunts out of published sets, and it lets hyper
offense hold the two that 14% of real hyper-offence teams do. Forcing one takes the same knob
removal needs (`CHASE` 0.80), and one gotcha: **Python's `round(0.5)` is 0**, so `offense`'s 0.50
mean rounds *down* and its cap lands at 1, not 2.

**For a themed gym the theme predicts Taunt better than the archetype does**, and the current
machinery cannot express that — floors and caps are per-archetype only. Monotype Taunt by theme:

| Fighting | Ghost | Dark | Fire | Steel | Psychic | … | Ground | Grass | Bug |
|--:|--:|--:|--:|--:|--:|--|--:|--:|--:|
| 53% | 50% | 42% | 41% | 40% | 30% | | 8% | 7% | **3%** |

The two at the top, Fighting and Ghost, are the two themes that could not remove hazards in a
pre-gen-9 dex (3% and 27%). If a per-theme term is not wanted, the cap plus supply gets most of
the way there on its own, because supply already varies the same way.

### Supply is the whole story, and Taunt is 7x easier than removal

Counted over Realidea's dex with no theme filter, and level-independent because all three come
by TM here:

| role move | species that can learn it |
|---|--:|
| Defog | **8** |
| Rapid Spin | 27 |
| either (= `removal`) | **35** |
| Taunt | **241** |

Removal is a 35-species role in this dex — that is why `CHASE = 0.90` leaving it unforced costs
so little, and why forcing it is expensive. Per gym, on-theme:

| gym | theme | removal carriers | Taunt carriers |
|---|---|--:|--:|
| Ciara | DARK | 2 | **46** |
| Lawrence | PSYCHIC | 3 | 30 |
| Bay | NORMAL | 4 | 27 |
| Kenn | WATER | 8 | 26 |
| Dhara | GROUND | 7 | 13 |
| **Aimi** | **FAIRY** | **1, and it is `DEAD_PRIMARY`** | **12** |
| Lilliana | STEEL | 4 | 11 |
| Douglas | ICE | 4 | 10 |
| Abi | BUG | 3 | **6** |

So the exemption and its replacement fall out together: **Aimi cannot be floored on removal and
can be floored on Taunt**, which is what the corpus does with Fighting and Ghost anyway. The
mechanism for the exemption already exists — `role_supply(level, stage, roles, theme=...)` takes
a theme precisely because a floor measured without it "says a floor is meetable that the fight
cannot meet". Abi is the one to watch on the other side: 6 Taunt carriers of 77, and Bug
monotype runs Taunt on 3% of teams, so a Taunt floor on a Bug gym would be fighting both the
dex and the corpus.

**One PBS fact to know before cross-checking any of this against Showdown**: Realidea has
**Alolan Sandslash as pure NORMAL** (Alolan Sandshrew is correctly Ice/Steel). It is therefore a
legal Normal-theme body in this build and not an Ice or Steel one, the generator and the game
agree with each other, and only canon disagrees.

### What does not transfer from the Smogon corpus

- **Nothing about which species answer what.** The immunity list is chart-derived and the
  chart is this build's; the bodies are this dex's, filtered by level and BST band. Both are
  re-measured above and both must be re-measured if PBS changes.
- **`reach` and the body-weighted numbers do not apply at all.** §8's coverage is weighted by
  the opposing metagame's real member population. A boss faces the *player*, not a
  distribution, so the bare-type test is the right gate here and the 92% figure is not a
  target.
- **Tera and the snow package are both out.** There is no Tera in this engine (§9 is moot),
  and §7's Aurora Veil answer is on the permanent exclusion list with Sticky Web.
- **Stall is still unbuildable** (`generate_bosses.py` line 255), which is why TEAM-CORPUS
  §12's stall row — the one archetype that trades reach for defence — has no application here.

## 12. What did not survive checking

- **"Water teams answer Grass with Water/Grass or Water/Poison."** They cannot. Those
  are ×1, not resists. The finding survives only as *neutral bodies*: 98% of Water teams
  have nothing better than a neutral switch-in to Grass, most often Toxapex or Tentacruel.
  Exactly two teams in 122 carry a real answer, and both are Sap Sipper Azumarill.
- **A first cut reported 66% typing coverage for Poison vs Ground.** The column labelled
  "typing only" was computed without *items* but still included abilities, so Levitate was
  being counted as a second type and compared against a typing-only null. Poison vs Ground
  has no typing answer in gen 9 at all — there is no legal Poison/Flying — and the real
  number is 0%, answered 53% by ability and 47% by Air Balloon.
- **"Structurally unresistable" was first computed from the null returning zero**, which
  silently merged two different facts: no type is immune to the attacker (a law of the
  chart, 32 pairs) versus the immunity exists but no legal species of that theme has it (a
  fact about one dex, 4 pairs). They are now reported apart.
- **4.4% of sets name an ability the listed forme cannot have, from two opposite causes.**
  Showdown's export writes the *pre-mega* ability — "Venusaur-Mega / Chlorophyll" plays as
  Thick Fat, "Houndoom-Mega / Flash Fire" as Solar Power — so 1,047 sets had the forme's
  real ability substituted. The remaining 345 are author error or a set written for another
  generation (Gengar with Levitate, which it lost in gen 7) and are dropped rather than
  guessed. Trusting the file as written had granted **52 answer slots that could never
  fire**, including a Sap Sipper Gastrodon resisting Grass.
- **449 sets write the base species beside its stone** ("Venusaur @ Venusaurite") instead
  of the Mega forme, and the first run scored them as the base. That is not cosmetic: base
  Gyarados is Water/Flying and takes Electric at ×4, Mega Gyarados is Water/Dark and takes
  it at ×2. Resolving them moved gen 6 Flying vs Ice from 13% to 33% (Mega Charizard X
  sheds Flying) and gen 6 Dragon vs Dragon from 0% to 4% — **Mega Altaria is the
  Dragon/Fairy answer the gen 9 dex does not have.**
- **`megaStone` is a map, not a forme name.** Showdown stores `{"Venusaur":
  "Venusaur-Mega"}`; reading it as a string yields `undefined` for every stone while
  `!!it.megaStone` stays true, so the mega resolution silently did nothing on its first
  run and every number came back byte-identical. An empty diff was the only symptom.
- **The gen 6 team-null result is weak, not negative.** One pair above the null at n=452
  against 10 at n=1,431 in gen 9 is a power difference; the pool-null count is 9-12 in
  every generation. Do not read gen 6 builders as less deliberate.
- **`type1` answers looked like a bug and were not.** A single-typed answer should be
  impossible on a monotype team; the eight that exist are Mega Aggron shedding Rock
  (§2). Worth re-checking if the count ever rises outside gen 6-7.
- **The typed Hidden Powers are absent from `Dex.moves.all()`** though `moves.get()`
  resolves them, so the first dump omitted all 1,277 of them — Hidden Power Ice alone is 495
  sets and it is the gen 6-7 coverage move. Fixing it was correct and **its measured effect
  is ~1%**: it is the *only* super-effective answer for 14 of 1,278 gen 6 theme-threat
  instances and 44 of 3,822 in gen 7 (0.1-0.2% in gens 8-9). Offensive coverage is so
  redundant that removing a move rarely removes the answer. Two mistakes were needed to get
  there: a typed Hidden Power comes back carrying the BASE move's id, so `moves[hp.id] = ...`
  overwrote one key eighteen times and the move count never moved.
- Five moves in the corpus do not carry their own type and are resolved rather than read:
  Tera Blast (the declared Tera), Ivy Cudgel (Ogerpon's non-Grass half, 146 sets), Weather
  Ball (the weather a *teammate* sets — Ice on a snow team), and Judgment / Multi-Attack /
  Revelation Dance / Raging Bull / Aura Wheel (the user's own typing, therefore never the
  off-type coverage §8 counts). Three remain unresolved (Terrain Pulse, Techno Blast,
  Natural Gift) and are counted as no coverage.
- Multiple comparisons are real: 51 pairs at α = 0.05 buys ~2.5 false positives, so the
  Bonferroni counts (10 above the pool null, 5 above the team null in gen 9) are the
  conservative read of §4. The `res%`-vs-null p-values also move with the null's seed for
  pairs near 0.05, which is why §4 reports seed survival rather than one run's list.
- The team null samples species sequentially by weight and rejects repeats to honour
  Species Clause, which is not exactly proportional sampling without replacement. The
  bias is small at six draws from 20-80 species and does not move any p-value here off
  its side of 0.05.
