// Sequential targeting: shown for several targets, saved as sequentialTargeting, read back.
const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 1400, height: 1000 } }); const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file://' + require('path').resolve(__dirname, '..', 'ability-blocks-stack.html')); await p.waitForTimeout(600);
  const r = await p.evaluate(() => {
    const out = {};
    const rec = { __typeName: 'ActivatedAbility', name: 'Three Strikes', targetType: 'target', range: '1', numTargets: '3', keywords: { Melee: true, Strike: true }, behaviors: [] };
    ab = openForEditing(JSON.parse(JSON.stringify(rec))); refresh();
    out.rowShown = document.body.innerText.includes('Targets are:');
    out.before = 'sequentialTargeting' in compileAbility().rec;
    ab.seqMode = 'one at a time';
    const saved = compileAbility().rec; out.saved = saved.sequentialTargeting;
    ab = openForEditing(JSON.parse(JSON.stringify(saved))); out.reread = ab.seqMode;
    ab.seqMode = 'all together'; out.cleared = 'sequentialTargeting' in compileAbility().rec;
    const one = { __typeName: 'ActivatedAbility', name: 'One', targetType: 'target', range: '1', numTargets: '1', keywords: { Melee: true }, behaviors: [] };
    ab = openForEditing(one); refresh();
    out.rowForOne = document.body.innerText.includes('Targets are:');
    return out; });
  console.log(JSON.stringify(r)); console.log('errs', errs); await b.close(); })();
