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
    --backtick code spans. The engine default is <mspace=2em>, which puts
    --every glyph on a huge fixed advance and renders code as
    --s p r e a d  o u t letters. Any mspace value is still a fixed grid,
    --so we drop monospace emulation entirely: code reads as a soft gold
    --tint at normal spacing. (True monospace needs a mono font face at
    --the engine level - flagged upstream.)
    ["`"] = "<color=#c8a45aCC>",
    ["/`"] = "</color>",
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

-- Style the visible text of links so they stand out from body copy. Opt-in:
-- only fires when the skin sets link.color, so the default skin and any sheet
-- that leaves `link` unset keep the engine's native link look (backward-safe).
-- The engine still parses and resolves the link target; we only wrap the display
-- span inside the brackets, leaving the (target) and click/hover behaviour intact.
-- Handles [display](target) and the bare [Label] shorthand. Injected markup
-- contains no brackets, so the bare-bracket pass skips spans the first pass
-- already styled (detected via the embedded <color= tag). An image (![alt](url))
-- is left alone so its alt text is not turned into a link.
local function ColorizeLinks(content, link)
    if type(content) ~= "string" or content == "" then return content end
    link = link or {}
    local color = SkinColor(link.color)
    if color == nil then return content end
    local open = string.format("<color=%s>", color)
    local close = "</color>"
    if link.underline ~= false then
        open = open .. "<u>"
        close = "</u>" .. close
    end
    local function wrap(inner)
        if inner == "" or string.find(inner, "<color=", 1, true) ~= nil then
            return nil
        end
        return open .. inner .. close
    end
    -- [display](target): style display, keep target. Skip image syntax (![..](..)).
    content = content:gsub("(!?)(%b[])(%b())", function(bang, disp, target)
        if bang == "!" then return nil end
        local styled = wrap(disp:sub(2, -2))
        if styled == nil then return nil end
        return "[" .. styled .. "]" .. target
    end)
    -- bare [Label]: remaining balanced single-bracket spans. The (!?) prefix
    -- keeps image alt text ([..] right after a !) from being matched on its own.
    content = content:gsub("(!?)(%b[])", function(bang, disp)
        if bang == "!" then return nil end
        local styled = wrap(disp:sub(2, -2))
        if styled == nil then return nil end
        return "[" .. styled .. "]"
    end)
    return content
end

