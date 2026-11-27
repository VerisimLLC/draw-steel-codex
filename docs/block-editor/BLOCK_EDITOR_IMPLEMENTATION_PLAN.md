# Block editor: implementation plan (UI module)

Status: draft for building, updated 2026-11-26 to match the decision ledger in
[`BLOCK_EDITOR_FRAMEWORK.md`](BLOCK_EDITOR_FRAMEWORK.md), which is **authoritative**: where this
plan and the ledger differ, the ledger wins. [`BLOCK_EDITOR_CODING_PLAN.md`](BLOCK_EDITOR_CODING_PLAN.md)
is kept for its infrastructure research and is historical where it differs. The worked reference
is the prototypes (`ui-mockup/class-builder/`, `ui-mockup/ability-blocks-stack.html`) and their
tests (`ui-mockup/tests/`). Nothing here is built yet.

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
  only routed around. It is called the **Advanced editor** everywhere (decided 2026-11-26).
- **THC's controller and state object** (one state, one refresh event down the tree, lazy panels,
  hidden panels halt). Not its registry: THC's `RegisterSelector` calls all sit in its own
  `Selectors.lua`, so adding a step means editing the builder. Ours live on the rules side (below).
- **HeroBuilder's host interface** for everything that touches data, its undo-per-change, and its
  `UIText` file with the text checker.

What we avoid (both are THC-builder habits the newer builder dropped):
- A hard-coded step enum plus per-step handlers in the controller (`SELECTOR`,
  CharacterBuilder.lua:93; `selectX` / `applyCurrentX`, MainPanel.lua:69-105). In the block editor the controller knows **no** block,
  modifier, behaviour or choice id; a CI grep enforces it (coding plan section 4).
- Writing straight to records without one save path. Every change goes through the host's `save`.

## 2. Where things live (decided 2026-11-26)

**Every registry is data, on the `Block` global in `DMHub Utils/Block.lua`** (no `gui`, loads
before `CharacterModifier.lua`). Declarations sit **beside the game types they describe**, in the
rules files. The UI module only **reads** the registries. Adding a block, a choice, a gain event,
a stat, a test, a colour group or a whole host is one registration in a rules file and no edit to
any `Block Editor/` file.

| Registry (on `Block`) | Declared where | What it gives the editor |
|---|---|---|
| `block = {...}` / `blocks = {...}` in `CharacterModifier.TypeInfo.<id>` (ledger D1 corrected) | beside each modifier type | a block: slots, sentence, claims, read/write, `supportsFilter`, `combine` |
| `block` on `ActivatedAbility.RegisterType` | beside each behaviour | an ability step |
| `block`, `category`, `order`, `create(ctx)` on `CharacterChoice.RegisterChoice` (moved to `DMHub Game Rules/Class.lua`) | beside each choice | a choice block; the builders read category and order from here too |
| `Block.RegisterTrigger{ id, words, ... }` alongside `TriggeredAbility.RegisterTrigger` | beside each trigger | trigger wording; its typed `symbols` drive "About this event" |
| `Block.RegisterGainEvent{ id, trigger, base, you, other, words, menu, order }` | beside the trigger it saves as | a way to gain a heroic resource (section 11) |
| `Block.RegisterStat{ id, words, kind }` | beside the attribute | the stat in every stat menu and formula |
| `Block.RegisterTest{ id, toScript, fromAst, prose }` | beside what it tests | a test in the test picker, read back by syntax tree (not regex) |
| `Block.RegisterGroup{ id, text, color, glyph, order }` | `DMHub Utils/Block.lua` (the shared groups) | the group's fixed colour and glyph (section 13) |
| `Block.RegisterWrapper{...}`, `Block.RegisterRecipe{...}` | beside the type they wrap / anywhere | Only if, aura, companion...; ready-made features |
| `Block.RegisterHost{ id, tableName, claims, header, sections, related }` | beside the record type (Class.lua, Feat.lua, Titles.lua...) | an editor for that record (section 6) |

