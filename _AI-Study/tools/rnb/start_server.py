#!/usr/bin/env python3
"""Run the local Showdown server the battles use (port 8123); leave it running. See
setup_battles.py."""
import os
import subprocess

from paths import SHOWDOWN

subprocess.run(["node", "pokemon-showdown", "start", "--skip-build", "8123"],
               cwd=os.path.join(SHOWDOWN, "node_modules", "pokemon-showdown"))
