#!/usr/bin/env python3
"""Do normal teams cover their weaknesses, and does the answer depend on the archetype?

`mono_synergy.py` could ask a clean question because monotype fixes the weakness list
before the first pick. A normal team has no theme, so the question has to be turned round:
the six picks CREATE a weakness profile, and covering it is a property of the build rather
than a response to a constraint. What replaces "the theme's weaknesses" is:

  blind      attacking types NO member resists -- a type the team has no switch-in for
  stacked    attacking types three or more members are weak to
  hole       both at once: three or more weak AND nobody resists. The thing that loses
             games, and the analogue of monotype's "no switch-in at all" column
  reach      share of the format's real bodies the team hits for x2, as in MONOTYPE-SYNERGY
             section 8 -- not the 18 bare types, because Ice Beam is super effective on
             Grass and not on Ferrothorn
  lose_to    a hole the team also cannot hit super-effectively

Archetype comes from the post title via `team_tags.py` (the dump has no archetype field).
**The tier mix differs by archetype** -- bulky offense is 38% Ubers where stall is 26%
gen8ou -- so a raw comparison would be partly a tier comparison. Every figure is therefore
reported against a null drawn from THAT team's own format, and the archetype claim is about
the residual: coverage above or below what the format's own species pool hands out.

  python3 tools/archetype_coverage.py                 # the report
  python3 tools/archetype_coverage.py --trials 400    # faster, noisier nulls
  python3 tools/archetype_coverage.py --format gen8ou # one format, no tier confound at all
"""
import argparse
import collections
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import team_tags                                       # noqa: E402
from type_model import (                               # noqa: E402
    DUMP, GENS, bodies, best_into, check_names, dex, forme_ability, infer_gen, legal_in,
    mega_forme, multiplier, null_draws, taken, tera_type, tid)

ARCHETYPES = ("stall", "semi-stall", "balance", "bulky offense", "offense", "hyper offense")


def read_labelled(only_format=None):
    """Titled, six-mon, singles, non-monotype teams with a generation that holds them.

    The generation is the FORMAT FILE's claim when the team is legal in it, and only then
    falls back to the post date. That is the opposite priority from mono_synergy, and for a
    good reason: `gen9monotype.json` is one subforum's whole history so its filename says
    nothing, while `gen6ou.json` really is ORAS OU. Trusting the date here moved 55 labelled
    gen 6 teams into gen 7 and left gen 6 with none at all."""
    d = dex()
    check_names(d)
    out, stats = [], collections.Counter()
    for fname in sorted(os.listdir(DUMP)):
        if not fname.endswith(".json") or "doubles" in fname or "monotype" in fname:
            continue
        fmt = fname[:-5]
        if only_format and fmt != only_format:
            continue
        file_gen = int(fmt[3])
        for team in json.load(open(os.path.join(DUMP, fname), encoding="utf-8")):
            data = team.get("data") or []
            arch = team_tags.tags(team.get("name") or "")["archetype"]
            if len(data) != 6 or arch not in ARCHETYPES:
                continue
            stats["titled six-mon teams"] += 1
            if legal_in(file_gen, data, d):
                gen, how = file_gen, "format file"
            else:
                gen, how = infer_gen(team, d)
                stats["format file's generation cannot hold the team"] += 1
            if gen is None:
                stats["no legal generation"] += 1
                continue
            species = d["gen%d" % gen]["species"]
            items = d["gen%d" % gen]["items"]
            mons = []
            for m in data:
                s = species.get(tid(m["species"]))
                if not s:
                    break
                s = mega_forme(s, m.get("item"), species, items, stats)
                mons.append({"species": s["name"], "display": s["name"], "types": s["types"],
                             "ability": forme_ability(m.get("ability") or "", s, stats),
                             "item": m.get("item") or "",
                             "tera": tera_type(m.get("teraType"), gen, d, stats),
                             "moves": [tid(x) for x in m.get("moves") or ()]})
            if len(mons) != 6:
                stats["species unresolved"] += 1
                continue
            out.append({"gen": gen, "how": how, "format": fmt, "archetype": arch,
                        "mons": mons, "url": team.get("url", ""), "name": team.get("name", "")})
            stats["usable"] += 1
    return out, stats


