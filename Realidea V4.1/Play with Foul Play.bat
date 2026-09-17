@echo off
REM Play Realidea against the Foul Play AI. Double-click this.
REM
REM It starts the search sidecar, waits for it, launches the game, and stops the
REM sidecar when you quit. Without the sidecar the enemy trainer silently falls back
REM to the rule engine, so the two are started together on purpose.
REM
REM First run on a new machine needs the search engine built once -- the sidecar
REM window will print the exact command if it is missing. See _AI-Study's
REM PORTABLE-AI-REALIDEA.md, "### 0.8.1".
setlocal

set "STUDY=%~dp0..\_AI-Study"
if not exist "%STUDY%\tools\foul_play_sidecar.bat" (
  echo ERROR: cannot find the study at "%STUDY%".
  echo This launcher expects _AI-Study to sit next to the game folder.
  goto :done
)
if not exist "%~dp0Game.exe" (
  echo ERROR: no Game.exe next to this launcher.
  goto :done
)

REM Turn the AI on. These two are deliberately NOT committed: a marker inside a
REM tracked Data\ would be copied into the gauntlet workers, and a measured run with
REM the marker present makes both arms portable and invalidates the comparison.
if not exist "%~dp0Data\portable_ai.txt" (
  >"%~dp0Data\portable_ai.txt" echo enabled
  echo Enabled the Portable AI ^(created Data\portable_ai.txt^).
)
if not exist "%~dp0Data\ai_harness.txt" (
  >"%~dp0Data\ai_harness.txt" echo foul_play=true
  >>"%~dp0Data\ai_harness.txt" echo foul_play_iterations=5000
  echo Switched the bridge on ^(created Data\ai_harness.txt^).
)

REM Same machine-local distro file the sidecar uses; needed again here to stop it.
set "DISTRO="
set "DFILE=%STUDY%\generated\foul_play\distro.txt"
if exist "%DFILE%" for /f "usebackq delims=" %%i in ("%DFILE%") do set "DISTRO=%%i"
if defined DISTRO (set "D=-d %DISTRO%") else (set "D=")

REM The sidecar publishes this once it is genuinely able to answer -- after the engine
REM build check and the id list, not merely on process start. Waiting for the FILE
REM rather than for a fixed number of seconds is what makes the difference between
REM "the search is running" and "a window opened".
set "MARKER=%~dp0Data\ai_foulplay_ready.txt"
if exist "%MARKER%" del /q "%MARKER%" >nul 2>&1

echo Starting the Foul Play sidecar...
start "Foul Play sidecar" cmd /c ""%STUDY%\tools\foul_play_sidecar.bat" "%~dp0.""

REM poke_engine takes a few seconds to import. Poll rather than sleep a flat 5: a cold
REM machine can take longer, and a sidecar that died on startup (wrong distro, a build
REM that cannot run) should not be waited out at all -- it should be reported.
REM
REM The sidecar builds the engine itself when it is missing or out of date, which takes
REM about a minute. While that is happening it holds ai_foulplay_building.txt, and the
REM countdown below restarts for as long as it exists -- so a first run on a new machine
REM waits as long as the build needs, while a genuinely dead sidecar is still reported in
REM thirty seconds. A goto loop rather than for /l because this one has to reset.
echo Waiting for the search engine...
set "READY="
set /a WAITED=0
:waitloop
if exist "%MARKER%" set "READY=1"
if defined READY goto ready
if exist "%~dp0Data\ai_foulplay_building.txt" set /a WAITED=0
wsl.exe %D% -e sleep 1
set /a WAITED+=1
if %WAITED% lss 30 goto waitloop
:ready

if not defined READY (
  echo.
  echo WARNING: the sidecar did not come up within 30 seconds.
  echo Check the "Foul Play sidecar" window -- it prints the reason, usually a
  echo missing or out-of-date engine build and the exact command to rebuild it.
  echo.
  echo Starting the game anyway. Enemy trainers will use the BACKUP rule AI, and
  echo the game will say so on the first turn of each battle.
  echo.
  pause
)

echo Starting the game...
"%~dp0Game.exe"

echo.
echo Game closed. Stopping the sidecar...
set "GAMEWIN=%~dp0."
for %%i in ("%GAMEWIN%") do set "GAMEWIN=%%~fi"
for /f "usebackq delims=" %%i in (`wsl.exe %D% -e wslpath -a -u "%GAMEWIN%"`) do set "GDIR=%%i"
wsl.exe %D% -e pkill -f "foul_play_side[c]ar.py --game %GDIR%" >nul 2>&1

:done
echo.
pause
