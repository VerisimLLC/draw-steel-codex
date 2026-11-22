// Paste every Steel Compendium ability page into the reader; count what it builds and compare the saved
// result with the same ability in our compendium data.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const all = JSON.parse(fs.readFileSync('md_all.json', 'utf8'));
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file:///home/user/draw-steel-codex/ui-mockup/ability-blocks-stack.html'); await p.waitForTimeout(200);
  const res = await p.evaluate((all) => {
    const walk = (l, c, inTier) => l.forEach(st => {
      if (st.type === 'todo') { c.todo++; (inTier ? (c.tierTodos = c.tierTodos || []) : c.todos).push(st.f.text); }
      else if (st.type === 'opaque') c.advanced++;
      else c.block++;
      (c.types[st.type] = (c.types[st.type] || 0) + 1);
      for (const k in (st.branches || {})) walk(st.branches[k], c, inTier || /^t\d$/.test(k));
    });
    const norm = t => String(t || '').toLowerCase().replace(/[#\s]/g, '').replace(/–/g, '-').replace(/[‘’]/g, "'");
    const out = [];
    for (const r of all) {
      const row = { file: r.file, name: r.name, cls: r.cls, level: r.level };
      try {
        const { ability, ctx } = importAbilityText(r.md);
        ab = ability; registerScopes(ab); compiledCache = null;
        const c = { block: 0, advanced: 0, todo: 0, todos: [], types: {} }; walk(ab.steps, c);
        row.steps = c; row.parsedName = ab.name; row.guesses = ctx.guesses;
        const comp = compileAbility(); const rec = comp.rec;
        row.problems = problems.filter(q => !q.soft).map(q => q.msg); row.checks = problems.filter(q => q.soft).map(q => q.msg);
        row.full = c.todo === 0 && row.problems.length === 0;
        if (r.ours) {
          const o = r.ours, cmp = {};
          const kw = x => Object.keys(x || {}).filter(k => x[k]).sort().join(',');
          cmp.keywords = kw(rec.keywords) === kw(o.keywords) || [kw(o.keywords), kw(rec.keywords)];
          const act = x => /^<.*>$/.test(x || '') ? x.slice(1, -1).toLowerCase() : (resourceNameById(x) || x || '').toLowerCase();
          cmp.action = act(rec.actionResourceId) === act(o.actionResourceId) || [act(o.actionResourceId), act(rec.actionResourceId)];
          cmp.targetType = rec.targetType === o.targetType || [o.targetType, rec.targetType];
          cmp.range = String(rec.range) === String(o.range) || [o.range, rec.range];
          cmp.cost = String(rec.resourceNumber || 0) === String(o.resourceNumber || 0) || [o.resourceNumber, rec.resourceNumber];
          const pr = x => ((x.behaviors || []).find(y => y.__typeName === 'ActivatedAbilityPowerRollBehavior') || {});
          const pt = pr(rec).tiers || [], ot = pr(o).tiers || [];
          cmp.tiers = (pt.length === ot.length && pt.every((t, i) => norm(t) === norm(ot[i]))) || [ot, pt];
          cmp.roll = norm(pr(rec).roll) === norm(pr(o).roll) || [pr(o).roll, pr(rec).roll];
          const bt = x => (x.behaviors || []).map(y => y.__typeName.replace(/^ActivatedAbility|Behavior$/g, '')).sort().join(',');
          cmp.behaviours = bt(rec) === bt(o) || [bt(o), bt(rec)];
          row.cmp = cmp;
        }
      } catch (e) { row.error = String(e && e.stack || e).slice(0, 400); }
      out.push(row);
    }
    return out;
  }, all);
  fs.writeFileSync('paste4.json', JSON.stringify(res, null, 1));
  console.log('page errors:', errs.slice(0, 5));
  await b.close();
})();
