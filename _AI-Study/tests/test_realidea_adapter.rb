require "test/unit"

root = File.expand_path("..", File.dirname(__FILE__))
require File.join(root, "portable_ai", "model")
require File.join(root, "portable_ai", "effects")
require File.join(root, "portable_ai", "core")

# ---------------------------------------------------------------------------
# Engine stubs. Constant VALUES are Realidea's own (075_PBEffects.rb,
# 069_PBStats.rb, 077_PBTargets.rb), so an index the adapter reads through the
# wrong namespace shows up here rather than in the game.
# ---------------------------------------------------------------------------
module PBTrainerAI
  def self.mediumSkill; 32; end
  def self.highSkill; 48; end
  def self.bestSkill; 100; end
end

module PBStats
  HP = 0; ATTACK = 1; DEFENSE = 2; SPEED = 3; SPATK = 4; SPDEF = 5
  ACCURACY = 6; EVASION = 7
end

module PBStatuses
  SLEEP = 1; POISON = 2; BURN = 3; PARALYSIS = 4; FROZEN = 5
end

module PBTypes
  NORMAL = 0; FIGHTING = 1; FLYING = 2; POISON = 3; GROUND = 4; ROCK = 5
  BUG = 6; GHOST = 7; STEEL = 8; FIRE = 9; WATER = 10; GRASS = 11
  ELECTRIC = 12; PSYCHIC = 13; ICE = 14; DRAGON = 15; DARK = 16; FAIRY = 17

  # 8 is neutral here: three type slots, each contributing 2 (066_PBTypes_Extra.rb:28).
  def self.getCombinedEffectiveness(attack, t1, t2 = nil, t3 = nil)
    mod1 = single(attack, t1)
    mod2 = (t2.nil? || t2 < 0 || t2 == t1) ? 2 : single(attack, t2)
    mod3 = (t3.nil? || t3 < 0 || t3 == t1 || t3 == t2) ? 2 : single(attack, t3)
    mod1 * mod2 * mod3
  end

  def self.single(attack, defender)
    return 2 if defender.nil? || defender < 0
    return 0 if attack == ELECTRIC && defender == GROUND
    return 4 if attack == WATER && defender == FIRE
    return 1 if attack == FIRE && defender == WATER
    2
  end
end

module PBEffects
  # Battler effects.
  Attract = 1; ChoiceBand = 7; LeechSeed = 43; MeanLook = 50; PerishSong = 66
  Substitute = 91; Toxic = 95; Type3 = 99; Wish = 105; Yawn = 108
  # Side effects (own array, so the index reuse below is Realidea's own).
  LightScreen = 4; Rainbow = 9; Reflect = 10; Safeguard = 12; Spikes = 14
  StealthRock = 15; StickyWeb = 16; Tailwind = 18; ToxicSpikes = 19
  # Field effects.
  TrickRoom = 10
end

module PBTargets
  SingleNonUser = 0x00; NoTarget = 0x01; RandomOpposing = 0x02
  AllOpposing = 0x04; AllNonUsers = 0x08; User = 0x10
  Partner = 0x100; UserOrPartner = 0x200; SingleOpposing = 0x400
  OppositeOpposing = 0x800

  def self.hasMultipleTargets?(move)
    move.target == AllOpposing || move.target == AllNonUsers
  end
end

module PBAbilities
  STURDY = 5; INTIMIDATE = 22; SERENEGRACE = 32; LEVITATE = 26; SHIELDDUST = 19
  MAGICGUARD = 98; MOLDBREAKER = 104; SHEERFORCE = 125; CONTRARY = 126
  MAGICBOUNCE = 156; PRANKSTER = 158; GALEWINGS = 177; TRIAGE = 209
  UNAWARE = 109
end

module PBItems
  WHITEHERB = 200; LEFTOVERS = 234; FOCUSSASH = 275
end

module PBMoves
  POUND = 1; TACKLE = 2; THUNDERWAVE = 3; TOXIC = 4; LEECHSEED = 5
  YAWN = 6; SWORDSDANCE = 7; FAKEOUT = 8
end

module PBWeather
  RAINDANCE = 1; SUNNYDAY = 2; SANDSTORM = 3; HAIL = 4
end

# The move-data record switch_matchup reads for a benched Pokemon's moves.
class PBMoveData
  attr_reader :type, :basedamage
  TABLE = {}
  def initialize(id)
    entry = TABLE[id] || [PBTypes::NORMAL, 80]
    @type = entry[0]
    @basedamage = entry[1]
  end
end

class StubMove
  attr_accessor :id, :basedamage, :priority, :target, :type, :function,
                :addlEffect, :accuracy, :magic_coat, :contact, :healing, :multi_hit

  def initialize(options = {})
    @id         = options.fetch(:id, PBMoves::POUND)
    @basedamage = options.fetch(:basedamage, 80)
    @priority   = options.fetch(:priority, 0)
    @target     = options.fetch(:target, PBTargets::SingleNonUser)
    @type       = options.fetch(:type, PBTypes::NORMAL)
    @function   = options.fetch(:function, 0x000)
    @addlEffect = options.fetch(:addlEffect, 0)
    @accuracy   = options.fetch(:accuracy, 100)
    @magic_coat = options.fetch(:magic_coat, false)
    @contact    = options.fetch(:contact, false)
    @healing    = options.fetch(:healing, false)
    @multi_hit  = options.fetch(:multi_hit, false)
    @typemod    = options.fetch(:typemod, 8)
  end

  def pbIsDamaging?; @basedamage > 0; end
  def pbIsStatus?; @basedamage <= 0; end
  def pbTypeModifier(_type, _attacker, _target); @typemod; end
  def pbType(_type, _attacker, _target); @type; end
  def pbIsPhysical?(_type); true; end
  def isContactMove?; @contact; end
  def isHealingMove?; @healing; end
  def pbIsMultiHit; @multi_hit; end
  def canMagicCoat?; @magic_coat; end
