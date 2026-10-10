#!/usr/bin/env python3
"""Add Heavy-Duty Boots to Realidea without recompiling unrelated PBS data.

Run with --game PATH. Requires Ruby (native, or Ubuntu-24.04 in WSL).
Existing files are backed up once; repeated installation is safe.
"""
import argparse
import re
import shutil
import struct
import subprocess
import zlib
from pathlib import Path

import pack_rxdata as PR
from marshal_rb import load
from patch_move_powers import replace_once

ITEM_ID = 743
NAME = "Heavy-Duty Boots"
DESCRIPTION = "Protects the holder from entry hazards when switching into battle."


def patch_hazards(source):
    anchors = [
        b"if pkmn.pbOwnSide.effects[PBEffects::Spikes]>0 && !pkmn.isAirborne?(moldbreaker)",
        b"if pkmn.pbOwnSide.effects[PBEffects::StealthRock] && !pkmn.isFainted?",
        b"elsif pkmn.pbCanPoisonSpikes?(moldbreaker)",
        b"if pkmn.pbOwnSide.effects[PBEffects::StickyWeb] && !pkmn.isFainted? &&",
    ]
    for old in anchors:
        # Keep Poison-type absorption of Toxic Spikes, including while wearing Boots.
        suffix = b" && !pkmn.hasWorkingItem(:HEAVYDUTYBOOTS)"
        new = old[:-3] + suffix + b" &&" if old.endswith(b" &&") else old + suffix
        source = replace_once(source, old, new) if new not in source else source
    return source


def bundle(path, section, transform):
    raw, _, spans = PR.scan(str(path))
    entries = load(str(path))
    matches = [(i, e) for i, e in enumerate(entries) if e[1] == section]
    if len(matches) != 1:
        raise ValueError(f"Expected one {section} section")
    i, entry = matches[0]
    source = zlib.decompress(entry[2].encode("latin1"))
    patched = transform(source)
    return raw if patched == source else PR.build(raw, spans, replace={i: PR.make_elem(section, patched)})


def constants(source):
    if b"HEAVYDUTYBOOTS=743" in source:
        return source
    source = replace_once(source, b"MAPA=742", b"MAPA=742\r\nHEAVYDUTYBOOTS=743")
    source = replace_once(source, b"return 730", b"return 731")
    return replace_once(source, b"return 742", b"return 743")


def icon_fallback(source):
    old = b'      bitmapFileName=sprintf("Graphics/Icons/item%03d",item)'
    new = old + (b'\n      if isConst?(item,PBItems,:HEAVYDUTYBOOTS) && !pbResolveBitmap(bitmapFileName)'
                 b'\n        bitmapFileName="Graphics/Icons/item000"\n      end')
    return source if new in source else replace_once(source, old, new)


def varint(value):
    result = bytearray()
    while value >= 128:
        result.append((value & 127) | 128)
        value >>= 7
    return bytes(result + bytes([value]))


def record(fields):
    return b"".join(b"i" + varint(f) if isinstance(f, int) else
                    b'"' + varint(len(f.encode())) + f.encode() for f in fields)


def items(raw):
    count = struct.unpack_from("<I", raw)[0] // 8
    payload = record([ITEM_ID, NAME, NAME, 1, 3000, DESCRIPTION, 0, 0, 0, 0])
    records = []
    for i in range(count):
        offset, size = struct.unpack_from("<II", raw, i * 8)
        records.append(raw[offset:offset + size])
    existing = [r for r in records if r.startswith(b"i" + varint(ITEM_ID))]
    if existing:
        if existing != [payload]:
            raise ValueError("Item ID 743 is already occupied by a different item")
        return raw
    records.append(payload)
    offset = len(records) * 8
    index = bytearray()
    for r in records:
        index += struct.pack("<II", offset, len(r))
        offset += len(r)
    return bytes(index) + b"".join(records)


def messages(path):
    # Ruby preserves all existing strings, encodings and object links in this table.
    helper = Path(__file__).with_name("add_heavy_duty_boots_messages.rb")
    output = path.with_name(path.name + ".boots.tmp")
    if shutil.which("ruby"):
        command = ["ruby", str(helper), str(path), str(output)]
    else:
        def linux(p):
            p = str(p.resolve()).replace("\\", "/")
            return "/mnt/" + p[0].lower() + p[2:]
        command = ["wsl", "-d", "Ubuntu-24.04", "--", "ruby", linux(helper), linux(path), linux(output)]
    try:
        subprocess.run(command, check=True)
        return output.read_bytes()
    finally:
        output.unlink(missing_ok=True)


def install(game):
    writes = []
    for filename, section, transform in [
        ("Constants.rxdata", "PBItems", constants),
        ("Scripts.rxdata", "PokeBattle_Battle", patch_hazards),
    ]:
        path = game / "Data" / filename
        data = bundle(path, section, transform)
        if filename == "Scripts.rxdata":
            # Install the matching shop catalogue in the same operation.
            path_tmp = game / "Data" / "Scripts.boots.tmp"
            try:
                path_tmp.write_bytes(data)
                service = Path(__file__).parents[1] / "adapters/realidea/Player_Services.rb"
                data = bundle(path_tmp, "Player_Services", lambda _: service.read_bytes())
                path_tmp.write_bytes(data)
                data = bundle(path_tmp, "PSystem_Utilities", icon_fallback)
            finally:
                path_tmp.unlink(missing_ok=True)
        writes.append((path, data))
    path = game / "Data/items.dat"
    writes.append((path, items(path.read_bytes())))
    path = game / "Data/messages.dat"
    writes.append((path, messages(path)))
    for relative in ("PBS/items.txt", "Data/items.txt"):
        path = game / relative
        if path.exists():
            raw = path.read_bytes()
            if b",HEAVYDUTYBOOTS," not in raw:
                if re.search(rb"(?m)^743,", raw):
                    raise ValueError("PBS item ID 743 is occupied")
                raw = raw.rstrip(b"\r\n") + (f'\r\n743,HEAVYDUTYBOOTS,{NAME},{NAME},1,3000,"{DESCRIPTION}",0,0,0,\r\n').encode()
            writes.append((path, raw))
    for path, data in writes:
        original = path.read_bytes()
        if original == data:
            continue
        backup = path.with_name(path.name + ".pre-heavy-duty-boots.bak")
        if not backup.exists():
            backup.write_bytes(original)
        PR.write_atomic(str(path), data)
        print(f"Updated {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    install(parser.parse_args().game.resolve())
