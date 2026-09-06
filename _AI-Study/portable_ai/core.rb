# Engine-independent battle decision module.
# Requires model.rb and effects.rb to have been loaded first.

module PortableAI
  HARD_REJECT = -1000000

  def self.plan(snapshot, config, rng)
    Model.validate(snapshot)
    cfg = Model.config(config)
    random = rng || Kernel
    scored_by_actor = []

    snapshot["actors"].each do |actor|
      scored = []
      actor["actions"].each do |action|
        candidate = score_action(snapshot, actor, action, cfg, random)
        scored << candidate
      end
      raise ArgumentError, "actor #{actor['index']} has no usable actions" if scored.empty?
      scored.sort! { |a, b| compare_candidates(a, b) }
      scored_by_actor << scored
    end

    selected, joint = choose_joint(snapshot, scored_by_actor, cfg)
    updates = memory_updates(selected)
    {
      "actions" => selected,
      "memory_updates" => updates,
      "diagnostics" => {
        "version" => VERSION,
        "format" => snapshot["format"] || (snapshot["actors"].length > 1 ? "double" : "single"),
        "joint_adjustment" => joint,
        "candidate_counts" => scored_by_actor.map { |items| items.length },
        "rankings" => scored_by_actor
      }
    }
  end

  def self.score_action(snapshot, actor, action, config, rng)
    out = Model.copy_hash(action)
    out["actor_index"] = actor["index"] if out["actor_index"].nil?
    reasons = []
    score = Model.number(action["base_score"], 0.0)
    reasons << ["engine_base", score]

    if action["type"] == "switch"
      score = score_switch(snapshot, actor, action, config, score, reasons)
    else
      score = score_move(snapshot, actor, action, config, score, reasons)
    end

    adjustment = Model.number(action["score_adjustment"], 0.0)
    if adjustment != 0
      score += adjustment
      reasons << ["adapter_adjustment", adjustment]
    end

    noise = Model.number(config["noise"], 0.0)
    if !config["deterministic"] && noise > 0
      roll = rng.rand((noise * 2).to_i + 1) - noise
      score += roll
      reasons << ["difficulty_noise", roll]
    end

    out["score"] = score
    out["reasons"] = reasons
    out
  end

  def self.score_move(snapshot, actor, action, config, score, reasons)
    move_id = action["move_id"].to_s.upcase
    tags = Effects.describe(move_id, action["tags"])
    out_score = score
    target = target_for(snapshot, action["target"])
    actor_hp = Model.number(actor["hp_pct"], 100.0)
    target_hp = target ? Model.number(target["hp_pct"], 100.0) : 100.0
    # A spread move carries no registration target -- the adapter sets
    # action["target"] = nil because there is no single battler to register against
    # (Portable_AI_Adapter.rb:551) -- so target_for returns nil and this defaulted to a
    # phantom 100% target. Earthquake and Lava Plume therefore NEVER reached `lethal`,
    # at any target HP, and ko_never_lands could not fire for them either. The adapter
    # exports the scoring target's own HP on every action (:638); read that instead.
    if !target && config["spread_target_hp"] && !action["target_hp_pct"].nil?
      target_hp = Model.number(action["target_hp_pct"], 100.0)
    end
    damage = Model.number(action["expected_damage_pct"], 0.0)
    effectiveness = Model.number(action["effectiveness"], 1.0)

    if Model.truthy(action["immune"]) || (Model.truthy(action["damaging"]) && effectiveness <= 0)
      reasons << ["immune", HARD_REJECT]
      return HARD_REJECT
    end

    # A move the engine refused last turn against this same target will be refused
    # again: the board has not moved. Reborn keeps the flag itself for Stomping
    # Tantrum (PBEffects::Tantrum, PokeBattle_Battler.rb:5085) and the adapter reads it
    # back on the action. Bisharp clicked a dead Sucker Punch three turns running with
    # a guaranteed Knock Off KO one point behind (bulky_vs_offense 196613 t22-24), so
    # this is deliberately larger than that gap and smaller than a kill call.
    if config["move_memory"] && Model.truthy(action["failed_last_turn"])
      out_score -= 200
      reasons << ["failed_last_turn", -200]
    end

    lethal = false
    faster = faster_flag(actor)

    if Model.truthy(action["damaging"])
      lethal = damage >= target_hp && target_hp > 0

      # NOTE on Sturdy and Focus Sash. 0.5.0 first cancelled the kill call here --
      # lethal = false, damage := target_hp - 1 -- on the argument that a hit leaving
      # the target on 1 HP is not a knockout. It was WITHDRAWN before release, for
      # three reasons that are worth keeping written down:
      #
      #  * Reborn does not do it. Its notOHKO? (:17401) exists to pay a MULTI-HIT move
      #    x1.3 for beating the guard (:7389); it never removes a single-hit move's own
      #    kill score. The multi-hit row in side_effect_rules is that same fact, and it
      #    is what the corpus cards (sturdy_blocks_the_kill_call, focus_sash_same_as_
      #    sturdy, sash_ignored_when_not_full_hp) actually decide on -- none of them
      #    ever touched this block.
      #  * The cost was out of proportion to the information. Cancelling lethal takes
      #    about 420 points off the strongest move, which is far more than "you will
      #    need a second hit" is worth: hitting hard is still right, because breaking
      #    the guard is what makes the next hit lethal.
      #  * It measured badly and it is the only ability row that could. Of the six
      #    ability rows, Unaware, Contrary, Justified and Regenerator are all INERT on
      #    set_a..e (the gauntlet builds every mon with setAbility(0) and no roster mon
      #    carries them in slot 0), so ability_rules on those rosters was essentially
      #    this row plus the status-deterrent table -- and turning ability_rules off
      #    was worth +3 wins over 120 battles.
      #
      # The knowledge is still worth having for the priority gate and the heal gate,
      # which read `lethal`; reinstating it needs a form that does not also delete the
      # move's value, and a roster on which the rest of the table is not inert.
      priority = Model.number(action["priority"], 0)

      # A knockout only counts if it lands. When the actor is slower and the foe's
      # best move already kills it, a non-priority "KO" resolves after the actor is
      # gone, so it is worth its damage and nothing more (Reborn :2855-2923).
      if lethal && config["priority_gate"] && faster == false && priority <= 0 &&
         certain_lethal_threat?(actor, config)
        lethal = false
        reasons << ["ko_never_lands", 0]
      end

      if lethal
        value = 500.0
        out_score += value
        reasons << ["lethal", 500]
      elsif damage > 0
        value = [damage, 100.0].min * 0.8
        out_score += value
        reasons << ["expected_damage", value]
      else
        value = 0.0
      end

      # Reborn scales every move score by (accuracy + 100) / 200 (:3349), which is
      # what makes an accurate KO beat an inaccurate one -- Portable had no accuracy
      # term at all and over-clicked Fire Blast, Stone Edge and Focus Blast. Only the
      # damage terms are scaled; the type and tag rules keep their full weight.
      if value > 0
        factor = accuracy_factor(action, config)
        if factor != 1.0
          adjust = value * factor - value
          out_score += adjust
          reasons << ["accuracy", adjust]
        end
      end

      # Priority is worth most exactly where it is the only way the KO happens.
      if config["priority_gate"] && lethal && priority > 0 && !faster.nil?
        bonus = faster ? 60 : 150
        bonus += 200 if !faster && threatened_lethal?(actor)
        # A second foe acts whichever order this one resolves in, so moving first buys
        # much less: Reborn drops priority from x2 to x1.3 in doubles (:2856), and the
        # probe measured Aqua Jet at 242 in singles against 157 in the same doubles
        # position. Flat 60 rather than a scaled 150.
        if config["format_rules"] && doubles?(snapshot) && bonus > 60
          bonus = 60
          reasons << ["priority_flat_in_doubles", 0]
        end
        out_score += bonus
        reasons << ["priority_finisher", bonus]
      end

      # Once the move kills, the type chart has already said everything it has to say:
      # both kills remove the same battler, so the only thing left to choose on is
      # which one lands. Fire Blast at 85% was beating Dragon Claw at 100% for the same
      # KO on a 70-point super-effective bonus against a 45-point resist penalty
      # (bulky_vs_offense 196613 t4: 649 against 555). flat_kill also drops the
      # secondaries that only pay out on a survivor -- see side_effect_rules.
      #
      # NOT applied to a SPREAD action, which is a summary of several targets rather
      # than one kill: its damage is the sum over the foes and its effectiveness is a
      # standing measure of how much of the field the move resolves, which is exactly
      # what choose_joint weighs it against. Dropping the term there cost Garchomp a
      # double kill it had been finding since 0.4.0 -- d_spread_kills_both_preferred,
      # caught by the corpus on the first 0.6.2 probe (Earthquake 740 -> 600, and the
      # split-fire pair's coordination bonus then won by 66 points).
      flat_kill = lethal && config["lethal_flat"] && !Model.truthy(action["spread"])
      if flat_kill
        reasons << ["lethal_flat", 0]
      elsif effectiveness > 1
        bonus = 35 * effectiveness
        out_score += bonus
        reasons << ["super_effective", bonus]
      elsif effectiveness > 0 && effectiveness < 1
        out_score -= 45
        reasons << ["resisted", -45]
      end

      if config["side_effects"]
        out_score = side_effect_rules(snapshot, actor, action, tags, target,
                                      damage, lethal, faster, out_score, reasons,
                                      flat_kill)
      end
      if config["ability_rules"]
        out_score = damaging_ability_rules(action, target, lethal, out_score, reasons)
      end
    end

    if tags.include?("heal") || tags.include?("variable_heal")
      if actor_hp >= 85
        out_score -= 500
        reasons << ["heal_near_full", -500]
      elsif actor_hp <= 35
        bonus = 220 + (35 - actor_hp) * 3
        out_score += bonus
        reasons << ["heal_low_hp", bonus]
      elsif actor_hp <= 60
        out_score += 90
        reasons << ["heal_mid_hp", 90]
      end
      if config["heal_gate"]
        out_score = heal_gate(snapshot, actor, action, tags, out_score, reasons, config)
      elsif threatened_lethal?(actor)
        out_score -= 80
        reasons << ["heal_under_lethal_threat", -80]
      end
    elsif tags.include?("delayed_heal")
      # Wish fails outright with a Wish already pending (PokeBattle_MoveEffects.rb:6084
      # returns -1 and displays "But it failed!"). Same channel the screens use: the
      # adapter reports PBEffects::Wish through effect_active.
      if config["wish_pending"] && Model.truthy(action["effect_active"])
        out_score -= 300
        reasons << ["delayed_heal_pending", -300]
      elsif actor_hp >= 90
        out_score -= 300
        reasons << ["delayed_heal_near_full", -300]
      elsif actor_hp <= 55
        out_score += 100
        reasons << ["delayed_heal_useful", 100]
      end
    end

    if tags.include?("status")
      if target && occupied_status?(target["status"])
        out_score -= 450
        reasons << ["target_already_statused", -450]
      elsif target && Model.truthy(target["status_immune"])
        out_score -= 450
        reasons << ["target_status_immune", -450]
      else
        out_score += 25
        reasons << ["fresh_status", 25]
        if config["ability_rules"] && !Model.truthy(action["damaging"])
          out_score = status_deterrent_rule(action, tags, target, out_score, reasons)
        end
      end
    end

    if config["side_effects"]
      out_score = turn_shape_rules(snapshot, actor, action, tags, faster,
                                   out_score, reasons)
    end
    if config["format_rules"]
      out_score = format_rules(snapshot, actor, action, tags, out_score, reasons)
      return HARD_REJECT - 1 if out_score <= HARD_REJECT
    end

    if tags.include?("setup")
      repeats = config["memory"] ? memory_count(snapshot, actor["index"], "setup") : 0
      # The memory counter alone answers "did I set up on the PREVIOUS action", because
      # apply_memory zeroes every counter but the one it just incremented
      # (Portable_AI_Adapter.rb:1487). One attack in between and a +2 sweeper was
      # "first setting up" all over again -- Heracross took a second Swords Dance at
      # 31% HP that way (bulky_vs_offense 196613 t20). The stages the actor is standing
      # in are the durable record of the same fact, and one setup move is worth about
      # two stages (Swords Dance +2, Dragon Dance +1/+1, Calm Mind +1/+1).
      if config["setup_stage"]
        carried = Model.number(actor["positive_stage_total"], 0).to_i / 2
        repeats = carried if carried > repeats
      end
      if config["ability_rules"] && actor_ability(actor) == "CONTRARY"
        # Contrary turns every boost into a drop. Reborn does not have this row at all;
        # it is here because a Contrary user clicking Swords Dance is strictly harming
        # itself, which no amount of engine damage data reveals.
        out_score -= 300
        reasons << ["contrary_setup", -300]
      elsif config["ability_rules"] && target_fact(action, target, "ability") == "UNAWARE"
        # Boosting in front of Unaware achieves nothing: it reads through the stages.
        # Reborn halves the setup score (:4966); -150 is that halving in score units.
        out_score -= 150
        reasons << ["setup_vs_unaware", -150]
      elsif actor_hp <= 30 || threatened_lethal?(actor)
        out_score -= 240
        reasons << ["unsafe_setup", -240]
      elsif setup_into_2hko?(snapshot, actor, target, config)
        # Being 2HKOed while SLOWER means the boost never gets used: the foe's second
        # hit lands before the boosted attack does. Reborn charges x0.4 for exactly
        # this (:6007) on top of the x0.8/x0.3 a status move already pays; against a
        # ~450-point setup score that is about -180.
        #
        # The `faster == false` clause is NOT an inference from the source, it is a
        # measurement: on one board with +2 Speed and nothing else changed, stock
        # Reborn's Swords Dance went from 9 to 46 (PORTABLE-AI-REBORN.md, "0.6.0 Phase
        # A"). What refuses the setup there is the speed order, not the race, and a
        # faster mon setting up into a 2HKO is behaviour the reference endorses.
        #
        # Departure from the reference, recorded because a future agent comparing
        # against Reborn will otherwise read it as a bug: Reborn's gate also requires
        # `stats[PBStats::ATTACK]==1`, and `stats` holds STAGES, so its own rule
        # silently skips every +2 move (Swords Dance, Nasty Plot) and only ever
        # reaches +1 moves. That is a quirk of how the gate was written, not a claim
        # about play, so this rule applies to any setup tag.
        out_score -= 180
        reasons << ["setup_into_2hko", -180]
      elsif repeats == 0
        out_score += 55
        reasons << ["first_setup", 55]
      else
        penalty = 100 * repeats
        out_score -= penalty
        reasons << ["repeated_setup", -penalty]
      end
    end

    if tags.include?("hp_cost_half") && actor_hp <= 50
      out_score -= 600
      reasons << ["hp_cost_unaffordable", -600]
    end

    if config["self_cost"] && tags.include?("self_drop")
      if config["ability_rules"] && actor_ability(actor) == "CONTRARY"
        # The same ability read the other way round: Draco Meteor's -2 becomes +2, so
        # the move Portable is charged 40 for is the one a Contrary user wants most.
        out_score += 40
        reasons << ["contrary_boost", 40]
      else
        penalty = lethal ? 15 : 40
        out_score -= penalty
        reasons << ["self_stat_drop", -penalty]
      end
    end

    if config["self_cost"] && tags.include?("self_ko")
      # Fainting on purpose is a trade. It is not one with nothing left to send out --
      # the battle ends there -- and it is not one while healthy: Reborn's deathcode
      # (:7779) scales the score by 1 - hp% and lands at 0.14 at full HP, where
      # Portable exploded 15 times out of 21.
      reserves = Model.number(action["own_reserves"], 0)
      trade = reserves > 0 && (actor_hp < 30 || threatened_lethal?(actor))
      if !trade
        out_score -= 400
        reasons << ["self_ko_cost", -400]
      end
    end

    if tags.include?("charge_solar") && snapshot["weather"] != "sun"
      out_score -= 120
      reasons << ["charge_turn_without_sun", -120]
    end

    if tags.include?("force_switch")
      layers = Model.number(action["foe_hazard_layers"], 0)
      boosts = Model.number(action["target_positive_stages"], 0)
      bonus = layers * 15 + boosts * 25
      if bonus > 0
        out_score += bonus
        reasons << ["phaze_value", bonus]
      end
    end

    if tags.include?("protect") || tags.include?("team_protect")
      repeats = config["memory"] ? memory_count(snapshot, actor["index"], "protect") : 0
      if repeats > 0
        penalty = 140 * repeats
        out_score -= penalty
        reasons << ["repeated_protect", -penalty]
      end
    end

    if tags.include?("substitute")
      if actor_hp <= 25
        out_score -= 500
        reasons << ["cannot_afford_substitute", -500]
      elsif config["memory"] && memory_count(snapshot, actor["index"], "substitute") > 0
        out_score -= 250
        reasons << ["substitute_already_used", -250]
      end
    end

    if tags.include?("hazard")
      layers = Model.number(action["existing_layers"], 0).to_i
      maximum = Model.number(action["max_layers"], 1).to_i
      if layers >= maximum
        out_score -= 500
        reasons << ["hazard_at_cap", -500]
      elsif action.key?("hazard_targets") && Model.number(action["hazard_targets"], 0) <= 0
        out_score -= 600
        reasons << ["hazard_hits_nobody", -600]
      elsif Model.number(action["foe_reserves"], 0) <= 0
        out_score -= 180
        reasons << ["hazard_no_reserves", -180]
      end
    end

    if tags.include?("hazard_remove") && Model.number(action["own_hazard_layers"], 0) <= 0
      out_score -= 300
      reasons << ["no_hazards_to_remove", -300]
    end

    if tags.include?("screen") && Model.truthy(action["effect_active"])
      out_score -= 400
      reasons << ["screen_already_active", -400]
    end

    if tags.include?("baton_pass") && Model.number(action["own_reserves"], 0) <= 0
      out_score -= 600
      reasons << ["baton_pass_no_bench", -600]
    end

    # A non-damaging move aimed at the partner is hostile unless it is an actual
    # support move: statusing or disrupting your own side is never worth a turn.
    if Model.truthy(action["friendly_target"]) && !Model.truthy(action["damaging"]) &&
       !tags.include?("partner_support") && !tags.include?("redirect") &&
       !tags.include?("heal")
      reasons << ["hostile_move_at_partner", HARD_REJECT]
      return HARD_REJECT
    end

    friendly = Model.number(action["friendly_fire_pct"], 0.0)
    if friendly > 0
      if Model.truthy(action["friendly_target"])
        reasons << ["targeted_friendly_fire", HARD_REJECT]
        return HARD_REJECT
      end
      partner_hp = Model.number(action["partner_hp_pct"], 100.0)
      penalty = friendly * 3
      penalty += 700 if friendly >= partner_hp
      out_score -= penalty
      reasons << ["friendly_fire", -penalty]
    end

    if move_id == "THUNDER"
      if snapshot["weather"] == "rain"
        out_score += 100
        reasons << ["thunder_in_rain", 100]
      else
        out_score -= 100
        reasons << ["thunder_without_rain", -100]
      end
    end

    out_score
  end

  # Reasons that, on their own, justify leaving. Modelled on Reborn's
  # shouldSwitchintense? (PokeBattle_AI_2.rb:13713), which builds its switch score
  # purely from affirmative escape reasons — residual damage, its own debuffs, Yawn,
  # Perish Song — and never reads the opponent's stat stages. Deliberately excluded:
  # "matchup" and "engine_base" (type chart and HP, which are near-constant and were
  # the thing switching used to win on), and "preserve_low_hp_actor", which fires
  # exactly where Intense switches least — it never once switched below 30% HP across
  # 180 measured battles.
  # "escape_lethal_threat" opens the gate only above HEALTHY_PIVOT_HP_PCT.
  # threatened_lethal? is incoming_damage_pct >= hp_pct, which conflates two different
  # situations: a healthy battler facing a genuine hard counter (Garchomp into Lapras —
  # a real matchup problem, and a legitimate pivot the scenario corpus requires), and a
  # battler at 20% HP that everything threatens (not a matchup problem, just accumulated
  # damage). Counting both licensed exactly the switches this gate exists to stop: the
  # first gated run left switches-below-30%-HP unchanged at 2.09/battle. Intense treats
  # a weak battler as a reason to *stay* — shouldSwitchintense? subtracts 100 below 30%
  # HP for non-sweepers — and spends it attacking. Below the threshold the bonus still
  # applies once some other reason has opened the gate; it just cannot open it alone.
  HEALTHY_PIVOT_HP_PCT = 50

  # A boosted foe must not be able to open the gate by itself. A foe at +2 roughly
  # doubles its output, so it turns threatened_lethal? on without the matchup having
  # changed at all — and HEALTHY_PIVOT_HP_PCT then licenses the switch precisely when
  # the battler is healthy, which is the worst moment to leave: the switch-in eats a
  # free boosted hit and the boost is still there afterwards. Measured over 180 fair
  # baseline battles, Reborn-Normal switched 0 times out of 173 while the foe was at
  # >= +2, whereas 49 of Portable 0.3.0's 451 switches happened there — 10.9% of its
  # switching in 5.8% of its turns.
  #
  # Only the lethal-threat reason is suppressed. Every other escape reason (no
  # effective move, crushed stats, Yawn, residual chip) is a fact about this battler
  # that a foe's boosts did not manufacture, so a boosted foe does not veto those.
  BOOST_SUPPRESSES_LETHAL_ESCAPE = 2

  # Type-matchup units as the adapters hand them over: a single neutral verdict is 4 on
  # Reborn's chart and is scaled x8, so neutral lands on 32, resisted 16, immune 0,
  # super-effective 64 and doubly so 128. How hard the defensive term pulls against the
  # offensive one is the "switch_risk_weight" config key, defaulted in
  # Model::DEFAULT_CONFIG.
  NEUTRAL_TYPE_MATCHUP = 32

  SWITCH_ESCAPE_REASONS = %w[
    no_effective_move clear_crushed_stats clear_bad_stats weak_current_attacks
    escape_yawn escape_residual_chip escape_lethal_threat_while_healthy
    losing_damage_race losing_race_bench_wins
  ]

  # Highest positive stage total among the opposing active battlers.
  def self.foe_boost_total(snapshot)
    best = 0
    (snapshot["targets"] || []).each do |target|
      total = Model.number((target || {})["positive_stages"], 0)
      best = total if total > best
    end
    best
  end

  def self.score_switch(snapshot, actor, action, config, score, reasons)
    if !config["switching"] && !Model.truthy(action["forced"])
      reasons << ["switching_disabled", HARD_REJECT]
      return HARD_REJECT
    end

    out_score = score + Model.number(action["matchup_score"], 0)
    reasons << ["matchup", Model.number(action["matchup_score"], 0)]

    # "matchup" is offence only. Weigh what the incoming Pokemon will eat the same way,
    # symmetrically around neutral, so resisting the foe is worth as much as threatening
    # it and walking a Pokemon into a super-effective STAB costs what it should. Only
    # applies once a switch is happening; it never argues for or against leaving, just
    # for who goes in. Absent (older adapters, forced switches) it contributes nothing.
    weight = Model.number(config["switch_risk_weight"],
                          Model::DEFAULT_CONFIG["switch_risk_weight"])
    # When the adapter can estimate what the candidate ACTUALLY eats on the way in --
    # a real damage roll against a fake battler, with the candidate's own Intimidate
    # already applied to the foes -- that replaces the type proxy rather than joining
    # it. The proxy pays (32 - risk) * weight, so +32w for an immunity and -96w for a
    # 4x hit; 25% incoming is mapped to neutral and 100% to the 4x end, which puts the
    # real number on exactly the scale the rest of the switch score was tuned against.
    real_incoming = config["entry_rules"] && action.key?("incoming_damage_pct")
    if action.key?("incoming_risk") && weight != 0 && !real_incoming
      risk = Model.number(action["incoming_risk"], NEUTRAL_TYPE_MATCHUP)
      adjust = (NEUTRAL_TYPE_MATCHUP - risk) * weight
      out_score += adjust
      reasons << ["incoming_risk", adjust]
    elsif real_incoming && weight != 0
      incoming = Model.number(action["incoming_damage_pct"], 0.0)
      adjust = (25.0 - incoming) * 1.28 * weight
      out_score += adjust
      reasons << ["entry_incoming_damage", adjust]
    end

    # WHO COMES IN, rather than whether to leave -- so this is the one race consumer
    # that also applies to a forced switch, which is the post-KO replacement Radical
    # Red designed its table for (ANALYSIS.md :655-684). A candidate whose two damage
    # estimates the adapter could not build contributes nothing.
    #
    # Both halves are Reborn-measured, not guessed. Phase A put two identical
    # Mamoswine on the bench differing only in an Assault Vest -- one incoming number,
    # nothing else -- and stock scored them 257 against -175.8; two identical Ampharos
    # differing only in 252 Speed EVs scored 193 against 115.8, so outspeeding alone
    # is worth about +77 in Reborn's units (:11755-11764 scales a switch-in's damage
    # output x1.5 when it outruns the foe and x0.75 when it does not). Radical Red
    # pays a flat +14 for the same fact; scaled x5 into Portable's units -- where a
    # neutral matchup is 32 and one super-effective step is another 32 -- that is +70,
    # which is within rounding of what Reborn actually pays.
    if config["damage_race"] && action.key?("outgoing_damage_pct") &&
       action.key?("incoming_damage_pct")
      bonus = switchin_race_bonus(action)
      if bonus != 0
        out_score += bonus
        reasons << ["switchin_race", bonus]
      end
    end
    # 0.6.4. The other half of the same question: not only how long the candidate
    # LASTS but who lands the last hit once it is in -- candidate_race, the full
    # exchange after the entry damage (hazards plus the free hit) is paid, graded by
    # the margin in hits. Every switch candidate carries it, the post-KO replacement
    # included, which is what the readout kept asking for: Scizor sent into a Heatran
    # that kills it first with Slowbro on the bench (team3_vs_team2 155921 t29). The
    # defensive bands above are Reborn's measured switch-in and stay as they are; this
    # is the term neither Reborn nor the bands have.
    if config["switchin_race_grade"] && config["damage_race"]
      grade = candidate_race_grade(snapshot, action)
      if grade != 0
        out_score += grade
        reasons << ["kill_order", grade]
      end
    end
    escapes = []

    if Model.truthy(action["forced"])
      out_score += 1000
      reasons << ["forced_switch", 1000]
    end
    # 0.6.3. "I cannot hurt it" is a reason to leave only for a body that can. Against
    # a wall every attacker's moves are weak, so these two reasons opened the gate for
    # whoever stood there, the bench Pokemon that came in was as weak as the one that
    # left, and it went straight back: 168 of the 193 switch-backs against an
    # unchanged foe in the first 0.6.3 Realidea run were Zapdos and Suicune trading
    # places in front of a Chansey on weak_current_attacks. The candidate's own
    # estimate is on the action; absent (older adapters), the reasons keep their
    # 0.6.2 shape and the candidate is not held to a number nobody computed.
    hitter = candidate_can_hit?(snapshot, actor, action, config)
    if Model.truthy(actor["no_effective_move"])
      if hitter == false
        reasons << ["bench_cannot_hit_either", 0]
      else
        out_score += 260
        reasons << ["no_effective_move", 260]
        escapes << "no_effective_move"
      end
    end
    negative_stages = Model.number(actor["negative_stage_total"], 0)
    if negative_stages <= -6
      bonus = [(-negative_stages) * 35, 350].min
      out_score += bonus
      reasons << ["clear_crushed_stats", bonus]
      escapes << "clear_crushed_stats"
    elsif negative_stages <= -3
      out_score += 90
      reasons << ["clear_bad_stats", 90]
      escapes << "clear_bad_stats"
    end
    if Model.number(actor["best_damage_pct"], 100) < 10
      if hitter == false
        reasons << ["bench_as_weak", 0]
      else
        out_score += 120
        reasons << ["weak_current_attacks", 120]
        escapes << "weak_current_attacks"
      end
    end
    if Model.truthy(actor["yawned"])
      out_score += 300
      reasons << ["escape_yawn", 300]
      escapes << "escape_yawn"
    end
    residual = Model.number(actor["residual_damage_pct"], 0)
    if residual >= 20
      bonus = [residual * 8, 400].min
      out_score += bonus
      reasons << ["escape_residual_chip", bonus]
      escapes << "escape_residual_chip"
    end
    if Model.truthy(actor["trapped"])
      reasons << ["trapped", HARD_REJECT]
      return HARD_REJECT
    end
    if threatened_lethal?(actor)
      out_score += 130
      reasons << ["escape_lethal_threat", 130]
      boosted_foe = foe_boost_total(snapshot) >= BOOST_SUPPRESSES_LETHAL_ESCAPE
      reasons << ["boosted_foe_holds_ground", 0] if boosted_foe
      if !boosted_foe && Model.number(actor["hp_pct"], 100) >= HEALTHY_PIVOT_HP_PCT
        escapes << "escape_lethal_threat_while_healthy"
      end
    end

    # Losing the race by a whole turn, at full health, is the generalisation of
    # escape_lethal_threat_while_healthy from "it kills me in one" to "it kills me in
    # two". OFF BY DEFAULT, and that is a finding rather than caution: the Phase A
    # card race_leave_when_losing_2hko_vs_3hko put a healthy Donphan in front of an
    # Espeon that 2HKOs it with a Psychic-IMMUNE bench available, and stock Reborn's
    # shouldSwitch? came back -50 and never even scored the bench. So the reference
    # does not do this; it is Radical-Red-cited only, the switch programme was closed
    # on evidence (PORTABLE-AI-DIAGNOSIS.md §4), and it must not reopen by default.
    # The boost suppression is the same one escape_lethal_threat carries: a +2 foe
    # manufactures a losing race exactly the way it manufactures a lethal threat.
    if config["damage_race_switch"]
      race = worst_race(snapshot, actor, config)
      if !race.nil? && race["winning"] == false &&
         !race["theirs"].nil? && race["theirs"] <= 2 &&
         Model.number(actor["hp_pct"], 100) >= HEALTHY_PIVOT_HP_PCT &&
         foe_boost_total(snapshot) < BOOST_SUPPRESSES_LETHAL_ESCAPE
        out_score += 110
        reasons << ["losing_damage_race", 110]
        escapes << "losing_damage_race"
      end
    end

    # 0.6.3. Leave a race this battler loses, for a bench candidate that WINS it.
    #
    # The 0.6.0 flag above opens the gate for every candidate once the actor's race is
    # lost, and that is the form the Donphan card sank: stock Reborn never asked whether
    # whoever came in would do any better, and neither did the flag. This one asks per
    # candidate, on the candidate's own two estimates, and pays for the switch turn
    # honestly -- the candidate eats one free hit coming in, then has to land the last
    # hit of the exchange that follows (candidate_race). Read off the Realidea shadow
    # run: 884 turns losing the race at >= 50% HP, 550 of them with a bench switch
    # vetoed by nothing but no_escape_reason -- Quagsire into a Calm Mind Clefable with
    # Magnezone on the bench among them (team1_vs_team2 104729 t0-5).
    #
    # Two things it deliberately does NOT carry over from the flag above. No boost
    # suppression: the foe's stages are already inside the candidate's incoming
    # estimate, so "it wins its race against a +2 foe" is a real claim here, not a
    # manufactured one. No HP floor: a chipped battler that is losing anyway has less
    # to preserve by staying, not more -- it is Zapdos at 13% Roosting into a 57% Lava
    # Plume five turns running with Chansey on the bench (team3_vs_team1 155921
    # t23-28). What it does require is that no recovery move the actor carries would
    # turn the race around: a race counted in hits is not lost by a battler that
    # out-heals the hit (heal_cannot_outpace?).
    if config["race_switch_to_winner"]
      race, foe = worst_race_with_target(snapshot, actor, config)
      if race_lost_by_a_hit?(race) && heal_cannot_outpace?(snapshot, actor)
        bench = candidate_race(action, foe)
        if !bench.nil? && bench["winning"]
          # 0.6.4: the size of the push is the kill_order grade above, so the reason
          # is worth its gate and nothing more; 0.6.3's flat 110 is what the grade
          # key off restores.
          bonus = config["switchin_race_grade"] ? 0 : 110
          out_score += bonus
          reasons << ["losing_race_bench_wins", bonus]
          escapes << "losing_race_bench_wins"
        end
      end
    end
    if config["entry_rules"] && action.key?("entry_damage_pct")
      # The hazard charge is already inside engine_base; recorded as its own reason so
      # a trace can say how much of a switch's cost was the entry rather than the
      # candidate. Zero delta on purpose -- charging it twice was the alternative.
      reasons << ["entry_hazards", 0]
    end
    # Safe entry originally asked only whether the candidate cleared the hazards with
    # 20% to spare. What actually matters is whether it is still alive at the end of
    # the turn it comes in on, which needs the incoming hit as well.
    safe = Model.truthy(action["safe_entry"])
    if config["entry_rules"] && action.key?("entry_damage_pct") &&
       action.key?("incoming_damage_pct")
      safe = Model.number(action["candidate_hp_pct"], 100.0) -
             Model.number(action["entry_damage_pct"], 0.0) -
             Model.number(action["incoming_damage_pct"], 0.0) > 0
    end
    if Model.number(actor["hp_pct"], 100) <= 20 && safe
      out_score += 80
      reasons << ["preserve_low_hp_actor", 80]
    end
    # The same subtraction, read the other way: a candidate that is dead before it acts
    # is not a switch, it is a sacrifice, and score_switch computed this quantity for
    # `safe` without ever rejecting on it. Mandibuzz sent a 58-HP Flygon into Stealth
    # Rock plus a Rapid Spin; it died without moving and Mandibuzz walked back through
    # the rocks (bulky_vs_balance 196613 t51).
    #
    # Charged on the MINIMUM damage roll, so only a candidate that dies on every roll
    # pays, and charged rather than HARD_REJECTed so a forced replacement still ranks
    # the least bad body instead of falling through to slot order.
    #
    # 500, not the ~300 the backlog entry proposed, and the corpus is why: on
    # a_dying_switch_in_is_not_worth_sending the candidate scores 385.9 against a
    # 59.8 move, so 300 left the corpse ahead by 26 points and the card failed on the
    # build that was supposed to fix it. 500 is not a fitted number either -- it is
    # what this scorer already pays for a knockout, and handing the opponent a free one
    # is the same event seen from the other side.
    if config["entry_death"] && config["entry_rules"] &&
       action.key?("entry_damage_pct") && action.key?("incoming_damage_pct")
      left = Model.number(action["candidate_hp_pct"], 100.0) -
             Model.number(action["entry_damage_pct"], 0.0) -
             Model.number(action["incoming_damage_pct"], 0.0) * MIN_DAMAGE_ROLL
      if left <= 0
        out_score -= 500
        reasons << ["dies_on_entry", -500]
      end
    end
    if config["ability_rules"] && actor_ability(actor) == "REGENERATOR" &&
       Model.number(actor["hp_pct"], 100) < 66
      # Reborn INTENDS this (healscore += 40/50 at :13415 and :13792) but the guard is
      # `hp/totalhp < (2/3)`, and (2/3) is Ruby integer division = 0, so it has never
      # once fired. Implemented here as the intent, and deliberately NOT added to
      # SWITCH_ESCAPE_REASONS: regenerating is a discount on leaving, never a reason to.
      out_score += 50
      reasons << ["regenerator_pivot", 50]
    end
    if config["memory"] && memory_count(snapshot, actor["index"], "switch") > 1
      out_score -= 120
      reasons << ["switch_loop", -120]
    end

    # The gate. Without a named reason to leave, the switch is not considered at all,
    # so the actor falls through to its moves — the shape of Reborn Intense's
    # `next if shouldSwitchintense?` (PokeBattle_AI_2.rb:1571), rather than the
    # non-Intense `shouldswitchscore > maxmovescore` comparison at :1576.
    if config["switch_gate"] && escapes.empty? && !Model.truthy(action["forced"])
      reasons << ["no_escape_reason", HARD_REJECT]
      return HARD_REJECT
    end
    reasons << ["escape_reasons", escapes.length] if !escapes.empty?
    out_score
  end

  def self.choose_joint(snapshot, scored_by_actor, config)
    if scored_by_actor.length == 1 || !config["coordination"]
      return [scored_by_actor.map { |items| items[0] }, 0]
    end

    best_actions = nil
    best_score = nil
    best_adjustment = 0
    scored_by_actor[0].each do |left|
      scored_by_actor[1].each do |right|
        adjustment = joint_adjustment(snapshot, left, right)
        score = left["score"] + right["score"] + adjustment
        pair = [left, right]
        if best_score.nil? || score > best_score ||
           (score == best_score && pair_key(pair) < pair_key(best_actions))
          best_actions = pair
          best_score = score
          best_adjustment = adjustment
        end
      end
    end
    [best_actions, best_adjustment]
  end

  def self.joint_adjustment(snapshot, left, right)
    adjustment = 0
    if left["type"] == "switch" && right["type"] == "switch" &&
       left["slot"].to_i == right["slot"].to_i
      return HARD_REJECT
    end

    if single_target_move?(left) && single_target_move?(right) &&
       left["target"] == right["target"]
      target = target_for(snapshot, left["target"])
      hp = target ? Model.number(target["hp_pct"], 100) : 100
      dl = Model.number(left["expected_damage_pct"], 0)
      dr = Model.number(right["expected_damage_pct"], 0)
      if (dl >= hp || dr >= hp) && alternate_live_target?(snapshot, left["target"])
        adjustment -= 400
      elsif dl + dr > hp * 1.5 && alternate_live_target?(snapshot, left["target"])
        adjustment -= 180
      end
    elsif single_target_move?(left) && single_target_move?(right) &&
          left["target"] != right["target"]
      adjustment += 25
      [left, right].each do |action|
        target = target_for(snapshot, action["target"])
        if target && Model.number(target["hp_pct"], 100) <= 35
          quality = Model.number(action["effectiveness"], 1) * 100
          adjustment += quality
        end
      end
    end
    adjustment
  end

  def self.single_target_move?(action)
    return false if action.nil? || action["type"] != "move"
    !Model.truthy(action["spread"]) && !action["target"].nil?
  end

  def self.alternate_live_target?(snapshot, used_index)
    snapshot["targets"].any? do |target|
      target["index"] != used_index && Model.number(target["hp_pct"], 0) > 0
    end
  end

  def self.target_for(snapshot, index)
    return nil if index.nil?
    snapshot["targets"].each { |target| return target if target["index"] == index }
    snapshot["actors"].each { |actor| return actor if actor["index"] == index }
    nil
  end

  def self.occupied_status?(status)
    return false if status.nil? || status == 0 || status == "0"
    value = status.to_s.downcase
    value != "" && value != "none" && value != "healthy"
  end

  # pbRoughDamage is a single deterministic number, but the engine rolls 85-100% of it.
  # A rule that costs a move 400 points should only fire where no roll rescues the
  # battler, so "this hit kills me" is tested against the LOW roll rather than the
  # estimate. The estimate itself still answers the softer question of whether healing
  # might help (threatened_lethal?), which is what earns the bonus.
  MIN_DAMAGE_ROLL = 0.85

  # The incoming hit kills through any damage roll, not merely through the estimate.
  # threatened_lethal? is the softer question and stays what the 0.3.2 rules ask.
  def self.certain_lethal_threat?(actor, config = {})
    hp = Model.number(actor["hp_pct"], 100.0)
    return false if hp <= 0
    incoming = actor["incoming_damage_pct"]
    # Under strict_threat only a hit that cannot fail to happen (100% accurate, foe
    # awake) makes death certain; adapters that export no such figure keep the loose
    # one, so the key is inert where the evidence is missing.
    strict = actor["certain_incoming_damage_pct"]
    incoming = strict if config["strict_threat"] && !strict.nil?
    return Model.truthy(actor["threatened_lethal"]) if incoming.nil?
    Model.number(incoming, 0.0) * MIN_DAMAGE_ROLL >= hp
  end

  # Tri-state speed order: true, false, or nil when the adapter exports none. Rules
  # that would cost the actor points treat nil as "faster", so a missing field never
  # penalises it; the priority gate skips itself entirely instead.
  def self.faster_flag(actor)
    value = actor["faster"]
    return nil if value.nil?
    Model.truthy(value)
  end

  # Reborn's (accuracy + 100) / 200 (PokeBattle_AI_2.rb:3349), softened by
  # config["accuracy_weight"] so 0 reproduces 0.3.2 and 1 is Reborn's own weight.
  # Adapters that export no accuracy contribute nothing.
  def self.accuracy_factor(action, config)
    weight = Model.number(config["accuracy_weight"],
                          Model::DEFAULT_CONFIG["accuracy_weight"])
    return 1.0 if weight == 0
    return 1.0 if !action.key?("accuracy") || action["accuracy"].nil?
    accuracy = Model.number(action["accuracy"], 100.0)
    accuracy = 100.0 if accuracy > 100.0
    accuracy = 0.0 if accuracy < 0
    1.0 + (((accuracy + 100.0) / 200.0) - 1.0) * weight
  end

  # Percentage points of maximum HP a recovery move restores, in the same units as
  # hp_pct and incoming_damage_pct.
  def self.heal_amount(snapshot, tags)
    return 100.0 if tags.include?("heal_full")
    if tags.include?("heal_weather")
      weather = snapshot["weather"]
      return 66.0 if weather == "sun"
      return 25.0 if weather == "sand" || weather == "hail"
    end
    50.0
  end

  # Does healing change who is alive at the end of the turn? Reborn's recovercode
  # (PokeBattle_AI_2.rb:7558) asks that; Portable 0.3.2 scored recovery on the healer's
  # own HP alone, which is why a quarter of its heals were the healer's last act and
  # 61% of the ones below 25% HP were (PORTABLE-AI-DIAGNOSIS.md section 2). These are
  # Reborn's multipliers rewritten as additive score units, plus the question Reborn
  # never asks -- whether it moves first -- which costs Reborn 18% of its own slow
  # heals. The existing hp_pct bonuses stay underneath: this rule only fires when the
  # actor is actually being threatened, so the plain low-HP heal is untouched.
  def self.heal_gate(snapshot, actor, action, tags, score, reasons, config = {})
    hp = Model.number(actor["hp_pct"], 100.0)
    incoming = Model.number(actor["incoming_damage_pct"], 0.0)
    # threatened_lethal is the adapter's own verdict; honour it when the raw number is
    # absent or disagrees.
    incoming = hp if Model.truthy(actor["threatened_lethal"]) && incoming < hp
    heal = heal_amount(snapshot, tags)
    headroom = 100.0 - hp
    heal = headroom if heal > headroom
    heal = 0.0 if heal < 0
    faster = faster_flag(actor)
    # Penalise only what no damage roll can rescue; reward wherever the heal might be
    # what survives the turn.
    will_die = certain_lethal_threat?(actor, config)
    might_die = threatened_lethal?(actor)

    if will_die && faster == false
      score -= 400
      reasons << ["heal_cannot_resolve", -400]
    elsif will_die && incoming * MIN_DAMAGE_ROLL >= hp + heal
      score -= 400
      reasons << ["heal_does_not_save", -400]
    elsif might_die
      # 0.6.3. A heal that restores less than the next hit takes, while the race is
      # already lost, saves nothing: it buys one turn at a net loss and the same
      # question comes back a turn later, a little lower. Zapdos at 13% Roosted +50
      # into a 57% Lava Plume five turns running and every one was scored a save
      # (Realidea shadow run, team3_vs_team1 155921 t23-28; 43 such turns in 3,033,
      # all 43 in a lost race). Charged what heal_losing_race charges outside a
      # threat, because it is the same fact with worse timing -- and so that a bench
      # candidate, once race_switch_to_winner opens the gate, can be heard over it.
      lost = config["heal_outpace"] ? worst_race(snapshot, actor, config) : nil
      if race_lost_by_a_hit?(lost) && heal <= incoming
        score -= 120
        reasons << ["heal_only_delays", -120]
      else
        score += 150
        reasons << ["heal_saves_battler", 150]
      end
    elsif incoming > heal
      score -= 120
      reasons << ["heal_losing_race", -120]
    end

    # Reborn's x0.3 when the foe is on its last Pokemon and a KO is in hand: there is
    # nothing left to outlast.
    if Model.number(action["foe_reserves"], 1) <= 0 && has_lethal_move?(snapshot, actor)
      score -= 200
      reasons << ["finish_instead_of_heal", -200]
    end
    score
  end

  # Every damaging action of this actor that can actually land, with the target each
  # one is scored against. has_lethal_move? and damage_race must agree on what counts
  # as "a hit on that target", so the matching lives here once. A spread move and a
  # single-foe snapshot's untargeted move both count against whichever target is asked
  # about, which is the same latitude has_lethal_move? has always taken.
  def self.each_damaging_action(snapshot, actor, only_target = nil)
    (actor["actions"] || []).each do |other|
      next if other["type"] != "move"
      next if !Model.truthy(other["damaging"]) || Model.truthy(other["immune"])
      next if Model.number(other["effectiveness"], 1.0) <= 0
      target = target_for(snapshot, other["target"])
      if !only_target.nil?
        aimed = (other["target"] == only_target["index"]) ||
                Model.truthy(other["spread"]) ||
                (other["target"].nil? && (snapshot["targets"] || []).length <= 1)
        next if !aimed
        target = only_target
      end
      target_hp = target ? Model.number(target["hp_pct"], 100.0) :
                           Model.number(other["target_hp_pct"], 100.0)
      next if target_hp <= 0
      yield other, target, target_hp
    end
  end

  def self.has_lethal_move?(snapshot, actor)
    each_damaging_action(snapshot, actor) do |other, _target, target_hp|
      return true if Model.number(other["expected_damage_pct"], 0.0) >= target_hp
    end
    false
  end

  # Beyond this many hits the exchange is not a race any more, it is a stall war, and
  # the counts stop carrying information. Cap rather than let a chip move produce a
  # 40-turn "plan" that compares equal to another one.
  RACE_MAX_HITS = 8

  # HOW MANY HITS EACH SIDE NEEDS, AND WHO LANDS THE LAST ONE.
  #
  # Every other rule in this core asks a one-hit question -- does the next hit kill me,
  # does my next hit kill it. This is the two-hit question a bulky team plays by.
  # Reborn has no explicit hits-to-KO either, but `maxdam*2 > hp` gates its setup
  # (PokeBattle_AI_2.rb:6007), its recovery (:7588) and Rest (:7667), hpGainPerTurn
  # (:10112) folds residual into the same comparison, and pbAIfaster? (:10051) orders
  # the final hit per move PAIR -- so a priority move on either side rewrites who lands
  # last. Radical Red states the same thing in five lines (ANALYSIS.md :655-684).
  #
  # Pure: it reads the snapshot and nothing else, so the adapter can call it on a
  # snapshot it has just built (view_trace does exactly that). Returns nil the moment
  # an input is missing -- an adapter with no threats_by_foe, an actor with no damaging
  # move -- and every consumer is written to go inert on nil. That is the same "a
  # missing field never penalises the actor" contract as faster_flag.
  #
  # Point estimates, not low rolls. The race is the soft question, the way
  # threatened_lethal? is; the consumers only ever withhold a bonus or add an escape
  # reason, never a -400. Accuracy is deliberately ignored, as Reborn's maxdam ignores
  # it too.
  def self.damage_race(snapshot, actor, target, config)
    return nil if !config["damage_race"] || actor.nil? || target.nil?

    target_hp = Model.number(target["hp_pct"], 100.0)
    actor_hp = Model.number(actor["hp_pct"], 100.0)
    return nil if target_hp <= 0 || actor_hp <= 0

    mine_best = 0.0
    mine_priority = 0.0
    guard = false
    each_damaging_action(snapshot, actor, target) do |other, target_view, _hp|
      damage = Model.number(other["expected_damage_pct"], 0.0)
      next if damage <= 0
      mine_best = damage if damage > mine_best
      guard = true if one_hit_guard?(other, target_view) && damage >= target_hp
      mine_priority = damage if Model.number(other["priority"], 0) > 0 &&
                                damage > mine_priority
    end

    # A race needs both sides. With no hit of my own on this target there is no
    # hit-count question to answer, and the rules that already cover that position
    # (no_effective_move, weak_current_attacks) are the ones that should speak.
    return nil if mine_best <= 0

    threats = actor["threats_by_foe"]
    return nil if threats.nil?
    threat = threats[target["index"].to_s] || threats[target["index"]]
    return nil if threat.nil?
    theirs_best = Model.number(threat["damage_pct"], 0.0)
    theirs_priority = Model.number(threat["priority_damage_pct"], 0.0)
    faster = threat["faster"]
    faster = nil if faster != true && faster != false

    # Sturdy and Focus Sash do not reduce the hit, they cost a whole extra one: the
    # blow that would have killed leaves the target on 1 HP. This is the ONE place the
    # guard belongs -- 0.5.0 deliberately left the kill call alone (see the note in
    # score_move), because cancelling `lethal` deletes the move's value, whereas
    # spending a hit is exactly what the guard actually does.
    mine = hits_needed(target_hp, mine_best)
    mine += 1 if !mine.nil? && guard && mine < RACE_MAX_HITS

    # Residual is on MY side only: the actor's own toxic and leech are exported, the
    # foe's are not. Reborn's hpGainPerTurn is the same one-sided term.
    residual = Model.number(actor["residual_damage_pct"], 0.0)
    theirs = hits_needed(actor_hp, theirs_best + residual)

    winning = nil
    last_hit_first = nil
    if !mine.nil? && !theirs.nil?
      if mine < theirs
        # A hit-count gap cannot be closed by speed or priority: the side needing
        # fewer hits simply finishes on an earlier turn.
        winning = true
      elsif mine > theirs
        winning = false
      else
        # Equal counts, so the exchange is decided by who lands the FINAL hit. This is
        # pbAIfaster?(attackermove, opponentmove) restricted to the last exchange: a
        # priority move only decides it if it is big enough to finish the job.
        mine_finishes = mine_priority > 0 &&
                        mine_priority >= target_hp - (mine - 1) * mine_best
        theirs_finishes = theirs_priority > 0 &&
                          theirs_priority >= actor_hp - (theirs - 1) * (theirs_best + residual)
        if mine_finishes && !theirs_finishes
          last_hit_first = true
        elsif theirs_finishes && !mine_finishes
          last_hit_first = false
        else
          last_hit_first = faster
        end
        winning = last_hit_first if !last_hit_first.nil?
      end
    end

    { "mine" => mine, "theirs" => theirs, "faster" => faster,
      "last_hit_first" => last_hit_first, "winning" => winning }
  end

  # nil when nothing gets through, otherwise the capped number of hits.
  def self.hits_needed(hp, per_hit)
    return nil if per_hit.nil? || per_hit <= 0
    count = (hp / per_hit.to_f).ceil
    count = RACE_MAX_HITS if count > RACE_MAX_HITS
    count = 1 if count < 1
    count
  end


  # "The foe kills me in two and I do not move first." Silent -- false, never a
  # penalty -- whenever the race is unavailable.
  # The race against whichever current foe the actor is doing worst against. In
  # singles that is the only foe; in doubles, losing to either one is a reason to
  # leave. nil when no target yields a race at all.
  # Radical Red's switch-in table, scaled x5 into Portable's switch units. The bands
  # are hits the FOE needs to knock this candidate out; the +70 is for outrunning it.
  # Keyed off the candidate's own HP, not 100%, because a chipped bench mon that dies
  # in one is exactly the candidate this is meant to refuse.
  # Radical Red's switch-in table, scaled x5 into Portable's switch units (a neutral
  # matchup is 32 there, and one super-effective step is another 32). The bands are
  # how many hits the FOE needs to knock this candidate out.
  SWITCHIN_RACE_OUTSPEED = 70

  def self.switchin_race_bonus(action)
    # The candidate's OWN hp, not 100: a chipped bench mon that dies in one is exactly
    # the candidate this is here to refuse.
    hp = Model.number(action["candidate_hp_pct"], 100.0)
    hp = 100.0 if hp <= 0
    theirs = hits_needed(hp, Model.number(action["incoming_damage_pct"], 0.0))
    bonus = 0
    if theirs.nil? || theirs >= 4
      bonus += 85            # nothing the foe has gets through in a hurry
    elsif theirs == 3
      bonus += 10
    elsif theirs == 2
      bonus -= 5
    else
      bonus -= 70            # it dies on the turn it arrives
    end
    # Reborn scales a switch-in's damage OUTPUT by whether it outruns the foe
    # (:11755-11764, x1.5 against x0.75), so the premium belongs to a candidate that
    # has output to scale. One that deals nothing gains nothing by moving first.
    if action["faster"] == true &&
       Model.number(action["outgoing_damage_pct"], 0.0) > 0
      bonus += SWITCHIN_RACE_OUTSPEED
    end
    bonus
  end

  def self.worst_race(snapshot, actor, config)
    worst_race_with_target(snapshot, actor, config)[0]
  end

  # The same, keeping WHICH foe it is: the bench candidate's race has to be run against
  # the foe the actor is actually losing to. [nil, nil] when no target yields a race.
  def self.worst_race_with_target(snapshot, actor, config)
    worst = nil
    worst_target = nil
    (snapshot["targets"] || []).each do |target|
      race = damage_race(snapshot, actor, target, config)
      next if race.nil?
      if worst.nil? || race_rank(race) < race_rank(worst)
        worst = race
        worst_target = target
      end
    end
    [worst, worst_target]
  end

  # damage_race's question asked of a BENCH candidate: once it is in, who lands the
  # last hit. The switch turn is paid for -- the candidate eats one free hit on entry,
  # on top of the hazards, and attacks nothing that turn -- and only then does the
  # exchange start. Built from the two estimates the adapter puts on the switch action
  # (switch_outgoing_damage / switch_incoming_damage); nil when either is missing, and
  # every consumer goes inert on nil, the contract damage_race keeps. Point estimates
  # and no priority term: the candidate's moves are not exported one by one, and this
  # is the soft question. `theirs` counts the free hit.
  def self.candidate_race(action, target)
    return nil if action.nil? || target.nil?
    return nil if !action.key?("outgoing_damage_pct") ||
                  !action.key?("incoming_damage_pct")
    target_hp = Model.number(target["hp_pct"], 100.0)
    return nil if target_hp <= 0
    incoming = Model.number(action["incoming_damage_pct"], 0.0)
    mine = hits_needed(target_hp, Model.number(action["outgoing_damage_pct"], 0.0))
    return nil if mine.nil?
    # At the cap the count carries no information (see RACE_MAX_HITS): a candidate
    # that needs eight or more hits is not winning a race, it is walling, and an
    # immune wall "wins" against anything by this arithmetic. Gengar into a Snorlax
    # mirror -- Body Slam does nothing to it, Shadow Ball does 7% -- was the case
    # (no_switch_full_hp_neutral, Reborn probe).
    return { "mine" => mine, "theirs" => nil, "winning" => false } if mine >= RACE_MAX_HITS
    left = Model.number(action["candidate_hp_pct"], 100.0) -
           Model.number(action["entry_damage_pct"], 0.0) - incoming
    return { "mine" => mine, "theirs" => 1, "winning" => false } if left <= 0
    more = hits_needed(left, incoming)
    winning = if more.nil? then true            # nothing of theirs gets through
              elsif mine < more then true
              elsif mine > more then false
              else action["faster"] == true
              end
    { "mine" => mine, "theirs" => (more.nil? ? nil : more + 1), "winning" => winning }
  end

  # Tri-state: true when the candidate's best hit on the current foes clears the
  # weak_current_attacks line (10% of the target), false when it does not, nil when
  # the adapter exported no estimate or the key is off -- and nil never withholds a
  # reason, the same contract every other missing field keeps.
  WEAK_ATTACK_PCT = 10

  #
  # 0.6.4 (escape_wall_margin): clearing the line is not enough. The bench estimate
  # and the field estimate are built from different battlers and disagree by a few
  # points, so a body at 11% on the bench read as weak once it stood there and went
  # straight back -- 62 of the 133 switch-backs left in the 0.6.3 run were that. The
  # candidate has to BEAT the actor at the actor's own game: two whole hits fewer to
  # the knockout, and no more than four of its own, against some foe on the field.
  # Both counts are hits_needed on the same foe HP, so the comparison is honest
  # about a chipped wall: at 40% a 15% hit is three, not "weak".
  WALL_BREAK_MARGIN = 2
  WALL_BREAK_MAX_HITS = 4

  def self.candidate_can_hit?(snapshot, actor, action, config)
    return nil if !config["escape_needs_hitter"]
    return nil if !action.key?("outgoing_damage_pct") || action["outgoing_damage_pct"].nil?
    outgoing = Model.number(action["outgoing_damage_pct"], 0.0)
    return outgoing >= WEAK_ATTACK_PCT if !config["escape_wall_margin"]
    actor_best = Model.number(actor["best_damage_pct"], 0.0)
    live = (snapshot["targets"] || []).select { |t| Model.number(t["hp_pct"], 100.0) > 0 }
    return nil if live.empty?
    live.any? do |target|
      hp = Model.number(target["hp_pct"], 100.0)
      mine = hits_needed(hp, outgoing) || RACE_MAX_HITS
      actors = hits_needed(hp, actor_best) || RACE_MAX_HITS
      mine <= WALL_BREAK_MAX_HITS && mine <= actors - WALL_BREAK_MARGIN
    end
  end

  # KILL ORDER, GRADED. candidate_race's answer as a number: the margin in hits
  # between what the foe needs on the candidate (free hit included) and what the
  # candidate needs on the foe. Positive is "it finishes first", by that many hits;
  # zero is decided by speed. In doubles the candidate has to win against both, so
  # the worse of its two races is the one that counts. 0 without estimates and 0 at
  # the cap (a wall is graded by the defensive bands, not by a race it never
  # finishes), so every consumer is inert exactly where candidate_race is.
  #
  # The bands: a win by two whole hits is the Scizor-into-Espeon case and worth more
  # than 0.6.3's flat 110; one hit is that 110; a win on the tiebreak is worth
  # less, because the adapters call a speed tie "slower" and this is where that
  # error lives. The losing side mirrors it, short of the -500 a death on entry
  # already pays.
  KILL_ORDER_GRADES = { 2 => 150, 1 => 110, 0 => 70, -1 => -70, -2 => -110 }
  KILL_ORDER_TIE_LOST = -30

  def self.kill_order_grade(race)
    return 0 if race.nil? || race["mine"].nil? || race["mine"] >= RACE_MAX_HITS
    # `theirs` counts the free entry hit, which the candidate answers with nothing,
    # so the exchange proper is theirs - 1 against mine.
    theirs = race["theirs"].nil? ? RACE_MAX_HITS : race["theirs"]
    margin = (theirs - 1) - race["mine"]
    return (race["winning"] ? KILL_ORDER_GRADES[0] : KILL_ORDER_TIE_LOST) if margin == 0
    KILL_ORDER_GRADES[[[margin, -2].max, 2].min]
  end

  def self.candidate_race_grade(snapshot, action)
    worst = nil
    (snapshot["targets"] || []).each do |target|
      race = candidate_race(action, target)
      next if race.nil?
      grade = kill_order_grade(race)
      worst = grade if worst.nil? || grade < worst
    end
    worst || 0
  end

  # The most any recovery move this battler carries restores, in hp_pct units and
  # UNCLIPPED by its current headroom: the question is what the heal is worth when it
  # is needed, not what it would restore this instant. 0 without one.
  def self.best_heal_pct(snapshot, actor)
    best = 0.0
    (actor["actions"] || []).each do |other|
      next if other["type"] != "move"
      tags = Effects.describe(other["move_id"], other["tags"])
      next if !(tags.include?("heal") || tags.include?("variable_heal"))
      amount = heal_amount(snapshot, tags)
      best = amount if amount > best
    end
    best
  end

  # A healer alternates healing and attacking, so to sustain, one heal has to cover
  # TWO of the foe's hits: Recover (50) holds against 20 a hit and bleeds out against
  # 30. Below that line a race counted in hits is as lost as it looks.
  def self.heal_cannot_outpace?(snapshot, actor)
    incoming = Model.number(actor["incoming_damage_pct"], 0.0)
    best_heal_pct(snapshot, actor) < incoming * 2
  end

  # Lost by a WHOLE hit, not on the tiebreak. The adapters export `faster` as a plain
  # "outspeeds" -- a speed tie reads as slower on both sides -- so two identical
  # Snorlax each see an equal-count race they "lose", and a rule that acted on that
  # would have both of them running from a mirror (the no_switch_full_hp_neutral card
  # caught exactly this). The 0.6.3 rules act only on the hit-count gap, which no
  # tiebreak can manufacture; the equal-count-and-slower case stays with the 0.6.0
  # flag, which is off.
  def self.race_lost_by_a_hit?(race)
    return false if race.nil? || race["winning"] != false
    return false if race["mine"].nil? || race["theirs"].nil?
    race["mine"] > race["theirs"]
  end

  # Lower is worse for the actor: losing < unknown < winning, and within losing the
  # one that kills it soonest.
  def self.race_rank(race)
    base = if race["winning"] == false then 0
           elsif race["winning"].nil? then 1
           else 2
           end
    theirs = race["theirs"].nil? ? RACE_MAX_HITS : race["theirs"]
    base * 100 + theirs
  end

  # A setup move is a STATUS move and the adapter gives it no scoring target, so
  # `target` is nil here in singles as well as doubles. Fall back to the foe the actor
  # is doing worst against, which is the one the setup has to survive. This cost a
  # portable probe run: the rule was silently inert on every card until the nil-target
  # case was found, and the unit test had been written with a target on the setup move.
  def self.setup_into_2hko?(snapshot, actor, target, config)
    race = target.nil? ? worst_race(snapshot, actor, config) :
                         damage_race(snapshot, actor, target, config)
    return false if race.nil?
    theirs = race["theirs"]
    return false if theirs.nil? || theirs > 2
    race["faster"] == false
  end

  def self.threatened_lethal?(actor)
    Model.truthy(actor["threatened_lethal"]) ||
      Model.number(actor["incoming_damage_pct"], 0) >= Model.number(actor["hp_pct"], 100)
  end

  def self.memory_count(snapshot, actor_index, key)
    memory = snapshot["memory"] || {}
    actor = memory[actor_index.to_s] || memory[actor_index] || {}
    Model.number(actor[key], 0).to_i
  end

  def self.memory_updates(actions)
    out = {}
    actions.each do |action|
      actor_index = action["actor_index"]
      update = { "last_type" => action["type"] }
      if action["type"] == "switch"
        update["increment"] = "switch"
      else
        tags = Effects.describe(action["move_id"], action["tags"])
        update["last_move"] = action["move_id"]
        if tags.include?("setup")
          update["increment"] = "setup"
        elsif tags.include?("protect") || tags.include?("team_protect")
          update["increment"] = "protect"
        elsif tags.include?("substitute")
          update["increment"] = "substitute"
        end
      end
      out[actor_index.to_s] = update
    end
    out
  end

  # ---------------------------------------------------------------------------
  # 0.5.0 tables.
  #
  # Reborn multiplies a move's damage-percent score by a per-move `miniscore`;
  # Portable adds. The quantity that multiplier scales is the move's DAMAGE score,
  # which here is the flat lethal bonus when the move kills and the capped damage term
  # when it does not — so scaling that same quantity keeps a x0.9 recoil charge worth
  # a tenth of what the move is actually being clicked for, instead of a tenth of a
  # number that stops mattering the moment the move is lethal.
  # ---------------------------------------------------------------------------
  def self.damage_value(lethal, damage)
    return 500.0 if lethal
    [Model.number(damage, 0.0), 100.0].min * 0.8
  end

  def self.multiplier_delta(m, lethal, damage)
    (m - 1.0) * damage_value(lethal, damage)
  end

  # Reborn's pbReduceWhenKills (:9887): once the damage score is at the cap, the
  # multiplier is square-rooted. x1.68 becomes x1.30 and x0.9 becomes x0.95 — bonuses
  # and costs soften alike, because by then the move is being clicked for the knockout
  # and not for what it does afterwards.
  def self.reduce_when_kills(m, lethal)
    return m if !lethal || m <= 0
    Math.sqrt(m)
  end

  # A secondary that fires 30% of the time is worth 30% of the effect. Reborn does NOT
  # do this — burncode/paracode/poisoncode/freezecode never read the move's addlEffect,
  # so Scald's 30% burn and Will-O-Wisp's 100% burn are priced identically (measured,
  # PORTABLE-AI-REBORN.md "0.5.0 Phase A", finding 6). This is a deliberate DEPARTURE.
  # A chance of exactly 0 means the effect is negated outright (Sheer Force, Shield
  # Dust, Covert Cloak) and the whole row is skipped by the caller.
  def self.chance_scaled(m, chance)
    return m if chance.nil?
    fraction = Model.number(chance, 100.0) / 100.0
    fraction = 1.0 if fraction > 1.0
    1.0 + (m - 1.0) * fraction
  end

  # Fact about the move's target, from the target view when the snapshot carries one
  # and from the action otherwise. Spread moves have no single target and read the
  # action's copy; unit tests may use either.
  def self.target_fact(action, target, key)
    return target[key] if target && !target[key].nil?
    action["target_" + key]
  end

  def self.actor_ability(actor)
    value = (actor || {})["ability"]
    value.nil? ? nil : value.to_s.upcase
  end

  def self.doubles?(snapshot)
    return true if (snapshot["format"] || "").to_s == "double"
    (snapshot["actors"] || []).length > 1
  end

  # Sturdy and Focus Sash both mean "survives one hit from full HP". Mold Breaker turns
  # Sturdy off and a multi-hit move beats both, which is exactly Reborn's notOHKO?
  # (:17401-17409) minus the field- and form-specific rows.
  # Sturdy, or a Focus Sash, on a full-HP target: it survives one hit whatever that
  # hit was. Mold Breaker turns Sturdy off. Read by the multi-hit row, which is the
  # only place 0.5.0 prices it -- see the note in score_move.
  def self.one_hit_guard?(action, target)
    return false if !Model.truthy(target_fact(action, target, "full_hp"))
    item = (target_fact(action, target, "item") || "").to_s.upcase
    return true if item == "FOCUSSASH"
    ability = (target_fact(action, target, "ability") || "").to_s.upcase
    ability == "STURDY" && !Model.truthy(action["mold_breaker"])
  end

  # Abilities the TARGET has that make a status worth less, keyed by status kind.
  # Copied from Reborn's burncode (:5647), paracode (:5605) and poisoncode, which is
  # where the numbers come from; nothing here is invented.
  STATUS_DETERRENTS = {
    "burn" => { "GUTS" => 0.1, "FLAREBOOST" => 0.1, "QUICKFEET" => 0.3,
                "NATURALCURE" => 0.3, "MAGICGUARD" => 0.5, "SYNCHRONIZE" => 0.5,
                "MARVELSCALE" => 0.7, "SHEDSKIN" => 0.7, "WATERVEIL" => 0.0 },
    "poison" => { "POISONHEAL" => 0.1, "MAGICGUARD" => 0.1, "TOXICBOOST" => 0.2,
                  "GUTS" => 0.2, "QUICKFEET" => 0.3, "NATURALCURE" => 0.3,
                  "SYNCHRONIZE" => 0.5, "SHEDSKIN" => 0.7, "IMMUNITY" => 0.0 },
    "paralyze" => { "GUTS" => 0.2, "QUICKFEET" => 0.2, "NATURALCURE" => 0.3,
                    "MARVELSCALE" => 0.5, "SYNCHRONIZE" => 0.5, "SHEDSKIN" => 0.7,
                    "LIMBER" => 0.0 },
    "freeze" => { "NATURALCURE" => 0.3, "SYNCHRONIZE" => 0.5, "MARVELSCALE" => 0.8,
                  "MAGMAARMOR" => 0.0 },
    "sleep" => { "NATURALCURE" => 0.3, "SHEDSKIN" => 0.7, "EARLYBIRD" => 0.5,
                 "INSOMNIA" => 0.0, "VITALSPIRIT" => 0.0 }
  }

  STATUS_KINDS = %w[burn poison paralyze freeze sleep confuse]

  def self.status_kind(tags)
    STATUS_KINDS.each { |kind| return kind if tags.include?(kind) }
    nil
  end

  def self.status_deterrent(kind, ability)
    return 1.0 if kind.nil? || ability.nil?
    row = STATUS_DETERRENTS[kind]
    return 1.0 if !row
    value = row[ability.to_s.upcase]
    value.nil? ? 1.0 : value
  end

  # A pure status move aimed at a target that profits from the status. Reborn's own
  # multipliers, restated: at x0.3 or worse the move is a mistake rather than merely a
  # weak choice, so the flat +25 the status block just paid becomes -150.
  def self.status_deterrent_rule(action, tags, target, score, reasons)
    m = status_deterrent(status_kind(tags), target_fact(action, target, "ability"))
    return score if m >= 1.0
    if m <= 0.3
      score -= 175
      reasons << ["status_deterred", -175]
    else
      penalty = (1.0 - m) * 100.0
      score -= penalty
      reasons << ["status_deterred", -penalty]
    end
    score
  end

  # Item removal is worth what the item was worth. Reborn's knockcode (:8072) is a
  # short whitelist and returns a flat 1 for everything else -- including Focus Sash,
  # which a human would certainly rather remove. Copied as-is rather than extended:
  # the probe measured Knock Off at 75 / 58 / 39 against Leftovers / Sash / no item,
  # and the 58 is the ENGINE's own x1.5 damage boost against an item holder, which
  # reaches the core through expected_damage_pct without any rule's help.
  ITEM_REMOVAL_VALUE = {
    "LEFTOVERS" => 1.3, "BLACKSLUDGE" => 1.3,
    "LIFEORB" => 1.2, "CHOICESCARF" => 1.2, "CHOICEBAND" => 1.2,
    "CHOICESPECS" => 1.2, "ASSAULTVEST" => 1.2
  }

  CONTACT_PUNISHERS = %w[ROUGHSKIN IRONBARBS UNBREAKABLEBODY]

  ABSORB_ABILITIES = {
    "FLASHFIRE" => "FIRE", "WELLBAKEDBODY" => "FIRE",
    "WATERABSORB" => "WATER", "STORMDRAIN" => "WATER", "DRYSKIN" => "WATER",
    "SAPSIPPER" => "GRASS", "EARTHEATER" => "GROUND",
    "VOLTABSORB" => "ELECTRIC", "LIGHTNINGROD" => "ELECTRIC",
    "MOTORDRIVE" => "ELECTRIC", "JUSTIFIED" => "DARK"
  }

  REDIRECT_ABILITIES = { "LIGHTNINGROD" => "ELECTRIC", "STORMDRAIN" => "WATER" }

  # Every per-move side effect that scales the damage the move already does. One pass,
  # one named reason per row that fires, so a trace says which table entry moved the
  # score.
  # flat_kill (0.6.2, config["lethal_flat"]) drops the rows that only pay out if the
  # target is still standing afterwards -- the secondary status/flinch/stat-drop, and
  # the knocked item. The rows that survive it are the ones about whether the knockout
  # HAPPENS or what it costs the actor: multi_hit versus Sturdy/Sash, recoil, drain.
  def self.side_effect_rules(snapshot, actor, action, tags, target, damage,
                             lethal, faster, score, reasons, flat_kill = false)
    chance = action.key?("effect_chance") ? Model.number(action["effect_chance"], 100.0) : nil
    kind = action["effect_kind"]
    kind = Effects.kind_of(tags, "secondary") if kind.nil?
    kind = kind.nil? ? nil : kind.to_s
    target_ability = (target_fact(action, target, "ability") || "").to_s.upcase
    target_item = (target_fact(action, target, "item") || "").to_s.upcase

    # chance == 0 is the engine saying the secondary is negated outright (Sheer Force,
    # Shield Dust, Covert Cloak). No row fires, and the move is judged on damage alone.
    if kind && !(chance && chance <= 0) && !flat_kill
      m = secondary_multiplier(kind, action, actor, target, target_ability,
                               lethal, faster)
      if m != 1.0
        m = chance_scaled(m, chance)
        m = reduce_when_kills(m, lethal)
        delta = multiplier_delta(m, lethal, damage)
        if delta != 0
          # A status the target profits from is a reason NOT to click the move, and the
          # deterrent table is the same one the pure status moves use.
          score += delta
          reasons << ["secondary_" + kind, delta]
        end
      end
    end

    if Model.truthy(action["multi_hit"])
      m = 1.0
      m *= 1.3 if one_hit_guard?(action, target)
      if Model.truthy(action["contact"]) &&
         (CONTACT_PUNISHERS.include?(target_ability) || target_item == "ROCKYHELMET")
        m *= 0.7
      end
      if m != 1.0
        delta = multiplier_delta(reduce_when_kills(m, lethal), lethal, damage)
        score += delta
        reasons << ["multi_hit", delta]
      end
    end

    recoil = Model.number(action["recoil_fraction"], 0.0)
    if recoil > 0 && actor_ability(actor) != "ROCKHEAD" && actor_ability(actor) != "MAGICGUARD"
      hp = Model.number(actor["hp_pct"], 100.0)
      m = 0.9
      m *= 0.8 if hp > 10 && hp < 40
      delta = multiplier_delta(reduce_when_kills(m, lethal), lethal, damage)
      score += delta
      reasons << ["recoil_cost", delta]
    end

    drain = Model.number(action["drain_fraction"], 0.0)
    if drain > 0
      hp = Model.number(actor["hp_pct"], 100.0)
      missing = 100.0 - hp
      if missing <= 0 && faster == true
        # Nothing to restore and the drain resolves after the hit either way
        # (absorbcode's guard clause, :7742).
      else
        healed = [Model.number(damage, 0.0) * drain, missing].min
        m = 1.0 + 0.5 * healed / 100.0
        m = 2.0 - m if target_ability == "LIQUIDOOZE"
        delta = multiplier_delta(reduce_when_kills(m, lethal), lethal, damage)
        if delta != 0
          score += delta
          reasons << ["drain_heal", delta]
        end
      end
    end

    if tags.include?("item_removal") && target_item != "" && !flat_kill
      m = ITEM_REMOVAL_VALUE[target_item] || 1.0
      if m != 1.0
        delta = multiplier_delta(reduce_when_kills(m, lethal), lethal, damage)
        score += delta
        reasons << ["knocks_item", delta]
      end
    end
    score
  end

  # The per-kind multiplier before chance and the kill reduction are applied.
  def self.secondary_multiplier(kind, action, actor, target, target_ability,
                                lethal, faster)
    deterrent = status_deterrent(kind, target_ability)
    case kind
    when "burn"
      m = 1.2
      m *= 1.4 if Model.truthy(target_fact(action, target, "physical_attacker"))
      m * deterrent
    when "poison", "freeze", "sleep"
      1.2 * deterrent
    when "paralyze"
      m = 1.0
      # Worth something only where halving the target's Speed changes who moves first.
      if faster == false
        target_speed = Model.number(target_fact(action, target, "speed"), 0.0)
        actor_speed = Model.number(actor["speed"], 0.0)
        m *= 1.2 if target_speed > 0 && actor_speed > 0 && target_speed / 2.0 < actor_speed
      end
      m *= 1.1 if Model.truthy(target_fact(action, target, "special_attacker"))
      m * deterrent
    when "flinch"
      # A flinch you never inflict is worth nothing: Reborn returns a flat 1 when the
      # user is slower or the move already kills (:5691).
      return 1.0 if faster != true || lethal
      return 1.0 if target_ability == "INNERFOCUS" || target_ability == "SHIELDDUST"
      return 1.0 if Model.truthy(target_fact(action, target, "substitute"))
      1.3
    when "drop"
      stat = (action["effect_stat"] || "").to_s.downcase
      return 1.0 if target_ability == "CLEARBODY" || target_ability == "WHITESMOKE" ||
                    target_ability == "FULLMETALBODY" || target_ability == "GOODASGOLD"
      case stat
      when "speed"
        faster == false ? 1.3 : 1.0
      when "spa"
        Model.truthy(target_fact(action, target, "special_attacker")) ? 1.2 : 1.0
      when "atk"
        Model.truthy(target_fact(action, target, "physical_attacker")) ? 1.2 : 1.0
      when "def", "spd"
        lethal ? 1.0 : 1.1
      else
        1.0
      end
    else
      1.0
    end
  end

  # Rules about what a move does to the SHAPE of the turn rather than to its damage:
  # speed control, first-turn-only moves, delayed damage. Flat score units, because
  # none of these three is a multiplier on damage the move does now.
  def self.turn_shape_rules(snapshot, actor, action, tags, faster, score, reasons)
    if tags.include?("first_turn_only")
      if Model.number(actor["turncount"], 0) == 0
        score += 115
        reasons << ["first_turn_hit", 115]
      else
        reasons << ["first_turn_over", HARD_REJECT]
        return HARD_REJECT
      end
    end

    if tags.include?("delayed_damage")
      if Model.truthy(action["effect_active"])
        score -= 200
        reasons << ["delayed_damage_pending", -200]
      elsif !threatened_lethal?(actor)
        score += 40
        reasons << ["delayed_damage", 40]
      end
    end

    if tags.include?("field_speed")
      move_id = action["move_id"].to_s.upcase
      active = move_id == "TRICKROOM" ? Model.truthy(snapshot["trick_room_active"]) :
                                        Model.truthy(snapshot["tailwind_active"])
      if active
        score -= 500
        reasons << ["speed_control_redundant", -500]
      elsif faster == false
        bonus = move_id == "TRICKROOM" ? 120 : 80
        # Trick Room is a whole-team investment: it is only worth a turn if the bench
        # is slow too, otherwise it hurts the mons that come in after this one.
        if move_id == "TRICKROOM"
          bench = Model.number(actor["slower_bench_count"], -1)
          reserves = Model.number(action["own_reserves"], 0)
          if bench >= 0 && reserves > 0 && bench * 2 < reserves
            bonus = 0
            reasons << ["trick_room_bench_is_fast", 0]
          end
        end
        bonus = (bonus * 1.3).round if bonus > 0 && doubles?(snapshot)
        if bonus > 0
          score += bonus
          reasons << ["speed_control_value", bonus]
        end
      end
    end
    score
  end

  # Doubles-only. Everything here is inert in singles except partner_heal, which is a
  # dead move there and says so.
  def self.format_rules(snapshot, actor, action, tags, score, reasons)
    if tags.include?("partner_heal")
      if !doubles?(snapshot)
        reasons << ["partner_heal_in_singles", HARD_REJECT]
        return HARD_REJECT
      end
      partner_hp = Model.number(actor["partner_hp_pct"], 100.0)
      if !Model.truthy(actor["partner_alive"])
        reasons << ["partner_heal_no_partner", HARD_REJECT]
        return HARD_REJECT
      elsif partner_hp >= 85
        score -= 500
        reasons << ["partner_heal_near_full", -500]
      elsif partner_hp <= 35
        bonus = 220 + (35 - partner_hp) * 3
        score += bonus
        reasons << ["partner_heal_low_hp", bonus]
      elsif partner_hp <= 60
        score += 90
        reasons << ["partner_heal_mid_hp", 90]
      end
    end
    return score if !doubles?(snapshot)

    move_type = (action["move_type"] || "").to_s.upcase
    return score if move_type == ""
    damage = Model.number(action["expected_damage_pct"], 0.0)

    if Model.truthy(action["spread"]) && Model.truthy(actor["partner_alive"])
      partner_ability = (actor["partner_ability"] || "").to_s.upcase
      if ABSORB_ABILITIES[partner_ability] == move_type
        # The partner does not merely survive the spread move, it profits from it:
        # Reborn doubles the score (:2031) and the probe measured Discharge at 280
        # against Thunderbolt's 112 on exactly that board.
        delta = multiplier_delta(2.0, false, damage)
        score += delta
        reasons << ["partner_absorbs", delta]
      elsif move_type == "GROUND" && Model.truthy(actor["partner_airborne"])
        reasons << ["partner_immune", 0]
      end
    end

    if !Model.truthy(action["spread"]) && !action["target"].nil?
      target = target_for(snapshot, action["target"])
      actor_ability_name = actor_ability(actor)
      steals = actor_ability_name != "STALWART" && actor_ability_name != "PROPELLERTAIL"
      if steals && target && REDIRECT_ABILITIES[(target["partner_ability"] || "").to_s.upcase] == move_type
        # The foe's partner takes the move instead, so it never reaches what it was
        # aimed at. Reborn already returns -1 for this (:3005) and the probe confirms;
        # the rule is here so the core does not depend on the adapter noticing.
        reasons << ["redirected_by_partner", HARD_REJECT]
        return HARD_REJECT
      end
      partner_ability = (actor["partner_ability"] || "").to_s.upcase
      if steals && REDIRECT_ABILITIES[partner_ability] == move_type
        # Reborn does NOT have this row: measured, it clicks Thunderbolt into a board
        # where its own Lightning Rod partner absorbs it (finding 2). Its own :3010
        # x0.3 is the symmetric case it does implement, so this is that number applied
        # to the direction the reference misses.
        delta = multiplier_delta(0.3, false, damage)
        score += delta
        reasons << ["own_partner_steals", delta]
      end
    end
    score
  end

  # Abilities on the TARGET that change what a damaging move is worth without changing
  # what it does.
  def self.damaging_ability_rules(action, target, lethal, score, reasons)
    return score if lethal
    ability = (target_fact(action, target, "ability") || "").to_s.upcase
    if ability == "JUSTIFIED" && (action["move_type"] || "").to_s.upcase == "DARK"
      # A Dark move that does not kill hands a Justified target a free Attack stage.
      score -= 40
      reasons << ["feeds_justified", -40]
    end
    score
  end

  def self.compare_candidates(a, b)
    by_score = b["score"] <=> a["score"]
    return by_score if by_score != 0
    action_key(a) <=> action_key(b)
  end

  def self.action_key(action)
    kind = action["type"] == "move" ? "0" : "1"
    [kind, action["slot"].to_i, action["target"].nil? ? -1 : action["target"].to_i,
     action["move_id"].to_s].join(":")
  end

  def self.pair_key(pair)
    pair.map { |action| action_key(action) }.join("|")
  end
end
