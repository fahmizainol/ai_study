"""Audit Portable's incoming-damage threat model against what actually happened.
Usage: python3 threat_audit.py <ndjson with view+incoming_by_move> [debuglog]"""
import json,sys,collections,statistics
sys.path.insert(0, __import__('os').path.dirname(__file__))
from debuglog_join import MOVES,st
STATUS={0:'none',1:'SLEEP',2:'poison',3:'burn',4:'PARALYSIS',5:'FROZEN'}
recs=[json.loads(l) for l in open(sys.argv[1])]
per_move=[]; cause=collections.defaultdict(collections.Counter); sleep_threat=collections.Counter()
detail=collections.defaultdict(list)
for r in recs:
    for t in r.get('portable_trace') or []:
        if t['actor']!=1: continue
        v=t.get('view') or {}
        now=st(r,t['turn'],'command',1); end=st(r,t['turn'],'round_end',1); fnow=st(r,t['turn'],'command',0); fend=st(r,t['turn'],'round_end',0)
        if not(now and end and fnow and fend): continue
        cands=t.get('candidates') or []
        refused=any(k=='heal_cannot_resolve' for c in cands for k,_ in c.get('reasons',[]))
        knl=bool(cands) and 'ko_never_lands' in {k for k,_ in cands[0].get('reasons',[])}
        fs=STATUS.get(fnow.get('status'),'?')
        if v.get('threatened_lethal'): sleep_threat[fs]+=1
        died= end['hp']==0 or (end['party_slot']!=now['party_slot'] and t['type']!='switch')
        same_slot = end['party_slot']==now['party_slot'] and t['type']!='switch'
        actual=(now['hp']-end['hp'])/now['totalhp']*100 if same_slot else None
        fm=MOVES.get(fnow.get('move_id'),('?',0,'?')) if fnow.get('choice')==1 else None
        bym=v.get('incoming_by_move') or {}
        est_move=bym.get('0:%d'%fnow['move_id']) if fm else None
        est_max=v.get('incoming_damage_pct')
        # (a) estimator accuracy: foe executed a damaging move, was not asleep/frozen, actor stayed in, hit landed (actual>0)
        if fm and fm[1]>0 and fs not in ('SLEEP','FROZEN') and actual is not None and est_move:
            per_move.append((actual/est_move, fm[0], fm[2], actual, est_move, r['id'], r['seed'], t['turn']))
        # (b)/(c) decomposition of survived false positives
        for rule,flag in (('refused_heal',refused),('ko_never_lands',knl)):
            if not flag: continue
            foe_koed = fnow.get('choice')!=2 and fend['party_slot']!=fnow['party_slot']
            if died: c='died (rule right)'
            elif fs in ('SLEEP','FROZEN'): c='foe asleep/frozen'
            elif fnow.get('choice')==2: c='foe switched'
            elif fm is None or fm[1]==0: c='foe used non-damaging move'
            elif est_move is not None and est_max and est_move < est_max*0.9: c='foe used weaker move than max'
            elif actual is not None and actual<=0: c='max move used but did 0 (miss/protect/immune)'
            elif actual is not None and est_move and actual < 0.85*est_move*0.95: c='max move hit but undershot min-roll (estimate error)'
            else: c='max move hit as estimated, actor still alive (roll/threshold)'
            if foe_koed and not died: c += ' [we KOd the foe]'
            cause[rule][c]+=1
            if len(detail[(rule,c)])<4: detail[(rule,c)].append('%s %d t%d spc%d hp%.0f%% est%.0f%% foe spc%d %s actual=%s'%(r['id'],r['seed'],t['turn'],now['species'],now['hp']/now['totalhp']*100,est_max or 0,fnow['species'],(fm[0] if fm else ('switch' if fnow.get('choice')==2 else 'other')),('%.0f%%'%actual) if actual is not None else None))
print('battles',len(recs))
if per_move:
    rs=[x[0] for x in per_move]
    print('\n(a) actual / per-move estimate, foe executed a damaging move (awake): n=%d median=%.2f  q25=%.2f q75=%.2f  share<0.85=%.0f%%  share==0=%.0f%%'%(len(rs),statistics.median(rs),sorted(rs)[len(rs)//4],sorted(rs)[3*len(rs)//4],100*sum(x<0.85 for x in rs)/len(rs),100*sum(x==0 for x in rs)/len(rs)))
    hits=[x for x in rs if x>0]
    print('    landed hits only: n=%d median=%.2f q25=%.2f q75=%.2f share<0.80=%.0f%%'%(len(hits),statistics.median(hits),sorted(hits)[len(hits)//4],sorted(hits)[3*len(hits)//4],100*sum(x<0.8 for x in hits)/len(hits)))
    low=sorted(per_move)[:12]
    print('    worst undershoots (ratio, move, cat, actual%, est%, battle):'); [print('      %.2f %-14s %-8s %5.1f %5.1f %s %d t%d'%x) for x in low]
for rule,c in cause.items():
    print('\n(b) %s outcomes:'%rule)
    for k,n in c.most_common(): print('    %-58s %d'%(k,n))
print('\n(d) foe status on turns Portable felt threatened_lethal:',dict(sleep_threat))
print('\nexamples:')
for k,v in detail.items():
    if 'rule right' in k[1]: continue
    print(' ',k); [print('     ',x) for x in v]
