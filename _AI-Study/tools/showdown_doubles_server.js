// Showdown as the referee for a doubles play harness: one battle at a time, driven over a
// JSON-line protocol so the policy can live in Python beside the poke-engine bindings.
//
//   node showdown_doubles_server.js        # reads commands on stdin, one JSON object a line
//
// Commands and replies (all single-line JSON):
//   {"cmd":"new","teams":[[i,...],[i,...]]}   -> {"ok":true,"position":{...},"requests":{...}}
//       team members are indices into the shared POOL.
//   {"cmd":"choose","p1":"move 1 1, move 2","p2":"..."} 
//                                            -> {"ok":true,"position":{...},"ended":bool,
//                                                "winner":"p1"|"p2"|null,"log":[...],"requests":{...}}
//   {"cmd":"quit"}                           -> exits
//
// `requests` carries, per side, what each active slot may legally do this turn (move ids with
// their Showdown target category, and the switchable bench), so the policy does not have to
// re-derive legality. A side that has nothing to choose (wait) is absent from `requests`.
//
// Determinism comes from the shared always-max PRNG, so a given sequence of choices always
// produces the same battle.
const { P, pinPrng, snap, POOL, teamFrom } = require('./showdown_doubles_lib.js');
const { Battle } = require(P + '/dist/sim/battle');
const { Dex } = require(P + '/dist/sim/dex');
const readline = require('readline');

let battle = null;

function requests() {
  const out = {};
  for (const side of battle.sides) {
    const req = side.activeRequest;
    if (!req || req.wait) continue;
    if (req.teamPreview) { out[side.id] = { teamPreview: true }; continue; }
    const bench = side.pokemon
      .map((p, i) => (!p.isActive && !p.fainted) ? { slot: i + 1, species: p.species.name } : null)
      .filter(Boolean);
    if (req.forceSwitch) {
      out[side.id] = { forceSwitch: req.forceSwitch, bench };
      continue;
    }
    out[side.id] = {
      bench,
      active: req.active.map((a, slot) => ({
        slot,
        species: side.active[slot] ? side.active[slot].species.name : null,
        fainted: side.active[slot] ? !!side.active[slot].fainted : true,
        trapped: !!a.trapped,
        // basePower/category come from the dex so a baseline policy can be written without
        // a damage model of its own; `target` is Showdown's own targeting category, which is
        // what decides whether a choice needs an explicit target number.
        moves: a.moves.map((m, j) => {
          const d = Dex.forGen(5).moves.get(m.id);
          return { n: j + 1, id: m.id, target: m.target, disabled: !!m.disabled,
                   basePower: d.basePower || 0, category: d.category };
        }),
      })),
    };
  }
  return out;
}

const reply = (o) => process.stdout.write(JSON.stringify(o) + '\n');

readline.createInterface({ input: process.stdin }).on('line', (line) => {
  line = line.trim();
  if (!line) return;
  let cmd;
  try { cmd = JSON.parse(line); } catch (e) { return reply({ ok: false, error: 'bad json: ' + e.message }); }
  try {
    if (cmd.cmd === 'quit') process.exit(0);
    if (cmd.cmd === 'new') {
      battle = new Battle({ formatid: 'gen5doublescustomgame', seed: [1, 2, 3, 4] });
      pinPrng(battle);
      battle.setPlayer('p1', { name: 'A', team: teamFrom(cmd.teams[0].map(i => POOL[i])) });
      battle.setPlayer('p2', { name: 'B', team: teamFrom(cmd.teams[1].map(i => POOL[i])) });
      for (const s of battle.sides) {
        if (s.activeRequest && s.activeRequest.teamPreview) battle.choose(s.id, 'team 1234');
      }
      return reply({ ok: true, position: snap(battle), requests: requests() });
    }
    if (cmd.cmd === 'choose') {
      const at = battle.log.length;
      for (const side of battle.sides) {
        const c = cmd[side.id];
        if (c) {
          if (!battle.choose(side.id, c)) {
            // Showdown records why in side.choice.error; without it a rejection is
            // undiagnosable from the driver's side.
            const why = (side.choice && side.choice.error) || 'no reason given';
            return reply({ ok: false, error: `rejected ${side.id} choice ${JSON.stringify(c)}: ${why}`,
                           requests: requests() });
          }
        }
      }
      return reply({
        ok: true, position: snap(battle), requests: requests(),
        // battle.winner is the player NAME; report the side id, which is what a driver keys on.
        ended: !!battle.ended,
        winner: battle.winner ? (battle.sides.find(s => s.name === battle.winner) || {}).id || null : null,
        log: battle.log.slice(at).filter(l => l.startsWith('|move|') || l.startsWith('|switch|')
                                          || l.startsWith('|faint|') || l.startsWith('|swap|')),
      });
    }
    reply({ ok: false, error: 'unknown cmd ' + cmd.cmd });
  } catch (e) {
    reply({ ok: false, error: `${e.message}` });
  }
});
