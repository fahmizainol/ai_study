class PBAI
  def self.log_threat(battler,score,msg)
    if $DEBUG
      if score >= 0
        $msg_log_threat += "\n[AI Threat Assessment: #{battler.pokemon.name}] +#{score}: " + msg
      else
        $msg_log_threat += "\n[AI Threat Assessment: #{battler.pokemon.name}] #{score}: " + msg
      end
    end
  end

  def self.burn_threat
    $threat_flags[:burn] = true
  end

  def self.frostbite_threat
    $threat_flags[:frostbite] = true
  end

  def self.paralyze_threat
    $threat_flags[:paralyze] = true
  end

  def self.threat_score(user,target)
    return $threat_scores[user.index][target.index]
  end

  def self.preserve_threats(battle,battler,target,targets)
    dmg = 0
    fast = 0
    score = 0
    able_targets = []
    targets.each { |mon| able_targets.push(mon) if mon && !mon.pokemon.fainted?  }
    able_targets.each do |opp|
      PBAI.log_ai("#{battler.pokemon.name} has killing moves vs #{opp.pokemon.name}? #{battler.has_killing_move?(opp)}")
      dmg += 1 if battler.has_killing_move?(opp)
      fast += 1 if battler.effective_speed > opp.effective_speed
    end
    if dmg == able_targets.length
      if fast == able_targets.length
        score = 20
        PBAI.log_threat(battler,-20,"We can fast KO every mon in the opposing party")
      else
        score = -10
        PBAI.log_threat(battler,-10,"We can KO every mon in the opposing party")
      end
    else
      score -= dmg
      PBAI.log_threat(battler,dmg*-1,"We can KO #{dmg} mons in the opposing party")
    end
    if dmg == 0 && fast > 0
      score -= fast
      PBAI.log_threat(battler,fast*-1,"We outspeed #{fast} mons in the opposing party")
    end
    return score
  end

  def self.threat_damage(battler,target)
    score = 0
    if battler.fast_kill?(target)
      score -= 3
      PBAI.log_threat(target.battler,-3,"for us having fast kill")
    elsif battler.slow_kill?(target)
      score -= 2
      PBAI.log_threat(target.battler,-2,"for us having slow kill")
    end
    if battler.target_fast_kill?(target)
      score += 5
      PBAI.log_threat(target.battler,5,"for target having fast kill")
    elsif battler.target_has_fast_2hko?(target)
      score += 3
      PBAI.log_threat(target.battler,3,"for target having fast 2HKO")
    elsif battler.target_has_killing_move?(target)
      score += 2
      PBAI.log_threat(target.battler,2,"for target having slow kill")
    end
    if !battler.has_killing_move?(target) && !battler.target_has_killing_move?(target)
      if battler.faster_than?(target)
        score -= 1
        PBAI.log_threat(target.battler,-1,"for us outspeeding")
      else
        score += 1
        PBAI.log_threat(target.battler,1,"for target outspeeding")
      end
    end
    return score
  end

  class ThreatHandler
    @@GeneralCode = []
    @@SelfCode = []
    @@SingleCode = []

    def self.add(&code)
      @@GeneralCode << code
    end

    def self.add_self(&code)
      @@SelfCode << code
    end

    def self.add_single(&code)
      @@SingleCode << code
    end

    def self.set(list,score,ai,battler,target)
      return score if list.nil?
      $test_trigger = true
      list = [list] if !list.is_a?(Array)
      list.each do |code|
      next if code.nil?
        newscore = code.call(score,ai,battler,target)
        score = newscore if newscore.is_a?(Numeric)
      end
      $test_trigger = false
      return score
    end

    def self.trigger(score,ai,battler,target)
      return self.set(@@GeneralCode,score,ai,battler,target)
    end

    def self.trigger_self(score,ai,battler,target)
      return self.set(@@SelfCode,score,ai,battler,target)
    end

    def self.trigger_single(score,ai,battler,target)
      return self.set(@@SingleCode,score,ai,battler,target)
    end
  end
end

# Assessing threats to immediate battler
PBAI::ThreatHandler.add do |score,ai,battler,target|
  score += PBAI.threat_damage(battler,target)
  next score
end
=begin
# Specific Ability Threat Scoring
PBAI::ThreatHandler.add do |score,ai,battler,target|
  score += PBAI.rank_ability(target)
  next score
end

