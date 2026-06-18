# Journal Stylesheets - Editor UI + Picker (Plan 4 of 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give users a UI to assign a stylesheet to a journal (a picker in the markdown editor) and to author stylesheets (a Compendium-hosted list + a curated property editor: stylesheet CRUD, inheritance, the high-impact base-skin fields, and named classes).

**Architecture:** Two existing files. In `DocumentSystem/MarkdownDocument.lua`: add `JournalStylesheet.CreateNew`, `JournalStylesheet.CreateEditor`/`SetData` (the editor panel, modeled on `CharacterCondition`), and a "Stylesheet:" dropdown in the journal editor (`MarkdownDocument:EditPanel`). In `DMHub Compendium/Compendium.lua`: a `ShowJournalStylesheetsPanel` (list + editor, modeled on `ShowConditionsPanel`) registered as a Compendium category. The editor mutates a `JournalStylesheet` and persists via `dmhub.SetAndUploadTableItem("journalStyles", sheet)`; the Plan 2 monitor live-re-renders open journals. Scope is **curated essentials** -- the long-tail properties stay import/code-only.

**Tech Stack:** DMHub Lua mod runtime; `dmhub.GetTable`/`SetAndUploadTableItem`/`ObliterateTableItem`; the Plan 1 resolver (`ResolveStylesheet`, `JournalStylesheet`); gui controls `gui.Dropdown`, `gui.ColorPicker`, `gui.Input`, `gui.Check`, `gui.Button`; `Compendium.Register`. Verification via the DMHub MCP bridge (`execute_lua` for logic; `screenshot` for UI) -- no CLI test runner.

## Global Constraints

- **ASCII only.** Every byte in both files (code and comments) 0-127. No em dashes, curly quotes, ellipses.
- **No new files.** All code in `DocumentSystem/MarkdownDocument.lua` and `DMHub Compendium/Compendium.lua`. Do not touch `main.lua`.
- **No CLI test runner.** Logic checks: `reload_lua` then `execute_lua` asserting `PASS`/`FAIL`. UI checks: `reload_lua`, open the panel/editor (or render via the bridge), `screenshot`, Read the image.
- **Curated scope.** Editor exposes: stylesheet name + `parentId`; per-heading-level `size`/`color`/`weight`/`caps`; body `color`; bullet `glyph`/`color`; per-class `name`/`kind`/`text.color`/`text.weight`/`text.italic` and (block) `box.bgcolor`/`box.border`/`box.cornerRadius`/`box.pad`. Everything else in the schema is intentionally NOT in the UI (authored via import/code); do not add controls for it.
- **Override semantics.** A form field DISPLAYS the resolved (effective) value but WRITES only this sheet's own override (`sheet.base...`/`sheet.classes...`). Untouched fields stay unset and keep inheriting. Clearing a field back to "inherit" is not in the curated UI (a documented limitation).
- **Persist via the table.** Every editor mutation calls `dmhub.SetAndUploadTableItem("journalStyles", sheet)` (verified to assign/keep the guid id). Deletes use `dmhub.ObliterateTableItem("journalStyles", id)`.
- **Forward-declare self-referencing locals** (gui closures referencing their own panel).
- **borderBox with padding.** Any panel using `pad`/`hpad`/`vpad` sets `borderBox = true`.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `DocumentSystem/MarkdownDocument.lua` | `JournalStylesheet` type; `CreateNew`/`CreateEditor`/`SetData`; the journal editor's stylesheet picker | Modify only |
| `DMHub Compendium/Compendium.lua` | `ShowJournalStylesheetsPanel` (list+editor host) + `Compendium.Register` category | Modify only |

Verified anchors (current line numbers):
- `MarkdownDocument:EditPanel` (journal editor): line 2325. `editInput` 3684; `previewDoc = MarkdownDocument.new{...}` 3742; `previewPanel` 3747 (its `editDocument` handler updates `previewDoc` and fires `refreshDocument`); `toolbar` (horizontal, wrap) 3916; `resultPanel` 4000. Picker row inserts into the toolbar (~3916) or as a row above the editor columns.
- `JournalStylesheet` type + `Create()` + `ResolveStylesheet`: lines ~22-230 (Plan 1).
- `ShowConditionsPanel`: `DMHub Compendium/Compendium.lua` line 672 (list iter 690-703; add button 724-726). `Compendium.Register{...}` category: 6449-6456.
- `CharacterCondition.CreateEditor` (line 567) + `SetData` (line 137) + `UploadCondition` pattern: `DMHub Game Rules/Condition.lua`. Form rows: Input 172-186; Dropdown 252-267; Check 290-300; `gui.ColorPicker` 208-223.

