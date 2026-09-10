#!/usr/bin/env python3
"""Measure Reborn Yang's Intense boss ladder: BST, EV cheat, and level-cap alignment.

Answers three questions the flat "avg EV total" column in TEAM-DESIGN.md §3 hides:

  1. How does species power (BST) actually progress across the 24 boss fights?
  2. Where does the difficulty budget switch from species to super-legal EVs?
  3. Where does LEVELCAPS sit relative to the boss you are about to fight?

Effective BST ("eBST") folds the EV cheat back into base stats. Both terms enter the
stat formula through the same bracket --

    stat = floor((floor((2*Base + IV + floor(EV/4)) * L/100) + 5) * nature)

-- so +1 base and +8 EV are worth exactly the same, at every level. eBST is therefore
    BST + max(0, EV_total - 510) / 8
i.e. the BST a *legal* (510-EV) Pokemon would need to match the boss's real stats.

Usage:
    python3 boss_curve.py            # markdown tables on stdout
    python3 boss_curve.py --json     # same numbers as JSON
"""
import json
import os
import re
import statistics as st
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STUDY = os.path.dirname(HERE)
RB = "/mnt/c/Users/kny/Documents/Games/Norm/Reborn Yang/Reborn Yang"
PBS = os.path.join(RB, "PBS", "PBS")
FORMS_RB = os.path.join(RB, "Scripts", "MultipleForms.rb")
TRAINERS = os.path.join(STUDY, "extracted", "reborn-trainers-full.json")

EV_CAP = 510          # Essentials PokeBattle_Pokemon::EVLIMIT
EV_PER_BASE = 8       # 8 EV == 1 base stat point, see module docstring

# Reborn/Reborn Yang, Scripts/Reborn/SystemConstants.rb line 7.
LEVELCAPS = [20, 25, 30, 35, 40, 45, 50, 55, 60, 65,
             70, 70, 75, 75, 80, 85, 90, 90, 95, 150]

# The boss ladder in badge order. Ordering is confirmed monotone in Normal-mode ace
# level; the (name, class) pairs are how each fight is keyed in trainers.dat, which is
# why Terra appears as "T3RR4" and Titania/Amaria as their numbered classes.
LADDER = [
    (1,  "Julia",     "JULIA",      "Julia"),
    (2,  "Florinia",  "FLORINIA",   "Florinia"),
    (3,  "Corey",     "Corey",      "Corey"),
    (4,  "Shelly",    "SHELLY",     "Shelly"),
    (5,  "Shade",     "SHADE",      "Shade"),
    (6,  "Kiki",      "Sensei",     "Kiki"),
    (7,  "Aya",       "AYA",        "Aya"),
    (8,  "Serra",     "SERRA",      "Serra"),
    (9,  "Noel",      "NOEL",       "Noel"),
    (10, "Radomus",   "RADOMUS",    "Radomus"),
    (11, "Luna",      "LUNA",       "Luna"),
    (12, "Samson",    "SAMSON",     "Samson"),
    (13, "Charlotte", "CHARLOTTE",  "Charlotte"),
    (14, "T3RR4",     "TERRA",      "Terra"),
    (15, "Ciel",      "CIEL",       "Ciel"),
    (16, "Adrienn",   "ADRIENN",    "Adrienn"),
    (17, "Titania",   "TITANIA1",   "Titania"),
    (18, "Amaria",    "AMARIA2",    "Amaria"),
    (19, "Hardy",     "HARDY",      "Hardy"),
    (20, "Saphira",   "SAPHIRA",    "Saphira"),      # cap has opened by here
    (21, "Heather",   "HEATHER",    "Heather (E4)"),
    (22, "Elias",     "ELIAS",      "Elias (E4)"),
    (23, "Anna",      "ANNA",       "Anna (E4)"),
    (24, "Lin",       "LIN",        "Lin (final)"),
]
LAST_CAPPED_BADGE = 19   # Saphira onward sits on LEVELCAPS[19] = 150, i.e. uncapped


def parse_pbs(path):
    """PBS pokemon.txt -> {InternalName: {field: value}}."""
    out, cur = {}, None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip().lstrip("﻿")
            if line.startswith("[") and line.endswith("]"):
                cur = {}
                continue
            if cur is None or "=" not in line:
                continue
            key, val = line.split("=", 1)
            cur[key] = val
            if key == "InternalName":
                out[val] = cur
    return out


