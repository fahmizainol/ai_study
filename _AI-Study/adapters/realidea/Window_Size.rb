# Window_Size — a Reborn-style "Window size" option: S / M / L / XL / Full / Borderless.
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
# Borderless is a frameless window covering the screen that, unlike Full, is NOT kept
# always on top: mkxp-z's fullscreen is already borderless (the display mode never
# changes) but marks itself topmost, so nothing else can sit above it. mkxp-z has no
# call for a frameless window, so this one takes the frame off through Win32: find
# mkxp-z's own window (class SDL_app, this process), drop the title bar and border,
# and size it to the screen. mkxp-z sees an ordinary resize and letterboxes the game.
#
# The option is appended through PokemonOptionScene#pbAddOnOptions, the hook the
# options scene already calls for exactly this, so no game section is edited.

module RealideaWindowSize
  FILE = "Data/window_size.txt"
  # "Brdls" is Borderless: the long word ran the whole row together on screen.
  LABELS = ["S", "M", "L", "XL", "Full", "Brdls"]
  # Window scale for each windowed choice: S is the game's own 512x384.
  SCALES = [1.0, 1.5, 2.0, 2.5]
  FULL = 4
  BORDERLESS = 5
  # GWL_STYLE bits: the title bar, border and min/max/close buttons, and WS_POPUP.
  FRAME_BITS = 0x00CF0000
  POPUP_BIT = 0x80000000

  def self.choice
    value = File.exist?(FILE) ? File.read(FILE).strip : ""
    return FULL if value !~ /\A\d+\z/
    [[value.to_i, 0].max, BORDERLESS].min
  rescue
    FULL
  end

  def self.save(value)
    File.open(FILE, "wb") { |file| file.write("#{value}\n") }
  rescue
  end

  def self.apply(value)
    if value == BORDERLESS
      Graphics.fullscreen = false if Graphics.fullscreen
      borderless
    elsif value == FULL
      framed
      Graphics.fullscreen = true if !Graphics.fullscreen
    else
      framed
      Graphics.fullscreen = false if Graphics.fullscreen
      Graphics.scale = fit(SCALES[value])
      Graphics.center if Graphics.respond_to?(:center)
    end
  rescue
    # A player without these calls keeps whatever window it opened with.
  end

  # mkxp-z's window. The game's own Win32API.pbFindRgssWindow looks for the stock
  # player's "RGSS Player" class, which this player does not have; and this player's
  # Win32API never copies an out-buffer back (GetWindowThreadProcessId's pid read 0 on
  # every try), so "is this SDL_app window ours" cannot be asked directly. Instead the
  # window is briefly retitled with this process's id -- unique on the desktop -- and
  # looked up by that title, then given its own title back. Found on the 3rd poll live.
  def self.window
    return @window if @window && @window != 0
    return nil if !defined?(Win32API) || !defined?(System)
    me = Win32API.new("kernel32", "GetCurrentProcessId", "", "L").call
    title = System.game_title
    tag = "#{title} ##{me}"
    find = Win32API.new("user32", "FindWindowW", "pp", "L")
    found = 0
    begin
      System.set_window_title(tag)
      50.times do
        found = find.call(wide("SDL_app"), wide(tag))
        break if found != 0
        sleep(0.01)
      end
    ensure
      System.set_window_title(title)
    end
    found != 0 ? (@window = found) : nil
  rescue
    nil
  end

  def self.borderless
    @borderless_frames = BORDERLESS_WATCH
    @borderless_held = 0
    place_borderless
  end

  # Leaving fullscreen happens on mkxp-z's event thread once frames start flowing, and
  # restores the old windowed size when it lands -- after the window has already
  # dropped TOPMOST, and after any wait done here at boot (measured three times: the
  # frame came off and the window stayed 528x423). So Graphics.update re-checks for a
  # while: place the window, read the rect back, place it again until it has held for
  # BORDERLESS_HOLD frames in a row. Nothing here sets TOPMOST: the point is that
  # other windows can go above.
  BORDERLESS_WATCH = 600
  BORDERLESS_HOLD = 30

  def self.watching?
    @borderless_frames && @borderless_frames > 0
  end

  def self.place_borderless
    @borderless_frames -= 1
    hwnd = window
    return (@borderless_frames = 0) if !hwnd
    get_style = Win32API.new("user32", "GetWindowLongW", "Li", "L")
    style = get_style.call(hwnd, -16) & 0xFFFFFFFF
    if (style & FRAME_BITS) != 0
      @framed_style = style
      Win32API.new("user32", "SetWindowLongW", "LiL", "L").call(
        hwnd, -16, ((style & ~FRAME_BITS) | POPUP_BIT) & 0xFFFFFFFF)
    end
    metrics = Win32API.new("user32", "GetSystemMetrics", "i", "i")
    width = metrics.call(0)
    height = metrics.call(1)
    rect = "\0" * 16
    Win32API.new("user32", "GetWindowRect", "Lp", "i").call(hwnd, rect)
    if rect.unpack("l4") == [0, 0, width, height]
      @borderless_held += 1
      @borderless_frames = 0 if @borderless_held >= BORDERLESS_HOLD
    else
      @borderless_held = 0
      # MoveWindow, not SetWindowPos: from this player's Win32API SetWindowPos moved
      # the window and never resized it (600 frames at 529x424 asking for 1280x720),
      # while MoveWindow resized it in the same probe. It also leaves the z-order alone.
      Win32API.new("user32", "MoveWindow", "LiiiiI", "i").call(hwnd, 0, 0, width, height, 1)
    end
  rescue
    @borderless_frames = 0
  end

  # Put the frame back after Borderless, before mkxp-z resizes or goes fullscreen.
  def self.framed
    @borderless_frames = 0
    return if !@framed_style
    hwnd = window
    return if !hwnd
    Win32API.new("user32", "SetWindowLongW", "LiL", "L").call(hwnd, -16, @framed_style)
    # 0x20 SWP_FRAMECHANGED | 0x01 SWP_NOSIZE | 0x02 SWP_NOMOVE | 0x04 SWP_NOZORDER
    Win32API.new("user32", "SetWindowPos", "LLiiiiI", "i").call(hwnd, 0, 0, 0, 0, 0, 0x27)
    @framed_style = nil
  rescue
  end

  # By hand: mkxp-z's Ruby has no String#encode (see FoulPlay.utf16le).
  def self.wide(text)
    (text.unpack("U*") + [0]).pack("v*")
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

module Graphics
  class << self
    alias realidea_window_size_update update

    def update(*args)
      realidea_window_size_update(*args)
      RealideaWindowSize.place_borderless if RealideaWindowSize.watching?
    end
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
