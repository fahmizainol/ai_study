=begin
#Defensive Role modifiers
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	roles = []
    for i in proj.pokemon.roles
      roles.push(i)
    end
  mon = ai.pbMakeFakeBattler(proj.pokemon)
  battler.opposing_side.battlers.each do |target|
  	next if target.nil?
  	if target.is_physical_attacker? && [:PHYSICALWALL].include?(roles)
  		score += 3
  		PBAI.log_switch(proj.pokemon.name,"+ 3")
  	end
  	if target.is_special_attacker? && [:SPECIALWALL].include?(roles)
  		score += 3
  		PBAI.log_switch(proj.pokemon.name,"+ 3")
  	end
  	if mon.defensive? && ![:PHYSICALWALL,:SPECIALWALL].include?(roles)
  		if [:DEFENSIVEPIVOT,:CLERIC,:TOXICSTALLER,:LEAD,:TANK].include?(roles)
  			score += 2
  			PBAI.log_switch(proj.pokemon.name,"+ 2")
  		else
  			score += 1
  			PBAI.log_switch(proj.pokemon.name,"+ 1")
  		end
  	end
  end
	next score
end
=end
#Setup Prevention
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	setup = 0
	add = 0
	target_moves = target.moves
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if target_moves != nil
		for i in target_moves
			if PBAI::AI_Move.setup_move?(i)
				setup += 1
			end
		end
	end
	if setup >= 1
		add = setup
		score += add
		PBAI.log_switch(proj.pokemon.name,"+ #{add} to prevent setup")
		$learned_flags[:has_setup].push(target)
	end
	next score
end

#Identifying Setup Fodder
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	next score if $switch_flags[:setup_fodder].nil?
	pkmn = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:setup_fodder].include?(target)
		party = ai.battle.pbParty(battler.index)
		setup_mons = party.find_all {|mon| mon.has_role?([:SETUPSWEEPER,:WINCON]) && mon.moves.any? {|move| PBAI::AI_Move.setup_move?(move)}}
		strong_moves = target.moves.find_all {|targ_move| proj.get_calc(target,targ_move) >= pkmn.hp/2}
		setup_mons.each do |pk|
			next if pk != pkmn
			score += 1 if pk.faster_than?(target)
			score += 1 if target.bad_against?(pk)
			score -= 2 if pk.bad_against?(target)
			score -= 1 if strong_moves.length > 0
			score += 1 if PBAI.threat_score(pk,target) <= 0
		end
	end
	next score
end
=begin
#Health Related
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if mon.hp <= mon.totalhp/4
		score -= 10
		PBAI.log_switch(proj.pokemon.name,"- 10")
	end
	if ai.battle.positions[battler.index].effects[PBEffects::Wish] > 0 && mon.hp <= mon.totalhp/3
		score += 4
		PBAI.log_switch(proj.pokemon.name,"+ 4")
		score += 2 if mon.setup?
		PBAI.log_switch(proj.pokemon.name,"+ 2") if mon.setup?
	end
	if $switch_flags[:need_cleric] && mon.has_role?(:CLERIC)
		score += 4
		PBAI.log_switch(proj.pokemon.name,"+ 4")
	end
	next score
end
=end
# Hazards related
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	rocks = proj.own_side.effects[PBEffects::StealthRock] ? 1 : 0
	shards = proj.own_side.effects[PBEffects::CometShards] ? 1 : 0
  webs = proj.own_side.effects[PBEffects::StickyWeb] ? 1 : 0
  spikes = proj.own_side.effects[PBEffects::Spikes] > 0 ? proj.own_side.effects[PBEffects::Spikes] : 0
  tspikes = proj.own_side.effects[PBEffects::ToxicSpikes] > 0 ? proj.own_side.effects[PBEffects::ToxicSpikes] : 0
	if mon.takesIndirectDamage?
		hazard_score = 0
	  hazard_score = (rocks) + (spikes) + (tspikes) + (shards)
	  if hazard_score > 0
	  	score -= hazard_score
	  	PBAI.log_switch(proj.pokemon.name,"- #{hazard_score}")
	  end
	end

  #Switch in to absorb hazards
  if tspikes > 0 && (mon.pbHasType?(:POISON) && !mon.airborne? && mon.item != :HEAVYDUTYBOOTS)
  	score += 4
  	PBAI.log_switch(proj.pokemon.name,"+ 4")
  end
  next score
