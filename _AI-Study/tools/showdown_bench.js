// Time Showdown's Battle object the way a search tree would use it:
// direct Battle construction, choose() per turn, and toJSON/fromJSON as the clone.
const { Battle } = require('/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown/dist/sim/battle');
const { Teams } = require('/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown/dist/sim/teams');

const teamA = Teams.import(`
Politoed @ Leftovers
Ability: Drizzle
EVs: 252 HP / 252 SpD / 4 Def
Calm Nature
- Scald
- Ice Beam
- Toxic
- Protect

Scizor @ Choice Band
Ability: Technician
EVs: 248 HP / 252 Atk / 8 SpD
Adamant Nature
- Bullet Punch
- U-turn
- Superpower
- Pursuit

Landorus-Therian @ Leftovers
Ability: Intimidate
EVs: 252 HP / 240 Def / 16 Spe
Impish Nature
- Earthquake
- Stone Edge
- U-turn
- Stealth Rock
`);
const teamB = Teams.import(`
Ninetales @ Leftovers
Ability: Drought
EVs: 252 HP / 252 SpD / 4 Spe
Calm Nature
- Flamethrower
- Will-O-Wisp
- Roar
- Protect

Venusaur @ Life Orb
Ability: Chlorophyll
EVs: 4 HP / 252 SpA / 252 Spe
Modest Nature
- Growth
- Giga Drain
- Hidden Power [Fire]
- Sleep Powder

Dugtrio @ Focus Sash
Ability: Arena Trap
EVs: 252 Atk / 4 Def / 252 Spe
Jolly Nature
- Earthquake
- Stone Edge
- Sucker Punch
- Reversal
`);

function newBattle(gameType) {
  const formatid = gameType === 'doubles' ? 'gen5doublescustomgame' : 'gen5customgame';
  const b = new Battle({ formatid, seed: [1, 2, 3, 4] });
  b.setPlayer('p1', { name: 'A', team: teamA });
  b.setPlayer('p2', { name: 'B', team: teamB });
  return b;
}

function randomChoice(side, prng) {
  const req = side.activeRequest;
  if (!req || req.wait) return null;
  if (req.teamPreview) return 'team 123';
  if (req.forceSwitch) {
    const opts = side.pokemon.map((p, i) => (!p.isActive && !p.fainted) ? i + 1 : 0).filter(Boolean);
    return req.forceSwitch.map(f => f ? `switch ${opts.shift()}` : 'pass').join(', ');
  }
  return req.active.map((a, i) => {
    const moves = a.moves.map((m, j) => (m.disabled ? 0 : j + 1)).filter(Boolean);
    const mv = moves.length ? moves[prng.random(moves.length)] : 1;
    return side.active.length > 1 ? `move ${mv} ${prng.random(2) + 1}` : `move ${mv}`;
  }).join(', ');
}

function playTurns(b, n) {
  let turns = 0;
  while (!b.ended && turns < n) {
    for (const side of b.sides) {
      const c = randomChoice(side, b.prng);
      if (c) b.choose(side.id, c);
    }
    turns++;
  }
  return turns;
}

for (const gameType of ['singles', 'doubles']) {
  // construction
  let t = process.hrtime.bigint();
  const N = 200;
  let b;
  for (let i = 0; i < N; i++) { b = newBattle(gameType); }
  const build = Number(process.hrtime.bigint() - t) / 1e6 / N;

  // turns
  t = process.hrtime.bigint();
  let turns = 0;
  for (let i = 0; i < N; i++) { const bb = newBattle(gameType); turns += playTurns(bb, 30); }
  const perTurn = Number(process.hrtime.bigint() - t) / 1e6 / turns;

  // clone via toJSON/fromJSON at a mid-battle position
  const mid = newBattle(gameType); playTurns(mid, 5);
  t = process.hrtime.bigint();
  let copy;
  for (let i = 0; i < N; i++) { copy = Battle.fromJSON(mid.toJSON()); }
  const clone = Number(process.hrtime.bigint() - t) / 1e6 / N;
  // does the clone keep playing?
  copy.restart(() => {});
  const contd = playTurns(copy, 5);

  console.log(`${gameType}: construct ${build.toFixed(2)} ms | per turn ${perTurn.toFixed(2)} ms (${turns} turns, incl. construct) | toJSON+fromJSON clone ${clone.toFixed(2)} ms | clone resumed ${contd} turns, ended=${copy.ended} turn=${copy.turn}`);
}

// mid-battle mutation from outside: set HP/status/boost directly on the live object
const b = newBattle('singles'); playTurns(b, 3);
const p = b.p2.active[0];
p.sethp(Math.floor(p.maxhp / 4)); p.setStatus('par'); p.boosts.spe = 2;
b.p1.addSideCondition('stealthrock', 'debug');
console.log(`after mutation: hp=${p.hp}/${p.maxhp} status=${p.status} spe boost=${p.boosts.spe} p1 rocks=${!!b.p1.sideConditions.stealthrock} weather=${b.field.weather}`);
playTurns(b, 3);
console.log(`mutated live battle kept running: turn=${b.turn} ended=${b.ended} p2 active hp=${p.hp}/${p.maxhp} status=${p.status}`);
