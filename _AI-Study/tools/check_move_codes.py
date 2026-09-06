#!/usr/bin/env python3
"""Guard the Realidea adapter's function-code tables against PBS/moves.txt.

The two adapters carry near-identical tables keyed by Essentials function code, and
the code spaces AGREE below 0x100 and DIVERGE above it: Reborn's 0x139 is a 3/4 drain
while Realidea's is Play Nice, Reborn's 0x13f is a Speed drop while Realidea's is
Flower Shield. A code copied across silently mislabels every move that carries it, and
nothing in the Ruby tests can see it because neither engine is present there.

Two checks, both pure text:

  1. every code in a Realidea table exists in Realidea's PBS -- a table row that names
     a code no move uses is dead, and usually means a Reborn code was pasted in;
  2. every code the two adapters disagree about, reported as a gap to look at by
     hand -- either Reborn names a code Realidea does not (a row pruned by mistake, if
     Realidea's PBS uses it) or both name it with DIFFERENT meanings (0x13B is a SpAtk
     drop in Reborn and a Defense drop here). Advisory only; the divergences above
     0x100 are real and the table comments record them.

Usage:
    python3 tools/check_move_codes.py [--pbs "../Realidea V4.1/PBS/moves.txt"]

Exit 0 when check 1 passes; exit 1 otherwise. Check 2 only ever prints.
"""

import argparse
import re
import sys
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
REALIDEA_ADAPTER = STUDY / "adapters" / "realidea" / "Portable_AI_Adapter.rb"
REBORN_ADAPTER = STUDY / "adapters" / "reborn" / "Portable_AI_Adapter.rb"
DEFAULT_PBS = STUDY.parent / "Realidea V4.1" / "PBS" / "moves.txt"

# Table name -> whether the literal is a Hash (codes are keys) or an Array (elements).
TABLES = {
    "MOVE_EFFECT_CODES": "hash",
    "MOVE_RECOIL_CODES": "hash",
    "MOVE_DRAIN_CODES": "hash",
    "MULTI_HIT_CODES": "array",
    "PARTNER_HEAL_CODES": "array",
}


def table_body(source, name):
    """The literal that follows `NAME = ` in a Ruby source, brackets balanced."""
    match = re.search(r"^\s*%s\s*=\s*([{\[])" % re.escape(name), source, re.M)
    if not match:
        return None
    opening = match.group(1)
    closing = "}" if opening == "{" else "]"
    depth = 0
    start = match.end(1) - 1
    for index in range(start, len(source)):
        char = source[index]
        if char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    return None


def codes_in(source, name, kind):
    body = table_body(source, name)
    if body is None:
        return set()
    # Strip comments so a code mentioned in prose is not read as a table entry.
    body = "\n".join(line.split("#", 1)[0] for line in body.splitlines())
    if kind == "hash":
        return {int(code, 16): value.strip()
                for code, value in re.findall(
                    r"0x([0-9A-Fa-f]+)\s*=>\s*(\[[^\]]*\]|[0-9.]+)", body)}
    return {int(v, 16): None for v in re.findall(r"0x([0-9A-Fa-f]+)", body)}


def pbs_codes(path):
    """function code -> sorted move constant names, from PBS/moves.txt."""
    out = {}
    text = path.read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        line = line.lstrip("﻿").strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(",")
        if len(fields) < 4:
            continue
        raw = fields[3].strip()
        if not re.match(r"^[0-9A-Fa-f]{1,4}$", raw):
            continue
        out.setdefault(int(raw, 16), []).append(fields[1].strip())
    for code in out:
        out[code].sort()
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pbs", default=str(DEFAULT_PBS))
    args = parser.parse_args()

    pbs_path = Path(args.pbs)
    if not pbs_path.exists():
        print("moves.txt not found: %s" % pbs_path, file=sys.stderr)
        return 2

    used = pbs_codes(pbs_path)
    realidea = REALIDEA_ADAPTER.read_text(encoding="utf-8")
    reborn = REBORN_ADAPTER.read_text(encoding="utf-8")

    failures = []
    advisories = []
    for name, kind in TABLES.items():
        ours = codes_in(realidea, name, kind)
        if not ours:
            failures.append("%s: no table found in the Realidea adapter" % name)
            continue
        dead = sorted(code for code in ours if code not in used)
        for code in dead:
            failures.append(
                "%s names 0x%03X, which no move in %s uses"
                % (name, code, pbs_path.name))
        theirs = codes_in(reborn, name, kind)
        for code in sorted(set(theirs) - set(ours)):
            if code in used:
                advisories.append(
                    "%s: Reborn names 0x%03X and Realidea does not, but %s uses it for %s"
                    % (name, code, pbs_path.name, ", ".join(used[code])))
        for code in sorted(set(theirs) & set(ours)):
            if theirs[code] is not None and theirs[code] != ours[code]:
                advisories.append(
                    "%s: 0x%03X is %s in Reborn and %s here (%s)"
                    % (name, code, theirs[code], ours[code],
                       ", ".join(used.get(code, ["unused"]))))
        print("%-20s %3d codes, %3d live" % (name, len(ours), len(ours) - len(dead)))

    for line in advisories:
        print("advisory: " + line)
    for line in failures:
        print("FAIL: " + line, file=sys.stderr)
    if failures:
        return 1
    print("all Realidea function-code table entries exist in %s" % pbs_path.name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
