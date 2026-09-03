#!/usr/bin/env python3
"""Tier-2 cross-engine comparison: rank correlation between two AIs on one corpus.

Implements SIM-SPEC.md §3 Tier 2 and §7. Compares the *ordering* of each AI's move-score
vector, not the chosen action — chosen actions diverge for reasons that have nothing to do
with port quality (§3: different game data, different mechanics, stochastic selection).

WHICH SCORE TO COMPARE. Each adapter declares one ranking-bearing vector as `score`. This
is not cosmetic:

  - Reborn Yang scores a rich vector and roulettes over the top 5%, so its selection-time
    scores still carry the full ordering.
  - PBAI's `determine_move_choice` (01_AI_Main.rb:1148) **mutates the score array in place
    and zeroes every entry except the winner**. Its post-pass vector is [0,..,X,..,0] and
    carries no ordering at all. The Hegemony adapter therefore emits the pre-pass (init)
    score as `score`, and keeps the collapsed one as `score_final` for provenance.

Comparing a collapsed vector would report ρ≈0 everywhere and read as "the AIs disagree
wildly" when the truth is "one AI discards its own ranking before we look". The
`degenerate` counter below exists to make that failure loud rather than silent.

Usage:
    python3 ai_diff.py A_scenarios.json A_results.ndjson B_scenarios.json B_results.ndjson \
        [--label-a reborn-yang] [--label-b hegemony] [--field score] [-v] [--json out.json]
"""
import argparse
import json
import sys