def _block(text, start):
    """Return the {...} block beginning at or after `start`, brace-matched."""
    open_at = text.find("{", start)
    if open_at < 0:
        return "", len(text)
    depth = 0
    for i in range(open_at, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[open_at + 1:i], i
    return text[open_at + 1:], len(text)


def parse_form_bst(path):
    """MultipleForms.rb -> {(SPECIES, form_index): BST} for forms that override stats.

    Brace-matched on purpose: a naive regex walks past a form that declares no
    :BaseStats and picks up the next form's, which silently mis-scores e.g.
    Urshifu-Rapid (no override, 550) as Urshifu-Dyna (650).
    """
    text = open(path, encoding="utf-8", errors="replace").read()
    out = {}
    for m in re.finditer(r"PBSpecies::(\w+)\s*=>\s*\{", text):
        species = m.group(1)
        body, _ = _block(text, m.start())
        fm = re.search(r":FormName\s*=>\s*", body)
        if not fm:
            continue
        names_src, _ = _block(body, fm.start())
        names = {int(i): n for i, n in re.findall(r"(\d+)\s*=>\s*\"([^\"]+)\"", names_src)}
        for idx, name in names.items():
            # Safe against the :FormName block itself: there a name appears as the
            # value (`1 => "Rapid"`), never followed by its own `=>`.
            fb = re.search(r"\"%s\"\s*=>\s*" % re.escape(name), body)
            if not fb:
                continue
            form_body, _ = _block(body, fb.start())
            stats = re.search(r":BaseStats\s*=>\s*\[([\d,\s]+)\]", form_body)
            if stats:
                out[(species, idx)] = sum(int(x) for x in stats.group(1).split(","))
    return out


class Dex:
    def __init__(self):
        self.mons = parse_pbs(os.path.join(PBS, "pokemon.txt"))
        for k, v in parse_pbs(os.path.join(PBS, "gen8pokemon.txt")).items():
            self.mons.setdefault(k, v)
        self.forms = parse_form_bst(FORMS_RB)

    def bst(self, species, form=0):
        if (species, form) in self.forms:
            return self.forms[(species, form)]
        rec = self.mons.get(species)
        if not rec or "BaseStats" not in rec:
            return None
        return sum(int(x) for x in rec["BaseStats"].split(","))

    def is_nfe(self, species):
        rec = self.mons.get(species)
        return bool(rec) and rec.get("Evolutions", "").strip() != ""


def effective_bst(bst, ev_total):
    return bst + max(0, ev_total - EV_CAP) / float(EV_PER_BASE)


def load_ladder():
    trainers = json.load(open(TRAINERS, encoding="utf-8"))
    dex = Dex()
    rows = []
    for badge, name, cls, label in LADDER:
        fights = {}
        for pid in (0, 100):
            for t in trainers:
                if (t["name"] == name and t["class"] == cls
                        and t["pid"] == pid and len(t["party"]) == 6):
                    fights[pid] = t
                    break
        if 100 not in fights:
            print("WARN: no Intense variant for %s" % label, file=sys.stderr)
            continue
        party = []
        for p in fights[100]["party"]:
            b = dex.bst(p["species"], p.get("form") or 0)
            if b is None:
                print("WARN: no BST for %s" % p["species"], file=sys.stderr)
                continue
            ev = sum(p["evs"])
            party.append({
                "species": p["species"], "form": p.get("form") or 0, "level": p["level"],
                "bst": b, "ev": ev, "ebst": effective_bst(b, ev),
                "nfe": dex.is_nfe(p["species"]),
                "ev_stat_max": max(p["evs"]),
            })
        levels = [m["level"] for m in party]
        bsts = [m["bst"] for m in party]
        normal = fights.get(0)
        normal_bst = None
        if normal:
            nb = [dex.bst(p["species"], p.get("form") or 0) for p in normal["party"]]
            nb = [x for x in nb if x]
            normal_bst = st.mean(nb) if nb else None
        cap = LEVELCAPS[badge - 1] if badge <= LAST_CAPPED_BADGE else None
        rows.append({
            "badge": badge, "label": label, "party": party,
            "lv_lo": min(levels), "lv_hi": max(levels),
            "cap": cap, "gap": (cap - max(levels)) if cap else None,
            "bst_mean": st.mean(bsts), "bst_min": min(bsts), "bst_max": max(bsts),
            "bst_spread": max(bsts) - min(bsts),
            "nfe": sum(1 for m in party if m["nfe"]),
            "ev_mean": st.mean(m["ev"] for m in party),
            "ev_over_cap": sum(1 for m in party if m["ev"] > EV_CAP),
            "ebst_mean": st.mean(m["ebst"] for m in party),
            "normal_bst_mean": normal_bst,
            "species_same_as_normal": bool(normal) and sorted(
                p["species"] for p in normal["party"]) == sorted(m["species"] for m in party),
        })
    return rows


def summary(rows):
    """The aggregate claims BOSS-CURVE.md makes, derived rather than hand-counted."""
    by_badge = {r["badge"]: r for r in rows}
    first, pivot, last = by_badge[1], by_badge[7], rows[-1]
    trainers = json.load(open(TRAINERS, encoding="utf-8"))
    intense = [p for t in trainers if t["pid"] >= 100 for p in t["party"]]
    over_stat = sum(1 for p in intense if max(p["evs"]) > 252)
    switchover = next((r for r in rows if r["ev_over_cap"] == 6), None)
    return {
        "seg_early_ebst": pivot["ebst_mean"] - first["ebst_mean"],
        "seg_early_species": pivot["bst_mean"] - first["bst_mean"],
        "seg_early_ev": (pivot["ebst_mean"] - first["ebst_mean"])
                        - (pivot["bst_mean"] - first["bst_mean"]),
        "seg_late_ebst": last["ebst_mean"] - pivot["ebst_mean"],
        "seg_late_species": last["bst_mean"] - pivot["bst_mean"],
        "seg_late_ev": (last["ebst_mean"] - pivot["ebst_mean"])
                       - (last["bst_mean"] - pivot["bst_mean"]),
        "intense_mons": len(intense),
        "over_252_per_stat": over_stat,
        "over_252_pct": 100.0 * over_stat / len(intense),
        "first_all_six_over_cap": switchover["label"] if switchover else None,
        "first_all_six_badge": switchover["badge"] if switchover else None,
        "switchover_species_identical": switchover["species_same_as_normal"] if switchover else None,
    }


def markdown(rows):
    o = []
    o.append("| # | boss | lv | cap | gap | BST | min | max | spread | NFE | EV | >510 | **eBST** | Δ |")
    o.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        cap = str(r["cap"]) if r["cap"] else "open"
        gap = "%+d" % r["gap"] if r["gap"] is not None else "—"
        o.append("| %d | %s | %d–%d | %s | %s | %.0f | %d | %d | %d | %d | %.0f | %d | **%.0f** | %s |" % (
            r["badge"], r["label"], r["lv_lo"], r["lv_hi"], cap, gap,
            r["bst_mean"], r["bst_min"], r["bst_max"], r["bst_spread"], r["nfe"],
            r["ev_mean"], r["ev_over_cap"], r["ebst_mean"],
            ("+%.0f" % (r["ebst_mean"] - r["bst_mean"])) if r["ebst_mean"] > r["bst_mean"] else "—"))
    o.append("")
    s = summary(rows)
    o.append("Power added, by segment and source:")
    o.append("")
    o.append("| segment | Δ eBST | from species | from EV cheat |")
    o.append("|---|---|---|---|")
    o.append("| badges 1 → 7 | **%+.0f** | %+.0f | %+.0f |" % (
        s["seg_early_ebst"], s["seg_early_species"], s["seg_early_ev"]))
    o.append("| badges 7 → final | **%+.0f** | %+.0f | **%+.0f** |" % (
        s["seg_late_ebst"], s["seg_late_species"], s["seg_late_ev"]))
    o.append("")
    o.append("Switchover: %s (badge %d) is the first boss with all six over the EV cap%s." % (
        s["first_all_six_over_cap"], s["first_all_six_badge"],
        ", and its species are identical to its Normal roster"
        if s["switchover_species_identical"] else ""))
    o.append("Per-stat cheating is rare: %d of %d Intense Pokémon (%.1f%%) exceed 252 in one stat."
             % (s["over_252_per_stat"], s["intense_mons"], s["over_252_pct"]))
    o.append("")
    mons = [(m["ebst"] - m["bst"], m, r) for r in rows for m in r["party"]]
    mons.sort(key=lambda x: -x[0])
    o.append("Largest single-Pokémon conversions:")
    o.append("")
    o.append("| boss | Pokémon | EV | BST → eBST |")
    o.append("|---|---|---|---|")
    for delta, m, r in mons[:8]:
        o.append("| %s | %s | %d | %d → **%.0f** (+%.0f) |" % (
            r["label"], m["species"].title(), m["ev"], m["bst"], m["ebst"], delta))
    return "\n".join(o)


if __name__ == "__main__":
    data = load_ladder()
    if "--json" in sys.argv:
        print(json.dumps({"ladder": data, "summary": summary(data)}, indent=2))
    else:
        print(markdown(data))
