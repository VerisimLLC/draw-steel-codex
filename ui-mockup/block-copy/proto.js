const { chromium } = require('playwright'); const fs = require('fs');
(async () => { const b = await chromium.launch(); const out = {};
  const a = await b.newPage({ viewport: { width: 1400, height: 1000 } });
  await a.goto('http://localhost:8765/ability-editor.html'); await a.waitForTimeout(500);
  const html = fs.readFileSync('/home/user/draw-steel-codex/ui-mockup/ability-blocks-stack.html', 'utf8');
  // typeName -> step key from the importer ("t === \"X\") st = STEPS.y")
  const imp = {}; for (const m of html.matchAll(/t === "([A-Za-z]+)"[^;]{0,80}?STEPS\.([A-Za-z]+)\.make/g)) imp[m[1]] = imp[m[1]] || m[2];
  out.ae = await a.evaluate((imp) => {
    const rows = [];
    for (const k of Object.keys(STEPS)) {
      const d = STEPS[k]; if (d.hidden && k !== 'generic') continue; if (k === 'generic') continue;
      let sentence = ''; window._tn = '';
      try { ab.steps.length = 0; const st = d.make('main'); ab.steps.push(st); editingId = null; refresh();
        const el = document.querySelector('[data-step="' + st.id + '"]'); var tn = ''; try { const c = compileAbility(); tn = [...new Set((c.rec.behaviors || []).map(x => x.__typeName))].join(', '); } catch (e2) {} window._tn = tn; sentence = el ? el.innerText.replace(/\s+/g, ' ').replace(/⋯|✕|⋮/g, '').trim() : ''; } catch (e) { sentence = '(' + e.message + ')'; }
      rows.push({ key: k, label: d.label, desc: d.desc, group: (PALETTE.find(g => g[2].includes(k)) || [d.cat, d.cat])[1], generic: !!d.generic, typeName: d.generic ? (GENERIC_BEHAVIORS.find(g => 'g_' + g[0] === k) || [])[2] : (window._tn || Object.keys(imp).find(t => imp[t] === k) || ''), sentence });
    }
    return rows;
  }, imp);
  const c = await b.newPage({ viewport: { width: 1440, height: 1000 } });
  await c.goto('http://localhost:8765/index.html'); await c.evaluate(() => localStorage.clear()); await c.reload(); await c.waitForTimeout(500);
  out.cb = await c.evaluate(() => Object.keys(SENT).map(k => { const d = SENT[k]; let beh = '', sentence = '';
    try { const s = makeSentence(k); const f = { id: 'fx', name: 'X', sentences: [s], text: '' }; const comp = JSON.stringify(compileFeature(f)); const m = comp.match(/"behavior":"([a-z_A-Z]+)"/); beh = m ? m[1] : (d.choice ? '(choice)' : '');
      const el = renderSentence(s, [s], 0, f); sentence = el.innerText.replace(/\s+/g, ' ').replace(/⋯|✕/g, '').trim(); window._p = autoText(f) || ''; } catch (e) { sentence = '(' + e.message + ')'; }
    const pr = window._p || ''; window._p = ''; return { key: k, label: d.label, desc: d.desc, group: (GROUPS.find(g => g[0] === d.group) || [0, d.group])[1], behavior: beh, sentence, prose: pr, choice: !!d.choice }; }));
  fs.writeFileSync('proto.json', JSON.stringify(out, null, 1)); console.log(out.ae.length, out.cb.length);
  console.log(out.ae.filter(r => !r.generic).map(r => r.key + '→' + r.typeName + ' | ' + r.sentence.slice(0, 70)).join('\n'));
  console.log(out.cb.map(r => r.key + '→' + r.behavior + ' | ' + r.sentence.slice(0, 70)).join('\n'));
  await b.close(); })();