Rules for every registry: **keyed by id, and registering an id again replaces it** (hot reload
is safe); the editor **gathers registrations when it opens**, not at load, so types registered by
later mods (Draw Steel Core Rules, Beastheart...) are included. The UI module's only registration
point is `BlockEditor.RegisterSlotWidget{ kind, create }`, for a new kind of slot control.

## 2a. The module, organised like THC's builder

A new mod, **`Block Editor/`**, loaded after Draw Steel UI and Draw Steel Ability Editor (it embeds
the triggered ability editor). It follows the file organisation of `Draw Steel Character Builder/`:

- **One core file** (`BlockEditor.lua`): the global, a design-doc comment at the top (as
  CharacterBuilder.lua:1-76), constants, the shared `_helpers`.
- **Every other file defines one prefixed global, `BE`** (`BEShelf`, `BEStack`, `BEStyles`), under a
  short `--[[ purpose ]]` header. These are plain tables with `@class` annotations, not
  `RegisterGameType` (nothing in the UI is saved).
- **Helpers are aliased as locals** where used; **entry points** are `X.CreatePanel()`; private
  functions start with `_`.

| THC builder | Block editor | Global | Role |
|---|---|---|---|
| `CharacterBuilder.lua` | `BlockEditor.lua` | `BlockEditor` | Design doc, constants, `_helpers` (`_fireControllerEvent`, `_getState`, `_getHost`), `RegisterSlotWidget` |
| `State.lua` | `State.lua` | `BEState` | The editing model and the undo/redo stack (section 12) |
| `MainPanel.lua` | `MainPanel.lua` | (on `BlockEditor`) | The controller panel: columns, events, `refreshEditorState`; `Open` / `Routes` |
| (none: generic) | `Page.lua` | `BEPage` | Builds a host's page from its declaration: header rows (as slots), sections, the section strip and related-record pills |
| `FeatureSelector.lua` | `BlockPanel.lua` | `BEBlockPanel` | Any registered block: grip, sentence label with link words, glyph, menu, wrapper bodies |
| (part of FeatureSelector) | `Slots.lua` | `BESlots` | Slot widgets: text, number, choice, many, formula (amount picker), test (test picker), ref, who, blocks |
| (new) | `Stack.lua` | `BEStack` | A list of blocks: drop slots, combine bracket |
| `Selectors.lua` (left rail) | `Shelf.lua` | `BEShelf` | The shelf from the registry: groups, search, recipes, drag sources |
| `FeatureCache.lua` | `RecordCache.lua` | `BERecordCache` | Opens a record into blocks and writes it back through `Block.lua` |
| `SelectionStatus.lua` | `IssueStatus.lua` | `BEIssueStatus` | The checks |
| `CharacterPanel.lua` | `SidePanel.lua` | `BESidePanel` | The right column: checks, book-style card / saved data |
| `Styles.lua` | `Styles.lua` | `BEStyles` | Sizes and chrome styles from theme tokens; block styles from `Block` groups (section 13) |
| `HeroBuilderText.lua` | `BlockEditorText.lua` | (UIText) | Every string (ASCII only), checked by `tests/uitext_check.lua` |

There are **no host-specific UI files** (no class, basics, levels or subclass panels): a host's
page is built from its declaration. A host that truly needs a bespoke panel names a function in
its declaration, defined beside the host (rules side may not use `gui`, so such a panel lives in a
UI mod that loads after `Block Editor/` and registers with `BlockEditor.RegisterSlotWidget`).

**Load order:** `BlockEditor.lua` -> `State.lua` -> `BlockEditorText.lua` -> `Styles.lua` ->
`RecordCache.lua` -> `IssueStatus.lua` -> `Slots.lua` -> `BlockPanel.lua` -> `Stack.lua` ->
`Shelf.lua` -> `Page.lua` -> `SidePanel.lua` -> `MainPanel.lua`.

