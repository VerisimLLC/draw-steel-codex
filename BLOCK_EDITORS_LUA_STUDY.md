# Block Editors in Lua: effort study and engine/data recommendations

**Status:** planning study, 2026-11-22 (historical estimates). Where it differs from the decision ledger in
[`BLOCK_EDITOR_FRAMEWORK.md`](BLOCK_EDITOR_FRAMEWORK.md) (authoritative) or
[`BLOCK_EDITOR_IMPLEMENTATION_PLAN.md`](BLOCK_EDITOR_IMPLEMENTATION_PLAN.md), those win (for example,
engine ask E2 is likely unnecessary: `transferDragTo` gives a drag ghost). Nothing in the codex was changed for this study.
**Inputs:** [`ABILITY_BLOCKS_DESIGN.md`](ABILITY_BLOCKS_DESIGN.md) (sections 4-7, decision ledger),
[`CLASS_AND_MODIFIER_EDITOR_PROPOSAL.md`](CLASS_AND_MODIFIER_EDITOR_PROPOSAL.md) (sections 0, 3, 4, 9-11),
the prototypes `ui-mockup/ability-blocks-stack.html` (4,368 lines) and `ui-mockup/class-builder/app.js`
(1,158 lines), this repository's Lua, and the compendium data in `verisimllc/draw-steel-data`
(`objectTables/`, used for the counts marked "data").
**Effort unit:** person-weeks (pw) for one developer who already knows the codex `gui` framework and
game types. Add roughly 30-50% for someone new to the codebase.

---

## 1. Summary for the designer

**Total: about 60-90 person-weeks for everything in both prototypes**, of which about 8-12 pw are
changes to shared rules code and data. With two developers that is roughly 7-10 months of calendar
time; with three, 5-7 months, because some pieces must happen in order.

A useful first milestone is much smaller: **the simple ability editor working on existing abilities
(open, read as blocks, edit common steps, save back untouched otherwise) is about 25-35 pw.** It is
where most authoring time goes, and everything else reuses its parts.

**No C# engine change is required.** Every recommended change below is in Lua (the rules live in
Lua: skill grants, attribute operations, aura triggers, ability matching, parameter hand-offs). Three
engine items would make the work cheaper or safer but are optional: a way to run round-trip tests on
the whole compendium without clicking through the app, a "drag a copy" option for panels, and undo
history for compendium items.

**The critical path** (each step needs the one before it):
1. **Round-trip harness and data models** (no UI): open every ability, trigger, modifier and class as
   blocks and save them back, and prove the result is identical. Includes a full GoblinScript
   parser/printer in Lua. *If this gate fails, the editors are unsafe on existing content.*
2. **Block framework** in `gui`: sentences with clickable words, pickers, the shelf, drag and drop.
3. **Ability editor**, then the **trigger editor** (same editor, different header and storage).
4. **Modifier sentences** (shared vocabulary for features, effects and the class builder).
5. **Class builder** (lanes, features, choices, resource gains, templates).

Paste readers, card overrides and templates hang off this path and can move later without
blocking it.

**Top changes to rules code and data (detail in Section 3):**

| # | Change | Verdict | Effort |
|---|---|---|---|
| R1 | One skill record that grants fixed skills **and** offers a choice (extend `CharacterSkillChoice`) | Required | 2-3 pw |
| R2 | Characteristic "to a maximum of N": the `cap` field in content is **ignored by the rules today**; honour it | Required (live bug) | 0.5-1 pw |
| R3 | Perk group tags: matching is exact text, data mixes "Perk"/"Perks"; the prototype's tags would match nothing for three groups | Required | 0.5-1 pw |
| R4 | Change Ability matched by ability id, not a name formula | Required for decision 9.3 | 1-1.5 pw |
| R5 | Card wording overrides on the ability itself (`displayOverrides`) so triggers no longer need a separate display record | Recommended | 3-5 pw incl. migration |
| R6 | Aura trigger "a creature ends its turn in the area" | Recommended | 0.5-1 pw |
| R7 | Nested follow-ups get their direct parent's values | Recommended | 0.5-1 pw |
| R8 | Power roll "applies" phrase | No engine change; editor mapping only | (in component e) |
| R9 | Weakness as negative damage reduction | Verified fine; no change | 0 |

---

## 2. Breakdown by component

Each component lists what exists to reuse, what is new, whether it is Lua-only, a size, and risks.
Sizes: S = under 2 pw, M = 2-5 pw, L = more than 5 pw.

### (a) Block and sentence rendering framework

**What authors get:** sentences with underlined words you click to change, pickers that open in
place, a shelf of blocks with search, drag and drop with a ghost and insertion marker, read mode vs
edit mode, keyboard paths for everything.

**Exists today:**
- Drag and drop: `draggable`, `dragTarget`, `canDragOnto`, `dragTargetPriority`, `dragMove`,
  `dragSnap`, `dragInPlace` (`Definitions/Panel.lua:65-75`). A working no-code step list with
  reorderable steps and drop targets between them: `DMHub Core UI/CommandBuilder.lua:1641-1700`.
- Clickable words inside a sentence: labels with `links = true` and `<link=id>` regions, read via
  `element.linkHovered` in `press`, with `hoverLink`/`dehoverLink` (`Definitions/Label.lua:16-17`;
  working precedent in `Draw Steel Core Rules/MCDMAbilityRollBehavior.lua:166-175` and the label near
  line 1077-1145, which underlines the chosen "or" option in tier text).
- Pickers: `gui.Dropdown`, `gui.Multiselect` (`DMHub Core UI/Dropdown.lua`, `Multiselect.lua`), popups
  via `element.popup`, `DMHub Core UI/SetEditor.lua`.
- Theme tokens and classes: `DMHub Core UI/ThemeEngine.lua`, `DefaultStyles.lua`, `DefaultStyles.md`,
  `STYLE_GUIDE.md`.
- Search ranking: none reusable for "name start, word start, synonyms, usage"; small to write.

