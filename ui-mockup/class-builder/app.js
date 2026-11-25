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
// Resource gain stats read with the class's own resource name ("start-of-turn Wrath gain").
// For a die-roll class the attribute is the die size (1d3); its level bonuses (+1, +2) live in the
// roll itself, as the rules and core content do, so the option says what it really changes.
const statOpts = () => { const r = cls && cls.resourceName || "resource", die = cls && cls.startGain && cls.startGain.kind === "die";
  return STAT_OPTS.concat([[HR_START, "start-of-turn " + r + (die ? " die size (1d" + cls.startGain.n + ")" : " gain")], [HR_ALL, "every " + r + " gain"]]); };
const CUSTOM_FLAGS = T.customAttributes.filter(a => !/Class Specific|Hidden/i.test(a[2]));
const statName = id => (STAT_OPTS.find(s => s[0] === id) || T.customAttributes.find(a => a[0] === id) || [id, id])[1];
const MOVES = [["fly", "fly"], ["climb", "climb at full speed"], ["swim", "swim at full speed"], ["burrow", "burrow"]];
const KEYWORDS = ["Animal", "Area", "Charge", "Magic", "Melee", "Psionic", "Ranged", "Strike", "Weapon"];
const SKILL_GROUPS = ["crafting", "exploration", "interpersonal", "intrigue", "lore"];
const PERK_GROUPS = ["crafting", "exploration", "interpersonal", "intrigue", "lore", "supernatural"];
// The tags perks carry in the compendium (some groups are plural there).
const PERK_TAGS = { crafting: "crafting perk", exploration: "exploration perks", interpersonal: "interpersonal perk", intrigue: "intrigue perk", lore: "lore perks", supernatural: "supernatural perks" };
/* The start-of-turn gain lives in a custom attribute (as core classes store it), so complications,
   titles and items can change it; another attribute adds to every heroic resource gain. */
const HR_START = "4d6eb7b5-85d1-41c0-a462-05cff692749a", HR_START_NAME = "Heroic Resource Gain at Start";
const HR_ALL = "61a3ee0a-353f-4407-a317-d05647551fa5";
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
/* A short notice at the bottom. action: { label, run } adds a button such as Undo. */
function toast(msg, action) {
  document.querySelectorAll(".toast").forEach(t => t.remove());
  const t = E("div", "toast"); t.setAttribute("role", "status"); t.appendChild(E("span", null, msg));
  if (action) { const b = E("button", "btn small", action.label); b.type = "button"; b.addEventListener("click", () => { t.remove(); action.run(); }); t.appendChild(b); }
  document.body.appendChild(t); setTimeout(() => t.remove(), action ? 8000 : 3500);
}
/* Keyboard focus survives re-rendering: focusable controls carry data-fk (a key that stays the same
   from one render to the next), and after a change the control with the same key gets focus back. */
const OBJ_KEYS = new WeakMap(); let objSeq = 0;
const objKey = o => { if (!OBJ_KEYS.has(o)) OBJ_KEYS.set(o, "o" + (++objSeq)); return OBJ_KEYS.get(o); };
const fk = (el, key) => { el.dataset.fk = key; return el; };
let menuFk = null, pendingFk = null;
function restoreFocus(key) {
  if (!key) return; const el = document.querySelector('[data-fk="' + CSS.escape(key) + '"]');
  if (el) el.focus({ preventScroll: true });
}
let openMenu = null;
function closeMenu() { if (openMenu) { openMenu.remove(); openMenu = null; } }
// A click on something the menu just rebuilt (no longer in the page) isn't a click outside it.
document.addEventListener("click", ev => { if (openMenu && ev.target.isConnected && !openMenu.contains(ev.target)) closeMenu(); });
document.addEventListener("keydown", ev => { if (ev.key === "Escape") closeMenu(); });
/* A popup menu under an element. build(menu) fills it; it closes on outside click or Escape. */
function menuAt(el, build) {
  closeMenu(); menuFk = el.dataset.fk || null;
  const m = E("div", "menu"); build(m);
  // Arrow keys move through the menu's buttons and fields; Escape returns to the word that opened it.
  m.addEventListener("keydown", ev => {
    if (ev.key === "Escape") { ev.stopPropagation(); closeMenu(); restoreFocus(menuFk); return; }
    if (ev.key !== "ArrowDown" && ev.key !== "ArrowUp") return;
    if (ev.target.tagName === "TEXTAREA") return;
    const items = [...m.querySelectorAll("button, input, textarea")].filter(x => x.offsetParent !== null);
    const i = items.indexOf(document.activeElement); if (!items.length) return;
    ev.preventDefault(); items[(i + (ev.key === "ArrowDown" ? 1 : -1) + items.length) % items.length].focus();
  });
  document.body.appendChild(m);
  const r = el.getBoundingClientRect();
  m.style.left = Math.max(8, Math.min(window.scrollX + r.left, window.scrollX + document.documentElement.clientWidth - m.offsetWidth - 8)) + "px";
  m.style.top = (window.scrollY + r.bottom + 4) + "px";
  openMenu = m; setTimeout(() => { const f = m.querySelector("input, button"); if (f) f.focus(); });
  return m;
}

// ---------------------------------------------------------------------------------------------
// Underlined values. Each opens one control; changes go through change() so undo and redraw happen.
function tok(text, onClick, empty, key) {
  const b = E("button", "tok" + (empty ? " empty" : ""), text); b.type = "button"; if (key) b.dataset.fk = key;
  b.addEventListener("click", ev => { ev.stopPropagation(); onClick(b); });
  return b;
}
/* Pick one of [value, label] options. */
function pickTok(obj, key, opts, empty) {
  const cur = opts.find(o => o[0] === obj[key]);
  return tok(cur ? cur[1] : (obj[key] || empty || "choose"), b => menuAt(b, m => {
    if (opts.length > 10) addFilter(m);
    opts.forEach(o => { const x = E("button", null, o[1]); x.type = "button"; x.addEventListener("click", () => { closeMenu(); change(() => { obj[key] = o[0]; }); }); m.appendChild(x); });
  }), !cur && !obj[key], objKey(obj) + ":" + key);
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
  }), !names.length, objKey(obj) + ":" + key);
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
    // Enter keeps focus on this word; Tab commits after focus has moved, so it lands on the next control.
    i.addEventListener("blur", () => setTimeout(commit)); i.addEventListener("keydown", e => { if (e.key === "Enter") { pendingFk = objKey(obj) + ":" + key; commit(); } if (e.key === "Escape") { done = true; render(); restoreFocus(objKey(obj) + ":" + key); } });
  }, v === "" || v == null, objKey(obj) + ":" + key);
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
/* Amounts that can be formulas ("fx"): a number, a GoblinScript formula (Victories, 1d3, Presence...),
   and optionally steps that change it with level ("1d3, 1d3 + 1 from 7th level"). The steps live in
   obj[key + "Lv"] as [{ from, value }]. fxFormula gives one formula for the engine; fxTable gives the
   level table core classes store on checklist lines. */
const fxSteps = (obj, key) => (obj[key + "Lv"] || []).filter(x => x.from && x.value !== "").slice().sort((a, b) => +a.from - +b.from);
function fxText(obj, key) {
  const st = fxSteps(obj, key), base = String(obj[key] == null ? "" : obj[key]);
  return st.length ? base + " (" + st.map(x => x.value + " from " + ORD(+x.from) + " level").join(", ") + ")" : base;
}
function fxFormula(obj, key) {
  let f = String(obj[key] == null ? "" : obj[key]).trim() || "0";
  fxSteps(obj, key).forEach(x => { f = "(" + x.value + ") when Level >= " + x.from + " else (" + f + ")"; });
  return f;
}
function fxTable(obj, key) {
  const st = fxSteps(obj, key); if (!st.length) return numOr(obj[key]);
  return { __typeName: "GoblinScriptTable", id: "table", field: "Level", editableField: true,
    entries: [{ threshold: 1, script: String(obj[key]) }].concat(st.map(x => ({ threshold: +x.from, script: String(x.value) }))) };
}
const FX_PICKS = [["1", "a number"], ["Victories", "your Victories"], ["1d3", "a die roll (1d3)"], ["Level", "your level"]].concat(CHARS.map(c => [c[1], "your " + c[1]]));
/* A formula read as words: "Victories" reads "your Victories" (the FX_PICKS wording). */
function fxWords(obj, key) {
  const base = String(obj[key] == null ? "" : obj[key]).trim(), pick = FX_PICKS.find(p => p[0] === base && /^your /.test(p[1]));
  return pick ? fxText(obj, key).replace(base, pick[1]) : fxText(obj, key);
}
/* True when an amount is a plain number or dice ("2", "1d3"), so "you gain 2 resolve" reads right;
   anything else reads "a number of resolve equal to your Victories". */
const fxIsCount = (obj, key) => /^(\d+|\d*d\d+)$/i.test(String(obj[key] == null ? "" : obj[key]).trim());
const gainAmountText = (g, res) => fxIsCount(g, "qty") || !String(g.qty || "").trim() ? fxText(g, "qty") + " " + res : "a number of " + res + " equal to " + fxWords(g, "qty");
function fxTok(obj, key, placeholder, words) {
  const t = tok((words ? fxWords(obj, key) : fxText(obj, key)) || placeholder, b => menuAt(b, m => fillFx(m, obj, key)), obj[key] === "" || obj[key] == null, objKey(obj) + ":" + key);
  t.classList.add("fx"); t.title = "Build a formula"; return t;
}
/* The formula picker, laid out like the ability editor's (same header, search, groups and
   "Type a formula instead"), so an fx amount looks the same in every editor. Class amounts are
   formula text, so a pick writes the formula; "Changes with level" keeps the level steps. */
const FX_STATS = ["Level", "Victories", "Might", "Agility", "Reason", "Intuition", "Presence", "Highest Characteristic", "Stamina", "Maximum Stamina", "Recovery Value", "Recoveries Available to Spend", "Heroic Resources Available to Spend", "Walking Speed", "Size", "Reach", "Combat Round"];
/* ad (optional) is for amounts stored another way, such as the start-of-turn gain:
   { get(), set(formula), addStep(), reads(formula) }. Without it the amount is obj[key]. */
function fillFx(m, obj, key, ad) {
  m.innerHTML = ""; m.classList.add("picker");
  const get = ad ? ad.get : () => obj[key];
  const base = () => String(get() == null ? "" : get()).trim() || "1";
  const wrap = f => /^[\w.]+$/.test(f) ? f : "(" + f + ")";
  const steps = ad ? [] : (obj[key + "Lv"] = obj[key + "Lv"] || []);
  const setF = f => { change(() => { if (ad) ad.set(f); else obj[key] = f; }); };
  const ph = E("div", "ph"); const t = E("div", "t", "Amount"); t.appendChild(E("span", "kind", "number")); ph.appendChild(t);
  ph.appendChild(E("p", null, "A number, or what it should be based on."));
  const search = E("input"); search.placeholder = "What should this be based on? e.g. level, might"; search.setAttribute("aria-label", "Search blocks"); ph.appendChild(search); m.appendChild(ph);
  const item = (txt, d, make, k) => ({ txt, d, make, k: k || "" });
  const groups = [
    ["Use a stat", "A characteristic, Level, Stamina...", FX_STATS.map(f => item("Your " + f, "", () => setF(f), "characteristic"))],
    ["Scale with level", "Grows as the creature levels up.", [
      item("[1], plus [1] from level [5]", "A bonus once a level is reached.", () => { if (ad) return change(ad.addStep); change(() => { steps.push({ from: "5", value: base() + " + 1" }); }, true); fillFx(m, obj, key); }, "echelon bonus"),
      item("[ ] plus your Level", "Goes up by one every level.", () => setF(base() + " + Level"), "per level")]],
    ["Do math", "Add, subtract, multiply, halve.", [
      item("[ ] + [ ]", "Add two values (also -, * and /).", () => setF(base() + " + 1"), "plus minus times add subtract"),
      item("Half of [ ]", "Division rounds down.", () => setF(wrap(base()) + " / 2"), "divide half"),
      item("[ ] if [test], otherwise [ ]", "Pick one of two values.", () => setF("2 when Winded else " + base()), "when else choose")]],
    ["Roll dice", "Only damage, healing and gains can roll.", [item("1d3", "Change the count and sides after.", () => setF("1d3"), "random d3 d6"), item("1d6", "", () => setF("1d6"), "random d6 d10")]],
  ];
  const pb = E("div", "pb"); m.appendChild(pb); const expanded = new Set();
  const draw = () => {
    pb.innerHTML = ""; const q = search.value.trim().toLowerCase(); let n = 0;
    groups.forEach(([g, gd, opts]) => {
      const vis = opts.filter(o => !q || (g + " " + o.txt + " " + o.d + " " + o.k).toLowerCase().includes(q)); if (!vis.length) return;
      const gh = E("div", "grp", g); gh.appendChild(E("span", "gd", gd)); pb.appendChild(gh);
      const cap = !q && !expanded.has(g) && vis.length > 4;
      (cap ? vis.slice(0, 3) : vis).forEach(o => { const b = E("button", "opt"); b.type = "button"; b.appendChild(E("span", "chip num", o.txt)); if (o.d) b.appendChild(E("span", "d", o.d));
        b.addEventListener("click", o.make); pb.appendChild(b); n++; });
      if (cap) { const more = E("button", "opt more", "Show " + (vis.length - 3) + " more"); more.type = "button"; more.addEventListener("click", ev => { ev.stopPropagation(); expanded.add(g); draw(); }); pb.appendChild(more); }
    });
    if (!n) pb.appendChild(E("p", "note", "Nothing matches. You can type a formula below."));
    // Level steps (core classes store these as a level table): shown under the groups while there are any.
    if (steps.length && !q) {
      const gh = E("div", "grp", "Changes with level"); gh.appendChild(E("span", "gd", "A different amount from a level on.")); pb.appendChild(gh);
      steps.forEach((x, i) => {
        const row = E("div", "fxrow"); row.appendChild(document.createTextNode("From level "));
        const lv = E("input", "fxlv"); lv.value = x.from; lv.inputMode = "numeric"; lv.setAttribute("aria-label", "From level");
        lv.addEventListener("change", () => { change(() => { x.from = lv.value.trim(); }, true); upd(); });
        const va = E("input", "fxval"); va.value = x.value; va.placeholder = "e.g. 1d3 + 1"; va.setAttribute("aria-label", "Amount from that level");
        va.addEventListener("change", () => { change(() => { x.value = va.value.trim(); }, true); upd(); });
        const rm = E("button", "btn small", "✕"); rm.type = "button"; rm.title = "Remove this step";
        rm.addEventListener("click", ev => { ev.stopPropagation(); change(() => { steps.splice(i, 1); }, true); fillFx(m, obj, key); });
        row.appendChild(lv); row.appendChild(document.createTextNode(":")); row.appendChild(va); row.appendChild(rm); pb.appendChild(row);
      });
    }
  };
  search.addEventListener("input", draw); draw();
  // Class amounts have no box beside the fx, so this one is open and holds the current amount.
  const tb = E("details", "typebox"); tb.open = true; tb.appendChild(E("summary", null, "Type a formula instead"));
  tb.appendChild(gsDocLink());
  const ta = E("textarea"); ta.id = "fxInput"; ta.spellcheck = false; ta.setAttribute("aria-label", "GoblinScript formula"); ta.placeholder = "e.g. 2, Victories, 1d3, Presence"; ta.value = get() == null ? "" : get();
  const res = E("div", "res"); const upd = () => { const v = ta.value.trim(); res.textContent = v ? "Reads: " + (ad ? ad.reads(v) : fxText(Object.assign({}, obj, { [key]: v }), key)) + (!ad && showGs ? "  ·  saves as " + fxFormula(Object.assign({}, obj, { [key]: v }), key) : "") : ""; };
  ta.addEventListener("input", upd); upd();
  const use = () => setF(ta.value.trim());
  ta.addEventListener("keydown", e => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); use(); } });
  const ins = E("button", "btn small", "Use this formula"); ins.type = "button"; ins.addEventListener("click", use);
  tb.appendChild(ta); tb.appendChild(res); tb.appendChild(ins); m.appendChild(tb);
  setTimeout(() => { if (m.isConnected) search.focus(); });
}
const lbl = t => document.createTextNode(" " + t + " ");

// ---------------------------------------------------------------------------------------------
// Sentence blocks: what a feature does. Each one: shelf label, group, a book-style sentence with
// underlined values, and the CharacterModifier record it saves as.
/* Shelf groups, by what an entry does for the character (a choice sits with what it gives: raising a
   characteristic is a stat, choosing a perk is with skills). A "Common" list of the most used comes first. */
const GROUPS = [["stats", "Stats", "--c-stats"], ["rolls", "Rolls", "--c-rolls"], ["def", "Defences", "--c-def"], ["abil", "Abilities", "--c-abil"],
  ["skill", "Skills, perks and languages", "--c-skill"], ["res", "Class, kit, resources and reminders", "--c-res"], ["if", "Logic", "--c-if"]];
const modBase = (feat, extra) => Object.assign({ __typeName: "CharacterModifier", name: feat.name, description: feat.text || "" }, extra);
/* Choice blocks are what the player picks when they gain the feature. Unlike the other sentences they
   don't save as modifiers: each saves as its own choice record, and compileFeature decides the feature's
   record type from its blocks (one choice alone -> that choice; a mix -> a feature list). */
