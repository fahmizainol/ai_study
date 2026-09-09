# Portable AI adapter for Realidea (Pokemon Essentials v16).
#
# This file is concatenated after portable_ai/model.rb, effects.rb, matrix.rb, core.rb
# and search.rb, then
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

  # Abilities that make a move of the given type do nothing at all, read off this
  # engine's own pbTypeImmunityByAbility (082:318-402). The engine's copy CANNOT be
  # called from the AI: it raises the target's stats, heals it, sets Flash Fire and
  # prints -- it is the live effect, not a query. pbTypeModifier (:405) is ability-blind,
  # so without this table a Thunderbolt into Lightning Rod came back neutral and the
  # core scored it as a kill. (Reborn gets this free: pbTypeModNoMessages returns -1.)
  #
  # Bulletproof and Telepathy are in the engine's list too but key off the move's bomb
  # flag and ally targeting rather than its type, so they are handled at the call site.
  ABSORB_ABILITIES = {
    "SAPSIPPER" => :GRASS,
    "STORMDRAIN" => :WATER, "DRYSKIN" => :WATER, "WATERABSORB" => :WATER,
    "LIGHTNINGROD" => :ELECTRIC, "MOTORDRIVE" => :ELECTRIC, "VOLTABSORB" => :ELECTRIC,
    "FLASHFIRE" => :FIRE
  }

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

  # Where an observing shadow's rolls are sent instead of the battle's RNG.
  #
  # An observation must take nothing from the stream the host is playing on, and the
  # planner's own difficulty noise is only half of that. Building a snapshot calls the
  # ENGINE's scoring helpers -- pbGetMoveScore above all -- and those roll: PokeBattle_AI
  # makes 21 pbAIRandom calls and no bare rand, several inside the stat-boost handlers
  # pbGetMoveScore runs for every candidate move. A first shadow run over 60 battles
  # proved the point rather than arguing it: 14 diverged from their unobserved twins,
  # and all 14 were the matchups whose observed team carried setup moves.
  #
  # So the diversion happens at pbAIRandom, the one choke point both the planner (via
  # BattleRNG) and the engine's helpers pass through, rather than at the planner alone.
  # An LCG rather than Kernel#rand because Kernel#rand IS the battle stream: srand(seed)
  # in the gauntlet seeds it, so drawing from it is the very leak being closed.
  class NeutralRNG
    attr_reader :draws

    def initialize(seed)
      @draws = 0
      @state = (seed.to_i & 0x3FFFFFFF)
    end

    def rand(limit)
      @draws += 1
      @state = ((@state * 1103515245) + 12345) & 0x3FFFFFFF
      bound = limit.to_i
      bound <= 0 ? 0 : @state % bound
    end
  end

  def self.requested?
    return true if defined?($PORTABLE_AI_ENABLED) && $PORTABLE_AI_ENABLED
    File.exist?(ENABLE_FILE)
  rescue
    false
  end

  # Shadow mode: build the snapshot and run the planner for the observed side, record
  # what it would have done, and register nothing -- the host AI still chooses. Both AIs
  # therefore answer from the identical position on every turn, which is the only way to
  # compare the two policies at scale; two live arms diverge after about a turn and
  # everything after that is a different battle, so a live stock/portable pair can be
  # compared on outcomes but never turn by turn.
  #
  # Sound because the planner registers nothing, draws from NeutralRNG instead of the
  # battle, and restores the two host fields build_snapshot stages (fake_battler's
  # effects and switch_incoming_damage's attack stages, both under `ensure`). What it
  # deliberately does NOT do is apply_memory: portable memory would otherwise record
  # moves the portable AI never made, so a shadow decision does not carry the
  # repeated-setup penalty the same position would attract in a live portable run.
  #
  # The claim is checked, not asserted -- run the shadow and stock arms over the same
  # seeds and every battle must agree on decision and turns. See PORTABLE-AI-REALIDEA.md.
  def self.shadow?
    defined?($PORTABLE_AI_SHADOW) && $PORTABLE_AI_SHADOW ? true : false
  end

  def self.active?
    requested? || shadow?
  end

  def self.enabled_for?(battle, index)
    return false if !active?
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
  # A played battle has no run around it: nothing calls Harness.with_config, so through
  # 0.8.0 the enemy in a normal battle always ran on the bare defaults and `foul_play`
  # could not be switched on outside the gauntlet and the probe. Harness.live_overrides
  # closes that, and only for live play -- see the comment there.
  def self.config_overrides
    return $PORTABLE_AI_CONFIG if defined?($PORTABLE_AI_CONFIG) && $PORTABLE_AI_CONFIG.is_a?(Hash)
    Harness.live_overrides
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
        entry = {
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
        if trace_candidates?
          entry["candidates"] =
            candidate_trace(battle.instance_variable_get(:@portable_ai_plan) || {}, index,
                            battle.instance_variable_get(:@portable_ai_last_snapshot))
        end
        foes = foe_choices(battle)
        entry["foe"] = foes if foes
        search = search_trace(battle.instance_variable_get(:@portable_ai_plan) || {})
        entry["search"] = search if search
        trace << entry
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

  # One paired observation: what the portable planner would have done from this
  # position, recorded and not registered. record_host_choice then fills in what the
  # host actually did, so a single entry holds both AIs' answers to the identical board
  # -- the turn-by-turn comparison that outcome numbers alone cannot give.
  def self.observe(battle, index)
    trace = battle.instance_variable_get(:@portable_ai_shadow_trace)
    return if !trace
    # Both command hooks can reach the same battler in one turn. Only the first is the
    # decision; a second entry would double-count that turn in any disagreement rate.
    last = trace[-1]
    return if last && last["turn"] == battle.turncount && last["actor"] == index
    action = nil
    plan = nil
    with_diverted_rng(battle) do
      plan = plan_for(battle)
      (plan["actions"] || []).each do |candidate|
        if candidate["actor_index"] == index
          action = candidate
          break
        end
      end
    end
    entry = {
      "turn" => battle.turncount,
      "actor" => index,
      "portable" => action_summary(action),
      "view" => view_trace(
        battle.instance_variable_get(:@portable_ai_last_snapshot), index)
    }
    if trace_candidates?
      entry["candidates"] = candidate_trace(
        plan || {}, index, battle.instance_variable_get(:@portable_ai_last_snapshot))
    end
    trace << entry
  rescue Exception => error
    log_error(error, index)
    clear_cache(battle)
    # A failed observation must leave a mark. Realidea's pbRoughDamage can divide by zero
    # (085:3557) while the snapshot is scoring a move, which leaves the actor with no
    # usable actions and no entry at all -- and an absent turn is indistinguishable from
    # "the actor had nothing to decide". Silently dropping it would shrink the
    # denominator of every agreement figure by an unknown amount. Recorded with a null
    # portable answer instead, so shadow_check counts it as unscorable and says so.
    failed = battle.instance_variable_get(:@portable_ai_shadow_trace)
    if failed
      last = failed[-1]
      if !(last && last["turn"] == battle.turncount && last["actor"] == index)
        failed << {
          "turn" => battle.turncount, "actor" => index, "portable" => nil,
          "observer_error" => "#{error.class}: #{error.message}"
        }
      end
    end
  end

  # Every roll taken inside the block comes from a private generator instead of the
  # battle's, and the count of them is kept: it is the number of draws the observation
  # would otherwise have stolen from the host, so a run reporting zero has either
  # observed nothing or lost its diversion.
  def self.with_diverted_rng(battle)
    previous = battle.instance_variable_get(:@portable_ai_observer_rng)
    rng = NeutralRNG.new(battle.turncount.to_i + 1)
    battle.instance_variable_set(:@portable_ai_observer_rng, rng)
    yield
  ensure
    battle.instance_variable_set(:@portable_ai_observer_rng, previous)
    if rng && rng.draws > 0
      total = battle.instance_variable_get(:@portable_ai_shadow_rng_draws).to_i
      battle.instance_variable_set(:@portable_ai_shadow_rng_draws, total + rng.draws)
    end
  end

  def self.action_summary(action)
    return nil if !action
    {
      "type" => action["type"],
      "slot" => action["slot"],
      "move_id" => action["move_id"],
      "numeric_move_id" => action["numeric_move_id"],
      "target" => action["target"],
      "score" => action["score"]
    }
  end

  # Engine choice codes, read off this engine's own pbRegisterMove/pbRegisterSwitch
  # rather than assumed: Realidea numbers a switch 2, where Reborn numbers it 3. An
  # unrecognised code is recorded as its number instead of being labelled, because a
  # mislabelled choice would read as a disagreement that never happened.
  CHOICE_TYPES = { 1 => "move", 2 => "switch", 3 => "item", 4 => "call", 5 => "run" }

  # What the host registered, read back from battle.choices in the shape the portable
  # action already uses. This is the half Realidea never recorded: without it a trace
  # says what portable would have done but not what it would have differed FROM.
  # numeric_move_id is the comparison key -- the choice holds a PokeBattle_Move object,
  # and its numeric id is the one field both sides carry without a name lookup.
  def self.record_host_choice(battle, index)
    trace = battle.instance_variable_get(:@portable_ai_shadow_trace)
    return if !trace
    entry = trace[-1]
    return if !entry || entry["actor"] != index || entry["turn"] != battle.turncount
    return if entry.has_key?("stock")
    entry["stock"] = describe_choice(battle.choices[index])
    foes = foe_choices(battle)
    entry["foe"] = foes if foes
  rescue
  end

  # What the OTHER side picked this turn, stashed as the command phase walks the seats.
  # PortableAIGauntlet.command_phase drives all four battlers through
  # pbDefaultChooseEnemyCommand in index order, so seat 0 has already registered by the
  # time the measured seat's entry is written -- which is what makes attaching it
  # possible at all. Without this a readout shows one side of a two-sided turn, and a
  # switch or a heal on the far side looks like the board changing for no reason.
  #
  # These are CHOICES, not outcomes: registered before the turn executes, so a move here
  # may still miss, be Protected, or never fire because its user fainted first. Execution
  # order is priority and speed, not the index order they were chosen in.
  def self.stash_foe_choice(battle, index)
    stash = battle.instance_variable_get(:@portable_ai_foe_choices)
    if !stash || stash["turn"] != battle.turncount
      stash = { "turn" => battle.turncount, "choices" => {} }
      battle.instance_variable_set(:@portable_ai_foe_choices, stash)
    end
    described = describe_choice(battle.choices[index])
    stash["choices"][index.to_s] = described if described
  rescue
  end

  def self.foe_choices(battle)
    stash = battle.instance_variable_get(:@portable_ai_foe_choices)
    return nil if !stash || stash["turn"] != battle.turncount
    return nil if stash["choices"].empty?
    stash["choices"]
  rescue
    nil
  end

  def self.describe_choice(choice)
    return nil if !choice
    kind = CHOICE_TYPES[choice[0]]
    return { "type" => "unregistered", "code" => choice[0] } if !kind
    out = { "type" => kind, "slot" => choice[1] }
    if choice[0] == 1
      move = choice[2]
      out["numeric_move_id"] = (move.id rescue nil)
      out["move_id"] = (getConstantName(PBMoves, move.id) rescue nil)
      out["target"] = choice[3]
    end
    out
  end

  # --- faint replacement ------------------------------------------------------
  #
  # Stock Essentials picks the replacement for a fainted AI Pokemon by summing the type
  # chart over each candidate's moves (pbChooseBestNewEnemy, 085_PokeBattle_AI.rb:4283)
  # and reads nothing about what the candidate takes on the way in. That is how a
  # Scizor was sent into a Heatran that removes it in one Lava Plume (team3_vs_team2
  # 155921 t29). The core already prices a forced switch -- entry damage, the
  # switch-in race, dies_on_entry -- so a Portable-driven side's replacement goes
  # through the same scorer. One run-level switch lets the gauntlet keep the older
  # convention (stock replacement on BOTH sides, so strength differences stayed
  # attributable to turn decisions); in play it is simply on.
  def self.replacement?
    return true if !defined?($PORTABLE_AI_REPLACEMENT)
    $PORTABLE_AI_REPLACEMENT != false
  end

  # The party slot the core would send in for the fainted battler at `index`, or nil
  # when it has nothing to say. nil means the stock chooser -- never a slot the engine
  # would refuse, which is re-checked on the way out.
  def self.choose_replacement(battle, index, party)
    battler = battle.battlers[index]
    return nil if !battler
    foe_indices = [0]
    foe_indices << 2 if battle.doublebattle
    foe_indices = foe_indices.select do |i|
      foe = battle.battlers[i] rescue nil
      foe && !foe.isFainted?
    end
    skill = corrected_skill(battle.pbGetOwner(index))
    actions = switch_actions(battle, battler, foe_indices, skill, true)
    return nil if actions.empty?
    snapshot = {
      "format" => battle.doublebattle ? "double" : "single",
      "turn" => battle.turncount,
      "weather" => weather_name(battle),
      "trick_room_active" => trick_room_active?(battle),
      "tailwind_active" => (safe_side_effect(battle.sides[1], :Tailwind, 0).to_i > 0),
      "actors" => [{ "index" => index, "species" => battler.species,
                     "hp_pct" => 0.0, "actions" => actions }],
      "targets" => foe_indices.map { |i| battler_view(battle.battlers[i], battle, skill) },
      "memory" => battle.instance_variable_get(:@portable_ai_memory) || {}
    }
    # The forced-switch consumer needs the same grid the voluntary one reads: this is
    # the decision the sole-answer rule was written for.
    snapshot["matrix"] = party_matrix(battle, index, foe_indices, skill) if
      matrix_wanted?(battle)
    plan = run_planner(snapshot, config_for(skill), BattleRNG.new(battle))
    chosen = nil
    (plan["actions"] || []).each do |action|
      chosen = action if action["actor_index"] == index && action["type"] == "switch"
    end
    return nil if !chosen
    slot = chosen["slot"]
    return nil if !battle.pbCanSwitchLax?(index, slot, false)
    trace = battle.instance_variable_get(:@portable_ai_decision_trace)
    if trace
      entry = {
        "turn" => battle.turncount, "actor" => index, "type" => "switch",
        "forced" => true, "slot" => slot, "score" => chosen["score"],
        "view" => view_trace(snapshot, index)
      }
      entry["candidates"] = candidate_trace(plan, index, snapshot) if trace_candidates?
      trace << entry
    end
    slot
  rescue Exception => error
    log_error(error, index)
    nil
  end

  # 0.7.0. WHICH PLANNER ANSWERS. Both take the same snapshot and return the same
  # shape, so this is the only place that knows there are two.
  #
  # The search planner declines by returning nil -- on doubles, and on any snapshot it
  # cannot resolve a board out of. That covers the forced-replacement path below
  # without a special case: the actor there is fainted, a fainted body occupies no
  # matrix seat, and a board with no own slot is one it refuses. So the search arm is
  # a voluntary-turn experiment and replacement switches stay with the rule engine
  # until something measures otherwise.
  #
  # No rescue. A planner that raises should show up in the run's error readout, not be
  # silently papered over by the arm it is supposed to be compared against.
  def self.run_planner(snapshot, config, rng)
    if config["search_planner"]
      searched = PortableAI::Search.plan(snapshot, config, rng)
      return searched if searched
    end
    PortableAI.plan(snapshot, config, rng)
  end

  def self.plan_for(battle)
    signature = cache_signature(battle)
    cached_signature = battle.instance_variable_get(:@portable_ai_cache_signature)
    cached = battle.instance_variable_get(:@portable_ai_plan)
    return cached if cached && cached_signature == signature

    snapshot, skill = build_snapshot(battle)
    config = config_for(skill)
    # 0.8.0. The bridge runs first and declines by returning nil, exactly as the
    # search planner does, so a silent sidecar or an unmappable reply falls through to
    # whatever planner the rest of the config names.
    use_foul_play = config["foul_play"] &&
                    !battle.instance_variable_get(:@portable_ai_foul_play_off)
    plan = use_foul_play ? FoulPlay.plan(battle, snapshot, config) : nil
    plan ||= run_planner(snapshot, config, BattleRNG.new(battle))
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
    out = {
      # Who this actually is. The trace used to record six scalars and the chosen move,
      # which made a readout unreadable without cross-referencing `parties` by seat --
      # and `parties` holds FINAL hp, not hp at the moment of the decision. All of this
      # is already in the snapshot the core was handed; none of it is newly computed.
      "species" => species_name(actor["species"]),
      "status" => actor["status"],
      "ability" => actor["ability"],
      "item" => actor["item"],
      "positive_stage_total" => actor["positive_stage_total"],
      "negative_stage_total" => actor["negative_stage_total"],
      "hp_pct" => actor["hp_pct"],
      "speed" => actor["speed"],
      "faster" => actor["faster"],
      "incoming_damage_pct" => actor["incoming_damage_pct"],
      "certain_incoming_damage_pct" => actor["certain_incoming_damage_pct"],
      "threatened_lethal" => actor["threatened_lethal"],
      # The board opposite, as the core saw it -- so `race vs foe@0` names a Pokemon
      # instead of a seat, and a switch decision can be read against what it faced.
      "targets" => (snapshot["targets"] || []).map do |t|
        {
          "index" => t["index"], "species" => species_name(t["species"]),
          "hp_pct" => t["hp_pct"],
          "status" => t["status"], "speed" => t["speed"], "ability" => t["ability"],
          "item" => t["item"], "positive_stages" => t["positive_stages"]
        }
      end,
      "race" => race,
      # 0.6.5. The whole grid, as the core derives it -- rows are our party, columns
      # theirs, and the verdict of each live pair at the HP both are standing on.
      # Reported AS COMPUTED, like the race above: a readout of a run with the
      # consumers off still has to show what they would have read.
      "matrix" => matrix_trace(snapshot)
    }
    # 0.6.6. The foe's declared intent and the hit it implies, when this run read
    # one; absent otherwise, so a readout can tell an oracle run from a plain one.
    if actor.key?("predicted_incoming_damage_pct")
      out["predicted_incoming_damage_pct"] = actor["predicted_incoming_damage_pct"]
      out["predicted_incoming_accuracy"] = actor["predicted_incoming_accuracy"]
      out["predicted_foe"] = actor["predicted_foe"]
    end
    out
  rescue
    {}
  end

  # The compact form: who is on each side, and W/L/S per live pair. The cells
  # themselves -- two damage numbers, two categories, two move names each -- are
  # roughly twenty times the size and only appear under trace=true, which is the same
  # split candidate_trace makes and what keeps a plain shadow file near 1.6 MB.
  def self.matrix_trace(snapshot)
    m = (snapshot || {})["matrix"]
    return nil if !m.is_a?(Hash)
    verdicts = {}
    PortableAI.matrix_live_slots(m["own"]).each do |own_slot|
      PortableAI.matrix_live_slots(m["foe"]).each do |foe_slot|
        verdicts["#{own_slot}:#{foe_slot}"] =
          PortableAI.matrix_verdict(snapshot, own_slot, foe_slot)
      end
    end
    out = { "own" => matrix_trace_side(m["own"]),
            "foe" => matrix_trace_side(m["foe"]),
            "verdicts" => verdicts }
    out["cells"] = m["cells"] if trace_candidates?
    out
  rescue
    nil
  end

  def self.matrix_trace_side(table)
    out = []
    (table || []).each do |entry|
      next if !entry
      out << { "slot" => entry["slot"], "species" => species_name(entry["species"]),
               "hp_pct" => entry["hp_pct"], "active" => !entry["index"].nil? }
    end
    out
  end

  # Every option a singles actor can have: four moves and five bench slots. The old
  # limit of 6 cut the list at two switches, so a readout could not say what the third
  # bench Pokemon scored -- which was exactly the question being asked of it.
  TRACE_CANDIDATE_LIMIT = 10

  # The snapshot carries the engine's numeric species id, because that is what the core
  # is given and nothing in the core wants a name. A trace is read by people, so it is
  # named on the way out only -- the snapshot itself is untouched. Same call
  # party_snapshot uses, so a trace and a record's `parties` agree on spelling.
  def self.species_name(id)
    return nil if id.nil?
    name = (PBSpecies.getName(id) rescue nil)
    (name.nil? || name == "") ? id.to_s : name
  end

  # Every option the actor had, with what it scored and why -- the moveset and the
  # scoring the chosen action alone cannot show. The core already ranks and explains
  # every candidate (core.rb builds diagnostics.rankings and attaches `reasons` to each);
  # this reads that out instead of recomputing anything.
  #
  # Gated on trace= because it is the bulky half: a plain shadow run stays lean and still
  # names both mons, while trace=true gives the full breakdown.
  def self.candidate_trace(plan, index, snapshot = nil)
    diagnostics = plan["diagnostics"] || {}
    rankings = diagnostics["rankings"] || []
    actors = (plan["actions"] || []).map { |action| action["actor_index"] }
    slot = actors.index(index)
    return [] if slot.nil?
    out = []
    (rankings[slot] || []).each do |candidate|
      break if out.length >= TRACE_CANDIDATE_LIMIT
      entry = {
        "type" => candidate["type"],
        "slot" => candidate["slot"],
        "move_id" => candidate["move_id"],
        "target" => candidate["target"],
        "score" => candidate["score"],
        # 0.6.3: the two estimates a switch candidate is judged on, so a readout can
        # say why a bench Pokemon did or did not count as winning its race.
        "outgoing_damage_pct" => candidate["outgoing_damage_pct"],
        "incoming_damage_pct" => candidate["incoming_damage_pct"],
        "predicted_incoming_damage_pct" => candidate["predicted_incoming_damage_pct"],
        "candidate_hp_pct" => candidate["candidate_hp_pct"],
        "faster" => candidate["faster"],
        "reasons" => candidate["reasons"]
      }
      # What the score was computed FROM, for a move. Without these a reader can see
      # that Bullet Punch beat Bug Bite but not that it was 28% into a 4x resist.
      # 0.7.0: search_row is the payoff against each foe option in order, which is the
      # only way to read why a maximin pick went where it did. 0.7.6: and search_visits
      # is what the tree RANKS by, so without it an MCTS readout shows six averages
      # within a hundredth of each other and no reason for the pick between them.
      %w[power effectiveness expected_damage_pct immune damaging priority
         search_mean search_row search_cell search_visits].each do |key|
        entry[key] = candidate[key] if candidate.has_key?(key)
      end
      # A switch candidate names the bench Pokemon it would bring in.
      entry["species"] = species_name(candidate["species"]) if candidate["species"]
      # 0.6.5. And what only IT answers, which is the whole of the sole_answer term:
      # a reader seeing -300 on a candidate needs the two names behind it. Empty
      # without a matrix, so this is inert on a run with the key off.
      if candidate["type"] == "switch" && snapshot
        named = sole_answer_names(snapshot, candidate["slot"])
        entry["sole_answer_to"] = named if !named.empty?
      end
      out << entry
    end
    out
  rescue
    []
  end

  # The live foes this bench slot is the only answer to, named.
  def self.sole_answer_names(snapshot, slot)
    table = ((snapshot || {})["matrix"] || {})["foe"]
    out = []
    PortableAI.sole_answers(snapshot, slot).each do |foe_slot|
      entry = PortableAI.matrix_entry(table, foe_slot)
      out << species_name(entry["species"]) if entry
    end
    out
  rescue
    []
  end

  # 0.7.7 diagnostic. WHERE THE TREE SPENT ITS BUDGET, next to what the foe then did.
  #
  # `foe_visits` is the MCTS root's own opponent model: how UCB1 spread the iterations
  # over the foe's options once the foe's own payoff chose between them. The entry
  # already carries `foe`, the move the foe actually registered that turn, so recording
  # the two together is the whole test of whether seeding the tree's foe statistics
  # from the stock model could buy anything -- if the tree already concentrates on the
  # moves the foe really plays, a better prior has nothing to correct.
  #
  # Diagnostics-only and small (two parallel arrays per decision, one entry each per
  # foe option), so unlike candidate_trace this is not gated on trace= -- a plain
  # shadow run answers the question too. Absent entirely on the maximin path, which
  # publishes no foe_visits.
  def self.search_trace(plan)
    diagnostics = plan["diagnostics"] || {}
    visits = diagnostics["foe_visits"]
    return nil if !visits.is_a?(Array) || visits.empty?
    { "foe_options" => diagnostics["foe_options"],
      "foe_visits" => visits,
      "iterations" => diagnostics["iterations"] }
  rescue
    nil
  end

  def self.trace_candidates?
    defined?($AI_GAUNTLET_TRACE) && $AI_GAUNTLET_TRACE ? true : false
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
    snapshot = {
      "format" => battle.doublebattle ? "double" : "single",
      "turn" => battle.turncount,
      "weather" => weather_name(battle),
      "trick_room_active" => trick_room_active?(battle),
      "tailwind_active" => (safe_side_effect(battle.sides[1], :Tailwind, 0).to_i > 0),
      "actors" => actors,
      "targets" => targets,
      "memory" => memory
    }
    # 0.6.5. Both parties, priced against each other. Absent when the key is off or
    # when nothing on this run would read it, and every core rule that reads it is
    # inert without it.
    # The key is always present, nil included: "the core reads this" is a contract
    # (test_realidea_adapter.rb TOP_LEVEL_KEYS), and nil is what every rule that
    # reads it is written to go inert on.
    snapshot["matrix"] = matrix_wanted?(battle) ?
                         party_matrix(battle, indices[0], foe_indices, skill) : nil
    [snapshot, skill]
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
      "partner_ability" => (partner && !partner.isFainted? ? ability_key(partner) : nil),
      # 0.7.1. Whether this body could leave, by the engine's own pbCanSwitch? -- the
      # same test the actor view answers for itself. The rule engine never reads it on
      # a target; the search planner drops the foe's switch column when it is true.
      "trapped" => !has_legal_switch?(battle, battler.index)
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
    intents = foe_intents(battle, foe_indices)
    switch_actions(battle, battler, foe_indices, skill, false, intents).each do |action|
      actions << action
    end

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
    # 0.6.6. What the foe has committed to, when this run is allowed to know it
    # (foe_intents, read once above for the bench candidates too).
    predicted = intents.empty? ? nil : predicted_incoming(battle, battler, intents, skill)
    toxic_stage = safe_effect(battler, :Toxic, 0).to_i
    residual = 0.0
    residual += (toxic_stage + 1) * 100.0 / 16.0 if toxic_stage > 0
    residual += 100.0 / 8.0 if safe_effect(battler, :LeechSeed, -1).to_i >= 0
    out = {
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
    if predicted
      # Present ONLY when an intent was read, so a run with the key off exports
      # nothing and the core's consumers stay on the worst-case figures.
      out["predicted_incoming_damage_pct"] = predicted["damage_pct"]
      out["predicted_incoming_accuracy"] = predicted["accuracy"]
      out["predicted_foe"] = predicted["foe"]
    end
    out
  end

  # ---------------------------------------------------------------------------
  # 0.6.6. WHAT THE FOE IS ABOUT TO DO.
  #
  # Every incoming estimate in this adapter is the WORST the foe could do: the
  # actor's incoming_damage_pct is the max over the foe's moves, a bench candidate's
  # is the max against that candidate. The foe clicks one move. Read off the 0.6.5
  # traces, the foe's best-damage move against the actor was its actual choice on
  # 54.9% of 891 turns, and the misses were mostly status and pivot moves -- so half
  # the time the entry hit the core charged a switch for was a move the foe had
  # not clicked: "Sceptile takes 167% from Rhydon" was Megahorn, and Rhydon had
  # registered Earthquake (gen5ru_a team3_vs_team4 104729 t8).
  #
  # This is the CONSUMER side of a prediction: the foe's intent, per foe, as a move
  # object or a switch, and the hit it implies against the actor and against each
  # bench candidate. Today the only producer is the oracle -- the registered choice
  # itself, under the foe_oracle key -- which is the ceiling, not a policy. A model
  # that predicts the move goes through the same three methods and exports the same
  # fields, and its number is judged against the oracle's.
  #
  # THE ORACLE IS CHEATING, and it can only cheat because of seat order: the gauntlet
  # registers seat 0 before seat 1 (PortableAIGauntlet.command_phase), and in play
  # the player registers before pbDefaultChooseEnemyCommand runs. The engine resets
  # every choice at the top of each command phase (084:3045-3051), so a registered
  # choice is always this turn's. A forced replacement decides between turns, after
  # the choices have executed and before they are reset, so it must not read them;
  # choose_replacement passes no intents.
  #
  # Keyed by foe index as an INTEGER here (this is the adapter's own working table);
  # the exported predicted_foe is keyed by string like threats_by_foe.
  def self.foe_intents(battle, foe_indices)
    out = {}
    return stock_intents(battle, foe_indices) if !rule_enabled?("foe_oracle")
    foe_indices.each do |foe_index|
      choice = battle.choices[foe_index] rescue nil
      next if !choice
      case choice[0]
      when 1
        move = choice[2]
        next if !move || (move.id rescue 0) == 0
        out[foe_index] = { "kind" => "move", "move" => move,
                           "target" => (choice[3].nil? ? -1 : choice[3].to_i) }
      when 2
        out[foe_index] = { "kind" => "switch", "slot" => (choice[1].nil? ? nil : choice[1].to_i) }
      end
    end
    out
  rescue
    {}
  end

  # 0.7.5. THE SECOND PRODUCER: what stock v16 would do, read from its own code
  # without the dice. Under foe_stock_model (and only when the oracle is off -- the
  # oracle is the ceiling this is judged against). Per foe: the withdraw triggers of
  # pbEnemyShouldWithdrawEx? (085:4116) as a CHANCE rather than a roll, the slot its
  # list would put first, and the move pbGetMoveScore scores highest. Nothing here
  # registers anything or draws a random number, so a run with the key on still
  # reproduces its own dice; but pbGetMoveScore is the scorer that divides by zero
  # on some boards (085:3557), so every foe is rescued on its own.
  #
  # What the triggers say about the measured foe: it switches on a super-effective
  # hit it just took (20-30%), on a Toxic about to kill (80%), on an Encore into a
  # dead move (80%), on Perish count 1 or on having no move left -- and otherwise
  # NEVER. That is why maximin's worst case (the wall it could switch to) is a reply
  # it does not make.
  def self.stock_intents(battle, foe_indices)
    out = {}
    return out if !rule_enabled?("foe_stock_model")
    foe_indices.each do |foe_index|
      intent = stock_intent(battle, foe_index)
      out[foe_index] = intent if intent
    end
    out
  rescue
    {}
  end

  def self.stock_intent(battle, foe_index)
    foe = battle.battlers[foe_index]
    return nil if !foe || foe.isFainted?
    skill = (battle.pbGetOwner(foe_index).skill rescue nil) || 0
    chance = stock_switch_chance(battle, foe, skill)
    slot = chance > 0.0 ? stock_switch_slot(battle, foe) : nil
    chance = 0.0 if slot.nil?
    return { "kind" => "switch", "slot" => slot } if chance >= 1.0
    move = stock_move(battle, foe, skill)
    return nil if !move
    { "kind" => "move", "move" => move, "target" => -1,
      "switch_chance" => chance, "switch_slot" => slot }
  rescue
    nil
  end

  # pbEnemyShouldWithdrawEx?'s triggers, each with the probability its roll gives
  # it, combined as "any of them fires". The Hyper Beam / Truant clause, which
  # cancels a switch 80% of the time, scales what the others found.
  def self.stock_switch_chance(battle, foe, skill)
    high = (skill >= PBTrainerAI.highSkill rescue false)
    medium = (skill >= PBTrainerAI.mediumSkill rescue false)
    fires = []
    if high && (foe.turncount rescue 0).to_i > 0
      opp = foe.pbOppositeOpposing
      opp = opp.pbPartner if opp && opp.isFainted?
      last = (opp && !opp.isFainted?) ? (opp.lastMoveUsed rescue 0).to_i : 0
      if last > 0 && ((opp.level - foe.level).abs rescue 99) <= 6
        data = PBMoveData.new(last)
        typemod = (battle.pbTypeModifier(data.type, foe, foe) rescue 8)
        if data.basedamage > 70 && typemod > 8
          fires << 0.3
        elsif data.basedamage > 50 && typemod > 8
          fires << 0.2
        end
      end
    end
    usable = (0...4).any? { |i| (battle.pbCanChooseMove?(foe.index, i, false) rescue true) }
    fires << 1.0 if !usable && (foe.turncount rescue 0).to_i > 5
    if high && foe.status == PBStatuses::POISON && (foe.statusCount rescue 0).to_i > 0
      toxic_hp = foe.totalhp / 16
      next_hp = toxic_hp * (safe_effect(foe, :Toxic, 0).to_i + 1)
      fires << 0.8 if next_hp >= foe.hp && toxic_hp < foe.hp
    end
    if medium && safe_effect(foe, :Encore, 0).to_i > 0
      idx = safe_effect(foe, :EncoreIndex, 0).to_i
      opp = foe.pbOppositeOpposing
      if opp && !opp.isFainted? && foe.moves[idx]
        score = (battle.pbGetMoveScore(foe.moves[idx], foe, opp, skill) rescue 100)
        fires << 0.8 if score <= 20
      end
    end
    fires << 1.0 if safe_effect(foe, :PerishSong, 0).to_i == 1
    return 0.0 if fires.empty?
    chance = 1.0 - fires.inject(1.0) { |acc, f| acc * (1.0 - f) }
    if high
      opp = foe.pbOppositeOpposing
      if opp && !opp.isFainted? &&
         (safe_effect(opp, :HyperBeam, 0).to_i > 0 ||
          ((opp.hasWorkingAbility(:TRUANT) rescue false) && safe_effect(opp, :Truant, false)))
        chance *= 0.2
      end
    end
    chance
  rescue
    0.0
  end

  # The slot stock's list puts first: party order among the bodies it may switch
  # to, with a body immune to the move it just took moved ahead (its 65% / 85%
  # roll, read as "usually"), or one resisting it when that body is also
  # super-effective on us (its 60%).
  def self.stock_switch_slot(battle, foe)
    party = battle.pbParty(foe.index)
    return nil if !party
    opp = foe.pbOppositeOpposing
    last = (opp && !opp.isFainted?) ? (opp.lastMoveUsed rescue 0).to_i : 0
    movetype = last > 0 ? (PBMoveData.new(last).type rescue -1) : -1
    first = nil
    party.each_with_index do |pokemon, slot|
      next if !pokemon || !(battle.pbCanSwitch?(foe.index, slot, false) rescue false)
      first = slot if first.nil?
      next if movetype < 0
      typemod = (battle.pbTypeModifier(movetype, foe, foe) rescue 8)
      return slot if typemod == 0
      if typemod < 8 && (battle.pbTypeModifier2(pokemon, opp) rescue 8) > 8
        return slot
      end
    end
    first
  rescue
    nil
  end

  # The move pbChooseMoves would score highest against the body in front of it;
  # the first usable one when nothing scores above zero (stock then picks among
  # its usable moves at random, and the first is as good a guess as any).
  def self.stock_move(battle, foe, skill)
    opp = foe.pbOppositeOpposing
    opp = opp.pbPartner if opp && opp.isFainted?
    return nil if !opp || opp.isFainted?
    best = nil
    best_score = 0
    first = nil
    (foe.moves || []).each_with_index do |move, i|
      next if !move || (move.id rescue 0) == 0
      next if !(battle.pbCanChooseMove?(foe.index, i, false) rescue true)
      first = move if first.nil?
      score = (battle.pbGetMoveScore(move, foe, opp, skill) rescue 0).to_i
      next if score <= best_score
      best = move
      best_score = score
    end
    best || first
  rescue
    nil
  end

  # Whether a foe's declared move lands on the given seat. Singles registers no
  # target (-1); a spread move hits every foe; otherwise the registered target says.
  def self.intent_aimed_at?(intent, seat)
    return false if !intent || intent["kind"] != "move"
    target = intent["target"].to_i
    return true if target < 0
    return true if target == seat
    (PBTargets.hasMultipleTargets?(intent["move"]) rescue false) ? true : false
  end

  # The hit the declared moves land on `battler` this turn: 0 for a status move, a
  # switch, or a foe that cannot act (frozen, asleep with sleep to serve -- the same
  # guard certain_incoming_damage keeps). Accuracy is the engine's own estimate of the
  # least accurate counted move, so the core can discount the hit by its chance of
  # happening; nil when no counted move has one.
  def self.predicted_incoming(battle, battler, intents, skill)
    damage = 0.0
    accuracy = nil
    priority = 0
    foes = {}
    intents.each do |foe_index, intent|
      foe = battle.battlers[foe_index]
      next if !foe || foe.isFainted?
      entry = { "type" => intent["kind"] }
      # A model's own reading of its switch, beside the move it expects (0.7.5); the
      # oracle's switch carries its slot the same way when it knows one.
      entry["slot"] = intent["slot"] if intent.key?("slot")
      entry["switch_chance"] = intent["switch_chance"] if intent.key?("switch_chance")
      entry["switch_slot"] = intent["switch_slot"] if intent.key?("switch_slot")
      if intent["kind"] == "move"
        move = intent["move"]
        entry["move_id"] = move_key(move.id)
        entry["target"] = intent["target"]
        if intent_aimed_at?(intent, battler.index) && foe_can_act?(foe)
          hit = rough_damage_pct(battle, move, foe, battler, skill)
          acc = rough_accuracy(battle, move, foe, battler, skill)
          pri = effective_priority(move, foe)
          entry["damage_pct"] = hit
          entry["accuracy"] = acc
          entry["priority"] = pri
          damage += hit
          accuracy = acc if hit > 0 && !acc.nil? && (accuracy.nil? || acc < accuracy)
          priority = pri if hit > 0 && pri > priority
        else
          entry["damage_pct"] = 0.0
        end
      end
      foes[foe_index.to_s] = entry
    end
    { "damage_pct" => damage, "accuracy" => accuracy, "priority" => priority,
      "foe" => foes }
  rescue
    nil
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

  # `replacement` builds the candidates for a FAINTED battler: legality is the engine's
  # own pbCanSwitchLax? (the test the stock chooser applies) rather than pbCanSwitch?,
  # which reads trapping effects off a battler that has just gone down, and every
  # candidate is forced -- the core skips its escape gate and ranks bodies.
  def self.switch_actions(battle, battler, foe_indices, skill, replacement = false,
                          intents = nil)
    party = battle.pbParty(battler.index)
    forced = replacement || safe_effect(battler, :PerishSong, 0) == 1
    actions = []
    party.each_with_index do |pokemon, slot|
      next if !pokemon
      legal = replacement ? battle.pbCanSwitchLax?(battler.index, slot, false) :
                            battle.pbCanSwitch?(battler.index, slot, false)
      next if !legal
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
      hits = switch_incoming_damages(battle, pokemon, slot, battler, foe_indices, skill,
                                     intents)
      if hits
        action["incoming_damage_pct"] = hits["worst"]
        # 0.6.6. Present only when the foe's intent was read: the hit the DECLARED
        # move lands on this candidate, which the core prices the entry on
        # (Core.entry_hit_pct). The worst case above stays what the race after
        # entry is run on.
        action["predicted_incoming_damage_pct"] = hits["predicted"] if !hits["predicted"].nil?
      end
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
  # PokeBattle_Battler#initialize is NOT pure. pbInitEffects reaches across to every
  # OTHER battler and clears whatever points at the index being built. Building a fake
  # at the actor's own index therefore cancels real effects on the board it is only
  # supposed to be measuring, so every slot it can touch is snapshotted and restored.
  # pbInitPokemon itself only copies stats and builds move objects through pbFromPBMove.
  #
  # There are FOUR such writes in Realidea, not the three stock Essentials documents:
  # Lock-On (LockOn + LockOnPos), infatuation (Attract), Mean Look (MeanLook), and --
  # this engine's own -- partial trapping (MultiTurn + MultiTurnUser), which stock v16
  # does not clear here. Missing that last pair meant that every time the AI weighed a
  # switch while it had a foe bound by Infestation, Wrap, Fire Spin or any other binding
  # move, merely THINKING about the switch set the foe free.
  #
  # That was invisible until the shadow arm gave it something to contradict: an observed
  # battle must play out exactly like its unobserved twin, and 14 of the first 60 did
  # not. All 14 were the matchups whose observed team carried the one Infestation user
  # in the roster. The bug is older than the shadow arm and was corrupting the live
  # Portable arm's own battles too -- it just had no way to show up there, because with
  # nothing to compare against, a freed foe is simply what happened.
  #
  # The list is read off THIS engine's pbInitEffects. If a future Realidea build adds a
  # fifth, the shadow equality check is what will catch it; see PORTABLE-AI-REALIDEA.md.
  #
  # nil when the engine refuses, which leaves the core on the type proxy it used
  # through 0.1.0.
  RESTORED_ON_FAKE = [:Attract, :MeanLook, :LockOn, :LockOnPos,
                      :MultiTurn, :MultiTurnUser]

  # The save/restore on its own, so a caller that needs MANY fakes pays for the board
  # once instead of once per body (party_matrix builds up to ten). Returns whatever
  # the block returns; the restore runs even when the block raises.
  def self.preserving_board(battle)
    saved = []
    for i in 0...4
      other = battle.battlers[i]
      next if !other
      values = []
      RESTORED_ON_FAKE.each { |name| values << safe_effect(other, name, nil) }
      saved << [other, values]
    end
    begin
      yield
    ensure
      saved.each do |entry|
        RESTORED_ON_FAKE.each_with_index do |name, slot|
          value = entry[1][slot]
          next if value.nil?
          next if !PBEffects.const_defined?(name.to_s)
          entry[0].effects[PBEffects.const_get(name.to_s)] = value
        end
      end
    end
  end

  # The construction alone. ONLY safe inside preserving_board -- on its own it leaves
  # the board with whatever pbInitEffects cleared.
  def self.fake_battler_unguarded(battle, pokemon, party_index, index)
    fake = PokeBattle_Battler.new(battle, index)
    fake.pbInitPokemon(pokemon, party_index)
    fake
  rescue
    nil
  end

  def self.fake_battler(battle, pokemon, party_index, index)
    preserving_board(battle) do
      fake_battler_unguarded(battle, pokemon, party_index, index)
    end
  rescue
    nil
  end

  # What the candidate actually eats on the turn it comes in, with its own Intimidate
  # applied to the foes first -- the only way an entry ability shows up in the number
  # at all. The temporary stage mutation is restored in `ensure`; pbCanReduceStatStage?
  # is what makes Clear Body, White Smoke, Full Metal Body and Hyper Cutter exempt.
  def self.switch_incoming_damage(battle, pokemon, party_index, battler, foe_indices, skill)
    hits = switch_incoming_damages(battle, pokemon, party_index, battler, foe_indices, skill)
    hits ? hits["worst"] : nil
  end

  # The same pass, also pricing the foe's DECLARED move against the candidate when an
  # intent table is given (0.6.6): one fake, one Intimidate application, both
  # numbers. "predicted" is nil without intents, so the export stays absent.
  def self.switch_incoming_damages(battle, pokemon, party_index, battler, foe_indices,
                                   skill, intents = nil)
    fake = fake_battler(battle, pokemon, party_index, battler.index)
    return nil if !fake
    intimidate = (ability_key(pokemon) == "INTIMIDATE")
    saved = {}
    worst = 0.0
    predicted = (intents && !intents.empty?) ? 0.0 : nil
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
        next if predicted.nil?
        intent = intents[foe_index]
        # The candidate takes the actor's seat, so "aimed at the actor" is aimed at it.
        next if !intent_aimed_at?(intent, battler.index) || !foe_can_act?(foe)
        predicted += rough_damage_pct(battle, intent["move"], foe, fake, skill)
      end
    ensure
      saved.each do |foe_index, value|
        battle.battlers[foe_index].stages[PBStats::ATTACK] = value
      end
    end
    { "worst" => worst, "predicted" => predicted }
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
        # 0.6.4 (switch_estimate_pp). A move with no PP left is not a hit this body
        # has. The field view drops it (pbCanChooseMove?), this estimate did not, so in
        # a long stall war -- Quagsire and Chansey in front of a Zapdos at turn 89,
        # every Scald and Seismic Toss spent -- the bench body "hit for 27%" while the
        # same body on the field hit for nothing, and the two traded places on
        # weak_current_attacks until the round cap. Its own PP is its own information.
        next if own.respond_to?(:pp) && own.pp.to_i <= 0 && rule_enabled?("switch_estimate_pp")
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

  # ---------------------------------------------------------------------------
  # 0.6.5. THE PARTY x PARTY DAMAGE MATRIX.
  #
  # Every estimate above this line is about the mon in front. switch_incoming_damage
  # and switch_outgoing_damage each build a fake battler, price it against the active
  # foes, and throw the battler away; nothing on either side ever sees the four bodies
  # still on the opposing bench. This builds the whole grid once -- best hit each way
  # for every live pair of party slots -- and hands it to the core, which derives the
  # hit counts and the verdicts from it (core.rb, "THE PARTY x PARTY DAMAGE MATRIX").
  #
  # SLOTS, NOT SEATS. Cells are keyed "<own party slot>:<foe party slot>", and the two
  # side tables carry the seat (`index`, nil on the bench) so the core can go from an
  # actor, a target or a switch action back to a row or a column.
  #
  # FAIR INFORMATION. It reads the foe party's movesets, which is exactly what
  # switch_incoming_damage already reads for the active foes; the contract is the
  # engine's own "fair" knowledge level, not partial observability.
  #
  # COST. In singles at battle start: ten bodies, 25 live pairs, two directions, at
  # most four moves each -- about 200 pbRoughDamage calls, once. After that only the
  # dirty rows and columns are re-rolled, so a Calm Mind costs one column (~40 calls)
  # and a turn that changes nothing but HP costs nothing at all. For comparison,
  # switch_actions already spends about ten fakes and forty calls on every decision.
  #
  # 0.7.4. EVERY MOVE, NOT ONLY THE BEST. A cell's `out` is one number, the best hit
  # the row body has on the column body, and it is all the search planner had for a
  # foe switch-in -- so every move we could click was credited the same damage
  # against every body on their bench, and the foe-switch column could not tell
  # Earthquake from Ice Beam (190 of the 227 move-versus-move disagreements with the
  # rule engine at 0.7.2 sat in that column). The rolls were already being made to
  # find the best; `out_moves` keeps them, keyed by move, with the category each is
  # priced in. Version 2 of the cell.
  #
  # 0.7.7. AND THE SAME FOR THEIRS. `in` was one number too -- the best hit the COLUMN
  # body has on the row body -- so the search's whole model of what the foe does was
  # "it attacks, at worst". Its `foe_options` was one `stay` column against five
  # switch columns, which means a tree built to let the foe's line be shaped by its
  # own payoff (0.7.6) was handed an opponent with one way to act, and decoupled UCB
  # had nothing to discover: 41/60 at 1000 iterations, 43 at 5000, against the
  # maximin's 46. The rolls were ALREADY being made and thrown away -- `incoming` is
  # the same `matrix_cell` call as `out`, with the same `moves` breakdown on it.
  # `in_moves` keeps it. No new engine calls. Version 3 of the cell.
  #
  # 0.7.9. THE WHOLE MOVE LIST, WITH WHAT THE SEARCH NEEDS TO PLAY IT. Both lists
  # carried damaging moves only, so the search's foe could attack or switch and do
  # nothing else -- never set up, heal, lay a hazard, Protect or land a status --
  # and our own switch-in below the root had one attack. poke-engine's tree hands
  # both sides every move. Each entry now also carries the hit chance (`acc`, from
  # pbRoughAccuracy -- the foe's moves never missed in the search), the priority
  # bracket (a cell carried none, so a foe's priority move was invisible), whether
  # it deals damage, and the effect triple move_effect exports for the root actions.
  # The side table carries the residual facts (status, item, ability, hazard entry
  # damage) so a projected turn can tick. Version 4 of the cell.
  MATRIX_VERSION = 4

  # WHETHER TO BUILD IT AT ALL. `party_matrix` says the matrix MAY be built; this says
  # anything would read it if it were.
  #
  # Measured on a 60-battle tier set with the consumers off and no trace: 57.2 s
  # against 72.6 s, so the grid costs about 27% of decision wall time. Both consumers
  # ship on, so the shipped default does pay it -- but an ABLATION arm with them off
  # would otherwise pay it for a grid that is never printed and never scored, and so
  # would every battle of a build whose defaults are later turned back off. The build
  # follows its readers: either consumer, or a run that is recording a trace (the
  # gauntlet's decision trace, the shadow observer, the probe). Turning party_matrix
  # off still forces it off everywhere, which is what the control run needs.
  def self.matrix_wanted?(battle)
    return false if !rule_enabled?("party_matrix")
    return true if rule_enabled?("sole_answer") || rule_enabled?("setup_matrix")
    return true if battle.instance_variable_get(:@portable_ai_decision_trace)
    return true if battle.instance_variable_get(:@portable_ai_shadow_trace)
    return true if defined?($aiprobe) && $aiprobe
    false
  rescue
    false
  end

  # The whole field, or nil when the key is off or the engine refuses. Cached on the
  # battle object against a per-slot signature; clear_cache deliberately leaves it
  # alone, because the signature is what invalidates it and the battle object is per
  # battle, so nothing leaks across two of them.
  def self.party_matrix(battle, own_index, foe_indices, skill)
    own_party = battle.pbParty(own_index)
    foe_party = battle.pbOpposingParty(own_index)
    return nil if !own_party || !foe_party
    own_side = own_index & 1
    own_seats = [own_side, own_side + 2]
    foe_seats = [own_side ^ 1, (own_side ^ 1) + 2]
    own = matrix_side(battle, own_party, own_seats)
    foe = matrix_side(battle, foe_party, foe_seats)

    field_sig = matrix_field_signature(battle, skill)
    own_sig = own.map { |entry| matrix_mon_signature(battle, own_party, entry) }
    foe_sig = foe.map { |entry| matrix_mon_signature(battle, foe_party, entry) }
    cached = battle.instance_variable_get(:@portable_ai_matrix)
    reuse = {}
    if cached && cached["field_sig"] == field_sig
      # A cell survives only if BOTH its bodies are unchanged. A field change (weather,
      # Trick Room, a screen going up) moves every number, so it drops the lot.
      old_own = cached["own_sig"] || []
      old_foe = cached["foe_sig"] || []
      (cached["cells"] || {}).each do |key, cell|
        o, f = key.split(":")
        o = o.to_i
        f = f.to_i
        next if own_sig[o].nil? || old_own[o] != own_sig[o]
        next if foe_sig[f].nil? || old_foe[f] != foe_sig[f]
        reuse[key] = cell
      end
    end

    live_own = matrix_live_slots(own)
    live_foe = matrix_live_slots(foe)
    cells = {}
    pending = []
    need_own = {}
    need_foe = {}
    live_own.each do |o|
      live_foe.each do |f|
        key = "#{o}:#{f}"
        if reuse.key?(key)
          cells[key] = reuse[key]
          next
        end
        pending << [o, f]
        need_own[o] = true
        need_foe[f] = true
      end
    end

    if !pending.empty?
      trick_room = trick_room_active?(battle)
      search_axis = rule_enabled?("search_planner")
      own_fake_seat = own_index
      foe_fake_seat = (foe_indices || []).first || (own_side ^ 1)
      # ONE save/restore for every body built below, rather than one per fake.
      preserving_board(battle) do
        bodies_own = matrix_bodies(battle, own_party, own, need_own.keys, own_fake_seat)
        bodies_foe = matrix_bodies(battle, foe_party, foe, need_foe.keys, foe_fake_seat)
        pending.each do |pair|
          attacker = bodies_own[pair[0]]
          defender = bodies_foe[pair[1]]
          next if !attacker || !defender
          out = matrix_cell(battle, attacker, defender, skill)
          incoming = matrix_cell(battle, defender, attacker, skill)
          cells["#{pair[0]}:#{pair[1]}"] = {
            "out" => out && out["pct"], "out_cat" => out && out["cat"],
            "out_move" => out && out["move"],
            "out_moves" => out && out["moves"],
            "in" => incoming && incoming["pct"], "in_cat" => incoming && incoming["cat"],
            "in_move" => incoming && incoming["move"],
            # 0.7.7. THE BUILD FOLLOWS ITS READERS, as matrix_wanted? does one level
            # up: the only thing that reads this is the search planner's foe move
            # axis (search.rb foe_moves), and the search ships off. Carrying it
            # unconditionally cost every shipped decision the allocation and every
            # traced run 28% of its file size (9.7 MB -> 12.4 MB on a 60-battle
            # control) for a field nothing in that run would open. The rolls
            # themselves are made either way -- this only decides whether they are
            # kept.
            "in_moves" => (search_axis ? (incoming && incoming["moves"]) : nil),
            "faster" => matrix_faster(own[pair[0]], foe[pair[1]], trick_room)
          }
        end
      end
    end

    battle.instance_variable_set(:@portable_ai_matrix,
                                { "field_sig" => field_sig, "own_sig" => own_sig,
                                  "foe_sig" => foe_sig, "cells" => cells })
    { "version" => MATRIX_VERSION, "own" => own, "foe" => foe, "cells" => cells }
  rescue Exception
    nil
  end

  # One entry per party slot, nil for an empty or egg slot. Rebuilt every snapshot --
  # it is six field reads a side and it carries the HP the core's verdicts are
  # derived from, which is exactly the thing that must never be cached.
  def self.matrix_side(battle, party, seats)
    out = []
    party.each_with_index do |pokemon, slot|
      if !pokemon || (pokemon.isEgg? rescue false)
        out << nil
        next
      end
      seat = nil
      seats.each do |i|
        battler = battle.battlers[i] rescue nil
        next if !battler || battler.isFainted?
        seat = i if battler.pokemonIndex == slot
      end
      body = seat.nil? ? nil : battle.battlers[seat]
      hp = body ? percent(body.hp, body.totalhp) : percent(pokemon.hp, pokemon.totalhp)
      # A benched body's Speed is the bare party stat -- no stages, no Choice Scarf,
      # no Swift Swim -- which is the convention switch_candidate_faster already uses
      # and the same thing it means: a switch-in arrives at stage 0.
      speed = body ? battler_speed(body) : (pokemon.speed rescue nil)
      types = body ? [body.type1, body.type2] : [pokemon.type1, pokemon.type2]
      out << {
        "slot" => slot,
        "index" => seat,
        "species" => (body ? body.species : pokemon.species),
        "hp_pct" => hp,
        "alive" => hp > 0,
        "speed" => speed,
        "types" => types.map { |t| type_key(t) }.compact.uniq,
        # 0.7.9. What a projected end of turn needs to tick, and what a switch-in
        # pays to arrive: the search's residuals and its below-root hazard damage
        # read these, per body, on both sides.
        "status" => (body ? body.status : pokemon.status),
        "item" => (body ? item_key(body) : pokemon_item_key(pokemon)),
        "ability" => ability_key(body || pokemon),
        "entry_damage_pct" => entry_hazard_pct(battle, pokemon, body, seats[0] & 1)
      }
    end
    out
  end

  def self.matrix_live_slots(side)
    out = []
    side.each do |entry|
      out << entry["slot"] if entry && entry["alive"]
    end
    out
  end

  # The real battler for a body on the field -- its actual stages, its Mega form, the
  # item it is holding -- and a fake for one on the bench. The fake goes at the seat
  # its own side occupies, so pbOwnSide (080:797, index & 1) resolves the screens to
  # the right half of the field.
  def self.matrix_bodies(battle, party, side, slots, fake_seat)
    out = {}
    slots.each do |slot|
      entry = side[slot]
      next if !entry
      out[slot] =
        if entry["index"].nil?
          fake_battler_unguarded(battle, party[slot], slot, fake_seat)
        else
          battle.battlers[entry["index"]]
        end
    end
    out
  end

  # The best damaging hit one body has on another, as a percentage of the DEFENDER's
  # max HP -- the same unit as hp_pct and every other estimate here. nil when the
  # engine could not price the pair at all, which is a different fact from 0.0 ("it
  # has nothing that lands") and the core reads the two differently.
  #
  # pbRoughDamage divides by the defender's defence (085:3557) and a board that
  # produces a zero there raises; per-pair rescue keeps one bad pair from costing the
  # whole matrix.
  def self.matrix_cell(battle, attacker, defender, skill)
    best = nil
    moves = {}
    (attacker.moves || []).each do |move|
      next if !move || move.id == 0
      # Same PP rule as the 0.6.4 bench estimate, on BOTH sides: a move with nothing
      # left is not a hit that body has.
      next if move.respond_to?(:pp) && move.pp.to_i <= 0 && rule_enabled?("switch_estimate_pp")
      damaging = (move.pbIsDamaging? rescue false) ? true : false
      key = move_key(move.id)
      # 0.7.9. A status move is a move the search can play (theirs) or click (ours
      # below the root). It has no damage number, and it is never the cell's best.
      pct = damaging ? rough_damage_pct!(battle, move, attacker, defender, skill) : 0.0
      type = (move.pbType(move.type, attacker, defender) rescue move.type)
      cat = (move.pbIsPhysical?(type) rescue true) ? "physical" : "special"
      kind, stat, chance = move_effect(battle, move, attacker, defender)
      # Every damaging move it has, including the ones that do nothing to this body:
      # a 0 here is the answer "Earthquake does not touch their Flying-type", which
      # is exactly what the foe-switch column needs to hear.
      moves[key] = { "pct" => pct, "cat" => cat, "damaging" => damaging,
                     "acc" => rough_accuracy(battle, move, attacker, defender, skill),
                     "priority" => (effective_priority(move, attacker) rescue 0),
                     "effect" => [kind, stat, chance] }
      next if !damaging
      next if best && pct <= best["pct"]
      best = { "pct" => pct, "cat" => cat, "move" => key }
    end
    return { "pct" => 0.0, "cat" => nil, "move" => nil, "moves" => moves } if best.nil?
    best["moves"] = moves
    best
  rescue Exception
    nil
  end

  # Engine convention (faster_than_foes?): strictly greater is faster, a tie is not,
  # Trick Room inverts. nil when either side table has no Speed.
  def self.matrix_faster(own_entry, foe_entry, trick_room)
    mine = own_entry && own_entry["speed"]
    theirs = foe_entry && foe_entry["speed"]
    return nil if mine.nil? || theirs.nil?
    trick_room ? mine < theirs : mine > theirs
  end

  # What has to change before a row or a column is re-rolled.
  #
  # Deliberately NOT here: HP. Every cell is a percentage of a max HP that does not
  # move, and the core derives its hit counts from the side tables, which are rebuilt
  # every snapshot. The known approximation this buys: a move whose POWER depends on
  # current HP either way -- Super Fang, Endeavor, Flail, Water Spout -- keeps the
  # number it had when the signature last changed.
  #
  # `form` because a Mega changes stats and ability without changing species; `status`
  # because burn halves physical damage; the per-move PP flag because the estimate
  # skips a spent move; `seat` so a body that walks onto the field is re-rolled as a
  # real battler with real stages instead of keeping its bench numbers.
  def self.matrix_mon_signature(battle, party, entry)
    return nil if !entry
    pokemon = party[entry["slot"]]
    return nil if !pokemon
    seat = entry["index"]
    source = seat.nil? ? pokemon : (battle.battlers[seat] rescue pokemon)
    moves = []
    (source.moves || []).each do |move|
      next if !move
      id = (move.id rescue 0)
      next if id.nil? || id == 0
      moves << [id, (move.respond_to?(:pp) ? move.pp.to_i > 0 : true)]
    end
    stages = seat.nil? ? nil : (source.stages.clone rescue nil)
    [(source.species rescue nil), (source.form rescue 0), ability_key(source),
     item_key(source), (source.status rescue 0), entry["alive"], moves, stages, seat]
  rescue Exception
    nil
  end

  # Everything outside the two bodies that moves a damage number: the weather, the
  # speed order, and the screens on either side (pbRoughDamage reads Reflect and Light
  # Screen at highSkill, 085:3610). Skill because the estimate itself is skill-gated.
  def self.matrix_field_signature(battle, skill)
    [weather_name(battle), trick_room_active?(battle), skill,
     safe_side_effect(battle.sides[0], :Reflect, 0),
     safe_side_effect(battle.sides[0], :LightScreen, 0),
     safe_side_effect(battle.sides[1], :Reflect, 0),
     safe_side_effect(battle.sides[1], :LightScreen, 0)]
  rescue Exception
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
    return 0.0 if move_does_nothing?(move, attacker, target)
    move.pbTypeModifier(move.type, attacker, target).to_f / 8.0
  rescue
    1.0
  end

  # The two immunities pbTypeModifier does not carry, in one place, so every damage
  # estimate (rough_damage_pct!) and the effectiveness the core rejects on agree.
  def self.move_does_nothing?(move, attacker, target)
    absorbed_by_ability?(move, attacker, target) ||
      ground_into_airborne?(move, attacker, target)
  end

  # 0.6.6 (airborne_immunity). Ground into a body that is not on the ground. The
  # engine decides it in pbSuccessCheck (080_PokeBattle_Battler.rb:2710), AFTER the
  # type modifier, off isAirborne? (080:647): Flying type, Levitate, Air Balloon,
  # Magnet Rise, Telekinesis -- minus Iron Ball, Ingrain, Smack Down and Gravity. The
  # Flying half is in the chart already; the other four were invisible to every
  # estimate here, so Steelix clicked Earthquake into a Levitate Rotom twice in one
  # battle at +500 (gen5ru_a team3_vs_team4 104729 t4-5, stock scored it 0) and the
  # matrix priced the same cell as a kill. The engine's own exceptions: Ring Target on
  # the target, Smack Down / Thousand Arrows (0x11C), and Mold Breaker, which walks
  # through the Levitate clause only -- isAirborne?(true) is the engine's own spelling
  # of that.
  def self.ground_into_airborne?(move, attacker, target)
    return false if !rule_enabled?("airborne_immunity")
    ground = (PBTypes.const_get(:GROUND) rescue nil)
    return false if ground.nil?
    type = (move.pbType(move.type, attacker, target) rescue move.type)
    return false if type != ground
    return false if (move.function rescue nil) == 0x11C
    return false if (target.hasWorkingItem(:RINGTARGET) rescue false)
    mold = (attacker.hasMoldBreaker rescue false) ? true : false
    (target.isAirborne?(mold) rescue false) ? true : false
  rescue
    false
  end

  # The read-only half of pbTypeImmunityByAbility (082:318-402). Same two guards the
  # engine opens with: a move aimed at the user itself is exempt, and Mold Breaker
  # switches the whole check off.
  def self.absorbed_by_ability?(move, attacker, target)
    return false if attacker.index == target.index
    return false if (attacker.hasMoldBreaker rescue false)
    # Telepathy: an ally's damaging move never lands on the holder.
    if ability_key(target) == "TELEPATHY" && !target.pbIsOpposing?(attacker.index)
      return true
    end
    return true if ability_key(target) == "BULLETPROOF" && (move.isBombMove? rescue false)
    wanted = ABSORB_ABILITIES[ability_key(target)]
    return false if !wanted
    type = (move.pbType(move.type, attacker, target) rescue move.type)
    value = (PBTypes.const_get(wanted) rescue nil)
    !value.nil? && type == value
  rescue
    false
  end

  # Same base-damage preparation stock v16 does before it calls pbRoughDamage
  # (085_PokeBattle_AI.rb:2802-2810): basedamage 1 is the "variable power" sentinel and
  # scores as 60, and pbBetterBaseDamage resolves the ~30 function codes that compute
  # their own power (Seismic Toss, Super Fang, Night Shade, Gyro Ball, Grass Knot...).
  # Passing raw basedamage instead, as this adapter did through 0.1.0, priced every one
  # of those at its sentinel.
  def self.rough_damage_pct(battle, move, attacker, target, skill)
    rough_damage_pct!(battle, move, attacker, target, skill)
  rescue
    0.0
  end

  # The same estimate with the refusal left visible. Every caller through 0.6.4 wants
  # "0% when the engine cannot say", which is what the wrapper above gives them; the
  # matrix wants to tell "nothing lands" apart from "this pair could not be priced",
  # because a cell it prints as 0 is a claim about the board and a cell it prints as
  # nil is an admission. pbRoughDamage divides by the defender's defence (085:3557).
  def self.rough_damage_pct!(battle, move, attacker, target, skill)
    return 0.0 if !target || !move.pbIsDamaging? || move.basedamage <= 0
    # pbRoughDamage reads pbTypeModifier and nothing else about immunity, so an
    # absorbed or airborne-dodged move came back as a full hit here even though
    # type_effectiveness already called it 0 -- which is what the incoming estimates,
    # the bench estimates and the matrix all read. One answer for all of them.
    return 0.0 if move_does_nothing?(move, attacker, target)
    base = move.basedamage
    base = 60 if base == 1
    base = battle.pbBetterBaseDamage(move, attacker, target, skill, base) rescue base
    damage = battle.pbRoughDamage(move, attacker, target, skill, base)
    percent(damage, target.totalhp)
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

  def self.entry_hazard_pct(battle, pokemon, battler, side_index = 1)
    side = battle.sides[side_index]
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

  # 0.8.0. FOUL PLAY, THE REAL ONE, PLAYING INSIDE THIS ENGINE.
  #
  # Eight versions of search (0.7.0-0.7.9) bought parity with the rule engine and
  # never a lead, and the last of them showed why nothing could be concluded from
  # that: the search's board is an approximation of this engine, so a loss can be the
  # board's fault and a win can be the board's luck. This module removes the
  # approximation from one side of the comparison. Every voluntary decision is
  # serialised as a poke-engine State -- both full parties, raw stats, boosts, side
  # conditions, volatiles, weather -- written to Data/, and a Python sidecar
  # (tools/foul_play_sidecar.py, running pmariglia's poke-engine package built for
  # gen 6) runs its Monte Carlo search on it and writes the most-visited choice back.
  # The choice is mapped onto one of the actions the snapshot already built for this
  # actor, so the trace, the memory and the registration paths are the ones every
  # other planner uses.
  #
  # The bargain: poke-engine's instruction generator and evaluation are the real
  # thing, not our port, and it plays against the real Realidea engine, so its wins
  # are real wins -- but it plans on Showdown gen 6 mechanics, and where this engine
  # differs (it is Essentials v16 with a gen 7 dex) it plans on the wrong rules. The
  # sidecar's --check mode measures that gap directly, by pricing the on-field pair's
  # moves in poke-engine and comparing them with the cells the matrix already carries.
  #
  # Handoff is by file because the harness is headless and this is Ruby 1.8 with no
  # sockets worth trusting on Windows: state out, reply in, each written to a temp
  # name and renamed so neither side ever reads a half-written file. A silent sidecar
  # costs one timeout and the turn falls through to the rule engine, which is logged;
  # a set with a dead sidecar is therefore a rules set with a slow first turn, not a
  # crash, and the log says so.
  #
  # Declines, like the search planner: doubles, no foe on the field, no actions.
  # Forced replacements stay with the rule engine (pbDefaultChooseNewEnemy never
  # reaches plan_for).
  module FoulPlay
    STATE_FILE = "Data/ai_foulplay_state.json"
    REPLY_FILE = "Data/ai_foulplay_reply.txt"
    LOG_FILE   = "Data/ai_foulplay_log.txt"
    DEFAULT_ITERATIONS = 5000

    @timeout = 60.0
    class << self
      attr_accessor :timeout
    end

    # Battler effect -> poke-engine volatile name, with the test that means "on".
    # :positive is > 0, :set is >= 0 (effects that hold an index, -1 when off),
    # :flag is Ruby truth. Effects this engine lacks are skipped by safe_effect.
    VOLATILES = [
      [:Confusion,   "CONFUSION",        :positive],
      [:LeechSeed,   "LEECHSEED",        :set],
      [:Taunt,       "TAUNT",            :positive],
      [:Encore,      "ENCORE",           :positive],
      [:Yawn,        "YAWN",             :positive],
      [:Curse,       "CURSE",            :flag],
      [:Ingrain,     "INGRAIN",          :flag],
      [:AquaRing,    "AQUARING",         :flag],
      [:Attract,     "ATTRACT",          :set],
      [:Torment,     "TORMENT",          :flag],
      [:Nightmare,   "NIGHTMARE",        :flag],
      [:Embargo,     "EMBARGO",          :positive],
      [:HealBlock,   "HEALBLOCK",        :positive],
      [:MagnetRise,  "MAGNETRISE",       :positive],
      [:Telekinesis, "TELEKINESIS",      :positive],
      [:Disable,     "DISABLE",          :positive],
      [:FocusEnergy, "FOCUSENERGY",      :positive],
      [:Protect,     "PROTECT",          :flag],
      [:Roost,       "ROOST",            :flag],
      [:SmackDown,   "SMACKDOWN",        :flag],
      [:Foresight,   "FORESIGHT",        :flag],
      [:MiracleEye,  "MIRACLEEYE",       :flag],
      [:Imprison,    "IMPRISON",         :flag],
      [:Minimize,    "MINIMIZE",         :flag],
      [:DefenseCurl, "DEFENSECURL",      :flag],
      [:Charge,      "CHARGE",           :positive],
      [:Stockpile,   "STOCKPILE",        :positive],
      [:Endure,      "ENDURE",           :flag],
      [:HyperBeam,   "MUSTRECHARGE",     :positive],
      [:Truant,      "TRUANT",           :flag],
      [:Unburden,    "UNBURDEN",         :flag],
      [:FlashFire,   "FLASHFIRE",        :flag],
      [:Rage,        "RAGE",             :flag],
      [:Uproar,      "UPROAR",           :positive],
      [:Outrage,     "LOCKEDMOVE",       :positive],
      [:Bide,        "BIDE",             :positive],
      [:MeanLook,    "PARTIALLYTRAPPED", :set],
      [:MultiTurn,   "PARTIALLYTRAPPED", :positive],
      [:SlowStart,   "SLOWSTART",        :positive],
      [:GastroAcid,  "GASTROACID",       :flag],
      [:LaserFocus,  "LASERFOCUS",       :positive],
      [:Electrify,   "ELECTRIFY",        :flag],
      [:Powder,      "POWDER",           :flag],
      [:DestinyBond, "DESTINYBOND",      :flag],
      [:Grudge,      "GRUDGE",           :flag],
      [:Substitute,  "SUBSTITUTE",       :positive],
      [:TwoTurnAttack, "TWOTURN",        :positive]
    ]

    # Side effect -> poke-engine side condition. Layer counts and turn counters pass
    # through; the two booleans (Stealth Rock, Sticky Web) become 1.
    SIDE_CONDITIONS = [
      [:Reflect,      "reflect"],
      [:LightScreen,  "light_screen"],
      [:Spikes,       "spikes"],
      [:ToxicSpikes,  "toxic_spikes"],
      [:StealthRock,  "stealth_rock"],
      [:StickyWeb,    "sticky_web"],
      [:Tailwind,     "tailwind"],
      [:Safeguard,    "safeguard"],
      [:Mist,         "mist"],
      [:LuckyChant,   "lucky_chant"],
      [:CraftyShield, "crafty_shield"],
      [:MatBlock,     "mat_block"],
      [:QuickGuard,   "quick_guard"],
      [:WideGuard,    "wide_guard"]
    ]

    STATUS_NAMES = { 1 => "sleep", 2 => "poison", 3 => "burn", 4 => "paralyze", 5 => "freeze" }

    def self.plan(battle, snapshot, config)
      return nil if battle.doublebattle
      actor = (snapshot["actors"] || [])[0]
      return nil if !actor || !actor["actions"].is_a?(Array) || actor["actions"].empty?
      index = actor["index"]
      state = state_for(battle, index, snapshot)
      return nil if !state
      state["iterations"] = (config["foul_play_iterations"] || DEFAULT_ITERATIONS).to_i
      state["iterations"] = DEFAULT_ITERATIONS if state["iterations"] <= 0
      reply = exchange(state)
      if !reply
        # A sidecar that was not running does not start mid-battle, and the wait is
        # long enough to be felt: without this, one silent turn in a PLAYED battle
        # becomes a silent turn every turn, each costing the full timeout before the
        # rules answer. Give up for this battle only, so the next one asks again. An
        # error reply is not silence and does not disable anything -- poke-engine
        # panics on particular positions, not on the whole battle.
        battle.instance_variable_set(:@portable_ai_foul_play_off, true)
        return nil
      end
      if reply["type"] == "error"
        log("turn=#{battle.turncount} actor=#{index} sidecar error: #{reply['message']}; rules took the turn")
        return nil
      end
      action = action_for(battle, index, actor, reply)
      if !action
        log("turn=#{battle.turncount} actor=#{index} unmapped reply #{reply['type']}=#{reply['slot']}")
        return nil
      end
      ranked = rankings(actor, reply)
      {
        "actions" => [action],
        "memory_updates" => PortableAI::Effects.memory_updates([action]),
        "diagnostics" => {
          "version" => PortableAI::VERSION,
          "planner" => "foul_play",
          "iterations" => reply["iterations"].to_i,
          "foe_options" => (reply["foe"] || []).map { |pair| pair[0] },
          "foe_visits" => (reply["foe"] || []).map { |pair| pair[1].to_i },
          "rankings" => [ranked]
        }
      }
    rescue Exception => error
      log("turn=#{battle.turncount rescue '?'} #{error.class}: #{error.message}")
      nil
    end

    # ---- the state -------------------------------------------------------------

    def self.state_for(battle, index, snapshot)
      own = battle.battlers[index]
      foe = battle.battlers[index ^ 1]
      return nil if !own || !foe || own.isFainted? || foe.isFainted?
      {
        "version" => 1,
        "turn" => battle.turncount,
        "actor" => index,
        "weather" => weather(battle),
        "weather_turns" => (battle.weatherduration.to_i rescue 0),
        "trick_room" => PortableAIRealidea.trick_room_active?(battle),
        "trick_room_turns" => PortableAIRealidea.safe_field_effect(battle, :TrickRoom, 0).to_i,
        "terrain" => terrain(battle),
        "side_one" => side_for(battle, own, battle.pbParty(index), index),
        "side_two" => side_for(battle, foe, battle.pbOpposingParty(index), index ^ 1),
        "cells" => cells_for(snapshot)
      }
    end

    def self.weather(battle)
      weather = (battle.pbWeather rescue battle.weather)
      [["SUNNYDAY", "sun"], ["RAINDANCE", "rain"], ["SANDSTORM", "sand"], ["HAIL", "hail"],
       ["HARSHSUN", "harshsun"], ["HEAVYRAIN", "heavyrain"]].each do |name, key|
        return key if PBWeather.const_defined?(name) && weather == PBWeather.const_get(name)
      end
      "none"
    end

    def self.terrain(battle)
      [[:ElectricTerrain, "electricterrain"], [:GrassyTerrain, "grassyterrain"],
       [:MistyTerrain, "mistyterrain"], [:PsychicTerrain, "psychicterrain"]].each do |name, key|
        return [key, PortableAIRealidea.safe_field_effect(battle, name, 0).to_i] if
          PortableAIRealidea.safe_field_effect(battle, name, 0).to_i > 0
      end
      ["none", 0]
    end

    def self.side_for(battle, active, party, index)
      side = battle.sides[index & 1]
      conditions = {}
      SIDE_CONDITIONS.each do |name, key|
        value = PortableAIRealidea.safe_side_effect(side, name, 0)
        conditions[key] = (value == true) ? 1 : ((value == false || value.nil?) ? 0 : value.to_i)
      end
      volatiles = []
      VOLATILES.each do |name, key, test|
        value = PortableAIRealidea.safe_effect(active, name, nil)
        next if value.nil?
        on = case test
             when :positive then value.is_a?(Numeric) && value > 0
             when :set      then value.is_a?(Numeric) && value >= 0
             else value ? true : false
             end
        volatiles << key if on && !volatiles.include?(key)
      end
      stages = active.stages || []
      pokemon = []
      party.each_with_index do |member, slot|
        next if !member || (member.isEgg? rescue false)
        body = (active.pokemonIndex == slot) ? active : nil
        pokemon << pokemon_for(battle, member, body, index)
      end
      {
        "active" => active.pokemonIndex,
        "boosts" => {
          "attack" => stages[PBStats::ATTACK].to_i, "defense" => stages[PBStats::DEFENSE].to_i,
          "special_attack" => stages[PBStats::SPATK].to_i, "special_defense" => stages[PBStats::SPDEF].to_i,
          "speed" => stages[PBStats::SPEED].to_i, "accuracy" => stages[PBStats::ACCURACY].to_i,
          "evasion" => stages[PBStats::EVASION].to_i
        },
        "conditions" => conditions,
        "toxic_count" => PortableAIRealidea.safe_effect(active, :Toxic, 0).to_i,
        "wish" => [PortableAIRealidea.safe_effect(active, :Wish, 0).to_i,
                   PortableAIRealidea.safe_effect(active, :WishAmount, 0).to_i],
        "volatiles" => volatiles,
        "durations" => {
          "confusion" => PortableAIRealidea.safe_effect(active, :Confusion, 0).to_i,
          "encore" => PortableAIRealidea.safe_effect(active, :Encore, 0).to_i,
          "taunt" => PortableAIRealidea.safe_effect(active, :Taunt, 0).to_i,
          "yawn" => PortableAIRealidea.safe_effect(active, :Yawn, 0).to_i,
          "lockedmove" => PortableAIRealidea.safe_effect(active, :Outrage, 0).to_i,
          "slowstart" => PortableAIRealidea.safe_effect(active, :SlowStart, 0).to_i
        },
        "substitute_health" => PortableAIRealidea.safe_effect(active, :Substitute, 0).to_i,
        "trapped" => trapped?(battle, index),
        "last_used_move" => last_used_move(active),
        "pokemon" => pokemon
      }
    end

    # Only trapping counts here -- an empty bench is something poke-engine sees for
    # itself from the party. pbCanSwitch? with no destination asks exactly that.
    def self.trapped?(battle, index)
      !(battle.pbCanSwitch?(index, -1, false) rescue true)
    rescue
      false
    end

    # The Choice lock is the fact that matters: poke-engine reads last_used_move for
    # Encore and the disabled flags for everything else, and the disabled flags come
    # from pbCanChooseMove? (which already knows about the lock, Disable, Taunt and
    # Torment), so the lock is safe to report through both.
    def self.last_used_move(active)
      locked = PortableAIRealidea.safe_effect(active, :ChoiceBand, -1)
      id = (locked.is_a?(Numeric) && locked > 0) ? locked : (active.lastMoveUsed rescue 0)
      return "move:none" if !id || id.to_i <= 0
      (active.moves || []).each_with_index do |move, slot|
        return "move:#{slot}" if move && move.id == id
      end
      "move:none"
    end

    def self.pokemon_for(battle, member, body, index)
      source = body || member
      types = [(source.type1 rescue nil), (source.type2 rescue nil)]
      types = types.map { |t| PortableAIRealidea.type_key(t) }.compact.uniq
      types << "TYPELESS" while types.length < 2
      evs = (member.ev rescue nil) || [0, 0, 0, 0, 0, 0]
      moves = []
      (source.moves || []).each_with_index do |move, slot|
        next if !move || move.id == 0
        entry = {
          "id" => PortableAIRealidea.move_key(move.id),
          "pp" => (move.pp.to_i rescue 0),
          "disabled" => (body ? !(battle.pbCanChooseMove?(index, slot, false) rescue true) : false)
        }
        if entry["id"] == "HIDDENPOWER"
          hp = (pbHiddenPower(member.iv) rescue nil)
          if hp
            entry["hp_type"] = PortableAIRealidea.type_key(hp[0])
            entry["hp_power"] = hp[1].to_i
          end
        end
        moves << entry
      end
      {
        "species" => PortableAIRealidea.constant_key(PBSpecies, :@species_keys, source.species),
        "form" => (source.form.to_i rescue 0),
        "mega" => ((member.isMega? rescue false) ? true : false),
        "level" => (source.level.to_i rescue 100),
        "types" => types,
        "hp" => source.hp.to_i,
        "maxhp" => source.totalhp.to_i,
        # Raw stats, stages excluded: poke-engine applies the boosts it is handed.
        "attack" => (source.attack.to_i rescue 0), "defense" => (source.defense.to_i rescue 0),
        "special_attack" => (source.spatk.to_i rescue 0),
        "special_defense" => (source.spdef.to_i rescue 0),
        "speed" => (source.speed.to_i rescue 0),
        "ability" => PortableAIRealidea.ability_key(source),
        "item" => (body ? PortableAIRealidea.item_key(body) : PortableAIRealidea.pokemon_item_key(member)),
        "nature" => (defined?(PBNatures) ?
                     PortableAIRealidea.constant_key(PBNatures, :@nature_keys, (member.nature rescue 0)) : nil),
        # PBStats order is HP, ATK, DEF, SPE, SPA, SPD; poke-engine's is hp, atk, def, spa, spd, spe.
        "evs" => [evs[0], evs[1], evs[2], evs[4], evs[5], evs[3]].map { |v| v.to_i },
        "status" => (STATUS_NAMES[source.status.to_i] || "none"),
        "status_count" => (source.statusCount.to_i rescue 0),
        "weight_kg" => ((member.weight rescue 0).to_f / 10.0),
        "moves" => moves
      }
    end

    # The on-field pair's cells, for the sidecar's damage check: this engine's own
    # max-roll price of every move both ways, keyed by move id.
    def self.cells_for(snapshot)
      matrix = snapshot["matrix"]
      return nil if !matrix.is_a?(Hash)
      own_slot = foe_slot = nil
      (matrix["own"] || []).each { |e| own_slot = e["slot"] if e && !e["index"].nil? }
      (matrix["foe"] || []).each { |e| foe_slot = e["slot"] if e && !e["index"].nil? }
      return nil if own_slot.nil? || foe_slot.nil?
      cell = (matrix["cells"] || {})["#{own_slot}:#{foe_slot}"]
      return nil if !cell
      { "out_moves" => cell["out_moves"], "in_moves" => cell["in_moves"] }
    end

    # ---- the handoff -----------------------------------------------------------

    def self.exchange(state)
      retrying { File.delete(REPLY_FILE) } if File.exist?(REPLY_FILE)
      retrying { File.delete(STATE_FILE) } if File.exist?(STATE_FILE)
      tmp = STATE_FILE + ".tmp"
      File.open(tmp, "wb") { |file| file.write(json(state)) }
      retrying { File.rename(tmp, STATE_FILE) }
      deadline = Time.now + @timeout
      while Time.now < deadline
        if File.exist?(REPLY_FILE)
          text = retrying { File.open(REPLY_FILE, "rb") { |file| file.read } }
          (retrying { File.delete(REPLY_FILE) }) rescue nil
          return parse_reply(text)
        end
        sleep 0.004
      end
      File.delete(STATE_FILE) rescue nil
      log("turn=#{state['turn']} actor=#{state['actor']} sidecar silent for #{@timeout}s; rules took the turn")
      nil
    end

    # Windows refuses to open or delete a file another process still has open, and the
    # sidecar's rename of the reply can land in the same instant we look at it: EACCES
    # here means "again in a moment", not failure. Two turns of the first thousand hit
    # it and fell to the rules before this existed.
    def self.retrying(tries = 100)
      attempt = 0
      begin
        yield
      rescue Errno::EACCES, Errno::EBUSY
        attempt += 1
        raise if attempt >= tries
        sleep 0.004
        retry
      end
    end

    # key=value per line. `own` and `foe` are label:visits pairs joined by commas.
    def self.parse_reply(text)
      reply = {}
      text.to_s.split(/[\r\n]+/).each do |line|
        key, value = line.split("=", 2)
        next if !key || value.nil?
        reply[key.strip] = value.strip
      end
      ["own", "foe"].each do |key|
        pairs = []
        reply[key].to_s.split(",").each do |part|
          # Labels carry a colon themselves (move:0), so the count is after the LAST one.
          cut = part.rindex(":")
          next if cut.nil? || cut == 0
          pairs << [part[0, cut], part[(cut + 1)..-1].to_i]
        end
        reply[key] = pairs
      end
      reply
    end

    def self.action_for(battle, index, actor, reply)
      slot = reply["slot"].to_i
      kind = reply["type"]
      chosen = nil
      actor["actions"].each do |action|
        next if action["type"] != kind || action["slot"] != slot
        next if kind == "move" && !action["target"].nil? && battle.doublebattle
        chosen = action
        break
      end
      return nil if !chosen
      out = PortableAI::Model.copy_hash(chosen)
      out["score"] = reply["score"].to_f
      out["search_visits"] = reply["visits"].to_i
      out["reasons"] = [["foul_play_visits", reply["visits"].to_i],
                        ["foul_play_avg", reply["score"].to_f],
                        ["foul_play_iterations", reply["iterations"].to_i]]
      out
    end

    # Every own action with the visits the sidecar reported for it, best first, so
    # the trace's candidates block reads the same as the search planner's.
    def self.rankings(actor, reply)
      visits = {}
      (reply["own"] || []).each { |label, count| visits[label] = count }
      ranked = actor["actions"].map do |action|
        scored = PortableAI::Model.copy_hash(action)
        scored["search_visits"] = visits[reply_label(action)].to_i
        scored["score"] = scored["search_visits"].to_f
        scored["reasons"] = [["foul_play_visits", scored["search_visits"]]]
        scored
      end
      ranked.sort { |a, b| b["search_visits"] <=> a["search_visits"] }
    end

    def self.reply_label(action)
      action["type"] == "switch" ? "switch:#{action['slot']}" : "move:#{action['slot']}"
    end

    # ---- plumbing --------------------------------------------------------------

    def self.log(line)
      File.open(LOG_FILE, "ab") { |file| file.write(line + "\n") }
    rescue
    end

    def self.json(value)
      case value
      when Hash
        "{" + value.map { |k, v| json_string(k.to_s) + ":" + json(v) }.join(",") + "}"
      when Array then "[" + value.map { |v| json(v) }.join(",") + "]"
      when String then json_string(value)
      when Symbol then json_string(value.to_s)
      when nil then "null"
      when true then "true"
      when false then "false"
      when Float
        (value.nan? || value.infinite?) ? "null" : value.to_s
      when Numeric then value.to_s
      else json_string(value.to_s)
      end
    end

    def self.json_string(text)
      out = text.gsub(/\\/, "\\\\\\\\").gsub(/"/, "\\\\\"")
      out = out.gsub(/\n/, "\\n").gsub(/\r/, "\\r").gsub(/\t/, "\\t")
      "\"" + out + "\""
    end
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
    # string "false" is truthy. Same twenty-eight keys as the Reborn gauntlet
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
      ["yawn_gate",          :boolean],
      # 0.6.3. All three false is 0.6.2, which is the control run.
      ["race_switch_to_winner", :boolean],
      ["heal_outpace",          :boolean],
      ["escape_needs_hitter", :boolean],
      # 0.6.4. All three false is 0.6.3, which is the control run.
      ["switchin_race_grade",  :boolean],
      ["escape_wall_margin",   :boolean],
      ["switch_estimate_pp",   :boolean],
      # 0.6.5. All three false is 0.6.4, which is the control run -- and so is
      # party_matrix on with the other two off, because building the grid decides
      # nothing by itself.
      ["party_matrix",         :boolean],
      ["sole_answer",          :boolean],
      ["setup_matrix",         :boolean],
      # 0.6.6. Both false is 0.6.5, which is the control run. foe_oracle is the
      # experiment arm and is never on by default.
      ["airborne_immunity",    :boolean],
      ["foe_oracle",           :boolean],
      ["no_hit_needs_threat",  :boolean],
      # 0.6.7. False is 0.6.6, which is the control run.
      ["dead_before_moving",   :boolean],
      # 0.7.0. Which planner runs. False is 0.6.7, which is the control run.
      ["search_planner",       :boolean],
      ["search_depth",         :float],
      ["search_foe_mix",       :float],
      ["search_foe_prior",     :boolean],
      ["foe_stock_model",      :boolean],
      # 0.7.6. Which search runs under search_planner. False is 0.7.5's maximin.
      ["search_mcts",          :boolean],
      ["search_iterations",    :float],
      ["search_seed",          :float],
      # 0.8.0. The Foul Play bridge (FoulPlay module). False is 0.7.9, which is the
      # control run; search_planner and foul_play are never on together.
      ["foul_play",            :boolean],
      ["foul_play_iterations", :float]
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

    # list's string counterpart. Kept separate rather than adding a flag to list,
    # because every existing caller wants integers and a mode name silently coerced by
    # to_i would become 0 rather than raise.
    def self.names(cfg, key, fallback)
      return fallback if !cfg[key] || cfg[key] == ""
      out = []
      cfg[key].to_s.split(",").each do |part|
        part = part.strip
        out << part if part != ""
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

    # The same overrides, for a battle nobody wrapped in with_config -- a player
    # fighting a trainer. Read once per session, so an edit mid-session cannot apply to
    # half a battle, and gated on the MARKER FILE rather than on requested?: the
    # gauntlet and the probe run with Data/portable_ai.txt absent and set
    # $PORTABLE_AI_ENABLED themselves, so every measured run still takes its config
    # solely from with_config and is unaffected by this path.
    def self.live_overrides
      return {} if !File.exist?(ENABLE_FILE)
      @live_overrides = config_overrides_from(config) if !defined?(@live_overrides) || !@live_overrides
      @live_overrides
    rescue
      {}
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
  if !method_defined?(:portable_ai_stock_pbAIRandom)
    alias portable_ai_stock_pbAIRandom pbAIRandom
  end
  if !method_defined?(:portable_ai_stock_pbDefaultChooseNewEnemy)
    alias portable_ai_stock_pbDefaultChooseNewEnemy pbDefaultChooseNewEnemy
  end

  # The faint replacement (see PortableAIRealidea.choose_replacement). enabled_for? is
  # true in the shadow arm too -- that is how the observer finds its seat -- and the
  # shadow arm registers nothing, so it is excluded here by name: its replacements stay
  # the stock chooser's, or the observed battle would stop being the stock battle.
  def pbDefaultChooseNewEnemy(index, party)
    if PortableAIRealidea.replacement? && !PortableAIRealidea.shadow? &&
       PortableAIRealidea.enabled_for?(self, index)
      slot = PortableAIRealidea.choose_replacement(self, index, party)
      return slot if slot
    end
    portable_ai_stock_pbDefaultChooseNewEnemy(index, party)
  end

  # The single point every AI roll passes through, engine and planner alike. While a
  # shadow observation is in progress it is redirected to that observation's private
  # generator, so watching a battle cannot change it. Outside an observation -- which is
  # every live arm and all of normal play -- this is the engine's own method.
  def pbAIRandom(limit)
    observer = @portable_ai_observer_rng
    return observer.rand(limit) if observer
    portable_ai_stock_pbAIRandom(limit)
  end

  def portable_ai_last_plan
    @portable_ai_last_plan
  end

  # The snapshot that plan was built from, so the probe can put the grid the rules
  # read on the record of a card they decided.
  def portable_ai_last_snapshot
    @portable_ai_last_snapshot
  end

  # Observe, let the host choose, then read back what it chose. Shared by both command
  # hooks so the paired entry is written the same way on either path.
  def portable_ai_shadowed(index)
    watching = PortableAIRealidea.enabled_for?(self, index) && pbCanShowCommands?(index)
    PortableAIRealidea.observe(self, index) if watching
    result = yield
    if watching
      PortableAIRealidea.record_host_choice(self, index)
    else
      PortableAIRealidea.stash_foe_choice(self, index)
    end
    result
  end

  def pbChooseMoves(index)
    if PortableAIRealidea.shadow?
      return portable_ai_shadowed(index) { portable_ai_stock_pbChooseMoves(index) }
    end
    if PortableAIRealidea.enabled_for?(self, index)
      return if PortableAIRealidea.choose(self, index)
    end
    portable_ai_stock_pbChooseMoves(index)
  end

  def pbDefaultChooseEnemyCommand(index)
    # Shadow observes and then hands the turn to the host untouched. It skips the block
    # below deliberately rather than falling through it: those pre-steps use an item,
    # auto-pick a move and register a mega evolution, and the host method runs all three
    # again, so a fall-through would perform each of them twice.
    if PortableAIRealidea.shadow?
      return portable_ai_shadowed(index) {
        portable_ai_stock_pbDefaultChooseEnemyCommand(index)
      }
    end
    if PortableAIRealidea.enabled_for?(self, index) && pbCanShowCommands?(index)
      return if pbEnemyShouldUseItem?(index)
      if pbCanShowFightMenu?(index)
        return if pbAutoFightMenu(index)
        pbRegisterMegaEvolution(index) if pbEnemyShouldMegaEvolve?(index)
      end
      return if PortableAIRealidea.choose(self, index)
    end
    result = portable_ai_stock_pbDefaultChooseEnemyCommand(index)
    # The far side of the board, for the live arm's trace. Only seats the portable AI
    # does not drive: its own are already in the entry.
    if !PortableAIRealidea.enabled_for?(self, index)
      PortableAIRealidea.stash_foe_choice(self, index)
    end
    result
  end
end
