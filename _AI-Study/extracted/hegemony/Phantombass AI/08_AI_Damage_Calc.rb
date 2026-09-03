class PBAI
	class AI_Move

		def pbBaseMultipliers
			multipliers = {
	        :base_damage_multiplier  => 1.0,
	        :attack_multiplier       => 1.0,
	        :defense_multiplier      => 1.0,
	        :final_damage_multiplier => 1.0
	      }
			return multipliers
		end
		def pbCalcDamage(user, target, numTargets = 1)
	      return 0 if @move.statusMove?
	      $test_trigger = true
	      if target.damageState.disguise || target.damageState.iceface
	        dmg = 1
	        return dmg
	      end
	      stageMul = [2, 2, 2, 2, 2, 2, 2, 3, 4, 5, 6, 7, 8]
	      stageDiv = [8, 7, 6, 5, 4, 3, 2, 2, 2, 2, 2, 2, 2]
	      # Get the move's type
	      type = @move.calcType   # nil is treated as physical
	      # Calculate whether this hit deals critical damage
	      target.damageState.critical = pbIsCritical?(user, target)
	      # Calcuate base power of move
	      baseDmg = pbBaseDamage(@move.baseDamage, user, target)
	      # Calculate user's attack stat
	      atk, atkStage = pbGetAttackStats(user, target)
	      if !target.hasActiveAbility?(:UNAWARE) || @battle.moldBreaker
	        atkStage = 6 if target.damageState.critical && atkStage < 6
	        atk = (atk.to_f * stageMul[atkStage] / stageDiv[atkStage]).floor
	      end
	      # Calculate target's defense stat
	      defense, defStage = pbGetDefenseStats(user, target)
	      if !user.hasActiveAbility?(:UNAWARE)
	        defStage = 6 if target.damageState.critical && defStage > 6
	        defense = (defense.to_f * stageMul[defStage] / stageDiv[defStage]).floor
	      end
	      # Calculate all multiplier effects
	      multipliers = pbBaseMultipliers
	      mult = pbCalcDamageMultipliers(user, target, numTargets, @move.pbCalcType(user), baseDmg, multipliers)
	      # Main damage calculation
	      baseDmg = [(baseDmg * mult[:base_damage_multiplier]).round, 1].max
	      atk     = [(atk     * mult[:attack_multiplier]).round, 1].max
	      defense = [(defense * mult[:defense_multiplier]).round, 1].max
	      damage  = ((((2.0 * user.level / 5) + 2).floor * baseDmg * atk / defense).floor / 50).floor + 2
	      dmg  = [(damage * mult[:final_damage_multiplier]).round, 1].max
	      $test_trigger = false
	      return dmg
	    end

	    #===========================================#
	    # Multipliers
	    #===========================================#
	    def ruin_mults(user,target,numTargets,type,baseDmg,multipliers)
	      [:TABLETSOFRUIN, :SWORDOFRUIN, :VESSELOFRUIN, :BEADSOFRUIN].each_with_index do |abil, i|
	        category = (i < 2) ? @move.physicalMove? : @move.specialMove?
	        category = !category if i.odd? && @battle.field.effects[PBEffects::WonderRoom] > 0
	        mult = (i.even?) ? multipliers[:attack_multiplier] : multipliers[:defense_multiplier]
	        mult *= 0.75 if @battle.pbCheckGlobalAbility(abil) && !user.hasActiveAbility?(abil) && category
	      end
	  	end

	  	def vocal_fry(user,target,numTargets,type,baseDmg,multipliers)
	  	  if user.hasActiveAbility?(:VOCALFRY) && @move.pbDamagingMove? && @move.soundMove?
	        m = PokeBattle_Move.from_pokemon_move(@battle,Pokemon::Move.new(@move.id))
	        m.category = 0
	      end	        
	    end

	    def global_ability_mults(user,target,numTargets,type,baseDmg,multipliers)
	    	 if (@battle.pbCheckGlobalAbility(:DARKAURA) && type == :DARK) ||
	           (@battle.pbCheckGlobalAbility(:FAIRYAURA) && type == :FAIRY) || (@battle.pbCheckGlobalAbility(:GAIAFORCE) && type == :GROUND) || (@battle.pbCheckGlobalAbility(:FEVERPITCH) && type == :POISON)
	          if @battle.pbCheckGlobalAbility(:AURABREAK)
	            multipliers[:base_damage_multiplier] *= 2 / 3.0
	          else
	            multipliers[:base_damage_multiplier] *= 4 / 3.0
	          end
	        end
	    end

	    def ability_mults(user,target,numTargets,type,baseDmg,multipliers)
	    	effectiveness = Effectiveness::NORMAL_EFFECTIVE_MULTIPLIER
	        # Ability effects that alter damage
	        if user.abilityActive?
	          PBAI::AbilityEffects.triggerDamageCalcFromUser(
	            user.ability, user, target, @move, multipliers, baseDmg, type
	          )
	          PBAI::AbilityEffects.triggerModifyTypeEffectiveness(user.ability, user, target, @move, @battle, effectiveness)
	        end
	        if !@battle.moldBreaker
	          # NOTE: It's odd that the user's Mold Breaker prevents its partner's
	          #       beneficial abilities (i.e. Flower Gift boosting Atk), but that's
	          #       how it works.
	          user.allAllies.each do |b|
	            next if !b.abilityActive?
	            PBAI::AbilityEffects.triggerDamageCalcFromAlly(
	              b.ability, user, target, @move, multipliers, baseDmg, type
	            )
	          end
	          if target.abilityActive?
	            PBAI::AbilityEffects.triggerDamageCalcFromTarget(
	              target.ability, user, target, @move, multipliers, baseDmg, type
	            )
	            PBAI::AbilityEffects.triggerDamageCalcFromTargetNonIgnorable(
	              target.ability, user, target, @move, multipliers, baseDmg, type
	            )
	          end
	          target.allAllies.each do |b|
	            next if !b.abilityActive?
	            PBAI::AbilityEffects.triggerDamageCalcFromTargetAlly(
	              b.ability, user, target, @move, multipliers, baseDmg, type
	            )
	          end
	        end
	    end

	    def item_mults(user,target,numTargets,type,baseDmg,multipliers)
	    	# Item effects that alter damage
	        if user.itemActive?
	          PBAI::ItemEffects.triggerDamageCalcFromUser(
	            user.item, user, target, @move, multipliers, baseDmg, type
	          )
	        end
	        if target.itemActive?
	          PBAI::ItemEffects.triggerDamageCalcFromTarget(
	            target.item, user, target, @move, multipliers, baseDmg, type
	          )
	        end
	    end

	    def second_hit_mults(user,target,numTargets,type,baseDmg,multipliers)
	    	if user.effects[PBEffects::ParentalBond] == 1
	          multipliers[:base_damage_multiplier] /= (Settings::MECHANICS_GENERATION >= 7) ? 4 : 2
	        end
	        if user.effects[PBEffects::EchoChamber] == 1
	          multipliers[:base_damage_multiplier] /= (Settings::MECHANICS_GENERATION >= 7) ? 4 : 2
	        end
	        if user.effects[PBEffects::Ambidextrous] == 1
	          multipliers[:base_damage_multiplier] /= (Settings::MECHANICS_GENERATION >= 7) ? 4 : 2
	        end
	    end

	    def misc_mults(user, target, numTargets, type, baseDmg, multipliers)
	    	if [PBEffects::Protect,PBEffects::CraftyShield,PBEffects::KingsShield,PBEffects::WideGuard,PBEffects::QuickGuard,PBEffects::SilkTrap,PBEffects::BurningBulwark,
		      PBEffects::BanefulBunker,PBEffects::MatBlock,PBEffects::SpikyShield].include?(target.effects) && user.hasActiveAbility?([:UNSEENFIST,:PIERCINGDRILL]) && @move.contactMove?
		      multipliers[:final_damage_multiplier] /= 4
		    end
	    	if user.effects[PBEffects::MeFirst]
	          multipliers[:base_damage_multiplier] *= 1.5
	        end
	        if user.effects[PBEffects::HelpingHand] && !@move.is_a?(PokeBattle_ConfuseMove)
	          multipliers[:base_damage_multiplier] *= 1.5
	        end
	        if user.effects[PBEffects::Charge] > 0 && type == :ELECTRIC
	          multipliers[:base_damage_multiplier] *= 2
	        end
	        # Mud Sport
	        if type == :ELECTRIC
	          if @battle.allBattlers.any? { |b| b.effects[PBEffects::MudSport] }
	            multipliers[:base_damage_multiplier] /= 3
	          end
	          if @battle.field.effects[PBEffects::MudSportField] > 0
	            multipliers[:base_damage_multiplier] /= 3
	          end
	        end
	        # Water Sport
	        if type == :FIRE
	          if @battle.allBattlers.any? { |b| b.effects[PBEffects::WaterSport] }
	            multipliers[:base_damage_multiplier] /= 3
	          end
	          if @battle.field.effects[PBEffects::WaterSportField] > 0
	            multipliers[:base_damage_multiplier] /= 3
	          end
	        end
	        multipliers[:final_damage_multiplier] *= 2 if target.effects[PBEffects::GlaiveRush] > 0
	    end

	    def badge_boost(user, target, numTargets, type, baseDmg, multipliers)
	    	if @battle.internalBattle
	          if user.pbOwnedByPlayer?
	            if @move.physicalMove? && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_ATTACK
	              multipliers[:attack_multiplier] *= 1.1
	            elsif @move.specialMove? && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_SPATK
	              multipliers[:attack_multiplier] *= 1.1
	            end
	          end
	          if target.pbOwnedByPlayer?
	            if @move.physicalMove? && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_DEFENSE
	              multipliers[:defense_multiplier] *= 1.1
	            elsif @move.specialMove? && @battle.pbPlayer.badge_count >= Settings::NUM_BADGES_BOOST_SPDEF
	              multipliers[:defense_multiplier] *= 1.1
	            end
	          end
	        end
	    end

	    def terrain_mults(user, target, numTargets, type, baseDmg, multipliers)
	    	terrain_multiplier = (Settings::MECHANICS_GENERATION >= 8) ? 1.3 : 1.5
	        case @battle.field.terrain
	        when :Electric
	          multipliers[:base_damage_multiplier] *= terrain_multiplier if type == :ELECTRIC && user.affectedByTerrain?
	        when :Grassy
	          multipliers[:base_damage_multiplier] *= terrain_multiplier if type == :GRASS && user.affectedByTerrain?
	        when :Psychic
	          multipliers[:base_damage_multiplier] *= terrain_multiplier if type == :PSYCHIC && user.affectedByTerrain?
	        when :Misty
	          multipliers[:base_damage_multiplier] /= 2 if type == :DRAGON && target.affectedByTerrain?
	        when :Poison
	          multipliers[:base_damage_multiplier] *= 1.5 if type == :POISON && user.affectedByTerrain?
	        end
	    end

	    def spread_damage(user, target, numTargets, type, baseDmg, multipliers)
	    	if numTargets > 1
	          multipliers[:final_damage_multiplier] *= 0.75
	        end
	    end

	    def weather_mults(user, target, numTargets, type, baseDmg, multipliers)
	    	case @battle.pbWeather
	        when :Sun, :HarshSun
	          case type
	          when :FIRE
	            multipliers[:final_damage_multiplier] *= 1.5
	          when :WATER
	            multipliers[:final_damage_multiplier] *= 0.5 if !user.hasActiveAbility?(:STEAMPOWERED) && @function != "550"
	          else
	            multipliers[:final_damage_multiplier] *= 1.0
	          end
	        when :Rain, :HeavyRain
	          case type
	          when :FIRE
	            multipliers[:final_damage_multiplier] *= 0.5 if !user.hasActiveAbility?(:STEAMPOWERED)
	          when :WATER
	            multipliers[:final_damage_multiplier] *= 1.5
	          else
	            multipliers[:final_damage_multiplier] *= 1.0
	          end
	        when :Hail
	          if Settings::GEN_9_SNOW == true
	            if target.pbHasType?(:ICE) && (@move.physicalMove? || @function=="122")
	              multipliers[:defense_multiplier] *= 1.5
	            end
	         end
	        when :Starstorm
	         if type == :COSMIC
	           multipliers[:final_damage_multiplier] *= 1.5
	         elsif type == :STEEL
	           multipliers[:final_damage_multiplier] /= 2
	         elsif target.pbHasType?(:COSMIC) && (@move.physicalMove? || @function=="122")
	           multipliers[:defense_multiplier] *= 1.5
	         end
	        when :Windy
	          if type == :ROCK || type == :ICE
	            multipliers[:final_damage_multiplier] /= 2
	          end
	          if @move.windMove?
	            multipliers[:final_damage_multiplier] *= 1.2
	          end
	        when :Fog
	          if type == :DRAGON
	            multipliers[:final_damage_multiplier] /= 2
	          end
	        when :Eclipse
	          if type == :DARK
	            multipliers[:final_damage_multiplier] *= 1.5
	          elsif type == :GHOST
	            multipliers[:final_damage_multiplier] *= 1.5
	          elsif type == :FAIRY && !user.hasActiveAbility?(:NOCTEMBOOST)
	            multipliers[:final_damage_multiplier] /= 2
	          elsif type == :PSYCHIC
	            multipliers[:final_damage_multiplier] /= 2
	          end
	        when :Storm
	          if type == :FIRE && !target.hasActiveAbility?(:STEAMPOWERED)
	            multipliers[:final_damage_multiplier] /= 2
	          elsif type == :WATER
	            multipliers[:final_damage_multiplier] *= 1.5
	          elsif type == :ELECTRIC
	            multipliers[:final_damage_multiplier] *= 1.5
	          end
	        when :Sleet
	          if type == :FIRE
	            multipliers[:final_damage_multiplier] /= 2
	          end
	        when :AcidRain
	          if target.pbHasType?(:POISON) && (@move.physicalMove? || @function=="122")
	            multipliers[:defense_multiplier] *= 1.5
	          end
	        when :Sandstorm
	          if target.pbHasType?(:ROCK) && @move.specialMove? && @function != "122"
	            multipliers[:defense_multiplier] *= 1.5
	          end
	        end
	    end

	    def crit_mults(user, target, numTargets, type, baseDmg, multipliers)
	    	if target.damageState.critical
	          if Settings::NEW_CRITICAL_HIT_RATE_MECHANICS
	            multipliers[:final_damage_multiplier] *= 1.5
	          else
	            multipliers[:final_damage_multiplier] *= 2
	          end
	        end
	    end

	    def damage_rolls(user, target, numTargets, type, baseDmg, multipliers)
	    	if !@move.is_a?(PokeBattle_ConfuseMove)
	          random = 85 + @battle.pbRandom(16)
	          random = 92 if $game_switches[Settings::NO_ROLLS]
	          multipliers[:final_damage_multiplier] *= random / 100.0
	        end
	    end

	    def stab(user, target, numTargets, type, baseDmg, multipliers)
	    	if (type && user.pbHasType?(type)) || user.hasActiveAbility?([:PROTEAN,:LIBERO])
	          if user.hasActiveAbility?(:ADAPTABILITY)
	            multipliers[:final_damage_multiplier] *= 2
	          else
	            multipliers[:final_damage_multiplier] *= 1.5
	          end
	        end
	    end

	    def type_effectiveness(user, target, numTargets, type, baseDmg, multipliers)
	    	multipliers[:final_damage_multiplier] *= target.damageState.typeMod.to_f / Effectiveness::NORMAL_EFFECTIVE
	    end

	    def statuses(user, target, numTargets, type, baseDmg, multipliers)
	    	if user.status == :BURN && @move.physicalMove? && @move.damageReducedByBurn? &&
	           !user.hasActiveAbility?(:GUTS)
	          multipliers[:final_damage_multiplier] /= 2
	        end
	        if [:FROZEN,:FROSTBITE].include?(user.status) && @move.specialMove?
	          multipliers[:final_damage_multiplier] /= 2
	        end
	    end

	    def screens(user, target, numTargets, type, baseDmg, multipliers)
	    	if !@move.ignoresReflect? && !target.damageState.critical &&
	           !user.hasActiveAbility?(:INFILTRATOR)
	          if target.pbOwnSide.effects[PBEffects::AuroraVeil] > 0
	            if @battle.pbSideBattlerCount(target) > 1
	              multipliers[:final_damage_multiplier] *= 2 / 3.0
	            else
	              multipliers[:final_damage_multiplier] /= 2
	            end
	          elsif target.pbOwnSide.effects[PBEffects::Reflect] > 0 && @move.physicalMove?
	            if @battle.pbSideBattlerCount(target) > 1
	              multipliers[:final_damage_multiplier] *= 2 / 3.0
	            else
	              multipliers[:final_damage_multiplier] /= 2
	            end
	          elsif target.pbOwnSide.effects[PBEffects::LightScreen] > 0 && @move.specialMove?
	            if @battle.pbSideBattlerCount(target) > 1
	              multipliers[:final_damage_multiplier] *= 2 / 3.0
	            else
	              multipliers[:final_damage_multiplier] /= 2
	            end
	          end
	        end
	    end

	    def minimize(user, target, numTargets, type, baseDmg, multipliers)
	    	if target.effects[PBEffects::Minimize] && @move.tramplesMinimize?(2)
	          multipliers[:final_damage_multiplier] *= 2
	        end
	    end

	    def field_effects(user, target, numTargets, type, baseDmg, multipliers)
	      fe = (@battle.field.field_effects) == :None ? nil : Field_Effects.try_get(@battle.field.field_effects)
	      if fe
	        #Field Effect Type Boosts
	         trigger = false
	         mesg = false
	         if Field_Effects.has?(fe,:type_damage_change)
	           for key in fe[:type_damage_change].keys
	             if @battle.field.field_effects != :None
	              if fe[:type_damage_change][key].include?(type)
	                multipliers[:final_damage_multiplier] *= key
	              end
	             end
	           end
	         end
	         #Field Effect Specific Move Boost
	         if Field_Effects.has?(fe,:move_damage_boost)
	           for dmg in fe[:move_damage_boost].keys
	             if @battle.field.field_effects != :None
	              if fe[:move_damage_boost][dmg].is_a?(Array)
	                if fe[:move_damage_boost][dmg].any? {|d| d.include?(@move.id)}
	                  multipliers[:final_damage_multiplier] *= dmg 
	                end
	              elsif @move.id == fe[:move_damage_boost][dmg]
	                multipliers[:final_damage_multiplier] *= dmg
	              end
	             end
	           end
	         end

	        #Field Effect Defensive Modifiers
	         if Field_Effects.has?(fe,:defensive_modifiers)
	          priority = @battle.pbPriority(true)
	          msg = nil
	          for d in fe[:defensive_modifiers].keys
	            if fe[:defensive_modifiers][d][1] == "fullhp"
	              multipliers[:final_damage_multiplier] /= d
	            elsif fe[:defensive_modifiers][d][1] == "physical"
	              multipliers[:defense_multiplier] *= d if @move.physicalMove?
	            elsif fe[:defensive_modifiers][d][1] == "special"
	              multipliers[:defense_multiplier] *= d if @move.specialMove?
	            elsif fe[:defensive_modifiers][d][1] == nil
	              multipliers[:defense_multiplier] *= d
	            end
	          end
	        end
	      end
	    end




	    def pbCalcDamageMultipliers(user, target, numTargets, type, baseDmg, multipliers)
	      ruin_mults(user, target, numTargets, type, baseDmg, multipliers)
	      vocal_fry(user, target, numTargets, type, baseDmg, multipliers)
	      global_ability_mults(user, target, numTargets, type, baseDmg, multipliers)
	      ability_mults(user, target, numTargets, type, baseDmg, multipliers)
	      item_mults(user, target, numTargets, type, baseDmg, multipliers)
	      second_hit_mults(user, target, numTargets, type, baseDmg, multipliers)
	      misc_mults(user, target, numTargets, type, baseDmg, multipliers)
	      terrain_mults(user, target, numTargets, type, baseDmg, multipliers)
	      badge_boost(user, target, numTargets, type, baseDmg, multipliers)
	      spread_damage(user, target, numTargets, type, baseDmg, multipliers)
	      weather_mults(user, target, numTargets, type, baseDmg, multipliers)
	      crit_mults(user, target, numTargets, type, baseDmg, multipliers)
	      damage_rolls(user, target, numTargets, type, baseDmg, multipliers)
	      stab(user, target, numTargets, type, baseDmg, multipliers)
	      type_effectiveness(user, target, numTargets, type, baseDmg, multipliers)
	      statuses(user, target, numTargets, type, baseDmg, multipliers)
	      screens(user, target, numTargets, type, baseDmg, multipliers)
	      minimize(user, target, numTargets, type, baseDmg, multipliers)
	      field_effects(user, target, numTargets, type, baseDmg, multipliers)
		  # Move-specific base damage modifiers
		  multipliers[:base_damage_multiplier] = pbBaseDamageMultiplier(multipliers[:base_damage_multiplier], user, target)
		  # Move-specific final damage modifiers
		  multipliers[:final_damage_multiplier] = pbModifyDamage(multipliers[:final_damage_multiplier], user, target)
		  return multipliers
	    end
	end
end