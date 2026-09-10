#!/usr/bin/env python3
"""Render one traced gauntlet battle as readable text.
Usage: python3 tools/render_battle.py <ndjson> <matchup_id> <seed> [--arm=normal_reborn]"""
import json,sys,re,collections
from pathlib import Path
args=[a for a in sys.argv[1:] if not a.startswith('--')]
ARM=next((a.split('=',1)[1] for a in sys.argv[1:] if a.startswith('--arm=')),'normal_portable')
SPECIES={}; cur=None
MOVES={}
game=Path(__file__).resolve().parents[2]/'Reborn Yang'
pbs=game/'PBS'/'PBS'
if pbs.exists():
    for line in (pbs/'pokemon.txt').read_text(encoding='utf-8',errors='replace').splitlines():
        m=re.match(r'^\[(\d+)\]',line)
        if m: cur=int(m.group(1)); continue
        if cur and line.startswith('Name='): SPECIES[cur]=line.split('=',1)[1].strip()
    for line in (pbs/'moves.txt').read_text(encoding='utf-8',errors='replace').splitlines():
        p=line.split(',')
        if p[0].isdigit(): MOVES[int(p[0])]=p[2]
else:
    def constants(path):
        out={}
        for line in path.read_text(encoding='utf-8',errors='replace').splitlines():
            m=re.match(r'^([A-Z][A-Z0-9_]*)\s*=\s*(\d+)$',line)
            if m: out[int(m.group(2))]=m.group(1).replace('_',' ').title()
        return out
    SPECIES=constants(game/'Scripts'/'Reborn'/'PBSpecies.rb')
    MOVES=constants(game/'Scripts'/'Reborn'/'PBMoves.rb')
STATUS={0:'',1:'SLP',2:'PSN',3:'BRN',4:'PAR',5:'FRZ'}
def sp(i): return SPECIES.get(i,'spc%s'%i)
def mv(i): return MOVES.get(i,'mv%s'%i) if i else '-'
rec=None
for l in open(args[0]):
    r=json.loads(l)
    if r['id']==args[1] and r['seed']==int(args[2]) and r.get('arm','normal_portable')==ARM: rec=r
if not rec: sys.exit('battle not found')
left,right=rec['left_reborn_team'],rec['right_test_team']
rounds=sum(1 for c in rec.get('commands') or [] if c.get('phase')=='command')
# final_parties: [left party, right party], each [species, hp, totalhp] in slot order
parties=rec.get('final_parties') or [[],[]]
def slotname(side,slot):
    try: return sp(parties[side][slot][0])
    except Exception: return 'slot%s'%slot
# Both arms name the run's Portable version: a stock-Reborn readout is only the
# baseline of the run it was recorded in (the harness has changed under it before).
RIGHT='Portable %s'%rec.get('portable_version','?') if ARM=='normal_portable' else 'Reborn-Normal (right seat, %s run)'%rec.get('portable_version','?')
print('%s  seed %d   Reborn-Normal (%s, left) vs %s (%s, right)   result for right seat: %s in %d rounds (engine turncount %d)'%(rec['id'],rec['seed'],left,RIGHT,right,rec['result'].upper(),rounds,rec['turns']))
print('  Reborn   (%s): %s'%(left,', '.join(sp(m[0]) for m in parties[0])))
print('  %-8s (%s): %s'%('Portable' if ARM=='normal_portable' else 'RebornR',right,', '.join(sp(m[0]) for m in parties[1])))
print('='*110)
trace=collections.defaultdict(dict)
for t in rec.get('portable_trace') or []: trace[t['turn']][t['actor']]=t
cmds=collections.defaultdict(dict)
for c in rec['commands']: cmds[c['turn']][c['phase']]=c
# Per-move events: what the engine actually executed, so a miss, a Protect, an
# immunity and a blocked user stop looking like "hit for nothing" (see the gauntlet's
# event hooks). Absent from traces recorded before they existed.
events=collections.defaultdict(list)
for e in rec.get('events') or []: events[e['turn']].append(e)
SIDE=lambda i:'Reborn' if i%2==0 else ('Portable' if ARM=='normal_portable' else 'RebornR')
def battler_name(actors,index):
    actor=actors.get(index)
    return sp(actor['species']) if actor else '%s battler %s'%(SIDE(index),index)
