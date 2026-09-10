# Optional Realidea debug-mode switch.
#
# Create Data/debug_mode.txt to expose the game's built-in debug menus.  This
# section runs immediately before Main because LukaUtilities temporarily clears
# $DEBUG while the title-screen scripts are loaded.

REALIDEA_DEBUG_MODE_FILE = "Data/debug_mode.txt"

begin
  if File.exist?(REALIDEA_DEBUG_MODE_FILE)
    $DEBUG = true
    $memDebug = true
  end
rescue
  # If the marker cannot be checked, preserve the game's normal startup mode.
end
