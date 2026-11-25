// Every core class / subclass ability: open in the ability editor, save unchanged, compare.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const s = fs.readFileSync(require('path').resolve(__dirname, '..', 'class-builder', 'core-classes.js'), 'utf8');
  const d = JSON.parse(s.slice(s.indexOf('{'), s.lastIndexOf('}') + 1)); const abil = [];
  (function walk(o) { if (Array.isArray(o)) return o.forEach(walk); if (o && typeof o === 'object') { if (o.__typeName === 'ActivatedAbility' && o.categorization !== 'Hidden') abil.push(o); Object.values(o).forEach(walk); } })(d);
  const b = await chromium.launch(); const p = await b.newPage(); const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://' + require('path').resolve(__dirname, '..', 'ability-blocks-stack.html')); await p.waitForTimeout(500);
  const r = await p.evaluate(list => {
    const canon = v => JSON.stringify(v, (k, x) => x && typeof x === 'object' && !Array.isArray(x) ? Object.keys(x).sort().reduce((o, kk) => (x[kk] !== undefined && (o[kk] = x[kk]), o), {}) : x);
    let same = 0; const bad = [];
    list.forEach(r => { try { ab = openForEditing(JSON.parse(JSON.stringify(r))); (function w(o, seen) { if (!o || typeof o !== 'object' || seen.has(o)) return; seen.add(o); if ('openSig' in o) o.openSig = 'forced'; Object.values(o).forEach(v => w(v, seen)); })(ab, new Set()); const c = compileAbility(); if (canon(c.rec) === canon(r)) same++; else bad.push(r.name); } catch (e) { bad.push(r.name + ' ERR ' + e.message); } });
    return { total: list.length, same, bad: bad.slice(0, 8) }; }, abil);
  console.log(JSON.stringify(r)); console.log('errs', errs.slice(0, 3)); await b.close();
})();