end

# A party entry (never on the field). switch_actions and entry_hazard_pct read these.
class StubPokemon
  attr_accessor :species, :hp, :totalhp, :type1, :type2, :ability, :item, :moves, :speed

  def initialize(options = {})
    @species = options.fetch(:species, 1)
    @totalhp = options.fetch(:totalhp, 100)
    @hp      = options.fetch(:hp, @totalhp)
    @type1   = options.fetch(:type1, PBTypes::NORMAL)
    @type2   = options.fetch(:type2, PBTypes::NORMAL)
    @ability = options.fetch(:ability, 0)
    @item    = options.fetch(:item, 0)
    @moves   = options.fetch(:moves, [StubMove.new])
    @speed   = options.fetch(:speed, 100)
  end

  def isEgg?; false; end
  def hasType?(symbol)
    value = (PBTypes.const_get(symbol) rescue nil)
    !value.nil? && (@type1 == value || @type2 == value)
  end
  def hasAbility?(symbol)
    value = (PBAbilities.const_get(symbol) rescue nil)
    !value.nil? && @ability == value
  end
end

class StubBattler
  attr_accessor :index, :species, :hp, :totalhp, :status, :statusCount, :type1, :type2,
                :stages, :effects, :moves, :ability, :item, :pokemonIndex, :turncount,
                :speed, :partner, :opposite, :pokemon, :mold_breaker, :can_status

  def initialize(options = {})
    @index       = options.fetch(:index, 1)
    @species     = options.fetch(:species, 1)
    @totalhp     = options.fetch(:totalhp, 100)
    @hp          = options.fetch(:hp, @totalhp)
    @status      = options.fetch(:status, 0)
    @statusCount = options.fetch(:statusCount, 0)
    @type1       = options.fetch(:type1, PBTypes::NORMAL)
    @type2       = options.fetch(:type2, PBTypes::NORMAL)
    @stages      = options.fetch(:stages, Array.new(8, 0))
    @effects     = options.fetch(:effects, default_effects)
    @moves       = options.fetch(:moves, [StubMove.new])
    @ability     = options.fetch(:ability, 0)
    @item        = options.fetch(:item, 0)
    @pokemonIndex = options.fetch(:pokemonIndex, 0)
    @turncount   = options.fetch(:turncount, 0)
    @speed       = options.fetch(:speed, 100)
    @partner     = options.fetch(:partner, nil)
    @opposite    = options.fetch(:opposite, nil)
    @pokemon     = options.fetch(:pokemon, nil)
    @mold_breaker = options.fetch(:mold_breaker, false)
    @can_status  = options.fetch(:can_status, true)
  end

  def default_effects
    fx = Array.new(130, 0)
    fx[PBEffects::LeechSeed] = -1
    fx[PBEffects::ChoiceBand] = -1
    fx
  end

  def pbSpeed; @speed; end
  def attack_stat; @attack_stat ||= 100; end
  def spatk_stat; @spatk_stat ||= 100; end
  attr_writer :attack_stat, :spatk_stat
  def isFainted?; @hp <= 0; end
  def pbPartner; @partner; end
  def pbOppositeOpposing; @opposite; end
  def hasMoldBreaker; @mold_breaker; end
  def isAirborne?(_ignore = false); false; end
  def pbHasType?(symbol)
    value = (PBTypes.const_get(symbol) rescue nil)
    !value.nil? && (@type1 == value || @type2 == value)
  end
  def pbCanBurn?(_a, _s, _m = nil); @can_status; end
  def pbCanPoison?(_a, _s, _m = nil); @can_status; end
  def pbCanParalyze?(_a, _s, _m = nil); @can_status; end
  def pbCanSleep?(_a, _s, _m = nil, _i = false); @can_status; end
  def pbCanFreeze?(_a, _s, _m = nil); @can_status; end
  def pbCanConfuse?(_a = nil, _s = true, _m = nil); @can_status; end
  def pbCanReduceStatStage?(_stat, _a = nil, _s = false, _m = nil, _mb = false, _ic = false)
    @can_reduce.nil? ? true : @can_reduce
  end
  attr_writer :can_reduce

  def hasWorkingAbility(symbol, _ignore = false)
    value = (PBAbilities.const_get(symbol) rescue nil)
    !value.nil? && @ability == value
  end

  def pbOwnSide; @own_side ||= StubSide.new; end
  attr_writer :own_side
end

# The two-line v16 equivalent of Reborn's pbMakeFakeBattler. The constructor's
# cross-battler Attract/MeanLook clearing is reproduced faithfully so the adapter's
# save/restore is actually under test.
class PokeBattle_Battler < StubBattler
  def initialize(battle, index)
    super(:index => index)
    battle.battlers.each do |other|
      next if !other
      other.effects[PBEffects::Attract] = -1 if other.effects[PBEffects::Attract] == index
      other.effects[PBEffects::MeanLook] = -1 if other.effects[PBEffects::MeanLook] == index
    end
  end

  def pbInitPokemon(pokemon, party_index)
    @species = pokemon.species
    @hp = pokemon.hp
    @totalhp = pokemon.totalhp
    @type1 = pokemon.type1
    @type2 = pokemon.type2
    @ability = pokemon.ability
    @item = pokemon.item
    @speed = pokemon.speed
    @moves = pokemon.moves
    @pokemonIndex = party_index
    self
  end
end

class PokeBattle_Move
  def self.pbFromPBMove(_battle, move); move; end
end

class StubSide
  attr_accessor :effects
  def initialize
    @effects = Array.new(24, 0)
    @effects[PBEffects::StealthRock] = false
    @effects[PBEffects::StickyWeb] = false
  end
end

class StubField
  attr_accessor :effects
  def initialize; @effects = Array.new(16, 0); end
end

