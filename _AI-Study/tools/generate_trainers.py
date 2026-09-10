#!/usr/bin/env python3
"""Named-trainer generator: the rivals and the other recurring bosses who are not
gym leaders (TEAM-DESIGN.md §6.5 lever 1).

Same machinery as the gym bosses, four differences:

  no theme      A rival has no type identity to build around, so the 4-of-6 theme
                rule has nothing to bind to. Their identity is their own roster --
                Owen's Eevee line, Alba's Beldum line, Teresa's Braixen line -- which
                is preserved by keeping every dev-chosen species and only re-equipping
                it, exactly as the KEEP-ORIGINAL policy intends.
  starter slot  Owen and Alba each carry one slot the ENGINE fills: `owenpoke2`,
                `albapoke1` and friends are methods in the Pokes Rivales script that
                pick a fakemon off $game_variables[54], so the rival always has the
                starter matching yours. Those slots are passed through untouched and
                left on the engine's default moveset -- the species is not knowable
                here, and replacing it would destroy the starter rivalry. Teresa has
                no such slot; her whole team is literal.
  short parties These fights ship 1-6 mons. Everything after gym 1 is padded to 6.
  scaled levels Camus, Atlas and Silver are built at `balanceo`, the game's own
                pbBalancedLevel-1, so the fight tracks the player instead of a pinned
                number. Those stay dynamic: the level cell is emitted as the token and
                the engine evaluates it at battle time. Their eBST band still has to
                come from somewhere, so it is read off where the fight HAPPENS --
                see G.story_level().

Levels are remapped onto the Unbound expert curve exactly as the gym bosses are, so
a rival meets the player at cap parity instead of trailing it. The STAGE a fight
belongs to is still read from its ORIGINAL levels -- that is its position in the
story, and remapping first would fold the two together. Item and mega gating then
follow the gym rules (see UNLOCK_STAGE in generate_bosses.py).

Usage:
    generate_rivals.py                    # preview
    generate_rivals.py Owen               # + full rosters
    generate_rivals.py --json out.json    # emit for validate_team.py
"""
import collections
import json
import os
import re
import sys

import generate_bosses as G
import smogon_corpus as SC

# Every non-gym trainer who fights the player with a roster of their own. The three
# rivals recur across the story; Jeremiah fights twice under two classes (the second
# is JEREBUZO, same four species with Piloswine evolved); Cintia is the post-game
# superboss. Gym leaders are excluded -- generate_bosses.py owns those.
RIVALS = ("OWEN1", "ALBA", "TERESA")
BOSSES = ("JEREMIAH", "JEREBUZO", "SIMON", "CINTIA", "CAMUS", "ATLAS", "SILVER")
TRAINERS = RIVALS + BOSSES
TEAM_SIZE = 6


def is_dynamic(species):
    """An engine-resolved starter slot, e.g. `owenpoke2`. Real internal names are
    uppercase, so the case test is unambiguous."""
    return species[:1].islower()


def dynamic_level(level):
    """('balanceo', offset) for a level that scales to the player, else None.

    Entrenadores.rb defines `balanceo` as pbBalancedLevel($Trainer.party) - 1, and the
    events add their own offset on top: Camus is balanceo+1, Silver balanceo-2. Both
    halves matter, so both are carried through to the emitted spec."""
    if isinstance(level, int):
        return None
    m = re.match(r"([a-z]\w*)([-+]\d+)?$", level)
    if not m:
        raise ValueError("unparsed level expression: %r" % level)
    return m.group(1), int(m.group(2) or 0)


def items_unlocked(stage, map_id):
    """Whether this fight may carry competitive items and a mega stone.

    Both open in the gym-4 town (G.UNLOCK_STAGE). A gym leader's badge count says
    exactly where they stand, but a wandering trainer's band does not: stage
    UNLOCK_STAGE spans the entire walk from gym 3 to gym 4, and Silver waits on
    Ruta 11 partway along it. So on that one boundary the fight has to actually BE in
    the unlock town to count as past the shop; every later band is unambiguous."""
    if stage != G.UNLOCK_STAGE:
        return stage > G.UNLOCK_STAGE
    return G.area_of(map_id) == G.area_of(G.CAPS[G.UNLOCK_STAGE]["map"])