def profile(team, chart, moves, pop):
    """The team's weakness profile and what it can hit, over all 18 attacking types."""
    types = sorted(chart)
    blind = stacked = holes = lose = 0
    weak_total = 0
    for atk in types:
        if atk == "Stellar":
            continue
        resists = sum(1 for m in team["mons"] if taken(atk, m, chart) < 1)
        weak = sum(1 for m in team["mons"] if taken(atk, m, chart) >= 2)
        weak_total += weak
        blind += resists == 0
        stacked += weak >= 3
        if resists == 0 and weak >= 3:
            holes += 1
            if not any(best_into(atk, m, team, chart, moves) >= 2 for m in team["mons"]):
                lose += 1
    population = pop[(team["gen"], team["format"])]
    total = sum(population.values()) or 1
    reach = sum(n for body, n in population.items()
                if any(best_into(list(body), m, team, chart, moves) >= 2
                       for m in team["mons"])) / total
    return {"blind": blind, "stacked": stacked, "holes": holes, "lose_to": lose,
            "weak_per_type": weak_total / 18.0, "reach": reach}


AXES = ("blind", "stacked", "holes", "lose_to", "weak_per_type", "reach")


def null_profile(team, teams_by_format, chart, moves, pop, n, rng):
    """The same profile for `n` shuffles of the team's own format pool.

    This is what makes the archetype comparison legitimate: the tier a team was posted in
    is held fixed, so a stall team from gen8ou is measured against gen8ou's own species at
    gen8ou's own frequencies, not against the corpus."""
    acc = collections.defaultdict(float)
    drawn = 0
    for pick in null_draws(teams_by_format[(team["gen"], team["format"])], n, rng):
        drawn += 1
        fake = {"gen": team["gen"], "format": team["format"], "mons": pick}
        p = profile(fake, chart, moves, pop)
        for k in AXES:
            acc[k] += p[k]
    if not drawn:
        return None
    return {k: acc[k] / drawn for k in AXES}


