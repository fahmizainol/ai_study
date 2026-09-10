# Optional Realidea debug-mode switch.
#
# Create Data/debug_mode.txt to expose the game's built-in debug menus.
#
# Launching with a debug flag cannot work here: Settings hard-codes DEBUG=false
# (000_Settings) and RGSS2Compatibility then does $DEBUG=DEBUG, overwriting
# whatever the executable set.  So the flag has to be re-raised from a script
# section.  It must sit immediately before Main because LukaUtilities has already
# stashed $memDebug = $DEBUG, and Scene_Intro#main (258_TitleScreen) restores
# $DEBUG = $memDebug on the way to the title screen -- both have to be true.

REALIDEA_DEBUG_MODE_FILE = "Data/debug_mode.txt"

begin
  if File.exist?(REALIDEA_DEBUG_MODE_FILE)
    $DEBUG = true
    $memDebug = true
  end
rescue
  # If the marker cannot be checked, preserve the game's normal startup mode.
end
