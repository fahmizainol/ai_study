# 0.7.0. A SECOND PLANNER: one-ply search over the joint action grid.
#
# Requires model.rb, effects.rb and matrix.rb. It does NOT require core.rb and must
# not come to: core.rb scores ACTIONS by summing 107 hand-tuned reason terms, and this
# scores the STATE an action leads to. Two answers to two different questions. Mixing
# them would give a number that is neither, so they share the board readers (matrix.rb)
# and nothing else. The adapter picks one per run; the rule planner is the default and
# this is off unless `search_planner` is set.
#
# PROVENANCE. The shape is poke-engine's legacy `expectiminimax_search` + `pick_safest`
# (https://github.com/pmariglia/poke-engine, src/search.rs, GPL-3.0), the path the
# older Foul Play "safest" bot ran; Foul Play today runs the engine's MCTS instead.
# Three ideas are borrowed, no code is:
#   * `pick_safest` -- pick by maximin over the joint own x foe payoff grid, not by
#     expected value against a guessed foe move.
#   * a state-value leaf -- the board after the turn is worth what stands on it. The
#     original's `evaluate` is a PARTY-WIDE sum: every live body is worth its HP plus a
#     flat alive bonus, and there is no matchup term at all. 0.7.1 made this leaf that
#     shape; the first version had the weighting inside out (see THE VALUE SCALE).
#   * chance as branches -- a speed tie and a miss are both two boards at their
#     probabilities, never one board at an averaged damage. The leaf is a step at
#     0 HP, so the value of the expected damage is not the expected value.
# Damage-roll grouping by faint threshold was NOT borrowed through 0.7.8 on the
# belief that a cell carried an expected roll; it carries the MAXIMUM (pbRoughDamage
# has no random factor), and 0.7.9 borrows the original's branching -- see
# roll_outcomes. Still not borrowed: reversible instructions (unnecessary -- the snapshot is a
# plain Hash and Model.copy_hash is the whole undo), and Smogon-corpus set prediction
# (that is the predictor backlog item, and it feeds the same snapshot fields).

