# Portable AI adapter for Realidea (Pokemon Essentials v16).
#
# This file is concatenated after portable_ai/model.rb, effects.rb and core.rb, then
# injected as one script section after "AI edit clara" and before Main.
#
# Safe rollout: the hook is inert unless Data/portable_ai.txt exists or
# $PORTABLE_AI_ENABLED is explicitly true. Any unsupported state or registration failure
# falls back to the exact pbChooseMoves implementation that was live before this section.

module PortableAIRealidea
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
          "score" => action["score"]
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
    plan
  end

  def self.clear_cache(battle)
    return if !battle
    battle.instance_variable_set(:@portable_ai_cache_signature, nil)
    battle.instance_variable_set(:@portable_ai_plan, nil)
    battle.instance_variable_set(:@portable_ai_last_plan, nil)
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
    targets = foe_indices.map { |i| battler_view(battle.battlers[i]) }
    actors = indices.map do |i|
      build_actor(battle, i, foe_indices, skill)
    end

    memory = battle.instance_variable_get(:@portable_ai_memory) || {}
    [{
      "format" => battle.doublebattle ? "double" : "single",
      "turn" => battle.turncount,
      "weather" => weather_name(battle),
      "actors" => actors,
      "targets" => targets,
      "memory" => memory
    }, skill]
  end

  def self.battler_view(battler)
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
      # Plain uppercase name, never a PBAbilities constant: the core matches it
      # against its own tables.
      "ability" => ability_key(battler)
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
    switch_actions(battle, battler, foe_indices).each { |action| actions << action }

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

    incoming = estimated_incoming_damage(battle, battler, foe_indices, skill)
    toxic_stage = safe_effect(battler, :Toxic, 0).to_i
    residual = 0.0
    residual += (toxic_stage + 1) * 100.0 / 16.0 if toxic_stage > 0
    residual += 100.0 / 8.0 if safe_effect(battler, :LeechSeed, -1).to_i >= 0
    {
      "index" => index,
      "species" => battler.species,
      "hp_pct" => percent(battler.hp, battler.totalhp),
      "status" => battler.status,
      "speed" => battler_speed(battler),
      "stages" => battler.stages.clone,
      "negative_stage_total" => negative_stages,
      # 0.6.2: the durable record of "I have already set up", which the memory counter
      # is not -- apply_memory zeroes it on any non-setup action.
      "positive_stage_total" => positive_stages(battler),
      "incoming_damage_pct" => incoming,
      "threatened_lethal" => incoming >= percent(battler.hp, battler.totalhp),
      "no_effective_move" => no_effective,
      "best_damage_pct" => best_damage,
      "yawned" => safe_effect(battler, :Yawn, 0).to_i > 0,
      "residual_damage_pct" => residual,
      "trapped" => !has_legal_switch?(battle, index),
      "ability" => ability_key(battler),
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
      if partner && target_index == partner.index && move.pbIsDamaging?
        action["friendly_fire_pct"] = action["expected_damage_pct"]
        action["partner_hp_pct"] = percent(partner.hp, partner.totalhp)
        action["friendly_target"] = true
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
      "priority" => move.priority,
      "effectiveness" => effectiveness,
      "immune" => (move.pbIsDamaging? && effectiveness <= 0) || blocked,
      "expected_damage_pct" => rough_damage_pct(battle, move, battler, scoring_target, skill),
      "target_hp_pct" => (scoring_target ? percent(scoring_target.hp, scoring_target.totalhp) : nil),
      "tags" => tags,
      "spread" => false,
      "existing_layers" => existing_layers(battle, move_id, false),
      "max_layers" => max_layers(move_id),
      "own_hazard_layers" => own_hazard_layers(battle),
      "target_positive_stages" => positive_stages(scoring_target),
      "effect_active" => effect_active?(battle, move_id, battler),
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

  def self.switch_actions(battle, battler, foe_indices)
    party = battle.pbParty(battler.index)
    forced = safe_effect(battler, :PerishSong, 0) == 1
    actions = []
    party.each_with_index do |pokemon, slot|
      next if !pokemon || !battle.pbCanSwitch?(battler.index, slot, false)
      hp_pct = percent(pokemon.hp, pokemon.totalhp)
      matchup = switch_matchup(pokemon, battle, foe_indices)
      hazard = entry_hazard_pct(battle, pokemon, battler)
      next if hazard >= hp_pct
      actions << {
        "type" => "switch",
        "actor_index" => battler.index,
        "slot" => slot,
        "base_score" => 20 + hp_pct * 0.35 - hazard,
        "matchup_score" => matchup,
        "forced" => forced,
        "safe_entry" => hp_pct > hazard + 20,
        "species" => pokemon.species
      }
    end
    actions
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

  def self.estimated_incoming_damage(battle, battler, foe_indices, skill)
    maximum = 0.0
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      foe.moves.each do |known|
        next if !known || known.id == 0
        damage = rough_damage_pct(battle, known, foe, battler, skill)
        maximum = damage if damage > maximum
      end
    end
    maximum
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
    else false
    end
  end

  def self.entry_hazard_pct(battle, pokemon, battler)
    side = battle.sides[1]
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
