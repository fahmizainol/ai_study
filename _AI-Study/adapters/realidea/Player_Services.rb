# Player_Services — the code NPC teaches moves and sells held items, and the Move
# Reminder offers egg moves.
#
# Create Data/player_services.txt to enable. Realidea's bosses run a search AI and
# carry these moves and items from gym 1. Competitive NPC purchases unlock at
# 4 badges (one cumulative purchase), 6 badges (two), and 8 badges (unlimited).
# Specialized items are unlimited. Claims persist in the trainer save; there is
# no equipped-item restriction. Consumed held items recover after battle. See
# _AI-Study/PLAYER-CURVE.md section 5.
#
#   CODE NPC ("señorcodiguito", common event 79 -> pbCodeMysteryGift) opens a menu:
#     Badge rewards (N waiting)  only while something waits; Badge_Rewards' offer.
#     Teach a move    free. Pick a Pokémon, then any TM or tutor move it can learn and
#                     does not know, one alphabetical list ("Ice Beam · ICE · 90") --
#                     every move in tm.dat, checked with the game's own form-aware
#                     isCompatibleWithMove?. The game has no move tutor of its own, and
#                     142 of its 194 TM/tutor moves had no source.
#     Remember moves  the game's Move Reminder, which now also lists egg moves.
#     Buy held items  competitive / specialized / type boosters and Gems / berries at
#                     own prices (the PBS prices are placeholders: Choice Band 100). The
#                     competitive items open at GATE_BADGES badges. The shop also
#                     shows the remaining cumulative purchase allowance.
#     Enter a code    the NPC's original code prompt.
#   MOVE REMINDER. pbGetRelearnableMoves also lists the line's egg moves (the baby's
#   and the root's eggEmerald.dat lists). Egg moves are stored per species, so the
#   Alolan Vulpix line (form 1) gets its own gen 7 list instead of fire Vulpix's.
#
# No map, event or PBS file is edited. Loads after Badge_Rewards.

