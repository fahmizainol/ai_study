#===============================================================================
# AI_Probe — decision probe for Realidea (Essentials v16, stock-derived AI).
#
# SIM-SPEC.md §6 adapter. Scores a constructed position WITHOUT advancing the turn
# and writes one canonical §4 record per scenario as newline-delimited JSON.
#
# OPT-IN: does nothing unless Data/ai_probe.txt exists.
#
#-------------------------------------------------------------------------------
# WHICH pbChooseMoves ACTUALLY RUNS
#
# NOT the one in `085_PokeBattle_AI.rb`. Section `275_AI edit clara` reopens
# PokeBattle_Battle and redefines pbChooseMoves wholesale, and it loads 190 sections
# later, so it wins. (Its own header says "Colocar sobre script Main".) Anything
# concluded from 085's copy is about dead code — the same class of mistake as reading
# Ashen Frost's plugin folder instead of its compiled bundle.
#
# WHERE THE SCORES COME FROM
#
# Both copies share the shape the probe depends on:
#     scores[i] = pbGetMoveScore(...)      <- init vector, one call per move
#     ... skill-gated minmax compression   <- final vector
#     if $INTERNAL ... PBDebug.log         <- their own log point
#     ... pbAIRandom(totalscore)           <- SELECTION starts here
#
# So scoring and selection are separable without touching their code: alias
# pbGetMoveScore to capture the init vector, then let pbDefaultChooseEnemyCommand run
# to completion and read @choices[index] for the action. Registering a choice does not
# advance the turn — the same thing Reborn's probe does.
#
# `score_final` is DERIVED here, not observed: the minmax pass compresses a local
# variable that nothing exposes. It is recomputed from the init vector using the exact
# thresholds at 275_AI edit clara.rb:129-141, and is marked derived in the record so it
# is never mistaken for a reading.
#===============================================================================

class AIProbeNullScene
  attr_reader :seen
  def initialize; @seen = {}; end
  def method_missing(name, *args)
    @seen[name.to_s] = (@seen[name.to_s] || 0) + 1
    nil
  end
  def respond_to_missing?(*_a); true; end
end

class AIProbeNullMap
  def terrain_tag(*_a); 0; end
  def map_id; 1; end
  def events; {}; end
  def width; 20; end
  def height; 20; end
  def valid?(*_a); true; end
end

