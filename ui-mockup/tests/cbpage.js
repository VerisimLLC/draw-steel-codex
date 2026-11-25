// Opens the class builder with files served from disk through Playwright routing.
const fs = require('fs'), path = require('path');
const ROOT = path.resolve(__dirname, '..', 'class-builder');
module.exports = async function openCB(b, opts = {}) {
  const ctx = await b.newContext(Object.assign({ viewport: { width: 1400, height: 1000 } }, opts));
  await ctx.route('http://cb.test/**', r => { const f = path.join(ROOT, decodeURIComponent(new URL(r.request().url()).pathname));
    const ct = f.endsWith('.html') ? 'text/html' : f.endsWith('.js') ? 'text/javascript' : f.endsWith('.css') ? 'text/css' : 'application/octet-stream';
    try { r.fulfill({ status: 200, contentType: ct, body: fs.readFileSync(f) }); } catch (e) { r.fulfill({ status: 404, body: '' }); } });
  const p = await ctx.newPage(); const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('http://cb.test/index.html'); await p.evaluate(() => localStorage.clear()); await p.reload(); await p.waitForTimeout(1500);
  p.errs = errs; return p;
};