end

# Tag Battles say hisssss
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	next if !ai.battle.doublebattle
	if proj.pokemon.owner.id != battler.pokemon.owner.id
		score -= 100
		PBAI.log_switch(proj.pokemon.name,"- 100 because it's not yours")
	end
  next score
end

PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
  next score if !ai.battle.doublebattle
  mon = ai.pbMakeFakeBattler(proj.pokemon)
	ally = battler.side.battlers.find {|pm| pm && pm != battler && !pm.fainted?}
	next score if ally.nil?
	for move in ally.moves
		if ally.target_is_immune?(move,battler) && [:AllNearOthers,:AllBattlers,:BothSides].include?(move.pbTarget(mon))
			score += 2
			PBAI.log_switch(proj.pokemon.name,"+ 2")
		end
	end
  next score
end

PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if proj.fast_kill?(target)
		score += 5
		PBAI.log_switch(proj.pokemon.name,"+ 5 because battler can kill before being killed")
	elsif proj.fast_2hko?(target) && !proj.target_has_2hko?(target)
		score += 3
		PBAI.log_switch(proj.pokemon.name,"+ 3 because battler can 2HKO and avoid being 2HKOd")
	else
		move = battler.target_highest_damaging_move(target)
		PBAI.log_ai("#{move.name} from target registered as highest damaging move vs current battler")
		if proj.target_has_kill_with_move?(target,move)
			score -= 5
			PBAI.log_switch(proj.pokemon.name,"- 5 because battler can be killed by #{move.name} on switch in")
		elsif proj.target_has_fast_2hko_with_move?(target,move)
			score -= 3
			PBAI.log_switch(proj.pokemon.name,"- 3 because battler will be killed by #{move.name} if taking 2 hits")
		else
			score -= 1
			PBAI.log_switch(proj.pokemon.name,"- 1 due to switch being not optimal")
		end
	end
  next score
end

#========================
# Type-base Switch Scoring
#========================
PBAI::SwitchHandler.add_type(:FIRE) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:fire] == true
	  if mon.hasActiveAbility?([:FLASHFIRE,:STEAMENGINE,:WELLBAKEDBODY]) || mon.hasActiveItem?(:FLASHFIREORB)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Fire immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:FIRE,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	  if mon.hasActiveAbility?(:THERMALEXCHANGE) 
	    score += 1
	    PBAI.log_switch(proj.pokemon.name,"+ 1 to gain a boost from Fire moves")
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:WATER) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:water] == true
	  if mon.hasActiveAbility?([:WATERABSORB,:DRYSKIN,:STORMDRAIN,:STEAMENGINE,:WATERCOMPACTION]) || mon.hasActiveItem?(:WATERABSORBORB)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Water immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:WATER,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:GRASS) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:grass] == true
	  if mon.hasActiveAbility?(:SAPSIPPER) || mon.hasActiveItem?(:SAPSIPPERORB)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Grass immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:GRASS,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:ELECTRIC) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:electric] == true
	  if mon.hasActiveAbility?([:VOLTABSORB,:LIGHTNINGROD,:MOTORDRIVE]) || mon.hasActiveItem?(:LIGHTNINGRODORB)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Electric immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:ELECTRIC,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:GROUND) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:ground] == true
	  if mon.hasActiveAbility?(:EARTHEATER) || mon.airborne? || mon.hasActiveItem?([:EARTHEATERORB,:LEVITATEORB])
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Ground immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:GROUND,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	  for i in target.moves
	  	if proj.calculate_move_matchup(i.id) < 1 && i.function == "TwoTurnAttackInvulnerableUnderground"
	  		dig = true
	  	end
	  	if proj.calculate_move_matchup(i.id) > 1 && i.function == "TwoTurnAttackInvulnerableUnderground"
	  		no_dig = true
	  	end
	  end
	  if dig == true && $switch_flags[:digging] == true
	  	score += 1
	  	PBAI.log_switch(proj.pokemon.name,"+ 1 to be immune to Dig")
	  end
	  if no_dig == true && $switch_flags[:digging] == true
	  	score -= 10
	  	PBAI.log_switch(proj.pokemon.name,"- 10")
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:DARK) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	pos = ai.battle.positions[battler.index]
	party = ai.battle.pbParty(battler.index)
	if $switch_flags[:dark] == true
	  if mon.hasActiveAbility?(:UNTAINTED)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Dark immunity")
	  elsif mon.hasActiveAbility?(:JUSTIFIED)
	  	score += 1
	  	PBAI.log_switch(proj.pokemon.name,"+ 1 to gain a boost from Dark moves")
	  else
	  	eff = Effectiveness.super_effective_type?(:DARK,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:POISON) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:poison] == true
	  if mon.hasActiveAbility?(:PASTELVEIL)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Poison immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:POISON,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:ROCK) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:rock] == true
	  if mon.hasActiveAbility?(:SCALER)  || mon.hasActiveItem?(:SCALERORB)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Rock immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:ROCK,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:DRAGON) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:dragon] == true
	  if mon.hasActiveAbility?(:LEGENDARMOR)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Dragon immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:DRAGON,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	end
	next score