def make_trainer(battle):
    scaled = [dynamic_level(m["level"]) for m in battle["party"]]
    how = None
    if all(scaled):
        # No level to read anywhere in the party, so take the band from where the
        # fight happens instead. The emitted levels stay dynamic either way; this
        # only decides the eBST target, the item pool and what may be built.
        pinned, how = G.story_level(battle["map"])
        party_levels = [pinned] * len(scaled)
    elif any(scaled):
        return None                     # mixed pinned/scaled party: not seen, not handled
    else:
        party_levels = [m["level"] for m in battle["party"]]

    ranked = sorted(party_levels)
    ace = ranked[-1]
    # MEDIAN, not highest: Alba's two early fights carry a Braviary stuck at level 60
    # beside level-16 teammates, and taking the max would file a level-16 fight as
    # endgame and hand it competitive items.
    median = ranked[len(ranked) // 2]
    stage = G.stage_of(median)
    target = G.TARGET[stage]
    lo = target - G.SPREAD[stage] / 2

    unlocked = items_unlocked(stage, battle["map"])
    cap = G.bp_cap(stage)
    allow = None if unlocked else G.early_items()
    quota = G.QUOTA if unlocked else [r for r in G.QUOTA if r != "mega"]
    banned = set() if unlocked else set(G.MEGASTONE)

    team, have, used, notes = [], collections.Counter(), set(), []

    def capped():
        return {r for r, n in G.ROLE_CAP.items() if have[r] >= n}

    def add(name, mon, why, kept):
        mon["kept"], mon["why"] = kept, why
        if mon["item"] in G.MEGASTONE:
            banned.update(G.MEGASTONE)
        team.append(mon)
        have.update(mon["roles"])
        used.add(name)

    # 1) every dev-chosen mon is kept and re-equipped. No band filter here: a rival's
    #    roster IS the character, so unlike a gym leader nothing is dropped for being
    #    under the curve -- the padding slots carry the power instead.
    for m, lvl in zip(battle["party"], party_levels):
        name = m["species"]
        if is_dynamic(name):
            team.append({"species": name, "level": G.remap(lvl), "moves": [], "item": None,
                         "ability": 0, "nature": "HARDY", "iv": 31, "ev": [0] * 6,
                         "roles": set(), "src": "engine (Pokes Rivales starter slot)",
                         "fidelity": 0, "inherited": None,
                         "kept": True, "why": "starter slot"})
            used.add(name)
            notes.append(f"{name} left to the engine — resolves to the starter "
                         f"matching the player's")
            continue
        if name not in G._sp:
            notes.append(f"skipped {name} — not in pokemon.txt")
            continue
        lvl = G.remap(lvl)
        mon = (G.build(name, lvl, banned, avoid=capped(), allow_items=allow, cap=cap)
               or G.fallback(name, lvl, cap))
        if m.get("moves"):
            mon["src"] += f" (dev set was {'/'.join(m['moves'])})"
        add(name, mon, "original", True)

    # 2) pad to six against this stage's eBST target
    def deficit():
        real = [m for m in team if not is_dynamic(m["species"])]
        return target * (len(real) + 1) - sum(G.ebst(m) for m in real)

    pad_level = max(2, G.remap(median) - 1)
    # Rivals get no Ubers at any stage. eligible() opens the Uber pool from gym 7,
    # which is right for a gym leader whose picks are still theme-locked -- a rival
    # has no theme, so the whole box-legendary pool comes with it and Owen turns up
    # with an Arceus. A rival should read as a peer, not a superboss.
    pool = [n for n in G.eligible(pad_level, stage)
            if n not in used and SC.band(n) != "Uber"
            and G.potential_bst(n, unlocked) >= lo]

    def take(role):
        for strict in (True, False):
            full = capped()
            for name in sorted(pool, key=lambda n: (abs(G.potential_bst(n, unlocked)
                                                        - deficit()), SC.rank(n))):
                mon = G.build(name, pad_level, banned, want=role, avoid=full,
                              allow_items=allow, cap=cap)
                if not mon or (role is not None and role not in mon["roles"]):
                    continue
                if strict and mon["roles"] & full:
                    continue
                pool.remove(name)
                add(name, mon, f"added:{role or 'power'}", False)
                return True
        return False

    while len(team) < TEAM_SIZE and pool:
        unmet = [r for r in quota if not have[r]]
        if not any(take(r) for r in unmet) and not take(None):
            break

    # 3) a rival with five dev-chosen mons has only one free slot, so roles cannot be
    #    covered by adding bodies. The set is the other lever: re-equip a kept mon
    #    toward a still-missing role. That changes what it does, never which mon it is.
    for role in quota:
        if have[role]:
            continue
        for i, m in enumerate(team):
            if not m["kept"] or is_dynamic(m["species"]) or len(m["roles"]) > 1:
                continue
            alt = G.build(m["species"], m["level"], banned, want=role,
                          avoid=capped(), allow_items=allow, cap=cap)
            if alt and role in alt["roles"]:
                alt["kept"], alt["why"] = True, f"original, re-set for {role}"
                have.subtract(m["roles"])
                have.update(alt["roles"])
                team[i] = alt
                notes.append(f"{m['species']} re-equipped to cover {role}")
                break

    team.sort(key=lambda m: (is_dynamic(m["species"]), G.ebst(m)
                             if not is_dynamic(m["species"]) else 0))

    # 4) a scaled fight keeps its scaling. Every slot goes back to the token it was
    #    built from -- padded slots included, taking the offset the party already uses
    #    -- so the fight still tracks the player's level after the swap.
    if how:
        token, off = collections.Counter(scaled).most_common(1)[0][0]
        cell = [token, off]
        notes.append("levels stay dynamic (%s%+d); band read from %s -> level %d, %s"
                     % (token, off, how, median, "gym %d" % (stage + 1)))
        for mon in team:
            # keep what the set was designed against: the runtime level is the
            # player's and is unknowable here, but legality was chosen at this one.
            mon["design_level"] = mon["level"]
            mon["level"] = cell
        ace = "%s%+d" % (token, off) if off else token

    return {"battle": battle, "stage": stage, "target": target, "ace": ace,
            "median": median, "level": G.remap(median), "team": team,
            "roles": have, "notes": notes, "dynamic": bool(how)}


def show_level(level):
    """A level cell is an int, or ['balanceo', offset] for a fight that scales."""
    if isinstance(level, int):
        return str(level)
    token, off = level
    return "%s%+d" % (token, off) if off else token


def load_fights():
    battles = json.load(open(os.path.join(G.EXTRACTED, "realidea-battles.json"),
                             encoding="utf-8"))
    gym1_cap = G.CAPS[0]["cap"]
    out, seen = [], set()
    for b in battles:
        if b["type"] not in TRAINERS or not b["party"]:
            continue
        lv = [m["level"] for m in b["party"] if isinstance(m["level"], int)]
        # A pinned fight at or under the gym-1 cap is the tutorial rival and is left
        # alone. A scaled fight has no pinned level to test and is never the tutorial.
        if lv and max(lv) <= gym1_cap:
            continue
        # Cintia's event is stored twice, byte-identical; one team, one override.
        sig = (b["map"], b["type"], b["name"],
               tuple((m["species"], m["level"]) for m in b["party"]))
        if sig in seen:
            continue
        seen.add(sig)
        out.append(b)
    return out


def main(argv):
    args = list(argv)
    if "--stats-only" in args:
        args.remove("--stats-only")
        SC.stats_only()
    out_path = None
    if "--json" in args:
        i = args.index("--json")
        out_path = args[i + 1]
        del args[i:i + 2]

    results, records = [], []
    type_ids = G._type_ids()
    for b in load_fights():
        r = make_trainer(b)
        if r:
            results.append(r)

    print(f'{"trainer":10}{"map":>5}{"lv":>9}{"stage":>7}{"mean":>6}{"tgt":>5}{"gap":>6}'
          f'{"sets":>8}  roles  party')
    for r in results:
        real = [m for m in r["team"] if not is_dynamic(m["species"])]
        mean = sum(G.ebst(m) for m in real) / len(real)
        fid = sum(m["fidelity"] for m in r["team"])
        nrole = sum(1 for x in G.QUOTA[:4] if r["roles"][x])
        b = r["battle"]
        shown = "bal ~" + str(r["level"]) if r["dynamic"] else \
            str(r["median"]) + "→" + str(r["level"])
        print(f'{b["name"] or b["type"]:10}{b["map"]:>5}{shown:>9}'
              f'{"gym " + str(r["stage"] + 1):>7}{mean:>6.0f}{r["target"]:>5}'
              f'{mean - r["target"]:>+6.0f}{f"{fid}/{len(real) * 4}":>8}  {nrole}/4'
              f'{"+M" if r["roles"]["mega"] else "  "} {len(r["team"])} mons')

    for r in results:
        b = r["battle"]
        if b["name"] in args or b["type"] in args:
            print(f'\n#### {b["name"] or b["type"]} — map {b["map"]}  lv {r["median"]}'
                  f'  gym-{r["stage"] + 1} band  target eBST {r["target"]}')
            for m in r["team"]:
                n = m["species"]
                bst = "" if is_dynamic(n) else f'{G.bst(n):>4} {SC.tier(n):>5}'
                print(f'  {"keep" if m["kept"] else "NEW "} {n:13}{bst:<11} '
                      f'lv{show_level(m["level"]):<11}'
                      f' {"/".join(m["moves"]) or "(engine default)"}')
                print(f'{"":20}{m["item"] or "—":<14}{m["nature"]:<9}'
                      f'{",".join(sorted(m["roles"])) or "attacker":<26}[{m["src"]}]')
            for note in r["notes"]:
                print(f"     · {note}")

    if out_path:
        for r in results:
            b = r["battle"]
            mons = [{k: (sorted(v) if isinstance(v, set) else v) for k, v in m.items()}
                    for m in r["team"]]
            records.append({
                "id": f'{"rival" if b["type"] in RIVALS else "boss"}_{b["type"]}'
                      f'_{b["name"] or "x"}_map{b["map"]:03d}',
                "map": b["map"], "type_id": b.get("type_id") or type_ids.get(b["type"]),
                "class": b["type"], "name": b["name"],
                "orig_ace_level": r["ace"], "cheat_tier": False,
                "trainer_items": [], "mons": mons,
                "design": {"target_ebst": r["target"], "stage": r["stage"],
                           "notes": r["notes"]}})
        json.dump(records, open(out_path, "w"), indent=1)
        print(f"\n{len(records)} trainer teams -> {out_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
