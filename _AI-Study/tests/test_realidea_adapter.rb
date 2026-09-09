require "test/unit"

root = File.expand_path("..", File.dirname(__FILE__))
require File.join(root, "portable_ai", "model")
require File.join(root, "portable_ai", "effects")
require File.join(root, "portable_ai", "matrix")
require File.join(root, "portable_ai", "core")
require File.join(root, "portable_ai", "search")

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

# The adapter names species only when exporting a trace; the core is handed the numeric
# id the engine uses. Two entries are enough to prove the id never reaches the readout.
module PBSpecies
  NAMES = { 213 => "Shuckle", 212 => "Scizor" }
  def self.getName(id); NAMES[id]; end
end

module PBEffects
  # Battler effects.
  Attract = 1; ChoiceBand = 7; LeechSeed = 43; LockOn = 45; LockOnPos = 46
  MeanLook = 50; MultiTurn = 51; MultiTurnUser = 52; PerishSong = 66
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
  LIGHTNINGROD = 31; VOLTABSORB = 10; WATERABSORB = 11; FLASHFIRE = 18
  SAPSIPPER = 157; STORMDRAIN = 114; MOTORDRIVE = 78; DRYSKIN = 87
  BULLETPROOF = 171; TELEPATHY = 140
  MAGICGUARD = 98; MOLDBREAKER = 104; SHEERFORCE = 125; CONTRARY = 126
  MAGICBOUNCE = 156; PRANKSTER = 158; GALEWINGS = 177; TRIAGE = 209
  UNAWARE = 109
end

module PBItems
  WHITEHERB = 200; LEFTOVERS = 234; FOCUSSASH = 275
end

module PBMoves
  POUND = 1; TACKLE = 2; THUNDERWAVE = 3; TOXIC = 4; LEECHSEED = 5
  YAWN = 6; SWORDSDANCE = 7; FAKEOUT = 8; SURF = 9; GROWL = 10
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
    # 0.6.5. The matrix records which side of the split a cell's best hit is on, so
    # a setup move can be priced by the stat it actually raises. The engine reads
    # @category (082:136); this drives the same answer from the same field.
    @category   = options.fetch(:category, 0)
    # PP is deliberately NOT a field here: the adapter guards every read with
    # respond_to?(:pp), and a move object that simply has no such field is a real
    # case (an older stub, a move built from a PBMove with none). A test that wants
    # one defines the singleton method, as test_switch_outgoing_damage_skips_a_move
    # _with_no_pp does.
  end

  attr_accessor :category

  def pbIsDamaging?; @basedamage > 0; end
  def pbIsStatus?; @basedamage <= 0; end
  def pbTypeModifier(_type, _attacker, _target); @typemod; end
  def pbType(_type, _attacker, _target); @type; end
  def pbIsPhysical?(_type); @category == 0; end
  def isContactMove?; @contact; end
  def isHealingMove?; @healing; end
  def pbIsMultiHit; @multi_hit; end
  def canMagicCoat?; @magic_coat; end
  def isBombMove?; @bomb ||= false; end
  attr_writer :bomb
end

# A party entry (never on the field). switch_actions and entry_hazard_pct read these.
class StubPokemon
  attr_accessor :species, :hp, :totalhp, :type1, :type2, :ability, :item, :moves, :speed,
                :form, :status

  def initialize(options = {})
    @species = options.fetch(:species, 1)
    # A Mega changes stats and ability without changing species, and burn halves
    # physical damage: both are in the matrix's per-body signature.
    @form    = options.fetch(:form, 0)
    @status  = options.fetch(:status, 0)
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
                :speed, :partner, :opposite, :pokemon, :mold_breaker, :can_status, :form

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
    @form        = options.fetch(:form, 0)
    @airborne    = options.fetch(:airborne, false)
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
  # :airborne => true for an item or effect, :levitate for the ability, which the
  # engine's ignoreability flag (Mold Breaker) walks through.
  attr_accessor :airborne
  def isAirborne?(ignore = false)
    return !ignore if @airborne == :levitate
    @airborne ? true : false
  end
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
  def pbIsOpposing?(other); (@index & 1) != (other & 1); end
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
      if other.effects[PBEffects::LockOnPos] == index && other.effects[PBEffects::LockOn] > 0
        other.effects[PBEffects::LockOn] = 0
        other.effects[PBEffects::LockOnPos] = -1
      end
      # Realidea's own fourth cross-battler write, which stock v16 does not make.
      if other.effects[PBEffects::MultiTurnUser] == index
        other.effects[PBEffects::MultiTurn] = 0
        other.effects[PBEffects::MultiTurnUser] = -1
      end
    end
  end

  def pbInitPokemon(pokemon, party_index)
    @species = pokemon.species
    @form = (pokemon.form rescue 0)
    @status = (pokemon.status rescue 0)
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
  attr_reader :stock_choice, :registered
  attr_accessor :battlers, :doublebattle, :turncount, :sides, :field, :parties,
                :weather, :owner, :score, :choices, :rng_draws

  def initialize
    @choices = [[0, 0, nil, -1], [0, 0, nil, -1], [0, 0, nil, -1], [0, 0, nil, -1]]
    @registered = []
    @rng_draws = 0
    @battlers = [nil, nil, nil, nil]
    @doublebattle = false
    @turncount = 0
    @sides = [StubSide.new, StubSide.new]
    @field = StubField.new
    @parties = [[], []]
    @weather = 0
    @score = 100
  end

  # The stock path registers, the way the engine's own does, so a shadow run has
  # something to read back. Move id 97 is arbitrary and only has to differ from
  # whatever a test's stubbed plan chooses.
  def pbChooseMoves(index); pbStockRegister(index); end
  def pbDefaultChooseEnemyCommand(index); pbStockRegister(index); end
  def pbStockRegister(index)
    @stock_choice = index
    @choices[index] = [1, 3, StubMove.new(:id => 97), -1]
    index
  end
  def pbCanShowCommands?(_index); true; end
  def pbIsOpposing?(index); index.odd?; end
  def opponent; Object.new; end
  def pbGetOwner(_index); @owner; end
  def pbWeather; @weather; end
  def pbAIRandom(_limit); @rng_draws += 1; 0; end
  def pbParty(index); @parties[index & 1]; end
  def pbOpposingParty(index); @parties[(index & 1) ^ 1]; end
  def pbCanChooseMove?(_index, _slot, _show); true; end
  def pbCanSwitch?(index, slot, _show)
    entry = pbParty(index)[slot]
    !entry.nil? && entry.hp > 0
  end
  # The engine's lax legality (no trapping reads), which the replacement path uses.
  def pbCanSwitchLax?(index, slot, _show)
    entry = pbParty(index)[slot]
    !entry.nil? && entry.hp > 0 && slot != (@battlers[index].pokemonIndex rescue -1)
  end
  # Stock's replacement chooser, as a marker the tests can tell from a real slot.
  def pbDefaultChooseNewEnemy(_index, _party); :stock; end
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
  def pbRegisterMove(i, slot, _show); @registered << [:move, i, slot]; true; end
  def pbRegisterSwitch(i, slot); @registered << [:switch, i, slot]; true; end
  def pbRegisterTarget(_i, _t); true; end
end

require File.join(root, "adapters", "realidea", "Portable_AI_Adapter")

