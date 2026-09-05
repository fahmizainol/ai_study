#!/usr/bin/env bash
# Build private Reborn game directories so gauntlet runs can go in parallel.
#
# The gauntlet reads its trigger (Data/ai_harness.txt) and writes its results entirely
# under the game's own Data/, at fixed paths. That makes two concurrent runs in one
# directory impossible -- and one directory each entirely safe, with no code change.
#
# Audio (806 MB) and Graphics (63 MB) are never read by the headless harness but are
# junctioned rather than skipped, so a worker is a faithful copy for ~118 MB of real
# disk. The ~1 GB of battle-music packs and zips beside them is not copied at all.
# Junctions, not WSL symlinks: Game.exe is a Windows process and will not follow the
# latter.
#
# Game.exe costs ~250 MB and ~0.7 of a core, on the WINDOWS side -- WSL only
# orchestrates. The ceiling is Windows free RAM, so check it before raising N.
#
# Usage:  tools/setup_gauntlet_workers.sh [N]        (default 4)
# Then:   tools/run_gauntlet_parallel.sh OUT_PREFIX CONFIG_FILE ROSTER...
#
# DESTRUCTIVE and idempotent: each worker directory is deleted and rebuilt. Never run
# it while a gauntlet is in flight.

set -e
SRC="/mnt/c/Users/kny/Documents/Games/Norm/Reborn Yang/Reborn Yang"
ROOT="/mnt/c/Users/kny/Documents/Games/Norm/.gauntlet-workers"
N=${1:-4}
# Everything the headless harness reads, minus the two big read-only trees (junctioned
# below) and the ~1 GB of music packs and zips it never opens.
COPY=(Data Scripts PBS Fonts Mods Game.exe Game.ini Game.rxproj mkxp.json intl.dat version)
mkdir -p "$ROOT"
for i in $(seq 1 "$N"); do
  W="$ROOT/w$i"
  rm -rf "$W"; mkdir -p "$W"
  for item in "${COPY[@]}"; do
    [ -e "$SRC/$item" ] && cp -r "$SRC/$item" "$W/"
  done
  cp "$SRC"/*.dll "$W/" 2>/dev/null || true
  for link in Audio Graphics; do
    cmd.exe /c mklink /J "$(wslpath -w "$W/$link")" "$(wslpath -w "$SRC/$link")" >/dev/null 2>&1
  done
  echo "w$i: $(du -sm "$W" 2>/dev/null | cut -f1) MB real, junctions: $(ls -d "$W"/Audio "$W"/Graphics 2>/dev/null | wc -l)/2"
done
