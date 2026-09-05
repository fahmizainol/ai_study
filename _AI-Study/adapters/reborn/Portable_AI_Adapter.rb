# Portable AI adapter for Reborn Yang (Reborn E19.16, v16-era fork, modern Ruby).
#
# Concatenated after portable_ai/model.rb, effects.rb and core.rb by
# tools/build_portable_ai.py --target reborn, installed as Scripts/Portable_AI.rb and
# listed in Data/!script_order.csv after AI_Harness, before Main.
#
# Hook point: PokeBattle_AI#chooseAction is Reborn's single registration site — its
# per-battler loop starts with `next if @battle.choices[i][0] != 0`, so any battler the
# portable side registers first is skipped by the host AI with no further patching.
#
# BENCHMARK POLICY — no silent fallback. The Realidea adapter falls back to the stock
# selector on error, which is safe there because stock IS the baseline. Here fallback
# would mean letting Reborn's own AI decide, silently contaminating any head-to-head
# strength result. Errors are appended to Data/portable_ai_error.txt and re-raised.
#
# BASE SCORE — neutral 100, not the host scorer. In Realidea the portable AI consumes
# stock v16 pbGetMoveScore as its base evidence. Reborn has no stock scorer left; its
# replacement is the 17k-line opinionated AI this benchmark measures against, so using
# it as base evidence is exactly the contamination the policy above forbids. The known
# consequence: the Reborn build leans entirely on the core's own evidence terms, and
# Tier-1/Tier-2 validation (not construction) decides whether that is good enough.
#
# Engine primitives intentionally borrowed from Reborn (adapter-legitimate, per
# AI-PORTABILITY.md §4: damage/type/legality belong to the engine):
#   - PokeBattle_AI#pbRoughDamage        damage estimate (needs @mondata staged)
#   - PokeBattle_AI#pbTypeModNoMessages  type verdict, neutral = 4, -1 = absorb ability
#   - pbCanChooseMove?/pbCanSwitch?/pbRegister* legality and registration
# While estimating, $game_switches[3000] (Intense) is masked off and swappredicted is
# neutralized so Intense-mode cheats cannot leak into the portable side's snapshot.

