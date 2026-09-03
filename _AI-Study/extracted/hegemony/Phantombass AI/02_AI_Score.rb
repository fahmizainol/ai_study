class PBAI
  def self.log_score(move,score,msg)
    if $DEBUG
      mod = score >= 0 ? "+" : ""
      $msg_log_score += "\n[AI][#{move.name}][#{mod}#{score}] " + msg
    end
  end
  class ScoreHandler
    @@GeneralCode = []
    @@MoveCode = {}
    @@StatusCode = []
    @@DamagingCode = []
    @@FinalCode = []

    def self.add_status(&code)
      @@StatusCode << code
    end

    def self.add_damaging(&code)
      @@DamagingCode << code
    end

    def self.add_final(&code)
      @@FinalCode << code
    end

    def self.add(*moves, &code)
      if moves.size == 0
        @@GeneralCode << code
      else
        moves.each do |move|
          if move.is_a?(Symbol) # Specific move
            id = GameData::Move.get(move).id
            raise "Invalid move #{move}" if id.nil? || id == 0
            @@MoveCode[id] = code
          elsif move.is_a?(String) # Function code
            @@MoveCode[move] = code
          end
        end
      end
    end

    def self.trigger(list, score, ai, user, target, move)
      return score if list.nil?
      list = [list] if !list.is_a?(Array)
      list.each do |code|
        next if code.nil?
        newscore = code.call(score, ai, user, target, move)
        score = newscore if newscore.is_a?(Numeric)
      end
      return score
    end

    def self.trigger_general(score, ai, user, target, move)
      return self.trigger(@@GeneralCode, score, ai, user, target, move)
    end

    def self.trigger_status_moves(score, ai, user, target, move)
      return self.trigger(@@StatusCode, score, ai, user, target, move)
    end

    def self.trigger_damaging_moves(score, ai, user, target, move)
      return self.trigger(@@DamagingCode, score, ai, user, target, move)
    end

    def self.trigger_final(score, ai, user, target, move)
      return self.trigger(@@FinalCode, score, ai, user, target, move)
    end

    def self.trigger_move(move, score, ai, user, target)
      id = move.id
      id = move.function if !@@MoveCode[id]
      return self.trigger(@@MoveCode[id], score, ai, user, target, move)
    end
  end
end

#=============================================================================#
#                                                                             #
# All Moves                                                                   #
#                                                                             #
#=============================================================================#

#Prefer sound moves if a substitute is up or if holding Throat Spray
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if !move.soundMove?
  roles = []
    for i in user.roles
      roles.push(i)
    end
  dmg = user.get_calc_self(target, move)
  if target.effects[PBEffects::Substitute] > 0 && dmg >= target.hp
    score += 3
    PBAI.log_score(move,3,"+ 3 for being able to kill behind a Substitute")
  end
  if user.hasActiveItem?(:THROATSPRAY)
    score += 2
    PBAI.log_score(move,2,"+ 2 for activating Throat Spray")
    if user.has_role?([:SETUPSWEEPER,:WINCON,:SPECIALBREAKER])#.include?(roles)
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a setup mon or special breaker")
    end
  end
  next score
end

#Prefer status moves if you have Truant on your truant turn
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if !move.statusMove?
  if user.hasActiveAbility?(:TRUANT) && user.effects[PBEffects::Truant]
    score += 10
    PBAI.log_score(move,10,"+ 10 for using status moves on the Truant turn")
  end
  next score
end

# Prefer priority moves that deal enough damage to knock the target out.
# Use previous damage dealt to determine if it deals enough damage now,
# or make a rough estimate.
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  # Apply this logic only for priority moves
  next if move.priority <= 0 || move.function == "0D4" || move.statusMove? || target.priority_blocking? || (ai.battle.field.terrain == :Psychic && target.affectedByTerrain?)
  next if move.statusMove?
  # Calculate the damage this priority move will do.
  # The AI kind of cheats here, because this takes all items, berries, abilities, etc. into account.
  # It is worth for the effect though; the AI using a priority move to prevent
  # you from using one last move before you faint.
  dmg = user.get_calc_self(target, move)
  if dmg >= target.battler.hp
    # We have the previous damage this user has done with this move.
    # Use the average of the previous damage dealt, and if it's more than the target's hp,
    # we can likely use this move to knock out the target.
    PBAI.log_score(move,3,"+ 3 for priority move with damage (#{dmg}) >= target hp (#{target.battler.hp})")
    score += 3
  end
  if target.hp <= target.totalhp/4 && dmg >= target.hp && !$spam_block_flags[:no_priority_flag].include?(target)
    score += 1
    PBAI.log_score(move,1,"+ 1 for attempting to kill the target with priority")
  end
  status = 0
  target.moves.each {|m| status += 1 if m.statusMove?}
  if status == 0 && [:SUCKERPUNCH,:THUNDERCLAP].include?(move.id)
    score += 1
    PBAI.log_score(move,1,"+ 1 because target has no status moves")
  end
  if PBAI.threat_score(user,target) == 50 && ![:FAKEOUT,:FIRSTIMPRESSION].include?(move.id)
    score += 6
    PBAI.log_score(move,6,"+ 6 because the target outspeeds and OHKOs our entire team.")
  end
  if user.target_fast_kill?(target)
    score += PBAI.threat_score(user,target)
    PBAI.log_score(move,PBAI.threat_score(user,target),"* #{PBAI.threat_score(user,target)} to factor in threat score")
  end
  next score
end

# Encourage using fixed-damage moves if the fixed damage is more than the target has HP
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if !move.is_a?(PokeBattle_FixedDamageMove) || move.function == "070" || move.function == "0D4"
  dmg = move.pbFixedDamage(user, target)
  dmg = 0 if dmg == nil
  if dmg >= target.hp
    score += 2
    PBAI.log_score(move,2,"+ 2 for this move's fixed damage being enough to knock out the target")
  end
  next score
end

# Prefer moves that are usable while the user is asleep
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  # If the move is usable while asleep, and if the user won't wake up this turn
  # Kind of cheating, but insignificant. This way the user can choose a more powerful move instead
  if move.usableWhenAsleep?
    if user.asleep? && user.statusCount > 1
      score += 2
      PBAI.log_score(move,2,"+ 2 for being able to use this move while asleep")
    else
      score -= 1
      PBAI.log_score(move,1,"- 1 for this move will have no effect")
    end
  end
  next score
end


# Prefer moves that can thaw the user if the user is frozen
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  # If the user is frozen and the move thaws the user
  if user.frozen? && move.thawsUser?
    score += 2
    PBAI.log_score(move,2,"+ 2 for being able to thaw the user")
  end
  next score
end

# Encourage using trapping moves, since they're generally weak
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  if move.function == "0CF" # Trapping Move
    if target.effects[PBEffects::Trapping] == 0 # The target is not yet trapped
      score += 1
      PBAI.log_score(move,1,"+ 1 for initiating a multi-turn trap")
    end
  end
  next score
end

# Remove a move as a possible choice if not the one Choice locked into
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  if user.effects[PBEffects::ChoiceBand]
    choiced_move = user.effects[PBEffects::ChoiceBand]
    if choiced_move == move.id
      score += 5
      PBAI.log_score(move,5,"+ 5 for being Choice locked")
      if !user.can_switch?
        score += 10
        PBAI.log_score(move,10,"+ 10 for being Choice locked and unable to switch")
      end
    else
      score -= 20
      PBAI.log_score(move,-20,"- 20 for being Choice locked")
    end
  end
  next score
end

# Status-inducing move handling.
PBAI::ScoreHandler.add_status do |score, ai, user, target, move|
  next if !PBAI::AI_Move.status_condition_move?(move)
  next if ai.battle.field.terrain == :Misty
  ability_list = [:MAGICBOUNCE,:GOODASGOLD,:PURIFYINGSALT,:GUTS,:COMATOSE,:FAIRYBUBBLE,:MARVELSCALE,:QUICKFEET]
  can_status = true unless target.status != :NONE
  case move.id
  when :WILLOWISP
    flag = :burn
    ability_list = [:MAGICBOUNCE,:GOODASGOLD,:PURIFYINGSALT,:WATERVEIL,:WATERBUBBLE,:GUTS,:COMATOSE,:FAIRYBUBBLE,:FLAREBOOST,:MARVELSCALE,:WELLBAKEDBODY,:STEAMENGINE,:FLASHFIRE,:QUICKFEET]
    can_status = target.can_burn?(user,move)
  when :DEEPFREEZE
    flag = :frostbite
    ability_list = [:MAGICBOUNCE,:GOODASGOLD,:PURIFYINGSALT,:MAGMAARMOR,:GUTS,:COMATOSE,:FAIRYBUBBLE,:MARVELSCALE,:QUICKFEET]
    can_status = target.can_freeze?(user,move)
  when :THUNDERWAVE,:GLARE,:STUNSPORE
    flag = :paralysis
    ability_list = [:MAGICBOUNCE,:GOODASGOLD,:PURIFYINGSALT,:LIMBER,:GUTS,:COMATOSE,:FAIRYBUBBLE,:MARVELSCALE,:QUICKFEET]
    can_status = target.can_paralyze?(user,move)
  when :POISONGAS,:TOXIC,:POISONPOWDER,:TOXICTHREAD
    flag = :poison
    ability_list = [:MAGICBOUNCE,:GOODASGOLD,:PURIFYINGSALT,:IMMUNITY,:TOXICBOOST,:POISONHEAL,:GUTS,:QUICKFEET,:COMATOSE,:FAIRYBUBBLE,:MARVELSCALE,:PASTELVEIL,:QUICKFEET]
    can_status = target.can_poison?(user,move)
  when :SPORE,:SING,:SLEEPPOWDER,:YAWN,:HYPNOSIS,:DARKVOID
    flag = :sleep
    ability_list = [:MAGICBOUNCE,:GOODASGOLD,:PURIFYINGSALT,:INSOMNIA,:SWEETVEIL,:VITALSPIRIT,:FAIRYBUBBLE,:GUTS,:COMATOSE,:MARVELSCALE,:QUICKFEET]
    can_status = target.can_sleep?(user,move)
  else
    next score
  end
  prankster = user.hasActiveAbility?(:PRANKSTER) && target.pbHasType?(:DARK)
  if PBAI.threat_score(user,target) > 0 && $threat_flags[flag] == true && !prankster
    score += PBAI.threat_score(user,target)
    PBAI.log_score(move,PBAI.threat_score(user,target),"+ #{PBAI.threat_score(user,target)} to add extra incentive to target this.")
  end
  if (target.hasActiveAbility?(ability_list) || !can_status || user.hasActiveAbility?(:PRANKSTER) && target.pbHasType?(:DARK))
    score -= 10
    PBAI.log_score(move,-10,"- 10 for not being able to status")
  end
  if (user.pbHasMove?(:HEX) || user.pbHasMove?(:BITTERMALICE)|| user.pbHasMove?(:BARBBARRAGE)|| user.pbHasMove?(:INFERNALPARADE)) && can_status
      score += 2
      PBAI.log_score(move,2,"+ 2 to set up for Hex-style spam")
    end
  if (user.target_is_immune?(move,target) || !can_status)
    score -= 10
    PBAI.log_score(move,-10,"- 10 for being immune to status or is already statused")
  end
  if flag == :paralysis
    if user.has_role?(:SPEEDCONTROL)
      score += 1
      PBAI.log_score(move,1,"+ 1")
    end
  end
  if flag == :poison
    if user.has_role?(:TOXICSTALLER)
      score += 2
      PBAI.log_score(move,2,"+ 2 for being a Toxic Staller")
    end
  end
  if target.hasActiveAbility?(:HOPEFULTOLL)
    PBAI.log_score(move,(score*-1),"- #{score} to encourage other moves since this will be removed at the end of the turn.")
    score = 0
  end
  next score
end

# Encourage using offense boosting setup moves if neither of us can kill.
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if !PBAI::AI_Move.offense_setup_move?(move)
  next if $spam_block_flags[:haze_flag].include?(target) && move.statusMove?
  next if user.set_up_score > 2
  ded = user.has_killing_move?(target)
  me_ded = user.target_has_2hko?(target)
  should_setup = !ded && !me_ded && user.set_up_score < 2
  if should_setup
    add = 9 - user.set_up_score
    score += add
    PBAI.log_ai("+ #{add} to encourage setup")
  end
  $thief = 0
  target.moves.each do |tmove|
    $thief += 1 if [:SPECTRALTHIEF,:PSYCHUP,:SNATCH].include?(tmove.id)
  end
  if $thief > 0
    score -= 10
    PBAI.log_score(move,-10,"- 10 to not give a mon free setup")
  end
  if $spam_block_flags[:haze_flag].include?(target)
    score -= 10
    PBAI.log_score(move,-10,"- 10 because target has Haze")
  end
  if $spam_block_triggered && $spam_block_flags[:choice].is_a?(Pokemon) && user.set_up_score == 0
    score += 10
    PBAI.log_score(move,10,"+ 10 to set up on the switch")
  end
  next score
