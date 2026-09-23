#!/usr/bin/env python3
"""Team composition per experiment: offence v defence, roles, type synergy, cores.

The tables in RNB-STUDY.md §10 ("Composition before and after the shuffle"). A set is an
ATTACKER with 3-4 attacking moves or a Choice/Life Orb item, WALL/SUPPORT with at most 1
attack or a defensive item plus recovery and at most 2, IN BETWEEN otherwise. Type
synergy ignores immunity abilities (Levitate etc.). A core pair is two species seen
together on 3+ real gen 7 teams (gen7 OU/Ubers/UU/AG in the dump).

    python tools/rnb/composition.py
"""
import collections
import itertools
import json
import os
import re
import statistics as st
import sys

from paths import STUDY  # noqa: E402
G = os.path.join(STUDY, "generated")
sys.path.insert(0, os.path.join(STUDY, "tools"))
import team_shape as TS  # noqa: E402

tid = lambda s: re.sub(r"[^a-z0-9]", "", s.lower())  # noqa: E731
DEX = json.load(open(os.path.join(G, "rnb", "pokedex.json"), encoding="utf-8"))
SD = json.load(open(os.path.join(G, "showdown_dex.json"), encoding="utf-8"))["gen9"]
MV, CHART = SD["moves"], SD["chart"]
TYPES = [t for t in CHART if t not in ("Stellar",)]
MEGA = {(tid(e["baseSpecies"]), e["requiredItem"]): e for e in DEX.values()
        if e.get("requiredItem") and e.get("forme", "").startswith(("Mega", "Primal"))}
DEF_ITEMS = {"leftovers", "blacksludge", "rockyhelmet", "assaultvest", "eviolite"}
OFF_ITEMS = {"choiceband", "choicespecs", "choicescarf", "lifeorb", "expertbelt"}
RECOVERY = {tid(m) for m in TS.ROLE_MOVES["recovery"]}


def team(path):
    out = []
    for b in open(path, encoding="utf-8").read().strip().split("\n\n"):
        L = b.splitlines()
        sp, _, item = L[0].partition(" @ ")
        e = DEX[tid(sp)]
        e = MEGA.get((tid(e.get("baseSpecies", e["name"])), item.strip()), e)
        moves = [l[2:] for l in L if l.startswith("- ")]
        out.append({"species": tid(DEX[tid(sp)].get("baseSpecies", sp)), "types": e["types"],
                    "item": tid(item), "moves": moves,
                    "attacks": [m for m in moves if MV.get(tid(m), {}).get("category") in ("Physical", "Special")]})
    return out


def kind(m):
    a = len(m["attacks"])
    rec = any(tid(x) in RECOVERY for x in m["moves"])
    if a <= 1 or (m["item"] in DEF_ITEMS and rec and a <= 2):
        return "wall/support"
    if a >= 3 or m["item"] in OFF_ITEMS:
        return "attacker"
    return "in between"


def mult(atk, types):
    x = 1.0
    for t in types:
        c = CHART[t].get(atk, 0)
        x *= {0: 1, 1: 2, 2: 0.5, 3: 0}[c]
    return x


def typing(t):
    blind = holes = 0
    for atk in TYPES:
        ms = [mult(atk, m["types"]) for m in t]
        resist = any(x < 1 for x in ms)
        blind += not resist
        holes += (sum(x > 1 for x in ms) >= 3 and not resist)
    hit = {d for m in t for a in m["attacks"] for d in TYPES
           if mult(MV[tid(a)]["type"], [d]) > 1 and MV[tid(a)].get("bp", 0)}
    return blind, holes, len(hit)


# species pairs seen together on real gen 7 teams (3+ teams)
pair_n = collections.Counter()
for f in ("gen7ou", "gen7ubers", "gen7uu", "gen7anythinggoes"):
    for tm in json.load(open(os.path.join(STUDY, "extracted", "smogon-dump", f + ".json"), encoding="utf-8")):
        sps = sorted({tid(DEX.get(tid(m["species"]), {}).get("baseSpecies", m["species"])) for m in tm.get("data") or []})
        pair_n.update(itertools.combinations(sps, 2))