**New:**
- A `BlockSentence` component: renders a list of tokens (text, value word, picker word, nested
  block) as one wrapping label with links, plus an edit mode for one token at a time.
- A shelf panel (search, Common group, collapsible categories), an insertion marker model, and a
  "next block goes here" cursor.
- A drag ghost from the shelf. `dragMove` moves the dragged panel itself, so dragging *from* the
  shelf needs a floating copy created on press (workaround in Lua; see engine ask E2).
- Keyed rebuild: the class-builder critique found that rebuilding the whole board loses focus
  (`CLASS_AND_MODIFIER_EDITOR_PROPOSAL.md` 11, problem 2). In `gui` the answer is to update the
  changed block's children only, never rebuild the stack.

**Lua-only.** Size **M-L, 4-6 pw.**

**Risks:**
- Performance: a 30-step ability with nested follow-ups is several hundred panels. Rebuilding a
  block on every keystroke must stay local. Measure early with the 20 largest bestiary abilities
  (plan step 3 in the brief).
- Link regions in labels are used for single words today; long sentences with many links and wrap
  need checking at 80-140% font size (`responsive-panel` guidance).

### (b) Ability editor

**What authors get:** the four-section stack, ~16 sentence blocks plus Advanced blocks for the rest,
tiers, potency, Only if, modes, follow-ups, a generated card with per-line wording overrides, a paste
reader, and "saves back unchanged unless edited".

**Exists today:**
- The Advanced editors stay as the fallback (decision D1): `Draw Steel Ability Editor/AbilityEditor.lua`
  (5,803 lines, entry `AbilityEditor.GenerateEditor` at 5339) and the dialog host
  `ActivatedAbility:ShowEditActivatedAbilityDialog` (`DMHub Compendium/ActivatedAbilityEditor.lua:3938`,
  39 call sites). The new editor can be offered from the same dialog.
- Behaviour registry: about 99 `ActivatedAbility.RegisterType` calls
  (`DMHub Game Rules/ActivatedAbility.lua:687`) and 131 behaviour game types, each with its own
  `EditorItems` form; Advanced blocks open that form.
- Prose for behaviours: `GoblinScriptProse.RenderBehaviour` (`DMHub Utils/GoblinScriptProse.lua:2677`).
- Tier text grammar: `ActivatedAbilityDrawSteelCommandBehavior.ValidateRule`, `WalkParsedSegments`,
  `DiagnoseTierText`, `ParseOrGroups` (`Draw Steel Core Rules/MCDMAbilityBehavior.lua:2666-3767`).
- Card: `ActivatedAbility:Render` (`Draw Steel Core Rules/MCDMActivatedAbility.lua:1681`), with existing
  text fields `flavor`, `rangeTextOverride` (3664) and `targetTextOverride` (3704).
- Diagnostics strip in today's editor (`AbilityEditor.lua:4897-5192`).
- Templates and "duplicate existing": `AbilityTemplate` table `abilityTemplates`
  (`Draw Steel Ability Editor/AbilityEditorTemplates.lua:31-50, 273`).
- Follow-up hand-offs: `AbilityUtils` in `DMHub Game Rules/AbilityInvokeAbility.lua:99-180`.
- Import parsing: `Draw Steel Importers/DrawSteelMonsterImporter.lua` (2,461 lines; statblock and
  ability parsing, `GetStandardAbility`/`GetStandardFeature` at 127-155), `DrawSteelRulesImporter.lua`
  (791 lines; classes and kits).

**New (with sizes):**

| Part | Notes | Size |
|---|---|---|
| `AbilityModel`: load a record into blocks, compile blocks back, fingerprints | Port of the prototype's open/compile logic. Each block remembers its source record and the compiled form at open; unchanged blocks write the original. | M, 3-4 pw |
| Sentence blocks for the ~16 common behaviours, plus Advanced | Power roll, damage, rule text, apply effect, conditions, forced movement, move a creature, heal, temp Stamina, resources, end effects, use another ability, float text, aura, modes, Only if. Advanced = summary + "Edit in Advanced editor". | L, 4-6 pw |
| Tier grammar blocks | Reuse the DrawSteelCommand parser; add the "#" tier-only steps and agreement checks. | M, 2 pw |
| Follow-ups and hand-offs | Generate `<<name>>` and `standardAbilityParams` from what the follow-up uses; keep existing names. | M, 2 pw |
| Card generation with per-line overrides | Book-style generation exists in `Render`; new is "basis" tracking and the rules-changed flag. Depends on R5 for lines with no field today. | M, 2-3 pw |
| Paste reader (plain card text, PDF copy, Steel Compendium markdown) | The prototype's reader is JS; the Lua importers parse statblocks, not class cards or markdown tables. Mostly a port with new rules. | M-L, 3-4 pw |

**Lua-only.** Size **L, 16-21 pw** for the full set; 10-14 pw without paste and overrides.

**Risks:**
- Fingerprint identity depends on serialised form. Lua tables have no key order and numbers vs
  numeric strings differ (`dr: -5` vs `dr: "-5"` both occur in data), so "identical" must be
  defined as `dmhub.DeepEqual` (`Definitions/dmhub.lua:1163`) on the deserialised object, not text.
- `ActivatedAbility.Create` sets transient flags (`_tmp_isNewAbility`, `AbilityEditor.lua:5780`);
  the new editor must not trip the old entry modal.
- Behaviours with their own `Deserialize` defaults (for example `proficiency`,
  `DMHub Game Rules/ModifierProficiency.lua:25-31`, `get_or_add` on load) can make an untouched save
  differ from the YAML even though nothing changed. The corpus test must compare after a load-save
  cycle of the *old* editor as the baseline.

### (c) Trigger editor and trigger display

**What authors get:** the same editor for triggered abilities; storage as Triggered Ability or Power
Roll Trigger decided by the steps; trigger conditions read as blocks using each event's own symbols;
the trigger's card generated from it instead of a separate display record.

**Exists today:**
- `NewTriggeredAbilityEditor.lua` (7,276 lines, `TriggeredAbility:GenerateEditor` at 7059), already
  using `GoblinScriptProse.RenderTriggerSentence` (`GoblinScriptProse.lua:1218`).