class PokeBattle_Battle
  attr_reader :stock_choice
  attr_accessor :battlers, :doublebattle, :turncount, :sides, :field, :parties,
                :weather, :owner, :score

  def initialize
    @battlers = [nil, nil, nil, nil]
    @doublebattle = false
    @turncount = 0
    @sides = [StubSide.new, StubSide.new]
    @field = StubField.new
    @parties = [[], []]
    @weather = 0
    @score = 100
  end

  def pbChooseMoves(index); @stock_choice = index; end
  def pbDefaultChooseEnemyCommand(index); @stock_choice = index; end
  def pbIsOpposing?(index); index.odd?; end
  def opponent; Object.new; end
  def pbGetOwner(_index); @owner; end
  def pbWeather; @weather; end
  def pbAIRandom(limit); 0; end
  def pbParty(index); @parties[index & 1]; end
  def pbOpposingParty(index); @parties[(index & 1) ^ 1]; end
  def pbCanChooseMove?(_index, _slot, _show); true; end
  def pbCanSwitch?(index, slot, _show)
    entry = pbParty(index)[slot]
    !entry.nil? && entry.hp > 0
  end
  def pbGetMoveScore(_move, _attacker, _target, _skill); @score; end
  def pbRegisterTargetStub; end
  def pbBetterBaseDamage(_move, _attacker, _target, _skill, basedamage); basedamage; end
  def pbRoughDamage(_move, _attacker, target, _skill, basedamage)
    (target.totalhp * basedamage / 200.0)
  end
  def pbRoughAccuracy(_move, _attacker, _target, _skill); 100; end
  def pbRoughStat(battler, stat, _skill)
    stat == PBStats::ATTACK ? battler.attack_stat : battler.spatk_stat
  end
  def pbRegisterMove(_i, _slot, _show); true; end
  def pbRegisterSwitch(_i, _slot); true; end
  def pbRegisterTarget(_i, _t); true; end
end

require File.join(root, "adapters", "realidea", "Portable_AI_Adapter")

