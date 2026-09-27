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
    python tools/rnb/gen_fixes.py choices OUTDIR  # the 2026-09-25 defaults before the walls:
                                                   # ladder sets, no early item cap,
                                                   # SHAPE_CHECK, SET_FIT, SETUP_CAP 1
    python tools/rnb/gen_fixes.py defense OUTDIR  # choices + WALL_MIN 2, REMOVAL_MIN 1
    python tools/rnb/gen_fixes.py atk     OUTDIR  # the 2026-09-27 roster as played at 10 ms:
                                                   # everything current but KEEP_MEASURED
    python tools/rnb/gen_fixes.py measured OUTDIR # atk + KEEP_MEASURED, as played at 10 ms
    python tools/rnb/gen_fixes.py fix     OUTDIR  # measured + the four weak-roster fixes, as played
    python tools/rnb/gen_fixes.py fix2    OUTDIR  # fix + coherence / filler / SETUP_CAP 2, as played
    python tools/rnb/gen_fixes.py core    OUTDIR  # fix2 + CORE_FIRST, THEME_FLOORS, as played
    python tools/rnb/gen_fixes.py core2   OUTDIR  # core + GROW_TO_TARGET, 0.6 KO bar, as played
    python tools/rnb/gen_fixes.py cores2  OUTDIR  # core2 + the off-theme slot rules and the
                                                   # core-first fixes, installed and played
    python tools/rnb/gen_fixes.py shipped OUTDIR  # the generator's current defaults
                                                   # (= cores2 + the breaking core)
    python tools/rnb/gen_fixes.py open    OUTDIR  # defense + the four limiters released
                                                   # (2026-09-26): EARLY_MOVES, all set
                                                   # formats, PICK_FLOOR 0, KEEP_NEED_SET

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
ARMS = ("off", "on", "theme", "tier", "all", "choices", "defense", "open", "atk", "measured", "fix", "fix2", "core", "core2", "cores2", "shipped")
if arm not in ARMS:
    sys.exit("arm is one of " + ", ".join(ARMS))
if arm != "shipped":
    # the breaking core (2026-09-28): second breaker, four attacking sets, speed control
    GB.SECOND_BREAKER, GB.ATTACKERS_MIN, GB.SPEED_FLOOR = 0, 0, 0
if arm not in ("cores2", "shipped"):
    # the off-theme slot rules and egg moves, after the core2 arm was played. NOTE: the
    # game's pokemon.txt / tm.txt were brought to gen 7 on 2026-09-27 (learnset_merge.py),
    # so every arm below rebuilds byte for byte only against the PBS as it was before
    # that -- the .pre-gen7-*.bak files beside them.
    GB.OFF_THEME_CAP, GB.OFF_THEME_MOST, GB.OFF_THEME_EXTRA, GB.EGG_MOVES = 0, 0, 0, 0
    GB.SET_GEN_MAX, GB.FILLER_AVOID = 0, GB.FILLER_AVOID_V2
    GB.MODE_SETTER_FIRST = 0
    # gym 4's hail plan and the Ice minimum of 5 (2026-09-28)
    GB.MODE[3] = None
    GB.ULTRA_BEASTS = frozenset()   # the Ultra Beast stage gate (2026-09-28)
    GB.THEME_MIN = dict(GB.THEME_MIN, ICE=4)
    # the core-first fixes read off real teams (2026-09-28): attacking anchor, off-theme
    # enabler, no patch, protect walls, one weather, no passive attackers, recovery cap
    GB.CORE_ANCHOR_RULE, GB.ENABLER_OFF_THEME, GB.CORE_PATCH = 0, 0, 1
    GB.WALL_PROTECT, GB.WEATHER_EXCLUSIVE, GB.WALL_NEEDS_BULK = 0, 0, 0
    GB.TRAINER_RECOVERY_CAP = 0
if arm not in ("core2", "cores2", "shipped"):
    # evolving a kept original toward the target, and the higher measured bar, after
    # the core arm was played
    GB.GROW_TO_TARGET = 0
    GB.MEASURED_DEALT, GB.MEASURED_KOS = 35.0, 0.2
if arm not in ("core", "core2", "cores2", "shipped"):
    # the core-first build and the per-type floors, after the fix2 arm was played
    GB.CORE_FIRST, GB.THEME_FLOORS = 0, 0
    GB.ITEM_FALLBACK = min(GB.ITEM_FALLBACK, 1)
if arm not in ("fix2", "core", "core2", "cores2", "shipped"):
    # the 2026-09-27 evening changes, after the fix arm was played
    GB.FILLER_AVOID, GB.SET_COHERENCE, GB.SETUP_CAP = GB.FILLER_AVOID_V1, 0, 1
if arm == "choices":
    GB.WALL_MIN, GB.REMOVAL_MIN = 0, 0
if arm == "defense":
    GB.WALL_MIN, GB.REMOVAL_MIN = 2, 1
if arm in ("choices", "defense"):
    # the 2026-09-26 releases, pinned back to how those arms were played
    GB.EARLY_MOVES, GB.KEEP_NEED_SET, GB.PICK_FLOOR = 0, 0, 1
    GB.SET_FORMATS = ("ubers", "ou", "uu", "ru", "nu", "anythinggoes", "nationaldex", "nationaldexag")
    GB.FILLER_AVOID = frozenset()
if arm not in ("atk", "measured", "fix", "fix2", "core", "core2", "cores2", "shipped"):
    # the 2026-09-27 choices, pinned back for every earlier arm
    GB.PICK_NO_LOW, GB.SET_FORMATS_OFF = 0, ("battlespotsingles",)
    GB.ATTACKER_SHAPE, GB.ATTACKER_ITEM, GB.PIVOT_MIN, GB.KEPT_ANY_FORMAT = 0, 0, 0, 0
    GB.REPEAT_BAND = 1
if arm not in ("measured", "fix", "fix2", "core", "core2", "cores2", "shipped"):
    GB.KEEP_MEASURED = 0          # on since 2026-09-27, after the atk arm was played
if arm not in ("fix", "fix2", "core", "core2", "cores2", "shipped"):
    # the changes after the measured arm was played (2026-09-27, late)
    GB.BP_CAP_UNTIL, GB.NO_PLAN_SETS, GB.ITEM_FALLBACK = 3, 0, 0
    if GB.ATTACKER_ITEM:
        GB.ATTACKER_ITEM = 1
if arm not in ("choices", "defense", "open", "atk", "measured", "fix", "fix2", "core", "core2", "cores2", "shipped"):
    # the defaults every test arm below was played under (changed 2026-09-25)
    GB.SET_FORMATS, GB.EARLY_ITEM_CAP = (), 1
    GB.SET_FIT, GB.SETUP_CAP, GB.SHAPE_CHECK = False, None, 0
    GB.WALL_MIN, GB.REMOVAL_MIN = 0, 0
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
