module GameData
  class Role
    attr_reader :id
    attr_reader :id_number
    attr_reader :real_name

    DATA = {}

    extend ClassMethods
    include InstanceMethods

    def self.load; end
    def self.save; end

    def initialize(hash)
      @id           = hash[:id]
      @id_number    = hash[:id_number]    || -1
      @real_name    = hash[:name]         || "Unnamed"
    end

    # @return [String] the translated name of this Role
    def name
      return _INTL(@real_name)
    end
  end
  class Trainer
    def to_trainer
      # Determine trainer's name
      tr_name = self.name
      Settings::RIVAL_NAMES.each do |rival|
        next if rival[0] != @trainer_type || !$game_variables[rival[1]].is_a?(String)
        tr_name = $game_variables[rival[1]]
        break
      end
      # Create trainer object
      trainer = NPCTrainer.new(tr_name, @trainer_type)
      trainer.id        = $Trainer.make_foreign_ID
      trainer.items     = @items.clone
      trainer.lose_text = self.lose_text
      # Create each Pokémon owned by the trainer
      randPkmn = Randomizer.trainers
      trainer_exclusions = $game_switches[906] ? nil : [:RIVAL1,:RIVAL2,:RIVAL3,:LEADER_Brock,:LEADER_Misty,:LEADER_Surge,:LEADER_Erika,:LEADER_Sabrina,:LEADER_Blaine,:LEADER_Winslow,:LEADER_Jackson,:OFFCORP,:DEFCORP,:PSYCORP,:ROCKETBOSS,:CHAMPION,:ARMYBOSS,:NAVYBOSS,:AIRFORCEBOSS,:GUARDBOSS,:CHANCELLOR,:DOJO_Luna,:DOJO_Apollo,:DOJO_Jasper,:DOJO_Maloki,:DOJO_Juliet,:DOJO_Adam,:DOJO_Wendy,:LEAGUE_Turner,:LEAGUE_Gordon,:LEAGUE_Astrid,:LEAGUE_Winslow,:LEAGUE_Eugene,:LEAGUE_Armand,:LEAGUE_Hazel,:LEAGUE_Vincent,:POKEMONTRAINER_Joseph]
      if randPkmn.nil? || randPkmn == 0 || (trainer_exclusions && trainer_exclusions.include?(@trainer_type)) || @version == 4 || @version == 6 || @version > 99
        @pokemon.each do |pkmn_data|
          species = GameData::Species.get(pkmn_data[:species]).species
          f = GameData::Species.get_species_form_data_from_species(pkmn_data[:species])
          pkmn = f.nil? ? Pokemon.new(species, pkmn_data[:level], trainer, false) : Pokemon.new(f, pkmn_data[:level], trainer, false)
          trainer.party.push(pkmn)
          # Set Pokémon's properties if defined
          if pkmn_data[:form]
            pkmn.forced_form = pkmn_data[:form] if MultipleForms.hasFunction?(species, "getForm")
            pkmn.form_simple = pkmn_data[:form]
          elsif !pkmn_data[:form] && [:LYCANROC,:BASCULEGION].include?(species) && f.nil?
            pkmn.forced_form = 0
            pkmn.form_simple = 0
          end
          pkmn.item = pkmn_data[:item]
          if pkmn_data[:moves] && pkmn_data[:moves].length > 0
            pkmn_data[:moves].each { |move| pkmn.learn_move(move) }
          else
            pkmn.reset_moves
          end
          if !pkmn_data[:roles]
            pkmn.roles = pkmn.assign_roles
          else
            for i in pkmn_data[:roles]
              pkmn.add_role(i)
            end
          end
          pkmn.ability_index = pkmn_data[:ability_index]
          pkmn.ability = pkmn_data[:ability]
          pkmn.gender = pkmn_data[:gender] || ((trainer.male?) ? 0 : 1)
          pkmn.shiny = (pkmn_data[:shininess]) ? true : false
          pkmn.square_shiny = (pkmn_data[:square_shiny]) ? true : false
          if pkmn_data[:nature]
            pkmn.nature = pkmn_data[:nature]
          else
            pkmn.nature = pkmn.generate_beneficial_nature
          end
          PBAI.log_misc("=====> Nature for #{pkmn.species.name}: #{pkmn.nature_id}")
          calculated_evs = pkmn.generate_beneficial_evs
          GameData::Stat.each_main do |s|
            if pkmn_data[:iv]
              pkmn.iv[s.id] = pkmn_data[:iv][s.id]
            else
              iv_cap = (Pokemon::IV_STAT_LIMIT / 3)*$Trainer.badge_count
              pkmn.iv[s.id] = [rand(iv_cap), Pokemon::IV_STAT_LIMIT].min
              pkmn.iv[s.id] = 31 if $Trainer.badge_count >= 4
              pkmn.iv[s.id] = 0 if (pkmn.roles.include?(:TRICKROOMSETTER) || ([:QUIET,:BRAVE,:SASSY,:RELAXED].include?(pkmn.nature))) && s.id == :SPEED
              pkmn.iv[s.id] = 31 if ($game_switches[Settings::DISABLE_EVS] || $game_switches[LvlCap::Expert])
            end
            if ($game_switches[Settings::DISABLE_EVS] || $game_switches[LvlCap::Expert])
              pkmn.ev[s.id] = 0
            else
              if pkmn_data[:ev]
                pkmn.ev[s.id] = pkmn_data[:ev][s.id]
              else
                pkmn.ev[s.id] = calculated_evs[s.id]
              end
            end
          end
          pkmn.happiness = pkmn_data[:happiness] ? pkmn_data[:happiness] : 255
          pkmn.name = pkmn_data[:name] if pkmn_data[:name] && !pkmn_data[:name].empty?
          if pkmn_data[:shadowness]
            pkmn.makeShadow
            pkmn.update_shadow_moves(true)
            pkmn.shiny = false
          end
          pkmn.poke_ball = pkmn_data[:poke_ball] if pkmn_data[:poke_ball]
          pkmn.calc_stats
        end
      else
        tr_name = "Blue" if [:RIVAL1,:RIVAL2].include?(@trainer_type)
        idx = -1
        for i in randPkmn[:trainer]
          idx += 1
          break if i[0] == @trainer_type && i[1] == tr_name && i[2] == @version
        end
        randSpec = randPkmn[:pokemon][:species][idx]
        randLvl = randPkmn[:pokemon][:level][idx]
        lvl = -1
        randSpec.each do |pkmn_data|
          lvl += 1
          species = GameData::Species.get(pkmn_data).species
            pkmn = Pokemon.new(species, randLvl[lvl], trainer, false)
            trainer.party.push(pkmn)
            pkmn.reset_moves
            pkmn.calc_stats
        end
      end
      return trainer
    end
  end
