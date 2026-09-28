# Level_Cap — Pokemon Unbound-style soft EXP caps for Realidea.
#
# The selected curve supplies one cap for each of Realidea's nine current
# pre-final progression stages (badge counts 0..8). Data/level_cap_mode.txt may
# contain "vanilla", "expert" or "rnb"; expert is the default.
# See generated/realidea_level_curve.json for the source table transcription.
#
#   rnb  Run & Bun's caps taken one-to-one: gym N gets the cap Run & Bun had for
#        its gym N, the ninth fight (8 badges) gets Victory Road Vito's 95 and the
#        Champion Wallace's 99. See _AI-Study/PLAYER-CURVE.md.
#
# A Pokemon already at or above the cap receives exactly 1 EXP from each normal
# battle EXP award. EV gain is unaffected. After the Champion event completes,
# the cap becomes 100. This replaces the previous disobedience-based patch.
#
# CATCH-UP EXP. Below the cap, battle EXP is multiplied by
#     1 + 0.25 * (levels below the cap - 1), at most 4
# so one level short gets x1, five short x2, thirteen short x4. A gift or a fresh
# catch reaches the team quickly while a Pokemon already near the cap is untouched,
# and a boosted award never carries past the cap: it stops at the cap's first EXP
# point. Data/exp_multiplier.txt overrides it: "off" (or 1) disables it, any other
# number is a flat multiplier. Like the cap itself, it touches battle EXP only.
#
# LADDERS. remap() moves a level between curves at the same story point, piecewise
# linearly through the nine leader stages and the Champion. "original" is the
# levels the game's own events are written at (the nine leaders' aces and the
# Champion's), the x-axis of generate_bosses.remap(); the other ladders are each
# mode's caps. Level_Scaling uses it to put fights built for one curve on another.

module RealideaLevelCap
  CAPS_BY_MODE = {
    "vanilla" => [15, 22, 29, 33, 37, 43, 51, 55, 60],
    "expert"  => [20, 26, 32, 36, 40, 45, 52, 57, 61],
    "rnb"     => [21, 25, 35, 42, 57, 69, 85, 91, 95]
  }
  CHAMPION_CAP_BY_MODE = { "vanilla" => 66, "expert" => 75, "rnb" => 99 }
  ORIGINAL_LADDER = [0, 14, 20, 26, 33, 38, 40, 45, 48, 51, 66]
  DEFAULT_MODE = "expert"
  MODE_FILE = "Data/level_cap_mode.txt"
  EXP_FILE = "Data/exp_multiplier.txt"
  ORIGINAL_TEAMS_FILE = "Data/original_teams.txt"
  CHAMPION_STAGE_FILE = "Data/champion_level_cap.txt"
  CHAMPION_SELF_SWITCH = [156, 14, "A"]
  CATCH_UP_STEP = 0.25
  CATCH_UP_MAX = 4.0

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

  def self.edited_teams?
    return !File.exist?(ORIGINAL_TEAMS_FILE)
  rescue
    return true
  end

  def self.current
    return 100 if champion_defeated?
    return 100 if !edited_teams?
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

  def self.ladder(name)
    return ORIGINAL_LADDER if name == "original"
    return nil if !CAPS_BY_MODE.has_key?(name)
    return [0] + CAPS_BY_MODE[name] + [CHAMPION_CAP_BY_MODE[name]]
  end

  # `level` on ladder `from` -> the level at the same story point on ladder `to`.
  # Past the top anchor the offset is carried over unchanged. Unknown ladders and
  # equal ladders return the level as given.
  def self.remap(level, from, to)
    return level if from == to
    xs = ladder(from)
    ys = ladder(to)
    return level if !xs || !ys
    top = xs.length - 1
    if level >= xs[top]
      out = level - xs[top] + ys[top]
    else
      out = level
      for i in 0...top
        next if level < xs[i] || level > xs[i + 1]
        span = xs[i + 1] - xs[i]
        frac = span == 0 ? 0.0 : (level - xs[i]).to_f / span
        out = (ys[i] + frac * (ys[i + 1] - ys[i]) + 0.5).floor
        break
      end
    end
    out = 1 if out < 1
    out = 100 if out > 100
    return out
  rescue
    return level
  end

  # nil = no multiplier file (catch-up applies); 1.0 = off; otherwise flat.
  def self.flat_multiplier
    return nil if !File.exist?(EXP_FILE)
    body = File.open(EXP_FILE, "rb") { |file| file.read }.to_s.strip.downcase
    return 1.0 if body == "off" || body == ""
    value = body.to_f
    return 1.0 if value <= 0
    return value
  rescue
    return nil
  end

  def self.exp_multiplier(level, cap)
    flat = flat_multiplier
    return flat if flat
    gap = cap - level
    return 1.0 if gap <= 1
    mult = 1.0 + CATCH_UP_STEP * (gap - 1)
    mult = CATCH_UP_MAX if mult > CATCH_UP_MAX
    return mult
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
      if pokemon && pokemon.exp == currexp
        cap = RealideaLevelCap.current
        if pokemon.level >= cap
          expgain = 1
        else
          mult = RealideaLevelCap.exp_multiplier(pokemon.level, cap)
          if mult != 1.0
            base = expgain
            expgain = (expgain * mult).floor
            # the boost stops at the cap instead of carrying past it -- but never
            # below the unboosted award, which may itself cross the cap as before
            begin
              limit = PBExperience.pbGetStartExperience(cap, growth)
              expgain = limit - currexp if currexp + expgain > limit
              expgain = base if expgain < base
            rescue
            end
          end
        end
      end
      return realidea_level_cap_add_experience(currexp, expgain, growth)
    end
  end
end
