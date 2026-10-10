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

module PBItems
  def self.getName(id); ITEMS.key(id).to_s; end
end
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
  attr_accessor :numbadges, :party, :money
end

class BagStub
  attr_accessor :items, :full
  def initialize; @items = []; @full = false; end
  def pbQuantity(item); @items.find_all { |id| id == item }.length; end
  def pbStoreItem(item)
    return false if @full
    @items.push(item)
    return true
  end
end

class Mon
  attr_accessor :species, :form, :name, :known, :compat, :item, :egg, :hp
  def initialize(species, known=[], compat=[], form=0)
    @species = species; @known = known; @compat = compat; @form = form; @name = "Mon"
    @item = 0; @egg = false; @hp = 100
  end
  def hasMove?(m); @known.include?(m); end
  def isCompatibleWithMove?(m); @compat.include?(m); end
  def isEgg?; @egg; end
end

# tm.dat: move => species that can learn it
$tm_loads = 0
def load_data(path)
  raise "unexpected #{path}" if path != "Data/tm.dat"
  $tm_loads += 1
  data = []
  { 10 => [21, 23], 11 => [21], 12 => [21], 13 => [99] }.each { |m, sp| data[m] = sp }
  return data
end

# the Alolan form (23 form 1) carries its own list, as Pokemon_MultipleForms does
module MultipleForms
  def self.call(name, pokemon)
    return nil if name != "getMoveCompatibility"
    return (pokemon.species == 23 && pokemon.form == 1) ? [:FREEZEDRY, 15] : nil
  end
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

BR_LOSS = 2
$trainer_calls = []
def pbTrainerBattle(*args); $trainer_calls.push([:single, args]); true; end
def pbDoubleTrainerBattle(*args); $trainer_calls.push([:double, args]); true; end
def customTrainerBattle(*args); $trainer_calls.push([:custom, args]); 1; end

load File.expand_path("../adapters/realidea/Player_Services.rb", __dir__)

