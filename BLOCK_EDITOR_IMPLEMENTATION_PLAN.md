# Block editor: implementation plan (UI module)

Status: draft for review, 2026-11-25. Builds on [`BLOCK_EDITOR_FRAMEWORK.md`](BLOCK_EDITOR_FRAMEWORK.md)
(decisions), [`BLOCK_EDITOR_CODING_PLAN.md`](BLOCK_EDITOR_CODING_PLAN.md) (registration and
infrastructure fit) and the class builder prototype (`ui-mockup/class-builder/`). Nothing here is
built yet.

The owner asked for the UI to be **a module set up the way the new/old hero builder was built**.
This plan copies that pattern, keeps what worked, and avoids the two things the older builder
hard-codes.

## 1. The pattern we are copying

`Draw Steel Character Builder/` holds two builders side by side:

| | Older: THC's Character Builder (`CharacterBuilder`, `CB*`) | Newer: `HeroBuilder` |
|---|---|---|
| Where it shows | The classic sheet's "Builder" tab (`CharSheet.RegisterTab{ id = "Builder", lazy = true }`, MainPanel.lua:831) | The Hero sheet window's Builder (HeroSheet.lua:278) |
| Who gets it | Everything the new one doesn't route to (monsters with builder choices, heroes without a documents layer) | Heroes, unless a custom interface owns the sheet (`HeroSheet.Routes`, HeroSheet.lua:94) |
| How the app chooses | **Routing, not a setting.** No feature flag; the new one claims the records it handles and the old one keeps the rest | |
| Structure | One controller panel holding a state object; `refreshBuilderState` fired down the tree; steps registered with `CharacterBuilder.RegisterSelector{ id, ord, selector, detail }` (CharacterBuilder.lua:176); detail panels built lazily, hidden ones stop the refresh | Steps from a rules table (`Build.STEPS`); every write through a **host interface** (`HeroBuilderHost`: token, canWrite, save, changed, block...) so it runs in the sheet or the EotW town; one `ModifyProperties` per pick, its own Undo; text in `HeroBuilderText.lua` (`UIText`) checked by `tests/uitext_check.lua` |

What we take:
- **A separate module** beside the editors it replaces, and **routing** that sends a record to the
  new editor when it can show it, and to today's editor otherwise. The old editor is never removed,
  only routed around (it is also the "Advanced editor" behind a grey block).
- **THC's controller and state object** (one state, one refresh event down the tree, lazy panels,
  hidden panels halt), and **its registry** (`RegisterSelector` becomes `RegisterHost`).
- **HeroBuilder's host interface** for everything that touches data, its undo-per-change, and its
  `UIText` file with the text checker.

What we avoid (both are THC-builder habits the newer builder dropped):
- A hard-coded step enum plus per-step handlers in the controller (`SELECTOR`, `selectX`,
  `applyCurrentX`, MainPanel.lua:770). In the block editor the controller knows **no** block,
  modifier, behaviour or choice id; a CI grep enforces it (coding plan section 4).
- Writing straight to records without one save path. Every change goes through the host's `save`.

## 2. The module, organised like THC's builder

A new mod, **`Block Editor/`** (decided: framework ledger), loaded after Draw Steel Core Rules and
Draw Steel UI. It follows the file organisation of `Draw Steel Character Builder/`:

**THC's conventions, kept exactly:**
- **One core file** (`CharacterBuilder.lua` there, `BlockEditor.lua` here): the global, a long
  design-doc comment at the top (overall design, events, state, helpers, optimisation notes, as
  CharacterBuilder.lua:1-76), constants and enums, the shared `_helpers`, and the registry.
- **Every other file defines one prefixed global** with `RegisterGameType` and a `@class`
  annotation, under a short `--[[ purpose ]]` header. THC uses `CB` (`CBAncestryDetail`,
  `CBSelectors`, `CBStyles`); we use **`BE`** (`BEShelf`, `BEFeatureDetail`, `BEStyles`).
