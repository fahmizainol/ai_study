#!/usr/bin/env python3
"""Per-Pokemon contribution from Showdown's own battle logs (the bots' logs carry no faints).

Needs the server started with exports.logchallenges (setup_battles.py sets it); each
finished battle is saved as logs/<month>/gen9nationaldexrnb/<day>/*.log.json. Side a (the
challenger) is always Run & Bun, so its username starts with "r"; the opponent is side b.

For each team on the opponent side, per member, over every logged battle:
  KOs      opposing Pokemon that fainted on a turn this member hit them (direct KOs;
           hazard/status chip is credited to nobody)
  dealt    % of opposing max HP this member's moves removed
  fainted  share of battles it was KO'd
  on field turns it started as the active Pokemon
  m:<move> times it used that move

Only battles that ended normally count: when a bot crashes the room times out, and that
"win" measures nothing. Teams holding two formes of one species are skipped: Foul Play cannot pilot them, see summarize_gen_battles.

    python3 tools/rnb/read_battles.py generated/rnb_vs_gen [--since EPOCH] [--pool]

--pool prints one line for the whole experiment instead of per team: KOs per slot, the
share of dead slots (no KO, under 2 turns on the field), and for every slot carrying a
setup move (team_shape.ROLE_MOVES) how often it used one and what it KO'd.
"""
import collections
import glob
import json
import os
import re
import sys

from paths import TOOLS, WORK, pokedex

sys.path.insert(0, TOOLS)
import team_shape as TS  # noqa: E402

LOGS = os.path.join(WORK, "showdown", "node_modules", "pokemon-showdown", "logs")


