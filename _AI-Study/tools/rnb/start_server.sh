#!/usr/bin/env bash
# Run the local Showdown server the battles use (port 8123). See setup_battles.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${RNB_WORK:-$(cd "$HERE/../.." && pwd)/generated/rnb_work}"
cd "$WORK/showdown/node_modules/pokemon-showdown"
exec node pokemon-showdown start --skip-build 8123
