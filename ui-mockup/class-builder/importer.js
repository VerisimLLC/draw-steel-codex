/* Opening saved records as blocks (the reverse of compile).

   Each block declares, next to its other settings in SENT:
     claims : the record fields it writes. Fields no block claims are kept untouched.
     read(m): turns a saved record into the block's fields, or null if it can't show it.
   A record is shown as a block only if writing the block back gives the same claimed fields
   (checked when the record is opened). Anything else becomes a grey "advanced" block that keeps
   the record as it is. Nothing here names an editor: adding a block means adding its claims and
   read beside it. */

const POWER_CLAIMS = ["modtype", "rollType", "keywords", "damageModifier", "damageModifierType", "potencymod", "surges", "surgesCanBeKept",
  "displayCondition", "activationCondition", "resourceCostType", "resourceCostAmount", "skills", "attribute", "rollRequirement", "surgeDamageType", "replaceText", "adjustments", "damageTypeMappings", "filterCondition"];
const kwList = k => Array.isArray(k) ? k.slice() : k && typeof k === "object" ? Object.keys(k).filter(x => k[x]) : [];
const scalar = v => v != null && (typeof v === "string" || typeof v === "number");
const make = (type, extra) => Object.assign(SENT[type].make(), extra);

/* The roll-option lines, read back ("Offered when" / "Automatically selected"). */
function readApplies(m, f) {
  const shown = String(m.displayCondition == null ? "" : m.displayCondition).trim();
  f.offer = shown ? { t: "raw", src: shown } : null;
  f.req = m.rollRequirement && m.rollRequirement !== "none" ? m.rollRequirement : "none";
  // A missing or empty activationCondition means never ticked (MCDModifyPowerRolls.lua hintPowerRoll).
  const a = m.activationCondition;
  if (m.resourceCostType && m.resourceCostType !== "none") { f.applies = actNorm(a) === "never" ? "choosecost" : "cost"; f.costRes = m.resourceCostType; f.costN = String(m.resourceCostAmount == null ? "1" : m.resourceCostAmount); }
  else if (a === true || a === 1 || a === "1") f.applies = "always";
  else if (a === false || a === undefined || a === "" || a === 0 || a === "0") f.applies = "choose";
  else { f.applies = "when"; f.tick = { t: "raw", src: String(a) }; }
  return f;
}
const EDGE_MODS = ["edge", "double_edge", "bane", "double_bane", "remove_bane", "remove_edge", "ignore_banes", "ignore_edges", "plusone", "plustwo", "plusthree", "minusone", "minustwo", "minusthree"];
const ON_OF = { test_power_roll: "tests", opposed_power_roll: "opposed", ability_power_roll: "abilities", all: "all" };
/* One power modifier can hold several parts (an edge, extra damage, potency, surges); several parts
   open as one combined block, as the claims rule decided. */
