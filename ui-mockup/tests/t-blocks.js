const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await require('./cbpage.js')(b);
  const r = await p.evaluate(() => { const out = {};
    out.kitAllowed = onlyIfAllowed('kit'); out.statAllowed = onlyIfAllowed('stat'); out.surgesAllowed = onlyIfAllowed('surges');
    // a kit block inside an Only if is flagged
    const f = { id: newId('f'), kind: 'feature', name: 'Kit test', text: '', sentences: [] };
    const oi = makeSentence('onlyIf'); oi.f.cond = { t: 'raw', src: 'Level >= 2' }; oi.children.push(makeSentence('kit')); f.sentences.push(oi);
    out.kitIssue = featureIssues(f, 'level-1').map(i => i.msg).filter(m => /ignores/.test(m));
    // combining keeps the roll requirement and the characteristic
    const e = makeSentence('edge'); e.f.req = 'hasSurges'; e.f.attr = 'mgt'; const d = makeSentence('damage'); d.f.req = 'hasSurges';
    const list = [e, d]; cls.lanes['level-1'] = [{ id: newId('f'), kind: 'feature', name: 'Combo', text: '', sentences: list }];
    combineBlocks(list, [e.id, d.id]);
    const rec = compileSentences(cls.lanes['level-1'][0].sentences, { name: 'Combo', text: '' })[0];
    out.combo = { req: rec.rollRequirement, attr: rec.attribute, n: cls.lanes['level-1'][0].sentences.length };
    // opening the formula picker doesn't change a block's snapshot
    const fury = CB_CORE.classes.find(c => c.name === 'Fury'); cls = importClassRecord(fury, []);
    const s0 = Object.values(cls.lanes).flat().flatMap(x => x.sentences).find(x => x.f && 'num' in x.f || x.f && 'amount' in x.f);
    const key = 'amount' in s0.f ? 'amount' : 'num'; const before = blockSnap(s0) === s0.snap;
    const m = document.createElement('div'); fillFx(m, s0.f, key); out.fxNoChange = { before, after: blockSnap(s0) === s0.snap, lvKey: (key + 'Lv') in s0.f };
    return out; });
  console.log(JSON.stringify(r)); console.log('errs', p.errs); await b.close(); })();
