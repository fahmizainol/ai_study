# Badge_Rewards — Run & Bun-style badge rewards, handed out by the code NPC.
#
# Create Data/badge_rewards.txt to enable. It turns on three things:
#
#   1. REWARDS. "señorcodiguito", the code NPC in every Pokémon Center, runs common
#      event 79, which calls pbCodeMysteryGift. Before his code prompt he now offers
#      every reward the player's badge count has earned and not yet claimed: one
#      Pokémon from that badge's list, and/or mega stones. Rewards accumulate, so a
#      skipped Center costs nothing. Claims are stored in $Trainer.regalosmis -- the
#      array the game already keeps for used codes -- so old saves need no migration.
#      Codes still work: the original function runs after the offer.
#   2. EARLY MEGAS. From MEGA_BADGES badges, pbCanMegaEvolve? runs as if switch 512
#      were on. The game sets 512 only in Simon's Ruta 13 event, so without this no
#      one -- player or boss -- can mega before that point. The switch is flipped for
#      the length of the check only and restored, so no event ever sees it change.
#   3. A HINT after each badge whose reward is waiting.
#
# The section's own lines are in English; species and item names, and the game's own
# "obtained"/"received" messages, come from the game and stay in Spanish.
#
# Gifts arrive GIFT_BELOW_CAP levels under the current level cap, evolved as far as
# that level allows (pbCheckEvolution, then resetMoves). The table follows Run & Bun's
# Game Corner order one-to-one by badge; see _AI-Study/PLAYER-CURVE.md.
# No map, event or PBS file is edited.

