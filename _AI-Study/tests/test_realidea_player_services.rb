require "test/unit"
require "tmpdir"

# --- engine stubs --------------------------------------------------------------
def _INTL(text, *args)
  args.each_with_index { |a, i| text = text.gsub("{#{i + 1}}", a.to_s) }
  text
end

ITEMS = { :CHOICEBAND => 1, :LIFEORB => 2, :ROCKYHELMET => 3, :CHARCOAL => 4, :LUMBERRY => 5 }
MOVES = { :ICEBEAM => 10, :KNOCKOFF => 11, :TOXIC => 12, :SURF => 13, :FREEZEDRY => 14,
          :MOONBLAST => 15, :ICICLECRASH => 16, :PURSUIT => 17 }
SPECIES = { :SNEASEL => 20, :WEAVILE => 21, :VULPIX => 22, :NINETALES => 23, :AZURILL => 24,
            :MARILL => 25 }
def getConst(mod, sym)
  table = { PBItems => ITEMS, PBMoves => MOVES, PBSpecies => SPECIES }[mod]
  return table[sym]
end

module PBItems; end
module PBSpecies; end
module PBMoves
  NAMES = { 10 => "Ice Beam", 11 => "Knock Off", 12 => "Toxic", 13 => "Surf" }
  def self.getName(id); NAMES[id] || "Move#{id}"; end
end

module PBTypes
  NAMES = { 1 => "ICE", 2 => "DARK", 3 => "POISON", 4 => "WATER" }
  def self.getName(t); NAMES[t]; end
end

MOVEDATA = { 10 => [1, 90], 11 => [2, 65], 12 => [3, 0], 13 => [4, 90] }
class PBMoveData
  attr_reader :type, :basedamage
  def initialize(m); @type, @basedamage = MOVEDATA[m]; end
end

$relearned = []
def pbRelearnMoveScreen(pokemon); $relearned.push(pokemon); end

class GameTemp
  attr_accessor :mart_prices
end
$game_temp = GameTemp.new

class TrainerStub
  attr_accessor :numbadges, :party
end

class Mon
  attr_accessor :species, :form, :name, :known, :compat
  def initialize(species, known=[], compat=[], form=0)
    @species = species; @known = known; @compat = compat; @form = form; @name = "Mon"
  end
  def hasMove?(m); @known.include?(m); end
  def isCompatibleWithMove?(m); @compat.include?(m); end
  def isEgg?; false; end
end

def load_data(path)
  raise "unexpected #{path}" if path != "Data/tm.dat"
  data = []
  [10, 11, 12, 13].each { |m| data[m] = [1] }
  return data
end

# eggEmerald.dat: species => moves
EGG = { 20 => [16, 17], 24 => [12] , 25 => [11] }
class FakeEggFile
  attr_accessor :pos
  def initialize
    @index = {}
    @words = []
    EGG.each { |sp, ms| @index[sp] = [1000 + @words.length * 2, ms.length]; @words.concat(ms) }
  end
  def fgetdw
    sp = @pos / 8 + 1
    val = @stage == :len ? (@index[sp] || [0, 0])[1] : (@index[sp] || [0, 0])[0]
    @stage = @stage == :len ? nil : :len
    return val
  end
  def fgetw
    w = @words[(@pos - 1000) / 2]
    @pos += 2
    return w
  end
end
def pbRgssOpen(path, mode)
  yield FakeEggFile.new
end

PREV = { 21 => 20, 23 => 22, 25 => 24 }
def pbGetPreviousForm(sp); PREV[sp] || sp; end
def pbGetBabySpecies(sp); sp == 25 ? 24 : pbGetPreviousForm(sp); end

def pbGetRelearnableMoves(pokemon); [99]; end

$mart = nil
def pbPokemonMart(stock, speech=nil, cantsell=false)
  $mart = [stock, $game_temp.mart_prices.dup, cantsell]
end

$learned = []
def pbLearnMove(pokemon, move); $learned.push([pokemon, move]); true; end
def pbFadeOutIn(z); yield; end
class PokemonScreen_Scene; end
class PokemonScreen
  def initialize(scene, party); end
  def pbStartScene(*a); end
  def pbChoosePokemon; $choose.shift; end
  def pbEndScene; end
end

module Kernel
  class << self
    attr_accessor :answers, :shown, :confirms
  end
  def self.pbMessage(message, commands=nil, cmd_if_cancel=0)
    (@shown ||= []).push([message, commands])
    return 0 if !commands
    ans = (@answers || []).shift
    return ans == :cancel ? cmd_if_cancel - 1 : ans
  end
  def self.pbConfirmMessage(message); (@confirms || []).shift; end
end

$code_prompts = []
def pbCodeMysteryGift
  $code_prompts.push(:original)
end

module RealideaBadgeRewards
  class << self; attr_accessor :waiting; end
  def self.offer; $code_prompts.push(:offer); end
  def self.enabled?; true; end
  def self.pending_badges; @waiting || []; end
end
alias badge_rewards_orig_pbCodeMysteryGift pbCodeMysteryGift
def pbCodeMysteryGift
  RealideaBadgeRewards.offer
  badge_rewards_orig_pbCodeMysteryGift
end

load File.expand_path("../adapters/realidea/Player_Services.rb", __dir__)