- **Helpers are aliased as locals** at the top of each file that uses them
  (`local _fireControllerEvent = BlockEditor._fireControllerEvent`), never re-implemented.
- **Public entry points** are `X.CreatePanel()` (UI) or `X.CreateNew(...)` (objects); private
  functions start with `_` (`BEFeatureDetail._navPanel`).
- **Split by role**: the controller, state, one `*Detail.lua` per area of the editor, shared widget
  files, a right-hand panel, styles. Registration lives in its own file, loaded after what it
  registers (as Selectors.lua is loaded after the `*Detail.lua` files).

**The files** (left: THC's file it mirrors):

| THC builder | Block editor | Global | Role |
|---|---|---|---|
| `CharacterBuilder.lua` | `BlockEditor.lua` | `BlockEditor` | Design doc, constants (`BlockEditor.AREA` enum like `SELECTOR`), shared `_helpers` (`_fireControllerEvent`, `_getController`, `_getState`, `_getHost`, `_getRecord`, `_confirmDialog`), `RegisterHost` / `RegisterArea` registries |
| `State.lua` | `State.lua` | `BlockEditorState` | Dotted-key store (`record`, `view`, `area.active`, `feature.openId`, `drag`, `issues`); `CreateNew`, `Get`, `Set` (a copy of CharacterBuilderState, renamed) |
| `MainPanel.lua` | `MainPanel.lua` | (on `BlockEditor`) | The controller panel: columns, state, controller events (`openFeature`, `addBlock`, `moveBlock`, `combine`, `showView`, `save`), fires `refreshEditorState`; the `Open` / `Routes` entry points |
| `Selectors.lua` | `Areas.lua` | `BEAreas` | The editor's areas in one place and their `RegisterArea{ id, ord, panel }` calls (class: Basics, Heroic resource, Levels; the subclass tabs). Loaded after the `*Detail.lua` files |
| `AncestryDetail.lua`, `ClassDetail.lua`... | `BasicsDetail.lua`, `ResourceDetail.lua`, `LevelsDetail.lua`, `FeatureDetail.lua`, `SubclassDetail.lua` | `BEBasicsDetail`... | One centre-column panel per area: the class's basics rows; how you gain the resource (gain blocks); the level lanes; an open feature (name, text, its stack); a subclass page |
| `FeatureSelector.lua` (generic choice UI) | `BlockPanel.lua` | `BEBlockPanel` | Generic block UI: any registered block draws through it (grip, sentence, slots, the ... menu, wrapper bodies). Its file-top comment lists what a block must declare, as FeatureSelector.lua:1-27 lists what a choice must implement |
| (part of FeatureSelector) | `Slots.lua` | `BESlots` | The slot widgets: Text, Number, Choice, Many, Formula (fx picker), Test (test picker), Ref (compendium search), Who, Blocks; `RegisterSlotType` |
| (new) | `Stack.lua` | `BEStack` | A list of blocks: rows, insert points, drop slots, combine brackets |
| `Selectors.lua` (left rail) | `Shelf.lua` | `BEShelf` | The shelf: groups, search, recipes, drag sources, built from the registry |
| `FeatureCache.lua` | `RecordCache.lua` | `BERecordCache` | The open record read into blocks, and written back (calls the rules-side reader and writer); keeps the kept-record marks |
| `SelectionStatus.lua` | `IssueStatus.lua` | `BEIssueStatus` | Things to finish / worth checking, per area and in total |
| `CharacterPanel.lua` (right column) | `StatusPanel.lua` | `BEStatusPanel` | The right column: status, book text preview, saved data |
| `Styles.lua` | `Styles.lua` | `BEStyles` | `BEStyles.SIZES`, `GetStyles()`; theme tokens only (no hard-coded colours, unlike CBStyles.COLORS); merged with `ThemeEngine.MergeStyles` and re-applied on theme change, as MainPanel.lua:55 / 820-825 |
| `HeroBuilderText.lua` | `BlockEditorText.lua` | (UIText) | Every string, `UIText.Define("BlockEditorText")`; added to `tests/uitext_check.lua` |
| (HeroBuilder's host) | `Hosts.lua` | `BEHosts` | The host interface and its `RegisterHost` calls: class (with subclass tabs), feature, title, perk; later ability |

**Load order** (registered in the mod's cloud file list in this order, as the builder's is):
`BlockEditor.lua` -> `State.lua` -> `BlockEditorText.lua` -> `Styles.lua` -> `RecordCache.lua` ->
`IssueStatus.lua` -> `Slots.lua` -> `BlockPanel.lua` -> `Stack.lua` -> `Shelf.lua` ->
`*Detail.lua` -> `Areas.lua` -> `StatusPanel.lua` -> `Hosts.lua` -> `MainPanel.lua`.

**Where THC's layout is not copied** (and why): the builder's step enum and per-step controller
handlers (`SELECTOR`, `selectX`, `applyCurrentX`, MainPanel.lua:770) know every step by name. Our
areas are registered the same way (`RegisterArea`), but the controller knows **no** block,
modifier, behaviour or choice id: those come only from the registry (CI grep, coding plan
section 4).

**Rules side** (outside the module, so it loads before `CharacterModifier.lua` and has no `gui`):

| File | Role | Built from (prototype) |
|---|---|---|
| `DMHub Utils/Block.lua` | `Block.Choice{}`, `Block.Formula{}`...; claims; the reader (record -> blocks: claims rule, engine defaults, condition matching); write-back (kept records, merge by claims, saved spellings) | `importer.js`, `mergeSrc`, `keptRecords` |
| Beside each type | `block = {...}` / `blocks = {...}` inside `CharacterModifier.TypeInfo.<id>`, on `ActivatedAbility.RegisterType`, on each registered choice | `SENT` entries in `app.js` |

## 3. How the app chooses (routing)

`BlockEditor.Routes(record, where)` returns true when a host is registered for that kind of record
and the record opens (it may still contain grey blocks). The existing editors call it first and
fall back to themselves, the way the sheet calls `HeroSheet.Routes`:

```lua
-- in today's class editor entry point (one line added)
if BlockEditor ~= nil and BlockEditor.Routes(classRecord, "compendium") then
    return BlockEditor.Open(classRecord, BlockEditor.CompendiumHost)
end
-- ... today's editor, unchanged
```

- Each host decides what it claims (`claims = function(record) ... end`), like HeroSheet.Routes
  refusing tokens a custom interface owns.
- **Rollout question for the owner:** the hero builder has no switch. While hosts are incomplete,
  do we want a temporary per-user setting ("Use the block editor", default off), or route only
  the hosts that are finished? Recommendation: route finished hosts only, plus a developer
  setting to force either editor for comparison; drop the setting once a host ships.

## 4. The host interface

Modelled on `HeroBuilderHost` (HeroBuilder.lua:72-101). The editor never writes data itself.

```lua
--- @class BlockEditorHost
--- @field record fun(): table                 the record being edited (class, feature, title...)
--- @field canWrite fun(): boolean
--- @field save fun(args: {description: string, execute: fun(record: table)}): boolean  one change, one undo step
--- @field changed fun()                       after a save: what shows the record repaints
--- @field undo fun(): boolean                 the editor's Undo button
--- @field stacks table[]                      where blocks go: { field, families, layer = "feature" | "modifiers" }
--- @field header table[]                      fixed rows (name, basics, heroic resource...)
```

- **Compendium host** (classes, subclasses, titles, perks): `save` edits a copy and calls
  `dmhub.SetAndUploadObject(tableName, id, record)`; undo keeps the editor's own snapshot stack (as
  the prototype does), since table rows are not token properties.
- **Token host** (a monster's or hero's own features, later): `save` wraps `token:ModifyProperties`.
- **Character sheet host**: edits directly, as the sheet manages uploads (CLAUDE.md).
- The class host owns the subclass tabs: each subclass is its own record in `subclasses` with
  `primaryClassId`, saved through the same `save`.

## 5. Controller and state

As THC's builder (CharacterBuilder.lua:23-60), with the editor's own names:

- `BlockEditor.Open(record, host)` builds the controller with `data = { state, host }`.
- Any change: a controller event -> `host.save{...}` -> `state:Set` -> `FireEventTree("refreshEditorState", state)`.
- Panels that are hidden (a closed feature, another tab) return early and halt the event.
- Big panels (a level lane's open feature, the shelf, the ability editor) are built on first use.
- Performance (decided): only the block that changed redraws; the refresh passes the changed path
  so other blocks halt.

## 6. Registration surface

Unchanged from the coding plan; repeated here as the module's API.

```lua
BlockEditor.RegisterHost{
    id = "class", ord = 10, tableName = "classes",
    claims = function(record) return record.isSubclass ~= true end,
    header = { "name", "details", "characteristics", "stamina", "recoveries", "kits", "heroicResource" },
    stacks = { { field = "levels", layer = "feature", families = { "modifier", "choice", "logic", "recipe" } } },
    tabs = "subclasses",
}
```

Blocks are declared beside their types (`TypeInfo.<id>.block = {...}`); the editor builds the shelf,
the sentences, the slots, read-back and saving from those declarations. Combine rules, roll-option
lines, wrappers (aura, companion, summoner) and choices are declared the same way. The prototype's
`SENT` table and `importer.js` are the worked reference for every block (about 45 types, 1,153 core
records read back, 0 differences on a forced rebuild).

## 7. Build order

| Phase | What | Done when |
|---|---|---|
| 0 | Module skeleton: `BlockEditor.lua`, `State.lua`, `MainPanel.lua`, `Styles.lua`, `BlockEditorText.lua`; register the mod in the cloud after Draw Steel UI; `DMHub Utils/Block.lua` with slot types and claims; choice registry moved to `Class.lua` (decided) | The empty editor opens from a developer command; type check clean |
| 1 | One host (Feature) and one modifier block end to end (coding plan's thin slice: `conditionimmunity`, then `attribute`), grey blocks for everything else | Open a saved feature -> save unchanged -> identical record; edit one value -> only that field changes |
| 2 | Shelf, stack, drag and drop zones, Status, Logic wrapper, test picker, fx picker | The prototype's interaction tests pass against the Lua editor |
| 3 | Roll blocks with combine, gains, growing table, wrappers, option choices | The prototype's readers ported; every core class opens with the counts in section 31 of the proposal |
| 4 | Class host with subclass tabs, routed from today's class editor | All 11 classes and 45 subclasses round-trip unchanged in the app |
| 5 | Title and Perk hosts | Same round trip for their tables |
| 6 | Ability steps (the ability editor as a host) | The ability editor's 1,148-ability round trip in the app |

Each phase keeps today's editor routed for everything not finished.

## 8. Testing

- **Round trip per table** (the prototype's proof, run in the app over MCP): open every record,
  save unchanged, compare; then force every block to rebuild and compare.
- **Interaction tests** from the prototype (`scratchpad/cb*.js`) become UI-harness scripts.
- **Text:** `tests/uitext_check.lua` covers `BlockEditorText.lua`.
- **Type check:** zero problems (TYPING.md); `@class BlockEditorHost`, `@class BlockDecl`.
- **CI grep:** no type ids in `Block Editor/*.lua`.

## 9. Decisions needed from the owner

1. **Rollout switch:** route finished hosts only (recommended), or a per-user "Use the block editor" setting?
2. **First host:** Feature (smallest, proves the slice) then Class (recommended), or Class first?
3. **Compendium undo:** an editor-owned undo stack (recommended, as the prototype), or wait for an engine undo for table rows?
4. **Who builds what:** the rules side (`Block.lua`, declarations beside types) and the UI module can proceed in parallel once phase 0 lands.
