@echo off
REM Start the Foul Play sidecar for live play against the Realidea bot.
REM
REM The game is a Windows process; the search engine (pmariglia's poke_engine) is a
REM Linux wheel in a WSL venv. They never talk directly -- the adapter writes
REM Data\ai_foulplay_state.json and the sidecar answers Data\ai_foulplay_reply.txt,
REM so crossing the WSL boundary costs nothing but the file. That is the same
REM arrangement the 0.8.0 measurement ran on (540 battles, ~10 ms a decision).
REM
REM   foul_play_sidecar.bat                      the campaign copy, gen 5 wheel
REM   foul_play_sidecar.bat "C:\path\to\game"    another copy
REM   foul_play_sidecar.bat "" gen6              the gen 6 wheel
REM
REM Start this BEFORE Game.exe: the first decision waits 60 s for a reply and then
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
if "%GEN%"=="" set "GEN=gen5"

if not exist "%GAME%\Data" (
  echo ERROR: no Data folder in "%GAME%".
  echo Pass the game directory as the first argument.
  goto :done
)

for /f "usebackq delims=" %%i in (`wsl.exe %D% -e wslpath -a -u "%~dp0."`) do set "TOOLS=%%i"
for /f "usebackq delims=" %%i in (`wsl.exe %D% -e wslpath -a -u "%GAME%"`) do set "GAMEDIR=%%i"
set "PY=%TOOLS%/../generated/foul_play/venv-%GEN%/bin/python"

wsl.exe %D% -e test -x "%PY%"
if errorlevel 1 (
  echo ERROR: no %GEN% venv. Build it once, from the study root:
  echo     tools/build_poke_engine.sh _AI-Study/generated/foul_play %GEN%
  goto :done
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
