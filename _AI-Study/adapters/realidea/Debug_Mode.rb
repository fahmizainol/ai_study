# Optional Realidea debug-mode switch.
#
# Create Data/debug_mode.txt to expose the game's built-in debug menus.
#
# Launching with a debug flag cannot work here: Settings hard-codes DEBUG=false
# (000_Settings) and RGSS2Compatibility then does $DEBUG=DEBUG, overwriting
# whatever the executable set.  So the flag has to be re-raised from a script
# section.  It must sit immediately before Main because LukaUtilities has already
# stashed $memDebug = $DEBUG, and Scene_Intro#main (258_TitleScreen) restores
# $DEBUG = $memDebug on the way to the title screen -- both have to be true.

REALIDEA_DEBUG_MODE_FILE = "Data/debug_mode.txt"

begin
  if File.exist?(REALIDEA_DEBUG_MODE_FILE)
    $DEBUG = true
    $memDebug = true
  end
rescue
  # If the marker cannot be checked, preserve the game's normal startup mode.
end

################################################################################
# Stat presets for the party debug menu.
#
# pbPokemonDebug (136_PScreen_Party, PokemonScreen#pbPokemonDebug) builds its
# 22-entry command list as a literal inside the method, so an entry cannot be
# added to it without owning the whole 380-line body.  Instead the method is
# aliased and fronted by a menu whose first entry is that original menu and
# whose remaining entries are presets.  That costs one keypress to reach the
# stock menu and duplicates none of it.  Taking the alias here, in a section
# that loads after 195_Following (which reopens PokemonScreen twice), captures
# whatever pbPokemonDebug is live rather than the one 136 defined.
#
# Applying a preset does exactly what the stock "EV/IV/pID" and "Nature" entries
# do: write @ev in place, then setNature, which stores @natureflag and calls
# calcStats.  calcStats preserves HP damage taken, so a preset cannot heal or
# faint a Pokemon.  IVs are left alone.
#
# The level entry reads the cap from RealideaLevelCap (Level_Cap.rb, section
# 331) so it always agrees with the curve the EXP patch is enforcing, and raises
# the Pokemon through pbChangeLevel -- the same routine a Rare Candy uses -- so
# happiness, the stat window, the new moves and the evolution all come from the
# engine rather than from here.  Level_Cap is a separately installable section,
# so the entry is simply absent when it is not there.
#
# The menu is only reachable while $DEBUG is true, so it needs no marker of its
# own -- Data/debug_mode.txt above already gates it.
################################################################################

