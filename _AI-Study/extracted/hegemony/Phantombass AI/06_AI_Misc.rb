def deep_copy(obj)
  Marshal.load(Marshal.dump(obj))
end

def pbHashConverter(mod,hash)
  newhash = {}
  hash.each {|key, value|
      for i in value
          newhash[mod.const_get(i.to_sym)]=key
      end
  }
  return newhash
end

def pbHashForwardizer(hash) #one-stop shop for your hash debackwardsing needs!
  return if !hash.is_a?(Hash)
  newhash = {}
  hash.each {|key, value|
      for i in value
          newhash[i]=key
      end
  }
  return newhash
end

def arrayToConstant(mod,array)
  newarray = []
  for symbol in array
    const = mod.const_get(symbol.to_sym) rescue nil
    newarray.push(const) if const
  end
  return newarray
end

def hashToConstant(mod,hash)
  for key in hash.keys
    const = mod.const_get(hash[key].to_sym) rescue nil
    hash.merge!(key=>const) if const
  end
  return hash
end

def hashArrayToConstant(mod,hash)
  for key in hash.keys
    array = hash[key]
    newarray = arrayToConstant(mod,array)
    hash.merge!(key=>newarray) if !newarray.empty?
  end
  return hash
end

Essentials::ERROR_TEXT += "[Phantombass AI v#{Phantombass_AI::VERSION}]\r\n"

=begin
STATUSTEXTS = ["status", "sleep", "poison", "burn", "paralysis", "ice"]
STATSTRINGS = ["HP", "Attack", "Defense", "Speed", "Sp. Attack", "Sp. Defense"]

class PBStuff
  #rejuv stuff while we work out the kinks
  #massive arrays of stuff that no one wants to see
  #List of Abilities that either prevent or co-opt Intimidate
  TRACEABILITIES = arrayToConstant(GameData::Ability,[:PROTEAN,:CONTRARY,:INTIMIDATE, :WONDERGUARD,:MAGICGUARD,
    :SWIFTSWIM,:SLUSHRUSH, :SANDRUSH,:TELEPATHY,:SURGESURFER, :SOLARPOWER,:DRYSKIN,:DOWNLOAD, :LEVITATE,
    :LIGHTNINGROD,:MOTORDRIVE, :VOLTABSORB,:FLASHFIRE,:MAGMAARMOR, :ADAPTABILITY,:DEFIANT,:COMPETITIVE, 
    :PRANKSTER,:SPEEDBOOST,:MULTISCALE, :SHADOWSHIELD,:SAPSIPPER,:FURCOAT, :FLUFFY,:MAGICBOUNCE,
    :REGENERATOR, :DAZZLING,:QUEENLYMAJESTY,:SOUNDPROOF, :TECHNICIAN,:SPEEDBOOST,:STEAMENGINE, 
    :ICESCALES,:BEASTBOOST,:SHEDSKIN, :CLEARBODY,:WHITESMOKE,:MOODY, :THICKFAT,:STORMDRAIN,
    :SIMPLE,:PUREPOWER,:MARVELSCALE,:STURDY,:MEGALAUNCHER,:LIBERO,:SHEERFORCE,:UNAWARE,:CHLOROPHYLL])
  NEGATIVEABILITIES = arrayToConstant(GameData::Ability,[:TRUANT,:DEFEATIST,:SLOWSTART,:KLUTZ,:STALL,:GORILLATACTICS,:RIVALRY])

#Standardized lists of moves or abilities which are sometimes called
  #Blacklisted abilities USUALLY can't be copied.
###--------------------------------------ABILITYBLACKLIST-------------------------------------------------------###
ABILITYBLACKLIST = arrayToConstant(GameData::Ability,[:MULTITYPE, :COMATOSE,:DISGUISE, :SCHOOLING, 
  :RKSSYSTEM, :IMPOSTER,:SHIELDSDOWN, :POWEROFALCHEMY,:RECEIVER,:TRACE, :FORECAST, :FLOWERGIFT,
  :ILLUSION,:WONDERGUARD, :ZENMODE, :STANCECHANGE,:POWERCONSTRUCT,:iceface,:MULTITOOL])

###--------------------------------------FIXEDABILITIES---------------------------------------------------------###
#Fixed abilities USUALLY can't be changed.
FIXEDABILITIES = arrayToConstant(GameData::Ability,[:MULTITYPE, :ZENMODE, :STANCECHANGE, :SCHOOLING, 
  :COMATOSE,:SHIELDSDOWN, :DISGUISE, :RKSSYSTEM, :POWERCONSTRUCT,:iceface, :GULPMISSILE])

#Standardized lists of moves with similar purposes/characteristics
#(mostly just "stuff that gets called together")

###--------------------------------------UNFREEZEMOVE-----------------------------------------------------------###
UNFREEZEMOVE = arrayToConstant(GameData::Move,[:FLAMEWHEEL,:SACREDFIRE,:FLAREBLITZ, :FUSIONFLARE, 
  :SCALD, :STEAMERUPTION, :BURNUP])

###--------------------------------------SETUPMOVE--------------------------------------------------------------###
SETUPMOVE = arrayToConstant(GameData::Move,[:SWORDSDANCE, :DRAGONDANCE, :CALMMIND, :WORKUP,:NASTYPLOT, 
  :TAILGLOW,:BELLYDRUM, :BULKUP,:COIL,:CURSE, :GROWTH, :HONECLAWS, :QUIVERDANCE, :SHELLSMASH])

###--------------------------------------PROTECTMOVE------------------------------------------------------------###
PROTECTMOVE = arrayToConstant(GameData::Move,[:PROTECT, :DETECT,:KINGSSHIELD, :SPIKYSHIELD, :BANEFULBUNKER])

###--------------------------------------PROTECTIGNORINGMOVE----------------------------------------------------###
PROTECTIGNORINGMOVE = arrayToConstant(GameData::Move,[:FEINT, :HYPERSPACEHOLE,:HYPERSPACEFURY, :SHADOWFORCE, :PHANTOMFORCE])

###--------------------------------------SCREENBREAKERMOVE------------------------------------------------------###
SCREENBREAKERMOVE = arrayToConstant(GameData::Move,[:DEFOG, :BRICKBREAK,:PSYCHICFANGS])

###--------------------------------------CONTRARYBAITMOVE-------------------------------------------------------###
CONTRARYBAITMOVE = arrayToConstant(GameData::Move,[:SUPERPOWER,:OVERHEAT,:DRACOMETEOR, :LEAFSTORM, 
  :FLEURCANNON, :PSYCHOBOOST])

###--------------------------------------TWOTURNAIRMOVE---------------------------------------------------------###
TWOTURNAIRMOVE = arrayToConstant(GameData::Move,[:BOUNCE,:FLY, :SKYDROP])

###--------------------------------------PIVOTMOVE--------------------------------------------------------------###
PIVOTMOVE = arrayToConstant(GameData::Move,[:UTURN, :VOLTSWITCH,:PARTINGSHOT,:CHILLYRECEPTION,:SHEDTAIL,:FLIPTURN,:TELEPORT])

###--------------------------------------DANCEMOVE--------------------------------------------------------------###
DANCEMOVE = arrayToConstant(GameData::Move,[:QUIVERDANCE, :DRAGONDANCE, :FIERYDANCE, 
  :FEATHERDANCE,:PETALDANCE,:SWORDSDANCE, :TEETERDANCE, :LUNARDANCE,:REVELATIONDANCE])

###--------------------------------------BULLETMOVE-------------------------------------------------------------###
BULLETMOVE = arrayToConstant(GameData::Move,[:ACIDSPRAY, :AURASPHERE,:BARRAGE, :BULLETSEED,
  :EGGBOMB, :ELECTROBALL, :ENERGYBALL, :FOCUSBLAST,:GYROBALL,:ICEBALL, :MAGNETBOMB, 
  :MISTBALL,:MUDBOMB, :OCTAZOOKA, :ROCKWRECKER, :SEARINGSHOT, :SEEDBOMB,:SHADOWBALL,
  :SLUDGEBOMB, :WEATHERBALL, :ZAPCANNON, :BEAKBLAST])

###--------------------------------------BITEMOVE---------------------------------------------------------------###
BITEMOVE = arrayToConstant(GameData::Move,[:BITE,:CRUNCH,:THUNDERFANG, :FIREFANG,:ICEFANG,
  :POISONFANG,:HYPERFANG, :PSYCHICFANGS, :COSMICFANGS, :DRACOFANGS, :IRONFANGS, :LEECHLIFE])

###--------------------------------------PHASEMOVE--------------------------------------------------------------###
PHASEMOVE = arrayToConstant(GameData::Move,[:ROAR,:WHIRLWIND, :CIRCLETHROW, :DRAGONTAIL,:YAWN,:PERISHSONG])

###--------------------------------------SCREENMOVE-------------------------------------------------------------###
SCREENMOVE = arrayToConstant(GameData::Move,[:LIGHTSCREEN, :REFLECT, :AURORAVEIL])

###--------------------------------------OHKOMOVE-------------------------------------------------------------###
OHKOMOVE = arrayToConstant(GameData::Move,[:FISSURE,:SHEERCOLD,:GUILLOTINE,:HORNDRILL])

#Moves that inflict statuses with at least a 50% of hitting
###--------------------------------------BURNMOVE---------------------------------------------------------------###
BURNMOVE = arrayToConstant(GameData::Move,[:WILLOWISP, :SACREDFIRE,:INFERNO])

###--------------------------------------PARAMOVE---------------------------------------------------------------###
PARAMOVE = arrayToConstant(GameData::Move,[:THUNDERWAVE, :STUNSPORE, :GLARE, :NUZZLE,:ZAPCANNON])

###--------------------------------------SLEEPMOVE--------------------------------------------------------------###
SLEEPMOVE = arrayToConstant(GameData::Move,[:SPORE, :SLEEPPOWDER, :HYPNOSIS, :DARKVOID,:GRASSWHISTLE,
  :LOVELYKISS,:SING, :YAWN])

###--------------------------------------POISONMOVE-------------------------------------------------------------###
POISONMOVE = arrayToConstant(GameData::Move,[:TOXIC, :POISONPOWDER,:POISONGAS, :TOXICTHREAD])

###--------------------------------------CONFUMOVE--------------------------------------------------------------###
CONFUMOVE = arrayToConstant(GameData::Move,[:CONFUSERAY,:SUPERSONIC,:FLATTER, :SWAGGER, :SWEETKISS, 
  :TEETERDANCE, :CHATTER, :DYNAMICPUNCH])

#all the status inflicting moves
###--------------------------------------STATUSCONDITIONMOVE----------------------------------------------------###
STATUSCONDITIONMOVE = arrayToConstant(GameData::Move,[:WILLOWISP, :DARKVOID,:GRASSWHISTLE, :HYPNOSIS,
  :LOVELYKISS,:SING,:SLEEPPOWDER, :SPORE, :YAWN,:POISONGAS, :POISONPOWDER, :TOXIC, :NUZZLE,
  :STUNSPORE, :THUNDERWAVE, :DEEPFREEZE])


#Odd groups of moves/effects with similar behavior
###--------------------------------------HEALFUNCTIONS----------------------------------------------------------###
HEALFUNCTIONS =["0D5","0D6","0D7","0D8","0D9","0DD","0DE","0DF",
  "0E3","0E4","114","139","158","162","169","16C","172"]

###--------------------------------------RATESHARERS------------------------------------------------------------###
RATESHARERS = arrayToConstant(GameData::Move,[:PROTECT, :DETECT,:QUICKGUARD, :WIDEGUARD, :ENDURE,
  :KINGSSHIELD, :SPIKYSHIELD, :BANEFULBUNKER, :CRAFTYSHIELD, :OBSTRUCT])

###--------------------------------------INVULEFFECTS-----------------------------------------------------------###
INVULEFFECTS = arrayToConstant(PBEffects,[:Protect, :Endure,:Obstruct, :KingsShield, :SpikyShield, :MatBlock, 
  :BanefulBunker])

###--------------------------------------POWDERMOVES------------------------------------------------------------###
POWDERMOVES = arrayToConstant(GameData::Move,[:COTTONSPORE, :SLEEPPOWDER, :STUNSPORE, :SPORE, :RAGEPOWDER,
  :POISONPOWDER,:POWDER])

###--------------------------------------AIRHITMOVES------------------------------------------------------------###
AIRHITMOVES = arrayToConstant(GameData::Move,[:THUNDER, :HURRICANE, :GUST, :TWISTER, :SKYUPPERCUT, 
  :SMACKDOWN, :THOUSANDARROWS])

# Blacklist stuff
###--------------------------------------NOCOPYMOVE-------------------------------------------------------------###
NOCOPYMOVE = arrayToConstant(GameData::Move,[:ASSIST,:COPYCAT, :MEFIRST, :METRONOME, :MIMIC, :MIRRORMOVE,
  :NATUREPOWER, :SHELLTRAP, :SKETCH,:SLEEPTALK, :STRUGGLE, :BEAKBLAST, :FOCUSPUNCH,:TRANSFORM, 
  :BELCH, :CHATTER, :KINGSSHIELD, :BANEFULBUNKER, :BESTOW, :COUNTER, :COVET, :DESTINYBOND, :DETECT, 
  :ENDURE,:FEINT, :FOLLOWME,:HELPINGHAND, :MATBLOCK,:MIRRORCOAT,:PROTECT, :RAGEPOWDER, :SNATCH,
  :SPIKYSHIELD, :SPOTLIGHT, :SWITCHEROO, :THIEF, :TRICK])

###--------------------------------------NOAUTOMOVE-------------------------------------------------------------###
NOAUTOMOVE = arrayToConstant(GameData::Move,[:ASSIST,:COPYCAT, :MEFIRST, :METRONOME, :MIMIC, :MIRRORMOVE,
  :NATUREPOWER, :SHELLTRAP, :SKETCH,:SLEEPTALK, :STRUGGLE])

###--------------------------------------DELAYEDMOVE------------------------------------------------------------###
DELAYEDMOVE = arrayToConstant(GameData::Move,[:BEAKBLAST, :FOCUSPUNCH, :SHELLTRAP])

###--------------------------------------TWOTURNMOVE------------------------------------------------------------###
TWOTURNMOVE = arrayToConstant(GameData::Move,[:BOUNCE,:DIG, :DIVE, :FLY, :PHANTOMFORCE,:SHADOWFORCE, :SKYDROP])

###--------------------------------------FORCEOUTMOVE-----------------------------------------------------------###
FORCEOUTMOVE = arrayToConstant(GameData::Move,[:CIRCLETHROW, :DRAGONTAIL,:ROAR, :WHIRLWIND])
###--------------------------------------REPEATINGMOVE----------------------------------------------------------###
REPEATINGMOVE = arrayToConstant(GameData::Move,[:ICEBALL, :OUTRAGE, :PETALDANCE, :ROLLOUT, :THRASH])

###--------------------------------------CHARGEMOVE-------------------------------------------------------------###
CHARGEMOVE = arrayToConstant(GameData::Move,[:BIDE, :GEOMANCY,:RAZORWIND, :SKULLBASH,:SKYATTACK,:SOLARBEAM, 
  :SOLARBLADE, :FREEZESHOCK, :ICEBURN, :METEORSHOWER])
end

=end
class PokeBattle_Battle
  def typesInverted?
    return $PokemonTemp.battleRules["inverseBattle"] == true
  end
end

module Effectiveness
  def get_resisted_types(type)
    resisted = []
    for i in types
      resisted.push(i) if self.resistant_type?(i,type)
    end
    return resisted
  end

  def get_super_effective_types(type)
    superE = []
    for i in types
      superE.push(i) if self.super_effective_type?(i,type)
    end
    return superE
  end
end

#===============================================================================
#
#===============================================================================
module PBAI::ItemEffects
  SpeedCalc                       = ItemHandlerHash.new
  WeightCalc                      = ItemHandlerHash.new   # Float Stone
  # Battler's HP/stat changed
  HPHeal                          = ItemHandlerHash.new
  OnStatLoss                      = ItemHandlerHash.new
  # Battler's status problem
  StatusCure                      = ItemHandlerHash.new
  # Priority and turn order
  PriorityBracketChange           = ItemHandlerHash.new
  PriorityBracketUse              = ItemHandlerHash.new
  # Move usage failures
  OnMissingTarget                 = ItemHandlerHash.new   # Blunder Policy
  # Accuracy calculation
  AccuracyCalcFromUser            = ItemHandlerHash.new
  AccuracyCalcFromTarget          = ItemHandlerHash.new
  # Damage calculation
  DamageCalcFromUser              = ItemHandlerHash.new
  DamageCalcFromTarget            = ItemHandlerHash.new
  CriticalCalcFromUser            = ItemHandlerHash.new
  CriticalCalcFromTarget          = ItemHandlerHash.new   # None!
  # Upon a move hitting a target
  OnBeingHit                      = ItemHandlerHash.new
  OnBeingHitPositiveBerry         = ItemHandlerHash.new
  # Items that trigger at the end of using a move
  AfterMoveUseFromTarget          = ItemHandlerHash.new
  AfterMoveUseFromUser            = ItemHandlerHash.new
  OnEndOfUsingMove                = ItemHandlerHash.new   # Leppa Berry
  OnEndOfUsingMoveStatRestore     = ItemHandlerHash.new   # White Herb
  # Experience and EV gain
  ExpGainModifier                 = ItemHandlerHash.new   # Lucky Egg
  EVGainModifier                  = ItemHandlerHash.new
  # Weather and terrin
  WeatherExtender                 = ItemHandlerHash.new
  TerrainExtender                 = ItemHandlerHash.new   # Terrain Extender
  TerrainStatBoost                = ItemHandlerHash.new
  # End Of Round
  EndOfRoundHealing               = ItemHandlerHash.new
  EndOfRoundEffect                = ItemHandlerHash.new
  # Switching and fainting
  CertainSwitching                = ItemHandlerHash.new   # Shed Shell
  TrappingByTarget                = ItemHandlerHash.new   # None!
  OnSwitchIn                      = ItemHandlerHash.new   # Air Balloon
  OnIntimidated                   = ItemHandlerHash.new   # Adrenaline Orb
  # Running from battle
  CertainEscapeFromBattle         = ItemHandlerHash.new   # Smoke Ball
  OnFlinch                       = ItemHandlerHash.new
  OnOpposingStatGain = ItemHandlerHash.new # Mirror Herb
  StatLossImmunity   = ItemHandlerHash.new # Clear Amulet

  #=============================================================================

  def self.trigger(hash, *args, ret: false)
    new_ret = hash.trigger(*args)
    return (!new_ret.nil?) ? new_ret : ret
  end

  #=============================================================================

  def self.triggerSpeedCalc(item, battler, mult)
    return trigger(SpeedCalc, item, battler, mult, ret: mult)
  end

  def self.triggerWeightCalc(item, battler, w)
    return trigger(WeightCalc, item, battler, w, ret: w)
  end

  #=============================================================================

  def self.triggerHPHeal(item, battler, battle, forced)
    return trigger(HPHeal, item, battler, battle, forced)
  end

  def self.triggerOnStatLoss(item, user, move_user, battle)
    return trigger(OnStatLoss, item, user, move_user, battle)
  end

  #=============================================================================

  def self.triggerStatusCure(item, battler, battle, forced)
    return trigger(StatusCure, item, battler, battle, forced)
  end

  #=============================================================================

  def self.triggerPriorityBracketChange(item, battler, battle)
    return trigger(PriorityBracketChange, item, battler, battle, ret: 0)
  end

  def self.triggerPriorityBracketUse(item, battler, battle)
    PriorityBracketUse.trigger(item, battler, battle)
  end

  #=============================================================================

  def self.triggerOnMissingTarget(item, user, target, move, hit_num, battle)
    OnMissingTarget.trigger(item, user, target, move, hit_num, battle)
  end

  def self.triggerOnFlinch(item, battler, battle)
    OnFlinch.trigger(item, battler, battle)
  end

  #=============================================================================

  def self.triggerAccuracyCalcFromUser(item, mods, user, target, move, type)
    AccuracyCalcFromUser.trigger(item, mods, user, target, move, type)
  end

  def self.triggerAccuracyCalcFromTarget(item, mods, user, target, move, type)
    AccuracyCalcFromTarget.trigger(item, mods, user, target, move, type)
  end

  #=============================================================================

  def self.triggerDamageCalcFromUser(item, user, target, move, mults, base_damage, type)
    DamageCalcFromUser.trigger(item, user, target, move, mults, base_damage, type)
  end

  def self.triggerDamageCalcFromTarget(item, user, target, move, mults, base_damage, type)
    DamageCalcFromTarget.trigger(item, user, target, move, mults, base_damage, type)
  end

  def self.triggerCriticalCalcFromUser(item, user, target, crit_stage)
    return trigger(CriticalCalcFromUser, item, user, target, crit_stage, ret: crit_stage)
  end

  def self.triggerCriticalCalcFromTarget(item, user, target, crit_stage)
    return trigger(CriticalCalcFromTarget, item, user, target, crit_stage, ret: crit_stage)
  end

  #=============================================================================

  def self.triggerOnBeingHit(item, user, target, move, battle)
    OnBeingHit.trigger(item, user, target, move, battle)
  end

  def self.triggerOnBeingHitPositiveBerry(item, battler, battle, forced)
    return trigger(OnBeingHitPositiveBerry, item, battler, battle, forced)
  end

  def self.triggerOnOpposingStatGain(item, battler, battle, statUps, forced)
    return trigger(OnOpposingStatGain, item, battler, battle, statUps, forced)
  end

  def self.triggerStatLossImmunity(item, battler, stat, battle, show_message)
    return trigger(StatLossImmunity, item, battler, stat, battle, show_message)
  end

  #=============================================================================

  def self.triggerAfterMoveUseFromTarget(item, battler, user, move, switched_battlers, battle)
    AfterMoveUseFromTarget.trigger(item, battler, user, move, switched_battlers, battle)
  end

  def self.triggerAfterMoveUseFromUser(item, user, targets, move, num_hits, battle)
    AfterMoveUseFromUser.trigger(item, user, targets, move, num_hits, battle)
  end

  def self.triggerOnEndOfUsingMove(item, battler, battle, forced)
    return trigger(OnEndOfUsingMove, item, battler, battle, forced)
  end

  def self.triggerOnEndOfUsingMoveStatRestore(item, battler, battle, forced)
    return trigger(OnEndOfUsingMoveStatRestore, item, battler, battle, forced)
  end

  #=============================================================================

  def self.triggerExpGainModifier(item, battler, exp)
    return trigger(ExpGainModifier, item, battler, exp, ret: -1)
  end

  def self.triggerEVGainModifier(item, battler, ev_array)
    return false if !EVGainModifier[item]
    EVGainModifier.trigger(item, battler, ev_array)
    return true
  end

  #=============================================================================

  def self.triggerWeatherExtender(item, weather, duration, battler, battle)
    return trigger(WeatherExtender, item, weather, duration, battler, battle, ret: duration)
  end

  def self.triggerTerrainExtender(item, terrain, duration, battler, battle)
    return trigger(TerrainExtender, item, terrain, duration, battler, battle, ret: duration)
  end

  def self.triggerTerrainStatBoost(item, battler, battle)
    return trigger(TerrainStatBoost, item, battler, battle)
  end

  #=============================================================================

  def self.triggerEndOfRoundHealing(item, battler, battle)
    EndOfRoundHealing.trigger(item, battler, battle)
  end

  def self.triggerEndOfRoundEffect(item, battler, battle)
    EndOfRoundEffect.trigger(item, battler, battle)
  end

  #=============================================================================

  def self.triggerCertainSwitching(item, switcher, battle)
    return trigger(CertainSwitching, item, switcher, battle)
  end

  def self.triggerTrappingByTarget(item, switcher, bearer, battle)
    return trigger(TrappingByTarget, item, switcher, bearer, battle)
  end

  def self.triggerOnSwitchIn(item, battler, battle)
    OnSwitchIn.trigger(item, battler, battle)
  end

  def self.triggerOnIntimidated(item, battler, battle)
    return trigger(OnIntimidated, item, battler, battle)
  end

  #=============================================================================

  def self.triggerCertainEscapeFromBattle(item, battler)
    return trigger(CertainEscapeFromBattle, item, battler)
  end
end

#===============================================================================
# SpeedCalc handlers
#===============================================================================

PBAI::ItemEffects::SpeedCalc.add(:CHOICESCARF,
  proc { |item, battler, mult|
    next mult * 1.5
  }
)

PBAI::ItemEffects::SpeedCalc.add(:MACHOBRACE,
  proc { |item, battler, mult|
    next mult / 2
  }
)

PBAI::ItemEffects::SpeedCalc.copy(:MACHOBRACE, :POWERANKLET, :POWERBAND,
                                                 :POWERBELT, :POWERBRACER,
                                                 :POWERLENS, :POWERWEIGHT)

PBAI::ItemEffects::SpeedCalc.add(:QUICKPOWDER,
  proc { |item, battler, mult|
    next mult * 2 if battler.isSpecies?(:DITTO) &&
                   !battler.effects[PBEffects::Transform]
  }
)

PBAI::ItemEffects::SpeedCalc.add(:IRONBALL,
  proc { |item, battler, mult|
    next mult / 2
  }
)

#===============================================================================
# WeightCalc handlers
#===============================================================================

PBAI::ItemEffects::WeightCalc.add(:FLOATSTONE,
  proc { |item, battler, w|
    next [w / 2, 1].max
  }
)

#===============================================================================
# HPHeal handlers
#===============================================================================

PBAI::ItemEffects::HPHeal.add(:AGUAVBERRY,
  proc { |item, battler, battle, forced|
    next battler.pbConfusionBerry(item, forced, 4,
       _INTL("For {1}, the {2} was too bitter!", battler.pbThis(true), GameData::Item.get(item).name)
    )
  }
)

PBAI::ItemEffects::HPHeal.add(:APICOTBERRY,
  proc { |item, battler, battle, forced|
    next battler.pbStatIncreasingBerry(item, forced, :SPECIAL_DEFENSE)
  }
)

PBAI::ItemEffects::HPHeal.add(:BERRYJUICE,
  proc { |item, battler, battle, forced|
    next false if !battler.canHeal?
    next false if !forced && battler.hp > battler.totalhp / 2
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] Forced consuming of #{itemName}") if forced
    battle.pbCommonAnimation("UseItem", battler) if !forced
    battler.pbRecoverHP(20)
    if forced
      battle.pbDisplay(_INTL("{1}'s HP was restored.", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1} restored its health using its {2}!", battler.pbThis, itemName))
    end
    next true
  }
)

PBAI::ItemEffects::HPHeal.add(:FIGYBERRY,
  proc { |item, battler, battle, forced|
    next battler.pbConfusionBerry(item, forced, 0,
       _INTL("For {1}, the {2} was too spicy!", battler.pbThis(true), GameData::Item.get(item).name)
    )
  }
)

PBAI::ItemEffects::HPHeal.add(:GANLONBERRY,
  proc { |item, battler, battle, forced|
    next battler.pbStatIncreasingBerry(item, forced, :DEFENSE)
  }
)

PBAI::ItemEffects::HPHeal.add(:IAPAPABERRY,
  proc { |item, battler, battle, forced|
    next battler.pbConfusionBerry(item, forced, 1,
       _INTL("For {1}, the {2} was too sour!", battler.pbThis(true), GameData::Item.get(item).name)
    )
  }
)

PBAI::ItemEffects::HPHeal.add(:LANSATBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumePinchBerry?
    next false if battler.effects[PBEffects::FocusEnergy] >= 2
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battler.effects[PBEffects::FocusEnergy] = 2
    itemName = GameData::Item.get(item).name
    if forced
      battle.pbDisplay(_INTL("{1} got pumped from the {2}!", battler.pbThis, itemName))
    else
      battle.pbDisplay(_INTL("{1} used its {2} to get pumped!", battler.pbThis, itemName))
    end
    next true
  }
)

