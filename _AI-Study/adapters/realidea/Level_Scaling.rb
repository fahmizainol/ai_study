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
# CURVE REMAP. Before the anchor is applied, every designed level L_i is moved to
# the active cap curve at the same story point (RealideaLevelCap.remap), so L_i in
# the formula above is the level the fight WOULD have been written at for that
# curve. Without it a route trainer written at 45 could only reach 51 under the
# rnb curve's 73 cap. Where a fight's levels come from decides the source ladder:
#   the event's own party, and filler overrides that keep it   -> "original"
#   a generated override (its ace differs from the event's)    -> TEAM_OVERRIDES_CURVE
#                                                                 ("expert" if absent)
#   any fight whose levels were written with `balanceo`        -> not remapped; it
#                                                                 already tracks the party
# `balanceo` is detected by hooking it: a call marks the next trainer built. The
# mark is used up by that trainer, and cleared after a wild battle or a gift (the
# other things written with `balanceo`) and at the start of every map-scene update,
# so it cannot outlive the event step that set it. Graphics.frame_count is NOT
# used: measured in-engine it does not advance under a frozen screen. The two
# pinned-outlier fights above call it through createPokemon too, so they keep
# their designed levels (the anchor still lifts them) -- the same two the outlier
# guard exists for.
#
# WILD LEVELS. Data/wild_scaling.txt moves random encounters (walking, surfing,
# fishing: PokemonEncounters#pbEncounteredPokemon) through the same remap from
# "original". Scripted wild battles pass their level straight to pbWildBattle and
# are not touched; the legendaries among them are written `balanceo` already.
#
# This section must load AFTER Team_Overrides so its aliases wrap it: the
# override supplies the designed levels, and this clamps them.

REALIDEA_LEVEL_SCALING_FILE = "Data/level_scaling.txt"
REALIDEA_WILD_SCALING_FILE = "Data/wild_scaling.txt"

module RealideaLevelScaling
  DEFAULT_LEASH = 6
  DEFAULT_OVERRIDE_CURVE = "expert"

  def self.enabled?
    return File.exist?(REALIDEA_LEVEL_SCALING_FILE)
  rescue
    return false
  end

  def self.wild_enabled?
    return File.exist?(REALIDEA_WILD_SCALING_FILE)
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

  # --- where a fight's levels came from --------------------------------------
  def self.override_built?
    return @override_built ? true : false
  end

  def self.override_built=(value)
    @override_built = value
  end

  def self.note_balanceo
    @balanceo_seen = true
  end

  def self.balanceo_seen?
    return @balanceo_seen ? true : false
  end

  def self.clear_balanceo
    @balanceo_seen = false
  end

  # The ladder the active cap mode stands on, or nil when nothing should move:
  # no Level_Cap section, or the original rosters (uncapped vanilla play).
  def self.target_curve
    return nil if !defined?(RealideaLevelCap)
    return nil if !RealideaLevelCap.edited_teams?
    return RealideaLevelCap.mode
  rescue
    return nil
  end

  def self.override_curve
    return TEAM_OVERRIDES_CURVE if defined?(TEAM_OVERRIDES_CURVE)
    return DEFAULT_OVERRIDE_CURVE
  end

  def self.max_level(party)
    ace = nil
    return nil if !party
    for pkmn in party
      next if pkmn.nil?
      ace = pkmn.level if ace.nil? || pkmn.level > ace
    end
    return ace
  end

  def self.remap_level(level, source)
    target = target_curve
    return level if source.nil? || target.nil?
    return RealideaLevelCap.remap(level, source, target)
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

  # Re-levels `party` in place: onto the active curve from `source` (nil = leave
  # the designed levels), then up toward the anchor. Any failure leaves the
  # party as the remap left it -- never weaker than designed.
  def self.apply(party, source=nil)
    return if !enabled? || suspended?
    return if !party || party.length == 0
    lsh = leash
    # outliers are judged on the DESIGNED levels, before anything moves
    ceiling = outlier_ceiling(party, lsh)
    members = []
    for pkmn in party
      members.push(pkmn) if !pkmn.nil? && pkmn.level <= ceiling
    end
    return if members.length == 0
    moved = []
    if !source.nil?
      for pkmn in members
        new = remap_level(pkmn.level, source)
        next if new == pkmn.level
        pkmn.level = new    # moves @exp only
        moved.push(pkmn)
      end
    end
    a = anchor
    if a
      ace = nil
      for pkmn in members
        ace = pkmn.level if ace.nil? || pkmn.level > ace
      end
      for pkmn in members
        old = pkmn.level
        new = a + (old - ace)
        new = old if new < old                  # floor: never weaker than designed
        new = old + lsh if new > old + lsh      # ceiling: a bounded rise
        new = 1 if new < 1
        new = PBExperience::MAXLEVEL if new > PBExperience::MAXLEVEL
        next if new == old
        pkmn.level = new
        moved.push(pkmn) if !moved.include?(pkmn)
      end
    end
    for pkmn in moved
      pkmn.calcStats      # stats are stale without this; it clamps @hp itself
    end
  rescue
    # a scaling failure must never cost the player a fight
  end

  # Source ladder for an inline createTrainer fight. `event_ace` is the ace of the
  # party the event passed in, before any override swapped it.
  def self.inline_source(event_ace, party)
    return nil if balanceo_seen?
    return "original" if !override_built?
    return "original" if max_level(party) == event_ace   # filler: levels kept
    return override_curve
  end

  # Random encounters: [species, level] from the encounter table.
  def self.wild(encounter)
    return encounter if !wild_enabled? || !encounter
    level = remap_level(encounter[1], "original")
    return encounter if level == encounter[1]
    return [encounter[0], level] + encounter[2..-1].to_a
  rescue
    return encounter
  end
