#!/usr/bin/env python3
"""What each fight is ABOUT, read off the team the developer already gave it.

`generate_bosses.ARCHETYPE` is nine words someone typed. This asks the fight itself:
Dhara's Ground gym already fields a Hippowdon, whose ability is Sand Stream and whose
two types are the two the corpus says sand over-represents most -- so "Dhara is a sand
fight" is not a flavour call, it is a reading of her own roster plus 171 real sand
teams. Fights where no such reading exists get no mode, and say so.

Three steps, and they are deliberately separate:

  derive()   the fight's context: what it keeps, what recurs across its class's
             other fights, what type it is really built on. No corpus, no building.
  propose()  candidate plans (archetype x mode) and the EVIDENCE for each, scored
             against the corpus. Still no building -- this is cheap and is what
             decides which candidates are worth the cost of building at all.
  score()    build each candidate through the real generator and report what it
             actually cost: floors met, and the gap from the eBST curve.

The split matters because evidence and outcome disagree, and the disagreement is the
useful part. Lawrence's Psychic gym is the corpus's second-best Trick Room theme and
fields four slow Pokemon -- strong evidence -- and then cannot build it, because at
eBST 593 the on-theme band holds exactly one slow Trick Room learner. Evidence says
what the fight wants; the build says what the dex will give it.

Nothing here is applied automatically. `--write` records the choices in
generated/fight_plans.json, which is the only thing the two generators read; an
absent entry means the static default, so a clean checkout reproduces the shipped
teams whether this file has ever run or not.

Usage:
    fight_context.py gym6_DHARA_Dhara      # one fight, all candidates
    fight_context.py Dhara                 # name, class or id all work
    fight_context.py --all
    fight_context.py --all --sort strength # rank by curve gap instead of evidence
    fight_context.py --all --write         # record the defaults as the chosen plans
"""
import collections
import json
import os
import sys

import generate_bosses as G
import generate_trainers as T
import realidea_data as D
import smogon_corpus as SC
import team_shape as TS

PLANS_VERSION = 1
# A mode needs this many agreement-validated corpus teams before its type lift and
# setter count are worth reading at all. Snow sits just over it (n=33) and is the one
# to watch: its lift on Ice is the largest of any mode on any type (5.7x) and is
# resting on the fewest teams.
MODE_MIN_N = 20
# How much evidence a mode needs before it is even proposed. One matching theme is
# worth its type lift alone, so a Fire gym (sun, 3.1x) or a Water gym (rain, 2.9x)
# clears this with no help from the roster; a theme the mode is neutral on needs two
# abusers or one setter already present.
MODE_MIN_EVIDENCE = 1.5
# Stall is excluded exactly as it is from generate_bosses.ARCHETYPE: Realidea's dex
# cannot supply five recovery sets inside a type theme and a BST band, so assigning
# it produces a worse balance team that merely reports missed floors (TEAM-CORPUS §6).
ARCHETYPES = [a for a in TS.ARCHETYPES if a != "stall"]

# The starter branch, the per-party resolver and the "families this rival always
# brings" tally all live in generate_trainers now: they are facts about the fight list
# and the dex, and assemble() needs them too -- it must not spend a rival's core
# family to satisfy a plan, and it cannot import this module to ask.
STARTER_BRANCH = T.STARTER_BRANCH
CORE_MIN = T.CORE_MIN
slots = T.slots
root = G.root


# ---------------------------------------------------------------- the fights
def fights():
    """Every fight that can carry a plan: the nine gyms and the 18 named trainers."""
    out = [{"id": G.gym_id(i), "kind": "gym", "idx": i, "cap": G.CAPS[i],
            "label": G.CAPS[i]["next_battle"], "who": G.CAPS[i]["trainer"],
            "cls": G.CAPS[i]["trainer_type"]}
           for i in range(len(G.CAPS))]
    for b in T.load_fights():
        kind = "rival" if b["type"] in T.RIVALS else "boss"
        if all(T.dynamic_level(m["level"]) for m in b["party"]):
            kind = "scaled"
        out.append({"id": T.fight_id(b), "kind": kind, "battle": b,
                    "label": b["name"] or b["type"], "who": b["name"] or b["type"],
                    "cls": b["type"]})
    return out


