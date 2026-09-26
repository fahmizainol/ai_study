#!/usr/bin/env python3
"""What a real gen 7 attacker is built like, and how each kind of attacker did against the
Run & Bun bosses -- next to the generator's attackers.

An "attacker" is composition.kind()'s class: 3+ damaging moves, or a Choice item, Life Orb
or Expert Belt. The profile is items, move shape (attack count, STAB, pivot, setup,
priority), base stats and Speed (Choice Scarf counted x1.5), tier and the species that
recur; the performance half joins each attacker slot to its battles in deck_slots.collect()
and groups them by item, setup, Speed, attacking stat, tier and STAB count.

Real teams are the 78 pilotable gen 7 teams (rnb_vs_gen7); their performance is the 25 ms
run (rnb_vs_gen7_25ms), the only real-team run on this machine. The generator arm with
battle data is the walls arm (rnb_vs_gen_defense, 100 ms). NEW names a generator roster to
profile (structure only), with its trainers folder read alongside when present.

    REALIDEA_PBS=<game>/PBS python3 tools/rnb/attacker_profile.py [NEW_ARM]   # default rnb_vs_gen_atk
"""
import collections
import os
import re
import statistics as st
import sys

import composition as C
import deck_slots as D
from paths import STUDY, TOOLS

sys.path.insert(0, TOOLS)
import smogon_corpus as SC  # noqa: E402
from team_shape import ROLE_MOVES  # noqa: E402

G = os.path.join(STUDY, "generated")
tid = C.tid
CHOICE = {"choiceband", "choicespecs", "choicescarf"}
BOOST = {"lifeorb", "expertbelt"}
OTHER = CHOICE | BOOST | {"focussash", "leftovers", "assaultvest"}


def sets(exp, side, keep=None):
    """One row per slot of every team file in generated/<exp>/teams/<side>."""
    d = os.path.join(G, exp, "teams", side)
    out = []
    for f in sorted(os.listdir(d)):
        if keep is not None and f not in keep:
            continue
        p = os.path.join(d, f)
        blocks = open(p, encoding="utf-8").read().strip().split("\n\n")
        for b, m in zip(blocks, C.team(p)):
            sp, _, item = b.split("\n")[0].partition(" @ ")
            e = C.DEX[tid(sp)]
            e = C.MEGA.get((tid(e.get("baseSpecies", e["name"])), tid(item)), e)
            bs = e["baseStats"]
            moves = [re.sub(r"[^A-Z]", "", ln[2:].upper()) for ln in b.split("\n") if ln.startswith("- ")]
            atk = list(m["attacks"])
            out.append({"team": f, "species": tid(sp), "name": e["name"], "item": m["item"], "kind": C.kind(m),
                        "tier": SC.tier(e["name"]), "band": SC.band(e["name"]), "bst": sum(bs.values()),
                        "spe": bs["spe"] * (1.5 if m["item"] == "choicescarf" else 1),
                        "off": max(bs["atk"], bs["spa"]), "bulk": bs["hp"] + bs["def"] + bs["spd"],
                        "n_atk": len(atk),
                        "stab": sum(C.MV[tid(a)]["type"] in e["types"] for a in atk),
                        "strong": sum(C.MV[tid(a)].get("bp", 0) >= 80 for a in atk),
                        "setup": bool(set(moves) & ROLE_MOVES["setup"]),
                        "pivot": bool(set(moves) & ROLE_MOVES["pivot"]),
                        "priority": bool(set(moves) & ROLE_MOVES["priority"]),
                        "mega": m["item"].endswith("ite") and m["item"] != "eviolite",
                        "types_hit": len({C.MV[tid(a)]["type"] for a in atk})})
    return out


def share(rows, f):
    return 100 * sum(f(r) for r in rows) / max(len(rows), 1)


