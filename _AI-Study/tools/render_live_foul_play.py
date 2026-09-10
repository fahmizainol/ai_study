#!/usr/bin/env python3
"""Render live Foul Play decision NDJSON into one readable text file per battle."""

import argparse
import contextlib
import json
from pathlib import Path

import render_realidea_battle as base


def load(path):
    rows = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.strip():
            rows.append(json.loads(line))
    return rows


def party(view, side):
    return [entry.get("species") or "?"
            for entry in (((view or {}).get("matrix") or {}).get(side) or [])]


def render(entries):
    first = entries[0]
    view = first.get("view") or {}
    own, foe = party(view, "own"), party(view, "foe")
    print("Foul Play live battle %s  single   %d decisions   [portable %s]" % (
        first.get("battle_id"), len(entries), first.get("portable_version", "?")))
    print("  opponent: %s" % ", ".join(foe))
    print("  FOUL PLAY: %s" % ", ".join(own))
    print("=" * 104)
    for entry in entries:
        view = entry.get("view") or {}
        if entry.get("type") == "switch":
            action = "switch -> %s" % (entry.get("switch_species") or "slot%s" % entry.get("slot"))
        else:
            action = entry.get("move_id") or "move%s" % entry.get("slot")
            if entry.get("target") is not None:
                action += " @%s" % entry["target"]
        print("\nTurn %-3s actor %s   %-28s score %s" % (
            entry.get("turn"), entry.get("actor"), action,
            base.score_column(entry.get("score") or 0)))
        line = base.board(view)
        if line:
            print("    board   : %s" % line)
        base.render_foe(entry, view)
        base.render_view(view)
        base.render_candidates(entry)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args()
    rows = load(args.input)
    groups = {}
    for row in rows:
        groups.setdefault(row.get("battle_id") or "unknown", []).append(row)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    base.SHOW_CELLS = True
    for battle_id, entries in groups.items():
        output = out_dir / ("foul_play_%s.txt" % battle_id)
        with output.open("w", encoding="utf-8", newline="\n") as handle:
            with contextlib.redirect_stdout(handle):
                render(entries)
        print(output)


if __name__ == "__main__":
    main()