class PortableAIRealideaAdapterTest < Test::Unit::TestCase
  Owner = Struct.new(:skill, :skillCode)

  def setup
    $PORTABLE_AI_ENABLED = false
    $PORTABLE_AI_CONFIG = nil
    $PORTABLE_AI_SHADOW = false
  end

  def teardown
    $PORTABLE_AI_ENABLED = false
    $PORTABLE_AI_CONFIG = nil
    $PORTABLE_AI_SHADOW = false
    $PORTABLE_AI_REPLACEMENT = nil
  end

  # --- 0.6.3 faint replacement --------------------------------------------------
  #
  # A fainted actor at 1 and two bench bodies: slot 1 at 5% HP, which the foe's Tackle
  # (20% here) removes on entry, and slot 2 at full health. Stock's chooser sums the
  # type chart over each body's moves and would not see the difference.
  def replacement_battle
    battle = contract_battle
    battle.battlers[0].moves = [StubMove.new(:id => PBMoves::TACKLE, :basedamage => 40)]
    battle.battlers[1].hp = 0
    battle.parties[1] = [
      StubPokemon.new(:species => 1),
      StubPokemon.new(:species => 3, :hp => 5, :totalhp => 100,
                      :moves => [StubMove.new(:id => PBMoves::TACKLE, :basedamage => 40)]),
      StubPokemon.new(:species => 4, :hp => 100, :totalhp => 100,
                      :moves => [StubMove.new(:id => PBMoves::TACKLE, :basedamage => 40)])
    ]
    battle
  end

  def test_replacement_prefers_the_body_that_survives_entry
    $PORTABLE_AI_ENABLED = true
    battle = replacement_battle
    assert_equal(2, PortableAIRealidea.choose_replacement(battle, 1, battle.parties[1]))
    assert_equal(2, battle.pbDefaultChooseNewEnemy(1, battle.parties[1]))
  end

  def test_replacement_is_stocks_when_off_or_not_portable_driven
    battle = replacement_battle
    # Portable not enabled at all.
    assert_equal(:stock, battle.pbDefaultChooseNewEnemy(1, battle.parties[1]))
    # Enabled, but the run says replacement=stock.
    $PORTABLE_AI_ENABLED = true
    $PORTABLE_AI_REPLACEMENT = false
    assert_equal(:stock, battle.pbDefaultChooseNewEnemy(1, battle.parties[1]))
    # The shadow arm is not Portable-driven: its replacements stay stock's, or the
    # observed battle would no longer be the stock battle.
    $PORTABLE_AI_REPLACEMENT = nil
    $PORTABLE_AI_SHADOW = true
    assert_equal(:stock, battle.pbDefaultChooseNewEnemy(1, battle.parties[1]))
    # The player's seat is never Portable's.
    $PORTABLE_AI_SHADOW = false
    assert_equal(:stock, battle.pbDefaultChooseNewEnemy(0, battle.parties[0]))
  end

  def test_replacement_offers_only_bodies_the_engine_would_accept
    $PORTABLE_AI_ENABLED = true
    battle = replacement_battle
    battle.parties[1][2].hp = 0            # the healthy body is gone too
    # Only the 5% body is legal; it is still the answer, because a bad legal body beats
    # handing the choice back to a chooser that would pick the same one.
    assert_equal(1, PortableAIRealidea.choose_replacement(battle, 1, battle.parties[1]))
    battle.parties[1][1].hp = 0
    # Nothing legal: nil, and the hook falls through to stock.
    assert_nil(PortableAIRealidea.choose_replacement(battle, 1, battle.parties[1]))
    assert_equal(:stock, battle.pbDefaultChooseNewEnemy(1, battle.parties[1]))
  end

  def test_replacement_is_traced_as_a_forced_switch
    $PORTABLE_AI_ENABLED = true
    battle = replacement_battle
    battle.instance_variable_set(:@portable_ai_decision_trace, [])
    battle.pbDefaultChooseNewEnemy(1, battle.parties[1])
    trace = battle.instance_variable_get(:@portable_ai_decision_trace)
    assert_equal(1, trace.length)
    assert_equal("switch", trace[0]["type"])
    assert_equal(true, trace[0]["forced"])
    assert_equal(2, trace[0]["slot"])
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

  # --- ability absorbs -------------------------------------------------------
  #
  # pbTypeModifier (082:405) is ability-blind, and the engine's own
  # pbTypeImmunityByAbility (:318) cannot be called from the AI -- it raises the
  # target's stats, heals it and prints. Without the read-only mirror, a Thunderbolt
  # into Lightning Rod came back neutral and the core scored it as a kill; the
  # d_redirect_by_foe_partner corpus card caught it in the first 0.6.2 probe run.

  def absorb_case(ability, move_type, options = {})
    target = StubBattler.new(:index => 0, :ability => ability)
    attacker = StubBattler.new(:index => 1,
                               :mold_breaker => options.fetch(:mold_breaker, false))
    move = StubMove.new(:type => move_type)
    move.bomb = options.fetch(:bomb, false)
    PortableAIRealidea.type_effectiveness(PokeBattle_Battle.new, move, attacker, target)
  end

  def test_an_absorbing_ability_makes_the_move_do_nothing
    assert_equal(0.0, absorb_case(PBAbilities::LIGHTNINGROD, PBTypes::ELECTRIC))
    assert_equal(0.0, absorb_case(PBAbilities::VOLTABSORB, PBTypes::ELECTRIC))
    assert_equal(0.0, absorb_case(PBAbilities::WATERABSORB, PBTypes::WATER))
    assert_equal(0.0, absorb_case(PBAbilities::SAPSIPPER, PBTypes::GRASS))
    assert_equal(0.0, absorb_case(PBAbilities::FLASHFIRE, PBTypes::FIRE))
  end

  def test_the_absorb_only_applies_to_its_own_type
    assert_equal(1.0, absorb_case(PBAbilities::LIGHTNINGROD, PBTypes::WATER))
    assert_equal(1.0, absorb_case(PBAbilities::STURDY, PBTypes::ELECTRIC))
  end

  # Both guards the engine opens pbTypeImmunityByAbility with.
  def test_mold_breaker_walks_through_an_absorb
    assert_equal(1.0, absorb_case(PBAbilities::LIGHTNINGROD, PBTypes::ELECTRIC,
                                  :mold_breaker => true))
  end

  def test_bulletproof_keys_off_the_bomb_flag_not_the_type
    assert_equal(0.0, absorb_case(PBAbilities::BULLETPROOF, PBTypes::NORMAL,
                                  :bomb => true))
    assert_equal(1.0, absorb_case(PBAbilities::BULLETPROOF, PBTypes::NORMAL))
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
    format turn weather trick_room_active tailwind_active actors targets memory matrix
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
    physical_attacker special_attacker substitute partner_ability trapped
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

  # Keys the Reborn adapter exports that this engine CANNOT supply, listed so a future
  # editor has to read the reason before adding one. failed_last_turn has no readable
  # source here: PBEffects::LastMoveFailed (075_PBEffects.rb:170) is declared in the
  # move-usage namespace at the same index as the battler effect BideDamage, is
  # initialised to false and is never set true anywhere in the build, and
  # successStates[i].useState is set to 2 only on the damaging path so a successful
  # status move reads back as failed. Absent, the core's move_memory rule is inert.
  ENGINE_GAPS = %w[failed_last_turn]

  def test_keys_this_engine_cannot_supply_stay_absent
    move = contract_snapshot["actors"][0]["actions"].find { |a| a["type"] == "move" }
    present = ENGINE_GAPS.select { |key| move.key?(key) }
    assert_equal([], present,
                 "exported a key this engine has no sound source for")
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

  # PokeBattle_Battler#initialize reaches across and clears Lock-On (080:338-345),
  # infatuation (:374-378) and Mean Look (:418-424) on everything pointing at the index
  # being built, so building a fake at the actor's own index would silently cancel all
  # three on a board it is only measuring.
  def test_building_a_fake_battler_leaves_the_real_board_alone
    battle = entry_battle
    foe = battle.battlers[0]
    foe.effects[PBEffects::Attract] = 1
    foe.effects[PBEffects::MeanLook] = 1
    foe.effects[PBEffects::LockOn] = 2
    foe.effects[PBEffects::LockOnPos] = 1
    PortableAIRealidea.switch_incoming_damage(
      battle, StubPokemon.new, 1, battle.battlers[1], [0], 100)
    assert_equal(1, foe.effects[PBEffects::Attract])
    assert_equal(1, foe.effects[PBEffects::MeanLook])
    assert_equal(2, foe.effects[PBEffects::LockOn])
    assert_equal(1, foe.effects[PBEffects::LockOnPos])
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

  # 0.6.4. A spent move is not a hit the candidate has: the field view drops it
  # through pbCanChooseMove? and the bench estimate must agree, or the two disagree by
  # a whole move and the body goes straight back out. Keyed (switch_estimate_pp) so
  # the control can reproduce 0.6.3's estimate.
  def test_switch_outgoing_damage_skips_a_move_with_no_pp
    battle = entry_battle
    spent = StubMove.new(:basedamage => 120)
    spent.define_singleton_method(:pp) { 0 }
    live = StubMove.new(:basedamage => 40)
    live.define_singleton_method(:pp) { 5 }
    candidate = StubPokemon.new(:moves => [spent, live])
    assert_equal(20.0, PortableAIRealidea.switch_outgoing_damage(
      battle, candidate, 1, battle.battlers[1], [0], 100))
    # Every move spent: nothing to hit with, and the estimate says so.
    both = StubPokemon.new(:moves => [spent])
    assert_equal(0.0, PortableAIRealidea.switch_outgoing_damage(
      battle, both, 1, battle.battlers[1], [0], 100))
    # A move that carries no PP field (an older stub, a move object without one) is
    # not held to a number nobody has.
    assert_equal(60.0, PortableAIRealidea.switch_outgoing_damage(
      battle, StubPokemon.new(:moves => [StubMove.new(:basedamage => 120)]), 1,
      battle.battlers[1], [0], 100))
    $PORTABLE_AI_CONFIG = { "switch_estimate_pp" => false }
    assert_equal(60.0, PortableAIRealidea.switch_outgoing_damage(
      battle, candidate, 1, battle.battlers[1], [0], 100))
  ensure
    $PORTABLE_AI_CONFIG = nil
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
  # Building a fake battler at a live index runs the engine's pbInitEffects, which
  # clears every effect on OTHER battlers that points at that index. Realidea clears a
  # partial trap there as well as Lock-On, Attract and Mean Look, so without MultiTurn
  # in the restore list, merely WEIGHING a switch while holding a foe in Infestation set
  # that foe free. The shadow arm is what surfaced it: 14 of 60 observed battles failed
  # to reproduce their unobserved twins, all of them the roster's one Infestation user.
  def test_weighing_a_switch_does_not_free_a_trapped_foe
    battle = PokeBattle_Battle.new
    trapped = StubBattler.new(:index => 0)
    trapped.effects[PBEffects::MultiTurn] = 3
    trapped.effects[PBEffects::MultiTurnUser] = 1
    battle.battlers[0] = trapped
    battle.battlers[1] = StubBattler.new(:index => 1)
    pokemon = StubPokemon.new
    assert_not_nil(PortableAIRealidea.fake_battler(battle, pokemon, 0, 1))
    assert_equal(3, trapped.effects[PBEffects::MultiTurn])
    assert_equal(1, trapped.effects[PBEffects::MultiTurnUser])
  end

  # The list is only correct while it matches the engine it was read from.
  def test_restore_list_covers_every_cross_battler_write
    assert_equal([:Attract, :LockOn, :LockOnPos, :MeanLook, :MultiTurn, :MultiTurnUser],
                 PortableAIRealidea::RESTORED_ON_FAKE.sort_by { |s| s.to_s })
  end

  # --- what a trace carries --------------------------------------------------

  SNAPSHOT = {
    "actors" => [{
      "index" => 1, "species" => 213, "hp_pct" => 70.0, "status" => 4,
      "ability" => "STURDY", "item" => "MENTALHERB", "speed" => 46, "faster" => false,
      "positive_stage_total" => 2, "negative_stage_total" => -1,
      "incoming_damage_pct" => 32.0, "certain_incoming_damage_pct" => 32.0,
      "threatened_lethal" => false
    }],
    "targets" => [{
      "index" => 0, "species" => 212, "hp_pct" => 88.0, "status" => 0,
      "speed" => 239, "ability" => "TECHNICIAN", "item" => "SCIZORITE",
      "positive_stages" => 0
    }]
  }

  # A readout that cannot say who was on the field is not a readout. `parties` cannot
  # answer it either: that holds FINAL hp, not hp at the moment of the decision.
  def test_view_names_both_sides_with_their_state_at_decision_time
    view = PortableAIRealidea.view_trace(SNAPSHOT, 1)
    assert_equal("Shuckle", view["species"])
    assert_equal(70.0, view["hp_pct"])
    assert_equal(4, view["status"])
    assert_equal("MENTALHERB", view["item"])
    assert_equal(2, view["positive_stage_total"])
    foe = view["targets"][0]
    assert_equal("Scizor", foe["species"])
    assert_equal(88.0, foe["hp_pct"])
    assert_equal(239, foe["speed"])
  end

  # The numeric id is what the core reads; it must never be what a reader sees.
  def test_species_is_named_on_the_way_out_only
    assert_equal("Shuckle", PortableAIRealidea.species_name(213))
    assert_equal(213, SNAPSHOT["actors"][0]["species"])
  end

  def test_unknown_species_falls_back_to_its_id_rather_than_vanishing
    assert_equal("99999", PortableAIRealidea.species_name(99999))
  end

  # The core scores and explains every option; the trace reads that out rather than
  # recomputing it. Without it a reader sees the chosen move and no alternative.
  def test_candidates_carry_every_option_with_its_score_and_reasons
    plan = {
      "actions" => [{ "actor_index" => 1 }],
      "diagnostics" => { "rankings" => [[
        { "type" => "move", "slot" => 0, "move_id" => "SUCKERPUNCH", "score" => 194.0,
          "power" => 80, "effectiveness" => 1, "expected_damage_pct" => 49.0,
          "reasons" => [["engine_base", 155], ["expected_damage", 39]] },
        { "type" => "switch", "slot" => 4, "species" => 212, "score" => -1000000.0,
          "reasons" => [["no_escape_reason", -1000000]] }
      ]] }
    }
    out = PortableAIRealidea.candidate_trace(plan, 1)
    assert_equal(2, out.length)
    assert_equal("SUCKERPUNCH", out[0]["move_id"])
    assert_equal(49.0, out[0]["expected_damage_pct"])
    assert_equal([["engine_base", 155], ["expected_damage", 39]], out[0]["reasons"])
    assert_equal("Scizor", out[1]["species"])
  end

  def test_candidates_are_capped_so_one_turn_cannot_dominate_a_file
    ranked = (0...20).map { |i| { "type" => "move", "slot" => i, "score" => 1.0 * i } }
    plan = { "actions" => [{ "actor_index" => 1 }],
             "diagnostics" => { "rankings" => [ranked] } }
    assert_equal(PortableAIRealidea::TRACE_CANDIDATE_LIMIT,
                 PortableAIRealidea.candidate_trace(plan, 1).length)
  end

  def test_candidate_trace_of_an_actor_with_no_plan_is_empty_not_an_error
    assert_equal([], PortableAIRealidea.candidate_trace({}, 1))
  end

  # --- shadow arm ------------------------------------------------------------

  def with_stubbed_plan(plan)
    singleton = (class << PortableAIRealidea; self; end)
    singleton.send(:alias_method, :real_plan_for, :plan_for)
    singleton.send(:define_method, :plan_for) { |_battle| plan }
    yield
  ensure
    singleton.send(:remove_method, :plan_for)
    singleton.send(:alias_method, :plan_for, :real_plan_for)
    singleton.send(:remove_method, :real_plan_for)
  end

  def test_shadow_enables_the_adapter_without_the_live_marker
    $PORTABLE_AI_SHADOW = true
    battle = PokeBattle_Battle.new
    assert_equal(true, PortableAIRealidea.shadow?)
    assert_equal(true, PortableAIRealidea.active?)
    assert_equal(true, PortableAIRealidea.enabled_for?(battle, 1))
    assert_equal(false, PortableAIRealidea.enabled_for?(battle, 0))
  end

  # The whole point of the arm: the host still chooses, and nothing the observer does
  # reaches the battle. A registration here would mean the observed battle is not the
  # battle that runs unobserved, which voids every comparison drawn from it.
  def test_shadow_records_both_answers_and_registers_nothing
    $PORTABLE_AI_SHADOW = true
    battle = PokeBattle_Battle.new
    battle.instance_variable_set(:@portable_ai_shadow_trace, [])
    plan = { "actions" => [{ "actor_index" => 1, "type" => "move", "slot" => 0,
                             "move_id" => "BULLETPUNCH", "numeric_move_id" => 418,
                             "target" => nil, "score" => 820.0 }] }
    with_stubbed_plan(plan) { battle.pbDefaultChooseEnemyCommand(1) }
    assert_equal([], battle.registered)
    assert_equal(1, battle.stock_choice)
    trace = battle.instance_variable_get(:@portable_ai_shadow_trace)
    assert_equal(1, trace.length)
    assert_equal(418, trace[0]["portable"]["numeric_move_id"])
    assert_equal("move", trace[0]["stock"]["type"])
    assert_equal(97, trace[0]["stock"]["numeric_move_id"])
  end

  # A crash inside the observer must not remove the turn from the record: absent is
  # indistinguishable from "nothing to decide", so a dropped turn silently shrinks the
  # denominator of every agreement figure.
  def test_a_failed_observation_is_recorded_not_dropped
    $PORTABLE_AI_SHADOW = true
    battle = PokeBattle_Battle.new
    battle.instance_variable_set(:@portable_ai_shadow_trace, [])
    singleton = (class << PortableAIRealidea; self; end)
    singleton.send(:alias_method, :real_plan_for, :plan_for)
    singleton.send(:define_method, :plan_for) { |_b| raise ZeroDivisionError, "divided by 0" }
    begin
      battle.pbDefaultChooseEnemyCommand(1)
    ensure
      singleton.send(:remove_method, :plan_for)
      singleton.send(:alias_method, :plan_for, :real_plan_for)
      singleton.send(:remove_method, :real_plan_for)
    end
    trace = battle.instance_variable_get(:@portable_ai_shadow_trace)
    assert_equal(1, trace.length)
    assert_nil(trace[0]["portable"])
    assert_equal("ZeroDivisionError: divided by 0", trace[0]["observer_error"])
    # and the host still chose, unaffected
    assert_equal(1, battle.stock_choice)
  end

  # A readout showing one side of a two-sided turn cannot explain the board changing.
  # command_phase drives all four seats in index order, so seat 0 has already registered
  # by the time seat 1's entry is written -- that ordering is what makes this possible.
  def test_the_other_sides_choice_is_attached_to_the_turn
    $PORTABLE_AI_SHADOW = true
    battle = PokeBattle_Battle.new
    battle.instance_variable_set(:@portable_ai_shadow_trace, [])
    plan = { "actions" => [{ "actor_index" => 1, "type" => "move", "slot" => 0,
                             "numeric_move_id" => 418 }] }
    with_stubbed_plan(plan) do
      battle.pbDefaultChooseEnemyCommand(0)   # the far side registers first
      battle.pbDefaultChooseEnemyCommand(1)   # the measured seat
    end
    trace = battle.instance_variable_get(:@portable_ai_shadow_trace)
    assert_equal(1, trace.length)             # seat 0 is not a second entry
    assert_equal("move", trace[0]["foe"]["0"]["type"])
    assert_equal(97, trace[0]["foe"]["0"]["numeric_move_id"])
  end

  # A stale foe choice must not bleed into a later turn and be read as this turn's.
  def test_foe_choices_do_not_survive_into_the_next_turn
    $PORTABLE_AI_SHADOW = true
    battle = PokeBattle_Battle.new
    battle.pbDefaultChooseEnemyCommand(0)
    assert_not_nil(PortableAIRealidea.foe_choices(battle))
    battle.turncount = 1
    assert_nil(PortableAIRealidea.foe_choices(battle))
  end

  # Both command hooks can reach one battler in a turn; a second entry would
  # double-count that turn in any disagreement rate.
  def test_shadow_records_one_entry_per_battler_per_turn
    $PORTABLE_AI_SHADOW = true
    battle = PokeBattle_Battle.new
    battle.instance_variable_set(:@portable_ai_shadow_trace, [])
    plan = { "actions" => [{ "actor_index" => 1, "type" => "move", "slot" => 0,
                             "numeric_move_id" => 418 }] }
    with_stubbed_plan(plan) do
      battle.pbDefaultChooseEnemyCommand(1)
      battle.pbChooseMoves(1)
    end
    assert_equal(1, battle.instance_variable_get(:@portable_ai_shadow_trace).length)
  end

  # The engine's own scorer rolls: pbGetMoveScore does it inside the stat-boost
  # handlers, and the snapshot calls it once per candidate move. Those rolls must come
  # from the observer's generator, not the battle's -- a first 60-battle shadow run
  # diverged on exactly the 14 matchups whose observed team carried setup moves.
  # The stubbed plan stands in for that scoring: it rolls through the battle, and the
  # battle must not feel it.
  def test_observing_diverts_every_roll_away_from_the_battle
    $PORTABLE_AI_SHADOW = true
    battle = PokeBattle_Battle.new
    battle.instance_variable_set(:@portable_ai_shadow_trace, [])
    plan = { "actions" => [{ "actor_index" => 1, "type" => "move", "slot" => 0 }] }
    singleton = (class << PortableAIRealidea; self; end)
    singleton.send(:alias_method, :real_plan_for, :plan_for)
    singleton.send(:define_method, :plan_for) do |b|
      3.times { b.pbAIRandom(10) }
      plan
    end
    begin
      battle.pbDefaultChooseEnemyCommand(1)
    ensure
      singleton.send(:remove_method, :plan_for)
      singleton.send(:alias_method, :plan_for, :real_plan_for)
      singleton.send(:remove_method, :real_plan_for)
    end
    assert_equal(0, battle.rng_draws)
    assert_equal(
      3, battle.instance_variable_get(:@portable_ai_shadow_rng_draws).to_i)
  end

  # Outside an observation the override must be the engine's own method, or every live
  # arm and all of normal play would quietly lose its randomness.
  def test_rolls_outside_an_observation_reach_the_battle
    battle = PokeBattle_Battle.new
    3.times { battle.pbAIRandom(10) }
    assert_equal(3, battle.rng_draws)
  end

  # Realidea numbers a switch 2 where Reborn numbers it 3, so this is read off this
  # engine rather than shared with the other adapter.
  def test_host_switch_choice_is_labelled_with_realidea_numbering
    choice = PortableAIRealidea.describe_choice([2, 4, nil, -1])
    assert_equal("switch", choice["type"])
    assert_equal(4, choice["slot"])
  end

  # A code with no label must not be given one: a mislabelled choice reads as a
  # disagreement that never happened.
  def test_unknown_choice_code_is_reported_not_guessed
    choice = PortableAIRealidea.describe_choice([9, 0, nil, -1])
    assert_equal("unregistered", choice["type"])
    assert_equal(9, choice["code"])
  end

  def test_neutral_rng_is_deterministic_and_counts_its_draws
    a = PortableAIRealidea::NeutralRNG.new(7)
    b = PortableAIRealidea::NeutralRNG.new(7)
    assert_equal(0, a.draws)
    drawn = (0...5).map { a.rand(100) }
    assert_equal(drawn, (0...5).map { b.rand(100) })
    assert_equal(5, a.draws)
    assert_equal(true, drawn.all? { |value| value >= 0 && value < 100 })
    assert_equal(0, PortableAIRealidea::NeutralRNG.new(7).rand(0))
  end

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

  # --- 0.6.5 the party x party damage matrix ------------------------------------
  #
  # pbRoughDamage in the stub battle returns totalhp * basedamage / 200, so a cell's
  # percentage is half the base damage: bp 40 is 20%, bp 60 is 30%, bp 80 is 40%.

  def matrix_battle
    battle = PokeBattle_Battle.new
    foe = StubBattler.new(:index => 0, :species => 2, :speed => 90, :pokemonIndex => 0,
                          :moves => [StubMove.new(:id => PBMoves::TACKLE,
                                                  :basedamage => 40)])
    actor = StubBattler.new(:index => 1, :species => 212, :speed => 120,
                            :pokemonIndex => 0,
                            :moves => [StubMove.new(:id => PBMoves::TACKLE,
                                                    :basedamage => 60)])
    actor.opposite = foe
    foe.opposite = actor
    battle.battlers[0] = foe
    battle.battlers[1] = actor
    battle.parties = [
      [StubPokemon.new(:species => 2, :moves => [StubMove.new(:basedamage => 40)]),
       StubPokemon.new(:species => 4, :moves => [StubMove.new(:basedamage => 20)])],
      [StubPokemon.new(:species => 212, :moves => [StubMove.new(:basedamage => 60)]),
       StubPokemon.new(:species => 213, :speed => 50,
                       :moves => [StubMove.new(:basedamage => 80)])]
    ]
    battle.owner = Owner.new(100, "")
    battle
  end

  def matrix_of(battle, skill = 100)
    PortableAIRealidea.party_matrix(battle, 1, [0], skill)
  end

  def test_party_matrix_has_a_cell_for_every_live_pair_and_none_for_the_dead
    matrix = matrix_of(matrix_battle)
    assert_equal(%w[0:0 0:1 1:0 1:1], matrix["cells"].keys.sort)
    # A fainted body is not a row and not a column: nothing has to answer it and it
    # answers nothing.
    battle = matrix_battle
    battle.parties[0][1].hp = 0
    assert_equal(%w[0:0 1:0], matrix_of(battle)["cells"].keys.sort)
    assert_equal(false, matrix_of(battle)["foe"][1]["alive"])
  end

  def test_party_matrix_maps_seats_to_slots_on_both_sides
    matrix = matrix_of(matrix_battle)
    assert_equal(1, matrix["own"][0]["index"])       # the actor, on the field
    assert_nil(matrix["own"][1]["index"])            # on the bench, no seat
    assert_equal(0, matrix["foe"][0]["index"])
    assert_nil(matrix["foe"][1]["index"])
    assert_equal(0, PortableAI.matrix_slot(matrix["own"], 1))
    assert_equal(0, PortableAI.matrix_slot(matrix["foe"], 0))
    assert_nil(PortableAI.matrix_slot(matrix["own"], 3))
  end

  def test_party_matrix_cells_carry_both_directions_category_move_and_speed_order
    battle = matrix_battle
    battle.battlers[1].moves = [StubMove.new(:id => PBMoves::TACKLE, :basedamage => 60,
                                             :category => 1)]
    cell = matrix_of(battle)["cells"]["0:0"]
    assert_equal(30.0, cell["out"])
    assert_equal("special", cell["out_cat"])
    assert_equal("TACKLE", cell["out_move"])
    assert_equal(20.0, cell["in"])
    assert_equal("physical", cell["in_cat"])
    assert_equal(true, cell["faster"])               # 120 against 90
    # The bench body is slower than the same foe, and a bench Speed is the bare party
    # stat, exactly as switch_candidate_faster reads it.
    assert_equal(false, matrix_of(battle)["cells"]["1:0"]["faster"])
  end

  # 0.7.4. The cell keeps every damaging move it rolled, not only the best, so a
  # reader with a particular move in hand can price THAT move against a body on the
  # bench. A move that does nothing to the body is a 0 in the list, which is a
  # different fact from not being in it.
  def test_party_matrix_cells_carry_every_damaging_move_by_key
    battle = matrix_battle
    battle.battlers[1].moves = [
      StubMove.new(:id => PBMoves::TACKLE, :basedamage => 60, :category => 0),
      StubMove.new(:id => PBMoves::SURF, :basedamage => 20, :category => 1),
      StubMove.new(:id => PBMoves::GROWL, :basedamage => 0)
    ]
    cell = matrix_of(battle)["cells"]["0:0"]
    assert_equal(30.0, cell["out"])
    assert_equal("TACKLE", cell["out_move"])
    # 0.7.9 (version 4): every move, the status move included at pct 0, each with
    # its hit chance, priority bracket, whether it deals damage, and the effect
    # triple the root actions carry -- what the search needs to play the move.
    assert_equal(%w[GROWL SURF TACKLE], cell["out_moves"].keys.sort)
    assert_equal({ "pct" => 30.0, "cat" => "physical", "damaging" => true, "acc" => 100.0,
                   "priority" => 0, "effect" => [nil, nil, nil] }, cell["out_moves"]["TACKLE"])
    assert_equal(10.0, cell["out_moves"]["SURF"]["pct"])
    assert_equal("special", cell["out_moves"]["SURF"]["cat"])
    assert_equal(0.0, cell["out_moves"]["GROWL"]["pct"])
    assert_equal(false, cell["out_moves"]["GROWL"]["damaging"])
    # A status move is never the cell's best, whatever its position in the list.
    assert_equal("TACKLE", cell["out_move"])
    # The side table carries what a projected end of turn ticks on (version 4).
    side = matrix_of(battle)["own"][0]
    assert_equal(true, side.has_key?("status") && side.has_key?("item") &&
                       side.has_key?("ability") && side.has_key?("entry_damage_pct"))
    # The pair the engine cannot price at all is still nil, not an empty list.
    # (A fresh battle: the first one's cells are cached against their signature.)
    broken = matrix_battle
    broken.define_singleton_method(:pbRoughDamage) { |*_a| raise ZeroDivisionError }
    assert_nil(matrix_of(broken)["cells"]["0:0"]["out"])
    assert_nil(matrix_of(broken)["cells"]["0:0"]["out_moves"])
  end

  # The active bodies are priced through their REAL battlers, so their stages, their
  # Mega form and the item they are holding are all in the number. A benched body has
  # no stages to read and arrives at zero.
  def test_party_matrix_uses_the_real_battler_for_actives_and_a_fake_for_the_bench
    battle = matrix_battle
    battle.define_singleton_method(:pbRoughDamage) do |_m, attacker, target, _s, base|
      target.totalhp * base * (2 + attacker.stages[PBStats::ATTACK]) / 400.0
    end
    plain = matrix_of(battle)["cells"]
    assert_equal(20.0, plain["0:0"]["in"])
    battle.battlers[0].stages[PBStats::ATTACK] = 2
    boosted = matrix_of(battle)["cells"]
    assert_equal(40.0, boosted["0:0"]["in"])
    # Their bench cannot carry a stage, so its column did not move.
    assert_equal(plain["0:1"]["in"], boosted["0:1"]["in"])
  end

  # A counting battle: every cell costs one pbRoughDamage call per direction per move,
  # so what is re-rolled is directly observable.
  def counting_battle
    battle = matrix_battle
    battle.instance_variable_set(:@rough_calls, 0)
    battle.define_singleton_method(:rough_calls) { @rough_calls }
    battle.define_singleton_method(:reset_rough_calls) { @rough_calls = 0 }
    battle.define_singleton_method(:pbRoughDamage) do |_m, _a, target, _s, base|
      @rough_calls += 1
      target.totalhp * base / 200.0
    end
    battle
  end

  def test_party_matrix_rerolls_only_dirty_cells
    battle = counting_battle
    matrix_of(battle)
    assert_equal(8, battle.rough_calls)              # four pairs, both directions
    # Nothing changed: the whole grid is reused.
    battle.reset_rough_calls
    matrix_of(battle)
    assert_equal(0, battle.rough_calls)
    # HP is deliberately not in the signature -- every cell is a percentage of a max
    # HP that does not move, and the verdicts are derived from the side tables.
    battle.battlers[0].hp = 40
    battle.reset_rough_calls
    matrix_of(battle)
    assert_equal(0, battle.rough_calls)
    # One foe's stages: its column, and nothing else.
    battle.battlers[0].stages[PBStats::ATTACK] = 2
    battle.reset_rough_calls
    matrix_of(battle)
    assert_equal(4, battle.rough_calls)
    # The weather moves every number there is.
    battle.weather = PBWeather::SANDSTORM
    battle.reset_rough_calls
    matrix_of(battle)
    assert_equal(8, battle.rough_calls)
  end

  # The 0.6.4 guard, extended: the matrix builds fakes at BOTH seats, so a board
  # effect pointing at either one has to survive the build.
  def test_party_matrix_build_leaves_the_board_alone
    battle = matrix_battle
    battle.battlers[0].effects[PBEffects::Attract] = 1
    battle.battlers[0].effects[PBEffects::MeanLook] = 1
    battle.battlers[0].effects[PBEffects::LockOn] = 2
    battle.battlers[0].effects[PBEffects::LockOnPos] = 1
    battle.battlers[1].effects[PBEffects::MultiTurn] = 3
    battle.battlers[1].effects[PBEffects::MultiTurnUser] = 0
    matrix_of(battle)
    assert_equal(1, battle.battlers[0].effects[PBEffects::Attract])
    assert_equal(1, battle.battlers[0].effects[PBEffects::MeanLook])
    assert_equal(2, battle.battlers[0].effects[PBEffects::LockOn])
    assert_equal(1, battle.battlers[0].effects[PBEffects::LockOnPos])
    assert_equal(3, battle.battlers[1].effects[PBEffects::MultiTurn])
    assert_equal(0, battle.battlers[1].effects[PBEffects::MultiTurnUser])
  end

  def test_party_matrix_skips_spent_moves_under_the_pp_rule
    battle = matrix_battle
    spent = StubMove.new(:basedamage => 80)
    spent.define_singleton_method(:pp) { 0 }
    live = StubMove.new(:basedamage => 40)
    live.define_singleton_method(:pp) { 5 }
    battle.parties[1][1].moves = [spent, live]
    assert_equal(20.0, matrix_of(battle)["cells"]["1:0"]["out"])
    # The 0.6.3 estimate, restored by the key the bench estimate already reads.
    $PORTABLE_AI_CONFIG = { "switch_estimate_pp" => false }
    battle.instance_variable_set(:@portable_ai_matrix, nil)
    assert_equal(40.0, matrix_of(battle)["cells"]["1:0"]["out"])
  ensure
    $PORTABLE_AI_CONFIG = nil
  end

  # 0% is a claim about the board -- nothing this body has lands. nil is an admission
  # that the engine could not price the pair at all, and the core reads the two
  # differently: a nil `out` loses the pair, a 0.0 `out` is the same verdict but says
  # so honestly.
  def test_a_cell_the_engine_cannot_price_is_nil_not_zero
    battle = matrix_battle
    battle.define_singleton_method(:pbRoughDamage) do |_m, _a, target, _s, base|
      raise ZeroDivisionError, "divided by 0" if target.species == 4
      target.totalhp * base / 200.0
    end
    cells = matrix_of(battle)["cells"]
    assert_nil(cells["0:1"]["out"])
    assert_nil(cells["0:1"]["out_cat"])
    # The other direction is still priced, and so is every other pair.
    assert_equal(10.0, cells["0:1"]["in"])
    assert_equal(30.0, cells["0:0"]["out"])
  end

  def test_party_matrix_is_absent_when_the_key_is_off
    $PORTABLE_AI_CONFIG = { "party_matrix" => false, "sole_answer" => true }
    battle = matrix_battle
    battle.instance_variable_set(:@portable_ai_decision_trace, [])
    snapshot, _skill = PortableAIRealidea.build_snapshot(battle)
    assert(snapshot.key?("matrix"), "the contract key must exist even when nil")
    assert_nil(snapshot["matrix"])
    $PORTABLE_AI_CONFIG = { "sole_answer" => true }
    on, _skill = PortableAIRealidea.build_snapshot(matrix_battle)
    assert_not_nil(on["matrix"])
    # 0.7.7: version 3 is the cell that carries the FOE's per-move rolls beside ours;
    # 0.7.9: version 4 carries every move on both sides, with accuracy and priority.
    assert_equal(4, on["matrix"]["version"])
    cell = on["matrix"]["cells"]["0:0"]
    # Ours is always kept (out_moves, 0.7.4). THEIRS FOLLOWS ITS READER: the foe move
    # axis is the only thing that opens in_moves and it lives behind search_planner,
    # which is off here -- so an ordinary run carries the rolls' summary and not the
    # breakdown, and pays neither the allocation nor the 28% bigger trace.
    assert_equal(true, cell["out_moves"].is_a?(Hash))
    assert_equal(nil, cell["in_moves"])

    $PORTABLE_AI_CONFIG = { "sole_answer" => true, "search_planner" => true }
    searched, _skill = PortableAIRealidea.build_snapshot(matrix_battle)
    cell = searched["matrix"]["cells"]["0:0"]
    assert_equal(true, cell["in_moves"].is_a?(Hash))
    assert_equal(false, cell["in_moves"].empty?)
    # A move in the list is priced and categorised, and the summary `in` is the
    # biggest of them -- so nothing that read `in` before reads anything new, and
    # turning the axis on cannot move a rule-engine decision.
    biggest = 0.0
    cell["in_moves"].each_value { |m| biggest = m["pct"] if m["pct"] > biggest }
    assert_equal(cell["in"], biggest)
    assert_equal(true, cell["in_moves"].has_key?(cell["in_move"]))
  ensure
    $PORTABLE_AI_CONFIG = nil
  end

  # The grid costs about a quarter of decision time to build (57.2 s against 72.6 s
  # over a 60-battle tier set), and at the shipped defaults nothing reads it: both
  # consumers are off, and a player fighting a trainer records no trace. So it follows
  # its readers rather than the clock.
  def test_the_matrix_is_not_built_when_nothing_would_read_it
    # Both consumers ship ON, so "nothing reads it" has to be asked for.
    $PORTABLE_AI_CONFIG = { "sole_answer" => false, "setup_matrix" => false }
    plain, _skill = PortableAIRealidea.build_snapshot(matrix_battle)
    assert_nil(plain["matrix"], "built a grid no rule and no trace would read")
    # A consumer wants it.
    $PORTABLE_AI_CONFIG = { "sole_answer" => false, "setup_matrix" => true }
    wanted, _skill = PortableAIRealidea.build_snapshot(matrix_battle)
    assert_not_nil(wanted["matrix"])
    $PORTABLE_AI_CONFIG = { "sole_answer" => false, "setup_matrix" => false }
    # So does a run that is recording one -- the gauntlet's decision trace, and the
    # shadow observer, which records even with trace=false.
    traced = matrix_battle
    traced.instance_variable_set(:@portable_ai_decision_trace, [])
    assert_not_nil(PortableAIRealidea.build_snapshot(traced)[0]["matrix"])
    shadowed = matrix_battle
    shadowed.instance_variable_set(:@portable_ai_shadow_trace, [])
    assert_not_nil(PortableAIRealidea.build_snapshot(shadowed)[0]["matrix"])
  ensure
    $PORTABLE_AI_CONFIG = nil
  end

  def test_replacement_snapshot_carries_the_matrix
    battle = matrix_battle
    battle.battlers[1].hp = 0
    trace = []
    battle.instance_variable_set(:@portable_ai_decision_trace, trace)
    PortableAIRealidea.choose_replacement(battle, 1, battle.parties[1])
    assert_equal(1, trace.length)
    grid = trace[0]["view"]["matrix"]
    assert_not_nil(grid, "the forced-switch consumer was handed no matrix")
    assert_not_nil(grid["verdicts"]["1:0"])
  end

  def test_the_trace_view_carries_the_verdict_grid_and_names_both_parties
    battle = matrix_battle
    battle.instance_variable_set(:@portable_ai_decision_trace, [])
    snapshot, _skill = PortableAIRealidea.build_snapshot(battle)
    view = PortableAIRealidea.view_trace(snapshot, 1)
    grid = view["matrix"]
    assert_equal(%w[Scizor Shuckle], grid["own"].map { |e| e["species"] })
    assert_equal([true, false], grid["own"].map { |e| e["active"] })
    assert_equal(2, grid["foe"].length)
    # The actor two-shots the foe in front and eats five: a win, from current HP.
    assert_equal("W", grid["verdicts"]["0:0"])
    # The cells themselves are the bulky half and only appear under trace=true.
    assert(!grid.has_key?("cells"))
    $AI_GAUNTLET_TRACE = true
    lean = PortableAIRealidea.view_trace(snapshot, 1)["matrix"]
    assert_equal(30.0, lean["cells"]["0:0"]["out"])
  ensure
    $AI_GAUNTLET_TRACE = false
  end

  def test_a_switch_candidate_names_what_only_it_answers
    $AI_GAUNTLET_TRACE = true
    battle = matrix_battle
    # Their benched body hits for 40%, which the actor cannot outrace, and the bench
    # Shuckle both survives it and outruns it: the only answer this side has to it.
    battle.parties[0][1].moves = [StubMove.new(:basedamage => 80)]
    battle.parties[1][1].moves = [StubMove.new(:basedamage => 80)]
    battle.parties[1][1].speed = 200
    battle.instance_variable_set(:@portable_ai_decision_trace, [])
    snapshot, skill = PortableAIRealidea.build_snapshot(battle)
    assert_equal("L", PortableAI.matrix_verdict(snapshot, 0, 1))
    assert_equal("W", PortableAI.matrix_verdict(snapshot, 1, 1))
    plan = PortableAI.plan(snapshot, PortableAIRealidea.config_for(skill),
                           PortableAIRealidea::BattleRNG.new(battle))
    entries = PortableAIRealidea.candidate_trace(plan, 1, snapshot)
    switch = entries.find { |e| e["type"] == "switch" && e["slot"] == 1 }
    assert_not_nil(switch)
    assert_equal(["4"], switch["sole_answer_to"])
  ensure
    $AI_GAUNTLET_TRACE = false
  end

  # --- 0.6.6 Ground into an airborne body --------------------------------------------
  #
  # pbTypeModifier says nothing about Levitate; pbSuccessCheck does (080:2710). Both
  # the effectiveness the core rejects on and the damage every estimate reads must
  # agree that the move does nothing.

  def airborne_case(airborne, options = {})
    target = StubBattler.new(:index => 0, :airborne => airborne,
                             :ability => options.fetch(:ability, 0))
    attacker = StubBattler.new(:index => 1,
                               :mold_breaker => options.fetch(:mold_breaker, false))
    move = StubMove.new(:type => options.fetch(:type, PBTypes::GROUND),
                        :function => options.fetch(:function, 0x000))
    battle = PokeBattle_Battle.new
    [PortableAIRealidea.type_effectiveness(battle, move, attacker, target),
     PortableAIRealidea.rough_damage_pct(battle, move, attacker, target, 100)]
  end

  def test_ground_into_an_airborne_target_does_nothing_in_both_estimates
    assert_equal([0.0, 0.0], airborne_case(true))
    assert_equal([0.0, 0.0], airborne_case(:levitate))
    assert_equal([1.0, 40.0], airborne_case(false))
  end

  def test_only_ground_is_dodged
    assert_equal([1.0, 40.0], airborne_case(true, :type => PBTypes::WATER))
  end

  def test_mold_breaker_walks_through_levitate_but_not_a_balloon
    assert_equal([1.0, 40.0], airborne_case(:levitate, :mold_breaker => true))
    assert_equal([0.0, 0.0], airborne_case(true, :mold_breaker => true))
  end

  def test_smack_down_lands_on_an_airborne_target
    assert_equal([1.0, 40.0], airborne_case(true, :function => 0x11C))
  end

  def test_airborne_immunity_off_restores_the_blind_estimate
    $PORTABLE_AI_CONFIG = { "airborne_immunity" => false }
    assert_equal([1.0, 40.0], airborne_case(:levitate))
  end

  # --- 0.6.6 the oracle --------------------------------------------------------------
  #
  # With foe_oracle on, the foe's registered choice is read back as its intent and the
  # hit it implies is exported on the actor and on every bench candidate. Off, or
  # with nothing registered, nothing is exported and the snapshot is 0.6.5's.

  def oracle_battle
    battle = contract_battle
    foe = battle.battlers[0]
    foe.moves = [StubMove.new(:id => PBMoves::TACKLE, :basedamage => 40),
                 StubMove.new(:id => PBMoves::POUND, :basedamage => 160)]
    battle
  end

  def test_oracle_exports_the_declared_hit_not_the_worst_one
    $PORTABLE_AI_CONFIG = { "foe_oracle" => true }
    battle = oracle_battle
    battle.choices[0] = [1, 0, battle.battlers[0].moves[0], -1]
    actor = PortableAIRealidea.build_snapshot(battle)[0]["actors"][0]
    assert_equal(80.0, actor["incoming_damage_pct"])
    assert_equal(20.0, actor["predicted_incoming_damage_pct"])
    assert_equal(100.0, actor["predicted_incoming_accuracy"])
    assert_equal("move", actor["predicted_foe"]["0"]["type"])
    switch = actor["actions"].find { |a| a["type"] == "switch" }
    assert_equal(80.0, switch["incoming_damage_pct"])
    assert_equal(20.0, switch["predicted_incoming_damage_pct"])
  end

  def test_a_declared_switch_is_a_free_turn
    $PORTABLE_AI_CONFIG = { "foe_oracle" => true }
    battle = oracle_battle
    battle.choices[0] = [2, 0, nil, -1]
    actor = PortableAIRealidea.build_snapshot(battle)[0]["actors"][0]
    assert_equal(0.0, actor["predicted_incoming_damage_pct"])
    assert_equal("switch", actor["predicted_foe"]["0"]["type"])
    switch = actor["actions"].find { |a| a["type"] == "switch" }
    assert_equal(0.0, switch["predicted_incoming_damage_pct"])
  end

  def test_the_oracle_is_silent_when_off_or_when_nothing_is_registered
    battle = oracle_battle
    battle.choices[0] = [1, 0, battle.battlers[0].moves[0], -1]
    actor = PortableAIRealidea.build_snapshot(battle)[0]["actors"][0]
    assert_equal(false, actor.key?("predicted_incoming_damage_pct"))
    switch = actor["actions"].find { |a| a["type"] == "switch" }
    assert_equal(false, switch.key?("predicted_incoming_damage_pct"))
    $PORTABLE_AI_CONFIG = { "foe_oracle" => true }
    unregistered = PortableAIRealidea.build_snapshot(oracle_battle)[0]["actors"][0]
    assert_equal(false, unregistered.key?("predicted_incoming_damage_pct"))
  end

  # 0.7.5. The stock model: the same export, produced from the engine's own AI.
  def test_stock_model_predicts_the_top_scoring_move_and_the_withdraw_chance
    $PORTABLE_AI_CONFIG = { "foe_stock_model" => true }
    battle = oracle_battle
    # Both moves score the stub's flat 100; the first is the pick, as pbChooseMoves
    # would take it. Turn 0, nothing poisoned, no Perish: it does not switch.
    actor = PortableAIRealidea.build_snapshot(battle)[0]["actors"][0]
    assert_equal(20.0, actor["predicted_incoming_damage_pct"])
    assert_equal("move", actor["predicted_foe"]["0"]["type"])
    assert_equal("TACKLE", actor["predicted_foe"]["0"]["move_id"])
    assert_equal(0.0, actor["predicted_foe"]["0"]["switch_chance"])
    assert_nil(actor["predicted_foe"]["0"]["switch_slot"])
    # The scorer decides: make the second move the one stock would score higher.
    battle = oracle_battle
    battle.define_singleton_method(:pbGetMoveScore) { |move, _a, _o, _s| move.basedamage }
    actor = PortableAIRealidea.build_snapshot(battle)[0]["actors"][0]
    assert_equal("POUND", actor["predicted_foe"]["0"]["move_id"])
    assert_equal(80.0, actor["predicted_incoming_damage_pct"])
    # Perish count 1: it must switch, to the first slot its list allows.
    battle = oracle_battle
    battle.battlers[0].effects[PBEffects::PerishSong] = 1
    actor = PortableAIRealidea.build_snapshot(battle)[0]["actors"][0]
    assert_equal("switch", actor["predicted_foe"]["0"]["type"])
    assert_equal(0, actor["predicted_foe"]["0"]["slot"])
    assert_equal(0.0, actor["predicted_incoming_damage_pct"])
    # Off: nothing exported, as before. On with the oracle: the oracle wins.
    $PORTABLE_AI_CONFIG = {}
    assert_equal(false, PortableAIRealidea.build_snapshot(oracle_battle)[0]["actors"][0].key?("predicted_foe"))
    $PORTABLE_AI_CONFIG = { "foe_stock_model" => true, "foe_oracle" => true }
    battle = oracle_battle
    battle.choices[0] = [2, 1, nil, -1]
    actor = PortableAIRealidea.build_snapshot(battle)[0]["actors"][0]
    assert_equal("switch", actor["predicted_foe"]["0"]["type"])
    assert_equal(1, actor["predicted_foe"]["0"]["slot"])
  ensure
    $PORTABLE_AI_CONFIG = nil
  end

  # A forced replacement decides between turns, when the registered choices are the
  # ones that have just executed. It must not read them.
  def test_a_replacement_never_reads_a_stale_choice
    $PORTABLE_AI_ENABLED = true
    $PORTABLE_AI_CONFIG = { "foe_oracle" => true }
    battle = replacement_battle
    battle.choices[0] = [1, 0, battle.battlers[0].moves[0], -1]
    actions = PortableAIRealidea.switch_actions(battle, battle.battlers[1], [0], 100, true)
    assert_equal(false, actions.any? { |a| a.key?("predicted_incoming_damage_pct") })
  end
  # ---------------------------------------------------------------------------
  # 0.7.0. PLANNER DISPATCH.

  def dispatch_snap
    { "format" => "single",
      "actors" => [{ "index" => 0, "hp_pct" => 100, "actions" => [
        { "type" => "move", "slot" => 0, "move_id" => "TACKLE", "target" => 0,
          "base_score" => 100, "expected_damage_pct" => 40, "accuracy" => 100,
          "effectiveness" => 1, "damaging" => true }] }],
      "targets" => [{ "index" => 0, "hp_pct" => 100, "status" => 0 }],
      "memory" => {} }
  end

  def dispatch_matrix
    side = lambda do |rows|
      rows.map { |r| { "slot" => r[0], "index" => r[2], "species" => 100 + r[0],
                       "hp_pct" => r[1], "alive" => true, "speed" => 100, "types" => [] } }
    end
    { "version" => 1, "own" => side.call([[0, 100, 0]]), "foe" => side.call([[0, 100, 0]]),
      "cells" => { "0:0" => { "out" => 40, "out_cat" => "physical", "out_move" => "TACKLE",
                              "in" => 40, "in_cat" => "physical", "in_move" => "TACKLE",
                              "faster" => true } } }
  end

  def test_the_search_planner_key_is_overridable_and_off_is_the_rule_engine
    keys = PortableAIRealidea::Harness::CONFIG_OVERRIDE_KEYS
    assert_equal(true, keys.include?(["search_planner", :boolean]))
    snap = dispatch_snap
    snap["matrix"] = dispatch_matrix
    off = PortableAIRealidea.run_planner(snap, PortableAI::Model.config({}), nil)
    # Byte-for-byte the rule planner's answer, which is what makes a run with the key
    # off the control for one with it on.
    assert_equal(PortableAI.plan(snap, PortableAI::Model.config({}), nil), off)
    assert_equal(nil, off["diagnostics"]["planner"])
  end

  def test_the_mcts_keys_are_overridable_and_route_the_same_board
    keys = PortableAIRealidea::Harness::CONFIG_OVERRIDE_KEYS
    # The harness file's parser reads a key's kind, so an unregistered key is a line
    # the run silently ignores -- which is how an arm reproduces its own control.
    assert_equal(true, keys.include?(["search_mcts", :boolean]))
    assert_equal(true, keys.include?(["search_iterations", :float]))
    assert_equal(true, keys.include?(["search_seed", :float]))
    assert_equal(true, keys.include?(["search_foe_prior", :boolean]))
    snap = dispatch_snap
    snap["matrix"] = dispatch_matrix
    # The dispatch: same planner key, same board, the other search underneath.
    tree = PortableAI::Model.config({ "search_planner" => true, "search_mcts" => true,
                                      "search_iterations" => 200 })
    plan = PortableAIRealidea.run_planner(snap, tree, nil)
    assert_equal("mcts", plan["diagnostics"]["planner"])
    assert_equal(200, plan["diagnostics"]["iterations"])
    # And with search_planner off the tree key alone changes nothing: run_planner
    # never asks the search at all.
    off = PortableAI::Model.config({ "search_mcts" => true })
    assert_equal(nil, PortableAIRealidea.run_planner(snap, off, nil)["diagnostics"]["planner"])
  end

  def test_search_trace_carries_the_trees_foe_budget_and_is_absent_off_the_tree
    snap = dispatch_snap
    snap["matrix"] = dispatch_matrix
    tree = PortableAI::Model.config({ "search_planner" => true, "search_mcts" => true,
                                      "search_iterations" => 200 })
    plan = PortableAIRealidea.run_planner(snap, tree, nil)
    trace = PortableAIRealidea.search_trace(plan)
    assert_equal(plan["diagnostics"]["foe_options"], trace["foe_options"])
    assert_equal(plan["diagnostics"]["foe_visits"], trace["foe_visits"])
    assert_equal(200, trace["iterations"])
    # One statistic per foe option, and the budget is what was actually spent.
    assert_equal(trace["foe_options"].length, trace["foe_visits"].length)
    assert_equal(true, trace["foe_visits"].inject(0) { |sum, v| sum + v } > 0)
    # The maximin publishes no foe_visits, so the key simply is not there -- which is
    # what keeps a non-tree trace the same shape it was before this diagnostic.
    maximin = PortableAI::Model.config({ "search_planner" => true })
    assert_equal(nil, PortableAIRealidea.search_trace(
      PortableAIRealidea.run_planner(snap, maximin, nil)))
    assert_equal(nil, PortableAIRealidea.search_trace({}))
  end

  def test_the_search_planner_answers_when_on_and_defers_when_it_cannot
    on = PortableAI::Model.config({ "search_planner" => true })
    snap = dispatch_snap
    snap["matrix"] = dispatch_matrix
    assert_equal("search", PortableAIRealidea.run_planner(snap, on, nil)["diagnostics"]["planner"])
    # No matrix -- Reborn's case, and every Realidea run with party_matrix off -- so
    # the rule engine answers even with the key set.
    assert_equal(nil, PortableAIRealidea.run_planner(dispatch_snap, on, nil)["diagnostics"]["planner"])
  end

  # ---- 0.8.0 Foul Play bridge ---------------------------------------------------

  # A private working directory for the file handoff: the bridge addresses Data/
  # relative to the process, as the game does.
  def foul_play_scratch
    require "tmpdir"
    dir = File.join(Dir.tmpdir, "portable_ai_foul_play_test")
    Dir.mkdir(dir) if !File.exist?(dir)
    dir
  end

  def foul_play_battle
    PBSpecies.const_set(:BULBASAUR, 1) if !PBSpecies.const_defined?(:BULBASAUR)
    PBSpecies.const_set(:IVYSAUR, 2) if !PBSpecies.const_defined?(:IVYSAUR)
    PBSpecies.const_set(:VENUSAUR, 3) if !PBSpecies.const_defined?(:VENUSAUR)
    PortableAIRealidea.instance_variable_set(:@species_keys, nil)
    # The rig declares only the effects earlier tests read; these are the game's indices.
    PBEffects.const_set(:Confusion, 8) if !PBEffects.const_defined?(:Confusion)
    PBEffects.const_set(:Substitute, 91) if !PBEffects.const_defined?(:Substitute)
    battle = contract_battle
    actor = battle.battlers[1]
    actor.moves = [StubMove.new(:id => PBMoves::TACKLE, :basedamage => 40),
                   StubMove.new(:id => PBMoves::TOXIC, :basedamage => 0, :category => 2)]
    actor.stages[PBStats::ATTACK] = 2
    actor.effects[PBEffects::Substitute] = 25
    actor.effects[PBEffects::Confusion] = 3
    battle.sides[1].effects[PBEffects::Spikes] = 2
    battle.sides[1].effects[PBEffects::StealthRock] = true
    battle
  end

  def test_foul_play_state_carries_both_sides_in_poke_engine_terms
    battle = foul_play_battle
    snapshot, _skill = PortableAIRealidea.build_snapshot(battle)
    state = PortableAIRealidea::FoulPlay.state_for(battle, 1, snapshot)
    own = state["side_one"]
    foe = state["side_two"]
    assert_equal(0, own["active"])
    assert_equal(2, own["pokemon"].length, "the whole own party travels")
    assert_equal(1, foe["pokemon"].length)
    assert_equal("BULBASAUR", own["pokemon"][0]["species"])
    assert_equal("IVYSAUR", foe["pokemon"][0]["species"])
    assert_equal(["TACKLE", "TOXIC"], own["pokemon"][0]["moves"].map { |m| m["id"] })
    assert_equal(2, own["boosts"]["attack"])
    assert_equal(0, foe["boosts"]["attack"])
    assert_equal(2, own["conditions"]["spikes"])
    assert_equal(1, own["conditions"]["stealth_rock"], "a boolean hazard becomes a layer count")
    assert_equal(0, foe["conditions"]["stealth_rock"])
    assert_equal(25, own["substitute_health"])
    assert(own["volatiles"].include?("SUBSTITUTE"))
    assert(own["volatiles"].include?("CONFUSION"))
    assert(!own["volatiles"].include?("LEECHSEED"), "-1 is the engine's 'off' for Leech Seed")
    assert_equal(3, own["durations"]["confusion"])
    assert_equal("none", own["pokemon"][0]["status"])
    assert_equal("none", state["weather"])
    assert_equal(["none", 0], state["terrain"])
    assert_equal(1, state["actor"])
  end

  def test_foul_play_declines_without_a_foe_on_the_field
    battle = foul_play_battle
    battle.battlers[0].hp = 0
    snapshot = { "actors" => [{ "index" => 1, "actions" => [{ "type" => "move", "slot" => 0 }] }] }
    assert_nil(PortableAIRealidea::FoulPlay.state_for(battle, 1, snapshot))
  end

  def test_foul_play_reply_maps_onto_the_snapshot_actions
    battle = foul_play_battle
    snapshot, _skill = PortableAIRealidea.build_snapshot(battle)
    actor = snapshot["actors"][0]
    reply = PortableAIRealidea::FoulPlay.parse_reply(
      "type=switch\nslot=1\nvisits=900\nscore=0.61\niterations=5000\n" +
      "own=move:0:100,move:1:0,switch:1:900\nfoe=move:0:700,switch:1:300\n")
    assert_equal([["move:0", 100], ["move:1", 0], ["switch:1", 900]], reply["own"])
    action = PortableAIRealidea::FoulPlay.action_for(battle, 1, actor, reply)
    assert_equal("switch", action["type"])
    assert_equal(1, action["slot"])
    assert_equal(900, action["search_visits"])
    assert_equal(["foul_play_visits", 900], action["reasons"][0])
    ranked = PortableAIRealidea::FoulPlay.rankings(actor, reply)
    assert_equal("switch", ranked[0]["type"], "most visited first")
    assert_equal(100, ranked[1]["search_visits"])
    failed = PortableAIRealidea::FoulPlay.parse_reply("type=error\nmessage=PanicException: Taunt duration\n")
    assert_equal("error", failed["type"])
    assert_equal("PanicException: Taunt duration", failed["message"])
    absent = PortableAIRealidea::FoulPlay.parse_reply("type=move\nslot=7\n")
    assert_nil(PortableAIRealidea::FoulPlay.action_for(battle, 1, actor, absent),
               "a slot the actor cannot play is not an action")
  end

  def test_foul_play_silent_sidecar_falls_through_to_the_rules
    battle = foul_play_battle
    $PORTABLE_AI_CONFIG = { "foul_play" => true, "party_matrix" => true }
    PortableAIRealidea::FoulPlay.timeout = 0.02
    Dir.chdir(foul_play_scratch) do
      Dir.mkdir("Data") if !File.exist?("Data")
      File.delete(PortableAIRealidea::FoulPlay::LOG_FILE) if File.exist?(PortableAIRealidea::FoulPlay::LOG_FILE)
      plan = PortableAIRealidea.plan_for(battle)
      assert_equal(1, plan["actions"].length)
      assert_not_equal("foul_play", (plan["diagnostics"] || {})["planner"])
      assert(File.exist?(PortableAIRealidea::FoulPlay::LOG_FILE), "the fallback is logged")
      assert_match(/sidecar silent/, File.read(PortableAIRealidea::FoulPlay::LOG_FILE))
      assert(!File.exist?(PortableAIRealidea::FoulPlay::STATE_FILE), "a stale state is not left for a later sidecar")
    end
  ensure
    PortableAIRealidea::FoulPlay.timeout = 60.0
  end

  def test_foul_play_reads_a_reply_and_plans_with_it
    battle = foul_play_battle
    $PORTABLE_AI_CONFIG = { "foul_play" => true, "party_matrix" => true, "foul_play_iterations" => 1234.0 }
    PortableAIRealidea::FoulPlay.timeout = 5.0
    Dir.chdir(foul_play_scratch) do
      Dir.mkdir("Data") if !File.exist?("Data")
      state_file = File.expand_path(PortableAIRealidea::FoulPlay::STATE_FILE)
      reply_file = File.expand_path(PortableAIRealidea::FoulPlay::REPLY_FILE)
      # A stand-in sidecar: answer only once the state has been written, the way the
      # real one does, so a reply left over from an earlier turn can never be taken.
      written = nil
      sidecar = Thread.new do
        sleep 0.002 while !File.exist?(state_file)
        written = File.read(state_file)
        File.open(reply_file + ".tmp", "wb") do |file|
          file.write("type=move\nslot=1\nvisits=800\nscore=0.55\niterations=1234\nown=move:0:400,move:1:800\nfoe=move:0:1234\n")
        end
        File.rename(reply_file + ".tmp", reply_file)
      end
      plan = PortableAIRealidea.plan_for(battle)
      sidecar.join
      assert_equal("foul_play", plan["diagnostics"]["planner"])
      assert_equal("move", plan["actions"][0]["type"])
      assert_equal(1, plan["actions"][0]["slot"])
      assert_equal(1234, plan["diagnostics"]["iterations"])
      assert_equal([1234], plan["diagnostics"]["foe_visits"])
      assert(!File.exist?(PortableAIRealidea::FoulPlay::REPLY_FILE), "a reply is consumed once")
      assert_match(/"iterations":1234/, written, "the state names the iteration count the run asked for")
      File.delete(PortableAIRealidea::FoulPlay::STATE_FILE) if File.exist?(PortableAIRealidea::FoulPlay::STATE_FILE)
    end
  ensure
    PortableAIRealidea::FoulPlay.timeout = 60.0
  end

  # ---- 0.8.1 live play ----------------------------------------------------------

  def test_live_overrides_come_from_the_harness_file_only_when_the_marker_is_present
    PortableAIRealidea::Harness.instance_variable_set(:@live_overrides, nil)
    $PORTABLE_AI_CONFIG = nil
    Dir.chdir(foul_play_scratch) do
      Dir.mkdir("Data") if !File.exist?("Data")
      File.open(PortableAIRealidea::Harness::FILE, "wb") do |file|
        file.write("foul_play=true\nfoul_play_iterations=5000\n")
      end
      File.delete(PortableAIRealidea::ENABLE_FILE) if File.exist?(PortableAIRealidea::ENABLE_FILE)
      # No marker: this is how the gauntlet and the probe run, and they must keep
      # taking their config from with_config alone.
      assert_equal({}, PortableAIRealidea.config_overrides)

      File.open(PortableAIRealidea::ENABLE_FILE, "wb") { |file| file.write("on\n") }
      PortableAIRealidea::Harness.instance_variable_set(:@live_overrides, nil)
      live = PortableAIRealidea.config_overrides
      assert_equal(true, live["foul_play"], "a played battle now sees the harness file")
      assert_equal(5000.0, live["foul_play_iterations"])
      assert_equal(true, PortableAIRealidea.config_for(0)["foul_play"],
                   "and it survives the skill-derived config it merges into")

      # A run that installed its own overrides still wins outright.
      $PORTABLE_AI_CONFIG = { "foul_play" => false }
      assert_equal({ "foul_play" => false }, PortableAIRealidea.config_overrides)
    end
  ensure
    $PORTABLE_AI_CONFIG = nil
    PortableAIRealidea::Harness.instance_variable_set(:@live_overrides, nil)
    Dir.chdir(foul_play_scratch) do
      File.delete(PortableAIRealidea::ENABLE_FILE) if File.exist?(PortableAIRealidea::ENABLE_FILE)
      File.delete(PortableAIRealidea::Harness::FILE) if File.exist?(PortableAIRealidea::Harness::FILE)
    end
  end

  def test_a_silent_sidecar_stops_being_asked_for_the_rest_of_the_battle
    battle = foul_play_battle
    $PORTABLE_AI_CONFIG = { "foul_play" => true, "party_matrix" => true }
    PortableAIRealidea::FoulPlay.timeout = 0.05
    Dir.chdir(foul_play_scratch) do
      Dir.mkdir("Data") if !File.exist?("Data")
      PortableAIRealidea.plan_for(battle)
      assert_equal(true, battle.instance_variable_get(:@portable_ai_foul_play_off))
      File.delete(PortableAIRealidea::FoulPlay::LOG_FILE) if File.exist?(PortableAIRealidea::FoulPlay::LOG_FILE)
      # A later turn of the SAME battle: a new cache signature, so the planner really
      # runs again -- and must not pay the timeout a second time.
      battle.turncount += 1
      started = Time.now
      plan = PortableAIRealidea.plan_for(battle)
      assert(Time.now - started < 0.05, "the second turn does not wait on the sidecar again")
      assert_not_equal("foul_play", (plan["diagnostics"] || {})["planner"])
      assert(!File.exist?(PortableAIRealidea::FoulPlay::LOG_FILE), "and nothing more is logged")
      # A fresh battle asks again: the flag is battle state, not a process latch.
      assert_nil(foul_play_battle.instance_variable_get(:@portable_ai_foul_play_off))
    end
  ensure
    PortableAIRealidea::FoulPlay.timeout = 60.0
    $PORTABLE_AI_CONFIG = nil
  end

  def test_foul_play_json_is_plain
    json = PortableAIRealidea::FoulPlay.json({ "a" => [1, 2.5, nil, true, "x\"y"], "b" => { "c" => :d } })
    assert_equal('{"a":[1,2.5,null,true,"x\"y"],"b":{"c":"d"}}', json)
  end

end
