#!/usr/bin/env python3
"""Regenerate the gyms and trainers under one arm of a generator test.

The fixes are module switches in generate_bosses.py. This sets them the way
boss_studio.py applies its knobs, then runs the generators' own CLIs, so nothing in
generated/ that ships is touched:

    python tools/rnb/gen_fixes.py off    OUTDIR   # the CLI baseline: every fix off, and
                                                   # the theme rules as they were
                                                   # (6 on-theme, co-occurrence gate)
    python tools/rnb/gen_fixes.py on     OUTDIR   # the set-level fixes (SET_FIT,
                                                   # SETUP_CAP 1, ITEM_PURPOSE)
    python tools/rnb/gen_fixes.py theme  OUTDIR   # the theme rules as shipped now: 5
                                                   # on-theme, Bug/Ice 4, cover gate
    python tools/rnb/gen_fixes.py tier   OUTDIR   # theme + TIER_BAND 40
    python tools/rnb/gen_fixes.py all    OUTDIR   # theme + SET_TIER_MATCH, USAGE_BAND 30,
                                                   # SHAPE_CHECK, GYM_MODES
    python tools/rnb/gen_fixes.py shipped OUTDIR  # the generator's current defaults

Every arm but `shipped` pins the defaults its test ran under, so an arm keeps
rebuilding the teams it was played with after a default changes.

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
if arm not in ("off", "on", "theme", "tier", "all", "shipped"):
    sys.exit("arm is off, on, theme, tier, all or shipped")
if arm != "shipped":
    # the defaults every test arm below was played under (changed 2026-09-25)
    GB.SET_FORMATS, GB.EARLY_ITEM_CAP = (), 1
    GB.SET_FIT, GB.SETUP_CAP, GB.SHAPE_CHECK = False, None, 0
if arm in ("off", "on"):
    # the theme rules the off/on test ran under, before they changed
    GB.ON_THEME_MIN, GB.THEME_MIN, GB.OFF_THEME_COVER = 6, {}, 0
if arm == "on":
    GB.SET_FIT, GB.SETUP_CAP, GB.ITEM_PURPOSE = True, 1, True
if arm == "tier":
    GB.TIER_BAND = 40
if arm == "all":
    GB.SET_TIER_MATCH, GB.USAGE_BAND, GB.SHAPE_CHECK, GB.GYM_MODES = 1, 30, 1, 1
os.makedirs(out, exist_ok=True)
GB.main(["--json", os.path.join(out, "gyms.json")])
GT.main(["--json", os.path.join(out, "trainers.json")])