## 3. How the app chooses (routing)

`BlockEditor.Routes(record, where)` returns true when a registered host claims the record. Today's
editors call it first and fall back to themselves, the way the sheet calls `HeroSheet.Routes`:

```lua
-- in today's class editor entry point (one line added)
if BlockEditor ~= nil and BlockEditor.Routes(classRecord, "compendium") then
    return BlockEditor.Open(classRecord)
end
-- ... today's editor, unchanged: the Advanced editor
```

Each host decides what it claims (`claims = function(record) ... end`). Today's editor stays as
the **Advanced editor**, reached from grey blocks and from the editor's menu. Whether unfinished
hosts are routed or held behind a setting is settled with phasing (section 7).

## 4. The host interface

Modelled on `HeroBuilderHost` (HeroBuilder.lua:72-101). The editor never writes data itself.

```lua
--- @class BlockEditorHost
--- @field record fun(): table          the record being edited (class, feature, title...)
--- @field canWrite fun(): boolean
--- @field upload fun(record: table)    sends one record to the server (section 12)
--- @field related nil|{tableName: string, field: string, label: string}   e.g. subclasses by primaryClassId
```

- **Compendium host** (classes, subclasses, titles, perks): `upload` calls
  `dmhub.SetAndUploadTableItem(tableName, record)` (Definitions/dmhub.lua:676). Undo is the
  editor's own (section 12): table rows are not token properties.
- **Token host** (a monster's or hero's own features, later): `upload` wraps `token:ModifyProperties`.
- **Character sheet host**: edits directly; the sheet manages uploads (CLAUDE.md).
- A class's subclasses are their own records in `subclasses` with `primaryClassId`, declared by
  the class host's `related` and shown as pills set apart from the class tab.

## 5. Controller and state

As THC's builder (CharacterBuilder.lua:23-60), with the editor's own names:

- `BlockEditor.Open(record)` finds the host, builds the controller with `data = { state, host }`.
- Any change: a controller event -> `BEState.Change(description, fn)` (section 12) ->
  `FireEventTree("refreshEditorState", state, changedPath)`.
- Panels that are hidden (another tab, a collapsed section) return early and halt the event; only
  the block on `changedPath` redraws (decided), found by a keyed lookup, not a tree walk.
- Big panels (a section's features, the shelf, the ability editor) are built on first use.
- Deferred work (uploads, drag auto-scroll) checks `mod.unloaded` first.

## 6. A host declaration

```lua
-- DMHub Game Rules/Class.lua, beside the Class type
Block.RegisterHost{
    id = "class", tableName = "classes",
    claims = function(record) return record.isSubclass ~= true end,
    header = { "name", "details", "characteristics", "stamina", "recoveries", "kits" },
    sections = {
        { id = "gains", label = "How you gain {resource}", stack = "gains", families = { "gain" } },
        { id = "slowstart", label = "Slow start", lanes = { "tutoriallevel-1", "tutoriallevel-2", "tutoriallevel-3", "tutoriallevel-4" }, layer = "feature", families = { "modifier", "choice", "logic", "recipe" }, optional = true },
        { id = "levels", lanes = "level-1..level-10", tabPerLane = true, layer = "feature", families = { "modifier", "choice", "logic", "recipe" } },
    },
    related = { tableName = "subclasses", field = "primaryClassId", label = "Subclasses" },
}
```

- **Sections** become the section strip: one tab per level, Slow start as one tab listing its four
  encounters (decided 2026-11-26).
- **Gain lines are blocks** of a `gain` family, declared beside Class: their event slot lists
  `Block.RegisterGainEvent` entries, and the block writes both the class's checklist line and its
  trigger (a "level 3" block that reads and writes the record itself, ledger D2).
- The prototype's `SENT` table and `importer.js` are the worked reference for every block (about
  45 types; every core class and subclass opens and saves back unchanged).

