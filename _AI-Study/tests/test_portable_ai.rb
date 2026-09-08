require "test/unit"

root = File.expand_path("..", File.dirname(__FILE__))
require File.join(root, "portable_ai", "model")
require File.join(root, "portable_ai", "effects")
require File.join(root, "portable_ai", "matrix")
require File.join(root, "portable_ai", "core")
require File.join(root, "portable_ai", "search")

class PortableAITest < Test::Unit::TestCase
  def target(index, hp)
    { "index" => index, "hp_pct" => hp, "status" => 0 }
  end

  def move(slot, id, target_index, base, damage, extra)
    out = {
      "type" => "move", "slot" => slot, "move_id" => id,
      "target" => target_index, "base_score" => base,
      "expected_damage_pct" => damage, "effectiveness" => 1,
      "damaging" => damage > 0
    }
    (extra || {}).each { |k, v| out[k] = v }
    out
  end

  def actor(index, hp, actions, extra)
    out = { "index" => index, "hp_pct" => hp, "actions" => actions }
    (extra || {}).each { |k, v| out[k] = v }
    out
  end

  def snapshot(actors, targets, memory)
    {
      "format" => actors.length > 1 ? "double" : "single",
      "actors" => actors, "targets" => targets, "memory" => memory || {}
    }
  end

  def pick(snap, config)
    PortableAI.plan(snap, config || {}, Random.new(7))["actions"]
  end

  def reasons_of(action)
    action["reasons"].map { |pair| pair[0] }
  end

  def reason_value(action, name)
    hit = (action["reasons"] || []).find { |r| r[0] == name }
    hit && hit[1]
  end

  def switch_action(slot)
    { "type" => "switch", "slot" => slot, "base_score" => 100, "matchup_score" => 0 }
  end

  def test_lethal_move_beats_setup
    foe = target(0, 12)
    actions = [
      move(0, "EARTHQUAKE", 0, 100, 30, {}),
      move(1, "SWORDSDANCE", 0, 120, 0, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("EARTHQUAKE", result[0]["move_id"])
  end

  def test_low_hp_heal_beats_weak_attack
    foe = target(0, 100)
    actions = [
      move(0, "ROOST", nil, 87, 0, {}),
      move(1, "BRAVEBIRD", 0, 110, 12, {})
    ]
    result = pick(snapshot([actor(1, 20, actions, {})], [foe], {}), {})
    assert_equal("ROOST", result[0]["move_id"])
  end

  def test_heal_is_rejected_near_full
    foe = target(0, 80)
    actions = [
      move(0, "SOFTBOILED", nil, 150, 0, {}),
      move(1, "DAZZLINGGLEAM", 0, 100, 20, {})
    ]
    result = pick(snapshot([actor(1, 95, actions, {})], [foe], {}), {})
    assert_equal("DAZZLINGGLEAM", result[0]["move_id"])
  end

  def test_immune_move_is_never_selected
    foe = target(0, 100)
    actions = [
      move(0, "EARTHQUAKE", 0, 500, 0, { "immune" => true }),
      move(1, "DRAGONCLAW", 0, 50, 10, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("DRAGONCLAW", result[0]["move_id"])
  end

  def test_forced_switch_beats_move
    foe = target(0, 100)
    actions = [
      move(0, "BODYSLAM", 0, 120, 0, { "immune" => true }),
      { "type" => "switch", "slot" => 1, "base_score" => 0,
        "matchup_score" => 30, "forced" => true }
    ]
    result = pick(snapshot([actor(1, 100, actions, { "no_effective_move" => true })], [foe], {}), {})
    assert_equal("switch", result[0]["type"])
    assert_equal(1, result[0]["slot"])
  end

  def test_unknown_move_uses_adapter_score
    foe = target(0, 100)
    actions = [
      move(0, "CUSTOMMOVE", 0, 130, 15, {}),
      move(1, "POUND", 0, 80, 15, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("CUSTOMMOVE", result[0]["move_id"])
  end

  def test_doubles_avoids_wasted_double_target
    left_foe = target(0, 20)
    right_foe = target(2, 30)
    left_actions = [
      move(0, "THUNDERBOLT", 0, 140, 30, {}),
      move(0, "THUNDERBOLT", 2, 130, 30, {})
    ]
    right_actions = [
      move(0, "FLAMETHROWER", 0, 140, 35, {}),
      move(0, "FLAMETHROWER", 2, 130, 35, {})
    ]
    actors = [actor(1, 100, left_actions, {}), actor(3, 100, right_actions, {})]
    result = pick(snapshot(actors, [left_foe, right_foe], {}), {})
    assert_not_equal(result[0]["target"], result[1]["target"])
  end

  def test_doubles_never_switches_both_actors_to_same_slot
    foes = [target(0, 100), target(2, 100)]
    switch = { "type" => "switch", "slot" => 2, "base_score" => 500,
               "matchup_score" => 100 }
    stay_left = move(0, "POUND", 0, 10, 5, {})
    stay_right = move(0, "PECK", 2, 10, 5, {})
    # Both actors need a real escape reason: since 0.3.0 an unmotivated switch is
    # gated out entirely, and this test is about slot coordination, not the gate.
    escaping = { "no_effective_move" => true }
    actors = [
      actor(1, 20, [switch, stay_left], escaping),
      actor(3, 20, [switch, stay_right], escaping)
    ]
    result = pick(snapshot(actors, foes, {}), {})
    assert_equal(1, result.count { |a| a["type"] == "switch" })
  end

  def test_switch_without_escape_reason_is_gated_out
    foe = [target(0, 100)]
    # A switch that would comfortably outscore the move under pre-0.3.0 scoring.
    switch = { "type" => "switch", "slot" => 1, "base_score" => 500,
               "matchup_score" => 400 }
    stay = move(0, "POUND", 0, 10, 5, {})
    actors = [actor(1, 100, [switch, stay], {})]
    result = pick(snapshot(actors, foe, {}), {})
    assert_equal("move", result[0]["type"])
  end

  def test_switch_with_escape_reason_is_allowed
    foe = [target(0, 100)]
    switch = { "type" => "switch", "slot" => 1, "base_score" => 500,
               "matchup_score" => 400 }
    stay = move(0, "POUND", 0, 10, 5, {})
    actors = [actor(1, 100, [switch, stay], { "no_effective_move" => true })]
    result = pick(snapshot(actors, foe, {}), {})
    assert_equal("switch", result[0]["type"])
  end

  def test_switch_gate_can_be_disabled_for_ab_runs
    foe = [target(0, 100)]
    switch = { "type" => "switch", "slot" => 1, "base_score" => 500,
               "matchup_score" => 400 }
    stay = move(0, "POUND", 0, 10, 5, {})
    actors = [actor(1, 100, [switch, stay], {})]
    result = pick(snapshot(actors, foe, {}), { "switch_gate" => false })
    assert_equal("switch", result[0]["type"])
  end

  def test_lethal_threat_opens_gate_only_while_healthy
    foe = [target(0, 100)]
    switch = { "type" => "switch", "slot" => 1, "base_score" => 500,
               "matchup_score" => 400 }
    stay = move(0, "POUND", 0, 10, 5, {})
    # Healthy battler facing a hard counter: a real matchup problem, pivot allowed.
    healthy = [actor(1, 100, [switch, stay], { "incoming_damage_pct" => 120 })]
    assert_equal("switch", pick(snapshot(healthy, foe, {}), {})[0]["type"])
    # Nearly dead: everything is lethal, so this must not license fleeing on its own.
    weak = [actor(1, 20, [switch, stay], { "incoming_damage_pct" => 120 })]
    assert_equal("move", pick(snapshot(weak, foe, {}), {})[0]["type"])
  end

  def test_boosted_foe_does_not_license_a_healthy_pivot
    switch = { "type" => "switch", "slot" => 1, "base_score" => 500,
               "matchup_score" => 400 }
    stay = move(0, "POUND", 0, 10, 5, {})
    healthy = [actor(1, 100, [switch, stay], { "incoming_damage_pct" => 120 })]
    # Same healthy battler, same lethal incoming damage — but the threat is the foe's
    # +2, not the matchup, so hold ground rather than hand it a free boosted hit.
    boosted = [target(0, 100)].each { |t| t["positive_stages"] = 2 }
    assert_equal("move", pick(snapshot(healthy, boosted, {}), {})[0]["type"])
  end

  def test_boosted_foe_still_allows_an_independent_escape_reason
    switch = { "type" => "switch", "slot" => 1, "base_score" => 500,
               "matchup_score" => 400 }
    stay = move(0, "POUND", 0, 10, 5, {})
    boosted = [target(0, 100)].each { |t| t["positive_stages"] = 4 }
    # Nothing here can damage the foe at all; its boosts do not veto that fact.
    stuck = [actor(1, 100, [switch, stay], { "no_effective_move" => true })]
    assert_equal("switch", pick(snapshot(stuck, boosted, {}), {})[0]["type"])
  end

  def test_switch_prefers_the_mon_that_resists_the_foe
    foe = [target(0, 100)]
    # Two escape routes with identical offence; one walks into super-effective STAB
    # (64), the other resists it (16). Nothing else separates them.
    into_it = { "type" => "switch", "slot" => 1, "base_score" => 100,
                "matchup_score" => 32, "incoming_risk" => 64 }
    resists = { "type" => "switch", "slot" => 2, "base_score" => 100,
                "matchup_score" => 32, "incoming_risk" => 16 }
    stay = move(0, "POUND", 0, 10, 5, {})
    actors = [actor(1, 100, [into_it, resists, stay], { "no_effective_move" => true })]
    result = pick(snapshot(actors, foe, {}), {})
    assert_equal("switch", result[0]["type"])
    assert_equal(2, result[0]["slot"])
  end

  # The two switch candidates below disagree: slot 1 hits harder (64) but eats a
  # super-effective STAB coming in (64), slot 2 is neutral offensively (32) and
  # resists (16). Which one wins is decided entirely by switch_risk_weight, so the
  # pair pins both ends of the knob — including 0.0, which is Portable 0.3.1 and is
  # the A/B arm the roster runs use.
  def risk_disagreement_actors
    hard_hitter = { "type" => "switch", "slot" => 1, "base_score" => 100,
                    "matchup_score" => 64, "incoming_risk" => 64 }
    survivor = { "type" => "switch", "slot" => 2, "base_score" => 100,
                 "matchup_score" => 32, "incoming_risk" => 16 }
    stay = move(0, "POUND", 0, 10, 5, {})
    [actor(1, 100, [hard_hitter, survivor, stay], { "no_effective_move" => true })]
  end

  def test_switch_risk_weight_default_prefers_surviving_the_entry_turn
    actors = risk_disagreement_actors
    assert_equal(2, pick(snapshot(actors, [target(0, 100)], {}), {})[0]["slot"])
  end

  def test_switch_risk_weight_zero_restores_offence_only_scoring
    actors = risk_disagreement_actors
    config = { "switch_risk_weight" => 0.0 }
    assert_equal(1, pick(snapshot(actors, [target(0, 100)], {}), config)[0]["slot"])
  end

  def test_switch_risk_weight_scales_the_defensive_term
    actors = risk_disagreement_actors
    # Half weight halves the 32-point risk gap to 16, which no longer overturns the
    # 32-point offensive gap, so the knob is a dial rather than an on/off switch.
    config = { "switch_risk_weight" => 0.5 }
    assert_equal(1, pick(snapshot(actors, [target(0, 100)], {}), config)[0]["slot"])
  end

  def test_switch_risk_is_ignored_when_the_adapter_omits_it
    foe = [target(0, 100)]
    # Older adapters send no incoming_risk; those switches must score as they did.
    better = { "type" => "switch", "slot" => 1, "base_score" => 100,
               "matchup_score" => 64 }
    worse = { "type" => "switch", "slot" => 2, "base_score" => 100,
              "matchup_score" => 32 }
    stay = move(0, "POUND", 0, 10, 5, {})
    actors = [actor(1, 100, [better, worse, stay], { "no_effective_move" => true })]
    assert_equal(1, pick(snapshot(actors, foe, {}), {})[0]["slot"])
  end

  def test_targeted_friendly_fire_is_rejected
    foes = [target(0, 100), target(2, 100)]
    hit_ally = move(
      0, "BRAVEBIRD", 3, 500, 80,
      {
        "friendly_fire_pct" => 80, "partner_hp_pct" => 100,
        "friendly_target" => true
      }
    )
    hit_foe = move(0, "BRAVEBIRD", 0, 100, 20, {})
    partner_move = move(0, "BODYSLAM", 2, 100, 20, {})
    actors = [
      actor(1, 100, [hit_ally, hit_foe], {}),
      actor(3, 100, [partner_move], {})
    ]
    result = pick(snapshot(actors, foes, {}), {})
    assert_equal(0, result[0]["target"])
  end

  def test_repeated_setup_is_penalized
    foe = target(0, 100)
    actions = [
      move(0, "SWORDSDANCE", 0, 160, 0, {}),
      move(1, "BODYSLAM", 0, 100, 20, {})
    ]
    memory = { "1" => { "setup" => 2 } }
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], memory), {})
    assert_equal("BODYSLAM", result[0]["move_id"])
  end

  def test_invalid_snapshot_is_rejected
    assert_raise(ArgumentError) { PortableAI.plan({}, {}, Random.new(1)) }
  end

  # --- 0.4.0 heal gate -------------------------------------------------------------

  def test_slower_heal_into_a_lethal_hit_is_refused
    foe = target(0, 100)
    actions = [
      move(0, "RECOVER", nil, 100, 0, {}),
      move(1, "BODYSLAM", 0, 100, 20, {})
    ]
    healer = actor(1, 12, actions, { "incoming_damage_pct" => 60, "faster" => false })
    result = pick(snapshot([healer], [foe], {}), {})
    assert_equal("BODYSLAM", result[0]["move_id"])
  end

  def test_strict_threat_keeps_the_heal_when_the_hit_is_not_certain
    foe = target(0, 100)
    actions = [
      move(0, "RECOVER", nil, 100, 0, {}),
      move(1, "BODYSLAM", 0, 100, 20, {})
    ]
    # The foe's best move is 70% accurate (or it is asleep): the adapter reports a
    # loose 60% threat but a certain 0%. Slower healer at 12%.
    healer = actor(1, 12, actions, { "incoming_damage_pct" => 60,
                                     "certain_incoming_damage_pct" => 0,
                                     "faster" => false })
    strict = pick(snapshot([healer], [foe], {}), {})
    assert_equal("RECOVER", strict[0]["move_id"])
    assert_equal(true, reasons_of(strict[0]).include?("heal_saves_battler"))
    loose = pick(snapshot([healer], [foe], {}), { "strict_threat" => false })
    assert_equal("BODYSLAM", loose[0]["move_id"])
  end

  def test_heal_that_cannot_outrun_the_incoming_hit_is_refused
    foe = target(0, 100)
    actions = [
      move(0, "SOFTBOILED", nil, 100, 0, {}),
      move(1, "SEISMICTOSS", 0, 100, 18, {})
    ]
    healer = actor(1, 10, actions, { "incoming_damage_pct" => 95, "faster" => true })
    result = pick(snapshot([healer], [foe], {}), {})
    assert_equal("SEISMICTOSS", result[0]["move_id"])
  end

  def test_rest_outruns_a_hit_that_a_half_heal_would_not
    foe = target(0, 100)
    partial = actor(1, 10, [move(0, "SOFTBOILED", nil, 100, 0, {})],
                    { "incoming_damage_pct" => 80, "faster" => true })
    full = actor(1, 10, [move(0, "REST", nil, 100, 0, {})],
                 { "incoming_damage_pct" => 80, "faster" => true })
    assert_equal(true, reasons_of(pick(snapshot([partial], [foe], {}), {})[0])
                       .include?("heal_does_not_save"))
    assert_equal(true, reasons_of(pick(snapshot([full], [foe], {}), {})[0])
                       .include?("heal_saves_battler"))
  end

  def test_weather_heal_is_worth_less_in_sand
    foe = target(0, 100)
    actions = [move(0, "MOONLIGHT", nil, 100, 0, {})]
    healer = actor(1, 20, actions, { "incoming_damage_pct" => 60, "faster" => true })
    clear = snapshot([healer], [foe], {})
    sand = snapshot([healer], [foe], {})
    sand["weather"] = "sand"
    assert_equal(true, reasons_of(pick(clear, {})[0]).include?("heal_saves_battler"))
    assert_equal(true, reasons_of(pick(sand, {})[0]).include?("heal_does_not_save"))
  end

  # A hit that the estimate kills with but a low roll does not is exactly the position
  # the -400 must not fire in: healing survives half the rolls and wins the game there.
  def test_marginally_lethal_hit_still_leaves_the_heal_worth_taking
    foe = target(0, 100)
    actions = [
      move(0, "SOFTBOILED", nil, 100, 0, {}),
      move(1, "DAZZLINGGLEAM", 0, 100, 20, {})
    ]
    healer = actor(1, 12, actions, { "incoming_damage_pct" => 13, "faster" => false })
    result = pick(snapshot([healer], [foe], {}), {})
    assert_equal("SOFTBOILED", result[0]["move_id"])
    assert_equal(true, reasons_of(result[0]).include?("heal_saves_battler"))
  end

  def test_heal_gate_off_restores_the_flat_lethal_threat_penalty
    foe = target(0, 100)
    actions = [
      move(0, "RECOVER", nil, 100, 0, {}),
      move(1, "BODYSLAM", 0, 100, 20, {})
    ]
    healer = actor(1, 12, actions, { "incoming_damage_pct" => 60, "faster" => false })
    result = pick(snapshot([healer], [foe], {}), { "heal_gate" => false })
    assert_equal("RECOVER", result[0]["move_id"])
    assert_equal(true, reasons_of(result[0]).include?("heal_under_lethal_threat"))
  end

  # --- 0.4.0 accuracy --------------------------------------------------------------

  def test_accurate_knockout_beats_the_inaccurate_one
    foe = target(0, 40)
    actions = [
      move(0, "STONEEDGE", 0, 100, 60, { "accuracy" => 80 }),
      move(1, "ROCKSLIDE", 0, 100, 45, { "accuracy" => 90 })
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("ROCKSLIDE", result[0]["move_id"])
  end

  def test_accuracy_weight_zero_restores_slot_order_among_knockouts
    foe = target(0, 40)
    actions = [
      move(0, "STONEEDGE", 0, 100, 60, { "accuracy" => 80 }),
      move(1, "ROCKSLIDE", 0, 100, 45, { "accuracy" => 90 })
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}),
                  { "accuracy_weight" => 0 })
    assert_equal("STONEEDGE", result[0]["move_id"])
  end

  def test_missing_accuracy_field_is_not_a_discount
    foe = target(0, 40)
    actions = [
      move(0, "EARTHQUAKE", 0, 100, 60, {}),
      move(1, "ROCKSLIDE", 0, 100, 45, { "accuracy" => 90 })
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("EARTHQUAKE", result[0]["move_id"])
  end

  # --- 0.4.0 priority vs speed -----------------------------------------------------

  def test_priority_secures_a_knockout_the_actor_could_not_land
    foe = target(0, 25)
    actions = [
      move(0, "ICICLECRASH", 0, 100, 70, {}),
      move(1, "ICESHARD", 0, 100, 30, { "priority" => 1 })
    ]
    doomed = actor(1, 30, actions, { "incoming_damage_pct" => 60, "faster" => false })
    result = pick(snapshot([doomed], [foe], {}), {})
    assert_equal("ICESHARD", result[0]["move_id"])
  end

  def test_a_knockout_that_resolves_after_the_actor_dies_is_not_a_knockout
    foe = target(0, 25)
    actions = [move(0, "ICICLECRASH", 0, 100, 70, {})]
    doomed = actor(1, 30, actions, { "incoming_damage_pct" => 60, "faster" => false })
    assert_equal(true, reasons_of(pick(snapshot([doomed], [foe], {}), {})[0])
                       .include?("ko_never_lands"))
    safe = actor(1, 90, actions, { "incoming_damage_pct" => 60, "faster" => false })
    assert_equal(true, reasons_of(pick(snapshot([safe], [foe], {}), {})[0])
                       .include?("lethal"))
  end

  def test_priority_gate_is_skipped_when_speed_order_is_unknown
    foe = target(0, 25)
    actions = [move(0, "ICICLECRASH", 0, 100, 70, {})]
    unknown = actor(1, 30, actions, { "incoming_damage_pct" => 60 })
    assert_equal(true, reasons_of(pick(snapshot([unknown], [foe], {}), {})[0])
                       .include?("lethal"))
  end

  def test_priority_gate_off_restores_slot_order_among_knockouts
    foe = target(0, 25)
    actions = [
      move(0, "ICICLECRASH", 0, 100, 70, {}),
      move(1, "ICESHARD", 0, 100, 30, { "priority" => 1 })
    ]
    doomed = actor(1, 30, actions, { "incoming_damage_pct" => 60, "faster" => false })
    result = pick(snapshot([doomed], [foe], {}), { "priority_gate" => false })
    assert_equal("ICICLECRASH", result[0]["move_id"])
  end

  # --- 0.4.0 self-cost -------------------------------------------------------------

  def test_self_stat_drop_loses_to_an_equal_knockout
    foe = target(0, 30)
    actions = [
      move(0, "DRACOMETEOR", 0, 100, 80, {}),
      move(1, "DARKPULSE", 0, 100, 50, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("DARKPULSE", result[0]["move_id"])
  end

  def test_self_stat_drop_is_still_taken_when_it_is_the_only_knockout
    foe = target(0, 60)
    actions = [
      move(0, "DRACOMETEOR", 0, 100, 80, {}),
      move(1, "DARKPULSE", 0, 100, 50, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("DRACOMETEOR", result[0]["move_id"])
  end

  def test_explosion_is_refused_at_full_hp_when_another_move_kills
    foe = target(0, 30)
    actions = [
      move(0, "EXPLOSION", 0, 100, 90, { "own_reserves" => 2 }),
      move(1, "THUNDERBOLT", 0, 100, 40, { "own_reserves" => 2 })
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("THUNDERBOLT", result[0]["move_id"])
  end

  def test_explosion_is_allowed_when_the_actor_is_about_to_die_anyway
    foe = target(0, 30)
    actions = [
      move(0, "EXPLOSION", 0, 100, 90, { "own_reserves" => 2 }),
      move(1, "THUNDERBOLT", 0, 100, 40, { "own_reserves" => 2 })
    ]
    result = pick(snapshot([actor(1, 20, actions, {})], [foe], {}), {})
    assert_equal("EXPLOSION", result[0]["move_id"])
  end

  # Reborn's deathcode never trades the last Pokemon: fainting on purpose there ends
  # the battle, whatever it takes with it.
  def test_explosion_is_refused_with_nothing_left_to_send_out
    foe = target(0, 30)
    actions = [
      move(0, "EXPLOSION", 0, 100, 90, { "own_reserves" => 0 }),
      move(1, "THUNDERBOLT", 0, 100, 40, { "own_reserves" => 0 })
    ]
    result = pick(snapshot([actor(1, 20, actions, {})], [foe], {}), {})
    assert_equal("THUNDERBOLT", result[0]["move_id"])
  end

  def test_self_cost_off_restores_slot_order
    foe = target(0, 30)
    actions = [
      move(0, "EXPLOSION", 0, 100, 90, { "own_reserves" => 2 }),
      move(1, "THUNDERBOLT", 0, 100, 40, { "own_reserves" => 2 })
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}),
                  { "self_cost" => false })
    assert_equal("EXPLOSION", result[0]["move_id"])
  end

  # --- 0.5.0 tables -----------------------------------------------------------------
  #
  # One pair per row: the rule fires where it should, and is correctly silent where it
  # should not. The silent half is the half that matters -- every 0.5.0 row is a
  # multiplier on a move the AI was already going to consider, so a row that never
  # switches itself off is a row that just rescales the whole move list.
  #
  # The three rows Reborn does NOT have are tested here and NOT in the probe corpus:
  # a corpus card is a guardrail only where stock Reborn passes it (see
  # PORTABLE-AI-REBORN.md, "0.5.0 Phase A").

  def sec(kind, chance, extra)
    out = { "effect_kind" => kind, "effect_chance" => chance }
    (extra || {}).each { |k, v| out[k] = v }
    out
  end

  # --- secondary status ---
  def test_burn_secondary_is_worth_more_into_a_physical_attacker
    foe = target(0, 100).merge("ability" => "SNORLAX", "physical_attacker" => true)
    actions = [
      move(0, "SCALD", 0, 100, 40, sec("burn", 100, {})),
      move(1, "SURF", 0, 100, 50, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("SCALD", result[0]["move_id"])
  end

  def test_burn_secondary_is_not_worth_10_bp_into_a_special_attacker
    foe = target(0, 100).merge("special_attacker" => true)
    actions = [
      move(0, "SCALD", 0, 100, 40, sec("burn", 100, {})),
      move(1, "SURF", 0, 100, 50, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("SURF", result[0]["move_id"])
  end

  # A 10% chance is worth a tenth of the effect. Reborn does not do this (its
  # burncode never reads addlEffect); the departure is deliberate and measured.
  def test_secondary_chance_scales_the_bonus
    foe = target(0, 100).merge("physical_attacker" => true)
    certain = [move(0, "SCALD", 0, 100, 40, sec("burn", 100, {})),
               move(1, "SURF", 0, 100, 50, {})]
    rare = [move(0, "SCALD", 0, 100, 40, sec("burn", 10, {})),
            move(1, "SURF", 0, 100, 50, {})]
    assert_equal("SCALD", pick(snapshot([actor(1, 100, certain, {})], [foe], {}), {})[0]["move_id"])
    assert_equal("SURF", pick(snapshot([actor(1, 100, rare, {})], [foe], {}), {})[0]["move_id"])
  end

  # effect_chance 0 is the engine saying Sheer Force / Shield Dust / Covert Cloak has
  # removed the secondary entirely.
  def test_negated_secondary_scores_nothing
    foe = target(0, 100).merge("physical_attacker" => true)
    actions = [
      move(0, "SCALD", 0, 100, 40, sec("burn", 0, {})),
      move(1, "SURF", 0, 100, 50, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("SURF", result[0]["move_id"])
  end

  def test_burn_is_worthless_into_a_guts_target
    foe = target(0, 100).merge("ability" => "GUTS", "physical_attacker" => true)
    actions = [
      move(0, "SCALD", 0, 100, 40, sec("burn", 100, {})),
      move(1, "SURF", 0, 100, 41, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("SURF", result[0]["move_id"])
  end

  # --- flinch ---
  def test_flinch_counts_only_when_faster
    foe = target(0, 100)
    actions = [
      move(0, "ROCKSLIDE", 0, 100, 40, sec("flinch", 30, {})),
      move(1, "ROCKTOMB", 0, 100, 42, {})
    ]
    fast = pick(snapshot([actor(1, 100, actions, { "faster" => true })], [foe], {}), {})
    slow = pick(snapshot([actor(1, 100, actions, { "faster" => false })], [foe], {}), {})
    assert_equal("ROCKSLIDE", fast[0]["move_id"])
    assert_equal("ROCKTOMB", slow[0]["move_id"])
  end

  def test_flinch_is_ignored_behind_inner_focus
    foe = target(0, 100).merge("ability" => "INNERFOCUS")
    actions = [
      move(0, "ROCKSLIDE", 0, 100, 40, sec("flinch", 30, {})),
      move(1, "ROCKTOMB", 0, 100, 42, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, { "faster" => true })], [foe], {}), {})
    assert_equal("ROCKTOMB", result[0]["move_id"])
  end

  # --- target stat drops ---
  def test_speed_drop_is_valued_only_when_slower
    foe = target(0, 100)
    actions = [
      move(0, "ICYWIND", 0, 100, 30, sec("drop", 100, { "effect_stat" => "speed" })),
      move(1, "ICEBEAM", 0, 100, 36, {})
    ]
    slow = pick(snapshot([actor(1, 100, actions, { "faster" => false })], [foe], {}), {})
    fast = pick(snapshot([actor(1, 100, actions, { "faster" => true })], [foe], {}), {})
    assert_equal("ICYWIND", slow[0]["move_id"])
    assert_equal("ICEBEAM", fast[0]["move_id"])
  end

  def test_stat_drop_is_dead_against_clear_body
    foe = target(0, 100).merge("ability" => "CLEARBODY")
    actions = [
      move(0, "ICYWIND", 0, 100, 30, sec("drop", 100, { "effect_stat" => "speed" })),
      move(1, "ICEBEAM", 0, 100, 33, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, { "faster" => false })], [foe], {}), {})
    assert_equal("ICEBEAM", result[0]["move_id"])
  end

  # --- recoil, drain, item removal, multi-hit ---
  def test_recoil_loses_to_a_clean_knockout
    foe = target(0, 20)
    actions = [
      move(0, "BRAVEBIRD", 0, 100, 90, { "recoil_fraction" => 0.3333 }),
      move(1, "DRILLPECK", 0, 100, 70, {})
    ]
    result = pick(snapshot([actor(1, 8, actions, {})], [foe], {}), {})
    assert_equal("DRILLPECK", result[0]["move_id"])
  end

  def test_rock_head_pays_nothing_for_recoil
    foe = target(0, 20)
    actions = [
      move(0, "BRAVEBIRD", 0, 100, 90, { "recoil_fraction" => 0.3333 }),
      move(1, "DRILLPECK", 0, 100, 70, {})
    ]
    result = pick(snapshot([actor(1, 8, actions, { "ability" => "ROCKHEAD" })], [foe], {}), {})
    assert_equal("BRAVEBIRD", result[0]["move_id"])
  end

  def test_drain_is_valued_when_damaged_and_not_at_full_hp
    foe = target(0, 100)
    actions = [
      move(0, "GIGADRAIN", 0, 100, 60, { "drain_fraction" => 0.5 }),
      move(1, "ENERGYBALL", 0, 100, 64, {})
    ]
    hurt = pick(snapshot([actor(1, 40, actions, { "faster" => true })], [foe], {}), {})
    full = pick(snapshot([actor(1, 100, actions, { "faster" => true })], [foe], {}), {})
    assert_equal("GIGADRAIN", hurt[0]["move_id"])
    assert_equal("ENERGYBALL", full[0]["move_id"])
  end

  def test_knock_off_is_worth_the_item_and_nothing_without_one
    held = target(0, 100).merge("item" => "LEFTOVERS")
    bare = target(0, 100)
    actions = [
      move(0, "KNOCKOFF", 0, 100, 40, {}),
      move(1, "NIGHTSLASH", 0, 100, 43, {})
    ]
    assert_equal("KNOCKOFF", pick(snapshot([actor(1, 100, actions, {})], [held], {}), {})[0]["move_id"])
    assert_equal("NIGHTSLASH", pick(snapshot([actor(1, 100, actions, {})], [bare], {}), {})[0]["move_id"])
  end

  # Focus Sash is deliberately NOT on the whitelist: Reborn's knockcode does not carry
  # it, and the engine's own damage boost against an item holder is what actually makes
  # Knock Off the better move there. Copying the list means copying the gap.
  def test_focus_sash_is_not_on_the_knock_off_whitelist
    foe = target(0, 100).merge("item" => "FOCUSSASH")
    actions = [
      move(0, "KNOCKOFF", 0, 100, 40, {}),
      move(1, "NIGHTSLASH", 0, 100, 43, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("NIGHTSLASH", result[0]["move_id"])
  end

  def test_multi_hit_answers_a_focus_sash_only_at_full_hp
    full = target(0, 100).merge("item" => "FOCUSSASH", "full_hp" => true)
    chipped = target(0, 90).merge("item" => "FOCUSSASH", "full_hp" => false)
    actions = [
      move(0, "ICICLESPEAR", 0, 100, 60, { "multi_hit" => true }),
      move(1, "ICICLECRASH", 0, 100, 68, {})
    ]
    assert_equal("ICICLESPEAR",
                 pick(snapshot([actor(1, 100, actions, {})], [full], {}), {})[0]["move_id"])
    assert_equal("ICICLECRASH",
                 pick(snapshot([actor(1, 100, actions, {})], [chipped], {}), {})[0]["move_id"])
  end

  # --- Sturdy and Focus Sash ---
  #
  # 0.5.0 prices the guard in exactly ONE place, the multi-hit row, which is where
  # Reborn prices it too. A single-hit move keeps its full kill score against a Sturdy
  # target: see the withdrawal note in Core.score_move for why the first draft's
  # kill-call cancellation is not here.
  def test_a_single_hit_move_keeps_its_kill_score_against_sturdy
    foe = target(0, 100).merge("ability" => "STURDY", "full_hp" => true)
    actions = [
      move(0, "EARTHQUAKE", 0, 100, 200, {}),
      move(1, "SWORDSDANCE", 0, 300, 0, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("EARTHQUAKE", result[0]["move_id"])
    assert_equal(true, reasons_of(result[0]).include?("lethal"))
  end

  def test_mold_breaker_removes_the_multi_hit_bonus_for_beating_sturdy
    foe = target(0, 100).merge("ability" => "STURDY", "full_hp" => true)
    actions = [
      move(0, "ICICLESPEAR", 0, 100, 60, { "multi_hit" => true }),
      move(1, "ICICLECRASH", 0, 100, 68, {})
    ]
    plain = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    breaking = [
      move(0, "ICICLESPEAR", 0, 100, 60, { "multi_hit" => true, "mold_breaker" => true }),
      move(1, "ICICLECRASH", 0, 100, 68, { "mold_breaker" => true })
    ]
    broken = pick(snapshot([actor(1, 100, breaking, {})], [foe], {}), {})
    assert_equal("ICICLESPEAR", plain[0]["move_id"])
    assert_equal("ICICLECRASH", broken[0]["move_id"])
  end

  # --- abilities that reprice a boost or a status ---
  def test_setup_is_pointless_in_front_of_unaware
    foe = target(0, 100).merge("ability" => "UNAWARE")
    actions = [
      move(0, "DRAGONDANCE", 0, 200, 0, {}),
      move(1, "DRAGONCLAW", 0, 100, 30, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("DRAGONCLAW", result[0]["move_id"])
  end

  def test_contrary_inverts_both_setup_and_the_self_drop_charge
    foe = target(0, 100)
    actions = [
      move(0, "LEAFSTORM", 0, 100, 60, {}),
      move(1, "GIGADRAIN", 0, 100, 62, {})
    ]
    plain = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    contrary = pick(snapshot([actor(1, 100, actions, { "ability" => "CONTRARY" })], [foe], {}), {})
    assert_equal("GIGADRAIN", plain[0]["move_id"])
    assert_equal("LEAFSTORM", contrary[0]["move_id"])
  end

  def test_status_move_is_deterred_by_the_ability_that_profits_from_it
    guts = target(0, 100).merge("ability" => "GUTS")
    plain = target(0, 100)
    actions = [
      move(0, "WILLOWISP", 0, 100, 0, {}),
      move(1, "SEISMICTOSS", 0, 100, 15, {})
    ]
    assert_equal("WILLOWISP",
                 pick(snapshot([actor(1, 100, actions, {})], [plain], {}), {})[0]["move_id"])
    assert_equal("SEISMICTOSS",
                 pick(snapshot([actor(1, 100, actions, {})], [guts], {}), {})[0]["move_id"])
  end

  def test_dark_move_that_does_not_kill_feeds_justified
    foe = target(0, 100).merge("ability" => "JUSTIFIED")
    actions = [
      move(0, "CRUNCH", 0, 100, 40, { "move_type" => "DARK" }),
      move(1, "ICEFANG", 0, 100, 39, { "move_type" => "ICE" })
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("ICEFANG", result[0]["move_id"])
  end

  # --- turn shape ---
  def test_fake_out_is_free_on_turn_zero_and_unusable_after
    foe = target(0, 100)
    actions = [
      move(0, "FAKEOUT", 0, 100, 20, {}),
      move(1, "FLAREBLITZ", 0, 100, 60, {})
    ]
    first = pick(snapshot([actor(1, 100, actions, { "turncount" => 0, "faster" => true })], [foe], {}), {})
    later = pick(snapshot([actor(1, 100, actions, { "turncount" => 3, "faster" => true })], [foe], {}), {})
    assert_equal("FAKEOUT", first[0]["move_id"])
    assert_equal("FLAREBLITZ", later[0]["move_id"])
  end

  def test_trick_room_is_for_a_slow_team_and_never_twice
    foe = target(0, 100)
    actions = [
      move(0, "TRICKROOM", 0, 100, 0, { "own_reserves" => 4 }),
      move(1, "POWERWHIP", 0, 100, 20, {})
    ]
    slow = actor(1, 100, actions, { "faster" => false, "slower_bench_count" => 4 })
    fast_bench = actor(1, 100, actions, { "faster" => false, "slower_bench_count" => 0 })
    assert_equal("TRICKROOM", pick(snapshot([slow], [foe], {}), {})[0]["move_id"])
    assert_equal("POWERWHIP", pick(snapshot([fast_bench], [foe], {}), {})[0]["move_id"])
    active = snapshot([slow], [foe], {}).merge("trick_room_active" => true)
    assert_equal("POWERWHIP", pick(active, {})[0]["move_id"])
  end

  def test_future_sight_is_not_stacked_on_itself
    foe = target(0, 100)
    actions = [
      move(0, "FUTURESIGHT", 0, 100, 0, { "effect_active" => true }),
      move(1, "PSYCHIC", 0, 100, 20, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("PSYCHIC", result[0]["move_id"])
  end

  # --- doubles ---
  def test_spread_move_is_worth_double_into_an_absorbing_partner
    foes = [target(0, 100), target(2, 100)]
    left = actor(1, 100, [
      move(0, "DISCHARGE", nil, 100, 40, { "spread" => true, "move_type" => "ELECTRIC" }),
      move(1, "THUNDERBOLT", 0, 100, 46, { "move_type" => "ELECTRIC" })
    ], { "partner_alive" => true, "partner_ability" => "VOLTABSORB" })
    right = actor(3, 100, [move(0, "SURF", 0, 100, 10, {})], {})
    result = pick(snapshot([left, right], foes, {}), {})
    assert_equal("DISCHARGE", result[0]["move_id"])
  end

  def test_move_the_foes_partner_redirects_is_rejected
    foes = [target(0, 100).merge("partner_ability" => "LIGHTNINGROD"), target(2, 100)]
    left = actor(1, 100, [
      move(0, "THUNDERBOLT", 0, 100, 80, { "move_type" => "ELECTRIC" }),
      move(1, "ICEBEAM", 0, 100, 30, { "move_type" => "ICE" })
    ], {})
    right = actor(3, 100, [move(0, "SURF", 0, 100, 10, {})], {})
    result = pick(snapshot([left, right], foes, {}), {})
    assert_equal("ICEBEAM", result[0]["move_id"])
  end

  # Reborn does NOT have this row -- measured, it clicks the move its own partner
  # absorbs. Unit-tested here rather than in the corpus for exactly that reason.
  def test_move_the_own_partner_steals_is_discounted
    foes = [target(0, 100), target(2, 100)]
    left = actor(1, 100, [
      move(0, "THUNDERBOLT", 0, 100, 44, { "move_type" => "ELECTRIC" }),
      move(1, "ICEBEAM", 0, 100, 40, { "move_type" => "ICE" })
    ], { "partner_alive" => true, "partner_ability" => "LIGHTNINGROD" })
    right = actor(3, 100, [move(0, "SURF", 0, 100, 10, {})], {})
    result = pick(snapshot([left, right], foes, {}), {})
    assert_equal("ICEBEAM", result[0]["move_id"])
  end

  def test_partner_heal_is_a_dead_move_in_singles
    foe = target(0, 100)
    actions = [
      move(0, "HEALPULSE", 0, 100, 0, {}),
      move(1, "POWERWHIP", 0, 100, 5, {})
    ]
    result = pick(snapshot([actor(1, 100, actions, {})], [foe], {}), {})
    assert_equal("POWERWHIP", result[0]["move_id"])
  end

  def test_partner_heal_is_the_move_when_the_partner_is_nearly_dead
    foes = [target(0, 100), target(2, 100)]
    left = actor(1, 100, [
      move(0, "HEALPULSE", 0, 100, 0, {}),
      move(1, "POWERWHIP", 0, 100, 20, {})
    ], { "partner_alive" => true, "partner_hp_pct" => 15 })
    right = actor(3, 100, [move(0, "SURF", 0, 100, 10, {})], {})
    result = pick(snapshot([left, right], foes, {}), {})
    assert_equal("HEALPULSE", result[0]["move_id"])
  end

  # --- entry and switching ---
  def test_regenerator_discounts_leaving_but_cannot_open_the_gate
    foe = target(0, 100)
    actions = [move(0, "SURF", 0, 100, 5, {}), switch_action(1)]
    quiet = actor(1, 50, actions, { "ability" => "REGENERATOR" })
    # No escape reason: the switch is still refused outright.
    assert_equal("move", pick(snapshot([quiet], [foe], {}), {})[0]["type"])
    escaping = actor(1, 50, actions, { "ability" => "REGENERATOR", "yawned" => true })
    plain = actor(1, 50, actions, { "yawned" => true })
    a = pick(snapshot([escaping], [foe], {}), {})[0]
    b = pick(snapshot([plain], [foe], {}), {})[0]
    assert_equal("switch", a["type"])
    assert_equal(50.0, (a["score"] - b["score"]).round(1))
  end

  def test_real_entry_damage_replaces_the_type_proxy
    foe = target(0, 100)
    safe = { "type" => "switch", "slot" => 1, "base_score" => 100, "matchup_score" => 0,
             "incoming_risk" => 32, "candidate_hp_pct" => 100,
             "entry_damage_pct" => 0, "incoming_damage_pct" => 5 }
    risky = { "type" => "switch", "slot" => 2, "base_score" => 100, "matchup_score" => 0,
              "incoming_risk" => 32, "candidate_hp_pct" => 100,
              "entry_damage_pct" => 0, "incoming_damage_pct" => 80 }
    actions = [move(0, "SURF", 0, 100, 5, {}), safe, risky]
    chosen = pick(snapshot([actor(1, 50, actions, { "yawned" => true })], [foe], {}), {})[0]
    assert_equal(1, chosen["slot"])
    assert_equal(true, reasons_of(chosen).include?("entry_incoming_damage"))
  end

  # --- the four off-switches ---
  #
  # Each key false must reproduce the 0.4.1 pick on a board the corresponding table
  # would otherwise decide. Together they are the control run in B5.
  def test_side_effects_off_restores_the_bare_damage_ranking
    foe = target(0, 100).merge("physical_attacker" => true)
    actions = [
      move(0, "SCALD", 0, 100, 40, sec("burn", 100, {})),
      move(1, "SURF", 0, 100, 50, {})
    ]
    snap = snapshot([actor(1, 100, actions, {})], [foe], {})
    assert_equal("SCALD", pick(snap, {})[0]["move_id"])
    assert_equal("SURF", pick(snap, { "side_effects" => false })[0]["move_id"])
  end

  def test_ability_rules_off_restores_the_unaware_boost
    foe = target(0, 100).merge("ability" => "UNAWARE")
    actions = [
      move(0, "DRAGONDANCE", 0, 200, 0, {}),
      move(1, "DRAGONCLAW", 0, 100, 30, {})
    ]
    snap = snapshot([actor(1, 100, actions, {})], [foe], {})
    assert_equal("DRAGONCLAW", pick(snap, {})[0]["move_id"])
    assert_equal("DRAGONDANCE", pick(snap, { "ability_rules" => false })[0]["move_id"])
  end

  def test_entry_rules_off_restores_the_type_proxy
    foe = target(0, 100)
    safe = { "type" => "switch", "slot" => 1, "base_score" => 100, "matchup_score" => 0,
             "incoming_risk" => 128, "candidate_hp_pct" => 100,
             "entry_damage_pct" => 0, "incoming_damage_pct" => 5 }
    risky = { "type" => "switch", "slot" => 2, "base_score" => 100, "matchup_score" => 0,
              "incoming_risk" => 0, "candidate_hp_pct" => 100,
              "entry_damage_pct" => 0, "incoming_damage_pct" => 80 }
    actions = [move(0, "SURF", 0, 100, 5, {}), safe, risky]
    snap = snapshot([actor(1, 50, actions, { "yawned" => true })], [foe], {})
    assert_equal(1, pick(snap, {})[0]["slot"])
    assert_equal(2, pick(snap, { "entry_rules" => false })[0]["slot"])
  end

  def test_format_rules_off_lets_the_partner_absorb_go_unpriced
    foes = [target(0, 100), target(2, 100)]
    left = actor(1, 100, [
      move(0, "DISCHARGE", nil, 100, 40, { "spread" => true, "move_type" => "ELECTRIC" }),
      move(1, "THUNDERBOLT", 0, 100, 46, { "move_type" => "ELECTRIC" })
    ], { "partner_alive" => true, "partner_ability" => "VOLTABSORB" })
    right = actor(3, 100, [move(0, "SURF", 0, 100, 10, {})], {})
    snap = snapshot([left, right], foes, {})
    assert_equal("DISCHARGE", pick(snap, {})[0]["move_id"])
    assert_equal("THUNDERBOLT", pick(snap, { "format_rules" => false })[0]["move_id"])
  end
  # --- 0.6.0 damage race ---------------------------------------------------
  # Core.damage_race is a pure function of the snapshot, so these call it directly
  # rather than inferring it from a pick.
  RACE_ON = { "damage_race" => true }

  def race_actor(hp, damage, threat, extra)
    actions = [move(0, "STRENGTH", 0, 100, damage, {})]
    (extra || {}).each { |k, v| actions[0][k] = v if k == "priority" }
    a = actor(1, hp, actions, { "threats_by_foe" => { "0" => threat } })
    (extra || {}).each { |k, v| a[k] = v if k != "priority" }
    a
  end

  def race(actor_hp, my_damage, foe_hp, threat, extra)
    foe = target(0, foe_hp)
    a = race_actor(actor_hp, my_damage, threat, extra)
    PortableAI.damage_race(snapshot([a], [foe], {}), a, foe, RACE_ON)
  end

  def threat(damage, priority, faster)
    { "damage_pct" => damage, "priority_damage_pct" => priority, "faster" => faster }
  end

  def test_race_fewer_hits_wins_even_when_slower
    r = race(100, 50, 100, threat(34, 0, false), {})   # mine 2, theirs 3
    assert_equal(2, r["mine"])
    assert_equal(3, r["theirs"])
    assert_equal(true, r["winning"])
  end

  def test_race_more_hits_loses_even_with_a_priority_finisher
    r = race(100, 34, 100, threat(50, 0, true), { "priority" => 1 })  # mine 3, theirs 2
    assert_equal(false, r["winning"])
  end

  def test_race_equal_hits_are_decided_by_speed
    assert_equal(true, race(100, 50, 100, threat(50, 0, true), {})["winning"])
    assert_equal(false, race(100, 50, 100, threat(50, 0, false), {})["winning"])
  end

  def test_race_equal_hits_a_priority_finisher_beats_being_slower
    # Two hits each; my second hit is the priority one and it finishes the job.
    r = race(100, 50, 100, threat(50, 0, false), { "priority" => 1 })
    assert_equal(true, r["last_hit_first"])
    assert_equal(true, r["winning"])
  end

  def test_race_the_foes_priority_finisher_beats_my_speed
    r = race(100, 50, 100, threat(50, 50, true), {})
    assert_equal(false, r["last_hit_first"])
    assert_equal(false, r["winning"])
  end

  def test_race_residual_costs_a_turn
    # 30% a hit alone needs two from 40%; with 12.5% of leech on top it needs one.
    assert_equal(2, race(40, 50, 100, threat(30, 0, true), {})["theirs"])
    assert_equal(1, race(40, 50, 100, threat(30, 0, true),
                         { "residual_damage_pct" => 12.5 })["theirs"])
  end

  def test_race_is_nil_without_the_export_or_without_damage
    foe = target(0, 100)
    bare = actor(1, 100, [move(0, "STRENGTH", 0, 100, 50, {})], {})
    snap = snapshot([bare], [foe], {})
    assert_nil(PortableAI.damage_race(snap, bare, foe, RACE_ON))
    assert_nil(race(100, 0, 100, threat(50, 0, true), {}))
  end

  def test_race_off_returns_nil
    assert_nil(PortableAI.damage_race(
      snapshot([race_actor(100, 50, threat(50, 0, true), {})], [target(0, 100)], {}),
      race_actor(100, 50, threat(50, 0, true), {}), target(0, 100),
      { "damage_race" => false }))
  end

  # The setup move carries NO target, exactly as the adapter exports it: a status move
  # has no scoring target, and the first cut of setup_into_2hko? was inert everywhere
  # because of it.
  def setup_snap(damage, threat_pct, faster)
    foe = target(0, 100)
    actions = [
      move(0, "SWORDSDANCE", nil, 300, 0, {}),
      move(1, "STRENGTH", 0, 100, damage, {})
    ]
    a = actor(1, 100, actions,
              { "threats_by_foe" => { "0" => threat(threat_pct, 0, faster) } })
    snapshot([a], [foe], {})
  end

  def test_setup_into_2hko_is_refused_when_slower
    snap = setup_snap(34, 50, false)
    assert_equal("STRENGTH", pick(snap, {})[0]["move_id"])
  end

  def test_setup_is_allowed_when_only_3hkoed
    assert_equal("SWORDSDANCE", pick(setup_snap(34, 34, false), {})[0]["move_id"])
  end

  def test_setup_is_allowed_when_faster
    assert_equal("SWORDSDANCE", pick(setup_snap(34, 50, true), {})[0]["move_id"])
  end

  def test_damage_race_off_restores_the_0_5_0_setup_pick
    snap = setup_snap(34, 50, false)
    assert_equal("SWORDSDANCE",
                 pick(snap, { "damage_race" => false })[0]["move_id"])
  end

  def switch_race_snap(hp, threat_pct, boost)
    foe = target(0, 100).merge("positive_stages" => boost)
    out = { "type" => "switch", "slot" => 1, "base_score" => 100,
            "matchup_score" => 0, "candidate_hp_pct" => 100 }
    actions = [move(0, "STRENGTH", 0, 100, 20, {}), out]
    a = actor(1, hp, actions,
              { "threats_by_foe" => { "0" => threat(threat_pct, 0, false) } })
    snapshot([a], [foe], {})
  end

  def test_losing_race_opens_the_gate_only_when_healthy_and_switched_on
    on = { "damage_race_switch" => true }
    assert_equal("switch", pick(switch_race_snap(100, 50, 0), on)[0]["type"])
    # Off by default: 0.5.0's gate refuses the switch for want of a reason.
    assert_equal("move", pick(switch_race_snap(100, 50, 0), {})[0]["type"])
    # Not below the healthy pivot, and not against a boosted foe.
    assert_equal("move", pick(switch_race_snap(40, 50, 0), on)[0]["type"])
    assert_equal("move", pick(switch_race_snap(100, 50, 2), on)[0]["type"])
    # Not when the foe needs three.
    assert_equal("move", pick(switch_race_snap(100, 34, 0), on)[0]["type"])
  end

  def test_switchin_race_prefers_the_candidate_the_foe_needs_more_hits_for
    foe = target(0, 100)
    bulky = { "type" => "switch", "slot" => 1, "base_score" => 100, "matchup_score" => 0,
              "candidate_hp_pct" => 100, "entry_damage_pct" => 0,
              "incoming_damage_pct" => 20, "outgoing_damage_pct" => 30,
              "faster" => false }
    frail = { "type" => "switch", "slot" => 2, "base_score" => 100, "matchup_score" => 0,
              "candidate_hp_pct" => 100, "entry_damage_pct" => 0,
              "incoming_damage_pct" => 55, "outgoing_damage_pct" => 30,
              "faster" => false }
    actions = [move(0, "STRENGTH", 0, 100, 5, {}), bulky, frail]
    snap = snapshot([actor(1, 50, actions, { "yawned" => true })], [foe], {})
    assert_equal(1, pick(snap, {})[0]["slot"])
  end

  def test_switchin_race_pays_for_outspeeding_and_needs_both_fields
    foe = target(0, 100)
    fast = { "type" => "switch", "slot" => 1, "base_score" => 100, "matchup_score" => 0,
             "candidate_hp_pct" => 100, "entry_damage_pct" => 0,
             "incoming_damage_pct" => 30, "outgoing_damage_pct" => 30,
             "faster" => true }
    slow = { "type" => "switch", "slot" => 2, "base_score" => 100, "matchup_score" => 0,
             "candidate_hp_pct" => 100, "entry_damage_pct" => 0,
             "incoming_damage_pct" => 30, "outgoing_damage_pct" => 30,
             "faster" => false }
    actions = [move(0, "STRENGTH", 0, 100, 5, {}), fast, slow]
    snap = snapshot([actor(1, 50, actions, { "yawned" => true })], [foe], {})
    assert_equal(1, pick(snap, {})[0]["slot"])
    assert(reasons_of(pick(snap, {})[0]).include?("switchin_race"))
    # A candidate the adapter could not estimate contributes no race term at all.
    bare = { "type" => "switch", "slot" => 3, "base_score" => 100,
             "matchup_score" => 0, "candidate_hp_pct" => 100 }
    snap2 = snapshot([actor(1, 50, [move(0, "STRENGTH", 0, 100, 5, {}), bare],
                            { "yawned" => true })], [foe], {})
    assert(!reasons_of(pick(snap2, {})[0]).include?("switchin_race"))
  end

  # ---------------------------------------------------------------------------
  # 0.6.2 bugfix batch. Every test asserts BOTH directions: the fix, and that the
  # key off restores the 0.6.1 behaviour it replaces. The control run for the whole
  # version rests on that second half being true seven times over.
  # ---------------------------------------------------------------------------

  # A spread move registers against no single battler, so the adapter sets
  # action["target"] = nil and target_for finds nothing. The exported target_hp_pct is
  # the same fact by another route: without it Earthquake is scored against a phantom
  # 100% target and can never be lethal, whatever the real target's HP.
  def spread_snap
    foe = target(0, 8)
    quake = move(0, "EARTHQUAKE", nil, 100, 30, { "target_hp_pct" => 8 })
    jab = move(1, "POISONJAB", 0, 100, 26, {})
    snapshot([actor(1, 100, [quake, jab], {})], [foe], {})
  end

  def test_spread_move_reaches_lethal_from_the_exported_target_hp
    result = pick(spread_snap, {})[0]
    assert_equal("EARTHQUAKE", result["move_id"])
    assert(reasons_of(result).include?("lethal"))
  end

  def test_spread_target_hp_off_leaves_the_move_on_expected_damage
    result = pick(spread_snap, { "spread_target_hp" => false })[0]
    assert_equal("POISONJAB", result["move_id"])
  end

  # Two moves, both lethal. Fire Blast is super-effective and 85% accurate; Dragon
  # Claw is neutral and never misses. Once the target is dying either way the type
  # chart has nothing left to say, so the accurate one has to win.
  def kill_snap
    foe = target(0, 20)
    blast = move(0, "FIREBLAST", 0, 100, 60,
                 { "effectiveness" => 2, "accuracy" => 85 })
    claw = move(1, "DRAGONCLAW", 0, 100, 40,
                { "effectiveness" => 1, "accuracy" => 100 })
    snapshot([actor(1, 100, [blast, claw], {})], [foe], {})
  end

  def test_a_kill_is_chosen_on_accuracy_not_on_type
    assert_equal("DRAGONCLAW", pick(kill_snap, {})[0]["move_id"])
  end

  def test_lethal_flat_off_restores_the_super_effective_pick
    assert_equal("FIREBLAST",
                 pick(kill_snap, { "lethal_flat" => false })[0]["move_id"])
  end

  # A spread action is a summary of several targets, not one kill: its damage is the
  # sum over the foes and its effectiveness is what choose_joint weighs "resolves the
  # whole field" against. Flattening it cost a double kill on the corpus card
  # d_spread_kills_both_preferred, so the rule stops at the spread flag.
  def test_a_spread_kill_keeps_its_effectiveness_term
    foe = target(0, 20)
    quake = move(0, "EARTHQUAKE", nil, 100, 120,
                 { "effectiveness" => 4, "spread" => true, "target_hp_pct" => 20 })
    result = pick(snapshot([actor(1, 100, [quake], {})], [foe], {}), {})[0]
    assert(reasons_of(result).include?("super_effective"))
    assert_equal(false, reasons_of(result).include?("lethal_flat"))
  end

  # 24% HP, 10% hazards on the way in, 30% incoming: 24 - 10 - 30*0.85 = -11.5, dead
  # before it moves. The healthy candidate has the same matchup and must be preferred.
  def entry_death_snap(candidate_hp)
    foe = target(0, 100)
    dying = { "type" => "switch", "slot" => 1, "base_score" => 140,
              "matchup_score" => 0, "forced" => true,
              "candidate_hp_pct" => candidate_hp, "entry_damage_pct" => 10,
              "incoming_damage_pct" => 30 }
    healthy = { "type" => "switch", "slot" => 2, "base_score" => 100,
                "matchup_score" => 0, "forced" => true,
                "candidate_hp_pct" => 100, "entry_damage_pct" => 10,
                "incoming_damage_pct" => 30 }
    snapshot([actor(1, 100, [dying, healthy], {})], [foe], {})
  end

  def test_a_switch_in_that_dies_before_it_moves_is_charged
    assert_equal(2, pick(entry_death_snap(24), {})[0]["slot"])
  end

  def test_entry_death_is_a_penalty_not_a_rejection
    # Only the dying body is on the bench: it is still registered, because a forced
    # replacement has to send SOMETHING.
    foe = target(0, 100)
    only = { "type" => "switch", "slot" => 1, "base_score" => 100,
             "matchup_score" => 0, "forced" => true, "candidate_hp_pct" => 24,
             "entry_damage_pct" => 10, "incoming_damage_pct" => 30 }
    result = pick(snapshot([actor(1, 100, [only], {})], [foe], {}), {})[0]
    assert_equal("switch", result["type"])
    assert(reasons_of(result).include?("dies_on_entry"))
  end

  def test_entry_death_off_takes_the_higher_scoring_corpse
    assert_equal(1, pick(entry_death_snap(24), { "entry_death" => false })[0]["slot"])
  end

  def test_a_candidate_that_survives_the_minimum_roll_is_not_charged
    # 46 - 10 - 25.5 = +10.5. The point estimate alone would have killed it.
    result = pick(entry_death_snap(46), {})[0]
    assert_equal(1, result["slot"])
  end

  # Wish with a Wish already pending is "But it failed!"
  # (PokeBattle_MoveEffects.rb:6084). effect_active is the channel the adapter reports
  # it on, the same one the screens use.
  def wish_snap
    foe = target(0, 100)
    wish = move(0, "WISH", nil, 200, 0, { "effect_active" => true })
    hit = move(1, "BODYSLAM", 0, 100, 20, {})
    snapshot([actor(1, 50, [wish, hit], {})], [foe], {})
  end

  def test_wish_is_refused_while_one_is_pending
    assert_equal("BODYSLAM", pick(wish_snap, {})[0]["move_id"])
  end

  def test_wish_pending_off_re_clicks_it
    assert_equal("WISH", pick(wish_snap, { "wish_pending" => false })[0]["move_id"])
  end

  # +2 Attack already standing, and the memory counter zeroed by the attack in
  # between. The stages are the durable record of the same fact.
  def setup_stage_snap(stages)
    foe = target(0, 100)
    actions = [
      move(0, "SWORDSDANCE", nil, 400, 0, {}),
      move(1, "CLOSECOMBAT", 0, 100, 45, {})
    ]
    snapshot([actor(1, 100, actions, { "positive_stage_total" => stages })], [foe], {})
  end

  def test_a_boosted_actor_does_not_get_a_first_setup_bonus
    result = pick(setup_stage_snap(2), {})[0]
    assert_equal("SWORDSDANCE", result["move_id"])
    assert(reasons_of(result).include?("repeated_setup"))
  end

  def test_an_unboosted_actor_still_gets_first_setup
    result = pick(setup_stage_snap(0), {})[0]
    assert(reasons_of(result).include?("first_setup"))
  end

  def test_setup_stage_off_calls_a_plus_two_sweeper_a_first_setup
    result = pick(setup_stage_snap(2), { "setup_stage" => false })[0]
    assert(reasons_of(result).include?("first_setup"))
  end

  # A move the engine refused last turn against this same target will be refused
  # again. Sucker Punch was re-clicked three turns running with Knock Off one point
  # behind, so the charge has to be bigger than that gap.
  def failed_move_snap
    foe = target(0, 100)
    sucker = move(0, "SUCKERPUNCH", 0, 100, 40, { "failed_last_turn" => true })
    knock = move(1, "KNOCKOFF", 0, 100, 38, {})
    snapshot([actor(1, 100, [sucker, knock], {})], [foe], {})
  end

  def test_a_move_that_failed_last_turn_is_not_re_clicked
    result = pick(failed_move_snap, {})[0]
    assert_equal("KNOCKOFF", result["move_id"])
  end

  def test_move_memory_off_re_clicks_the_dead_move
    assert_equal("SUCKERPUNCH",
                 pick(failed_move_snap, { "move_memory" => false })[0]["move_id"])
  end

  # --- 0.6.3 leave a losing race for a bench candidate that wins it -------------
  #
  # Every test asserts both directions: the rule, and that the key off restores the
  # 0.6.2 behaviour. Both keys false is the control run.

  def bench(slot, outgoing, incoming, faster)
    { "type" => "switch", "slot" => slot, "base_score" => 100, "matchup_score" => 0,
      "candidate_hp_pct" => 100, "entry_damage_pct" => 0,
      "outgoing_damage_pct" => outgoing, "incoming_damage_pct" => incoming,
      "faster" => faster }
  end

  # The actor hits for 20 (five to KO) and the foe hits it for 50 (two): a race lost
  # by three whole hits, at full health, against an unboosted foe.
  def losing_race_snap(actions, extra = {}, boost = 0)
    foe = target(0, 100).merge("positive_stages" => boost)
    fields = { "threats_by_foe" => { "0" => threat(50, 0, false) },
               "incoming_damage_pct" => 50 }
    extra.each { |k, v| fields[k] = v }
    a = actor(1, 100, [move(0, "STRENGTH", 0, 100, 20, {})] + actions, fields)
    snapshot([a], [foe], {})
  end

  def test_losing_race_leaves_for_a_bench_candidate_that_wins_it
    # Bench 1 two-shots the foe and eats 20 a hit: after the free entry hit it has 80
    # left, four more hits for the foe against two of its own.
    snap = losing_race_snap([bench(1, 60, 20, false)])
    result = pick(snap, {})[0]
    assert_equal("switch", result["type"])
    assert_equal(1, result["slot"])
    assert(reasons_of(result).include?("losing_race_bench_wins"))
    # Keyed off, the 0.6.2 gate refuses it for want of a reason.
    off = pick(snap, { "race_switch_to_winner" => false })[0]
    assert_equal("move", off["type"])
  end

  def test_a_bench_candidate_that_also_loses_does_not_open_the_gate
    # Bench 1 needs five hits and takes three: it loses the same race, only slower.
    result = pick(losing_race_snap([bench(1, 20, 40, false)]), {})[0]
    assert_equal("move", result["type"])
  end

  def test_the_switch_turn_is_paid_for
    # The candidate two-shots the foe and is two-shot itself. It attacks nothing on
    # the turn it comes in, so the foe's second hit lands first however fast it is.
    assert_equal("move", pick(losing_race_snap([bench(1, 50, 50, true)]), {})[0]["type"])
    # Three-shot instead: after the free hit the foe still needs two, and now the
    # candidate's speed decides the last exchange.
    assert_equal("switch", pick(losing_race_snap([bench(1, 50, 34, true)]), {})[0]["type"])
    assert_equal("move", pick(losing_race_snap([bench(1, 50, 34, false)]), {})[0]["type"])
  end

  def test_a_heal_that_covers_two_hits_keeps_the_actor_in
    # Counted in hits the race is lost either way. A healer alternates healing and
    # attacking, so one Recover has to cover two of the foe's hits to sustain: it
    # does against 20 a hit, and bleeds out against 30.
    recover = move(2, "RECOVER", nil, 100, 0, {})
    stays = losing_race_snap([recover, bench(1, 60, 20, false)],
                             { "threats_by_foe" => { "0" => threat(20, 0, false) },
                               "incoming_damage_pct" => 20 })
    leaves = losing_race_snap([recover, bench(1, 60, 20, false)],
                              { "threats_by_foe" => { "0" => threat(30, 0, false) },
                                "incoming_damage_pct" => 30 })
    assert_equal("move", pick(stays, {})[0]["type"])
    assert_equal("switch", pick(leaves, {})[0]["type"])
  end

  def test_a_boosted_foe_does_not_veto_leaving_for_a_winner
    # The foe's stages are already inside the candidate's incoming estimate, so the
    # suppression the 0.6.0 flag carries has nothing to guard against here.
    snap = losing_race_snap([bench(1, 60, 20, false)], {}, 2)
    assert_equal("switch", pick(snap, {})[0]["type"])
  end

  def test_a_candidate_that_dies_on_entry_never_wins_its_race
    assert_equal("move", pick(losing_race_snap([bench(1, 60, 100, true)]), {})[0]["type"])
  end

  def test_a_candidate_without_estimates_cannot_claim_the_race
    blind = { "type" => "switch", "slot" => 1, "base_score" => 100,
              "matchup_score" => 0, "candidate_hp_pct" => 100 }
    assert_equal("move", pick(losing_race_snap([blind]), {})[0]["type"])
  end

  def test_an_even_race_lost_on_the_tiebreak_does_not_open_the_gate
    # Two hits each way and the actor is "slower" -- which is what the adapters export
    # on a speed TIE too, so a mirror match reads as lost from both chairs. Leaving
    # over that would have both Snorlax running from each other.
    even = losing_race_snap([bench(1, 60, 20, false)],
                            { "threats_by_foe" => { "0" => threat(50, 0, false) },
                              "incoming_damage_pct" => 50 })
    even["actors"][0]["actions"][0]["expected_damage_pct"] = 50   # mine 2, theirs 2
    assert_equal("move", pick(even, {})[0]["type"])
    assert_equal(false, PortableAI.race_lost_by_a_hit?(
                          { "winning" => false, "mine" => 2, "theirs" => 2 }))
    assert_equal(true, PortableAI.race_lost_by_a_hit?(
                         { "winning" => false, "mine" => 3, "theirs" => 2 }))
  end

  def test_a_wall_that_cannot_finish_is_not_a_winner
    # Immune to everything the foe has, and needing fifteen hits of its own: the
    # count sits at the cap, and the cap means "stall war", not "win".
    wall = bench(1, 7, 0, true)
    assert_equal(false, PortableAI.candidate_race(wall, target(0, 100))["winning"])
    assert_equal("move", pick(losing_race_snap([wall]), {})[0]["type"])
  end

  def test_candidate_race_counts_the_free_hit
    race = PortableAI.candidate_race(bench(1, 60, 20, false), target(0, 100))
    assert_equal(2, race["mine"])
    assert_equal(5, race["theirs"])     # the free hit, then four more on 80
    assert_equal(true, race["winning"])
    assert_nil(PortableAI.candidate_race(bench(1, 60, 20, false), nil))
  end

  # --- 0.6.3 "I cannot hurt it" needs a bench body that can ---------------------

  # A wall: the actor's best hit is 5%, so weak_current_attacks would open the gate
  # for anything. No race is exported, so only that reason is in play.
  def wall_snap(candidates)
    a = actor(1, 80, [move(0, "STRENGTH", 0, 100, 5, {})] + candidates,
              { "best_damage_pct" => 5 })
    snapshot([a], [target(0, 100)], {})
  end

  def test_weak_attacks_leave_only_for_a_body_that_hits
    weak = bench(1, 6, 10, false)       # as weak as the one leaving
    hits = bench(2, 30, 10, false)
    result = pick(wall_snap([weak, hits]), {})[0]
    assert_equal("switch", result["type"])
    assert_equal(2, result["slot"])
    # Alone, the weak body cannot open the gate: the actor stays and attacks.
    alone = pick(wall_snap([weak]), {})[0]
    assert_equal("move", alone["type"])
    assert(reasons_of(pick(wall_snap([weak]), {})[0]).include?("STRENGTH") == false)
    # Keyed off, 0.6.2's shape: the weak body is a legal escape again.
    off = pick(wall_snap([weak]), { "escape_needs_hitter" => false })[0]
    assert_equal("switch", off["type"])
  end

  def test_no_effective_move_leaves_only_for_a_body_that_hits
    weak = bench(1, 6, 10, false)
    a = actor(1, 80, [move(0, "STRENGTH", 0, 100, 0, {}), weak],
              { "no_effective_move" => true })
    assert_equal("move", pick(snapshot([a], [target(0, 100)], {}), {})[0]["type"])
    a["actions"][1] = bench(1, 30, 10, false)
    assert_equal("switch", pick(snapshot([a], [target(0, 100)], {}), {})[0]["type"])
  end

  def test_a_candidate_without_an_estimate_is_not_held_to_one
    # No outgoing_damage_pct on the action (an older adapter): the reason keeps its
    # 0.6.2 shape rather than refusing on a number nobody computed.
    blind = { "type" => "switch", "slot" => 1, "base_score" => 100,
              "matchup_score" => 0, "candidate_hp_pct" => 100 }
    assert_equal("switch", pick(wall_snap([blind]), {})[0]["type"])
  end

  # --- 0.6.4 the switch-in is graded on who lands the last hit ------------------
  #
  # The grade ships OFF (see Model::DEFAULT_CONFIG for the measurement), so every
  # test turns it on by hand and asserts the default's 0.6.3 shape as well.

  GRADE = { "switchin_race_grade" => true }

  def test_kill_order_grades_by_the_margin_in_hits
    foe = target(0, 100)
    grade = lambda { |b| PortableAI.kill_order_grade(PortableAI.candidate_race(b, foe)) }
    # Two-shots the foe, takes 20: after the free hit the foe needs four more.
    assert_equal(150, grade.call(bench(1, 60, 20, false)))
    # Three-shots it, takes 20: four more after the free hit, a win by one.
    assert_equal(110, grade.call(bench(1, 34, 20, false)))
    # Three each way once the free hit is paid: speed decides.
    assert_equal(70, grade.call(bench(1, 34, 25, true)))
    assert_equal(-30, grade.call(bench(1, 34, 25, false)))
    # Loses by one, by two, and dies on entry.
    assert_equal(-70, grade.call(bench(1, 34, 34, true)))
    assert_equal(-110, grade.call(bench(1, 20, 50, true)))
    assert_equal(-110, grade.call(bench(1, 60, 100, true)))
    # Nothing of the foe's gets through: a win by everything up to the cap.
    assert_equal(150, grade.call(bench(1, 60, 0, false)))
    # At the cap the count is a stall war, graded by the defensive bands instead.
    assert_equal(0, grade.call(bench(1, 7, 0, true)))
    assert_equal(0, PortableAI.kill_order_grade(nil))
  end

  def test_a_forced_replacement_prefers_the_body_that_kills_first
    # Both take 20 a hit, so Radical Red's defensive bands see two identical bodies.
    # Slot 1 needs four hits, slot 2 needs two: Slowbro over Scizor into Heatran.
    slow = bench(1, 25, 20, false).merge("forced" => true)
    fast = bench(2, 50, 20, false).merge("forced" => true)
    a = actor(1, 0, [slow, fast], {})
    snap = snapshot([a], [target(0, 100)], {})
    result = pick(snap, GRADE)[0]
    assert_equal(2, result["slot"])
    assert(reasons_of(result).include?("kill_order"))
    # By default (the grade off) the two are the same body and slot order wins.
    off = pick(snap, {})[0]
    assert_equal(1, off["slot"])
    assert(!reasons_of(off).include?("kill_order"))
  end

  def test_a_losing_bench_body_is_charged_for_the_race_it_loses
    # The actor is Yawned, so leaving has its reason; the bench body is two-shot
    # after the free hit and needs four of its own. It still comes in -- the yawn is
    # worth more than the race -- but the grade is on the record, and by default the
    # switch scores exactly what 0.6.3 gave it.
    loser = bench(1, 25, 50, false)
    a = actor(1, 100, [move(0, "STRENGTH", 0, 100, 20, {}), loser], { "yawned" => true })
    snap = snapshot([a], [target(0, 100)], {})
    on = pick(snap, GRADE)[0]
    off = pick(snap, {})[0]
    assert_equal("switch", on["type"])
    assert_equal(-110, reason_value(on, "kill_order"))
    assert_equal(off["score"] - 110, on["score"])
  end

  def test_the_grade_replaces_the_flat_bonus_of_the_losing_race_gate
    snap = losing_race_snap([bench(1, 60, 20, false)])
    on = pick(snap, GRADE)[0]
    off = pick(snap, {})[0]
    assert_equal("switch", on["type"])
    assert_equal(0, reason_value(on, "losing_race_bench_wins"))
    assert_equal(150, reason_value(on, "kill_order"))
    assert_equal(110, reason_value(off, "losing_race_bench_wins"))
    assert_nil(reason_value(off, "kill_order"))
  end

  def test_in_doubles_the_candidate_is_graded_on_its_worse_race
    # 21% two-shots a foe at 40 (a win by two) and five-shots one at full health
    # (four more for the foe after the free hit: a loss by one). The worse race is
    # the one that counts.
    a = actor(1, 100, [move(0, "STRENGTH", 0, 100, 20, {}), bench(1, 21, 20, false)],
              { "yawned" => true })
    assert_equal(150, reason_value(pick(snapshot([a], [target(0, 40)], {}), GRADE)[0], "kill_order"))
    both = snapshot([a], [target(0, 40), target(2, 100)], {})
    assert_equal(-70, reason_value(pick(both, GRADE)[0], "kill_order"))
  end

  # --- 0.6.4 "I cannot hurt it" needs a body that breaks the wall ---------------

  def test_the_bench_body_has_to_beat_the_actor_by_two_hits
    # The actor hits the full-health wall for 5 (the cap). 20 is four-plus-one hits:
    # over the 10% line, and not a wall-breaker. 30 is four hits and is.
    line = bench(1, 20, 10, false)
    breaker = bench(2, 30, 10, false)
    assert_equal("move", pick(wall_snap([line]), {})[0]["type"])
    assert_equal("switch", pick(wall_snap([breaker]), {})[0]["type"])
    # 0.6.3's line: 20 clears 10% and opens the gate.
    assert_equal("switch", pick(wall_snap([line]), { "escape_wall_margin" => false })[0]["type"])
    # The margin refines escape_needs_hitter and is inert without it.
    weak = bench(1, 6, 10, false)
    assert_equal("switch", pick(wall_snap([weak]),
                                { "escape_needs_hitter" => false })[0]["type"])
  end

  def test_the_wall_margin_is_counted_on_the_wall_it_has_left
    # At 40% the actor's 5 is still eight hits, and 15 is three: enough.
    snap = wall_snap([bench(1, 15, 10, false)])
    snap["targets"][0]["hp_pct"] = 40
    assert_equal("switch", pick(snap, {})[0]["type"])
    # Against an actor that hits for 9 (five hits at 40), 15 is three: two fewer, ok;
    # 12 is four: only one fewer, and the gate stays shut.
    snap["actors"][0]["best_damage_pct"] = 9
    assert_equal("switch", pick(snap, {})[0]["type"])
    snap["actors"][0]["actions"][1] = bench(1, 12, 10, false)
    assert_equal("move", pick(snap, {})[0]["type"])
  end

  def test_the_wall_breaker_needs_no_more_than_four_hits_of_its_own
    # Actor at 5 is eight hits; 17 is six -- two fewer, but six is not breaking a wall.
    assert_equal("move", pick(wall_snap([bench(1, 17, 10, false)]), {})[0]["type"])
    assert_equal(false, PortableAI.candidate_can_hit?(
                          wall_snap([]), wall_snap([])["actors"][0],
                          bench(1, 17, 10, false), PortableAI::Model.config({})))
    assert_nil(PortableAI.candidate_can_hit?(
                 snapshot([actor(1, 80, [], {})], [], {}), { "best_damage_pct" => 5 },
                 bench(1, 30, 10, false), PortableAI::Model.config({})))
  end

  # --- 0.6.3 a heal that only delays is not a save ------------------------------

  def zapdos(incoming, extra_actions = [])
    actions = [move(0, "ROOST", nil, 100, 0, {}),
               move(1, "DISCHARGE", 0, 100, 23, {})] + extra_actions
    # 13% HP, faster, five hits from a KO against one.
    actor(1, 13, actions, { "incoming_damage_pct" => incoming, "faster" => true,
                            "threats_by_foe" => { "0" => threat(incoming, 0, false) } })
  end

  def test_a_heal_that_only_delays_is_not_a_save
    snap = snapshot([zapdos(57)], [target(0, 100)], {})
    on = pick(snap, {})[0]
    assert(reasons_of(on).include?("heal_only_delays"))
    assert(!reasons_of(on).include?("heal_saves_battler"))
    off = pick(snap, { "heal_outpace" => false })[0]
    assert(reasons_of(off).include?("heal_saves_battler"))
  end

  def test_a_heal_that_outpaces_the_hit_still_saves
    # Roost +50 against a 28% hit: the heal changes who is alive at the end of the
    # turn, and the turn after, so 0.6.2's verdict stands.
    result = pick(snapshot([zapdos(28)], [target(0, 100)], {}), {})[0]
    assert_equal("ROOST", result["move_id"])
    assert(reasons_of(result).include?("heal_saves_battler"))
  end

  def test_a_heal_that_only_delays_still_beats_attacking_with_no_bench
    # -120 is a charge, not a veto: with nowhere to go, healing into the hit is still
    # better than a 23% Discharge and dying.
    result = pick(snapshot([zapdos(57)], [target(0, 100)], {}), {})[0]
    assert_equal("ROOST", result["move_id"])
  end

  def test_zapdos_leaves_for_chansey_instead_of_roosting_into_a_bigger_hit
    # Chansey three-shots the foe and takes 10 a hit: the foe needs ten.
    chansey = bench(1, 34, 10, false)
    result = pick(snapshot([zapdos(57, [chansey])], [target(0, 100)], {}), {})[0]
    assert_equal("switch", result["type"])
    assert(reasons_of(result).include?("losing_race_bench_wins"))
    # Both keys off: 0.6.2 Roosts.
    both_off = { "race_switch_to_winner" => false, "heal_outpace" => false }
    assert_equal("ROOST", pick(snapshot([zapdos(57, [chansey])], [target(0, 100)], {}),
                               both_off)[0]["move_id"])
  end

  # --- 0.6.5 the party x party damage matrix ------------------------------------
  #
  # Every test asserts the rule AND that its key off restores 0.6.4. The three keys
  # false is the control run; a matrix that is merely built and exported decides
  # nothing, which test_matrix_consumers_are_inert_without_a_matrix pins from the
  # other side.

  # Both consumers ship ON from 0.6.5, so a test that wants the 0.6.4 behaviour has to
  # name the keys. Every 0.6.5 test below asserts the rule AND this.
  ALL_065_OFF = { "sole_answer" => false, "setup_matrix" => false }

  # One side table. Each row is [slot, hp_pct, seat (nil on the bench), speed].
  def mx_side(rows)
    rows.map do |row|
      { "slot" => row[0], "index" => row[2], "species" => 100 + row[0],
        "hp_pct" => row[1], "alive" => row[1] > 0,
        "speed" => (row[3] || 100), "types" => [] }
    end
  end

  def mx_cell(out, incoming, faster = false, out_cat = "physical", in_cat = "physical")
    { "out" => out, "out_cat" => out_cat, "out_move" => "TACKLE",
      "in" => incoming, "in_cat" => in_cat, "in_move" => "TACKLE",
      "faster" => faster }
  end

  def matrix_snap(own, foe, cells)
    { "version" => 1, "own" => mx_side(own), "foe" => mx_side(foe), "cells" => cells }
  end

  def with_matrix(snap, matrix)
    snap["matrix"] = matrix
    snap
  end

  def verdict_snap(own_hp, out, incoming, faster = false)
    { "matrix" => matrix_snap([[0, own_hp, 1]], [[0, 100, 0]],
                              { "0:0" => mx_cell(out, incoming, faster) }) }
  end

  def test_matrix_verdict_reads_hits_from_current_hp
    # Two hits against five.
    assert_equal("W", PortableAI.matrix_verdict(verdict_snap(100, 50, 20), 0, 0))
    assert_equal("L", PortableAI.matrix_verdict(verdict_snap(100, 20, 50), 0, 0))
    # Eight hits each way is not a race, it is a stall.
    assert_equal("S", PortableAI.matrix_verdict(verdict_snap(100, 10, 10), 0, 0))
    # Equal counts fall to the speed order, and an unknown one stays unknown.
    assert_equal("W", PortableAI.matrix_verdict(verdict_snap(100, 50, 50, true), 0, 0))
    assert_equal("L", PortableAI.matrix_verdict(verdict_snap(100, 50, 50, false), 0, 0))
    # No cell, no claim.
    assert_nil(PortableAI.matrix_verdict(verdict_snap(100, 50, 20), 0, 1))
    assert_nil(PortableAI.matrix_verdict({}, 0, 0))
    # The verdict is derived from CURRENT HP, so the stall decays: at 20% the same
    # cell says the foe needs two hits and this body still needs eight.
    assert_equal("L", PortableAI.matrix_verdict(verdict_snap(20, 10, 10), 0, 0))
  end

  def test_matrix_stall_band_sits_below_the_race_cap
    # RACE_MAX_HITS is a CAP, so "both at the cap" would need 12.5% a hit on both
    # sides and the stall band would be all but unreachable.
    assert(PortableAI::MATRIX_STALL_HITS < PortableAI::RACE_MAX_HITS)
    assert(PortableAI::MATRIX_STALL_HITS > PortableAI::WALL_BREAK_MAX_HITS)
  end

  # The actor is drowsy, so every switch candidate has its reason to leave and the
  # question is only which body goes in. Slot 1 outscores slot 2 by 100 on the engine
  # base alone, which is 0.6.4's answer.
  def sole_answer_snap(cells, foe_rows = [[0, 100, 0], [1, 100, nil]])
    actions = [move(0, "STRENGTH", 0, 100, 20, {}),
               { "type" => "switch", "slot" => 1, "base_score" => 200,
                 "matchup_score" => 0 },
               { "type" => "switch", "slot" => 2, "base_score" => 100,
                 "matchup_score" => 0 }]
    a = actor(1, 100, actions, { "yawned" => true })
    snap = snapshot([a], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 1], [1, 100, nil], [2, 100, nil]],
                                  foe_rows, cells))
  end

  WINS = [50, 20]        # two hits against five
  LOSES = [20, 50]

  def mx_pair(pair)
    mx_cell(pair[0], pair[1])
  end

  # Slot 1 is the only body that beats their benched foe and it LOSES to the one in
  # front; slot 2 beats what is in front and answers nothing else.
  def exposed_cells(other_answers_the_field = true)
    { "0:0" => mx_pair(LOSES), "0:1" => mx_pair(LOSES),
      "1:0" => mx_pair(LOSES), "1:1" => mx_pair(WINS),
      "2:0" => mx_pair(other_answers_the_field ? WINS : LOSES),
      "2:1" => mx_pair(LOSES) }
  end

  def test_sole_answers_names_the_only_live_body_that_beats_each_foe
    snap = sole_answer_snap(exposed_cells)
    assert_equal([1], PortableAI.sole_answers(snap, 1))
    assert_equal([], PortableAI.sole_answers(snap, 1) - [1])
    # Slot 2 is the only answer to the foe in FRONT, which is a real sole answer and
    # is what matrix_answers says.
    assert_equal([2], PortableAI.matrix_answers(snap, 0))
    assert_equal([1], PortableAI.matrix_answers(snap, 1))
    # A dead foe is not a foe anything has to answer, and a dead body of ours is not
    # an answer: with slot 2 fainted, nothing answers the foe in front.
    dead = sole_answer_snap(exposed_cells, [[0, 100, 0], [1, 0, nil]])
    assert_equal([], PortableAI.sole_answers(dead, 1))
    dead["matrix"]["own"][2]["alive"] = false
    dead["matrix"]["own"][2]["hp_pct"] = 0
    assert_equal([], PortableAI.matrix_answers(dead, 0))
  end

  def test_the_only_answer_to_a_bench_foe_is_not_sent_into_a_foe_it_loses_to
    snap = sole_answer_snap(exposed_cells)
    result = pick(snap, {})[0]
    assert_equal("switch", result["type"])
    assert_equal(2, result["slot"])
    # 0.6.4 spends the only answer, because slot 1 simply scores higher.
    off = pick(snap, ALL_065_OFF)[0]
    assert_equal(1, off["slot"])
  end

  def test_sole_answer_is_silent_when_no_other_body_answers_the_active_foe
    # Nothing else beats what is in front, so spending the unique body is not a
    # choice the rule gets to second-guess.
    snap = sole_answer_snap(exposed_cells(false))
    result = pick(snap, {})[0]
    assert_equal(1, result["slot"])
    assert(!reasons_of(result).include?("sole_answer_exposed"))
    assert(!reasons_of(result).include?("sole_answer_reserved"))
  end

  # Both bodies are forced replacements and both beat the foe in front. One of them is
  # also the only answer to a foe still on their bench.
  def test_a_forced_replacement_prefers_the_body_with_least_unique_value
    actions = [{ "type" => "switch", "slot" => 1, "base_score" => 100,
                 "matchup_score" => 0, "forced" => true },
               { "type" => "switch", "slot" => 2, "base_score" => 80,
                 "matchup_score" => 0, "forced" => true }]
    a = actor(1, 0.0, actions, {})
    snap = snapshot([a], [target(0, 100)], {})
    cells = { "1:0" => mx_pair(WINS), "1:1" => mx_pair(WINS),
              "2:0" => mx_pair(WINS), "2:1" => mx_pair(LOSES) }
    with_matrix(snap, matrix_snap([[0, 0, nil], [1, 100, nil], [2, 100, nil]],
                                  [[0, 100, 0], [1, 100, nil]], cells))
    plan = PortableAI.plan(snap, {}, Random.new(7))
    assert_equal(2, plan["actions"][0]["slot"])
    # The charge is on the body being held back, not on the one that goes.
    held = plan["diagnostics"]["rankings"][0].find { |c| c["slot"] == 1 }
    assert_equal(-45, reason_value(held, "sole_answer_reserved"))
    assert_nil(reason_value(plan["diagnostics"]["rankings"][0].find { |c| c["slot"] == 2 },
                            "sole_answer_reserved"))
    # 0.6.4 ranks them by score alone and spends the body it will need later.
    assert_equal(1, pick(snap, ALL_065_OFF)[0]["slot"])
  end

  def test_sole_answer_in_doubles_takes_the_harsher_target
    actions = [move(0, "STRENGTH", 0, 100, 20, {}),
               { "type" => "switch", "slot" => 1, "base_score" => 200,
                 "matchup_score" => 0 },
               { "type" => "switch", "slot" => 2, "base_score" => 100,
                 "matchup_score" => 0 }]
    a = actor(1, 100, actions, { "yawned" => true })
    snap = snapshot([a], [target(0, 100), target(2, 100)], {})
    snap["format"] = "double"
    # Slot 1 beats the first foe and loses to the second, so on the harsher target it
    # is exposed rather than reserved.
    cells = { "0:0" => mx_pair(LOSES), "0:1" => mx_pair(LOSES), "0:2" => mx_pair(LOSES),
              "1:0" => mx_pair(WINS), "1:1" => mx_pair(LOSES), "1:2" => mx_pair(WINS),
              "2:0" => mx_pair(WINS), "2:1" => mx_pair(WINS), "2:2" => mx_pair(LOSES) }
    with_matrix(snap, matrix_snap([[0, 100, 1], [1, 100, nil], [2, 100, nil]],
                                  [[0, 100, 0], [1, 100, 2], [2, 100, nil]], cells))
    scored = PortableAI.plan(snap, {},
                             Random.new(7))["diagnostics"]["rankings"][0]
    one = scored.find { |c| c["type"] == "switch" && c["slot"] == 1 }
    assert_equal(-150, reason_value(one, "sole_answer_exposed"))
    assert_nil(reason_value(one, "sole_answer_reserved"))
  end

  def test_matrix_consumers_are_inert_without_a_matrix
    both = {}
    plain = snapshot([actor(1, 100, [move(0, "STRENGTH", 0, 100, 20, {}),
                                     { "type" => "switch", "slot" => 1,
                                       "base_score" => 200, "matchup_score" => 0 },
                                     move(1, "SWORDSDANCE", nil, 300, 0, {})],
                            { "yawned" => true })], [target(0, 100)], {})
    on = pick(plain, both)[0]
    off = pick(plain, {})[0]
    assert_equal(reasons_of(off), reasons_of(on))
    assert_equal(off["score"], on["score"])
  end

  # --- 0.6.5 the boost is worth what it flips -----------------------------------

  # Swords Dance (+2 Attack) against a foe in front the actor already beats, and two
  # on their bench it does not. base_score 300 keeps the setup move the winner either
  # way, so the assertions are about the value of the term and not about a tie.
  def setup_matrix_snap(cells, actor_extra = {}, foe_rows = nil)
    actions = [move(0, "SWORDSDANCE", nil, 300, 0, {}),
               move(1, "STRENGTH", 0, 100, 20, {})]
    a = actor(1, 100, actions, actor_extra)
    snap = snapshot([a], [target(0, 100)], {})
    rows = foe_rows || [[0, 100, 0], [1, 100, nil], [2, 100, nil]]
    with_matrix(snap, matrix_snap([[0, 100, 1]], rows, cells))
  end

  # 30 a hit becomes 60: two hits instead of four, inside the five the foe needs.
  # 20 into each bench body becomes 40: three hits instead of five, against four.
  def flipping_cells
    { "0:0" => mx_cell(30, 20), "0:1" => mx_cell(20, 25), "0:2" => mx_cell(20, 25) }
  end

  def test_setup_is_worth_the_cells_it_flips
    snap = setup_matrix_snap(flipping_cells)
    result = pick(snap, {})[0]
    assert_equal("SWORDSDANCE", result["move_id"])
    assert_equal(110, reason_value(result, "setup_flips"))
    off = pick(snap, ALL_065_OFF)[0]
    assert_equal(55, reason_value(off, "first_setup"))
    assert_nil(reason_value(off, "setup_flips"))
  end

  def test_a_boost_that_moves_no_number_anywhere_loses_the_flat_bonus
    # Swords Dance raises Attack and every one of these bodies attacks specially, so
    # the boost changes not one hit count on the board. The foe in front cannot
    # threaten the turn, so this is not the budget refusing -- it is the boost.
    cells = { "0:0" => mx_cell(30, 10, false, "special", "special"),
              "0:1" => mx_cell(30, 10, false, "special", "special"),
              "0:2" => mx_cell(30, 10, false, "special", "special") }
    snap = setup_matrix_snap(cells)
    result = pick(snap, {})[0]
    assert_equal(0, reason_value(result, "setup_no_flip"))
    assert_nil(reason_value(result, "setup_flips"))
    assert_equal(55, reason_value(pick(snap, ALL_065_OFF)[0], "first_setup"))
  end

  # The middle answer, and the probe is why it exists: a boost that flips no verdict
  # but still shortens a race the actor was already winning is not worthless. Read off
  # the 0.6.5 probe, where paying 0 here dropped Heracross's Swords Dance behind Close
  # Combat in front of a Shuckle it beats either way and broke
  # `an_unboosted_sweeper_still_sets_up`, a card that has held since 0.4.0.
  def test_a_boost_that_only_shortens_a_won_race_keeps_the_flat_bonus
    cells = { "0:0" => mx_cell(30, 10), "0:1" => mx_cell(30, 10),
              "0:2" => mx_cell(30, 10) }
    snap = setup_matrix_snap(cells)
    result = pick(snap, {})[0]
    assert_equal(55, reason_value(result, "first_setup"))
    assert_nil(reason_value(result, "setup_no_flip"))
    assert_nil(reason_value(result, "setup_flips"))
    # Which is 0.6.4 exactly.
    assert_equal(55, reason_value(pick(snap, ALL_065_OFF)[0], "first_setup"))
  end

  def test_setup_needs_the_budget_in_front
    # The foe removes this body in two and the boosted attack still needs three: there
    # is no turn to spend, whatever the boost would be worth against their bench.
    cells = { "0:0" => mx_cell(20, 60), "0:1" => mx_cell(20, 25),
              "0:2" => mx_cell(20, 25) }
    snap = setup_matrix_snap(cells)
    result = pick(snap, {})[0]
    assert_equal(0, reason_value(result, "setup_no_budget"))
    assert_nil(reason_value(result, "setup_flips"))
    assert_equal(55, reason_value(pick(snap, ALL_065_OFF)[0], "first_setup"))
  end

  # A TIE is not a refusal. Both battles this rule lost on the 0.6.5 tier run were a
  # boost declined at exactly this line -- the boosted attack needing the same number
  # of turns the foe needs, counting the setup turn -- where withholding the flat 55
  # handed the turn to an attack and lost a battle 0.6.4 won. The dangerous boards are
  # the four safety branches above; this test only refuses what it can see is
  # unaffordable.
  def test_a_tied_budget_is_not_a_refusal
    # The foe needs three (35 a hit into 100); boosted, the actor needs two, and the
    # setup turn makes three.
    cells = { "0:0" => mx_cell(25, 35), "0:1" => mx_cell(20, 25),
              "0:2" => mx_cell(20, 25) }
    snap = setup_matrix_snap(cells)
    result = pick(snap, {})[0]
    assert_nil(reason_value(result, "setup_no_budget"))
    # And with the turn affordable the flips are paid: the foe in front and both on
    # their bench stop beating this body.
    assert_equal(165, reason_value(result, "setup_flips"))
    assert_equal(55, reason_value(pick(snap, ALL_065_OFF)[0], "first_setup"))
  end

  def test_setup_transform_respects_category_and_speed
    special = mx_cell(40, 20, false, "special", "physical")
    # Swords Dance raises Attack; a special attacker's best hit is untouched by it.
    swords = PortableAI.matrix_transform_cell(special, { "atk" => 2 }, 100, 120, false)
    assert_equal(40, swords["out"])
    # Nasty Plot moves the same cell.
    plot = PortableAI.matrix_transform_cell(special, { "spa" => 2 }, 100, 120, false)
    assert_equal(80.0, plot["out"])
    # A defensive stage divides what comes in, by the incoming move's category.
    amnesia = PortableAI.matrix_transform_cell(special, { "spd" => 2 }, 100, 120, false)
    assert_equal(20, amnesia["in"])
    iron = PortableAI.matrix_transform_cell(special, { "def" => 2 }, 100, 120, false)
    assert_equal(10.0, iron["in"])
    # Dragon Dance turns a losing speed order into a winning one, and Trick Room
    # turns it back.
    dance = PortableAI.matrix_transform_cell(special, { "atk" => 1, "speed" => 1 },
                                            100, 120, false)
    assert_equal(true, dance["faster"])
    inverted = PortableAI.matrix_transform_cell(special, { "atk" => 1, "speed" => 1 },
                                                100, 120, true)
    assert_equal(false, inverted["faster"])
  end

  def test_setup_safety_branches_still_outrank_the_matrix_value
    # At 30% HP the boost is refused whatever it would flip: unsafe_setup is one of
    # the four branches that run before this arm is reached.
    snap = setup_matrix_snap(flipping_cells)
    snap["actors"][0]["hp_pct"] = 25
    result = PortableAI.plan(snap, {},
                             Random.new(7))["diagnostics"]["rankings"][0]
    dance = result.find { |c| c["move_id"] == "SWORDSDANCE" }
    assert_equal(-240, reason_value(dance, "unsafe_setup"))
    assert_nil(reason_value(dance, "setup_flips"))
    assert_nil(reason_value(dance, "first_setup"))
  end

  def test_every_setup_move_has_a_stage_row
    missing = []
    PortableAI::Effects::TABLE.each do |id, tags|
      next if !tags.include?("setup")
      missing << id if PortableAI::Effects.setup_stages(id).nil?
    end
    assert_equal([], missing.sort,
                 "a setup move with no stage row falls back to the flat 55 in silence")
  end

  # --- 0.6.6 the foe's declared intent ---------------------------------------------
  #
  # The adapter exports predicted_incoming_damage_pct only when it read the foe's
  # committed move (the oracle arm today). The core then prices the entry hit and
  # the "you die whatever you click" rules on THAT hit; absent, nothing changes.

  def test_a_declared_status_move_makes_the_lethal_threat_uncertain
    foe = target(0, 100)
    actions = [move(0, "RECOVER", nil, 100, 0, {}), move(1, "BODYSLAM", 0, 100, 20, {})]
    # Worst case and certain case both kill the slower healer; the foe has declared
    # a move that does nothing to it.
    healer = actor(1, 12, actions, { "incoming_damage_pct" => 60,
                                     "certain_incoming_damage_pct" => 60,
                                     "predicted_incoming_damage_pct" => 0,
                                     "faster" => false })
    result = pick(snapshot([healer], [foe], {}), {})[0]
    assert_equal("RECOVER", result["move_id"])
    assert_equal(false, reasons_of(result).include?("heal_cannot_resolve"))
  end

  def test_a_declared_near_certain_hit_refuses_the_heal_strict_threat_missed
    foe = target(0, 100)
    actions = [move(0, "RECOVER", nil, 100, 0, {}), move(1, "BODYSLAM", 0, 100, 20, {})]
    # The Xatu turn: a 95% Air Slash the strict figure reads as 0%. Declared, its
    # minimum roll discounted by its hit chance still clears 28%.
    healer = actor(1, 28, actions, { "incoming_damage_pct" => 48,
                                     "certain_incoming_damage_pct" => 0,
                                     "predicted_incoming_damage_pct" => 48,
                                     "predicted_incoming_accuracy" => 95,
                                     "faster" => false })
    result = pick(snapshot([healer], [foe], {}), {})[0]
    assert_equal("BODYSLAM", result["move_id"])
    # An inaccurate declared hit has to overkill before it counts: 70% of 40 on the
    # minimum roll is 23.8, short of 28.
    gamble = actor(1, 28, actions, { "incoming_damage_pct" => 48,
                                     "certain_incoming_damage_pct" => 0,
                                     "predicted_incoming_damage_pct" => 40,
                                     "predicted_incoming_accuracy" => 70,
                                     "faster" => false })
    assert_equal("RECOVER", pick(snapshot([gamble], [foe], {}), {})[0]["move_id"])
  end

  def test_the_entry_hit_is_the_declared_one_and_the_race_after_it_is_the_worst
    foe = target(0, 100)
    # Worst case the foe removes the candidate on entry (Megahorn); it has declared
    # Earthquake, which the candidate resists.
    sceptile = { "type" => "switch", "slot" => 1, "base_score" => 100, "matchup_score" => 0,
                 "candidate_hp_pct" => 100, "entry_damage_pct" => 0,
                 "incoming_damage_pct" => 120, "predicted_incoming_damage_pct" => 20,
                 "outgoing_damage_pct" => 60, "faster" => true }
    snap = snapshot([actor(1, 60, [move(0, "STRENGTH", 0, 100, 20, {})] + [sceptile],
                           { "yawned" => true })], [foe], {})
    result = pick(snap, {})[0]
    assert_equal("switch", result["type"])
    assert_equal(false, reasons_of(result).include?("dies_on_entry"))
    assert_in_delta((25.0 - 20) * 1.28, reason_value(result, "entry_incoming_damage"), 0.01)
    # Without the declared hit the same candidate is a corpse.
    plain = sceptile.reject { |k, _v| k == "predicted_incoming_damage_pct" }
    ranked = PortableAI.plan(snapshot([actor(1, 60, [move(0, "STRENGTH", 0, 100, 20, {})] +
                                              [plain], { "yawned" => true })], [foe], {}),
                             {}, Random.new(7))["diagnostics"]["rankings"][0]
    blind = ranked.find { |c| c["type"] == "switch" }
    assert_equal(true, reasons_of(blind).include?("dies_on_entry"))
    # The race after entry still runs on the worst hit: 80 left against 120 a hit is
    # one more, so the candidate needs its two hits to land first and cannot.
    race = PortableAI.candidate_race(sceptile, foe)
    assert_equal(2, race["theirs"])
    assert_equal(false, race["winning"])
  end

  # --- 0.6.6 a wall that cannot be hurt has no reason to leave ---------------------

  def steelix_snap(incoming, moves, config = {})
    foe = target(0, 100)
    bench = { "type" => "switch", "slot" => 1, "base_score" => 100, "matchup_score" => 0,
              "candidate_hp_pct" => 100, "entry_damage_pct" => 0,
              "incoming_damage_pct" => 20, "outgoing_damage_pct" => 40, "faster" => true }
    a = actor(1, 100, moves + [bench],
              { "no_effective_move" => true, "best_damage_pct" => 0,
                "incoming_damage_pct" => incoming })
    pick(snapshot([a], [foe], {}), config)[0]
  end

  def test_a_wall_with_a_status_move_stays_when_the_foe_needs_four_hits
    toxic = move(0, "TOXIC", 0, 120, 0, {})
    eq = move(1, "EARTHQUAKE", 0, 0, 0, { "damaging" => true, "immune" => true,
                                          "effectiveness" => 0 })
    assert_equal("TOXIC", steelix_snap(18, [toxic, eq])["move_id"])
    # The foe three-shots it: the same two reasons open the gate as before.
    assert_equal("switch", steelix_snap(40, [toxic, eq])["type"])
    # Nothing but blanked attacks: leave, however safe.
    assert_equal("switch", steelix_snap(18, [eq])["type"])
    # Alakazam in front of a Toxic Umbreon: Calm Mind, Recover and Substitute work
    # on nobody but itself, so it is not a wall with a job, it is a body doing
    # nothing. Leaves (the 0.6.3 corpus card).
    kazam = [move(0, "CALMMIND", nil, 187, 0, {}), move(2, "RECOVER", nil, 100, 0, {}),
             move(3, "SUBSTITUTE", nil, 112, 0, {})]
    assert_equal("switch", steelix_snap(0, kazam + [eq])["type"])
    # Stealth Rock already at its cap is not a job either.
    capped = move(0, "STEALTHROCK", nil, 140, 0, { "existing_layers" => 1, "max_layers" => 1 })
    assert_equal("switch", steelix_snap(18, [capped, eq])["type"])
    fresh = move(0, "STEALTHROCK", nil, 140, 0, { "existing_layers" => 0, "max_layers" => 1 })
    assert_equal("STEALTHROCK", steelix_snap(18, [fresh, eq])["move_id"])
    # Key off is 0.6.5.
    assert_equal("switch", steelix_snap(18, [toxic, eq],
                                        { "no_hit_needs_threat" => false })["type"])
  end

  # --- 0.6.7 a move the actor does not live to click ------------------------------

  # The Sceptile turn (gen5ru_a team3_vs_team4 104729 t10): slower, 100%, a declared
  # Acrobatics of 198%; its own Acrobatics kills the foe at 88% and never lands.
  def sceptile_snap(extra_actor = {}, extra_moves = [])
    foe = target(0, 88)
    acro = move(0, "ACROBATICS", 0, 260, 123, { "effectiveness" => 2 })
    rock = move(1, "ROCKSLIDE", 0, 189, 28, {})
    uxie = { "type" => "switch", "slot" => 5, "base_score" => 55, "matchup_score" => 64,
             "candidate_hp_pct" => 100, "entry_damage_pct" => 0,
             "incoming_damage_pct" => 44, "predicted_incoming_damage_pct" => 44,
             "outgoing_damage_pct" => 51, "faster" => false }
    a = actor(1, 100, [acro, rock] + extra_moves + [uxie],
              { "incoming_damage_pct" => 198, "certain_incoming_damage_pct" => 198,
                "predicted_incoming_damage_pct" => 198,
                "predicted_incoming_accuracy" => 100,
                "faster" => false }.merge(extra_actor))
    snapshot([a], [foe], {})
  end

  def rankings(snap, config = {})
    PortableAI.plan(snap, config, Random.new(7))["diagnostics"]["rankings"][0]
  end

  def test_a_slower_actor_certain_to_die_does_not_credit_the_hit_it_never_lands
    ranked = rankings(sceptile_snap)
    assert_equal("switch", ranked[0]["type"])
    acro = ranked.find { |c| c["move_id"] == "ACROBATICS" }
    # ko_never_lands already stripped the kill call; what was left (260 + 80 + 70)
    # is scaled to a quarter.
    assert_equal(true, reasons_of(acro).include?("ko_never_lands"))
    assert_in_delta(410 * 0.25, acro["score"], 0.01)
    assert_in_delta(410 * -0.75, reason_value(acro, "dead_before_moving"), 0.01)
    # Key off is 0.6.6: the attack wins at 410 over the switch at 234.
    assert_equal("ACROBATICS", pick(sceptile_snap, { "dead_before_moving" => false })[0]["move_id"])
  end

  def test_the_order_among_the_moves_is_unchanged_and_a_priority_move_lands
    ranked = rankings(sceptile_snap)
    moves = ranked.select { |c| c["type"] == "move" }.map { |c| c["move_id"] }
    assert_equal(%w[ACROBATICS ROCKSLIDE], moves)
    # A chip with priority is clicked before death, so it keeps its whole score and
    # now outranks the attack that never happens.
    quick = move(2, "QUICKATTACK", 0, 100, 12, { "priority" => 1 })
    ranked = rankings(sceptile_snap({}, [quick]))
    moves = ranked.select { |c| c["type"] == "move" }
    assert_equal("QUICKATTACK", moves[0]["move_id"])
    assert_equal(false, reasons_of(moves[0]).include?("dead_before_moving"))
  end

  def test_the_rule_is_inert_when_faster_or_when_the_death_is_not_certain
    # Faster: the attack lands first and kills.
    fast = rankings(sceptile_snap({ "faster" => true }))
    assert_equal("ACROBATICS", fast[0]["move_id"])
    assert_equal(false, reasons_of(fast[0]).include?("dead_before_moving"))
    # Speed unknown is not slower.
    unknown = rankings(sceptile_snap({ "faster" => nil }))
    assert_equal(false, reasons_of(unknown.find { |c| c["move_id"] == "ACROBATICS" })
                          .include?("dead_before_moving"))
    # The foe declared a move that does not kill: nothing is scaled.
    alive = rankings(sceptile_snap({ "predicted_incoming_damage_pct" => 60 }))
    assert_equal("ACROBATICS", alive[0]["move_id"])
    assert_equal(false, reasons_of(alive[0]).include?("dead_before_moving"))
  end

  def test_a_trapped_or_low_actor_keeps_its_best_move
    # Trapped: the switches are rejected, the moves keep their order, Acrobatics
    # is still the click.
    trapped = pick(sceptile_snap({ "trapped" => true }), {})[0]
    assert_equal("ACROBATICS", trapped["move_id"])
    # Below the healthy pivot line the lethal threat is no reason to leave, the gate
    # stays shut, and the scaled attack is still what gets clicked.
    low = pick(sceptile_snap({ "hp_pct" => 30 }), {})[0]
    assert_equal("ACROBATICS", low["move_id"])
    assert_equal(true, reasons_of(low).include?("dead_before_moving"))
  end
  # ---------------------------------------------------------------------------
  # 0.7.0. THE SEARCH PLANNER. One ply over the joint grid, off by default.

  # Our active trades evenly with theirs and is faster; their bench crushes it; our
  # bench beats both of their bodies. The position the party matrix was built to see.
  def search_snap(own_actions)
    cells = {
      "0:0" => mx_cell(40, 40, true),
      "0:1" => mx_cell(5, 60, false),
      "1:0" => mx_cell(30, 15, true),
      "1:1" => mx_cell(35, 20, true)
    }
    snap = snapshot([actor(0, 100, own_actions, {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0], [1, 100, nil]],
                                  [[0, 100, 0], [1, 100, nil]], cells))
  end

  def search_pick(snap, config = {})
    plan = PortableAI::Search.plan(snap, config, Random.new(7))
    plan && plan["actions"][0]
  end

  # 0.7.9. Every damage number is a MAX roll; a hit that cannot kill lands, on
  # average over the search's roll branches, at this fraction of it (the average
  # roll, lifted by the crit branch). The board-arithmetic tests below are pinned
  # against it wherever a hit stays short of a kill.
  ROLL = PortableAI::Search::ROLL_AVERAGE *
         (1.0 + (PortableAI::Search::CRIT_MULT - 1.0) * PortableAI::Search::CRIT_RATE)

  # The board-arithmetic tests below pin the one-ply numbers; the depth is the
  # subject of its own tests further down.
  ONE_PLY = { "search_depth" => 1, "search_foe_mix" => 0 }

  def test_search_planner_declines_what_it_cannot_see
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })]
    # No matrix: nothing to project on to.
    assert_nil(PortableAI::Search.plan(
      snapshot([actor(0, 100, actions, {})], [target(0, 100)], {}), {}, nil))
    # Doubles: this version reasons about one pair.
    doubles = search_snap(actions)
    doubles["format"] = "double"
    assert_nil(PortableAI::Search.plan(doubles, {}, nil))
    # A fainted actor holds no matrix seat, so a forced replacement finds no board.
    # That is how the adapter's replacement path stays with the rule engine without
    # a special case for it.
    fainted = search_snap(actions)
    fainted["actors"][0]["index"] = 4
    assert_nil(PortableAI::Search.plan(fainted, {}, nil))
  end

  def test_search_planner_scores_every_action_against_every_foe_reply
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
               { "type" => "switch", "slot" => 1, "base_score" => 100,
                 "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }]
    ranked = PortableAI::Search.plan(search_snap(actions), ONE_PLY, nil)["diagnostics"]["rankings"][0]
    attack = ranked.find { |c| c["type"] == "move" }
    switch = ranked.find { |c| c["type"] == "switch" }
    # Stay, and one switch per live body on their bench.
    assert_equal(2, reason_value(attack, "search_foe_options"))
    assert_equal(2, attack["search_row"].length)
    # Within one ply their switch cannot punish an attack -- it only forgoes their
    # hit -- so the attack's best case is the switch column and its worst the stay.
    # (Through 0.7.3 a +/-25 verdict on the pair left standing made the switch the
    # pick here; the leaf is HP alone now. Where maximin departs from greedy is the
    # foe-switch column pricing each move on its own -- see
    # test_search_prefers_the_move_their_bench_cannot_wall -- and the second ply.)
    assert_equal(true, reason_value(attack, "search_best_case") >
                       reason_value(attack, "search_worst_case"))
    assert_equal(0.0, attack["score"])
    # The hit the switch-in eats, nothing back -- at the average roll (0.7.9).
    assert_in_delta(-15.0 * ROLL, switch["score"], 1e-9)
    assert_equal("move", ranked[0]["type"])
  end

  def test_search_planner_ranks_a_kill_by_the_body_it_removes
    # Their last body at 30%, so the only foe option is to stay and take it. Removing
    # it ends the battle, which sits above every standing board.
    cells = { "0:0" => mx_cell(40, 40, true) }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    ember = move(1, "EMBER", 0, 100, 10, { "accuracy" => 100 })
    snap = snapshot([actor(0, 100, [tackle, ember], {})], [target(0, 30)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 30, 0]], cells))
    chosen = search_pick(snap, ONE_PLY)
    assert_equal("TACKLE", chosen["move_id"])
    assert_equal(PortableAI::Search::BATTLE_OVER, chosen["score"])
    assert_equal(1, reason_value(chosen, "search_foe_options"))
    # With a bench behind it the kill is worth what it removes -- the 30 HP and the
    # body -- as in the original's evaluate, not a flat value that dwarfs the board.
    cells["0:1"] = mx_cell(40, 40, true)
    snap = snapshot([actor(0, 100, [tackle, ember], {})], [target(0, 30)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 30, 0], [1, 100, nil]], cells))
    ranked = PortableAI::Search.plan(snap, ONE_PLY, nil)["diagnostics"]["rankings"][0]
    kill = ranked.find { |c| c["move_id"] == "TACKLE" }
    chip = ranked.find { |c| c["move_id"] == "EMBER" }
    # Kill, foe stays: we 130, they 130 (the bench body). No pair stands, no verdict.
    assert_equal(0.0, kill["search_row"][0])
    # Chip, foe stays: we 100 - 40 + 30 = 90, they 20 + 30 + 130 = 180 -- at the
    # max roll; both hits fall short of a kill, so both land at the average (0.7.9).
    assert_in_delta(-90.0 + (40.0 - 10.0) * (1.0 - ROLL), chip["search_row"][0], 1e-9)
    assert_equal("TACKLE", ranked[0]["move_id"])
  end

  def test_search_branches_a_miss_instead_of_scaling_the_damage
    snap = search_snap([])
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    # A switch-in eats the hit in full on the way in -- candidate_race's convention --
    # on top of whatever hazards already took (entry_damage_pct).
    entry = { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100,
              "entry_damage_pct" => 0 }
    assert_equal(1, PortableAI::Search.project(snap, board, entry, stay, true)["own_slot"])
    assert_equal(85.0, PortableAI::Search.project(snap, board, entry, stay, true)["own_hp"])
    hazarded = { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100,
                 "entry_damage_pct" => 20 }
    assert_equal(65.0, PortableAI::Search.project(snap, board, hazarded, stay, true)["own_hp"])
    # Accuracy is a branch, not a multiplier: the move lands in full or not at all.
    half = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 50 })
    assert_equal(60.0, PortableAI::Search.project(snap, board, half, stay, true, true)["foe_hp"])
    assert_equal(100.0, PortableAI::Search.project(snap, board, half, stay, true, false)["foe_hp"])
    hit = PortableAI::Search.leaf(snap, PortableAI::Search.project(snap, board, half, stay, true, true))
    miss = PortableAI::Search.leaf(snap, PortableAI::Search.project(snap, board, half, stay, true, false))
    # `project` alone lands the raw number; `payoff` averages the roll branches on
    # both sides (0.7.9). Their 40 on us is short of a kill in every branch, so it
    # averages to 40 x ROLL in both; ours does the same in the hit branch only.
    assert_in_delta((hit + miss) / 2.0 + 20.0 * (1.0 - ROLL),
                    PortableAI::Search.payoff(snap, board, half, stay), 1e-9)
    # The case that made the branch necessary: a 70% move that kills outright is a
    # 70% chance of the kill, not a certain 70% hit that leaves the foe standing --
    # and a 90% move that kills by a hair is not a 90% hit that does not.
    cells = { "0:0" => mx_cell(40, 40, true) }
    snap = snapshot([actor(0, 100, [], {})], [target(0, 40)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 40, 0]], cells))
    board = PortableAI::Search.opening_board(snap)
    blast = move(0, "FOCUSBLAST", 0, 100, 100, { "accuracy" => 70 })
    edge = move(1, "STONEEDGE", 0, 100, 45, { "accuracy" => 90 })
    over = PortableAI::Search::BATTLE_OVER
    missed = PortableAI::Search.leaf(snap, PortableAI::Search.project(snap, board, blast, stay, true, false)) +
             40.0 * (1.0 - ROLL)
    # 100 max on 40 HP kills on the lowest roll, so the 70% is the whole story.
    assert_in_delta(0.7 * over + 0.3 * missed,
                    PortableAI::Search.payoff(snap, board, blast, stay), 1e-9)
    # 45 max on 40 HP kills on 12 of 16 rolls (85..88 fall short): the 90% move is
    # a 90% x (15/16 x 12/16 + 1/16 crit) = 68.9% kill, not a 90% one -- the 0.7.9
    # correction, the original's should_branch_on_damage arithmetic. The non-kill
    # branch lands the mean of the four short rolls, 0.865 x 45.
    p_kill = (1.0 - PortableAI::Search::CRIT_RATE) * 12 / 16.0 + PortableAI::Search::CRIT_RATE
    short = missed + 45.0 * 0.865
    assert_in_delta(0.9 * (p_kill * over + (1.0 - p_kill) * short) + 0.1 * missed,
                    PortableAI::Search.payoff(snap, board, edge, stay), 1e-9)
    assert_equal([[1.0, p_kill], [0.865, 1.0 - p_kill]],
                 PortableAI::Search.roll_outcomes(45.0, 40.0, true).map { |o| [(o[0] * 1e6).round / 1e6, o[1]] })
    assert_equal([[1.0, 1.0]], PortableAI::Search.roll_outcomes(100.0, 40.0, true))
    assert_equal([[PortableAI::Search::ROLL_AVERAGE, 1.0]], PortableAI::Search.roll_outcomes(45.0, 40.0, false))
    # Moving first and killing means taking nothing back.
    lethal = move(0, "TACKLE", 0, 100, 100, { "accuracy" => 100 })
    first = PortableAI::Search.project(snap, board, lethal, stay, true)
    assert_equal(0.0, first["foe_hp"])
    assert_equal(100.0, first["own_hp"])
    # Moving second, the same kill still costs the hit that came before it.
    second = PortableAI::Search.project(snap, board, lethal, stay, false)
    assert_equal(0.0, second["foe_hp"])
    assert_equal(60.0, second["own_hp"])
  end

  def test_search_planner_returns_the_shape_the_adapter_reads
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })]
    plan = PortableAI::Search.plan(search_snap(actions), {}, nil)
    assert_equal(PortableAI::VERSION, plan["diagnostics"]["version"])
    assert_equal("search", plan["diagnostics"]["planner"])
    # The same record the rule planner leaves, because the projection reads it back.
    assert_equal(true, plan["memory_updates"].is_a?(Hash))
    protect = PortableAI::Search.plan(search_snap(
      [move(0, "PROTECT", 0, 100, 0, { "actor_index" => 0, "accuracy" => 0 })]), {}, nil)
    assert_equal("protect", protect["memory_updates"]["0"]["increment"])
    assert_equal(1, plan["actions"].length)
    # rankings is [actor][candidates] with a score on each, which is what
    # candidate_trace and the readout tooling walk.
    assert_equal(1, plan["diagnostics"]["rankings"].length)
    assert_equal(actions.length, plan["diagnostics"]["rankings"][0].length)
    assert_equal(false, plan["diagnostics"]["rankings"][0][0]["score"].nil?)
    assert_equal([actions.length], plan["diagnostics"]["candidate_counts"])
  end

  def test_search_planner_is_off_by_default_and_leaves_the_rule_engine_alone
    assert_equal(false, PortableAI::Model::DEFAULT_CONFIG["search_planner"])
    # The rule planner never consults it: same snapshot, same answer as always.
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
               { "type" => "switch", "slot" => 1, "base_score" => 100,
                 "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }]
    snap = search_snap(actions)
    assert_equal("move", pick(snap, {})[0]["type"])
    assert_equal(nil, PortableAI.plan(snap, {}, Random.new(7))["diagnostics"]["planner"])
  end

  def test_a_foe_switch_in_stands_on_its_own_hp_not_the_body_it_replaced
    # Their active is nearly dead and their bench is fresh. Reading the bench body at
    # the active's 6% made every foe switch look like a free kill, which scored a kill
    # and made maximin choose between fictions. It was the first version's worst bug.
    cells = { "0:0" => mx_cell(40, 40, true), "0:1" => mx_cell(40, 40, true) }
    snap = snapshot([actor(0, 100, [], {})], [target(0, 6)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 6, 0], [1, 100, nil]], cells))
    board = PortableAI::Search.opening_board(snap)
    assert_equal(6.0, board["foe_hp"])
    after = PortableAI::Search.project(snap, board,
                                       move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
                                       { "kind" => "switch", "slot" => 1 }, true)
    assert_equal(1, after["foe_slot"])
    # 100 for the fresh body, minus our hit that lands on it -- not 6 minus the hit.
    assert_equal(60.0, after["foe_hp"])
    # Party-wide: we 100 + 30; they (6 + 30) + (60 + 30). Nothing for the pair itself
    # (0.7.4: no verdict term).
    assert_equal(130.0 - 126.0, PortableAI::Search.leaf(snap, after))
  end

  def test_the_on_field_pair_is_priced_from_the_live_view_not_the_cell
    # The cell says the foe hits for 60; the actor view says 24, because the foe is
    # Choice-locked into a weak move and the cells carry no Choice lock by design
    # (matrix.rb). Reading the cell made a healthy body score every move as a certain
    # death and flee; the live number is what every rule in core.rb reads.
    cells = { "0:0" => mx_cell(40, 60, true), "1:0" => mx_cell(30, 60, true) }
    acts = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })]
    snap = snapshot([actor(0, 100, acts, { "incoming_damage_pct" => 24, "faster" => false })],
                    [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0], [1, 100, nil]], [[0, 100, 0]], cells))
    board = PortableAI::Search.opening_board(snap)
    assert_equal(24.0, board["live_incoming"])
    stay = { "kind" => "stay" }
    # The actor view also owns the speed order: live_faster false beats the cell's true.
    assert_equal(false, PortableAI::Search.moves_first(snap, board, acts[0], stay))
    assert_equal(76.0, PortableAI::Search.project(snap, board, acts[0], stay, false)["own_hp"])
    # A body that switches in is priced by its own estimate when the adapter built one
    # (Intimidate-aware, every foe move, a real roll) ...
    entry = { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100,
              "entry_damage_pct" => 0, "incoming_damage_pct" => 33 }
    assert_equal(67.0, PortableAI::Search.project(snap, board, entry, stay, true)["own_hp"])
    # ... and by the cell only when nothing else priced the pair.
    entry.delete("incoming_damage_pct")
    assert_equal(40.0, PortableAI::Search.project(snap, board, entry, stay, true)["own_hp"])
  end

  def test_search_leaf_is_party_wide_so_a_switch_pays_for_the_hit_it_eats
    # An even trade on the field, a bench body that wins its pair. 0.7.0 switched here
    # every time: the verdict outranked any amount of HP, so the hit eaten on entry
    # was free. HP is the currency now, and the 20 the switch-in takes is 20 more than
    # attacking costs on the party sum.
    cells = { "0:0" => mx_cell(40, 40, true), "1:0" => mx_cell(50, 20, true) }
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
               { "type" => "switch", "slot" => 1, "base_score" => 100,
                 "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }]
    snap = snapshot([actor(0, 100, actions, {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0], [1, 100, nil]], [[0, 100, 0]], cells))
    ranked = PortableAI::Search.plan(snap, ONE_PLY, nil)["diagnostics"]["rankings"][0]
    attack = ranked.find { |c| c["type"] == "move" }
    switch = ranked.find { |c| c["type"] == "switch" }
    # Attack: we (60 + 30) + (100 + 30), they 60 + 30, +130. Switch: we (100 + 30) +
    # (80 + 30), they 100 + 30, +110. Twenty apart: the hit the switch-in ate.
    assert_equal(130.0, attack["score"])
    assert_in_delta(110.0 + 20.0 * (1.0 - ROLL), switch["score"], 1e-9)
    assert_equal("move", ranked[0]["type"])
    # And a body of ours going down costs that body, not the battle, while a bench
    # stands behind it.
    board = PortableAI::Search.opening_board(snap)
    dead = PortableAI::Search.project(snap, board,
                                      move(0, "TACKLE", 0, 100, 0, { "accuracy" => 100 }),
                                      { "kind" => "stay" }, true)
    dead["own_hp"] = 0.0
    dead["own_hps"][0] = 0.0
    assert_equal(130.0 - 130.0, PortableAI::Search.leaf(snap, dead))
    alone = with_matrix(snapshot([actor(0, 100, [], {})], [target(0, 100)], {}),
                        matrix_snap([[0, 100, 0]], [[0, 100, 0]], cells))
    gone = PortableAI::Search.opening_board(alone)
    gone["own_hp"] = 0.0
    gone["own_hps"][0] = 0.0
    assert_equal(-PortableAI::Search::BATTLE_OVER, PortableAI::Search.leaf(alone, gone))
  end

  def test_search_offers_no_foe_switch_column_when_the_foe_is_trapped
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })]
    free = search_snap(actions)
    assert_equal(["stay", "switch:1"],
                 PortableAI::Search.plan(free, {}, nil)["diagnostics"]["foe_options"])
    trapped = search_snap(actions)
    trapped["targets"][0]["trapped"] = true
    assert_equal(["stay"],
                 PortableAI::Search.plan(trapped, {}, nil)["diagnostics"]["foe_options"])
    assert_equal(1, reason_value(search_pick(trapped), "search_foe_options"))
  end

  # 0.7.2. WHAT A TURN CHANGES BESIDES HP, in the original's evaluate terms.

  def one_v_one(own_hp, foe_hp, cell, actor_extra = {}, target_extra = {})
    snap = snapshot([actor(0, own_hp, [], actor_extra)], [target(0, foe_hp)], {})
    target_extra.each { |k, v| snap["targets"][0][k] = v }
    with_matrix(snap, matrix_snap([[0, own_hp, 0, 100]], [[0, foe_hp, 0, 90]],
                                  { "0:0" => cell }))
  end

  def test_search_every_self_drop_move_has_a_stage_row
    PortableAI::Effects::TABLE.each do |id, tags|
      next if !tags.include?("self_drop")
      assert_not_nil(PortableAI::Effects.self_drop_stages(id), "no SELF_DROP_STAGES row for #{id}")
    end
  end

  def test_search_projects_a_boost_as_stages_the_leaf_reads
    # Even trade, we are slower. Dragon Dance costs the hit we take and the leaf pays
    # the original's 30 a stage for it.
    snap = one_v_one(100, 100, mx_cell(40, 40, false))
    board = PortableAI::Search.opening_board(snap)
    assert_equal({}, board["own_stages"])
    stay = { "kind" => "stay" }
    dd = move(0, "DRAGONDANCE", 0, 100, 0, { "accuracy" => 0 })
    after = PortableAI::Search.project(snap, board, dd, stay, false)
    assert_equal({ "atk" => 1, "speed" => 1 }, after["own_stages"])
    assert_equal(60.0, after["own_hp"])
    # Points: (60 + 30) - (100 + 30) = -40, +60 for two stages at multiplier 1.0.
    assert_equal(-40.0 + 60.0, PortableAI::Search.leaf(snap, after))
    # The stages ride on the body: a switch leaves them behind.
    boosted = PortableAI::Search.opening_board(snap)
    boosted["own_stages"] = { "atk" => 2 }
    snap["matrix"]["own"] << { "slot" => 1, "index" => nil, "hp_pct" => 100, "alive" => true, "speed" => 80 }
    snap["matrix"]["cells"]["1:0"] = mx_cell(30, 30, false)
    entry = { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }
    assert_equal({}, PortableAI::Search.project(snap, boosted, entry, stay, true)["own_stages"])
    # Belly Drum: half the HP for +6, and nothing at all from half or below.
    drum = move(0, "BELLYDRUM", 0, 100, 0, { "accuracy" => 0 })
    full = PortableAI::Search.project(snap, PortableAI::Search.opening_board(snap), drum, stay, true)
    assert_equal({ "atk" => 6 }, full["own_stages"])
    assert_equal(10.0, full["own_hp"])
    low = PortableAI::Search.opening_board(one_v_one(50, 100, mx_cell(40, 40, false)))
    assert_equal({}, PortableAI::Search.project(snap, low, drum, stay, true)["own_stages"])
    # The existing stages decode from the engine's array (PBStats order).
    carried = one_v_one(100, 100, mx_cell(40, 40, false), { "stages" => [0, 2, 0, 1, 0, 0, 0, 0] })
    assert_equal({ "atk" => 2, "speed" => 1 },
                 PortableAI::Search.opening_board(carried)["own_stages"])
  end

  def test_search_projects_a_heal_in_speed_order
    snap = one_v_one(40, 100, mx_cell(40, 40, false))
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    recover = move(0, "RECOVER", 0, 100, 0, { "accuracy" => 0 })
    # Slower: take 40 to 0 and never heal. Faster: heal to 90, then take 40.
    assert_equal(0.0, PortableAI::Search.project(snap, board, recover, stay, false)["own_hp"])
    assert_equal(50.0, PortableAI::Search.project(snap, board, recover, stay, true)["own_hp"])
    rest = move(0, "REST", 0, 100, 0, { "accuracy" => 0 })
    after = PortableAI::Search.project(snap, board, rest, stay, true)
    assert_equal(60.0, after["own_hp"])
    assert_equal(-25.0, after["own_status_points"])
  end

  def test_search_projects_protect_and_substitute
    snap = one_v_one(100, 100, mx_cell(40, 40, true))
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    protect = move(0, "PROTECT", 0, 100, 0, { "accuracy" => 0 })
    assert_equal(100.0, PortableAI::Search.project(snap, board, protect, stay, true)["own_hp"])
    # A repeat, by the memory counter, fails and the hit lands.
    repeated = PortableAI::Search.opening_board(snap)
    repeated["protect_repeats"] = 1
    assert_equal(60.0, PortableAI::Search.project(snap, repeated, protect, stay, true)["own_hp"])
    # Substitute costs a quarter, absorbs the hit, and breaks on one this size.
    sub = move(0, "SUBSTITUTE", 0, 100, 0, { "accuracy" => 0 })
    after = PortableAI::Search.project(snap, board, sub, stay, true)
    assert_equal(75.0, after["own_hp"])
    assert_equal(false, after["substitute"])
    # A hit under its HP leaves it standing, and standing it is worth 75 in the leaf.
    chip = one_v_one(100, 100, mx_cell(40, 10, true), { "incoming_damage_pct" => 10 })
    stood = PortableAI::Search.project(chip, PortableAI::Search.opening_board(chip), sub, stay, true)
    assert_equal(75.0, stood["own_hp"])
    assert_equal(true, stood["substitute"])
    bare = PortableAI::Search.leaf(chip, stood)
    stood["substitute"] = false
    assert_equal(75.0, bare - PortableAI::Search.leaf(chip, stood))
    # Made second, it goes up after the hit.
    late = PortableAI::Search.project(snap, board, sub, stay, false)
    assert_equal(35.0, late["own_hp"])
    assert_equal(true, late["substitute"])
  end

  def test_search_projects_a_status_at_the_exported_chance
    snap = one_v_one(100, 100, mx_cell(40, 40, true), {}, { "physical_attacker" => true })
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    toxic = move(0, "TOXIC", 0, 100, 0, { "accuracy" => 90, "effect_kind" => "poison",
                                        "effect_chance" => 100 })
    assert_equal(30.0, PortableAI::Search.project(snap, board, toxic, stay, true)["foe_status_points"])
    # The engine said it cannot land: nothing.
    blocked = move(0, "TOXIC", 0, 100, 0, { "accuracy" => 90, "effect_kind" => "poison",
                                          "effect_chance" => 0 })
    assert_equal(0.0, PortableAI::Search.project(snap, board, blocked, stay, true)["foe_status_points"])
    # A secondary at its rate; a burn on a special attacker at half.
    scald = move(1, "SCALD", 0, 100, 30, { "accuracy" => 100, "effect_kind" => "burn",
                                         "effect_chance" => 30,
                                         "target_physical_attacker" => false })
    assert_equal(25.0 * 0.5 * 0.3, PortableAI::Search.project(snap, board, scald, stay, true)["foe_status_points"])
    # A status move with no effect export still reads its kind off the tags.
    wisp = move(2, "WILLOWISP", 0, 100, 0, { "accuracy" => 85, "target_physical_attacker" => true })
    assert_equal(25.0, PortableAI::Search.project(snap, board, wisp, stay, true)["foe_status_points"])
    # A drop is a stage off the foe's boost; a foe switch drops all of theirs.
    boosted = one_v_one(100, 100, mx_cell(40, 40, true), { "incoming_damage_pct" => 0 },
                        { "positive_stages" => 2 })
    b = PortableAI::Search.opening_board(boosted)
    assert_equal(50.0, b["foe_boost"])
    growl = move(0, "GROWL", 0, 100, 0, { "accuracy" => 100, "effect_kind" => "drop",
                                        "effect_stat" => "atk", "effect_chance" => 100 })
    assert_equal(20.0, PortableAI::Search.project(boosted, b, growl, stay, true)["foe_boost"])
    boosted["matrix"]["foe"] << { "slot" => 1, "index" => nil, "hp_pct" => 100, "alive" => true, "speed" => 50 }
    boosted["matrix"]["cells"]["0:1"] = mx_cell(40, 40, true)
    # ... and the Growl then lands on the fresh body, a stage below zero.
    left = PortableAI::Search.project(boosted, b, growl, { "kind" => "switch", "slot" => 1 }, true)
    assert_equal(-30.0, left["foe_boost"])
    # And the leaf: the foe's points carry its boost, and lose the status.
    assert_equal(PortableAI::Search.leaf(boosted, b) + 30.0,
                 PortableAI::Search.leaf(boosted, PortableAI::Search.project(boosted, b, growl, stay, true)))
    # Miss branch: nothing lands, status included.
    assert_equal(0.0, PortableAI::Search.project(snap, board, toxic, stay, true, false)["foe_status_points"])
  end

  def test_search_projects_hazards_per_live_foe_body
    snap = one_v_one(100, 100, mx_cell(40, 40, true))
    snap["matrix"]["foe"] << { "slot" => 1, "index" => nil, "hp_pct" => 100, "alive" => true, "speed" => 50 }
    snap["matrix"]["foe"] << { "slot" => 2, "index" => nil, "hp_pct" => 0, "alive" => false, "speed" => 50 }
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    rocks = move(0, "STEALTHROCK", 0, 100, 0, { "accuracy" => 0, "existing_layers" => 0, "max_layers" => 1 })
    assert_equal(20.0, PortableAI::Search.project(snap, board, rocks, stay, true)["foe_hazard_points"])
    laid = move(0, "STEALTHROCK", 0, 100, 0, { "accuracy" => 0, "existing_layers" => 1, "max_layers" => 1 })
    assert_equal(0.0, PortableAI::Search.project(snap, board, laid, stay, true)["foe_hazard_points"])
    spikes = move(0, "SPIKES", 0, 100, 0, { "accuracy" => 0, "existing_layers" => 1, "max_layers" => 3 })
    assert_equal(14.0, PortableAI::Search.project(snap, board, spikes, stay, true)["foe_hazard_points"])
  end

  def test_search_charges_a_kill_for_what_the_move_costs
    # Both kill. Superpower pays a stage of Attack and Defence, so X-Scissor wins the
    # tie that 0.7.1 broke on the slot key.
    # At 80% so a drain has something to restore; faster, so the kill costs no hit.
    snap = one_v_one(80, 30, mx_cell(40, 40, true))
    snap["matrix"]["foe"] << { "slot" => 1, "index" => nil, "hp_pct" => 100, "alive" => true, "speed" => 50 }
    snap["matrix"]["cells"]["0:1"] = mx_cell(40, 40, true)
    snap["targets"][0]["trapped"] = true
    snap["actors"][0]["actions"] = [
      move(0, "SUPERPOWER", 0, 100, 60, { "accuracy" => 100 }),
      move(1, "XSCISSOR", 0, 100, 60, { "accuracy" => 100 }),
      move(2, "BRAVEBIRD", 0, 100, 60, { "accuracy" => 100, "recoil_fraction" => 0.3333 }),
      move(3, "DRAINPUNCH", 0, 100, 60, { "accuracy" => 100, "drain_fraction" => 0.5 })
    ]
    ranked = PortableAI::Search.plan(snap, ONE_PLY, nil)["diagnostics"]["rankings"][0]
    assert_equal(%w[DRAINPUNCH XSCISSOR BRAVEBIRD SUPERPOWER], ranked.map { |c| c["move_id"] })
    by = {}
    ranked.each { |c| by[c["move_id"]] = c["score"] }
    assert_equal(by["XSCISSOR"] - 45.0, by["SUPERPOWER"])
    assert_in_delta(by["XSCISSOR"] - 60.0 * 0.3333, by["BRAVEBIRD"], 0.001)
    # 80 + 30 caps at 100: twenty points, not thirty.
    assert_equal(by["XSCISSOR"] + 20.0, by["DRAINPUNCH"])
  end

  def test_search_clicks_a_setup_move_when_it_wins_the_position
    # Slower and losing the pair on a 40/40 trade; +1/+1 makes it faster and a
    # two-hit kill against three. The boost is worth more than the chip.
    snap = one_v_one(100, 100, mx_cell(40, 40, false))
    snap["targets"][0]["trapped"] = true
    snap["actors"][0]["actions"] = [
      move(0, "DRAGONDANCE", 0, 100, 0, { "accuracy" => 0 }),
      move(1, "WATERFALL", 0, 100, 40, { "accuracy" => 100 })
    ]
    chosen = search_pick(snap)
    assert_equal("DRAGONDANCE", chosen["move_id"])
  end

  # 0.7.3. THE SECOND PLY.

  def test_search_depth_comes_from_the_key_and_floors_at_one
    assert_equal(2, PortableAI::Search.depth_of({}))
    assert_equal(2, PortableAI::Search.depth_of(nil))
    assert_equal(1, PortableAI::Search.depth_of({ "search_depth" => 1 }))
    assert_equal(1, PortableAI::Search.depth_of({ "search_depth" => 0 }))
    assert_equal(3, PortableAI::Search.depth_of({ "search_depth" => 3.0 }))
    assert_equal(2, PortableAI::Model::DEFAULT_CONFIG["search_depth"])
    plan = PortableAI::Search.plan(search_snap([move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })]), {}, nil)
    assert_equal(2, plan["diagnostics"]["depth"])
  end

  def test_search_options_below_the_root_follow_the_bodies_on_the_field
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    bench = { "type" => "switch", "slot" => 1, "base_score" => 100,
              "candidate_hp_pct" => 100, "entry_damage_pct" => 0, "incoming_damage_pct" => 33 }
    snap = search_snap([tackle, bench])
    root = [tackle, bench]
    board = PortableAI::Search.opening_board(snap)
    # The same pair: the root's moves, and the root's own switch action for the bench.
    own = PortableAI::Search.own_options(snap, board, root)
    assert_equal(["TACKLE", nil], own.map { |a| a["move_id"] })
    assert_equal(33, own[1]["incoming_damage_pct"])
    # The foe switched: one attack worth the cell, and the bench priced off the table.
    after = PortableAI::Search.project(snap, board, tackle, { "kind" => "switch", "slot" => 1 }, true)
    own = PortableAI::Search.own_options(snap, after, root)
    assert_equal("MATRIX_ATTACK", own[0]["move_id"])
    assert_equal(5.0, own[0]["expected_damage_pct"])
    assert_equal(nil, own[1]["incoming_damage_pct"])
    # Our body down: replacements only, and the foe does nothing that ply.
    down = PortableAI::Search.opening_board(snap)
    down["own_hp"] = 0.0
    assert_equal([[true, 1]], PortableAI::Search.own_options(snap, down, root).map { |a| [a["forced"], a["slot"]] })
    assert_equal([{ "kind" => "none" }], PortableAI::Search.foe_options(snap, down))
    # Their body down: we idle, they pick from their bench.
    theirs = PortableAI::Search.opening_board(snap)
    theirs["foe_hp"] = 0.0
    assert_equal([{ "type" => "none" }], PortableAI::Search.own_options(snap, theirs, root))
    assert_equal([{ "kind" => "switch", "slot" => 1 }], PortableAI::Search.foe_options(snap, theirs))
    # A trapped actor has no bench while it is the body on the field, and has one
    # again once another body stands there.
    snap["actors"][0]["trapped"] = true
    held = PortableAI::Search.opening_board(snap)
    assert_equal(["TACKLE"], PortableAI::Search.own_options(snap, held, root).map { |a| a["move_id"] })
    moved = PortableAI::Search.project(snap, held, bench, { "kind" => "stay" }, true)
    assert_equal(true, PortableAI::Search.own_options(snap, moved, root).any? { |a| a["type"] == "switch" })
  end

  def test_search_second_ply_is_the_safest_reply_from_each_board
    # A kill with a bench behind it: at depth 2 the stay column is the replacement
    # ply -- the foe brings in whatever is worst for us and we do nothing -- and the
    # cell's value is exactly that leaf.
    cells = { "0:0" => mx_cell(40, 40, true), "0:1" => mx_cell(40, 40, true) }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    snap = snapshot([actor(0, 100, [tackle], {})], [target(0, 30)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 30, 0], [1, 100, nil]], cells))
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    killed = PortableAI::Search.project(snap, board, tackle, stay, true)
    replaced = PortableAI::Search.project(snap, killed, { "type" => "none" }, { "kind" => "switch", "slot" => 1 }, true)
    assert_equal(1, replaced["foe_slot"])
    assert_equal(100.0, replaced["foe_hp"])
    assert_equal(PortableAI::Search.leaf(snap, replaced),
                 PortableAI::Search.payoff(snap, board, tackle, stay, 2, [tackle]))
    # Depth 1 of the same cell is the board right after the kill.
    assert_equal(PortableAI::Search.leaf(snap, killed),
                 PortableAI::Search.payoff(snap, board, tackle, stay, 1, [tackle]))
    # A finished battle a ply early is worth the win plus the plies not needed.
    alone = snapshot([actor(0, 100, [tackle], {})], [target(0, 30)], {})
    with_matrix(alone, matrix_snap([[0, 100, 0]], [[0, 30, 0]], cells))
    b = PortableAI::Search.opening_board(alone)
    assert_equal(PortableAI::Search::BATTLE_OVER + PortableAI::Search::DEPTH_BONUS,
                 PortableAI::Search.payoff(alone, b, tackle, stay, 2, [tackle]))
  end

  def test_search_protect_fails_on_the_ply_after_a_protect
    snap = one_v_one(100, 100, mx_cell(40, 40, true))
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    protect = move(0, "PROTECT", 0, 100, 0, { "accuracy" => 0 })
    once = PortableAI::Search.project(snap, board, protect, stay, true)
    assert_equal(1, once["protect_repeats"])
    twice = PortableAI::Search.project(snap, once, protect, stay, true)
    assert_equal(60.0, twice["own_hp"])
    attacked = PortableAI::Search.project(snap, board, move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }), stay, true)
    assert_equal(0, attacked["protect_repeats"])
  end

  def test_search_projected_stages_scale_the_next_ply_and_the_speed_order
    snap = one_v_one(100, 100, mx_cell(40, 40, false))
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    dd = move(0, "DRAGONDANCE", 0, 100, 0, { "accuracy" => 0 })
    tackle = move(1, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    danced = PortableAI::Search.project(snap, board, dd, stay, false)
    # +1 Attack on a physical body: the root's 40 becomes 60 next ply.
    assert_equal(60.0, PortableAI::Search.own_damage(snap, danced, danced, tackle, stay))
    # +1 Speed: 150 against their 90 moves first now, whatever the live view said.
    assert_equal(false, PortableAI::Search.moves_first(snap, board, tackle, stay))
    assert_equal(true, PortableAI::Search.moves_first(snap, danced, tackle, stay))
    # A defence stage divides what comes in, by the category of their best hit.
    armored = PortableAI::Search.project(snap, board, move(0, "IRONDEFENSE", 0, 100, 0, { "accuracy" => 0 }), stay, true)
    assert_equal({ "def" => 2 }, armored["own_stages"])
    assert_equal(20.0, PortableAI::Search.foe_damage(snap, armored, armored, tackle, stay))
    # A landed status is not landed twice, and a foe switch-in starts clean.
    toxic = move(2, "TOXIC", 0, 100, 0, { "accuracy" => 100, "effect_kind" => "poison", "effect_chance" => 100 })
    poisoned = PortableAI::Search.project(snap, board, toxic, stay, true)
    assert_equal(30.0, PortableAI::Search.project(snap, poisoned, toxic, stay, true)["foe_status_points"])
    snap["matrix"]["foe"] << { "slot" => 1, "index" => nil, "hp_pct" => 100, "alive" => true, "speed" => 50 }
    snap["matrix"]["cells"]["0:1"] = mx_cell(40, 40, true)
    fresh = PortableAI::Search.project(snap, poisoned, { "type" => "none" }, { "kind" => "switch", "slot" => 1 }, true)
    assert_equal(0.0, fresh["foe_status_points"])
  end

  def test_search_remembers_the_hp_of_a_body_that_left_the_field
    # Depth two's collapse: we hit the foe for 40, it switched out, and on the leaf
    # it stood at its table HP again -- every hit was erased whenever the foe's worst
    # case was a switch, so only stages and hazards were worth clicking (15/60).
    cells = { "0:0" => mx_cell(40, 40, true), "0:1" => mx_cell(40, 40, true),
              "1:0" => mx_cell(40, 40, true), "1:1" => mx_cell(40, 40, true) }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    snap = snapshot([actor(0, 100, [tackle], {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0], [1, 100, nil]], [[0, 100, 0], [1, 100, nil]], cells))
    board = PortableAI::Search.opening_board(snap)
    assert_equal({ 0 => 100.0 }, board["foe_hps"])
    hit = PortableAI::Search.project(snap, board, tackle, { "kind" => "stay" }, true)
    assert_equal(60.0, hit["foe_hp"])
    assert_equal({ 0 => 60.0 }, hit["foe_hps"])
    left = PortableAI::Search.project(snap, hit, { "type" => "none" }, { "kind" => "switch", "slot" => 1 }, true)
    assert_equal({ 0 => 60.0, 1 => 100.0 }, left["foe_hps"])
    # The leaf still counts the 40 that body lost: we (60 + 30) + 130, they
    # (60 + 30) + 130: even.
    assert_equal(0.0, PortableAI::Search.leaf(snap, left))
    # And it comes back at 60, not 100.
    back = PortableAI::Search.project(snap, left, { "type" => "none" }, { "kind" => "switch", "slot" => 0 }, true)
    assert_equal(60.0, back["foe_hp"])
    # Our side, the same: a body that took 40 and left returns at 60.
    ours = PortableAI::Search.project(snap, board, tackle, { "kind" => "stay" }, true)
    assert_equal(60.0, ours["own_hp"])
    out = PortableAI::Search.project(snap, ours, { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }, { "kind" => "none" }, true)
    assert_equal({ 0 => 60.0, 1 => 100.0 }, out["own_hps"])
    home = PortableAI::Search.project(snap, out, { "type" => "switch", "slot" => 0, "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }, { "kind" => "none" }, true)
    assert_equal(60.0, home["own_hp"])
    # At depth two, a hit landed on a body that then switches out is still worth
    # the hit: the Tackle line beats the do-nothing line by what it dealt.
    switch_in = { "kind" => "switch", "slot" => 1 }
    idle = { "type" => "none" }
    assert_equal(true, PortableAI::Search.payoff(snap, board, tackle, switch_in, 2, [tackle]) >
                       PortableAI::Search.payoff(snap, board, idle, switch_in, 2, [tackle]))
  end

  # 0.7.4. A cell that carries every move it rolled (out_moves) prices THE MOVE WE
  # CLICK against a switch-in, not the body's best hit. Without the list the one
  # best number is all there is, as before.
  def test_search_prices_the_clicked_move_against_a_foe_switch_in
    cells = { "0:0" => mx_cell(40, 40, true),
              "0:1" => mx_cell(80, 40, true).merge(
                "out_moves" => { "ICEBEAM" => { "pct" => 80, "cat" => "special" },
                                 "EARTHQUAKE" => { "pct" => 0, "cat" => "physical" } }) }
    quake = move(0, "EARTHQUAKE", 0, 100, 40, { "accuracy" => 100 })
    beam = move(1, "ICEBEAM", 0, 100, 40, { "accuracy" => 100 })
    growl = move(2, "GROWL", 0, 100, 0, { "accuracy" => 100 })
    snap = snapshot([actor(0, 100, [quake, beam, growl], {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 100, 0], [1, 100, nil]], cells))
    board = PortableAI::Search.opening_board(snap)
    switch_in = { "kind" => "switch", "slot" => 1 }
    after = PortableAI::Search.project(snap, board, { "type" => "none" }, switch_in, true)
    assert_equal(80.0, PortableAI::Search.own_damage(snap, board, after, beam, switch_in))
    assert_equal(0.0, PortableAI::Search.own_damage(snap, board, after, quake, switch_in))
    assert_equal(0.0, PortableAI::Search.own_damage(snap, board, after, growl, switch_in))
    # A move the cell never rolled, or a cell with no list: the best number, as 0.7.3.
    other = move(3, "SURF", 0, 100, 40, { "accuracy" => 100 })
    assert_equal(80.0, PortableAI::Search.own_damage(snap, board, after, other, switch_in))
    snap["matrix"]["cells"]["0:1"].delete("out_moves")
    assert_equal(80.0, PortableAI::Search.own_damage(snap, board, after, quake, switch_in))
  end

  # ...and so the foe-switch column can finally order our moves: two 40s on the
  # field, but only one of them touches the body they would switch to.
  def test_search_prefers_the_move_their_bench_cannot_wall
    cells = { "0:0" => mx_cell(40, 40, true),
              "0:1" => mx_cell(80, 40, true).merge(
                "out_moves" => { "ICEBEAM" => { "pct" => 80, "cat" => "special" },
                                 "EARTHQUAKE" => { "pct" => 0, "cat" => "physical" } }) }
    quake = move(0, "EARTHQUAKE", 0, 100, 40, { "accuracy" => 100 })
    beam = move(1, "ICEBEAM", 0, 100, 40, { "accuracy" => 100 })
    snap = snapshot([actor(0, 100, [quake, beam], {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 100, 0], [1, 100, nil]], cells))
    assert_equal("ICEBEAM", search_pick(snap, ONE_PLY)["move_id"])
    # Slot order would have said Earthquake; the list is what decides it.
    snap["matrix"]["cells"]["0:1"].delete("out_moves")
    assert_equal("EARTHQUAKE", search_pick(snap, ONE_PLY)["move_id"])
  end

  # 0.7.4. The stages a body already stands on are inside every number the root
  # exports; only the stages this search projects on top scale them. A +2 body read
  # as +4 through 0.7.3.
  def test_search_does_not_scale_the_root_numbers_by_stages_they_already_carry
    stay = { "kind" => "stay" }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    # +2 Attack, +1 Speed, +2 Defence already, and the live view says we are slower.
    snap = one_v_one(100, 100, mx_cell(40, 40, false),
                     { "stages" => [0, 2, 2, 1, 0, 0, 0, 0], "faster" => false })
    board = PortableAI::Search.opening_board(snap)
    assert_equal({ "atk" => 2, "def" => 2, "speed" => 1 }, board["stage_base"])
    assert_equal({}, PortableAI::Search.projected_stages(board))
    assert_equal(40.0, PortableAI::Search.own_damage(snap, board, board, tackle, stay))
    assert_equal(40.0, PortableAI::Search.foe_damage(snap, board, board, tackle, stay))
    assert_equal(false, PortableAI::Search.moves_first(snap, board, tackle, stay))
    # The leaf still pays the original's boost term for the whole stack.
    assert_equal(PortableAI::Search.stage_points({ "atk" => 2, "def" => 2, "speed" => 1 }),
                 PortableAI::Search.leaf(snap, board) - PortableAI::Search.leaf(snap, board.merge("own_stages" => {})))
    # A Swords Dance on top is +2 more: x2 on the root's 40, not x3 on 80.
    dance = move(1, "SWORDSDANCE", 0, 100, 0, { "accuracy" => 0 })
    danced = PortableAI::Search.project(snap, board, dance, stay, true)
    assert_equal({ "atk" => 4, "def" => 2, "speed" => 1 }, danced["own_stages"])
    assert_equal({ "atk" => 2 }, PortableAI::Search.projected_stages(danced))
    assert_equal(80.0, PortableAI::Search.own_damage(snap, danced, danced, tackle, stay))
    # A switch leaves the base behind with the stages.
    snap["matrix"]["own"] << { "slot" => 1, "index" => nil, "hp_pct" => 100, "alive" => true, "speed" => 80 }
    snap["matrix"]["cells"]["1:0"] = mx_cell(30, 30, false)
    entry = { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }
    left = PortableAI::Search.project(snap, danced, entry, stay, true)
    assert_equal({}, left["stage_base"])
    assert_equal({}, PortableAI::Search.projected_stages(left))
  end

  # 0.7.5. THE OPPONENT MODEL. search_foe_mix 0 is the original's pick_safest (every
  # test above). 1 values a row at the expected reply; between, a blend. The weights
  # are uniform unless the adapter exported a predicted reply for the foe on the
  # field, and always uniform below the root.
  def test_search_foe_mix_blends_the_worst_reply_with_the_expected_one
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
               { "type" => "switch", "slot" => 1, "base_score" => 100,
                 "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }]
    attack_at = lambda do |config|
      PortableAI::Search.plan(search_snap(actions), config, nil)["diagnostics"]["rankings"][0]
                        .find { |c| c["type"] == "move" }
    end
    pure = attack_at.call(ONE_PLY)
    row = pure["search_row"]
    assert_equal(2, row.length)
    assert_equal(true, row[1] > row[0])            # their switch is our better column
    assert_equal(row.min, pure["score"])
    mean = (row[0] + row[1]) / 2.0
    assert_in_delta(mean, attack_at.call(ONE_PLY.merge("search_foe_mix" => 1.0))["score"], 1e-9)
    assert_in_delta(0.5 * row.min + 0.5 * mean,
                    attack_at.call(ONE_PLY.merge("search_foe_mix" => 0.5))["score"], 1e-9)
    # Clamped: 3 is 1, -1 is 0.
    assert_in_delta(mean, attack_at.call(ONE_PLY.merge("search_foe_mix" => 3))["score"], 1e-9)
    assert_equal(row.min, attack_at.call(ONE_PLY.merge("search_foe_mix" => -1))["score"])
    assert_equal(1.0, PortableAI::Search.mix_of("search_foe_mix" => 1.0))
    assert_equal(0.0, PortableAI::Search.mix_of({}))
  end

  def test_search_foe_mix_weights_the_columns_by_the_predicted_reply
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })]
    full = ONE_PLY.merge("search_foe_mix" => 1.0)
    expect = lambda do |predicted|
      snap = search_snap(actions)
      snap["actors"][0]["predicted_foe"] = { "0" => predicted } if predicted
      plan = PortableAI::Search.plan(snap, full, nil)
      [plan["diagnostics"]["rankings"][0][0], plan["diagnostics"]]
    end
    none, diag = expect.call(nil)
    row = none["search_row"]
    assert_equal([0.5, 0.5], diag["foe_weights"])
    assert_nil(diag["foe_reply"])
    # A model that says "stays four times in five".
    modelled, diag = expect.call({ "type" => "move", "move_id" => "TACKLE", "switch_chance" => 0.2 })
    assert_equal([0.8, 0.2], diag["foe_weights"])
    assert_in_delta(0.8 * row[0] + 0.2 * row[1], modelled["score"], 1e-9)
    assert_in_delta(0.8 * row[0] + 0.2 * row[1], reason_value(modelled, "search_expected"), 1e-9)
    # The oracle's declared switch, slot known: that column alone.
    declared, diag = expect.call({ "type" => "switch", "slot" => 1 })
    assert_equal([0.0, 1.0], diag["foe_weights"])
    assert_in_delta(row[1], declared["score"], 1e-9)
    # A switch to a slot the columns do not have shares the chance over every switch.
    assert_equal([0.5, 0.25, 0.25],
                 PortableAI::Search.column_weights(
                   [{ "kind" => "stay" }, { "kind" => "switch", "slot" => 1 }, { "kind" => "switch", "slot" => 2 }],
                   { "switch_chance" => 0.5, "switch_slot" => 9 }))
    # A replacement ply has no stay column: uniform whatever was predicted.
    assert_equal([0.5, 0.5],
                 PortableAI::Search.column_weights(
                   [{ "kind" => "switch", "slot" => 1 }, { "kind" => "switch", "slot" => 2 }],
                   { "switch_chance" => 0.0 }))
    # And a prediction is this turn's only: the projected board carries the mix, not
    # the reply.
    snap = search_snap(actions)
    snap["actors"][0]["predicted_foe"] = { "0" => { "type" => "switch", "slot" => 1 } }
    board = PortableAI::Search.opening_board(snap, "search_foe_mix" => 0.5)
    assert_equal({ "switch_chance" => 1.0, "switch_slot" => 1 }, board["foe_reply"])
    after = PortableAI::Search.project(snap, board, actions[0], { "kind" => "stay" }, true)
    assert_nil(after["foe_reply"])
  end

  def test_search_foe_mix_stays_maximin_below_the_root
    # The model is the root's: a prediction exists only for the board in front of
    # us, and blending the deeper grids with a uniform expectation measured worse
    # (42 against 46 with the stock model). So safest does not read the mix, and a
    # projected board does not carry it or the reply.
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })]
    snap = search_snap(actions)
    snap["actors"][0]["predicted_foe"] = { "0" => { "type" => "switch", "slot" => 1 } }
    board = PortableAI::Search.opening_board(snap, "search_foe_mix" => 1.0)
    assert_equal(false, board.key?("foe_mix"))
    foe = PortableAI::Search.foe_options(snap, board)
    own = PortableAI::Search.own_options(snap, board, actions)
    rows = own.map { |a| foe.map { |f| PortableAI::Search.payoff(snap, board, a, f, 1, actions) } }
    assert_in_delta(rows.map { |r| r.min }.max,
                    PortableAI::Search.safest(snap, board, own, foe, 1, actions), 1e-9)
    # At depth two the root row is blended and its cells are maximin sub-grids: the
    # root score with mix 1 and a declared switch is exactly the switch column of the
    # mix-0 row.
    pure = PortableAI::Search.plan(snap, { "search_foe_mix" => 0 }, nil)["diagnostics"]["rankings"][0][0]
    mixed = PortableAI::Search.plan(snap, { "search_foe_mix" => 1.0 }, nil)["diagnostics"]["rankings"][0][0]
    assert_equal(pure["search_row"], mixed["search_row"])
    assert_in_delta(pure["search_row"][1], mixed["score"], 1e-9)
  end

  def test_search_reads_its_defaults_under_the_overrides
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })]
    diag = PortableAI::Search.plan(search_snap(actions), {}, nil)["diagnostics"]
    assert_equal(PortableAI::Model::DEFAULT_CONFIG["search_foe_mix"], diag["foe_mix"])
    assert_equal(0.5, diag["foe_mix"])
    assert_equal(PortableAI::Model::DEFAULT_CONFIG["search_depth"], diag["depth"])
    # A nil config is the defaults too, as the rule engine takes it.
    assert_equal(0.5, PortableAI::Search.plan(search_snap(actions), nil, nil)["diagnostics"]["foe_mix"])
    assert_equal(0.0, PortableAI::Search.plan(search_snap(actions), { "search_foe_mix" => 0 }, nil)["diagnostics"]["foe_mix"])
  end

  # ---------------------------------------------------------------------------
  # 0.7.6. THE TREE. Decoupled simultaneous-move MCTS on the same board, off by
  # default; with the key off `plan` is the maximin above, decision for decision.

  MCTS = { "search_mcts" => true, "search_iterations" => 400 }

  def test_mcts_is_off_by_default_and_off_is_the_maximin
    assert_equal(false, PortableAI::Model::DEFAULT_CONFIG["search_mcts"])
    assert_equal(1000, PortableAI::Model::DEFAULT_CONFIG["search_iterations"])
    assert_equal(0, PortableAI::Model::DEFAULT_CONFIG["search_seed"])
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
               { "type" => "switch", "slot" => 1, "base_score" => 100,
                 "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }]
    # The defaults, and an explicit false, are both the grid -- and neither answer
    # carries a visit count, which is the only thing the tree ranks by.
    off = PortableAI::Search.plan(search_snap(actions), {}, nil)
    assert_equal("search", off["diagnostics"]["planner"])
    assert_equal(nil, off["diagnostics"]["rankings"][0][0]["search_visits"])
    assert_equal(off, PortableAI::Search.plan(search_snap(actions),
                                              { "search_mcts" => false }, nil))
  end

  def test_mcts_returns_the_shape_the_adapter_reads
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
               { "type" => "switch", "slot" => 1, "base_score" => 100,
                 "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }]
    plan = PortableAI::Search.plan(search_snap(actions), MCTS, nil)
    diag = plan["diagnostics"]
    assert_equal(PortableAI::VERSION, diag["version"])
    assert_equal("mcts", diag["planner"])
    assert_equal(400, diag["iterations"])
    assert_equal(PortableAI::Search::MCTS_HORIZON, diag["horizon"])
    assert_equal(1, plan["actions"].length)
    assert_equal(true, plan["memory_updates"].is_a?(Hash))
    ranked = diag["rankings"][0]
    assert_equal(actions.length, ranked.length)
    assert_equal([actions.length], diag["candidate_counts"])
    # Every iteration passes through the root and credits exactly one option a side,
    # so the root's visits are the budget -- on both axes.
    assert_equal(400, ranked.inject(0) { |sum, c| sum + c["search_visits"] })
    assert_equal(400, diag["foe_visits"].inject(0) { |sum, v| sum + v })
    # A score is an average in 0..1 (the sigmoid's range), not the leaf's HP points,
    # and the row has one entry per foe column as the readout tools expect.
    ranked.each do |candidate|
      assert_equal(true, candidate["score"] >= 0.0 && candidate["score"] <= 1.0)
      assert_equal(diag["foe_options"].length, candidate["search_row"].length)
      assert_equal(400, reason_value(candidate, "search_iterations"))
    end
    # Most-visited is the pick, which is Foul Play's convention and not "best average".
    assert_equal(ranked.map { |c| c["search_visits"] }.max, ranked[0]["search_visits"])
    assert_equal(ranked[0]["search_visits"], reason_value(ranked[0], "search_visits"))
  end

  def test_mcts_finds_the_kill_the_maximin_finds
    # The 0.7.0 kill snapshot, unchanged: their last body at 30%, so their only option
    # is to stand there and take it, and removing it ends the battle. A tree that
    # cannot find this one is not searching.
    cells = { "0:0" => mx_cell(40, 40, true) }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    ember = move(1, "EMBER", 0, 100, 10, { "accuracy" => 100 })
    snap = snapshot([actor(0, 100, [tackle, ember], {})], [target(0, 30)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 30, 0]], cells))
    assert_equal("TACKLE", search_pick(snap, MCTS)["move_id"])
    # And it is the battle ending that says so: a won board is the sigmoid's ceiling.
    ranked = PortableAI::Search.plan(snap, MCTS, nil)["diagnostics"]["rankings"][0]
    assert_equal(1.0, ranked.find { |c| c["move_id"] == "TACKLE" }["search_row"][0])
  end

  def test_mcts_branches_a_pair_into_its_chance_outcomes
    # An unknown speed order and a 70% move: two orders at a half, each splitting into
    # a hit and a miss. The same branching payoff averages over, kept as children.
    cells = { "0:0" => mx_cell(40, 40, nil) }
    half = move(0, "SURF", 0, 100, 40, { "accuracy" => 70 })
    snap = snapshot([actor(0, 100, [half], {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 100, 0]], cells))
    node = PortableAI::Search.node_for(PortableAI::Search.opening_board(snap), 0)
    PortableAI::Search.populate(snap, node, [half])
    kids = PortableAI::Search.branches(snap, node, 0, 0, [half])
    # 0.7.9: two orders x (our hit at its two rolls, or a miss) x their two rolls.
    assert_equal(12, kids.length)
    assert_equal(1.0, (kids.inject(0.0) { |sum, k| sum + k["prob"] } * 1e6).round / 1e6)
    assert_equal(0.3, (kids.select { |k| !k["chance"]["own_does"] }.inject(0.0) { |sum, k| sum + k["prob"] } * 1e6).round / 1e6)
    # A child's board is built when the tree first walks into it, not before.
    assert_equal(true, kids.all? { |k| k["node"].nil? })
    kids.each { |k| PortableAI::Search.child_node(snap, node, 0, 0, k) }
    # The miss branches leave them untouched; the hit branches do not.
    kids.each do |k|
      hp = k["node"]["board"]["foe_hp"]
      assert_equal(k["chance"]["own_does"], hp < 100.0)
    end
    # And every child is one ply deeper, which is what the horizon counts.
    assert_equal(true, kids.all? { |k| k["node"]["ply"] == 1 })
    # A certain kill on a known order against a foe that deals nothing is one child
    # at probability one; below the root's children the roll stops branching, so the
    # same pair that split three ways above is two children (order known: one).
    sure = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    known = snapshot([actor(0, 100, [sure], {})], [target(0, 30)], {})
    with_matrix(known, matrix_snap([[0, 100, 0]], [[0, 30, 0]],
                                   { "0:0" => mx_cell(40, 0, true) }))
    root = PortableAI::Search.node_for(PortableAI::Search.opening_board(known), 0)
    PortableAI::Search.populate(known, root, [sure])
    assert_equal([1.0], PortableAI::Search.branches(known, root, 0, 0, [sure]).map { |k| k["prob"] })
    deep = PortableAI::Search.node_for(PortableAI::Search.opening_board(snap), 2)
    PortableAI::Search.populate(snap, deep, [half])
    assert_equal([[true, true], [true, false], [false, true], [false, false]],
                 PortableAI::Search.branches(snap, deep, 0, 0, [half]).map { |k| [k["order"], k["chance"]["own_does"]] })
  end

  # ---- 0.7.9: the board the original's tree plays on ----

  def test_the_foe_misses_at_its_own_accuracy
    cells = { "0:0" => mx_cell(40, 40, true) }
    cells["0:0"]["in_moves"] = { "STONEEDGE" => { "pct" => 40, "cat" => "physical", "damaging" => true,
                                                  "acc" => 80, "priority" => 0, "effect" => [nil, nil, nil] } }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    snap = snapshot([actor(0, 100, [tackle], {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 100, 0]], cells))
    board = PortableAI::Search.opening_board(snap)
    edge = PortableAI::Search.foe_options(snap, board)[0]
    assert_equal("STONEEDGE", edge["move_id"])
    assert_equal(0.8, PortableAI::Search.foe_hit_chance(edge))
    specs = PortableAI::Search.outcomes(snap, board, tackle, edge, true)
    missed = specs.select { |sp| !sp[2]["foe_does"] }
    assert_in_delta(0.2, missed.inject(0.0) { |sum, sp| sum + sp[0] }, 1e-9)
    after = PortableAI::Search.project(snap, board, tackle, edge, true, true, missed[0][2])
    assert_equal(100.0, after["own_hp"])
    # A paralysed foe acts three times in four on top of that; asleep, a third.
    board["foe_status"] = "paralyze"
    stuck = PortableAI::Search.outcomes(snap, board, tackle, edge, true).select { |sp| !sp[2]["foe_does"] }
    assert_in_delta(1.0 - 0.8 * 0.75, stuck.inject(0.0) { |sum, sp| sum + sp[0] }, 1e-9)
    assert_equal(1.0 / 3.0, PortableAI::Search.act_chance("sleep"))
    assert_equal(1.0, PortableAI::Search.act_chance(nil))
    # And the board opens with the status the side table reports (PBStatuses).
    snap["matrix"]["foe"][0]["status"] = 4
    assert_equal("paralyze", PortableAI::Search.opening_board(snap)["foe_status"])
  end

  def test_the_foe_can_set_up_heal_protect_and_status_us
    cells = { "0:0" => mx_cell(40, 40, true) }
    cells["0:0"]["in_moves"] = {
      "SWORDSDANCE" => { "pct" => 0, "cat" => "physical", "damaging" => false, "acc" => nil,
                         "priority" => 0, "effect" => [nil, nil, nil] },
      "RECOVER" => { "pct" => 0, "cat" => "physical", "damaging" => false, "acc" => nil,
                     "priority" => 0, "effect" => [nil, nil, nil] },
      "PROTECT" => { "pct" => 0, "cat" => "physical", "damaging" => false, "acc" => nil,
                     "priority" => 4, "effect" => [nil, nil, nil] },
      "TOXIC" => { "pct" => 0, "cat" => "physical", "damaging" => false, "acc" => 90,
                   "priority" => 0, "effect" => ["poison", nil, 100] },
      "ROCKSLIDE" => { "pct" => 40, "cat" => "physical", "damaging" => true, "acc" => 90,
                       "priority" => 0, "effect" => [nil, nil, nil] } }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    snap = snapshot([actor(0, 100, [tackle], {})], [target(0, 60)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 60, 0]], cells))
    board = PortableAI::Search.opening_board(snap)
    foe = {}
    PortableAI::Search.foe_options(snap, board).each { |f| foe[f["move_id"]] = f if f["kind"] == "stay" }
    assert_equal(%w[PROTECT RECOVER ROCKSLIDE SWORDSDANCE TOXIC], foe.keys.sort)
    # Swords Dance: +2 Attack on their side, worth what ours is worth, and it scales
    # their next physical hit; the leaf and the order both see it.
    up = PortableAI::Search.project(snap, board, tackle, foe["SWORDSDANCE"], true)
    assert_equal({ "atk" => 2 }, up["foe_stages"])
    assert_equal(PortableAI::Search.leaf(snap, PortableAI::Search.project(snap, board, tackle, { "kind" => "stay" }, true)) + 40.0 - 60.0,
                 PortableAI::Search.leaf(snap, up))
    assert_equal(80.0, PortableAI::Search.foe_damage(snap, up, up, tackle, foe["ROCKSLIDE"]))
    # Recover: half back, capped -- after our hit when we move first, before it
    # when they do.
    assert_equal(70.0, PortableAI::Search.project(snap, board, tackle, foe["RECOVER"], true)["foe_hp"])
    assert_equal(60.0, PortableAI::Search.project(snap, board, tackle, foe["RECOVER"], false)["foe_hp"])
    # Protect at +4 moves first and takes our whole move; it fails on the repeat.
    assert_equal(false, PortableAI::Search.moves_first(snap, board, tackle, foe["PROTECT"]))
    shielded = PortableAI::Search.project(snap, board, tackle, foe["PROTECT"], false)
    assert_equal(60.0, shielded["foe_hp"])
    assert_equal(1, shielded["foe_protect_repeats"])
    assert_equal(20.0, PortableAI::Search.project(snap, shielded, tackle, foe["PROTECT"], false)["foe_hp"])
    # Toxic on us: the status points, the status itself, and it ticks from then on.
    poisoned = PortableAI::Search.project(snap, board, tackle, foe["TOXIC"], true)
    assert_equal(-30.0, poisoned["own_status_points"])
    assert_equal("toxic", poisoned["own_status"])
    assert_equal(100.0 - 6.25, poisoned["own_hp"])
    # A bare stay carries no move on the 0.7.9 board, and the foe (60 HP, hit once
    # already) dies to our second Tackle before it can act anyway: only the tick lands.
    again = PortableAI::Search.project(snap, poisoned, tackle, { "kind" => "stay" }, true)
    assert_equal(100.0 - 6.25 - 12.5, again["own_hp"])
    assert(again["foe_hp"] <= 0.0)
    # Moving first, its Rock Slide lands before the tick.
    assert_equal(100.0 - 6.25 - 40.0 - 12.5,
                 PortableAI::Search.project(snap, poisoned, tackle, foe["ROCKSLIDE"], false)["own_hp"])
    # A second Toxic on a body already carrying one is refused.
    assert_equal(-30.0, PortableAI::Search.project(snap, poisoned, tackle, foe["TOXIC"], true)["own_status_points"])
  end

  def test_the_end_of_turn_ticks_on_both_sides
    cells = { "0:0" => mx_cell(0, 0, true) }
    snap = snapshot([actor(0, 100, [], {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 100, 0]], cells))
    snap["matrix"]["own"][0]["item"] = "LEFTOVERS"
    snap["matrix"]["foe"][0]["status"] = 3   # burned
    snap["matrix"]["foe"][0]["types"] = ["FIRE"]
    snap["weather"] = "sand"
    board = PortableAI::Search.opening_board(snap)
    stay = { "kind" => "stay" }
    none = { "type" => "none" }
    after = PortableAI::Search.project(snap, board, none, stay, true)
    # Leftovers a sixteenth, sand a sixteenth: a wash for us; burn and sand for them.
    assert_equal(100.0, after["own_hp"])
    assert_equal(100.0 - 12.5 - 6.25, after["foe_hp"])
    # Sand-proof types and Magic Guard walk over it; Poison Heal turns poison around.
    snap["matrix"]["foe"][0]["types"] = ["ROCK"]
    assert_equal(100.0 - 12.5, PortableAI::Search.project(snap, board, none, stay, true)["foe_hp"])
    snap["matrix"]["foe"][0]["ability"] = "MAGICGUARD"
    assert_equal(100.0, PortableAI::Search.project(snap, board, none, stay, true)["foe_hp"])
    snap["matrix"]["foe"][0]["ability"] = "POISONHEAL"
    snap["matrix"]["foe"][0]["status"] = 2
    board = PortableAI::Search.opening_board(snap)
    assert_equal(100.0, PortableAI::Search.project(snap, board, none, stay, true)["foe_hp"])
    # A switch-in ticks too, under its own status, and a body that left stops.
    snap["matrix"]["foe"] << { "slot" => 1, "index" => nil, "species" => 101, "hp_pct" => 80,
                               "alive" => true, "speed" => 100, "types" => ["WATER"], "status" => 2,
                               "item" => "BLACKSLUDGE", "entry_damage_pct" => 12.5 }
    board = PortableAI::Search.opening_board(snap)
    came = PortableAI::Search.project(snap, board, none, { "kind" => "switch", "slot" => 1 }, true)
    # 80, minus the rocks it came in on, poison, sludge on a non-Poison body, sand.
    assert_equal(80.0 - 12.5 - 12.5 - 12.5 - 6.25, came["foe_hp"])
    assert_equal("poison", came["foe_status"])
  end

  def test_a_switch_below_the_root_pays_the_hazards_the_root_priced
    cells = { "0:0" => mx_cell(40, 40, true), "1:0" => mx_cell(40, 40, true),
              "0:1" => mx_cell(40, 40, true), "1:1" => mx_cell(40, 40, true) }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    root = [tackle, { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100, "entry_damage_pct" => 25 }]
    snap = snapshot([actor(0, 100, root, {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0], [1, 100, nil]], [[0, 100, 0], [1, 100, nil]], cells))
    snap["matrix"]["own"][1]["entry_damage_pct"] = 25
    board = PortableAI::Search.opening_board(snap)
    # After their switch the pair is no longer the live one, so the root's switch
    # action is not the truth about it -- but its hazard number still is.
    moved = PortableAI::Search.project(snap, board, tackle, { "kind" => "switch", "slot" => 1 }, true)
    bench = PortableAI::Search.own_options(snap, moved, root).find { |a| a["type"] == "switch" }
    assert_equal(25.0, bench["entry_damage_pct"])
    # And with no root export at all, the side table's number.
    bench = PortableAI::Search.own_options(snap, moved, [tackle]).find { |a| a["type"] == "switch" }
    assert_equal(25.0, bench["entry_damage_pct"])
  end

  def test_our_switch_in_has_its_whole_move_list_below_the_root
    cells = { "0:0" => mx_cell(40, 40, true), "1:0" => mx_cell(30, 40, true) }
    cells["1:0"]["out_moves"] = {
      "ICEBEAM" => { "pct" => 30, "cat" => "special", "damaging" => true, "acc" => 100,
                     "priority" => 0, "effect" => ["freeze", nil, 10] },
      "CALMMIND" => { "pct" => 0, "cat" => "special", "damaging" => false, "acc" => nil,
                      "priority" => 0, "effect" => [nil, nil, nil] } }
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    root = [tackle, { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }]
    snap = snapshot([actor(0, 100, root, {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0], [1, 100, nil]], [[0, 100, 0]], cells))
    board = PortableAI::Search.opening_board(snap)
    arrived = PortableAI::Search.project(snap, board, root[1], { "kind" => "stay" }, true)
    own = PortableAI::Search.own_options(snap, arrived, root)
    assert_equal(["CALMMIND", "ICEBEAM"], own.select { |a| a["type"] == "move" }.map { |a| a["move_id"] })
    mind = own.find { |a| a["move_id"] == "CALMMIND" }
    assert_equal({ "spa" => 1, "spd" => 1 },
                 PortableAI::Search.project(snap, arrived, mind, { "kind" => "stay" }, true)["own_stages"])
    beam = own.find { |a| a["move_id"] == "ICEBEAM" }
    assert_equal(30.0, PortableAI::Search.own_damage(snap, arrived, arrived, beam, { "kind" => "stay" }))
    # A cell with no list is still the one attack it always was.
    bare = PortableAI::Search.cell_actions(mx_cell(30, 40, true))
    assert_equal(["MATRIX_ATTACK"], bare.map { |a| a["move_id"] })
  end

  def test_mcts_backprop_credits_both_sides_of_one_leaf
    board = PortableAI::Search.opening_board(search_snap([]))
    node = PortableAI::Search.node_for(board, 0)
    node["own"] = [{ "type" => "move" }, { "type" => "switch" }]
    node["foe"] = [{ "kind" => "stay" }, { "kind" => "switch" }]
    PortableAI::Search.populate(search_snap([]), node, [])
    PortableAI::Search.backprop([[node, 1, 0]], 0.75)
    # Zero sum, one leaf: our option is worth the score, theirs its complement.
    assert_equal(0.75, node["own_stats"][1]["total"])
    assert_equal(0.25, node["foe_stats"][0]["total"])
    assert_equal([0, 1], node["own_stats"].map { |s| s["visits"] })
    assert_equal([1, 0], node["foe_stats"].map { |s| s["visits"] })
    assert_equal(1, node["visits"])
    # The per-cell tally search_row is read from, which the decoupled statistics
    # above cannot reconstruct.
    assert_equal({ "total" => 0.75, "visits" => 1 }, node["cells"][[1, 0]])
    # UCB1 sends the next visit to the option nobody has tried yet.
    assert_equal(0, PortableAI::Search.ucb_pick(node["own_stats"], node["visits"]))
    assert_equal(1, PortableAI::Search.ucb_pick(node["foe_stats"], node["visits"]))
  end

  def test_mcts_scores_a_finished_battle_and_stops_expanding_there
    snap = search_snap([])
    board = PortableAI::Search.opening_board(snap)
    won = PortableAI::Model.copy_hash(board)
    won["foe_hps"] = { 0 => 0.0, 1 => 0.0 }
    lost = PortableAI::Model.copy_hash(board)
    lost["own_hps"] = { 0 => 0.0, 1 => 0.0 }
    # The sigmoid's ends, not a leaf reading, so a win is never worth less than a
    # very good board.
    assert_equal(1.0, PortableAI::Search.evaluate_node(
      snap, PortableAI::Search.node_for(won, 1), 0.0))
    assert_equal(0.0, PortableAI::Search.evaluate_node(
      snap, PortableAI::Search.node_for(lost, 1), 0.0))
    # And neither is expanded: there is nothing left to play.
    [won, lost].each do |over|
      node = PortableAI::Search.node_for(over, 1)
      PortableAI::Search.populate(snap, node, [])
      assert_equal(true, PortableAI::Search.terminal_node?(snap, node))
    end
    # A standing board is expanded until the horizon and then scored where it stands.
    # Without the horizon a stage-only or Protect line never resolves and the descent
    # does not end.
    live = PortableAI::Search.node_for(board, PortableAI::Search::MCTS_HORIZON - 1)
    PortableAI::Search.populate(snap, live, [])
    assert_equal(false, PortableAI::Search.terminal_node?(snap, live))
    live["ply"] = PortableAI::Search::MCTS_HORIZON
    assert_equal(true, PortableAI::Search.terminal_node?(snap, live))
    assert_equal(0.5, PortableAI::Search.sigmoid(0.0))
  end

  def test_mcts_replays_from_the_snapshot_alone
    actions = [move(0, "SURF", 0, 100, 40, { "accuracy" => 70 }),
               move(1, "TACKLE", 0, 100, 25, { "accuracy" => 90 }),
               { "type" => "switch", "slot" => 1, "base_score" => 100,
                 "candidate_hp_pct" => 100, "entry_damage_pct" => 0 }]
    # The chance branches are sampled, so a decision is only readable if the stream is
    # the position: two runs of the same snapshot are the same tree, visit for visit.
    first = PortableAI::Search.plan(search_snap(actions), MCTS, nil)["diagnostics"]
    again = PortableAI::Search.plan(search_snap(actions), MCTS, Random.new(3))["diagnostics"]
    assert_equal(first["rankings"], again["rankings"])
    assert_equal(first["foe_visits"], again["foe_visits"])
    # The battle's own stream is untouched -- the rng argument is accepted and unused,
    # as on the maximin path -- so a shadow twin observes without disturbing.
    assert_equal(first["rankings"][0][0]["search_visits"],
                 PortableAI::Search.plan(search_snap(actions), MCTS,
                                         Random.new(99))["diagnostics"]["rankings"][0][0]["search_visits"])
    # search_seed is the one thing that can ask the same position for another tree.
    seeded = PortableAI::Search.plan(search_snap(actions),
                                     MCTS.merge({ "search_seed" => 17 }), nil)["diagnostics"]
    assert_equal(400, seeded["rankings"][0].inject(0) { |sum, c| sum + c["search_visits"] })
    assert_equal(true, PortableAI::Search.mcts_seed(search_snap(actions),
                                                    PortableAI::Search.opening_board(search_snap(actions)),
                                                    { "search_seed" => 17 }) !=
                       PortableAI::Search.mcts_seed(search_snap(actions),
                                                    PortableAI::Search.opening_board(search_snap(actions)), {}))
    # The budget is the key, floored at one.
    assert_equal(1, PortableAI::Search.iterations_of({ "search_iterations" => 0 }))
    assert_equal(1000, PortableAI::Search.iterations_of({}))
    assert_equal(2500, PortableAI::Search.iterations_of({ "search_iterations" => 2500.0 }))
  end

  # ---------------------------------------------------------------------------
  # 0.7.7. THE FOE GETS MOVES. Through 0.7.6 the foe had one `stay` column priced at
  # its best hit, so every planner here modelled the opponent as "it attacks, at
  # worst" -- and the 0.7.6 tree, whose whole thesis is that the foe's line should be
  # shaped by the foe's own payoff, was handed an opponent with one way to act.

  # A cell carrying the foe's own per-move rolls (in_moves, matrix version 3).
  def foe_move_cell(out, incoming, moves, faster = false)
    cell = mx_cell(out, incoming, faster)
    cell["in_moves"] = moves
    cell
  end

  # Their Golurk owns a big Earthquake, a middling Shadow Punch and a Stealth Rock
  # that does nothing at all -- the three shapes the old single column could not tell
  # apart, because it only ever reported the 60.
  FOE_MOVES = { "EARTHQUAKE" => { "pct" => 60, "cat" => "physical" },
                "SHADOWPUNCH" => { "pct" => 25, "cat" => "physical" },
                "STEALTHROCK" => { "pct" => 0, "cat" => nil } }

  def foe_axis_snap(own_actions, moves = FOE_MOVES)
    cells = { "0:0" => foe_move_cell(40, 60, moves, true),
              "1:0" => foe_move_cell(30, 10, { "EARTHQUAKE" => { "pct" => 10, "cat" => "physical" },
                                               "SHADOWPUNCH" => { "pct" => 50, "cat" => "physical" },
                                               "STEALTHROCK" => { "pct" => 0, "cat" => nil } }, true) }
    snap = snapshot([actor(0, 100, own_actions, {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0], [1, 100, nil]], [[0, 100, 0]], cells))
  end

  # --- 0.7.8: the damage prior over the foe's columns --------------------------

  # The foe axis snapshot has one foe body, so its columns are moves alone. This one
  # gives the foe a bench too, which is the only way a switch column exists to check
  # the prior never reaches it.
  def foe_bench_snap(own_actions)
    cells = { "0:0" => foe_move_cell(40, 60, FOE_MOVES, true),
              "0:1" => foe_move_cell(40, 30, FOE_MOVES, true) }
    snap = snapshot([actor(0, 100, own_actions, {})], [target(0, 100)], {})
    with_matrix(snap, matrix_snap([[0, 100, 0]], [[0, 100, 0], [1, 100, nil]], cells))
  end

  def test_foe_prior_normalises_the_stay_columns_and_leaves_switches_alone
    snap = foe_bench_snap([])
    options = PortableAI::Search.foe_options(snap, PortableAI::Search.opening_board(snap))
    prior = PortableAI::Search.foe_prior(options)
    # 60 / 25 / 0 over a total of 85, and the switch column is not the prior's business.
    assert_equal(["stay:EARTHQUAKE", "stay:SHADOWPUNCH", "stay:STEALTHROCK", "switch:1"],
                 options.map { |f| PortableAI::Search.foe_label(f) })
    assert_equal([0.7059, 0.2941, 0.0, 0.0], prior.map { |v| (v * 10000).round / 10000.0 })
    assert_equal(1.0, (prior.inject(0.0) { |sum, v| sum + v } * 10000).round / 10000.0)
    # Nothing priced -- a Reborn cell, a foe that only owns status -- is no prior at
    # all, which leaves both consumers exactly as they were.
    quiet = foe_axis_snap([], { "STEALTHROCK" => { "pct" => 0, "cat" => nil } })
    assert_equal(nil, PortableAI::Search.foe_prior(
      PortableAI::Search.foe_options(quiet, PortableAI::Search.opening_board(quiet))))
    assert_equal(nil, PortableAI::Search.foe_prior([]))
  end

  def test_column_weights_redistribute_within_the_stay_group_only
    snap = foe_bench_snap([])
    options = PortableAI::Search.foe_options(snap, PortableAI::Search.opening_board(snap))
    prior = PortableAI::Search.foe_prior(options)
    n = options.length.to_f
    assert_equal(options.map { 1.0 / n }, PortableAI::Search.column_weights(options, nil))
    # No opponent model, prior on: the three stay columns still hold 3/4 of the mass
    # between them, split 60/25/0 instead of evenly. The switch column does not move.
    weighted = PortableAI::Search.column_weights(options, nil, prior)
    assert_equal(1.0 / n, weighted[3])
    assert_equal((0.75 * 60 / 85 * 10000).round, (weighted[0] * 10000).round)
    assert_equal((0.75 * 25 / 85 * 10000).round, (weighted[1] * 10000).round)
    assert_equal(0.0, weighted[2])
    assert_equal(1.0, (weighted.inject(0.0) { |sum, v| sum + v } * 10000).round / 10000.0)
    # And with a prediction the switch/stay split the reply asked for is untouched --
    # the prior says WHICH MOVE, never whether the foe stays.
    reply = { "switch_chance" => 0.4, "switch_slot" => 1 }
    predicted = PortableAI::Search.column_weights(options, reply, prior)
    assert_equal(0.4, predicted[3])
    assert_equal((0.6 * 60 / 85 * 10000).round, (predicted[0] * 10000).round)
    assert_equal((0.6 * 25 / 85 * 10000).round, (predicted[1] * 10000).round)
    # Same reply, no prior: the old even share, so the key off is the 0.7.7 table.
    assert_equal([2000, 2000, 2000, 4000], PortableAI::Search.column_weights(
      options, reply).map { |v| (v * 10000).round })
  end

  def test_the_prior_key_is_off_by_default_and_off_reproduces_the_unpriored_search
    assert_equal(false, PortableAI::Model::DEFAULT_CONFIG["search_foe_prior"])
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
               move(0, "EMBER", 0, 100, 40, { "accuracy" => 100 })]
    snap = foe_axis_snap(actions)
    %w[maximin tree].each do |arm|
      base = arm == "tree" ? MCTS.dup : {}
      off = PortableAI::Search.plan(snap, base, nil)
      explicit = PortableAI::Search.plan(snap, base.merge({ "search_foe_prior" => false }), nil)
      # Everything but the wall clock, which the tree reports and nothing branches on.
      assert_equal(off["actions"], explicit["actions"])
      assert_equal(off["diagnostics"]["rankings"], explicit["diagnostics"]["rankings"])
      assert_equal(off["diagnostics"]["foe_visits"], explicit["diagnostics"]["foe_visits"])
    end
  end

  def test_the_prior_moves_the_trees_budget_towards_the_column_that_hits
    actions = [move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 }),
               move(0, "EMBER", 0, 100, 40, { "accuracy" => 100 })]
    snap = foe_axis_snap(actions)
    config = MCTS.merge({ "search_iterations" => 2000 })
    plain = PortableAI::Search.plan(snap, config, nil)["diagnostics"]
    primed = PortableAI::Search.plan(
      snap, config.merge({ "search_foe_prior" => true }), nil)["diagnostics"]
    assert_equal(plain["foe_options"], primed["foe_options"])
    quake = plain["foe_options"].index("stay:EARTHQUAKE")
    total = lambda { |d| d["foe_visits"].inject(0) { |sum, v| sum + v }.to_f }
    # Earthquake is the column that actually hurts, and the PUCT term buys it budget.
    assert_equal(true, primed["foe_visits"][quake] / total.call(primed) >
                       plain["foe_visits"][quake] / total.call(plain))
    # And the column priced at zero is still SAMPLED -- UCB1 sits underneath the
    # prior, so nothing is starved to nothing.
    rock = plain["foe_options"].index("stay:STEALTHROCK")
    assert_equal(true, primed["foe_visits"][rock] > 0)
    # Still one budget, still deterministic.
    assert_equal(2000, total.call(primed).to_i)
    assert_equal(primed["foe_visits"], PortableAI::Search.plan(
      snap, config.merge({ "search_foe_prior" => true }), nil)["diagnostics"]["foe_visits"])
  end

  def test_foe_options_are_one_column_per_move_and_fall_back_without_the_list
    snap = foe_axis_snap([])
    board = PortableAI::Search.opening_board(snap)
    options = PortableAI::Search.foe_options(snap, board)
    # Sorted by move id, because a Ruby 1.8 Hash has no order and a column list that
    # moved between two runs of one position would make every paired arm unrepeatable.
    assert_equal(["stay:EARTHQUAKE", "stay:SHADOWPUNCH", "stay:STEALTHROCK"],
                 options.map { |f| PortableAI::Search.foe_label(f) })
    assert_equal([60.0, 25.0, 0.0], options.map { |f| f["pct"] })
    # A cell with no in_moves -- an older adapter, and every Reborn run -- is the one
    # column at the best hit, which is 0.7.6 exactly.
    plain = search_snap([])
    assert_equal(["stay", "switch:1"], PortableAI::Search.foe_options(
      plain, PortableAI::Search.opening_board(plain)).map { |f| PortableAI::Search.foe_label(f) })
  end

  def test_the_foe_column_deals_its_own_move_not_the_best_one
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    snap = foe_axis_snap([tackle])
    board = PortableAI::Search.opening_board(snap)
    axis = PortableAI::Search.foe_options(snap, board)
    quake = axis.find { |f| f["move_id"] == "EARTHQUAKE" }
    rocks = axis.find { |f| f["move_id"] == "STEALTHROCK" }
    # Through 0.7.6 both of these were the same 60.
    assert_equal(60.0, PortableAI::Search.foe_damage(snap, board, board, tackle, quake))
    assert_equal(0.0, PortableAI::Search.foe_damage(snap, board, board, tackle, rocks))
    # And the move lands on whatever body is standing AFTER our switch resolves --
    # the mirror of own_damage pricing our move against their switch-in. Slot 1 takes
    # 10 from Earthquake where slot 0 took 60.
    leaving = { "type" => "switch", "slot" => 1, "candidate_hp_pct" => 100,
                "entry_damage_pct" => 0 }
    after = PortableAI::Search.project(snap, board, leaving, quake, true)
    assert_equal(1, after["own_slot"])
    assert_equal(90.0, after["own_hp"])
  end

  def test_maximin_still_answers_the_worst_column_so_mix_zero_barely_moves
    # The point of the axis is the EXPECTED reply and the tree, not pick_safest: the
    # worst thing the foe can do is still its biggest hit, so the min over the new
    # columns is the number the single column used to carry.
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    snap = foe_axis_snap([tackle])
    ranked = PortableAI::Search.plan(snap, ONE_PLY, nil)["diagnostics"]["rankings"][0]
    row = ranked[0]["search_row"]
    assert_equal(3, row.length)
    # Earthquake is the worst column for us and Stealth Rock the best.
    assert_equal(row.min, row[0])
    assert_equal(row.max, row[2])
    # The board after their best hit is the same board 0.7.6 scored, so the worst
    # case is unchanged: 100 - 60 HP on us.
    plain = PortableAI::Search.project(snap, PortableAI::Search.opening_board(snap),
                                       tackle, { "kind" => "stay" }, true)
    assert_equal(40.0, plain["own_hp"])
  end

  def test_the_predicted_stay_mass_spreads_over_every_move_column
    axis = [{ "kind" => "stay", "move_id" => "EARTHQUAKE" },
            { "kind" => "stay", "move_id" => "SHADOWPUNCH" },
            { "kind" => "switch", "slot" => 1 }]
    # The prediction says whether it stays, never which move it picks, so the mass
    # that is not a switch is shared. (Concentrating it on a predicted move is the
    # next arm; stock_move is already exported for it.)
    weights = PortableAI::Search.column_weights(axis, { "switch_chance" => 0.4 })
    assert_equal([0.3, 0.3, 0.4], weights)
    assert_equal(1.0, weights.inject(0.0) { |a, b| a + b })
    # Still uniform with nothing predicted, and still uniform on a column list that
    # has no switch to weigh the stay against.
    assert_equal([1.0 / 3, 1.0 / 3, 1.0 / 3], PortableAI::Search.column_weights(axis, nil))
  end

  def test_the_tree_sees_the_wider_foe_and_reports_it
    tackle = move(0, "TACKLE", 0, 100, 40, { "accuracy" => 100 })
    diag = PortableAI::Search.plan(foe_axis_snap([tackle]), MCTS, nil)["diagnostics"]
    assert_equal("mcts", diag["planner"])
    # Three columns the tree can tell apart, where 0.7.6 had one. (This foe has no
    # bench, so the axis here is moves alone -- which is the point being tested;
    # the mixed list is covered by the column_weights test above.)
    assert_equal(["stay:EARTHQUAKE", "stay:SHADOWPUNCH", "stay:STEALTHROCK"],
                 diag["foe_options"])
    assert_equal(3, diag["foe_visits"].length)
    assert_equal(400, diag["foe_visits"].inject(0) { |sum, v| sum + v })
    # And the foe's own payoff, not a table, is what spread those visits: the column
    # that hurts us most is the one it came back to.
    best = diag["foe_visits"].index(diag["foe_visits"].max)
    assert_equal("stay:EARTHQUAKE", diag["foe_options"][best])
  end
end
