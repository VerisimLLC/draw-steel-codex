// Second poll: open each sampled ability or trigger, save it back, edit it, and capture the card.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const sample = JSON.parse(fs.readFileSync('sample2.json', 'utf8'));
  const b = await chromium.launch(); const p = await (await b.newContext({ viewport: { width: 1400, height: 1000 } })).newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file:///home/user/draw-steel-codex/ui-mockup/ability-blocks-stack.html'); await p.waitForTimeout(300);
  const res = [];
  for (const r of sample) {
    const row = await p.evaluate((r) => {
      const canon = v => String(JSON.stringify(v, (k, x) => x && typeof x === 'object' && !Array.isArray(x) ? Object.keys(x).sort().reduce((o, kk) => (x[kk] !== undefined && (o[kk] = x[kk]), o), {}) : x));
      const diffKeys = (a, b) => { const ks = new Set(Object.keys(a || {}).concat(Object.keys(b || {}))); return [...ks].filter(k => canon((a || {})[k]) !== canon((b || {})[k])); };
      const count = (l, c) => { l.forEach(st => { c[st.type === 'opaque' ? 'advanced' : st.type === 'todo' ? 'todo' : 'block']++; if (st.type === 'opaque') c.advTypes.push(st.f.summary.split(':')[0]); if (st.type === 'todo') c.todos.push(st.f.text); for (const k in st.branches || {}) count(st.branches[k], c); }); return c; };
      const row = { source: r.source, kind: r.kind, who: r.monster || r.cls, level: r.level, name: r.name };
      const src = r.rec;
      try {
        ab = openForEditing(src);
        row.steps = count(ab.steps, { block: 0, advanced: 0, todo: 0, advTypes: [], todos: [] });
        row.hidden = ab.openHidden || [];
        const c1 = compileAbility(); row.problems = problems.filter(q => !q.soft).map(q => q.msg); row.checks = problems.filter(q => q.soft).map(q => q.msg);
        row.untouchedSame = canon(c1.rec) === canon(src);
        if (!row.untouchedSame) row.untouchedDiff = diffKeys(c1.rec, src).map(k => k + ': ' + canon(src[k]).slice(0, 200) + '  =>  ' + canon(c1.rec[k]).slice(0, 200));
        // rename
        ab = openForEditing(src); ab.name = ab.name + ' II'; const ren = compileAbility().rec; row.renameDiff = diffKeys(ren, src);
        // tier edit
        ab = openForEditing(src);
        const findPR = l => { for (const st of l) { if (st.type === 'powerRoll') return st; for (const k in st.branches || {}) { const f = findPR(st.branches[k]); if (f) return f; } } return null; };
        const pr = findPR(ab.steps); const dmg = pr && pr.branches.t1.find(st => st.type === 'damage');
        if (dmg) { const old = cHolder(dmg.slots.amount).s; dmg.slots.amount = holderFromText('roll', 'tierDamage', old.replace(/\d+/, n => String(+n + 1)));
          const ed = compileAbility().rec; const bs = (src.behaviors || []), es = (ed.behaviors || []);
          const prb = bs.find(x => x.__typeName === 'ActivatedAbilityPowerRollBehavior'), pre = es.find(x => x.__typeName === 'ActivatedAbilityPowerRollBehavior');
          row.tierEdit = { topChanged: diffKeys(ed, src).filter(k => k !== 'behaviors'), behChanged: es.filter((x, i) => canon(x) !== canon(bs[i])).length, tiers: prb && pre ? prb.tiers.map((t, i) => [t, pre.tiers[i]]).filter(x => x[0] !== x[1]) : null }; }
        // the card as shown
        ab = openForEditing(src); refresh();
        const q = sel => [...document.querySelectorAll(sel)];
        const card = document.querySelector('.card');
        row.card = { title: card.querySelector('h2').innerText, dist: (card.querySelector('.dtrow .dt .ctext') || {}).innerText || '', target: (card.querySelector('.dtrow .dt.right .ctext') || {}).innerText || '',
          tiers: q('.card .cline.tier .ctext').map(e => e.innerText), effects: q('.card .cline.eff').filter(e => e.querySelector('b, .clabel')).map(e => [((e.querySelector('b, .clabel') || {}).innerText || '').replace(/:$/, ''), (e.querySelector('.ctext') || {}).innerText || '']) };
      } catch (e) { row.error = String(e.stack || e).slice(0, 400); }
      return row;
    }, r);
    row.book = r.book; res.push(row);
  }
  fs.writeFileSync('roundtrip2.json', JSON.stringify(res, null, 1));
  console.log('page errors:', errs.slice(0, 3)); await b.close();
})();
