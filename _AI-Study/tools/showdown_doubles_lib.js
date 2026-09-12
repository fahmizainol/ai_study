// Shared pieces of the Showdown doubles harnesses: the deterministic PRNG, the position
// snapshot shape, and the curated team pool. Required by showdown_doubles_corpus.js (the
// differential corpus) and showdown_doubles_server.js (the play harness) so the two cannot
// drift -- the snapshot is a contract with tools/pe_doubles_corpus.py, which parses it.
const P = '/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown';
const { Teams } = require(P + '/dist/sim/teams');

// Always-max PRNG: the damage roll lands on its maximum, randomChance(1,16) for a crit is
// false, secondaries never fire, and speed ties resolve identically every run. The
// consequence to respect is that randomChance(acc,100) is only true above 99, so every move
// in POOL must be 100% accurate with no secondary or it will silently miss.
function pinPrng(battle) {
  const max = (from, to) => {
    if (from === undefined) return 0.999999999;
    if (to === undefined) return Math.max(0, from - 1);
    return Math.max(from, to - 1);
  };
  battle.prng = { random: max, randomChance: (n, d) => max(d) < n, sample: a => a[a.length - 1],
                  shuffle: a => a, next: () => 0.999999999, clone() { return this; },
                  getSeed: () => [0, 0, 0, 0], seed: [0, 0, 0, 0], startingSeed: [0, 0, 0, 0] };
}

const body = (p) => p && ({
  species: p.species.name, ability: p.ability, item: p.item || '',
  types: p.types, weightkg: p.species.weightkg,
  hp: p.hp, maxhp: p.maxhp, status: p.status || 'none', fainted: !!p.fainted,
  stats: { ...p.storedStats }, boosts: { ...p.boosts },
  volatiles: Object.keys(p.volatiles || {}),
  // Showdown enforces a Choice lock through lastMove rather than a field on the volatile, and
  // poke-engine represents the same thing as the Pokemon's last_used_move -- so the move id is
  // what the translator needs to turn `choicelock` into state instead of a skipped turn.
  lastMove: p.lastMove ? p.lastMove.id : null,
  moves: p.moveSlots.map(m => ({ id: m.id, pp: m.pp })),
});

// One position, in the shape tools/pe_doubles_corpus.py rebuilds a poke-engine State from.
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

// species, ability, moves. Every move is 100% accurate, inflicts no status and has no
// secondary (see pinPrng). The pool exercises doubles specifically: spread moves that do and
// do not hit the ally, both redirection moves, both area guards, Ally Switch, Helping Hand,
// and abilities that redirect, absorb or reduce.
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

const teamFrom = (picked) => Teams.import(picked.map(([sp, ab, mv]) =>
  `${sp}\nAbility: ${ab}\nLevel: 100\nEVs: 0 HP\nSerious Nature\n` + mv.map(m => `- ${m}`).join('\n')
).join('\n\n'));

module.exports = { P, pinPrng, body, snap, POOL, teamFrom };