function readPower(m) {
  const kw = kwList(m.keywords);
  if (m.rollType === "enemy_ability_power_roll") return EDGE_MODS.includes(m.modtype) ? { type: "enemy", f: readApplies(m, make("enemy", { mod: m.modtype, keywords: kw })) } : null;
  // Roll other dice instead: stands alone, for tests or ability rolls.
  if (m.modtype === "replaceroll") { if (m.damageModifier || m.surges || m.potencymod || (m.adjustments || []).length) return null;
    const on = ON_OF[m.rollType]; if (!on) return null;
    return { type: "replaceRoll", f: readApplies(m, make("replaceRoll", { formula: String(m.replaceText || ""), on, attr: m.attribute && m.attribute !== "all" ? m.attribute : "", skills: kwList(m.skills), keywords: kw })) }; }
  if (m.rollType === "test_power_roll" || m.rollType === "opposed_power_roll") {
    const tests = { on: ON_OF[m.rollType], attr: m.attribute && m.attribute !== "all" ? m.attribute : "", skills: kwList(m.skills), keywords: [] };
    if (EDGE_MODS.includes(m.modtype)) return { type: "edge", f: readApplies(m, make("edge", Object.assign({ mod: m.modtype }, tests))) };
    if (OUTCOMES.some(o => o[0] === m.modtype)) return { type: "outcome", f: readApplies(m, make("outcome", Object.assign({ out: m.modtype }, tests))) };
    return null;
  }
  if (m.rollType !== "ability_power_roll") return null;
  // A damage type change stands alone (damageTypeMappings with one source type).
  if (m.damageTypeMappings && Object.keys(m.damageTypeMappings).length) { const ks = Object.keys(m.damageTypeMappings); if (ks.length !== 1 || m.rollType !== "ability_power_roll" || (m.modtype && m.modtype !== "none") || m.damageModifier || m.surges || (m.adjustments || []).length) return null;
    const v = m.damageTypeMappings[ks[0]];
    return { type: "dmgType", f: readApplies(m, make("dmgType", { from: ks[0], to: Array.isArray(v) ? v.slice() : [v], asText: !Array.isArray(v), keywords: kw })) }; }
  // A forced movement bonus stands alone.
  const adj = m.adjustments || [];
  if (adj.length) { if (m.rollType !== "ability_power_roll" || (m.modtype && m.modtype !== "none") || m.damageModifier || m.surges || m.potencymod || m.surgeDamageType) return null;
    if (adj.some(a => String(a.value) !== String(adj[0].value) || !FM_KINDS.some(k => k[0] === a.type))) return null;
    return { type: "moveBonus", f: readApplies(m, make("moveBonus", { kinds: adj.map(a => a.type), amount: String(adj[0].value), keywords: kw })) }; }
  // A surge damage type option stands alone (it is offered only when the roll already has surges).
  if (m.surgeDamageType) return m.modtype && m.modtype !== "none" || m.damageModifier || m.surges || m.potencymod ? null
    : { type: "surgeType", f: readApplies(m, make("surgeType", { dtype: m.surgeDamageType, keywords: kw })) };
  const parts = [];
  const attr = m.attribute && m.attribute !== "all" ? m.attribute : "";
  if (EDGE_MODS.includes(m.modtype)) parts.push({ type: "edge", f: make("edge", { mod: m.modtype, on: "abilities", attr, keywords: kw }) });
  else if (OUTCOMES.some(o => o[0] === m.modtype)) parts.push({ type: "outcome", f: make("outcome", { out: m.modtype, on: "abilities", attr, keywords: kw }) });
  else if (m.modtype && m.modtype !== "none") return null;
  const dm = m.damageModifier;
  if (dm != null && dm !== "") { if (!scalar(dm)) return null; parts.push({ type: "damage", f: make("damage", { amount: String(dm), dtype: m.damageModifierType && m.damageModifierType !== "none" ? m.damageModifierType : "", keywords: kw }) }); }
  const pm = m.potencymod;
  if (pm != null && pm !== "" && pm !== "none") { if (!/^-?\d+$/.test(String(pm))) return null; parts.push({ type: "potency", f: make("potency", { dir: +pm < 0 ? "down" : "up", n: String(Math.abs(+pm)), keywords: kw }) }); }
  const sg = m.surges;
  if (sg != null && sg !== "") { if (!scalar(sg)) return null; parts.push({ type: "surges", f: make("surges", { n: String(sg), keep: m.surgesCanBeKept ? "keep" : "roll", keywords: kw }) }); }
  if (!parts.length) return null;
  if (parts.length === 1) { readApplies(m, parts[0].f); return parts[0]; }
  if (parts.filter(p => p.type === "edge" || p.type === "outcome").length > 1) return null;
  return { type: "rollCombo", f: readApplies(m, make("rollCombo", { keywords: kw })), children: parts };
}
const READERS = {
  power: readPower,
  attribute: m => {
    if (!scalar(m.value)) return null;
    const op = m.operation || "add", v = String(m.value);
    if (op === "add" && +m.value === 1 && MOVES.some(x => x[0] === m.attribute)) return { type: "move", f: make("move", { mode: m.attribute }) };
    if (op === "add" && +m.value === 1 && CUSTOM_FLAGS.some(x => x[0] === m.attribute)) return { type: "flag", f: make("flag", { attr: m.attribute }) };
    if (!["add", "set", "max", "min"].includes(op)) return null;
    const neg = op === "add" && /^-\((.*)\)$/.exec(v);
    return { type: "stat", f: make("stat", { attr: m.attribute, op: neg ? "sub" : op, value: neg ? neg[1] : v }) };
  },
  resistance: m => {
    const r = m.resistances; if (!Array.isArray(r) || !r.length || r.some(e => e.apply !== "Damage Reduction" || !scalar(e.dr) || String(e.dr) !== String(r[0].dr))) return null;
    const kws = r.map(e => kwList(e.keywords).sort().join("|")); if (kws.some(k => k !== kws[0])) return null;
    const w = /^-\((.*)\)$/.exec(String(r[0].dr));
    return { type: "immunity", f: make("immunity", { dtypes: r.map(e => e.damageType), kind: w ? "weakness" : "immunity", amount: w ? w[1] : String(r[0].dr), keywords: kwList(r[0].keywords) }) };
  },
  forcedmovement: m => Array.isArray(m.movementTypes) && m.movementTypes.length ? { type: "moveSwap", f: make("moveSwap", { pairs: m.movementTypes.map(x => ({ from: x.from, to: x.to })) }) } : null,
  conditionimmunity: m => ({ type: "condImm", f: make("condImm", { conds: kwList(m.conditions) }) }),
  proficiency: m => m.subtype === "language" ? { type: "language", f: make("language", { ids: kwList(m.skills) }) }
    : m.subtype === "skill" ? { type: "skills", f: make("skills", { granted: kwList(m.skills), num: "0", groups: [], named: [] }) } : null,
  resource: m => scalar(m.num) ? { type: "resource", f: make("resource", { res: m.resourceType, num: String(m.num) }) } : null,
  kitaccess: m => ({ type: "kit", f: make("kit", { kitType: m.kitType }) }),
  activated: m => m.activatedAbility ? { type: "ability", f: make("ability", { rec: clone(m.activatedAbility), limit: m.resourceRefreshType || "none", uses: String(m.numCharges || "1") }) } : null,
  // Its "Only if" lives on the Logic block or growing-table row around it, not on the ability.
  trigger: m => { const rec = clone(m); delete rec.resourceRefreshType; delete rec.numCharges; delete rec.filterCondition; return { type: "trigger", f: make("trigger", { rec, limit: m.resourceRefreshType || "none", uses: String(m.numCharges || "1") }) }; },
  // A power roll trigger opens as the same "triggered ability" block; the ability editor saves either kind.
  powertabletrigger: m => READERS.trigger(m),
  // Wrappers: the children are the records inside; their own fields are checked here.
  aura: m => m.aura && scalar(m.radius) && AURA_WHO.some(w => w[0] === m.aura.applyto) ? { type: "aura", f: make("aura", { radius: String(m.radius), who: m.aura.applyto }), childMods: m.aura.modifiers || [] } : null,
  modcompanion: m => m.feature ? { type: "companionMods", f: make("companionMods", {}), childMods: m.feature.modifiers || [] } : null,
  modsummoner: m => m.feature ? { type: "summonerMods", f: make("summonerMods", {}), childMods: m.feature.modifiers || [] } : null,
  // Changing an ability: a stat change ("+2 distance") or added steps/text ("it also...").
  modifyability: m => {
    const at = m.attributes || [], steps = ((m.ability || {}).behaviors || []).length, name = abilityNameOf(m.filterAbility) || "";
    if (at.length === 1 && !steps && ["range", "numtargets", "modkeywords"].includes(at[0].id) && (at[0].operation || "Add") === "Add") {
      const kw = at[0].id === "modkeywords" ? kwList(at[0].keywords) : [];
      if (at[0].id === "modkeywords" && kw.length !== 1) return null;
      return { type: "modAbility", f: make("modAbility", { name, filter: m.filterAbility || "", keepAbility: true, change: at[0].id === "modkeywords" ? "keyword" : at[0].id, value: String(at[0].value), keyword: kw[0] || "Charge", text: m.modifyDescription || "" }) };
    }
    if (!at.length && m.ability && (steps || m.modifyDescription)) return { type: "abilityAddon", f: make("abilityAddon", { name, filter: m.filterAbility || "", rec: clone(m.ability), text: m.modifyDescription || "" }) };
    return null;
  },
  movementtext: m => ({ type: "reminder", f: make("reminder", { text: m.text || "", color: m.color || "white" }) }),
};
// What each block writes. Everything else on the saved record is kept as it was.
const CLAIMS = {
  stat: ["attribute", "operation", "value", "filterCondition"], move: ["attribute", "operation", "value", "filterCondition"], flag: ["attribute", "operation", "value", "filterCondition"],
  immunity: ["resistances", "filterCondition"], condImm: ["conditions", "filterCondition"], language: ["subtype", "proficiency", "equate", "skills", "filterCondition"],
  skills: ["subtype", "proficiency", "equate", "skills", "filterCondition"], resource: ["resourceType", "num", "filterCondition"], kit: ["kitType", "filterCondition"],
  ability: ["activatedAbility", "resourceRefreshType", "numCharges", "filterCondition"], reminder: ["text", "color", "filterCondition"],
  trigger: ["resourceRefreshType", "numCharges", "filterCondition"], surgeType: POWER_CLAIMS, dmgType: POWER_CLAIMS, modAbility: ["attributes", "filterAbility", "modifyDescription", "filterCondition"], abilityAddon: ["ability", "filterAbility", "modifyDescription", "filterCondition"], moveBonus: POWER_CLAIMS, replaceRoll: POWER_CLAIMS, moveSwap: ["movementTypes", "filterCondition"], edge: POWER_CLAIMS, enemy: POWER_CLAIMS, damage: POWER_CLAIMS, outcome: POWER_CLAIMS, potency: POWER_CLAIMS, surges: POWER_CLAIMS, rollCombo: POWER_CLAIMS,
};
CLAIMS.growing = ["progression"];
Object.keys(CLAIMS).forEach(t => { if (SENT[t]) SENT[t].claims = CLAIMS[t]; });