# Assessing threats based on player party roles
PBAI::ThreatHandler.add do |score,ai,battler,target|
  party = ai.battle.pbParty(target.index)
  roles = PBAI.role_assignment(target,party)
  if roles[target.pokemon].include?(:SETUPSWEEPER)
    importance = [1,2,4,6,8,10]
    add = target.set_up_score < 0 ? 0 : importance[target.set_up_score]
    add = 0 if add == nil
    add == 10 if target.set_up_score > 5
    score += add
    PBAI.log_threat(add,"for being a setup sweeper.")
    if target.set_up_score > 0 && target.stages[:SPEED] > 0
      PBAI.paralyze_threat
      PBAI.log_ai("#{target.pokemon.name} is now flagged to attempt to be paralyzed.")
    end
  end
  if roles[target.pokemon].include?([:PHYSICALBREAKER,:SPECIALBREAKER])
    count = 0
    target.moves.each {|move| count += 1 if battler.get_calc(target,move) >= battler.hp}
    score += count
    PBAI.log_threat(count,"for being a breaker and having moves that can KO us.")
    if roles[target.pokemon].include?(:PHYSICALBREAKER) && target.can_burn?
      PBAI.burn_threat
      PBAI.log_ai("#{target.pokemon.name} is now flagged to attempt to be burned.")
    end
    if roles[target.pokemon].include?(:SPECIALBREAKER) && target.can_freeze?
      PBAI.frostbite_threat
      PBAI.log_ai("#{target.pokemon.name} is now flagged to attempt to be frostbitten.")
    end
  end
  if roles[target.pokemon].include?([:CLERIC,:TANK,:PHYSICALWALL,:SPECIALWALL])
    score -= 1
    PBAI.log_threat(-1,"for being a defensive role and not posing as much a threat.")
  end
  if roles[target.pokemon].include?(:SPEEDCONTROL) && battler.has_role?([:SETUPSWEEPER,:WINCON])
    score += 2
    PBAI.log_threat(2,"for being able to cripple our sweeper or win condition.")
  end
  if roles[target.pokemon].include?(:LEAD)
    my_party = ai.battle.pbParty(battler.index)
    c = 0
    my_party.each { |p| c += 1 if p && !p.egg? && !p.fainted? }
    add = (c/2).floor
    score += add
    PBAI.log_threat(add,"for being a hazard lead and us having #{c} party members left.")
  end
  plus = 0
  case target.pokemon.ability_id
  when :SHARPNESS
    target.moves.each {|move| plus += 1 if move.slicingMove?}
  when :STRONGJAW
    target.moves.each {|move| plus += 1 if move.bitingMove?}
  when :GAVELPOWER
    target.moves.each {|move| plus += 1 if move.hammerMove?}
  when :MEGALAUNCHER
    target.moves.each {|move| plus += 1 if move.pulseMove?}
  when :BALLISTIC
    target.moves.each {|move| plus += 1 if move.bombMove?}
  when :TIGHTFOCUS
    target.moves.each {|move| plus += 1 if move.beamMove?}
  when :IRONFIST
    target.moves.each {|move| plus += 1 if move.punchingMove?}
  when :TOUGHCLAWS
    target.moves.each {|move| plus += 1 if move.contactMove?}
  when :ROCKHEAD
    target.moves.each {|move| plus += 1 if move.headMove?}
  when :PUNKROCK
    target.moves.each {|move| plus += 1 if move.soundMove?}
  end
  score += plus
  if plus > 0
    PBAI.log_threat(plus,"for each move that abuses #{target.pokemon.ability.name}")
  end
  next score
end
=end
# Assessing threats to entire party: ALWAYS LAST TO ASSIGN HIGHEST SCORE TO A MON THAT CAN WIPE THE ENTIRE TEAM
PBAI::ThreatHandler.add_single do |score,ai,battler,target|
  party = ai.battle.pbParty(battler.index)
  $threat_index = battler.index
  ded = 0
  party.each do |pkmn|
    next if pkmn.fainted?
    proj = ai.pokemon_to_projection(pkmn)
    ded += 1 if proj.target_fast_kill?(target)
  end
  score += ded
  PBAI.log_threat(battler,ded,"for each party member the Pokémon can outspeed and kill.") if ded > 0
  ouch = 0
  party.each {|p| ouch += 1 if p && !p.egg? && !p.fainted? }
  if ded == ouch
    PBAI.log_threat(battler,50-score,"for being able to outspeed and wipe the entire party.")
    score = 50
  end
  $threat_index = nil
  PBAI.debug_threat
  next score
end

#==========================================
# Preserving Win Conditions
#==========================================

PBAI::ThreatHandler.add_self do |score,ai,battler,target|
  party = ai.battle.pbParty(target.index)
  targets = []
  party.each {|pkmn| targets.push(ai.pokemon_to_projection(pkmn)) if pkmn && !pkmn.egg? && !pkmn.fainted?}
  score += PBAI.preserve_threats(ai.battle,battler,target,targets)
  PBAI.debug_threat
  next score
end