- Event list with typed symbols: `TriggeredAbility.triggers` (`DMHub Game Rules/TriggeredAbility.lua:259`,
  `RegisterTrigger` at 737; 22 more registered in `Draw Steel Core Rules/MCDMRules.lua` from 1351).
- Power roll trigger events: `g_triggerChoices` (`Draw Steel Core Rules/PowerTableTriggers.lua:43-79`),
  modifier type registered at 195.
- Display record: `TriggeredAbilityDisplay` / modifier `triggerdisplay`
  (`Draw Steel Core Rules/DSModifyTriggerDisplay.lua:15-66`); it finds its trigger **by name**
  (`FindLivePartner`, 322-345). The "Trigger:" line exists only here (617); a `TriggeredAbility` has
  no trigger-text field of its own.

**New:**
- `TriggerModel`: one in-memory model, two-way conversion between `trigger` and `powertabletrigger`
  modifiers keeping the modifier `guid` (brief 4h, items 1-6). M, 3-4 pw.
- Condition blocks from event symbols (roles, yes/no tests, "About this event"). M, 2 pw.
- Card for triggers without `triggerdisplay` (needs R5) and the display migration. M, 2-3 pw
  (counted under R5).

**Lua-only.** Size **M-L, 6-9 pw** (excluding R5).

**Risks:**
- 14 Lua files read `triggerdisplay`/`TriggeredAbilityDisplay` (35 references), including the hero
  builder (`Draw Steel Character Builder/FeatureCache.lua:1115`, `HeroBuilder.lua:944`), the sheet
  (`Draw Steel V/HeroSheetFeatures.lua:216`, `DrawSteelChararcterSheet.lua:7930`), Monster AI
  (`Monster AI/MonsterAISupport.lua:238`) and the timeline (`Timeline/AbilitySidebar.lua`). Retiring
  displays touches all of them.
- Switching storage type changes which symbol names formulas see (`Subject` vs `Triggerer`); raw
  formulas cannot be rewritten safely (brief 4h item 3).

### (d) GoblinScript test/value blocks and the formula (fx) control

**Exists today:**
- `gui.GoblinScriptInput` with `documentation` objects (output type, subject symbols, extra symbols,
  examples) on every formula field (`DMHub Core Panels/GoblinScriptEditor.lua:62`; 63 files use it).
  These are the picker data the blocks need.
- `GoblinScriptTable` (level steps) already exists, with `ToText()` producing
  `"X when Level >= 7 else Y"` (`GoblinScriptEditor.lua:5-55`). Formulas that are tables go to the
  engine evaluator (`DMHub Utils/GoblinScript.lua:137-160`).
- `GoblinScriptProse` has a tokeniser and a partial parser: 8 shapes only, "GoblinScript has no AST
  exposed" (`GoblinScriptProse.lua:10-18`, parser 306-584).

**New:**
- `GoblinScriptAst`: the full grammar (`where`, dice, `{}` interpolation, spaced names, `has`/`is`,
  function calls) with a printer that reproduces the original spelling when unchanged. Run over every
  formula in the compendium. M, 3-4 pw.
- Test and value blocks driven by `documentation` (intent-grouped picker, "all of / any of" lists,
  "type a formula instead" with live parse feedback, friendly names from `BEHAVIOUR_PROSE.md` and
  `TRIGGER_SYMBOL_PROSE.md`). M, 2-3 pw.
- The fx value box with quick picks and level steps, saving either a `GoblinScriptTable` (checklist
  quantity, as content does) or the `when ... else` string. S, 1-1.5 pw.

**Lua-only.** Size **M-L, 6-8.5 pw.** Engine ask E1 (an AST from the engine compiler) would make
the parser cheaper and exact, but is optional.

**Risks:** the closed engine compiler is the truth; a Lua parser that disagrees on an edge case
(spaced names, precedence) would silently change meaning. The corpus gate (parse, print, compare
compiled results with `dmhub.CompileGoblinScriptDeterministic` on sample symbol tables) mitigates it.

### (e) Modifier sentences

The class builder's sentences (`ui-mockup/class-builder/app.js:202-338`) map to these registered
modifier types (61 `CharacterModifier.RegisterType` calls in total; `CharacterModifier.lua:108`):

| Sentence | Modifier (registered at) | Notes from the code |
|---|---|---|
| Change a stat / movement type | `attribute` (`DMHub Game Rules/CharacterModifier.lua:557`) | Ops are only add/set/max/min (`CustomAttribute.lua:343-355`). Movement types work as attributes (`creature:GetSpeed`, `Creature.lua:784`). See R2 for "to a maximum of". |
| Edge/bane on tests or abilities, extra damage, rolls against you | `power` (`Draw Steel Core Rules/MCDModifyPowerRolls.lua:179`) | Three conditions plus after-roll; see R8. |
| Immunity or weakness | `resistance` (`CharacterModifier.lua:1076`) | DS restricts types to "Damage Reduction" (`MCDMRules.lua:1212`); weakness is negative `dr` (R9). |
| Can't be (condition) | `conditionimmunity` (`CharacterModifier.lua:1523`) | |
| Skill / language | `proficiency` (`ModifierProficiency.lua:18`) | See R1. |
| Recoveries or a resource | `resource` (`CharacterModifier.lua:2725`) | `num` is a number or formula. |
| Kit | `kitaccess` (`Draw Steel Core Rules/MCDMKit.lua:1060`) | |
| Gain an ability / triggered ability | `activated` (2131), `trigger` (2021), `powertabletrigger` | Open the ability/trigger editor (k). |
| Change an ability | `modifyability` (`DMHub Game Rules/ModifierModifyAbilities.lua:6`) | Name formula today; see R4. |
| Improves an ability | `abilityimprovement` (`Draw Steel Core Rules/DSAbilityImprovement.lua:30`) | |
| Reminder | `movementtext` (`DMHub Game Rules/ModifierMovementText.lua:31`) | |
| Only if | `filterCondition` on each modifier (`CharacterModifier:FilterConditionEditor`) | Choices cannot carry it (correctly blocked in the prototype). |

