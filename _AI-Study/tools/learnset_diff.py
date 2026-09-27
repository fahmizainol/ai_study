#!/usr/bin/env python3
"""What another Essentials game's learnsets would ADD to Realidea's, species by species.

Realidea's pokemon.txt carries gen 5 egg lists and a 171-move tm.txt (TMs plus part of
the gen 7 tutor list), so a published gen 7 set often names a move the game cannot
teach (Weavile's Icicle Crash, RNB-STUDY.md §10). Reborn's PBS carries the USUM lists.
This reads both, keeps only what is ADDITIVE and legal in Realidea (a species Realidea
has, a move its moves.txt has), and checks every addition against Showdown's gen 7
learnset data so a mod's own edits can be told from vanilla.

    python3 tools/learnset_diff.py REF_PBS_DIR [REALIDEA_PBS_DIR]
        -> generated/learnset_diff.json, summary on stdout

Nothing is written into either game. The merge itself is a separate, deliberate step.
"""
import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "..", "generated")
SHOWDOWN = os.path.join(GEN, "showdown_learnsets_gen7.json")


def tid(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def read(path):
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        return [ln.rstrip("\r\n") for ln in fh]


def species(pbs):
    """{INTERNAL: {"level": {moves}, "egg": {moves}, "name": ..}} from pokemon.txt."""
    out, cur = {}, None
    for ln in read(os.path.join(pbs, "pokemon.txt")):
        if ln.startswith("InternalName="):
            cur = ln.split("=", 1)[1].strip()
            out[cur] = {"level": set(), "egg": set()}
        elif cur and ln.startswith("Moves="):
            parts = [p.strip() for p in ln.split("=", 1)[1].split(",") if p.strip()]
            out[cur]["level"] = {parts[i] for i in range(1, len(parts), 2)}
        elif cur and ln.startswith("EggMoves="):
            out[cur]["egg"] = {p.strip() for p in ln.split("=", 1)[1].split(",") if p.strip()}
    return out


def moves(pbs):
    """Internal names in moves.txt (one CSV row per move, name in column 2)."""
    out = set()
    for ln in read(os.path.join(pbs, "moves.txt")):
        parts = ln.split(",")
        if len(parts) > 2 and parts[1].strip():
            out.add(parts[1].strip())
    return out


def machines(pbs):
    """{MOVE: {species}} from tm.txt ([MOVE] sections, one CSV line of species each)."""
    out, cur = {}, None
    for ln in read(os.path.join(pbs, "tm.txt")):
        ln = ln.strip()
        if ln.startswith("[") and ln.endswith("]"):
            cur = ln[1:-1]
            out.setdefault(cur, set())
        elif cur and ln and not ln.startswith("#"):
            out[cur] |= {p.strip() for p in ln.split(",") if p.strip()}
    return out


def by_species(machine_table):
    out = collections.defaultdict(set)
    for mv, sps in machine_table.items():
        for sp in sps:
            out[sp].add(mv)
    return out


def main(argv):
    ref = argv[1]
    real = argv[2] if len(argv) > 2 else os.environ.get("REALIDEA_PBS")
    if not real:
        sys.exit("give the Realidea PBS dir or set REALIDEA_PBS")
    R, X = species(real), species(ref)
    rm, xm = moves(real), moves(ref)
    rt, xt = by_species(machines(real)), by_species(machines(ref))
    vanilla = json.load(open(SHOWDOWN, encoding="utf-8")) if os.path.exists(SHOWDOWN) else {}

    def gen7(sp, mv):
        """Showdown's gen 7 sources for this move on this species or its line ('' = none)."""
        e = vanilla.get(tid(sp))
        seen = set()
        while e and tid(sp) not in seen:
            src = e["moves"].get(tid(mv))
            if src:
                return src
            seen.add(tid(sp))
            e = vanilla.get(e.get("prevo") or "")
        return ""

    shared = [sp for sp in R if sp in X]
    ref_only = [sp for sp in X if sp not in R]
    missing_moves = collections.Counter()
    rows, tot = {}, collections.Counter()
    for sp in shared:
        add = {"egg": sorted(X[sp]["egg"] - R[sp]["egg"] - R[sp]["level"]),
               "level": sorted(X[sp]["level"] - R[sp]["level"]),
               "machine": sorted(xt.get(sp, set()) - rt.get(sp, set()) - R[sp]["level"])}
        row = {}
        for kind, lst in add.items():
            keep, dropped = [], []
            for mv in lst:
                if mv not in rm:
                    missing_moves[mv] += 1
                    dropped.append(mv)
                    continue
                keep.append({"move": mv, "gen7": gen7(sp, mv)})
            if keep:
                row[kind] = keep
                tot[kind] += len(keep)
                tot[kind + "_vanilla"] += sum(1 for k in keep if k["gen7"])
            if dropped:
                row.setdefault("not_in_realidea_moves", []).extend(dropped)
        if row:
            rows[sp] = row
    out = {"ref": os.path.abspath(ref), "realidea": os.path.abspath(real),
           "species_shared": len(shared), "species_ref_only": sorted(ref_only),
           "species_realidea_only": sorted(sp for sp in R if sp not in X),
           "moves_ref_not_in_realidea": dict(missing_moves.most_common()),
           "totals": dict(tot), "species": rows}
    os.makedirs(GEN, exist_ok=True)
    with open(os.path.join(GEN, "learnset_diff.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)

    print(f"species: {len(shared)} shared, {len(ref_only)} only in the reference, "
          f"{len(out['species_realidea_only'])} only in Realidea")
    print(f"moves the reference uses that Realidea's moves.txt lacks: {len(missing_moves)} "
          f"({sum(missing_moves.values())} learnset entries) -- top: "
          + ", ".join(f"{m} x{n}" for m, n in missing_moves.most_common(8)))
    print("additions Realidea could take (species x move), and how many Showdown's gen 7 data confirms:")
    for kind in ("egg", "level", "machine"):
        n, v = tot[kind], tot[kind + "_vanilla"]
        touched = sum(1 for r in rows.values() if kind in r)
        print(f"  {kind:<8} {n:5d} on {touched:3d} species   vanilla gen 7: {v} ({100 * v / n if n else 0:.0f}%)")
    print(f"species touched: {len(rows)} of {len(shared)}")
    # the reference's own inventions: additions no gen 7 source knows, by species
    own = collections.Counter()
    for sp, r in rows.items():
        for kind in ("egg", "level", "machine"):
            own[sp] += sum(1 for k in r.get(kind, ()) if not k["gen7"])
    print("most non-vanilla additions on one species: "
          + ", ".join(f"{sp} {n}" for sp, n in own.most_common(8) if n))
    for sp in ("SNEASEL", "WEAVILE", "MARILL", "AZUMARILL", "GALLADE", "PIDGEOT"):
        if sp in rows:
            r = rows[sp]
            print(f"  {sp}: " + "; ".join(
                f"{k} +" + ",".join(x["move"] + ("" if x["gen7"] else "?") for x in r[k])
                for k in ("egg", "level", "machine") if k in r))
    return out


if __name__ == "__main__":
    main(sys.argv)
