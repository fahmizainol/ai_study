#!/usr/bin/env python3
"""Parse a Reborn-family `Data/debuglog.txt` into canonical decision records.

Proves SIM-SPEC.md §4 against real data: Reborn Yang's existing PBDebug output already
contains everything the schema asks for (init + final move scores, item scores, switch
score, chosen action), so the Reborn adapter is a *format* problem, not a plumbing one.

Usage:
    python3 parse_reborn_log.py <debuglog.txt> [-o out.ndjson] [--stats]
"""
import argparse
import json
import re
import sys

RE_BATTLER = re.compile(r'^Scoring for battler:\s*(.+?)\s*,\s*HP percentage:\s*([\d.]+)\s*%')
RE_CONTEXT = re.compile(r'^Held Item:\s*(.*?)\s*,\s*Ability:\s*(.*?)\s*,\s*Field:\s*(.*?)\s*$')
# Two shapes:
#   gameplay logs   "Ice Beam - 0 vs Aerodactyl, Init scoring move:   |110"
#   AI_Harness logs "mv:243 vs , Init scoring move:                   |32"
# The harness emits numeric IDs because PBMoves.getName needs MessageTypes' indexed
# tables, which are only built on the compile path. Resolve via --pbs instead.
RE_MOVE = re.compile(
    r'^(.*?)(?:\s+-\s+(\d+))?\s+vs\s*(.*?),\s*(Init|Final) scoring move:\s*\|\s*(-?[\d.]+)')
RE_ID = re.compile(r'^(mv|spc|itm):(\d+)$')
RE_SWITCH = re.compile(r'^Scoring for Switching to other mon\s*\|\s*(-?[\d.]+)')
RE_ITEM = re.compile(r'^([A-Z][A-Za-z \'-]+?)\s*\|\s*(-?[\d.]+)\s*$')
RE_PREFER = re.compile(r'^\[Prefer\s+(.+?)\]')
RE_FOE_ARRAY = re.compile(r'^\[(?:The foe|The)?\s*(.+?):\s*(.+)\]$')
RE_SWITCH_CAND = re.compile(r'^Scoring for (.+?) switching to:\s*(.+?)\s*$')
RE_SWITCH_SCORE = re.compile(r'^Final Pokemon Score:\s*(-?[\d.]+)')


def load_pbs(pbs_dir):
    """id -> name maps from Reborn's plaintext PBS. Avoids depending on the engine's
    message tables, which the harness cannot populate."""
    import os
    maps = {'mv': {}, 'itm': {}, 'spc': {}}
    def csv_map(fname, key):
        path = os.path.join(pbs_dir, fname)
        if not os.path.exists(path):
            return
        for line in open(path, encoding='utf-8', errors='replace'):
            f = line.split(',')
            if len(f) >= 3 and f[0].strip().isdigit():
                maps[key][f[0].strip()] = f[2].strip()
    csv_map('moves.txt', 'mv')
    csv_map('items.txt', 'itm')
    path = os.path.join(pbs_dir, 'pokemon.txt')
    if os.path.exists(path):
        cur = None
        for line in open(path, encoding='utf-8', errors='replace'):
            line = line.strip()
            m = re.match(r'^\[(\d+)\]$', line)
            if m:
                cur = m.group(1)
            elif cur and line.startswith('Name='):
                maps['spc'][cur] = line[5:].strip()
                cur = None
    return maps


def resolve(val, maps):
    if not maps or not isinstance(val, str):
        return val
    m = RE_ID.match(val.strip())
    if not m:
        return val
    return maps.get(m.group(1), {}).get(m.group(2), val)


def num(s):
    f = float(s)
    return int(f) if f.is_integer() else f


