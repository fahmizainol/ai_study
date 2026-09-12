# Battle_Gimmicks — trainer-selectable battle rules for Realidea (Essentials v16).
#
# The built-in default deliberately starts every trainer battle in permanent Sun
# for playtesting. Wild battles are untouched. Data/battle_gimmicks.txt can change
# the default and add overrides keyed by the opponent's trainer type ID and name.
# See adapters/realidea/battle_gimmicks.example.txt for the file format.

module RealideaBattleGimmicks
  CONFIG_FILE = "Data/battle_gimmicks.txt"
  PERMANENT_TERRAIN_TURNS = 999

  DEFAULT = {
    "enabled"             => true,
    "weather"             => "sun",
    "weather_permanent"   => true,
    "weather_turns"       => 5,
    "terrain"             => "none",
    "terrain_permanent"   => true,
    "terrain_turns"       => 5,
    "trick_room"          => "0",
    "speed"               => "normal",
    "announce"            => true
  }

  WEATHER_NAMES = {
    "sun"  => :SUNNYDAY,
    "rain" => :RAINDANCE,
    "sand" => :SANDSTORM,
    "hail" => :HAIL
  }
  WEATHER_ANIMATIONS = {
    "sun" => "Sunny", "rain" => "Rain",
    "sand" => "Sandstorm", "hail" => "Hail"
  }
  WEATHER_LABELS = {
    "sun" => "sunlight", "rain" => "rain",
    "sand" => "a sandstorm", "hail" => "hail"
  }
  TERRAIN_NAMES = {
    "electric" => :ElectricTerrain,
    "grassy"   => :GrassyTerrain,
    "misty"    => :MistyTerrain,
    "psychic"  => :PsychicTerrain
  }
  TERRAIN_MOVES = {
    "electric" => :ELECTRICTERRAIN,
    "grassy"   => :GRASSYTERRAIN,
    "misty"    => :MISTYTERRAIN,
    "psychic"  => :PSYCHICTERRAIN
  }
  TERRAIN_LABELS = {
    "electric" => "Electric Terrain",
    "grassy"   => "Grassy Terrain",
    "misty"    => "Misty Terrain",
    "psychic"  => "Psychic Terrain"
  }
  SURGE_TERRAINS = {
    :ELECTRICSURGE => "electric",
    :GRASSYSURGE   => "grassy",
    :MISTYSURGE    => "misty",
    :PSYCHICSURGE  => "psychic"
  }

  def self.boolean(value, fallback)
    return value if value == true || value == false
    text = value.to_s.downcase
    return true if ["true", "yes", "on", "1"].include?(text)
    return false if ["false", "no", "off", "0"].include?(text)
    return fallback
  end

  def self.coerce(key, value)
    return boolean(value, DEFAULT[key]) if ["enabled", "weather_permanent",
      "terrain_permanent", "announce"].include?(key)
    return value.to_i if ["weather_turns", "terrain_turns"].include?(key)
    return value.to_s.downcase
  end

  def self.read_pairs(parts)
    settings = {}
    for part in parts
      key, value = part.split("=", 2)
      next if !key || !value
      key = key.to_s.strip.downcase
      settings[key] = coerce(key, value.to_s.strip)
    end
    return settings
  end

  # CSV-like, intentionally simple enough for Ruby 1.8:
  # default,weather=sun,weather_permanent=true
  # trainer,33,Abi,weather=rain,terrain=grassy,trick_room=5,speed=lighter
  def self.config
    defaults = DEFAULT.dup
    trainers = {}
    if File.exist?(CONFIG_FILE)
      File.open(CONFIG_FILE, "rb") do |file|
        file.each_line do |raw|
          line = raw.to_s.strip
          next if line.empty? || line[0, 1] == "#"
          parts = line.split(",").map { |part| part.strip }
          kind = parts.shift.to_s.downcase
          if kind == "default"
            defaults.update(read_pairs(parts))
          elsif kind == "trainer" && parts.length >= 2
            type_id = parts.shift.to_i
            name = parts.shift.to_s
            trainers[[type_id, name]] = read_pairs(parts)
          end
        end
      end
    end
    return defaults, trainers
  rescue
    return DEFAULT.dup, {}
  end

  def self.settings_for(battle)
    opponent = (battle.opponent rescue nil)
    return nil if !opponent
    defaults, trainers = config
    settings = defaults.dup
    opponents = opponent.is_a?(Array) ? opponent : [opponent]
    for trainer in opponents
      key = [(trainer.trainertype rescue -1), (trainer.name rescue "").to_s]
      settings.update(trainers[key]) if trainers[key]
    end
    return nil if !boolean(settings["enabled"], true)
    return settings
  end

  def self.weather_id(name)
    constant = WEATHER_NAMES[name.to_s.downcase]
    return nil if !constant
    return getConst(PBWeather, constant) rescue nil
  end

  def self.terrain_effect(name)
    constant = TERRAIN_NAMES[name.to_s.downcase]
    return nil if !constant
    return getConst(PBEffects, constant) rescue nil
  end

  def self.clear_terrains(field)
    for name in TERRAIN_NAMES.keys
      effect = terrain_effect(name)
      field.effects[effect] = 0 if !effect.nil?
    end
  end

  def self.prepare(battle)
    return if battle.instance_variable_get(:@realidea_gimmick_prepared)
    battle.instance_variable_set(:@realidea_gimmick_prepared, true)
    settings = settings_for(battle)
    battle.instance_variable_set(:@realidea_battle_gimmick, settings)
    return if !settings

    weather_name = settings["weather"].to_s.downcase
    weather = weather_id(weather_name)
    if !weather.nil?
      battle.weather = weather
      if boolean(settings["weather_permanent"], true)
        battle.weatherduration = -1
      else
        battle.weatherduration = [settings["weather_turns"].to_i, 1].max
      end
    end

    terrain_name = settings["terrain"].to_s.downcase
    terrain = terrain_effect(terrain_name)
    if !terrain.nil?
      clear_terrains(battle.field)
      turns = boolean(settings["terrain_permanent"], true) ?
        PERMANENT_TERRAIN_TURNS : [settings["terrain_turns"].to_i, 1].max
      battle.field.effects[terrain] = turns
    end

    trick_room = settings["trick_room"].to_s.downcase
    if trick_room == "permanent"
      battle.field.effects[PBEffects::TrickRoom] = PERMANENT_TERRAIN_TURNS
    elsif trick_room.to_i > 0
      battle.field.effects[PBEffects::TrickRoom] = trick_room.to_i
    end
  end

  def self.animation_user(battle)
    battlers = (battle.battlers rescue [])
    for battler in battlers
      return battler if battler && !(battler.isFainted? rescue true)
    end
    return nil
  end

  def self.play_terrain_animation(battle, terrain_name)
    move = TERRAIN_MOVES[terrain_name]
    user = animation_user(battle)
    return if !move || !user
    move_id = getConst(PBMoves, move) rescue nil
    battle.pbAnimation(move_id, user, user) if move_id
  rescue
  end

  def self.activate_surge(battler, onactive)
    return if !onactive || (battler.isFainted? rescue true)
    terrain_name = nil
    ability_name = nil
    for ability, name in SURGE_TERRAINS
      if (battler.hasWorkingAbility(ability) rescue false)
        terrain_name = name
        ability_name = ability
        break
      end
    end
    return if !terrain_name || active_terrain_name(battler.instance_variable_get(:@battle)) == terrain_name
    battle = battler.instance_variable_get(:@battle)
    clear_terrains(battle.field)
    effect = terrain_effect(terrain_name)
    turns = (battler.hasWorkingItem(:TERRAINEXTENDER) rescue false) ? 8 : 5
    battle.field.effects[effect] = turns
    play_terrain_animation(battle, terrain_name)
    ability_label = (PBAbilities.getName(battler.ability) rescue ability_name.to_s)
    terrain_label = TERRAIN_LABELS[terrain_name] || terrain_name
    battle.pbDisplay(_INTL("{1}'s {2} created {3}!", battler.pbThis, ability_label, terrain_label))
  end

  def self.move_priority(move, user)
    priority = (move.priority rescue 0).to_i
    if !defined?(USENEWBATTLEMECHANICS) || USENEWBATTLEMECHANICS
      priority += 1 if (user.hasWorkingAbility(:PRANKSTER) rescue false) &&
        (move.pbIsStatus? rescue false)
      priority += 1 if (user.hasWorkingAbility(:GALEWINGS) rescue false) &&
        isConst?((move.type rescue -1), PBTypes, :FLYING)
      priority += 3 if (user.hasWorkingAbility(:TRIAGE) rescue false) &&
        (move.isHealingMove? rescue false)
    end
    return priority
  rescue
    return priority || 0
  end

  def self.psychic_priority_blocked?(move, user, target)
    return false if !move || !user || !target
    battle = user.instance_variable_get(:@battle)
    effect = terrain_effect("psychic")
    return false if !battle || !effect || battle.field.effects[effect].to_i <= 0
    return false if !(user.pbIsOpposing?(target.index) rescue false)
    return false if (target.isAirborne? rescue true)
    return move_priority(move, user) > 0
  rescue
    false
  end

  def self.announce_start(battle)
    settings = battle.instance_variable_get(:@realidea_battle_gimmick)
    return if !settings || !boolean(settings["announce"], true)
    weather_name = settings["weather"].to_s.downcase
    if weather_id(weather_name) && boolean(settings["weather_permanent"], true)
      label = WEATHER_LABELS[weather_name] || weather_name
      battle.pbDisplay(_INTL("The battlefield sustains {1}. Other weather can suppress it temporarily!", label))
    end
    terrain_name = settings["terrain"].to_s.downcase
    if terrain_effect(terrain_name)
      play_terrain_animation(battle, terrain_name)
      label = TERRAIN_LABELS[terrain_name] || terrain_name
      if boolean(settings["terrain_permanent"], true)
        battle.pbDisplay(_INTL("{1} permanently covers the battlefield!", label))
      else
        battle.pbDisplay(_INTL("{1} covers the battlefield!", label))
      end
    end
    trick_room = settings["trick_room"].to_s.downcase
    if trick_room == "permanent" || trick_room.to_i > 0
      user = animation_user(battle)
      move_id = getConst(PBMoves, :TRICKROOM) rescue nil
      battle.pbAnimation(move_id, user, user) if move_id && user
      battle.pbDisplay(_INTL("The dimensions twisted before the first turn!"))
    end
    case settings["speed"].to_s.downcase
    when "heavier"
      battle.pbDisplay(_INTL("Pokemon move according to weight. Heavier Pokemon are faster!"))
    when "lighter"
      battle.pbDisplay(_INTL("Pokemon move according to weight. Lighter Pokemon are faster!"))
    end
  end

  def self.active_terrain_name(battle)
    for name in TERRAIN_NAMES.keys
      effect = terrain_effect(name)
      return name if effect && battle.field.effects[effect].to_i > 0
    end
    return nil
  end

  def self.restore_weather(battle, settings)
    name = settings["weather"].to_s.downcase
    weather = weather_id(name)
    return if !weather || !boolean(settings["weather_permanent"], true)
    return if battle.weather.to_i != 0
    battle.weather = weather
    battle.weatherduration = -1
    animation = WEATHER_ANIMATIONS[name]
    battle.pbCommonAnimation(animation, nil, nil) if animation
    label = WEATHER_LABELS[name] || name
    battle.pbDisplay(_INTL("The battlefield restored {1}!", label))
  end

  def self.restore_terrain(battle, settings)
    name = settings["terrain"].to_s.downcase
    effect = terrain_effect(name)
    return if !effect || !boolean(settings["terrain_permanent"], true)
    active = active_terrain_name(battle)
    if active == name
      battle.field.effects[effect] = PERMANENT_TERRAIN_TURNS
      return
    end
    return if active
    clear_terrains(battle.field)
    battle.field.effects[effect] = PERMANENT_TERRAIN_TURNS
    play_terrain_animation(battle, name)
    label = TERRAIN_LABELS[name] || name
    battle.pbDisplay(_INTL("The battlefield restored {1}!", label))
  end

  # Realidea's Gen 6 terrain backport never decrements Psychic Terrain. Keep it
  # on the same clock as the other terrains so a temporary override can expire.
  def self.tick_psychic_terrain(battle, settings)
    effect = terrain_effect("psychic")
    return if !effect
    turns = battle.field.effects[effect].to_i
    return if turns <= 0
    permanent_base = settings["terrain"].to_s.downcase == "psychic" &&
      boolean(settings["terrain_permanent"], true)
    return if permanent_base && turns == PERMANENT_TERRAIN_TURNS
    battle.field.effects[effect] = turns - 1
    if battle.field.effects[effect] == 0
      battle.pbDisplay(_INTL("The strange atmosphere disappeared from the battlefield."))
    end
  end

  def self.restore_trick_room(battle, settings)
    return if settings["trick_room"].to_s.downcase != "permanent"
    battle.field.effects[PBEffects::TrickRoom] = PERMANENT_TERRAIN_TURNS
  end

  def self.after_round(battle)
    settings = battle.instance_variable_get(:@realidea_battle_gimmick)
    return if (battle.decision.to_i > 0 rescue false)
    # Psychic Terrain was added after this engine's shared terrain clock, so it
    # needs its own countdown even in wild battles with no gimmick config.
    tick_psychic_terrain(battle, settings || {})
    return if !settings
    restore_weather(battle, settings)
    restore_terrain(battle, settings)
    restore_trick_room(battle, settings)
  end

  def self.speed_for(battler, normal_speed)
    battle = battler.instance_variable_get(:@battle)
    electric = terrain_effect("electric")
    if electric && battle && battle.field.effects[electric].to_i > 0 &&
       (battler.hasWorkingAbility(:SURGESURFER) rescue false)
      normal_speed *= 2
    end
    settings = battle.instance_variable_get(:@realidea_battle_gimmick) rescue nil
    return normal_speed if !settings
    rule = settings["speed"].to_s.downcase
    weight = battler.weight.to_i rescue 1
    weight = 1 if weight < 1
    return weight if rule == "heavier"
    return [1_000_000 / weight, 1].max if rule == "lighter"
    return normal_speed
  end
