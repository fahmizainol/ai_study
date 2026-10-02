require "test/unit"
require "tmpdir"

# --- engine stubs --------------------------------------------------------------
$wild_battles = 0
def pbWildBattle(*args); $wild_battles += 1; end
def pbAddPokemon(*args); true; end

class Scene_Map
  def update; :updated; end
end

module PBExperience
  MAXLEVEL = 100
  def self.pbAddExperience(currexp, expgain, growth); currexp + expgain; end
  def self.pbGetStartExperience(level, growth); level * 100; end
end

class PokeBattle_Battle
  def pbGainExpOne(index, defeated, partic, expshare, haveexpall, showmessages=true); end
end

class Mon
  attr_accessor :level, :stats_calls
  def initialize(level); @level = level; @stats_calls = 0; end
  def calcStats; @stats_calls += 1; end
end

TrainerStub = Struct.new(:numbadges, :party)
$Trainer = TrainerStub.new(0, [])
$game_self_switches = {}
$override_spec = nil       # what the stub Team_Overrides swaps in, or nil

def pbBalancedLevel(party)
  return party.map { |m| m.level }.max + 2    # enough for a readable anchor
end

def balanceo
  pbBalancedLevel($Trainer.party) - 1
end

def team_override_build(spec)
  spec.map { |lv| Mon.new(lv) }
end

# stand-ins for the engine + Team_Overrides chain the section wraps
def createTrainer(trainerid, trainername, party, items=[])
  party = team_override_build($override_spec) if $override_spec
  return [:opponent, items, party]
end

def pbLoadTrainer(trainerid, trainername, partyid=0)
  party = $override_spec ? team_override_build($override_spec) : $dat_party
  return [:opponent, [], party]
end

def pbRegisterPartner(trainerid, trainername, partyid=0)
  return pbLoadTrainer(trainerid, trainername, partyid)
end

class PokemonEncounters
  def pbEncounteredPokemon(enctype, tries=1)
    return $wild
  end
end

load File.expand_path("../adapters/realidea/Level_Cap.rb", __dir__)
load File.expand_path("../adapters/realidea/Level_Scaling.rb", __dir__)

