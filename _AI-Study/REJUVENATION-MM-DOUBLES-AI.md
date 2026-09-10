# Rejuvenation MM doubles AI teardown and Reborn Yang comparison

Source studied: `Rejuvenation MM/Scripts/PokeBattle_AI.rb` from the local Pokémon
Rejuvenation v13 MM install. The file is 37,352 lines. This is a source-level study;
the existing `Data/debuglog.txt` confirms that the doubles scoring paths execute, but
this document does not claim a cross-engine win rate.

## Decision pipeline

Rejuvenation MM does not have a separate joint coordinator. For each AI battler it:

1. enters `pbDefaultChooseEnemyCommand` and builds move scores before deciding whether
   to switch (`PokeBattle_AI.rb:37156-37181`);
2. scores every usable move against each opposing slot, producing `(move, target,
   score)` candidates (`:30221-30225`, `:30596-30602`);
3. recursively calls `pbBuildMoveScores` for its partner in damage-only mode and scans
   the partner's moves for priority, Fake Out, likely KOs, status targets and survival
   (`:30049-30216`);
4. rewrites its own target scores to avoid redundant attacks and support moves
   (`:30341-30503`), then keeps the best target for each move (`:30619-30635`);
5. chooses the exact maximum-scoring move. Equal maxima are resolved by accuracy
   (`:30760-30781`).

This is an **asymmetric look-ahead scorer**. It approximates the ally's best action
while choosing the first slot. When the later ally is scored, it can also inspect the
action already registered by the first ally through `Attacking` and
`AttackingTarget` (`:30460-30494`, `:30825-30836`). It does not enumerate and compare
all legal pairs of allied actions as complete plans.

## What it models well

### Target choice and overkill control

Each move is scored independently into both opposing targets. When the partner has a
likely KO, the current battler's score against that same target is usually reduced to
20%; the rule considers priority, Fake Out, whether the partner survives long enough
to act, move order under Trick Room, and whether a spread move can still profitably hit
the other foe (`:30052-30166`, `:30405-30495`). Ties favor the foe with the more
disruptive ability or the greater projected damage (`:30505-30543`).

The shipped debug log contains live `Multi-Target Adjustment`,
`Doubles-Target Adjustment`, and `Status-Target Adjustment` entries, so these are active
runtime paths rather than dead source.

### Spread moves and partner safety

For all-opponent moves, it adds the two foe scores (`:30280-30293`). For all-non-user
moves, it also estimates damage to the ally and reduces the result when the ally would
be hurt or KO'd before acting (`:30227-30276`). It recognizes Telepathy plus Flash Fire,
Water Absorb, Storm Drain, Dry Skin, Sap Sipper, Disenchant, Volt Absorb, Lightning Rod
and Motor Drive. Beneficial absorption can double the move score (`:30231-30249`).

It discounts spread attacks when a remembered opponent has Wide Guard, and also models
Powder and Ion Deluge (`:29886-30023`). Follow Me and Rage Powder in memory reduce a
single-target action aimed past the redirector (`:30301-30339`).

### Support and ally targeting

The normal per-effect scorer contains extensive doubles clauses for Fake Out, speed
control, Trick Room, Tailwind, redirection, guards and field effects. The target builder
also explicitly permits ally targeting for Heal Pulse, Simple Beam, Skill Swap, Frost
Breath, Beat Up, Topsy-Turvy, Floral Healing, Instruct, Pollen Puff, Purify, Spotlight,
Psych Up, Swagger, Flatter and Entrainment (`:30604-30616`).

It suppresses overlapping status and side effects when the predicted partner action is
similar (`:30341-30384`). This is useful, although the comparison is based on the
partner's provisional best score rather than a stable joint plan.

### MM-specific battle rules

The AI must be judged with MM's mechanics rather than standard doubles alone. Its
changelog gives Follow Me and Rage Powder one extra priority, makes Inner Focus protect
the partner from flinching, and changes Damp into Fire-type redirection. It also removes
Destiny Bond, Tailwind, Sticky Web, Encore and Wide Guard from normal learnsets
(`MOD CHANGELOG + CREDITS/MOD CHANGELOG.txt` and `Pokemon Changelog.txt`). Trainer-only
sets can still use scripted moves, so the corresponding AI rules remain relevant, but
their frequency in ordinary teams is lower than the source coverage suggests.

### Switching in doubles

`pbSwitchTo` evaluates an incoming Pokémon against both opponents. It checks speed and
priority from both slots, combined incoming damage, Trick Room, weather, status access,
Fake Out, Tailwind and partner combinations (`:34706-36224`). It also rejects a reserve
slot already selected by the partner (`:34792-34805`). This is substantially more than
a singles switch score reused unchanged.

## Information advantage

Rejuvenation MM's AI is not suitable as a fair-information reference without removing
several inputs.

