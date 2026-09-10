#!/usr/bin/env python3
"""Where the PLAYER can obtain each held item in Realidea V4.1.

Boss teams should not be built out of gear the player has no way to hold, so the
generator needs to know what is actually reachable. Five routes exist, and checking
only the obvious one is how you get a wrong answer: Leftovers looks unobtainable if
you scan script calls alone, but wild Snorlax and Munchlax carry it at the 50% common
rate.

  map event   pbItemBall / pbReceiveItem / pbHiddenItem / pbAddItem / pbStoreItem
  mart        pbPokemonMart item lists
  wild held   WildItemCommon/Uncommon/Rare in pokemon.txt (50% / 5% / 1%)
  pickup      the Pickup ability tables in PField_Field.rb, indexed by holder level
  berry plant berry-patch events, which name their berry in the event name

Matching is done on the ARGUMENTS of an acquisition call, never on the surrounding
page text: an event page that both gives an item and creates an opponent holding a
mega stone would otherwise credit the player with the stone. That false positive
made four phantom megastone sources appear before the match was tightened.

Usage: extract_item_sources.py [out.json]     (default generated/realidea_item_sources.json)
"""
import collections
import glob
import json
import os
import re
import sys

import realidea_data as D
from extract_rxdata import sections
from marshal_rb import load

HERE = os.path.dirname(os.path.abspath(__file__))
STUDY = os.path.dirname(HERE)
GAME = os.path.join(os.path.dirname(os.path.dirname(D.PBS)), "Realidea V4.1", "Data")
if not os.path.isdir(GAME):
    GAME = os.path.join(os.path.dirname(D.PBS), "Data")

ACQUIRE = ("pbItemBall", "pbReceiveItem", "pbHiddenItem", "pbAddItem", "pbStoreItem",
           "pbPokemonMart")
CALL = re.compile(r"(" + "|".join(ACQUIRE) + r")\s*\(([^)]*)\)", re.S)
NAME = re.compile(r"\b([A-Z][A-Z0-9]{2,})\b")


def _map_names():
    mi = load(os.path.join(GAME, "MapInfos.rxdata"))
    out = {}
    for k, v in mi.items():
        # marshal strings round-trip as latin1 so byte payloads survive; map names are
        # really utf-8 and have to be re-decoded or they read as "Ciudad AÌ�gata"
        out[int(k)] = v["@name"].encode("latin1").decode("utf-8", "replace")
    return out


def _commands(map_path):
    """Flatten one map into its event-command dicts and its event objects."""
    cmds, events = [], []
    def walk(o):
        if isinstance(o, dict):
            if "@code" in o:
                cmds.append(o)
            if "@pages" in o and "@name" in o:
                events.append(o)
            for v in o.values():
                walk(v)
        elif isinstance(o, (list, tuple)):
            for v in o:
                walk(v)
    walk(load(map_path))
    return cmds, events


def scan():
    names = _map_names()
    route = collections.defaultdict(set)

    for path in sorted(glob.glob(os.path.join(GAME, "Map[0-9][0-9][0-9].rxdata"))):
        mid = int(os.path.basename(path)[3:6])
        where = names.get(mid, f"map {mid}")
        try:
            cmds, events = _commands(path)
        except Exception as exc:
            print(f"skip {os.path.basename(path)}: {exc}", file=sys.stderr)
            continue
        for e in events:
            tag = (e.get("@name") or "").upper().replace(" ", "")
            if tag.endswith("BERRY"):
                route[tag].add(f"berry plant @ {where}")
        # 355 starts a script block and 655 continues it; join before matching so a
        # mart list split across ten lines is still one call
        buf = []
        for c in cmds + [{"@code": 0}]:
            if c["@code"] in (355, 655):
                p = c.get("@parameters") or []
                buf.append(p[0] if p and isinstance(p[0], str) else "")
                continue
            for fn, args in CALL.findall("".join(buf)):
                kind = "mart" if fn == "pbPokemonMart" else "map event"
                for item in NAME.findall(args):
                    route[item].add(f"{kind} @ {where}")
            buf = []

    rate = {"Common": "50%", "Uncommon": "5%", "Rare": "1%"}
    for line in open(os.path.join(D.PBS, "pokemon.txt"),
                     encoding="utf-8-sig", errors="replace"):
        if line.startswith("WildItem"):
            kind = line.split("=", 1)[0].replace("WildItem", "")
            for item in line.split("=", 1)[1].strip().split(","):
                if item:
                    route[item].add(f"wild held ({rate.get(kind, kind)})")

    # the Pickup tables live in compiled Ruby, so read them out of Scripts.rxdata
    # rather than keeping a copy of a game script in this repo
    block = ""
    for _name, src in sections(os.path.join(GAME, "Scripts.rxdata")):
        if "def Kernel.pbPickup" in src:
            block = src[src.index("def Kernel.pbPickup"):][:2500]
            break
    for tag, pat in (("pickup", r"pickupList=pbDynamicItemList\((.*?)\)"),
                     ("pickup rare", r"pickupListRare=pbDynamicItemList\((.*?)\)")):
        m = re.search(pat, block, re.S)
        if not m:
            print(f"note: {tag} table not found — those routes omitted", file=sys.stderr)
            continue
        entries = [x.strip().lstrip(":") for x in m.group(1).split(",") if x.strip()]
        for i, item in enumerate(entries):
            # pbPickup indexes both lists by (level-1)/10, so an item's position IS
            # its level requirement -- Leftovers at index 9 means a lv91+ holder.
            route[item].add(f"{tag} (holder lv{max(1, i * 10 + 1)}+)")

    known = D.items()
    return {k: sorted(v) for k, v in sorted(route.items()) if k in known}


if __name__ == "__main__":
    out = (sys.argv[1] if len(sys.argv) > 1
           else os.path.join(STUDY, "generated", "realidea_item_sources.json"))
    data = scan()
    json.dump(data, open(out, "w"), indent=1, ensure_ascii=False)
    unreachable = sorted(set(D.items()) - set(data))
    print(f"{len(data)} obtainable items -> {out}")
    print(f"{len(unreachable)} items in items.txt with no player route")
