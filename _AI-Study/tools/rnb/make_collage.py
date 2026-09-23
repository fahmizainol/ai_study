#!/usr/bin/env python3
"""Break the gen 7 teams apart: does a team need its six sets written TOGETHER?

Takes the gen 7 Smogon teams that played Run & Bun (generated/rnb_vs_gen7, 67.9%) and
shuffles their sets between teams: many random SWAPS, each exchanging two sets of
similar BST between two teams. Every one of the pool's sets is still used exactly once,
and each team's mean BST stays within 5 of its own (TEAM_DRIFT), so the only thing removed is which sets were written
together, by one author, for one team. The pairings are the same as the intact run, so
every battle compares one-to-one.

If the collages fall toward the boss generator's ~30%, cohesion is what the generator is
missing (it assembles six sets each written for a different team and tier). If they stay
near 68%, it is the sets it picks, not how they are put together.

A swap is accepted only if it keeps both teams legal -- no species twice, at most one
mega stone -- and does not put two sets from one source team back together. Teams Foul
Play cannot pilot (two formes of one species) are left out of pool and schedule alike.

A first version DREW replacements instead of swapping, and could not help favouring
some sets: the sets it left out KO'd 0.79 a battle in the intact run against 0.64 for
the ones it used, which would have made collages look weak for the wrong reason.

    python tools/rnb/make_collage.py        # -> generated/rnb_vs_gen7_collage/
    RNB_OUT=generated/rnb_vs_gen7_collage python tools/rnb/run_battles.py 4 2
"""
import collections
import json
import os
import random
import shutil

from make_battle_teams import tid
from paths import STUDY, pokedex

SRC = os.path.join(STUDY, "generated", "rnb_vs_gen7")
OUT = os.path.join(STUDY, "generated", "rnb_vs_gen7_collage")
BST_WINDOW = 30         # two sets swap only if their BSTs are this close
# Swaps random-walk a team's BST; without this bound the mean moved 28 points (max 97),
# which would change the pairing's difficulty, not just its cohesion. 30 BST over the
# team is 5 per mon.
TEAM_DRIFT = 30
SWAPS = 200_000         # proposals; far past the point where teams stop changing


def blocks(path):
    return open(path, encoding="utf-8").read().strip().split("\n\n")


def main():
    dex = pokedex()
    mega = {(tid(e["baseSpecies"]), e["requiredItem"]): e for e in dex.values()
            if e.get("requiredItem") and e.get("forme", "").startswith(("Mega", "Primal"))}

    def info(team, b):
        sp, _, item = b.split("\n")[0].partition(" @ ")
        e = dex[tid(sp)]
        m = mega.get((tid(e.get("baseSpecies", e["name"])), item.strip()))
        return {"home": team, "text": b, "species": tid(e.get("baseSpecies", e["name"])),
                "mega": m is not None, "bst": sum((m or e)["baseStats"].values())}

    teams = {}
    for f in sorted(os.listdir(os.path.join(SRC, "teams", "smogon"))):
        mons = [info(f, b) for b in blocks(os.path.join(SRC, "teams", "smogon", f))]
        if len({m["species"] for m in mons}) == len(mons):      # pilotable
            teams[f] = mons
    base = {t: sum(m["bst"] for m in ms) for t, ms in teams.items()}

    def legal(team, out_i, incoming):
        rest = [m for j, m in enumerate(team) if j != out_i]
        return (incoming["species"] not in {m["species"] for m in rest}
                and not (incoming["mega"] and any(m["mega"] for m in rest))
                and incoming["home"] not in {m["home"] for m in rest})

    rng = random.Random(7)
    names = list(teams)
    for _ in range(SWAPS):
        a, b = rng.sample(names, 2)
        i, j = rng.randrange(6), rng.randrange(6)
        x, y = teams[a][i], teams[b][j]
        if abs(x["bst"] - y["bst"]) > BST_WINDOW:
            continue
        d = y["bst"] - x["bst"]           # a gains d, b loses d
        now_a = sum(m["bst"] for m in teams[a]) - base[a]
        now_b = sum(m["bst"] for m in teams[b]) - base[b]
        if abs(now_a + d) > TEAM_DRIFT or abs(now_b - d) > TEAM_DRIFT:
            continue
        if legal(teams[a], i, y) and legal(teams[b], j, x):
            teams[a][i], teams[b][j] = y, x

    home = sum(m["home"] == t for t, ms in teams.items() for m in ms)
    drift = [abs(sum(m["bst"] for m in ms) - base[t]) / 6 for t, ms in teams.items()]

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(os.path.join(OUT, "teams", "smogon"))
    shutil.copytree(os.path.join(SRC, "teams", "rnb"), os.path.join(OUT, "teams", "rnb"))
    for t, ms in teams.items():
        with open(os.path.join(OUT, "teams", "smogon", t), "w", encoding="utf-8") as fh:
            fh.write("\n\n".join(m["text"] for m in ms) + "\n")
    pairs = [p for p in json.load(open(os.path.join(SRC, "pairs.json"))) if p["opp"] in teams]
    for p in pairs:
        p["opp_bst"] = round(sum(m["bst"] for m in teams[p["opp"]]) / 6)
    with open(os.path.join(OUT, "pairs.json"), "w") as fh:
        json.dump(pairs, fh, indent=1)
    print("%d teams, %d sets each used once, %d pairings; sets still on their own team %d; "
          "mean |team BST change| %.1f, max %.1f"
          % (len(teams), 6 * len(teams), len(pairs), home, sum(drift) / len(drift), max(drift)))


if __name__ == "__main__":
    main()
