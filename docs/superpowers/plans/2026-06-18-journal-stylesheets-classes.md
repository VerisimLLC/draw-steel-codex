# Journal Stylesheets - Named Classes (Plan 3 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let journal authors apply named stylesheet classes to content -- inline `{.class text}` (a styled span) and block `:::class ... :::` (a wrapping callout/box panel) -- resolving each from the document's stylesheet at render time.

**Architecture:** Reuse the Plan 2 inline-markup approach. A new `SkinClassTextMarkup(text, content)` builds inline TMP markup from a class's `text` block (the same technique as `SkinHeadingMarkup`). Inline `{.class text}` is resolved at render by `ApplyInlineClasses(text, classes)` (a `gsub` pass), with a `{.` pass-through branch added to `StripSpoilers` so the span survives the player-view strip. Block `:::class ... :::` follows the **blockquote precedent** (NOT a RichTag): a tokenizer branch emits a `styleblock` token, and a render-loop branch builds a wrapping `gui.Panel` carrying the class's `box` props plus an inner `MarkdownLabel` styled by the class's `text`. All in `DocumentSystem/MarkdownDocument.lua`.

**Tech Stack:** DMHub Lua mod runtime; the Plan 1 resolver (`MarkdownDocument:GetResolvedStylesheet().classes`); the Plan 2 `Skin*` helpers + `ApplySkinToText` wire-in; TextMeshPro inline markup; `gui.Panel` box properties (`bgcolor`/`border`/`borderImage`/`cornerRadius`/`pad`); `ThemeEngine.ResolveTokens` for `@token` colors. Verification via the DMHub MCP bridge (`reload_lua` + `execute_lua` for pure logic; `screenshot` for render).

## Global Constraints

- **ASCII only.** Every byte in `MarkdownDocument.lua` (code and comments) 0-127. No em dashes, curly quotes, ellipses.
- **No new files.** All code in `DocumentSystem/MarkdownDocument.lua`. Do not touch `main.lua`.
- **No CLI test runner.** Pure-logic tasks: `reload_lua` then `execute_lua` asserting `PASS`/`FAIL`. Render tasks: `reload_lua`, render a document, `screenshot`, Read the image.
- **Graceful fallthrough.** An unknown class name, or a class whose `kind` does not match the usage (inline class used as block or vice-versa), renders the inner content unstyled -- never an error, never literal `{.…}`/`:::` markers left visible.
- **No regression to Plans 1-2.** Documents with no stylesheet, and documents that use only base-skin features, must render exactly as they do after Plan 2. A document that contains no `{.` and no `:::` must be byte-identical through the new passes.
- **`@token` colors** resolve via `ThemeEngine.ResolveTokens`; literal hex passes through. (Use the existing `SkinColor` helper.)
- **Class schema (Plan 1).** A class entry is `{ kind = "inline"|"block", text = {...}, box = {...} }`. `text` fields: `color, size (percent), font, weight ("regular"|"bold"|"black"), italic (bool), caps ("allcaps"|"smallcaps"), tracking (1/1000 em), underline (bool), strike (bool), mark (bool)`. `box` fields (block only): `bgcolor, bgimage, bgslice, gradient, borderImage, border, borderColor, cornerRadius, beveledcorners, pad, inset`. `font` is NOT emitted (needs the asset pack; deferred, as in Plan 2).
- **Forward-declare self-referencing locals.**

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `DocumentSystem/MarkdownDocument.lua` | Markdown document type, resolver (Plan 1), render + skin markup (Plan 2) | Modify only |

Verified anchors (current line numbers, post-Plan-2):
- `MarkdownDocument:GetResolvedStylesheet()` -> `{ base, classes }`: line 208.
- `Skin*` helpers (`SkinColor`, `SkinHeadingMarkup`, `SkinBodyMarkup`, `SkinBulletMarkup`, `SkinOrderedMarkup`, `SkinQuoteText`) + `ApplySkinToText` + the test hook `MarkdownDocument.__ApplySkinToText`: in the block after line 208 (Plan 2).
- `StripSpoilers(text)`: lines 420-523. Brace branches `{!` (440), `{#` (443), `{:` (450), and the catch-all `else depth = depth + 1` (505). It runs ONLY for player view (`if isPlayer then content = StripSpoilers(content)`, line 543-544). The new `{.` branch goes before line 505.
- Tokenizer `BreakdownRichTags`: blockquote tokenized at lines 669-700 (`^> *` match, multi-line collect, `type = "blockquote"` at 692); divider at line 812. The `:::class:::` tokenizer branch mirrors the blockquote collect/skip pattern, added near line 669.
- Render loop hoist: `local resolvedSkin = self:GetResolvedStylesheet().base` at line 1424. `resolvedClasses` is hoisted alongside it.
- Body-text wire-in: `textPanel.text = ApplySkinToText(text, resolvedSkin)` at line 1928.
- Blockquote render branch (the pattern to mirror for `styleblock`): lines 1965-2005, with `m_blockquotes`/`newBlockquotes` reuse and `m_blockquotes = newBlockquotes` reset at line 2137.

