require "test/unit"
require "tmpdir"

def _INTL(text, *args); text; end

RecoveryTrainer = Struct.new(:party)
class RecoveryMon
  attr_accessor :item, :itemInitial, :itemRecycle
  def initialize(item)
    @item = @itemInitial = item
    @itemRecycle = 0
  end
  def isEgg?; false; end
  def setItem(item); @item = item; end
end

class RecoveryBag
  attr_accessor :items, :full
  def initialize; @items = []; @full = false; end
  def pbQuantity(item); @items.count(item); end
  def pbStoreItem(item)
    return false if @full
    @items.push(item)
    return true
  end
end

class PokeBattle_Battle
  attr_accessor :action
  def initialize(party); @party1 = party; end
  def pbStartBattle(result=1)
    @action.call(self)
    # The real engine resets held items to itemInitial during pbEndOfBattle.
    for pokemon in $Trainer.party
      pokemon.setItem(pokemon.itemInitial)
      pokemon.itemInitial = pokemon.itemRecycle = 0
    end
    return result
  end
end

class PokeBattle_Battler
  attr_reader :pokemon
  def initialize(battle, pokemon); @battle = battle; @pokemon = pokemon; end
  def item; @pokemon.item; end
  def pbConsumeItem(recycle=true, pickup=true)
    @pokemon.itemRecycle = item if recycle
    @pokemon.itemInitial = 0 if @pokemon.itemInitial == item
    @pokemon.item = 0
    return :consumed
  end
end

load File.expand_path("../adapters/realidea/Player_Services.rb", __dir__)
load File.expand_path("../adapters/realidea/Held_Item_Recovery.rb", __dir__)

class HeldItemRecoveryTest < Test::Unit::TestCase
  def setup
    $Trainer = RecoveryTrainer.new([])
    $PokemonBag = RecoveryBag.new
  end

  def in_game(enabled=true)
    Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, "Data"))
      File.write(File.join(directory, "Data/player_services.txt"), "") if enabled
      Dir.chdir(directory) { yield }
    end
  end

  def battle_with(items, result=1, enabled=true)
    $Trainer.party = items.map { |item| RecoveryMon.new(item) }
    battle = PokeBattle_Battle.new($Trainer.party)
    battle.action = proc { |b| yield b, $Trainer.party }
    in_game(enabled) { assert_equal(result, battle.pbStartBattle(result)) }
    return battle
  end

  def consume(battle, pokemon, *args)
    assert_equal(:consumed, PokeBattle_Battler.new(battle, pokemon).pbConsumeItem(*args))
    assert_equal(0, pokemon.item, "consumption must still apply within the battle")
  end

  def test_consumed_items_restore_after_win_loss_escape_capture_and_abort
    [1, 2, 3, 4, 0].each do |result|
      battle_with([10], result) { |battle, party| consume(battle, party[0]) }
      assert_equal(10, $Trainer.party[0].item)
    end
  end

  def test_nonrecyclable_consumption_also_restores
    battle_with([10]) { |battle, party| consume(battle, party[0], false, false) }
    assert_equal(10, $Trainer.party[0].item)
  end

  def test_duplicate_copies_restore_only_the_consumed_holder
    battle_with([10, 10]) { |battle, party| consume(battle, party[1]) }
    assert_equal([10, 10], $Trainer.party.map { |p| p.item })
    assert_equal([], $PokemonBag.items)
  end

  def test_recycle_or_harvest_does_not_duplicate_an_already_recovered_item
    battle_with([10]) do |battle, party|
      consume(battle, party[0])
      party[0].item = party[0].itemInitial = 10
    end
    assert_equal([10], $Trainer.party.map { |p| p.item })
    assert_equal([], $PokemonBag.items)
  end

  def test_pickup_transfer_does_not_duplicate_the_original_item
    battle_with([10, 0]) do |battle, party|
      consume(battle, party[0])
      party[1].item = party[1].itemInitial = 10
    end
    assert_equal([0, 10], $Trainer.party.map { |p| p.item })
  end

  def test_repeated_consumption_does_not_create_extra_copies
    battle_with([10]) do |battle, party|
      consume(battle, party[0])
      party[0].item = party[0].itemInitial = 10
      consume(battle, party[0])
    end
    assert_equal([10], $Trainer.party.map { |p| p.item })
    assert_equal([], $PokemonBag.items)
  end

  def test_a_newly_acquired_item_is_not_a_recovery_source
    battle_with([0]) do |battle, party|
      party[0].item = 10
      consume(battle, party[0])
    end
    assert_equal(0, $Trainer.party[0].item)
  end

  def test_npc_partner_is_not_a_recovery_source
    partner = RecoveryMon.new(20)
    battle_with([0]) { |battle, party| consume(battle, partner) }
    assert_equal(0, partner.item)
    assert_equal(0, $Trainer.party[0].item)
  end

  def test_existing_bag_copies_do_not_mask_a_consumed_held_copy
    $PokemonBag.items = [10, 10]
    battle_with([10]) { |battle, party| consume(battle, party[0]) }
    assert_equal(10, $Trainer.party[0].item)
    assert_equal([10, 10], $PokemonBag.items)
  end

  def test_replaced_item_is_preserved_and_recovery_goes_to_bag
    battle_with([10]) do |battle, party|
      consume(battle, party[0])
      party[0].item = party[0].itemInitial = 20
    end
    assert_equal(20, $Trainer.party[0].item)
    assert_equal([10], $PokemonBag.items)
  end

  def test_full_bag_keeps_pending_recovery_in_save_until_npc_can_deliver
    $PokemonBag.full = true
    battle_with([10]) do |battle, party|
      consume(battle, party[0])
      party[0].item = party[0].itemInitial = 20
    end
    assert_equal(20, $Trainer.party[0].item)
    assert_equal([10], RealideaPlayerServices.pending_restores)
    $Trainer = Marshal.load(Marshal.dump($Trainer))
    $PokemonBag.full = false
    RealideaPlayerServices.deliver_pending_restores
    assert_equal([10], $PokemonBag.items)
    assert_equal([], RealideaPlayerServices.pending_restores)
  end

  def test_disabled_services_leave_vanilla_consumption_in_place
    battle_with([10], 1, false) { |battle, party| consume(battle, party[0]) }
    assert_equal(0, $Trainer.party[0].item)
  end

  def test_cleanup_is_idempotent
    battle = battle_with([10]) { |b, party| consume(b, party[0]) }
    battle.realidea_finish_item_recovery
    assert_equal(10, $Trainer.party[0].item)
    assert_equal([], $PokemonBag.items)
  end

  def test_exception_still_recovers_consumed_items
    $Trainer.party = [RecoveryMon.new(10)]
    battle = PokeBattle_Battle.new($Trainer.party)
    battle.action = proc do |b|
      consume(b, $Trainer.party[0])
      raise "aborted"
    end
    in_game { assert_raise(RuntimeError) { battle.pbStartBattle } }
    assert_equal(10, $Trainer.party[0].item)
  end
end
