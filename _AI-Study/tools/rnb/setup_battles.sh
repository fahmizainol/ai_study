#!/usr/bin/env bash
# Build everything the Run & Bun vs Smogon battles need, under $RNB_WORK
# (default _AI-Study/generated/rnb_work, untracked):
#
#   foul-play/   pmariglia/foul-play at FOUL_PLAY_COMMIT + foul_play_rnb.patch, with a venv
#                holding poke-engine 0.0.48 built for gen 9
#   showdown/    pokemon-showdown 0.11.11 from npm, with the gen9nationaldexrnb format and
#                per-IP throttling off (every bot connects from 127.0.0.1)
#
# Needs git, node/npm, cargo and uv. Then:
#   tools/rnb/setup_battles.sh
#   tools/rnb/start_server.sh &            # local Showdown on :8123
#   python3 tools/rnb/run_battles.py 3 2   # 3 battles at a time, 2 rounds
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
STUDY="$(cd "$HERE/../.." && pwd)"
WORK="${RNB_WORK:-$STUDY/generated/rnb_work}"
mkdir -p "$WORK"
for d in "$HOME/.cargo/bin" "$HOME/.local/bin"; do case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac; done

# --- Foul Play
if [ ! -d "$WORK/foul-play" ]; then
  git clone -q https://github.com/pmariglia/foul-play.git "$WORK/foul-play"
  git -C "$WORK/foul-play" checkout -q "$(cat "$HERE/FOUL_PLAY_COMMIT")"
  git -C "$WORK/foul-play" apply "$HERE/foul_play_rnb.patch"
fi
if [ ! -x "$WORK/foul-play/.venv/bin/python" ]; then
  (cd "$WORK/foul-play" && uv venv -q .venv -p 3.12 \
    && uv pip install -q -p .venv requests==2.33.0 websockets==14.1 python-dateutil==2.8.0 \
    && uv pip install -q -p .venv --no-cache poke-engine==0.0.48 \
         --config-settings="build-args=--features poke-engine/gen9 --no-default-features")
fi

# --- Showdown
PS="$WORK/showdown/node_modules/pokemon-showdown"
if [ ! -d "$PS" ]; then
  mkdir -p "$WORK/showdown"
  (cd "$WORK/showdown" && npm install --silent pokemon-showdown@0.11.11)
fi
cp "$HERE/showdown-custom-formats.js" "$PS/dist/config/custom-formats.js"
# Showdown reverse-resolves every connecting IP; where 127.0.0.1 has no rDNS entry and
# something listens on port 80, its fallback probe calls localhost an open proxy and
# locks every bot (the rename comes back as "‽name" and login never confirms). Declare
# loopback residential so the probe never runs.
mkdir -p "$PS/config/chat-plugins"
grep -qs "^RANGE,127.0.0.0," "$PS/config/hosts.csv" || echo "RANGE,127.0.0.0,127.255.255.255,localhost/res" >> "$PS/config/hosts.csv"
mkdir -p "$PS/config" "$PS/logs/repl" "$PS/logs/chat" "$PS/logs/modlog" "$PS/logs/ladderlogs" "$PS/databases"
if [ ! -f "$PS/config/config.js" ]; then
  cp "$PS/dist/config/config-example.js" "$PS/config/config.js"
  cat >> "$PS/config/config.js" <<'EOF'

// Run & Bun study overrides.
// Guests may rename without an assertion, so bots never touch the public login server.
exports.noguestsecurity = true;
exports.port = 8123;
// Every bot connects from 127.0.0.1. With throttling on, Showdown allows 12 "battles and
// team validations" per IP per 3 minutes and refuses the rest with a popup foul-play
// ignores -- both bots then wait forever. That was the cause of every stalled battle.
exports.nothrottle = true;
exports.noipchecks = true;
EOF
fi
# Keep every battle's full protocol log (faints, damage, switches) under
# logs/<month>/<format>/<day>/*.log.json -- the bots' own logs record no faints.
grep -qs "^exports.logchallenges = true" "$PS/config/config.js" || echo "exports.logchallenges = true;" >> "$PS/config/config.js"
echo "ready: $WORK"