end

# Encourage using defense boosting setup moves if neither of us can kill.
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if !PBAI::AI_Move.defense_setup_move?(move)
  next if $spam_block_flags[:haze_flag].include?(target) && move.statusMove?
  next if user.set_up_score > 2
  ded = user.has_killing_move?(target)
  me_ded = user.target_has_2hko?(target)
  should_setup = !ded && !me_ded && user.set_up_score < 2
  if should_setup
    add = 9 - user.set_up_score
    score += add
    PBAI.log_ai("+ #{add} to encourage setup")
  end
  $thief = 0
  target.moves.each do |tmove|
    $thief += 1 if [:SPECTRALTHIEF,:PSYCHUP,:SNATCH].include?(tmove.id)
  end
  if $thief > 0
    score -= 10
    PBAI.log_score(move,-10,"- 10 to not give a mon free setup")
  end
  if $spam_block_flags[:haze_flag].include?(target)
    score -= 10
    PBAI.log_score(move,-10,"- 10 because target has Haze")
  end
  if $spam_block_triggered && $spam_block_flags[:choice].is_a?(Pokemon) && user.set_up_score == 0
    score += 10
    PBAI.log_score(move,10,"+ 10 to set up on the switch")
  end
  next score
end

# Encourage using speed boosting setup moves if neither of us can kill.
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if !PBAI::AI_Move.speed_setup_move?(move)
  next if $spam_block_flags[:haze_flag].include?(target) && move.statusMove?
  next if user.set_up_score > 2
  ded = user.has_killing_move?(target)
  me_ded = user.target_has_2hko?(target)
  should_setup = !ded && !me_ded && user.set_up_score < 2
  if should_setup
    add = 9 - user.set_up_score
    score += add
    PBAI.log_ai("+ #{add} to encourage setup")
  end
  $thief = 0
  target.moves.each do |tmove|
    $thief += 1 if [:SPECTRALTHIEF,:PSYCHUP,:SNATCH].include?(tmove.id)
  end
  if $thief > 0
    score -= 10
    PBAI.log_score(move,-10,"- 10 to not give a mon free setup")
  end
  if $spam_block_flags[:haze_flag].include?(target)
    score -= 10
    PBAI.log_score(move,-10,"- 10 because target has Haze")
  end
  if $spam_block_triggered && $spam_block_flags[:choice].is_a?(Pokemon) && user.set_up_score == 0
    score += 10
    PBAI.log_score(move,10,"+ 10 to set up on the switch")
  end
  next score
end


#=============================================================================#
#                                                                             #
# Damaging Moves                                                              #
#                                                                             #
#=============================================================================#

# Discourage using damaging moves if the target is semi-invulnerable and slower,
# and encourage using damaging moves if they can break through the semi-invulnerability
# (e.g. prefer earthquake when target is underground)
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  # Target is semi-invulnerable
  if target.semiInvulnerable? || target.effects[PBEffects::SkyDrop] >= 0
    encourage = false
    discourage = false
    # User will hit first while target is still semi-invulnerable.
    # If this move will do extra damage because the target is semi-invulnerable,
    # encourage using this move. If not, discourage using it.
    if user.faster_than?(target)
      if target.in_two_turn_attack?("0C9", "0CC", "0CE") # Fly, Bounce, Sky Drop
        encourage = move.hitsFlyingTargets?
        discourage = !encourage
      elsif target.in_two_turn_attack?("0CA") # Dig
        # Do not encourage using Fissure, even though it can hit digging targets, because it's an OHKO move
        encourage = move.hitsDiggingTargets? && move.function != "070"
        discourage = !encourage
      elsif target.in_two_turn_attack?("0CB") # Dive
        encourage = move.hitsDivingTargets?
        discourage = !encourage
      else
        discourage = true
      end
    end
    # If the user has No Guard
    if user.has_ability?(:NOGUARD)
      # Then any move would be able to hit the target, meaning this move wouldn't be anything special.
      encourage = false
      discourage = false
    end
    if encourage
      score += 1
      PBAI.log_score(move,1,"+ 1 for being able to hit through a semi-invulnerable state")
    elsif discourage
      score -= 2
      PBAI.log_score(move,2,"- 2 for not being able to hit target because of semi-invulnerability")
    end
  end
  next score
end


# Lower the score of multi-turn moves, because they likely have quite high power and thus score.
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  no_charge = false
  case ai.battle.pbWeather
  when :Sun, :HarshSun
    no_charge = ([:SOLARBEAM,:SOLARBLADE].include?(move.id))
  when :Rain, :HeavyRain
    no_charge = (move.id == :ELECTROSHOT)
  when :Starstorm
    no_charge = (move.id == :METEORSHOWER)
  end
  if !user.hasActiveItem?(:POWERHERB) && (move.chargingTurnMove? || move.function == "0C2") && !no_charge
    score -= 3
    PBAI.log_score(move,-3,"- 3 for requiring a charging turn")
  end
  next score
end

PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  # Start counting factor this when there's a level difference of greater than 5
  dmg = user.get_calc_self(target, move)
  if move.priority > 0 && dmg >= target.battler.hp && ai.battle.field.terrain != :Psychic && !target.priority_blocking?
    score += 3
    PBAI.log_score(move,3,"+ 3 for being a priority move and being able to KO the opponent")
  end
  if move.priority > 0 && user.hp <= user.totalhp/5
    score += 2
    PBAI.log_score(move,2,"+ 2 to get a last ditch hit off")
  end
  next score
end

# Discourage using physical moves when the user is burned
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  if user.burned?
    if user.hasActiveAbility?(:GUTS) && move.physicalMove?
      score += 3
      PBAI.log_score(move,3,"+ 3 for taking advantage of Guts")
    elsif !user.hasActiveAbility?(:GUTS) && move.physicalMove? && move.function != "07E"
      score -= 1
      PBAI.log_score(move,-1,"- 1 for being a physical move and being burned")
    end
  end
  if user.frozen?
    if move.specialMove?
      score -= 1
      PBAI.log_score(move,-1,"- 1 for being a special move and being frostbitten")
    end
  end
  next score
end


# Encourage high-critical hit rate moves, or damaging moves in general
# if Laser Focus or Focus Energy has been used
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  next if !move.pbCouldBeCritical?(user.battler, target.battler)
  if move.highCriticalRate? || user.effects[PBEffects::LaserFocus] > 0 ||
     user.effects[PBEffects::FocusEnergy] > 0
    score += 1
    PBAI.log_score(move,1,"+ 1 for having a high critical-hit rate")
  end
  next score
end


# Discourage recoil moves if they would knock the user out
PBAI::ScoreHandler.add_damaging do |score, ai, user, target, move|
  if move.is_a?(PokeBattle_RecoilMove) && !user.hasActiveAbility?([:ROCKHEAD,:MAGICGUARD])
    dmg = move.pbRecoilDamage(user.battler, target.battler)
    if dmg >= user.hp
      score -= 1
      PBAI.log_score(move,-1,"- 1 for the recoil will knock the user out")
    end
  end
  next score
end

#=============================================================================#
#                                                                             #
# Move-specific                                                               #
#                                                                             #
#=============================================================================#


# Facade
PBAI::ScoreHandler.add("07E") do |score, ai, user, target, move|
  if user.burned? || user.poisoned? || user.paralyzed? || user.frozen?
    score += 2
    PBAI.log_score(move,2,"+ 2 for doing more damage with a status condition")
  end
  next score
end


# Aromatherapy, Heal Bell
PBAI::ScoreHandler.add("019") do |score, ai, user, target, move|
  count = 0
  user.side.battlers.each do |proj|
    next if proj.nil?
    # + 80 for each active battler with a status condition
    count += 2.0 if proj.has_non_volatile_status?
  end
  user.side.party.each do |proj|
    next if proj.battler # Skip battlers
    # Inactive party members do not have a battler attached,
    # so we can't use has_non_volatile_status?
    count += 1.0 if proj.pokemon.status > 0
    # + 40 for each inactive pokemon with a status condition in the party
  end
  if count != 0
    add = count
    score += add
    PBAI.log_score(move,add,"+ #{add} for curing status condition(s)")
  else
    score -= 2
    PBAI.log_score(move,-2,"- 2 for not curing any status conditions")
  end
  next score
end


# Psycho Shift
PBAI::ScoreHandler.add("01B") do |score, ai, user, target, move|
  if user.has_non_volatile_status?
    # And the target doesn't have any status conditions
    if !target.has_non_volatile_status?
      # Then we can transfer our status condition
      transferrable = true
      transferrable = false if user.burned? && !target.can_burn?(user, move)
      transferrable = false if user.poisoned? && !target.can_poison?(user, move)
      transferrable = false if user.paralyzed? && !target.can_paralyze?(user, move)
      transferrable = false if user.asleep? && !target.can_sleep?(user, move)
      transferrable = false if user.frozen? && !target.can_freeze?(user, move)
      if transferrable
        score += 5
        PBAI.log_score(move,5,"+ 5 for being able to pass on our status condition")
        if user.burned? && target.is_physical_attacker?
          score += 2
          PBAI.log_score(move,2,"+ 2 for being able to burn the physical-attacking target")
        end
        if user.frozen? && target.is_special_attacker?
          score += 2
          PBAI.log_score(move,2,"+ 2 for being able to frostbite the special-attacking target")
        end
      end
    end
  else
    score -= 2
    PBAI.log_score(move,-2,"- 2 for not having a transferrable status condition")
  end
  next score
end


# Purify
PBAI::ScoreHandler.add("15B") do |score, ai, user, target, move|
  if target.has_non_volatile_status?
    factor = 1 - user.hp / user.totalhp.to_f
    # At full hp, factor is 0 (thus not encouraging this move)
    # At half hp, factor is 0.5 (thus slightly encouraging this move)
    # At 1 hp, factor is about 1.0 (thus encouraging this move)
    if user.flags[:will_be_healed] && ai.battle.pbSideSize(0) == 2
      score -= 1
      PBAI.log_score(move,-1,"- 1 for the user will already be healed by something")
    elsif factor != 0
      if user.is_healing_pointless?(0.5)
        score -= 1
        PBAI.log_score(move,-1,"- 1 for we will take more damage than we can heal if the target repeats their move")
      elsif user.is_healing_necessary?(0.5)
        add = 3
        score += add
        PBAI.log_score(move,3,"+ #{add} for we will likely die without healing")
      else
        add = 2
        score += add
        PBAI.log_score(move,2,"+ #{add} for we have lost some hp")
      end
    end
  else
    score -= 3
    PBAI.log_score(move,-3,"- 3 for the move will fail since the target has no status condition")
  end
  next score
end

# Refresh
PBAI::ScoreHandler.add("018") do |score, ai, user, target, move|
  if user.burned? || user.poisoned? || user.paralyzed?
    score += 2
    PBAI.log_score(move,2,"+ 2 for being able to cure our status condition")
  end
  next score
end

# Rest
PBAI::ScoreHandler.add("0D9") do |score, ai, user, target, move|
  factor = 1 - user.hp / user.totalhp.to_f
  deciding_factor = user.faster_than?(target) ? (factor <= 0.5) : (factor <= 0.67)
  if user.flags[:will_be_healed]
    score -= 3
    PBAI.log_score(move,-3,"- 3 for the user will already be healed by something")
  elsif deciding_factor && user.hp > user.target_highest_move_damage(target)
    # Not at full hp
    if user.can_sleep?(user, move, true) && user.hp < user.totalhp
      add = 2
      score += add
      PBAI.log_score(move,2,"+ #{add} for we have lost some hp")
    else
      diff = score - 1
      score = 1
      PBAI.log_score(move,(diff*-1),"- #{diff} for the move will not be worth it")
    end
  end
  next score
end

# Charge
PBAI::ScoreHandler.add("021") do |score, ai, user, target, move|
  if (target.types.include?(:GROUND) || target.hasActiveAbility?([:LIGHTNINGROD, :MOTORDRIVE, :VOLTABSORB])) || user.effects[PBEffects::Charge] != 0 
    score -= 10
    PBAI.log_score("- 10 because it's not worth using")
    next score
  end
  has_move = user.moves.any? {|mov| mov.type == :ELECTRIC && move.damagingMove?}
  if !has_move
    score -= 10
    PBAI.log_score("- 10 because there's no moves to boost")
  end
  next score
end