module PortableAIReborn
  ENABLE_FILE = "Data/portable_ai.txt"

  # Essentials function code -> [effect kind, affected stat]. This is the whole of
  # 0.5.0's move-side-effect knowledge: every burn/paralysis/poison/freeze/flinch
  # secondary, every target stat drop and every self-raise on a damaging move is
  # identified by the code the engine already stores, so ~80 hand-tagged move names
  # are replaced by one table that covers moves nobody has listed. Reborn and Realidea
  # share the code family (both are Essentials 16-era), and the codes were read off
  # Reborn's own dispatch (PokeBattle_AI_2.rb:3442-5510) rather than guessed.
  MOVE_EFFECT_CODES = {
    0x05 => ["poison", nil], 0x06 => ["poison", nil], 0x174 => ["poison", nil],
    0x225 => ["poison", nil], 0x256 => ["poison", nil],
    0x07 => ["paralyze", nil], 0x08 => ["paralyze", nil], 0x09 => ["paralyze", nil],
    0x127 => ["paralyze", nil],
    0x0A => ["burn", nil], 0x0B => ["burn", nil], 0x128 => ["burn", nil],
    0x207 => ["burn", nil], 0x230 => ["burn", nil],
    0x0C => ["freeze", nil], 0x0D => ["freeze", nil], 0x0E => ["freeze", nil],
    0x129 => ["freeze", nil],
    0x0F => ["flinch", nil], 0x10 => ["flinch", nil], 0x11 => ["flinch", nil],
    0x229 => ["flinch", nil], 0x236 => ["flinch", nil],
    # Target stat drops. The stat is the one Reborn passes to oppstatdrop; where a
    # move drops two, the one the core can actually price is named.
    0x42 => ["drop", "atk"], 0x226 => ["drop", "atk"],
    0x43 => ["drop", "def"], 0x4a => ["drop", "def"], 0x4c => ["drop", "def"],
    0x180 => ["drop", "def"],
    0x44 => ["drop", "speed"], 0x4d => ["drop", "speed"], 0x17c => ["drop", "speed"],
    0x13f => ["drop", "speed"],
    0x45 => ["drop", "spa"], 0x13b => ["drop", "spa"],
    0x46 => ["drop", "spd"],
    0x47 => ["drop", "acc"],
    # Self-raise on a damaging move (Power-Up Punch, Flame Charge, Charge Beam).
    0x1d => ["self_raise", "def"], 0x1e => ["self_raise", "def"],
    0x1f => ["self_raise", "speed"], 0x20 => ["self_raise", "spa"],
    0x21 => ["self_raise", "spd"], 0x01C => ["self_raise", "atk"]
  }

  # Recoil fraction of the damage dealt, from Reborn's own table (:4533) plus the
  # three moves that hard-code 1/3.
  MOVE_RECOIL_CODES = {
    0xfa => 0.25, 0xfb => 0.3333, 0xfc => 0.5,
    0xfd => 0.3333, 0xfe => 0.3333, 0x235 => 0.3333
  }

  # Fraction of the damage dealt that is restored to the user.
  MOVE_DRAIN_CODES = { 0xDD => 0.5, 0xDE => 0.5, 0x139 => 0.75 }

  MULTI_HIT_CODES = [0xBD, 0xBE, 0xBF, 0xC0, 0x17e, 0x202, 0x231, 0x251]

  # Reborn field ids for the four terrains the modern metagame actually uses
  # (PBStuff.rb:570-606). Everything else is a Reborn-specific field the portable core
  # has no rule for, and is exported as nil rather than as a name it cannot read.
  TERRAIN_FIELDS = { 1 => "electric", 2 => "grassy", 3 => "misty", 37 => "psychic" }
  ERROR_FILE  = "Data/portable_ai_error.txt"
  ENABLE_WILD = false

  NEUTRAL_BASE_SCORE = 100.0
  TYPEMOD_NEUTRAL    = 4.0

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

  # Shadow mode: build the snapshot and run the planner for the marked side, record
  # what it would have done, and register nothing — the host AI still chooses. Both
  # AIs therefore answer from the identical position on every turn, which is the only
  # way to compare the two policies at scale; two live arms diverge after ~1 turn and
  # everything after that is a different battle.
  #
  # Sound only because the planner is side-effect free at BESTSKILL: it draws from
  # BattleRNG solely for difficulty noise (off when deterministic), and
  # with_neutral_estimation restores every host field it stages. The one thing shadow
  # deliberately does NOT do is apply_memory — portable memory would otherwise record
  # moves the portable AI never made — so a shadow decision does not carry the
  # repeated-setup penalty the same position would attract in a live portable run.
  def self.shadow?
    defined?($PORTABLE_AI_SHADOW) && $PORTABLE_AI_SHADOW ? true : false
  end

  def self.active?
    requested? || shadow?
  end

  # Which battlers the portable AI drives. Default: the opposing (odd) side.
  #
  # The gauntlet needs a stronger identity: Reborn's test environment runs both sides
  # through the SAME odd-side AI path by physically swapping the battle's halves
  # (PokeBattle_TestEnvironment#switchTrainers exchanges @player/@opponent, parties,
  # battlers, choices and aimondata between the two pbChooseEnemyCommand calls of each
  # turn). Index parity therefore points at BOTH teams, one per call. When
  # $PORTABLE_AI_TRAINER is set, the portable side is whichever team that trainer
  # object currently owns — an identity the swap moves around consistently.
  def self.enabled_for?(battle, index)
    return false if !active?
    return false if !battle.pbIsOpposing?(index)
    return false if !ENABLE_WILD && !battle.opponent
    marked = $PORTABLE_AI_TRAINER
    if marked
      owner = battle.pbGetOwner(index) rescue nil
      return owner.equal?(marked)
    end
    true
  rescue
    false
  end

  # Run-level config overrides, set from Data/ai_harness.txt by the gauntlet. Keys not
  # named here keep their skill-derived or Model::DEFAULT_CONFIG value.
  #
  # This exists so one installed build can play both sides of a policy A/B — the
  # alternative is rebuilding and reinstalling between arms, which makes the two arms
  # different artifacts and invites exactly the mix-up the study cannot detect after
  # the fact. Every gauntlet record carries the overrides it ran under.
  def self.config_overrides
    return {} if !defined?($PORTABLE_AI_CONFIG) || !$PORTABLE_AI_CONFIG.is_a?(Hash)
    $PORTABLE_AI_CONFIG
  end

  def self.config_for(skill)
    base =
      if skill >= PokeBattle_AI::BESTSKILL
        {
          "deterministic" => true, "noise" => 0, "switching" => true,
          "memory" => true, "coordination" => true, "knowledge" => "fair"
        }
      elsif skill >= PokeBattle_AI::HIGHSKILL
        {
          "deterministic" => false, "noise" => 5, "switching" => true,
          "memory" => true, "coordination" => true, "knowledge" => "fair"
        }
      elsif skill >= PokeBattle_AI::MEDIUMSKILL
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

  def self.skill_for(ai, index)
    data = ai.aimondata[index]
    data ? data.skill.to_i : PokeBattle_AI::BESTSKILL
  rescue
    PokeBattle_AI::BESTSKILL
  end

  # Entry point, called from the chooseAction hook before the host AI registers
  # anything. Registers portable choices for every opposing battler that still needs
  # one; the host loop then skips those indices.
  def self.register_side(ai)
    return if !active?
    battle = ai.battle
    return if !battle || (!ENABLE_WILD && !battle.opponent)
    indices = pending_indices(battle)
    return if indices.empty?
    begin
      choose_all(ai, battle, indices)
    rescue Exception => error
      log_error(error)
      raise
    end
  end

  def self.pending_indices(battle)
    out = []
    [1, 3].each do |index|
      next if index == 3 && !battle.doublebattle
      battler = battle.battlers[index]
      next if !battler || battler.isFainted?
      next if !enabled_for?(battle, index)
      next if !battle.pbCanShowCommands?(index)
      next if battle.choices[index][0] != 0
      # Nothing to decide (no choosable move, no legal switch): leave the battler to
      # the host loop's pbAutoChooseMove path — that is engine mechanics (Struggle,
      # locked moves), not an AI decision.
      next if !any_choosable_move?(battle, index) && !has_legal_switch?(battle, index)
      out << index
    end
    out
  end

  def self.choose_all(ai, battle, indices)
    snapshot, skill = build_snapshot(ai, battle, indices)
    config = config_for(skill)
    plan = PortableAI.plan(snapshot, config, BattleRNG.new(battle))
    battle.instance_variable_set(:@portable_ai_last_plan, plan)
    observing = shadow?

    indices.each do |index|
      action = nil
      (plan["actions"] || []).each do |candidate|
        if candidate["actor_index"] == index
          action = candidate
          break
        end
      end
      raise "portable plan has no action for battler #{index}" if !action
      if !observing
        if !apply_action(battle, index, action)
          raise "portable action failed to register for battler #{index}: " +
                "#{action['type']} slot=#{action['slot']} target=#{action['target'].inspect}"
        end
        apply_memory(battle, index, action) if config["memory"]
      end
      trace = battle.instance_variable_get(
        observing ? :@portable_ai_shadow_trace : :@portable_ai_decision_trace)
      if trace
        entry = {
          "turn" => battle.turncount,
          "actor" => index,
          "type" => action["type"],
          "slot" => action["slot"],
          "move_id" => action["move_id"],
          "target" => action["target"],
          "score" => action["score"]
        }
        # Under trace, keep why as well as what. Storing only the chosen action means a
        # later diagnosis has to infer the gate reason from board state, which is what
        # produced the Chansey/Gengar misread; the planner already computed the reasons,
        # so this costs a copy. Top candidates only, to bound the file size.
        entry["candidates"] = candidate_trace(plan, index) if $AI_GAUNTLET_TRACE
        entry["view"] = view_trace(snapshot, index) if $AI_GAUNTLET_TRACE
        trace << entry
      end
    end
  end

  TRACE_CANDIDATE_LIMIT = 5
  # view_trace reports the race as computed, independently of whether the run
  # has the rules that consume it switched on.
  DEFAULT_RACE_CONFIG = { "damage_race" => true }

  # What the actor believed about the board when it chose: its own HP and speed order,
  # the incoming-damage estimate the heal and priority gates read, and each target's
  # HP. Joined with debuglog.txt this shows where the estimate and the foe's actual
  # choice part ways.
  def self.view_trace(snapshot, index)
    actor = (snapshot["actors"] || []).find { |a| a["index"] == index }
    return {} if !actor
    out = {
      "hp_pct" => actor["hp_pct"],
      "speed" => actor["speed"],
      "faster" => actor["faster"],
      "incoming_damage_pct" => actor["incoming_damage_pct"],
      "certain_incoming_damage_pct" => actor["certain_incoming_damage_pct"],
      "incoming_by_move" => actor["incoming_by_move"],
      "threatened_lethal" => actor["threatened_lethal"],
      "targets" => (snapshot["targets"] || []).map do |t|
        { "index" => t["index"], "hp_pct" => t["hp_pct"], "speed" => t["speed"] }
      end
    }
    # 0.6.0: the hits-to-KO both ways, per target. The helper is pure and reads only
    # the snapshot, so the adapter can call it on the snapshot it just built. The
    # counts live HERE and not in a reason pair -- reasons stay [name, number].
    race = {}
    (snapshot["targets"] || []).each do |t|
      race[t["index"].to_s] =
        PortableAI.damage_race(snapshot, actor, t, DEFAULT_RACE_CONFIG)
    end
    out["race"] = race
    out
  rescue
    {}
  end

  # The top scored candidates for one battler, each with the reason list that built its
  # score, from plan["diagnostics"]["rankings"] (already sorted best-first).
  def self.candidate_trace(plan, index)
    diagnostics = plan["diagnostics"] || {}
    rankings = diagnostics["rankings"] || []
    actors = (plan["actions"] || []).map { |a| a["actor_index"] }
    slot = actors.index(index)
    return [] if slot.nil?
    ranked = rankings[slot] || []
    out = []
    ranked.each do |candidate|
      break if out.length >= TRACE_CANDIDATE_LIMIT
      out << {
        "type" => candidate["type"],
        "slot" => candidate["slot"],
        "move_id" => candidate["move_id"],
        "target" => candidate["target"],
        "score" => candidate["score"],
        "reasons" => candidate["reasons"]
      }
    end
    out
  rescue
    []
  end

  def self.build_snapshot(ai, battle, indices)
    foe_indices = [0]
    foe_indices << 2 if battle.doublebattle
    foe_indices = foe_indices.select do |i|
      battler = battle.battlers[i]
      battler && !battler.isFainted?
    end

    skills = indices.map { |i| skill_for(ai, i) }
    skill = skills.min || PokeBattle_AI::BESTSKILL

    snapshot = nil
    with_neutral_estimation(ai, indices[0]) do
      targets = foe_indices.map { |i| battler_view(ai, battle.battlers[i]) }
      actors = indices.map { |i| build_actor(ai, battle, i, foe_indices, skill) }
      memory = battle.instance_variable_get(:@portable_ai_memory) || {}
      snapshot = {
        "format" => battle.doublebattle ? "double" : "single",
        "turn" => battle.turncount,
        "weather" => weather_name(battle),
        # Only the four modern terrains are named; every other Reborn field is a
        # mechanic the portable core has no rule for and is better reported as absent
        # than as a word it will not match.
        "terrain" => TERRAIN_FIELDS[(battle.FE rescue nil)],
        "trick_room_active" => ((battle.trickroom.to_i != 0) rescue false),
        "tailwind_active" =>
          (safe_side_effect(battle.battlers[indices[0]].pbOwnSide, :Tailwind, 0).to_i > 0 rescue false),
        "actors" => actors,
        "targets" => targets,
        "memory" => memory
      }
    end
    [snapshot, skill]
  end

  # pbRoughDamage reads @mondata.skill and @swappredicted, and both it and Reborn's
  # scoring branch on $game_switches[3000] (Intense player-choice reads, 100% Sucker
  # Punch prediction, mega reads). Stage a clean context for the duration of snapshot
  # building so the portable side estimates with fair information only.
  def self.with_neutral_estimation(ai, actor_index)
    old_mondata = ai.mondata
    old_swap    = ai.swappredicted
    old_intense = ($game_switches ? $game_switches[3000] : nil)
    ai.mondata = ai.aimondata[actor_index] || old_mondata
    raise "no aimondata for battler #{actor_index}" if !ai.mondata
    ai.swappredicted = [-1, -1]
    $game_switches[3000] = false if $game_switches
    yield
  ensure
    ai.mondata = old_mondata
    ai.swappredicted = old_swap
    $game_switches[3000] = old_intense if $game_switches && !old_intense.nil?
  end

  def self.battler_view(ai, battler)
    physical, special = attack_bias(ai, battler)
    partner = (battler.pbPartner rescue nil)
    {
      "index" => battler.index,
      "species" => battler.species,
      "hp_pct" => percent(battler.hp, battler.totalhp),
      "status" => battler.status,
      "types" => [battler.type1, battler.type2],
      "speed" => (battler.pbSpeed rescue battler.speed),
      # Switch scoring needs the foe's boost level and, unlike a move action, has no
      # scoring target to read it from.
      "positive_stages" => positive_stages(battler),
      # 0.5.0 facts. Plain uppercase names and booleans only: the core matches them
      # against its own tables and never sees a PBAbilities/PBItems constant.
      "ability" => ability_key(battler),
      "item" => item_key(battler),
      "full_hp" => (battler.hp >= battler.totalhp),
      "physical_attacker" => physical,
      "special_attacker" => special,
      "substitute" => (safe_effect(battler, :Substitute, 0).to_i > 0),
      "partner_ability" => (partner && !partner.isFainted? ? ability_key(partner) : nil),
      "choice_locked_move" => choice_locked_move(battler)
    }
  end

  # The move a Choice item has locked this battler into, once it has actually moved.
  # PBEffects::ChoiceBand holds the move id and is -1 when free (:6207).
  def self.choice_locked_move(battler)
    id = safe_effect(battler, :ChoiceBand, -1).to_i
    return nil if id < 0
    move_key(id)
  rescue
    nil
  end

  def self.build_actor(ai, battle, index, foe_indices, skill)
    battler = battle.battlers[index]
    actions = []
    battler.moves.each_with_index do |move, slot|
      next if !move || move.id == 0
      next if !battle.pbCanChooseMove?(index, slot, false)
      move_actions(ai, battle, battler, move, slot, foe_indices, skill).each do |action|
        actions << action
      end
    end
    switch_actions(ai, battle, battler, foe_indices).each { |action| actions << action }

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

    incoming_map = incoming_damage_by_move(ai, battle, battler, foe_indices)
    incoming = incoming_map.values.max || 0.0
    certain = certain_incoming_damage(ai, battle, battler, foe_indices, incoming_map)
    toxic_stage = safe_effect(battler, :Toxic, 0).to_i
    residual = 0.0
    residual += (toxic_stage + 1) * 100.0 / 16.0 if toxic_stage > 0
    residual += 100.0 / 8.0 if safe_effect(battler, :LeechSeed, -1).to_i >= 0
    speed = battler_speed(battler)
    partner = (battler.pbPartner rescue nil)
    partner_alive = partner && !partner.isFainted? ? true : false
    {
      "index" => index,
      "species" => battler.species,
      "hp_pct" => percent(battler.hp, battler.totalhp),
      "status" => battler.status,
      "speed" => speed,
      "faster" => faster_than_foes?(battle, speed, foe_indices),
      "stages" => battler.stages.clone,
      "negative_stage_total" => negative_stages,
      "incoming_damage_pct" => incoming,
      "certain_incoming_damage_pct" => certain,
      "incoming_by_move" => incoming_map,
      # 0.6.0: the per-foe view of the same threat, which is what a hits-to-KO
      # question has to read. Absent on any adapter that does not build it, and the
      # core's damage_race then returns nil and every consumer goes inert.
      "threats_by_foe" => threats_by_foe(ai, battle, battler, foe_indices, incoming_map),
      "threatened_lethal" => incoming >= percent(battler.hp, battler.totalhp),
      "no_effective_move" => no_effective,
      "best_damage_pct" => best_damage,
      "yawned" => safe_effect(battler, :Yawn, 0).to_i > 0,
      "residual_damage_pct" => residual,
      "trapped" => !has_legal_switch?(battle, index),
      # 0.5.0 facts about the actor itself.
      "ability" => ability_key(battler),
      "item" => item_key(battler),
      # Mold Breaker turns the target's Sturdy off, so the kill call stands.
      "mold_breaker" => mold_breaker?(battler),
      # Fake Out and First Impression are worth +115 on turn 0 and nothing after.
      "turncount" => (battler.turncount.to_i rescue 0),
      "slower_bench_count" => slower_bench_count(battle, battler, foe_indices),
      "partner_alive" => partner_alive,
      "partner_index" => (partner_alive ? partner.index : nil),
      "partner_ability" => (partner_alive ? ability_key(partner) : nil),
      "partner_hp_pct" => (partner_alive ? percent(partner.hp, partner.totalhp) : nil),
      "partner_airborne" =>
        (partner_alive ? (battler_has_type?(partner, :FLYING) ||
                          (ability_key(partner) == "LEVITATE")) : false),
      "actions" => actions
    }
  end

  def self.mold_breaker?(battler)
    name = ability_key(battler)
    name == "MOLDBREAKER" || name == "TERAVOLT" || name == "TURBOBLAZE"
  end

  # How many benched Pokemon are slower than every current foe. Trick Room is a
  # whole-team investment, so it is only worth a turn when the team behind the actor
  # is slow too.
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
      next if pokemon.equal?(battler.pokemon)
      speed = (pokemon.speed rescue nil)
      count += 1 if speed && speed < fastest
    end
    count
  rescue
    0
  end

  def self.move_actions(ai, battle, battler, move, slot, foe_indices, skill)
    target_const = (battler.pbTarget(move) rescue move.target)
    spread = (target_const == PBTargets::AllOpposing ||
              target_const == PBTargets::AllNonUsers)
    move_id = move_key(move.id)

    if spread
      scored = foe_indices.map do |target_index|
        target = battle.battlers[target_index]
        action_for_target(ai, battle, battler, move, slot, move_id, target, nil, skill)
      end
      return [] if scored.empty?
      action = scored[0]
      action["base_score"] = average(scored.map { |item| item["base_score"] })
      action["expected_damage_pct"] = scored.inject(0) do |sum, item|
        sum + PortableAI::Model.number(item["expected_damage_pct"], 0)
      end
      action["target"] = nil
      action["spread"] = true
      # Engine truth for partner exposure: AllNonUsers hits the partner, AllOpposing
      # does not. (The Realidea adapter used the effects-table tag; the dynamic
      # pbTarget answer is strictly better and free here.)
      if target_const == PBTargets::AllNonUsers
        partner = battler.pbPartner
        if partner && !partner.isFainted?
          action["friendly_fire_pct"] = rough_damage_pct(ai, move, battler, partner)
          action["partner_hp_pct"] = percent(partner.hp, partner.totalhp)
        end
      end
      return [action]
    end

    targets = legal_targets(battle, battler, target_const, foe_indices)
    if targets.empty?
      opponent = foe_indices.empty? ? nil : battle.battlers[foe_indices[0]]
      return [action_for_target(ai, battle, battler, move, slot, move_id, opponent, nil, skill)]
    end

    targets.map do |target_index|
      target = battle.battlers[target_index]
      registration_target = explicit_target?(target_const) ? target_index : nil
      action = action_for_target(
        ai, battle, battler, move, slot, move_id, target, registration_target, skill
      )
      partner = battler.pbPartner
      if partner && target_index == partner.index
        action["friendly_target"] = true
        if move.basedamage > 0
          action["friendly_fire_pct"] = action["expected_damage_pct"]
          action["partner_hp_pct"] = percent(partner.hp, partner.totalhp)
        end
      end
      action
    end
  end

  def self.action_for_target(ai, battle, battler, move, slot, move_id, target, register_target, skill)
    scoring_target = target
    if !scoring_target || scoring_target.index == battler.index
      scoring_target = battler.pbOppositeOpposing
    end
    effectiveness = type_effectiveness(ai, move, battler, scoring_target)
    damaging = move.basedamage > 0
    tags = PortableAI::Effects.describe(move_id, [])
    blocked = !damaging && status_blocked?(ai, move, tags, battler, scoring_target)
    kind, stat, chance = move_effect(ai, move, battler, scoring_target)
    physical, special = scoring_target ? attack_bias(ai, scoring_target) : [false, false]
    code = (move.function rescue nil)
    {
      "type" => "move",
      "actor_index" => battler.index,
      "slot" => slot,
      "move_id" => move_id,
      "numeric_move_id" => move.id,
      "target" => register_target,
      "base_score" => NEUTRAL_BASE_SCORE,
      "damaging" => damaging,
      "power" => move.basedamage,
      "priority" => effective_priority(battle, move, battler, scoring_target),
      # 0.5.0 move facts, all from the engine.
      "move_type" => type_key((move.pbType(battler) rescue move.type)),
      "category" => (damaging ? ((move.pbIsPhysical?(move.pbType(battler)) rescue false) ?
                                 "physical" : "special") : "status"),
      "contact" => ((move.isContactMove? rescue false) ? true : false),
      "effect_kind" => kind,
      "effect_stat" => stat,
      "effect_chance" => chance,
      "multi_hit" => multi_hit?(move),
      "recoil_fraction" => MOVE_RECOIL_CODES[code],
      "drain_fraction" => MOVE_DRAIN_CODES[code],
      "mold_breaker" => mold_breaker?(battler),
      # Mirrors of the target view, so a spread action (which has no single target)
      # and a unit test both reach the same facts.
      "target_ability" => (scoring_target ? ability_key(scoring_target) : nil),
      "target_item" => (scoring_target ? item_key(scoring_target) : nil),
      "target_full_hp" => (scoring_target ? (scoring_target.hp >= scoring_target.totalhp) : false),
      "target_speed" => (scoring_target ? battler_speed(scoring_target) : nil),
      "target_physical_attacker" => physical,
      "target_special_attacker" => special,
      "target_substitute" =>
        (scoring_target ? (safe_effect(scoring_target, :Substitute, 0).to_i > 0) : false),
      "effectiveness" => effectiveness,
      "immune" => (damaging && effectiveness <= 0) || blocked,
      "expected_damage_pct" => rough_damage_pct(ai, move, battler, scoring_target),
      "accuracy" => rough_accuracy(ai, move, battler, scoring_target),
      "target_hp_pct" => (scoring_target ? percent(scoring_target.hp, scoring_target.totalhp) : nil),
      "tags" => tags,
      "spread" => false,
      "existing_layers" => existing_layers(battler, move_id),
      "max_layers" => max_layers(move_id),
      "own_hazard_layers" => own_hazard_layers(battler),
      "foe_hazard_layers" => opposing_hazard_layers(battler),
      "target_positive_stages" => positive_stages(scoring_target),
      "effect_active" => effect_active?(battler, move_id),
      "foe_reserves" => reserve_count(battle, scoring_target ? scoring_target.index : battler.index ^ 1),
      "hazard_targets" => hazard_target_count(battle, move_id, battler.index),
      "own_reserves" => reserve_count(battle, battler.index)
    }
  end

  # Priority as the engine's own AI helper reads it: Prankster, Gale Wings and Triage
  # raise it, and Fake Out/First Impression lose it after turn 0 (PokeBattle_Move.rb
  # :2586). Psychic Terrain stops a priority move reaching a grounded target
  # altogether, which the probe confirmed stock Reborn already knows (Aqua Jet scored
  # 0 on field 37 against 242 on an open field), so a priority move that cannot land
  # is reported as having no priority rather than as having some.
  def self.effective_priority(battle, move, battler, target)
    base = move.priority
    if base > 0 && TERRAIN_FIELDS[(battle.FE rescue nil)] == "psychic" && target
      grounded = !(battler_has_type?(target, :FLYING) || ability_key(target) == "LEVITATE")
      return 0 if grounded
    end
    positive = (move.pbIsPriorityMoveAI(battler) rescue nil)
    return 0 if positive == false && base > 0
    return 1 if positive == true && base <= 0
    base
  rescue
    move.priority
  end

  def self.legal_targets(battle, battler, target_const, foe_indices)
    case target_const
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

  def self.explicit_target?(target_const)
    target_const == PBTargets::SingleNonUser ||
      target_const == PBTargets::SingleOpposing ||
      target_const == PBTargets::UserOrPartner ||
      target_const == PBTargets::Partner
  end

  def self.switch_actions(ai, battle, battler, foe_indices)
    party = battle.pbParty(battler.index)
    forced = safe_effect(battler, :PerishSong, 0) == 1
    actions = []
    party.each_with_index do |pokemon, slot|
      next if !pokemon || !battle.pbCanSwitch?(battler.index, slot, false)
      hp_pct = percent(pokemon.hp, pokemon.totalhp)
      matchup = switch_matchup(pokemon, battle, foe_indices)
      hazard = entry_hazard_pct(pokemon, battler)
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
        # 0.5.0 entry facts. candidate_hp_pct and entry_damage_pct restate what is
        # already folded into base_score so the core can ask "is this Pokemon alive at
        # the end of the turn it comes in on" rather than "did it clear the hazards".
        "candidate_hp_pct" => hp_pct,
        "entry_damage_pct" => hazard,
        "ability" => ability_key(pokemon),
        "item" => item_key(pokemon)
      }
      real = switch_incoming_damage(ai, battle, pokemon, foe_indices)
      action["incoming_damage_pct"] = real if !real.nil?
      # 0.6.0: the offensive half of the same estimate, so the core can run the race
      # for a candidate that has not come in yet. Same fake battler, same rescue-to-nil
      # contract as incoming_damage_pct.
      out = switch_outgoing_damage(ai, battle, pokemon, foe_indices)
      action["outgoing_damage_pct"] = out if !out.nil?
      fast = switch_candidate_faster(battle, pokemon, foe_indices)
      action["faster"] = fast if !fast.nil?
      actions << action
    end
    actions
  end

  # What the candidate actually eats on the turn it comes in, as a real damage estimate
  # against a fake battler rather than a type-chart proxy -- and with the candidate's
  # own Intimidate applied to the foes first, which is the only way an entry ability
  # can show up in the number at all. Reborn does exactly this, including the temporary
  # stage mutation and its restore (:11584-11617); pbCanReduceStatStage? is what makes
  # Clear Body, White Smoke, Full Metal Body, Hyper Cutter and Clear Amulet exempt, and
  # the probe confirmed the exemption is complete.
  #
  # nil when the engine cannot build a fake battler, which leaves the core on the type
  # proxy it used through 0.4.1.
  def self.switch_incoming_damage(ai, battle, pokemon, foe_indices)
    fake = (ai.pbMakeFakeBattler(pokemon) rescue nil)
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
          next if ability == "CONTRARY" || ability == "MIRRORARMOR" || ability == "DEFIANT"
          saved[foe_index] = foe.stages[PBStats::ATTACK]
          foe.stages[PBStats::ATTACK] -= 1
        end
      end
      foe_indices.each do |foe_index|
        foe = battle.battlers[foe_index]
        next if !foe || foe.isFainted?
        foe.moves.each do |known|
          next if !known || known.id == 0
          damage = rough_damage_pct(ai, known, foe, fake)
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

  # The mirror of switch_incoming_damage: the best real hit this candidate has into
  # any current foe, so the core can ask how many turns it needs rather than only how
  # many it survives. Same fake battler and the same nil-on-failure contract, which
  # leaves the core on switch_matchup's type proxy exactly as before.
  def self.switch_outgoing_damage(ai, battle, pokemon, foe_indices)
    fake = (ai.pbMakeFakeBattler(pokemon) rescue nil)
    return nil if !fake
    best = 0.0
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      next if !foe || foe.isFainted?
      (pokemon.moves || []).each do |own|
        next if !own || own.id == 0
        move = (PokeBattle_Move.pbFromPBMove(battle, own, fake) rescue nil)
        next if !move
        damage = rough_damage_pct(ai, move, fake, foe)
        best = damage if damage > best
      end
    end
    best
  rescue
    nil
  end

  # Whether the candidate would outrun every current foe once it is in. A benched
  # Pokemon has no battler and therefore no pbSpeed, so this reads the party entry's
  # own Speed stat -- no stages, which is right: a switch-in enters at stage 0.
  def self.switch_candidate_faster(battle, pokemon, foe_indices)
    speed = (pokemon.speed rescue nil)
    return nil if speed.nil?
    faster_than_foes?(battle, speed, foe_indices)
  rescue
    nil
  end

  # Best offensive type matchup of a benched Pokemon into the current foes.
  # Reborn's static chart is per-type neutral 2, combined neutral 4 (two type slots);
  # Realidea's combined neutral is 8 (three slots) with a x4 weight, so weight x8 here
  # to hand the core the same magnitudes (neutral 32, super-effective 64, double 128).
  def self.switch_matchup(pokemon, battle, foe_indices)
    best = 0
    (pokemon.moves || []).each do |pokemon_move|
      next if !pokemon_move || pokemon_move.id == 0
      data = PBMoveData.new(pokemon_move.id) rescue nil
      next if !data || data.basedamage <= 0
      total = 0
      foe_indices.each do |foe_index|
        foe = battle.battlers[foe_index]
        total += PBTypes.getCombinedEffectiveness(data.type, foe.type1, foe.type2)
      end
      best = total if total > best
    end
    best * 8
  rescue
    0
  end

  # The mirror of switch_matchup: how hard the foe hits the candidate coming in.
  # switch_matchup asks only what the incoming Pokemon can dish out, which is why
  # Portable's switch-ins took 33.5% of their HP on the entry turn against
  # Reborn-Normal's 26.5% over ~406 measured switches — it picks a good attacker and
  # never asks what that attacker will eat.
  #
  # Scored off the foe's own types rather than its moveset, so this stays inside the
  # fair-information contract: a player can see the opposing species and infer its STAB
  # without having been shown its moves. Same units as switch_matchup (x8, so neutral is
  # 32), and the worst foe is taken rather than the sum — in a double the incoming
  # Pokemon eats both, but the one that hits hardest is what decides whether it lives.
  def self.switch_incoming_risk(pokemon, battle, foe_indices)
    worst = 0
    types = [pokemon.type1, pokemon.type2].compact.uniq
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      next if !foe
      [foe.type1, foe.type2].compact.uniq.each do |attacking|
        value = PBTypes.getCombinedEffectiveness(attacking, types[0], types[-1])
        worst = value if value > worst
      end
    end
    worst * 8
  rescue
    0
  end

  # Reborn's own type verdict, ability- and field-aware. Neutral is 4; 0 is immune and
  # -1 is an absorb ability (heals/boosts the target) — both are "do not click" for a
  # damaging move, so both map to 0.0.
  def self.type_effectiveness(ai, move, attacker, target)
    return 1.0 if !target || move.basedamage <= 0
    raw = ai.pbTypeModNoMessages(
      (move.pbType(attacker) rescue move.type), attacker, target, move,
      PokeBattle_AI::BESTSKILL
    )
    return 0.0 if raw.nil? || raw <= 0
    raw.to_f / TYPEMOD_NEUTRAL
  rescue
    1.0
  end

  def self.rough_damage_pct(ai, move, attacker, target)
    return 0.0 if !target || move.basedamage <= 0
    damage = ai.pbRoughDamage(move, attacker, target, false, false)
    return 0.0 if !damage || damage <= 0
    percent(damage, target.totalhp)
  rescue
    0.0
  end

  # Hit chance 0-100 as the engine itself computes it, including ability, weather and
  # accuracy/evasion stages (PokeBattle_AI_2.rb:9965). It reads @mondata.skill, which
  # with_neutral_estimation has already staged, and returns 100 for never-miss moves.
  # nil when the primitive is unavailable, which the core reads as "do not discount".
  def self.rough_accuracy(ai, move, attacker, target)
    return nil if !target
    value = ai.pbRoughAccuracy(move, attacker, target)
    return nil if value.nil?
    value.to_f
  rescue
    nil
  end

  def self.battler_speed(battler)
    return nil if !battler
    (battler.pbSpeed rescue battler.speed)
  rescue
    nil
  end

  # Reborn's own convention (pbAIfaster?, :10055): strictly greater is faster, a tie is
  # not, and Trick Room inverts the comparison. nil when either speed is unavailable,
  # which every rule reading it treats as "unknown, do not penalise".
  def self.faster_than_foes?(battle, speed, foe_indices)
    return nil if speed.nil?
    fastest = nil
    foe_indices.each do |foe_index|
      foe_speed = battler_speed(battle.battlers[foe_index])
      next if foe_speed.nil?
      fastest = foe_speed if fastest.nil? || foe_speed > fastest
    end
    return nil if fastest.nil?
    trick_room = (battle.trickroom.to_i != 0 rescue false)
    trick_room ? speed < fastest : speed > fastest
  end

  # Fair-information caveat carried over from the Realidea adapter: this inspects the
  # foe's actual move objects rather than a revealed-move memory model.
  def self.estimated_incoming_damage(ai, battle, battler, foe_indices)
    maximum = 0.0
    incoming_damage_by_move(ai, battle, battler, foe_indices).each_value do |damage|
      maximum = damage if damage > maximum
    end
    maximum
  end

  # Every foe move's estimated hit on this battler, keyed "<foe index>:<move id>".
  # The maximum is what the threat rules read; the whole map goes into the trace view
  # so a later diagnosis can compare the estimate for the move the foe actually used
  # against the damage it actually did.
  def self.incoming_damage_by_move(ai, battle, battler, foe_indices)
    out = {}
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      # A Choice item that has already locked in is a CERTAINTY about what is coming,
      # and the strongest one available: the foe cannot use anything else until it
      # switches. Reborn reads the same effect when it scores switch-ins (:11377) but
      # NOT when it scores moves, which the probe caught -- Skarmory scored Roost at 0
      # behind a Heatran locked into a move it is immune to, because the threat model
      # still contained the Flamethrower it could not use. This is a deliberate
      # departure from the reference, on the strict_threat side of the ledger.
      locked = safe_effect(foe, :ChoiceBand, -1).to_i
      foe.moves.each do |known|
        next if !known || known.id == 0
        next if locked >= 0 && known.id != locked
        out["#{foe_index}:#{known.id}"] = rough_damage_pct(ai, known, foe, battler)
      end
    end
    out
  end

  # The same incoming_map, resolved PER FOE and with the two extra facts a hits-to-KO
  # question needs: the best hit that foe has, the best one it has that moves first,
  # and whether it outruns this battler. incoming_by_move is keyed "foe:moveid" with no
  # priority, and actor["faster"] is against the FASTEST foe only -- in doubles that is
  # the wrong flag for the slower target, and a race computed off it is wrong.
  #
  # Keyed by foe index as a STRING, because the core reads it out of a plain Hash that
  # has been through JSON in the Realidea build.
  def self.threats_by_foe(ai, battle, battler, foe_indices, incoming_map)
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
        damage = rough_damage_pct(ai, known, foe, battler) if damage.nil?
        damage = PortableAI::Model.number(damage, 0.0)
        best = damage if damage > best
        next if effective_priority(battle, known, foe, battler) <= 0
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

  # The largest incoming hit that cannot fail to happen: the foe is not asleep (with
  # sleep still to serve) or frozen, and the move never misses as the engine computes
  # its hit chance. The core's "you die whatever you click" rules read this under
  # strict_threat; the loose maximum stays for the soft rules. Set_c showed the loose
  # figure was wrong 72% of the time exactly when one of these two conditions held.
  def self.certain_incoming_damage(ai, battle, battler, foe_indices, incoming_map)
    maximum = 0.0
    foe_indices.each do |foe_index|
      foe = battle.battlers[foe_index]
      next if !foe || !foe_can_act?(foe)
      foe.moves.each do |known|
        next if !known || known.id == 0
        damage = incoming_map["#{foe_index}:#{known.id}"]
        next if !damage || damage <= 0
        accuracy = rough_accuracy(ai, known, foe, battler)
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
      count = (foe.statusCount rescue 0).to_i
      # One turn left means it wakes and acts this turn.
      return false if count > 1
    end
    true
  rescue
    true
  end

  def self.any_choosable_move?(battle, index)
    battler = battle.battlers[index]
    return false if !battler
    battler.moves.each_with_index do |move, slot|
      next if !move || move.id == 0
      return true if battle.pbCanChooseMove?(index, slot, false)
    end
    false
  rescue
    false
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
    party = battle.pbParty(actor_index ^ 1)
    count = 0
    party.each do |pokemon|
      next if !pokemon || pokemon.hp <= 0 || pokemon.isEgg?
      # Heavy-Duty Boots and Magic Guard walk over every hazard, so a party wearing
      # them is a party the move cannot touch. Reborn's Spikes and Toxic Spikes
      # branches skip Boots holders (:4603, :4633) and its Stealth Rock branch does
      # not look at the party at all -- measured, Spikes collapse to 0 against an
      # all-Boots party while Stealth Rock stays at 45. Applied to every hazard here,
      # because the asymmetry is a gap in the reference and not a rule.
      next if item_key(pokemon) == "HEAVYDUTYBOOTS"
      next if pokemon_ability?(pokemon, :MAGICGUARD)
      airborne = pokemon_has_type?(pokemon, :FLYING) || pokemon_ability?(pokemon, :LEVITATE)
      if move_id == "SPIKES" || move_id == "STICKYWEB"
        count += 1 if !airborne
      elsif move_id == "TOXICSPIKES"
        immune_type = pokemon_has_type?(pokemon, :POISON) || pokemon_has_type?(pokemon, :STEEL)
        count += 1 if !airborne && !immune_type
      else
        count += 1
      end
    end
    count
  rescue
    1
  end

  # Hazards this battler would lay land on the opposing half of the field.
  def self.existing_layers(battler, move_id)
    side = battler.pbOpposingSide
    case move_id
    when "SPIKES"       then safe_side_effect(side, :Spikes, 0)
    when "TOXICSPIKES"  then safe_side_effect(side, :ToxicSpikes, 0)
    when "STEALTHROCK"  then safe_side_effect(side, :StealthRock, false) ? 1 : 0
    when "STICKYWEB"    then safe_side_effect(side, :StickyWeb, false) ? 1 : 0
    else 0
    end
  end

  def self.max_layers(move_id)
    return 3 if move_id == "SPIKES"
    return 2 if move_id == "TOXICSPIKES"
    1
  end

  # Universal status-immunity facts, computed from engine type data. Kind tags come
  # from the canonical effects table; "typed_status" additionally consults the
  # engine's own type verdict (Thunder Wave vs Ground and ability absorbs).
  # Universal facts about a non-damaging move that make it unusable. Three sources,
  # in order of how much they know:
  #
  # 1. Magic Bounce on the target OR its partner reflects every status move
  #    (Reborn returns -1 for the whole move, :2828).
  # 2. Prankster gives status moves priority and a Dark type ignores them entirely
  #    (Reborn returns a flat 0, :3324).
  # 3. The status itself: ask the ENGINE's own can-status check rather than the type
  #    list this used to carry. pbCanBurn?/pbCanPoison?/pbCanParalyze?/pbCanSleep?/
  #    pbCanFreeze?/pbCanConfuse? already know about Misty and Electric Terrain,
  #    Safeguard, Leaf Guard, Comatose, Purifying Salt, Good as Gold, Overcoat and
  #    Sweet Veil against powder, Limber, Water Veil, Immunity, Insomnia and Vital
  #    Spirit -- none of which a type list can see. The list stays as the rescue path
  #    for an engine that does not expose them.
  def self.status_blocked?(ai, move, tags, battler, target)
    return false if !target
    return false if !tags.include?("status")
    return true if magic_bounced?(target)
    if ability_key(battler) == "PRANKSTER" && battler_has_type?(target, :DARK)
      return true
    end
    if tags.include?("typed_status")
      raw = ai.pbTypeModNoMessages(
        (move.pbType(battler) rescue move.type), battler, target, move,
        PokeBattle_AI::BESTSKILL
      ) rescue nil
      return true if raw && raw <= 0
    end
    verdict = engine_can_status?(tags, target)
    return !verdict if !verdict.nil?
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
  # be asked about (so the caller falls through to the type list).
  def self.engine_can_status?(tags, target)
    return target.pbCanBurn?(false)      if tags.include?("burn")
    return target.pbCanPoison?(false)    if tags.include?("poison")
    return target.pbCanParalyze?(false)  if tags.include?("paralyze")
    return target.pbCanSleep?(false)     if tags.include?("sleep")
    return target.pbCanFreeze?(false)    if tags.include?("freeze")
    return target.pbCanConfuse?(false)   if tags.include?("confuse")
    nil
  rescue
    nil
  end

  def self.magic_bounced?(target)
    return true if ability_key(target) == "MAGICBOUNCE"
    partner = (target.pbPartner rescue nil)
    return true if partner && !partner.isFainted? && ability_key(partner) == "MAGICBOUNCE"
    false
  rescue
    false
  end

  def self.battler_has_type?(battler, symbol)
    battler.pbHasType?(symbol)
  rescue
    type = (PBTypes.const_get(symbol) rescue nil)
    return false if type.nil?
    battler.type1 == type || battler.type2 == type
  end

  def self.positive_stages(target)
    return 0 if !target
    total = 0
    target.stages.each { |stage| total += stage if stage && stage > 0 }
    total
  rescue
    0
  end

  def self.opposing_hazard_layers(battler)
    side = battler.pbOpposingSide
    safe_side_effect(side, :Spikes, 0).to_i +
      safe_side_effect(side, :ToxicSpikes, 0).to_i +
      (safe_side_effect(side, :StealthRock, false) ? 1 : 0) +
      (safe_side_effect(side, :StickyWeb, false) ? 1 : 0)
  rescue
    0
  end

  def self.own_hazard_layers(battler)
    side = battler.pbOwnSide
    safe_side_effect(side, :Spikes, 0).to_i +
      safe_side_effect(side, :ToxicSpikes, 0).to_i +
      (safe_side_effect(side, :StealthRock, false) ? 1 : 0) +
      (safe_side_effect(side, :StickyWeb, false) ? 1 : 0)
  rescue
    0
  end

  def self.effect_active?(battler, move_id)
    side = battler.pbOwnSide
    case move_id
    when "REFLECT"     then safe_side_effect(side, :Reflect, 0).to_i > 0
    when "LIGHTSCREEN" then safe_side_effect(side, :LightScreen, 0).to_i > 0
    when "SAFEGUARD"   then safe_side_effect(side, :Safeguard, 0).to_i > 0
    when "SUBSTITUTE"  then safe_effect(battler, :Substitute, 0).to_i > 0
    else false
    end
  end

  # Rough entry cost on this battler's own side (what a switch-in would eat).
  # Reborn's combined-effectiveness neutral is 4, hence /4 where Realidea used /8.
  def self.entry_hazard_pct(pokemon, battler)
    side = battler.pbOwnSide
    # The other half of the Boots rule: a holder pays nothing to come in.
    return 0 if item_key(pokemon) == "HEAVYDUTYBOOTS"
    return 0 if pokemon_ability?(pokemon, :MAGICGUARD)
    spikes = safe_side_effect(side, :Spikes, 0).to_i
    damage = [0, 12.5, 16.7, 25.0][spikes] || 25.0
    if pokemon_has_type?(pokemon, :FLYING) || pokemon_ability?(pokemon, :LEVITATE)
      damage = 0
    end
    if safe_side_effect(side, :StealthRock, false)
      rock = (PBTypes.const_get(:ROCK) rescue nil)
      if rock
        effectiveness = PBTypes.getCombinedEffectiveness(
          rock, pokemon.type1, pokemon.type2
        )
        damage += 12.5 * effectiveness.to_f / TYPEMOD_NEUTRAL
      else
        damage += 12.5
      end
    end
    damage
  rescue
    0
  end

  def self.pokemon_has_type?(pokemon, symbol)
    pokemon.hasType?(symbol)
  rescue
    type = (PBTypes.const_get(symbol) rescue nil)
    return false if !type
    pokemon.type1 == type || pokemon.type2 == type
  end

  def self.pokemon_ability?(pokemon, symbol)
    value = (PBAbilities.const_get(symbol) rescue nil)
    return false if !value
    (pokemon.ability rescue nil) == value
  end

  def self.safe_effect(battler, name, fallback)
    return fallback if !PBEffects.const_defined?(name)
    battler.effects[PBEffects.const_get(name)]
  rescue
    fallback
  end

  def self.safe_side_effect(side, name, fallback)
    return fallback if !PBEffects.const_defined?(name)
    side.effects[PBEffects.const_get(name)]
  rescue
    fallback
  end

  # Uppercase type name ("FIRE"), the same shape the core's absorb and redirect tables
  # are keyed by. Built once from PBTypes, like move_key.
  def self.type_key(id)
    return nil if id.nil?
    if !defined?(@type_keys) || !@type_keys
      @type_keys = {}
      PBTypes.constants.each do |name|
        value = PBTypes.const_get(name) rescue nil
        @type_keys[value] = name.to_s.upcase if value.is_a?(Integer)
      end
    end
    @type_keys[id]
  end

  # Ability and item names as uppercase strings, resolved through the CONSTANT tables
  # rather than through PBAbilities.getName / PBItems.getName.
  #
  # getName goes to the compiled message file, and the test environment the probe and
  # the gauntlet both run in has no message data: it returns an empty string for every
  # id (the same reason debuglog.txt shows blank species names). The first 0.5.0 build
  # used getName, and the result was that ability_key returned "" for everything, so
  # every ability and item row in all four tables silently did nothing -- 22 corpus
  # cards failed under Portable while passing under stock Reborn. The constants are
  # compiled into the module itself and are always there.
  def self.ability_key(battler_or_pokemon)
    value = (battler_or_pokemon.ability rescue nil)
    return nil if value.nil? || value == 0
    constant_key(PBAbilities, :@ability_keys, value)
  rescue
    nil
  end

  def self.item_key(battler_or_pokemon)
    value = (battler_or_pokemon.item rescue nil)
    return nil if value.nil? || value == 0
    constant_key(PBItems, :@item_keys, value)
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

  # Which attacking stat this battler actually hits with. The burn, paralysis and
  # stat-drop rows all ask it, and Reborn asks the same question with pbRoughStat
  # (burncode:5662).
  def self.attack_bias(ai, battler)
    attack = (ai.pbRoughStat(battler, PBStats::ATTACK) rescue nil)
    special = (ai.pbRoughStat(battler, PBStats::SPATK) rescue nil)
    return [false, false] if attack.nil? || special.nil?
    [attack > special, special > attack]
  rescue
    [false, false]
  end

  # kind / stat / chance for one move against one target, all three from the engine.
  # The chance is the move's own addlEffect, doubled by Serene Grace and zeroed when
  # the engine says the secondary is negated (Sheer Force, Shield Dust, Covert Cloak) —
  # the same three checks Reborn makes in secondaryEffectNegated? (:17430).
  def self.move_effect(ai, move, battler, target)
    code = (move.function rescue nil)
    return [nil, nil, nil] if code.nil?
    entry = MOVE_EFFECT_CODES[code]
    return [nil, nil, nil] if !entry
    chance = (move.addlEffect rescue 0).to_i
    # A status MOVE (Will-O-Wisp, Toxic, Thunder Wave) carries addlEffect 0 because the
    # status is its whole point, not a secondary; those are certain.
    chance = 100 if move.basedamage <= 0 || chance <= 0
    if target && move.basedamage > 0
      negated = (ai.secondaryEffectNegated?(move, battler, target) rescue false)
      return [entry[0], entry[1], 0] if negated
      chance *= 2 if (battler.ability == PBAbilities::SERENEGRACE rescue false)
    end
    # A secondary that cannot land is worth nothing, and only the engine knows why not
    # -- a Fire type cannot burn, Misty Terrain blocks everything, Purifying Salt and
    # Good as Gold and Safeguard each block their own share. status_blocked? asks the
    # same question but only ever ran for NON-damaging moves, which left Scald scoring
    # its burn bonus into an Arcanine.
    if target
      verdict = engine_can_status?([entry[0]], target)
      return [entry[0], entry[1], 0] if verdict == false
    end
    chance = 100 if chance > 100
    [entry[0], entry[1], chance]
  rescue
    [nil, nil, nil]
  end

  def self.multi_hit?(move)
    return true if (move.pbIsMultiHit rescue false)
    MULTI_HIT_CODES.include?((move.function rescue nil))
  rescue
    false
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

  def self.log_error(error)
    signature = "#{error.class}: #{error.message}"
    return if defined?(@last_error) && @last_error == signature
    @last_error = signature
    File.open(ERROR_FILE, "ab") do |file|
      file.write("#{signature}\n")
      file.write(error.backtrace[0, 8].join("\n") + "\n") if error.backtrace
    end
  rescue
  end
end

class PokeBattle_Battle
  def portable_ai_last_plan
    @portable_ai_last_plan
  end
end

class PokeBattle_AI
  if !method_defined?(:portable_ai_orig_chooseAction)
    alias_method :portable_ai_orig_chooseAction, :chooseAction
  end

  def chooseAction
    PortableAIReborn.register_side(self)
    portable_ai_orig_chooseAction
  end
end
