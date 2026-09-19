#!/usr/bin/env python3
"""Does a monotype team cover the weaknesses its theme type hands it?

A Water team is weak to Grass and Electric before it picks a single Pokemon. The
question this asks is whether real teams answer that -- with a second type
(Water/Ground eats Electric), an ability (Sap Sipper, Volt Absorb), an item (Air
Balloon, a resist berry) or a defensive Tera -- and whether they do it more than the
species pool would give them for free.

Two nulls, because "they cover it" can mean two different things:

  pool  each theme's legal species drawn uniformly. Tests whether the species
        monotype players actually use cover better than the ones they could use.
  team  the theme's own species drawn with their observed frequency, each carrying
        one of its own observed sets. Marginals are preserved exactly, so this tests
        per-team coordination only: whether a builder who already has five members
        reaches for the sixth that patches the hole.

Type/ability/move facts come from the pokemon-showdown checkout via
dump_showdown_dex.js, not from tools/realidea_data.py: that PBS is one gen-6-era
16-type dex with a fangame's edits, and this corpus is gens 7-9 with Fairy, gen 9
species and gen 9 abilities.

  python3 tools/mono_synergy.py                  # the whole report, gen 9
  python3 tools/mono_synergy.py --gen 7 8 9      # stability across generations
  python3 tools/mono_synergy.py --theme Water    # one theme, with its answer species
  python3 tools/mono_synergy.py --json out.json  # per-team records
"""
import argparse
import collections
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from type_model import (                       # noqa: E402 -- see type_model's docstring
    ABILITY_FACTOR, ABILITY_SPECIAL, BERRY, CACHE, DUMP, DYNAMIC_UNRESOLVED, ERA, GENS,
    HAZARD_REMOVAL, ITEM_FACTOR, PIVOT_MOVES, RECOVERY_ABILITIES, RECOVERY_MOVES,
    SELF_TYPED, WEATHER_BALL, attack_types, best_into, bodies, check_names, dex,
    forme_ability, gen_from_date, infer_gen, legal_in, mechanism, mega_forme, multiplier,
    null_draws, switchin_quality, taken, tera_type, tid, ztest, _spread)

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "..", "extracted", "smogon-dump")
CACHE = os.path.join(HERE, "..", "generated", "showdown_dex.json")

# NEITHER the filename's tier NOR its generation can be taken at face value.
#
#   gen6monotype.json is not monotype at all: its 30 teams are one "Any Ability"
#   thread (Barraskewda, Zapdos-Galar on a gen 6 list), and 30 of 30 have no type
#   shared by all six members.
#
#   gen9monotype.json is not gen 9. It is the monotype subforum's whole history --
#   posts dated from 2014-03, 1827 teams holding a mega stone, and 2428 of 4337
#   containing a species that does not exist in gen 9. Grouping it by filename would
#   have scored gen 6 and gen 7 teams against the gen 9 dex, which is how a Mega
#   Swampert ends up reported as a gen 9 Water answer.
#
# So the tier is validated structurally (all six members share a type) and the
# generation is inferred per team from the post date, vetoed by legality.
GENS = (6, 7, 8, 9)
ERA = ((9, "2022-11-18"), (8, "2019-11-15"), (7, "2016-11-18"), (6, "2013-10-12"))