/* Grey blocks for records no block can show: they keep the record exactly and name its type. */
const REC_NAMES = { power: "Modify power rolls", aura: "Aura", forcedmovement: "Forced movement", triggerdisplay: "Triggered ability display", powertabletrigger: "Power roll trigger",
  growingresources: "Growing resources table", modifyability: "Modify an ability", trigger: "Triggered ability", attribute: "Change a stat", CharacterFeatureChoice: "Choice of features" };
const recKind = r => REC_NAMES[r.behavior || r.__typeName] || r.behavior || r.__typeName || "record";
SENT.advanced = { shelf: false, group: "adv", label: "Advanced", desc: "A saved record the blocks can't show yet.", make: () => ({ rec: null }), claims: ["filterCondition"],
  render: (f, add) => { add(E("span", "tag", recKind(f.rec || {}))); add(lbl(f.rec && f.rec.name ? f.rec.name : "")); add(E("span", "aside", "Make changes in the advanced editor")); },
  // Its "Only if" lives on the Logic block around it (see readModifiers), so the copy drops its own.
  prose: () => "", compile: f => { const r = clone(f.rec); delete r.filterCondition; return r; } };
SENT.advancedChoice = Object.assign({}, SENT.advanced, { choice: true, compile: undefined, compileChoice: f => clone(f.rec) });

/* Is the record really what this block would write? Compare the fields the block claims. */
const norm = v => {
  if (Array.isArray(v)) return v.every(x => typeof x === "string") ? v.slice().sort() : v.map(norm);
  if (v && typeof v === "object") { const ks = Object.keys(v); if (ks.length && ks.every(k => v[k] === true)) return ks.sort(); const o = {}; ks.sort().forEach(k => { if (v[k] !== undefined && !blank(v[k])) o[k] = norm(v[k]); }); return o; }
  if (typeof v === "string" && /^-?\d+$/.test(v.trim())) return +v;
  if (typeof v === "string") return v.trim().replace(/^\((.*)\)$/, "$1");
  return v;
};
const blank = v => v == null || (Array.isArray(v) && !v.length) || (v && typeof v === "object" && !Object.keys(v).length) || v === false || v === "";
const same = (a, b) => JSON.stringify(norm(blank(a) ? null : a)) === JSON.stringify(norm(blank(b) ? null : b));
// A saved record may leave a field out and rely on the engine's default (MCDModifyPowerRolls.lua).
const FIELD_DEFAULTS = { resourceCostAmount: "1", damageModifierType: "none", attribute: "all", operation: "add", resourceRefreshType: "none", numCharges: "1", rollRequirement: "none", resourceCostType: "none" };
// "Automatically selected": true, 1 and "1" are always; false, missing, "" and "0" are never.
const actNorm = v => v === true || v === 1 || v === "1" ? "always" : v === false || v == null || v === "" || v === 0 || v === "0" ? "never" : String(v).trim();
/* Two conditions are the same when they have the same "and" parts, ignoring letter case, spaces
   and order: GoblinScript names aren't case sensitive, and core content writes "level" or "Level". */