-- Test hook.
MarkdownDocument.__ColorizeLinks = ColorizeLinks

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
    local linkSkin = base.link
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
            out[#out + 1] = SkinBulletMarkup(base.bullet, bmarker, ColorizeLinks(bContent, linkSkin), bodyColor, bodyFont)
        elseif onum ~= nil then
            out[#out + 1] = SkinOrderedMarkup(base.ordered, onum, ColorizeLinks(oContent, linkSkin), bodyColor, bodyFont)
        elseif line == "" then
            local gap = SkinGapLine(bodyPS)
            out[#out + 1] = gap or SkinBodyMarkup(base.body, line)
        else
            out[#out + 1] = SkinBodyMarkup(base.body, ColorizeLinks(line, linkSkin))
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

-- Rich-tag annotations are stored in doc.annotations keyed by the tag text (e.g.
-- "encounter:Boss"), and that key is serialized verbatim as a cloud/Firebase key.
-- Firebase rejects keys that are empty or contain any of . $ # [ ] / -- and a
-- single bad key fails the WHOLE module/document upload. [ and ] can't occur in
-- tag text (they delimit the tag), so the practical set to reject is . $ # / .
-- We guard at annotation-creation time so a bad key never enters doc.annotations;
-- the tag still renders, it just doesn't persist a stored annotation.
function MarkdownDocument.IsLegalAnnotationKey(key)
    if type(key) ~= "string" or key == "" then
        return false
    end
    return key:find("[%.%$#%[%]/]") == nil
end

--Page-aware widget palette: rich-tag widgets call this from refreshTag so
--their chrome matches the host sheet's page instead of the app theme.
--Opt-in by the sheet: returns nil unless the resolved stylesheet defines
--its own page background (page.bgcolor), so default-skin documents keep
--the engine look untouched. Widget-specific semantic colors (difficulty
--tiers etc.) are NOT part of the palette and stay as authored.
--Mirrors the precedence RichCheckbox established: the page color is the
--fill, the sheet's bullet color (its established accent, falling back to
--link then body) is the accent, and the body color is the ink.
function MarkdownDocument.PageSkinPalette(doc)
    if doc == nil then return nil end
    local ok, resolved = pcall(function() return doc:GetResolvedStylesheet() end)
    if not ok or resolved == nil then return nil end
    local base = resolved.base or {}
    local page = SkinColor((base.page or {}).bgcolor)
    if page == nil then return nil end

    local ink = SkinColor((base.body or {}).color) or "#241f17"
    local accent = SkinColor((base.bullet or {}).color)
        or SkinColor((base.link or {}).color)
        or ink
    local link = SkinColor((base.link or {}).color) or accent

    --derive translucent tints from the ink; only #rrggbb colors can take
    --an alpha suffix, anything else is used as-is.
    local function tint(c, a)
        if type(c) == "string" and c:match("^#%x%x%x%x%x%x$") then
            return c .. a
        end
        return c
    end

    return {
        page = page,               --widget fill: sits on the page
        ink = ink,                 --primary text
        muted = tint(ink, "aa"),   --captions, secondary text
        border = tint(ink, "55"),  --widget borders
        hairline = tint(ink, "26"),--dividers
        wash = tint(ink, "14"),    --hover / chip fills
        accent = accent,
        link = link,
    }
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
    -- textLastLine remembers the LAST line that fed visible content, so multi-line text
    -- runs carry their full srcLine..srcLineEnd range; the live editor's block
    -- partitioner (PartitionTokensIntoBlocks) relies on that range being complete.
    -- Separator newlines appended between lines deliberately update neither, so a
    -- construct on a following line is never claimed by the text flushed before it.
    local currentLine = 1
    local textStartLine = nil
    local textLastLine = nil

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
            -- Accumulator runs anchor at textStartLine and extend to textLastLine; an
            -- explicitly-passed string (e.g. a rich line's prefix) belongs to the line
            -- being parsed now.
            if fromAccumulator then
                StampLine(result[#result], textStartLine, textLastLine)
            else
                StampLine(result[#result], currentLine)
            end
        end
        if fromAccumulator then
            textStartLine = nil
            textLastLine = nil
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

            --Optional 4th |-line is the "Critical" outcome (natural 19-20). Its mere presence
            --upgrades this power roll to four tiers; existing 3-line rolls are unaffected.
            local hasCritical = false
            if hasMatch then
                local critMatch = lines[i + 4] and
                regex.MatchGroups(lines[i + 4], "^" .. currentIndent .. "\\|(?<text>[^|]*)$")
                if critMatch ~= nil then
                    tiers[#tiers + 1] = critMatch.text
                    hasCritical = true
                end
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
                StampLine(result[#result], i, i + cond(hasCritical, 4, 3))
                skipLines = cond(hasCritical, 4, 3)
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

        --title charset includes common punctuation: a title like
        --"CUE - Reinforcement, round 2" must still form a card; before
        --commas were allowed, such lines silently fell through and
        --rendered as literal "+ ..." body text.
        local collapseNodeMatch = regex.MatchGroups(str, "^\\+ (?<title>['\"a-zA-Z0-9-_,.:()!? ]+)$")
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
                if str ~= "" then textLastLine = currentLine end
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
                -- The brace (and any spoiler link injected above) is visible content:
                -- anchor the accumulator run here if it is not already anchored, so
                -- spoiler-leading text runs carry source ranges too.
                if textStartLine == nil then textStartLine = currentLine end
                textLastLine = currentLine
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
                --measure the tag's span against str, NOT line: inside a collapse
                --card the body indent has been stripped from str, so #line
                --over-counts by the indent width and PatchToken would then
                --replace that many extra characters AFTER the tag (a tick on
                --"  [ ] - text" ate the "- "; tick+untick then ate the ". " at
                --the label boundary too).
                local len = #str - (#match.prefix + #match.suffix)

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

--Token types that continue a table when they appear on the line directly
--after the current block (a table is one edit block even though each source
--row emits its own row token).
local g_tableBlockTokenTypes = {
    rollable_table = true,
    row = true,
    cell = true,
    end_row = true,
}

--Groups a trackPositions token stream into top-level edit blocks for the
--live editor. Each block is a contiguous source line range (srcLine ..
--srcLineEnd over the tokens it holds) that renders and edits as one unit:
--  - tokens that share a source line always share a block.
--  - table tokens on directly adjacent lines merge, so a whole table
--    (including a rollable-table header) is a single block.
--  - collapse wrappers claim every token until their matching end token,
--    so a collapse node and its children form one block.
--  - unstamped tokens (cell/end_row and cell-inner tokens, which the
--    tokenizer deliberately leaves unstamped, plus whitespace-only text)
--    attach to the currently open block and never extend its range; they
--    never update the table-continuation type either, so a row's inner
--    tokens do not break row-to-row merging.
--  - blank lines and lines that emitted no tokens (false ??? conditional
--    regions) belong to no block; the caller preserves them verbatim when
--    splicing an edited block back into the document.
--Returns an array of { lineStart, lineEnd, tokens = {...} } in source order.
function MarkdownDocument.PartitionTokensIntoBlocks(tokens)
    local blocks = {}
    local current = nil
    local wrapperDepth = 0 --depth of open collapse wrappers.

    for _, token in ipairs(tokens) do
        if token.srcLine == nil then
            if current ~= nil then
                current.tokens[#current.tokens + 1] = token
            end
        else
            local joinsCurrent = false
            if current ~= nil then
                if wrapperDepth > 0 then
                    joinsCurrent = true
                elseif token.srcLine <= current.lineEnd then
                    --shares a line with the block.
                    joinsCurrent = true
                elseif token.srcLine == current.lineEnd + 1
                       and g_tableBlockTokenTypes[token.type]
                       and g_tableBlockTokenTypes[current.lastType] then
                    --table continuation on the very next line.
                    joinsCurrent = true
                end
            end

            if not joinsCurrent then
                current = {
                    lineStart = token.srcLine,
                    lineEnd = token.srcLineEnd or token.srcLine,
                    tokens = {},
                }
                blocks[#blocks + 1] = current
            end

            current.tokens[#current.tokens + 1] = token
            local tokenEnd = token.srcLineEnd or token.srcLine
            if tokenEnd > current.lineEnd then
                current.lineEnd = tokenEnd
            end
            current.lastType = token.type
        end

        if token.type == "collapse_node" then
            wrapperDepth = wrapperDepth + 1
        elseif token.type == "end_collapse_node" then
            if wrapperDepth > 0 then
                wrapperDepth = wrapperDepth - 1
            end
        end
    end

    for _, block in ipairs(blocks) do
        block.lastType = nil
    end

    return blocks
end

--Dev-only verification for the live-edit line-range work: tokenize with
--trackPositions and check the invariants the block partitioner relies on:
--  1. every stamped range is ordered and within 1..#lines.
--  2. stamped range starts never move backwards across the token stream.
--  3. every non-blank source line is covered by a token range or sits
--     inside a table row. Uncovered non-blank lines are reported; false ???
--     conditional regions emit no tokens and are expected to appear there.
--  4. unstamped text tokens outside table rows carry only whitespace.
--  5. blocks from PartitionTokensIntoBlocks form strictly ascending,
--     non-overlapping ranges.
--Run from the dev console on a document's content, e.g.:
--  MarkdownDocument.DebugCheckLineRanges(doc:GetTextContent())
--Returns { errors, uncovered, blocks, tokenCount } and prints a summary.
function MarkdownDocument.DebugCheckLineRanges(content)
    local tokens = BreakdownRichTags(content, nil, { trackPositions = true })

    local normalized = content:gsub("\v", "\n"):gsub("\r", "")
    local lines = string.split_allow_duplicates(normalized, "\n")

    local errors = {}
    local covered = {}
    local maxStart = 0
    local inRow = false

    for index, token in ipairs(tokens) do
        if token.type == "row" then
            inRow = true
        elseif token.type == "end_row" then
            inRow = false
        end

        if token.srcLine ~= nil then
            local srcEnd = token.srcLineEnd or token.srcLine
            if token.srcLine > srcEnd or token.srcLine < 1 or srcEnd > #lines then
                errors[#errors + 1] = string.format("token %d (%s): bad range %s..%s (doc has %d lines)",
                    index, token.type, tostring(token.srcLine), tostring(srcEnd), #lines)
            else
                if token.srcLine < maxStart then
                    errors[#errors + 1] = string.format("token %d (%s): range start %d is before an earlier token's start %d",
                        index, token.type, token.srcLine, maxStart)
                end
                maxStart = math.max(maxStart, token.srcLine)
                for j = token.srcLine, srcEnd do
                    covered[j] = true
                end
            end
        elseif token.type == "text" and (not inRow)
               and trim((token.text or ""):gsub("\n", "")) ~= "" then
            errors[#errors + 1] = string.format("token %d: unstamped text token outside a table row with content %q",
                index, token.text)
        end
    end

    local uncovered = {}
    for j, line in ipairs(lines) do
        if (not covered[j]) and trim(line) ~= "" then
            uncovered[#uncovered + 1] = j
        end
    end

    local blocks = MarkdownDocument.PartitionTokensIntoBlocks(tokens)
    local prevEnd = 0
    for index, block in ipairs(blocks) do
        if block.lineStart <= prevEnd then
            errors[#errors + 1] = string.format("block %d: range %d..%d overlaps previous block ending at %d",
                index, block.lineStart, block.lineEnd, prevEnd)
        end
        if block.lineEnd < block.lineStart then
            errors[#errors + 1] = string.format("block %d: inverted range %d..%d",
                index, block.lineStart, block.lineEnd)
        end
        prevEnd = math.max(prevEnd, block.lineEnd)
    end

    print(string.format("DebugCheckLineRanges: %d tokens, %d blocks over %d lines; %d errors; %d uncovered non-blank lines",
        #tokens, #blocks, #lines, #errors, #uncovered))
    for _, err in ipairs(errors) do
        print("  ERROR: " .. err)
    end
    for _, j in ipairs(uncovered) do
        print(string.format("  UNCOVERED line %d: %s", j, lines[j]))
    end

    return { errors = errors, uncovered = uncovered, blocks = blocks, tokenCount = #tokens }
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
    --Tier 4 is the optional "Critical" outcome. DrawSteelGlyphs has no crit glyph
    --(only !/@/# for tiers 1-3), so it gets a plain "Critical" text label instead.
    local iconLabel
    if n == 4 then
        iconLabel = gui.Label {
            width = CustomDocument.ScaleFontSize(54),
            height = CustomDocument.ScaleFontSize(22),
            textAlignment = "center",
            text = "Critical",
            fontSize = CustomDocument.ScaleFontSize(10),
            valign = "top",
            bgimage = true,
            bgcolor = "clear",
            fontFace = "book",
            borderWidth = 1,
            borderColor = "white",
        }
    else
        iconLabel = gui.Label {
            width = CustomDocument.ScaleFontSize(60),
            height = CustomDocument.ScaleFontSize(30),
            textAlignment = "center",
            fontFace = "DrawSteelGlyphs",
            text = cond(n == 1, '!', cond(n == 2, '@', '#')),
            fontSize = CustomDocument.ScaleFontSize(36),
            valign = "top",
        }
    end

    return gui.Panel {
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "horizontal",
        --Collapse rows whose tier text is absent. Tiers 1-3 are always present, so
        --this only ever hides the optional 4th "Critical" row.
        refreshPowerRoll = function(element, info)
            element:SetClass("collapsed", info.tiers[n] == nil)
        end,
        iconLabel,

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
        TierRoll(4),
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

--------------------------------------------------------------------------------
-- Glossary hints: rules terms in rendered documents get the design
-- system's broken-underline treatment (solid on hover/Bold) and act as
-- glossary: link regions. Hovering (with dwell) shows the definition
-- card; clicking pins it. Design brief: glossary-hints-brief.md (locked
-- 2026-07-12; visual updated to the broken underline 2026-07-13).
--
-- The pass runs at label-text assembly time inside RenderMarkdownTokens'
-- MakeTextLabel path only (never a whole-tree walk), display mode only,
-- top-level documents only (no embeds), gated by ctx.render.glossaryHints
-- which DisplayPanel sets from the user setting and the per-view mute.
--------------------------------------------------------------------------------

--one-time teach toast; latched only by explicit dismissal. Turning the
--feature off re-arms it so turning it back on re-teaches.
local g_glossaryToastSeen = setting{
    id = "glossaryhints:toastseen",
    default = false,
    storage = "preference",
}

--Off / Subtle / Bold. Subtle (broken underline) is the default; Bold is
--a solid underline.
local g_glossaryHintsSetting
g_glossaryHintsSetting = setting{
    id = "glossaryhints",
    description = "Glossary hints in documents",
    help = "Softly underline rules terms in documents. Hover for the definition, click to pin it.",
    storage = "preference",
    section = "general",
    editor = "dropdown",
    default = "subtle",
    enum = {
        { value = "off", text = "Off" },
        { value = "subtle", text = "Subtle" },
        { value = "bold", text = "Bold" },
    },
    onchange = function()
        --turning the feature off re-arms the teach toast.
        if g_glossaryHintsSetting ~= nil and g_glossaryHintsSetting:Get() == "off" then
            g_glossaryToastSeen:Set(false)
        end
    end,
}

MarkdownDocument.GlossaryHintsSetting = g_glossaryHintsSetting

local GLOSSARY_DWELL = 0.35        --hover time before the card shows.
local GLOSSARY_HYSTERESIS = 0.15   --hover gaps shorter than this accumulate.
local GLOSSARY_HIDE_GRACE = 0.30   --card survives this much dehover.

--Broken underline (the design system's treatment for term hints): TMP has
--no dashed-underline tag, so the break is literal - alternate 2-character
--<u> runs with 1-character gaps. No characters are added or removed, so
--layout is identical to the plain span. Spans are ASCII by construction
--(the matcher's word pattern), so byte slicing is safe. Spaces are never
--underlined; they read as natural breaks in multi-word terms.
local function GlossaryBrokenUnderline(span)
    local out = {}
    local i = 1
    local n = #span
    while i <= n do
        if string.sub(span, i, i) == " " then
            out[#out + 1] = " "
            i = i + 1
        else
            local j = math.min(i + 1, n)
            if string.sub(span, j, j) == " " then
                j = i
            end
            out[#out + 1] = "<u>" .. string.sub(span, i, j) .. "</u>"
            i = j + 1
            --one-character gap between runs.
            if i <= n and string.sub(span, i, i) ~= " " then
                out[#out + 1] = string.sub(span, i, i)
                i = i + 1
            end
        end
    end
    return table.concat(out)
end

--The hinted-term treatment for the current setting step: Subtle = broken
--underline, Bold = solid underline.
local function GlossaryUnderlineForm(span)
    if g_glossaryHintsSetting:Get() == "bold" then
        return "<u>" .. span .. "</u>"
    end
    return GlossaryBrokenUnderline(span)
end

--Term index: lowercase first word -> candidate entries sorted longest
--(most words) first. Built lazily from the glossaryTerms table; unhidden,
--non-commonWord terms only. Invalidated when tables refresh.
local g_glossaryIndex = nil

dmhub.RegisterEventHandler("refreshTables", function(keys)
    g_glossaryIndex = nil
end)

local function GetGlossaryIndex()
    if g_glossaryIndex ~= nil then
        return g_glossaryIndex
    end
    local index = {}
    local dataTable = dmhub.GetTable("glossaryTerms")
    if dataTable ~= nil then
        for id, term in pairs(dataTable) do
            if (not term:try_get("hidden", false)) and (not term:try_get("commonWord", false)) then
                local words = {}
                for w in string.gmatch(string.lower(term.name or ""), "[%w']+") do
                    words[#words + 1] = w
                end
                if #words > 0 then
                    local bucket = index[words[1]]
                    if bucket == nil then
                        bucket = {}
                        index[words[1]] = bucket
                    end
                    bucket[#bucket + 1] = { words = words, id = id }
                end
            end
        end
        for _, bucket in pairs(index) do
            table.sort(bucket, function(a, b) return #a.words > #b.words end)
        end
    end
    g_glossaryIndex = index
    return index
end

local function GlossaryTermById(id)
    local dataTable = dmhub.GetTable("glossaryTerms")
    if dataTable == nil then
        return nil
    end
    return dataTable[id]
end

local function IsCapitalized(word)
    local first = string.sub(word or "", 1, 1)
    return first ~= "" and first == string.upper(first) and first ~= string.lower(first)
end

--Mark glossary terms inside one plain-text segment (no tags). washed maps
--termid -> true once its underline has been spent for this label. Every
--match becomes a <link=glossary:id> region; the first match of each term
--also gets the underline treatment. Returns the rewritten segment.
local function GlossaryMarkSegment(seg, index, washed)
    --tokenize words with positions.
    local words = {}
    local searchPos = 1
    while true do
        local s, e = string.find(seg, "[%a][%w']*", searchPos)
        if s == nil then
            break
        end
        words[#words + 1] = { s = s, e = e, text = string.sub(seg, s, e) }
        searchPos = e + 1
    end
    if #words == 0 then
        return seg
    end

    local out = {}
    local copied = 1 --next seg index not yet copied to out.
    local k = 1
    while k <= #words do
        local w = words[k]
        local lower = string.lower(w.text)
        local candidates = index[lower]
        if candidates == nil and string.sub(lower, -1) == "s" then
            --plural of a single-word term.
            candidates = index[string.sub(lower, 1, -2)]
        end

        local matched = nil
        if candidates ~= nil then
            for _, entry in ipairs(candidates) do
                if k + #entry.words - 1 <= #words then
                    local ok = true
                    for j = 1, #entry.words do
                        local sw = string.lower(words[k + j - 1].text)
                        local tw = entry.words[j]
                        local isLast = (j == #entry.words)
                        if sw ~= tw and not (isLast and sw == tw .. "s") then
                            ok = false
                            break
                        end
                        --words must be adjacent (whitespace only between).
                        if ok and j > 1 then
                            local gap = string.sub(seg, words[k + j - 2].e + 1, words[k + j - 1].s - 1)
                            if string.find(gap, "%S") ~= nil then
                                ok = false
                                break
                            end
                        end
                    end
                    if ok then
                        matched = entry
                        break
                    end
                end
            end
        end

        if matched ~= nil and #matched.words == 1 and IsCapitalized(w.text) then
            --proper-noun guard: a capitalized single-word term adjacent to
            --another capitalized word is probably part of a name ("The
            --Winded Man"); skip it - the hint falls through to the next
            --occurrence naturally.
            local prevCap = k > 1 and IsCapitalized(words[k - 1].text)
            local nextCap = k < #words and IsCapitalized(words[k + 1].text)
            if prevCap or nextCap then
                matched = nil
            end
        end

        if matched ~= nil then
            local lastWord = words[k + #matched.words - 1]
            out[#out + 1] = string.sub(seg, copied, w.s - 1)
            local span = string.sub(seg, w.s, lastWord.e)
            if washed[matched.id] then
                out[#out + 1] = string.format("<link=glossary:%s>%s</link>", matched.id, span)
            else
                washed[matched.id] = true
                out[#out + 1] = string.format("<link=glossary:%s>%s</link>",
                    matched.id, GlossaryUnderlineForm(span))
            end
            copied = lastWord.e + 1
            k = k + #matched.words
        else
            k = k + 1
        end
    end
    out[#out + 1] = string.sub(seg, copied)
    return table.concat(out)
end

--Tag-aware pass over a label's final rich text. Skips <...> tag runs,
--anything inside an existing <link> or <size> run (size = skinned
--headings), and raw markdown heading lines (# ...) which the engine
--renders as headings in default-skin documents.
local function ApplyGlossaryHints(text)
    if text == nil or text == "" then
        return text
    end
    local index = GetGlossaryIndex()
    if index == nil or next(index) == nil then
        return text
    end

    local out = {}
    local linkDepth = 0
    local sizeDepth = 0
    local i = 1
    local n = #text
    local washed = {}
    local atLineStart = true
    while i <= n do
        local ch = string.sub(text, i, i)
        if ch == "<" then
            local close = string.find(text, ">", i, true)
            if close == nil then
                out[#out + 1] = string.sub(text, i)
                break
            end
            local tag = string.lower(string.sub(text, i, close))
            if string.starts_with(tag, "<link") then
                linkDepth = linkDepth + 1
            elseif tag == "</link>" then
                linkDepth = math.max(0, linkDepth - 1)
            elseif string.starts_with(tag, "<size") then
                sizeDepth = sizeDepth + 1
            elseif tag == "</size>" then
                sizeDepth = math.max(0, sizeDepth - 1)
            end
            out[#out + 1] = string.sub(text, i, close)
            i = close + 1
        else
            local nextTag = string.find(text, "<", i, true) or (n + 1)
            local seg = string.sub(text, i, nextTag - 1)
            if linkDepth > 0 or sizeDepth > 0 then
                out[#out + 1] = seg
            else
                --process line by line so raw markdown headings are skipped.
                local segOut = {}
                local pos = 1
                while pos <= #seg do
                    local nl = string.find(seg, "\n", pos, true)
                    local lineEnd = nl ~= nil and nl or (#seg + 1)
                    local line = string.sub(seg, pos, lineEnd - 1)
                    if atLineStart and string.match(line, "^#+[ \t]") ~= nil then
                        segOut[#segOut + 1] = line
                    else
                        segOut[#segOut + 1] = GlossaryMarkSegment(line, index, washed)
                    end
                    if nl ~= nil then
                        segOut[#segOut + 1] = "\n"
                        atLineStart = true
                        pos = nl + 1
                    else
                        atLineStart = false
                        pos = lineEnd
                    end
                end
                out[#out + 1] = table.concat(segOut)
            end
            i = nextTag
        end
    end
    return table.concat(out)
end

--The definition card, shared by hover tooltips, the pinned card, and the
--/glossary command. options: pinned (adds close X), close (dismiss fn).
function MarkdownDocument.CreateGlossaryCard(term, options)
    options = options or {}

    local sourceLine = nil
    local openButton = nil
    local src = term:try_get("sourceReference")
    if src ~= nil and src.docid ~= nil and src.docid ~= "none" then
        local pdfDoc = assets.pdfDocumentsTable[src.docid]
        if pdfDoc ~= nil and not pdfDoc.hidden then
            sourceLine = string.format("%s, p. %d", pdfDoc.description or "Book", src.page or 1)
            openButton = gui.Button{
                classes = {"sizeS"},
                halign = "right",
                valign = "center",
                lmargin = 6,
                fontSize = 13,
                hpad = 8,
                vpad = 2,
                text = "Open",
                click = function(element)
                    if options.close ~= nil then
                        options.close()
                    end
                    --opens at the PRINTED page (resolved against the PDF's
                    --page labels; see GlossaryTerm.OpenSourcePage).
                    GlossaryTerm.OpenSourcePage(src)
                end,
            }
        end
    end

    local headerChildren = {
        gui.Label{
            width = "auto",
            height = "auto",
            maxWidth = "100%-30",
            halign = "left",
            fontSize = 18,
            bold = true,
            color = "white",
            text = term.name or "Term",
        },
    }
    if options.pinned then
        headerChildren[#headerChildren + 1] = gui.Label{
            width = "auto",
            height = "auto",
            halign = "right",
            valign = "top",
            fontSize = 16,
            color = "#ffffff99",
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            hpad = 4,
            text = "x",
            hover = function(element) element.selfStyle.color = "#ffffff" end,
            dehover = function(element) element.selfStyle.color = "#ffffff99" end,
            click = function(element)
                if options.close ~= nil then
                    options.close()
                end
            end,
        }
    end

    local children = {
        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            children = headerChildren,
        },
        gui.Label{
            width = "100%",
            height = "auto",
            vmargin = 6,
            fontSize = 15,
            color = "#e8e8e8",
            text = term.definition or "",
        },
    }
    --footer: source line on the left, Share to Chat / Open on the right.
    --Always present so terms without a source reference remain shareable.
    local footerChildren = {}
    if sourceLine ~= nil then
        footerChildren[#footerChildren + 1] = gui.Label{
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            fontSize = 13,
            color = "#ffffff77",
            text = sourceLine,
        }
    end
    footerChildren[#footerChildren + 1] = gui.Button{
        classes = {"sizeS"},
        halign = "right",
        valign = "center",
        fontSize = 13,
        hpad = 8,
        vpad = 2,
        text = "Share to Chat",
        click = function(element)
            chat.ShareData(term)
        end,
    }
    if openButton ~= nil then
        footerChildren[#footerChildren + 1] = openButton
    end
    children[#children + 1] = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        vmargin = 2,
        children = footerChildren,
    }

    return gui.Panel{
        width = 380,
        height = "auto",
        flow = "vertical",
        pad = 10,
        borderBox = true,
        bgimage = "panels/square.png",
        bgcolor = "#101010f2",
        border = 1,
        borderColor = "#ffffff47",
        --presses on the card must not reach click-away dismissers that
        --PARENT the card (the /glossary modal wrapper closes on press;
        --buttons fire on release, so a bubbled press would destroy the
        --card before its buttons could ever fire).
        swallowPress = true,
        children = children,
    }
end

--Hover state machine: dwell with hysteresis, hide grace, wash brighten.
--Module-level: there is one cursor.
local g_glossHover = {
    link = nil,       --the glossary: link currently (or last) hovered.
    element = nil,
    startedAt = nil,  --when the (accumulated) dwell began.
    leftAt = nil,     --dehover time; nil while hovered.
    shown = false,    --tooltip currently displayed.
}

--NOTE: there is deliberately no hover restyle of the hinted span.
--Reassigning label.text mid-hover resets the engine's link-hover state
--(linkHovered reads nil until the mouse moves), which cascades into a
--phantom dehover that kills the card. The hover response is the card
--itself; the underline never changes under the cursor.

--The hover card is NOT an engine tooltip: tooltips anchor to the whole
--label panel (a full-width paragraph), which reads as center-screen. The
--card is instead placed at the mouse point on a floating host owned by the
--DisplayPanel (see hoverGlossaryTerm). It is only built when the dwell
--elapses: a panel parented at opacity 0 and revealed later never renders,
--so create-visible-at-reveal is the reliable pattern.
local GlossaryRevealCard

--Destroy the hover card and reset the hover state machine.
local function GlossaryClearHoverCard()
    local frame = g_glossHover.frame
    g_glossHover.frame = nil
    g_glossHover.shown = false
    g_glossHover.link = nil
    g_glossHover.leftAt = nil
    if frame ~= nil and frame.valid then
        frame:DestroySelf()
    end
end

local function GlossaryHintHover(element, link)
    local now = dmhub.Time()

    local resuming = g_glossHover.link == link and g_glossHover.leftAt ~= nil
        and (now - g_glossHover.leftAt) <= GLOSSARY_HYSTERESIS
    if resuming then
        --same link within the hysteresis window: keep the accumulated
        --dwell (and the card, if it was already up).
        g_glossHover.leftAt = nil
        g_glossHover.element = element
    else
        --new link: drop any card left over from a previous term.
        if g_glossHover.frame ~= nil and g_glossHover.frame.valid then
            g_glossHover.frame:DestroySelf()
        end
        g_glossHover.frame = nil
        g_glossHover.link = link
        g_glossHover.element = element
        g_glossHover.startedAt = now
        g_glossHover.leftAt = nil
        g_glossHover.shown = false
    end

    if GlossaryTermById(string.sub(link, 10)) == nil then
        return
    end

    --the card is only built at reveal time (see GlossaryRevealCard), fully
    --visible from birth, at the mouse point read at that moment.
    local remaining = GLOSSARY_DWELL - (now - g_glossHover.startedAt)
    if g_glossHover.shown or remaining <= 0 then
        GlossaryRevealCard(element)
    else
        element:ScheduleEvent("glossaryDwell", remaining)
    end
end

GlossaryRevealCard = function(element)
    if g_glossHover.link == nil then
        return
    end
    g_glossHover.shown = true
    --build (or rebuild, repositioning at the current mouse point) the card
    --on the DisplayPanel's hover host; the handler stores it in
    --g_glossHover.frame (events fire synchronously).
    element:FireEventOnParents("hoverGlossaryTerm", string.sub(g_glossHover.link, 10))

    --one-time teach toast, latched only by explicit dismissal.
    if not g_glossaryToastSeen:Get() then
        element:FireEventOnParents("glossaryToast")
    end
end

local function GlossaryHintDehover(element, link)
    if g_glossHover.link ~= link then
        return
    end
    g_glossHover.leftAt = dmhub.Time()
    element:ScheduleEvent("glossaryHideGrace", GLOSSARY_HIDE_GRACE)
end

local function GlossaryDwellEvent(element)
    if g_glossHover.link ~= nil and g_glossHover.leftAt == nil and not g_glossHover.shown
       and element.linkHovered == g_glossHover.link then
        GlossaryRevealCard(element)
    end
end

local function GlossaryHideGraceEvent(element)
    if g_glossHover.leftAt ~= nil
       and (dmhub.Time() - g_glossHover.leftAt) >= GLOSSARY_HIDE_GRACE - 0.01 then
        GlossaryClearHoverCard()
    end
end

--Strip glossary markup from every label under root. Run after renders with
--hints off (mute/setting): pooled labels can occasionally survive a render
--without text reassignment, so stale washes are removed positively rather
--than trusting the reassignment path. Mirrors the ApplyFindMarks walk.
local function StripGlossaryMarks(root)
    local function walk(panel)
        local ok, valid = pcall(function() return panel.valid end)
        if not ok or not valid then
            return
        end
        local text = nil
        pcall(function() text = panel.text end)
        if type(text) == "string" and string.find(text, "<link=glossary:", 1, true) ~= nil then
            local newText = text
            --legacy wash form (pooled labels from an older render).
            newText = string.gsub(newText, "<mark=#%x+><link=glossary:[^>]*>(.-)</link></mark>", "%1")
            --underline form: unwrap the link and its <u> runs.
            newText = string.gsub(newText, "<link=glossary:[^>]*>(.-)</link>", function(inner)
                return (string.gsub(inner, "</?u>", ""))
            end)
            pcall(function() panel.text = newText end)
        end
        local kids = nil
        pcall(function() kids = panel.children end)
        if kids ~= nil then
            for _, c in ipairs(kids) do
                walk(c)
            end
        end
    end
    walk(root)
end

local function GlossaryHintPress(element, link)
    --the hover card must not linger over the pinned card.
    GlossaryClearHoverCard()
    element:FireEventOnParents("pinGlossaryTerm", string.sub(link, 10))
end

--Renders a token stream (from BreakdownRichTags with trackPositions) into an
--array of child panels, reusing panels pooled from the previous render where
--possible. ctx is a stable per-host-panel render context:
--  ctx.doc            - the document being rendered. The caller updates this
--                       before each render; pooled panels' event closures
--                       read ctx.doc so they always act on the latest doc,
--                       matching the old behavior of capturing DisplayPanel's
--                       live self upvalue.
--  ctx.embedDepth     - recursion depth for document embeds.
--  ctx.tokenExtraInfo - extraOutput table from the tokenize pass (spoiler
--                       locations, queries); replaced by the caller each render.
--  ctx.pools          - panel pools carried between renders; swapped for the
--                       new generation at the end of each call.
--  ctx.render         - per-render skin values, set by the caller before each
--                       call: skin, classes, ruledLevels, usesAlign, pageColor.
--Each top-level child panel is stamped with data.srcLine (the source line of
--the token that produced it) for content-aware preview scroll sync.
--Returns the new children array for the host panel.
local function RenderMarkdownTokens(ctx, tokens)
    --read-side aliases for the panel pools; the new generation is written
    --back into ctx.pools at the bottom.
    local m_rollableTableRowLabels = ctx.pools.rollableTableRowLabels
    local m_textPanels = ctx.pools.textPanels
    local m_richPanels = ctx.pools.richPanels
    local m_richFrames = ctx.pools.richFrames
    local m_richRows = ctx.pools.richRows
    local m_rollableTables = ctx.pools.rollableTables
    local m_tables = ctx.pools.tables
    local m_tableRows = ctx.pools.tableRows
    local m_dividers = ctx.pools.dividers
    local m_headingRules = ctx.pools.headingRules
    local m_powerTables = ctx.pools.powerTables
    local m_embeds = ctx.pools.embeds
    local m_treeNodes = ctx.pools.treeNodes
    local m_blockquotes = ctx.pools.blockquotes
    local m_styleblocks = ctx.pools.styleblocks

    local embedDepth = ctx.embedDepth

    --per-render skin values resolved by the caller.
    local resolvedSkin = ctx.render.skin
    local resolvedClasses = ctx.render.classes
    local ruledLevels = ctx.render.ruledLevels
    local usesAlign = ctx.render.usesAlign
    local pageColor = ctx.render.pageColor

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

            local panel = m_powerTables[#newPowerTables + 1] or PowerRollDisplay(ctx.doc)
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
                            if ref.docid == ctx.doc.id and ref.tableid == tableName then
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

                    local ref = RollTableReference.CreateDocumentReference(ctx.doc.id, tableName)
                    if not ctx.doc:IsPlayerView(element) then
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

            panel.data.tableData = ctx.doc:GetRollableTable(tableName)
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
            currentRichRow.data.tagInRow = false
            currentRichRow.selfStyle.wrap = false
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
                        if string.starts_with(link, "glossary:") then
                            GlossaryHintHover(element, link)
                            return
                        end
                        CustomDocument.PreviewLink(element, link)
                    end,
                    dehoverLink = function(element, link)
                        if string.starts_with(link, "glossary:") then
                            GlossaryHintDehover(element, link)
                            return
                        end
                        element.tooltip = nil
                    end,
                    glossaryDwell = function(element)
                        GlossaryDwellEvent(element)
                    end,
                    glossaryHideGrace = function(element)
                        GlossaryHideGraceEvent(element)
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
                        if element.linkHovered ~= nil and string.starts_with(element.linkHovered, "glossary:") then
                            GlossaryHintPress(element, element.linkHovered)
                            return
                        end
                        if element.linkHovered ~= nil then
                            local link = element.linkHovered
                            if string.starts_with(link, "spoiler:") then
                                local spoilerValue = link:sub(9)
                                local spoilerInfo = (ctx.tokenExtraInfo.spoilers or {})[spoilerValue]
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
                                        ctx.doc:SetTextContent(table.concat(lines, "\n"))
                                        ctx.doc:Upload()
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

                local finalText = ApplySkinToText(ApplyInlineClasses(text, resolvedClasses), resolvedSkin)
                if ctx.render.glossaryHints then
                    finalText = ApplyGlossaryHints(finalText)
                end
                textPanel.text = finalText
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
                        currentRichRow.data.tagInRow = false
                        currentRichRow.selfStyle.wrap = false
                        newRichRows[#newRichRows + 1] = currentRichRow
                        children[#children + 1] = currentRichRow
                    end

                    if token.justification then
                        currentRichRow.selfStyle.width = "100%"
                    end

                    textPanel.selfStyle.width = "auto"
                    if currentRichRow.data.tagInRow and token.justification == nil then
                        --text following a rich tag: a %-maxWidth is measured from
                        --the label's own left edge, so "100%" overflows the row by
                        --the tag's width. Pull it in so text fits beside a small
                        --tag (a bare checkbox is ~34px); when the tag is wider the
                        --row's wrap drops the text to its own near-full-width line.
                        textPanel.selfStyle.maxWidth = "100%-40"
                    else
                        textPanel.selfStyle.maxWidth = "100%"
                    end
                    textPanel.selfStyle.valign = "center"
                    currentRichRow.data.children[#currentRichRow.data.children + 1] = textPanel
                else
                    -- Only widen for stylesheet alignment when the author did not set an explicit
                    -- :>/:<> justification (which positions an auto-width label via panel halign).
                    textPanel.selfStyle.width = (usesAlign and not token.justification) and "100%" or "auto"
                    textPanel.selfStyle.maxWidth = "100%"
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
                    label.selfStyle.maxWidth = "100%"
                    label.selfStyle.valign = "top"
                    local finalText = ApplySkinToText(
                        ApplyInlineClasses(seg.text, resolvedClasses),
                        resolvedSkin,
                        { ruledLevels = ruledLevels })
                    if ctx.render.glossaryHints then
                        finalText = ApplyGlossaryHints(finalText)
                    end
                    label.text = finalText
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
                    richTag = ctx.doc.annotations[candidate]

                    --patch over any possible bugs where the saved annotation is not a proper table.
                    if richTag ~= nil and getmetatable(richTag) == nil then
                        richTag = nil
                        ctx.doc.annotations[candidate] = nil
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
                        currentRichRow.data.tagInRow = false
                        currentRichRow.selfStyle.wrap = false
                        newRichRows[#newRichRows + 1] = currentRichRow
                        children[#children + 1] = currentRichRow
                    end

                    if m_richPanels[candidate] ~= nil and panel.parent ~= currentRichRow then
                        panel:Unparent()
                    end

                    if token.justification then
                        currentRichRow.selfStyle.width = "100%"
                    end

                    richTag._tmp_document = ctx.doc
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

                    currentRichRow.data.tagInRow = true
                    --a rich tag with same-line text: an auto-width label's maxWidth
                    --of 100% is the full row width, but the label starts after the
                    --tag panel, so long text overflows the row by the tag's width
                    --(clips in narrow embeds like the Run panel accordion). Let the
                    --row wrap so text that cannot fit beside the tag drops to its
                    --own full-width line instead of clipping.
                    currentRichRow.selfStyle.wrap = true
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

    ctx.pools.rollableTableRowLabels = newRollableTableRowLabels
    ctx.pools.rollableTables = newRollableTables
    ctx.pools.richRows = newRichRows
    ctx.pools.richPanels = newRichPanels
    ctx.pools.richFrames = newRichFrames
    ctx.pools.textPanels = newTextPanels
    ctx.pools.tableRows = newTableRows
    ctx.pools.tables = newTables
    ctx.pools.dividers = newDividers
    ctx.pools.headingRules = newHeadingRules
    ctx.pools.powerTables = newPowerTables
    ctx.pools.embeds = newEmbeds
    ctx.pools.treeNodes = newTreeNodes
    ctx.pools.blockquotes = newBlockquotes
    ctx.pools.styleblocks = newStyleblocks

    return children
end

--Creates a fresh render context for RenderMarkdownTokens. One context per
--host panel; it persists across renders so panel pools and closure state
--carry over.
local function CreateMarkdownRenderContext(doc, embedDepth)
    return {
        doc = doc,
        embedDepth = embedDepth or 0,
        tokenExtraInfo = {},
        render = {},
        pools = {
            rollableTableRowLabels = {},
            textPanels = {},
            richPanels = {},
            richFrames = {},
            richRows = {},
            rollableTables = {},
            tables = {},
            tableRows = {},
            dividers = {},
            headingRules = {},
            powerTables = {},
            embeds = {},
            treeNodes = {},
            blockquotes = {},
            styleblocks = {},
        },
    }
end

--Related-entries footer for the top-level read view. Two directions:
--"From this page" (documents this page references) and "Mentioned in"
--(documents that reference this page). A reference is either a link-form
--mention of the description in the text - all the link syntaxes end up
--containing "(desc", "[desc", "[:desc", or "document:desc" - or the doc's
--id appearing in the other page's annotations, which generically catches
--widget-held references (an exit's nextDocid, a cue's opendoc step)
--without knowing each widget's schema.
local function CollectRelatedDocs(selfDoc)
    local docsTable = dmhub.GetTable(CustomDocument.tableName) or {}
    local isDM = dmhub.isDM
    local accessibleRoots = nil
    if not isDM then
        accessibleRoots = CustomDocument.GetAccessibleRoots()
    end

    local function AnnotationsJson(doc)
        local result = ""
        pcall(function()
            local ann = doc:try_get("annotations")
            if ann ~= nil and next(ann) ~= nil then
                result = dmhub.ToJson(ann)
            end
        end)
        return result
    end

    --true when content references a page with this description via any
    --link form. Bare prose mentions deliberately do not count.
    local function MentionsDesc(content, ldesc)
        if #ldesc < 3 then
            return false
        end
        return string.find(content, "(" .. ldesc, 1, true) ~= nil
            or string.find(content, "[" .. ldesc, 1, true) ~= nil
            or string.find(content, "[:" .. ldesc, 1, true) ~= nil
            or string.find(content, "document:" .. ldesc, 1, true) ~= nil
    end

    local mydesc = string.lower(selfDoc.description or "")
    local myid = selfDoc:try_get("id")
    local mycontent = ""
    pcall(function() mycontent = string.lower(selfDoc:GetTextContent() or "") end)
    local myannotations = AnnotationsJson(selfDoc)

    local outgoing, incoming = {}, {}
    for id, doc in unhidden_pairs(docsTable) do
        if id ~= myid then
            local visible = isDM or ((not doc:try_get("hiddenFromPlayers", false))
                and CustomDocument.IsDocInAccessibleRoot(doc, accessibleRoots))
            if visible then
                local desc = doc.description or ""
                local ldesc = string.lower(desc)

                if MentionsDesc(mycontent, ldesc)
                    or (myannotations ~= "" and string.find(myannotations, id, 1, true)) then
                    outgoing[#outgoing + 1] = { id = id, name = desc }
                end

                local theircontent = ""
                pcall(function() theircontent = string.lower(doc:GetTextContent() or "") end)
                local theirann = AnnotationsJson(doc)
                if MentionsDesc(theircontent, mydesc)
                    or (myid ~= nil and theirann ~= "" and string.find(theirann, myid, 1, true)) then
                    incoming[#incoming + 1] = { id = id, name = desc }
                end
            end
        end
    end
    table.sort(outgoing, function(a, b) return a.name < b.name end)
    table.sort(incoming, function(a, b) return a.name < b.name end)
    return outgoing, incoming
end

local function BuildRelatedFooter(selfDoc)
    local outgoing, incoming = CollectRelatedDocs(selfDoc)
    if #outgoing == 0 and #incoming == 0 then
        return nil
    end

    --match the page skin when the sheet defines one; quiet greys otherwise.
    local pal = MarkdownDocument.PageSkinPalette(selfDoc)
    local mutedColor = pal ~= nil and pal.muted or "#8a8578"
    local linkColor = pal ~= nil and pal.link or "#b8b2a4"
    local inkColor = pal ~= nil and pal.ink or "#e4ddd0"
    local hairColor = pal ~= nil and pal.hairline or "#88888833"

    local function Row(entry)
        return gui.Label {
            width = "auto",
            height = "auto",
            maxWidth = "100%",
            halign = "left",
            fontSize = CustomDocument.ScaleFontSize(13),
            color = linkColor,
            bmargin = 2,
            text = entry.name,
            styles = {
                { selectors = { "hover" }, color = inkColor },
            },
            press = function(element)
                --navigate in place like a page link; fall back to a tab.
                local dialogPanel = element:FindParentWithClass("framedPanel")
                if dialogPanel and dialogPanel.data and dialogPanel.data.history then
                    dialogPanel:FireEvent("navigateToDocument", entry.id)
                    return
                end
                local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[entry.id]
                if doc ~= nil then
                    CustomDocument.OpenContent(doc)
                end
            end,
        }
    end

    local function Group(title, entries)
        if #entries == 0 then
            return nil
        end
        local children = {
            gui.Label {
                width = "100%",
                height = "auto",
                halign = "left",
                fontSize = CustomDocument.ScaleFontSize(11),
                bold = true,
                color = mutedColor,
                bmargin = 4,
                text = title,
            },
        }
        for _, entry in ipairs(entries) do
            children[#children + 1] = Row(entry)
        end
        return gui.Panel {
            flow = "vertical",
            width = "50%",
            height = "auto",
            halign = "left",
            valign = "top",
            children = children,
        }
    end

    local columns = {}
    columns[#columns + 1] = Group("FROM THIS PAGE", outgoing)
    columns[#columns + 1] = Group("MENTIONED IN", incoming)

    return gui.Panel {
        flow = "vertical",
        width = "100%",
        height = "auto",
        tmargin = 24,

        gui.Panel {
            width = "100%",
            height = 1,
            bgimage = "panels/square.png",
            bgcolor = hairColor,
            bmargin = 8,
        },
        gui.Label {
            width = "100%",
            height = "auto",
            halign = "left",
            fontSize = CustomDocument.ScaleFontSize(12),
            bold = true,
            color = mutedColor,
            bmargin = 6,
            text = "RELATED",
        },
        gui.Panel {
            flow = "horizontal",
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            children = columns,
        },
    }
end

--Find-in-page: highlight marks injected into rendered label text. The
--soft mark tints every hit; the current hit gets the stronger mark. A
--highlighter yellow/amber family reads on both the dark theme and
--parchment pages, and marks sit BEHIND the glyphs so ink stays legible.
local FIND_MARK_SOFT = "#ffd54a55"
local FIND_MARK_CURRENT = "#ff9d2e88"

--Wrap term occurrences in a label's rich text with <mark> tags, skipping
--<...> tag runs so markup (links, colors, existing marks) is never split.
--Occurrences that span a tag boundary (e.g. across </b>) do not match -
--acceptable for v1. Returns the marked text and the number of matches;
--the match numbered currentIndex - indexBase gets the current-mark color.
local function MarkLabelMatches(text, lterm, indexBase, currentIndex)
    local out = {}
    local count = 0
    local lower = string.lower(text)
    local i = 1
    local n = #text
    while i <= n do
        if text:sub(i, i) == "<" then
            local close = text:find(">", i, true)
            if close == nil then
                out[#out + 1] = text:sub(i)
                break
            end
            out[#out + 1] = text:sub(i, close)
            i = close + 1
        else
            local nextTag = text:find("<", i, true) or (n + 1)
            local seg = text:sub(i, nextTag - 1)
            local lseg = lower:sub(i, nextTag - 1)
            local spos = 1
            while true do
                local a, b = lseg:find(lterm, spos, true)
                if a == nil then
                    out[#out + 1] = seg:sub(spos)
                    break
                end
                count = count + 1
                local color = FIND_MARK_SOFT
                if currentIndex ~= nil and indexBase + count == currentIndex then
                    color = FIND_MARK_CURRENT
                end
                out[#out + 1] = seg:sub(spos, a - 1)
                out[#out + 1] = "<mark=" .. color .. ">" .. seg:sub(a, b) .. "</mark>"
                spos = b + 1
            end
            i = nextTag
        end
    end
    return table.concat(out), count
end

--Depth-first walk over the rendered page (render order == document order),
--marking matches in every label. Returns the total match count and the
--label carrying the current match. Panel reads error rather than return
--nil, so every read is pcall-guarded.
local function ApplyFindMarks(root, term, currentIndex)
    local lterm = string.lower(term)
    local total = 0
    local currentLabel = nil
    local function walk(panel)
        local ok, valid = pcall(function() return panel.valid end)
        if not ok or not valid then
            return
        end
        local text = nil
        pcall(function() text = panel.text end)
        if type(text) == "string" and text ~= "" then
            local newText, cnt = MarkLabelMatches(text, lterm, total, currentIndex)
            if cnt > 0 then
                pcall(function() panel.text = newText end)
                if currentIndex ~= nil and currentIndex > total and currentIndex <= total + cnt then
                    currentLabel = panel
                end
                total = total + cnt
            end
        end
        local kids = nil
        pcall(function() kids = panel.children end)
        if kids ~= nil then
            for _, c in ipairs(kids) do
                walk(c)
            end
        end
    end
    walk(root)
    return total, currentLabel
end

--Scroll a descendant into (vertically centered) view within its nearest
--vscroll ancestor. No engine ScrollIntoView exists; offsets are summed
--from preceding siblings' rendered heights (same approach as the
--character sheet's search reveal). Returns false until layout has
--rendered so the caller can retry.
local function ScrollFindTargetIntoView(target)
    if target == nil or not target.valid then
        return false
    end

    local scrollPanel = target.parent
    while scrollPanel ~= nil do
        local isScroll = false
        pcall(function() isScroll = scrollPanel.vscroll == true end)
        if isScroll then
            break
        end
        scrollPanel = scrollPanel.parent
    end
    if scrollPanel == nil then
        return false
    end

    local windowH = 0
    local targetH = 0
    pcall(function() windowH = scrollPanel.renderedHeight or 0 end)
    pcall(function() targetH = target.renderedHeight or 0 end)
    if windowH <= 0 or targetH <= 0 then
        return false
    end

    local contentH = 0
    pcall(function()
        for _, c in ipairs(scrollPanel.children) do
            contentH = contentH + (c.renderedHeight or 0)
        end
    end)
    local range = contentH - windowH
    if range <= 0 then
        return true
    end

    local offset = 0
    local node = target
    while node ~= nil and node ~= scrollPanel do
        local parent = node.parent
        if parent == nil then
            return false
        end
        pcall(function()
            for _, s in ipairs(parent.children) do
                if s == node then
                    break
                end
                offset = offset + (s.renderedHeight or 0)
            end
        end)
        node = parent
    end

    local desiredTop = offset - (windowH - targetH) * 0.5
    if desiredTop < 0 then
        desiredTop = 0
    elseif desiredTop > range then
        desiredTop = range
    end
    --vscrollPosition: 1 = top, 0 = bottom.
    scrollPanel.vscrollPosition = 1 - desiredTop / range
    return true
end

function MarkdownDocument.DisplayPanel(self, args)
    args = args or {}
    local embedDepth = args.embedDepth or 0
    args.embedDepth = nil

    --Related-entries footer: opt-in by the top-level viewer only, so page
    --embeds, hover previews, and template previews stay clean.
    local m_relatedFooter = args.relatedFooter or false
    args.relatedFooter = nil

    --Find-in-page state (driven by the findInPage event below).
    local m_findTerm = nil
    local m_findIndex = 1
    local m_findCallback = nil
    local m_findGeneration = 0

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

    --Glossary hints: per-view mute (toolbar eye), plus floating hosts for
    --the pinned definition card and the one-time teach toast. The hosts are
    --created once and re-appended to children on every render.
    local m_glossaryMuted = false
    local m_glossaryPinHost = nil
    local m_glossaryToastHost = nil
    local m_glossaryHoverHost = nil

    local BuildGlossaryPin

    local function GetGlossaryHoverHost()
        if m_glossaryHoverHost ~= nil and m_glossaryHoverHost.valid then
            return m_glossaryHoverHost
        end
        m_glossaryHoverHost = gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            interactable = false,
        }
        return m_glossaryHoverHost
    end

    --Hover card: built at the mouse point inside the document view. The
    --engine tooltip system anchors to the whole paragraph label, which
    --reads as center-screen, so the card is hosted here instead.
    local function ShowGlossaryHoverCard(termid)
        local term = (dmhub.GetTable("glossaryTerms") or {})[termid]
        if term == nil then
            return
        end
        local host = GetGlossaryHoverHost()
        local card = MarkdownDocument.CreateGlossaryCard(term, {})

        local hostW = host.renderedWidth or 0
        local hostH = host.renderedHeight or 0
        local px = nil
        local py = nil
        pcall(function()
            local p = host.mousePoint
            if p ~= nil and (p.x ~= 0 or p.y ~= 0) then
                px = p.x * hostW
                py = (1 - p.y) * hostH
            end
        end)
        if px == nil then
            --mouse point unavailable; fall back to the upper middle.
            px = math.max(8, hostW * 0.5 - 200)
            py = hostH * 0.3
        else
            px = math.max(8, math.min(px + 14, hostW - 400))
            py = math.max(8, math.min(py + 20, hostH - 260))
        end

        g_glossHover.gen = (g_glossHover.gen or 0) + 1
        local wrapper
        wrapper = gui.Panel{
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "top",
            x = px,
            y = py,
            interactable = false,
            data = { gen = g_glossHover.gen },
            --safety net: the label's dehover can be missed when the doc
            --re-renders or scrolls under a stationary mouse. Poll the
            --source label; when the link is gone, start the hide grace.
            --(generation ids rather than panel identity: userdata
            --references are not reliably comparable.)
            thinkTime = 0.25,
            think = function(element)
                if element.data.gen ~= g_glossHover.gen then
                    element:DestroySelf()
                    return
                end
                local src = g_glossHover.element
                local srcValid = false
                pcall(function() srcValid = src ~= nil and src.valid end)
                if not srcValid then
                    GlossaryClearHoverCard()
                    return
                end
                if g_glossHover.leftAt == nil then
                    local hovered = nil
                    pcall(function() hovered = src.linkHovered end)
                    if hovered ~= g_glossHover.link then
                        g_glossHover.leftAt = dmhub.Time()
                        src:ScheduleEvent("glossaryHideGrace", GLOSSARY_HIDE_GRACE)
                    end
                end
            end,
            card,
        }
        wrapper:MakeNonInteractiveRecursive()
        host.children = { wrapper }
        g_glossHover.frame = wrapper
    end

    local function GetGlossaryPinHost()
        if m_glossaryPinHost ~= nil and m_glossaryPinHost.valid then
            return m_glossaryPinHost
        end
        m_glossaryPinHost = gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            interactable = false,
            data = { pendingTerm = nil },
            --pin creation is deferred past the pinning click's release:
            --buttons fire on mouse-up, so a card materializing during the
            --click could have its Open button eat the release.
            glossaryPinDeferred = function(element)
                if element.data.pendingTerm ~= nil then
                    local termid = element.data.pendingTerm
                    element.data.pendingTerm = nil
                    BuildGlossaryPin(termid)
                end
            end,
        }
        return m_glossaryPinHost
    end

    local function GetGlossaryToastHost()
        if m_glossaryToastHost ~= nil and m_glossaryToastHost.valid then
            return m_glossaryToastHost
        end
        m_glossaryToastHost = gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            halign = "center",
            valign = "center",
            interactable = false,
        }
        return m_glossaryToastHost
    end

    local function CloseGlossaryPin()
        if m_glossaryPinHost ~= nil and m_glossaryPinHost.valid then
            m_glossaryPinHost.children = {}
        end
    end

    --Single pin: pinning a new term replaces the old card. The card sits at
    --the top right of the document view (screen-anchored, self-identifying
    --by its term-name header). A transparent blocker beneath it swallows
    --the dismissing click so click-away never activates content beneath.
    local function PinGlossaryCard(termid)
        local host = GetGlossaryPinHost()
        host.data.pendingTerm = termid
        --capture the click position now (the host spans the document view);
        --the deferred build places the card beside it.
        host.data.pendingPoint = nil
        pcall(function()
            local p = host.mousePoint
            if p ~= nil and (p.x ~= 0 or p.y ~= 0) then
                host.data.pendingPoint = {
                    x = p.x * (host.renderedWidth or 0),
                    y = (1 - p.y) * (host.renderedHeight or 0),
                }
            end
        end)
        host:ScheduleEvent("glossaryPinDeferred", 0.12)
    end

    BuildGlossaryPin = function(termid)
        local term = (dmhub.GetTable("glossaryTerms") or {})[termid]
        if term == nil then
            return
        end
        local host = GetGlossaryPinHost()
        local card = MarkdownDocument.CreateGlossaryCard(term, {
            pinned = true,
            close = CloseGlossaryPin,
        })

        --place the card beside the click point (captured at press time),
        --clamped inside the view; fall back to top-right if the point is
        --unavailable.
        local cardWrapper
        local pos = host.data.pendingPoint
        host.data.pendingPoint = nil
        if pos ~= nil then
            local hostW = host.renderedWidth or 0
            local hostH = host.renderedHeight or 0
            local px = math.max(8, math.min(pos.x + 12, hostW - 400))
            local py = math.max(8, math.min(pos.y + 14, hostH - 260))
            cardWrapper = gui.Panel{
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "top",
                x = px,
                y = py,
                card,
            }
        else
            cardWrapper = gui.Panel{
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "top",
                rmargin = 14,
                tmargin = 14,
                card,
            }
        end

        host.children = {
            gui.Panel{
                width = "100%",
                height = "100%",
                halign = "center",
                valign = "center",
                bgimage = "panels/square.png",
                bgcolor = "#00000000",
                captureEscape = true,
                escapePriority = EscapePriority.DMHUB_POPUP,
                escape = function(element)
                    CloseGlossaryPin()
                end,
                press = function(element)
                    CloseGlossaryPin()
                end,
            },
            cardWrapper,
        }
    end

    local function ShowGlossaryToast()
        if g_glossaryToastSeen:Get() then
            return
        end
        local host = GetGlossaryToastHost()
        if #host.children > 0 then
            return
        end
        host.children = {
            gui.Panel{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "top",
                tmargin = 10,
                flow = "horizontal",
                pad = 8,
                borderBox = true,
                bgimage = "panels/square.png",
                bgcolor = "#101010f2",
                border = 1,
                borderColor = "#ffffff47",
                gui.Label{
                    width = "auto",
                    height = "auto",
                    maxWidth = 520,
                    valign = "center",
                    fontSize = 14,
                    color = "#e8e8e8",
                    text = "Softly underlined terms have glossary definitions - hover to read, click to pin.",
                },
                gui.Label{
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    lmargin = 10,
                    hpad = 4,
                    fontSize = 15,
                    color = "#ffffff99",
                    bgimage = "panels/square.png",
                    bgcolor = "#00000000",
                    text = "x",
                    hover = function(element) element.selfStyle.color = "#ffffff" end,
                    dehover = function(element) element.selfStyle.color = "#ffffff99" end,
                    click = function(element)
                        --explicit dismissal is what latches the seen flag.
                        g_glossaryToastSeen:Set(true)
                        if m_glossaryToastHost ~= nil and m_glossaryToastHost.valid then
                            m_glossaryToastHost.children = {}
                        end
                    end,
                },
            },
        }
    end

    local ctx = CreateMarkdownRenderContext(self, embedDepth)

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
            ctx.doc = self

            ctx.tokenExtraInfo = {}
            -- trackPositions stamps each token's source line (purely additive; rendering
            -- ignores srcLine) so the rendered blocks below can be tagged for the preview's
            -- content-aware scroll sync (SyncPreviewScroll).
            local tokens = BreakdownRichTags(self:GetTextContent(), nil, { player = self:IsPlayerView(element), trackPositions = true }, ctx.tokenExtraInfo)

            if ctx.tokenExtraInfo.queries ~= nil then
                element.thinkTime = 0.2
                element.data.queries = ctx.tokenExtraInfo.queries
            else
                element.thinkTime = nil
                element.data.queries = nil
            end

            -- Plan 2: resolve this document's skin once per render. Memoized in
            -- the resolver, so re-calling per token would also be cheap, but we
            -- hoist it for clarity and to thread into text/divider/quote.
            local resolvedStylesheet = self:GetResolvedStylesheet()
            local resolvedSkin = resolvedStylesheet.base
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
            -- Page margin: inset content from the page edges. Use hpad/vpad (NOT
            -- pad): the container is built with hpad=6 (params.hpad), and hpad
            -- overrides pad on the horizontal axis, so setting pad alone leaves
            -- the left/right margin stuck at 6px. borderBox keeps the padding
            -- inside the declared width (no overflow). Unset/0 -> restore the
            -- construction defaults (hpad=6, no vpad) so the default skin is
            -- edge-to-edge as before.
            local pageMargin = (resolvedSkin.page or {}).margin
            if type(pageMargin) == "number" and pageMargin > 0 then
                element.hpad = pageMargin
                element.vpad = pageMargin
                element.borderBox = true
            else
                element.hpad = 6
                element.vpad = nil
                element.borderBox = nil
            end

            --Glossary hints: top-level interactive documents only (no
            --embeds, no preview panels), gated by the setting and the
            --per-view mute. Suspended while find-in-page has a term: the
            --broken-underline runs would split hinted words so find could
            --never match them (find wins; hints return when cleared).
            local glossaryOn = embedDepth == 0
                and (not m_noninteractive)
                and (not m_glossaryMuted)
                and m_findTerm == nil
                and g_glossaryHintsSetting:Get() ~= "off"

            ctx.render = {
                skin = resolvedSkin,
                classes = resolvedStylesheet.classes,
                -- Compute once per render: which heading levels (1..5) carry a rule.
                -- nil means no ruled headings -> every text run uses the fast path.
                ruledLevels = HeadingRuleLevels(resolvedSkin),
                usesAlign = SkinUsesAlign(resolvedSkin),
                pageColor = pageColor,
                glossaryHints = glossaryOn,
            }

            local children = RenderMarkdownTokens(ctx, tokens)
            if m_relatedFooter then
                local footer = BuildRelatedFooter(self)
                if footer ~= nil then
                    children[#children + 1] = footer
                end
            end
            if embedDepth == 0 and not m_noninteractive then
                children[#children + 1] = GetGlossaryHoverHost()
                children[#children + 1] = GetGlossaryToastHost()
                children[#children + 1] = GetGlossaryPinHost()
            end
            element.children = children

            --with hints off (muted or setting off), positively remove any
            --glossary markup a pooled label carried over from an earlier
            --hinted render.
            if not glossaryOn then
                StripGlossaryMarks(element)
            end

            --Find-in-page: mark matches over the freshly rendered labels.
            --Runs on every render so marks survive refreshes; clearing the
            --term simply renders without this pass.
            if m_findTerm ~= nil then
                local total, currentLabel = ApplyFindMarks(element, m_findTerm, m_findIndex)
                if m_findCallback ~= nil then
                    m_findCallback(total)
                end
                if currentLabel ~= nil then
                    --layout has not run yet for the new render; retry the
                    --scroll until heights are real. The generation guard
                    --abandons stale retries when the term or index moves on.
                    m_findGeneration = m_findGeneration + 1
                    local generation = m_findGeneration
                    local attempts = 12
                    local function tryScroll()
                        if mod.unloaded or generation ~= m_findGeneration then
                            return
                        end
                        if ScrollFindTargetIntoView(currentLabel) then
                            return
                        end
                        attempts = attempts - 1
                        if attempts > 0 then
                            dmhub.Schedule(0.1, tryScroll)
                        end
                    end
                    dmhub.Schedule(0.05, tryScroll)
                end
            end
        end,

        --Glossary hints: pin/toast/mute events fired up from the rendered
        --labels (pin), the hover machinery (toast), and the document
        --toolbar (mute).
        pinGlossaryTerm = function(element, termid)
            PinGlossaryCard(termid)
        end,
        hoverGlossaryTerm = function(element, termid)
            ShowGlossaryHoverCard(termid)
        end,
        glossaryToast = function(element)
            ShowGlossaryToast()
        end,
        glossaryMute = function(element, muted)
            m_glossaryMuted = muted and true or false
            CloseGlossaryPin()
            GlossaryClearHoverCard()
            element:FireEvent("refreshDocument")
        end,

        --Find-in-page driver. args = {term=string|nil, index=number,
        --callback=fun(count)}: re-renders with term occurrences marked,
        --reports the visible match count through the callback (synchronously,
        --during this event), and scrolls to match number index. A nil or
        --empty term clears the highlights.
        findInPage = function(element, findArgs)
            local term = findArgs ~= nil and findArgs.term or nil
            if term == "" then
                term = nil
            end
            m_findTerm = term
            m_findIndex = findArgs ~= nil and findArgs.index or 1
            m_findCallback = findArgs ~= nil and findArgs.callback or nil
            m_findGeneration = m_findGeneration + 1
            element:FireEvent("refreshDocument")
            m_findCallback = nil
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

--Creates the link/rich-tag autocomplete + link-info service used by the
--journal editors. One instance per editor surface (it keeps popup and
--suppression state); entry points are input-agnostic and take the input
--element to inspect. opts:
--  GetDocument()          - returns the MarkdownDocument being edited
--                           (annotations feed rich-tag previews); called at
--                           use time so live document swaps are respected.
--  OnTextChanged(newText) - optional; fired after the service rewrites the
--                           input's text (accepting a completion, link
--                           suggestion fixups) so the host can refresh
--                           previews and character counts.
--Returns { Update, Dismiss, UpdateLinkInfo, FindLinkContext, state }.
local function CreateMarkdownAutocomplete(opts)
    local function NotifyTextChanged(newText)
        if opts.OnTextChanged ~= nil then
            opts.OnTextChanged(newText)
        end
    end

    --Positions a popup for the given input. Hosts can override placement via
    --opts.GetPopupPositioning(inputElement, bracketPos) (the live editor
    --anchors popups below the whole block input); the default anchors at the
    --opening bracket so the popup stays stable as the user types.
    local function ApplyPopupPositioning(inputElement, bracketPos)
        if opts.GetPopupPositioning ~= nil then
            inputElement.popupPositioning = opts.GetPopupPositioning(inputElement, bracketPos)
            return
        end
        local anchorPos = bracketPos and inputElement:GetCharWorldPosition(bracketPos) or nil
        if anchorPos ~= nil then
            inputElement.popupPositioning = anchorPos
        else
            inputElement.popupPositioning = "panel"
        end
    end

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
        ["Bubble"]       = "implStatus3",
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
                                    NotifyTextChanged(newText)
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
        ApplyPopupPositioning(inputElement, bracketPos)
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
        local doc = opts.GetDocument()
        if doc ~= nil and doc.annotations ~= nil then
            -- The tag key in annotations is the tagText itself (e.g. "encounter:Name")
            -- Also check with disambiguation suffixes (-1, -2, etc.)
            for k, v in pairs(doc.annotations) do
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

        ApplyPopupPositioning(inputElement, bracketPos)
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
            NotifyTextChanged(newText)
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
            NotifyTextChanged(newText)
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
            NotifyTextChanged(newText)
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
            NotifyTextChanged(newText)
            inputElement:SetTextAndCaret(targetCaretPos, newText)
            return
        end

        if result.isPrefix then
            -- Prefix suggestion (e.g. "item:"): insert just the prefix,
            -- keep the bracket open, and re-trigger autocomplete.
            DismissAutocomplete(inputElement)
            local newText = before .. "[" .. result.link .. after
            local targetCaretPos = #before + 1 + #result.link
            NotifyTextChanged(newText)
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
        NotifyTextChanged(newText)
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
                            local doc = opts.GetDocument()
                            if doc ~= nil and doc.annotations ~= nil and result.link then
                                for k, v in pairs(doc.annotations) do
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
        ApplyPopupPositioning(inputElement, bracketPos)
        inputElement.popup = popup
    end

    return {
        Update = UpdateAutocomplete,
        Dismiss = DismissAutocomplete,
        UpdateLinkInfo = UpdateLinkInfo,
        FindLinkContext = FindLinkContext,
        state = autocompleteState,
    }
end

--Bottom strip of rich-tag annotation editors (encounter pickers, dice
--configs, image selectors, ...). Scans the content for [[tags]] whose
--registry entry has hasEdit, CREATES any missing annotation object on the
--document (this is what backs a freshly typed tag: display renders nothing
--for a tag with no annotation), and shows each tag's editor widget.
--Shared by the classic and live editors. Drive it by firing "editDocument"
--with the current content, or "refreshDocument" with a doc to pull from.
--opts.GetDocument() returns the MarkdownDocument being edited.
local function CreateAnnotationsPanel(opts)
    local m_richPanels = {}

    return gui.Panel {
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
            local doc = opts.GetDocument()
            if doc == nil then
                return
            end

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

                        local richTag = doc.annotations[candidate]
                        --patch over any possible bugs where the saved annotation is not a proper table.
                        if richTag ~= nil and getmetatable(richTag) == nil then
                            richTag = nil
                            doc.annotations[candidate] = nil
                        end

                        if richTag == nil and MarkdownDocument.IsLegalAnnotationKey(candidate) then
                            richTag = richTagInfo.Create()
                            richTag.identifier = suffix or false
                            doc.annotations[candidate] = richTag
                        end

                        if richTag ~= nil and richTagInfo.hasEdit ~= "hidden" then
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
end

--Formatting toolbar shared by the classic and live editors: inline wraps
--(bold/italic/...), heading and list line prefixes, spoilers, link/divider
--inserts, media/widget rich tags, and the stylesheet picker. opts:
--  GetInput()               - returns the input to apply an action to. May
--                             activate an editor first (the live editor
--                             reactivates the last edited block, since
--                             clicking a button defocuses and commits it).
--                             Return nil to make the action a no-op.
--  GetStylesheetId()        - current stylesheet id ("" for none).
--  OnStylesheetChanged(id)  - host-specific stylesheet application.
local function CreateMarkdownToolbar(opts)
    --caretOverride: hosts that had to reactivate an editor pass the intended
    --caret explicitly, because SetTextAndCaret defers actual caret placement
    --across the input's focus acquisition and input.caretPosition cannot be
    --trusted yet. Overrides collapse the selection at that position.
    local function InsertAction(input, action, caretOverride)
        local text = input.text or ""
        local caret = caretOverride or input.caretPosition or #text
        local anchor = caretOverride or input.selectionAnchorPosition or caret
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

    local function ApplyAction(action)
        local input, caretOverride = opts.GetInput()
        if input == nil or not input.valid then
            return
        end
        InsertAction(input, action, caretOverride)
    end

    local function WrapHandler(prefix, suffix)
        return function() ApplyAction{
            mode = "wrap", prefix = prefix, suffix = suffix,
        } end
    end

    local function LineHandler(prefix)
        return function() ApplyAction{
            mode = "linePrefix", prefix = prefix,
        } end
    end

    local function InsertHandler(text, caretOffset)
        return function() ApplyAction{
            mode = "insert", text = text, caretOffset = caretOffset,
        } end
    end

    local function RichTagHandler(tagName)
        return function() ApplyAction{
            mode = "insert",
            text = string.format("[[%s]]\n", tagName),
        } end
    end

    --Codex Design System treatment (tokens/colors.css + effects.css and the
    --Button/Select specs): controls are bordered ghosts on the warm-black
    --surface ladder with the single gold accent at graded alphas. Hover
    --brightens the border 0.28 -> 0.6 and steps the surface, and nothing
    --moves, fades, or casts a shadow.
    --accent updated from gold (#c8a45a) to white by request; the graded
    --alphas are unchanged so the design's weights are preserved.
    local DS_SURFACE_2   = "#1a1a1e"   --buttons / inputs
    local DS_SURFACE_3   = "#222228"   --hover surface
    local DS_TEXT        = "#e4ddd0"   --parchment body text
    local DS_GOLD_BD     = "#ffffff47" --white @ 0.28: control border
    local DS_GOLD_BD_HI  = "#ffffff99" --white @ 0.6: hover/active border
    local DS_GOLD        = "#ffffff"   --the single accent
    local DS_GOLD_DIM    = "#ffffff1f" --white @ 0.12: selected/accent fill
    local DS_GOLD_FILL_HI = "#ffffff59" --white @ 0.35: accent hover fill
    local DS_GOLD_BD_LO  = "#ffffff26" --white @ 0.15: hairline dividers
    local DS_SURFACE     = "#131315"   --popover surface
    local DS_TEXT_SOFT   = "#7a7468"   --warm-muted secondary labels

    --Applied to the toolbar root via ThemeEngine.MergeTokens, the documented
    --path for overriding inherited theme styling on one control subtree.
    --These are hardcoded Codex Design System values rather than theme tokens
    --by explicit decision: the design language is being trialed on this one
    --surface before deciding whether to author it as a real theme.
    --NOTE: no cornerRadius in these rules, deliberately. The user's theme
    --choice (default vs default-rounded) owns corner radii; our design
    --treatment only overrides color and border weight, so squared/rounded
    --preference is honored throughout the toolbar.
    --selector arity matters: the theme styles text buttons via
    --{label, button}, so these rules must carry both selectors (plus
    --states) to outrank the theme's whiteish border and fill.
    local dsToolbarStyles = {
        {
            selectors = { "label", "button" },
            bgimage = "panels/square.png",
            bgcolor = DS_SURFACE_2,
            borderColor = DS_GOLD_BD,
            border = 1,
            color = DS_TEXT,
        },
        {
            selectors = { "label", "button", "hover" },
            bgcolor = DS_SURFACE_3,
            borderColor = DS_GOLD_BD_HI,
        },
        {
            selectors = { "label", "button", "press" },
            bgcolor = DS_SURFACE,
            borderColor = DS_GOLD_BD_HI,
        },
        {
            selectors = { "dropdown" },
            bgimage = "panels/square.png",
            bgcolor = DS_SURFACE_2,
            borderColor = DS_GOLD_BD,
            border = 1,
        },
        {
            selectors = { "dropdown", "hover" },
            bgcolor = DS_SURFACE_3,
            borderColor = DS_GOLD_BD_HI,
        },
        {
            selectors = { "label", "dropdownLabel" },
            color = DS_TEXT,
            fontSize = 14,
        },
        {
            selectors = { "label", "dropdownOption" },
            fontSize = 14,
        },
    }

    local function ToolbarButton(label, fontSize, width, handler)
        return gui.Button{
            text = label,
            width = width or 30,
            height = 30,
            fontSize = fontSize or 15,
            valign = "center",
            hmargin = 3,
            press = handler,
        }
    end

    --hairline between control groups (design: 1px x 20px, gold @ 0.15,
    --with the design's wider inter-group gap).
    local function GroupDivider()
        return gui.Panel{
            width = 1,
            height = 20,
            valign = "center",
            hmargin = 9,
            bgimage = "panels/square.png",
            bgcolor = DS_GOLD_BD_LO,
        }
    end

    --the curated "earned" text-color palette from the design system; the
    --free color wheel is deliberately gone. Picking a swatch wraps the
    --selection in <color=hex>.
    local dsPalette = {
        { name = "Gold",      hex = "#c8a45a" },
        { name = "Parchment", hex = "#e4ddd0" },
        { name = "Healthy",   hex = "#2D6A4F" },
        { name = "Winded",    hex = "#7A4A18" },
        { name = "Dying",     hex = "#6B2020" },
        { name = "Success",   hex = "#4db88c" },
        { name = "Warning",   hex = "#e8a030" },
        { name = "Failure",   hex = "#c94040" },
    }

    local function ColorSwatch(entry, host)
        return gui.Panel{
            width = 26,
            height = 26,
            hmargin = 4,
            vmargin = 4,
            bgimage = "panels/square.png",
            bgcolor = entry.hex,
            cornerRadius = 13,
            border = 2,
            borderColor = "#0a0a0b",
            styles = {
                {
                    selectors = { "hover" },
                    borderColor = DS_GOLD_BD_HI,
                },
            },
            press = function(element)
                host.popup = nil
                WrapHandler(string.format("<color=%s>", entry.hex), "</color>")()
            end,
        }
    end

    local function ColorButton()
        local button
        button = gui.Button{
            text = "Color",
            width = 64,
            height = 30,
            fontSize = 14,
            valign = "center",
            hmargin = 3,
            press = function(element)
                if element.popup ~= nil then
                    element.popup = nil
                    return
                end
                local rows = {}
                for rowIndex = 0, 1 do
                    local swatches = {}
                    for col = 1, 4 do
                        local entry = dsPalette[rowIndex * 4 + col]
                        if entry ~= nil then
                            swatches[#swatches + 1] = ColorSwatch(entry, element)
                        end
                    end
                    rows[#rows + 1] = gui.Panel{
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",
                        children = swatches,
                    }
                end
                element.popupPositioning = "panel"
                element.popup = gui.Panel{
                    width = "auto",
                    height = "auto",
                    valign = "bottom",
                    halign = "right",
                    --themed surface classes (same as the autocomplete popup)
                    --so the menu chrome, including corner radius, follows
                    --the user's theme.
                    gui.Panel{
                        classes = { "bordered", "bg" },
                        flow = "vertical",
                        width = "auto",
                        height = "auto",
                        pad = 8,
                        borderBox = false,
                        children = rows,
                    },
                }
            end,
        }
        return button
    end

    local headingOptions = {
        { id = "",       text = "Heading" },
        { id = "# ",     text = "H1" },
        { id = "## ",    text = "H2" },
        { id = "### ",   text = "H3" },
        { id = "#### ",  text = "H4" },
        { id = "##### ", text = "H5" },
        { id = "> ",     text = "Quote" },
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
    --Draw Steel! lives in the widget menu but is not a rich tag: it inserts
    --the roll-link markup, so it gets a sentinel id the change handler
    --dispatches specially (a tag id can never start with "//").
    widgetOptions[#widgetOptions + 1] = { id = "//drawsteel", text = "Draw Steel!" }

    local toolbarRow = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        valign = "top",
        halign = "left",
        borderBox = true,
        --design metrics: 11px vertical breathing room, 16px edge inset.
        hpad = 16,
        vpad = 10,

        --group: history. Only hosts that supply an undo implementation get
        --these (the live editor); the classic editor relies on the input's
        --native undo. The wrapper keeps the positional children list free of
        --nil holes when the group is absent.
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            valign = "center",
            children = (opts.OnUndo ~= nil) and {
                ToolbarButton("Undo", 14, 52, function() opts.OnUndo() end),
                ToolbarButton("Redo", 14, 52, function()
                    if opts.OnRedo ~= nil then opts.OnRedo() end
                end),
                GroupDivider(),
            } or {},
        },

        --group: text style (typographic glyphs per the design).
        ToolbarButton("<b>B</b>", 15, 30, WrapHandler("**", "**")),
        ToolbarButton("<i>I</i>", 15, 30, WrapHandler("*", "*")),
        ToolbarButton("<u>U</u>", 15, 30, WrapHandler("__", "__")),
        ToolbarButton("<s>S</s>", 15, 30, WrapHandler("~~", "~~")),

        GroupDivider(),

        --group: marks.
        ColorButton(),
        ToolbarButton("Spoiler", 14, 66, WrapHandler("{", "}")),
        gui.Dropdown{
            width = 100, height = 30, idChosen = "", hmargin = 3,
            options = headingOptions,
            change = function(element)
                if element.idChosen ~= "" then
                    LineHandler(element.idChosen)()
                    element.idChosen = ""
                end
            end,
        },

        GroupDivider(),

        --group: blocks.
        ToolbarButton("List",    14, 52, LineHandler("* ")),
        ToolbarButton("Divider", 14, 68, InsertHandler("\n---\n", 5)),
        ToolbarButton("Link",    14, 50, InsertHandler("[]", 1)),

        --group: insert. Not pushed to the right edge: a "100% available"
        --spacer renders zero wide here, and it fills the wrap line exactly,
        --which makes the wrap pass reserve a phantom second line (the row
        --renders one line of controls but two lines of height).
        gui.Dropdown{
            width = 118, height = 30, idChosen = "", hmargin = 3,
            options = mediaOptions,
            change = function(element)
                if element.idChosen ~= "" then
                    RichTagHandler(element.idChosen)()
                    element.idChosen = ""
                end
            end,
        },

        gui.Dropdown{
            width = 118, height = 30, idChosen = "", hmargin = 3,
            options = widgetOptions,
            change = function(element)
                if element.idChosen == "//drawsteel" then
                    --not a rich tag: insert the Draw Steel! roll link.
                    InsertHandler('[[//link "Draw Steel!"|Draw Steel!]]')()
                    element.idChosen = ""
                elseif element.idChosen ~= "" then
                    RichTagHandler(element.idChosen)()
                    element.idChosen = ""
                end
            end,
        },

    }

    --Bar 4 per the handoff: the stylesheet picker is its own row with an
    --uppercase tracked label, not a tail entry on the format bar.
    local stylesheetRow = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        valign = "top",
        halign = "left",
        borderBox = true,
        hpad = 16,
        vpad = 8,
        gui.Label{
            text = "STYLESHEET",
            fontSize = 11,
            bold = true,
            color = DS_TEXT_SOFT,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            rmargin = 14,
        },
        gui.Dropdown{
            width = 220,
            height = 30,
            halign = "left",
            options = JournalStylesheet.PickerOptions(),
            idChosen = opts.GetStylesheetId() or "",
            change = function(element)
                opts.OnStylesheetChanged(element.idChosen)
            end,
        },
    }

    local function ToolbarHairline()
        return gui.Panel{
            width = "100%",
            height = 1,
            bgimage = "panels/square.png",
            bgcolor = DS_GOLD_BD_LO,
        }
    end

    --the design separates every chrome row with a gold hairline; the
    --toolbar carries its own rules so both editors get them. The design
    --styles live on this wrapper so the stylesheet row's dropdown inherits
    --them too.
    return gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "top",
        bmargin = 6,
        styles = ThemeEngine.MergeTokens(dsToolbarStyles),
        toolbarRow,
        ToolbarHairline(),
        stylesheetRow,
        ToolbarHairline(),
    }
end

--Obsidian-style live edit surface: the journal's editor (see EditPanel).
--The document is partitioned into blocks (PartitionTokensIntoBlocks); each
--block renders through RenderMarkdownTokens exactly like display mode, with
--a floating click-guard over it. Clicking a block swaps it for a multiline
--input seeded with that block's source lines; deactivating (click away,
--escape, focus loss) splices the edited lines back into the document and
--re-renders. Gap lines between blocks (blanks, false ??? regions) are
--preserved verbatim across splices.
--v1 limitations (see JOURNAL_EDITOR_PLAN.md in the dmhubclient repo):
--selection is confined to the active block; interactive widgets inside
--blocks are inert while this surface is up (the guard captures clicks);
--remote edits are ignored while a block is actively being edited.
function MarkdownDocument:LiveEditPanel(args)
    args = args or {}

    local resultPanel
    local m_doc = self

    local m_lines = {}       --master document state, as normalized lines.
    local m_blocks = {}      --current partition of m_lines into edit blocks.
    local m_blockPanels = {} --pooled per-block wrapper panels, by block index.
    local m_activeIndex = nil
    local m_editInput = nil  --single input reused for whichever block is active.
    local m_activateTime = 0 --guards the focus watchdog against the focus race.
    local m_lastEdit = nil   --{line, caret} of the most recent edit; lets the
                             --toolbar reactivate where the user was typing.
    local m_activeRenderedHeight = nil --the active block's rendered height,
                             --measured at activation; held as the edit
                             --input's minHeight so swapping a tall rendered
                             --block (widget, table, heading rule) for its
                             --shorter raw source does not make the content
                             --below it jump up.
    local m_findTerm = nil   --find-in-page state (findInPage event), marked
                             --over the rendered blocks exactly as in
                             --DisplayPanel. The active block's input is
                             --never marked: injected mark tags would become
                             --part of the block's raw source.
    local m_findIndex = 1
    local m_findCallback = nil
    local m_findGeneration = 0
    local m_savedContent = nil --the doc content as of the last load/save;
                             --distinguishes local unsaved work from a clean
                             --view so remote refreshes never clobber edits.
    local m_renderGeneration = 0 --bumped when blocks must re-render even
                             --with unchanged source (saves adopt merged
                             --content and annotation configs; stylesheet
                             --changes; remote adoption).
    local m_undoStack = {}   --content snapshots, one per committed change;
                             --drives Ctrl+Z / the toolbar Undo button.
    local m_redoStack = {}   --snapshots popped by undo, replayed by Ctrl+Y.

    --link/rich-tag autocomplete + link-info popups on the active block input,
    --shared machinery with the classic editor.
    local m_autocomplete = CreateMarkdownAutocomplete{
        GetDocument = function()
            return m_doc
        end,
        OnTextChanged = function(newText)
            --the service just rewrote the input's text and will re-focus it;
            --renew the watchdog grace period so the block is not committed
            --mid-completion.
            m_activateTime = dmhub.Time()
        end,
        --no GetPopupPositioning override: use the service default, which
        --anchors the popup at the typed bracket (GetCharWorldPosition) so
        --suggestions appear at the caret rather than pinned to the block's
        --frame at the end of the line.
    }

    --rich-tag annotation editor strip (encounter pickers, dice configs...),
    --shared machinery with the classic editor. Its scan also CREATES missing
    --annotation objects for typed tags, which the block renderer needs: a
    --tag with no annotation renders as nothing. Therefore the scan must run
    --after every content change and BEFORE blocks re-render.
    local m_annotationsPanel = CreateAnnotationsPanel{
        GetDocument = function()
            return m_doc
        end,
    }

    local function RefreshAnnotations(content)
        m_annotationsPanel:FireEvent("editDocument", content)
    end

    local m_listPanel
    local m_pagePanel --the scrollable page surface; painted with the
                      --stylesheet's page color each refresh, like DisplayPanel.

    --forward declarations: these reference each other from closures.
    local ActivateBlock
    local DeactivateBlock
    local RefreshBlockPanels

    local function GetContent()
        return table.concat(m_lines, "\n")
    end

    local function SetLinesFromContent(content)
        content = (content or ""):gsub("\v", "\n"):gsub("\r", "")
        m_lines = string.split_allow_duplicates(content, "\n")
    end

    local function BlockSource(block)
        return table.concat(m_lines, "\n", block.lineStart, block.lineEnd)
    end

    --Snapshot the pre-change content so Ctrl+Z can restore it. One entry per
    --committed change (block granularity); any new change invalidates redo.
    local UNDO_LIMIT = 50
    local function PushUndo(content)
        if m_undoStack[#m_undoStack] == content then
            return
        end
        m_undoStack[#m_undoStack + 1] = content
        if #m_undoStack > UNDO_LIMIT then
            table.remove(m_undoStack, 1)
        end
        m_redoStack = {}
    end

    local function IsHeadingLine(line)
        return line ~= nil and line:match("^#+[ \t]") ~= nil
    end

    --Long prose runs tokenize as one text token, so the partitioner hands
    --back blocks that can span a heading plus everything around it. Split
    --those so each heading line edits as its own block (letting the input
    --mirror the heading's rendered size; see BlockEditFont) while the prose
    --between headings stays one block. Only blocks whose stamped tokens are
    --all plain text are split - tables, widgets, styleblocks, and collapse
    --wrappers keep their existing grouping. Sub-blocks re-tokenize their own
    --source; per-block token line stamps are only used for rendering, so
    --relative positions are fine.
    local function SplitHeadingBlocks(blocks)
        local result = {}
        for _, block in ipairs(blocks) do
            local textOnly = true
            for _, token in ipairs(block.tokens) do
                if token.srcLine ~= nil and token.type ~= "text" and token.type ~= "justification" then
                    textOnly = false
                    break
                end
            end
            local hasHeading = false
            if textOnly and block.lineEnd > block.lineStart then
                for i = block.lineStart, block.lineEnd do
                    if IsHeadingLine(m_lines[i]) then
                        hasHeading = true
                        break
                    end
                end
            end

            if not (textOnly and hasHeading) then
                result[#result + 1] = block
            else
                --blank edge lines belong to no block (the splice model
                --preserves them verbatim), so trim them off each run.
                local function EmitRun(s, e)
                    while s <= e and trim(m_lines[s] or "") == "" do s = s + 1 end
                    while e >= s and trim(m_lines[e] or "") == "" do e = e - 1 end
                    if s > e then
                        return
                    end
                    local src = table.concat(m_lines, "\n", s, e)
                    result[#result + 1] = {
                        lineStart = s,
                        lineEnd = e,
                        tokens = BreakdownRichTags(src, nil, { player = false }),
                    }
                end
                local runStart = nil
                for i = block.lineStart, block.lineEnd do
                    if IsHeadingLine(m_lines[i]) then
                        if runStart ~= nil then
                            EmitRun(runStart, i - 1)
                            runStart = nil
                        end
                        EmitRun(i, i)
                    elseif runStart == nil then
                        runStart = i
                    end
                end
                if runStart ~= nil then
                    EmitRun(runStart, block.lineEnd)
                end
            end
        end
        return result
    end

    --Tokenize and partition the current content. Note player=false: ranges
    --must map to the true source (StripSpoilers rewrites the string, which
    --would corrupt splicing), and anyone on this surface can already see the
    --raw source in the input, exactly like the classic edit tab.
    local function RebuildBlockData()
        local tokens = BreakdownRichTags(GetContent(), nil, { player = false, trackPositions = true })
        m_blocks = SplitHeadingBlocks(MarkdownDocument.PartitionTokensIntoBlocks(tokens))

        if #m_blocks == 0 then
            --empty document: synthesize one block covering everything so
            --there is something to click on.
            m_blocks = {
                {
                    lineStart = 1,
                    lineEnd = math.max(1, #m_lines),
                    tokens = {},
                    placeholder = true,
                },
            }
        end
    end

    --If the doc grows past its limit the input refuses further characters;
    --budget = whatever the rest of the document is not using.
    local function ActiveCharacterBudget(blockSourceLength)
        return math.max(1, CustomDocument.MaxLength - (#GetContent() - blockSourceLength))
    end

    --Splices the active block's input text back into m_lines. Returns the
    --resulting change in total line count (0 if nothing was active).
    local function CommitActiveBlock()
        if m_activeIndex == nil or m_editInput == nil then
            return 0
        end
        local block = m_blocks[m_activeIndex]
        if block == nil then
            return 0
        end

        local oldCount = block.lineEnd - block.lineStart + 1
        local editedText = (m_editInput.text or ""):gsub("\v", "\n"):gsub("\r", "")
        local edited = string.split_allow_duplicates(editedText, "\n")

        local oldContent = GetContent()

        local newLines = {}
        for i = 1, block.lineStart - 1 do
            newLines[#newLines + 1] = m_lines[i]
        end
        for _, line in ipairs(edited) do
            newLines[#newLines + 1] = line
        end
        for i = block.lineEnd + 1, #m_lines do
            newLines[#newLines + 1] = m_lines[i]
        end
        m_lines = newLines

        if GetContent() ~= oldContent then
            PushUndo(oldContent)
        end

        return #edited - oldCount
    end

    --Master content with the active block's uncommitted input text spliced
    --in virtually; used for save/dirty checks without disturbing the edit.
    local function GetContentIncludingActive()
        if m_activeIndex == nil or m_editInput == nil then
            return GetContent()
        end
        local block = m_blocks[m_activeIndex]
        if block == nil then
            return GetContent()
        end

        local parts = {}
        if block.lineStart > 1 then
            parts[#parts + 1] = table.concat(m_lines, "\n", 1, block.lineStart - 1)
        end
        parts[#parts + 1] = m_editInput.text or ""
        if block.lineEnd < #m_lines then
            parts[#parts + 1] = table.concat(m_lines, "\n", block.lineEnd + 1, #m_lines)
        end
        return table.concat(parts, "\n")
    end

    --1-based line the caret is on within the input's text (same counting
    --technique as SyncPreviewScroll; caretPosition is 0-based).
    local function CaretLine(input)
        local text = input.text or ""
        local caret = input.caretPosition or 0
        local line = 1
        for i = 1, math.min(caret, #text) do
            if text:sub(i, i) == "\n" then
                line = line + 1
            end
        end
        return line
    end

    local function CountLines(text)
        local _, newlines = (text or ""):gsub("\n", "")
        return newlines + 1
    end

    --Heading level (1-6) when the block's source is a single heading line,
    --nil otherwise. Used to mirror the rendered heading treatment while the
    --block is being edited.
    local function BlockHeadingLevel(src)
        local line = trim(src or "")
        if line == "" or line:find("\n", 1, true) ~= nil then
            return nil
        end
        local hashes = line:match("^(#+)[ \t]")
        if hashes ~= nil and #hashes <= 6 then
            return #hashes
        end
        return nil
    end

    --The font size the live-edit input should use for a block, plus the
    --skin's heading entry when the block is a heading: body size normally,
    --scaled by the heading's sizePct so entering edit mode keeps the text
    --at the size it renders at. The default skin mirrors g_markdownStyle
    --(200%..120%), so unskinned headings match too.
    local function BlockEditFont(src, skin)
        local size = CustomDocument.ScaleFontSize(14)
        local heading = nil
        local level = BlockHeadingLevel(src)
        if level ~= nil then
            heading = ((skin or {}).headings or {})[level] or {}
            local pct = heading.sizePct or 100
            if pct ~= 100 then
                size = size * pct / 100
            end
        end
        return size, heading
    end

    local function EnsureEditInput()
        if m_editInput ~= nil and m_editInput.valid then
            return m_editInput
        end

        m_editInput = gui.Input{
            --match the rendered document: body text renders at
            --ScaleFontSize(14) in the theme's label face (inputs default to
            --the @input face, so re-point the base face at @label), so the
            --block barely changes appearance when it swaps to the input.
            --The default input chrome (dark @bg fill + border) is stripped
            --so the stylesheet's page color shows through the edit area,
            --exactly like the rendered blocks around it. The stylesheet's
            --body/heading font face, size, and ink color are applied
            --per-activation in RefreshBlockPanels (they change with the
            --skin and with the block being a heading).
            --pad/margin zeroed to match the rendered labels (pad 0), so the
            --block's height barely changes when it swaps to the input;
            --minHeight is set per-activation to one line of the block's
            --edit font rather than a fixed 30px for the same reason.
            styles = ThemeEngine.MergeTokens({
                {
                    selectors = { "input" },
                    fontFace = "@label",
                    bgcolor = "#00000000",
                    border = 0,
                    pad = 0,
                    margin = 0,
                },
            }),
            width = "100%",
            height = "auto",
            multiline = true,
            textAlignment = "topleft",
            fontSize = CustomDocument.ScaleFontSize(14),
            selectAllOnFocus = false,

            thinkTime = 0.2,
            editlag = 0.3,

            edit = function(element)
                --track the live caret while it is trustworthy (focused);
                --this is what the toolbar reactivates after its click
                --defocuses and commits the block.
                if m_activeIndex ~= nil then
                    local block = m_blocks[m_activeIndex]
                    if block ~= nil then
                        m_lastEdit = { line = block.lineStart, caret = element.caretPosition }
                    end
                end
                m_autocomplete.Update(element)
                --keep the annotation strip live while typing, like the
                --classic editor; this also pre-creates annotations so the
                --widget renders the moment the block commits.
                RefreshAnnotations(GetContentIncludingActive())
            end,

            caretReady = function(element)
                m_autocomplete.Update(element)
            end,

            --autocomplete dismissal + link-info refresh, mirroring the
            --classic editor's input think handler.
            think = function(element)
                if m_activeIndex ~= nil and element.hasInputFocus then
                    local block = m_blocks[m_activeIndex]
                    if block ~= nil then
                        m_lastEdit = { line = block.lineStart, caret = element.caretPosition }
                    end
                end
                if #m_autocomplete.state.results > 0 then
                    local searchText, bracketPos, contextType = m_autocomplete.FindLinkContext(element.text or "", element.caretPosition or 0)
                    if searchText == nil or ((contextType == "link" or contextType == "linkTarget") and #searchText < 1) then
                        m_autocomplete.Dismiss(element)
                    end
                else
                    m_autocomplete.UpdateLinkInfo(element)
                end
            end,

            --fires when the input loses focus after edits.
            change = function(element)
                if element.popup ~= nil then
                    --an autocomplete/link popup is mid-interaction; the
                    --service re-focuses the input itself after accepting.
                    return
                end
                DeactivateBlock()
            end,

            --escape is handled by the surface's captureEscape route (see
            --resultPanel), which outranks the journal window's close handler;
            --a handler here too would deactivate (clearing captureEscape)
            --before the capture pass resolves, letting the same keypress
            --fall through and close the whole journal.

            --arrow keys at the block's edge flow into the neighboring block,
            --so the cursor travels the document like a single continuous
            --editor. The engine fires these on every keypress while focused;
            --we only act at the boundary lines.
            uparrow = function(element)
                if m_activeIndex ~= nil and m_activeIndex > 1
                   and CaretLine(element) <= 1 then
                    ActivateBlock(m_activeIndex - 1, "end")
                end
            end,

            downarrow = function(element)
                if m_activeIndex ~= nil and m_activeIndex < #m_blocks
                   and CaretLine(element) >= CountLines(element.text) then
                    ActivateBlock(m_activeIndex + 1, "start")
                end
            end,
        }
        return m_editInput
    end

    local function CreateBlockPanel()
        local ctx = CreateMarkdownRenderContext(m_doc, 0)

        local contentPanel = gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            valign = "top",
            halign = "left",
        }

        local inputHost = gui.Panel{
            classes = { "collapsed" },
            flow = "vertical",
            width = "100%",
            height = "auto",
            valign = "top",
        }

        --The wrapper itself is the click target: it carries a hit-testable
        --transparent background and the press handler, and the rendered
        --content is made non-interactive after each render
        --(MakeNonInteractiveRecursive in RefreshBlockPanels). This makes the
        --whole block clickable, leaves widgets inside inert while live
        --editing, and avoids overlay geometry entirely (a floating
        --height="100%" child of an auto-height parent does not track the
        --block's real bounds). bgcolor lives in styles, never inline, so the
        --hover highlight can apply; the editing class suppresses it while
        --the block hosts the input.
        local wrapper
        wrapper = gui.Panel{
            classes = { "liveEditBlock" },
            flow = "vertical",
            width = "100%",
            height = "auto",
            valign = "top",
            halign = "left",
            vmargin = 2,
            --I-beam over editable chunks: signals click-to-type like any
            --text editor, alongside the (deliberately faint) hover wash.
            hoverCursor = "text",
            bgimage = "panels/square.png",
            --selector arity: the theme paints bare panels with its dark
            --surface via a {panel} rule, so these must carry
            --{panel, liveEditBlock} to stay transparent and let the
            --stylesheet's page color show through. Hover wash is gold-dim
            --so it reads on both dark and parchment pages.
            styles = {
                {
                    selectors = { "panel", "liveEditBlock" },
                    bgcolor = "#00000000",
                },
                {
                    selectors = { "panel", "liveEditBlock", "hover" },
                    --deliberately faint: just enough to signal the block is
                    --clickable without strobing as the mouse travels the page.
                    bgcolor = "#ffffff0a",
                },
                {
                    selectors = { "panel", "liveEditBlock", "hover", "editing" },
                    bgcolor = "#00000000",
                },
            },
            press = function(element)
                --map the click's position within the block to a source line
                --and column so the caret lands near where the user aimed.
                --mousePoint is normalized within the panel with y running
                --bottom-up (Unity convention); invert for a from-top
                --fraction. Approximate (rendered heights vary per line and
                --the face is proportional), but far better than always
                --landing at the end.
                local fraction = nil
                local xFraction = nil
                local point = element.mousePoint
                if point ~= nil then
                    fraction = 1 - point.y
                    xFraction = point.x
                end
                ActivateBlock(element.data.index, {
                    fraction = fraction,
                    xFraction = xFraction,
                    pixelWidth = element.renderedWidth,
                })
            end,
            data = {
                index = nil,
                ctx = ctx,
                contentPanel = contentPanel,
                inputHost = inputHost,
                placeholderLabel = nil,
            },
            contentPanel,
            inputHost,
        }
        return wrapper
    end

    --Find-in-page over the live editor: walk the block wrappers in document
    --order, marking matches in their rendered labels (same marks and scroll
    --scheme as DisplayPanel). Placeholder blocks and the active block are
    --skipped - the active block shows its raw source in an input, and marks
    --injected there would be committed into the document. Runs at the end
    --of every RefreshBlockPanels pass; the pass renders fresh labels
    --whenever a term is active (see the generation bump there), so a label
    --is never marked twice (re-marking would nest mark tags).
    local function ApplyLiveFindMarks()
        if m_findTerm == nil then
            return
        end
        local total = 0
        local currentLabel = nil
        for index, block in ipairs(m_blocks) do
            local wrapper = m_blockPanels[index]
            if (not block.placeholder) and index ~= m_activeIndex
               and wrapper ~= nil and wrapper.valid
               and wrapper.data.contentPanel ~= nil and wrapper.data.contentPanel.valid then
                local rel = m_findIndex - total
                if rel < 1 then
                    rel = nil
                end
                local cnt, cur = ApplyFindMarks(wrapper.data.contentPanel, m_findTerm, rel)
                if cur ~= nil then
                    currentLabel = cur
                end
                total = total + cnt
            end
        end
        if m_findCallback ~= nil then
            m_findCallback(total)
        end
        if currentLabel ~= nil then
            --layout has not run for the fresh labels; retry the scroll
            --until heights are real. The generation guard abandons stale
            --retries when the term or index moves on.
            m_findGeneration = m_findGeneration + 1
            local generation = m_findGeneration
            local attempts = 12
            local function tryScroll()
                if mod.unloaded or generation ~= m_findGeneration then
                    return
                end
                if ScrollFindTargetIntoView(currentLabel) then
                    return
                end
                attempts = attempts - 1
                if attempts > 0 then
                    dmhub.Schedule(0.1, tryScroll)
                end
            end
            dmhub.Schedule(0.05, tryScroll)
        end
    end

    RefreshBlockPanels = function()
        --with an active find term every pass must render fresh labels so
        --the mark pass at the end never marks an already-marked label and
        --index moves repaint the current-match color.
        if m_findTerm ~= nil then
            m_renderGeneration = m_renderGeneration + 1
        end

        --resolve the skin once per refresh and share it into every block's
        --render context, mirroring what DisplayPanel does per render.
        local resolvedStylesheet = m_doc:GetResolvedStylesheet()
        local resolvedSkin = resolvedStylesheet.base
        local render = {
            skin = resolvedSkin,
            classes = resolvedStylesheet.classes,
            ruledLevels = HeadingRuleLevels(resolvedSkin),
            usesAlign = SkinUsesAlign(resolvedSkin),
            pageColor = SkinColor((resolvedSkin.page or {}).bgcolor),
        }

        --paint the stylesheet's page onto the live-edit surface, exactly as
        --DisplayPanel does: page color behind all blocks so skinned content
        --sits on its intended background, and the page margin inset.
        --Cleared when the skin sets none so the default look is untouched.
        if m_pagePanel ~= nil then
            if render.pageColor then
                m_pagePanel.bgimage = "panels/square.png"
                m_pagePanel.bgcolor = render.pageColor
            else
                m_pagePanel.bgimage = nil
                m_pagePanel.bgcolor = nil
            end
            local pageMargin = (resolvedSkin.page or {}).margin
            if type(pageMargin) == "number" and pageMargin > 0 then
                m_pagePanel.hpad = pageMargin
                m_pagePanel.vpad = pageMargin
                m_pagePanel.borderBox = true
            else
                m_pagePanel.hpad = nil
                m_pagePanel.vpad = nil
                m_pagePanel.borderBox = nil
            end
        end

        --the editor surface itself can be destroyed out from under a queued
        --refresh (dialog closed, Lua reload); writing children to a dead
        --panel is useless and the pooled wrappers below are dead too.
        if m_listPanel == nil or not m_listPanel.valid then
            return
        end

        local children = {}
        for index, block in ipairs(m_blocks) do
            local wrapper = m_blockPanels[index]
            --a pooled wrapper can be invalidated out from under us (the same
            --hazard the placeholderLabel guard below covers): reads on a
            --destroyed panel return nil, so wrapper.data.index would crash
            --the whole refresh. Rebuild the wrapper instead.
            if wrapper == nil or not wrapper.valid then
                wrapper = CreateBlockPanel()
                m_blockPanels[index] = wrapper
            end
            wrapper.data.index = index
            wrapper.data.ctx.doc = m_doc
            wrapper.data.ctx.render = render

            local active = (index == m_activeIndex)
            wrapper.data.inputHost:SetClass("collapsed", not active)
            wrapper.data.contentPanel:SetClass("collapsed", active)
            wrapper:SetClass("editing", active)

            if active then
                local input = EnsureEditInput()
                --match the input to what the block renders as: the
                --stylesheet's body face and size normally, the heading
                --face/size/weight when the block is a heading line, so
                --entering edit mode does not jar the text. Unset or
                --unavailable faces fall back to the default face (same
                --rule as SkinFont).
                local size, heading = BlockEditFont(BlockSource(block), resolvedSkin)
                local face = (resolvedSkin.body or {}).font
                local bold = false
                --the stylesheet's ink: heading color when the block is a
                --heading and sets one, else the body color. nil falls back
                --to the theme's default input color - right for dark pages,
                --while light-page stylesheets set an explicit dark ink.
                local ink = SkinColor((resolvedSkin.body or {}).color)
                if heading ~= nil then
                    if type(heading.font) == "string" and heading.font ~= "" then
                        face = heading.font
                    end
                    bold = (heading.weight == "bold" or heading.weight == "black")
                    ink = SkinColor(heading.color) or ink
                end
                input.selfStyle.fontSize = size
                input.selfStyle.bold = bold
                input.selfStyle.color = ink
                --one line of the edit font, so an empty block still shows a
                --caret without padding the block taller than its render; when
                --the block's rendered form was measured at activation, hold
                --that height instead so the page does not reflow on entry
                --(raw source is usually shorter than widgets/tables render).
                local minHeight = math.ceil(size * 1.4)
                if m_activeRenderedHeight ~= nil and m_activeRenderedHeight > minHeight then
                    minHeight = m_activeRenderedHeight
                end
                input.selfStyle.minHeight = minHeight
                if type(face) == "string" and face ~= "" and FontAvailable(face) then
                    input.selfStyle.fontFace = face
                else
                    input.selfStyle.fontFace = nil
                end
                if input.parent ~= wrapper.data.inputHost then
                    if input.parent ~= nil then
                        input:Unparent()
                    end
                    wrapper.data.inputHost.children = { input }
                end
            elseif block.placeholder then
                if wrapper.data.placeholderLabel == nil or not wrapper.data.placeholderLabel.valid then
                    wrapper.data.placeholderLabel = gui.Label{
                        classes = { "fg" },
                        text = "Click to start writing...",
                        fontSize = CustomDocument.ScaleFontSize(14),
                        opacity = 0.5,
                        width = "auto",
                        height = "auto",
                        vpad = 8,
                    }
                end
                wrapper.data.contentPanel.children = { wrapper.data.placeholderLabel }
                wrapper.data.contentPanel:MakeNonInteractiveRecursive()
                wrapper.data.renderedSource = nil
            else
                --only re-render blocks whose source, stylesheet, or render
                --generation changed; on a typical commit every other block
                --is byte-identical and reuses its rendered panels as-is.
                --resolvedStylesheet is memoized, so identity comparison
                --detects stylesheet edits (ClearCache yields a new table).
                local source = BlockSource(block)
                if wrapper.data.renderedSource ~= source
                   or wrapper.data.renderedStylesheet ~= resolvedStylesheet
                   or wrapper.data.renderedGeneration ~= m_renderGeneration then
                    wrapper.data.contentPanel.children = RenderMarkdownTokens(wrapper.data.ctx, block.tokens)
                    --clicks anywhere on the block must reach the wrapper's
                    --press handler, so the rendered content is flattened to
                    --non-interactive -- EXCEPT rich-tag widgets that declare
                    --data.editorInteractive (checkboxes): those stay live so
                    --they can be ticked in place without entering edit mode.
                    --Their PatchToken splices against full-document token
                    --positions, so a tick saves exactly as in the plain
                    --viewer; a non-interactable parent does not block events
                    --reaching an interactable child.
                    wrapper.data.contentPanel:MakeNonInteractiveRecursive()
                    for _, tagPanel in pairs(wrapper.data.ctx.pools.richPanels or {}) do
                        if tagPanel.valid and tagPanel.data ~= nil and tagPanel.data.editorInteractive then
                            tagPanel.interactable = true
                        end
                    end
                    wrapper.data.renderedSource = source
                    wrapper.data.renderedStylesheet = resolvedStylesheet
                    wrapper.data.renderedGeneration = m_renderGeneration
                end
            end

            children[#children + 1] = wrapper
        end

        for i = #m_blocks + 1, #m_blockPanels do
            m_blockPanels[i] = nil
        end

        m_listPanel.children = children

        ApplyLiveFindMarks()
    end

    DeactivateBlock = function()
        if m_activeIndex == nil then
            return
        end
        if m_editInput ~= nil and m_editInput.valid then
            m_autocomplete.Dismiss(m_editInput)
            m_editInput.popup = nil
        end
        --m_lastEdit (where the toolbar reactivates) is tracked while the
        --input is focused - the caret is not reliable after defocus, so it
        --is deliberately NOT re-read here.
        CommitActiveBlock()
        m_activeIndex = nil
        m_activeRenderedHeight = nil
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.captureEscape = false
        end
        RebuildBlockData()
        RefreshAnnotations(GetContent())
        RefreshBlockPanels()
    end

    --caretPlacement: "start" puts the caret at the beginning of the block's
    --source (arriving from above), anything else at the end (default; also
    --used when arriving from below).
    ActivateBlock = function(index, caretPlacement)
        if index == nil or index == m_activeIndex then
            return
        end
        local target = m_blocks[index]
        if target == nil then
            return
        end
        local targetLine = target.lineStart

        if m_activeIndex ~= nil then
            --commit the current edit first; the target block's lines may
            --shift if the edit changed the line count above it.
            local active = m_blocks[m_activeIndex]
            local delta = CommitActiveBlock()
            if active ~= nil and targetLine > active.lineEnd then
                targetLine = targetLine + delta
            end
            m_activeIndex = nil
            RebuildBlockData()
            RefreshAnnotations(GetContent())

            index = nil
            for i, block in ipairs(m_blocks) do
                if targetLine <= block.lineEnd then
                    index = i
                    break
                end
            end
            if index == nil and #m_blocks > 0 then
                index = #m_blocks
            end
        end

        --measure the block's rendered height before RefreshBlockPanels
        --collapses it, so the edit input can hold the block at its rendered
        --size. The pooled wrapper at this index still shows the pre-edit
        --render here (RefreshBlockPanels has not run since the commit above),
        --which is exactly the height the user is looking at.
        m_activeRenderedHeight = nil
        if index ~= nil then
            local wrapper = m_blockPanels[index]
            if wrapper ~= nil and wrapper.valid
               and wrapper.data.contentPanel ~= nil and wrapper.data.contentPanel.valid then
                local h = wrapper.data.contentPanel.renderedHeight
                if type(h) == "number" and h > 0 then
                    m_activeRenderedHeight = h
                end
            end
        end

        m_activeIndex = index
        RefreshBlockPanels()

        if m_activeIndex ~= nil then
            local block = m_blocks[m_activeIndex]
            local src = BlockSource(block)
            m_activateTime = dmhub.Time()
            m_editInput.characterLimit = ActiveCharacterBudget(#src)
            local caret = #src
            if caretPlacement == "start" then
                caret = 0
            elseif type(caretPlacement) == "table" and caretPlacement.fraction ~= nil then
                --caret on the source line nearest the click's vertical
                --position within the block, at the column nearest its
                --horizontal position.
                local lineCount = CountLines(src)
                local targetLine = math.floor(caretPlacement.fraction * lineCount) + 1
                if targetLine < 1 then targetLine = 1 end
                if targetLine > lineCount then targetLine = lineCount end

                --1-based [first, last] char span of the target line in src.
                local lineFirst = 1
                if targetLine > 1 then
                    local seen = 0
                    for i = 1, #src do
                        if src:sub(i, i) == "\n" then
                            seen = seen + 1
                            if seen == targetLine - 1 then
                                lineFirst = i + 1
                                break
                            end
                        end
                    end
                end
                local lineLast = #src
                local nl = src:find("\n", lineFirst, true)
                if nl ~= nil then
                    lineLast = nl - 1
                end

                caret = lineLast --caret is 0-based; this is end-of-line.
                if caretPlacement.xFraction ~= nil
                   and caretPlacement.pixelWidth ~= nil
                   and caretPlacement.pixelWidth > 0 then
                    --approximate a column from the click's pixel offset,
                    --assuming an average glyph is about half the font size
                    --wide (using the size the block will actually edit at,
                    --which is larger for heading blocks). Proportional
                    --faces and markdown syntax make this inexact; clamping
                    --to the line keeps it sane.
                    local editFontSize = BlockEditFont(src, m_doc:GetResolvedStylesheet().base)
                    local approxCharWidth = editFontSize * 0.5
                    local px = caretPlacement.xFraction * caretPlacement.pixelWidth
                    local col = math.floor(px / approxCharWidth + 0.5)
                    local lineLen = lineLast - lineFirst + 1
                    if col < 0 then col = 0 end
                    if col > lineLen then col = lineLen end
                    caret = (lineFirst - 1) + col
                end
            end
            m_editInput:SetTextAndCaret(caret, src)
            m_editInput.hasInputFocus = true
            m_lastEdit = { line = block.lineStart, caret = caret }
        end

        --intercept escape only while a block is active (see resultPanel's
        --escape handler).
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.captureEscape = (m_activeIndex ~= nil)
        end
    end

    --Appends a fresh empty paragraph after the last block and opens it for
    --editing; the click-below-the-document affordance. The new paragraph
    --gets a synthetic block over a fresh blank line (blank lines belong to
    --no block, so the partitioner cannot produce one); once the user types
    --and the block commits, it becomes a real content block.
    local function AppendParagraph()
        DeactivateBlock()

        if #m_lines == 0 or trim(m_lines[#m_lines] or "") ~= "" then
            m_lines[#m_lines + 1] = "" --separator from the last content line.
        end
        m_lines[#m_lines + 1] = ""     --the new paragraph's home line.

        RebuildBlockData()
        if m_blocks[#m_blocks] == nil or not m_blocks[#m_blocks].placeholder then
            m_blocks[#m_blocks + 1] = {
                lineStart = #m_lines,
                lineEnd = #m_lines,
                tokens = {},
                placeholder = true,
            }
        end
        RefreshBlockPanels()
        ActivateBlock(#m_blocks)
    end

    --Adopt restored content wholesale (undo/redo): rebuild everything and
    --refresh the changes indicator against the last saved content.
    local function RestoreContent(content)
        SetLinesFromContent(content)
        m_lastEdit = nil
        m_renderGeneration = m_renderGeneration + 1
        RebuildBlockData()
        RefreshAnnotations(GetContent())
        RefreshBlockPanels()
        if resultPanel ~= nil then
            resultPanel:SetClassTree("changes", GetContent() ~= m_savedContent)
        end
    end

    --Ctrl+Z / the toolbar Undo button. A mid-edit block is committed first
    --(pushing its own snapshot), so undo reverts the thing the user just did.
    local function PerformUndo()
        if m_activeIndex ~= nil then
            DeactivateBlock()
        end
        local prev = m_undoStack[#m_undoStack]
        if prev == nil then
            return
        end
        m_undoStack[#m_undoStack] = nil
        m_redoStack[#m_redoStack + 1] = GetContent()
        RestoreContent(prev)
    end

    local function PerformRedo()
        --deactivating a dirty block commits a fresh change, which clears the
        --redo stack via PushUndo; that is the correct outcome (a new edit
        --invalidates redo history).
        if m_activeIndex ~= nil then
            DeactivateBlock()
        end
        local nxt = m_redoStack[#m_redoStack]
        if nxt == nil then
            return
        end
        m_redoStack[#m_redoStack] = nil
        --push directly (not PushUndo) so the redo stack survives.
        m_undoStack[#m_undoStack + 1] = GetContent()
        RestoreContent(nxt)
    end

    --the formatting toolbar, shared with the classic editor. Toolbar clicks
    --defocus the input, which commits and deactivates the block before the
    --button handler runs; GetInput reactivates the last edited block (line
    --anchored, caret restored) so the action lands where the user was typing.
    local m_toolbar = CreateMarkdownToolbar{
        OnUndo = PerformUndo,
        OnRedo = PerformRedo,
        GetInput = function()
            if m_activeIndex ~= nil then
                return m_editInput
            end
            if m_lastEdit == nil then
                return nil
            end
            local index = nil
            for i, block in ipairs(m_blocks) do
                if m_lastEdit.line <= block.lineEnd then
                    index = i
                    break
                end
            end
            if index == nil then
                return nil
            end
            ActivateBlock(index)
            if m_activeIndex == nil or m_editInput == nil or not m_editInput.valid then
                return nil
            end
            --hand the intended caret to the action explicitly: the caret set
            --during activation is still pending (deferred across the focus
            --race), so reading input.caretPosition here would act on a stale
            --position.
            local caret = nil
            if m_lastEdit ~= nil and m_lastEdit.caret ~= nil then
                caret = math.min(m_lastEdit.caret, #(m_editInput.text or ""))
            end
            return m_editInput, caret
        end,
        GetStylesheetId = function()
            return m_doc.styleSheetId or ""
        end,
        OnStylesheetChanged = function(chosen)
            m_doc.styleSheetId = (chosen ~= "" and chosen) or false
            ResolveStylesheet.ClearCache()
            m_doc._tmp_styleDirty = true
            m_renderGeneration = m_renderGeneration + 1
            RefreshBlockPanels()
            if resultPanel ~= nil then
                resultPanel:SetClassTree("changes", true)
            end
        end,
    }

    m_listPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
        valign = "top",
    }

    m_pagePanel = gui.Panel{
        width = "98%",
        height = "100% available",
        halign = "center",
        valign = "top",
        vscroll = true,
        flow = "vertical",
        m_listPanel,

        --click below the last block to append a new paragraph
        --(hairline-free: this is content space, not chrome). Same selector
        --arity note as the block wrappers: {panel, class} keeps the theme's
        --panel fill from painting this dark.
        gui.Panel{
            classes = { "liveEditAppend" },
            width = "100%",
            height = 48,
            hoverCursor = "text",
            bgimage = "panels/square.png",
            styles = {
                {
                    selectors = { "panel", "liveEditAppend" },
                    bgcolor = "#00000000",
                },
                {
                    selectors = { "panel", "liveEditAppend", "hover" },
                    --kept in step with the block hover wash above.
                    bgcolor = "#ffffff0a",
                },
            },
            press = function(element)
                AppendParagraph()
            end,
        },
    }

    resultPanel = gui.Panel{
        classes = { "collapsed" },
        styles = ThemeEngine.GetStyles(),
        width = "100%",
        height = "100%-0",
        valign = "top",
        tmargin = 2,
        flow = "vertical",

        --document-level history: Ctrl+Z/Ctrl+Y route here when the engine
        --dispatches them as input events (the focused block input handles
        --its own in-edit undo natively).
        inputEvents = { "undo", "redo" },
        undo = function(element)
            PerformUndo()
        end,
        redo = function(element)
            PerformRedo()
        end,

        --escape while a block is being edited commits the block and stays in
        --the journal instead of bubbling to the window's EXIT_DIALOG close.
        --Same pattern as the editor's find bar: DMHUB_POPUP outranks
        --EXIT_DIALOG, and captureEscape is toggled with block activation
        --(ActivateBlock/DeactivateBlock) so escape with no active block
        --still closes the journal window as usual.
        captureEscape = false,
        escapePriority = EscapePriority.DMHUB_POPUP,
        escape = function(element)
            DeactivateBlock()
        end,

        --Find-in-page driver, same contract as DisplayPanel's: re-renders
        --with term occurrences marked, reports the match count through the
        --callback (synchronously, during this event), and scrolls to match
        --number index. A nil or empty term clears the highlights. An active
        --block is committed first so its content is rendered, countable,
        --and safe to mark.
        findInPage = function(element, findArgs)
            local term = findArgs ~= nil and findArgs.term or nil
            if term == "" then
                term = nil
            end
            m_findTerm = term
            m_findIndex = findArgs ~= nil and findArgs.index or 1
            m_findCallback = findArgs ~= nil and findArgs.callback or nil
            m_findGeneration = m_findGeneration + 1
            --render fresh labels even when the term was just cleared, so
            --stale marks drop out.
            m_renderGeneration = m_renderGeneration + 1
            if m_activeIndex ~= nil then
                DeactivateBlock()
            else
                RefreshBlockPanels()
            end
            m_findCallback = nil
        end,

        --focus watchdog: if the active input silently lost focus (clicked
        --into another panel entirely) commit and re-render. The grace period
        --covers the input's multi-frame focus acquisition.
        thinkTime = 0.25,
        think = function(element)
            if m_activeIndex == nil then
                return
            end
            if dmhub.Time() - m_activateTime < 0.5 then
                return
            end
            if m_editInput ~= nil and m_editInput.valid and m_editInput.popup ~= nil then
                --an autocomplete/link popup owns the interaction right now.
                return
            end
            if m_editInput == nil or (not m_editInput.valid) or (not m_editInput.hasInputFocus) then
                DeactivateBlock()
            end
        end,

        refreshDocument = function(element, doc)
            if doc ~= nil then
                m_doc = doc
            end

            local hasLocalWork = (m_activeIndex ~= nil)
                or (m_savedContent ~= nil and GetContent() ~= m_savedContent)
            if hasLocalWork then
                --an active edit or committed-but-unsaved local changes:
                --never clobber them with a refresh. TextStorage merges
                --disjoint-region edits when we save; if the stored content
                --has moved on, surface it through the changes indicator so
                --the user knows a save will merge.
                local remote = (m_doc:GetTextContent() or ""):gsub("\v", "\n"):gsub("\r", "")
                if remote ~= GetContentIncludingActive() then
                    resultPanel:SetClassTree("changes", true)
                end
                return
            end

            m_lastEdit = nil
            SetLinesFromContent(m_doc:GetTextContent())
            m_savedContent = GetContent()
            m_renderGeneration = m_renderGeneration + 1
            RebuildBlockData()
            RefreshAnnotations(GetContent())
            RefreshBlockPanels()
        end,

        needsave = function(element, result)
            if m_doc:GetTextContent() ~= GetContentIncludingActive() then
                result.save = true
            end
        end,

        savedoc = function(element)
            DeactivateBlock()
            m_doc:SetTextContent(GetContent())
            --re-read: SetTextContent routes through TextStorage, which may
            --have merged concurrent remote edits into the stored result.
            SetLinesFromContent(m_doc:GetTextContent())
            m_savedContent = GetContent()
            m_renderGeneration = m_renderGeneration + 1
            RebuildBlockData()
            RefreshAnnotations(GetContent())
            RefreshBlockPanels()
        end,

        checkChanges = function(element, baseDoc)
            resultPanel:SetClassTree("changes", GetContentIncludingActive() ~= baseDoc:GetTextContent())
        end,

        m_toolbar,

        m_pagePanel,

        --hairline above the annotation strip, continuing the design's
        --row-separation rhythm.
        gui.Panel{
            width = "100%",
            height = 1,
            bgimage = "panels/square.png",
            bgcolor = "#ffffff26",
        },

        m_annotationsPanel,
    }

    SetLinesFromContent(m_doc:GetTextContent())
    m_savedContent = GetContent()
    RebuildBlockData()
    RefreshAnnotations(GetContent())
    RefreshBlockPanels()

    return resultPanel
end

local MarkdownReferenceTooltip

--The Obsidian-style live block editor (LiveEditPanel) is the journal's
--editor. The classic full-document editor is retained below as
--ClassicEditPanel for reference until its remaining exclusives (find bar
--while editing, formatting guide, preview pane) are ported to the live
--editor; nothing calls it.
function MarkdownDocument:EditPanel(args)
    return self:LiveEditPanel(args)
end

function MarkdownDocument:ClassicEditPanel(args)
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
                {
                    selectors = {"saveError"},
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

        gui.Label{
            --shown only when the write-verification watchdog (DocumentSystem.lua) gives up
            --after a delta save AND a full-write retry both go unconfirmed by the server.
            --Driven by the 'saveError' class set via resultPanel:SetClassTree. Collapsed
            --again as soon as the user edits (changes) or a new save is in flight
            --(savePending), and cleared automatically by a late server confirmation.
            styles = {
                {
                    selectors = {"~saveError"},
                    collapsed = 1,
                },
                {
                    selectors = {"changes"},
                    collapsed = 1,
                },
                {
                    selectors = {"savePending"},
                    collapsed = 1,
                },
            },

            color = "#ff5b5b",
            text = "Save failed!",
            fontSize = 14,
            width = "auto",
            height = "auto",
            hover = function(element)
                gui.Tooltip("The server did not confirm your save, so your latest changes may not be stored. Keep this document open -- it will retry automatically and clear this message if the connection recovers. You can also keep editing (each save retries) or press Ctrl+Z to recover text that vanished.")(element)
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

    -- Link autocomplete + link-info service (shared with LiveEditPanel; see
    -- CreateMarkdownAutocomplete). Aliases keep the historical local names
    -- used by the handlers below.
    local m_autocomplete = CreateMarkdownAutocomplete{
        GetDocument = function()
            return self
        end,
        OnTextChanged = function(newText)
            NotifyTextChanged(newText)
        end,
    }
    local autocompleteState = m_autocomplete.state
    local FindLinkContext = m_autocomplete.FindLinkContext
    local UpdateAutocomplete = m_autocomplete.Update
    local DismissAutocomplete = m_autocomplete.Dismiss
    local UpdateLinkInfo = m_autocomplete.UpdateLinkInfo

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

            -- Notify the document controller so its periodic-autosave timers
            -- (DocumentSystem.lua) restart their debounce from this edit.
            local documentPanel = element:FindParentWithClass("documentPanel")
            if documentPanel ~= nil then
                documentPanel:FireEvent("documentEdited")
            end
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

    --rich-tag annotation editor strip, shared with the live editor.
    local annotationsPanel = CreateAnnotationsPanel{
        GetDocument = function()
            return self
        end,
    }

    --formatting toolbar, shared with the live editor.
    local toolbar = CreateMarkdownToolbar{
        GetInput = function()
            return editInput
        end,
        GetStylesheetId = function()
            return self.styleSheetId or ""
        end,
        OnStylesheetChanged = function(chosen)
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