CORE = {p for p, n in pair_n.items() if n >= 3}

pools = {
    "gen 7 intact": ("rnb_vs_gen7", "smogon"),
    "gen 7 shuffled": ("rnb_vs_gen7_collage", "smogon"),
    "generator gyms": ("rnb_vs_gen", "gen"),
    "generator non-gym": ("rnb_vs_gen_trainers", "gen"),
    "Run & Bun bosses": ("rnb", "rnb"),
}
keep = set(os.listdir(os.path.join(G, "rnb_vs_gen7_collage", "teams", "smogon")))   # pilotable 78
rows = {}
for name, (exp, side) in pools.items():
    d = os.path.join(G, exp, "teams", side)
    files = [f for f in os.listdir(d) if side != "smogon" or f in keep]
    if side == "rnb":
        files = [f for f in files if not f.startswith(("Leader_Tate", "Leader_Liza"))]
    T = [team(os.path.join(d, f)) for f in files]
    k = collections.Counter(kind(m) for t in T for m in t)
    n = sum(k.values())
    roles = collections.defaultdict(list)
    for t in T:
        rc = TS.role_counts([{"moves": m["moves"]} for m in t])
        for r in ("hazards", "removal", "pivot", "recovery", "setup", "status"):
            roles[r].append(rc.get(r, 0) > 0)
    ty = [typing(t) for t in T]
    cores = [sum(tuple(sorted(p)) in CORE for p in itertools.combinations({m["species"] for m in t}, 2)) for t in T]
    rows[name] = (len(T), k, n, roles, ty, cores, T)

print("## Offence v defence (share of sets)")
print("%-18s %5s %9s %11s %13s %14s" % ("", "teams", "attacker", "in between", "wall/support", "def. item"))
for name, (nt, k, n, roles, ty, cores, T) in rows.items():
    di = st.mean(m["item"] in DEF_ITEMS for t in T for m in t)
    print("%-18s %5d %8.0f%% %10.0f%% %12.0f%% %13.0f%%" % (name, nt, 100 * k["attacker"] / n,
          100 * k["in between"] / n, 100 * k["wall/support"] / n, 100 * di))
print("\n## Walls/support sets per team (distribution)")
for name, (nt, k, n, roles, ty, cores, T) in rows.items():
    c = collections.Counter(sum(kind(m) == "wall/support" for m in t) for t in T)
    print("%-18s " % name + "  ".join("%d:%3.0f%%" % (i, 100 * c[i] / nt) for i in range(5)))
print("\n## Roles (share of teams carrying at least one)")
print("%-18s" % "" + "".join("%10s" % r for r in ("hazards", "removal", "pivot", "recovery", "setup", "status")))
for name, (nt, k, n, roles, ty, cores, T) in rows.items():
    print("%-18s" % name + "".join("%9.0f%%" % (100 * st.mean(roles[r])) for r in
                                   ("hazards", "removal", "pivot", "recovery", "setup", "status")))
print("\n## Type synergy / coverage (per team, mean)")
print("%-18s %22s %30s %26s" % ("", "types nobody resists", "holes (3+ weak, no resist)", "types hit super-eff. /18"))
for name, (nt, k, n, roles, ty, cores, T) in rows.items():
    print("%-18s %22.2f %30.2f %26.1f" % (name, st.mean(x[0] for x in ty), st.mean(x[1] for x in ty),
                                         st.mean(x[2] for x in ty)))
print("\n## Cores: species pairs on the team that also appear together on 3+ real gen 7 teams")
for name, (nt, k, n, roles, ty, cores, T) in rows.items():
    print("%-18s mean %.1f of 15 pairs; teams with none %3.0f%%" % (name, st.mean(cores), 100 * st.mean(c == 0 for c in cores)))
