const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const b = await chromium.launch(); const p = await require('./cbpage.js')(b);
  const errs = p.errs;
  
  const r = await p.evaluate(() => {
    const strip = rec => { const o = JSON.parse(JSON.stringify(rec)); if (o.levels) Object.keys(o.levels).forEach(k => { if (!(o.levels[k].features || []).length) delete o.levels[k]; }); return o; };
    const diff = (a, c, path, out) => { if (JSON.stringify(a) === JSON.stringify(c)) return out;
      if (Array.isArray(a) && Array.isArray(c) && a.concat(c).every(x => x && x.guid)) { const bm = Object.fromEntries(c.map(x => [x.guid, x])); a.forEach(x => diff(x, bm[x.guid], path + '[]', out)); c.filter(x => !a.some(y => y.guid === x.guid)).forEach(x => out.push(path + ' +record')); return out; }
      if (a && c && typeof a === 'object' && typeof c === 'object') { new Set(Object.keys(a).concat(Object.keys(c))).forEach(k => diff(a[k], c[k], path + '.' + k, out)); return out; }
      out.push(path + '  ' + String(JSON.stringify(a)).slice(0, 60) + ' => ' + String(JSON.stringify(c)).slice(0, 60)); return out; };
    const forget = lanes => Object.values(lanes).flat().forEach(function ff(f) { f.snap = -1; (function w(l) { (l || []).forEach(s => { s.snap = -1; if (s.children) w(s.children); if (s.f && s.f.rows) s.f.rows.forEach(r => w(r.blocks)); if (s.f && s.f.options) s.f.options.forEach(o => { o.snap = -1; if (o.sentences) ff(o); }); }); })(f.sentences); });
    const all = [];
    CB_CORE.classes.forEach(rec => {
      cls = importClassRecord(rec, CB_CORE.subclasses.filter(x => x.primaryClassId === rec.id));
      forget(cls.lanes); cls.subclasses.forEach(sc => forget(sc.lanes));
      // gains too: rebuild every gain from its fields
      [cls.startGain].concat(cls.gains).filter(Boolean).forEach(g => { g.snap = -1; });
      try { all.push(...diff(strip(rec), strip(compileClass()), rec.name, [])); cls.subclasses.forEach(sc => all.push(...diff(strip(sc.src), strip(compileSubclass(sc)), rec.name + '/' + sc.name, []))); }
      catch (e) { all.push(rec.name + ' ERROR ' + e.message + ' ' + e.stack.split('\n')[1]); }
    });
    return all;
  });
  fs.writeFileSync(require('path').join(require('os').tmpdir(), 'rebuildall.txt'), r.join('\n'));
  const pat = {}; r.forEach(x => { const k = x.replace(/^[^.]*\.levels\.[a-z-]+\d*\.features/, 'F').replace(/\.\d+/g, '.N').split('  ')[0]; pat[k] = (pat[k] || 0) + 1; });
  console.log('total diffs', r.length); console.log(Object.entries(pat).sort((a, b) => b[1] - a[1]).slice(0, 45).map(x => x[1] + '  ' + x[0]).join('\n'));
  console.log('errs', errs.slice(0, 3)); await b.close();
})();
