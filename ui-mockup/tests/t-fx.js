const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await require('./cbpage.js')(b);
  const r = await p.evaluate(() => { const out = [];
    for (const c of CB_CORE.classes) { cls = importClassRecord(c, []);
      const all = []; (function w(l) { l.forEach(s => { all.push(s); childLists(s).forEach(w); }); })(Object.values(cls.lanes).flat().flatMap(x => x.sentences));
      const s0 = all.find(s => s.snap != null && blockSnap(s) === s.snap && s.f && ['amount', 'num', 'value', 'n'].some(k => k in s.f));
      if (!s0) continue; const key = ['amount', 'num', 'value', 'n'].find(k => k in s0.f);
      const m = document.createElement('div'); fillFx(m, s0.f, key);
      out.push([c.name, s0.type, key, blockSnap(s0) === s0.snap]); if (out.length >= 4) break; }
    return out; });
  console.log(JSON.stringify(r)); console.log('errs', p.errs); await b.close(); })();
