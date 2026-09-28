# Curve_SelfTest — TEST-ONLY section, never shipped. Checks Level_Cap (rnb mode,
# remap, catch-up EXP), Level_Scaling (curve remap on the real createTrainer path,
# balanceo detection, a real Team_Overrides fight, real wild encounters) and
# Badge_Rewards (real evolution data, pending logic, mega switch, hook wiring)
# inside the real engine, then exits without reaching the title screen.
#
# Insert before Main in a SCRATCH bundle only. Trigger: Data/curve_selftest.txt.
# Writes Data/curve_selftest_results.txt. Expects Data/level_cap_mode.txt = rnb,
# Data/level_scaling.txt, Data/wild_scaling.txt and Data/badge_rewards.txt present.

module CurveSelfTest
  TRIGGER = "Data/curve_selftest.txt"
  OUT = "Data/curve_selftest_results.txt"

  def self.requested?
    return File.exist?(TRIGGER)
  rescue
    return false
  end

  def self.check(name)
    begin
      ok, detail = yield
      @lines.push("#{ok ? 'ok  ' : 'FAIL'} #{name}: #{detail}")
    rescue Exception => e
      @lines.push("FAIL #{name}: #{e.class}: #{e.message} @ #{(e.backtrace || [])[0, 3].join(' | ')}")
    end
  end

  def self.mon(sym, level)
    return PokeBattle_Pokemon.new(getConst(PBSpecies, sym), level, $Trainer)
  end

  def self.set_badges(n)
    $Trainer.badges = [] if !$Trainer.badges
    for i in 0...8
      $Trainer.badges[i] = (i < n)
    end
  end

  class Map78
    def map_id; 78; end
    def method_missing(*_a); nil; end
  end

  def self.run
    @lines = []
    AIProbe.bootstrap
    set_badges(0)
    $Trainer.party = [mon(:RATTATA, 10)]

    check("mode") { [RealideaLevelCap.mode == "rnb", RealideaLevelCap.mode] }
    check("caps") do
      got = (0..8).map { |b| set_badges(b); RealideaLevelCap.current }
      set_badges(0)
      [got == [21, 25, 35, 42, 57, 69, 85, 91, 95], got.inspect]
    end
    check("hooks wired") do
      want = [[Object, :level_scaling_orig_balanceo], [Object, :level_scaling_orig_team_override_build],
              [Object, :level_scaling_orig_createTrainer], [Object, :badge_rewards_orig_pbCodeMysteryGift],
              [Object, :badge_rewards_orig_renderBadgeAnimation],
              [PokemonEncounters, :level_scaling_orig_pbEncounteredPokemon],
              [PokeBattle_Battle, :badge_rewards_orig_pbCanMegaEvolve?],
              [PokeBattle_Battle, :realidea_level_cap_gain_exp_one],
              [Object, :level_scaling_orig_pbWildBattle], [Object, :level_scaling_orig_pbAddPokemon],
              [Scene_Map, :level_scaling_orig_update]]
      missing = want.reject { |k, m| k.method_defined?(m) || k.private_method_defined?(m) }
      [missing.empty?, missing.empty? ? "all #{want.length}" : "missing #{missing.inspect}"]
    end

    check("filler fight moves original -> rnb") do
      r = createTrainer(1, "SelfTest", [createPokemon("RATTATA", 40), createPokemon("RATTATA", 38)])
      got = r[2].map { |p| p.level }
      [got == [69, 57], got.inspect]
    end
    check("stats follow the new level") do
      r = createTrainer(1, "SelfTest", [createPokemon("RATTATA", 40)])
      p = r[2][0]
      fresh = mon(:RATTATA, p.level)
      [p.totalhp > 100 && p.level == 69, "lv#{p.level} hp#{p.totalhp}"]
    end
    check("balanceo fight is not remapped") do
      $Trainer.party = [mon(:RATTATA, 40)]
      b = balanceo
      r = createTrainer(1, "SelfTest", [createPokemon("RATTATA", balanceo), createPokemon("RATTATA", balanceo - 2)])
      got = r[2].map { |p| p.level }
      $Trainer.party = [mon(:RATTATA, 10)]
      [got == [b, b - 2], "balanceo #{b} -> #{got.inspect}"]
    end
    check("Abi's generated override moves expert -> rnb") do
      saved = $game_map
      $game_map = Map78.new
      begin
        party = [createPokemon("DEWPIDER", 14), createPokemon("ANORITH", 14), createPokemon("VESPIQUEN", 14)]
        r = createTrainer(33, "Abi", party)
        got = r[2].map { |p| p.level }
        names = r[2].map { |p| PBSpecies.getName(p.species) }
        [got.max == 21 && names.length == 6, "#{names.zip(got).inspect}"]
      ensure
        $game_map = saved
      end
    end
    check("dat path and partner") do
      [RealideaLevelScaling.override_curve == "expert" || defined?(TEAM_OVERRIDES_CURVE),
       "override curve #{RealideaLevelScaling.override_curve}"]
    end

    check("wild Ruta 1 levels follow the curve") do
      $PokemonMap = PokemonMapMetadata.new if !$PokemonMap
      enc = PokemonEncounters.new
      enc.setup(3)
      seen = []
      20.times do
        e = enc.pbEncounteredPokemon(EncounterTypes::Land)
        seen.push(e[1]) if e
      end
      seen = seen.uniq.sort
      [!seen.empty? && seen.min >= 5 && seen.max <= 6, "levels #{seen.inspect} (table 3-4)"]
    end

    check("catch-up EXP x3.75 at 12 below the cap") do
      set_badges(3)                              # rnb cap 42
      p = mon(:RATTATA, 30)
      RealideaLevelCap.exp_pokemon = p
      got = PBExperience.pbAddExperience(p.exp, 100, p.growthrate) - p.exp
      RealideaLevelCap.exp_pokemon = nil
      set_badges(0)
      [got == 375, "gained #{got}"]
    end

    check("gifts evolve through the game's own data") do
      want = { [:GIBLE, 39] => :GABITE, [:BELDUM, 54] => :METAGROSS, [:GOOMY, 60] => :GOODRA,
               [:ELEKID, 22] => :ELEKID, [:LARVITAR, 54] => :PUPITAR, [:JANGMOO, 66] => :KOMMOO }
      bad = []
      want.each do |(sym, lv), expect|
        p = RealideaBadgeRewards.build(sym, lv)
        got = p ? p.species : nil
        bad.push("#{sym}@#{lv}=#{got ? PBSpecies.getName(got) : 'nil'}") if got != getConst(PBSpecies, expect)
        bad.push("#{sym} no moves") if p && p.moves.reject { |m| !m || m.id == 0 }.empty?
      end
      [bad.empty?, bad.empty? ? "#{want.length} gifts ok" : bad.join(", ")]
    end
    check("every reward species and stone exists") do
      missing = []
      RealideaBadgeRewards::REWARDS.each do |b, r|
        (r[:pokemon] || []).each { |s| missing.push(s) if !RealideaBadgeRewards.species_id(s) }
        (r[:stones] || []).each { |s| missing.push(s) if !RealideaBadgeRewards.item_id(s) }
      end
      [missing.empty?, missing.empty? ? "all present" : missing.uniq.inspect]
    end
    check("pending rewards by badge count") do
      set_badges(3)
      got = RealideaBadgeRewards.pending_badges
      set_badges(0)
      [got == [1, 2, 3], got.inspect]
    end
    check("gift level is cap - 3") do
      set_badges(4)
      got = RealideaBadgeRewards.gift_level
      set_badges(0)
      [got == 54, "lv#{got}"]
    end
    check("mega switch is read as on from badge 3, then restored") do
      set_badges(2)
      before = RealideaBadgeRewards.with_mega_switch { $game_switches[512] }
      set_badges(3)
      during = RealideaBadgeRewards.with_mega_switch { $game_switches[512] }
      after = $game_switches[512]
      set_badges(0)
      [!before && during == true && !after, "2 badges #{before.inspect}, 3 badges #{during.inspect}, after #{after.inspect}"]
    end

    File.open(OUT, "wb") do |f|
      fails = @lines.select { |l| l.index("FAIL") == 0 }.length
      f.write("#{@lines.length} checks, #{fails} failed\n")
      f.write(@lines.join("\n") + "\n")
    end
  rescue Exception => e
    File.open(OUT, "wb") { |f| f.write("CRASH #{e.class}: #{e.message}\n#{(e.backtrace || []).join("\n")}\n") }
  end
end

module AIProbe
  class << self
    alias curve_selftest_orig_requested? requested?
    alias curve_selftest_orig_run run
  end

  def self.requested?
    return true if CurveSelfTest.requested?
    return curve_selftest_orig_requested?
  end

  def self.run
    return CurveSelfTest.run if CurveSelfTest.requested?
    return curve_selftest_orig_run
  end
end