function condParts(c) {
  const t = String(c || "").toLowerCase().replace(/\s+/g, " ").trim(), parts = []; let depth = 0, start = 0;
  const strip = x => { x = x.trim(); while (/^\(.*\)$/.test(x) && balanced(x.slice(1, -1))) x = x.slice(1, -1).trim(); return x; };
  for (let i = 0; i < t.length; i++) { const ch = t[i]; if (ch === "(") depth++; else if (ch === ")") depth--;
    else if (depth === 0 && t.startsWith(" and ", i)) { parts.push(t.slice(start, i)); start = i + 5; i += 4; } }
  parts.push(t.slice(start));
  const flat = parts.map(strip); return flat.length === 1 && flat[0] !== t ? condParts(flat[0]) : flat.map(x => x.replace(/\s/g, "")).sort();
}
const balanced = x => { let d = 0; for (const ch of x) { if (ch === "(") d++; else if (ch === ")" && --d < 0) return false; } return d === 0; };
const sameCond = (a, b) => JSON.stringify(condParts(a)) === JSON.stringify(condParts(b));
/* Same meaning for one field (used to keep a saved spelling when a block is rebuilt). */
function sameMeaning(k, a, b) {
  if (k === "filterCondition") return sameCond(a, b);
  if (k === "activationCondition") return actNorm(a) === actNorm(b);
  return same(a === undefined || a === "" ? FIELD_DEFAULTS[k] : a, b === undefined || b === "" ? FIELD_DEFAULTS[k] : b);
}
function blockMatches(s, m, filter) {
  const saved = compileSrcMods; compileSrcMods = null;
  try {
    const out = compileSentences([s], { name: m.name || "", text: m.description || "" }, filter);
    if (!out.length) return false;
    const r = out[0]; delete r.name; delete r.description;
    const keys = new Set(Object.keys(r).concat((SENT[s.type].claims || []).filter(k => k !== "filterCondition" || filter)));
    return [...keys].every(k => k === "filterCondition" ? sameCond(r[k], m[k]) : k === "activationCondition" ? actNorm(r[k]) === actNorm(m[k]) : same(r[k] === undefined || r[k] === "" ? FIELD_DEFAULTS[k] : r[k], m[k] === undefined || m[k] === "" ? FIELD_DEFAULTS[k] : m[k]));
  } catch (e) { return false; } finally { compileSrcMods = saved; }
}
/* One record -> its block (with the filter it sits under), or a grey advanced block. */
function readOne(m, i, filter, stats) {
  let s = null; const r = READERS[m.behavior] && READERS[m.behavior](m);
  if (r && r.childMods) s = { id: newId("s"), type: r.type, f: r.f, children: readModifiers(r.childMods, stats) };
  else if (r) {
    s = { id: newId("s"), type: r.type, f: r.f, children: r.children ? r.children.map(c => ({ id: newId("s"), type: c.type, f: c.f })) : (SENT[r.type].wrapper ? [] : undefined) };
    if (!blockMatches(s, m, filter)) s = null;
  }
  if (!s) s = { id: newId("s"), type: "advanced", f: { rec: clone(m) } };
  // A trigger's card (Triggered Ability Display), wherever it sits in the feature, goes with it.
  const di = DISPLAY_FOR[i];
  if (s.type === "trigger" && di != null && DISPLAY_SRC) { s.f.display = clone(DISPLAY_SRC[di]); s.srcExtra = di; }
  stats[s.type === "advanced" ? "advanced" : "blocks"]++;
  if (s.type === "advanced") stats.advancedKinds[recKind(m)] = (stats.advancedKinds[recKind(m)] || 0) + 1;
  s.srcIdx = i; s.srcFilter = filter; s.snap = blockSnap(s);
  return s;
}
/* A growing table (growingresources) and the records whose condition is one of its rows' conditions.
   Rows that replace an earlier row are found by trying each later row as the replacer. */
function readGrowing(mods, gi, used, stats) {
  const g = mods[gi];
  const rows = (g.progression || []).map(p => ({ id: newId("r"), at: String(p.resources), level: String(+p.level > 1 ? p.level : 1), replaces: "", text: p.description || "", tooltip: p.tooltip || "", blocks: [] }));
  const later = r => rows.filter(x => x !== r && (+x.at > +r.at || (+x.at === +r.at && +x.level > +r.level)));
  mods.forEach((m, i) => {
    if (i === gi || used.has(i) || !m.filterCondition) return;
    for (const r of rows) {
      const tries = [null].concat(later(r).filter(x => !x.replaces || x.replaces === r.id));
      const hit = tries.find(x => { const saved = x && x.replaces; if (x) x.replaces = r.id; const ok = sameCond(growRowCond(rows, r), m.filterCondition); if (x && !ok) x.replaces = saved; return ok; });
      if (hit !== undefined) { used.add(i); r.blocks.push({ i, m }); return; }
    }
  });
  // Read the rows' records only now, once every row's condition (with its replacements) is known.
  rows.forEach(r => { r.blocks = r.blocks.map(({ i, m }) => { return readOne(m, i, "(" + growRowCond(rows, r) + ")", stats); }); r.snap = srcHash(r.blocks.map(b => b.f)); });
  const s = { id: newId("s"), type: "growing", f: { rows } }; stats.blocks++;
  s.srcIdx = gi; s.srcFilter = g.filterCondition ? "(" + g.filterCondition + ")" : undefined; s.snap = blockSnap(s);
  return s;
}
/* A feature's modifiers -> blocks. Records with the same "Only if" share one Logic block (decided). */
let DISPLAY_FOR = {}, DISPLAY_SRC = null;
/* Pairs each display record with its trigger: same name (or the display's ability name), else the
   nearest trigger before it that has no card yet. */
