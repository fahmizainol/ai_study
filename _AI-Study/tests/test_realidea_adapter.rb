require "test/unit"

root = File.expand_path("..", File.dirname(__FILE__))
require File.join(root, "portable_ai", "model")
require File.join(root, "portable_ai", "effects")
require File.join(root, "portable_ai", "core")

module PBTrainerAI
  def self.mediumSkill; 32; end
  def self.highSkill; 48; end
  def self.bestSkill; 100; end
end

class PokeBattle_Battle
  attr_reader :stock_choice

  def pbChooseMoves(index)
    @stock_choice = index
  end

  def pbDefaultChooseEnemyCommand(index)
    @stock_choice = index
  end

  def pbIsOpposing?(index)
    index.odd?
  end

  def opponent
    Object.new
  end
end

require File.join(root, "adapters", "realidea", "Portable_AI_Adapter")

class PortableAIRealideaAdapterTest < Test::Unit::TestCase
  Owner = Struct.new(:skill, :skillCode)

  def setup
    $PORTABLE_AI_ENABLED = false
  end

  def teardown
    $PORTABLE_AI_ENABLED = false
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
end
