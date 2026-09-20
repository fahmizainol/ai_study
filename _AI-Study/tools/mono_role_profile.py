#!/usr/bin/env python3
"""The archetype role profile for MONOTYPE teams, which the tagged corpus cannot give.

`team_shape.profile()` derives every floor from the 1,959 title-tagged teams, and **five of
them are monotype** -- nobody titles a post "Water Balance". So the floors a themed gym is
held to were measured on teams that had no theme, and `MONOTYPE-SYNERGY.md` §11 shows that
matters for recovery and setup.

There are 4,898 monotype teams in the dump and no labels on them, so the archetype has to be
recovered. This classifies on **EV offence share alone**:

  * `TEAM-CORPUS.md` §2 measured that offensive EV share orders monotonically along the
    archetype axis -- stall 14% to hyper offense 78% -- so one feature carries the signal.
  * Using recovery or setup counts as features would be **circular**: the floors are those
    same counts, so a classifier fed them would reproduce them by construction. An EV spread
    is not a move, so banding on it and then reporting move roles is a real measurement.

Per-team accuracy is only ~53% over five classes, which does not matter here and is reported
anyway: what the floors need is the per-class ROLE MEAN, and `--validate` shows the bands
recover those on the labelled teams they can be checked against.

    python3 tools/mono_role_profile.py --validate    # the check, on labelled teams
    python3 tools/mono_role_profile.py               # the monotype table and its floors
"""
import argparse
import collections
import os
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smogon_corpus as SC                             # noqa: E402
import team_shape as TS                                # noqa: E402
import team_tags                                       # noqa: E402

JOB = [k for k in TS.ROLES if k not in TS.MODE_ROLES]


def load():
    """(labelled non-monotype, monotype) as [(archetype|None, role_counts, ev_offence)]."""
    lab, mono = [], []
    for stem, team in SC.dump_teams():
        rc = TS.role_counts(team["data"])
        off = statistics.mean(TS.offence_pct(s.get("evs") or {}) for s in team["data"])
        if "monotype" in stem:
            mono.append((None, rc, off))
        else:
            arch = team_tags.tags(team.get("name") or "")["archetype"]
            if arch:
                lab.append((arch, rc, off))
    return lab, mono


def centroids(lab):
    return {a: statistics.mean(o for x, _, o in lab if x == a) for a in TS.ARCHETYPES}


def band(off, cent):
    return min(TS.ARCHETYPES, key=lambda a: abs(off - cent[a]))


def table(rows, cent, label):
    """carry% and mean per role per band, plus the floors those numbers imply."""
    grouped = collections.defaultdict(list)
    for _, rc, off in rows:
        grouped[band(off, cent)].append(rc)
    print("\n%s" % label)
    print("%-10s %s" % ("role", " ".join("%16s" % ("%s %d" % (a[:9], len(grouped[a])))
                                         for a in TS.ARCHETYPES)))
    for r in JOB:
        cells = []
        for a in TS.ARCHETYPES:
            v = [rc[r] for rc in grouped[a]] or [0]
            cells.append("%6.0f%%(%.2f)" % (100 * sum(1 for x in v if x) / len(v),
                                            statistics.mean(v)))
        print("%-10s %s" % (r, " ".join("%16s" % c for c in cells)))
    print("\nfloors these numbers imply (carry >= %.2f and round(mean) >= 1):" % TS.CHASE)
    for a in TS.ARCHETYPES:
        floor = {}
        for r in JOB:
            v = [rc[r] for rc in grouped[a]] or [0]
            if sum(1 for x in v if x) / len(v) >= TS.CHASE and round(statistics.mean(v)) >= 1:
                floor[r] = round(statistics.mean(v))
        shipped = TS.role_plan(a)["floor"]
        print("  %-14s here: %-30s shipped (tagged, themeless): %s"
              % (a, ", ".join("%s %d" % kv for kv in sorted(floor.items())) or "(none)",
                 ", ".join("%s %d" % kv for kv in sorted(shipped.items())) or "(none)"))


def validate(lab, cent):
    """Do the bands recover the TRUE per-archetype role means? That is the fitness test.

    Per-team accuracy is the wrong measure -- a floor is a per-class mean, so a classifier
    that shuffles teams within a band while keeping the band's composition right is fit for
    this purpose and a per-team score would call it mediocre."""
    ok = sum(1 for a, _, o in lab if band(o, cent) == a)
    print("EV-offence centroids: %s"
          % ", ".join("%s %.0f%%" % (a, cent[a]) for a in TS.ARCHETYPES))
    print("per-team accuracy %.0f%% over 5 classes (chance ~20%%) -- not the fitness test"
          % (100 * ok / len(lab)))
    print("\ntrue / EV-banded role means on the %d labelled teams:" % len(lab))
    print("%-10s %s" % ("role", " ".join("%17s" % a[:16] for a in TS.ARCHETYPES)))
    for r in ("recovery", "setup", "pivot", "status", "hazards", "removal"):
        cells = []
        for a in TS.ARCHETYPES:
            t = statistics.mean(rc[r] for x, rc, _ in lab if x == a)
            b = statistics.mean(rc[r] for _, rc, o in lab if band(o, cent) == a)
            cells.append("%7.2f /%6.2f" % (t, b))
        print("%-10s %s" % (r, " ".join("%17s" % c for c in cells)))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--validate", action="store_true", help="check the bands against labels")
    a = ap.parse_args()
    lab, mono = load()
    cent = centroids(lab)
    print("labelled non-monotype teams %d | monotype teams %d" % (len(lab), len(mono)))
    if a.validate:
        validate(lab, cent)
        table(lab, cent, "the LABELLED THEMELESS teams, banded the same way (the control):")
    else:
        table(mono, cent, "MONOTYPE teams by EV-offence band:")


if __name__ == "__main__":
    main()