function pairDisplays(mods, used) {
  DISPLAY_FOR = {}; DISPLAY_SRC = mods; const taken = new Set();
  mods.forEach((d, di) => {
    if (d.behavior !== "triggerdisplay") return;
    const isTrig = m => m.behavior === "trigger" || m.behavior === "powertabletrigger";
    const nm = m => [m.name, m.triggeredAbility && m.triggeredAbility.name].filter(Boolean);
    let ti = mods.findIndex((m, i) => isTrig(m) && !taken.has(i) && nm(m).some(n => n === d.name || n === (d.ability && d.ability.name)));
    if (ti < 0) for (let i = di - 1; i >= 0; i--) if (isTrig(mods[i]) && !taken.has(i)) { ti = i; break; }
    if (ti >= 0) { taken.add(ti); DISPLAY_FOR[ti] = di; used.add(di); }
  });
}
function readModifiers(mods, stats) {
  const keepPairs = [DISPLAY_FOR, DISPLAY_SRC];
  try { return readModifierList(mods, stats); } finally { [DISPLAY_FOR, DISPLAY_SRC] = keepPairs; }
}
function readModifierList(mods, stats) {
  const out = []; let wrap = null; const used = new Set(), grow = {};
  pairDisplays(mods, used);
  mods.forEach((m, i) => { if (m.behavior === "growingresources") grow[i] = readGrowing(mods, i, used, stats); });
  mods.forEach((m, i) => {
    if (used.has(i)) return;
    if (grow[i]) { wrap = null; out.push(grow[i]); return; }
    const fc = String(m.filterCondition || "").trim();
    const s = readOne(m, i, fc ? "(" + fc + ")" : undefined, stats);
    if (fc) {
      if (!wrap || wrap.f.cond.src !== fc) { wrap = Object.assign(makeSentence("onlyIf"), { f: { cond: { t: "raw", src: fc } } }); out.push(wrap); }
      wrap.children.push(s);
    } else { wrap = null; out.push(s); }
  });
  return out;
}
/* Choice records -> choice blocks. */
const CHOICE_READERS = {
  CharacterDeityChoice: c => ({ type: "simpleChoice", f: make("simpleChoice", { typeName: c.__typeName, label: "Choose your deity" + (/domain/i.test(c.name || "") ? " and domains" : "") }) }),
  CharacterCompanionChoice: c => ({ type: "simpleChoice", f: make("simpleChoice", { typeName: c.__typeName, label: "Choose your companion" }) }),
  CharacterSubclassChoice: () => ({ type: "subclassChoice", f: make("subclassChoice", {}) }),
  CharacterFeatChoice: c => { const raw = String(c.tag || "").split(",").map(x => x.trim()), tags = raw.filter(x => x && x !== "feat");
    const groups = tags.map(t => Object.keys(PERK_TAGS).find(g => PERK_TAGS[g] === t)); if (groups.some(g => !g)) return null;
    return { type: "perkChoice", f: make("perkChoice", { num: String(c.numChoices || 1), groups, noTag: !c.tag, noFeatPrefix: !!c.tag && raw[0] !== "feat" }) }; },
  CharacterSkillChoice: c => { const cats = kwList(c.categories), named = kwList(c.individualSkills);
    const all = !named.length && SKILL_GROUPS.every(g => cats.includes(g)) && cats.length === SKILL_GROUPS.length;
    return { type: "skills", f: make("skills", { granted: [], num: String(c.numChoices || 1), groups: all ? [] : cats, named }) }; },
  CharacterFeatureChoice: c => {
    // Each option is one ability, or a triggered ability (its card, and any further records, kept).
    const option = o => { const ms = o.modifiers || [];
      if (ms.length === 1 && ms[0].behavior === "activated") return { rec: clone(ms[0].activatedAbility) };
      if (ms[0] && (ms[0].behavior === "trigger" || ms[0].behavior === "powertabletrigger")) { const d = ms.find(m => m.behavior === "triggerdisplay");
        return { rec: clone(ms[0]), display: d ? clone(d) : null, trig: true, extra: clone(ms.slice(1).filter(m => m !== d)) }; }
      return null; };
    const opts = (c.options || []).map(o => { const r = option(o); if (r) { r.src = clone(o); r.snap = optionSnap(r); } return r; });
    // Not all single abilities: each option is a small feature read like any other.
    if (!opts.length || opts.some(o => !o)) return (c.options || []).length ? { type: "optionChoice", f: make("optionChoice", { num: String(c.numChoices || 1), options: c.options.map(o => importFeature(o, CHOICE_STATS)) }) } : null;
    return { type: "abilityChoice", f: make("abilityChoice", { num: String(c.numChoices || 1), cat: /signature/i.test(c.name || "") ? "signature" : "heroic",
      // The cost comes from the options' own abilities (5 Ferocity...), else from a name like "9-Ferocity".
      cost: String((opts.find(o => o.rec && o.rec.resourceNumber != null) || { rec: {} }).rec.resourceNumber || (/(\d+)-/.exec(c.name || "") || [0, "3"])[1]), options: opts }) };
  },
};
let CHOICE_STATS = null;   // the stats a choice's options count into (set while a feature is read)
function readChoice(rec, stats) {
  const keep = CHOICE_STATS; CHOICE_STATS = stats;
  try { const r = CHOICE_READERS[rec.__typeName] && CHOICE_READERS[rec.__typeName](rec);
    stats[r ? "choices" : "advancedChoices"]++;
    return r ? { id: newId("s"), type: r.type, f: r.f } : { id: newId("s"), type: "advancedChoice", f: { rec: clone(rec) } }; } finally { CHOICE_STATS = keep; }
}
function importFeature(rec, stats) {
  const f = { id: newId("f"), kind: "feature", name: rec.name || "", text: rec.description || "", sentences: [] };
  if (rec.__typeName === "CharacterFeature") f.sentences = readModifiers(rec.modifiers || [], stats);
  else if (rec.__typeName === "CharacterFeatureList" && (rec.features || []).every(x => x.__typeName !== "CharacterFeatureList")) {
    // Plain features' modifiers, numbered in order as srcModsOf numbers them; each choice keeps its record.
    f.listRead = true; f.sentences = readModifiers(srcModsOf(rec), stats);
    (rec.features || []).filter(x => x.__typeName !== "CharacterFeature").forEach(x => { const s = readChoice(x, stats); s.choiceSrc = clone(x); s.snap = blockSnap(s); f.sentences.push(s); });
  }
  else {
    f.sentences = [readChoice(rec, stats)];
  }
  if (!f.sentences.length) stats.textOnly++;
  f.textBasis = autoText(f);
  f.src = rec; f.snap = srcHash({ n: f.name, t: f.text, s: f.sentences });
  return f;
}
function importLanes(levels, stats) {
  const lanes = {};
  Object.keys(levels || {}).forEach(k => { const fs = (levels[k] || {}).features || []; if (fs.length) lanes[k] = fs.map(x => importFeature(x, stats)); });
  return lanes;
}
const newStats = () => ({ blocks: 0, advanced: 0, choices: 0, advancedChoices: 0, textOnly: 0, advancedKinds: {} });
/* A whole class and its subclasses -> the builder's model. */
function importClassRecord(rec, subs) {
  const stats = newStats(), c = blankClass();
  const n = Object.keys(rec.baseCharacteristics || {}).filter(k => CHARS.some(x => x[0] === k));
  const hp = /^\s*(\d+)\s*\+\s*\(\s*Level\s*-\s*1\s*\)\s*\*\s*(\d+)\s*$/.exec(rec.hitpointsCalculation || "");
  Object.assign(c, { id: rec.id, name: rec.name, details: rec.details || "", resourceName: rec.heroicResourceName || "", epicName: rec.epicResourceName || "",
    primary: Object.fromEntries(n.map(k => [k, rec.baseCharacteristics[k]])), stamStart: hp ? hp[1] : "", stamPer: hp ? hp[2] : "",
    recoveries: "", kits: { on: "no", n: String(rec.numKits || 1), type: "martial" }, startGain: null, gains: [], hrRaw: clone(rec.heroicResourceChecklist || []),
    lanes: importLanes(rec.levels, stats), showLevels: 10, src: rec, view: null });
  c.slowStart = ENCOUNTERS.some(k => c.lanes[k]);
  const std = STD_ARRAYS[n.length] || STD_ARRAYS[1], arr = (rec.baseCharacteristics || {}).arrays;
  if (arr && JSON.stringify(arr) !== JSON.stringify(std)) { c.arrays = "custom"; c.arraysCustom = clone(arr); } else c.arrays = "auto";
  if (!hp) { c.stamStart = rec.hitpointsCalculation || ""; c.stamPer = ""; }
  readGains(c);   // falls back to the read-only checklist if the gains can't be paired up
  c.subclasses = (subs || []).map(s => { const st = newStats(); const sc = { id: s.id, name: s.name, details: s.details || "", lanes: importLanes(s.levels, st), showLevels: 10, src: s }; sc.stats = st; return sc; });
  c.importStats = stats;
  return c;
}
/* Open a core class from the compendium. An already-opened copy (with your changes) is reopened. */
function openCoreClass(id) {
  if (store.classes[id]) return openClass(id);
  const core = window.CB_CORE || { classes: [], subclasses: [] }, rec = core.classes.find(x => x.id === id); if (!rec) return;
  cls = importClassRecord(rec, core.subclasses.filter(x => x.primaryClassId === id));
  // Wording is generated against the open class, so the "text changed" check is set up now.
  [cls.lanes].concat(cls.subclasses.map(x => x.lanes)).forEach(l => Object.values(l).flat().forEach(f => { f.textBasis = autoText(f); }));
  undoStack = []; redoStack = []; openId = null; render(); saveStore();
  const st = cls.importStats, sub = cls.subclasses.reduce((a, x) => ({ b: a.b + x.stats.blocks, a: a.a + x.stats.advanced }), { b: 0, a: 0 });
  toast("Opened " + rec.name + ": " + (st.blocks + sub.b) + " records as blocks, " + (st.advanced + sub.a) + " in the advanced editor.");
}

