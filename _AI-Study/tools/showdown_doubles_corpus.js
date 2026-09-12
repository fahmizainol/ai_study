// The corpus stage of the doubles differential: random doubles battles played on Showdown as
// the reference, dumped per turn for tools/pe_doubles_corpus.py to replay on poke-engine.
//
//   node showdown_doubles_corpus.js [battles] [seed] > ../generated/showdown_doubles_corpus.ndjson
//
// Random CHOICES give breadth over positions and actions. MOVESETS are curated, not random,
// and that is what keeps the comparison sound: with Showdown's PRNG pinned to always-max,
// randomChance(acc,100) is only true above 99, so a sub-100% move would silently miss while
// poke-engine branched on its accuracy. Every move below is 100% accurate, inflicts no
// status and has no secondary effect, so both engines have exactly one outcome per turn and
// any difference is mechanical. The pool is chosen to exercise doubles specifically: spread
// moves that do and do not hit the ally, both redirection moves, both area guards, Ally
// Switch, Helping Hand, and abilities that redirect, absorb or reduce.
const P = '/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown';
const { Battle } = require(P + '/dist/sim/battle');
const { Teams } = require(P + '/dist/sim/teams');

const BATTLES = parseInt(process.argv[2] || '40', 10);
const SEED = parseInt(process.argv[3] || '7', 10);

// species, ability, moves. Abilities are the doubles-relevant ones; the move lists mix a
// spread move, a single-target move and a support move so most choices are interesting.
const POOL = [
  ['Snorlax',    'Immunity',      ['Tackle', 'Earthquake', 'Protect', 'Swords Dance']],
  ['Machamp',    'No Guard',      ['Mach Punch', 'Earthquake', 'Protect', 'Swords Dance']],
  ['Blastoise',  'Torrent',       ['Surf', 'Aqua Jet', 'Protect', 'Tackle']],
  ['Golem',      'Sturdy',        ['Earthquake', 'Tackle', 'Protect', 'Swords Dance']],
  ['Raichu',     'Static',        ['Shock Wave', 'Swift', 'Protect', 'Tackle']],
  ['Seaking',    'Lightning Rod', ['Aqua Jet', 'Tackle', 'Protect', 'Swords Dance']],
  ['Gastrodon',  'Storm Drain',   ['Earthquake', 'Tackle', 'Protect', 'Calm Mind']],
  ['Musharna',   'Telepathy',     ['Calm Mind', 'Tackle', 'Protect', 'Swift']],
  ['Clefable',   'Friend Guard',  ['Follow Me', 'Helping Hand', 'Tackle', 'Protect']],
  ['Vileplume',  'Chlorophyll',   ['Rage Powder', 'Tackle', 'Protect', 'Vine Whip']],
  ['Mienshao',   'Inner Focus',   ['Wide Guard', 'Quick Guard', 'Mach Punch', 'Tackle']],
  ['Gothitelle', 'Frisk',         ['Ally Switch', 'Tackle', 'Protect', 'Calm Mind']],
  ['Gengar',     'Levitate',      ['Shock Wave', 'Tackle', 'Protect', 'Calm Mind']],
  ['Gyarados',   'Intimidate',    ['Aqua Jet', 'Tackle', 'Protect', 'Swords Dance']],
];

// A tiny deterministic RNG for team and choice selection, so a seed reproduces a corpus.
let rngState = SEED >>> 0;
const rnd = (n) => { rngState = (rngState * 1103515245 + 12345) >>> 0; return (rngState >>> 8) % n; };

const teamOf = () => {
  const picked = [], seen = new Set();
  while (picked.length < 4) { const i = rnd(POOL.length); if (!seen.has(i)) { seen.add(i); picked.push(POOL[i]); } }
  return Teams.import(picked.map(([sp, ab, mv]) =>
    `${sp}\nAbility: ${ab}\nLevel: 100\nEVs: 0 HP\nSerious Nature\n` + mv.map(m => `- ${m}`).join('\n')
  ).join('\n\n'));
};

// Always-max PRNG. See the note above for why every move must be 100% accurate.
function pinPrng(battle) {
  const max = (from, to) => {
    if (from === undefined) return 0.999999999;
    if (to === undefined) return Math.max(0, from - 1);
    return Math.max(from, to - 1);
  };
  battle.prng = { random: max, randomChance: (n, d) => max(d) < n, sample: a => a[a.length - 1],
                  shuffle: a => a, next: () => 0.999999999, clone() { return this; },
                  getSeed: () => [0,0,0,0], seed: [0,0,0,0], startingSeed: [0,0,0,0] };
}

const body = (p) => p && ({
  species: p.species.name, ability: p.ability, item: p.item || '',
  types: p.types, weightkg: p.species.weightkg,
  hp: p.hp, maxhp: p.maxhp, status: p.status || 'none', fainted: !!p.fainted,
  stats: { ...p.storedStats }, boosts: { ...p.boosts },
  volatiles: Object.keys(p.volatiles || {}),
  moves: p.moveSlots.map(m => ({ id: m.id, pp: m.pp })),
});

