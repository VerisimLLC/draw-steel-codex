const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await require('./cbpage.js')(b);
  const r = await p.evaluate(() => {
    const out = {}, fury = JSON.parse(JSON.stringify(CB_CORE.classes.find(c => c.name === 'Fury')));
    fury.hitpointsCalculation = '21 + (Level - 1)*9 + Might';
    fury.levels['level-11'] = { __typeName: 'ClassLevel', features: [{ __typeName: 'CharacterFeature', name: 'Epic thing', guid: 'g11', modifiers: [] }] };
    cls = importClassRecord(fury, []);
    out.raw = { stamRaw: cls.stamRaw, start: cls.stamStart };
    const r1 = compileClass();
    out.unchanged = { hp: r1.hitpointsCalculation, l11: (r1.levels['level-11'] || {}).features && r1.levels['level-11'].features.map(f => f.name), emptyAdded: Object.keys(r1.levels).filter(k => !(k in fury.levels)) };
    cls.name = 'Fury Two'; const r2 = compileClass();
    out.renamed = { name: r2.name, hp: r2.hitpointsCalculation, l11: r2.levels['level-11'].features.length };
    cls.stamStart = '24 + (Level - 1)*9 + Might'; const r3 = compileClass();
    out.editedFormula = r3.hitpointsCalculation;
    return out; });
  console.log(JSON.stringify(r)); console.log('errs', p.errs); await b.close(); })();
