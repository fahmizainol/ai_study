#!/usr/bin/env python3
"""Score generated boss teams against 54k real ones.

generate_bosses.py is judged today by BOSS-CURVE.md's effective-BST ladder, which is
a statement about how STRONG a team is and says nothing about what it DOES. This is
the missing half: it takes the built teams and asks whether their shape looks like
anything a person has ever posted.

The reference is team_shape.profile() -- role frequencies from the scraped dump, with
per-archetype columns from the teams whose authors named an archetype in the title.

Three questions, in the order they turned out to matter:

  1. Is any role systematically MISSING? (removal: 0/9 bosses, 68% of the corpus)
  2. Do the nine differ from each other as much as nine real teams do? (no: 0.4th
     percentile -- nine RANDOM teams are more varied than nine themed gym leaders)
  3. Does each team's EV split agree with its role shape? (no: the roles are pinned
     by QUOTA, the EVs are inherited from whichever Smogon set was pulled, so the
     two axes move independently and some bosses get hyper-offense stats on a
     balance skeleton)

Read it as a description, not a target. A gym leader is not trying to be a ladder
team: it fights one opponent it cannot scout, at a level cap, from a type theme, and
against an opponent whose own hazards may never appear. Where a gap has a reason,
the reason is worth writing down; where it does not, it is a bug.

Usage:
    boss_diagnostic.py                        # generated/teams_bosses_gyms.json
    boss_diagnostic.py path.json [more.json]
    boss_diagnostic.py --refresh              # rebuild the corpus reference first
    boss_diagnostic.py --matrix               # gym x archetype feasibility (slow)
    boss_diagnostic.py --matrix --mode none   # ... with every assigned mode cleared
"""
import json
import os
import random
import statistics
import sys

import team_shape as TS
from generate_bosses import CHASED_ROLES  # the roles the generator is told to fill

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "..", "generated")
DEFAULT = os.path.join(GEN, "teams_bosses_gyms.json")
# PBS stat order, which is NOT the Showdown order the corpus uses: PBS puts speed
# third. Reading a boss `ev` list with Showdown's order silently swaps Spe and SpA
# and turns every physical sweeper into a special one.
PBS_EV = ["hp", "atk", "def", "spe", "spa", "spd"]
QUOTA_ROLES = [r for r in CHASED_ROLES if r in TS.ROLE_MOVES]


def load(path):
    with open(path, encoding="utf-8") as fh:
        for team in json.load(fh):
            mons = team.get("mons") or []
            if len(mons) != 6:
                continue
            yield team.get("name") or team.get("id"), mons


def spread(vectors, idx=None):
    """Mean pairwise L1 distance -- how unalike a set of teams is.

    `idx` restricts the comparison to some of the roles, which is the whole point:
    measured over every role the nine bosses look merely samey, but split by whether
    generate_bosses chases the role, the sameness turns out to live entirely in the
    half it was told to chase."""
    if idx is None:
        idx = range(len(vectors[0]))
    pairs = [(i, j) for i in range(len(vectors)) for j in range(i + 1, len(vectors))]
    return statistics.mean([sum(abs(vectors[i][k] - vectors[j][k]) for k in idx)
                            for i, j in pairs])


def matrix(no_modes=False):
    """Rebuild each gym as each archetype, and report what it costs.

    This is what ARCHETYPE in generate_bosses.py should be read off. Picking the
    assignment by flavour instead puts stall on a theme whose dex cannot supply five
    recovery sets, and the fight quietly comes out as a worse balance team. Slow on
    purpose -- it builds 45 teams.

    `--mode none` clears every assigned mode first. A mode adds a floor of its own,
    so a fight that carries one reports fewer floors met than the same archetype
    would without it -- which is a fact about the mode, not about the archetype, and
    reading the archetype column off it would be reading the wrong thing."""
    import generate_bosses as G

    print("floors met %, curve gap BST -- per gym x archetype"
          + ("  (modes cleared)" if no_modes else "") + "\n")
    print(f"{'gym':<11}{'theme':<9}" + "".join(f"{a[:11]:>15}" for a in TS.ARCHETYPES))
    before, modes = list(G.ARCHETYPE), list(G.MODE)
    if no_modes:
        G.MODE[:] = [None] * len(G.MODE)
    try:
        for i in range(9):
            name = G.CAPS[i]["trainer"]
            row = f"{name:<11}{G.THEME[name][:8]:<9}"
            for a in TS.ARCHETYPES:
                G.ARCHETYPE[i] = a
                gym = G.make_gym(i)
                need = [r for r in gym["floors"] if r != "mega"]
                met = sum(1 for r in need if gym["roles"][r] >= gym["floors"][r])
                gap = (sum(G.ebst(m) for m in gym["team"]) / len(gym["team"])
                       - gym["target"])
                row += f"{100 * met / max(len(need), 1):>9.0f}%{gap:>+6.0f}"
            G.ARCHETYPE[i] = before[i]
            print(row)
    finally:
        G.ARCHETYPE[:] = before
        G.MODE[:] = modes