# Pain Split
PBAI::ScoreHandler.add("05A") do |score, ai, user, target, move|
  factor = ((target.hp + user.hp)/2).floor
  if factor <= 0
    PBAI.log_score("- 10 because we will lose HP")
    score -= 10
    next score
  end
  hp_after = factor + user.hp
  perc = (user.totalhp/factor).floor
  diff = user.hp - user.target_highest_move_damage(target)
  if user.flags[:will_be_healed]
    score -= 3
    PBAI.log_score("- 3 for the user will already be healed by something")
    next score
  end
  if hp_after > user.target_highest_move_damage(target) && user.faster_than?(target)
    score += perc
    PBAI.log_score("+ #{perc} to encourage use")
  elsif diff > 0 && (hp_after > user.target_highest_move_damage(target)) && !user.faster_than?(target)
    score += perc
    PBAI.log_score("+ #{perc} to encourage use")
  else
    score -= 2
    PBAI.log_score("- 2 because we will not outlast the damage taken")
  end
  next score
end

# Encore
PBAI::ScoreHandler.add("0BC") do |score, ai, user, target, move|
  if user.faster_than?(target) && target.turnCount == 0
    score -= 9
    PBAI.log_score(move,-9,"- 9 to prevent use when the target has not made a move yet")
  end
  if target.effects[PBEffects::Encore] > 0
    score -= 9
    PBAI.log_score(move,-9,"- 9 since the target is already encored")
  end
  if target.turnCount > 0 && $spam_block_flags[:no_attacking].include?(target)
    score += 7
    PBAI.log_score(move,7,"+ 7 to encourage encoring into status move")
  end
  minus = 0
  target.moves.each do |mov|
    minus += 1 if user.get_calc(target,mov) >= user.hp/2 && !user.fast_kill?(target)
  end
  array = [0,2,5,7,9]
  final = array[minus]
  if final > 0
    score -= final
    PBAI.log_score(move,final*-1,"- #{final} because #{minus} move(s) can kill us before we kill them")
  end
  next score
end

# Wide Guard
PBAI::ScoreHandler.add("0AC") do |score, ai, user, target, move|
  wide = 0
  if ai.battle.doublebattle
    target_moves = target.moves
    if target_moves != nil
      for i in target_moves
        wide += 1 if [:AllNearFoes,:AllNearOthers,:AllBattlers,:BothSides].include?(i.pbTarget(user))
      end
    end
    score += wide
    PBAI.log_score(move,wide,"+ #{wide} for dodging spread moves")
    if user.has_role?(:SUPPORT)
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a Support role.")
    end
  end
  next score
end

# Power Trick
PBAI::ScoreHandler.add("057") do |score, ai, user, target, move|
  if user.turnCount == 0
    score += 5
    PBAI.log_score(move,5,"+ 5 for setting up Power Trick")
  else
    if user.effects[PBEffects::PowerTrick]
      score -= 20
      PBAI.log_score(move,-20,"- 20 for not reversing Power Trick")
    end
  end
  next score
end

# Dark Void
=begin
PBAI::ScoreHandler.add("003") do |score, ai, user, target, move|
  if move.name == "Dark Void"
    if user.is_species?(:DARKRAI)
      if !target.asleep? && target.can_sleep?(user, move)
        score += 2
        PBAI.log_score(move,2,"+ 2 for damaging the target with Nightmare if it is asleep")
      end
    else
      score -= 10
      PBAI.log_score(move,-10,"- 10 for this move will fail")
    end
  end
  next score
end
=end
# Yawn
PBAI::ScoreHandler.add("004") do |score, ai, user, target, move|
  if target.effects[PBEffects::Yawn] > 0
    score -= 20
    PBAI.log_score(move,-20,"- 20 to prevent failure")
    next score
  end
  if !target.has_non_volatile_status? && target.effects[PBEffects::Yawn] == 0
    score += 3
    PBAI.log_score(move,3,"+ 3 for putting the target to sleep")
  end
  if target.set_up_score > 0
    score += target.set_up_score
    PBAI.log_score(move,target.set_up_score,"+ #{target.set_up_score} for sleeping a setup mon")
  end
  if target.hasActiveAbility?([:MAGICBOUNCE,:GOODASGOLD,:PURIFYINGSALT,:FAIRYBUBBLE,:INSOMNIA,:VITALSPIRIT,:SWEETVEIL,:CACOPHONY])
    score -= 10
    PBAI.log_score(move,-10,"- 10 because Yawn will fail")
  end
  next score
end

# Uproar, Thrash, Petal Dance, Outrage, Ice Ball, Rollout
PBAI::ScoreHandler.add("0D1", "0D2", "0D3") do |score, ai, user, target, move|
  dmg = user.get_calc_self(target, move)
  perc = dmg / target.totalhp.to_f
  perc /= 1.5 if user.discourage_making_contact_with?(target) && move.pbContactMove?(user)
  if perc != 0
    add = (perc * 10).floor
    score += add
    PBAI.log_score(move,add,"+ #{add} for dealing about #{(perc * 100).round} percent dmg")
  end
  next score
end


# Stealth Rock, Spikes, Toxic Spikes, Sticky Web, Comet Shards
PBAI::ScoreHandler.add("103", "104", "105", "153", "500") do |score, ai, user, target, move|
  if move.function == "103" && user.opposing_side.effects[PBEffects::Spikes] >= 3 ||
     move.function == "104" && user.opposing_side.effects[PBEffects::ToxicSpikes] >= 2 ||
     move.function == "105" && user.opposing_side.effects[PBEffects::StealthRock] ||
     move.function == "153" && user.opposing_side.effects[PBEffects::StickyWeb] ||
     move.function == "500" && user.opposing_side.effects[PBEffects::CometShards]
    score = 0
    PBAI.log_score(move,(score*-1),"* 0 for the opposing side already has max #{move.name}")
  else
    fnt = 0
    user.side.party.each do |pkmn|
      fnt +=1 if pkmn.fainted?
    end
    inactive = user.opposing_side.party.size - fnt
    add = inactive
    add += (3 - user.opposing_side.effects[PBEffects::Spikes]) if move.function == "103"
    add += (2 - user.opposing_side.effects[PBEffects::ToxicSpikes]) if move.function == "104"
    add += 1 if !user.opposing_side.effects[PBEffects::StealthRock] && !user.opposing_side.effects[PBEffects::CometShards] && ["104","500"].include?(move.function)
    add += 1 if !user.opposing_side.effects[PBEffects::StickyWeb] && move.function == "153"
    score += add
    PBAI.log_score(move,add,"+ #{add} for there are #{inactive} pokemon to be sent out at some point")
    if user.has_role?(:LEAD)
      score += 5
      PBAI.log_score(move,5,"+ 5 for being a Hazard Lead")
    end
    if user.has_role?(:SPEEDCONTROL) && move.function == "153" && !user.opposing_side.effects[PBEffects::StickyWeb]
      score += 1
      PBAI.log_score(move,1,"+ 1 to lower speed")
    end
    removal = 0
    target.moves.each {|move| removal += 1 if [:RAPIDSPIN,:MORTALSPIN,:DEFOG,:TIDYUP].include?(move.id)}
    if removal > 0
      score -= 20
      PBAI.log_score(move,-20,"- 20 because the target has removal")
    end
    if ai.battle.field.weather == :Windy
      score -= 20
      PBAI.log_score(move,-20,"- 20 because Windy weather prevents hazards")
    end
    if target.hasActiveAbility?(:MAGICBOUNCE)
      score -= 20
      PBAI.log_score(move,-20,"- 20 because hazards will be set on our side")
    end
    for i in target.moves
      if PBAI::AI_Move.setup_move?(i) && !user.hasActiveAbility?(:UNAWARE)
        setup = true
      end
    end
    if setup == true
      score -= 10
      PBAI.log_score(move,-10,"- 10 to counter setup leads vs hazard leads")
    end
    if !target.can_switch? || !user.can_switch?
      score -= 10
      PBAI.log_score(move,-10,"- 10 hazards are useless, best to attack")
    end
  end
  next score
end


# Disable
PBAI::ScoreHandler.add("0B9") do |score, ai, user, target, move|
  # Already disabled one of the target's moves
  if target.effects[PBEffects::Disable] > 1
    score -= 3
    PBAI.log_score(move,-3,"- 3 for the target is already disabled")
  elsif target.flags[:will_be_disabled] == true
    score -= 3
    PBAI.log_score(move,-3,"- 3 for the target is being disabled by another battler")
  else
    # Get previous damage done by the target
    prevDmg = target.get_damage_by_user(user)
    if prevDmg.size > 0 && prevDmg != 0
      lastDmg = prevDmg[-1]
      # If the last move did more than 50% damage and the target was faster,
      # we can't disable the move in time thus using Disable is pointless.
      if user.is_healing_pointless?(0.5) && target.faster_than?(user)
        score -= 3
        PBAI.log_score(move,-3,"- 3 for the target move is too strong and the target is faster")
      else
        add = 3
        score += add
        PBAI.log_score(move,3,"+ #{add} for we disable a strong move")
      end
    else
      # Target hasn't used a damaging move yet
      score -= 3
      PBAI.log_score(move,-3,"- 3 for the target hasn't used a damaging move yet.")
    end
  end
  if target.hasActiveAbility?([:MAGICBOUNCE,:GOODASGOLD])
    score -= 10
    PBAI.log_score(move,-10,"- 10 because Disable will fail")
  end
  next score
end


# Counter
PBAI::ScoreHandler.add("071") do |score, ai, user, target, move|
  expect = false
  expect = true if target.is_physical_attacker? && !target.is_healing_necessary?(0.5)
  prevDmg = user.get_damage_by_user(target)
  if prevDmg.size > 0 && prevDmg != 0
    lastDmg = prevDmg[-1]
    lastMove = lastDmg[1]
    last = GameData::Move.get(lastMove).physical?
    expect = true if last
  end
  # If we can reasonably expect the target to use a physical move
  if expect
    score += 6
    PBAI.log_score(move,6,"+ 6 for we can reasonably expect the target to use a physical move")
  end
  next score
end

# Mirror Coat
PBAI::ScoreHandler.add("072") do |score, ai, user, target, move|
  expect = false
  expect = true if target.is_special_attacker? && !target.is_healing_necessary?(0.5)
  prevDmg = user.get_damage_by_user(target)
  if prevDmg.size > 0 && prevDmg != 0
    lastDmg = prevDmg[-1]
    lastMove = lastDmg[1]
    last = GameData::Move.get(lastMove).special?
    expect = true if last
  end
  # If we can reasonably expect the target to use a special move
  if expect
    score += 6
    PBAI.log_score(move,6,"+ 6 for we can reasonably expect the target to use a special move")
  end
  next score
end

# Leech Seed
PBAI::ScoreHandler.add("0DC") do |score, ai, user, target, move|
  if !target.has_type?(:GRASS) && target.effects[PBEffects::LeechSeed] == 0
    score += 6
    PBAI.log_score(move,6,"+ 6 for sapping hp from the target")
    if user.has_role?([:PHYSICALWALL,:SPECIALWALL,:DEFENSIVEPIVOT])#.include?(user.role)
      score += 3
      PBAI.log_score(move,3,"+ 3 role modifier")
    end
  end
  if target.hasActiveAbility?([:MAGICBOUNCE,:GOODASGOLD,:MAGICGUARD,:LIQUIDOOZE]) || target.has_type?(:GRASS) || target.effects[PBEffects::LeechSeed] != 0
    score -= 10
    PBAI.log_score(move,-10,"- 10 because Leech Seed will fail or be detrimental")
  end
  next score
end


# Leech Life, Parabolic Charge, Drain Punch, Giga Drain, Horn Leech, Mega Drain, Absorb
PBAI::ScoreHandler.add("0DD") do |score, ai, user, target, move|
  add = user.hasActiveAbility?(:VAMPIRIC) ? 2 : 1
  score += add
  PBAI.log_score(move,add,"+ #{add} for hp gained")
  next score
end


# Dream Eater
PBAI::ScoreHandler.add("0DE") do |score, ai, user, target, move|
  if target.asleep?
    add = 2
    score += add
    PBAI.log_score(move,2,"+ #{add} for hp gained")
  else
    score -= 3
    PBAI.log_score(move,-3,"- 3 for the move will fail")
  end
  next score
end

# Swagger, Confuse Ray
PBAI::ScoreHandler.add("041","013") do |score, ai, user, target, move|
  if target.confused?
    score -= 6
    PBAI.log_score(move,-6,"- 6 for the move not being useful")
  end
  next score
end