def find(token):
    """Every fight matching an id, a trainer name, a class or a gym label."""
    t = token.lower()
    return [f for f in fights()
            if t in (f["id"].lower(), f["who"].lower(), f["cls"].lower(),
                     f["label"].lower())]


# ---------------------------------------------------------------- context
def derive(f):
    """What this fight is, before any corpus or any building is involved."""
    if f["kind"] == "gym":
        cap = f["cap"]
        party, stage = cap["team"], f["idx"]
        level, target = G.remap(cap["cap"]) - 1, G.TARGET[f["idx"]]
    else:
        party = f["battle"]["party"]
        _lv, _ace, median, stage, _how = T.fight_band(f["battle"])
        level, target = max(2, G.remap(median) - 1), G.TARGET[stage]

    spine = slots(party)
    types = collections.Counter()
    for name, w in spine:
        for t in G._sp[name]["types"]:
            types[t] += w
    ranked = types.most_common()
    # A tie is not a theme. Two types at equal weight means the roster is not built
    # on either, and picking the alphabetically-first one would invent a reading.
    theme = ranked[0][0] if ranked and (len(ranked) < 2
                                        or ranked[0][1] > ranked[1][1]) else None
    warn = None
    if f["kind"] == "gym" and theme != G.THEME[f["who"]]:
        warn = (f"roster reads {theme or 'no clear type'}, "
                f"THEME says {G.THEME[f['who']]} — building on THEME")
        theme = G.THEME[f["who"]]

    ctx = dict(f, theme=theme, warn=warn, spine=spine, stage=stage,
               level=level, target=target, core=list(T.recurring(f["cls"])),
               lo=target - G.SPREAD[stage] / 2, hi=target + G.SPREAD[stage] / 2)
    ctx["plans"] = propose(ctx)
    return ctx


# ---------------------------------------------------------------- candidates
def affinity_of(name, mode, prof):
    """TS.affinity for a bare species -- every ability it could have, no set yet."""
    sp = G._sp[name]
    return TS.affinity(mode, sp["types"],
                       list(sp["abilities"]) + [sp["hidden_ability"]],
                       sp["base_stats"][3], (), prof=prof)


def setter_for(mode, level, stage, lo=None, hi=None):
    """A species in this fight's pool that could actually turn the mode on, or None.

    Without this check the generator is asked to floor a role nothing in the band can
    fill, and reports a missed floor rather than an infeasible plan.

    For the four WEATHERS that means an ability holder inside the fight's eBST band,
    not merely something that learns the move. Real weather teams set it with an
    ability -- 100% of sand, 91% of snow, 82% of rain, 60% of sun -- and Pelipper
    alone is 78% of all rain teams. Realidea has thirteen holders in the entire dex,
    and Pelipper and Torkoal are not among them: its PBS is gen-6 era, so both are in
    the game carrying Keen Eye and White Smoke instead of their gen-7 weather
    abilities. The two Ubers that do hold one (Kyogre, Groudon, 670 BST) are above
    every band ceiling in the game, so what is actually available is Politoed for
    rain, Ninetales for sun, three for sand and five for snow.

    The consequence is deliberate and worth stating: from gym 7 on (band 550+) sand
    is the only weather with a setter, because Tyranitar is the only holder that fits.
    Trick Room and screens keep the move path -- they have no ability, and that is
    what they are rather than a case to apologise for.

    This is the gate that stopped gym 1 being offered `balance + rain`: at band
    302-492 there is no Drizzle holder at all, Politoed being 500."""
    ability = {a for a, r in TS.WEATHER_ROLE_OF_ABILITY.items() if r == mode}
    weather = mode in TS.WEATHER_MODES
    for name in G.eligible(level, stage):
        sp = G._sp[name]
        has = ability & {SC.norm(a) for a in sp["abilities"] + [sp["hidden_ability"]]
                         if a}
        if weather:
            if has and (lo is None or lo <= G.bst(name) <= hi):
                return name
            continue
        if has or any(D.learnable(name, mv, level) in ("levelup", "tm")
                      for mv in TS.ROLE_MOVES[mode]):
            return name
    return None


