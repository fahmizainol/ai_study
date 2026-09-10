# Dependency-free regressions; usable with the game's embedded Ruby or system Ruby.
root = File.expand_path("..", __dir__)
%w[model effects matrix core].each { |name| require File.join(root, "portable_ai", name) }

def check(condition, message)
  raise message unless condition
end

def attack(actor, slot, target, damage, extra = {})
  { "type" => "move", "actor_index" => actor, "slot" => slot,
    "move_id" => "TACKLE", "target" => target, "damaging" => true,
    "base_score" => 100, "expected_damage_pct" => damage,
    "accuracy" => 100, "priority" => 0 }.merge(extra)
end

def board(left, right)
  { "format" => "double", "actors" => [
      { "index" => 1, "hp_pct" => 100, "speed" => 100, "actions" => left },
      { "index" => 3, "hp_pct" => 100, "speed" => 50, "actions" => right }],
    "targets" => [{ "index" => 0, "hp_pct" => 100 }, { "index" => 2, "hp_pct" => 100 }] }
end

def plan(snap, enabled = true)
  PortableAI.plan(snap, {
    "doubles_outcomes" => enabled,
    "doubles_adversarial" => false
  }, Random.new(7))
end

def value(snap, overrides = {})
  actions = snap["actors"].map { |actor| actor["actions"][0].merge("outcome_scored" => true) }
  config = { "doubles_adversarial" => false }.merge(overrides)
  PortableAI.doubles_outcome_value(snap, actions, PortableAI::Model.config(config))
end

# Two individually weak hits must focus to secure a KO.
snap = board([attack(1, 0, 0, 60), attack(1, 1, 2, 60)],
             [attack(3, 0, 0, 60), attack(3, 1, 2, 60)])
check(plan(snap)["actions"].map { |a| a["target"] }.uniq.length == 1, "focus KO")
check(plan(snap, false)["actions"].map { |a| a["target"] }.uniq.length == 2, "control retains split rule")
snap["actors"].each { |a| a["actions"].each { |m| m["expected_damage_pct"] = 100 } }
check(plan(snap)["actions"].map { |a| a["target"] }.uniq.length == 2, "split two secured KOs")

wait = { "type" => "move", "actor_index" => 3, "slot" => 0, "move_id" => "SPLASH", "base_score" => 0 }
spread = attack(1, 0, nil, 120, { "spread" => true, "damage_by_target" => {
  "0" => { "damage_pct" => 60, "accuracy" => 100 },
  "2" => { "damage_pct" => 60, "accuracy" => 100 } } })
check(value(board([spread], [wait])) == 96, "spread damage cannot invent a KO")
spread["immune"] = true # first foe is immune; second still takes damage
spread["damage_by_target"]["0"]["damage_pct"] = 0
check(value(board([spread], [wait])) == 48, "first foe immunity must not reject entire spread")

snap = board([attack(1, 0, 0, 100, { "accuracy" => 50 })], [attack(3, 0, 0, 100)])
check(value(snap) == 500, "second hit provides insurance after a miss")
snap["actors"][1]["actions"][0]["accuracy"] = 50
check(value(snap) == 375, "two independent 50 percent hits give 75 percent KO")

quake = attack(1, 0, nil, 120, { "move_id" => "EARTHQUAKE", "spread" => true,
  "friendly_fire_pct" => 100, "partner_protect_blocks" => true,
  "damage_by_target" => { "0" => { "damage_pct" => 60 }, "2" => { "damage_pct" => 60 } } })
protect = { "type" => "move", "actor_index" => 3, "slot" => 0,
  "move_id" => "PROTECT", "priority" => 4, "base_score" => 100 }
snap = board([quake], [protect])
check(value(snap) == 96, "Protect prevents allied damage")
quake["partner_protect_blocks"] = false
check(value(snap) == -904, "bypassing attack still damages Protect user")
quake["partner_protect_blocks"] = true
protect["priority"] = -1
check(value(snap) == -904, "late Protect cannot undo a hit")
protect["priority"] = 4
snap["memory"] = { "3" => { "protect" => 1 } }
check(value(snap) == -904, "repeated Protect is not assumed guaranteed")

