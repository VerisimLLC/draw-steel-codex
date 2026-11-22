const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const all = JSON.parse(fs.readFileSync('md_all.json', 'utf8')); const r = all.find(x => x.file === process.argv[2]);
  const b = await chromium.launch(); const p = await b.newPage(); p.on('pageerror', e => console.log('ERR', e.message));
  await p.goto('file:///home/user/draw-steel-codex/ui-mockup/ability-blocks-stack.html'); await p.waitForTimeout(200);
  console.log(await p.evaluate(md => { const t = cleanPastedText(markdownToPlain(md).text); const { ability, ctx } = importAbilityText(md); ab = ability; registerScopes(ab); compiledCache = null; const rec = compileAbility().rec; delete rec.guid;
    return t + '\n-----\n' + ctx.report.join(' | ') + '\n-----\n' + JSON.stringify(rec).slice(0, 1500) + '\n' + problems.map(q => q.msg).join('\n'); }, r.md));
  console.log('OURS', JSON.stringify(r.ours).slice(0, 1200)); await b.close();
})();