---

## Task 1: Journal editor stylesheet picker

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (a dropdown in `MarkdownDocument:EditPanel`; a small option-builder)

**Interfaces:**
- Consumes: `dmhub.GetTable("journalStyles")`, `self.styleSheetId`, `previewDoc`.
- Produces: `JournalStylesheet.PickerOptions() -> { {id,text}, ... }` (file-local or static method) used here and reused by the editor's parent dropdown in Task 3.

- [ ] **Step 1: Write the failing test (bridge snippet) for the option builder**

```lua
local ok=true local function ck(c,m) if not c then ok=false print("FAIL: "..m) end end
local opts = JournalStylesheet.PickerOptions()
ck(type(opts)=="table" and #opts >= 1, "options is a non-empty list")
ck(opts[1].id == "" and opts[1].text ~= nil, "first option is the none/default entry with id ''")
-- create one and confirm it appears
local s = JournalStylesheet.Create(); s.name = "PICKTEST"
local sid = dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, s)
local opts2 = JournalStylesheet.PickerOptions()
local found = false
for _,o in ipairs(opts2) do if o.id == sid and o.text == "PICKTEST" then found = true end end
ck(found, "created stylesheet appears in options by id+name")
dmhub.ObliterateTableItem(JournalStylesheet.tableName, sid)
print(ok and "PASS" or "TEST FAILED")
```

- [ ] **Step 2: Run to verify it fails**

`reload_lua`, `execute_lua`. Expected: `attempt to call a nil value (field 'PickerOptions')` -- not `PASS`.

- [ ] **Step 3: Implement the option builder + the picker**

(a) Add the option builder near the other `JournalStylesheet` methods (after `GetResolvedStylesheet` is fine):

```lua
-- Dropdown options for choosing a journal stylesheet. First entry (id "") means
-- "no stylesheet -> built-in default skin". Sorted by name.
function JournalStylesheet.PickerOptions()
    local result = { { id = "", text = "(Default skin)" } }
    local tbl = dmhub.GetTable(JournalStylesheet.tableName) or {}
    for k, sheet in unhidden_pairs(tbl) do
        result[#result + 1] = { id = k, text = sheet.name or "Unnamed" }
    end
    table.sort(result, function(a, b)
        if a.id == "" then return true end
        if b.id == "" then return false end
        return a.text < b.text
    end)
    return result
end
```

(b) Add the picker dropdown into `MarkdownDocument:EditPanel`. Locate the `toolbar = gui.Panel{ ... }` (line ~3916); add this as a child row of the toolbar (or, if the toolbar is tightly packed, add it as a labeled row immediately above the editor columns inside `resultPanel`). `self` and `previewDoc` are in scope in `EditPanel`:

```lua
        gui.Panel{
            classes = { "formStackedRow" },
            width = "auto",
            height = "auto",
            valign = "center",
            gui.Label{ classes = { "formStacked" }, text = "Stylesheet:" },
            gui.Dropdown{
                classes = { "formStacked" },
                options = JournalStylesheet.PickerOptions(),
                idChosen = self.styleSheetId or "",
                change = function(element)
                    local chosen = element.idChosen
                    self.styleSheetId = (chosen ~= "" and chosen) or false
                    previewDoc.styleSheetId = self.styleSheetId
                    ResolveStylesheet.ClearCache()
                    if previewPanel ~= nil then
                        previewPanel:FireEventTree("refreshDocument", previewDoc)
                    end
                    if resultPanel ~= nil then
                        resultPanel:FireEventTree("checkChanges", self)
                    end
                end,
            },
        },
```

