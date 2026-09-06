# Opt-in frozen strength benchmark for Realidea.
#
# Create Data/ai_gauntlet.txt and launch the game. The existing AIProbe boot branch
# delegates here, runs stock and Portable AI against the same teams/seeds, and writes
# Data/ai_gauntlet_results.ndjson without opening a save file.
#
# Data/ai_harness.txt (optional) sets run-level knobs, one key=value per line:
#   any of PortableAIRealidea::Harness::CONFIG_OVERRIDE_KEYS -- override that core
#     config key for the whole run, so a policy A/B is two runs of one build rather
#     than two builds. Whatever is set is stamped on every record.
#   trace=true   -- record the per-turn portable decision trace (default false; it was
#                   unconditional through 0.1.0 and dominated the file size)
#   seeds=a,b,c  -- replace the five default seeds
#   matchups=x,y -- run only these named matchups from the schedule
#   append=true  -- append to the results file instead of truncating it
#   teams=NAME   -- roster set (default "archetype", the frozen three-mon fixture).
#                   The tier sets gen6ou_a/gen6ou_b are real gen 6 OU sample teams;
#                   see tools/make_tier_teams.py --game realidea.
#   schedule=tier -- every ordered non-mirror pairing of the set's four teams in
#                   singles (12 matchups), written to its own results file so tier
#                   numbers can never pool with the frozen eight-matchup benchmark.
#   mega=false   -- suppress Mega Evolution (default on; see run_with)

class PortableAIGauntletScene < AIProbeNullScene
  def pbStartBattle(battle)
    @battle = battle
  end

  def pbChooseNewEnemy(index, party)
    @battle.pbDefaultChooseNewEnemy(index, party)
  end

  def pbDisplayConfirmMessage(msg)
    false
  end

  def pbShowCommands(msg, commands, default_value)
    default_value || 0
  end
end