module AIProbe
  TRIGGER   = "Data/ai_probe.txt"
  SCENARIOS = "Data/ai_scenarios.txt"
  OUT       = "Data/ai_probe_results.ndjson"
  OUT_STOCK = "Data/ai_probe_results_stock.ndjson"
  OUT_PORTABLE = "Data/ai_probe_results_portable.ndjson"
  ERRLOG    = "Data/ai_probe_error.txt"

  def self.requested?
    if defined?(PortableAIGauntlet) && PortableAIGauntlet.requested?
      return true
    end
    return File.exist?(TRIGGER)
  rescue
    return false
  end

  def self.result_path
    if defined?(PortableAIRealidea) && PortableAIRealidea.requested?
      return OUT_PORTABLE
    end
    OUT_STOCK
  rescue
    OUT
  end

  # --- JSON (no JSON library in RGSS) ---------------------------------------
  def self.jstr(s)
    return '"' + s.to_s.gsub(/[\\"]/) { |m| "\\" + m }.gsub("\n", "\\n").gsub("\r", "") + '"'
  end

  def self.json(o)
    case o
    when Hash  then return "{" + o.map { |k, v| jstr(k) + ":" + json(v) }.join(",") + "}"
    when Array then return "[" + o.map { |v| json(v) }.join(",") + "]"
    when NilClass then return "null"
    when TrueClass, FalseClass then return o.to_s
    when Float
      return "null" if o.nan? || o.infinite?
      return o.to_s
    when Integer then return o.to_s
    else return jstr(o)
    end
  end

  # This engine's Ruby has 1.8 semantics: Float#round takes NO argument, so `.round(1)`
  # raises "wrong number of arguments (1 for 0)". Do the rounding by hand.
  def self.pct(x)
    return ((x * 10).round) / 10.0
  end

  # --- boot -----------------------------------------------------------------
  def self.bootstrap
    $game_temp     = Game_Temp.new
    $game_system   = Game_System.new   rescue nil
    $game_switches = Game_Switches.new
    $game_variables = Game_Variables.new
    $game_self_switches = Game_SelfSwitches.new rescue nil
    $game_screen   = Game_Screen.new   rescue nil
    $game_map      = AIProbeNullMap.new
    $PokemonTemp   = PokemonTemp.new   rescue nil
    $PokemonGlobal = PokemonGlobalMetadata.new rescue nil
    $PokemonBag    = PokemonBag.new    rescue nil
    $PokemonSystem = PokemonSystem.new rescue nil
    $Trainer       = PokeBattle_Trainer.new("Probe", 0) if $Trainer.nil?
    $data_animations = pbLoadRxData("Data/Animations") rescue nil
    # Item data is read by the load and save screens in normal play, which a save-less
    # harness never opens, so nothing here had ever loaded it. That went unnoticed for
    # as long as no fixture Pokemon held an item -- but $ItemData[x] on nil raises
    # inside pbIsBerry? (PItem_Items.rb:63), which pbGetMoveScore calls whenever it
    # scores Bug Bite or Pluck at high skill, and the gauntlet trainer's skill is 100.
    # The line that used to be here asked for pbLoadItems, which is a later Essentials'
    # name and does not exist in v16, so its rescue swallowed a NameError and kept the
    # nil. See install_exception_capture for why that crash looked like a hang.
    begin
      $ItemData = readItemList("Data/items.dat") if !$ItemData
    rescue
      nil
    end
  end

  # Realidea runs pbCommandPhase and pbAttackPhase inside PBDebug.logonerr, whose
  # guard around pbPrintException is commented out (PBDebug.rb:11-13), and
  # pbPrintException ends in RGSS's print -- a modal box. So an exception in either
  # phase is caught by that rescue, never reaches run_one's, and leaves the process
  # parked in the window message pump at ~0.015 CPU-seconds per five wall seconds with
  # an empty results file and nothing written anywhere. Re-raising puts it back where
  # the harness can record it and move to the next battle. The exception text still
  # reaches the game's own errorlog.txt first, so nothing is lost.
  def self.install_exception_capture
    return if @exception_capture
    @exception_capture = true
    Object.class_eval do
      def pbPrintException(error)
        raise error
      end
    end
  rescue Exception
    @exception_capture = false
  end

  # --- score capture --------------------------------------------------------
  def self.install_capture
    return if @installed
    @installed = true
    PokeBattle_Battle.class_eval do
      alias aiprobe_pbGetMoveScore pbGetMoveScore
      def pbGetMoveScore(move, attacker, opponent, skill = 100)
        s = aiprobe_pbGetMoveScore(move, attacker, opponent, skill)
        if $aiprobe && $aiprobe[:on] && attacker && attacker.index == $aiprobe[:idx]
          # target is recorded so doubles can keep a per-target matrix; in singles
          # every entry carries the same lone opponent index and it collapses away.
          $aiprobe[:init].push({ "move" => (move.id rescue 0), "score" => s,
                                 "target" => (opponent ? opponent.index : -1) })
        end
        return s
      end

      # v16 switching is a PREDICATE, not a score: pbEnemyShouldWithdrawEx? returns
      # true/false (085:4116). There is no numeric analogue of Reborn's
      # shouldswitchscore, so the canonical field is filled with a three-state value —
      # 1 = evaluated and chose to switch, 0 = evaluated and declined, null = never
      # evaluated at all. That distinction is the whole point of `must_consider_switch`:
      # leaving it null unconditionally (as this adapter first did) reports "never
      # considered switching" for an AI that considered it every single turn.
      alias aiprobe_pbEnemyShouldWithdrawEx pbEnemyShouldWithdrawEx?
      def pbEnemyShouldWithdrawEx?(index, alwaysSwitch)
        r = aiprobe_pbEnemyShouldWithdrawEx(index, alwaysSwitch)
        if $aiprobe && $aiprobe[:on] && index == $aiprobe[:idx]
          $aiprobe[:switch_evaluated] = true
          $aiprobe[:switch_decision] = r ? 1 : 0
        end
        return r
      end
    end
  end

  # Mirror of the minmax compression at 275_AI edit clara.rb:129-141. DERIVED, not read.
  def self.derive_final(scores, skill)
    return scores.clone if skill < PBTrainerAI.mediumSkill
    threshold = (skill >= PBTrainerAI.bestSkill) ? 1.5 : (skill >= PBTrainerAI.highSkill) ? 2 : 3
    newscore  = (skill >= PBTrainerAI.bestSkill) ? 5 : (skill >= PBTrainerAI.highSkill) ? 10 : 15
    maxscore = 0
    scores.each { |s| maxscore = s if s && s > maxscore }
    out = scores.clone
    for i in 0...out.length
      if out[i] > newscore && out[i] * threshold < maxscore
        out[i] = newscore
      end
    end
    return out
  end

  # --- scenario file (shared format with the other adapters) ----------------
  def self.parse_mon(spec)
    m = {}
    spec.split("|").each do |part|
      k, v = part.split(":", 2)
      next if k.nil? || v.nil?
      k = k.strip; v = v.strip
      case k
      when "moves"  then m["moves"] = v.split(",").map { |x| x.strip.to_i }
      when "status" then m["status"] = v
      when "hp_pct" then m["hp_pct"] = v.to_f
      when /\Astage_(.+)\z/
        m["stages"] ||= {}
        m["stages"][$1] = v.to_i
      when /\Aeffect_(.+)\z/
        m["effects"] ||= {}
        m["effects"][$1] = v
      else m[k] = v.to_i
      end
    end
    return m
  end

  def self.parse_scenarios(path)
    scns = []
    cur = nil
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
        when "field"        then cur["field"] = v.to_i
        when "format"       then cur["format"] = v.strip
        when "weather"      then cur["weather"] = v.strip
        when "ai_side"      then cur["ai_side"] = parse_side(v)
        when "player_side"  then cur["player_side"] = parse_side(v)
        when "ai"           then cur["ai"]["active"] = parse_mon(v)
        when "player"       then cur["player"]["active"] = parse_mon(v)
        when "ai2"          then cur["ai"]["active2"] = parse_mon(v)
        when "player2"      then cur["player"]["active2"] = parse_mon(v)
        when "ai_bench"     then cur["ai"]["bench"].push(parse_mon(v))
        when "player_bench" then cur["player"]["bench"].push(parse_mon(v))
        end
      end
    end
    scns.push(cur) if cur
    return scns
  end

  # --- party ----------------------------------------------------------------
  STATUS_KEYS = {
    "sleep" => PBStatuses::SLEEP, "poison" => PBStatuses::POISON,
    "burn" => PBStatuses::BURN, "paralysis" => PBStatuses::PARALYSIS,
    "frozen" => PBStatuses::FROZEN
  }
  STAT_KEYS = {
    "atk" => PBStats::ATTACK, "def" => PBStats::DEFENSE,
    "spa" => PBStats::SPATK,  "spd" => PBStats::SPDEF,
    "spe" => PBStats::SPEED,  "acc" => PBStats::ACCURACY,
    "eva" => PBStats::EVASION
  }

  # ev_* scenario keys -> @ev array indices (iv/ev arrays are ordered by PBStats).
  EV_KEYS = {
    "hp"  => 0, "atk" => 1, "def" => 2, "spe" => 3, "spa" => 4, "spd" => 5
  }
  # Battler-effect keys (effect_*) -> [PBEffects index, kind]. Same layout as
  # the Reborn harness; choiceband arrives as a numeric move ID.
  EFFECT_KEYS = {
    "perishsong" => [PBEffects::PerishSong, :int],
    "leechseed"  => [PBEffects::LeechSeed,  :int],
    "confusion"  => [PBEffects::Confusion,  :int],
    "toxic"      => [PBEffects::Toxic,      :int],
    "yawn"       => [PBEffects::Yawn,       :int],
    "substitute" => [PBEffects::Substitute, :int],
    "curse"      => [PBEffects::Curse,      :bool],
    "choiceband" => [PBEffects::ChoiceBand, :int],
    "wish"       => [PBEffects::Wish,       :int]
  }

  # Scenarios that pin a mechanic this engine does not have. Running them anyway would
  # compare two different positions and blame the AI for the difference (SIM-SPEC §10),
  # which is the same reason a Reborn field id is skipped rather than zeroed.
  UNSUPPORTED = {
    # PBEffects::LastMoveFailed is declared in the MOVE-USAGE namespace as 4
    # (075_PBEffects.rb:170), which is the same index as the BATTLER effect BideDamage
    # (:8). The battler's copy is initialised to false (080:415) and NOTHING in the
    # build ever sets it true -- the only writes to index 4 are Bide's damage
    # accumulator. So Stomping Tantrum's own doubling is dead code here, and there is
    # no readable "this move failed last turn" flag for the adapter to export. Reborn's
    # PBEffects::Tantrum has no equivalent, and successStates[i].useState is not one:
    # it is set to 2 only on the damaging path (080:3223), so a status move that
    # worked perfectly reads back as 1 = failed.
    "a_move_that_failed_last_turn_is_not_re_clicked" =>
      "no readable move-failure flag: PBEffects::LastMoveFailed (075:170) collides " +
      "with BideDamage and is never set true",
    "a_move_that_worked_last_turn_is_still_clicked" =>
      "pair control for a_move_that_failed_last_turn_is_not_re_clicked; the memory it " +
      "varies cannot be read here",
    # Prankster is a priority modifier and nothing else in this build (084:1108,
    # 080:2618). No Dark-type immunity to it exists anywhere, so a Prankster status
    # move into a Dark type lands and the card is asserting the opposite engine.
    "prankster_status_fails_vs_dark" =>
      "Prankster is a priority modifier only here (084:1108); Dark types are not " +
      "immune to it"
  }

  # Why this scenario cannot be probed here, or nil. Checked before anything is built,
  # so an unbuildable card reports SKIP with a reason rather than ERR with a backtrace.
  def self.unsupported_reason(scn)
    if scn["field"].to_i != 0
      return "scenario pins Reborn field #{scn['field']}; no equivalent here"
    end
    named = UNSUPPORTED[scn["id"]]
    return named if named
    ["ai", "player"].each do |side|
      entries = [scn[side]["active"], scn[side]["active2"]]
      entries += (scn[side]["bench"] || [])
      entries.each do |m|
        next if !m
        (m["effects"] || {}).each_key do |k|
          if !EFFECT_KEYS[k]
            return "scenario sets effect #{k}, which has no equivalent in this engine"
          end
        end
      end
    end
    return nil
  end

  # Scenario weather names -> stock-v16 PBWeather constants.
  WEATHER_IDS = {
    "rain" => PBWeather::RAINDANCE, "sun" => PBWeather::SUNNYDAY,
    "sand" => PBWeather::SANDSTORM, "hail" => PBWeather::HAIL
  }
  # Side-effect keys -> [PBEffects index, kind]. Stock v16 matches Reborn here:
  # StealthRock is boolean, the others are layer/round ints.
  SIDE_EFFECT_KEYS = {
    "spikes"      => [PBEffects::Spikes,      :int],
    "toxicspikes" => [PBEffects::ToxicSpikes, :int],
    "stealthrock" => [PBEffects::StealthRock, :bool],
    "reflect"     => [PBEffects::Reflect,     :int],
    "lightscreen" => [PBEffects::LightScreen, :int]
  }

  def self.parse_side(spec)
    h = {}
    spec.split("|").each do |part|
      k, v = part.split(":", 2)
      h[k.strip] = v.strip.to_i if k && v
    end
    return h
  end

  # Hazards/screens on one half of the field. Raise on unknown keys: a scenario
  # that cannot be built must fail visibly, not probe a different position.
  def self.apply_side_effects(side, spec)
    return if side.nil? || spec.nil?
    spec.each do |k, v|
      eff = SIDE_EFFECT_KEYS[k]
      raise "unknown side effect #{k.inspect}" if !eff
      side.effects[eff[0]] = (eff[1] == :bool) ? (v != 0) : v
    end
  end

  def self.build_mon(m, owner)
    pkmn = PokeBattle_Pokemon.new(m["species"], (m["level"] || 50), owner)
    if m["moves"] && m["moves"].length > 0
      for k in 0...4
        pkmn.moves[k] = PBMove.new(m["moves"][k] || 0)
      end
    end
    pkmn.setItem(m["item"]) if m["item"] && m["item"] > 0
    # Determinism: an unpinned Pokemon rolls nature and ability slot from personalID,
    # so the same scenario could probe with different stats on different runs. Pin both
    # (HARDY / slot 0) unless the scenario specifies. RAISE if this v16 build has no
    # setter — a scenario that cannot be pinned must fail loudly, not run on random
    # stats (same lesson as the silently-unapplied Hegemony status, SIM-SPEC 9.5).
    nat = m["nature"] || 0   # 0 = HARDY, standard nature order
    if pkmn.respond_to?(:setNature)
      pkmn.setNature(nat)
    elsif pkmn.respond_to?(:natureflag=)
      pkmn.natureflag = nat
    else
      raise "cannot pin nature: no setNature/natureflag= on this build"
    end
    abil = m["ability"] || 0
    if pkmn.respond_to?(:setAbility)
      pkmn.setAbility(abil)
    elsif pkmn.respond_to?(:abilityflag=)
      pkmn.abilityflag = abil
    else
      raise "cannot pin ability: no setAbility/abilityflag= on this build"
    end
    for i in 0...6
      pkmn.iv[i] = 31
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
      pkmn.hp = [(pkmn.totalhp * m["hp_pct"] / 100.0).round, pkmn.totalhp].min
    end
    return pkmn
  end

  # Battler index layout, identical in all three engines: even = player side, odd =
  # AI side. Singles occupies 0/1; doubles adds 2 (player right) and 3 (AI right).
  # Party order must match — second active = party slot 1, bench from 2.
  def self.ai_indices(doubles);  return doubles ? [1, 3] : [1]; end
  def self.foe_indices(doubles); return doubles ? [0, 2] : [0]; end

  def self.build_party(side, owner)
    entries = [side["active"]]
    entries.push(side["active2"]) if side["active2"]
    entries += (side["bench"] || [])
    return entries.map { |m| build_mon(m, owner) }
  end

  def self.apply_state(b, m)
    return if b.nil? || m.nil?
    if m["hp_pct"]
      hp = (b.totalhp * m["hp_pct"] / 100.0).round
      hp = 1 if hp < 1
      hp = b.totalhp if hp > b.totalhp
      b.hp = hp
    end
    if m["status"] && STATUS_KEYS[m["status"]]
      b.status = STATUS_KEYS[m["status"]]
      b.statusCount = 3 if m["status"] == "sleep"
    end
    (m["stages"] || {}).each do |k, v|
      b.stages[STAT_KEYS[k]] = v if STAT_KEYS[k]
    end
    (m["effects"] || {}).each do |k, v|
      eff = EFFECT_KEYS[k]
      raise "unknown effect #{k.inspect}" if !eff
      b.effects[eff[0]] = (eff[1] == :bool) ? (v.to_i != 0) : v.to_i
    end
    if m["pp_all"]
      b.moves.each { |mv| mv.pp = m["pp_all"].to_i if mv && mv.id != 0 }
    end
  end

  # --- probe ----------------------------------------------------------------
  def self.probe(scn)
    reason = unsupported_reason(scn)
    if reason
      return { "id" => scn["id"], "engine" => "realidea", "skipped" => true,
               "reason" => reason }
    end

    aiTr = PokeBattle_Trainer.new("ProbeAI", 0)
    plTr = PokeBattle_Trainer.new("ProbePL", 0)
    # Trainer#skill reads trainertypes.dat by trainer type (113_PokeBattle_Trainer.rb:81),
    # so a type-0 stand-in would inherit whatever that entry happens to hold. Pin it to
    # max instead: skill gates the minmax pass and many score branches, and the corpus is
    # specified at skill 100.
    def aiTr.skill; 100; end
    def plTr.skill; 100; end

    doubles = (scn["format"] == "double")
    if doubles && (scn["ai"]["active2"].nil? || scn["player"]["active2"].nil?)
      raise "format=double needs both ai2= and player2="
    end
    aiParty = build_party(scn["ai"], aiTr)
    plParty = build_party(scn["player"], plTr)

    scene = AIProbeNullScene.new
    # party1 = player side (even indices), party2 = AI side (odd).
    battle = PokeBattle_Battle.new(scene, plParty, aiParty, plTr, aiTr)
    battle.internalbattle = true
    battle.doublebattle = doubles
    (battle.items = []) rescue nil

    foe_indices(doubles).each_with_index do |bi, k|
      battle.battlers[bi].pbInitialize(plParty[k], k, false)
      battle.pbSendOut(bi, plParty[k]) rescue nil
    end
    ai_indices(doubles).each_with_index do |bi, k|
      battle.battlers[bi].pbInitialize(aiParty[k], k, false)
      battle.pbSendOut(bi, aiParty[k]) rescue nil
    end
    battle.pbOnActiveAll rescue nil

    apply_state(battle.battlers[0], scn["player"]["active"])
    apply_state(battle.battlers[1], scn["ai"]["active"])
    if doubles
      apply_state(battle.battlers[2], scn["player"]["active2"])
      apply_state(battle.battlers[3], scn["ai"]["active2"])
    end

    # Battle-level state. sides[0] = player half, sides[1] = AI half.
    if scn["weather"]
      w = WEATHER_IDS[scn["weather"]]
      raise "unknown weather #{scn['weather'].inspect}" if !w
      battle.weather = w
      (battle.weatherduration = -1) rescue nil
    end
    apply_side_effects(battle.sides[0], scn["player_side"])
    apply_side_effects(battle.sides[1], scn["ai_side"])

    foes = foe_indices(doubles)
    actors = ai_indices(doubles).map { |bi| run_actor(battle, bi, foes) }
    b = battle.battlers[1]
    portable_plan = (battle.portable_ai_last_plan rescue nil)
    ai_label = portable_plan ? "portable-ai-#{PortableAI::VERSION}+realidea" : "stock-v16+clara"

    # Top-level keys mirror actors[0] (the AI's LEFT battler), so singles records
    # keep their pre-doubles shape and existing consumers work untouched.
    out = {
      "id"     => scn["id"],
      "engine" => "realidea",
      "ai"     => ai_label,
      "format" => (doubles ? "double" : "single"),
      "skill"  => 100,
      "field"  => nil,
      "actor"  => { "species" => b.species,
                    "hp_pct"  => pct(b.hp * 100.0 / b.totalhp) },
      "target" => { "species" => (battle.battlers[0].species rescue nil),
                    "status"  => (battle.battlers[0].status rescue nil),
                    "hp_pct"  => (pct(battle.battlers[0].hp * 100.0 /
                                       battle.battlers[0].totalhp) rescue nil) },
      "targets" => foes.map { |t|
        { "index"   => t,
          "species" => (battle.battlers[t].species rescue nil),
          "status"  => (battle.battlers[t].status rescue nil),
          "hp_pct"  => (pct(battle.battlers[t].hp * 100.0 /
                            battle.battlers[t].totalhp) rescue nil) }
      },
      "moves"  => actors[0]["moves"],
      "scores" => actors[0]["scores"],
      "score_final_derived" => actors[0]["score_final_derived"],
      "switch_scores"       => [],
      "should_switch_score" => actors[0]["should_switch_score"],
      "switch_evaluated"    => actors[0]["switch_evaluated"],
      "action" => actors[0]["action"],
      "actors" => actors
    }

    # Which build and which run-level ablation produced this record. Without both, a
    # results file cannot be told apart from one written by a different arm.
    out["portable_version"] = PortableAI::VERSION if defined?(PortableAI::VERSION)
    if defined?(PortableAIRealidea)
      overrides = (PortableAIRealidea.config_overrides rescue {})
      out["config_overrides"] = overrides if overrides && !overrides.empty?
    end
    sc = scene.seen.keys.sort
    out["scene_calls"] = sc if sc.length > 0
    return out
  end

  # One decision record per AI-side battler. In doubles this runs once per battler
  # in index order, which is what the real command phase does — v16 calls
  # pbDefaultChooseEnemyCommand per battler, and this engine's AI keeps no
  # cross-battler turn state, so the calls are independent.
  def self.run_actor(battle, bi, foes)
    doubles = foes.length > 1
    $aiprobe = { :on => true, :idx => bi, :init => [],
                 :switch_evaluated => false, :switch_decision => nil }
    begin
      battle.pbDefaultChooseEnemyCommand(bi)
    ensure
      $aiprobe[:on] = false
    end

    b = battle.battlers[bi]
    # The portable doubles planner scores both AI battlers on the first command call and
    # caches the joint plan. The second actor therefore makes no fresh pbGetMoveScore
    # calls. Read the planner's normalized rankings when present; otherwise retain the
    # stock alias-capture path.
    portable_entries = []
    portable_ranking = nil
    plan = (battle.portable_ai_last_plan rescue nil)
    if plan && plan["diagnostics"] && plan["diagnostics"]["rankings"]
      plan["diagnostics"]["rankings"].each do |ranking|
        if ranking.any? { |entry| entry["actor_index"] == bi }
          portable_ranking = ranking
        end
        ranking.each do |entry|
          if entry["actor_index"] == bi && entry["type"] == "move"
            portable_entries.push({
              "move" => entry["numeric_move_id"],
              "score" => entry["score"],
              "target" => (entry["target"].nil? ? -1 : entry["target"])
            })
          end
        end
      end
    end
    captured = portable_entries.empty? ? $aiprobe[:init] : portable_entries
    matrix = {}
    best   = {}
    captured.each do |e|
      t = e["target"]
      (matrix[t.to_s] ||= {})[e["move"]] = e["score"]
      next if e["score"].nil?
      cur = best[e["move"]]
      best[e["move"]] = [e["score"], t] if cur.nil? || e["score"] > cur[0]
    end
    moves = []
    raw = []
    b.moves.each_with_index do |mv, i|
      next if mv.nil? || mv.id == 0
      rec = best[mv.id]
      sc = rec ? rec[0] : nil
      moves.push({ "slot" => i, "id" => mv.id, "score" => sc,
                   "target" => (doubles && rec ? rec[1] : nil) })
      raw.push(sc || 0)
    end

    out = {
      "index"   => bi,
      "species" => b.species,
      "hp_pct"  => pct(b.hp * 100.0 / b.totalhp),
      "moves"   => moves,
      "scores"  => raw,
      "score_matrix" => matrix,
      "score_final_derived" => (portable_entries.empty? ? derive_final(raw, 100) : raw.clone),
      "should_switch_score" => ($aiprobe[:switch_evaluated] ? $aiprobe[:switch_decision] : nil),
      "switch_evaluated"    => $aiprobe[:switch_evaluated],
      "action"  => nil
    }
    ch = battle.choices[bi]
    if ch
      case ch[0]
      when 1
        # choices[i][3] is the registered target, written by pbRegisterTarget.
        # Singles never registers one, so it stays at its -1 sentinel.
        out["action"] = { "type" => "move", "move" => (ch[2] ? ch[2].id : nil),
                          "slot" => ch[1],
                          "target" => (doubles && ch[3] && ch[3] >= 0 ? ch[3] : nil) }
      when 2 then out["action"] = { "type" => "switch", "slot" => ch[1] }
      when 3 then out["action"] = { "type" => "item", "item" => ch[1] }
      else        out["action"] = { "type" => "none", "raw" => ch[0] }
      end
    end
    if portable_ranking
      switch_considered = portable_ranking.any? { |entry| entry["type"] == "switch" }
      out["switch_evaluated"] = switch_considered
      out["should_switch_score"] = switch_considered ? ((ch && ch[0] == 2) ? 1 : 0) : nil
      # Every option with its score and reasons, the same readout the gauntlet's trace
      # carries. Without it a failed card says WHAT was chosen and nothing about why,
      # and the first 0.6.3 probe run spent a rebuild finding out that a switch
      # candidate's race had never been computed.
      out["ranking"] = portable_ranking.map { |entry| ranking_entry(entry) }
      # 0.6.5. The party x party grid the sole_answer and setup_matrix rules read, in
      # the compact form the gauntlet trace carries. A card that fails on one of those
      # rules is unreadable without it: the ranking says a candidate lost 300 points
      # and only the grid says which two foes it was the last answer to. Absent on a
      # run with party_matrix off, exactly as the snapshot key is.
      grid = party_matrix_record(battle)
      out["party_matrix"] = grid if grid
    end
    return out
  end

  def self.party_matrix_record(battle)
    return nil if !defined?(PortableAIRealidea)
    snapshot = (battle.portable_ai_last_snapshot rescue nil)
    return nil if !snapshot || !snapshot["matrix"]
    PortableAIRealidea.matrix_trace(snapshot)
  rescue
    nil
  end

  RANKING_KEYS = %w[
    type slot move_id numeric_move_id target species score reasons
    expected_damage_pct effectiveness immune priority
    candidate_hp_pct entry_damage_pct incoming_damage_pct outgoing_damage_pct faster
  ]

  def self.ranking_entry(entry)
    out = {}
    RANKING_KEYS.each { |key| out[key] = entry[key] if entry.has_key?(key) }
    out
  end

  def self.run
    if defined?(PortableAIGauntlet) && PortableAIGauntlet.requested?
      return PortableAIGauntlet.run
    end
    # Same Data/ai_harness.txt overrides the gauntlet honours, so one table row can be
    # ablated against the corpus without a four-minute battle run. The probe is a
    # separate script section that loads BEFORE Portable_AI, so the module is resolved
    # here at call time rather than at load time.
    if defined?(PortableAIRealidea) && defined?(PortableAIRealidea::Harness)
      return PortableAIRealidea::Harness.with_config { run_scenarios }
    end
    run_scenarios
  end

  def self.run_scenarios
    bootstrap
    install_capture
    scns = parse_scenarios(SCENARIOS)
    ok = 0; err = 0; skip = 0
    File.open(result_path, "wb") do |f|
      scns.each do |scn|
        begin
          rec = probe(scn)
          rec["skipped"] ? skip += 1 : ok += 1
          f.write(json(rec) + "\n")
        rescue Exception => e
          err += 1
          f.write(json({ "id" => scn["id"], "engine" => "realidea",
                         "error" => "#{e.class}: #{e.message}",
                         "where" => (e.backtrace ? e.backtrace[0, 4].join(" | ") : nil)
                       }) + "\n")
        end
        f.flush
      end
    end
    File.open(ERRLOG, "wb") do |f|
      f.write("scenarios=#{scns.length} probed=#{ok} skipped=#{skip} errored=#{err}\n")
    end
  end
end
