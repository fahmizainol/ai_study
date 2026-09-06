#!/usr/bin/env python3
"""Generate the tier suite's rosters as a Ruby data module.

Why this exists: the archetype suite (set_a..set_g, tools/make_gauntlet_teams.py) is
built from curated per-archetype pools -- six offensive mons, six bulky ones, and so
on -- which tests whether an AI result survives a change of roster. It cannot test
whether the AI can pilot a *real* team, because no such team is archetype-pure. Human
teams carry hazard control, speed control and a win condition, and their sets are
defined as much by EV spread and item as by species.

This suite draws instead from Smogon's sample teams (extracted/smogon-teams/), so each
roster is a coherent competitive team that a person built and a tier maintainer
published. Teams within a tier fight each other, which is the matchup they were
designed for.

Two suites, deliberately kept apart:

  archetype  set_a..set_g            roster-invariance    make_gauntlet_teams.py
  tier       gen7ou_a..gen6ou_b      metagame competence  this file

They are separate files with separate seeds because they answer different questions and
their numbers must never be pooled. The separation is physical, not conventional: this
tool cannot re-roll set_b no matter what seed it is given, because it does not write
that file. Set names are tier-qualified rather than continuing the letters, so every
ndjson filename says which suite and which tier it came from -- and so a second author
adding, say, gen9doublesou_a cannot collide with these.

Tier choice is constrained by Reborn's engine, not by team quality. Reborn is gen-7-era
with gen 8 additions, so gen 6-8 teams behave roughly as designed. Gen 1-4 teams import
with 100% clean names and are mechanically meaningless -- a Gen 1 team stripped of Gen 1
mechanics is just six species. Gen 9 loses Tera Blast, Ivy Cudgel and the newest mons.
LC (level 5 + Eviolite) and VGC (level 50, doubles, bring-4) both fight the harness,
which forces level 100 singles.

Eligibility is all-or-nothing per team: six sets resolve or the team is dropped, since a
team missing a member is not the team its author built. Drops are reported, not silent.

Usage:
    python3 make_tier_teams.py              # writes generated/tier_teams_reborn.rb
    python3 make_tier_teams.py --report     # also print eligibility and every drop
"""

import argparse
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import reborn_names as rn

STUDY = Path(__file__).resolve().parents[1]
SOURCE = STUDY / "extracted" / "smogon-teams"
OUT = STUDY / "generated" / "tier_teams_reborn.rb"

# Draw seed for the tier suite. Independent of the archetype suite's seeds; changing it
# re-rolls every tier set and invalidates comparison against recorded tier runs.
DRAW_SEED = 20260906

# Two disjoint draws per tier: one set cannot distinguish "this tier stresses the AI"
# from "these four teams do". gen8ou's 11 eligible teams is what caps this at two.
SETS_PER_TIER = 2
TEAMS_PER_SET = 4

TIERS = ["gen7ou", "gen8ou", "gen8uu", "gen6ou"]

# Team keys are generic and identical across every set, because seat_audit_matchups
# builds its schedule from teams.keys -- tier-specific keys would make the schedule
# differ set to set and break comparability. Real names/authors go in comments.
TEAM_KEYS = [f"team{i + 1}" for i in range(TEAMS_PER_SET)]


def eligible_teams(reborn, tier):
    """-> ([(label, [resolved set, ...]), ...], [(label, reason), ...] dropped)."""
    payload = json.loads((SOURCE / f"{tier}.json").read_text(encoding="utf-8"))
    keep, dropped = [], []
    for index, team in enumerate(payload):
        label = team.get("name") or f"(unnamed #{index})"
        author = team.get("author") or ""
        # An author field is free text from the sample-team thread; it is sometimes a
        # URL rather than a person. Kept for provenance, never parsed.
        if author:
            label = f"{label} — {author}"
        try:
            keep.append((label, [reborn.resolve_set(s) for s in team["data"]]))
        except rn.Unrepresentable as reason:
            dropped.append((label, str(reason)))
    return keep, dropped


def draw(pools, seed):
    """Disjoint draws per tier, from a single seeded RNG consumed in TIERS order.

    Consumed in a fixed order so that adding a tier to the end of TIERS cannot re-roll
    the tiers before it -- the same staging discipline the archetype suite uses.
    """
    rng = random.Random(seed)
    sets = {}
    for tier in TIERS:
        pool = pools[tier]
        want = SETS_PER_TIER * TEAMS_PER_SET
        if len(pool) < want:
            raise SystemExit(
                f"{tier}: {len(pool)} eligible teams, need {want} for "
                f"{SETS_PER_TIER} sets of {TEAMS_PER_SET}")
        picked = rng.sample(range(len(pool)), want)
        for n in range(SETS_PER_TIER):
            chunk = picked[n * TEAMS_PER_SET:(n + 1) * TEAMS_PER_SET]
            name = f"{tier}_{chr(ord('a') + n)}"
            sets[name] = [pool[i] for i in chunk]
    return sets


