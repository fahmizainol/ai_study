# Level_Cap — Reborn-style obedience cap for Realidea (TEAM-DESIGN.md, option 2).
# Appended-section monkey-patch: reopens PokeBattle_Battler and redefines
# pbObedienceCheck? (original at script section 080, line ~2498). The original
# section is untouched; remove this section to revert.
#
# Two changes vs stock:
#   1. The disobedience roll no longer requires isForeign? — ALL overleveled
#      player mons disobey, not just traded ones (Reborn's rule).
#   2. Badge table retuned to sit ~2 levels above each gym's ace
#      (aces: 14,20,26,33,38,40,45,48; finale 51; optional superboss 64-66).
# Scripted-battle gimmicks (switches 212 / 401) are carried over verbatim.

class PokeBattle_Battler
  def pbObedienceCheck?(choice)
    if $game_switches[212] == true && @pokemon.name == "Braviary"
      if !@battle.pbOwnedByPlayer?(@index)
        @battle.pbDisplay(_INTL("¡{1} se niega a obedecer órdenes!",self.pbThis))
        cutin if self.pbCanReduceStatStage?(PBStats::SPDEF,nil,false) && self.pbCanReduceStatStage?(PBStats::DEFENSE,nil,false)
        self.pbReduceStat(PBStats::DEFENSE,6,nil,false) if self.pbCanReduceStatStage?(PBStats::DEFENSE,nil,false)
        self.pbReduceStat(PBStats::SPDEF,6,nil,false) if self.pbCanReduceStatStage?(PBStats::SPDEF,nil,false)
        return false
      end
    end

    if $game_switches[401] == true
      if @battle.pbPokemonCount(@battle.pbOpposingParty(@index))==1
        @battle.pbDisplay(_INTL("{1} mira fijamente a su rival...",self.pbThis))
        return false
      end
    end

    return true if choice[0]!=1
    if @battle.pbOwnedByPlayer?(@index) && @battle.internalbattle
      badgelevel=16                                       # pre-badge (gym 1 ace: 14)
      badgelevel=22  if @battle.pbPlayer.numbadges>=1     # gym 2 ace: 20
      badgelevel=28  if @battle.pbPlayer.numbadges>=2     # gym 3 ace: 26
      badgelevel=35  if @battle.pbPlayer.numbadges>=3     # gym 4 ace: 33
      badgelevel=40  if @battle.pbPlayer.numbadges>=4     # gym 5 ace: 38
      badgelevel=42  if @battle.pbPlayer.numbadges>=5     # gym 6 ace: 40
      badgelevel=47  if @battle.pbPlayer.numbadges>=6     # gym 7 ace: 45
      badgelevel=50  if @battle.pbPlayer.numbadges>=7     # gym 8 ace: 48
      badgelevel=65  if @battle.pbPlayer.numbadges>=8     # finale 51 + superboss headroom
      move=choice[2]
      disobedient=false
      if @level>badgelevel                                # was: isForeign? && over
        a=((@level+badgelevel)*@battle.pbRandom(256)/255).floor
        disobedient|=a<badgelevel
      end
      if self.respond_to?("pbHyperModeObedience")
        disobedient|=!self.pbHyperModeObedience(move)
      end

      if disobedient
        PBDebug.log("[Desobediencia] #{pbThis} ha desobedecido")
        @effects[PBEffects::Rage]=false
        if self.status==PBStatuses::SLEEP &&
           (move.function==0x11 || move.function==0xB4) # Snore, Sleep Talk
          @battle.pbDisplay(_INTL("¡{1} ignora las órdenes mientras se va a dormir!",pbThis))
          return false
        end
        b=((@level+badgelevel)*@battle.pbRandom(256)/255).floor
        if b<badgelevel
          return false if !@battle.pbCanShowFightMenu?(@index)
          othermoves=[]
          for i in 0...4
            next if i==choice[1]
            othermoves[othermoves.length]=i if @battle.pbCanChooseMove?(@index,i,false)
          end
          if othermoves.length>0
            @battle.pbDisplay(_INTL("¡{1} se hace el distraido!",pbThis))
            newchoice=othermoves[@battle.pbRandom(othermoves.length)]
            choice[1]=newchoice
            choice[2]=@moves[newchoice]
            choice[3]=-1
          end
          return true
        elsif self.status!=PBStatuses::SLEEP
          c=@level-b
          r=@battle.pbRandom(256)
          if r<c && pbCanSleep?(self,false)
            pbSleepSelf()
            @battle.pbDisplay(_INTL("¡{1} está tomando una siesta!",pbThis))
            return false
          end
          r-=c
          if r<c
            @battle.pbDisplay(_INTL("¡Está tan confuso que se hirió a sí mismo!"))
            pbConfusionDamage
          else
            message=@battle.pbRandom(4)
            @battle.pbDisplay(_INTL("¡{1} ignoró las órdenes!",pbThis)) if message==0
            @battle.pbDisplay(_INTL("¡{1} se alejó!",pbThis)) if message==1
            @battle.pbDisplay(_INTL("¡{1} está con pereza!",pbThis)) if message==2
            @battle.pbDisplay(_INTL("¡{1} fingió no darse cuenta!",pbThis)) if message==3
          end
          return false
        end
      end
      return true
    else
      return true
    end
  end
end