end

GameData::Role.register({
  :id           => :PHYSICALWALL,
  :id_number    => 0,
  :name         => _INTL("Physical Wall")
})

GameData::Role.register({
  :id           => :SPECIALWALL,
  :id_number    => 1,
  :name         => _INTL("Special Wall")
})

GameData::Role.register({
  :id           => :STALLBREAKER,
  :id_number    => 2,
  :name         => _INTL("Stallbreaker")
})

GameData::Role.register({
  :id           => :PHYSICALBREAKER,
  :id_number    => 3,
  :name         => _INTL("Physical Breaker")
})

GameData::Role.register({
  :id           => :SPECIALBREAKER,
  :id_number    => 4,
  :name         => _INTL("Special Breaker")
})

GameData::Role.register({
  :id           => :TANK,
  :id_number    => 5,
  :name         => _INTL("Tank")
})

GameData::Role.register({
  :id           => :LEAD,
  :id_number    => 5,
  :name         => _INTL("Lead")
})

GameData::Role.register({
  :id           => :CLERIC,
  :id_number    => 7,
  :name         => _INTL("Cleric")
})

GameData::Role.register({
  :id           => :REVENGEKILLER,
  :id_number    => 8,
  :name         => _INTL("Revenge Killer")
})

GameData::Role.register({
  :id           => :WINCON,
  :id_number    => 9,
  :name         => _INTL("Win Condition")
})

GameData::Role.register({
  :id           => :TOXICSTALLER,
  :id_number    => 10,
  :name         => _INTL("Toxic Staller")
})

GameData::Role.register({
  :id           => :SETUPSWEEPER,
  :id_number    => 11,
  :name         => _INTL("Setup Sweeper")
})

GameData::Role.register({
  :id           => :HAZARDREMOVAL,
  :id_number    => 12,
  :name         => _INTL("Hazard Removal")
})

GameData::Role.register({
  :id           => :DEFENSIVEPIVOT,
  :id_number    => 13,
  :name         => _INTL("Defensive Pivot")
})

