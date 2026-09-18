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
    """Internal names AS THE BRIDGE SENDS THEM. The adapter upcases every constant
    name (constant_key), so PBS's NIDORANfE reaches the sidecar as NIDORANFE; an
    audit that reads the file's own spelling audits a string nothing ever emits."""
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    return {n.upper() for n in re.findall(r"^InternalName=(\w+)", text, re.M)}


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
    """(alias, structural) for an unknown name; (None, False) if genuinely custom.

    Structural means the name follows a known convention and can be trusted. A merely
    FUZZY match must be read before it is believed: DRIFBLIMF sits one letter from
    DRIFBLIM and is a different Pokemon -- Ghost/Fire with its own statline -- so
    acting on the resemblance would map custom content onto a real species. Custom
    content SHOULD be unmappable; that is not a defect.
    """
    if name in NIDORAN:
        return (NIDORAN[name], True) if NIDORAN[name] in pool else (None, False)
    if name.startswith("A") and name[1:] + "ALOLA" in pool:
        return name[1:] + "ALOLA", True
    hit = difflib.get_close_matches(name, pool, n=1, cutoff=0.82)
    return (hit[0], False) if hit else (None, False)


def main():
    ids = json.loads(fps.IDS_FILE.read_text())
    report = []

    # Ask the SIDECAR what it would emit, rather than reimplementing its aliasing.
    # A copy of the rules drifts from the rules: the first version of this audit
    # applied SPECIES_ALIASES by hand and so could not see the regional-form rule
    # that lives inside species_id, and reported eighteen drops that were fixed.
    resolvers = {
        "items": lambda n, pr: fps.named("items", n, ids, pr, "NONE"),
        "abilities": lambda n, pr: fps.named("abilities", n, ids, pr, "NONE"),
        "moves": lambda n, pr: fps.move_id({"id": n}, ids, pr),
        "pokemon": lambda n, pr: fps.species_id({"species": n}, ids, pr),
    }
    universe = {
        "items": set(held_items()),
        "abilities": pbs_column(GAME / "PBS/abilities.txt", 1),
        "moves": pbs_column(GAME / "PBS/moves.txt", 1),
        "pokemon": pbs_species(GAME / "PBS/pokemon.txt"),
    }

    for kind, resolve in resolvers.items():
        present = universe[kind]
        missing = []
        for name in sorted(present):
            problems = set()
            resolve(name, problems)
            if problems:
                missing.append(name)
        report.append((kind, len(present), missing))

    print("=" * 72)
    print("A. REALIDEA CONTENT THE ENGINE DOES NOT KNOW (silently becomes NONE)")
    print("=" * 72)
    for kind, total, missing in report:
        print(f"\n{kind}: {len(missing)} of {total} unknown")
        for name in missing:
            match, structural = near(name, ids[kind])
            if match and structural:
                note = f"-> alias to {match}"
            elif match:
                note = f"-> VERIFY: looks like {match}, but read the entry first"
            else:
                note = "(no near match: custom content)"
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
