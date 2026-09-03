class Battle::AI
	#=============================================================================
	# Main move-choosing method (moves with higher scores are more likely to be
	# chosen)
	#=============================================================================
	def pbChooseMoves(idxBattler)
		user        = @battle.battlers[idxBattler]
		wildBattler = user.wild?
		skill       = 0
		if !wildBattler
			skill     = @battle.pbGetOwnerFromBattlerIndex(user.index).skill_level || 0
		end
		# Get scores and targets for each move
		# NOTE: A move is only added to the choices array if it has a non-zero
		#       score.
		choices     = []
		if !wildBattler
			echo("\n\nDamage calculations for: "+user.name+"\n")
			echo("------------------------------------------")
			
			wide = 0
			chance=50
			case $PokemonGlobal.difficulty
			when 0
				chance = 30
			when 2
				chance = 70
			end
			@battle.allBattlers.each do |b|
				if user.opposes?(b) && b.pbHasMoveFunction?("ProtectUserSideFromMultiTargetDamagingMoves")
					if pbAIRandom(100) < chance && @battle.choices[b.index][0]==:UseMove
						wide = 2 if @battle.choices[b.index][2].function=="ProtectUserSideFromMultiTargetDamagingMoves"
					else
						wide = 1
					end
				end
			end
			doublesthreats=calcDoublesThreats(user,skill)
		end
		user.eachMoveWithIndex do |_m, i|
			next if !@battle.pbCanChooseMove?(idxBattler, i, false)
			if wildBattler
				pbRegisterMoveWild(user, i, choices)
			else
				pbRegisterMoveTrainer(user, i, choices, skill,doublesthreats,wide)
			end
		end
		if !wildBattler
			echo("\nChoices and scores:\n") #for: "+user.name+"\n")
			echo("------------------------\n")#----------------\n")
		end
		# Figure out useful information about the choices
		totalScore = 0
		maxScore   = 0
		choices.each do |c|
			totalScore += c[1]
			if !wildBattler
				echo(c[3]+": "+c[1].to_s+"\n")
			end
			maxScore = c[1] if maxScore < c[1]
		end		
		# DemICE: Item usage AI has been moved here.
		if  $PokemonGlobal.bag_ban != 0
			item, idxTarget = pbEnemyItemToUse(idxBattler)
			if item
				if item[0]
					# Determine target of item (always the Pokémon choosing the action)
					useType = GameData::Item.get(item[0]).battle_use
					if [1, 2, 3, 6, 7, 8].include?(useType)   # Use on Pokémon
						idxTarget = @battle.battlers[idxTarget].pokemonIndex   # Party Pokémon
					end
					party = @battle.pbParty(idxBattler)
					if user.pokemonIndex == 0 && party.length>1
						item[1] *= 0.1 
						echo(item[0].name+": "+item[1].to_s+" discourage item usage on lead.\n")
					end
					if item[1]>maxScore
						# Register use of item
						@battle.pbRegisterItem(idxBattler,item[0],idxTarget)
						PBDebug.log("[AI] #{user.pbThis} (#{user.index}) will use item #{GameData::Item.get(item[0]).name}")
						return
					end
				end	
			end
		end
		# Log the available choices
		if $INTERNAL
			logMsg = "[AI] Move choices for #{user.pbThis(true)} (#{user.index}): "
			choices.each_with_index do |c, i|
				logMsg += "#{user.moves[c[0]].name}=#{c[1]}"
				logMsg += " (target #{c[2]})" if c[2] >= 0
				logMsg += ", " if i < choices.length - 1
			end
			PBDebug.log(logMsg)
		end
		# Find any preferred moves and just choose from them
		if !wildBattler && skill >= PBTrainerAI.highSkill && maxScore > 100
			#stDev = pbStdDev(choices)
			#if stDev >= 40 && pbAIRandom(100) < 90
			# DemICE removing randomness of AI
			preferredMoves = []
			choices.each do |c|
				next if c[1] < 200 && c[1] < maxScore * 0.8
				#preferredMoves.push(c)
				# DemICE prefer ONLY the best move
				preferredMoves.push(c) if c[1] == maxScore   # Doubly prefer the best move
			end
			if preferredMoves.length > 0
				m = preferredMoves[pbAIRandom(preferredMoves.length)]
				PBDebug.log("[AI] #{user.pbThis} (#{user.index}) prefers #{user.moves[m[0]].name}")
				@battle.pbRegisterMove(idxBattler, m[0], false)
				@battle.pbRegisterTarget(idxBattler, m[2]) if m[2] >= 0
				return
			end
			#end
		end
		# Decide whether all choices are bad, and if so, try switching instead
		if !wildBattler && skill >= PBTrainerAI.highSkill
			badMoves = false
			if ((maxScore <= 20 && user.turnCount > 2) ||
					(maxScore <= 40 && user.turnCount > 5)) #&& pbAIRandom(100) < 80  # DemICE removing randomness
				badMoves = true
			end
			if !badMoves && totalScore < 100 && user.turnCount >= 1
				badMoves = true
				choices.each do |c|
					next if !user.moves[c[0]].damagingMove?
					badMoves = false
					break
				end
				#badMoves = false if badMoves && pbAIRandom(100) < 10 # DemICE removing randomness
			end
			if badMoves && pbEnemyShouldWithdrawEx?(idxBattler, false)
				if $INTERNAL
					echo("\nWill switch due to terrible moves.\n")
					#PBDebug.log("[AI] #{user.pbThis} (#{user.index}) will switch due to terrible moves")
				end
				return
			end
		end
		# If there are no calculated choices, pick one at random
		if choices.length == 0
			PBDebug.log("[AI] #{user.pbThis} (#{user.index}) doesn't want to use any moves; picking one at random")
			user.eachMoveWithIndex do |_m, i|
				next if !@battle.pbCanChooseMove?(idxBattler, i, false)
				choices.push([i, 100, -1])   # Move index, score, target
			end
			if choices.length == 0   # No moves are physically possible to use; use Struggle
				@battle.pbAutoChooseMove(user.index)
			end
		end
		# Randomly choose a move from the choices and register it
		randNum = pbAIRandom(totalScore)
		choices.each do |c|
			randNum -= c[1]
			next if randNum >= 0
			@battle.pbRegisterMove(idxBattler, c[0], false)
			@battle.pbRegisterTarget(idxBattler, c[2]) if c[2] >= 0
			break
		end
		# Log the result
		if @battle.choices[idxBattler][2]
			PBDebug.log("[AI] #{user.pbThis} (#{user.index}) will use #{@battle.choices[idxBattler][2].name}")
		end
	end
	
	# Trainer Pokémon calculate how much they want to use each of their moves.
	def pbRegisterMoveTrainer(user, idxMove, choices, skill,doublesthreats,wide=0)
		move = user.moves[idxMove]
		target_data = move.pbTarget(user)
		darts=false
		target=user.pbDirectOpposing
		darts=true if target.allAllies.length > 0 && move.function == "HitTwoTimesTargetThenTargetAlly"
		if [:UserAndAllies, :AllAllies, :AllBattlers].include?(target_data.id) ||
			target_data.num_targets == 0
			# If move has no targets, affects the user, a side or the whole field, or
			# specially affects multiple Pokémon and the AI calculates an overall
			# score at once instead of per target
			score = pbGetMoveScore(move, user, user, skill,idxMove)
			choices.push([idxMove, score, -1, move.name]) if score > 0
		elsif target_data.num_targets > 1 || darts
			# If move affects multiple battlers and you don't choose a particular one
			totalScore = 100
			count=0
			theresone=false
			@battle.allBattlers.each do |b|
				next if !@battle.pbMoveCanTarget?(user.index, b.index, target_data)
				score = pbGetMoveScore(move, user, b, skill,idxMove)
				theresone=true if score>200 && user.opposes?(b)
				score-=100 
				score=0 if score <0 && !user.opposes?(b)
				totalScore += ((user.opposes?(b)) ? score : -score)
				count+=1
			end
			totalScore+=100 if theresone && count>1
			totalScore *= 0.5 if wide == 1
			totalScore = 0 if wide == 2
			choices.push([idxMove, totalScore, -1, move.name]) if totalScore > 0
		else
			# If move affects one battler and you have to choose which one
			scoresAndTargets = []
			@battle.allBattlers.each do |b|
				doublesthreat = doublesthreats[b.index]
				next if !@battle.pbMoveCanTarget?(user.index, b.index, target_data)
				next if target_data.targets_foe && !user.opposes?(b)
				score = pbGetMoveScore(move, user, b, skill,idxMove)
				indexopp=b.index
				if skill >= PBTrainerAI.mediumSkill 
					if move.function == "FailsIfTargetActed" && user.index>indexopp  # Sucker Punch
						aspeed = pbRoughStat(user,:SPEED,skill)
						ospeed = pbRoughStat(b,:SPEED,skill)
						chance=50
						case $PokemonGlobal.difficulty
						when 0
							chance = 30
						when 2
							chance = 70
						end
						if @battle.choices[indexopp][0]!=:UseMove
							if pbAIRandom(100) < chance	# Try play "mind games" instead of just getting baited every time.
								echo("\n'Predicting' that opponent will not attack and sucker will fail")
								score = 0
							end
						else
							if @battle.choices[indexopp][1]
								if pbAIRandom(100) < chance && ( # Try play "mind games" instead of just getting baited every time.
									!@battle.choices[indexopp][2].damagingMove? ||
									(priorityAI(target,@battle.choices[indexopp][2])==1 && ((aspeed<=ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))) ||
									priorityAI(target,@battle.choices[indexopp][2])>1
									)
									 echo("\n'Predicting' that opponent will not attack and sucker will fail")
									 score = 0
								end
							end
						end
					end
				end
				if @battle.pbSideBattlerCount(b) > 1 && user.opposes?(b)
					if score > 200
						doublesthreat += 1 * b.stages[:DEFENSE]
						doublesthreat += 1 * b.stages[:SPECIAL_DEFENSE]
						score += doublesthreat
					else
						if score < 198
							score += doublesthreat 
							score = 198 if score > 198
						end
					end
				end
				if user.opposes?(b) && b.pbOwnedByPlayer?
					if b.allAllies.length > 0
						b.allAllies.each do | a |
							if pbCheckMoveImmunity(score, move, user, a, skill)
								score -=2 
							else
								type = pbRoughType(move,user,skill)
								typeMod = pbCalcTypeMod(type,user,a)
								score -=0.5 if Effectiveness.resistant?(typeMod) && move.baseDamage>0
							end
						end
					end
					party = @battle.pbParty(b.index)
					inBattleIndices = @battle.allSameSideBattlers(b.index).map { |b| b.pokemonIndex }
					party.each_with_index do |pkmn, idxParty|
						next if !pkmn || !pkmn.able?
						next if inBattleIndices.include?(idxParty)
						dummy = @battle.pbMakeFakeBattler(party[idxParty],false,b) 
						if pbCheckMoveImmunity(score, move, user, dummy, skill)
							score -=2 
						else
							type = pbRoughType(move,user,skill)
							typeMod = pbCalcTypeMod(type,user,dummy)
							score -=0.5 if Effectiveness.resistant?(typeMod) && move.baseDamage>0
						end
					end
				end
				scoresAndTargets.push([score, b.index]) if score > 0
			end
			if scoresAndTargets.length > 0
				# Get the one best target for the move
				scoresAndTargets.sort! { |a, b| b[0] <=> a[0] }
				choices.push([idxMove, scoresAndTargets[0][0], scoresAndTargets[0][1], move.name])
			end
		end
	end
	
	# DemICE attempt for the AI to access threats better in doubles.
	def calcDoublesThreats(user,skill=100)
		threathash = {}
		@battle.allBattlers.each do |target|
			next if !user.opposes?(target)
			aspeed = pbRoughStat(user,:SPEED,skill)
			ospeed = pbRoughStat(target,:SPEED,skill)
			increment=0
			threathash[target.index] = increment
			if @battle.pbSideBattlerCount(target) > 1
				maxmaxdam=0
				maxoppphysspec= ""
				@battle.allSameSideBattlers(user.index).each do |b|
					maxoppdam=0
					maxoppidx=0
					bestoppmove=bestMoveVsTarget(target,b,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxoppdam=bestoppmove[0] 
					maxoppidx=bestoppmove[4] 
					maxoppmove=bestoppmove[1]
					maxoppprio=bestoppmove[2]
					if maxoppdam >= maxmaxdam
						maxmaxdam=maxoppdam 
						maxoppphysspec=bestoppmove[3]
					end
					survives = targetSurvivesMove(maxoppmove,maxoppidx,target,b)
					damagePercentage = maxoppdam * 100.0 / b.hp
					damagePercentage = 110 if damagePercentage > 100
					damagePercentage = 100 if survives
					increment += damagePercentage*0.01
				end
				#echo("\nDoubles Threat Level boost for "+target.name+": "+increment.to_s+"\n")
				if maxoppphysspec=="physical"
					increment += 1 * target.stages[:ATTACK]  
				else
					increment += 0.5 * target.stages[:ATTACK]  
				end
				if maxoppphysspec=="special"
					increment += 1 * target.stages[:SPECIAL_ATTACK]
				else
					increment += 0.5 * target.stages[:SPECIAL_ATTACK]
				end
				enemies = []
				ownparty = @battle.pbParty(user.index)
				ownparty.each_with_index do |ptmon,i|
					enemies.push(i) if ptmon.hp>0
				end
				#echo("\nDoubles Threat Level boost for "+target.name+": "+increment.to_s+"\n")
				speedsarray = pbChooseBestNewEnemy(user.index,ownparty,enemies,false,-1,false,true)
				speedsarray.each do | speed |
					increment +=1 if ((ospeed>speed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				end
				#increment = 0 if increment < 0
				echo("\nDoubles Threat Level boost for "+target.name+": "+increment.to_s+"\n")
				threathash[target.index] = increment
			end
		end
		return threathash
	end

	#=============================================================================
	# Get a score for the given move being used against the given target
	#=============================================================================
	def pbGetMoveScore(move, user, target, skill = 100,idxmove=0,doublesthreat=0)
		skill = 100#PBTrainerAI.minimumSkill if skill < PBTrainerAI.minimumSkill
		score = 100
		functionscore = pbGetMoveScoreFunctionCode(score, move, user, target, skill,idxmove)
		bsdam=pbMoveBaseDamage(move,user,target,skill)
		bsdiv=10.0/bsdam
		functionscore*= bsdiv if move.baseDamage>50 && move.priority == 0
		#print functionscore
		# A score of 0 here means it absolutely should not be used
		return 0 if score <= 0
		# Adjust score based on how much damage it can deal
		# DemICE moved damage calculation to the beginning
			# Account for accuracy of move
			accuracy = pbRoughAccuracy(move, user, target, skill)
			accuracy=100 if accuracy>100
		if move.damagingMove?
			damage = pbGetMoveScoreDamage(score, move, user, target, skill,idxmove)
			bestmove = bestMoveVsTarget(user,target,skill)
			maxdam=bestmove[0] 
			maxidx=bestmove[4]
			maxmove=bestmove[1]
			maxprio=bestmove[2]
			score+=functionscore if (damage <100 || move.priority > 0) && !(user.hasActiveAbility?(:SHEERFORCE) && move.addlEffect>0) && targetSurvivesMove(maxmove,maxidx,user,target,maxprio)
			score+= damage
			return 0 if score <= 0
			score -= (100-accuracy)*0.3 if accuracy < 100  # DemICE
		else   # Status moves
			score+=functionscore
			return 0 if score <= 0
			# Don't prefer attacks which don't deal damage
			score -= 10
			score *= accuracy / 100.0
			score = 0 if score <= 10 && skill >= PBTrainerAI.highSkill
		end
		aspeed = pbRoughStat(user,:SPEED,100)
		ospeed = pbRoughStat(target,:SPEED,100)
		if skill >= PBTrainerAI.mediumSkill
			# Prefer damaging moves if AI has no more Pokémon or AI is less clever
			# if @battle.pbAbleNonActiveCount(user.idxOwnSide) == 0 &&
			#    !(skill >= PBTrainerAI.highSkill && @battle.pbAbleNonActiveCount(target.idxOwnSide) > 0)
			#   if move.statusMove?
			#     score /= 1.5
			#   elsif target.hp <= target.totalhp / 2
			#     score *= 1.5
			#   end
			# end
			# Converted all score alterations to multiplicative
			# Don't prefer attacking the target if they'd be semi-invulnerable
			if skill >= PBTrainerAI.highSkill && move.accuracy > 0 &&
				(target.semiInvulnerable? || target.effects[PBEffects::SkyDrop] >= 0)
				miss = true
				miss = false if user.hasActiveAbility?(:NOGUARD) || target.hasActiveAbility?(:NOGUARD)
				miss = false if ((aspeed<=ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) && priorityAI(user,move)<1 # DemICE
				if miss && pbRoughStat(user, :SPEED, skill) > pbRoughStat(target, :SPEED, skill)
					# Knows what can get past semi-invulnerability
					if target.effects[PBEffects::SkyDrop] >= 0 ||
						target.inTwoTurnAttack?("TwoTurnAttackInvulnerableInSky",
							"TwoTurnAttackInvulnerableInSkyParalyzeTarget",
							"TwoTurnAttackInvulnerableInSkyTargetCannotAct")
						miss = false if move.hitsFlyingTargets?
					elsif target.inTwoTurnAttack?("TwoTurnAttackInvulnerableUnderground")
						miss = false if move.hitsDiggingTargets?
					elsif target.inTwoTurnAttack?("TwoTurnAttackInvulnerableUnderwater")
						miss = false if move.hitsDivingTargets?
					end
				end
				score *= 0.2 if miss
			end
			# Pick a good move for the Choice items
			if user.hasActiveItem?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF]) ||
				user.hasActiveAbility?(:GORILLATACTICS)
				if move.baseDamage >= 60
					score *= 1.2
				elsif move.damagingMove?
					score *= 1.2
				elsif move.function == "UserTargetSwapItems"
					score *= 1.2  # Trick
				else
					score *= 0.8
				end
			end
			# If user is asleep, prefer moves that are usable while asleep
			if user.status == :SLEEP && !move.usableWhenAsleep? && user.statusCount==1 # DemICE check if it'll wake up this turn
				user.eachMove do |m|
					next unless m.usableWhenAsleep?
					score *= 2
					break
				end
			end
			# If user is frozen, prefer a move that can thaw the user
			if user.status == :FROZEN
				if move.thawsUser?
					score *= 2
				else
					user.eachMove do |m|
						next unless m.thawsUser?
						score *= 0.8
						break
					end
				end
			end
			# If target is frozen, don't prefer moves that could thaw them
			if target.status == :FROZEN
				user.eachMove do |m|
					next if m.thawsUser?
					score *= 0.3 if score<120
					break
				end
			end
		end
		# Don't prefer moves that are ineffective because of abilities or effects
		return 0 if pbCheckMoveImmunity(score, move, user, target, skill)
		#score = score.to_i
		score = 0 if score < 0
		return score
	end
	
	#=============================================================================
	# Add to a move's score based on how much damage it will deal (as a percentage
	# of the target's current HP)
	#=============================================================================
	def pbGetMoveScoreDamage(score, move, user, target, skill,idxmove=0,doublesthreat=0)
		return 0 if score <= 0 || pbCheckMoveImmunity(score,move,user,target,skill)
		# Calculate how much damage the move will do (roughly)
		#baseDmg = pbMoveBaseDamage(move, user, target, skill)
		realDamage = @damagesAI[user.index][idxmove][:dmg][target.index] #pbRoughDamage(move, user, target, skill)#, baseDmg)  # DemICE Moved the baseDmg calculation inside pbRoughDamage
		return 0 if realDamage == 0
		#realDamage*=0.9 #DemICE encourage AI to use stronger moves to avoid opponent surviving from low damage roll.
		echo("\n"+move.name+" damage on "+target.name+": "+realDamage.to_s+" / "+target.hp.to_s+"\n")
		# Account for accuracy of move
		accuracy = pbRoughAccuracy(move, user, target, skill)
		accuracy=100 if accuracy>100
		#realDamage *= accuracy / 100.0 # DemICE
		aspeed = pbRoughStat(user,:SPEED,skill)
		ospeed = pbRoughStat(target,:SPEED,skill)
		mold_broken=moldbroken(user,target,move)
		bestoppmove=bestMoveVsTarget(target,user,skill) # [maxdam,maxmove,maxprio,physorspec]
		maxoppdam=bestoppmove[0] 
		maxoppidx=bestoppmove[4] 
		maxoppmove=bestoppmove[1]
		maxoppprio=bestoppmove[2]
		maxoppphysspec=bestoppmove[3]
		halfhealth= user.hp/2
		# Two-turn attacks waste 2 turns to deal one lot of damage
		if ((["TwoTurnAttackFlinchTarget", "TwoTurnAttackParalyzeTarget", 
			"TwoTurnAttackBurnTarget", "TwoTurnAttackChargeRaiseUserDefense1", "TwoTurnAttack", 
			"AttackTwoTurnsLater", "TwoTurnAttackChargeRaiseUserSpAtk1"].include?(move.function)  ||
			(move.function=="TwoTurnAttackOneTurnInSun" && ![:Sun, :HarshSun, :HolyInferno].include?(user.effectiveWeather)) ||
			(move.function=="TwoTurnAttackChargeRaiseUserSpAtk1OneTurnInRain" && ![:Rain, :HeavyRain, :FreezingRain, :FrozenStorm].include?(user.effectiveWeather))) && 
			!user.hasActiveItem?(:POWERHERB) && !user.hasActiveItem?(:POWERPACK) && !(user.isSpecies?(:MOLTRES) && user.hasActiveItem?(:ARDENTORB) && user.form == 0))
		  realDamage *= 2 / 3   # Not halved because semi-invulnerable during use or hits first turn
		  realDamage = 0 if target.pbHasMoveFunction?("ProtectUser", "ProtectUserFromTargetingMovesSpikyShield", "ProtectUserBanefulBunker", "ProtectUserFromDamagingMovesKingsShield", "ProtectUserFromDamagingMovesObstruct")	
		end
		if move.function == "AttackAndSkipNextTurn" && !user.hasActiveItem?(:BATTERYPACK) # Ashen Frost exclusive
			if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				if targetSurvivesMove(maxoppmove,maxoppidx,target,user,maxoppprio)
					realDamage *= 0.5
				end
			else
				if targetSurvivesMove(maxoppmove,maxoppidx,target,user,0,2)
					realDamage *= 0.5
				end
			end
		end
		# Brick Break, Raging Bull
		if (user.pbOpposingSide.effects[PBEffects::AuroraVeil] > 0 || user.pbOpposingSide.effects[PBEffects::Reflect] > 0 || user.pbOpposingSide.effects[PBEffects::LightScreen] > 0) &&
			["RemoveScreens", "TypeIsUserSecondTypeRemoveScreens"].include?(move.function) 
			realDamage*=2 
		end
		if skill >= PBTrainerAI.mediumSkill 
		# flinching are dealt with in the function code part of score calculation)
			if move.function =="PowerHigherWithUserHP" # Eruption / Water Spout after expected damage
				newhp = user.hp
				if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
					newhp -= maxoppprio
				else
					newhp -= maxoppdam
				end
				realDamage = [realDamage * newhp / user.hp, 1].max
			end
			if move.function == "UserFaintsExplosive"
				foes     = @battle.pbAbleNonActiveCount(user.idxOpposingSide)
				if foes != 0
					if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						if targetSurvivesMove(maxoppmove,maxoppidx,target,user,maxoppprio)
							realDamage *= 0.2
						end
					else
						if targetSurvivesMove(maxoppmove,maxoppidx,target,user,0,2)
							realDamage *= 0.2
						end
					end
				end	
			end
			# Prefer flinching external effects (note that move effects which cause
			if ((!target.hasActiveAbility?(:INNERFOCUS) && !target.hasActiveAbility?(:SHIELDDUST)) || mold_broken) &&
				target.effects[PBEffects::Substitute]==0 &&
				((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
				canFlinch = false
				if user.hasActiveItem?([:KINGSROCK,:RAZORFANG])
					canFlinch = true
				end
				if user.hasActiveAbility?(:STENCH) || move.flinchingMove?
					canFlinch = true
				end
				bestmove=bestMoveVsTarget(user,target,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] #* 0.9
				maxidx=bestmove[4]
				maxmove=bestmove[1]
				if targetSurvivesMove(maxmove,maxidx,user,target) && canFlinch
					realDamage *= 1.2 if (realDamage *100.0 / maxdam) > 75
					realDamage *= 1.6 if move.function=="HitTwoTimesFlinchTarget" || (move.function=="HitTwoToFiveTimes" && user.hasActiveItem?([:KINGSROCK,:RAZORFANG])) && user.hasActiveAbility?(:SKILLLINK)
					realDamage*=2 if user.hasActiveAbility?(:SERENEGRACE)
					realDamage = target.hp * 0.99 if realDamage >= target.hp
				end
			end
			# Try make AI not trolled by disguise
			if !mold_broken && target.hasActiveAbility?(:DISGUISE) && target.turnCount==0	
				if ["HitTwoToFiveTimes", "HitTwoTimes", "HitThreeTimes" ,"HitTwoTimesFlinchTarget", "HitThreeTimesPowersUpWithEachHit", "HitTenTimes"].include?(move.function)
					realDamage*=2.2
				end
			end	
			if !mold_broken && target.hasActiveAbility?(:ICEFACE) && move.physicalMove? && target.form==0
				if ["HitTwoToFiveTimes", "HitTwoTimes", "HitThreeTimes" ,"HitTwoTimesFlinchTarget", "HitThreeTimesPowersUpWithEachHit", "HitTenTimes"].include?(move.function)
					realDamage*=2.2
				end
			end	
		end
		# Convert damage to percentage of target's remaining HP
		damagePercentage = realDamage * 100.0 / target.hp
		reflect = 0
		if move.pbContactMove?(user)
			if target.hasActiveAbility?([:IRONBARBS,:ROUGHSKIN]) || target.hasActiveItem?(:ROCKYHELMET)
				if target.hasActiveAbility?([:IRONBARBS,:ROUGHSKIN])
					reflect = 12.5#user.totalhp/8
				else
					reflect = 16.7#user.totalhp/6
				end
				case move.function
				when "HitThreeTimesAlwaysCriticalHit" # DemICE Surging strikes
					reflect *= 3
				when "HitTwoTimes", "HitTwoTimesPoisonTarget"
					reflect *= 2
				when "HitTwoToFiveTimes", "HitTwoToFiveTimesRaiseUserSpd1LowerUserDef1"   # DemICE implementing multihit moves probably
				  if user.hasActiveAbility?(:SKILLLINK)
					reflect *= 5
				  elsif user.hasActiveItem?(:LOADEDDICE)
					reflect *= 4
				  else
					reflect = (reflect * 31 / 10).floor   # Average damage dealt
				  end
				when "HitTenTimes"
					accuracy = pbRoughAccuracy(move, user, target, skill)
					if accuracy>=99
						reflect*=10
					else
						reflect*=6
					end
				when "HitThreeTimesPowersUpWithEachHit"   # Triple Kick
					reflect *= 3   # Hits do x1, x2, x3 baseDmg in turn, for x6 in total
				when "HitTwoTimesFlinchTarget"   # Double Iron Bash
					reflect *= 2
				end
				if targetSurvivesMove(maxoppmove,maxoppidx,target,user,maxoppprio)
					damagePercentage -= reflect
					damagePercentage *= 0.6 if (user.hasActiveItem?(:FOCUSSASH) || user.hasActiveAbility?(:STURDY)) && (user.hp == user.totalhp)
				end
				hpreflected = reflect * user.totalhp / 100
				damagePercentage *= 0.3 if hpreflected > user.totalhp
			end
		end
		# Don't prefer weak attacks
		#    damagePercentage /= 2 if damagePercentage<20
		# Prefer damaging attack if level difference is significantly high
		#damagePercentage *= 1.2 if user.level - 10 > target.level
		# Adjust score
		damagePercentage = 110 if ["OHKO","OHKOIce","OHKOHitsUndergroundTarget"].include?(move.function) && (user.effects[PBEffects::LockOn]>0 || target.effects[PBEffects::GlaiveRush] > 0)
		if damagePercentage > 100   # Treat all lethal moves the same   # DemICE
			damagePercentage = 110 
			# Changed by DemICE 22-Sep-2023 Soulstones 2 Specific.
			if ["RaiseUserAttack3IfTargetFaints", "RaiseUserSpAtk3IfTargetFaints"].include?(move.function) # DemICE: Fell Stinger should be preferred among other moves that KO
				if user.hasActiveAbility?(:CONTRARY)
					damagePercentage-=90    
				else
					damagePercentage+=50    
				end
			end
			if move.function == "RaiseUserStat1Commander" && user.isCommanderHost?
				if user.hasActiveAbility?(:CONTRARY)
					damagePercentage-=90    
				else
					damagePercentage+=50    
				end
			end
			damagePercentage+=30  if move.function == "FailsIfNotUserFirstTurn"
			if (["HealUserByHalfOfDamageDone","HealUserByThreeQuartersOfDamageDone"].include?(move.function) || move.function == "HealUserByHalfOfDamageDoneIfTargetAsleep" && target.asleep?) &&
				!target.hasActiveAbility?(:LIQUIDOOZE) # Prefer draining move if on low HP.
				missinghp = (user.totalhp-user.hp) *100.0 / user.totalhp
				damagePercentage += missinghp*0.5
			end  
			if ["OHKO","OHKOHitsUndergroundTarget","OHKOIce"].include?(move.function)
				if user.effects[PBEffects::LockOn]>0
					damagePercentage = 280
				else
					damagePercentage -=10
				end
			end
			if ["RecoilHalfOfDamageDealt","RecoilThirdOfDamageDealtParalyzeTarget","RecoilHalfOfDamageDealt", 
				"RecoilThirdOfDamageDealtBurnTarget", "RecoilThirdOfDamageDealt"].include?(move.function) &&
				!user.hasActiveAbility?([:ROCKHEAD, :MAGICGUARD]) && !user.hasActiveItem?(:CRASHTESTHELMET)
				damagePercentage -=5
			end
			if ["LowerUserSpAtk2", "LowerUserAtkDef1"].include?(move.function)
				if user.hasActiveAbility?(:CONTRARY)
					damagePercentage +=50 
				else
					damagePercentage -=5    
				end
			end
			damagePercentage -= 10 if reflect > 0 
			damagePercentage += 50 if move.soundMove? && user.hasActiveItem?(:THROATSPRAY)
			damagePercentage += 50 if move.function == "TwoTurnAttackChargeRaiseUserSpAtk1" && (user.hasActiveItem?(:POWERPACK) || user.hasActiveItem?(:POWERHERB))
		else
			if move.function == "BurnTarget" && move.addlEffect == 100 && maxoppphysspec=="physical"
				if maxoppdam < halfhealth
					score = 98 
				end
				if !targetSurvivesMove(maxoppmove,maxoppidx,target,user) && targetSurvivesMove(maxoppmove,maxoppidx,target,user,0,0.5) &&
							((aspeed > ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>1)) 
					score = 98 
				end
			end
			if move.function == "LowerTargetAttack1" && move.addlEffect == 100 && maxoppphysspec=="physical"
				if target.hasActiveAbility?([:CONTRARY,:DEFIANT])
					damagePercentage = 0
				else
					if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						if !targetSurvivesMove(maxoppmove,maxoppidx,target,user,maxoppprio) && targetSurvivesMove(maxoppmove,maxoppidx,target,user,maxoppprio,0.7)
							damagePercentage = 98 
						end
					end
				end
			end
			if move.function == "LowerTargetSpAtk1" && move.addlEffect == 100 && maxoppphysspec=="special"
				if target.hasActiveAbility?([:CONTRARY,:COMPETITIVE])
					damagePercentage = 0
				else
					if ((aspeed>ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0))
						if !targetSurvivesMove(maxoppmove,maxoppidx,target,user,maxoppprio) && targetSurvivesMove(maxoppmove,maxoppidx,target,user,maxoppprio,0.7)
							damagePercentage = 98 
						end
					end
				end
			end
			if  ((aspeed<ospeed) ^ (@battle.field.effects[PBEffects::TrickRoom]>0)) &&
				(["HealUserByHalfOfDamageDone","HealUserByThreeQuartersOfDamageDone"].include?(move.function) || move.function == "HealUserByHalfOfDamageDoneIfTargetAsleep" && target.asleep?) &&
				!target.hasActiveAbility?(:LIQUIDOOZE) # Prefer draining move if on low HP.
				missinghp = (user.totalhp-user.hp) *100.0 / user.totalhp
				damagePercentage += 5
				damagePercentage = 98 if damagePercentage > 98
			end  
			#---------------------------------------------------------------------------
			if move.function ==  "SwitchOutUserDamagingMove"  # U-Turn , Volt Switch , Flip Turn
				damagePercentage *= 0.5 if user.pbOwnSide.effects[PBEffects::StealthRock] || user.pbOwnSide.effects[PBEffects::ToxicSpikes]>0 ||
				user.pbOwnSide.effects[PBEffects::Spikes]>0 || user.pbOwnSide.effects[PBEffects::StickyWeb]
				if aspeed>ospeed && !(target.status == :SLEEP && target.statusCount>1)
					damagePercentage *= 0.5  # DemICE: Switching AI is dumb so if you're faster, don't sack a healthy mon. Better use another move.
				else
					damagePercentage *= 1.2 if user.hasActiveAbility?(:REGENERATOR)
					damagePercentage = 98 if user.effects[PBEffects::Toxic]>3
					damagePercentage = 98 if user.effects[PBEffects::Curse]
					damagePercentage = 98 if user.effects[PBEffects::PerishSong]==1
					damagePercentage = 98 if user.effects[PBEffects::LeechSeed]>0
					bestmove=bestMoveVsTarget(user,target,skill) # [maxdam,maxmove,maxprio,physorspec]
					maxdam=bestmove[0] #* 0.9
					maxmove=bestmove[1]
					thirdopphealth = target.hp  / 3
					damagePercentage = 98 if maxdam < thirdopphealth
				end   
			end
			# Order Up    
			# I commented it out and left it for another time because it seemed like a pain in the ass and i wasnt feeling like it at that moment.
			# if move.function == "RaiseUserStat1Commander" && !user.hasActiveAbility?(:CONTRARY)
			# 	if user.isCommanderHost?
			# 	  form = user.effects[PBEffects::Commander][1]
			# 	  stat = [:ATTACK, :DEFENSE, :SPEED][form]
			# 	  case stat
			# 	  when :ATTACK
			# 		if !user.statStageAtMax?(:ATTACK) 
			# 	  end
			# 	end
			# end
			damagePercentage = 190 if move.soundMove? && user.hasActiveItem?(:THROATSPRAY) && damagePercentage > 10 
			if move.function == "TwoTurnAttackChargeRaiseUserSpAtk1" && (user.hasActiveItem?(:POWERPACK) || user.hasActiveItem?(:POWERHERB))
				bestmove=bestMoveVsTarget(user,target,skill) # [maxdam,maxmove,maxprio,physorspec]
				maxdam=bestmove[0] #* 0.9
				maxownspec=bestmove[3]
				#if maxownspec == "special"
				if !user.statStageAtMax?(:SPECIAL_ATTACK) && !user.hasActiveAbility?(:CONTRARY) && maxownspec == "special"
					damagePercentage = 90 if maxdam > (target.hp * 0.25) && maxdam < (target.hp * 0.5)
				# else	
				end
			end
		end  
		#damagePercentage -= 1 if accuracy < 100  # DemICE
		#damagePercentage += 40 if damagePercentage > 100   # Prefer moves likely to be lethal  # DemICE
		return damagePercentage
		# regret
		score += damagePercentage
		return score
	end
	
	
end


