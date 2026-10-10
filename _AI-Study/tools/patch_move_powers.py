#!/usr/bin/env python3
"""Install Realidea's custom move powers without recompiling unrelated game data.

Usage: python tools/patch_move_powers.py --game "../Realidea V4.1"
Knock Off is 65 BP; Return and Frustration are always 100 BP.
All anchors are checked before writing. Original files are backed up once.
"""
import argparse
from pathlib import Path
import zlib

import pack_rxdata as PR
from marshal_rb import load

POWERS = {35: (b"KNOCKOFF", 65), 331: (b"FRUSTRATION", 100),
          337: (b"RETURN", 100)}


def replace_once(source, old, new):
    if new in source and old not in source:
        return source
    if source.count(old) != 1:
        raise ValueError(f"Expected exactly one script anchor: {old!r}")
    return source.replace(old, new)


def patch_scripts(game):
    path = game / "Data/Scripts.rxdata"
    raw, count, spans = PR.scan(str(path))
    entries = load(str(path))
    replacements = {}
    for index, entry in enumerate(entries):
        name = entry[1]
        if name not in ("PokeBattle_MoveEffects", "PokeBattle_AI"):
            continue
        # Work on original bytes: legacy Spanish text is not uniformly UTF-8.
        source = zlib.decompress(entry[2].encode("latin1"))
        original = source
        for expression in (b"[(attacker.happiness*2/5).floor,1].max",
                           b"[((255-attacker.happiness)*2/5).floor,1].max"):
            prefix = b"return " if name == "PokeBattle_MoveEffects" else b"basedamage="
            if prefix + expression in source:
                source = replace_once(source, prefix + expression, prefix + b"100")
        if name == "PokeBattle_MoveEffects":
            for move in (b"089", b"08A"):
                anchor = b"class PokeBattle_Move_" + move + b" < PokeBattle_Move"
                body = source.split(anchor, 1)[1].split(b"\nend", 1)[0]
                if b"return 100" not in body or b"happiness" in body:
                    raise ValueError("Fixed-power move handler was not patched")
            start = source.index(b"class PokeBattle_Move_0F0 < PokeBattle_Move")
            end = source.index(b"\nend", start)
            body = source[start:end]
            old = b"if USENEWBATTLEMECHANICS &&\n       !@battle.pbIsUnlosableItem(opponent,opponent.item)"
            new = b"if USENEWBATTLEMECHANICS && opponent.item!=0 &&\n       !@battle.pbIsUnlosableItem(opponent,opponent.item)"
            body = replace_once(body, old, new)
            source = source[:start] + body + source[end:]
        if source != original:
            replacements[index] = PR.make_elem(name, source)
    if not {"PokeBattle_MoveEffects", "PokeBattle_AI"}.issubset({e[1] for e in entries}):
        raise ValueError("Required battle scripts missing")
    return path, PR.build(raw, spans, replace=replacements)


def patch_text(raw):
    result = []
    seen = set()
    for line in raw.splitlines(keepends=True):
        fields = line.split(b",", 6)
        if len(fields) > 6 and fields[0].isdigit() and int(fields[0]) in POWERS:
            move_id = int(fields[0])
            symbol, power = POWERS[move_id]
            if fields[1] != symbol:
                raise ValueError(f"Unexpected move ID {move_id}")
            fields[4] = str(power).encode()
            line = b",".join(fields)
            seen.add(move_id)
        result.append(line)
    if seen != set(POWERS):
        raise ValueError("Move text table is missing required entries")
    return b"".join(result)


def install(game):
    writes = [patch_scripts(game)]
    path = game / "Data/moves.dat"
    data = bytearray(path.read_bytes())
    if len(data) % 14:
        raise ValueError("Unexpected compiled move record size")
    for move_id, (_, power) in POWERS.items():
        data[move_id * 14 + 2] = power
    writes.append((path, bytes(data)))
    for relative in ("PBS/moves.txt", "Data/moves.txt"):
        path = game / relative
        if path.exists():
            writes.append((path, patch_text(path.read_bytes())))
    for path, new in writes:
        old = path.read_bytes()
        if old == new:
            continue
        backup = path.with_name(path.name + ".pre-custom-move-powers.bak")
        if not backup.exists():
            backup.write_bytes(old)
        path.write_bytes(new)
        print(f"Updated {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    install(parser.parse_args().game.resolve())