---

## Task 1: `SkinClassTextMarkup` helper + hoist `resolvedClasses`

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (add helper beside the other `Skin*` helpers; add a hoist beside `resolvedSkin`)

**Interfaces:**
- Consumes: `SkinColor` (Plan 2).
- Produces:
  - file-local `SkinClassTextMarkup(textBlock, content) -> string` (the class-text inline-markup builder), exposed for tests as `MarkdownDocument.__SkinClassTextMarkup`.
  - `local resolvedClasses = self:GetResolvedStylesheet().classes` hoisted in the render loop (consumed by Tasks 2-3). NOTE: call `GetResolvedStylesheet()` once and read both `.base` and `.classes` from it, rather than calling it twice.

- [ ] **Step 1: Write the failing test (bridge snippet)**

```lua
local f = MarkdownDocument.__SkinClassTextMarkup
local ok=true local function ck(c,m) if not c then ok=false print("FAIL: "..m) end end
ck(f(nil, "x") == "x", "nil text block -> unchanged")
ck(f({}, "x") == "x", "empty text block -> unchanged")
ck(f({ color="#e05a5a", weight="bold" }, "Warn") == "<b><color=#e05a5a>Warn</color></b>", "bold+color nests color inside bold")
ck(f({ italic=true }, "q") == "<i>q</i>", "italic")
ck(f({ underline=true }, "u") == "<u>u</u>", "underline")
ck(f({ strike=true }, "s") == "<s>s</s>", "strike")
ck(f({ size=150 }, "big") == "<size=150%>big</size>", "size percent")
ck(f({ caps="allcaps" }, "loud") == "LOUD", "allcaps uppercases content")
ck(f({ tracking=50 }, "t") == "<cspace=0.050em>t</cspace>", "tracking -> cspace em")
-- @token color resolves to hex
local out = f({ color="@danger" }, "z")
ck(out:find("<color=#") ~= nil and out:find("@danger") == nil, "@token color resolved")
print(ok and "PASS" or "TEST FAILED")
```

(The exact tag-nesting order asserted above: the implementation must append opens left-to-right in this order -- size, weight(b), italic(i), underline(u), strike(s), tracking(cspace), mark, color -- and prepend closes, so for `{color,weight=bold}` the output is `<b><color>...</color></b>`. Match the asserted strings exactly.)

- [ ] **Step 2: Run the test to verify it fails**

`reload_lua`, then `execute_lua` with the snippet. Expected: `attempt to index a nil value (field '__SkinClassTextMarkup')` -- not `PASS`.

- [ ] **Step 3: Write the implementation**

(a) Add the helper next to the other `Skin*` helpers (above `ApplySkinToText`):

```lua
-- Build inline TMP markup from a class's `text` block. Mirrors SkinHeadingMarkup
-- but covers the full class-text vocabulary (italic/underline/strike/mark). An
-- empty/nil block returns the content unchanged. `font` is intentionally not
-- emitted (needs imported faces; deferred to the asset pack, as in Plan 2).
local function SkinClassTextMarkup(t, content)
    t = t or {}
    local open, close = "", ""
    if t.size and t.size ~= 100 then
        open = open .. string.format("<size=%d%%>", t.size); close = "</size>" .. close
    end
    if t.weight == "bold" or t.weight == "black" then
        open = open .. "<b>"; close = "</b>" .. close
    end
    if t.italic == true then open = open .. "<i>"; close = "</i>" .. close end
    if t.underline == true then open = open .. "<u>"; close = "</u>" .. close end
    if t.strike == true then open = open .. "<s>"; close = "</s>" .. close end
    local tracking = t.tracking or 0
    if tracking ~= 0 then
        open = open .. string.format("<cspace=%.3fem>", tracking / 1000)
        close = "</cspace>" .. close
    end
    if t.mark == true then
        open = open .. ThemeEngine.ResolveTokens("<mark=@fg>"); close = "</mark>" .. close
    end
    local color = SkinColor(t.color)
    if color then
        open = open .. string.format("<color=%s>", color); close = "</color>" .. close
    end
    if t.caps == "allcaps" then
        content = string.upper(content)
    elseif t.caps == "smallcaps" then
        open = open .. "<smallcaps>"; close = "</smallcaps>" .. close
    end
    return open .. content .. close
end

-- Test hook.
MarkdownDocument.__SkinClassTextMarkup = SkinClassTextMarkup
```

