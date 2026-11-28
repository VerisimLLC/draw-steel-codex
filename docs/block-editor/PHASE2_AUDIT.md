# Block Editor: phase 2 audit (2026-11-28)

An audit of branch `New-Block-UI` at `49df75d3` ("Content containers"), focusing on how the Lua
interface compares with the approved prototype (`ui-mockup/ability-blocks-stack.html` on branch
`claude/vibrant-mayer-tzljkn`). Five reviewers ran in parallel: window layout, blocks and
interaction, the card and checks, saving, and code rules. Their main claims were checked against
the code. DMHub could not run in the review session, so the Lua side was traced from the code;
the prototype was rendered and driven with Playwright. Screenshots of the prototype are in
[`phase2-audit/`](phase2-audit/).

**Checks run:** all five plain-Lua tests pass (`tests/block_*_test.lua`), the LuaLS type check
has zero problems, `tools/block_editor/check_ui.py` passes, and the Lua is ASCII.

The decision ledger (end of `BLOCK_EDITOR_FRAMEWORK.md`) wins over the prototype. Each item says
whether a ledger row decides it, or whether it is drift. ★ marks what an author notices most.

## 1. Where the interface drifts from the prototype

Compare with [`prototype-page-gouge.png`](phase2-audit/prototype-page-gouge.png).

### The page and window

1. ★ **The real ability page is missing four parts.**
   - **Prototype:** "This is [an ability | a triggered ability]", "Belongs to" in the title bar,
     the Who it targets summary ("A creature within 1 square of you.") and "Start from:" pills.
   - **Lua:** only the stub host declares them (`DMHub Utils/BlockStubs.lua:472-523`). The real
     host (`Draw Steel Core Rules/MCDMAbilityBlocks.lua`, `Block.RegisterHost`) has no `kindChoice`,
     `toolbar`, `summary` or `templates`, so the page opens straight onto "What it is".
   - **Ledger:** none. Drift.
2. ★ **The Simple tab has three rows of chrome where the prototype has one.**
   - **Prototype:** one bar with the title, "Simple | Advanced editor" and the tools.
   - **Lua:**
     - the ability editor's own title strip, with tabs "Simple | Advanced"
       (`Draw Steel Ability Editor/AbilityEditor.lua:5404-5468`);
     - then a second bar with Paste text, Undo and Redo (`Block Editor/MainPanel.lua:271-284`);
     - then the section strip.
   - **Default tab:** the dialog opens on Advanced (`_lastView = "advanced"`).
   - **Ledger:** 2026-11-26 names it the **Advanced editor** everywhere; the label "Advanced"
     (`AbilityEditor.lua:5412`) breaks that.
3. **There is a section strip the prototype does not have** (`MainPanel.lua:385-432`).
   - It repeats the section headers just below it, and its selected mark does not follow
     scrolling.
   - It came from the Lua preview mockup and plan section 2a, not the prototype. No ledger row.
4. ★ **The shelf lists blocks but does not guide.**
   - **Prototype:**
     - search "Search blocks ( / )";
     - the hint "Drag, or click to add at **When it's used**";
     - a curated Common list (15 blocks) that becomes "Adding to <tier>";
     - blocks that don't fit, faded;
     - a folded "Only inside a power roll tier";
     - the "All blocks by category" grid.
   - **Lua** (`Block Editor/Shelf.lua:89-128`):
     - five always-open sections, about 30 rows in registry order;
     - a caret on each header that does nothing;
     - no hint, no "/" and no grid.
   - **Ledger:** none. Plan 10.2 lists these as designed but not yet drawn, so this is unfinished
     work.
5. **Section headers look heavier.**
   - **Prototype:** 11px, dim, letter-spaced, uppercase, with no caret, rule or count. "optional"
     shows only while the section is empty.
   - **Lua** (`Block Editor/Styles.lua:557-626`, `Page.lua:238-250`): 13px bold, with a caret,
     a full-width rule and a count. "optional" is always shown.
   - This came from the Lua preview mockup. No ledger row.
