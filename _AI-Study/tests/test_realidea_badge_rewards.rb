require "test/unit"
require "tmpdir"

# --- engine stubs --------------------------------------------------------------
def _INTL(text, *args)
  args.each_with_index { |a, i| text = text.gsub("{#{i + 1}}", a.to_s) }
  text
end

module PBSpecies
  NAMES = { 1 => "Gible", 2 => "Gabite", 3 => "Garchomp", 4 => "Axew", 5 => "Elekid",
            6 => "Magby", 7 => "Smoochum", 8 => "Latias" }
  def self.getName(id); NAMES[id]; end
end

module PBItems
  NAMES = { 101 => "Ampharosita", 102 => "Aggronita", 103 => "Pidgeotita",
            110 => "Abomasnowita", 111 => "Aerodactylita", 112 => "Alakazamita" }
  def self.getName(id); NAMES[id]; end
end

SPECIES = { :GIBLE => 1, :GABITE => 2, :GARCHOMP => 3, :AXEW => 4, :ELEKID => 5,
            :MAGBY => 6, :SMOOCHUM => 7, :LATIAS => 8 }
ITEMS = { :AMPHAROSITE => 101, :AGGRONITE => 102, :PIDGEOTITE => 103,
          :ABOMASITE => 110, :AERODACTYLITE => 111, :ALAKAZITE => 112 }

def getConst(mod, sym)
  return (mod == PBSpecies ? SPECIES : ITEMS)[sym]
end

module PBExperience
  MAXLEVEL = 100
  def self.pbAddExperience(currexp, expgain, growth); currexp + expgain; end
end

EVOLVES = { 1 => [24, 2], 2 => [48, 3] }     # Gible 24 -> Gabite 48 -> Garchomp

class PokeBattle_Pokemon
  attr_accessor :species, :level, :name, :reset
  def initialize(species, level, owner)
    @species = species; @level = level; @name = PBSpecies.getName(species)
  end
  def calcStats; end
  def resetMoves; @reset = true; end
end

def pbCheckEvolution(poke)
  evo = EVOLVES[poke.species]
  return (evo && poke.level >= evo[0]) ? evo[1] : -1
end

class TrainerStub
  attr_accessor :numbadges, :party
  def initialize; @numbadges = 0; @party = []; @regalosmis = []; end
  def regalosmis; @regalosmis; end
end

module Kernel
  class << self
    attr_accessor :answers, :shown, :received
  end
  def self.pbMessage(message, commands=nil, cmd_if_cancel=0)
    (@shown ||= []).push([message, commands])
    return 0 if !commands
    ans = (@answers || []).shift
    return ans == :cancel ? cmd_if_cancel - 1 : ans
  end
  def self.pbReceiveItem(item)
    (@received ||= []).push(item)
  end
end

$boxes_full = false
$added = []
def pbAddPokemon(poke)
  return false if $boxes_full
  $added.push(poke)
  return true
end

def pbBalancedLevel(party); 30; end

$codes_prompted = 0
def pbCodeMysteryGift
  $codes_prompted += 1
end

def renderBadgeAnimation(badge_number=0); :shown; end

class Game_Switches
  def initialize; @data = []; end
  def [](i); @data[i]; end
end

class PokeBattle_Battle
  def pbGainExpOne(index, defeated, partic, expshare, haveexpall, showmessages=true); end

  def pbCanMegaEvolve?(index)
    return false if $game_switches[512] == false || $game_switches[512].nil?
    return true
  end
end

load File.expand_path("../adapters/realidea/Level_Cap.rb", __dir__)
load File.expand_path("../adapters/realidea/Badge_Rewards.rb", __dir__)

