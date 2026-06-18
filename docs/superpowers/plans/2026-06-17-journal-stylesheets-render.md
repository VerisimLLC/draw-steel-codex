# Journal Stylesheets - Base-Skin Render Integration (Plan 2 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a journal actually re-skin its structural typography from its resolved stylesheet -- headings, body, bullets/ordered lists, blockquotes, and dividers -- by injecting inline TextMeshPro markup derived from the resolved skin at render time, and re-render live when the stylesheet changes.

**Architecture:** A live spike proved that swapping a `gui.MarkdownStyle` object does NOT restyle headings or bullets (the engine appears to intern style objects, and it renders bullets with its own glyph), but **inline TMP markup (`<size>`, `<color>`, `<b>`, `<cspace>`) renders reliably**. So Plan 2 preprocesses text: a pure `ApplySkinToText(text, base)` walks each line of a text token and injects skin-derived inline markup (stripping the markdown prefix it replaces), wired in at the single point where body text reaches its label. Blockquote and divider are styled on their existing panels. The built-in default skin is engineered so the transform is a visual no-op -- unstyled journals render exactly as today.

**Tech Stack:** DMHub Lua mod runtime; the Plan 1 resolver (`ResolveStylesheet` / `MarkdownDocument:GetResolvedStylesheet`); TextMeshPro inline rich-text; `ThemeEngine.ResolveTokens` for `@token` colors. Verification via the DMHub MCP bridge (`reload_lua` + `execute_lua` for pure-logic tests; `screenshot` for render tests) -- the project has no command-line test runner.

## Global Constraints

- **ASCII only.** Every byte in `MarkdownDocument.lua` (code and comments) must be 0-127. No em dashes, curly quotes, ellipses.
- **No new files.** All code in `DocumentSystem/MarkdownDocument.lua`. Do not touch `main.lua`.
- **No CLI test runner.** Pure-logic tasks: `reload_lua` then `execute_lua` with an assertion snippet printing `PASS`/`FAIL`. Render tasks: `reload_lua`, render a document, `screenshot`, and read the image to confirm.
- **The default skin must render visually identical to today.** `ApplySkinToText(text, defaultBase)` must produce output that renders the same as the input does now. This is the regression guard for every task: a journal with no stylesheet must not change.
- **Build on Plan 1, do not modify it.** Consume `MarkdownDocument:GetResolvedStylesheet() -> { base, classes }` and the `base` schema (`headings[1..6] = {sizePct, font, color, weight, caps, tracking, spaceBefore, spaceAfter}`, `body = {font, color, sizePct, lineHeight, paragraphSpacing, firstLineIndent}`, `bullet = {glyph, glyphFont, color, indent, hangingIndent, spacing}`, `ordered = {color, indent, hangingIndent, spacing}`, `quote = {font, color, weight, italic, justify, barColor, inset}`, `rule = {image, color, thickness, margin}`, `link = {color, underline}`). `weight` is a string (`"regular"`/`"bold"`/`"black"`); the default skin's headings use `"bold"`.
- **Forward-declare self-referencing locals.**
- **`@token` colors:** any color value may be an `@token` (e.g. `@danger`); resolve with `ThemeEngine.ResolveTokens(str)` before emitting. Literal hex (`#rrggbb`) passes through unchanged.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `DocumentSystem/MarkdownDocument.lua` | Markdown document type, resolver (Plan 1), rendering | Modify only |

Verified anchors (current line numbers, post-Plan-1):
- Resolver + default skin + `GetResolvedStylesheet`: lines ~22-230 (Plan 1).
- `g_markdownStyle` definition: lines 13-20. Its heading keys (`# ` -> `<size=200%><b>` etc.) are the exact markup the default skin must reproduce.
- Body text label creation: line 1618 (`local textPanel = ... or gui.Label{ classes={"fg"}, markdown=true, markdownStyle = g_markdownStyle, ... }`).
- **Body text application point: line 1769 (`textPanel.text = text`)** -- the single place a text token's text reaches its label. This is where `ApplySkinToText` is wired in.
- Text token shape: `{ type="text", text=<multi-line string>, justification, player }` (emitted by `EmitText`, line 407). A text token's `.text` contains `\n`-separated lines that may include `# ...` headings, `- ...`/`* ...` bullets, `1. ...` ordered items, and body lines.
- Token render loop: `for i, token in ipairs(tokens)` inside the document's render function. The resolved skin is computed ONCE just before this loop.
- Divider render: line 1328 (`elseif token.type == "divider"`, builds `gui.Divider{...}`).
- Blockquote render: line 1806 (`elseif token.type == "blockquote"`, builds `gui.Panel{ classes={"blockQuote"}, ... gui.MarkdownLabel{...} }`).