end

PBAI::SwitchHandler.add_type(:COSMIC) do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	if $switch_flags[:cosmic] == true
	  if mon.hasActiveAbility?(:DIMENSIONBLOCK) || mon.hasActiveItem?(:DIMENSIONBLOCKORB)
	    score += 2
	    PBAI.log_switch(proj.pokemon.name,"+ 2 for Cosmic immunity")
	  else
	  	eff = Effectiveness.super_effective_type?(:COSMIC,mon.type1,mon.type2,mon.effects[PBEffects::Type3])
		  if eff
		  	add = score
		  	score = 0
		  	PBAI.log_switch(proj.pokemon.name,"-#{add} to prevent switching into a super effective move")
		  end
	  end
	end
	next score
end

PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	mon = ai.pbMakeFakeBattler(proj.pokemon)
	party = ai.battle.pbParty(battler.index)
	able_party = party.find_all {|pkmn| pkmn && !pkmn.fainted? && !pkmn.egg?}
  if mon.hasActiveAbility?(:SUPREMEOVERLORD) && able_party.length != 1
  	nope = able_party.length
    score -= nope
    PBAI.log_switch(proj.pokemon.name,"-#{nope} for attempting to use Supreme Overlord effectively")
  end
	next score
end

PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	move = battler.target_highest_damaging_move(target)
	matchup = proj.calculate_move_matchup(move.id)
  type_matchup = proj.calculate_type_matchup(target)/8
  immune = 0
  if matchup < 2.0
  	immune = matchup + type_matchup
  elsif matchup >= 2.0
   	immune = -4
  end
  if matchup == 0.0
  	immune *= 2
  	immune = 1 if immune < 1
  end
  immune = 20 if matchup == 0.0
  $switch_flags[:immunity] = proj if matchup == 0.0
  score += immune
  PBAI.log_switch(proj.pokemon.name,"+ #{immune} for the matchup score")
  next score
end

#Don't switch if weak to pursuit
PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	next unless target.pokemon.hasMove?(:PURSUIT)
  matchup = battler.calculate_move_matchup(:PURSUIT)
  immune = 0
  if matchup >= 2.0
  	immune = -10
  end
	PBAI.log_switch(proj.pokemon.name,"#{immune} because we are weak to Pursuit") if immune < 0
	next score
end

PBAI::SwitchHandler.add do |score,ai,battler,proj,target|
	next score if PBAI.threat_score(battler,target) != 50
	score -= 10
	PBAI.log_switch(proj.pokemon.name,"- 10 because the target gets fast OHKO on the entire party")
	PBAI.debug_switch
	next score
end