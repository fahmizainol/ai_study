# Level_Scaling — trainer parties track the player's level.
#
# Create Data/level_scaling.txt to enable. The file may hold a single integer
# which overrides LEASH (default 6); empty or unparseable means the default.
# LEASH is how far ABOVE its designed level a fight may rise.
# See _AI-Study/LEVEL-SCALING.md for the derivation and the proof table.
#
#   A        = pbBalancedLevel($Trainer.party) - 1  # == balanceo
#   ace      = the fight's highest designed level, ignoring scripted outliers
#   scaled_i = clamp(A + (L_i - ace),  L_i,  L_i + LEASH)
#
# PRESSURE ONLY. `A + (L_i - ace)` preserves the team's internal spread; the L_i
# floor means a fight is never weaker than the developer designed it, and the
# L_i + LEASH ceiling bounds how far it may rise. An under-levelled player gets no
# relief - that is the point of this configuration, not an oversight.
#
# The ceiling is what stops the game collapsing to one level: without it every
# fight's ace lands on A, so a route-1 pair and the champion present identically.
# Measured: 89% of fights sit within 6 of their stage cap, so in forward play the
# ceiling almost never binds and a bounded rise reaches essentially everything.
#
# Of the developer's 25 hand-scaled fights, those written `balanceo` and
# `balanceo+1` are unchanged; those written `balanceo-2` rise by 2 onto the anchor,
# because a team pinned 2 below the anchor is indistinguishable at runtime from a
# fixed team designed 2 below its ace.
#
# OUTLIERS. A Pokemon more than 2*LEASH above its own team's median is a scripted
# gimmick, not the fight's difficulty: it neither sets the anchor nor moves. Two
# fights in the game need this (maps 164 and 198, the same pinned mon the engine
# already special-cases in createPokemon and pbGainExpOne); without the guard its
# level hijacks the anchor and drags its five teammates down by the full leash.
# Measured across both corpora the gap is bimodal - every other fight sits at 7 or
# below, these two at 37+ - so the cut point is not a tuned number.
#
# This section must load AFTER Team_Overrides so its aliases wrap it: the
# override supplies the designed levels, and this clamps them.

REALIDEA_LEVEL_SCALING_FILE = "Data/level_scaling.txt"

module RealideaLevelScaling
  DEFAULT_LEASH = 6

  def self.enabled?
    return File.exist?(REALIDEA_LEVEL_SCALING_FILE)
  rescue
    return false
  end

  def self.leash
    body = File.open(REALIDEA_LEVEL_SCALING_FILE, "rb") { |file| file.read }.to_s.strip
    return DEFAULT_LEASH if body.length == 0
    value = body.to_i
    return DEFAULT_LEASH if value <= 0
    return value
  rescue
    return DEFAULT_LEASH
  end

  # pbRegisterPartner builds the player's ALLY through pbLoadTrainer. Scaling it
  # down would weaken the player exactly when they are already behind.
  def self.suspended?
    return @suspended ? true : false
  end

  def self.suspended=(value)
    @suspended = value
  end

  def self.anchor
    return nil if !$Trainer
    party = $Trainer.party
    return nil if !party || party.length == 0
    return pbBalancedLevel(party) - 1   # == balanceo
  end

  # Levels above this are scripted outliers: excluded from the anchor and left
  # untouched. Lower median on an even count - deterministic and integer.
  def self.outlier_ceiling(party, lsh)
    levels = []
    for pkmn in party
      levels.push(pkmn.level) if !pkmn.nil?
    end
    return 0 if levels.length == 0
    levels = levels.sort
    return levels[(levels.length - 1) / 2] + (2 * lsh)
  end

  # Re-levels `party` in place. Any failure leaves it untouched.
  def self.apply(party)
    return if !enabled? || suspended?
    return if !party || party.length == 0
    a = anchor
    return if !a
    lsh = leash
    ceiling = outlier_ceiling(party, lsh)
    ace = nil
    for pkmn in party
      next if pkmn.nil? || pkmn.level > ceiling
      ace = pkmn.level if ace.nil? || pkmn.level > ace
    end
    return if ace.nil?
    for pkmn in party
      next if pkmn.nil? || pkmn.level > ceiling
      old = pkmn.level
      new = a + (old - ace)
      new = old if new < old                  # floor: never weaker than designed
      new = old + lsh if new > old + lsh      # ceiling: a bounded rise
      new = 1 if new < 1
      new = PBExperience::MAXLEVEL if new > PBExperience::MAXLEVEL
      next if new == old
      pkmn.level = new    # moves @exp only
      pkmn.calcStats      # stats are stale without this; it clamps @hp itself
    end
  rescue
    # a scaling failure must never cost the player a fight
  end
end

# Path 1: inline createTrainer fights (the 178 map-event battles, plus the
# battle facility and the mirror fight). Returns [opponent, items, party], and
# opponent.party is the same array object, so re-levelling in place covers both.
alias level_scaling_orig_createTrainer createTrainer
def createTrainer(trainerid, trainername, party, items=[])
  result = level_scaling_orig_createTrainer(trainerid, trainername, party, items)
  RealideaLevelScaling.apply(result[2]) if result
  return result
end

# Path 2: pbTrainerBattle / .dat fights. pbLoadTrainer returns
# [opponent, items, party] or nil, and never assigns opponent.party — the battle
# reads index 2, so that is the array to re-level.
alias level_scaling_orig_pbLoadTrainer pbLoadTrainer
def pbLoadTrainer(trainerid, trainername, partyid=0)
  result = level_scaling_orig_pbLoadTrainer(trainerid, trainername, partyid)
  RealideaLevelScaling.apply(result[2]) if result
  return result
end

# The player's ally is loaded through pbLoadTrainer too. Suspend across it.
alias level_scaling_orig_pbRegisterPartner pbRegisterPartner
def pbRegisterPartner(trainerid, trainername, partyid=0)
  RealideaLevelScaling.suspended = true
  return level_scaling_orig_pbRegisterPartner(trainerid, trainername, partyid)
ensure
  RealideaLevelScaling.suspended = false
end