---

## Task 1: `ApplySkinToText` -- heading and body markup (pure transformer)

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (add a file-local function after the Plan 1 resolver block, before the document render code)

**Interfaces:**
- Consumes: a resolved `base` skin table (Plan 1 shape); `ThemeEngine.ResolveTokens`.
- Produces: file-local `ApplySkinToText(text, base) -> string`. Splits `text` on `\n`, transforms each line, rejoins with `\n`. This task handles heading lines (`^#{1,6} `) and body lines. Bullets/ordered are added in Task 3 (until then they pass through unchanged). Exposed for tests via `MarkdownDocument.__ApplySkinToText = ApplySkinToText`.

- [ ] **Step 1: Write the failing test (bridge snippet)**

```lua
local f = MarkdownDocument.__ApplySkinToText
local base = JournalStylesheet.DefaultSkin()
local ok=true local function ck(c,m) if not c then ok=false print("FAIL: "..m) end end
-- default skin reproduces today's heading markup exactly (size 200% + bold), prefix stripped
ck(f("# Title", base) == "<size=200%><b>Title</b></size>", "h1 default -> 200% bold, # stripped")
ck(f("## Sub", base) == "<size=180%><b>Sub</b></size>", "h2 default -> 180% bold")
-- body line unchanged under default (visual no-op invariant)
ck(f("plain body line", base) == "plain body line", "default body line unchanged")
-- multi-line preserved
ck(f("# A\nbody\n## B", base) == "<size=200%><b>A</b></size>\nbody\n<size=180%><b>B</b></size>", "multiline")
-- a custom skin: size 320, black weight, gold color, allcaps
local custom = JournalStylesheet.DefaultSkin()
custom.headings[1] = { sizePct=320, weight="black", color="#c9a84a", caps="allcaps", tracking=0 }
ck(f("# chapter", custom) == "<size=320%><b><color=#c9a84a>CHAPTER</color></b></size>", "custom h1: size+black->b+color+allcaps")
-- @token color resolves
local tok = JournalStylesheet.DefaultSkin()
tok.headings[1] = { sizePct=200, weight="bold", color="@danger" }
local out = f("# x", tok)
ck(out:find("<color=#") ~= nil and out:find("@danger") == nil, "h1 @token color resolved to hex")
print(ok and "PASS" or "TEST FAILED")
```

- [ ] **Step 2: Run the test to verify it fails**

`reload_lua`, then `execute_lua` with the snippet. Expected: error `attempt to index a nil value (field '__ApplySkinToText')` -- not `PASS`.

- [ ] **Step 3: Write the implementation**

Insert after the Plan 1 resolver block (after `MarkdownDocument:GetResolvedStylesheet`), before the render code:

```lua
-- =============================================================================
-- Skin -> inline markup (Plan 2). A live spike showed gui.MarkdownStyle swaps do
-- not restyle headings/bullets, but inline TMP markup renders reliably. So we
-- inject skin-derived markup per line. The DEFAULT skin is tuned so this is a
-- visual no-op (unstyled journals render exactly as before).
-- =============================================================================

-- Resolve an optional color value (literal hex or @token) to a hex string, or
-- nil if unset. ThemeEngine.ResolveTokens turns "@danger" into "#rrggbb".
local function SkinColor(c)
    if c == nil or c == false or c == "" then return nil end
    return ThemeEngine.ResolveTokens(c)
end

-- Build the open/close markup pair for a heading level from its skin entry, and
-- return the (possibly case-transformed) content.
local function SkinHeadingMarkup(h, content)
    h = h or {}
    local open, close = "", ""
    if h.sizePct and h.sizePct ~= 100 then
        open = open .. string.format("<size=%d%%>", h.sizePct)
        close = "</size>" .. close
    end
    -- weight: "bold" or "black" both map to <b> (TMP has no separate black face
    -- in the current font catalog); "regular" emits nothing.
    if h.weight == "bold" or h.weight == "black" then
        open = open .. "<b>"
        close = "</b>" .. close
    end
    local tracking = h.tracking or 0
    if tracking ~= 0 then
        -- InDesign tracking is 1/1000 em; TMP <cspace> takes em. -20 -> -0.02em.
        open = open .. string.format("<cspace=%.3fem>", tracking / 1000)
        close = "</cspace>" .. close
    end
    local color = SkinColor(h.color)
    if color then
        open = open .. string.format("<color=%s>", color)
        close = "</color>" .. close
    end
    if h.caps == "allcaps" then
        content = string.upper(content)
    elseif h.caps == "smallcaps" then
        open = open .. "<smallcaps>"
        close = "</smallcaps>" .. close
    end
    return open .. content .. close
end

-- Wrap a body line per the body skin. Only emits markup for explicitly-set,
-- non-default values so the default skin stays a visual no-op.
local function SkinBodyMarkup(body, content)
    body = body or {}
    local open, close = "", ""
    local color = SkinColor(body.color)
    if color then
        open = open .. string.format("<color=%s>", color)
        close = "</color>" .. close
    end
    return open .. content .. close
end

local ApplySkinToText
ApplySkinToText = function(text, base)
    if type(text) ~= "string" or text == "" then return text end
    base = base or {}
    local out = {}
    -- Split on \n preserving structure; gmatch with a trailing sentinel keeps
    -- empty lines and a possible empty final segment.
    local start = 1
    local lines = {}
    while true do
        local nl = string.find(text, "\n", start, true)
        if nl == nil then
            lines[#lines + 1] = string.sub(text, start)
            break
        end
        lines[#lines + 1] = string.sub(text, start, nl - 1)
        start = nl + 1
    end
    for _, line in ipairs(lines) do
        local hashes, content = string.match(line, "^(#+) (.*)$")
        if hashes ~= nil and #hashes >= 1 and #hashes <= 6 then
            local level = #hashes
            out[#out + 1] = SkinHeadingMarkup((base.headings or {})[level], content)
        else
            out[#out + 1] = SkinBodyMarkup(base.body, line)
        end
    end
    return table.concat(out, "\n")
end

-- Test hook (no _tmp_ needed; this is a class-level function reference).
MarkdownDocument.__ApplySkinToText = ApplySkinToText
```

- [ ] **Step 4: Run the test to verify it passes**

`reload_lua`, then `execute_lua` with the Step-1 snippet. Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): ApplySkinToText heading/body inline-markup transformer"
```

---

## Task 2: Wire the transformer into the render path

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (compute resolved skin once before the token loop; transform at line 1769)

**Interfaces:**
- Consumes: `ApplySkinToText` (Task 1), `MarkdownDocument:GetResolvedStylesheet`.
- Produces: rendered journals whose headings reflect their stylesheet. No new exported symbol.

- [ ] **Step 1: Add the resolved-skin computation before the token loop**

Find the token render loop `for i, token in ipairs(tokens) do` (inside the document render function). Immediately BEFORE it, add:

```lua
            -- Plan 2: resolve this document's skin once per render. Memoized in
            -- the resolver, so re-calling per token would also be cheap, but we
            -- hoist it for clarity and to thread into text/divider/quote.
            local resolvedSkin = self:GetResolvedStylesheet().base
```

(If the loop body is a deeply nested closure where `self` is not in scope, compute it at the top of the render function where `self` is available and capture it as an upvalue. Confirm `self` resolves to the `MarkdownDocument` in this scope before proceeding; if it does not, report BLOCKED with the scope you found.)

- [ ] **Step 2: Transform the text at the application point**

At line 1769, the code currently reads:

```lua
                    textPanel.text = text
```

Change it to:

```lua
                    textPanel.text = ApplySkinToText(text, resolvedSkin)