const snap = (b) => ({
  weather: b.field.weather || 'none', terrain: b.field.terrain || 'none',
  pseudo: Object.keys(b.field.pseudoWeather || {}),
  sides: b.sides.map(s => ({
    side: s.id,
    conditions: Object.fromEntries(Object.entries(s.sideConditions).map(([k, v]) => [k, v.layers || 1])),
    active: s.active.map(body),
    bench: s.pokemon.filter(p => !p.isActive).map(body),
  })),
});

// One side's random legal choice, returned both as Showdown syntax and as the per-slot parts
// the python side needs to build a poke-engine combined action.
function pick(b, side) {
  const req = side.activeRequest;
  if (!req || req.wait) return null;
  if (req.teamPreview) return { showdown: 'team 1234', parts: null };
  const benchIdx = side.pokemon.map((p, i) => (!p.isActive && !p.fainted) ? i + 1 : 0).filter(Boolean);
  if (req.forceSwitch) {
    const o = benchIdx.slice();
    const parts = req.forceSwitch.map(f => {
      if (!f) return { kind: 'pass' };
      const i = o.shift();
      return i ? { kind: 'switch', species: side.pokemon[i - 1].species.name } : { kind: 'pass' };
    });
    const o2 = benchIdx.slice();
    return { showdown: req.forceSwitch.map(f => f ? `switch ${o2.shift()}` : 'pass').join(', '), parts, forced: true };
  }
  const parts = [], sd = [];
  const used = new Set();
  req.active.forEach((a, slot) => {
    if (!side.active[slot] || side.active[slot].fainted) { parts.push({ kind: 'pass' }); sd.push('pass'); return; }
    const legal = a.moves.map((m, j) => m.disabled ? null : j + 1).filter(Boolean);
    // a switch is offered as one more option when a live body is on the bench
    const canSwitch = !a.trapped && benchIdx.some(i => !used.has(i));
    if (canSwitch && rnd(5) === 0) {
      const i = benchIdx.find(x => !used.has(x)); used.add(i);
      parts.push({ kind: 'switch', species: side.pokemon[i - 1].species.name });
      sd.push(`switch ${i}`); return;
    }
    const mv = legal[rnd(legal.length)] || 1;
    const move = a.moves[mv - 1];
    const target = move.target;
    // normal/any need an explicit foe; adjacentAlly needs an ally; the rest are self-resolving
    if (target === 'normal' || target === 'any') {
      const t = rnd(2) + 1;                       // Showdown foe slots are 1 and 2
      sd.push(`move ${mv} ${t}`); parts.push({ kind: 'move', id: move.id, target: t - 1 });
    } else if (target === 'adjacentAlly' || target === 'adjacentAllyOrSelf') {
      sd.push(`move ${mv} -${slot === 0 ? 2 : 1}`); parts.push({ kind: 'move', id: move.id, target: null });
    } else {
      sd.push(`move ${mv}`); parts.push({ kind: 'move', id: move.id, target: null });
    }
  });
  return { showdown: sd.join(', '), parts };
}

let rows = 0;
for (let n = 0; n < BATTLES; n++) {
  rngState = (SEED + n * 7919) >>> 0;
  const b = new Battle({ formatid: 'gen5doublescustomgame', seed: [1, 2, 3, 4] });
  pinPrng(b);
  b.setPlayer('p1', { name: 'A', team: teamOf() });
  b.setPlayer('p2', { name: 'B', team: teamOf() });
  for (const s of b.sides) if (s.activeRequest && s.activeRequest.teamPreview) b.choose(s.id, 'team 1234');
  for (let turn = 0; turn < 14 && !b.ended; turn++) {
    const choices = b.sides.map(s => pick(b, s));
    if (choices.some(c => c && c.forced)) {             // replacement turns are not joint actions
      for (const [i, s] of b.sides.entries()) if (choices[i]) b.choose(s.id, choices[i].showdown);
      continue;
    }
    if (!choices[0] || !choices[1]) break;
    const before = snap(b);
    const logAt = b.log.length;
    for (const [i, s] of b.sides.entries()) b.choose(s.id, choices[i].showdown);
    const after = snap(b);
    process.stdout.write(JSON.stringify({
      battle: n, turn,
      choices: { p1: choices[0].showdown, p2: choices[1].showdown },
      parts: { s1: choices[0].parts, s2: choices[1].parts },
      before, after,
      log: b.log.slice(logAt).filter(l => l.startsWith('|move|') || l.startsWith('|switch|') || l.startsWith('|swap|')),
    }) + '\n');
    rows++;
  }
}
process.stderr.write(`${BATTLES} battles, ${rows} joint-action turns\n`);
