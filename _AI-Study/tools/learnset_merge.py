#!/usr/bin/env python3
"""Bring Realidea's learnsets up to gen 7, additively, from Showdown's learnset data.

Realidea's pokemon.txt carries gen 5 egg lists and a 171-move tm.txt, so published gen
7 sets name moves the game cannot teach (Weavile's Icicle Crash; RNB-STUDY.md §10). This
adds what Showdown's gen 7 (USUM) learnsets say a species can learn and Realidea's files
do not: level-up moves at their USUM level, egg moves on the base stage, and TM / tutor
compatibility in tm.txt. It never removes anything, never adds a move that is not already
defined in Realidea's moves.txt, and skips a small exclusion list (moves this engine does
not run yet). Fakemon and species Showdown does not know are left exactly as they are.

    python3 tools/learnset_merge.py [REALIDEA_PBS_DIR] [--with-aurora-veil]
        -> generated/learnset_merge/pokemon.txt, tm.txt, report.md, additions.json

--with-aurora-veil also hands out Aurora Veil; only once patch_aurora_veil.py's bundle is
installed, since the shipped engine crashes on the move.

The originals are not touched. Copy the two files into the game's PBS and recompile
(debug mode) as a separate, deliberate step.
"""
import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "..", "generated")
SHOWDOWN = os.path.join(GEN, "showdown_learnsets_gen7.json")
OUT = os.path.join(GEN, "learnset_merge")

# Moves the merge must not hand out. AURORAVEIL: only the setter exists in this build's
# scripts (no PBEffects constant, no damage hook) -- a separate engine patch. POWERTRIP:
# Realidea defines it with function code 0, a plain attack. The last three have no
# PokeBattle_Move_ class at all in the scripts.
EXCLUDE = {"AURORAVEIL", "POWERTRIP", "BEAKBLAST", "REVELATIONDANCE", "SOLARBLADE"}
# Showdown source kinds taken: level-up, egg, tutor, machine. Not event (S), virtual
# console (V) or dream world (D).
KINDS = {"L", "E", "T", "M"}
# Showdown move ids whose Realidea spelling differs from a plain squash of the name.
MOVE_ALIAS = {"visegrip": "VICEGRIP", "feintattack": "FAINTATTACK", "highjumpkick": "HIJUMPKICK",
              "smellingsalts": "SMELLINGSALT", "softboiled": "SOFTBOILED", "selfdestruct": "SELFDESTRUCT",
              "thunderpunch": "THUNDERPUNCH", "thundershock": "THUNDERSHOCK", "solarbeam": "SOLARBEAM",
              "dynamicpunch": "DYNAMICPUNCH", "extremespeed": "EXTREMESPEED", "ancientpower": "ANCIENTPOWER",
              "doubleslap": "DOUBLESLAP", "sandattack": "SANDATTACK", "bubblebeam": "BUBBLEBEAM",
              "poisonpowder": "POISONPOWDER", "featherdance": "FEATHERDANCE", "grasswhistle": "GRASSWHISTLE",
              "smokescreen": "SMOKESCREEN", "vicegrip": "VICEGRIP", "hijumpkick": "HIJUMPKICK"}


