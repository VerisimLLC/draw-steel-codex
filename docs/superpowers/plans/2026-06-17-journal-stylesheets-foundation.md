# Journal Stylesheets - Foundation (Plan 1 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the data model and cascade resolver for journal stylesheets -- a registered `JournalStylesheet` game type stored in a `journalStyles` table, a built-in default skin, an inheritance-aware `ResolveStylesheet(id)` resolver, and a persisted `styleSheetId` field on `MarkdownDocument`. No rendering or UI changes yet; this is the foundation every later plan consumes.

**Architecture:** All code lands in the existing `DocumentSystem/MarkdownDocument.lua` (the no-new-files rule forbids new Lua files). `JournalStylesheet` is a `RegisterGameType` with `tableName = "journalStyles"`, so it is cloud-stored and auto-serialized like other game content. The resolver walks the `parentId` chain to a built-in root skin, deep-merging child-over-parent, and memoizes results. `MarkdownDocument` gains one auto-serialized field, `styleSheetId`.

**Tech Stack:** DMHub Lua mod runtime; `RegisterGameType`, `dmhub.GetTable`/`dmhub.SetAndUploadTableItem`, the ThemeEngine token vocabulary. Verification via the DMHub MCP bridge (`reload_lua` + `execute_lua`), since the project has no command-line test runner.

## Global Constraints

- **ASCII only.** Every byte in `MarkdownDocument.lua` (code and comments) must be 0-127. No em dashes, curly quotes, ellipses. Use `-`, `"`, `...`.
- **No new files.** All additions go into `DocumentSystem/MarkdownDocument.lua`. Do not add a `require` to `main.lua`.
- **No CLI test runner.** Verify by: save the file, call `mcp__dmhub__reload_lua`, then `mcp__dmhub__execute_lua` with an assertion snippet that prints `PASS`/`FAIL`. There are no `.lua` test files to commit -- tests are bridge snippets recorded in this plan.
- **Forward-declare self-referencing locals.** `local x; x = function() ... x ... end`, never `local x = function() ... x ... end` when the closure references `x`.
- **Transient fields use `_tmp_` prefix** and are skipped by serialization; read them with `obj:try_get("_tmp_foo")`. All other fields on a game type auto-serialize -- no registration needed.
- **DMHub throws on reading uninitialized globals/fields.** Declare every default field on the type (e.g. `JournalStylesheet.parentId = nil`) so reads are safe.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `DocumentSystem/MarkdownDocument.lua` | Markdown document type + rendering + (new) stylesheet model | Modify only |

All Plan-1 code is added near the top of the file, after the existing `g_markdownStyle` definition (ends line 14) and before `g_hardwiredPowerTableList` (line 178). The `styleSheetId` field is added to the `MarkdownDocument` field block near line 5.

