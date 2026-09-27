#!/usr/bin/env python3
"""The "breaking core" model (Pinkacross, gen 9 OU singles) read off real Smogon teams.

The video builds a team around one breaking core: a breaker few things can switch into, plus
a partner that removes what walls it -- ideally a second breaker, so that answering one opens
the way for the other (Latios + Kingambit) -- and adds support afterwards (RNB-STUDY.md §10).
Checked here on the real teams already played on this machine, by type:

  breaker 1   attacking set, best attacking stat counting a mega (anchor_test.py)
  its walls   types that resist every attack of the breaker's own type (its STAB)
  remover     a teammate whose attacks hit those walls super-effectively
  2nd breaker the remover, when it is itself on an attacking set
  mutual      each breaker hits the other's walls
  support     speed control / priority / hazards / removal present on the team

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/breaking_core.py
"""
import os
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import deck_slots as DS  # noqa: E402
import core_on_real as CR  # noqa: E402
import anchor_test as AT  # noqa: E402
from make_battle_teams import Exporter  # noqa: E402
from paths import pokedex  # noqa: E402

GROUPS = {"mainstream gen 7": ("rnb_vs_gen7_25ms", "rnb_vs_gen7_10ms"),
          "monotype gen 7-9": ("rnb_vs_mono_10ms", "rnb_vs_mono8_10ms", "rnb_vs_mono7_10ms")}
SPEED = {"thunderwave", "icywind", "stickyweb", "tailwind", "trickroom", "glare", "stunspore",
         "electroweb", "nuzzle", "bulldoze", "rocktomb", "choicescarf"}
PRIORITY = {"suckerpunch", "aquajet", "bulletpunch", "machpunch", "iceshard", "shadowsneak",
            "extremespeed", "accelerock", "vacuumwave", "quickattack", "fakeout", "firstimpression",
            "jetpunch", "grassyglide"}


def atk(m):
    return max(m["form"]["atk"], m["form"]["spa"])


def attacks(m):
    return {CR.C.MV[x]["type"] for x in m["moves"] if CR.C.MV.get(x, {}).get("bp")}


def walls(m):
    stab = attacks(m) & set(m["types"]) or attacks(m)
    return [t for t in CR.TYPES if stab and all(CR.eff(h, [t]) < 1 for h in stab)]


def breaks(m, targets):
    return [t for t in targets if any(CR.eff(h, [t]) > 1 for h in attacks(m))]


def analyse(ms, kd, kpb):
    attackers = [m for m in ms if AT.attacking(m, kd.get(m["sp"]))]
    pool = attackers or list(ms)
    b1 = max(pool, key=lambda m: (atk(m), sum(m["form"].values())))
    w1 = walls(b1)
    others = [m for m in ms if m is not b1]
    rem = max(others, key=lambda m: (len(breaks(m, w1)), m in attackers, atk(m)), default=None)
    rem = rem if rem and w1 and breaks(rem, w1) else None
    b2 = rem if rem in attackers else None
    mutual = bool(b2 and walls(b2) and breaks(b1, walls(b2)))
    moves = {x for m in ms for x in m["moves"]} | {m["item"] for m in ms}
    core = [x for x in (b1, rem) if x]
    return {"walled": bool(w1), "remover": rem is not None, "second": b2 is not None, "mutual": mutual,
            "attackers": len(attackers), "speed": bool(moves & SPEED), "priority": bool(moves & PRIORITY),
            "core_kos": sum(kpb[x["sp"]] for x in core), "team_kos": sum(kpb.values()), "core_n": len(core),
            "b1": b1, "w1": w1, "rem": rem, "b2": b2}


def main():
    per, kinds, record = DS.collect()
    ex = Exporter(pokedex())
    fmt = lambda m: f"{m['name']}{' (mega)' if m['mega'] else ''}" if m else "-"  # noqa: E731
    for label, arms in GROUPS.items():
        rows = []
        for arm in arms:
            for team in sorted({t for (t, sp) in per.get(arm, {})}):
                path = os.path.join(DS.G, arm, "teams", "smogon", team)
                if not os.path.exists(path):
                    continue
                ms = CR.typed(AT.members(path, ex), ex)
                if any(per[arm][team, m["sp"]]["battles"] < 2 for m in ms):
                    continue
                kpb = {m["sp"]: per[arm][team, m["sp"]]["kos"] / per[arm][team, m["sp"]]["battles"] for m in ms}
                r = analyse(ms, kinds.get((arm, team), {}), kpb)
                w, l = record[arm][team, True], record[arm][team, False]
                r.update(team=team, win=w / max(w + l, 1), ms=ms, kpb=kpb)
                rows.append(r)
        n = len(rows)
        pct = lambda k, rs=rows: 100 * sum(bool(r[k]) for r in rs) / max(len(rs), 1)  # noqa: E731
        print(f"\n## {label}: {n} teams")
        print(f"   breaker 1 has type walls: {pct('walled'):.0f}%   a teammate breaks them: {pct('remover'):.0f}%   "
              f"that teammate is a 2nd breaker: {pct('second'):.0f}%   mutual pair: {pct('mutual'):.0f}%")
        att = [r["attackers"] for r in rows]
        print(f"   members on attacking sets: mean {st.mean(att):.1f} (" +
              ", ".join(f"{k}: {100 * att.count(k) / n:.0f}%" for k in range(0, 7) if att.count(k)) + ")")
        print(f"   speed control on the team: {pct('speed'):.0f}%   priority: {pct('priority'):.0f}%")
        core = [r for r in rows if r["core_n"] == 2]
        if core:
            print(f"   breaker + remover make {100 * sum(r['core_kos'] for r in core) / sum(r['team_kos'] for r in core):.0f}% "
                  f"of their team's KOs (two of six = 33%)")
        for key, name in (("mutual", "a mutual breaking pair"), ("second", "a 2nd breaker"), ("remover", "a wall-remover")):
            yes = [r["win"] for r in rows if r[key]]
            no = [r["win"] for r in rows if not r[key]]
            if yes and no:
                print(f"   win rate with {name}: {100 * st.mean(yes):.0f}% ({len(yes)} teams)  without: {100 * st.mean(no):.0f}% ({len(no)})")
        for k in sorted({r['attackers'] for r in rows}):
            rs = [r["win"] for r in rows if r["attackers"] == k]
            if len(rs) >= 8:
                print(f"      {k} attackers: win {100 * st.mean(rs):.0f}% ({len(rs)} teams)")
        print("   examples:")
        for r in [r for r in rows if r["mutual"]][:4] + [r for r in rows if r["remover"] and not r["mutual"]][:2]:
            print(f"     {r['team']}: {fmt(r['b1'])} walled by {'/'.join(r['w1'])}; "
                  f"{fmt(r['rem'])} breaks them{' and is a 2nd breaker' if r['b2'] else ''}"
                  f"{' (mutual)' if r['mutual'] else ''}; KOs/battle {r['kpb'][r['b1']['sp']]:.1f} + {r['kpb'][r['rem']['sp']]:.1f}")


if __name__ == "__main__":
    main()
