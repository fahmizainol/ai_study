#!/usr/bin/env python3
"""How often a slower actor that is certain to die attacks anyway.

The predicate is the core's own (certain_lethal_threat?): under the oracle the declared
hit on its minimum roll discounted by its hit chance, otherwise the strict worst-case
figure on its minimum roll. `had_open_switch` counts the turns where at least one switch
candidate got past the gate -- the most the dead_before_moving rule could ever flip.

Usage:
    python3 dead_slower_turns.py generated/realidea_tier_gen5ru_a_0_6_7_oracle.ndjson ...
"""

import json
import sys
from collections import Counter

MIN_DAMAGE_ROLL = 0.85


def certain(view):
    hp = float(view.get("hp_pct") or 100)
    if "predicted_incoming_damage_pct" in view:
        hit = float(view["predicted_incoming_damage_pct"] or 0)
        acc = view.get("predicted_incoming_accuracy")
        if acc is not None:
            hit *= min(float(acc), 100) / 100
        return hit * MIN_DAMAGE_ROLL >= hp
    inc = view.get("certain_incoming_damage_pct", view.get("incoming_damage_pct"))
    return inc is not None and float(inc) * MIN_DAMAGE_ROLL >= hp


def main(paths):
    for path in paths:
        turns = attacked = switched = scaled = 0
        extra = Counter()
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                rec = json.loads(line)
                if rec.get("mode") != "portable" or not rec.get("trace"):
                    continue
                for entry in rec["trace"]:
                    view = entry.get("view") or {}
                    if view.get("faster") is not False or not certain(view):
                        continue
                    turns += 1
                    cands = entry.get("candidates") or []
                    top = cands[0] if cands else {}
                    if entry.get("type") == "switch":
                        switched += 1
                    else:
                        attacked += 1
                    if any(r[0] == "dead_before_moving" for r in (top.get("reasons") or [])):
                        scaled += 1
                    if any(c.get("type") == "switch" and float(c.get("score") or -1e9) > -9000
                           for c in cands):
                        extra["had_open_switch"] += 1
        print("%s: slower+certain-dead turns=%d attacked=%d switched=%d "
              "top_move_was_scaled=%d open_switch=%d" % (
                  path.split("/")[-1], turns, attacked, switched, scaled,
                  extra["had_open_switch"]))


if __name__ == "__main__":
    main(sys.argv[1:])