def cashes(ctx, mode):
    """The dev's own Pokemon that CASH `mode` -- setters and abusers, never types."""
    return [n for n, _w in ctx["spine"] if G.mode_evidence(n, mode)]


def supported(ctx, mode, prof):
    """Does this fight's own roster carry enough of `mode` to claim it at all?

    The bar is TS.min_roster_abusers: one more than a team that is not trying would
    have. For weather that is one real setter or abuser; for Trick Room it is two,
    because 22% of the dex is slow and one slow Pokemon is not evidence.

    Screens is exempt and says so rather than quietly passing: its payoff is a SETUP
    set, which is a property of the set the builder chooses and not of the species, so
    no test on a bare roster can see it. It is gated on its type signal and on the
    pool being able to supply a setter."""
    if mode == "screens":
        return True
    return len(cashes(ctx, mode)) >= TS.min_roster_abusers(mode, prof)


def evidence(ctx, mode, prof):
    """How much this fight already looks like a `mode` fight. 0 for no mode.

    Three terms, all measured: the corpus's lift for the fight's own type, and the
    setters and abusers ALREADY on the dev's roster, counted through the same
    TS.affinity the builder ranks candidates with -- so the evidence and the build
    cannot be reading two different definitions of "abuser".

    Type overlap can now only ADD to a score, never create one: propose() refuses a
    mode the roster does not actually cash (see supported()). Alba's first fight scored
    rain 4.38 on four Pokemon whose entire contribution was being Grass, Flying or
    Water -- not one rain ability between them, and the Rain Dance in the built team
    was the setter the BUILDER added to satisfy the floor, i.e. a consequence of the
    plan being read as evidence for it.

    The theme term is held to the SAME bar as a Pokemon's own types, TS.LIFT_MIN.
    Taking the raw lift instead was a bug with a specific and repeatable signature: a
    lift under 1.0 means the mode carries LESS of that type than average -- evidence
    AGAINST -- and it was being added in favour. Any fight with a single on-type mon
    scores exactly 1.0, so a 0.7-1.1 theme term was enough to push it over the 1.5
    threshold on its own. It did that 21 times across the 27 fights, which is most of
    why rain and sand appeared nearly everywhere: Aimi's Fairy gym proposed rain at
    1.76 = one part-Water Marill, plus 0.76 for Fairy being a type rain AVOIDS."""
    if not mode:
        return 0.0
    lift = prof["mode"][mode]["type_lift"].get(ctx["theme"] or "", 0.0)
    ev = lift if lift >= TS.LIFT_MIN else 0.0
    for name, w in ctx["spine"]:
        ev += w * affinity_of(name, mode, prof)
    return round(ev, 2)


def fits_type(ctx, mode, prof):
    """Is this mode something this fight's TYPE would actually run?

    Two rules, and the first is measured rather than asserted: a weather is proposed
    only for a theme the corpus over-represents on teams running it --
    prof["mode"][m]["type_lift"] against TS.LIFT_MIN, the same threshold affinity()
    already uses to make this judgement about one set. sun is FIRE/GRASS/POISON, rain
    is WATER/FLYING/GRASS, sand is ROCK/GROUND/STEEL/DARK, snow is ICE/FIRE/WATER.

    The second is a design decision: a NON-weather mode is never a default. Trick Room
    is the reason -- it won four of the 27 fights on evidence, while the corpus puts it
    under 1% of real teams and the build probe puts it at 11 grants from 1,156 asks.
    Evidence scores what a roster LOOKS like, and a roster of slow bulky mons looks
    like Trick Room whether or not Trick Room is a plan worth having.

    Failing this does not remove the mode from the candidate list -- it is appended
    and flagged, so it ranks last and can still be chosen deliberately. A themeless
    fight (a rival) gets no weather, which is the right answer rather than a special
    case: there is no type to read one off."""
    if mode not in TS.WEATHER_MODES:
        return False
    lift = (prof["mode"][mode].get("type_lift") or {})
    return bool(ctx["theme"]) and lift.get(ctx["theme"], 0) >= TS.LIFT_MIN


