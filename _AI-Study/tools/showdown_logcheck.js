// Determinism harness: fixed seeds, fixed choice policy, hash every battle log.
const crypto = require('crypto');
const P = '/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown';
const { Battle } = require(P + '/dist/sim/battle');
const { Teams } = require(P + '/dist/sim/teams');
const T = require('./teams.js');

function play(gameType, seed) {
  const b = new Battle({ formatid: gameType === 'doubles' ? 'gen5doublescustomgame' : 'gen5customgame', seed });
  b.setPlayer('p1', { name: 'A', team: T.a });
  b.setPlayer('p2', { name: 'B', team: T.b });
  let turns = 0;
  while (!b.ended && turns < 40) {
    for (const side of b.sides) {
      const req = side.activeRequest;
      if (!req || req.wait) continue;
      if (req.teamPreview) { b.choose(side.id, 'team 123'); continue; }
      if (req.forceSwitch) {
        const opts = side.pokemon.map((p, i) => (!p.isActive && !p.fainted) ? i + 1 : 0).filter(Boolean);
        b.choose(side.id, req.forceSwitch.map(f => f ? `switch ${opts.shift()}` : 'pass').join(', '));
        continue;
      }
      b.choose(side.id, req.active.map(a => {
        const moves = a.moves.map((m, j) => (m.disabled ? 0 : j + 1)).filter(Boolean);
        const mv = moves.length ? moves[b.prng.random(moves.length)] : 1;
        return side.active.length > 1 ? `move ${mv} ${b.prng.random(2) + 1}` : `move ${mv}`;
      }).join(', '));
    }
    turns++;
  }
  return b.log.filter(l => !l.startsWith('|t:|')).join('\n');
}

const h = crypto.createHash('sha256');
let turnsTotal = 0;
for (const gameType of ['singles', 'doubles']) {
  for (let s = 0; s < 25; s++) {
    const log = play(gameType, [s, s + 1, s + 2, s + 3]);
    turnsTotal += log.split('\n').filter(l => l.startsWith('|turn|')).length;
    h.update(gameType + '|' + log);
  }
}
console.log(h.digest('hex'), 'turns', turnsTotal);
