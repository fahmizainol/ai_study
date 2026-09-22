#!/usr/bin/env python3
"""Play every pairing in generated/rnb/pairs.json through two Foul Play bots.

    python3 tools/rnb/run_battles.py [WORKERS=2] [ROUNDS=1] [SEARCH_MS=500]

Appends one record per attempt to generated/rnb/results.ndjson and is resumable: a tag
(b<pairing>x<round>) with a clean result is skipped, anything else is played again. A
result is NOT clean when either bot's log has a traceback, when no winner was logged, or
when it ended on turn 0 -- a 0-turn "win" is an abandoned room, not a battle.

Search is time-based (SEARCH_MS per decision), so oversubscribing the CPU does not slow a
run down, it silently weakens both bots. Each battle keeps up to two searches busy in
bursts; on 5 cores 3 workers held load near 2, 4 would still have been safe.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

from paths import HERE, OUT, TEAM_DIR, WORK, out

WORKERS = int(sys.argv[1]) if len(sys.argv) > 1 else 2
ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 1
SEARCH_MS = sys.argv[3] if len(sys.argv) > 3 else "500"
RESULTS = out("results.ndjson")


def sync_teams():
    """foul-play loads teams from its own fp/teams/teams/; the tracked copies live in OUT."""
    for side in ("rnb", "smogon"):
        dst = os.path.join(TEAM_DIR, side)
        shutil.rmtree(dst, ignore_errors=True)
        shutil.copytree(os.path.join(OUT, "teams", side), dst)


def clean_tags():
    done = set()
    if os.path.exists(RESULTS):
        with open(RESULTS) as fh:
            for line in fh:
                r = json.loads(line)
                if not r["error"] and r["turns"] > 0:
                    done.add(r["tag"])
    return done


def play(job):
    tag, p = job
    t0 = time.time()
    run_tag = "%st%d" % (tag, int(t0) % 100000)     # fresh bot usernames on every attempt
    rc = subprocess.run([os.path.join(HERE, "battle.sh"), run_tag, p["boss"], p["opp"],
                         SEARCH_MS]).returncode
    logs = [os.path.join(WORK, "runs", "%s_%s.log" % (run_tag, side)) for side in "ab"]
    a, b = (open(f).read() if os.path.exists(f) else "" for f in logs)
    w = re.search(r"Winner: (\S+)", a) or re.search(r"Winner: (\S+)", b)
    winner = None if not w else ("rnb" if w.group(1).startswith("r") else "smogon")
    turns = max([int(x) for x in re.findall(r"Turn: (\d+)", a)] or [0])
    err = "Traceback" in a or "Traceback" in b or turns == 0 or not w
    rec = dict(tag=tag, **p, winner=winner, turns=turns, secs=round(time.time() - t0), rc=rc,
               error=err)
    with open(RESULTS, "a") as fh:
        fh.write(json.dumps(rec) + "\n")
    print(tag, p["boss"], "vs", p["opp"], "->", winner, turns, "turns", rec["secs"], "s",
          "ERR" if err else "", flush=True)


def main():
    sync_teams()
    with open(out("pairs.json")) as fh:
        pairs = json.load(fh)
    done = clean_tags()
    jobs = [("b%dx%d" % (i, rnd), p) for rnd in range(ROUNDS) for i, p in enumerate(pairs)]
    jobs = [j for j in jobs if j[0] not in done]
    print("%d battles to play" % len(jobs), flush=True)
    with ThreadPoolExecutor(WORKERS) as ex:
        list(ex.map(play, jobs))


if __name__ == "__main__":
    main()