def profile(label, rows):
    a = [r for r in rows if r["kind"] == "attacker"]
    print("\n### %s: %d attacker slots of %d (%.0f%%)" % (label, len(a), len(rows), 100 * len(a) / len(rows)))
    print("  items     Choice %3.0f%%  Life Orb/Belt %3.0f%%  mega %3.0f%%  Sash %3.0f%%  Leftovers %3.0f%%  Vest %3.0f%%  other %3.0f%%" % (
        share(a, lambda r: r["item"] in CHOICE), share(a, lambda r: r["item"] in BOOST), share(a, lambda r: r["mega"]),
        share(a, lambda r: r["item"] == "focussash"), share(a, lambda r: r["item"] == "leftovers"),
        share(a, lambda r: r["item"] == "assaultvest"),
        share(a, lambda r: r["item"] not in OTHER and not r["mega"])))
    print("  moves     4 attacks %3.0f%%  3 attacks %3.0f%%  setup %3.0f%%  pivot %3.0f%%  priority %3.0f%%  STAB attacks %.1f  attacks 80+ BP %.1f  types hit %.1f" % (
        share(a, lambda r: r["n_atk"] >= 4), share(a, lambda r: r["n_atk"] == 3), share(a, lambda r: r["setup"]),
        share(a, lambda r: r["pivot"]), share(a, lambda r: r["priority"]),
        st.mean(r["stab"] for r in a), st.mean(r["strong"] for r in a), st.mean(r["types_hit"] for r in a)))
    print("  stats     BST %.0f  best attack %.0f  Speed %.0f (Scarf x1.5)  Speed 100+ %3.0f%%  bulk %.0f" % (
        st.mean(r["bst"] for r in a), st.mean(r["off"] for r in a), st.mean(r["spe"] for r in a),
        share(a, lambda r: r["spe"] >= 100), st.mean(r["bulk"] for r in a)))
    b = collections.Counter(r["band"] for r in a)
    print("  tier      " + "  ".join("%s %2.0f%%" % (k, 100 * b[k] / len(a)) for k in ("Uber", "OU", "UU", "RU", "NU", "low", "?")))
    top = collections.Counter(r["name"] for r in a).most_common(12)
    print("  species   " + ", ".join("%s %d" % (n, c) for n, c in top))
    return a


def perf(label, arm, rows, per):
    a = {(r["team"], r["species"]): r for r in rows if r["kind"] == "attacker"}
    stats = []
    for (t, sp), c in per[arm].items():
        if (t, sp) in a and c["battles"]:
            r, n = a[t, sp], c["battles"]
            stats.append((r, c["kos"] / n, c["dealt"] / n, c["fainted"] / n, c["onfield"] / n))
    if not stats:
        return
    print("\n### %s: how the attacker groups did (%s)" % (label, arm))
    print("  %-26s %5s %7s %7s %6s %5s" % ("group", "slots", "KO/b", "dealt%", "faint%", "turns"))

    def row(name, f):
        g = [s for s in stats if f(s[0])]
        if len(g) < 5:
            return
        print("  %-26s %5d %7.2f %6.0f%% %6.0f%% %5.1f" % (
            name, len(g), st.mean(x[1] for x in g), st.mean(x[2] for x in g),
            100 * st.mean(x[3] for x in g), st.mean(x[4] for x in g)))
    row("all attackers", lambda r: True)
    row("Choice item", lambda r: r["item"] in CHOICE)
    row("  Scarf", lambda r: r["item"] == "choicescarf")
    row("  Band / Specs", lambda r: r["item"] in ("choiceband", "choicespecs"))
    row("Life Orb / Expert Belt", lambda r: r["item"] in BOOST)
    row("mega", lambda r: r["mega"])
    row("Focus Sash", lambda r: r["item"] == "focussash")
    row("Leftovers", lambda r: r["item"] == "leftovers")
    row("with setup", lambda r: r["setup"])
    row("no setup", lambda r: not r["setup"])
    row("Speed 100+", lambda r: r["spe"] >= 100)
    row("Speed under 100", lambda r: r["spe"] < 100)
    row("best attack 120+", lambda r: r["off"] >= 120)
    row("best attack under 100", lambda r: r["off"] < 100)
    row("Uber / OU", lambda r: r["band"] in ("Uber", "OU"))
    row("UU / RU / NU", lambda r: r["band"] in ("UU", "RU", "NU"))
    row("PU and below", lambda r: r["band"] == "low")
    row("2+ STAB attacks", lambda r: r["stab"] >= 2)
    row("0-1 STAB attacks", lambda r: r["stab"] <= 1)


def main():
    new_arm = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("NEW", "rnb_vs_gen_atk")
    keep = set(os.listdir(os.path.join(G, "rnb_vs_gen7_collage", "teams", "smogon")))   # the pilotable 78
    real = sets("rnb_vs_gen7", "smogon", keep)
    dfg = sets("rnb_vs_gen_defense", "gen")
    dft = sets("rnb_vs_gen_trainers_defense", "gen")
    tr_arm = new_arm.replace("rnb_vs_gen_", "rnb_vs_gen_trainers_")
    new = sets(new_arm, "gen") if os.path.isdir(os.path.join(G, new_arm)) else []
    if new and os.path.isdir(os.path.join(G, tr_arm)):
        new += sets(tr_arm, "gen")
    profile("real gen 7", real)
    profile("generator, walls arm (gyms + trainers)", dfg + dft)
    if new:
        profile("generator, %s (gyms + trainers)" % new_arm, new)
    per, _kinds, _record = D.collect()
    perf("real gen 7 at 25 ms", "rnb_vs_gen7_25ms", real, per)
    perf("generator walls arm at 100 ms", "rnb_vs_gen_defense", dfg, per)


if __name__ == "__main__":
    main()
