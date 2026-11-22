/* Class Builder prototype.
   A class is a list of levels ("lanes"); each level holds features; a feature is a name, its book
   text, and what it does as sentence blocks. Sentences compile to the CharacterModifier records the
   engine stores. Abilities and triggered abilities open the simple ability editor (an iframe). */
"use strict";

// ---------------------------------------------------------------------------------------------
// Lookup tables (tables.js, built from the compendium by class-builder-data/build_data.py)
const T = window.CB_TABLES || { skills: [], languages: [], conditions: [], damageTypes: [], customAttributes: [], resources: [] };
const CHARS = [["mgt", "Might"], ["agl", "Agility"], ["rea", "Reason"], ["inu", "Intuition"], ["prs", "Presence"]];
const charName = id => (CHARS.find(c => c[0] === id) || [id, id])[1];
// Stats a sentence can change: characteristics, the common built-in stats, then the compendium's
// custom attributes (ids as content stores them).
const BUILTIN_STATS = [["hitpoints", "Stamina"], ["speed", "speed"], ["forcedmoveresistance", "stability"], ["recoveryvalue", "Recovery value"]];
const STAT_OPTS = CHARS.concat(BUILTIN_STATS);
const CUSTOM_FLAGS = T.customAttributes.filter(a => !/Class Specific|Hidden/i.test(a[2]));
const statName = id => (STAT_OPTS.find(s => s[0] === id) || T.customAttributes.find(a => a[0] === id) || [id, id])[1];
const MOVES = [["fly", "fly"], ["climb", "climb at full speed"], ["swim", "swim at full speed"], ["burrow", "burrow"]];
const KEYWORDS = ["Animal", "Area", "Charge", "Magic", "Melee", "Psionic", "Ranged", "Strike", "Weapon"];
const SKILL_GROUPS = ["crafting", "exploration", "interpersonal", "intrigue", "lore"];
const PERK_GROUPS = ["crafting", "exploration", "interpersonal", "intrigue", "lore", "supernatural"];
const RES = { heroic: "2d3d5511-4b80-46d1-a8c6-4705b9aa45ca", recovery: "5bd90f9b-46be-4cf2-8ca6-a96430d62949", surges: "8b0ae5fe-0eb3-45fa-9e6d-b9de68f5cc6d", epic: "e7b04a7e-61fc-4e17-b999-d95d7e751abb" };
const RESOURCE_OPTS = [[RES.recovery, "Recoveries"], [RES.surges, "surges"], [RES.epic, "epic resource"]];
const ACTION_NAMES = Object.fromEntries(T.resources.filter(r => r[2] === "Actions").map(r => [r[0], r[1]]));
const NUM_WORDS = ["zero", "one", "two", "three", "four", "five", "six"];
const word = n => NUM_WORDS[+n] || String(n);
const listWords = (a, conj = "or") => a.length <= 1 ? (a[0] || "") : a.slice(0, -1).join(", ") + " " + conj + " " + a[a.length - 1];
const lookupName = (tbl, id) => (tbl.find(r => r[0] === id) || [id, id])[1];

// ---------------------------------------------------------------------------------------------
// Small DOM helpers
const E = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };
let uid = 1;
const newId = p => (p || "x") + (uid++);
const guid = () => "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16); });
function toast(msg) {
  document.querySelectorAll(".toast").forEach(t => t.remove());
  const t = E("div", "toast", msg); document.body.appendChild(t); setTimeout(() => t.remove(), 3500);
}
let openMenu = null;
function closeMenu() { if (openMenu) { openMenu.remove(); openMenu = null; } }
document.addEventListener("click", ev => { if (openMenu && !openMenu.contains(ev.target)) closeMenu(); });
document.addEventListener("keydown", ev => { if (ev.key === "Escape") closeMenu(); });
/* A popup menu under an element. build(menu) fills it; it closes on outside click or Escape. */
function menuAt(el, build) {
  closeMenu();
  const m = E("div", "menu"); build(m);
  document.body.appendChild(m);
  const r = el.getBoundingClientRect();
  m.style.left = Math.max(8, Math.min(window.scrollX + r.left, window.scrollX + document.documentElement.clientWidth - m.offsetWidth - 8)) + "px";
  m.style.top = (window.scrollY + r.bottom + 4) + "px";
  openMenu = m; setTimeout(() => { const f = m.querySelector("input, button"); if (f) f.focus(); });
  return m;
}

// ---------------------------------------------------------------------------------------------
// Underlined values. Each opens one control; changes go through change() so undo and redraw happen.
function tok(text, onClick, empty) {
  const b = E("button", "tok" + (empty ? " empty" : ""), text); b.type = "button";
  b.addEventListener("click", ev => { ev.stopPropagation(); onClick(b); });
  return b;
}
/* Pick one of [value, label] options. */
function pickTok(obj, key, opts, empty) {
  const cur = opts.find(o => o[0] === obj[key]);
  return tok(cur ? cur[1] : (obj[key] || empty || "choose"), b => menuAt(b, m => {
    if (opts.length > 10) addFilter(m);
    opts.forEach(o => { const x = E("button", null, o[1]); x.type = "button"; x.addEventListener("click", () => { closeMenu(); change(() => { obj[key] = o[0]; }); }); m.appendChild(x); });
  }), !cur && !obj[key]);
}
/* Pick several of [value, label] options (stored as an array of values). */
function multiTok(obj, key, opts, emptyText, conj) {
  const sel = obj[key] || [];
  const names = sel.map(v => (opts.find(o => o[0] === v) || [v, v])[1]);
  return tok(names.length ? listWords(names, conj) : emptyText, b => menuAt(b, m => {
    if (opts.length > 10) addFilter(m);
    const box = E("div", "multi");
    opts.forEach(o => {
      const lb = E("label"); const cb = E("input"); cb.type = "checkbox"; cb.checked = sel.includes(o[0]);
      cb.addEventListener("change", () => change(() => { const s = new Set(obj[key] || []); cb.checked ? s.add(o[0]) : s.delete(o[0]); obj[key] = opts.map(x => x[0]).filter(v => s.has(v)); }, true));
      lb.appendChild(cb); lb.appendChild(document.createTextNode(o[1])); box.appendChild(lb);
    });
    m.appendChild(box);
  }), !names.length);
}
function addFilter(m) {
  const f = E("input", "filter"); f.placeholder = "Filter…"; m.appendChild(f);
  f.addEventListener("input", () => { const q = f.value.toLowerCase(); m.querySelectorAll("button, label").forEach(x => { x.style.display = x.textContent.toLowerCase().includes(q) ? "" : "none"; }); });
}
/* Free text or a number/formula, edited in place. */
function textTok(obj, key, placeholder, width) {
  const v = obj[key];
  return tok(v === "" || v == null ? placeholder : String(v), b => {
    const i = E("input", "edit-in"); i.value = v == null ? "" : v; i.placeholder = placeholder; i.style.width = (width || Math.max(4, String(v || placeholder).length + 2)) + "ch";
    b.replaceWith(i); i.focus(); i.select();
    let done = false;
    const commit = () => { if (done) return; done = true; change(() => { obj[key] = i.value.trim(); }); };
    i.addEventListener("blur", commit); i.addEventListener("keydown", e => { if (e.key === "Enter") commit(); if (e.key === "Escape") { done = true; render(); } });
  }, v === "" || v == null);
}
/* Ask before something big, in the page (browser confirm dialogs don't show in the artifact viewer). */
function askConfirm(el, question, yesText, onYes) {
  menuAt(el, m => { m.appendChild(E("div", "q", question)); const yn = E("div", "yn");
    const y = E("button", "btn primary", yesText); y.type = "button"; y.addEventListener("click", () => { closeMenu(); onYes(); });
    const n = E("button", "btn", "Cancel"); n.type = "button"; n.addEventListener("click", closeMenu);
    yn.appendChild(y); yn.appendChild(n); m.appendChild(yn); });
}
/* Copy text from a click (clipboard writes only work inside one); fall back to selecting it. */
function copyText(text, selectEl) {
  const fallback = () => { if (selectEl) { selectEl.focus(); if (selectEl.select) selectEl.select(); } toast("Press Ctrl+C (or Cmd+C) to copy the selected text."); };
  try { navigator.clipboard.writeText(text).then(() => toast("Copied."), fallback); } catch (e) { fallback(); }
}
const lbl = t => document.createTextNode(" " + t + " ");

// ---------------------------------------------------------------------------------------------
// Sentence blocks: what a feature does. Each one: shelf label, group, a book-style sentence with
// underlined values, and the CharacterModifier record it saves as.
const GROUPS = [["stats", "Stats", "--c-stats"], ["rolls", "Rolls", "--c-rolls"], ["def", "Defences", "--c-def"], ["abil", "Abilities", "--c-abil"],
  ["skill", "Skills and languages", "--c-skill"], ["res", "Resources and kits", "--c-res"], ["rem", "Reminders", "--c-rem"], ["if", "Only if", "--c-if"]];