```

Leave the label's `markdownStyle = g_markdownStyle` as-is: after transformation no `# ` prefixes remain, so the style's heading keys never fire and cannot conflict; `markdown = true` still handles inline `**bold**`, links, etc.

- [ ] **Step 3: Verify the default-skin journal is unchanged (screenshot regression)**

`reload_lua`. Then render a document with headings and body through the bridge and screenshot. Use this harness (renders a `MarkdownDocument` preview panel in a modal):

```lua
pcall(function() gamehud:CloseModal() end)
local doc = MarkdownDocument.new{ content = "# Chapter One\nBody paragraph text.\n## A Subhead\nMore body.", annotations = {} }
local panel = gui.Panel{ id="p2test", bgimage="panels/square.png", bgcolor="#15110bff",
  borderColor="#8a7544", borderWidth=2, width=640, height=380, halign="center", valign="center",
  flow="vertical", pad=20, borderBox=true, click=function() gamehud:CloseModal() end,
  children={ doc:DisplayPanel{ width="100%", height="auto" } } }
gamehud:ShowModal(panel)
print("shown")
```

`screenshot` and read it: headings render larger+bold, body normal -- i.e. exactly as a journal looks today. (Default skin = no visual change.)

- [ ] **Step 4: Verify a custom skin restyles headings (screenshot)**

```lua
pcall(function() gamehud:CloseModal() end)
local s = JournalStylesheet.Create()
s.base = { headings = { [1] = { sizePct=320, weight="black", color="#c9a84a", caps="allcaps" } } }
local sid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, s)
ResolveStylesheet.ClearCache()
local doc = MarkdownDocument.new{ content = "# Chapter One\nBody paragraph text.", annotations = {} }
doc.styleSheetId = sid
local panel = gui.Panel{ id="p2test2", bgimage="panels/square.png", bgcolor="#15110bff",
  borderColor="#8a7544", borderWidth=2, width=640, height=300, halign="center", valign="center",
  flow="vertical", pad=20, borderBox=true, click=function() gamehud:CloseModal() end,
  children={ doc:DisplayPanel{ width="100%", height="auto" } } }
gamehud:ShowModal(panel)
print("shown sid="..sid)
```

`screenshot` and read it: "CHAPTER ONE" renders large and gold (uppercase). Then clean up: `dmhub.ObliterateTableItem(JournalStylesheet.tableName, sid)` and `gamehud:CloseModal()`. Put the observed result in your report.

