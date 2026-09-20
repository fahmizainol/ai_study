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
import mono_synergy                                    # noqa: E402
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


def by_theme():
    """Role profile per THEME, which needs no classifier at all.

    The archetype cut above has to infer its class; a theme is a validated label -- every
    member shares it -- so this is a direct measurement and the one a themed generator
    actually wants. A Bug gym's floors should come from Bug teams, not from what a monotype
    team carries on average across eighteen dexes that have nothing in common."""
    teams, _ = mono_synergy.read_teams(mono_synergy.GENS)
    grouped = collections.defaultdict(list)
    for t in teams:
        grouped[t["theme"]].append(TS.role_counts(t["data"]))
    print("\nROLE PROFILE BY THEME, carry%% (mean) -- %d theme-validated teams, no classifier"
          % len(teams))
    print("%-9s %5s %s" % ("theme", "n", " ".join("%13s" % r[:12] for r in JOB)))
    overall = {r: statistics.mean([rc[r] for v in grouped.values() for rc in v]) for r in JOB}
    for th in sorted(grouped, key=lambda x: -len(grouped[x])):
        v = grouped[th]
        cells = ["%5.0f%%(%.2f)" % (100 * sum(1 for rc in v if rc[r]) / len(v),
                                    statistics.mean(rc[r] for rc in v)) for r in JOB]
        print("%-9s %5d %s" % (th, len(v), " ".join("%13s" % c for c in cells)))
    print("%-9s %5s %s" % ("ALL", len(teams),
                           " ".join("%13s" % ("      (%.2f)" % overall[r]) for r in JOB)))
    print("\nfloors each THEME implies (carry >= %.2f, round(mean) >= 1). Gym themes marked:"
          % TS.CHASE)
    gyms = {"BUG": "Abi", "FAIRY": "Aimi", "WATER": "Kenn", "ICE": "Douglas", "DARK": "Ciara",
            "GROUND": "Dhara", "PSYCHIC": "Lawrence", "NORMAL": "Bay", "STEEL": "Lilliana"}
    for th in sorted(grouped):
        v = grouped[th]
        floor = {r: round(statistics.mean(rc[r] for rc in v)) for r in JOB
                 if sum(1 for rc in v if rc[r]) / len(v) >= TS.CHASE
                 and round(statistics.mean(rc[r] for rc in v)) >= 1}
        who = gyms.get(th.upper())
        print("  %-9s %-9s %s" % (th, ("<- " + who) if who else "",
                                  ", ".join("%s %d" % kv for kv in sorted(floor.items()))
                                  or "(none)"))


# The nine gyms and the archetype each is assigned in generate_bosses.ARCHETYPE, so the
# per-gym cut can be read without importing the generator (which another session is editing).
GYMS = (("BUG", "Abi", "hyper offense"), ("FAIRY", "Aimi", "offense"),
        ("WATER", "Kenn", "offense"), ("ICE", "Douglas", "offense"),
        ("DARK", "Ciara", "offense"), ("GROUND", "Dhara", "offense"),
        ("PSYCHIC", "Lawrence", "balance"), ("NORMAL", "Bay", "bulky offense"),
        ("STEEL", "Lilliana", "bulky offense"))


def by_gym():
    """The cell each gym actually occupies: its own theme AND its assigned archetype.

    This is the narrowest cut the corpus supports and the one the generator should use, because
    a floor ought to describe teams of this type built this way. Cell sizes are 37-115, so the
    thin ones (Psychic/balance 37, Normal/bulky offense 39) carry real sampling noise and a
    carry rate sitting right on the 0.90 bar there should not be trusted to a single point."""
    lab, _ = load()
    cent = centroids(lab)
    teams, _ = mono_synergy.read_teams(mono_synergy.GENS)
    cell = collections.defaultdict(list)
    for t in teams:
        off = statistics.mean(TS.offence_pct(s.get("evs") or {}) for s in t["data"])
        cell[(t["theme"].upper(), band(off, cent))].append(TS.role_counts(t["data"]))
    print("\nPER-GYM FLOORS from the theme x archetype cell each one occupies")
    print("%-9s %-9s %-14s %5s  %s" % ("theme", "gym", "archetype", "n", "floors from that cell"))
    for th, who, arch in GYMS:
        v = cell[(th, arch)]
        if not v:
            print("%-9s %-9s %-14s %5d  (cell empty)" % (th, who, arch, 0))
            continue
        floor = {r: round(statistics.mean(rc[r] for rc in v)) for r in JOB
                 if sum(1 for rc in v if rc[r]) / len(v) >= TS.CHASE
                 and round(statistics.mean(rc[r] for rc in v)) >= 1}
        shipped = TS.role_plan(arch)["floor"]
        print("%-9s %-9s %-14s %5d  %-34s (shipped: %s)"
              % (th, who, arch, len(v),
                 ", ".join("%s %d" % kv for kv in sorted(floor.items())) or "(none)",
                 ", ".join("%s %d" % kv for kv in sorted(shipped.items())) or "(none)"))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--validate", action="store_true", help="check the bands against labels")
    ap.add_argument("--by-theme", action="store_true",
                    help="role profile per theme instead of per archetype band")
    ap.add_argument("--by-gym", action="store_true",
                    help="the theme x archetype cell each of the nine gyms occupies")
    a = ap.parse_args()
    if a.by_gym:
        by_gym()
        return
    if a.by_theme:
        by_theme()
        return
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
