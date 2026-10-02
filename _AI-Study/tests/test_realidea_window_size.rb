require "test/unit"
require "tmpdir"

# --- engine stubs --------------------------------------------------------------
def _INTL(text, *args)
  text
end

class EnumOption
  attr_reader :name, :values, :get_proc, :set_proc
  def initialize(name, values, get_proc, set_proc)
    @name, @values, @get_proc, @set_proc = name, values, get_proc, set_proc
  end
end

class PokemonOptionScene
  def pbAddOnOptions(options)
    options
  end
end

module Graphics
  class << self
    attr_accessor :fullscreen, :scale, :centered
    def center; @centered = true; end
  end
end

# Loading the section runs its boot-time apply, so do it from a scratch dir.
WINDOW_SIZE_SCRATCH = Dir.mktmpdir
Dir.chdir(WINDOW_SIZE_SCRATCH) do
  Dir.mkdir("Data")
  load File.expand_path("../adapters/realidea/Window_Size.rb", __dir__)
end

class RealideaWindowSizeTest < Test::Unit::TestCase
  def setup
    @dir = WINDOW_SIZE_SCRATCH
    Graphics.fullscreen = false
    Graphics.scale = 1.0
    Graphics.centered = false
  end

  def in_scratch(&block)
    Dir.chdir(@dir) do
      File.delete(RealideaWindowSize::FILE) if File.exist?(RealideaWindowSize::FILE)
      block.call
    end
  end

  def test_no_file_means_full
    in_scratch do
      assert_equal(RealideaWindowSize::FULL, RealideaWindowSize.choice)
      RealideaWindowSize.apply(RealideaWindowSize.choice)
      assert_equal(true, Graphics.fullscreen)
    end
  end

  def test_a_windowed_choice_leaves_fullscreen_scales_and_centres
    in_scratch do
      Graphics.fullscreen = true
      RealideaWindowSize.apply(2)
      assert_equal(false, Graphics.fullscreen)
      assert_equal(2.0, Graphics.scale)
      assert(Graphics.centered)
    end
  end

  def test_the_option_saves_and_applies_and_survives_a_reload
    in_scratch do
      option = PokemonOptionScene.new.pbAddOnOptions([]).last
      assert_equal("Window size", option.name)
      assert_equal(["S", "M", "L", "XL", "Full"], option.values)
      option.set_proc.call(1)
      assert_equal("1", File.read(RealideaWindowSize::FILE).strip)
      assert_equal(1.5, Graphics.scale)
      assert_equal(1, option.get_proc.call, "the menu shows the saved choice")
    end
  end

  def test_a_scale_too_big_for_the_screen_shrinks_to_fit
    Object.const_set(:Win32API, Class.new do
      def initialize(*args); end
      def call(index); index == 16 ? 1280 : 695; end  # a 1280x720 screen less one title bar
    end)
    assert_equal(1.68, RealideaWindowSize.fit(2.0), "(695 - 48) / 384, floored to 2 places")
    assert_equal(1.5, RealideaWindowSize.fit(1.5), "a size that fits is left alone")
  ensure
    Object.send(:remove_const, :Win32API) if defined?(Win32API)
  end

  def test_a_garbled_or_out_of_range_file_is_clamped
    in_scratch do
      File.open(RealideaWindowSize::FILE, "wb") { |f| f.write("99\n") }
      assert_equal(RealideaWindowSize::FULL, RealideaWindowSize.choice)
      File.open(RealideaWindowSize::FILE, "wb") { |f| f.write("big\n") }
      assert_equal(RealideaWindowSize::FULL, RealideaWindowSize.choice)
    end
  end

  def test_the_game_s_own_add_on_options_are_kept
    in_scratch do
      options = PokemonOptionScene.new.pbAddOnOptions([:theirs])
      assert_equal(:theirs, options.first)
      assert_equal(2, options.length)
    end
  end
end