6. **The add rows are flat.**
   - **Prototype:** "+ add step" and "+ add a requirement" are dashed boxes, and the insertion
     point is gold.
   - **Lua:** full-width rows with no border (`beAddRow`, `Styles.lua:654-666`). "Start from:"
     sits at the very bottom and always shows (`Page.lua:310-312`).
7. **The checks column has no status sentence.**
   - **Prototype:** a bordered box first ("Ready to save. The Advanced editor can open it too." or
     "1 thing to finish before saving."), then callouts, then the card, the hint and "Saved data".
   - **Lua** (`SidePanel.lua:250-301`): "CHECKS N" with a dot per check, and no "Saved data".
8. **The title bar is different.**
   - **Lua:** a gradient bar with a 22px bold title, theme folder tabs (the Advanced one is 190px
     and not clickable), and Close.
   - **Prototype:** a flat bar with a small gold segmented switch, plus Show GoblinScript and Open
     (plan 10.2 defers those two).
   - Redo is right: ledger 2026-11-26.
9. **Fonts differ.**
   - **Lua:** labels with no `fontFace` fall back to the theme's serif (Berling): the section strip,
     header rows, shelf names (15px) and block words (16px).
   - **Prototype:** sans (Inter 13px) everywhere but the card.
10. **Size and proportions differ.**
    - **Lua:** a fixed 1480x900 window with three columns of about 900 / 250 / 330, each scrolling.
      `WINDOW_WIDTH = 1320` is declared but unused (`Styles.lua:24` and `:59`).
    - **Prototype:** at most 1320 wide, split 742 / 236 / 340. The page scrolls and the shelf is
      sticky.
    - **Tone:** the page column has its own gradient (`@surfaceRadial`), so it reads a different
      tone from the shelf and side.

### Blocks and editing

Compare with [`prototype-block-menu.png`](phase2-audit/prototype-block-menu.png),
[`prototype-amount-picker.png`](phase2-audit/prototype-amount-picker.png),
[`prototype-test-picker.png`](phase2-audit/prototype-test-picker.png) and
[`prototype-drag.png`](phase2-audit/prototype-drag.png).

11. ★ **Without dragging, you cannot add into a chosen list.**
    - **Prototype:** an add row in every list ("+ add result" in each tier, "+ add step" in each
      wrapper and option, "+" between steps) and a gold insertion cursor. The shelf names the
      cursor ("click to add at tier 3 (17+)") and filters to what fits. After adding a wrapper, the
      cursor moves inside it.
    - **Lua:**
      - bodies have no add row (`BlockPanel.lua:168-187`);
      - a shelf click appends to the first list that fits (`Stack.lua:522-583`), so a tier block
        always lands in tier 1 of the first power roll, and a step never goes into an Only if or
        an Option.
    - **Ledger:** 2026-11-24 "every drag has a click path"; plan 10.2 "click to add at the
      insertion cursor". Drift.
12. ★ **Tests are GoblinScript.**
    - **Lua:** Only if starts as `Target.Winded` in Courier, typed in place
      (`MCDMAbilityBlocks.lua:996-997`); a Requirement works the same way (`:1053-1056`). The test
      picker (`Slots.lua:61-67`) lists three stub tests with "Build a test..." disabled, and no real
      block uses it.
    - **Prototype:** "Only if **the target is prone**". Adding the block opens the test picker, with
      grouped choices ("Combine tests", "Check what kind of creature", ...) and "Type a formula
      instead".
    - **Ledger:** 2026-11-27 (in-place editing) lists tests as typed; plan 10.2 still carries the
      test picker.
13. ★ **The amount picker is hard to reach.**
    - **Lua:** a lone number, and any tier amount with a value, is typed over in place
      (`Slots.lua:830-836`). A new Deal damage reads "2", so an author only meets A stat / More as
      you level / Depends on a test / A dice roll by typing GoblinScript. The tier damage kinds
      (`MCDMAbilityRollBehavior.lua:4787-4792`) are effectively unreachable, since tier damage
      starts as "2 + M".
    - **Prototype:** an fx button beside the number opens the picker.
    - **Ledger:** 2026-11-27 (in-place editing) and 2026-11-26 ("one entry per kind") pull against
      each other. **Owner decision 1.**
