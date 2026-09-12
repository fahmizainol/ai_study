// Showdown as the referee for a doubles play harness: one battle at a time, driven over a
// JSON-line protocol so the policy can live in Python beside the poke-engine bindings.
//
//   node showdown_doubles_server.js        # reads commands on stdin, one JSON object a line
//
// Commands and replies (all single-line JSON):
//   {"cmd":"new","teams":[[i,...],[i,...]]}   -> {"ok":true,"position":{...},"requests":{...}}
//       team members are indices into the shared POOL.
//   {"cmd":"new","p1":"<Showdown import text>","p2":"...","format":"gen6doublescustomgame",
//    "seed":[1,2,3,4],"pinPrng":false}
//       real teams instead of the pool. `pinPrng` defaults to TRUE for the pool path (the
//       differential corpus needs one outcome per turn) and should be FALSE for a play
//       measurement, where real accuracy, crits and secondaries are the point and Showdown's
//       own seeded PRNG keeps a run reproducible.
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

const LOGGED = ['|move|', '|switch|', '|faint|', '|swap|', '|-status|', '|-curestatus|',
  '|-fail|', '|-immune|', '|-miss|', '|-crit|', '|-boost|', '|-unboost|', '|-activate|',
  '|cant|', '|-start|', '|-end|', '|-enditem|', '|-sidestart|', '|-sideend|'];
const { Dex } = require(P + '/dist/sim/dex');
const { Teams } = require(P + '/dist/sim/teams');
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
        // Shadow Tag / Arena Trap is hidden information, so Showdown reports maybeTrapped and
        // only rejects the switch when it is attempted. A policy must treat both as trapped.
        trapped: !!a.trapped, maybeTrapped: !!a.maybeTrapped,
        // basePower/category come from the dex so a baseline policy can be written without
        // a damage model of its own; `target` is Showdown's own targeting category, which is
        // what decides whether a choice needs an explicit target number.
        moves: a.moves.map((m, j) => {
          // A locked move (Choice item, Outrage, a charging Solar Beam, a Hyper Beam
          // recharge) arrives as a single-entry list carrying only `move` and `id`. The
          // MISSING target means "no target may be given" -- it was chosen when the move
          // started -- so it must stay null rather than be looked up: sending one gets
          // "You can't choose a target for Solar Beam". basePower and category are still
          // worth filling from the dex, since a policy wants them.
          const d = battle.dex.moves.get(m.id);
          return { n: j + 1, id: m.id, target: m.target || null, locked: !m.target,
                   disabled: !!m.disabled, basePower: d.basePower || 0, category: d.category };
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
      const formatid = cmd.format || 'gen5doublescustomgame';
      battle = new Battle({ formatid, seed: cmd.seed || [1, 2, 3, 4] });
      const pin = cmd.pinPrng !== undefined ? cmd.pinPrng : !!cmd.teams;
      if (pin) pinPrng(battle);
      const team = (side) => cmd.teams
        ? teamFrom(cmd.teams[side].map(i => POOL[i]))
        : Teams.import(side === 0 ? cmd.p1 : cmd.p2);
      battle.setPlayer('p1', { name: 'A', team: team(0) });
      battle.setPlayer('p2', { name: 'B', team: team(1) });
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
        // The action lines alone cannot say whether an action DID anything: a Thunder Wave
        // that failed on an already-paralyzed target renders identically to one that landed.
        // The outcome lines are what make a transcript diagnostic rather than merely plausible.
        log: battle.log.slice(at).filter(l => LOGGED.some(p => l.startsWith(p))),
      });
    }
    reply({ ok: false, error: 'unknown cmd ' + cmd.cmd });
  } catch (e) {
    reply({ ok: false, error: `${e.message}` });
  }
});