def read_teams(gens):
    """(gen, theme, [set]) per monotype team whose six species all resolve.

    Theme is the type shared by every member. Where a listed forme breaks that -- a
    Mega whose typing differs from its base, which is how Monotype allows Charizard-
    Mega-X on Fire -- the base formes decide the theme while the listed forme keeps
    its own typing for every multiplier below, because the listed forme is what takes
    the hit."""
    d = dex()
    check_names(d)
    out, stats = [], collections.Counter()
    for fname in ("gen7monotype.json", "gen8monotype.json", "gen9monotype.json"):
        for team in json.load(open(os.path.join(DUMP, fname), encoding="utf-8")):
            data = team.get("data") or []
            stats["scraped records"] += 1
            if len(data) != 6:
                stats["not six mons"] += 1
                continue
            gen, how = infer_gen(team, d)
            if gen is None:
                stats["no legal generation"] += 1
                continue
            stats["gen%d (%s)" % (gen, how)] += 1
            if gen not in gens:
                continue
            species, items = d["gen%d" % gen]["species"], d["gen%d" % gen]["items"]
            mons = []
            for m in data:
                s = species.get(tid(m["species"]))
                if not s:
                    break
                s = mega_forme(s, m.get("item"), species, items, stats)
                base = species[s["base"]]
                ability = forme_ability(m.get("ability") or "", s, stats)
                mons.append({
                    "species": s["name"], "types": s["types"],
                    # Gastrodon-East and Gastrodon are one answer, not two: merge a
                    # forme back into its base only when typing and BST are identical,
                    # which keeps Swampert-Mega separate from Swampert.
                    "display": base["name"] if (s["types"] == base["types"]
                                                and s["bst"] == base["bst"]) else s["name"],
                    "base_types": base["types"],
                    "ability": ability, "item": m.get("item") or "",
                    "tera": tera_type(m.get("teraType"), gen, d, stats),
                    "item_legal": not (d["gen%d" % gen]["items"].get(tid(m.get("item") or ""), {}) or {}).get("nonstandard"),
                    "moves": [tid(x) for x in m.get("moves") or ()],
                })
            if len(mons) != 6:
                stats["species unresolved"] += 1
                continue
            for key in ("types", "base_types"):
                theme = set(mons[0][key]).intersection(*[set(x[key]) for x in mons[1:]])
                if theme:
                    break
            if len(theme) != 1:
                stats["no single shared type" if not theme else "ambiguous theme"] += 1
                continue
            out.append({"gen": gen, "how": how, "theme": theme.pop(), "mons": mons,
                        "url": team.get("url", ""), "name": team.get("name", "")})
            stats["usable"] += 1
    return out, stats


def typing_answer_possible(theme, atk, chart):
    """Can ANY second type take `theme`'s x2 weakness to `atk` below neutral?

    Derived, not assumed. A monotype member's multiplier is 2 x m(atk -> U) for its
    second type U, and the chart only ever contributes 2, 1, 0.5 or 0 -- so the product
    is under 1 only when m is 0. Every typing-based answer on a monotype team is
    therefore an IMMUNITY, and for the ten attacking types nothing is immune to, no
    second type helps at all and an ability or item is the only route. This returns the
    immune types so the claim is read off the chart each run instead of trusted."""
    return [u for u in chart if multiplier(atk, [theme, u], chart) < 1]


def weaknesses(theme, chart):
    return sorted(a for a, v in chart[theme].items() if v == 1)


# -------------------------------------------------------------------------- scoring
def score(team, chart):
    """Per theme weakness: how many members switch in, and by what mechanism.

    `answers` is the count that takes less than neutral damage -- the mon you can
    actually click a switch to. `neutral_only` is the weakness where the best the team
    can do is take x1, which on a 2x theme still means every member is a liability."""
    out = {}
    for atk in weaknesses(team["theme"], chart):
        rows = []
        for m in team["mons"]:
            rows.append({"species": m["species"],
                         # typing only -- the one the pool null is comparable to
                         "type_only": multiplier(atk, m["types"], chart),
                         "no_item": taken(atk, m, chart, use_item=False),
                         "full": taken(atk, m, chart),
                         "mech": mechanism(atk, m, chart), "mon": m})
        hard = [r for r in rows if r["full"] < 1]
        out[atk] = {
            "answers": len(hard),
            "answers_no_item": sum(1 for r in rows if r["no_item"] < 1),
            "answers_typing": sum(1 for r in rows if r["type_only"] < 1),
            "best": min(r["full"] for r in rows),
            "still_weak": sum(1 for r in rows if r["full"] >= 2),
            "mechs": collections.Counter(r["mech"] for r in hard),
            "who": [(r["species"], r["mech"], r["full"]) for r in hard],
            "rows": rows,
        }
    return out


# ----------------------------------------------------------------------------- nulls
def null_pool(theme, gen, d, n, rng):
    """Uniform draw from every species of `theme` legal in `gen` -- the pool-level null.

    Typing only: a legal species has no chosen ability or item, so comparing it to real
    teams' full coverage would compare two different measurements. Real teams are
    scored the same way (bare typing) wherever this null is quoted."""
    species = d["gen%d" % gen]["species"]
    legal = [s for s in species.values() if theme in s["types"] and not s["nonstandard"]]
    chart = d["gen%d" % gen]["chart"]
    weak = weaknesses(theme, chart)
    hits = collections.Counter(); counts = collections.defaultdict(list)
    for _ in range(n):
        pick = rng.sample(legal, 6) if len(legal) >= 6 else [rng.choice(legal) for _ in range(6)]
        for atk in weak:
            c = sum(1 for s in pick if multiplier(atk, s["types"], chart) < 1)
            hits[atk] += c > 0
            counts[atk].append(c)
    return {a: _spread(hits[a], counts[a], n) for a in weak}


