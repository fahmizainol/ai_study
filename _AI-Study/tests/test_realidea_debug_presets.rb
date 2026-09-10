require "test/unit"

root = File.expand_path("..", File.dirname(__FILE__))

# ---------------------------------------------------------------------------
# Engine stubs. Constant VALUES are Realidea's own (069_PBStats.rb,
# 067_PBNatures.rb, 123_PokeBattle_Pokemon.rb), so a preset written against the
# wrong stat order fails here rather than silently building the wrong Pokemon
# in game.
# ---------------------------------------------------------------------------
module PBStats
  HP = 0; ATTACK = 1; DEFENSE = 2; SPEED = 3; SPATK = 4; SPDEF = 5
end

module PBNatures
  HARDY = 0; LONELY = 1; BRAVE = 2; ADAMANT = 3; NAUGHTY = 4
  BOLD = 5; DOCILE = 6; RELAXED = 7; IMPISH = 8; LAX = 9
  TIMID = 10; HASTY = 11; SERIOUS = 12; JOLLY = 13; NAIVE = 14
  MODEST = 15; MILD = 16; QUIET = 17; BASHFUL = 18; RASH = 19
  CALM = 20; GENTLE = 21; SASSY = 22; CAREFUL = 23; QUIRKY = 24
  def self.getCount; 25; end
  def self.getName(id); "N#{id}"; end
end

module PokeBattle_Pokemon_Limits
  EVLIMIT = 510
  EVSTATLIMIT = 252
end

module PBExperience
  MAXLEVEL = 100
end

# Level_Cap.rb, section 331. The real one derives the cap from badges and the
# marker files; only the value it hands back matters here.
module RealideaLevelCap
  def self.current; @current.nil? ? 40 : @current; end
  def self.current=(value); @current = value; end
end

# 116_PItem_Items.rb:296. The real one shows the level-up message and stat
# window, teaches the level's moves and runs one evolution; what matters here is
# that the adapter delegates to it instead of assigning the level itself.
$change_level_calls = []
$evolution_scenes = []
$evolution_queue = []

def pbChangeLevel(pokemon, newlevel, scene)
  $change_level_calls << [pokemon, newlevel, scene]
  pokemon.level = newlevel
end

# 127_Pokemon_Evolution.rb:1014 -- returns the NEXT species only, or -1.
def pbCheckEvolution(pokemon, item = 0)
  $evolution_queue.empty? ? -1 : $evolution_queue.shift
end

def pbFadeOutInWithMusic(z)
  yield
end

class PokemonEvolutionScene
  def pbStartScreen(pkmn, newspecies); $evolution_scenes << newspecies; end
  def pbEvolution; end
  def pbEndScreen; end
end

def _INTL(str, *args)
  ret = str.dup
  args.each_with_index { |a, i| ret = ret.gsub("{#{i + 1}}", a.to_s) }
  ret
end

# 123_PokeBattle_Pokemon.rb: nature falls back to personalID%25 unless overridden;
# setNature writes @natureflag then recalculates.
class FakePokemon
  attr_accessor :natureflag, :personalID
  attr_reader :ev, :name, :calc_count

  def initialize
    @name = "Shuckle"
    @ev = [0, 0, 0, 0, 0, 0]
    @personalID = 3
    @natureflag = nil
    @calc_count = 0
    @level = 5
  end

  def nature; @natureflag.nil? ? @personalID % 25 : @natureflag; end
  def level; @level; end

  # level= raises outside 1..MAXLEVEL in the real engine, which is what the
  # adapter's clamp exists to avoid.
  def level=(value)
    raise ArgumentError.new("bad level #{value}") if value < 1 || value > PBExperience::MAXLEVEL
    @level = value
  end
  def calcStats; @calc_count += 1; end
  def setNature(value); @natureflag = value; calcStats; end
end

class FakeScene
  attr_reader :prompts

  def initialize(replies); @replies = replies; @prompts = []; end

  def pbShowCommands(help, commands, index = 0)
    @prompts << [help, commands.dup, index]
    raise "ran out of scripted replies" if @replies.empty?
    @replies.shift
  end
end

