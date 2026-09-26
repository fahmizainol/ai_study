#!/usr/bin/env python3
"""How strong is the vanilla core? The dev's own (kept) Pokemon against the generated picks,
and each kept species on its own, from the battles played on this machine.

A kept Pokemon is on the team in every arm (the generator never replaces it), so across the
100 ms arms each has 48-72 slot-battles on its own fight: enough to rank them by measured
contribution -- KOs and damage dealt for an attacker, turns on the field and faint rate for
a wall -- instead of by tier, which misjudges them (RNB-STUDY.md §10: Electrode ZU 0.88
KO a battle, Hippowdon UU 0.19). This is the evidence a KEEP_MEASURED test in the
generator would read.

Which slots are kept is read from the generator's own JSON for each arm (the `kept` flag),
which lives outside the repo: the arm builds gen_fixes.py wrote, in GEN_ARMS
(default ~/.cache/gen-arms), named as JSON maps them. That map is specific to how the arms
were built on this machine; another machine rebuilds them with gen_fixes.py and points
GEN_ARMS at the result.

    REALIDEA_PBS=<game>/PBS [GEN_ARMS=dir] python3 tools/rnb/core_strength.py
    REALIDEA_PBS=<game>/PBS python3 tools/rnb/core_strength.py --write [ARM ...]

--write writes generated/core_strength.json, the table generate_bosses.KEEP_MEASURED reads:
per fight id, per kept species (Essentials internal name), battles, KOs and % of an
opposing HP bar dealt per battle, % fainted, turns on the field, and the set kind it was
most often built as. Only the arms named are pooled (default: every arm in JSON), so a
table can be built from one search depth alone.
"""
import collections
import json
import os
import sys

import composition as C
import deck_slots as D
from paths import TOOLS

sys.path.insert(0, TOOLS)
import smogon_corpus as SC  # noqa: E402

tid = C.tid
GEN_ARMS = os.environ.get("GEN_ARMS", os.path.expanduser("~/.cache/gen-arms"))
# results folder -> the gen_fixes.py arm whose gyms.json / trainers.json built it
JSON = {"rnb_vs_gen_deckoff": "off", "rnb_vs_gen_theme": "theme", "rnb_vs_gen_tier": "tier",
        "rnb_vs_gen_all": "all", "rnb_vs_gen_choices": "shipped", "rnb_vs_gen_defense": "defense",
        "rnb_vs_gen_trainers_theme": "theme", "rnb_vs_gen_trainers_all": "all",
        "rnb_vs_gen_trainers_choices": "shipped", "rnb_vs_gen_trainers_defense": "defense",
        # the 10 ms baseline (2026-09-27)
        "rnb_vs_gen_defense_10ms": "defense", "rnb_vs_gen_trainers_defense_10ms": "defense",
        "rnb_vs_gen_atk_10ms": "atk", "rnb_vs_gen_trainers_atk_10ms": "atk",
        "rnb_vs_gen_atk_10ms_b": "atk", "rnb_vs_gen_trainers_atk_10ms_b": "atk",
        "rnb_vs_gen_measured_10ms": "measured", "rnb_vs_gen_trainers_measured_10ms": "measured"}
TABLE = os.path.join(TOOLS, "..", "generated", "core_strength.json")


def kept_map(arm):
    """{(team name, species tid): kept?} for one arm, teams named as make_gen_battles names them."""
    src = os.path.join(GEN_ARMS, JSON[arm], "trainers.json" if "trainers" in arm else "gyms.json")
    out, n = {}, collections.Counter()
    for t in json.load(open(src, encoding="utf-8")):
        if "trainers" in arm:
            if any(m["species"].islower() for m in t["mons"]):   # engine-filled starter slot: not played
                continue
            kind = t["id"].split("_", 1)[0]
            n[kind] += 1
            name = "%s%d" % (kind, n[kind])
        else:
            name = t["id"].split("_", 1)[0]
        for m in t["mons"]:
            out[name, tid(m["species"])] = bool(m.get("kept"))
    return out


def fight_ids(arm):
    """{team name: (fight id, {species tid: INTERNAL name})} for the kept mons of one arm."""
    src = os.path.join(GEN_ARMS, JSON[arm], "trainers.json" if "trainers" in arm else "gyms.json")
    out, n = {}, collections.Counter()
    for t in json.load(open(src, encoding="utf-8")):
        if "trainers" in arm:
            if any(m["species"].islower() for m in t["mons"]):
                continue
            kind = t["id"].split("_", 1)[0]
            n[kind] += 1
            name = "%s%d" % (kind, n[kind])
        else:
            name = t["id"].split("_", 1)[0]
        out[name] = (t["id"], {tid(m["species"]): m["species"] for m in t["mons"] if m.get("kept")})
    return out


