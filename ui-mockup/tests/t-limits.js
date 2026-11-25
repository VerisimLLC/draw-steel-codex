const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await require('./cbpage.js')(b);
  const r = await p.evaluate(() => {
    const out = {};
    // 1. a new ability block, usable 2 times per round
    const f = SENT.ability.make(); f.rec = { __typeName: 'ActivatedAbility', name: 'Test', behaviors: [] }; f.limit = 'round'; f.uses = '2';
    const m = compileSentences([{ id: 'a', type: 'ability', f }], { name: 'F', text: '' }, null)[0];
    out.ability = { guid: !!m.guid, rrt: m.resourceRefreshType, n: m.numCharges, inner: m.activatedAbility.usageLimitOptions, keyed: m.activatedAbility.usageLimitOptions.resourceid === m.guid, modelUntouched: !f.rec.usageLimitOptions };
    // 2. a new gain, once per round
    cls.gains.push({ id: newId('g'), event: 'dealdamage', freq: 'round', who: 'self', cond: null, qty: '2', qtyLv: [{ from: '4', value: '3' }], guid: guid() });
    const t = compileGains().triggers.at(-1);
    out.gain = { rrt: t.resourceRefreshType, inner: t.triggeredAbility.usageLimitOptions, keyed: t.triggeredAbility.usageLimitOptions.resourceid === t.guid, qty: t.triggeredAbility.behaviors[0].quantity.__typeName || t.triggeredAbility.behaviors[0].quantity };
    // 3. the Fury: change "take damage" from once per round to whenever
    const fury = CB_CORE.classes.find(c => c.name === 'Fury'); cls = importClassRecord(fury, []);
    const g = cls.gains.find(x => x.event === 'losehitpoints'); out.before = g.freq; g.freq = 'recurring';
    const rec = compileClass(); let saved = null;
    JSON.stringify(rec, (k, v) => { if (v && v.triggeredAbility && (v.triggeredAbility.behaviors || []).some(b => b.checklistid === g.guid)) saved = v; return v; });
    out.fury = { rrt: saved.resourceRefreshType, inner: saved.triggeredAbility.usageLimitOptions, mode: rec.heroicResourceChecklist.find(c => c.guid === g.guid).mode };
    // 4. ... and back to once per encounter
    g.freq = 'encounter'; const rec2 = compileClass(); let s2 = null;
    JSON.stringify(rec2, (k, v) => { if (v && v.triggeredAbility && (v.triggeredAbility.behaviors || []).some(b => b.checklistid === g.guid)) s2 = v; return v; });
    out.fury2 = { rrt: s2.resourceRefreshType, inner: s2.triggeredAbility.usageLimitOptions };
    // 5. a new gain's amount reads back with its level step
    cls = blankClass(); cls.gains.push({ id: newId('g'), event: 'dealdamage', freq: 'round', who: 'self', cond: null, qty: '2', qtyLv: [{ from: '4', value: '3' }], guid: guid() });
    const back = importClassRecord(compileClass(), []); const bg = back.gains.find(x => x.event === 'dealdamage');
    out.roundtrip = { qty: bg.qty, lv: bg.qtyLv, freq: bg.freq };
    return out; });
  console.log(JSON.stringify(r, null, 1)); console.log('errs', p.errs); await b.close(); })();
