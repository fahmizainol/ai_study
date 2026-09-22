#!/usr/bin/env python3
"""Run & Bun team-building, measured with the same code as the Smogon corpus work.

Nothing here is a new metric. Roles are `team_shape.ROLE_MOVES` (TEAM-CORPUS.md §2),
coverage is `archetype_coverage.profile` (§12), theme weaknesses are
`mono_synergy.score` (MONOTYPE-SYNERGY.md §1). The Run & Bun teams go through exactly the
code path the corpus teams did, and gen 9 OU / National Dex samples are scored beside them
so every number has a reference. RNB-STUDY.md §4 is this script's output.

    python3 tools/rnb/team_synergy.py

Needs generated/rnb/trainers.json + rows.json (parse_trainers.py, difficulty_curve.py) and
the gen 9 dex cache generated/showdown_dex.json (tools/dump_showdown_dex.js; set
SHOWDOWN_DIR to an `npm install pokemon-showdown` tree if you have no checkout).
"""
import collections
import json
import os
import random
import statistics as st
import sys
import types

from paths import DUMP, TOOLS, out

sys.path.insert(0, TOOLS)
# team_shape imports realidea_data, which insists on finding a Realidea install at import
# time. Nothing used here touches it.
sys.modules.setdefault("realidea_data", types.ModuleType("realidea_data"))
import archetype_coverage as AC  # noqa: E402
import mono_synergy as MS  # noqa: E402
import team_shape as ts  # noqa: E402
import type_model as TM  # noqa: E402
from type_model import attack_types, bodies, null_draws, taken, tid  # noqa: E402

ALIAS = {"enamorust": "enamorustherian"}
THEME = {"Brawly": "Fighting", "Roxanne": "Rock", "Wattson": "Electric", "Norman": "Normal",
         "Flannery": "Fire", "Winona": "Flying", "Tate": "Psychic", "Liza": "Psychic",
         "Juan": "Water", "Sidney": "Dark", "Phoebe": "Ghost", "Glacia": "Ice",
         "Drake": "Dragon", "Wallace": "Water"}
REPORT_ROLES = [r for r in ts.ROLES if r not in ("sun", "rain", "sand", "snow", "trickroom")]


def load_dex():
    d = TM.dex()["gen9"]
    return d["species"], d["chart"], d["moves"], d["items"]


def rnb_teams(SP, MV):
    """Every trainer as a type_model team, with kind/segment from rows.json."""
    with open(out("trainers.json"), encoding="utf-8") as fh:
        trainers = json.load(fh)
    with open(out("rows.json")) as fh:
        rows = json.load(fh)
    unresolved = collections.Counter()
    teams = []
    for t, r in zip(trainers, rows):
        mons = []
        for m in t["mons"]:
            s = SP.get(ALIAS.get(tid(m["sp"]), tid(m["sp"])))
            if not s:
                unresolved["species:" + m["sp"]] += 1
                continue
            moves = []
            for mv in m["moves"]:
                if tid(mv) in MV:
                    moves.append(tid(mv))
                else:
                    unresolved["move:" + mv] += 1
            mons.append({"species": s["name"], "display": s["name"], "types": s["types"],
                         "ability": m["ability"], "item": m["item"] or "", "tera": None,
                         "moves": moves})
        teams.append({"gen": 9, "format": "rnb", "name": t["name"], "kind": r["kind"],
                      "seg": r["seg"], "cap": r["cap"], "dbl": r["dbl"], "mons": mons})
    if unresolved:
        print("unresolved:", dict(unresolved))
    return teams


def boss_teams(teams):
    """Every boss fight once -- the rival's three starter variants count as one fight."""
    seen, out_ = set(), []
    for t in teams:
        if t["kind"] != "boss":
            continue
        if "Rival" in t["name"]:
            if t["seg"] in seen:
                continue
            seen.add(t["seg"])
        out_.append(t)
    return out_


def corpus(fmt, SP, items, cap=None):
    """Six-mon teams from one smogon-dump format, species resolved and megas applied."""
    teams = []
    with open(os.path.join(DUMP, fmt + ".json"), encoding="utf-8") as fh:
        raw = json.load(fh)
    for team in raw:
        data = team.get("data") or []
        if len(data) != 6:
            continue
        mons = []
        for m in data:
            s = SP.get(tid(m["species"]))
            if not s:
                break
            s = TM.mega_forme(s, m.get("item"), SP, items, collections.Counter())
            mons.append({"species": s["name"], "display": s["name"], "types": s["types"],
                         "ability": m.get("ability") or "", "item": m.get("item") or "",
                         "tera": None, "moves": [tid(x) for x in m.get("moves") or ()]})
        if len(mons) == 6:
            teams.append({"gen": 9, "format": fmt, "mons": mons})
    random.Random(1).shuffle(teams)
    return teams[:cap] if cap else teams