# 136_PScreen_Party.rb, class PokemonScreen. The adapter aliases pbPokemonDebug,
# so the stock method has to exist before the adapter is loaded.
class PokemonScreen
  attr_reader :stock_calls, :messages, :refreshed, :hard_refreshes

  def initialize(scene)
    @scene = scene
    @stock_calls = []
    @messages = []
    @refreshed = []
    @hard_refreshes = 0
  end

  def pbPokemonDebug(pkmn, pkmnid); @stock_calls << [pkmn, pkmnid]; end
  def pbRefreshSingle(pkmnid); @refreshed << pkmnid; end
  def pbHardRefresh; @hard_refreshes += 1; end
  def pbDisplay(msg); @messages << msg; end
end

load File.join(root, "adapters", "realidea", "Debug_Mode.rb")

PRESETS = PokemonScreen::REALIDEA_STAT_PRESETS
DEBUG_ENTRY = 0                    # first menu entry delegates to the stock menu
LEVEL_ENTRY = 1                    # present only while Level_Cap.rb is installed
PRESET_BASE = 2
CANCEL = PRESET_BASE + PRESETS.length

def preset(label)
  row = PRESETS.find { |p| p[0] == label }
  raise "no preset named #{label}" if row.nil?
  row
end

def preset_index(label)
  PRESET_BASE + PRESETS.index(preset(label))
end

# Shared engine state, reset by every suite that drives the menu -- otherwise a
# bounded-chain test leaves 45 pending evolutions for whatever runs next.
def reset_engine_calls
  RealideaLevelCap.current = nil
  $change_level_calls = []
  $evolution_scenes = []
  $evolution_queue = []
end

# Runs a block with Level_Cap.rb uninstalled, the way --remove would leave it.
def without_level_cap
  saved = RealideaLevelCap
  Object.send(:remove_const, :RealideaLevelCap)
  yield
ensure
  Object.const_set(:RealideaLevelCap, saved)
end

class TestPresetTable < Test::Unit::TestCase
  def test_every_spread_is_legal
    PRESETS.each do |label, evs, _nature|
      assert_equal 6, evs.length, "#{label}: needs one EV per PBStats slot"
      evs.each do |v|
        assert v >= 0 && v <= PokeBattle_Pokemon_Limits::EVSTATLIMIT,
               "#{label}: #{v} is outside 0..EVSTATLIMIT"
      end
      total = evs.inject(0) { |a, b| a + b }
      assert total <= PokeBattle_Pokemon_Limits::EVLIMIT,
             "#{label}: #{total} EVs exceeds EVLIMIT"
    end
  end

  def test_natures_are_real_ids
    PRESETS.each do |label, _evs, nature|
      next if nature.nil?
      assert nature >= 0 && nature < PBNatures.getCount, "#{label}: bad nature id"
    end
  end

  def test_labels_are_unique
    labels = PRESETS.map { |p| p[0] }
    assert_equal labels.length, labels.uniq.length
  end

  # The trap this table exists to avoid: PBStats puts SPEED at index 3, so a
  # sweeper written in Showdown order would invest in Sp. Atk instead.
  def test_sweepers_invest_in_speed_not_the_showdown_slot
    _label, evs, nature = preset("Physical sweeper")
    assert_equal 252, evs[PBStats::SPEED]
    assert_equal 252, evs[PBStats::ATTACK]
    assert_equal 0, evs[PBStats::SPATK]
    assert_equal PBNatures::JOLLY, nature
  end
end

class TestApplyPreset < Test::Unit::TestCase
  def setup
    @pkmn = FakePokemon.new
    @scene = FakeScene.new([])
    @screen = PokemonScreen.new(@scene)
  end

  def apply(label)
    @screen.pbApplyStatPreset(@pkmn, 2, preset(label))
  end

  def test_physical_wall_sets_evs_and_forces_nature
    apply("Physical wall")
    assert_equal [252, 0, 252, 0, 0, 4], @pkmn.ev
    assert_equal PBNatures::BOLD, @pkmn.natureflag
    assert_equal PBNatures::BOLD, @pkmn.nature
    assert_equal 1, @pkmn.calc_count
    assert_equal [2], @screen.refreshed
    assert_equal 1, @screen.messages.length
    assert @screen.messages[0].include?("Physical wall")
  end

  def test_clear_restores_the_natural_nature
    apply("Special sweeper")
    apply("Clear EVs and nature")
    assert_equal [0, 0, 0, 0, 0, 0], @pkmn.ev
    assert_nil @pkmn.natureflag
    assert_equal @pkmn.personalID % 25, @pkmn.nature
  end

  # The stock menu writes pkmn.ev element by element; anything holding the array
  # (the summary line, a party sprite) must not be left pointing at a stale one.
  def test_ev_array_is_mutated_in_place
    before = @pkmn.ev
    apply("Special wall")
    assert_same before, @pkmn.ev
  end

  def test_switching_presets_leaves_no_residue
    apply("Mixed attacker")
    apply("Special wall")
    assert_equal [252, 0, 4, 0, 0, 252], @pkmn.ev
    assert_equal PBNatures::CALM, @pkmn.natureflag
  end
