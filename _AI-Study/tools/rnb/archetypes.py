#!/usr/bin/env python3
"""Win rate against the Run & Bun bosses, cut by team archetype, for every battle run.

The archetype is read off the team, not its author's label (the generator records none):
count the wall/support sets as composition.kind() classes them -- 0 hyper offense,
1 offense, 2-3 balance, 4+ stall. Each group is also scored "paired": against what the
same bosses gave up to the study's gen 9 teams (§5), so a group that happened to draw
easy bosses does not look strong. The secondary cuts (setup users, weather, removal,
speed) use the same scoring.

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/archetypes.py   # composition.py needs the game
"""
import collections
import os
import re

import composition as C
from summarize_battles import EXCLUDED
from paths import STUDY, read_results
from team_shape import ROLE_MOVES, WEATHER_ABILITY

G = os.path.join(STUDY, "generated")
tid = C.tid
DEX = C.DEX
kind = C.kind

RUNS = [   # label, experiment dir, opponent side
    ("gen 9 Smogon (§5)", "rnb", "smogon"),
    ("gen 7 intact", "rnb_vs_gen7", "smogon"),
    ("gen 7 shuffled", "rnb_vs_gen7_collage", "smogon"),
    ("gen gyms", "rnb_vs_gen", "gen"),
    ("gen non-gym", "rnb_vs_gen_trainers", "gen"),
    ("gen gyms, fixes off", "rnb_vs_gen_off", "gen"),
    ("gen gyms, fixes on", "rnb_vs_gen_on", "gen"),
    ("gen non-gym, fixes off", "rnb_vs_gen_trainers_off", "gen"),
    ("gen non-gym, fixes on", "rnb_vs_gen_trainers_on", "gen"),
    ("gen gyms, published", "rnb_vs_gen_published", "gen"),
    ("gen non-gym, published", "rnb_vs_gen_trainers_published", "gen"),
]
ARCH = ["hyper offense", "offense", "balance", "stall"]


def archetype(team):
    w = sum(kind(m) == "wall/support" for m in team)
    return ARCH[0] if w == 0 else ARCH[1] if w == 1 else ARCH[2] if w <= 3 else ARCH[3]


def raw_sets(path):
    """species, ability and moves per set, straight from the export."""
    out = []
    for b in open(path, encoding="utf-8").read().strip().split("\n\n"):
        L = b.splitlines()
        sp, _, item = L[0].partition(" @ ")
        ab = next((l[9:] for l in L if l.startswith("Ability: ")), "")
        out.append({"species": sp.strip(), "item": tid(item), "ability": ab,
                    "moves": [re.sub(r"[^A-Z]", "", l[2:].upper()) for l in L if l.startswith("- ")]})
    return out


def traits(path):
    t = C.team(path)
    raw = raw_sets(path)
    setup = sum(bool(set(s["moves"]) & ROLE_MOVES["setup"]) for s in raw)
    weather = any(re.sub(r"[^A-Z]", "", s["ability"].upper()) in WEATHER_ABILITY
                  or set(s["moves"]) & {"SUNNYDAY", "RAINDANCE", "SANDSTORM", "HAIL"} for s in raw)
    removal = any(set(s["moves"]) & ROLE_MOVES["removal"] for s in raw)
    spe = []
    for s in raw:
        e = DEX.get(tid(s["species"]))
        if e and "baseStats" in e:
            spe.append(e["baseStats"]["spe"])
    return {"arch": archetype(t),
            "walls": sum(kind(m) == "wall/support" for m in t),
            "setup": "0" if setup == 0 else "1" if setup == 1 else "2+",
            "weather": "weather" if weather else "none",
            "removal": "removal" if removal else "none",
            "speed": "fast (>=90)" if sum(spe) / len(spe) >= 90 else "slow (<90)"}


def battles(exp, side):
    latest = {}
    for r in read_results(os.path.join(G, exp, "results.ndjson")):
        if r["boss"].startswith(EXCLUDED):   # one double battle in the game: 4-v-6 as singles
            continue
        if not r["error"] and r["turns"] > 0 and r["winner"]:
            latest[r["tag"]] = r
    V = list(latest.values())
    d = os.path.join(G, exp, "teams", side)
    out = []
    for r in V:
        p = os.path.join(d, r["opp"])
        base = [tid(DEX.get(tid(s["species"]), {}).get("baseSpecies", s["species"])) for s in raw_sets(p)]
        if len(set(base)) < len(base):     # two formes of one species: Foul Play cannot pilot it
            continue
        out.append((r, p))
    return out


def boss_rate():
    smog = collections.defaultdict(list)
    for r, _ in battles("rnb", "smogon"):
        smog[r["boss"]].append(r["winner"] != "rnb")
    return {b: sum(x) / len(x) for b, x in smog.items()}


def main():
    rate = boss_rate()
    cache = {}
    rows = []   # (run, traits, won, expected)
    for label, exp, side in RUNS:
        if not os.path.exists(os.path.join(G, exp, "results.ndjson")):
            continue
        for r, p in battles(exp, side):
            if p not in cache:
                cache[p] = traits(p)
            rows.append((label, cache[p], r["winner"] != "rnb", rate.get(r["boss"]), r["opp"]))

    def cell(rs):
        n = len(rs)
        if not n:
            return "%16s" % "-"
        w = sum(x[2] for x in rs)
        e = [x[3] for x in rs if x[3] is not None]
        return "%3d/%-3d %3.0f%% %+4.0f" % (w, n, 100 * w / n, 100 * (w / n - sum(e) / len(e)))

    groups = {"all generator": [l for l, _, s in RUNS if s == "gen"],
              "all real": [l for l, _, s in RUNS if s == "smogon"]}
    for key, vals in (("arch", ARCH), ("setup", ["0", "1", "2+"]), ("weather", ["none", "weather"]),
                      ("removal", ["none", "removal"]), ("speed", ["slow (<90)", "fast (>=90)"])):
        print("\n## by %s   (wins/battles, win%%, points above what the bosses gave gen 9 teams)" % key)
        print("%-24s" % "" + "".join("%18s" % v for v in vals) + "   teams per group")
        for label in [l for l, _, _ in RUNS] + list(groups):
            src = groups.get(label, [label])
            rs = [x for x in rows if x[0] in src]
            if not rs:
                continue
            teams = {(x[0], x[4]): x[1][key] for x in rs}
            cnt = collections.Counter(teams.values())
            print("%-24s" % label + "".join("%18s" % cell([x for x in rs if x[1][key] == v]) for v in vals)
                  + "   " + " ".join(str(cnt[v]) for v in vals))


if __name__ == "__main__":
    main()