(If `previewPanel`/`resultPanel` are declared with `local` AFTER this point, move the dropdown's construction to after their declarations, or forward-declare them, so the closure sees them. They are referenced, not redefined.)

- [ ] **Step 4: Run the option-builder test to verify it passes**

`reload_lua`, `execute_lua` with the Step-1 snippet. Expected: `PASS`.

- [ ] **Step 5: Screenshot + persistence check**

`reload_lua`. Create a stylesheet that restyles h1 (e.g. `base.headings[1] = { sizePct=300, color="#c9a84a", caps="allcaps" }`), upload it. Open a journal's editor in DMHub (or render `MarkdownDocument.new{content="# Chapter", ...}:EditPanel{}` in a modal via the bridge), `screenshot`, Read it: a "Stylesheet:" dropdown is present. Then through the bridge set the doc's styleSheetId to the test sheet and re-render/refresh; `screenshot` to confirm the preview re-skins. **Persistence:** after choosing a stylesheet in the picker, confirm `self.styleSheetId` is set and that the editor's save path persists it -- if the document does not save on a stylesheet-only change, wire the change handler to the editor's existing save trigger (the `checkChanges`/`needsave`/`savedoc` mechanism the text edit uses) so the Save control activates. Describe the persistence behavior you observed in your report. Clean up the test stylesheet.

- [ ] **Step 6: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): stylesheet picker in the journal editor"
```

---

## Task 2: Stylesheet list, CRUD, and Compendium category

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (`CreateNew`, `CreateEditor`, a `SetData` skeleton with name + parent)
- Modify: `DMHub Compendium/Compendium.lua` (`ShowJournalStylesheetsPanel` + `Compendium.Register`)

**Interfaces:**
- Consumes: `JournalStylesheet.Create`, `JournalStylesheet.PickerOptions` (Task 1), `ResolveStylesheet`.
- Produces:
  - `JournalStylesheet.CreateNew() -> JournalStylesheet` (for the add button).
  - `JournalStylesheet.CreateEditor() -> Panel` whose `.data.SetData(tableName, id)` populates the editor for entry `id`. Task 3-4 extend `SetData`'s field set.
  - file-local `JournalStyleEditor_BuildForm(sheet, upload, panel)` -- builds and assigns `panel.children`; Tasks 3-4 add sections to it. (Defined here with name + parent; extended later.)

- [ ] **Step 1: Write the failing test (CreateNew)**

```lua
local ok=true local function ck(c,m) if not c then ok=false print("FAIL: "..m) end end
local s = JournalStylesheet.CreateNew()
ck(type(s)=="table" and type(s.base)=="table" and type(s.classes)=="table", "CreateNew gives a fresh stylesheet")
ck(s.name ~= nil and s.name ~= "", "CreateNew sets a name")
local ed = JournalStylesheet.CreateEditor()
ck(type(ed)=="table" and type(ed.data.SetData)=="function", "CreateEditor returns a panel with data.SetData")
print(ok and "PASS" or "TEST FAILED")
```

- [ ] **Step 2: Run to verify it fails**

`reload_lua`, `execute_lua`. Expected: `attempt to call a nil value (field 'CreateNew')` -- not `PASS`.

- [ ] **Step 3: Implement CreateNew, CreateEditor, SetData skeleton, and the form builder**

Add near the other `JournalStylesheet` methods:

```lua
function JournalStylesheet.CreateNew()
    return JournalStylesheet.Create()
end

-- Forward-declared so SetData can call it before its definition below.
local JournalStyleEditor_BuildForm

-- SetData fetches the entry and (re)builds the editor form. Re-resolving on each
-- field change keeps displayed (inherited) values current.
local function JournalStyleEditor_SetData(tableName, panel, id)
    local sheet = (dmhub.GetTable(tableName) or {})[id]
    if sheet == nil then
        panel.children = {}
        return
    end
    panel.data.sheetid = id
    local upload = function()
        dmhub.SetAndUploadTableItem(tableName, sheet)
    end
    JournalStyleEditor_BuildForm(sheet, upload, panel)
end

function JournalStylesheet.CreateEditor()
    local panel
    panel = gui.Panel{
        vscroll = true,
        flow = "vertical",
        pad = 20,
        borderBox = true,
        width = "100%",
        height = "100%",
        data = {
            sheetid = "",
            SetData = function(tableName, id)
                JournalStyleEditor_SetData(tableName, panel, id)
            end,
        },
    }
    return panel
