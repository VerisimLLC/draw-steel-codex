# Journal Page Background Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single whole-journal page background color to the stylesheet base skin -- paint the journal's content panel from `base.page.bgcolor` at render, and add a "Page background" color row to the stylesheet editor.

**Architecture:** Extend the existing journal-stylesheet system (all in `DocumentSystem/MarkdownDocument.lua`). Add a `page` section to the built-in default skin and to the resolver's merge list (so it inherits like other base sections); paint the content container from the resolved `page.bgcolor` in the render path that already computes `resolvedSkin` (re-applied live by the existing table monitor); add an editor row using the existing `JSE_ColorRow` helper.

**Tech Stack:** DMHub Lua mod; the Plan 1-4 stylesheet system (`ResolveStylesheet`, `g_defaultSkin`, `JournalStyleEditor_BuildForm`, `JSE_ColorRow`, `SkinColor`, `ownBaseSection`); gui panel `bgcolor`/`bgimage`. Verification via the DMHub MCP bridge (`execute_lua` + `screenshot`).

## Global Constraints

- **ASCII only.** Every byte (code and comments) 0-127. No em dashes, curly quotes, ellipses.
- **No new files.** All code in `DocumentSystem/MarkdownDocument.lua`. Do not touch `main.lua`.
- **No CLI test runner.** Logic: `reload_lua` then `execute_lua` asserting `PASS`/`FAIL`. Render/editor: `reload_lua`, render via the bridge, `screenshot`, Read the image.
- **Default skin stays a visual no-op.** `base.page.bgcolor` defaults to `false` (the codebase's optional-value sentinel); a journal with no page background must render exactly as today.
- **Unset clears, set paints.** When `page.bgcolor` is unset/false, the render must CLEAR the content panel's `bgimage`/`bgcolor` (set nil) so a reused panel keeps no stale background.
- **`@token` colors** resolve via `SkinColor` (which calls `ThemeEngine.ResolveTokens`); literal hex passes through.
- **Contrast is the author's responsibility.** No auto-contrast logic; the author sets text colors via the existing fields.
- **Forward-declare self-referencing locals.** Panels using pad set `borderBox = true`.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `DocumentSystem/MarkdownDocument.lua` | Stylesheet schema, resolver, render, editor | Modify only |

Verified anchors:
- `g_defaultSkin` table: lines 53-68 (ends at the `}` on line 68; `link = {...}` is the last section at line 67).
- Resolver merge section list: line 106 -- `for _, key in ipairs({"body", "bullet", "ordered", "quote", "rule", "link"}) do`.
- Render resolve point: lines 1798-1800 -- `local resolvedStylesheet = self:GetResolvedStylesheet()` / `resolvedSkin` / `resolvedClasses`, inside the document render handler where `element` is the content panel that owns the rendered `children`. The `for i, token in ipairs(tokens)` loop starts at line 1801.
- Editor base-skin body row: line 391 -- `children[#children+1] = JSE_ColorRow("  Color:", (resolvedBase.body or {}).color, function(c) ownBaseSection("body").color = c; upload() end)` (inside `JournalStyleEditor_BuildForm`; `ownBaseSection`/`resolvedBase` are in scope there).
- `SkinColor` helper: line ~486. `JSE_ColorRow` helper: line ~283.

---

## Task 1: Schema, resolver merge, and render the page background

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (default skin line 68; merge list line 106; render application after line 1800)

**Interfaces:**
- Consumes: `g_defaultSkin`, the resolver's `MergeSkin`, `SkinColor`, the render's `resolvedSkin` + `element`.
- Produces: `resolvedSkin.page.bgcolor` is carried/inherited by `ResolveStylesheet`; a journal whose resolved skin has a page bgcolor paints its content panel.

- [ ] **Step 1: Write the failing test (bridge snippet)**

```lua
local ok=true local function ck(c,m) if not c then ok=false print("FAIL: "..m) end end
-- default skin has a page section with bgcolor false (no-op)
local d = JournalStylesheet.DefaultSkin()
ck(type(d.page) == "table", "default skin has a page section")
ck(d.page.bgcolor == false, "default page bgcolor is false (unset)")
-- resolver carries an explicit page bgcolor, and it inherits like other sections
local parent = JournalStylesheet.Create()
parent.base = { page = { bgcolor = "#efe8d6" } }
local pid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, parent)
ResolveStylesheet.ClearCache()
ck(ResolveStylesheet(pid).base.page.bgcolor == "#efe8d6", "resolver carries page bgcolor")
local child = JournalStylesheet.Create()
child.parentId = pid
child.base = { headings = { [1] = { sizePct = 250 } } }
local cid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, child)
ResolveStylesheet.ClearCache()
ck(ResolveStylesheet(cid).base.page.bgcolor == "#efe8d6", "child inherits page bgcolor from parent")
dmhub.ObliterateTableItem(JournalStylesheet.tableName, pid)
dmhub.ObliterateTableItem(JournalStylesheet.tableName, cid)
print(ok and "PASS" or "TEST FAILED")
```

- [ ] **Step 2: Run to verify it fails**

`reload_lua`, `execute_lua`. Expected: the `d.page` assertions FAIL (no page section yet) and/or the resolver returns no page section -- not `PASS`.

- [ ] **Step 3: Implement schema + merge + render**

(a) Add the `page` section to `g_defaultSkin`. After the `link` line (line 67) and before the closing `}` (line 68), add:

```lua
    link    = { color = nil, underline = true },
    page    = { bgcolor = false },
}
```

(So the table now ends `... link = {...}, page = { bgcolor = false }, }`.)

(b) Add `"page"` to the resolver merge section list at line 106:

```lua
    for _, key in ipairs({"body", "bullet", "ordered", "quote", "rule", "link", "page"}) do
```

(c) Paint the content panel in the render. Immediately AFTER line 1800 (`local resolvedClasses = resolvedStylesheet.classes`) and BEFORE the `for i, token in ipairs(tokens) do` loop, add:

```lua
            -- Page background: paint the content container from the resolved skin.
            -- Re-runs every render (including live stylesheet edits via the monitor).
            -- Unset clears it so a reused panel keeps no stale background and the
            -- default skin stays a visual no-op.
            local pageColor = SkinColor((resolvedSkin.page or {}).bgcolor)
            if pageColor then
                element.bgimage = "panels/square.png"
                element.bgcolor = pageColor
            else
                element.bgimage = nil
                element.bgcolor = nil
            end
```

- [ ] **Step 4: Run the test to verify it passes**

`reload_lua`, `execute_lua` with the Step-1 snippet. Expected: `PASS`.

- [ ] **Step 5: Screenshot check (render + no-op)**

`reload_lua`. (a) Render a doc with a page-background stylesheet and confirm the page color shows behind the content; (b) render a doc with NO stylesheet and confirm it looks like today (no background). Harness:

```lua
pcall(function() gamehud:CloseModal() end)
local s = JournalStylesheet.Create(); s.name = "PAGEBG"
s.base = { page = { bgcolor = "#efe8d6" }, headings = { [1] = { color = "#222222" } }, body = { color = "#222222" } }
local sid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, s)
ResolveStylesheet.ClearCache()
local doc = MarkdownDocument.new{ content = "# Chapter One\nDark text on a cream page.", annotations = {} }
doc.styleSheetId = sid
local docPlain = MarkdownDocument.new{ content = "# Chapter One\nPlain default.", annotations = {} }
local panel = gui.Panel{ id="pagebg", bgimage="panels/square.png", bgcolor="#444444",
  width=560, height=320, halign="center", valign="center", flow="vertical", pad=16, borderBox=true, vmargin=4,
  click=function() gamehud:CloseModal() end,
  children={ doc:DisplayPanel{ width="100%", height="auto" }, docPlain:DisplayPanel{ width="100%", height="auto" } } }
gamehud:ShowModal(panel)
print("shown sid="..sid)
```

`screenshot`, Read it: the first doc shows dark text on a cream page; the second (no stylesheet) shows the grey wrapper through it (no page bg). Clean up: `dmhub.ObliterateTableItem(JournalStylesheet.tableName, sid)`, `gamehud:CloseModal()`. Report what you saw.

- [ ] **Step 6: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): whole-journal page background from base.page.bgcolor"
```

---

## Task 2: Editor "Page background" row

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (`JournalStyleEditor_BuildForm`, near the body row at line 391)

**Interfaces:**
- Consumes: `JSE_ColorRow`, `ownBaseSection`, `resolvedBase` (all in scope in `JournalStyleEditor_BuildForm`).
- Produces: a "Page background" color control that writes `sheet.base.page.bgcolor`.

- [ ] **Step 1: Implement the editor row**

In `JournalStyleEditor_BuildForm`, find the Body section (the `gui.Label{ ..., text = "Body" }` header and the body color row at line 391). Immediately AFTER the body color row, add a Page section:

```lua
    children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "Page" }
    children[#children+1] = JSE_ColorRow("  Background:", (resolvedBase.page or {}).bgcolor, function(c)
        ownBaseSection("page").bgcolor = c; upload()
    end)