const SENT = {
  perkChoice: { featName: "Perk", desc: "The player picks perks from the groups you name.", label: "Choose a perk", group: "skill", uses: 54, choice: true, make: () => ({ num: "1", groups: ["exploration", "interpersonal", "intrigue"] }),
    render: (f, add) => { add(lbl("You gain")); add(textTok(f, "num", "1")); add(multiTok(f, "groups", PERK_GROUPS.map(g => [g, g]), "any", "or")); add(lbl((+f.num === 1 ? "perk" : "perks") + " of your choice")); },
    prose: f => "You gain " + word(f.num) + " " + listWords(f.groups) + " perk" + (+f.num === 1 ? "" : "s") + " of your choice.",
    // Perks are matched by exact tag text (Feat.lua HasTag, lowercased), so each group uses the tag its perks carry.
    compileChoice: (f, feat, base) => Object.assign({ __typeName: "CharacterFeatChoice" }, base, f.noTag && !f.groups.length ? {} : { tag: (f.noFeatPrefix ? "" : "feat,") + f.groups.map(g => PERK_TAGS[g] || g + " perk").join(",") }, +f.num > 1 ? { numChoices: +f.num } : {}) },
  /* One Skills block for both: skills you just have, and skills the player chooses. It saves whichever
     records are needed: a proficiency modifier for the fixed skills, a skill choice for the rest. */
  skills: { featName: "Skills", desc: "Skills the hero always has, plus any the player chooses from skill groups or a list you name.", label: "Have or choose skills", group: "skill", uses: 118, choice: true,
    make: () => ({ granted: [], num: "1", groups: [], named: [] }),
    render: (f, add) => {
      // Empty parts read naturally: "You have no fixed skills and choose 5 skills from ... (+ named skills)".
      const g = f.granted.length;
      add(lbl(g ? "You have the" : "You have")); add(multiTok(f, "granted", T.skills.map(x => [x[0], x[1]]), "no fixed skills", "and")); if (g) add(lbl(g === 1 ? "skill" : "skills"));
      add(lbl("and choose")); add(textTok(f, "num", "0")); add(lbl((+f.num === 1 ? "skill" : "skills") + " from" + (f.groups.length ? " the" : "")));
      add(multiTok(f, "groups", SKILL_GROUPS.map(g2 => [g2, g2]), "any skill group", "or")); if (f.groups.length) add(lbl(f.groups.length === 1 ? "skill group" : "skill groups"));
      if (f.named.length) add(lbl("or"));
      add(multiTok(f, "named", T.skills.map(x => [x[0], x[1]]), "+ named skills", "or"));
    },
    prose: f => {
      const have = f.granted.map(i => lookupName(T.skills, i)), n = +f.num || 0;
      const from = f.groups.length ? " from the " + listWords(f.groups) + (f.groups.length === 1 ? " skill group" : " skill groups") + (f.named.length ? " or " + listWords(f.named.map(i => lookupName(T.skills, i))) : "")
        : f.named.length ? " from " + listWords(f.named.map(i => lookupName(T.skills, i))) : " of your choice";
      const pick = n ? "choose " + word(n) + " skill" + (n === 1 ? "" : "s") + from : "";
      if (have.length && pick) return "You have the " + listWords(have, "and") + " skill" + (have.length === 1 ? "" : "s") + ". In addition, " + pick + ".";
      if (have.length) return "You have the " + listWords(have, "and") + " skill" + (have.length === 1 ? "" : "s") + ".";
      return pick ? pick.charAt(0).toUpperCase() + pick.slice(1) + "." : "";
    },
    compile: (f, feat) => f.granted.length ? modBase(feat, { behavior: "proficiency", subtype: "skill", proficiency: "proficient", equate: false, skills: Object.fromEntries(f.granted.map(i => [i, true])) }) : null,
    // No groups and no named skills means any skill: every group is offered, as core classes store it.
    compileChoice: (f, feat, base) => +f.num > 0 ? Object.assign({ __typeName: "CharacterSkillChoice" }, base, { numChoices: +f.num,
      categories: Object.fromEntries((f.groups.length || f.named.length ? f.groups : SKILL_GROUPS).map(g => [g, true])), individualSkills: Object.fromEntries(f.named.map(i => [i, true])) }) : null },
  charChoice: { featName: "Characteristic Increase", desc: "The player raises one characteristic of their choice by 1, up to the maximum you set.", label: "Raise a characteristic", group: "stats", uses: 33, choice: true, make: () => ({ num: "1", max: "3" }),
    render: (f, add) => { add(lbl("You can increase")); add(textTok(f, "num", "1")); add(lbl("other characteristic " + (+f.num === 1 ? "score" : "scores") + " by 1, to a maximum of")); add(textTok(f, "max", "3")); },
    prose: f => "Additionally, you can increase " + word(f.num) + " of your characteristic scores by 1, to a maximum of " + f.max + ".",
    // Options are the characteristics this feature doesn't already raise (its "score increases to" blocks).
    compileChoice: (f, feat, base) => { const raised = feat.sentences.filter(x => x.type === "stat" && CHARS.some(c => c[0] === x.f.attr)).map(x => x.f.attr);
      return Object.assign({ __typeName: "CharacterFeatureChoice" }, base, { numChoices: +f.num || 1, allowDuplicateChoices: false,
        options: CHARS.filter(c => !raised.includes(c[0])).map(c => ({ __typeName: "CharacterFeature", name: c[1], description: "", tags: { Hidden: true },
          // +1, then a separate "min" (Override: set max value) modifier for the maximum: the engine
          // doesn't read the "cap" field some content uses (see BLOCK_EDITORS_LUA_STUDY.md, R2).
          modifiers: [{ __typeName: "CharacterModifier", behavior: "attribute", name: c[1], description: "", attribute: c[0], value: 1 },
            { __typeName: "CharacterModifier", behavior: "attribute", name: c[1] + " maximum", description: "", attribute: c[0], operation: "min", value: numOr(f.max) }] })) }); } },
  abilityChoice: { shelf: false, desc: "The player picks abilities from a list you build here (signature, or heroic with a cost).", label: "Choose an ability", group: "abil", uses: 130, choice: true, make: () => ({ num: "1", cat: "signature", cost: "3", options: [] }),
    render: (f, add, s, feat) => {
      add(lbl("Choose")); add(textTok(f, "num", "1")); add(pickTok(f, "cat", [["signature", "signature"], ["heroic", "heroic"]])); add(lbl(+f.num === 1 ? "ability from these" : "abilities from these"));
      if (f.cat === "heroic") { add(lbl(", each costing")); add(textTok(f, "cost", "3")); add(lbl((cls.resourceName || "resource").toLowerCase())); }
      add(abilityCards(f.options.map(o => ({ rec: o.rec, display: o.display, trig: o.trig, problems: o.problems })), feat,
        (i, rec, d, problems) => { f.options[i].rec = rec; if (d !== undefined) f.options[i].display = d; f.options[i].problems = problems; }, i => f.options.splice(i, 1), s, () => abilitySeed(f.cat, f.cost)));
      const b = E("button", "addsent inblock", "+ new ability to choose from"); b.type = "button"; fk(b, "newopt:" + s.id);
      // The option is only added when the editor's Done is pressed; Cancel leaves nothing behind.
      b.addEventListener("click", ev => { ev.stopPropagation(); newOption(f, feat); });
      add(b);
    },
    prose: f => f.cat === "signature" ? "Choose " + word(f.num) + " signature ability from the following options. Signature abilities can be used at will."
      : "Choose " + word(f.num) + " heroic ability from the following options, each of which costs " + f.cost + " " + (cls.resourceName || "heroic resource").toLowerCase() + " to use.",
    compileChoice: (f, feat, base) => Object.assign({ __typeName: "CharacterFeatureChoice" }, base, { numChoices: +f.num || 1, allowDuplicateChoices: false,
      options: f.options.filter(o => o.rec).map(abilityOption) }) },
  subclassChoice: { featName: "Subclass", desc: "The player chooses their subclass (College, Circle, Domain...).", label: "Choose your subclass", group: "res", uses: 12, choice: true, make: () => ({}),
    // What subclasses are called (College, Circle, Domain...) is the feature's own name.
    // The subclasses to choose from: each built here opens on click; compendium ones that name this class show dashed.
    render: (f, add, s, feat) => { add(lbl("Choose your " + (feat && feat.name ? feat.name : "subclass") + ":"));
      cls.subclasses.forEach(sc => { const b = E("button", "subchip", sc.name); b.type = "button"; b.title = "Open the " + sc.name + " subclass"; b.addEventListener("click", ev => { ev.stopPropagation(); showView(sc.id); }); add(b); });
      compendiumSubclasses().forEach(x => { const c = E("span", "subchip linked", x[1]); c.title = "Already in the compendium with this class as its parent";
        add(c); });
      const nb = E("button", "subchip add", "+ new"); nb.type = "button"; nb.addEventListener("click", ev => { ev.stopPropagation(); change(() => { cls.view = newSubclass().id; openId = null; }); window.scrollTo(0, 0); }); add(nb);
      add(E("span", "aside", "(name this feature what the class calls its subclasses, such as College or Domain)")); },
    prose: (f, feat) => { const names = cls.subclasses.map(x => x.name).concat(compendiumSubclasses().map(x => x[1]));
      return "Choose your " + (feat && feat.name ? feat.name : "subclass") + (names.length ? " from " + listWords(names, "or") : "") + "."; },
    compileChoice: (f, feat, base) => Object.assign({ __typeName: "CharacterSubclassChoice" }, base) },
  stat: { desc: "Raise, lower or set one of the hero's numbers: Stamina, speed, stability, a characteristic...", label: "Change a stat", group: "stats", uses: 510, make: () => ({ attr: "hitpoints", op: "add", value: "3" }),
    render: (f, add) => {
      add(lbl("Your")); add(pickTok(f, "attr", statOpts().concat(CUSTOM_FLAGS.filter(a => a[0] !== HR_START && a[0] !== HR_ALL).map(a => [a[0], a[1]])))); if (CHARS.some(c => c[0] === f.attr)) add(lbl("score"));
      add(pickTok(f, "op", [["add", "increases by"], ["sub", "decreases by"], ["max", "increases to"], ["set", "is"], ["min", "can't go above"]]));
      add(fxTok(f, "value", "number or formula"));
    },
    compile: (f, feat) => { const v = fxFormula(f, "value"); const r = modBase(feat, { behavior: "attribute", attribute: f.attr, value: numOr(f.op === "sub" ? "-(" + v + ")" : v) });
      if (f.op === "max" || f.op === "set" || f.op === "min") r.operation = f.op; return r; } },
  move: { desc: "A movement type: fly, climb, swim or burrow.", label: "Movement type", group: "stats", uses: 12, make: () => ({ mode: "fly" }),
    render: (f, add) => { add(lbl("You can")); add(pickTok(f, "mode", MOVES)); },
    compile: (f, feat) => modBase(feat, { behavior: "attribute", attribute: f.mode, value: 1 }) },
  flag: { desc: "A special rule the hero follows, such as Ignore Difficult Terrain.", label: "You ignore / can't...", group: "stats", uses: 667, make: () => ({ attr: (CUSTOM_FLAGS.find(a => /Ignore Difficult Terrain/.test(a[1])) || CUSTOM_FLAGS[0] || [""])[0] }),
    render: (f, add) => { add(lbl("You have")); add(pickTok(f, "attr", CUSTOM_FLAGS.map(a => [a[0], a[1]]))); },
    compile: (f, feat) => modBase(feat, { behavior: "attribute", attribute: f.attr, value: 1 }) },
  edge: { desc: "An edge or bane on tests (by skill) or on ability rolls (by keyword).", label: "Edge or bane on rolls", group: "rolls", uses: 620, make: () => ({ mod: "edge", on: "tests", skills: [], keywords: [], applies: "always" }),
    render: (f, add) => {
      add(lbl("You have")); add(pickTok(f, "mod", EDGE_OPTS));
      add(lbl("on")); rollsPhrase(f, add);
      appliesPhrase(f, add);
    },
    prose: f => "You have " + lookupName(EDGE_OPTS, f.mod) + " on " +
      (onTests(f) ? testsProse(f) : (f.keywords.length ? listWords(f.keywords, "and") + " " : "") + "ability rolls") +
      appliesProse(f) + ".",
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: f.mod, rollType: ROLL_TYPE[f.on] || "ability_power_roll",
      keywords: !onTests(f) && f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [],
      }, rollFields(f), appliesFields(f))),
    combo: { modtype: f => f.mod, fields: () => ({}),
      render: (f, add) => { add(lbl("have")); add(pickTok(f, "mod", [["edge", "an edge"], ["double_edge", "a double edge"], ["bane", "a bane"], ["double_bane", "a double bane"]])); },
      prose: f => "have " + { edge: "an edge", double_edge: "a double edge", bane: "a bane", double_bane: "a double bane" }[f.mod] } },
  enemy: { desc: "Abilities used against you have a bane (or edge).", label: "Rolls against you", group: "rolls", uses: 252, make: () => ({ mod: "bane", keywords: [], applies: "always" }),
    render: (f, add) => { add(lbl("Abilities")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "of any kind", "and")); add(lbl("used against you have"));
      add(pickTok(f, "mod", EDGE_OPTS)); appliesPhrase(f, add); },
    prose: f => (f.keywords.length ? listWords(f.keywords, "and") + " abilities" : "Abilities") + " used against you have " + { bane: "a bane", double_bane: "a double bane", edge: "an edge" }[f.mod] + ".",
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: f.mod, rollType: "enemy_ability_power_roll", keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, f.applies ? appliesFields(f) : { activationCondition: true })) },
  damage: { desc: "Your abilities deal extra damage, optionally only with some keywords or a damage type.", label: "Extra damage", group: "rolls", uses: 208, make: () => ({ amount: "2", dtype: "", keywords: [], applies: "always" }),
    render: (f, add) => { add(lbl("Your")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "damaging", "and")); add(lbl("abilities deal"));
      add(fxTok(f, "amount", "amount")); add(lbl("extra")); add(pickTok(f, "dtype", [["", "(untyped)"]].concat(T.damageTypes.map(d => [d, d])))); add(lbl("damage")); appliesPhrase(f, add); },
    prose: f => "Your " + (f.keywords.length ? listWords(f.keywords, "and") + " " : "") + "abilities deal " + f.amount + " extra " + (f.dtype ? f.dtype + " " : "") + "damage" + appliesProse(f) + ".",
    compile: (f, feat) => { const r = modBase(feat, Object.assign({ behavior: "power", modtype: "none", rollType: "ability_power_roll", damageModifier: fxFormula(f, "amount"),
      keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, appliesFields(f)));
      if (f.dtype) r.damageModifierType = f.dtype; return r; },
    combo: { fields: f => Object.assign({ damageModifier: fxFormula(f, "amount") }, f.dtype ? { damageModifierType: f.dtype } : {}),
      render: (f, add) => { add(lbl("deal")); add(fxTok(f, "amount", "amount")); add(lbl("extra")); add(pickTok(f, "dtype", [["", "(untyped)"]].concat(T.damageTypes.map(d => [d, d])))); add(lbl("damage")); },
      prose: f => "deal " + fxText(f, "amount") + " extra " + (f.dtype ? f.dtype + " " : "") + "damage" } },
  outcome: { desc: "Change a roll's outcome: always tier 3, never tier 1, one tier better or worse. Optionally for a cost.", label: "Change the outcome", group: "rolls", uses: 12,
    make: () => ({ out: "tier3", on: "abilities", attr: "", skills: [], keywords: [], applies: "cost", costN: "1", costRes: "cost" }),
    render: (f, add) => { add(lbl("Your")); rollsPhrase(f, add); add(pickTok(f, "out", OUTCOMES)); appliesPhrase(f, add); },
    prose: f => "Your " + (onTests(f) ? testsProse(f) : (f.keywords.length ? listWords(f.keywords, "and") + " " : "") + "ability rolls") + " " + (OUTCOMES.find(o => o[0] === f.out) || ["", ""])[1] + appliesProse(f) + ".",
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: f.out, rollType: ROLL_TYPE[f.on] || "ability_power_roll",
      keywords: !onTests(f) && f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, rollFields(f), appliesFields(f))),
    combo: { modtype: f => f.out, fields: () => ({}), render: (f, add) => add(pickTok(f, "out", OUTCOMES)), prose: f => (OUTCOMES.find(o => o[0] === f.out) || ["", ""])[1] } },
  potency: { desc: "Raise or lower the potency of your abilities (or of ones used against you). Optionally for a cost.", label: "Change potency", group: "rolls", uses: 30,
    make: () => ({ dir: "up", n: "1", keywords: [], applies: "always" }),
    render: (f, add) => { add(lbl("The potency of your")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "", "and")); add(lbl("abilities"));
      add(pickTok(f, "dir", [["up", "increases by"], ["down", "decreases by"]])); add(textTok(f, "n", "1")); appliesPhrase(f, add); },
    prose: f => "The potency of your " + (f.keywords.length ? listWords(f.keywords, "and") + " " : "") + "abilities " + (f.dir === "up" ? "increases" : "decreases") + " by " + f.n + appliesProse(f) + ".",
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: "none", rollType: "ability_power_roll", potencymod: (f.dir === "up" ? "" : "-") + (f.n || 1), keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, appliesFields(f))),
    combo: { fields: f => ({ potencymod: (f.dir === "up" ? "" : "-") + (f.n || 1) }),
      render: (f, add) => { add(lbl("have their potency")); add(pickTok(f, "dir", [["up", "increased by"], ["down", "decreased by"]])); add(textTok(f, "n", "1")); },
      prose: f => "have their potency " + (f.dir === "up" ? "increased" : "decreased") + " by " + f.n } },
  /* Forced movement distance bonus (Knockback: "push, pull or slide + your Might"): the power
     modifier's adjustments list, one entry per kind of movement. */
  moveBonus: { desc: "Your abilities' forced movement (push, pull, slide) goes further, by a number or formula.", label: "Forced movement bonus", group: "rolls", uses: 6,
    make: () => ({ kinds: ["push"], amount: "1", keywords: [], applies: "always" }),
    render: (f, add) => { add(lbl("Your")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "", "and")); add(lbl("abilities'")); add(multiTok(f, "kinds", FM_KINDS, "choose", "and"));
      add(lbl("distance gains a bonus of")); add(fxTok(f, "amount", "amount", true)); appliesPhrase(f, add); },
    prose: f => "Your " + (f.keywords.length ? listWords(f.keywords, "and") + " " : "") + "abilities' " + listWords(f.kinds, "and") + " distance gains a bonus of " + fxWords(f, "amount") + appliesProse(f) + ".",
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: "none", rollType: "ability_power_roll", adjustments: f.kinds.map(k => ({ type: k, value: fxFormula(f, "amount") })),
      keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, appliesFields(f))) },
  /* Roll other dice instead (Strongest There Is: "3d10k2", roll three keep two): modtype replaceroll. */
  replaceRoll: { desc: "Tests (or ability rolls) roll different dice, such as 3d10, keep the highest 2.", label: "Roll differently", group: "rolls", uses: 3,
    make: () => ({ formula: "3d10k2", on: "tests", attr: "", skills: [], keywords: [], applies: "choose" }),
    render: (f, add) => { add(lbl("Your")); rollsPhrase(f, add); add(lbl("can roll")); add(textTok(f, "formula", "3d10k2", 16)); add(lbl("instead")); appliesPhrase(f, add); },
    prose: f => "Your " + (onTests(f) ? testsProse(f) : "ability rolls") + " can roll " + f.formula + " instead" + appliesProse(f) + ".",
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: "replaceroll", replaceText: f.formula, rollType: ROLL_TYPE[f.on] || "ability_power_roll",
      keywords: !onTests(f) && f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, rollFields(f), appliesFields(f))) },
  /* "When you push a creature, you can slide it instead" (the forcedmovement modifier's movementTypes). */
  moveSwap: { desc: "Forced movement of one kind can be done as another (push as slide...).", label: "Change forced movement", group: "rolls", uses: 4,
    make: () => ({ pairs: [{ from: "push", to: "slide" }] }),
    render: (f, add) => { f.pairs.forEach((x, i) => { add(lbl(i ? "and when you" : "When you")); add(pickTok(x, "from", [["any", "force move"]].concat(FM_KINDS))); add(lbl("a creature, you can")); add(pickTok(x, "to", FM_KINDS)); add(lbl("it instead")); }); },
    prose: f => f.pairs.map((x, i) => (i ? "when" : "When") + " you " + (x.from === "any" ? "force move" : x.from) + " a creature, you can " + x.to + " it instead").join(", and ") + ".",
    compile: (f, feat) => modBase(feat, { behavior: "forcedmovement", movementTypes: f.pairs.map(x => ({ from: x.from, to: x.to })) }) },
  /* Change a damage type (Stormheart: damage can be cold, fire, lightning or sonic; Cryokinetic:
     untyped psionic damage becomes cold). The power modifier's damageTypeMappings. */
  dmgType: { desc: "Your abilities' damage (all of it, or one type) can be dealt as another type instead.", label: "Change damage type", group: "rolls", uses: 3,
    make: () => ({ from: "untyped", to: ["fire"], keywords: [], applies: "choose" }),
    render: (f, add) => { add(lbl("Your")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "", "and")); add(lbl("abilities'")); add(pickTok(f, "from", [["all", "damage"], ["untyped", "untyped damage"]].concat(T.damageTypes.map(d => [d, d + " damage"]))));
      add(lbl("can be")); add(multiTok(f, "to", T.damageTypes.map(d => [d, d]), "choose a type", "or")); add(lbl("damage instead")); appliesPhrase(f, add); },
    prose: f => "Your " + (f.keywords.length ? listWords(f.keywords, "and") + " " : "") + "abilities' " + (f.from === "all" ? "" : f.from + " ") + "damage can be " + listWords(f.to, "or") + " damage instead" + appliesProse(f) + ".",
    // One type may be saved as a plain string (the engine reads both); "asText" keeps a saved string a string.
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: "none", rollType: "ability_power_roll", damageTypeMappings: { [f.from]: f.asText && f.to.length === 1 ? f.to[0] : f.to.slice() },
      keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, appliesFields(f))) },
  /* Primordial Strike style: an option, offered only once the roll has surges, that changes the surges'
     damage type (the modifier's rollRequirement "surges" and surgeDamageType). */
  surgeType: { desc: "When the roll has surges, the player can make the surge damage a type you pick (acid, fire...).", label: "Surge damage type", group: "rolls", uses: 7,
    make: () => ({ dtype: "fire", keywords: [], applies: "choose", req: "surges" }),
    render: (f, add) => { add(lbl("When your")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "", "and")); add(lbl("ability rolls have surges, their extra damage can be"));
      add(pickTok(f, "dtype", T.damageTypes.map(d => [d, d]))); add(lbl("damage")); appliesPhrase(f, add); },
    prose: f => "When your " + (f.keywords.length ? listWords(f.keywords, "and") + " " : "") + "ability rolls have surges, the extra damage can be " + f.dtype + " damage" + appliesProse(f) + ".",
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: "none", rollType: "ability_power_roll", surgeDamageType: f.dtype,
      keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, appliesFields(f))) },
  surges: { desc: "Your ability rolls gain surges. Optionally only with some keywords, or for a cost.", label: "Extra surges", group: "rolls", uses: 0,
    make: () => ({ n: "1", keep: "roll", keywords: [], applies: "always" }),
    render: (f, add) => { add(lbl("Your")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "", "and")); add(lbl("ability rolls gain")); add(fxTok(f, "n", "1")); add(lbl(String(f.n).trim() === "1" ? "surge" : "surges")); add(surgeKeepTok(f)); appliesPhrase(f, add); },
    prose: f => "Your " + (f.keywords.length ? listWords(f.keywords, "and") + " " : "") + "ability rolls gain " + fxText(f, "n") + (String(f.n).trim() === "1" ? " surge" : " surges") + surgeKeepProse(f) + appliesProse(f) + ".",
    compile: (f, feat) => modBase(feat, Object.assign({ behavior: "power", modtype: "none", rollType: "ability_power_roll", surges: fxFormula(f, "n"), surgesCanBeKept: f.keep === "keep" ? true : undefined, keywords: f.keywords.length ? Object.fromEntries(f.keywords.map(k => [k, true])) : [] }, appliesFields(f))),
    combo: { fields: f => Object.assign({ surges: fxFormula(f, "n") }, f.keep === "keep" ? { surgesCanBeKept: true } : {}),
      render: (f, add) => { add(lbl("gain")); add(fxTok(f, "n", "1")); add(lbl(String(f.n).trim() === "1" ? "surge" : "surges")); add(surgeKeepTok(f)); },
      prose: f => "gain " + fxText(f, "n") + (String(f.n).trim() === "1" ? " surge" : " surges") + surgeKeepProse(f) } },
  // One or more damage types share the amount (Elemental Form: acid, cold, fire... immunity equal to your Might).
  immunity: { desc: "Damage immunity or weakness to one or more types.", label: "Immunity or weakness", group: "def", uses: 383, make: () => ({ dtypes: ["fire"], kind: "immunity", amount: "5" }),
    render: (f, add) => { if (!f.dtypes) f.dtypes = [f.dtype || "fire"];
      add(lbl("You have")); add(multiTok(f, "dtypes", T.damageTypes.map(d => [d, d]).concat([["all", "damage"]]), "choose damage types", "and")); add(pickTok(f, "kind", [["immunity", "immunity"], ["weakness", "weakness"]])); if (!fxIsCount(f, "amount")) add(lbl("equal to")); add(fxTok(f, "amount", "amount", true));
      add(lbl("against")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "any damage", "and")); if ((f.keywords || []).length) add(lbl("abilities")); },
    prose: f => "You have " + listWords(f.dtypes || [f.dtype], "and") + " " + f.kind + " " + (fxIsCount(f, "amount") ? "" : "equal to ") + fxWords(f, "amount") + ".",
    // Weakness is saved as negative damage reduction: check against the engine before shipping.
    compile: (f, feat) => modBase(feat, { behavior: "resistance", resistances: (f.dtypes || [f.dtype]).map(d => Object.assign({ __typeName: "ResistanceEntry", apply: "Damage Reduction", damageType: d, dr: f.kind === "weakness" ? "-(" + fxFormula(f, "amount") + ")" : fxFormula(f, "amount") },
      (f.keywords || []).length ? { keywords: Object.fromEntries(f.keywords.map(k => [k, true])) } : {})) }) },
  condImm: { desc: "You can't gain the conditions you pick.", label: "Can't be (condition)", group: "def", uses: 65, make: () => ({ conds: [] }),
    render: (f, add) => { add(lbl("You can't be")); add(multiTok(f, "conds", T.conditions.map(c => [c[0], c[1].toLowerCase()]), "choose conditions")); },
    compile: (f, feat) => modBase(feat, { behavior: "conditionimmunity", conditions: f.conds.slice() }) },
  language: { featName: "Languages", desc: "You know the languages you pick.", label: "You know a language", group: "skill", uses: 4, make: () => ({ ids: [] }),
    render: (f, add) => { add(lbl("You know")); add(multiTok(f, "ids", T.languages.map(s => [s[0], s[1]]), "choose languages", "and")); },
    compile: (f, feat) => modBase(feat, { behavior: "proficiency", subtype: "language", proficiency: "proficient", equate: false, skills: Object.fromEntries(f.ids.map(i => [i, true])) }) },
  resource: { featName: "Recoveries", desc: "You have a number of Recoveries (or another resource).", label: "Recoveries or a resource", group: "res", uses: 35, make: () => ({ res: RES.recovery, num: "8" }),
    render: (f, add) => { add(lbl("You have")); add(fxTok(f, "num", "number")); add(pickTok(f, "res", RESOURCE_OPTS)); },
    compile: (f, feat) => modBase(feat, { behavior: "resource", resourceType: f.res, num: numOr(fxFormula(f, "num")) }) },
  kit: { featName: "Kit", desc: "You can use and gain the benefits of a martial or caster kit.", label: "Kit", group: "res", uses: 10, make: () => ({ kitType: "martial" }),
    render: (f, add) => { add(lbl("You can use and gain the benefits of a")); add(pickTok(f, "kitType", [["martial", "martial"], ["caster", "caster"]])); add(lbl("kit")); },
    compile: (f, feat) => modBase(feat, { behavior: "kitaccess", kitType: f.kitType }) },
  ability: { desc: "Give the hero an ability. You build it in the ability editor.", label: "Gain an ability", group: "abil", uses: 1052, make: () => ({ rec: null }), opensEditor: "ability",
    render: (f, add, s, feat) => { add(lbl("You have the following ability")); add(abilityCards([{ rec: f.rec, problems: f.problems }], feat, (i, rec, d, problems) => { f.rec = rec; f.problems = problems; }, null, s)); usagePhrase(f, add); },
    compile: (f, feat) => f.rec ? usageFields(modBase(feat, { behavior: "activated", name: "Ability", activatedAbility: f.rec }), f) : null },
  trigger: { desc: "Give the hero an ability they use in response to something happening. You build it in the ability editor.", label: "Gain a triggered ability", group: "abil", uses: 1727, make: () => ({ rec: null, display: null }), opensEditor: "triggered",
    render: (f, add, s, feat) => { add(lbl("You have the following triggered ability")); add(abilityCards([{ rec: f.rec, display: f.display, trig: true, problems: f.problems }], feat, (i, rec, display, problems) => { f.rec = rec; f.display = display; f.problems = problems; }, null, s)); usagePhrase(f, add); },
    compile: (f) => f.rec ? usageFields(Object.assign({}, f.rec), f) : null, extra: f => f.display ? [f.display] : [] },
  modAbility: { desc: "Change an ability: more distance, more targets, or a keyword.", label: "Change an ability", group: "abil", uses: 309, make: () => ({ name: "", change: "range", value: "2", keyword: "Charge" }),
    render: (f, add) => {
      add(lbl("Your")); whichAbility(f, add); add(lbl("gains"));
      add(pickTok(f, "change", [["range", "+ distance"], ["numtargets", "+ targets"], ["keyword", "a keyword"]]));
      if (f.change === "keyword") add(pickTok(f, "keyword", KEYWORDS.map(k => [k, k]))); else add(textTok(f, "value", "amount"));
      if (f.text) { add(lbl("and its card says:")); add(textTok(f, "text", "(nothing added)", 40)); }
    },
    // An opened record keeps its own (template) ability; a new one gets a blank modification.
    compile: (f, feat) => modBase(feat, { behavior: "modifyability", ability: f.keepAbility ? undefined : { __typeName: "ActivatedAbility", name: "New Ability", abilityModification: true, behaviors: [] },
      attributes: f.change === "keyword" ? [{ id: "modkeywords", keywords: { [f.keyword]: true }, operation: "Add", value: "" }] : [{ id: f.change, operation: "Add", value: f.value }],
      filterAbility: abilityFilterOf(f), modifyDescription: f.text || undefined }) },
  /* "When you use [ability], it also ...": steps added to an ability (an ability modification built in
     the ability editor), and/or text added to its card (modifyDescription). */
  abilityAddon: { desc: "When you use an ability, it also does more: extra steps built in the ability editor, and text added to its card.", label: "Add to an ability", group: "abil", uses: 15,
    make: () => ({ name: "", rec: { __typeName: "ActivatedAbility", name: "New Ability", abilityModification: true, behaviors: [] }, text: "" }),
    render: (f, add, s) => {
      add(lbl("When you use")); whichAbility(f, add); add(lbl("it also"));
      const n = ((f.rec || {}).behaviors || []).length;
      const b = fk(E("button", "btn small", n ? "does " + n + " more step" + (n === 1 ? "" : "s") + " (edit)" : "does more (add steps)"), "addon:" + s.id); b.type = "button";
      b.addEventListener("click", ev => { ev.stopPropagation(); openEditor({ rec: f.rec, kind: "ability" }, rec => { f.rec = rec; }); }); add(b);
      add(lbl("and its card says:")); add(textTok(f, "text", "(nothing added)", 40)); },
    prose: f => f.text ? String(f.text).replace(/\.?$/, ".") : "When you use " + (f.name || "the ability") + ", it does more.",
    compile: (f, feat) => modBase(feat, { behavior: "modifyability", filterAbility: abilityFilterOf(f), ability: f.rec, modifyDescription: f.text || undefined }) },
  reminder: { desc: "A note on the hero's sheet, for a rule the game can't apply for you. It doesn't change anything in play.", label: "Reminder text", group: "res", uses: 89, make: () => ({ text: "" }),
    render: (f, add) => { add(lbl("Reminder:")); add(textTok(f, "text", "what players are reminded of", 40)); },
    prose: f => String(f.text || "").replace(/\.?$/, "."),
    compile: (f, feat) => modBase(feat, { behavior: "movementtext", text: f.text, color: f.color || "white" }) },
  /* Growing table (Growing Ferocity, Psionic Mastery...): rows unlocked by the most heroic resource the
     hero has had this turn ("Heroic Resources This Turn", the turn's high-water mark), each from a level.
     Each row holds ordinary blocks. It saves the display table (growingresources) plus every row's
     modifiers, with conditions written for you, including rows that replace an earlier one. */
  growing: { shelf: false, desc: "Benefits that switch on as the hero's resource climbs during a turn, like the Fury's Growing Ferocity. Each row says what the hero gets at that amount; a later row can replace an earlier one.", label: "Growing table", group: "res", uses: 11, container: true, featName: "",
    make: () => ({ rows: [2, 4, 6].map(n => ({ id: newId("r"), at: String(n), level: "1", replaces: "", text: "", blocks: [] })) }),
    render: (f, add, s, feat) => {
      add(lbl("Each row switches on once you've had at least that much " + resWord() + " this turn, and stays on until the start of your next turn"));
      const rows = E("div", "growrows");
      f.rows.forEach((r, i) => {
        const row = E("div", "growrow");
        const head = E("div", "growhead");
        head.appendChild(lbl("At")); head.appendChild(textTok(r, "at", "2")); head.appendChild(lbl(resWord() + ", from level")); head.appendChild(textTok(r, "level", "1"));
        const earlier = f.rows.filter(x => x !== r && (+x.at < +r.at || (+x.at === +r.at && +x.level < +r.level)));
        if (earlier.length || r.replaces) { head.appendChild(lbl("\u00b7")); head.appendChild(pickTok(r, "replaces", [["", "adds to earlier rows"]].concat(earlier.map(x => [x.id, "replaces the row at " + x.at + (+x.level > 1 ? " (level " + x.level + ")" : "")])))); }
        head.appendChild(E("span", "grow"));
        const rm = fk(E("button", "mb", "\u2715"), "growrm:" + r.id); rm.type = "button"; rm.title = "Remove this row";
        rm.addEventListener("click", () => { change(() => { f.rows.splice(i, 1); f.rows.forEach(x => { if (x.replaces === r.id) x.replaces = ""; }); }); toast("Removed the row at " + r.at + ".", { label: "Undo", run: undo }); });
        head.appendChild(rm); row.appendChild(head);
        const body = E("div", "ifbody sents"); regList(body, r.blocks, feat, true); renderSentenceList(r.blocks, feat, body);
        const ad = fk(E("button", "addsent", "+ add to this row"), "growadd:" + r.id); ad.type = "button";
        ad.addEventListener("click", ev => { ev.stopPropagation(); sentenceMenu(ad, type => addSentence(feat, r.blocks, type), true); });
        body.appendChild(ad); row.appendChild(body);
        const tx = E("div", "growtext"); tx.appendChild(lbl("On the sheet:")); tx.appendChild(textTok(r, "text", growRowShort(r) || "short text for the table", 40));
        if (!r.text) tx.appendChild(E("span", "aside", "(text made from its blocks)"));
        row.appendChild(tx);
        rows.appendChild(row);
      });
      const more = fk(E("button", "addsent inblock", "+ add a row"), "growrow:" + s.id); more.type = "button";
      more.addEventListener("click", () => change(() => { const last = f.rows[f.rows.length - 1]; f.rows.push({ id: newId("r"), at: String(last ? +last.at + 2 : 2), level: last ? last.level : "1", replaces: "", text: "", blocks: [] }); }));
      rows.appendChild(more);
      add(rows);
    } },
  aura: { desc: "An area around you: the blocks inside apply to creatures in it (you and your allies, enemies...).", label: "Aura", group: "abil", uses: 28, wrapper: true, featName: "",
    make: () => ({ radius: "3", who: "selfandfriends" }),
    render: (f, add) => { add(lbl("You have an aura of")); add(textTok(f, "radius", "3")); add(lbl(+f.radius === 1 ? "square." : "squares.")); add(pickTok(f, "who", AURA_WHO)); add(lbl("in it:")); },
    claims: ["aura", "radius", "filterCondition"], childMods: r => (r.aura || {}).modifiers || [],
    // A saved aura keeps its own fields (display, guid...); its children and who it affects are rebuilt.
    compileWrap: (f, inner, feat, src) => modBase(feat, { behavior: "aura", radius: numOr(f.radius || "1"),
      aura: Object.assign(src ? omit(clone(src.aura), ["modifiers", "applyto"]) : { __typeName: "Aura", name: feat.name, description: feat.text || "" }, { applyto: f.who, modifiers: inner }) }) },
  /* Changes to your companion (Beastheart) or to your summons (Summoner): the blocks inside apply to
     that creature. Saved as one modcompanion / modsummoner record holding a feature of modifiers. */
  companionMods: { desc: "The blocks inside apply to your companion instead of you.", label: "Your companion", group: "abil", uses: 23, wrapper: true, featName: "",
    make: () => ({}), render: (f, add) => { add(lbl("Your companion has:")); },
    claims: ["feature", "filterCondition"], childMods: r => (r.feature || {}).modifiers || [],
    compileWrap: (f, inner, feat, src) => modBase(feat, { behavior: "modcompanion", feature: wrapFeature(src, inner, feat) }) },
  summonerMods: { desc: "The blocks inside apply to the creatures you summon (or, set to summoner, to you from your summons).", label: "Your summons", group: "abil", uses: 7, wrapper: true, featName: "",
    make: () => ({}), render: (f, add) => { add(lbl("Your summoned creatures have:")); },
    claims: ["feature", "filterCondition"], childMods: r => (r.feature || {}).modifiers || [],
    compileWrap: (f, inner, feat, src) => modBase(feat, { behavior: "modsummoner", feature: wrapFeature(src, inner, feat) }) },
  /* "Choose one of the following" where each option is a small feature built from blocks (a
     characteristic +1, a triggered ability, several benefits). */
  optionChoice: { featName: "Choice", desc: "The player picks one (or more) of the options you build here; each option is its own set of blocks.", label: "Choose from options", group: "res", uses: 81, choice: true,
    make: () => ({ num: "1", options: [blankOption("Option 1"), blankOption("Option 2")] }),
    render: (f, add, s, feat) => {
      add(lbl("Choose")); add(textTok(f, "num", "1")); add(lbl("of the following:"));
      const box = E("div", "growrows");
      f.options.forEach((o, i) => {
        const row = E("div", "growrow"), head = E("div", "growhead");
        head.appendChild(lbl("Option")); head.appendChild(textTok(o, "name", "name this option", 28)); head.appendChild(E("span", "grow"));
        const rm = fk(E("button", "mb", "\u2715"), "optrm:" + o.id); rm.type = "button"; rm.title = "Remove this option";
        rm.addEventListener("click", () => { change(() => { f.options.splice(i, 1); }); toast("Removed the option.", { label: "Undo", run: undo }); });
        head.appendChild(rm); row.appendChild(head);
        const body = E("div", "ifbody sents"); regList(body, o.sentences, feat, true); renderSentenceList(o.sentences, feat, body);
        const ad = fk(E("button", "addsent", "+ add to this option"), "optadd:" + o.id); ad.type = "button";
        ad.addEventListener("click", ev => { ev.stopPropagation(); sentenceMenu(ad, type => addSentence(feat, o.sentences, type), true); });
        body.appendChild(ad); row.appendChild(body); box.appendChild(row);
      });
      const more = fk(E("button", "addsent inblock", "+ add an option"), "optmore:" + s.id); more.type = "button";
      more.addEventListener("click", () => change(() => { f.options.push(blankOption("Option " + (f.options.length + 1))); }));
      box.appendChild(more); add(box);
    },
    prose: f => "Choose " + word(f.num) + " of the following: " + listWords(f.options.map(o => featName(o)), "or") + ".",
    compileChoice: (f, feat, base) => Object.assign({ __typeName: "CharacterFeatureChoice" }, base, { numChoices: +f.num || 1, allowDuplicateChoices: false, options: f.options.map(o => compileFeature(o)) }) },
  /* A choice the engine makes from its own list (deity, companion...): the builder names it and keeps it. */
  simpleChoice: { shelf: false, featName: "Choice", desc: "A choice from a list the game keeps (a deity, a companion).", label: "Engine choice", group: "res", uses: 3, choice: true,
    make: () => ({ typeName: "CharacterDeityChoice", label: "Choose a deity" }),
    render: (f, add) => { add(lbl(f.label)); add(E("span", "aside", "(the game lists the options)")); },
    prose: f => f.label + ".",
    compileChoice: (f, feat, base) => Object.assign({ __typeName: f.typeName }, base) },
  /* Several roll changes that apply to the same rolls, saved as ONE power roll modifier. The keywords
     and roll options are shared, so they are set once here; each block inside adds its part. */
  rollCombo: { shelf: false, desc: "Roll changes that apply together, saved as one power roll modifier.", label: "Combined roll change", group: "rolls", uses: 0, wrapper: true, comboHost: true,
    make: () => ({ keywords: [], applies: "always" }),
    render: (f, add) => { add(lbl("Your")); add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "", "and")); add(lbl("ability rolls:")); const t = E("span", "tag", "Combined"); t.title = "Saved as one power roll modifier"; add(t); } },
  onlyIf: { desc: "The blocks inside apply only while something is true: you're Strained, winded or prone, you have enough Victories, it's your turn...", label: "Logic", group: "if", uses: 720, make: () => ({ cond: null }), wrapper: true,
    render: (f, add) => { add(lbl("Only if")); add(renderTest(f, "cond", true)); } },
};
/* Logic tests, built like the ability editor's: "Only if [test]", where a test is a block you pick,
   and tests can be combined (all of / any of / not). A class feature only knows about the hero who
   has it, so there is no target, potency or "triggering creature" here; every test is about you.
   A test is stored as a small tree, e.g. { t: "cmp", a: "Victories", op: ">=", n: "5" }. */
