# =============================================================================
#  AI_Harness — automated AI-vs-AI batch runner with decision logging
#  Added by the _AI-Study project (see _AI-Study/SIM-SPEC.md). Not part of Reborn Yang.
#
#  OPT-IN. Does nothing unless Data/ai_harness.txt exists. Delete that file and the
#  game boots exactly as before.
#
#  Why this exists:
#    * allTrainersBattle/bestTrainersBattle both set $INTERNAL=false, which disables
#      logAIScorings — so the shipped runners give outcomes OR decisions, never both.
#      This runner calls the battle primitive directly and leaves $INTERNAL alone.
#    * bestTrainersBattle is dead in shipped builds: load_data("battle") has no target.
#    * The bootstrap below mirrors Main.rb's mainFunctionNoGraphics, which synthesises
#      $Trainer — so no save file is required.
#
#  Config: Data/ai_harness.txt, one key=value per line. All optional.
#    pairs=10            how many matchups to run          (default 10)
#    doubles=false       double battles                    (default false)
#    log_decisions=true  keep $INTERNAL on -> debuglog.txt (default true)
#    seed=20260903       RNG seed, logged with results     (default: time-based)
#    field=0             forced field effect id            (default 0)
#    filter=Gym          only trainers whose name matches  (default: none)
#    out=Data/ai_harness_results.csv
# =============================================================================

# Minimal stand-in for Game_Map. Battle setup touches the map even when no map is
# loaded: PokeBattle_Field.rb:55 guards with `$game_map ? ... : 0`, but :63 calls
# $game_map.terrain_tag unguarded and blows up on nil. Rather than patch their file we
# supply an object that answers the few things battle setup asks for.
class AIHarnessNullMap
  def terrain_tag(*_a); 0; end
  def map_id; 1; end
  def name; "AIHarness"; end
  def width; 20; end
  def height; 20; end
  def events; {}; end
  def passable?(*_a); true; end
  def method_missing(_m, *_a); nil; end
  def respond_to_missing?(*_a); true; end
end