def fmtev(e,actors):
    bits=[]
    for t in e.get('targets') or []:
        hits=t.get('hits') or []
        # typemod/crit come from the hits: Reborn's neutral is 4, and a damagestate
        # read after the move has often been reset back to 0.
        eff=(hits[-1]['typemod']/4.0) if hits else None
        relation='self' if t['index']==e['user'] else battler_name(actors,t['index'])
        bits.append('%s %s%s%s%s'%(relation,
            '-%d'%t['hp_lost'] if t['hp_lost'] else '0',
            ' x%d'%len(hits) if len(hits)>1 else '',
            ' CRIT' if any(h.get('crit') for h in hits) else '',
            '' if eff in (None,1) else (' immune' if eff==0 else ' x%g'%eff)))
    self_hp=(e.get('hp_delta') or {}).get(str(e['user']))
    if self_hp: bits.append('user %+d'%self_hp)
    why=' '.join('%s=%s'%(k,e[k]) for k in ('status','status_count','flinch','confusion') if k in e)
    return '%-12s used %-14s %-14s %s%s'%(battler_name(actors,e['user']),mv(e['move']),
                                           e['outcome'],', '.join(bits),
                                           (' ['+why+']') if why else '')
def fmt(a): return '%s %d/%d%s'%(sp(a['species']),a['hp'],a['totalhp'],(' '+STATUS.get(a['status'],'')) if a.get('status') else '')
for turn in sorted(cmds):
    cmd=cmds[turn].get('command'); end=cmds[turn].get('round_end')
    if not cmd: continue
    A={a['index']:a for a in cmd['actors']}; E={a['index']:a for a in end['actors']} if end else {}
    turn_events=events.get(turn,[])
    def act(a):
        if a.get('choice')==2: return 'switch->%s'%slotname(a['index']%2,a['switch_slot'])
        target=a.get('target')
        executed=next((e for e in turn_events
                       if e.get('user')==a['index'] and e.get('move')==a.get('move_id')),None)
        if executed and executed.get('outcome')=='untargeted': target=None
        return '%s%s'%(mv(a.get('move_id')),
                       (' -> %s'%battler_name(A,target)) if target not in (None,-1) else '')
    print('\nTurn %d'%(turn+1))
    for index in sorted(A):
        print('  %-9s %-24s -> %s'%(SIDE(index),fmt(A[index]),act(A[index])))
    for actor_index,t in sorted(trace.get(turn,{}).items()):
        print('    %s plan score %.1f, joint adjustment %.1f'%(
              battler_name(A,actor_index),t.get('score') or 0,t.get('joint_adjustment') or 0))
        v=t.get('view') or {}
        if v:
            print('    view: hp %.0f%%  speed %s (%s)  incoming max %.0f%%  certain %s  threatened=%s'%(v.get('hp_pct') or 0,v.get('speed'),'faster' if v.get('faster') else 'slower',v.get('incoming_damage_pct') or 0,('%.0f%%'%v['certain_incoming_damage_pct']) if v.get('certain_incoming_damage_pct') is not None else 'n/a',v.get('threatened_lethal')))
            bym=v.get('incoming_by_move') or {}
            if bym: print('    foe moves est: '+', '.join('%s %.0f%%'%(mv(int(k.split(':')[1])),d) for k,d in sorted(bym.items(),key=lambda x:-x[1])))
        for i,c in enumerate(t.get('candidates') or []):
            name=c['move_id'] or ('switch->%s'%slotname(1,c['slot']))
            if c.get('move_id') and c.get('target') not in (None,-1):
                name += ' -> '+battler_name(A,c['target'])
            rs=' '.join('%s%+.0f'%(k,d) for k,d in c.get('reasons',[]) if k!='engine_base' and abs(d)<900000) or ('no_escape_reason' if any(k=='no_escape_reason' for k,_ in c.get('reasons',[])) else '')
            chosen=(c.get('type')==t.get('type') and c.get('slot')==t.get('slot') and
                    c.get('move_id')==t.get('move_id') and c.get('target')==t.get('target'))
            print('    %s %-28s %7.0f  %s'%('*' if chosen else ' ',name,c['score'],rs))
    for e in turn_events:
        flag='!' if e['move']!=(A.get(e['user']) or {}).get('move_id') else ' '
        print('   %s%s'%(flag,fmtev(e,A)))
    if end:
        print('  end:     '+ ' | '.join('%s %s'%(SIDE(i),fmt(E[i])) for i in sorted(E)))