## 7. Build order (decided 2026-11-26)

The ability editor first, as a UI and then with working blocks; then the triggered editor in the
same order; then the class and subclass editor, which embeds both. The shared pieces (shelf,
stack, slots, pickers, card, checks, undo with uploads) are built with the ability editor and
reused after it.

| Phase | What | Done when |
|---|---|---|
| 0 | Module skeleton; `DMHub Utils/Block.lua` registries with **stub** block registrations; **proofs in the app**: a drag ghost via `transferDragTo` with pointer-based drop slots, one sentence label with many link words at 80-140% font size, fixed-colour blocks with hover/selected and glyphs, the book card fonts, panel counts for a large ability | The empty editor opens from a developer command; the proofs pass; type check clean |
| 1 | **Ability editor UI**: sections, stack, shelf, drop slots, amount and test pickers, the book-style card, checks, the Advanced editor link, undo/redo with uploads (section 12). Blocks come from the stub registrations, never written into the UI | It looks and behaves like the mockup; edits upload and undo; no real blocks needed |
| 2 | **Ability blocks**: real declarations beside each behaviour (replacing the stubs, no UI change); reader, writer and claims; one GoblinScript parser for tests and formulas | The 1,019 core abilities open and save back unchanged in the app |
| 3 | **Triggered editor**, UI then logic: the trigger card, "when", trigger conditions, Test Trigger, on the phase 1-2 pieces | Core triggered abilities round-trip |
| 4 | **Class and subclass editor**: the page from the host declaration, gain lines, level tabs, subclass pills, embedding the phase 2-3 editors | All 11 classes and 45 subclasses round-trip |
| later | Titles, perks, kits, items, monsters with the same stack | Each round-trips its table |

**Hosts and rollout.** Abilities mostly live inside other records (a feature's modifier, a
monster, an item), so the ability editor's host saves through the record that holds the ability;
the class builder later embeds it through that same host. Until abilities round-trip in the app
(end of phase 2), the new editor sits behind a developer setting; then it becomes the **Simple**
tab of the ability editor, with today's editor as the **Advanced** tab. The triggered and class
editors follow the same rule at the end of their phases.

## 8. Testing

- **Round trip per table** (run in the app over MCP): open every record, save unchanged, compare;
  then force every block to rebuild and compare. The prototype suite (`node ui-mockup/tests/run.js`)
  states the invariants the port must keep.
- **Modularity gate (G6):** a second developer adds a block by editing only that type's file, with
  no `Block Editor/` change. Run it in phase 1.
- **Plain-Lua tests of `Block.lua`** (claims, read/write, condition parsing), runnable without the app.
- **Interaction tests** from the prototype become UI-harness scripts.
- **Text:** `tests/uitext_check.lua` covers `BlockEditorText.lua`; rules-side block text is checked
  for ASCII by the same test.
- **Type check:** zero problems (TYPING.md); run the full check after typing `TypeInfo`, not `-Changed`.
- **CI grep:** no type ids in `Block Editor/*.lua`.

## 9. Decisions

Decided 2026-11-26 (ledger): registries on `Block`, declared beside the types; the ledger is
authoritative and the plans follow it; one contrast-checked palette with a group glyph, within what
Lua can draw (section 13); the old editor is the **Advanced editor**; undo and redo with server
uploads as in section 12; mouse-first, with a per-block word list for the keyboard and an engine
ask for focus on link words.

Phasing and rollout decided 2026-11-26 (section 7). Still open: who builds which side in parallel.

## 10. Web prototype features to carry into Lua (checked 2026-11-25)

The Lua mockups (`ui-mockup/lua-preview/`) draw one screen of each editor, so they leave out much
of what the web prototypes do. Nearly all of it is still the design and can be built with `gui`;
only the items in 10.1 change because of the toolkit. Each later row names where it is designed.

