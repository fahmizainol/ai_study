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
  ERRLOG    = "Data/ai_probe_error.txt"

  def self.requested?
    return File.exist?(TRIGGER)
  rescue
    return false
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
    $ItemData = pbLoadItems rescue $ItemData
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
          $aiprobe[:init].push({ "move" => (move.id rescue 0), "score" => s })
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
          cur = { "id" => $1, "field" => 0,
                  "ai" => { "active" => {}, "bench" => [] },
                  "player" => { "active" => {}, "bench" => [] } }
          next
        end
        next if cur.nil?
        k, v = line.split("=", 2)
        next if k.nil? || v.nil?
        case k.strip
        when "field"        then cur["field"] = v.to_i
        when "weather"      then cur["weather"] = v.strip
        when "ai_side"      then cur["ai_side"] = parse_side(v)
        when "player_side"  then cur["player_side"] = parse_side(v)
        when "ai"           then cur["ai"]["active"] = parse_mon(v)
        when "player"       then cur["player"]["active"] = parse_mon(v)
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
    "choiceband" => [PBEffects::ChoiceBand, :int]
  }

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

  def self.build_party(side, owner)
    entries = [side["active"]] + (side["bench"] || [])
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
    # Reborn field IDs have no Realidea equivalent; running them anyway would compare
    # two different positions and blame the AI for the difference (SIM-SPEC §10).
    if scn["field"].to_i != 0
      return { "id" => scn["id"], "engine" => "realidea", "skipped" => true,
               "reason" => "scenario pins Reborn field #{scn['field']}; no equivalent here" }
    end

    aiTr = PokeBattle_Trainer.new("ProbeAI", 0)
    plTr = PokeBattle_Trainer.new("ProbePL", 0)
    # Trainer#skill reads trainertypes.dat by trainer type (113_PokeBattle_Trainer.rb:81),
    # so a type-0 stand-in would inherit whatever that entry happens to hold. Pin it to
    # max instead: skill gates the minmax pass and many score branches, and the corpus is
    # specified at skill 100.
    def aiTr.skill; 100; end
    def plTr.skill; 100; end

    aiParty = build_party(scn["ai"], aiTr)
    plParty = build_party(scn["player"], plTr)

    scene = AIProbeNullScene.new
    # party1 = player side (even indices), party2 = AI side (odd).
    battle = PokeBattle_Battle.new(scene, plParty, aiParty, plTr, aiTr)
    battle.internalbattle = true
    battle.doublebattle = false
    (battle.items = []) rescue nil

    battle.battlers[0].pbInitialize(plParty[0], 0, false)
    battle.pbSendOut(0, plParty[0]) rescue nil
    battle.battlers[1].pbInitialize(aiParty[0], 0, false)
    battle.pbSendOut(1, aiParty[0]) rescue nil
    battle.pbOnActiveAll rescue nil

    apply_state(battle.battlers[0], scn["player"]["active"])
    apply_state(battle.battlers[1], scn["ai"]["active"])

    # Battle-level state. sides[0] = player half, sides[1] = AI half.
    if scn["weather"]
      w = WEATHER_IDS[scn["weather"]]
      raise "unknown weather #{scn['weather'].inspect}" if !w
      battle.weather = w
      (battle.weatherduration = -1) rescue nil
    end
    apply_side_effects(battle.sides[0], scn["player_side"])
    apply_side_effects(battle.sides[1], scn["ai_side"])

    $aiprobe = { :on => true, :idx => 1, :init => [],
                 :switch_evaluated => false, :switch_decision => nil }
    begin
      battle.pbDefaultChooseEnemyCommand(1)
    ensure
      $aiprobe[:on] = false
    end

    b = battle.battlers[1]
    best = {}
    $aiprobe[:init].each do |e|
      cur = best[e["move"]]
      best[e["move"]] = e if cur.nil? || (e["score"] && cur["score"] && e["score"] > cur["score"])
    end
    moves = []
    raw = []
    b.moves.each_with_index do |mv, i|
      next if mv.nil? || mv.id == 0
      rec = best[mv.id]
      sc = rec ? rec["score"] : nil
      moves.push({ "slot" => i, "id" => mv.id, "score" => sc })
      raw.push(sc || 0)
    end

    out = {
      "id"     => scn["id"],
      "engine" => "realidea",
      "ai"     => "stock-v16+clara",
      "skill"  => 100,
      "field"  => nil,
      "actor"  => { "species" => b.species,
                    "hp_pct"  => pct(b.hp * 100.0 / b.totalhp) },
      "target" => { "species" => (battle.battlers[0].species rescue nil),
                    "status"  => (battle.battlers[0].status rescue nil),
                    "hp_pct"  => (pct(battle.battlers[0].hp * 100.0 /
                                       battle.battlers[0].totalhp) rescue nil) },
      "moves"  => moves,
      "scores" => raw,
      "score_final_derived" => derive_final(raw, 100),
      "switch_scores"       => [],
      "should_switch_score" => ($aiprobe[:switch_evaluated] ? $aiprobe[:switch_decision] : nil),
      "switch_evaluated"    => $aiprobe[:switch_evaluated],
      "action" => nil
    }

    ch = battle.choices[1]
    if ch
      case ch[0]
      when 1 then out["action"] = { "type" => "move",
                                    "move" => (ch[2] ? ch[2].id : nil), "slot" => ch[1] }
      when 2 then out["action"] = { "type" => "switch", "slot" => ch[1] }
      when 3 then out["action"] = { "type" => "item", "item" => ch[1] }
      else        out["action"] = { "type" => "none", "raw" => ch[0] }
      end
    end
    sc = scene.seen.keys.sort
    out["scene_calls"] = sc if sc.length > 0
    return out
  end

  def self.run
    bootstrap
    install_capture
    scns = parse_scenarios(SCENARIOS)
    ok = 0; err = 0; skip = 0
    File.open(OUT, "wb") do |f|
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