const TEST_OPS = [[">=", "is at least"], ["<=", "is at most"], ["=", "is"], ["~=", "is not"]];
const TEST_OP_PROSE = { ">=": n => n + " or more", "<=": n => n + " or less", "=": n => "exactly " + n, "~=": n => "not " + n };
const TEST_OP_FLIP = { ">=": "<", "<=": ">", "=": "~=", "~=": "=", "<": ">=", ">": "<=" };
/* Numbers a class feature can compare: [GoblinScript name, word in the block, book wording from "5 or more"]. */
function testStats(ctx) {
  const r = resWord();
  // The engine only tells "Offered when" about the cast (how many targets), not "Automatically selected when".
  const castStats = ctx === "offer" ? [["Cast.Target Count", "the number of targets", q => "there are " + q + " targets"]] : [];
  // On a roll, the target's characteristics too ("Target.Intuition < 3" is common in potency-style options).
  const targetStats = ctx === "offer" || ctx === "tick" ? CHARS.map(c => ["Target." + c[1], "the target's " + c[1], q => "the target's " + c[1] + " is " + q]) : [];
  return castStats.concat(targetStats, [["Size", "your size", q => "your size is " + q]], [["Victories", "your Victories", q => "you have " + q + " Victories"], ["Level", "your level", q => "your level is " + q],
    ...CHARS.map(c => [c[1], "your " + c[1], q => "your " + c[1] + " is " + q]),
    ["Stamina", "your Stamina", q => "your Stamina is " + q],
    ["Recoveries Available to Spend", "your Recoveries left", q => "you have " + q + " Recoveries left"],
    ["Heroic Resources Available to Spend", "your " + r, q => "you have " + q + " " + r],
    ["Heroic Resources This Turn", "the most " + r + " you've had this turn", q => "you have had " + q + " " + r + " this turn"],
    ["Combat Round", "the combat round", q => "the combat round is " + q]]);
}
/* Yes/no facts about you: [type, block text, GoblinScript, book wording, negated book wording, negated block text]. */
const TEST_FACTS = [["strained", "You are Strained", "Strained", "you are Strained", "you are not Strained", "You are not Strained"],
  ["winded", "You are winded", "Stamina <= Maximum Stamina / 2", "you are winded", "you are not winded", "You are not winded"],
  ["dying", "You are dying", "Dying", "you are dying", "you are not dying", "You are not dying"],
  ["turn", "It is your turn", "Your Turn", "it is your turn", "it is not your turn", "It is not your turn"],
  ["combat", "You are in combat", "Combat Round > 0", "you are in combat", "you are not in combat", "You are not in combat"],
  ["saveends", "You have a save-ends effect", "Save Ends Effects", "you have a save-ends effect", "you don't have a save-ends effect", "You don't have a save-ends effect"]];
const fact = t => TEST_FACTS.find(x => x[0] === t);
/* Roll tests ("Offered when", "Automatically selected when" on a roll block) can also look at the
   ability being rolled and its target: [key, block text, GoblinScript, book wording, negated]. */
const ABILITY_FACTS = [["damage", "The ability deals damage", "Ability.DoesDamage", "the ability deals damage", "the ability doesn't deal damage"],
  ["signature", "It's a signature ability", "Ability.Categorization = \"Signature Ability\"", "it's a signature ability", "it isn't a signature ability"],
  ["heroic", "It's a heroic ability", "Ability.Categorization = \"Heroic Ability\"", "it's a heroic ability", "it isn't a heroic ability"],
  ["main", "It uses a main action", "Ability.Main Action", "it uses a main action", "it doesn't use a main action"],
  ["maneuver", "It's a maneuver", "Ability.Maneuver", "it's a maneuver", "it isn't a maneuver"],
  ["forced", "It force moves a creature", "Ability.HasForcedMovement", "it force moves a creature", "it doesn't force move a creature"],
  ["freestrike", "It's a free strike", "Ability.Free Strike", "it's a free strike", "it isn't a free strike"]];
const TARGET_FACTS = [["enemy", "The target is an enemy", "not Friends(Self, Target)", "the target is an enemy", "the target isn't an enemy"],
  ["ally", "The target is an ally", "Friends(Self, Target)", "the target is an ally", "the target isn't an ally"],
  ["smaller", "The target is no bigger than you", "Target.Size <= Size", "the target is no bigger than you", "the target is bigger than you"],
  ["saveends", "The target has a save-ends effect", "Target.Save Ends Effects", "the target has a save-ends effect", "the target doesn't have a save-ends effect"],["winded", "The target is winded", "Target.Winded", "the target is winded", "the target isn't winded"],
  ["concealed", "The target is concealed", "Target.Concealed or (Target.Conditions has \"concealment\")", "the target is concealed", "the target isn't concealed"],
  ["cover", "The target has cover", "Target.HasCover", "the target has cover", "the target doesn't have cover"],
  ["minion", "The target is a minion", "Target.Minion", "the target is a minion", "the target isn't a minion"]];
const abFact = k => ABILITY_FACTS.find(x => x[0] === k), tgFact = k => TARGET_FACTS.find(x => x[0] === k);
const isNum = v => /^-?\d+(\.\d+)?$/.test(String(v).trim());
/* The engine formula for a test (an empty test counts as true, but the status column flags it). */
function testGs(x) {
  if (!x) return "1";
  const wrap = y => (y && (y.t === "all" || y.t === "any" || y.t === "raw" || y.t === "winded" || y.t === "cmp" || y.t === "nearby" || y.t === "tgDist" || (y.t === "tg" && / or |<=/.test(testGs(y))))) ? "(" + testGs(y) + ")" : testGs(y);
  switch (x.t) {
    case "cond": return "Conditions has \"" + x.c + "\"";
    case "ab": return (abFact(x.k) || [0, 0, "1"])[2];
    case "abKw": return "Ability.Keywords has \"" + x.kw + "\"";
    case "abName": return "Ability.Name = \"" + (x.name || "") + "\"";
    case "tg": return (tgFact(x.k) || [0, 0, "1"])[2];
    case "tgCond": return "Target.Conditions has \"" + x.c + "\"";
    case "effect": return "Ongoing Effects has \"" + (x.name || "") + "\"";
    case "tgEffect": return "Target.Ongoing Effects has \"" + (x.name || "") + "\"";
    case "tgKw": return "Target.Keywords has \"" + (x.kw || "") + "\"";
    case "tgDist": return "Distance(Target) <= " + (isNum(x.n) ? String(x.n).trim() : "(" + (x.n || "1") + ")");
    case "nearby": return "Count Nearby " + x.kind + "(" + (x.r || "1") + ") " + x.op + " " + (x.n || "1");
    case "adjFeature": return "AdjacentAlliesWithFeature(\"" + (x.name || "") + "\")";
    case "cmp": return x.a + " " + x.op + " " + (isNum(x.n) ? String(x.n).trim() : "(" + (x.n || "0") + ")");
    case "not": return "not " + wrap(x.a);
    case "all": case "any": return x.items.map(wrap).join(x.t === "all" ? " and " : " or ");
    case "raw": return x.src || "1";
    default: return fact(x.t) ? fact(x.t)[2] : "1";
  }
}
/* The book wording for a test ("you have 5 or more Victories"); neg gives the opposite. */
function testProse(x, neg) {
  if (!x) return neg ? "a condition is not met" : "a condition is met";
  switch (x.t) {
    case "cond": return "you are " + (neg ? "not " : "") + String(x.c).toLowerCase();
    case "ab": return (abFact(x.k) || [])[neg ? 4 : 3] || "";
    case "abKw": return "the ability " + (neg ? "doesn't have" : "has") + " the " + x.kw + " keyword";
    case "abName": return "the ability is " + (neg ? "not " : "") + (x.name || "(no ability picked)");
    case "tg": return (tgFact(x.k) || [])[neg ? 4 : 3] || "";
    case "tgCond": return "the target is " + (neg ? "not " : "") + String(x.c).toLowerCase();
    case "effect": return "you " + (neg ? "don't have" : "have") + " the " + (x.name || "(no effect named)") + " effect";
    case "tgEffect": return "the target " + (neg ? "doesn't have" : "has") + " the " + (x.name || "(no effect named)") + " effect";
    case "tgKw": return "the target " + (neg ? "doesn't have" : "has") + " the " + (x.kw || "(no keyword)") + " keyword";
    case "tgDist": return "the target is " + (neg ? "more than " : "within ") + (x.n || "1") + (+x.n === 1 ? " square" : " squares") + (neg ? " from you" : " of you");
    case "nearby": { const one = +x.n === 1, w = { Enemies: one ? "enemy" : "enemies", Friends: one ? "ally" : "allies", Creatures: one ? "creature" : "creatures" }[x.kind];
      const q = (TEST_OP_PROSE[neg ? TEST_OP_FLIP[x.op] : x.op] || (n => n))(x.n || "1"); return "there " + (one ? "is " : "are ") + q + " " + w + " within " + (x.r || "1") + (+x.r === 1 ? " square" : " squares") + " of you"; }
    case "adjFeature": return (neg ? "no ally adjacent to you has" : "an ally adjacent to you has") + " the " + (x.name || "(no feature named)") + " feature";
    case "cmp": { const s = testStats("offer").find(y => y[0] === x.a), op = neg ? TEST_OP_FLIP[x.op] : x.op;
      const q = (TEST_OP_PROSE[op] || (n => (op === "<" ? "less than " : "more than ") + n))(x.n || "0");
      return s ? s[2](q) : x.a + " is " + q; }
    case "not": return testProse(x.a, !neg);
    case "all": case "any": { const parts = x.items.map(y => testProse(y)); const j = listWords(parts, x.t === "all" ? "and" : "or");
      return neg ? (x.t === "all" ? "not all of these are true: " : "none of these are true: ") + j : j; }
    case "raw": return neg ? "a condition is not met" : "a condition is met";
    default: return fact(x.t) ? fact(x.t)[neg ? 4 : 3] : "";
  }
}
/* True when the test, or any test inside it, still needs picking. */
const testMissing = x => !x || (x.t === "not" && testMissing(x.a)) || ((x.t === "all" || x.t === "any") && x.items.some(testMissing)) || (x.t === "abName" && !x.name) || ((x.t === "effect" || x.t === "tgEffect" || x.t === "adjFeature") && !x.name) || (x.t === "tgKw" && !x.kw);
/* Draws parent[key] (a test, or an empty "+ test" slot). parent may be an array (an all/any list). */
function renderTest(parent, key, required, ctx) {
  const x = parent[key];
  if (!x) {
    const b = fk(E("button", "empty-test" + (required ? " required" : ""), "+ test"), "test:" + objKey(parent) + ":" + key); b.type = "button";
    b.addEventListener("click", ev => { ev.stopPropagation(); openTestPicker(b, parent, key, ctx); });
    return b;
  }
  const e = E("span", "x" + (x.t === "all" || x.t === "any" ? " list" : "")); const add = n => e.appendChild(n);
  const clear = () => { const c = E("button", "clear", "✕"); c.type = "button"; c.title = "Remove this test"; c.setAttribute("aria-label", "Remove this test");
    c.addEventListener("click", ev => { ev.stopPropagation(); change(() => { if (Array.isArray(parent) && parent.length > 2) parent.splice(key, 1); else parent[key] = null; }); }); return c; };
  switch (x.t) {
    case "cond": add(lbl("You are")); add(pickTok(x, "c", T.conditions.map(c => [c[1], c[1].toLowerCase()]))); break;
    case "ab": add(lbl((abFact(x.k) || [0, x.k])[1])); break;
    case "abKw": add(lbl("It has the")); add(pickTok(x, "kw", KEYWORDS.map(k => [k, k]))); add(lbl("keyword")); break;
    case "abName": add(lbl("The ability is")); add(abilityNameTok(x)); break;
    case "tg": add(lbl((tgFact(x.k) || [0, x.k])[1])); break;
    case "tgCond": add(lbl("The target is")); add(pickTok(x, "c", T.conditions.map(c => [c[1], c[1].toLowerCase()]))); break;
    case "effect": add(lbl("You have the")); add(effectTok(x)); add(lbl("effect")); break;
    case "tgEffect": add(lbl("The target has the")); add(effectTok(x)); add(lbl("effect")); break;
    case "tgKw": add(lbl("The target has the")); add(textTok(x, "kw", "Undead")); add(lbl("keyword")); break;
    case "tgDist": add(lbl("The target is within")); add(textTok(x, "n", "1")); add(lbl(+x.n === 1 ? "square of you" : "squares of you")); break;
    case "nearby": add(lbl("There are")); add(pickTok(x, "op", [[">=", "at least"], ["<=", "at most"], ["=", "exactly"]])); add(textTok(x, "n", "1"));
      add(pickTok(x, "kind", [["Enemies", "enemies"], ["Friends", "allies"], ["Creatures", "creatures"]])); add(lbl("within")); add(textTok(x, "r", "1")); add(lbl("squares of you")); break;
    case "adjFeature": add(lbl("An ally adjacent to you has the")); add(textTok(x, "name", "feature name")); add(lbl("feature")); break;
    case "cmp": add(pickTok(x, "a", testStats(ctx).map(s => [s[0], s[1]]))); add(pickTok(x, "op", TEST_OPS)); add(textTok(x, "n", "0")); break;
    case "not": {
      // "Not [You are Strained]" reads as one test: "You are not Strained". Numbers and lists keep the "Not".
      const y = x.a;
      if (y && fact(y.t)) { add(lbl(fact(y.t)[5])); break; }
      if (y && y.t === "cond") { add(lbl("You are not")); add(pickTok(y, "c", T.conditions.map(c => [c[1], c[1].toLowerCase()]))); break; }
      add(lbl("Not")); add(renderTest(x, "a", false, ctx)); break;
    }
    case "raw": add(lbl("Formula")); add(textTok(x, "src", "GoblinScript test", 30)); break;
    case "all": case "any": {
      const head = E("div", "listhead", x.t === "all" ? "All of these are true" : "Any of these is true"); head.appendChild(clear()); add(head);
      x.items.forEach((y, i) => { const it = E("div", "item"); it.appendChild(E("span", "bullet", x.t === "all" ? "and" : "or")); it.appendChild(renderTest(x.items, i, false, ctx)); e.appendChild(it); });
      const more = fk(E("button", "addtest", "+ test"), "testmore:" + objKey(x)); more.type = "button";
      more.addEventListener("click", ev => { ev.stopPropagation(); change(() => x.items.push(null)); }); add(more);
      return e;
    }
    default: add(lbl(fact(x.t) ? fact(x.t)[1] : x.t));
  }
  add(clear()); return e;
}
/* A searchable list of the compendium's ongoing effects (1,000+, so typed to filter, never one long menu). */
function effectTok(x) {
  const all = T.effects || [];
  return tok(x.name || "choose an effect", b => menuAt(b, m => {
    m.classList.add("wide");
    const i = E("input", "filter"); i.placeholder = "Search effects, e.g. Marked"; i.value = x.name || ""; m.appendChild(i);
    const list = E("div"); m.appendChild(list);
    const pick = n => { closeMenu(); change(() => { x.name = n; }); };
    const draw = () => {
      list.innerHTML = ""; const q = i.value.trim().toLowerCase();
      const hits = all.filter(e => !q || e[1].toLowerCase().includes(q)).slice(0, 40);
      hits.forEach(e => { const o = E("button", null, e[1]); o.type = "button"; o.addEventListener("click", () => pick(e[1])); list.appendChild(o); });
      if (!hits.length) list.appendChild(E("div", "hint", "No effect in the compendium matches. Press Enter to use the name as typed."));
      else if (all.filter(e => e[1].toLowerCase().includes(q)).length > 40) list.appendChild(E("div", "hint", "Keep typing to narrow the list."));
    };
    i.addEventListener("input", draw);
    i.addEventListener("keydown", ev => { if (ev.key === "Enter") { ev.preventDefault(); const q = i.value.trim(), hit = all.find(e => e[1].toLowerCase() === q.toLowerCase()); if (q) pick(hit ? hit[1] : q); } });
    draw();
  }), !x.name, objKey(x) + ":name");
}
const isCompendiumEffect = n => (T.effects || []).some(e => e[1].toLowerCase() === String(n || "").toLowerCase());
/* The test picker: grouped ready-made tests with a search, as in the ability editor. */
function openTestPicker(anchor, parent, key, ctx) {
  const r = resWord(), set = make => { closeMenu(); change(() => { parent[key] = make(); }); };
  const cmp = (a, n) => () => ({ t: "cmp", a, op: ">=", n });
  const roll = ctx === "offer" || ctx === "tick";
  const CONDS_WORDS = T.conditions.map(c => c[1]).join(" ");   // so searching "slowed" finds the condition tests
  // On a roll block the ability and its target come first: they are what roll options test most.
  const rollGroups = !roll ? [] : [
    ["The ability", "What the roll is for: keywords, a named ability, damage, signature...", [["It has the [Strike] keyword", () => ({ t: "abKw", kw: "Strike" })], ["The ability is [ ]", () => ({ t: "abName", name: "" }), "Pick it from a list."]]
      .concat(ABILITY_FACTS.map(a => [a[1], () => ({ t: "ab", k: a[0] })]))],
    ["The target", "The creature the ability is used against.", [["The target has a condition", () => ({ t: "tgCond", c: "Prone" }), "", CONDS_WORDS]]
      .concat(TARGET_FACTS.map(a => [a[1], () => ({ t: "tg", k: a[0] })]))
      .concat([["The target is within [1] square of you", () => ({ t: "tgDist", n: "1" })], ["The target has the [Undead] keyword", () => ({ t: "tgKw", kw: "Undead" }), "A creature keyword."],
        ["The target has the [ ] effect", () => ({ t: "tgEffect", name: "" }), "An ongoing effect, by name."], ["The target's Might is at least [ ]", cmp("Target.Might", "2"), "Any characteristic: change Might after."]])],
  ].concat(ctx === "offer" ? [["The roll", "How many creatures the ability targets.", [["There are fewer than [2] targets", () => ({ t: "cmp", a: "Cast.Target Count", op: "<", n: "2" })]]]] : []);
  // Combining tests (all of, any of, not) is how most tests start, so it leads the list.
  const groups = [["Combine tests", "Need several things at once, or any one of them.", [["All of these are true", () => ({ t: "all", items: [null, null] }), "Every test must pass."],
      ["Any of these is true", () => ({ t: "any", items: [null, null] }), "At least one test must pass."], ["Not [ ]", () => ({ t: "not", a: null }), "True when the test inside is false."]]]].concat(rollGroups).concat([
    ["Strained (Talent)", "Whether you are, or are not, Strained.", [["You are Strained", () => ({ t: "strained" })], ["You are not Strained", () => ({ t: "not", a: { t: "strained" } })]]],
    ["Check a condition", "Prone, slowed, grabbed, and so on: pick which in the block.", [["You have a condition", () => ({ t: "cond", c: "Prone" }), "", CONDS_WORDS],
      ["You don't have a condition", () => ({ t: "not", a: { t: "cond", c: "Prone" } }), "", CONDS_WORDS]]],
    ["Check health", "Winded, dying, or how much Stamina is left.", [["You are winded", () => ({ t: "winded" }), "Stamina is at half or less."],
      ["Your Stamina is at most [ ]", () => ({ t: "cmp", a: "Stamina", op: "<=", n: "10" })], ["You are dying", () => ({ t: "dying" })]]],
    ["Check effects", "Ongoing effects and effects a saving throw can end.", [["You have the [ ] effect", () => ({ t: "effect", name: "" }), "An ongoing effect, by name."],
      ["You have a save-ends effect", () => ({ t: "saveends" })]]],
    ["Check what's nearby", "Creatures close to you.", [["There are at least [1] enemies within [1] squares of you", () => ({ t: "nearby", kind: "Enemies", op: ">=", n: "1", r: "1" }), "Also allies or any creatures."],
      ["An ally adjacent to you has the [ ] feature", () => ({ t: "adjFeature", name: "" }), "Such as Shield? Shield!"]]],
    ["Check the moment", "Whose turn it is, or whether you're in combat.", [["It is your turn", () => ({ t: "turn" })], ["You are in combat", () => ({ t: "combat" })]]],
    ["Compare a number", "Victories, level, characteristics, your " + r + "...", [["Your level is at least [ ]", cmp("Level", "5")], ["Your Might is at least [ ]", cmp("Might", "2"), "Any characteristic: change Might after."],
      ["The most " + r + " you've had this turn is at least [ ]", cmp("Heroic Resources This Turn", "4")], ["Your Victories are at least [ ]", cmp("Victories", "3")],
      ["Your " + r + " is at least [ ]", cmp("Heroic Resources Available to Spend", "3")], ["The combat round is at least [ ]", cmp("Combat Round", "2")],
      ["Your Recoveries left are at least [ ]", cmp("Recoveries Available to Spend", "1")], ["Your size is at most [ ]", () => ({ t: "cmp", a: "Size", op: "<=", n: "1" })]]],
  ]);
  // Combining tests leads; the rest go by how often compendium formulas use them (2026-11-23 count).
  const BY_USE = ["Combine tests", "The ability", "The target", "Compare a number", "Check health", "Check a condition", "Check effects", "Check what's nearby", "Check the moment", "The roll", "Strained (Talent)"];
  groups.sort((x, y) => BY_USE.indexOf(x[0]) - BY_USE.indexOf(y[0]));
  menuAt(anchor, m => {
    m.classList.add("picker");
    const head = ctx === "offer" ? ["Offered when", "The option shows on a roll only while this is true."]
      : ctx === "tick" ? ["Automatically selected when", "The option starts selected when this is true. The player can always change it."]
      : ["Only if", "The blocks inside apply only while this is true for the hero with this feature."];
    const ph = E("div", "ph"); ph.appendChild(E("div", "t", head[0]));
    ph.appendChild(E("p", null, head[1]));
    const search = E("input"); search.placeholder = "What do you want to check? e.g. prone, winded, level"; search.setAttribute("aria-label", "Search tests"); ph.appendChild(search); m.appendChild(ph);
    const pb = E("div", "pb"); m.appendChild(pb); const expanded = new Set();
    const draw = () => {
      pb.innerHTML = ""; const q = search.value.trim().toLowerCase(); let n = 0;
      groups.forEach(([g, gd, opts]) => {
        const vis = opts.filter(o => !q || (g + " " + o[0] + " " + (o[2] || "") + " " + (o[3] || "")).toLowerCase().includes(q)); if (!vis.length) return;
        const gh = E("div", "grp", g); gh.appendChild(E("span", "gd", gd)); pb.appendChild(gh);
        const cap = !q && !expanded.has(g) && vis.length > 4;
        (cap ? vis.slice(0, 3) : vis).forEach(o => { const b = E("button", "opt"); b.type = "button"; b.appendChild(E("span", "chip", o[0])); if (o[2]) b.appendChild(E("span", "d", o[2]));
          b.addEventListener("click", () => set(o[1])); pb.appendChild(b); n++; });
        if (cap) { const more = E("button", "opt more", "Show " + (vis.length - 3) + " more"); more.type = "button"; more.addEventListener("click", ev => { ev.stopPropagation(); expanded.add(g); draw(); }); pb.appendChild(more); }
      });
      if (!n) pb.appendChild(E("p", "note", "Nothing matches. You can type a formula below."));
    };
    search.addEventListener("input", draw); draw();
    const tb = E("details", "typebox"); tb.appendChild(E("summary", null, "Type a formula instead"));
    tb.appendChild(gsDocLink());
    const ta = E("textarea"); ta.spellcheck = false; ta.setAttribute("aria-label", "GoblinScript formula"); ta.placeholder = "e.g. Victories >= 3 and not Strained"; tb.appendChild(ta);
    const use = E("button", "btn small", "Use this formula"); use.type = "button"; use.addEventListener("click", () => { const src = ta.value.trim(); if (src) set(() => ({ t: "raw", src })); }); tb.appendChild(use);
    m.appendChild(tb);
  });
}
/* GoblinScript reference: opens goblinscript.html (built from GoblinScript_Guide.md) in a panel over
   the editor, so nothing being edited is lost. Escape or Close shuts it. */
