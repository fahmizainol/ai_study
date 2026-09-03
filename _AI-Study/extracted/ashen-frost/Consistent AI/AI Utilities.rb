$aiberrycheck=false
class Battle::AI
	attr_accessor :damagesAI  

	alias consistent_ai_initialize initialize
	def initialize(battle)
		consistent_ai_initialize(battle)
		@damagesAI = {}
	end
	
	def pbDefaultChooseEnemyCommand(idxBattler)
		#return if pbEnemyShouldUseItem?(idxBattler)
		return if pbEnemyShouldWithdraw?(idxBattler)
		return if @battle.pbAutoFightMenu(idxBattler)
		@battle.pbRegisterMegaEvolution(idxBattler) if pbEnemyShouldMegaEvolve?(idxBattler)
		if PluginManager.installed?("ZUD Mechanics")
			@battle.pbRegisterUltraBurst(idxBattler) if pbEnemyShouldUltraBurst?(idxBattler)
			@battle.pbRegisterDynamax(idxBattler) if pbEnemyShouldDynamax?(idxBattler)
		end
		if PluginManager.installed?("Terastal Phenomenon")
			@battle.pbRegisterTerastallize(idxBattler) if pbEnemyShouldTerastallize?(idxBattler)
		end
		if PluginManager.installed?("Pokémon Birthsigns")
			@battle.pbRegisterZodiacPower(idxBattler) if pbEnemyShouldZodiacPower?(idxBattler)
		end
		if PluginManager.installed?("Focus Meter System")
			@battle.pbRegisterFocus(idxBattler) if pbEnemyShouldFocus?(idxBattler)
		end
		if PluginManager.installed?("Essentials Deluxe")
			if !@battle.pbScriptedMechanic?(idxBattler, :custom) && pbEnemyShouldCustom?(idxBattler)
				@battle.pbRegisterCustom(idxBattler)
			end
		end	
		pbChooseMoves(idxBattler)
		if PluginManager.installed?("PLA Battle Styles") # Purposefully set after move selection.
			@battle.pbRegisterStyle(idxBattler) if pbEnemyShouldUseStyle?(idxBattler)
		end
	end
	

	def pbRoughStat(battler, stat, skill,opponent=nil,moldBreaker=false,function="none")
		return battler.pbSpeed if skill >= PBTrainerAI.highSkill && stat == :SPEED
		stageMul = [2, 2, 2, 2, 2, 2, 2, 3, 4, 5, 6, 7, 8]
		stageDiv = [8, 7, 6, 5, 4, 3, 2, 2, 2, 2, 2, 2, 2]
		stage = battler.stages[stat] + 6
		value = 0
		case stat
		when :ATTACK          
			value = battler.attack
			if opponent
				return value if (opponent.hasActiveAbility?(:UNAWARE) && !moldBreaker) #|| function == "IgnoreTargetDefSpDefEvaStatStages"
			end
		when :DEFENSE
			value = battler.defense
			if opponent
				return value if (opponent.hasActiveAbility?(:UNAWARE) && !moldBreaker) || function == "IgnoreTargetDefSpDefEvaStatStages"
			end
		when :SPECIAL_ATTACK
			value = battler.spatk
			if opponent
				return value if (opponent.hasActiveAbility?(:UNAWARE) && !moldBreaker) #|| function == "IgnoreTargetDefSpDefEvaStatStages"
			end
		when :SPECIAL_DEFENSE
			value = battler.spdef
			if opponent
				return value if (opponent.hasActiveAbility?(:UNAWARE) && !moldBreaker) || function == "IgnoreTargetDefSpDefEvaStatStages"
			end
		when :SPEED           then value = battler.speed
		end
		return (value.to_f * stageMul[stage] / stageDiv[stage]).floor
	  end

	
	def pbRoughDamage(move, user, target, skill, baseDmg=0)
		return 0 if user.effects[PBEffects::HyperBeam] > 0 # DemICE for AI to know its getting a free turn 
		baseDmg = pbMoveBaseDamage(move, user, target, skill)
		# Fixed damage moves
		return baseDmg if move.is_a?(Battle::Move::FixedDamageMove)
		# Get the move's type
		type = pbRoughType(move, user, skill)
		typeMod = pbCalcTypeMod(type,user,target)
		# Ability effects that alter damage
		# moldBreaker = false
		# if skill >= PBTrainerAI.highSkill && user.hasMoldBreaker?
		# 	moldBreaker = true
		# end
		moldBreaker=moldbroken(user,target,move)
		##### Calculate user's attack stat #####
		atk = pbRoughStat(user, :ATTACK, skill,target,moldBreaker,move.function)
		if move.function == "UseTargetAttackInsteadOfUserAttack"   # Foul Play
			atk = pbRoughStat(target, :ATTACK, skill,target,moldBreaker,move.function)
		elsif move.function == "UseUserBaseDefenseInsteadOfUserBaseAttack"   # Body Press
			atk = pbRoughStat(user, :DEFENSE, skill,target,moldBreaker,move.function)
			# Ashen Frost Exclusive
		elsif (move.specialMove?(type) || user.hasActiveItem?(:PWCONVERTER)) && !user.hasActiveItem?(:ENCONVERTER)
			if move.function == "UseTargetAttackInsteadOfUserAttack"   # Foul Play
				atk = pbRoughStat(target, :SPECIAL_ATTACK, skill,target,moldBreaker,move.function)
			else
				atk = pbRoughStat(user, :SPECIAL_ATTACK, skill,target,moldBreaker,move.function)
			end
		end
		##### Calculate target's defense stat #####
		defense = pbRoughStat(target, :DEFENSE, skill,user,moldBreaker,move.function)
		if move.specialMove?(type) && move.function != "UseTargetDefenseInsteadOfTargetSpDef"   # Psyshock
			defense = pbRoughStat(target, :SPECIAL_DEFENSE, skill)
		end
		##### Calculate all multiplier effects #####
		multipliers = {
			:base_damage_multiplier  => 1.0,
			:attack_multiplier       => 1.0,
			:defense_multiplier      => 1.0,
			:final_damage_multiplier => 1.0
		}
		if skill >= PBTrainerAI.mediumSkill && user.abilityActive?
			# NOTE: These abilities aren't suitable for checking at the start of the
			#       round.    # DemICE: some of them.
			abilityBlacklist = [:ANALYTIC, :SNIPER]#, :TINTEDLENS, :AERILATE, :PIXILATE, :REFRIGERATE]
			canCheck = true
			abilityBlacklist.each do |m|
				#next if move.id != m # Really? comparing a move id with an ability id? This blacklisting never worked.
				if target.hasActiveAbility?(m)
					canCheck = false
					break
				end
			end
			if canCheck
				Battle::AbilityEffects.triggerDamageCalcFromUser(
					user.ability, user, target, move, multipliers, baseDmg, type
				)
			end
		end
		if skill >= PBTrainerAI.mediumSkill && !moldBreaker
			user.allAllies.each do |b|
				next if !b.abilityActive?
				Battle::AbilityEffects.triggerDamageCalcFromAlly(
					b.ability, user, target, move, multipliers, baseDmg, type
				)
			end
		end
		if skill >= PBTrainerAI.bestSkill && !moldBreaker && target.abilityActive?
			# NOTE: These abilities aren't suitable for checking at the start of the
			#       round.    #DemICE:  WHAT THE FUCK DO YOU MEAN THEY AREN'T SUITABLE FFS
			abilityBlacklist = [:FILTER,:SOLIDROCK]
			canCheck = true
			abilityBlacklist.each do |m|
				#next if move.id != m # Really? comparing a move id with an ability id? This blacklisting never worked.
				if target.hasActiveAbility?(m)
					canCheck = false
					break
				end
			end
			if canCheck
				Battle::AbilityEffects.triggerDamageCalcFromTarget(
					target.ability, user, target, move, multipliers, baseDmg, type
				)
			end
		end
		if skill >= PBTrainerAI.bestSkill && !moldBreaker
			target.allAllies.each do |b|
				next if !b.abilityActive?
				Battle::AbilityEffects.triggerDamageCalcFromTargetAlly(
					b.ability, user, target, move, multipliers, baseDmg, type
				)
			end
		end
		# Item effects that alter damage
		# NOTE: Type-boosting gems aren't suitable for checking at the start of the
		#       round.
		if skill >= PBTrainerAI.mediumSkill && user.itemActive?
			# NOTE: These items aren't suitable for checking at the start of the
			#       round.     #DemICE:  WHAT THE FUCK DO YOU MEAN THEY AREN'T SUITABLE FFS
			itemBlacklist = [:EXPERTBELT]#,:LIFEORB]
			 if !itemBlacklist.include?(user.item_id)
			Battle::ItemEffects.triggerDamageCalcFromUser(
				user.item, user, target, move, multipliers, baseDmg, type
			)
			user.effects[PBEffects::GemConsumed] = nil   # Untrigger consuming of Gems
			end
		end
		if skill >= PBTrainerAI.bestSkill &&							# DemICE: I now have high suspicions that the chilan berry thing doesn't work.
			target.itemActive? && target.item && !target.item.is_berry?# && target.item_id!=:CHILANBERRY)
			Battle::ItemEffects.triggerDamageCalcFromTarget(
				target.item, user, target, move, multipliers, baseDmg, type
			)
		end
		# Global abilities
		if skill >= PBTrainerAI.mediumSkill &&
			((@battle.pbCheckGlobalAbility(:DARKAURA) && type == :DARK) ||
				(@battle.pbCheckGlobalAbility(:FAIRYAURA) && type == :FAIRY))
			if @battle.pbCheckGlobalAbility(:AURABREAK)
				multipliers[:base_damage_multiplier] *= 2 / 3.0
			else
				multipliers[:base_damage_multiplier] *= 4 / 3.0
			end
		end
		# Parental Bond
		if skill >= PBTrainerAI.mediumSkill && user.hasActiveAbility?(:PARENTALBOND)
			multipliers[:base_damage_multiplier] *= 1.25
		end
		#---------------------------------------------------------------------------
		# Added for "of Ruin" abilities
		#---------------------------------------------------------------------------
		if skill >= PBTrainerAI.mediumSkill
		  [:TABLETSOFRUIN, :SWORDOFRUIN, :VESSELOFRUIN, :BEADSOFRUIN].each_with_index do |abil, i|
			category = (i < 2) ? move.physicalMove? : move.specialMove?
			category = !category if i.odd? && @battle.field.effects[PBEffects::WonderRoom] > 0
			mult = (i.even?) ? multipliers[:attack_multiplier] : multipliers[:defense_multiplier]
			mult *= 0.75 if @battle.pbCheckGlobalAbility(abil) && !user.hasActiveAbility?(abil) && category
		  end
		end
		# Me First
		# TODO
		# Helping Hand - n/a
		# Charge
		if skill >= PBTrainerAI.mediumSkill &&
			user.effects[PBEffects::Charge] > 0 && type == :ELECTRIC
			multipliers[:base_damage_multiplier] *= 2
		end
		# Mud Sport and Water Sport
		if skill >= PBTrainerAI.mediumSkill
			if type == :ELECTRIC
				if @battle.allBattlers.any? { |b| b.effects[PBEffects::MudSport] }
					multipliers[:base_damage_multiplier] /= 3
				end
				if @battle.field.effects[PBEffects::MudSportField] > 0
					multipliers[:base_damage_multiplier] /= 3
				end
			end
			if type == :FIRE
				if @battle.allBattlers.any? { |b| b.effects[PBEffects::WaterSport] }
					multipliers[:base_damage_multiplier] /= 3
				end
				if @battle.field.effects[PBEffects::WaterSportField] > 0
					multipliers[:base_damage_multiplier] /= 3
				end
			end
		end
		# Freeze-Dry because i cant be bothered to figure out the move effectiveness shit in this part of the code.
		if move.function == "FreezeTargetSuperEffectiveAgainstWater" && target.pbHasType?(:WATER)
			multipliers[:base_damage_multiplier] *= 4 
		end
		# Terrain moves
		if skill >= PBTrainerAI.mediumSkill
			case @battle.field.terrain
			when :Electric
				multipliers[:base_damage_multiplier] *= 1.3 if type == :ELECTRIC && user.affectedByTerrain?
			when :Grassy
				multipliers[:base_damage_multiplier] *= 1.3 if type == :GRASS && user.affectedByTerrain?
			when :Psychic
				multipliers[:base_damage_multiplier] *= 1.3 if type == :PSYCHIC && user.affectedByTerrain?
			when :Misty
				multipliers[:base_damage_multiplier] /= 2 if type == :DRAGON && target.affectedByTerrain?
			end
		end
		# Badge multipliers
		if skill >= PBTrainerAI.highSkill && @battle.internalBattle && target.pbOwnedByPlayer?
			if move.physicalMove?(type) && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_DEFENSE
				multipliers[:defense_multiplier] *= 1.1
			elsif move.specialMove?(type) && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_SPDEF
				multipliers[:defense_multiplier] *= 1.1
			end
		end
		# DemICE interaction with super-effective moves.
		if Effectiveness.super_effective?(typeMod)
			if user.hasActiveItem?(:EXPERTBELT)
				multipliers[:final_damage_multiplier]*=1.2
			end
			if target.hasActiveAbility?([:SOLIDROCK, :FILTER]) && !moldBreaker
				multipliers[:final_damage_multiplier]*=0.75
			end
			if target.itemActive?
				case target.item_id
				when :BABIRIBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:STEEL
				when :SHUCABERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:GROUND
				when :CHARTIBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:ROCK
				when :CHOPLEBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:FIGHTING
				when :COBABERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:FLYING
				when :COLBURBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:DARK
				when :HABANBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:DRAGON
				when :KASIBBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:GHOST
				when :KEBIABERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:POISON
				when :OCCABERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:FIRE
				when :PASSHOBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:WATER
				when :PAYAPABERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:PSYCHIC
				when :RINDOBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:GRASS
				when :ROSELIBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:FAIRY
				when :TANGABERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:BUG
				when :WACANBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:ELECTRIC
				when :YACHEBERRY
					multipliers[:final_damage_multiplier]*=0.5 if type==:ICE
				end
			end  
		end
		# Multi-targeting attacks
		if skill >= PBTrainerAI.highSkill && pbTargetsMultiple?(move, user)
			multipliers[:final_damage_multiplier] *= 0.75
		end
		# Weather
		if skill >= PBTrainerAI.mediumSkill
			case user.effectiveWeather
			when :Sun, :HarshSun
				case type
				when :FIRE
					multipliers[:final_damage_multiplier] *= 1.5
				when :WATER
					if move.function == "IncreasePowerInSunWeather"
						multipliers[:final_damage_multiplier] *= 1.5
					else
						multipliers[:final_damage_multiplier] /= 2
					end
				end
			when :Rain, :HeavyRain, :FreezingRain
				case type
				when :FIRE
					multipliers[:final_damage_multiplier] /= 2
				when :WATER
					multipliers[:final_damage_multiplier] *= 1.5
				end
			when :Sandstorm
				if target.pbHasType?(:ROCK) && move.specialMove?(type) &&
					move.function != "UseTargetDefenseInsteadOfTargetSpDef"   # Psyshock
					multipliers[:defense_multiplier] *= 1.5
				end
			when :Hail 
				if PluginManager.installed?("Generation 9 Pack") && Settings::HAIL_WEATHER_TYPE > 0
					if target.pbHasType?(:ICE) && (move.physicalMove?(type) ||
						move.function == "UseTargetDefenseInsteadOfTargetSpDef")   # Psyshock
						multipliers[:defense_multiplier] *= 1.5
					end
				end
			# Ashen Frost weather type buffs/debuffs
			when :FrozenStorm
				case type
				when :WATER, :ICE, :ELECTRIC
					multipliers[:final_damage_multiplier] *= 1.5
				when :FIRE
					multipliers[:final_damage_multiplier] /= 2
				end
			when :HolyInferno
				case type
				when :FIRE
					multipliers[:final_damage_multiplier] *= 1.5
				when :NORMAL, :PSYCHIC
					multipliers[:final_damage_multiplier] *= 1.3
				when :WATER
					if move.function == "IncreasePowerInSunWeather"
						multipliers[:final_damage_multiplier] *= 1.5
					else
						multipliers[:final_damage_multiplier] /= 2
					end
				end
			when :SolarWinds
				case type
				when :FIRE, :PSYCHIC
					multipliers[:final_damage_multiplier] *= 1.5
				when :STEEL
					multipliers[:final_damage_multiplier] /= 2
				end

			end
		end
		# Critical hits - n/a
		# Random variance - n/a
		# DemICE encourage AI to use stronger moves to avoid opponent surviving from low damage roll.
		multipliers[:final_damage_multiplier] *= 0.9 if $PokemonGlobal.damage_variance == 0  # DemICE
		# STAB
		if skill >= PBTrainerAI.mediumSkill && type && user.pbHasType?(type)
			if user.hasActiveAbility?(:ADAPTABILITY)
				multipliers[:final_damage_multiplier] *= 2
			else
				multipliers[:final_damage_multiplier] *= 1.5
			end
		end
		# Type effectiveness
		if skill >= PBTrainerAI.mediumSkill
			typemod = pbCalcTypeMod(type, user, target)
			multipliers[:final_damage_multiplier] *= typemod.to_f / Effectiveness::NORMAL_EFFECTIVE
		end
		# Burn
		if skill >= PBTrainerAI.highSkill && move.physicalMove?(type) &&
			user.status == :BURN && !user.hasActiveAbility?(:GUTS) &&
			!(Settings::MECHANICS_GENERATION >= 6 &&
				move.function == "DoublePowerIfUserPoisonedBurnedParalyzed")   # Facade
			multipliers[:final_damage_multiplier] /= 2
		end
		#---------------------------------------------------------------------------
		# Added for Drowsy
		#---------------------------------------------------------------------------
		if skill >= PBTrainerAI.highSkill && user.status == :DROWSY
		  multipliers[:final_damage_multiplier] *= 4 / 3.0
		end
		#---------------------------------------------------------------------------
		# Added for Frostbite
		#---------------------------------------------------------------------------
		if skill >= PBTrainerAI.highSkill && move.specialMove?(type) && user.status == :FROSTBITE
		  multipliers[:final_damage_multiplier] /= 2
		end
		# Aurora Veil, Reflect, Light Screen
		if skill >= PBTrainerAI.highSkill && !move.ignoresReflect? && !user.hasActiveAbility?(:INFILTRATOR)
			if target.pbOwnSide.effects[PBEffects::AuroraVeil] > 0
				if @battle.pbSideBattlerCount(target) > 1
					multipliers[:final_damage_multiplier] *= 2 / 3.0
				else
					multipliers[:final_damage_multiplier] /= 2
				end
			elsif target.pbOwnSide.effects[PBEffects::Reflect] > 0 && move.physicalMove?(type)
				if @battle.pbSideBattlerCount(target) > 1
					multipliers[:final_damage_multiplier] *= 2 / 3.0
				else
					multipliers[:final_damage_multiplier] /= 2
				end
			elsif target.pbOwnSide.effects[PBEffects::LightScreen] > 0 && move.specialMove?(type)
				if @battle.pbSideBattlerCount(target) > 1
					multipliers[:final_damage_multiplier] *= 2 / 3.0
				else
					multipliers[:final_damage_multiplier] /= 2
				end
			end
		end
		# Minimize
		if skill >= PBTrainerAI.highSkill && target.effects[PBEffects::Minimize] && move.tramplesMinimize?
			multipliers[:final_damage_multiplier] *= 2
		end
		#---------------------------------------------------------------------------
		# Added for Glaive Rush
		#---------------------------------------------------------------------------
		if skill >= PBTrainerAI.highSkill && target.effects[PBEffects::GlaiveRush] > 0
		  multipliers[:final_damage_multiplier] *= 2
		end
		# Move-specific base damage modifiers
		# TODO
		# Move-specific final damage modifiers
		# TODO
		##### Main damage calculation #####
		baseDmg = [(baseDmg * multipliers[:base_damage_multiplier]).round, 1].max
		atk     = [(atk     * multipliers[:attack_multiplier]).round, 1].max
		defense = [(defense * multipliers[:defense_multiplier]).round, 1].max
		damage  = ((((2.0 * user.level / 5) + 2).floor * baseDmg * atk / defense).floor / 50).floor + 2
		damage  = [(damage * multipliers[:final_damage_multiplier]).round, 1].max
		# "AI-specific calculations below"
		# DemICE multihit moves go here instead of base damage because technician calculated them wrong
		case move.function
		when "HitThreeTimesAlwaysCriticalHit" # DemICE Surging strikes
			damage *= 3
		when "HitTwoTimes", "HitTwoTimesPoisonTarget"
			damage *= 2
		when "HitTwoToFiveTimes", "HitTwoToFiveTimesRaiseUserSpd1LowerUserDef1"   # DemICE implementing multihit moves probably
		  if user.hasActiveAbility?(:SKILLLINK)
			damage *= 5
		  elsif user.hasActiveItem?(:LOADEDDICE)
			damage *= 4
		  else
			damage = (damage * 31 / 10).floor   # Average damage dealt
		  end
		when "HitTenTimes"
			accuracy = pbRoughAccuracy(move, user, target, skill)
			if accuracy>=99
				damage*=10
			else
				damage*=6
			end
		when "HitThreeTimesPowersUpWithEachHit"   # Triple Kick
			damage *= 6   # Hits do x1, x2, x3 baseDmg in turn, for x6 in total
		when "HitTwoToFiveTimesOrThreeForAshGreninja"
			if user.isSpecies?(:GRENINJA) && user.form == 2
				damage *= 4   # 3 hits at 20 power = 4 hits at 15 power
			elsif user.hasActiveAbility?(:SKILLLINK)
				damage *= 5
			else
				damage = (damage * 31 / 10).floor   # Average damage dealt
			end
		when "HitTwoTimesFlinchTarget"   # Double Iron Bash
			damage *= 2
			damage *= 2 if skill >= PBTrainerAI.mediumSkill && target.effects[PBEffects::Minimize]
		end
		# Increased critical hit rates
		if skill >= PBTrainerAI.mediumSkill
			c = 0
			# Ability effects that alter critical hit rate
			if c >= 0 && user.abilityActive?
				c = Battle::AbilityEffects.triggerCriticalCalcFromUser(user.ability, user, target, c)
			end
			# DemICE Surging strikes were not handled properly in base essentials.
			c = 3 if ["AlwaysCriticalHit","HitThreeTimesAlwaysCriticalHit"].include?(move.function)
			if skill >= PBTrainerAI.bestSkill && c >= 0 && !moldBreaker && target.abilityActive?
				c = Battle::AbilityEffects.triggerCriticalCalcFromTarget(target.ability, user, target, c)
			end
			# Item effects that alter critical hit rate
			if c >= 0 && user.itemActive?
				c = Battle::ItemEffects.triggerCriticalCalcFromUser(user.item, user, target, c)
			end
			if skill >= PBTrainerAI.bestSkill && c >= 0 && target.itemActive?
				c = Battle::ItemEffects.triggerCriticalCalcFromTarget(target.item, user, target, c)
			end
			# Other efffects
			c = -1 if target.pbOwnSide.effects[PBEffects::LuckyChant] > 0
			if c >= 0
				c += 1 if move.highCriticalRate?
				c += user.effects[PBEffects::FocusEnergy]
				c += 1 if user.inHyperMode? && move.type == :SHADOW
			end
			# DemICE: taking into account 100% crit rate.
			stageMul = [2,2,2,2,2,2, 2, 3,4,5,6,7,8]
			stageDiv = [8,7,6,5,4,3, 2, 2,2,2,2,2,2]
			vatk, atkStage = move.pbGetAttackStats(user,target)
			vdef, defStage = move.pbGetDefenseStats(user,target)
			atkmult = 1.0*stageMul[atkStage]/stageDiv[atkStage]
			defmult = 1.0*stageMul[defStage]/stageDiv[defStage]
			if c==3 && 
				!target.hasActiveAbility?(:SHELLARMOR) && !target.hasActiveAbility?(:BATTLEARMOR) && 
				target.pbOwnSide.effects[PBEffects::LuckyChant]==0
				damage = 0.96*damage/atkmult if atkmult<1
				damage = damage*defmult if defmult>1
			end
			if c >= 0
				c = 4 if c > 4
				if c>=3
					damage*=1.5
					damage*=1.5 if user.hasActiveAbility?(:SNIPER)
				else
					#damage += damage*0.1*c
					damage += damage*0.2 if c >= 2
				end	
			end
		end
		return damage.floor
	end
	
	
	def moldbroken(attacker,opponent,move=attacker.moves[0])
		if (
				attacker.hasActiveAbility?(:MOLDBREAKER) || 
				attacker.hasActiveAbility?(:TURBOBLAZE) || 
				attacker.hasActiveAbility?(:TERAVOLT) ||
				(move.statusMove? && attacker.hasActiveAbility?(:MYCELIUMMIGHT)) ||
				move.function=="IgnoreTargetAbility"
			) && 
			!opponent.hasActiveAbility?(:FULLMETALBODY) && !opponent.hasActiveAbility?(:SHADOWSHIELD)
			return true
		end
		return false	
	end
	
	alias stupidity_pbCheckMoveImmunity pbCheckMoveImmunity
	def pbCheckMoveImmunity(score, move, user, target, skill)
		opponent=user.pbDirectOpposing(true)
		# Changed by DemICE 08-Sep-2023 Yes i had to move Last Resort here to make its score return 0 otherwise it just never became 0.
		if move.function == "FailsIfUserHasUnusedMove" 
			hasThisMove = false
			hasOtherMoves = false
			hasUnusedMoves = false
			user.eachMove do |m|
				hasThisMove    = true if m.id == move.id
				hasOtherMoves  = true if m.id != move.id
				hasUnusedMoves = true if m.id != move.id && !user.movesUsed.include?(m.id)
			end
			if !hasThisMove || !hasOtherMoves || hasUnusedMoves
				return true
			end 
		end  
		return true if move.function == "FailsIfNotUserFirstTurn" && user.turnCount >0 # First Impression
		# DemICE same as last resort above, but for Burn Up
		return true if move.function == "UserLosesFireType" && !user.pbHasType?(:FIRE)
		return true if move.function == "UserLosesElectricType" && !user.pbHasType?(:ELECTRIC)
		# DemICE: Mold Breaker implementation
		type = pbRoughType(move,user,skill)
		typeMod = pbCalcTypeMod(type,user,target)
		mold_broken=moldbroken(user,target,move)
		if ["OHKO","OHKOHitsUndergroundTarget","OHKOIce"].include?(move.function) 
			return true if move.function == "OHKOIce" && target.pbHasType?(:ICE)
			return true if target.hasActiveAbility?(:STURDY,false,mold_broken)
		end
		if ["UserFaintsExplosive","UserFaintsPowersUpInMistyTerrainExplosive"].include?(move.function) 
			return true if @battle.pbCheckGlobalAbility(:DAMP)
		end
		case type
		when :GROUND
			if (target.airborneAI(mold_broken) && !move.hitsFlyingTargets?) ||
				target.hasActiveAbility?(:EARTHEATER,false,mold_broken)
				return true 
			end
		when :FIRE
			return true if target.hasActiveAbility?([:FLASHFIRE,:WELLBAKEDBODY],false,mold_broken)
		when :WATER
			return true if target.hasActiveAbility?([:DRYSKIN,:STORMDRAIN,:WATERABSORB],false,mold_broken)
			target.allAllies.each do |b|
				if b.hasActiveAbility?(:STORMDRAIN) && !pbTargetsMultiple?(move,user) && 
					!user.hasActiveAbility?([:PROPELLERTAIL,:STALWART]) && !move.cannotRedirect? && !move.targetsPosition?
					return true
				end
			end
		when :GRASS
			return true if target.hasActiveAbility?(:SAPSIPPER,false,mold_broken)
		when :ELECTRIC
			return true if target.hasActiveAbility?([:LIGHTNINGROD,:MOTORDRIVE,:VOLTABSORB],false,mold_broken)
			target.allAllies.each do |b|
				if b.hasActiveAbility?(:LIGHTNINGROD) && !pbTargetsMultiple?(move,user) && 
					!user.hasActiveAbility?([:PROPELLERTAIL,:STALWART]) && !move.cannotRedirect? && !move.targetsPosition?
					return true
				end
			end
		end
		return true if !Effectiveness.super_effective?(typeMod) && move.baseDamage>0 && 
		target.hasActiveAbility?(:WONDERGUARD,false,mold_broken)
		return true if move.statusMove? && move.canMagicCoat? && target.hasActiveAbility?(:MAGICBOUNCE,false,mold_broken) &&
		target.opposes?(user)
		return true if move.soundMove? && target.hasActiveAbility?(:SOUNDPROOF,false,mold_broken)
		if PluginManager.installed?("Generation 9 Pack")
			return true if move.windMove? && target.hasActiveAbility?(:WINDRIDER,false,mold_broken)
		end
		return true if move.bombMove? && target.hasActiveAbility?(:BULLETPROOF,false,mold_broken)
		return true if move.statusMove? && target.hasActiveAbility?(:GOODASGOLD,false,mold_broken)
		if move.powderMove?
			return true if target.pbHasType?(:GRASS)
			return true if target.hasActiveAbility?(:OVERCOAT,false,mold_broken)
			return true if target.hasActiveItem?(:SAFETYGOGGLES)
		end
		if priorityAI(user,move) > 0 && target.index != user.index
			@battle.allSameSideBattlers(opponent.index).each do |b|
				return true if b.hasActiveAbility?([:DAZZLING, :QUEENLYMAJESTY, :ARMORTAIL],false,mold_broken) 
			end
			return true if @battle.field.terrain == :Psychic && target.affectedByTerrain? && target.opposes?(user)
		end
		return true  if move.function == "FailsIfTargetHasNoItem" && (!target.item || !target.itemActive?)
		
		return stupidity_pbCheckMoveImmunity(score, move, user, target, skill)
		#return result   
	end	
	
	#=============================================================================
	# Get a better move's base damage value
	#=============================================================================
	alias stupidity_pbMoveBaseDamage pbMoveBaseDamage
	def pbMoveBaseDamage(move,user,target,skill)
		baseDmg = move.baseDamage
		if pbTargetsMultiple?(move, user) && move.function == "HitTwoTimesTargetThenTargetAlly"
			return baseDmg
		end
		case move.function
		when "PowerHigherWithConsecutiveUse",   # DemICE fury cutter needs to consider it will become effect +1 before move executino.
			 "DoublePowerInElectricTerrain",  # DemICE mfw gen 8 pack didnt add AI support for the terrain moves
			 "HitsAllFoesAndPowersUpInPsychicTerrain", 
			 "TypeAndPowerDependOnTerrain", 
			 "UserFaintsPowersUpInMistyTerrainExplosive"
			baseDmg = move.pbBaseDamage(baseDmg, user, target)
			baseDmg += move.baseDamage
		when "AlwaysCriticalHit"
		when "DoublePowerIfUserLostHPThisTurn" , "HitTwoTimesTargetThenTargetAlly"
			baseDmg *= 2
		when "DoublePowerIfUserLostHPThisTurn"
		when "HitOncePerUserTeamMember"   # DemICE beat up was being calculated very wrong.
			beatUpList = []
			@battle.eachInTeamFromBattlerIndex(user.index) do |pkmn,i|
				next if !pkmn.able? || pkmn.status != :NONE
				beatUpList.push(i)
			end
			baseDmg = 0
			for i in beatUpList
				atk = @battle.pbParty(user.index)[i].baseStats[:ATTACK]
				baseDmg+= 5+(atk/10)
			end  
			baseDmg *= 1.5 if user.hasActiveAbility?(:TECHNICIAN)
		when "DoublePowerIfTargetNotActed"
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill,true) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxprio=bestmove[2]
			priod=false
			priod=true if priorityAI(target,maxmove)>0 || (maxprio > maxdam*0.6)
			if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && !priod
				baseDmg *= 2
			end
			# DemICE so that they don't calculate incorrectly.
		when "HitThreeTimesAlwaysCriticalHit" 
		when "HitTwoToFiveTimesOrThreeForAshGreninja"
		when "DoublePowerIfUserLostHPThisTurn"
		when "HitTwoTimesFlinchTarget"   # Double Iron Bash
		when "HitTwoTimes", "HitTwoTimesPoisonTarget"
		when "HitThreeTimesPowersUpWithEachHit"   # Triple Kick
		when "HitTwoToFiveTimes", "HitTwoToFiveTimesRaiseUserSpd1LowerUserDef1" 
		when "HitTenTimes"
		when "IncreasePowerEachFaintedAlly", "IncreaseDamageEachFaintedAllies"
			baseDmg = move.pbBaseDamage(baseDmg, user, target)
			
		else
			baseDmg = stupidity_pbMoveBaseDamage(move,user,target,skill)
		end
		
		return baseDmg
	end
	
	
	# NOTE: The AI will only consider using an item on the Pokémon it's currently
	#       choosing an action for.
	def pbEnemyItemToUse(idxBattler)
		return nil if !@battle.internalBattle
		items = @battle.pbGetOwnerItems(idxBattler)
		return nil if !items || items.length==0
		# Determine target of item (always the Pokémon choosing the action)
		idxTarget = idxBattler   # Battler using the item
		battler = @battle.battlers[idxTarget]
		pkmn = battler.pokemon
		# Item categories
		hpItems = {
			:POTION       => 20,
			:SUPERPOTION  => (Settings::REBALANCED_HEALING_ITEM_AMOUNTS) ? 60 : 50,
			:HYPERPOTION  => (Settings::REBALANCED_HEALING_ITEM_AMOUNTS) ? 120 : 200,
			:MAXPOTION    => 999,
			:BERRYJUICE   => 20,
			:SWEETHEART   => 20,
			:FRESHWATER   => (Settings::REBALANCED_HEALING_ITEM_AMOUNTS) ? 30 : 50,
			:SODAPOP      => (Settings::REBALANCED_HEALING_ITEM_AMOUNTS) ? 50 : 60,
			:LEMONADE     => (Settings::REBALANCED_HEALING_ITEM_AMOUNTS) ? 70 : 80,
			:MOOMOOMILK   => 100,
			:ORANBERRY    => 10,
			:SITRUSBERRY  => battler.totalhp / 4,
			:ENERGYPOWDER => (Settings::REBALANCED_HEALING_ITEM_AMOUNTS) ? 60 : 50,
			:ENERGYROOT   => (Settings::REBALANCED_HEALING_ITEM_AMOUNTS) ? 120 : 200,
			# Ashen Frost exclusive items
			:BURGER       => 45,
			:CHEESEBURGER => 100,
			:HOTCHOCOLATE => 75,
			:APPLECIDER   => 999,
			:COFFEE  	  => battler.totalhp / 4,
			:RAMEN        => 30,
			:SKETCHYRAMEN => 30,
			:SARSAPARILLA => 175,
			:SKETCHYBURGER=> 45,
			:IMPUREWATER  => 50,
			:REDSYRINGE   => 50,
			:GREENSYRINGE => battler.totalhp / 2,
			:SILVERSYRINGE=> 999,
			:BURGER       => 45,
			
		}
		hpItems[:RAGECANDYBAR] = 20 if !Settings::RAGE_CANDY_BAR_CURES_STATUS_PROBLEMS
		fullRestoreItems = [
			:FULLRESTORE, :GOLDSYRINGE
		]
		oneStatusItems = [   # Preferred over items that heal all status problems
			:AWAKENING, :CHESTOBERRY, :BLUEFLUTE,
			:ANTIDOTE, :PECHABERRY,
			:BURNHEAL, :RAWSTBERRY,
			:PARALYZEHEAL, :PARLYZHEAL, :CHERIBERRY,
			:ICEHEAL, :ASPEARBERRY,
			 # Ashen Frost exclusive items
			 :MILKSHAKE
		]
		allStatusItems = [
			:FULLHEAL, :LAVACOOKIE, :OLDGATEAU, :CASTELIACONE, :LUMIOSEGALETTE,
			:SHALOURSABLE, :BIGMALASADA, :PEWTERCRUNCHIES, :LUMBERRY, :HEALPOWDER,
			# Ashen Frost exclusive items
			:FRIES, :SKETCHYFRIES, :COFFEE, :GREENSYRINGE, :BLUESYRINGE
		]
		allStatusItems.push(:RAGECANDYBAR) if Settings::RAGE_CANDY_BAR_CURES_STATUS_PROBLEMS
		xItems = {
			:XATTACK    => [:ATTACK, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
			:XATTACK2   => [:ATTACK, 2],
			:XATTACK3   => [:ATTACK, 3],
			:XATTACK6   => [:ATTACK, 6],
			:XDEFENSE   => [:DEFENSE, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
			:XDEFENSE2  => [:DEFENSE, 2],
			:XDEFENSE3  => [:DEFENSE, 3],
			:XDEFENSE6  => [:DEFENSE, 6],
			:XDEFEND    => [:DEFENSE, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
			:XDEFEND2   => [:DEFENSE, 2],
			:XDEFEND3   => [:DEFENSE, 3],
			:XDEFEND6   => [:DEFENSE, 6],
			:XSPATK     => [:SPECIAL_ATTACK, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
			:XSPATK2    => [:SPECIAL_ATTACK, 2],
			:XSPATK3    => [:SPECIAL_ATTACK, 3],
			:XSPATK6    => [:SPECIAL_ATTACK, 6],
			:XSPECIAL   => [:SPECIAL_ATTACK, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
			:XSPECIAL2  => [:SPECIAL_ATTACK, 2],
			:XSPECIAL3  => [:SPECIAL_ATTACK, 3],
			:XSPECIAL6  => [:SPECIAL_ATTACK, 6],
			:XSPDEF     => [:SPECIAL_DEFENSE, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
			:XSPDEF2    => [:SPECIAL_DEFENSE, 2],
			:XSPDEF3    => [:SPECIAL_DEFENSE, 3],
			:XSPDEF6    => [:SPECIAL_DEFENSE, 6],
			:XSPEED     => [:SPEED, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
			:XSPEED2    => [:SPEED, 2],
			:XSPEED3    => [:SPEED, 3],
			:XSPEED6    => [:SPEED, 6],
			:XACCURACY  => [:ACCURACY, (Settings::X_STAT_ITEMS_RAISE_BY_TWO_STAGES) ? 2 : 1],
			:XACCURACY2 => [:ACCURACY, 2],
			:XACCURACY3 => [:ACCURACY, 3],
			:XACCURACY6 => [:ACCURACY, 6],
			:DIREHIT    => [PBEffects::FocusEnergy, 2],
			# Ashen frost exlclusive hidden tech
			:SKETCHYBURGER => [:ATTACK, 1]
		}
		losthp = battler.totalhp - battler.hp
		preferFullRestore = (battler.hp <= battler.totalhp * 2 / 3 &&
			(battler.status != :NONE || battler.effects[PBEffects::Confusion] > 0))
		
		user=battler
		attacker=battler
		target=battler.pbDirectOpposing(true)
		skill = 100
		
		hasPhysicalAttack = false
		hasSpecialAttack = false
		canthaw = false
		user.eachMove do |m|
			next if !m.physicalMove?(m.type)
			hasPhysicalAttack = true if m.physicalMove?(m.type)
			hasSpecialAttack = true if m.specialMove?(m.type)
			canthaw = true if m.thawsUser?
			break
		end
		aspeed = pbRoughStat(user,:SPEED,skill)
		ospeed = pbRoughStat(target,:SPEED,skill)
		# Find all usable items
		usableHPItems     = []
		usableStatusItems = []
		usableXItems      = []
		items.each do |i|
			next if !i
			next if !@battle.pbCanUseItemOnPokemon?(i,pkmn,battler,@battle.scene,false)
			next if !ItemHandlers.triggerCanUseInBattle(i,pkmn,battler,nil,
				false,self,@battle.scene,false)
			# Log HP healing items
			if losthp > 0
				power = hpItems[i]
				if power
					usableHPItems.push([i, 5, power])
					next
				end
			end
			# Log Full Restores (HP healer and status curer)
			if losthp > 0 || battler.status != :NONE || battler.effects[PBEffects::Confusion] > 0
				if fullRestoreItems.include?(i)
					usableHPItems.push([i, (preferFullRestore) ? 3 : 7, 999])
					usableStatusItems.push([i, (preferFullRestore) ? 3 : 9])
					next
				end
			end
			# Log single status-curing items
			if oneStatusItems.include?(i)
				usableStatusItems.push([i, 5])
				next
			end
			# Log Full Heal-type items
			if allStatusItems.include?(i)
				usableStatusItems.push([i, 7])
				next
			end
			# Log stat-raising items
			if xItems[i]
				data = xItems[i]
				usableXItems.push([i, battler.stages[data[0]], data[1]])
				next
			end
		end
		# Prioritise using a HP restoration item
		hpitemscore = 0
		if usableHPItems.length>0 #&& (battler.hp<=battler.totalhp/4 ||
			hpitemscore = 100
			#(battler.hp<=battler.totalhp/2 && pbAIRandom(100)<30))
			fastermon=((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
			fasterhealing=true
			usableHPItems.sort! { |a,b| (a[1]==b[1]) ? a[2]<=>b[2] : a[1]<=>b[1] }
			prevhpitem = nil
			chosenhpitem=nil
			usableHPItems.each do |i|
				if i[2]>=losthp
					if [:FULLRESTORE,:GOLDSYRINGE, :GREENSYRINGE, :COFFEE].include?(i[0]) &&
						(
							battler.hasActiveAbility?(:GUTS) && hasPhysicalAttack && 
							(
								(battler.status==:BURN && !battler.hasActiveItem?(:FLAMEORB)) || 
								(battler.status==:POISON && !battler.hasActiveItem?(:TOXICORB))
							)
						) ||  
						(
							battler.hasActiveAbility?(:TOXICBOOST) && hasPhysicalAttack && 
							(battler.status==:POISON && !battler.hasActiveItem?(:TOXICORB))
						) ||  
						(
							battler.hasActiveAbility?(:FLAREBOOST) && hasSpecialAttack && 
							(battler.status==:BURN && !battler.hasActiveItem?(:FLAMEORB))
						) ||  
						(
							battler.hasActiveAbility?(:QUICKFEET)&& 
							(
								(battler.status==:BURN && hasSpecialAttack && !battler.hasActiveItem?(:FLAMEORB)) ||
								(battler.status==:POISON && !battler.hasActiveItem?(:TOXICORB)) ||
								battler.status==:PARALYSIS
							)
						) ||  
						(
							battler.hasActiveAbility?(:MARVELSCALE) && hasSpecialAttack && 
							(battler.status==:BURN && !battler.hasActiveItem?(:FLAMEORB))
						) ||  
						(
							battler.hasActiveAbility?(:POISONHEAL) && 44
							(battler.status==:POISON && !battler.hasActiveItem?(:TOXICORB))
						) 
						
						echo("Will not use Full Restore because the status is beneficial.\n")
						break
						
					end	
					chosenhpitem = i
					break
				end
				chosenhpitem = i
			end
			
			if chosenhpitem
				heal = chosenhpitem[2]
				heal=losthp if heal>losthp
				heal-=battler.totalhp*0.1 if battler.hasActiveItem?(:LIFEORB)
				halfhealth=(user.hp+heal)/2
				echo("healing "+halfhealth.to_s+" of "+battler.totalhp.to_s+"\n")
				maxdam=0
				maxmove=nil
				maxidx=0 
				maxattacker=target
				@battle.allSameSideBattlers(target.index).each do |b|
					bestmove=bestMoveVsTarget(b,battler,skill) # [maxdam,maxmove,maxprio,physorspec]
					if bestmove[0] >= maxdam
						maxdam=bestmove[0] 
						maxidx=bestmove[4] 
						maxmove=bestmove[1]
						maxattacker=b
					end
				end
				maxdam=0 if (target.status == :SLEEP && target.statusCount>1)		
				#if maxdam>battler.hp
				echo(maxdam.to_s+" expected dmg vs "+heal.to_s+" healing\n")
				if !targetSurvivesMove(maxmove,maxidx,maxattacker,battler)
					echo("user does not survive player's strongest move at current hp")
					echo("\n")
					if maxdam>(battler.hp+heal)
						echo("expected damage is higher than hp after heal")
						echo("\n")
						hpitemscore=0
					else
						echo("expected damage is lower or equal than hp after heal")
						echo("\n")
						if maxdam>=halfhealth
							echo("expected damage is higher than half of hp after heal")
							echo("\n")
							if fasterhealing
								echo("healing will be executed before the player")
								echo("\n")
								hpitemscore*=0.1
							else
								echo("healing will be executed after the player")
								echo("\n")
								hpitemscore*=0.1
							end
						else
							echo("expected damage is lower than half of hp after heal. score doubles")
							echo("\n")
							hpitemscore*=2
						end
					end
				else
					echo("user survives player's strongest move at current hp")
					echo("\n")
					if maxdam*1.5>battler.hp
						echo("expected damage*1.5 is higher than user's current hp. score doubles")
						echo("\n")
						hpitemscore*=2
					end
					if !fastermon
						echo("user is slower than player's mon")
						echo("\n")
						if maxdam*2>battler.hp
							echo("expected damage*2 is higher than user's current hp. score doubles")
							echo("\n")
							hpitemscore*=2
						end
					end
				end
				hpchange=(EndofTurnHPChanges(battler,target,false,false,true)) # what % of our hp will change after end of turn effects go through
				opphpchange=(EndofTurnHPChanges(target,battler,false,false,true)) # what % of our hp will change after end of turn effects go through
				if opphpchange<1 ## we are going to be taking more chip damage than we are going to heal
					oppchipdamage=((target.totalhp*(1-hpchange)))
				end
				thisdam=maxdam#*1.1
				hplost=(battler.totalhp-battler.hp)
				hplost+=maxdam if !fasterhealing
				if battler.effects[PBEffects::LeechSeed]>=0 && !fastermon && canSleepTarget(target,battler)
					echo("user is slower and seeded. score x0.1")
					echo("\n")
					hpitemscore *= 0.1 
				end	
				if hpchange<1 ## we are going to be taking more chip damage than we are going to heal
					echo("we are going to be taking more chip damage than we are going to heal")
					echo("\n")
					chipdamage=((battler.totalhp*(1-hpchange)))
					thisdam+=chipdamage
				elsif hpchange>1 ## we are going to be healing more hp than we take chip damage for  
					echo("we are going to be healing more hp than we take chip damage for  ")
					echo("\n")
					healing=((battler.totalhp*(hpchange-1)))
					thisdam-=healing if !(thisdam>battler.hp)
				elsif hpchange<=0 ## we are going to a huge overstack of end of turn effects. hence we should just not heal.
					echo("we are going to a huge overstack of end of turn effects. hence we should just not heal. ")
					echo("\n")
					hpitemscore*=0
				end
				if thisdam>hplost
					echo("expected damage is bigger than missing hp. score x0.1 ")
					echo("\n")
					hpitemscore*=0.1
				else
					echo("expected damage is less than missing hp ")
					echo("\n")
					if @battle.pbAbleNonActiveCount(battler.idxOwnSide) == 0 && hplost<=(halfhealth)
						echo("this is the last pokemon and the missing hp is less than the future hp after healing. score x0.01 ")
						echo("\n")
						hpitemscore*=0.01
					end
					if thisdam<=(heal)
						echo("expected damage is smaller than the healing score doubles.")
						echo("\n")
						hpitemscore*=2
					else
						if fastermon
							echo("user is faster than the player's mon")
							echo("\n")
							if hpchange<1 && thisdam>=heal && !(opphpchange<1)
								echo("we are taking chip damage, expected damage is bigger than the healing, opponent does not take chip damage. score x0.3")
								echo("\n")
								hpitemscore*=0.3
							end
						end
					end
				end 
				if target.pbHasMoveFunction?("RaiseUserAtkDef1","RaiseUserAtkDefAcc1","RaiseUserAtkSpd1","RaiseUserAtk1Spd2",
						"RaiseUserSpAtkSpDefSpd1","RaiseUserSpAtkSpDef1","RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserAttack1",
						"RaiseUserAttack2","RaiseUserAtkAcc1","RaiseUserSpAtk2","RaiseUserSpAtk3","LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2") # Setup
					hpitemscore*=0.3
					echo("player has setup, score x0.3")
					echo("\n")
				end
				if ((battler.hp.to_f)<=halfhealth)
					echo("user's hp ("+battler.hp.to_s+") is less than half of hp after healing ("+halfhealth.to_s+"). score x1.5")
					echo("\n")
					hpitemscore*=1.5
				else
					echo("user's hp ("+battler.hp.to_s+") is more than half of hp after healing ("+halfhealth.to_s+"). score x0.3")
					echo("\n")
					hpitemscore*=0.2
				end
				hpitemscore/=(battler.effects[PBEffects::Toxic]) if battler.effects[PBEffects::Toxic]>0
				if maxdam>halfhealth
					echo("expected damage is higher than half of hp after healing")
					echo("\n")
					hpitemscore*=0.2 
				end
				if target.hasActiveItem?(:METRONOME)
					echo("player has metronome.. score decreases accordingly")
					echo("\n")
					met=(1.0+target.effects[PBEffects::Metronome]*0.2) 
					hpitemscore/=met
				end 
				if battler.status==:PARALYSIS || battler.effects[PBEffects::Confusion]>0
					echo("paralysis/confusion. score increases slightly")
					echo("\n")
					hpitemscore*=1.1 
				end
				if target.status==:POISON || target.status==:BURN || target.effects[PBEffects::LeechSeed]>=0 || target.effects[PBEffects::Curse] || target.effects[PBEffects::Trapping]>0
					echo("player mon suffers from damage over time. score x1.3")
					echo("\n")
					hpitemscore*=1.3
					hpitemscore*=1.3 if target.effects[PBEffects::Toxic]>0
					hpitemscore*=1.3 if battler.item == :BINDINGBAND
				end
				if ((battler.hp.to_f)/battler.totalhp)>0.8
					echo("user's hp is higher than  80perc. score x0.1")
					echo("\n")
					hpitemscore*=0.1 
				end
				if ((battler.hp.to_f)/battler.totalhp)>0.6
					echo("user's hp is higher than  60perc. score x0.6")
					echo("\n")
					hpitemscore*=0.6 
				end
				if ((battler.hp.to_f)/battler.totalhp)<0.25
					echo("user's hp is lower than  25perc. score doubles")
					echo("\n")
					hpitemscore*=2 
				end
			end
			
			
			#   usableHPItems.sort! { |a,b| (a[1]==b[1]) ? a[2]<=>b[2] : a[1]<=>b[1] }
			#   prevhpitem = nil
			#   usableHPItems.each do |i|
			#     return i[0], idxTarget if i[2]>=losthp
			#     prevhpitem = i
			#   end
			#   return prevhpitem[0], idxTarget 
		end
		
		statusitemscore=0
		maxscore=0
		chosenstatusitem = nil
		# Next prioritise using a status-curing item
		if usableStatusItems.length>0 #&& pbAIRandom(100)<40
			usableStatusItems.sort! { |a,b| a[1]<=>b[1] }
			usableStatusItems.each do |i|
				if i[1]==7
					if	(
							battler.hasActiveAbility?(:GUTS) && hasPhysicalAttack && 
							(
								battler.status==:BURN || battler.status==:POISON || 
								(battler.status==:SLEEP && battler.pbHasMoveFunction?("UseRandomUserMoveIfAsleep")) # Sleep Talk
							)
						) ||  
						(
							battler.hasActiveAbility?(:TOXICBOOST) && hasPhysicalAttack && battler.status==:POISON
						) ||  
						(
							battler.hasActiveAbility?(:FLAREBOOST) && hasSpecialAttack && battler.status==:BURN
						) ||  
						(
							battler.hasActiveAbility?(:QUICKFEET)&& 
							(
								(battler.status==:BURN && hasSpecialAttack) ||
								battler.status==:POISON ||
								battler.status==:PARALYSIS
							)
						) ||  
						(
							battler.hasActiveAbility?(:MARVELSCALE) && hasSpecialAttack && battler.status==:BURN
						) ||  
						(
							battler.hasActiveAbility?(:POISONHEAL) && battler.status==:POISON
						) ||
						(
							battler.status==:SLEEP && (battler.statusCount==1 || target.pbHasMoveFunction?("SleepTarget", "SleepTargetIfUserDarkrai"))
						) ||
						(
							battler.status==:FROZEN && canthaw
						) ||
						(
							battler.status==:PARALYSIS && 
							(
								((aspeed*4 < ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) ||
								target.pbHasMove?(:THUNDERWAVE) || target.pbHasMove?(:GLARE) || target.pbHasMove?(:STUNSPORE)
							)
						) ||
						(
							battler.status==:BURN && target.pbHasMove?(:WILLOWISP) || target.pbHasMove?(:SACREDFIRE) || target.pbHasMove?(:INFERNO) || !hasPhysicalAttack
						) ||
						(
							battler.status==:POISON && battler.effects[PBEffects::Toxic]<4
						)
						
						echo("Will not use Full Heal because it's either pointless or beneficial in this scenario.\n")
						
					else
						
						if battler.statusCount>2 && battler.status==:SLEEP && !target.pbHasMoveFunction?("SleepTarget", "SleepTargetIfUserDarkrai")
							statusitemscore=100
							bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxprio=bestmove[2]
							priodam=0
							priomove=nil
							user.moves.each_with_index do |j,i|
								next if priorityAI(user,j)<1
								if moveLocked(user)
									if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
										next if j.id!=user.lastMoveUsed
									end
								end		
								tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
								if tempdam>priodam
									priodam=tempdam 
									priomove=j
									prioidx=i
								end	
							end 
							halfhealth=(user.totalhp/2)
							thirdhealth=(user.totalhp/3)
							if targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 50
								statusitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
								if skill>=PBTrainerAI.highSkill
									aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
									ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
									if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
										if priomove
											if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
												statusitemscore+=90
											else	
												statusitemscore -= 90 
											end
										else
											statusitemscore -= 90 
										end
									else
										statusitemscore+=80
									end
								end
								statusitemscore += 20 if halfhealth>maxdam
								statusitemscore += 40 if thirdhealth>maxdam
							end 
						elsif battler.status==:FROZEN
							statusitemscore=100
							bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxprio=bestmove[2]
							priodam=0
							priomove=nil
							user.moves.each_with_index do |j,i|
								next if priorityAI(user,j)<1
								if moveLocked(user)
									if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
										next if j.id!=user.lastMoveUsed
									end
								end
									tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
								if tempdam>priodam
									priodam=tempdam 
									priomove=j
									prioidx=i
								end	
							end 
							halfhealth=(user.totalhp/2)
							thirdhealth=(user.totalhp/3)
							aspeed = pbRoughStat(user,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							if targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 50
								statusitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
								if skill>=PBTrainerAI.highSkill
									aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
									ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
									if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
										if priomove
											if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
												statusitemscore+=90
											else	
												statusitemscore -= 90 
											end
										else
											statusitemscore -= 90 
										end
									else
										statusitemscore+=80
									end
								end
								statusitemscore += 20 if halfhealth>maxdam
								statusitemscore += 40 if thirdhealth>maxdam
							end 
						elsif battler.status==:BURN && !target.pbHasMove?(:WILLOWISP)
							statusitemscore=100
							bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxprio=bestmove[2]
							priodam=0
							priomove=nil
							user.moves.each_with_index do |j,i|
								next if priorityAI(user,j)<1
								if moveLocked(user)
									if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
										next if j.id!=user.lastMoveUsed
									end
								end		
								tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
								if tempdam>priodam
									priodam=tempdam 
									priomove=j
									prioidx=i
								end	
							end 
							halfhealth=(user.totalhp/2)
							thirdhealth=(user.totalhp/3)
							aspeed = pbRoughStat(user,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							if targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 50
								statusitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
								if skill>=PBTrainerAI.highSkill
									aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
									ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
									if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
										if priomove
											if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
												statusitemscore+=90
											else	
												statusitemscore -= 90 
											end
										else
											statusitemscore -= 90 
										end
									else
										statusitemscore+=80
									end
								end
								statusitemscore += 20 if halfhealth>maxdam
								statusitemscore += 40 if thirdhealth>maxdam
							end 
						elsif battler.status==:PARALYSIS && !target.pbHasMove?(:THUNDERWAVE) && !target.pbHasMove?(:GLARE) && !target.pbHasMove?(:STUNSPORE)
							statusitemscore=100
							bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxprio=bestmove[2]
							halfhealth=(user.totalhp/2)
							thirdhealth=(user.totalhp/3)
							aspeed = pbRoughStat(user,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio) || (target.status == :SLEEP && target.statusCount>1)
								#statusitemscore += 40
								if skill>=PBTrainerAI.highSkill
									aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
									ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
									if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*4>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
										statusitemscore += 100 
										if attacker.pbHasMoveFunction?("FlinchTarget", "HitTwoTimesFlinchTarget") && attacker.hasActiveAbility?(:SERENEGRACE) && 
											((!target.hasActiveAbility?(:INNERFOCUS) && !target.hasActiveAbility?(:SHIELDDUST)) || mold_broken) &&
											target.effects[PBEffects::Substitute]==0
											statusitemscore +=140 
										end
									end
								end
								statusitemscore += 40 if thirdhealth>maxdam
							end
						elsif battler.status==:POISON && user.effects[PBEffects::Toxic]>3
							statusitemscore = 100
							aspeed = pbRoughStat(battler,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							fastermon=true 
							halfhealth=0
							bestmove=bestMoveVsTarget(target,battler,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxdam=0 if (target.status == :SLEEP && target.statusCount>1)		
							if !targetSurvivesMove(maxmove,maxidx,target,battler)
								if maxdam>(battler.hp+halfhealth)
									statusitemscore=0
								else
									if maxdam>=halfhealth
										if fastermon
											statusitemscore*=0.5
										else
											statusitemscore*=0.1
										end
									else
										statusitemscore*=2
									end
								end
							else
								if maxdam*1.5>battler.hp
									statusitemscore*=2
								end
								if !fastermon
									if maxdam*2>battler.hp
										statusitemscore*=2
									end
								end
							end
							hpchange=(EndofTurnHPChanges(battler,target,false,false,true)) # what % of our hp will change after end of turn effects go through
							opphpchange=(EndofTurnHPChanges(target,battler,false,false,true)) # what % of our hp will change after end of turn effects go through
							if opphpchange<1 ## we are going to be taking more chip damage than we are going to heal
								oppchipdamage=((target.totalhp*(1-hpchange)))
							end
							thisdam=maxdam#*1.1
							hplost=(battler.totalhp-battler.hp)
							hplost+=maxdam if !fastermon
							if battler.effects[PBEffects::LeechSeed]>=0 && !fastermon && canSleepTarget(target,battler)
								statusitemscore *= 0.3 
							end	
							if hpchange<1 ## we are going to be taking more chip damage than we are going to heal
								chipdamage=((battler.totalhp*(1-hpchange)))
								thisdam+=chipdamage
							elsif hpchange>1 ## we are going to be healing more hp than we take chip damage for  
								healing=((battler.totalhp*(hpchange-1)))
								thisdam-=healing if !(thisdam>battler.hp)
							elsif hpchange<=0 ## we are going to a huge overstack of end of turn effects. hence we should just not heal.
								statusitemscore*=0
							end
							if thisdam>hplost
								statusitemscore*=0.1
							else
								if @battle.pbAbleNonActiveCount(battler.idxOwnSide) == 0 && hplost<=(halfhealth)
									statusitemscore*=0.01
								end
								if thisdam<=(halfhealth)
									statusitemscore*=2
								else
									if fastermon
										if hpchange<1 && thisdam>=halfhealth && !(opphpchange<1)
											statusitemscore*=0.3
										end
									end
								end
							end
							statusitemscore*=0.7 if target.pbHasMoveFunction?("RaiseUserAtkDef1","RaiseUserAtkDefAcc1","RaiseUserAtkSpd1","RaiseUserAtk1Spd2",
								"RaiseUserSpAtkSpDefSpd1","RaiseUserSpAtkSpDef1","RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserAttack1",
								"RaiseUserAttack2","RaiseUserAtkAcc1","RaiseUserSpAtk2","RaiseUserSpAtk3","LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2") # Setup
							if ((battler.hp.to_f)<=halfhealth)
								statusitemscore*=1.5
							else
								statusitemscore*=0.8
							end
							statusitemscore/=(battler.effects[PBEffects::Toxic]) if battler.effects[PBEffects::Toxic]>0
							statusitemscore*=0.8 if maxdam>halfhealth
							if target.hasActiveItem?(:METRONOME)
								met=(1.0+target.effects[PBEffects::Metronome]*0.2) 
								statusitemscore/=met
							end 
							statusitemscore*=1.1 if battler.status==:PARALYSIS || battler.effects[PBEffects::Confusion]>0
							if target.status==:POISON || target.status==:BURN || target.effects[PBEffects::LeechSeed]>=0 || target.effects[PBEffects::Curse] || target.effects[PBEffects::Trapping]>0
								statusitemscore*=1.3
								statusitemscore*=1.3 if target.effects[PBEffects::Toxic]>0
								statusitemscore*=1.3 if battler.item == :BINDINGBAND
							end
							statusitemscore*=0.1 if ((battler.hp.to_f)/battler.totalhp)>0.8
							statusitemscore*=0.6 if ((battler.hp.to_f)/battler.totalhp)>0.6
							statusitemscore*=2 if ((battler.hp.to_f)/battler.totalhp)<0.25
						else
							statusitemscore=0
						end
					end	
				else
					case i[0]
					when :AWAKENING, :CHESTOBERRY, :BLUEFLUTE
						if battler.statusCount>2 && battler.status==:SLEEP && !target.pbHasMoveFunction?("SleepTarget", "SleepTargetIfUserDarkrai") &&
							!battler.pbHasMoveFunction?("UseRandomUserMoveIfAsleep") # Sleep Talk
							statusitemscore=100
							bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxprio=bestmove[2]
							priodam=0
							priomove=nil
							user.moves.each_with_index do |j,i|
								next if priorityAI(user,j)<1
								if moveLocked(user)
									if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
										next if j.id!=user.lastMoveUsed
									end
								end		
								tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
								if tempdam>priodam
									priodam=tempdam 
									priomove=j
									prioidx=i
								end	
							end 
							halfhealth=(user.totalhp/2)
							thirdhealth=(user.totalhp/3)
							aspeed = pbRoughStat(user,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							if targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 50
								statusitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
								if skill>=PBTrainerAI.highSkill
									aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
									ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
									if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
										if priomove
											if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
												statusitemscore+=90
											else	
												statusitemscore -= 90 
											end
										else
											statusitemscore -= 90 
										end
									else
										statusitemscore+=80
									end
								end
								statusitemscore += 20 if halfhealth>maxdam
								statusitemscore += 40 if thirdhealth>maxdam
							end 
						else
							statusitemscore=0
						end
					when :ICEHEAL, :ASPEARBERRY
						if battler.status==:FROZEN && canthaw
							statusitemscore=100
							bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxprio=bestmove[2]
							priodam=0
							priomove=nil
							user.moves.each_with_index do |j,i|
								next if priorityAI(user,j)<1
								if moveLocked(user)
									if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
										next if j.id!=user.lastMoveUsed
									end
								end		
								tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
								if tempdam>priodam
									priodam=tempdam 
									priomove=j
								end	
							end 
							halfhealth=(user.totalhp/2)
							thirdhealth=(user.totalhp/3)
							aspeed = pbRoughStat(user,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							if targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 50
								statusitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
								if skill>=PBTrainerAI.highSkill
									aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
									ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
									if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
										if priomove
											if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
												statusitemscore+=90
											else	
												statusitemscore -= 90 
											end
										else
											statusitemscore -= 90 
										end
									else
										statusitemscore+=80
									end
								end
								statusitemscore += 20 if halfhealth>maxdam
								statusitemscore += 40 if thirdhealth>maxdam
							end 
						else
							statusitemscore=0
						end
					when :BURNHEAL, :RAWSTBERRY , :MILKSHAKE
						if battler.status==:BURN && !target.pbHasMove?(:WILLOWISP) &&
							(!battler.hasActiveAbility?(:GUTS) && hasPhysicalAttack) && !battler.hasActiveAbility?(:QUICKFEET) 
							statusitemscore=100
							bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxprio=bestmove[2]
							priodam=0
							priomove=nil
							user.moves.each_with_index do |j,i|
								next if priorityAI(user,j)<1
								if moveLocked(user)
									if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
										next if j.id!=user.lastMoveUsed
									end
								end		
								tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
								if tempdam>priodam
									priodam=tempdam 
									priomove=j
									prioidx=i
								end	
							end 
							halfhealth=(user.totalhp/2)
							thirdhealth=(user.totalhp/3)
							aspeed = pbRoughStat(user,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							if targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 50
								statusitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
								statusitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
								if skill>=PBTrainerAI.highSkill
									aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
									ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
									if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
										if priomove
											if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
												statusitemscore+=90
											else	
												statusitemscore -= 90 
											end
										else
											statusitemscore -= 90 
										end
									else
										statusitemscore+=80
									end
								end
								statusitemscore += 20 if halfhealth>maxdam
								statusitemscore += 40 if thirdhealth>maxdam
							end 
						else
							statusitemscore=0
						end
					when :PARALYZEHEAL,:PARLYZHEAL, :CHERIBERRY
						if battler.status==:PARALYSIS && !target.pbHasMove?(:THUNDERWAVE) && !target.pbHasMove?(:GLARE) && !target.pbHasMove?(:STUNSPORE) &&
							!battler.hasActiveAbility?(:QUICKFEET) && ((aspeed*4 > ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
							statusitemscore=100
							bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxidx=bestmove[4] 
							maxmove=bestmove[1]
							maxprio=bestmove[2]
							halfhealth=(user.totalhp/2)
							thirdhealth=(user.totalhp/3)
							aspeed = pbRoughStat(user,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio) || (target.status == :SLEEP && target.statusCount>1)
								#statusitemscore += 40
								if skill>=PBTrainerAI.highSkill
									aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
									ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
									if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*4>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
										statusitemscore += 100 
										if attacker.pbHasMoveFunction?("FlinchTarget", "HitTwoTimesFlinchTarget") && attacker.hasActiveAbility?(:SERENEGRACE) && 
											((!target.hasActiveAbility?(:INNERFOCUS) && !target.hasActiveAbility?(:SHIELDDUST)) || mold_broken) &&
											target.effects[PBEffects::Substitute]==0
											statusitemscore +=140 
										end
									end
								end
								statusitemscore += 40 if thirdhealth>maxdam
							end
						else
							statusitemscore=0
						end
					when :ANTIDOTE, :PECHABERRY
						if battler.status==:POISON && user.effects[PBEffects::Toxic]>3 && 
							!((battler.hasActiveAbility?(:GUTS) || battler.hasActiveAbility?(:TOXICBOOST)) && hasPhysicalAttack) &&
							!battler.hasActiveAbility?(:QUICKFEET) && !battler.hasActiveAbility?(:POISONHEAL) && !battler.hasActiveItem?(:LIFEORB)
							statusitemscore = 100
							aspeed = pbRoughStat(battler,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							fastermon=true 
							halfhealth=0
							bestmove=bestMoveVsTarget(target,battler,skill) # [maxdam,maxmove,maxprio,physorspec]
							maxdam=bestmove[0] 
							maxmove=bestmove[1]
							maxdam=0 if (target.status == :SLEEP && target.statusCount>1)		
							if !targetSurvivesMove(maxmove,maxidx,target,battler)
								if maxdam>(battler.hp+halfhealth)
									statusitemscore=0
								else
									if maxdam>=halfhealth
										if fastermon
											statusitemscore*=0.5
										else
											statusitemscore*=0.1
										end
									else
										statusitemscore*=2
									end
								end
							else
								if maxdam*1.5>battler.hp
									statusitemscore*=2
								end
								if !fastermon
									if maxdam*2>battler.hp
										statusitemscore*=2
									end
								end
							end
							hpchange=(EndofTurnHPChanges(battler,target,false,false,true)) # what % of our hp will change after end of turn effects go through
							opphpchange=(EndofTurnHPChanges(target,battler,false,false,true)) # what % of our hp will change after end of turn effects go through
							if opphpchange<1 ## we are going to be taking more chip damage than we are going to heal
								oppchipdamage=((target.totalhp*(1-hpchange)))
							end
							thisdam=maxdam#*1.1
							hplost=(battler.totalhp-battler.hp)
							hplost+=maxdam if !fastermon
							if battler.effects[PBEffects::LeechSeed]>=0 && !fastermon && canSleepTarget(target,battler)
								statusitemscore *= 0.3 
							end	
							if hpchange<1 ## we are going to be taking more chip damage than we are going to heal
								chipdamage=((battler.totalhp*(1-hpchange)))
								thisdam+=chipdamage
							elsif hpchange>1 ## we are going to be healing more hp than we take chip damage for  
								healing=((battler.totalhp*(hpchange-1)))
								thisdam-=healing if !(thisdam>battler.hp)
							elsif hpchange<=0 ## we are going to a huge overstack of end of turn effects. hence we should just not heal.
								statusitemscore*=0
							end
							if thisdam>hplost
								statusitemscore*=0.1
							else
								if @battle.pbAbleNonActiveCount(battler.idxOwnSide) == 0 && hplost<=(halfhealth)
									statusitemscore*=0.01
								end
								if thisdam<=(halfhealth)
									statusitemscore*=2
								else
									if fastermon
										if hpchange<1 && thisdam>=halfhealth && !(opphpchange<1)
											statusitemscore*=0.3
										end
									end
								end
							end
							statusitemscore*=0.7 if target.pbHasMoveFunction?("RaiseUserAtkDef1","RaiseUserAtkDefAcc1","RaiseUserAtkSpd1","RaiseUserAtk1Spd2",
								"RaiseUserSpAtkSpDefSpd1","RaiseUserSpAtkSpDef1","RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserAttack1",
								"RaiseUserAttack2","RaiseUserAtkAcc1","RaiseUserSpAtk2","RaiseUserSpAtk3","LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2") # Setup
							if ((battler.hp.to_f)<=halfhealth)
								statusitemscore*=1.5
							else
								statusitemscore*=0.8
							end
							statusitemscore/=(battler.effects[PBEffects::Toxic]) if battler.effects[PBEffects::Toxic]>0
							statusitemscore*=0.8 if maxdam>halfhealth
							if target.hasActiveItem?(:METRONOME)
								met=(1.0+target.effects[PBEffects::Metronome]*0.2) 
								statusitemscore/=met
							end 
							statusitemscore*=1.1 if battler.status==:PARALYSIS || battler.effects[PBEffects::Confusion]>0
							if target.status==:POISON || target.status==:BURN || target.effects[PBEffects::LeechSeed]>=0 || target.effects[PBEffects::Curse] || target.effects[PBEffects::Trapping]>0
								statusitemscore*=1.3
								statusitemscore*=1.3 if target.effects[PBEffects::Toxic]>0
								statusitemscore*=1.3 if battler.item == :BINDINGBAND
							end
							statusitemscore*=0.1 if ((battler.hp.to_f)/battler.totalhp)>0.8
							statusitemscore*=0.6 if ((battler.hp.to_f)/battler.totalhp)>0.6
							statusitemscore*=2 if ((battler.hp.to_f)/battler.totalhp)<0.25
						else
							statusitemscore=0
						end   
					end
				end
				if statusitemscore>maxscore
					chosenstatusitem=i
					maxscore=statusitemscore
				end
				
				#return usableStatusItems[0][0], idxTarget
			end
			
		end	
		xitemscore=0
		maxscore=0
		chosenxitem = nil
		# Next try using an X item
		if usableXItems.length>0
			usableXItems.sort! { |a,b| (a[1]==b[1]) ? a[2]<=>b[2] : a[1]<=>b[1] }
			usableXItems.each do |i|
				xitemscore=90
				if user.hasActiveAbility?(:CONTRARY)
					if i[0] == :SKETCHYBURGER
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4] 
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						priodam=0
						priomove=nil
						user.moves.each_with_index do |j,i|
							next if priorityAI(user,j)<1
							if moveLocked(user)
								if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
									next if j.id!=user.lastMoveUsed
								end
							end		
							tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
							if tempdam>priodam
								priodam=tempdam 
								priomove=j
								prioidx=i
							end	
						end 
						halfhealth=(user.totalhp/2)
						thirdhealth=(user.totalhp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							xitemscore-=90
						end	
						if targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)
							xitemscore += 40
							xitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
							xitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
								if canSleepTarget(user,target,true) && 
									((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
									xitemscore-=90
								end	
								if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
									if priomove
										if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
											xitemscore+=80
										else	
											xitemscore -= 90 
										end
									else
										xitemscore -= 90 
									end
								else
									xitemscore+=80
								end
							end
							xitemscore += 20 if halfhealth>maxdam
							xitemscore += 40 if thirdhealth>maxdam
						end 
						xitemscore-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
						xitemscore-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
						xitemscore -= user.stages[:ATTACK]*20
						if skill>=PBTrainerAI.mediumSkill
							hasPhysicalAttack = false
							user.eachMove do |m|
								next if !m.physicalMove?(m.type)
								hasPhysicalAttack = true
								break
							end
							if hasPhysicalAttack
								xitemscore += 20
							else
								xitemscore -= 200
							end
						end
					else
						xitemscore=0
					end
				else
					case i[0]
					when :XATTACK, :XATTACK2, :XATTACK3, :XATTACK6
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4] 
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						priodam=0
						priomove=nil
						user.moves.each_with_index do |j,i|
							next if priorityAI(user,j)<1
							if moveLocked(user)
								if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
									next if j.id!=user.lastMoveUsed
								end
							end		
							tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
							if tempdam>priodam
								priodam=tempdam 
								priomove=j
								prioidx=i
							end	
						end 
						halfhealth=(user.totalhp/2)
						thirdhealth=(user.totalhp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							xitemscore-=90
						end	
						if targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)
							xitemscore += 40
							xitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
							xitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
								if canSleepTarget(user,target,true) && 
									((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
									xitemscore-=90
								end	
								if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
									if priomove
										if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
											xitemscore+=80
										else	
											xitemscore -= 90 
										end
									else
										xitemscore -= 90 
									end
								else
									xitemscore+=80
								end
							end
							xitemscore += 20 if halfhealth>maxdam
							xitemscore += 40 if thirdhealth>maxdam
						end 
						xitemscore-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
						xitemscore-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
						xitemscore -= user.stages[:ATTACK]*20
						if skill>=PBTrainerAI.mediumSkill
							hasPhysicalAttack = false
							user.eachMove do |m|
								next if !m.physicalMove?(m.type)
								hasPhysicalAttack = true
								break
							end
							if hasPhysicalAttack
								xitemscore += 20
							else
								xitemscore -= 200
							end
						end
					when :XDEFENSE, :XDEFENSE2, :XDEFENSE3, :XDEFENSE6, :XDEFEND2, :XDEFEND3, :XDEFEND6
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4] 
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						maxphys=(bestmove[3]=="physical") 
						halfhealth=(user.totalhp/2)
						thirdhealth=(user.totalhp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							xitemscore-=90
						end	
						mult=1.0
						mult=mult/2 if maxphys
						if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,mult) || (target.status == :SLEEP && target.statusCount>1)
							if maxphys
								xitemscore += 30
								xitemscore += 20 if halfhealth>maxdam
							end
							xitemscore += 40 if thirdhealth>maxdam
							if target.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn", "HealUserDependingOnWeather", "HealUserDependingOnSandstorm")   #  Recovery
								xitemscore += 40
							end
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							end
						end 
						xitemscore-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
						xitemscore-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
						if user.statStageAtMax?(:DEFENSE)
							xitemscore -= 90
						else
							xitemscore -= user.stages[:DEFENSE] * 20
						end
					when :XSPATK, :XSPATK2, :XSPATK3, :XSPATK6, :XSPECIAL, :XSPECIAL2, :XSPECIAL3, :XSPECIAL6
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4] 
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						halfhealth=(user.totalhp/2)
						thirdhealth=(user.totalhp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							xitemscore-=90
						end	
						if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio) || (target.status == :SLEEP && target.statusCount>1)
							xitemscore += 40
							xitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
							xitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
								xitemscore -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
							end
							xitemscore += 20 if halfhealth>maxdam
							xitemscore += 40 if thirdhealth>maxdam
						end 
						xitemscore-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
						xitemscore-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
						xitemscore -= user.stages[:SPECIAL_ATTACK]*20
						if skill>=PBTrainerAI.mediumSkill
							hasSpecialAttack = false
							user.eachMove do |m|
								next if !m.specialMove?(m.type)
								hasSpecialAttack = true
								break
							end
							if hasSpecialAttack
								xitemscore += 20
							else
								xitemscore -= 200
							end
						end
					when :XSPDEF, :XSPDEF2, :XSPDEF3, :XSPDEF6
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4] 
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						maxspec=(bestmove[3]=="special") 
						halfhealth=(user.totalhp/2)
						thirdhealth=(user.totalhp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							xitemscore-=90
						end	
						mult=1.0
						mult=mult/2 if maxspec
						if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,mult) || (target.status == :SLEEP && target.statusCount>1)
							if maxspec
								xitemscore += 30
								xitemscore += 20 if halfhealth>maxdam
							end
							xitemscore += 60 if thirdhealth>maxdam
							if target.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn", "HealUserDependingOnWeather", "HealUserDependingOnSandstorm")   #  Recovery
								xitemscore += 40
							end
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							end
						end 
						xitemscore-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
						xitemscore-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
						if user.statStageAtMax?(:SPECIAL_DEFENSE)
							xitemscore -= 90
						else
							xitemscore -= user.stages[:SPECIAL_DEFENSE] * 20
						end
					when :XSPEED, :XSPEED2, :XSPEED3, :XSPEED6
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4] 
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						halfhealth=(user.totalhp/2)
						thirdhealth=(user.totalhp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							xitemscore-=90
						end	
						if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio) || (target.status == :SLEEP && target.statusCount>1)
							#xitemscore += 40
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
								if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
									xitemscore += 100 
									if attacker.pbHasMoveFunction?("FlinchTarget", "HitTwoTimesFlinchTarget") && attacker.hasActiveAbility?(:SERENEGRACE) && 
										((!target.hasActiveAbility?(:INNERFOCUS) && !target.hasActiveAbility?(:SHIELDDUST)) || mold_broken) &&
										target.effects[PBEffects::Substitute]==0
										xitemscore +=140 
									end
								end
							end
							xitemscore += 40 if thirdhealth>maxdam
						end
						xitemscore-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
						xitemscore-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
						if user.statStageAtMax?(:SPEED)
							xitemscore -= 90
						else
							xitemscore -= user.stages[:SPEED] * 10
						end
					when :DIREHIT
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4] 
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						priodam=0
						priomove=nil
						user.moves.each_with_index do |j,i|
							next if priorityAI(user,j)<1
							if moveLocked(user)
								if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
									next if j.id!=user.lastMoveUsed
								end
							end		
							tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
							if tempdam>priodam
								priodam=tempdam 
								priomove=j
							end	
						end 
						halfhealth=(user.totalhp/2)
						thirdhealth=(user.totalhp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							xitemscore-=90
						end	
						hascrit = 0
						if user.hasActiveAbility?(:SUPERLUCK) || user.hasActiveAbility?(:SNIPER) || user.hasActiveItem?(:SCOPELENS)
							hascrit=2
						end
						user.eachMove do |m|
							next if !m.highCriticalRate?
							hascrit +=1
							break if hascrit>=2
						end
						if hascrit==2
							xitemscore += 20
						else
							xitemscore -= 200
						end
						if (targetSurvivesMove(maxmove,maxidx,target,user,maxprio) || (target.status == :SLEEP && target.statusCount>1)) && hascrit==2
							xitemscore += 40
							xitemscore+= 60 if (target.status == :SLEEP && target.statusCount>1)
							xitemscore += 60 if user.hasActiveAbility?(:SPEEDBOOST)
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
								if canSleepTarget(user,target,true) && 
									((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
									xitemscore-=90
								end	
								if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
									if priomove
										if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
											xitemscore+=80
										else	
											xitemscore -= 90 
										end
									else
										xitemscore -= 90 
									end
								else
									xitemscore+=80
								end
							end
							xitemscore += 20 if halfhealth>maxdam
							xitemscore += 40 if thirdhealth>maxdam
						end 
						
					end

				end
				
				if xitemscore>maxscore
					chosenxitem=i
					maxscore=xitemscore
				end
				
				# break if prevItem && i[1]>prevItem[1]
				# return i[0], idxTarget if i[1]+i[2]>=6
				# prevItem = i
			end
			#return prevItem[0], idxTarget
		end
		echo("\nItem scores:\n")
		if chosenhpitem
			echo(chosenhpitem[0].name+": "+hpitemscore.to_s+"\n")
		end	
		if chosenstatusitem
			echo(chosenstatusitem[0].name+": "+statusitemscore.to_s+"\n")
		end
		if chosenxitem
			echo(chosenxitem[0].name+": "+xitemscore.to_s+"\n")
		end
		echo("\n")
		bestitem= [hpitemscore, statusitemscore, xitemscore].max #nil
		case bestitem
		when hpitemscore
			if chosenhpitem
				return [chosenhpitem[0], hpitemscore], idxTarget
			else
				return [nil, hpitemscore], idxTarget
			end
		when statusitemscore
			if chosenstatusitem
				return [chosenstatusitem[0], statusitemscore], idxTarget
			else
				return [nil, statusitemscore], idxTarget
			end
		when xitemscore
			if chosenxitem
				return [chosenxitem[0], xitemscore], idxTarget
			else
				return [nil, xitemscore], idxTarget
			end
		end
		
	end


	def registerDamagesAI(faker=nil)
		for i in 0..@battle.battlers.length - 1
			user = @battle.battlers[i]
			if faker
				user = faker if i == faker.index
			end
			totaldamages = {}
			next if user == nil
			user.moves.each_with_index do |move,i|
				totaldamages[i] = {
					:move => move,
					:dmg =>  {}
				}
				target_data = move.pbTarget(user)
				damages = {}
				#@battle.battlers.each do |b|
				for j in 0..@battle.battlers.length - 1
					b = @battle.battlers[j]
					if faker
						b = faker if j == faker.index
					end
					if b == nil
						damages[j] = 0
						next
					end
					damages[b.index] = 0
					next if !@battle.pbMoveCanTarget?(user.index, b.index, target_data)
					damage = pbRoughDamage(move,user,b,100)
					damage = 0 if pbCheckMoveImmunity(1,move,user,b,100)
					damages[b.index] = damage
				end
				totaldamages[i][:dmg]=damages
			end
			@damagesAI[i] = totaldamages
		end
	end
	
    def targetSurvivesMove(move,idxmove,attacker,opponent,priodamage=0,mult=1,priomult=1,priotype=:NONE)
		return true if !move
		mold_broken=moldbroken(attacker,opponent,move)
		if priotype != :NONE
			type = pbRoughType(move, attacker, 100)
			typeMod = pbCalcTypeMod(type,attacker,opponent)
			priotypeMod = pbCalcTypeMod(priotype,attacker,opponent)
			if Effectiveness.super_effective?(priotypeMod) && priotype == resistBerryType(opponent) &&
				((type == priotype) || (priodamage*3>=opponent.hp))
				#echoln priotype
				priodamage*=2 
			end
		end
		damage=@damagesAI[attacker.index][idxmove][:dmg][opponent.index]#pbRoughDamage(move,attacker,opponent,100)
		damage+=priodamage
		damage*=mult
		# if opponent.name=="Darkbat" && attacker.name=="Metarill" && move.name=="Play Rough"
		# 	print damage
		# 	print opponent.hp
		# end
		if !mold_broken && opponent.hasActiveAbility?(:DISGUISE) && opponent.turnCount==0	
			if ["HitTwoToFiveTimes", "HitTwoTimes", "HitThreeTimes" ,"HitTwoTimesFlinchTarget", "HitThreeTimesPowersUpWithEachHit", "HitTenTimes"].include?(move.function)
				damage*=0.6
			else
				damage=1
			end
		end		
		if !mold_broken && opponent.hasActiveAbility?(:ICEFACE) && move.physicalMove? && opponent.form==0
			if ["HitTwoToFiveTimes", "HitTwoTimes", "HitThreeTimes" ,"HitTwoTimesFlinchTarget", "HitThreeTimesPowersUpWithEachHit", "HitTenTimes"].include?(move.function)
				damage*=0.6
			else
				damage=1
			end
		end		
		effectivehp = opponent.hp 
		if  ["HitTwoToFiveTimes", "HitTwoTimes", "HitThreeTimes" ,"HitTwoTimesFlinchTarget", "HitThreeTimesPowersUpWithEachHit", "HitTenTimes"].include?(move.function)
			effectivehp *= 1.25 if opponent.hasActiveItem?(:SITRUSBERRY)
			effectivehp += 10 if opponent.hasActiveItem?(:ORANBERRY)
			effectivehp += 20 if opponent.hasActiveItem?(:BERRYJUICE)
		end
		return true if damage < effectivehp
		return false if priodamage>0
		if (opponent.hasActiveItem?(:FOCUSSASH) || (!mold_broken && opponent.hasActiveAbility?(:STURDY))) && opponent.hp==opponent.totalhp
			return false if ["HitTwoToFiveTimes", "HitTwoTimes", "HitThreeTimes" ,"HitTwoTimesFlinchTarget", "HitThreeTimesPowersUpWithEachHit", "HitTenTimes"].include?(move.function)
			return true
		end	
		return false
	end

	def canSleepTarget(attacker,opponent,berry=false)
		return false if opponent.effects[PBEffects::Substitute]>0
		return false if berry && (opponent.status==:SLEEP)# && opponent.statusCount>1)
		return false if (opponent.hasActiveItem?(:LUMBERRY) || opponent.hasActiveItem?(:CHESTOBERRY)) && berry
		return false if !opponent.pbCanSleep?(attacker,false)
		return false if opponent.pbOwnSide.effects[PBEffects::Safeguard] > 0 && !attacker.hasActiveAbility?(:INFILTRATOR)
		for move in attacker.moves
			if ["SleepTarget", "SleepTargetIfUserDarkrai", "SleepTargetNextTurn"].include?(move.function)
				return false if move.powderMove? && opponent.pbHasType?(:GRASS)
				return true	
			end	
		end	
		return false
	end
	
	def bestMoveVsTarget(user,target,skill,rough=false)
		maxdam=0
		maxmove=user.moves[0]
		maxidxmove=0
		maxprio=0
		maxpriotype=:NONE
		physorspec= "none"
		user.moves.each_with_index do |j,i|
			if moveLocked(user)
				if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
					next if j.id!=user.lastMoveUsed
				end
			end		
			if rough
			 tempdam = pbRoughDamage(j,user,target,skill,j.baseDamage)
			 tempdam = 0 if pbCheckMoveImmunity(1,j,user,target,100)
			else
			 tempdam = @damagesAI[user.index][i][:dmg][target.index]
			end
			if tempdam>maxdam
				maxdam=tempdam 
				maxmove=j
				maxidxmove=i
				physorspec= "physical" if j.physicalMove?(j.type)
				physorspec= "special" if j.specialMove?(j.type)
			end	
			if priorityAI(user,j)>0
				if tempdam>maxprio
					maxprio=tempdam 
					maxpriotype=pbRoughType(j, user, skill)
				end
			end	
		end 
		return [maxdam,maxmove,maxprio,physorspec,maxidxmove,maxpriotype]
	end	


	def checkWeatherBenefit(user)
		sum=0
		ownparty = @battle.pbParty(user.index)
		ownparty.each_with_index do |pkmn, idxParty|
			next if !pkmn || !pkmn.able?
			if [:Sun, :HarshSun, :HolyInferno].include?(@battle.pbWeather)
				sum+=20 if pkmn.ability == :CHLOROPHYLL
				sum+=10 if pkmn.ability == :FLOWERGIFT || pkmn.ability == :SOLARPOWER || pkmn.ability == :PROTOSYNTHESIS || 
							pkmn.ability == :SYNTHESIZE # Changed by DemICE 30-Aug-2023 Soulstones 2 Specifics
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :FIRE
					sum += 10
				end   
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :WATER
					sum -= 5
				end   
				sum+=5 if pkmn.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun")
				sum+=10 if pkmn.pbHasMoveFunction?("TwoTurnAttackOneTurnInSun") 
			end
			if [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(@battle.pbWeather)
				sum+=20 if pkmn.ability == :SWIFTSWIM
				sum+=5 if pkmn.ability == :RAINDISH || pkmn.ability == :DRYSKIN || pkmn.ability == :HYDRATION
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :WATER
					sum += 10
				end   
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :FIRE
					sum -= 5
				end   
				sum-=5 if pkmn.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun") && @battle.field.weather == :Sun
				sum+=5 if pkmn.pbHasMoveFunction?("ParalyzeTargetAlwaysHitsInRainHitsTargetInSky") 
				sum+=10 if pkmn.pbHasMoveFunction?("TwoTurnAttackChargeRaiseUserSpAtk1OneTurnInRain") 
			end
			if @battle.pbWeather==:Sandstorm
				sum+=20 if pkmn.ability == :SANDRUSH
				sum+=10 if pkmn.ability == :SANDVEIL || pkmn.ability == :SANDFORCE || 
							pkmn.ability == :CLAYFORM  # Changed by DemICE 30-Aug-2023 Soulstones 2 Specifics
				sum+=10 if pkmn.hasType?(:ROCK)
				sum-=5 if pkmn.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun") && @battle.field.weather == :Sun
				sum+=5 if pkmn.pbHasMoveFunction?("HealUserDependingOnSandstorm") 
			end
			if [:Hail, :FreezingRain, :FrozenStorm].include?(@battle.pbWeather)
				sum+=20 if pkmn.ability == :SLUSHRUSH || pkmn.ability == :WINTERGIFT || pkmn.ability == :ICYVEINS  # Changed by DemICE 30-Aug-2023 Soulstones 2 Specifics
				sum+=10 if pkmn.ability == :SNOWCLOAK || pkmn.ability == :ICEBODY || pkmn.ability == :PACKEDSNOW  # Changed by DemICE 30-Aug-2023 Soulstones 2 Specifics
				sum+=10 if pkmn.hasType?(:ICE) && PluginManager.installed?("Generation 9 Pack") && Settings::HAIL_WEATHER_TYPE > 0 && @battle.pbWeather==:Hail
				sum-=5 if pkmn.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun") && @battle.field.weather == :Sun
				sum+=5 if pkmn.pbHasMoveFunction?("FreezeTargetAlwaysHitsInHail") 
				sum+=5 if pkmn.pbHasMoveFunction?("StartWeakenDamageAgainstUserSideIfHail") 
			end
			if @battle.field.terrain==:Electric
				sum+=5 if pkmn.item == :ELECTRICSEED
				sum+=10 if pkmn.ability == :SURGESURFER
				sum+=10 if pkmn.ability == :QUARKDRIVE
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :ELECTRIC
					sum += 5
				end   
				sum+=5 if pkmn.pbHasMoveFunction?("TypeAndPowerDependOnTerrain", "BPRaiseWhileElectricTerrain")
				sum+=5 if pkmn.pbHasMoveFunction?("DoublePowerInElectricTerrain") 
			end
			if @battle.field.terrain==:Grassy
				sum+=5 if pkmn.item == :GRASSYSEED
				sum+=5 if pkmn.ability == :GRASSPELT
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :GRASS
					sum += 5
				end   
				score-=5 if pkmn.pbHasMoveFunction?("DoublePowerIfTargetUnderground", "RandomPowerDoublePowerIfTargetUnderground",
					"LowerTargetSpeed1WeakerInGrassyTerrain")
				sum+=5 if pkmn.pbHasMoveFunction?("TypeAndPowerDependOnTerrain", "HealTargetDependingOnGrassyTerrain")
				sum+=5 if pkmn.pbHasMoveFunction?("HigherPriorityInGrassyTerrain") 
			end
			if @battle.field.terrain==:Misty
				sum+=5 if pkmn.item == :MISTYSEED
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :DRAGON
					sum -= 5
				end   
				score-=5 if pkmn.pbHasMoveFunction?("SleepTarget", "SleepTargetIfUserDarkrai", "SleepTargetChangeUserMeloettaForm", 
					"ParalyzeTargetIfNotTypeImmune", "BadPoisonTarget")
				sum+=5 if pkmn.pbHasMoveFunction?("TypeAndPowerDependOnTerrain", "UserFaintsPowersUpInMistyTerrainExplosive")
			end
			if @battle.field.terrain==:Psychic
				sum+=5 if pkmn.item == :PSSYCHICSEED
				sum-=5 if pkmn.ability == :PRANKSTER
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :PSYCHIC
					sum += 5
				end  
				pkmn.eachMove do |m|
					sum -= 1 if m.prio>0
				end   
				sum+=5 if pkmn.pbHasMoveFunction?("TypeAndPowerDependOnTerrain", "HitsAllFoesAndPowersUpInPsychicTerrain")
			end
		end
		return sum
	end


	def priorityAI(user,move,switchin=false)
		turncount = user.turnCount
		turncount = 0 if switchin
		pri = move.priority
		pri +=1 if user.hasActiveAbility?(:GALEWINGS) && user.hp==user.totalhp && move.type==:FLYING
		pri +=1 if move.baseDamage==0 && user.hasActiveAbility?(:PRANKSTER)
		pri +=1 if move.function=="HigherPriorityInGrassyTerrain" && @battle.field.terrain==:Grassy && user.affectedByTerrain?
		pri +=3 if move.healingMove? && user.hasActiveAbility?(:TRIAGE)
		return pri
	end
	
	def moveLocked(user)
		return true if user.effects[PBEffects::ChoiceBand] && user.hasActiveItem?([:CHOICEBAND,:CHOICESPECS,:CHOICESCARF])
		return true if user.usingMultiTurnAttack?
		return true if user.effects[PBEffects::Encore] > 0
		return true if user.hasActiveAbility?(:GORILLATACTICS)
		return false
	end
	
end


class Battle::Battler
	
	def pbMoveTypeWeakeningBerry(berry_type, move_type, mults)
		return if move_type != berry_type
		return if !Effectiveness.super_effective?(@damageState.typeMod) && move_type != :NORMAL
		mults[:final_damage_multiplier] /= 2
		@damageState.berryWeakened = true
		ripening = false
		if hasActiveAbility?(:RIPEN)
			@battle.pbShowAbilitySplash(self)
			mults[:final_damage_multiplier] /= 2
			ripening = true
		end
		@battle.pbCommonAnimation("EatBerry", self) if !$aiberrycheck
		@battle.pbHideAbilitySplash(self) if ripening
	end
	
	# Needing AI to account for mold breaker.
	def airborneAI(moldbreaker=false)
		return true if hasActiveAbility?(:LEVITATE) && !moldbreaker
		return airborne?
	end
	
	alias stupidity_hasActiveAbility? hasActiveAbility?
	def hasActiveAbility?(check_ability, ignore_fainted = false, mold_broken=false)
		return false if mold_broken
		return stupidity_hasActiveAbility?(check_ability, ignore_fainted) 
	end

	
	def pbCanLowerAttackStatStageIntimidateAI(user)
		return false if fainted?
		# NOTE: Substitute intentionally blocks Intimidate even if self has Contrary.
		return false if @effects[PBEffects::Substitute] > 0
		return false if Settings::MECHANICS_GENERATION >= 8 && hasActiveAbility?([:OBLIVIOUS, :OWNTEMPO, :INNERFOCUS, :SCRAPPY])
		# NOTE: These checks exist to ensure appropriate messages are shown if
		#       Intimidate is blocked somehow (i.e. the messages should mention the
		#       Intimidate ability by name).
		return false if !hasActiveAbility?(:CONTRARY)
		return false if !pbCanLowerStatStage?(:ATTACK, user)
	end	
	
end	


class Battle
	
	def pbMakeFakeBattler(pokemon,batonpass=false,currentmon=nil,effectnegate=true)
		if @index.nil? || !currentmon.nil?
			@index=currentmon.index
		end
		wonderroom= @field.effects[PBEffects::WonderRoom]!=0
		battler = Battler.new(self,@index)
		battler.pbInitPokemon(pokemon,@index)
		battler.pbInitEffects(batonpass)#,false,effectnegate)
		battler.effects[PBEffects::Illusion] = nil
		if batonpass
			battler.stages[:ATTACK]          = currentmon.stages[:ATTACK]
			battler.stages[:DEFENSE]         = currentmon.stages[:DEFENSE]
			battler.stages[:SPEED]           = currentmon.stages[:SPEED]
			battler.stages[:SPECIAL_ATTACK]  = currentmon.stages[:SPECIAL_ATTACK]
			battler.stages[:SPECIAL_DEFENSE] = currentmon.stages[:SPECIAL_DEFENSE]
			battler.stages[:ACCURACY]        = currentmon.stages[:ACCURACY]
			battler.stages[:EVASION]         = currentmon.stages[:EVASION]
		end	
		battler.stages[:SPEED] -= 1 if battler.pbOwnSide.effects[PBEffects::StickyWeb] && !battler.airborne?
		if battler.hasActiveAbility?(:MIMICRY)
			# Change to new typing
			terrain_hash = {
			:Electric => :ELECTRIC,
			:Grassy   => :GRASS,
			:Misty    => :FAIRY,
			:Psychic  => :PSYCHIC
			}
			new_type = terrain_hash[@field.terrain]
			new_type_name = nil
			if new_type
			type_data = GameData::Type.try_get(new_type)
			new_type = nil if !type_data
			new_type_name = type_data.name if type_data
			end
			if new_type
				battler.pbChangeTypes(new_type)
			end
		end
		return battler
	end	


	def pbCanHardSwitchLax?(idxBattler, idxParty)
		return true if idxParty < 0
		party = pbParty(idxBattler)
		return false if idxParty >= party.length
		return false if !party[idxParty]
		if party[idxParty].egg?
		  return false
		end
		if !pbIsOwner?(idxBattler, idxParty)
		  return false
		end
		if party[idxParty].fainted?
		  return false
		end
		# if pbFindBattler(idxParty, idxBattler)
		#   partyScene.pbDisplay(_INTL("{1} is already in battle!",
		# 							 party[idxParty].name)) if partyScene
		#   return false
		# end
		return true
	  end	

	
	def pbCommandPhaseLoop(isPlayer)
		# NOTE: Doing some things (e.g. running, throwing a Poké Ball) takes up all
		#       your actions in a round.
		actioned = []
		idxBattler = -1
		# DemICE store all damages in a hash for better efficiency.
		@battleAI.registerDamagesAI if isPlayer
		loop do
			break if @decision != 0   # Battle ended, stop choosing actions
			idxBattler += 1
			break if idxBattler >= @battlers.length
			next if !@battlers[idxBattler] || pbOwnedByPlayer?(idxBattler) != isPlayer
			next if @choices[idxBattler][0] != :None    # Action is forced, can't choose one
			next if !pbCanShowCommands?(idxBattler)   # Action is forced, can't choose one
			@controlPlayer = true if pbPlayerBattlerCount == 0 # Failsafe in case of AI mon shifting to a player mon position
			if !@controlPlayer && pbOwnedByPlayer?(idxBattler)
				# Player chooses an action
				actioned.push(idxBattler)
				commandsEnd = false   # Whether to cancel choosing all other actions this round
				loop do
					cmd = pbCommandMenu(idxBattler, actioned.length == 1)
					# If being Sky Dropped, can't do anything except use a move
					if cmd > 0 && @battlers[idxBattler].effects[PBEffects::SkyDrop] >= 0
						pbDisplay(_INTL("Sky Drop won't let {1} go!", @battlers[idxBattler].pbThis(true)))
						next
					end
					case cmd
					when 0    # Fight
						break if pbFightMenu(idxBattler)
					when 1    # Bag
						if pbItemMenu(idxBattler, actioned.length == 1)
							commandsEnd = true if pbItemUsesAllActions?(@choices[idxBattler][1])
							break
						end
					when 2    # Pokémon
						break if pbPartyMenu(idxBattler)
					when 3    # Run
						# NOTE: "Run" is only an available option for the first battler the
						#       player chooses an action for in a round. Attempting to run
						#       from battle prevents you from choosing any other actions in
						#       that round.
						if pbRunMenu(idxBattler)
							commandsEnd = true
							break
						end
					when 4    # Call
						break if pbCallMenu(idxBattler)
					when -2   # Debug
						pbDebugMenu
						next
					when -1   # Go back to previous battler's action choice
						next if actioned.length <= 1
						actioned.pop   # Forget this battler was done
						idxBattler = actioned.last - 1
						pbCancelChoice(idxBattler + 1)   # Clear the previous battler's choice
						actioned.pop   # Forget the previous battler was done
						break
					end
					pbCancelChoice(idxBattler)
				end
			else 
				# DemICE moved the AI decision after player decision.
				# AI controls this battler
				@battleAI.pbDefaultChooseEnemyCommand(idxBattler)
			end 
			break if commandsEnd
		end
	end
	
end

class Pokemon

    def isAirborne?
        return false if @item == :IRONBALL
        return true if hasType?(:FLYING)
        return true if @ability == :LEVITATE
        return true if @item == :AIRBALLOON
        return false
    end

    def eachMove
        @moves.each { |m| yield m }
    end  
    
    def pbHasMoveFunction?(*arg)
        return false if !arg
        eachMove do |m|
          arg.each { |code| return true if m.function_code == code }
        end
        return false
      end    

end  