def propose(ctx):
    """Candidate plans for this fight, evidence first. Always includes today's plan.

    The full product of archetypes x surviving modes: an archetype says how the six
    sets divide the work and a mode says what the battle is about, and neither
    constrains the other (they name disjoint roles -- see G.plan_for)."""
    prof = TS.profile()
    now_a, now_m = G.plan_of(ctx["id"])
    if ctx["kind"] == "gym" and now_a is None:
        now_a = G.ARCHETYPE[ctx["idx"]]
    archetypes = [now_a] + [a for a in ARCHETYPES if a != now_a]

    modes, why = [None], {}
    for mode in TS.MODE_ROLES:
        m = prof["mode"].get(mode)
        if ctx["stage"] < G.MODE_FROM:
            why[mode] = f"stage {ctx['stage']} is before MODE_FROM {G.MODE_FROM}"
        elif not m or m["n"] < MODE_MIN_N:
            why[mode] = f"only {m['n'] if m else 0} corpus teams (need {MODE_MIN_N})"
        elif not supported(ctx, mode, prof):
            why[mode] = (f"roster cashes it {len(cashes(ctx, mode))}x, "
                         f"needs {TS.min_roster_abusers(mode, prof)}")
        elif not setter_for(mode, ctx["level"], ctx["stage"],
                            ctx["lo"], ctx["hi"]):
            why[mode] = (f"no {'ability ' if mode in TS.WEATHER_MODES else ''}setter "
                         f"in the lv{ctx['level']} gym-{ctx['stage'] + 1} pool"
                         + (f" inside band {ctx['lo']:.0f}-{ctx['hi']:.0f}"
                            if mode in TS.WEATHER_MODES else ""))
        elif not fits_type(ctx, mode, prof):
            why[mode] = (f"{ctx['theme'] or 'no theme'} is not a type the corpus "
                         f"runs {mode} on" if mode in TS.WEATHER_MODES else
                         f"{mode} is not a weather a type can abuse")
            modes.append(mode)          # shown, never chosen -- see _order
        elif evidence(ctx, mode, prof) < MODE_MIN_EVIDENCE:
            why[mode] = (f"evidence {evidence(ctx, mode, prof)} "
                         f"< {MODE_MIN_EVIDENCE}")
        else:
            modes.append(mode)
    if now_m and now_m not in modes:
        modes.append(now_m)             # a chosen plan is always a candidate
    # `now` is what this fight is built as TODAY, and is not (archetypes[0],
    # modes[0]): modes[0] is None by construction, so reading the incumbent off the
    # candidate lists reports every already-moded fight as one the default changes.
    return {"archetypes": archetypes, "modes": modes, "now": (now_a, now_m),
            "rejected": why,
            "evidence": {m: evidence(ctx, m, prof) for m in TS.MODE_ROLES}}


# ---------------------------------------------------------------- building
def score(ctx, archetype, mode):
    """Build this candidate through the real generator and report what it cost."""
    if ctx["kind"] == "gym":
        i = ctx["idx"]
        was = G.ARCHETYPE[i], G.MODE[i]
        try:
            G.ARCHETYPE[i], G.MODE[i] = archetype, mode
            r = G.make_gym(i)
        finally:
            G.ARCHETYPE[i], G.MODE[i] = was
    else:
        r = T.make_trainer(ctx["battle"], (archetype, mode))
    team, floors, roles = r["team"], r["floors"], r["roles"]
    real = [m for m in team if not G.is_dynamic(m["species"])]
    # The mega floor is held out of the count: it is an item-unlock fact about the
    # stage, identical for every candidate, and including it flatters them all.
    need = [f for f in floors if f != "mega"]
    missed = [f for f in need if roles[f] < floors[f]]
    return {"archetype": archetype, "mode": mode,
            # propose() keeps today's plan on the candidate list however it scores, so
            # a person can see what it costs. It must not be able to WIN: a mode the
            # gates rejected is not a plan this fight can have, and left to rank
            # normally gym 1 went on defaulting to the `rain` its own gate had just
            # refused. Ranked last, shown, never chosen.
            "gated": bool(mode and mode in ctx["plans"]["rejected"]),
            "evidence": ctx["plans"]["evidence"][mode] if mode else 0.0,
            "met": len(need) - len(missed), "need": len(need), "missed": missed,
            "gap": round(sum(G.ebst(m) for m in real) / max(len(real), 1)
                         - ctx["target"]),
            "floors": floors, "roles": dict(roles), "team": team}


