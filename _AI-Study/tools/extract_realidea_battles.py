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
import subprocess, re, json, sys, os

DATA = "/mnt/c/Users/kny/Documents/Games/Norm/Realidea V4.1/Data"
TOOLS = "/mnt/c/Users/kny/Documents/Games/Norm/_AI-Study/tools"
sys.path.insert(0, TOOLS)
import marshal_rb

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

re_create = re.compile(r'(p\d)\s*=\s*createPokemon\(\s*("?)([A-Za-z0-9_]+)\2\s*,\s*(\d+|[a-zA-Z_]\w*)')
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
    out = subprocess.run(["strings", "-a", os.path.join(DATA, fn)],
                         capture_output=True, text=True).stdout.splitlines()
    cur = {}   # pN -> mon dict
    for line in out:
        # strip marshal length-prefix garbage before code
        code = re.sub(r'^[^a-zA-Z$]*', '', line)
        mc = re_create.search(code)
        if mc:
            var, _, species, lvl = mc.groups()
            cur[var] = {"species": species, "level": int(lvl) if lvl.isdigit() else lvl}
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

json.dump(battles, open(sys.argv[1], "w"), indent=1, ensure_ascii=False)
print(f"{len(battles)} battles extracted")
sizes = {}
for b in battles: sizes[len(b["party"])] = sizes.get(len(b["party"]), 0) + 1
print("party sizes:", dict(sorted(sizes.items())))