class RealideaPlayerServicesTest < Test::Unit::TestCase
  def setup
    $Trainer = TrainerStub.new
    $Trainer.numbadges = 0
    $Trainer.money = 100000
    $Trainer.party = []
    $trainer_calls = []
    $PokemonBag = BagStub.new
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

  def test_competitive_items_open_at_four_badges
    in_game do
      $Trainer.numbadges = 1
      assert(!RealideaPlayerServices.stock.collect { |r| r[0] }.include?(1))
      $Trainer.numbadges = 3
      assert(!RealideaPlayerServices.stock.collect { |r| r[0] }.include?(2))
      $Trainer.numbadges = 4
      assert_equal([[1, 8000], [2, 8000], [3, 3000], [4, 1000], [5, 500]],
                   RealideaPlayerServices.stock)
    end
  end

  def test_the_shop_sets_its_prices_and_restores_the_old_ones
    in_game do
      $Trainer.numbadges = 4
      RealideaPlayerServices.shop
      stock, prices, cantsell = $mart
      assert_equal([3, 4, 5], stock)
      assert_equal([3000, 1500], prices[3])
      assert_equal([500, 250], prices[5])
      assert(cantsell)
      assert_equal({ :before => 1 }, $game_temp.mart_prices)
    end
  end

  def test_teachable_is_compatible_unknown_moves_by_name
    mon = Mon.new(21, [12])                    # knows Toxic; Surf is not Weavile's
    assert_equal([10, 11], RealideaPlayerServices.teachable(mon))
  end

  def test_tm_data_is_read_once_not_once_per_move
    before = $tm_loads
    3.times { RealideaPlayerServices.teachable(Mon.new(21)) }
    assert($tm_loads - before <= 1, "tm.dat loaded #{$tm_loads - before} times")
  end

  def test_a_form_with_its_own_list_uses_it
    assert_equal([14, 15].sort, RealideaPlayerServices.teachable(Mon.new(23, [], [], 1)).sort)
    assert_equal([10], RealideaPlayerServices.teachable(Mon.new(23)))
  end

  def test_tutor_lists_every_move_alphabetically
    in_game do
      mon = Mon.new(21)
      $Trainer.party = [mon]
      $choose = [0, -1]
      Kernel.answers = [1]                       # Ice Beam, Knock Off, Toxic -> Knock Off
      Kernel.confirms = [false]
      RealideaPlayerServices.tutor
      assert_equal([[mon, 11]], $learned)
      assert_equal(["Ice Beam · ICE · 90", "Knock Off · DARK · 65", "Toxic · POISON · -", "Back"],
                   Kernel.shown[0][1])
      assert_equal("Mon can learn 3 moves. Which one?", Kernel.shown[0][0])
    end
  end

  def test_status_moves_show_no_power
    assert_equal("Toxic · POISON · -", RealideaPlayerServices.move_label(12))
  end

  def test_shop_categories_and_the_gate_notice
    in_game do
      $Trainer.numbadges = 1
      Kernel.answers = [0, 1, :cancel]
      RealideaPlayerServices.shops
      assert_equal([3], $mart[0])                # specialized items stay available
      assert(Kernel.shown.any? { |m, c| m.index("after your fourth badge") })
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

  def test_competitive_allowance_badge_boundaries
    [0, 0, 0, 0, 1, 1, 2, 2, nil, nil].each_with_index do |limit, badges|
      $Trainer.numbadges = badges
      assert_equal(limit, RealideaPlayerServices.competitive_limit)
    end
  end

  def test_claims_are_cumulative_across_badge_unlocks_and_each_copy_counts
    in_game do
      $Trainer.numbadges = 3
      assert_equal(false, RealideaPlayerServices.buy_competitive(1))
      $Trainer.numbadges = 4
      assert_equal(true, RealideaPlayerServices.buy_competitive(1))
      assert_equal(false, RealideaPlayerServices.buy_competitive(2))
      $Trainer.numbadges = 6
      assert_equal(true, RealideaPlayerServices.buy_competitive(1))
      assert_equal(false, RealideaPlayerServices.buy_competitive(2))
      assert_equal([1, 1], RealideaPlayerServices.competitive_claims)
      assert_equal([1, 1], $PokemonBag.items)
      assert_equal(84000, $Trainer.money)
      $Trainer.numbadges = 8
      5.times { assert_equal(true, RealideaPlayerServices.buy_competitive(2)) }
    end
  end

  def test_claim_history_survives_save_reload_and_selling_does_not_refund_it
    in_game do
      $Trainer.numbadges = 4
      RealideaPlayerServices.buy_competitive(1)
      $Trainer = Marshal.load(Marshal.dump($Trainer))
      $PokemonBag.items.clear
      assert_equal([1], RealideaPlayerServices.competitive_claims)
      assert_equal(false, RealideaPlayerServices.buy_competitive(2))
    end
  end

  def test_failed_purchase_and_noncompetitive_items_do_not_use_money_or_claims
    in_game do
      $Trainer.numbadges = 4
      assert_equal(false, RealideaPlayerServices.buy_competitive(3))
      $PokemonBag.full = true
      assert_equal(false, RealideaPlayerServices.buy_competitive(1))
      assert_equal(100000, $Trainer.money)
      $PokemonBag.full = false
      $Trainer.money = 7999
      assert_equal(false, RealideaPlayerServices.buy_competitive(1))
      assert_equal(7999, $Trainer.money)
      assert_equal([], RealideaPlayerServices.competitive_claims)
      assert_equal([], $PokemonBag.items)
    end
  end

  def test_competitive_shop_buys_one_copy_and_stops_at_allowance
    in_game do
      $Trainer.numbadges = 4
      Kernel.answers = [0]
      Kernel.confirms = [true]
      RealideaPlayerServices.shop([RealideaPlayerServices::COMPETITIVE])
      assert_equal([1], $PokemonBag.items)
      assert_equal([1], RealideaPlayerServices.competitive_claims)
      assert_equal(92000, $Trainer.money)
      assert(Kernel.shown.last[0].include?("1/1 total"))
    end
  end

  def test_cancelled_competitive_purchase_uses_no_claim
    in_game do
      $Trainer.numbadges = 4
      Kernel.answers = [0, :cancel]
      Kernel.confirms = [false]
      RealideaPlayerServices.competitive_shop
      assert_equal([], RealideaPlayerServices.competitive_claims)
      assert_equal([], $PokemonBag.items)
      assert_equal(100000, $Trainer.money)
    end
  end

  def test_leftovers_black_sludge_and_eviolite_are_specialized_and_early_stock
    assert(!RealideaPlayerServices::COMPETITIVE.include?(:LEFTOVERS))
    assert(!RealideaPlayerServices::COMPETITIVE.include?(:BLACKSLUDGE))
    assert(RealideaPlayerServices::SPECIALIZED.include?(:LEFTOVERS))
    assert(RealideaPlayerServices::SPECIALIZED.include?(:BLACKSLUDGE))
    assert(!RealideaPlayerServices::COMPETITIVE.include?(:EVIOLITE))
    assert(RealideaPlayerServices::SPECIALIZED.include?(:EVIOLITE))
    ITEMS[:LEFTOVERS] = 50; ITEMS[:BLACKSLUDGE] = 51; ITEMS[:EVIOLITE] = 52
    in_game do
      assert(RealideaPlayerServices.stock([RealideaPlayerServices::SPECIALIZED]).map { |r| r[0] }.include?(50))
      assert(RealideaPlayerServices.stock([RealideaPlayerServices::SPECIALIZED]).map { |r| r[0] }.include?(51))
      assert(RealideaPlayerServices.stock([RealideaPlayerServices::SPECIALIZED]).map { |r| r[0] }.include?(52))
      $Trainer.instance_variable_set(:@realidea_competitive_claims, [52, 1])
      assert_equal([1], RealideaPlayerServices.competitive_claims)
    end
  ensure
    ITEMS.delete(:LEFTOVERS); ITEMS.delete(:BLACKSLUDGE); ITEMS.delete(:EVIOLITE)
  end

  def test_boots_are_unrestricted_specialized_stock
    ITEMS[:HEAVYDUTYBOOTS] = 743
    in_game do
      $Trainer.numbadges = 0
      assert(!RealideaPlayerServices::COMPETITIVE.include?(:HEAVYDUTYBOOTS))
      assert(RealideaPlayerServices::SPECIALIZED.include?(:HEAVYDUTYBOOTS))
      assert(RealideaPlayerServices.stock([RealideaPlayerServices::SPECIALIZED]).any? { |r| r[0] == 743 })
    end
  ensure
    ITEMS.delete(:HEAVYDUTYBOOTS)
  end

  def test_equipped_items_no_longer_block_battles
    in_game do
      $Trainer.party = Array.new(6) { Mon.new(21) }
      $Trainer.party.each { |mon| mon.item = 1 }
      assert_equal(true, pbTrainerBattle(1, "Boss", "End"))
      assert_equal(true, pbDoubleTrainerBattle(1, "A", 0, "End", 2, "B", 0, "End"))
      assert_equal(1, customTrainerBattle(:trainer, "End"))
    end
  end

  def test_shop_claim_check_lists_purchase_history
    in_game do
      $Trainer.numbadges = 4
      RealideaPlayerServices.buy_competitive(2)
      Kernel.answers = [0, :cancel]
      RealideaPlayerServices.shops
      assert_equal("Which held items would you like?", Kernel.shown.first[0])
      assert(Kernel.shown.any? { |message, commands| message.include?("1/1 total") && message.include?("LIFEORB") })
    end
  end
end