class RealideaLevelScalingTest < Test::Unit::TestCase
  def setup
    $Trainer.numbadges = 5
    $Trainer.party = [Mon.new(10)]           # anchor 11: below every fight here
    $override_spec = nil
    $dat_party = nil
    $wild = nil
    RealideaLevelScaling.clear_balanceo
  end

  def in_game(files)
    Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, "Data"))
      files.each do |name, body|
        File.open(File.join(directory, "Data", name), "wb") { |file| file.write(body) }
      end
      Dir.chdir(directory) { yield }
    end
  end

  def levels(result)
    result[2].map { |m| m.level }
  end

  RNB = { "level_scaling.txt" => "", "level_cap_mode.txt" => "rnb" }

  def test_event_party_moves_from_the_original_ladder
    in_game(RNB) do
      # original 40 / 38 are gym-6 / gym-5 aces -> rnb 69 / 57
      assert_equal([69, 57], levels(createTrainer(1, "Filler", [Mon.new(40), Mon.new(38)])))
    end
  end

  def test_generated_override_moves_from_the_expert_ladder
    in_game(RNB) do
      $override_spec = [20, 19]               # built on expert: ace 20 != event's 14
      assert_equal([21, 20], levels(createTrainer(1, "Abi", [Mon.new(14)])))
    end
  end

  def test_filler_override_that_keeps_levels_is_original
    in_game(RNB) do
      $override_spec = [40, 38]               # same ace as the event: vanilla levels
      assert_equal([69, 57], levels(createTrainer(1, "Filler", [Mon.new(40), Mon.new(37)])))
    end
  end

  def test_registry_can_declare_its_curve
    in_game(RNB) do
      Object.const_set(:TEAM_OVERRIDES_CURVE, "rnb")
      begin
        $override_spec = [57, 55]             # already on rnb: stays
        assert_equal([57, 55], levels(createTrainer(1, "Gym5", [Mon.new(38)])))
      ensure
        Object.send(:remove_const, :TEAM_OVERRIDES_CURVE)
      end
    end
  end

  def test_balanceo_fight_is_not_remapped
    in_game(RNB) do
      $Trainer.party = [Mon.new(40)]          # balanceo 41, anchor 41
      party = [Mon.new(balanceo), Mon.new(balanceo - 2)]
      assert_equal([41, 39], levels(createTrainer(1, "Scaled", party)))
    end
  end

  def test_anchor_still_lifts_a_remapped_fight_within_the_leash
    in_game(RNB) do
      $Trainer.party = [Mon.new(80)]          # anchor 81
      # original 40 -> 69, then up toward 81 by at most 6
      assert_equal([75, 63], levels(createTrainer(1, "Filler", [Mon.new(40), Mon.new(38)])))
    end
  end

  def test_expert_overrides_are_untouched_in_expert_mode
    in_game("level_scaling.txt" => "", "level_cap_mode.txt" => "expert") do
      $override_spec = [20, 19]
      assert_equal([20, 19], levels(createTrainer(1, "Abi", [Mon.new(14)])))
    end
  end

  def test_scripted_outlier_keeps_its_level
    in_game(RNB) do
      # original 10 -> rnb 15; the pinned 60 is past median + 2*leash and stays
      party = [Mon.new(10), Mon.new(10), Mon.new(60)]
      assert_equal([15, 15, 60], levels(createTrainer(1, "Pinned", party)))
    end
  end

  def test_stats_are_recalculated_for_every_moved_mon
    in_game(RNB) do
      result = createTrainer(1, "Filler", [Mon.new(40)])
      assert_equal(1, result[2][0].stats_calls)
    end
  end

  def test_dat_fight_moves_from_the_original_ladder
    in_game(RNB) do
      $dat_party = [Mon.new(48)]
      assert_equal([91], levels(pbLoadTrainer(1, "Dat")))
    end
  end

  def test_partner_is_never_touched
    in_game(RNB) do
      $dat_party = [Mon.new(48)]
      assert_equal([48], levels(pbRegisterPartner(1, "Ally")))
    end
  end

  def test_nothing_moves_without_the_scaling_file
    in_game("level_cap_mode.txt" => "rnb") do
      assert_equal([40], levels(createTrainer(1, "Filler", [Mon.new(40)])))
    end
  end

  def test_original_rosters_are_never_remapped
    in_game(RNB.merge("original_teams.txt" => "")) do
      assert_equal([40], levels(createTrainer(1, "Filler", [Mon.new(40)])))
    end
  end

  def test_wild_levels_follow_the_curve_when_enabled
    in_game(RNB.merge("wild_scaling.txt" => "")) do
      $wild = [25, 40]
      assert_equal([25, 69], PokemonEncounters.new.pbEncounteredPokemon(0))
    end
    in_game(RNB) do
      $wild = [25, 40]
      assert_equal([25, 40], PokemonEncounters.new.pbEncounteredPokemon(0))
    end
  end

  def test_no_encounter_passes_through
    in_game(RNB.merge("wild_scaling.txt" => "")) do
      assert_nil(PokemonEncounters.new.pbEncounteredPokemon(0))
    end
  end

  def test_balanceo_mark_is_used_up_by_the_fight_it_marked
    in_game(RNB) do
      $Trainer.party = [Mon.new(40)]
      createTrainer(1, "Scaled", [Mon.new(balanceo)])
      $Trainer.party = [Mon.new(10)]
      assert_equal([69], levels(createTrainer(1, "Filler", [Mon.new(40)])))
    end
  end

  def test_wild_battles_gifts_and_map_updates_clear_a_stale_mark
    in_game(RNB) do
      balanceo; pbWildBattle(:HOOH, 50)
      assert_equal([69], levels(createTrainer(1, "Filler", [Mon.new(40)])))
      balanceo; pbAddPokemon(:ROWLET, 20)
      assert_equal([69], levels(createTrainer(1, "Filler", [Mon.new(40)])))
      balanceo; assert_equal(:updated, Scene_Map.new.update)
      assert_equal([69], levels(createTrainer(1, "Filler", [Mon.new(40)])))
    end
  end
end