end

if defined?(PokeBattle_Move)
  class PokeBattle_Move
    alias realidea_gimmicks_calc_damage pbCalcDamage
    def pbCalcDamage(attacker, opponent, options=0)
      damage = realidea_gimmicks_calc_damage(attacker, opponent, options)
      psychic = RealideaBattleGimmicks.terrain_effect("psychic")
      active = psychic && @battle.field.effects[psychic].to_i > 0
      move_type = (pbType(@type, attacker, opponent) rescue @type)
      if damage.to_i > 0 && active && !(attacker.isAirborne? rescue true) &&
         isConst?(move_type, PBTypes, :PSYCHIC)
        damage = (damage * 1.5).round
        opponent.damagestate.calcdamage = damage
      end
      return damage
    end
  end
end

# Electric/Grassy/Misty Terrain predate Psychic Terrain in this engine and do
# not clear it. Correct those three moves so exactly one terrain can be active.
if defined?(PokeBattle_Move_154)
  class PokeBattle_Move_154
    alias realidea_gimmicks_electric_terrain_effect pbEffect
    def pbEffect(*args)
      @battle.field.effects[PBEffects::PsychicTerrain] = 0
      return realidea_gimmicks_electric_terrain_effect(*args)
    end
  end
end

if defined?(PokeBattle_Move_155)
  class PokeBattle_Move_155
    alias realidea_gimmicks_grassy_terrain_effect pbEffect
    def pbEffect(*args)
      @battle.field.effects[PBEffects::PsychicTerrain] = 0
      return realidea_gimmicks_grassy_terrain_effect(*args)
    end
  end