class PortableAIRealideaAdapterTest < Test::Unit::TestCase
  Owner = Struct.new(:skill, :skillCode)

  def setup
    $PORTABLE_AI_ENABLED = false
    $PORTABLE_AI_CONFIG = nil
  end

  def teardown
    $PORTABLE_AI_ENABLED = false
    $PORTABLE_AI_CONFIG = nil
  end

  def test_numeric_skill_code_repairs_realidea_column_shift
    owner = Owner.new(32, "100")
    assert_equal(100, PortableAIRealidea.corrected_skill(owner))
  end

  def test_non_numeric_skill_code_is_not_treated_as_level
    owner = Owner.new(48, "SMART_SWITCH")
    assert_equal(48, PortableAIRealidea.corrected_skill(owner))
  end

  def test_best_skill_is_deterministic_and_coordinated
    config = PortableAIRealidea.config_for(100)
    assert_equal(true, config["deterministic"])
    assert_equal(true, config["coordination"])
    assert_equal(0, config["noise"])
  end

  def test_disabled_hook_delegates_to_stock_choice
    battle = PokeBattle_Battle.new
    battle.pbChooseMoves(1)
    assert_equal(1, battle.stock_choice)
  end

  def test_marker_override_can_enable_adapter
    $PORTABLE_AI_ENABLED = true
    battle = PokeBattle_Battle.new
    assert_equal(true, PortableAIRealidea.enabled_for?(battle, 1))
    assert_equal(false, PortableAIRealidea.enabled_for?(battle, 0))
  end

  def test_consecutive_setup_memory_increments
    battle = PokeBattle_Battle.new
    action = { "type" => "move", "move_id" => "SWORDSDANCE", "tags" => ["setup"] }
    PortableAIRealidea.apply_memory(battle, 1, action)
    PortableAIRealidea.apply_memory(battle, 1, action)
    memory = battle.instance_variable_get(:@portable_ai_memory)
    assert_equal(2, memory["1"]["setup"])
  end

  # --- 0.6.x config plumbing -------------------------------------------------

  def test_run_overrides_reach_the_core_config_without_disturbing_skill_tiers
    $PORTABLE_AI_CONFIG = { "switch_risk_weight" => 0.0 }
    config = PortableAIRealidea.config_for(100)
    assert_equal(0.0, config["switch_risk_weight"])
    assert_equal(true, config["deterministic"])
    assert_equal(true, config["memory"])
  end

  def test_absent_overrides_leave_the_config_alone
    assert_equal(false, PortableAIRealidea.config_for(100).key?("switch_risk_weight"))
  end

  def test_adapter_side_rules_follow_the_same_override_precedence
    assert_equal(true, PortableAIRealidea.rule_enabled?("yawn_gate"))
    $PORTABLE_AI_CONFIG = { "yawn_gate" => false }
    assert_equal(false, PortableAIRealidea.rule_enabled?("yawn_gate"))
  end

  # --- constant tables -------------------------------------------------------

  def test_ability_names_are_plain_uppercase_strings
    assert_equal("MAGICGUARD",
                 PortableAIRealidea.ability_key(StubBattler.new(:ability => PBAbilities::MAGICGUARD)))
    assert_nil(PortableAIRealidea.ability_key(StubBattler.new(:ability => 0)))
  end

  # --- positive stages -------------------------------------------------------

  def test_positive_stage_total_counts_only_the_boosts
    battler = StubBattler.new(:stages => [0, 2, 0, 1, 0, -2, 0, 0])
    assert_equal(3, PortableAIRealidea.positive_stages(battler))
    assert_equal(0, PortableAIRealidea.positive_stages(nil))
  end

  # --- status_blocked? -------------------------------------------------------
  #
  # Tags come from Effects.describe, the SAME call action_for_target makes. Hand-writing
  # ["status", "typed_status"] here would let a rule pass a test it never fires on.
  TWAVE_TAGS = PortableAI::Effects.describe("THUNDERWAVE", []).freeze
  TOXIC_TAGS = PortableAI::Effects.describe("TOXIC", []).freeze
  LEECH_TAGS = PortableAI::Effects.describe("LEECHSEED", []).freeze
  YAWN_TAGS  = PortableAI::Effects.describe("YAWN", []).freeze
  HYPNOSIS_TAGS = PortableAI::Effects.describe("HYPNOSIS", []).freeze

  def blocked?(move, tags, target, attacker = StubBattler.new(:index => 1))
    PortableAIRealidea.status_blocked?(move, tags, attacker, target)
  end

  def test_thunder_wave_is_dead_into_a_ground_type
    move = StubMove.new(:basedamage => 0, :type => PBTypes::ELECTRIC, :typemod => 0)
    ground = StubBattler.new(:index => 0, :type1 => PBTypes::GROUND, :type2 => PBTypes::GROUND)
    assert_equal(true, blocked?(move, TWAVE_TAGS, ground))
  end

  def test_thunder_wave_is_live_into_a_normal_type
    move = StubMove.new(:basedamage => 0, :type => PBTypes::ELECTRIC, :typemod => 8)
    assert_equal(false, blocked?(move, TWAVE_TAGS, StubBattler.new(:index => 0)))
  end

  # TOXIC is tagged ["status", "poison"] with no "typed_status" (effects.rb:53), so the
  # Steel immunity comes from the engine's own pbCanPoison? -- which is exactly what
  # this asserts, and why the type-list fallback below still has to exist.
  def test_toxic_is_dead_into_a_steel_type
    move = StubMove.new(:basedamage => 0, :type => PBTypes::POISON)
    steel = StubBattler.new(:index => 0, :type1 => PBTypes::STEEL,
                            :type2 => PBTypes::STEEL, :can_status => false)
    assert_equal(true, blocked?(move, TOXIC_TAGS, steel))
  end

  def test_the_type_list_still_blocks_when_the_predicate_is_missing
    move = StubMove.new(:basedamage => 0, :type => PBTypes::POISON)
    steel = StubBattler.new(:index => 0, :type1 => PBTypes::STEEL, :type2 => PBTypes::STEEL)
    class << steel
      undef_method :pbCanPoison?
    end
    assert_equal(true, blocked?(move, TOXIC_TAGS, steel))
  end

  def leech_target(seeded = false, sub = false, grass = false)
    target = StubBattler.new(:index => 0)
    target.effects[PBEffects::LeechSeed] = seeded ? 1 : -1
    target.effects[PBEffects::Substitute] = sub ? 1 : 0
    if grass
      target.type1 = PBTypes::GRASS
      target.type2 = PBTypes::GRASS
    end
    target
  end

  def leech_blocked?(target)
    blocked?(StubMove.new(:basedamage => 0, :function => 0x0DC), LEECH_TAGS, target)
  end

  def test_leech_seed_is_live_against_a_fresh_target
    assert_equal(false, leech_blocked?(leech_target))
  end

  def test_leech_seed_is_blocked_on_an_already_seeded_target
    assert_equal(true, leech_blocked?(leech_target(true)))
  end

  def test_leech_seed_is_blocked_by_a_substitute
    assert_equal(true, leech_blocked?(leech_target(false, true)))
  end

  def test_leech_seed_is_blocked_against_a_grass_type
    assert_equal(true, leech_blocked?(leech_target(false, false, true)))
  end

  def drowsy_target(drowsy, can_status = true)
    target = StubBattler.new(:index => 0, :can_status => can_status)
    target.effects[PBEffects::Yawn] = drowsy ? 2 : 0
    target
  end

  def test_yawn_carries_its_own_tag_in_the_shipped_table
    assert(YAWN_TAGS.include?("drowsy"))
    assert(YAWN_TAGS.include?("sleep"))
    assert_equal(false, HYPNOSIS_TAGS.include?("drowsy"))
  end

  def test_yawn_is_blocked_against_an_already_drowsy_target
    move = StubMove.new(:basedamage => 0, :function => 0x004)
    assert_equal(true, blocked?(move, YAWN_TAGS, drowsy_target(true)))
    assert_equal(false, blocked?(move, YAWN_TAGS, drowsy_target(false)))
  end

  def test_yawn_gate_off_restores_the_pre_gate_re_click
    $PORTABLE_AI_CONFIG = { "yawn_gate" => false }
    move = StubMove.new(:basedamage => 0, :function => 0x004)
    assert_equal(false, blocked?(move, YAWN_TAGS, drowsy_target(true)))
  end

  def test_hypnosis_is_unaffected_by_the_drowsy_clause
    move = StubMove.new(:basedamage => 0, :function => 0x001)
    assert_equal(false, blocked?(move, HYPNOSIS_TAGS, drowsy_target(true)))
  end

  def test_the_engine_predicate_still_owns_what_it_already_knew
    move = StubMove.new(:basedamage => 0, :function => 0x001)
    assert_equal(true, blocked?(move, HYPNOSIS_TAGS, drowsy_target(false, false)))
  end

  # Magic Bounce here bounces only flag-c moves and is turned off by Mold Breaker
  # (080_PokeBattle_Battler.rb:2433) -- both narrower than Reborn's blanket reflect.
  def test_magic_bounce_blocks_a_magic_coat_flagged_status_move
    bouncer = StubBattler.new(:index => 0, :ability => PBAbilities::MAGICBOUNCE)
    flagged = StubMove.new(:basedamage => 0, :magic_coat => true)
    unflagged = StubMove.new(:basedamage => 0, :magic_coat => false)
    assert_equal(true, blocked?(flagged, TWAVE_TAGS, bouncer))
    assert_equal(false, blocked?(unflagged, TWAVE_TAGS, bouncer))
  end

  def test_mold_breaker_walks_through_magic_bounce
    bouncer = StubBattler.new(:index => 0, :ability => PBAbilities::MAGICBOUNCE)
    breaker = StubBattler.new(:index => 1, :mold_breaker => true)
    flagged = StubMove.new(:basedamage => 0, :magic_coat => true)
    assert_equal(false, blocked?(flagged, TWAVE_TAGS, bouncer, breaker))
  end

  # --- 0.5.0 move facts ------------------------------------------------------

  def effect_for(move, user = StubBattler.new, target = StubBattler.new(:index => 0))
    PortableAIRealidea.move_effect(PokeBattle_Battle.new, move, user, target)
  end

  def test_function_code_map_names_the_kind_and_the_stat
    kind, stat, chance = effect_for(StubMove.new(:function => 0x0A, :addlEffect => 30))
    assert_equal(["burn", nil, 30], [kind, stat, chance])
    kind, stat, _ = effect_for(StubMove.new(:function => 0x44, :addlEffect => 100))
    assert_equal(["drop", "speed"], [kind, stat])
    kind, stat, _ = effect_for(StubMove.new(:function => 0x46, :addlEffect => 10))
    assert_equal(["drop", "spd"], [kind, stat])
  end

  # Realidea's own codes, read off 083_PokeBattle_MoveEffects.rb. Reborn numbers a 3/4
  # drain 0x139; here 0x139 is Play Nice and the drain is 0x14F.
  def test_realidea_specific_codes_are_named_for_what_this_engine_does
    kind, stat, _ = effect_for(StubMove.new(:function => 0x13D, :basedamage => 0))
    assert_equal(["drop", "spa"], [kind, stat])
    kind, stat, _ = effect_for(StubMove.new(:function => 0x139, :basedamage => 0))
    assert_equal(["drop", "atk"], [kind, stat])
    assert_equal(0.75, PortableAIRealidea::MOVE_DRAIN_CODES[0x14F])
    assert_nil(PortableAIRealidea::MOVE_DRAIN_CODES[0x139])
  end

  def test_unmapped_function_code_reports_no_effect
    assert_equal([nil, nil, nil], effect_for(StubMove.new(:function => 0x000)))
  end

  # A status MOVE carries addlEffect 0 because the status is the whole move.
  def test_status_move_effect_chance_is_certain_not_zero
    _, _, chance = effect_for(StubMove.new(:function => 0x0A, :basedamage => 0))
    assert_equal(100, chance)
  end

  def test_serene_grace_doubles_the_chance
    user = StubBattler.new(:ability => PBAbilities::SERENEGRACE)
    _, _, chance = effect_for(StubMove.new(:function => 0x0A, :addlEffect => 30), user)
    assert_equal(60, chance)
  end

  # 080:3059-3061: Sheer Force cancels the secondary outright; Shield Dust does unless
  # the user has Mold Breaker.
  def test_sheer_force_and_shield_dust_zero_the_chance
    forceful = StubBattler.new(:ability => PBAbilities::SHEERFORCE)
    _, _, zero = effect_for(StubMove.new(:function => 0x0A, :addlEffect => 30), forceful)
    assert_equal(0, zero)
    dusty = StubBattler.new(:index => 0, :ability => PBAbilities::SHIELDDUST)
    _, _, dusted = effect_for(StubMove.new(:function => 0x0A, :addlEffect => 30),
                              StubBattler.new, dusty)
    assert_equal(0, dusted)
    breaker = StubBattler.new(:mold_breaker => true)
    _, _, through = effect_for(StubMove.new(:function => 0x0A, :addlEffect => 30),
                               breaker, dusty)
    assert_equal(30, through)
  end

  def test_a_secondary_the_target_cannot_take_is_worth_nothing
    fireproof = StubBattler.new(:index => 0, :can_status => false)
    _, _, chance = effect_for(StubMove.new(:function => 0x0A, :addlEffect => 30),
                              StubBattler.new, fireproof)
    assert_equal(0, chance)
  end

  def test_attack_bias_reads_the_engines_own_rough_stat
    battle = PokeBattle_Battle.new
    physical = StubBattler.new
    physical.attack_stat = 200
    physical.spatk_stat = 100
    assert_equal([true, false], PortableAIRealidea.attack_bias(battle, physical, 100))
    special = StubBattler.new
    special.attack_stat = 80
    special.spatk_stat = 150
    assert_equal([false, true], PortableAIRealidea.attack_bias(battle, special, 100))
    even = StubBattler.new
    assert_equal([false, false], PortableAIRealidea.attack_bias(battle, even, 100))
  end

  def test_wish_is_reported_active_only_while_one_is_pending
    battle = PokeBattle_Battle.new
    pending = StubBattler.new
    pending.effects[PBEffects::Wish] = 2
    assert_equal(true, PortableAIRealidea.effect_active?(battle, "WISH", pending))
    assert_equal(false, PortableAIRealidea.effect_active?(battle, "WISH", StubBattler.new))
  end

  def test_partner_facts_are_absent_in_singles
    snapshot = contract_snapshot
    actor = snapshot["actors"][0]
    assert_equal(false, actor["partner_alive"])
    assert_nil(actor["partner_ability"])
    assert_nil(actor["partner_hp_pct"])
    assert_equal(false, actor["partner_airborne"])
  end

  # --- 0.6.0 threats_by_foe --------------------------------------------------

  def race_foe(index, speed, moves, locked = -1)
    foe = StubBattler.new(:index => index, :speed => speed, :moves => moves)
    foe.effects[PBEffects::ChoiceBand] = locked
    foe
  end

  def test_threats_by_foe_keeps_the_best_priority_hit_separate
    battle = PokeBattle_Battle.new
    battle.battlers[0] = race_foe(0, 90, [StubMove.new(:id => 1, :basedamage => 120),
                                          StubMove.new(:id => 2, :basedamage => 50,
                                                       :priority => 1)])
    me = StubBattler.new(:index => 1, :speed => 100)
    map = PortableAIRealidea.incoming_damage_by_move(battle, me, [0], 100)
    out = PortableAIRealidea.threats_by_foe(battle, me, [0], map, 100)
    assert_equal(60.0, out["0"]["damage_pct"])
    assert_equal(25.0, out["0"]["priority_damage_pct"])
    assert_equal(true, out["0"]["faster"])
  end

  # The reason the export exists: actor["faster"] is against the FASTEST foe, so on a
  # doubles board where the actor outruns one foe and not the other it is a single
  # false and a race computed off it is wrong for the slower target.
  def test_threats_by_foe_orders_against_each_foe_separately
    battle = PokeBattle_Battle.new
    battle.battlers[0] = race_foe(0, 90, [StubMove.new(:id => 1)])
    battle.battlers[2] = race_foe(2, 150, [StubMove.new(:id => 3)])
    me = StubBattler.new(:index => 1, :speed => 100)
    map = PortableAIRealidea.incoming_damage_by_move(battle, me, [0, 2], 100)
    out = PortableAIRealidea.threats_by_foe(battle, me, [0, 2], map, 100)
    assert_equal(true,  out["0"]["faster"])
    assert_equal(false, out["2"]["faster"])
    assert_equal(false, PortableAIRealidea.faster_than_foes?(battle, 100, [0, 2]))
  end

  def test_threats_by_foe_inherits_the_choice_lock
    battle = PokeBattle_Battle.new
    battle.battlers[0] = race_foe(0, 90, [StubMove.new(:id => 1, :basedamage => 120),
                                          StubMove.new(:id => 2, :basedamage => 50)], 2)
    me = StubBattler.new(:index => 1, :speed => 100)
    map = PortableAIRealidea.incoming_damage_by_move(battle, me, [0], 100)
    out = PortableAIRealidea.threats_by_foe(battle, me, [0], map, 100)
    assert_equal(25.0, out["0"]["damage_pct"])
  end

  def test_threats_by_foe_is_an_empty_hash_when_the_board_cannot_be_read
    assert_equal({}, PortableAIRealidea.threats_by_foe(nil, nil, [0], {}, 100))
  end

  # The race is reported as computed, so a run with damage_race off still says in its
  # trace what the race was.
  def test_the_trace_view_carries_the_race_per_target
    snapshot = contract_snapshot
    view = PortableAIRealidea.view_trace(snapshot, 1)
    assert_equal(true, view.key?("race"))
    assert_equal(true, view["race"].key?("0"))
    assert_equal(snapshot["actors"][0]["hp_pct"], view["hp_pct"])
  end

  # --- snapshot contract -----------------------------------------------------
  #
  # The list of keys the shared core reads at each level. When a future core rule adds
  # a read, the key goes here and this test fails until the Realidea export exists --
  # which is the whole reason this adapter drifted five minor versions behind.
  TOP_LEVEL_KEYS = %w[
    format turn weather trick_room_active tailwind_active actors targets memory
  ]

  ACTOR_KEYS = %w[
    index species hp_pct status speed faster stages negative_stage_total
    positive_stage_total incoming_damage_pct certain_incoming_damage_pct
    incoming_by_move threats_by_foe threatened_lethal no_effective_move
    best_damage_pct yawned
    residual_damage_pct trapped ability item mold_breaker slower_bench_count
    partner_alive partner_ability partner_hp_pct partner_airborne turncount actions
  ]

  MOVE_ACTION_KEYS = %w[
    type actor_index slot move_id numeric_move_id target base_score damaging power
    priority move_type contact effect_kind effect_stat effect_chance multi_hit
    recoil_fraction drain_fraction mold_breaker target_species target_ability
    target_item target_full_hp target_speed target_physical_attacker
    target_special_attacker target_substitute effectiveness immune
    expected_damage_pct accuracy target_hp_pct tags spread existing_layers max_layers
    own_hazard_layers foe_hazard_layers target_positive_stages effect_active
    foe_reserves hazard_targets own_reserves
  ]

  SWITCH_ACTION_KEYS = %w[
    type actor_index slot base_score matchup_score incoming_risk forced safe_entry
    species candidate_hp_pct entry_damage_pct incoming_damage_pct
    outgoing_damage_pct faster
  ]

  TARGET_KEYS = %w[
    index species hp_pct status types speed positive_stages ability item full_hp
    physical_attacker special_attacker substitute partner_ability
  ]

  # A minimal singles board: one AI battler at index 1 with one move and one healthy
  # bench Pokemon, one foe at index 0.
  def contract_battle
    battle = PokeBattle_Battle.new
    foe = StubBattler.new(:index => 0, :species => 2, :speed => 90)
    actor = StubBattler.new(:index => 1, :species => 1, :speed => 120,
                            :moves => [StubMove.new(:id => PBMoves::TACKLE)])
    actor.opposite = foe
    foe.opposite = actor
    battle.battlers[0] = foe
    battle.battlers[1] = actor
    battle.parties = [[StubPokemon.new(:species => 2)],
                      [StubPokemon.new(:species => 1), StubPokemon.new(:species => 3)]]
    battle.owner = Owner.new(100, "")
    battle
  end

  def contract_snapshot
    snapshot, _skill = PortableAIRealidea.build_snapshot(contract_battle)
    snapshot
  end

  def assert_exports(keys, hash, label)
    missing = keys.reject { |key| hash.key?(key) }
    assert_equal([], missing, "#{label} is missing snapshot keys")
  end

  def test_snapshot_exports_every_key_the_core_reads
    snapshot = contract_snapshot
    assert_exports(TOP_LEVEL_KEYS, snapshot, "snapshot")
    actor = snapshot["actors"][0]
    assert_exports(ACTOR_KEYS, actor, "actor")
    assert_exports(TARGET_KEYS, snapshot["targets"][0], "target")
    move = actor["actions"].find { |a| a["type"] == "move" }
    assert_not_nil(move, "no move action was built")
    assert_exports(MOVE_ACTION_KEYS, move, "move action")
    switch = actor["actions"].find { |a| a["type"] == "switch" }
    assert_not_nil(switch, "no switch action was built")
    assert_exports(SWITCH_ACTION_KEYS, switch, "switch action")
  end

  def test_actor_turncount_is_exported_so_first_turn_moves_stop_re_clicking
    battle = contract_battle
    battle.battlers[1].turncount = 4
    snapshot, _ = PortableAIRealidea.build_snapshot(battle)
    assert_equal(4, snapshot["actors"][0]["turncount"])
  end

  # --- 0.4.x exports ---------------------------------------------------------

  def speed_battler(value)
    StubBattler.new(:index => 0, :speed => value)
  end

  def test_speed_order_uses_a_strict_comparison
    battle = PokeBattle_Battle.new
    battle.battlers[0] = speed_battler(120)
    assert_equal(true,  PortableAIRealidea.faster_than_foes?(battle, 130, [0]))
    assert_equal(false, PortableAIRealidea.faster_than_foes?(battle, 90, [0]))
    assert_equal(false, PortableAIRealidea.faster_than_foes?(battle, 120, [0]))
  end

  def test_speed_order_is_nil_without_both_speeds
    battle = PokeBattle_Battle.new
    battle.battlers[0] = speed_battler(120)
    assert_nil(PortableAIRealidea.faster_than_foes?(battle, nil, [0]))
    assert_nil(PortableAIRealidea.faster_than_foes?(battle, 130, []))
  end

  def test_trick_room_inverts_speed_order
    battle = PokeBattle_Battle.new
    battle.battlers[0] = speed_battler(120)
    battle.field.effects[PBEffects::TrickRoom] = 5
    assert_equal(true,  PortableAIRealidea.faster_than_foes?(battle, 90, [0]))
    assert_equal(false, PortableAIRealidea.faster_than_foes?(battle, 130, [0]))
  end

  # 125 is v16's never-miss sentinel (085_PokeBattle_AI.rb:3770). Handing it to the
  # core as a hit chance would make a sure thing worth 1.25 of itself.
  def test_never_miss_accuracy_is_clamped_to_100
    battle = PokeBattle_Battle.new
    battle.define_singleton_method(:pbRoughAccuracy) { |_m, _a, _t, _s| 125 }
    assert_equal(100.0, PortableAIRealidea.rough_accuracy(
      battle, StubMove.new, StubBattler.new, StubBattler.new(:index => 0), 100))
  end

  def test_accuracy_is_nil_when_the_primitive_is_unavailable
    battle = PokeBattle_Battle.new
    class << battle
      undef_method :pbRoughAccuracy
    end
    assert_nil(PortableAIRealidea.rough_accuracy(
      battle, StubMove.new, StubBattler.new, StubBattler.new(:index => 0), 100))
  end

  # 084_PokeBattle_Battle.rb:1105-1113 is the whole of this engine's priority
  # arithmetic. Psychic Terrain is set by move 0x169 and read by nothing, so a priority
  # move under it keeps its bracket here -- unlike Reborn.
  def test_prankster_raises_a_status_moves_priority
    user = StubBattler.new(:ability => PBAbilities::PRANKSTER)
    assert_equal(1, PortableAIRealidea.effective_priority(
      StubMove.new(:basedamage => 0), user))
    assert_equal(0, PortableAIRealidea.effective_priority(StubMove.new, user))
  end

  def test_gale_wings_and_triage_raise_their_own_brackets
    flier = StubBattler.new(:ability => PBAbilities::GALEWINGS)
    assert_equal(1, PortableAIRealidea.effective_priority(
      StubMove.new(:type => PBTypes::FLYING), flier))
    assert_equal(0, PortableAIRealidea.effective_priority(StubMove.new, flier))
    healer = StubBattler.new(:ability => PBAbilities::TRIAGE)
    assert_equal(3, PortableAIRealidea.effective_priority(
      StubMove.new(:basedamage => 0, :healing => true), healer))
  end

  # --- threat model ----------------------------------------------------------

  def threat_battle(foe_status = 0, foe_count = 0, accuracy = 100)
    battle = PokeBattle_Battle.new
    battle.define_singleton_method(:pbRoughAccuracy) { |_m, _a, _t, _s| accuracy }
    foe = StubBattler.new(:index => 0, :status => foe_status, :statusCount => foe_count,
                          :moves => [StubMove.new(:id => PBMoves::TACKLE)])
    battle.battlers[0] = foe
    battle
  end

  def certain_for(battle, us = StubBattler.new(:index => 1))
    map = PortableAIRealidea.incoming_damage_by_move(battle, us, [0], 100)
    PortableAIRealidea.certain_incoming_damage(battle, us, [0], map, 100)
  end

  def test_certain_incoming_damage_counts_a_sure_hit
    assert_equal(40.0, certain_for(threat_battle))
  end

  def test_certain_incoming_damage_ignores_a_move_that_can_miss
    assert_equal(0.0, certain_for(threat_battle(0, 0, 85)))
  end

  def test_certain_incoming_damage_ignores_a_frozen_foe
    assert_equal(0.0, certain_for(threat_battle(PBStatuses::FROZEN)))
  end

  # Sleep with one turn left means the foe wakes and acts this turn.
  def test_certain_incoming_damage_reads_the_sleep_counter
    assert_equal(0.0, certain_for(threat_battle(PBStatuses::SLEEP, 3)))
    assert_equal(40.0, certain_for(threat_battle(PBStatuses::SLEEP, 1)))
  end

  def test_a_choice_locked_foe_contributes_only_the_locked_move
    battle = PokeBattle_Battle.new
    foe = StubBattler.new(:index => 0,
                          :moves => [StubMove.new(:id => 7), StubMove.new(:id => 9)])
    foe.effects[PBEffects::ChoiceBand] = 7
    battle.battlers[0] = foe
    map = PortableAIRealidea.incoming_damage_by_move(
      battle, StubBattler.new(:index => 1), [0], 100)
    assert_equal(["0:7"], map.keys)
    foe.effects[PBEffects::ChoiceBand] = -1
    map = PortableAIRealidea.incoming_damage_by_move(
      battle, StubBattler.new(:index => 1), [0], 100)
    assert_equal(["0:7", "0:9"], map.keys.sort)
  end

  # --- switch candidates -----------------------------------------------------

  def entry_battle(foe_atk_stage = 0)
    battle = PokeBattle_Battle.new
    foe = StubBattler.new(:index => 0, :moves => [StubMove.new(:id => PBMoves::TACKLE)])
    foe.stages[PBStats::ATTACK] = foe_atk_stage
    battle.battlers[0] = foe
    actor = StubBattler.new(:index => 1)
    actor.opposite = foe
    battle.battlers[1] = actor
    battle.define_singleton_method(:pbRoughDamage) do |_m, attacker, target, _s, base|
      target.totalhp * base * (2 + attacker.stages[PBStats::ATTACK]) / 400.0
    end
    battle
  end

  # Reborn does exactly this, including the temporary stage mutation and its restore;
  # leaking it would corrupt every later estimate in the same turn.
  def test_intimidate_lowers_the_entry_estimate_and_restores_the_stage
    battle = entry_battle
    actor = battle.battlers[1]
    plain = PortableAIRealidea.switch_incoming_damage(
      battle, StubPokemon.new, 1, actor, [0], 100)
    scary = StubPokemon.new(:ability => PBAbilities::INTIMIDATE)
    softened = PortableAIRealidea.switch_incoming_damage(battle, scary, 1, actor, [0], 100)
    assert_equal(40.0, plain)
    assert_equal(20.0, softened)
    assert_equal(0, battle.battlers[0].stages[PBStats::ATTACK])
  end

  # Clear Body and friends are honoured through the engine's own refusal, not a list
  # carried here.
  def test_intimidate_is_ignored_when_the_engine_refuses_the_drop
    battle = entry_battle
    battle.battlers[0].can_reduce = false
    scary = StubPokemon.new(:ability => PBAbilities::INTIMIDATE)
    assert_equal(40.0, PortableAIRealidea.switch_incoming_damage(
      battle, scary, 1, battle.battlers[1], [0], 100))
  end

  # PokeBattle_Battler#initialize clears Attract and MeanLook on everything pointing at
  # the index being built (080:374-378, :418-424), so building a fake at the actor's own
  # index would silently break a real infatuation.
  def test_building_a_fake_battler_leaves_infatuation_alone
    battle = entry_battle
    battle.battlers[0].effects[PBEffects::Attract] = 1
    battle.battlers[0].effects[PBEffects::MeanLook] = 1
    PortableAIRealidea.switch_incoming_damage(
      battle, StubPokemon.new, 1, battle.battlers[1], [0], 100)
    assert_equal(1, battle.battlers[0].effects[PBEffects::Attract])
    assert_equal(1, battle.battlers[0].effects[PBEffects::MeanLook])
  end

  def test_switch_outgoing_damage_takes_the_candidates_best_hit
    battle = entry_battle
    candidate = StubPokemon.new(:moves => [StubMove.new(:basedamage => 40),
                                           StubMove.new(:basedamage => 120)])
    assert_equal(60.0, PortableAIRealidea.switch_outgoing_damage(
      battle, candidate, 1, battle.battlers[1], [0], 100))
    assert_equal(20.0, PortableAIRealidea.switch_outgoing_damage(
      battle, StubPokemon.new(:moves => [StubMove.new(:basedamage => 40)]), 1,
      battle.battlers[1], [0], 100))
  end

  # Neutral is 8 here (three type slots), weighted x4 so the core sees the same
  # magnitudes it sees from Reborn: neutral 32, one super-effective step 64.
  def test_switch_incoming_risk_takes_the_worst_foe
    battle = PokeBattle_Battle.new
    battle.battlers[0] = StubBattler.new(:index => 0, :type1 => PBTypes::WATER,
                                         :type2 => PBTypes::WATER)
    fire = StubPokemon.new(:type1 => PBTypes::FIRE, :type2 => PBTypes::FIRE)
    normal = StubPokemon.new
    assert_equal(64, PortableAIRealidea.switch_incoming_risk(fire, battle, [0]))
    assert_equal(32, PortableAIRealidea.switch_incoming_risk(normal, battle, [0]))
  end

  def test_entry_hazard_cost_is_zero_for_magic_guard
    battle = PokeBattle_Battle.new
    battle.sides[1].effects[PBEffects::Spikes] = 3
    battler = StubBattler.new(:index => 1)
    assert_equal(25.0, PortableAIRealidea.entry_hazard_pct(battle, StubPokemon.new, battler))
    guarded = StubPokemon.new(:ability => PBAbilities::MAGICGUARD)
    assert_equal(0, PortableAIRealidea.entry_hazard_pct(battle, guarded, battler))
  end

  def test_slower_bench_count_ignores_the_active_slot
    battle = contract_battle
    battle.parties[1] = [StubPokemon.new(:speed => 10), StubPokemon.new(:speed => 10),
                         StubPokemon.new(:speed => 200)]
    assert_equal(1, PortableAIRealidea.slower_bench_count(battle, battle.battlers[1], [0]))
  end

  # Stock v16 resolves variable-power moves before it estimates damage
  # (085_PokeBattle_AI.rb:2802-2810); passing raw basedamage priced Seismic Toss and
  # Super Fang at their sentinel.
  def test_damage_estimate_goes_through_pbBetterBaseDamage
    battle = PokeBattle_Battle.new
    seen = []
    battle.define_singleton_method(:pbBetterBaseDamage) do |_m, _a, _t, _s, base|
      seen << base
      120
    end
    battle.define_singleton_method(:pbRoughDamage) do |_m, _a, target, _s, base|
      target.totalhp * base / 200.0
    end
    target = StubBattler.new(:index => 0)
    move = StubMove.new(:basedamage => 1)
    pct = PortableAIRealidea.rough_damage_pct(battle, move, StubBattler.new, target, 100)
    assert_equal([60], seen)
    assert_equal(60.0, pct)
  end
end
