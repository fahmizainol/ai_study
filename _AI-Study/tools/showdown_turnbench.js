// Steady-state: construction timed separately from turns; clone timed separately.
const P = '/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown';
const { Battle } = require(P + '/dist/sim/battle');
const T = require('./teams.js');
const mk = () => { const b = new Battle({ formatid: 'gen5customgame', seed: [1,2,3,4] });
  b.setPlayer('p1', {name:'A', team:T.a}); b.setPlayer('p2', {name:'B', team:T.b}); return b; };
function step(b) {
  for (const side of b.sides) {
    const req = side.activeRequest; if (!req || req.wait) continue;
    if (req.teamPreview) { b.choose(side.id, 'team 123'); continue; }
    if (req.forceSwitch) { const o = side.pokemon.map((p,i)=>(!p.isActive&&!p.fainted)?i+1:0).filter(Boolean);
      b.choose(side.id, req.forceSwitch.map(f=>f?`switch ${o.shift()}`:'pass').join(', ')); continue; }
    b.choose(side.id, req.active.map(a=>{ const m=a.moves.map((x,j)=>x.disabled?0:j+1).filter(Boolean);
      return `move ${m.length?m[b.prng.random(m.length)]:1}`; }).join(', '));
  }
}
// warm up the JIT and the dex caches
for (let i=0;i<40;i++){ const b=mk(); for(let t=0;t<30&&!b.ended;t++) step(b); }
let turns=0, ns=0n, cns=0n, builds=0, bns=0n;
for (let rep=0; rep<120; rep++) {
  let s=process.hrtime.bigint(); const b=mk(); bns+=process.hrtime.bigint()-s; builds++;
  s=process.hrtime.bigint();
  let t=0; while(!b.ended && t<40){ step(b); t++; }
  ns+=process.hrtime.bigint()-s; turns+=t;
}
const mid=mk(); for(let t=0;t<6;t++) step(mid);
for (let i=0;i<300;i++){ const s=process.hrtime.bigint(); Battle.fromJSON(mid.toJSON()); cns+=process.hrtime.bigint()-s; }
console.log(`turn ${(Number(ns)/1e6/turns).toFixed(3)} ms  construct ${(Number(bns)/1e6/builds).toFixed(3)} ms  clone ${(Number(cns)/1e6/300).toFixed(3)} ms  (${turns} turns)`);