def null_team(theme, gen, teams, chart, n, rng):
    """Defensive null: how often a shuffled team still resists each theme weakness."""
    weak = weaknesses(theme, chart)
    hits = collections.Counter(); counts = collections.defaultdict(list); drawn = 0
    pool = [t for t in teams if t["theme"] == theme and t["gen"] == gen]
    for pick in null_draws(pool, n, rng):
        drawn += 1
        for atk in weak:
            c = sum(1 for m in pick if taken(atk, m, chart) < 1)
            hits[atk] += c > 0
            counts[atk].append(c)
    if not drawn:
        return None
    return {a: _spread(hits[a], counts[a], drawn) for a in weak}


def null_offence(theme, gen, teams, chart, moves, n, rng):
    """Offensive null: how often a shuffled team still hits each threatening type."""
    weak = weaknesses(theme, chart)
    hits = collections.Counter(); counts = collections.defaultdict(list); drawn = 0
    pool = [t for t in teams if t["theme"] == theme and t["gen"] == gen]
    for pick in null_draws(pool, n, rng):
        drawn += 1
        fake = {"theme": theme, "mons": pick}
        for atk in weak:
            c = sum(1 for m in pick if best_into(atk, m, fake, chart, moves) >= 2)
            hits[atk] += c > 0
            counts[atk].append(c)
    if not drawn:
        return None
    return {a: _spread(hits[a], counts[a], drawn) for a in weak}




def offence(team, chart, moves, pop, unresolved=None):
    """Per threatening type: can this team hit back, and with what.

    `stab` is the theme's own STAB into the threat -- when it is below 1 the matchup is
    doubly bad (they hit us for x2, we are resisted) and a coverage move is the only way
    to threaten anything. `bodies` is the share of the threatening theme's REAL member
    population this team can hit for x2 or better, weighted by how often those bodies
    appear, which is the number that says whether the coverage actually does the job."""
    out = {}
    for atk in weaknesses(team["theme"], chart):
        rows = []
        for m in team["mons"]:
            rows.append({"mon": m,
                         "best": best_into(atk, m, team, chart, moves),
                         "off": best_into(atk, m, team, chart, moves, off_type_only=True)})
        population = pop[(team["gen"], atk)]
        total = sum(population.values()) or 1

        def share(pred):
            return sum(n for body, n in population.items() if pred(body)) / total

        hit = share(lambda body: any(best_into(list(body), m, team, chart, moves) >= 2
                                     for m in team["mons"]))
        # STAB only, and only if the team actually carries a theme-type attack: otherwise
        # this would report the type chart's potential rather than what the team can do.
        has_stab = any(team["theme"] in attack_types(name, m, team, moves)
                       for m in team["mons"] for name in m["moves"])
        stab_hit = share(lambda body: has_stab
                         and multiplier(team["theme"], list(body), chart) >= 2)
        neutral = share(lambda body: any(best_into(list(body), m, team, chart, moves) >= 1
                                         for m in team["mons"]))
        if unresolved is not None:
            for m in team["mons"]:
                for name in m["moves"]:
                    attack_types(name, m, team, moves, unresolved)
        out[atk] = {
            "stab": multiplier(team["theme"], [atk], chart),
            "se": sum(1 for r in rows if r["best"] >= 2),
            "off_se": sum(1 for r in rows if r["off"] >= 2),
            "bodies_hit": hit, "bodies_stab": stab_hit, "bodies_neutral": neutral,
            "rows": rows,
        }
    return out


