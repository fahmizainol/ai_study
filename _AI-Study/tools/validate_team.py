#!/usr/bin/env python3
"""Mechanical validator for generated Realidea trainer teams (TEAM-DESIGN.md §6.5).

Input: a JSON file — list of team objects:
  { "id": str, "type_id": int, "class": str, "name": str,
    "orig_ace_level": int, "cheat_tier": bool (default false),
    "trainer_items": [ITEM...],
    "mons": [ { "species": S, "level": int, "moves": [M x1-4],
                "item": ITEM|null, "ability": 0|1|2, "nature": N,
                "iv": int|[6 ints], "ev": [6 ints] } ] }

Exit 0 = all teams pass. Every failure is printed as  team_id: [RULE] detail.
Warnings (don't fail): levelup+N within slack, non-level evolution methods.

Usage: validate_team.py teams.json [--slack 2]
"""
import json, sys
import realidea_data as D

def validate(teams, slack=2):
    errs, warns = [], []
    sp, floor, mv, it = D.species(), D.min_level(), D.moves(), D.items()
    for t in teams:
        tid = t.get("id", "?")
        def err(rule, msg): errs.append(f"{tid}: [{rule}] {msg}")
        def warn(rule, msg): warns.append(f"{tid}: [{rule}] {msg}")
        cheat = t.get("cheat_tier", False)
        for item in t.get("trainer_items", []):
            if item not in it: err("TITEM", f"trainer item {item} not in items.txt")
        if not 1 <= len(t.get("mons", [])) <= 6:
            err("SIZE", f"{len(t.get('mons', []))} mons")
        for i, m in enumerate(t.get("mons", [])):
            tag = f"mon{i} {m.get('species')}"
            s = sp.get(m.get("species"))
            if not s:
                err("SPECIES", f"{tag}: not in pokemon.txt"); continue
            lvl = m.get("level")
            if not isinstance(lvl, int) or not 1 <= lvl <= 100:
                err("LEVEL", f"{tag}: level {lvl!r}"); continue
            if lvl < floor[m["species"]]:
                # a kept original species below its level-evo floor is the dev's own
                # roster choice (the engine instantiates it fine) — warn, don't fail.
                # A GENERATED mon under floor is our bug -> hard error.
                if m.get("kept"):
                    warn("EVO", f"{tag}: level {lvl} < evolution floor "
                                f"{floor[m['species']]} (kept original)")
                else:
                    err("EVO", f"{tag}: level {lvl} < evolution floor {floor[m['species']]}")
            mvs = m.get("moves", [])
            if not 1 <= len(mvs) <= 4:
                err("MOVES", f"{tag}: {len(mvs)} moves")
            for mo in mvs:
                if mo not in mv:
                    err("MOVE", f"{tag}: {mo} not in moves.txt"); continue
                how = D.learnable(m["species"], mo, lvl)
                if how is None:
                    err("LEARN", f"{tag}: can't learn {mo} (not learnset/TM)")
                elif how.startswith("levelup+"):
                    over = int(how.split("+")[1])
                    if over > slack:
                        err("LEARN", f"{tag}: {mo} is learnset lv{lvl+over}, over slack +{slack}")
                    else:
                        warn("LEARN", f"{tag}: {mo} is +{over} over level (leader privilege)")
            if m.get("item") is not None and m["item"] not in it:
                err("ITEM", f"{tag}: {m['item']} not in items.txt")
            ab = m.get("ability", 0)
            if ab == 2 and not s["hidden_ability"]:
                err("ABIL", f"{tag}: ability slot 2 but no HiddenAbility")
            elif ab in (0, 1) and ab >= len(s["abilities"]):
                err("ABIL", f"{tag}: ability slot {ab} but only {len(s['abilities'])} listed")
            if m.get("nature") not in D.NATURES:
                err("NATURE", f"{tag}: {m.get('nature')!r}")
            iv = m.get("iv", 31)
            ivs = [iv] * 6 if isinstance(iv, int) else iv
            if len(ivs) != 6 or any(not 0 <= v <= 31 for v in ivs):
                err("IV", f"{tag}: {iv!r}")
            ev = m.get("ev", [0] * 6)
            if len(ev) != 6 or any(not isinstance(v, int) or v < 0 for v in ev):
                err("EV", f"{tag}: {ev!r}")
            elif not cheat:
                if any(v > 252 for v in ev): err("EV", f"{tag}: >252 in a stat, not cheat_tier")
                if sum(ev) > 510: err("EV", f"{tag}: total {sum(ev)} > 510, not cheat_tier")
    return errs, warns

if __name__ == "__main__":
    slack = 2
    args = sys.argv[1:]
    if "--slack" in args:
        i = args.index("--slack"); slack = int(args[i + 1]); del args[i:i + 2]
    teams = []
    for path in args:
        teams += json.load(open(path))
    errs, warns = validate(teams, slack)
    for w in warns: print("WARN", w)
    for e in errs: print("FAIL", e)
    print(f"{len(teams)} teams: {len(errs)} errors, {len(warns)} warnings")
    sys.exit(1 if errs else 0)
