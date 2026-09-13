// Stage 0 of the doubles differential test: hand-authored doubles positions, played on
// Showdown as the reference, dumped for tools/pe_doubles_diff.py to replay on poke-engine.
//
//   node showdown_doubles_cases.js > ../generated/showdown_doubles_cases.json
//
// Determinism: the battle's PRNG is replaced by one that always returns the TOP of every
// range. One rule, and it pins everything stage 0 needs -- damage lands on its max roll
// (random(85,101) -> 100, the same quantity poke-engine's calculate_damage returns first),
// crits never happen (randomChance(1,16) -> random(16)=15 < 1 is false), secondaries never
// fire, and speed ties resolve the same way every run. The one consequence to respect:
// randomChance(acc,100) is only true when acc > 99, so every case move must be 100%
// accurate or it will silently miss. That is a feature -- a miss shows up as zero damage.
const P = '/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown';
const { Battle } = require(P + '/dist/sim/battle');
const { Teams } = require(P + '/dist/sim/teams');

const set = (species, ability, moves, opts = {}) =>
  `${species} @ ${opts.item || ''}\nAbility: ${ability}\nLevel: 100\nEVs: 0 HP\n` +
  `${opts.nature || 'Serious'} Nature\n` + moves.map(m => `- ${m}`).join('\n');

// Every move here is 100% accurate with no secondary effect, so both engines have exactly
// one outcome to produce. Fillers keep each side at four bodies so switches are legal.
const FILL = set('Ditto', 'Limber', ['Transform']);

