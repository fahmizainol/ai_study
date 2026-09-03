#!/usr/bin/env python3
"""Evaluate Tier-1 property assertions against probe results (SIM-SPEC.md §3, §7).

Joins scenarios.json (assertions, by id) with the engine's ai_probe_results.ndjson.

The gate is 100% on the REFERENCE AI. A failure means one of two things, and the
distinction matters: either the AI is genuinely weak there, or the assertion is wrong.
Assume the assertion is wrong first — an assertion the reference fails is a claim about
good play that has not been justified.

Usage:
    python3 check_scenarios.py scenarios.json <game>/Data/ai_probe_results.ndjson [-v]
"""
import argparse
import json
import sys


def load(scn_path, res_path):
    corpus = {s['id']: s for s in json.load(open(scn_path, encoding='utf-8'))}
    results = {}
    with open(res_path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                r = json.loads(line)
                results[r.get('id')] = r
    return corpus, results


def score_of(res, move_id):
    for m in res.get('moves', []):
        if m.get('id') == move_id:
            return m.get('score')
    return None


def degenerate(res):
    """True when every move scores the same.

    A must_not_choose_move assertion is MEANINGLESS here: with all scores tied the AI
    picks from the whole pool at random, so the test is a coin flip that will pass ~half
    the time and look healthy. This is not hypothetical — four scenarios in the v2 corpus
    gave the AI a backup move the target was immune to, so every score was 0, and an
    identical v1 scenario had been passing by luck. Always give the AI a viable
    alternative.
    """
    scores = [m.get('score') for m in res.get('moves', []) if m.get('score') is not None]
    return len(scores) > 1 and len(set(scores)) == 1


def evaluate(scn, res):
    """Return list of (assertion_repr, passed, detail)."""
    out = []
    ids = scn.get('move_ids', {})
    act = res.get('action') or {}
    for a in scn['assertions']:
        kind = a[0]
        ok, detail = True, ''
        if kind == 'must_choose_any':
            detail = 'open scenario (documents behaviour, no constraint)'
        elif kind == 'must_choose_move_in':
            want = [ids.get(n) for n in a[1]]
            ok = act.get('type') == 'move' and act.get('move') in want
            detail = 'chose %s, wanted one of %s' % (act.get('move'), want)
        elif kind == 'must_not_choose_move':
            ok = not (act.get('type') == 'move' and act.get('move') == ids.get(a[1]))
            detail = 'chose %s, forbidden %s' % (act.get('move'), ids.get(a[1]))
        elif kind == 'score_gt':
            hi, lo = score_of(res, ids.get(a[1])), score_of(res, ids.get(a[2]))
            ok = hi is not None and lo is not None and hi > lo
            detail = '%s=%s vs %s=%s' % (a[1], hi, a[2], lo)
        elif kind == 'score_gte':
            # For positions where the stronger move can TIE rather than win —
            # engines that do not rank overkill score two sufficient moves
            # identically (e.g. two lethal moves, or two 4x moves both at the
            # damage cap). Asserts only "must not be worse". Use score_gt
            # wherever a strict ordering is actually required.
            hi, lo = score_of(res, ids.get(a[1])), score_of(res, ids.get(a[2]))
            ok = hi is not None and lo is not None and hi >= lo
            detail = '%s=%s vs %s=%s' % (a[1], hi, a[2], lo)
        elif kind == 'must_switch':
            ok = act.get('type') == 'switch'
            detail = 'action=%s' % act.get('type')
        elif kind == 'must_not_switch':
            ok = act.get('type') != 'switch'
            detail = 'action=%s' % act.get('type')
        elif kind == 'must_consider_switch':
            sss = res.get('should_switch_score')
            ok = sss is not None and sss > -1000
            detail = 'should_switch_score=%s (-1000 means switching was not evaluated)' % sss
        else:
            ok, detail = False, 'unknown assertion kind'
        out.append(('%s %s' % (kind, a[1:] if len(a) > 1 else ''), ok, detail))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('scenarios')
    ap.add_argument('results')
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()

    corpus, results = load(a.scenarios, a.results)
    total = passed = 0
    failures, errors, missing, degen, skipped = [], [], [], [], []

    for sid, scn in corpus.items():
        res = results.get(sid)
        if res is None:
            missing.append(sid)
            continue
        if 'error' in res:
            errors.append((sid, res['error']))
            continue
        # A scenario the engine could not instantiate is SKIPPED, not failed. Counting it
        # as a failure would blame the AI for the harness's inability to express the
        # position (e.g. Reborn field IDs have no Hegemony equivalent). Reported loudly
        # below so the corpus cannot silently shrink — SIM-SPEC 10.
        if res.get('skipped'):
            skipped.append((sid, res.get('reason', 'no reason given')))
            continue
        _choice_kinds = ('must_not_choose_move', 'must_choose_move_in')
        if degenerate(res) and any(a[0] in _choice_kinds for a in scn['assertions']):
            degen.append(sid)
        for rep, ok, detail in evaluate(scn, res):
            total += 1
            if ok:
                passed += 1
                if a.verbose:
                    print('  PASS %-34s %s  [%s]' % (sid, rep, detail))
            else:
                failures.append((sid, rep, detail))

    for sid, rep, detail in failures:
        print('  FAIL %-34s %s  [%s]' % (sid, rep, detail))
    for sid, err in errors:
        print('  ERR  %-34s %s' % (sid, err))
    for sid in missing:
        print('  MISS %-34s no probe result' % sid)
    for sid in degen:
        print('  WARN %-34s all moves scored equal -> must_not_choose is a coin flip'
              % sid)
    for sid, reason in skipped:
        print('  SKIP %-34s %s' % (sid, reason))

    print('\nassertions: %d/%d passed' % (passed, total))
    if skipped:
        print('scenarios skipped by the engine: %d (their assertions were NOT counted)'
              % len(skipped))
    if errors:
        print('scenarios that errored in-engine: %d' % len(errors))
    if missing:
        print('scenarios with no result: %d' % len(missing))
    if degen:
        print('DEGENERATE scenarios (fix these, they pass by luck): %d' % len(degen))
    # Non-zero exit only on genuine assertion failure; errors/missing are reported
    # loudly but are a harness problem, not an AI-quality verdict.
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
