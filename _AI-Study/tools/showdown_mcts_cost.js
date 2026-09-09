// What one Foul-Play-shaped MCTS iteration costs on Showdown: no rollout, a static
// leaf evaluation, and a cloned Battle per node (the only way to descend, since
// Showdown cannot undo a turn the way poke-engine's instruction lists can).
//   node showdown_mcts_cost.js [singles|doubles]
const P = '/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown';
const { Battle } = require(P + '/dist/sim/battle');
const T = require('./showdown_teams.js');
const gameType = process.argv[2] || 'singles';
const formatid = gameType === 'doubles' ? 'gen5doublescustomgame' : 'gen5customgame';

function mk() {
  const b = new Battle({ formatid, seed: [1, 2, 3, 4] });
  b.setPlayer('p1', { name: 'A', team: T.a }); b.setPlayer('p2', { name: 'B', team: T.b });
  return b;
}
function step(b) {
  for (const side of b.sides) {
    const req = side.activeRequest; if (!req || req.wait) continue;
    if (req.teamPreview) { b.choose(side.id, 'team 123'); continue; }
    if (req.forceSwitch) {
      const o = side.pokemon.map((p, i) => (!p.isActive && !p.fainted) ? i + 1 : 0).filter(Boolean);
      b.choose(side.id, req.forceSwitch.map(f => f ? `switch ${o.shift()}` : 'pass').join(', ')); continue;
    }
    b.choose(side.id, req.active.map(a => {
      const m = a.moves.map((x, j) => x.disabled ? 0 : j + 1).filter(Boolean);
      const mv = m.length ? m[b.prng.random(m.length)] : 1;
      return side.active.length > 1 ? `move ${mv} ${b.prng.random(2) + 1}` : `move ${mv}`;
    }).join(', '));
  }
}
// a leaf evaluation of the kind poke-engine uses: HP fractions plus status, both sides
function evaluate(b) {
  let s = 0;
  for (const side of b.sides) {
    const sign = side.n === 0 ? 1 : -1;
    for (const p of side.pokemon) s += sign * (p.hp / p.maxhp) * (p.status ? 0.8 : 1);
  }
  return 1 / (1 + Math.exp(-s));
}

const root = mk(); for (let i = 0; i < 6; i++) step(root);
// NOTE: deserializeBattle MUTATES the state object it is given, so a parsed
// snapshot cannot be reused. Keep the snapshot as a string and let fromJSON parse it.
const rootState = JSON.stringify(root.toJSON());
for (let i = 0; i < 300; i++) { const b = Battle.fromJSON(rootState); b.restart(() => {}); step(b); evaluate(b); }

function iterations(n) {
  const t = process.hrtime.bigint();
  let acc = 0;
  for (let i = 0; i < n; i++) {
    const b = Battle.fromJSON(rootState);   // descend: reconstruct the leaf's state
    b.restart(() => {});
    step(b);                                 // expand: one joint action
    acc += evaluate(b);                      // evaluate: static leaf, no rollout
  }
  return Number(process.hrtime.bigint() - t) / 1e6;
}
const per = Math.min(iterations(2000), iterations(2000)) / 2000;
console.log(`${gameType}: ${per.toFixed(3)} ms per iteration  ->  1000 iter ${(per * 1000 / 1000).toFixed(2)} s   5000 iter ${(per * 5000 / 1000).toFixed(2)} s`);
// memory cost of holding a tree of cloned battles
global.gc && global.gc();
const before = process.memoryUsage().heapUsed;
const keep = []; for (let i = 0; i < 2000; i++) { const b = Battle.fromJSON(rootState); b.restart(() => {}); keep.push(b); }
const per_node = (process.memoryUsage().heapUsed - before) / 2000 / 1024;
console.log(`   ~${per_node.toFixed(0)} KB per retained node  ->  5000 nodes ~${(per_node * 5000 / 1024).toFixed(0)} MB (keep[0] turn ${keep[0].turn})`);