module RealideaPlayerServices
  FILE = "Data/player_services.txt"
  GATE_BADGES = 4
  COMPETITIVE = [:CHOICEBAND, :CHOICESPECS, :CHOICESCARF, :LIFEORB,
                 :ASSAULTVEST, :FOCUSSASH]

  GATED = [:CHOICEBAND, :CHOICESCARF, :CHOICESPECS, :LIFEORB, :ASSAULTVEST, :LEFTOVERS,
           :FOCUSSASH, :WEAKNESSPOLICY, :EXPERTBELT]
  UTILITY = [:ROCKYHELMET, :AIRBALLOON, :HEAVYDUTYBOOTS, :BLACKSLUDGE, :EVIOLITE, :LIGHTCLAY, :WHITEHERB,
             :POWERHERB, :MENTALHERB, :EJECTBUTTON, :REDCARD, :PROTECTIVEPADS, :SAFETYGOGGLES,
             :MUSCLEBAND, :WISEGLASSES, :SCOPELENS, :RAZORCLAW, :WIDELENS, :ZOOMLENS,
             :BRIGHTPOWDER, :QUICKCLAW, :KINGSROCK, :SHELLBELL, :METRONOME, :BIGROOT,
             :FLAMEORB, :TOXICORB, :SHEDSHELL, :ADRENALINEORB, :TERRAINEXTENDER,
             :ELECTRICSEED, :GRASSYSEED, :MISTYSEED, :PSYCHICSEED, :HEATROCK, :DAMPROCK,
             :SMOOTHROCK, :ICYROCK, :FLOATSTONE, :STICKYBARB, :IRONBALL, :LAGGINGTAIL,
             :RINGTARGET, :GRIPCLAW, :BINDINGBAND, :DESTINYKNOT, :ABSORBBULB, :CELLBATTERY,
             :SNOWBALL, :LUMINOUSMOSS]
  BOOSTERS = [:SILKSCARF, :NEVERMELTICE, :SOFTSAND, :BLACKGLASSES, :POISONBARB,
              :MIRACLESEED, :SILVERPOWDER, :HARDSTONE, :SHARPBEAK, :BLACKBELT, :METALCOAT,
              :DRAGONFANG, :CHARCOAL, :MAGNET, :MYSTICWATER, :TWISTEDSPOON, :SPELLTAG,
              :PIXIEPLATE, :NORMALGEM, :FIREGEM, :WATERGEM, :ELECTRICGEM, :GRASSGEM, :ICEGEM,
              :FIGHTINGGEM, :POISONGEM, :GROUNDGEM, :FLYINGGEM, :PSYCHICGEM, :BUGGEM, :ROCKGEM,
              :GHOSTGEM, :DRAGONGEM, :DARKGEM, :STEELGEM, :FAIRYGEM]
  BERRIES = [:LUMBERRY, :SITRUSBERRY, :CHESTOBERRY, :LIECHIBERRY, :SALACBERRY, :PETAYABERRY,
             :GANLONBERRY, :APICOTBERRY, :CUSTAPBERRY, :OCCABERRY, :PASSHOBERRY, :WACANBERRY,
             :RINDOBERRY, :YACHEBERRY, :CHOPLEBERRY, :KEBIABERRY, :SHUCABERRY, :COBABERRY,
             :PAYAPABERRY, :TANGABERRY, :CHARTIBERRY, :KASIBBERRY, :HABANBERRY, :COLBURBERRY,
             :BABIRIBERRY, :CHILANBERRY, :ROSELIBERRY]
  # a Rare Candy is 4800 and a Full Restore 3000 in this game
  PRICE = [[GATED, 8000], [UTILITY, 3000], [BOOSTERS, 1000], [BERRIES, 500]]

  # Showdown's gen 7 egg list for Alolan Vulpix; Realidea only has fire Vulpix's.
  ALOLAN_VULPIX_EGG = [:AGILITY, :CHARM, :DISABLE, :ENCORE, :EXTRASENSORY, :FLAIL,
                       :FREEZEDRY, :HOWL, :HYPNOSIS, :MOONBLAST, :POWERSWAP, :SECRETPOWER,
                       :SPITE, :TAILSLAP]

  def self.enabled?
    return File.exist?(FILE)
  rescue
    return false
  end

  def self.badges
    return 0 if !$Trainer || !$Trainer.respond_to?("numbadges")
    return $Trainer.numbadges
  rescue
    return 0
  end

  def self.const(mod, sym)
    id = getConst(mod, sym)
    return (id && id > 0) ? id : nil
  rescue
    return nil
  end

  # --- the shop ----------------------------------------------------------------
  def self.price_of(sym)
    for list, price in PRICE
      return price if list.include?(sym)
    end
    return nil
  end

  SPECIALIZED = (GATED + UTILITY) - COMPETITIVE
  SHOPS = [[_INTL("Competitive claims"), [COMPETITIVE]],
           [_INTL("Specialized items (unlimited)"), [SPECIALIZED]],
           [_INTL("Type boosters and Gems"), [BOOSTERS]],
           [_INTL("Berries"), [BERRIES]]] rescue []

  # [[item id, price]] a shop sells at the current badge count (all shops if nil)
  def self.stock(lists=nil)
    out = []
    for list, price in PRICE
      for sym in list
        next if lists && !lists.any? { |l| l.include?(sym) }
        next if COMPETITIVE.include?(sym) && badges < GATE_BADGES
        id = const(PBItems, sym)
        out.push([id, price]) if id
      end
    end
    return out
  end

  def self.shop(lists=nil)
    return competitive_shop if lists && lists.any? { |list| list.equal?(COMPETITIVE) }
    rows = stock(lists).reject { |row| competitive_ids.include?(row[0]) }
    return if rows.empty?
    saved = $game_temp.mart_prices
    prices = {}
    for id, price in rows
      prices[id] = [price, price / 2]
    end
    $game_temp.mart_prices = prices
    begin
      pbPokemonMart(rows.collect { |r| r[0] }, _INTL("Take your pick."), true)
    ensure
      $game_temp.mart_prices = saved
    end
  end

  def self.shops
    loop do
      names = SHOPS.collect { |s| s[0] }
      names.push(_INTL("Back"))
      idx = Kernel.pbMessage(_INTL("Which held items would you like?"), names, names.length)
      return if idx < 0 || idx >= SHOPS.length
      lists = SHOPS[idx][1]
      if idx == 0 && badges < GATE_BADGES
        Kernel.pbMessage(_INTL("Competitive items unlock after your fourth badge. Specialized items are unlimited. You may buy 1 competitive item total at four badges, 2 total at six, and unlimited at eight."))
        next
      end
      shop(lists)
    end
  end

  # Cumulative NPC purchases, not equipped slots. Existing saves start at zero:
  # earlier purchases were not recorded and are not inferred from current inventory.
  def self.competitive_limit
    return nil if badges >= 8
    return 2 if badges >= 6
    return 1 if badges >= 4
    return 0
  end

  def self.competitive_ids
    return COMPETITIVE.collect { |sym| const(PBItems, sym) }.compact
  end

  def self.competitive_claims
    return [] if !$Trainer
    claims = $Trainer.instance_variable_get(:@realidea_competitive_claims)
    if !claims.is_a?(Array)
      claims = []
      $Trainer.instance_variable_set(:@realidea_competitive_claims, claims)
    end
    # Eviolite is now specialized; its earlier purchases no longer use a claim.
    eviolite = const(PBItems, :EVIOLITE)
    claims.delete(eviolite) if eviolite
    return claims
  end

  def self.allowance_text
    limit = competitive_limit
    used = competitive_claims.length
    return _INTL("Competitive items bought: {1}. Purchases are unlimited after eight badges. Specialized items are always unlimited.", used) if limit.nil?
    return _INTL("Competitive items bought: {1}/{2} total. Allowance: 1 after four badges, 2 after six, unlimited after eight. Specialized items are always unlimited.", used, limit)
  end

  def self.claim_history_text
    text = allowance_text
    for item in competitive_claims
      text += "\n" + PBItems.getName(item)
    end
    return text
  end

  # Single-copy transactions prevent a bulk purchase from exceeding the allowance.
  # Money and claims change only after the Bag accepted the selected item.
  def self.buy_competitive(item)
    return false if !$Trainer || !competitive_ids.include?(item)
    limit = competitive_limit
    return false if !limit.nil? && competitive_claims.length >= limit
    sym = COMPETITIVE.find { |s| const(PBItems, s) == item }
    price = price_of(sym)
    if $Trainer.money < price
      Kernel.pbMessage(_INTL("You do not have enough money."))
      return false
    end
    if !$PokemonBag || !$PokemonBag.pbStoreItem(item)
      Kernel.pbMessage(_INTL("There is no room in your Bag."))
      return false
    end
    $Trainer.money -= price
    competitive_claims.push(item)
    return true
  end

  def self.competitive_shop
    deliver_pending_restores
    loop do
      limit = competitive_limit
      if !limit.nil? && competitive_claims.length >= limit
        Kernel.pbMessage(claim_history_text)
        return
      end
      rows = stock([COMPETITIVE])
      return if rows.empty?
      commands = rows.collect { |id, price| _INTL("{1} - ${2}", PBItems.getName(id), price) }
      commands.push(_INTL("Back"))
      idx = Kernel.pbMessage(claim_history_text, commands, commands.length)
      return if !idx || idx < 0 || idx >= rows.length
      item, price = rows[idx]
      next if !Kernel.pbConfirmMessage(_INTL("Buy one {1} for ${2}? This uses one competitive claim.", PBItems.getName(item), price))
      if buy_competitive(item)
        Kernel.pbMessage(_INTL("Purchased {1}.", PBItems.getName(item)))
      end
    end
  end

  def self.pending_restores
    return [] if !$Trainer
    pending = $Trainer.instance_variable_get(:@realidea_pending_item_restores)
    if !pending.is_a?(Array)
      pending = []
      $Trainer.instance_variable_set(:@realidea_pending_item_restores, pending)
    end
    return pending
  end

  # Rare case: the original holder has acquired a different item and the Bag is
  # full. Keep the recovered item in the save until space is available.
  def self.deliver_pending_restores
    return if !$Trainer || !defined?($PokemonBag) || !$PokemonBag
    pending_restores.delete_if { |item| $PokemonBag.pbStoreItem(item) }
  end

  # --- the tutor ---------------------------------------------------------------
  def self.tm_data
    @tm_data = load_data("Data/tm.dat") if !@tm_data
    return @tm_data
  end

  # every TM/tutor move this Pokémon can learn and does not know, by name.
  #
  # Same answer as asking isCompatibleWithMove? of every move, without asking it:
  # the species path (pbSpeciesCompatible?) runs load_data("Data/tm.dat") on EVERY
  # call, so ~700 calls froze the game for tens of seconds after picking a Pokémon.
  # A form with its own list (MultipleForms getMoveCompatibility) is read directly,
  # exactly as isCompatibleWithMove? does; otherwise tm.dat is read once and cached.
  def self.compatible_moves(pokemon)
    forms = nil
    forms = MultipleForms.call("getMoveCompatibility", pokemon) if defined?(MultipleForms)
    if forms
      return forms.collect { |m| m.is_a?(Integer) ? m : const(PBMoves, m) }.compact
    end
    data = tm_data
    species = pokemon.species
    out = []
    for move in 1...data.length
      out.push(move) if data[move] && data[move].include?(species)
    end
    return out
  end

  def self.teachable(pokemon)
    out = compatible_moves(pokemon).select { |m| m > 0 && !pokemon.hasMove?(m) }.uniq
    return out.sort_by { |m| PBMoves.getName(m) }
  rescue
    return []
  end

  def self.choose_pokemon(prompt)
    chosen = -1
    pbFadeOutIn(99999) {
      scene = PokemonScreen_Scene.new
      screen = PokemonScreen.new(scene, $Trainer.party)
      screen.pbStartScene(prompt, false)
      chosen = screen.pbChoosePokemon
      screen.pbEndScene
    }
    return chosen >= 0 ? $Trainer.party[chosen] : nil
  end

  def self.move_label(move)
    data = PBMoveData.new(move)
    power = data.basedamage > 1 ? data.basedamage.to_s : "-"
    return "#{PBMoves.getName(move)} · #{PBTypes.getName(data.type)} · #{power}"
  rescue
    return PBMoves.getName(move)
  end

  # one alphabetical list of every teachable move; nil when the player backs out
  def self.pick_move(pokemon, moves)
    labels = moves.collect { |m| move_label(m) }
    labels.push(_INTL("Back"))
    mi = Kernel.pbMessage(_INTL("{1} can learn {2} moves. Which one?", pokemon.name, moves.length),
                          labels, labels.length)
    return (mi >= 0 && mi < moves.length) ? moves[mi] : nil
  end

  def self.tutor
    loop do
      pokemon = choose_pokemon(_INTL("Teach which Pokémon?"))
      return if !pokemon
      if pokemon.isEgg? || (pokemon.isShadow? rescue false)
        Kernel.pbMessage(_INTL("That one can't learn anything from me."))
        next
      end
      loop do
        moves = teachable(pokemon)
        if moves.empty?
          Kernel.pbMessage(_INTL("There's nothing I can teach {1}.", pokemon.name))
          break
        end
        move = pick_move(pokemon, moves)
        break if !move
        pbLearnMove(pokemon, move)
        break if !Kernel.pbConfirmMessage(_INTL("Teach {1} another move?", pokemon.name))
      end
    end
  end

  def self.remember
    loop do
      pokemon = choose_pokemon(_INTL("Which Pokémon should remember a move?"))
      return if !pokemon
      if pokemon.isEgg? || pbGetRelearnableMoves(pokemon).empty?
        Kernel.pbMessage(_INTL("{1} has nothing to remember.", pokemon.name))
        next
      end
      pbRelearnMoveScreen(pokemon)
    end
  end

  # --- the NPC -----------------------------------------------------------------
  def self.rewards_waiting
    return 0 if !defined?(RealideaBadgeRewards) || !RealideaBadgeRewards.enabled?
    return RealideaBadgeRewards.pending_badges.length
  rescue
    return 0
  end

  def self.menu(code_prompt)
    deliver_pending_restores
    if pending_restores.length > 0
      Kernel.pbMessage(_INTL("{1} recovered held item(s) are waiting. Make room in your Bag and speak to me again.", pending_restores.length))
    end
    loop do
      acts = []
      cmds = []
      waiting = rewards_waiting
      if waiting > 0
        acts.push(:rewards)
        cmds.push(_INTL("Badge rewards ({1} waiting)", waiting))
      end
      [[:tutor, _INTL("Teach a move")], [:remember, _INTL("Remember moves")],
       [:shops, _INTL("Buy held items")], [:code, _INTL("Enter a code")]].each do |a, c|
        acts.push(a)
        cmds.push(c)
      end
      cmds.push(_INTL("Leave"))
      idx = Kernel.pbMessage(_INTL("What do you need?"), cmds, cmds.length)
      case (idx >= 0 && idx < acts.length) ? acts[idx] : :leave
      when :rewards then RealideaBadgeRewards.offer
      when :tutor then tutor
      when :remember then remember
      when :shops then shops
      when :code then return code_prompt.call
      else return
      end
    end
  end

  # --- egg moves in the Move Reminder ------------------------------------------
  def self.egg_list(species)
    moves = []
    return moves if !species || species <= 0
    pbRgssOpen("Data/eggEmerald.dat", "rb") { |f|
      f.pos = (species - 1) * 8
      offset = f.fgetdw
      length = f.fgetdw
      if length > 0
        f.pos = offset
        length.times { moves.push(f.fgetw) }
      end
    }
    return moves
  rescue
    return moves
  end

  def self.alolan_vulpix_line?(pokemon)
    return false if !pokemon.respond_to?(:form) || pokemon.form != 1
    return pokemon.species == const(PBSpecies, :VULPIX) ||
           pokemon.species == const(PBSpecies, :NINETALES)
  end

  def self.egg_moves(pokemon)
    if alolan_vulpix_line?(pokemon)
      return ALOLAN_VULPIX_EGG.collect { |s| const(PBMoves, s) }.compact
    end
    # every stage of the line: an incense baby (Azurill) and the stage that hatches
    # without the incense (Marill) can each carry a list
    line = [pokemon.species]
    8.times do
      prev = pbGetPreviousForm(line.last)
      break if !prev || prev <= 0 || line.include?(prev)
      line.push(prev)
    end
    baby = pbGetBabySpecies(pokemon.species) rescue nil
    line.push(baby) if baby && baby > 0 && !line.include?(baby)
    out = []
    for sp in line.reverse
      out |= egg_list(sp)
    end
    return out
  rescue
    return []
  end
end

if defined?(pbCodeMysteryGift)
  alias player_services_orig_pbCodeMysteryGift pbCodeMysteryGift
  def pbCodeMysteryGift
    return player_services_orig_pbCodeMysteryGift if !RealideaPlayerServices.enabled?
    # the code prompt without Badge_Rewards' offer, which menu() makes first
    if defined?(badge_rewards_orig_pbCodeMysteryGift)
      code = proc { badge_rewards_orig_pbCodeMysteryGift }
    else
      code = proc { player_services_orig_pbCodeMysteryGift }
    end
    return RealideaPlayerServices.menu(code)
  end
end

if defined?(pbGetRelearnableMoves)
  alias player_services_orig_pbGetRelearnableMoves pbGetRelearnableMoves
  def pbGetRelearnableMoves(pokemon)
    moves = player_services_orig_pbGetRelearnableMoves(pokemon)
    return moves if !RealideaPlayerServices.enabled? || !pokemon || pokemon.isEgg?
    begin
      for m in RealideaPlayerServices.egg_moves(pokemon)
        moves.push(m) if m && m > 0 && !pokemon.hasMove?(m) && !moves.include?(m)
      end
    rescue
    end
    return moves
  end
end
