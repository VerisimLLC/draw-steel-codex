// Second pass: classify round-trip differences and project coverage once planned blocks exist.
const fs = require('fs');
const E = require(process.cwd() + '/engine.js');
E.DOCS.trigger = E.DOCS.stepIf; E.DOCS.powerRoll = E.DOCS.tierDamage;
const rows = fs.readFileSync('formulas.jsonl', 'utf8').trim().split('\n').map(JSON.parse).filter(r => r.abType === 'ActivatedAbility');
const canon = s => E.norm(E.printAst(E.parseGS(s)));
// Equivalent spellings: "else 0" is the default, Self. is implied, Target. is the subject in target filters,
// and string comparisons ignore case.
const eqv = (s, docs) => { let t = canon(s).replace(/else0(?=\)|$)/g, '').replace(/self\./g, ''); if (docs === 'targetFilter') t = t.replace(/target\./g, ''); return t.replace(/[()]/g, ''); };
function rawSrcs(x, out) { if (!x || typeof x !== 'object') return out; if (x.type === 'raw') out.push(x.f.src); for (const k in x) rawSrcs(x[k], out); return out; }
function cls(src) {
  let a; try { a = E.parseGS(src); } catch (e) { return 'unparsed'; }
  const p = E.printAst(a).toLowerCase();
  if (/passespotency|potencyresistance/.test(p)) return 'potency check';
  if (/^friends\(/.test(p) || /friends\(/.test(p)) return 'allies / enemies';
  if (a.k === 'id' && /^(monster)?mode$/.test(p)) return 'mode';
  if ((a.k === 'has' || a.k === 'is') && /ongoingeffects/.test(E.printAst(a.l).toLowerCase())) return 'has ongoing effect';
  if ((a.k === 'has' || a.k === 'is') && /keywords|^target$|^self$|^caster$/.test(E.printAst(a.l).toLowerCase())) return 'has keyword';
  if (a.k === 'or' || a.k === 'and') return 'higher of (or on numbers)';
  if (a.k === 'id') return 'symbol (from field descriptions)';
  if (a.k === 'param') return 'parameter from invoking ability';
  if (a.k === 'call' && /^(target|caster|self|cast|invoker)?\.?distance$/.test(a.path.join('.').toLowerCase())) return 'distance';
  return 'other: ' + a.k;
}
const S = { nonliteral: 0, exact: 0, projected: 0, parseFail: 0, rtSame: 0, rtEquiv: 0, rtDiff: 0 };
const C = {}, diffs = [], pf = {};
for (const r of rows) {
  if (r.kind !== 'boolean' && /^\d+$/.test(r.formula)) continue;
  S.nonliteral++;
  try { E.parseGS(r.formula); } catch (e) { S.parseFail++; const k = /<</.test(r.formula) ? '<<parameter>> pipe' : /\{/.test(r.formula) ? '{...} braces' : /\)\./.test(r.formula) ? 'field access after a call: f(x).y' : e.message.slice(0, 50); pf[k] = (pf[k] || 0) + 1; continue; }
  const h = E.holderFromText(r.kind, r.docs, r.formula);
  const raws = h.expr ? rawSrcs(h.expr, []) : [];
  const kinds = raws.map(cls);
  kinds.forEach(k => C[k] = (C[k] || 0) + 1);
  if (!raws.length) S.exact++;
  if (kinds.every(k => !k.startsWith('other') && k !== 'unparsed')) S.projected++;
  const back = E.cHolder(h).s;
  if (canon(back) === canon(r.formula)) S.rtSame++;
  else if (eqv(back, r.docs) === eqv(r.formula, r.docs)) S.rtEquiv++;
  else { S.rtDiff++; if (diffs.length < 20) diffs.push(r.docs + ': ' + r.formula + '   =>   ' + back); }
}
console.log(JSON.stringify(S));
console.log('parse failures:', JSON.stringify(pf));
console.log(Object.entries(C).sort((a, b) => b[1] - a[1]).map(([k, n]) => String(n).padStart(5) + '  ' + k).join('\n'));
console.log('-- real differences --\n' + diffs.join('\n'));