**Exists:** each type's `createEditor`/`autoDescribe` (reuse `autoDescribe` for prose and as the
Advanced fallback form), the modifier picker `Draw Steel Ability Editor/AbilityEditorModifierPicker.lua`.

**New:** a `ModifierModel` (open, compile, fingerprint) and one sentence descriptor per type,
registered next to each `TypeInfo` as an optional field, with the opaque fallback for the other ~45
types. About 0.3-0.5 pw per sentence including round-trip tests.

**Lua-only.** Size **M, 5-7 pw.**

**Risks:** many modifiers copy their feature's text into `description` (1,040 of 1,765 in classes,
proposal section 5); the editor must keep descriptions untouched unless edited, and decide whether
new modifiers leave them empty (open question 3 in the proposal).

### (f) Class builder: lanes, features, choices, storage decisions

**Exists today:**
- Class model and level keys: `Class:FillLevelsUpTo` (`DMHub Game Rules/Class.lua:259-303`) gives
  `tutoriallevel-1..4` up to the current encounter and `level-1` only after the slow start; this is
  exactly decision 9.1's toggle, no engine change.
- Feature containers: `CharacterFeature`, `CharacterFeatureChoice`, `CharacterSubclassChoice`,
  `CharacterFeatureList` (`Class.lua:37-55`), `CharacterFeatChoice` (`DMHub Game Rules/Feat.lua:309`),
  `CharacterSkillChoice` (`Draw Steel Core Rules/DSSkillChoice.lua:10`), registered choices
  (`CharacterChoice.RegisterChoice`, `Draw Steel UI/DSClassEditor.lua:5`).
- Today's editor: `Draw Steel UI/DSClassEditor.lua` (2,190 lines; valid feature types at 10-18;
  prefabs at 1097-1160; upload debounce at 1185-1205; `ForceDomains` on every change at 1312, 1406).
- Character Increase pattern in content: `CharacterFeatureList` with a hidden attribute feature and a
  `CharacterFeatureChoice` (for example `classes/conduit.yaml`, data).
- Hero builder consumers: `Draw Steel Character Builder/FeatureCache.lua` (type order 30-50, filters
  684-686, validators 820-860, categoriser 1250-1340).

**New:** `ClassModel`, lanes with drag between levels, the slow-start toggle with moves and Undo,
features as containers, the storage chooser (modifiers only -> `CharacterFeature`; one choice ->
that choice; mixed -> `CharacterFeatureList` with a hidden modifier feature), choice blocks, Basics
header blocks (characteristics and arrays, `hitpointsCalculation` as two numbers, recoveries), and
the class open/save round trip.

**Lua-only.** Size **L, 6-9 pw** (excluding the ability editor, modifier sentences and templates).

**Risks:**
- `CharacterFeature:ForceDomains` overwrites `domains` on every feature
  (`DMHub Game Rules/CharacterFeature.lua:221-226`). It is idempotent for content that already has
  `class:<id>` domains, but must be proven by the corpus test, or run only on changed features.
- Two-record writes (resource gain, Characteristic Increase) must go in one
  `dmhub.SetAndUploadTableItem` of the whole class (`Definitions/dmhub.lua:670-675`), which today's
  editor already does.
- Imported features are replaced on re-import unless `importOverride` is set (proposal section 7).

### (g) Heroic resource gain = checklist line + linked trigger

