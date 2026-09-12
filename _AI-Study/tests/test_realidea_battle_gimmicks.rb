require "test/unit"
require "tmpdir"

def getConst(mod, name)
  return mod.const_get(name)
end

def _INTL(text, *args)
  result = text.dup
  args.each_with_index { |arg, index| result.gsub!("{#{index + 1}}", arg.to_s) }
  return result
end

module PBWeather
  SUNNYDAY = 1
  RAINDANCE = 2
  SANDSTORM = 3
  HAIL = 4
end

module PBEffects
  ElectricTerrain = 0
  GrassyTerrain = 1
  MistyTerrain = 2
  PsychicTerrain = 3
  TrickRoom = 4
end

module PBMoves
  ELECTRICTERRAIN = 1
  GRASSYTERRAIN = 2
  MISTYTERRAIN = 3
  PSYCHICTERRAIN = 4
  TRICKROOM = 5
end

module PBAbilities
  def self.getName(id)
    return id.to_s
  end
end

module PBTypes
  FLYING = 1
end

USENEWBATTLEMECHANICS = true

FieldStub = Struct.new(:effects)
TrainerStub = Struct.new(:trainertype, :name)

class PokeBattle_Battle
  attr_accessor :weather, :weatherduration, :decision
  attr_reader :opponent, :field, :messages, :animations, :battlers

  def initialize(opponent=nil)
    @opponent = opponent
    @field = FieldStub.new(Array.new(8, 0))
    @weather = 0
    @weatherduration = 0
    @decision = 0
    @messages = []
    @animations = []
    @battlers = []
  end

  def pbStartBattleCore(canlose)
    return :started
  end

  def pbOnActiveAll
    return :active
  end

  def pbEndOfRoundPhase
    if @weatherduration > 0
      @weatherduration -= 1
      if @weatherduration == 0
        @weather = 0
      end
    end
    return :round_ended
  end

  def pbDisplay(message)
    @messages << message
  end

  def pbCommonAnimation(name, user, target)
    @animations << name
  end

  def pbAnimation(move, user, target)
    @animations << move
  end
end

class PokeBattle_Battler
  attr_accessor :index, :ability

  def initialize(battle, weight, ability=nil, item=nil, index=1)
    @battle = battle
    @test_weight = weight
    @ability = ability
    @test_item = item
    @index = index
  end

  def pbSpeed
    return 123
  end

  def weight
    return @test_weight
  end

  def pbAbilitiesOnSwitchIn(onactive)
    return :abilities_checked
  end

  def pbSuccessCheck(move, user, target, turneffects, accuracy=true)
    return true
  end

  def hasWorkingAbility(ability)
    return @ability == ability
  end

  def hasWorkingItem(item)
    return @test_item == item
  end

  def isFainted?
    return false
  end

  def isAirborne?
    return false
  end

  def pbIsOpposing?(other_index)
    return (@index & 1) != (other_index & 1)
  end

  def pbThis
    return "Testmon"
  end
end

class PokeBattle_Move_154
  def initialize(battle)
    @battle = battle
  end

  def pbEffect(*args)
    @battle.field.effects[PBEffects::ElectricTerrain] = 5
    return 0
  end
end

class PokeBattle_Move_162
  def initialize(battle)
    @battle = battle
  end

  def pbEffect(*args)
    @battle.field.effects[PBEffects::MistyTerrain] = 5
    return 0
  end
end

load File.expand_path("../adapters/realidea/Battle_Gimmicks.rb", __dir__)