### 10.1 Changed by the Lua toolkit

| Web prototype | In Lua | Note |
|---|---|---|
| Typing in place: a line of the card, a block's text value, a label (e.g. "Strained") turns into a text box where it sits | A small `gui.Input` popup opened at the word (`element.popup`) | A sentence is one label with link regions, so nothing can sit inside the line. Feels nearly the same; needs the popup placed at the word, not the whole label (`popupPositioning = "mouse"`). |
| Keyboard: Tab to each clickable word, Enter opens its menu | **Decided (2026-11-26):** mouse-first; each block has a focusable "words in this block" list as the keyboard path; engine ask for focus on link words | Link regions inside a label have no focus of their own, and the engine has no keydown event. |
| Chips with an x inside a sentence (keywords, skill groups) | `gui.Multiselect` chips on their own row after the sentence, or "Melee x" as link text | Chips are panels, so they can't sit inside a label. |
| Drag ghost from the shelf | A small floating copy that takes over the drag (`element:transferDragTo(ghost)`, as DockablePanel.lua:1524) | The engine finds drop targets under the dragged panel, not the pointer, so a panel that stays put never reaches a slot. The drop slot is worked out from the pointer against cached block midpoints. |
| Combine bracket drawn as a curve | Three 1px panels and a button | Looks plainer; works the same. |
| Shape shows type (round values, pointed tests; first prototype) | Colour, and slots that only accept what fits (`canDragOnto`) | The stack editor had already dropped shapes for pickers. A 9-slice image with notches is possible if wanted. |
| Card in the Bitter font | The bundled `Book` font, tier marks in `DrawSteelGlyphs` | Book look kept (decided); face differs slightly. |
| Recipes and drafts kept in the browser | Need a home: a settings value per user, or a compendium table to share | Decide with the recipe shelf (CLASS_AND_MODIFIER_EDITOR_PROPOSAL.md). |

### 10.2 Ability editor: designed, not drawn in the mockup

| Feature | Designed in |
|---|---|
| Card: "+ Add paragraph", move paragraphs up/down, remove; reworded lines marked, flagged when the rules change ("Use new wording" / "Reset"); rename an effect label | ABILITY_BLOCKS_DESIGN.md 4j, 4q |
| Hover a dotted formula to see its GoblinScript (`hoverLink` + tooltip) | 4i |
| "Show GoblinScript" switch and the "Saved data" view | 4c, 4g |
| Open an existing ability; Paste text dialog with a sample; "Try to turn this into blocks"; "Keep as card text" | 4l, 4n, 4u, 4v |
| Scope line: "Open in Advanced editor" / "Keep editing here", and "Edit in Advanced editor" on grey blocks | 4s |
| Triggered ability: the trigger card, "+ when...", trigger conditions; Test Trigger | 4h, 4q, 4r; Test Trigger from TRIGGERED_ABILITY_EDITOR_DESIGN.md |
| Choose one when used (options), each option its own steps | 4n |
| Picking targets one at a time (`sequentialTargeting`), a row under Who it targets | 4ae |
| Requirements ("Can only be used when") with tests | 4y |
| Formula builder (fx) with the GoblinScript reference; the test picker with combining first | 4aa, 4ab, 4z |
| Remember a value; hand-offs to a follow-up; potency checks | 4w, 4ad, 4e, 4f |
| Quick fixes ("Fix: use your ...", "Fix: target's ...") | Prototype only (`ability-blocks-stack.html`); not yet written up |
| Shelf: click to add at the insertion cursor ("Drag, or click to add at When it's used"), "/" to search, the all-categories grid, faded blocks that don't fit here, hover text for every block | 4i (insertion cursor), 4x |
| Undo | Decision 9.3 |

### 10.3 Class builder: designed, not drawn in the mockup