14. **The block menu is thin.**
    - **Lua:** Move up, Move down, Delete (`BlockPanel.lua:43-82`). The moves are not greyed at the
      ends and can leave an empty undo step.
    - **Prototype:** also Wrap in Logic (Only if...), Wrap in potency check, Unwrap (keep the steps
      inside) and Duplicate.
15. **Grey Advanced blocks have no "Edit in the Advanced editor" button**
    (`MCDMAbilityBlocks.lua:1111-1122`). The ledger states table (section 6a) and plan 10.2 ask
    for it.
16. **The amount picker's details differ.**
    - **Title:** generic, "What should this be?". The prototype names the slot ("Damage") with a
      "number or dice" badge.
    - **Missing:** the help line, the Who: box, and the note "You change the stat, sign and
      numbers on the block after picking".
    - **"Now:" line:** shows the raw formula, not plain words.
    - **"Formula...":** does not check what is typed. The prototype says "Understood. Becomes
      blocks: ..." or shows the error.
    - **Matches:** the six kinds, and the search adapting the examples.
17. **Drag visuals differ.**
    - **Ghost:** a small name-only block (`Stack.lua:439-450`); the prototype drags a full copy.
    - **Source:** the moved block is not dimmed.
    - **Slots:** hints are grey and the open slot is a fixed 34px. The prototype's are gold and
      sized to the block.
    - **Shelf:** does not narrow to what fits during a drag.
18. **Blocks look like the Lua preview mockup, not the prototype.** No ledger row.
    - **Emphasis is reversed:** fixed lead words are bold, editable words are plain with a solid
      underline. The prototype bolds editable words with a dotted underline and fades defaults
      such as "untyped".
    - **Wording:** "Power roll + Might" has no "2d10". Tier blocks use book shorthand
      ("3 + M untyped damage"), not "Deal ..." / "Make the target ...".
    - **Shape:** bodies sit in closed frames, not the prototype's C-shaped spine. The menu button
      is a bare dots icon.
    - **Tier labels:** "11 or lower" rather than the prototype's tier marks; the ASCII rule forces
      that.
19. **Keyboard:** ledger 2026-11-26 promises a per-block word list. Lua has only Ctrl+Z/Y and
    Escape. The prototype's words take Tab and Enter, and "/" searches the shelf.

### The card and checks

Compare with [`prototype-card-strike.png`](phase2-audit/prototype-card-strike.png),
[`prototype-card-choose-one.png`](phase2-audit/prototype-card-choose-one.png),
[`prototype-card-potency.png`](phase2-audit/prototype-card-potency.png) and
[`prototype-card-requirement.png`](phase2-audit/prototype-card-requirement.png).

20. ★ **The distance and target line is not book wording** (`MCDMAbilityBlocks.lua:1320-1325`).
    - **What Lua prints:** "Self 1", "Burst 2 + Charges", "Cube <range>", "1 creature",
      "3 enemy".
    - **What the book says:** "Self", "2 burst", "3 cube within 10", "One creature or object",
      "Three enemies", "Each enemy in the area".
    - **Saved wording ignored:** `rangeTextOverride` (108 core abilities) and `targetTextOverride`
      (220) are never read.
    - **Same flaw on the page:** the header row "Distance: Self 1" shows the range for Self.
    - **Ledger:** design 4p says the card follows the book and saved wording wins. Drift.
21. ★ **The effect is one raw paragraph** (`:1353-1368`).
    - 80 core descriptions contain `**`, which shows literally, and 124 contain line breaks.
    - The prototype splits "**Strained:**" and "Special:" into labelled paragraphs, and hides a
      description that is only an implementation summary.
