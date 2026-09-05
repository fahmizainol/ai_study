#!/usr/bin/env python3
"""Where Portable's *move* policy loses to Reborn-Normal, measured from traces.

compare_arms.py closed the switching gap. This measures the three gaps that remained
once switching was at parity, each of which is a missing rule in portable_ai/core.rb:

  heal      recovery clicked on a turn the healer then died ("heal-death"), split by
            speed order — Reborn's recovercode returns 0 when the incoming hit exceeds
            HP-after-heal; Portable's heal rule never looks at incoming damage.
  finish    shadow turns where Portable scored its pick as lethal (>= 600) and
            Reborn-Normal chose a different attack — classified by accuracy, priority
            and self-drop/self-KO, none of which Portable's lethal tiebreak reads.
  race      (0.6.0) traced turns where the actor's own damage_race view said the
            foe needs two hits or fewer, split by speed order, counting how often it
            set up, stayed or left. Run it over two traced runs of the same roster
            differing only in `damage_race` and the delta IS the rule.
  leave     shadow turns where Portable would have switched and Reborn stayed,
            attributed to the gate reason that opened (offline L100 damage estimate
            from the rosters; stages applied, items/abilities/weather ignored), and
            what happened on the turn Reborn stayed.

heal uses live traces (both arms need `commands`); finish/leave use shadow_reborn
records (reborn_6v6_v031_set_*.ndjson carry them). Index 1 is the measured seat.

Usage:
    python3 tools/policy_gaps.py heal   generated/reborn_6v6_v032_set_[abc].ndjson generated/reborn_6v6_fairdiff_set_*.ndjson
    python3 tools/policy_gaps.py finish generated/reborn_6v6_v031_set_*.ndjson
    python3 tools/policy_gaps.py leave  generated/reborn_6v6_v031_set_*.ndjson
    python3 tools/policy_gaps.py race   generated/reborn_6v6_v060trace{,off}_set_c.ndjson
"""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

STUDY = Path(__file__).resolve().parents[1]
PBS = STUDY.parent / "Reborn Yang" / "Reborn Yang" / "PBS" / "PBS"
ROSTER = STUDY / "generated" / "gauntlet_teams_reborn.rb"

MEASURED, OPPONENT = 1, 0
ARMS = {"normal_portable": "portable", "normal_reborn": "reborn"}
SHADOW_ARM = "shadow_reborn"

RECOVERY = {"RECOVER", "ROOST", "SOFTBOILED", "SLACKOFF", "MOONLIGHT", "MORNINGSUN",
            "SYNTHESIS", "MILKDRINK", "REST", "PAINSPLIT"}
PHAZE = {"ROAR", "WHIRLWIND", "DRAGONTAIL", "CIRCLETHROW"}
# function codes: user stat drop after use (Draco Meteor/Overheat 03F, Superpower 03B,
# Close Combat 03C, V-create 03D/03E) and self-KO (Explosion 0E0, Final Gambit 0E1,
# Memento 0E2, Healing Wish 0E5, Lunar Dance 0E7)
SELF_COST = {"03F", "03B", "03C", "03D", "03E", "0E0", "0E1", "0E2", "0E5", "0E7"}


