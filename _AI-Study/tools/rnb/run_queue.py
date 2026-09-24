#!/usr/bin/env python3
"""Play one or more experiments to completion, and resume after a shutdown.

Safe to run again at any time, including after the PC was switched off mid-run: it starts
the local Showdown server if nothing is listening on :8123, then for each experiment
plays every battle without a clean result (run_battles.py skips the clean ones), with a
second pass for anything that errored. A battle cut off by a shutdown has no clean
record, so it is simply played again.

    python tools/rnb/run_queue.py [--rounds N] rnb_vs_gen7_injected [more experiments...]

--rounds fixes the round count for every experiment listed (default: what each has
already been played with, or 2 for a fresh one).

Experiments are folders under generated/. Run with WINDOWS Python (see setup_battles.py).
4 workers: every published number was played at that search depth.
"""
import os
import socket
import subprocess
import sys
import time

from paths import HERE, STUDY, WORK

WORKERS = "4"


def server_up():
    with socket.socket() as s:
        s.settimeout(1)
        return s.connect_ex(("127.0.0.1", 8123)) == 0


def ensure_server():
    if server_up():
        return
    flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    log = open(os.path.join(WORK, "server.log"), "ab")
    subprocess.Popen([sys.executable, os.path.join(HERE, "start_server.py")], stdout=log, stderr=log,
                     creationflags=flags, start_new_session=os.name != "nt")
    for _ in range(90):
        if server_up():
            return
        time.sleep(1)
    sys.exit("Showdown server did not come up on :8123 (see %s)" % os.path.join(WORK, "server.log"))


def rounds_of(exp):
    """The round count the experiment was played with: the highest x<round> tag + 1 in its
    results, or 2 for a fresh one (every run here is 2 rounds, round 3 was added later)."""
    import json
    path = os.path.join(STUDY, "generated", exp, "results.ndjson")
    rs = [0]
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            try:
                rs.append(int(json.loads(line)["tag"].split("x")[1]))
            except (ValueError, KeyError, IndexError):
                continue
    return str(max(max(rs) + 1, 2))


def main():
    args = sys.argv[1:]
    fixed = None
    if "--rounds" in args:
        i = args.index("--rounds")
        fixed = args[i + 1]
        del args[i:i + 2]
    exps = args
    if not exps:
        sys.exit(__doc__)
    ensure_server()
    for exp in exps:
        env = dict(os.environ, RNB_OUT=os.path.join(STUDY, "generated", exp), RNB_WORK=WORK)
        rounds = fixed or rounds_of(exp)
        for attempt in (1, 2):
            print("== %s: pass %d, %s rounds" % (exp, attempt, rounds), flush=True)
            subprocess.run([sys.executable, "-u", os.path.join(HERE, "run_battles.py"), WORKERS, rounds],
                           env=env)
    print("QUEUE DONE", flush=True)


if __name__ == "__main__":
    main()