end

class TestMenuWiring < Test::Unit::TestCase
  def setup; reset_engine_calls; end
  def teardown; reset_engine_calls; end

  def run_menu(replies)
    @pkmn = FakePokemon.new
    @scene = FakeScene.new(replies)
    @screen = PokemonScreen.new(@scene)
    @screen.pbPokemonDebug(@pkmn, 0)
  end

  def test_first_entry_opens_the_stock_debug_menu
    run_menu([DEBUG_ENTRY, CANCEL])
    assert_equal 1, @screen.stock_calls.length
    assert_equal [@pkmn, 0], @screen.stock_calls[0]
  end

  def test_cancel_and_b_button_both_exit
    run_menu([CANCEL])
    assert_equal 1, @scene.prompts.length
    run_menu([-1])
    assert_equal 1, @scene.prompts.length
  end

  def test_preset_applies_and_the_menu_stays_open
    run_menu([preset_index("Special sweeper"), CANCEL])
    assert_equal [4, 0, 0, 252, 252, 0], @pkmn.ev
    assert_equal PBNatures::TIMID, @pkmn.natureflag
    assert_equal 2, @scene.prompts.length
    assert_equal 0, @screen.stock_calls.length
  end

  def test_menu_lists_the_stock_menu_then_level_then_every_preset_then_cancel
    RealideaLevelCap.current = 36
    run_menu([CANCEL])
    commands = @scene.prompts[0][1]
    assert_equal PRESETS.length + 3, commands.length
    assert_equal "Debug menu", commands[DEBUG_ENTRY]
    assert_equal "Level up to cap (36)", commands[LEVEL_ENTRY]
    assert_equal "Cancel", commands[CANCEL]
    assert_equal PRESETS.map { |p| p[0] }, commands[PRESET_BASE...CANCEL]
  end

  # The header is the readout that tells you what a preset did, and it prints in
  # a different order than the array is stored in.
  def test_summary_reprints_evs_in_the_labelled_order
    run_menu([preset_index("Physical sweeper"), CANCEL])
    after = @scene.prompts[1][0]
    assert after.include?("EVs 4/252/0/0/0/252"), after
    assert after.include?("HP/Atk/Def/SpA/SpD/Spe"), after
    assert after.include?(PBNatures.getName(PBNatures::JOLLY)), after
  end

  def test_summary_shows_the_live_level
    RealideaLevelCap.current = 43
    run_menu([LEVEL_ENTRY, CANCEL])
    assert @scene.prompts[0][0].include?("Shuckle Lv5:"), @scene.prompts[0][0]
    assert @scene.prompts[1][0].include?("Shuckle Lv43:"), @scene.prompts[1][0]
  end

  def test_menu_reopens_on_the_last_choice
    run_menu([preset_index("Physical wall"), CANCEL])
    assert_equal preset_index("Physical wall"), @scene.prompts[1][2]
  end
end