end
```

Now the form builder. This task adds the NAME and PARENT rows; Tasks 3-4 add more sections to the same `children` list. To keep the form DRY across tasks, also add these small row helpers next to the builder:

```lua
-- Form row helpers (shared by base-skin and class editors). Each returns a panel.
local function JSE_TextRow(label, value, onset)
    return gui.Panel{ classes = {"formStackedRow"},
        gui.Label{ classes = {"formStacked"}, text = label },
        gui.Input{ classes = {"formStacked"}, text = value or "",
            change = function(element) onset(element.text); end },
    }
end

local function JSE_ColorRow(label, value, onset)
    return gui.Panel{ classes = {"formStackedRow"},
        gui.Label{ classes = {"formStacked"}, text = label },
        gui.ColorPicker{ value = value or "white", width = 24, height = 24, valign = "center",
            confirm = function(element) onset(element.value); end },
    }
end

local function JSE_NumberRow(label, value, onset)
    return gui.Panel{ classes = {"formStackedRow"},
        gui.Label{ classes = {"formStacked"}, text = label },
        gui.Input{ classes = {"formStacked"}, text = (value ~= nil and tostring(value)) or "",
            change = function(element)
                local n = tonumber(element.text)
                onset(n)
            end },
    }
end

local function JSE_CheckRow(label, value, onset)
    return gui.Panel{ classes = {"formStackedRow"},
        gui.Check{ value = value == true, text = label,
            change = function(element) onset(element.value == true); end },
    }
end

local function JSE_DropdownRow(label, options, idChosen, onset)
    return gui.Panel{ classes = {"formStackedRow"},
        gui.Label{ classes = {"formStacked"}, text = label },
        gui.Dropdown{ classes = {"formStacked"}, options = options, idChosen = idChosen or "",
            change = function(element) onset(element.idChosen); end },
    }
end