# Heal Pulse
PBAI::ScoreHandler.add("0DF") do |score, ai, user, target, move|
  # If the target is an ally
  ally = false
  target.battler.eachAlly do |battler|
    ally = true if battler == user.battler
  end
  if ally# && !target.will_already_be_healed?
    factor = 1 - target.hp / target.totalhp.to_f
    # At full hp, factor is 0 (thus not encouraging this move)
    # At half hp, factor is 0.5 (thus slightly encouraging this move)
    # At 1 hp, factor is about 1.0 (thus encouraging this move)
    if target.will_already_be_healed?
      score -= 3
      PBAI.log_score(move,-3,"- 3 for the target will already be healed by something")
    elsif factor != 0
      if target.is_healing_pointless?(0.5)
        score -= 1
        PBAI.log_score(move,-1,"- 1 for the target will take more damage than we can heal if the opponent repeats their move")
      elsif target.is_healing_necessary?(0.5)
        add = 3
        score += add
        PBAI.log_score(move,3,"+ #{add} for the target will likely die without healing")
      else
        add = 2
        score += add
        PBAI.log_score(move,2,"+ #{add} for the target has lost some hp")
      end
    else
      score -= 3
      PBAI.log_score(move,-3,"- 3 for the target is at full hp")
    end
  else
    score -= 3
    PBAI.log_score(move,-3,"- 3 for the target is not an ally")
  end
  next score
end


# Whirlwind, Roar, Circle Throw, Dragon Tail, U-Turn, Volt Switch
PBAI::ScoreHandler.add("0EB", "0EC", "0EE", "151", "529") do |score, ai, user, target, move|
  if user.bad_against?(target) && user.level >= target.level &&
     !target.has_ability?(:SUCTIONCUPS) && !target.effects[PBEffects::Ingrain] && !["0EE","151","529"].include?(move.function)
    score += 1
    PBAI.log_score(move,1,"+ 1 for forcing our target to switch and we're bad against our target")
    o_boost = 0
    faint = 0
    GameData::Stat.each_battle { |s| o_boost += target.stages[s] if target.stages[s] != nil}
    target.side.party.each do |pkmn|
      faint +=1 if pkmn.fainted?
    end
    if o_boost > 0 && faint > 1
      score += 3
      PBAI.log_score(move,3,"+ 3 for forcing out a set up mon")
    end
    if user.has_role?(:PHAZER)
      score += 2
      PBAI.log_score(move,2,"+ 2 for being a Phazer")
    end
  elsif ["0EE","151","529"].include?(move.function)
    if user.has_role?([:DEFENSIVEPIVOT,:OFFENSIVEPIVOT,:LEAD])#.include?(roles)
      score += 1 if user.can_switch?
      PBAI.log_score(move,1,"+ 1 for being a Pivot or Lead")
    end
    boosts = 0
    o_boost = 0
    GameData::Stat.each_battle { |s| boosts += user.stages[s] if user.stages[s] != nil}
    boosts *= -1
    score += boosts
    GameData::Stat.each_battle { |s| o_boost += target.stages[s] if target.stages[s] != nil}
    if boosts > 0
      PBAI.log_score(move,boosts,"+ #{boosts} for switching to reset lowered stats")
    elsif boosts < 0
      PBAI.log_score(move,boosts,"#{boosts} for not wasting boosted stats")
    end
    if o_boost > 0  
      score += 2
      PBAI.log_score(move,2,"+ 2 to switch on setup")
    end
    if user.trapped? && user.can_switch?
      score += 1
      PBAI.log_score(move,1,"+ 1 for escaping a trap")
    end
    if target.faster_than?(user) && !user.bad_against?(target)
      score += 1
      PBAI.log_score(move,1,"+ 1 for making a more favorable matchup")
    end
    dead = 0
    target.moves.each {|move| dead += 1 if user.get_calc(target,move) >= user.hp}
    if user.bad_against?(target) && target.faster_than?(user) && dead == 0
      score += 5
      PBAI.log_score(move,5,"+ 5 for gaining switch initiative against a bad matchup")
    end
    if user.bad_against?(target) && user.faster_than?(target)
      score += 4
      PBAI.log_score(move,4,"+ 4 for switching against a bad matchup")
    end
    if (user.effects[PBEffects::Substitute] > 0 || user.hp <= user.totalhp/2) && move.function == "UserMakeSubstituteSwitchOut"
      score - 20
      PBAI.log_score(move,-20,"- 20 because we already have a Substitute")
    end
    kill = 0
    for i in user.moves
      kill += 1 if user.get_calc_self(target,i) >= target.hp
    end
    fnt = 0
    user.side.party.each do |pkmn|
      fnt +=1 if pkmn.fainted?
    end
    if fnt == (user.side.party.length - 1) && user.highest_damaging_move(target) != move
      score -= 20
      PBAI.log_score(move,-20,"- 20 to prevent spamming when no switches are available")
    end
    diff = user.side.party.length - fnt
    if user.predict_switch?(target) && kill == 0 && diff > 1 && !$spam_block_triggered
      score += 1
      PBAI.log_score(move,1,"+ 1 for predicting the target to switch, being unable to kill, and having something to switch to")
    end
    if user.hasActiveAbility?(:ZEROTOHERO) && user.form == 0
      score += 8
      PBAI.log_score(move,8,"+ 8 to activate ability")
    end
  end
  if target.hasActiveAbility?([:MAGICBOUNCE,:GOODASGOLD]) && move.statusMove?
    score -= 20
    PBAI.log_score(move,-20,"- 20 because move will fail")
  end
  next score
end

# Shed Tail
PBAI::ScoreHandler.add("538") do |score, ai, user, target, move|
  if user.has_role?([:DEFENSIVEPIVOT,:OFFENSIVEPIVOT,:LEAD])#.include?(roles)
    score += 1
    PBAI.log_score(move,1,"+ 1 for being a Lead or Pivot")
  end
  if user.trapped? && user.can_switch?
    score += 2
    PBAI.log_score(move,2,"+ 2 for escaping a trap")
  end
  if target.faster_than?(user) && !user.bad_against?(target)
    score += 1
    PBAI.log_score(move,1,"+ 1 for making a more favorable matchup")
  end
  if user.bad_against?(target) && target.faster_than?(user)
    score += 1
    PBAI.log_score(move,1,"+ 1 for gaining switch initiative against a bad matchup")
  end
  if user.bad_against?(target) && user.faster_than?(target)
    score += 1
    PBAI.log_score(move,1,"+ 1 for switching against a bad matchup")
  end
  if user.effects[PBEffects::Substitute] > 0 || user.hp < user.totalhp/2
    score - 10
    PBAI.log_score(move,-20,"- 20 because we cannot make a Substitute")
  end
  if !user.can_switch?
    score -= 20
    PBAI.log_score(move,-20,"- 20 because we cannot pass a Substitute")
  end
  kill = 0
  for i in user.moves
    kill += 1 if user.get_calc_self(target,i) >= target.hp
  end
  fnt = 0
  user.side.party.each do |pkmn|
    fnt +=1 if pkmn.fainted?
  end
  diff = user.side.party.length - fnt
  if user.predict_switch?(target) && kill == 0 && diff > 1
    score += 1
    PBAI.log_score(move,1,"+ 1 for predicting the target to switch, being unable to kill, and having something to switch to")
  end
  boosts = 0
  GameData::Stat.each_battle { |s| boosts += user.stages[s] if user.stages[s] != nil}
  boosts *= -2
  score += boosts
  if boosts > 0
    PBAI.log_score(move,boosts,"+ #{boosts} for switching to reset lowered stats")
  elsif boosts < 0
    PBAI.log_score(move,boosts,"#{boosts} for not wasting boosted stats")
  end
  next score
end

# Anchor Shot, Block, Mean Look, Spider Web, Spirit Shackle, Thousand Waves
PBAI::ScoreHandler.add("0EF") do |score, ai, user, target, move|
  if target.bad_against?(user) && !target.has_type?(:GHOST)
    score += 2
    PBAI.log_score(move,2,"+ 2 for locking our target in battle with us and they're bad against us")
    if user.has_role?(:TRAPPER)
      score += 2
      PBAI.log_score(move,2,"+ 2 for being a Trapper role")
    end
  end
  next score
end

# Recover, Slack Off, Soft-Boiled, Heal Order, Milk Drink, Roost, Wish
PBAI::ScoreHandler.add("0D5", "0D6", "0D7") do |score, ai, user, target, move|
  factor = 1 - user.hp / user.totalhp.to_f
  # At full hp, factor is 0 (thus not encouraging this move)
  # At half hp, factor is 0.5 (thus slightly encouraging this move)
  # At 1 hp, factor is about 1.0 (thus encouraging this move)
  if user.flags[:will_be_healed] && ai.battle.pbSideSize(0) == 2
    score = 0
    PBAI.log_score(move,(score*-1),"* 0 for the user will already be healed by something")
  elsif factor >= 0.40
    if user.is_healing_pointless?(0.50)
      score -= 20
      PBAI.log_score(move,-20,"- 20 for we will take more damage than we can heal if the target repeats their move")
    elsif user.is_healing_necessary?(0.50)
      add = 6
      score += add
      PBAI.log_score(move,add,"+ #{add} for we will likely die without healing")
      if user.has_role?([:PHYSICALWALL,:SPECIALWALL,:TOXICSTALLER,:DEFENSIVEPIVOT,:OFFENSIVEPIVOT,:CLERIC])#.include?(roles)
        score += 1
        PBAI.log_score(move,1,"+ 1 for being a defensive role")
      end
    else
      if factor >= 0.40
        add = 3
        score += add
        PBAI.log_score(move,add,"+ #{add} for we have lost some hp")
        if user.has_role?([:PHYSICALWALL,:SPECIALWALL,:TOXICSTALLER,:DEFENSIVEPIVOT,:OFFENSIVEPIVOT,:CLERIC])#.include?(roles)
          score += 1
          PBAI.log_score(move,1,"+ 1 for being a defensive role")
        end
      else
        score -= 8
        PBAI.log_score(move,-8,"- 8 for being at full HP")
      end
    end
  else
    score -= 20
    PBAI.log_score(move,-20,"- 20 for we are at full hp")
  end
  score += 1 if user.predict_switch?(target)
  PBAI.log_score(move,1,"+ 1 for predicting the switch") if user.predict_switch?(target)
  if move.function == "0D7" && ai.battle.positions[user.index].effects[PBEffects::Wish] > 0
    score -= 10
    PBAI.log_score(move,-10,"- 10 because Wish this turn will fail")
  end
  fnt = 0
  user.side.party.each do |pkmn|
    fnt +=1 if pkmn.fainted?
  end
  if fnt == (user.side.party.length - 1)
    score -= 20
    PBAI.log_score(move,-20,"- 20 to prevent recovery spam as last mon")
  end
  next score
end


# Moonlight, Morning Sun, Synthesis
PBAI::ScoreHandler.add("0D8") do |score, ai, user, target, move|
  heal_factor = 0.5
  case ai.battle.pbWeather
  when :Sun, :HarshSun
    if move.type != :FAIRY
      heal_factor = 2.0 / 3.0
    else
      heal_factor = 0.25
    end
  when :Starstorm, :Eclipse
    if move.type == :FAIRY
      heal_factor = 2.0 / 3.0
    else
      heal_factor = 0.25
    end
  when :None, :StrongWinds
    heal_factor = 0.5
  else
    heal_factor = 0.25
  end
  effi_factor = 1.0
  effi_factor = 0.5 if heal_factor == 0.25
  factor = 1 - user.hp / user.totalhp.to_f
  # At full hp, factor is 0 (thus not encouraging this move)
  # At half hp, factor is 0.5 (thus slightly encouraging this move)
  # At 1 hp, factor is about 1.0 (thus encouraging this move)
  if user.flags[:will_be_healed]
    score -= 1
    PBAI.log_score(move,-1,"- 1 for the user will already be healed by something")
  elsif factor >= 0.40
    if user.is_healing_pointless?(heal_factor)
      score -= 1
      PBAI.log_score(move,-1,"- 1 for we will take more damage than we can heal if the target repeats their move")
    elsif user.is_healing_necessary?(heal_factor)
      add = 3
      score += add
      PBAI.log_score(move,3,"+ #{add} for we will likely die without healing")
    else
      add = 2
      score += add
      PBAI.log_score(move,2,"+ #{add} for we have lost some hp")
    end
  else
    score -= 23
    PBAI.log_score(move,-23,"- 23 for we are at full hp")
  end
  next score
end