GameData::Role.register({
  :id           => :SPEEDCONTROL,
  :id_number    => 14,
  :name         => _INTL("Speed Control")
})

GameData::Role.register({
  :id           => :SCREENS,
  :id_number    => 15,
  :name         => _INTL("Screens")
})

GameData::Role.register({
  :id           => :NONE,
  :id_number    => 16,
  :name         => _INTL("None")
})

GameData::Role.register({
  :id           => :TARGETALLY,
  :id_number    => 17,
  :name         => _INTL("Target Ally")
})

GameData::Role.register({
  :id           => :REDIRECTION,
  :id_number    => 18,
  :name         => _INTL("Redirection")
})

GameData::Role.register({
  :id           => :TRICKROOMSETTER,
  :id_number    => 19,
  :name         => _INTL("Trick Room Setter")
})

GameData::Role.register({
  :id           => :OFFENSIVEPIVOT,
  :id_number    => 20,
  :name         => _INTL("Offensive Pivot")
})

GameData::Role.register({
  :id           => :STATUSABSORBER,
  :id_number    => 21,
  :name         => _INTL("Status Absorber")
})

GameData::Role.register({
  :id           => :WEATHERTERRAIN,
  :id_number    => 22,
  :name         => _INTL("Weather/Terrain Setter")
})

GameData::Role.register({
  :id           => :TRAPPER,
  :id_number    => 23,
  :name         => _INTL("Trapper")
})

GameData::Role.register({
  :id           => :PHAZER,
  :id_number    => 24,
  :name         => _INTL("Phazer")
})

GameData::Role.register({
  :id           => :SUPPORT,
  :id_number    => 25,
  :name         => _INTL("Support")
})

GameData::Role.register({
  :id           => :WEATHERTERRAINABUSER,
  :id_number    => 26,
  :name         => _INTL("Weather/Terrain Abuser")
})

GameData::Role.register({
  :id           => :FEAR,
  :id_number    => 27,
  :name         => _INTL("FEAR")
})

GameData::Role.register({
  :id           => :CRIT,
  :id_number    => 28,
  :name         => _INTL("Crit")
})

