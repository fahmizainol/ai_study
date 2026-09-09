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

echo Starting the Foul Play sidecar...
start "Foul Play sidecar" cmd /c ""%STUDY%\tools\foul_play_sidecar.bat" "%~dp0.""

REM poke_engine takes a moment to import. The game would wait for it anyway -- its
REM first decision blocks for 60 s before giving up -- but starting cold looks like
REM a hang, so pause here where there is something to read.
wsl.exe %D% -e sleep 5

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
