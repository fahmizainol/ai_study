#!/usr/bin/env python3
"""Build everything the Run & Bun battles need, under paths.WORK (default
_AI-Study/generated/rnb_work, untracked). Runs the same on Windows and Linux; run the
battles on WINDOWS -- the WSL VM is a slice of the same machine, and a full run there
took the PC down (2026-09-23).

  foul-play/   pmariglia/foul-play at FOUL_PLAY_COMMIT + foul_play_rnb.patch, with a venv
               holding poke-engine 0.0.48 built for gen 9 (needs cargo; on Windows the
               MSVC build tools)
  showdown/    pokemon-showdown 0.11.11 from npm, with the gen9nationaldexrnb format,
               per-IP throttling off and battle logging on

Needs git, node/npm, cargo and Python 3.12. Then:

    python tools/rnb/setup_battles.py
    python tools/rnb/start_server.py           # local Showdown on :8123, leave it running
    python tools/rnb/run_battles.py 4 2        # 4 battles at a time, 2 rounds
"""
import os
import shutil
import subprocess
import sys

from paths import FOUL_PLAY, HERE, SHOWDOWN, VENV_PY, WORK

NPM = "npm.cmd" if os.name == "nt" else "npm"
CONFIG = """
// Run & Bun study overrides.
// Guests may rename without an assertion, so bots never touch the public login server.
exports.noguestsecurity = true;
exports.port = 8123;
// Every bot connects from 127.0.0.1. With throttling on, Showdown allows 12 "battles and
// team validations" per IP per 3 minutes and refuses the rest with a popup foul-play
// ignores -- both bots then wait forever. That was the cause of every stalled battle.
exports.nothrottle = true;
exports.noipchecks = true;
// Keep every battle's full protocol log (faints, damage, switches) under
// logs/<month>/<format>/<day>/*.log.json -- the bots' own logs record no faints.
// config.js hot-reloads, so switching this on reaches a running server.
exports.logchallenges = true;
"""
# Showdown reverse-resolves every connecting IP; where 127.0.0.1 has no rDNS entry and
# something listens on port 80, its fallback probe calls localhost an open proxy and locks
# every bot (the rename comes back as "‽name" and login never confirms). Declare loopback
# residential so the probe never runs.
HOSTS = "RANGE,127.0.0.0,127.255.255.255,localhost/res\n"


def run(*cmd, cwd=None):
    subprocess.run(cmd, cwd=cwd, check=True)


def foul_play():
    if not os.path.isdir(FOUL_PLAY):
        # autocrlf off: a CRLF checkout on Windows would refuse the LF patch
        run("git", "clone", "-q", "-c", "core.autocrlf=false",
            "https://github.com/pmariglia/foul-play.git", FOUL_PLAY)
        with open(os.path.join(HERE, "FOUL_PLAY_COMMIT")) as fh:
            run("git", "-C", FOUL_PLAY, "checkout", "-q", fh.read().strip())
        run("git", "-C", FOUL_PLAY, "apply", os.path.join(HERE, "foul_play_rnb.patch"))
    if not os.path.exists(VENV_PY):
        run(sys.executable, "-m", "venv", os.path.join(FOUL_PLAY, ".venv"))
        run(VENV_PY, "-m", "pip", "install", "-q", "requests==2.33.0", "websockets==14.1",
            "python-dateutil==2.8.0")
        run(VENV_PY, "-m", "pip", "install", "-q", "--no-cache-dir", "poke-engine==0.0.48",
            "--config-settings=build-args=--features poke-engine/gen9 --no-default-features")


def showdown():
    ps = os.path.join(SHOWDOWN, "node_modules", "pokemon-showdown")
    if not os.path.isdir(ps):
        os.makedirs(SHOWDOWN, exist_ok=True)
        run(NPM, "install", "--silent", "pokemon-showdown@0.11.11", cwd=SHOWDOWN)
    shutil.copy(os.path.join(HERE, "showdown-custom-formats.js"),
                os.path.join(ps, "dist", "config", "custom-formats.js"))
    for d in ("config/chat-plugins", "logs/repl", "logs/chat", "logs/modlog", "logs/ladderlogs",
              "databases"):
        os.makedirs(os.path.join(ps, d), exist_ok=True)
    hosts = os.path.join(ps, "config", "hosts.csv")
    if HOSTS not in (open(hosts).read() if os.path.exists(hosts) else ""):
        with open(hosts, "a") as fh:
            fh.write(HOSTS)
    cfg = os.path.join(ps, "config", "config.js")
    if not os.path.exists(cfg):
        shutil.copy(os.path.join(ps, "dist", "config", "config-example.js"), cfg)
    if "Run & Bun study overrides" not in open(cfg, encoding="utf-8").read():
        with open(cfg, "a", encoding="utf-8") as fh:
            fh.write(CONFIG)


if __name__ == "__main__":
    os.makedirs(WORK, exist_ok=True)
    foul_play()
    showdown()
    print("ready:", WORK)
