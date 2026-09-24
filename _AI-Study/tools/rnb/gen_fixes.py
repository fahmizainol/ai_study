#!/usr/bin/env python3
"""Regenerate the gyms and trainers with the set-level fixes switched ON, for testing.

The fixes are module switches in generate_bosses.py (SET_FIT, SETUP_CAP, ITEM_PURPOSE),
off by default. This sets them the way boss_studio.py applies its knobs, then runs the
generators' own CLIs, so nothing in generated/ that ships is touched:

    python tools/rnb/gen_fixes.py off  OUTDIR     # the CLI baseline (same code, switches off)
    python tools/rnb/gen_fixes.py on   OUTDIR     # all three fixes

Writes OUTDIR/gyms.json and OUTDIR/trainers.json. Compare the two with
make_gen_battles.py --from, not with the committed teams_*.json: those carry Boss Studio
preset settings and hand edits the CLI does not.
"""
import os
import sys

from paths import TOOLS

sys.path.insert(0, TOOLS)
os.chdir(TOOLS)
import generate_bosses as GB  # noqa: E402
import generate_trainers as GT  # noqa: E402

arm, out = sys.argv[1], os.path.abspath(sys.argv[2])
if arm == "on":
    GB.SET_FIT, GB.SETUP_CAP, GB.ITEM_PURPOSE = True, 1, True
elif arm != "off":
    sys.exit("arm is on or off")
os.makedirs(out, exist_ok=True)
GB.main(["--json", os.path.join(out, "gyms.json")])
GT.main(["--json", os.path.join(out, "trainers.json")])