def summarise(teams, d, gen, theme, trials, rng):
    """One row per weakness of `theme`, with both nulls beside the observed share."""
    chart = d["gen%d" % gen]["chart"]
    ts = [t for t in teams if t["gen"] == gen and t["theme"] == theme]
    if not ts:
        return []
    scored = [score(t, chart) for t in ts]
    npool = null_pool(theme, gen, d, trials, rng)
    nteam = null_team(theme, gen, teams, chart, trials, rng)
    rows = []
    for atk in weaknesses(theme, chart):
        n = len(ts)
        res = sum(1 for s in scored if s[atk]["answers"] > 0) / n
        bare = sum(1 for s in scored if s[atk]["answers_typing"] > 0) / n
        mech = collections.Counter()
        for s in scored:
            mech.update(s[atk]["mechs"])
        # Tera counts only where nothing else answers: a defensive Tera is a real out,
        # but a team with Swampert did not need it, and counting both would double-count
        # the same weakness.
        # A Tera that resists is not proof of defensive intent: Tera Poison on Toxapex
        # resists Grass and is also its own STAB. Only an OFF-TYPE Tera -- one the set
        # does not already have -- is a typing chosen for the matchup, so the two are
        # counted apart and never added together.
        tera_any = tera_off = 0
        for s in scored:
            if s[atk]["answers"]:
                continue
            fix = [r["mon"] for r in s[atk]["rows"]
                   if r["mon"]["tera"] and taken(atk, r["mon"], chart, use_tera=True) < 1]
            tera_any += bool(fix)
            tera_off += any(m["tera"] not in m["types"] for m in fix)
        tera_only, tera_offtype = tera_any / n, tera_off / n
        counts = [s[atk]["answers"] for s in scored]
        omean = sum(counts) / n
        ovar = sum((c - omean) ** 2 for c in counts) / n
        rows.append({
            "gen": gen, "theme": theme, "atk": atk, "n": n,
            "resist": res, "bare": bare,
            "mean": sum(s[atk]["answers"] for s in scored) / n,
            "neutral_only": sum(1 for s in scored if s[atk]["answers"] == 0
                                and s[atk]["best"] <= 1) / n,
            "nothing": sum(1 for s in scored if s[atk]["best"] >= 2) / n,
            "weak_mons": sum(s[atk]["still_weak"] for s in scored) / n,
            "pool": npool[atk]["share"], "team": nteam[atk]["share"] if nteam else None,
            "p_pool": ztest(bare, n, npool[atk]["share"], trials),
            "p_team": ztest(res, n, nteam[atk]["share"], trials) if nteam else 1.0,
            "tera_only": tera_only, "tera_offtype": tera_offtype, "mech": mech,
            "immune_types": typing_answer_possible(theme, atk, chart),
            "var": ovar, "exactly1": sum(1 for c in counts if c == 1) / n,
            "team_mean": nteam[atk]["mean"] if nteam else None,
            "team_var": nteam[atk]["var"] if nteam else None,
            "team_ex1": nteam[atk]["exactly1"] if nteam else None,
        })
    return rows


POP = [None]          # bodies(teams), built once in main


def report(teams, d, gens, themes, trials, rng, verbose_theme=None):
    for gen in gens:
        chart = d["gen%d" % gen]["chart"]
        present = sorted({t["theme"] for t in teams if t["gen"] == gen})
        rows = [th for th in present if not themes or th in themes]
        if not rows:
            continue
        print("\n=== gen %d — %d teams, %d themes ===" % (
            gen, sum(1 for t in teams if t["gen"] == gen and t["theme"] in rows), len(rows)))
        struct = collections.defaultdict(list)
        for th in rows:
            for atk in weaknesses(th, chart):
                struct[bool(typing_answer_possible(th, atk, chart))].append((th, atk))
        print("  structure, read off the type chart: of %d theme-weakness pairs, %d can be "
              "answered by a second type and %d cannot."
              % (len(struct[True]) + len(struct[False]), len(struct[True]), len(struct[False])))
        print("  a second type helps only where it is IMMUNE (2 x 0.5 is still neutral), so the "
              "%d unanswerable pairs are exactly those whose attacker nothing is immune to: %s"
              % (len(struct[False]), ", ".join(sorted({a for _, a in struct[False]}))))
        print("%-8s %4s %-8s | %5s %4s %5s %5s | %5s %5s %6s | %5s %5s %6s | %5s %5s | %4s %4s | %s" % (
            "theme", "n", "weak to", "res%", "mean", "neu%", "no%",
            "bare%", "pool%", "p", "res%", "team%", "p", "=1%", "null", "ter", "off", "mechanism"))
        allrows = []
        for th in rows:
            for r in summarise(teams, d, gen, th, trials, rng):
                allrows.append(r)
                tot = sum(r["mech"].values()) or 1
                ms = " ".join("%s %.0f" % (k, 100 * v / tot) for k, v in r["mech"].most_common(3))
                if not typing_answer_possible(th, r["atk"], chart):
                    ms = (ms + "  [no typing answer exists]").strip()
                print("%-8s %4d %-8s | %5.0f %4.2f %5.0f %5.0f | %5.0f %5.0f %6.3f | %5.0f %5.0f %6.3f | %5.0f %5.0f | %4.0f %4.0f | %s" % (
                    th, r["n"], r["atk"], 100 * r["resist"], r["mean"], 100 * r["neutral_only"],
                    100 * r["nothing"], 100 * r["bare"], 100 * r["pool"], r["p_pool"],
                    100 * r["resist"], 100 * (r["team"] or 0), r["p_team"],
                    100 * r["exactly1"], 100 * (r["team_ex1"] or 0),
                    100 * r["tera_only"], 100 * r["tera_offtype"], ms))
        digest(allrows, gen)
        report_offence(teams, d, gen, themes, trials, rng, POP[0])
    if verbose_theme:
        for gen in gens:
            detail(teams, d, verbose_theme, gen)


