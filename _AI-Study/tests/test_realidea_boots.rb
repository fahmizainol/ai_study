require 'minitest/autorun'
require 'zlib'

module PBEffects
  Spikes=1; StealthRock=2; ToxicSpikes=3; StickyWeb=4; Type3=5; Embargo=6; MagicRoom=7
end
module PBStats
  SPEED=1
end
module PBTypes
  ROCK=1
  def self.getCombinedEffectiveness(*args); 8; end
end
module PBDebug
  def self.log(*args); end
end

class BootsPokemon
  attr_accessor :boots, :poison_type, :airborne, :damage, :poisoned, :speed_drop, :klutz
  attr_reader :effects
  def initialize(boots)
    @boots=boots; @item=boots ? :HEAVYDUTYBOOTS : :NONE
    @damage=0; @effects={1=>3,2=>true,3=>2,4=>true,5=>0,6=>0,7=>0}; @battle=self
  end
  def pbOwnSide; self; end
  def field; self; end
  def isConst?(item,mod,sym); item==sym; end
  def hasWorkingAbility(ability,*args); ability==:KLUTZ && @klutz; end
  def isAirborne?(*args); @airborne; end
  def isFainted?; false; end
  def totalhp; 240; end
  def pbReduceHP(n); @damage+=n; end
  def pbThis; 'Test Pokemon'; end
  def type1; 0; end
  def type2; 0; end
  def pbHasType?(type); @poison_type && type==:POISON; end
  def pbCanPoisonSpikes?(*args); true; end
  def pbPoison(*args); @poisoned=true; end
  def pbCanReduceStatStage?(*args); true; end
  def pbReduceStat(*args); @speed_drop=true; end
end

class BootsHazardHarness
  def initialize; @scene=self; end
  def pbDamageAnimation(*args); end
  def pbDisplayPaused(*args); end
  def _INTL(text,*args); text; end
  def getConst(mod, sym); mod.const_get(sym); end
end

bundle=ARGV.shift || abort('Supply installed Data/Scripts.rxdata')
entry=Marshal.load(File.binread(bundle)).find {|e| e[1]=='PokeBattle_Battle'}
entries=Marshal.load(File.binread(bundle))
battler=Zlib.inflate(entries.find {|e| e[1]=='PokeBattle_Battler'}[2]).gsub("\r\n", "\n")
item_method=battler[/  def hasWorkingItem\(.*?\n  end/m]
raise 'Item suppression method missing' unless item_method
module PBItems; end
BootsPokemon.class_eval(item_method)
source=Zlib.inflate(entry[2]).gsub("\r\n", "\n")
start=source.index('      if pkmn.pbOwnSide.effects[PBEffects::Spikes]>0')
finish=source.index("    end\n    pkmn.pbAbilityCureCheck", start)
raise 'Hazard block missing' unless start && finish
block=source[start...finish]
BootsHazardHarness.class_eval(("# encoding: ISO-8859-1\ndef apply(pkmn)\n moldbreaker=false\n".b+block+"\nend\n").force_encoding('ISO-8859-1'))

class TestRealideaBoots < Minitest::Test
  def apply(p); BootsHazardHarness.new.apply(p); p; end
  def test_boots_block_all_four_hazards_without_removing_them
    p=apply(BootsPokemon.new(true))
    assert_equal 0,p.damage
    refute p.poisoned
    refute p.speed_drop
    assert_equal({1=>3,2=>true,3=>2,4=>true,5=>0,6=>0,7=>0},p.effects)
  end
  def test_absent_or_suppressed_boots_allow_hazards
    p=apply(BootsPokemon.new(false))
    assert_equal 90,p.damage
    assert p.poisoned
    assert p.speed_drop
  end
  def test_real_item_suppression_for_embargo_magic_room_and_klutz
    [:embargo, :magic_room, :klutz].each do |suppression|
      p=BootsPokemon.new(true)
      p.effects[PBEffects::Embargo]=1 if suppression==:embargo
      p.effects[PBEffects::MagicRoom]=1 if suppression==:magic_room
      p.klutz=true if suppression==:klutz
      apply(p)
      assert_equal 90,p.damage,suppression.to_s
      assert p.poisoned
      assert p.speed_drop
    end
  end
  def test_poison_type_still_absorbs_toxic_spikes_with_boots
    p=BootsPokemon.new(true); p.poison_type=true; apply(p)
    assert_equal 0,p.effects[PBEffects::ToxicSpikes]
    assert_equal 0,p.damage
    refute p.poisoned
  end
  def test_airborne_pokemon_only_take_stealth_rock_without_boots
    p=BootsPokemon.new(false); p.airborne=true; apply(p)
    assert_equal 30,p.damage
    refute p.poisoned
    refute p.speed_drop
    assert_equal 2,p.effects[PBEffects::ToxicSpikes]
  end
end