class Pokemon
  def has_role?(role)
    x = []
    for i in @roles
      x.push(i)
      if role.is_a?(Array)
        if role.include?(i)
          return true
        end
      end
    end
    return x.include?(role) && !role.is_a?(Array)
  end

  def generate_beneficial_nature
    PBAI.log_misc("Generating beneficial nature...")
    baseStats = species_data.base_stats
    if @roles.include?(:PHYSICALBREAKER)
      if baseStats[:ATTACK] >= 100 && baseStats[:SPEED] > baseStats[:ATTACK]
        return :JOLLY
      else
        return :ADAMANT
      end
    elsif @roles.include?(:SPECIALBREAKER)
      if baseStats[:SPECIAL_ATTACK] >= 100 && baseStats[:SPEED] > baseStats[:SPECIAL_ATTACK]
        return :TIMID
      else
        return :MODEST
      end
    elsif @roles.include?(:SETUPSWEEPER)
      if baseStats[:ATTACK] > baseStats[:SPECIAL_ATTACK] && baseStats[:ATTACK] > baseStats[:SPEED]
        return :ADAMANT
      elsif baseStats[:ATTACK] < baseStats[:SPECIAL_ATTACK] && baseStats[:SPECIAL_ATTACK] > baseStats[:SPEED]
        return :MODEST
      else
        return (baseStats[:ATTACK] > baseStats[:SPECIAL_ATTACK]) ? :JOLLY : :TIMID
      end
    elsif @roles.include?([:DEFENSIVEPIVOT,:TANK,:TOXICSTALLER,:PHAZER,:SCREENS,:TRICKROOMSETTER])
      return (baseStats[:DEFENSE] > baseStats[:SPECIAL_DEFENSE] ? :RELAXED : :SASSY)
    elsif @roles.include?(:PHYSICALWALL)
      if baseStats[:ATTACK] > baseStats[:SPECIAL_ATTACK]
        return :IMPISH
      else
        return :BOLD
      end
    elsif @roles.include?(:SPECIALWALL)
      if baseStats[:ATTACK] > baseStats[:SPECIAL_ATTACK]
        return :CAREFUL
      else
        return :CALM
      end
    end
    phys = 0
    spec = 0
    @moves.each do |move|
      phys += 1 if move.category == 0
      spec += 1 if move.category == 1
    end
    if phys > spec
      return :ADAMANT
    else
      return :MODEST
    end
  end

  def generate_beneficial_evs
    badges = $Trainer.badge_count
    evs = [0,64,128,256]
    ev_table = {
      :HP => 0,
      :ATTACK => 0,
      :DEFENSE => 0,
      :SPEED => 0,
      :SPECIAL_ATTACK => 0,
      :SPECIAL_DEFENSE => 0
    }
    return ev_table if badges == 0
    nature = GameData::Nature.get(@nature).id
    attack_boosting = [:ADAMANT,:BRAVE,:NAUGHTY,:LONELY].include?(nature)
    spatk_boosting = [:MODEST,:QUIET,:RASH,:MILD].include?(nature)
    speed_boosting = [:TIMID,:JOLLY,:HASTY,:NAIVE].include?(nature)
    def_boosting = [:BOLD,:IMPISH,:RELAXED].include?(nature)
    spdef_boosting = [:CALM,:CAREFUL,:SASSY].include?(nature)
    if attack_boosting
      boosted = :ATTACK
    elsif spatk_boosting
      boosted = :SPECIAL_ATTACK
    elsif speed_boosting
      boosted = :SPEED
    elsif def_boosting
      boosted = :DEFENSE
    elsif spdef_boosting
      boosted = :SPECIAL_DEFENSE
    end
    if speed_boosting
      secondary = @attack > @spatk ? :ATTACK : :SPECIAL_ATTACK
      secondary = :ATTACK if @roles.include?(:PHYSICALBREAKER)
      secondary = :SPECIAL_ATTACK if @roles.include?(:SPECIALBREAKER)
      tertiary = :HP
    else
      secondary = baseStats[:HP] > baseStats[:SPEED] ? :HP : :SPEED
      tertiary = secondary == :SPEED ? :HP : :SPEED
    end
    if badges < 4
      ev_table[boosted] = (evs[badges])/2
      ev_table[secondary] = evs[badges] - ev_table[boosted]
    else
      ev_table[boosted] = 252
      ev_table[secondary] = 252
      ev_table[tertiary] = 4
    end
    PBAI.log_misc("=====> EVs for #{species_data.name}: #{ev_table}")
    return ev_table
  end

  def generate_competitive_ivs(field=:None)
    pokemon.max_all_ivs
    if pokemon.roles.include?(:SPECIALBREAKER) && !pokemon.moves.any? { |move| move.category == 0  }
      pokemon.ivs[:ATTACK] = 0
    end
    if pokemon.roles.include?(:TRICKROOMSETTER) || pokemon.hasMove?(:GYROBALL) || field == :Dream
      pokemon.ivs[:SPEED] = 0
    end
  end

  def assign_roles
    roles = []
    physical_moves = 0
    special_moves = 0
    status_moves = 0
    @moves.each do |move|
      physical_moves += 1 if move.category == 0
      special_moves += 1 if move.category == 1
      status_moves += 1 if move.category == 2
    end
    roles.push(:PHYSICALBREAKER) if physical_moves >= 2
    roles.push(:SPECIALBREAKER) if special_moves >= 2
    for move in @moves
      m = GameData::Move.get(move.id).id
      roles.push(:SETUPSWEEPER) if PBAI::AI_Move.setup_move?(m)
      roles.push(:WEATHERTERRAIN) if PBAI::AI_Move.weather_terrain_move?(m)
      roles.push(:CLERIC) if [:WISH,:HEALBELL,:AROMATHERAPY].include?(m)
      roles.push(:OFFENSIVEPIVOT) if [:UTURN,:VOLTSWITCH,:FLIPTURN].include?(m)
      roles.push(:DEFENSIVEPIVOT) if [:PARTINGSHOT,:CHILLYRECEPTION,:TELEPORT,:SHEDTAIL].include?(m)
      roles.push(:SPEEDCONTROL) if [:ICYWIND,:THUNDERWAVE,:GLARE,:BULLDOZE,:DOLDRUMS,:ROCKTOMB,:POUNCE,:NUZZLE,:ELECTROWEB,:LOWSWEEP,:TAILWIND,:STUNSPORE].include?(m)
      roles.push(:STALLBREAKER) if m == :TAUNT
      roles.push(:REDIRECTION) if [:FOLLOWME,:ALLYSWITCH,:RAGEPOWDER].include?(m)
      roles.push(:SUPPORT) if [:HELPINGHAND,:WIDEGUARD,:MATBLOCK].include?(m)
      roles.push(:HAZARDREMOVAL) if [:RAPIDSPIN,:MORTALSPIN,:TIDYUP,:DEFOG].include?(m)
      roles.push(:SCREENS) if [:LIGHTSCREEN,:REFLECT,:AURORAVEIL].include?(m)
      roles.push(:TOXICSTALLER) if m == :TOXIC
      roles.push(:LEAD) if [:STEALTHROCK,:SPIKES,:TOXICSPIKES,:STICKYWEB,:COMETSHARDS].include?(m)
      roles.push(:TRICKROOMSETTER) if m == :TRICKROOM
      roles.push(:TANK) if [:RECOVER,:ROOST,:MOONLIGHT,:MORNINGSUN,:SHOREUP,:PACKIN,:SOFTBOILED,:SYNTHESIS,:HEALORDER].include?(m) && !roles.include?(:SETUPSWEEPER)
      roles.push(:PHAZER) if [:ROAR,:DRAGONTAIL,:WHIRLWIND,:HAZE,:FREEZYFROST].include?(m)
      roles.push(:STATUSABSORBER) if m == :FACADE
    end
    case @ability
    when :DRIZZLE,:DROUGHT,:SNOWWARNING,:SANDSTREAM,:SANDSPIT,:ELECTRICSURGE,:PSYCHICSURGE,:GRASSYSURGE,:MISTYSURGE,:SEEDSOWER,:EQUINOX,:GALEFORCE,:NIGHTFALL,:URBANCLOUD,:TOXICSURGE,:HAILSTORM,:ACCLIMATE,:RAGINGSEA
      roles.push(:WEATHERTERRAIN)
    when :SWIFTSWIM,:DRYSKIN,:HYDRATION,:RAINDISH,:SOLARPOWER,:CHLOROPHYLL,:PROTOSYNTHESIS,:SLUSHRUSH,:ICEBODY,:ICEFACE,:SANDRUSH,:SANDVEIL,
      :SANDFORCE,:SNOWCLOAK,:FLOWERGIFT,:FORECAST,:SURGESURFER,:MEADOWRUSH,:BRAINBLAST,:HARVEST,:STEAMPOWERED,:TOXICRUSH,:SLUDGERUSH,:NOCTEMBOOST,
      :STARSPRINT,:STARSALVE,:WINDRIDER,:BACKDRAFT,:GRASSPELT,:WINDPOWER
      roles.push(:WEATHERTERRAINABUSER)
    when :DEFIANT,:COMPETITIVE,:SOULHEART,:MOXIE,:ASONEICE,:ASONEGHOST,:GRIMNEIGH,:CHILLINGNEIGH,:LIONSPRIDE,:BEASTBOOST,:DOWNLOAD,:CONTRARY
      roles.push(:SETUPSWEEPER)
      roles.push(:SPECIALBREAKER) if [:COMPETITIVE,:SOULHEART,:ASONEGHOST,:GRIMNEIGH,:LIONSPRIDE].include?(@ability)
      roles.push(:PHYSICALBREAKER) if [:DEFIANT,:MOXIE,:ASONEICE,:CHILLINGNEIGH].include?(@ability)
    when :GUTS,:NATURALCURE,:FAIRYBUBBLE,:HOPEFULTOLL
      roles.push(:STATUSABSORBER)
    when :DIMENSIONSHIFT
      roles.push(:TRICKROOMSETTER)
    end
    if (self.species == :SWAMPERT && self.item == :SWAMPERTITE) || (self.species == :TOXTRICITY && self.item == :TOXTRICITITE) ||
      (self.species == :ABOMASNOW && self.item == :ABOMASITE) || (self.species == :VENUSAUR2 && self.item == :WVENUSAURITE)
      roles.push(:WEATHERTERRAINABUSER) unless roles.include?(:WEATHERTERRAINABUSER)
    end
    if (self.species == :CHARIZARD && self.item == :CHARIZARDITEY) || (self.species == :RILLABOOM && self.item == :RILLABOOMITE)
      roles.push(:WEATHERTERRAIN) unless roles.include?(:WEATHERTERRAIN)
    end
    roles.push(:NONE) if roles == []
    return roles
  end
end

module GameData
  class Species
    def self.get_species_form_data_from_species(species)
      return nil if !species
      validate species => [Symbol, self, String]
      species_base = species.species if species.is_a?(self)
      species_form = (DATA[species].nil?) ? species_base : species
      return (DATA.has_key?(species_form)) ? DATA[species_form] : nil
    end
  end
end