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

  # 100 EXP a level: level N starts at N * 100
  def self.pbGetStartExperience(level, growth)
    return level * 100
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

  def test_original_team_mode_disables_the_cap
    $Trainer.numbadges = 0
    Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, "Data"))
      File.open(File.join(directory, "Data", "original_teams.txt"), "wb") do |file|
        file.write("enabled\n")
      end
      Dir.chdir(directory) { assert_equal(100, RealideaLevelCap.current) }
    end
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

  def in_data_dir(files={})
    Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, "Data"))
      files.each do |name, body|
        File.open(File.join(directory, "Data", name), "wb") { |file| file.write(body) }
      end
      Dir.chdir(directory) { yield }
    end
  end

  def test_rnb_curve_is_run_and_bun_one_to_one
    in_data_dir("level_cap_mode.txt" => "rnb\n") do
      assert_equal([21, 25, 35, 42, 57, 69, 85, 91, 95],
                   (0..8).map do |badges|
                     $Trainer.numbadges = badges
                     RealideaLevelCap.current
                   end)
      $Trainer.numbadges = 8
      File.open(File.join("Data", "champion_level_cap.txt"), "wb") { |f| f.write("on") }
      assert_equal(99, RealideaLevelCap.current)
    end
  end

  def test_remap_lands_every_anchor_on_its_cap
    # every anchor but the 0 floor, which clamps to level 1
    original = RealideaLevelCap::ORIGINAL_LADDER[1..-1]
    assert_equal(RealideaLevelCap.ladder("rnb")[1..-1],
                 original.map { |level| RealideaLevelCap.remap(level, "original", "rnb") })
    assert_equal(RealideaLevelCap.ladder("expert")[1..-1],
                 original.map { |level| RealideaLevelCap.remap(level, "original", "expert") })
    assert_equal(1, RealideaLevelCap.remap(0, "original", "rnb"))
  end

  def test_remap_interpolates_and_composes_between_curves
    # original 42 is 2/5 of the way from 40 to 45 -> rnb 69 + 0.4 * 16
    assert_equal(75, RealideaLevelCap.remap(42, "original", "rnb"))
    # expert gym 1 (20) is the same story point as rnb gym 1 (21)
    assert_equal(21, RealideaLevelCap.remap(20, "expert", "rnb"))
    assert_equal(57, RealideaLevelCap.remap(40, "expert", "rnb"))
    assert_equal(33, RealideaLevelCap.remap(33, "rnb", "rnb"))
    assert_equal(33, RealideaLevelCap.remap(33, "nosuch", "rnb"))
  end

  def test_remap_carries_the_offset_past_the_top_and_clamps_to_100
    assert_equal(100, RealideaLevelCap.remap(70, "original", "rnb"))
    assert_equal(79, RealideaLevelCap.remap(70, "original", "expert"))
  end

  def test_catch_up_multiplier_grows_with_the_gap
    assert_equal(1.0, RealideaLevelCap.exp_multiplier(19, 20))
    assert_equal(2.0, RealideaLevelCap.exp_multiplier(15, 20))
    assert_equal(4.0, RealideaLevelCap.exp_multiplier(1, 20))
  end

  def test_boosted_battle_exp_below_the_cap
    pokemon = PokemonStub.new(15, 1_500)   # cap 20, five short -> x2
    result = PokeBattle_Battle.new([pokemon]).pbGainExpOne(0, nil, 0, 0, false)
    assert_equal(1_700, result)
  end

  def test_boost_stops_at_the_cap_but_never_below_the_plain_award
    pokemon = PokemonStub.new(10, 1_950)   # cap 20 starts at 2_000; x3.25 of 100 = 325
    result = PokeBattle_Battle.new([pokemon]).pbGainExpOne(0, nil, 0, 0, false)
    assert_equal(2_050, result)            # the plain 100 still lands, as before
  end

  def test_exp_multiplier_file_sets_a_flat_rate_or_turns_it_off
    in_data_dir("exp_multiplier.txt" => "off") do
      assert_equal(1.0, RealideaLevelCap.exp_multiplier(1, 20))
    end
    in_data_dir("exp_multiplier.txt" => "1.5") do
      assert_equal(1.5, RealideaLevelCap.exp_multiplier(19, 20))
    end
  end

  def test_non_battle_experience_is_not_boosted
    assert_equal(1_100, PBExperience.pbAddExperience(1_000, 100, :medium))
  end
end
