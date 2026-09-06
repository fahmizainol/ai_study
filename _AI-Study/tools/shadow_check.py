#!/usr/bin/env python3
"""Validate a Realidea shadow run, then report where the two AIs disagreed.

The shadow arm has the stock AI play the battle while the portable planner answers from
the same position every turn and registers nothing. That makes every turn a controlled
comparison -- unlike a live stock/portable pair, which holds identical state for about a
turn and is a different battle after that.

The comparison is only worth anything if observation was free, so this checks that
first: a shadow battle and a stock battle on the same matchup and seed must agree on
decision and turn count. They are the same battle, played by the same AI, differing only
in whether an observer was watching. A mismatch means the observer perturbed the run and
every disagreement number below it is void, so that is a hard failure, not a warning.

Disagreement is not error. Stock wins some of these battles; the shadow says where the
two policies part company, not which one was right.

Usage:
    python3 shadow_check.py generated/realidea_shadow_gen6ou_a.ndjson
    python3 shadow_check.py <ndjson> --examples 20
"""

import argparse
import json
import sys
from collections import Counter


def load(path):
    stock, shadow = {}, {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            # The roster set is part of a battle's identity: gen6ou_a and gen6ou_b
            # both name their matchups team1_vs_team2, so keying on id+seed alone
            # silently collapses two sets into one and halves the sample.
            key = (record.get("teams"), record.get("id"), record.get("seed"))
            if record.get("mode") == "stock":
                stock[key] = record
            elif record.get("mode") == "shadow":
                shadow[key] = record
    return stock, shadow


def check_free(stock, shadow):
    """Every paired battle must match on decision and turns. Returns the mismatches."""
    bad, paired = [], 0
    for key in sorted(set(stock) & set(shadow), key=lambda k: tuple(str(p) for p in k)):
        left, right = stock[key], shadow[key]
        paired += 1
        if left.get("decision") != right.get("decision") or \
           left.get("turns") != right.get("turns"):
            bad.append((key, left.get("decision"), left.get("turns"),
                        right.get("decision"), right.get("turns")))
    return paired, bad


def same_choice(portable, stock_choice):
    """None when the pair cannot be scored, else True/False.

    Moves compare on numeric id: the host choice holds a PokeBattle_Move object whose
    numeric id is the only field both sides carry without a name lookup. Switches
    compare on the party slot they picked.
    """
    if not portable or not stock_choice:
        return None
    left, right = portable.get("type"), stock_choice.get("type")
    if right in (None, "unregistered"):
        return None
    if left != right:
        return False
    if left == "move":
        a, b = portable.get("numeric_move_id"), stock_choice.get("numeric_move_id")
        return None if a is None or b is None else a == b
    if left == "switch":
        return portable.get("slot") == stock_choice.get("slot")
    return None


def label(choice):
    if not choice:
        return "-"
    kind = choice.get("type")
    if kind == "move":
        return choice.get("move_id") or "move#%s" % choice.get("numeric_move_id")
    if kind == "switch":
        return "switch->%s" % choice.get("slot")
    return str(kind)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--examples", type=int, default=10,
                        help="how many disagreeing turns to print (0 for none)")
    args = parser.parse_args()

    stock, shadow = load(args.path)
    if not shadow:
        sys.exit("no shadow records in %s" % args.path)

    paired, bad = check_free(stock, shadow)
    print("shadow battles : %d" % len(shadow))
    print("paired w/ stock: %d" % paired)
    missing = len(shadow) - paired
    if missing:
        print("unpaired       : %d (no stock record on the same id+seed)" % missing)

    if bad:
        print("\nOBSERVATION WAS NOT FREE -- %d/%d paired battles diverged:" %
              (len(bad), paired))
        for key, ld, lt, rd, rt in bad[:20]:
            print("  %-10s %-24s seed=%-8s stock decision=%s turns=%s | "
                  "shadow decision=%s turns=%s" % (
                      key[0], key[1], key[2], ld, lt, rd, rt))
        print("\nThe shadow perturbed the battles it observed, so no disagreement "
              "figure from this file means anything.")
        return 1
    if paired:
        print("observation free: yes -- all %d paired battles identical "
              "(decision and turns)" % paired)

    # Rolls the observation took from its own generator rather than the battle's.
    # Normally 0: at bestSkill the planner is deterministic, and the engine helpers the
    # snapshot calls (pbGetMoveScore, pbRoughDamage) take no rolls -- every pbAIRandom
    # in PokeBattle_AI sits in the choosing machinery, not the scorer. It goes above 0
    # only when the planner runs with noise, i.e. below bestSkill, and then the point is
    # that those draws came from the observer and not from the battle.
    diverted = sum(r.get("shadow_rng_diverted", 0) for r in shadow.values())
    print("rolls diverted   : %d%s" % (
        diverted, " (planner noise was active; diverted away from the battle)"
        if diverted else " (expected: nothing on this path rolls at bestSkill)"))

    agree = disagree = unscored = 0
    kinds = Counter()
    pairs = Counter()
    examples = []
    for key in sorted(shadow, key=lambda k: tuple(str(p) for p in k)):
        record = shadow[key]
        for entry in record.get("shadow") or []:
            verdict = same_choice(entry.get("portable"), entry.get("stock"))
            if verdict is None:
                unscored += 1
                continue
            if verdict:
                agree += 1
                continue
            disagree += 1
            p, s = entry.get("portable"), entry.get("stock")
            kinds["%s vs %s" % (p.get("type"), s.get("type"))] += 1
            pairs["%s vs %s" % (label(p), label(s))] += 1
            if len(examples) < args.examples:
                examples.append((key, entry, p, s))

    scored = agree + disagree
    failures = sum(1 for r in shadow.values()
                   for e in (r.get("shadow") or []) if e.get("observer_error"))
    print("\nturns compared : %d (%d unscorable%s)" % (
        scored, unscored,
        "" if not failures else
        ", of which %d are turns the observer itself failed on -- a pre-existing engine "
        "crash in pbRoughDamage, recorded rather than dropped so the denominator stays "
        "honest" % failures))
    if scored:
        print("agreed         : %d (%.1f%%)" % (agree, agree * 100.0 / scored))
        print("disagreed      : %d (%.1f%%)" % (disagree, disagree * 100.0 / scored))
    if kinds:
        print("\nby kind:")
        for name, count in kinds.most_common():
            print("  %-22s %4d" % (name, count))
    if pairs:
        print("\nmost common disagreements (portable vs stock):")
        for name, count in pairs.most_common(12):
            print("  %-46s %4d" % (name, count))
    if examples:
        print("\nexamples:")
        for key, entry, p, s in examples:
            view = entry.get("view") or {}
            hp = view.get("hp_pct")
            print("  %s/%s seed=%s turn %s actor %s: portable %s (score %s) | stock %s%s" % (
                key[0], key[1], key[2], entry.get("turn"), entry.get("actor"),
                label(p), p.get("score"), label(s),
                "" if hp is None else "   [hp %.0f%%%s]" % (
                    hp, ", threatened" if view.get("threatened_lethal") else "")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
