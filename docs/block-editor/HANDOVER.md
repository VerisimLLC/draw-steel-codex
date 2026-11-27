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