def digest(rows, gen):
    """The three headline questions, over every (theme, weakness) pair in this gen."""
    n = len(rows)
    if not n:
        return
    wt = sum(r["n"] for r in rows)
    mean = lambda k: sum(r[k] * r["n"] for r in rows) / wt
    print("  -- %d theme-weakness pairs, team-weighted: resist %.0f%% | neutral-only %.0f%% "
          "| nothing %.0f%% | mean answers %.2f | mean members still weak %.2f of 6"
          % (n, 100 * mean("resist"), 100 * mean("neutral_only"), 100 * mean("nothing"),
             mean("mean"), mean("weak_mons")))
    beats_pool = [r for r in rows if r["bare"] > r["pool"] and r["p_pool"] < 0.05]
    under_pool = [r for r in rows if r["bare"] < r["pool"] and r["p_pool"] < 0.05]
    beats_team = [r for r in rows if r["resist"] > r["team"] and r["p_team"] < 0.05]
    under_team = [r for r in rows if r["resist"] < r["team"] and r["p_team"] < 0.05]
    print("  -- vs pool null (typing only): %d pairs above, %d below, %d indistinguishable (p>=0.05)"
          % (len(beats_pool), len(under_pool), n - len(beats_pool) - len(under_pool)))
    print("  -- vs team null (co-occurrence): %d above, %d below, %d indistinguishable"
          % (len(beats_team), len(under_team), n - len(beats_team) - len(under_team)))
    worst = sorted(rows, key=lambda r: -r["nothing"])[:6]
    print("  -- weaknesses teams most often cannot switch into at all:")
    for r in worst:
        print("       %-8s vs %-8s %3.0f%% of %d teams have every member at x2 or worse"
              % (r["theme"], r["atk"], 100 * r["nothing"], r["n"]))
    slot = [r for r in rows if r["team"] is not None and r["resist"] > r["team"]
            and r["var"] < r["team_var"] and r["p_team"] < 0.05]
    print("  -- designated-slot signature (more teams covered than the team null AND a "
          "tighter spread, i.e. nearly always exactly one answer): %d of %d pairs" % (len(slot), n))
    if gen == 9:
        ta = sum(r["tera_only"] * r["n"] for r in rows) / wt
        to = sum(r["tera_offtype"] * r["n"] for r in rows) / wt
        print("  -- Tera on uncovered weaknesses: %.0f%% of teams hold a Tera that would resist, "
              "but only %.0f%% is an OFF-TYPE Tera (the rest is the set's own STAB, which resists "
              "as a side effect)" % (100 * ta, 100 * to))
    law = [r for r in rows if not r["immune_types"]]
    if law:
        print("  -- no typing answer CAN exist (nothing is immune to the attacker, and a resist "
              "only brings x2 back to x1): %d pairs, %s" % (
                  len(law), ", ".join("%s/%s" % (r["theme"], r["atk"]) for r in law)))
    gap = [r for r in rows if r["immune_types"] and r["pool"] == 0]
    if gap:
        print("  -- the immunity exists but no legal species of the theme has it, so the answer is "
              "on paper only: %s" % ", ".join(
                  "%s/%s (would need %s/%s)" % (r["theme"], r["atk"], r["theme"],
                                                "|".join(r["immune_types"])) for r in gap))
    strict = 0.05 / max(n, 1)
    print("  -- Bonferroni over %d pairs (alpha %.4f): %d still above the pool null, %d above the "
          "team null" % (n, strict,
                         sum(1 for r in rows if r["bare"] > r["pool"] and r["p_pool"] < strict),
                         sum(1 for r in rows if r["team"] is not None and r["resist"] > r["team"]
                             and r["p_team"] < strict)))


