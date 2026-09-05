# Opt-in frozen strength benchmark for Realidea.
#
# Create Data/ai_gauntlet.txt and launch the game. The existing AIProbe boot branch
# delegates here, runs stock and Portable AI against the same teams/seeds, and writes
# Data/ai_gauntlet_results.ndjson without opening a save file.

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
  SEEDS   = [104729, 130363, 155921, 196613, 262147]

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

  def self.run
    AIProbe.bootstrap
    old_trainer = $Trainer
    old_enabled = (defined?($PORTABLE_AI_ENABLED) ? $PORTABLE_AI_ENABLED : nil)
    counts = {
      "stock" => { "wins" => 0, "losses" => 0, "draws" => 0, "errors" => 0, "turns" => 0 },
      "portable" => { "wins" => 0, "losses" => 0, "draws" => 0, "errors" => 0, "turns" => 0 }
    }

    File.open(OUT, "wb") do |file|
      MATCHUPS.each do |matchup|
        SEEDS.each do |seed|
          ["stock", "portable"].each do |mode|
            record = run_one(matchup, seed, mode)
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

    File.open(SUMMARY, "wb") do |file|
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

  def self.run_one(matchup, seed, mode)
    id, left_name, right_name, doubles = matchup
    left_trainer = make_trainer("Stock #{left_name}")
    right_trainer = make_trainer("#{mode} #{right_name}")
    left_party = make_party(TEAMS[left_name], left_trainer)
    right_party = make_party(TEAMS[right_name], right_trainer)
    scene = PortableAIGauntletScene.new
    battle = PokeBattle_Battle.new(
      scene, left_party, right_party, left_trainer, right_trainer
    )
    battle.internalbattle = false
    battle.doublebattle = doubles
    battle.debug = true
    battle.items = []
    battle.instance_variable_set(:@portable_ai_gauntlet, true)
    battle.instance_variable_set(:@portable_ai_decision_trace, [])

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
      "decision" => decision,
      "result" => result,
      "turns" => battle.turncount
    }
    if mode == "portable"
      record["trace"] = battle.instance_variable_get(:@portable_ai_decision_trace)
    end
    record
  rescue Exception => error
    {
      "id" => id,
      "mode" => mode,
      "seed" => seed,
      "format" => doubles ? "double" : "single",
      "result" => "error",
      "turns" => 0,
      "error" => "#{error.class}: #{error.message}",
      "where" => (error.backtrace ? error.backtrace[0, 6].join(" | ") : nil)
    }
  end

  def self.make_trainer(name)
    trainer = PokeBattle_Trainer.new(name, 0)
    def trainer.skill; 100; end
    def trainer.skillCode; ""; end
    trainer
  end

  def self.make_party(specs, trainer)
    specs.map do |spec|
      species_name, move_names = spec
      species = PBSpecies.const_get(species_name)
      pokemon = PokeBattle_Pokemon.new(species, 100, trainer)
      for slot in 0...4
        move_name = move_names[slot]
        # Preserve compatibility with the one mixed-case fixture spelling above.
        move_name = move_name.to_s.upcase
        pokemon.moves[slot] = PBMove.new(PBMoves.const_get(move_name))
      end
      pokemon.setNature(0)
      pokemon.setAbility(0)
      for stat in 0...6
        pokemon.iv[stat] = 31
        pokemon.ev[stat] = 85
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