end

# `balanceo` levels track the party already; remember when one was just taken.
if defined?(balanceo)
  alias level_scaling_orig_balanceo balanceo
  def balanceo
    RealideaLevelScaling.note_balanceo
    return level_scaling_orig_balanceo
  end
end

# A generated override replaced the event's party.
if defined?(team_override_build)
  alias level_scaling_orig_team_override_build team_override_build
  def team_override_build(spec)
    RealideaLevelScaling.override_built = true
    return level_scaling_orig_team_override_build(spec)
  end
end

# Path 1: inline createTrainer fights (the 178 map-event battles, plus the
# battle facility and the mirror fight). Returns [opponent, items, party], and
# opponent.party is the same array object, so re-levelling in place covers both.
alias level_scaling_orig_createTrainer createTrainer
def createTrainer(trainerid, trainername, party, items=[])
  event_ace = RealideaLevelScaling.max_level(party)
  RealideaLevelScaling.override_built = false
  result = level_scaling_orig_createTrainer(trainerid, trainername, party, items)
  if result
    source = RealideaLevelScaling.inline_source(event_ace, result[2])
    RealideaLevelScaling.apply(result[2], source)
  end
  return result
ensure
  RealideaLevelScaling.clear_balanceo
end

# Path 2: pbTrainerBattle / .dat fights. pbLoadTrainer returns
# [opponent, items, party] or nil, and never assigns opponent.party — the battle
# reads index 2, so that is the array to re-level. Their levels are the game's
# own, and so are the dat overrides' (filler keeps them), so the ladder is
# "original" either way.
alias level_scaling_orig_pbLoadTrainer pbLoadTrainer
def pbLoadTrainer(trainerid, trainername, partyid=0)
  result = level_scaling_orig_pbLoadTrainer(trainerid, trainername, partyid)
  RealideaLevelScaling.apply(result[2], "original") if result
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

class PokemonEncounters
  alias level_scaling_orig_pbEncounteredPokemon pbEncounteredPokemon

  def pbEncounteredPokemon(enctype, tries=1)
    return RealideaLevelScaling.wild(level_scaling_orig_pbEncounteredPokemon(enctype, tries))
  end
end

# The other things written with `balanceo` -- scripted wild battles and gifts --
# must not leave a mark for the next trainer. Splat arguments: the game defines
# pbWildBattle twice and the later (*args) one wins.
alias level_scaling_orig_pbWildBattle pbWildBattle
def pbWildBattle(*args)
  RealideaLevelScaling.clear_balanceo
  return level_scaling_orig_pbWildBattle(*args)
ensure
  RealideaLevelScaling.clear_balanceo
end

alias level_scaling_orig_pbAddPokemon pbAddPokemon
def pbAddPokemon(*args)
  return level_scaling_orig_pbAddPokemon(*args)
ensure
  RealideaLevelScaling.clear_balanceo
end

# Each map-scene update is a new event step: nothing marked before it counts.
class Scene_Map
  alias level_scaling_orig_update update

  def update
    RealideaLevelScaling.clear_balanceo
    return level_scaling_orig_update
  end
end
