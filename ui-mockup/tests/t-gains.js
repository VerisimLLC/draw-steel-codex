const { chromium } = require('playwright');
(async () => { const b = await chromium.launch(); const p = await require('./cbpage.js')(b);
  const r = await p.evaluate(() => {
    const out = {};
    out.read = ['Resource = "Surges"', 'resource is "surges" and Quantity >= 3', 'Resource = "Surges" and (Quantity >= 2)', 'Resource = "Surges" and (A) or (B)', 'Resource = "Wonder"'].map(c => JSON.stringify(readGainEvent('useresource', c)));
    const con = CB_CORE.classes.find(c => c.name === 'Conduit'); cls = importClassRecord(con, CB_CORE.subclasses.filter(x => x.primaryClassId === con.id));
    out.conduitFreqs = [...new Set(cls.gains.map(g => g.freq))];
    out.noMode = con.heroicResourceChecklist.filter(c => !c.mode).length;
    out.who = GAIN_WHO.map(x => x[0]).join(',');
    return out; });
  console.log(JSON.stringify(r, null, 1)); console.log('errs', p.errs); await b.close(); })();