def report_offence(teams, d, gen, themes, trials, rng, pop):
    """The other half: against the types that threaten it, can the theme hit back?"""
    chart, moves = d["gen%d" % gen]["chart"], d["gen%d" % gen]["moves"]
    present = sorted({t["theme"] for t in teams if t["gen"] == gen})
    rows = [th for th in present if not themes or th in themes]
    if not rows:
        return
    unresolved = collections.Counter()
    print("\n--- gen %d, offence: %-38s ---" % (gen, "hitting the types that hit us"))
    print("%-8s %4s %-8s | %5s | %5s %4s %5s | %6s %6s %6s | %5s %5s %6s | %s" % (
        "theme", "n", "threat", "STAB", "se%", "mean", "off%",
        "bodies", "bySTAB", "neu", "se%", "team%", "p", "coverage types used"))
    out = []
    for th in rows:
        ts = [t for t in teams if t["gen"] == gen and t["theme"] == th]
        scored = [offence(t, chart, moves, pop, unresolved) for t in ts]
        nl = null_offence(th, gen, teams, chart, moves, trials, rng)
        for atk in weaknesses(th, chart):
            n = len(ts)
            se = sum(1 for s in scored if s[atk]["se"] > 0) / n
            off = sum(1 for s in scored if s[atk]["off_se"] > 0) / n
            mean = sum(s[atk]["se"] for s in scored) / n
            bh = sum(s[atk]["bodies_hit"] for s in scored) / n
            bs = sum(s[atk]["bodies_stab"] for s in scored) / n
            bn = sum(s[atk]["bodies_neutral"] for s in scored) / n
            stab = scored[0][atk]["stab"]
            kinds = collections.Counter()
            for t, s in zip(ts, scored):
                for r in s[atk]["rows"]:
                    for name in r["mon"]["moves"]:
                        for at in attack_types(name, r["mon"], t, moves):
                            if at != th and multiplier(at, [atk], chart) >= 2:
                                kinds[at] += 1
            tot = sum(kinds.values()) or 1
            p = ztest(se, n, nl[atk]["share"], trials) if nl else 1.0
            out.append({"theme": th, "atk": atk, "n": n, "stab": stab, "se": se, "off": off,
                        "bodies": bh, "by_stab": bs, "neutral": bn,
                        "null": nl[atk]["share"] if nl else None, "p": p})
            print("%-8s %4d %-8s | %5s | %5.0f %4.2f %5.0f | %6.0f %6.0f %6.0f | %5.0f %5.0f %6.3f | %s" % (
                th, n, atk, ("x%g" % stab) + ("!" if stab < 1 else ""), 100 * se, mean,
                100 * off, 100 * bh, 100 * bs, 100 * bn, 100 * se,
                100 * (nl[atk]["share"] if nl else 0), p,
                " ".join("%s %.0f" % (k, 100 * v / tot) for k, v in kinds.most_common(3))))
    digest_offence(out, unresolved)


def digest_offence(rows, unresolved):
    wt = sum(r["n"] for r in rows) or 1
    mean = lambda k: sum(r[k] * r["n"] for r in rows) / wt
    print("  -- team-weighted: %.0f%% of teams hit the threatening type super-effectively, "
          "and they hit %.0f%% of its real bodies for x2 (%.0f%% of bodies from the theme's own "
          "STAB, %.0f%% reachable at neutral or better)"
          % (100 * mean("se"), 100 * mean("bodies"), 100 * mean("by_stab"), 100 * mean("neutral")))
    hard = [r for r in rows if r["stab"] < 1]
    if hard:
        print("  -- matchups where the theme's own STAB is RESISTED by the type attacking it, "
              "so a coverage move is the only threat:")
        for r in sorted(hard, key=lambda r: -r["se"]):
            print("       %-8s vs %-8s STAB x%g | %3.0f%% of teams carry SE coverage, hitting "
                  "%3.0f%% of real bodies (STAB alone: %2.0f%%)"
                  % (r["theme"], r["atk"], r["stab"], 100 * r["se"], 100 * r["bodies"],
                     100 * r["by_stab"]))
    blind = [r for r in rows if r["se"] < 0.5]
    print("  -- threats over half of teams cannot hit super-effectively at all: %s"
          % (", ".join("%s/%s %.0f%%" % (r["theme"], r["atk"], 100 * r["se"]) for r in
                       sorted(blind, key=lambda r: r["se"])) or "none"))
    above = [r for r in rows if r["null"] is not None and r["se"] > r["null"] and r["p"] < 0.05]
    below = [r for r in rows if r["null"] is not None and r["se"] < r["null"] and r["p"] < 0.05]
    print("  -- vs the same co-occurrence null: %d above, %d below, %d indistinguishable"
          % (len(above), len(below), len(rows) - len(above) - len(below)))
    if unresolved:
        print("  -- move types left unresolved (counted as no coverage): %s" % dict(unresolved))


