#!/usr/bin/env python3
"""Render one traced gauntlet battle as readable text.
Usage: python3 tools/render_battle.py <ndjson> <matchup_id> <seed> [--arm=normal_reborn]"""
import json,sys,re,collections
args=[a for a in sys.argv[1:] if not a.startswith('--')]
ARM=next((a.split('=',1)[1] for a in sys.argv[1:] if a.startswith('--arm=')),'normal_portable')
PBS='../Reborn Yang/Reborn Yang/PBS/PBS'
SPECIES={}; cur=None
for line in open(PBS+'/pokemon.txt',encoding='utf-8',errors='replace'):
    m=re.match(r'^\[(\d+)\]',line)
    if m: cur=int(m.group(1)); continue
    if cur and line.startswith('Name='): SPECIES[cur]=line.split('=',1)[1].strip()
MOVES={}
for line in open(PBS+'/moves.txt',encoding='utf-8',errors='replace'):
    p=line.split(',')
    if p[0].isdigit(): MOVES[int(p[0])]=p[2]
STATUS={0:'',1:'SLP',2:'PSN',3:'BRN',4:'PAR',5:'FRZ'}
def sp(i): return SPECIES.get(i,'spc%s'%i)
def mv(i): return MOVES.get(i,'mv%s'%i) if i else '-'
rec=None
for l in open(args[0]):
    r=json.loads(l)
    if r['id']==args[1] and r['seed']==int(args[2]) and r.get('arm','normal_portable')==ARM: rec=r
if not rec: sys.exit('battle not found')
left,right=rec['left_reborn_team'],rec['right_test_team']
# final_parties: [left party, right party], each [species, hp, totalhp] in slot order
parties=rec.get('final_parties') or [[],[]]
def slotname(side,slot):
    try: return sp(parties[side][slot][0])
    except Exception: return 'slot%s'%slot
# Both arms name the run's Portable version: a stock-Reborn readout is only the
# baseline of the run it was recorded in (the harness has changed under it before).
RIGHT='Portable %s'%rec.get('portable_version','?') if ARM=='normal_portable' else 'Reborn-Normal (right seat, %s run)'%rec.get('portable_version','?')
print('%s  seed %d   Reborn-Normal (%s, left) vs %s (%s, right)   result for right seat: %s in %d turns'%(rec['id'],rec['seed'],left,RIGHT,right,rec['result'].upper(),rec['turns']))
print('  Reborn   (%s): %s'%(left,', '.join(sp(m[0]) for m in parties[0])))
print('  %-8s (%s): %s'%('Portable' if ARM=='normal_portable' else 'RebornR',right,', '.join(sp(m[0]) for m in parties[1])))
print('='*110)
trace={t['turn']:t for t in rec.get('portable_trace') or [] if t['actor']==1}
cmds=collections.defaultdict(dict)
for c in rec['commands']: cmds[c['turn']][c['phase']]=c
# Per-move events: what the engine actually executed, so a miss, a Protect, an
# immunity and a blocked user stop looking like "hit for nothing" (see the gauntlet's
# event hooks). Absent from traces recorded before they existed.
events=collections.defaultdict(list)
for e in rec.get('events') or []: events[e['turn']].append(e)
SIDE=lambda i:'Reborn' if i%2==0 else ('Portable' if ARM=='normal_portable' else 'RebornR')
def fmtev(e):
    bits=[]
    for t in e.get('targets') or []:
        hits=t.get('hits') or []
        # typemod/crit come from the hits: Reborn's neutral is 4, and a damagestate
        # read after the move has often been reset back to 0.
        eff=(hits[-1]['typemod']/4.0) if hits else None
        bits.append('%s %s%s%s%s'%('self' if t['index']==e['user'] else 'foe',
            '-%d'%t['hp_lost'] if t['hp_lost'] else '0',
            ' x%d'%len(hits) if len(hits)>1 else '',
            ' CRIT' if any(h.get('crit') for h in hits) else '',
            '' if eff in (None,1) else (' immune' if eff==0 else ' x%g'%eff)))
    self_hp=(e.get('hp_delta') or {}).get(str(e['user']))
    if self_hp: bits.append('user %+d'%self_hp)
    why=' '.join('%s=%s'%(k,e[k]) for k in ('status','status_count','flinch','confusion') if k in e)
    return '%-8s %-14s %-14s %s%s'%(SIDE(e['user']),mv(e['move']),e['outcome'],
                                    ', '.join(bits),(' ['+why+']') if why else '')
def fmt(a): return '%s %d/%d%s'%(sp(a['species']),a['hp'],a['totalhp'],(' '+STATUS.get(a['status'],'')) if a.get('status') else '')
for turn in sorted(cmds):
    cmd=cmds[turn].get('command'); end=cmds[turn].get('round_end')
    if not cmd: continue
    A={a['index']:a for a in cmd['actors']}; E={a['index']:a for a in end['actors']} if end else {}
    def act(a): return ('switch->%s'%slotname(a['index']%2,a['switch_slot'])) if a.get('choice')==2 else mv(a.get('move_id'))
    print('\nTurn %d'%(turn+1))
    print('  Reborn   %-28s -> %s'%(fmt(A[0]),act(A[0])))
    print('  %-8s %-28s -> %s'%('Portable' if ARM=='normal_portable' else 'RebornR',fmt(A[1]),act(A[1])))
    t=trace.get(turn)
    if t:
        v=t.get('view') or {}
        if v:
            print('    view: hp %.0f%%  speed %s (%s)  incoming max %.0f%%  certain %s  threatened=%s'%(v.get('hp_pct') or 0,v.get('speed'),'faster' if v.get('faster') else 'slower',v.get('incoming_damage_pct') or 0,('%.0f%%'%v['certain_incoming_damage_pct']) if v.get('certain_incoming_damage_pct') is not None else 'n/a',v.get('threatened_lethal')))
            bym=v.get('incoming_by_move') or {}
            if bym: print('    foe moves est: '+', '.join('%s %.0f%%'%(mv(int(k.split(':')[1])),d) for k,d in sorted(bym.items(),key=lambda x:-x[1])))
        for i,c in enumerate(t.get('candidates') or []):
            name=c['move_id'] or ('switch->%s'%slotname(1,c['slot']))
            rs=' '.join('%s%+.0f'%(k,d) for k,d in c.get('reasons',[]) if k!='engine_base' and abs(d)<900000) or ('no_escape_reason' if any(k=='no_escape_reason' for k,_ in c.get('reasons',[])) else '')
            print('    %s %-14s %7.0f  %s'%('*' if i==0 else ' ',name,c['score'],rs))
    for e in events.get(turn,[]):
        flag='!' if e['move']!=(A.get(e['user']) or {}).get('move_id') else ' '
        print('   %s%s'%(flag,fmtev(e)))
    if end:
        print('  end:     Reborn %-24s | right %s'%(fmt(E[0]) if 0 in E else '?',fmt(E[1]) if 1 in E else '?'))