def roles(teams):
    """{role: (% of teams with >=1 set, mean sets per team)}."""
    n = len(teams)
    pres, cnt = collections.Counter(), collections.Counter()
    for t in teams:
        for k, v in ts.role_counts(t["mons"]).items():
            cnt[k] += v
            pres[k] += v > 0
    return {k: (100 * pres[k] / n, cnt[k] / n) for k in ts.ROLES}


def coverage(teams, pool, CH, MV, pop, rng, trials):
    """Mean profile and mean residual against `trials` shuffles of `pool` (own-pool null)."""
    obs, res = collections.defaultdict(list), collections.defaultdict(list)
    for t in teams:
        p = AC.profile(t, CH, MV, pop)
        nulls = [AC.profile({"gen": 9, "format": t["format"], "mons": pick}, CH, MV, pop)
                 for pick in null_draws(pool, trials, rng)]
        for k in AC.AXES:
            obs[k].append(p[k])
            res[k].append(p[k] - st.mean(x[k] for x in nulls))
    return {k: (st.mean(obs[k]), st.mean(res[k])) for k in AC.AXES}


def offence(teams, MV):
    dmg = stab = stat = nmon = 0
    per_mon = []
    for t in teams:
        for m in t["mons"]:
            nmon += 1
            hit = set()
            for mv in m["moves"]:
                ats = attack_types(mv, m, t, MV)
                if not ats:
                    stat += 1
                    continue
                dmg += 1
                stab += bool(set(ats) & set(m["types"]))
                hit |= set(ats)
            per_mon.append(len(hit))
    tot = dmg + stat
    return {"moves/mon": tot / nmon, "damaging %": 100 * dmg / tot,
            "STAB % of damaging": 100 * stab / max(dmg, 1), "status-move %": 100 * stat / tot,
            "attack types/mon": st.mean(per_mon),
            "single-type attackers %": 100 * sum(a <= 1 for a in per_mon) / nmon}


def holes_of(t, CH):
    atks = [a for a in CH if a != "Stellar"]
    stacked = [a for a in atks if sum(taken(a, m, CH) >= 2 for m in t["mons"]) >= 3]
    return stacked, [a for a in stacked if not any(taken(a, m, CH) < 1 for m in t["mons"])]


def theme_weaknesses(teams, CH):
    print("\n== theme weaknesses (MONOTYPE-SYNERGY method: members under x1 / still weak)")
    agg, pairs = collections.Counter(), 0
    for t in teams:
        if "Aqua" in t["name"] or "Magma" in t["name"]:
            continue
        if not any(w in t["name"] for w in ("Leader", "Elite", "Champion")):
            continue
        theme = next((v for k, v in THEME.items() if k in t["name"]), None)
        if not theme:
            continue
        parts = []
        for atk, v in MS.score(dict(t, theme=theme), CH).items():
            pairs += 1
            agg["resist" if v["answers"] else ("none" if v["best"] >= 2 else "neutral")] += 1
            agg["still_weak"] += v["still_weak"]
            agg["members"] += len(t["mons"])
            who = ", ".join("%s(%s)" % (s, mech) for s, mech, _ in v["who"])
            parts.append("%s: %d [%s] weak %d" % (atk, v["answers"], who, v["still_weak"]))
        print("%-28s (%s) %s" % (t["name"][:28], theme, " | ".join(parts)))
    print("pairs %d: resist/immune %.0f%%, neutral best %.0f%%, nothing under x2 %.0f%%, "
          "still weak per 6 members %.2f" % (
              pairs, 100 * agg["resist"] / pairs, 100 * agg["neutral"] / pairs,
              100 * agg["none"] / pairs, agg["still_weak"] / pairs * 6 / (agg["members"] / pairs)))


SETTER = {"Drought": "sun", "Drizzle": "rain", "Sand Stream": "sand", "Snow Warning": "snow",
          "Primordial Sea": "rain", "Desolate Land": "sun", "Orichalcum Pulse": "sun",
          "Electric Surge": "eterrain", "Grassy Surge": "gterrain", "Psychic Surge": "pterrain",
          "Misty Surge": "mterrain", "Hadron Engine": "eterrain"}
ABUSER = {"sun": {"Chlorophyll", "Solar Power", "Protosynthesis", "Flower Gift", "Harvest"},
          "rain": {"Swift Swim", "Rain Dish", "Dry Skin", "Hydration"},
          "sand": {"Sand Rush", "Sand Force", "Sand Veil"},
          "snow": {"Slush Rush", "Ice Body", "Snow Cloak"},
          "eterrain": {"Surge Surfer", "Quark Drive"}, "gterrain": {"Grass Pelt"}}
