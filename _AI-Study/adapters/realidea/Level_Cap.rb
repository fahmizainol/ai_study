# Level_Cap — Pokemon Unbound-style soft EXP caps for Realidea.
#
# The selected curve supplies one cap for each of Realidea's nine current
# pre-final progression stages (badge counts 0..8). Data/level_cap_mode.txt may
# contain "vanilla" or "expert"; expert is the default.
# See generated/realidea_level_curve.json for the source table transcription.
#
# A Pokemon already at or above the cap receives exactly 1 EXP from each normal
# battle EXP award. EV gain is unaffected. After the Champion event completes,
# the cap becomes 100. This replaces the previous disobedience-based patch.

module RealideaLevelCap
  CAPS_BY_MODE = {
    "vanilla" => [15, 22, 29, 33, 37, 43, 51, 55, 60],
    "expert"  => [20, 26, 32, 36, 40, 45, 52, 57, 61]
  }
  CHAMPION_CAP_BY_MODE = { "vanilla" => 66, "expert" => 75 }
  DEFAULT_MODE = "expert"
  MODE_FILE = "Data/level_cap_mode.txt"
  CHAMPION_STAGE_FILE = "Data/champion_level_cap.txt"
  CHAMPION_SELF_SWITCH = [156, 14, "A"]

  def self.mode
    if File.exist?(MODE_FILE)
      selected = File.open(MODE_FILE, "rb") { |file| file.read }.to_s.strip.downcase
      return selected if CAPS_BY_MODE.has_key?(selected)
    end
    return DEFAULT_MODE
  rescue
    return DEFAULT_MODE
  end

  def self.caps
    return CAPS_BY_MODE[mode]
  end

  def self.champion_stage?
    return File.exist?(CHAMPION_STAGE_FILE)
  rescue
    return false
  end

  def self.champion_defeated?
    return false if !$game_self_switches
    return $game_self_switches[CHAMPION_SELF_SWITCH] == true
  rescue
    return false
  end

  def self.current
    return 100 if champion_defeated?
    badges = 0
    badges = $Trainer.numbadges if $Trainer && $Trainer.respond_to?("numbadges")
    badges = 0 if badges < 0
    if badges >= 8 && champion_stage?
      return CHAMPION_CAP_BY_MODE[mode]
    end
    active_caps = caps
    badges = active_caps.length - 1 if badges >= active_caps.length
    return active_caps[badges]
  rescue
    return CAPS_BY_MODE[DEFAULT_MODE][0]
  end

  def self.exp_pokemon
    return @exp_pokemon
  end

  def self.exp_pokemon=(pokemon)
    @exp_pokemon = pokemon
  end
end

# pbGainExpOne performs EV gain and all experience modifiers before calling
# PBExperience.pbAddExperience. Carry the recipient through that call so the
# cap changes only battle EXP, without affecting Rare Candies, daycare, or event
# scripts that also use PBExperience.
class PokeBattle_Battle
  alias realidea_level_cap_gain_exp_one pbGainExpOne

  def pbGainExpOne(index, defeated, partic, expshare, haveexpall, showmessages=true)
    RealideaLevelCap.exp_pokemon = @party1[index]
    return realidea_level_cap_gain_exp_one(index, defeated, partic, expshare,
                                            haveexpall, showmessages)
  ensure
    RealideaLevelCap.exp_pokemon = nil
  end
end

module PBExperience
  class << self
    alias realidea_level_cap_add_experience pbAddExperience

    def pbAddExperience(currexp, expgain, growth)
      pokemon = RealideaLevelCap.exp_pokemon
      if pokemon && pokemon.exp == currexp && pokemon.level >= RealideaLevelCap.current
        expgain = 1
      end
      return realidea_level_cap_add_experience(currexp, expgain, growth)
    end
  end
end
