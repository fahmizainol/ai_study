#!/usr/bin/env python3
"""Mechanical validator for generated Realidea trainer teams (TEAM-DESIGN.md §6.5).

Input: a JSON file — list of team objects:
  { "id": str, "type_id": int, "class": str, "name": str,
    "orig_ace_level": int, "cheat_tier": bool (default false),
    "trainer_items": [ITEM...],
    "mons": [ { "species": S, "level": int | ["balanceo", offset], "moves": [M x1-4],
                "item": ITEM|null, "ability": 0|1|2, "nature": N,
                "iv": int|[6 ints], "ev": [6 ints] } ] }

Exit 0 = all teams pass. Every failure is printed as  team_id: [RULE] detail.
Warnings (don't fail): levelup+N within slack, non-level evolution methods.

Usage: validate_team.py teams.json [--slack 2] [--early]
"""
import json, sys
import realidea_data as D


def _stated_floor():
    """{INTERNALNAME: the lowest level this species can possibly exist at}.

    The half of min_level() the dex states outright. min_level() also carries an
    INFERRED floor for every evolution whose method names no level -- a stone, a
    friendship, a held item -- estimated from the level-method edges of the same
    shape. That estimate is good, and it is still an estimate, which is exactly the
    line realidea_data.evo_stated() draws: "a Water Stone at level 31 is a shopping
    trip, an Araquanid at level 19 is impossible."

    Only the impossible half belongs in a hard error. Chained the same way, so a
    species is held to a floor only where every edge that reaches it states one; a
    single inferred hop anywhere up the line makes the whole floor an estimate.
    """
    sp, edges, stated = D.species(), D.evo_floor(), D.evo_stated()
    out = {name: 1 for name in sp}
    changed = True
    while changed:                      # a fixpoint: a line is only as settled as
        changed = False                 # its base is -- see realidea_data._stage()
        for (parent, child), lvl in edges.items():
            if (parent, child) not in stated:
                continue
            want = max(out[parent], lvl)
            if want > out[child]:
                out[child], changed = want, True
    return out


