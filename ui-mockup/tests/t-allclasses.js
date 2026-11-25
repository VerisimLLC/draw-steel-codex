const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const b = await chromium.launch(); const p = await require('./cbpage.js')(b);
  const errs = p.errs;
  
  const r = await p.evaluate(() => {
    const deq = (a, c) => { if (JSON.stringify(a) === JSON.stringify(c)) return true; if (a && c && typeof a === 'object' && typeof c === 'object') { const ks = new Set(Object.keys(a).concat(Object.keys(c))); return [...ks].every(k => deq(a[k], c[k])); } return false; };
    const strip = rec => { const o = JSON.parse(JSON.stringify(rec)); if (o.levels) Object.keys(o.levels).forEach(k => { if (!(o.levels[k].features || []).length) delete o.levels[k]; }); return o; };
    const why = (m, filt) => {
      const rd = READERS[m.behavior] && READERS[m.behavior](m);
      if (!READERS[m.behavior]) return 'no block for ' + m.behavior;
      if (!rd) return 'reader declined (' + m.behavior + (m.modtype ? ' ' + m.modtype : '') + (m.rollType ? ' ' + m.rollType : '') + ') ' + Object.keys(m).filter(k => !['name','description','__typeName','domains','guid','source','sourceguid','sourceReference','implementation','behavior','modtype','rollType','keywords','activationCondition','displayCondition'].includes(k) && !(m[k] === '' || (Array.isArray(m[k]) && !m[k].length))).join(',');
      const t = { id: 'x', type: rd.type, f: rd.f, children: rd.children ? rd.children.map(c => ({ id: 'y', type: c.type, f: c.f })) : undefined };
      let c; try { c = compileSentences([t], { name: m.name, text: '' }, filt)[0]; } catch (e) { return 'compile error ' + e.message; }
      const keys = new Set(Object.keys(c).concat(SENT[t.type].claims || []));
      return rd.type + ' mismatch: ' + [...keys].filter(k => k !== 'name' && k !== 'description' && (k === 'filterCondition' ? !sameCond(c[k], m[k]) : !same(c[k] === undefined ? FIELD_DEFAULTS[k] : c[k], m[k] === undefined ? FIELD_DEFAULTS[k] : m[k]))).map(k => k + '=' + String(JSON.stringify(m[k])).slice(0, 80) + '|' + String(JSON.stringify(c[k])).slice(0, 80)).join('; ');
    };
    const out = { classes: [], grey: [], choices: [], textOnly: [], hrRaw: [], notSame: [] };
    CB_CORE.classes.forEach(rec => {
      const subs = CB_CORE.subclasses.filter(x => x.primaryClassId === rec.id);
      cls = importClassRecord(rec, subs);
      if (cls.hrRaw) out.hrRaw.push(rec.name);
      try {
        if (!deq(strip(rec), strip(compileClass()))) out.notSame.push(rec.name);
        cls.subclasses.forEach(sc => { if (!deq(strip(sc.src), strip(compileSubclass(sc)))) out.notSame.push(rec.name + '/' + sc.name); });
      } catch (e) { out.notSame.push(rec.name + ' ERROR ' + e.message); }
      const all = [[rec.name, cls.lanes, cls.importStats]].concat(cls.subclasses.map(sc => [rec.name + '/' + sc.name, sc.lanes, sc.stats]));
      all.forEach(([who, lanes, st]) => {
        out.classes.push([who, st.blocks, st.advanced, st.choices, st.advancedChoices, st.textOnly]);
        Object.keys(lanes).forEach(k => lanes[k].forEach(f => {
          if (!f.sentences.length) out.textOnly.push([who, k, f.name, (f.text || '').slice(0, 220)]);
          (function w(l, filt) { l.forEach(s => {
            if (s.type === 'advanced') out.grey.push([who, f.name, recKind(s.f.rec), why(s.f.rec, s.srcFilter)]);
            if (s.type === 'advancedChoice') { const c = s.f.rec; out.choices.push([who, f.name, c.__typeName, (c.options || []).map(o => (o.modifiers || []).map(m => m.behavior).join('+') || o.__typeName).join(' ; ').slice(0, 200)]); }
            if (s.children) w(s.children); if (s.f && s.f.rows) s.f.rows.forEach(r => w(r.blocks)); }); })(f.sentences);
        }));
      });

    });
    return out;
  });
  fs.writeFileSync('allcls.json', JSON.stringify(r, null, 1));
  const tot = r.classes.reduce((a, c) => [a[0] + c[1], a[1] + c[2], a[2] + c[3], a[3] + c[4], a[4] + c[5]], [0, 0, 0, 0, 0]);
  console.log('records as blocks', tot[0], 'grey', tot[1], 'choices', tot[2], 'grey choices', tot[3], 'text-only features', tot[4]);
  console.log('gains not paired (read-only):', r.hrRaw.join(', ') || 'none');
  console.log('not identical on unchanged save:', r.notSame.join(', ') || 'none');
  const byKind = {}; r.grey.forEach(g => { const k = g[3].replace(/mismatch: .*/, 'mismatch').replace(/\(.*\)/, m => m); byKind[k] = (byKind[k] || 0) + 1; });
  console.log(Object.entries(byKind).sort((a, b) => b[1] - a[1]).map(x => x[1] + '  ' + x[0]).join('\n'));
  console.log('errs', errs.slice(0, 3)); await b.close();
})();