| Feature | Designed in |
|---|---|
| Basics: stamina, primary characteristics, characteristic arrays as chips, kits, Recoveries | CLASS_AND_MODIFIER_EDITOR_PROPOSAL.md |
| Levels shown side by side with "Show levels" collapse; Move to... another level; Duplicate | Proposal |
| Feature text vs blocks: "The text is still right" / "Use the blocks' wording" | Proposal |
| Surges: keep or this roll only; "Save as recipe", "Share all", "Open pasted class" | Proposal 26-31 |
| Subclass tabs: "+ subclass", Delete subclass, the subclass's own lanes | Proposal |
| Grey advanced blocks, info cards, "Copy the engine record" | BLOCK_EDITOR_FRAMEWORK.md |
| Each gain's "saves as" line under Show GoblinScript | Proposal |
| Growing rows ("+ more from a level"), options with their own blocks ("+ add to this option") | Proposal |

## 11. Adding a way to gain a heroic resource (worked example: spending surges)

A developer adds a gain event with **one registration beside the rules**, and no edit to any
editor file. It assumes the registries live on `Block` in `DMHub Utils/Block.lua`
(BLOCK_EDITOR_REVIEW.md, B2).

**1. The game event.** The engine trigger, with its typed values, already exists or is added in
the rules (an engine change, so it is its own task). Spending surges is `useresource`
(`Draw Steel Core Rules/MCDMRules.lua`), which reports `resource` and `quantity`:

```lua
TriggeredAbility.RegisterTrigger{
    id = "useresource",
    text = "Use Resource",
    symbols = {
        resource = { name = "Resource", type = "string", desc = "The resource used." },
        quantity = { name = "Quantity", type = "number", desc = "The number of resources used." },
    },
}
```

**2. The gain event**, registered in the same file, right after it:

```lua
Block.RegisterGainEvent{
    id = "spendsurges",                 -- the editor's own id; saved data never sees it
    trigger = "useresource",            -- the engine trigger it saves as
    base = 'Resource = "Surges"',       -- joined to the line's test: Resource = "Surges" and (...)
    you = "spend surges",               -- "you spend surges"
    other = "spends surges",            -- "you or an ally spends surges"
    words = { Quantity = "number of surges spent" },   -- how a test on a value reads in the sentence
    menu = true,                        -- in the short menu; otherwise only under "Build the trigger yourself..."
    order = 80,                         -- position in the menu (by how often classes use it)
}
```