let gsDocEl = null;
function openGsDoc() {
  if (gsDocEl) return;
  gsDocEl = document.createElement("div"); gsDocEl.className = "gsdoc"; gsDocEl.setAttribute("role", "dialog"); gsDocEl.setAttribute("aria-label", "GoblinScript reference");
  // Clicks in the panel must not close the formula menu underneath it.
  ["click", "pointerdown", "mousedown"].forEach(t => gsDocEl.addEventListener(t, ev => ev.stopPropagation()));
  const bar = document.createElement("div"); bar.className = "gsdoc-bar"; bar.textContent = "GoblinScript reference";
  const x = document.createElement("button"); x.type = "button"; x.className = "btn"; x.textContent = "Close"; x.addEventListener("click", closeGsDoc); bar.appendChild(x);
  const f = document.createElement("iframe"); f.src = "goblinscript.html"; f.title = "GoblinScript reference";
  gsDocEl.appendChild(bar); gsDocEl.appendChild(f); document.body.appendChild(gsDocEl); x.focus();
}
function closeGsDoc() { if (gsDocEl) { gsDocEl.remove(); gsDocEl = null; } }
window.addEventListener("keydown", ev => { if (ev.key === "Escape" && gsDocEl) { ev.stopImmediatePropagation(); ev.preventDefault(); closeGsDoc(); } }, true);
/* The link under "Type a formula instead". */
function gsDocLink() {
  const a = document.createElement("button"); a.type = "button"; a.className = "doclink"; a.textContent = "GoblinScript reference \u2197";
  a.title = "What you can write in a formula: fields, functions, operators";
  a.addEventListener("click", ev => { ev.preventDefault(); ev.stopPropagation(); openGsDoc(); });
  return a;
}
/* Older saves picked one of six fixed tests; turn them into test blocks. */
function migrateOnlyIf(f) {
  if (f.cond !== undefined) return f;
  const n = f.n || "0", t = f.test;
  const cond = t === "victories" ? { t: "cmp", a: "Victories", op: ">=", n } : t === "level" ? { t: "cmp", a: "Level", op: ">=", n: f.n || "1" }
    : t === "hrturn" ? { t: "cmp", a: "Heroic Resources This Turn", op: ">=", n } : t === "winded" ? { t: "winded" } : t === "strained" ? { t: "strained" }
    : t === "formula" ? (f.formula ? { t: "raw", src: f.formula } : null) : null;
  return { cond };
}
// Outcome changes (power modifier modtypes as content uses them).
/* Which tests a roll block applies to: a characteristic ("Might tests", saved as the modifier's
   attribute; "all" when blank) and skills. Used by the edge and outcome blocks. */
// The edge block's modifications (MCDMAbilityRollBehavior s_modificationTypes): edges and banes, removing
// or ignoring them, and flat bonuses.
const EDGE_OPTS = [["edge", "an edge"], ["double_edge", "a double edge"], ["bane", "a bane"], ["double_bane", "a double bane"],
  ["remove_bane", "a bane removed"], ["remove_edge", "an edge removed"], ["ignore_banes", "banes ignored"], ["ignore_edges", "edges ignored"],
  ["plusone", "a +1 bonus"], ["plustwo", "a +2 bonus"], ["plusthree", "a +3 bonus"], ["minusone", "a -1 penalty"], ["minustwo", "a -2 penalty"], ["minusthree", "a -3 penalty"]];
const TEST_CHARS = [["", "any"]].concat(CHARS.map(c => [c[0], c[1]]));
/* "[Might] [tests] using [Jump]" or "[Strike] [ability rolls]": the word "tests" / "ability rolls" is itself
   the switch between the two. */
const ROLL_ON = [["tests", "tests"], ["opposed", "opposed tests"], ["abilities", "ability rolls"], ["all", "power rolls"]];
const ROLL_TYPE = { tests: "test_power_roll", opposed: "opposed_power_roll", abilities: "ability_power_roll", all: "all" };
const onTests = f => f.on === "tests" || f.on === "opposed";
function rollsPhrase(f, add) {
  if (onTests(f)) { add(pickTok(f, "attr", TEST_CHARS, "any")); add(pickTok(f, "on", ROLL_ON)); add(lbl("using")); add(multiTok(f, "skills", T.skills.map(s => [s[0], s[1]]), "any skill")); }
  else { add(multiTok(f, "keywords", KEYWORDS.map(k => [k, k]), "any", "and")); add(pickTok(f, "on", ROLL_ON)); }
}
const testsProse = f => (f.attr ? lookupName(CHARS, f.attr) + " " : "") + "tests" + (f.skills.length ? " using " + listWords(f.skills.map(i => lookupName(T.skills, i))) : "");
const testsFields = f => Object.assign({ skills: f.skills.length ? f.skills.slice() : undefined }, f.attr ? { attribute: f.attr } : {});
// Some saved ability-roll records also carry a characteristic; the engine ignores it there, but it is kept.
const rollFields = f => onTests(f) ? testsFields(f) : (f.attr ? { attribute: f.attr } : {});
const FM_KINDS = [["push", "push"], ["pull", "pull"], ["slide", "slide"]];
const OUTCOMES = [["tier3", "have a tier 3 outcome"], ["nottierone", "can't have a tier 1 outcome"], ["tierup", "are improved by one tier"], ["tierdown", "are worsened by one tier"], ["nottierthree", "can't have a tier 3 outcome"], ["tier1", "have a tier 1 outcome"]];
/* Usage limits: "Usable [1] time [per round]" (the modifier's resourceRefreshType and numCharges).
   "respite" is the engine's long rest; "victory" refreshes when you earn a Victory. */
const LIMITS = [["none", "any number of times"], ["turn", "per turn"], ["round", "per round"], ["encounter", "per encounter"], ["long", "per respite"], ["victory", "until you earn a Victory"]];
function usagePhrase(f, add) {
  const row = E("div", "usage"); row.appendChild(lbl("Usable"));
  if (f.limit && f.limit !== "none") { if (f.uses == null) f.uses = "1"; row.appendChild(textTok(f, "uses", "1")); row.appendChild(lbl(+f.uses === 1 ? "time" : "times")); }
  row.appendChild(pickTok(f, "limit", LIMITS, "any number of times")); add(row);
}
function usageFields(r, f) {
  if (f.limit && f.limit !== "none") { r.resourceRefreshType = f.limit; if (String(f.uses || "1") !== "1") r.numCharges = numOr(f.uses); }
  return r;
}
const omit = (o, ks) => { ks.forEach(k => delete o[k]); return o; };
/* The feature record a companion / summoner wrapper holds: a saved one keeps its own fields. */
const wrapFeature = (src, inner, feat) => Object.assign(src && src.feature ? omit(clone(src.feature), ["modifiers"]) : { __typeName: "CharacterFeature", name: feat.name, description: feat.text || "" }, { modifiers: inner });
const blankOption = name => ({ id: newId("f"), kind: "feature", name, text: "", sentences: [] });
const AURA_WHO = [["selfandfriends", "You and each ally"], ["friends", "Each ally"], ["enemies", "Each enemy"], ["all", "Each creature"], ["allother", "Each other creature"]];
const numOr = v => /^-?\d+$/.test(String(v).trim()) ? +v : String(v).trim();
/* The two roll-option lines under a roll block. "Offered when" decides whether the option shows on a
   roll at all (displayCondition; empty = every matching roll). "Automatically selected" decides
   whether it starts selected (activationCondition). Logic around the block is the early exit (filterCondition). */
const ROLL_REQS = [["none", "any roll"], ["surges", "rolls with surges"], ["edge", "rolls with an edge"], ["doubleedge", "rolls with a double edge"], ["bane", "rolls with a bane"],
  ["doublebane", "rolls with a double bane"], ["noedge", "rolls with no edge"], ["nobane", "rolls with no bane"], ["skilled", "tests using a skill you have"], ["unskilled", "tests using a skill you don't have"]];
function appliesPhrase(f, add) {
  const off = E("div", "usage"); off.appendChild(lbl("Offered when")); off.appendChild(renderTest(f, "offer", false, "offer"));
  if (!f.offer && (!f.req || f.req === "none")) off.appendChild(E("span", "aside", "(every matching roll)"));
  // The engine's roll requirement: offered only on rolls that have surges, an edge, no bane...
  off.appendChild(lbl("on")); off.appendChild(pickTok(f, "req", ROLL_REQS, "any roll"));
  add(off);
  const tk = E("div", "usage"); tk.appendChild(lbl("Automatically selected"));
  tk.appendChild(pickTok(f, "applies", [["always", "always"], ["when", "when"], ["choose", "never (the player chooses)"], ["cost", "always, and it costs"], ["choosecost", "never (the player chooses), and it costs"]]));
  if (f.applies === "when") tk.appendChild(renderTest(f, "tick", true, "tick"));
  if (f.applies === "cost" || f.applies === "choosecost") { if (f.costN == null) f.costN = "1"; tk.appendChild(textTok(f, "costN", "1")); tk.appendChild(pickTok(f, "costRes", [["cost", resWord()], ["surges", "surges"], ["epic", (cls.epicName || "epic resource").toLowerCase()]], resWord())); }
  add(tk);
}
function appliesFields(f) {
  // "1" is always selected: the offer test already decides when it shows, so the test isn't repeated.
  // displayCondition defaults to "" (every matching roll) on the type, so it is written only when set.
  const shown = Object.assign(f.offer ? { displayCondition: testGs(f.offer) } : {}, f.req && f.req !== "none" ? { rollRequirement: f.req } : {});
  // "Always" is stored as true and "never" as false, as the engine stores them (MCDModifyPowerRolls.lua).
  if (f.applies === "cost" || f.applies === "choosecost") return Object.assign(shown, { activationCondition: f.applies === "cost", resourceCostType: f.costRes || "cost", resourceCostAmount: String(f.costN || "1") });
  if (f.applies === "when") return Object.assign(shown, { activationCondition: testGs(f.tick) });
  return Object.assign(shown, { activationCondition: f.applies === "always" });
}
const appliesProse = f => (f.offer ? " when " + testProse(f.offer) : "") + (f.req && f.req !== "none" ? " (only on " + lookupName(ROLL_REQS, f.req) + ")" : "") + (f.applies === "when" ? " (it applies automatically when " + testProse(f.tick) + ")" : "") + appliesProseCost(f);
const appliesProseCost = f => f.applies === "choose" ? " (you choose when to use this)" : f.applies === "choosecost" ? " (you can choose to spend " + (f.costN || 1) + " " + (f.costRes === "surges" ? (+f.costN === 1 ? "surge" : "surges") : f.costRes === "epic" ? (cls.epicName || "epic resource").toLowerCase() : resWord()) + " when you roll)" : f.applies === "cost" ? " if you spend " + (f.costN || 1) + " " + (f.costRes === "surges" ? (+f.costN === 1 ? "surge" : "surges") : f.costRes === "epic" ? (cls.epicName || "epic resource").toLowerCase() : resWord()) + " when you roll" : "";
/* One option of an ability choice: an ability, or a triggered ability (with its card). An option
   opened from a saved class is written back as saved while unchanged; once edited it keeps the
   saved option's other fields and records (e.g. a second trigger). */
const optionSnap = o => srcHash({ r: o.rec, d: o.display || null });
function abilityOption(o) {
  if (o.src && o.snap === optionSnap(o)) return clone(o.src);
  const mods = o.trig ? [clone(o.rec)].concat(o.display ? [clone(o.display)] : [], clone(o.extra || []))
    : [o.src ? Object.assign(clone(o.src.modifiers[0]), { activatedAbility: clone(o.rec) }) : { __typeName: "CharacterModifier", behavior: "activated", name: "Ability", description: "", activatedAbility: o.rec }];
  const base = { __typeName: "CharacterFeature", name: recName(o.rec), description: "", tags: { Ability: true }, modifiers: mods };
  return o.src ? Object.assign(clone(o.src), { modifiers: mods }) : base;   // a saved option keeps its own name
}
/* Combining roll changes. A block can join a combined block when it changes ability rolls: same
   keywords, and at most one edge/bane/outcome change between them (one power modifier holds one). */
const ROLL_OPT_KEYS = ["offer", "applies", "tick", "costN", "costRes"];
const comboKey = s => { const d = SENT[s.type]; if (!(d.combo || d.comboHost) || (s.type === "edge" && s.f.on === "tests")) return null; return (s.f.keywords || []).slice().sort().join("|"); };
const comboModtypes = s => SENT[s.type].comboHost ? s.children.map(comboModtypes).flat() : (SENT[s.type].combo.modtype ? [SENT[s.type].combo.modtype(s.f)] : []);
/* Groups of sibling blocks that could be one combined block: [[id, id, ...], ...]. */
function combinableGroups(list) {
  const byKey = new Map();
  list.forEach(s => { const k = comboKey(s); if (k == null) return; if (!byKey.has(k)) byKey.set(k, []); byKey.get(k).push(s); });
  const out = [];
  byKey.forEach(members => {
    let mods = 0, hosts = 0; const pick = [];
    members.forEach(s => { const m = comboModtypes(s).length, h = SENT[s.type].comboHost ? 1 : 0; if (mods + m > 1 || hosts + h > 1) return; mods += m; hosts += h; pick.push(s.id); });
    if (pick.length > 1) out.push(pick);
  });
  return out;
}
function combineBlocks(list, ids) {
  const members = list.filter(s => ids.includes(s.id)); if (members.length < 2) return;
  let host = members.find(s => SENT[s.type].comboHost);
  const first = members.find(s => !SENT[s.type].comboHost);
  const differ = members.some(s => !SENT[s.type].comboHost && ROLL_OPT_KEYS.some(k => JSON.stringify(s.f[k]) !== JSON.stringify((host || first).f[k])));
  change(() => {
    const at = list.indexOf(members[0]);
    if (!host) { host = makeSentence("rollCombo"); host.f.keywords = (first.f.keywords || []).slice(); ROLL_OPT_KEYS.forEach(k => { if (first.f[k] !== undefined) host.f[k] = JSON.parse(JSON.stringify(first.f[k])); }); }
    members.filter(s => s !== host).forEach(s => { list.splice(list.indexOf(s), 1); host.children.push(s); });
    if (!list.includes(host)) list.splice(Math.min(at, list.length), 0, host);
  });
  if (differ) toast("Combined. The blocks had different roll options, so the combined block uses the first one's.", { label: "Undo", run: undo });
}
/* A block taken out of a combined block gets the shared keywords and roll options back. */
function uncombine(host, child) { child.f.keywords = (host.f.keywords || []).slice(); ROLL_OPT_KEYS.forEach(k => { child.f[k] = host.f[k] === undefined ? undefined : JSON.parse(JSON.stringify(host.f[k])); }); if (child.type === "edge") child.f.on = "abilities"; return child; }
/* The bracket at the left of a list: an arrow to each block that can combine, and a Combine button. */
function drawCombineBrackets(into, list, groups) {
  groups.forEach((ids, gi) => {
    const els = ids.map(id => into.querySelector(':scope > [data-value="' + CSS.escape(id) + '"]')).filter(Boolean); if (els.length < 2) return;
    const mids = els.map(e => e.offsetTop + Math.min(e.offsetHeight / 2, 16)), top = Math.min(...mids), bot = Math.max(...mids);
    const br = E("div", "cbr"); br.style.top = top + "px"; br.style.height = (bot - top) + "px"; br.style.left = (2 + gi * 4) + "px"; into.appendChild(br);
    mids.forEach(y => { const a = E("div", "cbar"); a.style.top = (y - 1) + "px"; a.style.left = (2 + gi * 4) + "px"; into.appendChild(a); });
    const b = E("button", "cbtn", "Combine"); b.type = "button"; b.title = "Combine these into one roll change (saved as one power roll modifier)";
    b.style.top = ((top + bot) / 2) + "px"; b.style.left = (gi * 4) + "px";
    b.addEventListener("click", ev => { ev.stopPropagation(); combineBlocks(list, ids); });
    into.appendChild(b);
  });
}
/* Surges from a roll change are, by default, for that roll only: any not spent are lost
   (the engine's surgesCanBeKept, "Surges can be Kept", is off). "that you keep" turns it on. */
const SURGE_KEEP = [["roll", "to use on this roll only"], ["keep", "that you keep"]];
const surgeKeepTok = f => pickTok(f, "keep", SURGE_KEEP, SURGE_KEEP[0][1]);
const surgeKeepProse = f => f.keep === "keep" ? " that you keep if unspent" : " that can only be used on that roll";
/* Which abilities a "Change an ability" block applies to: one by name, or (opened from a class) any
   formula such as 'Ability.Keywords has "Ranged"'. A saved formula is kept as written. */
