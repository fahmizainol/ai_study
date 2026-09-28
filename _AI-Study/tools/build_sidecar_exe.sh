#!/usr/bin/env bash
# Build tools/foul_play_sidecar.py into a native Windows program the game starts itself.
#
#   tools/build_sidecar_exe.sh [gen]          default gen5; run from Git Bash on Windows
#
# Produces generated/foul_play/win/dist/foul_play_sidecar/ (foul_play_sidecar.exe plus
# its _internal/ folder). Copy that whole folder into the game as <game>/FoulPlay/ and
# the adapter starts it at boot (FoulPlay.launch_sidecar) -- no WSL, no Python, no .bat
# and no console window on the player's machine. It exits on its own when Game.exe does.
#
# Same engine as tools/build_poke_engine.sh -- the pinned commit and the permanent-fields
# patch -- built for win_amd64 instead of Linux. Its own clone under win/, because a
# checkout shared with the WSL build would share cargo's target dir across two platforms.
# Measured 2026-09-28 against the WSL gen5 wheel: 244 replayed states give byte-identical
# damage checks, and a paired gen6uu_a run went 53-3-2 against WSL's 55-3-2 (identical
# stock control), inside the ±3 run-to-run spread of the sampler.
#
# --onedir, not --onefile: a one-file exe unpacks itself to %TEMP% on every start, which
# is seconds of the boot wait and the thing antivirus heuristics flag. --noconsole makes
# it a GUI-subsystem program, so no window appears however it is launched.
#
# Needs cargo (x86_64-pc-windows-msvc), uv and git on the Windows side.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
GEN="${1:-gen5}"
TARGET="$HERE/generated/foul_play/win"
COMMIT=f4e224c75bf7af885c85c1dcba982b4143ebf582
PATCH="$HERE/patches/poke_engine_permanent_fields.patch"
mkdir -p "$TARGET"
if [ ! -d "$TARGET/poke-engine/.git" ]; then
  # autocrlf off: a CRLF checkout does not take the LF patch.
  git -c core.autocrlf=false clone --quiet https://github.com/pmariglia/poke-engine "$TARGET/poke-engine"
fi
git -C "$TARGET/poke-engine" -c core.autocrlf=false checkout --quiet "$COMMIT"
if git -C "$TARGET/poke-engine" apply --reverse --check "$PATCH" 2>/dev/null; then
  echo "poke-engine permanent-field forecast patch already applied"
else
  git -C "$TARGET/poke-engine" apply "$PATCH"
  echo "applied poke-engine permanent-field forecast patch"
fi
VENV="$TARGET/venv-$GEN"
PY="$VENV/Scripts/python.exe"
[ -x "$PY" ] || uv venv --quiet --python 3.12 "$VENV"
uv pip install --quiet --python "$PY" maturin pyinstaller
rm -rf "$TARGET/wheels-$GEN"
( cd "$TARGET/poke-engine/poke-engine-py" && \
  "$VENV/Scripts/maturin.exe" build --release --no-default-features \
    --features "poke-engine/$GEN" -o "$TARGET/wheels-$GEN" )
uv pip install --quiet --python "$PY" --reinstall "$TARGET"/wheels-"$GEN"/poke_engine-*.whl
# The same probe the .bat ran: the real constructor with the real fields.
"$PY" "$HERE/tools/foul_play_sidecar.py" --check-engine
# Windows paths throughout: Git Bash rewrites a bare /c/... argument for a native exe,
# but not one embedded in --add-data's "src;dest" value.
w() { cygpath -w "$1"; }
"$VENV/Scripts/pyinstaller.exe" --noconfirm --clean --log-level WARN \
  --onedir --noconsole --name foul_play_sidecar \
  --hidden-import poke_engine \
  --add-data "$(w "$HERE/generated/poke_engine_ids_gen6.json");generated" \
  --distpath "$(w "$TARGET/dist")" --workpath "$(w "$TARGET/build")" --specpath "$(w "$TARGET")" \
  "$(w "$HERE/tools/foul_play_sidecar.py")"
# The frozen exe must pass the same probe as the script, from inside its bundle.
"$TARGET/dist/foul_play_sidecar/foul_play_sidecar.exe" --check-engine
echo "$GEN sidecar ready: $TARGET/dist/foul_play_sidecar -- copy it into the game as FoulPlay/"