- [ ] **Step 5: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): apply resolved skin to body text at render time"
```

---

## Task 3: Bullets and ordered lists in `ApplySkinToText`

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (extend `ApplySkinToText`'s per-line branch)

**Interfaces:**
- Consumes: `base.bullet`, `base.ordered`.
- Produces: `ApplySkinToText` now also transforms `^[-*] ` (unordered) and `^%d+%. ` (ordered) lines. Default skin (glyph `"-"`, no color/indent) leaves them unchanged.

- [ ] **Step 1: Write the failing test (bridge snippet)**

```lua
local f = MarkdownDocument.__ApplySkinToText
local ok=true local function ck(c,m) if not c then ok=false print("FAIL: "..m) end end
-- default: bullets/ordered unchanged (visual no-op invariant)
local base = JournalStylesheet.DefaultSkin()
ck(f("- item", base) == "- item", "default unordered unchanged")
ck(f("* item", base) == "* item", "default star bullet unchanged")
ck(f("1. item", base) == "1. item", "default ordered unchanged")
-- custom bullet: gold glyph replacing the marker
local c = JournalStylesheet.DefaultSkin()
c.bullet = { glyph = ">", color = "#c9a84a", indent = 0 }
ck(f("- item", c) == "<color=#c9a84a>></color> item", "custom unordered: colored glyph + content")
ck(f("* item", c) == "<color=#c9a84a>></color> item", "star marker also restyled")
-- ordered color only
local o = JournalStylesheet.DefaultSkin()
o.ordered = { color = "#5ae0a0" }
ck(f("2. item", o) == "<color=#5ae0a0>2.</color> item", "ordered: colored number")
print(ok and "PASS" or "TEST FAILED")
```

- [ ] **Step 2: Run to verify it fails**

`reload_lua`, `execute_lua`. Expected: the bullet/ordered assertions FAIL (currently those lines pass through as body), not `PASS`.

- [ ] **Step 3: Extend the implementation**

In `ApplySkinToText`, replace the per-line `if hashes ... else body` block with one that also handles bullets and ordered lists. The new per-line body:

```lua
    for _, line in ipairs(lines) do
        local hashes, hContent = string.match(line, "^(#+) (.*)$")
        local bmarker, bContent = string.match(line, "^([%-%*]) (.*)$")
        local onum, oContent = string.match(line, "^(%d+%.) (.*)$")
        if hashes ~= nil and #hashes >= 1 and #hashes <= 6 then
            out[#out + 1] = SkinHeadingMarkup((base.headings or {})[#hashes], hContent)
        elseif bmarker ~= nil then
            out[#out + 1] = SkinBulletMarkup(base.bullet, bContent)
        elseif onum ~= nil then
            out[#out + 1] = SkinOrderedMarkup(base.ordered, onum, oContent)
        else
            out[#out + 1] = SkinBodyMarkup(base.body, line)
        end
    end
```

And add the two helpers next to `SkinBodyMarkup`:

```lua
-- Unordered bullet. Default skin (glyph "-", no color/indent) reproduces the
-- original "- content" so unstyled journals are unchanged.
local function SkinBulletMarkup(bullet, content)
    bullet = bullet or {}
    local glyph = bullet.glyph
    if glyph == nil or glyph == false or glyph == "" then glyph = "-" end
    local color = SkinColor(bullet.color)
    local indent = bullet.indent or 0
    local prefix
    if color then
        prefix = string.format("<color=%s>%s</color>", color, glyph)
    else
        prefix = glyph
    end
    local line = prefix .. " " .. content
    if indent and indent ~= 0 then
        line = string.format("<indent=%dpx>%s</indent>", indent, line)
    end
    return line
end

-- Ordered list item. `marker` is the literal "N." token. Default = unchanged.
local function SkinOrderedMarkup(ordered, marker, content)
    ordered = ordered or {}
    local color = SkinColor(ordered.color)
    local indent = ordered.indent or 0
    local prefix
    if color then
        prefix = string.format("<color=%s>%s</color>", color, marker)
    else
        prefix = marker
    end
    local line = prefix .. " " .. content
    if indent and indent ~= 0 then
        line = string.format("<indent=%dpx>%s</indent>", indent, line)
    end
    return line
end
```

(Declare `SkinBulletMarkup`/`SkinOrderedMarkup` ABOVE `ApplySkinToText`, like the other Skin* helpers.)

- [ ] **Step 4: Run to verify it passes**

`reload_lua`, `execute_lua` with the Step-1 snippet. Expected: `PASS`. Also re-run Task 1's snippet to confirm no regression (headings/body still pass).

- [ ] **Step 5: Screenshot check**

Render a doc with `content = "- alpha\n- beta\n1. one\n2. two"` under a custom bullet skin (`glyph=">"`, `color="#c9a84a"`) using the Task 2 Step-4 harness shape. `screenshot`, read it, confirm gold `>` markers. Clean up the stylesheet row and modal.

- [ ] **Step 6: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): skin bullets and ordered lists via inline markup"
```

---

## Task 4: Blockquote (quote) and divider (rule) styling

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (blockquote branch line 1806; divider branch line 1328)

**Interfaces:**
- Consumes: `resolvedSkin.quote`, `resolvedSkin.rule` (available from the Task 2 hoist).
- Produces: blockquote inner text styled by `quote`; divider styled by `rule`.

- [ ] **Step 1: Style the blockquote inner text**

The blockquote (line 1806) wraps a `gui.MarkdownLabel` whose text is set via the `markdownText` event (line 1831, `element.text = text`, fed by `blockquote:FireEventTree("markdownText", token.text)` at 1842). Apply the quote skin by transforming the fed text. Change line 1842 from:

```lua
                    blockquote:FireEventTree("markdownText", token.text)
```

to:

```lua
                    blockquote:FireEventTree("markdownText", SkinQuoteText(resolvedSkin.quote, token.text))
```

Add a `SkinQuoteText` helper next to the other Skin* helpers (Task 1 region):

```lua
-- Wrap blockquote body text per the quote skin (color/italic). Default skin
-- (no color, italic=false) returns the text unchanged.
local function SkinQuoteText(quote, content)
    quote = quote or {}
    if type(content) ~= "string" then return content end
    local open, close = "", ""
    local color = SkinColor(quote.color)
    if color then open = open .. string.format("<color=%s>", color); close = "</color>" .. close end
    if quote.italic == true then open = open .. "<i>"; close = "</i>" .. close end
    return open .. content .. close
end
```

(If `resolvedSkin` is not in scope at line 1842, hoist its computation per Task 2 Step 1 so it is. The bar color / inset on the `blockQuote` class are a CSS concern deferred to Plan 4's editor + theme work; this task styles the text only.)

- [ ] **Step 2: Style the divider**

The divider (line 1334) is `gui.Divider{ tmargin=0, bmargin=0, valign="top", width="100%" }`. `gui.Divider` has no LuaLS stub, so its stylable props are uncertain. Before writing the change, SPIKE it through the bridge: render a `gui.Divider` and try setting `bgcolor`, `height`, `tmargin`/`bmargin`, and read back which stick. Then apply only the `rule` fields that the spike confirms work, e.g.:

```lua
                    local divider = m_dividers[#newDividers + 1] or gui.Divider {
                        tmargin = 0,
                        bmargin = 0,
                        valign = "top",
                        width = "100%",
                    }
                    -- Plan 2: apply rule skin (only spike-confirmed props).
                    local rule = resolvedSkin.rule or {}
                    if rule.color then divider.selfStyle.bgcolor = SkinColor(rule.color) end
                    if rule.thickness then divider.selfStyle.height = rule.thickness end
                    if rule.margin then divider.selfStyle.tmargin = rule.margin; divider.selfStyle.bmargin = rule.margin end
```

If the spike shows `gui.Divider` ignores these, report DONE_WITH_CONCERNS describing what it ignored, and leave the divider unstyled (default skin sets none of these, so default rendering is unaffected regardless). Do not invent props.

- [ ] **Step 3: Verify (screenshot)**

`reload_lua`. Render a doc with `content = "> A read-aloud line.\n\n---\n\nAfter the rule."` under (a) the default skin -- confirm it looks like today; then (b) a custom skin with `quote = { color="#c9a84a", italic=true }` and `rule = { color="#8a7544", thickness=3 }` -- confirm the quote text is gold italic and the divider is a thicker gold line (to the extent the divider spike allowed). Clean up.

- [ ] **Step 4: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): style blockquote text and divider from skin"
```

---

## Task 5: Live re-render when the stylesheet changes

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (wire cache invalidation + refresh into the document display panel)

**Interfaces:**
- Consumes: `ResolveStylesheet.ClearCache`, `dmhub.GetTable("journalStyles")`.
- Produces: an open journal re-renders when any `journalStyles` entry changes (editor edits in Plan 4 take effect live).

- [ ] **Step 1: Add a table monitor to the document display panel**

The resolver memoizes, so after a stylesheet edit the cache is stale until cleared. Find the top-level panel returned by the document's `DisplayPanel` (the panel that owns the token render). Add a `monitorGame` on the `journalStyles` table path plus a `refreshGame` that clears the cache and re-renders. Use the table's monitor path (the standard pattern is `dmhub.GetTableMonitorPath(tableName)`; if that helper does not exist in this build, confirm the correct path accessor before proceeding -- search existing `monitorGame` users of a `GetTable` table). Add to the display panel args:

```lua
        monitorGame = dmhub.GetTableMonitorPath(JournalStylesheet.tableName),
        refreshGame = function(element)
            ResolveStylesheet.ClearCache()
            element:FireEvent("refreshDocument", self)
        end,
```

(Confirm the document panel already responds to `refreshDocument` by re-running its token render -- the editor preview at line ~3240 uses `refreshDocument` for exactly this. If the top-level panel needs a different re-render trigger, use the one the existing code uses to repaint after an edit.)

- [ ] **Step 2: Verify live update (screenshot before/after)**

`reload_lua`. Create a stylesheet, assign it to a doc, and render the doc in a modal (Task 2 harness). `screenshot` (before). Then, through the bridge, mutate the stylesheet (e.g. set `headings[1].color="#c9a84a"`) and `dmhub.SetAndUploadTableItem(...)` WITHOUT manually clearing the cache or re-rendering. `screenshot` again (after) and confirm the heading recolored on its own -- proving the monitor fired. Clean up the row and modal. Put both observations in your report.

- [ ] **Step 3: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): live re-render journals on stylesheet table change"
```

---

## Self-Review

**Spec coverage (Plan 2 scope):**
- "Build a per-document style from the resolved base" -- reframed by the spike to inline-markup injection (`ApplySkinToText`), Tasks 1+3. PASS.
- Heading size/font/color/weight/tracking/caps -- Task 1 (`SkinHeadingMarkup`). `font` per-heading is NOT injected (TMP `<font>` needs registered faces; deferred to a fidelity pass with the asset work -- noted). Weight maps black/bold->`<b>` given the font catalog. PASS with noted limit.
- Bullets/ordered lists styled -- Task 3. PASS.
- Blockquote (quote) + divider (rule) -- Task 4 (divider gated on a spike; default unaffected). PASS.
- Body font/color -- Task 1 (`SkinBodyMarkup`, color only; body `font`/`lineHeight`/`paragraphSpacing` deferred, same `<font>`/layout limitation). PARTIAL, noted.
- Link styling -- NOT in Plan 2 (links render via the label's own link handling; `base.link` deferred to a later pass). Noted gap, intentional.
- Live invalidation (monitor -> ClearCache -> refresh) -- Task 5. PASS.
- "Default skin renders identical to today" invariant -- enforced by every task's default-path test/screenshot. PASS.

**Placeholder scan:** No "TBD"/"handle edge cases". Two tasks contain explicit, bounded spikes (divider props in Task 4; monitor-path accessor in Task 5) with concrete fallbacks and "do not invent" / "report BLOCKED" instructions -- these are verification steps, not placeholders. The `font`/`link`/layout deferrals are called out as intentional scope, not skipped requirements.

**Type consistency:** `ApplySkinToText(text, base) -> string` and the `Skin*Markup` helpers use the Plan 1 `base` schema field names verbatim (`headings[n].sizePct/weight/color/caps/tracking`, `bullet.glyph/color/indent`, `ordered.color/indent`, `quote.color/italic`, `rule.color/thickness/margin`, `body.color`). `resolvedSkin` (Task 2 hoist) is the single name used in Tasks 2/4/5. `MarkdownDocument.__ApplySkinToText` test hook consistent across Tasks 1/3.

---

## Deferred to later plans / fidelity pass (noted, not gaps)

- **Per-element fonts (`<font=...>`)** for headings/body/quote: needs the imported book faces registered in `gui.availableFonts` (the asset pack). The markup hook is ready; wiring fonts is a fidelity pass once faces land. The default skin intentionally does not inject fonts (visual no-op).
- **Body `lineHeight` / `paragraphSpacing` / heading `spaceBefore`/`spaceAfter`**: paragraph-level layout, not inline markup; revisit with `<line-height>` / panel margins once the structural cases are visually validated.
- **`base.link`** styling: deferred; links currently render via the label's own link handling.
- **Bullet glyph as `{codepoint, font}`** (spec) vs the flattened `glyph`/`glyphFont` (Plan 1): reconcile the spec wording; the transformer reads the flattened form.
- **h6 parity:** Task 1 maps h6 from `base.headings[6]` (default 120%); since today `######` renders unstyled, the default skin's h6 entry means `######` will now render at 120%. Decide during Task 2's screenshot review whether to neutralize the default h6 (set its `sizePct=100`) to preserve exact parity, or accept the (arguably better) styled h6.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-17-journal-stylesheets-render.md`. This is Plan 2 of 4.

Two execution options:

1. **Subagent-Driven (recommended)** - fresh implementer per task + spec/quality review between tasks. Needs DMHub running for the bridge (pure-logic + screenshot verification).
2. **Inline Execution** - execute tasks here with checkpoints.

Which approach?
