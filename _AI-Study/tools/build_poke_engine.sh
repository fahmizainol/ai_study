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
mkdir -p "$TARGET"
if [ ! -d "$TARGET/poke-engine/.git" ]; then
  git clone --quiet https://github.com/pmariglia/poke-engine "$TARGET/poke-engine"
fi
git -C "$TARGET/poke-engine" checkout --quiet "$COMMIT"
[ -d "$TARGET/venv-$GEN" ] || uv venv --quiet "$TARGET/venv-$GEN"
# shellcheck disable=SC1091
. "$TARGET/venv-$GEN/bin/activate"
uv pip install --quiet maturin
( cd "$TARGET/poke-engine/poke-engine-py" && \
  maturin build --release --no-default-features --features "poke-engine/$GEN" -o "$TARGET/wheels-$GEN" )
uv pip install --quiet --reinstall "$TARGET"/wheels-"$GEN"/poke_engine-*.whl
python -c "import poke_engine; print('poke_engine $GEN ready in $TARGET/venv-$GEN')"