class RealideaBadgeRewardsTest < Test::Unit::TestCase
  def setup
    $Trainer = TrainerStub.new
    $game_switches = Game_Switches.new
    $game_self_switches = {}
    $boxes_full = false
    $added = []
    $codes_prompted = 0
    Kernel.answers = []
    Kernel.shown = []
    Kernel.received = []
  end

  def in_game(files={ "badge_rewards.txt" => "" })
    Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, "Data"))
      files.each do |name, body|
        File.open(File.join(directory, "Data", name), "wb") { |file| file.write(body) }
      end
      Dir.chdir(directory) { yield }
    end
  end

  def test_nothing_is_pending_without_badges
    in_game { assert_equal([], RealideaBadgeRewards.pending_badges) }
  end

  def test_rewards_accumulate_by_badge_count
    in_game do
      $Trainer.numbadges = 2
      assert_equal([1], RealideaBadgeRewards.pending_badges)   # badge 2's picks are absent here
    end
  end

  def test_claiming_a_badge_3_reward_gives_an_evolved_gift_and_a_stone
    in_game("badge_rewards.txt" => "", "level_cap_mode.txt" => "rnb") do
      $Trainer.numbadges = 3
      $Trainer.regalosmis.push("rnbbadge1p")                   # badge 1 already taken
      Kernel.answers = [1, 0]                                  # Gible, Ampharosita
      pbCodeMysteryGift
      gift = $added[0]
      assert_equal(39, gift.level)                             # rnb cap 42 - 3
      assert_equal(2, gift.species)                            # Gible 24 -> Gabite, not 48 yet
      assert_equal("Gabite", gift.name)
      assert(gift.reset)
      assert_equal([101], Kernel.received)
      assert_equal(["rnbbadge1p", "rnbbadge3p", "rnbbadge3s0", "rnbbadgeitem:AMPHAROSITE"],
                   $Trainer.regalosmis)
      assert_equal(1, $codes_prompted)                          # codes still asked after
      assert_equal([], RealideaBadgeRewards.pending_badges)
    end
  end

  def test_later_ends_the_offer_and_claims_nothing
    in_game do
      $Trainer.numbadges = 1
      Kernel.answers = [:cancel]
      pbCodeMysteryGift
      assert_equal([], $added)
      assert_equal([], $Trainer.regalosmis)
      assert_equal([1], RealideaBadgeRewards.pending_badges)
      assert_equal(1, $codes_prompted)
    end
  end

  def test_full_boxes_claim_nothing
    in_game do
      $Trainer.numbadges = 1
      $boxes_full = true
      Kernel.answers = [0]
      pbCodeMysteryGift
      assert_equal([], $Trainer.regalosmis)
    end
  end

  def test_a_late_stone_taken_at_badge_6_is_not_offered_again_at_7
    in_game do
      $Trainer.numbadges = 7
      $Trainer.regalosmis.push("rnbbadgeitem:ABOMASITE")
      assert_equal([:AERODACTYLITE, :ALAKAZITE], RealideaBadgeRewards.stone_choices(7))
    end
  end

  def test_disabled_offers_nothing
    in_game({}) do
      $Trainer.numbadges = 3
      pbCodeMysteryGift
      assert_equal([], Kernel.shown)
      assert_equal(1, $codes_prompted)
    end
  end

  def test_megas_open_at_badge_3_and_the_switch_is_restored
    in_game do
      battle = PokeBattle_Battle.new
      $Trainer.numbadges = 2
      assert_equal(false, battle.pbCanMegaEvolve?(0))
      $Trainer.numbadges = 3
      assert_equal(true, battle.pbCanMegaEvolve?(0))
      assert_nil($game_switches[512])
    end
  end

  def test_megas_follow_the_game_switch_when_disabled
    in_game({}) do
      $Trainer.numbadges = 8
      assert_equal(false, PokeBattle_Battle.new.pbCanMegaEvolve?(0))
    end
  end

  def test_badge_hint_only_when_something_waits
    in_game do
      $Trainer.numbadges = 1
      assert_equal(:shown, renderBadgeAnimation(0))
      assert_equal(1, Kernel.shown.length)
      $Trainer.regalosmis.push("rnbbadge1p")
      renderBadgeAnimation(0)
      assert_equal(1, Kernel.shown.length)
    end
  end
end
