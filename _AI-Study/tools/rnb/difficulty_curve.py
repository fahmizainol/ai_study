#!/usr/bin/env python3
"""Run & Bun's difficulty curve, boss and filler, against the level cap in force.

Reads generated/rnb/trainers.json (tools/rnb/parse_trainers.py) and writes one row per
trainer to generated/rnb/rows.json, then prints the per-segment table in RNB-STUDY.md §2.

A SEGMENT is the stretch of trainers fought under one level cap: every trainer takes the
cap of the next boss that raises it ("Mechanic Changes.txt" lists them). Run & Bun has no
EVs and every opponent runs 31 IVs, so a trainer's stats are fully determined by base
stats, level and nature, and the POWER INDEX is exact rather than a guess:

    power = mean over the team of sum(six stats at its level, 31 IV, its nature, 0 EV)
            / the same sum for a reference PLAYER mon: level cap, BST 500, 15 IV, neutral

1.00 is stat parity with a sensible player mon at the cap. Base stats are Showdown's gen 9
numbers -- the docs carry none -- so any species Run & Bun rebalanced is off.

    python3 tools/rnb/difficulty_curve.py
"""
import json
import re
import statistics as st

from paths import out, pokedex

# Trainer index (parse order) of the fight that RAISES each cap, with the cap it raises.
# Read off "Mechanic Changes.txt"; the name check below fails loudly if the sheet moves.
BOSS = {7: ("R104 Grunt", 12, "Petalburg Woods"), 18: ("Museum Grunts", 17, "Museum #2"),
        25: ("Brawly", 21, "Brawly"), 44: ("Roxanne", 25, "Roxanne"),
        54: ("Chelle", 32, "Chelle"), 65: ("Wattson", 35, "Wattson"),
        75: ("Rival CycRd", 38, "Cycling Road"), 91: ("Norman", 42, "Norman"),
        118: ("Vito 1", 48, "Vito"), 142: ("Maxie Chimney", 54, "Maxie"),
        156: ("Flannery", 57, "Flannery"), 214: ("Shelly", 65, "Shelly"),
        217: ("Rival Bridge", 66, "Bridge"), 227: ("Winona", 69, "Winona"),
        249: ("Rival Lilycove", 73, "Lilycove"), 266: ("Archie Pyre", 76, "Archie"),
        283: ("Maxie Hideout", 79, "Maxie"), 292: ("Matt", 81, "Matt"),
        313: ("Tate&Liza", 85, "Liza"), 349: ("Archie Seafloor", 89, "Archie"),
        393: ("Juan", 91, "Juan"), 408: ("Vito 2", 95, "Vito"), 435: ("E4+Wallace", 99, "Wallace")}
FIRST_E4 = 427          # Elite Four and Champion: all bosses, all at cap 99
OPTIONAL_TAB = 8        # the Victory Road tab; its trainers after Vito 2 are optional

NATURE = {"lonely": ("atk", "def"), "brave": ("atk", "spe"), "adamant": ("atk", "spa"),
          "naughty": ("atk", "spd"), "bold": ("def", "atk"), "relaxed": ("def", "spe"),
          "impish": ("def", "spa"), "lax": ("def", "spd"), "timid": ("spe", "atk"),
          "hasty": ("spe", "def"), "jolly": ("spe", "spa"), "naive": ("spe", "spd"),
          "modest": ("spa", "atk"), "mild": ("spa", "def"), "quiet": ("spa", "spe"),
          "rash": ("spa", "spd"), "calm": ("spd", "atk"), "gentle": ("spd", "def"),
          "sassy": ("spd", "spe"), "careful": ("spd", "spa")}
# Items that do not count as a competitive held item.
WEAK_ITEMS = {"", "Oran Berry", "Berry Juice", "Sitrus Berry", "Cheri Berry", "Pecha Berry",
              "Rawst Berry", "Aspear Berry", "Chesto Berry", "Persim Berry", "Lum Berry"}
LEGEND_TAGS = {"Restricted Legendary", "Sub-Legendary", "Mythical", "Paradox"}
ALIAS = {"enamorust": "enamorustherian"}


def dex_key(species):
    k = re.sub(r"[^a-z0-9]", "", species.lower())
    return ALIAS.get(k, k)


def stat_total(base, level, nature, iv=31):
    """Sum of the six in-battle stats with no EVs (Run & Bun removed them)."""
    up, down = NATURE.get(nature.lower(), (None, None))
    total = 0
    for s, b in base.items():
        if s == "hp":
            v = (2 * b + iv) * level // 100 + level + 10 if b > 1 else 1
        else:
            v = (2 * b + iv) * level // 100 + 5
            v = int(v * (1.1 if s == up else 0.9 if s == down else 1))
        total += v
    return total