def detail(teams, d, theme, gen):
    """Who answers, by what, and whether the answer is built to switch in."""
    chart = d["gen%d" % gen]["chart"]
    ts = [t for t in teams if t["theme"] == theme and t["gen"] == gen]
    if not ts:
        return
    print("\n--- gen %d %s (n=%d teams) ---" % (gen, theme, len(ts)))
    for atk in weaknesses(theme, chart):
        who = collections.Counter(); qual = collections.Counter(); per = collections.Counter()
        teras = collections.Counter()
        for t in ts:
            s = score(t, chart)[atk]
            per[s["answers"]] += 1
            for r in s["rows"]:
                if r["full"] < 1:
                    who["%-22s %-7s x%g" % (r["mon"]["display"], r["mech"], r["full"])] += 1
                    q = switchin_quality(r["mon"])
                    qual["total"] += 1
                    for k, v in q.items():
                        qual[k] += bool(v)
                if r["mon"]["tera"] and r["full"] >= 1 and \
                        taken(atk, r["mon"], chart, use_tera=True) < 1:
                    teras["%s -> Tera %s" % (r["mon"]["display"], r["mon"]["tera"])] += 1
        tot = qual["total"] or 1
        print("  vs %-8s answers per team %s" % (atk, dict(sorted(per.items()))))
        print("     %d answer slots: %.0f%% recovery, %.0f%% pivot move, %.0f%% hazard removal"
              % (qual["total"], 100 * qual["recovery"] / tot, 100 * qual["pivot"] / tot,
                 100 * qual["removal"] / tot))
        for name, k in who.most_common(8):
            print("       %-44s %3d teams (%2.0f%%)" % (name, k, 100 * k / len(ts)))
        if not who:
            neu = collections.Counter()
            for t in ts:
                for r in score(t, chart)[atk]["rows"]:
                    if r["full"] == 1:
                        neu[r["mon"]["display"]] += 1
            print("       (nothing resists; the best switch-ins are neutral bodies)")
            for name, k in neu.most_common(5):
                print("       %-44s %3d teams (%2.0f%%)" % (name + "  x1", k, 100 * k / len(ts)))
        mv = d["gen%d" % gen]["moves"]
        cov = collections.Counter()
        for t in ts:
            for m in t["mons"]:
                for name in m["moves"]:
                    for at in attack_types(name, m, t, mv):
                        if at != theme and multiplier(at, [atk], chart) >= 2:
                            cov["%s (%s)" % (mv[name]["name"] if name in mv else name, at)] += 1
        if cov:
            print("     hitting %s back -- off-type coverage moves on these teams:" % atk)
            for name, k in cov.most_common(5):
                print("       %-44s %3d sets" % (name, k))
        for name, k in teras.most_common(3):
            print("       [tera] %-37s %3d teams (%2.0f%%)" % (name, k, 100 * k / len(ts)))