def validate(teams, slack=2, early=False):
    """`early` is generate_bosses.EARLY_MOVES: the build was told it may keep a move
    the species has not reached yet. Then a levelup+N move is a CHOICE, not a defect,
    and refusing to ship it makes the knob unusable -- it exists precisely so a
    fangame can field precocious bosses. The SPECIES half of the gate is untouched:
    a move the mon could never learn stays a hard error however early the build is
    allowed to be, which is the same line the EVO rule draws between a level the dex
    states and one it merely implies."""
    errs, warns = [], []
    sp, floor, mv, it = D.species(), D.min_level(), D.moves(), D.items()
    hard = _stated_floor()
    for t in teams:
        tid = t.get("id", "?")
        # A record may declare the knob it was BUILT under, which outranks the
        # caller's default: a file on disk knows something the reader does not, and
        # the alternative is a team that installs cleanly and is then refused by the
        # next thing to read it.
        early_t = early or bool((t.get("design") or {}).get("early_moves"))
        def err(rule, msg): errs.append(f"{tid}: [{rule}] {msg}")
        def warn(rule, msg): warns.append(f"{tid}: [{rule}] {msg}")
        if t.get("battle_format", "inherit") not in ("inherit", "single", "double"):
            err("FORMAT", f"unknown battle format {t.get('battle_format')!r}")
        cheat = t.get("cheat_tier", False)
        for item in t.get("trainer_items", []):
            if item not in it: err("TITEM", f"trainer item {item} not in items.txt")
        if not 1 <= len(t.get("mons", [])) <= 6:
            err("SIZE", f"{len(t.get('mons', []))} mons")
        # The engine is happy to run the same species twice and the player just sees
        # a trainer with two of them, so nothing downstream catches this -- a boss
        # shipped with Mamoswine in it twice and only tripped SIZE, and a six-mon
        # team carrying a duplicate would have passed outright. Engine-resolved
        # starter slots are exempt: they are method names, not species, and a fight
        # can legitimately hold more than one.
        seen = [m.get("species") for m in t.get("mons", [])
                if isinstance(m.get("species"), str) and not m["species"].islower()]
        for name in sorted({n for n in seen if seen.count(n) > 1}):
            err("DUPLICATE", f"{name} appears {seen.count(name)} times")
        # 1-based, because every place a person can SEE this team counts from one:
        # the card lists mon 1..6 and the party in game is slots 1..6. Numbering from
        # zero here sent anyone reading "mon5 TYRANTRUM" to the fifth row, which held
        # something else entirely, and the sixth row is where the Tyrantrum was.
        for i, m in enumerate(t.get("mons", []), 1):
            tag = f"mon{i} {m.get('species')}"
            # A lowercase species is an engine-resolved slot, not a species: the
            # rival fights fill their starter slot from the Pokes Rivales script at
            # runtime (owenpoke2, albapoke1...). It has no fixed species and no
            # moveset to check, so there is nothing here to validate.
            if m.get("species", "")[:1].islower():
                warn("DYNAMIC", f"{tag}: engine-resolved slot, not checked"); continue
            s = sp.get(m.get("species"))
            if not s:
                err("SPECIES", f"{tag}: not in pokemon.txt"); continue
            lvl = m.get("level")
            if isinstance(lvl, list):
                # A scaled level, ['balanceo', offset]: the engine resolves it from
                # the player's party at battle time, so the runtime number is not
                # knowable here. Check the level the set was DESIGNED against, which
                # is what its legality was chosen at. (The game already instantiates
                # its own scaled teams the same way -- PokeBattle_Pokemon.new takes
                # any level, so a Mamoswine at 20 is built, not rejected.)
                lvl = m.get("design_level")
            if not isinstance(lvl, int) or not 1 <= lvl <= 100:
                err("LEVEL", f"{tag}: level {lvl!r}"); continue
            if lvl < floor[m["species"]]:
                # Three cases, and only one of them is a bug. Below a floor the dex
                # STATES, a generated mon cannot exist and that is ours to fix. Below
                # an inferred floor it merely arrives early -- the player bought the
                # stone sooner than most lines suggest -- which is a judgement call
                # about the fight, not an illegal team, so it is said and not failed.
                # A kept original is the dev's own roster choice either way.
                if m.get("kept"):
                    warn("EVO", f"{tag}: level {lvl} < evolution floor "
                                f"{floor[m['species']]} (kept original)")
                elif lvl < hard[m["species"]]:
                    err("EVO", f"{tag}: level {lvl} < evolution floor "
                               f"{hard[m['species']]}")
                else:
                    warn("EVO", f"{tag}: level {lvl} < evolution floor "
                                f"{floor[m['species']]} (estimated — this line names "
                                f"no level, so it is early, not impossible)")
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
                    if over <= slack:
                        warn("LEARN", f"{tag}: {mo} is +{over} over level (leader privilege)")
                    elif early_t:
                        warn("LEARN", f"{tag}: {mo} is learnset lv{lvl + over}, "
                                      f"+{over} early (EARLY_MOVES is on)")
                    else:
                        err("LEARN", f"{tag}: {mo} is learnset lv{lvl+over}, over slack +{slack}")
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
    # Match the build: a file written with EARLY_MOVES on is meant to carry moves
    # the species has not reached, so checking it without this reports a defect the
    # author chose. The studio passes the knob straight through.
    early = "--early" in args
    if early:
        args.remove("--early")
    teams = []
    for path in args:
        teams += json.load(open(path))
    errs, warns = validate(teams, slack, early)
    for w in warns: print("WARN", w)
    for e in errs: print("FAIL", e)
    print(f"{len(teams)} teams: {len(errs)} errors, {len(warns)} warnings")
    sys.exit(1 if errs else 0)
