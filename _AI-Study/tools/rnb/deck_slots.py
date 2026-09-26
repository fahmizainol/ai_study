#!/usr/bin/env python3
"""Per-slot contribution for every arm played on the Linux machine (the Deck), from
Showdown's own battle logs: KOs, damage dealt, faints and turns on the field, per set kind
(composition.kind: attacker / in between / wall-support), per arm.

read_battles.main() matches a log to an experiment by its pairing tag plus "every species
seen is on that team", which over-matches once several arms share pairing numbers and
similar teams (the theme arm read 186 battles where 108 were played). Here a log is
assigned to an arm by the attempt's START time instead: the bot username carries
int(t0) % 100000 (run_battles.py), the log carries its own timestamp, and together they
give t0 exactly; SCHEDULE below holds each arm's round blocks as the driver logged them.
Every arm then reads exactly its battle count.

SCHEDULE is data about the runs, kept here so the analysis reproduces. When a new run
finishes on this machine, append its "=== round r arm X <time>" lines from the driver log
(the 10 ms baseline -- gen7_10ms, gen_defense_10ms, gen_trainers_defense_10ms,
gen_atk_10ms, gen_trainers_atk_10ms; driver log ~/.cache/rnb-10ms.log -- is the first
one still to add). Times are the Deck's local clock (GMT+8).

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/deck_slots.py            # composition.py needs the game
    DETAIL=rnb_vs_gen_defense REALIDEA_PBS=... python3 tools/rnb/deck_slots.py   # + one arm's attacker slots
"""
import collections
import datetime
import glob
import json
import os
import re
import sys
import time

from paths import STUDY, TOOLS, pokedex

sys.path.insert(0, TOOLS)
import read_battles as R  # noqa: E402
import composition as C  # noqa: E402