class RealideaBattleGimmicksTest < Test::Unit::TestCase
  def in_empty_game
    Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, "Data"))
      Dir.chdir(directory) { yield directory }
    end
  end

  def write_config(directory, line)
    File.open(File.join(directory, "Data", "battle_gimmicks.txt"), "wb") do |file|
      file.write(line + "\n")
    end
  end

  def test_default_is_permanent_sun_in_trainer_battles
    in_empty_game do
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      assert_equal(:started, battle.pbStartBattleCore(false))
      assert_equal(PBWeather::SUNNYDAY, battle.weather)
      assert_equal(-1, battle.weatherduration)
      battle.pbOnActiveAll
      assert_match(/sustains sunlight/, battle.messages.last)
    end
  end

  def test_wild_battles_are_unchanged
    in_empty_game do
      battle = PokeBattle_Battle.new(nil)
      battle.pbStartBattleCore(false)
      assert_equal(0, battle.weather)
      assert_equal(0, battle.weatherduration)
    end
  end

  def test_temporary_weather_expires_then_restores_the_permanent_weather
    in_empty_game do
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      battle.pbStartBattleCore(false)
      battle.weather = PBWeather::RAINDANCE
      battle.weatherduration = 1
      battle.pbEndOfRoundPhase
      assert_equal(PBWeather::SUNNYDAY, battle.weather)
      assert_equal(-1, battle.weatherduration)
      assert_equal("Sunny", battle.animations.last)
      assert_match(/restored sunlight/, battle.messages.last)
    end
  end

  def test_trainer_override_can_select_terrain_trick_room_and_weight_speed
    in_empty_game do |directory|
      write_config(directory,
        "trainer,60,Aimi,weather=none,terrain=misty,trick_room=5,speed=heavier")
      battle = PokeBattle_Battle.new(TrainerStub.new(60, "Aimi"))
      battle.pbStartBattleCore(false)
      assert_equal(0, battle.weather)
      assert_equal(RealideaBattleGimmicks::PERMANENT_TERRAIN_TURNS,
        battle.field.effects[PBEffects::MistyTerrain])
      assert_equal(5, battle.field.effects[PBEffects::TrickRoom])
      assert_equal(750, PokeBattle_Battler.new(battle, 750).pbSpeed)
    end
  end

  def test_lighter_speed_rule_inverts_effective_weight
    in_empty_game do |directory|
      write_config(directory, "default,speed=lighter")
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      battle.pbStartBattleCore(false)
      light = PokeBattle_Battler.new(battle, 100).pbSpeed
      heavy = PokeBattle_Battler.new(battle, 1_000).pbSpeed
      assert_operator(light, :>, heavy)
    end
  end

  def test_psychic_terrain_expires_and_permanent_base_returns
    in_empty_game do |directory|
      write_config(directory, "default,weather=none,terrain=grassy")
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      battle.pbStartBattleCore(false)
      battle.field.effects[PBEffects::GrassyTerrain] = 0
      battle.field.effects[PBEffects::PsychicTerrain] = 1
      battle.pbEndOfRoundPhase
      assert_equal(0, battle.field.effects[PBEffects::PsychicTerrain])
      assert_equal(RealideaBattleGimmicks::PERMANENT_TERRAIN_TURNS,
        battle.field.effects[PBEffects::GrassyTerrain])
      assert_match(/restored Grassy Terrain/, battle.messages.last)
    end
  end

  def test_old_terrain_moves_clear_psychic_terrain
    in_empty_game do
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      battle.field.effects[PBEffects::PsychicTerrain] = 5
      PokeBattle_Move_154.new(battle).pbEffect
      assert_equal(0, battle.field.effects[PBEffects::PsychicTerrain])
      assert_equal(5, battle.field.effects[PBEffects::ElectricTerrain])
    end
  end

  def test_alternate_misty_terrain_move_clears_psychic_terrain
    in_empty_game do
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      battle.field.effects[PBEffects::PsychicTerrain] = 5
      PokeBattle_Move_162.new(battle).pbEffect
      assert_equal(0, battle.field.effects[PBEffects::PsychicTerrain])
      assert_equal(5, battle.field.effects[PBEffects::MistyTerrain])
    end
  end

  def test_psychic_terrain_expires_in_wild_battles
    in_empty_game do
      battle = PokeBattle_Battle.new(nil)
      battle.field.effects[PBEffects::PsychicTerrain] = 1
      battle.pbEndOfRoundPhase
      assert_equal(0, battle.field.effects[PBEffects::PsychicTerrain])
    end
  end


  def test_surges_activate_and_terrain_extender_sets_eight_turns
    in_empty_game do
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      battler = PokeBattle_Battler.new(battle, 100, :GRASSYSURGE, :TERRAINEXTENDER)
      assert_equal(:abilities_checked, battler.pbAbilitiesOnSwitchIn(true))
      assert_equal(8, battle.field.effects[PBEffects::GrassyTerrain])
      assert_match(/GRASSYSURGE created Grassy Terrain/, battle.messages.last)
    end
  end

  def test_each_surge_activates_its_matching_terrain
    in_empty_game do
      {
        :ELECTRICSURGE => PBEffects::ElectricTerrain,
        :GRASSYSURGE   => PBEffects::GrassyTerrain,
        :MISTYSURGE    => PBEffects::MistyTerrain,
        :PSYCHICSURGE  => PBEffects::PsychicTerrain
      }.each do |ability, effect|
        battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
        battler = PokeBattle_Battler.new(battle, 100, ability)
        battler.pbAbilitiesOnSwitchIn(true)
        assert_equal(5, battle.field.effects[effect], ability.to_s)
      end
    end
  end

  def test_psychic_terrain_blocks_grounded_opposing_priority
    in_empty_game do
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      battle.field.effects[PBEffects::PsychicTerrain] = 5
      user = PokeBattle_Battler.new(battle, 100, nil, nil, 1)
      target = PokeBattle_Battler.new(battle, 100, nil, nil, 0)
      move = Struct.new(:priority).new(1)
      assert_equal(false, user.pbSuccessCheck(move, user, target, {}, true))
      assert_match(/Psychic Terrain protected/, battle.messages.last)
    end
  end

  def test_surge_surfer_doubles_speed_on_electric_terrain
    in_empty_game do
      battle = PokeBattle_Battle.new(TrainerStub.new(33, "Abi"))
      battle.field.effects[PBEffects::ElectricTerrain] = 5
      battler = PokeBattle_Battler.new(battle, 100, :SURGESURFER)
      assert_equal(246, battler.pbSpeed)
    end
  end
end