The command loop asks for both player actions before both enemy actions: slots are
processed in the order 0, 2, 1, 3 (`PokeBattle_Battle.rb:5891-5917`). While the player
chooses, the engine stores the exact selected move in `SomethingCrazy`, whether it is
damaging in `Attacking`, its selected targets in `AttackingTarget`, item use in
`UsingItem`, and switching plus the reserve index in `Switching`/`SwitchingTo`
(`:5940-5971`, `:5986-6003`).

The AI consumes those fields. Examples include reading the exact chosen move class
(`PokeBattle_AI.rb:14939-14972`), selected targets (`:30460-30494`), item healing
(`:29912-29943`), and switch state (`:14192`, `:20070`, `:32687`). It also loops over
`opponent.moves` directly in many scoring and damage routines, bypassing revealed-move
memory. The advantage is broader than Reborn Yang Normal's narrow reads of registered
priority and item actions.

## Defects and fragile points

1. Four intended partner-damage penalties use `s * 0.5` without assignment, so those
   reductions do nothing (`PokeBattle_AI.rb:30254`, `:30256`, `:30264`, `:30266`).
   The same defect appears in Reborn Yang's earlier spread-damage block.
2. Partner prediction is recursive but reduced to damage arrays and a few provisional
   best-move facts. Interactions such as Helping Hand plus one particular attack are not
   evaluated as one complete pair.
3. Coordination depends on slot and command order. The second AI battler sees more
   committed ally information than the first.
4. The exact-max selector makes a small scoring discontinuity decisive and removes
   behavioral variety. Its calculated standard deviation is unused (`:30761-30768`).
5. The implementation mutates battler forms, types, HP, field and weather while
   estimating actions, then restores them through many local branches. That makes
   early returns and new rules risky.
6. Several doubles checks use full opponent movesets while nearby checks use AI memory,
   so the knowledge policy is inconsistent even apart from the current-turn reads.

## Comparison with Reborn Yang

| Area | Rejuvenation MM | Reborn Yang | Better basis for Portable AI |
|---|---|---|---|
| Core design | Per-battler target scorer with recursive ally estimate | Per-battler score matrices followed by `coordinateActions` | Reborn's separation is easier to reason about; an explicit joint planner is better than both |
| Pair search | No exhaustive pair evaluation | No exhaustive pair evaluation | Portable's Cartesian pair planner |
| Target allocation | Strong local KO and overkill rules; later slot sees the first action | Four-battler move-order cases, target patterns and threat ranking | Reborn for a cleaner shared-board model |
| Spread attacks | Sums both foe scores and prices ally damage/absorption | Same base idea plus an explicit double-KO plan and helper rewrites | Combine Rejuvenation's safety inputs with explicit joint evaluation |
| Support | Broad per-move coverage and ally-target whitelist | Explicit Fake Out, Quash, After You, Helping Hand, guards, redirection and duplicate-action pass | Reborn's coordination concepts |
| Switching | Deep score against both foes and duplicate reserve guard | Deep score against both foes plus separate Normal/Intense switching engines | Both provide useful features; neither should be copied literally |
| Opponent knowledge | Reads full movesets and current player move, target, item and switch state | Normal mostly uses observed memory, with narrow priority/item exceptions; Intense predicts choices | Reborn Normal after removing the two exceptions |
| Final choice | Deterministic exact maximum; accuracy breaks ties | Normal samples within 5% of maximum; Intense tightens to 2% | Configurable low-temperature sampling |
| Maintainability | One 37k-line scorer with nested mutation | Separate effect handlers and a coordination phase, but multiplier order still matters | Typed state plus pure pair scoring |

Rejuvenation MM is impressive at **coverage**: it knows many doubles mechanics, prices
both targets, protects its partner, and evaluates switches against the full opposing
pair. Reborn Yang has the stronger **coordination structure** and a much better Normal
mode knowledge model. Neither provides the final architecture for Portable AI because
neither scores complete allied action pairs as first-class plans.

## What Portable AI should take from it

- Add target-level features for partner survival, partner KO certainty, redirect risk,
  Wide Guard risk and absorb/immunity value.
- Feed the joint planner all legal ally-target actions, including beneficial attacks
  into Flash Fire, Storm Drain, Sap Sipper, Lightning Rod and similar abilities.
- Score switches against both foes and reserve the selected bench slot at the pair-plan
  level.
- Keep one explicit observation model. Current-turn player choices and unrevealed moves
  must not enter the fair core.
- Preserve stochastic choice only after joint plans have been ranked; use seeded,
  configurable temperature for measurement.

The next useful validation is a shared scenario suite, not a direct win-rate comparison
between games. The same board concepts should be encoded in each engine: double-target
overkill, spread move into a vulnerable ally, absorb-partner synergy, redirection,
Wide Guard, Fake Out plus speed control, and two allies competing for one reserve slot.