module RealideaBadgeRewards
  FILE = "Data/badge_rewards.txt"
  MEGA_BADGES = 3
  GIFT_BELOW_CAP = 3
  CLAIM_PREFIX = "rnbbadge"
  MEGA_SWITCH = 512

  LATE_STONES = [:ABOMASITE, :AERODACTYLITE, :ALAKAZITE, :AUDINITE, :BANETTITE,
                 :BEEDRILLITE, :BLASTOISINITE, :BLAZIKENITE, :CAMERUPTITE, :GALLADITE,
                 :GARDEVOIRITE, :GENGARITE, :GLALITE, :HERACRONITE, :HOUNDOOMINITE,
                 :KANGASKHANITE, :LUCARIONITE, :MANECTITE, :MAWILITE, :MEDICHAMITE,
                 :PINSIRITE, :SCEPTILITE, :SHARPEDONITE, :SLOWBRONITE, :SWAMPERTITE,
                 :VENUSAURITE]

  # badge => { :pokemon => choices (pick 1), :stones => choices, :picks => how many }
  REWARDS = {
    1 => { :pokemon => [:ELEKID, :MAGBY, :SMOOCHUM] },
    2 => { :pokemon => [:HERACROSS, :PINSIR] },
    3 => { :pokemon => [:AXEW, :GIBLE],
           :stones => [:AMPHAROSITE, :AGGRONITE, :PIDGEOTITE], :picks => 1 },
    4 => { :pokemon => [:LARVITAR, :BELDUM],
           :stones => [:LOPUNNITE, :ALTARIANITE, :ABSOLITE], :picks => 1 },
    5 => { :pokemon => [:DRATINI, :BAGON, :DEINO],
           :stones => [:GARCHOMPITE, :SCIZORITE, :GYARADOSITE], :picks => 1 },
    6 => { :pokemon => [:GOOMY, :JANGMOO], :stones => LATE_STONES, :picks => 2 },
    7 => { :pokemon => [:LATIAS, :LATIOS, :RAIKOU, :ENTEI, :SUICUNE, :HEATRAN],
           :stones => LATE_STONES, :picks => 2 },
    8 => { :pokemon => [:MEW, :JIRACHI, :CELEBI, :VICTINI] }
  }

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

  # --- claims ------------------------------------------------------------------
  def self.claims
    return [] if !$Trainer || !$Trainer.respond_to?("regalosmis")
    return $Trainer.regalosmis
  end

  def self.claimed?(tag)
    return claims.include?(tag)
  end

  def self.claim(tag)
    claims.push(tag) if !claimed?(tag)
  end

  def self.pokemon_tag(badge)
    return "#{CLAIM_PREFIX}#{badge}p"
  end

  def self.stone_tag(badge, k)
    return "#{CLAIM_PREFIX}#{badge}s#{k}"
  end

  # --- what exists in this game's data -------------------------------------------
  def self.species_id(sym)
    id = getConst(PBSpecies, sym)
    return (id && id > 0) ? id : nil
  rescue
    return nil
  end

  def self.item_id(sym)
    id = getConst(PBItems, sym)
    return (id && id > 0) ? id : nil
  rescue
    return nil
  end

  def self.species_choices(badge)
    r = REWARDS[badge]
    return [] if !r || !r[:pokemon]
    return r[:pokemon].select { |s| species_id(s) }
  end

  # Stones not yet given by this badge or any other. The badge-6 and badge-7
  # rows share LATE_STONES, so a stone taken at 6 is not offered again at 7.
  def self.stone_choices(badge)
    r = REWARDS[badge]
    return [] if !r || !r[:stones]
    given = claims.select { |c| c.to_s.index("#{CLAIM_PREFIX}item:") == 0 }
    return r[:stones].select { |s| item_id(s) && !given.include?("#{CLAIM_PREFIX}item:#{s}") }
  end

  def self.stone_picks_left(badge)
    r = REWARDS[badge]
    return 0 if !r || !r[:stones]
    left = 0
    for k in 0...(r[:picks] || 1)
      left += 1 if !claimed?(stone_tag(badge, k))
    end
    return left
  end

  def self.pokemon_pending?(badge)
    return !species_choices(badge).empty? && !claimed?(pokemon_tag(badge))
  end

  def self.pending_badges
    out = []
    for b in 1..badges
      next if !REWARDS[b]
      stones = stone_picks_left(b) > 0 && !stone_choices(b).empty?
      out.push(b) if pokemon_pending?(b) || stones
    end
    return out
  end

  def self.pending?
    return !pending_badges.empty?
  end

  # --- the gift itself -----------------------------------------------------------
  def self.gift_level
    cap = nil
    cap = RealideaLevelCap.current if defined?(RealideaLevelCap)
    cap = pbBalancedLevel($Trainer.party) if cap.nil? && $Trainer && $Trainer.party.length > 0
    cap = 10 if cap.nil?
    level = cap - GIFT_BELOW_CAP
    level = 5 if level < 5
    level = PBExperience::MAXLEVEL if level > PBExperience::MAXLEVEL
    return level
  rescue
    return 5
  end

  # Evolves `poke` as far as its level allows, like a Pokémon raised to it.
  def self.grow(poke)
    4.times do
      nxt = pbCheckEvolution(poke)
      break if !nxt || nxt <= 0 || nxt == poke.species
      poke.species = nxt
      poke.name = PBSpecies.getName(nxt)
      poke.calcStats
    end
    poke.resetMoves
    poke.calcStats
    return poke
  end

  def self.build(sym, level)
    id = species_id(sym)
    return nil if !id
    poke = PokeBattle_Pokemon.new(id, level, $Trainer)
    return grow(poke)
  end

  # --- the offer, inside pbCodeMysteryGift ---------------------------------------
  def self.choose(message, symbols, namer)
    names = symbols.collect { |s| namer.call(s) }
    names.push(_INTL("Later"))
    idx = Kernel.pbMessage(message, names, names.length)
    return nil if idx.nil? || idx < 0 || idx >= symbols.length
    return symbols[idx]
  end

  def self.species_name(sym)
    return PBSpecies.getName(species_id(sym))
  end

  def self.item_name(sym)
    return PBItems.getName(item_id(sym))
  end

  # Returns false when the player said "later", which ends the whole offer.
  def self.offer_badge(badge)
    if pokemon_pending?(badge)
      sym = choose(_INTL("For badge {1}, pick a Pokémon.", badge),
                   species_choices(badge), proc { |s| species_name(s) })
      return false if !sym
      poke = build(sym, gift_level)
      return false if !poke
      return false if !pbAddPokemon(poke)   # boxes full: nothing is claimed
      claim(pokemon_tag(badge))
    end
    r = REWARDS[badge]
    if r && r[:stones]
      for k in 0...(r[:picks] || 1)
        next if claimed?(stone_tag(badge, k))
        choices = stone_choices(badge)
        break if choices.empty?
        sym = choose(_INTL("For badge {1}, pick a Mega Stone.", badge),
                     choices, proc { |s| item_name(s) })
        return false if !sym
        Kernel.pbReceiveItem(item_id(sym))
        claim(stone_tag(badge, k))
        claim("#{CLAIM_PREFIX}item:#{sym}")
      end
    end
    return true
  end

  def self.offer
    return if !enabled? || !pending?
    Kernel.pbMessage(_INTL("By the way... I have something for you for your badges."))
    for b in pending_badges
      break if !offer_badge(b)
    end
  end

  # --- early megas -----------------------------------------------------------------
  def self.mega_unlocked?
    return enabled? && badges >= MEGA_BADGES
  end

  # Runs the block with switch 512 read as on, without a refresh or an event ever
  # seeing it: the raw array is set and restored around the call.
  def self.with_mega_switch
    data = nil
    data = $game_switches.instance_variable_get(:@data) if $game_switches
    if !mega_unlocked? || !data || data[MEGA_SWITCH]
      return yield
    end
    old = data[MEGA_SWITCH]
    data[MEGA_SWITCH] = true
    begin
      return yield
    ensure
      data[MEGA_SWITCH] = old
    end
  end
end

if defined?(pbCodeMysteryGift)
  alias badge_rewards_orig_pbCodeMysteryGift pbCodeMysteryGift
  def pbCodeMysteryGift
    begin
      RealideaBadgeRewards.offer
    rescue
      # a reward failure must never cost the player the code prompt
    end
    return badge_rewards_orig_pbCodeMysteryGift
  end
end

if defined?(renderBadgeAnimation)
  alias badge_rewards_orig_renderBadgeAnimation renderBadgeAnimation
  def renderBadgeAnimation(badge_number=0)
    ret = badge_rewards_orig_renderBadgeAnimation(badge_number)
    begin
      if RealideaBadgeRewards.enabled? && RealideaBadgeRewards.pending?
        Kernel.pbMessage(_INTL("The code guy at the Pokémon Center has something for you."))
      end
    rescue
    end
    return ret
  end
end

class PokeBattle_Battle
  alias badge_rewards_orig_pbCanMegaEvolve? pbCanMegaEvolve?

  def pbCanMegaEvolve?(index)
    return RealideaBadgeRewards.with_mega_switch { badge_rewards_orig_pbCanMegaEvolve?(index) }
  end
end