def reference(level, iv=15, bst=500):
    """The player-side yardstick: a BST-500 mon, average IVs, neutral nature."""
    b = bst / 6
    return ((2 * b + iv) * level // 100 + level + 10) + 5 * ((2 * b + iv) * level // 100 + 5)


def rows(trainers, dex):
    bosses = sorted(BOSS)
    for i, (seg, cap, needle) in BOSS.items():
        if needle not in trainers[i]["name"]:
            raise SystemExit("boss index %d is %r, expected %s -- sheet changed?"
                             % (i, trainers[i]["name"], needle))
    out_ = []
    for i, t in enumerate(trainers):
        seg, cap, _ = BOSS[next((b for b in bosses if b >= i), bosses[-1])]
        optional_tab = t["tab"] == OPTIONAL_TAB and i > 408
        if i in BOSS or "[Boss]" in t["name"] or i >= FIRST_E4:
            kind = "boss"
        elif "[Optional]" in t["name"] + (t["area"] or "") or optional_tab:
            kind = "optional"
        else:
            kind = "filler"
        if optional_tab:
            seg, cap = "Optional (post-VR)", 95
        ms = []
        for m in t["mons"]:
            d = dex[dex_key(m["sp"])]
            base = d["baseStats"]
            ms.append({"lv": m["lv"], "bst": sum(base.values()),
                       "st": stat_total(base, m["lv"], m["nature"]),
                       "fe": not d.get("evos"),
                       "leg": bool(set(d.get("tags", [])) & LEGEND_TAGS),
                       "mega": "Mega" in m["sp"] or "Primal" in m["sp"],
                       "item": m["item"] not in WEAK_ITEMS,
                       "nat": m["nature"].lower() in NATURE,
                       "m4": len(m["moves"]) >= 4})
        n = len(ms)
        out_.append({"i": i, "name": t["name"], "area": t["area"], "seg": seg, "cap": cap,
                     "kind": kind, "n": n,
                     "maxlv": max(x["lv"] for x in ms), "avglv": st.mean(x["lv"] for x in ms),
                     "bst": st.mean(x["bst"] for x in ms), "st": st.mean(x["st"] for x in ms),
                     "fe": sum(x["fe"] for x in ms) / n, "leg": sum(x["leg"] for x in ms),
                     "mega": sum(x["mega"] for x in ms), "item": sum(x["item"] for x in ms) / n,
                     "nat": sum(x["nat"] for x in ms) / n, "m4": sum(x["m4"] for x in ms) / n,
                     "dbl": "[Double]" in t["name"]})
    return out_


def report(rs):
    order = []
    for r in rs:
        if r["seg"] not in order:
            order.append(r["seg"])

    def mean(L, k):
        return st.mean(r[k] for r in L) if L else float("nan")

    print("%-20s%4s | %3s%8s%6s%6s%6s%5s%6s%5s%6s | %8s%6s%6s%4s%5s%6s" % (
        "segment", "cap", "#F", "Flv-cap", "Fmax", "Fsize", "FBST", "FE%", "item%", "nat%",
        "Fpow", "Bmax-cap", "BBST", "Bitem", "leg", "mega", "Bpow"))
    for s in order:
        seg = [r for r in rs if r["seg"] == s]
        cap = seg[0]["cap"]
        F = [r for r in seg if r["kind"] == "filler"]
        B = [r for r in seg if r["kind"] == "boss"]
        ref = reference(cap)
        print("%-20s%4d | %3d%8.1f%6d%6.1f%6.0f%5.0f%6.0f%5.0f%6.2f | %8d%6.0f%6.0f%4.1f%5.1f%6.2f" % (
            s, cap, len(F), mean(F, "avglv") - cap, max([r["maxlv"] for r in F] or [0]) - cap,
            mean(F, "n"), mean(F, "bst"), 100 * mean(F, "fe"), 100 * mean(F, "item"),
            100 * mean(F, "nat"), mean(F, "st") / ref if F else 0,
            max([r["maxlv"] for r in B] or [0]) - cap, mean(B, "bst"), 100 * mean(B, "item"),
            sum(r["leg"] for r in B) / max(1, len(B)), sum(r["mega"] for r in B) / max(1, len(B)),
            mean(B, "st") / ref if B else 0))
    print("\nfillers above the cap:")
    for r in rs:
        if r["kind"] == "filler" and r["maxlv"] > r["cap"]:
            print("  %-60s max L%d vs cap %d" % (r["name"], r["maxlv"], r["cap"]))
    print("\nperfect-IV edge per mon (31 vs 15 IV, BST 500): L50 x%.3f, L100 x%.3f"
          % (reference(50, 31) / reference(50), reference(100, 31) / reference(100)))


def main():
    with open(out("trainers.json"), encoding="utf-8") as fh:
        trainers = json.load(fh)
    rs = rows(trainers, pokedex())
    with open(out("rows.json"), "w") as fh:
        json.dump(rs, fh)
    report(rs)


if __name__ == "__main__":
    main()