def candidates(ctx, how="evidence"):
    """Every candidate plan, built and ranked. The first is the default."""
    now = ctx["plans"]["now"]
    out = [score(ctx, a, m) for a in ctx["plans"]["archetypes"]
           for m in ctx["plans"]["modes"]]
    for s in out:
        s["incumbent"] = (s["archetype"], s["mode"]) == now
    out.sort(key=lambda s: _order(s, how))
    return out


def _order(s, how):
    """Two rankings, because "best" is two different questions.

    `evidence` answers "what is this fight most like?"; `strength` answers "what lands
    closest to the curve?", which is what you want while the curve is being tuned.
    Both refuse to answer with a plan that does not build: a plan missing a floor is
    not a candidate for the default however well it reads or however close it lands.

    The incumbent wins exact ties. Evidence is a property of the MODE, so every
    archetype carrying the same mode scores identically and the ranking falls through
    to the curve gap -- where a 1-BST difference, against a ladder whose mean absolute
    deviation is 1.9 BST, would be enough to overturn an assignment that was read off
    the feasibility matrix. A tie is not a reason to change the plan."""
    # A missed floor disqualifies under BOTH sorts, not just evidence. It used to
    # disqualify only under evidence, on the reasoning that a near-miss is worth
    # seeing while the curve is being tuned -- but floors now include the mode's own
    # setter and abuser, so a strength-sorted default could pick a plan that CLAIMS
    # sand and did not build it. That is the defect this whole pass exists to remove,
    # and which sort you asked for is not a reason to reintroduce it. The sort chooses
    # between plans that build; it does not decide what counts as built.
    if how == "strength":
        return (s["gated"], s["met"] < s["need"], abs(s["gap"]), -s["evidence"],
                not s["incumbent"])
    return (s["gated"], s["met"] < s["need"], -s["evidence"], abs(s["gap"]),
            not s["incumbent"])


# ---------------------------------------------------------------- output
def label(s):
    """"balance + sand" / "offense" / "flat quota" -- one plan, one string."""
    return (s["archetype"] or "flat quota") + (" + " + s["mode"] if s["mode"] else "")


def show(ctx, how):
    spine = ", ".join(n if w == 1 else f"{n}*" for n, w in ctx["spine"])
    print(f'\n#### {ctx["label"]} — {ctx["id"]}')
    print(f'     {ctx["kind"]}, gym-{ctx["stage"] + 1} band, lv {ctx["level"]}, '
          f'target eBST {ctx["target"]}, theme {ctx["theme"] or "—"}')
    print(f'     keeps  {spine or "—"}' + ("   (* = starter branch, 1/3 each)"
                                           if any(w != 1 for _n, w in ctx["spine"])
                                           else ""))
    if ctx["core"]:
        print(f'     spine  {", ".join(ctx["core"])}   '
              f'(in >= {CORE_MIN} of their fights)')
    if ctx["warn"]:
        print(f'     note   {ctx["warn"]}')
    ev, rejected = ctx["plans"]["evidence"], ctx["plans"]["rejected"]
    for m in TS.MODE_ROLES:
        # A mode can be a candidate WITHOUT passing the gates -- propose() always
        # keeps today's plan on the list so a person can see what it costs. Saying
        # "proposed" for that is how gym 1 appeared to still be proposing rain after
        # the gate that rejects it was already working.
        if m in rejected:
            why = rejected[m] + ("   [today's plan]" if m in ctx["plans"]["modes"]
                                 else "")
        else:
            why = "proposed"
        print(f'     {m:<12}{ev[m]:>6}   {why}')

    got = candidates(ctx, how)
    print(f'\n     {"plan":<26}{"ev":>6}{"floors":>8}{"gap":>6}   roster')
    for i, s in enumerate(got):
        floors = "%d/%d" % (s["met"], s["need"])
        miss = "  missing " + "/".join(s["missed"]) if s["missed"] else ""
        if s["gated"]:
            miss += "  [gated: %s]" % ctx["plans"]["rejected"][s["mode"]]
        print(f'   {"*" if i == 0 else " "} {label(s):<26}{s["evidence"]:>6}'
              f'{floors:>8}{s["gap"]:>+6}   '
              + " ".join(m["species"].title() for m in s["team"]) + miss)
    best = got[0]
    now = next((s for s in got if s["incumbent"]), best)
    tail = ""
    # Two different reasons a fight ends up with no mode, and saying the wrong one
    # sends you looking for a bug that is not there: under --sort strength gym 6's
    # sand BUILDS (3/3) and simply costs 18 more BST than going without.
    moded = [s for s in got if s["mode"] and not s["gated"]]
    if best["mode"] is None and moded:
        tail = (" — every mode-carrying plan missed a floor it could not fill"
                if all(s["missed"] for s in moded)
                else " — the mode plans build; they just land further from the curve")
    elif not best["incumbent"]:
        tail = (f' — CHANGES the plan (today: {label(now)}, '
                f'ev {now["evidence"]}, {now["met"]}/{now["need"]}, '
                f'gap {now["gap"]:+d})')
    print(f'     default: {label(best)}{tail}')
    return got