end

if defined?(PokeBattle_Move_156)
  class PokeBattle_Move_156
    alias realidea_gimmicks_misty_terrain_effect pbEffect
    def pbEffect(*args)
      @battle.field.effects[PBEffects::PsychicTerrain] = 0
      return realidea_gimmicks_misty_terrain_effect(*args)
    end
  end
end

# A second move-function slot in Realidea also creates Misty Terrain.
if defined?(PokeBattle_Move_162)
  class PokeBattle_Move_162
    alias realidea_gimmicks_misty_terrain_162_effect pbEffect
    def pbEffect(*args)
      @battle.field.effects[PBEffects::PsychicTerrain] = 0
      return realidea_gimmicks_misty_terrain_162_effect(*args)
    end
  end
end

class PokeBattle_Battle
  alias realidea_gimmicks_start_battle_core pbStartBattleCore
  def pbStartBattleCore(canlose)
    RealideaBattleGimmicks.prepare(self)
    return realidea_gimmicks_start_battle_core(canlose)
  end

  alias realidea_gimmicks_on_active_all pbOnActiveAll
  def pbOnActiveAll
    result = realidea_gimmicks_on_active_all
    RealideaBattleGimmicks.announce_start(self)
    return result
  end

  alias realidea_gimmicks_end_of_round pbEndOfRoundPhase
  def pbEndOfRoundPhase
    result = realidea_gimmicks_end_of_round
    RealideaBattleGimmicks.after_round(self)
    return result
  end
end

class PokeBattle_Battler
  alias realidea_gimmicks_abilities_on_switch_in pbAbilitiesOnSwitchIn
  def pbAbilitiesOnSwitchIn(onactive)
    result = realidea_gimmicks_abilities_on_switch_in(onactive)
    RealideaBattleGimmicks.activate_surge(self, onactive)
    return result
  end

  alias realidea_gimmicks_success_check pbSuccessCheck
  def pbSuccessCheck(thismove, user, target, turneffects, accuracy=true)
    if RealideaBattleGimmicks.psychic_priority_blocked?(thismove, user, target)
      @battle.pbDisplay(_INTL("Psychic Terrain protected {1} from the priority move!", target.pbThis))
      return false
    end
    return realidea_gimmicks_success_check(thismove, user, target, turneffects, accuracy)
  end

  alias realidea_gimmicks_normal_speed pbSpeed
  def pbSpeed
    normal = realidea_gimmicks_normal_speed
    return RealideaBattleGimmicks.speed_for(self, normal)
  end
end