**3. What the editor does with it, with nothing else written:**
- The gain line's event menu lists "spend surges" (or not, with `menu = false`).
- The line's "Only if" picker starts with **About this event**: one entry per value the engine
  trigger reports, read from its `symbols`. A number becomes an ordinary comparison ("Quantity is
  at least [1]") whose value and comparison change in the block, and the value also appears in
  the block's stat menu. So there is no list of fixed amounts to write or keep in step.
- Saving writes the trigger (`useresource`), its condition (`base` joined to the line's test),
  the resource step linked to the class's checklist line, and the once-per-round/encounter limit.
- Opening a saved class reads a `useresource` trigger whose condition starts with `base` back
  as this event, with the rest as the line's test.
- Anything the short menu can't say is built with "Build the trigger yourself...", which opens
  the triggered ability editor seeded from the line.

**The amount picker** (formulas, both editors) is one list of the kinds of amount, each named
plainly with a real example in the block's own words, no group headings and no "[ ]" notation:
A number ("3"), A stat ("your Might, any characteristic, Level, Victories..."), A stat with math
("your Level plus 4 · your Might times 2"), More as you level ("1, then 2 from 5th level"),
Depends on a test ("2 if you are winded, otherwise 1"), A dice roll ("1d3"), then values the
trigger reports, then "Type a formula instead". A "Now:" line shows the current value, and a note
says the stat, sign and numbers are changed on the block after picking. Searching a stat's name
makes the stat rows use it ("might" + A stat with math = "your Might plus 1"), and their examples
change to that stat only ("agility": "your Agility", "your Agility plus 4 · your Agility times 2").

**Picker rule (both editors): one entry per kind of thing, never one per value.** A test or
formula that differs only in which stat, amount or dice it uses is one entry; the choice is made
in the block (a stat menu, a number box), where it is easy to change. Search still finds the
entry by every stat name it covers, and picking it after searching a stat's name uses that stat.
Nothing is chosen inside the picker itself: the block's word is the menu. Examples:
"A stat or attribute" (not one entry per stat; on the block it reads "your Might", and that word
lists the stats plus "A formula instead..."), "Your [level] is at least [ ]" (not one per number), one math entry whose sign is changed on the block
("your Level [plus] [4]", "your Might [times] [2]": each part a stat word or a number you type),
one dice entry, and one entry per value an event reports. Entries are only separate when they
are different tests ("You are winded", "There are at least [1] enemies within [1] squares").
Stats come from one list (`Block.RegisterStat`, or the trigger's own `symbols`), so a new stat
appears in every picker at once.

## 12. Undo, redo and saving to the server (decided 2026-11-26)

**How saving works today.** Compendium editors keep the record in memory, mark it changed, and
upload the whole record with `dmhub.SetAndUploadTableItem(tableName, record)`. The class editor
uploads 20 seconds after the first change, and again when the author switches record or closes
the editor (`DoUploadIfNeeded`, Draw Steel UI/DSClassEditor.lua:1186-1205, 1514-1525). Table edits
are not on DMHub's own undo (that is `token:ModifyProperties`, for token properties), so undo for
compendium records has to be the editor's.

**The rule: undo works on the editor's model; the server only ever receives whole records.**

1. **One step per action.** Every author action goes through `BEState.Change(description, fn)`:
   it copies the model of each record the action touches, runs `fn`, pushes one undo entry
   `{ description, before = { [recordId] = copy } }`, clears redo, and marks those records dirty.
   Typing in a text or number field is one step when it is committed (Enter or leaving the field),
   not one per keystroke. The model copies are the block model (small, plain tables), never panels.
2. **One stack for the editor, across tabs.** A class and each of its subclasses are separate
   records, and some actions touch two (adding a subclass changes the class page and creates a
   subclass record). So the editor keeps one undo stack and one redo stack; each entry lists the
   records it touched. Undoing an entry for a tab that isn't shown first switches to that tab and
   flashes the change, so nothing changes out of sight. Limit: 100 entries.
3. **Uploads follow the model, not the stack.** A dirty record is compiled (the claims writer) and
   uploaded:
   - 2 seconds after the last change to it (a short debounce, so a burst of clicks is one upload);
   - when the author switches tab or opens a different record;
   - when the editor closes (`destroy`), and on an explicit Save.
   The timer is a `think` handler that runs only while something is dirty (`thinkTime` set when a
   record turns dirty, cleared when all are clean), and checks `mod.unloaded` first.
4. **Undo and redo are ordinary changes to the server.** Undo restores the copied model, marks
   those records dirty, and the same upload path sends the earlier state. Nothing special is sent
   for an undo, so it works the same before and after an upload.
5. **Deleting is reversible.** Deleting a subclass (or any record) sets it hidden (soft delete, as
   `unhidden_pairs` expects) and uploads; undo clears the flag. Records are never obliterated from
   the editor.
6. **Other people's changes.** The editor watches its tables (`monitorAssets`, `refreshAssets`).
   When a record changes on the server: if it matches what this editor last uploaded (a hash of the
   record), it is our own echo and is ignored; if this editor has no unsaved change to it, the
   model is reloaded from the new record and that record's entries are dropped from the undo stack,
   with a toast ("Updated by someone else"); if it has unsaved changes, the editor keeps them and
   offers "Reload theirs / Keep mine" (ledger: last save wins).
7. **The ability editor inside the class builder** keeps its own stacks while it is open; **Done**
   commits one entry to the class editor's stack ("Edit Out of the Way!"), **Cancel** discards.
8. **What undo does not cover:** changes outside the editor, and history after the editor closes
   (it uploads anything pending, then the stacks are dropped, as in other DMHub editors).
9. **Controls:** Undo and Redo buttons in the title bar with the step's description as their
   tooltip, and the keys through the panel's `keybinds` (Definitions/Panel.lua:122) while the
   editor has focus. **Check in phase 0** that the bind strings for Ctrl+Z / Ctrl+Y (Ctrl+Shift+Z)
   exist and don't clash with map undo; if they do, keep the buttons and raise an engine ask.

Prototype reference: `change()` / `undo()` / `redo()` in `ui-mockup/class-builder/app.js` (one
step per action, separate stacks per class, kept in the browser).

## 13. Block colours and glyphs (decided 2026-11-26)

One table, keyed by meaning, used by both editors (`Block.RegisterGroup{ id, text, color, glyph }`,
read into `BEStyles.BlockColors`). Colours are literal hex (never theme tokens), each at least
5:1 under white text; every block and shelf row also shows the group's glyph, a Phosphor mask the
codex already ships, drawn white at 14px beside the grip
(`gui.Panel{ bgimage = "phosphor/<glyph>.png", bgcolor = "white", width = 14, height = 14 }`).
Styles: one local rule per group with the colour and a precomputed hover colour (an inline
`bgcolor` would beat the hover and selected rules); "selected" is a `boxShadow` ring.

| Group (meaning) | Colour | White text | Glyph (Phosphor) | Used for |
|---|---|---|---|---|
| Stats and movement | `#3c5fa8` | 6.2:1 | gauge / footprints-fill | change a stat, characteristics, speed; move a creature |
| Rolls and roll changes | `#7d4aa3` | 6.2:1 | dice-six | power roll, edges and banes, change the roll |
| Defences | `#2f6f6a` | 5.8:1 | shield | immunity, weakness, condition immunity |
| Abilities and areas | `#8b5434` | 6.2:1 | lightning / polygon | gain an ability, use a new ability, auras, summons |
| Skills, perks and languages | `#5d6a1c` | 5.9:1 | book-open | skills, perks, languages |
| Class and resources | `#8a6a20` | 5.0:1 | coin | resources, gains, kits, reminders |
| Logic | `#a8501d` | 5.5:1 | arrow-elbow-right-down-bold | Only if, choose one when used, remember |
| Choices | `#3d7a3a` | 5.2:1 | list-bullets | the player picks |
| Harm | `#a8343f` | 6.5:1 | sword | damage |
| Conditions | `#8e3f86` | 6.6:1 | lock-simple | apply a condition, forced movement |
| Effects | `#2b6f86` | 5.6:1 | sparkle | ongoing effects |
| Help | `#277057` | 5.9:1 | heart | heal, end effects, temporary Stamina |
| Tests and potency | `#2c7391` / `#4d6a8a` | 5.3 / 5.6:1 | magnifying-glass-bold / check-square | potency, test blocks |
| Numbers | `#357a4d` | 5.2:1 | plus-minus | value pieces |
| Growing tables | `#8f3a2e` | 7.5:1 | stack-plus | rows unlocked by resource and level |
| Your recipes | `#7a4f8f` | 6.3:1 | star | saved features |
| Display, scripts, unique | `#6b6258` / `#55524c` / `#6a5a3c` | 6.0 / 7.8 / 6.7:1 | eye / code / diamond | card text, scripts, one-offs |
| Advanced (grey) | `#5b564e` | 7.3:1 | gear-six-fill | records no block shows |
| Header lines | `#8c6a24` | 5.0:1 | (none) | fixed "what it is" lines |

A shelf block that can't go in the chosen list keeps its colour (the colour means its kind) and
shows a dashed outline; hovering says why.