PBAI::ItemEffects::HPHeal.add(:LIECHIBERRY,
  proc { |item, battler, battle, forced|
    next battler.pbStatIncreasingBerry(item, forced, :ATTACK)
  }
)

PBAI::ItemEffects::HPHeal.add(:MAGOBERRY,
  proc { |item, battler, battle, forced|
    next battler.pbConfusionBerry(item, forced, 2,
       _INTL("For {1}, the {2} was too sweet!", battler.pbThis(true), GameData::Item.get(item).name)
    )
  }
)

PBAI::ItemEffects::HPHeal.add(:MICLEBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumePinchBerry?
    next false if !battler.effects[PBEffects::MicleBerry]
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battler.effects[PBEffects::MicleBerry] = true
    itemName = GameData::Item.get(item).name
    if forced
      PBDebug.log("[Item triggered] Forced consuming of #{itemName}")
      battle.pbDisplay(_INTL("{1} boosted the accuracy of its next move!", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1} boosted the accuracy of its next move using its {2}!",
         battler.pbThis, itemName))
    end
    next true
  }
)

PBAI::ItemEffects::HPHeal.add(:ORANBERRY,
  proc { |item, battler, battle, forced|
    next false if !battler.canHeal?
    next false if !forced && !battler.canConsumePinchBerry?(false)
    amt = 10
    ripening = false
    if battler.hasActiveAbility?(:RIPEN)
      battle.pbShowAbilitySplash(battler, forced)
      amt *= 2
      ripening = true
    end
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battle.pbHideAbilitySplash(battler) if ripening
    battler.pbRecoverHP(amt)
    itemName = GameData::Item.get(item).name
    if forced
      PBDebug.log("[Item triggered] Forced consuming of #{itemName}")
      battle.pbDisplay(_INTL("{1}'s HP was restored.", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1} restored a little HP using its {2}!", battler.pbThis, itemName))
    end
    next true
  }
)

PBAI::ItemEffects::HPHeal.add(:PETAYABERRY,
  proc { |item, battler, battle, forced|
    next battler.pbStatIncreasingBerry(item, forced, :SPECIAL_ATTACK)
  }
)

PBAI::ItemEffects::HPHeal.add(:SALACBERRY,
  proc { |item, battler, battle, forced|
    next battler.pbStatIncreasingBerry(item, forced, :SPEED)
  }
)

PBAI::ItemEffects::HPHeal.add(:SITRUSBERRY,
  proc { |item, battler, battle, forced|
    next false if !battler.canHeal?
    next false if !forced && !battler.canConsumePinchBerry?(false)
    amt = battler.totalhp / 4
    ripening = false
    if battler.hasActiveAbility?(:RIPEN)
      battle.pbShowAbilitySplash(battler, forced)
      amt *= 2
      ripening = true
    end
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battle.pbHideAbilitySplash(battler) if ripening
    battler.pbRecoverHP(amt)
    itemName = GameData::Item.get(item).name
    if forced
      PBDebug.log("[Item triggered] Forced consuming of #{itemName}")
      battle.pbDisplay(_INTL("{1}'s HP was restored.", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1} restored its health using its {2}!", battler.pbThis, itemName))
    end
    next true
  }
)

PBAI::ItemEffects::HPHeal.add(:STARFBERRY,
  proc { |item, battler, battle, forced|
    stats = []
    GameData::Stat.each_main_battle { |s| stats.push(s.id) if battler.pbCanRaiseStatStage?(s.id, battler) }
    next false if stats.length == 0
    stat = stats[battle.pbRandom(stats.length)]
    next battler.pbStatIncreasingBerry(item, forced, stat, 2)
  }
)

PBAI::ItemEffects::HPHeal.add(:WIKIBERRY,
  proc { |item, battler, battle, forced|
    next battler.pbConfusionBerry(item, forced, 3,
       _INTL("For {1}, the {2} was too dry!", battler.pbThis(true), GameData::Item.get(item).name)
    )
  }
)

#===============================================================================
# OnStatLoss handlers
#===============================================================================
PBAI::ItemEffects::OnStatLoss.add(:EJECTPACK,
  proc { |item, battler, move_user, battle|
    next false if battler.effects[PBEffects::SkyDrop] >= 0 ||
                  battler.inTwoTurnAttack?("TwoTurnAttackInvulnerableInSkyTargetCannotAct")   # Sky Drop
    next false if battle.pbAllFainted?(battler.idxOpposingSide)
    next false if battler.wild?   # Wild Pokémon can't eject
    next false if !battle.pbCanSwitch?(battler.index)   # Battler can't switch out
    next false if !battle.pbCanChooseNonActive?(battler.index)   # No Pokémon can switch in
    battle.pbCommonAnimation("UseItem", battler)
    battle.pbDisplay(_INTL("{1} is switched out by the {2}!", battler.pbThis, battler.itemName))
    battler.pbConsumeItem(true, false)
    if battle.endOfRound   # Just switch out
      battle.scene.pbRecall(battler.index) if !battler.fainted?
      battler.pbAbilitiesOnSwitchOut   # Inc. primordial weather check
      next true
    end
    newPkmn = battle.pbGetReplacementPokemonIndex(battler.index)   # Owner chooses
    next false if newPkmn < 0   # Shouldn't ever do this
    battle.pbRecallAndReplace(battler.index, newPkmn)
    battle.pbClearChoice(battler.index)   # Replacement Pokémon does nothing this round
    battle.moldBreaker = false if move_user && battler.index == move_user.index
    battle.pbOnBattlerEnteringBattle(battler.index)
    next true
  }
)

#===============================================================================
# StatusCure handlers
#===============================================================================

PBAI::ItemEffects::StatusCure.add(:ASPEARBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if battler.status != :FROZEN
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battler.pbCureStatus(forced)
    battle.pbDisplay(_INTL("{1}'s {2} defrosted it!", battler.pbThis, itemName)) if !forced
    next true
  }
)

PBAI::ItemEffects::StatusCure.add(:CHERIBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if battler.status != :PARALYSIS
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battler.pbCureStatus(forced)
    battle.pbDisplay(_INTL("{1}'s {2} cured its paralysis!", battler.pbThis, itemName)) if !forced
    next true
  }
)

PBAI::ItemEffects::StatusCure.add(:CHESTOBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if battler.status != :SLEEP
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battler.pbCureStatus(forced)
    battle.pbDisplay(_INTL("{1}'s {2} woke it up!", battler.pbThis, itemName)) if !forced
    next true
  }
)

PBAI::ItemEffects::StatusCure.add(:LUMBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if battler.status == :NONE &&
                  battler.effects[PBEffects::Confusion] == 0
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    oldStatus = battler.status
    oldConfusion = (battler.effects[PBEffects::Confusion] > 0)
    battler.pbCureStatus(forced)
    battler.pbCureConfusion
    if forced
      battle.pbDisplay(_INTL("{1} snapped out of its confusion.", battler.pbThis)) if oldConfusion
    else
      case oldStatus
      when :SLEEP
        battle.pbDisplay(_INTL("{1}'s {2} woke it up!", battler.pbThis, itemName))
      when :POISON
        battle.pbDisplay(_INTL("{1}'s {2} cured its poisoning!", battler.pbThis, itemName))
      when :BURN
        battle.pbDisplay(_INTL("{1}'s {2} healed its burn!", battler.pbThis, itemName))
      when :PARALYSIS
        battle.pbDisplay(_INTL("{1}'s {2} cured its paralysis!", battler.pbThis, itemName))
      when :FROZEN
        battle.pbDisplay(_INTL("{1}'s {2} defrosted it!", battler.pbThis, itemName))
      end
      if oldConfusion
        battle.pbDisplay(_INTL("{1}'s {2} snapped it out of its confusion!", battler.pbThis, itemName))
      end
    end
    next true
  }
)

PBAI::ItemEffects::StatusCure.add(:MENTALHERB,
  proc { |item, battler, battle, forced|
    next false if battler.effects[PBEffects::Attract] == -1 &&
                  battler.effects[PBEffects::Taunt] == 0 &&
                  battler.effects[PBEffects::Encore] == 0 &&
                  !battler.effects[PBEffects::Torment] &&
                  battler.effects[PBEffects::Disable] == 0 &&
                  battler.effects[PBEffects::HealBlock] == 0
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}")
    battle.pbCommonAnimation("UseItem", battler) if !forced
    if battler.effects[PBEffects::Attract] >= 0
      if forced
        battle.pbDisplay(_INTL("{1} got over its infatuation.", battler.pbThis))
      else
        battle.pbDisplay(_INTL("{1} cured its infatuation status using its {2}!",
           battler.pbThis, itemName))
      end
      battler.pbCureAttract
    end
    battle.pbDisplay(_INTL("{1}'s taunt wore off!", battler.pbThis)) if battler.effects[PBEffects::Taunt] > 0
    battler.effects[PBEffects::Taunt] = 0
    battle.pbDisplay(_INTL("{1}'s encore ended!", battler.pbThis)) if battler.effects[PBEffects::Encore] > 0
    battler.effects[PBEffects::Encore]     = 0
    battler.effects[PBEffects::EncoreMove] = nil
    battle.pbDisplay(_INTL("{1}'s torment wore off!", battler.pbThis)) if battler.effects[PBEffects::Torment]
    battler.effects[PBEffects::Torment] = false
    battle.pbDisplay(_INTL("{1} is no longer disabled!", battler.pbThis)) if battler.effects[PBEffects::Disable] > 0
    battler.effects[PBEffects::Disable] = 0
    battle.pbDisplay(_INTL("{1}'s Heal Block wore off!", battler.pbThis)) if battler.effects[PBEffects::HealBlock] > 0
    battler.effects[PBEffects::HealBlock] = 0
    next true
  }
)

PBAI::ItemEffects::StatusCure.add(:PECHABERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if battler.status != :POISON
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battler.pbCureStatus(forced)
    battle.pbDisplay(_INTL("{1}'s {2} cured its poisoning!", battler.pbThis, itemName)) if !forced
    next true
  }
)

PBAI::ItemEffects::StatusCure.add(:PERSIMBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if battler.effects[PBEffects::Confusion] == 0
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battler.pbCureConfusion
    if forced
      battle.pbDisplay(_INTL("{1} snapped out of its confusion.", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1}'s {2} snapped it out of its confusion!", battler.pbThis,
         itemName))
    end
    next true
  }
)

PBAI::ItemEffects::StatusCure.add(:RAWSTBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if battler.status != :BURN
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battler.pbCureStatus(forced)
    battle.pbDisplay(_INTL("{1}'s {2} healed its burn!", battler.pbThis, itemName)) if !forced
    next true
  }
)

#===============================================================================
# PriorityBracketChange handlers
#===============================================================================

PBAI::ItemEffects::PriorityBracketChange.add(:CUSTAPBERRY,
  proc { |item, battler, battle|
    next 1 if battler.canConsumePinchBerry?
  }
)

PBAI::ItemEffects::PriorityBracketChange.add(:LAGGINGTAIL,
  proc { |item, battler, battle|
    next -1
  }
)

PBAI::ItemEffects::PriorityBracketChange.copy(:LAGGINGTAIL, :FULLINCENSE)

PBAI::ItemEffects::PriorityBracketChange.add(:QUICKCLAW,
  proc { |item, battler, battle|
    next 1 if battle.pbRandom(100) < 20
  }
)

#===============================================================================
# PriorityBracketUse handlers
#===============================================================================

PBAI::ItemEffects::PriorityBracketUse.add(:CUSTAPBERRY,
  proc { |item, battler, battle|
    battle.pbCommonAnimation("EatBerry", battler)
    battle.pbDisplay(_INTL("{1}'s {2} let it move first!", battler.pbThis, battler.itemName))
    battler.pbConsumeItem
  }
)

PBAI::ItemEffects::PriorityBracketUse.add(:QUICKCLAW,
  proc { |item, battler, battle|
    battle.pbCommonAnimation("UseItem", battler)
    battle.pbDisplay(_INTL("{1}'s {2} let it move first!", battler.pbThis, battler.itemName))
  }
)

#===============================================================================
# OnMissingTarget handlers
#===============================================================================

PBAI::ItemEffects::OnMissingTarget.add(:BLUNDERPOLICY,
  proc { |item, user, target, move, hit_num, battle|
    next if hit_num > 0 || target.damageState.invulnerable
    next if ["OHKO", "OHKOIce", "OHKOHitsUndergroundTarget"].include?(move.function)
    next if !user.pbCanRaiseStatStage?(:SPEED, user)
    battle.pbCommonAnimation("UseItem", user)
    user.pbRaiseStatStageByCause(:SPEED, 2, user, user.itemName)
    battle.pbDisplay(_INTL("The {1} was used up...", user.itemName))
    user.pbHeldItemTriggered(item)
  }
)

#===============================================================================
# AccuracyCalcFromUser handlers
#===============================================================================

PBAI::ItemEffects::AccuracyCalcFromUser.add(:WIDELENS,
  proc { |item, mods, user, target, move, type|
    mods[:accuracy_multiplier] *= 1.1
  }
)

PBAI::ItemEffects::AccuracyCalcFromUser.add(:ZOOMLENS,
  proc { |item, mods, user, target, move, type|
    if (target.battle.choices[target.index][0] != :UseMove &&
       target.battle.choices[target.index][0] != :Shift) ||
       target.movedThisRound?
      mods[:accuracy_multiplier] *= 1.2
    end
  }
)

#===============================================================================
# AccuracyCalcFromTarget handlers
#===============================================================================

PBAI::ItemEffects::AccuracyCalcFromTarget.add(:BRIGHTPOWDER,
  proc { |item, mods, user, target, move, type|
    mods[:accuracy_multiplier] *= 0.9
  }
)

PBAI::ItemEffects::AccuracyCalcFromTarget.copy(:BRIGHTPOWDER, :LAXINCENSE)

#===============================================================================
# DamageCalcFromUser handlers
#===============================================================================