snap = board([quake], [attack(3, 0, 0, 100)])
check(value(snap) == -904, "fainted partner loses its attack")
snap["trick_room_active"] = true
check(value(snap) == -452, "Trick Room lets partner attack before friendly KO")
snap["trick_room_active"] = false
snap["actors"][1]["speed"] = 100
check(value(snap) == -678, "speed tie averages both allied orders")

snap = board([attack(1, 0, 0, 100)], [attack(3, 0, 0, 100)])
snap["targets"][0].merge!("full_hp" => true, "item" => "FOCUSSASH")
check(value(snap) == 500, "first hit breaks Sash and second finishes")
snap["actors"][1]["actions"] = [wait]
check(value(snap) < 100, "single hit cannot KO full-HP Sash")

# A plausible faster foe response can remove an action; Protect and priority change it.
snap = board([attack(1, 0, 0, 100)], [wait])
snap["targets"][0]["speed"] = 200
snap["actors"][0]["threats_by_foe"] = {
  "0" => { "damage_pct" => 100, "accuracy" => 100, "priority" => 0 } }
check(value(snap) == -500, "faster foe KO removes allied action")
snap["targets"][0]["attack_probability"] = 0.0
check(value(snap) == 500, "support prior permits a non-attacking foe turn")
snap["targets"][0]["utility_response"] = {
  "kind" => "field_speed", "move_id" => "TAILWIND", "priority" => 0, "value" => 104 }
check(value(snap, { "opponent_utility" => true }) == 396,
      "faster support foe establishes Tailwind before taking a KO")
snap["actors"][0]["actions"][0]["priority"] = 1
check(value(snap, { "opponent_utility" => true }) == 500,
      "priority KO prevents opponent utility action")
snap["actors"][0]["actions"][0]["priority"] = 0
snap["targets"][0]["utility_response"] = {
  "kind" => "protect", "move_id" => "PROTECT", "priority" => 4 }
check(value(snap, { "opponent_utility" => true }) == 0,
      "opponent Protect blocks a predicted hit")
snap["targets"][0]["attack_probability"] = 1.0
snap["targets"][0].delete("utility_response")
snap["actors"][0]["actions"][0]["priority"] = 1
check(value(snap) == 500, "priority KO removes foe response")
snap["actors"][0]["actions"] = [{ "type" => "move", "actor_index" => 1,
  "slot" => 0, "move_id" => "PROTECT", "priority" => 4, "base_score" => 100 }]
check(value(snap) == 0, "Protect blocks plausible foe response")

snap = board([attack(1, 0, 0, 60)], [wait])
snap["targets"][0]["attack_probability"] = 1.0
snap["targets"][1].merge!(
  "hp_pct" => 50, "speed" => 200, "attack_probability" => 0.0,
  "utility_response" => {
    "kind" => "redirect", "move_id" => "FOLLOWME", "priority" => 2 })
check(value(snap, { "opponent_utility" => true }) == 500,
      "predicted redirection changes the recipient of a single-target hit")

# Fake Out changes the shared timeline: the struck foe loses its action, allowing the
# partner's speed-control turn to resolve safely.
snap = board([attack(1, 0, 0, 10, { "move_id" => "FAKEOUT", "priority" => 3 })], [wait])
snap["targets"][0]["speed"] = 200
fake_out = snap["actors"][0]["actions"][0].merge("outcome_scored" => true)
tailwind = snap["actors"][1]["actions"][0]
foe_hit = { "foe_response" => true, "actor_index" => 0, "target" => 3,
  "expected_damage_pct" => 100, "accuracy" => 100, "priority" => 0, "speed" => 200 }
fake_value = PortableAI.doubles_timeline_value(
  snap, [fake_out, tailwind, foe_hit], { "fakeout_timeline" => true })
