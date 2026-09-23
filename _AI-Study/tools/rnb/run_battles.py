#!/usr/bin/env python3
"""Play every pairing in generated/rnb/pairs.json through two Foul Play bots.

    python tools/rnb/run_battles.py [WORKERS=2] [ROUNDS=1] [SEARCH_MS=500]

Needs setup_battles.py and a running start_server.py. Run it with WINDOWS Python, not
from WSL: WSL is a slice of the same machine and a full run there crashed it.

RNB_OUT=<dir> runs another experiment's pairs.json (a pairing's opponent is read from
teams/<opp_side>/, default smogon).

Appends one record per attempt to generated/rnb/results.ndjson and is resumable: a tag
(b<pairing>x<round>) with a clean result is skipped, anything else is played again. A
result is NOT clean when either bot's log has a traceback, when no winner was logged, or
when it ended on turn 0 -- a 0-turn "win" is an abandoned room, not a battle.

Search is time-based (SEARCH_MS per decision), so oversubscribing the CPU does not slow a
run down, it silently weakens both bots. Each decision forks two searches per bot, so 4
battles can burst to 16 busy processes; every published number was played at 4 workers
(3 for the first Smogon run), so keep 4 for anything compared with them.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

from paths import FOUL_PLAY, OUT, TEAM_DIR, VENV_PY, WORK, out

WORKERS = int(sys.argv[1]) if len(sys.argv) > 1 else 2
ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 1
SEARCH_MS = sys.argv[3] if len(sys.argv) > 3 else "500"
RESULTS = out("results.ndjson")
START_WAIT = 120        # seconds for turn 1 to appear before the attempt is abandoned
BATTLE_CAP = 1800       # seconds a battle may take before both bots are killed


def sync_teams():
    """foul-play loads teams from its own fp/teams/teams/; the tracked copies live in OUT."""
    for side in os.listdir(os.path.join(OUT, "teams")):
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


def battle(run_tag, rnb_team, opp_team):
    """One Foul Play v Foul Play battle on the local server. Side a plays the Run & Bun
    team and challenges; side b plays the opponent and accepts. Logs go to
    WORK/runs/<run_tag>_{a,b}.log; returns side a's exit code.

    Watchdog: if no turn has started within START_WAIT seconds both bots are killed and
    the battle ends with 0 turns, which play() records as an error and a later run
    retries. (The stalls it was added for were Showdown's per-IP throttle -- see
    setup_battles.py -- but a lost challenge must never again hang a worker.)"""
    os.makedirs(os.path.join(WORK, "runs"), exist_ok=True)
    # gen9nationaldexrnb: the custom format (showdown-custom-formats.js). "nationaldex" in
    # the name is what makes foul-play allow megas in gen 9; set data is mapped to
    # gen9nationaldex by the patch, usage stats come from National Dex Ubers.
    common = [VENV_PY, "run.py", "--websocket-uri", "ws://localhost:8123/showdown/websocket",
              "--pokemon-format", "gen9nationaldexrnb", "--smogon-stats-format",
              "gen9nationaldexubers", "--search-time-ms", SEARCH_MS, "--run-count", "1",
              "--log-level", "INFO"]
    user = re.sub(r"[^a-z0-9]", "", run_tag)
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")   # Windows defaults to cp1252
    la, lb = (os.path.join(WORK, "runs", "%s_%s.log" % (run_tag, s)) for s in "ab")
    with open(lb, "w") as fb, open(la, "w") as fa:
        pb = subprocess.Popen(common + ["--ps-username", "s" + user, "--bot-mode", "accept_challenge",
                                        "--team-name", opp_team], cwd=FOUL_PLAY, env=env, stdout=fb, stderr=fb)
        time.sleep(6)
        pa = subprocess.Popen(common + ["--ps-username", "r" + user, "--bot-mode", "challenge_user",
                                        "--user-to-challenge", "s" + user, "--team-name", "rnb/" + rnb_team],
                              cwd=FOUL_PLAY, env=env, stdout=fa, stderr=fa)
        deadline = time.time() + START_WAIT
        while time.time() < deadline and pa.poll() is None and "Turn: 1" not in open(la, encoding="utf-8", errors="replace").read():
            time.sleep(1)
        if pa.poll() is None and "Turn: 1" not in open(la, encoding="utf-8", errors="replace").read():
            fa.write("WATCHDOG: no battle started within %ds\n" % START_WAIT)
            pa.kill()
            pb.kill()
            return 3
        try:
            rc = pa.wait(timeout=BATTLE_CAP)
        except subprocess.TimeoutExpired:
            pa.kill()
            rc = -9
        try:
            pb.wait(timeout=60)
        except subprocess.TimeoutExpired:
            pb.kill()
        return rc


def play(job):
    tag, p = job
    t0 = time.time()
    run_tag = "%st%d" % (tag, int(t0) % 100000)     # fresh bot usernames on every attempt
    rc = battle(run_tag, p["boss"], p.get("opp_side", "smogon") + "/" + p["opp"])
    logs = [os.path.join(WORK, "runs", "%s_%s.log" % (run_tag, side)) for side in "ab"]
    a, b = (open(f, encoding="utf-8", errors="replace").read() if os.path.exists(f) else "" for f in logs)
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