/* Gaining the heroic resource. Core classes store each way as a checklist line on the class plus a
   trigger (with a Replenish step pointing at the line) in one of the class's features; the
   start-of-turn die size is an attribute modifier. Reading pairs them into the gain blocks, and the
   feature keeps a "gainRef" placeholder where each record sits, so an unchanged gain saves back
   exactly and an edited one updates its own records in place. */
const gainModel = g => g === cls.startGain || g.kind ? { k: g.kind, n: g.n, st: g.steps } : { e: g.event, q: g.qty, l: g.qtyLv || [], f: g.freq, w: g.who || "self", c: g.cond || null };
// (a "manual" line has no trigger, so it never counts as changed)
const gainChanged = g => g.event !== "manual" && (!g.src || srcHash(gainModel(g)) !== g.snap);
/* What changed in an opened gain since it was opened: its event, and/or its amount. */
function gainChanges(g) {
  const now = gainModel(g), was = (g.src && g.src.model0) || {};
  return { event: now.e !== was.e, freq: now.f !== was.f, who: now.w !== was.w, cond: JSON.stringify(now.c) !== JSON.stringify(was.c), amount: JSON.stringify(now.e !== undefined ? [now.q, now.l] : [now.k, now.n, now.st]) !== JSON.stringify(was.e !== undefined ? [was.q, was.l] : [was.k, was.n, was.st]) };
}
const findGain = guid => cls.startGain && cls.startGain.guid === guid ? cls.startGain : (cls.gains || []).find(x => x.guid === guid) || null;
const HR_START_RE = "\\(?\\s*Heroic Resource Gain at Start\\s*\\)?";
function readGains(c) {
  if (!c.hrRaw || !c.hrRaw.length) return false;
  const trig = {}, startAttrs = [];
  Object.keys(c.lanes).forEach(k => c.lanes[k].forEach(f => (srcModsOf(f.src) || []).forEach((m, idx) => {
    const b = m.behavior === "trigger" && ((m.triggeredAbility || {}).behaviors || []).find(x => x.__typeName === "ActivatedAbilityReplenishBehavior" && x.checklistid);
    if (b) trig[b.checklistid] = { f, idx, m, b };
    if (m.behavior === "attribute" && m.attribute === HR_START) startAttrs.push({ f, idx, m });
  })));
  /* The start-of-turn gain: a die (1d X, steps as table rows) or a set amount (steps as extra
     modifiers "Level >= N"), as compileStartGain writes them. Anything else is an ordinary gain line. */
  const readStart = (ck, t, src) => {
    const q = t.b.quantity, base = startAttrs.filter(a => !a.m.filterCondition), steps = startAttrs.filter(a => a.m.filterCondition);
    if (base.length !== 1) return null;
    const entries = q && q.__typeName === "GoblinScriptTable" ? q.entries.slice().sort((a, b) => a.threshold - b.threshold) : [{ threshold: 1, script: String(q) }];
    const first = String(entries[0].script).trim();
    if (new RegExp("^1d\\s*" + HR_START_RE + "$", "i").test(first) && !steps.length) {
      let prev = 0; const st = [];
      for (const e of entries.slice(1)) { const mm = new RegExp("^\\(?\\s*1d\\s*" + HR_START_RE + "\\s*\\)?\\s*\\+\\s*(\\d+)\\s*$", "i").exec(String(e.script).trim()); if (!mm) return null; st.push({ from: String(e.threshold), add: String(+mm[1] - prev) }); prev = +mm[1]; }
      return { kind: "die", n: String(base[0].m.value), steps: st, guid: ck.guid, src, refs: [[t, "trigger"], [base[0], "startAttr"]] };
    }
    if (new RegExp("^" + HR_START_RE + "$", "i").test(first) && entries.length === 1) {
      const st = steps.map(a => { const mm = /^\s*Level\s*>=\s*(\d+)\s*$/i.exec(a.m.filterCondition); return mm && scalar(a.m.value) ? { from: mm[1], add: String(a.m.value), ref: a } : null; });
      if (st.some(x => !x)) return null;
      return { kind: "flat", n: String(base[0].m.value), steps: st.map(x => ({ from: x.from, add: x.add })), guid: ck.guid, src, refs: [[t, "trigger"], [base[0], "startAttr"]].concat(st.map(x => [x.ref, "startStep"])) };
    }
    return null;
  };
  let start = null; const gains = [];
  for (const [order, ck] of c.hrRaw.entries()) {
    const t = trig[ck.guid], src = { check: ck, order };
    // A line with no trigger is applied by another feature: kept as saved, shown read-only.
    if (!t) { gains.push({ id: newId("g"), event: "manual", guid: ck.guid, src, refs: [] }); continue; }
    const ev = t.m.triggeredAbility.trigger, q = t.b.quantity !== undefined ? t.b.quantity : (ck.quantity !== undefined ? ck.quantity : "1");
    if (ev === "beginturn" && !start) { const st = readStart(ck, t, src); if (st) { start = st; continue; } }
    // How often (the line's mode), who sets it off (the trigger's subject) and its condition.
    const ta = t.m.triggeredAbility, fixed = (GAIN_TRIGGERS.find(x => x.id === ev) || {}).fixed;
    const g = { id: newId("g"), event: ev, guid: ck.guid, src, refs: [[t, "trigger"]], freq: ck.mode || (fixed ? "encounter" : "recurring"), who: ta.subject || "self",
      cond: String(ta.conditionFormula || "").trim() ? { t: "raw", src: String(ta.conditionFormula).trim() } : null };
    if (q && q.__typeName === "GoblinScriptTable") { const es = q.entries.slice().sort((a, b) => a.threshold - b.threshold); g.qty = String(es[0].script); g.qtyLv = es.slice(1).map(e => ({ from: String(e.threshold), value: String(e.script) })); }
    else g.qty = String(q);
    gains.push(g);
  }
  // Swap the records' blocks in their features for placeholders that point at the gain.
  // Only the feature's own records: Logic blocks share its numbering; wrappers and options number their own.
  const toRef = (ref, guid, kind) => (function walk(l) { l.forEach((s, i) => { if (s.srcIdx === ref.idx && s.type !== "onlyIf" && !s.choiceSrc && !SENT[s.type].choice) l[i] = { id: s.id, type: "gainRef", f: { guid, kind, idx: ref.idx }, srcIdx: ref.idx, srcFilter: s.srcFilter, snap: 0 };
    else if (s.type === "onlyIf") walk(s.children); else if (s.type === "growing") s.f.rows.forEach(r => walk(r.blocks)); }); })(ref.f.sentences);
  [start].concat(gains).filter(Boolean).forEach(g => g.refs.forEach(([ref, kind]) => toRef(ref, g.guid, kind)));
  [start].concat(gains).filter(Boolean).forEach(g => { delete g.refs; g.snap = srcHash(gainModel(g)); g.src.model0 = clone(gainModel(g)); });
  // Placeholders changed the features' blocks, so their "unchanged" marks are taken again.
  Object.values(c.lanes).flat().forEach(f => { f.snap = srcHash({ n: f.name, t: f.text, s: f.sentences }); });
  c.gainFeatId = ((Object.values(trig)[0] || {}).f || {}).id;   // where gains added later are written
  c.startGain = start; c.gains = gains; c.hrRaw = null; c.gainsImported = true;
  return true;
}
/* The record a placeholder writes: the saved one while its gain is unchanged, else that record
   updated from the gain (event, amount, prompt, how often), keeping everything else. */