def tid(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def read_lines(path):
    raw = open(path, "rb").read()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw[3:].decode("utf-8", "replace") if bom else raw.decode("utf-8", "replace")
    crlf = "\r\n" in text
    return text.split("\r\n" if crlf else "\n"), bom, crlf


def write_lines(path, lines, bom, crlf):
    text = ("\r\n" if crlf else "\n").join(lines)
    with open(path, "wb") as fh:
        if bom:
            fh.write(b"\xef\xbb\xbf")
        fh.write(text.encode("utf-8"))


def realidea_moves(pbs):
    """{showdown id: REALIDEA_INTERNAL} for every move in moves.txt."""
    out = {}
    for ln, _, _ in [read_lines(os.path.join(pbs, "moves.txt"))]:
        for row in ln:
            p = row.split(",")
            if len(p) > 2 and p[1].strip():
                out[tid(p[1].strip())] = p[1].strip()
    for sid, internal in MOVE_ALIAS.items():
        if internal in out.values():
            out.setdefault(sid, internal)
    return out


def showdown_id(internal, sd):
    """Realidea internal name -> Showdown species id, or None (fakemon, unknown forme)."""
    t = tid(internal)
    if t in sd:
        return t
    if internal == "NIDORANfE":
        return "nidoranf"
    if internal == "NIDORANmA":
        return "nidoranm"
    if internal.startswith("A") and tid(internal[1:]) + "alola" in sd:   # ARAICHU -> raichualola
        return tid(internal[1:]) + "alola"
    return None


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    pbs = args[0] if args else os.environ.get("REALIDEA_PBS")
    if "--with-aurora-veil" in argv:
        EXCLUDE.discard("AURORAVEIL")
    if not pbs:
        sys.exit("give the Realidea PBS dir or set REALIDEA_PBS")
    sd = json.load(open(SHOWDOWN, encoding="utf-8"))
    mv_map = realidea_moves(pbs)
    unknown_moves = collections.Counter()

    def internal_move(sid):
        m = mv_map.get(sid)
        if not m:
            unknown_moves[sid] += 1
        return m

    # ---- pokemon.txt -------------------------------------------------------------
    lines, bom, crlf = read_lines(os.path.join(pbs, "pokemon.txt"))
    species_at = {}          # INTERNAL -> index of its InternalName= line
    for i, ln in enumerate(lines):
        if ln.startswith("InternalName="):
            species_at[ln.split("=", 1)[1].strip()] = i
    order = sorted(species_at, key=species_at.get)
    bounds = {sp: (species_at[sp], species_at[order[k + 1]] if k + 1 < len(order) else len(lines))
              for k, sp in enumerate(order)}

    def field(sp, key):
        a, b = bounds[sp]
        for i in range(a, b):
            if lines[i].startswith(key + "="):
                return i
        return None

    additions = {}
    tot = collections.Counter()
    known = {}               # INTERNAL -> set of moves it has by level or egg (before the merge)
    for sp in order:
        sid = showdown_id(sp, sd)
        mi, ei = field(sp, "Moves"), field(sp, "EggMoves")
        level = []
        if mi is not None:
            parts = [p.strip() for p in lines[mi].split("=", 1)[1].split(",") if p.strip()]
            level = [(int(parts[i]), parts[i + 1]) for i in range(0, len(parts) - 1, 2)]
        egg = [p.strip() for p in lines[ei].split("=", 1)[1].split(",") if p.strip()] if ei is not None else []
        known[sp] = {m for _, m in level} | set(egg)
        if not sid:
            continue
        entry = sd[sid]
        add_level, add_egg = [], []
        for move_id, srcs in entry["moves"].items():
            kinds = {s[1] for s in srcs}
            if not kinds & KINDS:
                continue
            mv = internal_move(move_id)
            if not mv or mv in EXCLUDE or mv in known[sp]:
                continue
            if "L" in kinds:
                lv = min(int(s[2:]) for s in srcs if s[1] == "L" and s[2:].isdigit())
                add_level.append((max(lv, 1), mv))
            elif "E" in kinds and not entry["prevo"]:
                add_egg.append(mv)
        if add_level:
            merged = sorted(level + add_level, key=lambda x: x[0])   # stable: existing first at a level
            lines[mi] = "Moves=" + ",".join(f"{lv},{m}" for lv, m in merged)
            tot["level"] += len(add_level)
        if add_egg:
            new_egg = egg + sorted(add_egg)
            if ei is not None:
                lines[ei] = "EggMoves=" + ",".join(new_egg)
            else:
                lines.insert(mi + 1, "EggMoves=" + ",".join(new_egg))
                # indices after this point shift by one
                species_at = {k: (v + 1 if v > mi else v) for k, v in species_at.items()}
                bounds = {k: (a + (a > mi), b + (b > mi)) for k, (a, b) in bounds.items()}
            tot["egg"] += len(add_egg)
        if add_level or add_egg:
            additions[sp] = {"level": [f"{lv},{m}" for lv, m in sorted(add_level)], "egg": sorted(add_egg)}
            known[sp] |= {m for _, m in add_level} | set(add_egg)
    os.makedirs(OUT, exist_ok=True)
    write_lines(os.path.join(OUT, "pokemon.txt"), lines, bom, crlf)

    # ---- tm.txt ------------------------------------------------------------------
    tlines, tbom, tcrlf = read_lines(os.path.join(pbs, "tm.txt"))
    section_at = {}
    for i, ln in enumerate(tlines):
        if ln.startswith("[") and ln.rstrip().endswith("]"):
            section_at[ln.strip()[1:-1]] = i
    machine = collections.defaultdict(set)      # MOVE -> species already listed
    for mv, i in section_at.items():
        j = i + 1
        while j < len(tlines) and (not tlines[j].strip() or tlines[j].startswith("#")):
            j += 1
        if j < len(tlines) and not tlines[j].startswith("["):
            machine[mv] = {p.strip() for p in tlines[j].split(",") if p.strip()}
    new_by_move = collections.defaultdict(list)
    for sp in order:
        sid = showdown_id(sp, sd)
        if not sid:
            continue
        for move_id, srcs in sd[sid]["moves"].items():
            kinds = {s[1] for s in srcs}
            if not kinds & {"T", "M"} or "L" in kinds:
                continue
            mv = internal_move(move_id)
            if not mv or mv in EXCLUDE or mv in known[sp] or sp in machine.get(mv, ()):
                continue
            new_by_move[mv].append(sp)
            additions.setdefault(sp, {"level": [], "egg": []}).setdefault("machine", []).append(mv)
            tot["machine"] += 1
    new_sections = []
    for mv, sps in sorted(new_by_move.items()):
        if mv in section_at:
            i = section_at[mv]
            j = i + 1
            while j < len(tlines) and (not tlines[j].strip() or tlines[j].startswith("#")):
                j += 1
            if j < len(tlines) and not tlines[j].startswith("["):
                tlines[j] = tlines[j].rstrip(",") + "," + ",".join(sps)
            else:
                tlines.insert(i + 1, ",".join(sps))
                section_at = {k: (v + 1 if v > i else v) for k, v in section_at.items()}
        else:
            new_sections.append(mv)
            tot["new tm.txt sections"] += 1
    if new_sections:
        tlines += ["#================================================================",
                   "# Tutor moves (gen 7 / USUM learnsets, tools/learnset_merge.py)",
                   "#================================================================"]
        for mv in new_sections:
            tlines += [f"[{mv}]", ",".join(new_by_move[mv])]
        if tlines[-1] != "":
            tlines.append("")
    write_lines(os.path.join(OUT, "tm.txt"), tlines, tbom, tcrlf)

    # ---- report ------------------------------------------------------------------
    unmatched = [sp for sp in order if not showdown_id(sp, sd)]
    touched = sum(1 for v in additions.values() if v["level"] or v["egg"] or v.get("machine"))
    with open(os.path.join(OUT, "additions.json"), "w", encoding="utf-8") as fh:
        json.dump({"totals": dict(tot), "excluded_moves": sorted(EXCLUDE),
                   "species_unmatched": unmatched, "moves_unknown_to_realidea": dict(unknown_moves.most_common()),
                   "species": additions}, fh, indent=1, sort_keys=True)
    rep = [f"# Gen 7 learnset merge for Realidea (Showdown USUM data, additive)", "",
           f"- species touched: {touched} of {len(order)} ({len(unmatched)} not matched to Showdown: fakemon, unknown formes)",
           f"- level-up moves added: {tot['level']}", f"- egg moves added (base stage only): {tot['egg']}",
           f"- TM / tutor compatibilities added: {tot['machine']} ({tot['new tm.txt sections']} new tm.txt sections)",
           f"- excluded moves: {', '.join(sorted(EXCLUDE))}",
           f"- Showdown moves Realidea does not define (skipped): {len(unknown_moves)} -- "
           + ", ".join(f"{m} x{n}" for m, n in unknown_moves.most_common(12)), "",
           "| species | level-up | egg | TM / tutor |", "|---|---|---|---|"]
    for sp in order:
        a = additions.get(sp)
        if not a:
            continue
        rep.append(f"| {sp} | {' '.join(a['level'])} | {' '.join(a['egg'])} | {' '.join(a.get('machine', []))} |")
    with open(os.path.join(OUT, "report.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(rep) + "\n")
    print("\n".join(rep[:8]))
    print(f"unmatched species: {unmatched}")
    print(f"-> {OUT}")


if __name__ == "__main__":
    main(sys.argv)
