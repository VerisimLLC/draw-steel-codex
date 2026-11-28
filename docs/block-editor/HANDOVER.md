# Block Editor: handover (2026-11-27)

For the next Claude Code session, running on the owner's computer in the local draw-steel-codex
clone. The earlier work happened in a cloud session that could not reach this computer, so
nothing below has been run in DMHub yet.

## 1. What this is

A Scratch-like **block editor** for Draw Steel content in the codex: an ability editor, a
triggered ability editor, then a class and subclass editor. Content is shown as coloured sentence
blocks dragged from a shelf. Blocks are a **view over the engine's existing records**: nothing
new is stored, an unchanged record saves back byte-identical, and an edited block writes only the
fields it claims. Today's editors stay, renamed the **Advanced editor**.

## 2. Where things are

| What | Where |
|---|---|
| Phase 0 code | this branch, `New-Block-UI` (commit `173af947`) |
| **Decision ledger (authoritative)** | `docs/block-editor/BLOCK_EDITOR_FRAMEWORK.md`, the table at the end: newest row wins |
| Build plan | `docs/block-editor/BLOCK_EDITOR_IMPLEMENTATION_PLAN.md`: section 2 (where things live), 2a (files), 4-6 (host, state, host declaration), **7 (build order)**, 10 (prototype features to carry over), 11 (adding a gain event), **12 (undo, redo and saving)**, **13 (colours and glyphs)** |
| Review findings | `docs/block-editor/BLOCK_EDITOR_REVIEW.md` (section 0: fixed; section 2 "Lua UI": engine facts the build relies on) |
| Ability editor design | `docs/block-editor/ABILITY_BLOCKS_DESIGN.md` (dated sections 4a-4ae; its section 7 ledger) |
| "Only if" support per modifier type | `docs/block-editor/MODIFIER_FILTER_AUDIT.md` |
| Engine and content issues (flagged, not fixed) | `docs/block-editor/FOLLOW_UP_ITEMS.md` |
| Lua look and feel mockups | `docs/block-editor/lua-preview/index.html` (class builder) and `ability.html`; every element has a `data-lua` attribute naming the `gui` call that draws it. Published: https://claude.ai/artifact/98P1ebeAkfFzfPMtjq4h8r |
| Working HTML prototypes (the reference behaviour) and their tests | branch `claude/vibrant-mayer-tzljkn`: `ui-mockup/class-builder/`, `ui-mockup/ability-blocks-stack.html`, `ui-mockup/tests/` (`node ui-mockup/tests/run.js`, needs Playwright). Published: https://claude.ai/artifact/JSUrSiutk6DnavtMof2hU5. The class proposal (`CLASS_AND_MODIFIER_EDITOR_PROPOSAL.md`, needed for phase 4) is there too. |

The copied documents still link to `ui-mockup/...` paths; those files are on the design branch
(`git show claude/vibrant-mayer-tzljkn:ui-mockup/...` or check that branch out in a worktree).

## 3. Phase 0: what was built

| File | Holds |
|---|---|
| `DMHub Utils/Block.lua` | The `Block` global: every registry as data (groups, hosts, gain events, stats, tests, triggers, wrappers, recipes, blocks), keyed by id, re-registering replaces, gathered lazily (`Block.All`, `Block.Get`); `Block.RegisterSource` hook for blocks declared beside types (phase 2); the 24 colour groups with fixed colours and Phosphor glyphs |
| `DMHub Utils/BlockStubs.lua` | 9 stub blocks, 5 stats, 2 tests (`stub = true`) for the phase 1 UI |
| `Block Editor/BlockEditor.lua` | Design notes, constants, helpers, `RegisterSlotWidget` |
| `Block Editor/State.lua` | `BEState`: per-record models, `state:Change(description, fn, recordIds?)`, one undo/redo stack across records (100), dirty set, uploads 2 s after the last change through `host.upload` |
| `Block Editor/BlockEditorText.lua` | All strings (UIText) |
| `Block Editor/Styles.lua` | Chrome from theme tokens; one fixed-colour rule plus hover rule per group, selected ring; glyph helper |
| `Block Editor/MainPanel.lua` | `BlockEditor.Open(record)`: the empty editor; `/blockeditor` |
| `Block Editor/Proofs.lua` | `/blockproofs`: the in-app proofs |
| `tests/block_editor_test.lua` | Plain-Lua test of registries, state, colour rules (153 checks pass) |
| `tests/uitext_check.lua` | The new strings added to its lists |

