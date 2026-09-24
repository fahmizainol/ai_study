#!/usr/bin/env python3
"""Each injected generator set against the real set it replaced, from the battle logs.

make_injected.py swapped 2 generator sets into every gen 7 team; injected.json records
which real set each one replaced. Here, per slot: KOs per battle, share of battles it
fainted, turns on the field -- the generator set in the injected run v the real set in
the intact run, same team, same bosses -- split by what kind of set each is
(composition.kind: attacker / in between / wall-support).

    python tools/rnb/injected_sets.py
"""
import collections
import json
import os
import sys

import composition as C
from paths import STUDY

sys.argv = [sys.argv[0], "x"]            # read_battles.main reads argv[1]; set per call
import read_battles as R  # noqa: E402

G = os.path.join(STUDY, "generated")


def per_slot(exp):
    sys.argv[1] = os.path.join(G, exp)
    per, _ = R.main()
    return per


def species_of(text):
    return R.tid(text.split("\n")[0].split(" @ ")[0])


def kind_of(text):
    path = os.path.join(os.environ.get("TEMP", "."), "_one_set.txt")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text + "\n")
    return C.kind(C.team(path)[0])


def main():
    inj = per_slot("rnb_vs_gen7_injected")
    intact = per_slot("rnb_vs_gen7")
    manifest = json.load(open(os.path.join(G, "rnb_vs_gen7_injected", "injected.json"), encoding="utf-8"))
    agg = collections.defaultdict(lambda: collections.Counter())
    for team, swaps in manifest.items():
        for s in swaps:
            new, old = inj.get((team, species_of(s["generator_set"]))), intact.get((team, species_of(s["replaced"])))
            if not new or not old or not new["battles"] or not old["battles"]:
                continue
            for label, c, text in (("generator set", new, s["generator_set"]), ("real set it replaced", old, s["replaced"])):
                for key in (label, "%s | %s" % (label, kind_of(text))):
                    a = agg[key]
                    a["slots"] += 1
                    a["battles"] += c["battles"]
                    a["kos"] += c["kos"]
                    a["fainted"] += c["fainted"]
                    a["onfield"] += c["onfield"]
    print("%-44s %6s %8s %8s %9s %9s" % ("", "slots", "battles", "KOs/bt", "fainted", "turns in"))
    for k in sorted(agg):
        a = agg[k]
        print("%-44s %6d %8d %8.2f %8.0f%% %9.1f" % (k, a["slots"], a["battles"], a["kos"] / a["battles"],
                                                    100 * a["fainted"] / a["battles"], a["onfield"] / a["battles"]))


if __name__ == "__main__":
    main()
