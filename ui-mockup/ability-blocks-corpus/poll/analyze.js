const { chromium } = require('playwright'); const fs = require('fs');
(async () => {
  const sample = JSON.parse(fs.readFileSync('sample.json', 'utf8'));
  const b = await chromium.launch(); const p = await b.newPage();
  const errs = []; p.on('pageerror', e => errs.push(e.message));
  await p.goto('file:///home/user/draw-steel-codex/ui-mockup/ability-blocks-stack.html'); await p.waitForTimeout(200);
  const res = await p.evaluate((sample) => {
    const MODELED = new Set(["PowerRoll","Damage","Heal","InvokeAbility","ApplyOngoingEffect","RelocateCreature","Aura","GrantTemporaryStamina","Replenish","PurgeEffects","DrawSteelCommand"].map(x => "ActivatedAbility" + x + "Behavior"));
    const GENERIC = new Set(GENERIC_BEHAVIORS.map(g => g[2]));
    const rawSrcs = (x, out) => { if (!x || typeof x !== 'object') return out; if (x.type === 'raw') out.push(x.f.src); for (const k in x) rawSrcs(x[k], out); return out; };
    const out = [];
    for (const r of sample) {
      const issues = [], info = {};
      let a = r.rec;
      if (r.kind !== "ability") { info.modifier = r.kind; a = r.rec.triggeredAbility || r.rec.ability || {}; if (r.kind === "powertabletrigger") { const pm = r.rec.powerRollModifier || {}; info.prt = Object.keys(pm).filter(k => !/^(__|id|name|guid|source|description)/.test(k) && pm[k] !== false && pm[k] !== "" && pm[k] !== 0).slice(0, 12).join(","); } info.trigger = a.trigger || r.rec.trigger; }
      const formula = (kind, docs, f, where) => {
        if (f == null || f === "" || typeof f === "object") return;
        f = String(f); if (kind !== "boolean" && /^\d+$/.test(f)) return;
        if (/<</.test(f)) issues.push(["pipe", where + ": " + f]);
        let h; try { h = holderFromText(kind, docs, f); } catch (e) { issues.push(["formula-error", where + ": " + f]); return; }
        const raws = h.expr ? rawSrcs(h.expr, []) : [];
        if (raws.length) issues.push(["formula-raw", where + ": " + f + "  [raw: " + raws.join(" | ") + "]"]);
      };
      const visitAbility = (ab, depth, label) => {
        if (!ab || typeof ab !== "object") return;
        const tt = ab.targetType;
        if (depth === 0) {
          info.dist = tt + (ab.radius != null ? " r" + ab.radius : "") + " range " + ab.range + (ab.lineDistance != null ? " ld" + ab.lineDistance : "") + " n" + ab.numTargets;
          if (tt && !["self", "target", "all", "cube", "line", "emptyspace"].includes(tt)) issues.push(["distance-form", "targetType " + tt]);
          if (ab.rangeTextOverride) issues.push(["distance-text", "rangeTextOverride: " + ab.rangeTextOverride]);
          if (ab.targetFilter) formula("boolean", "targetFilter", ab.targetFilter, "targetFilter");
          for (const k of ["range", "numTargets", "radius", "lineDistance"]) formula("number", k === "numTargets" ? "numTargets" : "range", ab[k], k);
          formula("number", "cost", ab.resourceNumber, "cost");
          (ab.reasonedFilters || []).forEach(x => formula("boolean", "requirement", x && x.formula, "requirement"));
          (ab.abilityFilters || []).forEach(x => formula("boolean", "requirement", x && x.formula, "requirement"));
          if (ab.conditionFormula) formula("boolean", "stepIf", ab.conditionFormula, "trigger condition");
        }
        if ((ab.modeList || []).length) issues.push(["modes", label + ": " + ab.modeList.length + " modes (" + ab.modeList.map(m => m.text || m.name || "?").join(" / ").slice(0, 120) + ")"]);
        if (ab.multipleModes || ab.modesFromKeywords) issues.push(["modes", label + ": mode flags"]);
        let rolls = 0;
        for (const bh of ab.behaviors || []) {
          if (!bh || typeof bh !== "object") continue;
          const t = bh.__typeName;
          if (t === "ActivatedAbilityPowerRollBehavior") rolls++;
          if (!MODELED.has(t)) issues.push([GENERIC.has(t) ? "behaviour-advanced" : "behaviour-unknown", label + ": " + t.replace(/^ActivatedAbility|Behavior$/g, "")]);
          if (bh.filterTarget) formula("boolean", "stepIf", bh.filterTarget, label + " " + t.replace(/^ActivatedAbility|Behavior$/g, "") + ".filterTarget");
          if (t === "ActivatedAbilityDamageBehavior") formula("roll", "damage", bh.roll, label + " damage");
          if (t === "ActivatedAbilityHealBehavior") formula("roll", "heal", bh.roll, label + " heal");
          if (t === "ActivatedAbilityPowerRollBehavior") {
            formula("roll", "powerRoll", bh.roll, label + " roll");
            (bh.tiers || []).forEach((tx, i) => { const ctx = { todo: 0, matched: 0, tier: "t" + (i + 1), rollChar: "Might", guesses: 0 }; const st = parseTierText(String(tx), ctx); if (ctx.todo) issues.push(["tier-text", label + " tier " + (i + 1) + ": " + tx]); });
          }
          if (t === "ActivatedAbilityInvokeAbilityBehavior" && bh.customAbility) { issues.push(["nested", label + " -> " + (bh.customAbility.name || "custom")]); visitAbility(bh.customAbility, depth + 1, label + ">" + (bh.customAbility.name || "custom")); }
          if (t === "ActivatedAbilityAuraBehavior" && bh.aura) for (const tr of bh.aura.triggers || []) if (tr.ability) visitAbility(tr.ability, depth + 1, label + ">aura " + (tr.trigger || ""));
        }
        if (rolls > 1) issues.push(["multi-roll", label + ": " + rolls + " power rolls"]);
      };
      visitAbility(a, 0, "main");
      if (r.kind === "ability" && !(a.behaviors || []).length) issues.push(["no-behaviours", "text only"]);
      // Paste the book text
      let paste = null;
      if (r.book) {
        try {
          const { ability, ctx } = importAbilityText(r.book);
          const want = a;
          paste = { matched: ctx.matched, todo: ctx.todo, guesses: ctx.guesses, header: ctx.report.length, name: ability.name, cost: cHolder(ability.cost).s, resource: ability.resource, word: ability.resourceWord, dist: ability.distance, target: ability.targetCount, steps: ability.steps.map(s => s.type).join(","),
            todos: [], wantCost: want.resourceNumber };
          const collect = l => l.forEach(s => { if (s.type === "todo") paste.todos.push(s.f.text); for (const k in s.branches || {}) collect(s.branches[k]); });
          collect(ability.steps);
        } catch (e) { paste = { error: String(e) }; }
      }
      out.push({ klass: r.klass, from: r.from, level: r.level, cat: r.cat, name: r.name, info, issues, paste });
    }
    return out;
  }, sample);
  fs.writeFileSync('results.json', JSON.stringify(res, null, 1));
  console.log(errs.slice(0, 5)); await b.close();
})();