def show_example(teams, d, pop, by_format, arch, trials, rng, want_format=None):
    """One real team of `arch`, with every number in the report derived in front of you.

    The team picked is the one closest to its archetype's own means on the four axes, so it
    illustrates the row rather than decorating it -- an outlier would make the walkthrough
    read better and mean less."""
    pool = [t for t in teams if t["archetype"] == arch
            and (not want_format or t["format"] == want_format)]
    if not pool:
        raise SystemExit("no %s teams%s" % (arch, " in " + want_format if want_format else ""))
    scored = []
    for t in pool:
        chart, moves = d["gen%d" % t["gen"]]["chart"], d["gen%d" % t["gen"]]["moves"]
        scored.append((t, profile(t, chart, moves, pop)))
    keys = ("blind", "stacked", "holes", "reach")
    mean = {k: sum(p[k] for _, p in scored) / len(scored) for k in keys}
    sd = {k: max((sum((p[k] - mean[k]) ** 2 for _, p in scored) / len(scored)) ** 0.5, 1e-9)
          for k in keys}
    team, p = min(scored, key=lambda tp: sum(((tp[1][k] - mean[k]) / sd[k]) ** 2 for k in keys))
    chart, moves = d["gen%d" % team["gen"]]["chart"], d["gen%d" % team["gen"]]["moves"]

    print("\n=== %s, the team closest to the archetype's own means ===" % arch)
    print("%s  [%s]\n%s" % (team["name"], team["format"], team["url"]))
    for m in team["mons"]:
        print("  %-18s %-16s %-16s %-18s %s" % (
            m["species"], "/".join(m["types"]), m["ability"] or "-", m["item"] or "-",
            ", ".join(m["moves"][:4])))
    print("\n  attacking type   weak  resists   best switch-in   can we hit it x2")
    for atk in sorted(chart):
        if atk == "Stellar":
            continue
        weak = [m for m in team["mons"] if taken(atk, m, chart) >= 2]
        res = [m for m in team["mons"] if taken(atk, m, chart) < 1]
        se = [m for m in team["mons"] if best_into(atk, m, team, chart, moves) >= 2]
        flag = ("HOLE" if not res and len(weak) >= 3 else
                "stacked" if len(weak) >= 3 else "blind" if not res else "")
        print("  %-14s %5d %8d   %-16s %-4s %s" % (
            atk, len(weak), len(res),
            (res[0]["species"][:16] if res else "-- none --"),
            "yes" if se else "NO", flag))
    q = null_profile(team, by_format, chart, moves, pop, trials, rng)
    print("\n  this team: blind %d | stacked %d | holes %d | lose_to %d | reach %.0f%%"
          % (p["blind"], p["stacked"], p["holes"], p["lose_to"], 100 * p["reach"]))
    if q:
        print("  %s null:  blind %.2f | stacked %.2f | holes %.2f | lose_to %.2f | reach %.0f%%"
              % (team["format"], q["blind"], q["stacked"], q["holes"], q["lose_to"],
                 100 * q["reach"]))
        print("  residual:  blind %+.2f | stacked %+.2f | holes %+.2f | lose_to %+.2f | reach %+.0f pts"
              % (p["blind"] - q["blind"], p["stacked"] - q["stacked"], p["holes"] - q["holes"],
                 p["lose_to"] - q["lose_to"], 100 * (p["reach"] - q["reach"])))
    print("  archetype means over %d %s teams: blind %.2f | stacked %.2f | holes %.2f | reach %.0f%%"
          % (len(scored), arch, mean["blind"], mean["stacked"], mean["holes"], 100 * mean["reach"]))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--trials", type=int, default=200, help="null draws per team")
    ap.add_argument("--format", help="restrict to one format, e.g. gen8ou")
    ap.add_argument("--seed", type=int, default=20260919)
    ap.add_argument("--min-n", type=int, default=15, help="skip archetypes below this")
    ap.add_argument("--example", help="also walk one real team of this archetype through "
                                     "every number in the report")
    a = ap.parse_args()
    rng = random.Random(a.seed)
    d = dex()
    teams, stats = read_labelled(a.format)
    print("corpus:", dict(stats))
    if not teams:
        raise SystemExit("no labelled teams matched")
    pop = bodies(teams, key=lambda t: (t["gen"], t["format"]))
    by_format = collections.defaultdict(list)
    for t in teams:
        by_format[(t["gen"], t["format"])].append(t)

    obs = collections.defaultdict(list)
    delta = collections.defaultdict(list)
    for t in teams:
        chart, moves = d["gen%d" % t["gen"]]["chart"], d["gen%d" % t["gen"]]["moves"]
        p = profile(t, chart, moves, pop)
        q = null_profile(t, by_format, chart, moves, pop, a.trials, rng)
        obs[t["archetype"]].append(p)
        if q:
            delta[t["archetype"]].append({k: p[k] - q[k] for k in AXES})

    if a.example:
        show_example(teams, d, pop, by_format, a.example, a.trials, rng, a.format)

    print("\n=== observed, 18 attacking types per team ===")
    print("%-14s %5s | %6s %8s %6s %8s %9s %7s" % (
        "archetype", "n", "blind", "stacked", "holes", "lose_to", "weak/type", "reach%"))
    for arch in ARCHETYPES:
        rows = obs[arch]
        if len(rows) < a.min_n:
            continue
        mean = lambda k: sum(r[k] for r in rows) / len(rows)
        print("%-14s %5d | %6.2f %8.2f %6.2f %8.2f %9.2f %7.0f" % (
            arch, len(rows), mean("blind"), mean("stacked"), mean("holes"),
            mean("lose_to"), mean("weak_per_type"), 100 * mean("reach")))

    print("\n=== minus each team's own format pool (positive = more than the tier hands out) ===")
    print("%-14s %5s | %6s %8s %6s %8s %9s %7s" % (
        "archetype", "n", "blind", "stacked", "holes", "lose_to", "weak/type", "reach%"))
    for arch in ARCHETYPES:
        rows = delta[arch]
        if len(rows) < a.min_n:
            continue
        mean = lambda k: sum(r[k] for r in rows) / len(rows)
        sd = lambda k: (sum((r[k] - mean(k)) ** 2 for r in rows) / max(len(rows) - 1, 1)) ** 0.5
        t = lambda k: mean(k) / (sd(k) / len(rows) ** 0.5) if sd(k) else 0.0
        print("%-14s %5d | %+6.2f %+8.2f %+6.2f %+8.2f %+9.2f %+7.1f" % (
            arch, len(rows), mean("blind"), mean("stacked"), mean("holes"),
            mean("lose_to"), mean("weak_per_type"), 100 * mean("reach")))
        print("%-14s %5s | %6s %8s %6s %8s %9s %7s" % (
            "  t", "", "%.1f" % t("blind"), "%.1f" % t("stacked"), "%.1f" % t("holes"),
            "%.1f" % t("lose_to"), "%.1f" % t("weak_per_type"), "%.1f" % t("reach")))


if __name__ == "__main__":
    main()
