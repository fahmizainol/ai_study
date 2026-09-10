#!/usr/bin/env python3
"""Extract dynamically-built trainer battles from Realidea map events.

Realidea V4.1 builds nearly all trainer teams inline in map-event scripts:
    p0 = createPokemon("SPECIES", level)
    p0.item = (PBItems::X)         # rare
    party = [p0, p1, ...]
    trainer = createTrainer(typeid, "Name", party)
    result = customTrainerBattle(trainer, "...")
Marshal stores each script line as a plain string in file order, so we scan
`strings -a` output per map and reconstruct battles.
"""
import argparse, re, json, sys, os

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import marshal_rb

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output")
parser.add_argument("--game", default=os.path.join(TOOLS, "..", "..", "Realidea"),
                    help="Realidea game directory (default: workspace Realidea folder)")
args = parser.parse_args()
DATA = os.path.join(os.path.abspath(args.game), "Data")


def printable_strings(path):
    """Yield the ASCII runs used by RPG Maker event script commands.

    The prior extractor called GNU strings from one developer's WSL install. Event
    Ruby is stored verbatim inside the Marshal file, so scanning printable runs is
    equivalent for the identifiers, levels, and calls parsed below and works on
    Windows without an external executable.
    """
    data = open(path, "rb").read()
    return [match.group(0).decode("ascii")
            for match in re.finditer(rb"[\x09\x20-\x7e]{4,}", data)]

tt = marshal_rb.load(os.path.join(DATA, "trainertypes.dat"))
TYPE_NAMES = {i: (r[1] if r and len(r) > 1 else None) for i, r in enumerate(tt)}

# map names (MapInfos may fail on odd types; fall back to id only)
MAP_NAMES = {}
try:
    mi = marshal_rb.load(os.path.join(DATA, "MapInfos.rxdata"))
    for k, v in mi.items():
        name = v.get("@name") if isinstance(v, dict) else None
        MAP_NAMES[int(k)] = name
except Exception as e:
    print("MapInfos parse failed:", e, file=sys.stderr)

# the third argument is an optional explicit moveset; bosses nearly always pass one,
# and dropping it silently rebuilds them on default level-up moves.
#
# The level is either a literal or an expression in `balanceo` (Entrenadores.rb:
# `pbBalancedLevel($Trainer.party) - 1`), which scales the fight to the player's
# party. The trailing offset is part of the design -- Camus is balanceo+1 and Silver
# is balanceo-2 -- so it is captured with the token, not thrown away.
re_create = re.compile(r'(p\d)\s*=\s*createPokemon\(\s*("?)([A-Za-z0-9_]+)\2\s*,\s*'
                       r'(\d+|[a-zA-Z_]\w*(?:\s*[-+]\s*\d+)?)\s*(?:,\s*\[([^\]]*)\])?')
re_attr   = re.compile(r'(p\d)\.(item|ev|name|setAbility|formNoCall)\s*=?\s*\(?\s*(?:PBItems::)?([A-Za-z0-9_,\[\] "]+?)\)?;?\s*$')
re_party  = re.compile(r'party\s*=\s*\[([^\]]*)\]')
re_trainer= re.compile(r'createTrainer\(\s*(\d+)\s*,\s*"([^"]*)"')

battles = []
for fn in sorted(os.listdir(DATA)):
    m = re.match(r'Map(\d+)\.rxdata$', fn)
    src = None
    if m: src = int(m.group(1))
    elif fn == "CommonEvents.rxdata": src = "common"
    else: continue
    out = printable_strings(os.path.join(DATA, fn))
    cur = {}   # pN -> mon dict
    for line in out:
        # strip marshal length-prefix garbage before code
        code = re.sub(r'^[^a-zA-Z$]*', '', line)
        mc = re_create.search(code)
        if mc:
            var, _, species, lvl, moves = mc.groups()
            lvl = re.sub(r"\s+", "", lvl)
            mon = {"species": species, "level": int(lvl) if lvl.isdigit() else lvl}
            if moves:
                mon["moves"] = re.findall(r':([A-Z0-9]+)', moves)
            cur[var] = mon
            continue
        ma = re_attr.search(code)
        if ma and ma.group(1) in cur:
            cur[ma.group(1)][ma.group(2)] = ma.group(3).strip().rstrip(');')
            continue
        mt = re_trainer.search(code)
        if mt:
            tid, name = int(mt.group(1)), mt.group(2)
            party = [cur[k] for k in sorted(cur)]
            battles.append({"map": src, "map_name": MAP_NAMES.get(src) if src != "common" else "CommonEvents",
                            "type_id": tid, "type": TYPE_NAMES.get(tid), "name": name,
                            "party": party})
            cur = {}

with open(args.output, "w", encoding="utf-8", newline="\n") as output:
    json.dump(battles, output, indent=1, ensure_ascii=False)
    output.write("\n")
print(f"{len(battles)} battles extracted")
sizes = {}
for b in battles: sizes[len(b["party"])] = sizes.get(len(b["party"]), 0) + 1
print("party sizes:", dict(sorted(sizes.items())))