module PortableAI
  module Search
    # THE VALUE SCALE, the original's proportions in HP points:
    #   1 point   one percent of a body's HP, every live body on both sides. HP is the
    #             currency, as in poke-engine's evaluate (POKEMON_HP = 100 x fraction).
    #   30        a body being alive at all (POKEMON_ALIVE). So a kill is worth the HP
    #             it removes plus 30, and losing a 5% body costs 35, not the game.
    #   +/-1000   the battle is over (the original's 100 x depth x battle_is_over).
    # NO VERDICT TERM (0.7.4). Through 0.7.3 the leaf added +/-25 for the pair left
    # standing (matrix.rb's W / L), a term the original does not have, kept "small
    # on purpose" after 0.7.0 had it at the top of the scale and fled to every
    # W-verdict bench body. Once the foe-switch column priced each move on its own
    # (out_moves), an attack the bench could wall read as a bad row, and the verdict
    # was what made the pre-emptive switch the better one: 35/60 with the term, 40/60
    # without, on the same build. The pair's matchup is already in the sum -- as the
    # HP each side stands to lose at the next ply -- which is where the original
    # keeps it.
    BODY_ALIVE = 30.0
    BATTLE_OVER = 1000.0
    # A win found a ply earlier is worth more (the original's 100 x depth), and the
    # sentinels the maximin loops start from -- no Float::INFINITY on RGSS's Ruby.
    DEPTH_BONUS = 100.0
    DEFAULT_DEPTH = 2
    HUGE = 1.0e18

    # THE REST OF THE ORIGINAL'S evaluate, at its numbers (poke-engine
    # src/genx/evaluate.rs), for what a turn can change besides HP. 0.7.2: before this
    # a setup, heal, Protect, status or hazard move projected as a wasted turn, so the
    # planner could never click one on purpose.
    STAGE_VALUE = { "atk" => 30.0, "spa" => 30.0, "speed" => 30.0,
                    "def" => 15.0, "spd" => 15.0 }
    STAGE_MULTIPLIER = [0.0, 1.0, 2.0, 2.5, 3.0, 3.15, 3.3]
    # A foe's stage, which the snapshot reports only as a count of positive ones.
    FOE_STAGE_VALUE = 25.0
    STATUS_VALUE = { "toxic" => 30.0, "poison" => 10.0, "burn" => 25.0,
                     "paralyze" => 25.0, "sleep" => 25.0, "freeze" => 40.0,
                     "confuse" => 20.0, "drain" => 30.0 }
    SUBSTITUTE_VALUE = 75.0
    SUBSTITUTE_COST = 25.0
    HAZARD_VALUE = { "STEALTHROCK" => 10.0, "SPIKES" => 7.0, "TOXICSPIKES" => 7.0,
                     "STICKYWEB" => 25.0 }

    # 0.7.9. THE ROLL AND THE TURN'S OTHER CHANCES. Every damage number this planner
    # is handed is pbRoughDamage, a maximum (no random factor, no crit: 085 "Random
    # variance - n/a"); the engine rolls 85..100% of it and crits one time in sixteen
    # for x1.5 (v16). See roll_outcomes. The act chances are the engine's for
    # paralysis and thaw; sleep is a third, the mean over a counter the snapshot does
    # not carry.
    ROLL_MIN = 0.85
    ROLL_AVERAGE = 0.925
    CRIT_RATE = 1.0 / 16.0
    CRIT_MULT = 1.5
    ACT_CHANCE = { "paralyze" => 0.75, "sleep" => 1.0 / 3.0, "freeze" => 0.2 }
    # PBStatuses, as the adapter exports a body's status; the names are what the
    # STATUS_VALUE table above keys on. "toxic" is this planner's own, for a Toxic it
    # landed itself -- the engine reports Toxic as POISON plus a counter it does not
    # export, so a body that arrived already badly poisoned ticks as poisoned.
    STATUS_CODES = { 1 => "sleep", 2 => "poison", 3 => "burn", 4 => "paralyze", 5 => "freeze" }
    STATUS_NAMES = { "paralysis" => "paralyze", "paralyzed" => "paralyze", "frozen" => "freeze",
                     "asleep" => "sleep", "poisoned" => "poison", "burned" => "burn",
                     "badly_poisoned" => "toxic" }
    # THE END OF TURN, in percent of max HP: an eighth for burn, poison, Leech Seed
    # and Black Sludge on the wrong body; a sixteenth for Leftovers, sand, hail and
    # each rung of the Toxic ladder. The engine's own fractions (080:2212-2231).
    RESIDUAL_EIGHTH = 12.5
    RESIDUAL_SIXTEENTH = 6.25
    SAND_PROOF_TYPES = %w[ROCK GROUND STEEL]
    SAND_PROOF_ABILITIES = %w[SANDVEIL SANDRUSH SANDFORCE OVERCOAT]
    HAIL_PROOF_ABILITIES = %w[ICEBODY SNOWCLOAK SLUSHRUSH OVERCOAT]

    # nil means "this planner declines" -- the adapter falls through to the rule planner
    # and the run is unchanged. Declining is the normal path on anything but a singles
    # battle with a matrix, so a build with the key on is still the rule AI everywhere
    # this cannot see the board.
    def self.plan(snapshot, config, rng)
      Model.validate(snapshot)
      # The defaults under the overrides, as the rule engine reads them. Through the
      # first 0.7.5 build this read the overrides alone, so a default that was not
      # spelled out in the harness (search_foe_mix 0.5) was 0 in play and the
      # shipped arm reproduced 0.7.4 to the decision.
      config = Model.config(config)
      return nil if (snapshot["format"] || "single") != "single"
      actors = snapshot["actors"]
      targets = snapshot["targets"] || []
      return nil if actors.length != 1 || targets.length != 1
      return nil if PortableAI.matrix(snapshot).nil?

      board = opening_board(snapshot, config)
      return nil if board.nil?
      own_actions = actors[0]["actions"]
      return nil if !own_actions.is_a?(Array) || own_actions.empty?
      foe_actions = foe_options(snapshot, board)
      return nil if foe_actions.empty?

      # 0.7.6. THE TREE, or the grid. Everything above is shared -- the same guards,
      # the same opening board, the same option lists -- and everything below is the
      # maximin. With the key off this line is the only trace of MCTS in a run.
      return mcts_plan(snapshot, config, board, own_actions, foe_actions) if config["search_mcts"]

      depth = depth_of(config)
      # THE OPPONENT MODEL LIVES AT THE ROOT. The mix and the weights are applied to
      # the root rows only; every ply below is the original's maximin (safest). A
      # prediction exists only for the board in front of us, and blending the deeper
      # grids with a uniform expectation instead was measured as the worse half of
      # every arm (stock model at 0.5: 42 with it, 46 without; the oracle 34 / 46).
      mix = mix_of(config)
      weights = column_weights(foe_actions, board["foe_reply"],
                               config["search_foe_prior"] ? foe_prior(foe_actions) : nil)
      ranked = own_actions.map do |action|
        row = foe_actions.map { |foe| payoff(snapshot, board, action, foe, depth, own_actions) }
        scored = Model.copy_hash(action)
        # Maximin: the action is worth the WORST the foe can do to it. pick_safest.
        # Not an average -- an average rewards a line that is excellent against three
        # foe options and loses the game against the fourth. That is the original,
        # and at search_foe_mix 0 it is all there is. Above 0 the worst reply is
        # blended with the EXPECTED one (row_value): 0.7.4 measured pure maximin as
        # the limit -- an attack's worst case is the bench body that walls it, and
        # the measured foe does not make that reply.
        scored["score"] = row_value(row, weights, mix)
        # The mean breaks a tie in the minimum, and ties are common by construction:
        # every own move projects the SAME number against a switching foe (own_damage),
        # so whenever a foe switch is the worst case the minima collapse. Without this
        # the fallback is the action key, and the planner would click move slot 0 in
        # every such position. Lexicographic, not a weighted sum, so it can never
        # reorder two genuinely different minima however close they are.
        scored["search_mean"] = row.inject(0.0) { |a, b| a + b } / row.length
        # The row itself, in foe_actions order, so a traced run can be read rather than
        # guessed at. The first version had to be debugged from four identical scores.
        scored["search_row"] = row
        # Diagnostic: the on-field cell the leaf and the ordering are read from. A move
        # scored as a certain death against a full-HP actor is either a real cell or a
        # misread one, and nothing else in the trace can tell those apart.
        on_field = PortableAI.matrix_cell(snapshot, board["own_slot"], board["foe_slot"])
        scored["search_cell"] = on_field
        scored["reasons"] = [["search_worst_case", row.min],
                             ["search_mean", scored["search_mean"]],
                             ["search_best_case", row.max],
                             ["search_foe_options", foe_actions.length],
                             ["search_expected", expected_value(row, weights)]]
        scored
      end
      ranked.sort! { |a, b| compare(a, b) }

      {
        "actions" => [ranked[0]],
        # The same record the rule planner leaves (Effects.memory_updates), because the
        # projection reads it back: a Protect clicked twice running fails, and only
        # the memory counter can say the last click was one.
        "memory_updates" => Effects.memory_updates([ranked[0]]),
        "diagnostics" => {
          "version" => VERSION,
          "planner" => "search",
          "depth" => depth,
          "foe_mix" => mix,
          "foe_weights" => weights,
          "foe_reply" => board["foe_reply"],
          "format" => "single",
          "joint_adjustment" => 0,
          "foe_options" => foe_actions.map { |f| foe_label(f) },
          "board" => board,
          "candidate_counts" => [ranked.length],
          "rankings" => [ranked]
        }
      }
    end

    # Plies to look ahead: the config key, floored at one. A bare Hash (the tests, an
    # adapter that never merged defaults) gets DEFAULT_DEPTH.
    # The opponent model's one number, clamped to [0, 1]. See DEFAULT_CONFIG.
    def self.mix_of(config)
      mix = Model.number((config || {})["search_foe_mix"], 0.0)
      mix = 0.0 if mix < 0.0
      mix = 1.0 if mix > 1.0
      mix
    end

    # What the adapter predicts the foe on the field will do this turn, if it
    # predicts anything: the chance it switches and, when known, the slot it
    # switches to. From the actor's predicted_foe entry for the target's seat --
    # the oracle's (type switch, chance 1) or a model's (type move, its own chance).
    # nil when nothing was exported, which is every run with both keys off.
    def self.predicted_reply(snapshot)
      actor = snapshot["actors"][0]
      target = snapshot["targets"][0]
      table = actor["predicted_foe"]
      return nil if !table.is_a?(Hash) || target["index"].nil?
      entry = table[target["index"].to_s]
      return nil if !entry.is_a?(Hash)
      if entry["type"].to_s == "switch"
        { "switch_chance" => 1.0, "switch_slot" => entry["slot"] }
      else
        { "switch_chance" => Model.number(entry["switch_chance"], 0.0),
          "switch_slot" => entry["switch_slot"] }
      end
    end

    # One weight per foe column, summing to one. Uniform without a prediction --
    # which, measured, is a bad model of this foe (it says "switches five turns in
    # six"): 29/60 at the root against 46 with the stock model's weights. With
    # one: the switch chance goes to the predicted slot's column, or is shared by
    # every switch column when the slot is unknown, and the rest is the stay column.
    # A column list with no stay (a replacement ply) is uniform whatever was said.
    def self.column_weights(foe_actions, reply, prior = nil)
      n = foe_actions.length
      return [] if n == 0
      uniform = foe_actions.map { 1.0 / n }
      if reply.nil?
        # No opponent model at all. The prior still has something to say -- it is a
        # statement about the foe's MOVES, not about whether it stays -- so the stay
        # columns share exactly the mass uniform gave them, redistributed by damage.
        return uniform if prior.nil?
        stays = []
        foe_actions.each_with_index { |f, i| stays << i if f["kind"] == "stay" }
        return uniform if stays.length < 2
        out = uniform.dup
        spread_stays(out, foe_actions, stays, stays.length.to_f / n, prior)
        return out
      end
      # 0.7.7: there are as many stay columns as the foe has moves, so the mass that
      # is not a switch is shared over all of them. The prediction says whether it
      # stays, never which move it picks -- concentrating this on a predicted move is
      # the next arm, and it is what `stock_move` was exported for.
      stays = []
      switches = []
      foe_actions.each_with_index do |f, i|
        stays << i if f["kind"] == "stay"
        switches << i if f["kind"] == "switch"
      end
      return uniform if stays.empty? || switches.empty?
      chance = Model.number(reply["switch_chance"], 0.0)
      chance = 0.0 if chance < 0.0
      chance = 1.0 if chance > 1.0
      out = foe_actions.map { 0.0 }
      spread_stays(out, foe_actions, stays, 1.0 - chance, prior)
      slot = reply["switch_slot"]
      named = slot.nil? ? nil : switches.find { |i| foe_actions[i]["slot"] == slot }
      if named
        out[named] = chance
      else
        switches.each { |i| out[i] = chance / switches.length }
      end
      out
    end


    # The stay columns' share of `mass`, split by the prior when there is one and
    # evenly when there is not. The prior only ever moves mass BETWEEN STAY COLUMNS:
    # it says which move the foe picks, never whether it stays, so the switch/stay
    # split its caller computed survives untouched.
    def self.spread_stays(out, foe_actions, stays, mass, prior)
      share = nil
      if !prior.nil?
        total = 0.0
        stays.each { |i| total += prior[i] }
        share = total if total > 0.0
      end
      if share.nil?
        stays.each { |i| out[i] = mass / stays.length }
      else
        stays.each { |i| out[i] = mass * prior[i] / share }
      end
    end

    # HOW HARD EACH OF THE FOE'S MOVES HITS, normalised: the free prior over the foe's
    # columns, read straight out of the cell the tree already built. Measured on the
    # 0.7.7 5000-iteration arm (925 decisions): the cell's max-damage move IS the move
    # the foe registers 51.7% of the time, against 43.1% for the tree's own most-visited
    # foe option -- so the tree's opponent model is worse than the one already sitting
    # in its input, and this is what the two `search_foe_prior` arms redistribute by.
    #
    # nil when nothing is priced (no in_moves, or every column zero), which leaves both
    # consumers exactly as they were. Switch columns get 0: the prior is about moves,
    # and its consumers never move mass out of the stay group.
    def self.foe_prior(foe_actions)
      out = foe_actions.map { 0.0 }
      total = 0.0
      foe_actions.each_with_index do |action, i|
        next if action["kind"] != "stay"
        pct = Model.number(action["pct"], 0.0)
        pct = 0.0 if pct < 0.0
        out[i] = pct
        total += pct
      end
      return nil if total <= 0.0
      out.map { |v| v / total }
    end

    def self.expected_value(row, weights)
      total = 0.0
      row.each_with_index { |v, i| total += v * Model.number(weights[i], 0.0) }
      total
    end

    # Worst reply blended with the expected one by the mix: 0 is the min, 1 the
    # expectation.
    def self.row_value(row, weights, mix)
      return row.min if mix <= 0.0
      row.min * (1.0 - mix) + expected_value(row, weights) * mix
    end

    def self.depth_of(config)
      depth = Model.number((config || {})["search_depth"], DEFAULT_DEPTH).to_i
      depth < 1 ? 1 : depth
    end

    # Worst case first, then the mean, then a stable key -- so a tie never depends on
    # the order the adapter happened to export actions in.
    def self.compare(a, b)
      by_score = b["score"] <=> a["score"]
      return by_score if by_score != 0
      by_mean = b["search_mean"] <=> a["search_mean"]
      return by_mean if by_mean != 0
      key(a) <=> key(b)
    end

    def self.key(candidate)
      [candidate["type"].to_s, candidate["slot"].to_i,
       candidate["move_id"].to_s, candidate["target"].to_i]
    end

    # ------------------------------------------------------------------------------
    # The board. Four numbers: which body stands on each side and the HP it stands on.
    # Every other body's HP is read from the side tables, which a turn does not touch.

    def self.opening_board(snapshot, config = {})
      m = PortableAI.matrix(snapshot)
      own_slot = PortableAI.matrix_slot(m["own"], snapshot["actors"][0]["index"])
      foe_slot = PortableAI.matrix_slot(m["foe"], snapshot["targets"][0]["index"])
      return nil if own_slot.nil? || foe_slot.nil?
      own = PortableAI.matrix_entry(m["own"], own_slot)
      foe = PortableAI.matrix_entry(m["foe"], foe_slot)
      return nil if own.nil? || foe.nil?
      actor = snapshot["actors"][0]
      target = snapshot["targets"][0]
      first = (actor["actions"] || [])[0] || {}
      own_hp = Model.number(own["hp_pct"], 100.0)
      foe_hp = Model.number(foe["hp_pct"], 100.0)
      { "own_slot" => own_slot, "foe_slot" => foe_slot,
        "own_hp" => own_hp,
        "foe_hp" => foe_hp,
        # EVERY BODY'S HP AS THIS SEARCH HAS CHANGED IT, by slot; a slot not here still
        # stands on its side-table number. own_hp / foe_hp are the on-field entries of
        # these maps, kept beside them for the readers. Without the maps a body that
        # took a hit and left the field came back at full table HP, so at depth two
        # every hit we landed was erased whenever the foe's worst case was a switch --
        # which it usually is -- and only stages, hazards and status survived a ply.
        # The planner clicked Rock Polish and Stealth Rock everywhere and won 15 of
        # 60. The 0.7.0 bug where a switch-in inherited the OUTGOING body's HP was
        # this one's mirror image.
        "own_hps" => { own_slot => own_hp },
        "foe_hps" => { foe_slot => foe_hp },
        # THE NARROW, THICK VIEW OF THE PAIR ON THE FIELD, kept beside the wide one.
        # A cell deliberately carries no Choice lock, no Intimidate, no hazards and no
        # priority (see matrix.rb) -- it answers "does this body beat that body", not
        # "what happens this turn". Using it as a per-turn damage number was this
        # planner's second bug and a worse one than the first: a Choice-Scarf Galvantula
        # locked into a 24% move read as a 174% Bug Buzz, so a healthy Sceptile scored
        # every move as a certain death and fled. These two fields are what every rule
        # in core.rb reads for the same question, and they are Choice-aware.
        "live_incoming" => (actor["incoming_damage_pct"].nil? ? nil :
                            Model.number(actor["incoming_damage_pct"], 0.0)),
        "live_faster" => actor["faster"],
        # Which pair those two numbers describe. A projected board where either body
        # has changed is not that pair any more, whatever slot it happens to sit on.
        "live_pair" => [own_slot, foe_slot],
        # Root facts a deeper ply needs: whether the actor may leave (only meaningful
        # while it is the body on the field) and whether the foe may.
        "own_trapped" => Model.truthy(actor["trapped"]),
        "foe_trapped" => Model.truthy(target["trapped"]),
        # What the turn can change besides HP, each in the original's evaluate terms.
        # Stages belong to the body on the field and are lost with it (own_stages
        # empties on a switch; foe_boost zeroes on theirs). The rest are DELTAS this
        # turn makes -- a status landed, a hazard laid, a Substitute standing -- so a
        # body's existing status, which every row carries alike, is not re-counted.
        "own_stages" => decode_stages(actor["stages"]),
        # AND WHICH OF THOSE THE ENGINE HAS ALREADY PRICED IN. Every number the root
        # exports -- expected_damage_pct, the live pair's cell, the side table's Speed
        # -- was rolled through the actor's real stages. Scaling them by own_stages
        # again counted a +2 body as +4 (0.7.1-0.7.3). Only the stages this search
        # PROJECTS on top scale a number; the leaf's boost term still reads the total,
        # because a switch really does throw the whole stack away.
        "stage_base" => decode_stages(actor["stages"]),
        "foe_boost" => Model.number(target["positive_stages"], 0.0) * FOE_STAGE_VALUE,
        "foe_status_points" => 0.0,
        "own_status_points" => 0.0,
        "foe_hazard_points" => 0.0,
        "substitute" => Model.truthy(actor["substitute"]),
        "protected" => false,
        "protect_repeats" => memory_count(snapshot, actor["index"], "protect"),
        # The opponent model's input: what the adapter predicts the foe on the field
        # will do. This turn's only -- project drops it, and plan reads it once.
        "foe_reply" => predicted_reply(snapshot),
        # 0.7.9. The foe's side of the same terms, so act_foe has somewhere to put
        # what its move does; the statuses both bodies stand under (they tick, and
        # they decide whether the body acts); what the foe already laid on our side.
        "foe_stages" => {},
        "own_status" => (status_key(own) || status_key(actor)),
        "foe_status" => (status_key(foe) || status_key(target)),
        "own_seeded" => false, "foe_seeded" => false,
        "own_toxic" => 0, "foe_toxic" => 0,
        "foe_substitute" => (Model.truthy(first["target_substitute"]) ||
                             Model.truthy(target["substitute"])),
        "foe_protected" => false,
        "foe_protect_repeats" => 0,
        "own_hazard_points" => 0.0,
        "own_hazard_layers" => Model.number(first["own_hazard_layers"], 0.0),
        "foe_laid" => {} }
    end

    # The adapter exports stages as the engine's array (PBStats order: attack 1,
    # defence 2, speed 3, special attack 4, special defence 5) or, on a thinner
    # adapter, as a Hash in the core's own short names. Either way out come the names.
    STAGE_INDEX = { "atk" => 1, "def" => 2, "speed" => 3, "spa" => 4, "spd" => 5 }

    def self.decode_stages(raw)
      out = {}
      if raw.is_a?(Array)
        STAGE_INDEX.each do |name, index|
          value = Model.number(raw[index], 0.0).to_i
          out[name] = value if value != 0
        end
      elsif raw.is_a?(Hash)
        STAGE_INDEX.each_key do |name|
          value = Model.number(raw[name], 0.0).to_i
          out[name] = value if value != 0
        end
      end
      out
    end

    def self.memory_count(snapshot, actor_index, key)
      memory = snapshot["memory"] || {}
      actor = memory[actor_index.to_s] || memory[actor_index] || {}
      Model.number(actor[key], 0).to_i
    end

    # WHAT THE FOE CAN DO. One column per move it owns, plus one per body on its bench.
    #
    # 0.7.7. THROUGH 0.7.6 THIS WAS ONE `stay` COLUMN priced at the foe's BEST hit --
    # "it attacks, at worst" -- and that was the whole model of the opponent. It made
    # 0.7.6's tree a fair-weather test of MCTS: a search whose entire thesis is that
    # the foe's line should be shaped by the foe's own payoff was handed an opponent
    # with one way to act, so per-side UCB had nothing to discover (41/60 at 1000
    # iterations, 43 at 5000, against the maximin's 46). The cell now carries the
    # foe's own per-move rolls (`in_moves`, matrix version 3 -- the mirror of the
    # `out_moves` 0.7.4 added for us, and the same rolls the adapter was already
    # making to find `in`), so the foe picks a MOVE here, not just "attack".
    #
    # 0.7.9. AND EVERY MOVE, NOT ONLY THE DAMAGING ONES. Version 3 listed the moves
    # `pbIsDamaging?` said yes to, so the tree's foe could attack or switch and do
    # nothing else -- never set up, heal, lay a hazard, Protect or land a status --
    # while our own root row was priced for all of those (0.7.2). The original hands
    # both sides the whole move list. A status column carries pct 0 and its effect
    # triple; `act_foe` plays it the way `act_own` plays ours.
    #
    # A cell without the list -- an older adapter, a pair the matrix never rolled --
    # is one `stay` column at the best hit, which is 0.7.6 exactly. That fallback is
    # also every Reborn run, which exports no matrix at all.
    #
    # NOTE FOR MAXIMIN: its worst case over these columns is still the biggest hit, so
    # `search_foe_mix` 0 is very nearly unchanged by this. What moves is the EXPECTED
    # reply (more columns to spread over, see column_weights) and the tree.
    #
    # A trapped foe has no switch column. The original's option generator respects
    # trapping; without this a trapper's whole advantage was invisible here, and a foe
    # switch was the worst case on 41% of turns.
    #
    # After a faint the ply is a replacement: the side that lost a body picks a
    # replacement and the other side does nothing (the original's force_switch
    # options, MoveChoice::None opposite). Both down, both pick.
    def self.foe_options(snapshot, board)
      m = PortableAI.matrix(snapshot)
      bench = PortableAI.matrix_live_slots(m["foe"]).reject { |slot| slot == board["foe_slot"] }
      return bench.map { |slot| { "kind" => "switch", "slot" => slot } } if board["foe_hp"] <= 0
      return [{ "kind" => "none" }] if board["own_hp"] <= 0
      out = foe_moves(snapshot, board)
      return out if board["foe_trapped"] && board["foe_slot"] == board["live_pair"][1]
      bench.each { |slot| out << { "kind" => "switch", "slot" => slot } }
      out
    end

    # The foe's move columns for the pair standing on the board. Sorted by move id --
    # a Ruby 1.8 Hash has no order of its own, and a column list that varied between
    # two runs of the same position would make every paired arm unrepeatable.
    def self.foe_moves(snapshot, board)
      cell = PortableAI.matrix_cell(snapshot, board["own_slot"], board["foe_slot"])
      moves = cell && cell["in_moves"]
      return [{ "kind" => "stay" }] if !moves.is_a?(Hash) || moves.empty?
      out = []
      moves.keys.sort.each do |move_id|
        entry = moves[move_id]
        next if !entry.is_a?(Hash)
        out << { "kind" => "stay", "move_id" => move_id,
                 "pct" => Model.number(entry["pct"], 0.0), "cat" => entry["cat"],
                 "damaging" => (entry.key?("damaging") ? Model.truthy(entry["damaging"]) :
                                Model.number(entry["pct"], 0.0) > 0.0),
                 "acc" => entry["acc"], "priority" => Model.number(entry["priority"], 0.0),
                 "effect" => (entry["effect"].is_a?(Array) ? entry["effect"] : [nil, nil, nil]) }
      end
      out.empty? ? [{ "kind" => "stay" }] : out
    end

    # The cell's own roll of one of the FOE's moves; the mirror of cell_move.
    def self.cell_in_move(cell, move_id)
      return nil if cell.nil? || move_id.nil?
      moves = cell["in_moves"]
      return nil if !moves.is_a?(Hash)
      entry = moves[move_id.to_s.upcase]
      entry.is_a?(Hash) ? entry : nil
    end

    # How a foe column reads in a trace: the move it names, or the body it brings in.
    def self.foe_label(option)
      return "switch:#{option['slot']}" if option["kind"] == "switch"
      return "none" if option["kind"] == "none"
      option["move_id"].nil? ? "stay" : "stay:#{option['move_id']}"
    end

    # OUR options from a projected board, for the plies below the root. The root's
    # exported actions are the truth about THIS turn (legality, PP, the Choice lock,
    # every per-move number against the foe on the field) and they stay the truth as
    # long as the same two bodies stand there. Any other pair has the matrix: 0.7.9,
    # every move the cell lists for the body (out_moves, version 4), built into the
    # same action shape the root exports -- so a switch-in can set up, Protect or
    # land a status below the root, as the original's option generator lets it.
    # Through 0.7.8 it had ONE attack worth the cell, and a switch read as a body
    # that could only ever hit. A cell without the list still gets that one attack.
    def self.own_options(snapshot, board, root_actions)
      m = PortableAI.matrix(snapshot)
      bench = PortableAI.matrix_live_slots(m["own"]).reject { |slot| slot == board["own_slot"] }
      if board["own_hp"] <= 0
        return bench.map { |slot| bench_switch(m, slot, board, root_actions, true) }
      end
      return [{ "type" => "none" }] if board["foe_hp"] <= 0
      out = []
      if live_pair?(board)
        root_actions.each { |a| out << a if a["type"] == "move" }
      else
        cell = PortableAI.matrix_cell(snapshot, board["own_slot"], board["foe_slot"])
        out = cell_actions(cell)
      end
      trapped = board["own_trapped"] && board["own_slot"] == board["live_pair"][0]
      bench.each { |slot| out << bench_switch(m, slot, board, root_actions, false) } if !trapped
      out
    end

    # A cell's out_moves as root-shaped actions, sorted by id for the same reason
    # foe_moves sorts. No list: one attack worth the cell's best number.
    def self.cell_actions(cell)
      moves = cell && cell["out_moves"]
      if !moves.is_a?(Hash) || moves.empty?
        return [{ "type" => "move", "move_id" => "MATRIX_ATTACK", "slot" => 0,
                  "damaging" => true, "accuracy" => 100,
                  "expected_damage_pct" => (cell.nil? ? 0.0 : Model.number(cell["out"], 0.0)) }]
      end
      out = []
      moves.keys.sort.each do |move_id|
        entry = moves[move_id]
        next if !entry.is_a?(Hash)
        effect = entry["effect"].is_a?(Array) ? entry["effect"] : [nil, nil, nil]
        pct = Model.number(entry["pct"], 0.0)
        out << { "type" => "move", "move_id" => move_id, "slot" => 0,
                 "damaging" => (entry.key?("damaging") ? Model.truthy(entry["damaging"]) : pct > 0.0),
                 "accuracy" => (entry["acc"].nil? ? 100 : Model.number(entry["acc"], 100.0)),
                 "priority" => Model.number(entry["priority"], 0.0),
                 "expected_damage_pct" => pct,
                 "effect_kind" => effect[0], "effect_stat" => effect[1],
                 "effect_chance" => effect[2], "tags" => [] }
      end
      out
    end

    # A switch to a bench body, priced from the side table -- or, when the root
    # exported this very switch against this very foe, from the root's own numbers.
    # 0.7.9: the hazard damage a switch-in pays does not depend on who it faces, so a
    # switch below the root reads it from the root's export of the same slot, else
    # from the side table -- through 0.7.8 it was 0 there, which made a chain of
    # switches under Stealth Rock free.
    def self.bench_switch(m, slot, board, root_actions, forced)
      exported = nil
      root_actions.each do |a|
        next if a["type"] != "switch" || a["slot"] != slot
        exported = a
        break
      end
      if !exported.nil? && board["foe_slot"] == board["live_pair"][1]
        return exported if !forced
        copy = Model.copy_hash(exported)
        copy["forced"] = true
        return copy
      end
      entry = PortableAI.matrix_entry(m["own"], slot)
      hazard = exported.nil? ? Model.number(entry && entry["entry_damage_pct"], 0.0) :
                               Model.number(exported["entry_damage_pct"], 0.0)
      { "type" => "switch", "slot" => slot, "forced" => forced,
        "candidate_hp_pct" => Model.number(entry && entry["hp_pct"], 100.0),
        "entry_damage_pct" => hazard }
      # (project reads the search's own HP map for this slot first, so a body this
      # search already damaged comes back at that HP, not the table's.)
    end

    def self.live_pair?(board)
      board["own_slot"] == board["live_pair"][0] && board["foe_slot"] == board["live_pair"][1]
    end

    # The value of one cell of the grid: the leaf averaged over every chance branch the
    # turn has (`outcomes`). Through 0.7.8 the branches were the speed order and OUR
    # accuracy, and every damage number was taken as it came. 0.7.9 branches what the
    # original branches: both sides' accuracy, whether a paralysed, asleep or frozen
    # body acts at all, and THE DAMAGE ROLL -- see roll_outcomes for why that one
    # matters more than the rest put together.
    def self.payoff(snapshot, board, own_action, foe_action, depth = 1, root_actions = [])
      total = 0.0
      outcomes(snapshot, board, own_action, foe_action, true).each do |spec|
        after = project(snapshot, board, own_action, foe_action, spec[1], true, spec[2])
        total += spec[0] * value_of(snapshot, after, depth - 1, root_actions)
      end
      total
    end

    # What a board is worth with `depth` plies still to look: the leaf when none are
    # left or the battle is over, otherwise the safest reply grid from it -- the
    # original's expectiminimax, which scores a sub-game by pick_safest.
    def self.value_of(snapshot, board, depth, root_actions)
      return leaf(snapshot, board) if depth <= 0
      over = battle_over(snapshot, board)
      return over + (over > 0 ? DEPTH_BONUS : -DEPTH_BONUS) * depth if !over.nil?
      own = own_options(snapshot, board, root_actions)
      foe = foe_options(snapshot, board)
      return leaf(snapshot, board) if own.empty? || foe.empty?
      safest(snapshot, board, own, foe, depth, root_actions)
    end

    # pick_safest with the original's pruning: a row whose running minimum has already
    # fallen to the best row's minimum cannot become the best row, so the rest of it
    # is never projected.
    def self.safest(snapshot, board, own, foe, depth, root_actions)
      best = -HUGE
      own.each do |action|
        worst = HUGE
        foe.each do |reply|
          value = payoff(snapshot, board, action, reply, depth, root_actions)
          worst = value if value < worst
          break if worst <= best
        end
        best = worst if worst > best
      end
      best
    end

    def self.battle_over(snapshot, board)
      m = PortableAI.matrix(snapshot)
      return -BATTLE_OVER if side_value(m["own"], board["own_hps"])["alive"] == 0
      return BATTLE_OVER if side_value(m["foe"], board["foe_hps"])["alive"] == 0
      nil
    end

    # 0.0..1.0. A switch always "lands"; a move lands at its exported accuracy.
    def self.hit_chance(own_action)
      return 1.0 if own_action["type"] != "move"
      accuracy = Model.number(own_action["accuracy"], 100.0)
      # A self-targeting move exports no meaningful accuracy; it does not miss.
      accuracy = 100.0 if accuracy <= 0 && !Model.truthy(own_action["damaging"])
      accuracy = 100.0 if accuracy > 100.0
      accuracy = 0.0 if accuracy < 0
      accuracy / 100.0
    end

    # The foe's mirror: a named column lands at the cell's accuracy for it (0.7.9;
    # through 0.7.8 the foe never missed, which was maximin's worst case carried into
    # a tree where it no longer meant that). A column without one is certain.
    def self.foe_hit_chance(foe_action)
      return 1.0 if foe_action["kind"] != "stay" || foe_action["acc"].nil?
      accuracy = Model.number(foe_action["acc"], 100.0)
      accuracy = 100.0 if accuracy <= 0 && !Model.truthy(foe_action["damaging"])
      accuracy = 100.0 if accuracy > 100.0
      accuracy = 0.0 if accuracy < 0
      accuracy / 100.0
    end

    # The chance a body under a status gets its move off at all: the engine's own
    # numbers for paralysis and thaw; sleep at a third, the average over a counter the
    # snapshot does not carry. The original branches on all three.
    def self.act_chance(status)
      ACT_CHANCE[status.to_s] || 1.0
    end

    # THE DAMAGE ROLL. Every number the adapter hands this planner -- a cell's pct,
    # a root action's expected_damage_pct -- is pbRoughDamage, which applies NO random
    # factor and no crit: it is the MAXIMUM roll. The engine then rolls 85..100% of
    # it (082:1140). core.rb has always known this (MIN_DAMAGE_ROLL); through 0.7.8
    # this planner took the number as an expected roll, its header said so, and with a
    # step leaf at 0 HP a kill that lands on one roll in sixteen read as certain --
    # on both axes, at every ply. That is the single largest thing the search had
    # wrong about the board.
    #
    # What comes back is a list of [multiplier, probability] on the max roll -- the
    # original's `should_branch_on_damage` shape, at its arithmetic:
    #   * the roll straddles the defender's HP: a KILL branch at the fraction of the
    #     sixteen rolls that reach it, plus the crit rate, against the average of the
    #     rolls that do not;
    #   * every roll falls short: a crit branch at the crit rate, else the average;
    #   * every roll kills: one branch, certain.
    # `branch` false (below the root's children in the tree, as the original) is the
    # average roll and nothing else.
    def self.roll_outcomes(max_pct, hp, branch)
      return [[1.0, 1.0]] if max_pct <= 0.0
      return [[ROLL_AVERAGE, 1.0]] if !branch
      min_pct = max_pct * ROLL_MIN
      if max_pct >= hp && min_pct < hp
        kills = 0
        sum = 0.0
        16.times do |r|
          mult = (85 + r) / 100.0
          if max_pct * mult >= hp
            kills += 1
          else
            sum += mult
          end
        end
        p_kill = (1.0 - CRIT_RATE) * kills / 16.0 + CRIT_RATE
        misses = 16 - kills
        rest = misses > 0 ? sum / misses : ROLL_AVERAGE
        return [[1.0, p_kill], [rest, 1.0 - p_kill]]
      end
      return [[1.0, 1.0]] if min_pct >= hp
      [[ROLL_AVERAGE * CRIT_MULT, CRIT_RATE], [ROLL_AVERAGE, 1.0 - CRIT_RATE]]
    end

    # EVERY CHANCE OUTCOME OF ONE JOINT PAIR, each as [probability, own_first, chance]
    # where `chance` is what project reads: whether each side's move happens at all
    # (accuracy times the status act chance -- a miss and a full paralysis are the
    # same board, so they are one dimension), and the roll multiplier each lands at.
    # The speed order splits first when nothing establishes it. Shared by the maximin
    # (payoff averages over it) and the tree (branches keeps it as children). Sums to
    # one.
    def self.outcomes(snapshot, board, own_action, foe_action, branch_rolls)
      first = moves_first(snapshot, board, own_action, foe_action)
      orders = first.nil? ? [[true, 0.5], [false, 0.5]] : [[first, 1.0]]
      own_does = own_action["type"] == "move" ?
                 hit_chance(own_action) * act_chance(board["own_status"]) : 1.0
      foe_does = foe_action["kind"] == "stay" ?
                 foe_hit_chance(foe_action) * act_chance(board["foe_status"]) : 1.0
      after = resolve_switches(snapshot, board, own_action, foe_action)
      own_rolls = roll_outcomes(own_damage(snapshot, board, after, own_action, foe_action),
                                after["foe_hp"], branch_rolls)
      foe_rolls = roll_outcomes(foe_damage(snapshot, board, after, own_action, foe_action),
                                after["own_hp"], branch_rolls)
      own_side = []
      own_rolls.each { |roll| own_side << [own_does * roll[1], true, roll[0]] } if own_does > 0.0
      own_side << [1.0 - own_does, false, 1.0] if own_does < 1.0
      foe_side = []
      foe_rolls.each { |roll| foe_side << [foe_does * roll[1], true, roll[0]] } if foe_does > 0.0
      foe_side << [1.0 - foe_does, false, 1.0] if foe_does < 1.0
      out = []
      orders.each do |order|
        own_side.each do |o|
          foe_side.each do |f|
            prob = order[1] * o[0] * f[0]
            next if prob <= 0.0
            out << [prob, order[0],
                    { "own_does" => o[1], "own_roll" => o[2],
                      "foe_does" => f[1], "foe_roll" => f[2] }]
          end
        end
      end
      out
    end

    # true we move first, false they do, nil unknown.
    #
    # Only two moves make the question meaningful. With a switch on either side at most
    # one side deals damage that turn, so both orders project the identical board and
    # the answer here is immaterial -- true, to spend one projection rather than two.
    def self.moves_first(snapshot, board, own_action, foe_action)
      return true if own_action["type"] != "move" || foe_action["kind"] != "stay"
      priority = Model.number(own_action["priority"], 0.0)
      # 0.7.9: the foe's column carries its bracket too (version 4), so a foe's
      # Protect or Sucker Punch is no longer invisible here.
      theirs = Model.number(foe_action["priority"], 0.0)
      return true if priority > theirs
      return false if theirs > priority
      # The adapter's own speed answer for the pair on the field, which reads a Choice
      # Scarf the cell does not. Only the cell knows about hypothetical pairs, and
      # only the transformed cell knows about a speed stage we projected.
      stages = projected_stages(board)
      foe_speed_stage = Model.number((board["foe_stages"] || {})["speed"], 0.0).to_i
      if live_pair?(board) && Model.number(stages["speed"], 0.0).to_i == 0 && foe_speed_stage == 0
        live = board["live_faster"]
        return live if live == true || live == false
      end
      cell = PortableAI.matrix_cell(snapshot, board["own_slot"], board["foe_slot"])
      cell = boosted_cell(snapshot, PortableAI.matrix(snapshot), board, cell)
      return nil if cell.nil?
      faster = cell["faster"]
      (faster == true || faster == false) ? faster : nil
    end

    # The board after both switches and before either move: which bodies stand
    # there and at what HP. A switch-in pays its hazard damage here (both sides,
    # 0.7.9 -- the foe's from the side table). Everything a switch throws away
    # (stages, a Substitute, this turn's status delta) goes with the body.
    def self.resolve_switches(snapshot, board, own_action, foe_action)
      out = Model.copy_hash(board)
      out["protected"] = false
      out["foe_protected"] = false
      out["foe_reply"] = nil
      out["own_hps"] = Model.copy_hash(board["own_hps"])
      out["foe_hps"] = Model.copy_hash(board["foe_hps"])
      m = PortableAI.matrix(snapshot)
      if own_action["type"] == "switch"
        out["own_slot"] = own_action["slot"]
        standing = out["own_hps"].key?(out["own_slot"]) ? out["own_hps"][out["own_slot"]] :
                   Model.number(own_action["candidate_hp_pct"], 100.0)
        out["own_hp"] = standing - Model.number(own_action["entry_damage_pct"], 0.0)
        # Stages, a Substitute and this turn's own status go with the body that left.
        out["own_stages"] = {}
        out["stage_base"] = {}
        out["substitute"] = false
        out["own_status_points"] = 0.0
        out["own_seeded"] = false
        out["own_toxic"] = 0
        out["own_status"] = status_key(PortableAI.matrix_entry(m["own"], out["own_slot"]))
      end
      if foe_action["kind"] == "switch"
        out["foe_slot"] = foe_action["slot"]
        # AND THE HP THAT BODY IS ACTUALLY STANDING ON. Leaving this at the outgoing
        # body's HP was the first version's worst bug: with the active foe chipped,
        # every one of its switches read as a free kill for us, so five of six foe
        # options scored a kill and maximin was choosing between fictions. The
        # switch-in's HP is in the same side table the board was opened from.
        entry = PortableAI.matrix_entry(m["foe"], foe_action["slot"])
        standing = out["foe_hps"].key?(out["foe_slot"]) ? out["foe_hps"][out["foe_slot"]] :
                   Model.number(entry && entry["hp_pct"], 100.0)
        out["foe_hp"] = standing - Model.number(entry && entry["entry_damage_pct"], 0.0)
        out["foe_boost"] = 0.0
        out["foe_stages"] = {}
        out["foe_status_points"] = 0.0
        out["foe_substitute"] = false
        out["foe_seeded"] = false
        out["foe_toxic"] = 0
        out["foe_status"] = status_key(entry)
      end
      out
    end

    # One turn, applied to a copy. Switches resolve first; then each side acts in
    # speed order, and the body that came in eats the other side's hit in full -- the
    # same free-hit convention candidate_race charges a switch candidate (core.rb).
    # `hit` is our accuracy branch: false and our move does nothing at all, damage and
    # effects alike. `chance` (0.7.9) is the full outcome from `outcomes`: whether
    # each side's move happens and the roll it lands at; absent, the foe acts, and
    # both land at the raw number. Then the end of turn ticks (residual).
    def self.project(snapshot, board, own_action, foe_action, own_first, hit = true, chance = nil)
      chance = chance || {}
      own_does = chance.key?("own_does") ? chance["own_does"] : hit
      foe_does = chance.key?("foe_does") ? chance["foe_does"] : true
      out = resolve_switches(snapshot, board, own_action, foe_action)

      # Damage each side lands AFTER both switches have resolved, so an attack aimed at
      # a body that left hits the one that replaced it -- which is the whole reason a
      # foe switch is worth considering.
      mine = own_does ? own_damage(snapshot, board, out, own_action, foe_action) *
                        Model.number(chance["own_roll"], 1.0) : 0.0
      theirs = foe_does ? foe_damage(snapshot, board, out, own_action, foe_action) *
                          Model.number(chance["foe_roll"], 1.0) : 0.0

      if own_first
        act_own(snapshot, out, own_action, mine, own_does)
        act_foe(snapshot, out, foe_action, theirs, foe_does) if out["foe_hp"] > 0 && out["own_hp"] > 0
      else
        act_foe(snapshot, out, foe_action, theirs, foe_does)
        act_own(snapshot, out, own_action, mine, own_does) if out["own_hp"] > 0 && out["foe_hp"] > 0
      end
      residual(snapshot, out)
      out["own_hp"] = 0.0 if out["own_hp"] < 0
      out["foe_hp"] = 0.0 if out["foe_hp"] < 0
      out["own_hp"] = 100.0 if out["own_hp"] > 100.0
      out["foe_hp"] = 100.0 if out["foe_hp"] > 100.0
      out["own_hps"][out["own_slot"]] = out["own_hp"]
      out["foe_hps"][out["foe_slot"]] = out["foe_hp"]
      # Next ply's Protect fails if this one was a Protect, on either side.
      out["protect_repeats"] = out["protected"] ? 1 : 0
      out["foe_protect_repeats"] = out["foe_protected"] ? 1 : 0
      out
    end

    # Our action on the board: the damage, then everything the move does besides,
    # each the original's evaluate term applied where the original's instruction
    # generator would apply it. A miss (hit false) applies nothing. A foe Protect
    # (0.7.9) takes the whole move; a foe Substitute takes the damage and every
    # effect aimed at the body behind it, and breaks unless the hit was under its HP.
    def self.act_own(snapshot, out, action, damage, hit)
      return if action["type"] != "move" || !hit
      return if out["foe_protected"]
      tags = Effects.describe(action["move_id"], action["tags"])
      move_id = action["move_id"].to_s.upcase
      shielded = out["foe_substitute"] ? true : false
      if shielded
        out["foe_substitute"] = false if damage >= SUBSTITUTE_COST
      else
        out["foe_hp"] -= damage
      end

      if damage > 0
        recoil = Model.number(action["recoil_fraction"], 0.0)
        out["own_hp"] -= damage * recoil if recoil > 0
        drain = Model.number(action["drain_fraction"], 0.0)
        out["own_hp"] = [100.0, out["own_hp"] + damage * drain].min if drain > 0 && !shielded
      end
      out["own_hp"] = 0.0 if tags.include?("self_ko")

      if tags.include?("setup")
        stages = Effects.setup_stages(move_id)
        if tags.include?("hp_cost_half")
          # Belly Drum fails below half; above it, half is the price.
          stages = nil if out["own_hp"] <= 50.0
          out["own_hp"] -= 50.0 if !stages.nil?
        end
        add_stages(out, stages)
      end
      add_stages(out, Effects.self_drop_stages(move_id)) if tags.include?("self_drop")
      if action["effect_kind"].to_s == "self_raise" &&
         Model.number(action["effect_chance"], 100.0) >= 100.0
        add_stages(out, { action["effect_stat"].to_s => 1 })
      end

      if tags.include?("heal") || tags.include?("variable_heal")
        out["own_hp"] = [100.0, out["own_hp"] + Effects.heal_amount(snapshot, tags)].min
        if tags.include?("self_sleep")
          out["own_status_points"] -= STATUS_VALUE["sleep"]
          out["own_status"] = "sleep"
        end
      end

      # Protect fails on a repeat; the memory counter is the only record of one.
      if tags.include?("protect") && out["protect_repeats"] <= 0
        out["protected"] = true
      end
      if tags.include?("substitute") && !out["substitute"] && out["own_hp"] > SUBSTITUTE_COST
        out["own_hp"] -= SUBSTITUTE_COST
        out["substitute"] = true
      end

      if tags.include?("hazard")
        layers = Model.number(action["existing_layers"], 0.0)
        cap = Model.number(action["max_layers"], 1.0)
        if layers < cap
          per_body = HAZARD_VALUE[move_id] || 0.0
          bodies = PortableAI.matrix_live_slots(PortableAI.matrix(snapshot)["foe"]).length
          out["foe_hazard_points"] += per_body * bodies
        end
      end

      # A status or a stat drop on the foe, at the chance the adapter exported: 100 for
      # a status move the engine says can land, 0 for one it says cannot (already
      # statused, immune, Sheer Force), the secondary rate for a damaging move.
      return if shielded
      kind = action["effect_kind"]
      kind = Effects.kind_of(tags, "secondary") if kind.nil?
      kind = status_kind(tags) if kind.nil? && tags.include?("status")
      return if kind.nil?
      # One status per body: a second Toxic on a foe this search already poisoned is
      # the engine refusing it, which the root's chance export cannot know a ply on.
      return if tags.include?("status") && (out["foe_status_points"] > 0 || !out["foe_status"].nil?)
      chance = Model.number(action["effect_chance"], 100.0)
      return if chance <= 0
      chance = 100.0 if chance > 100.0
      kind = kind.to_s
      if kind == "drop"
        value = STAGE_VALUE[action["effect_stat"].to_s] || 0.0
        out["foe_boost"] -= value * chance / 100.0
      elsif STATUS_VALUE.key?(kind)
        value = STATUS_VALUE[kind]
        value = value * (Model.truthy(action["target_physical_attacker"]) ? 1.0 : 0.5) if kind == "burn"
        value = STATUS_VALUE["toxic"] if kind == "poison" && move_id == "TOXIC"
        out["foe_status_points"] += value * chance / 100.0
        # A certain status is on the body for the plies that follow: it ticks, and
        # it decides whether the body acts. A secondary is points only.
        if chance >= 100.0
          if kind == "drain"
            out["foe_seeded"] = true
          elsif !out["foe_status"].nil?
            # already carrying one
          else
            out["foe_status"] = (kind == "poison" && move_id == "TOXIC") ? "toxic" : kind
          end
        end
      end
    end

    # THEIR action on the board (0.7.9), the mirror of act_own: the damage through our
    # Protect or Substitute, then whatever the column's move does besides -- its own
    # setup or drop, a heal, a Protect, a Substitute, a hazard on our side, a status
    # or a stat drop on us -- from the tags its id carries and the effect triple the
    # cell exported. Through 0.7.8 this was the damage and nothing else, because the
    # foe's columns were damaging moves and nothing else.
    def self.act_foe(snapshot, out, foe_action, damage, acts = true)
      return if foe_action["kind"] != "stay" || !acts
      return if out["protected"]
      shielded = out["substitute"] ? true : false
      if damage > 0
        if shielded
          out["substitute"] = false if damage >= SUBSTITUTE_COST
        else
          out["own_hp"] -= damage
        end
      end
      move_id = foe_action["move_id"]
      return if move_id.nil?
      move_id = move_id.to_s.upcase
      tags = Effects.describe(move_id, [])
      out["foe_hp"] = 0.0 if tags.include?("self_ko")

      if tags.include?("setup")
        stages = Effects.setup_stages(move_id)
        if tags.include?("hp_cost_half")
          stages = nil if out["foe_hp"] <= 50.0
          out["foe_hp"] -= 50.0 if !stages.nil?
        end
        add_stages(out, stages, "foe_stages")
      end
      add_stages(out, Effects.self_drop_stages(move_id), "foe_stages") if tags.include?("self_drop")

      if tags.include?("heal") || tags.include?("variable_heal")
        out["foe_hp"] = [100.0, out["foe_hp"] + Effects.heal_amount(snapshot, tags)].min
        if tags.include?("self_sleep")
          out["foe_status_points"] += STATUS_VALUE["sleep"]
          out["foe_status"] = "sleep"
        end
      end
      if tags.include?("protect") && Model.number(out["foe_protect_repeats"], 0.0) <= 0
        out["foe_protected"] = true
      end
      if tags.include?("substitute") && !out["foe_substitute"] && out["foe_hp"] > SUBSTITUTE_COST
        out["foe_hp"] -= SUBSTITUTE_COST
        out["foe_substitute"] = true
      end
      if tags.include?("hazard")
        # The snapshot carries our side's hazards as one count, so a foe hazard lands
        # when our side is clear and this search has not laid this one already.
        laid = out["foe_laid"] || {}
        if Model.number(out["own_hazard_layers"], 0.0) <= 0 && !laid[move_id]
          per_body = HAZARD_VALUE[move_id] || 0.0
          bodies = PortableAI.matrix_live_slots(PortableAI.matrix(snapshot)["own"]).length
          out["own_hazard_points"] += per_body * bodies
          laid = Model.copy_hash(laid)
          laid[move_id] = true
          out["foe_laid"] = laid
        end
      end

      return if shielded
      effect = foe_action["effect"].is_a?(Array) ? foe_action["effect"] : [nil, nil, nil]
      kind = effect[0]
      kind = status_kind(tags) if kind.nil? && tags.include?("status")
      return if kind.nil?
      return if tags.include?("status") && (out["own_status_points"] < 0 || !out["own_status"].nil?)
      chance = Model.number(effect[2], 100.0)
      return if chance <= 0
      chance = 100.0 if chance > 100.0
      kind = kind.to_s
      if kind == "drop"
        add_stages(out, { effect[1].to_s => -1 }) if chance >= 100.0
      elsif kind == "self_raise"
        add_stages(out, { effect[1].to_s => 1 }, "foe_stages") if chance >= 100.0
      elsif STATUS_VALUE.key?(kind)
        value = STATUS_VALUE[kind]
        value = STATUS_VALUE["toxic"] if kind == "poison" && move_id == "TOXIC"
        out["own_status_points"] -= value * chance / 100.0
        if chance >= 100.0
          if kind == "drain"
            out["own_seeded"] = true
          elsif out["own_status"].nil?
            out["own_status"] = (kind == "poison" && move_id == "TOXIC") ? "toxic" : kind
          end
        end
      end
    end

    # THE END OF THE TURN (0.7.9). What the original applies as end-of-turn
    # instructions every ply and this planner never did: Leftovers and Black Sludge,
    # burn, poison and the Toxic ladder, sand and hail on the bodies they touch, and
    # Leech Seed both ways. Through 0.7.8 a Toxic was thirty points forever and never
    # became HP, so an eight-ply tree could not see a stall matchup from either side.
    # Immunities the leaf knows about: Magic Guard (no residual damage at all), Poison
    # Heal, the sand and hail types and abilities.
    def self.residual(snapshot, out)
      m = PortableAI.matrix(snapshot)
      weather = (snapshot || {})["weather"].to_s
      ["own", "foe"].each do |side|
        hp_key = side + "_hp"
        next if out[hp_key] <= 0
        entry = PortableAI.matrix_entry(m[side], out[side + "_slot"]) || {}
        ability = entry["ability"].to_s.upcase
        item = entry["item"].to_s.upcase
        types = (entry["types"] || []).map { |t| t.to_s.upcase }
        guarded = ability == "MAGICGUARD"
        delta = 0.0
        if item == "LEFTOVERS"
          delta += RESIDUAL_SIXTEENTH
        elsif item == "BLACKSLUDGE"
          delta += types.include?("POISON") ? RESIDUAL_SIXTEENTH : (guarded ? 0.0 : -RESIDUAL_EIGHTH)
        end
        status = out[side + "_status"].to_s
        if status == "burn"
          delta -= RESIDUAL_EIGHTH if !guarded
        elsif status == "poison"
          delta += ability == "POISONHEAL" ? RESIDUAL_EIGHTH : (guarded ? 0.0 : -RESIDUAL_EIGHTH)
        elsif status == "toxic"
          count = Model.number(out[side + "_toxic"], 0.0).to_i + 1
          out[side + "_toxic"] = count
          delta += ability == "POISONHEAL" ? RESIDUAL_EIGHTH :
                   (guarded ? 0.0 : -RESIDUAL_SIXTEENTH * count)
        end
        if weather == "sand" && !guarded && !SAND_PROOF_ABILITIES.include?(ability) &&
           (types & SAND_PROOF_TYPES).empty?
          delta -= RESIDUAL_SIXTEENTH
        elsif weather == "hail" && !guarded && !HAIL_PROOF_ABILITIES.include?(ability) &&
              !types.include?("ICE")
          delta -= RESIDUAL_SIXTEENTH
        end
        if out[side + "_seeded"] && !guarded
          delta -= RESIDUAL_EIGHTH
          other = side == "own" ? "foe_hp" : "own_hp"
          out[other] += RESIDUAL_EIGHTH if out[other] > 0
        end
        out[hp_key] += delta
      end
      out
    end

    # The engine's status code on a side-table entry (PBStatuses: 1 sleep, 2 poison,
    # 3 burn, 4 paralysis, 5 frozen), as the name this planner keys on; nil healthy.
    def self.status_key(entry)
      return nil if entry.nil?
      raw = entry["status"]
      return nil if raw.nil?
      return STATUS_CODES[raw.to_i] if raw.is_a?(Numeric) || raw.to_s =~ /\A\d+\z/
      name = raw.to_s.downcase
      return nil if name == "" || name == "none" || name == "healthy" || name == "0"
      STATUS_NAMES[name] || name
    end

    def self.status_kind(tags)
      %w[poison burn paralyze sleep freeze confuse drain].each do |kind|
        return kind if tags.include?(kind)
      end
      nil
    end

    def self.add_stages(out, stages, key = "own_stages")
      return if stages.nil?
      merged = Model.copy_hash(out[key] || {})
      stages.each do |stat, delta|
        value = Model.number(merged[stat], 0.0).to_i + delta.to_i
        value = 6 if value > 6
        value = -6 if value < -6
        if value == 0
          merged.delete(stat)
        else
          merged[stat] = value
        end
      end
      out[key] = merged
    end

    # The damage our move lands when it lands. Accuracy is payoff's branch, not a
    # multiplier here.
    def self.own_damage(snapshot, board, projected, own_action, foe_action)
      return 0.0 if own_action["type"] != "move"
      cell = PortableAI.matrix_cell(snapshot, projected["own_slot"], projected["foe_slot"])
      priced = cell_move(cell, own_action["move_id"])
      category = priced ? priced["cat"] : nil
      raw = nil
      if foe_action["kind"] == "switch"
        # A body we have no live estimate against. Through 0.7.3 the cell was ONE
        # number -- the best this body has against that one -- so every move we could
        # click was credited the same damage against a switch-in and the foe-switch
        # column could not order our moves against each other; depth two showed that
        # was the bottleneck (190 of 227 move-versus-move disagreements sat in that
        # column). The cell now carries every damaging move it rolled (out_moves,
        # matrix version 2), so THIS move gets its own number against that body: a
        # 0 for the Earthquake their Flying-type shrugs off, the full Ice Beam for
        # the one it does not. A cell without the list (an older adapter, a move the
        # cell never rolled) still falls back to the one best number. A move that
        # deals nothing on the field deals nothing to a switch-in either.
        return 0.0 if !Model.truthy(own_action["damaging"])
        raw = priced ? Model.number(priced["pct"], 0.0) :
                       (cell.nil? ? 0.0 : Model.number(cell["out"], 0.0))
      else
        # The engine's own number for the pair on the field, which is better than the
        # cell: it carries this move, these stages, this weather -- and a stage this
        # search projected on top, by the category the cell priced this move in.
        raw = Model.number(own_action["expected_damage_pct"], 0.0)
      end
      # ...and the foe's own projected defence stages on the way in (0.7.9).
      raw * offence_multiplier(snapshot, projected, category) /
        stage_divisor(projected["foe_stages"], category, snapshot, projected, "out_cat", "def", "spd")
    end

    # The cell's own roll of one move, or nil when the cell has no such list.
    def self.cell_move(cell, move_id)
      return nil if cell.nil? || move_id.nil?
      moves = cell["out_moves"]
      return nil if !moves.is_a?(Hash)
      entry = moves[move_id.to_s.upcase]
      entry.is_a?(Hash) ? entry : nil
    end

    # The stages this search has put on the body ON TOP of the ones the engine's
    # numbers already carry: own_stages less the root's stage_base, per stat.
    def self.projected_stages(board)
      stages = board["own_stages"] || {}
      base = board["stage_base"] || {}
      out = {}
      stages.each do |stat, stage|
        delta = stage.to_i - Model.number(base[stat], 0.0).to_i
        out[stat] = delta if delta != 0
      end
      base.each do |stat, stage|
        next if stages.key?(stat)
        delta = -stage.to_i
        out[stat] = delta if delta != 0
      end
      out
    end

    # How a projected Attack or Special Attack stage scales what the body deals, by
    # the category the move is priced in -- or, for a move the cell never rolled, the
    # category of the body's best hit into the foe on the field (the cell's out_cat).
    def self.offence_multiplier(snapshot, board, category = nil)
      stages = projected_stages(board)
      return 1.0 if stages.empty?
      if category.nil?
        cell = PortableAI.matrix_cell(snapshot, board["own_slot"], board["foe_slot"])
        category = cell && cell["out_cat"]
      end
      stat = (category == "special") ? "spa" : "atk"
      stage = Model.number(stages[stat], 0.0).to_i
      stage == 0 ? 1.0 : Effects.stage_multiplier(stage)
    end

    # The mirror for what the body takes: by the category of the move the foe column
    # actually named (0.7.7), or of its best hit for a column that names none.
    def self.defence_divisor(snapshot, board, category = nil)
      stages = projected_stages(board)
      return 1.0 if stages.empty?
      if category.nil?
        cell = PortableAI.matrix_cell(snapshot, board["own_slot"], board["foe_slot"])
        category = cell && cell["in_cat"]
      end
      stat = (category == "special") ? "spd" : "def"
      stage = Model.number(stages[stat], 0.0).to_i
      stage == 0 ? 1.0 : Effects.stage_multiplier(stage)
    end

    # A stage table (the FOE's projected stages, 0.7.9) read as a ratio for one
    # category: `cat_key` names the cell field that says which category a column
    # without one is priced in, `physical`/`special` the stat each maps to.
    def self.stage_divisor(stages, category, snapshot, board, cat_key, physical, special)
      return 1.0 if stages.nil? || stages.empty?
      if category.nil?
        cell = PortableAI.matrix_cell(snapshot, board["own_slot"], board["foe_slot"])
        category = cell && cell[cat_key]
      end
      stage = Model.number(stages[(category == "special") ? special : physical], 0.0).to_i
      stage == 0 ? 1.0 : Effects.stage_multiplier(stage)
    end

    # A switching foe deals nothing this turn. A staying one hits whatever is in front
    # of it, and the number is read from the thickest view the snapshot has of that
    # pair: the actor view for the body already on the field, the switch candidate's
    # own estimate (Intimidate-aware, every foe move, a real damage roll) for a body
    # we bring in, and the cell only for a pair nothing else has priced.
    def self.foe_damage(snapshot, board, projected, own_action, foe_action)
      return 0.0 if foe_action["kind"] != "stay"
      # 0.7.7. THE FOE NAMED A MOVE, so this is that move's number and not the best
      # one it owns -- and it is read against whatever body is standing AFTER our
      # switch resolves, exactly as own_damage prices our move against their
      # switch-in. Falling back to the column's own number for a pair the matrix
      # never rolled.
      if !foe_action["move_id"].nil?
        return 0.0 if !Model.truthy(foe_action["damaging"]) && Model.number(foe_action["pct"], 0.0) <= 0.0
        priced = cell_in_move(
          PortableAI.matrix_cell(snapshot, projected["own_slot"], projected["foe_slot"]),
          foe_action["move_id"])
        raw = priced ? Model.number(priced["pct"], 0.0) : Model.number(foe_action["pct"], 0.0)
        category = priced ? priced["cat"] : foe_action["cat"]
        return raw / defence_divisor(snapshot, projected, category) *
               stage_divisor(projected["foe_stages"], category, snapshot, projected, "in_cat", "atk", "spa")
      end
      raw = nil
      raw = board["live_incoming"] if live_pair?(projected) && !board["live_incoming"].nil?
      if raw.nil? && own_action["type"] == "switch" && !own_action["incoming_damage_pct"].nil?
        raw = Model.number(own_action["incoming_damage_pct"], 0.0)
      end
      if raw.nil?
        cell = PortableAI.matrix_cell(snapshot, projected["own_slot"], projected["foe_slot"])
        raw = cell.nil? ? 0.0 : Model.number(cell["in"], 0.0)
      end
      raw / defence_divisor(snapshot, projected) *
        stage_divisor(projected["foe_stages"], nil, snapshot, projected, "in_cat", "atk", "spa")
    end

    # ------------------------------------------------------------------------------
    # The leaf: every live body on both sides, at the HP it stands on, plus the terms
    # the original's evaluate carries for the body on the field -- its stages, a
    # Substitute, a status landed this turn, hazards on the other side -- and, 0.7.9,
    # the same terms for THEIR body on the field. Each side's HP map overrides the
    # table for the bodies this search has touched; every other body is as the side
    # table has it.

    def self.leaf(snapshot, board)
      m = PortableAI.matrix(snapshot)
      own = side_value(m["own"], board["own_hps"])
      foe = side_value(m["foe"], board["foe_hps"])
      return -BATTLE_OVER if own["alive"] == 0
      return BATTLE_OVER if foe["alive"] == 0
      score = own["points"] - foe["points"]
      if board["own_hp"] > 0
        score += stage_points(board["own_stages"])
        score += SUBSTITUTE_VALUE if board["substitute"]
        score += board["own_status_points"]
      end
      if board["foe_hp"] > 0
        score -= board["foe_boost"]
        score -= stage_points(board["foe_stages"])
        score -= SUBSTITUTE_VALUE if board["foe_substitute"]
        score += board["foe_status_points"]
      end
      score += board["foe_hazard_points"]
      score -= Model.number(board["own_hazard_points"], 0.0)
      score
    end

    # The pair's cell as it reads under the stages this search projected -- a Dragon
    # Dance flips who moves first, which is what moves_first asks it for. The stages
    # the body already carried are inside the cell (matrix_bodies prices a body on
    # the field through its real battler), so only the projected ones apply. The
    # foe's projected speed stage (0.7.9) scales its side of the comparison.
    def self.boosted_cell(snapshot, m, board, cell)
      stages = projected_stages(board)
      foe_speed_stage = Model.number((board["foe_stages"] || {})["speed"], 0.0).to_i
      return cell if cell.nil? || (stages.empty? && foe_speed_stage == 0)
      own = PortableAI.matrix_entry(m["own"], board["own_slot"])
      foe = PortableAI.matrix_entry(m["foe"], board["foe_slot"])
      foe_speed = foe && foe["speed"]
      foe_speed = foe_speed.to_f * Effects.stage_multiplier(foe_speed_stage) if !foe_speed.nil? && foe_speed_stage != 0
      stages = Model.copy_hash(stages)
      # A foe speed stage with none of ours: hand the transform a zero own stage so
      # it still recomputes the order against the scaled foe speed.
      stages["speed"] = 0 if foe_speed_stage != 0 && !stages.key?("speed")
      if stages["speed"] == 0
        out = PortableAI.matrix_transform_cell(cell, stages, own && own["speed"], foe_speed,
                                               Model.truthy(snapshot["trick_room_active"]))
        own_speed = own && own["speed"]
        if !own_speed.nil? && !foe_speed.nil?
          trick = Model.truthy(snapshot["trick_room_active"])
          out["faster"] = trick ? own_speed.to_f < foe_speed.to_f : own_speed.to_f > foe_speed.to_f
        end
        return out
      end
      PortableAI.matrix_transform_cell(cell, stages, own && own["speed"], foe_speed,
                                       Model.truthy(snapshot["trick_room_active"]))
    end

    # The original's boost term: 30 a stage of offence or speed, 15 of defence,
    # through its diminishing multiplier (a second stage is worth as much as the
    # first, a third half as much, the sixth almost nothing more).
    def self.stage_points(stages)
      total = 0.0
      (stages || {}).each do |stat, stage|
        total += (STAGE_VALUE[stat.to_s] || 0.0) * stage_multiplier(stage.to_i)
      end
      total
    end

    def self.stage_multiplier(stage)
      sign = stage < 0 ? -1.0 : 1.0
      sign * (STAGE_MULTIPLIER[stage.abs] || STAGE_MULTIPLIER[6])
    end

    # Every live body on a side, at the HP the search's map says or, for a body the
    # search never touched, the table's.
    def self.side_value(table, hps)
      points = 0.0
      alive = 0
      hps = hps || {}
      (table || []).each do |entry|
        next if entry.nil? || entry["alive"] == false
        slot = entry["slot"]
        body_hp = hps.key?(slot) ? hps[slot] : Model.number(entry["hp_pct"], 0.0)
        next if body_hp <= 0
        points += body_hp + BODY_ALIVE
        alive += 1
      end
      { "points" => points, "alive" => alive }
    end

    # ------------------------------------------------------------------------------
    # THE TREE (0.7.6). A third planner path on the same board, off unless
    # `search_mcts` is set -- and with it off `plan` never reaches this section, so a
    # run without the key reproduces 0.7.5 decision for decision.
    #
    # WHY, given the maximin above sits at 46/60 against the rule engine's 48. Every
    # gain this month came from the board model and the opponent model, not from more
    # search: depth 2 was +1 over depth 1, and the whole 40 -> 46 was blending one
    # predicted reply into the root rows. That blend is a TABLE -- the foe's columns
    # weighted by what stock v16's triggers say it does -- and the AI's real opponent
    # is the player, who is not stock. The question this path asks is whether a tree
    # that lets the foe's line be shaped by ITS OWN payoff, over many iterations,
    # beats the one number. Ruby is slow and that is fine: the budget is an iteration
    # count, the gauntlet is a study harness and not a 100 ms move clock, so a
    # generous budget here answers the question a Rust port would only make faster.
    #
    # PROVENANCE: poke-engine's src/mcts.rs (GPL-3.0), the path Foul Play runs today,
    # read 2026-09-08. Four ideas, no code:
    #   * DECOUPLED simultaneous-move MCTS -- one node, two independent option lists,
    #     each side selecting its own by UCB1 without seeing the other's pick. The
    #     justification is Tak, Lanctot & Winands, "Monte Carlo Tree Search in
    #     Simultaneous Move Games" (2014); a sequential tree here would let one side
    #     answer a move it cannot see.
    #   * chance outcomes ENUMERATED into children with their probabilities, then one
    #     sampled by weight per iteration -- the same branching payoff already does,
    #     kept as nodes instead of averaged away.
    #   * NO PLAYOUT. The new board is scored by the static leaf relative to the root
    #     and squashed, `sigmoid(eval - root_eval)`. A random playout in a game this
    #     branchy is noise; the leaf is the same evaluate the maximin trusts.
    #   * the foe credited `1 - score`, and the pick being the MOST-VISITED root
    #     option (Foul Play's convention), not the highest average.
    # Not borrowed: the instruction generator (our `project` is the transition) and
    # reversible instructions (each node holds its own board copy; Model.copy_hash is
    # the undo).
    #
    # THE OPPONENT MODEL HERE IS THE TREE ITSELF. `foe_reply` / `column_weights` --
    # 0.7.5's table -- are deliberately NOT read on this path: the whole point is to
    # see what the foe's own payoff says when nothing tells it what to do. 0.7.8's
    # search_foe_prior is the follow-up, and it does NOT bring the opponent-model
    # producer in: what it steers by is `foe_prior`, damage the cell had already
    # priced, because the diagnostic found the tree's own foe model losing to it.
    MCTS_HORIZON = 8
    MCTS_DEFAULT_ITERATIONS = 1000
    # PUCT's exploration constant, AlphaZero's scale. Only reached under
    # search_foe_prior; the tree without the key is the 0.7.7 tree exactly.
    MCTS_PRIOR_C = 1.0
    # The original's scale: "~200 points is very close to 1.0", which in this leaf's
    # currency is two bodies' worth of swing.
    SIGMOID_SCALE = 0.0125

    def self.mcts_plan(snapshot, config, board, own_actions, foe_actions)
      started = Time.now
      iterations = iterations_of(config)
      prior_on = config["search_foe_prior"] ? true : false
      rng = Lcg.new(mcts_seed(snapshot, board, config))
      root = node_for(board, 0)
      # The root's own options are the EXPORTED actions -- legality, PP, the Choice
      # lock, every per-move number against this foe. Only the plies below have to
      # settle for own_options' matrix reconstruction.
      root["own"] = own_actions
      root["foe"] = foe_actions
      root_leaf = leaf(snapshot, board)
      count = 0
      while count < iterations
        mcts_iterate(snapshot, root, root_leaf, own_actions, rng, prior_on)
        count += 1
      end

      ranked = []
      own_actions.each_with_index do |action, i|
        stat = root["own_stats"][i]
        scored = Model.copy_hash(action)
        scored["score"] = average(stat)
        scored["search_visits"] = stat["visits"]
        # The row the readouts print, in foe_actions order: this action's average
        # score against each foe column. nil is "the tree never tried that pair",
        # which a 0.0 -- a real, and very bad, score -- would hide.
        row = []
        j = 0
        while j < foe_actions.length
          cell = root["cells"][[i, j]]
          row << (cell.nil? || cell["visits"] == 0 ? nil : cell["total"] / cell["visits"])
          j += 1
        end
        scored["search_row"] = row
        # As on the maximin path: the on-field cell the leaf and the ordering are read
        # from, because nothing else in a trace can tell a real certain death from a
        # misread cell.
        scored["search_cell"] = PortableAI.matrix_cell(snapshot, board["own_slot"], board["foe_slot"])
        scored["reasons"] = [["search_visits", stat["visits"]],
                             ["search_avg", scored["score"]],
                             ["search_iterations", iterations]]
        ranked << scored
      end
      ranked.sort! { |a, b| mcts_compare(a, b) }

      {
        "actions" => [ranked[0]],
        "memory_updates" => Effects.memory_updates([ranked[0]]),
        "diagnostics" => {
          "version" => VERSION,
          "planner" => "mcts",
          "iterations" => iterations,
          "horizon" => MCTS_HORIZON,
          # Wall clock, diagnostics only -- nothing branches on it, so a slow machine
          # and a fast one make the identical decisions. It is here because the budget
          # question is "how many iterations can a real run afford".
          "elapsed_ms" => ((Time.now - started) * 1000.0).to_i,
          "format" => "single",
          "joint_adjustment" => 0,
          "foe_options" => foe_actions.map { |f| foe_label(f) },
          # THE TREE'S OWN OPPONENT MODEL, readable against 0.7.5's foe_reply: how the
          # foe's visits spread over its options once its own payoff chose them.
          "foe_visits" => root["foe_stats"].map { |s| s["visits"] },
          "board" => board,
          "candidate_counts" => [ranked.length],
          "rankings" => [ranked]
        }
      }
    end

    def self.iterations_of(config)
      count = Model.number((config || {})["search_iterations"], MCTS_DEFAULT_ITERATIONS).to_i
      count < 1 ? 1 : count
    end

    # Foul Play's convention: the most-visited root option, the one UCB1 kept coming
    # back to. Its average breaks a tie, then the key -- so a tie never follows the
    # order the adapter happened to export actions in, as in `compare`.
    def self.mcts_compare(a, b)
      by_visits = b["search_visits"] <=> a["search_visits"]
      return by_visits if by_visits != 0
      by_score = b["score"] <=> a["score"]
      return by_score if by_score != 0
      key(a) <=> key(b)
    end

    def self.average(stat)
      stat["visits"] > 0 ? stat["total"] / stat["visits"] : 0.0
    end

    # A node is a board, the two option lists over it, one statistic per option per
    # side, and the chance children of each pair already expanded. `ply` is the
    # distance from the root, which is the only thing bounding the tree.
    def self.node_for(board, ply)
      { "board" => board, "ply" => ply, "visits" => 0,
        "own" => nil, "foe" => nil, "own_stats" => nil, "foe_stats" => nil,
        "children" => {}, "cells" => {} }
    end

    # Option lists and their statistics, built on first visit. Most nodes an iteration
    # creates are never descended into again, so enumerating options in `branches`
    # would price every leaf at a full option build.
    def self.populate(snapshot, node, root_actions, prior_on = false)
      return node if !node["own_stats"].nil?
      node["own"] = own_options(snapshot, node["board"], root_actions) if node["own"].nil?
      node["foe"] = foe_options(snapshot, node["board"]) if node["foe"].nil?
      node["own_stats"] = node["own"].map { { "total" => 0.0, "visits" => 0 } }
      node["foe_stats"] = node["foe"].map { { "total" => 0.0, "visits" => 0 } }
      node["foe_prior"] = prior_on ? foe_prior(node["foe"]) : nil
      node
    end

    # Scored where it stands and never expanded: the battle is over, a side has no
    # option, or the horizon is reached. THE HORIZON IS NOT OPTIONAL -- `project` does
    # not always change HP (a Protect, a stage-only turn, two switches), so a tree
    # without one can descend forever on a board that never resolves.
    def self.terminal_node?(snapshot, node)
      return true if node["ply"] >= MCTS_HORIZON
      return true if !battle_over(snapshot, node["board"]).nil?
      node["own"].empty? || node["foe"].empty?
    end

    # Decoupled UCB1, the original's numbers: `avg + sqrt(2 ln N / n)`, an unvisited
    # option ahead of every visited one. Called once per side per node, and neither
    # call sees the other's answer -- that independence is what makes this a
    # simultaneous-move tree.
    def self.ucb_pick(stats, parent_visits, prior = nil)
      # N is 0 on a node's first visit and ln 0 is not a number; every option is
      # unvisited then, so the exploration term is never reached.
      ln = parent_visits > 0 ? Math.log(parent_visits.to_f) : 0.0
      # 0.7.8, foe axis only. AlphaZero's PUCT term ADDED to UCB1 rather than
      # replacing it: `c * P(j) * sqrt(N) / (1 + n)` steers the split between the
      # foe's columns while UCB1's own term underneath keeps every column sampled --
      # so a column the prior prices at zero (Volt Switch off a Choice Specs set, a
      # status move) is still explored on merit, which a bare PUCT would starve.
      root = prior.nil? ? 0.0 : Math.sqrt(ln > 0.0 ? parent_visits.to_f : 0.0)
      best = -HUGE
      chosen = 0
      stats.each_with_index do |stat, i|
        visits = stat["visits"]
        value = visits == 0 ? HUGE :
                stat["total"] / visits + Math.sqrt(2.0 * ln / visits)
        value += MCTS_PRIOR_C * prior[i] * root / (1.0 + visits) if !prior.nil? && visits > 0
        if value > best
          best = value
          chosen = i
        end
      end
      chosen
    end

    # The chance outcomes of one joint pair, each with its probability -- the same
    # list `payoff` averages over (outcomes), kept as children so the tree can sample
    # them. The board of a child is NOT built here: an expansion enumerates every
    # outcome of the pair and an iteration walks into exactly one, so each child is
    # projected the first time it is sampled (child_node) and never otherwise.
    # The damage roll branches at the root and the root's children only, as the
    # original's should_branch_on_damage; deeper the average roll stands in.
    def self.branches(snapshot, node, i, j, root_actions)
      own_action = node["own"][i]
      foe_action = node["foe"][j]
      outcomes(snapshot, node["board"], own_action, foe_action, node["ply"] <= 1).map do |spec|
        { "prob" => spec[0], "order" => spec[1], "chance" => spec[2], "node" => nil }
      end
    end

    # The child's node, projected on first use and kept.
    def self.child_node(snapshot, parent, i, j, child)
      return child["node"] if !child["node"].nil?
      board = project(snapshot, parent["board"], parent["own"][i], parent["foe"][j],
                      child["order"], true, child["chance"])
      child["node"] = node_for(board, parent["ply"] + 1)
      child["node"]
    end

    def self.sample_branch(children, rng)
      roll = rng.next_float
      total = 0.0
      children.each do |child|
        total += child["prob"]
        return child if roll < total
      end
      children[children.length - 1]
    end

    # One iteration: descend by UCB1, sampling a chance branch at each step; expand the
    # first pair that has none; score the board reached; credit it back up the path.
    def self.mcts_iterate(snapshot, root, root_leaf, root_actions, rng, prior_on = false)
      path = []
      node = root
      while true
        populate(snapshot, node, root_actions, prior_on)
        break if terminal_node?(snapshot, node)
        i = ucb_pick(node["own_stats"], node["visits"])
        j = ucb_pick(node["foe_stats"], node["visits"], node["foe_prior"])
        path << [node, i, j]
        children = node["children"][[i, j]]
        if children.nil?
          children = branches(snapshot, node, i, j, root_actions)
          node["children"][[i, j]] = children
          # Expansion ends the descent: the new child is what this iteration scores.
          node = child_node(snapshot, node, i, j, sample_branch(children, rng))
          break
        end
        node = child_node(snapshot, node, i, j, sample_branch(children, rng))
      end
      backprop(path, evaluate_node(snapshot, node, root_leaf))
    end

    # No playout. The board is worth what the leaf says about it RELATIVE TO THE ROOT,
    # squashed to 0..1 -- the original's `sigmoid(eval - root_eval)`. Relative because
    # UCB1 needs a bounded reward and the leaf is unbounded HP points; a board that
    # ended the battle is the bound itself.
    def self.evaluate_node(snapshot, node, root_leaf)
      over = battle_over(snapshot, node["board"])
      return (over > 0 ? 1.0 : 0.0) if !over.nil?
      sigmoid(leaf(snapshot, node["board"]) - root_leaf)
    end

    def self.sigmoid(x)
      1.0 / (1.0 + Math.exp(-SIGMOID_SCALE * x))
    end

    # Up the path: our option is credited the score, theirs its complement -- one leaf,
    # read from both ends of a zero-sum game. The per-cell tally is ours and not the
    # original's: decoupled statistics cannot say what a ROW scored, and the row is
    # what a readout needs to see why the pick went where it did.
    def self.backprop(path, score)
      path.each do |entry|
        node = entry[0]
        i = entry[1]
        j = entry[2]
        node["visits"] += 1
        own = node["own_stats"][i]
        own["total"] += score
        own["visits"] += 1
        foe = node["foe_stats"][j]
        foe["total"] += 1.0 - score
        foe["visits"] += 1
        cell = node["cells"][[i, j]]
        if cell.nil?
          cell = { "total" => 0.0, "visits" => 0 }
          node["cells"][[i, j]] = cell
        end
        cell["total"] += score
        cell["visits"] += 1
      end
    end

    # A stable fingerprint of the position: the turn, the pair on the field, and every
    # body's HP on both sides, plus `search_seed`. Mixed rather than summed, so two
    # boards that differ only in which body holds a number do not collide.
    def self.mcts_seed(snapshot, board, config)
      seed = Model.number((config || {})["search_seed"], 0.0).to_i
      parts = [Model.number(snapshot["turn"], 0.0).to_i,
               board["own_slot"].to_i, board["foe_slot"].to_i]
      m = PortableAI.matrix(snapshot) || {}
      ["own", "foe"].each do |side|
        (m[side] || []).each do |entry|
          next if entry.nil?
          parts << entry["slot"].to_i
          parts << Model.number(entry["hp_pct"], 0.0).round.to_i
        end
      end
      parts.each { |part| seed = ((seed * 33) + part) & 0x3FFFFFFF }
      seed
    end

    # The chance branches are SAMPLED, so the tree needs a stream -- and it must not be
    # the battle's. `pbAIRandom` decides the engine's own rolls: drawing from it here
    # would change the battle a shadow run is meant to observe without disturbing, and
    # would make a traced decision unrepeatable. This is the adapter's NeutralRNG
    # recurrence, seeded per decision from the position alone, so a paired run and its
    # shadow twin agree and a readout can replay any decision from its snapshot.
    class Lcg
      def initialize(seed)
        @state = (seed.to_i & 0x3FFFFFFF)
      end

      def next_float
        @state = ((@state * 1103515245) + 12345) & 0x3FFFFFFF
        @state / 1073741824.0
      end
    end
  end
end