JournalStyleEditor_BuildForm = function(sheet, upload, panel)
    local children = {}

    -- Name
    children[#children+1] = JSE_TextRow("Name:", sheet.name, function(v)
        sheet.name = v; upload()
    end)

    -- Parent (inheritance). Options are all OTHER stylesheets plus "(none)".
    local parentOptions = { { id = "", text = "(No parent)" } }
    for k, other in unhidden_pairs(dmhub.GetTable(sheet.tableName or "journalStyles") or {}) do
        if k ~= panel.data.sheetid then
            parentOptions[#parentOptions+1] = { id = k, text = other.name or "Unnamed" }
        end
    end
    children[#children+1] = JSE_DropdownRow("Inherits from:", parentOptions,
        sheet.parentId or "", function(v)
            sheet.parentId = (v ~= "" and v) or false
            ResolveStylesheet.ClearCache()
            upload()
        end)

    panel.children = children
end
```

(Note: every `onset` that mutates the sheet calls `upload()` itself in the closures above; the helpers do not auto-upload. The name/parent rows do. Tasks 3-4 follow the same convention.)

- [ ] **Step 4: Run the CreateNew test to verify it passes**

`reload_lua`, `execute_lua` with the Step-1 snippet. Expected: `PASS`.

- [ ] **Step 5: Add the Compendium list panel + category**

In `DMHub Compendium/Compendium.lua`, model `ShowJournalStylesheetsPanel` on `ShowConditionsPanel` (line 672). It creates `JournalStylesheet.CreateEditor()`, lists `dmhub.GetTable(JournalStylesheet.tableName)` entries with click -> `SetData`, an add button calling `dmhub.SetAndUploadTableItem(JournalStylesheet.tableName, JournalStylesheet.CreateNew())`, and a delete affordance calling `dmhub.ObliterateTableItem(JournalStylesheet.tableName, id)`. Mirror the exact list/add/delete structure of `ShowConditionsPanel` (do not invent a new layout). Then register the category near line 6449:

```lua
Compendium.Register{
    section = "Rules",
    text = 'Journal Stylesheets',
    contentType = JournalStylesheet.tableName,
    click = function(contentPanel)
        ShowJournalStylesheetsPanel(contentPanel)
    end,
}
```

(Place `ShowJournalStylesheetsPanel`'s definition before this registration, matching how `ShowConditionsPanel` is defined before its `Compendium.Register`.)

- [ ] **Step 6: Screenshot check (CRUD)**

`reload_lua`. In DMHub, open the Compendium and select "Journal Stylesheets" (or, if you cannot drive the Compendium from the bridge, render `ShowJournalStylesheetsPanel` into a modal panel). `screenshot`, Read it: the list+editor is shown. Add a stylesheet (the add button), confirm it appears and selecting it shows the Name + Inherits-from rows; rename it (type in Name), set a parent; delete it. Screenshot each major step. Report what you observed. Clean up any leftover test rows.

- [ ] **Step 7: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua" "DMHub Compendium/Compendium.lua"
git commit -m "feat(journal): stylesheet list, CRUD, and Compendium category"
```

---

## Task 3: Curated base-skin property editor

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (extend `JournalStyleEditor_BuildForm` with base-skin sections)

**Interfaces:**
- Consumes: the Task 2 row helpers (`JSE_ColorRow`/`JSE_NumberRow`/`JSE_DropdownRow`), `ResolveStylesheet`.
- Produces: base-skin section UI appended to the form. No new exported symbol.

- [ ] **Step 1: Implement the base-skin sections**

In `JournalStyleEditor_BuildForm`, BEFORE `panel.children = children`, append the curated base-skin sections. Displayed values come from the RESOLVED sheet (effective/inherited); writes go to `sheet.base` (this sheet's override). Use a helper to ensure the override sub-table exists:

```lua
    -- Resolve once for display of inherited values.
    local resolvedBase = ResolveStylesheet(panel.data.sheetid).base

    local function ownBaseSection(key)
        sheet.base = sheet.base or {}
        sheet.base[key] = sheet.base[key] or {}
        return sheet.base[key]
    end
    local function ownHeading(level)
        sheet.base = sheet.base or {}
        sheet.base.headings = sheet.base.headings or {}
        sheet.base.headings[level] = sheet.base.headings[level] or {}
        return sheet.base.headings[level]
    end

    local weightOptions = {
        { id = "regular", text = "Regular" },
        { id = "bold", text = "Bold" },
        { id = "black", text = "Black" },
    }
    local capsOptions = {
        { id = "", text = "None" },
        { id = "smallcaps", text = "Small Caps" },
        { id = "allcaps", text = "All Caps" },
    }

    -- Headings 1-6 (curated: size, color, weight, caps)
    for level = 1, 6 do
        local rh = (resolvedBase.headings or {})[level] or {}
        children[#children+1] = gui.Label{ classes = {"formStacked"}, text = string.format("Heading %d", level) }
        children[#children+1] = JSE_NumberRow("  Size %:", rh.sizePct, function(n)
            ownHeading(level).sizePct = n; upload()
        end)
        children[#children+1] = JSE_ColorRow("  Color:", rh.color, function(c)
            ownHeading(level).color = c; upload()
        end)
        children[#children+1] = JSE_DropdownRow("  Weight:", weightOptions, rh.weight or "bold", function(v)
            ownHeading(level).weight = v; upload()
        end)
        children[#children+1] = JSE_DropdownRow("  Caps:", capsOptions, rh.caps or "", function(v)
            ownHeading(level).caps = (v ~= "" and v) or nil; upload()
        end)
    end

    -- Body (curated: color)
    children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "Body" }
    children[#children+1] = JSE_ColorRow("  Color:", (resolvedBase.body or {}).color, function(c)
        ownBaseSection("body").color = c; upload()
    end)

    -- Bullet (curated: glyph, color)
    children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "Bullet" }
    children[#children+1] = JSE_TextRow("  Glyph:", (resolvedBase.bullet or {}).glyph, function(v)
        ownBaseSection("bullet").glyph = (v ~= "" and v) or false; upload()
    end)
    children[#children+1] = JSE_ColorRow("  Color:", (resolvedBase.bullet or {}).color, function(c)
        ownBaseSection("bullet").color = c; upload()
    end)
```

(`JSE_TextRow` is from Task 2. The glyph `false` sentinel matches the Plan 3 default -- an empty glyph field means "use the source marker".)

- [ ] **Step 2: Screenshot check (live base-skin edit)**

`reload_lua`. Create a stylesheet, assign it to a journal rendered in a modal (Plan 2/3 harness). Open the stylesheet editor (or call `SetData`), `screenshot` to confirm the Heading/Body/Bullet rows appear. Then through the editor (or by simulating the `onset` calls + upload), change Heading 1 size to 300 and color to gold; the open journal must re-skin live (Plan 2 monitor). `screenshot` the journal, confirm the heading changed. Report observations. Clean up.

- [ ] **Step 3: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): curated base-skin property editor"
```

---

## Task 4: Curated named-class editor

**Files:**
- Modify: `DocumentSystem/MarkdownDocument.lua` (extend `JournalStyleEditor_BuildForm` with a classes section)

**Interfaces:**
- Consumes: the Task 2 row helpers; `ResolveStylesheet`.
- Produces: a classes list UI (add/remove a class; edit name/kind/text/box). No new exported symbol.

- [ ] **Step 1: Implement the classes section**

Append to `JournalStyleEditor_BuildForm`, before `panel.children = children`. A class is keyed by its name in `sheet.classes`; renaming moves the key. Each class shows curated fields; an "Add class" button and a per-class delete.

```lua
    -- Named classes (curated). Operate on this sheet's OWN classes table.
    sheet.classes = sheet.classes or {}
    children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "Classes" }

    local kindOptions = {
        { id = "inline", text = "Inline {.name text}" },
        { id = "block", text = "Block :::name:::" },
    }

    -- Stable, sorted iteration so the form does not reorder under the user.
    local classNames = {}
    for name,_ in pairs(sheet.classes) do classNames[#classNames+1] = name end
    table.sort(classNames)

    for _, name in ipairs(classNames) do
        local cls = sheet.classes[name]
        cls.text = cls.text or {}
        cls.box = cls.box or {}

        children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "  ." .. name }

        -- Rename: moves the key.
        children[#children+1] = JSE_TextRow("    Name:", name, function(v)
            v = string.lower(trim(v))
            if v ~= "" and v ~= name and sheet.classes[v] == nil then
                sheet.classes[v] = sheet.classes[name]
                sheet.classes[name] = nil
                upload()
                JournalStyleEditor_BuildForm(sheet, upload, panel)  -- rebuild with new key
            end
        end)
        children[#children+1] = JSE_DropdownRow("    Kind:", kindOptions, cls.kind or "inline", function(v)
            cls.kind = v; upload()
        end)
        children[#children+1] = JSE_ColorRow("    Text color:", cls.text.color, function(c)
            cls.text.color = c; upload()
        end)
        children[#children+1] = JSE_DropdownRow("    Text weight:", {
            { id = "regular", text = "Regular" }, { id = "bold", text = "Bold" }, { id = "black", text = "Black" },
        }, cls.text.weight or "regular", function(v) cls.text.weight = v; upload() end)
        children[#children+1] = JSE_CheckRow("    Italic", cls.text.italic, function(b)
            cls.text.italic = b; upload()
        end)
        -- Block box fields (shown always; only used when kind == "block")
        children[#children+1] = JSE_ColorRow("    Box bg:", cls.box.bgcolor, function(c)
            cls.box.bgcolor = c; upload()
        end)
        children[#children+1] = JSE_NumberRow("    Box border:", cls.box.border, function(n)
            cls.box.border = n; upload()
        end)
        children[#children+1] = JSE_ColorRow("    Box border color:", cls.box.borderColor, function(c)
            cls.box.borderColor = c; upload()
        end)
        children[#children+1] = JSE_NumberRow("    Box corner radius:", cls.box.cornerRadius, function(n)
            cls.box.cornerRadius = n; upload()
        end)
        children[#children+1] = JSE_NumberRow("    Box padding:", cls.box.pad, function(n)
            cls.box.pad = n; upload()
        end)
        children[#children+1] = gui.Button{ text = "Delete class ." .. name, width = "auto", height = 24,
            click = function()
                sheet.classes[name] = nil
                upload()
                JournalStyleEditor_BuildForm(sheet, upload, panel)
            end }
    end

    children[#children+1] = gui.Button{ text = "Add class", width = "auto", height = 28,
        click = function()
            local n, i = "class", 1
            while sheet.classes[n] ~= nil do i = i + 1; n = "class" .. i end
            sheet.classes[n] = { kind = "inline", text = {}, box = {} }
            upload()
            JournalStyleEditor_BuildForm(sheet, upload, panel)
        end }