G = os.path.join(STUDY, "generated")
# (local start, arm). None = played but not an arm (smoke tests, the discarded 500 ms run,
# the gaps between runs). A battle belongs to the last block that started before it did.
SCHEDULE = [
    ("2026-09-24 22:40:00", None),
    ("2026-09-24 23:00:44", "rnb_vs_gen_deckoff"), ("2026-09-24 23:05:00", "rnb_vs_gen_theme"),
    ("2026-09-24 23:09:47", "rnb_vs_gen_tier"), ("2026-09-24 23:14:53", "rnb_vs_gen_deckoff"),
    ("2026-09-24 23:19:15", "rnb_vs_gen_theme"), ("2026-09-24 23:23:51", "rnb_vs_gen_tier"),
    ("2026-09-24 23:28:33", "rnb_vs_gen_deckoff"), ("2026-09-24 23:33:11", "rnb_vs_gen_theme"),
    ("2026-09-24 23:37:49", "rnb_vs_gen_tier"), ("2026-09-24 23:42:46", None),
    ("2026-09-24 23:55:04", "rnb_vs_gen_all"), ("2026-09-24 23:59:35", "rnb_vs_gen_trainers_all"),
    ("2026-09-25 00:04:33", "rnb_vs_gen_trainers_theme"), ("2026-09-25 00:10:06", "rnb_vs_gen_all"),
    ("2026-09-25 00:14:11", "rnb_vs_gen_trainers_all"), ("2026-09-25 00:19:07", "rnb_vs_gen_trainers_theme"),
    ("2026-09-25 00:24:28", "rnb_vs_gen_all"), ("2026-09-25 00:28:36", "rnb_vs_gen_trainers_all"),
    ("2026-09-25 00:33:36", "rnb_vs_gen_trainers_theme"), ("2026-09-25 00:38:43", None),
    ("2026-09-25 01:07:16", "rnb_vs_gen_choices"), ("2026-09-25 01:11:58", "rnb_vs_gen_trainers_choices"),
    ("2026-09-25 01:17:27", "rnb_vs_gen_choices"), ("2026-09-25 01:21:38", "rnb_vs_gen_trainers_choices"),
    ("2026-09-25 01:26:37", "rnb_vs_gen_choices"), ("2026-09-25 01:31:01", "rnb_vs_gen_trainers_choices"),
    ("2026-09-25 01:36:11", "rnb_vs_gen_defense"), ("2026-09-25 01:40:35", "rnb_vs_gen_trainers_defense"),
    ("2026-09-25 01:45:54", "rnb_vs_gen_defense"), ("2026-09-25 01:50:31", "rnb_vs_gen_trainers_defense"),
    ("2026-09-25 01:55:54", "rnb_vs_gen_defense"), ("2026-09-25 02:00:45", "rnb_vs_gen_trainers_defense"),
    ("2026-09-25 02:06:14", None),
    ("2026-09-25 02:24:37", "rnb_vs_gen7_25ms"),          # incl. the 9 leftovers resumed later that day
    # the 10 ms baseline (2026-09-27); the gen7_10ms blocks also cover its retries of the
    # unpilotable pairing, which the watchdog killed
    ("2026-09-27 00:44:40", "rnb_vs_gen7_10ms"),
    ("2026-09-27 00:56:57", "rnb_vs_gen_defense_10ms"),
    ("2026-09-27 01:00:28", "rnb_vs_gen_trainers_defense_10ms"),
    ("2026-09-27 01:04:41", "rnb_vs_gen_atk_10ms"),
    ("2026-09-27 01:08:21", "rnb_vs_gen_trainers_atk_10ms"),
    ("2026-09-27 01:12:45", "rnb_vs_gen7_10ms"),
    ("2026-09-27 01:25:27", "rnb_vs_gen_defense_10ms"),
    ("2026-09-27 01:28:51", "rnb_vs_gen_trainers_defense_10ms"),
    ("2026-09-27 01:32:51", "rnb_vs_gen_atk_10ms"),
    ("2026-09-27 01:37:19", "rnb_vs_gen_trainers_atk_10ms"),
    ("2026-09-27 01:42:49", "rnb_vs_gen_defense_10ms"),
    ("2026-09-27 01:46:51", "rnb_vs_gen_trainers_defense_10ms"),
    ("2026-09-27 01:50:39", "rnb_vs_gen_atk_10ms"),
    ("2026-09-27 01:54:47", "rnb_vs_gen_trainers_atk_10ms"),
    ("2026-09-27 02:00:03", None),
    # KEEP_MEASURED roster and the identical replay of the new roster (2026-09-27)
    ("2026-09-27 02:17:58", "rnb_vs_gen_measured_10ms"),
    ("2026-09-27 02:22:03", "rnb_vs_gen_trainers_measured_10ms"),
    ("2026-09-27 02:27:06", "rnb_vs_gen_measured_10ms"),
    ("2026-09-27 02:30:43", "rnb_vs_gen_trainers_measured_10ms"),
    ("2026-09-27 02:35:12", "rnb_vs_gen_measured_10ms"),
    ("2026-09-27 02:39:04", "rnb_vs_gen_trainers_measured_10ms"),
    ("2026-09-27 02:43:28", None),
    ("2026-09-27 02:46:55", "rnb_vs_gen_atk_10ms_b"),
    ("2026-09-27 02:50:31", "rnb_vs_gen_trainers_atk_10ms_b"),
    ("2026-09-27 02:55:13", "rnb_vs_gen_atk_10ms_b"),
    ("2026-09-27 02:59:01", "rnb_vs_gen_trainers_atk_10ms_b"),
    ("2026-09-27 03:03:37", "rnb_vs_gen_atk_10ms_b"),
    ("2026-09-27 03:07:27", "rnb_vs_gen_trainers_atk_10ms_b"),
    ("2026-09-27 03:11:49", None),
]
SCHED = [(time.mktime(datetime.datetime.strptime(s, "%Y-%m-%d %H:%M:%S").timetuple()), a) for s, a in SCHEDULE]
ORDER = ["rnb_vs_gen_deckoff", "rnb_vs_gen_theme", "rnb_vs_gen_tier", "rnb_vs_gen_all",
         "rnb_vs_gen_choices", "rnb_vs_gen_defense", "rnb_vs_gen_trainers_theme",
         "rnb_vs_gen_trainers_all", "rnb_vs_gen_trainers_choices", "rnb_vs_gen_trainers_defense",
         "rnb_vs_gen7_25ms"]
KINDS = ("attacker", "in between", "wall/support")


def start_of(log):
    """The attempt's start epoch, from the username suffix and the log's timestamp."""
    m = re.match(r"[rs]b\d+x\d+t(\d+)", log["p1"])
    ts = datetime.datetime.strptime(log["timestamp"][:24], "%a %b %d %Y %H:%M:%S")
    E = time.mktime(ts.timetuple())
    return E - ((E - int(m.group(1))) % 100000) if m else None


def arm_of(t0):
    arm = None
    for start, a in SCHED:
        if t0 >= start:
            arm = a
    return arm