# Shore Up
PBAI::ScoreHandler.add("16D") do |score, ai, user, target, move|
  heal_factor = 0.5
  if ai.battle.pbWeather == :Sandstorm
    heal_factor = 2.0 / 3.0
  end
  factor = 1 - user.hp / user.totalhp.to_f
  # At full hp, factor is 0 (thus not encouraging this move)
  # At half hp, factor is 0.5 (thus slightly encouraging this move)
  # At 1 hp, factor is about 1.0 (thus encouraging this move)
  if user.flags[:will_be_healed] && ai.battle.pbSideSize(0) == 2
    score -= 3
    PBAI.log_score(move,-3,"- 3 for the user will already be healed by something")
  elsif factor >= 0.40
    if user.is_healing_pointless?(heal_factor)
      score -= 1
      PBAI.log_score(move,-2,"- 2 for we will take more damage than we can heal if the target repeats their move")
    elsif user.is_healing_necessary?(heal_factor)
      add = 4
      score += add
      PBAI.log_score(move,4,"+ #{add} for we will likely die without healing")
    else
      add = 2
      score += add
      PBAI.log_score(move,2,"+ #{add} for we have lost some hp")
    end
    score += 1 if ai.battle.pbWeather == :Sandstorm
    PBAI.log_score(move,1,"+ 1 for extra healing in Sandstorm")
  else
    score -= 3
    PBAI.log_score(move,-3,"- 3 for we are at full hp")
  end
  next score
end

# Reflect
PBAI::ScoreHandler.add("0A2") do |score, ai, user, target, move|
  if user.side.effects[PBEffects::Reflect] > 0
    score -= 3
    PBAI.log_score(move,-3,"- 3 for reflect is already active")
  elsif user.side.flags[:will_reflect] && ai.battle.pbSideSize(0) == 2
    score -= 3
    PBAI.log_score(move,-3,"- 3 for another battler will already use reflect")
  else
    fnt = target.side.party.size
    physenemies = 0
    target.side.party.each do |pkmn|
      next if pkmn.battler == nil
      fnt -=1 if pkmn.fainted?
      physenemies += 1 if pkmn.is_physical_attacker?
    end
    add = fnt + physenemies
    score += add
    PBAI.log_score(move,add,"+ #{add} based on enemy and physical enemy count")
    if user.has_role?(:SCREENS)
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a Screens role")
    end
  end
  next score
end


# Light Screen
PBAI::ScoreHandler.add("0A3") do |score, ai, user, target, move|
  if user.side.effects[PBEffects::LightScreen] > 0
    score -= 3
    PBAI.log_score(move,-3,"- 3 for light screen is already active")
  elsif user.side.flags[:will_lightscreen] && ai.battle.pbSideSize(0) == 2
    score -= 3
    PBAI.log_score(move,-3,"- 3 for another battler will already use light screen")
  else
    fnt = target.side.party.size
    specenemies = 0
    target.side.party.each do |pkmn|
      next if pkmn.battler == nil
      fnt -=1 if pkmn.fainted?
      specenemies += 1 if pkmn.is_special_attacker?
    end
    add = fnt + specenemies
    score += add
    PBAI.log_score(move,add,"+ #{add} based on enemy and special enemy count")
    if user.has_role?(:SCREENS)
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a Screens role")
    end
  end
  next score
end

# Aurora Veil
PBAI::ScoreHandler.add("167") do |score, ai, user, target, move|
  if user.side.effects[PBEffects::AuroraVeil] > 0
    score -= 9
    PBAI.log_score(move,-9,"- 9 for Aurora Veil is already active")
  elsif user.side.flags[:will_auroraveil] && ai.battle.pbSideSize(0) == 2
    score -= 9
    PBAI.log_score(move,-9,"- 9 for another battler will already use Aurora Veil")
  elsif ![:Hail,:Sleet,:Snow].include?(ai.battle.pbWeather)
    score -= 9
    PBAI.log_score(move,-9,"- 9 for Aurora Veil will fail without Hail or Sleet active")
  else
    fnt = target.side.party.size
    target.side.party.each do |pkmn|
      fnt -=1 if pkmn.fainted?
    end
    add = fnt
    score += add
    PBAI.log_score(move,add,"+ #{add} based on enemy count")
    if user.has_role?(:SCREENS)
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a Screens role")
    end
  end
  next score
end

# Taunt
PBAI::ScoreHandler.add("0BA") do |score, ai, user, target, move|
  if target.flags[:will_be_taunted] && ai.battle.pbSideSize(0) == 2
    score -= 3
    PBAI.log_score(move,-3,"- 3 for another battler will already use Taunt on this target")
  elsif target.effects[PBEffects::Taunt]>0
    score -= 3
    PBAI.log_score(move,-3,"- 3 for the target is already Taunted")
  else
    weight = 0
    target_moves = target.moves
    target_moves.each do |proj|
      weight += 1 if proj.statusMove?
    end
    score += weight
    PBAI.log_score(move,weight,"+ #{weight} to Taunt potential stall or setup")
    if user.has_role?(:STALLBREAKER) && weight > 1
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a Stallbreaker")
    end
    for i in target.moves
      if PBAI::AI_Move.setup_move?(i.id)
        setup = true
      end
    end
    if setup == true
      score += 2
      PBAI.log_score(move,2,"+ 2 to counter setup")
    end
    if $learned_flags[:should_taunt].include?(target) || $spam_block_flags[:no_attacking] == target
      score += 3
      PBAI.log_score(move,3,"+ 3 for stallbreaking")
    end
    if $spam_block_triggered && $spam_block_flags[:choice].is_a?(PokeBattle_Move) && setup_moves.include?($spam_block_flags[:choice].id)
      buff = user.faster_than?(target) ? 3 : 2
      score += buff
      PBAI.log_score(move,buff,"+ #{buff} to prevent setup")
    end
  end
  if target.hasActiveAbility?([:MAGICBOUNCE,:GOODASGOLD,:AROMAVEIL,:OBLIVIOUS])
    score -= 20
    PBAI.log_score(move,-20,"- 20 because Taunt will fail")
  end
  next score
end

# Haze
PBAI::ScoreHandler.add("051") do |score, ai, user, target, move|
  if user.side.flags[:will_haze] && ai.battle.pbSideSize(0) == 2
    score -= 20
    PBAI.log_score(move,-20,"- 20 for another battler will already use haze")
  else
    net = 0
    # User buffs: net goes up
    # User debuffs: net goes down
    # Target buffs: net goes down
    # Target debuffs: net goes up
    # The lower net is, the better Haze is to choose.
    user.side.battlers.each do |proj|
      next if proj.nil?
      GameData::Stat.each_battle { |s| net -= proj.stages[s] if proj.stages[s] != nil }
    end
    target.side.battlers.each do |proj|
      next if proj.nil?
      GameData::Stat.each_battle { |s| net += proj.stages[s] if proj.stages[s] != nil }
    end
    # As long as the target's stat stages are more advantageous than ours (i.e. net < 0), Haze is a good choice
    if net < 0
      add = -net
      score += add
      PBAI.log_score(move,add,"+ #{add} to reset disadvantageous stat stages")
      if user.has_role?([:STALLBREAKER,:PHAZER])##.include?(roles)
        score += 1
        PBAI.log_score(move,1,"+ 1 for having a role that compliments this move")
      end
      score += 1 if target.include?($learned_flags[:has_setup])
      PBAI.log_score(move,1,"+ 1 for preventing the target from setting up")
    else
      score -= 3
      PBAI.log_score(move,-3,"- 3 for our stat stages are advantageous")
    end
  end
  next score
end


# Bide
PBAI::ScoreHandler.add("0D4") do |score, ai, user, target, move|
  # If we've been hit at least once, use Bide if we could take two hits of the last attack and survive
 prevDmg = target.get_damage_by_user(user)
  if prevDmg.size > 0 && prevDmg != 0
    lastDmg = prevDmg[-1]
    predDmg = lastDmg[2] * 2
    # We would live if we took two hits of the last move
    if user.hp - predDmg > 0
      score += 3
      PBAI.log_score(move,3,"+ 3 for we can survive two subsequent attacks")
    else
      score -= 20
      PBAI.log_score(move,-20,"- 20 for we would not survive two subsequent attacks")
    end
  else
    score -= 20
    PBAI.log_score(move,-20,"- 20 for we don't know whether we'd survive two subsequent attacks")
  end
  next score
end

# Curse
PBAI::ScoreHandler.add("10D") do |score, ai, user, target, move|
  next unless user.types.include?(:GHOST)
  curse_target = (target.set_up_score > 0 || target.status != :NONE)
  if curse_target
    score += 6
    PBAI.log_ai("+ 6 to add residual damage.")
  end
  next score
end

# Grassy Glide
PBAI::ScoreHandler.add("18C") do |score, ai, user, target, move|
  if ai.battle.field.terrain == :Grassy && user.get_calc_self(target,move) >= target.hp
    pri = 0
    for i in user.moves
      pri += 1 if i.priority > 0 && i.damagingMove?
    end
    if target.faster_than?(user)
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a priority move to outspeed opponent")
      if user.get_calc_self(target, move) >= target.hp
        score += 1
        PBAI.log_score(move,1,"+ 1 for being able to KO with priority")
      end
    end
    if pri > 0
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a priority move to counter opponent's priority")
      if user.faster_than?(target)
        score += 1
        PBAI.log_score(move,1,"+ 1 for outprioritizing opponent")
      end
    end
    score += 1
    field = "Grassy Terrain boost"
    PBAI.log_score(move,1,"+ 1 for #{field}")
  end
  next score
end

# Protect
PBAI::ScoreHandler.add("0AA") do |score, ai, user, target, move|
  if ai.battle.positions[user.index].effects[PBEffects::Wish] > 0
    score += 3
    PBAI.log_score(move,3,"+ 3 for receiving an incoming Wish")
  end
  if ai.battle.pbSideSize(0) == 2 && user.effects[PBEffects::ProtectRate] == 1
    score += 1
    PBAI.log_score(move,1,"+ 1 for encouraging use of Protect in Double battles")
  end
  if user.effects[PBEffects::Substitute] > 0 && user.effects[PBEffects::ProtectRate] == 1
    if user.hasActiveAbility?(:SPEEDBOOST) && target.faster_than?(user)
      score += 2
      PBAI.log_score(move,2,"+ 2 for boosting speed to outspeed opponent")
    end
    if (user.hasActiveItem?(:LEFTOVERS) || (user.hasActiveAbility?(:POISONHEAL) && user.status == :POISON)) && user.hp < user.totalhp
      score += 1
      PBAI.log_score(move,1,"+ 1 for recovering HP behind a Substitute")
    end
    if target.effects[PBEffects::LeechSeed] || [:POISON,:BURN,:FROZEN].include?(target.status)
      score += 1
      PBAI.log_score(move,1,"+ 1 for forcing opponent to take residual damage")
    end
  end
  if (user.hasActiveItem?(:FLAMEORB) && user.status == :NONE && user.hasActiveAbility?([:GUTS,:MARVELSCALE])) || ((user.hasActiveItem?(:TOXICORB) || ai.battle.field.terrain == :Poison) && user.hasActiveAbility?([:TOXICBOOST,:POISONHEAL,:GUTS]) && user.affectedByTerrain? && user.status == :NONE)
    score += 10
    PBAI.log_score(move,10,"+ 10 for getting a status to benefit their ability")
  end
  if (target.status == :POISON || target.status == :BURN || target.status == :FROZEN)
    protect = 2 - user.effects[PBEffects::ProtectRate]
    score += protect
    PBAI.log_score(move,protect,"+ #{protect} for stalling status damage")
    if user.has_role?(:TOXICSTALLER) && target.status == :POISON
      score += 1
      PBAI.log_score(move,1,"+ 1 for being a Toxic Staller")
    end
  end
  score -= 2 if user.predict_switch?(target)
  if user.predict_switch?(target)
    PBAI.log_score(move,-2,"- 2 for predicting the switch")
  end
  score += 2 if user.flags[:should_protect] == true
  PBAI.log_score(move,2,"+ 2 because there are no better moves") if user.flags[:should_protect] == true
  if user.effects[PBEffects::ProtectRate] > 1
    protect = user.effects[PBEffects::ProtectRate]*2
    score -= protect
    PBAI.log_score(move,protect,"- #{protect} to prevent potential Protect failure")
  else
    if user.turnCount == 0 && user.hasActiveAbility?(:SPEEDBOOST)
      score += 3
      PBAI.log_score(move,3,"+ 3 for getting turn 1 Speed Boost")
    end
  end
  if target.turnCount == 0 && target.moves.any? {|move| move.id == :FAKEOUT}
    score += 10
    PBAI.log_score(move,10,"+ 10 to prevent Fake Out Turn 1")
  end
  if user.hasActiveAbility?(:STANCECHANGE) && user.form == 1 && move.id == :KINGSSHIELD
    score += 3
    PBAI.log_score(move,3,"+ 3 for switching forms")
  end
  if user.turnCount > 0
    last_move = user.lastRegularMoveUsed
    if last_move == :GLAIVERUSH
      score += 10
      PBAI.log_score(move,10,"+ 10 to counteract Glaive Rush's effect")
    end
  end
  if [:BURN,:FROZEN,:POISON,:FROZEN].include?(user.status)
    score -= 10
    PBAI.log_score(move,-10," - 10 because of residual damage")
  end
  next score