def load_side(scn_path, res_path):
    """Return {scenario_id: {move_name: score}} plus the raw records.

    Move IDs are per-engine (Reborn's EARTHQUAKE is 223; another game may number it
    differently), so results are canonicalised back to internal names via that side's own
    scenarios.json `move_ids` map. Cross-engine comparison is only meaningful by name.
    """
    corpus = {s['id']: s for s in json.load(open(scn_path, encoding='utf-8'))}
    vectors, records, errored = {}, {}, {}
    with open(res_path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            sid = r.get('id')
            records[sid] = r
            if 'error' in r:
                errored[sid] = r['error']
                continue
            scn = corpus.get(sid)
            if scn is None:
                continue
            by_id = {v: k for k, v in (scn.get('move_ids') or {}).items()}
            vec = {}
            for m in r.get('moves', []):
                name = by_id.get(m.get('id'))
                score = m.get('score')
                if name is not None and score is not None:
                    vec[name] = score
            vectors[sid] = vec
    return corpus, vectors, records, errored


def avg_ranks(values):
    """Rank descending (best = 1) with ties averaged — the standard Spearman tie
    correction. Without it, tied scores get arbitrary distinct ranks and ρ is inflated or
    deflated depending on input order."""
    order = sorted(range(len(values)), key=lambda i: -values[i])
    ranks = [0.0] * len(values)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and values[order[j + 1]] == values[order[i]]:
            j += 1
        shared = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[order[k]] = shared
        i = j + 1
    return ranks


def pearson(x, y):
    n = len(x)
    mx, my = sum(x) / n, sum(y) / n
    num = sum((a - mx) * (b - my) for a, b in zip(x, y))
    dx = sum((a - mx) ** 2 for a in x)
    dy = sum((b - my) ** 2 for b in y)
    if dx == 0 or dy == 0:
        return None          # zero variance: correlation is undefined, NOT zero
    return num / (dx * dy) ** 0.5


def spearman(a_scores, b_scores):
    """ρ over the shared move set. Returns (rho, n, note)."""
    shared = sorted(set(a_scores) & set(b_scores))
    n = len(shared)
    if n < 2:
        return None, n, 'fewer than 2 shared moves'
    xa = [a_scores[m] for m in shared]
    xb = [b_scores[m] for m in shared]
    if len(set(xa)) == 1 and len(set(xb)) == 1:
        return None, n, 'both sides flat (no ranking on either)'
    if len(set(xa)) == 1:
        return None, n, 'side A flat (all moves scored equal)'
    if len(set(xb)) == 1:
        return None, n, 'side B flat (all moves scored equal)'
    rho = pearson(avg_ranks(xa), avg_ranks(xb))
    note = '' if n >= 3 else 'only 2 shared moves — rho is +/-1 by construction'
    return rho, n, note


def top1(vec):
    """Highest-scoring move name, or None if the vector cannot pick a winner."""
    if not vec:
        return None
    best = max(vec.values())
    winners = [m for m, s in vec.items() if s == best]
    return winners[0] if len(winners) == 1 else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('a_scenarios')
    ap.add_argument('a_results')
    ap.add_argument('b_scenarios')
    ap.add_argument('b_results')
    ap.add_argument('--label-a', default='A')
    ap.add_argument('--label-b', default='B')
    ap.add_argument('--threshold', type=float, default=0.6,
                    help='flag scenarios below this rho (SIM-SPEC 3, default 0.6)')
    ap.add_argument('--json', help='write the full per-scenario table here')
    ap.add_argument('-v', '--verbose', action='store_true')
    args = ap.parse_args()

    _, va, ra, ea = load_side(args.a_scenarios, args.a_results)
    _, vb, rb, eb = load_side(args.b_scenarios, args.b_results)
    A, B = args.label_a, args.label_b

    both = sorted(set(va) & set(vb))
    only_a = sorted(set(va) - set(vb))
    only_b = sorted(set(vb) - set(va))

    rows, rhos = [], []
    agree_top1 = comparable_top1 = 0
    agree_action = comparable_action = 0
    degenerate_a = degenerate_b = 0
    undefined = []

    for sid in both:
        rho, n, note = spearman(va[sid], vb[sid])
        if note.startswith('side A flat') or note.startswith('both sides flat'):
            degenerate_a += 1
        if note.startswith('side B flat') or note.startswith('both sides flat'):
            degenerate_b += 1
        if rho is None:
            undefined.append((sid, note))
        else:
            rhos.append(rho)

        ta, tb = top1(va[sid]), top1(vb[sid])
        if ta is not None and tb is not None:
            comparable_top1 += 1
            if ta == tb:
                agree_top1 += 1

        aa = (ra[sid].get('action') or {}).get('type')
        ab = (rb[sid].get('action') or {}).get('type')
        if aa and ab:
            comparable_action += 1
            if aa == ab:
                agree_action += 1

        rows.append({'id': sid, 'rho': rho, 'shared_moves': n, 'note': note,
                     'top1_a': ta, 'top1_b': tb,
                     'action_a': aa, 'action_b': ab,
                     'scores_a': va[sid], 'scores_b': vb[sid]})

    print('=' * 72)
    print('Tier-2 rank correlation:  %s  vs  %s' % (A, B))
    print('=' * 72)
    print('scenarios in both        : %d' % len(both))
    if rhos:
        mean = sum(rhos) / len(rhos)
        srt = sorted(rhos)
        med = srt[len(srt) // 2] if len(srt) % 2 else (srt[len(srt)//2 - 1] + srt[len(srt)//2]) / 2
        print('mean Spearman rho        : %.3f   (median %.3f, over %d comparable)'
              % (mean, med, len(rhos)))
    else:
        print('mean Spearman rho        : n/a — nothing was comparable')
    if comparable_top1:
        print('top-1 agreement (score)  : %d/%d (%.1f%%)'
              % (agree_top1, comparable_top1, 100.0 * agree_top1 / comparable_top1))
    if comparable_action:
        print('action-type agreement    : %d/%d (%.1f%%)'
              % (agree_action, comparable_action, 100.0 * agree_action / comparable_action))

    # Everything below is a coverage report. A shrinking corpus that still reports a high
    # rho is the failure mode SIM-SPEC 10 names explicitly, so these are never silent.
    print('-' * 72)
    if undefined:
        print('rho undefined            : %d' % len(undefined))
    if degenerate_a:
        print('  !! %-20s : %d scenarios scored every move equal — it has no '
              'ranking to correlate' % (A, degenerate_a))
    if degenerate_b:
        print('  !! %-20s : %d scenarios scored every move equal — it has no '
              'ranking to correlate' % (B, degenerate_b))
    if only_a:
        print('only in %-16s : %d  %s' % (A, len(only_a), only_a[:6]))
    if only_b:
        print('only in %-16s : %d  %s' % (B, len(only_b), only_b[:6]))
    if ea:
        print('errored in %-13s : %d' % (A, len(ea)))
    if eb:
        print('errored in %-13s : %d' % (B, len(eb)))

    flagged = sorted([r for r in rows if r['rho'] is not None and r['rho'] < args.threshold],
                     key=lambda r: r['rho'])
    if flagged:
        print('-' * 72)
        print('worst divergences (rho < %.2f): %d' % (args.threshold, len(flagged)))
        for r in flagged[:15]:
            print('  rho=%+.3f  %-34s %s:%s  vs  %s:%s'
                  % (r['rho'], r['id'], A, r['top1_a'], B, r['top1_b']))

    if args.verbose:
        print('-' * 72)
        for r in rows:
            rho = 'n/a  ' if r['rho'] is None else '%+.3f' % r['rho']
            print('  %s  n=%d  %-34s %s' % (rho, r['shared_moves'], r['id'], r['note']))

    if args.json:
        with open(args.json, 'w', encoding='utf-8') as fh:
            json.dump({'label_a': A, 'label_b': B, 'rows': rows,
                       'only_a': only_a, 'only_b': only_b,
                       'errored_a': ea, 'errored_b': eb}, fh, indent=2)
        print('\nwrote per-scenario table to %s' % args.json)

    # Exit non-zero only when nothing could be compared. A low rho is a finding to read,
    # not a build failure — that judgement belongs to whoever is doing the port.
    sys.exit(0 if rhos else 2)


if __name__ == '__main__':
    main()
