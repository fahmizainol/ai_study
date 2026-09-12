#!/usr/bin/env bash
# Build pmariglia's poke-engine Python package for gen 6 into a local venv, for
# tools/foul_play_sidecar.py. Pinned to the commit the 0.8.0 bridge was measured with.
#
#   tools/build_poke_engine.sh [target-dir] [gen]   default: _AI-Study/generated/foul_play, gen6
#
# Produces <target>/venv-<gen> (with poke_engine importable) and <target>/poke-engine (the
# source clone). gen5 for the gen 5 rosters (Realidea's PBS carries gen 5 numbers and the
# 0.8.0 addendum measured the damage agreement at 93-94% within 3% on it), gen6 for the
# gen 6 roster (megas, Fairy). Needs cargo, uv and python3. Regenerate generated/poke_engine_ids_gen6.json
# from the same clone with `tools/foul_play_sidecar.py --extract-ids <target>/poke-engine`.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$HERE/generated/foul_play}"
GEN="${2:-gen6}"
COMMIT=f4e224c75bf7af885c85c1dcba982b4143ebf582
PERMANENT_FIELDS_PATCH="$HERE/patches/poke_engine_permanent_fields.patch"
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"
if [ ! -d "$TARGET/poke-engine/.git" ]; then
  git clone --quiet https://github.com/pmariglia/poke-engine "$TARGET/poke-engine"
fi
git -C "$TARGET/poke-engine" checkout --quiet "$COMMIT"
if git -C "$TARGET/poke-engine" apply --reverse --check "$PERMANENT_FIELDS_PATCH" 2>/dev/null; then
  echo "poke-engine permanent-field forecast patch already applied"
else
  git -C "$TARGET/poke-engine" apply --check "$PERMANENT_FIELDS_PATCH"
  git -C "$TARGET/poke-engine" apply "$PERMANENT_FIELDS_PATCH"
  echo "applied poke-engine permanent-field forecast patch"
fi
[ -d "$TARGET/venv-$GEN" ] || uv venv --quiet "$TARGET/venv-$GEN"
# shellcheck disable=SC1091
. "$TARGET/venv-$GEN/bin/activate"
uv pip install --quiet maturin
( cd "$TARGET/poke-engine/poke-engine-py" && \
  maturin build --release --no-default-features --features "poke-engine/$GEN" -o "$TARGET/wheels-$GEN" )
uv pip install --quiet --reinstall "$TARGET"/wheels-"$GEN"/poke_engine-*.whl
python -c "import poke_engine; print('poke_engine $GEN ready in $TARGET/venv-$GEN')"
# Record which distro this venv belongs to: its python symlinks into that distro's
# home, so another distro cannot run it. tools/foul_play_sidecar.bat reads this to
# pick the right -d; without it the .bat would have to hardcode a machine's distro.
[ -n "${WSL_DISTRO_NAME:-}" ] && printf '%s\n' "$WSL_DISTRO_NAME" > "$TARGET/distro.txt"
