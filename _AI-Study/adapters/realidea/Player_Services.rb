# Player_Services — the code NPC teaches moves and sells held items, and the Move
# Reminder offers egg moves.
#
# Create Data/player_services.txt to enable. Realidea's bosses run a search AI and
# carry these moves and items from gym 1, so the player is not rationed the way Run &
# Bun rations its players (its limits exist to prop up a weak AI). See
# _AI-Study/PLAYER-CURVE.md section 5.
#
#   CODE NPC ("señorcodiguito", common event 79 -> pbCodeMysteryGift) opens a menu:
#     Badge rewards (N waiting)  only while something waits; Badge_Rewards' offer.
#     Teach a move    free. Pick a Pokémon, then a type, then any TM or tutor move of
#                     that type it can learn and does not know ("Ice Beam · ICE · 90") --
#                     every move in tm.dat, checked with the game's own form-aware
#                     isCompatibleWithMove?. The game has no move tutor of its own, and
#                     142 of its 194 TM/tutor moves had no source.
#     Remember moves  the game's Move Reminder, which now also lists egg moves.
#     Buy held items  three shops (battle items / type boosters and Gems / berries) at
#                     own prices (the PBS prices are placeholders: Choice Band 100). The
#                     strongest items open at GATE_BADGES badges.
#     Enter a code    the NPC's original code prompt.
#   MOVE REMINDER. pbGetRelearnableMoves also lists the line's egg moves (the baby's
#   and the root's eggEmerald.dat lists). Egg moves are stored per species, so the
#   Alolan Vulpix line (form 1) gets its own gen 7 list instead of fire Vulpix's.
#
# No map, event or PBS file is edited. Loads after Badge_Rewards.

module RealideaPlayerServices
  FILE = "Data/player_services.txt"
  GATE_BADGES = 2

  GATED = [:CHOICEBAND, :CHOICESCARF, :CHOICESPECS, :LIFEORB, :ASSAULTVEST, :LEFTOVERS,
           :FOCUSSASH, :WEAKNESSPOLICY, :EXPERTBELT]
  UTILITY = [:ROCKYHELMET, :AIRBALLOON, :BLACKSLUDGE, :EVIOLITE, :LIGHTCLAY, :WHITEHERB,
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

  SHOPS = [[_INTL("Battle items"), [GATED, UTILITY]],
           [_INTL("Type boosters and Gems"), [BOOSTERS]],
           [_INTL("Berries"), [BERRIES]]] rescue []

  # [[item id, price]] a shop sells at the current badge count (all shops if nil)
  def self.stock(lists=nil)
    out = []
    for list, price in PRICE
      next if lists && !lists.any? { |l| l.equal?(list) }
      next if list.equal?(GATED) && badges < GATE_BADGES
      for sym in list
        id = const(PBItems, sym)
        out.push([id, price]) if id
      end
    end
    return out
  end

  def self.shop(lists=nil)
    rows = stock(lists)
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
      idx = Kernel.pbMessage(_INTL("What are you after?"), names, names.length)
      return if idx < 0 || idx >= SHOPS.length
      lists = SHOPS[idx][1]
      if lists.any? { |l| l.equal?(GATED) } && badges < GATE_BADGES
        Kernel.pbMessage(_INTL("Choice items, Life Orb, Assault Vest, Leftovers, Focus Sash, Weakness Policy and Expert Belt come in after your second badge."))
      end
      shop(lists)
    end
  end

  # --- the tutor ---------------------------------------------------------------
  def self.tm_data
    @tm_data = load_data("Data/tm.dat") if !@tm_data
    return @tm_data
  end

  # every TM/tutor move this Pokémon can learn and does not know, by name
  def self.teachable(pokemon)
    data = tm_data
    out = []
    for move in 1...data.length
      next if !data[move]
      next if pokemon.hasMove?(move)
      out.push(move) if pokemon.isCompatibleWithMove?(move)
    end
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

  def self.move_type(move)
    return PBMoveData.new(move).type
  rescue
    return -1
  end

  def self.move_label(move)
    data = PBMoveData.new(move)
    power = data.basedamage > 1 ? data.basedamage.to_s : "-"
    return "#{PBMoves.getName(move)} · #{PBTypes.getName(data.type)} · #{power}"
  rescue
    return PBMoves.getName(move)
  end

  # pick a type, then a move of that type; nil when the player backs out
  def self.pick_move(pokemon, moves)
    loop do
      types = moves.collect { |m| move_type(m) }.uniq.sort_by { |t| (PBTypes.getName(t) rescue t.to_s) }
      names = types.collect { |t| n = moves.select { |m| move_type(m) == t }.length
                                  "#{(PBTypes.getName(t) rescue '?')} (#{n})" }
      names.push(_INTL("Back"))
      ti = Kernel.pbMessage(_INTL("{1} can learn {2} moves. Which type?", pokemon.name, moves.length),
                            names, names.length)
      return nil if ti < 0 || ti >= types.length
      of_type = moves.select { |m| move_type(m) == types[ti] }
      labels = of_type.collect { |m| move_label(m) }
      labels.push(_INTL("Back"))
      mi = Kernel.pbMessage(_INTL("Which move should {1} learn?", pokemon.name), labels, labels.length)
      return of_type[mi] if mi >= 0 && mi < of_type.length
    end
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