=begin
def self.rank_ability(target)
    ability_list = {
    8 => [:INTREPIDSWORD,:DAUNTLESSSHIELD,:COMPOSURE,:HUGEPOWER,:TERASHELL,:WONDERGUARD,:BATTLEBOND,:DIMENSIONSHIFT,:REVERSEROOM,:EMBODYASPECT,
      :EMBODYASPECT_1,:EMBODYASPECT_2,:EMBODYASPECT_3,:NEUTRALIZINGGAS,:SOULHEART,:BEASTBOOST,:DELTASTREAM,:PRIMORDIALSEA,:DESOLATELAND,:PUREPOWER,
      :SPEEDBOOST,:SHADOWTAG,:DEATHGRIP,:POWERCONSTRUCT,:INNARDSOUT,:ACCLIMATE],
    7 => [:ADAPTABILITY,:DARKAURA,:FAIRYAURA,:FAIRYBUBBLE,:GAIAFORCE,:GRIMNEIGH,:CHILLINGNEIGH,:MOXIE,:ASONEICE,:ASONEGHOST,
      :DOWNLOAD,:FOREWARN,:REGENERATOR,:LIONSPRIDE,:STEAMENGINE,:MEDUSOID,:CONTRARY,:SIMPLE,:ICESCALES,:FURCOAT,:WATERBUBBLE,:ANGERSHELL],
    6 => [:MAGICGUARD,:MAGICBOUNCE,:RESURGENCE,:SPLINTER,:WEBWEAVER,:SHADOWGUARD,:HAUNTED,:ECHOCHAMBER,:AMBIDEXTROUS,:MINDSEYE,:SWORDOFRUIN,
      :VESSELOFRUIN,:BEADSOFRUIN,:TABLETSOFRUIN,:LIBERO,:PROTEAN,:UNAWARE,:GORILLATACTICS,:TOXICDEBRIS,:PROTOSYNTHESIS,:QUARKDRIVE,:PURIFYINGSALT,
      :GOODASGOLD,:SUPREMEOVERLORD,:ZEROTOHERO,:FLUFFY,:PRISMARMOR,:SHADOWSHIELD,:MULTISCALE,:TRIAGE,:PRANKSTER,:SHEERFORCE,:SOLIDROCK,:FILTER,
      :ARENATRAP,:POISONHEAL,:ASTRALCLOAK],
    5 => [:TIGHTFOCUS,:ROCKHEAD,:SHARPNESS,:GAVELPOWER,:UNSHAKEN,:HOPEFULTOLL,:STEPMASTER,:VOCALFRY,:FEVERPITCH,:PASTELVEIL,
      :WINDPOWER,:WINDRIDER,:FLOWERGIFT,:GUTS,:TOXICBOOST,:ENTYMATE,:PIXILATE,:GALVANIZE,:REFRIGERATE,:AERILATE,:GUARDDOG,:OPPORTUNIST,:COSTAR,
      :PUNKROCK,:DRIZZLE,:DROUGHT,:SNOWWARNING,:SANDSTREAM,:ELECTRICSURGE,:GRASSYSURGE,:MISTYSURGE,:PSYCHICSURGE,:SEEDSOWER,:THERMALEXCHANGE,
      :SANDSPIT,:SANDRUSH,:MEADOWRUSH,:BRAINBLAST,:SWIFTSWIM,:SLUSHRUSH,:CHLOROPHYLL,:SURGESURFER,:DAZZLING,:ARMORTAIL,:QUEENLYMAJESTY,
      :DISGUISE,:GOOEY,:TOUGHCLAWS,:MEGALAUNCHER,:STRONGJAW,:FLAREBOOST,:DEFIANT,:MARVELSCALE,:EARTHEATER,:SKILLLINK,:COMPETITIVE,:STAMINA,:EQUINOX,
      :TOXICSURGE,:NIGHTFALL,:URBANCLOUD,:DIMENSIONBLOCK],
    4 => [:INTIMIDATE,:MINDGAMES,:SCALER,:UNTAINTED,:SUBWOOFER,:LEGENDARMOR,:VAMPIRIC,:BALLISTIC,:SCRAPPY,:QUICKFEET,
      :DRYSKIN,:DRAGONSMAW,:TRANSISTOR,:IMPATIENT,:NEUROFORCE,:BERSERK,:SANDFORCE,:LIGHTNINGROD,:STORMDRAIN,:WATERCOMPACTION,:WELLBAKEDBODY,:SAPSIPPER,
      :WATERABSORB,:FLASHFIRE,:VOLTABSORB,:IRONFIST,:TRACE,:LEVITATE,:BATTLEARMOR,:SHELLARMOR,:TECHNICIAN,:LIQUIDVOICE,:COMMANDER],
    3 => [:SUPERSWEETSYRUP,:TRASHSHIELD,:NITRIC,:STEAMPOWERED,:UNKNOWNPOWER,:ROCKYPAYLOAD,:STEELWORKER,:ELECTROMORPHOSIS,:STEELYSPIRIT,:EMERGENCYEXIT,
      :WIMPOUT,:MUMMY,:WANDERINGSPIRIT,:LINGERINGAROMA,:NOGUARD,:SERENEGRACE,:THICKFAT,:SHEDSKIN,:HEATPROOF,:COMATOSE,:SLAYER],
    2 => [:ICEBODY,:POWERSPOT,:BACKDRAFT,:CUDCHEW,:RIPEN,:PERISHBODY,:MIRRORARMOR,:AROMAVEIL,:TURBOBLAZE,:TERAVOLT,:MOLDBREAKER,:IMMUNITY,:ANGERPOINT,
      :HARVEST,:IMPOSTER,:CORROSION,:ICEFACE,:GULPMISSILE,:STATIC,:FLAMEBODY,:IRONBARBS,:ROUGHSKIN],
    1 => [:CACOPHONY,:SCREENCLEANER,:CURIOUSMEDICINE,:PROPELLERTAIL,:STALWART,:JUSTIFIED,:RATTLED,:FRIENDGUARD,:WATERVEIL,
      :CURSEDBODY,:QUICKDRAW,:MIMICRY],
    -1 => [:STALL,:TRUANT,:BALLFETCH,:DEFEATIST,:KLUTZ,:SLOWSTART,:HONEYGATHER,:MYCELIUMMIGHT]
  }
    for rank in ability_list.keys
      ability_list[rank].each do |ability|
        next if !target.hasActiveAbility?(ability)
        PBAI.log_threat(rank,"for ability threat ranking.")
        return rank
      end
    end
    return 0
  end

  def self.role_assignment(target,party)
    roles = {}
    weather = {
    :Rain => [:DRIZZLE],
    :Sun => [:DROUGHT],
    :Snow => [:SNOWWARNING],
    :Sandstorm => [:SANDSTREAM,:SANDSPIT]
    }
    terrain = {
      :Electric => [:ELECTRICSURGE],
      :Grassy => [:GRASSYSURGE,:SEEDSOWER],
      :Misty => [:MISTYSURGE],
      :Psychic => [:PSYCHICSURGE]
    }
    weather_match = {
      :Rain => [:SWIFTSWIM,:RAINDISH,:DRYSKIN,:FORECAST,:STEAMPOWERED],
      :Sun => [:SOLARPOWER,:CHLOROPHYLL,:PROTOSYNTHESIS,:FLOWERGIFT,:HARVEST,:FORECAST,:STEAMPOWERED],
      :Snow => [:ICEBODY,:SLUSHRUSH,:SNOWCLOAK,:ICEFACE,:FORECAST],
      :Sandstorm => [:SANDRUSH,:SANDVEIL,:SANDFORCE,:FORECAST]
    }
    terrain_match = {
      :Electric => [:SURGESURFER,:QUARKDRIVE],
      :Grassy => [:MEADOWRUSH],
      :Misty => [:NOCTEMBOOST],
      :Psychic => [:BRAINBLAST]
    }
    party.each do |pkmn|
      roles[pkmn] = pkmn.assign_roles
    end
    if roles[target.pokemon].include?(:WEATHERTERRAIN) && party.any? {|mon| !mon.fainted? && roles[mon].include?(:WEATHERTERRAINABUSER)}
      for key in weather.keys
        if target.pokemon.ability_id == weather[key]
          party.each do |m|
            if m.ability_id == weather_match[key]
              score += 5
              PBAI.log_threat(5,"for being a weather setter and having a weather abuser in the party.")
            end
          end
        end
      end
      for key2 in terrain.keys
        if target.pokemon.ability_id == terrain[key2]
          party.each do |m2|
            if m2.ability_id == terrain_match[key2]
              score += 5
              PBAI.log_threat(5,"for being a terrain setter and having a weather abuser in the party.")
            end
          end
        end
      end
    end
    if roles[target.pokemon].include?(:WEATHERTERRAINABUSER) && party.any? {|pk| !pk.fainted? && roles[pk].include?(:WEATHERTERRAIN)}
      for key3 in weather_match.keys
        if target.pokemon.ability_id == weather_match[key3]
          party.each do |m|
            if m.ability_id == weather[key3]
              score += 5
              PBAI.log_threat(5,"for being a weather abuser and having a weather setter in the party.")
            end
          end
        end
      end
      for key4 in terrain_match.keys
        if target.pokemon.ability_id == terrain_match[key4]
          party.each do |m2|
            if m2.ability_id == terrain[key4]
              score += 5
              PBAI.log_threat(5,"for being a terrain abuser and having a weather setter in the party.")
            end
          end
        end
      end
    end
    PBAI.log_ai("Roles assigned to #{target.pokemon.name}: #{roles[target.pokemon]}")
    return roles
  end
=end