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


# Returned by switch_index when the record's array cannot carry a positional
# assertion at all. Distinct from a failure: the claim is untested here, not refuted,
# and it is reported separately so it can never be mistaken for a pass.
UNEVALUABLE = object()


# Foe designations usable in a must_target assertion -> battler index.
# Battler indices are shared by both engines: even = player side, odd = AI side.
FOE_SLOTS = {'left': 0, 'right': 2}


def opts_of(a):
    """Trailing options dict on an assertion, e.g. ('must_switch', {'actor': 1}).

    Assertions are positional per kind, so an optional field cannot be appended
    positionally without ambiguity. A trailing dict is unambiguous (no assertion
    argument is ever a dict), round-trips through JSON as-is, and matches the
    order-free trailing dict the scenario corpus already uses for battle state.
    """
    return a[-1] if a and isinstance(a[-1], dict) else {}


def args_of(a):
    return a[:-1] if a and isinstance(a[-1], dict) else a


def actor_view(res, idx):
    """The decision record for one AI-side battler.

    Probes emit `actors` (index 0 = AI left / battler 1, index 1 = AI right /
    battler 3) and mirror actors[0] onto the top level. Falling back to the whole
    record when `actors` is absent keeps pre-doubles artifacts readable.
    """
    actors = res.get('actors')
    if actors:
        return actors[idx] if idx < len(actors) else None
    return res if idx == 0 else None


def score_of(res, move_id):
    for m in (res or {}).get('moves', []):
        if m.get('id') == move_id:
            return m.get('score')
    return None