end

# Teleport
PBAI::ScoreHandler.add("0EA") do |score, ai, user, target, move|
  if user.effects[PBEffects::Trapping] > 0 && !user.predict_switch?(target)
    score += 3
    PBAI.log_score(move,3,"+ 3 for escaping the trap")
  end
  if user.has_role?([:PHYSICALWALL,:SPECIALWALL,:DEFENSIVEPIVOT,:OFFENSIVEPIVOT,:TOXICSTALLER,:LEAD])
    score += 1
    PBAI.log_score(move,1,"+ 1 ")
  end
  fnt = 0
  user.side.party.each do |pkmn|
    fnt +=1 if pkmn.fainted?
  end
  if user.hasActiveAbility?(:REGENERATOR) && fnt < user.side.party.length && user.hp < user.totalhp*0.67
    score += 1
    PBAI.log_score(move,1,"+ 1 for being able to recover with Regenerator")
  end
  if fnt == user.side.party.length - 1
    score -= 20
    PBAI.log_score(move,-20,"- 20 for being the last Pokémon in the party")
  end
  if !user.can_switch?
    score -= 20
    PBAI.log_score(move,-20,"- 20 because we cannot Teleport")
  end
  next score
end

# Beat Up for Doubles Mini Boss
PBAI::ScoreHandler.add("0C1") do |score, ai, user, target, move|
  if user.has_role?(:TARGETALLY) && move.id == :BEATUP2
    score += 20
    PBAI.log_score(move,20,"+ 20 to initiate the gimmick")
  end
  next score
end

# Tempest Rage for Primal Castform
PBAI::ScoreHandler.add("087") do |score, ai, user, target, move|
  if user.battler.species == :CASTFORM && user.battler.form == 1 && move.id == :TEMPESTRAGE
    score += 5
    PBAI.log_score(move,5,"+ 5 because the move changes type and weather to match well vs target")
  end
  next score
end

# Substitute
PBAI::ScoreHandler.add("10C") do |score, ai, user, target, move|
  dmg = 0
  sound = 0
  roles = []
    for i in user.roles
      roles.push(i)
    end
  for i in target.moves
    dmg += 1 if user.get_calc(target,i) >= user.totalhp/4
    sound += 1 if i.soundMove? && i.damagingMove?
  end
  if user.effects[PBEffects::Substitute] == 0
    if user.turnCount == 0 && dmg == 0
      score += 5
      PBAI.log_score(move,5,"+ 5 for Substituting on the first turn and being guaranteed to have a Sub stay up")
    end
    if user.has_role?([:TOXICSTALLER,:PHYSICALWALL,:SPECIALWALL,:STALLBREAKER,:DEFENSIVEPIVOT,:OFFENSIVEPIVOT,:SETUPSWEEPER,:WINCON])
      score += 2
      PBAI.log_score(move,2,"+ 2")
    end
    if user.hp < user.totalhp/4
      score -= 10
      PBAI.log_score(move,-10,"- 10 for being unable to Substitute")
    end
    if sound > 0
      score -= 7
      PBAI.log_score(move,-7,"- 7 because the target has shown a damaging sound-based move")
    end
    if target.status == :POISON || target.status == :BURN || target.status == :FROZEN || target.effects[PBEffects::LeechSeed]>=0 || target.effects[PBEffects::StarSap]>=0
      score += 3
      PBAI.log_score(move,3,"+ 3 for capitalizing on target's residual damage")
    end
    if user.predict_switch?(target)
      score += 3
      PBAI.log_score(move,3,"+ 3 for capitalizing on target's predicted switch")
    end
  else
    score -= 10
    PBAI.log_score(move,-10,"- 10 for already having a Substitute")
  end
  next score
end

# Destiny Bond
PBAI::ScoreHandler.add("0E7") do |score, ai, user, target, move|
  if user.target_has_fast_2hko?(target) || user.target_has_killing_move?(target)
    dbond = 8
    score += dbond
    PBAI.log_score(move,dbond,"+ #{dbond} for being able to take down the opponent with Destiny Bond")
    if user.hasActiveItem?(:CUSTAPBERRY) && user.hp <= user.totalhp/4 && user.target_fast_kill?(target)
      score += 1
      PBAI.log_score(move,1,"+ 1 for having Custap Berry's boosted priority on Destiny Bond")
    end
  end
  score -= 10 if user.effects[PBEffects::DestinyBondPrevious] == true
  PBAI.log_score(move,-10,"- 10 for having used Destiny Bond the previous turn") if user.effects[PBEffects::DestinyBondPrevious] == true
  next score
end

# Overcharge
PBAI::ScoreHandler.add("501") do |score, ai, user, target, move|
  if target.pbHasType?(:GROUND)
    score += 2
    PBAI.log_score(move,2,"+ 2 for being effective against Ground types")
  end
  if target.hasActiveAbility?([:LIGHTINGROD,:MOTORDRIVE,:VOLTABSORB]) && target.pbHasType?([:WATER,:FLYING])
    score += 2
    PBAI.log_score(move,2,"+ 2 for move ignoring abilities and potentially being strong against target")
  end
  next score
end

# Draco Meteor, Astro Bomb, Psycho Boost, etc.
PBAI::ScoreHandler.add("03F","03C","03B","03E","15F","193","114") do |score, ai, user, target, move|
  if user.hasActiveAbility?(:CONTRARY) && !["114"].include?(move.function)
    score += 2
    PBAI.log_score(move,2,"+ 2 for boosting")
  end
  if user.hasActiveAbility?(:UNSHAKEN)
    score += 1
    PBAI.log_score(move,1,"+ 1 for stat drops being prevented")
  end
  next score
end

# Bonemerang
PBAI::ScoreHandler.add("520") do |score, ai, user, target, move|
  if target.pbHasType?(:FLYING)
    score += 2
    PBAI.log_score(move,2,"+ 2 for being effective against Flying types")
  end
  if target.hasActiveAbility?(:LEVITATE) && target.pbHasType?([:FIRE,:ELECTRIC,:ROCK,:STEEL])
    score += 2
    PBAI.log_score(move,2,"+ 2 for move ignoring abilities and potentially being strong against target")
  end
  next score
end

# Perfection Pulse, Ancient Cry
PBAI::ScoreHandler.add("504") do |score, ai, user, target, move|
  if target.pbHasType?(:FAIRY)
    score += 2
    PBAI.log_score(move,2,"+ 2 for being effective against Fairy types")
  end
  next score
end

# Polarity Pulse
PBAI::ScoreHandler.add("505") do |score, ai, user, target, move|
  if target.pbHasType?(:ELECTRIC)
    score += 2
    PBAI.log_score(move,2,"+ 2 for being super effective against Electric types")
  end
  next score
end

# Stone Axe
PBAI::ScoreHandler.add("512") do |score, ai, user, target, move|
  if user.opposing_side.effects[PBEffects::StealthRock] != true
    score += 2
    PBAI.log_score(move,2,"+ 2 for being able to set Stealth Rocks")
  end
  next score
end

# Ceaseless Edge
PBAI::ScoreHandler.add("522") do |score, ai, user, target, move|
  if user.opposing_side.effects[PBEffects::Spikes] < 3
    add = 3 - user.opposing_side.effects[PBEffects::Spikes]
    score += add
    PBAI.log_score(move,add,"+ #{add} for being able to set Spikes")
  end
  next score
end

# Explosion
PBAI::ScoreHandler.add("0E7","0E0") do |score, ai, user, target, move|
  next if move.pbCalcType(user) == :NORMAL && target.pbHasType?(:GHOST)
  next if target.hasActiveAbility?(:DAMP)
  next if user.moves.length == 1
  skip_score = false
  # if user.has_killing_move?(target)
  #   user.moves.each do |move1|
  #     if user.get_calc_self(target,move1) >= target.hp && move1 != move
  #       skip_score = true
  #       break
  #     end
  #   end
  # end
  move1 = user.highest_damaging_move_non_explosive(target)
  skip_score = user.get_calc_self(target,move1) >= target.hp
  if skip_score
    score -= 25
    PBAI.log_score(move,-25,"- 25 because we have another move that kills")
    next score
  end
  if !user.can_switch?
    score -= 25
    PBAI.log_score(move,-25,"- 25 because we are the last mon or are trapped")
    next score
  end
  if user.get_calc_self(target, move) >= target.hp
    score += 5
    PBAI.log_score(move,5,"+ 5 for being able to KO")
  end
  factor = (user.totalhp/user.hp).floor
  score += factor
  PBAI.log_score(move,factor,"+ #{factor} to encourage exploding with lower HP")
  if !user.can_switch? && user.hasActiveItem?(:CUSTAPBERRY)
    score += 12
    PBAI.log_score(move,12,"+ 12 for being unable to switch and will likely outprioritize the target")
  end
  if user.hasActiveItem?(:CUSTAPBERRY) && user.hp <= user.totalhp/4
    score += 5
    PBAI.log_score(move,5,"+ 5 for being unable to switch and will likely outprioritize the target")
  end
  protect = false
  for i in target.moves
    if i.function == "0AA"
      protect = true 
      break
    end
  end
  if protect == true
    pro = 5 * target.effects[PBEffects::ProtectRate]
    score += pro
    if pro > 0
      PBAI.log_score(move,pro,"+ #{pro} to predict around Protect")
    else
      score -= 10
      PBAI.log_score(move,-10,"- 10 because the target has Protect and can choose it")
    end
  end
  next score
end

# Rage Powder/Ally Switch
PBAI::ScoreHandler.add("117","120") do |score, ai, user, target, move|
  if ai.battle.pbSideSize(0) == 2
    ally = false
    b = nil
    enemy = []
    user.battler.eachAlly do |battler|
      ally = true if battler != user.battler
    end
    if ally
      ai.battle.eachOtherSideBattler(user.index) do |opp|
        next if opp.fainted?
        next if opp.nil?
        enemy.push(opp)
      end
      mon = user.side.battlers.find {|proj| proj && proj != self && !proj.fainted?}
      if enemy.any? {|e| mon.bad_against?(e)}
        score += 3
        PBAI.log_score(move,3,"+ 3 for redirecting an attack away from partner")
        if user.has_role?(:REDIRECTION)
          score += 3
          PBAI.log_score(move,3,"+ 3")
        end
      end
      if user.has_role?(:REDIRECTION) && mon.setup?
        score += 2
        PBAI.log_score(move,2,"+ 2")
      end
      if $chosen_move != nil
        if $chosen_move.id == :PROTECT
          score = 0
          PBAI.log_score(move,(score*-1),"* 0 for not wasting a turn.")
        end
      end
    end
  else
    score -= 20
    PBAI.log_score(move,-20,"- 20 because move will fail")
  end
  if $team_flags[:will_redirect] == true
    score -= 20
    PBAI.log_score(move,-20,"- 20 to prevent double Follow Me")
  end
  next score
end

# Helping Hand
PBAI::ScoreHandler.add("09C") do |score, ai, user, target, move|
  if ai.battle.pbSideSize(0) == 2
    ally = false
    b = nil
    enemy = []
    user.battler.eachAlly do |battler|
      ally = true if battler != user.battler
    end
    if ally
      add = user.has_role?(:SUPPORT) ? 6 : 4
      score += add
      PBAI.log_score(move,add,"+ #{add} to boost damage of ally")
      mon = user.side.battlers.find {|proj| proj && proj != self && !proj.fainted?}
      pk = ai.pokemon_to_projection(mon.pokemon)
      dmg = pk.get_calc_self(target, m)
      tar_dmg = pk.get_calc(target,m2)
      ally_kill = mon.moves.any? {|m| (dmg*1.5) >= target.hp} #the 1.5x multiplier here is to consider the Helping Hand boost
      target_kill_ally = target.moves.any? {|m2| tar_dmg >= mon.hp}
      target_fast_kill_ally - target_kill_ally && target.faster_than?(mon)
      ally_fast_kill = ally_kill && mon.faster_than?(target)
      if mon.effects[PBEffects::HyperBeam] || mon.defensive? || target_kill_ally && !ally_fast_kill || target_fast_kill_ally
        score -= 10
        PBAI.log_score(move,-10,"- 10 because move will be pointless")
      end
    end
  else
    score -= 20
    PBAI.log_score(move,-20,"- 20 because move will fail")
  end
  next score
end

# Clangorous Soul
PBAI::ScoreHandler.add("179") do |score, ai, user, target, move|
  if user.hp > user.totalhp/3
    score += 2
    PBAI.log_score(move,2,"+ 2 for gaining an omni-boost")
    if user.hasActiveItem?(:THROATSPRAY)
      score += 1
      PBAI.log_score(move,1,"+ 1 for activating Throat Spray")
    end
  else
    score -= 10
    PBAI.log_score(move,-10,"- 10 because we don't have enough HP")
  end
  next score
