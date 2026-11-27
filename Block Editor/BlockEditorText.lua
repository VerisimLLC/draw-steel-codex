local mod = dmhub.GetModLoading()

--The words of the Block Editor (the "Simple" editors) and its developer proofs.
--
--HOW TO EDIT THIS FILE (for writers)
--
--  Each entry is:   text("an.id", [[the words]])
--
--  * Change only the words between [[ and ]]. Never change the id in quotes:
--    it is how the editor finds the words.
--  * {name} is filled in by the editor (a record's name, a number, ...). Keep
--    every one, spelled exactly as it is; you may move it in the sentence.
--  * <b>...</b> and <i>...</i> are formatting. Keep them, in pairs.
--  * Use plain keyboard characters only: straight quotes ' and ", three dots
--    ..., a hyphen or a colon for a dash. Curly quotes, em dashes and other
--    special characters break the file.
--  * Lines starting with -- are notes for you; the editor ignores them.
--
--The words ON the blocks (a block's name, its sentence, its hover text) are
--not here: they are declared with each block, beside the game rules.
--
--Code: UIText (DMHub Utils/UIText.lua). Checked by tests/uitext_check.lua.

local text = UIText.Define("BlockEditorText")

----------------------------------------------------------------------------
-- THE EDITOR WINDOW: the title bar
-- (Block Editor/MainPanel.lua)
----------------------------------------------------------------------------

--The window's heading. {name} is the record being edited.
text("blockeditor.title", [[Edit {name}]])
--The two editor tabs. "Advanced editor" is the name of today's form editor
--everywhere; do not reword it in one place only.
text("blockeditor.tab.simple", [[Simple]])
text("blockeditor.tab.advanced", [[Advanced editor]])
--Its tooltip while the tab is not connected yet.
text("blockeditor.tab.advanced_tooltip", [[Opens today's editor on the same record. Not connected yet.]])
--The Undo and Redo buttons. Short: buttons.
text("blockeditor.undo", [[Undo]])
text("blockeditor.redo", [[Redo]])
--Their tooltips. {change} is what the step did, e.g. "Add Deal damage".
text("blockeditor.undo_tooltip", [[Undo: {change}]])
text("blockeditor.redo_tooltip", [[Redo: {change}]])
text("blockeditor.undo_nothing", [[Nothing to undo.]])
text("blockeditor.redo_nothing", [[Nothing to redo.]])

--What an undo step is called when a block is added. {block} is the block's name.
text("blockeditor.change.add", [[Add {block}]])

----------------------------------------------------------------------------
-- THE EDITOR WINDOW: the three columns
----------------------------------------------------------------------------

--The left column: the record's blocks.
text("blockeditor.detail.heading", [[Blocks]])
--Shown while the record has no blocks.
text("blockeditor.detail.empty", [[Nothing here yet. Click a block on the shelf to add it.]])

--The middle column: the blocks that can be added.
text("blockeditor.shelf.heading", [[Shelf]])
text("blockeditor.shelf.note", [[Click a block to add it.]])

--The right column.
text("blockeditor.side.checks", [[Checks]])
text("blockeditor.side.checks_note", [[Problems with the record will be listed here.]])
--A developer readout of the editor's undo and saving, while it is being built.
text("blockeditor.side.state", [[Undo and saving]])
text("blockeditor.side.state_text", [[Undo steps: {undo}
Redo steps: {redo}
Records not saved yet: {unsaved}
Saves sent: {uploads}]])

--The developer window's sample record and its sections.
text("blockeditor.demo.record_name", [[a sample ability]])
text("blockeditor.demo.section.what", [[What it is]])
text("blockeditor.demo.section.who", [[Who it targets]])
text("blockeditor.demo.section.when", [[Can only be used when]])
text("blockeditor.demo.section.used", [[When it's used]])

----------------------------------------------------------------------------
-- THE PROOFS: a developer-only window (Block Editor/Proofs.lua)
-- Each "check" says what the developer should look for.
----------------------------------------------------------------------------

text("blockeditor.proofs.title", [[Block Editor proofs]])
text("blockeditor.proofs.tab.drag", [[1. Drag]])
text("blockeditor.proofs.tab.sentence", [[2. Sentence]])
text("blockeditor.proofs.tab.blocks", [[3. Blocks]])
text("blockeditor.proofs.tab.card", [[4. Card]])
text("blockeditor.proofs.tab.count", [[5. Count]])
text("blockeditor.proofs.yes", [[yes]])
text("blockeditor.proofs.no", [[no]])

--1. Drag
text("blockeditor.proofs.drag.check", [[Check: drag a block from the shelf. A small copy should follow the pointer at once. Every gap in the stack turns into a dashed slot, and the one the block would land in opens to "Drop here" without flickering as you move. Hold the pointer near the stack's top or bottom edge: it should scroll. Let go to insert the block; let go outside the stack and nothing changes.]])
text("blockeditor.proofs.drag.stack", [[Stack]])
text("blockeditor.proofs.drag.shelf", [[Shelf]])
text("blockeditor.proofs.drag.drop_here", [[Drop here]])
--The readout under the stack. {count} is how many blocks the stack holds.
text("blockeditor.proofs.drag.status_idle", [[{count} blocks. Drag one from the shelf.]])
--{slot} is the slot's number (0 is above the first block), {engine} is yes or
--no, {y} is the pointer's height in the stack.
text("blockeditor.proofs.drag.status", [[Slot: {slot}   Pointer: {y}   The engine sees the stack under the copy: {engine}]])

--2. Sentence
text("blockeditor.proofs.sentence.check", [[Check: this is one label. Each underlined word should light up under the pointer without the text moving, and a click on it should open a menu at the pointer; picking an entry changes the word. Try every text size and width: words should wrap cleanly and stay clickable on every line.]])
--{percent} is the text size, 80 to 140.
text("blockeditor.proofs.sentence.size", [[Text size: {percent}%]])
--A button. {width} is a width in pixels, or 100%.
text("blockeditor.proofs.sentence.width", [[Width {width}]])
--The one menu entry of a word that is typed, not picked.
text("blockeditor.proofs.sentence.no_choices", [[(typed in a small box here)]])

--3. Blocks
text("blockeditor.proofs.blocks.check", [[Check: one block per colour group, each with white text and its glyph. Hover should brighten a block and a click should ring it (click again to clear). Pick each colour scheme: the window changes and the blocks must not. The schemes here change your own setting; it is put back when this window closes.]])
--A button: shows the outline of a block that cannot go in the chosen list.
text("blockeditor.proofs.blocks.no_fit", [[Show "does not fit here"]])

--4. Card
text("blockeditor.proofs.card.check", [[Check: the card should look like the printed book on any colour scheme: cream paper, black ink, the Book font, a tier mark in front of each of the three results, and the characteristic as a shaded chip.]])
--The sample ability on the card (the Fury's, from the rules).
text("blockeditor.proofs.card.name", [[Out of the Way! (3 Ferocity)]])
text("blockeditor.proofs.card.flavor", [[Your enemies will clear your path, whether they want to or not.]])
text("blockeditor.proofs.card.keywords", [[Melee, Strike, Weapon]])
text("blockeditor.proofs.card.action", [[Main action]])
text("blockeditor.proofs.card.distance", [[Melee 1]])
text("blockeditor.proofs.card.target", [[One creature]])
text("blockeditor.proofs.card.roll", [[Power Roll + Might:]])
--The letter in the characteristic chip.
text("blockeditor.proofs.card.chip", [[M]])
--The three results. {chip} is the characteristic chip.
text("blockeditor.proofs.card.tier1", [[3 + {chip} damage; slide 2]])
text("blockeditor.proofs.card.tier2", [[5 + {chip} damage; slide 3]])
text("blockeditor.proofs.card.tier3", [[8 + {chip} damage; slide 5]])
text("blockeditor.proofs.card.effect", [[<b>Effect:</b> When you slide the target, you can move into any square they leave. If you take damage from an opportunity attack by moving this way, the target takes the same damage.]])

--5. Count
text("blockeditor.proofs.count.check", [[Check: build each size and scroll the list. Scrolling should stay smooth at 300 blocks, and the build time shows what opening a large record costs (it does not include the first layout).]])
--A button. {count} is how many blocks it builds.
text("blockeditor.proofs.count.build", [[Build {count} blocks]])
text("blockeditor.proofs.count.idle", [[Nothing built yet.]])
--{blocks} blocks were built from {panels} panels in {ms} milliseconds.
text("blockeditor.proofs.count.result", [[{blocks} blocks, {panels} panels, built in {ms} ms.]])
