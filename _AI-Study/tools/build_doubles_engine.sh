#!/usr/bin/env bash
# Rebuild the PR #10 doubles engine with this study's patches, into a venv with the
# poke_engine wheel importable. The scratchpad holding the clone, the venv and the wheel has
# now been wiped three times mid-project (runs 12 and 17), so this exists to make that cost a
# minute instead of an hour. Everything it needs is tracked: the patches are in patches/.
#
#   tools/build_doubles_engine.sh [target-dir] [gen] [--instruments]
#       default target: _AI-Study/generated/doubles_engine       default gen: gen6
#
# Produces <target>/engine (the patched clone) and <target>/venv-<gen>.
#
# --instruments additionally applies patches/poke_engine_doubles_instruments.patch, which is
# inert unless you set one of its environment variables at RUN time:
#
#   PE_DBG_BOOST_RANGE=1   every boost write that leaves +-6          (found Belly Drum, run 16;
#                                                                      Intrepid/Dauntless, run 17)
#   PE_DBG_ITEM=1          every item write, with the body it hits     (found Knock Off, run 15)
#   PE_DBG_CTOR=<Name>     every construction of that instruction,     (named choice_effects.rs:781
#                          tagged with its SOURCE SITE                  and abilities.rs:1531)
#
# The PAIR is the method and it is what three runs converged on: the mutator proves a bad write
# exists and names the VICTIM; only the constructor names the CULPRIT. Reaching for the mutator
# alone is what cost runs 14 and 15 their wrong hypotheses.
#
# Example, the run 17 measurement end to end:
#   tools/build_doubles_engine.sh /tmp/dbl gen6 --instruments
#   . /tmp/dbl/venv-gen6/bin/activate
#   PE_DBG_BOOST_RANGE=1 python3 tools/pe_doubles_play.py --battles 20 --p1 greedy --p2 mcts \
#       --ms 300 --seed 101 --teams gen6doublesou 2>dbg.txt >/dev/null
#   grep -c 'DBG boost OUT OF RANGE' dbg.txt        # 0 since run 17
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$HERE/generated/doubles_engine}"
GEN="${2:-gen6}"
WANT_INSTR="${3:-}"
BRANCH=main-doubles
COMMIT=bf863be                       # PR #10 head; every measurement in SEARCH-BOARDS.md is this
P="$HERE/patches"

mkdir -p "$TARGET"; TARGET="$(cd "$TARGET" && pwd)"
if [ ! -d "$TARGET/engine/.git" ]; then
  git clone --quiet --single-branch --branch "$BRANCH" --depth 6 \
      https://github.com/0neCr1t/engine "$TARGET/engine"
fi
cd "$TARGET/engine"
git checkout --quiet .                       # drop any previous patch application
git rev-parse --short HEAD | grep -q "^$COMMIT" || echo "WARNING: head is not $COMMIT"

for patch in poke_engine_doubles_spread_per_target \
             poke_engine_doubles_debug_slot \
             poke_engine_doubles_choice_labels; do
  git apply "$P/$patch.patch"
  echo "applied $patch"
done
if [ "$WANT_INSTR" = "--instruments" ]; then
  git apply "$P/poke_engine_doubles_instruments.patch"
  echo "applied poke_engine_doubles_instruments (inert unless PE_DBG_* is set)"
fi

[ -d "$TARGET/venv-$GEN" ] || uv venv --quiet "$TARGET/venv-$GEN"
# shellcheck disable=SC1091
. "$TARGET/venv-$GEN/bin/activate"
uv pip install --quiet maturin
( cd "$TARGET/engine/poke-engine-py" && \
  maturin build --release --no-default-features --features "poke-engine/$GEN,doubles" \
      -o "$TARGET/wheels-$GEN" >/dev/null )
uv pip install --quiet --reinstall "$TARGET"/wheels-"$GEN"/poke_engine-*.whl
python -c "import poke_engine; print('poke_engine $GEN doubles ready in $TARGET/venv-$GEN')"