def collect():
    """-> (per[arm][(team, species)] Counter, kinds[(arm, team)][species], record[arm][(team, won)])."""
    dex = pokedex()
    pairs, kinds = {}, {}
    per = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    record = collections.defaultdict(collections.Counter)
    for f in glob.glob(os.path.join(R.LOGS, "*", "*", "*", "*.log.json")):
        try:
            d = json.load(open(f, encoding="utf-8"))
        except ValueError:                 # truncated by a crash mid-write
            continue
        t0 = start_of(d)
        if t0 is None:
            continue
        arm = arm_of(t0)
        if not arm:
            continue
        names, won, stat = R.battle(f)
        if stat is None:
            continue
        if arm not in pairs:
            pairs[arm] = json.load(open(os.path.join(G, arm, "pairs.json")))
        rside = "p1" if names["p1"].startswith("r") else "p2"
        oside = "p2" if rside == "p1" else "p1"
        m = re.match(r"rb(\d+)x\d+t", names[rside])
        p = pairs[arm][int(m.group(1))]
        team = p["opp"]
        path = os.path.join(G, arm, "teams", p.get("opp_side", "smogon"), team)
        blocks = open(path, encoding="utf-8").read().strip().split("\n\n")
        own = [R.tid(b.split("\n")[0].split(" @ ")[0]) for b in blocks]
        base = {R.tid(dex[sp].get("baseSpecies", sp)) for sp in own}
        if len(base) < len(own):
            continue                       # two formes of one species: not pilotable
        if not {sp for (s, sp) in stat if s == oside} <= set(own):
            print("MISMATCH", arm, team, f, file=sys.stderr)
            continue
        if (arm, team) not in kinds:
            kinds[arm, team] = dict(zip(own, [C.kind(x) for x in C.team(path)]))
        record[arm][team, won == oside] += 1
        for sp in own:
            c = stat.get((oside, sp), collections.Counter())
            per[arm][team, sp].update(c)
            per[arm][team, sp]["battles"] += 1
            per[arm][team, sp]["dead"] += c["kos"] == 0 and c["onfield"] < 2
    return per, kinds, record


def main():
    per, kinds, record = collect()
    print("%-28s %7s %6s | %-30s %-30s %-30s" % ("arm", "battles", "won", "attacker: KO/b faint% turns dead%",
                                                 "in between", "wall/support"))
    for arm in ORDER:
        rec = record[arm]
        n = sum(rec.values())
        if not n:
            continue
        w = sum(v for (t, ok), v in rec.items() if ok)
        cells = []
        for k in KINDS:
            cs = [c for (t, sp), c in per[arm].items() if kinds[arm, t][sp] == k]
            b = sum(c["battles"] for c in cs) or 1
            cells.append("%4.2f %5.0f%% %5.1f %5.0f%%  (%3d)" % (
                sum(c["kos"] for c in cs) / b, 100 * sum(c["fainted"] for c in cs) / b,
                sum(c["onfield"] for c in cs) / b, 100 * sum(c["dead"] for c in cs) / b, len(cs)))
        print("%-28s %7d %5.1f%% | %-30s %-30s %-30s" % (arm, n, 100 * w / n, *cells))

    print("\nattacker damage dealt per battle (% of an opposing mon's max HP), and per turn on the field")
    for arm in ORDER:
        cs = [c for (t, sp), c in per[arm].items() if kinds.get((arm, t), {}).get(sp) == "attacker"]
        if not cs:
            continue
        b = sum(c["battles"] for c in cs)
        turns = sum(c["onfield"] for c in cs) or 1
        print("  %-28s dealt %5.0f%% / battle, %5.1f%% / turn" % (
            arm, sum(c["dealt"] for c in cs) / b, sum(c["dealt"] for c in cs) / turns))

    detail = os.environ.get("DETAIL")
    if detail:
        import smogon_corpus as SC
        print("\n%s attacker slots" % detail)
        side = "smogon" if "gen7" in detail else "gen"
        rows = []
        for (t, sp), c in per[detail].items():
            if kinds[detail, t][sp] != "attacker":
                continue
            path = os.path.join(G, detail, "teams", side, t)
            block = next(b for b in open(path, encoding="utf-8").read().strip().split("\n\n")
                         if R.tid(b.split("\n")[0].split(" @ ")[0]) == sp)
            head = block.split("\n")[0]
            moves = [ln[2:] for ln in block.split("\n") if ln.startswith("- ")]
            n = c["battles"]
            rows.append((c["kos"] / n, t, head, SC.tier(head.split(" @ ")[0]), c["dealt"] / n,
                         100 * c["fainted"] / n, c["onfield"] / n, " / ".join(moves)))
        for ko, t, head, tier, dealt, faint, on, mv in sorted(rows):
            print("  %-5s %-32s %-5s KO %4.2f dealt %4.0f%% faint %3.0f%% turns %4.1f | %s"
                  % (t, head, tier, ko, dealt, faint, on, mv))


if __name__ == "__main__":
    main()