def tid(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


SETUP = {tid(m) for m in TS.ROLE_MOVES["setup"]}


def hp(s):
    """'57/100' -> 57.0; '0 fnt' -> 0.0"""
    s = s.split()[0]
    if "/" not in s:
        return 0.0
    a, b = s.split("/")
    return 100.0 * float(a) / float(b)


def battle(path):
    """Replay one protocol log -> (winner side, per-(side, species) Counter)."""
    try:
        with open(path, encoding="utf-8") as fh:
            d = json.load(fh)
    except ValueError:                        # truncated by a crash mid-write
        return {}, None, None
    lines = d["log"] if isinstance(d.get("log"), list) else d["log"].split("\n")
    names = {"p1": d.get("p1", ""), "p2": d.get("p2", "")}
    active, cur, last_hit = {}, {}, {}
    stat = collections.defaultdict(collections.Counter)
    attacker = None
    for ln in lines:
        p = ln.split("|")
        if len(p) < 2:
            continue
        kind = p[1]
        if kind in ("switch", "drag", "replace"):
            side = p[2][:2]
            sp = tid(p[3].split(",")[0])
            key = (side, sp)
            # a mega keeps its base species' slot: map "charizardmegax" onto "charizard"
            for (s2, sp2) in list(cur):
                if s2 == side and sp.startswith(sp2) and sp != sp2:
                    key = (side, sp2)
            active[side] = key
            cur.setdefault(key, 100.0)
            cur[key] = hp(p[4]) if len(p) > 4 else cur[key]
        elif kind == "turn":
            for side, key in active.items():
                stat[key]["onfield"] += 1
        elif kind == "move":
            attacker = active.get(p[2][:2])
            if attacker:
                stat[attacker]["m:" + tid(p[3])] += 1
        elif kind == "-damage" and len(p) > 3:
            side = p[2][:2]
            key = active.get(side)
            if key is None:
                continue
            new = hp(p[3])
            src = ln.split("[from]")[1].strip() if "[from]" in ln else ""
            if not src and attacker and attacker[0] != side:
                stat[attacker]["dealt"] += max(cur.get(key, 100.0) - new, 0.0)
                last_hit[key] = attacker
            elif src:                      # hazards, status, weather: nobody's KO
                last_hit.pop(key, None)
            cur[key] = new
        elif kind in ("-heal", "-sethp") and len(p) > 3:
            key = active.get(p[2][:2])
            if key:
                cur[key] = hp(p[3])
        elif kind == "faint":
            key = active.get(p[2][:2])
            if key:
                stat[key]["fainted"] += 1
                killer = last_hit.pop(key, None)
                if killer:
                    stat[killer]["kos"] += 1
        elif kind == "upkeep":
            attacker = None
            last_hit.clear()
    if d.get("endType") != "normal":         # a bot crashed and the room timed out
        return names, None, None
    winner = d.get("winner", "")
    side_won = "p1" if winner == names["p1"] else "p2" if winner == names["p2"] else None
    return names, side_won, stat


def main():
    out = sys.argv[1]
    since = float(sys.argv[sys.argv.index("--since") + 1]) if "--since" in sys.argv else 0
    pairs = json.load(open(os.path.join(out, "pairs.json")))
    per = collections.defaultdict(collections.Counter)
    record = collections.Counter()
    dex = pokedex()
    for f in glob.glob(os.path.join(LOGS, "*", "*", "*", "*.log.json")):
        if os.path.getmtime(f) < since:
            continue
        names, won, stat = battle(f)
        if stat is None:
            continue
        rside = "p1" if names["p1"].startswith("r") else "p2"
        oside = "p2" if rside == "p1" else "p1"
        # the bot usernames carry the run tag ("rb28x1t52566" -> pairing 28); tags repeat
        # across experiments, so also require every species seen to be on that team
        m = re.match(r"rb(\d+)x\d+t", names[rside])
        if not m or int(m.group(1)) >= len(pairs):
            continue
        p = pairs[int(m.group(1))]
        team = p["opp"]
        path = os.path.join(out, "teams", p.get("opp_side", "smogon"), team)
        own = {tid(b.split("\n")[0].split(" @ ")[0]) for b in open(path, encoding="utf-8").read().strip().split("\n\n")}
        base = {tid(dex[sp].get("baseSpecies", sp)) for sp in own}
        if not {sp for (s, sp) in stat if s == oside} <= own or len(base) < len(own):
            continue                    # another experiment's tag, or two formes of one species
        record[team, won == oside] += 1
        sets = {tid(b.split("\n")[0].split(" @ ")[0]): {tid(ln[2:]) for ln in b.split("\n") if ln.startswith("- ")}
                for b in open(path, encoding="utf-8").read().strip().split("\n\n")}
        for sp, moves in sets.items():
            c = stat.get((oside, sp), collections.Counter())
            per[team, sp].update(c)
            per[team, sp]["battles"] += 1
            per[team, sp]["dead"] += c["kos"] == 0 and c["onfield"] < 2
            if moves & SETUP:
                per[team, sp]["setup_carrier"] += 1
                per[team, sp]["setup_used"] += any(c["m:" + m] for m in moves & SETUP)
    return per, record


def pool_line(per, record):
    n_battles = sum(record.values())
    wins = sum(v for (t, w), v in record.items() if w)
    slots = [c for c in per.values()]
    kos = sum(c["kos"] for c in slots)
    dead_share = sum(c["dead"] for c in slots) / max(sum(c["battles"] for c in slots), 1)
    sc = [c for c in slots if c["setup_carrier"]]
    carried = sum(c["setup_carrier"] for c in sc)
    used = sum(c["setup_used"] for c in sc)
    sko = sum(c["kos"] for c in sc) / max(carried, 1)
    oko = sum(c["kos"] for c in slots if not c["setup_carrier"]) / max(sum(c["battles"] for c in slots if not c["setup_carrier"]), 1)
    return ("battles %3d  won %5.1f%%  KOs/battle %.2f  never-contributing slots %4.1f%%  "
            "setup slots %4.1f%% of slots, used setup in %4.1f%% of their battles, KOs/battle %.2f (others %.2f)"
            % (n_battles, 100 * wins / max(n_battles, 1), kos / max(n_battles, 1), 100 * dead_share,
               100 * carried / max(sum(c["battles"] for c in slots), 1), 100 * used / max(carried, 1), sko, oko))


if __name__ == "__main__":
    per, record = main()
    if "--pool" in sys.argv:
        print(pool_line(per, record))
        sys.exit()
    for t in sorted({t for t, _ in record}):
        n = record[t, True] + record[t, False]
        print("\n%s  %d-%d" % (t, record[t, True], record[t, False]))
        for (tt, sp), c in sorted(per.items()):
            if tt != t:
                continue
            print("  %-14s KOs %4.2f  dealt %5.0f%%  fainted %3.0f%%  on field %4.1f turns" %
                  (sp, c["kos"] / n, c["dealt"] / n, 100 * c["fainted"] / n, c["onfield"] / n))