end

# First Impression
PBAI::ScoreHandler.add("174") do |score, ai, user, target, move|
  if user.turnCount == 0 && ai.battle.field.terrain != :Psychic && !target.priority_blocking?
    score += 4
    PBAI.log_score(move,4,"+ 4 for getting priority damage")
  else
    score -= 20
    PBAI.log_score(move,-20,"- 20 to discourage use after turn 1")
  end
  next score
end

# Rapid Spin
PBAI::ScoreHandler.add("110") do |score, ai, user, target, move|
  hazard_score = 0
  rocks = user.own_side.effects[PBEffects::StealthRock] ? 1 : 0
  webs = user.own_side.effects[PBEffects::StickyWeb] ? 1 : 0
  spikes = user.own_side.effects[PBEffects::Spikes] > 0 ? user.own_side.effects[PBEffects::Spikes] : 0
  tspikes = user.own_side.effects[PBEffects::ToxicSpikes] > 0 ? user.own_side.effects[PBEffects::ToxicSpikes] : 0
  comet = user.own_side.effects[PBEffects::CometShards] ? 1 : 0
  hazard_score = (rocks) + (webs) + (spikes) + (tspikes) + (comet)
  score += hazard_score
  PBAI.log_score(move,hazard_score,"+ #{hazard_score} for removing hazards")
  if user.has_role?(:HAZARDREMOVAL)
    score += 2
    PBAI.log_score(move,2,"+ 2")
  end
  fnt = 0
  user.side.party.each do |pkmn|
    fnt +=1 if pkmn.fainted?
  end
  if fnt == user.side.party.length - 1
    score -= 20
    PBAI.log_score(move,-20,"- 20 because of being the last mon")
  end
  next score
end

# Defog
PBAI::ScoreHandler.add("049") do |score, ai, user, target, move|
  hazard_score = 0
  rocks = user.own_side.effects[PBEffects::StealthRock] ? 1 : 0
  webs = user.own_side.effects[PBEffects::StickyWeb] ? 1 : 0
  spikes = user.own_side.effects[PBEffects::Spikes] > 0 ? user.own_side.effects[PBEffects::Spikes] : 0
  tspikes = user.own_side.effects[PBEffects::ToxicSpikes] > 0 ? user.own_side.effects[PBEffects::ToxicSpikes] : 0
  comet = user.own_side.effects[PBEffects::CometShards] ? 1 : 0
  light = user.opposing_side.effects[PBEffects::LightScreen] > 0 ? user.opposing_side.effects[PBEffects::LightScreen] : 0
  reflect = user.opposing_side.effects[PBEffects::Reflect] > 0 ? user.opposing_side.effects[PBEffects::Reflect] : 0
  veil = user.opposing_side.effects[PBEffects::AuroraVeil] > 0 ? user.opposing_side.effects[PBEffects::AuroraVeil] : 0
  hazard_score = (rocks) + (webs) + (spikes) + (tspikes) + (light) + (reflect) + (veil) + (comet)

  orocks = user.opposing_side.effects[PBEffects::StealthRock] ? 1 : 0
  owebs = user.opposing_side.effects[PBEffects::StickyWeb] ? 1 : 0
  ospikes = user.opposing_side.effects[PBEffects::Spikes] > 0 ? user.opposing_side.effects[PBEffects::Spikes] : 0
  otspikes = user.opposing_side.effects[PBEffects::ToxicSpikes] > 0 ? user.opposing_side.effects[PBEffects::ToxicSpikes] : 0
  ocomet = user.opposing_side.effects[PBEffects::CometShards] ? 1 : 0
  slight = user.own_side.effects[PBEffects::LightScreen] > 0 ? user.own_side.effects[PBEffects::LightScreen] : 0
  sreflect = user.own_side.effects[PBEffects::Reflect] > 0 ? user.own_side.effects[PBEffects::Reflect] : 0
  sveil = user.own_side.effects[PBEffects::AuroraVeil] > 0 ? user.own_side.effects[PBEffects::AuroraVeil] : 0
  user_score = (orocks) + (owebs) + (ospikes) + (otspikes) + (slight) + (sreflect) + (sveil) + (ocomet)
  hazards = (hazard_score - user_score)
  score += hazards
  PBAI.log_score(move,hazards,"+ #{hazards} for removing hazards and screens")
  if user.has_role?(:HAZARDREMOVAL) && hazards > 0
    score += 2
    PBAI.log_score(move,2,"+ 2 for being a Hazard Remover")
  end
  fnt = 0
  user.side.party.each do |pkmn|
    fnt +=1 if pkmn.fainted?
  end
  if target.hasActiveAbility?(:GOODASGOLD) || fnt == user.side.party.length - 1
    score -= 20
    PBAI.log_score(move,-20,"- 20 because Defog will fail")
  end
  next score
end

# Rage Fist
PBAI::ScoreHandler.add("522") do |score, ai, user, target, move|
  hit = ai.battle.getBattlerHit(user)
  if hit > 0
    score += hit
    PBAI.log_score(move,hit,"+ #{hit} for having a damage boost")
  end
  next score
end

# Tailwind
PBAI::ScoreHandler.add("05B") do |score, ai, user, target, move|
  if user.own_side.effects[PBEffects::Tailwind] <= 0 && !user.has_killing_move?(target)
    score += 4
    PBAI.log_score(move,4,"+ 4 for setting up to outspeed")
    if user.has_role?(:SPEEDCONTROL)
      score += 2
      PBAI.log_score(move,2,"+ 2 for being a Speed Control role")
    end
  else
    score -= 20
    PBAI.log_score(move,-20,"- 20 because Tailwind is already up")
  end
  next score
end

# Pursuit
PBAI::ScoreHandler.add("088") do |score, ai, user, target, move|
  calc = user.get_calc_self(target,move)
  if (calc*2) >= target.hp && user.predict_switch?(target)
    score += 5
    PBAI.log_score(move,5,"+ 5 for predicting the switch and Pursuit doing enough damage to kill if boosted")
  end
  next score
end

# Hex, Bitter Malice, Barb Barrage, Infernal Parade
PBAI::ScoreHandler.add("07F","519","515","517") do |score, ai, user, target, move|
  if target.status != :NONE
    score += 2
    PBAI.log_score(move,2,"+ 2 for abusing target's status")
  end
  next score
end

# Bolt Beak, Fishious Rend
PBAI::ScoreHandler.add("178") do |score, ai, user, target, move|
  if (user.faster_than?(target) && !user.target_is_immune?(move,target)) || user.predict_switch?(target)
    score += 6
    PBAI.log_score(move,6,"+ 6 for getting double damage")
  end
  next score
end

# Poltergeist
PBAI::ScoreHandler.add("192") do |score, ai, user, target, move|
  if target.item == nil
    score -= 20
    PBAI.log_score(move,-20,"- 20 since it will fail")
  end
  next score
end

# Gigaton Hammer, Blood Moon
PBAI::ScoreHandler.add("540") do |score, ai, user, target, move|
  if user.effects[PBEffects::SuccessiveMove] == move.id
    score -= 20
    PBAI.log_score(move,-20,"- 20 since it will fail")
  end
  next score
end

# Sleep Talk
PBAI::ScoreHandler.add("0B4") do |score, ai, user, target, move|
  if (user.hasActiveAbility?(:COMATOSE) || user.asleep? && user.statusCount > 0)
    score += 10
    PBAI.log_score(move,10,"+ 10 to prioritize using moves while sleeping")
  end
  if !user.asleep?
    diff = score - 1
    score = 1
    PBAI.log_score(move,diff*-1,"- #{diff} to disincentivize")
  end
  next score
end

# Last Resort
PBAI::ScoreHandler.add("125") do |score, ai, user, target, move|
  moveslist = []
  used = []
  unused_moves = false
  user.moves.each {|use| used.push(use.id) if use.id != :LASTRESORT}
  user.moves.each {|m| moveslist.push(m.id) if m.pp > 0}
  used.each do |move2|
    unused_moves = true if !user.movesUsed.include?(move2)
  end
  if (user.hasActiveAbility?(:COMATOSE) && user.moves.length == moveslist.length && moveslist.include?(:SLEEPTALK)) || unused_moves == true
    score -= 20
    PBAI.log_score(move,-20,"- 20 to prioritize using other moves over this move")
  end
  if unused_moves == false
    score += 10
    PBAI.log_score(move,10,"+ 10 because this move is now usable")
  end
  next score
end

# Focus Energy
PBAI::ScoreHandler.add("023") do |score, ai, user, target, move|
  if user.has_role?(:CRIT) && user.turnCount == 0
    score += 10
    PBAI.log_score(move,10,"+ 10 to set up crit")
  else
    score -= 20
    PBAI.log_score(move,-20,"- 20 to prevent bad move")
  end
  next score
end

# Trick Room
PBAI::ScoreHandler.add("11F") do |score, ai, user, target, move|
  if ai.battle.field.effects[PBEffects::TrickRoom] == 0 && target.faster_than?(user)
    score += 3
    PBAI.log_score(move,3,"+ 3 for setting Trick Room to outspeed target")
    if user.has_role?(:TRICKROOMSETTER)
      score += 2
      PBAI.log_score(move,2,"+ 2 for being a Trick Room setter")
    end
  else
    score -= 20
    PBAI.log_score(move,-20,"- 20 to not undo Trick Room") if ai.battle.field.effects[PBEffects::TrickRoom] != 0
  end
  next score
end

# Body Press
PBAI::ScoreHandler.add("177") do |score, ai, user, target, move|
  defense = user.stages[:DEFENSE]
  score += defense
  PBAI.log_score(move,defense,"+ #{defense} for boosted Defense stats") if defense > 0
  PBAI.log_score(move,defense,"#{defense} for lowered Defense stats") if defense < 0
  next score
end

# Double Shock
PBAI::ScoreHandler.add("531") do |score, ai, user, target, move|
  score = 0 if user.effects[PBEffects::DoubleShock] == true
  PBAI.log_score(move,(score*-1),"* 0 since Double Shock removes Electric type")
  next score
end

# Burn Up
PBAI::ScoreHandler.add("162") do |score, ai, user, target, move|
  score = 0 if user.effects[PBEffects::BurnUp] == true
  PBAI.log_score(move,(score*-1),"* 0 since Burn Up removes Fire type")
  next score
end

# RotoBlast
PBAI::ScoreHandler.add("516") do |score, ai, user, target, move|
  score_log = []
  rotoblast_log = []
  rotoblast_list = [:HYDROPUMP,:OVERHEAT,:LEAFSTORM,:WINDDRILL,:FLASHCANNON,:BLIZZARD]
  rotoblast_list.each {|r| rotoblast_log.push(user.get_potential_move_damage(target,Battle::Move.from_pokemon_move(ai.battle,Pokemon::Move.new(r))))}
  user.moves.each do |mov|
    next if mov.id == :ROTOBLAST
    score_log.push(user.get_potential_move_damage(target,mov))
  end
  flag = false
  score_log.each do |s|
    rotoblast_log.each do |roto|
      next if s > roto
      if s <= roto
        flag = true
        break
      end
    end
  end
  mod = flag ? -9 : 9
  score += mod
  add = (mod>=0) ? "+" : ""
  PBAI.log_score(move,mod,"#{add}#{mod} to properly factor in all moves RotoBlast can use")
  next score
end
#=============================================================================#
#                                                                             #
# FINAL CONSIDERATIONS                                                        #
#                                                                             #
#=============================================================================#

PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  # Field Effect boost
  next score if move.statusMove?
  fe = (ai.battle.field.field_effects) == :None ? nil : Field_Effects.try_get(ai.battle.field.field_effects)
  next if !fe
  move_boost = nil
  type_boost = nil
  if Field_Effects.has?(fe,:move_damage_boost)
    move_boost = fe[:move_damage_boost].keys.find {|boost| fe[:move_damage_boost][boost].include?(move.id)}
  end
  if Field_Effects.has?(fe,:type_damage_change)
    type_boost = fe[:type_damage_change].keys.find {|boost1| fe[:type_damage_change][boost1].include?(move.type)}
  end
  add = 0
  if move_boost
    fe[:move_damage_boost].keys.each do |b|
      add = ((b-1.0)*10).round
      score += add
      PBAI.log_score(move,add,"Field effect move boost")
    end
  end
  if type_boost
    fe[:type_damage_change].keys.each do |b|
      add = ((b-1.0)*10).round
      score += add
      PBAI.log_score(move,add,"Field effect type boost")
    end
  end
  next score
end