22. **Choose one when used and variations.**
    - **Book and design 4m:** each option is its own bold-labelled paragraph ("**Spend 1
      Ferocity:** ..."), and an option that targets differently starts with its own distance and
      target.
    - **Lua:** puts "Name: rules" lines in the single Effect paragraph, with the name not bold, and
      shows them even when a description exists. The prototype shows saved option text only when
      there is no description. **Owner decision 2.**
23. **Potency is not the book's box.** `_tierParts` (`:461`) makes any lone M/A/R/I/P a chip, so
    "P < weak" draws as [P] then plain "< weak". The prototype boxes "P<WEAK".
24. **The target filter and requirements are not listed under the card** (prototype notes:
    "Only affects a creature if ...", "Can only be used if ... (reason)"; design 4p).
25. **The checks are weaker.**
    - **No status line:** a new ability with nothing wrong shows "Checks 0" and nothing else.
    - **Blocks saving in the prototype, only warns in Lua:** an unnamed option, fewer than two
      options, a requirement with no test (`:1371-1408`).
    - **Missing:** "The ability does nothing yet", "This power roll has no results yet", "Nothing
      happens inside this potency check", and the "N saved settings kept" list.
    - **Grammar:** "1 of the options have no name".
26. **Smaller card points.**
    - A formula damage shows "{Reason*2}" with braces; the prototype shows "double your Reason".
    - Cost shows only when above 0. Eight abilities have a resource and cost 0.
    - Empty tiers print nothing; the prototype prints "no effect".
    - Card lines light up on hover, though clicking does nothing yet.

## 2. Saving problems (fix before relying on it)

1. **Blocker: "Use theirs / Keep mine" does not hold.**
   - **Where:** `MainPanel.lua:686` holds the upload with `dirty = math.huge`, but
     `BEState:Change` (`State.lua:210`) and undo or redo (`_restore`, `:162`) reset it to now.
   - **What happens:** keep editing while the bar is up, and your version uploads over theirs two
     seconds later. "Use theirs" then finds nothing changed. Closing the window
     (`UploadDirty(true)`, `MainPanel.lua:593`) also saves yours without asking.
   - **Fix:** a separate "held" set that Change, undo, redo and UploadDirty all respect.
     **Owner decision 3** (close: save or ask).
2. **Your own save coming back may look like someone else's change** (unverified in the app).
   - `known = DeepCopy(record)` (`MainPanel.lua:131`) keeps `_tmp_` fields, and only the last
     upload is remembered.
   - If the server's copy differs at all, the record is reloaded and `ReplaceRecord` wipes its
     undo history. Only changes faked in memory were tested (handover sections 10-11).
3. **A failure while opening Choose one when used wipes the modes.** If `split.gather` raises,
   `OpenSteps` keeps the list without the block (`RecordCache.lua:235`). The next save calls
   `saveRecord(nil)` (`:388`), which sets `multipleModes = false` on a record nobody touched.
4. **Mode numbers go stale.**
   - Advanced steps are never wrapped, so deleting an option leaves their `modesSelected` on the
     old numbers, and they run in the wrong option, or in none.
   - Removing Choose one only sets `multipleModes = false`; adding it again brings old tags back to
     life.
5. **Changing an option's extra cost** (`MCDMAbilityBlocks.lua:604`, `:771-774`, `:868-892`):
   - it replaces a non-cost or compound mode condition;
   - a cost of 0 removes the first Spend step, even one the author made;
   - adding a cost may charge twice (unverified against content).
6. **Saves go to the first row holding the ability's guid** (`_uploadOwner`, `:1191`,
   `FindCompendiumItemOwningGuid`), not the row it was opened from. It also walks the whole
   compendium on every save; `_locate` already uses the cached `FindCompendiumSource`.
7. **Smaller saving issues.**
   - **Usage limit in two places:** the class feature's modifier keeps its own copy, which the
     class editor writes over the ability's (known gap).
   - **Requirements:** a test saved as a formula table is written back as the text "table: 0x..."
     once any requirement is edited (`:1078-1086`). The target filter guards against this;
     requirements do not.
   - **Clearing leaves empty values:** `reasonedFilters = {}`, `targetFilter = ""`, and a "none"
     limit with its counter. The game treats them as nothing.
   - **"victory:N"** reads as "victory": N cannot be seen and is lost on a switch.
   - **Typing in place:** a number slot accepts "abc" or empty text.
   - **Two placeholder files are committed** in f4e6a5c5: `DMHub Utils/BlockTiers.lua` and
     `DMHub Game Rules/GetTableTypes().lua`. Merging to main would bring back files that were
     deliberately removed. Remove them with `git rm` and from the app's file lists.

## 3. Code rules

