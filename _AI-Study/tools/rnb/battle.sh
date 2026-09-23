#!/usr/bin/env bash
# One Foul Play vs Foul Play battle on the local server:
#   battle.sh TAG RNB_TEAM OPP_SIDE/OPP_TEAM [search_ms]  -> $RNB_WORK/runs/TAG_{a,b}.log
# Side a plays the Run & Bun team and challenges; side b plays the Smogon team and accepts.
#
# Watchdog: if no turn has started within START_WAIT seconds both bots are killed and the
# battle ends with 0 turns, which run_battles.py records as an error and retries. (The
# stalls it was added for turned out to be Showdown's per-IP throttle -- see setup_battles.sh
# -- but a lost challenge must never again hang a worker for half an hour.)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${RNB_WORK:-$(cd "$HERE/../.." && pwd)/generated/rnb_work}"
TAG=$1; A=$2; B=$3; MS=${4:-500}; START_WAIT=120
mkdir -p "$WORK/runs"
cd "$WORK/foul-play"
P=.venv/bin/python
# gen9nationaldexrnb: the custom format (showdown-custom-formats.js). "nationaldex" in the
# name is what makes foul-play allow megas in gen 9; set data is mapped to gen9nationaldex
# by the patch, usage stats come from National Dex Ubers (legendaries are in both teams).
COMMON=(--websocket-uri ws://localhost:8123/showdown/websocket --pokemon-format gen9nationaldexrnb
        --smogon-stats-format gen9nationaldexubers --search-time-ms "$MS" --run-count 1 --log-level INFO)
UA="r${TAG//[^a-z0-9]/}"; UB="s${TAG//[^a-z0-9]/}"
LA="$WORK/runs/${TAG}_a.log"; LB="$WORK/runs/${TAG}_b.log"
$P run.py "${COMMON[@]}" --ps-username "$UB" --bot-mode accept_challenge --team-name "$B" > "$LB" 2>&1 &
PB=$!
sleep 6
timeout 1800 $P run.py "${COMMON[@]}" --ps-username "$UA" --bot-mode challenge_user --user-to-challenge "$UB" --team-name "rnb/$A" > "$LA" 2>&1 &
PA=$!
for ((i = 0; i < START_WAIT; i++)); do
  grep -q "Turn: 1" "$LA" 2>/dev/null && break
  kill -0 $PA 2>/dev/null || break
  sleep 1
done
if ! grep -q "Turn: 1" "$LA" 2>/dev/null && kill -0 $PA 2>/dev/null; then
  echo "WATCHDOG: no battle started within ${START_WAIT}s" >> "$LA"
  kill $PA $PB 2>/dev/null; pkill -P $PA 2>/dev/null
  wait 2>/dev/null
  exit 3
fi
wait $PA; RC=$?
wait $PB 2>/dev/null
exit $RC
