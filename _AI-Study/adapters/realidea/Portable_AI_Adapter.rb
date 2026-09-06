# Portable AI adapter for Realidea (Pokemon Essentials v16).
#
# This file is concatenated after portable_ai/model.rb, effects.rb and core.rb, then
# injected as one script section after "AI edit clara" and before Main.
#
# Safe rollout: the hook is inert unless Data/portable_ai.txt exists or
# $PORTABLE_AI_ENABLED is explicitly true. Any unsupported state or registration failure
# falls back to the exact pbChooseMoves implementation that was live before this section.

module PortableAIRealidea
  # Essentials function code -> [effect kind, affected stat]. Mirrors the Reborn
  # adapter's MOVE_EFFECT_CODES, PRUNED to codes that exist in this build and EXTENDED
  # with Realidea's own. The base v16 space (0x05-0x21, 0x42-0x4F) is shared verbatim
  # and was checked move by move against PBS/moves.txt; everything Reborn carries above
  # 0x100 is a Reborn code that either does not exist here or means something else --
  # Reborn's 0x139 is a 3/4 drain, Realidea's is Play Nice; Reborn's 0x13f is a Speed
  # drop, Realidea's is Flower Shield. tools/check_move_codes.py is the guard.
  MOVE_EFFECT_CODES = {
    0x05 => ["poison", nil], 0x06 => ["poison", nil],
    0x07 => ["paralyze", nil], 0x08 => ["paralyze", nil], 0x09 => ["paralyze", nil],
    0x0A => ["burn", nil], 0x0B => ["burn", nil],
    0x0C => ["freeze", nil], 0x0D => ["freeze", nil], 0x0E => ["freeze", nil],
    0x0F => ["flinch", nil], 0x10 => ["flinch", nil], 0x11 => ["flinch", nil],
    # Target stat drops.
    0x42 => ["drop", "atk"],
    0x43 => ["drop", "def"], 0x4A => ["drop", "def"], 0x4C => ["drop", "def"],
    0x44 => ["drop", "speed"], 0x4D => ["drop", "speed"],
    0x45 => ["drop", "spa"],
    0x46 => ["drop", "spd"],
    0x47 => ["drop", "acc"],
    # Self-raise on a damaging move (Power-Up Punch, Flame Charge, Charge Beam).
    0x1C => ["self_raise", "atk"], 0x1D => ["self_raise", "def"],
    0x1E => ["self_raise", "def"], 0x1F => ["self_raise", "speed"],
    0x20 => ["self_raise", "spa"], 0x21 => ["self_raise", "spd"],
    # Realidea's own, read off 083_PokeBattle_MoveEffects.rb rather than guessed.
    0x139 => ["drop", "atk"],   # Play Nice      (:8847)
    0x13A => ["drop", "atk"],   # Noble Roar     (:8866, also SpAtk)
    0x13B => ["drop", "def"],   # Hyperspace Fury(:8912, secondary on the target)
    0x13C => ["drop", "spa"],   # Confide        (:8937)
    0x13D => ["drop", "spa"],   # Eerie Impulse  (:8956)
    0xCF14 => ["drop", "atk"]   # Tearful Look   (:9975, also SpAtk)
  }

  # Recoil as a fraction of the damage dealt. 0x10B (Jump Kick / High Jump Kick) is
  # crash damage on a MISS, not recoil, and is left out exactly as Reborn leaves it out.
  MOVE_RECOIL_CODES = {
    0xFA => 0.25, 0xFB => 0.3333, 0xFC => 0.5, 0xFD => 0.3333, 0xFE => 0.3333
  }

  # Fraction of the damage dealt that is restored to the user. 0x14F is Realidea's
  # 3/4 drain (Draining Kiss, Oblivion Wing) -- Reborn numbers the same effect 0x139.
  MOVE_DRAIN_CODES = { 0xDD => 0.5, 0xDE => 0.5, 0x14F => 0.75 }

  MULTI_HIT_CODES = [0xBD, 0xBE, 0xBF, 0xC0, 0xC1]

  # Pollen Puff HEALS the partner instead of damaging it (083:9897), so the friendly
  # fire charge must not apply when it is aimed there.
  PARTNER_HEAL_CODES = [0xCF19]

  ENABLE_FILE = "Data/portable_ai.txt"
  ERROR_FILE  = "Data/portable_ai_error.txt"
  ENABLE_WILD = false

  class BattleRNG
    def initialize(battle)
      @battle = battle
    end

    def rand(limit)
      @battle.pbAIRandom(limit)
    end
  end

  def self.requested?
    return true if defined?($PORTABLE_AI_ENABLED) && $PORTABLE_AI_ENABLED
    File.exist?(ENABLE_FILE)
  rescue
    false
  end

  def self.enabled_for?(battle, index)
    return false if !requested?
    return false if !battle.pbIsOpposing?(index)
    return false if !ENABLE_WILD && !battle.opponent
    true
  rescue
    false
  end

  def self.corrected_skill(owner)
    return 100 if !owner
    current = (owner.skill || 0).to_i rescue 0
    code = (owner.skillCode || "").to_s rescue ""
    # Realidea's intended 100 was written into the skillCode column. Only consume a
    # wholly numeric code, so actual script-like skill codes remain untouched.
    intended = (code =~ /\A\d+\z/) ? code.to_i : 0
    [current, intended].max
  end

  # Run-level config overrides, set from Data/ai_harness.txt by the gauntlet and the
  # probe. Keys not named there keep their skill-derived or Model::DEFAULT_CONFIG value.
  #
  # Same contract as the Reborn adapter (:150-186): one installed build plays both
  # sides of a policy A/B, and every gauntlet and probe record carries the overrides it
  # ran under. Without this Realidea could not ablate a single core rule without a
  # rebuild, which makes the two arms different artifacts.
  def self.config_overrides
    return {} if !defined?($PORTABLE_AI_CONFIG) || !$PORTABLE_AI_CONFIG.is_a?(Hash)
    $PORTABLE_AI_CONFIG
  end

  # Whether one core config key is on for this run, for the handful of rules that live
  # on THIS side of the boundary and so never see the config hash the core is handed.
  # Same precedence as Model.config: a run-level override wins, otherwise the default.
  def self.rule_enabled?(key)
    overrides = config_overrides
    return overrides[key] ? true : false if overrides.key?(key)
    PortableAI::Model::DEFAULT_CONFIG[key] ? true : false
  rescue
    true
  end

  def self.config_for(skill)
    base =
      if skill >= PBTrainerAI.bestSkill
        {
          "deterministic" => true, "noise" => 0, "switching" => true,
          "memory" => true, "coordination" => true, "knowledge" => "fair"
        }
      elsif skill >= PBTrainerAI.highSkill
        {
          "deterministic" => false, "noise" => 5, "switching" => true,
          "memory" => true, "coordination" => true, "knowledge" => "fair"
        }
      elsif skill >= PBTrainerAI.mediumSkill
        {
          "deterministic" => false, "noise" => 12, "switching" => true,
          "memory" => false, "coordination" => true, "knowledge" => "fair"
        }
      else
        {
          "deterministic" => false, "noise" => 25, "switching" => false,
          "memory" => false, "coordination" => false, "knowledge" => "fair"
        }
      end
    base.merge(config_overrides)
  end

  def self.choose(battle, index)
    plan = plan_for(battle)
    action = nil
    (plan["actions"] || []).each do |candidate|
      if candidate["actor_index"] == index
        action = candidate
        break
      end
    end
    return false if !action

    ok = apply_action(battle, index, action)
    if ok
      owner = battle.pbGetOwner(index) rescue nil
      if config_for(corrected_skill(owner))["memory"]
        apply_memory(battle, index, action)
      end
      trace = battle.instance_variable_get(:@portable_ai_decision_trace)
      if trace
        trace << {
          "turn" => battle.turncount,
          "actor" => index,
          "type" => action["type"],
          "slot" => action["slot"],
          "move_id" => action["move_id"],
          "target" => action["target"],
          "score" => action["score"],
          "view" => view_trace(
            battle.instance_variable_get(:@portable_ai_last_snapshot), index)
        }
      end
      return true
    end
    clear_cache(battle)
    false
  rescue Exception => error
    log_error(error, index)
    clear_cache(battle)
    false
  end

  def self.plan_for(battle)
    signature = cache_signature(battle)
    cached_signature = battle.instance_variable_get(:@portable_ai_cache_signature)
    cached = battle.instance_variable_get(:@portable_ai_plan)
    return cached if cached && cached_signature == signature

    snapshot, skill = build_snapshot(battle)
    plan = PortableAI.plan(snapshot, config_for(skill), BattleRNG.new(battle))
    battle.instance_variable_set(:@portable_ai_cache_signature, signature)
    battle.instance_variable_set(:@portable_ai_plan, plan)
    battle.instance_variable_set(:@portable_ai_last_plan, plan)
    battle.instance_variable_set(:@portable_ai_last_snapshot, snapshot)
    plan
  end

  # What the actor believed about the board when it chose: its own HP and speed order,
  # the incoming-damage estimates the heal and priority gates read, and the hits-to-KO
  # both ways per target. The race is reported AS COMPUTED, independently of whether
  # the run has the rules that consume it switched on -- a trace that only showed the
  # race when it was live could not say why a run with it off decided differently.
  DEFAULT_RACE_CONFIG = { "damage_race" => true }

  def self.view_trace(snapshot, index)
    return {} if !snapshot
    actor = nil
    (snapshot["actors"] || []).each do |candidate|
      actor = candidate if candidate["index"] == index
    end
    return {} if !actor
    race = {}
    (snapshot["targets"] || []).each do |target|
      race[target["index"].to_s] =
        PortableAI.damage_race(snapshot, actor, target, DEFAULT_RACE_CONFIG)
    end
    {
      "hp_pct" => actor["hp_pct"],
      "speed" => actor["speed"],
      "faster" => actor["faster"],
      "incoming_damage_pct" => actor["incoming_damage_pct"],
      "certain_incoming_damage_pct" => actor["certain_incoming_damage_pct"],
      "threatened_lethal" => actor["threatened_lethal"],
      "race" => race
    }
  rescue
    {}
  end

  def self.clear_cache(battle)
    return if !battle
    battle.instance_variable_set(:@portable_ai_cache_signature, nil)
    battle.instance_variable_set(:@portable_ai_plan, nil)
    battle.instance_variable_set(:@portable_ai_last_plan, nil)
    battle.instance_variable_set(:@portable_ai_last_snapshot, nil)
  rescue
  end

  def self.cache_signature(battle)
    active = []
    [1, 3].each do |i|
      battler = battle.battlers[i] rescue nil
      next if !battler || battler.isFainted?
      active << [i, battler.pokemonIndex, battler.hp, battler.status]
    end
    [battle.turncount, active]
  end

  def self.build_snapshot(battle)
    indices = [1]
    indices << 3 if battle.doublebattle
    indices = indices.select do |i|
      battler = battle.battlers[i] rescue nil
      battler && !battler.isFainted?
    end
    raise "no active opposing battlers" if indices.empty?

    foe_indices = [0]
    foe_indices << 2 if battle.doublebattle
    foe_indices = foe_indices.select do |i|
      battler = battle.battlers[i] rescue nil
      battler && !battler.isFainted?
    end

    skills = indices.map { |i| corrected_skill(battle.pbGetOwner(i)) }
    skill = skills.min || 100
    targets = foe_indices.map { |i| battler_view(battle.battlers[i], battle, skill) }
    actors = indices.map do |i|
      build_actor(battle, i, foe_indices, skill)
    end

    memory = battle.instance_variable_get(:@portable_ai_memory) || {}
    [{
      "format" => battle.doublebattle ? "double" : "single",
      "turn" => battle.turncount,
      "weather" => weather_name(battle),
      "trick_room_active" => trick_room_active?(battle),
      "tailwind_active" => (safe_side_effect(battle.sides[1], :Tailwind, 0).to_i > 0),
      "actors" => actors,
      "targets" => targets,
      "memory" => memory
    }, skill]
  end

  def self.battler_view(battler, battle, skill)
    physical, special = attack_bias(battle, battler, skill)
    partner = (battler.pbPartner rescue nil)
    {
      "index" => battler.index,
      "species" => battler.species,
      "hp_pct" => percent(battler.hp, battler.totalhp),
      "status" => battler.status,
      "types" => [battler.type1, battler.type2],
      "speed" => battler_speed(battler),
      # Switch scoring needs the foe's boost level and, unlike a move action, has no
      # scoring target to read it from (core.rb foe_boost_total).
      "positive_stages" => positive_stages(battler),
      # 0.5.0 facts. Plain uppercase names and booleans only: the core matches them
      # against its own tables and never sees a PBAbilities/PBItems constant.
      "ability" => ability_key(battler),
      "item" => item_key(battler),
      "full_hp" => (battler.hp >= battler.totalhp),
      "physical_attacker" => physical,
      "special_attacker" => special,
      "substitute" => (safe_effect(battler, :Substitute, 0).to_i > 0),
      "partner_ability" => (partner && !partner.isFainted? ? ability_key(partner) : nil)
    }
  end

  def self.build_actor(battle, index, foe_indices, skill)
    battler = battle.battlers[index]
    actions = []
    battler.moves.each_with_index do |move, slot|
      next if !move || move.id == 0
      next if !battle.pbCanChooseMove?(index, slot, false)
      move_actions(battle, battler, move, slot, foe_indices, skill).each do |action|
        actions << action
      end
    end
    switch_actions(battle, battler, foe_indices, skill).each { |action| actions << action }

    damaging = actions.select { |action| action["type"] == "move" && action["damaging"] }
    best_damage = 0
    damaging.each do |action|
      damage = PortableAI::Model.number(action["expected_damage_pct"], 0)
      best_damage = damage if damage > best_damage
    end
    no_effective = !damaging.empty? && damaging.all? do |action|
      PortableAI::Model.truthy(action["immune"]) ||
        PortableAI::Model.number(action["effectiveness"], 1) <= 0
    end
    negative_stages = 0
    battler.stages.each { |stage| negative_stages += stage if stage && stage < 0 }
    speed = battler_speed(battler)
    partner = (battler.pbPartner rescue nil)
    partner_alive = (partner && !partner.isFainted?) ? true : false

    incoming_map = incoming_damage_by_move(battle, battler, foe_indices, skill)
    incoming = 0.0
    incoming_map.each_value { |damage| incoming = damage if damage > incoming }
    certain = certain_incoming_damage(battle, battler, foe_indices, incoming_map, skill)
    toxic_stage = safe_effect(battler, :Toxic, 0).to_i
    residual = 0.0
    residual += (toxic_stage + 1) * 100.0 / 16.0 if toxic_stage > 0
    residual += 100.0 / 8.0 if safe_effect(battler, :LeechSeed, -1).to_i >= 0
    {
      "index" => index,
      "species" => battler.species,
      "hp_pct" => percent(battler.hp, battler.totalhp),
      "status" => battler.status,
      "speed" => speed,
      "faster" => faster_than_foes?(battle, speed, foe_indices),
      "stages" => battler.stages.clone,
      "negative_stage_total" => negative_stages,
      # 0.6.2: the durable record of "I have already set up", which the memory counter
      # is not -- apply_memory zeroes it on any non-setup action.
      "positive_stage_total" => positive_stages(battler),
      "incoming_damage_pct" => incoming,
      "certain_incoming_damage_pct" => certain,
      "incoming_by_move" => incoming_map,
      # 0.6.0: the per-foe view of the same threat, which is what a hits-to-KO question
      # has to read. Absent on an adapter that does not build it, and the core's
      # damage_race then returns nil and every consumer goes inert.
      "threats_by_foe" => threats_by_foe(battle, battler, foe_indices, incoming_map, skill),
      "threatened_lethal" => incoming >= percent(battler.hp, battler.totalhp),
      "no_effective_move" => no_effective,
      "best_damage_pct" => best_damage,
      "yawned" => safe_effect(battler, :Yawn, 0).to_i > 0,
      "residual_damage_pct" => residual,
      "trapped" => !has_legal_switch?(battle, index),
      "ability" => ability_key(battler),
      "item" => item_key(battler),
      # Mold Breaker turns the target's Sturdy off, so the kill call stands.
      "mold_breaker" => (battler.hasMoldBreaker rescue false) ? true : false,
      "slower_bench_count" => slower_bench_count(battle, battler, foe_indices),
      "partner_alive" => partner_alive,
      "partner_ability" => (partner_alive ? ability_key(partner) : nil),
      "partner_hp_pct" => (partner_alive ? percent(partner.hp, partner.totalhp) : nil),
      "partner_airborne" => (partner_alive ? (partner.isAirborne? rescue false) : false),
      # Fake Out and First Impression are worth +115 on turn 0 and nothing after.
      # Without this the core's turn_shape_rules fired every turn and the AI re-clicked
      # a move the engine refuses (core.rb first_turn_hit).
      "turncount" => (battler.turncount.to_i rescue 0),
      "actions" => actions
    }
  end

  def self.move_actions(battle, battler, move, slot, foe_indices, skill)
    targets = legal_targets(battle, battler, move, foe_indices)
    spread = PBTargets.hasMultipleTargets?(move)
    move_id = move_key(move.id)

    if spread
      scored = foe_indices.map do |target_index|
        target = battle.battlers[target_index]
        action_for_target(battle, battler, move, slot, move_id, target, nil, skill)
      end
      return [] if scored.empty?
      action = scored[0]
      action["base_score"] = average(scored.map { |item| item["base_score"] })
      action["expected_damage_pct"] = scored.inject(0) do |sum, item|
        sum + PortableAI::Model.number(item["expected_damage_pct"], 0)
      end
      action["target"] = nil
      action["spread"] = true
      if PortableAI::Effects.tagged?(move_id, [], "friendly_fire")
        partner = battler.pbPartner
        if partner && !partner.isFainted?
          action["friendly_fire_pct"] = rough_damage_pct(battle, move, battler, partner, skill)
          action["partner_hp_pct"] = percent(partner.hp, partner.totalhp)
        end
      end
      return [action]
    end

    if targets.empty?
      opponent = foe_indices.empty? ? nil : battle.battlers[foe_indices[0]]
      return [action_for_target(battle, battler, move, slot, move_id, opponent, nil, skill)]
    end

    targets.map do |target_index|
      target = battle.battlers[target_index]
      registration_target = explicit_target?(move) ? target_index : nil
      action = action_for_target(
        battle, battler, move, slot, move_id, target, registration_target, skill
      )
      partner = battler.pbPartner
      if partner && target_index == partner.index
        action["friendly_target"] = true
        # Pollen Puff aimed at the partner is a HEAL, not friendly fire (083:9897).
        heals = PARTNER_HEAL_CODES.include?((move.function rescue nil))
        if move.pbIsDamaging? && !heals
          action["friendly_fire_pct"] = action["expected_damage_pct"]
          action["partner_hp_pct"] = percent(partner.hp, partner.totalhp)
        end
      end
      action
    end
  end

  def self.action_for_target(battle, battler, move, slot, move_id, target, register_target, skill)
    scoring_target = target
    scoring_target = battler.pbOppositeOpposing if !scoring_target || scoring_target.index == battler.index
    base = battle.pbGetMoveScore(move, battler, scoring_target, skill)
    effectiveness = type_effectiveness(battle, move, battler, scoring_target)
    tags = PortableAI::Effects.describe(move_id, [])
    blocked = !move.pbIsDamaging? && status_blocked?(move, tags, battler, scoring_target)
    kind, stat, chance = move_effect(battle, move, battler, scoring_target)
    physical, special = scoring_target ? attack_bias(battle, scoring_target, skill) : [false, false]
    code = (move.function rescue nil)
    {
      "type" => "move",
      "actor_index" => battler.index,
      "slot" => slot,
      "move_id" => move_id,
      "numeric_move_id" => move.id,
      "target" => register_target,
      "base_score" => base,
      "damaging" => move.pbIsDamaging?,
      "power" => move.basedamage,
      "priority" => effective_priority(move, battler),
      # 0.5.0 move facts, all from the engine.
      "move_type" => type_key((move.pbType(move.type, battler, scoring_target) rescue move.type)),
      "contact" => ((move.isContactMove? rescue false) ? true : false),
      "effect_kind" => kind,
      "effect_stat" => stat,
      "effect_chance" => chance,
      "multi_hit" => multi_hit?(move),
      "recoil_fraction" => MOVE_RECOIL_CODES[code],
      "drain_fraction" => MOVE_DRAIN_CODES[code],
      "mold_breaker" => (battler.hasMoldBreaker rescue false) ? true : false,
      # Mirrors of the target view, so a spread action (which has no single target) and
      # a unit test both reach the same facts.
      "target_species" => (scoring_target ? scoring_target.species : nil),
      "target_ability" => (scoring_target ? ability_key(scoring_target) : nil),
      "target_item" => (scoring_target ? item_key(scoring_target) : nil),
      "target_full_hp" =>
        (scoring_target ? (scoring_target.hp >= scoring_target.totalhp) : false),
      "target_speed" => (scoring_target ? battler_speed(scoring_target) : nil),
      "target_physical_attacker" => physical,
      "target_special_attacker" => special,
      "target_substitute" =>
        (scoring_target ? (safe_effect(scoring_target, :Substitute, 0).to_i > 0) : false),
      "effectiveness" => effectiveness,
      "immune" => (move.pbIsDamaging? && effectiveness <= 0) || blocked,
      "expected_damage_pct" => rough_damage_pct(battle, move, battler, scoring_target, skill),
      "accuracy" => rough_accuracy(battle, move, battler, scoring_target, skill),
      "target_hp_pct" => (scoring_target ? percent(scoring_target.hp, scoring_target.totalhp) : nil),
      "tags" => tags,
      "spread" => false,
      "existing_layers" => existing_layers(battle, move_id, false),
      "max_layers" => max_layers(move_id),
      "own_hazard_layers" => own_hazard_layers(battle),
      "foe_hazard_layers" => opposing_hazard_layers(battle),
      "target_positive_stages" => positive_stages(scoring_target),
      "effect_active" => effect_active?(battle, move_id, battler),
      # NOTE: no "failed_last_turn". The Reborn adapter reads PBEffects::Tantrum, the
      # flag its engine keeps for Stomping Tantrum. Realidea declares the equivalent as
      # PBEffects::LastMoveFailed = 4 -- but in the MOVE-USAGE namespace, which is the
      # same index as the BATTLER effect BideDamage = 4 (075_PBEffects.rb:8 and :170).
      # The battler's copy is initialised to false (080:415) and NOTHING in the build
      # ever sets it true; the only writes to index 4 are Bide's damage accumulator, so
      # this engine's own Stomping Tantrum doubling is dead code. successStates is not
      # a substitute: useState is set to 2 only on the damaging path (080:3223), so a
      # status move that worked perfectly reads back as 1 = failed.
      #
      # Exporting the key from either source would be worse than leaving it out: the
      # core's move_memory rule takes 200 points off a move, and it would take them off
      # the wrong ones. Absent, Model.truthy reads nil and the rule is inert, which is
      # the honest answer for this engine. AI_Probe::UNSUPPORTED skips the corpus pair
      # that tests it.
      "foe_reserves" => reserve_count(battle, battler.pbOppositeOpposing.index),
      "hazard_targets" => hazard_target_count(battle, move_id, battler.index),
      "own_reserves" => reserve_count(battle, battler.index)
    }
  end

  def self.legal_targets(battle, battler, move, foe_indices)
    case move.target
    when PBTargets::SingleNonUser
      out = foe_indices.clone
      partner = battler.pbPartner
      out << partner.index if partner && !partner.isFainted?
      out
    when PBTargets::SingleOpposing
      foe_indices.clone
    when PBTargets::OppositeOpposing
      target = battler.pbOppositeOpposing
      target = target.pbPartner if target && target.isFainted?
      target && !target.isFainted? ? [target.index] : []
    when PBTargets::RandomOpposing
      foe_indices.clone
    when PBTargets::User
      [battler.index]
    when PBTargets::UserOrPartner
      out = [battler.index]
      partner = battler.pbPartner
      out << partner.index if partner && !partner.isFainted?
      out
    when PBTargets::Partner
      partner = battler.pbPartner
      partner && !partner.isFainted? ? [partner.index] : []
    else
      []
    end
  end

  def self.explicit_target?(move)
    move.target == PBTargets::SingleNonUser ||
      move.target == PBTargets::SingleOpposing ||
      move.target == PBTargets::UserOrPartner ||
      move.target == PBTargets::Partner
  end

  def self.switch_actions(battle, battler, foe_indices, skill)
    party = battle.pbParty(battler.index)
    forced = safe_effect(battler, :PerishSong, 0) == 1
    actions = []
    party.each_with_index do |pokemon, slot|
      next if !pokemon || !battle.pbCanSwitch?(battler.index, slot, false)
      hp_pct = percent(pokemon.hp, pokemon.totalhp)
      matchup = switch_matchup(pokemon, battle, foe_indices)
      hazard = entry_hazard_pct(battle, pokemon, battler)
      next if hazard >= hp_pct
      action = {
        "type" => "switch",
        "actor_index" => battler.index,
        "slot" => slot,
        "base_score" => 20 + hp_pct * 0.35 - hazard,
        "matchup_score" => matchup,
        "incoming_risk" => switch_incoming_risk(pokemon, battle, foe_indices),
        "forced" => forced,
        "safe_entry" => hp_pct > hazard + 20,
        "species" => pokemon.species,
        # candidate_hp_pct and entry_damage_pct restate what is already folded into
        # base_score so the core can ask "is this Pokemon alive at the end of the turn
        # it comes in on" rather than "did it clear the hazards".
        "candidate_hp_pct" => hp_pct,
        "entry_damage_pct" => hazard
      }
      real = switch_incoming_damage(battle, pokemon, slot, battler, foe_indices, skill)
      action["incoming_damage_pct"] = real if !real.nil?
      out = switch_outgoing_damage(battle, pokemon, slot, battler, foe_indices, skill)
      action["outgoing_damage_pct"] = out if !out.nil?
      fast = switch_candidate_faster(battle, pokemon, foe_indices)
      action["faster"] = fast if !fast.nil?
      actions << action
    end
    actions
  end

  # A battler object for a Pokemon that is not on the field, so the entry estimates can
  # be real damage rolls rather than a type-chart proxy. This is what Reborn's
  # pbMakeFakeBattler does internally; v16 has no such helper, so it is spelled out.
  #
  # PokeBattle_Battler#initialize is NOT pure: pbInitEffects clears Attract and MeanLook
  # on every battler pointing at the index being built (080:374-378, :418-424). Building
  # a fake at the actor's own index would therefore silently break a real infatuation or
  # trap, so both effects are snapshotted and restored. pbInitPokemon itself only copies
  # stats and builds move objects through pbFromPBMove (:203-241).
  #
  # nil when the engine refuses, which leaves the core on the type proxy it used
  # through 0.1.0.
  def self.fake_battler(battle, pokemon, party_index, index)
    saved = []
    for i in 0...4
      other = battle.battlers[i]
      next if !other
      saved << [other, other.effects[PBEffects::Attract],
                other.effects[PBEffects::MeanLook]]
    end
    begin
      fake = PokeBattle_Battler.new(battle, index)
      fake.pbInitPokemon(pokemon, party_index)
      fake
    ensure
      saved.each do |entry|
        entry[0].effects[PBEffects::Attract] = entry[1]
        entry[0].effects[PBEffects::MeanLook] = entry[2]
      end
    end
  rescue
    nil
  end

  # What the candidate actually eats on the turn it comes in, with its own Intimidate
  # applied to the foes first -- the only way an entry ability shows up in the number
  # at all. The temporary stage mutation is restored in `ensure`; pbCanReduceStatStage?
  # is what makes Clear Body, White Smoke, Full Metal Body and Hyper Cutter exempt.
  def self.switch_incoming_damage(battle, pokemon, party_index, battler, foe_indices, skill)
    fake = fake_battler(battle, pokemon, party_index, battler.index)
    return nil if !fake
    intimidate = (ability_key(pokemon) == "INTIMIDATE")
    saved = {}
    worst = 0.0
    begin
      if intimidate
        foe_indices.each do |foe_index|
          foe = battle.battlers[foe_index]
          next if !foe || foe.isFainted?
          next if !(foe.pbCanReduceStatStage?(PBStats::ATTACK) rescue false)
          next if (foe.item == PBItems::WHITEHERB rescue false)
          ability = ability_key(foe)
          next if ability == "CONTRARY" || ability == "DEFIANT" || ability == "COMPETITIVE"
          saved[foe_index] = foe.stages[PBStats::ATTACK]
          foe.stages[PBStats::ATTACK] -= 1
        end
      end
      foe_indices.each do |foe_index|
        foe = battle.battlers[foe_index]
        next if !foe || foe.isFainted?
        foe.moves.each do |known|
          next if !known || known.id == 0
          damage = rough_damage_pct(battle, known, foe, fake, skill)
          worst = damage if damage > worst
        end
      end
    ensure
      saved.each do |foe_index, value|
        battle.battlers[foe_index].stages[PBStats::ATTACK] = value
      end
    end
    worst
  rescue
    nil
  end

  # The mirror: the best real hit this candidate has into any current foe, so the core
  # can ask how many turns it needs rather than only how many it survives. v16's
  # pbFromPBMove takes (battle, move) -- no user argument (082:50).
  def self.switch_outgoing_damage(battle, pokemon, party_index, battler, foe_indices, skill)
    fake = fake_battler(battle, pokemon, party_index, battler.index)
    return nil if !fake
    best = 0.0
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      next if !foe || foe.isFainted?
      (pokemon.moves || []).each do |own|
        next if !own || own.id == 0
        move = (PokeBattle_Move.pbFromPBMove(battle, own) rescue nil)
        next if !move
        damage = rough_damage_pct(battle, move, fake, foe, skill)
        best = damage if damage > best
      end
    end
    best
  rescue
    nil
  end

  # Whether the candidate would outrun every current foe once it is in. A benched
  # Pokemon has no battler and therefore no pbSpeed, so this reads the party entry's own
  # Speed stat -- no stages, which is right: a switch-in enters at stage 0.
  def self.switch_candidate_faster(battle, pokemon, foe_indices)
    speed = (pokemon.speed rescue nil)
    return nil if speed.nil?
    faster_than_foes?(battle, speed, foe_indices)
  rescue
    nil
  end

  # The mirror of switch_matchup: how hard the foe hits the candidate coming in, scored
  # off the foe's own types rather than its moveset so this stays inside the
  # fair-information contract. Same units as switch_matchup (neutral 8, x4 = 32), and
  # the worst foe is taken rather than the sum.
  def self.switch_incoming_risk(pokemon, battle, foe_indices)
    worst = 0
    types = [pokemon.type1, pokemon.type2].compact.uniq
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      next if !foe
      [foe.type1, foe.type2].compact.uniq.each do |attacking|
        value = PBTypes.getCombinedEffectiveness(attacking, types[0], types[-1], -1)
        worst = value if value > worst
      end
    end
    worst * 4
  rescue
    0
  end

  # How many benched Pokemon are slower than every current foe. Trick Room is a
  # whole-team investment, so it is only worth a turn when the team behind the actor is
  # slow too.
  def self.slower_bench_count(battle, battler, foe_indices)
    fastest = 0
    foe_indices.each do |foe_index|
      speed = battler_speed(battle.battlers[foe_index])
      fastest = speed if speed && speed > fastest
    end
    return 0 if fastest <= 0
    count = 0
    battle.pbParty(battler.index).each_with_index do |pokemon, slot|
      next if !pokemon || pokemon.hp <= 0 || pokemon.isEgg?
      next if slot == battler.pokemonIndex
      speed = (pokemon.speed rescue nil)
      count += 1 if speed && speed < fastest
    end
    count
  rescue
    0
  end

  def self.switch_matchup(pokemon, battle, foe_indices)
    best = 0
    (pokemon.moves || []).each do |pokemon_move|
      next if !pokemon_move || pokemon_move.id == 0
      data = PBMoveData.new(pokemon_move.id) rescue nil
      next if !data || data.basedamage <= 0
      total = 0
      foe_indices.each do |foe_index|
        foe = battle.battlers[foe_index]
        type3 = safe_effect(foe, :Type3, -1)
        total += PBTypes.getCombinedEffectiveness(data.type, foe.type1, foe.type2, type3)
      end
      best = total if total > best
    end
    best * 4
  rescue
    0
  end

  def self.type_effectiveness(battle, move, attacker, target)
    return 1.0 if !target || !move.pbIsDamaging?
    move.pbTypeModifier(move.type, attacker, target).to_f / 8.0
  rescue
    1.0
  end

  # Same base-damage preparation stock v16 does before it calls pbRoughDamage
  # (085_PokeBattle_AI.rb:2802-2810): basedamage 1 is the "variable power" sentinel and
  # scores as 60, and pbBetterBaseDamage resolves the ~30 function codes that compute
  # their own power (Seismic Toss, Super Fang, Night Shade, Gyro Ball, Grass Knot...).
  # Passing raw basedamage instead, as this adapter did through 0.1.0, priced every one
  # of those at its sentinel.
  def self.rough_damage_pct(battle, move, attacker, target, skill)
    return 0.0 if !target || !move.pbIsDamaging? || move.basedamage <= 0
    base = move.basedamage
    base = 60 if base == 1
    base = battle.pbBetterBaseDamage(move, attacker, target, skill, base) rescue base
    damage = battle.pbRoughDamage(move, attacker, target, skill, base)
    percent(damage, target.totalhp)
  rescue
    0.0
  end

  def self.battler_speed(battler)
    return nil if !battler
    (battler.pbSpeed rescue battler.speed)
  rescue
    nil
  end

  # Hit chance 0-100 as the engine computes it, including ability, weather and
  # accuracy/evasion stages (085:3716). 125 is v16's never-miss sentinel (:3770), so it
  # is clamped rather than handed to the core as a >100 probability. nil when the
  # primitive is unavailable, which the core reads as "do not discount".
  def self.rough_accuracy(battle, move, attacker, target, skill)
    return nil if !target
    value = battle.pbRoughAccuracy(move, attacker, target, skill)
    return nil if value.nil?
    value = 100 if value > 100
    value.to_f
  rescue
    nil
  end

  # Priority as the engine brackets it (084:1105-1113): Prankster on a status move,
  # Gale Wings on a Flying move, Triage on a healing move. Nothing else moves priority
  # in this build -- Psychic Terrain is set by move 0x169 and read by NOTHING, so the
  # Reborn clause that zeroes a priority move under it is deliberately absent here.
  def self.effective_priority(move, battler)
    priority = move.priority
    if (battler.hasWorkingAbility(:PRANKSTER) rescue false) && (move.pbIsStatus? rescue false)
      priority += 1
    end
    flying = (PBTypes.const_get(:FLYING) rescue nil)
    if (battler.hasWorkingAbility(:GALEWINGS) rescue false) && !flying.nil? &&
       move.type == flying
      priority += 1
    end
    if (battler.hasWorkingAbility(:TRIAGE) rescue false) && (move.isHealingMove? rescue false)
      priority += 3
    end
    priority
  rescue
    move.priority
  end

  # Reborn's own convention (pbAIfaster?): strictly greater is faster, a tie is not,
  # and Trick Room inverts the comparison. nil when either speed is unavailable, which
  # every rule reading it treats as "unknown, do not penalise".
  def self.faster_than_foes?(battle, speed, foe_indices)
    return nil if speed.nil?
    fastest = nil
    foe_indices.each do |foe_index|
      foe_speed = battler_speed(battle.battlers[foe_index])
      next if foe_speed.nil?
      fastest = foe_speed if fastest.nil? || foe_speed > fastest
    end
    return nil if fastest.nil?
    trick_room_active?(battle) ? speed < fastest : speed > fastest
  end

  def self.trick_room_active?(battle)
    safe_field_effect(battle, :TrickRoom, 0).to_i > 0
  rescue
    false
  end

  # Every foe move's estimated hit on this battler, keyed "<foe index>:<move id>". The
  # maximum is what the threat rules read.
  #
  # A Choice item that has already locked in is a CERTAINTY about what is coming and the
  # strongest one available: the foe cannot use anything else until it switches
  # (PBEffects::ChoiceBand holds the move id, -1 when free, 080:3725).
  def self.incoming_damage_by_move(battle, battler, foe_indices, skill)
    out = {}
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      next if !foe
      locked = safe_effect(foe, :ChoiceBand, -1).to_i
      foe.moves.each do |known|
        next if !known || known.id == 0
        next if locked >= 0 && known.id != locked
        out["#{foe_index}:#{known.id}"] = rough_damage_pct(battle, known, foe, battler, skill)
      end
    end
    out
  end

  # The same incoming_map resolved PER FOE, with the two extra facts a hits-to-KO
  # question needs: that foe's best hit, its best hit that moves first, and whether it
  # outruns this battler. incoming_by_move is keyed "foe:moveid" with no priority, and
  # actor["faster"] is against the FASTEST foe only -- in doubles that is the wrong
  # flag for the slower target and a race computed off it is wrong.
  #
  # Keyed by foe index as a STRING, because the core reads it out of a plain Hash that
  # has been through JSON in the probe's results file.
  def self.threats_by_foe(battle, battler, foe_indices, incoming_map, skill)
    speed = battler_speed(battler)
    out = {}
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      next if !foe || foe.isFainted?
      locked = safe_effect(foe, :ChoiceBand, -1).to_i
      best = 0.0
      best_priority = 0.0
      foe.moves.each do |known|
        next if !known || known.id == 0
        next if locked >= 0 && known.id != locked
        # Reuse the map the actor already paid for; fall back for anything not in it.
        damage = incoming_map["#{foe_index}:#{known.id}"]
        damage = rough_damage_pct(battle, known, foe, battler, skill) if damage.nil?
        damage = PortableAI::Model.number(damage, 0.0)
        best = damage if damage > best
        next if effective_priority(known, foe) <= 0
        best_priority = damage if damage > best_priority
      end
      out[foe_index.to_s] = {
        "damage_pct" => best,
        "priority_damage_pct" => best_priority,
        "faster" => faster_than_foes?(battle, speed, [foe_index])
      }
    end
    out
  rescue
    {}
  end

  def self.estimated_incoming_damage(battle, battler, foe_indices, skill)
    maximum = 0.0
    incoming_damage_by_move(battle, battler, foe_indices, skill).each_value do |damage|
      maximum = damage if damage > maximum
    end
    maximum
  end

  # The largest incoming hit that cannot fail to happen: the foe is not frozen or asleep
  # with sleep still to serve, and the move never misses as the engine computes its hit
  # chance. The core's "you die whatever you click" rules read this under strict_threat;
  # the loose maximum stays for the soft rules.
  def self.certain_incoming_damage(battle, battler, foe_indices, incoming_map, skill)
    maximum = 0.0
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      next if !foe || !foe_can_act?(foe)
      foe.moves.each do |known|
        next if !known || known.id == 0
        damage = incoming_map["#{foe_index}:#{known.id}"]
        next if !damage || damage <= 0
        accuracy = rough_accuracy(battle, known, foe, battler, skill)
        next if !accuracy.nil? && accuracy < 100
        maximum = damage if damage > maximum
      end
    end
    maximum
  end

  def self.foe_can_act?(foe)
    status = foe.status
    return false if status == PBStatuses::FROZEN
    if status == PBStatuses::SLEEP
      # One turn left means it wakes and acts this turn.
      return false if (foe.statusCount rescue 0).to_i > 1
    end
    true
  rescue
    true
  end

  def self.has_legal_switch?(battle, index)
    party = battle.pbParty(index)
    party.each_with_index do |pokemon, slot|
      return true if pokemon && battle.pbCanSwitch?(index, slot, false)
    end
    false
  rescue
    false
  end

  def self.reserve_count(battle, index)
    count = 0
    party = battle.pbParty(index)
    party.each_with_index do |pokemon, slot|
      next if !pokemon || pokemon.hp <= 0 || pokemon.isEgg?
      active = battle.battlers.any? do |battler|
        battler && battle.pbIsOpposing?(battler.index) == battle.pbIsOpposing?(index) &&
          battler.pokemonIndex == slot && !battler.isFainted?
      end
      count += 1 if !active
    end
    count
  rescue
    0
  end

  def self.hazard_target_count(battle, move_id, actor_index)
    party = battle.pbOpposingParty(actor_index)
    count = 0
    party.each do |pokemon|
      next if !pokemon || pokemon.hp <= 0 || pokemon.isEgg?
      # The other half of the exemption above: a party that walks over hazards is a
      # party the hazard move cannot touch.
      next if pokemon_item_key(pokemon) == "HEAVYDUTYBOOTS"
      next if pokemon.hasAbility?(:MAGICGUARD)
      airborne = pokemon.hasType?(:FLYING) || pokemon.hasAbility?(:LEVITATE)
      if move_id == "SPIKES" || move_id == "STICKYWEB"
        count += 1 if !airborne
      elsif move_id == "TOXICSPIKES"
        immune_type = pokemon.hasType?(:POISON) || pokemon.hasType?(:STEEL)
        count += 1 if !airborne && !immune_type
      else
        count += 1
      end
    end
    count
  rescue
    1
  end

  def self.existing_layers(battle, move_id, own_side)
    side = own_side ? battle.sides[1] : battle.sides[0]
    case move_id
    when "SPIKES"       then safe_side_effect(side, :Spikes, 0)
    when "TOXICSPIKES"  then safe_side_effect(side, :ToxicSpikes, 0)
    when "STEALTHROCK"  then safe_side_effect(side, :StealthRock, false) ? 1 : 0
    when "STICKYWEB"     then safe_side_effect(side, :StickyWeb, false) ? 1 : 0
    else 0
    end
  end

  def self.max_layers(move_id)
    return 3 if move_id == "SPIKES"
    return 2 if move_id == "TOXICSPIKES"
    1
  end

  # Hazards already sitting on the half of the field this battler would lay them on.
  def self.opposing_hazard_layers(battle)
    side = battle.sides[0]
    safe_side_effect(side, :Spikes, 0).to_i +
      safe_side_effect(side, :ToxicSpikes, 0).to_i +
      (safe_side_effect(side, :StealthRock, false) ? 1 : 0) +
      (safe_side_effect(side, :StickyWeb, false) ? 1 : 0)
  rescue
    0
  end

  def self.own_hazard_layers(battle)
    side = battle.sides[1]
    safe_side_effect(side, :Spikes, 0).to_i +
      safe_side_effect(side, :ToxicSpikes, 0).to_i +
      (safe_side_effect(side, :StealthRock, false) ? 1 : 0) +
      (safe_side_effect(side, :StickyWeb, false) ? 1 : 0)
  rescue
    0
  end

  def self.effect_active?(battle, move_id, battler)
    side = battle.sides[1]
    case move_id
    when "REFLECT"     then safe_side_effect(side, :Reflect, 0).to_i > 0
    when "LIGHTSCREEN" then safe_side_effect(side, :LightScreen, 0).to_i > 0
    when "SAFEGUARD"   then safe_side_effect(side, :Safeguard, 0).to_i > 0
    when "SUBSTITUTE"  then safe_effect(battler, :Substitute, 0).to_i > 0
    # 0.6.2. Wish fails outright with a Wish already pending. PBEffects::Wish is the
    # countdown on the USER, not a side effect, which is why it is read off the battler.
    when "WISH"        then safe_effect(battler, :Wish, 0).to_i > 0
    else false
    end
  end

  def self.entry_hazard_pct(battle, pokemon, battler)
    side = battle.sides[1]
    # Heavy-Duty Boots and Magic Guard walk over every hazard, so a holder pays nothing
    # to come in. (Boots does not exist in this build's item list; the row costs
    # nothing and keeps the two adapters saying the same thing.)
    return 0 if pokemon_item_key(pokemon) == "HEAVYDUTYBOOTS"
    return 0 if pokemon.hasAbility?(:MAGICGUARD)
    spikes = safe_side_effect(side, :Spikes, 0).to_i
    damage = [0, 12.5, 16.7, 25.0][spikes] || 25.0
    if pokemon.hasType?(:FLYING) || pokemon.hasAbility?(:LEVITATE)
      damage = 0
    end
    if safe_side_effect(side, :StealthRock, false)
      rock = PBTypes.const_get("ROCK") rescue nil
      if rock
        effectiveness = PBTypes.getCombinedEffectiveness(
          rock, pokemon.type1, pokemon.type2, -1
        )
        damage += 12.5 * effectiveness.to_f / 8.0
      else
        damage += 12.5
      end
    end
    damage
  rescue
    0
  end

  # Which attacking stat this battler actually hits with. The burn, paralysis and
  # stat-drop rows all ask it, and stock v16 asks the same question with pbRoughStat
  # (085:2930).
  def self.attack_bias(battle, battler, skill)
    return [false, false] if !battler
    attack = (battle.pbRoughStat(battler, PBStats::ATTACK, skill) rescue nil)
    special = (battle.pbRoughStat(battler, PBStats::SPATK, skill) rescue nil)
    return [false, false] if attack.nil? || special.nil?
    [attack > special, special > attack]
  rescue
    [false, false]
  end

  # kind / stat / chance for one move against one target, all three from the engine.
  # The chance is the move's own addlEffect, doubled by Serene Grace or a Rainbow and
  # zeroed when the secondary is negated -- the same two conditions the engine itself
  # checks before rolling for it (080:3058-3065).
  def self.move_effect(battle, move, battler, target)
    code = (move.function rescue nil)
    return [nil, nil, nil] if code.nil?
    entry = MOVE_EFFECT_CODES[code]
    return [nil, nil, nil] if !entry
    chance = (move.addlEffect rescue 0).to_i
    # A status MOVE (Will-O-Wisp, Toxic, Thunder Wave) carries addlEffect 0 because the
    # status is its whole point, not a secondary; those are certain.
    chance = 100 if !move.pbIsDamaging? || chance <= 0
    if target && move.pbIsDamaging?
      return [entry[0], entry[1], 0] if secondary_negated?(move, battler, target)
      chance *= 2 if serene_grace?(battler) && (move.function rescue 0) != 0xA4
    end
    # A secondary that cannot land is worth nothing, and only the engine knows why not.
    if target
      verdict = engine_can_status?([entry[0]], battler, target)
      return [entry[0], entry[1], 0] if verdict == false
    end
    chance = 100 if chance > 100
    [entry[0], entry[1], chance]
  rescue
    [nil, nil, nil]
  end

  # 080:3059-3061: Sheer Force cancels the secondary outright, and Shield Dust does
  # unless the user has Mold Breaker.
  def self.secondary_negated?(move, battler, target)
    return true if (battler.hasWorkingAbility(:SHEERFORCE) rescue false)
    return false if (battler.hasMoldBreaker rescue false)
    (target.hasWorkingAbility(:SHIELDDUST) rescue false) ? true : false
  rescue
    false
  end

  def self.serene_grace?(battler)
    return true if (battler.hasWorkingAbility(:SERENEGRACE) rescue false)
    (safe_side_effect(battler.pbOwnSide, :Rainbow, 0).to_i > 0 rescue false)
  rescue
    false
  end

  def self.multi_hit?(move)
    return true if (move.pbIsMultiHit rescue false)
    MULTI_HIT_CODES.include?((move.function rescue nil))
  rescue
    false
  end

  def self.positive_stages(battler)
    return 0 if !battler
    total = 0
    battler.stages.each { |stage| total += stage if stage && stage > 0 }
    total
  rescue
    0
  end

  # Universal facts about a NON-DAMAGING move that make it unusable, so the core can
  # stop paying fresh_status +25 for a move the engine will refuse. Mirrors the Reborn
  # adapter's status_blocked? (:1154-1204) against Realidea's own engine, which
  # diverges in three places, each verified in 080_PokeBattle_Battler.rb:
  #
  # 1. Magic Bounce here bounces only moves carrying the Magic Coat flag (flag c,
  #    082_PokeBattle_Move.rb:236) and is turned off by Mold Breaker (:2433). Reborn
  #    reflects every status move and reads the partner's ability too; neither is true
  #    in this engine, so neither is modelled.
  # 2. Prankster is a PRIORITY MODIFIER ONLY here (084:1108, 080:2618). There is no
  #    Dark-type immunity to it anywhere in the build, so the Reborn clause that skips
  #    a Prankster status move into a Dark type is deliberately absent -- modelling it
  #    would make the AI refuse a move that lands.
  # 3. The pbCan*? predicates take the ATTACKER first (081:5-553), not just a
  #    showMessages flag.
  def self.status_blocked?(move, tags, battler, target)
    return false if !target
    return false if !tags.include?("status")
    return true if magic_bounced?(move, battler, target)
    # Thunder Wave into Ground, Toxic into Steel: a typed status move is refused by the
    # engine's own type verdict, which the damaging-move `immune` path never saw
    # because a status move has no base damage.
    if tags.include?("typed_status")
      return true if type_effectiveness_raw(move, battler, target) <= 0
    end
    # Leech Seed sets PBEffects::LeechSeed, not a status CONDITION, so no pbCan*?
    # predicate sees it and a seeded foe looked fresh every turn. The three failure
    # conditions are PokeBattle_Move_0DC#pbEffect (083:6296-6310) exactly.
    if tags.include?("drain")
      return true if safe_effect(target, :LeechSeed, -1).to_i >= 0
      return true if safe_effect(target, :Substitute, 0).to_i > 0
      return true if battler_has_type?(target, :GRASS)
    end
    # Yawn is the same shape one move over: tagged ["status", "sleep"], so the engine
    # check below is pbCanSleep?, which answers about the status CONDITION and says yes
    # about a target that is merely drowsy. The engine's second guard is a separate
    # line, PokeBattle_Move_004#pbEffect (083:189).
    if tags.include?("drowsy") && rule_enabled?("yawn_gate")
      return true if safe_effect(target, :Yawn, 0).to_i > 0
    end
    verdict = engine_can_status?(tags, battler, target)
    return !verdict if !verdict.nil?
    # Rescue path for an engine that does not expose the predicates.
    return true if tags.include?("burn") && battler_has_type?(target, :FIRE)
    return true if tags.include?("poison") &&
                   (battler_has_type?(target, :POISON) || battler_has_type?(target, :STEEL))
    return true if tags.include?("powder") && battler_has_type?(target, :GRASS)
    return true if tags.include?("paralyze") && battler_has_type?(target, :ELECTRIC)
    false
  rescue
    false
  end

  # true/false from the engine, or nil when this move applies no status the engine can
  # be asked about (so the caller falls through to the type list). showMessages is
  # false: these predicates print "But it failed!" otherwise.
  def self.engine_can_status?(tags, battler, target)
    return target.pbCanBurn?(battler, false)     if tags.include?("burn")
    return target.pbCanPoison?(battler, false)   if tags.include?("poison")
    return target.pbCanParalyze?(battler, false) if tags.include?("paralyze")
    return target.pbCanSleep?(battler, false)    if tags.include?("sleep")
    return target.pbCanFreeze?(battler, false)   if tags.include?("freeze")
    return target.pbCanConfuse?(battler, false)  if tags.include?("confuse")
    nil
  rescue
    nil
  end

  def self.magic_bounced?(move, battler, target)
    return false if !(move.canMagicCoat? rescue false)
    return false if (battler.hasMoldBreaker rescue false)
    ability_key(target) == "MAGICBOUNCE"
  rescue
    false
  end

  # The engine's raw type verdict on the 8-is-neutral scale, for a move with no base
  # damage (type_effectiveness returns a flat 1.0 for those).
  def self.type_effectiveness_raw(move, attacker, target)
    move.pbTypeModifier(move.type, attacker, target).to_i
  rescue
    8
  end

  def self.battler_has_type?(battler, symbol)
    battler.pbHasType?(symbol)
  rescue
    type = (PBTypes.const_get(symbol) rescue nil)
    return false if type.nil?
    battler.type1 == type || battler.type2 == type
  end

  def self.safe_effect(battler, name, fallback)
    return fallback if !PBEffects.const_defined?(name.to_s)
    value = PBEffects.const_get(name.to_s)
    battler.effects[value]
  rescue
    fallback
  end

  def self.safe_side_effect(side, name, fallback)
    return fallback if !PBEffects.const_defined?(name.to_s)
    value = PBEffects.const_get(name.to_s)
    side.effects[value]
  rescue
    fallback
  end

  def self.safe_field_effect(battle, name, fallback)
    return fallback if !PBEffects.const_defined?(name.to_s)
    value = PBEffects.const_get(name.to_s)
    battle.field.effects[value]
  rescue
    fallback
  end

  # Ability and item names as uppercase strings, resolved through the CONSTANT tables
  # rather than through PBAbilities.getName / PBItems.getName -- getName goes to the
  # compiled message file, which in this build is Spanish, and returns an empty string
  # for every id in the probe/gauntlet environment that has no message data loaded.
  # The constants come from Data/Constants.rxdata and are always there.
  def self.ability_key(battler_or_pokemon)
    value = (battler_or_pokemon.ability rescue nil)
    return nil if value.nil? || value == 0
    constant_key(PBAbilities, :@ability_keys, value)
  rescue
    nil
  end

  # Uppercase type name ("FIRE"), the same shape the core's absorb and redirect tables
  # are keyed by. Built once from PBTypes, like move_key.
  def self.type_key(id)
    return nil if id.nil?
    constant_key(PBTypes, :@type_keys, id)
  end

  def self.item_key(battler_or_pokemon)
    value = (battler_or_pokemon.item rescue nil)
    return nil if value.nil? || value == 0
    constant_key(PBItems, :@item_keys, value)
  rescue
    nil
  end

  # A party entry exposes its held item through the same reader; kept as its own name
  # so the hazard rows read as being about a benched Pokemon.
  def self.pokemon_item_key(pokemon)
    item_key(pokemon)
  end

  def self.constant_key(namespace, cache_name, value)
    cache = instance_variable_get(cache_name)
    if !cache
      cache = {}
      namespace.constants.each do |name|
        id = namespace.const_get(name) rescue nil
        cache[id] = name.to_s.upcase if id.is_a?(Integer)
      end
      instance_variable_set(cache_name, cache)
    end
    cache[value]
  rescue
    nil
  end

  def self.move_key(id)
    if !defined?(@move_keys) || !@move_keys
      @move_keys = {}
      PBMoves.constants.each do |name|
        value = PBMoves.const_get(name) rescue nil
        @move_keys[value] = name.to_s.upcase if value.is_a?(Integer)
      end
    end
    @move_keys[id] || id.to_s
  end

  def self.weather_name(battle)
    weather = battle.pbWeather rescue battle.weather
    return "rain" if defined?(PBWeather::RAINDANCE) && weather == PBWeather::RAINDANCE
    return "rain" if defined?(PBWeather::HEAVYRAIN) && weather == PBWeather::HEAVYRAIN
    return "sun" if defined?(PBWeather::SUNNYDAY) && weather == PBWeather::SUNNYDAY
    return "sun" if defined?(PBWeather::HARSHSUN) && weather == PBWeather::HARSHSUN
    return "sand" if defined?(PBWeather::SANDSTORM) && weather == PBWeather::SANDSTORM
    return "hail" if defined?(PBWeather::HAIL) && weather == PBWeather::HAIL
    "none"
  end

  def self.percent(value, total)
    return 0.0 if !total || total.to_f <= 0
    value.to_f * 100.0 / total.to_f
  end

  def self.average(values)
    return 0.0 if values.empty?
    values.inject(0.0) do |sum, value|
      sum + PortableAI::Model.number(value, 0)
    end / values.length
  end

  def self.apply_action(battle, index, action)
    if action["type"] == "switch"
      return battle.pbRegisterSwitch(index, action["slot"])
    end
    return false if !battle.pbRegisterMove(index, action["slot"], false)
    target = action["target"]
    battle.pbRegisterTarget(index, target) if !target.nil? && battle.doublebattle
    true
  end

  def self.apply_memory(battle, index, action)
    memory = battle.instance_variable_get(:@portable_ai_memory) || {}
    state = memory[index.to_s] || {}
    selected_key = nil
    if action["type"] == "switch"
      selected_key = "switch"
    else
      tags = PortableAI::Effects.describe(action["move_id"], action["tags"])
      if tags.include?("setup")
        selected_key = "setup"
      elsif tags.include?("protect") || tags.include?("team_protect")
        selected_key = "protect"
      elsif tags.include?("substitute")
        selected_key = "substitute"
      end
    end
    previous_count = selected_key ? state[selected_key].to_i : 0
    %w[setup protect substitute switch].each { |key| state[key] = 0 }
    if action["type"] == "switch"
      state["switch"] = previous_count + 1
    else
      state[selected_key] = previous_count + 1 if selected_key
      state["last_move"] = action["move_id"]
    end
    state["last_type"] = action["type"]
    memory[index.to_s] = state
    battle.instance_variable_set(:@portable_ai_memory, memory)
  end

  # Run-level knobs read from Data/ai_harness.txt, in the same key=value format the
  # Reborn harness uses (AI_Harness.rb:51-64). It lives HERE rather than in the
  # gauntlet because the probe needs it too and the probe is a separate script section
  # that loads earlier -- and because the thing that consumes $PORTABLE_AI_CONFIG is
  # this module, not the benchmark that happens to set it.
  module Harness
    FILE = "Data/ai_harness.txt"

    # Core config keys a run may override, with the type each parses to. Booleans
    # become real true/false: the core tests them with plain Ruby truthiness, and the
    # string "false" is truthy. Same nineteen keys as the Reborn gauntlet
    # (Portable_AI_Gauntlet.rb:37-70), so an ablation reads identically in both studies.
    CONFIG_OVERRIDE_KEYS = [
      ["switch_risk_weight", :float],
      ["accuracy_weight",    :float],
      ["heal_gate",          :boolean],
      ["priority_gate",      :boolean],
      ["self_cost",          :boolean],
      ["strict_threat",      :boolean],
      # 0.5.0 tables. All four false is 0.4.1, which is the control run.
      ["side_effects",       :boolean],
      ["ability_rules",      :boolean],
      ["entry_rules",        :boolean],
      ["format_rules",       :boolean],
      # 0.6.0. damage_race=false is the control for the damage-race batch.
      ["damage_race",        :boolean],
      ["damage_race_switch", :boolean],
      # 0.6.2 bugfix batch, one key each so the arms can be ablated singly.
      ["spread_target_hp",   :boolean],
      ["lethal_flat",        :boolean],
      ["entry_death",        :boolean],
      ["wish_pending",       :boolean],
      ["setup_stage",        :boolean],
      ["move_memory",        :boolean],
      ["yawn_gate",          :boolean]
    ]

    def self.config
      cfg = {}
      return cfg if !File.exist?(FILE)
      File.open(FILE, "rb") do |file|
        file.read.split(/[\r\n]+/).each do |line|
          line = line.strip
          next if line.empty? || line[0, 1] == "#"
          key, value = line.split("=", 2)
          cfg[key.to_s.strip] = value.to_s.strip if key && value
        end
      end
      cfg
    rescue
      {}
    end

    def self.bool(cfg, key, fallback)
      return fallback if !cfg[key] || cfg[key] == ""
      ["true", "1", "yes", "on"].include?(cfg[key].to_s.downcase)
    end

    def self.list(cfg, key, fallback)
      return fallback if !cfg[key] || cfg[key] == ""
      out = []
      cfg[key].to_s.split(",").each do |part|
        part = part.strip
        out << part.to_i if part != ""
      end
      out.empty? ? fallback : out
    end

    def self.config_overrides_from(cfg)
      overrides = {}
      CONFIG_OVERRIDE_KEYS.each do |key, kind|
        value = cfg[key]
        next if !value || value == ""
        overrides[key] = (kind == :float) ? value.to_f : (value == "true")
      end
      overrides
    end

    # Install this run's overrides for the duration of the block and hand the block the
    # raw config so it can read its own non-core keys (trace, seeds, append).
    def self.with_config
      cfg = config
      $PORTABLE_AI_CONFIG = config_overrides_from(cfg)
      yield cfg
    ensure
      $PORTABLE_AI_CONFIG = nil
    end
  end

  def self.log_error(error, index)
    signature = "#{error.class}: #{error.message}"
    return if defined?(@last_error) && @last_error == signature
    @last_error = signature
    File.open(ERROR_FILE, "ab") do |file|
      file.write("actor=#{index} #{signature}\n")
      file.write(error.backtrace[0, 8].join("\n") + "\n") if error.backtrace
    end
  rescue
  end
end

class PokeBattle_Battle
  if !method_defined?(:portable_ai_stock_pbChooseMoves)
    alias portable_ai_stock_pbChooseMoves pbChooseMoves
  end
  if !method_defined?(:portable_ai_stock_pbDefaultChooseEnemyCommand)
    alias portable_ai_stock_pbDefaultChooseEnemyCommand pbDefaultChooseEnemyCommand
  end

  def portable_ai_last_plan
    @portable_ai_last_plan
  end

  def pbChooseMoves(index)
    if PortableAIRealidea.enabled_for?(self, index)
      return if PortableAIRealidea.choose(self, index)
    end
    portable_ai_stock_pbChooseMoves(index)
  end

  def pbDefaultChooseEnemyCommand(index)
    if PortableAIRealidea.enabled_for?(self, index) && pbCanShowCommands?(index)
      return if pbEnemyShouldUseItem?(index)
      if pbCanShowFightMenu?(index)
        return if pbAutoFightMenu(index)
        pbRegisterMegaEvolution(index) if pbEnemyShouldMegaEvolve?(index)
      end
      return if PortableAIRealidea.choose(self, index)
    end
    portable_ai_stock_pbDefaultChooseEnemyCommand(index)
  end
end