- **The Simple tab is registered from the generic module.** `MainPanel.lua:772-784` calls
  `AbilityEditor.RegisterView`, and `BlockEditorText.lua:37` says "Edit this ability as blocks".
  Both belong on the Draw Steel side. `check_ui.py` does not look for this.
- **A reload can hit an open text box.** A reload from someone else's change redraws the page
  while an in-place box may be open (the engine's "Cannot change the sibling position" warning).
  Call `BESlots.CancelEdit()` first.
- **Possible errors:** `editorReloadTheirs` / `editorKeepMine` assign `conflicts[id]` with an id
  that may be nil. `Slots.lua:196` calls an old box's `finish()` without checking it is still
  valid.
- **One notice for all records:** an "updated" note for one record replaces a conflict bar for
  another.
- **Stale and dead code:**
  - `BlockEditor.lua:104-109` still says saving through the container is not built.
  - `BlockEditor.Routes` is dead (`MainPanel.lua:437-443`; `CanOpen` replaced it).
  - "phase 1" (`MainPanel.lua:34`); the Advanced tab tooltip still says "Not connected yet".
  - The handover section 10 heading says "NOT yet run".
- **Duplicated code:** `MCDMAbilityBlocks.lua:359` and `:1087` re-write `Block.SameFormula`.
- **Cost:**
  - each save copies the record about three times, and the embedded tab does this on every
    change;
  - `_splitDecls()` scans the registry on every open and save;
  - `Stack.lua:299` reads `_content(detail)` twice per tick.
- **No tests cover the real Draw Steel parts:** gather / prepare / remap, variations, the cost
  step, the limit writers, filter locking, the requirements writer, or the window's
  upload / echo / conflict handling.
- **Non-developers:** no change in the Advanced editor without developer mode and the
  `blockeditor:enabled` setting (`CanOpen` gates it).

## 4. What matches

- The shelf is on the right with full-colour rows, grip and glyph; blocks have fixed colours
  (ledger 2026-11-25, 2026-11-26).
- Each word is its own panel, and the whole slot lights on hover. Editing in place is one undo
  step; Escape restores the words.
- An amount's stat, sign and numbers are words on the block, with "Change what it is based on...";
  the picker's six kinds and adaptive search match.
- Drop slots: hidden at rest, dashed during a drag, the innermost list wins, the gap is chosen by
  block halves, "Drop here" shows, the page holds still and auto-scrolls, and a release outside
  every list adds nothing.
- Keyword chips with an X and "+ keyword"; a newly added block flashes.
- The card: cream paper, black ink, the Book font, diamond marks, the bold keyword and action line,
  the icons, "Power Roll + Might:", and characteristic chips.
- Choose one when used as Option blocks with Targets differently; requirements; the target filter
  row; usage limit; "Targets are" (all ledger 2026-11-27).
- Both round trips are 748/748 in DMHub (handover sections 11-16).

## 5. Decisions for the owner

1. **A lone number: type in place, or the amount picker?** Suggested: type in place, plus a small
   "fx" button beside it that opens the picker, as in the prototype.
2. **Saved option text on the card:** only when the ability has no description (prototype), or
   always (Lua now)?
3. **Closing the window during a conflict:** save yours, or ask?
4. **The section strip and the heavier section headers** came from the Lua preview mockup, not the
   prototype. Keep them, or match the prototype?

## 6. Suggested order of work

1. **Saving:** the conflict hold, the gather failure, saving to the row the record was opened
   from, the requirement formula table, and removing the placeholder files.
2. **Add rows** inside every list, with an insertion cursor the shelf follows.
3. **The page parts** the real host is missing ("This is", the Who summary, "Start from"), and the
   tab name "Advanced editor".
4. **The card's book wording** for distance and target (read the saved overrides), effect
   paragraphs, option paragraphs and the potency box.
5. **Shelf guidance:** the hint, the curated Common list, faded blocks, "/" search.
6. **The test picker** for Only if and requirements.
7. **The block menu:** wrap, unwrap, duplicate, greyed moves; "Edit in the Advanced editor" on grey
   blocks.
8. **Look and feel:** fonts, header weight, emphasis on editable words, drag visuals.