Type check (`tools/typing/check.py`, LuaLS 3.19.2 as CI): zero problems. **Not registered with
any CodeMod and never run in the app.**

## 4. Next steps, in order

### Step 1: register the files (DMHub running; CLAUDE.md "New top-level Lua files")
Use `mcp__dmhub__register_lua_file` and confirm Firebase persistence after each:
1. Mod **DMHub Utils**: `DMHub Utils/Block.lua`, then `DMHub Utils/BlockStubs.lua`, both after
   `UIText.lua` and `Utils.lua` (DMHub Utils already loads before DMHub Game Rules).
2. A new mod **Block Editor**, depending on (loaded after) **Draw Steel UI** and **Draw Steel
   Ability Editor**, files in this order: `BlockEditor.lua`, `State.lua`, `BlockEditorText.lua`,
   `Styles.lua`, `MainPanel.lua`, `Proofs.lua`. Phase 1 files go between `Styles.lua` and
   `MainPanel.lua`.

If the MCP bridge cannot create the new mod, ask the owner. Do not hand-edit `main.lua`.
Then reload (F4) or deploy (`deploy.ps1`, see CLAUDE.md), and check `Player.log` for the
`MOD:: READ CONTENTS FOR MOD` lines.

### Step 2: run the proofs (developer mode on, a game open)
`/blockeditor`: the empty editor. Click shelf blocks: they appear in the middle column; Undo/Redo
(buttons and Ctrl+Z / Ctrl+Y) step through them; "Saves sent" in the side panel ticks up about
2 s after the last click (the demo host only logs).

`/blockproofs`, five tabs (each says on screen what to check):
1. **Drag**: a ghost follows the pointer at once, gaps become dashed slots, one opens to "Drop
   here" without flicker, holding near an edge scrolls.
2. **Sentence**: hover lights a word without moving text; a click opens a menu at the pointer;
   80-140% text and three widths.
3. **Blocks**: one block per colour group with glyph, hover, selected ring; scheme buttons
   recolour the window, never the blocks.
4. **Card**: book-style card: cream paper, black ink, `Book` font, tier marks, the "M" chip.
5. **Count**: build 20 / 100 / 300 blocks; note the panel count and time.

Screenshot each (the `ui-harness` skill helps) and show the owner.