MODE_MOVE = {"sunnyday": "sun", "raindance": "rain", "sandstorm": "sand", "hail": "snow",
             "snowscape": "snow", "electricterrain": "eterrain", "grassyterrain": "gterrain",
             "psychicterrain": "pterrain", "mistyterrain": "mterrain", "trickroom": "trickroom"}


def modes(t):
    return ({SETTER[m["ability"]] for m in t["mons"] if m["ability"] in SETTER}
            | {MODE_MOVE[mv] for m in t["mons"] for mv in m["moves"] if mv in MODE_MOVE})


def main():
    SP, CH, MV, items = load_dex()
    teams = rnb_teams(SP, MV)
    bosses = boss_teams(teams)
    fill6 = [t for t in teams if t["kind"] == "filler" and len(t["mons"]) == 6]
    fill_all = [t for t in teams if t["kind"] == "filler"]
    print("bosses %d, 6-mon fillers %d, all fillers %d" % (len(bosses), len(fill6), len(fill_all)))
    refs = {"gen9ou": corpus("gen9ou", SP, items, 800),
            "gen9nationaldex": corpus("gen9nationaldex", SP, items, 800)}

    groups = [("bosses", bosses), ("6-mon filler", fill6)] + list(refs.items())
    table = {g: roles(tt) for g, tt in groups}
    print("\n== roles: % teams with >=1 set / mean sets per team")
    print("%-10s" % "role" + "".join("%18s" % g[:16] for g, _ in groups))
    for k in REPORT_ROLES:
        print("%-10s" % k + "".join("%11.0f%% %5.2f" % table[g][k] for g, _ in groups))
    singles = [t for t in bosses if not t["dbl"] and "Tag" not in t["name"]]
    doubles = [t for t in bosses if t not in singles]
    for g, tt in (("singles bosses", singles), ("doubles/tag bosses", doubles)):
        r = roles(tt)
        print("%-20s" % g + " ".join("%s %.0f%%" % (k, r[k][0]) for k in REPORT_ROLES))

    pop = bodies([t for t in teams if t["mons"]] + sum(refs.values(), []),
                 key=lambda t: (t["gen"], t["format"]))
    rng = random.Random(7)
    cov = {"bosses": coverage(bosses, bosses, CH, MV, pop, rng, 150),
           "6-mon filler": coverage(fill6, fill6, CH, MV, pop, rng, 150)}
    for fmt, tt in refs.items():
        cov[fmt] = coverage(tt[:300], tt, CH, MV, pop, rng, 60)
    print("\n== coverage: raw (residual vs own-pool null)")
    print("%-14s" % "axis" + "".join("%22s" % g[:16] for g in cov))
    for k in AC.AXES:
        cells = [("%5.0f%% (%+5.1f)" % (100 * v[0], 100 * v[1])) if k == "reach"
                 else "%6.2f (%+5.2f)" % v for v in (cov[g][k] for g in cov)]
        print("%-14s" % k + "".join("%22s" % c for c in cells))

    print("\n== per boss")
    for t in bosses:
        p = AC.profile(t, CH, MV, pop)
        stacked, holes = holes_of(t, CH)
        atk = {at for m in t["mons"] for mv in m["moves"] for at in attack_types(mv, m, t, MV)}
        rc = ts.role_counts(t["mons"])
        print("%-34s blind %d stacked %s holes %s reach %.0f%% atktypes %d | %s" % (
            t["name"][:34], p["blind"], stacked, holes, 100 * p["reach"], len(atk),
            " ".join("%s%d" % (k, v) for k, v in rc.items() if v and k in REPORT_ROLES)))

    print("\n== offence per mon")
    for g, tt in [("bosses", bosses), ("6-mon filler", fill6), ("all filler", fill_all)] + list(refs.items()):
        print("%-16s %s" % (g, "  ".join("%s %.2f" % kv for kv in offence(tt, MV).items())))

    theme_weaknesses(teams, CH)

    print("\n== modes (weather / terrain / Trick Room) on boss teams, with abusers")
    for t in bosses:
        ms = modes(t)
        if ms:
            print("%-34s %s" % (t["name"][:34], {md: [m["species"] for m in t["mons"]
                                                      if m["ability"] in ABUSER.get(md, ())]
                                                 for md in sorted(ms)}))
    print("fillers setting any mode: %d / %d" % (sum(1 for t in fill_all if modes(t)), len(fill_all)))


if __name__ == "__main__":
    main()
