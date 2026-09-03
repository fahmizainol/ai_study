#!/usr/bin/env python3
"""Parsed view of Realidea V4.1's PBS data — shared by the team validator and
the filler generator. Everything a generated team may reference is checked
against these tables, so nothing can be emitted that the game can't resolve.
"""
import os, re
from functools import lru_cache

PBS = "/mnt/c/Users/kny/Documents/Games/Norm/Realidea V4.1/PBS"

NATURES = ["HARDY","LONELY","BRAVE","ADAMANT","NAUGHTY","BOLD","DOCILE","RELAXED",
           "IMPISH","LAX","TIMID","HASTY","SERIOUS","JOLLY","NAIVE","MODEST",
           "MILD","QUIET","BASHFUL","RASH","CALM","GENTLE","SASSY","CAREFUL","QUIRKY"]

# stat order used by v16 iv=/ev= arrays
STAT_ORDER = ["HP", "ATK", "DEF", "SPD", "SPA", "SPDEF"]


@lru_cache(maxsize=1)
def species():
    """{INTERNALNAME: {types, base_stats(list of 6, PBS order), bst, abilities,
    hidden_ability, learnset [(level, MOVE)...], evolutions [(child, method, param)]}}"""
    out, cur = {}, None
    for line in open(os.path.join(PBS, "pokemon.txt"), encoding="utf-8", errors="replace"):
        line = line.strip()
        if line.startswith("InternalName="):
            cur = line.split("=", 1)[1]
            out[cur] = {"types": [], "abilities": [], "hidden_ability": None,
                        "learnset": [], "evolutions": [], "base_stats": [], "bst": 0}
        elif cur is None:
            continue
        elif line.startswith("Type1=") or line.startswith("Type2="):
            out[cur]["types"].append(line.split("=", 1)[1])
        elif line.startswith("BaseStats="):
            bs = [int(x) for x in line.split("=", 1)[1].split(",")]
            out[cur]["base_stats"] = bs
            out[cur]["bst"] = sum(bs)
        elif line.startswith("Abilities="):
            out[cur]["abilities"] = [a for a in line.split("=", 1)[1].split(",") if a]
        elif line.startswith("HiddenAbility="):
            out[cur]["hidden_ability"] = line.split("=", 1)[1].split(",")[0] or None
        elif line.startswith("Moves="):
            f = line.split("=", 1)[1].split(",")
            out[cur]["learnset"] = [(int(f[i]), f[i+1]) for i in range(0, len(f) - 1, 2)]
        elif line.startswith("Evolutions=") and line != "Evolutions=":
            f = line.split("=", 1)[1].split(",")
            out[cur]["evolutions"] = [tuple(f[i:i+3]) for i in range(0, len(f) - 2, 3)]
    return out


@lru_cache(maxsize=1)
def min_level():
    """{INTERNALNAME: minimum legal level} from Level-method evolution chains.
    Non-level methods (item/trade/happiness...) contribute no floor."""
    sp = species()
    floor = {name: 1 for name in sp}
    for parent, data in sp.items():
        for child, method, param in data["evolutions"]:
            if child not in floor:
                continue
            if method in ("Level", "AttackGreater", "DefenseGreater", "AtkDefEqual",
                          "Silcoon", "Cascoon", "Ninjask", "Shedinja") and param.isdigit():
                floor[child] = max(floor[child], int(param))
    # second pass for 3-stage lines (floor of stage3 >= floor of stage2)
    for parent, data in sp.items():
        for child, method, param in data["evolutions"]:
            if child in floor and floor[parent] > floor[child]:
                floor[child] = floor[parent]
    return floor


@lru_cache(maxsize=1)
def moves():
    """{INTERNALNAME: {type, category, power, accuracy}}"""
    out = {}
    for line in open(os.path.join(PBS, "moves.txt"), encoding="utf-8", errors="replace"):
        f = line.split(",")
        if len(f) > 8 and f[0].isdigit():
            out[f[1]] = {"type": f[5], "category": f[6],
                         "power": int(f[4]) if f[4].isdigit() else 0,
                         "accuracy": int(f[7]) if f[7].isdigit() else 0}
    return out


@lru_cache(maxsize=1)
def items():
    out = set()
    for line in open(os.path.join(PBS, "items.txt"), encoding="utf-8", errors="replace"):
        f = line.split(",")
        if len(f) > 2 and f[0].isdigit():
            out.add(f[1])
    return out


@lru_cache(maxsize=1)
def tm_moves():
    """{MOVE: set(species that can learn it via TM/tutor list)}"""
    out, cur = {}, None
    for line in open(os.path.join(PBS, "tm.txt"), encoding="utf-8", errors="replace"):
        line = line.strip()
        m = re.match(r'\[([A-Z0-9]+)\]$', line)
        if m:
            cur = m.group(1); out[cur] = set()
        elif cur and line:
            out[cur].update(x for x in line.split(",") if x)
    return out


def learnable(sp_name, move, level, slack=0):
    """How can sp_name know `move` at `level`? Returns one of:
    'levelup', 'levelup+N' (over by N but within slack... always returned when over),
    'tm', None."""
    sp = species().get(sp_name)
    if not sp:
        return None
    lvls = [lv for lv, mv in sp["learnset"] if mv == move]
    if lvls and min(lvls) <= level:
        return "levelup"
    if sp_name in tm_moves().get(move, ()):
        return "tm"
    if lvls:
        return f"levelup+{min(lvls) - level}"
    return None
