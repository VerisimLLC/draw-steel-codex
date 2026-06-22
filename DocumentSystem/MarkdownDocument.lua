local mod = dmhub.GetModLoading()

---@class MarkdownDocument:CustomDocument
MarkdownDocument = RegisterGameType("MarkdownDocument", "CustomDocument")
MarkdownDocument.vscroll = false
-- Id of the JournalStylesheet that re-skins this document. `false` = built-in
-- default skin. (false is the codebase sentinel for an optional id; a nil
-- default does NOT register a readable field, so reads would throw. Confirmed
-- by Task 1, which hit the same constraint with parentId.)
-- Auto-serialized; round-trips through document upload.
MarkdownDocument.styleSheetId = false

local g_markdownStyle = gui.MarkdownStyle {
    ["#  "] = "<size=200%><b>", ["/#  "] = "</b></size>",
    ["# "] = "<size=200%><b>", ["/# "] = "</b></size>",
    ["## "] = "<size=180%><b>", ["/## "] = "</b></size>",
    ["### "] = "<size=160%><b>", ["/### "] = "</b></size>",
    ["#### "] = "<size=140%><b>", ["/#### "] = "</b></size>",
    ["##### "] = "<size=120%><b>", ["/##### "] = "</b></size>",
}

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
JournalStylesheet.parentId = false
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
        [1] = { sizePct = 200, font = nil, color = nil, weight = "bold", caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [2] = { sizePct = 180, font = nil, color = nil, weight = "bold", caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [3] = { sizePct = 160, font = nil, color = nil, weight = "bold", caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [4] = { sizePct = 140, font = nil, color = nil, weight = "bold", caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [5] = { sizePct = 120, font = nil, color = nil, weight = "bold", caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
        [6] = { sizePct = 120, font = nil, color = nil, weight = "bold", caps = nil, tracking = 0, spaceBefore = 0, spaceAfter = 0 },
    },
    body    = { font = nil, color = nil, sizePct = 100, lineHeight = nil, paragraphSpacing = nil, firstLineIndent = 0 },
    bullet  = { glyph = false, glyphFont = nil, color = nil, indent = 0, hangingIndent = 0, spacing = 0 },
    ordered = { color = nil, indent = 0, hangingIndent = 0, spacing = 0 },
    quote   = { font = nil, color = nil, bgcolor = nil, bold = false, italic = false, justify = nil, barColor = nil, inset = 0 },
    rule    = { image = nil, color = nil, thickness = 1, margin = 0 },
    link    = { color = nil, underline = true },
    -- page.margin (optional, px): symmetric inner padding insetting content from
    -- the page edges. Unset/0 = edge-to-edge (default).
    page    = { bgcolor = false },
    blocks  = {
        powerRoll     = { box = {}, inner = {} },
        table         = { box = {}, inner = {} },
        rollableTable = { box = {}, inner = {} },
        collapse      = { box = {}, inner = {} },
    },
    embed   = { box = {} },
    button  = { box = {}, text = {} },
}

-- Read-only accessor (deep copy) so callers/tests cannot mutate the canonical
-- default. DeepCopy is a global utility used throughout the codebase.
function JournalStylesheet.DefaultSkin()
    return DeepCopy(g_defaultSkin)
end

-- =============================================================================
-- Task 2: Cascade resolver (inheritance + memoization + cycle defense)
-- =============================================================================

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
    for _, key in ipairs({"body", "bullet", "ordered", "quote", "rule", "link", "page", "embed", "button"}) do
        out[key] = MergeSection(parent and parent[key], child[key])
    end
    -- blocks: per-block-type box merge (each block type has its own box override)
    out.blocks = {}
    local pblk = (parent and parent.blocks) or {}
    local cblk = child.blocks or {}
    for _, btype in ipairs({"powerRoll", "table", "rollableTable", "collapse"}) do
        out.blocks[btype] = {
            box   = MergeSection((pblk[btype] or {}).box,   (cblk[btype] or {}).box),
            inner = MergeSection((pblk[btype] or {}).inner, (cblk[btype] or {}).inner),
        }
    end
    return out
end

-- Merge class dictionaries: child class entries override parent entries by name.
-- Within a class, text/box sub-tables merge child-over-parent.
-- Every returned entry is a fresh table so callers cannot corrupt stored objects.
local function MergeClasses(parent, child)
    local out = {}
    parent = parent or {}
    child = child or {}
    for name, cls in pairs(parent) do
        out[name] = { kind = cls.kind, text = MergeSection(cls.text, nil), box = MergeSection(cls.box, nil) }
    end
    for name, cls in pairs(child) do
        local base = out[name]
        if type(base) == "table" then
            out[name] = { kind = cls.kind or base.kind, text = MergeSection(base.text, cls.text), box = MergeSection(base.box, cls.box) }
        else
            out[name] = { kind = cls.kind, text = MergeSection(cls.text, nil), box = MergeSection(cls.box, nil) }
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
    while cur do  -- a falsy parentId (the `false` no-parent sentinel) stops the walk
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

---@class ResolvedStylesheet
---@field base table
---@field classes table

--- ResolveStylesheet is a callable table so that ClearCache can be attached as
--- a field. Call it as ResolveStylesheet(id) or ResolveStylesheet.ClearCache().
---
--- Resolve a stylesheet id to a fully-merged { base, classes }. nil/unknown id
--- returns the default skin with empty classes. Result is memoized per id.
--- @param id string|nil
--- @return ResolvedStylesheet
ResolveStylesheet = setmetatable({}, {
    __call = function(self, id)
        local key = id or "@default"
        local cached = g_resolveCache[key]
        if cached ~= nil then return cached end

        -- Default: a fresh, fully-populated copy of the default skin. MergeSkin
        -- always builds new tables, so we never hand back (and cache) the raw
        -- g_defaultSkin reference, which must stay immutable. This is also the
        -- graceful fallthrough for a falsy id (nil / the `false` sentinel) AND
        -- for a truthy-but-unknown id whose chain comes back empty.
        local base = MergeSkin(g_defaultSkin, nil)
        local classes = {}
        if id then
            local chain = BuildChain(id)
            for _, sheet in ipairs(chain) do
                base = MergeSkin(base, sheet:try_get("base"))
                classes = MergeClasses(classes, sheet:try_get("classes"))
            end
        end

        local result = { base = base, classes = classes }
        g_resolveCache[key] = result
        return result
    end,
})

function ResolveStylesheet.ClearCache()
    g_resolveCache = {}
end

--- Resolve this document's stylesheet (or the default skin if unset).
--- @return ResolvedStylesheet
function MarkdownDocument:GetResolvedStylesheet()
    return ResolveStylesheet(self.styleSheetId)
end

-- Dropdown options for choosing a journal stylesheet. First entry (id "") means
-- "no stylesheet -> built-in default skin". Sorted by name.
function JournalStylesheet.PickerOptions()
    local result = { { id = "", text = "Default" } }
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

-- =============================================================================
-- Stylesheet CRUD (Task 2: editor UI)
-- =============================================================================

function JournalStylesheet.CreateNew()
    return JournalStylesheet.Create()
end

-- Forward-declared so JournalStyleEditor_SetData can call it before its
-- definition below.
local JournalStyleEditor_BuildForm

-- Build the read-only "showcase" markdown for the stylesheet editor preview:
-- a fixed base + built-in-block sample, then a sample per named class.
local function BuildShowcaseContent(sheet)
    local lines = {
        "# Chapter Title",
        "## Section Heading",
        "Body paragraph text showing the body color and the page background.",
        "### Sub-heading",
        "- First bullet item",
        "- Second bullet item",
        "1. First numbered item",
        "2. Second numbered item",
        "#### Smaller Heading",
        "> A read-aloud style blockquote line.",
        "",
        "---",
        "",
        "##### Power Roll",
        "|Might Test: Might",
        "| You fail.",
        "| You succeed at a cost.",
        "| You succeed.",
        "",
        "|Column A|Column B|",
        "|---|---|",
        "|a1|b1|",
        "|a2|b2|",
        "",
        "+ A Collapse Section",
        "Content inside the collapse section.",
    }
    local classNames = {}
    for name, _ in pairs(sheet:try_get("classes") or {}) do classNames[#classNames + 1] = name end
    table.sort(classNames)
    if #classNames > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "###### Classes"
        for _, name in ipairs(classNames) do
            local cls = sheet.classes[name]
            if cls.kind == "block" then
                lines[#lines + 1] = "::: " .. name
                lines[#lines + 1] = "Block class '" .. name .. "' sample."
                lines[#lines + 1] = ":::"
            else
                lines[#lines + 1] = "Inline: {." .. name .. " sample text}"
            end
        end
    end
    return table.concat(lines, "\n")
end

-- Test hook.
MarkdownDocument.__BuildShowcaseContent = BuildShowcaseContent

-- SetData fetches the entry and (re)builds the editor form. Re-resolving on
-- each field change keeps displayed (inherited) values current.
local function JournalStyleEditor_SetData(tableName, formPanel, previewDoc, previewPanel, id)
    local sheet = (dmhub.GetTable(tableName) or {})[id]
    if sheet == nil then
        formPanel.children = {}
        previewDoc.styleSheetId = false
        previewDoc:SetTextContent("")
        previewPanel:FireEventTree("refreshDocument", previewDoc)
        return
    end
    formPanel.data.sheetid = id
    previewDoc.styleSheetId = id
    local upload = function()
        dmhub.SetAndUploadTableItem(tableName, sheet)
    end
    JournalStyleEditor_BuildForm(sheet, upload, formPanel)
end

function JournalStylesheet.CreateEditor()
    local formPanel = gui.Panel{
        vscroll = true, flow = "vertical", pad = 20, borderBox = true,
        width = "50%", height = "100%",
        data = { sheetid = "" },
    }
    local previewDoc = MarkdownDocument.new{ content = "", annotations = {}, styleSheetId = false }
    local previewPanel = gui.Panel{
        vscroll = true, flow = "vertical", borderBox = true,
        width = "50%-8", height = "100%", lmargin = 8, hpad = 16, vpad = 12,
        previewDoc:DisplayPanel{ width = "100%", height = "auto" },
    }
    -- Let BuildForm reach the preview so class add/remove/rename regenerates it.
    formPanel.data.previewDoc = previewDoc
    formPanel.data.previewPanel = previewPanel

    local root = gui.Panel{
        -- Fixed width, left-aligned: the Compendium host places this editor in a
        -- horizontal flow next to an auto-width list panel. A "100%" root would
        -- claim the whole parent and push the preview half off the right edge, so
        -- use a fixed width like the other compendium editors (e.g. Conditions).
        flow = "horizontal", width = 1200, height = "100%", halign = "left",
        data = {
            SetData = function(tableName, id)
                JournalStyleEditor_SetData(tableName, formPanel, previewDoc, previewPanel, id)
            end,
        },
        formPanel,
        previewPanel,
    }
    return root
end

-- Form row helpers (shared by base-skin and class editors). Each returns a panel.
local function JSE_TextRow(label, value, onset)
    return gui.Panel{ classes = {"formStackedRow"},
        gui.Label{ classes = {"formStacked"}, text = label },
        gui.Input{ classes = {"formStacked"}, text = value or "",
            change = function(element) onset(element.text) end },
    }
end

local function JSE_ColorRow(label, value, onset)
    return gui.Panel{ classes = {"formStackedRow"},
        gui.Label{ classes = {"formStacked"}, text = label },
        gui.ColorPicker{ value = value or "white", width = 24, height = 24, valign = "center",
            -- element.value is a Color userdata; the renderer needs a hex string.
            -- Color.tostring gives "#RRGGBBAA"; pass strings through unchanged.
            confirm = function(element)
                local v = element.value
                if type(v) == "userdata" then v = v.tostring end
                onset(v)
            end },
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
            change = function(element) onset(element.value == true) end },
    }
end

local function JSE_DropdownRow(label, options, idChosen, onset)
    return gui.Panel{ classes = {"formStackedRow"},
        gui.Label{ classes = {"formStacked"}, text = label },
        gui.Dropdown{ classes = {"formStacked"}, options = options, idChosen = idChosen or "",
            change = function(element) onset(element.idChosen) end },
    }
end

JournalStyleEditor_BuildForm = function(sheet, upload, panel)
    local children = {}

    -- Name
    children[#children+1] = JSE_TextRow("Name:", sheet.name, function(v)
        sheet.name = v; upload()
    end)

    -- Parent (inheritance). Options are all OTHER stylesheets plus "(No parent)".
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

    -- Page (curated: bgcolor)
    children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "Page" }
    children[#children+1] = JSE_ColorRow("  Background:", (resolvedBase.page or {}).bgcolor, function(c)
        ownBaseSection("page").bgcolor = c; upload()
    end)

    -- Built-in block frames (auto-applied by syntax; no author class).
    local blockTypes = {
        { key = "powerRoll",     label = "Power roll" },
        { key = "table",         label = "Table" },
        { key = "rollableTable", label = "Rollable table (header)" },
        { key = "collapse",      label = "Collapse section" },
    }
    local function ownBlockBox(bkey)
        sheet.base = sheet.base or {}
        sheet.base.blocks = sheet.base.blocks or {}
        sheet.base.blocks[bkey] = sheet.base.blocks[bkey] or {}
        sheet.base.blocks[bkey].box = sheet.base.blocks[bkey].box or {}
        return sheet.base.blocks[bkey].box
    end
    local function ownBlockInner(bkey)
        sheet.base = sheet.base or {}
        sheet.base.blocks = sheet.base.blocks or {}
        sheet.base.blocks[bkey] = sheet.base.blocks[bkey] or {}
        sheet.base.blocks[bkey].inner = sheet.base.blocks[bkey].inner or {}
        return sheet.base.blocks[bkey].inner
    end
    children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "Blocks" }
    for _, bt in ipairs(blockTypes) do
        local rbox = (((resolvedBase.blocks or {})[bt.key]) or {}).box or {}
        children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "  " .. bt.label }
        children[#children+1] = JSE_ColorRow("    Background:", rbox.bgcolor, function(c)
            ownBlockBox(bt.key).bgcolor = c; upload()
        end)
        children[#children+1] = JSE_NumberRow("    Border:", rbox.border, function(n)
            ownBlockBox(bt.key).border = n; upload()
        end)
        children[#children+1] = JSE_ColorRow("    Border color:", rbox.borderColor, function(c)
            ownBlockBox(bt.key).borderColor = c; upload()
        end)
        children[#children+1] = JSE_NumberRow("    Corner radius:", rbox.cornerRadius, function(n)
            ownBlockBox(bt.key).cornerRadius = n; upload()
        end)
        children[#children+1] = JSE_NumberRow("    Padding:", rbox.pad, function(n)
            ownBlockBox(bt.key).pad = n; upload()
        end)
        local rinner = (((resolvedBase.blocks or {})[bt.key]) or {}).inner or {}
        children[#children+1] = JSE_ColorRow("    Inner background:", rinner.bgcolor, function(c)
            ownBlockInner(bt.key).bgcolor = c; upload()
        end)
        children[#children+1] = JSE_ColorRow("    Inner text:", rinner.color, function(c)
            ownBlockInner(bt.key).color = c; upload()
        end)
        if bt.key == "table" or bt.key == "rollableTable" then
            children[#children+1] = JSE_ColorRow("    Alt row tint:", rinner.altcolor, function(c)
                ownBlockInner(bt.key).altcolor = c; upload()
            end)
        end
    end

    -- Bullet (curated: glyph, color)
    children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "Bullet" }
    children[#children+1] = JSE_TextRow("  Glyph:", (resolvedBase.bullet or {}).glyph, function(v)
        ownBaseSection("bullet").glyph = (v ~= "" and v) or false; upload()
    end)
    children[#children+1] = JSE_ColorRow("  Color:", (resolvedBase.bullet or {}).color, function(c)
        ownBaseSection("bullet").color = c; upload()
    end)

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

        -- Show the syntax the author actually types: {.name} for inline, :::name for block.
        local syntaxLabel = (cls.kind == "block") and (":::" .. name) or ("{." .. name .. "}")
        children[#children+1] = gui.Label{ classes = {"formStacked"}, text = "  " .. syntaxLabel }

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
        children[#children+1] = gui.Button{ text = "Delete class: " .. name, width = "auto", height = 24,
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

    panel.children = children

    -- Live preview: regenerate the showcase content for this sheet and refresh.
    -- (Base-skin/frame/color edits re-render via the journalStyles monitor that
    -- every DisplayPanel carries; class add/remove/rename rebuilds the form, so
    -- regenerating here picks up new/removed class samples.)
    if panel.data.previewDoc ~= nil then
        panel.data.previewDoc:SetTextContent(BuildShowcaseContent(sheet))
        if panel.data.previewPanel ~= nil then
            panel.data.previewPanel:FireEventTree("refreshDocument", panel.data.previewDoc)
        end
    end
end

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

-- Apply a box "frame" to a container panel: clears the frame props first (so a
-- reused cached panel keeps no stale frame and an empty box is a no-op), then
-- applies any set props. Same vocabulary as the callout-box render.
local function ApplyBlockFrame(panel, box)
    box = box or {}
    local ss = panel.selfStyle
    ss.bgimage = nil
    ss.bgcolor = nil
    ss.borderImage = nil
    ss.border = nil
    ss.borderColor = nil
    ss.cornerRadius = nil
    ss.pad = nil
    ss.borderBox = nil
    if box.bgcolor then ss.bgimage = "panels/square.png"; ss.bgcolor = SkinColor(box.bgcolor) end
    if box.bgimage then ss.bgimage = box.bgimage end
    if box.borderImage then ss.borderImage = box.borderImage end
    if box.border then ss.border = box.border end
    if box.borderColor then ss.borderColor = SkinColor(box.borderColor) end
    if box.cornerRadius then ss.cornerRadius = box.cornerRadius end
    if box.pad then ss.pad = box.pad; ss.borderBox = true end
end

-- Test hook.
MarkdownDocument.__ApplyBlockFrame = ApplyBlockFrame

-- Theme a blockquote panel from the `quote` skin. The blockquote's bg + left
-- accent bar come from the {"panel","blockQuote"} theme class; setting selfStyle
-- overrides the class. Clears to nil when unset so an unstyled blockquote reverts
-- to the theme (the bar GEOMETRY stays from the class -- only its color changes).
-- Called every render because the blockquote panel is cached and reused.
local function ApplyQuoteFrame(panel, quote)
    quote = quote or {}
    local ss = panel.selfStyle
    local bg = SkinColor(quote.bgcolor)
    if bg then
        ss.bgimage = "panels/square.png"; ss.bgcolor = bg
    else
        ss.bgimage = nil; ss.bgcolor = nil
    end
    ss.borderColor = SkinColor(quote.barColor) or nil
    ss.hpad = (type(quote.inset) == "number" and quote.inset > 0) and quote.inset or nil
end
MarkdownDocument.__ApplyQuoteFrame = ApplyQuoteFrame

-- Apply a stylesheet's inner block styling to a built-in block's inner content
-- (power-roll tier rows, collapse body). Mirrors ApplyBlockFrame: re-runs every
-- render, no-ops when inner is unset so default (dark) rendering is preserved, and
-- restores defaults on a reused panel when inner is later cleared.
--
-- The inner darkness is NOT an inline background: every inner element carries the
-- engine "uiblur" (dark frosted-glass) class. So we strip uiblur and paint our own
-- opaque background on every non-root, non-label descendant panel, and set the
-- label text color.
--
-- NOTE: this is used for power roll and collapse, whose inner elements are plain
-- markdown-created panels. TABLES are styled differently -- a gui.Table colors its
-- rows from theme class-selectors during its own layout, so external painting does
-- not stick; tables use the Table's own `styles` instead (see TableInnerStyles and
-- the table render branch).
-- blockType is one of "powerRoll" | "collapse" (kept for call-site symmetry).
local function ApplyBlockInner(panel, inner, blockType)
    inner = inner or {}
    local bg  = inner.bgcolor and SkinColor(inner.bgcolor) or nil
    local txt = inner.color   and SkinColor(inner.color)   or nil
    local active = (bg ~= nil) or (txt ~= nil)
    local function visit(el, isRoot)
        if el == nil then return end
        local cls; pcall(function() cls = el.classes end)
        local ss; pcall(function() ss = el.selfStyle end)
        local isLabel = cls and table.contains(cls, "label")
        local paintsBg = (not isRoot) and (not isLabel)
        if ss then
            if active then
                pcall(function() el:SetClass("uiblur", false) end)
                if paintsBg and bg then ss.bgimage = "panels/square.png"; ss.bgcolor = bg end
                if isLabel and txt then ss.color = txt end
            else
                -- inactive: restore the default dark glass and clear what we set
                pcall(function() el:SetClass("uiblur", true) end)
                if paintsBg then ss.bgimage = nil; ss.bgcolor = nil end
                if isLabel then ss.color = nil end
            end
        end
        local kids; pcall(function() kids = el.children end)
        if kids then for _, c in ipairs(kids) do visit(c, false) end end
    end
    visit(panel, true)
end

-- Test hook.
MarkdownDocument.__ApplyBlockInner = ApplyBlockInner

-- Build instance style overrides for a gui.Table from a block's inner config.
-- A gui.Table colors its rows from the theme's row/oddRow/evenRow/headerRow
-- selectors during its own layout (so painting rows from outside does not stick).
-- The Table's `styles` DO apply -- but only when set at construction; the setter
-- rejects post-construction updates. So the table render branch passes these into
-- the constructor and rebuilds the Table when the inner config changes.
-- Returns nil when inner is unset (the Table keeps its default theme look).
-- Pass RAW values: the style system resolves color tokens/hex itself.
local function TableInnerStyles(inner)
    inner = inner or {}
    local function val(c) if c == nil or c == false or c == "" then return nil end return c end
    local bg  = val(inner.bgcolor)
    local txt = val(inner.color)
    local alt = val(inner.altcolor)
    if bg == nil and txt == nil and alt == nil then return nil end
    local styles = {}
    if bg then
        styles[#styles + 1] = { selectors = {"row", "headerRow"}, bgcolor = bg }
        styles[#styles + 1] = { selectors = {"row", "oddRow"},  bgcolor = bg }
        styles[#styles + 1] = { selectors = {"row", "evenRow"}, bgcolor = alt or bg }
    elseif alt then
        styles[#styles + 1] = { selectors = {"row", "evenRow"}, bgcolor = alt }
    end
    if txt then
        styles[#styles + 1] = { selectors = {"label"}, color = txt }
    end
    return styles
end
MarkdownDocument.__TableInnerStyles = TableInnerStyles

-- Signature of a block's inner config, to detect when a cached gui.Table must be
-- rebuilt (its styles can only be set at construction).
local function TableInnerSig(inner)
    inner = inner or {}
    return tostring(inner.bgcolor) .. ":" .. tostring(inner.color) .. ":" .. tostring(inner.altcolor)
end


-- TMP alignment values keyed by stylesheet value. justify -> TMP "justified".
local g_alignTMP = { left = "left", center = "center", right = "right", justify = "justified" }

-- Rich-tag types that are standalone embeds (framed by a stylesheet embed.box).
-- Inline widgets (dice/counter/checkbox/bar/macro/timer/sound/reminder/setting/
-- fishing) are intentionally excluded -- they often sit next to text.
local g_standaloneEmbedTags = {
    encounter = true, image = true, party = true,
    follower = true, scene = true, map = true,
}

-- Wrap a built line in a paragraph-level <align> tag when align is recognized.
-- Unset/unknown -> content unchanged (no tag), so the default skin is a no-op.
-- The closing </align> resets alignment for the next line (prevents bleed).
local function SkinAlign(align, content)
    local v = g_alignTMP[align]
    if v == nil then return content end
    return string.format("<align=%s>%s</align>", v, content)
end

-- Lazily-built lookup of valid font ids from gui.availableFonts (the faces
-- configured for this build). Built on first use so it is ready even if the
-- font list populates after this file loads.
local g_fontSet = nil
local function FontAvailable(id)
    if g_fontSet == nil then
        g_fontSet = {}
        for _, f in ipairs(gui.availableFonts or {}) do g_fontSet[f] = true end
    end
    return g_fontSet[id] == true
end

-- Wrap content in a per-span <font> tag when `font` is a valid available id.
-- Unset/unknown -> content unchanged (no tag), so the default skin is a no-op
-- and an unavailable id falls back to the default face (never leaks a literal
-- tag). The closing </font> resets the face for the next line (no bleed).
local function SkinFont(font, content)
    if type(font) == "string" and font ~= "" and FontAvailable(font) then
        return string.format("<font=\"%s\">%s</font>", font, content)
    end
    return content
end
MarkdownDocument.__SkinFont = SkinFont

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
    return SkinAlign(h.align, SkinFont(h.font, open .. content .. close))
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
    -- line-height: percent of the line's font size. Unset or 100 = no tag, so
    -- the default skin stays a visual no-op. Wrapped + closed so it does not
    -- bleed into adjacent heading lines that set no line-height.
    if body.lineHeight and body.lineHeight ~= 100 then
        open = open .. string.format("<line-height=%d%%>", body.lineHeight)
        close = "</line-height>" .. close
    end
    -- first-line indent (px). Positive indents the first visual line via a
    -- horizontal space; negative is a hanging indent (wrapped lines pushed in,
    -- matching SkinBulletMarkup). 0/nil = no markup.
    local fli = body.firstLineIndent or 0
    if fli > 0 then
        open = open .. string.format("<space=%dpx>", fli)
    elseif fli < 0 then
        open = string.format("<indent=%dpx>", -fli) .. open
        close = close .. "</indent>"
    end
    return SkinAlign(body.align, SkinFont(body.font, open .. content .. close))
end

-- Unordered bullet. `defmarker` is the original marker character ("-" or "*"),
-- used as the glyph when no skin glyph is set so unstyled journals are unchanged.
local function SkinBulletMarkup(bullet, defmarker, content, bodyColor, bodyFont)
    bullet = bullet or {}
    local glyph = bullet.glyph
    if glyph == nil or glyph == false or glyph == "" then glyph = defmarker end
    local bodyCol = SkinColor(bodyColor)
    -- Marker uses its own color if set, else the body text color so it stays as
    -- readable as the item text.
    local markerColor = SkinColor(bullet.color) or bodyCol
    local indent = bullet.indent or 0
    local prefix
    if markerColor then
        prefix = string.format("<color=%s>%s</color>", markerColor, glyph)
    else
        prefix = glyph
    end
    -- Item text inherits the body color so list items read the same as body
    -- paragraphs. Default skin (body color unset) emits no tag -> unchanged.
    local body = content
    if bodyCol then
        body = string.format("<color=%s>%s</color>", bodyCol, content)
    end
    local line = SkinFont(bullet.font or bodyFont, prefix .. " " .. body)
    if indent ~= 0 then
        line = string.format("<indent=%dpx>%s</indent>", indent, line)
    end
    return SkinAlign(bullet.align, line)
end

-- Ordered list item. `marker` is the literal "N." token. Default = unchanged.
local function SkinOrderedMarkup(ordered, marker, content, bodyColor, bodyFont)
    ordered = ordered or {}
    local bodyCol = SkinColor(bodyColor)
    -- Marker uses its own color if set, else the body text color (readable).
    local markerColor = SkinColor(ordered.color) or bodyCol
    local indent = ordered.indent or 0
    local prefix
    if markerColor then
        prefix = string.format("<color=%s>%s</color>", markerColor, marker)
    else
        prefix = marker
    end
    -- Item text inherits the body color (default skin: unset -> no tag).
    local body = content
    if bodyCol then
        body = string.format("<color=%s>%s</color>", bodyCol, content)
    end
    local line = SkinFont(ordered.font or bodyFont, prefix .. " " .. body)
    if indent ~= 0 then
        line = string.format("<indent=%dpx>%s</indent>", indent, line)
    end
    return SkinAlign(ordered.align, line)
end

-- Wrap blockquote body text per the quote skin (color/italic). Default skin
-- (no color, italic=false) returns the text unchanged.
local function SkinQuoteText(quote, content)
    quote = quote or {}
    if type(content) ~= "string" then return content end
    local open, close = "", ""
    local color = SkinColor(quote.color)
    if color then open = open .. string.format("<color=%s>", color); close = "</color>" .. close end
    if quote.italic == true then open = open .. "<i>"; close = "</i>" .. close end
    return SkinFont(quote.font, open .. content .. close)
end

-- Test hook.
MarkdownDocument.__SkinQuoteText = SkinQuoteText

-- Set of heading levels (1..5) that have a rule (weight > 0), or nil if none.
-- Returns nil when NO level has a rule, enabling the fast-path single-label render.
-- Level 6 is excluded: ApplySkinToText renders it as body text, not a heading.
local function HeadingRuleLevels(skin)
    local out = nil
    local hs = (skin and skin.headings) or {}
    for n = 1, 5 do
        local r = (hs[n] or {}).rule
        if r and (r.weight or 0) > 0 then out = out or {}; out[n] = true end
    end
    return out
end

-- True if the resolved skin sets a recognized align on any text element
-- (headings 1..5, body, bullet, ordered). Used to widen block text labels so
-- short lines have room to align.
local function SkinUsesAlign(skin)
    if skin == nil then return false end
    local function has(sec) return sec ~= nil and g_alignTMP[sec.align] ~= nil end
    if has(skin.body) or has(skin.bullet) or has(skin.ordered) then return true end
    local hs = skin.headings or {}
    for n = 1, 5 do if has(hs[n]) then return true end end
    return false
end

-- Build/refresh a thin rule panel from a heading entry's `rule` sub-table.
-- `panel` is a reused gui.Panel (or nil to create a new one). Returns the panel.
local function BuildHeadingRulePanel(panel, h)
    h = h or {}
    local r = h.rule or {}
    panel = panel or gui.Panel { valign = "top", borderBox = true }
    local ss = panel.selfStyle
    ss.bgimage = "panels/square.png"
    ss.bgcolor = SkinColor(r.color) or SkinColor(h.color)  -- nil -> no override
    ss.height = r.weight or 1
    local indent = r.indent or 0
    ss.width = indent > 0 and string.format("100%%-%d", indent * 2) or "100%"
    ss.lmargin = indent
    ss.rmargin = indent
    ss.tmargin = r.offset or 0          -- heading -> rule gap
    ss.bmargin = h.spaceAfter or 0      -- rule -> body gap (spaceAfter moves here)
    return panel
end

-- Split a text run at ruled heading lines. Returns a list of
-- { text=..., ruleLevel=n_or_nil } entries; each entry whose ruleLevel is
-- non-nil ended at (and includes) a heading of that level. The trailing
-- remainder is its own entry with ruleLevel=nil. A single leading newline is
-- stripped from non-first trailing segments so the blank markdown separator
-- line between a heading and the next paragraph does not double the rule
-- panel bmargin gap.
local function SplitRunAtRuledHeadings(text, ruledLevels)
    local segments = {}
    local accum = {}
    local start = 1
    while true do
        local nl = string.find(text, "\n", start, true)
        local line
        if nl == nil then
            line = string.sub(text, start)
        else
            line = string.sub(text, start, nl - 1)
        end
        accum[#accum + 1] = line
        local hashes = string.match(line, "^(#+) ")
        if hashes ~= nil and #hashes >= 1 and #hashes <= 5 and ruledLevels[#hashes] then
            local segText = table.concat(accum, "\n")
            -- Strip one leading newline from non-first segments: the blank markdown
            -- separator line between a previous rule panel and this paragraph is
            -- accounted for by bmargin, so stripping it keeps spacing consistent.
            if #segments > 0 and string.sub(segText, 1, 1) == "\n" then
                segText = string.sub(segText, 2)
            end
            segments[#segments + 1] = {
                text = segText,
                ruleLevel = #hashes,
            }
            accum = {}
        end
        if nl == nil then break end
        start = nl + 1
    end
    if #accum > 0 then
        local segText = table.concat(accum, "\n")
        -- Strip one leading newline when this follows a ruled heading: the blank
        -- markdown line between heading and body is accounted for by bmargin.
        if #segments > 0 and string.sub(segText, 1, 1) == "\n" then
            segText = string.sub(segText, 2)
        end
        -- Do not emit a trailing segment whose text is empty (e.g. run ends with
        -- a newline immediately after the last ruled heading).
        if segText ~= "" then
            segments[#segments + 1] = { text = segText, ruleLevel = nil }
        end
    end
    return segments
end

-- Test hook for unit tests (mirrors __SkinClassTextMarkup pattern).
MarkdownDocument.__SplitRunAtRuledHeadings = SplitRunAtRuledHeadings

-- Returns true if `text` contains at least one line that is a heading at a
-- level present in ruledLevels (levels 1..5 only). Used as a cheap per-token
-- gate so runs with no ruled heading stay on the fast path even when the skin
-- has a heading rule configured.
local function TextHasRuledHeading(text, ruledLevels)
    local start = 1
    while true do
        local nl = string.find(text, "\n", start, true)
        local line
        if nl == nil then
            line = string.sub(text, start)
        else
            line = string.sub(text, start, nl - 1)
        end
        local hashes = string.match(line, "^(#+) ")
        if hashes ~= nil and #hashes >= 1 and #hashes <= 5 and ruledLevels[#hashes] then
            return true
        end
        if nl == nil then break end
        start = nl + 1
    end
    return false
end

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
    return SkinFont(t.font, open .. content .. close)
end

-- Test hook.
MarkdownDocument.__SkinClassTextMarkup = SkinClassTextMarkup

-- A vertical gap rendered inside a single TMP label: a blank line sized to n px.
-- Returns nil for non-positive n so callers can skip inserting a line.
local function SkinGapLine(n)
    if type(n) ~= "number" or n <= 0 then return nil end
    return string.format("<size=%dpx> </size>", n)
end

local ApplySkinToText
ApplySkinToText = function(text, base, opts)
    if type(text) ~= "string" or text == "" then return text end
    base = base or {}
    local out = {}
    -- Split on \n with a manual string.find loop: this preserves empty lines
    -- between consecutive newlines and a possible empty final segment.
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
    local bodyPS = (base.body or {}).paragraphSpacing
    local bodyColor = (base.body or {}).color
    local bodyFont = (base.body or {}).font
    for _, line in ipairs(lines) do
        local hashes, hContent = string.match(line, "^(#+) (.*)$")
        local bmarker, bContent = string.match(line, "^([%-%*]) (.*)$")
        local onum, oContent = string.match(line, "^(%d+%.) (.*)$")
        if hashes ~= nil and #hashes >= 1 and #hashes <= 5 then
            local h = (base.headings or {})[#hashes] or {}
            local before = SkinGapLine(h.spaceBefore)
            if before then out[#out + 1] = before end
            out[#out + 1] = SkinHeadingMarkup(h, hContent)
            local after = SkinGapLine(h.spaceAfter)
            local ruled = opts and opts.ruledLevels and opts.ruledLevels[#hashes]
            if after and not ruled then out[#out + 1] = after end
        elseif bmarker ~= nil then
            out[#out + 1] = SkinBulletMarkup(base.bullet, bmarker, bContent, bodyColor, bodyFont)
        elseif onum ~= nil then
            out[#out + 1] = SkinOrderedMarkup(base.ordered, onum, oContent, bodyColor, bodyFont)
        elseif line == "" then
            local gap = SkinGapLine(bodyPS)
            out[#out + 1] = gap or SkinBodyMarkup(base.body, line)
        else
            out[#out + 1] = SkinBodyMarkup(base.body, line)
        end
    end
    return table.concat(out, "\n")
end

-- Test hook (no _tmp_ needed; this is a class-level function reference).
MarkdownDocument.__ApplySkinToText = ApplySkinToText

-- Resolve inline {.name inner} spans to the named inline class's text markup.
-- Unknown names, or classes whose kind is not "inline", strip to bare `inner`
-- (graceful fallthrough -- never leave the literal {....} markers visible).
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

local showPreviewSetting = setting{
    id = "markdownEditorShowPreview",
    name = "Show Preview Pane in Markdown Editor",
    default = true,
    storage = "preferences",
}

---@class RichTag
---@field pattern false|string
RichTag = RegisterGameType("RichTag")
RichTag.pattern = false
RichTag.hasEdit = true

function RichTag.Create()
    return RichTag.new {}
end

function RichTag:GetDocument()
    return self:try_get("_tmp_document")
end

function RichTag:UploadDocument()
    if self:has_key("_tmp_document") then
        self._tmp_document:Upload()
    end
end

function RichTag.CreateDisplay(self)
    return gui.Panel {
        width = 10,
        height = 10,
    }
end

function RichTag.CreateEditor(self)
    return gui.Panel {
        width = 1,
        height = 1,
    }
end

function RichTag.GetColorFromToken(token)
    if token.stylingInfo ~= nil and token.stylingInfo.colorStack ~= nil and #token.stylingInfo.colorStack > 0 then
        return token.stylingInfo.colorStack[#token.stylingInfo.colorStack]
    end

    return nil
end

--- @type table<string, RichTag>
MarkdownDocument.RichTagRegistry = {}

--- @param info RichTag
function MarkdownDocument.RegisterRichTag(info)
    MarkdownDocument.RichTagRegistry[info.tag] = info
end

local function StripSpoilers(text)
    local result = ""
    local i, depth = 1, 0
    local markDepth = 0
    local markEnd = nil

    while true do
        local a, b, brace = text:find("([{}])", i)
        if not a then
            if depth == 0 then
                result = result .. text:sub(i)
            end
            break
        end

        if depth == 0 and a > i then
            result = result .. text:sub(i, a - 1)
        end

        if brace == "{" then
            if text:sub(a + 1, a + 1) == "!" and depth == 0 then
                markDepth = markDepth + 1
                b = b + 1
            elseif text:sub(a + 1, a + 1) == "#" and depth == 0 then
                if markDepth == 0 then
                    result = result .. ThemeEngine.ResolveTokens("<alpha=#FF><mark=@fg><color=@fg>")
                    markEnd = "</color></mark>"
                end
                markDepth = markDepth + 1
                b = b + 1
            elseif text:sub(a + 1, a + 1) == ":" and depth == 0 then
                --start of a language.
                local x, y = text:find(":", a + 2)
                if x ~= nil then
                    b = y

                    markDepth = markDepth + 1
                    local langName = string.lower(text:sub(a + 2, x - 1))
                    local languages = dmhub.GetTable(Language.tableName) or {}
                    local bestScore = 0
                    local bestLanguage = nil
                    for langid, language in pairs(languages) do
                        local score = nil
                        local namelc = string.lower(language.name)
                        if namelc == langName then
                            score = 3
                        elseif string.starts_with(namelc, langName) then
                            score = 2
                        else
                            local speakerlc = string.lower(language.speakers)
                            if speakerlc == langName then
                                score = 1
                            elseif string.starts_with(speakerlc, langName) then
                                score = 0.5
                            elseif string.find(speakerlc, langName) ~= nil then
                                score = 0.3
                            end
                        end

                        if score ~= nil and score > bestScore then
                            bestScore = score
                            bestLanguage = language
                        end
                    end

                    local canSpeak = false
                    if bestLanguage ~= nil then
                        result = result .. string.format("(in %s) ", bestLanguage.name)

                        if not dmhub.isDM then
                            local token = dmhub.currentToken
                            if token ~= nil and token.properties:LanguagesKnown()[bestLanguage.id] then
                                canSpeak = true
                            end
                        end
                    end


                    if markDepth == 1 and not canSpeak then
                        --TODO: get fonts working.
                        result = result .. ThemeEngine.ResolveTokens("<alpha=#FF><mark=@fg><color=@fg>")
                        markEnd = "</color></mark>"
                        --result = result .. "<font=\"Tengwar\">"
                        --markEnd = "</font>"
                    end
                end
            elseif text:sub(a + 1, a + 1) == "." and depth == 0 then
                -- Inline class span {.name text}: copy verbatim so the render-time
                -- ApplyInlineClasses pass (which has the resolved classes) handles
                -- it. Stripping here would lose the class for player view.
                local close = text:find("}", a + 1, true)
                if close ~= nil then
                    result = result .. text:sub(a, close)
                    b = close
                else
                    result = result .. text:sub(a)
                    b = #text
                end
            else
                depth = depth + 1
            end
        else --brace == "}"
            if depth > 0 then
                depth = depth - 1
            elseif markDepth > 0 then
                markDepth = markDepth - 1
                if markDepth == 0 and markEnd ~= nil then
                    result = result .. markEnd
                    markEnd = nil
                end
            end
        end
        i = b + 1
    end

    return result
end

local g_hardwiredPowerTableList = {
    { preset = "|easy", tiers = {"You succeed on the task and incur a consequence.", "You succeed on the task.", "You succeed on the task with a reward."}, },
    { preset = "|medium", tiers = {"You fail the task.", "You succeed on the task and incur a consequence.", "You succeed on the task."}, },
    { preset = "|hard", tiers = {"You fail the task and incur a consequence.", "You fail the task.", "You succeed on the task."}, },
}

local g_hardwiredPowerTables = {}

for _,info in ipairs(g_hardwiredPowerTableList) do
    g_hardwiredPowerTables[info.preset] = info.tiers
end

local BreakdownRichTags
BreakdownRichTags = function(content, result, options, extraOutput)
    extraOutput = extraOutput or {}
    options = options or {}
    local isPlayer = options.player

    -- Opt-in source-position tracking for the editor's syntax highlighter (off for every
    -- render caller, so rendering is unaffected). Stamps the 1-based source line range each
    -- colorable token came from; the highlighter maps that back to character offsets. Purely
    -- additive. Not propagated into the recursive table-cell call (its lines are cell-relative),
    -- so cell-inner tokens stay unstamped and the highlighter simply skips them.
    local trackPositions = options.trackPositions
    local function StampLine(tok, firstLine, lastLine)
        if not trackPositions then return end
        tok.srcLine = firstLine
        tok.srcLineEnd = lastLine or firstLine
    end

    if isPlayer then
        content = StripSpoilers(content)
    end

    local stylingInfo = options.stylingInfo or { colorStack = {} }

    local collapseNodes = {}

    result = result or {}
    content = content:gsub("\v", "\n") --replace vertical tabs with newlines.
    content = content:gsub("\r", "")
    local lines = string.split_allow_duplicates(content, '\n')

    local text = ""

    -- Source-line cursor for SyncPreviewScroll's content-aware scroll mapping (only
    -- populated when options.trackPositions is set; see StampLine). currentLine is the
    -- line being parsed; textStartLine remembers the first line that fed visible text into
    -- the run currently accumulating in `text`, so the emitted text token is stamped at
    -- its START (where it begins rendering) rather than the line it happened to flush on.
    local currentLine = 1
    local textStartLine = nil

    local EmitText = function(t, justification)
        local fromAccumulator = (t == nil)
        if t == nil then
            t = text
            text = ""
        end
        if t ~= "" then
            local searchColorStr = t
            local pattern = '^[^\\0]*?(</color>|<color="?(?<color>.*?)"?>)(?<suffix>[^\\0]*)$'
            local matchColor = regex.MatchGroups(searchColorStr, pattern)
            while matchColor ~= nil do
                if matchColor.color ~= nil then
                    local color = matchColor.color
                    stylingInfo.colorStack[#stylingInfo.colorStack + 1] = color
                else
                    if #stylingInfo.colorStack > 0 then
                        stylingInfo.colorStack[#stylingInfo.colorStack] = nil
                    end
                end

                searchColorStr = matchColor.suffix
                matchColor = regex.MatchGroups(searchColorStr, pattern)
            end

            result[#result + 1] = {
                type = "text",
                text = t,
                justification = justification,
                player = isPlayer,
                --trace = debug.traceback(),
            }
            -- Accumulator runs anchor at textStartLine; an explicitly-passed string
            -- (e.g. a rich line's prefix) belongs to the line being parsed now.
            StampLine(result[#result], (fromAccumulator and textStartLine) or currentLine)
        end
        if fromAccumulator then
            textStartLine = nil
        end
    end

    local parsingRollableTable = false

    local skipLines = 0

    for i, line in ipairs(lines) do
        currentLine = i
        local currentIndent = ""
        local skipping = false
        local str = line

        if skipLines <= 0 then
            local conditional = regex.MatchGroups(str, "^ *\\?\\?\\?(?<condition>.*)$")
            if conditional ~= nil and trim(conditional.condition) == "" then
                skipLines = 1
            elseif conditional ~= nil then
                local query = trim(conditional.condition)
                local result = dmhub.Execute(query)
                if result == nil then
                    result = false
                end
                local queries = extraOutput.queries or {}
                extraOutput.queries = queries
                queries[query] = result
                if tonumber(result) == 0 or result == "" or result == false then
                    local ndeep = 1

                    local nskip = 1

                    for j=i+1,#lines do
                        local line = lines[j]
                        local s = line
                        local m = regex.MatchGroups(s, "^ *\\?\\?\\?(?<condition>.*)$")
                        if m ~= nil then
                            if trim(m.condition) == "" then
                                ndeep = ndeep - 1
                            else
                                ndeep = ndeep + 1
                            end
                        end
                        nskip = nskip + 1
                        if ndeep == 0 then
                            break
                        end
                    end

                    skipLines = nskip
                else
                    skipLines = 1
                end
            end
        end



        if skipLines > 0 then
            skipLines = skipLines - 1
            str = ""
            skipping = true
        end

        while #collapseNodes > 0 do
            local indent = string.rep(" ", collapseNodes[#collapseNodes])
            if string.starts_with(str, indent) then
                str = str:sub(#indent + 1)
                currentIndent = indent
                break
            else
                EmitText()

                result[#result + 1] = {
                    type = "end_collapse_node",
                    player = isPlayer,
                    text = "",
                }

                collapseNodes[#collapseNodes] = nil
            end
        end

        local blockquoteMatch = regex.MatchGroups(str, "^> *(?<text>.*)$")
        if blockquoteMatch ~= nil then
            EmitText()
            local additionalLines = 0
            for j=i+1,#lines do
                if regex.MatchGroups(lines[j], "^> *(?<text>.*)$") ~= nil then
                    additionalLines = additionalLines + 1
                else
                    break
                end
            end

            local blockLines = {}
            for j=0,additionalLines do
                local match = regex.MatchGroups(lines[i + j], "^> *(?<text>.*)$")
                if match ~= nil then
                    blockLines[#blockLines + 1] = match.text
                else
                    break
                end
            end

            result[#result+1] = {
                type = "blockquote",
                text = table.concat(blockLines, "\n"),
                player = isPlayer,
            }
            StampLine(result[#result], i, i + additionalLines)

            skipping = true
            skipLines = additionalLines
            str = ""
        end

        local styleBlockMatch = regex.MatchGroups(str, "^::: *(?<class>[a-zA-Z0-9_-]+) *$")
        if styleBlockMatch ~= nil then
            EmitText()
            skipping = true
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
            StampLine(result[#result], i, i + consumed)
            skipLines = consumed
            str = ""
        end

        local rollableTableHeaderMatch = regex.MatchGroups(str, "^\\|(?<name>[^:]+): *(?<dice>[0-9]+d[0-9]+) *$")
        if rollableTableHeaderMatch ~= nil and lines[i + 1] ~= nil and string.starts_with(lines[i + 1], "|") then
            EmitText()

            result[#result + 1] = {
                type = "rollable_table",
                name = rollableTableHeaderMatch.name,
                dice = rollableTableHeaderMatch.dice,
                player = isPlayer,
            }
            StampLine(result[#result], i)

            str = ""
            parsingRollableTable = true
        end

        local powerRollMatch = (not parsingRollableTable) and
        regex.MatchGroups(str, "^\\|(?<name>[^|]+): (?<attr>[^|]+)$")
        if powerRollMatch and lines[i+1] then
            local tiers = {}
            local hasMatch = true
            local nextLine = string.lower(trim(lines[i+1]))
            for j = 1, 3 do
                local match = lines[i + j] and
                regex.MatchGroups(lines[i + j], "^" .. currentIndent .. "\\|(?<text>[^|]*)$")
                if match == nil then
                    hasMatch = false
                    break
                end

                tiers[#tiers + 1] = match.text
            end

            if hasMatch then
                EmitText()

                result[#result + 1] = {
                    type = "power_roll",
                    name = powerRollMatch.name,
                    attr = powerRollMatch.attr,
                    tiers = tiers,
                    player = isPlayer,
                }
                StampLine(result[#result], i, i + 3)
                skipLines = 3
                str = ""
            elseif g_hardwiredPowerTables[nextLine] then
                EmitText()
                skipLines = 1
                result[#result+1] = {
                    type = "power_roll",
                    name = powerRollMatch.name,
                    attr = powerRollMatch.attr,
                    tiers = g_hardwiredPowerTables[nextLine],
                    preset = nextLine,
                    lines = options.linesContext or lines,
                    lineIndex = options.lineIndexContext or i,
                    player = isPlayer,
                }
                StampLine(result[#result], i, i + 1)
                str = ""
            end
        end

        local tableMatch = regex.MatchGroups(str, "^\\|(?<row>.*)(?<suffix>\\| *)$")

        --when parsing a rollable table we can be a little more generous with the match.
        if rollableTableHeaderMatch == nil and tableMatch == nil and parsingRollableTable then
            tableMatch = regex.MatchGroups(str, "^\\|(?<row>.*)$")
            if tableMatch == nil then
                parsingRollableTable = false
            end
        end

        if tableMatch ~= nil then
            EmitText()

            result[#result + 1] = {
                type = "row",
                player = isPlayer,
            }
            StampLine(result[#result], i)

            local linePrefix = "|"

            local cells = string.split_with_square_brackets(tableMatch.row, "|")
            for j, cell in ipairs(cells) do
                result[#result + 1] = {
                    type = "cell",
                    player = isPlayer,
                }
                BreakdownRichTags(cell, result, {
                    player = options.player,
                    linePrefix = linePrefix,
                    linesContext = lines,
                    lineIndexContext = i,
                    stylingInfo = stylingInfo,
                }, extraOutput)

                linePrefix = linePrefix .. cell .. "|"
            end

            result[#result + 1] = {
                type = "end_row",
                player = isPlayer,
            }

            str = ""
        end

        if tableMatch == nil and i ~= 1 and not skipping then
            text = text .. "\n"
        end

        if #lines > 1 and regex.MatchGroups(str, "^(---+|___+)$") ~= nil then
            EmitText()
            result[#result + 1] = {
                type = "divider",
                player = isPlayer,
            }
            StampLine(result[#result], i)
            str = ""
        end

        local collapseNodeMatch = regex.MatchGroups(str, "^\\+ (?<title>['\"a-zA-Z0-9-_ ]+)$")
        if collapseNodeMatch ~= nil and lines[i + 1] ~= nil then
            local leading = string.match(lines[i + 1], "^(%s*)")
            if #leading > 0 then
                EmitText()
                result[#result + 1] = {
                    type = "collapse_node",
                    title = collapseNodeMatch.title,
                    text = str,
                    player = isPlayer,
                }
                StampLine(result[#result], i)
                collapseNodes[#collapseNodes + 1] = #leading
                str = ""
            end
        end

        local justification = nil

        while str ~= "" do
            local match = regex.MatchGroups(str,
                "^(?<prefix>.*?)((?<spoiler>\\{)|(?<justification>:(<>|><|<|>))|(?<embed>\\[:[^\\[\\]]+\\])|(?<tag>\\[[ xX]\\] *(?<checkname>[a-zA-Z0-9 ]*))|\\[\\[(?<tag>[^\\]]*)\\]\\])(?<suffix>.*)$")
            if match == nil then
                if textStartLine == nil and str ~= "" then textStartLine = currentLine end
                text = text .. str
                if str ~= line:sub(#currentIndent + 1) and text ~= "" then
                    --we have emitted rich content this line, so emit this string now.
                    EmitText(nil, justification)
                end

                break
            end

            EmitText(nil, justification)

            if match.prefix ~= "" then
                EmitText(match.prefix, justification)
            end

            if match.spoiler ~= nil then

                -- {.name ...} is an inline class marker, not a spoiler: skip the
                -- spoiler UI so the render-time ApplyInlineClasses pass resolves it.
                local isInlineClass = string.match(match.suffix, "^%.[%w_%-]+ ") ~= nil

                if not isPlayer and not isInlineClass then

                    local linepos = (#line - #str) + #match.prefix

                    local suffix = match.suffix
                    local firstChar = suffix:sub(1,1)
                    local spoilerText = "Reveal to Players"
                    if firstChar == "!" then
                        spoilerText = "Hide from Players"
                    end

                    local spoilerInfo = extraOutput.spoilers or {}
                    extraOutput.spoilers = spoilerInfo

                    local guid = dmhub.GenerateGuid()

                    spoilerInfo[guid] = {
                        lines = options.linesContext or lines,
                        lineIndex = options.lineIndexContext or i,
                        linepos = linepos,
                    }

                    text = text .. ThemeEngine.ResolveTokens(string.format("<color=@accent><size=70%%><link=spoiler:%s>%s</link></size></color>", guid, spoilerText))
                end

                text = text .. "{"
            elseif match.justification ~= nil then
                result[#result + 1] = {
                    type = "justification",
                    text = match.justification,
                    player = isPlayer,
                }
                StampLine(result[#result], i)

                if match.justification == ":<" then
                    justification = "left"
                elseif match.justification == ":>" then
                    justification = "right"
                else
                    justification = "center"
                end
            elseif match.embed ~= nil then
                result[#result + 1] = {
                    type = "embed",
                    text = match.embed,
                    justification = justification,
                    player = isPlayer,
                }
                StampLine(result[#result], i)
            else
                local linepos = (#line - #str) + #match.prefix
                local len = #line - (#match.prefix + #match.suffix)

                if options.linePrefix then
                    linepos = linepos + #options.linePrefix
                end

                local guid = dmhub.GenerateGuid()
                result[#result + 1] = {
                    guid = guid,
                    type = "tag",
                    text = match.tag,
                    justification = justification,

                    stylingInfo = DeepCopy(stylingInfo),

                    player = isPlayer,

                    --the lines this comes from.
                    lines = options.linesContext or lines,
                    lineIndex = options.lineIndexContext or i,
                    linepos = linepos,
                    length = len,
                }
                StampLine(result[#result], i)
            end

            str = match.suffix
        end

        if justification ~= nil then
            --EmitText(nil, justification)
        end
    end

    EmitText()

    while #collapseNodes > 0 do
        result[#result + 1] = {
            type = "end_collapse_node",
            text = "",
            player = isPlayer,
        }

        collapseNodes[#collapseNodes] = nil
    end

    return result
end

--Returns the annotations that are actually referenced by a rich tag in the document
--content, as an ordered array (in content order) of { key = annotationKey,
--annotation = annotation } entries.
--
--This mirrors how DisplayPanel resolves content tags to annotations (see the
--token.type == "tag" branch in DisplayPanel), including the "-N" de-duplication of
--repeated identical tags. Annotation entries that no longer have a corresponding
--tag in the text (stale/orphaned annotations) are therefore excluded -- they are
--invisible in the rendered journal, and callers generally want the same view.
--
--Note: pattern-based rich tags (RichTag.pattern) are not specially handled here;
--they do not carry stored annotations, so they never contribute to the result.
function MarkdownDocument:GetReferencedAnnotations(options)
    local result = {}
    local annotations = self:try_get("annotations")
    if annotations == nil then
        return result
    end

    local tokens = BreakdownRichTags(self:GetTextContent(), nil, options or {})
    local tagsSeen = {}
    for _, token in ipairs(tokens) do
        if token.type == "tag" then
            local fullname = token.text
            local text = token.text:match("^(.-):") or token.text
            local richTagInfo = MarkdownDocument.RichTagRegistry[string.lower(text)]
            if richTagInfo ~= nil then
                local candidate = fullname
                local index = 1
                while tagsSeen[candidate] do
                    candidate = fullname .. '-' .. index
                    index = index + 1
                end
                tagsSeen[candidate] = true

                local annotation = annotations[candidate]
                if annotation ~= nil then
                    result[#result + 1] = { key = candidate, annotation = annotation }
                end
            end
        end
    end

    return result
end

function MarkdownDocument:PatchToken(token, str)
    local lines = table.shallow_copy(token.lines)
    local line = token.lines[token.lineIndex]
    lines[token.lineIndex] = line:sub(1, token.linepos) .. str .. line:sub(token.linepos + token.length + 1)
    self:SetTextContent(table.concat(lines, "\n"))
end

function MarkdownDocument:GetRollableTableFromTokens(tableid, tokens, startPos)
    --look for the first "row" token within three spaces, otherwise we give up.
    local found = false
    for i=1,3 do
        if tokens[startPos+i] ~= nil and tokens[startPos+i].type == "row" then
            startPos = startPos + i
            found = true
            break
        end
    end

    if not found then
        return false
    end

    local t = RollTable.CreateNew()

    local currentRow = {}
    local processingRow = false

    local TryAddRow = function()
        if #currentRow > 0 then

            local value = VariantCollection.Create()
            for j,cell in ipairs(currentRow) do
                value:Add(Variant.CreateText(cell))
            end
            local row = RollTableRow.new{
                id = self.id .. "-" .. tableid .. "-" .. string.format("%d", #t.rows),
                value = value,
            }

            t.rows[#t.rows+1] = row

            currentRow = {}
        end
    end

    for i=startPos,#tokens do
        local token = tokens[i]
        if token.type == "row" then
            TryAddRow()
            processingRow = true
        elseif token.type == "end_row" then
            TryAddRow()
            processingRow = false
        elseif token.type == "text" then
            if not processingRow then
                break
            end

            currentRow[#currentRow+1] = token.text
        end
    end

    TryAddRow()

    return t
end

function MarkdownDocument:GetRollableTable(tableid)
    local rollableTablesByName = {}
    local tokens = BreakdownRichTags(self:GetTextContent(), nil, {})
    for i,token in ipairs(tokens) do
        if token.type == "rollable_table" then
            local tableName = token.name
            local count = rollableTablesByName[tableName] or 0
            rollableTablesByName[tableName] = count + 1
            if count > 0 then
                tableName = string.format("%s|%d", tableName, count)
            end

            if tableName == tableid then
                local result = self:GetRollableTableFromTokens(tableid, tokens, i)
                if result ~= nil then
                    result.text = true
                    result.name = token.name

                    for _,rollType in ipairs(RollTable.RollTypes) do
                        if rollType.id == token.dice or rollType.text == token.dice then
                            result.rollType = rollType.id
                            break
                        end
                    end

                    if result.rollType == "auto" then
                        result.customRoll = token.dice
                    end
                end
                return result
            end
        end
    end

    return nil
end

local function TierRoll(n)
    return gui.Panel {
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "horizontal",
        gui.Label {
            width = CustomDocument.ScaleFontSize(60),
            height = CustomDocument.ScaleFontSize(30),
            textAlignment = "center",
            fontFace = "DrawSteelGlyphs",
            text = cond(n == 1, '!', cond(n == 2, '@', '#')),
            fontSize = CustomDocument.ScaleFontSize(36),
            valign = "top",
        },

        gui.Label {
            id = string.format("tier_%d", n),
            debugLogging = (n == 1),
            width = "100%-60",
            height = "auto",
            textAlignment = "topleft",
            fontSize = CustomDocument.ScaleFontSize(16),
            vmargin = 0,
            vpad = 0,
            markdown = true,
            markdownStyle = g_markdownStyle,
            refreshPowerRoll = function(element, info)
                element.text = info.tiers[n] or ""
            end,
        },
    }
end

local function PowerRollDisplay(doc)
    local resultPanel

    local m_token = nil
    local m_info = nil

    resultPanel = gui.Panel {
        width = "auto",
        height = "auto",
        flow = "vertical",
        halign = "left",
        valign = "top",

        gui.Panel{
            height = "auto",
            width = "auto",
            flow = "horizontal",
            halign = "left",
            gui.Label {
                classes = { "link", "bold" },
                halign = "left",
                refreshPowerRoll = function(element, info)
                    m_info = info
                    element.text = string.format("%s: %s", info.name, info.attr)
                end,
                press = function(element)
                    local attr = string.lower(m_info.attr)
                    local characteristics = {}
                    for attrid, attrInfo in pairs(creature.attributesInfo) do
                        if string.find(attr, string.lower(attrInfo.description)) then
                            characteristics[attrid] = true
                        end
                    end

                    local skills = {}
                    local skillsList = Skill.skillsDropdownOptions
                    for _, skillInfo in ipairs(skillsList) do
                        if string.find(attr, string.lower(skillInfo.text)) ~= nil then
                            skills[#skills + 1] = skillInfo.id
                        end
                    end

                    if not doc:IsPlayerView(element) then
                        LaunchablePanel.LaunchPanelByName("Request Rolls", {
                            title = string.format("%s: %s", m_info.name, m_info.attr),
                            powerRollTable = PowerRollTable.Create {
                                tiers = m_info.tiers,
                            },
                            characteristics = characteristics,
                            skills = skills,
                        })
                    else
                        local token = dmhub.currentToken
                        if token ~= nil then
                            token.properties:RollCustomPowerTableTest(string.format("%s: %s", m_info.name, m_info.attr),
                                characteristics, skills, m_info.tiers)
                        end
                    end
                end,
                fontSize = CustomDocument.ScaleFontSize(18),
            },

            gui.Label{
                classes = {"fg", "link"},
                lmargin = 8,
                fontSize = 16,
                width = 120,
                height = 18,
                valign = "center",
                text = "",
                refreshPowerRoll = function(element, token)
                    if token.preset == nil then
                        element:SetClass("collapsed", true)
                        return
                    end

                    element.data.token = token
                    element:SetClass("collapsed", false)
                    element.text = string.sub(token.preset, 2)
                end,

                press = function(element)
                    local token = element.data.token
                    if token == nil then
                        return
                    end

                    local nextIndex = 1
                    for i=1,#g_hardwiredPowerTableList do
                        local info = g_hardwiredPowerTableList[i]
                        if info.preset == token.preset then
                            nextIndex = i+1
                            if nextIndex > #g_hardwiredPowerTableList then
                                nextIndex = 1
                            end
                            break
                        end
                    end

                    local lines = table.shallow_copy(token.lines)
                    lines[token.lineIndex+1] = g_hardwiredPowerTableList[nextIndex].preset
                    doc:SetTextContent(table.concat(lines, "\n"))
                    doc:Upload()
                end,
            },
        },

        TierRoll(1),
        TierRoll(2),
        TierRoll(3),
    }

    return resultPanel
end

local function CreateTreeNodePanel()
    local resultPanel

    local bodyPanel = gui.Panel {
        flow = "vertical",
        width = "100%-8",
        height = "auto",
        halign = "right",
        valign = "top",
        refreshTreeChildren = function(element, children)
            element.children = children
            element:HaltEventPropagation()
        end,
    }

    local headerPanel = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",
        gui.ExpandoArrow {
            classes = { "expanded" },
            press = function(element)
                element:SetClass("expanded", not element:HasClass("expanded"))
                bodyPanel:SetClass("collapsed", not element:HasClass("expanded"))
            end,
        },
        gui.Label {
            classes = { "fg", "bold" },
            refreshTreeNode = function(element, title)
                element.text = title
                element:HaltEventPropagation()
            end,
            fontSize = CustomDocument.ScaleFontSize(16),
            width = "auto",
            height = "auto",
        },
    }

    resultPanel = gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "top",
        headerPanel,
        bodyPanel,
    }

    return resultPanel
end

--given text, will run it through our normal formatter.
function MarkdownDocument.FormatRichText(text, options)
    local result = ""
    local tokens = BreakdownRichTags(text, nil, options)
    for _, token in ipairs(tokens) do
        if token.type == "text" then
            result = result .. token.text
        end
    end

    return result
end

function MarkdownDocument.DisplayPanel(self, args)
    args = args or {}
    local embedDepth = args.embedDepth or 0
    args.embedDepth = nil

    -- Host page color handed down to an embedded document. When this embed has
    -- no page background of its own, it falls back to this so it blends into
    -- the host page. nil for top-level documents and for embeds whose host has
    -- no page color. Captured as a closure local so it survives re-renders,
    -- exactly like embedDepth above.
    local m_hostPageColor = args.hostPageColor
    args.hostPageColor = nil

    --TODO: respect this parameter.
    local m_noninteractive = args.noninteractive or false
    args.noninteractive = nil

    local resultPanel

    local m_rollableTableRowLabels = {}
    local m_textPanels = {}
    local m_richPanels = {}
    local m_richFrames = {}
    local m_richRows = {}
    local m_rollableTables = {}
    local m_tables = {}
    local m_tableRows = {}
    local m_dividers = {}
    local m_headingRules = {}
    local m_powerTables = {}
    local m_embeds = {}
    local m_treeNodes = {}
    local m_blockquotes = {}
    local m_styleblocks = {}
    local m_tokenExtraInfo = {}

    local params = {
        styles = ThemeEngine.GetStyles(),
        width = "100%",
        height = "100%",
        flow = "vertical",
        halign = "center",
        valign = "center",
        hpad = 6,
        vscroll = true,
        think = function(element)
            if element.data.queries == nil then
                return
            end

            for k,v in pairs(element.data.queries) do
                local result = dmhub.Execute(k)
                if result == nil then
                    result = false
                end

                if result ~= v then
                    element:FireEvent("refreshDocument")
                    break
                end
            end
        end,
        savedoc = function(element)
            element:FireEvent("refreshDocument")
        end,
        refreshDocument = function(element, doc)
            if doc ~= nil then
                self = doc
            end

            local children = {}
            local childrenStack = {} --stack used by collapse nodes.
            local treeNodeStack = {}
            local newRollableTables = {}
            local newTables = {}
            local newTableRows = {}
            local newRollableTableRowLabels = {}
            local newTextPanels = {}
            local newRichPanels = {}
            local newRichFrames = {}
            local newRichRows = {}
            local newPowerTables = {}
            local newEmbeds = {}
            local newTreeNodes = {}
            local newBlockquotes = {}
            local newStyleblocks = {}
            local currentRichRow = nil

            local rollableTablesByName = {}

            local newDividers = {}
            local newHeadingRules = {}

            local currentRollableTable = nil --the panel controlling the current rollable table.
            local currentTable = nil
            local currentTableRow = nil

            local tagsSeen = {}

            m_tokenExtraInfo = {}
            -- trackPositions stamps each token's source line (purely additive; rendering
            -- ignores srcLine) so the rendered blocks below can be tagged for the preview's
            -- content-aware scroll sync (SyncPreviewScroll).
            local tokens = BreakdownRichTags(self:GetTextContent(), nil, { player = self:IsPlayerView(element), trackPositions = true }, m_tokenExtraInfo)

            if m_tokenExtraInfo.queries ~= nil then
                element.thinkTime = 0.2
                element.data.queries = m_tokenExtraInfo.queries
            else
                element.thinkTime = nil
                element.data.queries = nil
            end

            -- Plan 2: resolve this document's skin once per render. Memoized in
            -- the resolver, so re-calling per token would also be cheap, but we
            -- hoist it for clarity and to thread into text/divider/quote.
            local resolvedStylesheet = self:GetResolvedStylesheet()
            local resolvedSkin = resolvedStylesheet.base
            local resolvedClasses = resolvedStylesheet.classes
            -- Compute once per render: which heading levels (1..5) carry a rule.
            -- nil means no ruled headings -> every text run uses the fast path.
            local ruledLevels = HeadingRuleLevels(resolvedSkin)
            local usesAlign = SkinUsesAlign(resolvedSkin)
            -- Page background: paint the content container from the resolved skin.
            -- Re-runs every render (including live stylesheet edits via the monitor).
            -- Unset clears it so a reused panel keeps no stale background and the
            -- default skin stays a visual no-op.
            local pageColor = SkinColor((resolvedSkin.page or {}).bgcolor)
            -- Embeds default to the host page color when they set none of their
            -- own, so embedded content blends into the page. An embed's own page
            -- color (non-nil here) always wins. m_hostPageColor is only set for
            -- embeds, so top-level documents are unaffected. pageColor is now the
            -- effective color, which propagates to any nested embeds below.
            if pageColor == nil and m_hostPageColor ~= nil then
                pageColor = m_hostPageColor
            end
            if pageColor then
                element.bgimage = "panels/square.png"
                element.bgcolor = pageColor
            else
                element.bgimage = nil
                element.bgcolor = nil
            end
            -- Page margin: inset content from the page edges. borderBox keeps the
            -- pad inside the declared width (no overflow). Unset/0 -> cleared, so
            -- the default skin stays edge-to-edge.
            local pageMargin = (resolvedSkin.page or {}).margin
            if type(pageMargin) == "number" and pageMargin > 0 then
                element.pad = pageMargin
                element.borderBox = true
            else
                element.pad = nil
                element.borderBox = nil
            end
            -- Content-aware preview scroll: tag each top-level child with the source line
            -- of the token that produced it. Capture the children array + length at the
            -- start of each iteration and stamp whatever got appended at the end. This
            -- survives the collapse-node array swap (the captured ref still points at the
            -- table the appends went to) and rich-row batching (a row is appended once, in
            -- its first tag's iteration, so it is stamped with that line). lastStampLine
            -- carries the last known line forward for the rare token with none.
            local lastStampLine = 1
            for i, token in ipairs(tokens) do
                local stampChildren = children
                local stampFrom = #children + 1
                local stampLine = token.srcLine or lastStampLine
                if token.srcLine ~= nil then lastStampLine = token.srcLine end
                if token.type == "justification" then
                    --pass, nothing needed here.
                elseif token.type == "collapse_node" then
                    local panel = m_treeNodes[#newTreeNodes + 1] or CreateTreeNodePanel()
                    ApplyBlockFrame(panel, ((resolvedSkin.blocks or {}).collapse or {}).box)
                    if m_treeNodes[#newTreeNodes + 1] ~= nil then
                        panel:Unparent()
                    end
                    children[#children + 1] = panel
                    newTreeNodes[#newTreeNodes + 1] = panel
                    childrenStack[#childrenStack + 1] = children
                    children = {}
                    treeNodeStack[#treeNodeStack + 1] = panel

                    panel:FireEventTree("refreshTreeNode", token.title or "")
                elseif token.type == "end_collapse_node" then
                    local panel = treeNodeStack[#treeNodeStack]
                    treeNodeStack[#treeNodeStack] = nil
                    panel:FireEventTree("refreshTreeChildren", children)
                    ApplyBlockInner(panel, ((resolvedSkin.blocks or {}).collapse or {}).inner, "collapse")
                    children = childrenStack[#childrenStack]
                    childrenStack[#childrenStack] = nil
                elseif token.type == "embed" then
                    local embed = trim(token.text:sub(3, -2))
                    local original = embed
                    local count = 0

                    while newEmbeds[embed] ~= nil and count < 8 do
                        count = count + 1
                        embed = string.format("%s|%d", original, count)
                    end

                    if m_embeds[embed] then
                        newEmbeds[embed] = m_embeds[embed]
                        newEmbeds[embed]:Unparent()
                    else
                        local doc = CustomDocument.ResolveLink(original)
                        if doc ~= nil then
                            newEmbeds[embed] = CustomDocument.CreateEmbeddablePanel(doc, { embedDepth = embedDepth, hostPageColor = pageColor }) or
                            false
                        else
                            newEmbeds[embed] = false
                        end
                    end

                    if newEmbeds[embed] ~= false then
                        ApplyBlockFrame(newEmbeds[embed], (resolvedSkin.embed or {}).box)
                        children[#children + 1] = newEmbeds[embed]
                    end
                elseif token.type == "power_roll" then
                    currentRollableTable = nil
                    currentTable = nil
                    currentTableRow = nil
                    currentRichRow = nil

                    local panel = m_powerTables[#newPowerTables + 1] or PowerRollDisplay(self)
                    ApplyBlockFrame(panel, ((resolvedSkin.blocks or {}).powerRoll or {}).box)
                    panel:FireEventTree("refreshPowerRoll", token)
                    ApplyBlockInner(panel, ((resolvedSkin.blocks or {}).powerRoll or {}).inner, "powerRoll")
                    newPowerTables[#newPowerTables + 1] = panel
                    children[#children + 1] = panel
                elseif token.type == "divider" then
                    currentRollableTable = nil
                    currentTable = nil
                    currentTableRow = nil
                    currentRichRow = nil

                    local divider = m_dividers[#newDividers + 1] or gui.Divider {
                        tmargin = 0,
                        bmargin = 0,
                        valign = "top",
                        width = "100%",
                    }
                    -- Plan 2: apply rule skin (only spike-confirmed props).
                    -- Spike result: bgcolor and tmargin/bmargin error on selfStyle set;
                    -- height works. Only thickness is applied here.
                    local rule = resolvedSkin.rule or {}
                    if rule.thickness then divider.selfStyle.height = rule.thickness end

                    newDividers[#newDividers + 1] = divider
                    children[#children + 1] = divider
                elseif token.type == "rollable_table" then
                    local tableName = token.name
                    local count = rollableTablesByName[tableName] or 0
                    rollableTablesByName[tableName] = count + 1
                    if count > 0 then
                        tableName = string.format("%s|%d", tableName, count)
                    end

                    local panel = m_rollableTables[tableName] or gui.Label {
                        classes = { "bold", "link" },
                        data = {
                            rolls = {},
                            diceToRollId = {},

                        },
                        valign = "top",
                        fontSize = CustomDocument.ScaleFontSize(18),
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        text = string.format("%s (Roll %s)", token.name, token.dice),
                        textAlignment = "left",

                        diceface = function(element, guid, num, timeRemaining)
                            local rollid = element.data.diceToRollId[guid]
                            if rollid ~= nil and element.data.rolls[rollid] ~= nil and element.data.rolls[rollid].totals[guid] ~= nil then
                                element.data.rolls[rollid].totals[guid] = num
                                local total = 0
                                for _,v in pairs(element.data.rolls[rollid].totals) do
                                    total = total + v
                                end

                                if element.data.rowList ~= nil then
                                    for i,row in ipairs(element.data.rowList) do
                                        if row.data.range ~= nil and total >= row.data.range.min and total <= row.data.range.max then
                                            row:SetClassTree("highlight", true)
                                        else
                                            row:SetClassTree("highlight", false)
                                        end
                                    end
                                end

                            end
                        end,

                        create = function(element)
                            element.data.eventHandler = dmhub.RegisterEventHandler("DiceRoll", function(info)
                                if info.properties ~= nil and rawget(info.properties, "tableRef") then
                                    local rollid = dmhub.GenerateGuid()
                                    element.data.rolls[rollid] = {
                                        info = info,
                                        totals = {},
                                        table = info.properties.tableRef:GetTable(),
                                        bonus = info.total - info.naturalRoll,
                                        total = info.total,
                                    }
                                    local ref = rawget(info.properties, "tableRef")
                                    if ref.docid == self.id and ref.tableid == tableName then
                                        local rolls = info.rolls
                                        for i,roll in ipairs(rolls) do
                                            local events = chat.DiceEvents(roll.guid)
                                            events:Listen(element)
                                            element.data.diceToRollId[roll.guid] = rollid
                                            element.data.rolls[rollid].totals[roll.guid] = 0

                                            if roll.partnerguid ~= nil then
                                                local partnerEvents = chat.DiceEvents(roll.partnerguid)
                                                partnerEvents:Listen(element)
                                                element.data.diceToRollId[roll.partnerguid] = rollid
                                                element.data.rolls[rollid].totals[roll.partnerguid] = 0
                                            end
                                        end
                                    end
                                end
                            end)
                        end,

                        destroy = function(element)
                            if element.data.eventHandler ~= nil then
                                dmhub.DeregisterEventHandler(element.data.eventHandler)
                                element.data.eventHandler = nil
                            end
                        end,

                        press = function(element)

                            local ref = RollTableReference.CreateDocumentReference(self.id, tableName)
                            if not self:IsPlayerView(element) then
                                LaunchablePanel.LaunchPanelByName("Request Rolls", {
                                    title = token.name,
                                    checkType = "Table",
                                    check = RollCheck.new{
                                        type = "table",
                                        id = "custom",
                                        group = "custom",
                                        text = token.name,
                                        tableRef = ref,
                                        rollProperties = RollOnTableProperties.new{
                                            tableRef = ref,
                                        },
                                    }
                                    --characteristics = characteristics,
                                    --skills = skills,
                                })
                            else
                                local charToken = dmhub.selectedOrPrimaryTokens[1]
                                local rollArgs = {
                                    title = "Roll on Table",
                                    description = token.name,
                                    roll = token.dice,
                                    tableRef = ref,
                                    type = "table",
                                    creature = charToken and charToken.properties or nil,
                                    rollProperties = RollOnTableProperties.new{
                                        tableRef = ref,
                                    },
                                }

                                GameHud.instance.rollDialog.data.ShowDialog(rollArgs)
                            end
                        end,
                    }

                    panel.data.tableData = self:GetRollableTable(tableName)
                    panel.data.rollInfo = panel.data.tableData:CalculateRollInfo()
                    panel.data.table = nil
                    currentRollableTable = panel

                    ApplyBlockFrame(panel, ((resolvedSkin.blocks or {}).rollableTable or {}).box)

                    if m_rollableTables[tableName] ~= nil then
                        panel:Unparent()
                    end

                    newRollableTables[tableName] = panel

                    children[#children + 1] = panel
                elseif token.type == "row" then
                    currentRichRow = nil
                    if currentTable == nil then
                        -- The frame (border/bg/pad) goes on a wrapper panel, NOT the
                        -- gui.Table itself: a gui.Table lays out its cells from its own
                        -- origin and ignores the panel's pad, so a frame applied directly
                        -- leaves the upper-left cells sitting outside the box. The wrapper
                        -- is a normal panel whose pad insets the Table correctly. m_tables
                        -- caches the wrapper; the Table persists inside it as
                        -- wrapper.data.tablePanel.
                        -- Pick the block (rollable tables share the row path) and its
                        -- inner config; row colors are applied via the Table's own
                        -- `styles`, which can only be set at construction -- so rebuild
                        -- the Table when the inner config changes (the journalStyles
                        -- monitor already re-renders the document on any style edit).
                        local blockKey = (currentRollableTable ~= nil) and "rollableTable" or "table"
                        local blockSkin = (resolvedSkin.blocks or {})[blockKey] or {}
                        local innerSig = TableInnerSig(blockSkin.inner)
                        local function NewInnerTable()
                            return gui.Table {
                                halign = "left",
                                valign = "top",
                                width = "auto",
                                height = "auto",
                                flow = "vertical",
                                styles = TableInnerStyles(blockSkin.inner),
                            }
                        end
                        local tableWrapper = m_tables[#newTables + 1]
                        if tableWrapper == nil then
                            local tbl = NewInnerTable()
                            tableWrapper = gui.Panel {
                                flow = "vertical",
                                width = "auto",
                                height = "auto",
                                halign = "left",
                                valign = "top",
                                lmargin = 6,
                                tbl,
                            }
                            tableWrapper.data.tablePanel = tbl
                            tableWrapper.data.innerSig = innerSig
                        elseif tableWrapper.data.innerSig ~= innerSig then
                            -- inner styling changed: rebuild the Table with new styles.
                            local tbl = NewInnerTable()
                            tableWrapper.data.tablePanel = tbl
                            tableWrapper.children = { tbl }
                            tableWrapper.data.innerSig = innerSig
                        end
                        currentTable = tableWrapper.data.tablePanel

                        currentTable.data.children = {}

                        ApplyBlockFrame(tableWrapper, blockSkin.box)

                        if currentRollableTable ~= nil then
                            currentRollableTable.data.table = currentTable
                            currentRollableTable.data.row = 1
                        end

                        newTables[#newTables + 1] = tableWrapper
                        currentTableRow = nil
                        children[#children + 1] = tableWrapper
                    end

                    currentTableRow = m_tableRows[#newTableRows + 1] or gui.TableRow {
                        width = "auto",
                        height = "auto",
                    }

                    if m_tableRows[#newTableRows + 1] ~= nil then
                        currentTableRow:Unparent()
                    end

                    currentTableRow.data.children = {}

                    -- First row of each table is the markdown header row (followed
                    -- by `|---|`). Toggle the headerRow class so the cascade's
                    -- {row, headerRow} / {label, parent:headerRow} rules apply.
                    -- SetClass with a boolean correctly clears the class on rows
                    -- that were previously a header row but got repositioned.
                    local isHeaderRow = #currentTable.data.children == 0
                    currentTableRow:SetClass("headerRow", isHeaderRow)

                    newTableRows[#newTableRows + 1] = currentTableRow

                    currentTable.data.children[#currentTable.data.children + 1] = currentTableRow

                    if currentRollableTable ~= nil then
                        local rollInfo = currentRollableTable.data.rollInfo
                        local range = rollInfo.rollRanges[currentRollableTable.data.row]
                        if range ~= nil then
                            newRollableTableRowLabels[#newRollableTableRowLabels + 1] = m_rollableTableRowLabels[#newRollableTableRowLabels + 1] or gui.Label{
                                classes = { "bold" },
                                fontSize = 16,
                                width = 70,
                                halign = "left",
                                height = "auto",
                            }

                            local label = newRollableTableRowLabels[#newRollableTableRowLabels]
                            label:Unparent()
                            label.text = RollTable.FormatRange(range) .. "."

                            currentRollableTable.data.rowList = currentRollableTable.data.rowList or {}
                            currentRollableTable.data.rowList[currentRollableTable.data.row] = currentTableRow
                            currentTableRow.data.range = range

                            currentTableRow.data.children[#currentTableRow.data.children + 1] = label
                        end

                        currentRollableTable.data.row = currentRollableTable.data.row + 1
                    end
                elseif token.type == "end_row" then
                    currentTableRow = nil
                    currentRichRow = nil
                elseif token.type == "cell" then
                    currentRichRow = m_richRows[#newRichRows + 1] or gui.Panel {
                        flow = "horizontal",
                        height = "auto",
                        vmargin = 0,
                        pad = 4,
                    }
                    if m_richRows[#newRichRows + 1] ~= nil then
                        currentRichRow:Unparent()
                    end
                    currentRichRow.data.children = {}
                    currentRichRow.selfStyle.width = "auto"
                    currentRichRow.selfStyle.valign = "center"

                    --scan for the number of cells in this row.
                    local beginRowIndex = i
                    for j=i,1,-1 do
                        if tokens[j].type == "row" then
                            beginRowIndex = j
                            break
                        end
                    end

                    local cellCount = 0
                    for j=beginRowIndex,#tokens do
                        if tokens[j].type == "end_row" then
                            break
                        elseif tokens[j].type == "cell" then
                            cellCount = cellCount + 1
                        end
                    end

                    local cellWidth = math.floor(100 / cellCount)
                    local tableHeaderSpacing = 0
                    if currentRollableTable ~= nil then
                        tableHeaderSpacing = 80/cellCount
                    end

                    --currentRichRow.selfStyle.width = string.format("%d%%-%d", round(cellWidth), round(tableHeaderSpacing))
                    currentRichRow.selfStyle.maxWidth = string.format("%d%%-%d", round(cellWidth), round(tableHeaderSpacing))

                    newRichRows[#newRichRows + 1] = currentRichRow
                    if currentTableRow ~= nil then
                        currentTableRow.data.children[#currentTableRow.data.children + 1] = currentRichRow
                    end
                elseif token.type == "text" and token.justification == nil and token.text == "\n" and currentRichRow ~= nil then
                    --this special case doesn't require inserting a text panel. Instead we just end the rich row of content.
                    currentRichRow = nil
                elseif token.type == "text" then
                    if currentTable ~= nil and currentTableRow == nil then
                        --end of table.
                        currentRollableTable = nil
                        currentRichRow = nil
                        currentTable = nil
                    end

                    local function MakeTextLabel()
                        return gui.Label {
                            classes = {"fg"},
                            width = "auto",
                            height = "auto",
                            maxWidth = "100%",
                            valign = "center",
                            vmargin = 0,
                            markdown = true,
                            markdownStyle = g_markdownStyle,
                            textAlignment = "topleft",
                            fontSize = CustomDocument.ScaleFontSize(14),
                            pad = 0,
                            links = true,
                            hoverLink = function(element, link)
                                if string.starts_with(link, "spoiler:") then
                                    return
                                end
                                CustomDocument.PreviewLink(element, link)
                            end,
                            dehoverLink = function(element, link)
                                element.tooltip = nil
                            end,
                            rightClick = function(element)
                                if element.linkHovered == nil then return end
                                local link = element.linkHovered
                                if string.starts_with(link, "spoiler:") then return end
                                local doc = CustomDocument.ResolveLink(link)
                                if doc == nil then return end

                                -- Only show context menu for navigable document types
                                local isNavigable = false
                                if type(doc) == "table" or type(doc) == "userdata" then
                                    if doc.IsDerivedFrom and doc.IsDerivedFrom("CustomDocument") and doc:try_get("id") then
                                        isNavigable = true
                                    elseif MarkdownRender.IsRenderable(doc) then
                                        isNavigable = true
                                    end
                                end
                                if not isNavigable then return end

                                element.popup = gui.ContextMenu {
                                    entries = {
                                        {
                                            text = "Open in New Tab",
                                            click = function()
                                                element.popup = nil
                                                CustomDocument.OpenContent(doc)
                                            end,
                                        },
                                    },
                                }
                            end,
                            press = function(element)
                                if element.popup then
                                    element.popup = nil
                                    return
                                end
                                if element.linkHovered ~= nil then
                                    local link = element.linkHovered
                                    if string.starts_with(link, "spoiler:") then
                                        local spoilerValue = link:sub(9)
                                        local spoilerInfo = (m_tokenExtraInfo.spoilers or {})[spoilerValue]
                                        if spoilerInfo == nil then
                                            return
                                        end

                                        local lines = table.shallow_copy(spoilerInfo.lines)
                                        local line = spoilerInfo.lines[spoilerInfo.lineIndex]
                                        for i=spoilerInfo.linepos,#line do
                                            if line:sub(i,i) == "{" then
                                                local nextChar = line:sub(i+1,i+1)
                                                if nextChar == "!" then
                                                    line = line:sub(1,i) .. line:sub(i+2)
                                                else
                                                    line = line:sub(1,i) .. "!" .. line:sub(i+1)
                                                end
                                                lines[spoilerInfo.lineIndex] = line
                                                self:SetTextContent(table.concat(lines, "\n"))
                                                self:Upload()
                                                break
                                            end
                                        end

                                        return
                                    end

                                    local doc = CustomDocument.ResolveLink(element.linkHovered)
                                    if doc ~= nil then
                                        -- Try in-place navigation for real document types only.
                                        -- Renderable content (e.g. an item/spell link) wraps into a
                                        -- transient MarkdownDocument that is never written to the
                                        -- table, so navigateToDocument (which looks up by id) can't
                                        -- resolve it -- let those fall through to OpenContent instead.
                                        local navigableDocId = nil
                                        if type(doc) == "table" or type(doc) == "userdata" then
                                            if doc.IsDerivedFrom and doc.IsDerivedFrom("CustomDocument") and doc:try_get("id") then
                                                navigableDocId = doc.id
                                            end
                                        end

                                        if navigableDocId then
                                            local dialogPanel = element:FindParentWithClass("framedPanel")
                                            if dialogPanel and dialogPanel.data and dialogPanel.data.history then
                                                dialogPanel:FireEvent("navigateToDocument", navigableDocId)
                                                return
                                            end
                                        end

                                        -- Fall back to opening in new window
                                        CustomDocument.OpenContent(doc)
                                    else
                                        local guid = dmhub.GenerateGuid()
                                        local markdownDoc = MarkdownDocument.new {
                                            id = guid,
                                            description = element.linkHovered,
                                            content = "# " .. element.linkHovered,
                                            annotations = {},
                                        }

                                        dmhub.SetAndUploadTableItem(MarkdownDocument.tableName, markdownDoc)
                                        markdownDoc:ShowDocument { edit = true }
                                    end
                                end
                            end,
                        }
                    end
                    if ruledLevels == nil or not TextHasRuledHeading(token.text, ruledLevels) then
                        -- Fast path: skin has no ruled headings, or this run
                        -- contains no ruled heading line -> single label, unchanged.
                        local textPanel = m_textPanels[#newTextPanels + 1] or MakeTextLabel()

                        textPanel.selfStyle.halign = token.justification or "left"

                        if m_textPanels[#newTextPanels + 1] ~= nil then
                            textPanel:Unparent()
                        end

                        local text = token.text
                        if string.starts_with(text, "\n") then
                            text = text:sub(2)
                        end

                        --make it so that leading or trailing spaces are non-breaking
                        if string.starts_with(text, " ") then
                            text = "<color=#00000000>.</color>" .. text:sub(2)
                        end

                        if string.ends_with(text, " ") then
                            text = text:sub(1, -2) .. "<color=#00000000>.</color>"
                        end

                        textPanel.text = ApplySkinToText(ApplyInlineClasses(text, resolvedClasses), resolvedSkin)
                        newTextPanels[#newTextPanels + 1] = textPanel

                        --find if the string only has a newline at the end or no newline,
                        --in which case it can go inline.
                        if (currentRichRow ~= nil and token.text:match("^[^\n]*\n?$") ~= nil) or (currentRichRow == nil and string.find(token.text, "\n") == nil) then
                            if currentRichRow == nil then
                                currentRichRow = m_richRows[#newRichRows + 1] or gui.Panel {
                                    flow = "horizontal",
                                    height = "auto",
                                    vmargin = 0,
                                }
                                if m_richRows[#newRichRows + 1] ~= nil then
                                    currentRichRow:Unparent()
                                end
                                currentRichRow.selfStyle.width = "100%"
                                currentRichRow.selfStyle.valign = "top"
                                currentRichRow.selfStyle.maxWidth = nil
                                currentRichRow.data.children = {}
                                newRichRows[#newRichRows + 1] = currentRichRow
                                children[#children + 1] = currentRichRow
                            end

                            if token.justification then
                                currentRichRow.selfStyle.width = "100%"
                            end

                            textPanel.selfStyle.width = "auto"
                            textPanel.selfStyle.valign = "center"
                            currentRichRow.data.children[#currentRichRow.data.children + 1] = textPanel
                        else
                            -- Only widen for stylesheet alignment when the author did not set an explicit
                            -- :>/:<> justification (which positions an auto-width label via panel halign).
                            textPanel.selfStyle.width = (usesAlign and not token.justification) and "100%" or "auto"
                            textPanel.selfStyle.valign = "top"
                            children[#children + 1] = textPanel
                        end

                        if currentRichRow ~= nil and string.find(token.text, "\n") then
                            currentRichRow = nil
                        end
                    else
                        -- Split path: ruled headings present; emit one label per
                        -- segment and a rule panel after each ruled-heading segment.
                        -- Does NOT use the rich-row inline branch (block content).
                        currentRichRow = nil
                        local text = token.text
                        if string.starts_with(text, "\n") then
                            text = text:sub(2)
                        end
                        if string.starts_with(text, " ") then
                            text = "<color=#00000000>.</color>" .. text:sub(2)
                        end
                        if string.ends_with(text, " ") then
                            text = text:sub(1, -2) .. "<color=#00000000>.</color>"
                        end
                        local segments = SplitRunAtRuledHeadings(text, ruledLevels)
                        for _, seg in ipairs(segments) do
                            local label = m_textPanels[#newTextPanels + 1] or MakeTextLabel()
                            label.selfStyle.halign = token.justification or "left"
                            if m_textPanels[#newTextPanels + 1] ~= nil then
                                label:Unparent()
                            end
                            -- Only widen for stylesheet alignment when the author did not set an explicit
                            -- :>/:<> justification (which positions an auto-width label via panel halign).
                            label.selfStyle.width = (usesAlign and not token.justification) and "100%" or "auto"
                            label.selfStyle.valign = "top"
                            label.text = ApplySkinToText(
                                ApplyInlineClasses(seg.text, resolvedClasses),
                                resolvedSkin,
                                { ruledLevels = ruledLevels })
                            newTextPanels[#newTextPanels + 1] = label
                            children[#children + 1] = label
                            if seg.ruleLevel ~= nil then
                                local h = (resolvedSkin.headings or {})[seg.ruleLevel]
                                local rulePanel = m_headingRules[#newHeadingRules + 1]
                                if rulePanel == nil then
                                    rulePanel = BuildHeadingRulePanel(nil, h)
                                else
                                    BuildHeadingRulePanel(rulePanel, h)
                                    rulePanel:Unparent()
                                end
                                newHeadingRules[#newHeadingRules + 1] = rulePanel
                                children[#children + 1] = rulePanel
                            end
                        end
                    end
                elseif token.type == "blockquote" then
                    currentRichRow = nil
                    local blockquote = m_blockquotes[#newBlockquotes + 1] or gui.Panel {
                        classes = {"blockQuote"},
                        width = "100%",
                        height = "auto",
                        halign = "left",
                        valign = "top",
                        flow = "horizontal",
                        savedoc = function(element)
                            element:HaltEventPropagation()
                        end,
                        refreshDocument = function(element)
                            element:HaltEventPropagation()
                        end,
                        editDocument = function(element)
                            element:HaltEventPropagation()
                        end,
                        refreshTag = function(element)
                            element:HaltEventPropagation()
                        end,

                        gui.MarkdownLabel{
                            width = "100%-20",
                            halign = "right",
                            markdownText = function(element, text)
                                element:HaltEventPropagation()
                                element.text = text
                            end,
                        }
                    }

                    if m_blockquotes[#newBlockquotes + 1] ~= nil then
                        blockquote:Unparent()
                    end

                    blockquote:FireEventTree("markdownText", SkinQuoteText(resolvedSkin.quote, token.text))

                    ApplyQuoteFrame(blockquote, resolvedSkin.quote)

                    newBlockquotes[#newBlockquotes + 1] = blockquote

                    children[#children+1] = blockquote

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
                    ApplyBlockFrame(styleblock, box)

                    if m_styleblocks[#newStyleblocks + 1] ~= nil then
                        styleblock:Unparent()
                    end

                    local innerText = token.text
                    if type(cls) == "table" and cls.kind == "block" and cls.text ~= nil then
                        innerText = SkinClassTextMarkup(cls.text, token.text)
                    end
                    styleblock:FireEventTree("markdownText", innerText)

                    newStyleblocks[#newStyleblocks + 1] = styleblock
                    children[#children + 1] = styleblock

                elseif token.type == "tag" then
                    if currentTable ~= nil and currentTableRow == nil then
                        --end of table.
                        currentRollableTable = nil
                        currentRichRow = nil
                        currentTable = nil
                    end

                    local text, suffix
                    local match = regex.MatchGroups(token.text, "^(?<text>.+?):(?<name>.+)$")
                    if match ~= nil then
                        text = match.text
                        suffix = match.name
                    end

                    local text, suffix = token.text:match("^(.-):(.*)$")
                    if suffix == nil then
                        text = token.text
                    end

                    local fullname = token.text
                    local richTagFromPattern = nil

                    local patternMatch = nil

                    for key, richTag in pairs(MarkdownDocument.RichTagRegistry) do
                        if richTag.pattern then
                            patternMatch = regex.MatchGroups(token.text, richTag.pattern)
                            if patternMatch ~= nil then
                                fullname = key
                                text = key
                                richTagFromPattern = richTag
                                break
                            end
                        end
                    end

                    local richTagInfo = MarkdownDocument.RichTagRegistry[string.lower(text)]

                    if richTagInfo ~= nil then
                        local candidate = fullname
                        local index = 1
                        while tagsSeen[candidate] do
                            candidate = fullname .. '-' .. index
                            index = index + 1
                        end

                        tagsSeen[candidate] = true

                        local richTag
                        
                        if richTagFromPattern then
                            richTag = DeepCopy(richTagFromPattern)
                        else
                            richTag = self.annotations[candidate]

                            --patch over any possible bugs where the saved annotation is not a proper table.
                            if richTag ~= nil and getmetatable(richTag) == nil then
                                richTag = nil
                                self.annotations[candidate] = nil
                            end
                        end

                        
                        if richTag ~= nil then
                            local panel = m_richPanels[candidate] or richTag:CreateDisplay()

                            if currentRichRow == nil then
                                currentRichRow = m_richRows[#newRichRows + 1] or gui.Panel {
                                    flow = "horizontal",
                                    height = "auto",
                                    vmargin = 0,
                                }
                                if m_richRows[#newRichRows + 1] ~= nil then
                                    currentRichRow:Unparent()
                                end
                                currentRichRow.selfStyle.width = "100%"
                                currentRichRow.selfStyle.valign = "top"
                                currentRichRow.selfStyle.maxWidth = nil
                                currentRichRow.data.children = {}
                                newRichRows[#newRichRows + 1] = currentRichRow
                                children[#children + 1] = currentRichRow
                            end

                            if m_richPanels[candidate] ~= nil and panel.parent ~= currentRichRow then
                                panel:Unparent()
                            end

                            if token.justification then
                                currentRichRow.selfStyle.width = "100%"
                            end

                            richTag._tmp_document = self
                            panel:FireEventTree("refreshTag", richTag, patternMatch or match, token)

                            newRichPanels[candidate] = panel
                            local embedBox = (resolvedSkin.embed or {}).box
                            if g_standaloneEmbedTags[string.lower(text)] and embedBox ~= nil and next(embedBox) ~= nil then
                                -- Wrap so the rich-tag's own look is preserved inside
                                -- the stylesheet frame (do NOT ApplyBlockFrame the
                                -- component panel directly).
                                local frame = m_richFrames[candidate] or gui.Panel { width = "auto", height = "auto", valign = "top" }
                                ApplyBlockFrame(frame, embedBox)
                                frame.children = { panel }
                                newRichFrames[candidate] = frame
                                currentRichRow.data.children[#currentRichRow.data.children + 1] = frame
                            else
                                currentRichRow.data.children[#currentRichRow.data.children + 1] = panel
                            end
                        end
                    end
                end

                -- Stamp the source line onto whatever top-level children this token
                -- appended (overwrite, so reused/cached panels refresh each render).
                for k = stampFrom, #stampChildren do
                    stampChildren[k].data.srcLine = stampLine
                end
            end

            for i, row in ipairs(newRichRows) do
                row.children = row.data.children
                row.data.children = nil
            end

            for i, row in ipairs(newTableRows) do
                row.children = row.data.children
                row.data.children = nil
            end

            for i, t in ipairs(newTables) do
                -- t is the wrapper; commit rows onto the gui.Table it holds. The
                -- wrapper carries the block FRAME and the Table carries its inner row
                -- colors via `styles` (both set in the table render branch), so no
                -- post-build styling is needed here.
                local tbl = t.data.tablePanel
                tbl.children = tbl.data.children
                tbl.data.children = nil
            end

            m_rollableTableRowLabels = newRollableTableRowLabels
            m_rollableTables = newRollableTables
            m_richRows = newRichRows
            m_richPanels = newRichPanels
            m_richFrames = newRichFrames
            m_textPanels = newTextPanels
            m_tableRows = newTableRows
            m_tables = newTables
            m_dividers = newDividers
            m_headingRules = newHeadingRules
            m_powerTables = newPowerTables
            m_embeds = newEmbeds
            m_treeNodes = newTreeNodes
            m_blockquotes = newBlockquotes
            m_styleblocks = newStyleblocks
            element.children = children
        end,
        monitorGame = "/assets/objectTables/" .. JournalStylesheet.tableName,
        refreshGame = function(element)
            ResolveStylesheet.ClearCache()
            element:FireEvent("refreshDocument", self)
        end,
    }

    for k, v in pairs(args) do
        params[k] = v
    end

    resultPanel = gui.Panel(params)
    resultPanel:FireEventTree("refreshDocument")

    ThemeEngine.OnThemeChanged(mod, function()
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.styles = ThemeEngine.GetStyles()
            resultPanel:FireEventTree("refreshDocument")
        end
    end)

    return resultPanel
end

local MarkdownReferenceTooltip

function MarkdownDocument:EditPanel(args)
    local resultPanel

    local markdownReferenceLabel = gui.Label {
        classes = { "link" },
        width = "auto",
        height = "auto",
        text = "Formatting Guide",
        fontSize = CustomDocument.ScaleFontSize(16),
        halign = "left",
        valign = "top",
        hover = function(element)
            element.tooltip = MarkdownReferenceTooltip()
        end,
    }

    local editInput

    local savePanel = gui.Panel{
        flow = "horizontal",
        width = 160,
        height = 16,
        halign = "right",

        gui.Label{

            styles = {
                {
                    selectors = {"changes"},
                    collapsed = 1,
                },
                {
                    selectors = {"savePending"},
                    collapsed = 1,
                },
            },

            text = "Changes Saved",
            fontSize = 14,
            width = "auto",
            height = "auto",
        },

        gui.Label{
            classes = { "fgMuted" },
            styles = {
                {
                    selectors = {"changes"},
                    collapsed = 1,
                },
                {
                    selectors = {"~savePending"},
                    collapsed = 1,
                },
            },

            text = "Saving...",
            fontSize = 14,
            width = "auto",
            height = "auto",
        },

        gui.Label{
            styles = {
                {
                    selectors = {"~changes"},
                    collapsed = 1,
                }
            },
            text = "Unsaved Changes",
            fontSize = 14,
            width = "auto",
            height = "auto",
        },

        gui.Button{
            styles = {
                {
                    selectors = {"~changes"},
                    collapsed = 1,
                }
            },
            inputEvents = { "save" },
            text = "Save",
            width = 40,
            height = 16,
            fontSize = 12,
            save = function(element)
                if element:HasClass("changes") then
                    element:FireEvent("press")
                end
            end,
            press = function(element)
                local documentPanel = element:FindParentWithClass("documentPanel")
                if documentPanel ~= nil then
                    resultPanel:SetClassTree("savePending", true)
                    documentPanel:FireEvent("saveDocument")
                end
            end,

            saveConfirmed = function(element)
                resultPanel:SetClassTree("savePending", false)
            end,
        },
    }

    local charactersUsedLabel = gui.Label {
        classes = {"fg"},
        width = "auto",
        height = "auto",
        halign = "right",
        valign = "center",
        rmargin = 246,
        fontSize = CustomDocument.ScaleFontSize(16),
        refreshLength = function(element, text)
            local len = #text
            local remaining = CustomDocument.MaxLength - len
            if remaining < 1000 then
                element:SetClass("danger", remaining < 200)

                element.text = string.format("%d characters remaining...", remaining)
                element:SetClass("hidden", false)
            else
                element:SetClass("hidden", true)
            end
        end,
        refreshDocument = function(element)
            element:FireEvent("refreshLen", #self:GetTextContent())
        end,
        editDocument = function(element)
            element:FireEvent("refreshLen", #self:GetTextContent())
        end,
    }

    -- Link autocomplete helpers
    local autocompleteState = {
        results = {},
        selectedIndex = 1,
    }

    -- Find an unclosed [ or [[ before the caret, returning the search text,
    -- bracket position, and context type ("link" or "richTag").
    -- Returns nil if the caret is not inside an open bracket.
    local function FindLinkContext(text, caretPos)
        local beforeCaret = string.sub(text, 1, caretPos)
        local afterCaret = string.sub(text, caretPos + 1)

        -- Check for caret inside the (link) portion of a [text](link). This
        -- fires even when ) is already present so editing an existing link
        -- target gets autocomplete too. Search text is whatever sits between
        -- ( and the caret.
        for i = #beforeCaret, 1, -1 do
            local ch = string.sub(beforeCaret, i, i)
            if ch == '\n' or ch == ')' or ch == '[' or ch == ']' then
                break
            elseif ch == '(' then
                if i > 1 and string.sub(beforeCaret, i - 1, i - 1) == ']' then
                    return string.sub(beforeCaret, i + 1), i, "linkTarget"
                end
                break
            end
        end

        -- Search backwards for an unclosed [ or [[
        local bracketPos = nil
        local depth = 0
        local isRichTag = false
        for i = #beforeCaret, 1, -1 do
            local ch = string.sub(beforeCaret, i, i)
            if ch == ']' then
                depth = depth + 1
            elseif ch == '[' then
                if depth > 0 then
                    depth = depth - 1
                else
                    if i > 1 and string.sub(beforeCaret, i - 1, i - 1) == '[' then
                        -- [[ rich tag opener
                        isRichTag = true
                        bracketPos = i - 1
                    else
                        bracketPos = i
                    end
                    break
                end
            elseif ch == '\n' then
                return nil
            end
        end

        if bracketPos == nil then
            return nil
        end

        -- If the bracket is already closed after the cursor, no autocomplete needed
        if isRichTag then
            -- Check for ]] after caret
            local found = string.find(afterCaret, "]]", 1, true)
            if found ~= nil then
                -- Make sure there's no newline before the ]]
                local nl = string.find(afterCaret, "\n", 1, true)
                if nl == nil or nl > found then
                    return nil
                end
            end
        else
            for i = 1, #afterCaret do
                local ch = string.sub(afterCaret, i, i)
                if ch == ']' then
                    return nil
                elseif ch == '[' or ch == '\n' then
                    break
                end
            end
        end

        if isRichTag then
            -- Return text after [[
            return string.sub(beforeCaret, bracketPos + 2), bracketPos, "richTag"
        else
            return string.sub(beforeCaret, bracketPos + 1), bracketPos, "link"
        end
    end

    -- Find a completed [[ ]] rich tag around the caret.
    -- Returns tagText, bracketOpen or nil.
    local function FindCompletedRichTagAtCaret(text, caretPos)
        local beforeCaret = string.sub(text, 1, caretPos)

        -- Search backwards for [[ (not preceded by another [)
        local openPos = nil
        for i = #beforeCaret, 2, -1 do
            local ch = string.sub(beforeCaret, i, i)
            if ch == '[' and string.sub(beforeCaret, i - 1, i - 1) == '[' then
                openPos = i - 1
                break
            elseif ch == ']' or ch == '\n' then
                return nil
            end
        end

        if openPos == nil then
            return nil
        end

        -- Find matching ]] after the opening [[
        local closePos = string.find(text, "]]", openPos + 2, true)
        if closePos == nil then
            return nil
        end

        -- Make sure there's no newline between [[ and ]]
        local inner = string.sub(text, openPos + 2, closePos - 1)
        if string.find(inner, "\n", 1, true) then
            return nil
        end

        -- Caret must be within the [[ ... ]] range (inclusive of brackets)
        if caretPos < openPos or caretPos > closePos + 1 then
            return nil
        end

        return inner, openPos
    end

    -- Find a completed link around the caret. Returns linkText, displayName, bracketOpen or nil.
    -- Handles both [link] and [display](link) forms. Skips [[ ]] rich tags.
    local function FindCompletedLinkAtCaret(text, caretPos)
        -- First check if we're inside a rich tag -- if so, not a link.
        if FindCompletedRichTagAtCaret(text, caretPos) ~= nil then
            return nil
        end

        local beforeCaret = string.sub(text, 1, caretPos)

        -- If caret is inside the (link) portion of [text](link), resolve from
        -- the parenthesised target rather than the bracketed display text.
        local parenOpen = nil
        for i = #beforeCaret, 1, -1 do
            local ch = string.sub(beforeCaret, i, i)
            if ch == '(' then
                if i > 1 and string.sub(beforeCaret, i - 1, i - 1) == ']' then
                    parenOpen = i
                end
                break
            elseif ch == ')' or ch == '\n' or ch == '[' or ch == ']' then
                break
            end
        end
        if parenOpen ~= nil then
            local parenClose = nil
            for i = caretPos + 1, #text do
                local ch = string.sub(text, i, i)
                if ch == ')' then
                    parenClose = i
                    break
                elseif ch == '\n' then
                    break
                end
            end
            if parenClose ~= nil then
                local closeBracket = parenOpen - 1
                local openBracket = nil
                for i = closeBracket - 1, 1, -1 do
                    local ch = string.sub(text, i, i)
                    if ch == '[' then
                        -- Skip [[ rich tag opener
                        if i > 1 and string.sub(text, i - 1, i - 1) == '[' then
                            openBracket = nil
                        else
                            openBracket = i
                        end
                        break
                    elseif ch == '\n' or ch == ']' then
                        break
                    end
                end
                if openBracket ~= nil then
                    local displayName = string.sub(text, openBracket + 1, closeBracket - 1)
                    local linkTarget = string.sub(text, parenOpen + 1, parenClose - 1)
                    return linkTarget, displayName, openBracket
                end
            end
        end

        -- Search backwards from caret for the nearest [ that has a matching ]

        -- Find the [ before or at the caret. Stop at ] or newline.
        local bracketOpen = nil
        for i = #beforeCaret, 1, -1 do
            local ch = string.sub(beforeCaret, i, i)
            if ch == '[' then
                -- Skip [[ (check both directions)
                if i > 1 and string.sub(beforeCaret, i - 1, i - 1) == '[' then
                    return nil
                end
                if i < #text and string.sub(text, i + 1, i + 1) == '[' then
                    return nil
                end
                bracketOpen = i
                break
            elseif ch == ']' or ch == '\n' then
                return nil
            end
        end

        if bracketOpen == nil then
            return nil
        end

        -- Find the matching ] after the open bracket
        local bracketClose = nil
        for i = bracketOpen + 1, #text do
            local ch = string.sub(text, i, i)
            if ch == ']' then
                bracketClose = i
                break
            elseif ch == '\n' then
                return nil
            end
        end

        if bracketClose == nil then
            return nil
        end

        -- Caret must be between [ and ] (inclusive of edges)
        if caretPos < bracketOpen or caretPos > bracketClose then
            return nil
        end

        local innerText = string.sub(text, bracketOpen + 1, bracketClose - 1)

        -- Check for [display](link) form
        if bracketClose < #text and string.sub(text, bracketClose + 1, bracketClose + 1) == '(' then
            local parenClose = string.find(text, ')', bracketClose + 2, true)
            if parenClose ~= nil then
                local linkTarget = string.sub(text, bracketClose + 2, parenClose - 1)
                return linkTarget, innerText, bracketOpen
            end
        end

        -- Plain [link] form
        return innerText, innerText, bracketOpen
    end

    local autocompleteTypeClasses = {
        ["Document"]     = "implStatus2",
        ["PDF Document"] = "implStatus2",
        ["PDF Fragment"] = "implStatus2",
        ["Map"]          = "implStatus3",
        ["item"]         = "implStatus4",
        ["title"]        = "implStatus4",
        ["monster"]      = "implStatus0",
        ["Rich Tag"]     = "implStatus0",
        ["Command"]      = "implStatus1",
    }

    -- Descriptions and metadata for rich tags used by autocomplete.
    -- patternExample: if set, the tag is pattern-based and this is inserted as the
    --   content between [[ and ]] (e.g. [[5]] for counter). The tag name is NOT used.
    -- takesName: if true, the tag uses [[tagname]] or [[tagname:suffix]] syntax and
    --   a unique name is auto-generated on insert.
    local richTagDescriptions = {
        dice = {desc = "Embeddable dice roll", takesName = true},
        counter = {desc = "Editable numeric counter", patternExample = "0"},
        checkbox = {desc = "Toggleable checkbox", patternExample = "[ ]"},
        timer = {desc = "Countdown timer", takesName = true},
        image = {desc = "Embedded image", takesName = true},
        sound = {desc = "Audio player", takesName = true},
        bar = {desc = "Progress or health bar", patternExample = "###--"},
        macro = {desc = "Clickable command button", patternExample = "/roll 1d20|Roll"},
        encounter = {desc = "Embedded encounter", takesName = true},
        scene = {desc = "Scene reference", takesName = true},
        party = {desc = "Party display", takesName = true},
        reminder = {desc = "Reminder notification", takesName = true},
        follower = {desc = "Companion or follower", takesName = true},
        setting = {desc = "Game setting toggle", patternExample = "setting:settingid"},
        fishing = {desc = "Fishing activity", takesName = true},
    }

    local linkInfoState = {
        currentLink = nil,
        suppressed = false,
        lastCaretPos = nil,
        lastText = nil,
    }

    local function DismissLinkInfo(inputElement)
        if linkInfoState.currentLink ~= nil then
            inputElement.popup = nil
            linkInfoState.currentLink = nil
        end
    end

    local function SuppressLinkInfo(inputElement)
        inputElement.popup = nil
        linkInfoState.currentLink = nil
        linkInfoState.suppressed = true
        linkInfoState.lastCaretPos = inputElement.caretPosition
        linkInfoState.lastText = inputElement.text
    end

    local function ShowLinkInfo(inputElement, linkText, displayName, bracketPos)
        if linkText == linkInfoState.currentLink then
            return
        end
        linkInfoState.currentLink = linkText

        local resolved = CustomDocument.ResolveLink(linkText)
        local children = {}

        if resolved ~= nil then
            -- Valid link: show type and name, hoverable for preview, clickable to open
            local resolvedName = nil
            local resolvedType = nil
            if type(resolved) == "string" then
                resolvedName = resolved
                resolvedType = "URL"
            elseif type(resolved) == "table" then
                resolvedName = rawget(resolved, "name") or rawget(resolved, "description") or rawget(resolved, "monster_type") or displayName

                -- Use the link prefix (e.g. "item", "title") as the display type when it maps to a known table
                local linkPrefix = string.match(linkText, "^([^:]+):")
                if linkPrefix ~= nil and MarkdownRender.FindTableFromPrefix(string.lower(linkPrefix)) ~= nil then
                    resolvedType = linkPrefix
                else
                    resolvedType = rawget(resolved, "typeName") or "Link"
                end
            end

            local typeClass = autocompleteTypeClasses[resolvedType] or "fgMuted"

            children[#children + 1] = gui.Panel{
                classes = {"contextMenuItem"},
                width = "100%-20",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                hpad = 10,
                vpad = 5,
                hover = function(element)
                    CustomDocument.PreviewLink(element, linkText)
                end,
                press = function(element)
                    SuppressLinkInfo(inputElement)
                    inputElement.hasInputFocus = false
                    CustomDocument.OpenContent(resolved)
                end,
                gui.Label{
                    classes = {"contextMenuLabel", "sizeS"},
                    text = resolvedName or displayName,
                    -- fontSize = 14,
                    width = "100%-90",
                    height = "auto",
                    textAlignment = "left",
                    valign = "center",
                    -- }),
                },
                gui.Label{
                    classes = { "contextMenuLabel", "sizeXs", typeClass },
                    text = resolvedType,
                    -- fontSize = 11,
                    width = 90,
                    height = "auto",
                    halign = "right",
                    textAlignment = "right",
                    valign = "center",
                },
            }
        else
            -- Invalid link
            children[#children + 1] = gui.Panel{
                width = "100%-20",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                hpad = 10,
                vpad = 5,
                gui.Label{
                    classes = { "danger" },
                    text = string.format("No link found for \"%s\"", displayName),
                    fontSize = 13,
                    width = "100%",
                    height = "auto",
                    textAlignment = "left",
                },
            }

            -- Offer suggestions
            local suggestions = CustomDocument.SearchLinks(linkText)
            table.sort(suggestions, function(a, b)
                if (a.isPrefix and true or false) ~= (b.isPrefix and true or false) then
                    return a.isPrefix and true or false
                end
                return a.name < b.name
            end)

            local maxSuggestions = 5
            for i = 1, math.min(#suggestions, maxSuggestions) do
                local result = suggestions[i]
                local typeClass = autocompleteTypeClasses[result.type] or "fgMuted"
                children[#children + 1] = gui.Panel{
                    classes = {"contextMenuItem"},
                    width = "100%-20",
                    height = "auto",
                    flow = "horizontal",
                    halign = "center",
                    hpad = 10,
                    vpad = 4,
                    press = function(element)
                        -- Replace the link text with the suggestion
                        local text = inputElement.text
                        local caret = inputElement.caretPosition
                        local lt, dn = FindCompletedLinkAtCaret(text, caret)
                        if lt ~= nil then
                            -- Find the bracket positions again
                            local openBracket = nil
                            for j = caret, 1, -1 do
                                if string.sub(text, j, j) == '[' then
                                    openBracket = j
                                    break
                                end
                            end
                            if openBracket ~= nil then
                                local closeBracket = string.find(text, ']', openBracket + 1, true)
                                if closeBracket ~= nil then
                                    local before = string.sub(text, 1, openBracket - 1)
                                    -- Skip past ](link) if present
                                    local afterClose = closeBracket
                                    if closeBracket < #text and string.sub(text, closeBracket + 1, closeBracket + 1) == '(' then
                                        local parenClose = string.find(text, ')', closeBracket + 2, true)
                                        if parenClose ~= nil then
                                            afterClose = parenClose
                                        end
                                    end
                                    local after = string.sub(text, afterClose + 1)
                                    local insertion
                                    local linkPrefix = string.match(result.link, "^([^:]+):")
                                    if linkPrefix ~= nil and MarkdownRender.FindTableFromPrefix(linkPrefix) ~= nil then
                                        insertion = string.format("[%s]", result.link)
                                    else
                                        insertion = string.format("[%s](%s)", result.name, result.link)
                                    end
                                    local newText = before .. insertion .. after
                                    local targetCaret = #before + #insertion
                                    if resultPanel ~= nil then
                                        resultPanel:FireEventTree("editDocument", newText)
                                    end
                                    charactersUsedLabel:FireEvent("refreshLength", newText)
                                    DismissLinkInfo(inputElement)
                                    inputElement:SetTextAndCaret(targetCaret, newText)
                                end
                            end
                        end
                    end,
                    gui.Label{
                        classes = {"contextMenuLabel", "sizeS"},
                        text = result.name,
                        width = "100%-80",
                        height = "auto",
                        textAlignment = "left",
                        valign = "center",
                    },
                    gui.Label{
                        classes = { "contextMenuLabel", "sizeXs", typeClass },
                        text = result.type,
                        width = 80,
                        height = "auto",
                        halign = "right",
                        textAlignment = "right",
                        valign = "center",
                    },
                }
            end
        end

        local popup = gui.Panel{
            width = "auto",
            height = "auto",
            valign = "bottom",
            halign = "right",
            gui.Panel{
                classes = {"bordered", "bg"},
                width = 400,
                height = "auto",
                maxHeight = 300,
                flow = "vertical",
                children = children,
            },
        }
        -- Position at the opening [ bracket
        local anchorPos = bracketPos and inputElement:GetCharWorldPosition(bracketPos) or nil
        if anchorPos ~= nil then
            inputElement.popupPositioning = anchorPos
        else
            inputElement.popupPositioning = "panel"
        end
        inputElement.popupsInheritStyles = true
        inputElement.popup = popup
    end

    local function ShowRichTagInfo(inputElement, tagText, bracketPos)
        -- Avoid re-showing the same tag
        if tagText == linkInfoState.currentLink then
            return
        end
        linkInfoState.currentLink = tagText

        -- Parse tag name and look up description
        local tagName = tagText
        local colonPos = string.find(tagText, ":", 1, true)
        if colonPos ~= nil then
            tagName = string.sub(tagText, 1, colonPos - 1)
        end
        tagName = string.lower(tagName)

        -- Check if this is a macro tag (starts with /)
        local isMacro = string.sub(tagText, 1, 1) == "/"
        local meta
        if isMacro then
            -- Extract command and display text from macro pattern /command|text
            local pipePos = string.find(tagText, "|", 1, true)
            local macroCmd = pipePos and string.sub(tagText, 2, pipePos - 1) or string.sub(tagText, 2)
            meta = {desc = string.format("Command button: /%s", macroCmd)}
        else
            meta = richTagDescriptions[tagName] or {}
        end

        local children = {}

        if meta.desc then
            children[#children + 1] = gui.Label{
                classes = {"fg"},
                text = meta.desc,
                fontSize = 13,
                width = "100%",
                height = "auto",
                vpad = 4,
            }
        end

        -- Render a mini preview of the tag, passing matching annotations
        -- from the current document so tags like [[encounter]] render properly
        local tagContent = string.format("[[%s]]", tagText)
        local previewAnnotations = {}
        if self.annotations ~= nil then
            -- The tag key in annotations is the tagText itself (e.g. "encounter:Name")
            -- Also check with disambiguation suffixes (-1, -2, etc.)
            for k, v in pairs(self.annotations) do
                if k == tagText or string.starts_with(k, tagText .. "-") then
                    previewAnnotations[k] = v
                end
            end
        end
        local previewDoc = MarkdownDocument.new{
            content = tagContent,
            annotations = previewAnnotations,
        }
        children[#children + 1] = previewDoc:DisplayPanel{
            width = "100%",
            height = "auto",
            vscroll = false,
        }

        local popup = gui.Panel{
            width = "auto",
            height = "auto",
            valign = "bottom",
            halign = "right",
            gui.Panel{
                classes = {"bordered", "bg"},
                width = 300,
                height = "auto",
                maxHeight = 300,
                flow = "vertical",
                children = children,
            },
        }

        local anchorPos = bracketPos and inputElement:GetCharWorldPosition(bracketPos) or nil
        if anchorPos ~= nil then
            inputElement.popupPositioning = anchorPos
        else
            inputElement.popupPositioning = "panel"
        end
        inputElement.popupsInheritStyles = true
        inputElement.popup = popup
    end

    local function UpdateLinkInfo(inputElement)
        local text = inputElement.text
        local caretPos = inputElement.caretPosition

        -- If suppressed, only clear suppression when caret or text changes
        if linkInfoState.suppressed then
            if caretPos ~= linkInfoState.lastCaretPos or text ~= linkInfoState.lastText then
                linkInfoState.suppressed = false
            else
                return
            end
        end

        -- Check for rich tag first
        local richTagText, richBracketPos = FindCompletedRichTagAtCaret(text, caretPos)
        if richTagText ~= nil and #richTagText > 0 then
            ShowRichTagInfo(inputElement, richTagText, richBracketPos)
            return
        end

        local linkText, displayName, bracketPos = FindCompletedLinkAtCaret(text, caretPos)
        if linkText ~= nil and #linkText > 0 then
            ShowLinkInfo(inputElement, linkText, displayName, bracketPos)
        else
            DismissLinkInfo(inputElement)
        end
    end

    local UpdateAutocomplete -- forward declaration for use in AcceptAutocomplete

    local function DismissAutocomplete(inputElement)
        if #autocompleteState.results > 0 then
            inputElement.popup = nil
            autocompleteState.results = {}
            autocompleteState.selectedIndex = 1
            linkInfoState.currentLink = nil
        end
    end

    local function AcceptAutocomplete(inputElement, result)
        local text = inputElement.text
        local caretPos = inputElement.caretPosition
        local searchText, bracketPos, contextType = FindLinkContext(text, caretPos)
        if searchText == nil or bracketPos == nil then
            DismissAutocomplete(inputElement)
            return
        end

        if contextType == "linkTarget" then
            -- Replace the link target inside [text](link). bracketPos is the
            -- position of (; we keep [text]( and ) (or newline / end of line)
            -- and overwrite everything between with result.link.
            local afterCaret = string.sub(text, caretPos + 1)
            local closeOffset = string.find(afterCaret, "[)\n]")
            local replaceEnd
            if closeOffset == nil then
                replaceEnd = #text
            else
                replaceEnd = caretPos + closeOffset - 1
            end
            local before = string.sub(text, 1, bracketPos)
            local after = string.sub(text, replaceEnd + 1)
            local newText = before .. result.link .. after
            local targetCaretPos = #before + #result.link
            if resultPanel ~= nil then
                resultPanel:FireEventTree("editDocument", newText)
            end
            charactersUsedLabel:FireEvent("refreshLength", newText)
            DismissAutocomplete(inputElement)
            inputElement:SetTextAndCaret(targetCaretPos, newText)
            return
        end

        local before = string.sub(text, 1, bracketPos - 1)
        local after = string.sub(text, caretPos + 1)

        if result.isRichTagPrefix then
            -- Insert [[ and re-trigger autocomplete for rich tag names.
            DismissAutocomplete(inputElement)
            local newText = before .. "[[" .. after
            local targetCaretPos = #before + 2
            if resultPanel ~= nil then
                resultPanel:FireEventTree("editDocument", newText)
            end
            charactersUsedLabel:FireEvent("refreshLength", newText)
            inputElement:SetTextAndCaret(targetCaretPos, newText)
            return
        end

        if result.isMacroCommand then
            -- Complete a macro command: insert [[/command|Display Text]]
            DismissAutocomplete(inputElement)
            local insertion = string.format("[[/%s|%s]]", result.macroCommand, result.macroText)
            local newText = before .. insertion .. after
            -- Place caret after the insertion
            local targetCaretPos = #before + #insertion
            if resultPanel ~= nil then
                resultPanel:FireEventTree("editDocument", newText)
            end
            charactersUsedLabel:FireEvent("refreshLength", newText)
            inputElement:SetTextAndCaret(targetCaretPos, newText)
            return
        end

        if result.isRichTag then
            -- Complete a rich tag name inside [[ ]]
            DismissAutocomplete(inputElement)
            local tagName = result.link
            local insertion

            if result.patternExample then
                -- Pattern-based tag: insert the example content directly.
                -- e.g. counter -> [[0]], bar -> [[###--]]
                insertion = string.format("[[%s]]", result.patternExample)
            elseif result.takesName then
                -- Name-based tag: generate a unique name suffix.
                -- Scan the rest of the document for existing tags to avoid dupes.
                local docText = before .. after
                local baseName = tagName
                local candidate = baseName
                local index = 2
                while string.find(docText, "[[" .. candidate .. "]]", 1, true)
                   or string.find(docText, "[[" .. candidate .. ":", 1, true) do
                    candidate = baseName .. index
                    index = index + 1
                end
                insertion = string.format("[[%s]]", candidate)
            else
                insertion = string.format("[[%s]]", tagName)
            end

            local newText = before .. insertion .. after
            -- Place caret before ]] so the user can add or edit content
            local targetCaretPos = #before + #insertion - 2
            if resultPanel ~= nil then
                resultPanel:FireEventTree("editDocument", newText)
            end
            charactersUsedLabel:FireEvent("refreshLength", newText)
            inputElement:SetTextAndCaret(targetCaretPos, newText)
            return
        end

        if result.isPrefix then
            -- Prefix suggestion (e.g. "item:"): insert just the prefix,
            -- keep the bracket open, and re-trigger autocomplete.
            DismissAutocomplete(inputElement)
            local newText = before .. "[" .. result.link .. after
            local targetCaretPos = #before + 1 + #result.link
            if resultPanel ~= nil then
                resultPanel:FireEventTree("editDocument", newText)
            end
            charactersUsedLabel:FireEvent("refreshLength", newText)
            -- Use engine-side SetTextAndCaret which defers the caret
            -- positioning until after TMP's activation processing.
            -- The 'caretReady' event fires once the caret is stable.
            inputElement:SetTextAndCaret(targetCaretPos, newText)
            return
        end

        -- For prefixed table entries (e.g. item:Bloodbound Band), the link
        -- text is the full reference, so use [link] form directly.
        -- For other types, use [name](link) form.
        local insertion
        local linkPrefix = string.match(result.link, "^([^:]+):")
        if linkPrefix ~= nil and MarkdownRender.FindTableFromPrefix(linkPrefix) ~= nil then
            insertion = string.format("[%s]", result.link)
        else
            insertion = string.format("[%s](%s)", result.name, result.link)
        end
        local newText = before .. insertion .. after
        local targetCaretPos = #before + #insertion
        if resultPanel ~= nil then
            resultPanel:FireEventTree("editDocument", newText)
        end
        charactersUsedLabel:FireEvent("refreshLength", newText)
        DismissAutocomplete(inputElement)
        inputElement:SetTextAndCaret(targetCaretPos, newText)
    end

    local function BuildAutocompletePopup(inputElement, results)
        local maxShow = 8
        local children = {}
        inputElement.popupsInheritStyles = true

        for i = 1, math.min(#results, maxShow) do
            local result = results[i]
            local typeClass = autocompleteTypeClasses[result.type] or "fgMuted"
            children[#children + 1] = gui.Panel{
                -- bgimage = true,
                -- width excludes padding, so subtract 2*hpad to stay within parent bounds
                classes = {"contextMenuItem"},
                width = "100%-40",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                hpad = 10,
                vpad = 5,
                press = function(element)
                    AcceptAutocomplete(inputElement, result)
                end,
                hover = function(element)
                    if result.isMacroCommand then
                        -- Show a preview of the macro button
                        local tagContent = string.format("[[/%s|%s]]", result.macroCommand, result.macroText)
                        local tooltipChildren = {}
                        if result.desc then
                            tooltipChildren[#tooltipChildren + 1] = gui.Label{
                                classes = {"fg"},
                                text = result.desc,
                                fontSize = 13,
                                width = "100%",
                                height = "auto",
                                vpad = 4,
                            }
                        end
                        local previewDoc = MarkdownDocument.new{
                            content = tagContent,
                        }
                        tooltipChildren[#tooltipChildren + 1] = previewDoc:DisplayPanel{
                            width = "100%",
                            height = "auto",
                            vscroll = false,
                        }
                        local panel = gui.Panel{
                            width = 300,
                            height = "auto",
                            flow = "vertical",
                            pad = 6,
                            children = tooltipChildren,
                        }
                        element.tooltip = gui.TooltipFrame(panel, {
                            interactable = false,
                            halign = "right",
                        })
                        element.tooltip:MakeNonInteractiveRecursive()
                    elseif result.isRichTag or result.isRichTagPrefix then
                        -- Render a mini document showing what the rich tag looks like.
                        local tagContent
                        if result.patternExample then
                            tagContent = string.format("[[%s]]", result.patternExample)
                        elseif result.isRichTag then
                            tagContent = string.format("[[%s]]", result.link)
                        end

                        local tooltipChildren = {}
                        if result.desc then
                            tooltipChildren[#tooltipChildren + 1] = gui.Label{
                                classes = {"fg"},
                                text = result.desc,
                                fontSize = 13,
                                width = "100%",
                                height = "auto",
                                vpad = 4,
                            }
                        end
                        if tagContent then
                            local previewAnnotations = {}
                            if self.annotations ~= nil and result.link then
                                for k, v in pairs(self.annotations) do
                                    if k == result.link or string.starts_with(k, result.link .. "-") then
                                        previewAnnotations[k] = v
                                    end
                                end
                            end
                            local previewDoc = MarkdownDocument.new{
                                content = tagContent,
                                annotations = previewAnnotations,
                            }
                            tooltipChildren[#tooltipChildren + 1] = previewDoc:DisplayPanel{
                                width = "100%",
                                height = "auto",
                                vscroll = false,
                            }
                        end
                        if #tooltipChildren > 0 then
                            local panel = gui.Panel{
                                width = 300,
                                height = "auto",
                                flow = "vertical",
                                pad = 6,
                                children = tooltipChildren,
                            }
                            element.tooltip = gui.TooltipFrame(panel, {
                                interactable = false,
                                halign = "right",
                            })
                            element.tooltip:MakeNonInteractiveRecursive()
                        end
                    else
                        CustomDocument.PreviewLink(element, result.link)
                    end
                end,
                gui.Label{
                    classes = {"fg", "sizeXs", "contextMenuLabel"},
                    text = result.name,
                    width = "100%-90",
                    height = "auto",
                    textAlignment = "left",
                    valign = "center",
                },
                gui.Label{
                    classes = {"sizeXs", "contextMenuLabel", typeClass},
                    text = result.type,
                    width = 90,
                    height = "auto",
                    halign = "right",
                    textAlignment = "right",
                    valign = "center",
                },
            }
        end

        if #results > maxShow then
            children[#children + 1] = gui.Label{
                classes = { "fgMuted", "sizeXxs" },
                text = string.format("... and %d more results", #results - maxShow),
                width = "100%",
                height = "auto",
                textAlignment = "center",
                vpad = 4,
            }
        end

        return gui.Panel{
            width = "auto",
            height = "auto",
            valign = "bottom",
            halign = "right",
            gui.Panel{
                classes = {"bordered", "bgAlt"},
                width = 400,
                height = "auto",
                maxHeight = 300,
                flow = "vertical",
                children = children,
            },
        }
    end

    UpdateAutocomplete = function(inputElement)
        local text = inputElement.text
        local caretPos = inputElement.caretPosition
        local searchText, bracketPos, contextType = FindLinkContext(text, caretPos)

        if searchText == nil then
            DismissAutocomplete(inputElement)
            return
        end

        local results = {}

        if contextType == "richTag" then
            -- Inside [[ -- search for rich tag completions
            local searchLower = string.lower(searchText)
            -- Split on colon: tag name vs tag data
            local tagName = searchLower
            local colonPos = string.find(searchLower, ":", 1, true)
            if colonPos ~= nil then
                tagName = string.sub(searchLower, 1, colonPos - 1)
            end

            -- Only offer tag name completions if we haven't typed a colon yet
            if colonPos == nil then
                for name, richTag in pairs(MarkdownDocument.RichTagRegistry) do
                    if string.find(name, tagName, 1, true) == 1 and #name > #tagName then
                        local meta = richTagDescriptions[name] or {}
                        local displayName = name
                        if meta.patternExample then
                            displayName = string.format("%s  e.g. [[%s]]", name, meta.patternExample)
                        end
                        results[#results + 1] = {
                            name = displayName,
                            link = name,
                            type = "Rich Tag",
                            isRichTag = true,
                            desc = meta.desc,
                            takesName = meta.takesName,
                            patternExample = meta.patternExample,
                        }
                    end
                end
            end

            -- When the search text starts with /, offer command completions
            if string.sub(searchLower, 1, 1) == "/" then
                local cmdSearch = string.sub(searchLower, 2) -- text after the /
                local pipePos = string.find(cmdSearch, "|", 1, true)
                -- Only offer command completions before the pipe
                if pipePos == nil then
                    -- Search registered UI commands
                    local registeredCmds = Commands.GetRegisteredCommands and Commands.GetRegisteredCommands() or {}
                    for id, info in pairs(registeredCmds) do
                        local cmdName = info.command
                        local displayName = info.name or id
                        -- For setting-based commands, use "toggle settingname"
                        if cmdName == nil and info.setting ~= nil then
                            cmdName = string.format("toggle %s", info.setting)
                        end
                        if cmdName ~= nil and (#cmdSearch == 0 or string.find(string.lower(cmdName), cmdSearch, 1, true) or string.find(string.lower(displayName), cmdSearch, 1, true)) then
                            local suggestedText = displayName
                            results[#results + 1] = {
                                name = string.format("/%s  -  %s", cmdName, displayName),
                                link = cmdName,
                                type = "Command",
                                isMacroCommand = true,
                                macroCommand = cmdName,
                                macroText = suggestedText,
                                desc = string.format("Runs /%s when clicked", cmdName),
                            }
                        end
                    end

                    -- Search registered macros
                    local macros = Commands.GetAllMacros and Commands.GetAllMacros() or {}
                    for name, info in pairs(macros) do
                        if #cmdSearch == 0 or string.find(string.lower(name), cmdSearch, 1, true) then
                            -- Skip if already added from registered commands
                            local alreadyAdded = false
                            for _, r in ipairs(results) do
                                if r.isMacroCommand and r.macroCommand == name then
                                    alreadyAdded = true
                                    break
                                end
                            end
                            if not alreadyAdded then
                                local suggestedText = info.summary or name
                                -- Capitalize first letter for display
                                suggestedText = string.upper(string.sub(suggestedText, 1, 1)) .. string.sub(suggestedText, 2)
                                results[#results + 1] = {
                                    name = string.format("/%s  -  %s", name, info.summary or name),
                                    link = name,
                                    type = "Command",
                                    isMacroCommand = true,
                                    macroCommand = name,
                                    macroText = suggestedText,
                                    desc = info.doc or string.format("Runs /%s when clicked", name),
                                }
                            end
                        end
                    end

                    -- Also search Commands table directly for callable functions
                    for name, fn in pairs(Commands) do
                        if type(fn) == "function" and name ~= "Register" and name ~= "RegisterMacro"
                           and name ~= "GetMacroInfo" and name ~= "GetAllMacros"
                           and name ~= "GetRegisteredCommands" and name ~= "AccumulateMenuItems"
                           and not string.starts_with(name, "_") then
                            if #cmdSearch == 0 or string.find(string.lower(name), cmdSearch, 1, true) then
                                -- Skip if already added
                                local alreadyAdded = false
                                for _, r in ipairs(results) do
                                    if r.isMacroCommand and r.macroCommand == name then
                                        alreadyAdded = true
                                        break
                                    end
                                end
                                if not alreadyAdded then
                                    local macroInfo = Commands.GetMacroInfo and Commands.GetMacroInfo(name) or nil
                                    local summary = macroInfo and macroInfo.summary or name
                                    local suggestedText = string.upper(string.sub(summary, 1, 1)) .. string.sub(summary, 2)
                                    results[#results + 1] = {
                                        name = string.format("/%s", name),
                                        link = name,
                                        type = "Command",
                                        isMacroCommand = true,
                                        macroCommand = name,
                                        macroText = suggestedText,
                                        desc = macroInfo and macroInfo.doc or string.format("Runs /%s when clicked", name),
                                    }
                                end
                            end
                        end
                    end
                end
            end
        elseif contextType == "linkTarget" then
            -- Inside [text](...) -- search for links to fill the target.
            -- Same backing search as plain [ but without the [[ rich-tag prefix
            -- (rich tags can't be the target of a Markdown link).
            if #searchText < 1 then
                DismissAutocomplete(inputElement)
                return
            end
            results = CustomDocument.SearchLinks(searchText)
        else
            -- Inside [ -- search for links
            if #searchText < 1 then
                DismissAutocomplete(inputElement)
                return
            end

            results = CustomDocument.SearchLinks(searchText)

            -- Offer [[ rich tag prefix when search text is short
            if #searchText <= 1 then
                table.insert(results, 1, {
                    name = "[[  Rich Tag",
                    link = "[[",
                    type = "Rich Tag",
                    isRichTagPrefix = true,
                    desc = "Insert an interactive element (dice, image, counter, etc.)",
                })
            end
        end

        -- Rank entries by how well their name matches the typed text. The
        -- effective search term drops any recognized table prefix (e.g. the
        -- "item:" in "item:heal") so "Healing Potion" still ranks as a prefix
        -- match. rank 0 = exact name, 1 = name starts with the search, 2 =
        -- substring match anywhere.
        local rankSearch = string.lower(searchText)
        local rankColon = string.find(rankSearch, ":", 1, true)
        if rankColon ~= nil then
            rankSearch = string.sub(rankSearch, rankColon + 1)
        end
        local function MatchRank(name)
            local n = string.lower(name or "")
            if n == rankSearch then return 0 end
            if string.find(n, rankSearch, 1, true) == 1 then return 1 end
            return 2
        end

        -- Sort prefix suggestions first, then by match rank, then alphabetically.
        table.sort(results, function(a, b)
            -- Rich tag prefix always first
            if (a.isRichTagPrefix and true or false) ~= (b.isRichTagPrefix and true or false) then
                return a.isRichTagPrefix and true or false
            end
            if (a.isPrefix and true or false) ~= (b.isPrefix and true or false) then
                return a.isPrefix and true or false
            end
            local ra, rb = MatchRank(a.name), MatchRank(b.name)
            if ra ~= rb then
                return ra < rb
            end
            return a.name < b.name
        end)

        if #results == 0 then
            DismissAutocomplete(inputElement)
            return
        end

        autocompleteState.results = results
        autocompleteState.selectedIndex = 1
        local popup = BuildAutocompletePopup(inputElement, results)
        -- Position the popup at the opening bracket so it stays stable
        -- as the user types. bracketPos is 1-based from FindLinkContext.
        local anchorPos = inputElement:GetCharWorldPosition(bracketPos)
        if anchorPos ~= nil then
            inputElement.popupPositioning = anchorPos
        else
            inputElement.popupPositioning = "panel"
        end
        inputElement.popup = popup
    end

    local function InsertAction(input, action)
        local text = input.text or ""
        local caret = input.caretPosition or #text
        local anchor = input.selectionAnchorPosition or caret
        local selStart = math.min(caret, anchor)
        local selEnd   = math.max(caret, anchor)
        local selected = text:sub(selStart + 1, selEnd)

        local newText, newCaret

        if action.mode == "wrap" then
            local body = selected
            if body == "" then body = action.placeholder or "" end
            newText = text:sub(1, selStart)
                    .. action.prefix .. body .. action.suffix
                    .. text:sub(selEnd + 1)
            newCaret = selStart + #action.prefix + #body
        elseif action.mode == "linePrefix" then
            local lineStart = selStart
            while lineStart > 0 and text:sub(lineStart, lineStart) ~= "\n" do
                lineStart = lineStart - 1
            end
            newText = text:sub(1, lineStart) .. action.prefix
                    .. text:sub(lineStart + 1)
            newCaret = selStart + #action.prefix
        else
            newText = text:sub(1, selStart) .. action.text
                    .. text:sub(selEnd + 1)
            newCaret = selStart + (action.caretOffset or #action.text)
        end

        input:SetTextAndCaret(newCaret, newText)
        input:FireEvent("edit")
    end

    local function WrapHandler(prefix, suffix)
        return function() InsertAction(editInput, {
            mode = "wrap", prefix = prefix, suffix = suffix,
        }) end
    end

    local function LineHandler(prefix)
        return function() InsertAction(editInput, {
            mode = "linePrefix", prefix = prefix,
        }) end
    end

    local function InsertHandler(text, caretOffset)
        return function() InsertAction(editInput, {
            mode = "insert", text = text, caretOffset = caretOffset,
        }) end
    end

    local function RichTagHandler(tagName)
        return function() InsertAction(editInput, {
            mode = "insert",
            text = string.format("[[%s]]\n", tagName),
        }) end
    end

    local lastSyncedCaret = -1
    -- Scroll the live preview so the block under the editor caret stays in view. A flat
    -- caretLine/totalLines ratio assumes every source line renders at the same height, so it
    -- drifts whenever an image/table/heading (tall) or blank lines (short) sit above the
    -- caret. Instead we map the caret's source line to the real rendered pixel offset of the
    -- block it produced: each top-level preview block is tagged with its source line
    -- (data.srcLine, stamped during render), so summing rendered heights gives every block's
    -- pixel top, and we interpolate between the two anchors bracketing the caret line.
    -- Interpolating (not snapping to a block) keeps scrolling smooth inside a long uniform
    -- prose run while still jumping the right amount past a tall block. Geometry reads are
    -- pcall-guarded and read 0 before layout has run; in that case we bail WITHOUT recording
    -- lastSyncedCaret so the editor's 0.2s think retries next tick. Mirrors the geometry
    -- pattern in Draw Steel V/DrawSteelChararcterSheet.lua (ScrollCapabilityIntoView).
    local SYNC_PREVIEW_TOP_BIAS = 0.3   -- keep the active block ~30% down from the top edge.
    local function SyncPreviewScroll(input, previewPanel, previewBody)
        if previewPanel:HasClass("collapsed") or previewBody == nil then
            return
        end
        local caret = input.caretPosition or 0
        if caret == lastSyncedCaret then
            return
        end

        local text = input.text or ""
        -- 1-based source line of the caret, to match token srcLine.
        local caretLine = 1
        for i = 1, math.min(caret, #text) do
            if text:sub(i, i) == "\n" then
                caretLine = caretLine + 1
            end
        end
        local _, totalNewlines = text:gsub("\n", "\n")
        local totalLines = totalNewlines + 1

        local windowH = 0
        pcall(function() windowH = previewPanel.renderedHeight or 0 end)

        -- Walk the rendered blocks once: accumulate heights for the content height and record
        -- a {line, top} anchor for every block that carries a source line.
        local anchors = {}
        local accum = 0
        pcall(function()
            for _, child in ipairs(previewBody.children) do
                local ln = child.data ~= nil and child.data.srcLine or nil
                if ln ~= nil then
                    anchors[#anchors + 1] = { line = ln, top = accum }
                end
                accum = accum + (child.renderedHeight or 0)
            end
        end)
        local contentH = accum

        if windowH <= 0 or contentH <= 0 then
            -- Layout not measured yet; do not record lastSyncedCaret so think() retries.
            return
        end
        lastSyncedCaret = caret

        local range = contentH - windowH
        if range <= 0 then
            -- Everything fits; nothing to scroll.
            return
        end

        -- Sentinels bracket the document so A/B always exist. A = last anchor at/above the
        -- caret line; B = first anchor below it (topmost when several share a line).
        local A = { line = 0, top = 0 }
        local B = { line = totalLines + 1, top = contentH }
        for _, a in ipairs(anchors) do
            if a.line <= caretLine then
                if a.line > A.line then A = a end
            else
                if a.line < B.line then B = a end
            end
        end

        local span = B.line - A.line
        local frac = 0
        if span > 0 then
            frac = (caretLine - A.line) / span
        end
        frac = math.max(0, math.min(1, frac))
        local targetTop = A.top + (B.top - A.top) * frac

        local desiredTop = targetTop - windowH * SYNC_PREVIEW_TOP_BIAS
        desiredTop = math.max(0, math.min(range, desiredTop))
        -- vscrollPosition: 1 = top, 0 = bottom.
        previewPanel.vscrollPosition = 1 - desiredTop / range
    end

    local previewPanel
    local previewBody

    -- Find bar (Ctrl+F) state. Defined after editInput; forward-declared here so the
    -- editInput 'find' event handler can call OpenFind.
    local findInput, findBar, findCountLabel
    local OpenFind, CloseFind, UpdateFindUI

    -- Markdown syntax highlighting for the editor. Colors are driven by the journal's own
    -- tokenizer (BreakdownRichTags, run with trackPositions) so highlighting matches exactly
    -- how the document is parsed for display. Headings/list markers are not tokenized by
    -- BreakdownRichTags (they are handled at render time by ApplySkinToText), so they are
    -- recognized here per line using the same patterns ApplySkinToText uses.
    local g_journalSyntaxColors = {
        heading    = "#e5c07b",  -- # headings (whole line)
        listMarker = "#56b6c2",  -- -, *, 1. list markers
        tag        = "#61afef",  -- [[ ... ]] rich tags
        embed      = "#c678dd",  -- [: ... ] embeds
        blockquote = "#7f848e",  -- > quotes
        divider    = "#5c6370",  -- --- / ___ dividers
        collapse   = "#d19a66",  -- + collapsible section headers
        styleblock = "#98c379",  -- ::: styled blocks
        table      = "#4ec9b0",  -- | tables / power rolls / rollable tables (teal, not error-red)
        justify    = "#5c6370",  -- :< :> :<> justification markers
    }

    local function ComputeMarkdownColorSpans(text)
        text = text or ""
        if text == "" then return {} end

        -- Match how BreakdownRichTags normalizes line breaks before splitting, so our line indexing
        -- stays aligned with the token srcLine values. '\v' (Shift+Enter soft break) becomes '\n';
        -- this is length-preserving, so byte offsets are unaffected. (We deliberately do NOT strip
        -- '\r' the way BreakdownRichTags does -- that would change length and shift our offsets
        -- relative to the editor's text; the editor normalizes typed '\r' to '\n' anyway.)
        text = text:gsub("\v", "\n")

        -- Split into lines exactly as BreakdownRichTags does, and record each line's 1-based
        -- absolute start offset so token line ranges map back to character positions.
        local lines = string.split_allow_duplicates(text, "\n")
        local lineOffsets = {}
        local off = 1
        for i = 1, #lines do
            lineOffsets[i] = off
            off = off + #lines[i] + 1  -- +1 for the '\n' separator
        end

        local spans = {}
        local function AddSpan(from, to, color)
            -- from/to are 1-based and 'to' is inclusive (matches gui.TextEditor:SetColorSpans).
            if from ~= nil and to ~= nil and color ~= nil and to >= from then
                spans[#spans + 1] = { from = from, to = to, color = color }
            end
        end

        -- Lines claimed by a block token; the heading/list pass skips these so it does not
        -- recolor e.g. a power-roll tier line or quoted text.
        local blockLines = {}
        local function ClaimLines(firstLine, lastLine)
            for li = firstLine, math.min(lastLine or firstLine, #lines) do
                blockLines[li] = true
            end
        end

        local function LineRangeBounds(firstLine, lastLine)
            lastLine = math.min(lastLine or firstLine, #lines)
            if lineOffsets[firstLine] == nil or lines[lastLine] == nil then return nil end
            return lineOffsets[firstLine], lineOffsets[lastLine] + #lines[lastLine] - 1
        end

        -- Per-line moving cursor so repeated identical inline literals map in document order.
        local lineFindCursor = {}
        local function FindInLine(lineIdx, literal)
            local line = lines[lineIdx]
            if line == nil or literal == nil or literal == "" then return nil end
            local s, e = string.find(line, literal, lineFindCursor[lineIdx] or 1, true)
            if s == nil then return nil end
            lineFindCursor[lineIdx] = e + 1
            local base = lineOffsets[lineIdx]
            return base + s - 1, base + e - 1
        end

        -- 1) Structural + inline tokens, straight from the journal's own tokenizer.
        local tokens = BreakdownRichTags(text, nil, { player = false, trackPositions = true })
        for _, token in ipairs(tokens) do
            local ty = token.type
            if ty == "tag" and token.srcLine ~= nil then
                -- [[inner]] (text is the inner content), or a [ ]/[x] checkbox whose text
                -- already includes the brackets. Try the bracketed form first.
                local from, to = FindInLine(token.srcLine, "[[" .. token.text .. "]]")
                if from == nil then
                    from, to = FindInLine(token.srcLine, token.text)
                end
                AddSpan(from, to, g_journalSyntaxColors.tag)
            elseif ty == "embed" and token.srcLine ~= nil then
                local from, to = FindInLine(token.srcLine, token.text)
                AddSpan(from, to, g_journalSyntaxColors.embed)
            elseif ty == "justification" and token.srcLine ~= nil then
                local from, to = FindInLine(token.srcLine, token.text)
                AddSpan(from, to, g_journalSyntaxColors.justify)
            elseif token.srcLine ~= nil then
                local color = nil
                if ty == "blockquote" then color = g_journalSyntaxColors.blockquote
                elseif ty == "divider" then color = g_journalSyntaxColors.divider
                elseif ty == "collapse_node" then color = g_journalSyntaxColors.collapse
                elseif ty == "styleblock" then color = g_journalSyntaxColors.styleblock
                elseif ty == "power_roll" or ty == "rollable_table" or ty == "row" then
                    color = g_journalSyntaxColors.table
                end
                if color ~= nil then
                    local from, to = LineRangeBounds(token.srcLine, token.srcLineEnd)
                    AddSpan(from, to, color)
                    ClaimLines(token.srcLine, token.srcLineEnd)
                end
            end
        end

        -- 2) Headings and list markers (emitted as plain text by BreakdownRichTags). Recognize
        -- them with the same patterns ApplySkinToText uses on the render side.
        for i = 1, #lines do
            if not blockLines[i] then
                local line = lines[i]
                local base = lineOffsets[i]
                local hashes = string.match(line, "^(#+) ")
                local bmarker = string.match(line, "^([%-%*]) ")
                local onum = string.match(line, "^(%d+%.) ")
                if hashes ~= nil and #hashes >= 1 and #hashes <= 5 then
                    AddSpan(base, base + #line - 1, g_journalSyntaxColors.heading)
                elseif bmarker ~= nil then
                    AddSpan(base, base + #bmarker - 1, g_journalSyntaxColors.listMarker)
                elseif onum ~= nil then
                    AddSpan(base, base + #onum - 1, g_journalSyntaxColors.listMarker)
                end
            end
        end

        -- 3) Single-bracket links. [Label] is the journal's shorthand link form -- it is stored as
        -- [Label] and expanded to [[//link "Label"|Label]] at render time, so BreakdownRichTags
        -- never tokenizes it. Color the [Label] spans like other links. A match that is really the
        -- inner [..] of a [[..]] tag starts one character later than the tag's own span, so the
        -- earlier-starting tag span wins in the C# recolor (and both are the same color anyway).
        for i = 1, #lines do
            local line = lines[i]
            local base = lineOffsets[i]
            local init = 1
            while true do
                local s, e = string.find(line, "%[([^%[%]]+)%]", init)
                if s == nil then break end
                AddSpan(base + s - 1, base + e - 1, g_journalSyntaxColors.tag)
                init = e + 1
            end
        end

        -- All offsets above are Lua BYTE positions, but gui.TextEditor:SetColorSpans indexes by
        -- character (the C# side uses characterInfo[i].index, i.e. UTF-16 char indices). Multi-byte
        -- UTF-8 -- curly quotes/apostrophes, accents, em dashes -- makes the two diverge, so a token
        -- after such a character is colored too far to the right. Translate every span endpoint from
        -- a byte position to a 1-based character index. ASCII text needs no work (byte == char);
        -- invalid UTF-8 (utf8.len returns nil) falls back to byte offsets.
        local charLen = utf8.len(text)
        if charLen ~= nil and charLen ~= #text and #spans > 0 then
            -- byteToChar[b] = 1-based character index of the character that byte b belongs to.
            local starts = {}
            local ci = 0
            for p in utf8.codes(text) do
                ci = ci + 1
                starts[ci] = p
            end
            local byteToChar = {}
            local total = #text
            for k = 1, ci do
                local lastByte = (k < ci) and (starts[k + 1] - 1) or total
                for b = starts[k], lastByte do
                    byteToChar[b] = k
                end
            end
            for _, sp in ipairs(spans) do
                sp.from = byteToChar[sp.from] or sp.from
                sp.to = byteToChar[sp.to] or sp.to
            end
        end

        return spans
    end

    editInput = gui.TextEditor {
        id = "editorPanel",
        classes = { "monospace" },
        width = "100%",
        height = "100%",
        halign = "center",
        fontSize = CustomDocument.ScaleFontSize(16),
        multiline = true,
        textAlignment = "topleft",
        text = self:GetTextContent(),
        verticalScrollbar = true,
        selectAllOnFocus = false,
        characterLimit = CustomDocument.MaxLength,

        thinkTime = 0.2,
        editlag = 0.3,
        create = function(element)
            element:SetColorSpans(ComputeMarkdownColorSpans(element.text))
        end,
        edit = function(element)
            if resultPanel ~= nil then
                resultPanel:FireEventTree("editDocument", element.text)
            end
            charactersUsedLabel:FireEvent("refreshLength", element.text)
            UpdateAutocomplete(element)
            element:SetColorSpans(ComputeMarkdownColorSpans(element.text))
            -- The preview just re-rendered, so block heights may have changed even if the
            -- caret line did not (e.g. forward-delete). Force the next think to re-sync.
            lastSyncedCaret = -1
        end,
        refreshDocument = function(element)
            element.text = self:GetTextContent()
        end,
        needsave = function(element, result)
            if self:GetTextContent() ~= element.text or self:try_get("_tmp_styleDirty") == true then
                result.save = true
            end
        end,
        savedoc = function(element)
            self:SetTextContent(element.text)
            element.text = self:GetTextContent()
            self._tmp_styleDirty = nil
        end,

        checkChanges = function(element, baseDoc)
            resultPanel:SetClassTree("changes", element.text ~= baseDoc:GetTextContent() or self:try_get("_tmp_styleDirty") == true)
        end,

        caretReady = function(element)
            UpdateAutocomplete(element)
            SyncPreviewScroll(element, previewPanel, previewBody)
        end,

        find = function(element)
            OpenFind()
        end,

        think = function(element)
            if #autocompleteState.results > 0 then
                local searchText, bracketPos, contextType = FindLinkContext(element.text, element.caretPosition)
                if searchText == nil or ((contextType == "link" or contextType == "linkTarget") and #searchText < 1) then
                    DismissAutocomplete(element)
                end
            else
                UpdateLinkInfo(element)
            end
            SyncPreviewScroll(element, previewPanel, previewBody)
        end,
    }

    local previewDoc = MarkdownDocument.new{
        content = self:GetTextContent(),
        annotations = self.annotations,
        styleSheetId = self.styleSheetId or false,
    }

    -- Hoisted out of the panel child-list so SyncPreviewScroll can read its rendered blocks
    -- (data.srcLine + renderedHeight) to map the caret line to a scroll position.
    previewBody = previewDoc:DisplayPanel{
        width = "100%",
        height = "auto",
    }

    previewPanel = gui.Panel{
        classes = showPreviewSetting:Get() and {} or { "collapsed" },
        width = "50%-16",
        height = "100%",
        valign = "top",
        vscroll = true,
        flow = "vertical",
        borderBox = true,
        lmargin = 8,
        hpad = 16,
        vpad = 16,

        editDocument = function(element, content)
            previewDoc:SetTextContent(content or "")
            element:FireEventTree("refreshDocument", previewDoc)
        end,

        previewBody,

        gui.Panel{
            classes = { "previewClickGuard" },
            width = "100%",
            height = "100%",
            floating = true,
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            click = function() end,
            rightClick = function() end,
        },
    }

    local m_richPanels = {}

    local annotationsPanel = gui.Panel {
        width = "98%",
        height = "auto",
        maxHeight = 200,
        vscroll = true,
        vmargin = 8,
        flow = "horizontal",
        wrap = true,

        refreshDocument = function(element, doc)
            if doc ~= nil then
                element:FireEvent("editDocument", doc:GetTextContent())
            end
        end,

        editDocument = function(element, content)
            local tagsSeen = {}

            local newRichPanels = {}
            local children = {}
            local tokens = BreakdownRichTags(content)
            for i, token in ipairs(tokens) do
                if token.type == "tag" then
                    local text, suffix = token.text:match("^(.-):(.*)$")
                    if suffix == nil then
                        text = token.text
                    end

                    local richTagInfo = MarkdownDocument.RichTagRegistry[string.lower(text)]

                    if richTagInfo ~= nil and richTagInfo.hasEdit then
                        local candidate = token.text
                        local index = 1
                        while tagsSeen[candidate] do
                            candidate = token.text .. '-' .. index
                            index = index + 1
                        end

                        tagsSeen[candidate] = true

                        local richTag = self.annotations[candidate]
                        --patch over any possible bugs where the saved annotation is not a proper table.
                        if richTag ~= nil and getmetatable(richTag) == nil then
                            richTag = nil
                            self.annotations[candidate] = nil
                        end

                        if richTag == nil then
                            richTag = richTagInfo.Create()
                            richTag.identifier = suffix or false
                            self.annotations[candidate] = richTag
                        end

                        if richTagInfo.hasEdit ~= "hidden" then
                            local richPanel = m_richPanels[candidate] or gui.Panel {
                                width = "auto",
                                height = 120,
                                flow = "vertical",
                                halign = "left",
                                valign = "top",
                                hmargin = 4,
                                gui.Panel {
                                    width = "auto",
                                    height = 96,
                                    richTag:CreateEditor(),
                                },
                                gui.Label {
                                    text = candidate,
                                    fontSize = CustomDocument.ScaleFontSize(12),
                                    textAlignment = "center",
                                    width = 96,
                                    height = "auto",
                                    halign = "center",
                                    valign = "center",
                                },
                            }

                            newRichPanels[candidate] = richPanel
                            children[#children + 1] = richPanel

                            richPanel:FireEventTree("refreshEditor", richTag)
                        end
                    end
                end
            end

            m_richPanels = newRichPanels
            element.children = children
        end,
    }

    local function ToolbarButton(label, fontSize, width, handler)
        return gui.Button{
            text = label,
            width = width or 28,
            height = 24,
            fontSize = fontSize or 14,
            valign = "center",
            press = handler,
        }
    end

    local headingOptions = {
        { id = "",       text = "Heading" },
        { id = "# ",     text = "H1" },
        { id = "## ",    text = "H2" },
        { id = "### ",   text = "H3" },
        { id = "#### ",  text = "H4" },
        { id = "##### ", text = "H5" },
    }

    local spoilerOptions = {
        { id = "",  text = "Spoiler" },
        { id = "h", text = "Hidden" },
        { id = "r", text = "Redacted" },
        { id = "v", text = "Revealed" },
    }

    local mediaTags  = { "image", "sound", "ability", "scene",
                         "encounter", "party", "follower" }
    local widgetTags = { "dice", "bar", "counter", "checkbox", "macro",
                         "reminder", "timer", "setting" }

    local mediaOptions = { { id = "", text = "Insert Media" } }
    for _, t in ipairs(mediaTags) do
        mediaOptions[#mediaOptions + 1] = { id = t, text = t }
    end

    local widgetOptions = { { id = "", text = "Insert Widget" } }
    for _, t in ipairs(widgetTags) do
        widgetOptions[#widgetOptions + 1] = { id = t, text = t }
    end

    local toolbar = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        valign = "top",
        halign = "left",
        borderBox = true,
        hpad = 4,
        bmargin = 4,

        ToolbarButton("B", 16, 28, WrapHandler("**", "**")),
        ToolbarButton("I", 16, 28, WrapHandler("*", "*")),
        ToolbarButton("U", 16, 28, WrapHandler("__", "__")),
        ToolbarButton("S", 16, 28, WrapHandler("~~", "~~")),

        ToolbarButton("Color", 12, 44,
            WrapHandler("<color=red>", "</color>")),

        gui.Dropdown{
            width = 90, height = 24, idChosen = "",
            options = spoilerOptions,
            change = function(element)
                local id = element.idChosen
                if id == "h" then
                    WrapHandler("{", "}")()
                elseif id == "r" then
                    WrapHandler("{#", "}")()
                elseif id == "v" then
                    WrapHandler("{!", "}")()
                end
                element.idChosen = ""
            end,
        },

        gui.Dropdown{
            width = 80, height = 24, idChosen = "",
            options = headingOptions,
            change = function(element)
                if element.idChosen ~= "" then
                    LineHandler(element.idChosen)()
                    element.idChosen = ""
                end
            end,
        },

        ToolbarButton("List",    12, 44, LineHandler("* ")),
        ToolbarButton("Divider", 12, 56, InsertHandler("\n---\n", 5)),
        ToolbarButton("Link",    12, 40, InsertHandler("[]", 1)),

        ToolbarButton("Draw Steel!", 12, 80,
            InsertHandler('[[//link "Draw Steel!"|Draw Steel!]]')),

        gui.Dropdown{
            width = 110, height = 24, idChosen = "",
            options = mediaOptions,
            change = function(element)
                if element.idChosen ~= "" then
                    RichTagHandler(element.idChosen)()
                    element.idChosen = ""
                end
            end,
        },

        gui.Dropdown{
            width = 110, height = 24, idChosen = "",
            options = widgetOptions,
            change = function(element)
                if element.idChosen ~= "" then
                    RichTagHandler(element.idChosen)()
                    element.idChosen = ""
                end
            end,
        },

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
                    self._tmp_styleDirty = true
                    if resultPanel ~= nil then
                        resultPanel:SetClassTree("changes", true)
                    end
                end,
            },
        },
    }

    -- Find bar: a small overlay at the top of the editor. The search field is a plain
    -- gui.Input; all matching/highlighting/scrolling is driven through the TextEditor API
    -- (Find / FindNext / FindPrev / ClearFind), which selects + scrolls the match in the
    -- editor. resetOnDeActivation is set false while open so the match stays highlighted
    -- even though the search field holds focus.
    findCountLabel = gui.Label{
        width = "auto",
        height = "auto",
        valign = "center",
        hmargin = 8,
        fontSize = 12,
        color = "#bbbbbb",
        text = "",
    }

    findInput = gui.Input{
        width = "45%",
        height = 22,
        valign = "center",
        fontSize = 14,
        placeholderText = "Find",
        text = "",
        lineType = "SingleLine",
        edit = function(element)
            editInput:Find(element.text, false)
            UpdateFindUI()
        end,
        submit = function(element)
            editInput:FindNext()
            UpdateFindUI()
        end,
    }

    UpdateFindUI = function()
        local total = editInput:FindCount()
        if total <= 0 then
            findCountLabel.text = (findInput.text ~= "" and "No results") or ""
        else
            findCountLabel.text = string.format("%d / %d", editInput:FindCurrent(), total)
        end
    end

    OpenFind = function()
        findBar:SetClass("collapsed", false)
        findBar.captureEscape = true
        -- Keep the match highlighted while the search field has focus.
        editInput.resetOnDeActivation = false
        findInput.hasInputFocus = true
        if findInput.text ~= "" then
            editInput:Find(findInput.text, false)
        end
        UpdateFindUI()
    end

    CloseFind = function()
        findBar:SetClass("collapsed", true)
        findBar.captureEscape = false
        editInput:ClearFind()
        editInput.resetOnDeActivation = true
        editInput.hasInputFocus = true
    end

    findBar = gui.Panel{
        classes = { "collapsed" },
        floating = true,
        width = "100%-8",
        height = 30,
        halign = "center",
        valign = "top",
        tmargin = 4,
        flow = "horizontal",
        bgimage = "panels/square.png",
        bgcolor = "#1a1a1af0",
        hpad = 6,
        vpad = 4,
        borderBox = true,

        -- Escape closes the find bar (and refocuses the editor) rather than bubbling to the
        -- journal's EXIT_DIALOG handler. DMHUB_POPUP outranks EXIT_DIALOG, and captureEscape
        -- is toggled with the bar's open state so it only intercepts Escape while open.
        captureEscape = false,
        escapePriority = EscapePriority.DMHUB_POPUP,
        escape = function(element)
            CloseFind()
        end,

        findInput,
        findCountLabel,
        gui.Button{
            text = "Prev", width = 46, height = 20, fontSize = 11, hmargin = 2, valign = "center",
            press = function() editInput:FindPrev() UpdateFindUI() findInput.hasInputFocus = true end,
        },
        gui.Button{
            text = "Next", width = 46, height = 20, fontSize = 11, hmargin = 2, valign = "center",
            press = function() editInput:FindNext() UpdateFindUI() findInput.hasInputFocus = true end,
        },
        gui.Button{
            text = "Close", width = 50, height = 20, fontSize = 11, hmargin = 2, valign = "center",
            press = function() CloseFind() end,
        },
    }

    local editorColumn
    editorColumn = gui.Panel{
        width = showPreviewSetting:Get() and "50%" or "100%",
        height = "100%",
        borderBox = true,
        editInput,
        findBar,
    }

    resultPanel = gui.Panel {
        classes = { "collapsed" },
        width = "100%",
        height = "100%-0",
        valign = "top",
        tmargin = 2,
        flow = "vertical",
        refreshDocument = function(element, doc)
            self = doc or self
        end,

        toolbar,

        gui.Panel{
            width = "98%",
            height = "100% available",
            halign = "center",
            valign = "top",
            flow = "horizontal",
            editorColumn,
            previewPanel,
        },
        gui.Panel {
            width = "100%",
            height = 16,
            tmargin = 12,
            markdownReferenceLabel,
            gui.Button{
                text = "Preview",
                width = 70,
                height = 16,
                fontSize = 12,
                halign = "right",
                rmargin = 168,
                classes = showPreviewSetting:Get() and { "selected" } or {},
                press = function(element)
                    local newState = not element:HasClass("selected")
                    element:SetClass("selected", newState)
                    showPreviewSetting:Set(newState)
                    previewPanel:SetClass("collapsed", not newState)
                    editorColumn.selfStyle.width = newState and "50%" or "100%"
                    if newState then
                        lastSyncedCaret = -1
                        previewPanel:FireEvent("editDocument",
                            editInput.text or self:GetTextContent())
                    end
                end,
            },
            charactersUsedLabel,
            savePanel,
        },
        annotationsPanel,
    }

    resultPanel:FireEventTree("editDocument", self:GetTextContent())

    return resultPanel
end

function MarkdownDocument:MatchesSearch(search)
    if string.find(string.lower(self:GetTextContent()), search, 1, true) then
        return true
    end

    return false
end

CustomDocument.Register {
    id = "markdown",
    text = "New Text Document",
    create = function()
        return MarkdownDocument.new {
            content = "",
            annotations = {},
        }
    end,
}

local g_markdownSamples = {
    "# Title", "*italics*", "**bold**", "__underline__", "~~strike~~",
    [[* point 1
* point 2
* point 3]],
    "{hidden from players}",
    "{#redacted from players}",
    "{!revealed to players}",

    "Before divider\n---\nAfter divider",

    [[|Disarm the Scythe Trap: Agility Test
|The hero triggers the trap.
|The hero fails to disarm the trap, but doesn't trigger it.
|The hero disarms the trap.]],

    '<color=red>Red Text</color>',
    "Interest: [[##--]]",

    "[[image]]",
    "[[sound]]",

}

MarkdownReferenceTooltip = function()
    local annotations = {
        image = RichImage.new {
            image = "98fa8fcd-5a62-4736-924d-0753b2900b2e",
            uiscale = 0.15,
        },
        sound = RichAudio.new{
            sound = "f6bc62cc-7225-48cf-b719-b86280ea198d",
        },
    }

    local resultPanel

    local children = {}

    children[#children + 1] = gui.TableRow {
        classes = {"markdownRefRow", "bordered"},
        width = "100%",
        height = "auto",

        gui.Panel {
            width = "50%",
            height = "auto",
            pad = 6,
            gui.Label {
                classes = { "bold" },
                fontSize = CustomDocument.ScaleFontSize(24),
                width = "100%",
                height = "auto",
                text = "You Type",
            },
        },

        gui.Panel {
            width = "50%",
            height = "auto",
            pad = 6,
            gui.Label {
                classes = { "bold" },
                fontSize = CustomDocument.ScaleFontSize(24),
                width = "100%",
                height = "auto",
                text = "You See",
            },
        },
    }

    for _, sample in ipairs(g_markdownSamples) do
        local doc = MarkdownDocument.new {
            content = sample,
            annotations = annotations,
        }
        children[#children + 1] = gui.TableRow {
            classes = {"markdownRefRow", "bordered"},
            width = "100%",
            height = "auto",
            gui.Panel {
                width = "50%",
                height = "auto",
                pad = 6,
                gui.Label {
                    classes = { "monospace" },
                    width = "100%",
                    height = "auto",
                    text = string.format("<noparse>%s</noparse>", sample),
                    fontSize = CustomDocument.ScaleFontSize(14),
                    textAlignment = "topleft",
                },
            },
            gui.Panel {
                width = "50%",
                height = "auto",
                pad = 6,
                doc:DisplayPanel {
                    width = "100%-24",
                    vscroll = false,
                    height = "auto",
                },
            }
        }
    end

    local t = gui.Table {
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",
        children = children,
    }

    local panel = gui.Panel {
        width = "100%",
        height = "auto",
        flow = "horizontal",
        t,
    }

    resultPanel = gui.TooltipFrame(panel, {
        halign = "right",
        width = 1100,
        height = "auto",
    })

    resultPanel:MakeNonInteractiveRecursive()

    return resultPanel
end