**Exists today:** the class's `heroicResourceChecklist` (plain tables `{guid, name, details,
quantity, mode}`; editor `Class:HeroicResourceEditor`, `Draw Steel Core Rules/MCDMClass.lua:145-160`);
the character reads it in `character:GetHeroicResourceChecklist` (51-80); the Replenish behaviour
links by `checklistid` and uses it to stop double gains per encounter/round
(`DMHub Game Rules/AbilityReplenish.lua:347-366, 661-676`; picker at 839 built by
`Class.GatherHeroicResourceCheckListItems`, `MCDMClass.lua:86-120`). Quantities may be
`GoblinScriptTable` (evaluated at `Draw Steel Core Rules/MCDMCharacterPanel.lua:6466, 6487`).

**New:** one sentence writes both records with a fresh guid, keeps them in sync, and on open pairs
them by `checklistid` (and shows both when they disagree, decision 9.2). The prototype already does
this (`app.js:546-560`).

**Lua-only.** Size **S, 1-2 pw.** No engine change needed. Risk: content where the trigger lives in a
subclass but the checklist line on the class; pairing must search both.

### (h) Status and validation panel

**Exists today:** the ability editor's diagnostics strip (`AbilityEditor.lua:4897-5192`),
`DiagnoseTierText` (`MCDMAbilityBehavior.lua:3767`), feature `implementation` status, `CloudError`
for unknown skills in `proficiency` (`ModifierProficiency.lua:47-49`).

**New:** a rule list producing items with a jump-to and an optional fix: empty features, unnamed
features, empty Only if, unfinished abilities, ability choices with too few options, missing values,
Skills blocks that give nothing, text that no longer matches its blocks (needs a stored "basis" for
typed text, same idea as card overrides). Size **S-M, 2-3 pw.** Lua-only.

### (i) User-made ready-made templates

**Exists today, and fits:** the `featurePrefabs` table (`CharacterFeaturePrefabs`,
`DMHub Game Rules/FeaturePrefab.lua:10-80`; 5 records in data: Characteristic Increase, Choice of a
Language, Domain Features, Heroic Resource, Kit). The class editor already copies a prefab into a
class (`DSClassEditor.lua:1153-1160`, `clone.prefab = id`), which is the "dragging one in copies it"
rule. There is also a live-reference form `FeaturePrefabInstance` (`FeaturePrefabInstance.lua`)
that the new editor should not use for templates. `AbilityTemplate` (`abilityTemplates`) is the
equivalent for abilities.

**Recommendation:** store ready-made features in `featurePrefabs` (one prefab set per author or
table, each feature a template), adding optional shelf metadata (icon, group, short description,
default numbers). Do not invent a new table.
- **Who can make them:** compendium tables are edited by the Director; players see compendium
  sections according to `CompendiumPermission` (`DMHub Compendium/Compendium.lua:148-155, 350-375`)
  and the `permissions.playerlibrary` setting (`Compendium.lua:6733`). That matches "a table or
  organisation can extend".
- **Sharing beyond one game:** through module publishing, like other compendium content. I did not
  verify how modules carry `featurePrefabs` rows; treat as an open question.
- **Size S, 1-2 pw.** Lua-only.

**Risk:** the existing "Characteristic Increase" prefab says "to a maximum of 4" but its modifiers
are plain `add 1` with no limit (data, `featureprefabs/characteristic-increase.yaml`), so it does not
enforce the maximum. Fix with R2.

### (j) Undo/redo and draft persistence

**What DMHub offers:**
- `token:ModifyProperties` undo is for token properties, not compendium items.
- `dmhub.Undo()` / `dmhub.Redo()` exist (`Definitions/dmhub.lua:1394`), but I found no compendium
  editor that records undo steps for table items; the codex's compendium editors have no undo.
- `dmhub.SetAndUploadTableItem` uploads the whole item (no diff, no history); `BeginTransaction` /
  `EndTransaction` group network writes (`dmhub.lua:2099-2102`).
- Per-user storage: `setting{}` with `storage = "account"` (26 uses) or `"preference"` (284 uses);
  shared documents (`mod:GetDocumentSnapshot`) are per game and visible to all clients.

**New:** an editor-local history (snapshot of the model per change, coalesced per word edit), Undo
and Redo buttons and shortcuts, toasts with Undo after deletes. Drafts: the edited copy is a draft
until Save; keep unsaved drafts in an `account` setting keyed by record id (size unknown; see E3).
Size **M, 2-3 pw.** Lua-only.

**Risk:** drafts of large classes may exceed setting size limits (not documented in the stubs).

### (k) Embedding the ability editor in the class builder

**Exists:** the editor is already hosted in a dialog by `ShowEditActivatedAbilityDialog` and takes
options (`ActivatedAbilityEditor.lua:3938-4235`); `GenerateEditor(ability, opts)` has an `embedded`
mode (`AbilityEditor.lua:5339-5345`).

**New:** a transactional pop-up: edit a `DeepCopy`, write back only on Done, Escape = Cancel, pass
class context (resource name `Class.heroicResourceName`, `MCDMClass.lua:31`; ability category
names; keyword list). Size **S, 1-1.5 pw.** Lua-only.

### (l) Tests and round-trip gates on all content

**Exists:** standalone Lua tests with stubbed engine globals (`tests/`, 41 files, run with the
bundled `lua.exe`); LuaLS type check in CI (`TYPING.md`); the prototype corpus scripts
(`ui-mockup/ability-blocks-corpus/`) and the MCP bridge to a running app (`ClaudeBridge/`, `/test-ability`).

**New:**
- An in-app round-trip command: for every row of `classes`, `subclasses`, `kits`, `feats`,
  `standardAbilities`, careers, ancestries, titles and every bestiary monster, open in the models,
  save, `DeepEqual` against the original, and report per type. This must run inside DMHub because
  game types, `RegisterGameType` metatables and `Deserialize` hooks only exist there.
- A pinned baseline (what fails today and why) so regressions are visible.
- Size **M, 3-5 pw** spread across phases.

**Risk:** CI cannot run it (no headless DMHub). Until E1/E4 exist this is a manual pre-release gate
run over MCP.

### Totals

| Component | pw (low-high) |
|---|---|
| (a) Block framework | 4-6 |
| (b) Ability editor | 16-21 |
| (c) Trigger editor | 6-9 |
| (d) GoblinScript blocks, fx, level steps | 6-8.5 |
| (e) Modifier sentences | 5-7 |
| (f) Class builder | 6-9 |
| (g) Resource gain linkage | 1-2 |
| (h) Status panel | 2-3 |
| (i) Templates | 1-2 |
| (j) Undo/redo, drafts | 2-3 |
| (k) Embedding | 1-1.5 |
| (l) Round-trip gates | 3-5 |
| Rules/data changes (Section 3) | 8-12 |
| **Total** | **61-89** |

(The phase table in Section 4 adds up to 60-85 pw; the difference is rounding and where the round-trip work is counted.)

Not included: content clean-up passes (Section 5 of the proposal), translation, documentation, and
design iteration after authors use the Lua version (budget another 10-20% if the designs change).

---

## 3. Recommended engine and data changes

None of these needs C#. "Engine" here means shared rules code in `DMHub Game Rules/` and
`Draw Steel Core Rules/`. Each keeps old records loading and working; the editor simply stops
producing the old shape for new content.

### R1. One skill record for fixed skills and a choice (Required)

**Problem.** "You have the Hide and Sneak skills; choose five more" is two mechanisms today:
- `proficiency` modifier, `subtype = "skill"`, `skills = {id = true}`
  (`DMHub Game Rules/ModifierProficiency.lua:18-38`): fixed skills, inside a `CharacterFeature`.
- `CharacterSkillChoice` (`Draw Steel Core Rules/DSSkillChoice.lua`): a builder choice with
  `categories` and `individualSkills` (used as **sets**, line 61 and 295-317, though annotated
  `string[]` at 5-6) and `numChoices`. When the player picks, it copies the importer's standard
  "Skill" feature per skill, guid = the skill id, and stamps `sourceguid` = the choice
  (`GetSkillFeatures`, 162-203). So both paths end as `proficiency` modifiers.
- A third, 5e leftover: `CharacterSkillsChoice` (`DMHub Game Rules/Class.lua:1020-1110`, for duplicate
  proficiencies). Used by no content (0 in data).

In data: `CharacterSkillChoice` appears in 18 career, 11 class, 13 complication, 13 culture-aspect,
6 subclass, 6 title, 2 feat and 1 ancestry files; `proficiency` skill grants in 12 career, 15 class,
16 subclass, 5 complication and 3 title files. Mixed features need a `CharacterFeatureList` to hold
both. The prototype's single Skills block saves "a proficiency modifier, a skill choice, or both in a
feature list, as needed" (`app.js:208-232`).

**Who consumes them** (all must keep working):
- Builder: `FeatureCache.lua` (type order 44, filter 686, "already have it" validator 830-834,
  categoriser 1324, grant detection 1395-1420 and 2025-2045), `HeroBuilder.lua:1956-1960` (search lines),
  `HeroSkillsLanguages.lua` (grant pools keyed by `sourceguid` 505-530; hand-made rows 230-260, 1090-1110).
- Sheet: `Draw Steel V/SkillsDialog.lua` (86, 114-180, 785-817).
- Editors: `DSClassEditor.lua:17`, `CharacterSkillChoice:CreateEditor` (243-330).

**Proposal.** Extend `CharacterSkillChoice` rather than add a new type, because every consumer
already knows it:
- New optional field `grantedSkills` (set of skill ids). `FillFeaturesRecursive` and `FillChoice`
  always add one generated feature holding a `proficiency` modifier for those skills, with
  `sourceguid = self.guid` and a guid derived from the choice (not the skill id, to avoid the
  shared-guid collision between choices that `GetSkillFeatures` has today).
- Allow `numChoices = 0`: the record then only grants. The builder must not show it as a pending
  choice (`SuppressStatus`/`OfferFilter` hooks already exist in `FeatureCache.lua:675-700`).
- `GetDescription` writes the combined sentence ("You have the Hide and Sneak skills. In addition,
  choose five...").
- `HeroSkillsLanguages` shows granted skills as "has" rows of the same source; `SkillsDialog`
  reports them with the choice.
- Fix the annotations to `table<string, boolean>`.
- The same shape suits languages (`CharacterLanguageChoice`, `DSLanguageChoice.lua`); do it later if
  wanted.

**Backward compatibility.** Old `proficiency` features and old `CharacterSkillChoice` records load
and behave as today (no field = no grant). The editor opens a feature that is "fixed skills
modifier + skill choice" (or a `CharacterFeatureList` of exactly those) as one Skills block; untouched
it saves as it was; edited, it saves as one extended `CharacterSkillChoice`. A migration is optional.
`CharacterSkillsChoice` stays untouched.

**Effort:** 2-3 pw including builder and sheet checks (the builder's duplicate-skill handling is the
risky part).

### R2. "Increases by 1, to a maximum of N": honour `cap` (Required, live bug)

**Verified.** `AttributeType:ApplyOperation` only knows add/max/min/set
(`DMHub Game Rules/CustomAttribute.lua:343-355`), and the attribute modifier calls it without any
limit (`CharacterModifier.lua:620-646`). No Lua in the codex reads a `cap` field. In content, 16
attribute modifiers carry `cap`; 8 are paired with a separate `min N` modifier that does the real
capping (for example in the Conduit, Elementalist and Shadow records; the proposal's note that `min 5` "is a no-op"
is not right: applied after the add, it is the cap). **The other 8 have `cap` and nothing else:**
Conduit and Elementalist "to a maximum of 3" options (Agility, Might, Presence, Reason; Agility,
Intuition, Might, Presence), so today a 3 can become a 4. The `featurePrefabs` "Characteristic
Increase" ("to a maximum of 4") has no limit at all. The class-builder prototype also writes only
`cap` (`app.js:240`), so it would create the same bug.
(The attribute path is Lua; I could not see C#, but nothing suggests the engine reads `cap`.)

**Proposal.** In `TypeInfo.attribute.modify`, when `cap` is set, clamp the result:
`min(ApplyOperation(...), cap)`, never lowering a value that was already above the cap before this
modifier. Show it in `autoDescribe` and `describe`.

**Backward compatibility.** Records with `cap` and a `min` pair give the same result. The 8 records
with only `cap` start enforcing what their text says (a rules fix; tell content owners). The editor
writes `add 1, cap N` for "by 1, to a maximum of N", `max N` for "increases to N", `set N` for "is N",
and opens the old `add + min` pair as the same sentence.

**Effort:** 0.5-1 pw plus a content check.

### R3. Perk groups on `CharacterFeatChoice` (Required)

**Verified.** Matching splits the choice's `tag` on commas and compares each, trimmed and
lower-cased, for exact equality with the perk's tags (`DMHub Game Rules/Feat.lua:315-335, 353-385`).
A tag of exactly `feat` (or empty) offers every perk (458-465). In data, perk tags are inconsistent:
"Exploration Perks", "Lore Perks", "Supernatural Perks" (plural) but "Interpersonal Perk", "Crafting
Perk", "intrigue perk" (singular). Class and career choices use the matching spellings
("exploration perks", "interpersonal perk"...). The prototype writes `"feat," + "<group> perk"`
(`app.js:206`): "exploration perk", "lore perk" and "supernatural perk" would match **no** perk, and
the leading "feat" matches nothing either (no perk is tagged "feat"), so those choices would offer
nothing.

**Proposal.** Either (a) a structured `perkGroups` set on `CharacterFeatChoice` and a `perkGroup`
field on `CharacterFeat`, falling back to tags when absent; or (b, smaller) normalise in `HasTag`:
compare with a trailing "s" removed. Recommend (b) now plus a data pass that normalises perk tags,
and have the editor read the group list from the perks' own tags rather than a hard-coded list.

**Backward compatibility.** (b) only widens matches that were meant to match. Existing `tag`
strings keep working.

**Effort:** 0.5-1 pw.

### R4. Change Ability by ability id (Required for decision 9.3)

**Verified.** `modifyability` matches with keywords and a `filterAbility` GoblinScript
(`ModifierModifyAbilities.lua:985-1035`); content matches by name formula (114 per the proposal). Every
class, subclass and kit ability in data has a `guid` (1,118 of 1,118, data), the guid is a declared
field (`ActivatedAbility.lua:76`, `GetGuid` 972-976), and temporary clones keep it
(`MakeTemporaryClone`, 414-422). But GoblinScript sees the ability's `name`, not its guid
(`ActivatedAbility.lua:7119`). Power roll triggers cannot evaluate `filterAbility` at all
(`ModifierModifyAbilities.lua:1150-1155`), so an id list would also make "Apply to Power Roll
Triggers" usable with a filter.

**Proposal.** An optional `abilityIds` set on `modifyability` (and `abilityimprovement`), checked in
`willModifyAbility`/`modifyAbility` before the formula; expose `Ability.ID` to GoblinScript for
formulas that need it.

**Backward compatibility.** No field = today's behaviour; both set = both must pass. The editor
opens `Ability.Name = "X"` that matches exactly one ability as that ability and saves the id only when
edited (decision 9.3).

**Risks:** abilities copied into several places keep the same guid (for example a choice option
DeepCopied); that is desirable for matching, but check standard abilities and item abilities, which
may lack a stable guid.

**Effort:** 1-1.5 pw.

### R5. Card wording overrides on the ability (`displayOverrides`) (Recommended)

**Verified.** Abilities already store some card lines: `flavor`, `description` (effect),
`rangeTextOverride` and `targetTextOverride` (`MCDMActivatedAbility.lua:3664, 3704`), and tier text
is authored text. What is missing is (1) a trigger line and effect wording for triggers, which only
`TriggeredAbilityDisplay` holds (`DSModifyTriggerDisplay.lua:26-34, 617`), matched to its trigger by
name (`FindLivePartner`, 322-345), and (2) a stored "basis" so the editor can tell when a reworded
line is stale. The prototype saves `displayOverrides` as text only (`ability-blocks-stack.html:1647-1653`),
which loses the basis on reload.

**Proposal.**
1. `displayOverrides = { [line] = { text, basis }, ["<line>.label"] = text }` on `ActivatedAbility`
   (inherited by `TriggeredAbility`) and on `powertabletrigger` modifiers; `Render` uses an override
   when present. Keep using the existing fields for flavor, distance, target and description.
2. One card renderer for triggers (trigger line from `RenderTriggerSentence`, overridable).
3. Interim step (cheap): give `TriggeredAbilityDisplay` a `triggerGuid` and prefer it over the
   name in `FindLivePartner`, so renames stop breaking links even before migration.
4. Migration: for each display with a same-named trigger on the same owner (271 of 345), copy wording
   that differs from the generated text into the trigger's overrides and remove the display; list
   the 74 without a partner for review.
5. Update the readers listed in (c).

**Backward compatibility.** `triggerdisplay` keeps loading and rendering; the editor stops creating
it. Migration is a separate, reviewable content change.

**Effort:** 3-5 pw (renderer and readers 2-3, migration and review 1-2).

### R6. Aura trigger "a creature ends its turn in the area" (Recommended)

**Verified.** Aura trigger conditions are `onenter`, `onfirstenterround`, `targetstartturnaura`,
`casterstartturnaura`, `casterendturnaura` (`DMHub Game Rules/Aura.lua:38-64`). Start of the
affected creature's turn is fired from `creature:BeginTurn` through `GetAurasAffecting` and
`EnterAura(..., fromBeginTurn)` (`Creature.lua:11138-11143, 13698-13720`); the end of a turn only
fires the caster's own auras (`CheckAuraExpiration("endturn")`, `Aura.lua:3033-3060`, called at
`Creature.lua:11453`). There is no "affected creature ends its turn". About 18 data files use "ends
their turn in/within" wording (webbing, streams, areas).

**Proposal.** Add `targetendturnaura`, dispatched from `creature:EndTurn` for each aura the
creature is inside (same filters as start of turn), with a test in the style of
`tests/aura_round_triggers_test.lua`.

**Backward compatibility.** Additive.

**Effort:** 0.5-1 pw.

### R7. Nested follow-ups get their direct parent's values (Recommended)

**Verified.** `ExtractAbilityParameters`, `DeepReplaceAbility` and `SetDefaultParameters` walk the
whole copied child, including follow-ups nested inside it (`AbilityInvokeAbility.lua:99-180`,
called at 1330-1355). The outermost Invoke step therefore fills every `<<name>>` at every depth, and
blanks names it does not set, before an inner step runs. This is the prototype's `NESTED_NOTE`
(`ability-blocks-stack.html:533`). Also: `ExtractAbilityParameters` prints a debug line for every
match (116).

**Proposal.** Stop the three walks at a nested Invoke behaviour's `customAbility`; remove the debug
print. Adjust the one known content case (`high-elf-zephyr`, Sweeping Blade) so its inner step
passes `targetid` (per the brief 4e).

**Backward compatibility.** Changes behaviour for nested parameters only; the corpus script should
list every nested `<<...>>` before and after. **Effort:** 0.5-1 pw.

### R8. Power roll modifier conditions as one "applies" phrase (no engine change)

**Verified** in `Draw Steel Core Rules/MCDModifyPowerRolls.lua`: the fields mean different things.
- `filterCondition`: is the modifier present at all (`PassesFilter`, checked at 830).
- `displayCondition`: is it shown in this roll's dialog (824-845; sees ability, target, caster, cast).
- `activationCondition`: `true` always ticked, `false` never auto-ticked (offered as opt-in only for
  paid, limited or own-ability options, 673-683), a string = ticked when true (751).
- `activationAfterRoll`: decided after the roll (644, 851-896). Editor dropdown: 1895-1930.

**Proposal.** Keep all fields. The sentence offers "always applies" (`activationCondition = true`),
"you choose when you roll" (`false`), "applies only if ..." (string `activationCondition`), "you can
choose after the roll" (`activationAfterRoll`). `displayCondition` and `filterCondition` open as an
"Only offered when..." sub-phrase and are kept as opened. Mapping only; part of (e).

### R9. Weakness as negative damage reduction (verified, no change)

`creature.DamageResistance` (`Creature.lua:3571-3700`) treats a negative `dr` on a "Damage
Reduction" entry as weakness, keeps it separate (`weaknessDr`) so immunity bypass never skips it,
and supports stacking. Content uses `-5` and `"-5"` (data). The prototype's `"-(formula)"` string is
consistent with formula `dr` values in content (`Might*2`, `Summoner.Reason`). No change needed.
Optional clean-up: remove the per-call debug print `RESISTANCE:: KEYWORDS` (`Creature.lua:3586`),
which runs on every damage resolution.

### Other items found that affect a clean editor

| Item | Evidence | Verdict |
|---|---|---|
| E1. Exact GoblinScript AST from the engine compiler | Lua parser is partial (`GoblinScriptProse.lua:10-18`); the compiler is C# | Optional (C#). Saves 1-2 pw and removes the "two parsers disagree" risk |
| E2. Drag a copy (shelf ghost) | `dragMove` moves the panel itself (`Definitions/Panel.lua:73`) | Optional (C#). Workable in Lua with a floating copy |
| E3. Undo history or versions for compendium items | No compendium undo in the codex; `SetAndUploadTableItem` uploads whole items | Optional (C#). The editor does its own history meanwhile |
| E4. Headless or batch round-trip runs | Game types only exist in the app; CI runs LuaLS only | Recommended (C# or MCP tooling). Makes the corpus gate a CI test |
| Choice summary for subclass prerequisites (`Deity.Domains has "X"`, 22) | proposal 3.1 item 6 | Editor reading only; no change |
| `ForceDomains` on every change | `DSClassEditor.lua:1312, 1406`; `CharacterFeature.lua:221-226` | Verify idempotent in phase 0; else run only on changed features |
| Content: `cap`-only attributes, perk tag spelling, text/modifier mismatches (a Conduit Characteristic Increase modifier whose text says Reason but sets Intuition, `classes/conduit.yaml` around 1000-1030) | data | Content pass alongside R2/R3 |

---

## 4. Phasing

Each phase ends with something authors can use, and with the round-trip gate green for what it
touches.

| Phase | What | Unlocks for authors | pw |
|---|---|---|---|
| **0. Foundations** | Round-trip command in the app; `GoblinScriptAst`; `AbilityModel`, `TriggerModel`, `ModifierModel` load/save without UI; R2, R3, R7 rules fixes; R5 step 3 (`triggerGuid`) | Nothing visible, except fixed characteristic caps and perk choices. Proves the editors cannot damage content | 10-14 |
| **1. Read as blocks** | Block framework (a) read mode; a "Blocks" view inside today's ability and trigger editors | Authors can read any ability as sentences and a card; finds bugs in content | 5-7 |
| **2. Simple ability editor** | Editable blocks for the common steps, Advanced blocks, tiers, potency, Only if, modes, follow-ups, fx, status, undo; launched from the existing edit dialog | Most class and monster abilities edited without GoblinScript | 14-18 |
| **3. Triggers** | Trigger header, storage switching, condition blocks; R5 overrides and trigger card; display migration; R6 | One editor for triggered abilities and power roll triggers; no separate display | 8-12 |
| **4. Modifier sentences** | (e) inside today's feature editor (each feature's modifier list shows as sentences), R4, R8 mapping | Kits, ancestries, titles, items and effects get readable rules without waiting for the class builder | 6-8 |
| **5. Class builder** | Lanes, features, choices, R1 skill record, resource gains, templates in `featurePrefabs`, embedded ability editor, class round trip | Build a class the way the book prints it | 11-16 |
| **6. Paste and polish** | Paste readers (abilities, Steel Compendium markdown, class pages via `DrawSteelRulesImporter`), "Save as pattern", drafts, content clean-up tools | Fast entry of new books and homebrew | 6-10 |

Phases 4 and 2/3 can run in parallel with two developers once phase 1 has the framework. Phase 5
needs phases 2-4.

---

## 5. Open questions for the engine team

1. **Round trips outside the app (E4).** Can a batch mode or MCP endpoint load every table row as
   game types, run a Lua function on it, and return a diff, so the corpus gate runs in CI?
2. **GoblinScript AST (E1).** Can the C# compiler expose its parse tree (or a canonical printer)
   to Lua? Is the grammar in `GoblinScript_Guide.md` complete, including spaced names and `where`?
3. **`cap` on attribute modifiers (R2).** Confirm nothing in C# reads `cap` (the Lua path ignores it),
   and agree that enforcing it for the 8 cap-only records is the intended rule.
4. **Ability guids (R4).** Are guids stable for standard abilities, item abilities and abilities
   copied by `Steal Ability`/kits? Any place that regenerates them on load?
5. **Compendium undo and history (E3).** Does `dmhub.Undo` cover `SetAndUploadTableItem` at all?
   Is there a per-item version history the editor could offer as "restore earlier version"?
6. **Setting size limits.** What is the size limit for an `account` setting value (drafts of a
   whole class with its abilities can be hundreds of KB)?
7. **Templates in modules.** Are `featurePrefabs` and `abilityTemplates` rows carried by module
   publishing, and can a table restrict who edits them separately from other compendium content?
8. **`triggerdisplay` retirement (R5).** Are there consumers outside this repository (DMHub client,
   other mods, Forge Steel import) that read `triggerdisplay` records?
9. **Drag copy (E2).** Is a "drag a proxy panel" option cheap in the panel system, or should the
   editor keep its Lua workaround?
10. **Performance budget.** Is there a recommended maximum panel count for an editor pane, and a
    profiler hook (`dmhub.ProfileMarker` is referenced in `GoblinScript.lua`) we should use in the
    phase 1 gate?

### Things this study could not verify

- C# behaviour behind `dmhub.EvalGoblinScriptDeterministic` for `GoblinScriptTable` values, the
  serialiser's handling of numbers vs numeric strings, and `dmhub.Undo` scope.
- Whether module publishing carries `featurePrefabs`.
- Exact panel-count performance in the `gui` framework for deep stacks (needs a measurement in the
  app).
- Calendar estimates assume the designs in the two briefs are settled; the briefs still list open
  questions (proposal section 8, brief section 9).