function gainRefRecord(f) {
  const src = compileSrcMods && compileSrcMods[f.idx], g = findGain(f.guid);
  if (!g || !src) return null;
  if (!gainChanged(g)) return clone(src);
  const r = clone(src);
  if (f.kind === "startAttr") { if (String(cls.startGain.n) !== String(g.src.model0.n)) r.value = numOr(cls.startGain.n); return r; }
  if (f.kind === "startStep") return null;   // an edited start gain writes its level steps afresh (newGainRecords)
  const all = compileGains(), c2 = all.checklist.find(c => c.guid === g.guid), t2 = all.triggers.find(t => t.triggeredAbility.behaviors[0].checklistid === g.guid);
  const ta = r.triggeredAbility, rb = ta.behaviors.find(b => b.checklistid === g.guid), ch = gainChanges(g);
  if (ch.who) { if (g.who && g.who !== "self") ta.subject = g.who; else delete ta.subject; }
  if (ch.cond) { if (g.cond) ta.conditionFormula = testGs(g.cond); else ta.conditionFormula = ""; }
  if (ch.event || ch.who || ch.freq) ta.triggerPrompt = t2.triggeredAbility.triggerPrompt;
  if (ch.event) { ta.trigger = t2.triggeredAbility.trigger; ta.triggerPrompt = t2.triggeredAbility.triggerPrompt;
    if ("resourceRefreshType" in src) { if (c2.mode === "round" || c2.mode === "encounter") r.resourceRefreshType = c2.mode; else delete r.resourceRefreshType; } }
  if (ch.amount && rb) rb.quantity = g === cls.startGain ? clone(t2.triggeredAbility.behaviors[0].quantity) : clone(c2.quantity);
  return r;
}
/* The class's checklist: each gain's saved line while unchanged, else updated; new gains are added. */
function gainChecklist() {
  const all = compileGains();
  return [cls.startGain].concat(cls.gains).filter(Boolean).sort((a, b) => (a.src ? a.src.order : 1e9) - (b.src ? b.src.order : 1e9)).map(g => {
    const c2 = all.checklist.find(c => c.guid === g.guid);
    if (!g.src) return c2;
    if (!gainChanged(g)) return clone(g.src.check);
    // Only what changed: a new amount rewrites the amount and wording; a new event its wording and how often.
    const ch = gainChanges(g), out = clone(g.src.check);
    if (ch.amount) Object.assign(out, { details: c2.details, quantity: clone(c2.quantity) });
    if (ch.event || ch.who || ch.cond) Object.assign(out, { details: c2.details });
    if (ch.freq) Object.assign(out, { details: c2.details, mode: c2.mode });
    return out;
  });
}
/* Records for gains added after opening (no saved records yet): written into the feature that holds the others. */
function newGainRecords() {
  const all = compileGains(), fresh = [cls.startGain].concat(cls.gains).filter(g => g && !g.src);
  const out = [];
  fresh.forEach(g => { if (g === cls.startGain) out.push(...all.mods); out.push(all.triggers.find(t => t.triggeredAbility.behaviors[0].checklistid === g.guid)); });
  // An opened set-amount start gain that was edited: its level-step modifiers are written afresh.
  const sg = cls.startGain; if (sg && sg.src && sg.kind === "flat" && gainChanged(sg)) out.push(...all.mods.slice(1));
  return out.filter(Boolean);
}
const featureGainsChanged = f => (cls.gainsImported && f.id === cls.gainFeatId && newGainRecords().length) ||
  (function walk(l) { return l.some(s => (s.type === "gainRef" && (!findGain(s.f.guid) || gainChanged(findGain(s.f.guid)))) || (s.children && walk(s.children))); })(f.sentences);
SENT.gainRef = { shelf: false, group: "res", label: "Resource gain", noKeep: true, claims: [], make: () => ({ guid: "", kind: "trigger", idx: 0 }),
  render: (f, add) => { const g = findGain(f.guid);
    add(E("span", "tag", resWord())); add(lbl(!g ? "(removed)" : f.kind === "startAttr" ? "start-of-turn die size" : g === cls.startGain ? "start-of-turn gain" : ((GAIN_EVENTS.find(e => e[0] === g.event) || [0, g.event])[1])));
    add(E("span", "aside", "Edit it under “How you gain " + resWord() + "”")); },
  prose: () => "", compile: f => gainRefRecord(f) };
