require "test/unit"
require "tmpdir"

TrainerStub = Struct.new(:numbadges)
PokemonStub = Struct.new(:level, :exp)

$Trainer = TrainerStub.new(0)
$game_self_switches = {}

module PBExperience
  def self.pbAddExperience(currexp, expgain, growth)
    return currexp + expgain
  end
end

class PokeBattle_Battle
  def initialize(party)
    @party1 = party
  end

  def pbGainExpOne(index, defeated, partic, expshare, haveexpall, showmessages=true)
    pokemon = @party1[index]
    return PBExperience.pbAddExperience(pokemon.exp, 100, :medium)
  end
end

load File.expand_path("../adapters/realidea/Level_Cap.rb", __dir__)

class RealideaLevelCapTest < Test::Unit::TestCase
  def setup
    $Trainer.numbadges = 0
    $game_self_switches.clear
    RealideaLevelCap.exp_pokemon = nil
  end

  def test_default_caps_match_unbound_expert_curve
    assert_equal([20, 26, 32, 36, 40, 45, 52, 57, 61],
                 (0..8).map do |badges|
                   $Trainer.numbadges = badges
                   RealideaLevelCap.current
                 end)
  end

  def test_vanilla_curve_is_available
    assert_equal([15, 22, 29, 33, 37, 43, 51, 55, 60],
                 RealideaLevelCap::CAPS_BY_MODE["vanilla"])
  end

  def test_champion_completion_unlocks_level_100
    $Trainer.numbadges = 8
    $game_self_switches[[156, 14, "A"]] = true
    assert_equal(100, RealideaLevelCap.current)
  end

  def test_champion_stage_uses_selected_mode_cap
    $Trainer.numbadges = 8
    Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, "Data"))
      File.open(File.join(directory, "Data", "champion_level_cap.txt"), "wb") do |file|
        file.write("enabled\n")
      end
      Dir.chdir(directory) do
        assert_equal(75, RealideaLevelCap.current)
        File.open(File.join("Data", "level_cap_mode.txt"), "wb") do |file|
          file.write("vanilla\n")
        end
        assert_equal(66, RealideaLevelCap.current)
      end
    end
  end

  def test_pokemon_at_cap_gets_one_battle_exp
    pokemon = PokemonStub.new(20, 1_000)
    result = PokeBattle_Battle.new([pokemon]).pbGainExpOne(0, nil, 0, 0, false)
    assert_equal(1_001, result)
    assert_nil(RealideaLevelCap.exp_pokemon)
  end

  def test_pokemon_below_cap_gets_normal_battle_exp
    pokemon = PokemonStub.new(19, 1_000)
    result = PokeBattle_Battle.new([pokemon]).pbGainExpOne(0, nil, 0, 0, false)
    assert_equal(1_100, result)
  end

  def test_non_battle_experience_is_unchanged
    assert_equal(1_100, PBExperience.pbAddExperience(1_000, 100, :medium))
  end
end
