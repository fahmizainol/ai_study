# Head-to-head strength gauntlet: Portable AI vs Reborn's own AI, in Reborn's engine.
#
# Invoked by AIHarness.run when Data/ai_harness.txt contains mode=gauntlet (the harness
# has already bootstrapped globals and loaded PokeBattle_TestEnvironment.rb). Uses the
# same fixture teams, matchups and seeds as Realidea's frozen gauntlet so the two
# studies stay structurally comparable — though win rates are NOT the same currency
# across engines; all sound comparisons are within-Reborn, between arms.
#
# In the frozen/default arms, LEFT is Reborn and RIGHT is the measured seat. The
# *_portable_left audit arms reverse the AI assignment while preserving the teams;
# $PORTABLE_AI_TRAINER identifies the portable side by trainer object rather than
# index parity under the test environment's switchTrainers machinery.
#
# Intense arms set $game_switches[3000] for the whole battle: Reborn's AI gets its full
# cheat set (forced skill 100, choice reads, 100% Sucker Punch prediction) on BOTH its
# scoring passes, while the portable side's snapshot stays fair-information because the
# adapter masks the switch during estimation. That asymmetry is the experiment:
# normal_* is the honest head-to-head, intense_* is "vs the cheat set".
#
# Faint replacements go through Reborn's pbDefaultChooseNewEnemy for BOTH sides (same
# convention as the Realidea gauntlet, which used stock replacement logic in both
# modes), so strength differences remain attributable to turn decisions.
#
# schedule=seat_audit selects every ordered pairing of the four fixture teams in
# singles (12 matchups). Its balanced schedule and separate output files measure
# right/left seat asymmetry without changing the frozen eight-matchup benchmark.
#
# Any key in CONFIG_OVERRIDE_KEYS may be set in Data/ai_harness.txt to override that
# portable core config key for the whole run, so a policy A/B needs two runs rather
# than two builds. switch_risk_weight=0 is Portable 0.3.1; turning off all four 0.4.0
# rules (heal_gate, accuracy_weight, priority_gate, self_cost) is 0.3.2.

