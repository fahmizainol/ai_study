require "test/unit"

root = File.expand_path("..", File.dirname(__FILE__))
require File.join(root, "portable_ai", "model")
require File.join(root, "portable_ai", "effects")
require File.join(root, "portable_ai", "core")

# Minimal engine stubs matching the Reborn Yang surface the adapter touches at
# load/definition time and in the units under test.
class PokeBattle_Battle
  attr_accessor :doublebattle, :battlers, :choices, :opponent

  def initialize
    @doublebattle = false
    @battlers = [nil, nil, nil, nil]
    @choices = Array.new(4) { [0, 0, nil, -1] }
    @opponent = Object.new
  end

  def pbIsOpposing?(index)
    index.odd?
  end
end

class PokeBattle_AI
  MINIMUMSKILL = 1
  LOWSKILL = 10
  MEDIUMSKILL = 30
  HIGHSKILL = 60
  BESTSKILL = 100

  attr_accessor :battle, :mondata, :swappredicted, :aimondata

  def initialize(battle = nil)
    @battle = battle
    @aimondata = [nil, nil, nil, nil]
    @swappredicted = [-1, -1]
  end

  def chooseAction
    @host_choose_action_ran = true
  end

  def host_choose_action_ran
    @host_choose_action_ran
  end
end


# Constant namespaces the 0.5.0 exports read. Only the members under test are defined;
# every adapter helper that touches one is written to rescue a missing constant, which
# is what keeps the same file loadable in Realidea.
module PBAbilities
  GUTS = 1
  STURDY = 5
  INTIMIDATE = 22
  SERENEGRACE = 32
  MAGICGUARD = 98
  MOLDBREAKER = 104
  CONTRARY = 126
  MAGICBOUNCE = 156
  PRANKSTER = 158
  NAMES = { 1 => "Guts", 5 => "Sturdy", 22 => "Intimidate", 32 => "Serene Grace",
            98 => "Magic Guard", 104 => "Mold Breaker", 126 => "Contrary" }
  def self.getName(id); NAMES[id]; end
end

module PBItems
  WHITEHERB = 200
  LEFTOVERS = 234
  FOCUSSASH = 275
  HEAVYDUTYBOOTS = 849
  NAMES = { 200 => "White Herb", 234 => "Leftovers", 275 => "Focus Sash",
            849 => "Heavy-Duty Boots" }
  def self.getName(id); NAMES[id]; end
end

module PBStats
  ATTACK = 1
  DEFENSE = 2
  SPEED = 3
  SPATK = 4
  SPDEF = 5
end

module PBEffects
  ChoiceBand = 7
  Substitute = 12
  LeechSeed = 13
  PerishSong = 20
  Yawn = 24
  Wish = 25
  # Reborn's own "the move that just ran failed" flag, kept for Stomping Tantrum
  # (PokeBattle_Battler.rb:5085). A boolean, not a counter.
  Tantrum = 26
end

module PBTypes
  NORMAL = 0
  FIRE = 1
  WATER = 2
  ELECTRIC = 3
  GRASS = 4
  FLYING = 9
  DARK = 16
end

require File.join(root, "adapters", "reborn", "Portable_AI_Adapter")

