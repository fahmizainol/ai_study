// Validate every exported team against gen9nationaldexrnb exactly as the server would.
// The format has no Obtainable rule (Run & Bun movesets are not Showdown-legal), so this
// catches only what would make the server refuse a challenge outright.
//
//   node tools/rnb/validate_teams.js
const fs = require('fs');
const path = require('path');
const STUDY = path.resolve(__dirname, '..', '..');
const WORK = process.env.RNB_WORK || path.join(STUDY, 'generated', 'rnb_work');
const PS = path.join(WORK, 'showdown', 'node_modules', 'pokemon-showdown', 'dist', 'sim');
const {Teams} = require(PS);
const {TeamValidator} = require(path.join(PS, 'team-validator'));

const v = TeamValidator.get('gen9nationaldexrnb');
let bad = 0, n = 0;
const OUT = process.env.RNB_OUT || path.join(STUDY, 'generated', 'rnb');
for (const side of fs.readdirSync(path.join(OUT, 'teams'))) {
  const dir = path.join(OUT, 'teams', side);
  for (const f of fs.readdirSync(dir)) {
    n++;
    const problems = v.validateTeam(Teams.import(fs.readFileSync(path.join(dir, f), 'utf8')));
    if (problems && problems.length) {
      bad++;
      console.log(`${side}/${f}: ${problems.join(' | ')}`);
    }
  }
}
console.log(`${n} teams, ${bad} rejected`);
