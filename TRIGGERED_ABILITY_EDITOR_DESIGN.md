# Triggered Ability Editor - Design Handoff

Authoritative design document for the new Triggered Ability Editor in Draw Steel Codex (Chunk 4 of [DS_UI_ROADMAP.md](DS_UI_ROADMAP.md)). Supersedes `TRIGGER_PICKER_CATEGORIES.md` and `RESPONSE_SECTION_LABELS.md`, both of which can be deleted once this file is in place.

**Status:** Phases 1-8 fully shipped including Phase 6 (Test Trigger panel), the 2026-04-28 polish pass that fixed all P0/P1 bugs surfaced by the bestiary test sweep (TEST_TRIGGER_PANEL_TESTS.md), the 2026-04-28 follow-up that shipped C2 (plain-language failure prose for function calls), C3 (bounded-value dropdowns for Condition / Damage Type / Resource), and C3.5 (canonical-literal validation chip in Mech View), the 2026-04-29 C2 polish followup that fixed the detail-line capitalisation, the `Self`-vs-`Subject` prose collision (now Draw Steel 2nd-person voice "you"/"your"), renamed the Test Trigger panel role-slot label `"Caster"` -> `"Trigger Owner"`, C5 -- Required Condition gate simulation (hybrid auto-derive + manual override), and (same day 2026-04-29) C4 -- dotted-access inputs for object-typed symbols (`Used Ability.Keywords`, `Cast.X`, `Path.X`) via new `ListReferencedDottedAccesses` walker + per-tail input rows + `GenerateSymbols(nil, stub)` eval-context wrapping. Outstanding work: C6a/b/c (popout floating test panel + reopen-path callbacks). See the "Phase 6 polish pass (2026-04-28)" section below.

---

## Start here (new session orientation)

**You are here because a new session is picking up the Triggered Ability Editor work.** Read this section first.

### Current state in one paragraph
Phases 1-8 shipped + verified. Phase 6 polish pass landed 2026-04-28 -- fixed all P0/P1 bugs from the bestiary test sweep. Same-day follow-up shipped C2 (plain-language failure prose for function calls -- `Path.DistanceToCreature` registered, `GoblinScriptProse.functionUnits` registry, `AttributeFailure` extended with `failingDetail` for compare-with-call-LHS / bare-bool-call / negated-bool-call leaf shapes), C3 (bounded-value dropdowns for Condition / Damage Type / Resource via new `valueOptionsSource` symbol field + `TEST_OPTION_BUILDERS` table; Ongoing Effect dropped from scope -- no trigger.symbols entry exposes it), and C3.5 (edit-time canonical-table literal validation chip in Mech View via new `GoblinScriptProse.WalkLiteralComparisons` walker; gold `#cca350` chip distinguishes typo-class warnings from amber `#c47e2c` structural errors). Remaining: a small C2 polish pass (capitalisation of detail line + `Self` symbol prose collision with `Subject`), C4 (dotted-access inputs -- Used Ability.Keywords, Cast.X, Path.X), C5 (Requires Condition gate simulation, hybrid auto-derive + manual override), and C6a/b/c (popout floating test panel that survives editor close, with reopen-path callbacks for the deepest character-sheet navigation paths).

### Read in this order
1. **This section.** (You are here.)
2. **"Gotchas"** - ten numbered items. Items 1, 5, 6, 9 are load-bearing; read them before touching anything.
3. **"Working artifacts"** - know which files are current vs historical.
4. **"Open questions"** - remaining items that may block specific implementation phases.
5. **"Technical references"** - line-number-level pointers into the codebase. Skim on first read, consult as needed.
6. **Section(s) relevant to whatever you're about to modify.**

### The three highest-danger gotchas
- **"Trigger Subject" is a UI-label-only rename** (gotcha 1) - the form field is labeled "Trigger Subject" but the data field `subject`, the GoblinScript `Subject` symbol, and the runtime token naming are all UNCHANGED. Never rename those; formula migrations are out of scope.
- **Trigger enumeration across multiple files** (gotcha 5) - `MCDMRules.lua` is easy to miss (it has 16 DS triggers), and `Aura.lua`'s triggers must NOT appear in the main picker (they belong to the Create Aura behaviour's embedded editor only).
- **Template literal `${inst}` trap** (gotcha 9) - cost us the mockup's rendering in one session. Never reference per-instance variables from a module-scope `const`; use a function.

### What's blocking further phases
- Nothing structural. Q4 (Condition Prose Engine: launch scope) resolved 2026-04-24 as Option A / Launch Tight -- see opt-in #4 for the 8-pattern launch-tier grammar. Remaining Open Questions (action links UX, test scenario persistence, TriggeredAbilityDisplay deprecation) can be resolved during phase work.
- **Review Items** (aura-behaviour embedded trigger editor) - regression check built into phase 1 via the `options.excludeTriggerCondition` / `options.excludeAppearance` dispatch fallthrough. Retest after any dispatch changes.

### Phase 6 polish pass (SHIPPED 2026-04-28)

A real-bestiary test sweep against `TEST_TRIGGER_PANEL_TESTS.md` (~25 representative triggers + a bonus Mech-View typo case) surfaced two structural bug clusters and a stack of UX issues. All P0/P1/C1 fixes landed in this pass. Same-day follow-up shipped C2 (function-call failure prose), C3 (bounded-value dropdowns for Condition / Damage Type / Resource), and C3.5 (canonical-literal validation chip). 2026-04-29 shipped the C2 polish followup (capitalisation + `Self` -> 2nd-person voice + panel role-slot label `"Caster"` -> `"Trigger Owner"`), C5 (Required Condition gate simulation, hybrid auto-derive + manual override), C4 (dotted-access inputs for object-typed symbols + multi-select keyword picker for set-typed dotted leaves with bounded vocabulary). **Only C6a/b/c (popout floating test panel + reopen-path callbacks) remains open.**

**Structural fixes:**

- **trigger.symbols array-form normalisation** -- many triggers (`dealdamage`, `useability`, `rollpower`, `custom`, plus `forcemove.Vertical`) register their symbols as numerically-indexed arrays (`{ {name = "Damage Type", type = "text"}, ... }`) rather than keyed maps (`damagetype = {...}`). The runtime injects values under a normalised key (lowercase + strip spaces -- `Creature.lua:1999` shows `symbols.damagetype = damageType`). The Test Trigger panel was using the raw `pairs()` key (number 1, 2, ...) so user inputs landed at `symbols[2]` while GoblinScript looked up `symbols.damagetype` -- inputs never reached the formula. Fixed in `discoverTestInputs` via a small `evalKey(rawKey, def)` helper that derives the normalised key from `def.name` when `rawKey` is numeric. **One change resolved both the string-equality cluster (Tests 4/13/14/21/23/24) and the boolean-checkbox cluster (Tests 12/18).** Pattern is reusable for any future code that consumes trigger.symbols.
- **`tokenHasTriggeredAbility` unfiltered modifier walk** -- was using `creature:GetActiveModifiers` (which runs `FilterModifiers` per `Creature.lua:4953`), so any triggered ability whose `filterCondition` was currently false (e.g. See Through with `Ongoing Effects has "Invisible"`) was gated out before the matcher saw it. Now calls `FillBaseActiveModifiers` + `FillTemporalActiveModifiers` + `FillModifiersFromModifiers` directly, bypassing the filter step. Matching uses three layers: identity, guid (`try_get`), name+trigger fallback for compendium-fork paths. Lets the test panel correctly default the Caster slot to the actual owner token even when the ability is conditionally granted.
- **Mech View undeclared-symbol detection** -- "Triggers When" row now flags references like `Damage` on a `creaturedeath` trigger (which exposes no `damage` symbol). Added `unknownReferences(formula, allowed)` helper; allowed set is ambient + trigger.symbols (both forms) + `creature.helpSymbols`. `ListReferencedSymbols` extended to skip identifiers followed by `(` so function calls (Distance, Friends) don't false-positive. Chip text shortened to "Unknown: <name>" with bounded width + textWrap so longer chip text wraps inside the card border instead of overflowing.

**UX fixes:**

- `forcemove.hasattacker` declared as `creature` -> flipped to `boolean` (confirmed by lead dev).
- Subject default respects subject filter: `tokenMatchesSubjectFilter` now excludes the caster for `allies` / `other` / `otherheroes` (was incorrectly including caster because `IsFriend(self,self)` returns true).
- Role-slot filtering: creature-typed event-payload symbols (Attacker, Pusher, Target, ...) only appear when the condition formula references them. Subject (when non-self) stays unconditional.
- Modal token picker no longer fills full vertical viewport -- rows wrapped in inner `height = "auto"` panel mirroring `AbilityEditorTemplates.lua:1436-1453`.
- Minion squad name displays in token picker via `tokenDisplayName(tok)` helper that prefers `MinionSquad()` over `tok.name`.
- `tokenHasTriggeredAbility` `ability:try_get("guid")` instead of bare access (was throwing strict-type errors for ActivatedAbility instances without a guid field).
- Terminology pass: "scene" -> "map" in user-facing UI strings (per user: "map" is the canvas, "scene" is the displayed image to players). Internal function names left alone.

**Outstanding (shipped + remaining):**

- **C2** -- SHIPPED 2026-04-28 (later same day). `Path.DistanceToCreature` registered in the function-prose table; new `GoblinScriptProse.functionUnits` registry maps `Distance` and `Path.DistanceToCreature` to `"squares"`. `AttributeFailure` now computes a `failingDetail` (and per-leaf `detail`) field for three leaf shapes: numeric compare with function-call LHS (re-evaluates LHS via the supplied `evalLeaf`, formats `"<lhs prose> was N <units>."`), bare boolean function call, and `not <funcCall>` (both return `""` to suppress the redundant detail line; headline is self-sufficient). Editor result block prefers `failingDetail`/`detail` when present, falls back to the existing `Formula clause ... evaluated to ...` line for non-call shapes. OR clauses inherit per-clause detail when each clause is a leaf shape; compound branches (e.g. the bugbear `OR(AND, AND)` form) still fall back to the existing `(got X)` annotation -- drilling into compound OR branches is a future improvement, not in C2 scope.
- **C3.5** -- SHIPPED 2026-04-28 (later same day, follow-up to C3). Edit-time canonical-table literal validation chip in the Mech View "Triggers When" row. Catches typos like `Ongoing Effects has "Invasable"` at authoring time rather than waiting for a silent test fail. New `GoblinScriptProse.WalkLiteralComparisons(formula, callback)` walks `hasEq`/`isEq`/`compare(=)` AST leaves with string-literal RHS. Editor's `unknownLiterals(formula, triggerId)` dispatches the LHS shape to a canonical source: dotted-tail `OngoingEffects` / `Conditions` for set-membership `has`, top-level idents matching trigger.symbols entries with `valueOptionsSource` (reuses C3 registration) for `is`/`=`/`!=`. Mismatched literal renders as a gold (`#cca350`) chip "Unknown ongoing effect: \"X\"" -- distinct from the existing amber (`#c47e2c`) "Unknown: <ident>" structural-error chip. Chip schema extended to support `{text, color}` alongside legacy plain-string chips. Identifier-unknown chip wins over literal-unknown chip when both fire (fix structural problem first). Validated against real bestiary formulas (Sudden Downpour, Earth Sink, etc.) -- 0 false positives.
- **C3** -- SHIPPED 2026-04-28 (later same day). Bounded-value dropdowns for three categories: `Condition` (22 entries), `Damage Type` (10 canonical), `Resource` (~8). `Ongoing Effect` was DROPPED from C3 scope because no trigger.symbols declaration in either `TriggeredAbility.lua` or `MCDMRules.lua` exposes it as a `text` symbol -- ongoing-effect comparisons in real authored content go through `Subject.OngoingEffects has "X"` style set-membership on creature properties, not through a dedicated trigger symbol. New `valueOptionsSource` optional field on symbol declarations (e.g. `valueOptionsSource = "damageTypes"`); the test panel's `TEST_OPTION_BUILDERS` table maps each source to a builder that produces `{id, text}` options where `id` matches the runtime injection identity (lowercase damage type / `conditionInfo.name` PascalCase / `string.lower(resourceInfo.name)`). The existing `CharacterCondition.FillDropdownOptions` helper is intentionally NOT reused because it produces GUID-as-id which mismatches GoblinScript's name-based string comparison. Pre-fill is case-insensitive (formulas use both `"Grabbed"` and `"grabbed"`); when matched the stored value normalises to the canonical id. Dropdown prepends a `(none)` sentinel for the unset state. `hasSearch = true` deferred -- option counts comfortable in flat dropdowns. 10 trigger.symbols declarations updated total: 7 Damage Type + 1 Condition + 2 Resource.
- **C2 polish followup -- SHIPPED 2026-04-29.** Three pieces, plus a vocabulary cleanup that surfaced during the design discussion:
    - Detail line capitalisation: `buildFailingDetail` now uppercases the leading char of `lhsPhrase` (helper `capitaliseFirst` co-located in the same closure). Detail now reads "The distance to the attacker was 6 squares." rather than starting lowercase.
    - `Self` prose disambiguation: design discussion surfaced that `Caster` is **narrowly aura-scoped** per [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md) line 66 ("Ambient, aura-triggered abilities only. Absent for standalone triggers.") -- so any plan that re-purposes "Caster" for the generic trigger-owner concept collides with the symbol's locked meaning, and the editor's own helpSymbols block at `NewTriggeredAbilityEditor.lua:959-963` already documents that scoping. Resolution: `S("Self", { role = "you", possessive = "your" })` (was `{ dynamic = "subject" }`). Renders as Draw Steel's locked 2nd-person voice (worksheet line 55: "every real card in the compendium uses second person for the ability owner"). New resolver shape supports tables with explicit `role`/`possessive` fields -- generalises beyond Self for any future role with an irregular possessive. Verified: `Friends(Self, Subject)` with subject=enemy now renders "you and any enemy are friends" (was "any enemy and any enemy are friends"); `Self.Stamina < 10` -> "your stamina is less than 10". Subject and Caster prose unchanged.
    - Test Trigger panel role-slot label `"Caster"` -> `"Trigger Owner"` (`NewTriggeredAbilityEditor.lua:3790-3792`). Eliminates the in-file contradiction between this label and the helpSymbols definition. Pairs with the existing `Trigger Subject` field label -- editor vocabulary now consistently `Trigger X`. The `helpSymbols.caster` entry (formula-help block) is intentionally untouched; its narrow aura-only scope remains correct.
    - **Two-register vocabulary model:** editor language (`Self`, `Subject`, `Trigger Owner`, `Trigger Subject`) is what the author writes/sees in the panel; player language (`you`, `any enemy`, `the aura caster`) is what the rendered card says. The Test Trigger panel's resolved-values grid handles formula-to-token traceability, so prose doesn't need to do double duty as a debug echo.