module AIHarness
  TRIGGER = "Data/ai_harness.txt"

  def self.requested?
    File.exist?(TRIGGER)
  rescue
    false
  end

  def self.config
    cfg = {}
    File.open(TRIGGER, "rb") do |f|
      f.read.split(/[\r\n]+/).each do |line|
        line = line.strip
        next if line.empty? || line[0, 1] == "#"
        k, v = line.split("=", 2)
        cfg[k.to_s.strip] = v.to_s.strip if k && v
      end
    end
    cfg
  rescue
    {}
  end

  def self.int(cfg, key, dflt)
    cfg[key] ? cfg[key].to_i : dflt
  end

  def self.bool(cfg, key, dflt)
    return dflt if !cfg[key]
    ["true", "1", "yes", "on"].include?(cfg[key].downcase)
  end

  # Mirrors Main.rb:56 mainFunctionNoGraphics. Builds just enough global state for
  # battles to run, without loading a save.
  def self.bootstrap
    $cache.pkmn_dex   = load_data("Data/dexdata.dat")  if !$cache.pkmn_dex
    $cache.pkmn_move  = load_data("Data/moves.dat")    if !$cache.pkmn_move
    $cache.RXsystem   = load_data("Data/System.rxdata") if !$cache.RXsystem
    $cache.cacheFields
    $cache.items      = load_data("Data/items.dat")    if !$cache.items
    $game_system    = Game_System.new
    $game_switches  = Game_Switches.new  if !$game_switches
    $game_variables = Game_Variables.new if !$game_variables
    $PokemonTemp    = PokemonTemp.new
    $game_temp      = Game_Temp.new
    $Trainer        = PokeBattle_Trainer.new("AIHarness", 5) if !$Trainer
    $game_screen    = Game_Screen.new
    $game_player    = Game_Player.new    if !$game_player
    $PokemonGlobal  = PokemonGlobalMetadata.new if !$PokemonGlobal
    $PokemonBag     = PokemonBag.new     if !$PokemonBag
    $testing        = true
    # Battle setup reads the map; give it something harmless.
    $game_map = AIHarnessNullMap.new if !$game_map
    $game_player.instance_variable_set(:@map, $game_map) if $game_player
    # Species/move/item/ability names live in Data/messages.dat, which is only loaded on
    # the compile path (Compiler.rb:2145) — so in a plain release boot the AI logs come
    # out with every name blank. Load it explicitly or the decision records are unusable
    # for differential testing.
    begin
      MessageTypes.loadMessageFile("Data/messages.dat") if safeExists?("Data/messages.dat")
      # loadMessageFile alone is not enough: the INDEXED tables (Species, Moves, Items,
      # Abilities) are populated by pbSetTextMessages (Compiler.rb:2152), which normally
      # only runs on the compile path. Hashed lookups like TrainerNames work without it,
      # which is why trainer names resolve but move names do not.
      pbSetTextMessages
      echo "AIHarness: messages loaded (sample: #{PBMoves.getName(PBMoves::TACKLE) rescue '?'})"
    rescue Exception => e
      echo "AIHarness: WARNING message load failed (#{e.class}: #{e.message}) — names blank"
    end
  end

  # PokeBattle_TestEnvironment.rb is deliberately NOT in Data/!script_order.csv — it is
  # eval'd on demand (see Main.rb mainFunctionNoGraphics). It defines the battle
  # primitives we need: idontwanttobreakperryscode, trainershit, testAllBattlesSingles,
  # and the pbDisplay overrides that stop battles blocking on message boxes.
  def self.load_test_environment
    return if $ai_harness_testenv_loaded
    Object.class_eval(File.open("Scripts/PokeBattle_TestEnvironment.rb", "rb") { |f| f.read })
    # PokeBattle_TestEnvironment.rb:1024 reopens PokeBattle_Pokemon with
    # `attr_accessor :ability` so random_battles can write mon.ability= — which
    # REPLACES the computed #ability with a plain @ability reader. @ability is nil on
    # every Pokemon the probe builds, so the AI saw NO abilities at all: Levitate,
    # Volt/Water Absorb and Flash Fire targets all scored as plain type matchups
    # (verified: battler.ability was nil in every probe record before this fix).
    # Restore the computed path while keeping the writer random_battles needs.
    # __rc_ability is the alias RandomizedChallenge took of the MultipleForms-era
    # method, which honours @abilityflag — the pin the probe sets via setAbility.
    PokeBattle_Pokemon.class_eval do
      def ability
        return @ability if @ability
        return __rc_ability
      end
    end
    $ai_harness_testenv_loaded = true
  end

  # The structured decision dump ($ai_log_data[i].logAIScorings) is called from
  # PokeBattle_Battle.rb:5147 in the NORMAL command phase, but pbCommandPhaseTEST
  # replaces that phase and its equivalent calls are commented out
  # (PokeBattle_TestEnvironment.rb:196-201) — they use a stale signature,
  # `logAIScorings($ai_log_data[i])`, which would raise. So the shipped test path
  # produces battles with no structured scoring blocks. Re-attach it correctly.
  #
  # Unlike the normal flow we do NOT skip pbOwnedByPlayer? battlers: in the harness
  # both sides are AI, and we want decisions from both.
  def self.attach_decision_logging
    return if $ai_harness_logging_attached
    PokeBattle_Battle.class_eval do
      alias_method :ai_harness_orig_command_phase, :pbCommandPhaseTEST
      def pbCommandPhaseTEST
        ai_harness_orig_command_phase
        for i in 0...4
          next if @battlers[i].nil? || @battlers[i].hp <= 0
          next if $ai_log_data.nil? || $ai_log_data[i].nil?
          begin
            # PokeBattle_AI_Info#reset takes its names from battler.name / .item /
            # .ability, all of which come out blank under the test environment (it
            # replaces PokeBattle_Pokemon#ability with a bare attr_accessor and stubs
            # pbThis). Repopulate from the data layer so records are identifiable —
            # a decision log without move identity is useless for differential testing.
            # Log numeric IDs, not names. PBMoves/PBSpecies.getName go through
            # MessageTypes' INDEXED tables, which are populated by pbSetTextMessages
            # (Compiler.rb:2152) — compile-path only, and it raises here because the
            # compiler's data tables are not loaded. IDs are always available, and
            # tools/parse_reborn_log.py resolves them offline from PBS/*.txt.
            b   = @battlers[i]
            rec = $ai_log_data[i]
            rec.battler_name = "spc:#{b.species}"
            rec.battler_item = (b.item && b.item != 0 ? "itm:#{b.item}" : "")
            names = []
            for mv in b.moves
              next if mv.nil? || mv.id == 0
              names.push("mv:#{mv.id}")
            end
            rec.move_names = names if names.length > 0
            rec.logAIScorings()
          rescue Exception
            # never let logging kill a battle
          end
        end
      end
    end
    $ai_harness_logging_attached = true
  end

  def self.run
    cfg     = config
    pairs   = int(cfg, "pairs", 10)
    doubles = bool(cfg, "doubles", false)
    logdec  = bool(cfg, "log_decisions", true)
    seed    = int(cfg, "seed", Time.now.to_i)
    field   = int(cfg, "field", 0)
    filter  = cfg["filter"]
    outfile = cfg["out"] || "Data/ai_harness_results.csv"

    echo "AIHarness: starting (pairs=#{pairs} seed=#{seed})"
    srand(seed)
    echo "AIHarness: bootstrap..."
    bootstrap
    echo "AIHarness: loading test environment..."
    load_test_environment
    echo "AIHarness: test environment loaded"
    if logdec
      attach_decision_logging
      # logAIScorings gates on $INTERNAL; logAISwitching gates on $DEBUG
      # (PokeBattle_AI_2.rb:17593, 17633). We bypass mainFunction entirely, so setting
      # $DEBUG here only affects logging, not the title/boot path.
      $INTERNAL = true
      $DEBUG    = true
      echo "AIHarness: decision logging attached (INTERNAL+DEBUG on)"
    else
      $INTERNAL = false
    end
    $game_variables[:Forced_Field_Effect] = field rescue nil

    if (cfg["mode"] || "battles") == "probe"
      run_probe(cfg)
      return
    end

    # Head-to-head strength benchmark; lives in the Portable_AI section (installed
    # after this script) because it drives the portable adapter. cfg key: arms=
    # comma-list to run a subset (normal_reborn,normal_portable,intense_reborn,
    # intense_portable).
    if cfg["mode"] == "gauntlet"
      if defined?(PortableAIRebornGauntlet)
        PortableAIRebornGauntlet.run(cfg)
      else
        echo "AIHarness: mode=gauntlet but the Portable_AI section is not installed"
      end
      return
    end

    list = unhashTRlist
    if filter && filter != ""
      list = list.find_all { |t| t[1].to_s.downcase.include?(filter.downcase) }
    end
    # Only trainers that actually have a party.
    list = list.find_all { |t| t[3] && t[3].length > 0 }

    echo "AIHarness: #{list.length} eligible trainers, running #{pairs} matchups, " \
         "seed=#{seed}, doubles=#{doubles}, log_decisions=#{logdec}"

    if list.length < 2
      echo "AIHarness: not enough trainers after filtering — aborting."
      finish(outfile, [], seed)
      return
    end

    rows = []
    idx  = 0
    while rows.length < pairs
      a = list[rand(list.length)]
      b = list[rand(list.length)]
      next if a.equal?(b)
      idx += 1
      break if idx > pairs * 50   # guard against a pathological filter

      t0 = Time.now
      begin
        # CAREFUL: idontwanttobreakperryscode(x, y) builds the battle as
        #   PokeBattle_Battle.new(scene, y_party, x_party, y_trainer, x_trainer)
        # so *y* is party1 (the "player" side), and it returns (decision==1), which
        # PokeBattle_Battle.rb:4633 defines as the player side winning.
        # => the return value means "b won", NOT "a won". Do not "simplify" this.
        b_won = idontwanttobreakperryscode(a, b, doubles)
        a_won = !b_won
        rows.push([rows.length, nameof(a), nameof(b), a_won ? 1 : 0,
                   a_won ? nameof(a) : nameof(b), ((Time.now - t0) * 1000).to_i])
        echo "  [#{rows.length}/#{pairs}] #{nameof(a)} vs #{nameof(b)} -> " \
             "#{a_won ? nameof(a) : nameof(b)}  (#{((Time.now - t0) * 1000).to_i} ms)"
      rescue Exception => e
        rows.push([rows.length, nameof(a), nameof(b), "ERR", "ERR", 0])
        echo "  [#{rows.length}/#{pairs}] #{nameof(a)} vs #{nameof(b)} -> ERROR: #{e.class}: #{e.message}"
      end
    end

    finish(outfile, rows, seed)
  end

  # ---------------------------------------------------------------------------
  #  probe() — score a constructed position and STOP.
  #
  #  Never advances the turn. processAIturn() ends in chooseAction(), which only
  #  *registers* intent via pbRegisterMove/pbRegisterSwitch/pbRegisterItem into
  #  @battle.choices — nothing is executed. So we read the decision straight out of
  #  battle.choices instead of scraping "[Prefer X]" from the log, which sidesteps the
  #  blank-name problem entirely.
  # ---------------------------------------------------------------------------

  STAT_KEYS = {
    "atk" => PBStats::ATTACK,  "def" => PBStats::DEFENSE, "spe" => PBStats::SPEED,
    "spa" => PBStats::SPATK,   "spd" => PBStats::SPDEF,
    "acc" => PBStats::ACCURACY, "eva" => PBStats::EVASION
  }
  # ev_* scenario keys -> @ev array indices (iv/ev arrays are ordered by PBStats).
  EV_KEYS = {
    "hp"  => PBStats::HP,    "atk" => PBStats::ATTACK, "def" => PBStats::DEFENSE,
    "spe" => PBStats::SPEED, "spa" => PBStats::SPATK,  "spd" => PBStats::SPDEF
  }
  STATUS_KEYS = {
    "sleep" => PBStatuses::SLEEP, "poison" => PBStatuses::POISON,
    "burn"  => PBStatuses::BURN,  "paralysis" => PBStatuses::PARALYSIS,
    "frozen" => PBStatuses::FROZEN
  }
  # Scenario weather names -> engine constants (battle.weather / pbWeather).
  WEATHER_IDS = {
    "rain" => PBWeather::RAINDANCE, "sun" => PBWeather::SUNNYDAY,
    "sand" => PBWeather::SANDSTORM, "hail" => PBWeather::HAIL
  }
  # Battler-effect scenario keys (effect_*) -> [PBEffects index, kind].
  # Curse is a boolean here; choiceband arrives as a numeric MOVE ID (the
  # generator resolves the name) matching how the engine stores it (:6207).
  EFFECT_KEYS = {
    "perishsong" => [PBEffects::PerishSong, :int],
    "leechseed"  => [PBEffects::LeechSeed,  :int],
    "confusion"  => [PBEffects::Confusion,  :int],
    "toxic"      => [PBEffects::Toxic,      :int],
    "yawn"       => [PBEffects::Yawn,       :int],
    "substitute" => [PBEffects::Substitute, :int],
    "curse"      => [PBEffects::Curse,      :bool],
    "choiceband" => [PBEffects::ChoiceBand, :int],
    # Wish is a countdown on the USER (PokeBattle_MoveEffects.rb:6089), which is what
    # makes "a Wish is already pending" expressible. Tantrum is Reborn's own boolean
    # "the move that just ran failed" flag (PokeBattle_Battler.rb:5085), kept for
    # Stomping Tantrum and read by the portable AI's move_memory rule.
    "wish"       => [PBEffects::Wish,       :int],
    "tantrum"    => [PBEffects::Tantrum,    :bool]
  }
  # Side-effect scenario keys -> [PBEffects index, value kind]. StealthRock is a
  # BOOLEAN in this engine (the AI tests `!effects[PBEffects::StealthRock]`,
  # PokeBattle_AI_2.rb:4670); the counters are layer/round ints.
  SIDE_EFFECT_KEYS = {
    "spikes"      => [PBEffects::Spikes,      :int],
    "toxicspikes" => [PBEffects::ToxicSpikes, :int],
    "stealthrock" => [PBEffects::StealthRock, :bool],
    "reflect"     => [PBEffects::Reflect,     :int],
    "lightscreen" => [PBEffects::LightScreen, :int]
  }

  # Build a trainer-format party entry (see PokemonTrainers.rb TPDEFAULTS, 27 fields).
  def self.mon_entry(m)
    e = TPDEFAULTS.clone
    e[TPSPECIES] = m["species"].to_i
    e[TPLEVEL]   = (m["level"] || 50).to_i
    e[TPITEM]    = (m["item"] || 0).to_i
    mv = m["moves"] || []
    e[TPMOVE1] = (mv[0] || 0).to_i
    e[TPMOVE2] = (mv[1] || 0).to_i
    e[TPMOVE3] = (mv[2] || 0).to_i
    e[TPMOVE4] = (mv[3] || 0).to_i
    e[TPABILITY] = m["ability"] if m["ability"]
    e[TPIV] = (m["iv"] || 31).to_i
    e[TPNATURE] = (m["nature"] || PBNatures::HARDY).to_i
    e
  end

  # Battler index layout, identical in both engines: even = player side, odd = AI
  # side. Singles occupies 0/1; doubles adds 2 (player right) and 3 (AI right).
  # Party order must match, so the second active is party slot 1 and the bench
  # starts at 2 — pbInitialize takes the party index and a mismatch would make the
  # AI's own bench reads (switch scoring) describe the wrong Pokemon.
  def self.ai_indices(doubles);  doubles ? [1, 3] : [1]; end
  def self.foe_indices(doubles); doubles ? [0, 2] : [0]; end

  def self.build_party(side, owner)
    entries = [side["active"]]
    entries.push(side["active2"]) if side["active2"]
    entries += (side["bench"] || [])
    party = []
    entries.each do |m|
      e = mon_entry(m)
      pkmn = PokeBattle_Pokemon.new(e[TPSPECIES], e[TPLEVEL], owner)
      pkmn.resetMoves
      pkmn.setItem(e[TPITEM])
      if e[TPMOVE1] > 0 || e[TPMOVE2] > 0 || e[TPMOVE3] > 0 || e[TPMOVE4] > 0
        k = 0
        for mi in [TPMOVE1, TPMOVE2, TPMOVE3, TPMOVE4]
          pkmn.moves[k] = PBMove.new(e[mi])
          k += 1
        end
        pkmn.moves.compact!
      end
      # Determinism: an unpinned Pokemon rolls its ability slot from personalID%3
      # (PokeBattle_Pokemon.rb:233 abilityIndex) — which can even land on the HIDDEN
      # ability. Nature was already pinned (HARDY); pin the ability slot to 0 too
      # unless the scenario asks for a specific one.
      pkmn.setAbility((e[TPABILITY] || 0).to_i)
      pkmn.setNature(e[TPNATURE])
      for i in 0...6
        pkmn.iv[i] = e[TPIV]
      end
      EV_KEYS.each do |k, idx|
        pkmn.ev[idx] = m["ev_" + k].to_i if m["ev_" + k]
      end
      pkmn.calcStats
      pkmn.hp = pkmn.totalhp
      # Bench HP, including hp_pct:0 = fainted (a dead bench is how "last able
      # mon" positions are built). The ACTIVE mon's hp is re-applied on-field by
      # apply_state, which clamps to >= 1 — only bench mons may be at 0 here.
      if m["hp_pct"]
        pkmn.hp = [(pkmn.totalhp * m["hp_pct"].to_f / 100.0).round, pkmn.totalhp].min
      end
      party.push(pkmn)
    end
    party
  end

  # Apply post-init state that only exists once a battler is on the field.
  def self.apply_state(battler, m)
    if m["hp_pct"]
      hp = (battler.totalhp * m["hp_pct"].to_f / 100.0).round
      hp = 1 if hp < 1
      battler.hp = [hp, battler.totalhp].min
    end
    if m["status"] && STATUS_KEYS[m["status"]]
      battler.status = STATUS_KEYS[m["status"]]
      battler.statusCount = 3 if m["status"] == "sleep"
    end
    (m["stages"] || {}).each do |k, v|
      battler.stages[STAT_KEYS[k]] = v.to_i if STAT_KEYS[k]
    end
    (m["effects"] || {}).each do |k, v|
      eff = EFFECT_KEYS[k]
      raise "unknown effect #{k.inspect}" if !eff
      battler.effects[eff[0]] = (eff[1] == :bool) ? (v.to_i != 0) : v.to_i
    end
    if m["pp_all"]
      battler.moves.each { |mv| mv.pp = m["pp_all"].to_i if mv && mv.id != 0 }
    end
  end

  # Seed the PORTABLE AI's per-battler memory, so a scenario can say "I clicked this
  # move last turn". Paired with effect_tantrum it expresses the whole position the
  # move_memory rule reads: the engine refused this move, and this is what it was.
  #
  # last_move arrives as a numeric move id (make_scenarios resolves the name, same as
  # effect_choiceband) and is converted with the adapter's OWN move_key, so the stored
  # key is byte-identical to what apply_memory would have written in a real battle.
  # The remembered target is the foe this probe just built, which is the only foe there
  # is. No-op when the portable section is not installed.
  def self.seed_portable_memory(battle, index, m)
    return if !m || !m["last_move"]
    return if !defined?(PortableAIReborn)
    memory = battle.instance_variable_get(:@portable_ai_memory) || {}
    foe = battle.battlers[index ^ 1]
    memory[index.to_s] = {
      "last_move" => PortableAIReborn.move_key(m["last_move"].to_i),
      "last_target_species" => (foe ? foe.species : nil),
      "last_type" => "move"
    }
    battle.instance_variable_set(:@portable_ai_memory, memory)
  end

  # Hazards/screens on one half of the field. Raise on unknown keys: a scenario
  # that cannot be built must fail visibly, not probe a different position.
  def self.apply_side_effects(side, spec)
    return if side.nil? || spec.nil?
    spec.each do |k, v|
      eff = SIDE_EFFECT_KEYS[k]
      raise "unknown side effect #{k.inspect}" if !eff
      side.effects[eff[0]] = (eff[1] == :bool) ? (v.to_i != 0) : v.to_i
    end
  end

  def self.parse_side(spec)
    h = {}
    spec.split("|").each do |part|
      k, v = part.split(":", 2)
      h[k.strip] = v.strip.to_i if k && v
    end
    h
  end

  # Scenario file format — deliberately dependency-free (no JSON in RGSS):
  #
  #   [scenario_id]
  #   field=0
  #   ai=species:471|level:50|item:543|moves:243,463|hp_pct:100|stage_atk:2
  #   ai_bench=species:6|level:50|moves:53
  #   player=species:142|level:50|moves:17
  #
  # Assertions live on the Python side (tools/check_scenarios.py) and join by id.
  def self.parse_mon(spec)
    m = {}
    spec.split("|").each do |part|
      k, v = part.split(":", 2)
      next if k.nil? || v.nil?
      k = k.strip; v = v.strip
      case k
      when "moves"
        m["moves"] = v.split(",").map { |x| x.strip.to_i }
      when "status"
        m["status"] = v
      when "hp_pct"
        m["hp_pct"] = v.to_f
      when /\Astage_(.+)\z/
        m["stages"] ||= {}
        m["stages"][$1] = v.to_i
      when /\Aeffect_(.+)\z/
        m["effects"] ||= {}
        m["effects"][$1] = v
      else
        m[k] = v.to_i
      end
    end
    m
  end

  def self.parse_scenarios(path)
    scns = []
    cur  = nil
    File.open(path, "rb") do |f|
      f.read.split(/[\r\n]+/).each do |line|
        line = line.strip
        next if line.empty? || line[0, 1] == "#"
        if line =~ /\A\[(.+)\]\z/
          scns.push(cur) if cur
          cur = { "id" => $1, "field" => 0, "format" => "single",
                  "ai" => { "active" => {}, "bench" => [] },
                  "player" => { "active" => {}, "bench" => [] } }
          next
        end
        next if cur.nil?
        k, v = line.split("=", 2)
        next if k.nil? || v.nil?
        case k.strip
        when "field"      then cur["field"] = v.to_i
        when "format"     then cur["format"] = v.strip
        when "weather"    then cur["weather"] = v.strip
        when "ai_side"     then cur["ai_side"] = parse_side(v)
        when "player_side" then cur["player_side"] = parse_side(v)
        when "ai"         then cur["ai"]["active"] = parse_mon(v)
        when "player"     then cur["player"]["active"] = parse_mon(v)
        when "ai2"        then cur["ai"]["active2"] = parse_mon(v)
        when "player2"    then cur["player"]["active2"] = parse_mon(v)
        when "ai_bench"     then cur["ai"]["bench"].push(parse_mon(v))
        when "player_bench" then cur["player"]["bench"].push(parse_mon(v))
        end
      end
    end
    scns.push(cur) if cur
    scns
  end

  def self.probe(scn)
    scene  = pbNewBattleScene
    aiTr   = PokeBattle_Trainer.new("ProbeAI", 0)
    plTr   = PokeBattle_Trainer.new("ProbePL", 0)
    aiSide = scn["ai"]
    plSide = scn["player"]
    doubles = (scn["format"] == "double")
    if doubles && (aiSide["active2"].nil? || plSide["active2"].nil?)
      raise "format=double needs both ai2= and player2="
    end
    aiParty = build_party(aiSide, aiTr)
    plParty = build_party(plSide, plTr)

    # Field must be set BEFORE construction: PokeBattle_Field#initialize reads
    # $game_variables[:Forced_Field_Effect] (PokeBattle_Field.rb:64) and otherwise derives
    # a field from the map's battleback — with our null map that lands on an arbitrary
    # non-zero field (35), which would silently contaminate every scenario. Reborn's AI
    # branches on the field in 704 places, so this has to be pinned, not left to default.
    fid = (scn["field"] || 0).to_i
    $game_variables[:Forced_Field_Effect] = fid rescue nil

    # party1 = player side, party2 = AI side (matches idontwanttobreakperryscode).
    battle = PokeBattle_Battle.new(scene, plParty, aiParty, plTr, aiTr)
    battle.internalbattle = true
    battle.doublebattle   = doubles
    battle.items  = []
    battle.items2 = []

    # Belt and braces: force the layer too, since field 0 ("no field") cannot be expressed
    # via Forced_Field_Effect — PokeBattle_Field.rb:65 only applies the override when > 0.
    fld = battle.instance_variable_get(:@field)
    if fld
      fld.layer    = [fid]
      fld.effect   = fid
      fld.duration = 0
    end
    pbPrepareBattle(battle)
    battle.scene.pbStartBattle(battle) rescue nil

    # The AI must exist BEFORE pbSendOut: send-out calls @ai.addMonToMemory to populate
    # the knowledge model (PokeBattle_Battle.rb:2021). testAllBattlesSingles builds it
    # first for the same reason.
    $ai_log_data = [PokeBattle_AI_Info.new, PokeBattle_AI_Info.new,
                    PokeBattle_AI_Info.new, PokeBattle_AI_Info.new]
    battle.ai = PokeBattle_AI.new(battle)

    # All four battler objects exist from construction (PokeBattle_Battle.rb:514
    # creates 0..3 unconditionally), so doubles only needs two more send-outs.
    # AI side first, then the player, preserving the singles ordering.
    ai_indices(doubles).each_with_index do |bi, k|
      battle.battlers[bi].pbInitialize(aiParty[k], k, false)
      battle.pbSendOut(bi, aiParty[k])
    end
    foe_indices(doubles).each_with_index do |bi, k|
      battle.battlers[bi].pbInitialize(plParty[k], k, false)
      battle.pbSendOut(bi, plParty[k])
    end
    battle.pbOnActiveAll rescue nil

    apply_state(battle.battlers[1], aiSide["active"])
    apply_state(battle.battlers[0], plSide["active"])
    if doubles
      apply_state(battle.battlers[3], aiSide["active2"])
      apply_state(battle.battlers[2], plSide["active2"])
    end
    seed_portable_memory(battle, 1, aiSide["active"])
    seed_portable_memory(battle, 3, aiSide["active2"]) if doubles

    # Battle-level state. sides[0] = player half (hazards the AI would lay land
    # here), sides[1] = AI half (its own screens). Weather goes on the battle
    # directly — the AI reads it via pbWeather (nobody on the field has Cloud
    # Nine/Air Lock, so pbWeather returns @weather unmodified).
    if scn["weather"]
      w = WEATHER_IDS[scn["weather"]]
      raise "unknown weather #{scn['weather'].inspect}" if !w
      battle.weather         = w
      battle.weatherduration = -1
    end
    apply_side_effects(battle.sides[0], scn["player_side"])
    apply_side_effects(battle.sides[1], scn["ai_side"])

    # Rebuild after state changes so aimondata reflects the final position.
    battle.ai = PokeBattle_AI.new(battle)
    battle.ai.processAIturn

    foes = foe_indices(doubles)
    actors = ai_indices(doubles).map { |bi| actor_record(battle, bi, foes) }
    md = battle.ai.aimondata[1]
    b  = battle.battlers[1]
    # When the Portable AI section is installed AND enabled (Data/portable_ai.txt),
    # its chooseAction hook registered the decisions and left its joint plan on the
    # battle. Label the record and surface the portable score vector so the same
    # grader/differ pipeline reads both AIs' output (mirrors Realidea's AI_Probe).
    plan = (battle.portable_ai_last_plan rescue nil)
    ai_label = plan ? "portable-ai-#{PortableAI::VERSION}+reborn" : "reborn-yang"
    # Top-level keys describe the AI's LEFT battler (index 1) and are a verbatim
    # mirror of actors[0]. In singles that is the only actor and this record is
    # byte-identical to the pre-doubles one, so every existing consumer
    # (check_scenarios.py, ai_diff.py, the archived artifacts) keeps working
    # untouched. Doubles-aware code reads "actors".
    out = {
      "id"      => scn["id"],
      "engine"  => "reborn-yang",
      "ai"      => ai_label,
      "format"  => (doubles ? "double" : "single"),
      "skill"   => (md ? md.skill : nil),
      "field"   => (battle.FE rescue nil),
      # Diagnostic: the weather the AI actually saw, so a weather scenario that
      # failed to apply is distinguishable from an AI that ignored it.
      "weather" => (battle.pbWeather rescue nil),
      "actor"   => { "species" => b.species, "hp_pct" => (b.hp * 100.0 / b.totalhp).round(1) },
      # Diagnostic: the target's RUNTIME ability plus the AI's own typemod verdict per
      # move, so an assertion failure can distinguish "probe built the wrong position"
      # from "the AI scored a position it fully understood" (SIM-SPEC 9.5 rule).
      "target"  => {
        "species" => (battle.battlers[0].species rescue nil),
        "ability" => (battle.battlers[0].ability rescue nil),
        "typemods" => typemods(battle, b, 0)
      },
      "targets" => foes.map { |t|
        { "index" => t,
          "species" => (battle.battlers[t].species rescue nil),
          "ability" => (battle.battlers[t].ability rescue nil) }
      },
      "moves"   => actors[0]["moves"],
      "scores"  => (plan ? actors[0]["moves"].map { |m| m["score"] || 0 } :
                           (md ? md.scorearray[0] : [])),
      "switch_scores"       => actors[0]["switch_scores"],
      "should_switch_score" => actors[0]["should_switch_score"],
      "action"  => actors[0]["action"],
      "actors"  => actors
    }
    out
  end

  # The AI's own type-effectiveness verdict for each of `b`'s moves against one foe.
  def self.typemods(battle, b, foeindex)
    b.moves.map { |mv|
      next nil if mv.nil? || mv.id == 0
      battle.ai.pbTypeModNoMessages(mv.pbType(b), b, battle.battlers[foeindex], mv, 100) rescue "err"
    } rescue nil
  end

  # One decision record per AI-side battler.
  #
  # scorearray is indexed [target][move] even in singles, where only row 0 is
  # populated. So a move's headline "score" is its best over the live foes, and
  # "target" names the foe that produced it — in singles that reduces to
  # scorearray[0][i] exactly, which is what the pre-doubles record emitted.
  # score_matrix keeps the raw per-target rows so a coordination scenario can be
  # read without re-deriving them. NOTE: Reborn appends a 5th entry to each row
  # for the Z-move score (PokeBattle_AI_2.rb:312), which has no move slot — it is
  # visible in score_matrix but deliberately absent from "moves".
  def self.actor_record(battle, index, foes)
    b   = battle.battlers[index]
    md  = battle.ai.aimondata[index]
    ch  = battle.choices[index]
    doubles = foes.length > 1

    # Portable AI path: when the injected section registered this battler's choice,
    # read the normalized plan rankings instead of Reborn's scorearray, exactly as
    # Realidea's AI_Probe does — same downstream schema, different score source.
    plan = (battle.portable_ai_last_plan rescue nil)
    portable_entries = []
    portable_ranking = nil
    if plan && plan["diagnostics"] && plan["diagnostics"]["rankings"]
      plan["diagnostics"]["rankings"].each do |ranking|
        if ranking.any? { |entry| entry["actor_index"] == index }
          portable_ranking = ranking
        end
        ranking.each do |entry|
          next if entry["actor_index"] != index || entry["type"] != "move"
          portable_entries.push({
            "move"   => entry["numeric_move_id"],
            "score"  => entry["score"],
            "target" => (entry["target"].nil? ? -1 : entry["target"])
          })
        end
      end
    end

    matrix = {}
    tmods  = {}
    foes.each do |t|
      matrix[t.to_s] = (md ? (md.scorearray[t] || []) : []) if portable_entries.empty?
      tmods[t.to_s]  = typemods(battle, b, t)
    end
    if !portable_entries.empty?
      portable_entries.each do |e|
        (matrix[e["target"].to_s] ||= {})[e["move"]] = e["score"]
      end
    end
    moves = []
    b.moves.each_with_index do |mv, i|
      next if mv.nil? || mv.id == 0
      best, bestt = nil, nil
      if portable_entries.empty?
        foes.each do |t|
          s = md ? (md.scorearray[t] || [])[i] : nil
          next if s.nil?
          if best.nil? || s > best
            best  = s
            bestt = t
          end
        end
      else
        portable_entries.each do |e|
          next if e["move"] != mv.id
          next if !e["score"]
          if best.nil? || e["score"] > best
            best  = e["score"]
            bestt = (e["target"] >= 0 ? e["target"] : nil)
          end
        end
      end
      moves.push({ "slot" => i, "id" => mv.id, "score" => best, "target" => bestt })
    end
    rec = {
      "index"   => index,
      "species" => b.species,
      "hp_pct"  => (b.hp * 100.0 / b.totalhp).round(1),
      "moves"   => moves,
      "score_matrix" => matrix,
      "typemods"     => tmods,
      "switch_scores"       => (md ? md.switchscore : []),
      "should_switch_score" => (md ? md.shouldswitchscore : nil),
      "action"  => nil
    }
    if portable_ranking
      switch_entries = portable_ranking.select { |entry| entry["type"] == "switch" }
      rec["switch_scores"] = switch_entries.map { |entry| entry["score"] }
      # Mirrors Realidea's portable probe: 1/0 records that switching was weighed
      # (and whether it won); nil means the planner saw no legal switch at all.
      rec["switch_evaluated"] = !switch_entries.empty?
      rec["should_switch_score"] =
        switch_entries.empty? ? nil : ((ch && ch[0] == 2) ? 1 : 0)
    end
    if doubles
      # THE SCORE MATRIX IS NOT WHAT REBORN CHOOSES BY. chooseAction (:1549) feeds
      # the matrix through findChoosableMoves (:1998), which collapses the
      # per-target rows into one score per (move, target set), and the collapse is
      # not a max:
      #   SingleNonUser -> one entry per candidate target, including the PARTNER
      #   AllOpposing   -> scorearray[left] + scorearray[right]   (a sum, not a max)
      #   AllNonUsers   -> that same sum, then multiplied by
      #                    max(1 - 2*scorearray[partner][move]/100, 0), halved
      #                    again when the user is faster and would KO the partner
      # So a spread move that scores >= 50 against its own partner is multiplied to
      # zero and becomes unchooseable no matter how well it does against the foes
      # — which is how Earthquake at 79 loses to Rock Slide at 14. None of that is
      # visible in score_matrix, so the real decision quantity is recorded too;
      # reading a doubles decision from the matrix alone will mislead.
      cm = (battle.ai.send(:findChoosableMoves, b, md) rescue nil)
      rec["chooseable"] = (cm || []).map { |h|
        { "slot" => h[:moveindex], "target" => h[:target],
          "score" => h[:score], "zmove" => h[:zmove] }
      }
    end
    if ch
      case ch[0]
      when 1
        # choices[i][3] is the registered target index, written by pbRegisterTarget
        # (PokeBattle_Battle.rb:1626). Singles never registers one, so it stays at
        # its -1 sentinel and is reported as nil rather than a fake slot.
        rec["action"] = { "type" => "move", "move" => (ch[2] ? ch[2].id : nil),
                          "slot" => ch[1],
                          "target" => (doubles && ch[3] && ch[3] >= 0 ? ch[3] : nil) }
      when 2 then rec["action"] = { "type" => "switch", "slot" => ch[1] }
      when 3 then rec["action"] = { "type" => "item", "item" => ch[1] }
      else        rec["action"] = { "type" => "none", "raw" => ch[0] }
      end
    end
    rec
  end

  def self.jsonify(o)
    case o
    when nil        then "null"
    when true, false then o.to_s
    when Numeric    then o.to_s
    when String     then "\"" + o.gsub("\\", "\\\\\\\\").gsub("\"", "\\\"") + "\""
    when Array      then "[" + o.map { |x| jsonify(x) }.join(",") + "]"
    when Hash       then "{" + o.map { |k, v| jsonify(k.to_s) + ":" + jsonify(v) }.join(",") + "}"
    else                 jsonify(o.to_s)
    end
  end

  def self.run_probe(cfg)
    infile  = cfg["scenarios"] || "Data/ai_scenarios.txt"
    outfile = cfg["out"] || "Data/ai_probe_results.ndjson"
    unless File.exist?(infile)
      echo "AIHarness: scenario file #{infile} not found"
      return
    end
    scns = parse_scenarios(infile)
    echo "AIHarness: probing #{scns.length} scenarios"
    results = []
    scns.each_with_index do |scn, i|
      begin
        r = probe(scn)
        results.push(r)
        act = r["action"] ? r["action"]["type"] : "?"
        echo "  [#{i + 1}/#{scns.length}] #{scn['id']} -> #{act} #{(r['action'] || {}).inspect}"
      rescue Exception => e
        results.push({ "id" => scn["id"], "error" => "#{e.class}: #{e.message}",
                       "backtrace" => e.backtrace.to_a[0, 4] })
        echo "  [#{i + 1}/#{scns.length}] #{scn['id']} -> ERROR #{e.class}: #{e.message}"
      end
    end
    File.open(outfile, "wb") { |f| results.each { |r| f.write(jsonify(r), "\n") } }
    echo "AIHarness: wrote #{results.length} probe results to #{outfile}"
  end

  def self.nameof(t)
    n = pbGetMessageFromHash(MessageTypes::TrainerNames, t[1]) rescue t[1].to_s
    "#{n}##{t[4]}"
  end

  def self.finish(outfile, rows, seed)
    begin
      File.open(outfile, "wb") do |f|
        f.write("idx,trainer_a,trainer_b,a_won,winner,ms,seed\n")
        rows.each { |r| f.write((r + [seed]).join(",") + "\n") }
      end
      wins = rows.count { |r| r[3] == 1 }
      echo "AIHarness: wrote #{rows.length} rows to #{outfile} (A won #{wins})"
    rescue Exception => e
      echo "AIHarness: FAILED to write #{outfile}: #{e.message}"
    end
    echo "AIHarness: done. Delete #{TRIGGER} to boot normally again."
  end

  def self.echo(msg)
    $stdout.print(msg, "\n") rescue nil
    $stdout.flush rescue nil
    PBDebug.log(msg) rescue nil
  end
end
