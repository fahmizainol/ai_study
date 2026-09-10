# Reborn Yang doubles AI teardown

Source: `Reborn Yang/Scripts/PokeBattle_AI_2.rb`. This document describes the shipped
Normal AI unless a rule is explicitly marked Intense.

## Decision pipeline

Reborn does not search every pair of allied actions. Its pipeline is:

1. Score each active battler separately against the left foe, right foe, and its own
   partner (`processAIturn`, lines 129-158; `buildMoveScores`, line 317).
2. Run `coordinateActions` once both score matrices exist (lines 160 and 2092-2675).
   This mutates individual scores using shared board facts and predicted move order.
3. Select each battler's action independently from the mutated scores. Normal samples
   the top 5% and gives the exact maximum two entries in the roulette (lines 1666-1684).

The architecture is therefore a **score-matrix plus coordination rewrite**, not a
two-action game-tree search. It is expressive, but its rules can interact in ways that
are difficult to reason about because one multiplier changes the input to later rules.

## What Reborn models well

### Target allocation and immediate tempo

`coordinateActions` identifies which foe each ally can KO, computes a threat score for
both foes, and uses the predicted order of all four battlers to discourage wasted
double-targeting (2095-2366). Threat combines base stats, level, boosts, speed, status,
known spread moves, disruptive ability value, and whether the foe can KO an ally
(2677-2717).

A spread move that can KO both foes receives a 1.5 multiplier (2117-2123). Once such a
move is identified, the other ally is pushed toward actions that help it resolve:
Feint, priority, Fake Out, Quash, Tailwind, Trick Room, setup, healing, redirection, and
speed or damage reduction receive large order-dependent multipliers (2385-2575).

### Partner safety

For moves hitting all non-users, Reborn sums value against both foes and then prices
damage to its partner (879-928). It recognizes Telepathy and type-absorb combinations
such as Flash Fire, Water Absorb, Storm Drain, Sap Sipper, Earth Eater, Justified,
Volt Absorb, Lightning Rod, and Motor Drive (883-901). Otherwise partner damage can
reduce the move toward zero, especially when it would KO the partner before it acts.

### Support moves

- Tailwind is worth more in doubles and less under Trick Room (6667-6679).
- Trick Room considers roles, survivability, Room Service, both opposing speeds, and
  receives a doubles multiplier (8420-8441).
- Follow Me/Rage Powder values a bulky redirector, a setup partner, partner danger,
  redirector HP, and move order (8348-8372).
- Helping Hand considers whether the user lacks a good attack, relative offensive
  stats, whether the user is slow or expendable, and whether its partner is also slow
  (6911-6921).
- Wide Guard is only scored when a known opposing spread move or allied all-non-user
  move makes it relevant (4190-4206).
- After You and Quash inspect the partner's current best move and whether changing the
  order creates a KO (4806-4823 and 8407-8417).

### Duplicate-action prevention

After finding both provisional best moves, Reborn prevents both allies from choosing
Follow Me/Rage Powder, the same field move, overlapping status, confusion or Encore.
It also cancels Helping Hand when the partner's best move is non-damaging, and handles
the Earthquake/Roost order conflict (2592-2674).

### Switching

Doubles switch-in scoring checks both opponents, their priority damage, speed against
both, spread attacks, Intimidate effects, and whether both allies selected the same
reserve slot (11363 onward; duplicate-slot guard at 1577-1586). The existing probe has
not produced a positive voluntary doubles switch score while the partner is alive, so
this part is source-supported but not yet behaviorally validated.

## Normal versus Intense information

Normal is mostly fair-information, using revealed-move memory. There are two narrow
doubles exceptions: it reads the player's registered item use and registered priority
move while deciding whether its partner survives (745-763).

Intense adds direct reads and prediction. It watches registered Follow Me/Rage Powder
choices and probabilistically redirects its intended target (2746-2785), and tracks
repeated Wide Guard and redirection habits (225-239). Those rules should not be copied
into a fair Portable AI.

## Defects and fragile points to test

1. The fallback split-target random branch is duplicated: both sides of `rand(2)` make
   the same score edits (2321-2329).
2. Several `:rigth` spellings make intended `:right` pattern branches unreachable
   (2277, 2287, 2299, 2314, 2356).
3. The spread-KO support condition contains `moveloop==nil && ... moveloop.id`, which
   can dereference `nil` and can never recognize a real support move (2119).
4. Two expressions intended to halve a partner-damage factor use `s * 0.5` without
   assignment, so they do nothing (907 and 919).
5. Coordination applies sequential multipliers to shared score matrices, making rule
   order significant and complicating attribution.
6. Final selection is still a roulette after coordination, so identical score matrices
   need multiple seeded observations rather than a single expected action.

## Portable AI lessons

The useful ideas to reproduce are the information inputs, not the literal multipliers:

- Build one per-foe threat and damage-race record with order against each foe.
- Evaluate an explicit pair of allied actions, preserving the Portable core's current
  Cartesian joint planner.
- Treat a spread double-KO as a plan and value the partner action by whether it helps
  that plan resolve before either attacker faints.
- Represent protection, redirection, Fake Out, Quash, After You, speed control and
  partner attacks as effects on a four-battler turn timeline.
- Reject duplicate field/status actions structurally rather than by zeroing one move's
  entire score row.
- Keep all opponent-choice reads outside the fair-information core.

## Measurement plan

Before implementing weights, add discriminating scenario cards for:

1. Fake Out + Tailwind versus two attacks.
2. Follow Me + setup when the setup partner is threatened, and the same board when the
   redirector cannot survive the redirected hit.
3. Helping Hand + a secured KO versus two weaker attacks.
4. Protect + allied Earthquake, including move order and Feint/Unseen Fist exceptions.
5. Wide Guard against a revealed spread move and against an unrevealed one.
6. Quash/After You creating a KO before the target moves.
7. Deliberate double-targeting when one hit is insufficient, versus wasted overkill.
8. A voluntary switch covered by the partner, tested against both opponents' damage.

Only then should each Portable rule be enabled separately and run through traced
`doubles_a` battles against Reborn Normal.