class RealideaPlayerServicesTest < Test::Unit::TestCase
  def setup
    $Trainer = TrainerStub.new
    $Trainer.numbadges = 0
    $game_temp.mart_prices = { :before => 1 }
    $mart = nil; $learned = []; $code_prompts = []; $choose = []
    Kernel.answers = []; Kernel.shown = []; Kernel.confirms = []
    RealideaBadgeRewards.waiting = []
  end

  def in_game(files={ "player_services.txt" => "" })
    Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, "Data"))
      files.each do |name, body|
        File.open(File.join(directory, "Data", name), "wb") { |file| file.write(body) }
      end
      Dir.chdir(directory) { yield }
    end
  end

  def test_disabled_keeps_the_npc_as_it_was
    in_game({}) do
      pbCodeMysteryGift
      assert_equal([:offer, :original], $code_prompts)
      assert_equal([], Kernel.shown)
    end
  end

  def test_menu_has_no_rewards_entry_when_nothing_waits
    in_game do
      Kernel.answers = [:cancel]
      pbCodeMysteryGift
      assert_equal([], $code_prompts)
      assert_equal(["Teach a move", "Remember moves", "Buy held items", "Enter a code", "Leave"],
                   Kernel.shown.last[1])
    end
  end

  def test_waiting_rewards_are_a_menu_entry
    in_game do
      RealideaBadgeRewards.waiting = [1, 2]
      Kernel.answers = [0, :cancel]
      pbCodeMysteryGift
      assert_equal("Badge rewards (2 waiting)", Kernel.shown.first[1][0])
      assert_equal([:offer], $code_prompts)
    end
  end

  def test_enter_a_code_runs_the_prompt_without_an_offer
    in_game do
      Kernel.answers = [3]
      pbCodeMysteryGift
      assert_equal([:original], $code_prompts)
    end
  end

  def test_the_strongest_items_open_at_two_badges
    in_game do
      $Trainer.numbadges = 1
      assert(!RealideaPlayerServices.stock.collect { |r| r[0] }.include?(1))
      $Trainer.numbadges = 2
      assert_equal([[1, 8000], [2, 8000], [3, 3000], [4, 1000], [5, 500]],
                   RealideaPlayerServices.stock)
    end
  end

  def test_the_shop_sets_its_prices_and_restores_the_old_ones
    in_game do
      $Trainer.numbadges = 2
      RealideaPlayerServices.shop
      stock, prices, cantsell = $mart
      assert_equal([1, 2, 3, 4, 5], stock)
      assert_equal([8000, 4000], prices[1])
      assert_equal([500, 250], prices[5])
      assert(cantsell)
      assert_equal({ :before => 1 }, $game_temp.mart_prices)
    end
  end

  def test_teachable_is_compatible_unknown_moves_by_name
    mon = Mon.new(21, [12], [10, 11, 12])      # knows Toxic; Surf incompatible
    assert_equal([10, 11], RealideaPlayerServices.teachable(mon))
  end

  def test_tutor_picks_a_type_then_a_move
    in_game do
      mon = Mon.new(21, [], [10, 11, 13])
      $Trainer.party = [mon]
      $choose = [0, -1]
      Kernel.answers = [0, 0]                    # types sorted: DARK, ICE, WATER -> DARK; Knock Off
      Kernel.confirms = [false]
      RealideaPlayerServices.tutor
      assert_equal([[mon, 11]], $learned)
      assert_equal(["DARK (1)", "ICE (1)", "WATER (1)", "Back"], Kernel.shown[0][1])
      assert_equal(["Knock Off · DARK · 65", "Back"], Kernel.shown[1][1])
    end
  end

  def test_status_moves_show_no_power
    assert_equal("Toxic · POISON · -", RealideaPlayerServices.move_label(12))
  end

  def test_shop_categories_and_the_gate_notice
    in_game do
      $Trainer.numbadges = 1
      Kernel.answers = [0, :cancel]
      RealideaPlayerServices.shops
      assert_equal([3], $mart[0])                # battle items without the gated ones
      assert(Kernel.shown.any? { |m, c| m.index("after your second badge") })
    end
  end

  def test_remember_opens_the_move_reminder
    in_game do
      mon = Mon.new(21)
      $Trainer.party = [mon]
      $choose = [0, -1]
      RealideaPlayerServices.remember
      assert_equal([mon], $relearned)
    end
  end

  def test_egg_moves_come_from_the_root_and_the_baby
    assert_equal([16, 17], RealideaPlayerServices.egg_moves(Mon.new(21)))    # Weavile <- Sneasel
    assert_equal([11, 12], RealideaPlayerServices.egg_moves(Mon.new(25)).sort)  # Marill: Azurill + own
  end

  def test_alolan_vulpix_line_gets_its_own_list
    assert_equal([14, 15], RealideaPlayerServices.egg_moves(Mon.new(23, [], [], 1)))
  end

  def test_move_reminder_adds_unknown_egg_moves_when_enabled
    in_game do
      assert_equal([99, 17], pbGetRelearnableMoves(Mon.new(21, [16])))
    end
    in_game({}) do
      assert_equal([99], pbGetRelearnableMoves(Mon.new(21)))
    end
  end
end