const modBase = (feat, extra) => Object.assign({ __typeName: "CharacterModifier", name: feat.name, description: feat.text || "" }, extra);
const SENT = {
  stat: { label: "Change a stat", group: "stats", uses: 510, make: () => ({ attr: "hitpoints", op: "add", value: "3" }),
    render: (f, add) => {
      add(lbl("Your")); add(pickTok(f, "attr", STAT_OPTS.concat(CUSTOM_FLAGS.map(a => [a[0], a[1]]))));
      add(pickTok(f, "op", [["add", "increases by"], ["sub", "decreases by"], ["max", "increases to"], ["set", "is"], ["min", "can't go above"]]));
      add(textTok(f, "value", "number or formula"));
    },
    compile: (f, feat) => { const r = modBase(feat, { behavior: "attribute", attribute: f.attr, value: numOr(f.op === "sub" ? "-" + f.value : f.value) });
      if (f.op === "max" || f.op === "set" || f.op === "min") r.operation = f.op; return r; } },
  move: { label: "Movement type", group: "stats", uses: 12, make: () => ({ mode: "fly" }),
    render: (f, add) => { add(lbl("You can")); add(pickTok(f, "mode", MOVES)); },
    compile: (f, feat) => modBase(feat, { behavior: "attribute", attribute: f.mode, value: 1 }) },
  flag: { label: "You ignore / can't...", group: "stats", uses: 667, make: () => ({ attr: (CUSTOM_FLAGS.find(a => /Ignore Difficult Terrain/.test(a[1])) || CUSTOM_FLAGS[0] || [""])[0] }),
    render: (f, add) => { add(lbl("You have")); add(pickTok(f, "attr", CUSTOM_FLAGS.map(a => [a[0], a[1]]))); },
    compile: (f, feat) => modBase(feat, { behavior: "attribute", attribute: f.attr, value: 1 }) },
  edge: { label: "Edge or bane on rolls", group: "rolls", uses: 620, make: () => ({ mod: "edge", on: "tests", skills: [], keywords: [], applies: "always" }),
    render: (f, add) => {
      add(lbl("You have")); add(pickTok(f, "mod", [["edge", "an edge"], ["double_edge", "a double edge"], ["bane", "a bane"], ["double_bane", "a double bane"]]));
      add(lbl("on")); add(pickTok(f, "on", [["tests", "tests"], ["abilities", "ability rolls"]]));
      if (f.on === "tests") { add(lbl("using")); add(multiTok(f, "skills", T.skills.map(s => [s[0], s[1]]), "any skill")); }
      else { add(lbl("with")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "any keyword", "and")); }
      appliesPhrase(f, add);
    },
    compile: (f, feat) => modBase(feat, { behavior: "power", modtype: f.mod, rollType: f.on === "tests" ? "test_power_roll" : "ability_power_roll",
      keywords: f.on === "abilities" && f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [],
      skills: f.on === "tests" && f.skills.length ? f.skills.slice() : undefined, activationCondition: f.applies === "always", displayCondition: "" }) },
  enemy: { label: "Rolls against you", group: "rolls", uses: 252, make: () => ({ mod: "bane", keywords: [] }),
    render: (f, add) => { add(lbl("Abilities")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "of any kind", "and")); add(lbl("used against you have"));
      add(pickTok(f, "mod", [["bane", "a bane"], ["double_bane", "a double bane"], ["edge", "an edge"]])); },
    compile: (f, feat) => modBase(feat, { behavior: "power", modtype: f.mod, rollType: "enemy_ability_power_roll", keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [], activationCondition: true }) },
  damage: { label: "Extra damage", group: "rolls", uses: 208, make: () => ({ amount: "2", dtype: "", keywords: [], applies: "always" }),
    render: (f, add) => { add(lbl("Your")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "damaging", "and")); add(lbl("abilities deal"));
      add(textTok(f, "amount", "amount")); add(lbl("extra")); add(pickTok(f, "dtype", [["", "(untyped)"]].concat(T.damageTypes.map(d => [d, d])))); add(lbl("damage")); appliesPhrase(f, add); },
    compile: (f, feat) => { const r = modBase(feat, { behavior: "power", modtype: "none", rollType: "ability_power_roll", damageModifier: f.amount,
      keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [], activationCondition: f.applies === "always" });
      if (f.dtype) r.damageModifierType = f.dtype; return r; } },
  immunity: { label: "Immunity or weakness", group: "def", uses: 383, make: () => ({ dtype: "fire", kind: "immunity", amount: "5" }),
    render: (f, add) => { add(lbl("You have")); add(pickTok(f, "dtype", T.damageTypes.map(d => [d, d]).concat([["all", "damage"]]))); add(pickTok(f, "kind", [["immunity", "immunity"], ["weakness", "weakness"]])); add(textTok(f, "amount", "amount")); },
    // Weakness is saved as negative damage reduction: check against the engine before shipping.
    compile: (f, feat) => modBase(feat, { behavior: "resistance", resistances: [{ __typeName: "ResistanceEntry", apply: "Damage Reduction", damageType: f.dtype, dr: f.kind === "weakness" ? "-(" + f.amount + ")" : f.amount }] }) },
  condImm: { label: "Can't be (condition)", group: "def", uses: 65, make: () => ({ conds: [] }),
    render: (f, add) => { add(lbl("You can't be")); add(multiTok(f, "conds", T.conditions.map(c => [c[0], c[1].toLowerCase()]), "choose conditions")); },
    compile: (f, feat) => modBase(feat, { behavior: "conditionimmunity", conditions: f.conds.slice() }) },
  skill: { label: "You have a skill", group: "skill", uses: 36, make: () => ({ ids: [] }),
    render: (f, add) => { add(lbl("You have the")); add(multiTok(f, "ids", T.skills.map(s => [s[0], s[1]]), "choose skills", "and")); add(lbl(f.ids.length > 1 ? "skills" : "skill")); },
    compile: (f, feat) => modBase(feat, { behavior: "proficiency", subtype: "skill", proficiency: "proficient", equate: false, skills: Object.fromEntries(f.ids.map(i => [i, true])) }) },
  language: { label: "You know a language", group: "skill", uses: 4, make: () => ({ ids: [] }),
    render: (f, add) => { add(lbl("You know")); add(multiTok(f, "ids", T.languages.map(s => [s[0], s[1]]), "choose languages", "and")); },
    compile: (f, feat) => modBase(feat, { behavior: "proficiency", subtype: "language", proficiency: "proficient", equate: false, skills: Object.fromEntries(f.ids.map(i => [i, true])) }) },
  resource: { label: "Recoveries or a resource", group: "res", uses: 35, make: () => ({ res: RES.recovery, num: "8" }),
    render: (f, add) => { add(lbl("You have")); add(textTok(f, "num", "number")); add(pickTok(f, "res", RESOURCE_OPTS)); },
    compile: (f, feat) => modBase(feat, { behavior: "resource", resourceType: f.res, num: numOr(f.num) }) },
  kit: { label: "Kit", group: "res", uses: 10, make: () => ({ kitType: "martial" }),
    render: (f, add) => { add(lbl("You can use and gain the benefits of a")); add(pickTok(f, "kitType", [["martial", "martial"], ["caster", "caster"]])); add(lbl("kit")); },
    compile: (f, feat) => modBase(feat, { behavior: "kitaccess", kitType: f.kitType }) },
  ability: { label: "Gain an ability", group: "abil", uses: 1052, make: () => ({ rec: null }), opensEditor: "ability",
    render: (f, add, s, feat) => { add(lbl("You have the following ability")); add(abilityCards([{ rec: f.rec }], feat, (i, rec) => { f.rec = rec; }, null, s)); },
    compile: (f, feat) => f.rec ? modBase(feat, { behavior: "activated", name: "Ability", activatedAbility: f.rec }) : null },
  trigger: { label: "Gain a triggered ability", group: "abil", uses: 1727, make: () => ({ rec: null, display: null }), opensEditor: "triggered",
    render: (f, add, s, feat) => { add(lbl("You have the following triggered ability")); add(abilityCards([{ rec: f.rec, display: f.display, trig: true }], feat, (i, rec, display) => { f.rec = rec; f.display = display; }, null, s)); },
    compile: (f) => f.rec ? Object.assign({}, f.rec) : null, extra: f => f.display ? [f.display] : [] },
  modAbility: { label: "Change an ability", group: "abil", uses: 309, make: () => ({ name: "", change: "range", value: "2", keyword: "Charge" }),
    render: (f, add) => {
      add(lbl("Your")); add(abilityNameTok(f)); add(lbl("ability gains"));
      add(pickTok(f, "change", [["range", "+ distance"], ["numtargets", "+ targets"], ["keyword", "a keyword"]]));
      if (f.change === "keyword") add(pickTok(f, "keyword", KEYWORDS.map(k => [k, k]))); else add(textTok(f, "value", "amount"));
    },
    compile: (f, feat) => modBase(feat, { behavior: "modifyability", ability: { __typeName: "ActivatedAbility", name: "New Ability", abilityModification: true, behaviors: [] },
      attributes: f.change === "keyword" ? [{ id: "modkeywords", keywords: { [f.keyword]: true }, operation: "Add", value: "" }] : [{ id: f.change, operation: "Add", value: f.value }],
      filterAbility: 'Ability.name = "' + String(f.name).replace(/"/g, "") + '"' }) },
  reminder: { label: "Reminder text", group: "rem", uses: 89, make: () => ({ text: "" }),
    render: (f, add) => { add(lbl("Reminder:")); add(textTok(f, "text", "what players are reminded of", 40)); },
    compile: (f, feat) => modBase(feat, { behavior: "movementtext", text: f.text, color: "white" }) },
  onlyIf: { label: "Only if...", group: "if", uses: 720, make: () => ({ test: "victories", n: "5", formula: "" }), wrapper: true,
    render: (f, add) => { add(lbl("Only if")); add(pickTok(f, "test", ONLY_IF.map(t => [t[0], t[1]])));
      if (f.test === "victories" || f.test === "level") add(textTok(f, "n", "N")); if (f.test === "formula") add(textTok(f, "formula", "GoblinScript test", 30)); } },
};
const ONLY_IF = [["victories", "you have N or more Victories", f => "Victories >= " + (f.n || 0)], ["level", "you are level N or higher", f => "Level >= " + (f.n || 1)],
  ["winded", "you are winded", () => "Stamina <= Maximum Stamina / 2"], ["strained", "you are Strained", () => "Strained"], ["formula", "(a GoblinScript test)", f => f.formula || "1"]];
const numOr = v => /^-?\d+$/.test(String(v).trim()) ? +v : String(v).trim();
/* "always applies / you choose when you roll": one phrase in place of the engine's activation fields. */
function appliesPhrase(f, add) { add(lbl(",")); add(pickTok(f, "applies", [["always", "always applies"], ["choose", "you choose when you roll"]])); }
function abilityNameTok(f) {
  const names = allAbilityNames();
  return tok(f.name || "choose an ability", b => menuAt(b, m => {
    m.appendChild(E("h5", null, "Abilities in this class"));
    if (!names.length) m.appendChild(E("div", "hint", "No abilities yet. Type a name below."));
    names.forEach(n => { const x = E("button", null, n); x.type = "button"; x.addEventListener("click", () => { closeMenu(); change(() => { f.name = n; }); }); m.appendChild(x); });
    const i = E("input", "filter"); i.placeholder = "or type a name (e.g. Free Strike)"; i.value = f.name || "";
    i.addEventListener("keydown", e => { if (e.key === "Enter") { closeMenu(); change(() => { f.name = i.value.trim(); }); } }); m.appendChild(i);
    m.appendChild(E("div", "hint", "Saved by name for now; the engine change to save the ability's id is in the design brief."));
  }), !f.name);
}
function allAbilityNames() {
  const out = new Set();
  eachFeature(feat => {
    (feat.sentences || []).forEach(function walk(s) { if ((s.type === "ability" || s.type === "trigger") && s.f.rec) out.add(recName(s.f.rec)); (s.children || []).forEach(walk); });
    (feat.options || []).forEach(o => o.rec && out.add(recName(o.rec)));
  });
  return [...out];
}
const recName = rec => rec.__typeName === "CharacterModifier" ? ((rec.triggeredAbility || {}).name || rec.name) : rec.name;
function makeSentence(type) { const d = SENT[type]; return { id: newId("s"), type, f: d.make(), children: d.wrapper ? [] : undefined }; }

// ---------------------------------------------------------------------------------------------
// Features. "feature" is built from sentences; the rest are the ready-made shapes core classes repeat.
const FKINDS = {
  feature: "Feature", abilities: "Ability choice", skills: "Skills", perk: "Perk", subclass: "Subclass choice", charinc: "Characteristic Increase",
};
const READY = [
  { key: "perk", title: "Perk", uses: 54, desc: "One perk from [groups]", make: () => ({ kind: "perk", name: "Perk", groups: ["exploration", "interpersonal", "intrigue"] }) },
  { key: "skills", title: "Skills", uses: 69, desc: "[N] skills from [groups]", make: () => ({ kind: "skills", name: "Skills", num: "1", groups: SKILL_GROUPS.slice(), named: [] }) },
  { key: "charinc", title: "Characteristic Increase", uses: 33, desc: "Scores increase to [N]; choose another", make: () => ({ kind: "charinc", name: "Characteristic Increase", fixed: primaryChars().map(c => ({ attr: c, to: "3" })), num: "1", max: "3" }) },
  { key: "heroic", title: "Choose a heroic ability", uses: 45, desc: "One [N]-[resource] ability from [list]", make: () => ({ kind: "abilities", name: "", cat: "heroic", cost: "3", num: "1", options: [] }) },
  { key: "signature", title: "Signature ability", uses: 9, desc: "Choose one of [list]", make: () => ({ kind: "abilities", name: "Signature Ability", cat: "signature", cost: "", num: "1", options: [] }) },
  { key: "subclass", title: "Subclass choice", uses: 12, desc: "College, Circle, Domain...", make: () => ({ kind: "subclass", name: (cls.subclassWord || "Subclass") }) },
  { key: "kit", title: "Kit", uses: 7, desc: "Use a [martial] kit", make: () => feature("Kit", "You can use and gain the benefits of a kit.", ["kit"]) },
  { key: "recoveries", title: "Recoveries", uses: 11, desc: "You have [N] Recoveries", make: () => feature("Recoveries", "", ["resource"]) },
  { key: "languages", title: "Languages", uses: 6, desc: "You know [languages]", make: () => feature("Languages", "", ["language"]) },
  { key: "withability", title: "Feature with an ability", uses: 601, desc: "Name, text and an ability card", make: () => feature("", "", ["ability"]), opens: "ability" },
  { key: "withtrigger", title: "Feature with a triggered ability", uses: 220, desc: "Name, text and a trigger card", make: () => feature("", "", ["trigger"]), opens: "trigger" },
  { key: "empty", title: "Empty feature", uses: null, desc: "Name, text, then add sentences", make: () => feature("", "", []) },
];
function feature(name, text, types) { return { kind: "feature", name, text, sentences: types.map(makeSentence) }; }
function newFeature(tpl) { const f = tpl.make(); f.id = newId("f"); if (f.kind === "feature" && f.text == null) f.text = ""; if (f.text == null) f.text = ""; return f; }
const primaryChars = () => Object.keys(cls.primary || {}).length ? Object.keys(cls.primary) : ["mgt"];
function eachFeature(fn) { laneKeys().forEach(k => (cls.lanes[k] || []).forEach(f => fn(f, k))); }
function findFeature(id) { let r = null; eachFeature((f, k) => { if (f.id === id) r = { feat: f, lane: k }; }); return r; }

// Generated book text for ready-made features (used when the author hasn't written their own).
function autoText(f) {
  switch (f.kind) {
    case "perk": return "You gain one " + listWords(f.groups) + " perk of your choice.";
    case "skills": return "You gain " + word(f.num) + " skill" + (+f.num === 1 ? "" : "s") + (f.named.length ? " (" + listWords(f.named.map(i => lookupName(T.skills, i)), "and") + ")" : "") + " of your choice from the " + listWords(f.groups) + " skill groups.";
    case "charinc": return f.fixed.map(x => "Your " + charName(x.attr) + " score increases to " + x.to + ".").join(" ") + (+f.num > 0 ? " Additionally, you can increase " + word(f.num) + " of your characteristic scores by 1, to a maximum of " + f.max + "." : "");
    case "abilities": return f.cat === "signature" ? "Choose " + word(f.num) + " signature ability from the following options. Signature abilities can be used at will."
      : "Choose " + word(f.num) + " heroic ability from the following options, each of which costs " + f.cost + " " + (cls.resourceName || "heroic resource").toLowerCase() + " to use.";
    case "subclass": return "Choose your " + (f.name || "subclass") + ".";
    case "feature": return sentenceProse(f);
    default: return "";
  }
}
/* A sentence-built feature with no book text of its own reads as its sentences (ability cards are
   shown on their own, so those sentences are left out). */
function sentenceProse(f) {
  const out = [];
  (function walk(list, prefix) { list.forEach(s => {
    if (s.type === "onlyIf") { const t = ONLY_IF.find(x => x[0] === s.f.test); walk(s.children, "If " + t[1].replace(/\bN\b/, s.f.n || "N").replace(/^you are/, "you're").replace(/\(a GoblinScript test\)/, "a condition is met") + ", "); return; }
    if (s.type === "ability" || s.type === "trigger") return;
    const tmp = E("span"); SENT[s.type].render(s.f, n => tmp.appendChild(n), s, f);
    let t = tmp.textContent.replace(/\s+/g, " ").replace(/\s+([,.])/g, "$1").trim();
    if (prefix) t = prefix + t.charAt(0).toLowerCase() + t.slice(1);
    out.push(t.replace(/[.,]?$/, "."));
  }); })(f.sentences || [], "");
  return out.join(" ");
}
const featName = f => f.name || (f.kind === "abilities" && f.cat === "heroic" ? f.cost + "-" + (cls.resourceName || "Resource") + " Heroic Abilities" : "") || "Unnamed feature";
const featText = f => f.text || autoText(f);

// ---------------------------------------------------------------------------------------------
// The class model and its levels.
const GAIN_EVENTS = [["rollinitiative", "When combat starts", "encounter"], ["beginturn", "At the start of each of your turns", "round"],
  ["dealdamage", "The first time each round you deal damage", "round"], ["losehitpoints", "The first time each round you take damage", "round"],
  ["winded", "The first time you become winded in an encounter", "encounter"], ["dying", "The first time you become dying in an encounter", "encounter"],
  ["forcemove", "The first time each round you force move a creature", "round"], ["useability", "Whenever you use an ability", "recurring"]];
function blankClass() {
  return { id: guid(), name: "New Class", details: "", resourceName: "Resolve", epicName: "", subclassWord: "Subclass", slowStart: false,
    primary: { mgt: 2 }, arrays: "[2, -1, -1] [1, 1, -1] [1, 0, 0]", stamStart: "18", stamPer: "6", showLevels: 5,
    gains: [{ id: newId("g"), event: "rollinitiative", qty: "Victories", guid: guid() }, { id: newId("g"), event: "beginturn", qty: "2", guid: guid() }],
    lanes: {} };
}
const LEVELS = Array.from({ length: 10 }, (_, i) => "level-" + (i + 1));
const ENCOUNTERS = ["tutoriallevel-1", "tutoriallevel-2", "tutoriallevel-3", "tutoriallevel-4"];
const laneKeys = () => (cls.slowStart ? ENCOUNTERS : []).concat(LEVELS);
function laneLabel(k) {
  if (k.startsWith("tutorial")) return ["Encounter", k.slice(-1), ""];
  const n = +k.slice(6);
  if (n === 1 && cls.slowStart) return ["Level", "1", "after the slow start"];
  return ["Level", String(n), ""];
}
const ORD = n => n + (n % 10 === 1 && n !== 11 ? "st" : n % 10 === 2 && n !== 12 ? "nd" : n % 10 === 3 && n !== 13 ? "rd" : "th");

// ---------------------------------------------------------------------------------------------
// Compile: the class record as the engine stores it.
function compileSentences(list, feat, filter) {
  const out = [];
  for (const s of list) {
    if (s.type === "onlyIf") { const t = ONLY_IF.find(x => x[0] === s.f.test); out.push(...compileSentences(s.children, feat, (filter ? filter + " and " : "") + "(" + t[2](s.f) + ")")); continue; }
    const d = SENT[s.type]; const r = d.compile(s.f, feat); if (!r) continue;
    if (filter) r.filterCondition = r.filterCondition ? "(" + r.filterCondition + ") and " + filter : filter;
    Object.keys(r).forEach(k => r[k] === undefined && delete r[k]);
    out.push(r); if (d.extra) out.push(...d.extra(s.f));
  }
  return out;
}
function compileFeature(f) {
  const name = featName(f), description = featText(f), base = { name, description, classid: cls.id };
  switch (f.kind) {
    case "feature": return Object.assign({ __typeName: "CharacterFeature" }, base, { modifiers: compileSentences(f.sentences, { name, text: description }) });
    case "perk": return Object.assign({ __typeName: "CharacterFeatChoice" }, base, { tag: "feat," + f.groups.map(g => g + " perk").join(",") });
    case "skills": return Object.assign({ __typeName: "CharacterSkillChoice" }, base, { numChoices: +f.num || 1, categories: Object.fromEntries(f.groups.map(g => [g, true])), individualSkills: Object.fromEntries(f.named.map(i => [i, true])) });
    case "subclass": return Object.assign({ __typeName: "CharacterSubclassChoice" }, base);
    case "abilities": return Object.assign({ __typeName: "CharacterFeatureChoice" }, base, { numChoices: +f.num || 1, allowDuplicateChoices: false,
      options: f.options.filter(o => o.rec).map(o => ({ __typeName: "CharacterFeature", name: o.rec.name, description: "", tags: { Ability: true },
        modifiers: [{ __typeName: "CharacterModifier", behavior: "activated", name: "Ability", description: "", activatedAbility: o.rec }] })) });
    case "charinc": {
      // Stored the way core classes store it: one hidden feature per fixed score, plus a choice of +1.
      const fixed = f.fixed.map(x => ({ __typeName: "CharacterFeature", name: charName(x.attr), description: "Your " + charName(x.attr) + " is " + x.to + ".", tags: { Hidden: true },
        modifiers: [{ __typeName: "CharacterModifier", behavior: "attribute", name: charName(x.attr), description: "", attribute: x.attr, operation: "max", value: numOr(x.to) }] }));
      const parts = fixed.slice();
      if (+f.num > 0) parts.push({ __typeName: "CharacterFeatureChoice", name, description, numChoices: +f.num, allowDuplicateChoices: false,
        options: CHARS.filter(c => !f.fixed.some(x => x.attr === c[0])).map(c => ({ __typeName: "CharacterFeature", name: c[1], description: "", tags: { Hidden: true },
          modifiers: [{ __typeName: "CharacterModifier", behavior: "attribute", name: c[1], description: "", attribute: c[0], value: 1, cap: numOr(f.max) }] })) });
      return Object.assign({ __typeName: "CharacterFeatureList" }, base, { features: parts });
    }
  }
}
/* "How you gain your resource" writes two linked records, as decided: the checklist line players see,
   and the trigger that grants it (its Replenish step points at the line by checklistid). */
function compileGains() {
  const res = cls.resourceName || "Resource";
  const checklist = [], triggers = [];
  cls.gains.forEach(g => {
    const ev = GAIN_EVENTS.find(e => e[0] === g.event) || GAIN_EVENTS[0];
    const details = ev[1] + ", you gain " + g.qty + " " + res.toLowerCase() + ".";
    checklist.push({ name: ev[1], details, guid: g.guid, mode: ev[2], quantity: numOr(g.qty) });
    triggers.push({ __typeName: "CharacterModifier", behavior: "trigger", name: ev[1], description: details,
      triggeredAbility: { __typeName: "TriggeredAbility", name: ev[1], description: details, trigger: ev[0], targetType: "self", mandatory: "game:heroicresourcetriggers", triggerPrompt: ev[1] + ": gain " + res + ".",
        behaviors: [{ __typeName: "ActivatedAbilityReplenishBehavior", checklistid: g.guid, quantity: String(g.qty), resourceid: RES.heroic }] } });
  });
  return { checklist, triggers };
}
function compileClass() {
  const primary = Object.fromEntries(Object.keys(cls.primary).map(k => [k, numOr(cls.primary[k])]));
  let arrays = []; try { arrays = JSON.parse("[" + cls.arrays.replace(/\]\s*\[/g, "],[") + "]"); } catch (e) { arrays = cls.arrays; }
  const g = compileGains();
  const rec = { __typeName: "Class", id: cls.id, name: cls.name, details: cls.details, isSubclass: false,
    heroicResourceName: cls.resourceName, epicResourceName: cls.epicName || undefined,
    baseCharacteristics: Object.assign({}, primary, { arrays }), hitpointsCalculation: cls.stamStart + " + (Level - 1)*" + cls.stamPer,
    heroicResourceChecklist: g.checklist, levels: {} };
  const all = ENCOUNTERS.concat(Array.from({ length: 20 }, (_, i) => "level-" + (i + 1)));
  all.forEach(k => { rec.levels[k] = { __typeName: "ClassLevel", features: (laneKeys().includes(k) ? cls.lanes[k] || [] : []).map(compileFeature) }; });
  // The resource feature holds the gain triggers, in the first lane (as core classes do).
  const first = laneKeys()[0];
  rec.levels[first].features.unshift({ __typeName: "CharacterFeature", name: cls.resourceName || "Heroic Resource", classid: cls.id,
    description: g.checklist.map(c => c.details).join(" "), tags: { Hidden: true }, modifiers: g.triggers });
  Object.keys(rec).forEach(k => rec[k] === undefined && delete rec[k]);
  return rec;
}

// ---------------------------------------------------------------------------------------------
// State, undo, and the draft kept in this browser.
let cls = null, openId = null, showGs = false, sideTab = "book", undoStack = [];
const DRAFT_KEY = "classBuilderDraft";
function change(fn, keepMenu) {
  undoStack.push(JSON.stringify(cls)); if (undoStack.length > 80) undoStack.shift();
  fn(); if (!keepMenu) closeMenu(); render(); saveDraft();
}
function undo() { if (!undoStack.length) return toast("Nothing to undo."); cls = JSON.parse(undoStack.pop()); render(); saveDraft(); }
function saveDraft() { try { localStorage.setItem(DRAFT_KEY, JSON.stringify({ cls, uid })); } catch (e) {} }
function loadDraft() { try { const d = JSON.parse(localStorage.getItem(DRAFT_KEY) || "null"); if (d && d.cls && d.cls.lanes) { uid = Math.max(uid, d.uid || 1); return d.cls; } } catch (e) {} return null; }

// ---------------------------------------------------------------------------------------------
// The ability editor (simple ability editor in embedded mode). One iframe, reused.
const abModal = document.getElementById("abModal"), abFrame = document.getElementById("abFrame");
let abReady = false, abPending = null, abDone = null;
function openEditor(msg, done) {
  abDone = done; abModal.classList.add("open"); abModal.setAttribute("aria-hidden", "false");
  const m = Object.assign({ type: "cb-edit", owner: cls.name, resourceName: cls.resourceName }, msg);
  if (abReady) abFrame.contentWindow.postMessage(m, "*"); else abPending = m;
}
function closeEditor() { abModal.classList.remove("open"); abModal.setAttribute("aria-hidden", "true"); abDone = null; }
window.addEventListener("message", ev => {
  const m = ev.data || {};
  if (m.type === "cb-ready") { abReady = true; if (abPending) { abFrame.contentWindow.postMessage(abPending, "*"); abPending = null; } }
  else if (m.type === "cb-cancel") closeEditor();
  else if (m.type === "cb-done") {
    const done = abDone; closeEditor();
    if (done) change(() => done(m.rec, m.display));
    toast(m.problems && m.problems.length ? "Saved into the class. Still to finish: " + m.problems[0] : "Saved into the class.");
  }
});
/* A new ability starts as a small record so the editor opens with the class's own resource cost
   (heroic choices) or as a blank triggered ability. */
function abilitySeed(cat, cost) {
  if (cat !== "heroic") return null;
  return { __typeName: "ActivatedAbility", name: "New Heroic Ability", categorization: "Heroic Ability", resourceCost: RES.heroic, resourceNumber: numOr(cost || 3),
    actionResourceId: "d19658a2-4d7b-4504-af9e-1a5410fb17fd", targetType: "target", range: 1, numTargets: 1, keywords: {}, behaviors: [] };
}

// ---------------------------------------------------------------------------------------------
// Book-style cards for abilities (simplified from the ability editor's card).
function cardFor(rec, display, trig) {
  const c = E("div", "card" + (trig ? " trig" : ""));
  if (!rec) { c.appendChild(E("h4", null, trig ? "New triggered ability" : "New ability")); c.appendChild(E("div", null, "Click to build it in the ability editor.")); return c; }
  if (trig) {
    const ta = rec.triggeredAbility || rec.powerRollModifier || {}, d = display && display.ability || {};
    c.appendChild(E("h4", null, recName(rec)));
    if (d.flavor) c.appendChild(E("div", "fl", d.flavor));
    const kr = E("div", "kr"); kr.appendChild(E("span", null, Object.keys(ta.keywords || {}).join(", ") || "-")); kr.appendChild(E("span", null, actionName(ta.actionResourceId) || (rec.type === "free" ? "Free triggered action" : "Triggered action"))); c.appendChild(kr);
    const tr = E("div", "ef"); tr.innerHTML = "<b>Trigger:</b> "; tr.appendChild(document.createTextNode(d.trigger || rec.description || ta.triggerPrompt || ("When you " + (ta.trigger || "...")))); c.appendChild(tr);
    const ef = d.effect || ta.description || (ta.behaviors || []).map(b => b.rule || "").filter(Boolean).join("; ");
    if (ef) { const e = E("div", "ef"); e.innerHTML = "<b>Effect:</b> "; e.appendChild(document.createTextNode(String(ef).replace(/\{[^}|]*\|([^}]*)\}/g, "$1").replace(/[{}]/g, ""))); c.appendChild(e); }
    return c;
  }
  const cost = rec.resourceNumber ? " (" + rec.resourceNumber + " " + (cls.resourceName || "Resource") + ")" : "";
  c.appendChild(E("h4", null, rec.name + cost));
  if (rec.flavor) c.appendChild(E("div", "fl", rec.flavor));
  const kr = E("div", "kr"); kr.appendChild(E("span", null, Object.keys(rec.keywords || {}).filter(k => rec.keywords[k]).join(", ") || "-")); kr.appendChild(E("span", null, actionName(rec.actionResourceId) || "Main action")); c.appendChild(kr);
  const dr = E("div", "dr"); dr.appendChild(E("span", null, distanceText(rec))); dr.appendChild(E("span", null, targetText(rec))); c.appendChild(dr);
  const pr = (rec.behaviors || []).find(b => b.__typeName === "ActivatedAbilityPowerRollBehavior");
  if (pr) {
    c.appendChild(E("div", "pr", "Power Roll + " + String(pr.roll || "").replace(/^2d10\s*\+\s*/, "") + ":"));
    ["≤11", "12–16", "17+"].forEach((n, i) => { const r = E("div", "tr"); r.appendChild(E("span", "n", n)); r.appendChild(E("span", null, String((pr.tiers || [])[i] || "").replace(/#/g, ""))); c.appendChild(r); });
  }
  if (rec.description) { const e = E("div", "ef"); e.innerHTML = "<b>Effect:</b> "; e.appendChild(document.createTextNode(rec.description.replace(/\*\*([^*]+)\*\*/g, "$1"))); c.appendChild(e); }
  return c;
}
function actionName(id) { if (!id) return ""; const m = String(id).match(/^<(.+)>$/); return m ? m[1] : (ACTION_NAMES[id] || ""); }
function distanceText(r) {
  if (r.rangeTextOverride) return r.rangeTextOverride;
  const kw = r.keywords || {};
  switch (r.targetType) {
    case "self": return "Self";
    case "all": return (r.range || 1) + " burst";
    case "cube": return (r.radius || 1) + " cube within " + (r.range || 1);
    case "line": return (r.radius || 1) + " x " + (r.lineDistance || 1) + " line within 1";
    default: return (kw.Melee && !kw.Ranged ? "Melee " : kw.Ranged && !kw.Melee ? "Ranged " : "") + (r.range || 1);
  }
}
function targetText(r) {
  if (r.targetTextOverride) return r.targetTextOverride;
  if (r.targetType === "self") return "Self";
  if (["all", "cube", "line"].includes(r.targetType)) return "Each enemy in the area";
  const n = +r.numTargets || 1; return n === 1 ? "One creature" : word(n).replace(/^./, c => c.toUpperCase()) + " creatures";
}
/* Ability cards with Edit / Remove. items: [{rec, display, trig}]; setRec(i, rec, display) stores the result. */
function abilityCards(items, feat, setRec, onRemove, sent, seedFn) {
  const wrap = E("div", "cards");
  items.forEach((it, i) => {
    const cw = E("div", "cardwrap"); const card = cardFor(it.rec, it.display, it.trig);
    const edit = () => openEditor({ rec: it.rec || (seedFn ? seedFn() : null), display: it.display || null, kind: it.trig ? "triggered" : "ability" }, (rec, display) => setRec(i, rec, display));
    card.tabIndex = 0; card.title = "Edit in the ability editor"; card.addEventListener("click", edit); card.addEventListener("keydown", e => { if (e.key === "Enter") edit(); });
    cw.appendChild(card);
    const btns = E("div", "cbtns");
    const eb = E("button", "btn small", it.rec ? "Edit" : "Build it"); eb.type = "button"; eb.addEventListener("click", edit); btns.appendChild(eb);
    if (onRemove) { const rb = E("button", "btn small", "Remove"); rb.type = "button"; rb.addEventListener("click", () => change(() => onRemove(i))); btns.appendChild(rb); }
    cw.appendChild(btns); wrap.appendChild(cw);
  });
  wrap.style.flexBasis = "100%";
  return wrap;
}

// ---------------------------------------------------------------------------------------------
// Rendering: board, shelf, side.
const board = document.getElementById("board"), shelf = document.getElementById("shelf"), side = document.getElementById("side");
let compiled = null;
function render() {
  compiled = compileClass();
  renderBoard(); renderShelf(); renderSide();
  document.getElementById("showGs").checked = showGs;
}
function renderBoard() {
  const y = window.scrollY; board.innerHTML = "";
  const nm = E("div", "clsname");
  const ni = E("input"); ni.value = cls.name; ni.setAttribute("aria-label", "Class name");
  ni.addEventListener("change", () => change(() => { cls.name = ni.value.trim() || "New Class"; }));
  nm.appendChild(ni);
  const nb = E("button", "btn small", "New blank class"); nb.type = "button";
  nb.addEventListener("click", ev => { ev.stopPropagation(); askConfirm(nb, "Start a new blank class? Undo brings this one back.", "Start blank", () => change(() => { cls = blankClass(); openId = null; })); });
  nm.appendChild(nb); board.appendChild(nm);
  const det = E("textarea", "details"); det.placeholder = "The class's introduction, as the book prints it (optional)"; det.value = cls.details;
  det.addEventListener("change", () => change(() => { cls.details = det.value; })); board.appendChild(det);

  // Basics
  board.appendChild(E("h3", "sec", "Basics"));
  const b = E("div", "fixed");
  const row = (label, ...nodes) => { const r = E("div", "row"); r.appendChild(E("span", "lbl", label)); nodes.forEach(n => r.appendChild(n)); b.appendChild(r); };
  row("Characteristics", lbl("You start with"), multiTok({ get list() { return Object.keys(cls.primary); }, set list(v) { cls.primary = Object.fromEntries(v.map(k => [k, cls.primary[k] || 2])); } }, "list", CHARS, "choose", "and"),
    lbl("of 2; the other scores use one of these arrays:"), textTok(cls, "arrays", "[2, -1, -1] [1, 1, -1]", 30));
  row("Stamina", textTok(cls, "stamStart", "18"), lbl("at 1st level, plus"), textTok(cls, "stamPer", "6"), lbl("each level after"));
  row("Subclass", lbl("Subclasses are called"), textTok(cls, "subclassWord", "College, Circle, Domain..."));
  b.appendChild(E("p", "hint", "Recoveries, skills and kits are features: drag them in from the shelf (Recoveries, Skills, Kit)."));
  board.appendChild(b);

  // Heroic resource
  board.appendChild(E("h3", "sec", "Heroic resource"));
  const r = E("div", "fixed");
  const rr = E("div", "row"); rr.appendChild(E("span", "lbl", "Name")); rr.appendChild(textTok(cls, "resourceName", "e.g. Wrath")); rr.appendChild(lbl("epic resource")); rr.appendChild(textTok(cls, "epicName", "optional")); r.appendChild(rr);
  r.appendChild(E("div", "hint", "How you gain " + (cls.resourceName || "it").toLowerCase() + ":"));
  cls.gains.forEach((g, i) => {
    const line = E("div", "chk");
    const s = E("div"); s.appendChild(pickTok(g, "event", GAIN_EVENTS.map(e => [e[0], e[1]]))); s.appendChild(lbl(", you gain")); s.appendChild(textTok(g, "qty", "1"));
    s.appendChild(lbl((cls.resourceName || "resource").toLowerCase() + "."));
    line.appendChild(s);
    const x = E("button", "btn small", "Remove"); x.type = "button"; x.addEventListener("click", () => change(() => cls.gains.splice(i, 1))); line.appendChild(x);
    const ev = GAIN_EVENTS.find(e => e[0] === g.event) || GAIN_EVENTS[0];
    const l = E("div", "link"); l.innerHTML = "Writes the sheet's checklist line <b>and</b> the trigger that grants it (once per " + ({ round: "round", encounter: "encounter", recurring: "time" })[ev[2]] + "), linked so they can't disagree.";
    line.appendChild(l); r.appendChild(line);
  });
  const ag = E("button", "addsent", "+ add a way to gain " + (cls.resourceName || "it").toLowerCase()); ag.type = "button";
  ag.addEventListener("click", () => change(() => cls.gains.push({ id: newId("g"), event: "dealdamage", qty: "1", guid: guid() })));
  r.appendChild(ag); board.appendChild(r);

  // Levels
  const lh = E("div", "lanes-head");
  lh.appendChild(E("h3", "sec", "Levels"));
  const st = E("label", "toggle"); const cb = E("input"); cb.type = "checkbox"; cb.checked = cls.slowStart;
  const setSlow = () => {
    // Turning it on moves 1st-level features into Encounter 1 (where core classes keep them); the
    // "1st level, after the slow start" lane is for what a hero gets once the slow start is over.
    change(() => { cls.slowStart = cb.checked; if (cls.slowStart) { cls.lanes["tutoriallevel-1"] = (cls.lanes["tutoriallevel-1"] || []).concat(cls.lanes["level-1"] || []); cls.lanes["level-1"] = []; }
      if (!cls.slowStart) { const moved = ENCOUNTERS.flatMap(k => cls.lanes[k] || []); ENCOUNTERS.forEach(k => delete cls.lanes[k]); cls.lanes["level-1"] = moved.concat(cls.lanes["level-1"] || []); } });
  };
  cb.addEventListener("change", () => {
    if (!cb.checked && ENCOUNTERS.some(k => (cls.lanes[k] || []).length)) { cb.checked = true;
      setTimeout(() => askConfirm(st, "Turn off the slow start rules? Features in Encounters 1\u20134 move into 1st level.", "Turn off", () => { cb.checked = false; setSlow(); }));
      return; }
    setSlow();
  });
  st.appendChild(cb); st.appendChild(document.createTextNode("Uses the slow start rules (Encounters 1–4)")); lh.appendChild(st);
  board.appendChild(lh);
  const keys = laneKeys(); let shown = 0;
  keys.forEach(k => {
    const isLevel = k.startsWith("level-"); const n = isLevel ? +k.slice(6) : 0;
    if (isLevel && n > cls.showLevels && !(cls.lanes[k] || []).length) return;
    shown++; board.appendChild(renderLane(k));
  });
  if (cls.showLevels < 10) {
    const more = E("button", "collapsed-note", "Levels " + (cls.showLevels + 1) + "–10 collapsed · click to show the next level"); more.type = "button";
    more.addEventListener("click", () => change(() => { cls.showLevels = Math.min(10, cls.showLevels + 1); })); board.appendChild(more);
  }
  window.scrollTo(0, y);
}
function renderLane(k) {
  const lane = E("div", "lane"); lane.dataset.lane = k;
  const [a, n, sub] = laneLabel(k);
  const ln = E("div", "ln", a); ln.appendChild(E("b", null, n)); if (sub) ln.appendChild(E("small", null, sub)); lane.appendChild(ln);
  const items = E("div", "items");
  (cls.lanes[k] || []).forEach(f => items.appendChild(f.id === openId ? renderFeature(f, k) : chip(f, k)));
  const add = E("button", "addf", "+ add a feature"); add.type = "button";
  add.addEventListener("click", ev => { ev.stopPropagation(); menuAt(add, m => READY.forEach(t => { const x = E("button", null, t.title); x.type = "button"; x.addEventListener("click", () => { closeMenu(); addFeature(t, k); }); m.appendChild(x); })); });
  items.appendChild(add); lane.appendChild(items);
  // Drop target for shelf items and for features dragged from another level.
  lane.addEventListener("dragover", ev => { if (dragData && dragData.kind !== "sentence") { ev.preventDefault(); lane.classList.add("drop"); } });
  lane.addEventListener("dragleave", ev => { if (!lane.contains(ev.relatedTarget)) lane.classList.remove("drop"); });
  lane.addEventListener("drop", ev => { ev.preventDefault(); lane.classList.remove("drop"); const d = dragData; dragData = null; if (!d) return;
    if (d.kind === "ready") addFeature(READY.find(t => t.key === d.key), k);
    else if (d.kind === "feature") change(() => { const at = findFeature(d.id); if (!at) return; cls.lanes[at.lane] = cls.lanes[at.lane].filter(x => x !== at.feat); (cls.lanes[k] = cls.lanes[k] || []).push(at.feat); }); });
  return lane;
}
function chip(f, k) {
  const c = E("button", "chip"); c.type = "button"; c.draggable = true;
  c.appendChild(E("span", "kind", FKINDS[f.kind] || "Feature")); c.appendChild(E("span", "nm", featName(f)));
  c.title = featText(f) || "Click to open";
  c.addEventListener("click", () => { openId = f.id; render(); });
  c.addEventListener("dragstart", ev => { dragData = { kind: "feature", id: f.id }; ev.dataTransfer.setData("text/plain", f.id); c.classList.add("dragging"); });
  c.addEventListener("dragend", () => c.classList.remove("dragging"));
  return c;
}
function addFeature(tpl, laneKey) {
  const f = newFeature(tpl);
  change(() => { (cls.lanes[laneKey] = cls.lanes[laneKey] || []).push(f); openId = f.id;
    if (laneKey.startsWith("level-") && +laneKey.slice(6) > cls.showLevels) cls.showLevels = +laneKey.slice(6); });
  // Features made around an ability go straight to the ability editor.
  if (tpl.opens) { const s = f.sentences[0]; openEditor({ rec: null, kind: tpl.opens === "trigger" ? "triggered" : "ability" }, (rec, display) => { s.f.rec = rec; if (display !== undefined) s.f.display = display; if (!f.name && rec) f.name = recName(rec); }); }
}
let dragData = null;

function renderFeature(f, laneKey) {
  const box = E("div", "feat");
  const head = E("div", "feat-head");
  head.appendChild(E("span", "kind", FKINDS[f.kind]));
  const nin = E("input", "fname"); nin.value = f.name; nin.placeholder = featName(f) === "Unnamed feature" ? "Feature name" : featName(f); nin.setAttribute("aria-label", "Feature name");
  nin.addEventListener("change", () => change(() => { f.name = nin.value.trim(); })); head.appendChild(nin);
  const close = E("button", "btn small", "Close"); close.type = "button"; close.addEventListener("click", () => { openId = null; render(); }); head.appendChild(close);
  box.appendChild(head);
  const ta = E("textarea", "ftext"); ta.value = f.text; ta.placeholder = autoText(f) || "The feature's text, as the book prints it";
  ta.addEventListener("change", () => change(() => { f.text = ta.value; })); box.appendChild(ta);
  if (!f.text && autoText(f)) box.appendChild(E("div", "hint", "The book text above is written from the sentences below until you type your own."));
  box.appendChild(E("div", "lbl2", f.kind === "feature" ? "What it does" : "Settings"));
  const sents = E("div", "sents");
  if (f.kind === "feature") {
    renderSentenceList(f.sentences, f, sents);
    const add = E("button", "addsent", "+ add what it does"); add.type = "button";
    add.addEventListener("click", ev => { ev.stopPropagation(); sentenceMenu(add, type => addSentence(f, f.sentences, type)); });
    sents.appendChild(add);
    sents.addEventListener("dragover", ev => { if (dragData && dragData.kind === "sentence") { ev.preventDefault(); sents.classList.add("drop-target"); } });
    sents.addEventListener("drop", ev => { ev.preventDefault(); const d = dragData; dragData = null; if (d && d.kind === "sentence") addSentence(f, f.sentences, d.type); });
  } else renderReadyBody(f, sents);
  box.appendChild(sents);
  const foot = E("div", "feat-foot");
  const lanes = laneKeys();
  const mv = E("button", "btn small", "Move to…"); mv.type = "button";
  mv.addEventListener("click", ev => { ev.stopPropagation(); menuAt(mv, m => lanes.forEach(k => { const [a, n, sub] = laneLabel(k); const x = E("button", null, a + " " + n + (sub ? " (" + sub + ")" : "")); x.type = "button";
    x.addEventListener("click", () => change(() => { cls.lanes[laneKey] = cls.lanes[laneKey].filter(y => y !== f); (cls.lanes[k] = cls.lanes[k] || []).push(f); if (k.startsWith("level-") && +k.slice(6) > cls.showLevels) cls.showLevels = +k.slice(6); })); m.appendChild(x); })); });
  foot.appendChild(mv);
  const dup = E("button", "btn small", "Duplicate"); dup.type = "button";
  dup.addEventListener("click", () => change(() => { const c = JSON.parse(JSON.stringify(f)); c.id = newId("f"); JSON.stringify(c, (k, v) => { if (v && typeof v === "object" && typeof v.id === "string" && /^s\d+$/.test(v.id)) v.id = newId("s"); return v; }); cls.lanes[laneKey].push(c); openId = c.id; }));
  foot.appendChild(dup);
  const del = E("button", "btn small", "Delete"); del.type = "button";
  del.addEventListener("click", () => change(() => { cls.lanes[laneKey] = cls.lanes[laneKey].filter(y => y !== f); openId = null; }));
  foot.appendChild(del);
  foot.appendChild(E("span", "spacer"));
  const fl = E("button", "btn small", "Saved data"); fl.type = "button"; fl.addEventListener("click", () => { sideTab = "saved"; renderSide(); side.scrollIntoView({ block: "start" }); });
  foot.appendChild(fl);
  box.appendChild(foot);
  return box;
}
function addSentence(feat, list, type) {
  const s = makeSentence(type);
  change(() => list.push(s));
  const d = SENT[type];
  if (d.opensEditor) openEditor({ rec: null, kind: d.opensEditor }, (rec, display) => { s.f.rec = rec; if (display !== undefined) s.f.display = display; if (!feat.name && rec) feat.name = recName(rec); });
}
function sentenceMenu(el, pick, noWrapper) {
  menuAt(el, m => GROUPS.forEach(g => {
    const types = Object.keys(SENT).filter(t => SENT[t].group === g[0] && !(noWrapper && SENT[t].wrapper)); if (!types.length) return;
    m.appendChild(E("h5", null, g[1]));
    types.forEach(t => { const x = E("button", null, SENT[t].label); x.type = "button"; x.addEventListener("click", () => { closeMenu(); pick(t); }); m.appendChild(x); });
  }));
}
function renderSentenceList(list, feat, into) {
  list.forEach((s, i) => into.appendChild(renderSentence(s, list, i, feat)));
}
function renderSentence(s, list, i, feat) {
  const d = SENT[s.type]; const g = GROUPS.find(x => x[0] === d.group);
  const el = E("div", "sent" + (d.wrapper ? " ifwrap" : "")); el.style.setProperty("--c", "var(" + g[2] + ")");
  const line = d.wrapper ? E("div", "ifline") : el;
  const add = n => line.appendChild(n);
  d.render(s.f, add, s, feat);
  const grow = E("span", "grow"); line.appendChild(grow);
  const mb = E("button", "mb", "⋯"); mb.type = "button"; mb.setAttribute("aria-label", d.label + " options");
  mb.addEventListener("click", ev => { ev.stopPropagation(); menuAt(mb, m => {
    const item = (t, fn) => { const x = E("button", null, t); x.type = "button"; x.addEventListener("click", () => { closeMenu(); change(fn); }); m.appendChild(x); };
    if (i > 0) item("Move up", () => { [list[i - 1], list[i]] = [list[i], list[i - 1]]; });
    if (i < list.length - 1) item("Move down", () => { [list[i + 1], list[i]] = [list[i], list[i + 1]]; });
    if (!d.wrapper) item("Wrap in “Only if…”", () => { const w = makeSentence("onlyIf"); w.children.push(s); list.splice(i, 1, w); });
    if (d.wrapper) item("Remove the “Only if” (keep what's inside)", () => { list.splice(i, 1, ...s.children); });
    item("Delete", () => { list.splice(i, 1); });
  }); });
  line.appendChild(mb);
  if (d.wrapper) {
    el.appendChild(line);
    const body = E("div", "ifbody"); renderSentenceList(s.children, feat, body);
    const add2 = E("button", "addsent", "+ add inside"); add2.type = "button";
    add2.addEventListener("click", ev => { ev.stopPropagation(); sentenceMenu(add2, type => addSentence(feat, s.children, type), true); });
    body.appendChild(add2); el.appendChild(body);
  } else if (showGs) {
    const recs = compileSentences([s], { name: featName(feat), text: featText(feat) });
    el.appendChild(E("div", "saves", recs.length ? recs.map(savesLine).join("\n") : "(nothing saved yet)"));
  }
  return el;
}
/* "saves as attribute: hitpoints, value 3": the record's behaviour and its interesting fields. */
function savesLine(r) {
  const skip = new Set(["__typeName", "name", "description", "behavior", "activatedAbility", "triggeredAbility", "ability"]);
  const parts = Object.keys(r).filter(k => !skip.has(k)).map(k => k + " " + JSON.stringify(r[k]).slice(0, 80));
  return "saves as " + (r.behavior || r.__typeName) + (parts.length ? ": " + parts.join(", ") : "");
}
/* Settings for ready-made features, as sentences. */
function renderReadyBody(f, into) {
  const S = (...nodes) => { const el = E("div", "sent"); el.style.setProperty("--c", "var(--c-skill)"); nodes.forEach(n => el.appendChild(n)); into.appendChild(el); return el; };
  switch (f.kind) {
    case "perk": S(lbl("You gain one"), multiTok(f, "groups", PERK_GROUPS.map(g => [g, g]), "any", "or"), lbl("perk of your choice")); break;
    case "skills": S(lbl("You gain"), textTok(f, "num", "1"), lbl("skill(s) of your choice from the"), multiTok(f, "groups", SKILL_GROUPS.map(g => [g, g]), "no", "or"), lbl("skill groups"));
      S(lbl("or these named skills:"), multiTok(f, "named", T.skills.map(s => [s[0], s[1]]), "none", "and")); break;
    case "subclass": { const el = S(lbl("The player chooses their"), textTok(f, "name", cls.subclassWord || "subclass"));
      el.appendChild(E("span", "hint", " (the subclasses themselves are made in the subclass editor)")); break; }
    case "charinc": {
      f.fixed.forEach((x, i) => { const el = S(lbl("Your"), pickTok(x, "attr", CHARS), lbl("score increases to"), textTok(x, "to", "3"));
        const rm = E("button", "mb", "✕"); rm.type = "button"; rm.title = "Remove"; rm.addEventListener("click", () => change(() => f.fixed.splice(i, 1))); el.appendChild(E("span", "grow")); el.appendChild(rm); });
      const a = E("button", "addsent", "+ another score that increases"); a.type = "button"; a.addEventListener("click", () => change(() => f.fixed.push({ attr: "agl", to: "3" }))); into.appendChild(a);
      S(lbl("Additionally, you can increase"), textTok(f, "num", "1"), lbl("other characteristic score(s) by 1, to a maximum of"), textTok(f, "max", "3"));
      break;
    }
    case "abilities": {
      const el = S(lbl("Choose"), textTok(f, "num", "1"), lbl("of these " + (f.cat === "signature" ? "signature abilities" : "heroic abilities")));
      if (f.cat === "heroic") { el.appendChild(lbl(", each costing")); el.appendChild(textTok(f, "cost", "3")); el.appendChild(lbl((cls.resourceName || "resource").toLowerCase())); }
      into.appendChild(abilityCards(f.options.map(o => ({ rec: o.rec })), f, (i, rec) => { f.options[i].rec = rec; }, i => f.options.splice(i, 1), null, () => abilitySeed(f.cat, f.cost)));
      const add = E("button", "addsent", "+ new ability to choose from"); add.type = "button";
      add.addEventListener("click", () => { const o = { id: newId("o"), rec: null }; change(() => f.options.push(o));
        openEditor({ rec: abilitySeed(f.cat, f.cost), kind: "ability" }, rec => { o.rec = rec; }); });
      into.appendChild(add);
      break;
    }
  }
}

function renderShelf() {
  const q = (shelf.querySelector("input.search") || {}).value || "";
  shelf.innerHTML = "";
  const s = E("input", "search"); s.placeholder = "Search features and sentences ( / )"; s.value = q; s.setAttribute("aria-label", "Search the shelf");
  s.addEventListener("input", () => { const pos = s.selectionStart; renderShelf(); const n = shelf.querySelector("input.search"); n.focus(); n.setSelectionRange(pos, pos); });
  shelf.appendChild(s);
  const match = t => !q || t.toLowerCase().includes(q.toLowerCase());
  const h = E("h4"); h.appendChild(E("span", null, "Ready-made features")); h.appendChild(E("span", null, "uses")); shelf.appendChild(h);
  shelf.appendChild(E("p", "hint", "Drag onto a level, or click to add to the open feature's level."));
  READY.filter(t => match(t.title + " " + t.desc)).forEach(t => {
    const b = E("button", "rm"); b.type = "button"; b.draggable = true;
    const tt = E("div", "t"); tt.appendChild(document.createTextNode(t.title)); if (t.uses) tt.appendChild(E("span", null, String(t.uses))); b.appendChild(tt);
    b.appendChild(E("div", "d", t.desc));
    b.addEventListener("dragstart", ev => { dragData = { kind: "ready", key: t.key }; ev.dataTransfer.setData("text/plain", t.key); });
    b.addEventListener("click", () => { const at = openId && findFeature(openId); addFeature(t, at ? at.lane : laneKeys()[0]); });
    shelf.appendChild(b);
  });
  const at = openId && findFeature(openId);
  const canAdd = at && at.feat.kind === "feature";
  shelf.appendChild(E("h4", null, "Sentences"));
  shelf.appendChild(E("p", "hint", canAdd ? "Click to add to “" + featName(at.feat) + "”, or drag onto it." : "Open a feature built from sentences to add these."));
  GROUPS.forEach(g => {
    Object.keys(SENT).filter(t => SENT[t].group === g[0] && match(SENT[t].label + " " + g[1])).forEach(t => {
      const b = E("button", "sb"); b.type = "button"; b.draggable = true; b.style.setProperty("--c", "var(" + g[2] + ")");
      b.appendChild(document.createTextNode(SENT[t].label)); if (SENT[t].uses) b.appendChild(E("span", null, String(SENT[t].uses)));
      if (!canAdd) b.setAttribute("aria-disabled", "true");
      b.addEventListener("dragstart", ev => { dragData = { kind: "sentence", type: t }; ev.dataTransfer.setData("text/plain", t); });
      b.addEventListener("click", () => { if (!canAdd) return toast("Open a feature first (or add an Empty feature from above)."); addSentence(at.feat, at.feat.sentences, t); });
      shelf.appendChild(b);
    });
  });
  shelf.appendChild(E("p", "hint", "Counts are how often content uses each kind of record today."));
}

function renderSide() {
  side.innerHTML = "";
  const tabs = E("div", "tabs"); tabs.setAttribute("role", "tablist");
  [["book", "Book page"], ["saved", "Saved data"]].forEach(([k, t]) => { const b = E("button", null, t); b.type = "button"; b.setAttribute("role", "tab"); b.setAttribute("aria-selected", String(sideTab === k));
    b.addEventListener("click", () => { sideTab = k; renderSide(); }); tabs.appendChild(b); });
  side.appendChild(tabs);
  if (sideTab === "book") side.appendChild(bookPage()); else savedPanel();
}
function bookPage() {
  const b = E("div", "book");
  b.appendChild(E("h2", null, cls.name));
  if (cls.details) b.appendChild(E("p", null, cls.details));
  b.appendChild(E("h3", null, "Basics"));
  const prim = Object.keys(cls.primary).map(charName);
  b.appendChild(E("p", null, "Starting Characteristics: You start with " + (prim.length ? listWords(prim, "and") + " of 2" : "no fixed scores") + ", and you can choose one of the following arrays for your other characteristic scores: " + cls.arrays));
  b.appendChild(E("p", null, "Starting Stamina at 1st Level: " + cls.stamStart + "\nStamina Gained at 2nd and Higher Levels: " + cls.stamPer));
  // Advancement table, generated from the levels.
  const tb = E("table"); const hr = E("tr"); ["Level", "Features"].forEach(t => hr.appendChild(E("th", null, t))); tb.appendChild(hr);
  laneKeys().forEach(k => { const fs = cls.lanes[k] || []; if (!fs.length) return; const [a, n] = laneLabel(k); const tr = E("tr");
    tr.appendChild(E("td", null, a === "Level" ? ORD(+n) : "Enc. " + n)); tr.appendChild(E("td", null, fs.map(featName).join(", "))); tb.appendChild(tr); });
  b.appendChild(tb);
  if (cls.resourceName) {
    b.appendChild(E("h3", null, cls.resourceName));
    b.appendChild(E("p", null, compileGains().checklist.map(c => c.details).join(" ")));
  }
  laneKeys().forEach(k => {
    const fs = cls.lanes[k] || []; if (!fs.length) return;
    const [a, n, sub] = laneLabel(k);
    b.appendChild(E("h3", null, a === "Level" ? ORD(+n) + "-Level Features" + (sub ? " (" + sub + ")" : "") : "Encounter " + n));
    fs.forEach(f => {
      b.appendChild(E("h5", null, featName(f)));
      if (featText(f)) b.appendChild(E("p", null, featText(f)));
      const recs = [];
      if (f.kind === "feature") (function walk(l) { l.forEach(s => { if ((s.type === "ability" || s.type === "trigger") && s.f.rec) recs.push([s.f.rec, s.f.display, s.type === "trigger"]); if (s.children) walk(s.children); }); })(f.sentences);
      if (f.kind === "abilities") f.options.forEach(o => o.rec && recs.push([o.rec, null, false]));
      if (recs.length && f.kind === "feature") b.appendChild(E("p", null, "You have the following ability" + (recs.length > 1 ? "s" : "") + ":"));
      recs.forEach(([r, d, t]) => b.appendChild(cardFor(r, d, t)));
    });
  });
  return b;
}
function savedPanel() {
  const at = openId && findFeature(openId);
  side.appendChild(E("p", "hint", "What the engine would store. Nothing here is saved anywhere: copy it to keep it."));
  const btns = E("div", "feat-foot");
  const json = JSON.stringify(compiled, null, 2);
  const cp = E("button", "btn small", "Copy class JSON"); cp.type = "button";
  cp.addEventListener("click", () => copyText(json, null));
  btns.appendChild(cp); side.appendChild(btns);
  if (at) {
    side.appendChild(E("h3", "sec", "“" + featName(at.feat) + "”"));
    side.appendChild(E("pre", "saved", JSON.stringify(compileFeature(at.feat), null, 2)));
  }
  side.appendChild(E("h3", "sec", "Whole class"));
  const sm = Object.assign({}, compiled, { levels: Object.fromEntries(Object.entries(compiled.levels).filter(([, v]) => v.features.length)) });
  side.appendChild(E("pre", "saved", JSON.stringify(sm, null, 2)));
  side.appendChild(E("p", "hint", "Empty levels are left out of this view; Copy includes all of them."));
}

// ---------------------------------------------------------------------------------------------
// Start
document.getElementById("undoBtn").addEventListener("click", undo);
document.getElementById("showGs").addEventListener("change", e => { showGs = e.target.checked; render(); });
document.addEventListener("keydown", e => {
  if ((e.ctrlKey || e.metaKey) && e.key === "z" && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) { e.preventDefault(); undo(); }
  if (e.key === "/" && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) { e.preventDefault(); const s = shelf.querySelector("input.search"); if (s) s.focus(); }
});
/* Share a class: Export gives this page's own model as text to copy (downloads don't work in the
   artifact viewer); Import takes that text back, pasted or from a saved .json file. */
function exportBuilder(btn) {
  const text = JSON.stringify({ classBuilder: 1, cls });
  menuAt(btn, m => { m.appendChild(E("div", "q", "Copy this and send it; anyone can paste it into Import to open the class.")); const ta = E("textarea", "io"); ta.readOnly = true; ta.value = text; m.appendChild(ta);
    const yn = E("div", "yn"); const c = E("button", "btn primary", "Copy"); c.type = "button"; c.addEventListener("click", () => copyText(text, ta)); yn.appendChild(c); m.appendChild(yn); });
}
function loadBuilderText(t) {
  let d; try { d = JSON.parse(t); } catch (e) { return toast("That isn't valid JSON. Paste the whole text from Export."); }
  if (!d || !d.cls || !d.cls.lanes) return toast("That isn't a class from this builder (use Export to make one).");
  const ids = t.match(/"id":"[a-z](\d+)"/g) || []; ids.forEach(m => { const n = +m.replace(/\D/g, ""); if (n >= uid) uid = n + 1; });
  closeMenu(); change(() => { cls = d.cls; openId = null; }); toast("Opened \u201c" + cls.name + "\u201d. Undo goes back to the class you had.");
}
function importBuilder(btn) {
  menuAt(btn, m => { m.appendChild(E("div", "q", "Paste a class from Export, or choose a saved .json file.")); const ta = E("textarea", "io"); ta.placeholder = '{"classBuilder":1, ...}'; m.appendChild(ta);
    const yn = E("div", "yn"); const o = E("button", "btn primary", "Open pasted class"); o.type = "button"; o.addEventListener("click", () => loadBuilderText(ta.value));
    const fi = E("input"); fi.type = "file"; fi.accept = ".json,application/json"; fi.id = "importFile"; fi.addEventListener("change", () => { const fl = fi.files[0]; if (fl) fl.text().then(loadBuilderText); });
    yn.appendChild(o); yn.appendChild(fi); m.appendChild(yn); });
}
document.getElementById("exportBtn").addEventListener("click", ev => { ev.stopPropagation(); exportBuilder(ev.currentTarget); });
document.getElementById("importBtn").addEventListener("click", ev => { ev.stopPropagation(); importBuilder(ev.currentTarget); });
const openSel = document.getElementById("openSel");
[["draft", "Your class (kept in this browser)"], ["blank", "New blank class"]].forEach(([v, t]) => { const o = E("option", null, t); o.value = v; openSel.appendChild(o); });
openSel.addEventListener("change", () => { if (openSel.value === "blank") { change(() => { cls = blankClass(); openId = null; }); } openSel.value = "draft"; });
cls = loadDraft() || blankClass();
render();