def write(arms):
    """Pool `arms` into generated/core_strength.json (see the module docstring)."""
    import time
    per, kinds, _record = D.collect()
    acc = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    votes = collections.defaultdict(collections.Counter)
    for arm in arms:
        fmap = fight_ids(arm)
        for (t, sp), c in per[arm].items():
            fid, kept = fmap[t]
            hit = kept.get(sp) or next((v for k, v in kept.items() if k in sp or sp in k), None)
            if not hit:
                continue
            acc[fid][hit].update(c)
            votes[fid, hit][kinds[arm, t][sp]] += c["battles"]
    table = {}
    for fid, mons in acc.items():
        table[fid] = {}
        for sp, c in mons.items():
            n = c["battles"]
            table[fid][sp] = {"battles": n, "kos": round(c["kos"] / n, 3), "dealt": round(c["dealt"] / n, 1),
                              "fainted": round(100 * c["fainted"] / n, 1), "turns": round(c["onfield"] / n, 2),
                              "kind": votes[fid, sp].most_common(1)[0][0]}
    with open(TABLE, "w", encoding="utf-8") as fh:
        json.dump({"written": time.strftime("%Y-%m-%d"), "arms": list(arms),
                   "note": "kept (dev) Pokemon per fight: per-battle KOs, % of an opposing HP bar "
                           "dealt, % fainted, turns on the field, set kind as most often built",
                   "fights": table}, fh, indent=1, sort_keys=True)
    print(TABLE, len(table), "fights,", sum(len(v) for v in table.values()), "kept species")


def agg(rs):
    b = sum(c["battles"] for *_, c in rs) or 1
    return (len(rs), sum(c["kos"] for *_, c in rs) / b, sum(c["dealt"] for *_, c in rs) / b,
            100 * sum(c["fainted"] for *_, c in rs) / b, sum(c["onfield"] for *_, c in rs) / b,
            100 * sum(c["dead"] for *_, c in rs) / b)


def main():
    per, kinds, _record = D.collect()
    rows = []          # (arm, team, species, kept, kind, Counter)
    for arm in JSON:
        km = kept_map(arm)
        for (t, sp), c in per[arm].items():
            if (t, sp) in km:
                kept = km[t, sp]
            else:
                # the exported name differs (a forme); try the base species
                cand = [k for k in km if k[0] == t and (k[1] in sp or sp in k[1])]
                if len(cand) != 1:
                    print("unmatched", arm, t, sp, file=sys.stderr)
                    continue
                kept = km[cand[0]]
            rows.append((arm, t, sp, kept, kinds[arm, t][sp], c))

    print("## kept (dev) v generated slots, all 100 ms arms pooled   slots KO/b dealt% faint% turns dead%")
    for grp in ("gyms", "trainers"):
        for kept in (True, False):
            for kind in D.KINDS:
                rs = [r for r in rows if ("trainers" in r[0]) == (grp == "trainers") and r[3] == kept and r[4] == kind]
                if rs:
                    print("  %-8s %-9s %-13s %4d  %4.2f  %4.0f%%  %4.0f%%  %4.1f  %4.0f%%"
                          % (grp, "kept" if kept else "generated", kind, *agg(rs)))

    print("\n## each kept species, pooled over arms (battles = slot-battles)   KO/b dealt% faint% turns dead%")
    by = collections.defaultdict(list)
    for r in rows:
        if r[3]:
            by[r[1], r[2]].append(r)
    out = []
    for (t, sp), rs in by.items():
        n = sum(c["battles"] for *_, c in rs)
        _k, ko, de, fa, on, dd = agg(rs)
        kind = collections.Counter(r[4] for r in rs).most_common(1)[0][0]
        out.append((ko, t, sp, kind, n, de, fa, on, dd))
    for ko, t, sp, kind, n, de, fa, on, dd in sorted(out):
        name = C.DEX.get(sp, {}).get("name", sp)
        print("  %-8s %-14s %-13s %-5s %3d  %4.2f  %4.0f%%  %4.0f%%  %4.1f  %4.0f%%"
              % (t, name, kind, SC.tier(name), n, ko, de, fa, on, dd))


if __name__ == "__main__":
    if "--write" in sys.argv:
        named = [a for a in sys.argv[1:] if not a.startswith("--")]
        write(named or list(JSON))
    else:
        main()