- **C4 -- SHIPPED 2026-04-29.** Dotted-access inputs for object-typed trigger symbols (`ability`, `spellcast`, `path`, `loc`). Surfaces one input row per (head, tail) pair the formula actually references, with widget kind chosen by operator hint. Affects tests 13, 14, 21.
    - **New** `GoblinScriptProse.ListReferencedDottedAccesses(formula)` walks tokens (not the AST) and returns `{[head_lower] = {displayHead, lookupKey, tails = {[tail_lower] = {displayTail, opHint}}}}`. `lookupKey` is the head with spaces stripped + lowered, matching the runtime injection identity (`usedability`, `cast`, `path`). `opHint` derived from the next token: `has` -> `"has"` (set), `is`/`=`/`!=` -> `"compare-str"`, `>=`/`<=`/`>`/`<` -> `"compare-num"`, otherwise `"bool"`. Skips tails followed by `(` (function calls) or `.` (chained dot, e.g. `Cast.X.Y` not yet supported).
    - **Editor**: in `discoverTestInputs`, the existing else-if branch for `creaturelist`/`path`/`loc` (kind="unsupported") now branches on object-typed symbols. For each such symbol, the new branch consults `ListReferencedDottedAccesses` and emits one input row per tail, id format `"<lookupKey>.<tail_lower>"`, kind from `kindFromOpHint(opHint)` (has -> set, compare-num -> number, bool -> boolean, otherwise text). The bare-head row is NOT emitted -- there's nothing meaningful to type at the head level for an object symbol.
    - **Eval context wiring** (the brief's "risky bit"): `buildEvalContext` now groups `scenario.symbolValues` keys containing `.` by head, builds a stub fields table per head, and wraps with `GenerateSymbols(nil, fields)` so GoblinScript's compiled code (which checks `if type(symbols) == 'table' then symbols = GenerateSymbols(symbols)` on dot access) sees a callable already and skips the inner re-wrap. The reason for `GenerateSymbols(nil, fields)` rather than passing the raw table: GoblinScript's table-wrap path is `GenerateSymbols(self=table, symbolTable=nil)` which then tries `self.lookupSymbols[symbol]` -- a plain table doesn't have that field, so the compare returns 0 ("Runtime error: 0"). Verified empirically before fixing.
    - **Set-typed leaves require StringSet.** `keywords has "Melee"` dispatches at the `function` branch in compiled GoblinScript (calls `result('__is__')` for set membership). Plain Lua tables don't satisfy this dispatch -- the `keywords` field on a real ActivatedAbility is built as `StringSet.new()` (see `ActivatedAbility.lua:4997`). `buildEvalContext`'s grouping now special-cases `info.kind == "set"` and rebuilds the value as a StringSet with lowercased keys (matching GoblinScript's case-insensitive set semantics). Threaded `kind` through `scenario.symbolValues` entries.
    - **Prefill**: `ExtractSatisfyingValues` extended to recognise two-part dotted atoms. `atomIdent(atom)` now returns the composite key `"<lookupKey>.<tail_lower>"` for dotted atoms, matching the input id format. Bare-symbol prefills unchanged. Creature-typed dotted atoms (`Subject.YourTurn`) emit harmlessly-unmatched composite keys -- the role slot path still wires the actual token, so the prefill is just unused.
    - **Verified end-to-end**: synthetic stub `{name="Dig"} -> 'Used Ability.name is "Dig"'` returns 1 (pass). StringSet stub `{keywords=StringSet["melee"]} -> 'Used Ability.Keywords has "Melee"'` returns 1. `Ability.Name is "charge"` against `{name="charge"}` returns 1. Numeric `Used Ability.tier >= 2` against `{tier=2}` returns 1. Cast variant `Cast.tierfortarget >= 2` against `{tierfortarget=3}` returns 1. All compile + execute paths exercised.
    - **Out of scope intentionally**: chained dot (`Cast.X.Y`); per-leaf type override when `=` is used with a numeric RHS (currently always classified `compare-str`, which renders text input -- the runtime accepts both forms and the user can type "3"). Both can be added if real authoring patterns demand them.
    - **C4 followup -- SHIPPED 2026-04-29 (live-test fix):** `evalKey` was returning the trigger.symbols string-key when present, but the runtime injection identity is always derived from the symbol NAME (lowercase + space-stripped), not the declaration key. `targetwithability` declares `ability = { name = "Used Ability", ... }` but [ActivatedAbility.lua:1669](DMHub Game Rules/ActivatedAbility.lua:1669) injects `symbols.usedability = self` -- so the dotted-access lookup mismatched (id="ability" via key, lookupKey from formula="usedability"). Fixed by always preferring `def.name` normalisation, falling back to raw key only when name is missing. Verified across 7 declaration forms: keyed-mismatched (`ability`/`Used Ability` -> `usedability`), keyed-matched (`target`/`Target` -> `target`), bare-array numeric (`Used Ability` -> `usedability`), and existing simple cases (`damagetype`, `hasattacker`).
    - **Bestiary content note (deferred, not C4 scope):** The wider pattern of `Ability.X` (no "Used") in bestiary YAML files is silently broken at runtime -- the runtime injects `usedability`, not `ability`. The Mech View "Unknown: Ability" structural chip correctly flags this. Authors should rewrite `Ability.X` -> `Used Ability.X`. No editor-side fix needed; this is a content-quality issue. Adding an "ability name" literal validator (per user question) would only be useful after the LHS fix, since the literal RHS is never compared against anything when the LHS symbol resolves to nil.
    - **Keyword multi-select picker -- SHIPPED 2026-04-29 (C4 followup):** `Used Ability.Keywords has "X"` (and OR-of-has compounds like `... has "magic" or ... has "psionic"`) now render as a chip-based multi-select picker over `GameSystem.abilityKeywords` (~25 entries) instead of free text. Real authoring patterns in classes / subclasses / inventory frequently OR multiple keyword checks; single-select would mis-model the case where the author wants to verify a stub ability bearing both keywords. New `abilityKeywords` builder in `TEST_OPTION_BUILDERS` (lowercase id, original-case display text). The C4 dotted-access discovery branch attaches `valueOptionsSource = "abilityKeywords"` when `tailKey == "keywords"` and the head's symType is `ability`/`spellcast`. `buildSymbolInputRow` got a new `kind == "set" + valueOptionsSource` branch that mirrors the existing `buildKeywordsPicker` UX (chips with delete buttons + "Add keyword..." dropdown with `hasSearch`); collapses when all keywords are picked. Storage is a comma-separated lowercase string in `v.raw` (compatible with the existing `coerceSymbolInputValue("set", ...)` parse path), so the StringSet wrap in `buildEvalContext` carries through unchanged. Prefill from `ExtractSatisfyingValues` (first OR branch) seeds one chip; user adds the rest via the dropdown. The single-select dropdown branch (kind == "text") for Conditions / Damage Types / Resources is unchanged. Verified: OR-of-has against StringSet stub passes when either keyword is present, fails when neither is.
- **C5 -- SHIPPED 2026-04-29.** Required Condition gate simulation in the Test Trigger panel. Mirrors `TriggeredAbility:subjectHasRequiredCondition` (`TriggeredAbility.lua:699-710`) so the test pre-flight check matches the runtime gate that fires before the conditionFormula. Hybrid auto-derive + manual override per the locked design:
    - New `evaluateRequiredConditionGate(ability, subjectToken, casterToken, override)` helper returns `{kind = "no-gate" | "pass-auto" | "pass-override" | "fail-auto", conditionId, conditionName, requireInflictedBy, autoState, inflicterTokenName}`. Calls `subjectToken.properties:HasCondition(conditionId)` -- which returns the inflicter's tokenid (or `true` for legacy entries with no casterInfo, or `false` for absent). Honours `characterConditionInflictedBySelf` by comparing against `dmhub.LookupTokenId(casterToken)`.
    - `runTriggerTest` evaluates the gate first (after the no-caster check) and short-circuits with new `kind = "gate-fail"` when auto-derived state would block. Gate result is also attached to passing/failing results so the resolved-values grid can surface it.
    - `state.gateOverride` (boolean) persists in the test card's closure-local state alongside `roleSelections` and `symbolValues`. Threaded through `buildScenario -> scenario.gateOverride -> evaluateRequiredConditionGate`.
    - **UI**: new "Required Condition" row sits between role slots and per-symbol inputs (mirrors runtime evaluation order). Status text colour-codes by state: green (auto-pass), gold (overridden), red (fail-auto, with `(subject doesn't have it)` or `(needs Trigger Owner as inflicter)` qualifier). Override checkbox `"Pretend subject has <Condition>"` renders only when auto-derived state is fail (or already overridden) -- hidden once auto-pass to avoid noise.
    - **Result block**: `gate-fail` renders as a red `<b>Blocked</b>` headline naming the missing condition + subject; grey detail line distinguishes wrong-inflicter from missing-condition. Trailing hint points to the override checkbox above.
    - **Resolved-values grid**: extra "Required Condition" row appears whenever the gate exists (any kind != no-gate). Rendering: `"<Cond> present (auto)"` / `"<Cond> (overridden)"` / `"<Cond> present, wrong inflicter"` / `"<Cond> missing"`.
    - **Verified**: 9-case logic test pass (no-gate, missing-no-override, missing+override, present-any-inflicter, present-true-legacy, present+right-inflicter, present+wrong-inflicter, wrong-inflicter+override, gate-disabled). Direct API contract check: `creature:HasCondition(id)` returns the inflicter tokenid or false as expected after `InflictCondition(id, {casterInfo = ...})`. **No bestiary triggers use `characterConditionRequired` today** -- C5 unblocks authoring this pattern, which today silently fails tests because the gate ran but wasn't surfaced. User-side regression test must construct a synthetic ability with the gate set.
- **C6a** -- popout test panel as floating window that survives editor close. Snapshot the ability at popout, re-evaluate against current map state.
- **C6b** -- reopen callback contract: `options.reopen = function() ... end` passed at editor-open time. Wire highest-value entry points first (character sheet class features, compendium class features -- the deepest navigation paths the user explicitly flagged).
- **C6c** -- backfill remaining entry points + robustness fallbacks for stale references / deleted entries.

- **Path C (in-formula state overrides + scope note + no-subject early exit + hint text)** -- SHIPPED. Three pieces:
    - **Header note**: italic grey caption under the "Test Trigger" expanded-card header explains that the panel evaluates only the trigger's condition, not the resulting effects. Sets expectations once for the whole panel rather than per-row.
    - **No-subject early exit**: `runTriggerTest` short-circuits with `kind = "no-subject"` (mirroring `no-caster`) when the ability requires a non-self Subject and no token on the map matches the subject filter. Replaces the previous behaviour of running the test against a confusing fallback (often the caster itself). `buildResultBlock` renders the "Cannot test -- this trigger requires a Subject (filter: X)..." message with a "Add a token of that type to the map and re-run" follow-up.
    - **In-formula condition / ongoing-effect overrides**: when the conditionFormula references any of:
        - `Subject.Conditions has "X"` / `Self.OngoingEffects has "X"` etc. -- prefixed set-membership form
        - `Conditions has "X"` / `Ongoing Effects has "X"` etc. -- BARE-LHS set-membership form (head omitted; implicit Self per GoblinScript bare-ref convention)
        - `Subject.Flanked` / `Self.Bleeding` etc. -- prefixed bare-boolean dotted access where the property name matches a registered condition or ongoing-effect canonical
        - `Flanked` / `Bleeding` etc. -- bare ident with NO head prefix and NO `has` operator (also implicit Self)
        the test panel surfaces a "Pretend X has Y" checkbox per condition/effect in a new section below the Required Condition gate row. All shapes unify into the same {head, set, value} entries -- toggling the checkbox covers every form automatically. State lives in `state.formulaOverrides` keyed by `"<head>:<set>:<value>"`.

      At eval time, `buildEvalContext` wraps `symbols.subject` (and `symbols.self` when relevant) with `GenerateSymbols(props, overrideTable)` -- the engine's existing override hook from `Creature.lua:8262` -- AND copies the entire override table (augmented StringSets + per-value booleans) wholesale to the OUTER symbols table so bare references (with no Self prefix) resolve through the top-level lookup callable. Without the outer-level copy, bare refs fall through to the real creature's `lookupSymbols.conditions`/`.ongoingeffects` and the override is invisible.

      The override table contains the AUGMENTED StringSet (real conditions/effects + overridden values, precomputed via `buildAugmentedSet`) AND a per-value boolean (lowercase + space-stripped key, value=true). Real creature properties are NEVER mutated.
    - **Hint-text fallback**: when a test fails AND the formula references creature state we DON'T have override toggles for (`.Stamina < 5`, custom attributes, etc.), the result block appends a tip line directing the author to apply that state on the map. Detection uses `ListReferencedDottedAccesses`; suppressed when every dotted access is already override-eligible.
    - **Discovery**: `discoverInFormulaOverrides` runs two passes:
        - Pass 1 (`WalkLiteralComparisons`, the same C3.5 helper) extracts `<head>.Conditions has "X"` / `<head>.OngoingEffects has "X"` literal triples. **`info.lhs` from this callback is an AST atom (`{kind = "dotted", parts = {...}}`), NOT a string** -- treating it as a string was the original bug that prevented any overrides from ever appearing. The `parts` array gives `{head, setName}` for two-part dotted access. Tail names are normalised (lowercase + space-strip) before matching, since GoblinScript's tokenizer merges adjacent WORDs into a single IDENT separated by a space (`GoblinScriptProse.lua:244-264`) -- so `Subject.Ongoing Effects` parses as `parts = {"Subject", "Ongoing Effects"}` and the spaced tail must normalise to `"ongoingeffects"` to match. Plain `string.lower("Ongoing Effects")` returns `"ongoing effects"` and silently misses; use `lower(gsub(s, "%s+", ""))`.
        - Pass 2 (`ListReferencedDottedAccesses`, the C4 helper) walks every dotted access in the formula. For each `<head>.<X>` where head is `Subject`/`Self` and X (case-insensitive, with optional space-stripping) matches a condition or ongoing-effect canonical name from `dmhub.GetTable("charConditions")` / `dmhub.GetTable("characterOngoingEffects")`, the value is added under the matching set. Tail names `Conditions`/`OngoingEffects` themselves are skipped (those are the LHS of pass 1's set-membership form, not values to override).
        Both passes feed the same `addOverride(head, setName, value)` accumulator with case-insensitive de-dup, so a condition referenced via both shapes only gets one checkbox. Restricted to `Subject`/`Self` heads -- broader patterns are deferred to the hint text.
    - **Display**: the override section merges Conditions and OngoingEffects entries into a single list per head with a neutral heading ("Pretend Subject has:" / "Pretend Trigger Owner has:"). Earlier separate-group form ("Pretend Subject has condition: ..." / "Pretend Subject has ongoing effect: ...") leaked the internal Conditions vs OngoingEffects split as user-visible categorization, which authors found confusing because Draw Steel derives many conditions FROM ongoing effects (`Creature.lua:7892`) -- e.g. "Flanked" appears as an ongoing-effect entry in DS content but authors think of it as a state. Per-value checkbox is dedup'd by lowercased value: a state referenced via both `Subject.Flanked` AND `Subject.Conditions has "Flanked"` produces ONE checkbox that, when toggled, sets all related `state.formulaOverrides[head:set:value]` keys so the eval-time injection covers every form.
    - **Lexical-scope ordering caveat**: `buildAugmentedSet` and `collectOverrideValues` MUST be defined ABOVE `buildEvalContext`. Lua's `local function` in chunk scope captures references at compile time -- a forward reference to a not-yet-declared local becomes a global lookup that's nil at runtime. `discoverInFormulaOverrides` and `buildOverridesSection` are fine where they are because they're only invoked from within `buildTestTriggerCard`'s body, which runs long after all module-level locals are declared.
    - **Out of scope intentionally**: arbitrary creature property overrides (numeric thresholds, custom attributes); behaviour-side state simulation (the test panel evaluates only the condition formula, not the trigger's effects -- the header note documents this); chained dotted access like `Subject.Foo.Bar`. The scope note + hint text cover the gaps.

- **Test panel orphan-panel fix** -- SHIPPED. `buildCasterSlotRow` previously built its wrapper panel + token-picker button + label unconditionally, then the caller in `buildExpanded` discarded it via `if casterRow ~= nil and #(dmhub.allTokens or {}) > 1`. With a single token on the map, the row was built and discarded, leaking every panel inside. Fixed by moving the `<= 1` token-count gate inside `buildCasterSlotRow` so the panels aren't constructed at all in the single-token case. Caller's redundant check removed.

- **`width = 360` -> `width = "100%"` on the Setup section's Prompt Text input** -- SHIPPED. The 300-char prompt was scrolling within a fixed-width input; widened to fill the row so authors can proofread the full text without scrubbing.

**Code-fact discoveries worth remembering for future modifications:**

- `trigger.symbols` registrations come in BOTH keyed-map and bare-array forms; never assume one. Use the `evalKey` normalisation pattern (`NewTriggeredAbilityEditor.lua` discoverTestInputs comment) when iterating.
- `creature:GetActiveModifiers` runs `FilterModifiers` and gates by `filterCondition`. For "is this defined on the creature" questions (preferred-list match, etc.), walk via the `Fill*ActiveModifiers` trio directly to bypass the filter.
- `creature.helpSymbols` (`Creature.lua:6842`) is the canonical map of bare creature properties accessible without `Self.` prefix. ~294 entries. Useful for any "is this a valid symbol reference" check.
- `GoblinScriptProse.ListReferencedSymbols` now skips identifiers followed by `(` (function calls). If old behaviour is needed, add a separate function rather than reverting.

### Lua phase 1 status (SHIPPED 2026-04-24)

**File layout:**
- `DMHub Compendium\TriggeredAbilityEditor.lua` - UNCHANGED. Classic implementation stays intact.
- `Draw Steel Ability Editor\NewTriggeredAbilityEditor.lua` - new editor. Preserves classic via `local classicGenerateEditor = TriggeredAbility.GenerateEditor` at file-load time, then redefines `TriggeredAbility:GenerateEditor` with dispatch.
- `Draw Steel Ability Editor\AbilityEditorBehaviorPicker.lua` - 3-line polymorphism edit (L515-525, L597): reads `ability.Types` / `ability.TypesById` instead of `ActivatedAbility.Types` so TriggeredAbility instances reach the extra `momentary` entry via inheritance. Normal ActivatedAbility callers unchanged.
- `Draw Steel Ability Editor\AbilityEditor.lua` - added public `AbilityEditor.GetEditorStyles()` accessor exposing the full internal style pack. No other changes.

**Dispatch rules** (in `TriggeredAbility:GenerateEditor`):
1. `options.excludeTriggerCondition` or `options.excludeAppearance` -> classic. Keeps aura-embedded editor (`Aura.lua:234`) working unchanged.
2. `dmhub.GetSettingValue("classicTriggeredAbilityEditor") == true` -> classic. User opt-out.
3. Otherwise -> new sectioned editor.

**Setting:** `classicTriggeredAbilityEditor` (boolean, default false). Mirrors `classicAbilityEditor`.

**Styling:** `buildStyles()` calls `AbilityEditor.GetEditorStyles()` for the full shared pack (label alignment, nav-button / section-heading / field-row / checkbox / dropdown / input / button skins). Only local override: `selectors={"appearance"} halign="left" priority=3` to pin the Custom Icon check under Display's Icon label. Shared nae-* class names used throughout (nae-root, nae-nav-col, nae-nav-button, nae-section-content, nae-section-heading, nae-field-row, nae-field-label, nae-field-hint, nae-detail-col) so future AE style tweaks flow in automatically. Internal element IDs keep the `ts_` / `ts` prefix for DOM-lookup hygiene (ts_nav_*, ts_section_*, tsNavCol, tsDetailCol, triggeredAbilityEditorRoot).

**Momentary picker resolution (2026-04-24):** Option 1 chosen -- minimal polymorphism edit to the shared picker. `ability.Types` resolves to `TriggeredAbility.Types` (includes momentary at index 70) for TriggeredAbility instances via the RegisterGameType inheritance chain, and to `ActivatedAbility.Types` for regular abilities. Zero regression surface for existing ActivatedAbility flow.

**Verified in-engine:** All four nav tabs render and switch; conditional field visibility works (Trigger Range hidden when Subject=self; Prompt Text + Resource Cost hidden when Trigger Mode=Occurs Automatically; inflicted-by checkbox hidden when no Requires Condition); aura-embed path falls through to classic; opt-out setting falls through to classic; no new Lua errors on reload. Dispatch tested by toggling the setting and by passing `excludeTriggerCondition=true`.

**Known phase-1 limitation flagged for phase 2:** "Add Ability Filter" and "Add Reasoned Filter" buttons rendered center-aligned inside the Effects section. **RESOLVED 2026-04-24** by the Effects BehaviorEditor replacement (see below) -- Effects now uses `AbilityEditor.BuildEffectsSection` which hosts those buttons inside per-behaviour cards with correct left-alignment.

**Minor deferrals (phase-labels pass):**
- Despawn dropdown labels overridden locally via `DESPAWN_OPTIONS` ("Skip Despawned Targets" / "Retarget to Corpse"). Classic editor still shows its original labels ("Remove Despawned Targets" / "Target Corpse") - harmless since the classic editor is only reached through opt-out or aura-embed paths.

### Lua phases 2, 3, Effects replacement + bottom bar status (SHIPPED 2026-04-24)

**Phase 2 (Trigger Event picker modal):**
- `TRIGGER_METADATA` + `TRIGGER_GROUPS` tables in `NewTriggeredAbilityEditor.lua` with all approved renames applied as per-id `label` overrides (fallenon -> "Creature Lands On You", targetwithability -> "Targeted by an Ability", leaveadjacent -> "Adjacent Creature Moves Away", fall casing fix, beginround -> "Start of Round", teleport normalized).
- `miss` + `attacked` explicitly excluded via `EXCLUDED_TRIGGER_IDS`; `fumble` filtered via its existing `hide()` predicate.
- Field row is label + gold-accent-bar + bold cream text ("currently selected") + inline `[Change]` button that opens the picker modal. No dropdown mimicry.
- Modal pattern lifted from `AbilityEditorBehaviorPicker.lua`: search input, categorized band list, Common band priority-sorted, other bands alphabetical.
- Selection writes `ability.trigger` and triggers `refreshSection()` to rebuild the Trigger section with the updated label.

**Phase 3 (Trigger Mode progressive disclosure):**
- Segmented toggle for the two common `mandatory` values (`false` = "Prompt the Player", `true` = "Occurs Automatically"). Highlighted segment fills gold, unselected outlined.
- "Advanced modes" foldout below the segmented uses the shared `nae-more-options-row` / `nae-more-options-label` / `nae-more-options-chevron` classes from the New Ability Editor (left-aligned variant -- note AE's centered variant is considered an oversight to fix in a later pass).
- Foldout content uses `collapsed-anim` (not `hidden`) so height truly collapses and no dead space is reserved.
- Advanced radios: `"local"`, `"prompt_remote"`, `"game:heroicresourcetriggers"`. Filled gold circle = selected, ring = unselected.
- Foldout auto-opens when the current value is one of the advanced ids.
- Selection writes `ability.mandatory` directly; existing `IsMandatory` / `MayBePrompted` helpers keep working unchanged so the conditional Prompt Text / Resource Cost fields continue to hide/show correctly.

**Effects BehaviorEditor replacement:**
- `AbilityEditor.BuildEffectsSection = _buildEffectsSection` exposed as a public wrapper in `AbilityEditor.lua` (one line alias).
- `buildEffectsSection` in the new editor now renders per-behaviour cards via that wrapper. `ability.Types` / `ability.TypesById` resolve to `TriggeredAbility.Types` via inheritance (the phase-1 polymorphism edit) so the `momentary` behaviour entry reaches both the picker and the createBehavior lookup without special-casing.
- Killed the known phase-1 alignment leak (Add Ability Filter / Add Reasoned Filter are now correctly left-aligned inside their parent behaviour card).

**Effects bottom bar (Add / Paste anchored):**
- `detailCol` is now a non-scrolling vertical wrapper holding `detailScroll` (vscroll, padded, contains section contents) + `effectsBottomBar` (anchored via the shared `nae-effects-bottom-bar` style).
- `selectSection` toggles the bar's `collapsed` class per tab and shrinks `detailScroll.height` to `100%-42` when Effects is active. Other tabs collapse the bar and reclaim the 42px.
- Bar hosts a centered button cluster: `+ Add Behavior` (opens `AbilityEditor.OpenBehaviorPicker` and calls `_trackRecentBehavior` on selection) + `Paste Behavior` (collapse-anim'd unless `dmhub.GetInternalClipboard()` holds an `ActivatedAbility*Behavior`).
- Paste visibility kept in sync via two handlers: `refreshAbility` (fired by our internal dispatch when we paste/add) and `internalClipboardChanged` (fired by the engine when the user copies a behaviour from elsewhere while the editor is open).
- `fireChange` at `generateSectionedEditor` scope dispatches `refreshAbility` across the root subtree; threaded through `makeSectionContent(sectionDef, ability, fireChange)` and then `buildEffectsSection(ability, refreshSection, fireChange)`.
- Full-screen context is guaranteed: the only callers of `TriggeredAbility:GenerateEditor` that reach the sectioned editor are `ShowEditActivatedAbilityDialog` (full-screen modal) paths. The aura-embed path (`Aura.lua:234` with `excludeTriggerCondition=true`) and `classicTriggeredAbilityEditor` opt-out both fall through to classic -- so no embedded-panel context ever sees the anchored bottom bar.

**Verified in-engine (combined):** Trigger Event picker opens from `[Change]`, all renames render, Common band priority-sorted, selection writes + label refreshes; Trigger Mode segmented + advanced foldout expands/collapses cleanly with chevron flip animation, radios + segments mutually exclusive, Prompt Text visibility tracks `MayBePrompted()`; Effects tab shows per-behaviour cards with correct alignment, bottom bar anchors Add + Paste, Paste auto-hides/shows on clipboard change, non-Effects tabs hide the bar and reclaim scroll height, adding a behaviour keeps the bar anchored while content scrolls; aura-embed dispatch still routes to classic (no bottom bar); no Lua errors on reload.

### Phase 8 status: Condition Prose Engine (SHIPPED 2026-04-24)

**File:** `DMHub Utils\GoblinScriptProse.lua` (~1000 lines), registered at `main.lua:13` after `GoblinScript.lua`.

**Architecture:** tokeniser (multi-word identifier merging, context-aware `has`/`is` keyword demotion, space- and case-insensitive normalisation) -> recursive-descent shaper producing a mini-AST -> eight pattern renderers (bare boolean, negated boolean, numeric comparison, string equality, set membership, AND chain, OR chain, function call) -> vocabulary layer. All wrapped in pcall so any tokeniser/parser/render failure returns the raw formula string. Raw-formula fallback matches the classic editor's quality floor.

**Vocabulary (locked 2026-04-24):**
- 75 symbols from [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md), centralised in a `do` block at the bottom of the file.
- 15 functions (Distance / Line of Sight / Cast.passespotency / etc.).
- 12 roles for dotted-access composition (Attacker -> "the attacker" -> Attacker.Level -> "the attacker's level").
- 42 trigger event templates from [TRIGGER_EVENT_PROSE.md](TRIGGER_EVENT_PROSE.md) (41 DS-native + `attacked` from `dnd5e.lua`). Placeholders: `{subject}` / `{subject-possessive}` / `{s}` / `{es}` / `{is}`.

**Dynamic-prose shapes:** `Subject` symbol splits into `role` + `possessive` fields keyed on `ability.subject` (8 entries). `Speed` keyed on trigger id (4 entries). `Quantity` keyed on trigger id (3 entries). Self uses second-person voice (`you` / `your`); compound subjects expand (`you or any ally`) rather than collapsing.

**Public API:**
- `GoblinScriptProse.Render(formula, ctx)` -- renders a single condition formula to prose. `ctx = { subject, trigger }` drives dynamic-prose lookups.
- `GoblinScriptProse.RenderTriggerSentence(ability)` -- composes `[event template][, if [condition prose]].` with correct verb agreement and capitalisation. Consumed by the card's Trigger row AND the Mechanical View's when-clause.
- `GoblinScriptProse.RegisterSymbolProse(name, prose)` / `RegisterFunctionProse` / `RegisterRoleProse` -- runtime extension hooks. The eventual migration target (per `memory/project_prose_engine_migration.md`) is for each symbol's `RegisterSymbol` call site to carry its own `prose` field rather than using the central registration block, but that's deferred.

**Coverage:** 90% on a 29-formula real-bestiary smoke test. The 3 raw fallbacks are all worksheet-deferred creature-property symbols (`Conditions`, `Effects Count`, `SaveEndsEffects`). Edge cases (empty, nil, gibberish, unsupported `when`/`where` keywords) return safely via pcall.

**Deferred follow-ups** (both have memory notes):
- **Vocabulary migration to per-symbol `prose` fields** (`project_prose_engine_migration.md`). Revisit after phase 5 shipping validates the prose shapes.
- **Condition absorption** (`project_condition_absorption.md`). Fold simple condition patterns (`Damage >= 5 and Damage Type is "fire"`) into the event template itself for cleaner prose ("When you take 5 or more fire damage" vs the verbose "When you take damage, if..."). ~3-4 days; revisit after phase 4 exercised the composer in a second surface.

### Phase 5 status: Trigger Preview card (SHIPPED 2026-04-24)

**File:** `Draw Steel Ability Editor\NewTriggeredAbilityEditor.lua`. Added `buildTriggerPreviewCard(ability)` + `makePreviewColumn(ability, schedulePreviewRefresh)` + `renderTriggerProse(ability)` + `behaviorsFallbackText(ability)` + debounced `schedulePreviewRefresh` helper.

**Layout:** editor is now three-column -- nav + detail + preview column (fixed 440px, matches `AbilityEditor.LAYOUT.PREVIEW_WIDTH`). `detailCol.width` shrunk to `100%-NAV_WIDTH-PREVIEW_WIDTH-24`.

**Card mirror:** matches `TriggeredAbilityDisplay:Render` visual (title bar with name + cost, keywords/type row, distance/target row, divider, Trigger row, Effect row). Auto-derivation per field:
- `name` -> `ability.name`
- `cost` -> `resourceNumber` in parens, blank otherwise
- `type` -> "Triggered Action" default (phase 7 overrides)
- `keywords` / `distance` / `target` / `flavor` -> blank, grey italic "-" (phase 7 overrides)
- `trigger` (prose) -> `GoblinScriptProse.RenderTriggerSentence(ability)` -- full sentence composition, including event phrase + subject prose + optional condition prose
- `effect` -> `GoblinScriptProse.RenderBehaviourList(ability)` -- per-type prose templates from [BEHAVIOUR_PROSE.md](BEHAVIOUR_PROSE.md) chained with ", " / ", then ". Fallback to comma-joined `SummarizeBehavior()` if engine unavailable.

**Refresh plumbing:** **[PERFORMANCE_PREVIEW_REBUILD]** 0.25s `thinkTime` poll on `previewSlot`, **fingerprint-gated via `dmhub.ToJson(ability)`** -- only schedules a refresh when the serialised ability state actually changes. The 0.15s `schedulePreviewRefresh` debounce coalesces rapid changes into a single rebuild. `fireChange()` dispatches `refreshAbility` tree-wide + schedules a preview refresh, so structural changes propagate immediately.

**Why fingerprint-gated, not unconditional**: the preview rebuild reconstructs the entire Trigger Preview card + Mechanical View card on every fire -- which means re-running `dmhub.CompileGoblinScriptDeterministic` on the condition formula, walking the formula AST twice (`ListReferencedSymbols` and `WalkLiteralComparisons`), composing prose via `RenderTriggerSentence` and `RenderBehaviourList`, calling `SummarizeBehavior` on every behaviour, and allocating dozens of `gui.Panel{}` / `gui.Label{}` tables. The original implementation called `schedulePreviewRefresh` unconditionally on every tick, so this entire pipeline ran ~3 times per second per open editor regardless of whether anything had changed. With multiple editors open the GC pressure stacked across long sessions and made the UI noticeably laggy / sometimes required restart. Fingerprint-gating drops the rebuild rate to "only when something changed" while keeping the safety net for fields that bypass `fireChange` (per-field edits inside behaviour cards, plus several top-level handlers in `buildTriggerSection` that don't currently call `fireChange` -- `name`, `whenActive`, `subjectRange`, `conditionFormula`, `characterConditionRequired`, etc.).

**Compile cache**: `compileCondition(formula)` caches results by formula string in module-local `_conditionCompileCache`. `dmhub.CompileGoblinScriptDeterministic` allocates a fresh Lua function on every call (per `dmhub.lua:664` callers are *expected* to cache the return value). Without the cache, every Mechanical View rebuild re-compiled the same formula. With Approach C the rebuild rate drops sharply, but the cache still helps when formulas are edited heavily or when multiple `compileCondition` calls land in the same rebuild.

**Rules for adding new preview-relevant fields**:
- Top-level field whose change handler you control: call `fireChange()` after the mutation. This propagates immediately, no 250ms wait. Mirrors the Display section pattern.
- Field on a behaviour's `EditorItems`: do NOT add `fireChange` calls into shared behaviour code (huge blast radius across non-DS editors). The fingerprint poll catches it.
- Whatever you do, **DO NOT** revert the `previewSlot.think` handler to call `schedulePreviewRefresh` unconditionally. That re-introduces the rebuild storm. The block comment at the top of `makePreviewColumn` in `NewTriggeredAbilityEditor.lua` documents this in code; cite this section if a new contributor proposes the change.

### Phase 4 status: Mechanical View pane + opt-in #3 narrow compatibility (SHIPPED 2026-04-24)

**File:** `Draw Steel Ability Editor\NewTriggeredAbilityEditor.lua`. Added `buildMechanicalView(ability)` returning `(card, rollupInfo)`, validation helpers (`isValidTriggerId`, `compileCondition`, `summariseBehaviours`, `renderThenClause`), and constant tables (`VALID_SUBJECT_IDS`, `MODE_LABELS`, `WHEN_ACTIVE_LABELS`, `CASTER_INCLUSIVE_SUBJECTS`, `GLOBAL_SUBJECTLESS_TRIGGERS`).

**What renders** (pane below Trigger Preview, sub-heading "How This Triggers" with the rollup chip inline on the right):
- Rollup chip -- green "Trigger ready" / amber "N issues", aggregated across rows
- Six rows with label + raw value + optional issue chip (shown only for non-Valid states): Event / Subject / Triggers When / Behaviours / Mode / When Active
- Two-clause Trigger Summary -- "**Triggers when:** <RenderTriggerSentence output>" + "**Then:** <behaviour summary>". Markdown-enabled labels use Unity rich-text `<b>` tags for the bold leads.

**Static validation only** (runtime-hook integration per gotcha 10 deferred):
- Event: `TriggeredAbility.GetTriggerById` lookup. Chip: Missing / Unregistered.
- Subject: membership in `VALID_SUBJECT_IDS`. Chip: Unknown.
- Compatibility (opt-in #3 narrow): `GLOBAL_SUBJECTLESS_TRIGGERS` (`beginround`, `endcombat`, `rollinitiative`) paired with a non-caster-inclusive subject -> chip "Never fires". Verified against the runtime resolver at `TriggeredAbility.lua:746` which explicitly rejects these combinations. Broader semantic compat warnings (e.g. "`dealdamage` + subject=enemy is unusual") intentionally not shipped -- those are hints not runtime-backed errors.
- Triggers When: `dmhub.CompileGoblinScriptDeterministic` compile. Chip: Error: <reason>.
- Behaviours: empty list + not `silent`. Chip: Empty.
- Mode / When Active: membership in label tables. Chip: Unknown.

**Visual polish** (locked 2026-04-24 after user review):
- Column heading `Preview` removed. Each pane now has its own sub-heading (`Trigger Preview`, `How This Triggers`). Test Trigger (phase 6) follows the same pattern.
- Both cards use `COLORS.CARD_BG = "#040807"` (DS "rich black" from `MCDMCharacterPanel.lua:34`) with a 2px `GOLD_DIM` border. Cards read as inset against the near-black column; the gold border carries visual separation. `bgimage = "panels/square.png"` is required or `bgcolor` + `borderColor` don't paint (DMHub GUI gotcha).
- Fonts: 13pt body rows, 14pt sub-heading, 12pt rollup chip, 11pt issue chips, 13pt summary clauses.
- Rollup chip lives inline with the `How This Triggers` sub-heading (not in its own row inside the card). The card body starts with the row grid -- cleaner visual weight.

**Deferred follow-ups for Phase 4 v2:**
- Runtime log-hook integration (gotcha 10) -- parse actual `TriggeredAbility.lua:734-757` / `:859-874` / `:898-910` / `:947-959` log entries to surface per-firing diagnostics rather than just static structural checks.
- Action links on diagnostic chips ("Pick a replacement", "Open event picker") -- open question #1.
- Broader opt-in #3 compatibility matrix beyond the three global subjectless triggers.

### Collaboration norms (from prior sessions)
- Propose before executing on design / terminology / scope decisions. The user values deliberation over unilateral action.
- Bug fixes and straightforward implementation of agreed designs are fine to execute.
- Verify codebase facts with grep/read before stating them - false positives waste review cycles.
- Structural / sizing / wrong-data-label issues are worth fixing in the phase that surfaces them. Spacing / micro-alignment / anything phase 2+ will reshape anyway batches into a post-functional polish pass.
- Inherit New Ability Editor styles wherever possible rather than maintaining parallel rules. The two editors should feel identical.

### Collaboration norms (from the last session)
- Propose before executing on design / terminology / scope decisions. The user values deliberation over unilateral action.
- Bug fixes and straightforward implementation of agreed designs are fine to execute.
- When a codebase fact is ambiguous, verify with a grep or read before stating it - we had false positives last session that wasted a review cycle.
- **Do not create new Lua files without asking.** Per CLAUDE.md, DMHub's module system does not auto-load files by disk presence -- a new file requires user registration. For phase 8 (prose engine), ask the user to create `DMHub Utils\GoblinScriptProse.lua` and register it before writing implementation.
- When presenting visual-style choices (colors / borders / weights), offer 3-4 concrete alternatives from lightest to heaviest touch, with a recommendation. User typically iterates through 2-3 variants (e.g. A -> B -> C with bold) before locking in.
- "Advanced modes" foldout pattern should use `nae-more-options-row` / `nae-more-options-label` / `nae-more-options-chevron` (shared from the New Ability Editor) + `collapsed-anim` for content. Left-align by default for new uses; the AE's own centered variant is considered an oversight to fix in a later pass (not this session's scope).

---

## Working artifacts

| File | Purpose | Status |
|---|---|---|
| `triggered-ability-editor-interactive.html` | Interactive mockup shown to devs. Single View 3 design at both target resolutions (1366x768, 1920x1080), clickable nav, working Trigger Event picker modal, Run Test button, Developer Notes tab. | Current working design. |
| `triggered-ability-editor-mockup.html` | Older multi-view mockup (5 views incl. robustness gallery + mechanical-view variants). | Historical reference. Keep. |
| `TRIGGER_PICKER_CATEGORIES.md` | Working doc for trigger categorization + rename decisions. | Merged into this doc. Delete. |
| `RESPONSE_SECTION_LABELS.md` | Working doc for field labels + microcopy. | Merged into this doc. Delete. |

---

## Technical references (codebase)

Where Claude should look for authoritative answers, with specific line numbers where useful.

### Classic editor (what this replaces)
- `DMHub Compendium\TriggeredAbilityEditor.lua` - the whole file is ~450 lines; single flat `Refresh()` method.
  - Line 22-33: Name input
  - Line 40-70: Subject dropdown (8 values at lines 54-62)
  - Line 72-96: When Active dropdown (2 values at 85-88)
  - Line 102-138: Requires Condition + "inflicted by you" checkbox
  - Line 141-162: Trigger Mode (5 values, `mandatoryTriggerSettings` reference)
  - Line 164-171: Create manual version checkbox
  - Line 175-191: Prompt Text (conditional on `MayBePrompted()`)
  - Line 193-218: Resource Cost (numeric input, not a dropdown)
  - Line 220-250: Subject Range (GoblinScript, conditional on Subject != self)
  - Line 239: inline `symbols = {subject = {...}}` - the GoblinScript Subject symbol registration (see gotcha 1)
  - Line 252-279: Trigger Event dropdown (populated by `TriggeredAbility.GetTriggerDropdownOptions()`)
  - Line 282-306: Action Type dropdown (dynamic from `CharacterResource.GetActionOptions()`)
  - Line 358-380: Triggers Only When (GoblinScript input for `conditionFormula`)
  - Line 382: Behaviour editor (lifted from ActivatedAbility)
  - Line 389-414: Right panel - icon + description (classic editor keeps these separate; new design folds them into Trigger section)

### Data model
- `DMHub Game Rules\TriggeredAbility.lua` - the object.
  - Line 15: `despawnBehavior = "remove"` default
  - Line 37-58: `TriggeredAbility.mandatoryTriggerSettings` (5 real values)
  - Line 62-88: `IsMandatory` / `IsLocalOnly` / `MayBePrompted` helpers
  - Line 114-165: `TriggeredAbility.TargetTypes` (behaviour-level targets - DO NOT confuse with Subject, see gotcha 1)
  - Line 152-155: Subject field id declaration
  - Line 167-436: `TriggeredAbility.triggers = {}` inline trigger definitions (21 triggers)
  - Line 500+: `RegisterTrigger` API and base registrations (`custom`, `dealdamage`, `winded`, `dying`, `startrespite`, `startdowntime`, `endrespite`)
  - Line 634-636: `GetTriggerDropdownOptions` / `GetTriggerById`
  - Line 666: `name` default
  - Line 668: `conditionFormula` default
  - Line 727-790: Subject resolver (runtime check at 734-757 logs "Wrong subject"; range check at 790)
  - Line 859-874: Condition evaluation (logs reason on failure)
  - Line 889: `targetType == 'subject'` handling
  - Line 898-910: Aura resolution
  - Line 947-959: Missing attacker/target runtime check
  - Line 1211-1226: Despawn behaviour implementation (`remove` vs `corpse` fallback)

### Draw Steel trigger registrations
- `Draw Steel Core Rules\MCDMRules.lua` lines 1015-1487: 16 DS-specific `RegisterTrigger` calls (`inflictcondition`, `movethrough`, `teleport`, `leaveadjacent`, `gaintempstamina`, `castsignature`, `useresource`, `gainresource`, `earnvictory`, `useability`, `prestartturn`, `targetwithability`, `rollpower`, others).
- `Draw Steel Core Rules\PowerTableTriggers.lua`: separate power-roll trigger system with its own `g_triggerChoices` list (lines 43-79). Not part of the main `TriggeredAbility.triggers` - do NOT include in picker metadata.

### Aura-embedded triggered abilities (SCOPE NOTE - see Review Items below)
- `DMHub Game Rules\Aura.lua:24,28`: aura-specific trigger ids (`onenter`, `casterendturnaura`).
- These are **NOT** registered via the main `RegisterTrigger` mechanism and must **NOT** appear in the standalone Triggered Ability Editor's picker modal.
- They appear inside the **Create Aura behaviour**'s embedded TriggeredAbility editor - an aura has its own `triggers: [ {ability: TriggeredAbility{...}} ]` array where each trigger's event is an aura-specific id. Example in compendium: `compendium\bestiary\abyssal-rift.yaml:197-246` (Demon Portal aura with a `trigger: onenter` ability nested inside).
- The aura-embedded trigger editor is a separate instance of the TriggeredAbility editor with an aura-context event list. Must remain functional after the standalone editor rewrite.

### Picker pattern source (for Trigger Event picker implementation)
- `Draw Steel Ability Editor\AbilityEditorBehaviorPicker.lua` - lift pattern: `BEHAVIOR_METADATA` table (line 19) with `description`, `tags`, `group`, `sortOrder`; search input + category bands; modal UX.
- `Draw Steel Ability Editor\AbilityEditorModifierPicker.lua` - same pattern for modifiers.

### Card rendering (what the Trigger Preview pane mirrors)
- `Draw Steel Core Rules\DSModifyTriggerDisplay.lua` - defines `TriggeredAbilityDisplay` game type and render logic (around line 321). Fields: `name, cost, keywords, flavor, type, distance, target, trigger, effect, implementationNotes`.
- `DMHub Core UI\Gui.lua` - `Styles.Triggers` for title-bar colors (trigger/free/passive).
- `Timeline\AbilitySidebar.lua` + `DMHub Core Panels\CharacterPanel.lua` - existing surfaces that render trigger cards.

### GoblinScript (for Triggers Only When condition evaluation)
- `GoblinScript_Guide.md` - language reference (the old one in `memory/goblinscript.md` is also relevant).
- `DMHub Utils\GoblinScript.lua` - compiler (note: emits Lua closure, no AST exposed - see gotcha 4).
- `dmhub.CompileGoblinScriptDeterministic(formula, out)` - compiles, returns closure + `out.lua` for the compiled Lua source.

---

## Design decisions (final)

### Sections
Four sections in the left nav, in order:
- **Trigger** (real fields, reorganized from classic)
- **Setup** (real fields, new Trigger Mode progressive disclosure + the full Target Type / Range / numTargets / AOE / proximity stack lifted from the New Ability Editor; renamed from "Response" 2026-04-24)
- **Effects** (real, lifted from Activated Ability editor)
- **Display** (real card-override fields)

### Trigger section

| Field | Real/Proposed | Data field | Notes |
|---|---|---|---|
| Name | Real | `name` | Text input |
| Trigger Event | Real value, PROPOSED picker UX | `trigger` (id) | Opens picker modal - see below. Classic editor uses a dropdown. |
| Trigger Subject | Real | `subject` | 8 values - see Trigger Subject table. UI label "Trigger Subject"; data field name, runtime token naming, and GoblinScript `Subject` symbol all unchanged. |
| When Active | Real | `whenActive` | Segmented toggle - 2 values |
| Requires Condition | Real | `characterConditionRequired` | Dropdown of conditions. If set, unlocks the inflicted-by checkbox. |
| Condition must be inflicted by this creature | Real | `characterConditionInflictedBySelf` | Checkbox. Hidden when Requires Condition is not set. |
| Trigger Range | Real | `subjectRange` | GoblinScript. Hidden when Trigger Subject is Self. |
| Triggers Only When | Real | `conditionFormula` | GoblinScript. (Classic editor calls this "Condition"; new UI uses "Triggers Only When" throughout - see gotcha 2.) |
| Modes | Real | `multipleModes`, `modeList` | Dropdown (No Modes / Multiple Modes / Ability Variations) + conditional mode list with per-mode name, rules text, condition formula, and Variations' "Has Ability" sub-editor. Injected via `AbilityEditor.BuildModesSection` (shared with the New Ability Editor). |
| Icon | Real | icon | Uses existing `IconEditorPanel`. Folded in from classic's right panel. |
| Description | Real | `description` | Multiline. Folded in from classic's right panel. |

### Setup section (renamed from Response 2026-04-24)

| Field | Real/Proposed | Data field | Notes |
|---|---|---|---|
| Trigger Mode | Real value, PROPOSED progressive-disclosure UX | `mandatory` | 5 real values - see Trigger Mode table. Progressive disclosure: segmented for 2 common modes, expander for 3 advanced. |
| Prompt Text | Real | `triggerPrompt` | Hidden when mode doesn't allow prompting. 300-char limit. |
| Resource Cost | Real | `resourceCost` / `resourceNumber` | Numeric input (NOT a dropdown - gotcha 3). Heroic Resources. |
| Action Used | Real | `actionResourceId` | Dropdown dynamic from `CharacterResource.GetActionOptions()`. |
| Also show as a manual trigger | Real | `hasManualVersion` | Checkbox. |
| Target Type | Real | `targetType` | Dropdown. **Event-aware** options via `ability:GetDisplayedTargetTypeOptions()` -- filters `TriggeredAbility.TargetTypes` by each entry's `condition(ability)` predicate (e.g. `attacker` only valid for `attacked`/`hit`/`losehitpoints`/`inflictcondition`/`winded`/`dying`; `pathmoved`/`pathmovednodest` only for `finishmove`; `aura` only for `casterendturnaura`; `subject` only when subject != self -- last shows as **"The Trigger Subject"** per gotcha 6). Lifted from the New Ability Editor via the new `AbilityEditor.BuildTargetingSection` public helper, so all conditional companion fields below come along automatically. |
| Range / Length | Real | `range` | GoblinScript. Hidden when Target Type = self/map. Label changes to "Length:" for line targets. |
| Radius / Size / Width | Real | `radius` | GoblinScript. Visible only for sphere/cylinder/cube/line. Label per shape. |
| Distance | Real | `lineDistance` | GoblinScript. Line-only. |
| Can Choose Lower Range | Real | `canChooseLowerRange` | Check. Line-only. |
| Target Count | Real | `numTargets` | GoblinScript. Visible for target/emptyspace/anyspace. |
| Allow Duplicate Targeting | Real | `repeatTargets` | Check. Visible when target multi. |
| Proximity Targeting | Real | `proximityTargeting` | Check. Visible when target multi. |
| Chain Proximity + Proximity range | Real | `proximityChain`, `proximityRange` | Sub-group. Visible when proximity on. |
| Affects | Real | `objectTarget` + `targetAllegiance` | Dropdown (Creatures / Creatures and Objects / Allied / Enemy). Visible for AOE types. |
| Can Target Self | Real | `selfTarget` | Check. Hidden when Target Type = self. |
| Cast immediately when clicked | Real | `castImmediately` | Check. Self-only. |
| Targeting mode | Real | `targeting` | Dropdown (Direct / Pathfinding / Direct Path / etc.). Visible for emptyspace/anyspace. |
| Forced Movement + Through Creatures | Real | `forcedMovement`, `forcedMovementThroughCreatures` | Sub-group. Visible when targeting=straightline. |
| Object ID | Real | `areaTemplateObjectId` | Text. Visible only for areatemplate. |
| Target Filter | Real | `targetFilter` | GoblinScript. Always visible. |
| Range Text / Target Text | Real | `rangeTextOverride`, `targetTextOverride` | Text overrides with derived placeholders. |
| More options -> Ability Filters / Reasoned Filters | Real | `abilityFilters`, `reasonedFilters` | Filter list editor. |
| When Target Despawns | Real | `despawnBehavior` | Dropdown - 2 values. See table. Last field in the section. |

### Effects section
Behaviour cards lifted from Activated Ability editor. Interactive mockup demonstrates three example behaviours: **Damage**, **Invoke Ability**, **Purge Ongoing Effect**. The `+ Add behaviour` button opens the behaviour picker modal (`AbilityEditorBehaviorPicker.lua` pattern).

### Display section (SHIPPED 2026-04-24)
Per-field overrides for the Trigger Preview card's auto-derived text. Each input has a placeholder hint. Where an override is blank, the card shows the derivation; where the derivation itself is blank, the card shows a grey italic "-" placeholder.

| Field | Data field | Overrides | Derivation when blank |
|---|---|---|---|
| Display Name | `displayName` | Card title | `ability.name`. |
| Card Type | `displayCardType` | Title-bar colour + Type row label | Default `"trigger"` (Triggered Action). Dropdown: Triggered Action / Free Triggered Action / Passive. |
| Cost | `displayCost` | Parens suffix on the title (free text, e.g. *"1 Heroic Resource"*) | Numeric `resourceNumber` as a last-resort fallback. |
| Keywords | `displayKeywords` (set table) | Keywords row | No derivation -- picker writes directly. Uses the classic keyword-picker pattern (dropdown + chip rows) but with smaller font + flush-inline bin icon. |
| Distance | `displayDistance` | Distance row | `"Self"` when subject == self; `"Ranged <subjectRange>"` when subject != self and subjectRange is non-blank; blank otherwise. |
| Target | `displayTarget` | Target row | `ability:DescribeTarget()` -- respects Setup-section `targetType` + `numTargets` + AOE + `targetAllegiance` + `selfTarget` and also honours the Setup-section `targetTextOverride` field before falling to the derived phrase. |
| Flavor | `displayFlavor` | Italic flavour line above the card body | No derivation. Blank collapses the row. |
| Trigger | `displayTriggerProse` | Trigger row | `GoblinScriptProse.RenderTriggerSentence(ability)` -- full event + subject + condition composition. Updates card only; Mechanical View always shows the raw formula. |
| Effect | `displayEffectProse` | Effect row | `GoblinScriptProse.RenderBehaviourList(ability)` -- per-behaviour prose chained with ", " / ", then ". |

---

## Dropdown values

### Trigger Subject (`subject`)
UI label: "Trigger Subject". Helper text: *"Who the editor is listening for the trigger event to occur on."* Data field name stays `subject`; GoblinScript `Subject` symbol unchanged.

| id | Display |
|---|---|
| `self` | Self |
| `any` | Self or Any Creature |
| `selfandheroes` | Self or a Hero |
| `otherheroes` | Any Hero (Not Self) |
| `selfandallies` | Self or an Ally |
| `allies` | Any Ally (Not Self) |
| `enemy` | Any Enemy |
| `other` | Any Creature (Not Self) |

### When Active (`whenActive`)
Rendered as a segmented toggle.

| id | Display |
|---|---|
| `always` | Always Active |
| `combat` | Only During Combat |

### Trigger Mode (`mandatory`)
Rendered as progressive disclosure: segmented toggle for the two common modes + "Advanced modes" expander with radios for the three others.

| id | Display (new) | Common vs Advanced |
|---|---|---|
| `false` | Prompt the Player | Common (segmented) |
| `true` | Occurs Automatically | Common (segmented) |
| `"local"` | Occurs Automatically (Local Only) | Advanced (radio) |
| `"prompt_remote"` | Prompt Remote Player, Auto for Local | Advanced (radio) |
| `"game:heroicresourcetriggers"` | Automatic Heroic Resource Setting | Advanced (radio) |

Prompt Text field visibility is driven by whether the chosen mode allows prompting:
- Prompt the Player, Prompt Remote Player Auto for Local -> show Prompt Text
- Occurs Automatically, Occurs Automatically (Local Only), Heroic Resource Setting -> hide Prompt Text

### When Target Despawns (`despawnBehavior`)
| id | Display |
|---|---|
| `remove` | Skip Despawned Targets |
| `corpse` | Retarget to Corpse |

Helper text under this field: *"If a target of this trigger leaves the map before it resolves, skip them or retarget to their corpse. 'Retarget to Corpse' falls back to skipping if no corpse exists."*

### Conditions list (for Requires Condition dropdown)
Real options come from `CharacterCondition.FillDropdownOptions()`. In the mockup, representative sample: Bleeding, Dazed, Frightened, Grabbed, Prone, Restrained, Slowed, Taunted, Weakened.

### Damage Type (inside Damage behaviour)
Values not enumerated in `TriggeredAbility.lua` - they come from the Draw Steel damage-type registry. Representative list: physical, piercing, slashing, bludgeoning, fire, cold, lightning, acid, psychic, holy, corruption, sonic, poison.

---

## Trigger Event picker modal

Pattern lifted from `AbilityEditorBehaviorPicker.lua`. Mockup implements clickable version with search input and categorized bands.

### Band order and contents

**Common** (priority-sorted, order matters):
1. Take Damage - Fires when the creature loses stamina from damage. Most common "when hit, retaliate" trigger.
2. Damage an Enemy - Fires when the creature deals damage. Use for on-hit riders.
3. Roll Power - Fires on any power roll, with the 2d10 results available as symbols. Use for crit-on-natural-11+ effects or tier-specific riders.
4. Condition Applied - Fires when a condition is inflicted on the subject. Use for conditional reactions.
5. Use an Ability - Fires when the creature uses any ability. Use for ability-economy effects.
6. Start of Turn - Fires at the start of the creature's turn. Heavily used by ongoing effects and Begin-Turn auras in the bestiary.

**Combat** (alphabetical): Attack an Enemy, Attacked, Become Dying (Heroes Only), Become Winded, Creature Lands On You, Death, Drop to Zero Stamina, Gain Temporary Stamina, Kill a Creature, Made Reactive Roll Against damage, Regain Stamina.

**Abilities & Power Rolls** (alphabetical): Finish Using an Ability, Targeted by an Ability, Use Signature Attack or Area.

**Movement** (alphabetical): Adjacent Creature Moves Away, Begin Movement, Break Through a Wall, Collide with a Creature or Object, Complete Movement, Force Moved, Land From a Fall, Move Through Creature, Stepped on a Pressure Plate, Teleport.

**Resources & Victory**: Earn Victory, Gain Resource, Use Resource.

**Turn & Game Mode**: Before Start of Turn, Draw Steel, End of Combat, End Respite, End Turn, Start Downtime, Start of Round, Start Respite.

**Custom**: Custom Trigger.

### Approved renames (Display Name only - IDs untouched)
- `targetwithability`: "Target With Ability" -> **Targeted by an Ability**
- `moveawayfrom` (or equivalent): "Creature Moved Away From" -> **Adjacent Creature Moves Away**
- `fallenon`: "A Creature Lands on You From a Fall" -> **Creature Lands On You** (placed under Combat, not Movement)
- `fall`: "Land from a fall" -> **Land From a Fall** (casing fix)
- `beginround`: "Begin Round" -> **Start of Round**

### Kept original names (proposed renames rejected)
- `movethrough`: Move Through Creature (not "You Move Through a Creature")
- `castsignature`: Use Signature Attack or Area (not "Use Signature Ability")
- `endturn`: End Turn (not "End of Turn")
- `rollinitiative`: Draw Steel (DS flavour preserved)
- `saveagainstdamage`: Made Reactive Roll Against damage
- `creaturedeath`: Death (not "Die")

### Hidden from picker (still registered; existing content keeps working)
- `miss` (from `dnd5e.lua`, no DS usage) - conditional `hide = function()` at `TriggeredAbility.lua:338-350`.

### Already hidden by predicate
- `fumble` - gated by power-roll outcome structure; DS power rolls don't emit fumbles. Same predicate as `miss`.
- `hit` - deregistered at `MCDMRules.lua:1277`.

### Never registered in DS (5e-only)
- `attacked` - registered only in `dnd5e.lua:864-901`; DS never re-registers it. Existing 5e content references it, but it never appears in the DS picker. Event-payload symbols that existed only on `attacked` + `miss` (`outcome`, `roll`, `degree`, `attack`) are out of scope for DS symbol-prose work.

---

## New features (PROPOSED)

### Preview column
Three stacked panes, banner reads "Proposed New Preview Column" in the mockup.

**Trigger Preview card** - mirrors `TriggeredAbilityDisplay` rendering (see `DSModifyTriggerDisplay.lua:321`). All text auto-derived from programmatic fields unless a Display override fills the slot. Uses white-on-recognised / grey-on-unrecognised pattern (inherited from Activated Ability editor's preview).

**Mechanical View** - diagnostic mirror. Rollup header ("Trigger ready" / "N issues"). Per-row status chips (Valid / Unknown symbol / Empty / Trigger Subject mismatch / etc.) surface only for problem states. Rows: Event, Trigger Subject, Triggers When, Behaviours, Mode, When Active.

At the bottom, a two-clause **Trigger Summary** that reads the whole configuration in plain English:
- **Triggers when** [event phrase] [subject phrase] [condition phrase]
- **Then** [behaviour list as prose]

Example (dev lead's sketch, updated 2026-04-24 for second-person self voice): *"Triggers when an enemy deals 5 or more damage to you. Then pushes the attacker 4 squares and knocks them prone."* This is ALWAYS derived from the programmatic fields - no override path. The Trigger Preview card's Display prose overrides only affect the player-facing card, never the Mechanical View summary.

Requires the Condition Prose Engine (opt-in item #4 in this doc). Without it, falls back to raw formula in the when-clause and a terse list in the then-clause. Dev feedback suggests this should be elevated from opt-in to launch scope - revisit in phasing discussion.

**Test Trigger** - collapsed strip by default (single 32px row with last-run summary). `Run Test` button expands the panel and immediately runs with default inputs. Inside the panel: typed input per GoblinScript symbol referenced by the condition, a result block with pass/fail and the concrete values that decided it, behaviour list preview, close-to-strip button.

Scope of Test Trigger (what it does and does not do):
- **Does**: compile the condition, evaluate with substituted inputs from real scene tokens, resolve map-state functions (Distance, Count Nearby, Line of Sight, Adjacent) against real token positions, show pass/fail with concrete values, highlight which sub-condition failed in compound conditions, preview the behaviour list that would run on pass, live-update result on slider release.
- **Does not**: execute behaviours for real; simulate multi-trigger cascades; replace the runtime Trigger Debugger; persist scenarios across sessions (initially).

### Role tokens from scene
When a trigger's Trigger Subject is other than `Self` - or when the condition references a role symbol the event exposes (Attacker on `losehitpoints`, Target on `targetwithability`, Caster on aura triggers) - the Test Trigger panel grows a **role-token slot** at the top for each referenced role.

**Source: tokens on the current scene.** Each role slot is a dropdown populated from real tokens placed on the active map. No fabricated templates; test subjects are real creature objects with every field populated correctly. Map-state functions the condition may reference (`Distance`, `Count Nearby Enemies`, `Line of Sight`, `Adjacent`) resolve against actual token positions rather than pretend state.

**Why not pretend tokens:** fabricated templates risk silent divergence from the runtime - any field the engine looks up that the template didn't model causes the test to pass while a real run fails. Using real tokens eliminates that class of false-positive. (Dev feedback 2026-04-23.)

**Dropdown hierarchy per role slot:**
1. **Preferred list** - tokens on the scene that already have the container (feature / ability / item) holding this trigger. Same resolution path the runtime uses.
2. **Secondary list** - all other tokens on the scene, below a divider. Used for Attacker / Target / Caster role slots where the role is an adversary rather than the trigger's owner.
3. Both lists filtered by the slot's Trigger Subject constraint (e.g. an "Any Ally" slot hides enemies).

**Auto-fill:** the first token in the preferred list (or secondary list, if preferred is empty) matching the Trigger Subject filter. Author can swap via the dropdown.

**Empty / missing states:**
- No tokens on scene: tip *"Place a token on the map to test against."* Run Test disabled.
- No tokens match the Trigger Subject filter: tip *"No token on this scene matches [Trigger Subject label]."*
- No tokens have the container feature (preferred list empty) but secondary has entries: tip *"No token on this scene has [feature name] - add it via [container UI], or pick any token below to test with."*

**Scene context requirement:** Test Trigger requires an active scene. Opening the editor from a compendium browser with no scene loaded shows the scene-context tip instead of the Run Test button.

**Experience flow** (example: a trigger with Trigger Subject=Self, event=Take Damage, condition `damage >= 5 and Attacker.Keywords has "Melee"`):
1. Click Run Test -> panel expands.
2. Condition references `Attacker.Keywords`, so an **Attacker** role slot appears with a dropdown of scene tokens (filtered to enemies, preferred list showing any that already have the feature).
3. Default fill: first matching enemy token on the scene.
4. Event symbol inputs below (damage slider, damagetype dropdown, hasattacker toggle).
5. Auto-runs with defaults. Author can swap the Attacker via dropdown; slider release re-evaluates.
6. Result block reports: "with Attacker = Goblin Skirmisher (Melee, Strike) -> keyword check passed; damage 5 >= 5 -> true".

For triggers with Trigger Subject representing a group (e.g. `Any Enemy`, `Self or an Ally`), the role dropdown is filtered to matching tokens and the author picks one as the concrete test instance.

**Implementation note to verify:** preferred-list detection depends on a cheap API for "tokens on the current scene that have feature X". If feature-attachment walks (class / ancestry / kit / inventory / token-direct modifiers) turn out to be expensive per-token, scope the preferred list down to token-direct cases and lean on the secondary-list tip for indirect containers.

### Trigger Event picker modal
See previous section. Replaces the flat alphabetical dropdown in the classic editor.

### Trigger Mode progressive disclosure
Segmented toggle (2 common modes) + inline "Advanced modes" expander (3 advanced radios). Data model unchanged - still writes one of the five `mandatory` values.

### Display section
New sub-surface for per-field card overrides. See "Display section" in Design Decisions.

---

## Opt-in technical additions

Each is optional. Skipping any degrades a specific affordance but nothing breaks at runtime.

### 1. Symbol prose templates
Add optional `prose` field to each GoblinScript symbol declaration (on `RegisterSymbol` / inline symbol tables).

```lua
damage = {
    name = "Damage",
    type = "number",
    desc = "The amount of damage taken when triggering this event.",
    prose = "the damage",   -- NEW, optional
}
```

**Why:** powers auto-derived card text and the "Triggers when: X" dry-run sentence. `damage >= 3` -> "the damage is at least 3".
**If skipped:** raw formula fallback. Editor still works. Per-symbol degradation until backfilled.
**Effort:** ~1 day backfill for ~30-40 existing symbols. ~1 minute per new symbol.

### 2. Function prose templates
Same pattern for GoblinScript functions (`Distance`, `Count Nearby Enemies`, `Stacks`, `Line of Sight`, `Friends`, etc.). Template uses positional placeholders:

```lua
RegisterSymbol("Distance", {
    fn = function(ctx, target) ... end,
    type = "number",
    prose = "the distance to {1}",   -- {1} = first argument
})
```

**Effort:** ~15-20 functions.

### 3. Trigger Subject-event compatibility metadata
Declarative lookup of which Trigger Subject values are valid for each trigger event. Powers the "Trigger Subject does not match event" warning chip.

**If skipped:** author discovers mismatches at runtime via Trigger Debugger log (`TriggeredAbility.lua:947-959` already logs "attacker not available").
**Effort:** ~half day. Mapping is implicit in the subject resolver today; just needs extraction.

### 4. Condition prose rendering engine -- LAUNCH SCOPE (resolved 2026-04-24, Option A)
New Lua subsystem (probably `DMHub Utils\GoblinScriptProse.lua`). Given a GoblinScript formula string, returns plain-English sentence.

**Approach:** regex pattern-match against 8 launch-tier grammar shapes (below), fall back to raw formula for anything that doesn't match. Uses the `prose` fields on symbol / function registrations (from the worksheets) to fill in noun phrases. Covers ~80-90% of real compendium conditions when patterns compose via AND/OR chains.

**Launch-tier pattern shapes** (locked 2026-04-24):

| # | Shape | Matches | Renders as |
|---|---|---|---|
| 1 | Bare boolean symbol | `Path.Forced`, `Has Ability`, `Tier One` | *"the movement was forced"* |
| 2 | Negated boolean (`not X`) | `not Path.Forced`, `not Has Attacker` | *"the movement was not forced"* |
| 3 | Numeric comparison (`X [>=><<=!=] Y`) | `Damage >= 5`, `Subject.Level < Attacker.Level` | *"the damage is at least 5"* |
| 4 | String equality (`X is "value"`) | `Damage Type is "fire"`, `Condition is "Grabbed"` | *"the damage type is fire"* |
| 5 | Set membership (`X has "value"`) | `Keywords has "Melee"` | *"the damage keywords include Melee"* |
| 6 | AND chain (`A and B [and C]`) | `Damage > 5 and Path.Forced` | *"the damage is more than 5 and the movement was forced"* |
| 7 | OR chain (`A or B`) | `Damage Type is "fire" or Damage Type is "acid"` | *"the damage type is fire or the damage type is acid"* (optional same-left-side collapse to *"fire or acid"*) |
| 8 | Function call (`F(args) [op] Value`, bare form, or comparison form) | `Distance(Subject) <= 1`, `Cast.passespotency(Target, "mgt", 2)` | *"the distance to the subject is at most 1"*, *"the target passes the potency check"* |

**Parser responsibilities** (not separate patterns, but required for the 8 to compose):
- Parenthesis handling (`(A or B) and C` is common).
- Case / whitespace insensitivity (GoblinScript normalises both).
- Raw-formula fallback when no pattern matches any sub-expression.

**Engine special-cases** for dynamic-prose symbols (rendered at display time, not from static `prose` fields):
- `Subject` -- 8-entry table keyed on ability's `subject` field value.
- `Speed` -- 4-entry table keyed on trigger id (collide / wallbreak / fall / fallenon).
- `Quantity` -- 3-entry table keyed on trigger id (earnvictory / gainresource / useresource).

**Post-launch patterns** (deferred; add incrementally if real-world content needs them):
- Arithmetic expressions (`X + Y > Z`)
- Ternary / conditional (`if X then Y else Z`)
- Complex nested function calls that aren't simple `F(args)` comparisons

**Effort:** ~3 critical-path days for the engine (tokeniser + parser + 8 pattern matchers + testing); ~1 day for symbol/function `prose` backfill wire-up from the worksheets. **~4 days total.**

**If skipped (Option C fallback):** dry-run and auto-derived card Trigger row always show raw formulas. Dev lead's gut-check Trigger Summary reads as garbage in ~25-50% of abilities. Mechanical view chips and Test Trigger still work.

Companion review artifacts:
- [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md) - worksheet enumerating ~70 reviewable entries (47 event-payload + ambient symbols, 25 top-used Ability / Cast / Path properties). Reviewed + locked 2026-04-24.
- [BEHAVIOUR_PROSE.md](BEHAVIOUR_PROSE.md) - worksheet enumerating 34 DS-active behaviours with per-type prose templates. Reviewed + locked 2026-04-24.

Creature-property symbols (~50) are backfill-incremental, not launch-blocking.

### 5. Behaviour prose templates
Per-behaviour-type prose generation for the Mechanical View's Trigger Summary "Then" clause. Reads author-configured fields from each behaviour (damage roll, push distance, effect name, etc.) and emits a plain-English fragment. Engine recurses into nested behaviour structures (power-roll tiers, aura triggered abilities, modifier objects).

**Approach:** dispatch table keyed by behaviour type id. Trivial / Easy / Moderate tiers use field-substitution templates. Recursive tier calls back into the engine for nested structures. Hard tier (freeform GoblinScript fields like `AbilityMacro.macro`, `AbilityRecastAbility.abilityFilter`, `draw_steel_command.rule`) renders formula-string literally. Impossible tier (UI-modal behaviours with no declarative fields - `persistenceControl`, `recoverySelection`, `rouitineControl`) renders a bare type-name phrase.
**If skipped:** the "Then" clause of the Trigger Summary falls back to a comma-joined list of behaviour type names (e.g. "Damage, Forced Movement, Ongoing Effect"). Still informative, just not narrative.
**Effort:** ~1.5 days for the launch tier (Trivial + Easy + `damage` - covers ~15 behaviour types by authoring frequency). ~3-5 days for full Moderate + Recursive coverage. Hard / Impossible tiers are permanent fallbacks, no further work.

Companion review artifact: [BEHAVIOUR_PROSE.md](BEHAVIOUR_PROSE.md) - worksheet enumerating all 34 DS-active behaviour types with proposed templates and complexity tiers. 5 5e-suppressed types excluded per `MCDMRules.lua:1262-1266`.

---

## Gotchas (things that tripped us up - read these)

### 1. "Trigger Subject" is a UI-label-only rename; four underlying concepts still exist
The new editor renames the UI form label to **"Trigger Subject"** (resolved 2026-04-23) - but the underlying four concepts are still distinct in code, and you must not conflate them when reading or writing Lua / formulas:
- **Trigger Subject field (UI label)** - the form dropdown the author selects, data field `subject`, values like `self`, `any`, `selfandheroes`. Declared at `TriggeredAbility.lua:152-155`. Helper text in the form: *"Who the editor is listening for the trigger event to occur on."*
- **Data field `subject`** - UNCHANGED. Still serialises as `subject` in the YAML / Lua object. Renaming this is out of scope (data migration risk).
- **Runtime resolved subject token** - the creature the engine resolves when the event raises. `symbols.subject = creature` at `TriggeredAbility.lua:855-856`. Name unchanged.
- **GoblinScript `Subject` symbol** - variable referenceable inside condition formulas (e.g. `Subject.stamina`). Registered at `TriggeredAbilityEditor.lua:239` via `symbols = {subject = {...}}`. Name UNCHANGED. Never rename; every bestiary formula that references it would break.
- **Behaviour-target dropdown display** - the behaviour target value `subject` in `TriggeredAbility.TargetTypes` (line 114-165) displays as **"The Trigger Subject"** in the behaviour target dropdown, to match the form field label. Underlying value string `subject` is unchanged.

**Summary:** user-facing labels say "Trigger Subject" (form) or "The Trigger Subject" (behaviour target dropdown). Everything below the UI layer keeps its existing name. If you are writing Lua or editing compendium YAML, use `subject`. If you are writing UI strings or docs for authors, use "Trigger Subject".

### 2. "Triggers Only When" vs "Condition" vs "Filter" vs `conditionFormula`
The Draw Steel codex uses several terms for the same thing:
- **Classic editor UI label:** "Condition"
- **Data field:** `conditionFormula`
- **Engine error messages:** "trigger condition"
- **New editor UI label:** "Triggers Only When" (form) / "Triggers When" (mechanical view short form)
- **Hodent pass decision:** "Triggers Only When" was selected as the plain-language winner for the form field.

Narrative prose in docs can use "condition" or "trigger condition" - the plain-language label only applies to user-facing controls.

### 3. Cooldown / usage limits live on the parent ActivatedAbility
The classic Triggered Ability editor has NO cooldown field. Usage limits (per-round, per-encounter, per-day, per-respite) are on `ActivatedAbility.usageLimitOptions` (parent class), edited in the ActivatedAbility editor. A Cooldown field in the Triggered Ability editor is an imagined feature - don't add it.

### 4. GoblinScript has no AST exposed
`dmhub.CompileGoblinScriptDeterministic(formula, out)` returns a Lua closure + `out.lua` (compiled source). No parsed tree. Prose rendering needs either:
- Regex/pattern matching on the raw formula string (Option B, recommended).
- Custom parser (overkill for a prose feature).

Don't plan on walking an AST that doesn't exist.

### 5. Trigger enumeration requires reading multiple files (and distinguishing scope)
Triggers live in several places, and each has a different scope. Get this wrong and you end up with false positives in "unregistered trigger" detection or wrong options in the picker.

**Main Triggered Ability editor picker** - read these:
- `DMHub Game Rules\TriggeredAbility.lua:167-436` - inline `TriggeredAbility.triggers = {}` table (21 base triggers)
- `DMHub Game Rules\TriggeredAbility.lua:500+` - base `RegisterTrigger` calls (7 additions)
- `Draw Steel Core Rules\MCDMRules.lua:1015-1487` - DS-specific `RegisterTrigger` calls (16 triggers)

**Separate systems - DO NOT include in the main picker:**
- `DMHub Game Rules\Aura.lua:24,28` - aura-specific trigger ids (`onenter`, `casterendturnaura`). These only apply inside the Create Aura behaviour's embedded TriggeredAbility editor. See the "Aura-embedded triggered abilities" section above.
- `Draw Steel Core Rules\PowerTableTriggers.lua` - separate `powertabletrigger` character modifier with its own local `g_triggerChoices` table (lines 43-79). Not a `TriggeredAbility` at all.

Missing any file from the first group = false positives in "unregistered trigger" detection. We hit this once: the crawl claimed 100+ unregistered triggers; the real answer was closer to 0 because `MCDMRules.lua` was skipped.

Including `Aura.lua` in the main picker = offering authors trigger events they can never actually raise from a standalone ability, leading to silent no-ops at runtime.

### 6. TargetTypes and Trigger Subject are different axes
- `TriggeredAbility.TargetTypes` at `TriggeredAbility.lua:114-165` - **behaviour-level** target resolution (who the behaviour affects). Values like `self`, `all`, `attacker`, `target`, `pathmoved`, `subject`, `aura`. The `subject` value here is displayed as "The Trigger Subject" in the behaviour target dropdown.
- `TriggeredAbility.subject` at `TriggeredAbility.lua:152-155` - **trigger-level** Trigger Subject selection (whose event context the trigger listens to). Displayed as "Trigger Subject" in the form. Values at `TriggeredAbilityEditor.lua:54-62`.

Even though the UI labels share the word "Trigger Subject", these are two distinct axes: one chooses whose event the trigger fires on, the other chooses whom the behaviour applies to. Never conflate them in code.

### 7. Empty behaviours are legitimate in ~4% of content
Bestiary crawl (339 `TriggeredAbility` objects): 13 have empty behaviours. Two legitimate patterns:
- **Aura bookkeeping** - `silent: true`, no behaviour, no description. The trigger exists to clean up aura state.
- **Narrative-only abilities** - description tells the GM what to do; no mechanical behaviour (rival-fury "Overpower", rival-tactician "Take the Opening", etc.).

The Mechanical View should not warn on empty behaviours when `silent: true`. For the INFO-level warning (non-silent + empty description + empty behaviours), it's a real authoring-stub case.

### 8. The `silent` flag is runtime-only
Not exposed in the classic editor UI. Controls whether a trigger auto-targets without prompting for selection. Set programmatically on the ability object. Interpreted at `TriggeredAbility.lua:134`.

### 9. Mockup template string trap
When writing JavaScript template literals that will be instantiated multiple times, do NOT reference per-instance variables (like `inst`) in a module-scope `const`:

```js
// WRONG: throws ReferenceError at load time
const editorHTML = `... ${inst} ...`;

// RIGHT: function takes the variable as a parameter
const makeEditorHTML = (inst) => `... ${inst} ...`;
```

We shipped this bug in the mockup; the editor frames rendered empty because the script threw before reaching the instantiation loop.

### 10. Existing validation hooks to piggyback
The runtime already logs reasons for these cases - the Mechanical View can surface the same info at authoring time:
- `TriggeredAbility.lua:734-757` - subject mismatch ("Wrong subject")
- `TriggeredAbility.lua:859-874` - condition evaluation failure (reason logged)
- `TriggeredAbility.lua:898-910` - aura missing ("No aura found")
- `TriggeredAbility.lua:947-959` - missing attacker/target ("attacker not available")

---

## Open questions (parked for before Lua implementation)

1. **Action links in Mechanical View diagnostics** - "Pick a replacement" (for unregistered trigger event errors), "Open event picker" (for prose-in-id errors). UX details still to design.
2. **Test scenario persistence** - should "last run" state survive editor close-and-reopen, or reset on every open? Simpler to reset; saved scenarios can come later if demand shows up.
3. **Deprecation story for `TriggeredAbilityDisplay` modifier** - the classic modifier-based card display still exists in content. New editor derives the card from fields directly. Need a migration plan.

### Resolved
- **Subject terminology rename** (resolved 2026-04-23) - UI field renamed to **"Trigger Subject"** and the behaviour-target dropdown displays the `subject` value as **"The Trigger Subject"**. Data field `subject`, runtime token naming, and GoblinScript `Subject` symbol all UNCHANGED. Formula migration explicitly out of scope. See gotcha 1 for the full picture.
- **Pretend token templates for Test Trigger** (resolved 2026-04-23) - superseded by scene-token approach; the Test Trigger panel now pulls role tokens from the active scene with preferred/secondary ordering based on container-feature membership. See "Role tokens from scene" section. Dev feedback (Denivarius, James/Vex, Djordi) flagged fabricated templates as a false-positive risk vs. the runtime.
- **Condition Prose Engine phasing** (resolved 2026-04-24, Option A / Launch Tight) - prose engine elevated to launch scope (phase 4-5 of implementation). Ships with 8 grammar pattern shapes + launch-tier symbol/function/behaviour prose vocabulary from the two companion worksheets. Covers ~80-90% of real compendium conditions via pattern composition; raw-formula fallback for the rest (no regression vs classic editor). ~4 critical-path days (~3 engine + ~1 vocabulary wire-up). Pattern enumeration in opt-in #4 above.

---

## Review items (things to confirm during Lua implementation)

Things that aren't design questions but must be validated during / after the editor rewrite to avoid regressions.

### Aura behaviour embedded trigger editor
The Create Aura behaviour (`CharacterModifier` with `behavior = "aura"`) embeds a TriggeredAbility editor for its `aura.triggers[]` list. Each embedded ability uses aura-specific trigger ids (`onenter`, `casterendturnaura` at `DMHub Game Rules\Aura.lua:24,28`).

**Must verify after the standalone editor rewrite:**
- The aura behaviour's embedded trigger editor still renders all its fields.
- Its trigger event picker shows the aura-specific event list (not the standalone list).
- Adding, editing, and removing aura-triggered abilities continues to work.
- Existing compendium content using aura triggers (e.g. `bestiary\abyssal-rift.yaml:197-246` Demon Portal) still loads and functions.

If the embedded editor shares code with the standalone editor, the picker's event list must be context-parameterized so the aura embed gets `Aura.lua`'s trigger ids and the standalone gets the main list.

### Existing compendium content load
Every existing TriggeredAbility in `compendium\bestiary\*.yaml` (339 objects across 540 files) must load and function without conversion. The data model is unchanged, so this should be trivial - but worth running an import check to confirm.

### Runtime behaviour unchanged
The engine's trigger dispatch, condition evaluation, subject resolution, and behaviour execution paths are all untouched by the editor rewrite. No regressions expected, but regression-test a few representative abilities (a simple reaction, a complex compound condition, an aura embed, a Heroic Resource trigger).

---

## Implementation architecture (revised 2026-04-24)

The new editor does NOT rewrite `DMHub Compendium\TriggeredAbilityEditor.lua`. That file is core functionality and stays untouched, mirroring how the New Ability Editor lives alongside `DMHub Compendium\ActivatedAbilityEditor.lua` rather than replacing it.

**File layout:**
- `DMHub Compendium\TriggeredAbilityEditor.lua` - unchanged. Contains `TriggeredAbility:GenerateEditor(options)` classic implementation.
- `Draw Steel Ability Editor\NewTriggeredAbilityEditor.lua` - new file. Preserves classic via `local classicGenerateEditor = TriggeredAbility.GenerateEditor`, then redefines `TriggeredAbility:GenerateEditor` with setting-gated dispatch.

**Dispatch rules** (inside the new `GenerateEditor`):
1. If `options.excludeTriggerCondition` or `options.excludeAppearance` set -> fall through to `classicGenerateEditor`. Keeps the aura-embedded editor path (`Aura.lua:234`) working unchanged. Zero regression risk for existing content.
2. If `dmhub.GetSettingValue("classicTriggeredAbilityEditor") == true` -> fall through to classic. User opt-out.
3. Otherwise -> new sectioned editor.

**Setting:** `classicTriggeredAbilityEditor` (boolean, default false). Mirrors the `classicAbilityEditor` setting pattern.

### Section layout (revised 2026-04-24)

Icon and Description were originally (per earlier revs) folded into the Trigger section. Moved to the Display section after user feedback that they aren't trigger-logic fields and shouldn't clutter the Trigger form.

| Section | Fields |
|---|---|
| **Trigger** | Name, Trigger Event, Trigger Subject, When Active, Requires Condition + inflicted-by, Trigger Range, Triggers Only When |
| **Response** | Trigger Mode, Prompt Text, Resource Cost, Manual Version, Action Used, When Target Despawns |
| **Effects** | Behaviour cards (all DS-visible types kept; behavior picker via `AbilityEditor.OpenBehaviorPicker`, with pending work to surface `momentary`) + "+ Add Behavior" button |
| **Display** | Icon (`self:IconEditorPanel()`), Description, plus phase-7 card-override field placeholders |

### Styling

Share the palette + visual language with the New Ability Editor. Use `AbilityEditor.COLORS` (resolved lazily at editor-creation time via `rawget(_G, "AbilityEditor")` since the New Ability Editor loads after us). Use `nae-*` style conventions as a reference; declare local classes with a `ts-` or similar prefix to avoid cross-contamination.

### Behaviour picker filter

Decision 2026-04-24: **keep all behavior types** that survive the existing `ActivatedAbility.SuppressType` calls (5 already suppressed: `attack`, `castspell`, `contestedattack`, `forcedmovement`, `saving_throw`). No additional allow/deny list for trigger context. The only extra requirement is to ensure `momentary` (unique to `TriggeredAbility.Types`) reaches the picker -- see parked technical decision in Start Here.

---

## Implementation plan (phasing)

1. **UI shell** - four sections with real field list, real dropdown values. Uses existing `TriggeredAbility` data model; no schema changes. Hide/show conditionals (Trigger Range, inflicted-by, Prompt Text) driven by existing field values. **SHIPPED 2026-04-24.**
2. **Trigger Event picker modal** - categorized picker lifted from `AbilityEditorBehaviorPicker.lua` pattern. `TRIGGER_METADATA` + `TRIGGER_GROUPS` tables live in `NewTriggeredAbilityEditor.lua`; approved renames applied via per-id `label` overrides; `miss` / `attacked` excluded; `fumble` filtered via the existing `hide()` predicate. Field row is a field-shaped button that opens the modal on press; selection writes to `ability.trigger` and the button label refreshes via section rebuild. **SHIPPED 2026-04-24.**
3. **Trigger Mode progressive disclosure** - segmented toggle for the two common `mandatory` values (`false` = Prompt the Player, `true` = Occurs Automatically) + "Advanced modes" expander revealing three radios (`"local"`, `"prompt_remote"`, `"game:heroicresourcetriggers"`). Control writes to `ability.mandatory` directly so existing `IsMandatory` / `MayBePrompted` helpers keep working unchanged. Expander starts open when the current value is advanced. **SHIPPED 2026-04-24.**
4. **Mechanical View pane** - static validation using existing runtime hooks (gotcha 10). Chips and rollup. **SHIPPED 2026-04-24.** Runtime-hook integration deferred to phase-4 v2. Opt-in #3 narrow compatibility (global subjectless triggers) shipped alongside.
5. **Trigger Preview card** - auto-derives from fields. **SHIPPED 2026-04-24.** Uses `GoblinScriptProse.RenderTriggerSentence` for the Trigger row and `GoblinScriptProse.RenderBehaviourList` for the Effect row (opt-in #5 full pass shipped 2026-04-24).
6. **Test Trigger panel** - compiles and evaluates the `conditionFormula` with author-supplied inputs using existing GoblinScript eval. No new eval infrastructure. **Not started.**
7. **Display section card-override fields** - override fields on top of the existing Icon + Description panel; blank falls through to derivation. **SHIPPED 2026-04-24** -- 8 override fields land on `display*` data fields (`displayName`, `displayCardType`, `displayCost`, `displayDistance`, `displayTarget`, `displayFlavor`, `displayTriggerProse`, `displayEffectProse`); preview card's `pickOverride` helper picks override-or-derivation per row. Card Type changes the title-bar colour and Type row label. Cost replaces the previously-blank Keywords row (Keywords had no override and no derivation, so the slot was unused). Each row's input fires `fireChange()` so the preview rebuilds on the same debounced 0.15s timer that other field edits use.
8. **Condition Prose Engine + symbol / function prose wiring** - launch-tier grammar per opt-in #4 (8 patterns). **SHIPPED 2026-04-24.** Behaviour prose (opt-in #5) full pass also shipped 2026-04-24 -- see changelog rev 13.

**Effects section behaviour-card replacement** - **SHIPPED 2026-04-24.** `NewTriggeredAbilityEditor.lua:buildEffectsSection` now composes the per-behaviour cards from `AbilityEditor.BuildEffectsSection(ability, fireChange)` (newly exposed public wrapper around the internal `_buildEffectsSection`). `fireChange` dispatches `refreshAbility` across the root subtree so both the behaviour list's key-guarded rebuild and the bottom bar's paste-button visibility stay in sync. Killed the known phase-1 alignment leak (Add Ability Filter / Add Reasoned Filter now left-aligned inside their parent behaviour card).

**Effects bottom bar (Add / Paste anchored)** - **SHIPPED 2026-04-24.** `detailCol` is now a non-scrolling vertical container holding `detailScroll` (vscroll, padded, contains section contents) and `effectsBottomBar` (anchored via the shared `nae-effects-bottom-bar` style). `selectSection` toggles the bar's `collapsed` class per tab and shrinks `detailScroll.height` to `100%-42` on Effects. The bar hosts a centered button cluster: `+ Add Behavior` (opens `AbilityEditor.OpenBehaviorPicker`) + `Paste Behavior` (collapse-anim'd unless `dmhub.GetInternalClipboard` holds an ActivatedAbility*Behavior; refreshed via `refreshAbility` and the engine's `internalClipboardChanged` event). Mirrors the New Ability Editor UX. Full-screen context is guaranteed -- the aura-embed path falls through to the classic editor so this never runs inside another panel.

---

## Changelog

- **2026-04-23** - Document created as handoff. Supersedes `TRIGGER_PICKER_CATEGORIES.md` and `RESPONSE_SECTION_LABELS.md`. Interactive mockup (`triggered-ability-editor-interactive.html`) shared with devs for feedback.
- **2026-04-23** (rev 1) - Clarified that aura-specific trigger ids (`onenter`, `casterendturnaura` from `Aura.lua`) belong to the Create Aura behaviour's embedded TriggeredAbility editor only, NOT the standalone picker. Added Review Items section with the aura embed regression-check requirement.
- **2026-04-23** (rev 2) - Lead developer feedback incorporated. Added Pretend Tokens section under Test Trigger (stock template roster, experience flow, scope). Extended Mechanical View to include a plain-English Trigger Summary ("Triggers when... / Then...") with the dev's sketch as the canonical example. Opened question #6 on elevating the Condition Prose Engine from opt-in to launch scope.
- **2026-04-23** (rev 3) - Second round of dev feedback (Denivarius, James/Vex, Djordi). Replaced Pretend Tokens design with "Role tokens from scene": Test Trigger pulls real tokens from the active scene with preferred/secondary ordering by container-feature membership, an empty-scene tip, and a scene-context requirement. Map-state functions (Distance, Count Nearby, Line of Sight, Adjacent) are now evaluated against real positions rather than pretend inputs. Open question 3 (pretend-token roster) resolved and moved to Resolved subsection; remaining questions renumbered. Open question 1 updated to reflect the "Trigger Subject" candidate naming, including the behaviour-target display knock-on.
- **2026-04-23** (rev 4) - Subject terminology rename confirmed: UI field is now **"Trigger Subject"** and the behaviour-target dropdown displays the `subject` value as **"The Trigger Subject"**. Explicit scope boundary: UI labels only - data field `subject`, runtime subject token naming, and GoblinScript `Subject` symbol are all unchanged. Propagated through Sections table, dropdown-values header, Trigger Range note, Mechanical View row list, Role tokens from scene section, and opt-in #3 (compatibility metadata). Gotcha 1 rewritten to document the resolution; gotcha 6 updated to distinguish the two "Trigger Subject"-labelled axes (trigger-level Trigger Subject field vs behaviour-level `subject` target value). Open question 1 resolved and moved to Resolved subsection; remaining open questions renumbered (1-4). Start Here "What's blocking" updated accordingly.
- **2026-04-23** (rev 5) - Prose-engine scoping pass. Created two companion review worksheets: [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md) enumerates the ~47 event-payload + ambient symbols with proposed prose fragments; [BEHAVIOUR_PROSE.md](BEHAVIOUR_PROSE.md) enumerates all 34 DS-active behaviour types with templates grouped by complexity (Trivial/Easy/Moderate/Recursive/Hard/Impossible). Added opt-in #5 (Behaviour prose templates) to the design doc - previously a gap in the opt-in list. Dynamic-prose pattern established for the `Subject` symbol: its rendered fragment is derived from the ability's `subject` field value (e.g. `subject=enemy` -> "the enemy"), not from a static string. Added `attacked` to the 5e-excluded trigger list (never registered in DS; only in `dnd5e.lua:864-901`). Codebase bugs flagged: `forcemove.hasattacker` declared as `creature` should be `boolean`; `AbilityRoutineCast` registers its type id as `rouitineControl` (typo). Both are data-migration-carrying renames to be handled separately from the editor rewrite.
- **2026-04-24** (rev 6) - Q4 resolved: Condition Prose Engine elevated to launch scope as Option A / Launch Tight. Opt-in #4 now specifies the 8 launch-tier grammar pattern shapes (bare boolean, negated boolean, numeric comparison, string equality, set membership, AND chain, OR chain, function call) -- covers ~80-90% of real compendium conditions via pattern composition; raw-formula fallback for the rest. ~4 critical-path days total (~3 engine + ~1 vocabulary wire-up). Both prose worksheets (symbol + behaviour) reviewed and locked by user. `attacked` trigger retained in scope as orphan-content case (7 compendium entries; dev ticket needed to verify runtime state). Three dynamic-prose symbols identified: `Subject` (keyed on ability's subject field), `Speed` (keyed on trigger id, 4 entries), `Quantity` (keyed on trigger id, 3 entries). Ability property `Ability.spell` marked DEFER (non-DS concept). Damage behaviour template simplified to drop `dcsuccess` / `magicalDamage` / `dc` after verifying DCEditor is stubbed in DS (5e leftovers with no DS editor UI). `manipulate_targets` prose rewritten to specify caster-prompt interaction (not author-time). `ongoingEffect` prose elevated to resolve effect-id to display name at render time. Pattern enumeration unblocks Lua implementation phase 1; Start Here "What's blocking" section updated accordingly.
- **2026-04-24** (rev 7) - Lua phase 1 architecture revised. First implementation attempt rewrote `DMHub Compendium\TriggeredAbilityEditor.lua` in place; rolled back to HEAD after user feedback that core-functionality files shouldn't be touched in place. New editor relocated to `Draw Steel Ability Editor\NewTriggeredAbilityEditor.lua` (user-created stub) with classic-preserving dispatch + `classicTriggeredAbilityEditor` setting toggle, mirroring the New Ability Editor pattern. Icon and Description moved from the Trigger section to the Display section to de-clutter Trigger (which should be trigger-logic fields only). Behaviour picker filter decision: keep all DS-visible behaviors (no additional allow/deny list beyond the existing five `SuppressType` calls). One technical decision parked for next session: how to expose `momentary` (`TriggeredAbility.Types[70]`, not in `ActivatedAbility.Types`) through `AbilityEditor.OpenBehaviorPicker` -- three options identified. See Start Here "Lua phase 1 status" for details.
- **2026-04-24** (rev 8) - **Lua phase 1 shipped.** `NewTriggeredAbilityEditor.lua` fully implemented: `classicTriggeredAbilityEditor` setting registered, dispatch (aura-embed fallthrough + opt-out + default sectioned editor), four sections with all real fields (Trigger / Response / Effects / Display), effects section lifted via `ability:BehaviorEditor()` for phase 1. Verified in DMHub via MCP: all nav tabs render, conditional fields hide/show correctly, aura-embed + opt-out paths fall through to classic, no Lua errors. Momentary picker resolved as Option 1 (3-line polymorphism edit to `AbilityEditorBehaviorPicker.lua` reading `ability.Types` / `ability.TypesById`). First polish pass done: nav column full-height with vertically centered button group, checkboxes use shared `checkbox` / `checkbox-label` / `check-background` / `check-mark` skin (labels now render right of the box instead of underneath), despawn dropdown shows corrected labels ("Skip Despawned Targets" / "Retarget to Corpse") via local `DESPAWN_OPTIONS` override. Second polish pass: exposed AE style pack as `AbilityEditor.GetEditorStyles`, rewrote `buildStyles()` to inherit the full pack, renamed all local `ts-*` classes to `nae-*`, added only one scoped override (`selectors={"appearance"} halign="left"` for Custom Icon check). Known phase-1 leak flagged for phase 2: "Add Ability Filter" / "Add Reasoned Filter" buttons still center-aligned because the classic wrapper panels in `ActivatedAbilityEditor.lua:1825+` have width=auto with no halign and no targetable class -- resolves when phase 2+ replaces `BehaviorEditor` with our own sectioned behaviour cards.
- **2026-04-24** (rev 9) - **Lua phases 2-3 + Effects BehaviorEditor replacement + Effects bottom bar shipped.** Phase 2 added a categorized Trigger Event picker modal (6 Common band priority-sorted entries + 27 others across Combat / Abilities & Power Rolls / Movement / Resources & Victory / Turn & Game Mode / Custom) with approved renames applied as per-id `label` overrides; `miss` + `attacked` explicitly excluded, `fumble` filtered via `hide()`. Field row is gold-accent-bar + bold cream label + inline `[Change]` button that pops the modal (no dropdown mimicry) -- final choice after iterating through plain text / bold-gold / bordered-chip / accent-bar variants. Phase 3 added progressive disclosure for Trigger Mode: segmented toggle for the two common `mandatory` values + "Advanced modes" foldout with three radios, using the shared `nae-more-options-*` style pack + `collapsed-anim` for content (left-aligned variant -- AE's own centered foldout deemed an oversight to fix later). Foldout auto-opens when current value is advanced. Effects section BehaviorEditor replacement: `AbilityEditor.BuildEffectsSection = _buildEffectsSection` exposed as one-line public alias; new editor composes per-behaviour cards via that wrapper. Killed the phase-1 Add Ability Filter / Add Reasoned Filter alignment leak. Effects bottom bar: `detailCol` split into non-scrolling wrapper + `detailScroll` (vscroll) + `effectsBottomBar` anchored via shared `nae-effects-bottom-bar` style; `selectSection` shrinks `detailScroll.height` to `100%-42` on Effects; bar hosts centered `+ Add Behavior` + `Paste Behavior` cluster; Paste visibility tracks clipboard via `refreshAbility` + `internalClipboardChanged` handlers. `fireChange` at editor scope dispatches `refreshAbility` across root subtree and threads through `makeSectionContent` -> `buildEffectsSection(ability, refreshSection, fireChange)`. All verified in-engine.
- **2026-04-24** (rev 10) -- **Phase 8 (Condition Prose Engine) shipped.** New file `DMHub Utils\GoblinScriptProse.lua` (~1000 lines, registered at `main.lua:13`). Tokeniser + recursive-descent shaper + 8 pattern renderers + vocabulary layer + pcall-safety wrapper. 75 symbols / 15 functions / 12 roles registered from the locked [TRIGGER_SYMBOL_PROSE.md](TRIGGER_SYMBOL_PROSE.md) worksheet. 90% coverage on a 29-formula real-bestiary smoke test; raw-formula fallback for the 3 remaining worksheet-deferred cases. Centralised vocabulary staging deliberately -- per-symbol `prose` field migration deferred until phases 4-5 validate the prose shapes (memory: `project_prose_engine_migration.md`). Future deferred: condition absorption ("when you take 5 or more fire damage" pattern-folding -- memory: `project_condition_absorption.md`).
- **2026-04-24** (rev 11) -- **Phase 5 (Trigger Preview card) shipped.** Added preview column (440px) + `buildTriggerPreviewCard` + `makePreviewColumn` + `renderTriggerProse` + debounced `schedulePreviewRefresh` (copied AE's 0.15s Schedule + 0.25s think poll pattern). Post-verification the user observed the Trigger row should show full event+subject+condition composition rather than condition-only, which led to the new [TRIGGER_EVENT_PROSE.md](TRIGGER_EVENT_PROSE.md) worksheet (42 event templates with placeholders `{subject}` / `{subject-possessive}` / `{s}` / `{es}` / `{is}`). Subject prose forked into `role` + `possessive` after the user flagged that "this creature takes damage" reads as developer-voice rather than the player-card idiom "you take damage" -- `self` now renders second person, compound subjects use "you or any ally". `GoblinScriptProse.RenderTriggerSentence` composer introduced: substitutes placeholders, handles verb agreement (base form for `you`, 3rd-singular for everything else), appends `, if <condition prose>.` when present, capitalises. Card's Trigger row uses the composer; Mech View's when-clause (phase 4) also uses it. Distance/target derivation deferred to phase 7. Effect row uses `SummarizeBehavior()` fallback until opt-in #5 behaviour prose ships.
- **2026-04-24** (rev 17) -- **Preview card polish pass + Modes in Trigger + Distance/Target derivations.** Post-ship feedback iteration. Preview card: Cost moved into the title bar parens as free text (`displayCost` field, falls back to `resourceNumber`); Cost kvRow replaced with Keywords; new keyword picker in the Display section between Cost and Distance (writes to `displayKeywords` as a set table, same shape as `ActivatedAbility.keywords`; mirrors the classic picker UX with chip rows + "Add keyword..." dropdown, but with smaller font + smaller bin icon sitting flush next to the keyword rather than pinned right). Flavour label, `kvRow`, and `fullRow` all got `hpad = 6, borderBox = true` so Keywords / Distance / Trigger / Effect labels now line up vertically with the title text and flavour (which sit at content_left + 6 inside the yellow title bar). Keywords value label got `textWrap = true` with a bounded width so long keyword lists drop to a second line inside the left 50% segment instead of bleeding into the Type column. "More options" chevron in the Setup targeting stack left-aligned via scoped priority-3 style override (`nae-more-options-row` -> `halign = "left"`); New Ability Editor's centered rendering preserved. Display section field labels dropped the "(prose)" suffix (`"Trigger (prose)"` -> `"Trigger"`, same for Effect). Modes / Variations injected into the **Trigger section** (not Setup -- 2026-04-24 feedback that Modes are a trigger-level concept, not a firing/targeting concern) after "Triggers Only When", via the new public `AbilityEditor.BuildModesSection` helper (extracted from `_buildOverviewSection`'s inline modes block via a forward-declared `_buildModesBlock` local; parallel to the earlier `BuildTargetingSection` exposure). Sparse real-world use (1 triggered ability in the compendium uses `multipleModes = "variations"`, Death Rampage) but parity with the classic editor's `BehaviorEditor -> TargetTypeEditor` path. Distance derivation wired: `self` subject -> `"Self"`; other subject with non-blank `subjectRange` -> `"Ranged {subjectRange}"`; `displayDistance` beats both. Target derivation wired via `ability:DescribeTarget()` which already handles AOE / target / emptyspace / self / per-allegiance combinations and falls back to `targetTextOverride` (the Setup-section's "Target Text:" row) before deriving; `displayTarget` in the Display section beats that.
- **2026-04-24** (rev 16) -- **Setup section rename + trigger-level targeting injection.** Section formerly called "Response" renamed to **Setup** (channeling Hodent's player-task framing -- the section sits mid-pipeline, so the previous-considered "Resolution" was rejected for its finality tone). Section id renamed to `setup` (no external dependants). Inside Setup, between "Also show as a manual trigger" and "When Target Despawns", we now inject the full trigger-level targeting stack: Target Type, Range/Length, Radius/Size/Width, Distance, Can Choose Lower Range, Target Count, Allow Duplicate Targeting, Proximity Targeting (+ Chain Proximity + Proximity range), Affects, Can Target Self, Cast immediately when clicked, Targeting mode (+ Forced Movement subgroup), Object ID, Target Filter, Range Text, Target Text, and a "More options" expander with Ability Filters + Reasoned Filters. All of these are conditional-visibility per the chosen Target Type and mirror the active-ability surface authors already know. Implemented by exposing `AbilityEditor.BuildTargetingSection = _buildTargetingSection` as a public helper (mirrors the earlier `AbilityEditor.BuildEffectsSection` exposure pattern), then calling it from `buildSetupSection` and splicing its children into the section. Target Type dropdown is event-aware via `ability:GetDisplayedTargetTypeOptions()` -- options filter through `TriggeredAbility.TargetTypes[*].condition(ability)` so e.g. "Path Moved Along" only appears when the trigger event is `finishmove`. Per design doc gotcha 6 / rev 4, the `subject` entry in `TriggeredAbility.TargetTypes` had its display text renamed from "Subject" to **"The Trigger Subject"** -- one-line change to a data table; underlying `id` stays `subject`, runtime token naming and the GoblinScript `Subject` symbol unchanged. The classic editor's "Target Type:" dropdown (`ActivatedAbilityEditor.lua:2010`) and the New Ability Editor's targeting section both pick up the new label automatically.
- **2026-04-24** (rev 15) -- **Phase 7 (Display card-overrides) shipped.** `buildDisplaySection` extended below the existing Icon + Description rows with eight per-field card overrides (Display Name, Card Type, Cost, Distance, Target, Flavor, Trigger prose, Effect prose). Each override stores to a `display*` field on the TriggeredAbility instance (`displayName`, `displayCardType`, `displayCost`, `displayDistance`, `displayTarget`, `displayFlavor`, `displayTriggerProse`, `displayEffectProse`). A `buildOverrideInput` helper covers the 7 text-input rows (single-line for Display Name, multiline for Flavor / Trigger prose / Effect prose); Card Type uses a Dropdown over the three `TRIGGER_TYPE_LABELS` values. `buildTriggerPreviewCard` now reads each override via a new `pickOverride(override, derived)` helper that returns the override when non-blank, the derived value otherwise -- so a blank field passes through to the engine-derived value (or the existing grey-italic `-` placeholder when the derivation is also blank). Card Type changes the title-bar colour through the existing `getTitleBarColor` and the Type row label; default `"trigger"` preserved when the field is unset or holds an unknown value. Flavor row uncollapses when set so the italic flavour line takes layout space only when populated. Cost replaces the previously-always-blank Keywords slot in the upper kvRow (Keywords had no override and no derivation, so the slot was unused authoring surface). Each input fires `fireChange()` so the preview rebuilds on the same debounced 0.15s timer used by other field edits. Verified in-engine: editor module reloads cleanly, all 8 fields persist on a synthetic TriggeredAbility instance, override values are readable via `try_get`, derivation paths still fire when overrides are blank.
- **2026-04-24** (rev 14) -- **Behaviour prose post-ship sweep + 7 additional templates landed.** Real-bestiary sweep of 80 triggered abilities (38 unique) surfaced 7 DS-active behaviour types missing from the locked [BEHAVIOUR_PROSE.md](BEHAVIOUR_PROSE.md) worksheet but used heavily in compendium content: `invoke_ability` (`ActivatedAbilityInvokeAbilityBehavior`), `floattext`, `change_initiative`, `purge_effects`, `replenish_resources` (with `mode = replenish | expend`), `remove_creature`, `conditionriders`. All landed in `GoblinScriptProse.lua` with verb-led templates that chain naturally. New helpers: `lookupResourceName` (`dmhub.GetTable("characterResources")[id].name`) and `lookupConditionName` (`dmhub.GetTable("charConditions")[id].name`). Total registered behaviour templates: 41. Also fixed power-table tier double-period bug -- author-written tier text ending in `.` no longer produces `..` when joined with `. Tier 2:`. Worksheet updated with an "Additional (post-sweep)" section and a 41-total tally. Out-of-scope follow-ups noted: condition prose engine misses for `Path.DistanceToCreature`, `ConditionCaster`, bare booleans like `Taken Turn` / `Captain` (these are opt-in #4 vocabulary gaps, not opt-in #5).
- **2026-04-24** (rev 13) -- **Opt-in #5 (behaviour prose) full pass shipped.** `GoblinScriptProse.lua` extended with a `behaviourProse` dispatch table keyed by behaviour `typeName` (class name -- read directly, not via `try_get`, since `typeName` is class-level), `RenderBehaviour(behaviour, ability, depth)`, and `RenderBehaviourList(ability)` returning `(text, isEmpty)`. Templates for all 34 DS-active behaviour types per [BEHAVIOUR_PROSE.md](BEHAVIOUR_PROSE.md): Trivial (9), Easy (5), Moderate (6), Recursive (7), Hard (3 -- `recast` uses the worksheet's FALLBACK), Impossible (4). Per-tier rendering for `power_roll` (3 tier text strings), effect-id->name lookup for `ongoingEffect` and `stealAbility` via `dmhub.GetTable("characterOngoingEffects")[id].name`, attribute lookup for `opposed` via `creature.attributesInfo[id].description`, paramid->label lookup for `modify_cast` via `ActivatedAbilityModifyCastBehavior.ParamsById`. Recursion bounded by `MAX_BEHAVIOUR_DEPTH = 3` (depth check before dispatch falls back to `SummarizeBehavior`). Chaining convention: `", "` between earlier items, `", then "` before the last, per worksheet. Editor (`NewTriggeredAbilityEditor.lua`) `behaviorsFallbackText` and `summariseBehaviours` both call the engine first, with the comma-joined `SummarizeBehavior` fallback retained for safety. Verified in-engine via MCP execute_lua across all 34 behaviour types and 3-/2-/1-/0-element chains.
- **2026-04-24** (rev 12) -- **Phase 4 (Mechanical View) shipped + narrow opt-in #3 compat warning + visual polish pass.** Added `buildMechanicalView(ability)` returning `(card, rollupInfo)` -- the rollup chip sits inline with the `How This Triggers` sub-heading rather than in its own row. Six validation rows (Event / Subject / Triggers When / Behaviours / Mode / When Active) with issue chips shown only for non-Valid states. Two-clause Trigger Summary -- "**Triggers when:** ..." (reuses `RenderTriggerSentence`) + "**Then:** ..." (comma-joined `SummarizeBehavior` fallback). Markdown-enabled labels use Unity rich-text `<b>` tags for bold leads. Narrow compat check: `GLOBAL_SUBJECTLESS_TRIGGERS` (`beginround` / `endcombat` / `rollinitiative`) paired with non-caster-inclusive subject flags "Never fires" -- matches the runtime reject at `TriggeredAbility.lua:746`. Broader semantic compat warnings intentionally not shipped. Visual polish after user review: column `Preview` heading removed (each pane has its own sub-heading); cards use DS "rich black" (`#040807`) with 2px `GOLD_DIM` border; `bgimage = "panels/square.png"` required for `bgcolor` + `borderColor` to paint (DMHub GUI gotcha). `COLORS.CARD_BG` spliced into `AbilityEditor.COLORS` on demand via `getColors()`. Runtime-hook integration (gotcha 10), broader compat matrix, action links, behaviour prose for the Effect/Then rows all deferred to follow-up phases.