const CASES = [
  { name: 'follow_me_redirects',
    why: 'slot0 uses Follow Me; the foe aims Tackle at slot1 and should hit slot0 instead',
    p1: [set('Clefable', 'Unaware', ['Follow Me', 'Tackle']), set('Snorlax', 'Immunity', ['Tackle']), FILL, FILL],
    p2: [set('Machamp', 'No Guard', ['Tackle']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1, move 1 1', c2: 'move 1 2, move 1 2',
    pe1: 'followme;tackle,0', pe2: 'tackle,1;tackle,1' },

  { name: 'rage_powder_redirects',
    why: 'same as Follow Me but the grass-immunity rule does not apply to a Fighting attacker',
    p1: [set('Vileplume', 'Chlorophyll', ['Rage Powder', 'Tackle']), set('Snorlax', 'Immunity', ['Tackle']), FILL, FILL],
    p2: [set('Machamp', 'No Guard', ['Tackle']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1, move 1 1', c2: 'move 1 2, move 1 2',
    pe1: 'ragepowder;tackle,0', pe2: 'tackle,1;tackle,1' },

  { name: 'lightningrod_redirects_and_boosts',
    why: 'slot1 has Lightning Rod; an Electric move aimed at slot0 is redirected, nullified, +1 SpA',
    p1: [set('Snorlax', 'Immunity', ['Tackle']), set('Seaking', 'Lightning Rod', ['Tackle']), FILL, FILL],
    p2: [set('Raichu', 'Static', ['Shock Wave']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1 1, move 1 1', c2: 'move 1 1, move 1 1',
    pe1: 'tackle,0;tackle,0', pe2: 'shockwave,0;tackle,0' },

  // Added to adjudicate tests/test_doubles.rs:1402, which asserts that a Surf into a side
  // holding Storm Drain does NO damage anywhere on that side -- the whole-move-redirect
  // model. Storm Drain should absorb for its HOLDER only and leave the partner hit. Rather
  // than decide that from reasoning, ask Showdown: slot1 holds Storm Drain, slot0 is a
  // plain body, and nothing else touches slot0, so slot0's HP answers exactly one question.
  // Swords Dance keeps p1's second body busy without adding damage anywhere.
  { name: 'storm_drain_does_not_shield_partner',
    why: 'Surf into a Storm Drain holder: the holder absorbs (+1 SpA, no damage) but its partner is still hit',
    p1: [set('Blastoise', 'Torrent', ['Surf']), set('Machamp', 'No Guard', ['Swords Dance']), FILL, FILL],
    p2: [set('Snorlax', 'Immunity', ['Tackle']), set('Gastrodon', 'Storm Drain', ['Tackle']), FILL, FILL],
    c1: 'move 1, move 1', c2: 'move 1 1, move 1 1',
    pe1: 'surf;swordsdance', pe2: 'tackle,0;tackle,0' },

  // Defect 20: get_instructions_from_status_effects resolves the target slot correctly and
  // then writes through `get_active()` (slot 0) anyway, so a status aimed at slot 1 lands on
  // slot 0. Aim Thunder Wave at p2 SLOT 1 with two distinguishable, freely paralyzable bodies
  // so the answer is a species, not a slot number. Thunder Wave is 100% accurate in gen 5,
  // which the pinned always-max PRNG requires. Swords Dance keeps p1's other body busy
  // without touching anyone's HP or status.
  { name: 'thunder_wave_lands_on_the_slot_aimed_at',
    why: 'Thunder Wave aimed at slot 1 must paralyze slot 1, not slot 0',
    p1: [set('Snorlax', 'Immunity', ['Thunder Wave']), set('Machamp', 'No Guard', ['Swords Dance']), FILL, FILL],
    p2: [set('Blastoise', 'Torrent', ['Tackle']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1 2, move 1', c2: 'move 1 1, move 1 1',
    pe1: 'thunderwave,1;swordsdance', pe2: 'tackle,0;tackle,0' },

  { name: 'spread_surf_reduction',
    why: 'Surf hits all adjacent; every hit takes the 0.75x spread multiplier',
    p1: [set('Snorlax', 'Immunity', ['Tackle']), set('Machamp', 'No Guard', ['Tackle']), FILL, FILL],
    p2: [set('Blastoise', 'Torrent', ['Surf']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1 1, move 1 1', c2: 'move 1, move 1 1',
    pe1: 'tackle,0;tackle,0', pe2: 'surf;tackle,0' },

  { name: 'earthquake_hits_ally',
    why: 'Earthquake is AllAdjacent, so it hits the attacker’s own partner too',
    p1: [set('Snorlax', 'Immunity', ['Tackle']), set('Machamp', 'No Guard', ['Tackle']), FILL, FILL],
    p2: [set('Golem', 'Sturdy', ['Earthquake']), set('Machoke', 'Guts', ['Tackle']), FILL, FILL],
    c1: 'move 1 1, move 1 1', c2: 'move 1, move 1 1',
    pe1: 'tackle,0;tackle,0', pe2: 'earthquake;tackle,0' },

  { name: 'telepathy_avoids_ally_spread',
    why: 'the partner has Telepathy, so the ally’s Earthquake does not touch it',
    p1: [set('Snorlax', 'Immunity', ['Tackle']), set('Machamp', 'No Guard', ['Tackle']), FILL, FILL],
    p2: [set('Golem', 'Sturdy', ['Earthquake']), set('Musharna', 'Telepathy', ['Tackle']), FILL, FILL],
    c1: 'move 1 1, move 1 1', c2: 'move 1, move 1 1',
    pe1: 'tackle,0;tackle,0', pe2: 'earthquake;tackle,0' },

  { name: 'wide_guard_blocks_spread',
    why: 'slot0 Wide Guards; the foe’s Surf should hit neither of our bodies',
    p1: [set('Mienshao', 'Inner Focus', ['Wide Guard', 'Tackle']), set('Snorlax', 'Immunity', ['Tackle']), FILL, FILL],
    p2: [set('Blastoise', 'Torrent', ['Surf']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1, move 1 1', c2: 'move 1, move 1 1',
    pe1: 'wideguard;tackle,0', pe2: 'surf;tackle,0' },

  // Added 2026-09-13 for defect 5. Wide Guard is a SIDE condition, and Showdown's
  // condition.onTryHit has no check on where the move came from -- so in principle a side's
  // own Wide Guard should also stop its partner's Earthquake. Nothing in stage 0 tested
  // that, because the old poke-engine code only ever consulted get_other_side(), so the
  // path was invisible. This case is built to be decisive: p2 aims both Tackles at p1
  // SLOT 1, never at the Wide Guarder, so slot 0's HP after the turn answers exactly one
  // question. Full HP => own-side protection is real; damaged => Wide Guard only stops the
  // opposing side's spread moves and the per-position keying must be narrowed.
  { name: 'wide_guard_blocks_own_ally_spread',
    why: 'slot0 Wide Guards and slot1 uses Earthquake; does our own guard spare slot0 from our own spread move?',
    p1: [set('Mienshao', 'Inner Focus', ['Wide Guard', 'Tackle']), set('Golem', 'Sturdy', ['Earthquake']), FILL, FILL],
    p2: [set('Snorlax', 'Immunity', ['Tackle']), set('Machamp', 'No Guard', ['Tackle']), FILL, FILL],
    c1: 'move 1, move 1', c2: 'move 1 2, move 1 2',
    pe1: 'wideguard;earthquake', pe2: 'tackle,1;tackle,1' },

  { name: 'quick_guard_blocks_priority',
    why: 'slot0 Quick Guards; a priority move should be blocked and a normal one should not',
    p1: [set('Mienshao', 'Inner Focus', ['Quick Guard', 'Tackle']), set('Snorlax', 'Immunity', ['Tackle']), FILL, FILL],
    p2: [set('Hitmonchan', 'Keen Eye', ['Mach Punch']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1, move 1 1', c2: 'move 1 2, move 1 2',
    pe1: 'quickguard;tackle,0', pe2: 'machpunch,1;tackle,1' },

  { name: 'helping_hand_boosts_ally',
    why: 'slot1 Helping Hands, so slot0’s Tackle should do 1.5x',
    p1: [set('Snorlax', 'Immunity', ['Tackle']), set('Clefable', 'Unaware', ['Helping Hand', 'Tackle']), FILL, FILL],
    p2: [set('Gengar', 'Levitate', ['Tackle']), set('Machamp', 'No Guard', ['Tackle']), FILL, FILL],
    c1: 'move 1 1, move 1 -1', c2: 'move 1 1, move 1 1',
    pe1: 'tackle,0;helpinghand', pe2: 'tackle,0;tackle,0' },

  { name: 'friend_guard_reduces_ally_damage',
    why: 'the partner has Friend Guard, so our slot0 takes 0.75x from the foe',
    p1: [set('Snorlax', 'Immunity', ['Tackle']), set('Clefable', 'Friend Guard', ['Tackle']), FILL, FILL],
    p2: [set('Machamp', 'No Guard', ['Tackle']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1 1, move 1 1', c2: 'move 1 1, move 1 1',
    pe1: 'tackle,0;tackle,0', pe2: 'tackle,0;tackle,0' },

  { name: 'ally_switch_swaps_slots',
    why: 'slot0 Ally Switches, so the foe’s attack aimed at slot0 lands on the body that moved there',
    p1: [set('Gothitelle', 'Frisk', ['Ally Switch', 'Tackle']), set('Snorlax', 'Immunity', ['Tackle']), FILL, FILL],
    p2: [set('Machamp', 'No Guard', ['Tackle']), set('Gengar', 'Levitate', ['Tackle']), FILL, FILL],
    c1: 'move 1, move 1 1', c2: 'move 1 1, move 1 1',
    pe1: 'allyswitch;tackle,0', pe2: 'tackle,0;tackle,0' },

  { name: 'intimidate_drops_both_foes',
    why: 'switching an Intimidate body in should drop the Attack of both opposing actives',
    p1: [set('Snorlax', 'Immunity', ['Tackle']), set('Machamp', 'No Guard', ['Tackle']), set('Gyarados', 'Intimidate', ['Tackle']), FILL],
    p2: [set('Gengar', 'Levitate', ['Tackle']), set('Machoke', 'Guts', ['Tackle']), FILL, FILL],
    c1: 'switch 3, move 1 1', c2: 'move 1 1, move 1 1',
    pe1: 'gyarados;tackle,0', pe2: 'tackle,0;tackle,0' },
];

// Always-max PRNG: see the determinism note at the top.
function pinPrng(battle) {
  const max = (from, to) => {
    if (from === undefined) return 0.999999999;      // random() -> real in [0,1)
    if (to === undefined) return Math.max(0, from - 1);
    return Math.max(from, to - 1);
  };
  battle.prng = { random: max, randomChance: (n, d) => max(d) < n, sample: a => a[a.length - 1],
                  shuffle: a => a, next: () => 0.999999999, get startingSeed() { return [0,0,0,0]; },
                  clone() { return this; }, getSeed: () => [0,0,0,0], seed: [0,0,0,0] };
}

const snap = (battle) => battle.sides.map(side => ({
  side: side.id,
  active: side.active.map(p => p && ({
    species: p.species.name, ability: p.ability, item: p.item || '',
    types: p.types, weightkg: p.species.weightkg,
    hp: p.hp, maxhp: p.maxhp, status: p.status || 'none',
    stats: { ...p.storedStats }, boosts: { ...p.boosts },
    moves: p.moveSlots.map(m => ({ id: m.id, pp: m.pp })),
  })),
  bench: side.pokemon.filter(p => !p.isActive).map(p => ({
    species: p.species.name, ability: p.ability, item: p.item || '',
    types: p.types, weightkg: p.species.weightkg,
    hp: p.hp, maxhp: p.maxhp, status: p.status || 'none',
    stats: { ...p.storedStats }, boosts: { ...p.boosts },
    moves: p.moveSlots.map(m => ({ id: m.id, pp: m.pp })),
  })),
}));

const out = [];
for (const c of CASES) {
  const b = new Battle({ formatid: 'gen5doublescustomgame', seed: [1, 2, 3, 4] });
  pinPrng(b);
  b.setPlayer('p1', { name: 'A', team: Teams.import(c.p1.join('\n\n')) });
  b.setPlayer('p2', { name: 'B', team: Teams.import(c.p2.join('\n\n')) });
  // gen5doublescustomgame runs team preview, so the actives are not on the field until
  // both sides pick an order. `team 1234` sends bodies 1 and 2 out as slots 0 and 1.
  for (const side of b.sides) if (side.activeRequest && side.activeRequest.teamPreview) b.choose(side.id, 'team 1234');
  const before = snap(b);
  b.choose('p1', c.c1);
  b.choose('p2', c.c2);
  const after = snap(b);
  out.push({ name: c.name, why: c.why, choices: { p1: c.c1, p2: c.c2 },
             pe: { s1: c.pe1, s2: c.pe2 }, before, after,
             log: b.log.filter(l => !l.startsWith('|t:|')) });
}
process.stdout.write(JSON.stringify(out, null, 1));
