# Trainer Level Scaling — Realidea V4.1

Spec for making every trainer's party level track the player's. Status: **specified,
not implemented.** Sibling of `Level_Cap.rb` and `Challenge_Rules.rb`; same adapter
convention, same fail-safe posture as `Team_Overrides.rb`.

## 1. What already exists (reuse, don't reinvent)

| thing | where | what it does |
|---|---|---|
| `balanceo` | `265_Entrenadores.rb:105` | `pbBalancedLevel($Trainer.party) - 1` — the dev's own scaler |
| `pbBalancedLevel` | `173_PSystem_Utilities.rb:2079` | weighted party mean, skewed toward the higher mons, **+2** |
| scaled fights | 25 of 178 battles | levels written `balanceo` (37 mons), `balanceo-2` (14), `balanceo+1` (3) |
| dormant full-scale mode | `265_Entrenadores.rb:117` | `$game_switches[289]/[290]` → `pbBalancedLevel-4+rand(5)`, per mon, no party context |
| `RealideaLevelCap.current` | `Level_Cap.rb` | badge-indexed soft EXP cap, expert `[20,26,32,36,40,45,52,57,61]`, champion 75 |
| `team_override_build` | `Team_Overrides.rb:1135` | evaluates `["balanceo", offset]` level cells at battle time |

`balanceo` and `balanceo+1` are the **same anchor with a per-mon integer offset** — the
map events write a plain arithmetic expression into `createPokemon`'s level argument.
That offset is the team's internal shape (ace one above, chaff two below). Any scaling
scheme that ignores it flattens every fight into N mons at one level, which is
[§5 deficiency 5](TEAM-DESIGN.md) all over again.

The dormant `289/290` mode is **not** reusable as-is: it runs inside `createPokemon`,
which sees one mon at a time and cannot know the team's ace, so it destroys exactly
that shape. It is evidence the dev wanted this feature, not an implementation of it.

## 2. Decisions

| decision | value | rationale |
|---|---|---|
| Anchor `A` | `pbBalancedLevel($Trainer.party) - 1` — i.e. **`balanceo`** | the dev's own measure, used verbatim by 25 fights. `pbBalancedLevel` adds +2 over your weighted party mean and `balanceo` takes 1 back, so a fight meets you at mean+1 |
| Scope | **all 178 battles**, bosses included | user decision; gyms scale too |
| Leash | **6** | how far **above** its designed level a fight may rise |
| Direction | **pressure only** — designed level is a hard **floor**, `designed + LEASH` the ceiling | see §3 |
| Gate | `Data/level_scaling.txt` present = on | matches `Challenge_Rules`; absent = engine untouched |

### Why pressure-only, and why the ceiling stays

A fight is never weaker than the developer designed it, and rises to meet a player who
has outgrown it. **An under-levelled player gets no relief** — that is the configuration,
not an oversight.

The reason this needed measuring: the fights that matter already sit near the cap.
**89% of them are within 6 levels of their stage cap** (median 3), so in forward play a
bounded rise reaches essentially everything — the ceiling almost never binds. Worked
example, a pre-gym-3 fight designed `[29,29,30,29,28,28]` against a player at cap 32:

| band | result |
|---|---|
| designed as ceiling (the first build) | `29,29,30,29,28,28` — untouched, the player walks through |
| **designed as floor, `+6` ceiling** | `33,33,34,33,32,32` |
| unbounded rise | `33,33,34,33,32,32` — *identical* |

**The ceiling costs nothing where you play and saves everything where you don't.**
Delete it and every fight's ace lands on `A` regardless of where it sits in the story:
measured over the installed teams at 8 badges, the whole game collapses from 46 distinct
ace levels to **2**, a route-1 pair presenting the same level as the champion. Encoding
"this is an early fight" is exactly what the designed level does, and the `+LEASH`
ceiling is what preserves it without needing a per-fight stage table (§8).

## 3. The formula

For a fight whose party the engine has just built with levels `L_0..L_n`:

```
A        = pbBalancedLevel($Trainer.party) - 1      # = balanceo
cut      = median(L) + 2*LEASH                     # scripted-outlier cut
ace      = max(L_i where L_i <= cut)
scaled_i = clamp(A + (L_i - ace),  L_i,  L_i + LEASH)     # LEASH = 6
           then clamp into [1, PBExperience::MAXLEVEL]
           mons above `cut` are left exactly as designed
```

Three clauses, one each for a property:

- `A + (L_i - ace)` — **preserves the team's internal spread exactly.** The ace lands on
  `A`; a `balanceo-2` chaff mon lands two below it.
