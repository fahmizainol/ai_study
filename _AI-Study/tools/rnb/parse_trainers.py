#!/usr/bin/env python3
"""Parse Run & Bun's trainer-doc sheet into generated/rnb/trainers.json.

Source: the ten story-ordered tabs of the Run & Bun trainer documentation spreadsheet,
exported as CSV into extracted/runandbun/00-*.csv .. 09-*.csv (see the MANIFEST there).
The tab order IS the story order; nothing in a tab says so, it was read off the level
caps in "Mechanic Changes.txt".

Each trainer is a block laid out column-per-Pokemon:

    Name,<trainer>
    Pokémon
    ,<species 1>,<species 2>,...
    Level,...   Held Item,...   Ability,...   Nature,...
    Moves,<move 1 of each>      then up to three unlabelled rows of further moves

A row with only its second cell filled is an AREA header ("Route 104") -- except that a
few such rows are move-tutor notes ("Wood Hammer"), which then get used as an area name.
Harmless: areas are only labels, and tab order carries the progression.

    python3 tools/rnb/parse_trainers.py
"""
import csv
import glob
import json
import os
import re

from paths import SRC, out


def blocks(rows):
    """Yield (area, name, {field: [row cells]}) for every trainer block in one tab."""
    area, i = None, 0
    while i < len(rows):
        r = rows[i] + [""] * 8
        if r[0] == "" and r[1] and not any(r[2:7]):
            area = r[1]
            i += 1
            continue
        if r[0] != "Name":
            i += 1
            continue
        name, fields, last = r[1], {}, None
        j = i + 1
        while j < len(rows) and (rows[j] + [""])[0] != "Name":
            rr = rows[j] + [""] * 8
            # the next area header ends this block
            if rr[0] == "" and rr[1] and not any(rr[2:7]) and j > i + 3 and "Moves" in fields:
                break
            key = rr[0] or (last if last == "Moves" else "")   # unlabelled rows continue Moves
            if rr[0] == "" and j == i + 2:
                key = "Species"                                 # the row under "Pokémon"
            if rr[0]:
                last = rr[0]
            if key and key != "Pokémon":
                fields.setdefault(key, []).append(rr[1:7])
            j += 1
        yield area, name, fields
        i = j


def mons(fields):
    def cell(key, k):
        return (fields.get(key, [[""] * 6])[0][k] or "").strip()

    out_ = []
    for k, sp in enumerate(fields.get("Species", [[""] * 6])[0]):
        if not sp.strip():
            continue
        out_.append({
            "sp": sp.strip(),
            "lv": int(re.sub(r"\D", "", cell("Level", k)) or 0),
            "item": cell("Held Item", k),
            "ability": cell("Ability", k),
            "nature": cell("Nature", k),
            "moves": [m[k].strip() for m in fields.get("Moves", []) if k < len(m) and m[k].strip()],
        })
    return out_


def main():
    trainers = []
    for tab, path in enumerate(sorted(glob.glob(os.path.join(SRC, "[0-9][0-9]-*.csv")))):
        with open(path, encoding="utf-8") as fh:
            rows = list(csv.reader(fh))
        for area, name, fields in blocks(rows):
            trainers.append({"name": name, "area": area, "tab": tab, "mons": mons(fields)})
    os.makedirs(os.path.dirname(out("trainers.json")), exist_ok=True)
    with open(out("trainers.json"), "w", encoding="utf-8") as fh:
        json.dump(trainers, fh, ensure_ascii=False, indent=0)
    print("%d trainers, %d Pokemon -> %s" % (len(trainers), sum(len(t["mons"]) for t in trainers),
                                             out("trainers.json")))


if __name__ == "__main__":
    main()
