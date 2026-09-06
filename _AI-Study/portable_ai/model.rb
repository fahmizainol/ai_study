# PortableAI normalized model.
#
# The core deliberately accepts and returns plain Hash/Array values. Engine adapters own
# every object lookup and legality check; callers only need to know this small interface:
#
#   PortableAI.plan(snapshot, config, rng) -> {
#     "actions" => [decision, ...], "diagnostics" => {...}
#   }
#
# Required snapshot keys:
#   "actors"  Array of AI battlers. Each actor has "index" and legal "actions".
#   "targets" Array of opposing active battlers.
#
# An action is already legal and has "type" ("move" or "switch"), "base_score", and the
# registration fields the adapter needs ("slot", plus "target" for targeted moves).
# Everything else is optional evidence used to improve the score.

module PortableAI
  VERSION = "0.6.5" unless const_defined?(:VERSION)

  module Model
    DEFAULT_CONFIG = {
      "deterministic" => true,
      "noise"         => 0,
      "switching"     => true,
      "memory"        => true,
      "coordination"  => true,
      "knowledge"     => "fair",
      # A voluntary switch must name an escape reason rather than merely outscoring
      # the available moves (Core.score_switch). Set false to restore the pre-0.3.0
      # score-competition behaviour for A/B runs.
      "switch_gate"   => true,
      # How loudly a switch candidate's incoming type risk counts against its
      # offensive matchup, in Core.score_switch. 1.0 makes the two exactly as loud as
      # each other; it was chosen for that symmetry, not swept, so this is a knob and
      # not a constant. 0.0 disables the defensive term and reproduces 0.3.1 exactly.
      "switch_risk_weight" => 1.0,

      # 0.4.0 move-policy rules. Each reproduces 0.3.2 exactly when off, so the
      # gauntlet can A/B any one of them without rebuilding (Data/ai_harness.txt ->
      # $PORTABLE_AI_CONFIG -> Adapter.config_for).
      #
      # Ask whether healing changes who is alive at the end of the turn, instead of
      # scoring recovery on the healer's own HP alone (Core.score_move). False
      # restores the flat heal_under_lethal_threat -80.
      "heal_gate"       => true,
      # How loudly a move's hit chance discounts its damage and its lethal bonus:
      # Reborn's (accuracy + 100) / 200 (PokeBattle_AI_2.rb:3349). 0.0 ignores
      # accuracy, which is 0.3.2; 1.0 is Reborn's own weight.
      "accuracy_weight" => 1.0,
      # Read the exported move priority against the actor's speed order, so a KO that
      # cannot land before the actor dies stops being scored as a KO.
      "priority_gate"   => true,
      # Charge stat-dropping and self-KO moves for what they cost.
      "self_cost"       => true,
      # The -400 "you die whatever you click" rules (heal_cannot_resolve,
      # ko_never_lands) only count a threat as certain when the adapter says the
      # foe's move cannot fail to happen: 100% accurate and the foe awake
      # (actor["certain_incoming_damage_pct"]). Measured on set_c, the loose
      # predicate was right 85% of the time under those conditions and 28% outside
      # them (PORTABLE-AI-REBORN.md, "Decision-log run"). False is 0.4.0.
      "strict_threat"   => true,

      # 0.5.0 tables. Reborn is mostly per-move and per-ability branches (494 move
      # function branches, 1,161 ability mentions that are decision logic), and single
      # per-turn rules stopped moving wins after 0.3.0. These four ship that breadth as
      # data read by a few generic rules, measured as one batch. All four false
      # reproduces 0.4.1 battle-for-battle.
      #
      # Move side effects: secondary status, flinch, stat drops, recoil, drain,
      # multi-hit, item removal, speed control, first-turn and delayed moves.
      "side_effects"    => true,
      # Abilities that change what a move is worth without changing its damage:
      # Sturdy/Focus Sash defeating a kill call, Unaware, Contrary, Justified,
      # Regenerator, and the status-deterrent table.
      "ability_rules"   => true,
      # Entry cost as its own term: hazards and the real incoming estimate on the
      # switch candidate, in place of the type-only proxy.
      "entry_rules"     => true,
      # 0.6.0. Hits-to-KO both ways, computed once in Core.damage_race and read by the
      # setup gate and the switch-in ladder. False reproduces 0.5.0 exactly.
      "damage_race"     => true,
      # The switch ESCAPE reason built on the same helper, kept separate and OFF.
      # Phase A measured stock Reborn refusing to leave a race it loses by a whole turn
      # even with an immune bench available (shouldSwitch? = -50), so this is a
      # Radical-Red-cited experiment the A/B can turn on, not a reproduction. The
      # switch programme was closed on evidence (PORTABLE-AI-DIAGNOSIS.md §4) and this
      # must not reopen it by default.
      "damage_race_switch" => false,
      # Doubles-only rules: partner absorbs, redirection, partner healing, and the
      # flatter value of priority when a second foe acts regardless.
      "format_rules"    => true,

      # 0.6.2 bugfix batch. Every one of these was READ OFF a turn-by-turn readout of
      # the 0.6.1 set_c run, not proposed from the source
      # (PORTABLE-AI-REBORN.md, "Turn-by-turn readout pass on set_c"), and each is its
      # own key so the batch can be ablated one row at a time. ALL SEVEN FALSE
      # REPRODUCES 0.6.1 BATTLE-FOR-BATTLE -- that control run is what makes any
      # number from this version mean anything.
      #
      # A spread move carries no registration target, so target_for returned nil and
      # every Earthquake was scored against a phantom 100% target: never lethal, and
      # ko_never_lands could not fire for it either. Read the adapter's exported
      # target_hp_pct instead.
      "spread_target_hp" => true,
      # A knockout is a knockout: once lethal, the type-effectiveness term and the
      # secondaries that only matter to a survivor stop counting, so accuracy decides
      # between two kills. Fire Blast (85%) was beating Dragon Claw (100%) for the
      # same KO purely on the super-effective bonus.
      "lethal_flat"      => true,
      # Charge a switch candidate that is dead before it moves. score_switch already
      # computed the subtraction for preserve_low_hp_actor and never rejected on it.
      "entry_death"      => true,
      # Wish re-clicked with a Wish already pending. The adapter now reports
      # PBEffects::Wish through effect_active, the same channel the screens use.
      "wish_pending"     => true,
      # first_setup was decided by a memory counter that apply_memory zeroes on any
      # non-setup action, so a +2 sweeper that attacked once was "first setting up"
      # again. Drive it off the stages the actor is actually carrying.
      "setup_stage"      => true,
      # Do not re-click a move that failed last turn against the same target. Reborn
      # keeps the flag itself for Stomping Tantrum (PBEffects::Tantrum); this reads it.
      "move_memory"      => true,
      # Yawn into an already-drowsy target. Same bug class as 0.6.1's Leech Seed: the
      # move writes an EFFECT, not a status condition, so pbCanSleep? answers "yes"
      # about a target the engine will refuse (PokeBattle_MoveEffects.rb:249).
      "yawn_gate"        => true,

      # 0.6.3. Two rules read off the Realidea shadow run's turn-by-turn readout, where
      # the same three battles were losing races with a better Pokemon on the bench and
      # every switch vetoed for want of a reason (PORTABLE-AI-REALIDEA.md, "0.6.3").
      # Each is its own key; BOTH FALSE REPRODUCES 0.6.2 BATTLE-FOR-BATTLE.
      #
      # Leave a race this battler loses for a bench candidate that wins it -- per
      # candidate, on the candidate's own estimates, after paying the switch turn; and
      # only when no recovery move the actor carries would turn the race around. The
      # 0.6.0 damage_race_switch flag opened the gate for every candidate; this asks who.
      "race_switch_to_winner" => true,
      # A heal that restores less than the next hit takes, in a race already lost, is
      # charged as heal_only_delays (-120) instead of credited as heal_saves_battler
      # (+150). Zapdos Roosted into a bigger Lava Plume five turns running.
      "heal_outpace"          => true,
      # "I cannot hurt it" (no_effective_move, weak_current_attacks) opens the gate
      # only for a bench candidate whose own best hit clears the weak line. Against a
      # wall every attacker is weak, and without this the bench body that came in was
      # as weak as the one that left and went straight back.
      "escape_needs_hitter"   => true,

      # 0.6.4. Two refinements of the 0.6.3 rules, read off the same readouts, and one
      # estimate fix. ALL THREE FALSE REPRODUCES 0.6.3 BATTLE-FOR-BATTLE.
      #
      # Every switch candidate -- the post-KO replacement included -- is graded on who
      # lands the last hit once it is in, after hazards and the free entry hit, by
      # the margin in hits (Core.kill_order_grade). Replaces the flat 110 of
      # losing_race_bench_wins, which keeps its gate and gives up its score.
      #
      # OFF BY DEFAULT, on measurement: the probe and the cards say it does what it
      # says, and the gauntlets say it costs wins -- Reborn 231 -> 219 / 420 alone
      # (p = 0.07), 224 with its penalties removed, Realidea +5/-7 -- concentrated in
      # one bulky roster. Same disposition as damage_race_switch in 0.6.0: an
      # experiment the A/B can turn on, not a default.
      "switchin_race_grade"   => false,
      # A bench body opens the "I cannot hurt it" gate only if it beats the actor at
      # the actor's own game: two whole hits fewer to the knockout and no more than
      # four of its own. Refines escape_needs_hitter (inert without it): 62 of the
      # 133 switch-backs left at 0.6.3 were a body that cleared the 10% line on the
      # bench and not on the field.
      "escape_wall_margin"    => true,
      # Adapter-side (rule_enabled?): a bench candidate's outgoing estimate skips a
      # move with no PP left, as the field view already does. Found in the 0.6.4
      # trace: the switch-backs that survived the wall margin were two bodies whose
      # attacks were all spent, each "hitting for 27%" on the bench and for nothing
      # on the field.
      "switch_estimate_pp"    => true,

      # 0.6.5. The party x party damage matrix and the two rules that read it. Every
      # scoring rule goes inert when snapshot["matrix"] is absent, so the Reborn build
      # is untouched and its gauntlet is this version's control. ALL THREE FALSE
      # REPRODUCES 0.6.4 BATTLE-FOR-BATTLE -- and so does party_matrix alone, because
      # building and exporting the matrix changes no decision by itself.
      #
      # Adapter-side (rule_enabled?), and the one of the three that ships ON: it
      # builds snapshot["matrix"] and puts the grid in the trace. Every 0.6.3 and
      # 0.6.4 rule was read off a readout, and a readout cannot show what was never
      # exported. Cached against a per-slot signature, so steady-state cost is the
      # dirty rows only.
      "party_matrix"          => true,
      # The only answer to a foe still on their bench is not a body to spend in front
      # of a foe it loses to (Core.sole_answer_value). Shipped ON, on the paired
      # gauntlet: 84-26-4 against the control's 83-28-4 over 240 tier battles, gained
      # 2 and lost 0, with the stock arm bit-identical. Two battles is weak evidence
      # (p = 0.48) and both are in gen6ou_a, but the disposition rule is the one
      # escape_wall_margin shipped under in 0.6.4 at +1/-0, and Reborn exports no
      # matrix, so this cannot reach the other study at all.
      "sole_answer"           => true,
      # The first boost is worth the cells it flips across their party, instead of a
      # flat 55 (Core.setup_matrix_value). Also ON: 84-27-4, gained 1 lost 0 -- but
      # only after the tier run found the budget test refusing a boost on a TIE and
      # losing two battles for it. As first written it measured 82-29-4, gained 1 lost
      # 2. The rule that survived is the narrow one: refuse only what is strictly
      # unaffordable, and where there is nothing better to say than the flat 55, say
      # nothing.
      "setup_matrix"          => true
    }

    def self.config(overrides)
      out = {}
      DEFAULT_CONFIG.each { |k, v| out[k] = v }
      (overrides || {}).each { |k, v| out[k.to_s] = v }
      out
    end

    def self.validate(snapshot)
      raise ArgumentError, "snapshot must be a Hash" if !snapshot.is_a?(Hash)
      actors = snapshot["actors"]
      targets = snapshot["targets"]
      raise ArgumentError, "snapshot actors must be a non-empty Array" if !actors.is_a?(Array) || actors.empty?
      raise ArgumentError, "snapshot targets must be an Array" if !targets.is_a?(Array)
      actors.each do |actor|
        raise ArgumentError, "actor must be a Hash" if !actor.is_a?(Hash)
        raise ArgumentError, "actor index missing" if actor["index"].nil?
        actions = actor["actions"]
        raise ArgumentError, "actor actions must be an Array" if !actions.is_a?(Array)
        actions.each do |action|
          validate_action(action)
        end
      end
      true
    end

    def self.validate_action(action)
      raise ArgumentError, "action must be a Hash" if !action.is_a?(Hash)
      kind = action["type"]
      raise ArgumentError, "unknown action type #{kind.inspect}" if kind != "move" && kind != "switch"
      raise ArgumentError, "action slot missing" if action["slot"].nil?
      if kind == "move"
        raise ArgumentError, "move id missing" if action["move_id"].nil?
      end
      true
    end

    def self.number(value, fallback)
      return fallback if value.nil?
      value.to_f
    rescue
      fallback
    end

    def self.truthy(value)
      value == true || value == 1 || value == "1" || value == "true"
    end

    def self.copy_hash(source)
      out = {}
      (source || {}).each { |k, v| out[k] = v }
      out
    end
  end
end
