@echo off
REM Start the Foul Play sidecar for live play against the Realidea bot.
REM
REM The game is a Windows process; the search engine (pmariglia's poke_engine) is a
REM Linux wheel in a WSL venv. They never talk directly -- the adapter writes
REM Data\ai_foulplay_state.json and the sidecar answers Data\ai_foulplay_reply.txt,
REM so crossing the WSL boundary costs nothing but the file. That is the same
REM arrangement the 0.8.0 measurement ran on (540 battles, ~10 ms a decision).
REM
REM   foul_play_sidecar.bat                      the campaign copy, gen 6 wheel
REM   foul_play_sidecar.bat "C:\path\to\game"    another copy
REM   foul_play_sidecar.bat "" gen5              the gen 5 wheel
REM
REM Start this BEFORE Game.exe: the first decision waits 3 s for a reply and then
REM hands the battle to the rule engine. Close the window to stop it.
setlocal

REM The venv's python symlinks into one distro's home, so another distro cannot run
REM it -- it fails with a bare "No such file or directory". build_poke_engine.sh
REM records the distro it built in; without that file we use the default distro,
REM which is the right guess on a machine with one.
set "DISTRO="
set "DFILE=%~dp0..\generated\foul_play\distro.txt"
if exist "%DFILE%" for /f "usebackq delims=" %%i in ("%DFILE%") do set "DISTRO=%%i"
if defined DISTRO (set "D=-d %DISTRO%") else (set "D=")

set "GAME=%~1"
if "%GAME%"=="" set "GAME=%~dp0..\..\Realidea V4.1"
for %%i in ("%GAME%") do set "GAME=%%~fi"
set "GEN=%~2"
if "%GEN%"=="" set "GEN=gen6"

if not exist "%GAME%\Data" (
  echo ERROR: no Data folder in "%GAME%".
  echo Pass the game directory as the first argument.
  goto :done
)

for /f "usebackq delims=" %%i in (`wsl.exe %D% -e wslpath -a -u "%~dp0."`) do set "TOOLS=%%i"
for /f "usebackq delims=" %%i in (`wsl.exe %D% -e wslpath -a -u "%GAME%"`) do set "GAMEDIR=%%i"
set "PY=%TOOLS%/../generated/foul_play/venv-%GEN%/bin/python"

REM Build the engine when it is missing or older than this sidecar, rather than
REM telling the user to. The wheel is git-ignored and built once, so a pull that
REM touches patches/poke_engine_permanent_fields.patch leaves a venv that imports
REM perfectly and rejects every state -- the failure that cost three days of play.
REM
REM Staleness is not guessed from a stamp: --check-engine runs the real constructor
REM with the real fields, and answers 3 for "out of date" specifically, so anything
REM else (a broken import, a missing id list) is still reported rather than silently
REM "fixed" by a rebuild that cannot fix it.
set "BUILDING=%GAME%\Data\ai_foulplay_building.txt"
set "NEEDBUILD="
wsl.exe %D% -e test -x "%PY%"
if errorlevel 1 set "NEEDBUILD=missing"
if not defined NEEDBUILD (
  wsl.exe %D% -e "%PY%" "%TOOLS%/foul_play_sidecar.py" --check-engine
  if errorlevel 3 set "NEEDBUILD=out of date"
)

if defined NEEDBUILD (
  echo The %GEN% search engine is %NEEDBUILD%. Building it now -- this takes about a
  echo minute, and only happens when the engine changes.
  echo.
  REM A breadcrumb the game launcher watches: it stops counting down its wait while
  REM this exists, so a one-time build does not look like a sidecar that failed.
  >"%BUILDING%" echo building
  wsl.exe %D% -e bash "%TOOLS%/build_poke_engine.sh" "%TOOLS%/../generated/foul_play" %GEN%
  set "BUILDFAILED="
  if errorlevel 1 set "BUILDFAILED=1"
  del "%BUILDING%" >nul 2>&1
  if defined BUILDFAILED (
    echo.
    echo ERROR: could not build the %GEN% engine. It needs cargo, uv and python3 in
    echo WSL. Build it by hand from the study root to see the full error:
    echo     tools/build_poke_engine.sh generated/foul_play %GEN%
    goto :done
  )
  echo.
  echo Engine built.
)

REM Two sidecars on the SAME game answer the same file and their replies cross,
REM which corrupts a run silently rather than loudly. Scoped to this game dir, so a
REM gauntlet worker's sidecar is left alone. Closing the window does not always
REM reach the Linux process, so clear a leftover rather than dead-ending on it.
REM The [c] keeps the pattern from matching the pgrep/pkill command itself.
set "PATTERN=foul_play_side[c]ar.py --game %GAMEDIR%"
wsl.exe %D% -e pgrep -f "%PATTERN%" >nul 2>&1
if not errorlevel 1 (
  echo Stopping a sidecar already serving this game...
  wsl.exe %D% -e pkill -f "%PATTERN%"
  wsl.exe %D% -e sleep 1
)

echo Game : %GAME%
echo Wheel: %GEN%
echo.
echo Leave this window open, then start Game.exe. Closing it stops the sidecar and
echo the enemy trainer falls back to the rule engine.
echo.
wsl.exe %D% -e "%PY%" "%TOOLS%/foul_play_sidecar.py" --game "%GAMEDIR%"

:done
echo.
pause