- ceiling `L_i` — **never scales up.** This is what makes the reference table unnecessary.
- floor `L_i` — **never weaker than designed.** This is the pressure-only choice.
- ceiling `L_i + LEASH` — **a bounded rise.** Without it the game collapses to one level.
- outlier cut — **a scripted gimmick does not set the fight's difficulty.**
  Two fights (maps 164 and 198) pin one mon 37-47 levels above its five teammates;
  the engine already special-cases it twice, rewriting its level to `balanceo` under
  `$game_switches[212]` and zeroing its EXP award. Ungated it becomes `ace`, and the
  whole shift `A - ace` goes deeply negative — the replay in §6 caught it distorting
  those teammates by the full leash. Such a mon neither sets the anchor nor moves.
  The gap is bimodal across both corpora — every other fight in the game sits at 7 or
  below — so any cut between 8 and 36 gives the same answer and the threshold is not tuned.

### Verified behaviour

Run `tools/check_level_scaling.rb` (§6). Gym 4, designed ace 36, expert cap 36:

| player party | `A` | scaled team |
|---|---|---|
| 36/35/35/34/34/33 (on curve) | 36 | 35,35,35,35,35,**36** — unchanged |
| 33/32/32/31/31/30 (a little behind) | 33 | 35,35,35,35,35,**36** — unchanged, no relief |
| 24/23/22/22/21/20 (far behind) | 23 | 35,35,35,35,35,**36** — unchanged, no relief |
| 50/50/49/48/48/47 (cap off, over-levelled) | 50 | 41,41,41,41,41,**42** — risen, ceiling-bound |
| route-1 fight designed 3, player at 8 badges | 57 | **9**,9 — risen, ceiling-bound |

Two consequences worth stating plainly:

1. **The whole game gets harder, everywhere — not just on revisits.** Designed levels sit
   a median of 3 below their cap, so a player at cap previously met fights *below* them
   and now meets them at `mean+1`. Across the installed teams at cap parity, **158 of 161
   fights rise**. That is the intended effect of making the designed level a floor, but
   it is a far broader change than "revisiting is less trivial".
2. **Falling behind no longer helps you.** The floor means a struggling player faces the
   full designed team however far under the curve they are — at 15 under cap only 3 of
   161 fights differ from vanilla, and those rose. The EXP death-spiral argument that
   motivated a floor in the first build does not apply here, because nothing ever drops.

### The developer's 25 hand-scaled fights: 20 unchanged, 5 rise

Their levels are `A + off_i`, so `ace = A + max_off` and the shift is `-max_off`. Where
the team's top offset is `0` or `+1` — 20 of the 25 fights — the shift is zero or
negative, the floor pins it, and the fight is untouched. **The 5 fights written entirely
as `balanceo-2` rise by 2 onto the anchor**, because at runtime a team pinned 2 below the
anchor is indistinguishable from a fixed team designed 2 below its own ace. There is no
information in the party that separates them; preserving the developer's deliberate −2
would need the registry to mark those fights as already-scaled.

## 4. Where it hooks

Both battle paths return the same `[trainer, items, party]` triple, so one helper serves
both. Hook the **result**, not the construction — that covers overridden and original
parties with one code path.

| hook | path | note |
|---|---|---|
| `createTrainer` | inline map-event fights (the 178) | alias must be installed **after** `Team_Overrides` so it wraps it: the override supplies designed levels, then this clamps them |
| `pbLoadTrainer` | `pbTrainerBattle` / `.dat` fights (16 trainers) | same helper |
| `pbRegisterPartner` | **guard, not a hook** | `098_PField_Field.rb:1969` calls `pbLoadTrainer` to build your **ally**. Scaling it down weakens the player when they are already behind — exactly backwards. Set a suspend flag around the inner call |

Not `createPokemon`: it is called per mon with no party context, so it cannot compute
`ace` and cannot preserve the spread. That is the mistake the dormant `289/290` mode makes.

### Re-levelling a built Pokémon

```ruby
poke.level = n      # raises ArgumentError outside [1, MAXLEVEL] -> clamp first
poke.calcStats      # level= only moves @exp; stats are stale without this
```

`calcStats` (`123_PokeBattle_Pokemon.rb:882`) preserves the damage diff and clamps
`@hp` to the new `@totalhp`, so a freshly built full-HP mon comes out full. Moves are
explicit on overridden teams and are not touched; an original mon scaled down keeps the
level-up moves it was built with, which is the desirable direction.

### Section placement

New section after `Team_Overrides` (330) and before `Main` (336) — natural slot is 332,
after `Level_Cap`. Injected with `tools/pack_rxdata.py --insert`, independently removable
like the others.

## 5. Guards and edge cases

1. **Nil mons.** Original events carry typo'd species that yield `nil` party entries
   (`Team_Overrides` already skips them). Skip nils when computing `ace`; bail if no
   valid level survives.
2. **Empty player party.** `pbBalancedLevel([])` returns 1, which would floor every
   fight. No-op when `$Trainer.nil? || $Trainer.party.length == 0`.
3. **Range.** Floor can go below 1 for low-level fights (`L_i ≤ 5`); `level=` raises.
   Clamp into `[1, MAXLEVEL]` last.