Anchor reference (verified):
- `MarkdownDocument = RegisterGameType("MarkdownDocument", "CustomDocument")` -- line 4; default fields at lines 5 (`vscroll`) and 66 (`RichTagRegistry`).
- `g_markdownStyle = gui.MarkdownStyle{...}` -- lines 7-14 (today's heading sizes, the values the default skin mirrors).
- Document create pattern -- line ~3551: `MarkdownDocument.new{ content = "", annotations = {} }`.
- Upload pattern -- line ~1546: `dmhub.SetAndUploadTableItem(MarkdownDocument.tableName, markdownDoc)`.

---

## Task 1: Register the JournalStylesheet type, table, and built-in default skin

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (insert after line 14, before line 178)

**Interfaces:**
- Produces:
  - Global `JournalStylesheet` (a `RegisterGameType`), with fields `name:string`, `parentId:string|nil`, `base:table`, `classes:table`, and class field `JournalStylesheet.tableName = "journalStyles"`.
  - `JournalStylesheet.Create() -> JournalStylesheet` (empty `base`/`classes`).
  - Module-local `g_defaultSkin` (a fully-populated base-skin table) -- consumed by Task 2's resolver as the implicit inheritance root. Shape documented in code below.

- [ ] **Step 1: Write the failing test (bridge snippet)**

This is the assertion we will run through the MCP bridge. Save nothing; run it via `execute_lua` after `reload_lua`.

```lua
-- TEST 1: type + table + default skin exist and are shaped correctly
local ok = true
local function check(cond, msg) if not cond then ok=false print("FAIL: "..msg) end end
check(type(JournalStylesheet) == "table", "JournalStylesheet type registered")
check(JournalStylesheet.tableName == "journalStyles", "tableName is journalStyles")
local s = JournalStylesheet.Create()
check(type(s.base) == "table", "Create() gives a base table")
check(type(s.classes) == "table", "Create() gives a classes table")
check(s.parentId == nil, "new stylesheet parentId defaults nil")
-- default skin shape
check(type(g_defaultSkin_PROBE) == "table", "default skin accessible via probe")
check(g_defaultSkin_PROBE.headings[1].sizePct == 200, "h1 default size mirrors today (200%)")
check(g_defaultSkin_PROBE.body.font ~= nil, "body font set")
check(g_defaultSkin_PROBE.bullet.glyph ~= nil, "bullet glyph set")
print(ok and "PASS" or "TEST FAILED")
```

Note: `g_defaultSkin` is a file-local; to test it we expose a read-only probe `JournalStylesheet.DefaultSkin()` and reference it as `g_defaultSkin_PROBE` by assigning `local g_defaultSkin_PROBE = JournalStylesheet.DefaultSkin()` at the top of the snippet. Adjust the snippet's first line to:
```lua
local g_defaultSkin_PROBE = JournalStylesheet.DefaultSkin()
```

- [ ] **Step 2: Run the test to verify it fails**

Run `mcp__dmhub__reload_lua`, then `mcp__dmhub__execute_lua` with the snippet above.
Expected: an error like `Attempt to read uninitialized variable JournalStylesheet` (type not yet defined), i.e. NOT `PASS`.

- [ ] **Step 3: Write the implementation**

Insert the following block into `DocumentSystem/MarkdownDocument.lua` immediately after line 14 (the closing `}` of `g_markdownStyle`):

```lua
-- =============================================================================
-- Journal Stylesheets (Plan 1: data model + cascade resolver)
-- A JournalStylesheet re-skins a journal's structural typography (base) and
-- defines named inline/block classes. Stylesheets inherit via parentId, diff-
-- merging down to g_defaultSkin (the built-in root that mirrors today's look).
-- =============================================================================

---@class JournalStylesheet
JournalStylesheet = RegisterGameType("JournalStylesheet")
JournalStylesheet.tableName = "journalStyles"
JournalStylesheet.name = "New Stylesheet"
JournalStylesheet.parentId = nil
-- base/classes default to shared empty tables ONLY as type defaults; Create()
-- always assigns fresh per-instance tables so instances never alias.
JournalStylesheet.base = {}
JournalStylesheet.classes = {}

function JournalStylesheet.Create()
    return JournalStylesheet.new{
        name = "New Stylesheet",
        base = {},
        classes = {},
    }
end

-- The built-in default skin. Values mirror today's g_markdownStyle so a journal
-- with no stylesheet (or one that overrides nothing) renders exactly as it does
-- now. Heading sizes are stored as percentages of body, matching the existing
-- <size=NNN%> markup. The book-faithful "Print" values from the IDML live in a
-- separate authored stylesheet (later plan), NOT here -- the default must stay
-- non-breaking. font names are validated engine faces (gui.availableFonts).
local g_defaultSkin = {
    headings = {
        [1] = { sizePct = 200, font = nil, color = nil, bold = true,  caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [2] = { sizePct = 180, font = nil, color = nil, bold = true,  caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [3] = { sizePct = 160, font = nil, color = nil, bold = true,  caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [4] = { sizePct = 140, font = nil, color = nil, bold = true,  caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [5] = { sizePct = 120, font = nil, color = nil, bold = true,  caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [6] = { sizePct = 120, font = nil, color = nil, bold = true,  caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
    },
    body    = { font = "berling", color = nil, sizePct = 100, lineHeight = nil, paragraphSpacing = nil, firstLineIndent = 0 },
    bullet  = { glyph = "-", glyphFont = nil, color = nil, indent = 0, hangingIndent = 0, spacing = 0 },
    ordered = { color = nil, indent = 0, hangingIndent = 0, spacing = 0 },
    quote   = { font = nil, color = nil, bold = false, italic = false, justify = nil, barColor = nil, inset = 0 },
    rule    = { image = nil, color = nil, thickness = 1, margin = 0 },
    link    = { color = nil, underline = true },
}

-- Read-only accessor (deep copy) so callers/tests cannot mutate the canonical
-- default. DeepCopy is a global utility used throughout the codebase.
function JournalStylesheet.DefaultSkin()
    return DeepCopy(g_defaultSkin)
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run `mcp__dmhub__reload_lua`, then `mcp__dmhub__execute_lua` with the Step-1 snippet (with the `DefaultSkin()` probe line).
Expected output: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): register JournalStylesheet type, table, and default skin"
```

---

## Task 2: Cascade resolver with inheritance, memoization, and cycle defense

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (insert directly after the Task 1 block)

**Interfaces:**
- Consumes: `JournalStylesheet` (Task 1), `g_defaultSkin`, `dmhub.GetTable("journalStyles")`.
- Produces:
  - `ResolveStylesheet(id) -> { base = <merged skin>, classes = <merged classes> }`. `id == nil` or unknown returns the default skin with empty classes. Always returns a fresh table (safe to read). Memoized internally.
  - `ResolveStylesheet.ClearCache()` -- drops the memo (call when the `journalStyles` table changes; consumers wire this to a monitor in a later plan).

- [ ] **Step 1: Write the failing tests (bridge snippet)**

```lua
-- TEST 2: resolver merges a child over the default, follows parentId, and
-- defends against cycles. We build stylesheets in-memory and inject them into a
-- fake table via dmhub.SetAndUploadTableItem so the resolver can find parents.
local ok = true
local function check(cond, msg) if not cond then ok=false print("FAIL: "..msg) end end

-- nil id -> default skin, empty classes
local d = ResolveStylesheet(nil)
check(d.base.headings[1].sizePct == 200, "nil id yields default h1 200%")
check(next(d.classes) == nil, "nil id yields empty classes")

-- a child that overrides only h1 size and adds one class
local child = JournalStylesheet.Create()
child.name = "Child"
child.base = { headings = { [1] = { sizePct = 320 } } }
child.classes = { warning = { kind = "inline", text = { bold = true } } }
local cid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, child)
ResolveStylesheet.ClearCache()
local r = ResolveStylesheet(cid)
check(r.base.headings[1].sizePct == 320, "child overrides h1 size")
check(r.base.headings[2].sizePct == 180, "child inherits h2 from default (180)")
check(r.base.body.font == "berling", "child inherits body font from default")
check(r.classes.warning ~= nil and r.classes.warning.text.bold == true, "child class merged in")

-- grandchild inheriting from child overrides h2 only
local gchild = JournalStylesheet.Create()
gchild.name = "Grandchild"
gchild.parentId = cid
gchild.base = { headings = { [2] = { sizePct = 200 } } }
local gid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, gchild)
ResolveStylesheet.ClearCache()
local g = ResolveStylesheet(gid)
check(g.base.headings[1].sizePct == 320, "grandchild inherits h1 320 from child")
check(g.base.headings[2].sizePct == 200, "grandchild overrides h2 to 200")
check(g.classes.warning ~= nil, "grandchild inherits class from child")

-- cycle defense: point child.parentId at grandchild, expect no infinite loop
child.parentId = gid
dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, child)
ResolveStylesheet.ClearCache()
local cyc = ResolveStylesheet(gid)
check(type(cyc.base) == "table", "cycle resolves to a table without hanging")

-- cleanup
dmhub.DeleteTableItem(JournalStylesheet.tableName, cid)
dmhub.DeleteTableItem(JournalStylesheet.tableName, gid)
print(ok and "PASS" or "TEST FAILED")
```

Note: if `dmhub.DeleteTableItem` is not the correct removal call in this build, set `.hidden = true` and re-upload instead (the codebase's soft-delete convention). Confirm against an existing caller before relying on it; cleanup failure does not affect the assertions.

- [ ] **Step 2: Run the test to verify it fails**

Run `reload_lua`, then `execute_lua` with the snippet.
Expected: error `Attempt to read uninitialized variable ResolveStylesheet`, i.e. NOT `PASS`.

- [ ] **Step 3: Write the implementation**

Insert directly after the Task 1 block:

```lua
-- Deep-merge child over parent for one base-skin sub-section (e.g. body, a
-- single heading level). Child keys win; keys absent in child inherit parent.
local function MergeSection(parent, child)
    local out = {}
    if type(parent) == "table" then
        for k, v in pairs(parent) do out[k] = v end
    end
    if type(child) == "table" then
        for k, v in pairs(child) do out[k] = v end
    end
    return out
end

-- Merge a full base skin: parent is fully-populated, child is sparse (only the
-- keys it overrides). headings is per-level; other sections merge as a unit.
local function MergeSkin(parent, child)
    child = child or {}
    local out = {}
    -- headings: merge each level 1..6 individually
    out.headings = {}
    local ph = (parent and parent.headings) or {}
    local ch = child.headings or {}
    for level = 1, 6 do
        out.headings[level] = MergeSection(ph[level], ch[level])
    end
    -- single-section keys
    for _, key in ipairs({"body", "bullet", "ordered", "quote", "rule", "link"}) do
        out[key] = MergeSection(parent and parent[key], child[key])
    end
    return out
end

-- Merge class dictionaries: child class entries override parent entries by name.
-- Within a class, text/box sub-tables merge child-over-parent.
local function MergeClasses(parent, child)
    local out = {}
    parent = parent or {}
    child = child or {}
    for name, cls in pairs(parent) do out[name] = cls end
    for name, cls in pairs(child) do
        local base = out[name]
        if type(base) == "table" then
            local merged = { kind = cls.kind or base.kind }
            merged.text = MergeSection(base.text, cls.text)
            merged.box  = MergeSection(base.box,  cls.box)
            out[name] = merged
        else
            out[name] = cls
        end
    end
    return out
end

-- Build the inheritance chain from a stylesheet up to (but not including) the
-- default root, outermost-ancestor-first. Defends against cycles with a visited
-- set; a detected cycle is logged once and the chain is truncated there.
local g_loggedStylesheetCycles = {}
local function BuildChain(id)
    local chain = {}
    local visited = {}
    local tbl = dmhub.GetTable(JournalStylesheet.tableName) or {}
    local cur = id
    while cur ~= nil do
        if visited[cur] then
            if not g_loggedStylesheetCycles[cur] then
                g_loggedStylesheetCycles[cur] = true
                print("JOURNAL_STYLESHEET:: parentId cycle detected at " .. tostring(cur))
            end
            break
        end
        visited[cur] = true
        local sheet = tbl[cur]
        if sheet == nil then break end
        chain[#chain + 1] = sheet
        cur = sheet:try_get("parentId")
    end
    -- chain is [self, parent, grandparent, ...]; reverse to root-first
    local rev = {}
    for i = #chain, 1, -1 do rev[#rev + 1] = chain[i] end
    return rev
end

local g_resolveCache = {}

--- Resolve a stylesheet id to a fully-merged { base, classes }. nil/unknown id
--- returns the default skin with empty classes. Result is memoized per id.
--- @param id string|nil
--- @return table { base = table, classes = table }
function ResolveStylesheet(id)
    local key = id or "@default"
    local cached = g_resolveCache[key]
    if cached ~= nil then return cached end

    local base = g_defaultSkin
    local classes = {}
    if id ~= nil then
        local chain = BuildChain(id)
        for _, sheet in ipairs(chain) do
            base = MergeSkin(base, sheet:try_get("base"))
            classes = MergeClasses(classes, sheet:try_get("classes"))
        end
    end
    -- ensure base is fully populated even when id was nil (deep copy default)
    if id == nil then base = MergeSkin(g_defaultSkin, nil) end

    local result = { base = base, classes = classes }
    g_resolveCache[key] = result
    return result
end

function ResolveStylesheet.ClearCache()
    g_resolveCache = {}
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run `reload_lua`, then `execute_lua` with the Step-1 snippet.
Expected output: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): cascade resolver with inheritance, memo, cycle defense"
```

---

## Task 3: Persist styleSheetId on MarkdownDocument and expose a resolved-stylesheet helper

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (add field near line 5; add method after the Task 2 block)

**Interfaces:**
- Consumes: `ResolveStylesheet` (Task 2).
- Produces:
  - `MarkdownDocument.styleSheetId = nil` (default field; auto-serialized, round-trips through document upload).
  - `MarkdownDocument:GetResolvedStylesheet() -> { base, classes }` -- convenience used by the render layer in Plan 2.

- [ ] **Step 1: Write the failing test (bridge snippet)**

```lua
-- TEST 3: documents carry styleSheetId and resolve through it
local ok = true
local function check(cond, msg) if not cond then ok=false print("FAIL: "..msg) end end
local doc = MarkdownDocument.new{ content = "", annotations = {} }
check(doc.styleSheetId == nil, "styleSheetId defaults nil (safe read)")
local rs = doc:GetResolvedStylesheet()
check(rs.base.headings[1].sizePct == 200, "nil styleSheetId resolves to default skin")

-- with a real stylesheet assigned
local s = JournalStylesheet.Create()
s.base = { headings = { [1] = { sizePct = 333 } } }
local sid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, s)
ResolveStylesheet.ClearCache()
doc.styleSheetId = sid
local rs2 = doc:GetResolvedStylesheet()
check(rs2.base.headings[1].sizePct == 333, "assigned styleSheetId resolves through")
dmhub.DeleteTableItem(JournalStylesheet.tableName, sid)
print(ok and "PASS" or "TEST FAILED")
```

- [ ] **Step 2: Run the test to verify it fails**

Run `reload_lua`, then `execute_lua` with the snippet.
Expected: a failure (either `Attempt to read unknown field styleSheetId` if reads are strict before the default is declared, or `FAIL: ...` lines), i.e. NOT `PASS`.

- [ ] **Step 3: Write the implementation**

(a) Add the default field. Find line 5:
```lua
MarkdownDocument.vscroll = false
```
Change it to:
```lua
MarkdownDocument.vscroll = false
-- Id of the JournalStylesheet that re-skins this document. nil = built-in
-- default skin. Auto-serialized; round-trips through document upload.
MarkdownDocument.styleSheetId = nil
```

(b) Add the helper method directly after the Task 2 block:
```lua
--- Resolve this document's stylesheet (or the default skin if unset).
--- @return table { base = table, classes = table }
function MarkdownDocument:GetResolvedStylesheet()
    return ResolveStylesheet(self.styleSheetId)
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run `reload_lua`, then `execute_lua` with the Step-1 snippet.
Expected output: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): add styleSheetId field and GetResolvedStylesheet helper"
```

---

## Self-Review

**Spec coverage (Plan 1 scope only):**
- "New game type + data table" -- Task 1. PASS.
- "Inheritance via parentId, diff-merge to built-in default" -- Task 2 (`BuildChain` + `MergeSkin`/`MergeClasses`). PASS.
- "Memoized per stylesheetId, invalidated when the table changes" -- Task 2 (`g_resolveCache` + `ClearCache`). Invalidation *wiring* (a table monitor) is deferred to Plan 2's consumer, noted there. PASS for the mechanism.
- "parentId cycles broken with a visited-set and logged" -- Task 2 (`BuildChain` visited set, `g_loggedStylesheetCycles`). PASS.
- "MarkdownDocument gains styleSheetId, auto-serialized, round-trips" -- Task 3. PASS.
- "Unknown class / no stylesheet -> graceful fallthrough" -- Task 2 (nil/unknown id returns default skin). PASS.
- Out of Plan-1 scope (correctly deferred): rendering, tokenizer branches, editor UI. Covered by Plans 2-4 below.

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". Every step carries runnable code. The one conditional note (`DeleteTableItem` vs soft-delete) is a verified-at-implementation instruction with a concrete fallback, not a placeholder in shipped code. OK.

**Type consistency:** `ResolveStylesheet(id) -> {base, classes}` used identically in Tasks 2 and 3. `JournalStylesheet.Create()`, `.tableName`, `.base`, `.classes`, `.parentId` consistent across tasks. `g_defaultSkin` shape (`headings[1..6].sizePct`, `body.font`, `bullet.glyph`) matches every assertion. OK.

---

## Roadmap: Plans 2-4 (written after each predecessor lands)

These are scoped here with verified anchors so they can be expanded into full plans. They are NOT implemented by this plan.

### Plan 2 - Base-skin render integration
Make a journal actually re-skin from its resolved `base`.
- Build a per-document `gui.MarkdownStyle` from `resolved.base.headings` instead of the module constant `g_markdownStyle`. Consumption sites to convert: **line 789** (TierRoll label) and **line 1430** (main render-loop text panel) -- both currently `markdownStyle = g_markdownStyle`. Add a `MarkdownDocument:BuildMarkdownStyle(resolved)` that emits `<size=NNN%>`/`<b>`/`<font=...>`/`<cspace=...>`/`<smallcaps>` from each heading entry.
- **Bullets/numbered lists are NOT tokenized** (confirmed): they arrive as plain text lines with `* `/`1. ` prefixes (toolbar `LineHandler("* ")`, line ~3443). To style them, transform these prefixes during text-token rendering using `resolved.base.bullet` (glyph/glyphFont/color/indent). This is the fiddliest task -- isolate it and screenshot-verify.
- **Blockquote** render branch at **lines 1610-1650**: apply `resolved.base.quote` (barColor/inset/font/italic) to the existing `blockQuote` panel.
- **Divider** token (`type = "divider"`, tokenized lines 465-472): apply `resolved.base.rule` (image/color/thickness/margin) where dividers render in the loop.
- Wire cache invalidation: `monitorGame` the `journalStyles` table path -> `ResolveStylesheet.ClearCache()` + refresh. (Mechanism from Plan 1; this plan connects it.)
- Verify: a journal with the default skin looks pixel-identical to today (screenshot diff); a journal pointed at a test stylesheet shows changed heading sizes/bullets/quote/divider.

### Plan 3 - Named classes (inline + block)
- **Inline `{.class text}`**: new brace branch in the brace processor, beside `{!`/`{#`/`{:}`. Insertion point is **line 158** (before `else depth = depth + 1`), inside the `StripSpoilers`/brace function (lines 73-176). Emit the class's `text` rich-text tags (`<color>`, `<size>`, `<b>`, `<cspace>`, `<smallcaps>`, `<mark>`), running `ThemeEngine.ResolveTokens` for `@token` colors. Look the class up in the document's resolved `classes`.
- **Block `:::class ... :::`**: follow the **blockquote precedent, NOT the RichTag rail** (RichTags are inline `[[tag]]` single tokens -- wrong shape for a multi-line wrapper). Add a tokenizer branch in `BreakdownRichTags` (near the blockquote branch, lines 322-353) that emits a new `type = "styleblock"` token carrying `className` + inner `text`. Add a render-loop branch mirroring `type == "blockquote"` (lines 1610-1650): a wrapping `gui.Panel` painted from the class's `box` (bgcolor/bgimage/bgslice/borderImage/border/cornerRadius/pad) containing a nested `gui.MarkdownLabel` styled by the class's `text`. Reuse the `m_blockquotes`-style cache pattern (`m_styleblocks`/`newStyleblocks`).
- Verify: `{.warning be careful}` renders styled inline; `:::read-aloud ... :::` renders a framed panel.

### Plan 4 - Editor UI + journal picker
- **Stylesheet editor**: model on `ShowConditionsPanel` (`DMHub Compendium/Compendium.lua:672-731`) + `Condition.lua:567` `CreateEditor`/`SetData` populate pattern; form fields via `formStackedRow` + `gui.Input`/`gui.Dropdown` with `change -> set field -> dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, sheet)` (Condition.lua:172-186, 252-267). Surface it in the Compendium category list. Host file: `Compendium.lua` (where similar show-functions live) + `JournalStylesheet.CreateEditor()` method added to `MarkdownDocument.lua` (no-new-files).
- **Journal picker**: add a `gui.Dropdown` (options from `dmhub.GetTable("journalStyles")`, `idChosen = self.styleSheetId`) into the markdown editor host near `editInput` (`MarkdownDocument.lua:3165`). On change, set `self.styleSheetId`, set the preview doc's id too (`previewDoc.styleSheetId`, line 3223), and fire `editDocument`/`refreshDocument` so the preview re-renders.
- Verify: create a stylesheet in the editor, assign it to a journal via the picker, see the journal re-skin live.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-17-journal-stylesheets-foundation.md`. This is Plan 1 of 4 (the foundation); Plans 2-4 are scoped in the roadmap and will be written as full plans once their predecessor lands and the real API is in hand.

Two execution options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration. Note: subagents will need the DMHub MCP bridge (`reload_lua`/`execute_lua`) to run the verification snippets, and DMHub must stay running.

2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?
