#===============================================================================
# * Difficulty Modes - by FL (Credits will be apreciated)
#===============================================================================
#
# This script is for Pokémon Essentials. It allows a easy way to make difficulty
# modes like the ones on Key System in B2W2.
#
# A difficulty mode may change:
# - Wild Pokémon levels
# - Trainer's Pokémon levels
# - Trainer's skill level
# - Trainer's money given
# - Trainer definition (define a different trainer entry in trainers.txt)
# - Exp received
#
#== INSTALLATION ===============================================================
#
# To this script works, put it above main OR convert into a plugin.
#
#=== HOW TO USE ================================================================
#
# Change the variable number in "VARIABLE" to variable index used to keep the 
# difficulty mode index.
#
# There are already three difficulties defined: Example Mode, Easy Mode and Hard
# Mode. You can define more on 'def self.current_mode', see the instruction on
# this method.
#
#=== EXAMPLES ==================================================================
#
# The below example creates an easy mode who loads another party if defined and
# nothing more. We will choose 50 as the ID jump, so, instead of
# [TEAMROCKET_M,Grunt,1] team being load, the [TEAMROCKET_M,Grunt,51] will be
# load instead, if it exists. After line '# Add new modes HERE' add: 
#
#  my_easy_mode = Difficulty.new
#  my_easy_mode.id_jump = 50
#  difficulty_hash[4] = my_easy_mode
#
# And set game variable 90 value to 4 (I suggest to do this by events).
#
#===============================================================================

if !PluginManager.installed?("Difficulty Modes")
  PluginManager.register({                                                 
    :name    => "Difficulty Modes",                                        
    :version => "1.1.1",                                                     
    :link    => "https://www.pokecommunity.com/showthread.php?t=300975",             
    :credits => "FL"
  })
end

module DifficultyModes

  # Number of variable who controls the difficulty.
  # To use a different variable, change this. 1 deactivates this script.
  VARIABLE = 400
  
  def self.current_mode
    return nil if DifficultyModes::VARIABLE < 0 || DifficultyModes::VARIABLE == 1
    difficulty_hash={}
    

    hard_mode = Difficulty.new
    # Michael note - Added easy mode
    easy_mode = Difficulty.new

    # A formula to change all wild pokémon levels. 
    # IN THIS EXAMPLE: Every wild pokémon have the level*1.2 (round down). 
    # A pokémon level 21 will be level 25.
   # example_mode.wild_level_proc = proc{|pokemon|
   #   next pokemon.level*1.2
   # }
    
    # A formula to change all trainers pokémon levels. 
    # This affects money earned in battle.
    # IN THIS EXAMPLE: Every opponent pokémon have the level*0.9 (round down). 
    # A pokémon level 19 will be level 16.
    hard_mode.trainer_level_proc = proc{|pokemon, trainer|
      next pokemon.level * 1.1
    }
    
    # A formula to change all trainers skill level.
    # IN THIS EXAMPLE: All trainers always have a low skill level (1).
  #  example_mode.skill_proc = proc{|skill_level,trainer|
  #   next 1
  #  }
    
    # A formula to change all trainers base money.
    # IN THIS EXAMPLE: Multiplier the money given by the opponent by 1.3 (round
    # down), so if the base money earned is 99, this is changed to be 128.
=begin
    hard_mode.money_proc = proc{|money, trainer|
      next money * 0.7
    }

    easy_mode.money_proc = proc{|money, trainer|
      next money * 1.3
    }
    
    # A formula to change exp gained.
    # IN THIS EXAMPLE: Multiplier exp received by 1.2.
    # hard_mode.exp_proc = proc{|exp, receiver_battler|
    #  next exp * 0.9
    #}