# Discount Status Moves if Taunted
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  if move.statusMove? && user.effects[PBEffects::Taunt] > 0
      score -= 20
      PBAI.log_score(move,-20,"- 20 to prevent failing")
  end
  if $spam_block_triggered && move.statusMove? && target.faster_than?(user) && $spam_block_flags[:choice].is_a?(PokeBattle_Move) && $spam_block_flags[:choice].id == :TAUNT
    score -= 20
    PBAI.log_score(move,-20,"- 20 because target is going for Taunt")
  end
  next score
end

# Properly choose moves if Tormented
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  if move == user.lastRegularMoveUsed && user.effects[PBEffects::Torment]
      score -= 20
      PBAI.log_score(move,-20,"- 20 to prevent failing")
  end
  next score
end

# Properly choose moves if Encored
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  if user.effects[PBEffects::Encore] > 0
    encore_move = user.effects[PBEffects::EncoreMove]
    if move.id == encore_move
      score += 10
      PBAI.log_score(move,10,"+ 10 to guarantee use of this move")
    else
      score -= 20
      PBAI.log_score(move,-20,"- 20 to prevent failing")
    end
  end
  next score
end

# Encourage using Fake Out properly
PBAI::ScoreHandler.add("012") do |score, ai, user, target, move|
  next if target.priority_blocking?
  next if ai.battle.field.terrain == :Psychic
  if user.turnCount == 0 && !user.fast_kill?(target)
    score += 10
    PBAI.log_score(move,10,"+ 10 for using Fake Out turn 1")
    if ai.battle.pbSideSize(0) == 2
      score += 2
      PBAI.log_score(move,2,"+ 2 for being in a Double battle")
    end
    if PBAI.threat_score(user,target) == 50
      score += 10
      PBAI.log_score(move,10,"+ 10 because the target outspeeds and OHKOs our entire team.")
    end
  else
    score -= 30
    PBAI.log_score(move,-30,"- 30 to discourage use")
  end
  next score
end

# Prefer Weather/Terrain Moves if you are a weather setter
PBAI::ScoreHandler.add do |score, ai, user, target, move|
  next if move.damagingMove?
  next if !PBAI::AI_Move.weather_terrain_move?(move)
  weather = [:Sun,:Rain,:Snow,:Sandstorm,:Starstorm,:Eclipse,:AcidRain,:Electric,:Grassy,:Misty,:Psychic,:Poison]
  setter = [[:SUNNYDAY],[:RAINDANCE],[:HAIL,:SNOWSCAPE,:CHILLYRECEPTION],[:SANDSTORM],[:STARSTORM],[nil],[nil],[:ELECTRICTERRAIN],[:GRASSYTERRAIN],[:MISTYTERRAIN],[:PSYCHICTERRAIN],[nil]]
  ability = [
  [:SOLARPOWER,:CHLOROPHYLL,:PROTOSYNTHESIS,:FLOWERGIFT,:HARVEST,:FORECAST,:STEAMPOWERED],
  [:SWIFTSWIM,:RAINDISH,:DRYSKIN,:FORECAST,:STEAMPOWERED],
  [:ICEBODY,:SLUSHRUSH,:SNOWCLOAK,:ICEFACE,:FORECAST],
  [:SANDRUSH,:SANDVEIL,:SANDFORCE,:FORECAST],
  [:STARSPRINT],
  [:NOCTEMBOOST],
  [:TOXICRUSH],
  [:SURGESURFER,:QUARKDRIVE],
  [:MEADOWRUSH],
  [nil],
  [:BRAINBLAST],
  [:SLUDGERUSH]]
  idx = -1
  setter.each do |abil|
    idx += 1
    break if abil.include?(move.id)
  end
  party = ai.battle.pbParty(user.index)
  next if weather[idx] == ai.battle.pbWeather
  next if weather[idx] == ai.battle.field.terrain
  if weather[idx] != ai.battle.pbWeather
    if user.has_role?(:WEATHERTERRAIN)
      mod = party.any? {|pkmn| !pkmn.fainted? && pkmn.has_role?(:WEATHERTERRAINABUSER) && ability[idx].include?(pkmn.ability_id)}
      add = mod ? 8 : 5
      score += add
      PBAI.log_score(move,add,"+ #{add} to set weather for abuser in the back")
    end
  elsif weather[idx] != ai.battle.field.terrain
    if user.has_role?(:WEATHERTERRAIN)
      mod = party.any? {|pkmn| !pkmn.fainted? && pkmn.has_role?(:WEATHERTERRAINABUSER) && ability[idx].include?(pkmn.ability_id)}
      add = mod ? 8 : 5
      score += add
      PBAI.log_score(move,add,"+ #{add} to set terrain for abuser in the back")
    end
  else
    score -= 15
    PBAI.log_score(move,-15,"- 15 to prevent failing")
  end
  next score
end

# Ally considerations
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next if !ai.battle.doublebattle
  if target.side != user.side
    # If the move is a status move, we can assume it has a positive effect and thus would be good for our ally too.
    if !move.statusMove?
      target_type = move.pbTarget(user)
      # If the move also targets our ally
      if [:AllNearOthers,:AllBattlers,:BothSides].include?(target_type)
        # See if we have an ally
        if ally = user.side.battlers.find { |proj| proj && proj != user && !proj.fainted? }
          matchup = ally.calculate_move_matchup(move.id)
          # The move would be super effective on our ally
          if matchup > 1
            decr = (matchup / 2.0 * 5.0).round
            score -= decr
            PBAI.log_score(move,decr*-1,"- #{decr} for super effectiveness on ally battler")
          end
        end
      end
    end
  end
  next score
end

# Immunity modifier
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next if $inverse
  next score if user.effects[PBEffects::EncoreMove] == move.id
  if !move.statusMove? && user.target_is_immune?(move, target) && !user.choice_locked?
    score -= 10
    PBAI.log_score(move,-10,"- 10 for the target being immune")
  end
  if user.choice_locked? && user.target_is_immune?(move, target) && user.can_switch?
    score -= 10
    PBAI.log_score(move,-10,"- 10 for the target being immune and us being choice locked")
  end
  next score
end

# Disabled modifier
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  if user.effects[PBEffects::DisableMove] == move.id
    score -= 10
    PBAI.log_score(move,-10,"- 10 for the move being disabled")
  end
  next score
end

# Threat score modifier
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next if move.statusMove?
  next score if user.effects[PBEffects::EncoreMove] == move.id
  threat = PBAI.threat_score(user,target)
  threat = 1 if threat <= 0
  if user.target_is_immune?(move,target) && !$inverse && user.effects[PBEffects::ChoiceBand] != move.id
    score -= 20
    PBAI.log_score(move,-20,"- 20 for extra weight against using ineffective moves")
  else
    if threat > 1 && threat < 7
      score += (threat/2).floor
      PBAI.log_score(move,(threat/2).floor,"+ #{(threat/2).floor} to weight move scores vs this target.")
    elsif threat >= 7
      if move.damagingMove?
        score += threat
        PBAI.log_score(move,threat,"+ #{threat} to add urgency to killing the threat.")
      end
    end
  end
  next score
end

# Setup prevention when kill is seen modifier
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next score unless move.statusMove?
  next score if move.id == :DESTINYBOND
  next score if user.effects[PBEffects::EncoreMove] == move.id
  minus = 0
  minus = 20 if user.fast_kill?(target)
  minus = 20 if user.slow_kill?(target)
  minus = 20 if user.target_fast_kill?(target)
  minus = 20 if user.target_has_fast_2hko?(target)

  next score if minus == 0
  score -= minus
  PBAI.log_score(move,minus,"- #{minus} because we should prioritize attacking moves")
  next score
end

# Effectiveness modifier
# For this to have a more dramatic effect, this block could be moved lower down
# so that it factors in more score modifications before multiplying.
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  # Effectiveness doesn't add anything for fixed-damage moves.
  next if move.is_a?(PokeBattle_FixedDamageMove) || move.statusMove?
  next score if user.effects[PBEffects::EncoreMove] == move.id
  # Add half the score times the effectiveness modifiers. Means super effective
  # will be a 50% increase in score.
  target_types = target.types
  mod = move.pbCalcTypeMod(move.pbBaseType(user), user, target) / Effectiveness::NORMAL_EFFECTIVE.to_f
  # If mod is 0, i.e. the target is immune to the move (based on type, at least),
  # we do not multiply the score to 0, because immunity is handled as a final multiplier elsewhere.
  case ai.battle.pbWeather
  when :HarshSun
    mod = 0 if move.type == :WATER
  when :HeavyRain
    mod = 0 if move.type == :FIRE
  end
  if mod == 0
    score -= 20
    PBAI.log_score(move,-20,"- 20 because this will do nothing")
  end
  next score
end

# Factoring in immunity to all status moves
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next if move.damagingMove?
  next if move.id == :SLEEPTALK
  if target.immune_to_status?(user)
    score -= 20
    PBAI.log_score(move,-20,"- 20 for the move being ineffective")
  end
  next score
end

# Adding score based on the ability to outspeed and KO
PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  next score if [:FAKEOUT,:FIRSTIMPRESSION].include?(move.id)
  next score if user.effects[PBEffects::DisableMove] == move.id
  count = 0
  o_count = 0
  se = 0
  user.moves.each do |m|
    next if m.statusMove?
    count += 1 if user.get_calc_self(target, m) >= target.hp
    matchup = target.calculate_move_matchup(m.id)
    se += 1 if matchup > 1
  end
  prio_kill = false
  target.moves.each do |t|
    next if t.statusMove?
    o_count += 1 if user.get_calc(target, t) >= user.hp
    prio_kill = true if user.get_calc(target,t) >= user.hp && t.priority > 0
  end
  faster = user.faster_than?(target)
  fast_kill = faster
  slow_kill = !faster && count == 0 && o_count > 0
  user_slow_kill = !faster && o_count == 0 && count > 0
  target_fast_kill = (!faster && o_count > 0) || prio_kill
  prankster = user.hasActiveAbility?(:PRANKSTER) && !target.types.include?(:DARK)
  inflict_status = [PokeBattle_BurnMove,PokeBattle_SleepMove,PokeBattle_FreezeMove,PokeBattle_ParalysisMove,PokeBattle_PoisonMove]
  inflict_status_function = ["0E7","0E2"]
  last_status = move.statusMove? && (inflict_status_function.include?(move.function) || inflict_status.any? {|mov| move.is_a?(mov)})
  if (move.statusMove? && prio_kill || move.statusMove? && move.id != :DESTINYBOND && target_fast_kill && !prankster)
    prev = score
    score = 0
    PBAI.log_ai("- #{prev} because we will not be able to get a status move off without dying")
  elsif last_status && !fast_kill && !user_slow_kill && (prankster || faster)
    add = (9 + PBAI.threat_score(user,target))
    score += add
    PBAI.log_ai("+ #{add} to get a last ditch status off against target")
  end
  if count > 0
    if move.damagingMove? && user.get_calc_self(target, move) >= target.hp
      if fast_kill
        add = 15
      elsif target_fast_kill
        add = 5
      elsif user_slow_kill
        add = 12
      else
        add = 0
      end
      score += add
      if target_fast_kill
        PBAI.log_ai("+ 5 because we kill even though they kill us first")
      elsif fast_kill
        PBAI.log_ai("+ #{add} for fast kill")
      elsif user_slow_kill
        PBAI.log_ai("+ #{add} for slow kill")
      end
    end
    $ai_flags[:can_kill] = true
  else
    $ai_flags[:can_kill] = false if se == 0
    move_damage = []
    ind = 0
    user.moves.each do |m|
      next if m.statusMove?
      next if [:FINALGAMBIT,:FAKEOUT,:FIRSTIMPRESSION].include?(m.id)
      temp = [m,user.get_calc_self(target, m),ind]
      move_damage.push(temp)
      ind += 1
    end
    if move_damage.length > 1
      move_damage.sort! do |a,b|
        if b[1] != a[1]
          b[1] <=> a[1]
        else
          a[2] <=> b[2]
        end
      end
    elsif move_damage.length == 0
      if move.id == :ASSIST
        info = [move,1,0]
        move_damage.push(info)
      else
        i = 0
        user.moves.each do |mo|
          data = [mo,1,i]
          move_damage.push(data)
          i += 1
        end
      end
    end
    if move_damage[0][0] == move
      add = 4
      score += add
      PBAI.log_ai("+ #{add} to prefer highest damaging move or first status move")
    end
  end
  if user.moves.length == 1
    score += 10
    PBAI.log_ai("+ 10 to bypass Struggle issues with choiced single-move mons")
  end
  if score <= 0
    score = (user.target_is_immune?(move,target) || move.statusMove?) ? 0 : 1
    PBAI.log_ai("Set score to 1 if less than 1 to prevent going for Struggle") if score > 0
  end
  next score
end

PBAI::ScoreHandler.add_final do |score, ai, user, target, move|
  PBAI.debug_score
  next score
end