const abilityNameOf = fl => (/^\s*Ability\.name\s*(?:=|is)\s*"?([^"]*?)"?\s*$/i.exec(fl || "") || [])[1];
const abilityFilterOf = f => f.filter && (abilityNameOf(f.filter) === f.name || (!f.name && !abilityNameOf(f.filter))) ? f.filter : 'Ability.name = "' + String(f.name).replace(/"/g, "") + '"';
function whichAbility(f, add) {
  if (f.filter && !abilityNameOf(f.filter) && !f.name) { add(lbl("abilities where")); add(textTok(f, "filter", "formula", 30)); }
  else { add(abilityNameTok(f)); add(lbl("ability")); }
}
function abilityNameTok(f) {
  const names = allAbilityNames();
  return tok(f.name || "choose an ability", b => menuAt(b, m => {
    m.appendChild(E("h5", null, "Abilities in this class"));
    if (!names.length) m.appendChild(E("div", "hint", "No abilities yet. Type a name below."));
    names.forEach(n => { const x = E("button", null, n); x.type = "button"; x.addEventListener("click", () => { closeMenu(); change(() => { f.name = n; }); }); m.appendChild(x); });
    const i = E("input", "filter"); i.placeholder = "or type a name (e.g. Free Strike)"; i.value = f.name || "";
    i.addEventListener("keydown", e => { if (e.key === "Enter") { closeMenu(); change(() => { f.name = i.value.trim(); }); } }); m.appendChild(i);
    m.appendChild(E("div", "hint", "Pick one of this class's abilities, or type the name of any ability."));
  }), !f.name);
}
function allAbilityNames() {
  const out = new Set();
  eachFeature(feat => {
    (feat.sentences || []).forEach(function walk(s) { if ((s.type === "ability" || s.type === "trigger") && s.f.rec) out.add(recName(s.f.rec));
      if (s.type === "abilityChoice") s.f.options.forEach(o => o.rec && out.add(recName(o.rec))); childLists(s).forEach(l => l.forEach(walk)); });
  });
  return [...out];
}
function newOption(f, feat) {
  openEditor({ rec: abilitySeed(f.cat, f.cost), kind: "ability" }, (rec, d, problems) => { f.options.push({ id: newId("o"), rec, problems }); });
}
const recName = rec => rec.__typeName === "CharacterModifier" ? ((rec.triggeredAbility || {}).name || rec.name) : rec.name;
/* The block lists inside a block: an Only if's children, or each row of a growing table. */
const childLists = s => s.children ? [s.children] : s.type === "growing" ? s.f.rows.map(r => r.blocks) : [];
const resWord = () => (cls && cls.resourceName || "resource").toLowerCase();
/* A row's text: its blocks in words. The sheet's short text is the first sentence, trimmed. */
function growRowProse(r) { return sentenceProse({ sentences: r.blocks }); }
function growRowShort(r) { const t = growRowProse(r); return t.length > 90 ? t.slice(0, 87).replace(/\s+\S*$/, "") + "\u2026" : t; }
function makeSentence(type) { const d = SENT[type]; return { id: newId("s"), type, f: d.make(), children: d.wrapper ? [] : undefined }; }

// ---------------------------------------------------------------------------------------------
// Features: a name, its book text, and blocks. Ready-made features are just pre-filled blocks; every
// block in them stays editable, and dragging one in copies it.
/* One shelf (critique alternative C): every block, plus a few recipes (several blocks, or a block with
   presets). Dropped on a level, an entry becomes a feature named after it; dropped into a feature, its
   blocks are added there. Authors' own recipes (saved features) join the shelf the same way. */
const RECIPES = [
  { key: "growing", label: "Growing table", group: "res", uses: 11, desc: "Rows at 2, 4 and 6, then 8 at 4th level, 10 at 7th and 12 at 10th: the same steps the core classes use.", name: () => "Growing " + (cls.resourceName || "Resource"),
    blocks: () => [["growing", { rows: [["2", "1"], ["4", "1"], ["6", "1"], ["8", "4"], ["10", "7"], ["12", "10"]].map(([at, level]) => ({ id: newId("r"), at, level, replaces: "", text: "", blocks: [] })) }]] },
  { key: "charinc", label: "Characteristic Increase", group: "stats", uses: 33, desc: "Your starting characteristics increase to 3, and the player raises one other score by 1.", name: "Characteristic Increase",
    blocks: () => primaryChars().map(c => ["stat", { attr: c, op: "max", value: "3" }]).concat([["charChoice"]]) },
  { key: "signature", label: "Signature ability", group: "abil", uses: 9, desc: "The player chooses one signature ability from a list you build.", name: "Signature Ability", blocks: () => [["abilityChoice", { cat: "signature" }]] },
  { key: "heroic", label: "Heroic ability choice", group: "abil", uses: 45, desc: "The player chooses one heroic ability costing N of your resource, from a list you build.", name: "", blocks: () => [["abilityChoice", { cat: "heroic" }]] },
];
/* An entry key is "s:<block type>", "r:<recipe>", "t:<your template id>" or "empty". */
function entryOf(key) {
  if (key === "empty") return { label: "Empty feature", name: "", blocks: () => [] };
  const [k, v] = [key.slice(0, 1), key.slice(2)];
  if (k === "s") { const d = SENT[v]; return { label: d.label, name: d.featName || "", blocks: () => [[v]], opens: d.opensEditor }; }
  if (k === "r") { const r = RECIPES.find(x => x.key === v); return r && { label: r.label, name: typeof r.name === "function" ? r.name() : r.name, blocks: r.blocks }; }
  if (k === "t") { const t = (store.templates || []).find(x => x.id === v); return t && { label: t.name, template: t }; }
  return null;
}
/* A copy of a feature with fresh ids (for templates, and Duplicate). */
function cloneFeature(f) {
  const c = JSON.parse(JSON.stringify(f)); c.id = newId("f");
  (function walk(l) { l.forEach(x => { x.id = newId("s"); if (x.f && x.f.options) x.f.options.forEach(o => { o.id = newId("o"); });
    // Rows get new ids too, and "replaces" follows them.
    if (x.type === "growing") { const map = {}; x.f.rows.forEach(r => { map[r.id] = newId("r"); }); x.f.rows.forEach(r => { r.id = map[r.id]; if (r.replaces) r.replaces = map[r.replaces] || ""; }); }
    childLists(x).forEach(walk); }); })(c.sentences || []);
  return c;
}
/* The blocks an entry adds (fresh copies). */
function entryBlocks(e) {
  if (e.template) return cloneFeature(e.template.feature).sentences;
  return e.blocks().map(([t, o]) => { const x = makeSentence(t); Object.assign(x.f, o || {}); return x; });
}
/* Drop or click an entry onto a level: a new feature, named after the entry. */
function addEntryToLane(key, laneKey) {
  const e = entryOf(key); if (!e) return;
  const f = e.template ? cloneFeature(e.template.feature) : Object.assign(feature(e.name, []), { sentences: entryBlocks(e) });
  if (!e.template) f.id = newId("f");
  addFeature({ make: () => f, opens: e.opens === "triggered" ? "trigger" : e.opens }, laneKey);
}
/* Drop or click an entry into a feature's block list (at idx). */
function addEntryToList(key, feat, list, idx, inIf) {
  const e = entryOf(key); if (!e) return;
  if (key.startsWith("s:")) return addSentence(feat, list, key.slice(2), idx);
  const blocks = entryBlocks(e);
  if (inIf && blocks.some(b => SENT[b.type].choice || SENT[b.type].wrapper)) return toast("A choice can't go inside a Logic block.");
  change(() => { list.splice(idx == null ? list.length : idx, 0, ...blocks); if (!feat.name && e.name) feat.name = e.name; });
}
/* types: [[sentence type, field overrides]] */
function feature(name, types) { return { kind: "feature", name, text: "", sentences: types.map(([t, o]) => { const x = makeSentence(t); Object.assign(x.f, o || {}); return x; }) }; }
function newFeature(tpl) { const f = tpl.make(); if (!f.id) f.id = newId("f"); return f; }
/* Drafts and exports from before choice blocks stored ready-made features as their own kinds. */
function migrateFeature(f) {
  if (!f || f.kind === "feature" || !f.kind) return f;
  const blocks = { perk: () => [["perkChoice", { groups: f.groups }]], skills: () => [["skills", { granted: [], num: f.num, groups: f.groups, named: f.named || [] }]],
    subclass: () => [["subclassChoice"]], abilities: () => [["abilityChoice", { num: f.num, cat: f.cat, cost: f.cost, options: f.options || [] }]],
    charinc: () => (f.fixed || []).map(x => ["stat", { attr: x.attr, op: "max", value: x.to }]).concat(+f.num > 0 ? [["charChoice", { num: f.num, max: f.max }]] : []) }[f.kind];
  const n = feature(f.name, blocks ? blocks() : []); n.id = f.id; n.text = f.text || ""; return n;
}
/* Older blocks: "You have a skill" and "Choose skills" are now one Skills block. */
function migrateSentence(x) {
  if (x.type === "skill") { x.type = "skills"; x.f = { granted: x.f.ids || [], num: "0", groups: [], named: [] }; }
  else if (x.type === "skillChoice") { x.type = "skills"; x.f = { granted: [], num: x.f.num, groups: x.f.groups || [], named: x.f.named || [] }; }
  if (x.type === "onlyIf") x.f = migrateOnlyIf(x.f);
  (x.children || []).forEach(migrateSentence); return x;
}
function migrateClass(c) {
  // Classes saved before Recoveries and kits moved to the class's basics keep using their blocks.
  if (c.recoveries === undefined) c.recoveries = "";
  if (c.kits === undefined) c.kits = { on: "no", n: "1", type: "martial" };
  if (!c.subclasses) c.subclasses = []; delete c.linkedSubclasses; if (c.view === undefined) c.view = null;
  c.subclasses.forEach(sc => Object.keys(sc.lanes || {}).forEach(k => { sc.lanes[k] = sc.lanes[k].map(migrateFeature); sc.lanes[k].forEach(f => (f.sentences || []).forEach(migrateSentence)); }));
  Object.keys(c.lanes || {}).forEach(k => { c.lanes[k] = c.lanes[k].map(migrateFeature); c.lanes[k].forEach(f => (f.sentences || []).forEach(migrateSentence)); }); return migrateText(c); }
/* What a feature is, for its chip: named after its one choice, else Ability / Feature. */
function kindLabel(f) {
  const top = f.sentences || [], ch = top.filter(x => SENT[x.type].choice);
  if (ch.length === 1 && top.length === 1) return { perkChoice: "Perk", skills: "Skills", charChoice: "Choice", abilityChoice: "Ability choice", subclassChoice: "Subclass" }[ch[0].type];
  if (ch.length) return "Choice";
  if (top.some(x => x.type === "trigger")) return "Triggered ability";
  if (top.some(x => x.type === "ability")) return "Ability";
  if (top.some(x => x.type === "growing")) return "Growing table";
  if (top.length === 1) return { kit: "Kit", resource: "Resource", language: "Languages" }[top[0].type] || "Feature";
  return "Feature";
}
const primaryChars = () => Object.keys(cls.primary || {}).length ? Object.keys(cls.primary) : ["mgt"];
function eachFeature(fn) { const o = ed(); laneKeys().forEach(k => (o.lanes[k] || []).forEach(f => fn(f, k))); }
function findFeature(id) { let r = null; eachFeature((f, k) => { if (f.id === id) r = { feat: f, lane: k }; }); return r; }

// A feature with no book text of its own reads as its blocks.
const autoText = f => sentenceProse(f);
/* A sentence-built feature with no book text of its own reads as its sentences (ability cards are
   shown on their own, so those sentences are left out). */
function sentenceProse(f) {
  const out = [];
  (function walk(list, prefix) { list.forEach(s => {
    if (s.type === "onlyIf") { walk(s.children, "If " + testProse(s.f.cond) + ", "); return; }
    if (s.type === "aura") { const who = (AURA_WHO.find(x => x[0] === s.f.who) || ["", "Each creature"])[1].toLowerCase(); walk(s.children, "While within " + s.f.radius + " squares of you, " + who + ": "); return; }
    if (s.type === "growing") { s.f.rows.forEach(r => { const t = r.text || growRowProse(r); if (t) out.push("At " + r.at + " " + resWord() + (+r.level > 1 ? " (level " + r.level + "+)" : "") + ": " + t.replace(/\.?$/, ".")); }); return; }
    if (s.type === "ability" || s.type === "trigger") return;
    if (s.type === "rollCombo") { const ps = s.children.filter(c => SENT[c.type].combo).map(c => SENT[c.type].combo.prose(c.f)); if (!ps.length) return;
      const t = "Your " + (s.f.keywords.length ? listWords(s.f.keywords, "and") + " " : "") + "ability rolls " + listWords(ps, "and") + appliesProse(s.f) + ".";
      out.push(prefix ? prefix + t.charAt(0).toLowerCase() + t.slice(1) : t); return; }
    // An unfinished block stays out of the book text (the status column lists it instead).
    if ((REQUIRED[s.type] || []).some(k => { const v = s.f[k]; return v == null || v === "" || (Array.isArray(v) && !v.length); })) return;
    let t;
    if (SENT[s.type].prose) t = SENT[s.type].prose(s.f, f);
    else { const tmp = E("span"); SENT[s.type].render(s.f, n => tmp.appendChild(n), s, f);
      t = [...tmp.childNodes].map(n => n.textContent.trim()).filter(Boolean).join(" ").replace(/\s+/g, " ").replace(/\s+([,.])/g, "$1").trim(); }
    if (!t) return;   // blocks with no wording (grey advanced blocks) add nothing to the book text
    if (prefix) t = prefix + t.charAt(0).toLowerCase() + t.slice(1);
    out.push(t.replace(/[.,]?$/, "."));
  }); })(f.sentences || [], "");
  return out.join(" ");
}
/* An unnamed heroic choice is named the way the book names it: "3-Wrath Heroic Abilities". */
function featName(f) {
  if (f.name) return f.name;
  const hc = (f.sentences || []).find(x => x.type === "abilityChoice" && x.f.cat === "heroic");
  return hc ? hc.f.cost + "-" + (cls.resourceName || "Resource") + " Heroic Abilities" : "Unnamed feature";
}
const featText = f => f.text || autoText(f);

// ---------------------------------------------------------------------------------------------
// The class model and its levels.
const GAIN_EVENTS = [["rollinitiative", "When combat starts", "encounter"],
  ["dealdamage", "The first time each round you deal damage", "round"], ["losehitpoints", "The first time each round you take damage", "round"],
  ["winded", "The first time you become winded in an encounter", "encounter"], ["dying", "The first time you become dying in an encounter", "encounter"],
  ["forcemove", "The first time each round you force move a creature", "round"], ["useability", "Whenever you use an ability", "recurring"]];
function blankClass() {
  return { id: guid(), name: "New Class", details: "", resourceName: "Resolve", epicName: "", slowStart: false,
    primary: { mgt: 2 }, arrays: "auto", arraysCustom: [], stamStart: "18", stamPer: "6", showLevels: 5,
    gains: [{ id: newId("g"), event: "rollinitiative", qty: "Victories", guid: guid() }],
    startGain: { kind: "flat", n: "2", steps: [], guid: guid() },
    recoveries: "8", kits: { on: "yes", n: "1", type: "martial" },
    // Subclasses built here (each saves as its own compendium entry naming this class as parent),
    // and which one the board is showing (null = the class itself).
    subclasses: [], view: null,
    lanes: {} };
}
/* Characteristic arrays: core classes with one starting characteristic use four-number arrays, those with
   two use three-number arrays, so "standard" follows the class's starting characteristics. */
const STD_ARRAYS = { 1: [[2, 2, -1, -1], [2, 1, 1, -1], [2, 1, 0, 0], [1, 1, 1, 0]], 2: [[2, -1, -1], [1, 1, -1], [1, 0, 0]] };
const arraysValue = () => cls.arrays === "custom" ? cls.arraysCustom : (STD_ARRAYS[Object.keys(cls.primary).length] || STD_ARRAYS[1]);
const arrayWords = a => a.map(x => x.map(n => n < 0 ? "\u2212" + (-n) : String(n)).join(", ")).join("  \u00b7  ");
function arraysTok() {
  const s = tok(arrayWords(arraysValue()) + (cls.arrays === "custom" ? "" : " (standard)"), b => menuAt(b, m => {
    m.classList.add("wide");
    const st = E("button", null, "Standard arrays for " + word(Object.keys(cls.primary).length || 1) + " starting characteristic" + (Object.keys(cls.primary).length === 2 ? "s" : "")); st.type = "button";
    st.addEventListener("click", () => { closeMenu(); change(() => { cls.arrays = "auto"; }); }); m.appendChild(st);
    m.appendChild(E("h5", null, "Or your own: one array per line"));
    const ta = E("textarea", "io"); ta.style.height = "90px"; ta.value = arraysValue().map(a => a.join(", ")).join("\n"); m.appendChild(ta);
    const yn = E("div", "yn"); const ok = E("button", "btn primary", "Use these"); ok.type = "button";
    ok.addEventListener("click", () => { const rows = ta.value.split(/\n+/).map(l => l.split(/[,\s]+/).filter(Boolean).map(Number)).filter(r => r.length && r.every(n => Number.isFinite(n)));
      if (!rows.length) return toast("Write each array as numbers separated by commas, one per line (e.g. 2, -1, -1)."); closeMenu(); change(() => { cls.arrays = "custom"; cls.arraysCustom = rows; }); });
    yn.appendChild(ok); m.appendChild(yn);
  }), false, "cls:arrays");
  // One chip per array, numbers signed ("+2 +2 −1 −1"), so the arrays are easy to tell apart.
  const t = s; t.textContent = ""; t.classList.add("arrays");
  arraysValue().forEach(x => t.appendChild(E("span", "arr", x.map(n => n < 0 ? "\u2212" + (-n) : n > 0 ? "+" + n : "0").join(" "))));
  if (cls.arrays !== "custom") t.appendChild(E("span", "arrtag", "standard"));
  t.setAttribute("aria-label", "Characteristic arrays: " + arrayWords(arraysValue()) + (cls.arrays === "custom" ? "" : " (standard)"));
  return t;
}
const LEVELS = Array.from({ length: 10 }, (_, i) => "level-" + (i + 1));
const ENCOUNTERS = ["tutoriallevel-1", "tutoriallevel-2", "tutoriallevel-3", "tutoriallevel-4"];
/* What the board is editing: the class, or one of its subclasses (same levels and blocks, no basics). */
const ed = () => (cls.view && (cls.subclasses || []).find(x => x.id === cls.view)) || cls;
const classLaneKeys = () => (cls.slowStart ? ENCOUNTERS : []).concat(LEVELS);
// Subclasses follow the class's slow start: core subclasses also grant features in Encounters 1-4.
const laneKeys = () => classLaneKeys();
/* Switching what the board shows isn't an edit, so it skips the undo stack. */
function showView(id) { cls.view = id; openId = null; render(); saveStore(); window.scrollTo(0, 0); }
function newSubclass(name) { const sc = { id: guid(), name: name || "New Subclass", details: "", lanes: {}, showLevels: 5 }; cls.subclasses.push(sc); return sc; }
/* Compendium subclasses that already name this class as their parent. */
const compendiumSubclasses = () => (T.subclasses || []).filter(x => x[2] === cls.id);
const className = id => (T.classes || []).find(c => c[0] === id)?.[1] || "";
function laneLabel(k) {
  if (k.startsWith("tutorial")) return ["Encounter", k.slice(-1), ""];
  const n = +k.slice(6);
  if (n === 1 && cls.slowStart) return ["Level", "1", "after the slow start"];
  return ["Level", String(n), ""];
}
const ORD = n => n + (n % 10 === 1 && n !== 11 ? "st" : n % 10 === 2 && n !== 12 ? "nd" : n % 10 === 3 && n !== 13 ? "rd" : "th");

// ---------------------------------------------------------------------------------------------
// Compile: the class record as the engine stores it.
/* When a growing-table row applies: reached the amount this turn (and the level), and no later row
   that replaces it is unlocked. Saving and reading saved records (importer.js) both use this. */
/* A row's hover text: an opened row keeps its saved text until its blocks are edited. */
const rowTooltip = r => r.tooltip && r.snap === srcHash(r.blocks.map(b => b.f)) ? r.tooltip : growRowProse(r) || r.tooltip || "";
function growRowCond(rows, r) {
  let c = "Heroic Resources This Turn >= " + r.at + (+r.level > 1 ? " and Level >= " + r.level : "");
  rows.filter(x => x.replaces === r.id).forEach(x => { c += " and (Heroic Resources This Turn < " + x.at + (+x.level > 1 ? " or Level < " + x.level : "") + ")"; });
  return c;
}
/* Imported records (see importer.js). A block read from a saved record keeps that record: while the
   block and its Logic condition are unchanged, the record is written back exactly as it was; once
   edited, the block's fields replace the ones it claims and every other field is kept. */
let compileSrcMods = null;   // the saved feature's modifiers, while compiling an imported feature
const srcHash = o => { const t = JSON.stringify(o); let h = 5381; for (let i = 0; i < t.length; i++) h = ((h * 33) ^ t.charCodeAt(i)) >>> 0; return h; };
const clone = o => o == null ? o : JSON.parse(JSON.stringify(o));
/* What makes a block "unchanged": its fields, and for a wrapper (Logic, aura, combined roll change) its children. */
const blockSnap = s => srcHash(s.children ? { f: s.f, c: s.children } : s.f);
// Which saved record each written record came from (its index in the feature's saved modifiers),
// so a feature list can put records back into the plain feature they were saved in.
const SRC_INDEX = new WeakMap();
const tagSrc = (r, i) => { if (r && typeof r === "object" && i != null) SRC_INDEX.set(r, i); return r; };
function keptRecords(s, filter) {
  if (s.srcIdx == null || !compileSrcMods || SENT[s.type].noKeep || blockSnap(s) !== s.snap || filter !== s.srcFilter) return null;
  return [s.srcIdx].concat(s.srcExtra != null ? [s.srcExtra] : []).map(i => tagSrc(clone(compileSrcMods[i]), i));
}
/* An edited block: the saved record minus the fields the block claims, plus what the block writes.
   Where the block writes the same meaning the record already had ("1" or true, "(X)" or X, 12 or
   "12", operation "add" or left out), the saved spelling is kept. */
function mergeSrc(s, r) {
  if (s.srcIdx == null || !compileSrcMods) return r;
  const saved = compileSrcMods[s.srcIdx], src = clone(saved); (SENT[s.type].claims || []).forEach(k => delete src[k]);
  delete r.name; delete r.description;
  const out = Object.assign(src, r);
  if (typeof sameMeaning === "function") (SENT[s.type].claims || []).forEach(k => {
    if (k in saved) { if (sameMeaning(k, out[k], saved[k])) out[k] = clone(saved[k]); }
    else if (k in out && sameMeaning(k, out[k], undefined)) delete out[k];   // a default the record left out stays out
  });
  return tagSrc(out, s.srcIdx);
}
function compileSentences(list, feat, filter) {
  const out = [];
  for (const s of list) {
    // (A growing table keeps only its own record here; its rows are compiled below either way.)
    const kept = s.type !== "growing" && keptRecords(s, filter); if (kept) { out.push(...kept); continue; }
    // A wrapper that saves as one record holding its children's records (aura, companion, summoner):
    // the type's compileWrap builds it, and childMods says where a saved one keeps its children.
    if (SENT[s.type].compileWrap) {
      const d = SENT[s.type], saved = compileSrcMods, src = s.srcIdx != null && saved ? saved[s.srcIdx] : null;
      compileSrcMods = src ? d.childMods(src) : null;
      let inner; try { inner = compileSentences(s.children, feat); } finally { compileSrcMods = saved; }
      const r = d.compileWrap(s.f, inner, feat, src);
      if (filter) r.filterCondition = filter; out.push(mergeSrc(s, r)); continue;
    }
    if (s.type === "rollCombo") {
      // One power modifier: the shared keywords and roll options, plus each block's part.
      const parts = s.children.filter(c => SENT[c.type].combo), mt = parts.map(c => SENT[c.type].combo.modtype && SENT[c.type].combo.modtype(c.f)).find(Boolean);
      const r = modBase(feat, Object.assign({ behavior: "power", modtype: mt || "none", rollType: "ability_power_roll", keywords: s.f.keywords.length ? Object.fromEntries(s.f.keywords.map(k => [k, true])) : [] },
        ...parts.map(c => SENT[c.type].combo.fields(c.f)), appliesFields(s.f)));
      if (filter) r.filterCondition = filter; out.push(mergeSrc(s, r)); continue;
    }
    if (s.type === "onlyIf") { out.push(...compileSentences(s.children, feat, (filter ? filter + " and " : "") + "(" + testGs(s.f.cond) + ")")); continue; }
    if (s.type === "growing") {
      const rows = s.f.rows.filter(r => /^\d+$/.test(String(r.at).trim()));
      const own = keptRecords(s, filter);
      out.push(own ? own[0] : mergeSrc(s, { __typeName: "CharacterModifier", behavior: "growingresources", name: feat.name, description: "",
        progression: rows.map(r => ({ resources: +r.at, level: +r.level > 1 ? +r.level : 0, description: r.text || growRowShort(r), tooltip: rowTooltip(r) })) }));
      rows.forEach(r => out.push(...compileSentences(r.blocks, feat, (filter ? filter + " and " : "") + "(" + growRowCond(rows, r) + ")")));
      continue;
    }
    const d = SENT[s.type]; if (!d.compile) continue;
    const r = d.compile(s.f, feat); if (!r) continue;
    if (filter) r.filterCondition = r.filterCondition ? "(" + r.filterCondition + ") and " + filter : filter;
    Object.keys(r).forEach(k => r[k] === undefined && delete r[k]);
    out.push(mergeSrc(s, r)); if (d.extra) out.push(...d.extra(s.f));
  }
  return out;
}
/* The record type follows from the blocks (the author never picks it): modifiers only -> a feature;
   one choice alone -> that choice record; anything else -> a feature list holding a hidden feature with
   the modifiers, then each choice (as core classes store Characteristic Increase). */
let compileOwner = null;   // a subclass's features carry the subclass's id as their classid
function compileFeature(f) {
  // An imported feature nobody has changed is written back exactly as it was saved.
  if (f.src && srcHash({ n: f.name, t: f.text, s: f.sentences }) === f.snap && !(typeof featureGainsChanged === "function" && featureGainsChanged(f))) return clone(f.src);
  const saved = compileSrcMods; compileSrcMods = srcModsOf(f.src);
  try { return mergeFeatureSrc(f.src, compileFeatureBlocks(f), f); } finally { compileSrcMods = saved; }
}
/* The saved modifiers a feature's blocks point into: a feature's own, or (a feature list) those of
   every plain feature in it, in order. importer.js numbers blocks the same way. */
const srcModsOf = src => !src ? null : src.__typeName === "CharacterFeatureList" ? (src.features || []).filter(x => x.__typeName === "CharacterFeature").flatMap(x => x.modifiers || []) : (src.modifiers || null);
/* An edited saved feature list keeps its shape: each plain feature gets back the records that came
   from it (new records go to the first), and each choice stays in its place; new choices go last. */
function rebuildList(f, base, mods, choices, parts) {
  const plain = f.src.features.filter(x => x.__typeName === "CharacterFeature");
  let start = 0; const ranges = plain.map(p => { const r = [start, start + (p.modifiers || []).length]; start = r[1]; return r; });
  const buckets = plain.map(() => []);
  mods.forEach(m => { const i = SRC_INDEX.get(m), b = i == null ? -1 : ranges.findIndex(([a, z]) => i >= a && i < z); (buckets[b < 0 ? 0 : b] || (buckets[0] = buckets[0] || [])).push(m); });
  const used = new Set();
  const features = f.src.features.map(x => {
    if (x.__typeName === "CharacterFeature") return Object.assign(clone(x), { modifiers: buckets[plain.indexOf(x)] });
    const i = choices.findIndex((c, j) => !used.has(j) && c.choiceSrc && (c.choiceSrc.guid ? c.choiceSrc.guid === x.guid : JSON.stringify(c.choiceSrc) === JSON.stringify(x)));
    if (i < 0) return null; used.add(i); return parts[i];
  }).filter(Boolean);
  if (!plain.length && mods.length) features.unshift({ __typeName: "CharacterFeature", name: base.name, description: base.description, tags: { Hidden: true }, modifiers: mods });
  parts.forEach((p, j) => { if (p && !used.has(j) && !choices[j].choiceSrc) features.push(p); });
  return Object.assign({ __typeName: "CharacterFeatureList" }, base, { features });
}
/* A choice inside a saved feature list keeps its saved record while unchanged. */
function choicePart(x, f, base) {
  const r = SENT[x.type].compileChoice(x.f, f, base);
  if (!r || !x.choiceSrc) return r;
  if (blockSnap(x) === x.snap) return clone(x.choiceSrc);
  // A choice inside a list keeps its own name and text (the list's name is the feature's).
  return Object.assign(mergeFeatureSrc(x.choiceSrc, r, { text: "" }), "name" in x.choiceSrc ? { name: x.choiceSrc.name } : {}, "description" in x.choiceSrc ? { description: x.choiceSrc.description } : {});
}
/* An edited imported feature keeps the saved fields its blocks don't write (guid, source, tags...).
   What the blocks write replaces the saved value; a name or text the saved record left blank stays blank. */
const isChoiceDefault = (k, v) => (k === "numChoices" && +v === 1) || (k === "individualSkills" && !Object.keys(v || {}).length) || (k === "allowDuplicateChoices" && v === false)
  || (k === "categories" && SKILL_GROUPS.every(g => (v || {})[g]) && Object.keys(v || {}).length === SKILL_GROUPS.length);
const FEATURE_CLAIMS = ["modifiers", "features", "options", "numChoices", "tag", "categories", "individualSkills", "allowDuplicateChoices"];
function mergeFeatureSrc(src, r, f) {
  if (!src || src.__typeName !== r.__typeName) return r;
  const out = clone(src); FEATURE_CLAIMS.filter(k => k in r).forEach(k => delete out[k]);   // only what the blocks write
  Object.keys(r).forEach(k => { if (["name", "description", "classid"].includes(k) && !(k in src)) return;
    if (!(k in src) && isChoiceDefault(k, r[k])) return;   // e.g. numChoices 1, no named skills, every skill group
    if (k in src && (typeof src[k] === "string" || typeof src[k] === "number") && String(src[k]) === String(r[k])) { out[k] = src[k]; return; }   // "2" and 2 alike: keep the saved one
    if (k === "description" && src.description === "" && !f.text) return;   // a deliberately blank text stays blank
    out[k] = r[k]; });
  return out;
}
function compileFeatureBlocks(f) {
  const name = featName(f), description = featText(f), base = { name, description, classid: compileOwner || cls.id };
  const mods = compileSentences(f.sentences, { name, text: description });
  if (cls.gainsImported && f.id === cls.gainFeatId) mods.push(...newGainRecords());   // gains added after opening
  const choices = f.sentences.filter(x => SENT[x.type].compileChoice), parts = choices.map(x => choicePart(x, f, base));
  if (f.src && f.src.__typeName === "CharacterFeatureList" && f.listRead) return rebuildList(f, base, mods, choices, parts);
  parts.splice(0, parts.length, ...parts.filter(Boolean));
  if (!parts.length) return Object.assign({ __typeName: "CharacterFeature" }, base, { modifiers: mods });
  if (parts.length === 1 && !mods.length) return parts[0];
  const list = mods.length ? [{ __typeName: "CharacterFeature", name, description, tags: { Hidden: true }, modifiers: mods }] : [];
  return Object.assign({ __typeName: "CharacterFeatureList" }, base, { features: list.concat(parts) });
}
/* "How you gain your resource" writes two linked records, as decided: the checklist line players see,
   and the trigger that grants it (its Replenish step points at the line by checklistid). */
/* Start of turn, written the way core classes do it:
   - the amount is the "Heroic Resource Gain at Start" attribute (a flat amount, or the die size for 1dN),
     set by a modifier at 1st level, with level steps as extra modifiers (flat) or table rows (die);
   - the trigger gains that attribute (or rolls 1d it) and only fires while it's above 0, so a
     complication that sets it to 0 switches the gain off;
   - the checklist line reads the attribute, so the sheet shows the changed amount. */
function startGainText(sg) {
  const st = (sg.steps || []).filter(x => x.from && x.add);
  const base = sg.kind === "die" ? "1d" + sg.n : sg.n;
  // "1d3 (1d3 + 1 from 7th level, 1d3 + 2 from 10th level)": each step adds to the previous ones.
  let total = 0; const parts = st.map(x => { total += +x.add || 0; return (sg.kind === "die" ? base + " + " + total : String((+sg.n || 0) + total)) + " from " + ORD(+x.from) + " level"; });
  return base + (parts.length ? " (" + parts.join(", ") + ")" : "");
}
function compileStartGain(res) {
  const sg = cls.startGain; if (!sg) return null;
  const st = (sg.steps || []).filter(x => x.from && x.add).slice().sort((a, b) => +a.from - +b.from);
  const name = "Start of Turn", A = HR_START_NAME;
  const mods = [{ __typeName: "CharacterModifier", behavior: "attribute", name: res + " at Start of Turn", description: "", attribute: HR_START, value: numOr(sg.n) }];
  let qty;
  if (sg.kind === "die") {
    // 1dN, plus the level steps as table rows: "1d X", "(1d X) + 1" from 7th level...
    let bonus = 0; const entries = [{ threshold: 1, script: "1d " + A }];
    st.forEach(x => { bonus += +x.add || 0; entries.push({ threshold: +x.from, script: "(1d " + A + ") + " + bonus }); });
    qty = entries.length > 1 ? { __typeName: "GoblinScriptTable", id: "table", field: "Level", editableField: true, entries } : "1d " + A;
  } else {
    st.forEach(x => mods.push({ __typeName: "CharacterModifier", behavior: "attribute", name: res + " at Start of Turn (" + ORD(+x.from) + " level)", description: "", attribute: HR_START, value: numOr(x.add), filterCondition: "Level >= " + x.from }));
    qty = A;
  }
  const details = sg.kind === "die" ? "At the start of your turn you gain " + startGainText(sg) + " " + res + "." : "At the start of your turn you gain {" + A + "} " + res + ".";
  return { mods, check: { name, details, guid: sg.guid, mode: "round", quantity: qty },
    trigger: { __typeName: "CharacterModifier", behavior: "trigger", name, description: details,
      triggeredAbility: { __typeName: "TriggeredAbility", name, description: details, trigger: "beginturn", targetType: "self", mandatory: "game:heroicresourcetriggers", conditionFormula: A + " > 0",
        triggerPrompt: "Start of turn: gain " + res + ".", behaviors: [{ __typeName: "ActivatedAbilityReplenishBehavior", checklistid: sg.guid, quantity: qty, resourceid: RES.heroic }] } } };
}
/* The events a gain can use: the usual ones, plus the one an opened class's gain already uses (a
   start-of-turn formula, "an enemy uses Malice"...), named by its checklist line. */
const gainEvents = g => GAIN_EVENTS.some(e => e[0] === g.event) || !g.src ? GAIN_EVENTS : GAIN_EVENTS.concat([[g.event, g.src.check.name, g.src.check.mode || "recurring"]]);
function compileGains() {
  const res = cls.resourceName || "Resource";
  const checklist = [], triggers = [], mods = [];
  const sg = compileStartGain(res);
  if (sg) { checklist.push(sg.check); triggers.push(sg.trigger); mods.push(...sg.mods); }
  cls.gains.filter(g => g.event !== "manual").forEach(g => {
    const ev = gainEvents(g).find(e => e[0] === g.event) || GAIN_EVENTS[0];
    const details = ev[1] + ", you gain " + gainAmountText(g, res) + ".";   // the book capitalises resource names (Ferocity)
    checklist.push({ name: ev[1], details, guid: g.guid, mode: ev[2], quantity: fxTable(g, "qty") });
    triggers.push({ __typeName: "CharacterModifier", behavior: "trigger", name: ev[1], description: details,
      triggeredAbility: { __typeName: "TriggeredAbility", name: ev[1], description: details, trigger: ev[0], targetType: "self", mandatory: "game:heroicresourcetriggers", triggerPrompt: ev[1] + ": gain " + res + ".",
        behaviors: [{ __typeName: "ActivatedAbilityReplenishBehavior", checklistid: g.guid, quantity: fxFormula(g, "qty"), resourceid: RES.heroic }] } });
  });
  return { checklist, triggers, mods };
}
/* Kit types the engine registers (Kit.RegisterKitType in MCDMKit.lua). */
const KIT_TYPES = [["martial", "martial"], ["caster", "caster"], ["stormwight", "Stormwight"], ["null", "Null"]];
function compileClass() {
  const primary = Object.fromEntries(Object.keys(cls.primary).map(k => [k, numOr(cls.primary[k])]));
  const arrays = arraysValue();
  const g = compileGains();
  const rec = { __typeName: "Class", id: cls.id, name: cls.name, details: cls.details, isSubclass: false,
    heroicResourceName: cls.resourceName, epicResourceName: cls.epicName || undefined,
    baseCharacteristics: Object.assign({}, primary, { arrays }), hitpointsCalculation: cls.stamStart + " + (Level - 1)*" + cls.stamPer,
    heroicResourceChecklist: g.checklist, levels: {} };
  if (cls.kits && cls.kits.on === "yes") rec.numKits = +cls.kits.n || 1;
  const all = ENCOUNTERS.concat(Array.from({ length: 20 }, (_, i) => "level-" + (i + 1)));
  all.forEach(k => { rec.levels[k] = { __typeName: "ClassLevel", features: (classLaneKeys().includes(k) ? cls.lanes[k] || [] : []).map(compileFeature) }; });
  // The resource feature holds the gain triggers, in the first lane (as core classes do).
  const first = classLaneKeys()[0];
  // Recoveries and kit access from the basics, as features of the first lane (where core classes keep them).
  const basics = [];
  if (String(cls.recoveries || "").trim()) basics.push({ __typeName: "CharacterFeature", name: "Recoveries", classid: cls.id, description: "You have " + cls.recoveries + " Recoveries.",
    modifiers: [{ __typeName: "CharacterModifier", name: "Recoveries", behavior: "resource", resourceType: RES.recovery, num: numOr(cls.recoveries) }] });
  if (cls.kits && cls.kits.on === "yes") basics.push({ __typeName: "CharacterFeature", name: "Kit", classid: cls.id,
    description: "You can use and gain the benefits of " + (cls.kits.n === "2" ? "two " + cls.kits.type + " kits" : "a " + cls.kits.type + " kit") + ".",
    modifiers: [{ __typeName: "CharacterModifier", name: "Kit", behavior: "kitaccess", kitType: cls.kits.type }] });
  rec.levels[first].features.unshift(...basics);
  // An imported class keeps its saved checklist; its resource feature is one of its imported features.
  if (cls.hrRaw) rec.heroicResourceChecklist = clone(cls.hrRaw);
  else if (cls.gainsImported) rec.heroicResourceChecklist = gainChecklist();
  else rec.levels[first].features.unshift({ __typeName: "CharacterFeature", name: cls.resourceName || "Heroic Resource", classid: cls.id,
    description: g.checklist.map(c => c.details).join(" "), tags: { Hidden: true }, modifiers: g.mods.concat(g.triggers) });
  Object.keys(rec).forEach(k => rec[k] === undefined && delete rec[k]);
  return mergeClassSrc(cls.src, rec);
}

/* A subclass is saved as its own Class record (table "subclasses"): isSubclass, and primaryClassId
   pointing at this class. The class's "Choose your subclass" block lists every subclass that does. */
function compileSubclass(sc) {
  compileOwner = sc.id;
  try {
    // Subclasses can add their own ways to gain the resource (Conduit domains add Piety gains); an
    // opened subclass keeps its saved list until subclass gain blocks exist.
    const rec = { __typeName: "Class", id: sc.id, name: sc.name, details: sc.details, isSubclass: true, primaryClassId: cls.id,
      heroicResourceChecklist: clone(sc.src && sc.src.heroicResourceChecklist || []), levels: {} };
    ENCOUNTERS.concat(Array.from({ length: 20 }, (_, i) => "level-" + (i + 1))).forEach(k => { rec.levels[k] = { __typeName: "ClassLevel", features: (sc.lanes[k] || []).map(compileFeature) }; });
    return mergeClassSrc(sc.src, rec);
  } finally { compileOwner = null; }
}
/* An imported class or subclass keeps every field the builder doesn't edit (colour, portrait, ability
   category names...), and each level keeps its own fields around the rebuilt feature list. */
// numKits is written only when kits are switched on, so a saved value is otherwise kept.
const CLASS_CLAIMS = ["name", "details", "heroicResourceName", "epicResourceName", "baseCharacteristics", "hitpointsCalculation", "heroicResourceChecklist", "levels", "isSubclass", "primaryClassId"];
function mergeClassSrc(src, rec) {
  if (!src) return rec;
  // Blank values the saved record leaves out are defaults (isSubclass false, details "").
  Object.keys(rec).forEach(k => { if (!(k in src) && (rec[k] === false || rec[k] === "" || (Array.isArray(rec[k]) && !rec[k].length))) delete rec[k]; });
  // The same Stamina formula spelled differently ("(Level-1)" vs "(Level - 1)") keeps the saved spelling.
  const hp = t => String(t || "").replace(/\s+/g, "");
  if (src.hitpointsCalculation && hp(src.hitpointsCalculation) === hp(rec.hitpointsCalculation)) rec.hitpointsCalculation = src.hitpointsCalculation;
  const out = clone(src); CLASS_CLAIMS.forEach(k => { if (k !== "levels") delete out[k]; });
  const levels = out.levels || {};
  Object.keys(rec.levels).forEach(k => { levels[k] = Object.assign(levels[k] || {}, rec.levels[k]); });
  return Object.assign(out, rec, { levels });
}
const trimLevels = r => Object.assign({}, r, { levels: Object.fromEntries(Object.entries(r.levels).filter(([, v]) => v.features.length)) });

// ---------------------------------------------------------------------------------------------
// State, undo, and the draft kept in this browser.
let cls = null, openId = null, showGs = false, undoStack = [], redoStack = [];
/* Classes are kept in this browser: several of them, each with its own undo and redo history, so a
   reload or an Import never loses work. (Older single drafts are moved into the list.) */
const STORE_KEY = "classBuilderStore", OLD_DRAFT_KEY = "classBuilderDraft";
let store = { current: null, order: [], classes: {} };
/* Every change goes through here: one undo step, redraw, keep focus on the same control, save. */
function change(fn, keepMenu) {
  undoStack.push(JSON.stringify(cls)); if (undoStack.length > 60) undoStack.shift(); redoStack = [];
  const key = pendingFk || (document.activeElement && document.activeElement.dataset && document.activeElement.dataset.fk) || menuFk;
  fn(); if (!keepMenu) closeMenu(); render(); saveStore();
  const target = pendingFk || key; pendingFk = null;
  if (!(keepMenu && openMenu && openMenu.contains(document.activeElement))) restoreFocus(target);
}
function undo() { if (!undoStack.length) return toast("Nothing to undo."); redoStack.push(JSON.stringify(cls)); cls = JSON.parse(undoStack.pop()); render(); saveStore(); toast("Undone.", { label: "Redo", run: redo }); }
function redo() { if (!redoStack.length) return toast("Nothing to redo."); undoStack.push(JSON.stringify(cls)); cls = JSON.parse(redoStack.pop()); render(); saveStore(); toast("Redone."); }
function saveStore() {
  // A big class (an imported core class) keeps its undo history in memory only: browser storage is small.
  const big = JSON.stringify(cls).length > 100000;
  store.classes[cls.id] = { cls, undo: big ? [] : undoStack.slice(-30), redo: big ? [] : redoStack.slice(-30) };
  if (!store.order.includes(cls.id)) store.order.push(cls.id); store.current = cls.id; store.uid = uid;
  // Browser storage is limited: if it's full, keep the classes and drop old history first.
  for (const keep of [30, 5, 0]) {
    try { Object.values(store.classes).forEach(c => { c.undo = (c.undo || []).slice(-keep); c.redo = (c.redo || []).slice(-keep); }); localStorage.setItem(STORE_KEY, JSON.stringify(store)); return; } catch (e) {}
  }
}
function loadStore() {
  try { const d = JSON.parse(localStorage.getItem(STORE_KEY) || "null"); if (d && d.classes && d.order) store = d; } catch (e) {}
  try { const old = JSON.parse(localStorage.getItem(OLD_DRAFT_KEY) || "null");
    if (old && old.cls && old.cls.lanes && !store.classes[old.cls.id]) { store.classes[old.cls.id] = { cls: old.cls, undo: [], redo: [] }; store.order.push(old.cls.id); store.current = store.current || old.cls.id; uid = Math.max(uid, old.uid || 1); }
    localStorage.removeItem(OLD_DRAFT_KEY); } catch (e) {}
  uid = Math.max(uid, store.uid || 1);
}
function openClass(id) {
  const e = store.classes[id]; if (!e) return;
  if (cls) saveStore();
  cls = migrateClass(e.cls); undoStack = e.undo || []; redoStack = e.redo || []; openId = null; saveStore(); render();
}
function newClass(c) { if (cls) saveStore(); cls = c || blankClass(); undoStack = []; redoStack = []; openId = null; saveStore(); render(); }
function deleteClass() {
  const name = cls.name; delete store.classes[cls.id]; store.order = store.order.filter(x => x !== cls.id); cls = null;
  if (store.order.length) openClass(store.order[store.order.length - 1]); else newClass();
  toast("Deleted \u201c" + name + "\u201d from this browser.");
}
/* Classes made before the start-of-turn block had it as an ordinary gain: move it into the block. */
function migrateStartGain(c) {
  if (c.startGain !== undefined) return;
  const i = (c.gains || []).findIndex(g => g.event === "beginturn"); c.startGain = null;
  if (i < 0) return;
  const g = c.gains[i], q = String(g.qty || "").trim(), m = q.match(/^1d(\d+)$/i);
  c.startGain = { kind: m ? "die" : "flat", n: m ? m[1] : (/^\d+$/.test(q) ? q : "2"), steps: [], guid: g.guid || guid() };
  c.gains.splice(i, 1);
}
function migrateText(c) {
  migrateStartGain(c);
  // Typed feature text remembers the blocks' wording it was written against, so a later change can be flagged.
  Object.values(c.lanes || {}).forEach(l => l.forEach(f => { if (f.text && f.textBasis == null) f.textBasis = sentenceProse(f); }));
  if (typeof c.arrays === "string" && c.arrays !== "auto" && c.arrays !== "custom") {
    let a = null; try { a = JSON.parse("[" + c.arrays.replace(/\]\s*\[/g, "],[") + "]"); } catch (e) {}
    const std = STD_ARRAYS[Object.keys(c.primary || {}).length] || STD_ARRAYS[1];
    if (a && JSON.stringify(a) !== JSON.stringify(std)) { c.arrays = "custom"; c.arraysCustom = a; } else { c.arrays = "auto"; c.arraysCustom = []; }
  }
  return c;
}

// ---------------------------------------------------------------------------------------------
// The ability editor (simple ability editor in embedded mode). One iframe, reused.
const abModal = document.getElementById("abModal"), abFrame = document.getElementById("abFrame");
let abReady = false, abPending = null, abDone = null, abReturnFk = null;
function openEditor(msg, done) {
  abDone = done; abReturnFk = (document.activeElement && document.activeElement.dataset.fk) || menuFk;
  abModal.classList.add("open"); abModal.setAttribute("aria-hidden", "false"); setTimeout(() => abFrame.focus());
  const m = Object.assign({ type: "cb-edit", owner: cls.name, resourceName: cls.resourceName }, msg);
  if (abReady) abFrame.contentWindow.postMessage(m, "*"); else abPending = m;
}
function closeEditor() { abModal.classList.remove("open"); abModal.setAttribute("aria-hidden", "true"); abDone = null; restoreFocus(abReturnFk); }
document.addEventListener("keydown", ev => { if (ev.key === "Escape" && abModal.classList.contains("open")) closeEditor(); });
window.addEventListener("message", ev => {
  const m = ev.data || {};
  if (m.type === "cb-ready") { abReady = true; if (abPending) { abFrame.contentWindow.postMessage(abPending, "*"); abPending = null; } }
  else if (m.type === "cb-cancel") closeEditor();
  else if (m.type === "cb-done") {
    const done = abDone; closeEditor();
    if (done) change(() => done(m.rec, m.display, m.problems && m.problems.length ? m.problems : undefined));
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
    const edit = () => openEditor({ rec: it.rec || (seedFn ? seedFn() : null), display: it.display || null, kind: it.trig ? "triggered" : "ability" }, (rec, display, problems) => setRec(i, rec, display, problems));
    card.tabIndex = 0; card.title = "Edit in the ability editor"; card.addEventListener("click", edit); card.addEventListener("keydown", e => { if (e.key === "Enter") edit(); });
    cw.appendChild(card);
    const btns = E("div", "cbtns");
    const eb = E("button", "btn small", it.rec ? "Edit" : "Build it"); eb.type = "button"; eb.addEventListener("click", edit); btns.appendChild(eb);
    if (it.problems) btns.appendChild(E("span", "warnpill", it.problems.length + " thing" + (it.problems.length === 1 ? "" : "s") + " to finish"));
    if (onRemove) { const rb = E("button", "btn small", "Remove"); rb.type = "button"; rb.addEventListener("click", () => { change(() => onRemove(i)); toast("Removed \u201c" + (it.rec ? recName(it.rec) : "ability") + "\u201d.", { label: "Undo", run: undo }); }); btns.appendChild(rb); }
    cw.appendChild(btns); wrap.appendChild(cw);
  });
  wrap.style.flexBasis = "100%";
  return wrap;
}

// The starting characteristics as a pickable list (one stable object, so its focus key stays the same).
const PRIMARY = { get list() { return Object.keys(cls.primary); }, set list(v) { cls.primary = Object.fromEntries(v.map(k => [k, cls.primary[k] || 2])); } };
// ---------------------------------------------------------------------------------------------
// Rendering: board, shelf, side.
const board = document.getElementById("board"), shelf = document.getElementById("shelf"), side = document.getElementById("side");
let compiled = null, compiledSub = null;
function render() {
  for (const k in LISTS) delete LISTS[k];
  compiled = compileClass(); compiledSub = ed() !== cls ? compileSubclass(ed()) : null;
  renderBoard(); renderShelf(); renderSide();
  document.getElementById("showGs").checked = showGs;
  if (store.order) updateOpenSel();
}
function renderBoard() {
  const y = window.scrollY; board.innerHTML = "";
  const sc = ed() !== cls ? ed() : null, who = sc || cls;
  // Text fields commit after focus has moved on (setTimeout), so Tab lands on the next control.
  const ni = fk(E("input"), "cls:name"); ni.value = who.name; ni.setAttribute("aria-label", sc ? "Subclass name" : "Class name");
  ni.addEventListener("change", () => setTimeout(() => change(() => { who.name = ni.value.trim() || (sc ? "New Subclass" : "New Class"); })));
  board.appendChild(nameTabs(ni));
  const det = fk(E("textarea", "details"), "cls:details"); det.placeholder = sc ? "The subclass's introduction, as the book prints it (optional)" : "The class's introduction, as the book prints it (optional)"; det.value = who.details;
  det.addEventListener("change", () => setTimeout(() => change(() => { who.details = det.value; }))); board.appendChild(det);
  if (sc) board.appendChild(subclassInfo(sc));
  if (!sc) {

  // Basics
  board.appendChild(E("h3", "sec", "Basics"));
  const b = E("div", "fixed");
  const row = (label, ...nodes) => { const r = E("div", "row"); r.appendChild(E("span", "lbl", label)); nodes.forEach(n => r.appendChild(n)); b.appendChild(r); };
  row("Characteristics", lbl("You start with"), multiTok(PRIMARY, "list", CHARS, "choose", "and"),
    lbl("of 2; the other scores use one of these arrays:"), arraysTok());
  row("Stamina", textTok(cls, "stamStart", "18"), lbl("at 1st level, plus"), textTok(cls, "stamPer", "6"), lbl("each level after"));
  // Recoveries and kits are part of every class, so they sit with the basics (the blocks still exist for features).
  // Core classes keep Recoveries and kits in features (kits often in each subclass); say where.
  const recFeat = basicsSource(o => o.type === "resource" && o.f.res === RES.recovery), kitFeats = basicsSource(o => o.type === "kit", true);
  if (!String(cls.recoveries || "").trim() && recFeat) row("Recoveries", lbl("You have " + recFeat.s.f.num + " Recoveries, from the \u201c" + featName(recFeat.f) + "\u201d feature (" + laneLabel(recFeat.k).slice(0, 2).join(" ") + ")."));
  else row("Recoveries", lbl("You have"), textTok(cls, "recoveries", "8"), lbl("Recoveries"));
  if (cls.kits.on !== "yes" && kitFeats.length) row("Kits", lbl("Kits come from " + listWords([...new Set(kitFeats.map(x => x.where))], "and") + "."));
  else {
    const kitRow = [pickTok(cls.kits, "on", [["yes", "You use"], ["no", "This class doesn't use kits"]])];
    if (cls.kits.on === "yes") kitRow.push(pickTok(cls.kits, "n", [["1", "one"], ["2", "two"]]), pickTok(cls.kits, "type", KIT_TYPES), lbl(cls.kits.n === "2" ? "kits" : "kit"));
    row("Kits", ...kitRow);
  }
  board.appendChild(b);

  // Heroic resource
  board.appendChild(E("h3", "sec", "Heroic resource"));
  const r = E("div", "fixed");
  const rr = E("div", "row"); rr.appendChild(E("span", "lbl", "Name")); rr.appendChild(textTok(cls, "resourceName", "e.g. Wrath")); rr.appendChild(lbl("epic resource")); rr.appendChild(textTok(cls, "epicName", "optional")); r.appendChild(rr);
  board.appendChild(r);
  // How you gain it: one block per way, like any sentence (each writes a checklist line and its trigger).
  const gl = E("div", "lbl2", "How you gain " + (cls.resourceName || "it").toLowerCase()); board.appendChild(gl);
  const gs = E("div", "sents");
  const res = (cls.resourceName || "resource").toLowerCase();
  // An imported class keeps its saved resource checklist; it is shown, and changed in the advanced editor.
  if (cls.hrRaw) cls.hrRaw.forEach(c => { const el = E("div", "sent"); el.style.setProperty("--c", "var(--c-adv)"); el.appendChild(E("span", null, c.details || c.name));
    el.appendChild(E("span", "grow")); el.appendChild(E("span", "aside", "Make changes in the advanced editor")); gs.appendChild(el); });
  if (cls.startGain && !cls.hrRaw) {
    const sg = cls.startGain;
    const el = E("div", "sent startgain"); el.style.setProperty("--c", "var(--c-res)");
    el.appendChild(lbl("At the start of each of your turns, you gain"));
    // The same fx picker as every other amount; "1d3" stores as a die, anything else as a set amount.
    const sgAd = { get: () => sg.kind === "die" ? "1d" + sg.n : sg.n,
      set: f => { const d = String(f).trim().match(/^1\s*d\s*(\d+)$/i); sg.kind = d ? "die" : "flat"; sg.n = d ? d[1] : String(f).trim(); },
      addStep: () => { sg.steps = sg.steps || []; const last = sg.steps.length ? +sg.steps[sg.steps.length - 1].from : 4; sg.steps.push({ from: String(last < 7 ? 7 : 10), add: "1" }); },
      reads: f => { const d = String(f).trim().match(/^1\s*d\s*(\d+)$/i); return startGainText(Object.assign({}, sg, { kind: d ? "die" : "flat", n: d ? d[1] : f })); } };
    const amt = tok(sgAd.get() || "2", b => menuAt(b, m => fillFx(m, sg, "n", sgAd)), !String(sg.n || "").trim(), "startgain:n");
    amt.classList.add("fx"); amt.title = "Build a formula"; el.appendChild(amt); el.appendChild(lbl(res));
    el.appendChild(E("span", "grow"));
    const mb = fk(E("button", "mb", "\u22ef"), "startgainmb"); mb.type = "button"; mb.setAttribute("aria-label", "Start-of-turn gain options");
    mb.addEventListener("click", ev => { ev.stopPropagation(); menuAt(mb, m => { const x = E("button", null, "This class doesn't gain " + res + " at the start of its turn"); x.type = "button";
      x.addEventListener("click", () => { closeMenu(); pendingFk = "addgain"; change(() => { cls.startGain = null; }); toast("Removed the start-of-turn gain.", { label: "Undo", run: undo }); }); m.appendChild(x); }); });
    el.appendChild(mb);
    // Level steps: "+1 from 7th level" (core classes use 7th and 10th).
    const steps = E("div", "gainsteps");
    (sg.steps || []).forEach((x, i) => {
      const row = E("span", "gstep"); row.appendChild(lbl("+")); row.appendChild(textTok(x, "add", "1")); row.appendChild(lbl("from")); row.appendChild(textTok(x, "from", "7")); row.appendChild(lbl(ORD(+x.from || 0).replace(/^\d+/, "") + " level"));
      const rm = E("button", "mb", "\u2715"); rm.type = "button"; rm.title = "Remove this step"; rm.addEventListener("click", () => change(() => sg.steps.splice(i, 1))); row.appendChild(rm);
      steps.appendChild(row);
    });
    const addStep = fk(E("button", "addsent inblock", "+ more from a level"), "startgainstep"); addStep.type = "button";
    addStep.addEventListener("click", () => change(() => { sg.steps = sg.steps || []; const last = sg.steps.length ? +sg.steps[sg.steps.length - 1].from : 4; sg.steps.push({ from: String(last < 7 ? 7 : 10), add: "1" }); }));
    steps.appendChild(addStep); el.appendChild(steps);
    if (showGs) el.appendChild(E("div", "sgnote", "saves as attribute " + HR_START_NAME + " = " + sg.n + (sg.kind === "die" ? " (the die size)" : "") + "; trigger beginturn gains " + (sg.kind === "die" ? "1d " : "") + HR_START_NAME + " while it is above 0; checklist line reads it"));
    gs.appendChild(el);
  }
  cls.gains.forEach((g, i) => {
    const el = E("div", "sent"); el.style.setProperty("--c", "var(--c-res)");
    // A line the class keeps with no trigger of its own (applied by another feature) is shown as saved.
    if (g.event === "manual") { el.appendChild(E("span", null, g.src.check.details || g.src.check.name)); el.appendChild(E("span", "grow")); el.appendChild(E("span", "aside", "Applied by another feature")); gs.appendChild(el); return; }
    el.appendChild(pickTok(g, "event", gainEvents(g).map(e => [e[0], e[1]]))); const rw = (cls.resourceName || "resource").toLowerCase();
    // "you gain 2 resolve", or "you gain a number of resolve equal to your Victories" for a formula.
    // The comma sits right against the event word: the row spaces its pieces out, so pull it back.
    const comma = E("span", null, ","); comma.style.marginLeft = "-4px"; el.appendChild(comma);
    if (fxIsCount(g, "qty") || !String(g.qty || "").trim()) { el.appendChild(document.createTextNode("you gain ")); el.appendChild(fxTok(g, "qty", "1")); el.appendChild(lbl(rw)); }
    else { el.appendChild(document.createTextNode("you gain a number of " + rw + " equal to ")); el.appendChild(fxTok(g, "qty", "1", true)); }
    el.appendChild(E("span", "grow"));
    const mb = fk(E("button", "mb", "\u22ef"), "gainmb:" + g.id); mb.type = "button"; mb.setAttribute("aria-label", "Options");
    mb.addEventListener("click", ev => { ev.stopPropagation(); menuAt(mb, m => { const x = E("button", null, "Delete"); x.type = "button"; x.addEventListener("click", () => { closeMenu(); pendingFk = "addgain"; change(() => cls.gains.splice(i, 1)); toast("Deleted that way to gain " + (cls.resourceName || "it").toLowerCase() + ".", { label: "Undo", run: undo }); }); m.appendChild(x); }); });
    el.appendChild(mb);
    if (showGs) { const ev = gainEvents(g).find(e => e[0] === g.event) || GAIN_EVENTS[0]; el.appendChild(E("div", "saves", "saves as checklist line (once per " + ({ round: "round", encounter: "encounter", recurring: "time" })[ev[2]] + ") + trigger " + ev[0] + ": Replenish " + fxFormula(g, "qty") + ", checklistid linked")); }
    gs.appendChild(el);
  });
  const ag = fk(E("button", "addsent", "+ add a way to gain " + (cls.resourceName || "it").toLowerCase()), "addgain"); ag.type = "button";
  ag.addEventListener("click", ev => { ev.stopPropagation(); if (cls.startGain) return change(() => cls.gains.push({ id: newId("g"), event: "dealdamage", qty: "1", guid: guid() }));
    menuAt(ag, m => { const a = E("button", null, "At the start of each turn (start-of-turn gain)"); a.type = "button"; a.addEventListener("click", () => { closeMenu(); change(() => { cls.startGain = { kind: "flat", n: "2", steps: [], guid: guid() }; }); });
      const b = E("button", null, "When something happens (combat starts, you deal damage...)"); b.type = "button"; b.addEventListener("click", () => { closeMenu(); change(() => cls.gains.push({ id: newId("g"), event: "dealdamage", qty: "1", guid: guid() })); });
      m.appendChild(a); m.appendChild(b); }); });
  if (!cls.hrRaw) gs.appendChild(ag); board.appendChild(gs);

  }
  // Levels
  const lh = E("div", "lanes-head");
  lh.appendChild(E("h3", "sec", sc ? sc.name + " features by level" : "Levels"));
  if (!sc) {
  const st = E("label", "toggle"); const cb = fk(E("input"), "slowstart"); cb.type = "checkbox"; cb.checked = cls.slowStart;
  const setSlow = () => {
    // Turning it on moves 1st-level features into Encounter 1 (where core classes keep them); the
    // "1st level, after the slow start" lane is for what a hero gets once the slow start is over.
    const moving = cb.checked ? (cls.lanes["level-1"] || []).length : ENCOUNTERS.reduce((n, k) => n + (cls.lanes[k] || []).length, 0);
    change(() => { cls.slowStart = cb.checked; if (cls.slowStart) { cls.lanes["tutoriallevel-1"] = (cls.lanes["tutoriallevel-1"] || []).concat(cls.lanes["level-1"] || []); cls.lanes["level-1"] = []; }
      if (!cls.slowStart) { const moved = ENCOUNTERS.flatMap(k => cls.lanes[k] || []); ENCOUNTERS.forEach(k => delete cls.lanes[k]); cls.lanes["level-1"] = moved.concat(cls.lanes["level-1"] || []); } });
    if (moving) toast(moving + " feature" + (moving === 1 ? "" : "s") + " moved to " + (cls.slowStart ? "Encounter 1." : "1st level."), { label: "Undo", run: undo });
  };
  cb.addEventListener("change", () => {
    if (!cb.checked && ENCOUNTERS.some(k => (cls.lanes[k] || []).length)) { cb.checked = true;
      setTimeout(() => askConfirm(st, "Turn off the slow start rules? Features in Encounters 1\u20134 move into 1st level.", "Turn off", () => { cb.checked = false; setSlow(); }));
      return; }
    setSlow();
  });
  st.appendChild(cb); st.appendChild(document.createTextNode("Uses the slow start rules (Encounters 1–4)")); lh.appendChild(st);
  }
  board.appendChild(lh);
  if (!sc) board.appendChild(E("p", "hint", "Create slow start rules used by Pregen Characters."));
  const keys = laneKeys(); let shown = 0;
  keys.forEach(k => {
    const isLevel = k.startsWith("level-"); const n = isLevel ? +k.slice(6) : 0;
    if (isLevel && n > ed().showLevels && !(ed().lanes[k] || []).length) return;
    shown++; board.appendChild(renderLane(k));
  });
  if (ed().showLevels < 10) {
    const more = fk(E("button", "collapsed-note", "Show levels " + (ed().showLevels + 1) + "\u201310"), "morelevels"); more.type = "button";
    more.addEventListener("click", () => change(() => { ed().showLevels = 10; })); board.appendChild(more);
  }
  window.scrollTo(0, y);
}
/* Finds a block in the class's features (and, with subs, its subclasses' features). Returns the first
   match ({ s, f, k }), or with subs every match with where it is ("the Berserker subclass"). */
function basicsSource(test, subs) {
  const hits = [];
  const scan = (lanes, where) => Object.keys(lanes || {}).forEach(k => (lanes[k] || []).forEach(f => (function walk(l) { (l || []).forEach(x => { if (test(x)) hits.push({ s: x, f, k, where }); walk(x.children); }); })(f.sentences)));
  scan(cls.lanes, "the class's features");
  if (subs) cls.subclasses.forEach(sc => scan(sc.lanes, "the " + sc.name + " subclass"));
  return subs ? hits : hits[0];
}
/* The name row is a row of tabs: the class, then its subclasses to the right, then "+ subclass".
   The tab being shown holds the name field; the others switch to theirs. Each subclass is still its
   own compendium entry (table "subclasses") that stores this class as its parent. */
function nameTabs(input) {
  const bar = E("div", "clsname nametabs"); bar.setAttribute("role", "tablist"); bar.setAttribute("aria-label", "Class and subclasses");
  const tab = (o, kind) => {
    const on = ed() === o, t = E(on ? "div" : "button", "ntab" + (on ? " on" : "") + (kind === "Subclass" ? " sub" : ""));
    t.setAttribute("role", "tab"); t.setAttribute("aria-selected", on ? "true" : "false"); t.appendChild(E("span", "k", kind));
    if (on) t.appendChild(input); else { t.type = "button"; t.appendChild(E("span", "n", o.name)); t.addEventListener("click", () => showView(o === cls ? null : o.id)); fk(t, "subtab:" + (o === cls ? "class" : o.id)); }
    bar.appendChild(t);
  };
  tab(cls, "Class"); cls.subclasses.forEach(x => tab(x, "Subclass"));
  const add = fk(E("button", "ntab add", "+ subclass"), "subtab:new"); add.type = "button"; add.title = "Add a subclass to " + cls.name;
  add.addEventListener("click", () => { change(() => { cls.view = newSubclass().id; openId = null; }); window.scrollTo(0, 0); setTimeout(() => { const i = document.querySelector('[data-fk="cls:name"]'); if (i) { i.focus(); i.select(); } }); });
  bar.appendChild(add);
  return bar;
}
/* Under a subclass's name: which class it belongs to, how players pick it, and Delete. */
function subclassInfo(sc) {
  const b = E("div", "fixed");
  const r = E("div", "row"); r.appendChild(E("span", "lbl", "Parent class"));
  const back = E("button", "tok", cls.name); back.type = "button"; back.title = "Back to the class"; back.addEventListener("click", () => showView(null)); r.appendChild(back);
  const choice = (() => { let at = null; classLaneKeys().forEach(k => (cls.lanes[k] || []).forEach(f => { if (!at && (f.sentences || []).some(x => x.type === "subclassChoice")) at = { f, k }; })); return at; })();
  if (choice) { const [a, n] = laneLabel(choice.k); r.appendChild(lbl("Players choose it at " + a + " " + n + " (\u201c" + featName(choice.f) + "\u201d).")); }
  else r.appendChild(E("span", "aside", "The class has no \u201cChoose your subclass\u201d block yet, so players can't pick it."));
  r.appendChild(E("span", "grow"));
  const del = fk(E("button", "btn small", "Delete subclass"), "subdel"); del.type = "button";
  del.addEventListener("click", () => askConfirm(del, "Delete the " + sc.name + " subclass and its features?", "Delete", () => { change(() => { cls.subclasses = cls.subclasses.filter(x => x !== sc); cls.view = null; openId = null; }); toast("Deleted the " + sc.name + " subclass.", { label: "Undo", run: undo }); }));
  r.appendChild(del); b.appendChild(r); return b;
}
function renderLane(k) {
  const lane = E("div", "lane"); lane.dataset.lane = k;
  const [a, n, sub] = laneLabel(k);
  const ln = E("div", "ln", a); ln.appendChild(E("b", null, n)); if (sub) ln.appendChild(E("small", null, sub)); lane.appendChild(ln);
  const items = E("div", "items");
  (ed().lanes[k] || []).forEach(f => items.appendChild(f.id === openId ? renderFeature(f, k) : chip(f, k)));
  const add = fk(E("button", "addf", "+ add a feature"), "addf:" + k); add.type = "button";
  add.addEventListener("click", ev => { ev.stopPropagation(); menuAt(add, m => { addFilter(m);
    shelfEntries().forEach(([group, items]) => { if (!items.length) return; m.appendChild(E("h5", null, group));
      items.forEach(it => { const x = E("button", null, it.label); x.type = "button"; x.title = it.desc || ""; x.addEventListener("click", () => { closeMenu(); addEntryToLane(it.key, k); }); m.appendChild(x); }); }); }); });
  items.appendChild(add); lane.appendChild(items);
  return lane;
}
/* A feature is drawn in the colour of its first block (orange for an ability, blue for a stat...),
   so it reads as a block on the lanes too. An empty feature uses the neutral block colour. */
function featColor(f) {
  const first = (f.sentences || [])[0]; const d = first && SENT[first.type];
  const g = d && GROUPS.find(x => x[0] === d.group);
  return g ? g[2] : "--c-adv";
}
function chip(f, k) {
  const bad = featureIssues(f, k).some(x => !x.soft);
  const c = fk(E("button", "chip blockchip" + (bad ? " bad" : "")), "chip:" + f.id); c.type = "button"; c.dataset.drag = "feature"; c.dataset.value = f.id;
  c.style.setProperty("--c", "var(" + featColor(f) + ")");
  const gr = E("span", "grip"); gr.innerHTML = GRIP; c.appendChild(gr);
  c.appendChild(E("span", "nm", featName(f)));
  c.title = kindLabel(f) + (bad ? ". Something to finish." : "") + (featText(f) ? "\n" + featText(f) : "");
  c.addEventListener("click", () => { if (c.dataset.dragged) return; openFeature(f.id); });
  return c;
}
function openFeature(id) { openId = id; render(); restoreFocus("fname:" + id); const el = document.querySelector('[data-fk="fname:' + id + '"]'); if (el) el.scrollIntoView({ block: "nearest" }); }
function addFeature(tpl, laneKey) {
  const f = newFeature(tpl);
  const place = () => { const o = ed(); (o.lanes[laneKey] = o.lanes[laneKey] || []).push(f); openId = f.id; pendingFk = "fname:" + f.id;
    if (laneKey.startsWith("level-") && +laneKey.slice(6) > o.showLevels) o.showLevels = +laneKey.slice(6); };
  // A feature made around an ability goes straight to the ability editor, and is only placed on Done.
  if (tpl.opens) { const s = f.sentences[0]; openEditor({ rec: null, kind: tpl.opens === "trigger" ? "triggered" : "ability" }, (rec, display, problems) => { s.f.rec = rec; s.f.problems = problems; if (display !== undefined) s.f.display = display; if (!f.name && rec) f.name = recName(rec); place(); }); return; }
  change(place);
}
/* Pointer dragging, as in the ability editor (works with touch too): a ghost follows the pointer and a
   gold line shows where it lands. Drag a shelf block onto a level or into the open feature, drag a block
   to reorder it, or drag a feature chip to another level. A short press is still a click. */
const GRIP = '<svg viewBox="0 0 10 14" aria-hidden="true"><circle cx="2" cy="2" r="1.4"/><circle cx="8" cy="2" r="1.4"/><circle cx="2" cy="7" r="1.4"/><circle cx="8" cy="7" r="1.4"/><circle cx="2" cy="12" r="1.4"/><circle cx="8" cy="12" r="1.4"/></svg>';
const LISTS = {};   // id -> { list, feat }, filled while rendering each block list
let drag = null, dropLine = null;
const ghost = E("div", "ghost"); document.body.appendChild(ghost);
document.addEventListener("pointerdown", ev => {
  if (ev.button !== 0) return;
  const el = ev.target.closest("[data-drag]"); if (!el || ev.target.closest(".tok, .mb, input, textarea, .card, .btn, .addsent.inblock")) return;
  drag = { el, kind: el.dataset.drag, value: el.dataset.value, sx: ev.clientX, sy: ev.clientY, live: false };
  const r = el.getBoundingClientRect(); drag.ox = ev.clientX - r.left; drag.oy = ev.clientY - r.top;
});
document.addEventListener("pointermove", ev => {
  if (!drag) return;
  if (!drag.live) {
    if (Math.hypot(ev.clientX - drag.sx, ev.clientY - drag.sy) < 6) return;
    drag.live = true; closeMenu();
    ghost.innerHTML = ""; const c = drag.el.cloneNode(true); c.style.width = drag.el.getBoundingClientRect().width + "px"; ghost.appendChild(c); ghost.style.display = "block";
    drag.el.classList.add("dragging"); document.body.classList.add("is-dragging");
    markDropZones();
  }
  ghost.style.transform = "translate(" + (ev.clientX - drag.ox) + "px," + (ev.clientY - drag.oy) + "px)";
  drag.target = dropTarget(ev.clientX, ev.clientY); showDrop(drag.target);
});
document.addEventListener("pointerup", () => {
  if (!drag) return;
  const d = drag; drag = null; ghost.style.display = "none"; ghost.innerHTML = ""; d.el.classList.remove("dragging"); document.body.classList.remove("is-dragging"); showDrop(null);
  document.querySelectorAll(".can-drop").forEach(z => z.classList.remove("can-drop"));
  if (!d.live) return;
  d.el.dataset.dragged = "1"; setTimeout(() => delete d.el.dataset.dragged, 0);
  if (d.target) doDrop(d, d.target);
});
const isFeatureDrag = k => k === "feature";
/* Where would this land? A level (features) or a position in a block list (blocks). */
function dropTarget(x, y) {
  const under = document.elementFromPoint(x, y); if (!under) return null;
  if (isFeatureDrag(drag.kind)) { const lane = under.closest(".lane"); return lane ? { lane: lane.dataset.lane, el: lane } : null; }
  // A shelf entry over an open feature's blocks goes into them; anywhere else on a level, it makes a feature.
  const box = under.closest(".sents[data-list]");
  if (!box) { if (drag.kind !== "entry") return null; const lane = under.closest(".lane"); return lane ? { lane: lane.dataset.lane, el: lane } : null; }
  if (!listAccepts(box)) return null;
  const rows = [...box.children].filter(c => c.classList.contains("sent"));
  let idx = rows.length;
  for (let i = 0; i < rows.length; i++) { const r = rows[i].getBoundingClientRect(); if (y < r.top + r.height / 2) { idx = i; break; } }
  return { list: box.dataset.list, idx, el: box, before: rows[idx] || box.querySelector(":scope > .addsent") };
}
/* Can the block being dragged go into this block list? (Logic and aura bodies take no choices or
   wrappers; a combined roll change takes only roll changes; nothing goes inside itself.) */
function listAccepts(box) {
  const L = LISTS[box.dataset.list]; if (!L || !drag) return false;
  if (drag.kind === "feature") return false;
  if (drag.kind !== "entry" && drag.el.contains(box)) return false;
  const type = drag.kind === "entry" ? (drag.value.startsWith("s:") ? drag.value.slice(2) : null) : (findSentence(drag.value) || {}).s?.type;
  if (L.inIf && type && (SENT[type].choice || SENT[type].wrapper || SENT[type].container)) return false;
  if (L.inIf && drag.kind === "entry" && !drag.value.startsWith("s:")) return false;
  if (L.combo && !(type && comboAccepts(L.combo, type, drag.kind === "entry" ? null : drag.value))) return false;
  return true;
}
/* While dragging, every place that can take the block is outlined, so it's clear where it can go:
   levels (a new feature there) for shelf blocks and features, and block lists for blocks. */
function markDropZones() {
  if (drag.kind === "entry" || drag.kind === "feature") document.querySelectorAll(".lane").forEach(l => l.classList.add("can-drop"));
  document.querySelectorAll(".sents[data-list]").forEach(b => { if (listAccepts(b)) b.classList.add("can-drop"); });
}
/* The spot it would land opens up: a dashed slot about the size of the block, with what happens. */
let dropKey = null;
function showDrop(t) {
  const key = t ? (t.lane ? "lane:" + t.lane : t.list + ":" + t.idx) : null;
  if (key === dropKey) return; dropKey = key;
  document.querySelectorAll(".lane.drop").forEach(l => l.classList.remove("drop"));
  if (dropLine) { dropLine.remove(); dropLine = null; }
  if (!t) return;
  const h = Math.max(34, Math.min(64, drag ? drag.el.getBoundingClientRect().height : 40));
  dropLine = E("div", "dropslot", t.lane ? (drag && drag.kind === "feature" ? "Move the feature here" : "Drop to make a new feature here") : "Drop here");
  dropLine.style.height = h + "px";
  if (t.lane) { t.el.classList.add("drop"); const items = t.el.querySelector(".items"), add = items && items.querySelector(":scope > .addf"); if (add) add.before(dropLine); else if (items) items.appendChild(dropLine); return; }
  if (t.before) t.before.before(dropLine); else t.el.appendChild(dropLine);
}
function findSentence(id) {
  for (const k in LISTS) { const L = LISTS[k]; const i = L.list.findIndex(x => x.id === id); if (i >= 0) return { s: L.list[i], L, i }; }
  return null;
}
function doDrop(d, t) {
  if (t.lane) {
    if (d.kind === "entry") return addEntryToLane(d.value, t.lane);
    return change(() => { const o = ed(), at = findFeature(d.value); if (!at || at.lane === t.lane) return; o.lanes[at.lane] = o.lanes[at.lane].filter(x => x !== at.feat); (o.lanes[t.lane] = o.lanes[t.lane] || []).push(at.feat);
      const n = +t.lane.slice(6); if (t.lane.startsWith("level-") && n > o.showLevels) o.showLevels = n; });
  }
  const L = LISTS[t.list];
  if (d.kind === "entry") return addEntryToList(d.value, L.feat, L.list, t.idx, L.inIf);
  const from = findSentence(d.value); if (!from) return;
  const inside = (x, l) => childLists(x).some(cl => cl === l || cl.some(c => inside(c, l)));
  if (inside(from.s, L.list)) return;   // an "Only if" can't go inside itself
  // Dragged out of a combined block: it takes the shared keywords and roll options with it.
  change(() => { if (from.L.combo && from.L.combo !== L.combo) uncombine(from.L.combo, from.s); from.L.list.splice(from.i, 1); let idx = t.idx; if (from.L.list === L.list && from.i < idx) idx--; L.list.splice(idx, 0, from.s); });
}

function renderFeature(f, laneKey) {
  const box = E("div", "feat"); box.style.setProperty("--c", "var(" + featColor(f) + ")");
  // The open feature's header is the block itself, in the feature's colour.
  const head = E("div", "feat-head blockhead"); head.title = kindLabel(f);
  const nin = fk(E("input", "fname"), "fname:" + f.id); nin.value = f.name; nin.placeholder = featName(f) === "Unnamed feature" ? "Feature name" : featName(f); nin.setAttribute("aria-label", "Feature name");
  nin.addEventListener("change", () => setTimeout(() => change(() => { f.name = nin.value.trim(); }))); head.appendChild(nin);
  const close = fk(E("button", "btn small", "Close"), "close:" + f.id); close.type = "button"; close.addEventListener("click", () => { openId = null; render(); restoreFocus("chip:" + f.id); }); head.appendChild(close);
  box.appendChild(head);
  const ta = fk(E("textarea", "ftext"), "ftext:" + f.id); ta.value = f.text; ta.placeholder = autoText(f) || "The feature's text, as the book prints it";
  // Typed text remembers the blocks' wording at that moment, so a later change to the blocks is flagged.
  ta.addEventListener("change", () => setTimeout(() => change(() => { f.text = ta.value; f.textBasis = ta.value ? autoText(f) : null; }))); box.appendChild(ta);
  if (!f.text && autoText(f)) box.appendChild(E("div", "hint", "The text above is written for you from the blocks below. Type over it to use your own wording."));
  if (textStale(f)) box.appendChild(staleNote(f));
  const lb = E("div", "lbl2", "What it does");
  if (showGs) lb.appendChild(E("span", "mono saves-type", " \u00b7 saves as " + compileFeature(f).__typeName));
  box.appendChild(lb);
  const sents = E("div", "sents"); regList(sents, f.sentences, f, false);
  {
    renderSentenceList(f.sentences, f, sents);
    const add = fk(E("button", "addsent", "+ add what it does"), "addsent:" + f.id); add.type = "button";
    add.addEventListener("click", ev => { ev.stopPropagation(); sentenceMenu(add, type => addSentence(f, f.sentences, type)); });
    sents.appendChild(add);
  }
  box.appendChild(sents);
  const foot = E("div", "feat-foot");
  const lanes = laneKeys();
  const mv = fk(E("button", "btn small", "Move to…"), "move:" + f.id); mv.type = "button";
  mv.addEventListener("click", ev => { ev.stopPropagation(); menuAt(mv, m => lanes.forEach(k => { const [a, n, sub] = laneLabel(k); const x = E("button", null, a + " " + n + (sub ? " (" + sub + ")" : "")); x.type = "button";
    x.addEventListener("click", () => change(() => { const o = ed(); o.lanes[laneKey] = o.lanes[laneKey].filter(y => y !== f); (o.lanes[k] = o.lanes[k] || []).push(f); if (k.startsWith("level-") && +k.slice(6) > o.showLevels) o.showLevels = +k.slice(6); })); m.appendChild(x); })); });
  foot.appendChild(mv);
  const dup = fk(E("button", "btn small", "Duplicate"), "dup:" + f.id); dup.type = "button";
  dup.addEventListener("click", () => change(() => { const c = cloneFeature(f); ed().lanes[laneKey].push(c); openId = c.id; pendingFk = "fname:" + c.id; }));
  foot.appendChild(dup);
  const sv = fk(E("button", "btn small", "Save as recipe"), "tpl:" + f.id); sv.type = "button"; sv.title = "Keep this feature on your shelf as a recipe, to reuse in any class or share";
  sv.addEventListener("click", ev => { ev.stopPropagation(); saveTemplateMenu(sv, f); });
  foot.appendChild(sv);
  const del = fk(E("button", "btn small", "Delete"), "del:" + f.id); del.type = "button";
  del.addEventListener("click", () => { pendingFk = "addf:" + laneKey; change(() => { const o = ed(); o.lanes[laneKey] = o.lanes[laneKey].filter(y => y !== f); openId = null; });
    toast("Deleted \u201c" + featName(f) + "\u201d.", { label: "Undo", run: undo }); });
  foot.appendChild(del);
  box.appendChild(foot);
  return box;
}
/* Whether a block type can go into a combined block: a roll change, and no second edge/outcome change. */
function comboAccepts(host, type, movingId) {
  const d = SENT[type]; if (!d || !d.combo) return false;
  return !d.combo.modtype || !host.children.some(c => c.id !== movingId && comboModtypes(c).length);
}
function regList(el, list, feat, inIf) { const id = "l:" + (feat.id || "") + ":" + Object.keys(LISTS).length; LISTS[id] = { list, feat, inIf }; el.dataset.list = id; }
function addSentence(feat, list, type, idx) {
  const s = makeSentence(type);
  const place = () => { if (idx == null || idx > list.length) list.push(s); else list.splice(idx, 0, s); pendingFk = "mb:" + s.id; };
  const d = SENT[type];
  // Ability blocks are only placed when the editor's Done is pressed.
  if (d.opensEditor) return openEditor({ rec: null, kind: d.opensEditor }, (rec, display, problems) => { s.f.rec = rec; s.f.problems = problems; if (display !== undefined) s.f.display = display; if (!feat.name && rec) feat.name = recName(rec); place(); });
  change(place);
}
function sentenceMenu(el, pick, noWrapper, only) {
  menuAt(el, m => GROUPS.forEach(g => {
    // Inside an "Only if" there are no choices or nested wrappers (a choice is made when the feature is gained).
    const types = Object.keys(SENT).filter(t => SENT[t].group === g[0] && t !== "rollCombo" && !(noWrapper && (SENT[t].wrapper || SENT[t].choice || SENT[t].container)) && (!only || only(t))); if (!types.length) return;
    m.appendChild(E("h5", null, g[1]));
    types.forEach(t => { const x = E("button", null, SENT[t].label); x.type = "button"; x.addEventListener("click", () => { closeMenu(); pick(t); }); m.appendChild(x); });
  }));
}
function renderSentenceList(list, feat, into, host) {
  list.forEach((s, i) => into.appendChild(renderSentence(s, list, i, feat, host)));
  // Blocks that could be one roll change get a bracket and a Combine button (drawn once laid out).
  const groups = host ? [] : combinableGroups(list);
  if (groups.length) { into.classList.add("hascombine"); requestAnimationFrame(() => { if (into.isConnected) drawCombineBrackets(into, list, groups); }); }
}
function renderSentence(s, list, i, feat, host) {
  const d0 = SENT[s.type], g = GROUPS.find(x => x[0] === d0.group) || ["adv", "", "--c-adv"];
  // Inside a combined block each block shows only its part ("deal 2 extra damage"); the rest is shared.
  const d = host && d0.combo ? Object.assign({}, d0, { render: d0.combo.render }) : d0;
  const el = E("div", "sent" + (d.wrapper ? " ifwrap" : "")); el.style.setProperty("--c", "var(" + g[2] + ")");
  el.dataset.drag = "block"; el.dataset.value = s.id;
  const line = d.wrapper ? E("div", "ifline") : el;
  const grip = E("span", "grip"); grip.innerHTML = GRIP; grip.title = "Drag to move"; line.appendChild(grip);
  const add = n => line.appendChild(n);
  d.render(s.f, add, s, feat);
  const grow = E("span", "grow"); line.appendChild(grow);
  const mb = fk(E("button", "mb", "⋯"), "mb:" + s.id); mb.type = "button"; mb.setAttribute("aria-label", d.label + " options");
  mb.addEventListener("click", ev => { ev.stopPropagation(); menuAt(mb, m => {
    const item = (t, fn) => { const x = E("button", null, t); x.type = "button"; x.addEventListener("click", () => { closeMenu(); change(fn); }); m.appendChild(x); };
    if (i > 0) item("Move up", () => { [list[i - 1], list[i]] = [list[i], list[i - 1]]; });
    if (i < list.length - 1) item("Move down", () => { [list[i + 1], list[i]] = [list[i], list[i + 1]]; });
    if (!host && !d.wrapper && !d.choice && !d.container) item("Wrap in Logic (Only if\u2026)", () => { const w = makeSentence("onlyIf"); w.children.push(s); list.splice(i, 1, w); });
    if (host) item("Take out of the combined block", () => { list.splice(i, 1); const hl = findSentence(host.id); hl.L.list.splice(hl.i + 1, 0, uncombine(host, s)); });
    if (d.comboHost) item("Split into separate blocks", () => { list.splice(i, 1, ...s.children.map(c => uncombine(s, c))); });
    else if (d.wrapper) item("Remove the \u201c" + d.label.replace(/\.\.\.$/, "") + "\u201d (keep what's inside)", () => { list.splice(i, 1, ...s.children); });
    const delItem = E("button", null, "Delete"); delItem.type = "button";
    delItem.addEventListener("click", () => { closeMenu(); pendingFk = "addsent:" + feat.id; change(() => { list.splice(i, 1); }); toast("Deleted \u201c" + d.label + "\u201d.", { label: "Undo", run: undo }); }); m.appendChild(delItem);
  }); });
  line.appendChild(mb);
  if (d.wrapper) {
    el.appendChild(line);
    const body = E("div", "ifbody sents"); regList(body, s.children, feat, true); if (d.comboHost) LISTS[body.dataset.list].combo = s;
    renderSentenceList(s.children, feat, body, d.comboHost ? s : null);
    const add2 = fk(E("button", "addsent", d.comboHost ? "+ add a roll change" : "+ add inside"), "addin:" + s.id); add2.type = "button";
    add2.addEventListener("click", ev => { ev.stopPropagation(); sentenceMenu(add2, type => addSentence(feat, s.children, type), true, d.comboHost ? t => comboAccepts(s, t) : null); });
    body.appendChild(add2); el.appendChild(body);
    if (d.comboHost) { const foot = E("div", "combofoot"); appliesPhrase(s.f, n => foot.appendChild(n)); el.appendChild(foot); }
  } else if (showGs) {
    if (d.choice) { const r = d.compileChoice(s.f, feat, {}), m = d.compile ? compileSentences([s], { name: featName(feat), text: featText(feat) }) : [];
      const lines = m.map(savesLine); if (r) lines.push("saves as a " + r.__typeName + " (the player's choice)" + (r.options ? ": " + r.options.length + " option" + (r.options.length === 1 ? "" : "s") : r.tag ? ": tag " + r.tag : ""));
      el.appendChild(E("div", "saves", lines.join("\n") || "(nothing saved yet)")); }
    else { const recs = compileSentences([s], { name: featName(feat), text: featText(feat) });
      el.appendChild(E("div", "saves", recs.length ? recs.map(savesLine).join("\n") : "(nothing saved yet)")); }
  }
  return el;
}
/* "saves as attribute: hitpoints, value 3": the record's behaviour and its interesting fields. */
function savesLine(r) {
  const skip = new Set(["__typeName", "name", "description", "behavior", "activatedAbility", "triggeredAbility", "ability"]);
  const parts = Object.keys(r).filter(k => !skip.has(k)).map(k => k + " " + JSON.stringify(r[k]).slice(0, 80));
  return "saves as " + (r.behavior || r.__typeName) + (parts.length ? ": " + parts.join(", ") : "");
}
/* The shelf, in the ability editor's look: coloured blocks with a grip, hover for what each does. */
function shelfBlock(label, color, uses, title, dragKind, value, onClick, disabled) {
  const b = E("button", "pal"); b.type = "button"; b.style.setProperty("--c", "var(" + color + ")");
  b.dataset.drag = dragKind; b.dataset.value = value; b.title = title; fk(b, "shelf:" + dragKind + ":" + value);
  const h = E("span", "grip"); h.innerHTML = GRIP; b.appendChild(h); b.appendChild(E("span", "pl", label));
  if (disabled) b.setAttribute("aria-disabled", "true");
  b.addEventListener("click", () => { if (b.dataset.dragged) return; onClick(); });
  return b;
}
const groupColor = g => (GROUPS.find(x => x[0] === g) || [0, 0, "--c-adv"])[2];
/* The shelf's entries by group: [group label, [{ key, label, color, uses, desc }]]. */
function shelfEntries() {
  const out = [];
  const mine = (store.templates || []).map(t => ({ key: "t:" + t.id, label: t.name, color: "--c-mine", desc: "Your recipe: " + (sentenceProse(t.feature) || "(no blocks)"), tpl: t }));
  out.push(["Your recipes", mine]);
  const groups = GROUPS.map(g => {
    const items = Object.keys(SENT).filter(t => SENT[t].group === g[0] && SENT[t].shelf !== false).map(t => ({ key: "s:" + t, label: SENT[t].label, color: g[2], uses: SENT[t].uses, desc: SENT[t].desc }))
      .concat(RECIPES.filter(r => r.group === g[0]).map(r => ({ key: "r:" + r.key, label: r.label, color: g[2], uses: r.uses, desc: r.desc + " A recipe: adds the blocks for you to edit.", recipe: true })));
    items.sort((a, b) => (b.uses || 0) - (a.uses || 0));
    return [g[1], items, g[2]];
  });
  // Common: what class authors reach for most (each also stays in its own group).
  const all = groups.flatMap(g => g[1]);
  const common = COMMON_KEYS.map(k => all.find(it => it.key === k)).filter(Boolean).map(it => Object.assign({}, it, { common: true }))
    .concat([{ key: "empty", label: "Empty feature", color: "--c-adv", desc: "A feature with a name and text; add blocks to it." }]);
  out.push(["Common", common]);
  return out.concat(groups);
}
const COMMON_KEYS = ["s:ability", "s:trigger", "s:stat", "s:edge", "s:skills", "s:perkChoice", "r:charinc", "r:heroic"];
function renderShelf() {
  const q = (shelf.querySelector("input.search") || {}).value || "";
  shelf.innerHTML = "";
  const s = E("input", "search"); s.id = "shelfSearch"; s.placeholder = "Search the shelf ( / )"; s.value = q; s.setAttribute("aria-label", "Search the shelf");
  s.addEventListener("input", () => { const pos = s.selectionStart; renderShelf(); const n = shelf.querySelector("input.search"); n.focus(); n.setSelectionRange(pos, pos); });
  shelf.appendChild(s);
  const match = t => !q || t.toLowerCase().includes(q.toLowerCase());
  const at = openId && findFeature(openId);
  shelf.appendChild(E("p", "hint", "Drag a block onto a level to make a new feature, or into a feature to add to it. Clicking a block adds it to " + (at ? "\u201c" + featName(at.feat) + "\u201d" : "a new feature") + "."));
  shelfEntries().forEach(([group, items, color]) => {
    const vis = items.filter(it => match(it.label + " " + group + " " + (it.desc || "")));
    if (group === "Your recipes") { if (!vis.length && q) return; }
    else if (!vis.length) return;
    const gh = E("h5", "palhead"); const sw = E("span", "sw"); sw.style.background = "var(" + (color || (group.startsWith("Your") ? "--c-mine" : "--c-adv")) + ")"; gh.appendChild(sw); gh.appendChild(document.createTextNode(group));
    if (group === "Your recipes" && (store.templates || []).length) {
      const sh = fk(E("button", "btn link", "Share all"), "tplshareall"); sh.type = "button"; sh.addEventListener("click", ev => { ev.stopPropagation(); shareTemplates(sh, store.templates); }); gh.appendChild(sh);
    }
    shelf.appendChild(gh);
    const box = E("div", "palgroup");
    if (group === "Your recipes" && !vis.length) box.appendChild(E("p", "hint", "Open a feature and choose \u201cSave as recipe\u201d to keep it here. Import adds ones others share."));
    vis.forEach(it => {
      const click = () => { if (at) { const top = at.feat.sentences; addEntryToList(it.key, at.feat, top, top.length, false); } else addEntryToLane(it.key, laneKeys()[0]); };
      const b = shelfBlock(it.label, it.color, it.uses, it.desc, "entry", it.key, click);
      if (it.recipe) b.querySelector(".pl").appendChild(E("span", "recipe", "recipe"));
      if (it.common) { b.dataset.common = "1"; b.dataset.fk = "shelf:common:" + it.key; }
      if (it.tpl) { const row = E("div", "palrow"); row.appendChild(b); const mb = fk(E("button", "mb", "\u22ef"), "tplmb:" + it.tpl.id); mb.type = "button"; mb.setAttribute("aria-label", it.label + " options");
        mb.addEventListener("click", ev => { ev.stopPropagation(); templateMenu(mb, it.tpl); }); row.appendChild(mb); box.appendChild(row); }
      else box.appendChild(b);
    });
    shelf.appendChild(box);
  });
}
/* Your recipes (saved features): kept in this browser (store.templates), shared as text like classes. */
function saveTemplateMenu(btn, f) {
  menuAt(btn, m => {
    m.appendChild(E("div", "q", "Save this feature to your shelf as a recipe, to reuse in any class. Its abilities come with it."));
    const i = E("input", "filter"); i.value = featName(f) === "Unnamed feature" ? "" : featName(f); i.placeholder = "Name on the shelf"; m.appendChild(i);
    const yn = E("div", "yn"); const ok = E("button", "btn primary", "Save"); ok.type = "button";
    ok.addEventListener("click", () => { const name = i.value.trim() || featName(f); const c = JSON.parse(JSON.stringify(f)); delete c.id; c.name = name;
      (store.templates = store.templates || []).push({ id: guid(), name, feature: c }); closeMenu(); saveStore(); render(); toast("Saved \u201c" + name + "\u201d to your recipes."); });
    i.addEventListener("keydown", e => { if (e.key === "Enter") ok.click(); });
    yn.appendChild(ok); m.appendChild(yn);
  });
}
function templateMenu(btn, t) {
  menuAt(btn, m => {
    const item = (label, fn) => { const x = E("button", null, label); x.type = "button"; x.addEventListener("click", fn); m.appendChild(x); };
    item("Share", () => shareTemplates(btn, [t]));
    item("Rename", () => { m.innerHTML = ""; const i = E("input", "filter"); i.value = t.name; m.appendChild(i); i.focus(); i.select();
      i.addEventListener("keydown", e => { if (e.key === "Enter") { t.name = i.value.trim() || t.name; closeMenu(); saveStore(); render(); } }); });
    item("Delete", () => { closeMenu(); store.templates = store.templates.filter(x => x !== t); saveStore(); render();
      toast("Deleted \u201c" + t.name + "\u201d from your shelf.", { label: "Undo", run: () => { store.templates.push(t); saveStore(); render(); } }); });
  });
}
function shareTemplates(btn, list) {
  const text = JSON.stringify({ classBuilderTemplates: 1, templates: list.map(t => ({ name: t.name, feature: t.feature })) });
  menuAt(btn, m => { m.classList.add("wide"); m.appendChild(E("div", "q", "Copy this and send it. Whoever gets it pastes it into Import, and " + (list.length === 1 ? "the feature joins" : "these " + list.length + " features join") + " their shelf."));
    const ta = E("textarea", "io"); ta.readOnly = true; ta.value = text; m.appendChild(ta);
    const yn = E("div", "yn"); const c = E("button", "btn primary", "Copy"); c.type = "button"; c.addEventListener("click", () => copyText(text, ta)); yn.appendChild(c); m.appendChild(yn); });
}
/* What's left to finish, per feature (hard) and worth checking (soft), each with a fix where one is obvious.
   Shown in the status column and as a red mark on the feature's chip. */
const REQUIRED = { stat: ["value"], damage: ["amount"], immunity: ["amount"], resource: ["num"], reminder: ["text"], modAbility: ["name"], condImm: ["conds"], language: ["ids"], perkChoice: ["groups"] };
function textStale(f) { return !!f.text && f.textBasis != null && f.textBasis !== autoText(f); }
function staleNote(f) {
  const n = E("div", "stale"); n.appendChild(E("span", null, "The blocks have changed since this text was written. Does it still match?"));
  const a = E("button", "btn small", "Use the blocks' wording"); a.type = "button"; a.addEventListener("click", () => change(() => { f.text = ""; f.textBasis = null; }));
  const b = E("button", "btn small", "The text is still right"); b.type = "button"; b.addEventListener("click", () => change(() => { f.textBasis = autoText(f); }));
  n.appendChild(a); n.appendChild(b); return n;
}
function featureIssues(f, lane) {
  const out = [], nm = "\u201c" + featName(f) + "\u201d", [a, n] = laneLabel(lane);
  const add = (msg, soft, fix) => out.push({ feat: f, lane, msg, soft, fix });
  if (!f.sentences.length && !f.src) add(nm + " doesn't do anything yet.", false, { label: "Delete it", run: () => { change(() => { const o = ed(); o.lanes[lane] = o.lanes[lane].filter(x => x !== f); }); toast("Deleted.", { label: "Undo", run: undo }); } });
  if (featName(f) === "Unnamed feature") add("A feature at " + a + " " + n + " has no name.", true);
  (function walk(list) { list.forEach(s => {
    const d = SENT[s.type];
    if (s.type === "growing") s.f.rows.forEach(r => { if (!r.blocks.length) add("The row at " + r.at + " in " + nm + " has no blocks yet, so it only shows text.", true); if (!/^\d+$/.test(String(r.at).trim())) add("A row in " + nm + "'s growing table needs a whole number.", false); });
    if (s.type === "aura" && !s.children.length) add("The aura in " + nm + " has nothing inside: add what it does to creatures in it.", false);
    if (s.type === "onlyIf" && testMissing(s.f.cond)) add("A Logic block in " + nm + " needs a test.", false);
    if (s.f && s.f.applies === "when" && testMissing(s.f.tick)) add("\u201c" + d.label + "\u201d in " + nm + " is automatically selected \u201cwhen\u201d, but needs a test.", false);
    (function effNames(x) { if (!x || typeof x !== "object") return; if ((x.t === "effect" || x.t === "tgEffect") && x.name && !isCompendiumEffect(x.name)) add("\u201c" + x.name + "\u201d in " + nm + " isn't an effect in the compendium. Check the spelling, or pick one from the list.", true);
      ["a", "cond", "offer", "tick"].forEach(k => effNames(x[k])); (x.items || []).forEach(effNames); })(s.f);
    if (s.f && s.f.offer && testMissing(s.f.offer)) add("\u201c" + d.label + "\u201d in " + nm + " has an unfinished \u201cOffered when\u201d test.", false);
    if (s.type === "onlyIf" && !s.children.length) add("A Logic block in " + nm + " has nothing inside.", false, { label: "Remove it", run: () => change(() => { const L = findList(f, s); if (L) L.splice(L.indexOf(s), 1); }) });
    if ((s.type === "ability" || s.type === "trigger") && !s.f.rec) add(nm + " has an ability that isn't built yet.", false, { label: "Build it", run: () => openEditor({ rec: null, kind: d.opensEditor }, (rec, display, problems) => { s.f.rec = rec; s.f.problems = problems; if (display !== undefined) s.f.display = display; }) });
    if ((s.type === "ability" || s.type === "trigger") && s.f.rec && s.f.problems) add("\u201c" + recName(s.f.rec) + "\u201d in " + nm + " has " + s.f.problems.length + " thing" + (s.f.problems.length === 1 ? "" : "s") + " to finish: " + s.f.problems[0], false,
      { label: "Edit it", run: () => openEditor({ rec: s.f.rec, display: s.f.display || null, kind: d.opensEditor }, (rec, display, problems) => { s.f.rec = rec; s.f.problems = problems; if (display !== undefined) s.f.display = display; }) });
    if (s.type === "abilityChoice") {
      if (!s.f.options.length) add(nm + " has no abilities to choose from.", false, { label: "+ New ability", run: () => newOption(s.f, f) });
      else if (s.f.options.length < (+s.f.num || 1)) add(nm + " offers " + s.f.options.length + " but players choose " + s.f.num + ".", false, { label: "+ New ability", run: () => newOption(s.f, f) });
      s.f.options.forEach(o => { if (o.problems) add("\u201c" + recName(o.rec) + "\u201d in " + nm + " has " + o.problems.length + " thing" + (o.problems.length === 1 ? "" : "s") + " to finish: " + o.problems[0], false,
        { label: "Edit it", run: () => openEditor({ rec: o.rec, kind: "ability" }, (rec, dd, problems) => { o.rec = rec; o.problems = problems; }) }); });
    }
    if (s.type === "skills" && !s.f.granted.length && !(+s.f.num > 0)) add(nm + " gives no skills: pick fixed skills or a number to choose.", false);
    (REQUIRED[s.type] || []).forEach(k => { const v = s.f[k]; if (v == null || v === "" || (Array.isArray(v) && !v.length)) add("\u201c" + d.label + "\u201d in " + nm + " is missing a value.", false); });
    childLists(s).forEach(walk);
  }); })(f.sentences);
  if (textStale(f)) add("The blocks in " + nm + " changed since its text was written.", true, { label: "Use the blocks' wording", run: () => change(() => { f.text = ""; f.textBasis = null; }) });
  return out;
}
function findList(f, s) { let r = null; (function walk(l) { l.forEach(x => { if (x === s) r = l; childLists(x).forEach(walk); }); })(f.sentences); return r; }
function classIssues() {
  if (ed() !== cls) return subclassIssues(ed());
  const out = [];
  if (!cls.resourceName) out.push({ msg: "The heroic resource has no name.", soft: false });
  if (!cls.gains.length && !cls.hrRaw) out.push({ msg: "There's no way to gain " + (cls.resourceName || "the resource").toLowerCase() + " yet.", soft: true });
  if (cls.startGain && !String(cls.startGain.n).trim()) out.push({ msg: "The start-of-turn " + (cls.resourceName || "resource").toLowerCase() + " gain has no amount.", soft: false });
  cls.gains.forEach(g => { if (!String(g.qty || "").trim()) out.push({ msg: "A way to gain " + (cls.resourceName || "the resource").toLowerCase() + " has no amount.", soft: false }); });
  if (!Object.keys(cls.primary).length) out.push({ msg: "Pick the class's starting characteristics.", soft: false });
  if (!String(cls.recoveries || "").trim() && !classLaneKeys().some(k => (cls.lanes[k] || []).some(f => (f.sentences || []).some(x => x.type === "resource" && x.f.res === RES.recovery))))
    out.push({ msg: "The class has no Recoveries.", soft: true });
  classLaneKeys().forEach(k => (cls.lanes[k] || []).forEach(f => out.push(...featureIssues(f, k))));
  // Subclasses are checked on their own page; here, one line each that has something to finish.
  const hasChoice = classLaneKeys().some(k => (cls.lanes[k] || []).some(f => (f.sentences || []).some(x => x.type === "subclassChoice")));
  cls.subclasses.forEach(sc => { const n = subclassIssues(sc).filter(x => !x.soft).length;
    if (n) out.push({ msg: "The " + sc.name + " subclass has " + n + " thing" + (n === 1 ? "" : "s") + " to finish.", soft: false, fix: { label: "Open it", run: () => showView(sc.id) } }); });
  if ((cls.subclasses.length || compendiumSubclasses().length) && !hasChoice) out.push({ msg: "The class has subclasses, but no \u201cChoose your subclass\u201d block, so players can't pick one.", soft: true });
  if (hasChoice && !cls.subclasses.length && !compendiumSubclasses().length) out.push({ msg: "Players choose a subclass, but there are none yet.", soft: true, fix: { label: "Add a subclass", run: () => { change(() => { cls.view = newSubclass().id; openId = null; }); } } });
  return out;
}
/* A subclass's own checks: its features, and that it has a name. */
function subclassIssues(sc) {
  const out = [];
  if (!String(sc.name || "").trim() || sc.name === "New Subclass") out.push({ msg: "The subclass needs a name.", soft: false });
  const saved = cls.view; cls.view = sc.id;   // featureIssues' fixes act on the board being shown
  try { classLaneKeys().forEach(k => (sc.lanes[k] || []).forEach(f => out.push(...featureIssues(f, k)))); } finally { cls.view = saved; }
  return out;
}
/* The right-hand column: the class's status (what's left to finish), then what the engine would store. */
function renderSide() {
  side.innerHTML = "";
  const issues = classIssues(), hard = issues.filter(x => !x.soft), soft = issues.filter(x => x.soft);
  side.appendChild(E("h3", "sec", "Status"));
  const sum = E("div", "status " + (hard.length ? "bad" : soft.length ? "check" : "ok"));
  sum.appendChild(E("span", "dot")); sum.appendChild(E("span", null, hard.length ? hard.length + " thing" + (hard.length === 1 ? "" : "s") + " to finish" + (soft.length ? ", " + soft.length + " worth checking" : "")
    : soft.length ? "Ready to save, " + soft.length + " thing" + (soft.length === 1 ? "" : "s") + " worth checking" : "Ready to save"));
  side.appendChild(sum);
  const list = E("ul", "issues");
  hard.concat(soft).forEach((x, i) => {
    const li = E("li", x.soft ? "soft" : ""); li.appendChild(E("span", "msg", x.msg));
    const row = E("div", "fixes");
    if (x.feat) { const go = fk(E("button", "btn small", "Show"), "go:" + i); go.type = "button"; go.addEventListener("click", () => openFeature(x.feat.id)); row.appendChild(go); }
    if (x.fix) { const b = E("button", "btn small primary", x.fix.label); b.type = "button"; b.addEventListener("click", () => x.fix.run()); row.appendChild(b); }
    if (row.children.length) li.appendChild(row);
    list.appendChild(li);
  });
  side.appendChild(list);
  savedPanel();
}
function savedPanel() {
  const at = openId && findFeature(openId);
  const det = E("details", "savedbox"); det.open = !!savedOpen; det.addEventListener("toggle", () => { savedOpen = det.open; });
  det.appendChild(E("summary", null, "Saved data (for developers)"));
  det.appendChild(E("p", "hint", "Only needed when working on the app itself. To send this class to someone, use Share."));
  const json = JSON.stringify(compiledSub || compiled, null, 2);
  const cp = E("button", "btn small", "Copy the engine record"); cp.type = "button"; cp.addEventListener("click", () => copyText(json, null)); det.appendChild(cp);
  if (at) { det.appendChild(E("h3", "sec", "\u201c" + featName(at.feat) + "\u201d")); det.appendChild(E("pre", "saved", JSON.stringify(compileFeature(at.feat), null, 2))); }
  if (compiledSub) { det.appendChild(E("h3", "sec", "Whole subclass (table subclasses; empty levels left out)")); det.appendChild(E("pre", "saved", JSON.stringify(trimLevels(compiledSub), null, 2))); side.appendChild(det); return; }
  det.appendChild(E("h3", "sec", "Whole class (empty levels left out)"));
  det.appendChild(E("pre", "saved", JSON.stringify(trimLevels(compiled), null, 2)));
  if (cls.subclasses.length) { det.appendChild(E("h3", "sec", "Subclasses (table subclasses)")); det.appendChild(E("pre", "saved", JSON.stringify(cls.subclasses.map(x => trimLevels(compileSubclass(x))), null, 2))); }

  side.appendChild(det);
}
let savedOpen = false;

// ---------------------------------------------------------------------------------------------
// Start
document.getElementById("undoBtn").addEventListener("click", undo);
document.getElementById("redoBtn").addEventListener("click", redo);
document.getElementById("showGs").addEventListener("change", e => { showGs = e.target.checked; render(); });
document.addEventListener("keydown", e => {
  const typing = /INPUT|TEXTAREA/.test(document.activeElement.tagName);
  if ((e.ctrlKey || e.metaKey) && !typing && ((e.key.toLowerCase() === "z" && e.shiftKey) || e.key.toLowerCase() === "y")) { e.preventDefault(); redo(); return; }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z" && !typing) { e.preventDefault(); undo(); }
  if (e.key === "/" && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) { e.preventDefault(); const s = shelf.querySelector("input.search"); if (s) s.focus(); }
});
/* Share a class: Export gives this page's own model as text to copy (downloads don't work in the
   artifact viewer); Import takes that text back, pasted or from a saved .json file. */
function exportBuilder(btn) {
  const text = JSON.stringify({ classBuilder: 1, cls });
  menuAt(btn, m => { m.classList.add("wide"); m.appendChild(E("div", "q", "Copy this text and send it. Whoever gets it pastes it into Import, and the class opens as a new class beside theirs.")); const ta = E("textarea", "io"); ta.readOnly = true; ta.value = text; m.appendChild(ta);
    const yn = E("div", "yn"); const c = E("button", "btn primary", "Copy"); c.type = "button"; c.addEventListener("click", () => copyText(text, ta)); yn.appendChild(c); m.appendChild(yn); });
}
function loadBuilderText(t) {
  let d; try { d = JSON.parse(t); } catch (e) { return toast("That text couldn't be read. Copy the whole Share text again and paste all of it."); }
  if (d && d.classBuilderTemplates && Array.isArray(d.templates)) {
    const added = d.templates.filter(t => t && t.feature && Array.isArray(t.feature.sentences)).map(t => ({ id: guid(), name: String(t.name || "Shared feature"), feature: migrateClass({ lanes: { x: [Object.assign({ id: "f0" }, t.feature)] } }).lanes.x[0] }));
    added.forEach(t => delete t.feature.id);
    store.templates = (store.templates || []).concat(added); closeMenu(); saveStore(); render();
    return toast("Added " + added.length + " recipe" + (added.length === 1 ? "" : "s") + " to your shelf.");
  }
  if (!d || !d.cls || !d.cls.lanes) return toast("That isn't a class or recipe shared from this builder.");
  const ids = t.match(/"id":"[a-z](\d+)"/g) || []; ids.forEach(m => { const n = +m.replace(/\D/g, ""); if (n >= uid) uid = n + 1; });
  // An imported class opens as a new class in the list; the one you had stays as it was.
  closeMenu(); const c = migrateClass(d.cls); if (store.classes[c.id]) c.id = guid();
  newClass(c); toast("Opened \u201c" + cls.name + "\u201d as a new class. Your other classes are in the Open list.");
}
function importBuilder(btn) {
  menuAt(btn, m => { m.classList.add("wide"); m.appendChild(E("div", "q", "Paste a class or recipes someone shared with you, or choose a saved file. A class opens as a new class; features join your shelf.")); const ta = E("textarea", "io"); ta.placeholder = '{"classBuilder":1, ...}'; m.appendChild(ta);
    const yn = E("div", "yn"); const o = E("button", "btn primary", "Open pasted class"); o.type = "button"; o.addEventListener("click", () => loadBuilderText(ta.value));
    const fl = E("label", "btn filebtn", "Choose a file\u2026"); const fi = E("input"); fi.type = "file"; fi.accept = ".json,application/json"; fi.id = "importFile";
    fi.addEventListener("change", () => { const x = fi.files[0]; if (x) x.text().then(loadBuilderText); }); fl.appendChild(fi);
    yn.appendChild(o); yn.appendChild(fl); m.appendChild(yn); });
}
document.getElementById("exportBtn").addEventListener("click", ev => { ev.stopPropagation(); exportBuilder(ev.currentTarget); });
document.getElementById("importBtn").addEventListener("click", ev => { ev.stopPropagation(); importBuilder(ev.currentTarget); });
/* The Open list: every class kept in this browser, plus New and Delete. */
const openSel = document.getElementById("openSel");
function updateOpenSel() {
  openSel.innerHTML = "";
  const g = E("optgroup"); g.label = "Your classes (kept in this browser)";
  const seen = {};
  store.order.forEach(id => { const c = store.classes[id]; if (!c) return; const nm = c.cls.name || "Unnamed class"; seen[nm] = (seen[nm] || 0) + 1;
    const o = E("option", null, nm + (seen[nm] > 1 ? " (" + seen[nm] + ")" : "")); o.value = "open:" + id; g.appendChild(o); });
  openSel.appendChild(g);
  // Core classes from the compendium (core-classes.js): opening one reads its records back into blocks.
  const core = (window.CB_CORE || { classes: [] }).classes;
  if (core.length) { const cg = E("optgroup"); cg.label = "Core classes (from the compendium)";
    core.forEach(c => { const o = E("option", null, c.name + (store.classes[c.id] ? "" : " (open a copy)")); o.value = "core:" + c.id; if (!store.classes[c.id]) cg.appendChild(o); }); if (cg.children.length) openSel.appendChild(cg); }
  [["new", "+ New blank class"], ["delete", "Delete this class\u2026"]].forEach(([v, t]) => { const o = E("option", null, t); o.value = v; openSel.appendChild(o); });
  openSel.value = "open:" + cls.id;
}
openSel.addEventListener("change", () => {
  const v = openSel.value;
  if (v.startsWith("open:")) openClass(v.slice(5));
  else if (v.startsWith("core:")) openCoreClass(v.slice(5));
  else if (v === "new") { newClass(); toast("Started a new class. Your other classes are in the Open list."); }
  else if (v === "delete") { updateOpenSel(); askConfirm(openSel, "Delete \u201c" + cls.name + "\u201d from this browser? This can't be undone.", "Delete class", deleteClass); return; }
  updateOpenSel();
});
// Start once every script has loaded (importer.js adds blocks that opened classes may use).
window.addEventListener("DOMContentLoaded", () => {
  loadStore();
  if (store.current && store.classes[store.current]) openClass(store.current); else newClass();
});
