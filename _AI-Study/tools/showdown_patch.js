// Apply/revert experimental optimizations to Showdown's built dist. Backs up originals.
const fs = require('fs');
const P = '/mnt/c/Users/kny/Documents/Games/Norm/pokemon-showdown';
const F = { battle: P + '/dist/sim/battle.js', dex: P + '/dist/sim/dex.js' };
const which = process.argv.slice(2);

function backup(f) { if (!fs.existsSync(f + '.orig')) fs.copyFileSync(f, f + '.orig'); }
function restore() { for (const f of Object.values(F)) if (fs.existsSync(f + '.orig')) fs.copyFileSync(f + '.orig', f); console.log('reverted'); }
if (which[0] === 'revert') { restore(); process.exit(0); }
restore();
for (const f of Object.values(F)) backup(f);

let b = fs.readFileSync(F.battle, 'utf8');
const before = b;

// --- P1: hoist the per-call object literal + cache the three template-string keys ---
if (which.includes('prio')) {
  const old = `  resolvePriority(h, callbackName) {
    const handler = h;
    handler.order = handler.effect[\`\${callbackName}Order\`] || false;
    handler.priority = handler.effect[\`\${callbackName}Priority\`] || 0;
    handler.subOrder = handler.effect[\`\${callbackName}SubOrder\`] || 0;
    if (!handler.subOrder) {
      const effectTypeOrder = {`;
  if (!b.includes(old)) throw new Error('prio anchor not found');
  b = b.replace(old, `  resolvePriority(h, callbackName) {
    const handler = h;
    let __k = __keyCache.get(callbackName);
    if (__k === void 0) { __k = [callbackName + "Order", callbackName + "Priority", callbackName + "SubOrder"]; __keyCache.set(callbackName, __k); }
    handler.order = handler.effect[__k[0]] || false;
    handler.priority = handler.effect[__k[1]] || 0;
    handler.subOrder = handler.effect[__k[2]] || 0;
    if (!handler.subOrder) {
      const effectTypeOrder = __effectTypeOrder || {`);
  // close the hoist: the literal stays but is now only built once, cached on first use
  b = b.replace(`      handler.subOrder = effectTypeOrder[handler.effect.effectType] || 0;`,
                `      __effectTypeOrder = effectTypeOrder;
      handler.subOrder = effectTypeOrder[handler.effect.effectType] || 0;`);
}

// --- P2: per-effect handler map, so effect[callbackName] stops being a megamorphic miss ---
if (which.includes('cb')) {
  const old = `  getCallback(target, effect, callbackName) {
    let callback = effect[callbackName];`;
  if (!b.includes(old)) throw new Error('cb anchor not found');
  b = b.replace(old, `  getCallback(target, effect, callbackName) {
    let __m = __cbCache.get(effect);
    if (__m === void 0) {
      __m = new Map();
      for (const __key in effect) {
        if (__key.charCodeAt(0) === 111 && __key.charCodeAt(1) === 110) __m.set(__key, effect[__key]);
      }
      __cbCache.set(effect, __m);
    }
    let callback = __m.get(callbackName);`);
}

if (which.includes('prio') || which.includes('cb')) {
  b = b.replace('"use strict";', '"use strict";\nconst __keyCache = new Map();\nlet __effectTypeOrder = null;\nconst __cbCache = new WeakMap();');
}
if (b !== before) fs.writeFileSync(F.battle, b);

// --- P3: shallow copy instead of deepClone when a move is activated ---
if (which.includes('move')) {
  let d = fs.readFileSync(F.dex, 'utf8');
  const old = `    const moveCopy = this.deepClone(move);
    moveCopy.hit = 0;`;
  if (!d.includes(old)) throw new Error('move anchor not found');
  d = d.replace(old, `    const moveCopy = Object.assign(Object.create(Object.getPrototypeOf(move)), move);
    if (moveCopy.secondaries) moveCopy.secondaries = moveCopy.secondaries.map((s) => ({ ...s }));
    if (moveCopy.self) moveCopy.self = { ...moveCopy.self };
    if (moveCopy.boosts) moveCopy.boosts = { ...moveCopy.boosts };
    if (moveCopy.flags) moveCopy.flags = { ...moveCopy.flags };
    moveCopy.hit = 0;`);
  fs.writeFileSync(F.dex, d);
}
console.log('applied:', which.join(',') || '(none)');
