// Open each sampled class ability as blocks, save it back, and compare with the original.
const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const sample = JSON.parse(fs.readFileSync('sample.json', 'utf8'));
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file:///home/user/draw-steel-codex/ui-mockup/ability-blocks-stack.html'); await p.waitForTimeout(200);
  const res = await p.evaluate((sample) => {
    const canon = v => String(JSON.stringify(v, (k, x) => x && typeof x === 'object' && !Array.isArray(x) ? Object.keys(x).sort().reduce((o, kk) => (x[kk] !== undefined && (o[kk] = x[kk]), o), {}) : x));
    const diffKeys = (a, b) => { const ks = new Set(Object.keys(a).concat(Object.keys(b))); return [...ks].filter(k => canon(a[k]) !== canon(b[k])); };
    const countSteps = (l, c) => { l.forEach(st => { c[st.type === 'opaque' ? 'advanced' : st.type === 'todo' ? 'todo' : 'block']++; if (st.type === 'opaque') (c.advTypes = c.advTypes || []).push(st.f.summary + (st.f.record.abilityType ? '(' + st.f.record.abilityType + ')' : '')); if (st.type === 'todo') c.todos.push(st.f.text); for (const k in st.branches || {}) countSteps(st.branches[k], c); }); return c; };
    const out = [];
    for (const r of sample) {
      const row = { klass: r.klass, level: r.level, name: r.name, kind: r.kind };
      if (r.kind !== 'ability') { row.skipped = 'trigger (CharacterModifier): not opened in this test'; out.push(row); continue; }
      const src = r.rec;
      try {
        // 1. open
        const a = openForEditing(src);
        row.steps = countSteps(a.steps, { block: 0, advanced: 0, todo: 0, todos: [] });
        row.hidden = a.openHidden;
        row.problems = (compileAbility(), problems.filter(q => !q.soft).map(q => q.msg)); row.checks = problems.filter(q => q.soft).map(q => q.msg);
        // 2. untouched save
        const saved = compileAbility().rec;
        row.untouchedSame = canon(saved) === canon(src);
        if (!row.untouchedSame) row.savedRec = saved; if (!row.untouchedSame) row.untouchedDiff = diffKeys(saved, src).map(k => k + ': ' + canon(src[k]).slice(0, 140) + '  =>  ' + canon(saved[k]).slice(0, 140));
        // 3. what the blocks alone regenerate (no keeping of originals)
        sigMode = 'off'; const raw = compileAbility().rec; sigMode = null;
        const fieldDiffs = Object.keys(raw).filter(k => k !== 'behaviors' && canon(raw[k]) !== canon(src[k])).map(k => k + ': ' + canon(src[k]).slice(0, 90) + ' => ' + canon(raw[k]).slice(0, 90));
        const sb = src.behaviors || [], rb = raw.behaviors || [];
        const behDiffs = [];
        for (let i = 0; i < Math.max(sb.length, rb.length); i++) {
          const x = sb[i], y = rb[i];
          if (!x || !y) { behDiffs.push('#' + i + ' ' + (x ? 'missing after save: ' + x.__typeName : 'extra after save: ' + y.__typeName)); continue; }
          if (x.__typeName !== y.__typeName) { behDiffs.push('#' + i + ' order/type: ' + x.__typeName + ' vs ' + y.__typeName); continue; }
          const ks = diffKeys(x, y).filter(k => !['guid', 'name', 'chatMessage'].includes(k));
          if (ks.length) behDiffs.push('#' + i + ' ' + x.__typeName.replace(/^ActivatedAbility|Behavior$/g, '') + ': ' + ks.map(k => k + ' ' + canon(x[k]).slice(0, 110) + ' => ' + canon(y[k]).slice(0, 110)).join(' | '));
        }
        row.regen = { fieldDiffs, behDiffs };
        // 4a. rename only
        ab = openForEditing(src); ab.name = ab.name + ' II';
        const ren = compileAbility().rec; row.renameDiff = diffKeys(ren, src);
        // 4b. raise the first tier damage by 1
        ab = openForEditing(src);
        const findPR = l => { for (const st of l) { if (st.type === 'powerRoll') return st; for (const k in st.branches || {}) { const f = findPR(st.branches[k]); if (f) return f; } } return null; };
        const pr = findPR(ab.steps);
        const dmg = pr && pr.branches.t1.find(st => st.type === 'damage');
        if (dmg) {
          const old = cHolder(dmg.slots.amount).s; const nw = old.replace(/\d+/, n => String(+n + 1));
          dmg.slots.amount = holderFromText('roll', 'tierDamage', nw);
          const ed = compileAbility().rec;
          const before = (src.behaviors || []).filter(x => x.__typeName === 'ActivatedAbilityPowerRollBehavior');
          const after = (ed.behaviors || []).filter(x => x.__typeName === 'ActivatedAbilityPowerRollBehavior');
          row.tierEdit = { changedTopFields: diffKeys(ed, src).filter(k => k !== 'behaviors'), changedBehaviours: (ed.behaviors || []).filter((x, i) => canon(x) !== canon((src.behaviors || [])[i])).length,
            tiers: before.length && after.length ? before[0].tiers.map((t, i) => [t, after[0].tiers[i]]) : null };
        }
      } catch (e) { row.error = String(e.stack || e).slice(0, 300); }
      out.push(row);
    }
    return out;
  }, sample);
  fs.writeFileSync('roundtrip.json', JSON.stringify(res, null, 1));
  console.log('page errors:', errs.slice(0, 3));
  await b.close();
})();
