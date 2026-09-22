#!/usr/bin/env bash
# Stop run_battles.py and every in-flight battle. Finished results are kept; the battles
# killed here are retried by the next run_battles.py. A script file on purpose: `pkill -f`
# typed at a shell matches that shell's own command line and kills it.
for pid in $(pgrep -f "run_battles.py"); do kill "$pid"; done
for pid in $(pgrep -f "tools/rnb/battle.sh"); do kill "$pid"; done
for pid in $(pgrep -f "^(timeout 1800 )?.venv/bin/python run.py"); do kill "$pid"; done
sleep 2
echo "bots left: $(pgrep -fc '^.venv/bin/python run.py')"
