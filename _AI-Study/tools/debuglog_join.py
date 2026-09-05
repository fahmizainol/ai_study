"""Join Reborn's debuglog (blank-name test env) to the gauntlet ndjson trace.
Usage: python3 joinlog.py <ndjson> <debuglog> -> prints per-turn table for index 1."""
import json,re,sys,collections
PBS="../Reborn Yang/Reborn Yang/PBS/PBS/moves.txt"
MOVES={}
for line in open(PBS,encoding='utf-8',errors='replace'):
    p=line.split(',')
    if len(p)>8 and p[0].isdigit(): MOVES[int(p[0])]=(p[1],int(p[4]) if p[4].isdigit() else 0,p[7])
def parse_log(path):
    battles={}; cur=None; rnd=None; block=None
    for raw in open(path,encoding='utf-8',errors='replace'):
        line=raw.rstrip('\r\n')
        m=re.match(r'^=== (\S+) seed (\d+) arm (\S+) ===',line)
        if m: cur=battles.setdefault((m.group(1),int(m.group(2))),{}); rnd=None; continue
        if cur is None: continue
        m=re.match(r'^\*\*\*Round (\d+)\*\*\*',line)
        if m: rnd=cur.setdefault(int(m.group(1))-1,{'blocks':[],'vectors':[],'switch':[]}); continue
        if rnd is None: continue
        m=re.match(r'^Scoring for battler: spc:(\d+) , HP percentage: ([\d.]+) %',line)
        if m: block={'species':int(m.group(1)),'hp':float(m.group(2)),'expected':[],'moves':{}}; rnd['blocks'].append(block); continue
        m=re.match(r'^Expected Damage taken from\s*\|([\d.]+) %',line)
        if m and block: block['expected'].append(float(m.group(1))); continue
        m=re.match(r'^mv:(\d+) vs , (Init|Final) scoring move:\s*\|(-?[\d.]*)',line)
        if m and block:
            d=block['moves'].setdefault(int(m.group(1)),{}); d[m.group(2)]=float(m.group(3)) if m.group(3) else None; continue
        m=re.match(r'^\[: (.*)\]$',line)
        if m: rnd['vectors'].append([int(x) for x in re.findall(r'=\[(-?\d+),',m.group(1))]); continue
        m=re.match(r'^ShouldSwitchScore: (-?[\d.]+)',line)
        if m: rnd['switch'].append(float(m.group(1)))
    return battles
def st(rec,turn,phase,idx):
    for c in rec['commands']:
        if c['turn']==turn and c['phase']==phase:
            for a in c['actors']:
                if a['index']==idx: return a
def rows(ndjson,log):
    battles=parse_log(log); out=[]
    for r in map(json.loads,open(ndjson)):
        lb=battles.get((r['id'],r['seed']),{})
        for t in r.get('portable_trace') or []:
            if t['actor']!=1: continue
            v=t.get('view') or {}
            now=st(r,t['turn'],'command',1); end=st(r,t['turn'],'round_end',1)
            fnow=st(r,t['turn'],'command',0); fend=st(r,t['turn'],'round_end',0)
            if not(now and end and fnow): continue
            foe_move=fnow.get('move_id'); fm=MOVES.get(foe_move,('?',0,'?')) if foe_move else ('none',0,'')
            actual=(now['hp']-end['hp'])/now['totalhp']*100 if end['party_slot']==now['party_slot'] else None
            died= end['hp']==0 or (end['party_slot']!=now['party_slot'] and t['type']!='switch')
            blk=None
            for b in lb.get(t['turn'],{}).get('blocks',[]):
                if b['species']==now['species'] and b['expected']: blk=b
            out.append(dict(id=r['id'],seed=r['seed'],turn=t['turn'],species=now['species'],hp=now['hp']/now['totalhp']*100,
                foe=fnow['species'],foe_choice=fnow.get('choice'),foe_move=fm[0],foe_bp=fm[1],foe_slot=None,
                est=v.get('incoming_damage_pct'),by_move=v.get('incoming_by_move'),faster=v.get('faster'),
                reborn_exp=(blk['expected'][0] if blk else None),actual=actual,died=died,chosen=t['move_id'] or t['type'],
                refused=any(k=='heal_cannot_resolve' for c in t.get('candidates') or [] for k,_ in c.get('reasons',[]))))
    return out
if __name__=='__main__':
    R=rows(sys.argv[1],sys.argv[2])
    print('rows',len(R),'with reborn_exp',sum(1 for x in R if x['reborn_exp'] is not None))
    # Portable estimate vs Reborn's expected vs actual, on turns where the foe used a damaging move and actor survived same slot
    import statistics
    ratios=[];rr=[]
    for x in R:
        if x['foe_choice']==1 and x['foe_bp']>0 and x['actual'] is not None and x['est']:
            ratios.append(x['actual']/x['est'])
            if x['reborn_exp']: rr.append(x['reborn_exp']/x['est'])
    print('actual/portable_est on damaging-foe-move turns: n=%d median=%.2f mean=%.2f'%(len(ratios),statistics.median(ratios),statistics.mean(ratios)))
    print('reborn_exp/portable_est: n=%d median=%.2f'%(len(rr),statistics.median(rr)))
    print('\nrefused-heal turns where actor survived:')
    for x in R:
        if x['refused'] and not x['died']:
            print(' %-20s %6d t%-3d spc%-4d hp%5.1f%% est%6.1f%% rebornExp%6s faster=%-5s foe spc%-4d did %-14s bp%-3d actual=%s chosen=%s'%(x['id'],x['seed'],x['turn'],x['species'],x['hp'],x['est'] or -1,x['reborn_exp'],x['faster'],x['foe'],('switch' if x['foe_choice']==2 else x['foe_move']),x['foe_bp'],('%.1f%%'%x['actual']) if x['actual'] is not None else None,x['chosen']))
