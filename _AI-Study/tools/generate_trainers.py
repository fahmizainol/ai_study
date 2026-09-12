#!/usr/bin/env python3
"""Named-trainer generator: the rivals and the other recurring bosses who are not
gym leaders (TEAM-DESIGN.md §6.5 lever 1).

The SAME machinery as the gym bosses, not merely a similar one: the build itself is
generate_bosses.assemble(), and everything below is a field of the spec handed to it.
What is left here is the four things that are genuinely about these fights:

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

A fight may also carry an archetype and a mode, which it gets from
generated/fight_plans.json via G.plan_of(); with no entry there it gets the flat
presence quota, which is what these fights have always had. See TEAM-DESIGN.md §6.8.

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
import functools
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

# The starter-slot test lives with the assembly loop that has to skip those slots.
is_dynamic = G.is_dynamic


# The starter branch, verbatim from the game's `Pokes Rivales` script: each of these
# is a Ruby method returning one of three fakemon off $game_variables[54], so the
# rival's slot is whichever line rivals the player's starter. A fight that carries one
# does not have one Pokemon there, it has three at a third of the weight each -- and
# that is the honest way to read it, because a reading has to hold for all three
# playthroughs or it is not a reading about the fight.
STARTER_BRANCH = {
    "owenpoke1": ("MEADEW", "GULLIBY", "TIGGLARE"),
    "owenpoke2": ("NINFAE", "SAIGULL", "RABATUTA"),
    "owenpoke3": ("FAEUNA", "SEAGHOUL", "TIGNITUS"),
    "albapoke1": ("SAIGULL", "RABATUTA", "NINFAE"),
    "albapoke2": ("SEAGHOUL", "TIGNITUS", "FAEUNA"),
}
# How often a family must turn up across one trainer's fights to count as their spine.
CORE_MIN = 2


def slots(party):
    """[(species, weight)] for one party, starter branches resolved.

    A branch slot contributes all three fakemon at 1/3 each rather than picking one,
    so nothing downstream can accidentally read a fight as "the Water one" when that
    is true in one playthrough of three."""
    out = []
    for m in party:
        name = m["species"]
        if name in STARTER_BRANCH:
            out += [(sp, 1 / 3) for sp in STARTER_BRANCH[name]]
        elif is_dynamic(name):
            continue                   # an engine slot nobody has a table for
        else:
            out.append((name, 1.0))
    return [(n, w) for n, w in out if n in G._sp]


@functools.lru_cache(maxsize=None)
def recurring(trainer_type):
    """Families this trainer brings to at least CORE_MIN of their own fights.

    A rival appears up to five times; what makes them that rival is the line that
    keeps coming back, not the padding around it. Gym leaders fight once, so this is
    empty for them, which is correct -- a gym's identity is its type, not its spine.

    Here rather than in fight_context because it is a fact about the fight list this
    module owns, and because assemble() needs it to know which of a rival's Pokemon
    must never be spent to satisfy a plan."""
    tally = collections.Counter()
    n = 0
    for b in load_fights():
        if b["type"] != trainer_type:
            continue
        n += 1
        seen = collections.Counter()
        for name, w in slots(b["party"]):
            seen[G.root(name)] = max(seen[G.root(name)], w)
        tally.update(seen)
    if n < CORE_MIN:
        return ()
    return tuple(sorted(k for k, v in tally.items() if v >= CORE_MIN))


def fight_id(battle):
    """The id this fight's team record is emitted under, and the key its plan is
    filed under in generated/fight_plans.json."""
    return (f'{"rival" if battle["type"] in RIVALS else "boss"}_{battle["type"]}'
            f'_{battle["name"] or "x"}_map{battle["map"]:03d}')


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


def fight_band(battle):
    """Where this fight sits in the story: (party levels, ace, median, stage, how).

    `how` is None for a pinned fight, and otherwise says where the level was read
    from -- see G.story_level(). Returns None for a party that mixes pinned and
    scaled levels, which is not seen in Realidea and is not handled.

    Separate from make_trainer because fight_context.py needs a fight's stage and
    band to propose plans FOR it, and computing them cannot require building it."""
    scaled = [dynamic_level(m["level"]) for m in battle["party"]]
    how = None
    if all(scaled):
        # No level to read anywhere in the party, so take the band from where the
        # fight happens instead. The emitted levels stay dynamic either way; this
        # only decides the eBST target, the item pool and what may be built.
        pinned, how = G.story_level(battle["map"])
        party_levels = [pinned] * len(scaled)
    elif any(scaled):
        return None
    else:
        party_levels = [m["level"] for m in battle["party"]]
    ranked = sorted(party_levels)
    # MEDIAN, not highest: Alba's two early fights carry a Braviary stuck at level 60
    # beside level-16 teammates, and taking the max would file a level-16 fight as
    # endgame and hand it competitive items.
    median = ranked[len(ranked) // 2]
    return party_levels, ranked[-1], median, G.stage_of(median), how


def make_trainer(battle, plan=None):
    band = fight_band(battle)
    if band is None:
        return None
    party_levels, ace, median, stage, how = band
    scaled = [dynamic_level(m["level"]) for m in battle["party"]]
    target = G.TARGET[stage]
    unlocked = items_unlocked(stage, battle["map"])

    # A named trainer has no archetype or mode of its own unless one has been chosen
    # for it; without a plan the flat presence quota applies, which is what these
    # fights have always had.
    archetype, mode = plan if plan else G.plan_of(fight_id(battle))
    if stage < G.MODE_FROM:
        mode = None
    floors, caps = G.plan_for(archetype, unlocked, mode)

    # 1) every dev-chosen mon is kept and re-equipped, at its own remapped level.
    #    The starter slots Owen and Alba carry are passed through untouched: the
    #    species is a method on $game_variables[54] and is not knowable here.
    # A Builder card can drop one of this trainer's own Pokemon or pin an extra, and
    # can name which published sets a species may use. A starter slot is never
    # droppable: it is a method the engine resolves, not a species anyone chose.
    keep, sets_ = G.picks_for(fight_id(battle))
    kept = [{"species": m["species"], "level": G.remap(lvl),
             "moves": m.get("moves"), "dynamic": is_dynamic(m["species"])}
            for m, lvl in zip(battle["party"], party_levels)]
    own = {m["species"] for m in battle["party"]}
    lv = G.remap(max(party_levels) if party_levels else median)
    kept += [{"species": n, "level": lv, "moves": None, "dynamic": False,
              "pinned": True}
             for n, on in keep.items() if on and n not in own and n in G._sp]

    # 2) pad to six against this stage's eBST target. Rivals get no Ubers at any
    #    stage: eligible() opens that pool from gym 7, which is right for a gym
    #    leader whose picks are still theme-locked -- a rival has no theme, so the
    #    whole box-legendary pool comes with it and Owen turns up with an Arceus.
    built = G.assemble({
        "level": max(2, G.remap(median) - 1), "ace_level": None, "stage": stage,
        "target": target, "lo": target - G.SPREAD[stage] / 2,
        "hi": target + G.SPREAD[stage] / 2,
        "theme": None, "on_theme_min": 0, "why_theme": None,
        "kept": kept, "keep_band": False, "note_unknown": True,
        "floors": floors, "caps": caps, "mode": mode, "mega_ok": unlocked,
        "ubers_ok": False, "project_spent_mega": False,
        "why_open": ("added:%s", "added:power"),
        "reequip": True, "dedupe": False,
        # A rival's roster IS the character, so the families they bring to two or more
        # of their own fights are held back on top of the mode's evidence.
        "keep_drop": G.KEEP_DROP, "keep_test": G.keep_filter(keep),
        "set_formats": G.SET_FORMATS, "early_moves": G.EARLY_MOVES,
        "set_seed": G.SET_SEED or None, "pick_seed": G.PICK_SEED or None,
        "set_filter": sets_,
        "protected": ([m["species"] for m in battle["party"]
                       if G.root(m["species"]) in recurring(battle["type"])]
                      + [m["species"] for m in battle["party"]
                         if G.mode_evidence(m["species"], mode)]),
    })
    team, notes = built["team"], built["notes"]

    # 3) a scaled fight keeps its scaling. Every slot goes back to the token it was
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
            "roles": built["roles"], "notes": notes, "dynamic": bool(how),
            "archetype": archetype, "mode": mode, "floors": floors}


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
          f'{"sets":>8}  roles  plan')
    for r in results:
        real = [m for m in r["team"] if not is_dynamic(m["species"])]
        mean = sum(G.ebst(m) for m in real) / len(real)
        fid = sum(m["fidelity"] for m in r["team"])
        # against this fight's OWN floors: once a fight can carry an archetype, a
        # fixed four-role denominator is measuring a plan it may not have.
        floors = {k: v for k, v in r["floors"].items() if k != "mega"}
        nrole = sum(1 for k, v in floors.items() if r["roles"][k] >= v)
        b = r["battle"]
        shown = "bal ~" + str(r["level"]) if r["dynamic"] else \
            str(r["median"]) + "→" + str(r["level"])
        print(f'{b["name"] or b["type"]:10}{b["map"]:>5}{shown:>9}'
              f'{"gym " + str(r["stage"] + 1):>7}{mean:>6.0f}{r["target"]:>5}'
              f'{mean - r["target"]:>+6.0f}{f"{fid}/{len(real) * 4}":>8}'
              f'  {nrole}/{len(floors)}{"+M" if r["roles"]["mega"] else "  "} '
              + (r["archetype"] or "flat quota")
              + (" + " + r["mode"] if r["mode"] else ""))

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
                "id": fight_id(b),
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
