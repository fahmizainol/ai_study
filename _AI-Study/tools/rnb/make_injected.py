#!/usr/bin/env python3
"""Put the boss generator's sets into real teams: are its SETS what is weaker?

The collage run (make_collage.py) showed six sets need not come from one team, so what
separates the generator from real teams is the sets themselves. This tests it head on:
each gen 7 team from generated/rnb_vs_gen7 (67.9% against Run & Bun) gets K of its sets
replaced by generator sets (the gyms' and the non-gym teams', as exported for battle) of
similar BST, and plays the same pairings. If real teams fall as they absorb generator
sets, the sets are weaker; the logs then say which kind of set costs what, because a
generator set and the real set it replaced play in the same team against the same boss.

Per team: K replacements, each within BST_WINDOW of the slot it takes, keeping no
species twice and at most one mega stone; every generator set is used at most MAX_USES
times, least-used first, so the injected pool is spread over all 114 sets. Teams Foul
Play cannot pilot are left out (the collage run's 78). The draw is seeded: rebuilding
gives the same files.

Writes generated/rnb_vs_gen7_injected/ with injected.json (per team: which slot, the
real set it replaced, the generator set, its source team). Refuses to overwrite a run
that has results unless --force, since changing teams mid-run mixes two experiments.

    python tools/rnb/make_injected.py
    RNB_OUT=generated/rnb_vs_gen7_injected python tools/rnb/run_battles.py 4 2
"""
import collections
import json
import os
import random
import shutil
import sys

from make_battle_teams import tid
from paths import STUDY, pokedex, read_results

G = os.path.join(STUDY, "generated")
SRC = os.path.join(G, "rnb_vs_gen7")
KEEP = os.path.join(G, "rnb_vs_gen7_collage", "teams", "smogon")     # the pilotable 78
GEN = [os.path.join(G, "rnb_vs_gen", "teams", "gen"), os.path.join(G, "rnb_vs_gen_trainers", "teams", "gen")]
OUT = os.path.join(G, "rnb_vs_gen7_injected")
K = 2
BST_WINDOW = 30
MAX_USES = 2


def blocks(path):
    return open(path, encoding="utf-8").read().strip().split("\n\n")


def main():
    if read_results(os.path.join(OUT, "results.ndjson")) and "--force" not in sys.argv:
        sys.exit("%s already has results; not rebuilding its teams (use --force)" % OUT)
    dex = pokedex()
    mega = {(tid(e["baseSpecies"]), e["requiredItem"]): e for e in dex.values()
            if e.get("requiredItem") and e.get("forme", "").startswith(("Mega", "Primal"))}

    def info(b, origin):
        sp, _, item = b.split("\n")[0].partition(" @ ")
        e = dex[tid(sp)]
        m = mega.get((tid(e.get("baseSpecies", e["name"])), item.strip()))
        return {"text": b, "origin": origin, "species": tid(e.get("baseSpecies", e["name"])),
                "mega": m is not None, "bst": sum((m or e)["baseStats"].values())}

    teams = {f: [info(b, f) for b in blocks(os.path.join(SRC, "teams", "smogon", f))]
             for f in sorted(os.listdir(KEEP))}
    gen = [info(b, os.path.basename(d.split(os.sep + "teams")[0]).replace("rnb_vs_", "") + "/" + f)
           for d in GEN for f in sorted(os.listdir(d)) for b in blocks(os.path.join(d, f))]
    uses = collections.Counter()
    rng = random.Random(11)
    manifest = {}
    for t, mons in teams.items():
        done = []
        for _ in range(K):
            cands = []
            for i, m in enumerate(mons):
                if i in [d["slot"] for d in done]:
                    continue
                rest = [x for j, x in enumerate(mons) if j != i]
                for gi, g in enumerate(gen):
                    if (uses[gi] < MAX_USES and abs(g["bst"] - m["bst"]) <= BST_WINDOW
                            and g["species"] not in {x["species"] for x in rest}
                            and not (g["mega"] and any(x["mega"] for x in rest))):
                        cands.append((uses[gi], rng.random(), i, gi))
            if not cands:
                break
            _, _, i, gi = min(cands)
            done.append({"slot": i, "replaced": mons[i]["text"], "generator_set": gen[gi]["text"],
                         "from": gen[gi]["origin"], "bst_change": gen[gi]["bst"] - mons[i]["bst"]})
            mons[i] = gen[gi]
            uses[gi] += 1
        manifest[t] = done

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(os.path.join(OUT, "teams", "smogon"))
    shutil.copytree(os.path.join(SRC, "teams", "rnb"), os.path.join(OUT, "teams", "rnb"))
    for t, mons in teams.items():
        with open(os.path.join(OUT, "teams", "smogon", t), "w", encoding="utf-8") as fh:
            fh.write("\n\n".join(m["text"] for m in mons) + "\n")
    pairs = [p for p in json.load(open(os.path.join(SRC, "pairs.json"))) if p["opp"] in teams]
    for p in pairs:
        p["opp_bst"] = round(sum(m["bst"] for m in teams[p["opp"]]) / 6)
    with open(os.path.join(OUT, "pairs.json"), "w") as fh:
        json.dump(pairs, fh, indent=1)
    with open(os.path.join(OUT, "injected.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1)
    n = [len(v) for v in manifest.values()]
    print("%d teams, %d pairings; generator sets per team %s; distinct generator sets used %d of %d"
          % (len(teams), len(pairs), dict(collections.Counter(n)), len(uses), len(gen)))


if __name__ == "__main__":
    main()
