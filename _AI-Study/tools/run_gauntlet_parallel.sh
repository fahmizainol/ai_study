#!/usr/bin/env bash
# Run one gauntlet config across several rosters at once, one Game.exe per roster.
#
# The gauntlet reads its trigger and writes its results entirely under the game's own
# Data/, so giving each worker a private game directory parallelises it with no code
# change. Workers live in .gauntlet-workers/w* (see tools/setup_gauntlet_workers.sh);
# Audio and Graphics are NTFS junctions back to the master, so each costs ~120 MB.
#
# Game.exe is a Windows process: the CPU and RAM come off the Windows side, ~250 MB
# and most of one core each. Four workers is the ceiling this machine's free RAM
# supports comfortably.
#
# Scripts/ is re-synced from the master on every run, so a worker can never silently
# execute a stale Portable_AI.rb after a rebuild.
#
# Usage:
#   tools/run_gauntlet_parallel.sh OUT_PREFIX CONFIG_FILE ROSTER [ROSTER...]
# where CONFIG_FILE holds the Data/ai_harness.txt body WITHOUT a teams= line, e.g.
#   mode=gauntlet
#   schedule=normal_baseline
#   party_size=6
#   arms=normal_reborn,normal_portable
#   trace=true
#   log_decisions=false
# Results land at OUT_PREFIX_<roster>.ndjson.
set -u
NORM="/mnt/c/Users/kny/Documents/Games/Norm"
MASTER="$NORM/Reborn Yang/Reborn Yang"
ROOT="$NORM/.gauntlet-workers"

if [ "$#" -lt 3 ]; then
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
OUT_PREFIX="$1"; CONFIG="$2"; shift 2
ROSTERS=("$@")
[ -f "$CONFIG" ] || { echo "no config file at $CONFIG" >&2; exit 2; }
grep -q '^teams=' "$CONFIG" && { echo "config must not set teams= (rosters are the args)" >&2; exit 2; }

mapfile -t WORKERS < <(ls -d "$ROOT"/w* 2>/dev/null)
[ "${#WORKERS[@]}" -gt 0 ] || { echo "no workers; run tools/setup_gauntlet_workers.sh" >&2; exit 2; }
echo "${#ROSTERS[@]} rosters over ${#WORKERS[@]} workers"

run_one() {  # worker_dir roster
  local w="$1" roster="$2"
  rsync -a --delete "$MASTER/Scripts/" "$w/Scripts/" 2>/dev/null \
    || cp -r "$MASTER/Scripts/." "$w/Scripts/"
  cp "$MASTER/Data/!script_order.csv" "$w/Data/" 2>/dev/null
  rm -f "$w"/Data/ai_*results*.ndjson "$w"/Data/ai_*summary*.txt
  { cat "$CONFIG"; echo "teams=$roster"; } > "$w/Data/ai_harness.txt"
  touch "$w/Data/portable_ai.txt"
  ( cd "$w" && ./Game.exe ) > "$w/run.log" 2>&1
  local produced
  produced=$(ls "$w"/Data/ai_*results*.ndjson 2>/dev/null | head -1)
  if [ -n "$produced" ]; then
    cp "$produced" "${OUT_PREFIX}_${roster}.ndjson"
    echo "ROSTER_DONE $roster -> ${OUT_PREFIX}_${roster}.ndjson ($(grep -c . "$produced") records)"
  else
    echo "ROSTER_FAILED $roster (no results; see $w/run.log)"
  fi
  rm -f "$w/Data/ai_harness.txt" "$w/Data/portable_ai.txt"
}

i=0
for roster in "${ROSTERS[@]}"; do
  # Block until a worker frees up, so at most ${#WORKERS[@]} games run at once.
  while [ "$(jobs -rp | wc -l)" -ge "${#WORKERS[@]}" ]; do wait -n; done
  run_one "${WORKERS[$(( i % ${#WORKERS[@]} ))]}" "$roster" &
  i=$(( i + 1 ))
done
wait
echo "ALL_DONE"
