# Optional competitive battle rules for Realidea.
#
# Create Data/challenge_rules.txt to:
#   - remove all opponent trainer bag items,
#   - force Set battle style, and
#   - block the player's Bag in trainer battles.
# Pokemon held items are not changed.  The Bag remains available in wild
# battles so that the player can catch Pokemon.

REALIDEA_CHALLENGE_RULES_FILE = "Data/challenge_rules.txt"

module RealideaChallengeRules
  def self.enabled?
    return File.exist?(REALIDEA_CHALLENGE_RULES_FILE)
  rescue
    return false
  end
end

class PokemonSystem
  alias realidea_challenge_rules_battlestyle battlestyle
  alias realidea_challenge_rules_battlestyle_set battlestyle=

  def battlestyle
    return 1 if RealideaChallengeRules.enabled?
    return realidea_challenge_rules_battlestyle
  end

  def battlestyle=(value)
    value = 1 if RealideaChallengeRules.enabled?
    return realidea_challenge_rules_battlestyle_set(value)
  end
end

alias realidea_challenge_rules_prepare_battle pbPrepareBattle
def pbPrepareBattle(battle)
  result = realidea_challenge_rules_prepare_battle(battle)
  battle.shiftStyle = false if RealideaChallengeRules.enabled?
  return result
end

class PokeBattle_Battle
  alias realidea_challenge_rules_items_set items=
  alias realidea_challenge_rules_item_menu pbItemMenu

  def items=(items)
    items = [] if RealideaChallengeRules.enabled? && @opponent
    return realidea_challenge_rules_items_set(items)
  end

  def pbItemMenu(index)
    if RealideaChallengeRules.enabled? && @opponent
      pbDisplay(_INTL("Items cannot be used in Trainer battles."))
      return [0, -1]
    end
    return realidea_challenge_rules_item_menu(index)
  end
end