class PokemonScreen
  # [label, EVs, nature (nil clears the override and restores the natural one)].
  #
  # EVs are in PBStats order -- HP, Attack, Defense, SPEED, Sp. Atk, Sp. Def.
  # v16 puts Speed at index 3, not last, and getting that wrong silently builds
  # the wrong Pokemon.  Every spread totals 508, inside EVLIMIT (510), with no
  # stat over EVSTATLIMIT (252).
  #                                   HP  Atk  Def  Spe  SpA  SpD
  REALIDEA_STAT_PRESETS = [
    ["Physical wall",              [252,   0, 252,   0,   0,   4], PBNatures::BOLD],
    ["Special wall",               [252,   0,   4,   0,   0, 252], PBNatures::CALM],
    ["Physical sweeper",           [  4, 252,   0, 252,   0,   0], PBNatures::JOLLY],
    ["Special sweeper",            [  4,   0,   0, 252, 252,   0], PBNatures::TIMID],
    ["Physical tank",              [252, 252,   0,   0,   0,   4], PBNatures::ADAMANT],
    ["Special tank",               [252,   0,   4,   0, 252,   0], PBNatures::MODEST],
    ["Mixed attacker",             [  4, 128,   0, 252, 124,   0], PBNatures::HASTY],
    ["Clear EVs and nature",       [  0,   0,   0,   0,   0,   0], nil]
  ]

  # The header is the readout for every action on this menu, so it carries the
  # three things the entries change: level, nature and the EV spread.
  def pbDebugMenuSummary(pkmn)
    ev = pkmn.ev
    return _INTL("{1} Lv{2}: {3} nature.\nEVs {4}/{5}/{6}/{7}/{8}/{9} (HP/Atk/Def/SpA/SpD/Spe).",
       pkmn.name, pkmn.level, PBNatures.getName(pkmn.nature),
       ev[PBStats::HP], ev[PBStats::ATTACK], ev[PBStats::DEFENSE],
       ev[PBStats::SPATK], ev[PBStats::SPDEF], ev[PBStats::SPEED])
  end

  def pbApplyStatPreset(pkmn, pkmnid, preset)
    evs = preset[1]
    for i in 0...evs.length
      pkmn.ev[i] = evs[i]
    end
    if preset[2].nil?
      pkmn.natureflag = nil
      pkmn.calcStats
    else
      pkmn.setNature(preset[2])
    end
    pbRefreshSingle(pkmnid)
    pbDisplay(_INTL("{1}: {2} preset applied.", pkmn.name, preset[0]))
  end

  # nil when Level_Cap.rb is not installed, otherwise the cap the EXP patch is
  # currently enforcing, clamped into a range level= will accept (it raises
  # ArgumentError outside 1..MAXLEVEL, which would abort the party screen).
  def pbCurrentLevelCap
    return nil if !defined?(RealideaLevelCap)
    cap = RealideaLevelCap.current
    return nil if !cap.is_a?(Integer)
    return 1 if cap < 1
    return PBExperience::MAXLEVEL if cap > PBExperience::MAXLEVEL
    return cap
  end

  # A jump of several levels can cross several evolution thresholds, but
  # pbChangeLevel runs one evolution and pbCheckEvolution only ever reports the
  # next stage, so a level 5 starter sent to the cap would stop one stage short.
  # Keep going until the chain reports nothing; the bound is there because bad
  # PBS data can describe a species that evolves into itself, and an unbounded
  # loop here would be an evolution scene the player cannot escape.
  EVOLUTION_STEP_LIMIT = 5

  def pbEvolveFully(pkmn)
    steps = 0
    while steps < EVOLUTION_STEP_LIMIT
      newspecies = pbCheckEvolution(pkmn)
      break if newspecies <= 0
      pbFadeOutInWithMusic(99999) {
        evo = PokemonEvolutionScene.new
        evo.pbStartScreen(pkmn, newspecies)
        evo.pbEvolution
        evo.pbEndScreen
      }
      steps += 1
    end
  end

  def pbLevelToCap(pkmn, cap)
    if pkmn.level >= cap
      pbDisplay(_INTL("{1} is already at the level cap ({2}).", pkmn.name, cap))
      return
    end
    # pbChangeLevel announces the level gain and shows the stat window itself.
    pbChangeLevel(pkmn, cap, self)
    pbEvolveFully(pkmn)
    pbHardRefresh   # the species, and so the party sprite, may have changed
  end

  alias realidea_stock_pbPokemonDebug pbPokemonDebug

  # Indices are resolved the way 136_PScreen_Party resolves its own party menu
  # (cmdDebug/cmdSummary/...), because the level entry is not always present.
  def pbPokemonDebug(pkmn, pkmnid)
    cap = pbCurrentLevelCap
    commands = [_INTL("Debug menu")]
    cmdLevelCap = -1
    if !cap.nil?
      cmdLevelCap = commands.length
      commands.push(_INTL("Level up to cap ({1})", cap))
    end
    cmdPresets = commands.length
    for i in 0...REALIDEA_STAT_PRESETS.length
      commands.push(REALIDEA_STAT_PRESETS[i][0])
    end
    cmdCancel = commands.length
    commands.push(_INTL("Cancel"))
    cmd = 0
    loop do
      cmd = @scene.pbShowCommands(pbDebugMenuSummary(pkmn), commands, cmd)
      break if cmd < 0 || cmd == cmdCancel
      if cmd == 0
        realidea_stock_pbPokemonDebug(pkmn, pkmnid)
      elsif cmdLevelCap >= 0 && cmd == cmdLevelCap
        pbLevelToCap(pkmn, cap)
      else
        pbApplyStatPreset(pkmn, pkmnid, REALIDEA_STAT_PRESETS[cmd - cmdPresets])
      end
    end
  end
end