```

(`trim` is an existing global string helper used elsewhere in this file. The rename/delete/add handlers rebuild the form via `JournalStyleEditor_BuildForm` so the list reflects the change; the function is already forward-declared, so the recursive call resolves.)

- [ ] **Step 2: Screenshot check (author + apply classes)**

`reload_lua`. Open the stylesheet editor for a sheet, `screenshot` to confirm the Classes section + "Add class" button. Add an inline class, set its text color/bold; add a block class, set box bg/border. Then render a journal (assigned this sheet) whose content uses `{.classN text}` and `::: classM ... :::`, `screenshot`, and confirm both render styled (Plan 3). Report observations. Clean up.

- [ ] **Step 3: Commit**

```bash
git add "DocumentSystem/MarkdownDocument.lua"
git commit -m "feat(journal): curated named-class editor"
```

---

## Self-Review

**Spec coverage (Plan 4 / curated scope):**
- "Journal editor gains a stylesheet picker that sets MarkdownDocument.styleSheetId" -- Task 1. PASS.
- "Stylesheet editor panel hosted in an existing DocumentSystem/Compendium file; lists stylesheets; name + parentId picker; only-override semantics; live preview" -- Tasks 2-4 (Compendium-hosted; name + parent; override semantics via display-resolved/write-own; live re-render via the Plan 2 monitor rather than a dedicated preview pane). PASS for the curated set.
- "base-skin sections with only-override semantics" -- Task 3 (curated: headings size/color/weight/caps, body color, bullet glyph/color). PARTIAL by design (curated scope chosen); long-tail fields documented as import/code-only.
- "a list of named classes, each toggling inline/block and exposing relevant property fields" -- Task 4 (curated: name/kind/text color+weight+italic/box bgcolor+border+borderColor+cornerRadius+pad). PARTIAL by design.
- Surfacing via Compendium category -- Task 2 (`Compendium.Register`). PASS.

**Placeholder scan:** No "TBD"/"handle edge cases". Form code is complete via shared row helpers + data-driven loops (headings 1-6; sorted class iteration). Task 1 Step 5 and Task 2 Step 5 contain "if you cannot drive the Compendium from the bridge, render into a modal" -- a concrete fallback for the harness, not a placeholder. The persistence verify-and-wire step in Task 1 is a concrete instruction with the exact existing mechanism named (`checkChanges`/`needsave`/`savedoc`).

**Type consistency:** `JournalStylesheet.PickerOptions()`/`CreateNew()`/`CreateEditor()`; `JournalStyleEditor_SetData`/`JournalStyleEditor_BuildForm`; `JSE_TextRow`/`JSE_ColorRow`/`JSE_NumberRow`/`JSE_CheckRow`/`JSE_DropdownRow` are used identically across tasks. Field names match the Plan 1 schema (`base.headings[n].{sizePct,color,weight,caps}`, `base.body.color`, `base.bullet.{glyph,color}`, `classes[name].{kind,text.{color,weight,italic},box.{bgcolor,border,borderColor,cornerRadius,pad}}`) and the Plan 3 `glyph=false` sentinel.

---

## Deferred / documented limitations

- **Curated fields only** (per the chosen scope): tracking, underline/strike/mark, font, ordered-list styling, quote/rule fields, and `box.bgslice`/`gradient`/`beveledcorners`/`inset` are authored via import/code, not the UI.
- **No "clear to inherit"** in the curated UI: a field, once set, stays an override. Resetting to inherit is an import/code edit.
- **Per-class `font`** still needs the asset pack (Plans 2-3), so no font control.
- **Color values are literal hex** from `gui.ColorPicker`; `@token` colors are an import/code feature.
- A future pass could add a dedicated in-editor preview pane; v1 relies on the live monitor updating any open journal that uses the sheet.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-18-journal-stylesheets-editor.md`. This is Plan 4 of 4 (final).

Two execution options:

1. **Subagent-Driven (recommended)** - fresh implementer per task + spec/quality review between tasks. DMHub running for the bridge (logic + screenshot verification).
2. **Inline Execution** - execute tasks here with checkpoints.

Which approach?