4. **Blanket `rescue` → party untouched**, mirroring `Team_Overrides`. A scaling failure
   must never cost the player a fight; note that `createPokemon`'s own bare `rescue`
   returns `nil`, which is how a bad level silently reverts a whole override today.
5. **Orthogonal to the level cap.** The cap limits the player, scaling limits the
   trainer; they act on opposite sides and need no coordination. Deliberately *not*
   gated on `Data/original_teams.txt` — scaling works fine on original rosters, unlike
   `Level_Cap`, which disables itself there.
6. **`pbLoadTrainer` never assigns `opponent.party`** — it returns the party at index
   2 and `pbTrainerBattle` reads it from there, while `PokeBattle_Trainer#initialize`
   leaves `@party` an empty array. Hook index 2, not `result[0].party`. **This is also a
   live defect in `Team_Overrides.rb`'s dat hook** (§7 below), which is why this spec
   does not copy its shape.
7. **Wild Pokémon are out of scope** (`pbGenerateWildPokemon`, a different path). Say so
   explicitly — "scale with the player" can be read to include them.
8. **Facility and mirror fights are already no-ops.** `269_Metrocombate` builds its
   starter trios at `balanceo` (§3 no-op) and `270_Doppel prota` copies your own party
   levels (ceiling = your levels). Only Metrocombate's `when 6` Alola trio, pinned at a
   flat 35, is reachable by the clamp.

## 6. Proof plan

Cheap and sufficient, in order:

1. **`tools/check_level_scaling.rb`** — pure-arithmetic harness, no engine. Ports
   `pbBalancedLevel` verbatim and asserts the §3 table plus the 12 `balanceo` no-op
   cases. Ruby 3.2 is installed locally; the subset used is 1.8-compatible. *Already
   written and passing — this is the evidence in §3.*
2. **Replay against real data** — `tools/replay_level_scaling.py`, over both corpora
   the game actually runs: the 178 original event parties and the 161 installed
   replacement teams, at three synthetic player curves. **Written, and passing:**

   | corpus | player | fights changed | mons moved | max rise |
   |---|---|---|---|---|
   | original events (178) | on cap | 151 | 350 | 6 |
   | | cap-6 | 26 | 61 | 6 |
   | | cap-15 | 4 | 10 | 6 |
   | installed teams (161) | on cap | 158 | 477 | 6 |
   | | cap-6 | 29 | 75 | 6 |
   | | cap-15 | 3 | 11 | 6 |

   Three invariants asserted, all holding: **no level ever falls below its designed
   value**, no rise exceeds `LEASH`, no level leaves `[1, MAXLEVEL]`. Each is
   negative-controlled — running the replay against a build with the floor and ceiling
   deleted makes it FAIL with those exact messages, which is the only thing that proves
   an assertion is actually wired up. This harness also caught the outlier defect above.
3. **Boot test** — one trainer fight with the marker file absent (must be byte-identical
   to today) and one with it present at a deliberately under-levelled save.

## 7. Found while wiring this — a live defect in `Team_Overrides.rb`

Not fixed here; out of scope for level scaling, and it wants its own proof.

`Team_Overrides.rb:1227`'s `pbLoadTrainer` hook builds its lookup key from
`result[0].party`. `pbLoadTrainer` (`114_PTrainer_NPCTrainers.rb:20-94`) never assigns
`opponent.party`; it returns `[opponent, items, party]` and `PokeBattle_Trainer#initialize`
(`113_PokeBattle_Trainer.rb:274`) leaves `@party` as `[]`. So the hook computes
`ace = 0` and `sig = []`, producing key `[tid, partyid, 0, []]`, which matches none of
the 11 registry keys — every one carries a real ace and species list. **The dat
overrides have never fired.** And the assignment `result[0].party = newparty` would not
reach the battle even on a match, since `pbTrainerBattle` reads `trainer[2]`.

Both halves are one-line fixes (`result[2]` in place of `result[0].party`), but the
right order is: fix, then re-run the dat replay, then verify in game which of the 16
dat trainers is reachable — the registry covers 11 of them and their teams have never
been seen at runtime.

## 8. If down-only turns out to be wrong

Upgrading to full rubber-banding is additive, not a rewrite: keep the same formula and
replace the ceiling `L_i` with `ref_F + (L_i - ace)`, where `ref_F` is the fight's stage
level. That needs the `map_id → stage` table described in §2, which
`fight_context.G.story_level()` can emit — it already computes exactly this number
offline for the generator's item gate and eBST targets.

## 9. Files

| file | what |
|---|---|
| `adapters/realidea/Level_Scaling.rb` | the injected section (to write) |
| `tools/check_level_scaling.rb` | formula harness, §6 step 1 |
| `tools/replay_level_scaling.py` | replay over both real corpora, §6 step 2 |
| `Data/level_scaling.txt` | marker: present = on; optional integer body overrides `LEASH` (default 6) |