PBAI::ItemEffects::DamageCalcFromUser.add(:ADAMANTORB,
  proc { |item, user, target, move, mults, baseDmg, type|
    if user.isSpecies?(:DIALGA) && [:DRAGON, :STEEL].include?(type)
      mults[:base_damage_multiplier] *= 1.2
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:BLACKBELT,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :FIGHTING
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:BLACKBELT, :FISTPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:BLACKGLASSES,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :DARK
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:BLACKGLASSES, :DREADPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:BUGGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :BUG, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:CHARCOAL,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :FIRE
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:CHARCOAL, :FLAMEPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:CHOICEBAND,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.5 if move.physicalMove?
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:CHOICESPECS,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.5 if move.specialMove?
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:DARKGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :DARK, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:DEEPSEATOOTH,
  proc { |item, user, target, move, mults, baseDmg, type|
    if user.isSpecies?(:CLAMPERL) && move.specialMove?
      mults[:attack_multiplier] *= 2
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:DRAGONFANG,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :DRAGON
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:DRAGONFANG, :DRACOPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:DRAGONGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :DRAGON, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:ELECTRICGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :ELECTRIC, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:EXPERTBELT,
  proc { |item, user, target, move, mults, baseDmg, type|
    if Effectiveness.super_effective?(target.damageState.typeMod)
      mults[:final_damage_multiplier] *= 1.2
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:FAIRYGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :FAIRY, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:FIGHTINGGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :FIGHTING, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:FIREGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :FIRE, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:FLYINGGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :FLYING, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:GHOSTGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :GHOST, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:GRASSGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :GRASS, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:GRISEOUSORB,
  proc { |item, user, target, move, mults, baseDmg, type|
    if user.isSpecies?(:GIRATINA) && [:DRAGON, :GHOST].include?(type)
      mults[:base_damage_multiplier] *= 1.2
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:GROUNDGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :GROUND, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:HARDSTONE,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :ROCK
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:HARDSTONE, :STONEPLATE, :ROCKINCENSE)

PBAI::ItemEffects::DamageCalcFromUser.add(:ICEGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :ICE, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:LIFEORB,
  proc { |item, user, target, move, mults, baseDmg, type|
    if !move.is_a?(PokeBattle_ConfuseMove)
      mults[:final_damage_multiplier] *= 1.3
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:LIGHTBALL,
  proc { |item, user, target, move, mults, baseDmg, type|
    if user.isSpecies?(:PIKACHU)
      mults[:attack_multiplier] *= 2
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:LUSTROUSORB,
  proc { |item, user, target, move, mults, baseDmg, type|
    if user.isSpecies?(:PALKIA) && [:DRAGON, :WATER].include?(type)
      mults[:base_damage_multiplier] *= 1.2
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:MAGNET,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :ELECTRIC
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:MAGNET, :ZAPPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:METALCOAT,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :STEEL
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:METALCOAT, :IRONPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:METRONOME,
  proc { |item, user, target, move, mults, baseDmg, type|
    met = 1 + (0.2 * [user.effects[PBEffects::Metronome], 5].min)
    mults[:final_damage_multiplier] *= met
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:MIRACLESEED,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :GRASS
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:MIRACLESEED, :MEADOWPLATE, :ROSEINCENSE)

PBAI::ItemEffects::DamageCalcFromUser.add(:MUSCLEBAND,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.1 if move.physicalMove?
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:MYSTICWATER,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :WATER
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:MYSTICWATER, :SPLASHPLATE, :SEAINCENSE, :WAVEINCENSE)

PBAI::ItemEffects::DamageCalcFromUser.add(:NEVERMELTICE,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :ICE
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:NEVERMELTICE, :ICICLEPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:NORMALGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :NORMAL, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:PIXIEPLATE,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :FAIRY
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:POISONBARB,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :POISON
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:POISONBARB, :TOXICPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:POISONGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :POISON, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:PSYCHICGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :PSYCHIC, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:ROCKGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :ROCK, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:SHARPBEAK,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :FLYING
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:SHARPBEAK, :SKYPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:SILKSCARF,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :NORMAL
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:SILVERPOWDER,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :BUG
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:SILVERPOWDER, :INSECTPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:SOFTSAND,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :GROUND
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:SOFTSAND, :EARTHPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:SOULDEW,
  proc { |item, user, target, move, mults, baseDmg, type|
    next if !user.isSpecies?(:LATIAS) && !user.isSpecies?(:LATIOS)
    if Settings::SOUL_DEW_POWERS_UP_TYPES
      mults[:final_damage_multiplier] *= 1.2 if [:DRAGON, :PSYCHIC].include?(type)
    elsif move.specialMove? && !user.battle.rules["souldewclause"]
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:SPELLTAG,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :GHOST
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:SPELLTAG, :SPOOKYPLATE)

PBAI::ItemEffects::DamageCalcFromUser.add(:STEELGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :STEEL, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:THICKCLUB,
  proc { |item, user, target, move, mults, baseDmg, type|
    if (user.isSpecies?(:CUBONE) || user.isSpecies?(:MAROWAK)) && move.physicalMove?
      mults[:attack_multiplier] *= 2
    end
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:TWISTEDSPOON,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if type == :PSYCHIC
  }
)

PBAI::ItemEffects::DamageCalcFromUser.copy(:TWISTEDSPOON, :MINDPLATE, :ODDINCENSE)

PBAI::ItemEffects::DamageCalcFromUser.add(:WATERGEM,
  proc { |item, user, target, move, mults, baseDmg, type|
    user.pbBattleGem(user, :WATER, move, type, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromUser.add(:WISEGLASSES,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.1 if move.specialMove?
  }
)

#===============================================================================
# DamageCalcFromTarget handlers
# NOTE: Species-specific held items consider the original species, not the
#       transformed species, and still work while transformed. The exceptions
#       are Metal/Quick Powder, which don't work if the holder is transformed.
#===============================================================================

PBAI::ItemEffects::DamageCalcFromTarget.add(:ASSAULTVEST,
  proc { |item, user, target, move, mults, baseDmg, type|
    mults[:defense_multiplier] *= 1.5 if move.specialMove?
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:BABIRIBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:STEEL, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:CHARTIBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:ROCK, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:CHILANBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:NORMAL, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:CHOPLEBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:FIGHTING, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:COBABERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:FLYING, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:COLBURBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:DARK, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:DEEPSEASCALE,
  proc { |item, user, target, move, mults, baseDmg, type|
    if target.isSpecies?(:CLAMPERL) && move.specialMove?
      mults[:defense_multiplier] *= 2
    end
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:EVIOLITE,
  proc { |item, user, target, move, mults, baseDmg, type|
    # NOTE: Eviolite cares about whether the Pokémon itself can evolve, which
    #       means it also cares about the Pokémon's form. Some forms cannot
    #       evolve even if the species generally can, and such forms are not
    #       affected by Eviolite.
    if target.pokemon.species_data.get_evolutions(true).length > 0
      mults[:defense_multiplier] *= 1.5
    end
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:HABANBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:DRAGON, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:KASIBBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:GHOST, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:KEBIABERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:POISON, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:METALPOWDER,
  proc { |item, user, target, move, mults, baseDmg, type|
    if target.isSpecies?(:DITTO) && !target.effects[PBEffects::Transform]
      mults[:defense_multiplier] *= 1.5
    end
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:OCCABERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:FIRE, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:PASSHOBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:WATER, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:PAYAPABERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:PSYCHIC, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:RINDOBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:GRASS, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:ROSELIBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:FAIRY, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:SHUCABERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:GROUND, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:SOULDEW,
  proc { |item, user, target, move, mults, baseDmg, type|
    next if Settings::SOUL_DEW_POWERS_UP_TYPES
    next if !target.isSpecies?(:LATIAS) && !target.isSpecies?(:LATIOS)
    if move.specialMove? && !user.battle.rules["souldewclause"]
      mults[:defense_multiplier] *= 1.5
    end
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:TANGABERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:BUG, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:WACANBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:ELECTRIC, type, target, mults)
  }
)

PBAI::ItemEffects::DamageCalcFromTarget.add(:YACHEBERRY,
  proc { |item, user, target, move, mults, baseDmg, type|
    target.pbBattleTypeWeakingBerry(:ICE, type, target, mults)
  }
)

#===============================================================================
# CriticalCalcFromUser handlers
#===============================================================================

PBAI::ItemEffects::CriticalCalcFromUser.add(:LUCKYPUNCH,
  proc { |item, user, target, c|
    next c + 2 if user.isSpecies?(:CHANSEY)
  }
)

PBAI::ItemEffects::CriticalCalcFromUser.add(:RAZORCLAW,
  proc { |item, user, target, c|
    next c + 1
  }
)

PBAI::ItemEffects::CriticalCalcFromUser.copy(:RAZORCLAW, :SCOPELENS)

PBAI::ItemEffects::CriticalCalcFromUser.add(:LEEK,
  proc { |item, user, target, c|
    next c + 2 if user.isSpecies?(:FARFETCHD) || user.isSpecies?(:SIRFETCHD)
  }
)

PBAI::ItemEffects::CriticalCalcFromUser.copy(:LEEK, :STICK)

#===============================================================================
# CriticalCalcFromTarget handlers
#===============================================================================

# There aren't any!

#===============================================================================
# OnBeingHit handlers
#===============================================================================

PBAI::ItemEffects::OnBeingHit.add(:ABSORBBULB,
  proc { |item, user, target, move, battle|
    next if move.calcType != :WATER
    next if !target.pbCanRaiseStatStage?(:SPECIAL_ATTACK, target)
    battle.pbCommonAnimation("UseItem", target)
    target.pbRaiseStatStageByCause(:SPECIAL_ATTACK, 1, target, target.itemName)
    target.pbHeldItemTriggered(item)
  }
)

PBAI::ItemEffects::OnBeingHit.add(:AIRBALLOON,
  proc { |item, user, target, move, battle|
    battle.pbDisplay(_INTL("{1}'s {2} popped!", target.pbThis, target.itemName))
    target.pbConsumeItem(false, true)
    target.pbSymbiosis
  }
)

PBAI::ItemEffects::OnBeingHit.add(:CELLBATTERY,
  proc { |item, user, target, move, battle|
    next if move.calcType != :ELECTRIC
    next if !target.pbCanRaiseStatStage?(:ATTACK, target)
    battle.pbCommonAnimation("UseItem", target)
    target.pbRaiseStatStageByCause(:ATTACK, 1, target, target.itemName)
    target.pbHeldItemTriggered(item)
  }
)

PBAI::ItemEffects::OnBeingHit.add(:ENIGMABERRY,
  proc { |item, user, target, move, battle|
    next if target.damageState.substitute ||
            target.damageState.disguise || target.damageState.iceface
    next if !Effectiveness.super_effective?(target.damageState.typeMod)
    if PBAI::ItemEffects.triggerOnBeingHitPositiveBerry(item, target, battle, false)
      target.pbHeldItemTriggered(item)
    end
  }
)

PBAI::ItemEffects::OnBeingHit.add(:JABOCABERRY,
  proc { |item, user, target, move, battle|
    next if !target.canConsumeBerry?
    next if !move.physicalMove?
    next if !user.takesIndirectDamage?
    amt = user.totalhp / 8
    ripening = false
    if target.hasActiveAbility?(:RIPEN)
      battle.pbShowAbilitySplash(target)
      amt *= 2
      ripening = true
    end
    battle.pbCommonAnimation("EatBerry", target)
    battle.pbHideAbilitySplash(user) if ripening
    battle.scene.pbDamageAnimation(user)
    user.pbReduceHP(amt, false)
    battle.pbDisplay(_INTL("{1} consumed its {2} and hurt {3}!", target.pbThis,
       target.itemName, user.pbThis(true)))
    target.pbHeldItemTriggered(item)
  }
)

# NOTE: Kee Berry supposedly shouldn't trigger if the user has Sheer Force, but
#       I'm ignoring this. Weakness Policy has the same kind of effect and
#       nowhere says it should be stopped by Sheer Force. I suspect this
#       stoppage is either a false report that no one ever corrected, or an
#       effect that later changed and wasn't noticed.
PBAI::ItemEffects::OnBeingHit.add(:KEEBERRY,
  proc { |item, user, target, move, battle|
    next if !move.physicalMove?
    if PBAI::ItemEffects.triggerOnBeingHitPositiveBerry(item, target, battle, false)
      target.pbHeldItemTriggered(item)
    end
  }
)

PBAI::ItemEffects::OnBeingHit.add(:LUMINOUSMOSS,
  proc { |item, user, target, move, battle|
    next if move.calcType != :WATER
    next if !target.pbCanRaiseStatStage?(:SPECIAL_DEFENSE, target)
    battle.pbCommonAnimation("UseItem", target)
    target.pbRaiseStatStageByCause(:SPECIAL_DEFENSE, 1, target, target.itemName)
    target.pbHeldItemTriggered(item)
  }
)

# NOTE: Maranga Berry supposedly shouldn't trigger if the user has Sheer Force,
#       but I'm ignoring this. Weakness Policy has the same kind of effect and
#       nowhere says it should be stopped by Sheer Force. I suspect this
#       stoppage is either a false report that no one ever corrected, or an
#       effect that later changed and wasn't noticed.
PBAI::ItemEffects::OnBeingHit.add(:MARANGABERRY,
  proc { |item, user, target, move, battle|
    next if !move.specialMove?
    if PBAI::ItemEffects.triggerOnBeingHitPositiveBerry(item, target, battle, false)
      target.pbHeldItemTriggered(item)
    end
  }
)

PBAI::ItemEffects::OnBeingHit.add(:ROCKYHELMET,
  proc { |item, user, target, move, battle|
    next if !move.pbContactMove?(user) || !user.affectedByContactEffect?
    next if !user.takesIndirectDamage?
    battle.scene.pbDamageAnimation(user)
    user.pbReduceHP(user.totalhp / 6, false)
    battle.pbDisplay(_INTL("{1} was hurt by the {2}!", user.pbThis, target.itemName))
  }
)

PBAI::ItemEffects::OnBeingHit.add(:ROWAPBERRY,
  proc { |item, user, target, move, battle|
    next if !target.canConsumeBerry?
    next if !move.specialMove?
    next if !user.takesIndirectDamage?
    amt = user.totalhp / 8
    ripening = false
    if user.hasActiveAbility?(:RIPEN)
      battle.pbShowAbilitySplash(user)
      amt *= 2
      ripening = true
    end
    battle.pbCommonAnimation("EatBerry", target)
    battle.pbHideAbilitySplash(user) if ripening
    battle.scene.pbDamageAnimation(user)
    user.pbReduceHP(amt, false)
    battle.pbDisplay(_INTL("{1} consumed its {2} and hurt {3}!", target.pbThis,
       target.itemName, user.pbThis(true)))
    target.pbHeldItemTriggered(item)
  }
)

PBAI::ItemEffects::OnBeingHit.add(:SNOWBALL,
  proc { |item, user, target, move, battle|
    next if move.calcType != :ICE
    next if !target.pbCanRaiseStatStage?(:ATTACK, target)
    battle.pbCommonAnimation("UseItem", target)
    target.pbRaiseStatStageByCause(:ATTACK, 1, target, target.itemName)
    target.pbHeldItemTriggered(item)
  }
)

PBAI::ItemEffects::OnBeingHit.add(:STICKYBARB,
  proc { |item, user, target, move, battle|
    next if !move.pbContactMove?(user) || !user.affectedByContactEffect?
    next if user.fainted? || user.item
    user.item = target.item
    target.item = nil
    target.effects[PBEffects::Unburden] = true if target.hasActiveAbility?(:UNBURDEN)
    if battle.wildBattle? && !user.opposes? &&
       !user.initialItem && user.item == target.initialItem
      user.setInitialItem(user.item)
      target.setInitialItem(nil)
    end
    battle.pbDisplay(_INTL("{1}'s {2} was transferred to {3}!",
       target.pbThis, user.itemName, user.pbThis(true)))
  }
)

PBAI::ItemEffects::OnBeingHit.add(:WEAKNESSPOLICY,
  proc { |item, user, target, move, battle|
    next if target.damageState.disguise || target.damageState.iceface
    next if !Effectiveness.super_effective?(target.damageState.typeMod)
    next if !target.pbCanRaiseStatStage?(:ATTACK, target) &&
            !target.pbCanRaiseStatStage?(:SPECIAL_ATTACK, target)
    battle.pbCommonAnimation("UseItem", target)
    showAnim = true
    if target.pbCanRaiseStatStage?(:ATTACK, target)
      target.pbRaiseStatStageByCause(:ATTACK, 2, target, target.itemName, showAnim)
      showAnim = false
    end
    if target.pbCanRaiseStatStage?(:SPECIAL_ATTACK, target)
      target.pbRaiseStatStageByCause(:SPECIAL_ATTACK, 2, target, target.itemName, showAnim)
    end
    battle.pbDisplay(_INTL("The {1} was used up...", target.itemName))
    target.pbHeldItemTriggered(item)
  }
)

#===============================================================================
# OnBeingHitPositiveBerry handlers
# NOTE: This is for berries that have an effect when Pluck/Bug Bite/Fling
#       forces their use.
#===============================================================================

PBAI::ItemEffects::OnBeingHitPositiveBerry.add(:ENIGMABERRY,
  proc { |item, battler, battle, forced|
    next false if !battler.canHeal?
    next false if !forced && !battler.canConsumeBerry?
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    amt = battler.totalhp / 4
    ripening = false
    if battler.hasActiveAbility?(:RIPEN)
      battle.pbShowAbilitySplash(battler, forced)
      amt *= 2
      ripening = true
    end
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battle.pbHideAbilitySplash(battler) if ripening
    battler.pbRecoverHP(amt)
    if forced
      battle.pbDisplay(_INTL("{1}'s HP was restored.", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1} restored its health using its {2}!", battler.pbThis, itemName))
    end
    next true
  }
)

PBAI::ItemEffects::OnBeingHitPositiveBerry.add(:KEEBERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if !battler.pbCanRaiseStatStage?(:DEFENSE, battler)
    itemName = GameData::Item.get(item).name
    amt = 1
    ripening = false
    if battler.hasActiveAbility?(:RIPEN)
      battle.pbShowAbilitySplash(battler, forced)
      amt *= 2
      ripening = true
    end
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battle.pbHideAbilitySplash(battler) if ripening
    next battler.pbRaiseStatStageByCause(:DEFENSE, amt, battler, itemName) if !forced
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}")
    next battler.pbRaiseStatStage(:DEFENSE, amt, battler)
  }
)

PBAI::ItemEffects::OnBeingHitPositiveBerry.add(:MARANGABERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    next false if !battler.pbCanRaiseStatStage?(:SPECIAL_DEFENSE, battler)
    itemName = GameData::Item.get(item).name
    amt = 1
    ripening = false
    if battler.hasActiveAbility?(:RIPEN)
      battle.pbShowAbilitySplash(battler, forced)
      amt *= 2
      ripening = true
    end
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battle.pbHideAbilitySplash(battler) if ripening
    next battler.pbRaiseStatStageByCause(:SPECIAL_DEFENSE, amt, battler, itemName) if !forced
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}")
    next battler.pbRaiseStatStage(:SPECIAL_DEFENSE, amt, battler)
  }
)

#===============================================================================
# AfterMoveUseFromTarget handlers
#===============================================================================

PBAI::ItemEffects::AfterMoveUseFromTarget.add(:EJECTBUTTON,
  proc { |item, battler, user, move, switched_battlers, battle|
    next if !switched_battlers.empty?
    next if battle.pbAllFainted?(battler.idxOpposingSide)
    next if !battle.pbCanChooseNonActive?(battler.index)
    battle.pbCommonAnimation("UseItem", battler)
    battle.pbDisplay(_INTL("{1} is switched out with the {2}!", battler.pbThis, battler.itemName))
    battler.pbConsumeItem(true, false)
    newPkmn = battle.pbGetReplacementPokemonIndex(battler.index)   # Owner chooses
    next if newPkmn < 0
    battle.pbRecallAndReplace(battler.index, newPkmn)
    battle.pbClearChoice(battler.index)   # Replacement Pokémon does nothing this round
    switched_battlers.push(battler.index)
    battle.moldBreaker = false if battler.index == user.index
    battle.pbOnBattlerEnteringBattle(battler.index)
  }
)

PBAI::ItemEffects::AfterMoveUseFromTarget.add(:REDCARD,
  proc { |item, battler, user, move, switched_battlers, battle|
    next if !switched_battlers.empty? || user.fainted?
    newPkmn = battle.pbGetReplacementPokemonIndex(user.index, true)   # Random
    next if newPkmn < 0
    battle.pbCommonAnimation("UseItem", battler)
    battle.pbDisplay(_INTL("{1} held up its {2} against {3}!",
       battler.pbThis, battler.itemName, user.pbThis(true)))
    battler.pbConsumeItem
    if user.hasActiveAbility?(:SUCTIONCUPS) && !battle.moldBreaker
      battle.pbShowAbilitySplash(user)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} anchors itself!", user.pbThis))
      else
        battle.pbDisplay(_INTL("{1} anchors itself with {2}!", user.pbThis, user.abilityName))
      end
      battle.pbHideAbilitySplash(user)
      next
    end
    if user.effects[PBEffects::Ingrain]
      battle.pbDisplay(_INTL("{1} anchored itself with its roots!", user.pbThis))
      next
    end
    battle.pbRecallAndReplace(user.index, newPkmn, true)
    battle.pbDisplay(_INTL("{1} was dragged out!", user.pbThis))
    battle.pbClearChoice(user.index)   # Replacement Pokémon does nothing this round
    switched_battlers.push(user.index)
    battle.moldBreaker = false
    battle.pbOnBattlerEnteringBattle(user.index)
  }
)

#===============================================================================
# AfterMoveUseFromUser handlers
#===============================================================================

PBAI::ItemEffects::AfterMoveUseFromUser.add(:LIFEORB,
  proc { |item, user, targets, move, numHits, battle|
    next if !user.takesIndirectDamage?
    next if !move.pbDamagingMove? || numHits == 0
    hitBattler = false
    targets.each do |b|
      hitBattler = true if !b.damageState.unaffected && !b.damageState.substitute
      break if hitBattler
    end
    next if !hitBattler
    PBDebug.log("[Item triggered] #{user.pbThis}'s #{user.itemName} (recoil)")
    user.pbReduceHP(user.totalhp / 10)
    battle.pbDisplay(_INTL("{1} lost some of its HP!", user.pbThis))
    user.pbItemHPHealCheck
    user.pbFaint if user.fainted?
  }
)

# NOTE: In the official games, Shell Bell does not prevent Emergency Exit/Wimp
#       Out triggering even if Shell Bell heals the holder back to 50% HP or
#       more. Essentials ignores this exception.
PBAI::ItemEffects::AfterMoveUseFromUser.add(:SHELLBELL,
  proc { |item, user, targets, move, numHits, battle|
    next if !user.canHeal?
    totalDamage = 0
    targets.each { |b| totalDamage += b.damageState.totalHPLost }
    next if totalDamage <= 0
    user.pbRecoverHP(totalDamage / 8)
    battle.pbDisplay(_INTL("{1} restored a little HP using its {2}!",
       user.pbThis, user.itemName))
  }
)

PBAI::ItemEffects::AfterMoveUseFromUser.add(:THROATSPRAY,
  proc { |item, user, targets, move, numHits, battle|
    next if battle.pbAllFainted?(user.idxOwnSide) ||
            battle.pbAllFainted?(user.idxOpposingSide)
    next if !move.soundMove? || numHits == 0
    next if !user.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user)
    battle.pbCommonAnimation("UseItem", user)
    user.pbRaiseStatStage(:SPECIAL_ATTACK, 1, user)
    user.pbConsumeItem
  }
)

#===============================================================================
# OnEndOfUsingMove handlers
#===============================================================================

PBAI::ItemEffects::OnEndOfUsingMove.add(:LEPPABERRY,
  proc { |item, battler, battle, forced|
    next false if !forced && !battler.canConsumeBerry?
    found_empty_moves = []
    found_partial_moves = []
    battler.pokemon.moves.each_with_index do |move, i|
      next if move.total_pp <= 0 || move.pp == move.total_pp
      (move.pp == 0) ? found_empty_moves.push(i) : found_partial_moves.push(i)
    end
    next false if found_empty_moves.empty? && (!forced || found_partial_moves.empty?)
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    amt = 10
    ripening = false
    if battler.hasActiveAbility?(:RIPEN)
      battle.pbShowAbilitySplash(battler, forced)
      amt *= 2
      ripening = true
    end
    battle.pbCommonAnimation("EatBerry", battler) if !forced
    battle.pbHideAbilitySplash(battler) if ripening
    choice = found_empty_moves.first
    choice = found_partial_moves.first if forced && choice.nil?
    pkmnMove = battler.pokemon.moves[choice]
    pkmnMove.pp += amt
    pkmnMove.pp = pkmnMove.total_pp if pkmnMove.pp > pkmnMove.total_pp
    battler.moves[choice].pp = pkmnMove.pp
    moveName = pkmnMove.name
    if forced
      battle.pbDisplay(_INTL("{1} restored its {2}'s PP.", battler.pbThis, moveName))
    else
      battle.pbDisplay(_INTL("{1}'s {2} restored its {3}'s PP!", battler.pbThis, itemName, moveName))
    end
    next true
  }
)

#===============================================================================
# OnEndOfUsingMoveStatRestore handlers
#===============================================================================

PBAI::ItemEffects::OnEndOfUsingMoveStatRestore.add(:WHITEHERB,
  proc { |item, battler, battle, forced|
    reducedStats = false
    GameData::Stat.each_battle do |s|
      next if battler.stages[s.id] >= 0
      battler.stages[s.id] = 0
      battler.statsRaisedThisRound = true
      reducedStats = true
    end
    next false if !reducedStats
    itemName = GameData::Item.get(item).name
    PBDebug.log("[Item triggered] #{battler.pbThis}'s #{itemName}") if forced
    battle.pbCommonAnimation("UseItem", battler) if !forced
    if forced
      battle.pbDisplay(_INTL("{1}'s status returned to normal!", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1} returned its status to normal using its {2}!",
         battler.pbThis, itemName))
    end
    next true
  }
)

#===============================================================================
# ExpGainModifier handlers
#===============================================================================

PBAI::ItemEffects::ExpGainModifier.add(:LUCKYEGG,
  proc { |item, battler, exp|
    next exp * 3 / 2
  }
)

#===============================================================================
# EVGainModifier handlers
#===============================================================================

PBAI::ItemEffects::EVGainModifier.add(:MACHOBRACE,
  proc { |item, battler, evYield|
    evYield.each_key { |stat| evYield[stat] *= 2 }
  }
)

PBAI::ItemEffects::EVGainModifier.add(:POWERANKLET,
  proc { |item, battler, evYield|
    evYield[:SPEED] += (Settings::MORE_EVS_FROM_POWER_ITEMS) ? 8 : 4
  }
)

PBAI::ItemEffects::EVGainModifier.add(:POWERBAND,
  proc { |item, battler, evYield|
    evYield[:SPECIAL_DEFENSE] += (Settings::MORE_EVS_FROM_POWER_ITEMS) ? 8 : 4
  }
)

PBAI::ItemEffects::EVGainModifier.add(:POWERBELT,
  proc { |item, battler, evYield|
    evYield[:DEFENSE] += (Settings::MORE_EVS_FROM_POWER_ITEMS) ? 8 : 4
  }
)

PBAI::ItemEffects::EVGainModifier.add(:POWERBRACER,
  proc { |item, battler, evYield|
    evYield[:ATTACK] += (Settings::MORE_EVS_FROM_POWER_ITEMS) ? 8 : 4
  }
)

PBAI::ItemEffects::EVGainModifier.add(:POWERLENS,
  proc { |item, battler, evYield|
    evYield[:SPECIAL_ATTACK] += (Settings::MORE_EVS_FROM_POWER_ITEMS) ? 8 : 4
  }
)

PBAI::ItemEffects::EVGainModifier.add(:POWERWEIGHT,
  proc { |item, battler, evYield|
    evYield[:HP] += (Settings::MORE_EVS_FROM_POWER_ITEMS) ? 8 : 4
  }
)

#===============================================================================
# WeatherExtender handlers
#===============================================================================

PBAI::ItemEffects::WeatherExtender.add(:DAMPROCK,
  proc { |item, weather, duration, battler, battle|
    next 8 if weather == :Rain
  }
)

PBAI::ItemEffects::WeatherExtender.add(:HEATROCK,
  proc { |item, weather, duration, battler, battle|
    next 8 if weather == :Sun
  }
)

PBAI::ItemEffects::WeatherExtender.add(:ICYROCK,
  proc { |item, weather, duration, battler, battle|
    next 8 if weather == :Hail
  }
)

PBAI::ItemEffects::WeatherExtender.add(:SMOOTHROCK,
  proc { |item, weather, duration, battler, battle|
    next 8 if weather == :Sandstorm
  }
)

#===============================================================================
# TerrainExtender handlers
#===============================================================================

PBAI::ItemEffects::TerrainExtender.add(:TERRAINEXTENDER,
  proc { |item, terrain, duration, battler, battle|
    next 8
  }
)

#===============================================================================
# TerrainStatBoost handlers
#===============================================================================

PBAI::ItemEffects::TerrainStatBoost.add(:ELECTRICSEED,
  proc { |item, battler, battle|
    next false if battle.field.terrain != :Electric
    next false if !battler.pbCanRaiseStatStage?(:DEFENSE, battler)
    itemName = GameData::Item.get(item).name
    battle.pbCommonAnimation("UseItem", battler)
    next battler.pbRaiseStatStageByCause(:DEFENSE, 1, battler, itemName)
  }
)

PBAI::ItemEffects::TerrainStatBoost.add(:GRASSYSEED,
  proc { |item, battler, battle|
    next false if battle.field.terrain != :Grassy
    next false if !battler.pbCanRaiseStatStage?(:DEFENSE, battler)
    itemName = GameData::Item.get(item).name
    battle.pbCommonAnimation("UseItem", battler)
    next battler.pbRaiseStatStageByCause(:DEFENSE, 1, battler, itemName)
  }
)

PBAI::ItemEffects::TerrainStatBoost.add(:MISTYSEED,
  proc { |item, battler, battle|
    next false if battle.field.terrain != :Misty
    next false if !battler.pbCanRaiseStatStage?(:SPECIAL_DEFENSE, battler)
    itemName = GameData::Item.get(item).name
    battle.pbCommonAnimation("UseItem", battler)
    next battler.pbRaiseStatStageByCause(:SPECIAL_DEFENSE, 1, battler, itemName)
  }
)

PBAI::ItemEffects::TerrainStatBoost.add(:PSYCHICSEED,
  proc { |item, battler, battle|
    next false if battle.field.terrain != :Psychic
    next false if !battler.pbCanRaiseStatStage?(:SPECIAL_DEFENSE, battler)
    itemName = GameData::Item.get(item).name
    battle.pbCommonAnimation("UseItem", battler)
    next battler.pbRaiseStatStageByCause(:SPECIAL_DEFENSE, 1, battler, itemName)
  }
)

#===============================================================================
# EndOfRoundHealing handlers
#===============================================================================

PBAI::ItemEffects::EndOfRoundHealing.add(:BLACKSLUDGE,
  proc { |item, battler, battle|
    if battler.pbHasType?(:POISON)
      next if !battler.canHeal?
      battle.pbCommonAnimation("UseItem", battler)
      battler.pbRecoverHP(battler.totalhp / 16)
      battle.pbDisplay(_INTL("{1} restored a little HP using its {2}!",
         battler.pbThis, battler.itemName))
    elsif battler.takesIndirectDamage?
      battle.pbCommonAnimation("UseItem", battler)
      battler.pbTakeEffectDamage(battler.totalhp / 8) { |hp_lost|
        battle.pbDisplay(_INTL("{1} is hurt by its {2}!", battler.pbThis, battler.itemName))
      }
    end
  }
)

PBAI::ItemEffects::EndOfRoundHealing.add(:LEFTOVERS,
  proc { |item, battler, battle|
    next if !battler.canHeal?
    battle.pbCommonAnimation("UseItem", battler)
    battler.pbRecoverHP(battler.totalhp / 16)
    battle.pbDisplay(_INTL("{1} restored a little HP using its {2}!",
       battler.pbThis, battler.itemName))
  }
)

#===============================================================================
# EndOfRoundEffect handlers
#===============================================================================

PBAI::ItemEffects::EndOfRoundEffect.add(:FLAMEORB,
  proc { |item, battler, battle|
    next if !battler.pbCanBurn?(battler, false)
    battler.pbBurn(nil, _INTL("{1} was burned by the {2}!", battler.pbThis, battler.itemName))
  }
)

PBAI::ItemEffects::EndOfRoundEffect.add(:STICKYBARB,
  proc { |item, battler, battle|
    next if !battler.takesIndirectDamage?
    battle.scene.pbDamageAnimation(battler)
    battler.pbTakeEffectDamage(battler.totalhp / 8, false) { |hp_lost|
      battle.pbDisplay(_INTL("{1} is hurt by its {2}!", battler.pbThis, battler.itemName))
    }
  }
)

PBAI::ItemEffects::EndOfRoundEffect.add(:TOXICORB,
  proc { |item, battler, battle|
    next if !battler.pbCanPoison?(battler, false)
    battler.pbPoison(nil, _INTL("{1} was badly poisoned by the {2}!",
       battler.pbThis, battler.itemName), true)
  }
)

#===============================================================================
# CertainSwitching handlers
#===============================================================================

PBAI::ItemEffects::CertainSwitching.add(:SHEDSHELL,
  proc { |item, battler, battle|
    next true
  }
)

#===============================================================================
# TrappingByTarget handlers
#===============================================================================

# There aren't any!

#===============================================================================
# OnSwitchIn handlers
#===============================================================================

PBAI::ItemEffects::OnSwitchIn.add(:AIRBALLOON,
  proc { |item, battler, battle|
    battle.pbDisplay(_INTL("{1} floats in the air with its {2}!",
       battler.pbThis, battler.itemName))
  }
)

PBAI::ItemEffects::OnSwitchIn.add(:ROOMSERVICE,
  proc { |item, battler, battle|
    next if battle.field.effects[PBEffects::TrickRoom] == 0
    next if !battler.pbCanLowerStatStage?(:SPEED)
    battle.pbCommonAnimation("UseItem", battler)
    battler.pbLowerStatStage(:SPEED, 1, nil)
    battler.pbConsumeItem
  }
)

#===============================================================================
# OnIntimidated handlers
#===============================================================================

PBAI::ItemEffects::OnIntimidated.add(:ADRENALINEORB,
  proc { |item, battler, battle|
    next false if !battler.pbCanRaiseStatStage?(:SPEED, battler)
    itemName = GameData::Item.get(item).name
    battle.pbCommonAnimation("UseItem", battler)
    next battler.pbRaiseStatStageByCause(:SPEED, 1, battler, itemName)
  }
)

#===============================================================================
# CertainEscapeFromBattle handlers
#===============================================================================

PBAI::ItemEffects::CertainEscapeFromBattle.add(:SMOKEBALL,
  proc { |item, battler|
    next true
  }
)

#===============================================================================
#
#===============================================================================
module PBAI::AbilityEffects
  SpeedCalc                        = AbilityHandlerHash.new
  WeightCalc                       = AbilityHandlerHash.new
  # Battler's HP/stat changed
  OnHPDroppedBelowHalf             = AbilityHandlerHash.new
  # Battler's status problem
  StatusCheckNonIgnorable          = AbilityHandlerHash.new   # Comatose
  StatusImmunity                   = AbilityHandlerHash.new
  StatusImmunityNonIgnorable       = AbilityHandlerHash.new
  StatusImmunityFromAlly           = AbilityHandlerHash.new
  OnStatusInflicted                = AbilityHandlerHash.new   # Synchronize
  StatusCure                       = AbilityHandlerHash.new
  # Battler's stat stages
  StatLossImmunity                 = AbilityHandlerHash.new
  StatLossImmunityNonIgnorable     = AbilityHandlerHash.new   # Full Metal Body
  StatLossImmunityFromAlly         = AbilityHandlerHash.new   # Flower Veil
  OnStatGain                       = AbilityHandlerHash.new   # None!
  OnStatLoss                       = AbilityHandlerHash.new
  # Priority and turn order
  PriorityChange                   = AbilityHandlerHash.new
  PriorityBracketChange            = AbilityHandlerHash.new   # Stall
  PriorityBracketUse               = AbilityHandlerHash.new   # None!
  # Move usage failures
  OnFlinch                         = AbilityHandlerHash.new   # Steadfast
  MoveBlocking                     = AbilityHandlerHash.new
  MoveImmunity                     = AbilityHandlerHash.new
  # Move usage
  ModifyMoveBaseType               = AbilityHandlerHash.new
  # Accuracy calculation
  AccuracyCalcFromUser             = AbilityHandlerHash.new
  AccuracyCalcFromAlly             = AbilityHandlerHash.new   # Victory Star
  AccuracyCalcFromTarget           = AbilityHandlerHash.new
  # Damage calculation
  DamageCalcFromUser               = AbilityHandlerHash.new
  DamageCalcFromAlly               = AbilityHandlerHash.new
  DamageCalcFromTarget             = AbilityHandlerHash.new
  DamageCalcFromTargetNonIgnorable = AbilityHandlerHash.new
  DamageCalcFromTargetAlly         = AbilityHandlerHash.new
  CriticalCalcFromUser             = AbilityHandlerHash.new
  CriticalCalcFromTarget           = AbilityHandlerHash.new
  # Upon a move hitting a target
  OnBeingHit                       = AbilityHandlerHash.new
  OnDealingHit                     = AbilityHandlerHash.new   # Poison Touch
  # Abilities that trigger at the end of using a move
  OnEndOfUsingMove                 = AbilityHandlerHash.new
  AfterMoveUseFromTarget           = AbilityHandlerHash.new
  # End Of Round
  EndOfRoundWeather                = AbilityHandlerHash.new
  EndOfRoundHealing                = AbilityHandlerHash.new
  EndOfRoundEffect                 = AbilityHandlerHash.new
  EndOfRoundGainItem               = AbilityHandlerHash.new
  # Switching and fainting
  CertainSwitching                 = AbilityHandlerHash.new   # None!
  TrappingByTarget                 = AbilityHandlerHash.new
  OnSwitchIn                       = AbilityHandlerHash.new
  OnSwitchOut                      = AbilityHandlerHash.new
  ChangeOnBattlerFainting          = AbilityHandlerHash.new
  OnBattlerFainting                = AbilityHandlerHash.new   # Soul-Heart
  OnTerrainChange                  = AbilityHandlerHash.new   # Mimicry
  OnIntimidated                    = AbilityHandlerHash.new   # Rattled (Gen 8)
  # Running from battle
  CertainEscapeFromBattle          = AbilityHandlerHash.new   # Run Away
  OnTypeChange            = AbilityHandlerHash.new  # Protean, Libero
  OnOpposingStatGain      = AbilityHandlerHash.new  # Opportunist
  ModifyTypeEffectiveness = AbilityHandlerHash.new  # Tera Shell (damage)
  ModifyTypeEffectivenessAlly = AbilityHandlerHash.new  # Tera Shell (damage)
  OnMoveSuccessCheck      = AbilityHandlerHash.new  # Tera Shell (display)
  OnInflictingStatus      = AbilityHandlerHash.new  # Poison Puppeteer
  StatLossImmunityAbilityUnshaken = AbilityHandlerHash.new

  #=============================================================================

  def self.trigger(hash, *args, ret: false)
    new_ret = hash.trigger(*args)
    return (!new_ret.nil?) ? new_ret : ret
  end

  #=============================================================================

  def self.triggerSpeedCalc(ability, battler, mult)
    return trigger(SpeedCalc, ability, battler, mult, ret: mult)
  end

  def self.triggerWeightCalc(ability, battler, weight)
    return trigger(WeightCalc, ability, battler, weight, ret: weight)
  end

  #=============================================================================

  def self.triggerOnHPDroppedBelowHalf(ability, user, move_user, battle)
    return trigger(OnHPDroppedBelowHalf, ability, user, move_user, battle)
  end

  #=============================================================================

  def self.triggerStatusCheckNonIgnorable(ability, battler, status)
    return trigger(StatusCheckNonIgnorable, ability, battler, status)
  end

  def self.triggerStatusImmunity(ability, battler, status)
    return trigger(StatusImmunity, ability, battler, status)
  end

  def self.triggerStatusImmunityNonIgnorable(ability, battler, status)
    return trigger(StatusImmunityNonIgnorable, ability, battler, status)
  end

  def self.triggerStatusImmunityFromAlly(ability, battler, status)
    return trigger(StatusImmunityFromAlly, ability, battler, status)
  end

  def self.triggerOnStatusInflicted(ability, battler, user, status)
    OnStatusInflicted.trigger(ability, battler, user, status)
  end

  def self.triggerStatusCure(ability, battler)
    return trigger(StatusCure, ability, battler)
  end

  def self.triggerOnStatusInflicted(ability, battler, user, status)
    OnInflictingStatus.trigger(user.ability, user, battler, status) if user && user.abilityActive? # Poison Puppeteer
    OnStatusInflicted.trigger(ability, battler, user, status)
  end
  
  def self.triggerOnSwitchIn(ability, battler, battle, switch_in = false)
    OnSwitchIn.trigger(ability, battler, battle, switch_in)
    battle.allSameSideBattlers(battler.index).each do |b|
      next if !b.hasActiveAbility?(:COMMANDER)
      next if b.effects[PBEffects::Commander]
      OnSwitchIn.trigger(b.ability, b, battle, switch_in)   
    end
  end

  def self.triggerStatLossImmunityAbilityUnshaken(ability, battler, stat, battle, show_messages)
    ret = StatLossImmunityAbilityUnshaken.trigger(ability, battler, stat, battle, show_messages)
    return (ret!=nil) ? ret : false
  end

  def self.triggerOnTypeChange(ability, battler, type)
    OnTypeChange.trigger(ability, battler, type)
  end

  def self.triggerOnOpposingStatGain(ability, battler, battle, statUps)
    OnOpposingStatGain.trigger(ability, battler, battle, statUps)
  end
  
  def self.triggerModifyTypeEffectiveness(ability, user, target, move, battle, effectiveness)
    return trigger(ModifyTypeEffectiveness, ability, user, target, move, battle, effectiveness, ret: effectiveness)
  end

  def self.triggerModifyTypeEffectivenessAlly(ability, user, target, move, battle, effectiveness)
    return trigger(ModifyTypeEffectivenessAlly, ability, user, target, move, battle, effectiveness, ret: effectiveness)
  end
  
  def self.triggerOnMoveSuccessCheck(ability, user, target, move, battle)
    OnMoveSuccessCheck.trigger(ability, user, target, move, battle)
  end

  def self.triggerOnInflictingStatus(ability, battler, user, status)
    OnInflictingStatus.trigger(ability, battler, user, status)
  end

  #=============================================================================

  def self.triggerStatLossImmunity(ability, battler, stat, battle, show_messages)
    return trigger(StatLossImmunity, ability, battler, stat, battle, show_messages)
  end

  def self.triggerStatLossImmunityNonIgnorable(ability, battler, stat, battle, show_messages)
    return trigger(StatLossImmunityNonIgnorable, ability, battler, stat, battle, show_messages)
  end

  def self.triggerStatLossImmunityFromAlly(ability, bearer, battler, stat, battle, show_messages)
    return trigger(StatLossImmunityFromAlly, ability, bearer, battler, stat, battle, show_messages)
  end

  def self.triggerOnStatGain(ability, battler, stat, user)
    OnStatGain.trigger(ability, battler, stat, user)
  end

  def self.triggerOnStatLoss(ability, battler, stat, user)
    OnStatLoss.trigger(ability, battler, stat, user)
  end

  #=============================================================================

  def self.triggerPriorityChange(ability, battler, move, priority)
    return trigger(PriorityChange, ability, battler, move, priority, ret: priority)
  end

  def self.triggerPriorityBracketChange(ability, battler, battle)
    return trigger(PriorityBracketChange, ability, battler, battle, ret: 0)
  end

  def self.triggerPriorityBracketUse(ability, battler, battle)
    PriorityBracketUse.trigger(ability, battler, battle)
  end

  #=============================================================================

  def self.triggerOnFlinch(ability, battler, battle)
    OnFlinch.trigger(ability, battler, battle)
  end

  def self.triggerMoveBlocking(ability, bearer, user, targets, move, battle)
    return trigger(MoveBlocking, ability, bearer, user, targets, move, battle)
  end

  def self.triggerMoveImmunity(ability, user, target, move, type, battle, show_message)
    return trigger(MoveImmunity, ability, user, target, move, type, battle, show_message)
  end

  #=============================================================================

  def self.triggerModifyMoveBaseType(ability, user, move, type)
    return trigger(ModifyMoveBaseType, ability, user, move, type, ret: type)
  end

  #=============================================================================

  def self.triggerAccuracyCalcFromUser(ability, mods, user, target, move, type)
    AccuracyCalcFromUser.trigger(ability, mods, user, target, move, type)
  end

  def self.triggerAccuracyCalcFromAlly(ability, mods, user, target, move, type)
    AccuracyCalcFromAlly.trigger(ability, mods, user, target, move, type)
  end

  def self.triggerAccuracyCalcFromTarget(ability, mods, user, target, move, type)
    AccuracyCalcFromTarget.trigger(ability, mods, user, target, move, type)
  end

  #=============================================================================

  def self.triggerDamageCalcFromUser(ability, user, target, move, mults, base_damage, type)
    DamageCalcFromUser.trigger(ability, user, target, move, mults, base_damage, type)
  end

  def self.triggerDamageCalcFromAlly(ability, user, target, move, mults, base_damage, type)
    DamageCalcFromAlly.trigger(ability, user, target, move, mults, base_damage, type)
  end

  def self.triggerDamageCalcFromTarget(ability, user, target, move, mults, base_damage, type)
    DamageCalcFromTarget.trigger(ability, user, target, move, mults, base_damage, type)
  end

  def self.triggerDamageCalcFromTargetNonIgnorable(ability, user, target, move, mults, base_damage, type)
    DamageCalcFromTargetNonIgnorable.trigger(ability, user, target, move, mults, base_damage, type)
  end

  def self.triggerDamageCalcFromTargetAlly(ability, user, target, move, mults, base_damage, type)
    DamageCalcFromTargetAlly.trigger(ability, user, target, move, mults, base_damage, type)
  end

  def self.triggerCriticalCalcFromUser(ability, user, target, crit_stage)
    return trigger(CriticalCalcFromUser, ability, user, target, crit_stage, ret: crit_stage)
  end

  def self.triggerCriticalCalcFromTarget(ability, user, target, crit_stage)
    return trigger(CriticalCalcFromTarget, ability, user, target, crit_stage, ret: crit_stage)
  end

  #=============================================================================

  def self.triggerOnBeingHit(ability, user, target, move, battle)
    OnBeingHit.trigger(ability, user, target, move, battle)
  end

  def self.triggerOnDealingHit(ability, user, target, move, battle)
    OnDealingHit.trigger(ability, user, target, move, battle)
  end

  #=============================================================================

  def self.triggerOnEndOfUsingMove(ability, user, targets, move, battle)
    OnEndOfUsingMove.trigger(ability, user, targets, move, battle)
  end

  def self.triggerAfterMoveUseFromTarget(ability, target, user, move, switched_battlers, battle)
    AfterMoveUseFromTarget.trigger(ability, target, user, move, switched_battlers, battle)
  end

  #=============================================================================

  def self.triggerEndOfRoundWeather(ability, weather, battler, battle)
    EndOfRoundWeather.trigger(ability, weather, battler, battle)
  end

  def self.triggerEndOfRoundHealing(ability, battler, battle)
    EndOfRoundHealing.trigger(ability, battler, battle)
  end

  def self.triggerEndOfRoundEffect(ability, battler, battle)
    EndOfRoundEffect.trigger(ability, battler, battle)
  end

  def self.triggerEndOfRoundGainItem(ability, battler, battle)
    EndOfRoundGainItem.trigger(ability, battler, battle)
  end

  #=============================================================================

  def self.triggerCertainSwitching(ability, switcher, battle)
    return trigger(CertainSwitching, ability, switcher, battle)
  end

  def self.triggerTrappingByTarget(ability, switcher, bearer, battle)
    return trigger(TrappingByTarget, ability, switcher, bearer, battle)
  end

  def self.triggerOnSwitchIn(ability, battler, battle, switch_in = false)
    OnSwitchIn.trigger(ability, battler, battle, switch_in)
  end

  def self.triggerOnSwitchOut(ability, battler, end_of_battle)
    OnSwitchOut.trigger(ability, battler, end_of_battle)
  end

  def self.triggerChangeOnBattlerFainting(ability, battler, fainted, battle)
    ChangeOnBattlerFainting.trigger(ability, battler, fainted, battle)
  end

  def self.triggerOnBattlerFainting(ability, battler, fainted, battle)
    OnBattlerFainting.trigger(ability, battler, fainted, battle)
  end

  def self.triggerOnTerrainChange(ability, battler, battle, ability_changed)
    OnTerrainChange.trigger(ability, battler, battle, ability_changed)
  end

  def self.triggerOnIntimidated(ability, battler, battle)
    OnIntimidated.trigger(ability, battler, battle)
  end

  #=============================================================================

  def self.triggerCertainEscapeFromBattle(ability, battler)
    return trigger(CertainEscapeFromBattle, ability, battler)
  end
end

#===============================================================================
# SpeedCalc handlers
#===============================================================================

PBAI::AbilityEffects::SpeedCalc.add(:CHLOROPHYLL,
  proc { |ability, battler, mult|
    next mult * 2 if [:Sun, :HarshSun].include?(battler.battle.pbWeather)
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:QUICKFEET,
  proc { |ability, battler, mult|
    next mult * 1.5 if battler.pbHasAnyStatus?
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:SANDRUSH,
  proc { |ability, battler, mult|
    next mult * 2 if [:Sandstorm].include?(battler.battle.pbWeather)
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:SLOWSTART,
  proc { |ability, battler, mult|
    next mult / 2 if battler.effects[PBEffects::SlowStart] > 0
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:SLUSHRUSH,
  proc { |ability, battler, mult|
    next mult * 2 if [:Hail].include?(battler.battle.pbWeather)
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:SURGESURFER,
  proc { |ability, battler, mult|
    next mult * 2 if battler.battle.field.terrain == :Electric
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:SWIFTSWIM,
  proc { |ability, battler, mult|
    next mult * 2 if [:Rain, :HeavyRain].include?(battler.battle.pbWeather)
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:UNBURDEN,
  proc { |ability, battler, mult|
    next mult * 2 if battler.effects[PBEffects::Unburden] && !battler.item
  }
)

#===============================================================================
# WeightCalcy handlers
#===============================================================================

PBAI::AbilityEffects::WeightCalc.add(:HEAVYMETAL,
  proc { |ability, battler, w|
    next w * 2
  }
)

PBAI::AbilityEffects::WeightCalc.add(:LIGHTMETAL,
  proc { |ability, battler, w|
    next [w / 2, 1].max
  }
)

#===============================================================================
# OnHPDroppedBelowHalf handlers
#===============================================================================

PBAI::AbilityEffects::OnHPDroppedBelowHalf.add(:EMERGENCYEXIT,
  proc { |ability, battler, move_user, battle|
    next false if battler.effects[PBEffects::SkyDrop] >= 0 ||
                  battler.inTwoTurnAttack?("TwoTurnAttackInvulnerableInSkyTargetCannotAct")   # Sky Drop
    # In wild battles
    if battle.wildBattle?
      next false if battler.opposes? && battle.pbSideBattlerCount(battler.index) > 1
      next false if !battle.pbCanRun?(battler.index)
      battle.pbShowAbilitySplash(battler, true)
      battle.pbHideAbilitySplash(battler)
      pbSEPlay("Battle flee")
      battle.pbDisplay(_INTL("{1} fled from battle!", battler.pbThis))
      battle.decision = 3   # Escaped
      next true
    end
    # In trainer battles
    next false if battle.pbAllFainted?(battler.idxOpposingSide)
    next false if !battle.pbCanSwitch?(battler.index)   # Battler can't switch out
    next false if !battle.pbCanChooseNonActive?(battler.index)   # No Pokémon can switch in
    battle.pbShowAbilitySplash(battler, true)
    battle.pbHideAbilitySplash(battler)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1}'s {2} activated!", battler.pbThis, battler.abilityName))
    end
    battle.pbDisplay(_INTL("{1} went back to {2}!",
       battler.pbThis, battle.pbGetOwnerName(battler.index)))
    if battle.endOfRound   # Just switch out
      battle.scene.pbRecall(battler.index) if !battler.fainted?
      battler.pbAbilitiesOnSwitchOut   # Inc. primordial weather check
      next true
    end
    newPkmn = battle.pbGetReplacementPokemonIndex(battler.index)   # Owner chooses
    next false if newPkmn < 0   # Shouldn't ever do this
    battle.pbRecallAndReplace(battler.index, newPkmn)
    battle.pbClearChoice(battler.index)   # Replacement Pokémon does nothing this round
    battle.moldBreaker = false if move_user && battler.index == move_user.index
    battle.pbOnBattlerEnteringBattle(battler.index)
    next true
  }
)

PBAI::AbilityEffects::OnHPDroppedBelowHalf.copy(:EMERGENCYEXIT, :WIMPOUT)

#===============================================================================
# StatusCheckNonIgnorable handlers
#===============================================================================

PBAI::AbilityEffects::StatusCheckNonIgnorable.add(:COMATOSE,
  proc { |ability, battler, status|
    next false if !battler.isSpecies?(:KOMALA)
    next true if status.nil? || status == :SLEEP
  }
)

PBAI::AbilityEffects::StatusCheckNonIgnorable.add(:OMNIPOTENT,
  proc { |ability, battler, status|
    next false if !battler.isSpecies?(:CELEBI)
    next true if status.nil? || status == :SLEEP
  }
)

#===============================================================================
# StatusImmunity handlers
#===============================================================================

PBAI::AbilityEffects::StatusImmunity.add(:FLOWERVEIL,
  proc { |ability, battler, status|
    next true if battler.pbHasType?(:GRASS)
  }
)

PBAI::AbilityEffects::StatusImmunity.add(:IMMUNITY,
  proc { |ability, battler, status|
    next true if status == :POISON
  }
)

PBAI::AbilityEffects::StatusImmunity.copy(:IMMUNITY, :PASTELVEIL)

PBAI::AbilityEffects::StatusImmunity.add(:INSOMNIA,
  proc { |ability, battler, status|
    next true if status == :SLEEP
  }
)

PBAI::AbilityEffects::StatusImmunity.copy(:INSOMNIA, :SWEETVEIL, :VITALSPIRIT)

PBAI::AbilityEffects::StatusImmunity.add(:LEAFGUARD,
  proc { |ability, battler, status|
    next true if [:Sun, :HarshSun].include?(battler.battle.pbWeather)
  }
)

PBAI::AbilityEffects::StatusImmunity.add(:LIMBER,
  proc { |ability, battler, status|
    next true if status == :PARALYSIS
  }
)

PBAI::AbilityEffects::StatusImmunity.add(:MAGMAARMOR,
  proc { |ability, battler, status|
    next true if status == :FROZEN
  }
)

PBAI::AbilityEffects::StatusImmunity.add(:WATERVEIL,
  proc { |ability, battler, status|
    next true if status == :BURN
  }
)

PBAI::AbilityEffects::StatusImmunity.copy(:WATERVEIL, :WATERBUBBLE)

#===============================================================================
# StatusImmunityNonIgnorable handlers
#===============================================================================

PBAI::AbilityEffects::StatusImmunityNonIgnorable.add(:COMATOSE,
  proc { |ability, battler, status|
    next true if battler.isSpecies?(:KOMALA)
  }
)

PBAI::AbilityEffects::StatusImmunityNonIgnorable.add(:OMNIPOTENT,
  proc { |ability, battler, status|
    next true if battler.isSpecies?(:CELEBI)
  }
)

PBAI::AbilityEffects::StatusImmunityNonIgnorable.add(:SHIELDSDOWN,
  proc { |ability, battler, status|
    next true if battler.isSpecies?(:MINIOR) && battler.form < 7
  }
)

#===============================================================================
# StatusImmunityFromAlly handlers
#===============================================================================

PBAI::AbilityEffects::StatusImmunityFromAlly.add(:FLOWERVEIL,
  proc { |ability, battler, status|
    next true if battler.pbHasType?(:GRASS)
  }
)

PBAI::AbilityEffects::StatusImmunityFromAlly.add(:SWEETVEIL,
  proc { |ability, battler, status|
    next true if status == :SLEEP
  }
)

#===============================================================================
# OnStatusInflicted handlers
#===============================================================================

PBAI::AbilityEffects::OnStatusInflicted.add(:SYNCHRONIZE,
  proc { |ability, battler, user, status|
    next if !user || user.index == battler.index
    case status
    when :POISON
      if user.pbCanPoisonSynchronize?(battler)
        battler.battle.pbShowAbilitySplash(battler)
        msg = nil
        if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          msg = _INTL("{1}'s {2} poisoned {3}!", battler.pbThis, battler.abilityName, user.pbThis(true))
        end
        user.pbPoison(nil, msg, (battler.statusCount > 0))
        battler.battle.pbHideAbilitySplash(battler)
      end
    when :BURN
      if user.pbCanBurnSynchronize?(battler)
        battler.battle.pbShowAbilitySplash(battler)
        msg = nil
        if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          msg = _INTL("{1}'s {2} burned {3}!", battler.pbThis, battler.abilityName, user.pbThis(true))
        end
        user.pbBurn(nil, msg)
        battler.battle.pbHideAbilitySplash(battler)
      end
    when :PARALYSIS
      if user.pbCanParalyzeSynchronize?(battler)
        battler.battle.pbShowAbilitySplash(battler)
        msg = nil
        if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          msg = _INTL("{1}'s {2} paralyzed {3}! It may be unable to move!",
             battler.pbThis, battler.abilityName, user.pbThis(true))
        end
        user.pbParalyze(nil, msg)
        battler.battle.pbHideAbilitySplash(battler)
      end
    end
  }
)

#===============================================================================
# StatusCure handlers
#===============================================================================

PBAI::AbilityEffects::StatusCure.add(:IMMUNITY,
  proc { |ability, battler|
    next if battler.status != :POISON
    battler.battle.pbShowAbilitySplash(battler)
    battler.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battler.battle.pbDisplay(_INTL("{1}'s {2} cured its poisoning!", battler.pbThis, battler.abilityName))
    end
    battler.battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::StatusCure.add(:INSOMNIA,
  proc { |ability, battler|
    next if battler.status != :SLEEP
    battler.battle.pbShowAbilitySplash(battler)
    battler.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battler.battle.pbDisplay(_INTL("{1}'s {2} woke it up!", battler.pbThis, battler.abilityName))
    end
    battler.battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::StatusCure.copy(:INSOMNIA, :VITALSPIRIT)

PBAI::AbilityEffects::StatusCure.add(:LIMBER,
  proc { |ability, battler|
    next if battler.status != :PARALYSIS
    battler.battle.pbShowAbilitySplash(battler)
    battler.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battler.battle.pbDisplay(_INTL("{1}'s {2} cured its paralysis!", battler.pbThis, battler.abilityName))
    end
    battler.battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::StatusCure.add(:MAGMAARMOR,
  proc { |ability, battler|
    next if battler.status != :FROZEN
    battler.battle.pbShowAbilitySplash(battler)
    battler.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battler.battle.pbDisplay(_INTL("{1}'s {2} defrosted it!", battler.pbThis, battler.abilityName))
    end
    battler.battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::StatusCure.add(:OBLIVIOUS,
  proc { |ability, battler|
    next if battler.effects[PBEffects::Attract] < 0 &&
            (battler.effects[PBEffects::Taunt] == 0 || Settings::MECHANICS_GENERATION <= 5)
    battler.battle.pbShowAbilitySplash(battler)
    if battler.effects[PBEffects::Attract] >= 0
      battler.pbCureAttract
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battler.battle.pbDisplay(_INTL("{1} got over its infatuation.", battler.pbThis))
      else
        battler.battle.pbDisplay(_INTL("{1}'s {2} cured its infatuation status!",
           battler.pbThis, battler.abilityName))
      end
    end
    if battler.effects[PBEffects::Taunt] > 0 && Settings::MECHANICS_GENERATION >= 6
      battler.effects[PBEffects::Taunt] = 0
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battler.battle.pbDisplay(_INTL("{1}'s Taunt wore off!", battler.pbThis))
      else
        battler.battle.pbDisplay(_INTL("{1}'s {2} made its taunt wear off!",
           battler.pbThis, battler.abilityName))
      end
    end
    battler.battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::StatusCure.add(:OWNTEMPO,
  proc { |ability, battler|
    next if battler.effects[PBEffects::Confusion] == 0
    battler.battle.pbShowAbilitySplash(battler)
    battler.pbCureConfusion
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battler.battle.pbDisplay(_INTL("{1} snapped out of its confusion.", battler.pbThis))
    else
      battler.battle.pbDisplay(_INTL("{1}'s {2} snapped it out of its confusion!",
         battler.pbThis, battler.abilityName))
    end
    battler.battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::StatusCure.add(:WATERVEIL,
  proc { |ability, battler|
    next if battler.status != :BURN
    battler.battle.pbShowAbilitySplash(battler)
    battler.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battler.battle.pbDisplay(_INTL("{1}'s {2} healed its burn!", battler.pbThis, battler.abilityName))
    end
    battler.battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::StatusCure.copy(:WATERVEIL, :WATERBUBBLE)

#===============================================================================
# StatLossImmunity handlers
#===============================================================================

PBAI::AbilityEffects::StatLossImmunity.add(:BIGPECKS,
  proc { |ability, battler, stat, battle, showMessages|
    next false if stat != :DEFENSE
    if showMessages
      battle.pbShowAbilitySplash(battler)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s {2} cannot be lowered!", battler.pbThis, GameData::Stat.get(stat).name))
      else
        battle.pbDisplay(_INTL("{1}'s {2} prevents {3} loss!", battler.pbThis,
           battler.abilityName, GameData::Stat.get(stat).name))
      end
      battle.pbHideAbilitySplash(battler)
    end
    next true
  }
)

PBAI::AbilityEffects::StatLossImmunity.add(:CLEARBODY,
  proc { |ability, battler, stat, battle, showMessages|
    if showMessages
      battle.pbShowAbilitySplash(battler)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s stats cannot be lowered!", battler.pbThis))
      else
        battle.pbDisplay(_INTL("{1}'s {2} prevents stat loss!", battler.pbThis, battler.abilityName))
      end
      battle.pbHideAbilitySplash(battler)
    end
    next true
  }
)

PBAI::AbilityEffects::StatLossImmunity.copy(:CLEARBODY, :WHITESMOKE, :OMNIPOTENT)

PBAI::AbilityEffects::StatLossImmunity.add(:FLOWERVEIL,
  proc { |ability, battler, stat, battle, showMessages|
    next false if !battler.pbHasType?(:GRASS)
    if showMessages
      battle.pbShowAbilitySplash(battler)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s stats cannot be lowered!", battler.pbThis))
      else
        battle.pbDisplay(_INTL("{1}'s {2} prevents stat loss!", battler.pbThis, battler.abilityName))
      end
      battle.pbHideAbilitySplash(battler)
    end
    next true
  }
)

PBAI::AbilityEffects::StatLossImmunity.add(:HYPERCUTTER,
  proc { |ability, battler, stat, battle, showMessages|
    next false if stat != :ATTACK
    if showMessages
      battle.pbShowAbilitySplash(battler)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s {2} cannot be lowered!", battler.pbThis, GameData::Stat.get(stat).name))
      else
        battle.pbDisplay(_INTL("{1}'s {2} prevents {3} loss!", battler.pbThis,
           battler.abilityName, GameData::Stat.get(stat).name))
      end
      battle.pbHideAbilitySplash(battler)
    end
    next true
  }
)

PBAI::AbilityEffects::StatLossImmunity.add(:KEENEYE,
  proc { |ability, battler, stat, battle, showMessages|
    next false if stat != :ACCURACY
    if showMessages
      battle.pbShowAbilitySplash(battler)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s {2} cannot be lowered!", battler.pbThis, GameData::Stat.get(stat).name))
      else
        battle.pbDisplay(_INTL("{1}'s {2} prevents {3} loss!", battler.pbThis,
           battler.abilityName, GameData::Stat.get(stat).name))
      end
      battle.pbHideAbilitySplash(battler)
    end
    next true
  }
)

#===============================================================================
# StatLossImmunityNonIgnorable handlers
#===============================================================================

PBAI::AbilityEffects::StatLossImmunityNonIgnorable.add(:FULLMETALBODY,
  proc { |ability, battler, stat, battle, showMessages|
    if showMessages
      battle.pbShowAbilitySplash(battler)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s stats cannot be lowered!", battler.pbThis))
      else
        battle.pbDisplay(_INTL("{1}'s {2} prevents stat loss!", battler.pbThis, battler.abilityName))
      end
      battle.pbHideAbilitySplash(battler)
    end
    next true
  }
)

#===============================================================================
# StatLossImmunityFromAlly handlers
#===============================================================================

PBAI::AbilityEffects::StatLossImmunityFromAlly.add(:FLOWERVEIL,
  proc { |ability, bearer, battler, stat, battle, showMessages|
    next false if !battler.pbHasType?(:GRASS)
    if showMessages
      battle.pbShowAbilitySplash(bearer)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s stats cannot be lowered!", battler.pbThis))
      else
        battle.pbDisplay(_INTL("{1}'s {2} prevents {3}'s stat loss!",
           bearer.pbThis, bearer.abilityName, battler.pbThis(true)))
      end
      battle.pbHideAbilitySplash(bearer)
    end
    next true
  }
)

#===============================================================================
# OnStatGain handlers
#===============================================================================

# There aren't any!

#===============================================================================
# OnStatLoss handlers
#===============================================================================

PBAI::AbilityEffects::OnStatLoss.add(:COMPETITIVE,
  proc { |ability, battler, stat, user|
    next if user && !user.opposes?(battler)
    battler.pbRaiseStatStageByAbility(:SPECIAL_ATTACK, 2, battler)
  }
)

PBAI::AbilityEffects::OnStatLoss.add(:DEFIANT,
  proc { |ability, battler, stat, user|
    next if user && !user.opposes?(battler)
    battler.pbRaiseStatStageByAbility(:ATTACK, 2, battler)
  }
)

#===============================================================================
# PriorityChange handlers
#===============================================================================

PBAI::AbilityEffects::PriorityChange.add(:GALEWINGS,
  proc { |ability, battler, move, pri|
    next pri + 1 if (Settings::MECHANICS_GENERATION <= 6 || battler.hp == battler.totalhp) &&
                    move.type == :FLYING
  }
)

PBAI::AbilityEffects::PriorityChange.add(:PRANKSTER,
  proc { |ability, battler, move, pri|
    if move.statusMove?
      battler.effects[PBEffects::Prankster] = true
      next pri + 1
    end
  }
)

PBAI::AbilityEffects::PriorityChange.add(:TRIAGE,
  proc { |ability, battler, move, pri|
    next pri + 3 if move.healingMove?
  }
)

#===============================================================================
# PriorityBracketChange handlers
#===============================================================================

PBAI::AbilityEffects::PriorityBracketChange.add(:QUICKDRAW,
  proc { |ability, battler, battle|
    next 1 if battle.pbRandom(100) < 30
  }
)

PBAI::AbilityEffects::PriorityBracketChange.add(:STALL,
  proc { |ability, battler, battle|
    next -1
  }
)

#===============================================================================
# PriorityBracketUse handlers
#===============================================================================

PBAI::AbilityEffects::PriorityBracketUse.add(:QUICKDRAW,
  proc { |ability, battler, battle|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} made {2} move faster!", battler.abilityName, battler.pbThis(true)))
    battle.pbHideAbilitySplash(battler)
  }
)

#===============================================================================
# OnFlinch handlers
#===============================================================================

PBAI::AbilityEffects::OnFlinch.add(:STEADFAST,
  proc { |ability, battler, battle|
    battler.pbRaiseStatStageByAbility(:SPEED, 1, battler)
  }
)

#===============================================================================
# MoveBlocking handlers
#===============================================================================

PBAI::AbilityEffects::MoveBlocking.add(:DAZZLING,
  proc { |ability, bearer, user, targets, move, battle|
    next false if battle.choices[user.index][4] <= 0
    next false if !bearer.opposes?(user)
    ret = false
    targets.each do |b|
      next if !b.opposes?(user)
      ret = true
    end
    next ret
  }
)

PBAI::AbilityEffects::MoveBlocking.copy(:DAZZLING, :QUEENLYMAJESTY)

#===============================================================================
# MoveImmunity handlers
#===============================================================================

PBAI::AbilityEffects::MoveImmunity.add(:BULLETPROOF,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !move.bombMove?
    if show_message
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!",
           target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:FLASHFIRE,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if user.index == target.index
    next false if type != :FIRE
    if show_message
      battle.pbShowAbilitySplash(target)
      if !target.effects[PBEffects::FlashFire]
        target.effects[PBEffects::FlashFire] = true
        if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          battle.pbDisplay(_INTL("The power of {1}'s Fire-type moves rose!", target.pbThis(true)))
        else
          battle.pbDisplay(_INTL("The power of {1}'s Fire-type moves rose because of its {2}!",
             target.pbThis(true), target.abilityName))
        end
      elsif PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!",
                               target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:LIGHTNINGROD,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type,
       :ELECTRIC, :SPECIAL_ATTACK, 1, show_message)
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:MOTORDRIVE,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type,
       :ELECTRIC, :SPEED, 1, show_message)
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:SAPSIPPER,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type,
       :GRASS, :ATTACK, 1, show_message)
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:SOUNDPROOF,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !move.soundMove?
    next false if Settings::MECHANICS_GENERATION >= 8 && user.index == target.index
    if show_message
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} blocks {3}!", target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:STORMDRAIN,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type,
       :WATER, :SPECIAL_ATTACK, 1, show_message)
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:TELEPATHY,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if move.statusMove?
    next false if user.index == target.index || target.opposes?(user)
    if show_message
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} avoids attacks by its ally Pokémon!", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1} avoids attacks by its ally Pokémon with {2}!",
           target.pbThis, target.abilityName))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:VOLTABSORB,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityHealingAbility(user, move, type, :ELECTRIC, show_message)
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:WATERABSORB,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityHealingAbility(user, move, type, :WATER, show_message)
  }
)

PBAI::AbilityEffects::MoveImmunity.copy(:WATERABSORB, :DRYSKIN)

PBAI::AbilityEffects::MoveImmunity.add(:WONDERGUARD,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if move.statusMove?
    next false if !type || Effectiveness.super_effective?(target.damageState.typeMod)
    if show_message
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1} avoided damage with {2}!", target.pbThis, target.abilityName))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

#===============================================================================
# ModifyMoveBaseType handlers
#===============================================================================

PBAI::AbilityEffects::ModifyMoveBaseType.add(:AERILATE,
  proc { |ability, user, move, type|
    next if type != :NORMAL || !GameData::Type.exists?(:FLYING)
    move.powerBoost = true
    next :FLYING
  }
)

PBAI::AbilityEffects::ModifyMoveBaseType.add(:GALVANIZE,
  proc { |ability, user, move, type|
    next if type != :NORMAL || !GameData::Type.exists?(:ELECTRIC)
    move.powerBoost = true
    next :ELECTRIC
  }
)

PBAI::AbilityEffects::ModifyMoveBaseType.add(:LIQUIDVOICE,
  proc { |ability, user, move, type|
    next :WATER if GameData::Type.exists?(:WATER) && move.soundMove?
  }
)

PBAI::AbilityEffects::ModifyMoveBaseType.add(:NORMALIZE,
  proc { |ability, user, move, type|
    next if !GameData::Type.exists?(:NORMAL)
    move.powerBoost = true if Settings::MECHANICS_GENERATION >= 7
    next :NORMAL
  }
)

PBAI::AbilityEffects::ModifyMoveBaseType.add(:PIXILATE,
  proc { |ability, user, move, type|
    next if type != :NORMAL || !GameData::Type.exists?(:FAIRY)
    move.powerBoost = true
    next :FAIRY
  }
)

PBAI::AbilityEffects::ModifyMoveBaseType.add(:REFRIGERATE,
  proc { |ability, user, move, type|
    next if type != :NORMAL || !GameData::Type.exists?(:ICE)
    move.powerBoost = true
    next :ICE
  }
)

#===============================================================================
# AccuracyCalcFromUser handlers
#===============================================================================

PBAI::AbilityEffects::AccuracyCalcFromUser.add(:COMPOUNDEYES,
  proc { |ability, mods, user, target, move, type|
    mods[:accuracy_multiplier] *= 1.3
  }
)

PBAI::AbilityEffects::AccuracyCalcFromUser.add(:HUSTLE,
  proc { |ability, mods, user, target, move, type|
    mods[:accuracy_multiplier] *= 0.8 if move.physicalMove?
  }
)

PBAI::AbilityEffects::AccuracyCalcFromUser.add(:KEENEYE,
  proc { |ability, mods, user, target, move, type|
    mods[:evasion_stage] = 0 if mods[:evasion_stage] > 0 && Settings::MECHANICS_GENERATION >= 6
  }
)

PBAI::AbilityEffects::AccuracyCalcFromUser.add(:NOGUARD,
  proc { |ability, mods, user, target, move, type|
    mods[:base_accuracy] = 0
  }
)

PBAI::AbilityEffects::AccuracyCalcFromUser.add(:UNAWARE,
  proc { |ability, mods, user, target, move, type|
    mods[:evasion_stage] = 0 if move.damagingMove?
  }
)

PBAI::AbilityEffects::AccuracyCalcFromUser.add(:VICTORYSTAR,
  proc { |ability, mods, user, target, move, type|
    mods[:accuracy_multiplier] *= 1.1
  }
)

#===============================================================================
# AccuracyCalcFromAlly handlers
#===============================================================================

PBAI::AbilityEffects::AccuracyCalcFromAlly.add(:VICTORYSTAR,
  proc { |ability, mods, user, target, move, type|
    mods[:accuracy_multiplier] *= 1.1
  }
)

#===============================================================================
# AccuracyCalcFromTarget handlers
#===============================================================================

PBAI::AbilityEffects::AccuracyCalcFromTarget.add(:LIGHTNINGROD,
  proc { |ability, mods, user, target, move, type|
    mods[:base_accuracy] = 0 if type == :ELECTRIC
  }
)

PBAI::AbilityEffects::AccuracyCalcFromTarget.add(:NOGUARD,
  proc { |ability, mods, user, target, move, type|
    mods[:base_accuracy] = 0
  }
)

PBAI::AbilityEffects::AccuracyCalcFromTarget.add(:SANDVEIL,
  proc { |ability, mods, user, target, move, type|
    mods[:evasion_multiplier] *= 1.25 if target.battle.pbWeather == :Sandstorm
  }
)

PBAI::AbilityEffects::AccuracyCalcFromTarget.add(:SNOWCLOAK,
  proc { |ability, mods, user, target, move, type|
    mods[:evasion_multiplier] *= 1.25 if target.battle.pbWeather == :Hail
  }
)

PBAI::AbilityEffects::AccuracyCalcFromTarget.add(:STORMDRAIN,
  proc { |ability, mods, user, target, move, type|
    mods[:base_accuracy] = 0 if type == :WATER
  }
)

PBAI::AbilityEffects::AccuracyCalcFromTarget.add(:TANGLEDFEET,
  proc { |ability, mods, user, target, move, type|
    mods[:accuracy_multiplier] /= 2 if target.effects[PBEffects::Confusion] > 0
  }
)

PBAI::AbilityEffects::AccuracyCalcFromTarget.add(:UNAWARE,
  proc { |ability, mods, user, target, move, type|
    mods[:accuracy_stage] = 0 if move.damagingMove?
  }
)

PBAI::AbilityEffects::AccuracyCalcFromTarget.add(:WONDERSKIN,
  proc { |ability, mods, user, target, move, type|
    if move.statusMove? && user.opposes?(target) && mods[:base_accuracy] > 50
      mods[:base_accuracy] = 50
    end
  }
)

#===============================================================================
# DamageCalcFromUser handlers
#===============================================================================

PBAI::AbilityEffects::DamageCalcFromUser.add(:AERILATE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if move.powerBoost
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.copy(:AERILATE, :PIXILATE, :REFRIGERATE, :GALVANIZE, :NORMALIZE)

PBAI::AbilityEffects::DamageCalcFromUser.add(:ANALYTIC,
  proc { |ability, user, target, move, mults, baseDmg, type|
    # NOTE: In the official games, if another battler faints earlier in the
    #       round but it would have moved after the user, then Analytic does not
    #       power up the move. However, this makes the determination so much
    #       more complicated (involving pbPriority and counting or not counting
    #       speed/priority modifiers depending on which Generation's mechanics
    #       are being used), so I'm choosing to ignore it. The effect is thus:
    #       "power up the move if all other battlers on the field right now have
    #       already moved".
    if target.pbSpeed > user.pbSpeed
      mults[:base_damage_multiplier] *= 1.3
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:BLAZE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.hp <= user.totalhp / 3 && type == :FIRE
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:DEFEATIST,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] /= 2 if user.hp <= user.totalhp / 2
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:DRAGONSMAW,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 1.5 if type == :DRAGON
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:FLAREBOOST,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.burned? && move.specialMove?
      mults[:base_damage_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:FLASHFIRE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.effects[PBEffects::FlashFire] && type == :FIRE
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:FLOWERGIFT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if move.specialMove? && [:Sun, :HarshSun].include?(user.battle.pbWeather)
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:GORILLATACTICS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 1.5 if move.physicalMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:GUTS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.pbHasAnyStatus? && move.physicalMove?
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:HUGEPOWER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 2 if move.physicalMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.copy(:HUGEPOWER, :PUREPOWER)

PBAI::AbilityEffects::DamageCalcFromUser.add(:HUSTLE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 1.5 if move.physicalMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:IRONFIST,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if move.punchingMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:MEGALAUNCHER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.5 if move.pulseMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:MINUS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    next if !move.specialMove?
    if user.allAllies.any? { |b| b.hasActiveAbility?([:MINUS, :PLUS]) }
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.copy(:MINUS, :PLUS)

PBAI::AbilityEffects::DamageCalcFromUser.add(:NEUROFORCE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if Effectiveness.super_effective?(target.damageState.typeMod)
      mults[:final_damage_multiplier] *= 1.25
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:OVERGROW,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.hp <= user.totalhp / 3 && type == :GRASS
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:PUNKROCK,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 1.3 if move.soundMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:RECKLESS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if move.recoilMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:RIVALRY,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.gender != 2 && target.gender != 2
      if user.gender == target.gender
        mults[:base_damage_multiplier] *= 1.25
      else
        mults[:base_damage_multiplier] *= 0.75
      end
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:SANDFORCE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.battle.pbWeather == :Sandstorm &&
       [:ROCK, :GROUND, :STEEL].include?(type)
      mults[:base_damage_multiplier] *= 1.3
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:SHEERFORCE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.3 if move.addlEffect > 0
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:SLOWSTART,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] /= 2 if user.effects[PBEffects::SlowStart] > 0 && move.physicalMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:SOLARPOWER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if move.specialMove? && [:Sun, :HarshSun].include?(user.battle.pbWeather)
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:SNIPER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if target.damageState.critical
      mults[:final_damage_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:STAKEOUT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    next if target.index == nil
    mults[:attack_multiplier] *= 2 if target.battle.choices[target.index][0] == :SwitchOut
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:STEELWORKER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 1.5 if type == :STEEL
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:STEELYSPIRIT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] *= 1.5 if type == :STEEL
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:STRONGJAW,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.5 if move.bitingMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:SWARM,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.hp <= user.totalhp / 3 && type == :BUG
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:TECHNICIAN,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.index != target.index && move && move.id != :STRUGGLE &&
       baseDmg * mults[:base_damage_multiplier] <= 60
      mults[:base_damage_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:TINTEDLENS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] *= 2 if Effectiveness.resistant?(target.damageState.typeMod)
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:TORRENT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.hp <= user.totalhp / 3 && type == :WATER
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:TOUGHCLAWS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 4 / 3.0 if move.contactMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:TOXICBOOST,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.poisoned? && move.physicalMove?
      mults[:base_damage_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:TRANSISTOR,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 1.5 if type == :ELECTRIC
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:WATERBUBBLE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 2 if type == :WATER
  }
)

#===============================================================================
# DamageCalcFromAlly handlers
#===============================================================================

PBAI::AbilityEffects::DamageCalcFromAlly.add(:BATTERY,
  proc { |ability, user, target, move, mults, baseDmg, type|
    next if !move.specialMove?
    mults[:final_damage_multiplier] *= 1.3
  }
)

PBAI::AbilityEffects::DamageCalcFromAlly.add(:FLOWERGIFT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if move.specialMove? && [:Sun, :HarshSun].include?(user.battle.pbWeather)
      mults[:attack_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromAlly.add(:POWERSPOT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] *= 1.3
  }
)

PBAI::AbilityEffects::DamageCalcFromAlly.add(:STEELYSPIRIT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] *= 1.5 if type == :STEEL
  }
)

#===============================================================================
# DamageCalcFromTarget handlers
#===============================================================================

PBAI::AbilityEffects::DamageCalcFromTarget.add(:DRYSKIN,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.25 if type == :FIRE
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:FILTER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if Effectiveness.super_effective?(target.damageState.typeMod)
      mults[:final_damage_multiplier] *= 0.75
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.copy(:FILTER, :SOLIDROCK, :OMNIPOTENT)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:FLOWERGIFT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if [:Sun, :HarshSun].include?(target.battle.pbWeather)
      mults[:defense_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:FLUFFY,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] *= 2 if move.calcType == :FIRE
    mults[:final_damage_multiplier] /= 2 if move.pbContactMove?(user)
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:FURCOAT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:defense_multiplier] *= 2 if move.physicalMove? ||
                                       move.function == "UseTargetDefenseInsteadOfTargetSpDef"   # Psyshock
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:GRASSPELT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if user.battle.field.terrain == :Grassy
      mults[:defense_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:HEATPROOF,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] /= 2 if type == :FIRE
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:ICESCALES,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] /= 2 if move.specialMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:MARVELSCALE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if target.pbHasAnyStatus? && move.physicalMove?
      mults[:defense_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:MULTISCALE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] /= 2 if target.hp == target.totalhp
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:PUNKROCK,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] /= 2 if move.soundMove?
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:THICKFAT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] /= 2 if [:FIRE, :ICE].include?(type)
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:WATERBUBBLE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] /= 2 if type == :FIRE
  }
)

#===============================================================================
# DamageCalcFromTargetNonIgnorable handlers
#===============================================================================

PBAI::AbilityEffects::DamageCalcFromTargetNonIgnorable.add(:PRISMARMOR,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if Effectiveness.super_effective?(target.damageState.typeMod)
      mults[:final_damage_multiplier] *= 0.75
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromTargetNonIgnorable.add(:SHADOWSHIELD,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if target.hp == target.totalhp
      mults[:final_damage_multiplier] /= 2
    end
  }
)

#===============================================================================
# DamageCalcFromTargetAlly handlers
#===============================================================================

PBAI::AbilityEffects::DamageCalcFromTargetAlly.add(:FLOWERGIFT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if [:Sun, :HarshSun].include?(target.battle.pbWeather)
      mults[:defense_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromTargetAlly.add(:FRIENDGUARD,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] *= 0.75
  }
)

#===============================================================================
# CriticalCalcFromUser handlers
#===============================================================================

PBAI::AbilityEffects::CriticalCalcFromUser.add(:MERCILESS,
  proc { |ability, user, target, c|
    next 99 if target.poisoned?
  }
)

PBAI::AbilityEffects::CriticalCalcFromUser.add(:SUPERLUCK,
  proc { |ability, user, target, c|
    next c + 1
  }
)

#===============================================================================
# CriticalCalcFromTarget handlers
#===============================================================================

PBAI::AbilityEffects::CriticalCalcFromTarget.add(:BATTLEARMOR,
  proc { |ability, user, target, c|
    next -1
  }
)

PBAI::AbilityEffects::CriticalCalcFromTarget.copy(:BATTLEARMOR, :SHELLARMOR)

#===============================================================================
# OnBeingHit handlers
#===============================================================================

PBAI::AbilityEffects::OnBeingHit.add(:AFTERMATH,
  proc { |ability, user, target, move, battle|
    next if !target.fainted?
    next if !move.pbContactMove?(user)
    battle.pbShowAbilitySplash(target)
    if !battle.moldBreaker
      dampBattler = battle.pbCheckGlobalAbility(:DAMP)
      if dampBattler
        battle.pbShowAbilitySplash(dampBattler)
        if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          battle.pbDisplay(_INTL("{1} cannot use {2}!", target.pbThis, target.abilityName))
        else
          battle.pbDisplay(_INTL("{1} cannot use {2} because of {3}'s {4}!",
             target.pbThis, target.abilityName, dampBattler.pbThis(true), dampBattler.abilityName))
        end
        battle.pbHideAbilitySplash(dampBattler)
        battle.pbHideAbilitySplash(target)
        next
      end
    end
    if user.takesIndirectDamage?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH) &&
       user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      battle.scene.pbDamageAnimation(user)
      user.pbReduceHP(user.totalhp / 4, false)
      battle.pbDisplay(_INTL("{1} was caught in the aftermath!", user.pbThis))
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:ANGERPOINT,
  proc { |ability, user, target, move, battle|
    next if !target.damageState.critical
    next if !target.pbCanRaiseStatStage?(:ATTACK, target)
    battle.pbShowAbilitySplash(target)
    target.stages[:ATTACK] = 6
    target.statsRaisedThisRound = true
    battle.pbCommonAnimation("StatUp", target)
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1} maxed its {2}!", target.pbThis, GameData::Stat.get(:ATTACK).name))
    else
      battle.pbDisplay(_INTL("{1}'s {2} maxed its {3}!",
         target.pbThis, target.abilityName, GameData::Stat.get(:ATTACK).name))
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:COTTONDOWN,
  proc { |ability, user, target, move, battle|
    next if battle.allBattlers.none? { |b| b.pbCanLowerStatStage?(:DEFENSE, target) }
    battle.pbShowAbilitySplash(target)
    battle.allBattlers.each do |b|
      b.pbLowerStatStageByAbility(:SPEED, 1, target, false)
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:CURSEDBODY,
  proc { |ability, user, target, move, battle|
    next if user.fainted?
    next if user.effects[PBEffects::Disable] > 0
    regularMove = nil
    user.eachMove do |m|
      next if m.id != user.lastRegularMoveUsed
      regularMove = m
      break
    end
    next if !regularMove || (regularMove.pp == 0 && regularMove.total_pp > 0)
    next if battle.pbRandom(100) >= 30
    battle.pbShowAbilitySplash(target)
    if !move.pbMoveFailedAromaVeil?(target, user, PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      user.effects[PBEffects::Disable]     = 3
      user.effects[PBEffects::DisableMove] = regularMove.id
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s {2} was disabled!", user.pbThis, regularMove.name))
      else
        battle.pbDisplay(_INTL("{1}'s {2} was disabled by {3}'s {4}!",
           user.pbThis, regularMove.name, target.pbThis(true), target.abilityName))
      end
      battle.pbHideAbilitySplash(target)
      user.pbItemStatusCureCheck
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:CUTECHARM,
  proc { |ability, user, target, move, battle|
    next if target.fainted?
    next if !move.pbContactMove?(user)
    next if battle.pbRandom(100) >= 30
    if user.pbCanAttract?(target, PokeBattle_SceneConstants::USE_ABILITY_SPLASH) &&
       user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
       battle.pbShowAbilitySplash(target)
      msg = nil
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        msg = _INTL("{1}'s {2} made {3} fall in love!", target.pbThis,
           target.abilityName, user.pbThis(true))
      end
      user.pbAttract(target, msg)
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:EFFECTSPORE,
  proc { |ability, user, target, move, battle|
    # NOTE: This ability has a 30% chance of triggering, not a 30% chance of
    #       inflicting a status condition. It can try (and fail) to inflict a
    #       status condition that the user is immune to.
    next if !move.pbContactMove?(user)
    next if battle.pbRandom(100) >= 30
    r = battle.pbRandom(3)
    next if r == 0 && user.asleep?
    next if r == 1 && user.poisoned?
    next if r == 2 && user.paralyzed?
    if user.affectedByPowder?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH) &&
       user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      case r
      when 0
        if user.pbCanSleep?(target, PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
          battle.pbShowAbilitySplash(target)
          msg = nil
          if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
            msg = _INTL("{1}'s {2} made {3} fall asleep!", target.pbThis,
               target.abilityName, user.pbThis(true))
          end
          user.pbSleep(msg)
        end
      when 1
        if user.pbCanPoison?(target, PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
          battle.pbShowAbilitySplash(target)
          msg = nil
          if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
            msg = _INTL("{1}'s {2} poisoned {3}!", target.pbThis,
               target.abilityName, user.pbThis(true))
          end
          user.pbPoison(target, msg)
        end
      when 2
        if user.pbCanParalyze?(target, PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
          battle.pbShowAbilitySplash(target)
          msg = nil
          if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
            msg = _INTL("{1}'s {2} paralyzed {3}! It may be unable to move!",
               target.pbThis, target.abilityName, user.pbThis(true))
          end
          user.pbParalyze(target, msg)
        end
      end
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:FLAMEBODY,
  proc { |ability, user, target, move, battle|
    next if !move.pbContactMove?(user)
    next if user.burned? || battle.pbRandom(100) >= 30
    if user.pbCanBurn?(target, PokeBattle_SceneConstants::USE_ABILITY_SPLASH) &&
       user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
       battle.pbShowAbilitySplash(target)
      msg = nil
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        msg = _INTL("{1}'s {2} burned {3}!", target.pbThis, target.abilityName, user.pbThis(true))
      end
      user.pbBurn(target, msg)
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:GOOEY,
  proc { |ability, user, target, move, battle|
    next if !move.pbContactMove?(user)
    user.pbLowerStatStageByAbility(:SPEED, 1, target, true, true)
  }
)

PBAI::AbilityEffects::OnBeingHit.copy(:GOOEY, :TANGLINGHAIR)

PBAI::AbilityEffects::OnBeingHit.add(:ILLUSION,
  proc { |ability, user, target, move, battle|
    # NOTE: This intentionally doesn't show the ability splash.
    next if !target.effects[PBEffects::Illusion]
    target.effects[PBEffects::Illusion] = nil
    battle.scene.pbChangePokemon(target, target.pokemon)
    battle.pbDisplay(_INTL("{1}'s illusion wore off!", target.pbThis))
    battle.pbSetSeen(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:INNARDSOUT,
  proc { |ability, user, target, move, battle|
    next if !target.fainted? || user.dummy
    battle.pbShowAbilitySplash(target)
    if user.takesIndirectDamage?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      battle.scene.pbDamageAnimation(user)
      user.pbReduceHP(target.damageState.hpLost, false)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} is hurt!", user.pbThis))
      else
        battle.pbDisplay(_INTL("{1} is hurt by {2}'s {3}!", user.pbThis,
           target.pbThis(true), target.abilityName))
      end
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:IRONBARBS,
  proc { |ability, user, target, move, battle|
    next if !move.pbContactMove?(user)
    battle.pbShowAbilitySplash(target)
    if user.takesIndirectDamage?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH) &&
       user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      battle.scene.pbDamageAnimation(user)
      user.pbReduceHP(user.totalhp / 8, false)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} is hurt!", user.pbThis))
      else
        battle.pbDisplay(_INTL("{1} is hurt by {2}'s {3}!", user.pbThis,
           target.pbThis(true), target.abilityName))
      end
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.copy(:IRONBARBS, :ROUGHSKIN)

PBAI::AbilityEffects::OnBeingHit.add(:JUSTIFIED,
  proc { |ability, user, target, move, battle|
    next if move.calcType != :DARK
    target.pbRaiseStatStageByAbility(:ATTACK, 1, target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:MUMMY,
  proc { |ability, user, target, move, battle|
    next if !move.pbContactMove?(user)
    next if user.fainted?
    next if user.unstoppableAbility? || user.ability == ability
    oldAbil = nil
    if user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      oldAbil = user.ability
      battle.pbShowAbilitySplash(user, true, false) if user.opposes?(target)
      user.ability = ability
      battle.pbReplaceAbilitySplash(user) if user.opposes?(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s Ability became {2}!", user.pbThis, user.abilityName))
      else
        battle.pbDisplay(_INTL("{1}'s Ability became {2} because of {3}!",
           user.pbThis, user.abilityName, target.pbThis(true)))
      end
      battle.pbHideAbilitySplash(user) if user.opposes?(target)
    end
    battle.pbHideAbilitySplash(target) if user.opposes?(target)
    user.pbOnLosingAbility(oldAbil)
    user.pbTriggerAbilityOnGainingIt
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:PERISHBODY,
  proc { |ability, user, target, move, battle|
    next if !move.pbContactMove?(user)
    next if user.fainted?
    next if user.effects[PBEffects::PerishSong] > 0 || target.effects[PBEffects::PerishSong] > 0
    battle.pbShowAbilitySplash(target)
    if user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      user.effects[PBEffects::PerishSong] = 4
      user.effects[PBEffects::PerishSongUser] = target.index
      target.effects[PBEffects::PerishSong] = 4
      target.effects[PBEffects::PerishSongUser] = target.index
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("Both Pokémon will faint in three turns!"))
      else
        battle.pbDisplay(_INTL("Both Pokémon will faint in three turns because of {1}'s {2}!",
           target.pbThis(true), target.abilityName))
      end
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:POISONPOINT,
  proc { |ability, user, target, move, battle|
    next if !move.pbContactMove?(user)
    next if user.poisoned? || battle.pbRandom(100) >= 30
    if user.pbCanPoison?(target, PokeBattle_SceneConstants::USE_ABILITY_SPLASH) &&
       user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
       battle.pbShowAbilitySplash(target)
      msg = nil
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        msg = _INTL("{1}'s {2} poisoned {3}!", target.pbThis, target.abilityName, user.pbThis(true))
      end
      user.pbPoison(target, msg)
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:RATTLED,
  proc { |ability, user, target, move, battle|
    next if ![:BUG, :DARK, :GHOST].include?(move.calcType)
    target.pbRaiseStatStageByAbility(:SPEED, 1, target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:SANDSPIT,
  proc { |ability, user, target, move, battle|
    battle.pbStartWeatherAbility(:Sandstorm, target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:STAMINA,
  proc { |ability, user, target, move, battle|
    target.pbRaiseStatStageByAbility(:DEFENSE, 1, target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:STATIC,
  proc { |ability, user, target, move, battle|
    next if !move.pbContactMove?(user)
    next if user.paralyzed? || battle.pbRandom(100) >= 30
    if user.pbCanParalyze?(target, PokeBattle_SceneConstants::USE_ABILITY_SPLASH) &&
       user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
       battle.pbShowAbilitySplash(target)
      msg = nil
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        msg = _INTL("{1}'s {2} paralyzed {3}! It may be unable to move!",
           target.pbThis, target.abilityName, user.pbThis(true))
      end
      user.pbParalyze(target, msg)
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:WANDERINGSPIRIT,
  proc { |ability, user, target, move, battle|
    next if !move.pbContactMove?(user)
    next if user.ungainableAbility? || [:RECEIVER, :WONDERGUARD].include?(user.ability_id)
    oldUserAbil   = nil
    oldTargetAbil = nil
    #battle.pbShowAbilitySplash(target) if user.opposes?(target)
    if user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      battle.pbShowAbilitySplash(user, true, false) if user.opposes?(target)
      oldUserAbil   = user.ability
      oldTargetAbil = target.ability
      user.ability   = oldTargetAbil
      target.ability = oldUserAbil
      if user.opposes?(target)
        battle.pbReplaceAbilitySplash(user)
        battle.pbReplaceAbilitySplash(target)
      end
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} swapped Abilities with {2}!", target.pbThis, user.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1} swapped its {2} Ability with {3}'s {4} Ability!",
           target.pbThis, user.abilityName, user.pbThis(true), target.abilityName))
      end
      if user.opposes?(target)
        battle.pbHideAbilitySplash(user)
        battle.pbHideAbilitySplash(target)
      end
    end
    battle.pbHideAbilitySplash(target) if user.opposes?(target)
    user.pbOnLosingAbility(oldUserAbil)
    target.pbOnLosingAbility(oldTargetAbil)
    user.pbTriggerAbilityOnGainingIt
    target.pbTriggerAbilityOnGainingIt
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:WATERCOMPACTION,
  proc { |ability, user, target, move, battle|
    next if move.calcType != :WATER
    target.pbRaiseStatStageByAbility(:DEFENSE, 2, target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:WEAKARMOR,
  proc { |ability, user, target, move, battle|
    next if !move.physicalMove?
    next if !target.pbCanLowerStatStage?(:DEFENSE, target) &&
            !target.pbCanRaiseStatStage?(:SPEED, target)
    battle.pbShowAbilitySplash(target)
    target.pbLowerStatStageByAbility(:DEFENSE, 1, target, false)
    target.pbRaiseStatStageByAbility(:SPEED,
       (Settings::MECHANICS_GENERATION >= 7) ? 2 : 1, target, false)
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# OnDealingHit handlers
#===============================================================================

PBAI::AbilityEffects::OnDealingHit.add(:POISONTOUCH,
  proc { |ability, user, target, move, battle|
    next if !move.contactMove?
    next if battle.pbRandom(100) >= 30
    next if target.fainted?
    battle.pbShowAbilitySplash(user)
    if target.hasActiveAbility?(:SHIELDDUST) && !battle.moldBreaker
      battle.pbShowAbilitySplash(target)
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} is unaffected!", target.pbThis))
      end
      battle.pbHideAbilitySplash(target)
    elsif target.pbCanPoison?(user, PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      msg = nil
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        msg = _INTL("{1}'s {2} poisoned {3}!", user.pbThis, user.abilityName, target.pbThis(true))
      end
      target.pbPoison(user, msg)
    end
    battle.pbHideAbilitySplash(user)
  }
)

#===============================================================================
# OnEndOfUsingMove handlers
#===============================================================================

PBAI::AbilityEffects::OnEndOfUsingMove.add(:BEASTBOOST,
  proc { |ability, user, targets, move, battle|
    next if battle.pbAllFainted?(user.idxOpposingSide)
    numFainted = 0
    targets.each { |b| numFainted += 1 if b.damageState.fainted }
    next if numFainted == 0
    userStats = user.plainStats
    highestStatValue = 0
    userStats.each_value { |value| highestStatValue = value if highestStatValue < value }
    GameData::Stat.each_main_battle do |s|
      next if userStats[s.id] < highestStatValue
      if user.pbCanRaiseStatStage?(s.id, user)
        user.pbRaiseStatStageByAbility(s.id, numFainted, user)
      end
      break
    end
  }
)

PBAI::AbilityEffects::OnEndOfUsingMove.add(:CHILLINGNEIGH,
  proc { |ability, user, targets, move, battle|
    next if battle.pbAllFainted?(user.idxOpposingSide)
    numFainted = 0
    targets.each { |b| numFainted += 1 if b.damageState.fainted }
    next if numFainted == 0 || !user.pbCanRaiseStatStage?(:ATTACK, user)
    user.ability_id = :CHILLINGNEIGH   # So the As One abilities can just copy this
    user.pbRaiseStatStageByAbility(:ATTACK, 1, user)
    user.ability_id = ability
  }
)

PBAI::AbilityEffects::OnEndOfUsingMove.copy(:CHILLINGNEIGH, :ASONECHILLINGNEIGH)

PBAI::AbilityEffects::OnEndOfUsingMove.add(:GRIMNEIGH,
  proc { |ability, user, targets, move, battle|
    next if battle.pbAllFainted?(user.idxOpposingSide)
    numFainted = 0
    targets.each { |b| numFainted += 1 if b.damageState.fainted }
    next if numFainted == 0 || !user.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user)
    user.ability_id = :GRIMNEIGH   # So the As One abilities can just copy this
    user.pbRaiseStatStageByAbility(:SPECIAL_ATTACK, 1, user)
    user.ability_id = ability
  }
)

PBAI::AbilityEffects::OnEndOfUsingMove.copy(:GRIMNEIGH, :ASONEGRIMNEIGH)

PBAI::AbilityEffects::OnEndOfUsingMove.add(:MAGICIAN,
  proc { |ability, user, targets, move, battle|
    next if battle.futureSight
    next if !move.pbDamagingMove?
    next if user.item
    next if user.wild?
    targets.each do |b|
      next if b.damageState.unaffected || b.damageState.substitute
      next if !b.item
      next if b.unlosableItem?(b.item) || user.unlosableItem?(b.item)
      battle.pbShowAbilitySplash(user)
      if b.hasActiveAbility?(:STICKYHOLD)
        battle.pbShowAbilitySplash(b) if user.opposes?(b)
        if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          battle.pbDisplay(_INTL("{1}'s item cannot be stolen!", b.pbThis))
        end
        battle.pbHideAbilitySplash(b) if user.opposes?(b)
        next
      end
      user.item = b.item
      b.item = nil
      b.effects[PBEffects::Unburden] = true if b.hasActiveAbility?(:UNBURDEN)
      if battle.wildBattle? && !user.initialItem && user.item == b.initialItem
        user.setInitialItem(user.item)
        b.setInitialItem(nil)
      end
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} stole {2}'s {3}!", user.pbThis,
           b.pbThis(true), user.itemName))
      else
        battle.pbDisplay(_INTL("{1} stole {2}'s {3} with {4}!", user.pbThis,
           b.pbThis(true), user.itemName, user.abilityName))
      end
      battle.pbHideAbilitySplash(user)
      user.pbHeldItemTriggerCheck
      break
    end
  }
)

PBAI::AbilityEffects::OnEndOfUsingMove.add(:MOXIE,
  proc { |ability, user, targets, move, battle|
    next if battle.pbAllFainted?(user.idxOpposingSide)
    numFainted = 0
    targets.each { |b| numFainted += 1 if b.damageState.fainted }
    next if numFainted == 0 || !user.pbCanRaiseStatStage?(:ATTACK, user)
    user.pbRaiseStatStageByAbility(:ATTACK, numFainted, user)
  }
)

#===============================================================================
# AfterMoveUseFromTarget handlers
#===============================================================================

PBAI::AbilityEffects::AfterMoveUseFromTarget.add(:BERSERK,
  proc { |ability, target, user, move, switched_battlers, battle|
    next if !move.damagingMove?
    next if !target.droppedBelowHalfHP
    next if !target.pbCanRaiseStatStage?(:SPECIAL_ATTACK, target)
    target.pbRaiseStatStageByAbility(:SPECIAL_ATTACK, 1, target)
  }
)

PBAI::AbilityEffects::AfterMoveUseFromTarget.add(:COLORCHANGE,
  proc { |ability, target, user, move, switched_battlers, battle|
    next if target.damageState.calcDamage == 0 || target.damageState.substitute
    next if !move.calcType || GameData::Type.get(move.calcType).pseudo_type
    next if target.pbHasType?(move.calcType) && !target.pbHasOtherType?(move.calcType)
    typeName = GameData::Type.get(move.calcType).name
    battle.pbShowAbilitySplash(target)
    target.pbChangeTypes(move.calcType)
    battle.pbDisplay(_INTL("{1}'s type changed to {2} because of its {3}!",
       target.pbThis, typeName, target.abilityName))
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::AfterMoveUseFromTarget.add(:PICKPOCKET,
  proc { |ability, target, user, move, switched_battlers, battle|
    # NOTE: According to Bulbapedia, this can still trigger to steal the user's
    #       item even if it was switched out by a Red Card. That doesn't make
    #       sense, so this code doesn't do it.
    next if target.wild?
    next if switched_battlers.include?(user.index)   # User was switched out
    next if !move.contactMove?
    next if user.effects[PBEffects::Substitute] > 0 || target.damageState.substitute
    next if target.item || !user.item
    next if user.unlosableItem?(user.item) || target.unlosableItem?(user.item)
    battle.pbShowAbilitySplash(target)
    if user.hasActiveAbility?(:STICKYHOLD)
      battle.pbShowAbilitySplash(user) if target.opposes?(user)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s item cannot be stolen!", user.pbThis))
      end
      battle.pbHideAbilitySplash(user) if target.opposes?(user)
      battle.pbHideAbilitySplash(target)
      next
    end
    target.item = user.item
    user.item = nil
    user.effects[PBEffects::Unburden] = true if user.hasActiveAbility?(:UNBURDEN)
    if battle.wildBattle? && !target.initialItem && target.item == user.initialItem
      target.setInitialItem(target.item)
      user.setInitialItem(nil)
    end
    battle.pbDisplay(_INTL("{1} pickpocketed {2}'s {3}!", target.pbThis,
       user.pbThis(true), target.itemName))
    battle.pbHideAbilitySplash(target)
    target.pbHeldItemTriggerCheck
  }
)

#===============================================================================
# EndOfRoundWeather handlers
#===============================================================================

PBAI::AbilityEffects::EndOfRoundWeather.add(:DRYSKIN,
  proc { |ability, weather, battler, battle|
    case weather
    when :Sun, :HarshSun
      battle.pbShowAbilitySplash(battler)
      battle.scene.pbDamageAnimation(battler)
      battler.pbReduceHP(battler.totalhp / 8, false)
      battle.pbDisplay(_INTL("{1} was hurt by the sunlight!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
      battler.pbItemHPHealCheck
    when :Rain, :HeavyRain
      next if !battler.canHeal?
      battle.pbShowAbilitySplash(battler)
      battler.pbRecoverHP(battler.totalhp / 8)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s HP was restored.", battler.pbThis))
      else
        battle.pbDisplay(_INTL("{1}'s {2} restored its HP.", battler.pbThis, battler.abilityName))
      end
      battle.pbHideAbilitySplash(battler)
    end
  }
)

PBAI::AbilityEffects::EndOfRoundWeather.add(:ICEBODY,
  proc { |ability, weather, battler, battle|
    next unless weather == :Hail
    next if !battler.canHeal?
    battle.pbShowAbilitySplash(battler)
    battler.pbRecoverHP(battler.totalhp / 16)
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1}'s HP was restored.", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1}'s {2} restored its HP.", battler.pbThis, battler.abilityName))
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::EndOfRoundWeather.add(:iceface,
  proc { |ability, weather, battler, battle|
    next if weather != :Hail
    next if !battler.canRestoreiceface || battler.form != 1
    battle.pbShowAbilitySplash(battler)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1}'s {2} activated!", battler.pbThis, battler.abilityName))
    end
    battler.pbChangeForm(0, _INTL("{1} transformed!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::EndOfRoundWeather.add(:RAINDISH,
  proc { |ability, weather, battler, battle|
    next unless [:Rain, :HeavyRain].include?(weather)
    next if !battler.canHeal?
    battle.pbShowAbilitySplash(battler)
    battler.pbRecoverHP(battler.totalhp / 16)
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1}'s HP was restored.", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1}'s {2} restored its HP.", battler.pbThis, battler.abilityName))
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::EndOfRoundWeather.add(:SOLARPOWER,
  proc { |ability, weather, battler, battle|
    next unless [:Sun, :HarshSun].include?(weather)
    battle.pbShowAbilitySplash(battler)
    battle.scene.pbDamageAnimation(battler)
    battler.pbReduceHP(battler.totalhp / 8, false)
    battle.pbDisplay(_INTL("{1} was hurt by the sunlight!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
    battler.pbItemHPHealCheck
  }
)

#===============================================================================
# EndOfRoundHealing handlers
#===============================================================================

PBAI::AbilityEffects::EndOfRoundHealing.add(:HEALER,
  proc { |ability, battler, battle|
    next unless battle.pbRandom(100) < 30
    battler.allAllies.each do |b|
      next if b.status == :NONE
      battle.pbShowAbilitySplash(battler)
      oldStatus = b.status
      b.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        case oldStatus
        when :SLEEP
          battle.pbDisplay(_INTL("{1}'s {2} woke its partner up!", battler.pbThis, battler.abilityName))
        when :POISON
          battle.pbDisplay(_INTL("{1}'s {2} cured its partner's poison!", battler.pbThis, battler.abilityName))
        when :BURN
          battle.pbDisplay(_INTL("{1}'s {2} healed its partner's burn!", battler.pbThis, battler.abilityName))
        when :PARALYSIS
          battle.pbDisplay(_INTL("{1}'s {2} cured its partner's paralysis!", battler.pbThis, battler.abilityName))
        when :FROZEN
          battle.pbDisplay(_INTL("{1}'s {2} defrosted its partner!", battler.pbThis, battler.abilityName))
        end
      end
      battle.pbHideAbilitySplash(battler)
    end
  }
)

PBAI::AbilityEffects::EndOfRoundHealing.add(:HYDRATION,
  proc { |ability, battler, battle|
    next if battler.status == :NONE
    next if ![:Rain, :HeavyRain].include?(battler.battle.pbWeather)
    battle.pbShowAbilitySplash(battler)
    oldStatus = battler.status
    battler.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      case oldStatus
      when :SLEEP
        battle.pbDisplay(_INTL("{1}'s {2} woke it up!", battler.pbThis, battler.abilityName))
      when :POISON
        battle.pbDisplay(_INTL("{1}'s {2} cured its poison!", battler.pbThis, battler.abilityName))
      when :BURN
        battle.pbDisplay(_INTL("{1}'s {2} healed its burn!", battler.pbThis, battler.abilityName))
      when :PARALYSIS
        battle.pbDisplay(_INTL("{1}'s {2} cured its paralysis!", battler.pbThis, battler.abilityName))
      when :FROZEN
        battle.pbDisplay(_INTL("{1}'s {2} defrosted it!", battler.pbThis, battler.abilityName))
      end
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::EndOfRoundHealing.add(:SHEDSKIN,
  proc { |ability, battler, battle|
    next if battler.status == :NONE
    next unless battle.pbRandom(100) < 30
    battle.pbShowAbilitySplash(battler)
    oldStatus = battler.status
    battler.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      case oldStatus
      when :SLEEP
        battle.pbDisplay(_INTL("{1}'s {2} woke it up!", battler.pbThis, battler.abilityName))
      when :POISON
        battle.pbDisplay(_INTL("{1}'s {2} cured its poison!", battler.pbThis, battler.abilityName))
      when :BURN
        battle.pbDisplay(_INTL("{1}'s {2} healed its burn!", battler.pbThis, battler.abilityName))
      when :PARALYSIS
        battle.pbDisplay(_INTL("{1}'s {2} cured its paralysis!", battler.pbThis, battler.abilityName))
      when :FROZEN
        battle.pbDisplay(_INTL("{1}'s {2} defrosted it!", battler.pbThis, battler.abilityName))
      end
    end
    battle.pbHideAbilitySplash(battler)
  }
)

#===============================================================================
# EndOfRoundEffect handlers
#===============================================================================

PBAI::AbilityEffects::EndOfRoundEffect.add(:BADDREAMS,
  proc { |ability, battler, battle|
    battle.allOtherSideBattlers(battler.index).each do |b|
      next if !b.near?(battler) || !b.asleep?
      battle.pbShowAbilitySplash(battler)
      next if !b.takesIndirectDamage?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      b.pbTakeEffectDamage(b.totalhp / 8) { |hp_lost|
        if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          battle.pbDisplay(_INTL("{1} is tormented!", b.pbThis))
        else
          battle.pbDisplay(_INTL("{1} is tormented by {2}'s {3}!",
             b.pbThis, battler.pbThis(true), battler.abilityName))
        end
        battle.pbHideAbilitySplash(battler)
      }
    end
  }
)

PBAI::AbilityEffects::EndOfRoundEffect.add(:MOODY,
  proc { |ability, battler, battle|
    randomUp = []
    randomDown = []
    if Settings::MECHANICS_GENERATION >= 8
      GameData::Stat.each_main_battle do |s|
        randomUp.push(s.id) if battler.pbCanRaiseStatStage?(s.id, battler)
        randomDown.push(s.id) if battler.pbCanLowerStatStage?(s.id, battler)
      end
    else
      GameData::Stat.each_battle do |s|
        randomUp.push(s.id) if battler.pbCanRaiseStatStage?(s.id, battler)
        randomDown.push(s.id) if battler.pbCanLowerStatStage?(s.id, battler)
      end
    end
    next if randomUp.length == 0 && randomDown.length == 0
    battle.pbShowAbilitySplash(battler)
    if randomUp.length > 0
      r = battle.pbRandom(randomUp.length)
      battler.pbRaiseStatStageByAbility(randomUp[r], 2, battler, false)
      randomDown.delete(randomUp[r])
    end
    if randomDown.length > 0
      r = battle.pbRandom(randomDown.length)
      battler.pbLowerStatStageByAbility(randomDown[r], 1, battler, false)
    end
    battle.pbHideAbilitySplash(battler)
    battler.pbItemStatRestoreCheck if randomDown.length > 0
    battler.pbItemOnStatDropped
  }
)

PBAI::AbilityEffects::EndOfRoundEffect.add(:SPEEDBOOST,
  proc { |ability, battler, battle|
    # A Pokémon's turnCount is 0 if it became active after the beginning of a
    # round
    if battler.turnCount > 0 && battle.choices[battler.index][0] != :Run &&
       battler.pbCanRaiseStatStage?(:SPEED, battler)
      battler.pbRaiseStatStageByAbility(:SPEED, 1, battler)
    end
  }
)

#===============================================================================
# EndOfRoundGainItem handlers
#===============================================================================

PBAI::AbilityEffects::EndOfRoundGainItem.add(:BALLFETCH,
  proc { |ability, battler, battle|
    next if battler.item
    next if battle.first_poke_ball.nil?
    battle.pbShowAbilitySplash(battler)
    battler.item = battle.first_poke_ball
    battler.setInitialItem(battler.item) if !battler.initialItem
    battle.first_poke_ball = nil
    battle.pbDisplay(_INTL("{1} retrieved the thrown {2}!", battler.pbThis, battler.itemName))
    battle.pbHideAbilitySplash(battler)
    battler.pbHeldItemTriggerCheck
  }
)

PBAI::AbilityEffects::EndOfRoundGainItem.add(:HARVEST,
  proc { |ability, battler, battle|
    next if battler.item
    next if !battler.recycleItem || !GameData::Item.get(battler.recycleItem).is_berry?
    if ![:Sun, :HarshSun].include?(battler.battle.pbWeather)
      next unless battle.pbRandom(100) < 50
    end
    battle.pbShowAbilitySplash(battler)
    battler.item = battler.recycleItem
    battler.setRecycleItem(nil)
    battler.setInitialItem(battler.item) if !battler.initialItem
    battle.pbDisplay(_INTL("{1} harvested one {2}!", battler.pbThis, battler.itemName))
    battle.pbHideAbilitySplash(battler)
    battler.pbHeldItemTriggerCheck
  }
)

PBAI::AbilityEffects::EndOfRoundGainItem.add(:PICKUP,
  proc { |ability, battler, battle|
    next if battler.item
    foundItem = nil
    fromBattler = nil
    use = 0
    battle.allBattlers.each do |b|
      next if b.index == battler.index
      next if b.effects[PBEffects::PickupUse] <= use
      foundItem   = b.effects[PBEffects::PickupItem]
      fromBattler = b
      use         = b.effects[PBEffects::PickupUse]
    end
    next if !foundItem
    battle.pbShowAbilitySplash(battler)
    battler.item = foundItem
    fromBattler.effects[PBEffects::PickupItem] = nil
    fromBattler.effects[PBEffects::PickupUse]  = 0
    fromBattler.setRecycleItem(nil) if fromBattler.recycleItem == foundItem
    if battle.wildBattle? && !battler.initialItem && fromBattler.initialItem == foundItem
      battler.setInitialItem(foundItem)
      fromBattler.setInitialItem(nil)
    end
    battle.pbDisplay(_INTL("{1} found one {2}!", battler.pbThis, battler.itemName))
    battle.pbHideAbilitySplash(battler)
    battler.pbHeldItemTriggerCheck
  }
)

#===============================================================================
# CertainSwitching handlers
#===============================================================================

# There aren't any!

#===============================================================================
# TrappingByTarget handlers
#===============================================================================

PBAI::AbilityEffects::TrappingByTarget.add(:ARENATRAP,
  proc { |ability, switcher, bearer, battle|
    next true if !switcher.airborne?
  }
)

PBAI::AbilityEffects::TrappingByTarget.add(:MAGNETPULL,
  proc { |ability, switcher, bearer, battle|
    next true if switcher.pbHasType?(:STEEL)
  }
)

PBAI::AbilityEffects::TrappingByTarget.add(:SHADOWTAG,
  proc { |ability, switcher, bearer, battle|
    next true if !switcher.hasActiveAbility?(:SHADOWTAG)
  }
)

#===============================================================================
# OnSwitchIn handlers
#===============================================================================

PBAI::AbilityEffects::OnSwitchIn.add(:AIRLOCK,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1} has {2}!", battler.pbThis, battler.abilityName))
    end
    battle.pbDisplay(_INTL("The effects of the weather disappeared."))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.copy(:AIRLOCK, :CLOUDNINE)

PBAI::AbilityEffects::OnSwitchIn.add(:ANTICIPATION,
  proc { |ability, battler, battle, switch_in|
    next if !battler.pbOwnedByPlayer?
    battlerTypes = battler.pbTypes(true)
    types = battlerTypes
    found = false
    battle.allOtherSideBattlers(battler.index).each do |b|
      b.eachMove do |m|
        next if m.statusMove?
        if types.length > 0
          moveType = m.type
          if Settings::MECHANICS_GENERATION >= 6 && m.function == "TypeDependsOnUserIVs"   # Hidden Power
            moveType = pbHiddenPower(b.pokemon)[0]
          end
          eff = Effectiveness.calculate(moveType, types[0], types[1], types[2])
          next if Effectiveness.ineffective?(eff)
          next if !Effectiveness.super_effective?(eff) &&
                  !["OHKO", "OHKOIce", "OHKOHitsUndergroundTarget"].include?(m.function)
        elsif !["OHKO", "OHKOIce", "OHKOHitsUndergroundTarget"].include?(m.function)
          next
        end
        found = true
        break
      end
      break if found
    end
    if found
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1} shuddered with anticipation!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    end
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:ASONECHILLINGNEIGH,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} has two Abilities!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
    battler.ability_id = :UNNERVE
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is too nervous to eat Berries!", battler.pbOpposingTeam))
    battle.pbHideAbilitySplash(battler)
    battler.ability_id = ability
  }
)

PBAI::AbilityEffects::OnSwitchIn.copy(:ASONECHILLINGNEIGH, :ASONEGRIMNEIGH)

PBAI::AbilityEffects::OnSwitchIn.add(:AURABREAK,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} reversed all other Pokémon's auras!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:COMATOSE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is drowsing!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:CURIOUSMEDICINE,
  proc { |ability, battler, battle, switch_in|
    next if battler.allAllies.none? { |b| b.hasAlteredStatStages? }
    battle.pbShowAbilitySplash(battler)
    battler.allAllies.each do |b|
      next if !b.hasAlteredStatStages?
      b.pbResetStatStages
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s stat changes were removed!", b.pbThis))
      else
        battle.pbDisplay(_INTL("{1}'s stat changes were removed by {2}'s {3}!",
           b.pbThis, battler.pbThis(true), battler.abilityName))
      end
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DARKAURA,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is radiating a dark aura!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DAUNTLESSSHIELD,
  proc { |ability, battler, battle, switch_in|
    battler.pbRaiseStatStageByAbility(:DEFENSE, 1, battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DELTASTREAM,
  proc { |ability, battler, battle, switch_in|
    battle.pbStartWeatherAbility(:StrongWinds, battler, true)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DESOLATELAND,
  proc { |ability, battler, battle, switch_in|
    battle.pbStartWeatherAbility(:HarshSun, battler, true)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DOWNLOAD,
  proc { |ability, battler, battle, switch_in|
    oDef = oSpDef = 0
    battle.allOtherSideBattlers(battler.index).each do |b|
      oDef   += b.defense
      oSpDef += b.spdef
    end
    stat = (oDef < oSpDef) ? :ATTACK : :SPECIAL_ATTACK
    battler.pbRaiseStatStageByAbility(stat, 1, battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DRIZZLE,
  proc { |ability, battler, battle, switch_in|
    battle.pbStartWeatherAbility(:Rain, battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DROUGHT,
  proc { |ability, battler, battle, switch_in|
    battle.pbStartWeatherAbility(:Sun, battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:ELECTRICSURGE,
  proc { |ability, battler, battle, switch_in|
    next if battle.field.terrain == :Electric
    battle.pbShowAbilitySplash(battler)
    battle.pbStartTerrain(battler, :Electric)
    # NOTE: The ability splash is hidden again in def pbStartTerrain.
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:FAIRYAURA,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is radiating a fairy aura!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:FOREWARN,
  proc { |ability, battler, battle, switch_in|
    next if !battler.pbOwnedByPlayer?
    highestPower = 0
    forewarnMoves = []
    battle.allOtherSideBattlers(battler.index).each do |b|
      b.eachMove do |m|
        power = m.baseDamage
        power = 160 if ["OHKO", "OHKOIce", "OHKOHitsUndergroundTarget"].include?(m.function)
        power = 150 if ["PowerHigherWithUserHP"].include?(m.function)    # Eruption
        # Counter, Mirror Coat, Metal Burst
        power = 120 if ["CounterPhysicalDamage",
                        "CounterSpecialDamage",
                        "CounterDamagePlusHalf"].include?(m.function)
        # Sonic Boom, Dragon Rage, Night Shade, Endeavor, Psywave,
        # Return, Frustration, Crush Grip, Gyro Ball, Hidden Power,
        # Natural Gift, Trump Card, Flail, Grass Knot
        power = 80 if ["FixedDamage20",
                       "FixedDamage40",
                       "FixedDamageUserLevel",
                       "LowerTargetHPToUserHP",
                       "FixedDamageUserLevelRandom",
                       "PowerHigherWithUserHappiness",
                       "PowerLowerWithUserHappiness",
                       "PowerHigherWithUserHP",
                       "PowerHigherWithTargetFasterThanUser",
                       "TypeAndPowerDependOnUserBerry",
                       "PowerHigherWithLessPP",
                       "PowerLowerWithUserHP",
                       "PowerHigherWithTargetWeight"].include?(m.function)
        power = 80 if Settings::MECHANICS_GENERATION <= 5 && m.function == "TypeDependsOnUserIVs"
        next if power < highestPower
        forewarnMoves = [] if power > highestPower
        forewarnMoves.push(m.name)
        highestPower = power
      end
    end
    if forewarnMoves.length > 0
      battle.pbShowAbilitySplash(battler)
      forewarnMoveName = forewarnMoves[battle.pbRandom(forewarnMoves.length)]
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} was alerted to {2}!",
          battler.pbThis, forewarnMoveName))
      else
        battle.pbDisplay(_INTL("{1}'s Forewarn alerted it to {2}!",
          battler.pbThis, forewarnMoveName))
      end
      battle.pbHideAbilitySplash(battler)
    end
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:FRISK,
  proc { |ability, battler, battle, switch_in|
    next if !battler.pbOwnedByPlayer?
    foes = battle.allOtherSideBattlers(battler.index).select { |b| b.item }
    if foes.length > 0
      battle.pbShowAbilitySplash(battler)
      if Settings::MECHANICS_GENERATION >= 6
        foes.each do |b|
          battle.pbDisplay(_INTL("{1} frisked {2} and found its {3}!",
             battler.pbThis, b.pbThis(true), b.itemName))
        end
      else
        foe = foes[battle.pbRandom(foes.length)]
        battle.pbDisplay(_INTL("{1} frisked the foe and found one {2}!",
           battler.pbThis, foe.itemName))
      end
      battle.pbHideAbilitySplash(battler)
    end
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:GRASSYSURGE,
  proc { |ability, battler, battle, switch_in|
    next if battle.field.terrain == :Grassy
    battle.pbShowAbilitySplash(battler)
    battle.pbStartTerrain(battler, :Grassy)
    # NOTE: The ability splash is hidden again in def pbStartTerrain.
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:iceface,
  proc { |ability, battler, battle, switch_in|
    next if !battler.isSpecies?(:EISCUE) || battler.form != 1
    next if battler.battle.pbWeather != :Hail
    battle.pbShowAbilitySplash(battler)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1}'s {2} activated!", battler.pbThis, battler.abilityName))
    end
    battler.pbChangeForm(0, _INTL("{1} transformed!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:IMPOSTER,
  proc { |ability, battler, battle, switch_in|
    next if !switch_in || battler.effects[PBEffects::Transform]
    choice = battler.pbDirectOpposing
    next if choice.fainted?
    next if choice.effects[PBEffects::Transform] ||
            choice.effects[PBEffects::Illusion] ||
            choice.effects[PBEffects::Substitute] > 0 ||
            choice.effects[PBEffects::SkyDrop] >= 0 ||
            choice.semiInvulnerable?
    battle.pbShowAbilitySplash(battler, true)
    battle.pbHideAbilitySplash(battler)
    battle.pbAnimation(:TRANSFORM, battler, choice)
    battle.scene.pbChangePokemon(battler, choice.pokemon)
    battler.pbTransform(choice)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:INTIMIDATE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.allOtherSideBattlers(battler.index).each do |b|
      next if !b.near?(battler)
      check_item = true
      if b.hasActiveAbility?(:CONTRARY)
        check_item = false if b.statStageAtMax?(:ATTACK)
      elsif b.statStageAtMin?(:ATTACK)
        check_item = false
      end
      check_ability = b.pbLowerAttackStatStageIntimidate(battler)
      b.pbAbilitiesOnIntimidated if check_ability
      b.pbItemOnIntimidatedCheck if check_item
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:INTREPIDSWORD,
  proc { |ability, battler, battle, switch_in|
    battler.pbRaiseStatStageByAbility(:ATTACK, 1, battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:MIMICRY,
  proc { |ability, battler, battle, switch_in|
    next if battle.field.terrain == :None
    PBAI::AbilityEffects.triggerOnTerrainChange(ability, battler, battle, false)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:MISTYSURGE,
  proc { |ability, battler, battle, switch_in|
    next if battle.field.terrain == :Misty
    battle.pbShowAbilitySplash(battler)
    battle.pbStartTerrain(battler, :Misty)
    # NOTE: The ability splash is hidden again in def pbStartTerrain.
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:MOLDBREAKER,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} breaks the mold!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:NEUTRALIZINGGAS,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler, true)
    battle.pbHideAbilitySplash(battler)
    battle.pbDisplay(_INTL("Neutralizing gas filled the area!"))
    battle.allBattlers.each do |b|
      # Slow Start - end all turn counts
      b.effects[PBEffects::SlowStart] = 0
      # Truant - let b move on its first turn after Neutralizing Gas disappears
      b.effects[PBEffects::Truant] = false
      # Gorilla Tactics - end choice lock
      if !b.hasActiveItem?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF])
        b.effects[PBEffects::ChoiceBand] = nil
      end
      # Illusion - end illusions
      if b.effects[PBEffects::Illusion]
        b.effects[PBEffects::Illusion] = nil
        if !b.effects[PBEffects::Transform]
          battle.scene.pbChangePokemon(b, b.pokemon)
          battle.pbDisplay(_INTL("{1}'s {2} wore off!", b.pbThis, b.abilityName))
          battle.pbSetSeen(b)
        end
      end
    end
    # Trigger items upon Unnerve being negated
    battler.ability_id = nil   # Allows checking if Unnerve was active before
    had_unnerve = battle.pbCheckGlobalAbility(:UNNERVE)
    battler.ability_id = :NEUTRALIZINGGAS
    if had_unnerve && !battle.pbCheckGlobalAbility(:UNNERVE)
      battle.allBattlers.each { |b| b.pbItemsOnUnnerveEnding }
    end
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:OMNIPOTENT,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is staring you down!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:PASTELVEIL,
  proc { |ability, battler, battle, switch_in|
    next if battler.allAllies.none? { |b| b.status == :POISON }
    battle.pbShowAbilitySplash(battler)
    battler.allAllies.each do |b|
      next if b.status != :POISON
      b.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s {2} cured {3}'s poisoning!",
           battler.pbThis, battler.abilityName, b.pbThis(true)))
      end
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:PRESSURE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is exerting its pressure!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:PRIMORDIALSEA,
  proc { |ability, battler, battle, switch_in|
    battle.pbStartWeatherAbility(:HeavyRain, battler, true)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:PSYCHICSURGE,
  proc { |ability, battler, battle, switch_in|
    next if battle.field.terrain == :Psychic
    battle.pbShowAbilitySplash(battler)
    battle.pbStartTerrain(battler, :Psychic)
    # NOTE: The ability splash is hidden again in def pbStartTerrain.
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:SANDSTREAM,
  proc { |ability, battler, battle, switch_in|
    battle.pbStartWeatherAbility(:Sandstorm, battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:SCREENCLEANER,
  proc { |ability, battler, battle, switch_in|
    next if battler.pbOwnSide.effects[PBEffects::AuroraVeil] == 0 &&
            battler.pbOwnSide.effects[PBEffects::LightScreen] == 0 &&
            battler.pbOwnSide.effects[PBEffects::Reflect] == 0 &&
            battler.pbOpposingSide.effects[PBEffects::AuroraVeil] == 0 &&
            battler.pbOpposingSide.effects[PBEffects::LightScreen] == 0 &&
            battler.pbOpposingSide.effects[PBEffects::Reflect] == 0
    battle.pbShowAbilitySplash(battler)
    if battler.pbOpposingSide.effects[PBEffects::AuroraVeil] > 0
      battler.pbOpposingSide.effects[PBEffects::AuroraVeil] = 0
      battle.pbDisplay(_INTL("{1}'s Aurora Veil wore off!", battler.pbOpposingTeam))
    end
    if battler.pbOpposingSide.effects[PBEffects::LightScreen] > 0
      battler.pbOpposingSide.effects[PBEffects::LightScreen] = 0
      battle.pbDisplay(_INTL("{1}'s Light Screen wore off!", battler.pbOpposingTeam))
    end
    if battler.pbOpposingSide.effects[PBEffects::Reflect] > 0
      battler.pbOpposingSide.effects[PBEffects::Reflect] = 0
      battle.pbDisplay(_INTL("{1}'s Reflect wore off!", battler.pbOpposingTeam))
    end
    if battler.pbOwnSide.effects[PBEffects::AuroraVeil] > 0
      battler.pbOwnSide.effects[PBEffects::AuroraVeil] = 0
      battle.pbDisplay(_INTL("{1}'s Aurora Veil wore off!", battler.pbTeam))
    end
    if battler.pbOwnSide.effects[PBEffects::LightScreen] > 0
      battler.pbOwnSide.effects[PBEffects::LightScreen] = 0
      battle.pbDisplay(_INTL("{1}'s Light Screen wore off!", battler.pbTeam))
    end
    if battler.pbOwnSide.effects[PBEffects::Reflect] > 0
      battler.pbOwnSide.effects[PBEffects::Reflect] = 0
      battle.pbDisplay(_INTL("{1}'s Reflect wore off!", battler.pbTeam))
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:SLOWSTART,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battler.effects[PBEffects::SlowStart] = 5
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1} can't get it going!", battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1} can't get it going because of its {2}!",
         battler.pbThis, battler.abilityName))
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:SNOWWARNING,
  proc { |ability, battler, battle, switch_in|
    battle.pbStartWeatherAbility(:Hail, battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:TERAVOLT,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is staring you down!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:TURBOBLAZE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is radiating a blazing aura!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:UNNERVE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is too nervous to eat Berries!", battler.pbOpposingTeam))
    battle.pbHideAbilitySplash(battler)
  }
)

#===============================================================================
# OnSwitchOut handlers
#===============================================================================

PBAI::AbilityEffects::OnSwitchOut.add(:IMMUNITY,
  proc { |ability, battler, endOfBattle|
    next if battler.status != :POISON
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.status = :NONE
  }
)

PBAI::AbilityEffects::OnSwitchOut.add(:INSOMNIA,
  proc { |ability, battler, endOfBattle|
    next if battler.status != :SLEEP
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.status = :NONE
  }
)

PBAI::AbilityEffects::OnSwitchOut.copy(:INSOMNIA, :VITALSPIRIT)

PBAI::AbilityEffects::OnSwitchOut.add(:LIMBER,
  proc { |ability, battler, endOfBattle|
    next if battler.status != :PARALYSIS
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.status = :NONE
  }
)

PBAI::AbilityEffects::OnSwitchOut.add(:MAGMAARMOR,
  proc { |ability, battler, endOfBattle|
    next if battler.status != :FROZEN
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.status = :NONE
  }
)

PBAI::AbilityEffects::OnSwitchOut.add(:NATURALCURE,
  proc { |ability, battler, endOfBattle|
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.status = :NONE
  }
)

PBAI::AbilityEffects::OnSwitchOut.add(:REGENERATOR,
  proc { |ability, battler, endOfBattle|
    next if endOfBattle
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.pbRecoverHP(battler.totalhp / 3, false, false)
  }
)

PBAI::AbilityEffects::OnSwitchOut.add(:WATERVEIL,
  proc { |ability, battler, endOfBattle|
    next if battler.status != :BURN
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.status = :NONE
  }
)

PBAI::AbilityEffects::OnSwitchOut.copy(:WATERVEIL, :WATERBUBBLE)

#===============================================================================
# ChangeOnBattlerFainting handlers
#===============================================================================

PBAI::AbilityEffects::ChangeOnBattlerFainting.add(:POWEROFALCHEMY,
  proc { |ability, battler, fainted, battle|
    next if battler.opposes?(fainted)
    next if fainted.ungainableAbility? ||
       [:POWEROFALCHEMY, :RECEIVER, :TRACE, :WONDERGUARD].include?(fainted.ability_id)
    battle.pbShowAbilitySplash(battler, true)
    battler.ability = fainted.ability
    battle.pbReplaceAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1}'s {2} was taken over!", fainted.pbThis, fainted.abilityName))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::ChangeOnBattlerFainting.copy(:POWEROFALCHEMY, :RECEIVER)

#===============================================================================
# OnBattlerFainting handlers
#===============================================================================

PBAI::AbilityEffects::OnBattlerFainting.add(:SOULHEART,
  proc { |ability, battler, fainted, battle|
    battler.pbRaiseStatStageByAbility(:SPECIAL_ATTACK, 1, battler)
  }
)

#===============================================================================
# OnTerrainChange handlers
#===============================================================================

PBAI::AbilityEffects::OnTerrainChange.add(:MIMICRY,
  proc { |ability, battler, battle, ability_changed|
    if battle.field.terrain == :None
      # Revert to original typing
      battle.pbShowAbilitySplash(battler)
      battler.pbResetTypes
      battle.pbDisplay(_INTL("{1} changed back to its regular type!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    else
      # Change to new typing
      terrain_hash = {
        :Electric => :ELECTRIC,
        :Grassy   => :GRASS,
        :Misty    => :FAIRY,
        :Psychic  => :PSYCHIC
      }
      new_type = terrain_hash[battle.field.terrain]
      new_type_name = nil
      if new_type
        type_data = GameData::Type.try_get(new_type)
        new_type = nil if !type_data
        new_type_name = type_data.name if type_data
      end
      if new_type
        battle.pbShowAbilitySplash(battler)
        battler.pbChangeTypes(new_type)
        battle.pbDisplay(_INTL("{1}'s type changed to {2}!", battler.pbThis, new_type_name))
        battle.pbHideAbilitySplash(battler)
      end
    end
  }
)

#===============================================================================
# OnIntimidated handlers
#===============================================================================

PBAI::AbilityEffects::OnIntimidated.add(:RATTLED,
  proc { |ability, battler, battle|
    next if Settings::MECHANICS_GENERATION < 8
    battler.pbRaiseStatStageByAbility(:SPEED, 1, battler)
  }
)

#===============================================================================
# CertainEscapeFromBattle handlers
#===============================================================================

PBAI::AbilityEffects::CertainEscapeFromBattle.add(:RUNAWAY,
  proc { |ability, battler|
    next true
  }
)

#Fairy Bubble
PBAI::AbilityEffects::DamageCalcFromUser.add(:FAIRYBUBBLE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 2 if type == :FAIRY
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:FAIRYBUBBLE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] /= 2 if type == :POISON
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:FEVERPITCH,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:final_damage_multiplier] /= 2 if type == :PSYCHIC
  }
)

PBAI::AbilityEffects::StatusCure.copy(:WATERVEIL,:FEVERPITCH)
PBAI::AbilityEffects::StatusImmunity.copy(:WATERVEIL,:FEVERPITCH)

PBAI::AbilityEffects::OnSwitchOut.add(:FAIRYBUBBLE,
  proc { |ability, battler, endOfBattle|
    next if battler.status == :NONE
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.status = :NONE
  }
)

PBAI::AbilityEffects::StatusImmunity.add(:FAIRYBUBBLE,
  proc { |ability, battler, status|
    next true if status != :NONE
  }
)

PBAI::AbilityEffects::StatusCure.add(:FAIRYBUBBLE,
  proc { |ability, battler|
    next if battler.status == :NONE
    battler.battle.pbShowAbilitySplash(battler)
    battler.pbCureStatus(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
    if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battler.battle.pbDisplay(_INTL("{1}'s {2} healed its status!", battler.pbThis, battler.abilityName))
    end
    battler.battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:LEGENDARMOR,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityHealingAbility(user, move, type, :DRAGON, show_message)
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:WATERCOMPACTION,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type, :WATER, :DEFENSE, 2, show_message)
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:STEAMENGINE,
  proc { |ability, user, target, move, type, battle, show_message|
    next (target.pbMoveImmunityStatRaisingAbility(user, move, type, :WATER, :SPEED, 6, show_message) || target.pbMoveImmunityStatRaisingAbility(user, move, type, :FIRE, :SPEED, 6, show_message))
  }
)

#Composure
PBAI::AbilityEffects::DamageCalcFromUser.add(:COMPOSURE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 2 if move.specialMove?
  }
)

#Rock Head
PBAI::AbilityEffects::DamageCalcFromUser.add(:ROCKHEAD,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if move.headMove?
  }
)

#Gavel Power
PBAI::AbilityEffects::DamageCalcFromUser.add(:GAVELPOWER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.5 if move.hammerMove?
  }
)

#Step Master
PBAI::AbilityEffects::DamageCalcFromUser.add(:STEPMASTER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if move.kickingMove?
  }
)

#Tight Focus
PBAI::AbilityEffects::DamageCalcFromUser.add(:TIGHTFOCUS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.3 if move.beamMove?
  }
)

#Vampiric
PBAI::AbilityEffects::DamageCalcFromUser.add(:VAMPIRIC,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.2 if move.healingMove?
  }
)

PBAI::AbilityEffects::OnEndOfUsingMove.add(:VAMPIRIC,
  proc { |ability,user,targets,move,battle|
    next if !move.bitingMove?
    next if user.hp == user.totalhp
    totalDamage = 0
    for target in targets
      totalDamage += target.damageState.totalHPLost
    end
    next if totalDamage<=0
    battle.pbShowAbilitySplash(user)
    user.pbRecoverHP(totalDamage/2)
    battle.pbDisplay(_INTL("{1} sapped some HP.",user.pbThis))
    battle.pbHideAbilitySplash(user)
  }
)

#Vocal Fry
PBAI::AbilityEffects::DamageCalcFromUser.add(:VOCALFRY,
  proc { |ability,user,target,move,mults,baseDmg,type|
    if move.soundMove? && move.damagingMove?
      mults[:base_damage_multiplier] = (mults[:base_damage_multiplier]*1.2).round
    end
  }
)

#Unknown Power
PBAI::AbilityEffects::DamageCalcFromAlly.add(:UNKNOWNPOWER,
  proc { |ability,user,target,move,mults,baseDmg,type|
    mults[:attack_multiplier] *= 1.3
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:UNKNOWNPOWER,
  proc { |ability,user,target,move,mults,baseDmg,type|
    mults[:attack_multiplier] *= 1.3
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:UNKNOWNPOWER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:defense_multiplier] *= 1.5
  }
)

PBAI::AbilityEffects::DamageCalcFromTargetAlly.add(:UNKNOWNPOWER,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:defense_multiplier] *= 1.5
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:TRASHSHIELD,
  proc { |ability, user, target, move, mults, baseDmg, type|
    if Effectiveness.super_effective?(target.damageState.typeMod)
      mults[:defense_multiplier] /= 2
    else
      mults[:defense_multiplier] *= 1.5
    end
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:SCALER,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if type!=:ROCK
    if show_message
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!",
           target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:PASTELVEIL,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if type!=:POISON
    if show_message
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!",
           target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:UNTAINTED,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if type!=:DARK
    if show_message
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!",
           target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)


#Haunted
PBAI::AbilityEffects::OnSwitchIn.add(:HAUNTED,
  proc { |ability,battler,battle|
    battler.effects[PBEffects::Type3] = :GHOST
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is possessed!",battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

#Shadow Guard
PBAI::AbilityEffects::OnSwitchIn.add(:SHADOWGUARD,
  proc { |ability,battler,battle|
    battler.effects[PBEffects::Type3] = :DARK
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is shrouded in the shadows!",battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

#Gaia Force
PBAI::AbilityEffects::OnSwitchIn.add(:GAIAFORCE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is gathering the power of the earth!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

#Reverse Room
PBAI::AbilityEffects::OnSwitchIn.add(:REVERSEROOM,
  proc { |ability, battler, battle, switch_in|
    next if $game_temp.battle_rules["inverseBattle"]
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is twisting type matchups against it!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::ModifyTypeEffectiveness.add(:REVERSEROOM,
  proc { |ability, user, target, move, battle, effectiveness|
    next if !move.damagingMove?
    next if user.hasMoldBreaker?
    eff = effectiveness/8
    next if eff == Effectiveness::NORMAL_EFFECTIVE_MULTIPLIER
    if eff == Effectiveness::SUPER_EFFECTIVE_MULTIPLIER
      next Effectiveness::NOT_VERY_EFFECTIVE_MULTIPLIER
    else
      next Effectiveness::SUPER_EFFECTIVE_MULTIPLIER
    end
  }
)

# Cacophony
PBAI::AbilityEffects::OnSwitchIn.add(:CACOPHONY,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is creating a loud noise!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

#Fever Pitch
PBAI::AbilityEffects::OnSwitchIn.add(:FEVERPITCH,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is ramping up its toxic power!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:WEBWEAVER,
  proc { |ability, user, target, move, battle|
    next if target.pbOpposingSide.effects[PBEffects::StickyWeb] == true
    battle.pbShowAbilitySplash(target)
    battle.scene.pbAnimation(GameData::Move.get(:STICKYWEB).id,target,target.pbDirectOpposing)
    target.pbOpposingSide.effects[PBEffects::StickyWeb] = true
    battle.pbDisplay(_INTL("{1}'s {2} set Sticky Web!",target.pbThis,target.abilityName))
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:SPLINTER,
  proc { |ability, user, target, move, battle|
    next if target.pbOpposingSide.effects[PBEffects::StealthRock] == true
    battle.pbShowAbilitySplash(target)
    battle.scene.pbAnimation(GameData::Move.get(:STEALTHROCK).id,target,target.pbDirectOpposing)
    target.pbOpposingSide.effects[PBEffects::StealthRock] = true
    battle.pbDisplay(_INTL("{1}'s {2} set Stealth Rocks!",target.pbThis,target.abilityName))
    battle.pbHideAbilitySplash(target)
  }
)

#Mind Games & Medusoid
PBAI::AbilityEffects::OnSwitchIn.add(:MINDGAMES,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.allOtherSideBattlers(battler.index).each do |b|
      next if !b.near?(battler)
      check_item = true
      if b.hasActiveAbility?(:CONTRARY)
        check_item = false if b.statStageAtMax?(:SPECIAL_ATTACK)
      elsif b.statStageAtMin?(:SPECIAL_ATTACK)
        check_item = false
      end
      check_ability = b.pbLowerSpAtkStatStageMindGames(battler)
      b.pbAbilitiesOnIntimidated if check_ability
      b.pbItemOnIntimidatedCheck if check_item
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:MEDUSOID,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.allOtherSideBattlers(battler.index).each do |b|
      next if !b.near?(battler)
      check_item = true
      if b.hasActiveAbility?(:CONTRARY)
        check_item = false if b.statStageAtMax?(:SPEED)
      elsif b.statStageAtMin?(:SPEED)
        check_item = false
      end
      check_ability = b.pbLowerSpeedStatStageMedusoid(battler)
      b.pbAbilitiesOnIntimidated if check_ability
      b.pbItemOnIntimidatedCheck if check_item
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnEndOfUsingMove.add(:LIONSPRIDE,
  proc { |ability, user, targets, move, battle|
    next if battle.pbAllFainted?(user.idxOpposingSide)
    numFainted = 0
    targets.each { |b| numFainted += 1 if b.damageState.fainted }
    next if numFainted == 0 || !user.pbCanRaiseStatStage?(:SPECIAL_ATTACK, user)
    user.pbRaiseStatStageByAbility(:SPECIAL_ATTACK, 1, user)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:LIONSPRIDE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} is too nervous to eat Berries!", battler.pbOpposingTeam))
    battle.pbHideAbilitySplash(battler)
    battler.ability_id = ability
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DIMENSIONSHIFT,
  proc { |ability,battler,battle|
    battle.pbShowAbilitySplash(battler)
    if $gym_tr == true
      battle.pbDisplay(_INTL("The dimensions are unchanged!"))
    else
      if battle.field.effects[PBEffects::TrickRoom] > 0
        battle.field.effects[PBEffects::TrickRoom] = 0
        battle.pbDisplay(_INTL("{1} reverted the dimensions!",battler.pbThis))
        battle.pbCalculatePriority
      else
        battle.field.effects[PBEffects::TrickRoom] = 5
        battle.pbDisplay(_INTL("{1} twisted the dimensions!",battler.pbThis))
        battle.pbCalculatePriority
      end
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::EndOfRoundHealing.add(:RESURGENCE,
  proc { |ability,battler,battle|
    next if !battler.canHeal?
    battle.pbShowAbilitySplash(battler)
    battler.pbRecoverHP(battler.totalhp/16)
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1}'s HP was restored.",battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1}'s {2} restored its HP.",battler.pbThis,battler.abilityName))
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::EndOfRoundHealing.add(:HOPEFULTOLL,
  proc { |ability,battler,battle|
    battler.status = :NONE
    battle.pbShowAbilitySplash(battler)
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("{1} rang a healing bell!",battler.pbThis))
    else
      battle.pbDisplay(_INTL("{1} sounded a {2}",battler.pbThis,battler.abilityName))
    end
    battle.pbParty(battler.index).each_with_index do |pkmn,i|
      next if !pkmn || !pkmn.able? || pkmn.status==:NONE
      pkmn.status = :NONE
    end
    if battle.doublebattle
      battle.battlers[0].status = :NONE
      battle.battlers[2].status = :NONE
    end
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnBeingHit.add(:ICEBODY,
  proc { |ability,user,target,move,battle|
    next if !move.pbContactMove?(user)
    next if user.frozen? || battle.pbRandom(100)>=30
    next if !user.pbCanFreeze?(target,false)
    battle.pbShowAbilitySplash(target)
    if user.pbCanFreeze?(target,PokeBattle_SceneConstants::USE_ABILITY_SPLASH) &&
       user.affectedByContactEffect?(PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      msg = nil
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        msg = _INTL("{1}'s {2} gave {3} frostbite!",target.pbThis,target.abilityName,user.pbThis(true))
      end
      user.pbFreezeIceBody(target,msg)
    end
    battle.pbHideAbilitySplash(target)
  }
)

PBAI::AbilityEffects::StatLossImmunityAbilityUnshaken.add(:UNSHAKEN,
  proc { |ability,battler,stat,battle,showMessages|
    if showMessages
      battle.pbShowAbilitySplash(battler)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1}'s stats cannot be lowered!",battler.pbThis))
      else
        battle.pbDisplay(_INTL("{1}'s {2} prevents stat loss!",battler.pbThis,battler.abilityName))
      end
      battle.pbHideAbilitySplash(battler)
    end
    next true
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:BACKDRAFT,
  proc { |ability, battler, mult|
    next mult * 2 if [:StrongWinds].include?(battler.battle.pbWeather)
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:MEADOWRUSH,
  proc { |ability, battler, mult|
    next mult * 2 if battler.battle.field.terrain == :Grassy
  }
)

PBAI::AbilityEffects::SpeedCalc.add(:BRAINBLAST,
  proc { |ability, battler, mult|
    next mult * 2 if battler.battle.field.terrain == :Psychic
  }
)


PBAI::AbilityEffects::MoveImmunity.add(:PESTICIDE,
  proc { |ability, user, target, move, type, battle, show_message|
    next if type != :BUG
    battle.pbShowAbilitySplash(target)
    if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
      battle.pbDisplay(_INTL("It doesn't affect {1}...",target.pbThis(true)))
    else
      battle.pbDisplay(_INTL("{1}'s {2} blocks {3}!",target.pbThis,target.abilityName,move.name))
    end
    if user.status == :NONE
      anim_name = GameData::Status.get(:POISON).animation
      battle.pbCommonAnimation(anim_name, user)
      user.status = :POISON
    end
    battle.pbParty(user.index).each do |pkmn|
      next if !pkmn.hasType?(:BUG) || pkmn.hasType?(:STEEL) || pkmn.hasType?(:POISON)
      next if pkmn.hasAbility?([:IMMUNITY,:PURIFYINGSALT,:FAIRYBUBBLE,:COMATOSE,:SHIELDSDOWN])
      pkmn.status = :POISON
      battle.pbDisplay(_INTL("All Bug-types in the party were Poisoned!"))
    end
    battle.pbHideAbilitySplash(target)
    next true
  }
)

PBAI::AbilityEffects::MoveImmunity.copy(:WATERABSORB, :EMBODYASPECT_1)
PBAI::AbilityEffects::OnStatLoss.copy(:DEFIANT, :EMBODYASPECT)

PBAI::AbilityEffects::TrappingByTarget.add(:DEATHGRIP,
  proc { |ability, switcher, bearer, battle|
    next true if !switcher.hasActiveAbility?(:DEATHGRIP)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:FOREWARN,
  proc { |ability, battler, battle, switch_in|
    next if !battler.pbOwnedByPlayer?
    highestPower = 0
    forewarnMoves = []
    battle.allOtherSideBattlers(battler.index).each do |b|
      b.eachMove do |m|
        power = m.baseDamage
        power = 160 if ["OHKO", "OHKOIce", "OHKOHitsUndergroundTarget"].include?(m.function)
        power = 150 if ["PowerHigherWithUserHP"].include?(m.function)    # Eruption
        # Counter, Mirror Coat, Metal Burst
        power = 120 if ["CounterPhysicalDamage",
                        "CounterSpecialDamage",
                        "CounterDamagePlusHalf"].include?(m.function)
        # Sonic Boom, Dragon Rage, Night Shade, Endeavor, Psywave,
        # Return, Frustration, Crush Grip, Gyro Ball, Hidden Power,
        # Natural Gift, Trump Card, Flail, Grass Knot
        power = 80 if ["FixedDamage20",
                       "FixedDamage40",
                       "FixedDamageUserLevel",
                       "LowerTargetHPToUserHP",
                       "FixedDamageUserLevelRandom",
                       "PowerHigherWithUserHappiness",
                       "PowerLowerWithUserHappiness",
                       "PowerHigherWithUserHP",
                       "PowerHigherWithTargetFasterThanUser",
                       "TypeAndPowerDependOnUserBerry",
                       "PowerHigherWithLessPP",
                       "PowerLowerWithUserHP",
                       "PowerHigherWithTargetWeight"].include?(m.function)
        power = 80 if Settings::MECHANICS_GENERATION <= 5 && m.function == "TypeDependsOnUserIVs"
        next if power < highestPower
        forewarnMoves = [] if power > highestPower
        forewarnMoves.push(m.name)
        highestPower = power
        $category = m.category
      end
    end
    if forewarnMoves.length > 0
      battle.pbShowAbilitySplash(battler)
      forewarnMoveName = forewarnMoves[battle.pbRandom(forewarnMoves.length)]
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} was alerted to {2}!",
          battler.pbThis, forewarnMoveName))
      else
        battle.pbDisplay(_INTL("{1}'s Forewarn alerted it to {2}!",
          battler.pbThis, forewarnMoveName))
      end
      stat = $category == 1 ? :SPECIAL_DEFENSE : :DEFENSE
      battler.pbRaiseStatStageByAbility(stat, 1, battler)
      battle.pbHideAbilitySplash(battler)
    end
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:DOWNLOAD,
  proc { |ability, battler, battle, switch_in|
    oDef = oSpDef = 0
    battle.allOtherSideBattlers(battler.index).each do |b|
      oDef   += b.defense
      oSpDef += b.spdef
    end
    stat = (oDef < oSpDef) ? :ATTACK : :SPECIAL_ATTACK
    mod = battler.hasActiveItem?(:UPGRADE) ? 2 : 1
    battler.pbRaiseStatStageByAbility(stat, mod, battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:KEENEYE,
  proc { |ability, battler, battle, switch_in|
    next if battler.effects[PBEffects::FocusEnergy] >= 2
    battle.pbShowAbilitySplash(battler)
    battle.scene.pbAnimation(GameData::Move.get(:FOCUSENERGY).id,battler,battler)
    battler.effects[PBEffects::FocusEnergy] = 2
    battle.pbDisplay(_INTL("{1} is getting pumped!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::MoveBlocking.copy(:DAZZLING, :QUEENLYMAJESTY, :ARMORTAIL)

#===============================================================================
# Rocky Payload
#===============================================================================
PBAI::AbilityEffects::DamageCalcFromUser.add(:ROCKYPAYLOAD,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 1.5 if type == :ROCK
  }
)

#===============================================================================
# Sharpness
#===============================================================================
PBAI::AbilityEffects::DamageCalcFromUser.add(:SHARPNESS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:base_damage_multiplier] *= 1.5 if move.slicingMove?
  }
)

#===============================================================================
# Supreme Overlord
#===============================================================================
PBAI::AbilityEffects::DamageCalcFromUser.add(:SUPREMEOVERLORD,
  proc { |ability, user, target, move, mults, baseDmg, type|
    bonus = user.effects[PBEffects::SupremeOverlord]
    next if bonus <= 0
    mults[:base_damage_multiplier] *= (1 + (0.1 * bonus))
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:SUPREMEOVERLORD,
  proc { |ability, battler, battle, switch_in|
    numFainted = [5, battler.num_fainted_allies].min
    next if numFainted <= 0
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} gained strength from the fallen!", battler.pbThis))
    battler.effects[PBEffects::SupremeOverlord] = numFainted
    battle.pbHideAbilitySplash(battler)
  }
)

#===============================================================================
# Mycelium Might
#===============================================================================
PBAI::AbilityEffects::PriorityBracketChange.add(:MYCELIUMMIGHT,
  proc { |ability, battler, battle|
    choices = battle.choices[battler.index]
    if choices[0] == :UseMove
      next -1 if choices[2].statusMove?
    end
  }
)

#===============================================================================
# Purifying Salt
#===============================================================================
PBAI::AbilityEffects::StatusImmunity.add(:PURIFYINGSALT,
  proc { |ability, battler, status|
    next true
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:PURIFYINGSALT,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] /= 2 if type == :GHOST
  }
)

#===============================================================================
# Earth Eater
#===============================================================================
PBAI::AbilityEffects::MoveImmunity.add(:EARTHEATER,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityHealingAbility(user, move, type, :GROUND, show_message)
  }
)

#===============================================================================
# Good As Gold
#===============================================================================
PBAI::AbilityEffects::MoveImmunity.add(:GOODASGOLD,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !move.statusMove?
    next false if user.index == target.index
    if show_message
      battle.pbShowAbilitySplash(target)
      if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} blocks {3}!",
           target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

#===============================================================================
# Well-Baked Body
#===============================================================================
PBAI::AbilityEffects::MoveImmunity.add(:WELLBAKEDBODY,
  proc { |ability, user, target, move, type, battle, show_message|
    next target.pbMoveImmunityStatRaisingAbility(user, move, type, :FIRE, :DEFENSE, 2, show_message)
  }
)

#===============================================================================
# Wind Rider
#===============================================================================
PBAI::AbilityEffects::MoveImmunity.add(:WINDRIDER,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !move.windMove?
    next false if user.index == target.index
    if show_message
      battle.pbShowAbilitySplash(target)
      if target.pbCanRaiseStatStage?(:ATTACK, user, move)
        if PokeBattle_SceneConstants::USE_ABILITY_SPLASH
          target.pbRaiseStatStage(:ATTACK, 1, user)
        else
          target.pbRaiseStatStageByCause(:ATTACK, 1, user, target.abilityName)
        end
      elsif PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("It doesn't affect {1}...", target.pbThis(true)))
      else
        battle.pbDisplay(_INTL("{1}'s {2} made {3} ineffective!", target.pbThis, target.abilityName, move.name))
      end
      battle.pbHideAbilitySplash(target)
    end
    next true
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:WINDRIDER,
  proc { |ability, battler, battle, switch_in|
    next if !battler.pbCanRaiseStatStage?(:ATTACK, battler)
    if battler.pbOwnSide.effects[PBEffects::Tailwind] > 0 || (battle.pbWeather == :StrongWinds && $gym_weather == true)
        battler.pbRaiseStatStageByAbility(:ATTACK, 1, battler)
      end
  }
)

#===============================================================================
# Anger Shell
#===============================================================================
PBAI::AbilityEffects::AfterMoveUseFromTarget.add(:ANGERSHELL,
  proc { |ability, target, user, move, switched_battlers, battle|
    next if !move.damagingMove?
    next if !target.droppedBelowHalfHP
    showAnim = true
    battle.pbShowAbilitySplash(target)
    [:ATTACK, :SPECIAL_ATTACK, :SPEED].each do |stat|
      next if !target.pbCanRaiseStatStage?(stat, user, nil, true)
      if target.pbRaiseStatStage(stat, 1, user, showAnim)
        showAnim = false
      end
    end
    showAnim = true
    [:DEFENSE, :SPECIAL_DEFENSE].each do |stat|
      next if !target.pbCanLowerStatStage?(stat, user, nil, true)
      if target.pbLowerStatStage(stat, 1, user, showAnim)
        showAnim = false
      end
    end
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Electromorphosis
#===============================================================================
PBAI::AbilityEffects::OnBeingHit.add(:ELECTROMORPHOSIS,
  proc { |ability, user, target, move, battle|
    next if target.fainted?
    next if target.effects[PBEffects::Charge] > 0
    battle.pbShowAbilitySplash(target)
    target.effects[PBEffects::Charge] = 2
    battle.pbDisplay(_INTL("Being hit by {1} charged {2} with power!", move.name, target.pbThis(true)))
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Lingering Aroma
#===============================================================================
PBAI::AbilityEffects::OnBeingHit.copy(:MUMMY, :LINGERINGAROMA)

#===============================================================================
# Seed Sower
#===============================================================================
PBAI::AbilityEffects::OnBeingHit.add(:SEEDSOWER,
  proc { |ability, user, target, move, battle|
    next if !move.damagingMove?
    next if battle.field.terrain == :Grassy
    battle.pbShowAbilitySplash(target)
    battle.pbStartTerrain(target, :Grassy)
  }
)

#===============================================================================
# Thermal Exchange
#===============================================================================
PBAI::AbilityEffects::OnBeingHit.add(:THERMALEXCHANGE,
  proc { |ability, user, target, move, battle|
    next if move.calcType != :FIRE
    target.pbRaiseStatStageByAbility(:ATTACK, 1, target)
  }
)

PBAI::AbilityEffects::StatusImmunity.add(:THERMALEXCHANGE,
  proc { |ability, battler, status|
    next true if status == :BURN
  }
)

PBAI::AbilityEffects::StatusCure.copy(:WATERVEIL, :WATERBUBBLE, :THERMALEXCHANGE)

#===============================================================================
# Toxic Debris
#===============================================================================
PBAI::AbilityEffects::OnBeingHit.add(:TOXICDEBRIS,
  proc { |ability, user, target, move, battle|
    next if !move.physicalMove?
    next if target.damageState.substitute
    next if $toxic_spikes[target.idxOpposingSide] >= 2
    battle.pbShowAbilitySplash(target)
    $toxic_spikes[target.idxOpposingSide] += 1
    battle.pbAnimation(:TOXICSPIKES, target, target.pbDirectOpposing)
    battle.pbDisplay(_INTL("Poison spikes were scattered on the ground all around {1}!", target.pbOpposingTeam(true)))
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Wind Power
#===============================================================================
PBAI::AbilityEffects::MoveImmunity.add(:WINDPOWER,
  proc { |ability, user, target, move, type, battle, show_message|
    next if !move.windMove?
    next if target.effects[PBEffects::Charge] > 0
    battle.pbShowAbilitySplash(target)
    target.effects[PBEffects::Charge] = 2
    battle.pbDisplay(_INTL("Being hit by {1} charged {2} with power!", move.name, target.pbThis(true)))
    battle.pbHideAbilitySplash(target)
  }
)

#===============================================================================
# Cud Chew
#===============================================================================
PBAI::AbilityEffects::EndOfRoundEffect.add(:CUDCHEW,
  proc { |ability, battler, battle|
    next if battler.item
    next if !battler.recycleItem || !GameData::Item.get(battler.recycleItem).is_berry?
    case battler.effects[PBEffects::CudChew]
    when 0 # End round after eat berry
      battler.effects[PBEffects::CudChew] += 1
    else # next turn after eat berry
      battler.effects[PBEffects::CudChew] = 0
      battle.pbShowAbilitySplash(battler, true)
      battle.pbHideAbilitySplash(battler)
      battler.pbHeldItemTriggerCheck(battler.recycleItem, true)
      battler.setRecycleItem(nil)
    end
  }
)

#===============================================================================
# Opportunist
#===============================================================================
PBAI::AbilityEffects::OnOpposingStatGain.add(:OPPORTUNIST,
  proc { |ability, battler, battle, statUps|
    showAnim = true
    battle.pbShowAbilitySplash(battler)
    statUps.each do |stat, increment|
    next if !battler.pbCanRaiseStatStage?(stat, battler)
      if battler.pbRaiseStatStage(stat, increment, battler, showAnim)
        showAnim = false
      end
    end
    battle.pbDisplay(_INTL("{1}'s stats won't go any higher!", user.pbThis)) if showAnim
    battle.pbHideAbilitySplash(battler)
    battler.pbItemOpposingStatGainCheck(statUps)
    # Mirror Herb can trigger off this ability.
    if !showAnim 
      opposingStatUps = battle.sideStatUps[battler.idxOwnSide]
      battle.allOtherSideBattlers(battler.index).each do |b|
        next if !b || b.fainted?
        if b.itemActive?
          b.pbItemOpposingStatGainCheck(opposingStatUps)
        end
      end
      opposingStatUps.clear
    end
  }
)

#===============================================================================
# Costar
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:COSTAR,
  proc { |ability, battler, battle, switch_in|
    battler.allAllies.each do |b|
      next if b.index == battler.index
      next if !b.hasAlteredStatStages? && b.effects[PBEffects::FocusEnergy] == 0
      battle.pbShowAbilitySplash(battler)
      battler.effects[PBEffects::FocusEnergy] = b.effects[PBEffects::FocusEnergy]
      GameData::Stat.each_battle { |stat| battler.stages[stat.id] = b.stages[stat.id] }
      battle.pbDisplay(_INTL("{1} copied {2}'s stat changes!", battler.pbThis, b.pbThis(true)))
      battle.pbHideAbilitySplash(battler)
      break
    end
  }
)

#===============================================================================
# Zero To Hero
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:ZEROTOHERO,
  proc { |ability, battler, battle, switch_in|
    next if battler.form == 0 || battler.ability_triggered?
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1} underwent a heroic transformation!", battler.pbThis))
    battle.pbHideAbilitySplash(battler)
    battle.pbSetAbilityTrigger(battler)
  }
)

PBAI::AbilityEffects::OnSwitchOut.add(:ZEROTOHERO,
  proc { |ability, battler, endOfBattle|
    next if battler.form == 1 || endOfBattle
    PBDebug.log("[Ability triggered] #{battler.pbThis}'s #{battler.abilityName}")
    battler.pbChangeForm(1, "")
  }
)

#===============================================================================
# Commander
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:COMMANDER,
  proc { |ability, battler, battle, switch_in|
    next if battler.effects[PBEffects::Commander]
    showAnim = true
    battler.allAllies.each{|b|
      next if !b || !b.near?(battler) || b.fainted?
      next if !b.isSpecies?(:DONDOZO)
      next if b.effects[PBEffects::Commander]
      battle.pbShowAbilitySplash(battler)
      battle.pbClearChoice(battler.index)
      battle.pbDisplay(_INTL("{1} goes inside the mouth of {2}!", battler.pbThis, b.pbThis(true)))
      battle.scene.sprites["pokemon_#{battler.index}"].visible = false
      b.effects[PBEffects::Commander] = [battler.index, battler.form]
      battler.effects[PBEffects::Commander] = [b.index]
      [:ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED].each do |stat|
        next if !b.pbCanRaiseStatStage?(stat, b)
        if b.pbRaiseStatStage(stat, 2, b, showAnim)
          showAnim = false
        end
      end
      battle.pbHideAbilitySplash(battler)
      break
    }
  }
)

PBAI::AbilityEffects::MoveImmunity.add(:COMMANDER,
  proc { |ability, user, target, move, type, battle, show_message|
    next false if !target.isCommander?
    battle.pbDisplay(_INTL("{1} avoided the attack!", target.pbThis)) if show_message
    next true
  }
)

#===============================================================================
# Tablets of Ruin, Sword of Ruin, Vessel of Ruin, Beads of Ruin
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:TABLETSOFRUIN,
  proc { |ability, battler, battle, switch_in|
    case ability
    when :TABLETSOFRUIN then stat_name = GameData::Stat.get(:ATTACK).name
    when :SWORDOFRUIN   then stat_name = GameData::Stat.get(:DEFENSE).name
    when :VESSELOFRUIN  then stat_name = GameData::Stat.get(:SPECIAL_ATTACK).name
    when :BEADSOFRUIN   then stat_name = GameData::Stat.get(:SPECIAL_DEFENSE).name
    end
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("{1}'s {2} weakened the {3} of all surrounding Pokémon!", battler.pbThis, battler.abilityName, stat_name))
    battle.pbHideAbilitySplash(battler)
  }
)

PBAI::AbilityEffects::OnSwitchIn.copy(:TABLETSOFRUIN, :SWORDOFRUIN, :VESSELOFRUIN, :BEADSOFRUIN)

#===============================================================================
# Orichalcum Pulse
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:ORICHALCUMPULSE,
  proc { |ability, battler, battle, switch_in|
    if [:Sun, :HarshSun].include?(battler.battle.pbWeather)
      battle.pbShowAbilitySplash(battler)
      battle.pbDisplay(_INTL("{1} basked in the sunlight, sending its ancient pulse into a frenzy!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    else
      battle.pbStartWeatherAbility(:Sun, battler)
      battle.pbDisplay(_INTL("{1} turned the sunlight harsh, sending its ancient pulse into a frenzy!", battler.pbThis))
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:ORICHALCUMPULSE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 4 / 3.0 if move.physicalMove? && [:Sun, :HarshSun].include?(user.battle.pbWeather)
  }
)

#===============================================================================
# Hadron Engine
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:HADRONENGINE,
  proc { |ability, battler, battle, switch_in|
    battle.pbShowAbilitySplash(battler)
    if battle.field.terrain == :Electric
      battle.pbDisplay(_INTL("{1} used the Electric Terrain to energize its futuristic engine!", battler.pbThis))
      battle.pbHideAbilitySplash(battler)
    else
      battle.pbStartTerrain(battler, :Electric)
      battle.pbDisplay(_INTL("{1} turned the ground into Electric Terrain, energizing its futuristic engine!", battler.pbThis))
    end
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:HADRONENGINE,
  proc { |ability, user, target, move, mults, baseDmg, type|
    mults[:attack_multiplier] *= 4 / 3.0 if move.specialMove? && user.battle.field.terrain == :Electric
  }
)

#===============================================================================
# Protosynthesis, Quark Drive
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:PROTOSYNTHESIS,
  proc { |ability, battler, battle, switch_in|
    case ability
    when :PROTOSYNTHESIS then field_check = [:Sun, :HarshSun].include?(battle.field.weather)
    when :QUARKDRIVE     then field_check = battle.field.terrain == :Electric
    end
    if !field_check && !battler.effects[PBEffects::BoosterEnergy] && battler.effects[PBEffects::ParadoxStat]
      battle.pbDisplay(_INTL("The effects of {1}'s {2} wore off!", battler.pbThis(true), battler.abilityName))
      battler.effects[PBEffects::ParadoxStat] = nil
    end
    next if battler.effects[PBEffects::ParadoxStat]
    next if !field_check && battler.item != :BOOSTERENERGY
    highestStat = nil
    highestStatVal = 0
    stageMul = [2, 2, 2, 2, 2, 2, 2, 3, 4, 5, 6, 7, 8]
    stageDiv = [8, 7, 6, 5, 4, 3, 2, 2, 2, 2, 2, 2, 2]
    battler.plainStats.each do |stat, val|
      stage = battler.stages[stat] + 6
      realStat = (val.to_f * stageMul[stage] / stageDiv[stage]).floor
      if realStat > highestStatVal
        highestStatVal = realStat 
        highestStat = stat
      end
    end
    if highestStat
      battle.pbShowAbilitySplash(battler)
      if field_check
        case ability
        when :PROTOSYNTHESIS then cause = "harsh sunlight"
        when :QUARKDRIVE     then cause = "Electric Terrain"
        end
        battle.pbDisplay(_INTL("The #{cause} activated {1}'s {2}!", battler.pbThis(true), battler.abilityName))
      elsif battler.item == :BOOSTERENERGY
        battler.effects[PBEffects::BoosterEnergy] = true
        battle.pbDisplay(_INTL("{1} used its {2} to activate its {3}!", battler.pbThis, battler.itemName, battler.abilityName))
        battler.pbHeldItemTriggered(battler.item)
      end
      battler.effects[PBEffects::ParadoxStat] = highestStat
      battle.pbDisplay(_INTL("{1}'s {2} was heightened!", battler.pbThis, GameData::Stat.get(highestStat).name))
      battle.pbHideAbilitySplash(battler)
    end
  }
)

PBAI::AbilityEffects::OnSwitchIn.copy(:PROTOSYNTHESIS, :QUARKDRIVE)

PBAI::AbilityEffects::OnTerrainChange.add(:QUARKDRIVE,
  proc { |ability, battler, battle, switch_in|
    PBAI::AbilityEffects.triggerOnSwitchIn(ability, battler, battle, switch_in)
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.add(:PROTOSYNTHESIS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    stat = user.effects[PBEffects::ParadoxStat]
    mults[:attack_multiplier] *= 1.3 if move.physicalMove? && stat == :ATTACK
    mults[:attack_multiplier] *= 1.3 if move.specialMove?  && stat == :SPECIAL_ATTACK
  }
)

PBAI::AbilityEffects::DamageCalcFromUser.copy(:PROTOSYNTHESIS, :QUARKDRIVE)

PBAI::AbilityEffects::DamageCalcFromTarget.add(:PROTOSYNTHESIS,
  proc { |ability, user, target, move, mults, baseDmg, type|
    stat = target.effects[PBEffects::ParadoxStat]
    mults[:defense_multiplier] *= 1.3 if move.physicalMove? && stat == :DEFENSE
    mults[:defense_multiplier] *= 1.3 if move.specialMove?  && stat == :SPECIAL_DEFENSE
  }
)

PBAI::AbilityEffects::DamageCalcFromTarget.copy(:PROTOSYNTHESIS, :QUARKDRIVE)

PBAI::AbilityEffects::SpeedCalc.add(:PROTOSYNTHESIS,
  proc { |ability, battler, mult, ret|
    next mult * 1.5 if battler.effects[PBEffects::ParadoxStat] == :SPEED
  }
)

PBAI::AbilityEffects::SpeedCalc.copy(:PROTOSYNTHESIS, :QUARKDRIVE)

#===============================================================================
# Supersweet Syrup
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:SUPERSWEETSYRUP,
  proc { |ability, battler, battle, switch_in|
    next if battler.ability_triggered?
    battle.pbShowAbilitySplash(battler)
    battle.pbDisplay(_INTL("A supersweet aroma is wafting from the syrup covering {1}!", battler.pbThis))
    battle.allOtherSideBattlers(battler.index).each do |b|
      next if !b.near?(battler) || b.fainted?
      if b.itemActive? && !b.hasActiveAbility?(:CONTRARY) && b.effects[PBEffects::Substitute] == 0
        next if PBAI::ItemEffects.triggerStatLossImmunity(b.item, b, :EVASION, battle, true)
      end
      b.pbLowerStatStageByAbility(:EVASION, 1, battler, false)
    end
    battle.pbHideAbilitySplash(battler)
    battle.pbSetAbilityTrigger(battler)
  }
)

#===============================================================================
# Hospitality
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:HOSPITALITY,
  proc { |ability, battler, battle, switch_in|
    next if battler.allAllies.none? { |b| b.hp < b.totalhp }
    battle.pbShowAbilitySplash(battler)
    battler.allAllies.each do |b|
      next if b.hp == b.totalhp
      amt = (b.totalhp / 4).floor
      b.pbRecoverHP(amt)
      battle.pbDisplay(_INTL("{1} drank down all the matcha that {2} made!", b.pbThis, battler.pbThis(true)))
    end
    battle.pbHideAbilitySplash(battler)
  }
)

#===============================================================================
# Toxic Chain
#===============================================================================
PBAI::AbilityEffects::OnDealingHit.add(:TOXICCHAIN,
  proc { |ability, user, target, move, battle|
    next if battle.pbRandom(100) >= 30
    next if target.hasActiveItem?(:COVERTCLOAK)
    battle.pbShowAbilitySplash(user)
    if target.hasActiveAbility?(:SHIELDDUST) && !battle.moldBreaker
      battle.pbShowAbilitySplash(target)
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        battle.pbDisplay(_INTL("{1} is unaffected!", target.pbThis))
      end
      battle.pbHideAbilitySplash(target)
    elsif target.pbCanPoison?(user, PokeBattle_SceneConstants::USE_ABILITY_SPLASH)
      msg = nil
      if !PokeBattle_SceneConstants::USE_ABILITY_SPLASH
        msg = _INTL("{1} was badly poisoned!", target.pbThis)
      end
      target.pbPoison(user, msg, true)
    end
    battle.pbHideAbilitySplash(user)
  }
)

#===============================================================================
# Mind's Eye
#===============================================================================
PBAI::AbilityEffects::StatLossImmunity.copy(:KEENEYE, :MINDSEYE)
PBAI::AbilityEffects::AccuracyCalcFromUser.copy(:KEENEYE, :MINDSEYE)

#===============================================================================
# Embody Aspect
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:EMBODYASPECT,
  proc { |ability, battler, battle, switch_in|
    next if !battler.isSpecies?(:OGERPON)
    #next if battler.effects[PBEffects::OneUseAbility] == ability
    mask = GameData::Species.get(:OGERPON).form_name
    battle.pbDisplay(_INTL("The {1} worn by {2} shone brilliantly!", mask, battler.pbThis(true)))
    battler.pbRaiseStatStageByAbility(:SPEED, 1, battler)
    #battler.effects[PBEffects::OneUseAbility] = ability
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:EMBODYASPECT_1,
  proc { |ability, battler, battle, switch_in|
    next if !battler.isSpecies?(:OGERPON)
    #next if battler.effects[PBEffects::OneUseAbility] == ability
    mask = GameData::Species.get(:OGERPON_1).form_name
    battle.pbDisplay(_INTL("The {1} worn by {2} shone brilliantly!", mask, battler.pbThis(true)))
    battler.pbRaiseStatStageByAbility(:SPECIAL_DEFENSE, 1, battler)
    #battler.effects[PBEffects::OneUseAbility] = ability
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:EMBODYASPECT_2,
  proc { |ability, battler, battle, switch_in|
    next if !battler.isSpecies?(:OGERPON)
    #next if battler.effects[PBEffects::OneUseAbility] == ability
    mask = GameData::Species.get(:OGERPON_2).form_name
    battle.pbDisplay(_INTL("The {1} worn by {2} shone brilliantly!", mask, battler.pbThis(true)))
    battler.pbRaiseStatStageByAbility(:ATTACK, 1, battler)
    #battler.effects[PBEffects::OneUseAbility] = ability
  }
)

PBAI::AbilityEffects::OnSwitchIn.add(:EMBODYASPECT_3,
  proc { |ability, battler, battle, switch_in|
    next if !battler.isSpecies?(:OGERPON)
    #next if battler.effects[PBEffects::OneUseAbility] == ability
    mask = GameData::Species.get(:OGERPON_3).form_name
    battle.pbDisplay(_INTL("The {1} worn by {2} shone brilliantly!", mask, battler.pbThis(true)))
    battler.pbRaiseStatStageByAbility(:DEFENSE, 1, battler)
    #battler.effects[PBEffects::OneUseAbility] = ability
  }
)


############################# Indigo Disk DLC ##################################

#===============================================================================
# Tera Shell
#===============================================================================
PBAI::AbilityEffects::ModifyTypeEffectiveness.add(:TERASHELL,
  proc { |ability, user, target, move, battle, effectiveness|
    next if !move.damagingMove?
    next if target.hasMoldBreaker?
    next if target.hp < target.totalhp
    next if effectiveness < Effectiveness::NORMAL_EFFECTIVE
    Effectiveness::NOT_VERY_EFFECTIVE_ONE
  }
)

PBAI::AbilityEffects::OnMoveSuccessCheck.add(:TERASHELL,
  proc { |ability, user, target, move, battle|
    next
  }
)

#===============================================================================
# Teraform Zero
#===============================================================================
PBAI::AbilityEffects::OnSwitchIn.add(:TERAFORMZERO,
  proc { |ability, battler, battle, switch_in|
    weather = battle.field.weather
    terrain = battle.field.terrain
    next if weather == :None && terrain == :None
    showSplash = false
    if weather != :None
      showSplash = true
      battle.pbShowAbilitySplash(battler)
      battle.field.weather = :None
      battle.field.weatherDuration = 0
      case weather
      when :Sun         then battle.pbDisplay(_INTL("The sunlight faded."))
      when :Rain        then battle.pbDisplay(_INTL("The rain stopped."))
      when :Sandstorm   then battle.pbDisplay(_INTL("The sandstorm subsided."))
      when :Hail
        case Settings::HAIL_WEATHER_TYPE
        when 0 then battle.pbDisplay(_INTL("The hail stopped."))
        when 1 then battle.pbDisplay(_INTL("The snow stopped."))
        when 2 then battle.pbDisplay(_INTL("The hailstorm ended."))
        end
      when :HarshSun    then battle.pbDisplay(_INTL("The harsh sunlight faded!"))
      when :HeavyRain   then battle.pbDisplay(_INTL("The heavy rain has lifted!"))
      when :StrongWinds then battle.pbDisplay(_INTL("The mysterious air current has dissipated!"))
      else
        battle.pbDisplay(_INTL("The weather returned to normal."))
      end
    end
    if terrain != :None
      battle.pbShowAbilitySplash(battler) if !showSplash
      battle.field.terrain = :None
      battle.field.terrainDuration = 0
      case terrain
      when :Electric then battle.pbDisplay(_INTL("The electric current disappeared from the battlefield!"))
      when :Grassy   then battle.pbDisplay(_INTL("The grass disappeared from the battlefield!"))
      when :Psychic  then battle.pbDisplay(_INTL("The mist disappeared from the battlefield!"))
      when :Misty    then battle.pbDisplay(_INTL("The weirdness disappeared from the battlefield!"))
      else
        battle.pbDisplay(_INTL("The battlefield returned to normal."))
      end
    end
    next if !showSplash
    battle.pbHideAbilitySplash(battler)
    battle.allBattlers.each { |b| b.pbCheckFormOnWeatherChange }
    battle.allBattlers.each { |b| b.pbAbilityOnTerrainChange }
    battle.allBattlers.each { |b| b.pbItemTerrainStatBoostCheck }
  }
)

#===============================================================================
# Poison Puppeteer
#===============================================================================
PBAI::AbilityEffects::OnInflictingStatus.add(:POISONPUPPETEER,
  proc { |ability, user, battler, status|
    next if !user || user.index == battler.index
    next if status != :POISON
    next if battler.effects[PBEffects::Confusion] > 0
    user.battle.pbShowAbilitySplash(user)
    battler.pbConfuse if battler.pbCanConfuse?(user, false, nil)
    user.battle.pbHideAbilitySplash(user)
  }
)