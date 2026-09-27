#!/usr/bin/env python3
"""Which anchor ranking finds a real team's best attacker? Checked on real Smogon teams.

Core-first builds a gym around an "anchor", and when the dev kept no attacker it picks one
by distance from the fight's eBST target with the attacking stat as a tie-break -- which
gave gym 9 a defensive Heatran over Mega Lucario (RNB-STUDY.md §10). Before replacing that
with a Smogon-informed ranking, test the candidates where the answer is known: the real
Smogon teams already played on this machine (gen 7 at 25 / 10 ms, monotype gen 7-9 at
10 ms). Within each real team, a ranking picks one member; its score is the KOs per battle
that member actually made, against the team's best member and the team average.

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/anchor_test.py
"""
import collections
import os
import random
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import deck_slots as DS  # noqa: E402
import smogon_corpus as SC  # noqa: E402
from make_battle_teams import Exporter  # noqa: E402
from paths import pokedex  # noqa: E402

MIN_BATTLES = 2
ATTACK_ITEMS = {"choiceband", "choicespecs", "choicescarf", "lifeorb", "expertbelt"}
SETUP = {"swordsdance", "nastyplot", "dragondance", "calmmind", "shellsmash", "quiverdance",
         "bulkup", "shiftgear", "coil", "agility", "rockpolish", "tailglow", "bellydrum",
         "geomancy", "workup", "growth", "curse"}


def tid(s):
    return "".join(ch for ch in s.lower() if ch.isalnum())


def members(path, ex):
    """[{sp, item, moves, stats, mega, name}] from an exported team file."""
    out = []
    for b in open(path, encoding="utf-8").read().strip().split("\n\n"):
        lines = b.split("\n")
        head = lines[0].split(" @ ")
        sp, item = tid(head[0]), tid(head[1]) if len(head) > 1 else ""
        e = ex.entry(sp)
        mega = ex.mega.get((tid(e.get("baseSpecies", e["name"])), head[1].strip() if len(head) > 1 else ""))
        form = mega or e
        out.append({"sp": sp, "item": item, "moves": [tid(l[2:]) for l in lines if l.startswith("- ")],
                    "base": e["baseStats"], "form": form["baseStats"], "mega": bool(mega),
                    "tier_name": form["name"]})
    return out


def tier_rank(name):
    t = SC.tier(name)
    return SC.RANK.index(t) if t in SC.RANK else len(SC.RANK)


def attacking(m, kind):
    return kind == "attacker" or m["item"] in ATTACK_ITEMS or m["mega"] or bool(set(m["moves"]) & SETUP)


def main():
    per, kinds, record = DS.collect()
    ex = Exporter(pokedex())
    rng = random.Random(0)
    rankers = {
        "current: best base attack stat": lambda m, k: max(m["base"]["atk"], m["base"]["spa"]),
        "BST (counting the mega)": lambda m, k: sum(m["form"].values()),
        "best attack stat, counting the mega": lambda m, k: max(m["form"]["atk"], m["form"]["spa"]),
        "Smogon tier": lambda m, k: -tier_rank(m["tier_name"]),
        "attacking set, then tier, then mega attack": lambda m, k: (
            attacking(m, k), -tier_rank(m["tier_name"]), max(m["form"]["atk"], m["form"]["spa"])),
        "attacking set, then mega attack, then tier": lambda m, k: (
            attacking(m, k), max(m["form"]["atk"], m["form"]["spa"]), -tier_rank(m["tier_name"])),
        "random member": lambda m, k: rng.random(),
    }
    res = collections.defaultdict(lambda: collections.defaultdict(list))
    teams = collections.Counter()
    arms = [a for a in per if not a.startswith(("rnb_vs_gen_", "rnb_vs_gen_trainers"))]
    for arm in sorted(arms):
        by_team = collections.defaultdict(dict)
        for (team, sp), c in per[arm].items():
            by_team[team][sp] = c
        for team, mons in by_team.items():
            if min(c["battles"] for c in mons.values()) < MIN_BATTLES:
                continue
            side = "smogon"
            path = os.path.join(DS.G, arm, "teams", side, team)
            if not os.path.exists(path):
                continue
            ms = members(path, ex)
            kpb = {m["sp"]: mons[m["sp"]]["kos"] / mons[m["sp"]]["battles"] for m in ms if m["sp"] in mons}
            if len(kpb) < 6:
                continue
            group = "monotype" if "mono" in arm else "mainstream"
            teams[group] += 1
            best, mean = max(kpb.values()), st.mean(kpb.values())
            for name, f in rankers.items():
                pick = max(ms, key=lambda m: f(m, kinds.get((arm, team), {}).get(m["sp"])))
                got = kpb[pick["sp"]]
                res[group][name].append((got, got == best, got - mean))
                res["all"][name].append((got, got == best, got - mean))
    print(f"arms: {', '.join(sorted(arms))}")
    for group in ("mainstream", "monotype", "all"):
        n = teams[group] if group != "all" else sum(teams.values())
        print(f"\n## {group}: {n} real Smogon teams with {MIN_BATTLES}+ battles each")
        print(f"{'ranking':46s} {'anchor KOs/battle':>18s} {'picked the top KO-getter':>25s} {'vs team average':>16s}")
        for name, rows in sorted(res[group].items(), key=lambda kv: -st.mean(r[0] for r in kv[1])):
            print(f"{name:46s} {st.mean(r[0] for r in rows):18.2f} {100 * st.mean(r[1] for r in rows):24.0f}% "
                  f"{st.mean(r[2] for r in rows):+16.2f}")


if __name__ == "__main__":
    main()