def load_pbs():
    moves, byname = {}, {}
    for line in (PBS / "moves.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        p = line.split(",")
        if len(p) > 12 and p[0].strip().isdigit():
            d = dict(name=p[1], func=p[3], power=int(p[4] or 0), type=p[5], cat=p[6],
                     acc=int(p[7] or 0), prio=int(p[11]))
            moves[int(p[0])] = d
            byname[p[1]] = d
    species, cur = {}, None
    for line in (PBS / "pokemon.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"\[(\d+)\]", line)
        if m:
            cur = int(m.group(1))
            species[cur] = {}
        elif cur and "=" in line:
            k, v = line.split("=", 1)
            species[cur][k.strip()] = v.strip()
    types, tcur = {}, None
    for line in (PBS / "types.txt").read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"\[(\d+)\]", line)
        if m:
            tcur = int(m.group(1))
            types[tcur] = {}
        elif tcur is not None and "=" in line:
            k, v = line.split("=", 1)
            types[tcur][k.strip()] = v.strip()
    if not moves or not species or not types:
        raise SystemExit(f"could not parse PBS under {PBS}")
    return moves, byname, species, {v["InternalName"]: k for k, v in types.items()}, types


def load_roster():
    roster = {}
    for m in re.finditer(r'\["([A-Z0-9]+)", %w\[([A-Z0-9 ]+)\]\]', ROSTER.read_text()):
        roster.setdefault(m.group(1), m.group(2).split())
    return roster


def records(paths, arms):
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            rec = json.loads(line)
            if rec.get("arm") in arms and rec.get("commands"):
                yield rec


def command_turns(rec):
    """(entry, me, foe, round_end actors after it) for each command phase."""
    cmds = rec["commands"]
    for i, entry in enumerate(cmds):
        if entry.get("phase") != "command":
            continue
        actors = {a["index"]: a for a in entry.get("actors", [])}
        me, foe = actors.get(MEASURED), actors.get(OPPONENT)
        if not me or not foe:
            continue
        after = next((x for x in cmds[i + 1:] if x.get("phase") == "round_end"), None)
        after = {a["index"]: a for a in after["actors"]} if after else {}
        yield entry, me, foe, after


def left_field(me, after):
    """True when the measured battler is no longer the active one after the round."""
    am = after.get(MEASURED)
    return (not am) or am["party_slot"] != me["party_slot"]


class Estimator:
    """L100, 31 IV / 85 EV, neutral nature — how the gauntlet builds parties."""

    def __init__(self, species, tname, types):
        self.species, self.tname, self.types = species, tname, types

    def stats(self, sp):
        b = [int(x) for x in self.species[sp]["BaseStats"].split(",")]
        return dict(hp=2 * b[0] + 162, atk=2 * b[1] + 57, dfn=2 * b[2] + 57,
                    spe=2 * b[3] + 57, spa=2 * b[4] + 57, spd=2 * b[5] + 57)

    @staticmethod
    def stage(x):
        return (2 + x) / 2 if x >= 0 else 2 / (2 - x)

    def eff(self, atk, sp):
        r = 1.0
        for d in {sp.get("Type1"), sp.get("Type2")}:
            if not d:
                continue
            t = self.types[self.tname[d]]
            if atk in t.get("Weaknesses", "").split(","):
                r *= 2
            elif atk in t.get("Resistances", "").split(","):
                r *= 0.5
            elif atk in t.get("Immunities", "").split(","):
                r *= 0
        return r

    def damage_pct(self, att, dfn, mv, ast, dst):
        if mv["power"] == 0:
            return 0.0
        a, d = self.stats(att), self.stats(dfn)
        if mv["cat"] == "Physical":
            A, D = a["atk"] * self.stage(ast[1]), d["dfn"] * self.stage(dst[2])
        else:
            A, D = a["spa"] * self.stage(ast[4]), d["spd"] * self.stage(dst[5])
        base = (42 * mv["power"] * A / D) / 50 + 2
        sp = self.species[att]
        stab = 1.5 if mv["type"] in (sp.get("Type1"), sp.get("Type2")) else 1.0
        return base * stab * self.eff(mv["type"], self.species[dfn]) * 0.925 / d["hp"] * 100

    def speed(self, sp, st):
        return self.stats(sp)["spe"] * self.stage(st[3])


def cmd_heal(args, moves, byname, species, tname, types):
    est = Estimator(species, tname, types)
    S = defaultdict(Counter)
    for rec in records(args.results, ARMS):
        arm = ARMS[rec["arm"]]
        for entry, me, foe, after in command_turns(rec):
            if me.get("choice") != 1:
                continue
            S[arm]["turns"] += 1
            if moves.get(me["move_id"], {}).get("name") not in RECOVERY:
                continue
            if foe.get("choice") == 1 and moves.get(foe["move_id"], {}).get("name") in PHAZE:
                continue
            hp = me["hp"] / me["totalhp"]
            mst = [s or 0 for s in me["stages"]]
            fst = [s or 0 for s in foe["stages"]]
            order = "faster" if est.speed(me["species"], mst) > est.speed(foe["species"], fst) else "slower"
            band = "<25" if hp < .25 else "<50" if hp < .5 else "<80" if hp < .8 else ">=80"
            dead = left_field(me, after)
            for key in ("all", band, order):
                S[arm]["heals " + key] += 1
                S[arm]["died " + key] += dead
    print("Recovery clicked, then the healer left the field that same round (phazes excluded).")
    print("Speed order is estimated from base stats and stages.\n")
    for arm in ("reborn", "portable"):
        s = S[arm]
        if not s["turns"]:
            continue
        print(f"{arm:9} {s['heals all']} heals over {s['turns']} move turns "
              f"({s['heals all'] / s['turns'] * 100:.1f}%)")
        for key in ("all", "<25", "<50", "<80", ">=80", "faster", "slower"):
            n = s["heals " + key]
            print(f"   {key:7} heals {n:4}  died {s['died ' + key]:4}  ({s['died ' + key] / max(1, n) * 100:4.0f}%)")


def cmd_finish(args, moves, byname, species, tname, types):
    total = agree = 0
    c, pairs = Counter(), Counter()
    for rec in records(args.results, {SHADOW_ARM}):
        shadow = {e["turn"]: e for e in rec.get("portable_shadow") or [] if e.get("actor") == MEASURED}
        for entry, me, foe, after in command_turns(rec):
            plan = shadow.get(entry["turn"])
            if not plan or plan["type"] != "move" or plan.get("score", 0) < 600:
                continue
            total += 1
            pm = byname.get(plan["move_id"])
            if me.get("choice") != 1 or not pm:
                c["reborn did not attack"] += 1
                continue
            hm = moves.get(me["move_id"])
            if hm["name"] == pm["name"]:
                agree += 1
                continue
            tags = []
            if hm["power"] == 0:
                tags.append("reborn used a status/recovery move")
            else:
                if hm["prio"] > 0 and pm["prio"] <= 0:
                    tags.append("reborn: priority move")
                if hm["acc"] and pm["acc"] and hm["acc"] > pm["acc"]:
                    tags.append("reborn: more accurate")
                if pm["func"] in SELF_COST and hm["func"] not in SELF_COST:
                    tags.append("portable: self-drop / self-KO move")
                if hm["acc"] and pm["acc"] and hm["acc"] < pm["acc"]:
                    tags.append("reborn: LESS accurate")
                if not tags:
                    tags.append("other (mostly Reborn's roulette among equal KOs)")
            for t in tags:
                c[t] += 1
            pairs[(hm["name"], pm["name"])] += 1
    print(f"Portable-lethal shadow decisions: {total}; same move {agree}; "
          f"different {total - agree - c['reborn did not attack']}\n")
    for k, v in c.most_common():
        print(f"{v:5d}  {k}")
    print("\ntop (reborn, portable) pairs:")
    for k, v in pairs.most_common(12):
        print(f"{v:4d}  {k[0]:>14} vs {k[1]}")


def cmd_leave(args, moves, byname, species, tname, types):
    est = Estimator(species, tname, types)
    roster = load_roster()
    c, per_arch, stayed = Counter(), Counter(), Counter()
    for rec in records(args.results, {SHADOW_ARM}):
        shadow = {e["turn"]: e for e in rec.get("portable_shadow") or [] if e.get("actor") == MEASURED}
        arch = rec.get("right_test_team")
        for entry, me, foe, after in command_turns(rec):
            plan = shadow.get(entry["turn"])
            if not plan or plan["type"] != "switch" or me.get("choice") == 2:
                continue
            ms, fs = me["species"], foe["species"]
            mst = [s or 0 for s in me["stages"]]
            fst = [s or 0 for s in foe["stages"]]
            mine = [byname[n] for n in roster.get(species[ms]["InternalName"], []) if n in byname]
            theirs = [byname[n] for n in roster.get(species[fs]["InternalName"], []) if n in byname]
            best = max([est.damage_pct(ms, fs, m, mst, fst) for m in mine] or [0])
            incoming = max([est.damage_pct(fs, ms, m, fst, mst) for m in theirs] or [0])
            hp = me["hp"] / me["totalhp"] * 100
            foe_hp = foe["hp"] / foe["totalhp"] * 100
            neg = sum(s for s in mst[1:6] if s < 0)
            reasons = []
            if best == 0:
                reasons.append("no_effective_move")
            elif best < 10:
                reasons.append("weak_current_attacks")
            if incoming >= hp and hp >= 50:
                reasons.append("lethal_while_healthy")
            if neg <= -3:
                reasons.append("bad_stats")
            if not reasons:
                reasons.append("unattributed (Leech Seed/Yawn/Toxic chip or estimate error)")
            c["+".join(reasons)] += 1
            per_arch[(arch, reasons[0])] += 1
            if reasons[0] == "lethal_while_healthy":
                order = "faster" if est.speed(ms, mst) > est.speed(fs, fst) else "slower"
                k = (order, "can KO" if best >= foe_hp else "no KO")
                stayed[k + ("n",)] += 1
                stayed[k + ("died",)] += left_field(me, after)
                stayed[k + ("koed",)] += bool(after.get(OPPONENT)) and after[OPPONENT]["party_slot"] != foe["party_slot"]
    print(f"Shadow turns where Portable would switch and Reborn-Normal stayed: {sum(c.values())}\n")
    for k, v in c.most_common():
        print(f"{v:5d}  {k}")
    print("\nprimary reason by measured archetype:")
    for arch in ("offense", "balance", "bulky", "speed"):
        row = sorted(((v, k) for (a, k), v in per_arch.items() if a == arch), reverse=True)
        print(f"  {arch:8} " + "  ".join(f"{k.split(' ')[0]}={v}" for v, k in row))
    print("\nlethal_while_healthy: what happened on the turn Reborn stayed in:")
    for k in sorted({k[:2] for k in stayed}):
        n = stayed[k + ("n",)]
        print(f"  {k[0]:6} {k[1]:7} n={n:3}  Reborn's battler died {stayed[k + ('died',)]:3} "
              f"({stayed[k + ('died',)] / max(1, n) * 100:3.0f}%)  it KO'd the foe "
              f"{stayed[k + ('koed',)]:3} ({stayed[k + ('koed',)] / max(1, n) * 100:3.0f}%)")



# Reasons the core attaches to a setup move, whichever branch of the setup rule fired.
# Reading the reason list rather than a move-name table keeps this metric tied to the
# rule under test instead of to a list that has to be maintained alongside effects.rb.
SETUP_REASONS = {"first_setup", "repeated_setup", "unsafe_setup", "setup_into_2hko",
                 "contrary_setup", "setup_vs_unaware"}


def race_of(entry):
    """The worst race in this turn's view: the foe that kills the actor soonest."""
    view = entry.get("view") or {}
    races = [r for r in (view.get("race") or {}).values() if r]
    if not races:
        return None
    def rank(r):
        theirs = r.get("theirs")
        return (0 if r.get("winning") is False else 1 if r.get("winning") is None else 2,
                99 if theirs is None else theirs)
    return sorted(races, key=rank)[0]


def chosen_reasons(entry):
    for cand in entry.get("candidates") or []:
        if cand.get("type") == entry.get("type") and cand.get("slot") == entry.get("slot"):
            return {r[0] for r in (cand.get("reasons") or [])}
    return set()


def cmd_race(args, moves, byname, species, tname, types):
    """What the actor did on the turns its own race view said it was in trouble.

    The point of this metric is that a rule's BEHAVIOURAL effect is measurable even
    when its effect on wins is not: 0.3.0 through 0.5.0 each changed a mechanism and
    none moved wins detectably. Run it over two traced runs of the same roster that
    differ only in `damage_race` and the delta is the rule.
    """
    buckets = defaultdict(Counter)
    for path in args.results:
        tag = Path(path).stem
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            rec = json.loads(line)
            if rec.get("arm") not in ARMS:
                continue
            for entry in rec.get("portable_trace") or []:
                if entry.get("actor") != MEASURED:
                    continue
                race = race_of(entry)
                if not race:
                    continue
                theirs = race.get("theirs")
                if theirs is None or theirs > 2:
                    continue
                reasons = chosen_reasons(entry)
                if entry.get("type") == "switch":
                    what = "left"
                elif reasons & SETUP_REASONS:
                    what = "set up"
                else:
                    what = "stayed"
                key = (tag, "2HKO" if theirs == 2 else "1HKO",
                       {True: "faster", False: "slower"}.get(race.get("faster"), "order?"))
                buckets[key][what] += 1
                buckets[key]["n"] += 1
    print("Turns the actor's own race view called losable (foe needs <= 2 hits)\n")
    print(f"{'run':34} {'race':6} {'order':7} {'n':>5} {'set up':>8} {'stayed':>8} {'left':>6}")
    for key in sorted(buckets):
        b = buckets[key]
        print(f"{key[0]:34} {key[1]:6} {key[2]:7} {b['n']:5d} "
              f"{b['set up']:8d} {b['stayed']:8d} {b['left']:6d}")
    for tag in sorted({k[0] for k in buckets}):
        rows = [b for k, b in buckets.items() if k[0] == tag]
        n = sum(b["n"] for b in rows)
        su = sum(b["set up"] for b in rows)
        print(f"\n{tag}: {su} setups over {n} losable turns "
              f"({su / max(1, n) * 100:.1f}%)")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("metric", choices=["heal", "finish", "leave", "race"])
    parser.add_argument("results", nargs="+", type=Path)
    args = parser.parse_args()
    pbs = load_pbs()
    {"heal": cmd_heal, "finish": cmd_finish, "leave": cmd_leave,
     "race": cmd_race}[args.metric](args, *pbs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
