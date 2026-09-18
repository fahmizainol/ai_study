"""Replay the LEVEL-SCALING.md clamp over every real Realidea party.

Two corpora, because the game runs a mix of both:
  extracted/realidea-battles.json  - the developer's original event parties (178)
  generated/teams_*.json           - the installed replacement teams (150)

Player curves are synthesised from the active Unbound expert cap table: a party
of six flat at cap, cap-LEASH, and cap-15 for the fight's stage.
"""
import json, math, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAXLEVEL = 100
LEASH = 6
CAPS = [20, 26, 32, 36, 40, 45, 52, 57, 61, 75]  # ..., champion cap


def pb_balanced_level(levels):
    if not levels:
        return 1
    total = sum(levels)
    if total == 0:
        return 1
    avg = total / float(len(levels))
    stdev = math.sqrt(sum((l - avg) ** 2 for l in levels) / len(levels))
    weights = []
    for l in levels:
        w = l / float(total)
        if w < 0.5:
            w -= stdev / float(MAXLEVEL)
            w = 0.001 if w <= 0.001 else w
        else:
            w += stdev / float(MAXLEVEL)
            w = 0.999 if w >= 0.999 else w
        weights.append(w)
    mean = sum(l * w for l, w in zip(levels, weights)) / sum(weights)
    # Ruby's Float#round is half-up; Python's is banker's rounding.
    mean = int(math.floor(mean + 0.5))
    mean = max(mean, 1) + 2
    return min(mean, MAXLEVEL)


def outlier_ceiling(team, leash):
    """A mon more than 2*leash above its team's median is a scripted gimmick."""
    s = sorted(team)
    return s[(len(s) - 1) // 2] + 2 * leash


def scale(team, player, leash=LEASH):
    a = pb_balanced_level(player) - 1        # == balanceo
    ceiling = outlier_ceiling(team, leash)
    kept = [l for l in team if l <= ceiling]
    if not kept:
        return list(team)
    ace = max(kept)
    out = []
    for l in team:
        if l > ceiling:
            out.append(l)          # outlier: excluded from anchor, left alone
            continue
        n = a + (l - ace)
        n = max(n, l)                       # floor: never weaker than designed
        n = min(n, l + leash)               # ceiling: a bounded rise
        out.append(min(max(n, 1), MAXLEVEL))
    return out


def stage_for(levels):
    """Nearest cap at or above the fight's ace -> the stage it belongs to."""
    ace = max(levels)
    for i, c in enumerate(CAPS):
        if ace <= c:
            return i
    return len(CAPS) - 1


def load_corpora():
    out = {}
    battles = json.loads((ROOT / "extracted/realidea-battles.json").read_text())
    orig = []
    for t in battles:
        lv = [p["level"] for p in t["party"]]
        scaled_marker = any(not isinstance(l, int) for l in lv)
        ints = [l for l in lv if isinstance(l, int)]
        orig.append({
            "id": "map%03d_%s_%s" % (t["map"], t["type"], t["name"]),
            "levels": ints, "balanceo": scaled_marker, "raw": lv,
        })
    out["original events"] = orig

    gen = []
    for name in ("teams_bosses_gyms", "teams_trainers", "teams_filler", "teams_dat"):
        path = ROOT / "generated" / (name + ".json")
        if not path.exists():
            continue
        for t in json.loads(path.read_text()):
            lv = [m["level"] for m in t["mons"]]
            ints = [l for l in lv if isinstance(l, int)]
            gen.append({
                "id": t.get("id", "?"), "levels": ints,
                "balanceo": any(not isinstance(l, int) for l in lv), "raw": lv,
            })
    out["installed teams"] = gen
    return out


def main():
    fail = 0
    for corpus, fights in load_corpora().items():
        print("== %s (%d fights) ==" % (corpus, len(fights)))
        for label, offset in (("on cap", 0), ("cap-%d" % LEASH, LEASH), ("cap-15", 15)):
            changed = moved = 0
            worst = 0
            oob = []
            dropped = []
            bal_changed = []
            for f in fights:
                if not f["levels"]:
                    continue
                cap = CAPS[stage_for(f["levels"])]
                player = [max(cap - offset, 2)] * 6
                out = scale(f["levels"], player)
                if any(n < 1 or n > MAXLEVEL for n in out):
                    oob.append(f["id"])
                deltas = [n - o for o, n in zip(f["levels"], out)]
                if any(d < 0 for d in deltas):
                    dropped.append(f["id"])
                if any(d > LEASH for d in deltas):
                    oob.append(f["id"] + " (rise>leash)")
                if any(deltas):
                    changed += 1
                    moved += sum(1 for d in deltas if d)
                    worst = max(worst, max(deltas))
                    if f["balanceo"]:
                        bal_changed.append(f["id"])
            note = ""
            if oob:
                note += "  OUT OF RANGE: %d %s" % (len(oob), oob[:3]); fail += 1
            if dropped:
                note += "  FELL BELOW DESIGNED: %d %s" % (len(dropped), dropped[:3])
                fail += 1
            if bal_changed:
                note += "  balanceo fights risen: %d" % len(bal_changed)
            print("  player %-8s  fights changed %3d/%-3d  mons moved %4d  max rise %d%s"
                  % (label, changed, len(fights), moved, worst, note))
        print()
    print("FAIL" if fail else "PASS - no out-of-range level; nothing ever falls below"
                             " its designed level; rises bounded by the leash")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