module PortableAIRebornGauntlet
  # Core config keys this harness may override, with the type each parses to. Booleans
  # become real true/false: the core tests them with plain Ruby truthiness, and the
  # string "false" is truthy.
  CONFIG_OVERRIDE_KEYS = [
    ["switch_risk_weight", :float],
    ["accuracy_weight",    :float],
    ["heal_gate",          :boolean],
    ["priority_gate",      :boolean],
    ["self_cost",          :boolean],
    ["strict_threat",      :boolean],
    # 0.5.0 tables. All four false is 0.4.1, which is the control run: the same build
    # must reproduce the previous version battle-for-battle before any of its numbers
    # mean anything.
    ["side_effects",       :boolean],
    ["ability_rules",      :boolean],
    ["entry_rules",        :boolean],
    ["format_rules",       :boolean],
    # 0.6.0. damage_race=false is the control: the same build must reproduce 0.5.0
    # battle-for-battle before any of its numbers mean anything.
    ["damage_race",        :boolean],
    ["damage_race_switch", :boolean]
  ]

  OUT     = "Data/ai_gauntlet_results.ndjson"
  SUMMARY = "Data/ai_gauntlet_summary.txt"
  SEAT_AUDIT_OUT     = "Data/ai_seat_audit_results.ndjson"
  SEAT_AUDIT_SUMMARY = "Data/ai_seat_audit_summary.txt"
  SIX_V_SIX_OUT      = "Data/ai_6v6_results.ndjson"
  SIX_V_SIX_SUMMARY  = "Data/ai_6v6_summary.txt"
  NORMAL_BASELINE_OUT     = "Data/ai_normal_baseline_results.ndjson"
  NORMAL_BASELINE_SUMMARY = "Data/ai_normal_baseline_summary.txt"
  SEEDS   = [104729, 130363, 155921, 196613, 262147]

  # Archetype rosters live in the generated module (tools/make_gauntlet_teams.py),
  # which is bundled ahead of this file by build_portable_ai.py. "set_a" is the
  # original fixture and the default, so omitting teams= reproduces every run
  # recorded before roster selection existed.
  DEFAULT_TEAM_SET = "set_a"

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

  # Every ordered non-mirror pairing of the roster's archetypes. Archetype keys are
  # identical across roster sets, so the schedule is stable set to set.
  def self.seat_audit_matchups(teams)
    teams.keys.inject([]) do |all, left|
      teams.keys.each do |right|
        all << ["#{left}_vs_#{right}", left, right, false] if left != right
      end
      all
    end
  end

  def self.team_set(name)
    sets = PortableAIRebornTeams::SETS
    teams = sets[name]
    if !teams
      raise "unknown team set #{name.inspect}; available: #{sets.keys.sort.join(', ')}"
    end
    teams
  end

  # [name, portable?, global intense?, measured seat, portable scope, right intense?,
  #  shadow?]
  #
  # shadow_reborn is normal_reborn with the portable planner riding along as an
  # observer: Reborn-Normal plays the battle, and every turn the portable AI is asked
  # what it would have done from the same position and the answer is recorded without
  # being registered. Its battles are identical to normal_reborn's (the planner draws
  # no RNG and mutates nothing at BESTSKILL), so the two arms' results must match —
  # a mismatch means observation is not free and the comparison is void.
  ARMS = [
    ["normal_reborn",         false, false, "right"],
    ["normal_portable",       true,  false, "right"],
    ["intense_reborn",        false, true,  "right"],
    ["intense_portable",      true,  true,  "right"],
    ["normal_portable_left",  true,  false, "left"],
    ["intense_portable_left", true,  true,  "left"],
    ["portable_mirror",       true,  false, "right", "both"],
    ["intense_vs_normal",     false, false, "right", nil, true],
    ["shadow_reborn",         false, false, "right", nil, false, true]
  ]
  DEFAULT_ARM_NAMES = %w[
    normal_reborn normal_portable intense_reborn intense_portable
  ]

  def self.install_test_environment_patch
    return if PokeBattle_Battle.method_defined?(:portable_gauntlet_orig_command_phase)
    PokeBattle_Battle.class_eval do
      alias_method :portable_gauntlet_orig_switchTrainers, :switchTrainers
      alias_method :portable_gauntlet_orig_command_phase, :pbCommandPhaseTEST
      alias_method :portable_gauntlet_orig_end_of_round, :pbEndOfRoundPhase

      # PokeBattle_TestEnvironment swaps the AI data array but leaves each data
      # object's stored battler index unchanged.
      def switchTrainers
        portable_gauntlet_orig_switchTrainers
        @ai.aimondata.each_with_index do |data, index|
          data.index = index if data
        end
      end

      # Home-and-away arms keep Portable as the first chooser in either seat.
      def pbCommandPhaseTEST
        if !$AI_TEST_LEFT_FIRST
          result = portable_gauntlet_orig_command_phase
        else
          switchTrainers
          result = portable_gauntlet_orig_command_phase
          switchTrainers
          if @doublebattle
            @choices.each do |choice|
              choice[3] ^= 1 if choice[0] == 1 && choice[3] && choice[3] >= 0
            end
          end
        end
        portable_gauntlet_record_state("command", true)
        result
      end

      def pbEndOfRoundPhase
        result = portable_gauntlet_orig_end_of_round
        portable_gauntlet_record_state("round_end", false)
        result
      end

      def portable_gauntlet_record_state(phase, include_choices)
        trace = @gauntlet_command_trace
        return if !trace
        actors = []
        @battlers.each do |battler|
          next if !battler || !battler.pokemon || battler.isFainted?
          choice = @choices[battler.index]
          actor = {
            "index" => battler.index,
            "species" => battler.species,
            "party_slot" => battler.pokemonIndex,
            "hp" => battler.hp,
            "totalhp" => battler.totalhp,
            "status" => battler.status,
            "status_count" => battler.statusCount,
            "stages" => battler.stages.dup
          }
          if include_choices
            actor["choice"] = choice[0]
            actor["move_slot"] = choice[0] == 1 ? battler.moves.index(choice[2]) : nil
            actor["move_id"] = choice[0] == 1 && choice[2] ? choice[2].id : nil
            actor["switch_slot"] = choice[0] == 2 ? choice[1] : nil
            actor["target"] = choice[3]
          end
          actors << actor
        end
        trace << { "turn" => @turncount, "phase" => phase, "actors" => actors }
      end

      # --- Per-move event log -----------------------------------------------
      # The state trace above records the *registered* choice and end-of-turn HP
      # only, so a miss, a Protect, an immunity, a failed Sucker Punch and a
      # sleeping user are all indistinguishable from "hit for nothing". These
      # accessors let the battler/move hooks below append what the engine
      # actually executed. Absent unless run_one armed the log, which is what
      # keeps the hooks inert outside a traced gauntlet run.
      def portable_gauntlet_events
        @gauntlet_move_events
      end

      # The innermost open move attempt, or nil when no move is executing --
      # Reborn's own AI calls the same primitives while scoring, and those calls
      # must not be recorded.
      def portable_gauntlet_frame
        @gauntlet_event_stack && @gauntlet_event_stack.last
      end

      def portable_gauntlet_push_frame(event)
        @gauntlet_move_events << event
        @gauntlet_event_stack << { "event" => event, "targets_processed" => 0,
                                  "hits" => [] }
      end

      def portable_gauntlet_pop_frame
        @gauntlet_event_stack.pop
      end
    end

    # Move execution recorded from the engine rather than from @choices: two
    # turns in the set_c readouts show a left-side action that cannot be what
    # executed (a U-turn that neither damages nor switches; a Dragon Dance whose
    # user ends the turn asleep), and only the engine can settle which.
    #
    # Outcome classification reuses the engine's own verdicts and duplicates no
    # fail branch -- there are dozens, scattered through Reborn's modified move
    # code, and a copy of them would rot:
    #   successStates[i].useState  Reborn's "0 not used / 1 failed / 2 succeeded"
    #                              (PokeBattle_Battle.rb:52), kept for Battle Arena
    #   successStates[i].protected the Protect family
    #   damagestate                per-target crit / typemod / substitute / endured
    #   pbTryUseMove -> false      could not move at all (sleep, flinch, paralysis,
    #                              confusion, Disable, Taunt, recharge, Truant...)
    #   pbSuccessCheck -> false    did not connect (immunity, Protect, semi-invuln)
    #   pbAccuracyCheck -> false   specifically a miss
    #
    # Two limits, both degrading toward a vaguer label and never toward a wrong
    # "hit". (1) useState is only maintained on the targeted path, so a move that
    # targets its own side (Swords Dance, Roost, Stealth Rock) or is charging a
    # two-turn attack is reported as "untargeted"; its effect is visible in the
    # state trace's stages and in hp_delta. (2) Six move subclasses override
    # pbAccuracyCheck (Struggle, Confusion, OHKO 0x070, 0x0A5, 0x157, 0x159) and
    # so bypass that hook; all either always hit or appear in no gauntlet roster,
    # and a miss they made would read as "no_connect".
    # pbUseMove ends by calling updateSkill on all four success states, and that
    # resets useState/protected (PokeBattle_Battle.rb:82) -- so the verdict is
    # already gone by the time the pbUseMove wrapper regains control. Stash it as
    # it is consumed. Paths that return before the attack section never reach
    # updateSkill, and there the live field is still readable.
    PokeBattle_SuccessState.class_eval do
      attr_accessor :portable_gauntlet_verdict
      alias_method :portable_gauntlet_orig_update_skill, :updateSkill

      def updateSkill
        @portable_gauntlet_verdict = [@useState, @protected]
        portable_gauntlet_orig_update_skill
      end
    end

    PokeBattle_Battler.class_eval do
      alias_method :portable_gauntlet_orig_use_move, :pbUseMove
      alias_method :portable_gauntlet_orig_try_use_move, :pbTryUseMove
      alias_method :portable_gauntlet_orig_success_check, :pbSuccessCheck
      alias_method :portable_gauntlet_orig_process_target, :pbProcessMoveAgainstTarget

      def pbUseMove(choice, flags = { danced: false, totaldamage: 0, specialusage: false })
        if !@battle.portable_gauntlet_events
          return portable_gauntlet_orig_use_move(choice, flags)
        end
        # Paired with the occupant, because U-turn/Volt Switch and a faint mid-move
        # replace the Pokemon in a slot -- comparing HP across that is meaningless.
        before = @battle.battlers.map { |battler| battler ? [battler.hp, battler.pokemon] : nil }
        event = {
          "turn" => @battle.turncount,
          "user" => @index,
          "species" => self.species,
          # Overwritten on exit: the engine substitutes choice[2] in place for a
          # continuing multi-turn move, an Encore, and an Encore-forced Struggle.
          "move" => (choice[2] ? choice[2].id : nil),
          "targets" => []
        }
        event["nested"] = true if @battle.portable_gauntlet_frame
        if self.status != 0
          event["status"] = self.status
          event["status_count"] = self.statusCount
        end
        event["flinch"] = true if @effects[PBEffects::Flinch]
        event["confusion"] = @effects[PBEffects::Confusion] if @effects[PBEffects::Confusion] > 0
        state = @battle.successStates[@index]
        state.portable_gauntlet_verdict = nil
        @battle.portable_gauntlet_push_frame(event)
        begin
          portable_gauntlet_orig_use_move(choice, flags)
        ensure
          frame = @battle.portable_gauntlet_pop_frame
          event["move"] = choice[2].id if choice[2]
          use_state, blocked_by_protect =
            state.portable_gauntlet_verdict || [state.useState, state.protected]
          event["use_state"] = use_state
          event["outcome"] =
            if frame["blocked"] then "could_not_move"
            elsif use_state == 0 then "not_used"
            elsif frame["targets_processed"] == 0 then "untargeted"
            elsif frame["no_connect"] && frame["hits"].empty?
              blocked_by_protect ? "protected" :
                frame["accuracy_failed"] ? "missed" : "no_connect"
            elsif frame["effect_failed"] then "failed"
            elsif use_state == 2 then "hit"
            else "failed"
            end
          delta = {}
          @battle.battlers.each_with_index do |battler, index|
            was = before[index]
            next if !battler || !was || !battler.pokemon.equal?(was[1])
            delta[index.to_s] = battler.hp - was[0] if battler.hp != was[0]
          end
          event["hp_delta"] = delta if !delta.empty?
        end
      end

      def pbTryUseMove(choice, thismove, flags = { passedtrying: false, instructed: false })
        allowed = portable_gauntlet_orig_try_use_move(choice, thismove, flags)
        frame = @battle.portable_gauntlet_frame
        frame["blocked"] = true if frame && !allowed
        allowed
      end

      def pbSuccessCheck(thismove, user, target, flags, accuracy = true)
        frame = @battle.portable_gauntlet_frame
        # Scoped to this check: pbAccuracyCheck also runs during Reborn's damage
        # estimates, which can be triggered from inside a move (faint replacement).
        frame["missed"] = false if frame
        connected = portable_gauntlet_orig_success_check(thismove, user, target, flags, accuracy)
        if frame && !connected
          frame["no_connect"] = true
          frame["accuracy_failed"] = frame["missed"]
        end
        connected
      end

      def pbProcessMoveAgainstTarget(thismove, user, target, numhits,
                                     flags = { totaldamage: 0 }, nocheck = false,
                                     alltargets = nil, showanimation = true)
        frame = @battle.portable_gauntlet_frame
        before = (frame && target) ? target.hp : nil
        first_hit = frame ? frame["hits"].length : 0
        result = portable_gauntlet_orig_process_target(thismove, user, target, numhits,
                                                       flags, nocheck, alltargets,
                                                       showanimation)
        if before
          frame["targets_processed"] += 1
          # Reborn's own "the move that just ran failed" flag, which it keeps for
          # Stomping Tantrum (PokeBattle_Battler.rb:5085, `damage == -1`). useState
          # reaches 2 even when the effect itself failed, so this is what separates
          # a Toxic that landed from one the target shrugged off.
          frame["effect_failed"] = user.effects[PBEffects::Tantrum] ? true : false
          entry = { "index" => target.index, "hp_lost" => before - target.hp }
          hits = frame["hits"][first_hit..-1].select do |hit|
            hit.delete("target") == target.index
          end
          entry["hits"] = hits if !hits.empty?
          frame["event"]["targets"] << entry
        end
        result
      end
    end

    PokeBattle_Move.class_eval do
      alias_method :portable_gauntlet_orig_accuracy_check, :pbAccuracyCheck
      alias_method :portable_gauntlet_orig_reduce_hp_damage, :pbReduceHPDamage

      # One call per connecting hit, and the only moment damagestate still describes
      # that hit: several paths reset it before pbProcessMoveAgainstTarget returns,
      # where a reset reads as typemod 0 -- indistinguishable from an immunity, since
      # Reborn's neutral is 4.
      def pbReduceHPDamage(damage, attacker, opponent)
        dealt = portable_gauntlet_orig_reduce_hp_damage(damage, attacker, opponent)
        frame = @battle ? @battle.portable_gauntlet_frame : nil
        if frame && opponent
          state = opponent.damagestate
          hit = { "target" => opponent.index, "damage" => dealt,
                  "typemod" => state.typemod }
          hit["crit"] = true if state.critical
          hit["substitute"] = true if state.substitute
          hit["endured"] = true if state.endured || state.sturdy || state.focussashused
          frame["hits"] << hit
        end
        dealt
      end

      def pbAccuracyCheck(attacker, opponent, dragondarts = false)
        hit = portable_gauntlet_orig_accuracy_check(attacker, opponent, dragondarts)
        frame = @battle ? @battle.portable_gauntlet_frame : nil
        frame["missed"] = true if frame && !hit
        hit
      end
    end

    if !PokeBattle_AI.method_defined?(:portable_gauntlet_orig_process_ai_turn)
      PokeBattle_AI.class_eval do
        alias_method :portable_gauntlet_orig_process_ai_turn, :processAIturn

        # Reborn's Intense mode is a global switch. For the controlled baseline arm,
        # enable it only while the marked right trainer's AI pass is executing.
        def processAIturn
          marked = $AI_GAUNTLET_INTENSE_TRAINER
          return portable_gauntlet_orig_process_ai_turn if !marked
          old_intense = $game_switches[3000]
          opponents = @battle.opponent.is_a?(Array) ? @battle.opponent : [@battle.opponent]
          $game_switches[3000] = opponents.any? { |trainer| trainer.equal?(marked) }
          portable_gauntlet_orig_process_ai_turn
        ensure
          $game_switches[3000] = old_intense if marked
        end
      end
    end
  end

  # Parse the portable-core config overrides out of a Data/ai_harness.txt config hash.
  # Booleans become real true/false: the core tests them with plain Ruby truthiness, and
  # the string "false" is truthy.
  def self.config_overrides_from(cfg)
    overrides = {}
    CONFIG_OVERRIDE_KEYS.each do |key, kind|
      value = cfg[key]
      next if !value || value == ""
      overrides[key] = (kind == :float) ? value.to_f : (value == "true")
    end
    overrides
  end

  # mode=probe returns from AIHarness.run (AI_Harness.rb:218) before the gauntlet's
  # override parse ever runs, so a probe could not be told which core rules to switch
  # off -- and the probe is how one table row gets ablated without a 4-minute battle
  # run. AI_Harness.rb is game-side and outside this study's sources, so the parse is
  # attached from here instead; !script_order.csv loads AI_Harness before Portable_AI,
  # so the method exists by the time this file is read.
  def self.install_probe_config_patch
    return if !defined?(AIHarness)
    return if AIHarness.respond_to?(:portable_gauntlet_orig_run_probe)
    AIHarness.singleton_class.class_eval do
      alias_method :portable_gauntlet_orig_run_probe, :run_probe
      def run_probe(cfg)
        $PORTABLE_AI_CONFIG = PortableAIRebornGauntlet.config_overrides_from(cfg)
        portable_gauntlet_orig_run_probe(cfg)
      ensure
        $PORTABLE_AI_CONFIG = nil
      end
    end
  end

  def self.run(cfg = {})
    install_test_environment_patch
    # Reborn's own scoring log (logAIScorings :17593) gates on $INTERNAL, so forcing it
    # false made every gauntlet run blind to the reference AI's score vectors whatever
    # log_decisions= said -- the reason a Reborn-vs-Portable comparison had to be
    # inferred from state. Off by default (debuglog.txt grows fast); on for the one
    # roster where the vectors are wanted.
    log_decisions = cfg["log_decisions"] == "true"
    if log_decisions
      AIHarness.attach_decision_logging
      $INTERNAL = true
    else
      $INTERNAL = false
    end
    $AI_GAUNTLET_TRACE = cfg["trace"] == "true"
    # $DEBUG gates the test loop's 500-round pbDecisionOnTime cap
    # (PokeBattle_TestEnvironment.rb testAllBattlesSingles), which guarantees stall
    # matchups terminate with a decision-on-time instead of hanging the runner.
    $DEBUG = true

    arms = ARMS.select { |arm| DEFAULT_ARM_NAMES.include?(arm[0]) }
    if cfg["arms"] && cfg["arms"] != ""
      wanted = cfg["arms"].split(",").map { |name| name.strip }
      arms = ARMS.select { |arm| wanted.include?(arm[0]) }
    end
    if arms.empty?
      AIHarness.echo "Gauntlet: no arms matched #{cfg['arms'].inspect}"
      return
    end

    set_name = (cfg["teams"] && cfg["teams"] != "") ? cfg["teams"] : DEFAULT_TEAM_SET
    begin
      teams = team_set(set_name)
    rescue RuntimeError => error
      AIHarness.echo "Gauntlet: #{error.message}"
      return
    end

    seat_audit = cfg["schedule"] == "seat_audit"
    normal_baseline = cfg["schedule"] == "normal_baseline"
    matchups = (seat_audit || normal_baseline) ? seat_audit_matchups(teams) : MATCHUPS
    if cfg["matchups"] && cfg["matchups"] != ""
      wanted_matchups = cfg["matchups"].split(",").map { |name| name.strip }
      matchups = matchups.select { |matchup| wanted_matchups.include?(matchup[0]) }
    end
    seeds = SEEDS
    if cfg["seeds"] && cfg["seeds"] != ""
      seeds = cfg["seeds"].split(",").map { |seed| seed.strip.to_i }
    end
    party_size = (cfg["party_size"] || "3").to_i
    if party_size < 1 || party_size > 6
      AIHarness.echo "Gauntlet: party_size must be between 1 and 6"
      return
    end

    # Portable core config overrides for this run, so a policy A/B is two runs of one
    # build rather than two builds. Whatever is set lands in every record, because the
    # ndjson is the only lasting statement of what ran.
    overrides = config_overrides_from(cfg)
    $PORTABLE_AI_CONFIG = overrides
    if normal_baseline
      out = NORMAL_BASELINE_OUT
      summary = NORMAL_BASELINE_SUMMARY
    elsif party_size == 6
      out = SIX_V_SIX_OUT
      summary = SIX_V_SIX_SUMMARY
    else
      out = seat_audit ? SEAT_AUDIT_OUT : OUT
      summary = seat_audit ? SEAT_AUDIT_SUMMARY : SUMMARY
    end
    counts = {}
    arms.each do |arm|
      counts[arm[0]] = { "wins" => 0, "losses" => 0, "draws" => 0,
                         "errors" => 0, "turns" => 0 }
    end
    total = matchups.length * seeds.length * arms.length
    done = 0
    schedule_name = normal_baseline ? "normal baseline" :
                    seat_audit ? "seat audit" : "frozen"
    AIHarness.echo "Gauntlet: #{total} battles, #{schedule_name} schedule " \
                   "(#{arms.map { |a| a[0] }.join(', ')}), #{party_size}v#{party_size}, " \
                   "teams=#{set_name}, portable #{PortableAI::VERSION}" \
                   "#{overrides.empty? ? '' : " #{overrides.inspect}"}"

    File.open(out, cfg["append"] == "true" ? "ab" : "wb") do |file|
      matchups.each do |matchup|
        seeds.each do |seed|
          arms.each do |arm|
            record = run_one(matchup, seed, arm, party_size, teams, set_name)
            bucket = counts[arm[0]]
            bucket["turns"] += record["turns"].to_i
            case record["result"]
            when "win"  then bucket["wins"] += 1
            when "loss" then bucket["losses"] += 1
            when "draw" then bucket["draws"] += 1
            else bucket["errors"] += 1
            end
            file.write(AIHarness.jsonify(record) + "\n")
            file.flush
            done += 1
            AIHarness.echo "  [#{done}/#{total}] #{record['id']} #{arm[0]} seed=#{seed} " \
                           "-> #{record['result']} (#{record['turns']} turns)"
          end
        end
      end
    end

    File.open(summary, "wb") do |file|
      counts.each do |name, values|
        finished = values["wins"] + values["losses"] + values["draws"]
        win_rate = finished > 0 ? values["wins"] * 100.0 / finished : 0
        mean_turns = finished > 0 ? values["turns"] * 1.0 / finished : 0
        line = "#{name}: wins=#{values['wins']} losses=#{values['losses']} " \
               "draws=#{values['draws']} errors=#{values['errors']} " \
               "win_rate=#{win_rate.round(1)} mean_turns=#{mean_turns.round(1)}"
        file.write(line + "\n")
        AIHarness.echo line
      end
    end
    AIHarness.echo "Gauntlet: wrote #{out} and #{summary}"
  ensure
    $PORTABLE_AI_CONFIG = nil
    $PORTABLE_AI_ENABLED = false
    $PORTABLE_AI_SHADOW = false
    $PORTABLE_AI_TRAINER = nil
    $AI_GAUNTLET_INTENSE_TRAINER = nil
    $AI_TEST_LEFT_FIRST = false
    $AI_GAUNTLET_TRACE = false
    $game_switches[3000] = false if $game_switches
  end

  def self.run_one(matchup, seed, arm, party_size = 3, teams = nil,
                   set_name = DEFAULT_TEAM_SET)
    teams ||= team_set(DEFAULT_TEAM_SET)
    id, left_name, right_name, doubles = matchup
    arm_name, portable, intense, measured_seat, portable_scope, right_intense,
      shadow = arm
    left_trainer  = PokeBattle_Trainer.new("Left #{left_name}", 0)
    right_trainer = PokeBattle_Trainer.new("Right #{right_name}", 0)
    left_party  = make_party(teams[left_name].first(party_size), left_trainer)
    right_party = make_party(teams[right_name].first(party_size), right_trainer)

    # Header so debuglog.txt lines can be joined back to the ndjson record they belong
    # to; PBDebug.log is a no-op unless log_decisions turned $INTERNAL on.
    PBDebug.log("=== #{id} seed #{seed} arm #{arm_name} ===") if $INTERNAL

    # Field 0 must be pinned before construction (same reasoning and mechanism as the
    # probe: the null map otherwise derives an arbitrary non-zero field).
    ($game_variables[:Forced_Field_Effect] = 0) rescue nil
    scene = pbNewBattleScene
    battle = PokeBattle_Battle.new(scene, left_party, right_party,
                                   left_trainer, right_trainer)
    # PokeBattle_Battle#initialize (PokeBattle_Battle.rb:525) overwrites obedient on
    # every @party1 member with `level <= LEVELCAPS[numbadges]`, and the harness has
    # no badges, so LEVELCAPS[0] = 20 made the whole LEFT party disobedient however
    # make_party had set it. Reborn's AI holds the left seat in every default arm,
    # so it was losing ~17% of its move attempts to naps, self-confusion damage and
    # ignored orders while the right seat -- never pbOwnedByPlayer? -- was exempt.
    # Restore the flag after construction, where nothing resets it again. Found by
    # the per-move event log below: 41 of 42 "could_not_move" events in a 10-battle
    # sample were the left side, most with no status to explain them.
    (left_party + right_party).each { |pokemon| pokemon.obedient = true }
    battle.doublebattle = doubles
    battle.endspeech = ""
    battle.items  = []
    battle.items2 = []
    battle.internalbattle = true
    field = battle.instance_variable_get(:@field)
    if field
      field.layer = [0]
      field.effect = 0
      field.duration = 0
    end
    pbPrepareBattle(battle)
    battle.instance_variable_set(:@portable_ai_decision_trace, []) if portable
    battle.instance_variable_set(:@portable_ai_shadow_trace, []) if shadow
    if $AI_GAUNTLET_TRACE
      battle.instance_variable_set(:@gauntlet_command_trace, [])
      battle.instance_variable_set(:@gauntlet_move_events, [])
      battle.instance_variable_set(:@gauntlet_event_stack, [])
    end

    $game_switches[3000] = intense
    $AI_GAUNTLET_INTENSE_TRAINER = right_intense ? right_trainer : nil
    $PORTABLE_AI_ENABLED = portable
    $PORTABLE_AI_SHADOW = shadow ? true : false
    # Shadow needs the same seat identity as a live portable side so the observer
    # watches the measured seat, even though it registers nothing.
    $PORTABLE_AI_TRAINER = if (portable && portable_scope != "both") || shadow
                             measured_seat == "left" ? left_trainer : right_trainer
                           else
                             nil
                           end
    # The measured portable side chooses first in either seating. This preserves the
    # same information flow for Reborn Intense's choice-reading behavior.
    $AI_TEST_LEFT_FIRST = portable && measured_seat == "left"
    srand(seed)
    decision = doubles ? battle.testAllBattlesDoubles(true) :
                         battle.testAllBattlesSingles(true)

    # Record result from the measured seat's perspective. Existing arms measure the
    # right seat; *_portable_left measures Portable AI on the left.
    seat_won = measured_seat == "left" ? decision == 1 : decision == 2
    seat_lost = measured_seat == "left" ? decision == 2 : decision == 1
    result = seat_won ? "win" : seat_lost ? "loss" : "draw"
    record = {
      "id" => id,
      "arm" => arm_name,
      "mode" => (portable ? "portable" : "reborn"),
      "intense" => (intense || right_intense ? true : false),
      "measured_seat" => measured_seat,
      "seed" => seed,
      "party_size" => party_size,
      "team_set" => set_name,
      "format" => (doubles ? "double" : "single"),
      "left_reborn_team" => left_name,
      "right_test_team" => right_name,
      "decision" => decision,
      "result" => result,
      "turns" => battle.turncount
    }
    if $AI_GAUNTLET_TRACE
      record["commands"] = battle.instance_variable_get(:@gauntlet_command_trace)
      # One flat list, each event carrying its own turn: the test loop breaks out
      # of the round before pbEndOfRoundPhase when the battle is decided, so a
      # per-turn flush would drop the deciding turn's moves.
      record["events"] = battle.instance_variable_get(:@gauntlet_move_events)
      record["final_parties"] = [
        left_party.map { |pokemon| [pokemon.species, pokemon.hp, pokemon.totalhp] },
        right_party.map { |pokemon| [pokemon.species, pokemon.hp, pokemon.totalhp] }
      ]
    end
    if portable || shadow
      record["portable_version"] = PortableAI::VERSION
      run_overrides = PortableAIReborn.config_overrides
      record["config_overrides"] = run_overrides if !run_overrides.empty?
    end
    if portable
      trace = battle.instance_variable_get(:@portable_ai_decision_trace)
      record["trace_len"] = trace ? trace.length : 0
      record["portable_trace"] = trace if $AI_GAUNTLET_TRACE
    end
    if shadow
      trace = battle.instance_variable_get(:@portable_ai_shadow_trace)
      record["shadow_len"] = trace ? trace.length : 0
      record["portable_shadow"] = trace if $AI_GAUNTLET_TRACE
    end
    record
  rescue Exception => error
    {
      "id" => id, "arm" => arm_name, "seed" => seed,
      "party_size" => party_size, "team_set" => set_name,
      "format" => (doubles ? "double" : "single"),
      "result" => "error", "turns" => 0,
      "error" => "#{error.class}: #{error.message}",
      "where" => (error.backtrace ? error.backtrace[0, 6].join(" | ") : nil)
    }
  ensure
    $PORTABLE_AI_ENABLED = false
    $PORTABLE_AI_SHADOW = false
    $PORTABLE_AI_TRAINER = nil
    $AI_GAUNTLET_INTENSE_TRAINER = nil
    $AI_TEST_LEFT_FIRST = false
  end

  # A roster entry is ["SPECIES", %w[four moves]] or, for the dressed sets f/g,
  # ["SPECIES", %w[four moves], {"item" => "NAME", "ability" => slot}]. The two-element
  # form behaves exactly as it always did -- slot-0 ability, no held item -- so
  # set_a..set_e stay bit-for-bit the teams every recorded run used.
  #
  # The dressed sets exist because slot-0-and-no-item made half of the 0.5.0 tables
  # unmeasurable: no Knock Off target has an item, no Focus Sash exists to break, no
  # Choice lock ever forms, and Regenerator/Unaware/Multiscale/Mold Breaker are all
  # non-slot-0 abilities. See tools/make_gauntlet_teams.py for how f/g are dressed.
  def self.make_party(specs, trainer)
    specs.map do |spec|
      species_name, move_names, extra = spec
      species = PBSpecies.const_get(species_name)
      pokemon = PokeBattle_Pokemon.new(species, 100, trainer)
      pokemon.resetMoves
      move_names.each_with_index do |move_name, slot|
        pokemon.moves[slot] = PBMove.new(PBMoves.const_get(move_name))
      end
      if extra && extra["item"]
        item = (PBItems.const_get(extra["item"]) rescue nil)
        pokemon.setItem(item) if item
      end
      pokemon.setAbility((extra && extra["ability"]) || 0)
      pokemon.setNature(0)
      pokemon.obedient = true
      for stat in 0...6
        pokemon.iv[stat] = 31
        pokemon.ev[stat] = 85
      end
      pokemon.calcStats
      pokemon.hp = pokemon.totalhp
      pokemon
    end
  end
end

PortableAIRebornGauntlet.install_probe_config_patch