plain_hit = fake_out.merge("move_id" => "TACKLE")
plain_value = PortableAI.doubles_timeline_value(
  snap, [plain_hit, tailwind, foe_hit], { "fakeout_timeline" => true })
check(fake_value > plain_value, "Fake Out preserves partner action by flinching its foe")
check(PortableAI.doubles_timeline_value(snap, [fake_out, tailwind, foe_hit]) ==
      PortableAI.doubles_timeline_value(snap, [plain_hit, tailwind, foe_hit]),
      "disabled Fake Out timeline preserves the measured baseline")

# Stage A keeps strategically distinct candidates in its five-action beam even when
# their raw scores trail several ordinary attacks.
ordinary = (0..5).map do |slot|
  attack(1, slot, 0, 20 - slot).merge("score" => 200 - slot)
end
protect_candidate = { "type" => "move", "move_id" => "PROTECT", "score" => 50 }
redirect_candidate = { "type" => "move", "move_id" => "FOLLOWME", "score" => 40 }
speed_candidate = { "type" => "move", "move_id" => "TAILWIND", "score" => 30 }
switch_candidate = { "type" => "switch", "slot" => 4, "score" => 20 }
pruned = PortableAI.prune_doubles_candidates(
  ordinary + [protect_candidate, redirect_candidate, speed_candidate, switch_candidate], 5)
check(pruned.length == 5, "adversarial beam is bounded")
check(pruned.include?(ordinary[0]), "adversarial beam retains top raw action")
check(pruned.include?(protect_candidate), "adversarial beam retains Protect")
check(pruned.include?(redirect_candidate), "adversarial beam retains redirection")
check(pruned.include?(speed_candidate), "adversarial beam retains field speed")
check(pruned.include?(switch_candidate), "adversarial beam retains a switch")

weighted = [[100, 0.5], [-100, 0.5]]
check(PortableAI.robust_doubles_value(weighted) == -20,
      "robust response score charges for credible downside")
check(PortableAI.robust_doubles_value([[40, 1.0], [-1000, 0.0]]) == 40,
      "zero-probability responses cannot become the worst case")
check(PortableAI.doubles_search_response_value([[100, 0.5], [-100, 0.5]], 0.5) == -50,
      "doubles search blends the worst and expected reply")
check(PortableAI.doubles_search_response_value([[40, 1.0], [-1000, 0.0]], 0.5) == 40,
      "doubles search excludes impossible replies")

# Reject duplicate reserve slots structurally, even when scores exceed HARD_REJECT.
switch = { "type" => "switch", "slot" => 4, "base_score" => 2_000_000 }
snap = board([switch], [switch])
begin
  plan(snap)
  raise "duplicate switch pair selected"
rescue ArgumentError => e
  check(e.message == "no legal joint action pair", "unexpected error: #{e.message}")
end

# The new flag cannot change singles, including a spread action carrying adapter data.
single_spread = attack(1, 0, nil, 120, { "spread" => true,
  "target_hp_pct" => 100, "damage_by_target" => {
    "0" => { "damage_pct" => 60, "accuracy" => 100 } } })
snap = board([single_spread], [wait])
snap["actors"].pop
snap["targets"].pop
snap["format"] = "single"
check(plan(snap)["actions"] == plan(snap, false)["actions"], "singles unchanged")
check(PortableAI::Model.config({})["doubles_outcomes"] == true,
      "doubles outcome planner defaults on for playtesting")
check(PortableAI::Model.config({})["opponent_utility"] == false,
      "opponent utility experiment defaults off")
check(PortableAI::Model.config({})["fakeout_timeline"] == false,
      "Fake Out timeline experiment defaults off")
check(PortableAI::Model.config({})["doubles_adversarial"] == true,
      "adversarial doubles planner defaults on for playtesting")
check(PortableAI::Model.config({})["doubles_search"] == false,
      "Foul Play-shaped doubles search defaults off")
check(PortableAI::Model.config({})["doubles_search_leaf"] == false,
      "Foul Play doubles leaf ablation defaults off")