=end
    # party id number for trainer than can have other party.
    # Trainers loaded this way ignores the trainer_level_proc.
    # IN THIS EXAMPLE: If you start a battle versus YOUNGSTER Ben team 1,
    # the game searches for the YOUNGSTER Ben team 101 (100+1),
    # if the game founds it loads instead of the team 1. If there is no 101, 
    # Ben team 1 will be loaded. 
    hard_mode.id_jump = 100
    easy_mode.id_jump = 200

    # The Hash index is the value than when are in the VARIABLE number value,
    # the difficulty will be ON.
    # IN THIS EXAMPLE: Only when variable 90 value is 1 that this mode will
    # be ON.
    difficulty_hash[2] = hard_mode
    difficulty_hash[0] = easy_mode
    
    # Add new modes HERE

    return difficulty_hash[pbGet(DifficultyModes::VARIABLE)]
  end 
  
  def self.apply_wild_level_proc(pokemon)
    return pokemon.level if !current_mode || !current_mode.wild_level_proc
    return  [[
      current_mode.wild_level_proc.call(pokemon).floor,
      GameData::GrowthRate.max_level
    ].min,1].max
  end
  
  def self.apply_trainer_level_proc(pokemon,trainer)
    return pokemon.level if !current_mode || !current_mode.trainer_level_proc || (trainer.name == "Hart" && pokemon.isSpecies?(:MAGIKARP)) || 
    (trainer.name == "Sean" && pokemon.isSpecies?(:PROBOPASS)) || $game_switches[420]
    return  [[
      current_mode.trainer_level_proc.call(pokemon,trainer).floor,
      GameData::GrowthRate.max_level
    ].min,1].max
  end
  
  def self.apply_skill_proc(skill,trainer)
    return skill if !current_mode || !current_mode.skill_proc
    return [current_mode.skill_proc.call(skill,trainer).floor,0].max
  end
  
  def self.apply_money_proc(money,trainer)
    return money if !current_mode || !current_mode.money_proc
    return [current_mode.money_proc.call(money,trainer).floor,0].max
  end
  
  def self.apply_exp_proc(exp,receiver_battler)
    return exp if !current_mode || !current_mode.exp_proc
    return [current_mode.exp_proc.call(exp,receiver_battler).floor,0].max
  end
    
  private
  class Difficulty
    attr_accessor :wild_level_proc
    attr_accessor :trainer_level_proc
    attr_accessor :skill_proc
    attr_accessor :money_proc
    attr_accessor :exp_proc
    attr_accessor :id_jump
    
    def initialize
      @id_jump = 0
    end  
  end  
end

alias :_pbLoadTrainer_FL_dif :pbLoadTrainer
def pbLoadTrainer(tr_type, tr_name, tr_id = 0)
  if tr_id.nil?
    tr_id = 0
  end
  if DifficultyModes.current_mode && DifficultyModes.current_mode.id_jump != 0
    ret = _pbLoadTrainer_FL_dif(
      tr_type, tr_name, DifficultyModes.current_mode.id_jump + tr_id
    )
  end
  if !ret
    ret = _pbLoadTrainer_FL_dif(tr_type, tr_name, tr_id)
    return ret if !ret 
    if DifficultyModes.current_mode
      for pkmn in ret.party
        pkmn.level = DifficultyModes.apply_trainer_level_proc(pkmn,self)
        pkmn.calc_stats
      end
    end
  end
  return ret
end

class Trainer
  alias :_base_money_FL_dif :base_money
  def base_money
    return DifficultyModes.apply_money_proc(_base_money_FL_dif,self)
  end

  alias :_skill_level_FL_dif :skill_level
  def skill_level
    return DifficultyModes.apply_skill_proc(_skill_level_FL_dif,self)
  end
end

class Battle
  module ItemEffects
    class << self
      # Essentials v19- compatibility
      def triggerExpGainModifier(item,battler,exp)
        BattleHandlers.triggerExpGainModifierItem(item,battler,exp)
      end unless method_defined?(:triggerExpGainModifier)

      alias :_triggerExpGainModifier_FL_dif :triggerExpGainModifier
      def triggerExpGainModifierItem(item,battler,exp)
        ret = _triggerExpGainModifier_FL_dif(item,battler,exp)
        if DifficultyModes.current_mode
          ret = DifficultyModes.apply_exp_proc(ret>0 ? ret : exp,battler)
        end
        return ret
      end
    end
  end
end

# Essentials v19- compatibility
if defined?(Events) && Events.respond_to?(:onWildPokemonCreate) 
  Events.onWildPokemonCreate+=proc {|sender,e|
    pkmn = e[0]
    pkmn.level = DifficultyModes.apply_wild_level_proc(pkmn)
    pkmn.calc_stats
  }
else
  EventHandlers.add(:on_wild_pokemon_created, :difficulty_mode,
    proc { |pkmn|
      pkmn.level = DifficultyModes.apply_wild_level_proc(pkmn)
      pkmn.calc_stats
    }
  )
end