def main(argv):
    if "--matrix" in argv:
        i = argv.index("--mode") if "--mode" in argv else None
        return matrix(no_modes=i is not None and argv[i + 1:i + 2] == ["none"])
    paths = [a for a in argv if not a.startswith("--")] or [DEFAULT]
    prof = TS.profile(refresh="--refresh" in argv)
    carry, arch = prof["all"]["carry"], prof["archetype"]

    teams = [t for p in paths for t in load(p)]
    if not teams:
        raise SystemExit(f"no six-mon teams in {', '.join(paths)}")
    vec = {name: [TS.role_counts(mons, lambda m: m["moves"])[k] for k in TS.ROLES]
           for name, mons in teams}
    off = {name: TS.team_offence([dict(zip(PBS_EV, m["ev"])) for m in mons])
           for name, mons in teams}

    print(f"{len(teams)} teams vs {prof['all']['n']} corpus teams "
          f"({sum(a['n'] for a in arch.values())} archetype-tagged)\n")

    w = max(len(n) for n, _ in teams) + 1
    print(f"{'team':<{w}}{'lv':>3}  " + "".join(f"{k[:8]:>9}" for k in TS.ROLES)
          + f"{'off%':>7}")
    for name, mons in teams:
        print(f"{name:<{w}}{mons[0]['level']:>3}  "
              + "".join(f"{n:>9}" for n in vec[name]) + f"{off[name]:>6.0f}%")
    print(f"\n{'corpus carry':<{w + 5}}" + "".join(f"{100 * carry[k]:>8.0f}%" for k in TS.ROLES)
          + f"{prof['all']['offence']:>6.0f}%")
    print(f"{'these carry':<{w + 5}}" + "".join(
        f"{100 * sum(1 for v in vec.values() if v[i]) / len(vec):>8.0f}%"
        for i in range(len(TS.ROLES))))

    # 1) roles the corpus expects and these teams do not have
    print("\n--- roles most out of line with the corpus")
    gaps = sorted(TS.ROLES, key=lambda k: -abs(
        carry[k] - sum(1 for v in vec.values() if v[TS.ROLES.index(k)]) / len(vec)))
    for k in gaps[:4]:
        i = TS.ROLES.index(k)
        mine = sum(1 for v in vec.values() if v[i])
        best = max(arch, key=lambda a: arch[a]["carry"][k])
        worst = min(arch, key=lambda a: arch[a]["carry"][k])
        print(f"  {k:<9} {mine}/{len(vec)} here vs {100 * carry[k]:.0f}% of the corpus"
              f"   (by archetype: {worst} {100 * arch[worst]['carry'][k]:.0f}%"
              f" .. {best} {100 * arch[best]['carry'][k]:.0f}%)")

    # 2) are they as unalike as real teams? -- split by whether QUOTA chases the role,
    #    because that split is what turns "these teams are samey" into a cause.
    rows = prof["sample"]["rows"]
    nr = len(TS.ROLES)
    qi = [TS.ROLES.index(k) for k in QUOTA_ROLES]
    oi = [i for i in range(nr) if i not in qi]
    rng = random.Random(11)
    print("\n--- variety: mean pairwise distance between the role vectors")
    print(f"{'':<30}{'these':>8}{'random':>9}{'sd':>7}{'pctile':>9}")
    for label, idx in (("all %d roles" % nr, list(range(nr))),
                       ("the %d generate_bosses chases" % len(qi), qi),
                       ("the %d it does not" % len(oi), oi)):
        null = [spread([rng.choice(rows)[:nr] for _ in range(len(vec))], idx)
                for _ in range(4000)]
        got = spread(list(vec.values()), idx)
        pct = 100 * sum(1 for s in null if s < got) / len(null)
        note = "  <- flatter than random" if pct < 5 else (
               "  <- as varied as real teams" if pct > 50 else "")
        print(f"{label:<30}{got:>8.2f}{statistics.mean(null):>9.2f}"
              f"{statistics.pstdev(null):>7.2f}{pct:>8.1f}%{note}")

    # 3) do roles and EVs tell the same story?
    #
    #    Both reads are crude -- a 1-of-5 guess off eleven bits, and a 1-of-5 guess
    #    off one number -- so they disagree constantly on REAL teams too. Without
    #    that baseline printed next to it, this section reads as a finding when it
    #    is a property of the two readers. It is here because the per-team column is
    #    useful context, not because the rate means anything on its own.
    def two_reads(v, o):
        by_role = min(TS.ARCHETYPES, key=lambda a: sum(
            abs((1 if v[i] else 0) - arch[a]["carry"][k])
            for i, k in enumerate(TS.ROLES)))
        by_ev = min(TS.ARCHETYPES, key=lambda a: abs(arch[a]["offence"] - o))
        return by_role, by_ev

    base = sum(1 for r in rows if len(set(two_reads(r[:nr], r[nr]))) > 1) / len(rows)
    mine = [two_reads(vec[n], off[n]) for n, _ in teams]
    disagree = sum(1 for a, b in mine if a != b)
    print("\n--- archetype read two ways (roles vs EV split)")
    print(f"  these teams disagree {disagree}/{len(mine)} "
          f"({100 * disagree / len(mine):.0f}%);  real teams disagree "
          f"{100 * base:.0f}% of the time -- so only a large gap here means anything")
    print(f"  corpus EV offence by archetype: " + "  ".join(
        f"{a.split()[0][:5]} {arch[a]['offence']:.0f}%" for a in TS.ARCHETYPES))
    print(f"\n{'team':<{w}}{'by roles':>16}{'by EVs':>16}")
    for (name, _), (by_role, by_ev) in zip(teams, mine):
        print(f"{name:<{w}}{by_role:>16}{by_ev:>16}"
              + ("   <- disagree" if by_role != by_ev else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
