#!/usr/bin/env python3
"""Audit every id the Realidea->poke-engine bridge can emit against what the engine knows.

Two silent failure modes live between the game and the search, and neither shows up
in a win rate:

  A. WE EMIT IT, THE ENGINE DOESN'T KNOW IT. The sidecar maps the name to NONE and
     logs a problem. Cheap to find here, before a battle stumbles into it, because
     the game's whole content list is on disk. Measured examples: BERRYJUICE and
     LIGHTCLAY, 95 decisions across two sessions.

  C. THE ENGINE MODELS IT AND WE HAVE NO ROW AT ALL. This one is SILENT BY
     CONSTRUCTION -- a mechanic that is never exported never produces a warning, so
     no amount of log reading or extra battles will surface it. The only way to see
     it is to compare the two tables. TWOTURN was the A-shaped half of exactly this
     story; the Protect variants are candidates for the C-shaped half.

The sidecar's own alias tables are imported rather than copied, so a rename there
cannot silently make this audit lie.
"""

import difflib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import foul_play_sidecar as fps

STUDY = Path(__file__).resolve().parents[1]
GAME = STUDY.parent / "Realidea V4.1"


def pbs_column(path, index):
    """Internal names out of a comma-delimited PBS file (items/abilities/moves)."""
    out = set()
    for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split(",")
        if len(parts) > index and parts[0].strip().isdigit():
            out.add(parts[index].strip().upper())
    return out


def pbs_species(path):
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    return set(re.findall(r"^InternalName=(\w+)", text, re.M))


def held_items():
    """Items actually WORN in a battle, with where each was seen.

    PBS lists 730 items and 543 are unknown to the engine, but that number is
    meaningless: it counts Bicycle and Antidote, which nothing ever holds. Only an
    item on a body can reach the search, so the audit is worth no more than its
    universe -- the same trap that made a gen 5 pool "prove" Belly Drum was safe.
    """
    seen = {}
    bosses = STUDY / "generated" / "teams_bosses_gyms.json"
    if bosses.exists():
        for team in json.loads(bosses.read_text()):
            for mon in team.get("mons") or []:
                if mon.get("item"):
                    seen.setdefault(mon["item"].upper(), set()).add("boss teams")
    log = GAME / "Data" / "ai_foulplay_battles.ndjson"
    if log.exists():
        for line in log.read_text(errors="replace").splitlines():
            if not line.strip():
                continue
            view = json.loads(line).get("view") or {}
            for item in [view.get("item")] + [t.get("item") for t in view.get("targets") or []]:
                if item:
                    seen.setdefault(str(item).upper(), set()).add("live battles")
    return seen


# Realidea gives a regional form its own species entry rather than a forme index, so
# the name carries the region as a PREFIX where poke-engine carries it as a SUFFIX.
# Nearest-string is actively WRONG here: it reads ANINETALES as NINETALES, mapping
# Ice/Fairy onto Fire. Structure first, fuzz only as a fallback.
NIDORAN = {"NIDORANfE": "NIDORANF", "NIDORANmA": "NIDORANM"}


def near(name, pool):
    """The alias an unknown name should map to, or None if it is genuinely custom.

    Custom content SHOULD be unmappable -- a fakemon with no near match is not a
    defect, and forcing one onto a real species would be worse than leaving it NONE.
    """
    if name in NIDORAN:
        return NIDORAN[name] if NIDORAN[name] in pool else None
    if name.startswith("A") and name[1:] + "ALOLA" in pool:
        return name[1:] + "ALOLA"
    hit = difflib.get_close_matches(name, pool, n=1, cutoff=0.82)
    return hit[0] if hit else None


def main():
    ids = json.loads(fps.IDS_FILE.read_text())
    report = []

    checks = [
        ("items", set(held_items()), fps.NAMED_ALIASES.get("items", {})),
        ("abilities", pbs_column(GAME / "PBS/abilities.txt", 1), {}),
        ("moves", pbs_column(GAME / "PBS/moves.txt", 1), {}),
        ("pokemon", pbs_species(GAME / "PBS/pokemon.txt"), fps.SPECIES_ALIASES),
    ]

    for kind, present, aliases in checks:
        known = set(ids[kind])
        missing = sorted(n for n in present if aliases.get(n, n) not in known)
        report.append((kind, len(present), missing))

    print("=" * 72)
    print("A. REALIDEA CONTENT THE ENGINE DOES NOT KNOW (silently becomes NONE)")
    print("=" * 72)
    for kind, total, missing in report:
        print(f"\n{kind}: {len(missing)} of {total} unknown")
        for name in missing:
            match = near(name, ids[kind])
            note = f"-> alias to {match}" if match else "(no near match: custom content)"
            print(f"    {name:<18} {note}")

    # C. Volatiles the engine models that the adapter has no row for. The adapter's
    # table is Ruby, so it is read as text; keys resolved at runtime from a move id
    # (test :move) are counted as covered, since every charge volatile is reachable
    # through move_key.
    adapter = (STUDY / "adapters/realidea/Portable_AI_Adapter.rb").read_text(encoding="utf-8")
    table = adapter.split("VOLATILES = [", 1)[1].split("\n    ]", 1)[0]
    fixed = set(re.findall(r'"(\w+)"', table))
    dynamic = set()
    if ":move" in table:
        dynamic = {v for v in ids["volatiles"]
                   if v in pbs_column(GAME / "PBS/moves.txt", 1)}
    side = set(re.findall(r'"(\w+)"', adapter.split("SIDE_CONDITIONS = [", 1)[1]
                          .split("\n    ]", 1)[0]))
    covered = fixed | dynamic | {s.upper() for s in side}
    blind = sorted(v for v in ids["volatiles"] if v not in covered)

    print("\n" + "=" * 72)
    print("C. VOLATILES THE ENGINE MODELS THAT THE ADAPTER NEVER EXPORTS")
    print("   (silent by construction -- no warning is ever logged for these)")
    print("=" * 72)
    reachable = pbs_column(GAME / "PBS/moves.txt", 1) | pbs_column(GAME / "PBS/abilities.txt", 1)
    likely = [v for v in blind if v in reachable]
    print(f"\n{len(blind)} never exported; {len(likely)} share a name with a move or "
          f"ability that EXISTS in Realidea:\n")
    for v in likely:
        print("   ", v)


if __name__ == "__main__":
    main()
