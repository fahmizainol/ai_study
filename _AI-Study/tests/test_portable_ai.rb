require "test/unit"

root = File.expand_path("..", File.dirname(__FILE__))
require File.join(root, "portable_ai", "model")
require File.join(root, "portable_ai", "effects")
require File.join(root, "portable_ai", "core")

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
end