class TestLevelCapEntry < Test::Unit::TestCase
  def setup
    reset_engine_calls
    RealideaLevelCap.current = 40
  end

  def teardown; reset_engine_calls; end

  def run_menu(replies)
    @pkmn = FakePokemon.new
    @scene = FakeScene.new(replies)
    @screen = PokemonScreen.new(@scene)
    @screen.pbPokemonDebug(@pkmn, 1)
  end

  # The engine owns what a level gain means -- happiness, the stat window, the
  # moves, the first evolution -- so the adapter must delegate, not assign.
  def test_the_level_gain_goes_through_pbChangeLevel
    run_menu([LEVEL_ENTRY, CANCEL])
    assert_equal 1, $change_level_calls.length
    pokemon, newlevel, scene = $change_level_calls[0]
    assert_same @pkmn, pokemon
    assert_equal 40, newlevel
    assert_same @screen, scene
    assert_equal 40, @pkmn.level
  end

  # A species/sprite can change underneath the party panel, which pbRefreshSingle
  # does not redraw -- the Rare Candy handler calls pbHardRefresh for this reason.
  def test_the_party_panel_is_hard_refreshed
    run_menu([LEVEL_ENTRY, CANCEL])
    assert_equal 1, @screen.hard_refreshes
  end

  # The bug this fixes: a jump across two thresholds used to stop one stage short,
  # because pbChangeLevel runs one evolution and pbCheckEvolution reports one stage.
  def test_a_multi_stage_chain_evolves_all_the_way
    $evolution_queue = [5, 6]
    run_menu([LEVEL_ENTRY, CANCEL])
    assert_equal [5, 6], $evolution_scenes
  end

  def test_no_evolution_scene_when_the_chain_reports_nothing
    run_menu([LEVEL_ENTRY, CANCEL])
    assert_equal [], $evolution_scenes
  end

  # Bad PBS data can describe a species that evolves into itself; unbounded, that
  # is an evolution scene the player cannot escape.
  def test_a_self_referential_chain_is_bounded
    $evolution_queue = Array.new(50) { 9 }
    run_menu([LEVEL_ENTRY, CANCEL])
    assert_equal PokemonScreen::EVOLUTION_STEP_LIMIT, $evolution_scenes.length
  end

  # The cap moves with badges, so a party member is routinely already past it.
  def test_a_pokemon_at_the_cap_is_left_alone
    RealideaLevelCap.current = 5
    run_menu([LEVEL_ENTRY, CANCEL])
    assert_equal 5, @pkmn.level
    assert_equal [], $change_level_calls
    assert_equal [], $evolution_scenes
    assert_equal 0, @screen.hard_refreshes
    assert @screen.messages[0].include?("already at the level cap (5)"), @screen.messages[0]
  end

  def test_a_pokemon_above_the_cap_is_never_lowered
    RealideaLevelCap.current = 3
    run_menu([LEVEL_ENTRY, CANCEL])
    assert_equal 5, @pkmn.level
    assert_equal [], $change_level_calls
  end

  # level= raises ArgumentError outside 1..MAXLEVEL, and that would abort the
  # party screen rather than showing an error.
  def test_an_out_of_range_cap_is_clamped_not_raised
    RealideaLevelCap.current = 999
    run_menu([LEVEL_ENTRY, CANCEL])
    assert_equal PBExperience::MAXLEVEL, @pkmn.level
    assert_equal "Level up to cap (100)", @scene.prompts[0][1][LEVEL_ENTRY]
  end

  def test_a_non_integer_cap_hides_the_entry
    RealideaLevelCap.current = "expert"
    run_menu([PRESETS.length + 1])       # Cancel, one slot lower without the entry
    commands = @scene.prompts[0][1]
    assert_equal PRESETS.length + 2, commands.length
    assert_equal "Debug menu", commands[DEBUG_ENTRY]
    assert_equal PRESETS.map { |p| p[0] }, commands[1...(PRESETS.length + 1)]
  end

  # Level_Cap.rb installs and uninstalls independently of this section.
  def test_entry_is_absent_when_the_level_cap_section_is_not_installed
    without_level_cap do
      run_menu([PRESETS.length + 1])
      commands = @scene.prompts[0][1]
      assert_equal PRESETS.length + 2, commands.length
      assert_equal "Cancel", commands[PRESETS.length + 1]
      assert_equal [], $change_level_calls
    end
  end

  # With the entry gone every preset shifts down one slot; picking by position
  # has to still land on the preset the label promises.
  def test_presets_still_resolve_without_the_level_entry
    without_level_cap do
      run_menu([1, PRESETS.length + 1])
      assert_equal PRESETS[0][1], @pkmn.ev
      assert_equal PRESETS[0][2], @pkmn.natureflag
    end
  end
end