def ruby_set_entry(resolved):
    """One Pokemon as its Ruby literal. Only non-default fields are emitted."""
    extra = {
        "form": resolved["form"],
        "item": f'"{resolved["item"]}"' if resolved["item"] else None,
        "ability": resolved["ability"],
        "nature": resolved["nature"],
        "evs": "[" + ", ".join(str(v) for v in resolved["evs"]) + "]",
        "ivs": "[" + ", ".join(str(v) for v in resolved["ivs"]) + "]",
        "hptype": f'"{resolved["hptype"]}"' if resolved["hptype"] else None,
    }
    if resolved["form"] == 0:
        del extra["form"]
    if resolved["ivs"] == [31] * 6:
        del extra["ivs"]
    fields = ", ".join(f'"{k}" => {v}' for k, v in extra.items() if v is not None)
    moves = " ".join(resolved["moves"])
    return f'["{resolved["species"]}", %w[{moves}], {{ {fields} }}]'


def ruby_literal(sets):
    lines = [
        "# Tier suite rosters — generated by tools/make_tier_teams.py; do not hand-edit.",
        "# Regenerate to change; the draw seed is fixed in that tool.",
        "#",
        "# Real competitive teams from Smogon's sample threads (extracted/smogon-teams/),",
        "# two disjoint sets per tier. Distinct from the archetype suite (set_a..set_g):",
        "# different question, separate seeds, results are never pooled across suites.",
        "#",
        "# Team keys are generic so the seat-audit schedule is identical across sets.",
        "# Selected at run time via teams= in Data/ai_harness.txt, exactly like set_a.",
        "",
        "module PortableAIRebornTiers",
        "  SETS = {",
    ]
    for name in sorted(sets):
        lines.append(f'    "{name}" => {{')
        for key, (label, party) in zip(TEAM_KEYS, sets[name]):
            safe = label.replace("\n", " ").strip()
            lines.append(f"      # {safe}")
            lines.append(f'      "{key}" => [')
            for resolved in party:
                lines.append(f"        {ruby_set_entry(resolved)},")
            lines[-1] = lines[-1].rstrip(",")
            lines.append("      ],")
        lines[-1] = lines[-1].rstrip(",")
        lines.append("    },")
    lines[-1] = lines[-1].rstrip(",")
    lines += [
        "  }",
        "end",
        "",
        "# Merged into the archetype suite's lookup so teams= resolves either suite by",
        "# name and the harness needs no change. The bundle concatenates the archetype",
        "# roster file first (see tools/build_portable_ai.py), so SETS exists by now.",
        "PortableAIRebornTeams::SETS.merge!(PortableAIRebornTiers::SETS)",
        "",
        "# Which suite a set belongs to, for grouping results. Never pool across suites.",
        "module PortableAIRebornTeams",
        "  SUITES = {",
        '    "archetype" => %w[set_a set_b set_c set_d set_e set_f set_g],',
        f'    "tier" => %w[{" ".join(sorted(sets))}]',
        "  }",
        "end",
        "",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args()

    reborn = rn.Reborn()
    pools, drops = {}, {}
    for tier in TIERS:
        pools[tier], drops[tier] = eligible_teams(reborn, tier)

    if args.report:
        for tier in TIERS:
            total = len(pools[tier]) + len(drops[tier])
            print(f"\n{tier}: {len(pools[tier])}/{total} eligible")
            for label, reason in drops[tier]:
                print(f"    dropped: {label[:52]:54} {reason}")

    sets = draw(pools, DRAW_SEED)
    OUT.write_text(ruby_literal(sets), encoding="utf-8")
    mons = sum(len(p) for s in sets.values() for _, p in s)
    print(f"\nwrote {OUT.relative_to(STUDY)}: {len(sets)} sets, "
          f"{len(sets) * TEAMS_PER_SET} teams, {mons} Pokemon")
    for name in sorted(sets):
        print(f"  {name:14} " + " | ".join(l[:26] for l, _ in sets[name]))


if __name__ == "__main__":
    main()
