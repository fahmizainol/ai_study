#!/usr/bin/env python3
"""Decode Reborn Yang Data/trainers.dat into readable JSON.

trainers.dat: list indexed by trainer_type_id ->
  { trainer_name: { partyId(str): [ [mon arrays], [trainer item ids] ] } }
mon array: [species, level, item, m1, m2, m3, m4, abilIdx, gender, form,
            shadow, natureIdx, iv, happiness, nick, shiny, ball, hp?, ev*6, ...]
partyId >= 100 is the Intense-mode variant of (partyId - 100).
"""
import sys, re, json, os
TOOLS = "/mnt/c/Users/kny/Documents/Games/Norm/_AI-Study/tools"
sys.path.insert(0, TOOLS)
import marshal_rb

RB = "/mnt/c/Users/kny/Documents/Games/Norm/Reborn Yang/Reborn Yang"
PBS = os.path.join(RB, "PBS", "PBS")

moves = {}
for line in open(os.path.join(PBS, "moves.txt"), encoding="utf-8", errors="replace"):
    f = line.split(",")
    if len(f) > 2 and f[0].isdigit(): moves[int(f[0])] = f[1]

items = {}
for line in open(os.path.join(PBS, "items.txt"), encoding="utf-8", errors="replace"):
    f = line.split(",")
    if len(f) > 2 and f[0].isdigit(): items[int(f[0])] = f[1]

species = {}
cur_id = None
for line in open(os.path.join(PBS, "pokemon.txt"), encoding="utf-8", errors="replace"):
    m = re.match(r'\[(\d+)\]', line.strip())
    if m: cur_id = int(m.group(1)); continue
    if line.startswith("InternalName") and cur_id is not None:
        species[cur_id] = line.split("=", 1)[1].strip()

NATURES = ["HARDY","LONELY","BRAVE","ADAMANT","NAUGHTY","BOLD","DOCILE","RELAXED",
           "IMPISH","LAX","TIMID","HASTY","SERIOUS","JOLLY","NAIVE","MODEST",
           "MILD","QUIET","BASHFUL","RASH","CALM","GENTLE","SASSY","CAREFUL","QUIRKY"]

tt = marshal_rb.load(os.path.join(RB, "Data", "trainertypes.dat"))
d = marshal_rb.load(os.path.join(RB, "Data", "trainers.dat"))

out = []
for tid, entry in enumerate(d):
    if not entry: continue
    tname_class = tt[tid][1] if tt[tid] and len(tt[tid]) > 1 else str(tid)
    for name, parties in entry.items():
        for pid, pdata in parties.items():
            mons, titems = pdata[0], pdata[1] if len(pdata) > 1 else []
            party = []
            for a in mons:
                mon = {"species": species.get(a[0], a[0]), "level": a[1],
                       "item": items.get(a[2]) if a[2] else None,
                       "moves": [moves.get(x) for x in a[3:7] if x],
                       "ability_idx": a[7], "form": a[9],
                       "nature": NATURES[a[11]] if isinstance(a[11], int) and a[11] < 25 else a[11],
                       "iv": a[12]}
                evs = a[18:24] if len(a) >= 24 else None
                if evs and any(isinstance(x, int) for x in evs): mon["evs"] = evs
                party.append(mon)
            out.append({"type_id": tid, "class": tname_class, "name": name,
                        "pid": int(pid), "trainer_items": [items.get(x, x) for x in titems],
                        "party": party})

json.dump(out, open(sys.argv[1], "w"), indent=1)
print(len(out), "trainer parties")