def parse(path, maps=None):
    """Yield one record per 'Scoring for battler' block."""
    with open(path, encoding='utf-8', errors='replace') as fh:
        lines = fh.read().splitlines()

    # NOTE ON ORDERING: `[Prefer X]` and the switch-candidate blocks are written by
    # PBDebug.log immediately, while logAIScorings() buffers a whole block and dumps it
    # afterwards. So both PRECEDE the "Scoring for battler" block they belong to. Buffer
    # them and attach to the *next* block, not the previous one.
    records = []
    cur = None
    in_items = False
    pending_switch = None
    pending_prefer = None
    pending_switch_scores = []

    def flush():
        nonlocal cur
        if cur:
            cur['move_scores'] = [m for m in cur['move_scores'].values()]
            cur['move_scores'].sort(key=lambda m: -(m.get('final') or -10**9))
            for i, m in enumerate(cur['move_scores'], 1):
                m['rank'] = i
            records.append(cur)
        cur = None

    for ln in lines:
        m = RE_BATTLER.match(ln)
        if m:
            flush()
            cur = {
                'schema': 1, 'engine': 'reborn-yang', 'ai': 'reborn-e19+yang',
                'source': 'debuglog',
                'actor': {'species': resolve(m.group(1), maps), 'hp_pct': num(m.group(2)),
                          'item': None, 'ability': None},
                'context': {'field': None},
                'move_scores': {}, 'item_scores': [],
                'switch_scores': pending_switch_scores,
                'should_switch_score': None,
                'chosen': ({'type': 'move', 'move': pending_prefer}
                           if pending_prefer else None),
            }
            pending_prefer = None
            pending_switch_scores = []
            in_items = False
            continue

        # Buffered-before-block lines (see ORDERING note above).
        sc = RE_SWITCH_CAND.match(ln)
        if sc:
            pending_switch = sc.group(2)
            continue
        if pending_switch:
            ss = RE_SWITCH_SCORE.match(ln)
            if ss:
                pending_switch_scores.append(
                    {'species': pending_switch, 'score': num(ss.group(1))})
                pending_switch = None
                continue

        p = RE_PREFER.match(ln)
        if p:
            pending_prefer = p.group(1).strip()
            continue

        if cur is None:
            continue

        c = RE_CONTEXT.match(ln)
        if c:
            cur['actor']['item'] = resolve(c.group(1), maps) or None
            cur['actor']['ability'] = c.group(2) or None
            cur['context']['field'] = c.group(3) or None
            continue

        s = RE_SWITCH.match(ln)
        if s:
            cur['should_switch_score'] = num(s.group(1))
            continue

        if ln.startswith('Scoring for items'):
            in_items = True
            continue

        mv = RE_MOVE.match(ln)
        if mv:
            in_items = False
            name, target, opp, kind, val = mv.groups()
            target = target or '0'
            key = (name.strip(), target)
            rec = cur['move_scores'].setdefault(
                key, {'move': name.strip(), 'target': int(target),
                      'vs': opp.strip(), 'init': None, 'final': None})
            rec['move'] = resolve(rec['move'], maps)
            rec['init' if kind == 'Init' else 'final'] = num(val)
            continue

        if in_items:
            it = RE_ITEM.match(ln)
            if it:
                cur['item_scores'].append(
                    {'item': it.group(1).strip(), 'score': num(it.group(2))})
                continue

    flush()
    return records


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('log')
    ap.add_argument('-o', '--out')
    ap.add_argument('--stats', action='store_true')
    ap.add_argument('--pbs', help='PBS dir for id->name resolution')
    a = ap.parse_args()

    maps = load_pbs(a.pbs) if a.pbs else None
    recs = parse(a.log, maps)

    if a.out:
        with open(a.out, 'w', encoding='utf-8') as fh:
            for r in recs:
                fh.write(json.dumps(r, ensure_ascii=False) + '\n')
        print(f'wrote {len(recs)} records to {a.out}')

    if a.stats or not a.out:
        withmoves = [r for r in recs if r['move_scores']]
        chosen = [r for r in recs if r['chosen']]
        adjusted = sum(1 for r in recs for m in r['move_scores']
                       if m['init'] is not None and m['final'] is not None
                       and m['init'] != m['final'])
        # Did the AI take its own top-ranked move?
        agree = sum(1 for r in chosen if r['move_scores']
                    and r['chosen']['move'] == r['move_scores'][0]['move'])
        print(f'decision blocks      : {len(recs)}')
        print(f'  with move scores   : {len(withmoves)}')
        print(f'  with chosen action : {len(chosen)}')
        print(f'  switch scores      : {sum(len(r["switch_scores"]) for r in recs)}')
        print(f'  item scores        : {sum(len(r["item_scores"]) for r in recs)}')
        print(f'moves rescored init->final : {adjusted}')
        if chosen:
            print(f'chose own top-ranked move  : {agree}/{len(chosen)} '
                  f'({100.0*agree/len(chosen):.1f}%)')
        if recs:
            print('\n--- sample record ---')
            sample = next((r for r in recs if r['move_scores'] and r['chosen']), recs[0])
            print(json.dumps(sample, indent=2, ensure_ascii=False)[:900])


if __name__ == '__main__':
    main()
