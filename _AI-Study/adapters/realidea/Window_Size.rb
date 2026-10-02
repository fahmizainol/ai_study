# Window_Size — a Reborn-style "Window size" option: S / M / L / XL / Full.
#
# Realidea ships the same option ("Tamaño de ventana", 146_PScreen_Options) commented
# out, and its resizer (029_Sprite_Resizer) drives the window through Win32API calls
# written for the original RGSS player. This game runs on mkxp-z, which scales the
# window itself, so the option here goes straight to mkxp-z's Graphics.fullscreen=,
# Graphics.scale= and Graphics.center (all three probed live in this player,
# 2026-10-02). The game still draws at 512x384; only the window around it changes.
#
# The choice is saved to Data/window_size.txt rather than the save file, so it applies
# at boot, before any save is loaded, the way Reborn re-applies its own. With no file
# the game opens in Full, matching "fullscreen": true in mkxp.json. Alt+Enter still
# toggles fullscreen; it just does not change the saved choice.
#
# The option is appended through PokemonOptionScene#pbAddOnOptions, the hook the
# options scene already calls for exactly this, so no game section is edited.

module RealideaWindowSize
  FILE = "Data/window_size.txt"
  LABELS = ["S", "M", "L", "XL", "Full"]
  # Window scale for each windowed choice: S is the game's own 512x384.
  SCALES = [1.0, 1.5, 2.0, 2.5]
  FULL = LABELS.length - 1

  def self.choice
    value = File.exist?(FILE) ? File.read(FILE).strip : ""
    return FULL if value !~ /\A\d+\z/
    [[value.to_i, 0].max, FULL].min
  rescue
    FULL
  end

  def self.save(value)
    File.open(FILE, "wb") { |file| file.write("#{value}\n") }
  rescue
  end

  def self.apply(value)
    if value == FULL
      Graphics.fullscreen = true if !Graphics.fullscreen
    else
      Graphics.fullscreen = false if Graphics.fullscreen
      Graphics.scale = fit(SCALES[value])
      Graphics.center if Graphics.respond_to?(:center)
    end
  rescue
    # A player without these calls keeps whatever window it opened with.
  end

  # The largest scale that still fits the screen, if the asked one does not. On a
  # 1280x720 screen L (1024x768) put the title bar 55 px above the top edge, so a
  # small screen gets L and XL at the biggest window it can show. SM_CXFULLSCREEN /
  # SM_CYFULLSCREEN (16, 17) are the client area of a maximised window: the screen
  # minus the taskbar and ONE title bar -- this window's frame is 39 px tall, so
  # FRAME_ROOM more is kept back (measured: without it the title bar sat 18 px above
  # the top of a 1280x720 screen).
  FRAME_ROOM = 48

  def self.fit(scale)
    return scale if !defined?(Win32API)
    metrics = Win32API.new("user32", "GetSystemMetrics", "i", "i")
    width = metrics.call(16) - FRAME_ROOM
    height = metrics.call(17) - FRAME_ROOM
    return scale if width <= 0 || height <= 0
    room = [width / 512.0, height / 384.0].min
    return scale if room >= scale || room < 1.0
    (room * 100).floor / 100.0
  rescue
    scale
  end

  def self.option
    EnumOption.new(_INTL("Window size"), LABELS.map { |label| _INTL(label) },
                   proc { RealideaWindowSize.choice },
                   proc { |value|
                     if value != RealideaWindowSize.choice
                       RealideaWindowSize.save(value)
                       RealideaWindowSize.apply(value)
                     end
                   })
  end
end

class PokemonOptionScene
  alias realidea_window_size_add_on_options pbAddOnOptions

  def pbAddOnOptions(options)
    realidea_window_size_add_on_options(options) + [RealideaWindowSize.option]
  end
end

# At boot, before the title screen: the saved size, or Full.
RealideaWindowSize.apply(RealideaWindowSize.choice)