class PortableAIRebornAdapterTest < Test::Unit::TestCase
  MonData = Struct.new(:skill)

  def setup
    $PORTABLE_AI_ENABLED = false
    $PORTABLE_AI_CONFIG = nil
  end

  def teardown
    $PORTABLE_AI_ENABLED = false
    $PORTABLE_AI_CONFIG = nil
  end

  def test_best_skill_is_deterministic_and_coordinated
    config = PortableAIReborn.config_for(PokeBattle_AI::BESTSKILL)
    assert_equal(true, config["deterministic"])
    assert_equal(true, config["coordination"])
    assert_equal(0, config["noise"])
  end

  def test_skill_thresholds_use_reborn_tiers
    assert_equal(false, PortableAIReborn.config_for(59)["memory"])
    assert_equal(true, PortableAIReborn.config_for(60)["memory"])
    assert_equal(false, PortableAIReborn.config_for(29)["switching"])
  end

  def test_run_overrides_reach_the_core_config_without_disturbing_skill_tiers
    $PORTABLE_AI_CONFIG = { "switch_risk_weight" => 0.0 }
    config = PortableAIReborn.config_for(PokeBattle_AI::BESTSKILL)
    assert_equal(0.0, config["switch_risk_weight"])
    assert_equal(true, config["deterministic"])
    assert_equal(true, config["memory"])
  end

  def test_absent_overrides_leave_the_config_alone
    assert_equal(false, PortableAIReborn.config_for(PokeBattle_AI::BESTSKILL)
                                       .key?("switch_risk_weight"))
  end

  def test_disabled_hook_runs_host_choose_action_untouched
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    ai.chooseAction
    assert_equal(true, ai.host_choose_action_ran)
  end

  def test_marker_override_enables_opposing_side_only
    $PORTABLE_AI_ENABLED = true
    battle = PokeBattle_Battle.new
    assert_equal(true, PortableAIReborn.enabled_for?(battle, 1))
    assert_equal(false, PortableAIReborn.enabled_for?(battle, 0))
  end

  def test_trainer_marking_survives_side_swaps
    $PORTABLE_AI_ENABLED = true
    battle = PokeBattle_Battle.new
    ours = Object.new
    theirs = Object.new
    owners = { 1 => ours, 3 => ours }
    battle.define_singleton_method(:pbGetOwner) { |i| owners[i] }
    $PORTABLE_AI_TRAINER = ours
    assert_equal(true, PortableAIReborn.enabled_for?(battle, 1))
    # After the test environment's switchTrainers, the odd side belongs to the OTHER
    # trainer — the portable AI must refuse to drive it.
    owners[1] = theirs
    assert_equal(false, PortableAIReborn.enabled_for?(battle, 1))
  ensure
    $PORTABLE_AI_TRAINER = nil
  end

  def test_skill_for_reads_aimondata_and_defaults_to_best
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    ai.aimondata[1] = MonData.new(60)
    assert_equal(60, PortableAIReborn.skill_for(ai, 1))
    assert_equal(PokeBattle_AI::BESTSKILL, PortableAIReborn.skill_for(ai, 3))
  end

  def test_consecutive_setup_memory_increments
    battle = PokeBattle_Battle.new
    action = { "type" => "move", "move_id" => "SWORDSDANCE", "tags" => ["setup"] }
    PortableAIReborn.apply_memory(battle, 1, action)
    PortableAIReborn.apply_memory(battle, 1, action)
    memory = battle.instance_variable_get(:@portable_ai_memory)
    assert_equal(2, memory["1"]["setup"])
  end

  def test_error_in_portable_side_is_reraised_not_swallowed
    $PORTABLE_AI_ENABLED = true
    battle = PokeBattle_Battle.new
    battler = Object.new
    def battler.isFainted?; false; end
    battle.battlers[1] = battler
    def battle.pbCanShowCommands?(_i); true; end
    ai = PokeBattle_AI.new(battle)
    # No moves/party stubs beyond this point: pending_indices reaches
    # any_choosable_move?/has_legal_switch?, both rescue to false, so the battler is
    # skipped — but a failure INSIDE choose_all must re-raise. Force one directly.
    def PortableAIReborn.build_snapshot(_ai, _battle, _indices)
      raise "boom"
    end
    begin
      assert_raise(RuntimeError) do
        PortableAIReborn.choose_all(ai, battle, [1])
      end
    ensure
      class << PortableAIReborn
        remove_method :build_snapshot
      end
    end
  end

  # --- 0.4.0 exports ---------------------------------------------------------------

  def speed_battler(value)
    battler = Object.new
    battler.define_singleton_method(:pbSpeed) { value }
    battler
  end

  def test_rough_accuracy_reads_the_engine_primitive
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    def ai.pbRoughAccuracy(_move, _attacker, _opponent); 85; end
    assert_equal(85.0, PortableAIReborn.rough_accuracy(ai, Object.new, Object.new,
                                                       Object.new))
  end

  # An engine without the primitive must yield nil, not 0: the core reads nil as
  # "no accuracy information" and a 0 as "this move almost never hits".
  def test_rough_accuracy_is_nil_when_the_primitive_is_unavailable
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    assert_nil(PortableAIReborn.rough_accuracy(ai, Object.new, Object.new, Object.new))
    assert_nil(PortableAIReborn.rough_accuracy(ai, Object.new, Object.new, nil))
  end

  def test_speed_order_follows_reborns_strict_comparison
    battle = PokeBattle_Battle.new
    battle.battlers[0] = speed_battler(120)
    assert_equal(true,  PortableAIReborn.faster_than_foes?(battle, 130, [0]))
    assert_equal(false, PortableAIReborn.faster_than_foes?(battle, 90, [0]))
    # pbAIfaster? uses <, so a tie is not faster.
    assert_equal(false, PortableAIReborn.faster_than_foes?(battle, 120, [0]))
  end

  def test_speed_order_is_nil_without_both_speeds
    battle = PokeBattle_Battle.new
    battle.battlers[0] = speed_battler(120)
    assert_nil(PortableAIReborn.faster_than_foes?(battle, nil, [0]))
    assert_nil(PortableAIReborn.faster_than_foes?(battle, 130, []))
  end

  def test_speed_order_is_measured_against_the_fastest_foe
    battle = PokeBattle_Battle.new
    battle.battlers[0] = speed_battler(80)
    battle.battlers[2] = speed_battler(140)
    assert_equal(false, PortableAIReborn.faster_than_foes?(battle, 100, [0, 2]))
    assert_equal(true,  PortableAIReborn.faster_than_foes?(battle, 150, [0, 2]))
  end

  def test_trick_room_inverts_speed_order
    battle = PokeBattle_Battle.new
    battle.battlers[0] = speed_battler(120)
    def battle.trickroom; 5; end
    assert_equal(true,  PortableAIReborn.faster_than_foes?(battle, 90, [0]))
    assert_equal(false, PortableAIReborn.faster_than_foes?(battle, 130, [0]))
  end

  # --- 0.5.0 exports ----------------------------------------------------------------

  class FakeMove
    attr_reader :function, :addlEffect, :basedamage, :id, :priority
    def initialize(function, addl, basedamage, id = 1)
      @function = function
      @addlEffect = addl
      @basedamage = basedamage
      @id = id
      @priority = 0
    end
  end

  def plain_battler(ability = nil, item = nil)
    b = Object.new
    b.define_singleton_method(:ability) { ability }
    b.define_singleton_method(:item) { item }
    b.define_singleton_method(:isFainted?) { false }
    b.define_singleton_method(:pbPartner) { nil }
    b
  end

  # The whole move-side-effect table is one lookup on the engine's own function code,
  # which is what replaces ~80 hand-tagged move names.
  def test_function_code_map_names_the_kind_and_the_stat
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    def ai.secondaryEffectNegated?(_m, _a, _o); false; end
    user = plain_battler
    foe = plain_battler
    kind, stat, chance = PortableAIReborn.move_effect(ai, FakeMove.new(0x0A, 30, 80), user, foe)
    assert_equal(["burn", nil, 30], [kind, stat, chance])
    kind, stat, _ = PortableAIReborn.move_effect(ai, FakeMove.new(0x44, 100, 60), user, foe)
    assert_equal(["drop", "speed"], [kind, stat])
    kind, stat, _ = PortableAIReborn.move_effect(ai, FakeMove.new(0x46, 10, 90), user, foe)
    assert_equal(["drop", "spd"], [kind, stat])
  end

  def test_unmapped_function_code_reports_no_effect
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    assert_equal([nil, nil, nil],
                 PortableAIReborn.move_effect(ai, FakeMove.new(0x000, 0, 80),
                                              plain_battler, plain_battler))
  end

  # A status MOVE carries addlEffect 0 because the status is the whole move, not a
  # secondary; reporting 0 there would switch the row off entirely.
  def test_status_move_effect_chance_is_certain_not_zero
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    _, _, chance = PortableAIReborn.move_effect(ai, FakeMove.new(0x0A, 0, 0),
                                                plain_battler, plain_battler)
    assert_equal(100, chance)
  end

  def test_serene_grace_doubles_the_chance_and_negation_zeroes_it
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    def ai.secondaryEffectNegated?(_m, _a, _o); false; end
    user = plain_battler(PBAbilities::SERENEGRACE)
    _, _, chance = PortableAIReborn.move_effect(ai, FakeMove.new(0x0A, 30, 80),
                                                user, plain_battler)
    assert_equal(60, chance)

    negating = PokeBattle_AI.new(PokeBattle_Battle.new)
    def negating.secondaryEffectNegated?(_m, _a, _o); true; end
    _, _, zero = PortableAIReborn.move_effect(negating, FakeMove.new(0x0A, 30, 80),
                                              plain_battler, plain_battler)
    assert_equal(0, zero)
  end

  def test_mold_breaker_family_is_recognised_by_name
    assert_equal(true, PortableAIReborn.mold_breaker?(plain_battler(PBAbilities::MOLDBREAKER)))
    assert_equal(false, PortableAIReborn.mold_breaker?(plain_battler(PBAbilities::GUTS)))
  end

  def test_ability_and_item_names_are_plain_uppercase_strings
    assert_equal("MAGICGUARD", PortableAIReborn.ability_key(plain_battler(PBAbilities::MAGICGUARD)))
    assert_equal("HEAVYDUTYBOOTS", PortableAIReborn.item_key(plain_battler(nil, PBItems::HEAVYDUTYBOOTS)))
    assert_nil(PortableAIReborn.ability_key(plain_battler(nil)))
    assert_nil(PortableAIReborn.item_key(plain_battler(nil, 0)))
  end

  # The engine's own can-status check replaces the hand-written type list, and its
  # answer wins: it knows about terrain, Safeguard and a dozen abilities the list does
  # not. When the primitive is missing the list is still there.
  def test_status_block_asks_the_engine_before_the_type_list
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    target = plain_battler
    target.define_singleton_method(:pbCanBurn?) { |_show| false }
    assert_equal(true, PortableAIReborn.status_blocked?(
      ai, FakeMove.new(0x0A, 0, 0), ["status", "burn"], plain_battler, target))
    willing = plain_battler
    willing.define_singleton_method(:pbCanBurn?) { |_show| true }
    willing.define_singleton_method(:pbHasType?) { |_sym| true }   # a Fire type
    # The engine says yes, so the old "Fire types cannot burn" list must not override.
    assert_equal(false, PortableAIReborn.status_blocked?(
      ai, FakeMove.new(0x0A, 0, 0), ["status", "burn"], plain_battler, willing))
  end

  def test_type_list_still_blocks_when_the_engine_primitive_is_missing
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    target = plain_battler
    target.define_singleton_method(:pbHasType?) { |sym| sym == :FIRE }
    assert_equal(true, PortableAIReborn.status_blocked?(
      ai, FakeMove.new(0x0A, 0, 0), ["status", "burn"], plain_battler, target))
  end

  def test_magic_bounce_blocks_every_status_move
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    bouncer = plain_battler(PBAbilities::MAGICBOUNCE)
    bouncer.define_singleton_method(:pbCanBurn?) { |_show| true }
    assert_equal(true, PortableAIReborn.status_blocked?(
      ai, FakeMove.new(0x0A, 0, 0), ["status", "burn"], plain_battler, bouncer))
  end

  def test_prankster_status_is_dead_into_a_dark_type
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    user = plain_battler(PBAbilities::PRANKSTER)
    dark = plain_battler
    dark.define_singleton_method(:pbHasType?) { |sym| sym == :DARK }
    dark.define_singleton_method(:pbCanBurn?) { |_show| true }
    assert_equal(true, PortableAIReborn.status_blocked?(
      ai, FakeMove.new(0x0A, 0, 0), ["status", "burn"], user, dark))
    plain = plain_battler
    plain.define_singleton_method(:pbHasType?) { |_sym| false }
    plain.define_singleton_method(:pbCanBurn?) { |_show| true }
    assert_equal(false, PortableAIReborn.status_blocked?(
      ai, FakeMove.new(0x0A, 0, 0), ["status", "burn"], user, plain))
  end

  # Leech Seed carries the "status" tag but sets no status CONDITION -- it writes
  # PBEffects::LeechSeed -- so neither the core's major-status guard nor any pbCanX?
  # predicate ever saw it, and a seeded foe looked fresh: the move kept collecting
  # fresh_status+25 and the engine kept returning "failed". These four mirror
  # PokeBattle_Move_0DC#pbEffect (PokeBattle_MoveEffects.rb:6194) exactly.
  #
  # The tags come from Effects.describe, the SAME call the action builder makes
  # (Portable_AI_Adapter.rb:597). Hand-writing ["status", "drain"] here would let the
  # rule pass a test it never fires on in a real battle.
  LEECH_TAGS = PortableAI::Effects.describe("LEECHSEED", []).freeze

  def seed_target(seeded = false, sub = false, grass = false)
    t = plain_battler
    fx = Hash.new(0)
    fx[PBEffects::LeechSeed]  = seeded ? 0 : -1
    fx[PBEffects::Substitute] = sub ? 1 : 0
    t.define_singleton_method(:effects) { fx }
    t.define_singleton_method(:pbHasType?) { |sym| grass && sym == :GRASS }
    t
  end

  def leech_blocked?(target)
    PortableAIReborn.status_blocked?(
      PokeBattle_AI.new(PokeBattle_Battle.new),
      FakeMove.new(0xDC, 0, 0), LEECH_TAGS, plain_battler, target)
  end

  def test_leech_seed_is_live_against_a_fresh_target
    assert_equal(false, leech_blocked?(seed_target))
  end

  def test_leech_seed_is_blocked_on_an_already_seeded_target
    assert_equal(true, leech_blocked?(seed_target(true)))
  end

  def test_leech_seed_is_blocked_by_a_substitute
    assert_equal(true, leech_blocked?(seed_target(false, true)))
  end

  def test_leech_seed_is_blocked_against_a_grass_type
    assert_equal(true, leech_blocked?(seed_target(false, false, true)))
  end

  # A secondary that cannot land is worth nothing -- the check status_blocked? makes
  # for a status MOVE, applied to a damaging move's secondary as well.
  def test_secondary_chance_is_zero_when_the_target_cannot_take_the_status
    ai = PokeBattle_AI.new(PokeBattle_Battle.new)
    def ai.secondaryEffectNegated?(_m, _a, _o); false; end
    fireproof = plain_battler
    fireproof.define_singleton_method(:pbCanBurn?) { |_show| false }
    _, _, chance = PortableAIReborn.move_effect(ai, FakeMove.new(0x0A, 30, 80),
                                                plain_battler, fireproof)
    assert_equal(0, chance)
  end

  # Boots and Magic Guard walk over hazards, so a party wearing them is a party the
  # hazard move cannot touch.
  def test_hazard_target_count_excludes_boots_and_magic_guard
    battle = PokeBattle_Battle.new
    bare = plain_battler
    bare.define_singleton_method(:hp) { 100 }
    bare.define_singleton_method(:isEgg?) { false }
    booted = plain_battler(nil, PBItems::HEAVYDUTYBOOTS)
    booted.define_singleton_method(:hp) { 100 }
    booted.define_singleton_method(:isEgg?) { false }
    guarded = plain_battler(PBAbilities::MAGICGUARD)
    guarded.define_singleton_method(:hp) { 100 }
    guarded.define_singleton_method(:isEgg?) { false }
    party = [bare, booted, guarded]
    battle.define_singleton_method(:pbParty) { |_i| party }
    assert_equal(1, PortableAIReborn.hazard_target_count(battle, "SPIKES", 1))
  end

  # A Choice lock is the strongest certainty the threat model can have: the foe cannot
  # use anything else. Reborn reads it for switch-ins and not for moves; this is the
  # export that fixes the second half.
  def test_choice_locked_foe_contributes_only_the_locked_move
    battle = PokeBattle_Battle.new
    ai = PokeBattle_AI.new(battle)
    def ai.pbRoughDamage(move, _a, _t, _x, _y); move.id * 10; end
    foe = plain_battler
    effects = Array.new(40, -1)
    effects[PBEffects::ChoiceBand] = 7
    foe.define_singleton_method(:effects) { effects }
    foe.define_singleton_method(:moves) { [FakeMove.new(0x00, 0, 80, 7),
                                           FakeMove.new(0x00, 0, 80, 9)] }
    battle.battlers[0] = foe
    us = plain_battler
    us.define_singleton_method(:totalhp) { 100 }
    map = PortableAIReborn.incoming_damage_by_move(ai, battle, us, [0])
    assert_equal(["0:7"], map.keys)
  end

  def test_unlocked_foe_contributes_every_move
    battle = PokeBattle_Battle.new
    ai = PokeBattle_AI.new(battle)
    def ai.pbRoughDamage(move, _a, _t, _x, _y); move.id * 10; end
    foe = plain_battler
    effects = Array.new(40, -1)
    foe.define_singleton_method(:effects) { effects }
    foe.define_singleton_method(:moves) { [FakeMove.new(0x00, 0, 80, 7),
                                           FakeMove.new(0x00, 0, 80, 9)] }
    battle.battlers[0] = foe
    us = plain_battler
    us.define_singleton_method(:totalhp) { 100 }
    assert_equal(["0:7", "0:9"].sort,
                 PortableAIReborn.incoming_damage_by_move(ai, battle, us, [0]).keys.sort)
  end

  # The entry estimate is a real damage roll against a fake battler, with the
  # candidate's own Intimidate applied to the foes first and restored afterwards --
  # the stage mutation is Reborn's own (:11586/:11617) and leaking it would corrupt
  # every later estimate in the same turn.
  def test_intimidate_lowers_the_entry_estimate_and_restores_the_stage
    battle = PokeBattle_Battle.new
    ai = PokeBattle_AI.new(battle)
    def ai.pbMakeFakeBattler(pokemon); pokemon; end
    def ai.pbRoughDamage(_move, attacker, target, _x, _y)
      50 * (2 + attacker.stages[PBStats::ATTACK])
    end
    foe = plain_battler
    stages = Array.new(8, 0)
    foe.define_singleton_method(:stages) { stages }
    foe.define_singleton_method(:moves) { [FakeMove.new(0x00, 0, 80, 1)] }
    foe.define_singleton_method(:pbCanReduceStatStage?) { |_stat| true }
    battle.battlers[0] = foe

    scary = plain_battler
    scary.define_singleton_method(:totalhp) { 100 }
    plain = PortableAIReborn.switch_incoming_damage(ai, battle, scary, [0])

    intimidating = plain_battler(PBAbilities::INTIMIDATE)
    intimidating.define_singleton_method(:totalhp) { 100 }
    softened = PortableAIReborn.switch_incoming_damage(ai, battle, intimidating, [0])

    assert_equal(100.0, plain)
    assert_equal(50.0, softened)
    assert_equal(0, stages[PBStats::ATTACK])
  end

  # Clear Body and friends are honoured through the engine's own refusal, not through
  # a list carried here -- which is the correction Phase A made to the plan.
  def test_intimidate_is_ignored_when_the_engine_refuses_the_drop
    battle = PokeBattle_Battle.new
    ai = PokeBattle_AI.new(battle)
    def ai.pbMakeFakeBattler(pokemon); pokemon; end
    def ai.pbRoughDamage(_move, attacker, target, _x, _y)
      50 * (2 + attacker.stages[PBStats::ATTACK])
    end
    foe = plain_battler
    stages = Array.new(8, 0)
    foe.define_singleton_method(:stages) { stages }
    foe.define_singleton_method(:moves) { [FakeMove.new(0x00, 0, 80, 1)] }
    foe.define_singleton_method(:pbCanReduceStatStage?) { |_stat| false }
    battle.battlers[0] = foe
    intimidating = plain_battler(PBAbilities::INTIMIDATE)
    intimidating.define_singleton_method(:totalhp) { 100 }
    assert_equal(100.0, PortableAIReborn.switch_incoming_damage(ai, battle, intimidating, [0]))
  end

  def test_entry_hazard_cost_is_zero_for_boots_and_magic_guard
    side = Object.new
    side.define_singleton_method(:effects) { Array.new(40, 0) }
    battler = plain_battler
    battler.define_singleton_method(:pbOwnSide) { side }
    booted = plain_battler(nil, PBItems::HEAVYDUTYBOOTS)
    assert_equal(0, PortableAIReborn.entry_hazard_pct(booted, battler))
    guarded = plain_battler(PBAbilities::MAGICGUARD)
    assert_equal(0, PortableAIReborn.entry_hazard_pct(guarded, battler))
  end
  # --- 0.6.0 threats_by_foe ------------------------------------------------
  # A foe stub with a moveset the adapter can walk. rough_damage_pct is bypassed by
  # seeding incoming_map, which is what build_actor really passes in.
  def threat_foe(speed, moves)
    foe = Object.new
    foe.define_singleton_method(:pbSpeed) { speed }
    foe.define_singleton_method(:isFainted?) { false }
    foe.define_singleton_method(:moves) { moves }
    # ChoiceBand is -1 when free; a Hash.new(0) here would read as "locked into move 0"
    # and silently drop every move from the summary.
    free = Hash.new(0)
    free[PBEffects::ChoiceBand] = -1
    foe.define_singleton_method(:effects) { free }
    foe
  end

  def threat_move(id, priority)
    move = Object.new
    move.define_singleton_method(:id) { id }
    move.define_singleton_method(:priority) { priority }
    move.define_singleton_method(:pbIsPriorityMoveAI) { |_u| priority > 0 }
    move
  end

  def test_threats_by_foe_keeps_the_best_priority_hit_separate
    battle = PokeBattle_Battle.new
    battle.battlers[0] = threat_foe(90, [threat_move(1, 0), threat_move(2, 1)])
    me = speed_battler(100)
    map = { "0:1" => 60.0, "0:2" => 25.0 }
    out = PortableAIReborn.threats_by_foe(nil, battle, me, [0], map)
    assert_equal(60.0, out["0"]["damage_pct"])
    assert_equal(25.0, out["0"]["priority_damage_pct"])
    assert_equal(true, out["0"]["faster"])
  end

  # The reason the export exists: actor["faster"] is against the FASTEST foe, so in a
  # doubles board where the actor outruns one foe and not the other it is a single
  # false and a race computed off it is wrong for the slower target.
  def test_threats_by_foe_orders_against_each_foe_separately
    battle = PokeBattle_Battle.new
    battle.battlers[0] = threat_foe(90, [threat_move(1, 0)])
    battle.battlers[2] = threat_foe(150, [threat_move(3, 0)])
    me = speed_battler(100)
    map = { "0:1" => 40.0, "2:3" => 40.0 }
    out = PortableAIReborn.threats_by_foe(nil, battle, me, [0, 2], map)
    assert_equal(true,  out["0"]["faster"])
    assert_equal(false, out["2"]["faster"])
    # ... where the single flag the actor carries is false for both.
    assert_equal(false, PortableAIReborn.faster_than_foes?(battle, 100, [0, 2]))
  end

  def test_threats_by_foe_inherits_the_choice_lock
    battle = PokeBattle_Battle.new
    foe = threat_foe(90, [threat_move(1, 0), threat_move(2, 0)])
    locked = { PBEffects::ChoiceBand => 2 }
    locked.default = 0
    foe.define_singleton_method(:effects) { locked }
    battle.battlers[0] = foe
    map = { "0:2" => 25.0 }
    out = PortableAIReborn.threats_by_foe(nil, battle, speed_battler(100), [0], map)
    assert_equal(25.0, out["0"]["damage_pct"])
  end

  # ---------------------------------------------------------------------------
  # 0.6.2 adapter-side rules.
  # ---------------------------------------------------------------------------

  # Yawn is Leech Seed's twin: tagged ["status", "sleep"] (effects.rb), so the engine
  # check the adapter runs is pbCanSleep?, which answers about the status CONDITION and
  # says yes about a target that is merely drowsy. The engine's real second guard is a
  # separate line in PokeBattle_Move_004#pbEffect (PokeBattle_MoveEffects.rb:249).
  #
  # Tags come from Effects.describe, the same call the action builder makes: the
  # "drowsy" tag has to actually be on YAWN in the shipped table or the rule never
  # fires in a battle no matter what this asserts.
  YAWN_TAGS = PortableAI::Effects.describe("YAWN", []).freeze
  HYPNOSIS_TAGS = PortableAI::Effects.describe("HYPNOSIS", []).freeze

  def drowsy_target(drowsy, can_sleep = true)
    t = plain_battler
    fx = Hash.new(0)
    fx[PBEffects::Yawn] = drowsy ? 2 : 0
    t.define_singleton_method(:effects) { fx }
    t.define_singleton_method(:pbCanSleep?) { |_show| can_sleep }
    t.define_singleton_method(:pbHasType?) { |_sym| false }
    t
  end

  def sleep_blocked?(target, tags = YAWN_TAGS)
    PortableAIReborn.status_blocked?(
      PokeBattle_AI.new(PokeBattle_Battle.new),
      FakeMove.new(0x04, 0, 0), tags, plain_battler, target)
  end

  def test_yawn_carries_its_own_tag_in_the_shipped_table
    assert(YAWN_TAGS.include?("drowsy"))
    assert(YAWN_TAGS.include?("sleep"))
    assert_equal(false, HYPNOSIS_TAGS.include?("drowsy"))
  end

  def test_yawn_is_live_against_a_target_that_is_not_drowsy
    assert_equal(false, sleep_blocked?(drowsy_target(false)))
  end

  def test_yawn_is_blocked_against_an_already_drowsy_target
    assert_equal(true, sleep_blocked?(drowsy_target(true)))
  end

  # The engine check still owns everything it already knew: a target that cannot sleep
  # at all is blocked whether or not it is drowsy.
  def test_yawn_still_defers_to_the_engine_sleep_check
    assert_equal(true, sleep_blocked?(drowsy_target(false, false)))
  end

  # Hypnosis writes the status condition directly, so a drowsy target is a legal
  # target for it. Only Yawn carries the extra guard.
  def test_hypnosis_is_unaffected_by_the_drowsy_clause
    assert_equal(false, sleep_blocked?(drowsy_target(true), HYPNOSIS_TAGS))
  end

  def test_yawn_gate_off_restores_the_0_6_1_re_click
    $PORTABLE_AI_CONFIG = { "yawn_gate" => false }
    assert_equal(false, sleep_blocked?(drowsy_target(true)))
  ensure
    $PORTABLE_AI_CONFIG = nil
  end

  # Wish reported through the same channel the screens use.
  def wish_battler(pending)
    b = plain_battler
    fx = Hash.new(0)
    fx[PBEffects::Wish] = pending ? 2 : 0
    b.define_singleton_method(:effects) { fx }
    b.define_singleton_method(:pbOwnSide) { Object.new }
    b
  end

  def test_wish_is_reported_active_only_while_one_is_pending
    assert_equal(true, PortableAIReborn.effect_active?(wish_battler(true), "WISH"))
    assert_equal(false, PortableAIReborn.effect_active?(wish_battler(false), "WISH"))
  end

  # The durable "I have already set up" record, which the memory counter is not.
  def test_positive_stage_total_counts_only_the_boosts
    b = plain_battler
    stages = [0, 2, 0, 1, 0, -2, 0, 0]
    b.define_singleton_method(:stages) { stages }
    assert_equal(3, PortableAIReborn.positive_stages(b))
  end

  # failed_last_turn? is Reborn's Tantrum flag ANDed with the portable memory's record
  # of what was clicked at whom. Both halves have to line up: Tantrum alone only says
  # that something failed.
  def failed_battler(tantrum)
    b = plain_battler
    fx = Hash.new(0)
    fx[PBEffects::Tantrum] = tantrum
    b.define_singleton_method(:effects) { fx }
    b.define_singleton_method(:index) { 1 }
    b
  end

  def failed_case(tantrum, last_move, last_species, target_species)
    battle = PokeBattle_Battle.new
    battle.instance_variable_set(
      :@portable_ai_memory,
      { "1" => { "last_move" => last_move, "last_target_species" => last_species } })
    target = plain_battler
    target.define_singleton_method(:species) { target_species }
    PortableAIReborn.failed_last_turn?(battle, failed_battler(tantrum),
                                       "SUCKERPUNCH", target)
  end

  def test_a_repeat_of_the_move_that_failed_at_the_same_target_is_reported
    assert_equal(true, failed_case(true, "SUCKERPUNCH", 500, 500))
  end

  def test_nothing_is_reported_when_the_engine_says_the_move_worked
    assert_equal(false, failed_case(false, "SUCKERPUNCH", 500, 500))
  end

  def test_a_different_move_is_not_charged_for_the_failure
    assert_equal(false, failed_case(true, "KNOCKOFF", 500, 500))
  end

  def test_the_failure_does_not_carry_to_a_target_that_switched_in
    assert_equal(false, failed_case(true, "SUCKERPUNCH", 500, 501))
  end

  def test_no_memory_at_all_reports_nothing
    battle = PokeBattle_Battle.new
    assert_equal(false,
                 PortableAIReborn.failed_last_turn?(battle, failed_battler(true),
                                                    "SUCKERPUNCH", nil))
  end
end