def switch_index(scn, view, ref):
    """Resolve a bench reference to an index into this actor's switch_scores.

    A ref is either `bench<k>` (k-th AI bench mon, in corpus order) or a SPECIES
    name, which must be unique in the AI party -- several cards deliberately bench
    two of one species so the only difference between the candidates is an ability
    or an item, and those must use bench0/bench1.

    Only a PARTY-INDEXED array can be read this way, and only Reborn emits one:
    getSwitchInScoresParty (:11417) returns one score per party slot with the actives
    left at -10000000, so its length equals the party's. The Portable probe record
    replaces it with the plan's ranking, which is SORTED BY SCORE and carries only the
    switchable candidates -- index 0 is whichever candidate won, not a party slot. A
    positional assertion against that array is not merely unreliable, it is
    meaningless, and it silently PASSED the four entry cards before this was noticed
    (the best candidate is always first, whichever bench slot it came from). So the
    unlabelled shape returns UNEVALUABLE rather than a number.
    """
    scores = view.get('switch_scores') or []
    party = scn.get('ai_party_species') or []
    actives = scn.get('ai_actives', 1)
    if not party:
        return None, 'scenario has no ai_party_species (regenerate scenarios.json)'
    if ref.startswith('bench') and ref[5:].isdigit():
        slot = actives + int(ref[5:])
    else:
        hits = [i for i, sp in enumerate(party) if sp == ref]
        if len(hits) != 1:
            return None, ('species %s appears %d times in the AI party; use benchN'
                          % (ref, len(hits)))
        slot = hits[0]
    if slot >= len(party):
        return None, '%s is past the end of the AI party (%d mons)' % (ref, len(party))
    if not scores:
        return None, 'switch_scores is empty (the AI never evaluated switching here)'
    if len(scores) != len(party):
        return UNEVALUABLE, ('switch_scores is not party-indexed (%d entries for %d '
                             'party slots) -- this AI reports a score-ordered ranking, '
                             'which no positional assertion can read'
                             % (len(scores), len(party)))
    if slot >= len(scores):
        return None, '%s maps to switch_scores[%d], out of range' % (ref, slot)
    return scores[slot], None


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
    for raw in scn['assertions']:
        opts = opts_of(raw)
        a = args_of(raw)
        kind = a[0]
        # Assertions address one AI battler. With no {'actor': n} they address the
        # left one, which in singles is the only one — so every pre-doubles
        # assertion keeps its exact meaning.
        aidx = opts.get('actor', 0)
        view = actor_view(res, aidx)
        if view is None:
            out.append(('%s %s' % (kind, a[1:]), False,
                        'no record for actor %d (scenario is not doubles?)' % aidx))
            continue
        act = view.get('action') or {}
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
            hi, lo = score_of(view, ids.get(a[1])), score_of(view, ids.get(a[2]))
            ok = hi is not None and lo is not None and hi > lo
            detail = '%s=%s vs %s=%s' % (a[1], hi, a[2], lo)
        elif kind == 'score_gte':
            # For positions where the stronger move can TIE rather than win —
            # engines that do not rank overkill score two sufficient moves
            # identically (e.g. two lethal moves, or two 4x moves both at the
            # damage cap). Asserts only "must not be worse". Use score_gt
            # wherever a strict ordering is actually required.
            hi, lo = score_of(view, ids.get(a[1])), score_of(view, ids.get(a[2]))
            ok = hi is not None and lo is not None and hi >= lo
            detail = '%s=%s vs %s=%s' % (a[1], hi, a[2], lo)
        elif kind == 'switch_score_gt':
            # Reborn only fills switchscore when shouldSwitch? already came out
            # positive (:11358), so a card using this must put the active in real
            # trouble -- otherwise the array is empty and the assertion is
            # unevaluable, which is reported as a failure, not a pass.
            hi, hi_err = switch_index(scn, view, a[1])
            lo, lo_err = switch_index(scn, view, a[2])
            if hi is UNEVALUABLE or lo is UNEVALUABLE:
                out.append(('%s %s' % (kind, a[1:]), UNEVALUABLE, hi_err or lo_err))
                continue
            err = hi_err or lo_err
            ok = err is None and hi > lo
            detail = err or ('%s=%s vs %s=%s' % (a[1], hi, a[2], lo))
        elif kind == 'must_switch_to':
            # WHICH body was sent in, by species. Both AIs record a switch as
            # {"type": "switch", "slot": <party slot>} (AI_Harness.rb:785), so this
            # reads the same on either side -- unlike switch_score_gt, which needs a
            # party-indexed score array only Reborn emits. Added for the 0.6.2
            # dies_on_entry card, where the whole question is which of two candidates
            # the AI picked.
            party = scn.get('ai_party_species') or []
            hits = [i for i, sp in enumerate(party) if sp == a[1]]
            if not party:
                ok, detail = False, 'scenario has no ai_party_species'
            elif len(hits) != 1:
                ok = False
                detail = ('species %s appears %d times in the AI party'
                          % (a[1], len(hits)))
            else:
                ok = act.get('type') == 'switch' and act.get('slot') == hits[0]
                detail = ('action=%s slot=%s, wanted slot %d (%s)'
                          % (act.get('type'), act.get('slot'), hits[0], a[1]))
        elif kind == 'must_switch':
            ok = act.get('type') == 'switch'
            detail = 'action=%s' % act.get('type')
        elif kind == 'must_not_switch':
            ok = act.get('type') != 'switch'
            detail = 'action=%s' % act.get('type')
        elif kind == 'must_consider_switch':
            sss = view.get('should_switch_score')
            ok = sss is not None and sss > -1000
            detail = 'should_switch_score=%s (-1000 means switching was not evaluated)' % sss
        elif kind == 'must_not_double_target':
            # Cross-actor, so it ignores {'actor': n} and reads both records. Both
            # AI battlers aiming single-target moves at the same foe wastes one of
            # them whenever the other foe is also worth hitting.
            #
            # ONLY meaningful when both chosen moves are single-target: a spread
            # move's registered target is nominal (it hits everything regardless),
            # so a scenario using this kind must not give either actor one.
            v0, v1 = actor_view(res, 0), actor_view(res, 1)
            a0 = (v0 or {}).get('action') or {}
            a1 = (v1 or {}).get('action') or {}
            t0, t1 = a0.get('target'), a1.get('target')
            ok = (a0.get('type') == 'move' and a1.get('type') == 'move'
                  and t0 is not None and t1 is not None and t0 != t1)
            detail = 'left %s->%s, right %s->%s' % (
                a0.get('type'), t0, a1.get('type'), t1)
        elif kind == 'must_target':
            # Doubles only. Requires an actual move choice: a switch or item has no
            # target, and treating "no target recorded" as a pass would make this
            # assertion vacuous exactly when the AI did something unexpected.
            want = FOE_SLOTS.get(a[1])
            got = act.get('target')
            ok = (act.get('type') == 'move' and want is not None and got == want)
            detail = 'action=%s target=%s, wanted %s (battler %s)' % (
                act.get('type'), got, a[1], want)
        else:
            ok, detail = False, 'unknown assertion kind'
        scope = '' if aidx == 0 else ' @actor%d' % aidx
        out.append(('%s%s %s' % (kind, scope, a[1:] if len(a) > 1 else ''), ok, detail))
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
    unevaluable = []

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
        # Degeneracy is per battler: in doubles the left mon's vector can be flat
        # while the right mon's carries a real ranking, so checking only the
        # top-level record would either miss a coin-flip assertion or cry wolf
        # about an actor nothing was asserted on. must_target is included because
        # a randomly picked move drags its target along with it.
        _choice_kinds = ('must_not_choose_move', 'must_choose_move_in', 'must_target')
        for aidx in sorted({opts_of(x).get('actor', 0) for x in scn['assertions']
                            if args_of(x)[0] in _choice_kinds}):
            v = actor_view(res, aidx)
            if v is not None and degenerate(v):
                degen.append(sid if aidx == 0 else '%s @actor%d' % (sid, aidx))
        for rep, ok, detail in evaluate(scn, res):
            if ok is UNEVALUABLE:
                unevaluable.append((sid, rep, detail))
                continue
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
    for sid, rep, detail in unevaluable:
        print('  N/A  %-34s %s  [%s]' % (sid, rep, detail))

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
    if unevaluable:
        print('assertions this record cannot answer: %d (NOT counted as passes)'
              % len(unevaluable))
    # A quality gate is only meaningful over a complete, non-degenerate run. Explicit
    # engine skips remain allowed and visible, but missing/error records or coin-flip
    # vectors must fail automation instead of shrinking the denominator silently.
    sys.exit(1 if failures or errors or missing or degen else 0)


if __name__ == '__main__':
    main()
