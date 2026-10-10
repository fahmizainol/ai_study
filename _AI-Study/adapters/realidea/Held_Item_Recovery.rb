# Restore the player's consumed held items after any ordinary battle ends.
# Enabled with Player_Services. No effect on consumption, Recycle, Harvest,
# Pickup or item transfers while the battle is in progress.

module RealideaHeldItemRecovery
  def self.owned_count(item)
    count = 0
    if $Trainer && $Trainer.party
      for pokemon in $Trainer.party
        count += 1 if pokemon && pokemon.item == item
      end
    end
    count += $PokemonBag.pbQuantity(item) if defined?($PokemonBag) && $PokemonBag
    count += RealideaPlayerServices.pending_restores.find_all { |id| id == item }.length
    return count
  end
end

class PokeBattle_Battle
  # Only real player-owned Pokemon participating in this battle are eligible.
  # New captures and NPC partners never become recovery sources.
  def realidea_begin_item_recovery
    @realidea_item_recovery = nil
    return if !RealideaPlayerServices.enabled? || !$Trainer || !$Trainer.party
    records = []
    for pokemon in $Trainer.party
      next if !pokemon || pokemon.isEgg? || pokemon.item <= 0
      next if !@party1 || !@party1.any? { |member| member.equal?(pokemon) }
      records.push([pokemon, pokemon.item])
    end
    totals = {}
    for pokemon, item in records
      totals[item] = RealideaHeldItemRecovery.owned_count(item)
    end
    @realidea_item_recovery = [records, totals, {}]
  end

  def realidea_note_consumed_item(item)
    return if !@realidea_item_recovery || item <= 0
    records, totals, consumed = @realidea_item_recovery
    return if !totals.has_key?(item)
    consumed[item] = (consumed[item] || 0) + 1
  end

  def realidea_finish_item_recovery
    snapshot = @realidea_item_recovery
    @realidea_item_recovery = nil           # a second cleanup cannot duplicate items
    return if !snapshot
    records, totals, consumed = snapshot
    for pokemon, item in records
      next if (consumed[item] || 0) <= 0
      next if pokemon.item == item
      # Recycle, Harvest, Pickup or a retained item may already have recovered it.
      next if RealideaHeldItemRecovery.owned_count(item) >= totals[item]
      if pokemon.item == 0
        pokemon.setItem(item)
      elsif !defined?($PokemonBag) || !$PokemonBag || !$PokemonBag.pbStoreItem(item)
        RealideaPlayerServices.pending_restores.push(item)
      end
      consumed[item] -= 1
    end
  end

  alias realidea_recovery_orig_pbStartBattle pbStartBattle
  def pbStartBattle(*args)
    realidea_begin_item_recovery
    begin
      return realidea_recovery_orig_pbStartBattle(*args)
    ensure
      realidea_finish_item_recovery
    end
  end
end

class PokeBattle_Battler
  alias realidea_recovery_orig_pbConsumeItem pbConsumeItem
  def pbConsumeItem(*args)
    @battle.realidea_note_consumed_item(self.item)
    return realidea_recovery_orig_pbConsumeItem(*args)
  end
end