PLANS_DOC = ("Per-fight plan for generate_bosses.py and generate_trainers.py. They "
             "read `archetype` and `mode` ONLY; every other field is why, and is for "
             "a person. `chosen: user` is a hand-picked plan and fight_context.py "
             "--write leaves it alone; `chosen: default` is this tool's pick and is "
             "overwritten on every --write. A fight that is absent gets the static "
             "default in generate_bosses.ARCHETYPE / MODE, which is what makes a "
             "clean checkout reproduce the shipped teams.")


def save(fights_, how="evidence"):
    """Replace the plans file. `fights_` is the whole {id: entry} map."""
    with open(G.PLANS_PATH, "w", encoding="utf-8") as fh:
        json.dump({"_doc": PLANS_DOC, "version": PLANS_VERSION, "sort": how,
                   "fights": fights_}, fh, indent=1)
        fh.write("\n")


def entry(best, rest=(), chosen="default"):
    return {"archetype": best["archetype"], "mode": best["mode"], "chosen": chosen,
            "evidence": best["evidence"], "gap": best["gap"],
            "floors_met": "%d/%d" % (best["met"], best["need"]),
            "alternatives": [[s["archetype"], s["mode"], s["evidence"],
                              "%d/%d" % (s["met"], s["need"]), s["gap"]]
                             for s in rest]}


def record(fid, archetype, mode, extra=None):
    """File one fight's plan as a PERSON's choice. Used by boss_studio.py."""
    fights_ = G.load_plans()
    fights_[fid] = dict(extra or {}, archetype=archetype, mode=mode, chosen="user")
    save(fights_)
    return fights_[fid]


def write(chosen, how):
    """Record the defaults, never overwriting a plan a person picked."""
    old = G.load_plans()
    out, kept = dict(old), 0
    for fid, got in chosen.items():
        if (old.get(fid) or {}).get("chosen") == "user":
            kept += 1
            continue
        out[fid] = entry(got[0], got[1:])
    save(out, how)
    print(f'\n{len(out)} fights -> {os.path.relpath(G.PLANS_PATH)}'
          + (f'   ({kept} left alone: chosen by hand)' if kept else ""))


def main(argv):
    how = "evidence"
    args = list(argv)
    if "--sort" in args:
        i = args.index("--sort")
        how = args[i + 1]
        del args[i:i + 2]
    do_write = "--write" in args
    args = [a for a in args if not a.startswith("--")]
    if how not in ("evidence", "strength"):
        raise SystemExit("--sort takes evidence or strength")

    if "--all" in argv:
        picked = fights()
    else:
        picked = [f for a in args for f in find(a)]
        if not picked:
            raise SystemExit("no fight matched %s — try --all, or an id from it"
                             % (args or "(nothing)"))
    chosen = {}
    for f in picked:
        ctx = derive(f)
        chosen[ctx["id"]] = show(ctx, how)
    if do_write:
        write(chosen, how)


if __name__ == "__main__":
    main(sys.argv[1:])