### Step 3: likely adjustments (guesses made without the app)
- **Colours look off against the web palette**: `Block Editor/Styles.lua:21`, set
  `BEStyles.COLOR_PREFIX = ""` (it is `"srgb:"`, copied from the character builder's styles).
- **Ghost offset from the pointer** (modal layer scaled): `Block Editor/Proofs.lua` `BeginDrag`
  (~315) and `Tick` assume screen position, rendered size and a floating child's x/y share units.
- **The stack never highlights during a drag**: remove `dragInPlace = true` on the ghost
  (`Proofs.lua` ~351) and give the ghost its own `styles`.
- **Drop does nothing**: the code assumes `drag` fires on the ghost when released with no target.
- **Undo keys** use `inputEvents = {"undo", "redo"}` (`MainPanel.lua` ~424), the initiative
  bar's route; check the editor wins while open in combat.
- `<mark>` fills draw over text, so word highlights and the "M" chip are translucent; a solid
  chip is not possible that way.
- The scheme toggle changes the user's real colour scheme and restores it on close.

## 5. Then: phase 1 (the ability editor's UI)

From plan section 7 (decided build order): **(0)** skeleton and proofs, **(1) ability editor UI**
with blocks from the stub registrations, (2) ability blocks working (all 1,019 core abilities
round-trip), (3) triggered editor, UI then logic, (4) class and subclass, embedding both; later
titles, perks, kits, items, monsters. Each editor sits behind a developer setting until its
records round-trip, then becomes the **Simple** tab beside the **Advanced editor**.

Phase 1 builds, to look like `docs/block-editor/lua-preview/ability.html`: the sections (What it
is, Who it targets, Can only be used when, When it's used), the block stack with drop slots, the
shelf on the right, the amount and test pickers, the book-style card, the checks, the Advanced
editor link, and undo/redo with uploads (plan section 12). Blocks come from the stub
registrations: **never write block knowledge into the UI** (no modifier, behaviour or choice ids in
`Block Editor/*.lua`; real declarations replace the stubs in phase 2 with no UI change).

## 6. The owner's decisions and preferences (all in the ledger)

- Blocks have **fixed colours** (one table keyed by meaning, at least 5:1 under white text) and a
  **group glyph**; the theme never recolours them. Shelf blocks show full colour; ones that don't
  fit keep their colour with a dashed outline.
- The **shelf stays on the right** at every width but a phone's. **Drop slots** are hidden at rest,
  dashed during a drag, block-sized "Drop here" under the pointer.
- The **ability card keeps the printed book's layout**, not the game's tooltip.
- **Pickers: one entry per kind, never one per value.** The amount picker lists the kinds of amount
  with real examples (A number, A stat, A stat with math, More as you level, Depends on a test, A
  dice roll); examples follow a searched stat; the stat, sign and numbers change on the block.
- Moving before or after an attack is a **Choose one when used** block; picking targets one at a
  time is a "Targets are:" row (`sequentialTargeting`).
- Class page (phase 4): one tab per level, **Slow start** as one tab; subclasses as smaller pills
  set apart from the class; the **chain icon** combines roll changes.
- **Registries on `Block`, declared beside the game types**; the UI only reads them.
- **Engine and content problems are flagged in `FOLLOW_UP_ITEMS.md`, not fixed**, unless asked.
- Keyboard: mouse-first, with a per-block word list as the keyboard path.
- Write user-facing text and replies in plain language.

## 7. Still open

- Who builds which part in parallel.
- Where recipes (saved features) are stored: a per-user setting or a compendium table.
- Engine asks: focus on link words for keyboard use; a surge-spend purpose (F14/F15).

## 8. Phase 2 audit fixes (2026-11-27, commits after `563f0146`)

An audit of phase 2 against the decisions found gaps; these are fixed on this branch. Every
plain-Lua test passes (`tests/block_*_test.lua`), the type check is clean, and
`python tools/block_editor/check_ui.py` passes. **None of it has run in DMHub yet.**

**Do this first in the app (CodeMod registration changed):**
1. **DMHub Utils**: remove `DMHub Utils/BlockTiers.lua` from the file list (the file moved). The
   list should hold `Block.lua`, `BlockFormula.lua`, `BlockBehaviors.lua`, `BlockStubs.lua`, in
   that order, after `UIText.lua` and `Utils.lua`.
2. **Draw Steel Core Rules**: register `Draw Steel Core Rules/BlockTiers.lua` **before**
   `MCDMAbilityBehavior.lua` and `MCDMAbilityRollBehavior.lua` (they declare tier blocks at load).
   `MCDMAbilityBlocks.lua` must be registered too, anywhere after it.
3. **Block Editor**: `BlockEditor.lua` first; then `State.lua`, `BlockEditorText.lua`,
   `Styles.lua`, `RecordCache.lua`, `Slots.lua`, `BlockPanel.lua`, `Stack.lua`, `Shelf.lua`,
   `Page.lua`, `SidePanel.lua`, `MainPanel.lua`, `RoundTrip.lua`, `Proofs.lua`.
4. Turn on **developer mode** and the new **Block Editor (in development)** developer setting
   (`blockeditor:enabled`); the commands refuse to run without it.
5. Run `/blockroundtrip` and `/blockroundtrip forced`. The forced run now really writes every
   slot, so it may report differences the old one could not see: those are writers that do not
   reproduce the saved form, worth a look one by one.

**What changed:**
- **Saving:** stub blocks are off a real ability's shelf; a tier part that saves as one segment
  takes one block (`BlockBody.max`); a red check counts added blocks that cannot be saved; a
  failed upload stays dirty and retries; a failing block writer keeps the saved step.
- **Defaults:** an unsaved field reads as the game reads it (`Block.FieldValue`): damage type
  force, roll 1d6, category Skill, cost 1. Melee to ranged now sets a range of 10.
- **The UI names no game types** (CI: `.github/workflows/block-editor.yml`). The ability host
  lists its records (`records`) and names its Advanced steps (`stepName`).
- **Formulas** go through the parser: the roll's characteristic, the card's roll line, Only if
  grouping, and formula slots compared by meaning. The Draw Steel characteristics are a stat
  source and replace the stubs.
- **Amount picker:** one row per kind (A number, A stat, A stat with math, More as you level,
  Depends on a test, A dice roll), a "Now:" line, a search that adapts the examples; on the
  block each number, stat and sign is its own word. Number slots open a box.
- **Redo** button; the tier code moved to Draw Steel Core Rules; durations and damage types come
  from the game's lists; ledger rows for per-word sentence panels and `RegisterBehaviorBlock`.

**Look at in the app:** the amount picker (`Slots.lua`, `_openAmountPicker`) is new UI drawn
without seeing it: its width, the search box and row hover (`Styles.lua`, `beAmount*`).

**Still open (planned, not built):** saving through the class or subclass row (milestone 2c:
the ability host has no `upload`, and `tableName = "abilities"` is not a real table); usage
limits, Choose one when used (variations) and the "Targets are:" row; plan 12.5-12.6 (soft
deletes, other people's changes); the Advanced editor tab and its states; the per-block word
list; redrawing only the changed block; the dashed "doesn't fit" shelf rows; a card for a roll
like "2d10 + Might + 1" shows the raw roll.

## 9. Milestone 2c, first part (2026-11-27, run in DMHub)

- **Saving:** the editor opens a private copy of the record and, on each save, writes a fresh copy
  into the live record (so undo after a save works). The window then uploads through the host's
  `upload`: the ability host uploads the class or subclass that holds the ability
  (`FindCompendiumItemOwningGuid`, as the Advanced editor's dialog does). `tableName` is now
  optional; the ability host has none.
- **Simple tab:** `AbilityEditor.RegisterView` (Draw Steel Ability Editor) offers other views of an
  ability as tabs beside the Advanced editor; the Block Editor registers "Simple" there
  (`BlockEditor.CreatePanel(record, {embedded = true})`). It writes into the ability on every
  change and the dialog uploads it on close, as before. Shown only with developer mode and the
  `blockeditor:enabled` setting.
- **Writers keep saved forms:** a writer is skipped when what is saved already reads as the value
  (header slots in `RecordCache.Save`, step slots in `BlockBehaviors._writeField`). This fixed the
  12 forced differences (`anyspace` respelled `emptyspace`, `2d10 +Agility` respelled, an unset
  `durationUntilEndOfTurn` written as false), and it protects real edits: editing a tier rewrites
  every slot of its power roll. Side effect: the forced run no longer exercises a writer whose
  value already reads the same.
- **Measured in DMHub:** 748/748 untouched, 748/748 forced, 557 open fully as blocks (514 with every
  tier word read). DMHub Utils still lists the old `BlockTiers.lua` (it loads empty); remove it
  in the Codex's mod tools.
- **Still open:** other people's changes to an open record (plan 12.6) now matter, since the window
  saves for real; usage limits, Choose one when used, the "Targets are:" row; add a requirement;
  drop-slot precision.


## 10. Milestone 2c, second part (2026-11-27, written on the Mac, NOT yet run in DMHub)

DMHub was closed before any of this could be tested. First job on the next computer: reload the
Codex, check the console is clean, then run the tests below.

**Other people's changes (plan 12.6)** (`Block Editor/MainPanel.lua`, `State.lua`):
- The host keeps a copy of each record as the editor last saw or wrote it (`known`). The window
  (not the embedded Simple tab, whose dialog owns the record) sets `monitorAssets = true`; on
  `refreshAssets` it asks the host declaration's new `locate(record)` for the current version
  (the ability host: `ActivatedAbility:FindCompendiumSource` then the path) and compares.
- Same as `known`: our own echo, ignored. Different and nothing of ours pending: the record is
  re-opened from the new version (`BEState:ReplaceRecord` drops its pending change and its undo and
  redo parts) and a note shows for `BlockEditor.NOTICE_SECONDS`. Different with our change pending:
  the upload is held (`dirty = math.huge`) and a bar offers **Use theirs** / **Keep mine** (Keep
  mine saves over theirs: last save wins). Closing without choosing saves ours.

**Header rows** (`Draw Steel Core Rules/MCDMAbilityBlocks.lua`):
- **Usage limit** (What it is): the menu is `CharacterResource.usageLimitOptions` (Draw Steel's
  periods); saved into `usageLimitOptions`, the field the game enforces. Once limited, a
  "Uses before it refreshes" row (`charges`) appears. A new limit starts at 1 and gets a counter id
  (the ability's guid) unless it already has one. "victory:N" reads as the victory period.
  Known gap: a class feature's modifier keeps its own copy of the limit and the class editor copies
  it over the ability's when the feature is edited.
- **Targets are** (Who it targets): together / one at a time, saved as `sequentialTargeting`
  (unset for together); shown when the target count is not 1 or it is already one at a time.
- Rows can now hide: `BlockHeaderRow.when(values)` (`Block Editor/Page.lua`).

**Tests to run in DMHub** (stub the editor host's `upload`, never `dmhub.*`, which cannot be
replaced from Lua and then really uploads):
1. `/blockroundtrip` and `/blockroundtrip forced`: expect 748/748 both (new header writers must
   not change untouched records).
2. Open `/blockeditor Out of the Way!`, set `controller.data.host.upload` to a stub, change the
   live ability's name in memory, fire `refreshAssets` on the controller: expect the model renamed
   and the note shown. Then make an edit, change the live name again, fire again: expect the
   choice bar; try both buttons. Put the live name back afterwards.
3. On an ability with several targets, check the Targets are row shows; set a usage limit and see
   the count row appear; save (stubbed) and read `usageLimitOptions` / `sequentialTargeting`.
4. Plain-Lua tests in CI: `tests/block_editor_test.lua` (new ReplaceRecord case) and
   `tests/block_recordcache_test.lua` (writers keep saved forms); the type check.

**Still open:** the full "Choose one when used" block (option names, extra costs, options that
target differently / variations, design 4n); add a requirement; drop-slot precision.

## 11. Tested in DMHub on the owner's Windows computer (2026-11-27)

- Section 10's tests pass: both round trips 748/748; the "someone else changed it" note, the Use
  theirs / Keep mine bar, the Targets are row and the Usage limit with its use count all work.
- Fixed in `MCDMAbilityBlocks.lua`: setting the limit back to "none" on an ability that never had
  one now saves no limit (the limit's `changed` resets the use count to "0"), and an ability with
  no resource reads "which costs nothing" (separate `free` row) instead of "costs 1 nothing".
- Loading on this computer: a reload (F4 or the bridge's `/reload`) does not re-read Draw Steel
  Core Rules or Block Editor files, so edits there need a DMHub restart. The app's file lists still
  name `DMHub Utils/BlockTiers.lua` and `DMHub Game Rules/GetTableTypes().lua`; it recreates them
  as empty files on start. Keep them out of commits, or remove them from the lists in mod tools.
- **Owner feedback, later pass:** clicking a word should make it editable in place, not open a
  pop-up editor (ledger row 2026-11-27, "Clicking a text or number word edits it in place").

## 12. Choose one when used, plain modes and variations (2026-11-27, run in DMHub)

- **Blocks** (`Draw Steel Core Rules/MCDMAbilityBlocks.lua`): **Choose one when used** (shelf: Common;
  "before picking targets / after picking the target"; starts with two options), **Option** (name,
  extra cost 0-5, card text, its steps; shelf section "Inside Choose one when used"), and **Targets
  differently** (distance, range, count, target; shelf section "Inside an option"). Picking an extra
  cost adds, updates or removes a "Spend N Heroic Resource" step in the option (the option's
  `changed`), and sets the mode's condition "Heroic Resources Available to Spend >= N".
- **Framework** (generic, no Draw Steel names): `BlockDecl.split` (gather on open, key per option,
  prepare, saveRecord), `BlockDecl.initial` (a new block's bodies), `BlockDecl.changed` (called by
  `BlockPanel` after a slot edit), `ctx.result` (the copy being written) and `ctx.remap`.
  `BERecordCache.SaveSteps` flattens split blocks; `CountUnsaveable` flags a second one in a list or
  one inside another's options.
- **Measured in DMHub:** both round trips 748/748; 75 abilities open a Choose one block (223
  options, 16 Targets differently). Steps left outside as "Only when used as": only those in "no
  mode" (-1) or several modes (Hurl Element, Inertial Step, Elements Unleashed, Burning Lash, There
  Is No Space Between). Tested with saving stubbed: adding options, a cost, a variation; removing
  the block (modes off, option list kept, as the Advanced editor does); deleting an option renumbers
  the steps left outside; editing a variation's range changes only that field.
- Plain-Lua tests run on Windows with the VS Code Lua extension's runtime:
  `lua-language-server.exe tests/block_recordcache_test.lua` (Lua 5.5; CI uses 5.4).
- **Known gaps:** Advanced blocks are never wrapped, so a renumbered option does not renumber an
  Advanced step's saved modes; a non-cost mode condition is replaced when the extra cost changes;
  empty option lists draw as thin dark bars; "after picking the target" is not hidden once an
  option targets differently (it saves as before, since the game needs plain modes for it).

## 13. Add a requirement (2026-11-27, run in DMHub)

- **Block:** Requirement (Logic), "Only if [test], otherwise the player is told: [reason]", in the
  "Can only be used when" section (a stack of `requirements`); shelf section of the same name. The
  "add a requirement" row adds one at once (an add row with one fitting block skips its menu).
- **Saves as** `reasonedFilters`. The game checks each per target (`TargetPassesFilter`): bare
  names are the target's, `Caster.X` the user's. Only 5 requirements in 4 class abilities today
  (Impaled!, Healing Grace, Faith's Sword - Give Resource to Ally, Omnomnom). A test that means the
  same keeps its saved spelling; a new one with no test is not saved (a check says so).
- **Framework:** `BlockHost.lists` (read/write per record field), `model.lists` and
  `model.listCounts`; `BEState.AssignUids` and `FindInstance` walk those lists too.
- **Measured in DMHub:** both round trips 748/748; opening, editing a reason (only that field
  changes), removing, adding, and the empty-test check all checked with saving stubbed.
- **Not built:** the target filter row ("Only affects creatures who", `targetFilter`, 78 class
  abilities); the section count says "steps" for requirements.

## 14. Target filter row (2026-11-27, run in DMHub)

- **Row** under Who it targets: "Only affects a creature if [test]" (`filter` slot, saved as
  `targetFilter`; the game skips any creature that fails it, bare names being the target's).
- 79 class abilities use one (`Enemy` 33, `not Enemy` 25, then one-offs). I'm No Threat's is a
  GoblinScript table: it shows as "(a formula table: edit it in the Advanced editor)" and is locked.
- **Measured in DMHub:** both round trips 748/748 (one locked slot, that table). Changing, clearing
  and adding a filter write only `targetFilter`.

## 15. In-place editing (2026-11-27, run in DMHub)

- `Block Editor/Slots.lua`: `_editInPlace` hides a slot's words (they stay in the row) and puts an
  `Input` (`beWordInput`, styled as the hot word, `@label` font) where the first one was. Ends on
  submit, change or focus loss; unchanged text puts the words back. The box captures Escape at
  `EscapePriority.DMHUB_DROPDOWN` (the window's is `EXIT_MODAL_DIALOG`, and the modal layer otherwise
  closes the window first). `BESlots.CancelEdit()` is also called from the window's Escape.
- Goes straight to the box: text, number, formulas with no options, lone-number amounts, tier
  amounts with a value; amount pieces and the amount picker's "A number" / "Formula..." rows too.
- **Measured in DMHub:** flavor, name, cost, tier damage typed in place; one undo step each; undo
  restores; Escape cancels, a second Escape closes the window; Ctrl+Z while typing stays in the box.
- **Known:** redrawing the page while a box is open logs engine "Cannot change the sibling
  position" warnings (only reachable from code; the Undo button and Ctrl+Z end or keep the edit).
- Also fixed: `BlockEditorHost` now declares `changedElsewhere` and `adopt` (type check problems
  from the "Shared Edits" commit).

## 16. Drop-slot precision (2026-11-27, run in DMHub with virtual mouse drags)

- `Block Editor/Stack.lua`. Found by driving the bridge's `/mouse` (`down`, `move`, `up`, virtual):
  the pointer was read from the ghost (about 50 units off sideways); a slot opened only within 28
  units of a gap, so most of a tall block took nothing; opening a slot made the page taller and
  the fractional scroll moved everything under the pointer (the target jumped to the list's end);
  the edge auto-scroll band reached 36 units into the column at 1.5% of the page per tick; and a
  release between ticks dropped into the last open slot even outside every list.
- Now: `_pointer` (the window's `mousePoint`), `_gapUnder` (innermost fitting list, block halves),
  `_holdStill` (scrolls back by how far the content's top moved), `EDGE_IN` 16 / `EDGE_OUT` 60 at
  `SCROLL_SPEED` 8 units per tick, and the drop runs `_tick` first. The nearest-gap rule is kept for
  a pointer over no list.
- **Measured:** on Explosive Parade at mid-scroll, both halves of two steps open the right gaps
  with no jumps; a shelf drop lands after the step under the pointer; a grip move lands where shown
  (adjusted for the gap it leaves); a release outside every list adds nothing. On Banshee Howl, the
  option steps and the gap after the power roll.
- Testing note: set `vscrollPosition` a second or more after the window opens; earlier it is ignored.

## 17. Phase 2 audit: saving fixes (2026-11-28, run in DMHub)

`PHASE2_AUDIT.md` was reviewed against the code; its saving and code-rule findings held up. Fixed:
- **Conflict hold:** `BEState:Hold` / `Release` / `AnyHeld` (`state.held`); held records never
  upload, even forced. Closing with a record held shows a notice ("closing") instead of closing;
  a window destroyed otherwise keeps theirs. One bar, but an "updated" note no longer hides a
  conflict, and the next held record shows after a choice. Reloads cancel an open word box.
- **Gather failure:** the opened list keeps `splitFailed`; saving then skips `saveRecord(nil)`.
- **Saving to the opened row:** `_classAbilities` records table, row key and path per ability
  (`g_sources`, weak keys); `_uploadOwner` and `_locate` use it (`_sourceOf`, id lookup as the
  fallback). 36 class or subclass ability guids are shared between rows (Censor and Conduit both
  hold Hands of the Maker, Grave Speech, Revitalizing Ritual).
- **Requirements:** a formula table reads as the table marker and is kept unless retyped.
- **Modes:** wrapper `rekey` renumbers steps outside the wrapper (Advanced steps); re-adding Choose
  one after modes were off drops stale tags (`remap` false). Extra cost keeps the rest of a
  condition (joined with "and"); only the Spend step the cost made, or matched on open
  (`instance.marks.costStep`), is changed or removed.
- Code: `Slots` checks an old box is valid before finishing it; conflict buttons ignore a nil id;
  `Block.SameFormula` replaces the copy in the target filter; dead `BlockEditor.Routes` removed.
- `git rm` of `DMHub Utils/BlockTiers.lua` and `DMHub Game Rules/GetTableTypes().lua`; also remove
  them from those mods' file lists in the Codex's mod tools, or the app recreates them.
- **Measured in DMHub:** round trips 748/748 both; conflict held through edit, undo, redo and a
  forced upload; close blocked with notice; Keep mine uploads once; Censor's Hands of the Maker
  resolves to Censor's row; Banshee Howl's cost step updates and removes only itself.
- **Still from the audit:** tab name "Advanced editor", add rows in every list, card book wording,
  the "fx" button (decision 1), the Simple tab registered from the Draw Steel side, and the
  look-and-feel items. Owner decisions are in the ledger (2026-11-28).

## 18. Audit's cheap batch (2026-11-28, run in DMHub)

- **Tab name:** "Advanced editor" (`Draw Steel Ability Editor/AbilityEditor.lua`, `_viewTabs`);
  needs a DMHub restart to see.
- **Add rows** (`Block Editor/Stack.lua`): a stack inside a block (`ref.owner` set) ends with an
  add row (`_addRow`, `BEStack.AppendTo`); words from `BlockHost.addTexts`, noted by any list that
  reaches the host (`g_addTexts`), since a new block's lists are built before they join the page.
  Ability host: step "add step", tier "add result", option "add option", optiontargets "targets
  differently". Checked: tier 1 and option 2 take a block at their end, one undo step each.
- **Card:** `_cardDistance` / `_cardTarget` (`MCDMAbilityBlocks.lua`); Banshee Howl "3 burst /
  Each enemy in the area" from its saved wording, "5 burst" once the range changes; Bifurcated
  Incineration "Ranged 10 / Two creatures". Option text shows only with no description (decision 2).
- **fx:** an amount slot with a value gets a small "fx" word after it (`beWordFx`) that opens the
  amount picker; the number itself is typed in place (decision 1). Styles take no `italic`
  property (it raised an engine error popup); the italic is `<i>` in the label text.
- Still from the audit: the Simple tab registered from the Draw Steel side, shelf guidance and an
  insertion cursor, the test picker, the block menu, and the look-and-feel items.