(b) Hoist `resolvedClasses` beside `resolvedSkin` (line 1424). Replace:

```lua
            local resolvedSkin = self:GetResolvedStylesheet().base
```

with:

```lua
            local resolvedStylesheet = self:GetResolvedStylesheet()
            local resolvedSkin = resolvedStylesheet.base
            local resolvedClasses = resolvedStylesheet.classes
```

- [ ] **Step 4: Run the test to verify it passes**

`reload_lua`, then `execute_lua` with the Step-1 snippet. Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): SkinClassTextMarkup helper and resolvedClasses hoist"
```

---

## Task 2: Inline `{.class text}` spans

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (add `ApplyInlineClasses`; add a `{.` branch to `StripSpoilers`; wire into the render body-text site)

**Interfaces:**
- Consumes: `SkinClassTextMarkup` (Task 1), `resolvedClasses` (Task 1), `ApplySkinToText` (Plan 2).
- Produces: file-local `ApplyInlineClasses(text, classes) -> string`, exposed as `MarkdownDocument.__ApplyInlineClasses`. Replaces each `{.name inner}` span with the inline class's text markup; unknown / non-inline classes strip to bare `inner`.

- [ ] **Step 1: Write the failing test (bridge snippet)**

```lua
local f = MarkdownDocument.__ApplyInlineClasses
local ok=true local function ck(c,m) if not c then ok=false print("FAIL: "..m) end end
local classes = {
  warn = { kind="inline", text = { color="#e05a5a", weight="bold" } },
  big  = { kind="inline", text = { size=150 } },
  boxy = { kind="block",  box = { bgcolor="#222222" } },
}
-- no markers -> unchanged
ck(f("plain text", classes) == "plain text", "no class markers unchanged")
-- a span in the middle of a line
ck(f("be {.warn careful} now", classes) == "be <b><color=#e05a5a>careful</color></b> now", "inline span resolved mid-line")
-- multiple spans
ck(f("{.warn a} and {.big b}", classes) == "<b><color=#e05a5a>a</color></b> and <size=150%>b</size>", "two spans")
-- unknown class -> strip wrapper, keep inner
ck(f("see {.nope text}", classes) == "see text", "unknown class strips to inner")
-- non-inline (block) class used inline -> strip wrapper, keep inner
ck(f("{.boxy hi}", classes) == "hi", "block class used inline strips to inner")
-- nil/empty classes -> spans strip to inner
ck(f("{.warn x}", nil) == "x", "nil classes strips to inner")
print(ok and "PASS" or "TEST FAILED")
```

- [ ] **Step 2: Run the test to verify it fails**

`reload_lua`, `execute_lua`. Expected: `attempt to index a nil value (field '__ApplyInlineClasses')` -- not `PASS`.

- [ ] **Step 3: Write the implementation**

(a) Add `ApplyInlineClasses` next to `ApplySkinToText` (after it is fine):

```lua
-- Resolve inline {.name inner} spans to the named inline class's text markup.
-- Unknown names, or classes whose kind is not "inline", strip to bare `inner`
-- (graceful fallthrough -- never leave the literal {.…} markers visible).
-- inner may not contain a literal "}" (the common authoring case); a span whose
-- inner needs a brace is not supported.
local function ApplyInlineClasses(text, classes)
    if type(text) ~= "string" or text == "" then return text end
    classes = classes or {}
    return (text:gsub("{%.([%w_%-]+) ([^}]*)}", function(name, inner)
        local cls = classes[name]
        if type(cls) == "table" and cls.kind == "inline" then
            return SkinClassTextMarkup(cls.text, inner)
        end
        return inner
    end))
end

-- Test hook.
MarkdownDocument.__ApplyInlineClasses = ApplyInlineClasses
```

(The outer parentheses around the `gsub` discard its second return value -- the match count -- so the function returns only the string.)

(b) Preserve `{.…}` through the player-view strip. In `StripSpoilers`, add a branch before the catch-all `else depth = depth + 1` (line 505). The `{:` branch ends around line 504 with `end` (closing the `if x ~= nil`) followed by `end` -- insert the new `elseif` between the close of the `{:` block and the `else`:

```lua
            elseif text:sub(a + 1, a + 1) == "." and depth == 0 then
                -- Inline class span {.name text}: copy verbatim so the render-time
                -- ApplyInlineClasses pass (which has the resolved classes) handles
                -- it. Stripping here would lose the class for player view.
                if depth == 0 then
                    local close = text:find("}", a + 1, true)
                    if close ~= nil then
                        result = result .. text:sub(a, close)
                        b = close
                    else
                        result = result .. text:sub(a)
                        b = #text
                    end
                end
```

(c) Wire it into the render body-text site. At line 1928, change:

```lua
                    textPanel.text = ApplySkinToText(text, resolvedSkin)
```

to:

```lua
                    textPanel.text = ApplySkinToText(ApplyInlineClasses(text, resolvedClasses), resolvedSkin)
```

(Inline spans resolve first, producing inner markup; then `ApplySkinToText` applies line-level heading/bullet/body markup around them. Line-start detection in `ApplySkinToText` is unaffected because a `{.` span never begins a line's heading/bullet prefix.)

(d) **Exclude `{.` from the spoiler tokenizer (REQUIRED -- discovered at runtime).**
The main tokenizer (NOT just `StripSpoilers`) treats every `{` as a GM spoiler:
the regex at line 914 captures `(?<spoiler>\{)` and the branch at line 931 emits a
"Reveal to Players" link for it in DM view. Without this fix, `{.class text}` gets a
spurious spoiler link layered over the styled span. In the `if match.spoiler ~= nil`
branch, detect the inline-class marker and skip the spoiler UI (mirroring how the same
branch already special-cases `{!` at line 940). Change:

```lua
            if match.spoiler ~= nil then

                if not isPlayer then
```

to:

```lua
            if match.spoiler ~= nil then

                -- {.name ...} is an inline class marker, not a spoiler: skip the
                -- spoiler UI so the render-time ApplyInlineClasses pass resolves it.
                local isInlineClass = string.match(match.suffix, "^%.[%w_%-]+ ") ~= nil

                if not isPlayer and not isInlineClass then
```

The `text = text .. "{"` at line 960 still runs, so the `{` and the rest of
`.name text}` flow through as plain text into the text token, where
`ApplyInlineClasses` resolves the span. This makes `{.class}` render cleanly in BOTH
views (no spoiler link in DM view; `StripSpoilers` passthrough in player view).

- [ ] **Step 4: Run the unit test to verify it passes**

`reload_lua`, `execute_lua` with the Step-1 snippet. Expected: `PASS`. Also re-run the Plan 2 `ApplySkinToText` default-skin snippet (from `MarkdownDocument.__ApplySkinToText`, e.g. `f("# Title", default)=="<size=200%><b>Title</b></size>"`) to confirm no regression.

- [ ] **Step 5: Screenshot check (DM view + player view)**

`reload_lua`. Create a stylesheet with an inline class, assign it to a doc whose content uses `{.warn be careful}`, render it in a modal (Plan 2 Task 2 harness shape), `screenshot`, Read it: the span renders bold red, no literal `{.…}` visible. Then set `dmhub.isDM = false` if togglable, OR render the doc's player view path if exposed, screenshot again to confirm the span survives the player strip; if you cannot force player view from the bridge, note that and rely on the unit test for the StripSpoilers branch. Clean up the stylesheet row and modal.

- [ ] **Step 6: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): inline {.class} spans with player-view passthrough"
```

---

## Task 3: Block `:::class ... :::` callout panels

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (tokenizer branch near line 669; render-loop branch near line 1965; cache reset near line 2137)

**Interfaces:**
- Consumes: `SkinClassTextMarkup` (Task 1), `resolvedClasses` (Task 1).
- Produces: a new token `type = "styleblock"` (`{ type, className, text, player }`) and its render branch -- a wrapping `gui.Panel` styled by the class's `box`, containing an inner `gui.MarkdownLabel` whose text is `SkinClassTextMarkup(cls.text, token.text)`.

- [ ] **Step 1: Add the tokenizer branch**

In `BreakdownRichTags`, near the blockquote tokenization (line 669), add a branch that recognizes an opening fence line `::: classname` and collects lines until a closing `:::`. Mirror the blockquote branch's line-collection and skip mechanism (study lines 669-700 for how it advances past consumed lines -- use the SAME `skipLines`/`additionalLines` mechanism, do not invent one). The branch:

```lua
        local styleBlockMatch = regex.MatchGroups(str, "^::: *(?<class>[a-zA-Z0-9_-]+) *$")
        if styleBlockMatch ~= nil then
            EmitText()
            local blockLines = {}
            local consumed = 0
            for j = i + 1, #lines do
                if regex.MatchGroups(lines[j], "^::: *$") ~= nil then
                    consumed = consumed + 1  -- count the closing fence
                    break
                end
                blockLines[#blockLines + 1] = lines[j]
                consumed = consumed + 1
            end
            result[#result + 1] = {
                type = "styleblock",
                className = string.lower(styleBlockMatch.class),
                text = table.concat(blockLines, "\n"),
                player = isPlayer,
            }
            skipLines = consumed
            str = ""
        end
```

IMPORTANT: confirm how the surrounding tokenizer loop consumes `skipLines` and how `str` being set to `""` is handled (mirror exactly what the blockquote/divider branches do at lines 669-700 / 812). If the loop uses a different advance variable than `skipLines`, use that one. Place this branch so it is checked alongside the other block matchers (after `EmitText` is available, before the line falls through to plain-text accumulation).

- [ ] **Step 2: Add the render branch**

In the token render loop, add a branch mirroring the blockquote branch (lines 1965-2005). Put it right after the blockquote branch:

```lua
                elseif token.type == "styleblock" then
                    currentRichRow = nil
                    local cls = resolvedClasses[token.className]
                    local styleblock = m_styleblocks[#newStyleblocks + 1] or gui.Panel {
                        width = "100%",
                        height = "auto",
                        halign = "left",
                        valign = "top",
                        flow = "vertical",
                        borderBox = true,
                        savedoc = function(element) element:HaltEventPropagation() end,
                        refreshDocument = function(element) element:HaltEventPropagation() end,
                        editDocument = function(element) element:HaltEventPropagation() end,
                        refreshTag = function(element) element:HaltEventPropagation() end,
                        gui.MarkdownLabel{
                            width = "100%",
                            markdownText = function(element, text)
                                element:HaltEventPropagation()
                                element.text = text
                            end,
                        }
                    }

                    -- Apply the class box props (graceful when class is missing or
                    -- not a block class -> renders as a plain unstyled panel).
                    local box = (type(cls) == "table" and cls.kind == "block" and cls.box) or {}
                    local ss = styleblock.selfStyle
                    if box.bgcolor then ss.bgimage = "panels/square.png"; ss.bgcolor = SkinColor(box.bgcolor) end
                    if box.bgimage then ss.bgimage = box.bgimage end
                    if box.borderImage then ss.borderImage = box.borderImage end
                    if box.border then ss.border = box.border end
                    if box.borderColor then ss.borderColor = SkinColor(box.borderColor) end
                    if box.cornerRadius then ss.cornerRadius = box.cornerRadius end
                    if box.pad then ss.pad = box.pad end

                    if m_styleblocks[#newStyleblocks + 1] ~= nil then
                        styleblock:Unparent()
                    end

                    local innerText = token.text
                    if type(cls) == "table" and cls.text ~= nil then
                        innerText = SkinClassTextMarkup(cls.text, token.text)
                    end
                    styleblock:FireEventTree("markdownText", innerText)

                    newStyleblocks[#newStyleblocks + 1] = styleblock
                    children[#children + 1] = styleblock
```

- [ ] **Step 3: Declare and reset the styleblock caches**

Mirror the `m_blockquotes` lifecycle. Where `local m_blockquotes = {}` is declared (line 1346), add `local m_styleblocks = {}`. Where `newBlockquotes` is initialized at the top of the render pass (find `local newBlockquotes = {}`), add `local newStyleblocks = {}`. Where `m_blockquotes = newBlockquotes` resets at the end (line 2137), add `m_styleblocks = newStyleblocks`. (Find all three blockquote cache sites and add the parallel styleblock line at each.)

- [ ] **Step 4: Verify (screenshot)**

`reload_lua`. Create a stylesheet with a block class, e.g.:

```lua
local s = JournalStylesheet.Create()
s.classes = { readaloud = { kind="block",
  box = { bgcolor="#2a2418", border=2, borderColor="#8a7544", cornerRadius=6, pad=12 },
  text = { italic=true, color="#d8c8a0" } } }
local sid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, s)
ResolveStylesheet.ClearCache()
local doc = MarkdownDocument.new{ content = "Intro line.\n\n::: readaloud\nThe door creaks open.\nDust hangs in the air.\n:::\n\nAfter the box.", annotations = {} }
doc.styleSheetId = sid
local panel = gui.Panel{ id="p3test", bgimage="panels/square.png", bgcolor="#15110bff",
  borderColor="#8a7544", borderWidth=2, width=680, height=420, halign="center", valign="center",
  flow="vertical", pad=20, borderBox=true, click=function() gamehud:CloseModal() end,
  children={ doc:DisplayPanel{ width="100%", height="auto" } } }
gamehud:ShowModal(panel)
print("shown sid="..sid)
```

`screenshot`, Read it: the read-aloud text renders inside a bordered, dark, padded box, italic and tan; the surrounding lines render normally; no literal `:::` markers visible. Also confirm an UNKNOWN block class (`::: nope ... :::`) renders the inner text in a plain panel (no error). Clean up: `dmhub.ObliterateTableItem(JournalStylesheet.tableName, sid)`, `gamehud:CloseModal()`. Put both observations in your report.

- [ ] **Step 5: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): block :::class::: callout panels"
```

---

## Self-Review

**Spec coverage (Plan 3 scope):**
- Named classes, inline + block -- Tasks 2 (inline) and 3 (block). PASS.
- Inline `{.class text}` resolves class `text` markup -- Task 2 via `ApplyInlineClasses` + `SkinClassTextMarkup`. PASS.
- Block `:::class:::` wraps a panel with `box` + inner text styled by `text`, via the blockquote precedent (NOT a RichTag) -- Task 3. PASS.
- `@token` colors resolve -- Task 1 (`SkinColor` in `SkinClassTextMarkup` and box colors). PASS.
- Graceful fallthrough (unknown/mismatched-kind class) -- Task 2 (strip to inner) and Task 3 (plain panel). PASS.
- Resolved `classes` threaded at render -- Task 1 (`resolvedClasses` hoist). PASS.
- Player-view survival of inline spans -- Task 2 (`StripSpoilers` `{.` pass-through). PASS.
- Deferred (noted): per-class `font` (asset pack, same as Plan 2); `box.bgslice`/`box.gradient`/`box.beveledcorners`/`box.inset` are accepted in the schema but only the common box props are wired in Task 3 (bgcolor/bgimage/borderImage/border/borderColor/cornerRadius/pad) -- extend when a stylesheet needs them; an inner-text-only block class still works.

**Placeholder scan:** No "TBD"/"handle edge cases". Two tasks contain explicit "mirror the existing blockquote skip/cache mechanism, confirm the exact variable" instructions -- these are verified-against-existing-code directions with concrete anchors (lines 669-700, 1346, 2137), not placeholders. The `box.bgslice`/`gradient`/`inset` non-wiring is called out as intentional scope.

**Type consistency:** `SkinClassTextMarkup(textBlock, content) -> string`, `ApplyInlineClasses(text, classes) -> string`, `resolvedClasses`, token `type="styleblock"` with `.className`/`.text`, and `m_styleblocks`/`newStyleblocks` are used consistently across tasks. Class schema field names (`kind`, `text.{color,size,weight,italic,caps,tracking,underline,strike,mark}`, `box.{bgcolor,bgimage,borderImage,border,borderColor,cornerRadius,pad}`) match the Global Constraints and Plan 1.

---

## Deferred to Plan 4 / later (noted)

- **Per-class `font`** -- needs imported faces (asset pack), as in Plan 2.
- **`box.bgslice` / `box.gradient` / `box.beveledcorners` / `box.inset`** -- accepted by the schema; wire on demand when an authored stylesheet uses them.
- **Inline spans inside headings/bullets** work (resolved before `ApplySkinToText`), but an inline span whose `inner` contains a literal `}` is unsupported -- acceptable for v1 authoring.
- **`borderImage` 9-slice frames at journal scale** -- the spec flagged a spike for crispness; do it when authoring the first framed "Print" sidebar class.
- The Plan 2 carry-overs (args-merge ordering, allcaps-on-URLs) remain for Plan 4's editor.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-18-journal-stylesheets-classes.md`. This is Plan 3 of 4.

Two execution options:

1. **Subagent-Driven (recommended)** - fresh implementer per task + spec/quality review between tasks. Needs DMHub running for the bridge (pure-logic + screenshot verification).
2. **Inline Execution** - execute tasks here with checkpoints.

Which approach?
