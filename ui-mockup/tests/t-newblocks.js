const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await require('./cbpage.js')(b);
  const r = await p.evaluate(() => {
    const find = (cname, beh) => { const c = CB_CORE.classes.find(x => x.name === cname); cls = importClassRecord(c, CB_CORE.subclasses.filter(x => x.primaryClassId === c.id));
      for (const k in cls.lanes) for (const f of cls.lanes[k]) for (const s of f.sentences) if (SENT[s.type] && s.f && (beh === s.type)) return { f, s, k }; return null; };
    const words = s => { const d = document.createElement('div'); SENT[s.type].render(s.f, el => d.appendChild(el), s, {}); return d.textContent.replace(/\s+/g, ' ').trim(); };
    const out = {};
    for (const [cn, t] of [['Null', 'improve'], ['Null', 'suppress'], ['Troubadour', 'routine']]) {
      const hit = find(cn, t); if (!hit) { out[t] = 'not found'; continue; }
      out[t] = { words: words(hit.s).slice(0, 220), prose: SENT[t].prose(hit.s.f).slice(0, 160) };
      // edit one thing, save, and check that only that changed
      const before = JSON.parse(JSON.stringify(compileClass()));
      if (t === 'improve') hit.s.f.n = '5'; if (t === 'suppress') hit.s.f.why = 'Not while leaping'; if (t === 'routine') hit.s.f.rec.distance = 'Aura 10';
      const after = compileClass(); const diffs = [];
      (function df(a, c, pth) { if (JSON.stringify(a) === JSON.stringify(c)) return; if (a && c && typeof a === 'object' && typeof c === 'object') { new Set(Object.keys(a).concat(Object.keys(c))).forEach(k => df(a[k], c[k], pth + '.' + k)); return; } diffs.push(pth.replace(/^.*modifiers\./, 'mod.') + ': ' + JSON.stringify(a) + ' => ' + JSON.stringify(c)); })(before, after, '');
      out[t].edit = diffs;
    }
    return out; });
  console.log(JSON.stringify(r, null, 1)); console.log('errs', p.errs); await b.close(); })();
