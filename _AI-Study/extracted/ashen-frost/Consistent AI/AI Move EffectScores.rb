class Battle::AI
	
	alias stupidity_pbGetMoveScoreFunctionCode pbGetMoveScoreFunctionCode
	
	def pbGetMoveScoreFunctionCode(score, move, user, target, skill = 100,idxmove=0)
		initialscore=score
		attacker=user
		opponent=user.pbDirectOpposing(true)
        mold_broken=moldbroken(attacker,opponent,move)
		# prankpri = false
		# if move.baseDamage==0 && attacker.hasWorkingAbility(:PRANKSTER)
		# 	prankpri = true
		# end	
		# if move.priority>0 || prankpri || (attacker.hasWorkingAbility(:GALEWINGS) && attacker.hp==attacker.totalhp && move.type==:FLYING)
		thisprio = priorityAI(user,move)
		if thisprio>0 
			aspeed = pbRoughStat(attacker,:SPEED,skill)
			ospeed = pbRoughStat(opponent,:SPEED,skill)
			if move.baseDamage>0  
				fastermon = ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				if fastermon
					echo("\n"+user.name+" is faster than "+opponent.name+".\n")
				else
					echo("\n"+opponent.name+" is faster than "+user.name+".\n")
				end   
				# pridamage=pbRoughDamage(move,attacker,opponent,skill,move.baseDamage)   
				# if pridamage>=opponent.totalhp  
				if !targetSurvivesMove(move,idxmove,attacker,opponent)
					echo("\n"+opponent.name+" will not survive.")
					if fastermon
						echo("Score x1.3\n")
						score*=1.3
					else
						echo("Score x2\n")
						score*=2
					end
				end   
				movedamage = -1
				maxpriomove=nil
				maxprioidx=0
				maxmove=nil   
				maxidxmove=0
				movedamage = -1
				opppri = false     
				pridam = -1
				#if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				opponent.moves.each_with_index do |j,i|
					tempdam = @damagesAI[opponent.index][i][:dmg][attacker.index]#pbRoughDamage(j,opponent,attacker,skill,j.baseDamage)
					if priorityAI(opponent,j)>0
						opppri=true
						if tempdam>pridam
							pridam = tempdam
							maxpriomove=j
							maxprioidx=i
						end              
					end    
					if tempdam>movedamage
						movedamage = tempdam
						maxmove=j
						maxidxmove=i
					end 
				end 
				if opppri
					echo("Expected priority damage taken by "+opponent.name+": "+pridam.to_s+"\n") 
				end
				#end
				if !fastermon
					echo("Expected damage taken by "+opponent.name+": "+movedamage.to_s+"\n") 
					maxdam=0
					maxmove2=nil
					maxidxmove2=0
					#if movedamage>attacker.hp
					if !targetSurvivesMove(maxmove,maxidxmove,opponent,attacker)
						echo(user.name+" does not survive. Score +150. \n")
						score+=150
						opponent.moves.each_with_index do |j,i|
							if moveLocked(opponent)
								if opponent.lastMoveUsed && opponent.pbHasMove?(opponent.lastMoveUsed)
									next if j.id!=opponent.lastMoveUsed
								end
							end		
							tempdam = @damagesAI[opponent.index][i][:dmg][attacker.index]#pbRoughDamage(j,opponent,attacker,skill,j.baseDamage)
							maxdam=tempdam if tempdam>maxdam
							maxmove2=j
							maxidxmove2=i
						end  
						#if maxdam>=attacker.hp
						if !targetSurvivesMove(maxmove2,maxidxmove2,opponent,attacker)
							score+=30
						end
					end
				end     
				if opppri
					score*=1.1
					#if pridam>attacker.hp
					if !targetSurvivesMove(maxpriomove,maxprioidx,opponent,attacker)
						if fastermon
							echo(user.name+" does not survive piority move. Score x3. \n")
							score*=3
						else
							echo(user.name+" does not survive priority move but is faster. Score -100 \n")
							score-=100
						end
					end
				end
				if !fastermon && opponent.inTwoTurnAttack?("TwoTurnAttackInvulnerableInSky",
						"TwoTurnAttackInvulnerableUnderground",
						"TwoTurnAttackInvulnerableInSkyParalyzeTarget",
						"TwoTurnAttackInvulnerableUnderwater",
						"TwoTurnAttackInvulnerableInSkyTargetCannotAct")
					echo("Player Pokemon is invulnerable. Score-300. \n")
					score-=300
				end
				if @battle.field.terrain == :Psychic && opponent.affectedByTerrain?
					echo("Blocked by Psychic Terrain. Score-300. \n")
					score-=300
				end
				@battle.allSameSideBattlers(opponent.index).each do |b|
					priobroken=moldbroken(attacker,b,move)
					if b.hasActiveAbility?([:DAZZLING, :QUEENLYMAJESTY, :ARMORTAIL],false,priobroken) 
						score-=300 
						echo("Blocked by enemy ability. Score-300. \n")
					end
				end 
				if pbTargetsMultiple?(move,user)    
					quickcheck = false 
					for j in opponent.moves
						quickcheck = true if j.function=="ProtectUserSideFromPriorityMoves"
					end          
					if quickcheck
						echo("Expecting quick guard. Score-200. \n")
						score-=200
					end  
				end    
			end      
		elsif thisprio<0
			if fastermon
				score*=0.9
				if move.baseDamage>0
					if opponent.inTwoTurnAttack?("TwoTurnAttackInvulnerableInSky",
							"TwoTurnAttackInvulnerableUnderground",
							"TwoTurnAttackInvulnerableInSkyParalyzeTarget",
							"TwoTurnAttackInvulnerableUnderwater",
							"TwoTurnAttackInvulnerableInSkyTargetCannotAct")
						echo("Negative priority move and AI pokemon is faster. Score x2 because Player Pokemon is invulnerable. \n")
						score*=2
					end
				end
			end      
		end   


		case move.function
			
			#---------------------------------------------------------------------------
		when "SleepTarget", "SleepTargetIfUserDarkrai", "SleepTargetChangeUserMeloettaForm", "SleepTargetNextTurn", "DrowseTarget"
			aspeed = pbRoughStat(user, :SPEED, skill)
			ospeed = pbRoughStat(target, :SPEED, skill)
			if target.pbCanSleep?(user,false,move)
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec,maxidxmove]
				maxdam=bestmove[0] 
				maxidx=bestmove[4] 
				maxmove=bestmove[1]
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				halfopphealth = (target.hp/2)
				score += 90
				if ((aspeed > ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) &&
					!targetSurvivesMove(maxmove,maxidx,target,attacker)
					score+=30
				end
				maxowndmg=0
				maxownidx=0
				maxownmove=nil
				bestownmove=bestMoveVsTarget(user,target,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxowndmg=bestownmove[0]
				maxownidx=bestownmove[4]
				maxownmove=bestownmove[1]
				if targetSurvivesMove(maxownmove,maxownidx,attacker,target)
					score+=30
					score+=20 if user.hasActiveAbility?(:BADDREAMS)
				end
				if target.pbHasMoveFunction?("RaiseUserEvasion2", "RaiseUserEvasion2MinimizeUser", "RaiseUserEvasion3",   # Evasion Moves
						"AddSpikesToFoeSide", "AddToxicSpikesToFoeSide", "AddStealthRocksToFoeSide", "AddStickyWebToFoeSide", # Hazards
						"HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn",  # Recovery
						"HealUserDependingOnWeather", "HealUserDependingOnSandstorm", "HealUserFullyAndFallAsleep")  # Recovery
					score += 40
				end
				if user.pbHasMoveFunction?("RaiseUserSpAtkSpDefSpd1", "RaiseUserAtkSpd1", # Quiver Dance, Dragon Dance
						"RaiseUserAtk1Spd2", "LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2",  # Shift Gear, Shell Smash
						"RaiseUserEvasion2", "RaiseUserEvasion2MinimizeUser", "RaiseUserEvasion3",   # Evasion Moves
						"AddSpikesToFoeSide", "AddToxicSpikesToFoeSide", "AddStealthRocksToFoeSide", "AddStickyWebToFoeSide", # Hazards
						"HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn",  # Recovery
						"HealUserDependingOnWeather", "HealUserDependingOnSandstorm", "HealUserFullyAndFallAsleep")  # Recovery
					score += 40
				end
				if user.pbHasMoveFunction?("RaiseUserAtkDef1", "RaiseUserAtkDefAcc1", "RaiseUserSpAtkSpDef1", # Swords Dance, Coil, Calm Mind
						"RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserDefSpDef1", # Growth, Cosmoic Power
						"RaiseUserAttack1", "RaiseUserAttack2", "RaiseUserAtkAcc1", # Howl, Swords Dance, Hone Claws
						"RaiseUserSpAtk2", "RaiseUserSpAtk3") && # Nasty Plot, Tail Glow
					aspeed > ospeed
					score += 40
				end
				score-=50 if target.hasActiveItem?(:LUMBERRY) || target.hasActiveItem?(:CHESTOBERRY)
				if skill >= PBTrainerAI.mediumSkill
					score -= 30 if maxowndmg>halfopphealth
				end
				if skill >= PBTrainerAI.mediumSkill
					score -= 200 if target.effects[PBEffects::Yawn] > 0 && move.function == "SleepTargetNextTurn"
				end
				score -=200 if target.hasActiveAbility?(:HYDRATION) && [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(target.effectiveWeather)
				if skill >= PBTrainerAI.highSkill
					score -= 30 if target.hasActiveAbility?(:MARVELSCALE)
				end
				if skill >= PBTrainerAI.bestSkill
					if target.pbHasMoveFunction?("FlinchTargetFailsIfUserNotAsleep",
							"UseRandomUserMoveIfAsleep")   # Snore, Sleep Talk
						score -= 50
					end
					score -= 150 if target.hasActiveAbility?(:EARLYBIRD)
				end
			elsif skill >= PBTrainerAI.mediumSkill
				score -= 90 if move.statusMove?
				score -=200 if target.effects[PBEffects::Yawn] > 0 && move.function == "SleepTargetNextTurn"
			end
			
			#---------------------------------------------------------------------------
		when "ParalyzeTarget", "ParalyzeTargetIfNotTypeImmune",
			"ParalyzeTargetAlwaysHitsInRainHitsTargetInSky", "ParalyzeFlinchTarget"
			if target.pbCanParalyze?(user, false,move) &&
				!(skill >= PBTrainerAI.mediumSkill &&
					move.id == :THUNDERWAVE &&
					Effectiveness.ineffective?(pbCalcTypeMod(move.type, user, target)))
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxprio=bestmove[2]
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				score += 10
				score-=50 if target.hasActiveItem?(:LUMBERRY) || target.hasActiveItem?(:CHERIBERRY)
				score-=50 if maxprio>thirdhealth
				if skill >= PBTrainerAI.mediumSkill
					aspeed = pbRoughStat(user, :SPEED, skill)
					ospeed = pbRoughStat(target, :SPEED, skill)
					halfspeed = ospeed/2
					if ((aspeed < ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						score += 40
						score += 60 if move.statusMove? && ((aspeed > halfspeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
					elsif ((aspeed > ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						score -= 40
					end
				end
				score -=200 if target.hasActiveAbility?(:HYDRATION) && [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(target.effectiveWeather)
				if skill >= PBTrainerAI.highSkill
					score -= 40 if target.hasActiveAbility?([:GUTS, :MARVELSCALE, :QUICKFEET])
				end
			elsif skill >= PBTrainerAI.mediumSkill
				score -= 200 if move.statusMove?
			end
			
			#---------------------------------------------------------------------------
		when "BurnTarget"
			if target.pbCanBurn?(user, false,move)
				score += 30    
				score += 80 if target.hasActiveAbility?(:WONDERGUARD)
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4] 
				maxmove=bestmove[1]
				maxphys=(bestmove[3]=="physical") 
				halfhealth=(user.hp/2)      
				halfdam= maxdam*0.5
				if skill>=PBTrainerAI.highSkill
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
					score -= 20 if ((aspeed > ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
				end
				if move.statusMove? && maxphys
					score += 40 
					score += 80 if halfdam < halfhealth
					score += 10 * target.stages[:ATTACK] 
				# elsif move.addlEffect == 100 && maxphys
				# 	if halfdam < halfhealth
				# 		score += 1000 
				# 	end
				# 	if !targetSurvivesMove(maxmove,maxidx,target,user) && targetSurvivesMove(maxmove,maxidx,target,user,0,0.5) &&
				# 				((aspeed > ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) 
				# 		score+= 1000 
				# 	end
				end   
				if target.hasActiveItem?(:LUMBERRY) || target.hasActiveItem?(:RAWSTBERRY)
					score-=50 
					score-=150 if maxdam>halfhealth
				end	
				score -=200 if target.hasActiveAbility?(:HYDRATION) && [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(target.effectiveWeather)
				if skill >= PBTrainerAI.highSkill
					score -= 40 if target.hasActiveAbility?([:GUTS, :MARVELSCALE, :QUICKFEET, :FLAREBOOST])
				end
			elsif skill >= PBTrainerAI.mediumSkill
				score -= 200 if move.statusMove?
			end  
			#---------------------------------------------------------------------------
		when "PoisonTarget", "BadPoisonTarget", "HitTwoTimesPoisonTarget"
			if target.pbCanPoison?(user,false,move)
				score += 40
				if target.pbHasMoveFunction?("RaiseUserSpAtkSpDefSpd1", "RaiseUserAtkSpd1", # Quiver Dance, Dragon Dance
						"RaiseUserAtk1Spd2", "LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2",  # Shift Gear, Shell Smash
						"RaiseUserEvasion2", "RaiseUserEvasion2MinimizeUser", "RaiseUserEvasion3",   # Evasion Moves
						"AddSpikesToFoeSide", "AddToxicSpikesToFoeSide", "AddStealthRocksToFoeSide", "AddStickyWebToFoeSide", # Hazards
						"HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn",  # Recovery
						"HealUserDependingOnWeather", "HealUserDependingOnSandstorm", "HealUserFullyAndFallAsleep", # Recovery
						"RaiseUserAtkDef1", "RaiseUserAtkDefAcc1", "RaiseUserSpAtkSpDef1", # Swords Dance, Coil, Calm Mind
						"RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserDefSpDef1", # Growth, Cosmoic Power
						"RaiseUserAttack1", "RaiseUserAttack2", "RaiseUserAtkAcc1", # Howl, Swords Dance, Hone Claws
						"RaiseUserSpAtk2", "RaiseUserSpAtk3")  
					score += 20
				end
				score += 80 if target.hasActiveAbility?(:WONDERGUARD)
				if skill>=PBTrainerAI.mediumSkill
					score += 30 if target.hp<=target.totalhp/4
					score += 50 if target.hp<=target.totalhp/8
					score -= 40 if target.effects[PBEffects::Yawn]>0
				end
				score -=200 if target.hasActiveAbility?(:HYDRATION) && [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(target.effectiveWeather)
				if skill>=PBTrainerAI.highSkill
					score += 10 if pbRoughStat(target,:DEFENSE,skill)>100
					score += 10 if pbRoughStat(target,:SPECIAL_DEFENSE,skill)>100
					score -= 40 if target.hasActiveAbility?([:GUTS,:MARVELSCALE,:TOXICBOOST])
				end
			else
				if skill>=PBTrainerAI.mediumSkill
					score -= 200 if move.statusMove?
				end
			end              
			#---------------------------------------------------------------------------
		when "FlinchTargetFailsIfNotUserFirstTurn"   # Fake Out
			if user.turnCount == 0
				#if skill >= PBTrainerAI.highSkill
				if !target.hasActiveAbility?(:INNERFOCUS) &&
					target.effects[PBEffects::Substitute] == 0
					score +=120 
					maxdam = 0
					@battle.allSameSideBattlers(user.index).each do |b|
						bestmove=bestMoveVsTarget(target,b,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0]  if bestmove[0]>maxdam
					end
					score += maxdam
				end
				# end
			else
				score -= 90   # Because it will fail here
				score = 0 #if skill >= PBTrainerAI.bestSkill
			end
			
		when "DoublePowerIfTargetAsleepCureTarget"          # Wake-Up Slap   
			score -= 1000 if [:SLEEP, :DROWSY].include?(target.status) && target.statusCount > 1    
			#---------------------------------------------------------------------------
		when "RaiseUserEvasion1", "RaiseUserEvasion2", "RaiseUserEvasion2MinimizeUser", "RaiseUserEvasion3"  # Minimize
			if move.statusMove?
				if user.statStageAtMax?(:EVASION) || user.hasActiveAbility?(:CONTRARY)
					score -= 90
				else
					target==user.pbDirectOpposing(true)
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker) || (target.status == :SLEEP && target.statusCount>1)
						score += 40
						score += 20 if halfhealth>maxdam
						score += 40 if thirdhealth>maxdam
						if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn", "HealUserFullyAndFallAsleep")   # Recover, Roost
							score += 40
						end
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>halfhealth
						end
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:EVASION] * 10
				end
			else
				score += 10 if user.turnCount == 0
				score += 20 if user.stages[:EVASION] < 0
			end
			#---------------------------------------------------------------------------
		when "CurseTargetOrLowerUserSpd1RaiseUserAtkDef1"  # Curse
			target=user.pbDirectOpposing(true)
			if user.pbHasType?(:GHOST)
				score-=200 if target.effects[PBEffects::Curse]
				score-=200 if target.hasActiveAbility?(:MAGICGUARD)
			else     
				if (user.statStageAtMax?(:ATTACK) &&
					user.statStageAtMax?(:DEFENSE)) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else 
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					maxphys=(bestmove[3]=="physical") 
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype)|| (target.status == :SLEEP && target.statusCount>1)
						score += 40
						score+=20 if maxphys
						if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
							score += 20
						end
						if skill>=PBTrainerAI.highSkill
							aspeed = pbRoughStat(user,:SPEED,skill)
							ospeed = pbRoughStat(target,:SPEED,skill)
							score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>halfhealth
						end
						score += 20 if halfhealth>maxdam
						score += 40 if thirdhealth>maxdam
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:ATTACK]*10
					score -= user.stages[:DEFENSE]*10
					if skill>=PBTrainerAI.mediumSkill
						hasPhysicalAttack = false
						if user.hasActiveItem?(:ENCONVERTER)
							hasPhysicalAttack = true
						else
							user.eachMove do |m|
								next if !m.physicalMove?(m.type)
								hasPhysicalAttack = true
								break
							end
						end
						if hasPhysicalAttack
							score += 20
						elsif skill>=PBTrainerAI.highSkill
							score -= 90
						end
						score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
					end
				end
			end    
			#---------------------------------------------------------------------------
		when "RaiseUserAtkDef1"  # Bulk Up
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:ATTACK) &&
				user.statStageAtMax?(:DEFENSE)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				maxphys=(bestmove[3]=="physical") 
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype)|| (target.status == :SLEEP && target.statusCount>1)
					score += 40
					score+=20 if maxphys
					if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
						score += 20
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
					end
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:ATTACK]*10
				score -= user.stages[:DEFENSE]*10
				if skill>=PBTrainerAI.mediumSkill
					hasPhysicalAttack = false
					if user.hasActiveItem?(:ENCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.physicalMove?(m.type)
							hasPhysicalAttack = true
							break
						end
					end
					if hasPhysicalAttack
						score += 20
					elsif skill>=PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end
			
			#---------------------------------------------------------------------------
		when "RaiseUserAtkDefAcc1"  # Coil
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:ATTACK) &&
				user.statStageAtMax?(:DEFENSE) &&
				user.statStageAtMax?(:ACCURACY)) || user.hasActiveAbility?(:CONTRARY)
				score -= 90
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				maxphys=(bestmove[3]=="physical") 
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 40
					score+=20 if maxphys
					if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
						score += 20
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
					end
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:ATTACK]*10
				score -= user.stages[:DEFENSE]*10
				score -= user.stages[:ACCURACY]*10
				if skill>=PBTrainerAI.mediumSkill
					hasPhysicalAttack = false
					if user.hasActiveItem?(:ENCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.physicalMove?(m.type)
							hasPhysicalAttack = true
							break
						end
					end
					if hasPhysicalAttack
						score += 20
					elsif skill>=PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end		  
			
			#---------------------------------------------------------------------------
		when "RaiseUserAtkSpd1", "RaiseUserAtkSpd1RemoveHazardsSubstitutes"  # Dragon Dance
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:ATTACK) &&
				user.statStageAtMax?(:SPEED)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				maxowndam=0
				maxownidx=0
				maxownmove=nil
				bestownmove=bestMoveVsTarget(user,target,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxowndam=bestownmove[0] 
				maxownidx=bestownmove[4]
				maxownmove=bestownmove[1]
				maxownprio=bestownmove[2]
				priodam=0
				priomove=nil
				user.moves.each_with_index do |j,i|
					next if priorityAI(user,j)<1
					if moveLocked(user)
						if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
							next if j.id!=user.lastMoveUsed
						end
					end		
					tempdam =  @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					if tempdam>priodam
						priodam=tempdam 
						priomove=j
					end	
				end 
				prioppdam=0
				prioppmove=nil
				prioppidx=0
				target.moves.each_with_index do |j,i|
					next if priorityAI(target,j)<1
					if moveLocked(target)
						if target.lastMoveUsed && target.pbHasMove?(target.lastMoveUsed)
							next if j.id!=target.lastMoveUsed
						end
					end		
					tempdam = @damagesAI[target.index][i][:dmg][user.index]#pbRoughDamage(j,target,user,skill,j.baseDamage)
					if tempdam>priodam
						prioppdam=tempdam 
						prioppmove=j
						prioppidx=i
					end	
				end 
				sleepcount = 1
				if prioppmove
					survivesprio = true
					survivesprio = targetSurvivesMove(prioppmove,prioppidx,target,user)
					sleepcount +=1 if !survivesprio
				end
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>sleepcount)
					score += 20
					score+= 60 if (target.status == :SLEEP && target.statusCount>1)
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						if (((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*1.5>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))) ||
							(targetSurvivesMove(maxownmove,maxownidx,attacker,target) && maxownmove.pbContactMove?(user) && 
								(
									target.hasActiveAbility?([:STATIC,:FLAMEBODY,:EFFECTSPORE,:POISONPOINT,:IRONBARBS,:ROUGHSKIN]) || target.hasActiveItem?(:ROCKYHELMET)
								)
							)
							score += 90 
						end

					end
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
				end
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:ATTACK]*10
				score -= user.stages[:SPEED]*10
				if skill>=PBTrainerAI.mediumSkill
					hasPhysicalAttack = false
					if user.hasActiveItem?(:ENCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.physicalMove?(m.type)
							hasPhysicalAttack = true
							break
						end
					end
					if hasPhysicalAttack
						score += 20
					elsif skill>=PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end
			
			#---------------------------------------------------------------------------
		when "RaiseUserAtk1Spd2"  # Shift Gear
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:ATTACK) &&
				user.statStageAtMax?(:SPEED)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 20
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score += 40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
					end
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
				end
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:ATTACK] * 10
				score -= user.stages[:SPEED] * 10
				if skill >= PBTrainerAI.mediumSkill
					hasPhysicalAttack = false
					if user.hasActiveItem?(:ENCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.physicalMove?(m.type)
							hasPhysicalAttack = true
							break
						end
					end
					if hasPhysicalAttack
						score += 20
					elsif skill >= PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end
			#---------------------------------------------------------------------------
		when "RaiseUserSpAtkSpDefSpd1"  # Quiver Dance
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:SPEED) &&
				user.statStageAtMax?(:SPECIAL_ATTACK) &&
				user.statStageAtMax?(:SPECIAL_DEFENSE)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				maxspec=(bestmove[3]=="special") 
				priodam=0
				priomove=nil
				user.moves.each_with_index do |j,i|
					next if priorityAI(user,j)<1
					if moveLocked(user)
						if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
							next if j.id!=user.lastMoveUsed
						end
					end		
					tempdam =  @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					if tempdam>priodam
						priodam=tempdam 
						priomove=j
					end	
				end 
				prioppdam=0
				prioppmove=nil
				prioppidx=0
				target.moves.each_with_index do |j,i|
					next if priorityAI(target,j)<1
					if moveLocked(target)
						if target.lastMoveUsed && target.pbHasMove?(target.lastMoveUsed)
							next if j.id!=target.lastMoveUsed
						end
					end		
					tempdam =  @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					if tempdam>priodam
						prioppdam=tempdam 
						prioppmove=j
						prioppidx=i
					end	
				end 
				sleepcount = 1
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
					sleepcount +=1
				elsif prioppmove
					survivesprio = true
					survivesprio = targetSurvivesMove(prioppmove,prioppidx,target,user)
					sleepcount +=1 if !survivesprio
				end
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>sleepcount)
					score += 20
					score+= 60 if (target.status == :SLEEP && target.statusCount>1)
					score+=20 if maxspec
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
					if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
						score += 20
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score += 40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*1.5>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
					end
				end
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:SPECIAL_ATTACK]*3
				score -= user.stages[:SPECIAL_DEFENSE]*3
				score -= user.stages[:SPEED]*3
				if skill>=PBTrainerAI.mediumSkill
					hasSpecicalAttack = false
					if user.hasActiveItem?(:PWCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.specialMove?(m.type)
							hasSpecicalAttack = true
							break
						end
					end
					if hasSpecicalAttack
						score += 20
					elsif skill>=PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end
						
		#---------------------------------------------------------------------------
		when "RaiseUserAtkDefSpd1"  # Victory Dance
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:SPEED) &&
				user.statStageAtMax?(:ATTACK) &&
				user.statStageAtMax?(:DEFENSE)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				maxspec=(bestmove[3]=="physical") 
				priodam=0
				priomove=nil
				user.moves.each_with_index do |j,i|
					next if priorityAI(user,j)<1
					if moveLocked(user)
						if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
							next if j.id!=user.lastMoveUsed
						end
					end		
					tempdam =  @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					if tempdam>priodam
						priodam=tempdam 
						priomove=j
					end	
				end 
				prioppdam=0
				prioppmove=nil
				prioppidx=0
				target.moves.each_with_index do |j,i|
					next if priorityAI(target,j)<1
					if moveLocked(target)
						if target.lastMoveUsed && target.pbHasMove?(target.lastMoveUsed)
							next if j.id!=target.lastMoveUsed
						end
					end		
					tempdam =  @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					if tempdam>priodam
						prioppdam=tempdam 
						prioppmove=j
						prioppidx=i
					end	
				end 
				sleepcount = 1
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
					sleepcount +=1
				elsif prioppmove
					survivesprio = true
					survivesprio = targetSurvivesMove(prioppmove,prioppidx,target,user)
					sleepcount +=1 if !survivesprio
				end
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>sleepcount)
					score += 20
					score+= 60 if (target.status == :SLEEP && target.statusCount>1)
					score+=20 if maxspec
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
					if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
						score += 20
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score += 40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*1.5>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
					end
				end
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:ATTACK]*3
				score -= user.stages[:DEFENSE]*3
				score -= user.stages[:SPEED]*3
				if skill>=PBTrainerAI.mediumSkill
					hasPhysicalAttack = false
					user.eachMove do |m|
						next if !m.physicalMove?(m.type)
						hasPhysicalAttack = true
						break
					end
					if hasPhysicalAttack
						score += 20
					elsif skill >= PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end
			
			#---------------------------------------------------------------------------
		when "RaiseUserSpAtkSpDef1"  # Calm Mind
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:SPECIAL_ATTACK) &&
				user.statStageAtMax?(:SPECIAL_DEFENSE)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				maxspec=(bestmove[3]=="special") 
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 40
					score+=20 if maxspec
					if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
						score += 20
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
					end
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:SPECIAL_ATTACK]*10
				score -= user.stages[:SPECIAL_DEFENSE]*10
				if skill>=PBTrainerAI.mediumSkill
					hasSpecicalAttack = false
					if user.hasActiveItem?(:PWCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.specialMove?(m.type)
							hasSpecicalAttack = true
							break
						end
					end
					if hasSpecicalAttack
						score += 20
					elsif skill>=PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end
			
			#---------------------------------------------------------------------------
		when "RaiseUserDefSpDef1"  # Cosmic Power
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:DEFENSE) &&
				user.statStageAtMax?(:SPECIAL_DEFENSE)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				hpchange=EndofTurnHPChanges(user,target,false,false,true)
				score += (hpchange -1) * 200
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 30
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
					if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
						score += 40
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) 
							#healorchip=user.totalhp*(1-hpchange)
							actualhp = thirdhealth + (user.totalhp * hpchange)
							if maxdam>actualhp
								score -= 90 
							else
								score += 60 if hpchange >= 1.1
							end
						end
					end
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:DEFENSE] * 10
				score -= user.stages[:SPECIAL_DEFENSE] * 10
			end
			#---------------------------------------------------------------------------
		when "UserAddStockpileRaiseDefSpDef1"  # Stockpile
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:DEFENSE) &&
				user.statStageAtMax?(:SPECIAL_DEFENSE)) || user.effects[PBEffects::Stockpile] >= 3 || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 30
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
					if target.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
						score += 40
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>thirdhealth
					end
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:DEFENSE] * 10
				score -= user.stages[:SPECIAL_DEFENSE] * 10
			end
			#---------------------------------------------------------------------------
		when "RaisePlusMinusUserAndAlliesAtkSpAtk1"  # Gear Up
			geared=false
			@battle.allSameSideBattlers(user.index).each do |b|
				next if !b.hasActiveAbility?(:PLUS) && !b.hasActiveAbility?(:MINUS)
				geared=true
			end
			if (user.statStageAtMax?(:ATTACK) &&
					user.statStageAtMax?(:SPECIAL_ATTACK)) || !geared || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				target=user.pbDirectOpposing(true)
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 40
					score += 20 if user.hasActiveAbility?(:SPEEDBOOST)
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
					end
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
					prio=false
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:ATTACK] * 10
				score -= user.stages[:SPECIAL_ATTACK] * 10
				if skill >= PBTrainerAI.mediumSkill
					hasDamagingAttack = false
					user.eachMove do |m|
						next if !m.damagingMove?
						hasDamagingAttack = true
						break
					end
					if hasDamagingAttack
						score += 20
					elsif skill >= PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end
			#---------------------------------------------------------------------------
		when "RaisePlusMinusUserAndAlliesDefSpDef1"  # Magnetic Flux
			geared=false
			@battle.allSameSideBattlers(user.index).each do |b|
				next if !b.hasActiveAbility?(:PLUS) && !b.hasActiveAbility?(:MINUS)
				geared=true
			end
			target=user.pbDirectOpposing(true)
			if (user.statStageAtMax?(:DEFENSE) &&
					user.statStageAtMax?(:SPECIAL_DEFENSE)) || !geared || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 30
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
					if target.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
						score += 40
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>thirdhealth
					end
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:DEFENSE] * 4
				score -= user.stages[:SPECIAL_DEFENSE] * 4
			end
			#-----------------------------------------------------------------
		when "RaiseUserDefense1", "RaiseUserDefense2"  # Iron Defense
			target=user.pbDirectOpposing(true)
			if move.statusMove?
				if user.statStageAtMax?(:DEFENSE) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					maxphys=(bestmove[3]=="physical") 
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						if maxphys
							score += 30
							score += 20 if halfhealth>maxdam
						end
						score += 40 if thirdhealth>maxdam
						if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
							score += 40
						end
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>thirdhealth
						end
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:DEFENSE] * 20
				end
			else
				score += 20 if user.stages[:DEFENSE] < 0
			end
			#---------------------------------------------------------------------------
		when "RaiseUserDefense3"
			target=user.pbDirectOpposing(true)
			if move.statusMove?
				if user.statStageAtMax?(:DEFENSE) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					maxphys=(bestmove[3]=="physical") 
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						if maxphys
							score += 40
							score += 20 if halfhealth>maxdam
						end
						score += 60 if thirdhealth>maxdam
						if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
							score += 40
						end
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>thirdhealth
						end
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score += 40 if user.turnCount == 0
					score -= user.stages[:DEFENSE] * 30
				end
			else
				score += 10 if user.turnCount == 0
				score += 30 if user.stages[:DEFENSE] < 0
			end
			#---------------------------------------------------------------------------
		when "RaiseUserSpDef1", "RaiseUserSpDef2", "RaiseUserSpDef3"  # Amnesia
			target=user.pbDirectOpposing(true)
			if move.statusMove?
				if user.statStageAtMax?(:SPECIAL_DEFENSE) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					maxspec=(bestmove[3]=="special") 
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						if maxspec
							score += 30
							score += 20 if halfhealth>maxdam
						end
						score += 60 if thirdhealth>maxdam
						if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
							score += 40
						end
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>thirdhealth
						end
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:SPECIAL_DEFENSE] * 20
				end
			else
				score += 20 if user.stages[:SPECIAL_DEFENSE] < 0
			end
			#---------------------------------------------------------------------------
		when "RaiseUserSpeed1", "HitTwoToFiveTimesRaiseUserSpd1LowerUserDef1"  # Flame Charge, Scale Shot
			target=user.pbDirectOpposing(true)
			if move.statusMove?
				if user.statStageAtMax?(:SPEED) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						#score += 40
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score += 100 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*1.5>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						end
						score += 40 if thirdhealth>maxdam
					end
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:SPEED] * 10
				end
			else #user.stages[:SPEED] < 0
				if !user.hasActiveAbility?(:CONTRARY)
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					# if canSleepTarget(user,target,true) && 
					# 	((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					# 	score-=50
					# end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						#score += 40
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score += 1000 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*1.5>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						end
						score += 40 if thirdhealth>maxdam
					end
					score-=500 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:SPEED] * 100
					score = 100 if score < 100
					score-=500 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				end
			end
			#---------------------------------------------------------------------------
		when "RaiseUserSpeed2", "RaiseUserSpeed2LowerUserWeight", "RaiseUserSpeed3" # Agility
			target=user.pbDirectOpposing(true)
			if move.statusMove?
				if user.statStageAtMax?(:SPEED) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					lowerspeed = false
					target.moves.each_with_index do |j,i|
						if ((["ParalyzeTargetIfNotTypeImmune","ParalyzeTarget"].include?(j.function) && 
							user.pbCanParalyze?(target, false,j)) ||
							(["LowerTargetSpeed2","LowerTargetSpeed1","LowerTargetSpeed1WeakerInGrassyTerrain",
							"PoisonTargetLowerTargetSpeed1","LowerTargetSpeed1MakeTargetWeakerToFire",
							"LowerTargetSpeedOverTime"].include?(j.function) && user.pbCanLowerStatStage?(:SPEED, target))) &&
							(j.statusMove? || j.addlEffect>=50)
							lowerspeed=true
						end
					end
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					aspeed /=2 if lowerspeed
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						#score += 40
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
								score += 130 
								if attacker.pbHasMoveFunction?("HitTwoTimesFlinchTarget") && attacker.hasActiveAbility?(:SERENEGRACE) && 
									((!target.hasActiveAbility?(:INNERFOCUS) && !target.hasActiveAbility?(:SHIELDDUST)) || mold_broken) &&
									target.effects[PBEffects::Substitute]==0
									score +=140 
								end
							end
						end
						score += 40 if thirdhealth>maxdam
					end
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:SPEED] * 10
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			else
				score += 20 if user.stages[:SPEED] < 0
			end
			#---------------------------------------------------------------------------
		when "RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun"  # Work Up, Growth
			if (user.statStageAtMax?(:ATTACK) &&
				user.statStageAtMax?(:SPECIAL_ATTACK)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				target=user.pbDirectOpposing(true)
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				lowerspeed = false
				target.moves.each_with_index do |j,i|
					if ((["ParalyzeTargetIfNotTypeImmune","ParalyzeTarget"].include?(j.function) && 
						user.pbCanParalyze?(target, false,j)) ||
						(["LowerTargetSpeed2","LowerTargetSpeed1","LowerTargetSpeed1WeakerInGrassyTerrain",
						"PoisonTargetLowerTargetSpeed1","LowerTargetSpeed1MakeTargetWeakerToFire",
						"LowerTargetSpeedOverTime"].include?(j.function) && user.pbCanLowerStatStage?(:SPEED, target))) &&
						(j.statusMove? || j.addlEffect>=50)
						lowerspeed=true
					end
				end
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				aspeed /=2 if lowerspeed
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 40
					score += 20 if user.hasActiveAbility?(:SPEEDBOOST)
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
					end
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
					prio=false
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:ATTACK] * 10
				score -= user.stages[:SPECIAL_ATTACK] * 10
				if skill >= PBTrainerAI.mediumSkill
					hasDamagingAttack = false
					user.eachMove do |m|
						next if !m.damagingMove?
						hasDamagingAttack = true
						break
					end
					if hasDamagingAttack
						score += 20
					elsif skill >= PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
				if move.function == "RaiseUserAtkSpAtk1Or2InSun"   # Growth
					score += 20 if [:Sun, :HarshSun, :HolyInferno].include?(user.effectiveWeather)
				end
			end
			#---------------------------------------------------------------------------
		when "RaiseUserAttack1"  # Howl
			if move.statusMove?
				if user.statStageAtMax?(:ATTACK) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					target=user.pbDirectOpposing(true)
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					lowerspeed = false
					target.moves.each_with_index do |j,i|
						if ((["ParalyzeTargetIfNotTypeImmune","ParalyzeTarget"].include?(j.function) && 
							user.pbCanParalyze?(target, false,j)) ||
							(["LowerTargetSpeed2","LowerTargetSpeed1","LowerTargetSpeed1WeakerInGrassyTerrain",
							"PoisonTargetLowerTargetSpeed1","LowerTargetSpeed1MakeTargetWeakerToFire",
							"LowerTargetSpeedOverTime"].include?(j.function) && user.pbCanLowerStatStage?(:SPEED, target))) &&
							(j.statusMove? || j.addlEffect>=50)
							lowerspeed=true
						end
					end
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					aspeed /=2 if lowerspeed
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						score += 40
						score += 20 if user.hasActiveAbility?(:SPEEDBOOST)
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
						end
						score += 20 if halfhealth>maxdam
						score += 40 if thirdhealth>maxdam
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:ATTACK] * 20
					if skill >= PBTrainerAI.mediumSkill
						hasPhysicalAttack = false
						if user.hasActiveItem?(:ENCONVERTER)
							hasPhysicalAttack = true
						else
							user.eachMove do |m|
								next if !m.physicalMove?(m.type)
								hasPhysicalAttack = true
								break
							end
						end
						if hasPhysicalAttack
							score += 20
						elsif skill >= PBTrainerAI.highSkill
							score -= 90
						end
						score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
					end
				end
			else
				score += 20 if user.stages[:ATTACK] < 0
				if skill >= PBTrainerAI.mediumSkill
					hasPhysicalAttack = false
					if user.hasActiveItem?(:ENCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.physicalMove?(m.type)
							hasPhysicalAttack = true
							break
						end
					end
					score += 20 if hasPhysicalAttack
				end
			end            
			#---------------------------------------------------------------------------
		when "RaiseUserAttack2"  # Swords Dance
			if move.statusMove?
				if user.statStageAtMax?(:ATTACK) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					target=user.pbDirectOpposing(true)
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					priodam=0
					priomove=nil
					prioidx=0
					user.moves.each_with_index do |j,i|
						next if priorityAI(user,j)<1
						if moveLocked(user)
							if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
								next if j.id!=user.lastMoveUsed
							end
						end		
						tempdam =  @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
						if tempdam>priodam
							priodam=tempdam 
								priomove=j
								prioidx=i
						end	
					end 
					prioppdam=0
					prioppmove=nil
					prioppidx=0
					lowerspeed=false
					target.moves.each_with_index do |j,i|
						if ((["ParalyzeTargetIfNotTypeImmune","ParalyzeTarget"].include?(j.function) && 
							user.pbCanParalyze?(target, false,j)) ||
							(["LowerTargetSpeed2","LowerTargetSpeed1","LowerTargetSpeed1WeakerInGrassyTerrain",
							"PoisonTargetLowerTargetSpeed1","LowerTargetSpeed1MakeTargetWeakerToFire",
							"LowerTargetSpeedOverTime"].include?(j.function) && user.pbCanLowerStatStage?(:SPEED, target))) &&
							(j.statusMove? || j.addlEffect>=50)
							lowerspeed=true
						end
						next if priorityAI(target,j)<1
						if moveLocked(target)
							if target.lastMoveUsed && target.pbHasMove?(target.lastMoveUsed)
								next if j.id!=target.lastMoveUsed
							end
						end		
						tempdam = @damagesAI[target.index][i][:dmg][user.index]#pbRoughDamage(j,target,user,skill,j.baseDamage)
						if tempdam>priodam
							prioppdam=tempdam 
							prioppmove=j
							prioppidx=i
						end	
					end 
					sleepcount = 1
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					aspeed /= 2 if lowerspeed
					if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						sleepcount +=1
					elsif prioppmove
						survivesprio = true
						survivesprio = targetSurvivesMove(prioppmove,prioppidx,target,user)
						sleepcount +=1 if !survivesprio
					end
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,user,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>sleepcount)
						score += 40
						score+= 60 if (target.status == :SLEEP && target.statusCount>1)
						score += 60 if user.hasActiveAbility?(:SPEEDBOOST)
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
								if priomove
									if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
										score+=80
									else	
										score -= 90 
									end
								else
									score -= 90 
								end
							else
								score+=80
							end
						end
						score += 20 if halfhealth>maxdam
						score += 40 if thirdhealth>maxdam
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:ATTACK]*20
					if skill>=PBTrainerAI.mediumSkill
						hasPhysicalAttack = false
						if user.hasActiveItem?(:ENCONVERTER)
							hasPhysicalAttack = true
						else
							user.eachMove do |m|
								next if !m.physicalMove?(m.type)
								hasPhysicalAttack = true
								break
							end
						end
						if hasPhysicalAttack
							score += 20
						elsif skill>=PBTrainerAI.highSkill
							score -= 90
						end
						score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
					end
				end
			else
				score += 10 if user.hp==user.totalhp
				score += 20 if user.stages[:ATTACK]<0
				if skill>=PBTrainerAI.mediumSkill
					hasPhysicalAttack = false
					if user.hasActiveItem?(:ENCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.physicalMove?(m.type)
							hasPhysicalAttack = true
							break
						end
					end
					score += 20 if hasPhysicalAttack
				end
			end
			
			#---------------------------------------------------------------------------
		when "RaiseUserAtkAcc1" # Hone Claws
			if (user.statStageAtMax?(:ATTACK) &&
				user.statStageAtMax?(:ACCURACY)) || user.hasActiveAbility?(:CONTRARY)
				score -= 200
			else
				target=user.pbDirectOpposing(true)
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxpriotype=bestmove[5]
				priodam=0
				priomove=nil
				prioidx=0
				user.moves.each_with_index do |j,i|
					next if priorityAI(user,j)<1
					if moveLocked(user)
						if user.lastMoveUsed && user.pbHasMove?(user.lastMoveUsed)
							next if j.id!=user.lastMoveUsed
						end
					end		
					tempdam =  @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					if tempdam>priodam
						priodam=tempdam 
						priomove=j
						prioidx=i
					end	
				end 
				halfhealth=(user.hp/2)
				thirdhealth=(user.hp/3)
				lowerspeed = false
				target.moves.each_with_index do |j,i|
					if ((["ParalyzeTargetIfNotTypeImmune","ParalyzeTarget"].include?(j.function) && 
						user.pbCanParalyze?(target, false,j)) ||
						(["LowerTargetSpeed2","LowerTargetSpeed1","LowerTargetSpeed1WeakerInGrassyTerrain",
						"PoisonTargetLowerTargetSpeed1","LowerTargetSpeed1MakeTargetWeakerToFire",
						"LowerTargetSpeedOverTime"].include?(j.function) && user.pbCanLowerStatStage?(:SPEED, target))) &&
						(j.statusMove? || j.addlEffect>=50)
						lowerspeed=true
					end
				end
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				aspeed /=2 if lowerspeed
				if canSleepTarget(user,target,true) && 
					((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score-=90
				end	
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 40
					score += 20 if user.hasActiveAbility?(:SPEEDBOOST)
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
							if priomove
								if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,2)
									score+=80
								else	
									score -= 90 
								end
							else
								score -= 90 
							end
						else
							score+=80
						end
					end
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
				end 
				score-=50 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
				score-=50 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				score -= user.stages[:ATTACK] * 10
				score -= user.stages[:ACCURACY] * 10
				if skill >= PBTrainerAI.mediumSkill
					hasPhysicalAttack = false
					if user.hasActiveItem?(:ENCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.physicalMove?(m.type)
							hasPhysicalAttack = true
							break
						end
					end
					if hasPhysicalAttack
						score += 20
					elsif skill >= PBTrainerAI.highSkill
						score -= 90
					end
					score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
				end
			end
			#---------------------------------------------------------------------------
		when "RaiseUserSpAtk2"  # Nasty Plot
			if move.statusMove?
				if user.statStageAtMax?(:SPECIAL_ATTACK) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					target=user.pbDirectOpposing(true)
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					priodam=0
					priomove=nil
					prioppidx=0
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
							prioppidx=i
						end	
					end 
					prioppdam=0
					prioppmove=nil
					prioppidx=0
					lowerspeed = false
					target.moves.each_with_index do |j,i|
						if ((["ParalyzeTargetIfNotTypeImmune","ParalyzeTarget"].include?(j.function) && 
							user.pbCanParalyze?(target, false,j)) ||
							(["LowerTargetSpeed2","LowerTargetSpeed1","LowerTargetSpeed1WeakerInGrassyTerrain",
							"PoisonTargetLowerTargetSpeed1","LowerTargetSpeed1MakeTargetWeakerToFire",
							"LowerTargetSpeedOverTime"].include?(j.function) && user.pbCanLowerStatStage?(:SPEED, target))) &&
							(j.statusMove? || j.addlEffect>=50)
							lowerspeed=true
						end
						next if priorityAI(target,j)<1
						if moveLocked(target)
							if target.lastMoveUsed && target.pbHasMove?(target.lastMoveUsed)
								next if j.id!=target.lastMoveUsed
							end
						end		
						tempdam = @damagesAI[target.index][i][:dmg][user.index]#pbRoughDamage(j,target,user,skill,j.baseDamage)
						if tempdam>priodam
							prioppdam=tempdam 
							prioppmove=j
							prioppidx=i
						end	
					end 
					sleepcount = 1
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					aspeed /= 2 if lowerspeed
					if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						sleepcount +=1
					elsif prioppmove
						survivesprio = true
						survivesprio = targetSurvivesMove(prioppmove,prioppidx,target,user)
						sleepcount +=1 if !survivesprio
					end
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>sleepcount)
						score += 40
						score+= 60 if (target.status == :SLEEP && target.statusCount>sleepcount) 
						score += 60 if user.hasActiveAbility?(:SPEEDBOOST)
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
								if priomove
									if targetSurvivesMove(priomove,prioppidx,user,target) && !targetSurvivesMove(priomove,prioppidx,user,target,0,2)
										score+=80
									else	
										score -= 90 
									end
								else
									score -= 90 
								end
							else
								score+=80
							end
						end
						score += 20 if halfhealth>maxdam
						score += 40 if thirdhealth>maxdam
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:SPECIAL_ATTACK]*20
					if skill>=PBTrainerAI.mediumSkill
						hasSpecicalAttack = false
						if user.hasActiveItem?(:PWCONVERTER)
							hasPhysicalAttack = true
						else
							user.eachMove do |m|
								next if !m.specialMove?(m.type)
								hasSpecicalAttack = true
								break
							end
						end
						if hasSpecicalAttack
							score += 20
						elsif skill>=PBTrainerAI.highSkill
							score -= 90
						end
						score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
					end
				end
			else
				score += 10 if user.turnCount==0
				score += 20 if user.stages[:SPECIAL_ATTACK]<0
				if skill>=PBTrainerAI.mediumSkill
					hasSpecicalAttack = false
					if user.hasActiveItem?(:PWCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.specialMove?(m.type)
							hasSpecicalAttack = true
							break
						end
					end
					score += 20 if hasSpecicalAttack
				end
			end
			
			#---------------------------------------------------------------------------
		when "RaiseUserSpAtk3" # Tail Glow
			if move.statusMove?
				if user.statStageAtMax?(:SPECIAL_ATTACK) || user.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					target=user.pbDirectOpposing(true)
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					lowerspeed = false
					target.moves.each_with_index do |j,i|
						if ((["ParalyzeTargetIfNotTypeImmune","ParalyzeTarget"].include?(j.function) && 
							user.pbCanParalyze?(target, false,j)) ||
							(["LowerTargetSpeed2","LowerTargetSpeed1","LowerTargetSpeed1WeakerInGrassyTerrain",
							"PoisonTargetLowerTargetSpeed1","LowerTargetSpeed1MakeTargetWeakerToFire",
							"LowerTargetSpeedOverTime"].include?(j.function) && user.pbCanLowerStatStage?(:SPEED, target))) &&
							(j.statusMove? || j.addlEffect>=50)
							lowerspeed=true
						end
					end
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					aspeed /=2 if lowerspeed
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						score += 40
						score += 20 if user.hasActiveAbility?(:SPEEDBOOST)
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
						end
						score += 20 if halfhealth>maxdam
						score += 40 if thirdhealth>maxdam
					end 
					score -= user.stages[:SPECIAL_ATTACK] * 30
					if skill >= PBTrainerAI.mediumSkill
						hasSpecicalAttack = false
						if user.hasActiveItem?(:PWCONVERTER)
							hasPhysicalAttack = true
						else
							user.eachMove do |m|
								next if !m.specialMove?(m.type)
								hasSpecicalAttack = true
								break
							end
						end
						if hasSpecicalAttack
							score += 20
						elsif skill >= PBTrainerAI.highSkill
							score -= 90
						end
					end
				end
			else
				score += 10 if user.turnCount == 0
				score += 30 if user.stages[:SPECIAL_ATTACK] < 0
				if skill >= PBTrainerAI.mediumSkill
					hasSpecicalAttack = false
					if user.hasActiveItem?(:PWCONVERTER)
						hasPhysicalAttack = true
					else
						user.eachMove do |m|
							next if !m.specialMove?(m.type)
							hasSpecicalAttack = true
							break
						end
					end
					score += 20 if hasSpecicalAttack
				end
			end       
			#---------------------------------------------------------------------------
		when "LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2" # Shell Smash
			target=user.pbDirectOpposing(true)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxprio=bestmove[2]
			maxpriotype=bestmove[5]
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			if user.hasActiveAbility?(:CONTRARY)
				score += user.stages[:ATTACK] * 20
				score += user.stages[:SPEED] * 20
				score += user.stages[:SPECIAL_ATTACK] * 20
				score -= user.stages[:DEFENSE] * 10
				score -= user.stages[:SPECIAL_DEFENSE] * 10
				if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
					score += 30
					score += 20 if halfhealth>maxdam
					score += 40 if thirdhealth>maxdam
					if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn", "HealUserFullyAndFallAsleep")   # Recover, Roost, Rest
						score += 40
					end
					if skill>=PBTrainerAI.highSkill
						aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
						ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
						score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>thirdhealth
					end
				end 
			else
				score -= user.stages[:ATTACK] * 20
				score -= user.stages[:SPEED] * 20
				score -= user.stages[:SPECIAL_ATTACK] * 20
				score += user.stages[:DEFENSE] * 10
				score += user.stages[:SPECIAL_DEFENSE] * 10
				if skill>=PBTrainerAI.mediumSkill
					hasDamagingAttack = false
					user.eachMove do |m|
						next if !m.damagingMove?
						hasDamagingAttack = true
						break
					end
					score += 20 if hasDamagingAttack
					mult=1
					mult=2 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && !user.hasActiveItem?(:WHITEHERB)
					maxdam*=mult
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,mult,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						score += 100-30*mult
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score += 40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						end
						score += 20 if halfhealth>(maxdam)
						score += 40 if thirdhealth>(maxdam)
					end
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				end	
			end    
			#---------------------------------------------------------------------------
		when "RaiseUserMainStats1LoseThirdOfTotalHP" # Clangorous Soul
			target=user.pbDirectOpposing(true)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxprio=bestmove[2]
			maxpriotype=bestmove[5]
			halfhealth=(user.hp/2)# - (user.totalhp/3)
			thirdhealth=(user.hp/3)# - (user.totalhp/3)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			if user.hasActiveAbility?(:CONTRARY)
			else
				score -= user.stages[:ATTACK] * 20
				score -= user.stages[:SPEED] * 20
				score -= user.stages[:SPECIAL_ATTACK] * 20
				score -= user.stages[:DEFENSE] * 10
				score -= user.stages[:SPECIAL_DEFENSE] * 10
				if skill>=PBTrainerAI.mediumSkill
					hasDamagingAttack = false
					user.eachMove do |m|
						next if !m.damagingMove?
						hasDamagingAttack = true
						break
					end
					score += 20 if hasDamagingAttack
					mult=1.5
					mult*=0.7 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					maxdam*=mult
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,mult,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						score += 100-30*mult
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score += 40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						end
						score += 20 if halfhealth>(maxdam)
						score += 40 if thirdhealth>(maxdam)
					end
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
				end	
			end    
			#---------------------------------------------------------------------------
			when "MaxUserAttackLoseHalfOfTotalHP" # Belly Drum 
				if user.statStageAtMax?(:ATTACK) ||
					user.hp <= user.totalhp / 2
					score -= 300
				else
					target=user.pbDirectOpposing(true)
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					priodam=0
					priomove=nil
					prioidx=0
					user.moves.each_with_index do |j,i|
						next if j.priority<1
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
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					mult=2
					mult=1.5 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && user.hasActiveItem?(:SITRUSBERRY)
					if targetSurvivesMove(maxmove,maxidx,target,user,maxprio,mult,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						score += 40
						score+= 60 if (target.status == :SLEEP && target.statusCount>1)
						score += 60 if user.hasActiveAbility?(:SPEEDBOOST)
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
								if priomove
									if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,4)
										score+=80
									else	
										score -= 90 
									end
								else
									score -= 90 
								end
							else
								score+=80
							end
						end
						score += 20 if halfhealth>maxdam
						score += 40 if thirdhealth>maxdam
					end 
					score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
					score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
					score -= user.stages[:ATTACK]*20
					if skill>=PBTrainerAI.mediumSkill
						hasPhysicalAttack = false
						if user.hasActiveItem?(:ENCONVERTER)
							hasPhysicalAttack = true
						else
							user.eachMove do |m|
								next if !m.physicalMove?(m.type)
								hasPhysicalAttack = true
								break
							end
						end
						if hasPhysicalAttack
							score += 20
						elsif skill>=PBTrainerAI.highSkill
							score -= 90
						end
						score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
					end
				end
				#---------------------------------------------------------------------------
				when "RaiseUserAtk2SpAtk2Speed2LoseHalfOfTotalHP" # Fillet Away
					if user.hp <= user.totalhp / 2
						score -= 300
					else
						target=user.pbDirectOpposing(true)
						maxdam=0
						maxidx=0
						maxmove=nil
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4]
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						maxpriotype=bestmove[5]
						priodam=0
						priomove=nil
						prioidx=0
						score -= user.stages[:ATTACK] * 20
						score -= user.stages[:SPEED] * 20
						score -= user.stages[:SPECIAL_ATTACK] * 20
						user.moves.each_with_index do |j,i|
							next if j.priority<1
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
						halfhealth=(user.hp/2)
						thirdhealth=(user.hp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							score-=90
						end	
						mult=2
						mult=1.5 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && user.hasActiveItem?(:SITRUSBERRY)
						if targetSurvivesMove(maxmove,maxidx,target,user,maxprio,mult,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
							score += 40
							score+= 60 if (target.status == :SLEEP && target.statusCount>1)
							score += 60 if user.hasActiveAbility?(:SPEEDBOOST)
							score += 40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
								if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && maxdam>halfhealth
									if priomove
										if targetSurvivesMove(priomove,prioidx,user,target) && !targetSurvivesMove(priomove,prioidx,user,target,0,4)
											score+=80
										else	
											score -= 90 
										end
									else
										score -= 90 
									end
								else
									score+=80
								end
							end
							score += 20 if halfhealth>maxdam
							score += 40 if thirdhealth>maxdam
						end 
						score=5 if target.pbHasMoveFunction?("UserCopyTargetStatStages","UserTargetSwapStatStages","UserStealTargetPositiveStatStages") # Psych Up, Heart Swap, Spectral Thief
						score=5 if target.pbHasMove?(:CLEARSMOG) && !user.pbHasType?(:STEEL) # Clear Smog
						score -= user.stages[:ATTACK]*20
						if skill>=PBTrainerAI.mediumSkill
							hasPhysicalAttack = false
							user.eachMove do |m|
								next if !m.physicalMove?(m.type)
								hasPhysicalAttack = true
								break
							end
							if hasPhysicalAttack
								score += 20
							elsif skill>=PBTrainerAI.highSkill
								score -= 90
							end
							score = 5 if target.num_fainted_allies == (@battle.pbParty(target.index).length - 1)
						end
					end
				#---------------------------------------------------------------------------
			when "LowerTargetSpDef2" # Acid Spray
				bestmove=bestMoveVsTarget(user,target,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				maxspec=(bestmove[3]=="special") 
				thirdhealth=(target.hp/3)
				score +=40 if maxspec && maxdam <= thirdhealth && !target.hasActiveAbility?(:CONTRARY) && !target.statStageAtMin?(:SPECIAL_DEFENSE)
				#---------------------------------------------------------------------------
				when "LowerTargetAttack2", "LowerTargetAttack3" # Charm, Featherdance
					if !target.pbCanLowerStatStage?(:ATTACK, user) || target.hasActiveAbility?(:CONTRARY)
						score -= 200
					else
						maxdam=0
						maxidx=0
						maxmove=nil
						bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
						maxdam=bestmove[0] 
						maxidx=bestmove[4]
						maxmove=bestmove[1]
						maxprio=bestmove[2]
						maxphys=(bestmove[3]=="physical") 
						halfhealth=(user.hp/2)
						thirdhealth=(user.hp/3)
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(target,:SPEED,skill)
						if canSleepTarget(user,target,true) && 
							((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							score-=90
						end	
						if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio) || (target.status == :SLEEP && target.statusCount>1)
							if maxphys
								score += 30
								score += 30 if halfhealth>maxdam
								score += 40 if thirdhealth>maxdam
								if user.pbHasMoveFunction?("HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn")   # Recover, Roost
									score += 40
								end
							end
							if skill>=PBTrainerAI.highSkill
								aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
								ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
								score -= 90 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>thirdhealth
							end
						end 
						score += target.stages[:ATTACK] * 40
					end
			#---------------------------------------------------------------------------
		when "LowerTargetSpeed1", "LowerTargetSpeed1WeakerInGrassyTerrain"
			target=user.pbDirectOpposing(true)
			if move.statusMove?
				if !target.pbCanLowerStatStage?(:SPEED, user) || target.hasActiveAbility?(:CONTRARY)
					score -= 200
				else
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					if canSleepTarget(user,target,true) && 
						((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score-=90
					end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						#score += 40
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score += 100 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*1.5>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						end
						score += 40 if thirdhealth>maxdam
					end
					score += target.stages[:ATTACK] * 40
				end
			else 
				if !target.hasActiveAbility?(:CONTRARY)
					maxdam=0
					maxidx=0
					maxmove=nil
					bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] 
					maxidx=bestmove[4]
					maxmove=bestmove[1]
					maxprio=bestmove[2]
					maxpriotype=bestmove[5]
					halfhealth=(user.hp/2)
					thirdhealth=(user.hp/3)
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					# if canSleepTarget(user,target,true) && 
					# 	((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					# 	score-=50
					# end	
					if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio,1,1,maxpriotype) || (target.status == :SLEEP && target.statusCount>1)
						#score += 40
						if skill>=PBTrainerAI.highSkill
							aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
							ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
							score += 1000 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*1.5>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
						end
						score += 40 if thirdhealth>maxdam
					end
					score -= target.stages[:SPEED] * 400
					score = 100 if score < 100
				else
					score -= 500
				end
			end
			#---------------------------------------------------------------------------
		when "CounterPhysicalDamage"  # Counter
			target=user.pbDirectOpposing(true)
			if target.effects[PBEffects::HyperBeam] > 0
				score -= 90
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxphys=(bestmove[3]=="physical") 
				maxowndam=0
				user.moves.each_with_index do |j,i|
					tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					maxowndam=tempdam if tempdam>maxowndam
				end 
				maxowndam=target.hp if maxowndam>target.hp
				counterdam=0
				counterdam=maxdam*2 if maxphys
				counterdam=target.hp if counterdam>target.hp
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if maxphys && targetSurvivesMove(maxmove,maxidx,target,attacker)
					damagePercentage = counterdam * 100.0 / target.hp
					damagePercentage=110 if damagePercentage>target.hp
					score+=damagePercentage
				end
				if maxowndam>=counterdam
					score-=90
				else
					score += 30 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				end   
				score-=200 if pbAIRandom(100) < 50
			end
			#---------------------------------------------------------------------------
		when "CounterSpecialDamage"  # Mirror Coat
			target=user.pbDirectOpposing(true)
			if target.effects[PBEffects::HyperBeam] > 0
				score -= 90
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxspec=(bestmove[3]=="special") 
				maxowndam=0
				user.moves.each_with_index do |j,i|
					tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					maxowndam=tempdam if tempdam>maxowndam
				end 
				maxowndam=target.hp if maxowndam>target.hp
				counterdam=0
				counterdam=maxdam*2 if maxspec
				counterdam=target.hp if counterdam>target.hp
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if maxspec && targetSurvivesMove(maxmove,maxidx,target,attacker)
					damagePercentage = counterdam * 100.0 / target.hp
					damagePercentage=110 if damagePercentage>target.hp
					score+=damagePercentage
				end
				if maxowndam>=counterdam
					score-=90
				else
					score += 30 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				end   
				score-=200 if pbAIRandom(100) < 50
			end  
			#---------------------------------------------------------------------------
		when "CounterDamagePlusHalf"  # Metal Burst
			target=user.pbDirectOpposing(true)
			if target.effects[PBEffects::HyperBeam] > 0
				score -= 90
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxowndam=0
				user.moves.each_with_index do |j,i|
					tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					maxowndam=tempdam if tempdam>maxowndam
				end 
				maxowndam=target.hp if maxowndam>target.hp
				counterdam=0
				counterdam=maxdam*1.5
				counterdam=target.hp if counterdam>target.hp
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if targetSurvivesMove(maxmove,maxidx,target,attacker)
					damagePercentage = counterdam * 100.0 / target.hp
					damagePercentage=110 if damagePercentage>target.hp
					score+=damagePercentage
				end
				if maxowndam>=counterdam
					score-=90
				else
					if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score += 30 
					else  
						score-=90
					end        
				end  
				score=5 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score-=200 if pbAIRandom(100) < 50
			end   
			#---------------------------------------------------------------------------
		when "MultiTurnAttackBideThenReturnDoubleDamage"  # Bide
			target=user.pbDirectOpposing(true)
			if target.effects[PBEffects::HyperBeam] > 0
				score -= 90
			else
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxowndam=0
				user.moves.each_with_index do |j,i|
					tempdam = @damagesAI[user.index][i][:dmg][target.index]#pbRoughDamage(j,user,target,skill,j.baseDamage)
					maxowndam=tempdam if tempdam>maxowndam
				end 
				maxowndam=target.hp if maxowndam>target.hp
				counterdam=0
				counterdam=maxdam*2
				counterdam=target.hp if counterdam>target.hp
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				if targetSurvivesMove(maxmove,maxidx,target,attacker,0,2)
					damagePercentage = counterdam * 100.0 / target.hp
					damagePercentage=110 if damagePercentage>target.hp
					score+=damagePercentage
				end
				if maxowndam>=counterdam
					score-=90
				else
					score += 30 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				end   
				score-=200 if pbAIRandom(100) < 50
			end       
			#---------------------------------------------------------------------------
		when "UseRandomUserMoveIfAsleep"   # Sleep Talk
			if (user.asleep? && user.statusCount>1) || (user.hasActiveAbility?(:COMATOSE) && user.pbHasMoveFunction?("FailsIfUserHasUnusedMove"))
				score += 150   # Because it can only be used while asleep
			else
				score -= 90
			end 
			#---------------------------------------------------------------------------
			# when "FailsIfUserHasUnusedMove" # Last Resort
			#       hasThisMove = false
			#       hasOtherMoves = false
			#       hasUnusedMoves = false
			#       user.eachMove do |m|
			#         hasThisMove    = true if m.id == @id
			#         hasOtherMoves  = true if m.id != @id
			#         hasUnusedMoves = true if m.id != @id && !user.movesUsed.include?(m.id)
			#       end
			#       if !hasThisMove || !hasOtherMoves || hasUnusedMoves
			#         score=0
			#       end
			#---------------------------------------------------------------------------
		when "SwitchOutTargetStatusMove" # Whirlwind
			if target.effects[PBEffects::Ingrain] ||
				(skill>=PBTrainerAI.highSkill && target.hasActiveAbility?(:SUCTIONCUPS))
				score -= 90
			else
				ch = 0
				@battle.pbParty(target.index).each_with_index do |pkmn,i|
					ch += 1 if @battle.pbCanSwitchLax?(target.index,i)
				end
				score -= 90 if ch==0
			end
			if score>20
				score += 50 if target.pbOwnSide.effects[PBEffects::Spikes]>0
				score += 50 if target.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
				score += 50 if target.pbOwnSide.effects[PBEffects::StealthRock]
				@battle.allOtherSideBattlers(user.index).each do |b|
					if b.hasActiveAbility?(:WONDERGUARD) &&
						(user.pbOpposingSide.effects[PBEffects::StealthRock] ||
							user.pbOpposingSide.effects[PBEffects::ToxicSpikes] >0
							user.pbOpposingSide.effects[PBEffects::Spikes] >0)	
						score+=50
					end	
				end	
			end
			#---------------------------------------------------------------------------
			when "SwitchOutTargetDamagingMove" # Dragon tail
				if target.effects[PBEffects::Ingrain] ||
					(skill>=PBTrainerAI.highSkill && target.hasActiveAbility?([:SUCTIONCUPS, :GUARDDOG]))
					score -= 1000
				else
					ch = 0
					@battle.pbParty(target.index).each_with_index do |pkmn,i|
						ch += 1 if @battle.pbCanSwitchLax?(target.index,i)
					end
					score -= 1000 if ch==0
				end
				if score>20
					score += 1000 if target.pbOwnSide.effects[PBEffects::Spikes]>0
					score += 1000 if target.pbOwnSide.effects[PBEffects::ToxicSpikes]>0
					score += 1000 if target.pbOwnSide.effects[PBEffects::StealthRock]
					@battle.allOtherSideBattlers(user.index).each do |b|
						if b.hasActiveAbility?(:WONDERGUARD) &&
							(user.pbOpposingSide.effects[PBEffects::StealthRock] ||
								user.pbOpposingSide.effects[PBEffects::ToxicSpikes] >0
								user.pbOpposingSide.effects[PBEffects::Spikes] >0)	
							score+=1000
						end	
					end	
				end
			#---------------------------------------------------------------------------
		when "SetTargetTypesToWater" # Soak
			if target.effects[PBEffects::Substitute]>0 || !target.canChangeType?
				score -= 90
			elsif !target.pbHasOtherType?(:WATER)
				score -= 90
			end
			score+=60 if target.hasActiveAbility?(:WONDERGUARD)
			#---------------------------------------------------------------------------
		when "StartDamageTargetEachTurnIfTargetAsleep" # Nightmare
			if target.effects[PBEffects::Nightmare] ||
				target.effects[PBEffects::Substitute]>0
				score -= 90
			elsif !target.asleep?
				score -= 90
			else
				score -= 90 if target.statusCount<=1
				score +=50 if target.statusCount>1
			end
			#---------------------------------------------------------------------------
		when "NegateTargetAbility" # Gastro Acid
			if target.effects[PBEffects::Substitute]>0 ||
				target.effects[PBEffects::GastroAcid]
				score -= 200
			elsif skill>=PBTrainerAI.highSkill
				score+=50 if target.hasActiveAbility?(:WONDERGUARD)
				score -= 90 if target.unstoppableAbility? || target.hasActiveItem?(:ABILITYSHIELD)
			end
			#---------------------------------------------------------------------------
		when "AddSpikesToFoeSide" # Spikes
			target=user.pbDirectOpposing(true)
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			denier=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				if b.effects[PBEffects::MagicCoat] || b.hasActiveAbility?(:MAGICBOUNCE) ||
					(b.pbHasMoveFunction?("RemoveUserBindingAndEntryHazards") && !user.pbHasType?(:GHOST)) ||
					b.pbHasMoveFunction?("LowerTargetEvasion1RemoveSideEffects","BounceBackProblemCausingStatusMoves") 
					denier=true
				end
			end    
			if user.pbOpposingSide.effects[PBEffects::Spikes] >= 3 || denier
				score -= 90
			elsif user.allOpposing.none? { |b| @battle.pbCanChooseNonActive?(b.index) }
				score -= 90   # Opponent can't switch in any Pokemon
			else
				party = @battle.pbParty(target.index)
				inBattleIndices = @battle.allSameSideBattlers(target.index).map { |b| b.pokemonIndex }
				count = 0
				party.each_with_index do |pkmn, idxParty|
					next if !pkmn || !pkmn.able?
					next if inBattleIndices.include?(idxParty)
					next if pkmn.ability == :MAGICGUARD || pkmn.isAirborne? || pkmn.item == :HEAVYDUTYBOOTS 
					count += 1
					count += 1 if (pkmn.item == :FOCUSSASH || pkmn.ability == :STURDY || pkmn.ability == :WONDERGUARD) && 
					user.pbOpposingSide.effects[PBEffects::Spikes]==0
					count =0 if pkmn.ability == :MAGICBOUNCE
				end
				score += [15, 10, 5][user.pbOpposingSide.effects[PBEffects::Spikes]] * count
			end
			#---------------------------------------------------------------------------
		when "AddToxicSpikesToFoeSide" # Toxic Spikes
			target=user.pbDirectOpposing(true)
			denier=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				if b.effects[PBEffects::MagicCoat] || b.hasActiveAbility?(:MAGICBOUNCE) ||
					(b.pbHasMoveFunction?("RemoveUserBindingAndEntryHazards") && !user.pbHasType?(:GHOST)) ||
					b.pbHasMoveFunction?("LowerTargetEvasion1RemoveSideEffects","BounceBackProblemCausingStatusMoves") 
					denier=true
				end
			end    
			if user.pbOpposingSide.effects[PBEffects::ToxicSpikes] >= 2 || denier
				score -= 90
			elsif user.allOpposing.none? { |b| @battle.pbCanChooseNonActive?(b.index) }
				score -= 90  # Opponent can't switch in any Pokemon
			else
				party = @battle.pbParty(target.index)
				inBattleIndices = @battle.allSameSideBattlers(target.index).map { |b| b.pokemonIndex }
				count = 0
				party.each_with_index do |pkmn, idxParty|
					next if !pkmn || !pkmn.able?
					next if inBattleIndices.include?(idxParty)
					next if pkmn.ability == :MAGICGUARD || pkmn.ability == :IMMUNITY || pkmn.isAirborne? || pkmn.item == :HEAVYDUTYBOOTS || 
					pkmn.status != :NONE || pkmn.hasType?(:STEEL)
					if pkmn.hasType?(:POISON) || pkmn.ability == :POISONHEAL || pkmn.ability == :GUTS || pkmn.ability == :TOXICBOOST
						count-=1
					elsif pkmn.ability == :MAGICBOUNCE
						count=0
					else  
						count += 1
						count += 1 if (pkmn.item == :FOCUSSASH || pkmn.ability == :STURDY || pkmn.ability == :WONDERGUARD) && 
						user.pbOpposingSide.effects[PBEffects::ToxicSpikes]==0
					end 
				end
				count=0 if count<0
				score += [15, 5][user.pbOpposingSide.effects[PBEffects::ToxicSpikes]] * count
			end
			#---------------------------------------------------------------------------
		when "AddStealthRocksToFoeSide" # Stealth Rock
			target=user.pbDirectOpposing(true)
			denier=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				if b.effects[PBEffects::MagicCoat] || b.hasActiveAbility?(:MAGICBOUNCE) ||
					(b.pbHasMoveFunction?("RemoveUserBindingAndEntryHazards") && !user.pbHasType?(:GHOST)) ||
					b.pbHasMoveFunction?("LowerTargetEvasion1RemoveSideEffects","BounceBackProblemCausingStatusMoves") 
					denier=true
				end
			end    
			if user.pbOpposingSide.effects[PBEffects::StealthRock] || denier
				score -= 200
			elsif user.allOpposing.none? { |b| @battle.pbCanChooseNonActive?(b.index) }
				score -= 200   # Opponent can't switch in any Pokemon
			else
				party = @battle.pbParty(target.index)
				inBattleIndices = @battle.allSameSideBattlers(target.index).map { |b| b.pokemonIndex }
				count = 0
				party.each_with_index do |pkmn, idxParty|
					next if !pkmn || !pkmn.able?
					next if inBattleIndices.include?(idxParty)
					next if pkmn.ability == :MAGICGUARD || pkmn.item == :HEAVYDUTYBOOTS
					count += 1
					count += 1 if pkmn.item == :FOCUSSASH || pkmn.ability == :STURDY || pkmn.ability == :WONDERGUARD ||
					(pkmn.hasType?(:FIRE) && (pkmn.hasType?(:ICE) || pkmn.hasType?(:BUG) || pkmn.hasType?(:FLYING))) || 
					(pkmn.hasType?(:ICE) &&  (pkmn.hasType?(:BUG) || pkmn.hasType?(:FLYING))) || 
					(pkmn.hasType?(:BUG) && pkmn.hasType?(:FLYING)) 
					count +=3 if pkmn.ability == :WONDERGUARD
					count =0 if pkmn.ability == :MAGICBOUNCE
				end
				score += 15 * count
				@battle.allOtherSideBattlers(user.index).each do |b|
					score+=40 if b.hasActiveAbility?(:WONDERGUARD)
				end	
			end
			#---------------------------------------------------------------------------
		when "AddStickyWebToFoeSide" # Sticky Web
			target=user.pbDirectOpposing(true)
			denier=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				if b.effects[PBEffects::MagicCoat] || b.hasActiveAbility?(:MAGICBOUNCE) ||
					(b.pbHasMoveFunction?("RemoveUserBindingAndEntryHazards") && !user.pbHasType?(:GHOST)) ||
					b.pbHasMoveFunction?("LowerTargetEvasion1RemoveSideEffects","BounceBackProblemCausingStatusMoves") 
					denier=true
				end
			end    
			if user.pbOpposingSide.effects[PBEffects::StickyWeb] || denier
				score -= 95
			elsif user.allOpposing.none? { |b| @battle.pbCanChooseNonActive?(b.index) }
				score -= 95   # Opponent can't switch in any Pokemon
			else
				maxownspeed=0
				ownparty = @battle.pbParty(user.index)
				ownparty.each_with_index do |pkmn, idxParty|
					maxownspeed = pkmn.speed if pkmn.speed>maxownspeed
				end
				party = @battle.pbParty(target.index)
				inBattleIndices = @battle.allSameSideBattlers(target.index).map { |b| b.pokemonIndex }
				count = 0
				party.each_with_index do |pkmn, idxParty|
					next if !pkmn || !pkmn.able?
					next if inBattleIndices.include?(idxParty)
					next if pkmn.item == :HEAVYDUTYBOOTS || pkmn.ability == :CLEARBODY || pkmn.ability == :FULLMETALBODY
					if pkmn.ability == :CONTRARY || pkmn.ability == :DEFIANT || pkmn.ability == :COMPETITIVE
						count-=1
					elsif pkmn.ability == :MAGICBOUNCE
						count=0
					else  
						count += 1
						count += 1 if pkmn.speed>=maxownspeed
					end 
				end
				score += 22 * count
			end
			
			#---------------------------------------------------------------------------
		when "StartWeakenPhysicalDamageAgainstUserSide" # Reflect
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxphys=(bestmove[3]=="physical") 
			antifishious=false
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxphys &&
				user.hasActiveAbility?(:PRANKSTER) && maxmove.function == "DoublePowerIfTargetNotActed"
				antifishious = true
			end
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=40 if user.hasActiveItem?(:LIGHTCLAY)
			party = @battle.pbParty(user.index)
			count = 0
			party.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				count +=1
			end
			if @battle.pbSideSize(user.index)>1
				score += 20*count
			else
				score += 5*count
			end
			if maxphys || user.hasActiveItem?(:LIGHTCLAY)
				score+=40 if halfhealth>maxdam
				mult = 0.5
				mult = 0.25 if antifishious
				score+=60 if !targetSurvivesMove(maxmove,maxidx,target,user) && targetSurvivesMove(maxmove,maxidx,target,user,0,mult)
				score+=60
				score+=10 if maxphys
				if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score -= 50 if maxdam>thirdhealth
				else
					halfdam=maxdam/2
					score+=40 if halfdam<user.hp
				end     
			end 
			if canSleepTarget(user,target,true) && 
				((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score-=90
			end	
			score-=90 if target.pbHasMoveFunction?("StealAndUseBeneficialStatusMove", "RemoveScreens", "LowerTargetEvasion1RemoveSideEffects") || 
			(target.pbHasMoveFunction?("DisableTargetStatusMoves") && aspeed<ospeed)
			score = 5 if user.pbOwnSide.effects[PBEffects::Reflect] > 0 || user.pbOwnSide.effects[PBEffects::AuroraVeil] > 1
			
			#---------------------------------------------------------------------------
		when "StartWeakenSpecialDamageAgainstUserSide" # Light Screen
			score = 5 if user.pbOwnSide.effects[PBEffects::LightScreen] > 0 || user.pbOwnSide.effects[PBEffects::AuroraVeil] > 1
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxspec=(bestmove[3]=="special") 
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=40 if user.hasActiveItem?(:LIGHTCLAY)
			party = @battle.pbParty(user.index)
			count = 0
			party.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				count +=1
			end
			if @battle.pbSideSize(user.index)>1
				score += 20*count
			else
				score += 5*count
			end
			if maxspec || user.hasActiveItem?(:LIGHTCLAY)
				score+=40 if halfhealth>maxdam
				score+=60 if !targetSurvivesMove(maxmove,maxidx,target,user) && targetSurvivesMove(maxmove,maxidx,target,user,0,0.5)
				score+=60
				score+=10 if maxspec
				if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					score -= 50 if maxdam>thirdhealth
				else
					halfdam=maxdam/2
					score+=40 if halfdam<user.hp
				end     
			end 
			if canSleepTarget(user,target,true) && 
				((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score-=90
			end	
			score-=90 if target.pbHasMoveFunction?("StealAndUseBeneficialStatusMove", "RemoveScreens", "LowerTargetEvasion1RemoveSideEffects") || 
			(target.pbHasMoveFunction?("DisableTargetStatusMoves") && aspeed<ospeed)
			score = 5 if user.pbOwnSide.effects[PBEffects::LightScreen] > 0 || user.pbOwnSide.effects[PBEffects::AuroraVeil] > 1
			#---------------------------------------------------------------------------
		when "StartWeakenDamageAgainstUserSideIfHail" # Aurora Veil
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=40 if user.hasActiveItem?(:LIGHTCLAY)
			score+=40 if halfhealth>maxdam
			party = @battle.pbParty(user.index)
			count = 0
			party.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				count +=1
			end
			#if @battle.pbSideSize(user.index)>1
				score += 30*count
			# else
			# 	score += 10*count
			# end
			score+=60 if !targetSurvivesMove(maxmove,maxidx,target,user) && targetSurvivesMove(maxmove,maxidx,target,user,0,0.5)
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			else
				halfdam=maxdam/2
				score+=80 if halfdam<user.hp
			end    
			if canSleepTarget(user,target,true) && 
				((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score-=90
			end	
			score-=90 if target.pbHasMoveFunction?("StealAndUseBeneficialStatusMove", "RemoveScreens", "LowerTargetEvasion1RemoveSideEffects") || 
			(target.pbHasMoveFunction?("DisableTargetStatusMoves") && aspeed<ospeed)
			score =5 if user.pbOwnSide.effects[PBEffects::AuroraVeil] > 0 || 
						![:Hail, :FreezingRain, :FrozenStorm].include?(user.effectiveWeather) || 
						(user.pbOwnSide.effects[PBEffects::Reflect] > 1 && user.pbOwnSide.effects[PBEffects::LightScreen] > 1)
			#---------------------------------------------------------------------------
		when "StartSunWeather" # Sunny Day
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			#ospeed = pbRoughStat(target,:SPEED,skill)
			ospeed=0
			@battle.allSameSideBattlers(target.index).each do |b|
				espeed = pbRoughStat(b,:SPEED,skill)
				espeed*=1.5 if b.hasActiveAbility?(:SPEEDBOOST)
				ospeed=espeed if espeed>ospeed
			end
			maxdam=0
			water=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				b.moves.each_with_index do |j,i|
					if moveLocked(b)
						if b.lastMoveUsed && b.pbHasMove?(b.lastMoveUsed)
							next if j.id!=b.lastMoveUsed
						end
					end	
					tempdam = @damagesAI[b.index][i][:dmg][user.index]#pbRoughDamage(j,b,user,skill,j.baseDamage)
					if tempdam>maxdam
						maxdam=tempdam 
						water= (j.type==:WATER)
					end    
				end 
			end   
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=30 if user.hasActiveItem?(:HEATROCK)
			score+=30 if halfhealth>maxdam || (target.status == :SLEEP && target.statusCount>1)
			score+=40 if water && ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			end
			if ![:None, :Sun, :HarshSun, :HolyInferno, :FrozenStorm, :HeavyRain].include?(@battle.pbWeather)
				score+=20
			end
			score+=10 if user.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun")
			score+=20 if user.pbHasMoveFunction?("TwoTurnAttackOneTurnInSun")
			user.eachMove do |m|
				next if !m.damagingMove? || m.type != :FIRE
				score += 20
			end    
			if user.hasActiveAbility?(:CHLOROPHYLL)
				score+=30
				score+=40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
			end    
			score+=20 if user.hasActiveAbility?(:FLOWERGIFT) || user.hasActiveAbility?(:SOLARPOWER) || user.hasActiveAbility?(:PROTOSYNTHESIS)
			score-=50 if user.hasActiveAbility?(:DRYSKIN)
			ownparty = @battle.pbParty(user.index)
			inBattleIndices = @battle.allSameSideBattlers(user.index).map { |b| b.pokemonIndex }
			ownparty.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				next if inBattleIndices.include?(idxParty)
				score+=40 if pkmn.ability == :CHLOROPHYLL
				score+=20 if pkmn.ability == :FLOWERGIFT || pkmn.ability == :SOLARPOWER || pkmn.ability == :PROTOSYNTHESIS
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :FIRE
					score += 20
				end   
				score-=10 if user.pbHasMoveFunction?("TwoTurnAttackChargeRaiseUserSpAtk1OneTurnInRain") && (@battle.pbWeather == :Rain || @battle.pbWeather == :FreezingRain)
				score+=10 if pkmn.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun")
				score+=20 if pkmn.pbHasMoveFunction?("TwoTurnAttackOneTurnInSun") 
			end
			party = @battle.pbParty(target.index)
			party.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				if pkmn.ability == :SWIFTSWIM && [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(@battle.pbWeather)
					score+=40
				end 
				if (pkmn.ability == :SLUSHRUSH && (@battle.pbWeather == :Hail || @battle.pbWeather == :FreezingRain)) || (pkmn.ability == :SANDRUSH && @battle.pbWeather == :Sandstorm)
					score+=20
				end 
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :WATER
					score += 20
				end    
			end
			if @battle.pbCheckGlobalAbility(:AIRLOCK) ||
				@battle.pbCheckGlobalAbility(:CLOUDNINE) || @battle.field.effects[PBEffects::ClearFlute]>0
				score -=200
			elsif [:Sun, :HeavyRain, :FrozenStorm, :HarshSun, :HolyInferno].include?(@battle.pbWeather)
				score -=200
			end
			#---------------------------------------------------------------------------
		when "StartRainWeather"  # Rain Dance
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			#ospeed = pbRoughStat(target,:SPEED,skill)
			ospeed=0
			@battle.allSameSideBattlers(target.index).each do |b|
				espeed = pbRoughStat(b,:SPEED,skill)
				espeed*=1.5 if b.hasActiveAbility?(:SPEEDBOOST)
				ospeed=espeed if espeed>ospeed
			end
			maxdam=0
			fire=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				b.moves.each_with_index do |j,i|
					if moveLocked(b)
						if b.lastMoveUsed && b.pbHasMove?(b.lastMoveUsed)
							next if j.id!=b.lastMoveUsed
						end
					end	
					tempdam = @damagesAI[b.index][i][:dmg][user.index]#pbRoughDamage(j,b,user,skill,j.baseDamage)
					if tempdam>maxdam
						maxdam=tempdam 
						fire= (j.type==:FIRE)
					end    
				end 
			end   
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=30 if user.hasActiveItem?(:DAMPROCK)
			score+=30 if halfhealth>maxdam || (target.status == :SLEEP && target.statusCount>1)
			score+=40 if fire && ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			end
			if ![:None, :Rain, :HeavyRain, :FreezingRain, :FrozenStorm, :HarshSun, :HolyInferno].include?(@battle.pbWeather)
				score+=20
			end
			score-=20 if user.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun") && @battle.pbWeather == :Sun
			score+=10 if user.pbHasMoveFunction?("ParalyzeTargetAlwaysHitsInRainHitsTargetInSky")
			score+=20 if user.pbHasMoveFunction?("TwoTurnAttackChargeRaiseUserSpAtk1OneTurnInRain")
			user.eachMove do |m|
				next if !m.damagingMove? || m.type != :WATER
				score += 20
			end    
			if user.hasActiveAbility?(:SWIFTSWIM)
				score+=30
				score+=40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
			end    
			score+=20 if user.hasActiveAbility?(:RAINDISH) || user.hasActiveAbility?(:DRYSKIN) || user.hasActiveAbility?(:HYDRATION)
			ownparty = @battle.pbParty(user.index)
			inBattleIndices = @battle.allSameSideBattlers(user.index).map { |b| b.pokemonIndex }
			ownparty.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				next if inBattleIndices.include?(idxParty)
				score+=40 if pkmn.ability == :SWIFTSWIM
				score+=20 if pkmn.ability == :RAINDISH || pkmn.ability == :DRYSKIN || pkmn.ability == :HYDRATION
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :WATER
					score += 20
				end   
				score-=10 if pkmn.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun") && @battle.pbWeather == :Sun
				score+=10 if pkmn.pbHasMoveFunction?("ParalyzeTargetAlwaysHitsInRainHitsTargetInSky") 
				score+=20 if user.pbHasMoveFunction?("TwoTurnAttackChargeRaiseUserSpAtk1OneTurnInRain")
			end
			party = @battle.pbParty(target.index)
			party.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				if pkmn.ability == :CHLOROPHYLL && @battle.pbWeather == :Sun
					score+=40
				end 
				if (pkmn.ability == :SLUSHRUSH && [:Hail, :FreezingRain].include?(@battle.pbWeather)) || 
					(pkmn.ability == :SANDRUSH && @battle.pbWeather == :Sandstorm)
					score+=20
				end 
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :FIRE
					score += 20
				end    
			end
			if @battle.pbCheckGlobalAbility(:AIRLOCK) ||
				@battle.pbCheckGlobalAbility(:CLOUDNINE) || @battle.field.effects[PBEffects::ClearFlute]>0
				score -=200
			elsif [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm, :HarshSun, :HolyInferno].include?(@battle.pbWeather)
				score -=200
			end
			#---------------------------------------------------------------------------
		when "StartSandstormWeather"  # Sandstorm
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			#ospeed = pbRoughStat(target,:SPEED,skill)
			ospeed=0
			@battle.allSameSideBattlers(target.index).each do |b|
				espeed = pbRoughStat(b,:SPEED,skill)
				espeed*=1.5 if b.hasActiveAbility?(:SPEEDBOOST)
				ospeed=espeed if espeed>ospeed
			end
			maxdam=0
			maxspec=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				b.moves.each_with_index do |j,i|
					if moveLocked(b)
						if b.lastMoveUsed && b.pbHasMove?(b.lastMoveUsed)
							next if j.id!=b.lastMoveUsed
						end
					end	
					tempdam = @damagesAI[b.index][i][:dmg][user.index]#pbRoughDamage(j,b,user,skill,j.baseDamage)
					if tempdam>maxdam
						maxdam=tempdam 
						maxspec=j.specialMove?(j.type)
					end    
				end 
			end   
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=30 if user.hasActiveItem?(:SMOOTHROCK)
			score+=30 if halfhealth>maxdam || (target.status == :SLEEP && target.statusCount>1)
			score+=20 if maxspec && ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && user.pbHasType?(:ROCK)
			score+=20 if user.pbHasType?(:ROCK)
			if !user.hasActiveItem?(:SAFETYGOGGLES) && !user.hasActiveItem?(:UTILITYUMBRELLA) && 
				!user.pbHasType?(:ROCK) && !user.pbHasType?(:STEEL) && !user.pbHasType?(:GROUND) &&
				!user.hasActiveAbility?(:MAGICGUARD) && !user.hasActiveAbility?(:OVERCOAT) && 
				!user.hasActiveAbility?(:SANDVEIL) && !user.hasActiveAbility?(:SANDRUSH) && !user.hasActiveAbility?(:SANDFORCE)
				score-=10
				score-=40 if user.hp==user.totalhp && (user.hasActiveAbility?(:STURDY) || user.hasActiveItem?(:FOCUSSASH))
			end    
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			end
			score-=20 if user.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun")
			score+=20 if user.pbHasMoveFunction?("HealUserDependingOnSandstorm")
			if user.hasActiveAbility?(:SANDRUSH)
				score+=30
				score+=40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
			end    
			score+=20 if user.hasActiveAbility?(:SANDVEIL) || user.hasActiveAbility?(:SANDFORCE)
			ownparty = @battle.pbParty(user.index)
			inBattleIndices = @battle.allSameSideBattlers(user.index).map { |b| b.pokemonIndex }
			ownparty.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				next if inBattleIndices.include?(idxParty)
				score+=40 if pkmn.ability == :SANDRUSH
				score+=20 if pkmn.ability == :SANDVEIL || pkmn.ability == :SANDFORCE
				score+=20 if pkmn.hasType?(:ROCK)
				score-=10 if user.pbHasMoveFunction?("TwoTurnAttackChargeRaiseUserSpAtk1OneTurnInRain") && (@battle.pbWeather == :Rain || @battle.pbWeather == :FreezingRain)
				score-=10 if pkmn.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun") && @battle.pbWeather == :Sun
				score+=20 if pkmn.pbHasMoveFunction?("HealUserDependingOnSandstorm") 
			end
			party = @battle.pbParty(target.index)
			party.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				if (pkmn.ability == :CHLOROPHYLL && @battle.pbWeather == :Sun) || (pkmn.ability == :SWIFTSWIM && (@battle.pbWeather == :Rain || @battle.pbWeather == :FreezingRain))
					score+=40
				end 
				if (pkmn.ability == :SLUSHRUSH && [:Hail, :FreezingRain].include?(@battle.pbWeather))
					score+=20
				end 
			end
			@battle.allOtherSideBattlers(user.index).each do |b|
				score+=80 if b.hasActiveAbility?(:WONDERGUARD) && !b.pbHasType?(:ROCK) && !b.pbHasType?(:GROUND) && !b.pbHasType?(:STEEL)
			end	
			if @battle.pbCheckGlobalAbility(:AIRLOCK) ||
				@battle.pbCheckGlobalAbility(:CLOUDNINE) || @battle.field.effects[PBEffects::ClearFlute]>0
				score -=200
			elsif [:Sandstorm, :HeavyRain, :FrozenStorm, :HarshSun, :HolyInferno].include?(@battle.pbWeather)
				score -=200
			end
			#------------------------------------------------------------------
		when "StartHailWeather"  # Hail
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			#ospeed = pbRoughStat(target,:SPEED,skill)
			ospeed=0
			@battle.allSameSideBattlers(target.index).each do |b|
				espeed = pbRoughStat(b,:SPEED,skill)
				espeed*=1.5 if b.hasActiveAbility?(:SPEEDBOOST)
				ospeed=espeed if espeed>ospeed
			end
			maxdam=0
			maxphys=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				b.moves.each_with_index do |j,i|
					if moveLocked(b)
						if b.lastMoveUsed && b.pbHasMove?(b.lastMoveUsed)
							next if j.id!=b.lastMoveUsed
						end
					end	
					tempdam = @damagesAI[b.index][i][:dmg][user.index]#pbRoughDamage(j,b,user,skill,j.baseDamage)
					if tempdam>maxdam
						maxdam=tempdam 
						maxphys=j.physicalMove?(j.type)
					end    
				end 
			end   
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=30 if user.hasActiveItem?(:ICYROCK)
			score+=30 if halfhealth>maxdam || (target.status == :SLEEP && target.statusCount>1)
			if PluginManager.installed?("Generation 9 Pack") && Settings::HAIL_WEATHER_TYPE > 0
				score+=20 if maxphys && aspeed>ospeed && user.pbHasType?(:ICE)
			end    
			score+=20 if user.pbHasType?(:ICE)
			if !user.hasActiveItem?(:SAFETYGOGGLES) && !user.hasActiveItem?(:UTILITYUMBRELLA) && 
				!user.pbHasType?(:ICE) && !user.pbHasType?(:STEEL) && !user.pbHasType?(:GROUND) &&
				!user.hasActiveAbility?(:MAGICGUARD) && !user.hasActiveAbility?(:OVERCOAT) && 
				!user.hasActiveAbility?(:SANDVEIL) && !user.hasActiveAbility?(:SANDRUSH) && !user.hasActiveAbility?(:SANDFORCE)
				if PluginManager.installed?("Generation 9 Pack")
					if Settings::HAIL_WEATHER_TYPE == 0
						score-=10
						score-=40 if user.hp==user.totalhp && (user.hasActiveAbility?(:STURDY) || user.hasActiveItem?(:FOCUSSASH))
					end   
				else
					score-=10
					score-=40 if user.hp==user.totalhp && (user.hasActiveAbility?(:STURDY) || user.hasActiveItem?(:FOCUSSASH))
				end
			end     
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			end
			score-=10 if user.pbHasMoveFunction?("TwoTurnAttackChargeRaiseUserSpAtk1OneTurnInRain") && (@battle.pbWeather == :Rain || @battle.pbWeather == :FreezingRain)
			score-=20 if user.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun")
			score+=20 if user.pbHasMoveFunction?("FreezeTargetAlwaysHitsInHail")
			score+=40 if user.pbHasMoveFunction?("StartWeakenDamageAgainstUserSideIfHail")
			if user.hasActiveAbility?(:SLUSHRUSH)
				score+=30
				score+=40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
			end    
			score+=20 if user.hasActiveAbility?(:SNOWCLOAK) || user.hasActiveAbility?(:ICEBODY)
			ownparty = @battle.pbParty(user.index)
			inBattleIndices = @battle.allSameSideBattlers(user.index).map { |b| b.pokemonIndex }
			ownparty.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				next if inBattleIndices.include?(idxParty)
				score+=40 if pkmn.ability == :SLUSHRUSH
				score+=20 if pkmn.ability == :SNOWCLOAK || pkmn.ability == :ICEBODY
				score+=20 if pkmn.hasType?(:ICE) && PluginManager.installed?("Generation 9 Pack") && Settings::HAIL_WEATHER_TYPE > 0
				score-=10 if pkmn.pbHasMoveFunction?("HealUserDependingOnWeather", "RaiseUserAtkSpAtk1Or2InSun", "TwoTurnAttackOneTurnInSun") && @battle.pbWeather == :Sun
				score+=20 if pkmn.pbHasMoveFunction?("FreezeTargetAlwaysHitsInHail") 
				score+=20 if pkmn.pbHasMoveFunction?("StartWeakenDamageAgainstUserSideIfHail") 
			end
			party = @battle.pbParty(target.index)
			party.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				if (pkmn.ability == :CHLOROPHYLL && @battle.pbWeather == :Sun) || (pkmn.ability == :SWIFTSWIM && (@battle.pbWeather == :Rain || @battle.pbWeather == :FreezingRain))
					score+=40
				end 
				if (pkmn.ability == :SANDRUSH && @battle.pbWeather == :Sandstorm)
					score+=20
				end 
			end
			@battle.allOtherSideBattlers(user.index).each do |b|
				score+=80 if b.hasActiveAbility?(:WONDERGUARD) && !b.pbHasType?(:ICE)
			end	
			if @battle.pbCheckGlobalAbility(:AIRLOCK) ||
				@battle.pbCheckGlobalAbility(:CLOUDNINE) || @battle.field.effects[PBEffects::ClearFlute]>0
				score -=200
			elsif [:Hail, :HeavyRain, :FreezingRain, :FrozenStorm, :HarshSun, :HolyInferno].include?(@battle.pbWeather)
				score -=200
			end  
			#---------------------------------------------------------------------------
		when "StartElectricTerrain"  # Electric Terrain
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			maxdam=0
			maxphys=false
			maxspec=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				b.moves.each_with_index do |j,i|
					if moveLocked(b)
						if b.lastMoveUsed && b.pbHasMove?(b.lastMoveUsed)
							next if j.id!=b.lastMoveUsed
						end
					end	
					tempdam = @damagesAI[b.index][i][:dmg][user.index]#pbRoughDamage(j,b,user,skill,j.baseDamage)
					if tempdam>maxdam
						maxdam=tempdam 
						maxphys=j.physicalMove?(j.type)
						maxspec=j.specialMove?(j.type)
					end    
				end 
			end   
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=30 if user.hasActiveItem?(:TERRAINEXTENDER)
			score+=20 if halfhealth>maxdam
			score+=20 if aspeed>ospeed && user.hasActiveItem?(:ELECTRICSEED) & maxphys
			score+=20 if aspeed>ospeed && target.pbHasMoveFunction?("SleepTarget", "SleepTargetIfUserDarkrai", "SleepTargetChangeUserMeloettaForm")
			user.eachMove do |m|
				next if !m.damagingMove? || m.type != :ELECTRIC
				score += 10
			end  
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			end
			score+=20 if user.pbHasMoveFunction?("TypeAndPowerDependOnTerrain", "BPRaiseWhileElectricTerrain")
			score+=30 if user.pbHasMoveFunction?("DoublePowerInElectricTerrain")
			if user.hasActiveAbility?(:SURGESURFER)
				score+=20
				score+=40 if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))
			end  
			score+=20 if user.hasActiveAbility?(:QUARKDRIVE)
			ownparty = @battle.pbParty(user.index)
			inBattleIndices = @battle.allSameSideBattlers(user.index).map { |b| b.pokemonIndex }
			ownparty.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				next if inBattleIndices.include?(idxParty)
				score+=40 if pkmn.ability == :SURGESURFER
				score+=20 if pkmn.ability == :QUARKDRIVE
				score+=20 if pkmn.item == :ELECTRICSEED
				score+=20 if pkmn.pbHasMoveFunction?("TypeAndPowerDependOnTerrain", "BPRaiseWhileElectricTerrain")
				score+=30 if pkmn.pbHasMoveFunction?("DoublePowerInElectricTerrain") 
			end
			party = @battle.pbParty(target.index)
			if @battle.field.terrain == :Electric
				score -=200
			end   
			#---------------------------------------------------------------------------
		when "StartGrassyTerrain"  # Grassy Terrain
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			maxdam=0
			maxmove= "none"
			maxphys=false
			maxspec=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				b.moves.each_with_index do |j,i|
					if moveLocked(b)
						if b.lastMoveUsed && b.pbHasMove?(b.lastMoveUsed)
							next if j.id!=b.lastMoveUsed
						end
					end	
					tempdam = @damagesAI[b.index][i][:dmg][user.index]#pbRoughDamage(j,b,user,skill,j.baseDamage)
					if tempdam>maxdam
						maxdam=tempdam 
						maxmove=j.function
						maxphys=j.physicalMove?(j.type)
						maxspec=j.specialMove?(j.type)
					end    
				end 
			end    
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=30 if user.hasActiveItem?(:TERRAINEXTENDER)
			score+=20 if halfhealth>maxdam
			score+=20 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && user.hasActiveItem?(:GRASSYSEED) & maxphys
			score+=20 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && (maxmove == "DoublePowerIfTargetUnderground" || 
				maxmove == "RandomPowerDoublePowerIfTargetUnderground" || maxmove == "LowerTargetSpeed1WeakerInGrassyTerrain")
			user.eachMove do |m|
				next if !m.damagingMove? || m.type != :GRASS
				score += 10
			end  
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			end
			score+=20 if user.pbHasMoveFunction?("TypeAndPowerDependOnTerrain", "HealTargetDependingOnGrassyTerrain")
			score+=30 if user.pbHasMoveFunction?("HigherPriorityInGrassyTerrain")
			if user.hasActiveAbility?(:GRASSPELT)
				score+=20
				score+=20 if maxphys && aspeed<ospeed && aspeed*2>ospeed
			end    
			ownparty = @battle.pbParty(user.index)
			inBattleIndices = @battle.allSameSideBattlers(user.index).map { |b| b.pokemonIndex }
			ownparty.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				next if inBattleIndices.include?(idxParty)
				score+=20 if pkmn.ability == :GRASSPELT
				score+=20 if pkmn.item == :GRASSYSEED
				score-=20 if pkmn.pbHasMoveFunction?("DoublePowerIfTargetUnderground", "RandomPowerDoublePowerIfTargetUnderground",
					"LowerTargetSpeed1WeakerInGrassyTerrain")
				score+=20 if pkmn.pbHasMoveFunction?("TypeAndPowerDependOnTerrain", "HealTargetDependingOnGrassyTerrain")
				score+=40 if pkmn.pbHasMoveFunction?("HigherPriorityInGrassyTerrain") 
			end
			party = @battle.pbParty(target.index)
			if @battle.field.terrain == :Grassy
				score -=200
			end   
			#---------------------------------------------------------------------------
		when "StartMistyTerrain"  # Misty Terrain
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			maxdam=0
			dragon=false
			maxphys=false
			maxspec=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				b.moves.each_with_index do |j,i|
					if moveLocked(b)
						if b.lastMoveUsed && b.pbHasMove?(b.lastMoveUsed)
							next if j.id!=b.lastMoveUsed
						end
					end	
					tempdam = @damagesAI[b.index][i][:dmg][user.index]#pbRoughDamage(j,b,user,skill,j.baseDamage)
					if tempdam>maxdam
						maxdam=tempdam 
						dragon= (j.type==:DRAGON)
						maxphys=j.physicalMove?(j.type)
						maxspec=j.specialMove?(j.type)
					end    
				end 
			end   
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			score+=40 if dragon && ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
			score+=20 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && user.hasActiveItem?(:MISTYSEED) & maxspec
			score+=30 if user.hasActiveItem?(:TERRAINEXTENDER)
			score+=20 if halfhealth>maxdam
			target.eachMove do |m|
				next if m.baseDamage>20
				score += 20 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && (m.function=="ParalyzeTarget" || m.function == "ParalyzeTargetIfNotTypeImmune")
			end    
			score+=20 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && target.pbHasMoveFunction?("SleepTarget", "SleepTargetIfUserDarkrai", "SleepTargetChangeUserMeloettaForm")
			
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			end
			score+=20 if user.pbHasMoveFunction?("TypeAndPowerDependOnTerrain")
			score+=30 if user.pbHasMoveFunction?("UserFaintsPowersUpInMistyTerrainExplosive")
			ownparty = @battle.pbParty(user.index)
			inBattleIndices = @battle.allSameSideBattlers(user.index).map { |b| b.pokemonIndex }
			ownparty.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				next if inBattleIndices.include?(idxParty)
				score+=20 if pkmn.item == :MISTYSEED
				pkmn.eachMove do |m|
					next if m.base_damage==0 || m.type != :DRAGON
					score -= 20
				end   
				score-=20 if pkmn.pbHasMoveFunction?("SleepTarget", "SleepTargetIfUserDarkrai", "SleepTargetChangeUserMeloettaForm", 
					"ParalyzeTargetIfNotTypeImmune", "BadPoisonTarget")
				score+=20 if pkmn.pbHasMoveFunction?("TypeAndPowerDependOnTerrain")
				score+=30 if pkmn.pbHasMoveFunction?("UserFaintsPowersUpInMistyTerrainExplosive") 
			end
			party = @battle.pbParty(target.index)
			if @battle.field.terrain == :Misty
				score -=200
			end   
			#---------------------------------------------------------------------------
		when "StartPsychicTerrain"  # Psychic Terrain
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			maxdam=0
			prio=false
			maxphys=false
			maxspec=false
			@battle.allOtherSideBattlers(user.index).each do |b|
				b.moves.each_with_index do |j,i|
					if moveLocked(b)
						if b.lastMoveUsed && b.pbHasMove?(b.lastMoveUsed)
							next if j.id!=b.lastMoveUsed
						end
					end	
					tempdam = @damagesAI[b.index][i][:dmg][user.index]#pbRoughDamage(j,b,user,skill,j.baseDamage)
					if tempdam>maxdam
						maxdam=tempdam 
						prio= (j.priority>0)
						maxphys=j.physicalMove?(j.type)
						maxspec=j.specialMove?(j.type)
					end    
				end 
			end   
			halfhealth=(user.hp/2)
			thirdhealth=(user.hp/3)
			user.eachMove do |m|
				next if !m.damagingMove? || m.type != :PSYCHIC
				score += 10
			end  
			score+=40 if prio
			score+=20 if target.hasActiveAbility?(:PRANKSTER)
			score+=20 if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && user.hasActiveItem?(:PSYCHICSEED) & maxspec
			score+=30 if user.hasActiveItem?(:TERRAINEXTENDER)
			score+=20 if halfhealth>maxdam
			score+=20 if target.pbHasMoveFunction?("FailsIfTargetActed")                                          
			if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				score -= 50 if maxdam>thirdhealth
			end
			score+=20 if user.pbHasMoveFunction?("TypeAndPowerDependOnTerrain")
			score+=30 if user.pbHasMoveFunction?("HitsAllFoesAndPowersUpInPsychicTerrain")
			ownparty = @battle.pbParty(user.index)
			inBattleIndices = @battle.allSameSideBattlers(user.index).map { |b| b.pokemonIndex }
			ownparty.each_with_index do |pkmn, idxParty|
				next if !pkmn || !pkmn.able?
				next if inBattleIndices.include?(idxParty)
				score-=10 if pkmn.ability == :PRANKSTER
				score+=20 if pkmn.item == :PSYCHICSEED
				pkmn.eachMove do |m|
					score -= 5 if m.priority>0
				end   
				score+=20 if pkmn.pbHasMoveFunction?("TypeAndPowerDependOnTerrain")
				score+=30 if pkmn.pbHasMoveFunction?("HitsAllFoesAndPowersUpInPsychicTerrain") 
			end
			party = @battle.pbParty(target.index)
			if @battle.field.terrain == :Psychic
				score -=200
			end 
			#---------------------------------------------------------------------------
		when "SwitchOutUserDamagingMove"  # U-Turn , Volt Switch , Flip Turn
			# I handle this in AI Move
			#---------------------------------------------------------------------------
		when "SwitchOutUserStatusMove"  # Teleport
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			score -= 30 if user.pbOwnSide.effects[PBEffects::StealthRock] || user.pbOwnSide.effects[PBEffects::ToxicSpikes]>0 ||
			user.pbOwnSide.effects[PBEffects::Spikes]>0 || user.pbOwnSide.effects[PBEffects::StickyWeb]
			score +=30 if user.hasActiveAbility?(:REGENERATOR)
			score +=30 if user.effects[PBEffects::Toxic]>3
			score +=30 if user.effects[PBEffects::Curse]
			score +=30 if user.effects[PBEffects::PerishSong]==1
			score +=30 if user.effects[PBEffects::LeechSeed]>0
			score +=30 if target.status == :SLEEP && target.statusCount>1
			#---------------------------------------------------------------------------
		when "SwitchOutUserPassOnEffects" # Baton PAss
			attacker=user
			opponent=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(opponent,:SPEED,skill)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxoppdam=0
			maxoppmove=nil
			maxoppidx=0
			opponent.moves.each_with_index do |j,i|
				if moveLocked(opponent)
					if opponent.lastMoveUsed && opponent.pbHasMove?(opponent.lastMoveUsed)
						next if j.id!=opponent.lastMoveUsed
					end
				end		
				tempdam = @damagesAI[opponent.index][i][:dmg][user.index]#pbRoughDamage(j,opponent,user,skill,j.baseDamage)
				tempdam = 0 if pbCheckMoveImmunity(1,j,opponent,user,100)
				if tempdam>maxoppdam
					maxoppdam=tempdam 
					maxoppmove=j
					maxoppidx=i
				end	
			end 
			party=@battle.pbParty(attacker.index)
			sack=false
			sack=true if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
			stagemult=1
			swapper=attacker.pokemonIndex
			switchin=pbHardSwitchChooseNewEnemy(attacker.index,party,sack,true)
			registerDamagesAI
			if switchin
				if switchin.is_a?(Array)
					swapper=switchin[0]
				else
					swapper=switchin
				end
			end
			if @battle.pbCanChooseNonActive?(attacker.index) && swapper!=attacker.pokemonIndex
				if targetSurvivesMove(maxmove,maxidx,attacker,opponent)
					stagemult+=1
					if sack
						stagemult+=2
						case attacker.status
						when :BURN
							stagemult+=5 if maxmove.physicalMove? && !attacker.hasActiveAbility?(:GUTS)
						when :POISON
							stagemult+=5 if !attacker.hasActiveAbility?(:POISONHEAL) && !attacker.hasActiveAbility?(:GUTS)
						when :PARALYSIS
							stagemult+=5 if maxdam>=attacker.hp/3
						end
					end	
				end
				if (opponent.status == :SLEEP && opponent.statusCount==2)
					stagemult+=5 if targetSurvivesMove(maxmove,maxidx,attacker,opponent) 
					stagemult+=5 if !targetSurvivesMove(maxoppmove,maxoppidx,opponent,attacker)
				end		
				GameData::Stat.each_battle do |stat|
					next if attacker.pbHasMoveFunction?("CurseTargetOrLowerUserSpd1RaiseUserAtkDef1") && attacker.stages[stat.id]<0 && stat.id==:SPEED
					score += stagemult*attacker.stages[stat.id]
				end	
				if attacker.effects[PBEffects::Substitute]>0
					score+=30
				end
				if attacker.effects[PBEffects::Confusion]>0
					score-=20
				end
				if attacker.effects[PBEffects::LeechSeed]>=0
					score-=40
				end
				if attacker.effects[PBEffects::Curse]
					score-=40
				end
				if attacker.effects[PBEffects::Yawn]>0
					score-=20
				end
				score+=10 if attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::AquaRing]
				score-=200 if attacker.effects[PBEffects::PerishSong]>0
				if attacker.turnCount<1
					score-=30
				end
				score-=20 if @battle.pbSideSize(1)>1
			else
				score-=200
			end
			#---------------------------------------------------------------------------
			when "CantSelectConsecutiveTurns"                   # Gigaton Hammer
			  if user.hasActiveItem?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF]) ||
				 user.hasActiveAbility?(:GORILLATACTICS) || user.effects[PBEffects::Encore] > 0
				score -= 2000 
			  end
			#---------------------------------------------------------------------------
			when "UserFaintsPowersUpInMistyTerrainExplosive"
			#---------------------------------------------------------------------------
			when "DoublePowerInElectricTerrain"
			#---------------------------------------------------------------------------
			when "HitsAllFoesAndPowersUpInPsychicTerrain"
			#---------------------------------------------------------------------------
			when "HigherPriorityInGrassyTerrain"
			#---------------------------------------------------------------------------
			when "TypeAndPowerDependOnTerrain"
			#---------------------------------------------------------------------------
			when "RecoilHalfOfTotalHP"                          # Chloroblast
			#---------------------------------------------------------------------------
			when "IncreasePowerEachFaintedAlly"                 # Last Respects
			#---------------------------------------------------------------------------
			when "IncreasePowerEachTimeHit"                     # Rage Fist
			#---------------------------------------------------------------------------
			when "IncreasePowerInSunWeather"                    # Hydro Steam
			#---------------------------------------------------------------------------
			when "IncreasePowerWhileElectricTerrain"            # Psyblade
			#---------------------------------------------------------------------------
			when "CrashDamageIfFailsConfuseTarget"              # Axe Kick
			#---------------------------------------------------------------------------
			when "UserVulnerableUntilNextAction"                # Glaive Rush
			#---------------------------------------------------------------------------
		when "RaiseUserAttack2IfTargetFaints", "RaiseUserAttack3IfTargetFaints"
			# Yes, this is my change. To override the one in AI_Move_Effectscores_1 that treats the move like fucking Swords Dance >.>
			# This is now handled in pbGetMoveScoreDamage.
			#---------------------------------------------------------------------------
		when "RaiseUserSpAtk2IfTargetFaints", "RaiseUserSpAtk3IfTargetFaints"
			# Yes, this is my change. To override the one in AI_Move_Effectscores_1 that treats the move like fucking Swords Dance >.>
			# This is now handled in pbGetMoveScoreDamage.
		#---------------------------------------------------------------------------
		when "FailsIfTargetHasNoItem"
			# Simply overriding the erroneous scoring from AI_Move_Effectscores_1.
			# This is now handled in pbCheckMoveImmunity
		#---------------------------------------------------------------------------
		when "DoublePowerIfUserLostHPThisTurn"
			# Simply overriding the erroneous scoring from AI_Move_Effectscores_1.
			# This is now handled in pbGetMoveScoreDamage.
			#---------------------------------------------------------------------------
		when "EnsureNextMoveAlwaysHits" # Lock-On / Mind Reader
			if user.effects[PBEffects::LockOn]>0 || target.effects[PBEffects::Substitute]>0
				score -=200
			else
				found=false
				for m in user.moves
					found=true if ["OHKO","OHKOHitsUndergroundTarget","OHKOIce"].include?(m.function)  && !pbCheckMoveImmunity(1,m,user,target,100)
				end
				score +=90 if found
			end
			#---------------------------------------------------------------------------
			when "StartPerishCountsForAllBattlers" # Perish Song
				target=user.pbDirectOpposing(true)
				score += 90 if user.hasActiveAbility?([:SHADOWTAG,:ARENATRAP])
			  if @battle.pbAbleNonActiveCount(user.idxOwnSide) == 0 && @battle.pbAbleNonActiveCount(target.idxOwnSide) > 0
				score = 5
			  elsif target.effects[PBEffects::PerishSong] > 0
				score = 5
			  end
			#---------------------------------------------------------------------------
		 when "HealUserByHalfOfDamageDoneIfTargetAsleep" # Dream Eater  # Disabled in ss2 due to move rework
			if !target.asleep?
				score -= 2000
			elsif skill>=PBTrainerAI.highSkill && target.hasActiveAbility?(:LIQUIDOOZE)
				score -= 500
			else
				score += 20 if user.hp<=user.totalhp/2
			end
			#---------------------------------------------------------------------------
			when "HealUserByHalfOfDamageDone"
			  if skill >= PBTrainerAI.highSkill && target.hasActiveAbility?(:LIQUIDOOZE)
				score -= 500
			  elsif user.hp <= user.totalhp / 2
				score += 20
			  end
			#---------------------------------------------------------------------------
			when "HealUserByThreeQuartersOfDamageDone"
			  if skill >= PBTrainerAI.highSkill && target.hasActiveAbility?(:LIQUIDOOZE)
				score -= 750
			  elsif user.hp <= user.totalhp / 2
				score += 40
			  end
			#---------------------------------------------------------------------------
		when "StartUserSideDoubleSpeed" # Tailwind
			target=user.pbDirectOpposing(true)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			if targetSurvivesMove(maxmove,maxidx,target,attacker) || (target.status == :SLEEP && target.statusCount>1)
				#score += 40
				pspeed=0
				espeed=0
				if skill>=PBTrainerAI.highSkill
					minspeed=0
					@battle.allSameSideBattlers(user.index).each do |b|
						pspeed = pbRoughStat(b,:SPEED,skill)
						pspeed*=1.5 if b.hasActiveAbility?(:SPEEDBOOST)
						minspeed=pspeed if pspeed<minspeed
					end
					maxspeed=0
					@battle.allSameSideBattlers(target.index).each do |b|
						espeed = pbRoughStat(b,:SPEED,skill)
						espeed*=1.5 if b.hasActiveAbility?(:SPEEDBOOST)
						maxspeed=espeed if espeed>maxspeed
					end
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
					ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
					score += 100 if (((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))) || 
					(((aspeed<espeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((aspeed*2>espeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))) ||
					(((pspeed<espeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((pspeed*2>espeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1))) || 
					(((pspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) && ((pspeed*2>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)))
				end
			end
			score -=200 if user.pbOwnSide.effects[PBEffects::Tailwind] > 0
			#---------------------------------------------------------------------------
		when "StartSlowerBattlersActFirst" # Trick Room
			target=user.pbDirectOpposing(true)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxprio=bestmove[2]
			if targetSurvivesMove(maxmove,maxidx,target,attacker,maxprio) || maxprio==0 || (target.status == :SLEEP && target.statusCount>1)
				#score += 40
				pspeed=0
				espeed=0
				if skill>=PBTrainerAI.highSkill
					minspeed=5000
					@battle.allSameSideBattlers(user.index).each do |b|
						pspeed = pbRoughStat(b,:SPEED,skill)
						pspeed*=1.5 if b.hasActiveAbility?(:SPEEDBOOST)
						minspeed=pspeed if pspeed<minspeed
					end
					maxspeed=0
					@battle.allSameSideBattlers(target.index).each do |b|
						espeed = pbRoughStat(b,:SPEED,skill)
						espeed*=1.5 if b.hasActiveAbility?(:SPEEDBOOST)
						espeed*=0.5 if b.pbHasMove?(:CURSE) && !b.pbHasType?(:GHOST)
						maxspeed=espeed if espeed>maxspeed
					end
					aspeed = pbRoughStat(user,:SPEED,skill)
					ospeed = pbRoughStat(target,:SPEED,skill)
					aspeed*=1.5 if user.hasActiveAbility?(:SPEEDBOOST)
					ospeed*=1.5 if target.hasActiveAbility?(:SPEEDBOOST)
					ospeed*=0.5 if target.pbHasMove?(:CURSE) && !target.pbHasType?(:GHOST)
					#if ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) ||
					if	((minspeed<maxspeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						score += 150 
					else
						score -= 200
					end
				end
			end
			#---------------------------------------------------------------------------
			when "RedirectAllMovesToUser" # Follow Me
				ignores=false
				@battle.allSameSideBattlers(opponent.index).each do |b|
					ignores = true if b.hasActiveAbility?([:STALWART,:PROPELLERTAIL])
				end
			  if user.allAllies.length == 0 || ignores
				score -= 90 
			  else
				user.allAllies.each do |b|
					score +=90 #if b.pbOwnedByPlayer?
					if b.pbHasMoveFunction?("StartSlowerBattlersActFirst") && @battle.field.effects[PBEffects::TrickRoom]==0
						score += 150
					end
				end
			  end
			#---------------------------------------------------------------------------
			when "ProtectUser", "ProtectUserFromDamagingMovesObstruct", "ProtectUserFromTargetingMovesSpikyShield", "ProtectUserBanefulBunker", "ProtectUserFromDamagingMovesKingsShield" # Protect
				target=user.pbDirectOpposing(true)
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxprio=bestmove[2]
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				ownhpchange=(EndofTurnHPChanges(user,target,false,false,true)) # what % of our hp will change after end of turn effects go through
				opphpchange=(EndofTurnHPChanges(target,user,false,false,true)) # what % of our hp will change after end of turn effects go through
				score -= 200 if maxdam < (user.hp * 0.1)
				if @battle.positions[user.index].effects[PBEffects::Wish]>0
					score+=140 if (maxdam >= @battle.positions[user.index].effects[PBEffects::WishAmount] || maxdam >= user.hp)
				else
					if ownhpchange > opphpchange
						score += 90 
					end
					score += 90 if target.effects[PBEffects::PerishSong] > 0 && user.hasActiveAbility?([:SHADOWTAG,:ARENATRAP])
					if ((aspeed<=ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && maxdam>0
						if user.hasActiveAbility?(:SPEEDBOOST) && !target.hasActiveAbility?(:SPEEDBOOST) 
							if @battle.field.effects[PBEffects::TrickRoom]<2
								score+=60
								score+=80 if (aspeed * 1.5) > ospeed
							else
								score-=90
							end
						end
						if target.pbOwnSide.effects[PBEffects::Tailwind] > user.pbOwnSide.effects[PBEffects::Tailwind]
							if @battle.field.effects[PBEffects::TrickRoom]<2
								score+=60
								score+=80 if (aspeed * 2) > ospeed
							else
								score-=90
							end
						end
					end
					if target.pbOwnSide.effects[PBEffects::AuroraVeil]>0
						if (target.pbOwnSide.effects[PBEffects::AuroraVeil] > user.pbOwnSide.effects[PBEffects::AuroraVeil])
							score+=90
						else
							score-=90
						end
					end
					maxowndam=0
					maxownidx=0
					maxownmove=nil
					bestownmove=bestMoveVsTarget(user,target,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxowndam=bestownmove[0] 
					maxownidx=bestownmove[4]
					maxownmove=bestownmove[1]
					maxownprio=bestownmove[2]
					if target.effects[PBEffects::Rollout] > 0 && maxdam>0
						if ((aspeed<=ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
							score+=140
						else
							score+=140 if targetSurvivesMove(maxownmove,maxownidx,user,target,maxownprio)
						end
					end
					score += 90 if target.effects[PBEffects::TwoTurnAttack]
					score += 90 if target.effects[PBEffects::Toxic]>0
				end
				score-=90 if target.pbHasMoveFunction?("RaiseUserAtkDef1","RaiseUserAtkDefAcc1","RaiseUserAtkSpd1","RaiseUserAtk1Spd2",
					"RaiseUserSpAtkSpDefSpd1","RaiseUserSpAtkSpDef1","RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserAttack1",
					"RaiseUserAttack2","RaiseUserAtkAcc1","RaiseUserSpAtk2","RaiseUserSpAtk3","LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2") # Setup
			  if user.effects[PBEffects::ProtectRate]>1 
				score -= 90
				if ((aspeed>=ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) &&
					targetSurvivesMove(maxmove,maxidx,target,user,maxprio)
					score -= 300
				end
			#   else
			# 	if skill>=PBTrainerAI.mediumSkill
			# 	  score -= user.effects[PBEffects::ProtectRate]*40
			# 	end
			  end
			#---------------------------------------------------------------------------
		when "StartLeechSeedTarget" # Leech Seed
			attacker=user
			opponent=target
			if (opponent.effects[PBEffects::LeechSeed]<0 && !opponent.pbHasType?(:GRASS) && opponent.effects[PBEffects::Substitute]<=0) 
				if attacker.effects[PBEffects::Substitute]>0
					score+=30
				end
				if opponent.hp==opponent.totalhp
					score+=30
					# else
					# 	score*=(opponent.hp*(1.0/opponent.totalhp))
				end
				if attacker.hasActiveItem?(:LEFTOVERS) || attacker.hasActiveItem?(:BIGROOT) || (attacker.hasActiveItem?(:BLACKSLUDGE) && attacker.pbHasType?(:POISON))
					score+=10
				end
				if attacker.effects[PBEffects::Ingrain] || attacker.effects[PBEffects::AquaRing]
					score+=10
				end
				if attacker.hasWorkingAbility(:RAINDISH) && [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(attacker.effectiveWeather)
					score+=10
				end
				if opponent.status==:PARALYSIS || opponent.status==:SLEEP
					score+=10
				end
				if opponent.effects[PBEffects::Confusion]>0
					score+=10
				end
				if opponent.effects[PBEffects::Attract]>=0
					score+=10
				end
				if opponent.status==:POISON || opponent.status==:BURN
					score+=10
				end
				score+=80 if target.hasActiveAbility?(:WONDERGUARD)
				score-=50 if target.pbHasMoveFunction?("SwitchOutUserDamagingMove") # U-Turn
				if opponent.hp*2<opponent.totalhp
					score-=10
					if opponent.hp*4<opponent.totalhp
						score-=80
					end
				end
				protectmove=false
				protectmove = true if attacker.pbHasMoveFunction?("ProtectUser", "ProtectUserFromTargetingMovesSpikyShield", "ProtectUserBanefulBunker", "ProtectUserFromDamagingMovesKingsShield", "ProtectUserFromDamagingMovesObstruct")
				if protectmove
					score+=20
				end
				if opponent.hasWorkingAbility(:LIQUIDOOZE)
					score-=100
				end
			else
				score-=100
			end
			#---------------------------------------------------------------------------
		when "HealUserHalfOfTotalHP", "HealUserHalfOfTotalHPLoseFlyingTypeThisTurn", "HealUserDependingOnWeather", "HealUserDependingOnSandstorm" # Recover, Roost, Synthesis, Shore Up
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			fastermon=((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
			fasterhealing=fastermon || user.hasActiveAbility?(:PRANKSTER) || user.hasActiveAbility?(:TRIAGE) 
			if move.function == "HealUserDependingOnWeather" 
				case user.effectiveWeather
				when :Sun, :HarshSun, :HolyInferno
					halfhealth=(user.totalhp*2/3)
				when :None
					halfhealth=(user.totalhp/2)
				else
					halfhealth=(user.totalhp/4)
				end
			elsif move.function == "HealUserDependingOnSandstorm" 
				case user.effectiveWeather
				when :Sandstorm
					halfhealth=(user.totalhp*2/3)
				else
					halfhealth=(user.totalhp/2)
				end   
			else     
				halfhealth=(user.totalhp/2)
			end   
			maxdam=0
			maxidx=0
			maxmove=nil    
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxdam=0 if (target.status == :SLEEP && target.statusCount>1)	
			berrymulti = 1
			berrymulti = 2 if target.moves[maxidx].type == resistBerryType(user)
			maxdam *= berrymulti
			#if maxdam>user.hp
			if !targetSurvivesMove(maxmove,maxidx,target,user,berrymulti)
				if maxdam>(user.hp+halfhealth)
					score=0
				else
					if maxdam>=halfhealth
						if fastermon
							score*=0.5
						else
							score*=0.1
						end
					else
						score*=2
					end
				end
			else
				if maxdam*1.5>user.hp
					score*=2
				end
				if !fastermon
					if maxdam*2>user.hp
						score*=2
					end
				end
			end
			hpchange=(EndofTurnHPChanges(user,target,false,false,true)) # what % of our hp will change after end of turn effects go through
			opphpchange=(EndofTurnHPChanges(target,user,false,false,true)) # what % of our hp will change after end of turn effects go through
			if opphpchange<1 ## we are going to be taking more chip damage than we are going to heal
				oppchipdamage=((target.totalhp*(1-hpchange)))
			end
			thisdam=maxdam#*1.1
			hplost=(user.totalhp-user.hp)
			hplost+=maxdam if !fasterhealing
			if user.effects[PBEffects::LeechSeed]>=0 && !fastermon && canSleepTarget(target,user)
				score *= 0.3 
			end	
			if hpchange<1 ## we are going to be taking more chip damage than we are going to heal
				chipdamage=((user.totalhp*(1-hpchange)))
				thisdam+=chipdamage
			elsif hpchange>1 ## we are going to be healing more hp than we take chip damage for  
				healing=((user.totalhp*(hpchange-1)))
				thisdam-=healing if !(thisdam>user.hp)
			elsif hpchange<=0 ## we are going to a huge overstack of end of turn effects. hence we should just not heal.
				score*=0
			end
			if thisdam>hplost
				score*=0.1
			else
				if @battle.pbAbleNonActiveCount(user.idxOwnSide) == 0 && hplost<=(halfhealth)
					score*=0.01
				end
				if thisdam<=(halfhealth)
					score*=2
				else
					if fastermon
						if hpchange<1 && thisdam>=halfhealth && !(opphpchange<1)
							score*=0.3
						end
					end
				end
			end
			score*=0.7 if target.pbHasMoveFunction?("RaiseUserAtkDef1","RaiseUserAtkDefAcc1","RaiseUserAtkSpd1","RaiseUserAtk1Spd2",
				"RaiseUserSpAtkSpDefSpd1","RaiseUserSpAtkSpDef1","RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserAttack1",
				"RaiseUserAttack2","RaiseUserAtkAcc1","RaiseUserSpAtk2","RaiseUserSpAtk3","LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2") # Setup
			if ((user.hp.to_f)<=halfhealth)
				score*=1.5
			else
				score*=0.5
			end
			score/=(user.effects[PBEffects::Toxic]) if user.effects[PBEffects::Toxic]>0
			score*=0.8 if maxdam>halfhealth
			if target.hasActiveItem?(:METRONOME)
				met=(1.0+target.effects[PBEffects::Metronome]*0.2) 
				score/=met
			end 
			score*=1.1 if user.status==:PARALYSIS || user.effects[PBEffects::Confusion]>0
			if target.status==:POISON || target.status==:BURN || target.effects[PBEffects::LeechSeed]>=0 || target.effects[PBEffects::Curse] || target.effects[PBEffects::Trapping]>0
				score*=1.3
				score*=1.3 if target.effects[PBEffects::Toxic]>0
				score*=1.3 if user.item == :BINDINGBAND
			end
			score*=0.1 if ((user.hp.to_f)/user.totalhp)>0.8
			score*=0.6 if ((user.hp.to_f)/user.totalhp)>0.6
			score*=2 if ((user.hp.to_f)/user.totalhp)<0.25
			score=0 if user.effects[PBEffects::Wish]>0	
			
			#---------------------------------------------------------------------------
		when "HealUserPositionNextTurn" # Wish
			if @battle.positions[user.index].effects[PBEffects::Wish] == 0
				target=user.pbDirectOpposing(true)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				fastermon=false#((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				fasterhealing=false#fastermon || user.hasActiveAbility?(:PRANKSTER) || user.hasActiveAbility?(:TRIAGE)
				halfhealth=(user.totalhp/2)
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxdam=0 if (target.status == :SLEEP && target.statusCount>1)	
				mult=2
				mult=1 if user.pbHasMoveFunction?("ProtectUser", "ProtectUserFromTargetingMovesSpikyShield", "ProtectUserBanefulBunker", "ProtectUserFromDamagingMovesKingsShield", "ProtectUserFromDamagingMovesObstruct")	
				#if maxdam>user.hp
				if !targetSurvivesMove(maxmove,maxidx,target,user,0,mult)
					# if maxdam>(user.hp+halfhealth)
						score=0
					# else
					# 	if maxdam>=halfhealth
					# 		if fasterhealing
					# 			score*=0.5
					# 		else
					# 			score*=0.1
					# 		end
					# 	else
					# 		score*=2
					# 	end
					# end
				# else
				# 	if maxdam*1.5>user.hp
				# 		score*=2
				# 	end
				# 	if !fastermon
				# 		if maxdam*2>user.hp
				# 			score*=2
				# 		end
				# 	end
				end
				hpchange=(EndofTurnHPChanges(user,target,false,false,true)) # what % of our hp will change after end of turn effects go through
				opphpchange=(EndofTurnHPChanges(target,user,false,false,true)) # what % of our hp will change after end of turn effects go through
				if opphpchange<1 ## we are going to be taking more chip damage than we are going to heal
					oppchipdamage=((target.totalhp*(1-hpchange)))
				end
				thisdam=maxdam#*1.1
				hplost=(user.totalhp-user.hp)
				hplost+=maxdam if !fasterhealing
				if user.effects[PBEffects::LeechSeed]>=0 && !fastermon && canSleepTarget(target,user)
					score *= 0.3 
				end	
				if hpchange<1 ## we are going to be taking more chip damage than we are going to heal
					chipdamage=((user.totalhp*(1-hpchange)))
					thisdam+=chipdamage
				elsif hpchange>1 ## we are going to be healing more hp than we take chip damage for  
					healing=((user.totalhp*(hpchange-1)))
					thisdam-=healing if !(thisdam>user.hp)
				elsif hpchange<=0 ## we are going to a huge overstack of end of turn effects. hence we should just not heal.
					score*=0
				end
				# if thisdam>hplost
				# 	score*=0.1
				# else
					if @battle.pbAbleNonActiveCount(user.idxOwnSide) == 0 && hplost<=(halfhealth)
						score*=0.01
					end
					if thisdam<=(halfhealth) && user.hp < thisdam*3 && user.hp > thisdam*mult
						score*=3
					# else
					# 	if fastermon
					# 		if hpchange<1 && thisdam>=halfhealth && !(opphpchange<1)
					# 			score*=0.3
					# 		end
					# 	end
					end
				# end
				score*=0.7 if target.pbHasMoveFunction?("RaiseUserAtkDef1","RaiseUserAtkDefAcc1","RaiseUserAtkSpd1","RaiseUserAtk1Spd2",
				"RaiseUserSpAtkSpDefSpd1","RaiseUserSpAtkSpDef1","RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserAttack1",
				"RaiseUserAttack2","RaiseUserAtkAcc1","RaiseUserSpAtk2","RaiseUserSpAtk3","LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2") # Setup
				# if ((user.hp.to_f)/user.totalhp)<0.6
				# 	score*=1.5
				# else
				# 	score*=0.5
				# end
				score/=(user.effects[PBEffects::Toxic]) if user.effects[PBEffects::Toxic]>0
				score*=0.8 if maxdam>halfhealth
				if target.hasActiveItem?(:METRONOME)
					met=(1.0+target.effects[PBEffects::Metronome]*0.2) 
					score/=met
				end 
				score*=1.1 if user.status==:PARALYSIS || user.effects[PBEffects::Confusion]>0
				if target.status==:POISON || target.status==:BURN || target.effects[PBEffects::LeechSeed]>=0 || target.effects[PBEffects::Curse] || target.effects[PBEffects::Trapping]>0
					score*=1.3
					score*=1.3 if target.effects[PBEffects::Toxic]>0
					score*=1.3 if user.item == :BINDINGBAND
				end
				# score *=2 if user.totalhp-user.hp
				# score*=0.1 if ((user.hp.to_f)/user.totalhp)>0.8
				# score*=1.5 if ((user.hp.to_f)/user.totalhp)>0.6
				# score*=2 if ((user.hp.to_f)/user.totalhp)<0.6
				score*=1.5 if user.pbHasMoveFunction?("ProtectUser", "ProtectUserFromTargetingMovesSpikyShield", "ProtectUserBanefulBunker", "ProtectUserFromDamagingMovesKingsShield", "ProtectUserFromDamagingMovesObstruct")
			else
				score=0 
			end
			#---------------------------------------------------------------------------
		when "HealUserByTargetAttackLowerTargetAttack1" # Strength Sap
			target=user.pbDirectOpposing(true)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			fastermon=((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
			fasterhealing=fastermon || user.hasActiveAbility?(:PRANKSTER) || user.hasActiveAbility?(:TRIAGE) 
			healAmt=pbRoughStat(target,:ATTACK,skill)
			halfhealth=(healAmt/2)
			maxdam=0
			maxidx=0
			maxmove=nil
			bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			if !maxmove.nil?
				if maxmove.physicalMove?
					if target.hasActiveAbility?(:CONTRARY)
						maxdam *= 1.5 
					else
						maxdam *= 0.7 
					end
				end
				maxdam=0 if (target.status == :SLEEP && target.statusCount>1)		
				#if maxdam>user.hp
				if !targetSurvivesMove(maxmove,maxidx,target,user)
					if maxdam>(user.hp+halfhealth)
						score=0
					else
						if maxdam>=halfhealth
							if fastermon
								score*=0.5
							else
								score*=0.1
							end
						else
							score*=2
						end
					end
				else
					if maxdam*1.5>user.hp
						score*=2
					end
					if !fastermon
						if maxdam*2>user.hp
							score*=2
						end
					end
				end
				hpchange=(EndofTurnHPChanges(user,target,false,false,true)) # what % of our hp will change after end of turn effects go through
				opphpchange=(EndofTurnHPChanges(target,user,false,false,true)) # what % of our hp will change after end of turn effects go through
				if opphpchange<1 ## we are going to be taking more chip damage than we are going to heal
					oppchipdamage=((target.totalhp*(1-hpchange)))
				end
				thisdam=maxdam#*1.1
				hplost=(user.totalhp-user.hp)
				hplost+=maxdam if !fasterhealing
				if user.effects[PBEffects::LeechSeed]>=0 && !fastermon && canSleepTarget(target,user)
					score *= 0.3 
				end	
				if hpchange<1 ## we are going to be taking more chip damage than we are going to heal
					chipdamage=((user.totalhp*(1-hpchange)))
					thisdam+=chipdamage
				elsif hpchange>1 ## we are going to be healing more hp than we take chip damage for  
					healing=((user.totalhp*(hpchange-1)))
					thisdam-=healing if !(thisdam>user.hp)
				elsif hpchange<=0 ## we are going to a huge overstack of end of turn effects. hence we should just not heal.
					score*=0
				end
				if thisdam>hplost
					score*=0.1
				else
					if @battle.pbAbleNonActiveCount(user.idxOwnSide) == 0 && hplost<=(halfhealth)
						score*=0.01
					end
					if thisdam<=(halfhealth)
						score*=2
					else
						if fastermon
							if hpchange<1 && thisdam>=halfhealth && !(opphpchange<1)
								score*=0.3
							end
						end
					end
				end
				score*=0.7 if target.pbHasMoveFunction?("RaiseUserAtkDef1","RaiseUserAtkDefAcc1","RaiseUserAtkSpd1","RaiseUserAtk1Spd2",
					"RaiseUserSpAtkSpDefSpd1","RaiseUserSpAtkSpDef1","RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserAttack1",
					"RaiseUserAttack2","RaiseUserAtkAcc1","RaiseUserSpAtk2","RaiseUserSpAtk3","LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2") # Setup
				if ((user.hp.to_f)<=halfhealth)
					score*=1.5
				else
					score*=0.5
				end
				score/=(user.effects[PBEffects::Toxic]) if user.effects[PBEffects::Toxic]>0
				score*=0.8 if maxdam>halfhealth
				if target.hasActiveItem?(:METRONOME)
					met=(1.0+target.effects[PBEffects::Metronome]*0.2) 
					score/=met
				end 
				score*=1.1 if user.status==:PARALYSIS || user.effects[PBEffects::Confusion]>0
				if target.status==:POISON || target.status==:BURN || target.effects[PBEffects::LeechSeed]>=0 || target.effects[PBEffects::Curse] || target.effects[PBEffects::Trapping]>0
					score*=1.3
					score*=1.3 if target.effects[PBEffects::Toxic]>0
					score*=1.3 if user.item == :BINDINGBAND
				end
				score*=0.1 if ((user.hp.to_f)/user.totalhp)>0.8
				score*=0.6 if ((user.hp.to_f)/user.totalhp)>0.6
				score*=2 if ((user.hp.to_f)/user.totalhp)<0.25
				score=0 if user.effects[PBEffects::Wish]>0	
			end
			#---------------------------------------------------------------------------
		when "HealUserFullyAndFallAsleep" # Rest
			if user.hp == user.totalhp || user.hasActiveAbility?(:PURIFYINGSALT) ||
				!user.pbCanSleep?(user, false, nil, true)
			   score -= 200
			else
				target=user.pbDirectOpposing(true)
				aspeed = pbRoughStat(user,:SPEED,skill)
				ospeed = pbRoughStat(target,:SPEED,skill)
				fastermon=((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				fasterhealing=fastermon || user.hasActiveAbility?(:PRANKSTER) || user.hasActiveAbility?(:TRIAGE)    
				if user.hasActiveItem?(:CHESTOBERRY) || user.hasActiveItem?(:LUMBERRY)
					halfhealth=(user.totalhp*2/3)
				else
					if user.pbHasMoveFunction?("UseRandomUserMoveIfAsleep")   
						halfhealth=(user.totalhp/3) 
					else
						halfhealth=(user.totalhp/4)
					end
				end    
				maxdam=0
				maxidx=0
				maxmove=nil
				bestmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] 
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				maxdam=0 if (target.status == :SLEEP && target.statusCount>1)		
				#if maxdam>user.hp
				if !targetSurvivesMove(maxmove,maxidx,target,user)
					if maxdam>(user.hp+halfhealth)
						score=0
					else
						if maxdam>=halfhealth
							if fasterhealing
								score*=0.5
							else
								score*=0.1
							end
						else
							score*=2
						end
					end
				else
					if maxdam<=(halfhealth) || user.hasActiveItem?(:CHESTOBERRY) || user.hasActiveItem?(:LUMBERRY)
						if maxdam*1.5>user.hp
							score*=2
						end
						if !fastermon
							if maxdam*2>user.hp
								score*=2
							end
						end
					end
				end
				hpchange=(EndofTurnHPChanges(user,target,false,false,true,false,true)) # what % of our hp will change after end of turn effects go through
				opphpchange=(EndofTurnHPChanges(target,user,false,false,true)) # what % of our hp will change after end of turn effects go through
				if opphpchange<1 ## we are going to be taking more chip damage than we are going to heal
					oppchipdamage=((target.totalhp*(1-hpchange)))
				end
				thisdam=maxdam#*1.1
				hplost=(user.totalhp-user.hp)
				hplost+=maxdam if !fasterhealing
				if user.effects[PBEffects::LeechSeed]>=0 && !fastermon && canSleepTarget(target,user)
					score *= 0.3 
				end	
				if hpchange<1 ## we are going to be taking more chip damage than we are going to heal
					chipdamage=((user.totalhp*(1-hpchange)))
					thisdam+=chipdamage
				elsif hpchange>1 ## we are going to be healing more hp than we take chip damage for  
					healing=((user.totalhp*(hpchange-1)))
					thisdam-=healing if !(thisdam>user.hp)
				elsif hpchange<=0 ## we are going to a huge overstack of end of turn effects. hence we should just not heal.
					score*=0
				end
				if thisdam>hplost
					score*=0.1
				else
					if @battle.pbAbleNonActiveCount(user.idxOwnSide) == 0 && hplost<=(halfhealth)
						score*=0.01
					end
					if thisdam<=(halfhealth)
						score*=2
					else
						if fastermon
							if hpchange<1 && thisdam>=halfhealth && !(opphpchange<1)
								score*=0.3
							end
						end
					end
				end
				score*=0.7 if target.pbHasMoveFunction?("RaiseUserAtkDef1","RaiseUserAtkDefAcc1","RaiseUserAtkSpd1","RaiseUserAtk1Spd2",
					"RaiseUserSpAtkSpDefSpd1","RaiseUserSpAtkSpDef1","RaiseUserAtkSpAtk1", "RaiseUserAtkSpAtk1Or2InSun","RaiseUserAttack1",
					"RaiseUserAttack2","RaiseUserAtkAcc1","RaiseUserSpAtk2","RaiseUserSpAtk3","LowerUserDefSpDef1RaiseUserAtkSpAtkSpd2") # Setup
				if ((user.hp.to_f)<=halfhealth)
					score*=1.5
				else
					score*=0.8
				end
				score*=(user.effects[PBEffects::Toxic]) if user.effects[PBEffects::Toxic]>0
				score*=0.8 if maxdam>halfhealth
				if target.hasActiveItem?(:METRONOME)
					met=(1.0+target.effects[PBEffects::Metronome]*0.2) 
					score/=met
				end 
				score*=1.1 if user.status==:PARALYSIS || user.effects[PBEffects::Confusion]>0
				if target.status==:POISON || target.status==:BURN || target.effects[PBEffects::LeechSeed]>=0 || target.effects[PBEffects::Curse] || target.effects[PBEffects::Trapping]>0
					score*=1.3
					score*=1.3 if target.effects[PBEffects::Toxic]>0
					score*=1.3 if user.item == :BINDINGBAND
				end
				score*=0.1 if ((user.hp.to_f)/user.totalhp)>0.8
				score*=0.6 if ((user.hp.to_f)/user.totalhp)>0.6
				score*=2 if ((user.hp.to_f)/user.totalhp)<0.25
				score=0 if user.effects[PBEffects::Wish]>0	
			end

		else
			score = stupidity_pbGetMoveScoreFunctionCode(score, move, user, target, skill)
		end
		
		return score-initialscore
	end
	
	def EndofTurnHPChanges(user,target,heal,chips,both,switching=false,rest=false)
		#### Azery: function below sums up all the changes to hp that will occur after the battle round. Healing from various effects/items/statuses or damage from the same. 
		### the arguments above show which ones in specific we're looking for, both being the typical default for most but sometimes we're only looking to see how much damage will occur at the end or how much healing.
		### thus it will return at 3 different points; end of healing if heal is desired, end of chip if chip is desired or at the very end if both.
		healing = 1  
		chip = 0
		oppitemworks = target.itemActive?
		attitemworks = user.itemActive?
		skill=100
		if (user.effects[PBEffects::AquaRing])==true
			subscore = 0
			subscore *= 1.3 if attitemworks && user.item == :BIGROOT
			healing += subscore
		end
		if user.effects[PBEffects::Ingrain]
			subscore = 0
			subscore *= 1.3 if attitemworks && user.item == :BIGROOT
			healing += subscore
		end
		healing += 0.0625 if user.hasWorkingAbility(:DRYSKIN) &&  [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(user.effectiveWeather)
		healing += 0.0625 if attitemworks && (user.item == :LEFTOVERS || (user.item == :BLACKSLUDGE && user.pbHasType?(:POISON)))
		healing += 0.0625 if user.hasWorkingAbility(:RAINDISH) && [:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(user.effectiveWeather)
		healing += 0.0625 if  user.hasWorkingAbility(:ICEBODY) && [:Hail, :FreezingRain, :FrozenStorm].include?(user.effectiveWeather)
		healing += 0.125 if user.status == :POISON && user.hasWorkingAbility(:POISONHEAL)
		healing += 0.125 if (target.effects[PBEffects::LeechSeed]>-1 && !target.hasWorkingAbility(:LIQUIDOOZE)) 
		healing*=0 if user.effects[PBEffects::HealBlock]>0
		return healing if heal
		if !(user.hasWorkingAbility(:MAGICGUARD)) 
			if !(attitemworks && user.item == :SAFETYGOGGLES) || !(user.hasWorkingAbility(:OVERCOAT)) 
				weatherchip = 0
				weatherchip += 0.0625 if [:Sun, :HarshSun, :HolyInferno].include?(user.effectiveWeather) && user.hasWorkingAbility(:DRYSKIN)
				if @battle.pbWeather==:Sandstorm && !(user.pbHasType?(:ROCK) || user.pbHasType?(:STEEL) || user.pbHasType?(:GROUND)) && !(user.hasWorkingAbility(:SANDVEIL) || user.hasWorkingAbility(:SANDFORCE) || user.hasWorkingAbility(:SANDRUSH))				 
					weatherchip += 0.0625
				end	
				if @battle.pbWeather==:FreezingRain && !(user.pbHasType?(:ICE)) && !(user.pbHasType?(:WATER)) && !(user.hasWorkingAbility(:ICEBODY) || user.hasWorkingAbility(:SNOWCLOAK) || user.hasWorkingAbility(:SLUSHRUSH)) 				 				 
					weatherchip += 0.0625
				end	 
				chip += weatherchip
			end
			if user.effects[PBEffects::Trapping]>0
				multiturnchip = 0.125 
				multiturnchip *= 1.3333 if (target.item == :BINDINGBAND)
				chip+=multiturnchip
			end
			chip += 0.125 if (user.effects[PBEffects::LeechSeed]>=0 || (target.effects[PBEffects::LeechSeed]>=0 && target.hasWorkingAbility(:LIQUIDOOZE))) 
			chip += 0.25  if (user.effects[PBEffects::Curse]) 
			if @battle.pbWeather == :HolyInferno && user.takesHolyInfernoDamage?
				# Fire Damage check
				bTypes = user.pbTypes(true)
				eff = Effectiveness.calculate(:FIRE, bTypes[0], bTypes[1], bTypes[2])
				eff *= 2 if user.hasActiveAbility?(:FLUFFY)
				amt = (1.0*eff) / 32
				chip += amt
			end
			if user.status!=:NONE && !rest
				statuschip = 0
				statuschip += 0.0625 if user.status==:BURN 
				statuschip += 0.125 if ((user.status==:POISON &&  !user.hasWorkingAbility(:POISONHEAL) && user.effects[PBEffects::Toxic]==0)) || (user.status == :SLEEP && target.hasWorkingAbility(:BADDREAMS)) 
				statuschip += (0.0625*user.effects[PBEffects::Toxic]) if user.effects[PBEffects::Toxic]!=0 && !(user.hasWorkingAbility(:POISONHEAL)) 
				chip+=statuschip
			end
		end
		return chip if chips
		diff=(healing-chip)
		return diff if both
	end

	def resistBerryType(user)
		return :NONE if !user.itemActive?
		case user.item_id
		when :BABIRIBERRY
			return :STEEL
		when :SHUCABERRY
			return :GROUND
		when :CHARTIBERRY
			return :ROCK
		when :CHOPLEBERRY
			return :FIGHTING
		when :COBABERRY
			return :FLYING
		when :COLBURBERRY
			return :DARK
		when :HABANBERRY
			return :DRAGON
		when :KASIBBERRY
			return :GHOST
		when :KEBIABERRY
			return :POISON
		when :OCCABERRY
			return :FIRE
		when :PASSHOBERRY
			return :WATER
		when :PAYAPABERRY
			return :PSYCHIC
		when :RINDOBERRY
			return :GRASS
		when :ROSELIBERRY
			return :FAIRY
		when :TANGABERRY
			return :BUG
		when :WACANBERRY
			return :ELECTRIC
		when :YACHEBERRY
			return :ICE
		else
			return :NONE
		end
	end
	
end