```

(`ownBaseSection("page")` lazily creates `sheet.base.page` and returns it, same as the other sections. `JSE_ColorRow` already converts the picked Color to a hex string.)

- [ ] **Step 2: Screenshot check**

`reload_lua`. Create a stylesheet, open its editor via the bridge harness (`local ed = JournalStylesheet.CreateEditor(); ed.data.SetData(JournalStylesheet.tableName, sid)`, show in a modal), `screenshot`, Read it: a "Page" section with a "Background:" color row appears (after Body). Then drive its onset to set a cream bgcolor and upload; with a journal assigned that sheet rendered in a second modal, confirm the journal's page turns cream live (the monitor). Programmatic alt if the row is scrolled off: walk the editor children and assert a label "Page" and a "  Background:" row exist; then set `sheet.base.page.bgcolor` via the onset and confirm `ResolveStylesheet(sid).base.page.bgcolor` updated. Report observations. Clean up.

- [ ] **Step 3: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): Page background color row in the stylesheet editor"
```

---

## Self-Review

**Spec coverage:**
- "Schema: `base.page = { bgcolor }`" -- Task 1 Step 3a (default skin) + 3b (merge). PASS.
- "Render: paint when set, clear when unset, re-applied live" -- Task 1 Step 3c (in the resolve path that re-runs each render). PASS.
- "Editor: Page background row near Body" -- Task 2. PASS.
- "Default skin visual no-op" -- `bgcolor = false` default + the clear-when-unset branch; Task 1 Step 5(b) verifies. PASS.
- "Inherits like other base sections" -- Task 1 Step 3b adds `page` to the merge list; Step 1 test asserts inheritance. PASS.
- "Contrast = author's job, no auto logic" -- honored (no contrast code; the harness sets text colors explicitly). PASS.
- "Texture/image out of scope" -- only `bgcolor` added. PASS.

**Placeholder scan:** No TBD/vague items. The Task 2 "programmatic alt" is a concrete fallback for a scrolled-off control, not a placeholder.

**Type consistency:** `base.page.bgcolor`, `resolvedSkin.page`, `resolvedBase.page`, `ownBaseSection("page")`, `SkinColor` used consistently. `bgcolor = false` sentinel matches `SkinColor` (returns nil for false). Merge-list key `"page"` matches the schema key.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-18-journal-page-background.md`.

Two execution options:

1. **Subagent-Driven (recommended)** - fresh implementer per task + spec/quality review between tasks. DMHub running for the bridge.
2. **Inline Execution** - execute the two tasks here with checkpoints.

Which approach?
