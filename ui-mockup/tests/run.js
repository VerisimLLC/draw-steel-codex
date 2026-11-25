// Runs the block editor prototype tests and checks each one's result.
// Usage (from the repo root, with Playwright installed): node ui-mockup/tests/run.js
// These are the invariants the Lua port must keep (BLOCK_EDITOR_REVIEW.md, section 6).
const { execFileSync } = require('child_process');
const path = require('path');

const CHECKS = [
  // Every core class and subclass opens as blocks and saves back unchanged.
  ['t-allclasses.js', out => /not identical on unchanged save: none/.test(out)],
  // Forcing every block to rebuild still writes the saved records.
  ['t-rebuild.js', out => /total diffs 0\b/.test(out)],
  // Usage limits are written where the game reads them (usageLimitOptions), keyed by the modifier.
  ['t-limits.js', out => { const j = json(out); return j.ability.keyed && j.ability.inner.charges === '2' && j.gain.keyed
    && j.fury.rrt === 'none' && j.fury.inner.resourceRefreshType === 'none' && j.fury2.inner.resourceRefreshType === 'encounter'
    && j.roundtrip.lv.length === 1; }],
  // An odd Stamina formula and levels 11+ survive a save.
  ['t-classrec.js', out => { const j = json(out); return j.unchanged.hp === '21 + (Level - 1)*9 + Might' && j.unchanged.l11.length === 1
    && !j.unchanged.emptyAdded.length && j.renamed.hp === j.unchanged.hp && j.editedFormula === '24 + (Level - 1)*9 + Might'; }],
  // Gain lines read back as the game counts them; the surges reader uses its own limit.
  ['t-gains.js', out => { const j = json(out); return !j.conduitFreqs.includes('recurring') && /spendsurges/.test(j.read[1]) && /useresource/.test(j.read[3]); }],
  // Only if is refused where the game ignores it; combining keeps the roll requirement.
  ['t-blocks.js', out => { const j = json(out); return !j.kitAllowed && j.statAllowed && j.kitIssue.length === 1 && j.combo.req === 'hasSurges' && j.combo.attr === 'mgt'; }],
  // Opening the formula picker doesn't mark a block as edited.
  ['t-fx.js', out => json(out).every(x => x[3] === true)],
  // Every core ability opens in the ability editor and saves back unchanged (4 known exceptions).
  ['t-ab.js', out => json(out).same >= 1015],
  // Treating every step as edited still keeps the saved records (13 known reader-precision cases).
  ['t-ab-forced.js', out => json(out).same >= 1006],
];

function json(out) { const s = out.slice(out.indexOf('{') >= 0 && (out.indexOf('[') < 0 || out.indexOf('{') < out.indexOf('[')) ? out.indexOf('{') : out.indexOf('['));
  let depth = 0, end = 0; for (let i = 0; i < s.length; i++) { if ('{['.includes(s[i])) depth++; else if ('}]'.includes(s[i]) && --depth === 0) { end = i + 1; break; } }
  return JSON.parse(s.slice(0, end)); }

let failed = 0;
for (const [file, ok] of CHECKS) {
  let out = '';
  try { out = execFileSync(process.execPath, [path.join(__dirname, file)], { encoding: 'utf8', timeout: 300000 }); } catch (e) { out = String(e.stdout || '') + String(e.message); }
  let pass = false; try { pass = ok(out) && !/errs \[\s*'/.test(out); } catch (e) { pass = false; }
  console.log((pass ? 'PASS ' : 'FAIL ') + file); if (!pass) { failed++; console.log(out.slice(0, 1500)); }
}
console.log(failed ? failed + ' failed' : 'all passed');
process.exitCode = failed ? 1 : 0;