def example(teams, d, theme, gen, pop):
    """One real team of `theme`, with both halves derived member by member.

    Picks the team closest to its theme's own means, as archetype_coverage's --example does
    and for the same reason: an outlier would read better and illustrate less."""
    chart, moves = d["gen%d" % gen]["chart"], d["gen%d" % gen]["moves"]
    ts = [t for t in teams if t["theme"] == theme and t["gen"] == gen]
    if not ts:
        raise SystemExit("no gen %d %s teams" % (gen, theme))
    weak = weaknesses(theme, chart)
    rows = []
    for t in ts:
        ds, os_ = score(t, chart), offence(t, chart, moves, pop)
        rows.append((t, ds, os_,
                     (sum(ds[a]["answers"] for a in weak) / len(weak),
                      sum(1 for a in weak if ds[a]["best"] >= 2) / len(weak),
                      sum(os_[a]["se"] for a in weak) / len(weak))))
    mean = [sum(r[3][i] for r in rows) / len(rows) for i in range(3)]
    sd = [max((sum((r[3][i] - mean[i]) ** 2 for r in rows) / len(rows)) ** 0.5, 1e-9)
          for i in range(3)]
    team, ds, os_, _ = min(rows, key=lambda r: sum(((r[3][i] - mean[i]) / sd[i]) ** 2
                                                   for i in range(3)))
    print("\n=== gen %d %s, the team closest to the theme's own means (of %d) ===" % (
        gen, theme, len(ts)))
    print("%s\n%s" % (team["name"] or "(untitled)", team["url"]))
    for m in team["mons"]:
        print("  %-18s %-16s %-15s %-17s %-7s %s" % (
            m["display"], "/".join(m["types"]), m["ability"] or "-", m["item"] or "-",
            ("Tera " + m["tera"]) if m["tera"] else "-",
            ", ".join(m["moves"][:4])))
    for atk in weak:
        immune = typing_answer_possible(theme, atk, chart)
        print("\n  --- weak to %s (%s) ---" % (
            atk, ("a %s/%s would be immune" % (theme, "|".join(immune))) if immune
            else "NO typing answer exists: nothing is immune to %s" % atk))
        for m, dr, orow in zip(team["mons"], ds[atk]["rows"], os_[atk]["rows"]):
            verdict = ("RESISTS via %s" % dr["mech"] if dr["full"] < 1
                       else "weak" if dr["full"] >= 2 else "neutral")
            hits = [x for x in m["moves"]
                    if any(multiplier(a, [atk], chart) >= 2
                           for a in attack_types(x, m, team, moves))]
            print("     %-18s x%-4g %-16s | hits back: %s" % (
                m["display"], dr["full"], verdict, ", ".join(hits) or "no"))
        print("     team: %d resist, %d neutral, %d weak | %d can hit %s back%s"
              % (ds[atk]["answers"],
                 sum(1 for r in ds[atk]["rows"] if r["full"] == 1),
                 ds[atk]["still_weak"], os_[atk]["se"], atk,
                 "" if os_[atk]["stab"] >= 1 else
                 " (and %s STAB is resisted by %s, x%g)" % (theme, atk, os_[atk]["stab"])))
    print("\n  the %s rows this team sits in (all %d gen %d %s teams):" % (theme, len(ts), gen, theme))
    for atk in weak:
        n = len(ts)
        print("     vs %-8s res %3.0f%% | neutral-only %3.0f%% | nothing %3.0f%% | "
              "hits it %3.0f%% (mean %.2f members)"
              % (atk,
                 100 * sum(1 for _, x, _, _ in rows if x[atk]["answers"] > 0) / n,
                 100 * sum(1 for _, x, _, _ in rows if x[atk]["answers"] == 0
                           and x[atk]["best"] <= 1) / n,
                 100 * sum(1 for _, x, _, _ in rows if x[atk]["best"] >= 2) / n,
                 100 * sum(1 for _, _, y, _ in rows if y[atk]["se"] > 0) / n,
                 sum(y[atk]["se"] for _, _, y, _ in rows) / n))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gen", nargs="*", type=int, default=[9], choices=GENS)
    ap.add_argument("--theme", nargs="*", default=None)
    ap.add_argument("--trials", type=int, default=4000, help="null-model draws per theme")
    ap.add_argument("--seed", type=int, default=20260919)
    ap.add_argument("--json", help="write per-team coverage records here")
    ap.add_argument("--rebuild-dex", action="store_true")
    ap.add_argument("--example", action="store_true",
                    help="with --theme: walk one real team of it through both halves")
    a = ap.parse_args()
    if a.rebuild_dex:
        dex(force=True)
    d = dex()
    teams, stats = read_teams(GENS)
    POP[0] = bodies(teams)
    print("corpus:", dict(stats))
    if a.example:
        for th in (a.theme or []):
            for gen in a.gen:
                example(teams, d, th, gen, POP[0])
        return
    report(teams, d, a.gen, a.theme, a.trials, random.Random(a.seed),
           verbose_theme=(a.theme[0] if a.theme else None))
    if a.json:
        recs = []
        for t in teams:
            chart = d["gen%d" % t["gen"]]["chart"]
            s = score(t, chart)
            recs.append({"gen": t["gen"], "theme": t["theme"], "url": t["url"],
                         "species": [m["species"] for m in t["mons"]],
                         "weaknesses": {k: {kk: vv for kk, vv in v.items() if kk != "rows"}
                                        for k, v in s.items()}})
        with open(a.json, "w") as fh:
            json.dump(recs, fh, indent=1, default=lambda o: list(o.elements()) if isinstance(o, collections.Counter) else str(o))
        print("wrote", a.json, len(recs), "records")


if __name__ == "__main__":
    main()
