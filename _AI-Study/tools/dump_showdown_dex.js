// Dump the per-generation dex facts the monotype type-synergy analysis needs, from
// the pokemon-showdown checkout in ../.. -- species typing/abilities, the type chart,
// and the move fields used to tell a pivot from an attack.
//
// Realidea's PBS (tools/realidea_data.py) cannot answer this: it is one gen-6-era
// 16-type dex with a fangame's own edits, and the monotype corpus is gens 6-9 with
// Fairy, gen 7-9 species and gen 9 abilities. Showdown's Dex.forGen(n) is the only
// source here that gets each generation's own chart and legality.
//
//   node tools/dump_showdown_dex.js > generated/showdown_dex.json
const P = '/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown';
const { Dex } = require(P + '/dist/sim/dex');

const out = {};
for (const gen of [5, 6, 7, 8, 9]) {
  const dex = Dex.forGen(gen);
  const species = {};
  for (const s of dex.species.all()) {
    if (!s.exists) continue;
    species[s.id] = {
      name: s.name,
      base: dex.species.get(s.baseSpecies).id,
      types: s.types,
      abilities: Object.values(s.abilities),
      bst: Object.values(s.baseStats).reduce((a, b) => a + b, 0),
      nonstandard: s.isNonstandard || null,
    };
  }
  const chart = {};
  for (const t of dex.types.all()) chart[t.name] = t.damageTaken;   // 0 normal 1 weak 2 resist 3 immune
  const items = {};
  for (const it of dex.items.all()) {
    if (!it.exists) continue;
    // `megaStone` is a MAP from base species to the forme the stone produces --
    // {"Venusaur": "Venusaur-Mega"} -- not a forme name. Reading it as a string yields
    // undefined for every stone while `!!it.megaStone` stays true, so the mistake is
    // invisible until a set listed as "Venusaur @ Venusaurite" fails to become Mega.
    const megaMap = {};
    if (it.megaStone) {
      const pairs = typeof it.megaStone === 'string'
        ? [[it.megaEvolves, it.megaStone]] : Object.entries(it.megaStone);
      for (const [from, to] of pairs) {
        if (!from || !to) continue;
        megaMap[dex.species.get(from).id] = dex.species.get(to).id;
      }
    }
    items[it.id] = { name: it.name, nonstandard: it.isNonstandard || null,
                     mega: !!it.megaStone, z: !!it.zMove, gen: it.gen, mega_map: megaMap };
  }
  const moves = {};
  for (const m of dex.moves.all()) {
    if (!m.exists) continue;
    moves[m.id] = { name: m.name, type: m.type, category: m.category, bp: m.basePower,
                    target: m.target, self_switch: !!m.selfSwitch, nonstandard: m.isNonstandard || null,
                    heal: !!m.heal || !!(m.flags||{}).heal };
  }
  out['gen' + gen] = { species, chart, moves, items };
}
process.stdout.write(JSON.stringify(out));
