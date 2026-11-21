// All triggers: open with their display, save, rename, and read the card and the trigger condition.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const all = JSON.parse(fs.readFileSync('triggers_all.json', 'utf8'));
  const b = await chromium.launch(); const p = await (await b.newContext({ viewport: { width: 1400, height: 1000 } })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file:///home/user/draw-steel-codex/ui-mockup/ability-blocks-stack.html'); await p.waitForTimeout(300);
  const res = [];
  for (let i = 0; i < all.length; i += 50) {
    const chunk = all.slice(i, i + 50);
    const rows = await p.evaluate((chunk) => {
      const canon = v => String(JSON.stringify(v, (k, x) => x && typeof x === 'object' && !Array.isArray(x) ? Object.keys(x).sort().reduce((o, kk) => (x[kk] !== undefined && (o[kk] = x[kk]), o), {}) : x));
      const diffKeys = (a, b) => { const ks = new Set(Object.keys(a || {}).concat(Object.keys(b || {}))); return [...ks].filter(k => canon((a || {})[k]) !== canon((b || {})[k])); };
      const rawSrcs = (x, out) => { if (!x || typeof x !== 'object') return out; if (x.type === 'raw') out.push(x.f.src); for (const k in x) rawSrcs(x[k], out); return out; };
      const count = (l, c) => { l.forEach(st => { c[st.type === 'opaque' ? 'advanced' : st.type === 'todo' ? 'todo' : 'block']++; if (st.type === 'opaque') c.advTypes.push(st.f.summary.split(':')[0]); for (const k in st.branches || {}) count(st.branches[k], c); }); return c; };
      return chunk.map(r => {
        const row = { folder: r.folder, owner: r.owner, name: r.name, kind: r.kind, hasDisplay: !!r.display, hasBook: !!r.book };
        try {
          ab = openForEditing(r.rec, r.display);
          row.event = ab.trig.event; row.who = ab.trig.who; row.action = ab.trig.action;
          row.steps = count(ab.steps, { block: 0, advanced: 0, todo: 0, advTypes: [] });
          row.hidden = ab.openHidden || [];
          const c1 = compileAbility(); row.problems = problems.map(q => q.msg);
          row.same = canon(c1.rec) === canon(r.rec);
          if (!row.same) row.diff = diffKeys(c1.rec, r.rec).map(k => k + ': ' + canon(r.rec[k]).slice(0, 160) + ' => ' + canon(c1.rec[k]).slice(0, 160));
          row.displaySame = r.display ? canon(c1.display) === canon(r.display) : c1.display === null;
          if (!row.displaySame) row.displayDiff = r.display ? diffKeys(c1.display, r.display).concat(diffKeys((c1.display || {}).ability, r.display.ability).map(k => 'ability.' + k)) : ['created a display'];
          // the condition, as blocks
          const cond = (r.kind === 'powertabletrigger' ? r.rec.targetFilter : (r.rec.triggeredAbility || {}).conditionFormula) || '';
          row.cond = cond;
          if (cond) { const h = holderFromText('boolean', 'trigCond', cond); const raws = h.expr ? rawSrcs(h.expr, []) : []; row.condRaw = raws; row.condProse = cHolder(h).prose; }
          // rename: only names change, on the trigger and its display
          ab = openForEditing(r.rec, r.display); ab.name = ab.name + ' II'; const c2 = compileAbility();
          const inner = (x, y, k) => diffKeys((x || {})[k], (y || {})[k]).filter(z => !(k === 'powerRollModifier' && z === 'customTrigger' && diffKeys(x[k].customTrigger, y[k].customTrigger).every(w => w === 'name')));
          row.renameOk = diffKeys(c2.rec, r.rec).every(k => k === 'name' || (['triggeredAbility', 'powerRollModifier'].includes(k) && inner(c2.rec, r.rec, k).every(z => z === 'name')))
            && (!r.display || (diffKeys(c2.display, r.display).every(k => k === 'name' || (k === 'ability' && inner(c2.display, r.display, 'ability').every(z => z === 'name')))));
          // the card the editor shows
          if (r.display && r.book) { ab = openForEditing(r.rec, r.display); refresh();
            const q = s => [...document.querySelectorAll(s)];
            row.card = { dist: (document.querySelector('.card .dtrow .dt .ctext') || {}).innerText || '', target: (document.querySelector('.card .dtrow .dt.right .ctext') || {}).innerText || '',
              tiers: q('.card .cline.tier .ctext').map(e => e.innerText), effects: q('.card .cline.eff').filter(e => e.querySelector('b, .clabel')).map(e => [((e.querySelector('b, .clabel') || {}).innerText || '').replace(/:$/, ''), (e.querySelector('.ctext') || {}).innerText || '']) }; }
        } catch (e) { row.error = String(e.stack || e).slice(0, 300); }
        return row;
      });
    }, chunk);
    rows.forEach((row, k) => { row.book = chunk[k].book; res.push(row); });
    process.stdout.write('.');
  }
  fs.writeFileSync('roundtrip3.json', JSON.stringify(res));
  console.log('\npage errors:', errs.slice(0, 3)); await b.close();
})();