module PortableAIGauntlet
  TRIGGER = "Data/ai_gauntlet.txt"
  OUT     = "Data/ai_gauntlet_results.ndjson"
  SUMMARY = "Data/ai_gauntlet_summary.txt"
  TIER_OUT     = "Data/ai_tier_results.ndjson"
  TIER_SUMMARY = "Data/ai_tier_summary.txt"
  PROGRESS     = "Data/ai_gauntlet_progress.txt"
  ERRLOG       = "Data/ai_gauntlet_error.txt"
  SEEDS   = [104729, 130363, 155921, 196613, 262147]

  DEFAULT_TEAM_SET = "archetype"

  TEAMS = {
    "offense" => [
      ["GARCHOMP",  %w[EARTHQUAKE DRAGONCLAW SWORDSDANCE PROTECT]],
      ["MAGNEZONE", %w[THUNDERBOLT FLASHCANNON THUNDERWAVE PROTECT]],
      ["GENGAR",    %w[SHADOWBALL SLUDGEBOMB WILLOWISP DESTINYBOND]]
    ],
    "balance" => [
      ["SKARMORY", %w[BRAVEBIRD ROOST STEALTHROCK WHIRLWIND]],
      ["SNORLAX",  %w[BODYSLAM CRUNCH REST SLEEPTALK]],
      ["STARMIE",  %w[SURF PSYCHIC RECOVER THUNDERBOLT]]
    ],
    "bulky" => [
      ["UMBREON",   %w[FOULPLAY TOXIC MOONLIGHT PROTECT]],
      ["FERROTHORN", %w[POWERWHIP GYROBALL LEECHSEED STEALTHROCK]],
      ["TOXAPEX",   %w[SCALD RECOVER TOXIC HAZE]]
    ],
    "speed" => [
      ["ALAKAZAM", %w[PSYCHIC SHADOWBALL DAZZLINGGLEAM RECOVER]],
      ["CROBAT",   %w[BRAVEBIRD CROSSPOISON UTURN ROOST]],
      ["WEAVILE",  %w[ICICLECRASH KNOCKOFF ICEshard SWORDSDANCE]]
    ]
  }

  # The frozen benchmark: eight matchups over the three-mon archetype fixture. Every
  # 0.1.0 number was measured on exactly these, so they do not change.
  MATCHUPS = [
    ["offense_vs_balance", "offense", "balance", false],
    ["balance_vs_offense", "balance", "offense", false],
    ["bulky_vs_speed", "bulky", "speed", false],
    ["speed_vs_bulky", "speed", "bulky", false],
    ["offense_vs_bulky", "offense", "bulky", false],
    ["speed_vs_balance", "speed", "balance", false],
    ["double_offense_balance", "offense", "balance", true],
    ["double_speed_bulky", "speed", "bulky", true]
  ]

  # Every ordered non-mirror pairing of a roster's four teams. Team keys are generic
  # (team1..team4) across every tier set, so the schedule is identical set to set and
  # the two sets stay comparable.
  def self.tier_matchups(teams)
    names = teams.keys.sort
    out = []
    names.each do |left|
      names.each do |right|
        out << ["#{left}_vs_#{right}", left, right, false] if left != right
      end
    end
    out
  end

  def self.team_set(name)
    sets = PortableAIRealideaTeams::SETS
    teams = sets[name]
    if !teams
      raise "unknown team set #{name.inspect}; available: #{sets.keys.sort.join(', ')}"
    end
    teams
  end

  def self.requested?
    File.exist?(TRIGGER)
  rescue
    false
  end

  def self.command_phase(battle)
    scene = battle.scene
    scene.pbBeginCommandPhase
    scene.pbResetCommandIndices
    PortableAIRealidea.clear_cache(battle)

    for index in 0...4
      battler = battle.battlers[index]
      battler.effects[PBEffects::SkipTurn] = false if battler
      if battler && (battle.pbCanShowCommands?(index) || battler.isFainted?)
        battle.choices[index][0] = 0
        battle.choices[index][1] = 0
        battle.choices[index][2] = nil
        battle.choices[index][3] = -1
      end
    end
    mega = battle.megaEvolution
    for side in 0...mega.length
      for owner in 0...mega[side].length
        mega[side][owner] = -1 if mega[side][owner] >= 0
      end
    end

    for index in 0...4
      battler = battle.battlers[index]
      next if !battler || battler.isFainted?
      next if !battle.pbCanShowCommands?(index)
      battle.pbDefaultChooseEnemyCommand(index)
    end
  end

  # One line per battle, flushed as it goes. The results file only gains a record when
  # a battle finishes, so without this a run that stops mid-battle is indistinguishable
  # from one that never started.
  def self.note(line)
    begin
      File.open(PROGRESS, "ab") { |file| file.write(line + "\n") }
    rescue
      nil
    end
  end

  def self.run
    begin
      File.open(PROGRESS, "wb") { |file| file.write("") }
      File.delete(ERRLOG) if File.exist?(ERRLOG)
    rescue
      nil
    end
    PortableAIRealidea::Harness.with_config { |cfg| run_with(cfg) }
  rescue Exception => error
    # Anything thrown outside run_one's own rescue used to surface as nothing at all:
    # mkxp raises its modal error box, the process then sits in the window message pump
    # at ~0.015 CPU-seconds per five wall seconds, and the results file is empty with no
    # statement anywhere of what went wrong. That is the shape the 0.6.2 "gauntlet hang"
    # was reported in. It is a crash, and this is where it becomes readable.
    begin
      File.open(ERRLOG, "wb") do |file|
        file.write("#{error.class}: #{error.message}\n")
        file.write(((error.backtrace || [])[0, 15]).join("\n") + "\n")
      end
    rescue
      nil
    end
  end

  def self.run_with(cfg)
    AIProbe.bootstrap
    AIProbe.install_exception_capture
    trace = PortableAIRealidea::Harness.bool(cfg, "trace", false)
    seeds = PortableAIRealidea::Harness.list(cfg, "seeds", SEEDS)
    mode_flag = PortableAIRealidea::Harness.bool(cfg, "append", false) ? "ab" : "wb"

    set_name = (cfg["teams"] && cfg["teams"] != "") ? cfg["teams"] : DEFAULT_TEAM_SET
    begin
      teams = team_set(set_name)
    rescue RuntimeError => error
      note("Gauntlet: #{error.message}")
      return
    end
    tier = cfg["schedule"] == "tier"
    matchups = tier ? tier_matchups(teams) : MATCHUPS
    # Named subset, for smoke-testing a new roster cheaply and for resuming a run past
    # a matchup that stalled without re-fighting the ones already on disk.
    if cfg["matchups"] && cfg["matchups"] != ""
      wanted = cfg["matchups"].split(",").map { |name| name.strip }
      matchups = matchups.select { |matchup| wanted.include?(matchup[0]) }
    end
    if matchups.empty?
      note("Gauntlet: no matchups matched #{cfg['matchups'].inspect}")
      return
    end
    out     = tier ? TIER_OUT : OUT
    summary = tier ? TIER_SUMMARY : SUMMARY

    # Realidea gates Mega Evolution on two story switches that a save-less harness
    # leaves false (pbCanMegaEvolve?, PokeBattle_Battle.rb:1967), so without this a
    # Tyranitar holding Tyranitarite is just a Tyranitar holding a rock -- and the
    # gen 6 rosters are built around megas. Both arms reach it by the same path:
    # stock and Portable both call pbRegisterMegaEvolution from
    # pbEnemyShouldMegaEvolve?, so this changes the teams, never the policy. On by
    # default and provably inert for the archetype fixture, whose mons hold no stone:
    # pbCanMegaEvolve? tests hasMega? before it reaches either switch.
    mega = PortableAIRealidea::Harness.bool(cfg, "mega", true)
    $game_switches[512] = mega

    old_trainer = $Trainer
    old_enabled = (defined?($PORTABLE_AI_ENABLED) ? $PORTABLE_AI_ENABLED : nil)
    counts = {
      "stock" => { "wins" => 0, "losses" => 0, "draws" => 0, "errors" => 0, "turns" => 0 },
      "portable" => { "wins" => 0, "losses" => 0, "draws" => 0, "errors" => 0, "turns" => 0 }
    }
    note("Gauntlet: #{matchups.length * seeds.length * 2} battles, " +
         "#{tier ? 'tier' : 'frozen'} schedule, teams=#{set_name}, " +
         "mega=#{mega}, portable #{PortableAI::VERSION}")

    File.open(out, mode_flag) do |file|
      matchups.each do |matchup|
        seeds.each do |seed|
          ["stock", "portable"].each do |mode|
            note("start #{matchup[0]} #{mode} seed=#{seed}")
            record = run_one(matchup, seed, mode, trace, teams, set_name, mega)
            note("  #{record['result']} turns=#{record['turns']}" +
                 (record["error"] ? " #{record['error']}" : ""))
            bucket = counts[mode]
            bucket["turns"] += record["turns"].to_i
            case record["result"]
            when "win"  then bucket["wins"] += 1
            when "loss" then bucket["losses"] += 1
            when "draw" then bucket["draws"] += 1
            else bucket["errors"] += 1
            end
            file.write(AIProbe.json(record) + "\n")
            file.flush
          end
        end
      end
    end

    File.open(summary, "wb") do |file|
      counts.each do |mode, values|
        total = values["wins"] + values["losses"] + values["draws"]
        win_rate = total > 0 ? values["wins"] * 100.0 / total : 0
        mean_turns = total > 0 ? values["turns"] * 1.0 / total : 0
        file.write("#{mode}: wins=#{values['wins']} losses=#{values['losses']} " +
                   "draws=#{values['draws']} errors=#{values['errors']} " +
                   "win_rate=#{round1(win_rate)} " +
                   "mean_turns=#{round1(mean_turns)}\n")
      end
    end
  ensure
    $Trainer = old_trainer if defined?(old_trainer)
    $PORTABLE_AI_ENABLED = old_enabled if defined?(old_enabled)
  end

  def self.run_one(matchup, seed, mode, trace = false, teams = nil,
                   set_name = DEFAULT_TEAM_SET, mega = true)
    teams ||= team_set(DEFAULT_TEAM_SET)
    id, left_name, right_name, doubles = matchup
    left_trainer = make_trainer("Stock #{left_name}")
    right_trainer = make_trainer("#{mode} #{right_name}")
    left_party = make_party(teams[left_name], left_trainer)
    right_party = make_party(teams[right_name], right_trainer)
    scene = PortableAIGauntletScene.new
    battle = PokeBattle_Battle.new(
      scene, left_party, right_party, left_trainer, right_trainer
    )
    battle.internalbattle = false
    battle.doublebattle = doubles
    battle.debug = true
    battle.items = []
    battle.instance_variable_set(:@portable_ai_gauntlet, true)
    battle.instance_variable_set(:@portable_ai_decision_trace, trace ? [] : nil)

    $Trainer = left_trainer
    $PORTABLE_AI_ENABLED = (mode == "portable")
    srand(seed)
    decision = battle.pbStartBattle(true)
    result = decision == 2 ? "win" : decision == 1 ? "loss" : "draw"
    record = {
      "id" => id,
      "mode" => mode,
      "seed" => seed,
      "format" => doubles ? "double" : "single",
      "left_stock_team" => left_name,
      "right_test_team" => right_name,
      "teams" => set_name,
      # Stamped because it changes the rosters, not the policy: a mega-less gen 6 team
      # is not the team its author built, and a reader must not have to guess which
      # they are looking at.
      "mega" => mega,
      "decision" => decision,
      "result" => result,
      "turns" => battle.turncount
    }
    # Stamped on EVERY arm, not just the portable one: a stock record is only meaningful
    # as the paired baseline of the run it came from, and a readout rendered from a
    # stale baseline is the failure this stamp exists to make visible.
    record["portable_version"] = PortableAI::VERSION if defined?(PortableAI::VERSION)
    if mode == "portable"
      overrides = PortableAIRealidea.config_overrides
      record["config_overrides"] = overrides if !overrides.empty?
      captured = battle.instance_variable_get(:@portable_ai_decision_trace)
      record["trace"] = captured if captured
    end
    record
  rescue Exception => error
    {
      "id" => id,
      "mode" => mode,
      "seed" => seed,
      "format" => doubles ? "double" : "single",
      "teams" => set_name,
      "mega" => mega,
      "result" => "error",
      "turns" => 0,
      "error" => "#{error.class}: #{error.message}",
      "where" => (error.backtrace ? error.backtrace[0, 6].join(" | ") : nil),
      "portable_version" => (defined?(PortableAI::VERSION) ? PortableAI::VERSION : nil)
    }
  end

  def self.make_trainer(name)
    trainer = PokeBattle_Trainer.new(name, 0)
    def trainer.skill; 100; end
    def trainer.skillCode; ""; end
    trainer
  end

  # A spec is [SPECIES, [moves]] for the archetype fixture, or that plus a hash of
  # form/item/ability/nature/evs/ivs for a tier set. Omitting the hash reproduces the
  # fixture exactly: flat 31 IVs, 85 EVs, slot-0 ability, Hardy, no item.
  def self.make_party(specs, trainer)
    specs.map do |spec|
      species_name, move_names, extra = spec
      extra ||= {}
      species = PBSpecies.const_get(species_name)
      pokemon = PokeBattle_Pokemon.new(species, 100, trainer)
      # Forme first: a forme carries its own BaseStats and its own ability slots, so
      # setting it after the spread would build the mon from the base species' numbers.
      # form= runs the species' onSetForm hook, which for Rotom swaps an appliance move
      # into the moveset -- harmless here only because the four slots are assigned
      # immediately below. formNoCall= is the fallback because form= also calls
      # pbSeenForm, which wants a Pokedex this harness has no save file for.
      if extra["form"] && extra["form"] > 0
        begin
          pokemon.form = extra["form"]
        rescue
          pokemon.formNoCall = extra["form"]
        end
      end
      for slot in 0...4
        move_name = move_names[slot]
        next if !move_name
        # Preserve compatibility with the one mixed-case fixture spelling above.
        move_name = move_name.to_s.upcase
        pokemon.moves[slot] = PBMove.new(PBMoves.const_get(move_name))
      end
      if extra["item"]
        item = (PBItems.const_get(extra["item"]) rescue nil)
        pokemon.setItem(item) if item
      end
      pokemon.setAbility(extra["ability"] || 0)
      pokemon.setNature(extra["nature"] || 0)
      # Hidden Power carries no field in v16: its type is derived from IV parities
      # (pbHiddenPower, PokeBattle_MoveEffects.rb:3760) over a pool one type wider than
      # the generation these sets were built for. The IVs below are already solved for
      # the type the author wanted -- see Realidea.finalise_hidden_power in
      # tools/showdown_names.py -- so nothing is set here and nothing may be.
      evs = extra["evs"]
      ivs = extra["ivs"]
      for stat in 0...6
        pokemon.iv[stat] = ivs ? ivs[stat] : 31
        pokemon.ev[stat] = evs ? evs[stat] : 85
      end
      pokemon.calcStats
      pokemon.hp = pokemon.totalhp
      pokemon
    end
  end

  def self.round1(value)
    ((value * 10).round) / 10.0
  end
end

# Roster lookup, shared with the tier suite. The tier file the bundle concatenates
# after this one merges itself in here (tools/make_tier_teams.py --game realidea).
# "archetype" is the original three-mon fixture and the default, so omitting teams=
# reproduces every run recorded before roster selection existed.
module PortableAIRealideaTeams
  SETS = { "archetype" => PortableAIGauntlet::TEAMS }
end


class PokeBattle_Battle
  if !method_defined?(:portable_ai_gauntlet_stock_pbCommandPhase)
    alias portable_ai_gauntlet_stock_pbCommandPhase pbCommandPhase
  end
  if !method_defined?(:portable_ai_gauntlet_stock_pbEndOfBattle)
    alias portable_ai_gauntlet_stock_pbEndOfBattle pbEndOfBattle
  end

  def pbCommandPhase
    if @portable_ai_gauntlet
      PortableAIGauntlet.command_phase(self)
    else
      portable_ai_gauntlet_stock_pbCommandPhase
    end
  end

  def pbEndOfBattle(canlose = false)
    if @portable_ai_gauntlet
      @scene.pbEndBattle(@decision)
      return @decision
    end
    portable_ai_gauntlet_stock_pbEndOfBattle(canlose)
  end
end
