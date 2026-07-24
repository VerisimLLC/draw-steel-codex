local mod = dmhub.GetModLoading()


---@class CustomDocument
---@field id string
---@field title string
---@field content false|string
---@field nodeType string
---@field hidden boolean
---@field hiddenFromPlayers boolean
---@field vscroll boolean
---@field description string
---@field ownerid false|string
---@field textStorage false|TextStorage
CustomDocument = RegisterGameType("CustomDocument")
CustomDocument.readonly = false
CustomDocument.updateid = ""
CustomDocument.tableName = "documents"
CustomDocument.parentFolder = "private"
CustomDocument.ownerid = false --by default owned by the Director.
CustomDocument.nodeType = "custom"
CustomDocument.hidden = false
CustomDocument.hiddenFromPlayers = false
CustomDocument.description = "New Document"
CustomDocument.AddAlias("name", "description")
CustomDocument.bookmarks = {}
CustomDocument.vscroll = true
CustomDocument.textStorage = false
CustomDocument.ord = 0

CustomDocument.MaxLength = 8192*4

CustomDocument.documentTypes = {}

----------------------------------------------------------------------
-- Document semantic types
-- -----------------------
-- A fixed, presentational classification of a document -- what KIND of
-- beat or reference it is -- so the tree, the Run, the Flow lens, and
-- (later) tabs can show one consistent glyph and users know a doc's
-- purpose at a glance. This is separate from `nodeType` (the Lua kind,
-- used for tree filtering) and from `documentTypes` (the "New Document"
-- creation menu): it is a per-instance field, defaulting to narration,
-- pinned by the functional subtypes (Montage, Negotiation).
--
-- `beat` splits the taxonomy: beats sequence on the Run and appear as
-- Flow nodes (narration, exploration, combat, montage, negotiation);
-- references (location, npc) get an icon in the tree and inline links
-- but never enter the Run/Flow.
--
-- App icons (Icon_App_*) are full-colour: render them with bgcolor
-- "white" -- an inline theme-token bgcolor paints them invisible.
----------------------------------------------------------------------

CustomDocument.docType = "narration"

--Fixed registry, keyed by type id. glyph = single-letter Flow badge.
--Icons are Phosphor line glyphs (monochrome masks): they render tinted @fg
--through the tree/Run cascade and invert on hover, unlike the old full-colour
--Icon_App art which was painted untinted. exploration and location now carry
--distinct art (compass vs pin), resolving the placeholder they used to share.
CustomDocument.docTypeInfo = {
    note        = { text = "Note",        icon = "phosphor/note-pencil.png",          beat = false, glyph = "~", ord = 5 },
    narration   = { text = "Narration",   icon = "phosphor/quotes.png",               beat = true,  glyph = "N", ord = 10 },
    exploration = { text = "Exploration", icon = "phosphor/compass.png",              beat = true,  glyph = "E", ord = 20 },
    combat      = { text = "Combat",      icon = "phosphor/sword.png",                beat = true,  glyph = "C", ord = 30 },
    montage     = { text = "Montage",     icon = "phosphor/film-slate.png",           beat = true,  glyph = "M", ord = 40 },
    negotiation = { text = "Negotiation", icon = "phosphor/handshake.png",            beat = true,  glyph = "G", ord = 50 },
    location    = { text = "Location",    icon = "phosphor/map-pin-simple.png",       beat = false, glyph = "L", ord = 60 },
    npc         = { text = "NPC",         icon = "phosphor/person-simple-circle.png", beat = false, glyph = "P", ord = 70 },
}

--The document's semantic type id, always a valid key (falls back to
--narration for unset or unknown values -- pre-migration docs included).
--Read docType via direct index, NOT try_get: the functional subtypes pin
--their type as a TYPE-LEVEL default (MontageDocument.docType = "montage"),
--which try_get does not see (it only checks the instance's raw fields).
--Direct index walks the type chain; the base default makes it safe.
function CustomDocument.DocTypeId(doc)
    local t = nil
    pcall(function() t = doc.docType end)
    if t == nil or CustomDocument.docTypeInfo[t] == nil then
        return "narration"
    end
    return t
end

--The registry entry for a document's semantic type (never nil).
function CustomDocument.DocTypeInfo(doc)
    return CustomDocument.docTypeInfo[CustomDocument.DocTypeId(doc)]
end

--Convenience readers used by the read-sites (tree/Run/Flow).
function CustomDocument.DocTypeIcon(doc)
    return CustomDocument.DocTypeInfo(doc).icon
end

function CustomDocument.DocTypeIsBeat(doc)
    return CustomDocument.DocTypeInfo(doc).beat == true
end

--One-time, per-game migration: backfill docType on plain custom docs from
--their legacy italic-subtitle word (the same words the Flow lens reads). Only
--touches docs still at the default narration, and only sets a non-narration
--type, so it is safe to re-run and never clobbers an explicitly-set type.
--Uploads are spaced one-per-frame via dmhub.Schedule -- same-table uploads in
--a single frame drop all but the last. Call from the console per game;
--onDone(typedCount, scannedCount) fires when finished.
function CustomDocument.BackfillDocTypesFromSubtitles(onDone)
    local SUBTITLE_TYPE = {
        combat = "combat", montage = "montage", negotiation = "negotiation",
        exploration = "exploration", location = "location", npc = "npc",
    }
    local docs = dmhub.GetTable(CustomDocument.tableName) or {}
    local queue = {}
    for _, doc in pairs(docs) do
        if not doc.hidden and doc.nodeType == "custom" and CustomDocument.DocTypeId(doc) == "narration" then
            queue[#queue + 1] = doc
        end
    end
    local i, typed = 0, 0
    local function step()
        if mod.unloaded then return end
        i = i + 1
        if i > #queue then
            if onDone then onDone(typed, #queue) end
            return
        end
        local doc = queue[i]
        local content = doc:GetTextContent() or ""
        local italic = string.match(content, "\n%*([^%*\n]+)%*")
        local word = string.lower(string.match(italic or "", "^(%a+)") or "")
        local mapped = SUBTITLE_TYPE[word]
        if mapped ~= nil then
            doc.docType = mapped
            doc:Upload()
            typed = typed + 1
        end
        dmhub.Schedule(0.05, step)
    end
    step()
end

local g_tabbedViewer = nil

-- Tab system sizes
local TAB_HEIGHT = 30
local TAB_MAX_WIDTH = 200
local TAB_BAR_HEIGHT = TAB_HEIGHT + 6

--Width of the docked journal tree rail inside the tabbed viewer.
local TREE_RAIL_WIDTH = 250

--Per-user preference: keep the journal tree pinned as a rail inside the
--tabbed document viewer. Off = the viewer looks exactly as it does today.
local g_journalTreeRailSetting = setting{
    id = "docviewer:journaltree",
    default = false,
    storage = "preference",
}

function CustomDocument.Register(args)
    CustomDocument.documentTypes[args.id] = args
end

local g_settingJournalFontSize = setting {
    id = "journal:fontsize",
    storage = "preference",
    description = "Journal Font Size",
    section = "general",
    default = 100,
    editor = "slider",
    min = 50,
    max = 300,
}

function CustomDocument:HaveEditPermissions()
    return (not self.readonly) and (dmhub.isDM or (self.ownerid == dmhub.loginUserid))
end

local g_scale = nil
function CustomDocument.ScaleFontSize(size)
    if g_scale == nil then
        g_scale = g_settingJournalFontSize:Get() / 100
    end
    return math.floor(size * g_scale)
end

function CustomDocument.OnDeserialize(self)
    if self.textStorage and not getmetatable(self.textStorage) then
        --textStorage came back without its metatable (e.g. it deserialized as a
        --plain table). Do NOT just discard it: that falls back to the stale/empty
        --self.content (SetTextContent no longer keeps content in sync), and the
        --next save would then permanently overwrite the good data in the DB with
        --that empty content. Re-wrap the raw sections into a proper TextStorage so
        --the content survives. Only give up if there is genuinely nothing to keep.
        local raw = self.textStorage
        if TextStorage ~= nil and type(raw) == "table" and type(raw.sections) == "table" then
            self.textStorage = TextStorage.new{ sections = raw.sections }
        else
            self.textStorage = nil
        end
    end
end

function CustomDocument:Render()
    return nil
end

function CustomDocument:PreviewDescription()
    return string.format("Click to view '%s'", self.description)
end

function CustomDocument:Upload(originalDocument)
    self.updateid = dmhub.GenerateGuid()
    dmhub.SetAndUploadTableItem(self.tableName, self, {delta = originalDocument ~= nil, deltaFrom = originalDocument})
    return self.updateid
end

--Document text is LF-only; a carriage return is never legal in it. This is not
--cosmetic: TMP renders a bare \r as a real teletype carriage return -- the pen
--goes back to the left margin with NO vertical advance (TMP_Text.cs, "Handle
--Carriage Return") -- so in the editor the rest of the line is drawn ON TOP of
--the text before it. Removing every \r collapses CRLF to LF for free and joins
--the (vanishingly rare) bare-CR case, which is what a stray CR pasted out of a
--PDF or a Windows source actually wants. Applied on read as well as write so a
--document that already carries one displays correctly right now and is healed
--permanently the next time it is saved.
local function NormalizeDocumentText(str)
    if type(str) ~= "string" or string.find(str, "\r", 1, true) == nil then
        return str
    end
    return (string.gsub(str, "\r", ""))
end

CustomDocument.NormalizeText = NormalizeDocumentText

function CustomDocument:GetTextContent()
    if (not self.textStorage) or not getmetatable(self.textStorage) then
        return NormalizeDocumentText(self.content or "")
    end

    return NormalizeDocumentText(self.textStorage:GetContent() or "")
end

function CustomDocument:SetTextContent(str)
    --self.content = nil

    str = NormalizeDocumentText(str)

    if (not self.textStorage) or not getmetatable(self.textStorage) then
        self.textStorage = TextStorage.Create(str)
    else
        self.textStorage:SetContent(str)
    end
end

function CustomDocument:ShowCreateDialog()
end

function CustomDocument:EditPanel()
    local editInput = gui.TextEditor {
        width = "90%",
        height = "90%",
        halign = "center",
        valign = "center",
        multiline = true,
        textAlignment = "topleft",
        text = self:GetTextContent() or "",
        selectAllOnFocus = false,
        focus = function(element)
        end,
        defocus = function(element)
        end,
        edit = function(element)
        end,
        savedoc = function(element)
            self:SetTextContent(element.text)
        end,
    }

    local writePanel = gui.Panel {
        classes = { "collapsed" },
        width = "100%",
        height = "100%",
        editInput,
    }

    return writePanel
end

function CustomDocument:DisplayPanel()
    local readPanel = gui.Label {
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        text = self:GetTextContent(),
        markdown = true,
        textAlignment = "topleft",
        fontSize = 14,
        pad = 16,
        links = true,
        hoverLink = function(element, link)
        end,
        savedoc = function(element)
            element.text = self:GetTextContent()
        end,
    }

    return readPanel
end

--utility function to determine if we are in player view mode.
function CustomDocument:IsPlayerView(element)
    return (not self:HaveEditPermissions()) or (element:FindParentWithClass("playerPreview") ~= nil)
end

local function checkUnsavedChanges(writePanel, resultPanel, doc, onProceed)
    --writePanel is nil until the user first enters edit mode (it is built
    --lazily); no edit panel means nothing unsaved.
    if writePanel == nil or writePanel:HasClass("collapsed") then
        onProceed()
        return
    end
    local needSave = {save = false}
    writePanel:FireEventTree("needsave", needSave)
    if not needSave.save then
        onProceed()
        return
    end
    gui.ModalMessage {
        title = "Unsaved Changes",
        message = "You have unsaved changes. Are you sure you want to navigate away without saving?",
        options = {
            { text = "Cancel" },
            {
                text = "Save",
                execute = function()
                    resultPanel:FireEventTree("savedoc")
                    if not dmhub.DeepEqual(doc, resultPanel.data.original) then
                        doc:Upload(resultPanel.data.original)
                    end
                    onProceed()
                end,
            },
            { text = "Don't Save", execute = onProceed },
        },
    }
end

--- Builds a breadcrumb string from a document's folder ancestry including the document name
--- Walks up assets.documentFoldersTable and built-in root folders
--- @param doc table The document to build a breadcrumb for
--- @return string breadcrumb The breadcrumb text (always includes at least the doc name)
local function buildBreadcrumbText(doc)
    local builtinFolderNames = {
        public = "Shared Documents",
        private = "Private Documents",
        templates = "Templates",
    }
    if game and game.currentMapId then
        builtinFolderNames[game.currentMapId] = "Map Documents"
    end
    if dmhub and dmhub.loginUserid then
        builtinFolderNames[dmhub.loginUserid] = "My Private Documents"
    end

    -- todo: game.GetMap(doc.parentFolder) using folder ID if nil, not a map. if not nil, it's a map
    local foldersTable = assets.documentFoldersTable or {}
    local parts = {}
    local folderId = doc.parentFolder
    local count = 0
    while folderId and folderId ~= "" and count < 20 do
        local folder = foldersTable[folderId]
        if folder and not folder.hidden then
            parts[#parts + 1] = folder.description or folderId
            folderId = folder.parentFolder
        elseif builtinFolderNames[folderId] then
            parts[#parts + 1] = builtinFolderNames[folderId]
            break
        else
            break
        end
        count = count + 1
    end
    local reversed = {}
    for i = #parts, 1, -1 do
        --handoff spec: folder crumbs are uppercase 11px warm-muted labels;
        --the document name carries the weight at full size.
        reversed[#reversed + 1] = string.format("<size=11><color=#7a7468>%s</color></size>", string.upper(parts[i]))
    end
    reversed[#reversed + 1] = "**" .. (doc.description or "Untitled") .. "**"
    --gold separators per the design's breadcrumb treatment.
    return table.concat(reversed, " <color=#ffffff99>></color> ")
end

function CustomDocument.GetAccessibleRoots()
    local roots = {}
    roots["public"] = true
    if dmhub.isDM then
        roots["private"] = true
        roots["templates"] = true
        if game and game.currentMapId then
            roots[game.currentMapId] = true
        end
    else
        if dmhub.loginUserid then
            roots[dmhub.loginUserid] = true
        end
    end
    return roots
end

function CustomDocument.IsDocInAccessibleRoot(doc, accessibleRoots)
    local allFolders = assets.documentFoldersTable or {}
    local pf = doc.parentFolder or "private"
    local count = 0
    while pf and pf ~= "" and count < 20 do
        if accessibleRoots[pf] then return true end
        local folder = allFolders[pf]
        if folder == nil then break end
        pf = folder.parentFolder or "private"
        count = count + 1
    end
    return false
end

--Expand/collapse choices made in the viewer tree (docked rail or dropdown
--popup) survive rebuilds for the session: folderId -> bool. Nil means use
--the default (built-in roots open, like the journal panel; subfolders open
--only on the current document's ancestor chain).
local g_journalTreeExpanded = {}

--- Builds a popup tree view of the journal hierarchy
--- @param currentDocId string The ID of the currently displayed document
--- @param dialogPanel Panel The dialog panel with navigation handlers
--- @param opts nil|{onPick: fun(docId: string), onNewDocument: fun(typeInfo: table)}
---   onPick: picking a document calls this instead of navigating dialogPanel
---   (the tab bar's + uses it to open the pick in a new tab). onNewDocument:
---   when set, a "New Document" entry heads the popup; it expands to the
---   registered document types and picking one calls this.
--- @return Panel The popup panel
local function buildJournalTree(currentDocId, dialogPanel, opts)
    --pick-once latch: a single physical click can deliver press more than
    --once while the popup is being torn down mid-dispatch (observed with the
    --tab bar's + popup: one click on a create row made two documents). Any
    --picking action arms this and further picks are ignored; the popup is
    --closing anyway.
    local m_pickHandled = false
    -- Built-in root folders
    local builtinRoots = {}
    builtinRoots["public"] = { description = "Shared Documents", parentFolder = "" }
    if dmhub.isDM then
        builtinRoots["private"] = { description = "Private Documents", parentFolder = "" }
        builtinRoots["templates"] = { description = "Templates", parentFolder = "" }
        if game and game.currentMapId then
            builtinRoots[game.currentMapId] = { description = "Map Documents", parentFolder = "" }
        end
    else
        if dmhub.loginUserid then
            builtinRoots[dmhub.loginUserid] = { description = "My Private Documents", parentFolder = "" }
        end
    end

    -- Merge built-in + user folders
    local allFolders = {}
    for k, v in pairs(builtinRoots) do allFolders[k] = v end
    for k, v in pairs(assets.documentFoldersTable or {}) do
        if not v.hidden then allFolders[k] = v end
    end

    -- Build foldersToMembers map (folders + custom docs only). The nodeType
    -- gate matches the journal panel's row builder (Journal.lua): documents
    -- with specialized nodeTypes (e.g. "negotiation") are surfaced through
    -- their own panels, not the journal tree.
    local foldersToMembers = {}
    local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
    for k, doc in pairs(customDocs) do
        --custom pages plus prep docs that live in the journal (negotiations are
        --journal documents seeded from a compendium archetype, so they belong
        --in the tree alongside pages; they carry their own type icon).
        if not doc.hidden and (doc.nodeType == "custom" or doc.nodeType == "negotiation")
            and (dmhub.isDM or not doc.hiddenFromPlayers) then
            local pf = doc.parentFolder or "private"
            foldersToMembers[pf] = foldersToMembers[pf] or {}
            foldersToMembers[pf][k] = { type = "doc", id = k, description = doc.description or "Untitled",
                icon = CustomDocument.DocTypeIcon(doc) }
        end
    end
    --PDF books, image documents, and PDF page fragments -- the same member
    --sources as the journal panel (hidden covers the Patreon PDF variants
    --that share book names). Non-doc members carry their content object and
    --open via CustomDocument.OpenContent, exactly like a journal panel
    --click; they are never navigated to in a viewer tab.
    for k, doc in pairs(assets.pdfDocumentsTable or {}) do
        if not doc.hidden then
            local pf = doc.parentFolder or "private"
            foldersToMembers[pf] = foldersToMembers[pf] or {}
            foldersToMembers[pf][k] = { type = "pdf", id = k, description = doc.description or "PDF", content = doc }
        end
    end
    for k, image in pairs(assets.imagesByTypeTable.Document or {}) do
        if not image.hidden then
            local pf = image.parentFolder or "private"
            foldersToMembers[pf] = foldersToMembers[pf] or {}
            foldersToMembers[pf][k] = { type = "image", id = k, description = image.description or "Image", content = image }
        end
    end
    --PDFFragment is registered by JournalPDFViewer (a later-loading module);
    --guard so the tree still builds if that module is absent.
    if rawget(_G, "PDFFragment") ~= nil then
        for k, fragment in unhidden_pairs(dmhub.GetTable(PDFFragment.tableName) or {}) do
            local pf = fragment.parentFolder or "private"
            foldersToMembers[pf] = foldersToMembers[pf] or {}
            foldersToMembers[pf][k] = { type = "pdffragment", id = k, description = fragment.description or "PDF Page", content = fragment }
        end
    end
    for k, folder in pairs(allFolders) do
        if builtinRoots[k] == nil then
            local pf = folder.parentFolder or "private"
            foldersToMembers[pf] = foldersToMembers[pf] or {}
            foldersToMembers[pf][k] = { type = "folder", id = k, description = folder.description or k }
        end
    end

    -- Check if a folder is an ancestor of the current document
    local function isAncestorOf(folderId, docId)
        local doc = customDocs[docId]
        if doc == nil then return false end
        local pf = doc.parentFolder
        local count = 0
        while pf and pf ~= "" and count < 20 do
            if pf == folderId then return true end
            local folder = allFolders[pf]
            if folder == nil then break end
            pf = folder.parentFolder or "private"
            count = count + 1
        end
        return false
    end

    --Shared look for the whole tree, mirroring the journal panel's tree
    --styles (Journal.lua, CreateFolderContentsPanel + its styles block):
    --20px rows, fontSize 14, hover = @fgStrong fill with @bg content,
    --folder headers filled @bg (@bgAlt + muted label when nested), and one
    --fixed row grammar: [18px expander slot][icon][name]. Attached to the
    --tree's root container so it cascades to every row in both the docked
    --rail and the dropdown popup.
    local treeStyles = ThemeEngine.MergeTokens({
        {
            selectors = { "treeRow" },
            width = "100%",
            height = 20,
            bgimage = "panels/square.png",
            bgcolor = "clear",
            flow = "horizontal",
            halign = "left",
        },
        {
            priority = 5,
            selectors = { "treeRow", "currentDoc" },
            bgcolor = "@bgAlt",
        },
        {
            priority = 5,
            selectors = { "treeRow", "folderRow" },
            bgcolor = "@bg",
        },
        {
            priority = 6,
            selectors = { "treeRow", "folderRow", "subfolder" },
            bgcolor = "@bgAlt",
        },
        {
            priority = 7,
            selectors = { "treeRow", "hover" },
            bgcolor = "@fgStrong",
        },
        {
            selectors = { "treeLabel" },
            color = "@fg",
            fontSize = 14,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 4,
            textWrap = false,
        },
        {
            priority = 5,
            selectors = { "treeLabel", "parent:subfolder" },
            color = "@fgMuted",
        },
        {
            priority = 6,
            selectors = { "treeLabel", "parent:currentDoc" },
            color = "@fgStrong",
            bold = true,
        },
        {
            priority = 7,
            selectors = { "treeLabel", "parent:hover" },
            color = "@bg",
        },
        {
            selectors = { "treeIcon" },
            width = 16,
            height = 16,
            bgcolor = "@fg",
            halign = "left",
            valign = "center",
            hmargin = 4,
        },
        {
            priority = 5,
            selectors = { "treeIcon", "parent:hover" },
            bgcolor = "@bg",
        },
        --triangles match the journal panel: @fg glyphs that invert on row
        --hover. A "ghost" triangle holds its 18px slot in the row but is
        --invisible (rows that cannot expand keep the slot so their icons
        --line up with sibling folder labels).
        {
            priority = 5,
            selectors = { "triangle" },
            bgcolor = "@fg",
        },
        {
            priority = 6,
            selectors = { "triangle", "parent:hover" },
            bgcolor = "@bg",
        },
        {
            priority = 10,
            selectors = { "triangle", "ghost" },
            bgcolor = "clear",
        },
    })

    --the 18px expander slot for rows that can never expand: same triangle
    --geometry as a folder's toggle (8px glyph + 5px margins) but ghosted,
    --exactly like the journal panel's doc rows.
    local function makeExpanderGhost()
        return gui.Panel {
            bgimage = "panels/triangle.png",
            classes = { "triangle", "ghost" },
            styles = gui.TriangleStyles,
        }
    end

    -- Build a single folder entry (row + collapsible children)
    local function buildFolderEntry(folderId, description, isExpanded, childrenPanels, isRoot)
        --a toggle the user made earlier this session wins over the default.
        if g_journalTreeExpanded[folderId] ~= nil then
            isExpanded = g_journalTreeExpanded[folderId]
        end
        local isCollapsed = not isExpanded

        local contentPanel = gui.Panel {
            --the indent ladder, identical to the journal panel: each
            --folder's contents shift ALL children (doc rows and subfolder
            --headers alike) one 16px step right, contained (halign left +
            --reduced width) so nesting never overflows the rail.
            halign = "left",
            width = "100%-16",
            height = "auto",
            flow = "vertical",
            lmargin = 16,
            classes = { cond(isCollapsed, "collapsed") },
            children = childrenPanels,
        }

        local arrow = gui.Panel {
            bgimage = "panels/triangle.png",
            classes = { "triangle", cond(not isCollapsed, "expanded") },
            styles = gui.TriangleStyles,
        }

        local folderRow = gui.Panel {
            classes = { "treeRow", "folderRow", cond(not isRoot, "subfolder") },
            press = function(element)
                isCollapsed = not isCollapsed
                --remember the choice for the session ("newdocument" is the
                --popup's create header, not a real folder; always start it
                --closed).
                if folderId ~= "newdocument" then
                    g_journalTreeExpanded[folderId] = not isCollapsed
                end
                contentPanel:SetClass("collapsed", isCollapsed)
                arrow:SetClass("expanded", not isCollapsed)
            end,

            arrow,
            gui.Label {
                classes = { "treeLabel" },
                text = description,
            },
        }

        return gui.Panel {
            width = "100%",
            height = "auto",
            flow = "vertical",
            folderRow,
            contentPanel,
        }
    end

    -- Recursive tree builder for one folder level
    local function buildFolderChildren(folderId)
        local members = foldersToMembers[folderId] or {}
        local children = {}

        local sorted = {}
        for k, member in pairs(members) do
            sorted[#sorted + 1] = member
        end
        table.sort(sorted, function(a, b)
            --folders first; docs and pdfs interleave alphabetically.
            local aFolder = a.type == "folder"
            local bFolder = b.type == "folder"
            if aFolder ~= bFolder then return aFolder end
            return (a.description or "") < (b.description or "")
        end)

        for _, member in ipairs(sorted) do
            if member.type == "folder" then
                local expandThis = isAncestorOf(member.id, currentDocId)
                local subChildren = buildFolderChildren(member.id)
                children[#children + 1] = buildFolderEntry(member.id, member.description, expandThis, subChildren)
            else
                local isCurrentDoc = (member.id == currentDocId)
                --every tree glyph is now a monochrome Phosphor mask, so they
                --all tint @fg through the cascade and invert on hover; no
                --member needs the untinted-white path the full-colour art used.
                local memberIcon = member.icon or "phosphor/file-text.png"
                if member.type == "pdf" then
                    memberIcon = "phosphor/file-pdf.png"
                elseif member.type == "image" then
                    memberIcon = "phosphor/image.png"
                elseif member.type == "pdffragment" then
                    memberIcon = "phosphor/bookmark-simple.png"
                end
                children[#children + 1] = gui.Panel {
                    classes = { "treeRow", cond(isCurrentDoc, "currentDoc") },
                    press = function(element)
                        if m_pickHandled then return end
                        --non-doc members (pdf/image/pdffragment) open via
                        --OpenContent in every context; they are never a
                        --viewer tab or a nav target.
                        if member.content ~= nil then
                            m_pickHandled = true
                            element:ScheduleEvent("resetPickLatch", 0.1)
                            CustomDocument.OpenContent(member.content)
                            return
                        end
                        if opts ~= nil and opts.onPick ~= nil then
                            m_pickHandled = true
                            element:ScheduleEvent("resetPickLatch", 0.1)
                            opts.onPick(member.id)
                            return
                        end
                        if member.id == currentDocId then return end
                        if dialogPanel and dialogPanel.data then
                            dialogPanel:FireEvent("navigateToDocument", member.id)
                        end
                    end,
                    --the pick latch protects one PHYSICAL click from double
                    --dispatch during popup teardown; in the persistent rail
                    --the tree outlives the pick, so the latch must re-open
                    --shortly after instead of staying armed forever.
                    resetPickLatch = function(element)
                        m_pickHandled = false
                    end,

                    makeExpanderGhost(),
                    gui.Panel {
                        classes = { "treeIcon" },
                        bgimage = memberIcon,
                        --all glyphs are Phosphor masks now: inherit the
                        --treeIcon cascade (@fg, inverts to @bg on row hover).
                    },
                    gui.Label {
                        classes = { "treeLabel" },
                        text = member.description,
                    },
                }
            end
        end
        return children
    end

    -- Build root-level entries
    local rootChildren = {}
    local rootOrder = {"public", "private", "templates"}
    if game and game.currentMapId then rootOrder[#rootOrder + 1] = game.currentMapId end
    if dmhub and dmhub.loginUserid then rootOrder[#rootOrder + 1] = dmhub.loginUserid end

    for _, rootId in ipairs(rootOrder) do
        local root = builtinRoots[rootId]
        if root then
            local subChildren = buildFolderChildren(rootId)
            if #subChildren > 0 then
                --journal panel parity: built-in root folders start open
                --(a session toggle, remembered in buildFolderEntry, wins).
                rootChildren[#rootChildren + 1] = buildFolderEntry(rootId, root.description, true, subChildren, true)
            end
        end
    end

    if #rootChildren == 0 and (opts == nil or opts.onNewDocument == nil) then
        return nil
    end

    --"New Document" heads the popup when the caller can create documents:
    --a row with an expando arrow that unfolds the registered document
    --types, so a type can be picked right here without the create dialog.
    local headerPanels = {}
    if opts ~= nil and opts.onNewDocument ~= nil then
        local typeRows = {}
        local sortedTypes = {}
        for _, v in pairs(CustomDocument.documentTypes) do
            sortedTypes[#sortedTypes + 1] = v
        end
        table.sort(sortedTypes, function(a, b) return (a.text or "") < (b.text or "") end)
        for _, v in ipairs(sortedTypes) do
            typeRows[#typeRows + 1] = gui.Panel {
                classes = { "treeRow" },
                press = function(element)
                    if m_pickHandled then return end
                    m_pickHandled = true
                    element:ScheduleEvent("resetPickLatch", 0.1)
                    opts.onNewDocument(v)
                end,
                resetPickLatch = function(element)
                    m_pickHandled = false
                end,
                makeExpanderGhost(),
                gui.Panel {
                    classes = { "treeIcon" },
                    --Phosphor type glyph (or the generic page glyph); tints
                    --@fg through the treeIcon cascade like every other row.
                    bgimage = v.icon or "phosphor/file-text.png",
                },
                gui.Label {
                    classes = { "treeLabel" },
                    text = v.text,
                },
            }
        end

        headerPanels[#headerPanels + 1] = buildFolderEntry("newdocument", "New Document", false, typeRows, true)
        --hairline separating the create entry from the journal tree.
        headerPanels[#headerPanels + 1] = gui.Panel {
            width = "100%",
            height = 1,
            bgimage = "panels/square.png",
            classes = {"border"},
            styles = ThemeEngine.MergeTokens({
                { bgcolor = "@border" },
            }),
            vmargin = 3,
        }
    end

    local popupChildren = {}
    for _, p in ipairs(headerPanels) do
        popupChildren[#popupChildren + 1] = p
    end
    for _, p in ipairs(rootChildren) do
        popupChildren[#popupChildren + 1] = p
    end

    --the tree body shared by both hosts: an 8px left gutter (the journal
    --panel's root indent step) containing the rows.
    local function makeTreeBody()
        return gui.Panel {
            halign = "left",
            width = "100%-8",
            height = "auto",
            flow = "vertical",
            lmargin = 8,
            children = popupChildren,
        }
    end

    --bare mode: return just the tree rows (no popup chrome, no fixed size),
    --for callers that host the tree in their own container -- the viewer's
    --docked tree rail. The popup wrapper below stays for dropdown callers.
    if opts ~= nil and opts.bare then
        return gui.Panel {
            width = "100%",
            height = "auto",
            halign = "left",
            valign = "top",
            flow = "vertical",
            styles = treeStyles,
            makeTreeBody(),
        }
    end

    return gui.Panel {
        width = 0,
        height = 0,
        halign = "left",
        valign = "bottom",

        gui.Panel {
            styles = ThemeEngine.MergeStyles({
                {
                    selectors = {"journalTreePopup"},
                    bgcolor = "@bg",
                    borderColor = "@border",
                },
            }),
            classes = {"journalTreePopup"},
            bgimage = "panels/square.png",
            border = 1,
            width = 300,
            height = "auto",
            maxHeight = 400,
            halign = "left",
            valign = "top",
            flow = "vertical",
            vpad = 4,
            hpad = 4,

            gui.Panel {
                width = "100%",
                height = "auto",
                maxHeight = 392,
                flow = "vertical",
                vscroll = true,
                styles = treeStyles,
                makeTreeBody(),
            },
        },
    }
end

function CustomDocument:CreateInterface(args)

    local buttonSize = 20

    args = args or {}
    local readPanel = self:DisplayPanel{ relatedFooter = true }

    --The edit panel is the most expensive part of opening a document and most
    --opens never edit, so it is built lazily on first entry into edit mode.
    --nil until then; every consumer treats nil as "not editing".
    local writePanel = nil
    local m_bodyPanel --the writePanel/readPanel host; assigned below.

    local function GetOrCreateWritePanel()
        if writePanel ~= nil and writePanel.valid then
            return writePanel
        end
        writePanel = self:EditPanel(args)
        writePanel:SetClass("collapsed", true)
        --splice ahead of readPanel: the font-size monitor on m_bodyPanel
        --replaces the LAST child assuming it is readPanel.
        local children = m_bodyPanel.children
        table.insert(children, #children, writePanel)
        m_bodyPanel.children = children
        return writePanel
    end

    local function IsEditing()
        return writePanel ~= nil and writePanel.valid and not writePanel:HasClass("collapsed")
    end

    --forward-declared (defined with the find state below): the edit-mode
    --toggle re-fires the active find term at whichever panel it reveals.
    local FireFind

    local m_presentButton
    local m_playerPreviewButton

    local m_bubbleIconInput = nil
    if args.bubbleIcon then
        m_bubbleIconInput = gui.Input {
            text = args.bubbleIcon,
            cornerRadius = "50% height",
            width = 25,
            height = 25,
            hpad = 0,
            vpad = 0,
            valign = "center",
            textAlignment = "center",
            characterLimit = 3,
            placeholderText = "",
            editable = true,
            lmargin = 12,
            edit = function(element)
                for _, bubble in pairs(dmhub.infoBubbles) do
                    if bubble.document ~= nil and bubble.document.docid == self.id then
                        bubble:BeginChanges()
                        bubble.icon = element.text
                        bubble:CompleteChanges("Update bubble icon")
                        local dialog = element:FindParentWithClass("journalTabbedViewer")
                        if dialog then
                            dialog:FireEventTree("refreshTabBubbleIcon", self.id, element.text)
                        end
                        break
                    end
                end
            end,
        }
    end

    local m_bubbleLockIcon = nil
    if args.bubbleIcon then
        m_bubbleLockIcon = gui.Panel {
            classes = {"buttonIcon", "image"},
            width = 20,
            height = 20,
            valign = "center",
            lmargin = 8,
            linger = gui.Tooltip("Unlock to allow dragging on the map"),
            refreshLockIcon = function(element)
                for _, bubble in pairs(dmhub.infoBubbles) do
                    if bubble.document ~= nil and bubble.document.docid == self.id then
                        element.selfStyle.bgimage = cond(bubble.locked,
                            "icons/icon_tool/icon_tool_30.png",
                            "icons/icon_tool/icon_tool_30_unlocked.png")
                        return
                    end
                end
            end,
            create = function(element)
                element:FireEvent("refreshLockIcon")
            end,
            press = function(element)
                for _, bubble in pairs(dmhub.infoBubbles) do
                    if bubble.document ~= nil and bubble.document.docid == self.id then
                        bubble:BeginChanges()
                        bubble.locked = not bubble.locked
                        bubble:CompleteChanges(cond(bubble.locked,
                            "Lock info bubble", "Unlock info bubble"))
                        element:FireEvent("refreshLockIcon")
                        return
                    end
                end
            end,
        }
    end

    local m_titlePanel = args.titlePanel or gui.Panel {
        classes = {"collapsed"},
        halign = "left",
        valign = "center",
        width = "auto",
        height = "auto",
        flow = "horizontal",
        rmargin = 4,
        m_bubbleIconInput,
        m_bubbleLockIcon,
        gui.Input {
            text = self.description,
            fontSize = 14,
            width = 240,
            height = 20,
            valign = "center",
            lmargin = 12,
            characterLimit = 48,
            placeholderText = "Untitled document",
            placeholderAlpha = 0.35,
            editable = self:HaveEditPermissions(),
            editlag = 1.0,
            --styled like the search field: quiet hairline-weight edge.
            border = 1,
            borderColor = "#ffffff26",
            refreshDocument = function(element, doc)
                self = doc or self
            end,
            edit = function(element)
                if element.text ~= self.description then
                    local original = DeepCopy(self)
                    self.description = element.text
                    if writePanel ~= nil and not writePanel:HasClass("collapsed") then
                        writePanel:FireEventTree("savedoc")
                    end
                    self:Upload(original)
                    local dialog = element:FindParentWithClass("journalViewer")
                    if dialog then
                        dialog:FireEventTree("refreshNavButtons")
                        dialog:FireEventTree("refreshTabTitle", self.id, self.description)
                    end
                end
            end,
        },
    }

    local m_editingButton

    local resultPanel

    -- Write verification. After a save we expect the server to echo our document back:
    -- refreshGame (below) fires when /assets/objectTables/documents/table/<id> changes and
    -- confirms the save once the echoed doc.updateid matches our pendingUpload. If that
    -- confirmation does not arrive within SAVE_CONFIRM_TIMEOUT seconds, the watchdog in
    -- 'think' retries ONCE with a full (non-delta) document write; if the full write is
    -- also unconfirmed within the timeout, it surfaces a visible save error (red text in
    -- the journal save status area, driven by the 'saveError' class). The timeout is
    -- generous so a brief WebSocket reconnect -- whose queued writes replay on reconnect --
    -- still confirms inside the window rather than tripping a false failure. A late
    -- confirmation (e.g. after the connection recovers) clears the error automatically.
    local SAVE_CONFIRM_TIMEOUT = 12

    -- Periodic autosave. After an edit we schedule a save AUTOSAVE_IDLE_DELAY seconds out;
    -- each further edit pushes that out again (debounce). AUTOSAVE_MAX_DELAY caps the wait
    -- so continuous typing still flushes -- a save is forced that many seconds after the
    -- first edit of the current unsaved burst. Timing is stamped by the documentEdited
    -- handler and consumed by 'think'.
    local AUTOSAVE_IDLE_DELAY = 15
    local AUTOSAVE_MAX_DELAY = 60

    -- Issue a save and arm the confirmation watchdog. fullWrite=true forces a complete
    -- document upload with no delta baseline (used for the retry); otherwise the upload is
    -- a delta against the last server-confirmed baseline (data.original). Returns true if
    -- an upload was actually sent.
    local function BeginSaveAttempt(fullWrite)
        --flush every editable element's current content into the document object first.
        resultPanel:FireEventTree("savedoc")

        if not fullWrite and dmhub.DeepEqual(self, resultPanel.data.original) then
            --nothing changed since the confirmed baseline; nothing to upload.
            return false
        end

        local deltaFrom = nil
        if not fullWrite then
            deltaFrom = resultPanel.data.original
        end

        resultPanel.data.pendingUpload = self:Upload(deltaFrom)
        resultPanel.data.pendingUploadTime = dmhub.Time()
        resultPanel.data.pendingUploadFull = (fullWrite == true)
        resultPanel.data.pendingUploadFailed = nil

        --this attempt captures every edit up to now; reset the autosave debounce + cap.
        --(edits made after this point re-stamp the timers and earn their own save.)
        resultPanel.data.firstEditTime = nil
        resultPanel.data.editTime = nil

        --do NOT advance data.original here: it is the baseline the next save's delta is
        --computed from, and must only move forward once the server confirms this save
        --landed (see refreshGame). If this upload is lost, the next save's delta still
        --includes everything from this one.
        resultPanel.data.pendingOriginal = DeepCopy(self)

        --a new attempt supersedes any previously displayed save error.
        resultPanel:SetClassTree("saveError", false)

        if writePanel ~= nil and writePanel.valid then
            writePanel:FireEventTree("checkChanges", resultPanel.data.pendingOriginal)
        end
        return true
    end

    if dmhub.isDM then --and not args.presentationMode then
    -- Present to Players
        m_presentButton = gui.Button {
            classes = {"sizeS"},
            icon = "icons/icon_app/icon_app_34.png",
            escapeActivates = false,
            halign = "left",
            hmargin = 4,
            thinkTime = 0.2,
            think = function(element)
                --GameHud is false while the hud rebuilds (e.g. during a
                --code reload with this dialog open); skip the tick.
                local hud = GameHud and GameHud.instance
                if not hud then
                    return
                end
                local presentedDialog = hud.GetCurrentlyPresentedDialog()
                if presentedDialog ~= nil and presentedDialog.dialog == "document" and presentedDialog.args.docid == self.id then
                    element:SetClass("selected", true)
                else
                    element:SetClass("selected", false)
                end
            end,
            press = function(element)
                if element:HasClass("selected") then
                    GameHud.HidePresentedDialog()
                else
                    --make it so just closing out of present mode doesn't close the dialog for us.
                    element.parent.data.persistAfterPresentation = true
                    GameHud.PresentDialogToUsers(element.parent, "document", { docid = self.id })
                end
            end,
            destroy = function(element)
                --make sure when we close this dialog we stop it being presented.
                if element:HasClass("selected") then
                    GameHud.HidePresentedDialog()
                end
            end,
            hover = function(element)
                gui.Tooltip("Present to Players")(element)
            end,
        }
    end

    if self:HaveEditPermissions() and not args.presentationMode then
        -- Preview as player
        m_playerPreviewButton = gui.Button {
            classes = {"sizeS"},
            icon = "icons/icon_game/icon_game_193.png",
            escapeActivates = false,
            halign = "left",
            hmargin = 4,
            press = function(element)
                if m_editingButton ~= nil and m_editingButton:HasClass("selected") then
                    --if we are editing, stop editing.
                    m_editingButton:FireEvent("press")
                end
                resultPanel:SetClass("playerPreview", not resultPanel:HasClass("playerPreview"))
                element:SetClass("playerPreview", resultPanel:HasClass("playerPreview"))
                resultPanel:SetClass("selected", not resultPanel:HasClass("selected"))
                element:SetClass("selected", resultPanel:HasClass("selected"))
                resultPanel:FireEventTree("refreshDocument")
            end,
            hover = function(element)
                gui.Tooltip("Preview as Player")(element)
            end,
        }

        --editing button.
        m_editingButton = gui.Button {
            classes = {"sizeS"},
            icon = "icons/icon_tool/icon_tool_79.png",
            escapeActivates = false,
            halign = "left",
            hmargin = 4,
            press = function(element)
                if IsEditing() then
                    resultPanel:FireEventTree("savedoc")
                    if not dmhub.DeepEqual(self, resultPanel.data.original) then
                        self:Upload(resultPanel.data.original)
                    end
                else
                    resultPanel.data.original = DeepCopy(self)
                    resultPanel.data.pendingOriginal = nil
                    resultPanel.data.pendingUpload = nil
                end
                GetOrCreateWritePanel()
                writePanel:SetClass("collapsed", not writePanel:HasClass("collapsed"))
                readPanel:SetClass("collapsed", not readPanel:HasClass("collapsed"))
                element:SetClass("selected", not writePanel:HasClass("collapsed"))
                m_titlePanel:SetClass("collapsed", writePanel:HasClass("collapsed"))

                --carry an active find across the mode switch: re-fire it at
                --the panel that just became visible.
                if FireFind ~= nil then
                    FireFind(true)
                end

                element.thinkTime = cond(element:HasClass("selected"), 1)
            end,

            think = function(element)
                --compare against the most recent save the user has asked for
                --(confirmed or still pending) so the unsaved-changes indicator
                --clears as soon as they hit save, not when the server confirms.
                if writePanel ~= nil and writePanel.valid then
                    writePanel:FireEventTree("checkChanges", resultPanel.data.pendingOriginal or resultPanel.data.original)
                end
            end,

            hover = function(element)
                gui.Tooltip("Edit Document")(element)
            end,
            create = function(element)
                if args.edit then
                    element:FireEvent("press")
                end
            end,
        }
    end

    local m_controlMenuButtons = {}

    -- Back button
    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.Button {
        classes = {"sizeS"},
        icon = "icons/icon_arrow/icon_arrow_28.png",
        escapeActivates = false,
        halign = "left",
        hmargin = 4,
        rotate = 180,
        linger = function(element)
            gui.Tooltip("Back")(element)
        end,
        press = function(element)
            local dialogPanel = args.dialogPanel
            if dialogPanel == nil then return end
            local history = dialogPanel.data.history
            if #history == 0 then return end
            checkUnsavedChanges(writePanel, resultPanel, self, function()
                dialogPanel:FireEvent("navigateBack")
            end)
        end,
        refreshNavButtons = function(element)
            local dialogPanel = args.dialogPanel
            local hasHistory = dialogPanel ~= nil and #dialogPanel.data.history > 0
            element.interactable = hasHistory
        end,
    }

    -- Forward button
    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.Button {
        classes = {"sizeS"},
        icon = "icons/icon_arrow/icon_arrow_28.png",
        escapeActivates = false,
        halign = "left",
        hmargin = 4,
        linger = function(element)
            gui.Tooltip("Forward")(element)
        end,
        press = function(element)
            local dialogPanel = args.dialogPanel
            if dialogPanel == nil then return end
            local forwardHistory = dialogPanel.data.forwardHistory
            if #forwardHistory == 0 then return end
            checkUnsavedChanges(writePanel, resultPanel, self, function()
                dialogPanel:FireEvent("navigateForward")
            end)
        end,
        refreshNavButtons = function(element)
            local dialogPanel = args.dialogPanel
            local hasForward = dialogPanel ~= nil and #dialogPanel.data.forwardHistory > 0
            element.interactable = hasForward
        end,
    }

    -- Zoom out
    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.Button {
        classes = {"sizeS"},
        icon = "icons/icon_tool/icon_tool_41.png",
        escapeActivates = false,
        halign = "left",
        hmargin = 4,
        linger = function(element)
            gui.Tooltip(string.format("Decrease Font Size (Currently %d%%)", round(dmhub.GetSettingValue("journal:fontsize"))))(element)
        end,
        press = function(element)
            if dmhub.GetSettingValue("journal:fontsize") <= 20 then
                return
            end
            dmhub.SetSettingValue("journal:fontsize", dmhub.GetSettingValue("journal:fontsize") - 20)
        end,
    }

    -- Zoom in
    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.Button {
        classes = {"sizeS"},
        icon = "icons/icon_tool/icon_tool_40.png",
        escapeActivates = false,
        halign = "left",
        hmargin = 4,
        linger = function(element)
            gui.Tooltip(string.format("Increase Font Size (Currently %d%%)", round(dmhub.GetSettingValue("journal:fontsize"))))(element)
        end,
        press = function(element)
            if dmhub.GetSettingValue("journal:fontsize") > 300 then
                return
            end
            dmhub.SetSettingValue("journal:fontsize", dmhub.GetSettingValue("journal:fontsize") + 20)
        end,
    }

    -- Glossary hints quick-mute (view-local, never persisted): lets a
    -- director instantly silence term hints while performing or presenting,
    -- without touching the global preference.
    if dmhub.GetSettingValue("glossaryhints") ~= "off" then
        m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.Button {
            classes = {"sizeS"},
            icon = "ui-icons/eye.png",
            escapeActivates = false,
            halign = "left",
            hmargin = 4,
            data = { muted = false },
            linger = function(element)
                gui.Tooltip("Hide glossary hints in this view")(element)
            end,
            press = function(element)
                element.data.muted = not element.data.muted
                element:SetClass("selected", element.data.muted)
                if readPanel ~= nil and readPanel.valid then
                    readPanel:FireEvent("glossaryMute", element.data.muted)
                end
            end,
        }
    end

    if not args.presentationMode then
        m_controlMenuButtons[#m_controlMenuButtons + 1] = m_playerPreviewButton
    end

    m_controlMenuButtons[#m_controlMenuButtons + 1] = m_presentButton

    if not args.presentationMode then
        if self:HaveEditPermissions() then
            -- Edit external
            m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.Button {
                classes = {"sizeS"},
                icon = "ui-icons/icon-scale.png",
                escapeActivates = false,
                halign = "left",
                hmargin = 4,
                press = function(element)
                    if resultPanel.data.watcher ~= nil then
                        resultPanel.data.watcher:Destroy()
                        resultPanel.data.watcher = nil
                        element:SetClass("selected", resultPanel.data.watcher ~= nil)
                        return
                    end
                    resultPanel.data.watcherContent = self:GetTextContent()
                    resultPanel.data.watcher = dmhub.OpenTextFileInConnectedEditor(self.description, self:GetTextContent(),
                        function(contents)
                            if resultPanel.data == nil then
                                return
                            end
                            if #contents > self.MaxLength then
                                contents = contents:sub(1, self.MaxLength)
                                gui.ModalMessage {
                                    title = "Document Too Long",
                                    message = string.format("The document you are editing is too long. A document may be up to %d characters.", CustomDocument.MaxLength)
                                }
                            end
                            local original = DeepCopy(self)
                            self:SetTextContent(contents)
                            resultPanel.data.watcherContent = self:GetTextContent()
                            resultPanel:FireEventTree("editDocument", contents)
                            resultPanel:FireEventTree("refreshDocument")
                            self:Upload(original)
                        end)
                    element:SetClass("selected", resultPanel.data.watcher ~= nil)
                end,
                hover = function(element)
                    gui.Tooltip("Edit in External Editor")(element)
                end,
            }
        end

        m_controlMenuButtons[#m_controlMenuButtons + 1] = m_editingButton
    end

    m_controlMenuButtons[#m_controlMenuButtons + 1] = m_titlePanel

    --Document type picker: an icon + label that opens a menu of the plain
    --types (narration/exploration/combat/location/npc). Shown only for plain
    --docs -- the functional subtypes (montage/negotiation) pin their type and
    --so never resolve to a plain id here -- and only to editors.
    do
        local plainTypes = { "note", "narration", "exploration", "combat", "location", "npc" }
        local currentId = CustomDocument.DocTypeId(self)
        local isPlain = false
        for _, t in ipairs(plainTypes) do
            if t == currentId then isPlain = true break end
        end

        if isPlain and (dmhub.isDM or self:HaveEditPermissions()) then
            local typeIconPanel, typeLabel
            local function SyncType()
                local info = CustomDocument.DocTypeInfo(self)
                if typeIconPanel ~= nil and typeIconPanel.valid then typeIconPanel.bgimage = info.icon end
                if typeLabel ~= nil and typeLabel.valid then typeLabel.text = info.text end
            end
            typeIconPanel = gui.Panel {
                width = 14, height = 14, valign = "center",
                bgimage = CustomDocument.DocTypeIcon(self),
                bgcolor = "@fg", --monochrome Phosphor mask, tinted as chrome
            }
            typeLabel = gui.Label {
                classes = { "fgMuted" },
                width = "auto", height = "auto", valign = "center",
                fontSize = 13, lmargin = 5,
                text = CustomDocument.DocTypeInfo(self).text,
            }
            m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.Panel {
                flow = "horizontal",
                width = "auto", height = "auto",
                halign = "left", valign = "center",
                hmargin = 8, borderBox = true, hpad = 6, vpad = 3,
                bgimage = "panels/square.png",
                styles = ThemeEngine.MergeTokens({
                    { bgcolor = "clear", cornerRadius = 4 },
                    { selectors = { "hover" }, bgcolor = "@fgMuted" },
                }),
                linger = function(element)
                    gui.Tooltip("Document type")(element)
                end,
                press = function(element)
                    local entries = {}
                    for _, t in ipairs(plainTypes) do
                        local info = CustomDocument.docTypeInfo[t]
                        entries[#entries + 1] = {
                            text = info.text,
                            click = function()
                                element.popup = nil
                                self.docType = t
                                self:Upload()
                                SyncType()
                            end,
                        }
                    end
                    element.popup = gui.ContextMenu { entries = entries }
                end,
                children = { typeIconPanel, typeLabel },
            }
        end
    end

    local m_closeButton = gui.Button {
        classes = { "closeButton", "sizeXs", cond(args.suppressCloseButton or args.presentationMode or (args.dialog == nil and args.close == nil), "collapsed") },
        hmargin = 4,
        closedocuments = function(element)
            element:FireEvent("press")
        end,
        press = function(element)
            local function doClose()
                if args.close then
                    args.close()
                else
                    args.dialog:DestroySelf()
                end
            end
            checkUnsavedChanges(writePanel, resultPanel, self, doClose)
        end,
    }

    local m_breadcrumb = gui.Label {
        classes = {"fgMuted"},
        text = buildBreadcrumbText(self),
        halign = "left",
        valign = "center",
        width = "auto",
        maxWidth = "60%",
        height = "auto",
        markdown = true,
        lmargin = 8,
        textOverflow = "ellipsis",
        textWrap = false,
        press = function(element)
            if element.popup then
                element.popup = nil
                return
            end
            local docId = self.id
            local dp = args.dialogPanel
            if dp and dp.data and dp.data.currentDocId then
                docId = dp.data.currentDocId
            end
            element.popupPositioning = "panel"
            element.popup = buildJournalTree(docId, args.dialogPanel)
        end,
        refreshNavButtons = function(element)
            local dialogPanel = args.dialogPanel
            if dialogPanel and dialogPanel.data and dialogPanel.data.currentDocId then
                local docTable = dmhub.GetTable(CustomDocument.tableName) or {}
                local currentDoc = docTable[dialogPanel.data.currentDocId]
                if currentDoc then
                    element.text = buildBreadcrumbText(currentDoc)
                end
            end
        end,
    }

    --Find-in-page state for THIS page (the interface is rebuilt per
    --document, so the term/position are naturally per-page). The search box
    --drives it; MarkdownDocument's findInPage event does the marking,
    --counting, and scrolling, reporting the count back synchronously.
    local m_findState = { term = nil, index = 1, count = 0 }
    local m_findRowLabel = nil
    local m_searchInput

    FireFind = function(onlyIfActive)
        if onlyIfActive and m_findState.term == nil then
            return
        end
        --the display panel and the live editor both implement findInPage;
        --target whichever is currently visible.
        local target = readPanel
        if writePanel ~= nil and writePanel.valid and not writePanel:HasClass("collapsed") then
            target = writePanel
        end
        if target == nil or not target.valid then
            return
        end
        target:FireEvent("findInPage", {
            term = m_findState.term,
            index = m_findState.index,
            callback = function(count)
                m_findState.count = count
            end,
        })
    end

    local function FindRowText()
        if m_findState.count == 1 then
            return "1 match"
        end
        return string.format("%d/%d matches", m_findState.index, m_findState.count)
    end

    local function CycleFind(delta)
        if m_findState.term == nil or m_findState.count == 0 then
            return
        end
        m_findState.index = ((m_findState.index - 1 + delta) % m_findState.count) + 1
        FireFind()
        if m_findRowLabel ~= nil and m_findRowLabel.valid then
            m_findRowLabel.text = FindRowText()
        end
    end

    m_searchInput = gui.SearchInput {
        classes = {"sizeXs"},
        width = 240,
        height = 20,
        halign = "right",
        valign = "center",
        rmargin = 4,
        placeholderText = "Search journal...",
        placeholderAlpha = 0.35,
        --hairline-weight edge (gold @ 0.15, matching the row dividers) set
        --inline because the themed input frame outranks scoped styles.
        border = 1,
        borderColor = "#ffffff26",
        popupPositioning = "panel",

        --Enter steps to the next on-page match.
        submit = function(element)
            CycleFind(1)
        end,

        search = function(element, text)
            if text == nil or text == "" then
                if m_findState.term ~= nil then
                    m_findState.term = nil
                    m_findState.index = 1
                    m_findState.count = 0
                    FireFind()
                end
                element.popup = nil
                return
            end

            --update the on-page highlights. An unchanged term (e.g. the
            --change event re-firing on Enter) keeps its position.
            if text ~= m_findState.term then
                m_findState.term = text
                m_findState.index = 1
                FireFind()
            end

            --a programmatic text set (carry-the-term navigation) should
            --highlight but not pop the results list open.
            if not element:HasClass("focus") then
                return
            end

            local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
            local accessibleRoots = CustomDocument.GetAccessibleRoots()
            local results = {}
            for docId, doc in pairs(customDocs) do
                if docId ~= self.id and not doc.hidden and (dmhub.isDM or not doc.hiddenFromPlayers) and CustomDocument.IsDocInAccessibleRoot(doc, accessibleRoots) then
                    local titleMatch = string.find(string.lower(doc.description or ""), text, 1, true)
                    local contentMatch = doc.MatchesSearch and doc:MatchesSearch(text)
                    if titleMatch or contentMatch then
                        local score = 0
                        local name = doc.description or "Untitled"
                        local nameLower = string.lower(name)
                        if nameLower == text then
                            score = 100
                        elseif string.starts_with(nameLower, text) then
                            score = 75
                        elseif titleMatch then
                            score = 50
                        else
                            score = 25
                        end
                        results[#results + 1] = {
                            name = name,
                            score = score,
                            docId = docId,
                        }
                    end
                end
            end

            table.stable_sort(results, function(a, b) return a.score > b.score end)
            while #results > 10 do
                table.remove(results)
            end

            if #results == 0 and m_findState.count == 0 then
                element.popup = gui.Label {
                    classes = {"bg"},
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "bottom",
                    fontSize = 14,
                    bgimage = true,
                    pad = 8,
                    text = "No results found",
                }
                return
            end

            local function SectionLabel(t)
                return gui.Label {
                    classes = { "fgMuted", "bold" },
                    width = "100%",
                    height = "auto",
                    fontSize = 11,
                    borderBox = true,
                    hpad = 8,
                    tmargin = 6,
                    bmargin = 2,
                    text = t,
                }
            end

            local rows = {}

            if m_findState.count > 0 then
                rows[#rows + 1] = SectionLabel("ON THIS PAGE")
                local function ArrowButton(glyph, delta, tip)
                    return gui.Button {
                        classes = { "sizeXs" },
                        width = 22,
                        height = 18,
                        fontSize = 12,
                        valign = "center",
                        hmargin = 2,
                        text = glyph,
                        swallowPress = true,
                        press = function()
                            CycleFind(delta)
                        end,
                        linger = function(btnElement)
                            gui.Tooltip(tip)(btnElement)
                        end,
                    }
                end
                --width "auto", NOT "100% available": the latter resolves to
                --zero here and the text renders one character per line.
                m_findRowLabel = gui.Label {
                    classes = { "fg" },
                    width = "auto",
                    height = "auto",
                    minWidth = 180,
                    fontSize = 14,
                    valign = "center",
                    halign = "left",
                    textWrap = false,
                    borderBox = true,
                    hpad = 8,
                    text = FindRowText(),
                }
                rows[#rows + 1] = gui.Panel {
                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    borderBox = true,
                    vpad = 2,
                    m_findRowLabel,
                    ArrowButton("<", -1, "Previous match"),
                    ArrowButton(">", 1, "Next match (Enter)"),
                }
            end

            if #results > 0 then
                rows[#rows + 1] = SectionLabel("OTHER DOCUMENTS")
                for _, result in ipairs(results) do
                    rows[#rows + 1] = gui.Label {
                        classes = { "fg", "hoverable" },
                        bgimage = "panels/square.png",
                        bgcolor = "#00000000",
                        width = "100%",
                        height = "auto",
                        fontSize = 14,
                        borderBox = true,
                        hpad = 8,
                        vpad = 3,
                        text = string.format("<b>%s</b>", result.name),
                        press = function()
                            element.popup = nil
                            if args.dialogPanel and args.dialogPanel.data then
                                --carry the term: the destination page's
                                --interface seeds its find from this and
                                --arrives highlighted at the first match.
                                args.dialogPanel.data.pendingFind = text
                                args.dialogPanel:FireEvent("navigateToDocument", result.docId)
                            end
                        end,
                    }
                end
            end

            element.popupsInheritStyles = true
            element.popup = gui.Panel {
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "bottom",
                constrainToScreen = true,
                gui.Panel {
                    classes = { "bordered", "bg" },
                    flow = "vertical",
                    width = 300,
                    height = "auto",
                    maxHeight = 400,
                    vscroll = true,
                    borderBox = true,
                    pad = 4,
                    children = rows,
                },
            }
        end,
    }

    --Codex Design System treatment for the journal top bar (the design
    --project's Journal Toolbar spec, rows 1-2): warm-black bar surface,
    --hairline row separators, ghost icon buttons that only show chrome on
    --hover, and a gold-accented selected state. Corner radii are
    --deliberately left to the user's theme (squared vs rounded). Hardcoded
    --colors are the same design-trial decision as the format toolbar in
    --MarkdownDocument.lua.
    --icon buttons are true ghosts at rest (transparent, per the handoff);
    --hover conjures the warm-black fill and gold edge, and the selected
    --state goes gold-dim -- so Edit/Present/Preview read as toggles.
    local dsTopBarStyles = {
        {
            selectors = { "iconButton" },
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            border = 1,
            borderColor = "#00000000",
        },
        {
            selectors = { "iconButton", "hover" },
            bgcolor = "#222228",
            borderColor = "#ffffff99",
        },
        --priority 6: the theme's {iconButton, selected} rule is priority 5 and
        --fills the chrome @accent -- the same color the theme tints the selected
        --glyph (and near-identical to @fg in the default scheme) -- so without
        --outranking it the icon vanishes into its own highlight. The dim fill
        --below keeps the @accent glyph readable.
        {
            selectors = { "iconButton", "selected" },
            bgcolor = "#ffffff1f",
            borderColor = "#ffffff99",
            priority = 6,
        },
        {
            selectors = { "iconButton", "selected", "hover" },
            bgcolor = "#ffffff59",
            borderColor = "#ffffff99",
            priority = 6,
        },
        --design icon-button footprint: 34px squares (the themed sizeS
        --default is smaller) with breathing room between the outlined
        --buttons. Two selectors to match the theme rule's specificity.
        --The close button (sizeXs) deliberately stays small.
        {
            selectors = { "iconButton", "sizeS" },
            width = 34,
            height = 34,
            hmargin = 5,
        },
    }

    local function TopBarHairline()
        return gui.Panel{
            width = "100%",
            height = 1,
            bgimage = "panels/square.png",
            bgcolor = "#ffffff26",
        }
    end

    local m_topBar = gui.Panel {
        classes = {"surfaceLinear", "journalTopBar"},
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#0d0d0d",
        styles = ThemeEngine.MergeTokens(dsTopBarStyles),

        --window-shade: the tabbed viewer rolls up to just the tab strip, so
        --the breadcrumb/search and tool rows hide along with the body.
        journalShade = function(element, shaded)
            element:SetClass("collapsed", shaded)
        end,

        -- Row 1: breadcrumb + search + close. Design metrics: 11px vertical
        -- breathing room, 16px inset from the edges.
        gui.Panel {
            width = "100%",
            height = 42,
            flow = "horizontal",
            borderBox = true,
            hpad = 16,

            m_breadcrumb,
            m_searchInput,
            m_closeButton,
        },

        TopBarHairline(),

        -- Row 2: tool buttons + document name
        gui.Panel {
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "left",
            valign = "top",
            borderBox = true,
            hpad = 16,
            vpad = 10,
            wrap = true,
            children = m_controlMenuButtons,
        },

        TopBarHairline(),
    }

    local monitorGame = nil
    if not self.readonly then
        monitorGame = "/assets/objectTables/documents/table/" .. self.id
    end

    m_bodyPanel = gui.Panel {
        width = "100%-24",
        height = "100% available",
        vscroll = self.vscroll,
        halign = "center",
        bmargin = 8,

        --window-shade: the tabbed viewer collapses the document body,
        --leaving only the tab strip visible.
        journalShade = function(element, shaded)
            element:SetClass("collapsed", shaded)
        end,

        --writePanel is spliced in ahead of readPanel by GetOrCreateWritePanel
        --on first entry into edit mode.
        readPanel,

        multimonitor = { "journal:fontsize" },
        monitor = function(element)
            g_scale = nil
            local newReadPanel = self:DisplayPanel{ relatedFooter = true }
            newReadPanel:SetClass("collapsed", readPanel:HasClass("collapsed"))
            readPanel = newReadPanel

            local children = element.children
            children[#children] = newReadPanel
            element.children = children
        end,
    }

    resultPanel = gui.Panel {
        classes = {"documentPanel"},
        monitorGame = monitorGame,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        flow = "vertical",
        closetab = function(element)
            local function doClose()
                if args.close then
                    args.close()
                end
            end
            checkUnsavedChanges(writePanel, resultPanel, self, doClose)
        end,

        refreshGame = function(element)
            if self.readonly then
                return
            end
            local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[self.id]
            if doc == nil then
                --the document row is gone (e.g. hard-deleted while open). Nothing
                --to confirm or refresh, and dereferencing doc.updateid below would
                --throw, so bail out.
                return
            end

            if writePanel ~= nil and not writePanel:HasClass("collapsed") then

                if resultPanel.data.pendingUpload ~= nil and doc.updateid == resultPanel.data.pendingUpload then
                    --we got a confirmation of our save going through. Only now
                    --do we promote the saved snapshot to the delta baseline:
                    --refreshGame fires off the server echo of our patch, so
                    --reaching here means the write really landed server-side.
                    if resultPanel.data.pendingOriginal ~= nil then
                        resultPanel.data.original = resultPanel.data.pendingOriginal
                        resultPanel.data.pendingOriginal = nil
                    end
                    resultPanel.data.pendingUpload = nil
                    resultPanel.data.pendingUploadTime = nil
                    resultPanel.data.pendingUploadFull = nil
                    resultPanel.data.pendingUploadFailed = nil
                    resultPanel.data.saveConfirmed = true
                    --a confirmation (even a late one, after the connection recovered)
                    --clears any save error we may have surfaced in the meantime.
                    resultPanel:SetClassTree("saveError", false)
                    element:FireEventTree("saveConfirmed")
                end

                --if we are editing, don't refresh the document.
                return
            end

            element:FireEventTree("refreshDocument", doc)
        end,

        saveDocument = function(element)
            --normal (delta) save. The write-verification watchdog in 'think' escalates to
            --a full write and then to a visible error if the server never confirms this.
            BeginSaveAttempt(false)
        end,

        documentEdited = function(element)
            --periodic-autosave bookkeeping, fired by the editor on each edit. firstEditTime
            --marks the start of the current unsaved burst (drives the AUTOSAVE_MAX_DELAY cap
            --and is only set on a clean->dirty transition so continuous typing cannot keep
            --pushing the cap out); editTime is the most recent edit (drives the
            --AUTOSAVE_IDLE_DELAY debounce, reset by every edit). Both clear when a save runs.
            local now = dmhub.Time()
            if resultPanel.data.firstEditTime == nil then
                resultPanel.data.firstEditTime = now
            end
            resultPanel.data.editTime = now
        end,

        thinkTime = 0.2,
        think = function(element)
            --make sure we keep the content in sync with the locally editing file.
            if element.data.watcher ~= nil then
                local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[self.id]
                if doc ~= nil and doc:GetTextContent() ~= element.data.watcherContent then
                    element.data.watcherContent = doc:GetTextContent()
                    element.data.watcher:WriteContents(doc:GetTextContent())
                end
            end

            --periodic autosave. firstEditTime/editTime are stamped by documentEdited. Save
            --AUTOSAVE_IDLE_DELAY seconds after the last edit (debounce), or force a save once
            --AUTOSAVE_MAX_DELAY seconds have passed since the first edit of this burst (cap).
            --Only while actually editing. BeginSaveAttempt clears the timers and no-ops via
            --its DeepEqual guard if nothing truly changed (e.g. edits that cancelled out), in
            --which case we clear the timers here so we don't re-check every tick.
            if resultPanel.data.firstEditTime ~= nil and IsEditing() then
                local now = dmhub.Time()
                if (now - resultPanel.data.editTime) >= AUTOSAVE_IDLE_DELAY or (now - resultPanel.data.firstEditTime) >= AUTOSAVE_MAX_DELAY then
                    if BeginSaveAttempt(false) then
                        resultPanel:SetClassTree("savePending", true)
                    else
                        resultPanel.data.firstEditTime = nil
                        resultPanel.data.editTime = nil
                    end
                end
            end

            --write-verification watchdog. A save sets data.pendingUpload (the updateid we
            --expect echoed back) and data.pendingUploadTime. If the server has not confirmed
            --within SAVE_CONFIRM_TIMEOUT, retry once with a full document write; if the full
            --write is also unconfirmed, surface a visible save error. pendingUploadFailed
            --latches the error state without clearing pendingUpload, so a late confirmation
            --(refreshGame) can still clear the error if the connection recovers.
            if resultPanel.data.pendingUpload ~= nil and resultPanel.data.pendingUploadTime ~= nil and not resultPanel.data.pendingUploadFailed then
                local elapsed = dmhub.Time() - resultPanel.data.pendingUploadTime
                if elapsed >= SAVE_CONFIRM_TIMEOUT then
                    if not resultPanel.data.pendingUploadFull then
                        dmhub.Debug(string.format("JOURNAL_SAVE:: delta upload for document '%s' not confirmed after %.1fs; retrying with a full document write.", tostring(self.id), elapsed))
                        BeginSaveAttempt(true)
                    else
                        dmhub.CloudError(string.format("JOURNAL_SAVE:: full document write for '%s' not confirmed after %.1fs; surfacing save error to user.", tostring(self.id), elapsed))
                        resultPanel.data.pendingUploadFailed = true
                        resultPanel:SetClassTree("savePending", false)
                        resultPanel:SetClassTree("saveError", true)
                        element:FireEventTree("saveFailed")
                    end
                end
            end
        end,

        destroy = function(element)
            if resultPanel.data.watcher ~= nil then
                resultPanel.data.watcher:Destroy()
                resultPanel.data.watcher = nil
            end
        end,

        m_topBar,

        m_bodyPanel,
    }

    --Carry-the-term navigation: a search-result jump stores the term on the
    --viewer before navigating; the destination page's interface (this one)
    --seeds its find from it so the page arrives highlighted and scrolled to
    --the first match. The box is seeded too, but unfocused, so no popup.
    if args.dialogPanel ~= nil and args.dialogPanel.data ~= nil and args.dialogPanel.data.pendingFind then
        local pending = args.dialogPanel.data.pendingFind
        args.dialogPanel.data.pendingFind = nil
        m_findState.term = pending
        m_findState.index = 1
        m_searchInput.text = pending
        FireFind()
    end

    return resultPanel
end

local function DialogResizePanel(self, dialogWidth, dialogHeight)

    local parentPanel

    local GetDialog = function()
        return parentPanel.parent
    end

    --handle on right
    local rightHandle = gui.Panel {
        styles = {
            {
                width = 8,
                height = "100%-32",
                valign = "top",
                halign = "left",
            }
        },
        x = dialogWidth - 8,
        y = 0,
        floating = true,
        swallowPress = true,
        bgimage = true,
        bgcolor = "clear",
        hoverCursor = "horizontal-expand",
        dragBounds = { x1 = 100, y1 = -1200, x2 = 1500, y2 = -100 },
        draggable = true,
        beginDrag = function(element)
            element.data.beginPos = {
                x = element.x,
                y = element.y,
            }
        end,
        drag = function(element)
            local dialog = GetDialog()
            element.x = element.xdrag
            self._tmp_location = {
                x = dialog.x,
                y = dialog.y,
                width = dialog.selfStyle.width,
                height = dialog.selfStyle.height,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y
            }
            parentPanel:FireEventTree("resize", element, {deltax = element.x - element.data.beginPos.x})
        end,
        dragging = function(element)
            local dialog = GetDialog()
            dialog.selfStyle.width = element.xdrag + 8
        end,

        resize = function(element, callingElement, delta)
            if callingElement == element then
                return
            end

            element.x = element.x + (delta.deltax or 0)
        end,
    }

    --handle on bottom
    local bottomHandle = gui.Panel {
        styles = {
            {
                width = "100%-32",
                height = 8,
                valign = "top",
                halign = "left",
            }
        },
        x = 0,
        y = dialogHeight - 8,
        floating = true,
        swallowPress = true,
        bgimage = true,
        bgcolor = "clear",
        hoverCursor = "vertical-expand",
        dragBounds = { x1 = 100, y1 = -1200, x2 = 1500, y2 = -100 },
        draggable = true,
        beginDrag = function(element)
            element.data.beginPos = {
                x = element.x,
                y = element.y,
            }
        end,
        drag = function(element)
            local dialog = GetDialog()
            element.y = element.ydrag
            self._tmp_location = {
                x = dialog.x,
                y = dialog.y,
                width = dialog.selfStyle.width,
                height = dialog.selfStyle.height,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y
            }
            parentPanel:FireEventTree("resize", element, {deltay = element.y - element.data.beginPos.y})
        end,
        dragging = function(element)
            local dialog = GetDialog()
            dialog.selfStyle.height = element.ydrag + 8
        end,

        resize = function(element, callingElement, delta)
            if callingElement == element then
                return
            end

            element.y = element.y + (delta.deltay or 0)
        end,
    }

    --handle in bottom right
    local bottomRightHandle = gui.Panel {
        styles = {
            {
                width = 32,
                height = 32,
                valign = "top",
                halign = "left",
            }
        },
        x = dialogWidth - 32,
        y = dialogHeight - 32,
        floating = true,
        swallowPress = true,
        bgimage = true,
        bgcolor = "clear",
        hoverCursor = "diagonal-expand",
        dragBounds = { x1 = 100, y1 = -1200, x2 = 1500, y2 = -100 },
        draggable = true,
        beginDrag = function(element)
            element.data.beginPos = {
                x = element.x,
                y = element.y,
            }
        end,
        drag = function(element)
            local dialog = GetDialog()
            element.x = element.xdrag
            element.y = element.ydrag
            self._tmp_location = {
                x = dialog.x,
                y = dialog.y,
                width = dialog.selfStyle.width,
                height = dialog.selfStyle.height,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y
            }
            parentPanel:FireEventTree("resize", element, {deltax = element.x - element.data.beginPos.x, deltay = element.y - element.data.beginPos.y})
        end,
        dragging = function(element)
            local dialog = GetDialog()
            dialog.selfStyle.width = element.xdrag + 32
            dialog.selfStyle.height = element.ydrag + 32
        end,
        resize = function(element, callingElement, delta)
            if callingElement == element then
                return
            end

            element.x = element.x + (delta.deltax or 0)
            element.y = element.y + (delta.deltay or 0)
        end,
    }

    parentPanel = gui.Panel{
        floating = true,
        width = "100%",
        height = "100%",
        rightHandle,
        bottomHandle,
        bottomRightHandle,
    }

    return parentPanel

end

local function CreateTabButton(doc, tabbedViewer, tabId, bubbleIcon)
    local tabButton
    local children = {}

    local tabLabelStyles = {
        {
            selectors = {"label"},
            width = "auto",
            height = "auto",
            valign = "center",
            textWrap = false,
            textOverflow = "ellipsis",
            maxWidth = TAB_MAX_WIDTH - 40,
            rmargin = 2,
        },
        --design tab type size; two selectors to outrank the theme's sizeXs
        --sizing.
        {
            selectors = {"label", "sizeXs"},
            fontSize = 13.5,
        },
    }

    --the doc's semantic-type glyph, same as its tree row -- so an open tab
    --carries the same icon you clicked to open it. Guarded: non-custom docs
    --(pdf/image) have no DocTypeIcon and fall back to the generic page glyph.
    local tabTypeIcon = nil
    pcall(function() tabTypeIcon = CustomDocument.DocTypeIcon(doc) end)
    children[#children + 1] = gui.Panel {
        classes = {"tabTypeIcon"},
        bgimage = tabTypeIcon or "phosphor/file-text.png",
        width = 14,
        height = 14,
        valign = "center",
        rmargin = 6,
        --keep in step if the doc's type changes while the tab is open.
        refreshTabTitle = function(element, docId, newTitle)
            if docId == tabButton.data.docId then
                local icon = nil
                pcall(function() icon = CustomDocument.DocTypeIcon(doc) end)
                element.bgimage = icon or "phosphor/file-text.png"
            end
        end,
    }

    if bubbleIcon then
        children[#children + 1] = gui.Label {
            styles = tabLabelStyles,
            classes = {"sizeXs", "fgStrong"},
            text = "(" .. bubbleIcon .. ")",
            refreshTabBubbleIcon = function(element, docId, newIcon)
                if docId == tabButton.data.docId then
                    element.text = "(" .. newIcon .. ")"
                end
            end,
        }
    end

    children[#children + 1] = gui.Label {
        styles = tabLabelStyles,
        classes = {"sizeXs", "fgStrong"},
        text = doc.description or "Untitled",
        refreshTabTitle = function(element, docId, newTitle)
            if docId == tabButton.data.docId then
                element.text = newTitle
            end
        end,
    }

    children[#children + 1] = gui.Panel {
        classes = {"multiselectChipRemove"},
        hidden = 0,
        press = function(element)
            tabbedViewer:FireEvent("closeTab", tabButton.data.tabId)
        end,
        gui.Label {
            classes = {"multiselectChipRemove"},
            text = "X",
        },
    }

    tabButton = gui.Panel {
        classes = {"panel", "tab", "journalTab"},
        height = TAB_HEIGHT,
        width = "auto",
        maxWidth = TAB_MAX_WIDTH,
        flow = "horizontal",
        halign = "left",
        valign = "bottom",
        hpad = 11,
        vpad = 4,
        data = { tabId = tabId, docId = doc.id },
        press = function(element)
            tabbedViewer:FireEvent("switchToTab", element.data.tabId)
        end,
        --window-shade: double-clicking a tab rolls the window up to just the
        --tab strip (and back). The press above still runs, which just
        --switches to this tab -- harmless.
        doubleclick = function(element)
            tabbedViewer:FireEvent("toggleShade")
        end,
        rightClick = function(element)
            --Director-side: add the tab's document to the Run panel. rawget
            --because the RunAgenda hook lives in CampaignTrackerPanel.
            if not dmhub.isDM or rawget(_G, "RunAgenda") == nil then
                return
            end
            local tabDoc = (dmhub.GetTable(CustomDocument.tableName) or {})[element.data.docId]
            if tabDoc == nil then
                return
            end
            element.popup = gui.ContextMenu {
                entries = {
                    {
                        text = "Add to Run",
                        click = function()
                            element.popup = nil
                            RunAgenda.AddDocument(tabDoc)
                        end,
                    },
                },
            }
        end,
        children = children,
    }
    return tabButton
end

--Read-only: the doc id of the journal document currently shown in the tabbed journal
--viewer (its active tab), or nil if the viewer isn't open. Unlike
--GetOrCreateTabbedViewer this never creates a viewer as a side effect.
function CustomDocument.GetCurrentJournalDocId()
    local viewer = g_tabbedViewer
    if viewer == nil or not viewer.valid then
        return nil
    end

    for _, tab in ipairs(viewer.data.tabs) do
        if tab.tabId == viewer.data.activeTabId then
            return tab.docId
        end
    end

    return nil
end

function CustomDocument.GetOrCreateTabbedViewer()
    if g_tabbedViewer ~= nil and g_tabbedViewer.valid then
        return g_tabbedViewer
    end

    local dialogWidth = 1100
    local dialogHeight = 940
    local loc = {
        x = 1920 * 0.5 * ((dmhub.screenDimensionsBelowTitlebar.x / dmhub.screenDimensionsBelowTitlebar.y) / (1920 / 1080)) - dialogWidth / 2,
        y = 1080 * 0.5 - dialogHeight / 2,
        width = dialogWidth,
        height = dialogHeight,
    }

    local refreshTabVisibility

    local tabScrollLeft = gui.Button {
        classes = {"pagingArrow", "left"},
        height = TAB_BAR_HEIGHT / 2,
        valign = "center",
        press = function(element)
            local v = element:FindParentWithClass("journalTabbedViewer")
            local tabs = v.data.tabs
            for i, tab in ipairs(tabs) do
                if tab.tabId == v.data.activeTabId and i > 1 then
                    v:FireEvent("switchToTab", tabs[i - 1].tabId)
                    break
                end
            end
        end,
    }

    local tabScrollRight = gui.Button {
        classes = {"pagingArrow", "right"},
        height = TAB_BAR_HEIGHT / 2,
        valign = "center",
        lmargin = 4,
        press = function(element)
            local v = element:FindParentWithClass("journalTabbedViewer")
            local tabs = v.data.tabs
            for i, tab in ipairs(tabs) do
                if tab.tabId == v.data.activeTabId and i < #tabs then
                    v:FireEvent("switchToTab", tabs[i + 1].tabId)
                    break
                end
            end
        end,
    }

    local closeAllButton = gui.Button {
        classes = {"closeButton", "sizeXs"},
        valign = "center",
        halign = "right",
        hmargin = -4,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        click = function(element)
            local v = element:FindParentWithClass("journalTabbedViewer")
            v:FireEvent("closeAllTabs")
        end,
        linger = function(element)
            gui.Tooltip("Close all tabs")(element)
        end,
    }

    local tabButtonsPanel = gui.Panel {
        valign = "bottom",
        height = TAB_BAR_HEIGHT,
        width = "auto",
        flow = "horizontal",
        halign = "left",
    }

    local tabArrowsPanel = gui.Panel {
        width = "auto",
        height = TAB_BAR_HEIGHT,
        halign = "right",
        rmargin = 8,
        flow = "horizontal",
        tabScrollLeft,
        tabScrollRight,
        closeAllButton,
    }

    --Codex Design System treatment for the tab strip (the design's Bar 0):
    --the strip sits on the deepest surface; inactive tabs are ghosts with
    --soft text, hover steps the surface, and the active tab gets the
    --surface-2 fill with a gold edge and parchment text. Corner radii stay
    --with the theme (the rounded theme already rounds only tab tops).
    local dsTabStyles = {
        {
            selectors = { "tab", "journalTab" },
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            border = 1,
            borderColor = "#00000000",
        },
        {
            selectors = { "tab", "journalTab", "hover" },
            bgcolor = "#222228",
        },
        {
            selectors = { "tab", "journalTab", "selected" },
            bgcolor = "#1a1a1e",
            borderColor = "#ffffff99",
        },
        {
            selectors = { "label", "parent:journalTab" },
            color = "#7a7468",
        },
        {
            selectors = { "label", "parent:selected" },
            color = "#e4ddd0",
        },
        --the tab's type glyph tracks its label's colour: dim on an inactive
        --tab, parchment on the active one.
        {
            selectors = { "tabTypeIcon", "parent:journalTab" },
            bgcolor = "#7a7468",
        },
        {
            selectors = { "tabTypeIcon", "parent:selected" },
            bgcolor = "#e4ddd0",
        },
        --the tab close x: quiet dim glyph with no chip box; the fail-red
        --treatment appears only on hover, per the design.
        {
            selectors = { "multiselectChipRemove", "parent:journalTab" },
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            border = 0,
        },
        {
            selectors = { "multiselectChipRemove", "hover", "parent:journalTab" },
            bgcolor = "#c940401f",
        },
        {
            selectors = { "label", "multiselectChipRemove" },
            color = "#4a4640",
        },
        {
            selectors = { "label", "multiselectChipRemove", "parent:hover" },
            color = "#c94040",
        },
    }

    --Chrome-style + after the last tab: opens the journal-tree popup (the
    --same tree the breadcrumb shows) headed by a "New Document" entry that
    --unfolds the document types. Picking a document opens it in a new tab;
    --picking a type creates the document immediately (no create dialog -
    --it opens in edit mode ready to be named) with the same ownership
    --rules as the journal panel's + button.
    local newTabButton = gui.Label {
        classes = {"panel", "tab", "journalTab"},
        text = "+",
        fontSize = 18,
        color = "#7a7468",
        textAlignment = "center",
        width = TAB_HEIGHT,
        height = TAB_HEIGHT,
        halign = "left",
        valign = "bottom",
        press = function(element)
            if element.popup ~= nil then
                element.popup = nil
                return
            end

            --highlight the active tab's document in the tree.
            local currentDocId = nil
            local v = element:FindParentWithClass("journalTabbedViewer")
            if v ~= nil and v.data ~= nil then
                for _, tab in ipairs(v.data.tabs or {}) do
                    if tab.tabId == v.data.activeTabId then
                        currentDocId = tab.docId
                        break
                    end
                end
            end

            element.popupPositioning = "panel"
            element.popup = buildJournalTree(currentDocId, nil, {
                onPick = function(docId)
                    element.popup = nil
                    local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[docId]
                    if doc ~= nil then
                        doc:ShowDocument()
                    end
                end,
                onNewDocument = function(typeInfo)
                    element.popup = nil
                    local doc = typeInfo.create()
                    doc.id = dmhub.GenerateGuid()
                    if not dmhub.isDM then
                        doc.ownerid = dmhub.loginUserid
                        doc.parentFolder = dmhub.loginUserid
                    else
                        doc.parentFolder = "private"
                    end
                    doc:Upload()
                    doc:ShowDocument{edit = true}
                end,
            })
        end,
        linger = function(element)
            gui.Tooltip("Open or create a document")(element)
        end,
    }

    --Sidebar toggle at the left end of the tab strip: pins/unpins the
    --journal tree rail. The rail and content column are constructed after
    --the tab bar, so they are forward-declared and captured as upvalues.
    local treeRail
    local contentArea

    --sidebar glyph, the same the dock/rail toggles use, so "show the side
    --tree" reads consistently everywhere. bgcolor carries the lit/dim state.
    local treeToggleIcon = gui.Panel {
        bgimage = "phosphor/sidebar-simple.png",
        bgcolor = cond(g_journalTreeRailSetting:Get(), "#e4ddd0", "#7a7468"),
        width = 16,
        height = 16,
        halign = "center",
        valign = "center",
    }

    local treeToggleButton = gui.Panel {
        classes = {"panel", "tab", "journalTab"},
        width = TAB_HEIGHT,
        height = TAB_HEIGHT,
        halign = "left",
        valign = "bottom",
        press = function(element)
            --if the window is shaded, unshade it first: pinning the rail
            --into a rolled-up window would show a squeezed sliver of tree.
            local v = element:FindParentWithClass("journalTabbedViewer")
            if v ~= nil and v.data.shaded then
                v:FireEvent("toggleShade")
            end
            local open = not g_journalTreeRailSetting:Get()
            g_journalTreeRailSetting:Set(open)
            treeRail:SetClass("collapsed", not open)
            contentArea.selfStyle.width = cond(open, string.format("100%%-%d", TREE_RAIL_WIDTH), "100%")
            treeToggleIcon.selfStyle.bgcolor = cond(open, "#e4ddd0", "#7a7468")
            if open then
                treeRail:FireEvent("refreshTree")
            end
        end,
        linger = function(element)
            if g_journalTreeRailSetting:Get() then
                gui.Tooltip("Hide journal tree")(element)
            else
                gui.Tooltip("Show journal tree")(element)
            end
        end,
        treeToggleIcon,
    }

    local tabBar = gui.Panel {
        classes = {"tabContainer"},
        height = "auto",
        width = "100%",
        flow = "horizontal",
        bgimage = "panels/square.png",
        bgcolor = "#0a0a0b",
        styles = ThemeEngine.MergeTokens(dsTabStyles),
        --window-shade: double-clicking the empty strip area rolls the window
        --up to just the tab strip (and back).
        doubleclick = function(element)
            local v = element:FindParentWithClass("journalTabbedViewer")
            if v ~= nil then
                v:FireEvent("toggleShade")
            end
        end,
        treeToggleButton,
        tabButtonsPanel,
        newTabButton,
        tabArrowsPanel,
    }

    refreshTabVisibility = function(element)
        local tabs = element.data.tabs
        local offset = element.data.scrollOffset

        -- Active tab index and paging-arrow enable state (independent of measurement).
        local activeIdx = 0
        for i, tab in ipairs(tabs) do
            if tab.tabId == element.data.activeTabId then
                activeIdx = i
                break
            end
        end
        tabScrollLeft:SetClass("disabled", activeIdx <= 1)
        tabScrollLeft.interactable = activeIdx > 1
        tabScrollRight:SetClass("disabled", activeIdx >= #tabs or #tabs <= 1)
        tabScrollRight.interactable = (#tabs > 1 and activeIdx < #tabs)

        -- Available width for the tab strip = bar width minus the arrow/close cluster.
        -- tabButtonsPanel is auto-width, so its renderedWidth is the content (sum of
        -- tabs), not the container; measure the full bar and subtract the arrows.
        -- Before the first layout pass every panel reports a placeholder width, so
        -- defer until we have a real measurement (the viewer's think re-runs this).
        local barWidth = tabBar.renderedWidth or 0
        local arrowsWidth = tabArrowsPanel.renderedWidth or 0
        local panelWidth = barWidth - arrowsWidth - 12
        if panelWidth < 200 then
            for _, tab in ipairs(tabs) do
                tab.tabButton:SetClass("collapsed", false)
            end
            element.data.visibleCount = #tabs
            return
        end

        -- Per-tab width, caching the last real measurement so collapsed tabs (which
        -- report ~0 since they take no space) don't distort the fit calculation.
        local function tabWidth(tab)
            local w = tab.tabButton.renderedWidth
            if w and w > 1 then
                tab.lastWidth = w
                return w
            end
            return tab.lastWidth or TAB_MAX_WIDTH
        end

        -- Compute how many tabs fit starting from a given offset
        local function countVisible(fromOffset)
            local count = 0
            local used = 0
            for i = fromOffset + 1, #tabs do
                local w = tabWidth(tabs[i])
                if used + w > panelWidth and count > 0 then
                    break
                end
                used = used + w
                count = count + 1
            end
            return math.max(count, 1)
        end

        local visibleCount = countVisible(offset)

        -- Ensure active tab and its neighbors are within the visible window
        if activeIdx > 0 then
            local needFirst = activeIdx > 1 and activeIdx - 1 or activeIdx
            local needLast = activeIdx < #tabs and activeIdx + 1 or activeIdx
            if needFirst - 1 < offset then
                offset = needFirst - 1
                visibleCount = countVisible(offset)
            elseif needLast > offset + visibleCount then
                offset = needLast - visibleCount
                visibleCount = countVisible(offset)
            end
        end

        -- Clamp offset
        local maxOffset = math.max(0, #tabs - visibleCount)
        if offset > maxOffset then
            offset = maxOffset
            visibleCount = countVisible(offset)
        end
        element.data.scrollOffset = offset

        -- Set visibility
        for i, tab in ipairs(tabs) do
            tab.tabButton:SetClass("collapsed", i - 1 < offset or i - 1 >= offset + visibleCount)
        end

        element.data.visibleCount = visibleCount
    end

    contentArea = gui.Panel {
        classes = {"journalTabContent"},
        --engine gotcha: percent-available WIDTH resolves to ~0 in a
        --horizontal row, so the content column gets an explicit width that
        --the rail toggle swaps between full and full-minus-rail.
        width = cond(g_journalTreeRailSetting:Get(), string.format("100%%-%d", TREE_RAIL_WIDTH), "100%"),
        height = "100%",
        halign = "left",
        valign = "top",
    }

    --The journal tree rail: the same tree the breadcrumb and the tab bar's
    --+ button pop up transiently, pinned as a persistent sidebar. Rebuilt on
    --navigation (piggybacks the viewer's refreshNavButtons broadcast) and on
    --document/folder changes; visibility is a per-user preference.
    --NOT vscroll: the framed journal panel brings its own scroll region, and
    --nesting one inside another makes the engine mis-measure and cull the
    --content to a blank background.
    local treeRailScroll = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",
    }

    treeRail = gui.Panel {
        classes = {"journalTreeRail", cond(not g_journalTreeRailSetting:Get(), "collapsed")},
        width = TREE_RAIL_WIDTH,
        height = "100%",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#0a0a0b",
        hpad = 6,
        vpad = 6,
        borderBox = true,
        data = {
            treeDirty = true,
            builtForDocId = "",
        },
        monitorAssets = { "documents", "objecttables" },

        refreshAssets = function(element)
            element.data.treeDirty = true
            element:FireEvent("refreshTree")
        end,

        --fired tree-wide by the viewer after every tab switch and every
        --back/forward/link navigation -- exactly when the highlight moves.
        refreshNavButtons = function(element)
            element:FireEvent("refreshTree")
        end,

        refreshTree = function(element)
            if element:HasClass("collapsed") then
                return
            end
            local currentDocId = ""
            local v = element:FindParentWithClass("journalTabbedViewer")
            if v ~= nil and v.data ~= nil then
                for _, tab in ipairs(v.data.tabs or {}) do
                    if tab.tabId == v.data.activeTabId then
                        currentDocId = tab.docId or ""
                        break
                    end
                end
            end
            --FRAME the real journal panel rather than building a second
            --tree: the rail used to call buildJournalTree, so anything
            --added to the journal panel (the Characters section, per-type
            --icons, the row menu, drag-to-rail) was missing here. Built
            --ONCE -- the panel keeps itself current off its own asset
            --monitors, so there is nothing to rebuild on navigation.
            if not element.data.treeDirty then
                return
            end
            element.data.treeDirty = false
            element.data.builtForDocId = currentDocId

            if rawget(_G, "JournalCreatePanel") == nil then
                return
            end

            local tree = JournalCreatePanel{
                embedded = true,
                onPick = function(docId)
                    local viewerPanel = element:FindParentWithClass("journalTabbedViewer")
                    if viewerPanel == nil then
                        return
                    end
                    local activeDocId = nil
                    for _, tab in ipairs(viewerPanel.data.tabs or {}) do
                        if tab.tabId == viewerPanel.data.activeTabId then
                            activeDocId = tab.docId
                            break
                        end
                    end
                    if docId == activeDocId then
                        return
                    end
                    viewerPanel:FireEvent("navigateToDocument", docId)
                end,
            }
            treeRailScroll.children = { tree }
        end,

        --window-shade: hide the rail while shaded; on unshade, restore the
        --user's pin preference (and rebuild, since refreshTree bails while
        --collapsed).
        journalShade = function(element, shaded)
            if shaded then
                element:SetClass("collapsed", true)
            else
                local open = g_journalTreeRailSetting:Get()
                element:SetClass("collapsed", not open)
                if open then
                    element:FireEvent("refreshTree")
                end
            end
        end,

        treeRailScroll,

        --hairline separating the rail from the document content.
        gui.Panel{
            floating = true,
            halign = "right",
            valign = "top",
            width = 1,
            height = "100%",
            bgimage = "panels/square.png",
            bgcolor = "#ffffff26",
        },
    }

    local bodyRow = gui.Panel {
        width = "100%",
        height = "100% available",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        treeRail,
        contentArea,
    }

    local innerPanel = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",
        tabBar,
        --hairline under the tab strip, per the design's Bar 0.
        gui.Panel{
            width = "100%",
            height = 1,
            bgimage = "panels/square.png",
            bgcolor = "#ffffff26",
        },
        bodyRow,
    }

    local viewer

    local function findActiveTab(element)
        for _, tab in ipairs(element.data.tabs) do
            if tab.tabId == element.data.activeTabId then
                return tab
            end
        end
        return nil
    end

    local function syncNavState(element)
        local tab = findActiveTab(element)
        if tab then
            element.data.history = tab.history
            element.data.forwardHistory = tab.forwardHistory
        else
            element.data.history = {}
            element.data.forwardHistory = {}
        end
    end

    --Instant shell: instead of building a document's interface synchronously
    --inside the click frame (hundreds of ms for a big page), the tab gets a
    --lightweight placeholder immediately -- so the window, tab strip, and
    --chrome paint this frame -- and the real interface is built on the next
    --scheduled tick. The placeholder stands in as tabData.contentPanel until
    --the build lands; the build only attaches if the tab still owns that
    --exact placeholder, so closing or navigating the tab while pending
    --abandons the stale build.
    --
    --resolveDoc is called at build time so the freshest table copy renders
    --(mirroring the old realize-time lookup semantics).
    local function beginDeferredTabContent(tabData, resolveDoc, buildArgs)
        local placeholder = gui.Panel{
            width = "100%",
            height = "100%",

            --closing while the real interface is still pending: nothing can
            --be unsaved yet, so route the close events (normally handled by
            --the built interface's close button) straight through.
            closetab = function(element)
                tabData.close()
            end,
            closedocuments = function(element)
                tabData.close()
            end,

            gui.LoadingIndicator{},
        }
        tabData.contentPanel = placeholder
        contentArea:AddChild(placeholder)

        dmhub.Schedule(0.01, function()
            if mod.unloaded then return end
            --abandon if the tab was closed or navigated away while pending.
            if not placeholder.valid or tabData.contentPanel ~= placeholder then
                return
            end
            local doc = resolveDoc()
            if doc == nil then return end

            local contentPanel = doc:CreateInterface(buildArgs)
            contentPanel:SetClass("collapsed", placeholder:HasClass("collapsed"))
            tabData.contentPanel = contentPanel
            contentArea:AddChild(contentPanel)
            placeholder:DestroySelf()

            if viewer ~= nil and viewer.valid then
                --a panel built while the window is shaded starts hidden.
                if viewer.data.shaded then
                    contentPanel:FireEventTree("journalShade", true)
                end
                --nav buttons and other chrome synced against the placeholder;
                --refresh them now the real interface's handlers exist.
                viewer:FireEventTree("refreshNavButtons")
            end
        end)
    end

    local function replaceTabContent(activeTab, newDoc, navArgs)
        activeTab.contentPanel:DestroySelf()
        beginDeferredTabContent(activeTab, function() return newDoc end, navArgs)
    end

    -- Build a tab's content panel on demand. No-op if already realized (or
    -- pending: the placeholder counts as realized). tabData.tabArgs is the
    -- full args table captured at addTab time (dialog, close, bubbleIcon,
    -- etc), so the lazily-built panel is identical to the one addTab used to
    -- build eagerly. switchToTab calls this on activation so opening the
    -- journal only builds the tab the user actually lands on.
    local function realizeTab(tabData)
        if tabData.contentPanel ~= nil then return end
        local docs = dmhub.GetTable(CustomDocument.tableName) or {}
        -- Prefer the most up-to-date table copy, but fall back to the in-memory
        -- doc captured at addTab time. Transient docs (e.g. an item/spell link
        -- wrapped via MarkdownRender.RenderToMarkdown) are never written to the
        -- table, so a table-only lookup would render a blank tab for them.
        local doc = docs[tabData.docId] or tabData.doc
        if doc == nil then return end

        beginDeferredTabContent(tabData, function()
            local t = dmhub.GetTable(CustomDocument.tableName) or {}
            return t[tabData.docId] or tabData.doc
        end, tabData.tabArgs)
        --switchToTab's collapse pass runs right after this and un-collapses
        --the active tab's placeholder; the built panel copies that state.
        tabData.contentPanel:SetClass("collapsed", true)
    end

    -- local viewerStyles = ThemeEngine.GetStyles()
    -- viewerStyles[#viewerStyles + 1] = gui.Style {
    --     classes = {"framedPanel"},
    --     priority = 5,
    --     opacity = 0.98,
    --     borderWidth = 0,
    --     borderColor = "clear",
    -- }
    -- viewerStyles[#viewerStyles + 1] = gui.Style {
    --     classes = {"framedPanel", "~uiblur"},
    --     priority = 5,
    --     opacity = 1,
    -- }
    -- for _, s in ipairs(BuildJournalTabStyles()) do
    --     viewerStyles[#viewerStyles + 1] = s
    -- end

    local resizePanel = gui.DialogResizePanel({}, dialogWidth, dialogHeight)

    --window-shade support: set the viewer height and keep the floating
    --resize handles in sync. The handles are positioned by absolute x/y and
    --only follow size changes via "resize" delta events, so a programmatic
    --height change must broadcast the same delta a drag would.
    local function SetViewerHeight(element, newHeight)
        local old = element.selfStyle.height
        if type(old) ~= "number" then
            old = element.renderedHeight
        end
        element.selfStyle.height = newHeight
        if type(old) == "number" and math.abs(newHeight - old) > 0.5 then
            resizePanel:FireEventTree("resize", nil, {deltay = newHeight - old})
        end
    end

    -- Outer Journal Panel
    viewer = gui.Panel {
        styles = ThemeEngine.GetStyles(), --viewerStyles,
        classes = {"framedPanel", "journalViewer", "journalTabbedViewer"},
        border = 0,
        -- bgimage = true,
        blurBackground = true,
        x = loc.x,
        y = loc.y,
        width = loc.width,
        height = loc.height,
        halign = "left",
        valign = "top",
        draggable = true,
        drag = function(element)
            element.x = element.xdrag
            element.y = element.ydrag
            element:SetAsLastSibling()
        end,
        click = function(element)
            element:SetAsLastSibling()
        end,

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            if element.data.activeTabId then
                element:FireEvent("closeTab", element.data.activeTabId)
            end
        end,

        -- Re-run tab visibility once layout has produced real widths (the synchronous
        -- add/switch calls run before the first layout pass, when every panel reports a
        -- placeholder width), and again whenever the bar/arrows resize or the tab count
        -- changes. The signature guard keeps this from doing work on idle frames.
        thinkTime = 0.1,
        think = function(element)
            local bw = math.floor(tabBar.renderedWidth or 0)
            local aw = math.floor(tabArrowsPanel.renderedWidth or 0)
            local sig = bw .. ":" .. aw .. ":" .. #element.data.tabs
            if sig ~= element.data.visSig and (bw - aw) > 200 then
                element.data.visSig = sig
                refreshTabVisibility(element)
            end

            --while shaded, keep the window height hugging the top bar (its
            --height settles a layout pass after a tab is first realized, and
            --changes on tab switch / breadcrumb navigation).
            if element.data.shaded then
                element:FireEvent("updateShadeHeight")
            end
        end,

        data = {
            tabs = {},
            activeTabId = nil,
            nextTabId = 1,
            scrollOffset = 0,
            history = {},
            forwardHistory = {},
            shaded = false,
        },

        --window-shade: roll the window up so only the tab strip remains,
        --or roll it back down. Toggled by double-clicking the tab strip.
        toggleShade = function(element)
            --the engine can deliver a double-click to several overlapping
            --panels (a tab and the strip under it), each of which fires this
            --event; debounce so multi-delivery nets a single toggle.
            local now = dmhub.Time()
            if element.data.lastShadeToggle ~= nil and now - element.data.lastShadeToggle < 0.25 then
                return
            end
            element.data.lastShadeToggle = now

            local shaded = not element.data.shaded
            element.data.shaded = shaded
            if shaded then
                local cur = element.selfStyle.height
                if type(cur) ~= "number" then
                    cur = element.renderedHeight or loc.height
                end
                element.data.unshadedHeight = cur
                element:FireEventTree("journalShade", true)
                element:FireEvent("updateShadeHeight")
            else
                element:FireEventTree("journalShade", false)
                SetViewerHeight(element, element.data.unshadedHeight or loc.height)
            end
        end,

        updateShadeHeight = function(element)
            if not element.data.shaded then
                return
            end
            local h = tabBar.renderedHeight or 0
            if h < TAB_BAR_HEIGHT then
                h = TAB_BAR_HEIGHT
            end
            h = h + 1  --the hairline under the tab strip
            local cur = element.selfStyle.height
            if type(cur) == "number" and math.abs(cur - h) < 0.5 then
                return
            end
            SetViewerHeight(element, h)
        end,

        addTab = function(element, doc, args)
            --opening a document into a shaded window unshades it: the user
            --asked to see content.
            if element.data.shaded then
                element:FireEvent("toggleShade")
            end

            for _, tab in ipairs(element.data.tabs) do
                if tab.docId == doc.id then
                    element:FireEvent("switchToTab", tab.tabId)
                    return
                end
            end

            local tabArgs = DeepCopy(args) or {}
            tabArgs.dialog = viewer
            tabArgs.dialogPanel = viewer
            tabArgs.suppressCloseButton = true

            local tabData = {
                tabId = element.data.nextTabId,
                docId = doc.id,
                doc = doc,            -- in-memory fallback for transient docs not in the table
                history = {},
                forwardHistory = {},
                contentPanel = nil,   -- realized lazily on first switchToTab
                tabArgs = tabArgs,    -- captured so realizeTab can build later
            }
            element.data.nextTabId = element.data.nextTabId + 1

            tabArgs.close = function()
                local idx = nil
                for i, t in ipairs(element.data.tabs) do
                    if t.tabId == tabData.tabId then
                        idx = i
                        break
                    end
                end
                if idx == nil then return end

                tabData.tabButton:DestroySelf()
                if tabData.contentPanel ~= nil then  -- may be nil if tab was never viewed
                    tabData.contentPanel:DestroySelf()
                end
                table.remove(element.data.tabs, idx)

                if #element.data.tabs == 0 then
                    viewer:DestroySelf()
                    g_tabbedViewer = nil
                    return
                end

                if element.data.closeAllPending then
                    -- Tearing the whole viewer down: do NOT switch to (and thus
                    -- realize) a tab we're about to destroy. Just cascade to the
                    -- next one. Otherwise close-all would build every tab's full
                    -- interface one by one only to immediately destroy it.
                    if #element.data.tabs > 0 then
                        element:FireEvent("closeAllTabs")
                    end
                elseif element.data.activeTabId == tabData.tabId then
                    local newIndex = math.min(idx, #element.data.tabs)
                    element:FireEvent("switchToTab", element.data.tabs[newIndex].tabId)
                else
                    refreshTabVisibility(element)
                end
            end
            tabData.close = tabArgs.close

            -- Content is NOT built here; realizeTab() builds it on first view.
            -- The tab button is cheap and is needed for the strip regardless.
            local tabButton = CreateTabButton(doc, viewer, tabData.tabId, args and args.bubbleIcon)

            tabData.tabButton = tabButton
            element.data.tabs[#element.data.tabs + 1] = tabData

            tabButtonsPanel:AddChild(tabButton)

            if args and args.skipRefresh then
                -- Batch mode: skip per-tab refresh, caller will trigger final refresh.
                -- Content stays unbuilt until the tab is actually viewed.
            else
                refreshTabVisibility(element)
                element:FireEvent("switchToTab", tabData.tabId)  -- realizes this one
            end
        end,

        switchToTab = function(element, tabId)
            element.data.activeTabId = tabId

            -- Build the target tab's content the first time it is viewed.
            for _, tab in ipairs(element.data.tabs) do
                if tab.tabId == tabId then
                    realizeTab(tab)
                    break
                end
            end

            for _, tab in ipairs(element.data.tabs) do
                if tab.contentPanel ~= nil then  -- skip never-viewed (unrealized) tabs
                    tab.contentPanel:SetClass("collapsed", tab.tabId ~= tabId)
                end
                tab.tabButton:SetClass("selected", tab.tabId == tabId)
            end
            refreshTabVisibility(element)
            syncNavState(element)
            element:FireEventTree("refreshNavButtons")
        end,

        closeTab = function(element, tabId)
            for _, tab in ipairs(element.data.tabs) do
                if tab.tabId == tabId then
                    if tab.contentPanel ~= nil then
                        tab.contentPanel:FireEvent("closetab")
                    else
                        tab.close()  -- unrealized: run the close closure directly
                    end
                    return
                end
            end
        end,

        closeAllTabs = function(element)
            element.data.closeAllPending = true
            -- Close the first tab and let its close closure cascade. We target a
            -- live tab (tabs[1]) rather than activeTabId because the close path no
            -- longer switches activeTabId to a surviving tab during teardown.
            local tabs = element.data.tabs
            if #tabs > 0 then
                element:FireEvent("closeTab", tabs[1].tabId)
            end
        end,

        navigateToDocument = function(element, docId)
            local activeTab = findActiveTab(element)
            if activeTab == nil then return end

            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local newDoc = docs[docId]
            if newDoc == nil then return end

            activeTab.history[#activeTab.history + 1] = activeTab.docId
            activeTab.forwardHistory = {}
            activeTab.docId = docId
            activeTab.tabButton.data.docId = docId

            local navArgs = {
                dialog = viewer,
                dialogPanel = viewer,
                suppressCloseButton = true,
                close = activeTab.close,
            }
            replaceTabContent(activeTab, newDoc, navArgs)

            tabButtonsPanel:FireEventTree("refreshTabTitle", docId, newDoc.description or "Untitled")

            syncNavState(element)
            element:FireEventTree("refreshNavButtons")
        end,

        navigateBack = function(element)
            local activeTab = findActiveTab(element)
            if activeTab == nil or #activeTab.history == 0 then return end

            local prevDocId = activeTab.history[#activeTab.history]
            activeTab.history[#activeTab.history] = nil

            activeTab.forwardHistory[#activeTab.forwardHistory + 1] = activeTab.docId
            activeTab.docId = prevDocId
            activeTab.tabButton.data.docId = prevDocId

            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local prevDoc = docs[prevDocId]
            if prevDoc == nil then return end

            local navArgs = {
                dialog = viewer,
                dialogPanel = viewer,
                suppressCloseButton = true,
                close = activeTab.close,
            }
            replaceTabContent(activeTab, prevDoc, navArgs)

            tabButtonsPanel:FireEventTree("refreshTabTitle", prevDocId, prevDoc.description or "Untitled")

            syncNavState(element)
            element:FireEventTree("refreshNavButtons")
        end,

        navigateForward = function(element)
            local activeTab = findActiveTab(element)
            if activeTab == nil or #activeTab.forwardHistory == 0 then return end

            local nextDocId = activeTab.forwardHistory[#activeTab.forwardHistory]
            activeTab.forwardHistory[#activeTab.forwardHistory] = nil

            activeTab.history[#activeTab.history + 1] = activeTab.docId
            activeTab.docId = nextDocId
            activeTab.tabButton.data.docId = nextDocId

            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local nextDoc = docs[nextDocId]
            if nextDoc == nil then return end

            local navArgs = {
                dialog = viewer,
                dialogPanel = viewer,
                suppressCloseButton = true,
                close = activeTab.close,
            }
            replaceTabContent(activeTab, nextDoc, navArgs)

            tabButtonsPanel:FireEventTree("refreshTabTitle", nextDocId, nextDoc.description or "Untitled")

            syncNavState(element)
            element:FireEventTree("refreshNavButtons")
        end,

        resizePanel,

        innerPanel,
    }

    g_tabbedViewer = viewer

    ThemeEngine.OnThemeChanged(mod, function()
        if g_tabbedViewer ~= nil and g_tabbedViewer.valid then
            g_tabbedViewer.styles = ThemeEngine.GetStyles()
        end
    end)

    return viewer
end

--args may carry placement overrides for the window:
--  width/height: initial size (defaults to the full document dialog size;
--      a location remembered from a drag/resize this session still wins).
--  x/y: explicit position. Beats both the default centering and the
--      remembered location -- callers anchoring a window to a fixed spot
--      (e.g. beside a rail icon) always get the spot they asked for.
--The args table is also forwarded to CreateInterface, so interface args
--(close, bubbleIcon, ...) ride along unchanged.
function CustomDocument:PresentDocument(args)
    args = args or {}

    local dialogWidth = args.width or 1100
    local dialogHeight = args.height or 940

    local loc = {
        x = 1920 * 0.5 * ((dmhub.screenDimensionsBelowTitlebar.x / dmhub.screenDimensionsBelowTitlebar.y) / (1920 / 1080)) - dialogWidth / 2,
        y = 1080 * 0.5 - dialogHeight / 2,
        width = dialogWidth,
        height = dialogHeight,
    }
    if self:has_key("_tmp_location") and self._tmp_location.screenx == dmhub.screenDimensionsBelowTitlebar.x and self._tmp_location.screeny == dmhub.screenDimensionsBelowTitlebar.y then
        loc.x = self._tmp_location.x or loc.x
        loc.y = self._tmp_location.y or loc.y
        loc.width = self._tmp_location.width or loc.width
        loc.height = self._tmp_location.height or loc.height
    end

    if args.x ~= nil then
        loc.x = args.x
    end
    if args.y ~= nil then
        loc.y = args.y
    end

    dialogWidth = loc.width
    dialogHeight = loc.height

    local dialog

    local dialogStyles = ThemeEngine.GetStyles()
    dialogStyles[#dialogStyles + 1] = gui.Style {
        classes = { "framedPanel" },
        priority = 5,
        opacity = 0.98,
        borderWidth = 0,
        borderColor = "clear",
    }
    dialogStyles[#dialogStyles + 1] = gui.Style {
        classes = { "framedPanel", "~uiblur" },
        priority = 5,
        opacity = 1,
    }

    dialog = gui.Panel {
        styles = dialogStyles,
        classes = { "framedPanel", "journalViewer" },
        bgimage = true,
        blurBackground = true,
        x = loc.x,
        y = loc.y,
        width = loc.width,
        height = loc.height,
        halign = "left",
        valign = "top",
        --presses anywhere in the window stay in the window: without this
        --a right-click inside (e.g. a journal row's context menu) also
        --reaches the map, whose menu replaces ours. Self-dragging is
        --unaffected -- swallowPress only stops PARENT propagation.
        swallowPress = true,
        draggable = true,
        drag = function(element)
            element.x = element.xdrag
            element.y = element.ydrag
            element:SetAsLastSibling()

            self._tmp_location = {
                x = dialog.x,
                y = dialog.y,
                width = dialog.selfStyle.width,
                height = dialog.selfStyle.height,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y
            }

            --callers that care where the window lands (e.g. the icon rail
            --pinning a dragged panel window) can observe the move.
            if args.onMoved ~= nil then
                args.onMoved(element)
            end
        end,
        click = function(element)
            element:SetAsLastSibling()
        end,

        data = {
            history = {},
            forwardHistory = {},
            currentDocId = self.id,
        },

        navigateToDocument = function(element, docId)
            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local newDoc = docs[docId]
            if newDoc == nil then return end

            -- Push current onto history, clear forward
            element.data.history[#element.data.history + 1] = element.data.currentDocId
            element.data.forwardHistory = {}
            element.data.currentDocId = docId

            -- Replace the content panel (child index 2, after resize panel)
            if element.children[2] then
                element.children[2]:DestroySelf()
            end
            local navArgs = DeepCopy(args) or {}
            navArgs.dialog = dialog
            navArgs.dialogPanel = dialog
            local newPanel = newDoc:CreateInterface(navArgs)
            dialog:AddChild(newPanel)

            dialog:FireEventTree("refreshNavButtons")
        end,

        navigateBack = function(element)
            local history = element.data.history
            if #history == 0 then return end

            local prevDocId = history[#history]
            history[#history] = nil

            element.data.forwardHistory[#element.data.forwardHistory + 1] = element.data.currentDocId
            element.data.currentDocId = prevDocId

            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local prevDoc = docs[prevDocId]
            if prevDoc == nil then return end

            if element.children[2] then
                element.children[2]:DestroySelf()
            end
            local navArgs = DeepCopy(args) or {}
            navArgs.dialog = dialog
            navArgs.dialogPanel = dialog
            local newPanel = prevDoc:CreateInterface(navArgs)
            dialog:AddChild(newPanel)

            dialog:FireEventTree("refreshNavButtons")
        end,

        navigateForward = function(element)
            local forwardHistory = element.data.forwardHistory
            if #forwardHistory == 0 then return end

            local nextDocId = forwardHistory[#forwardHistory]
            forwardHistory[#forwardHistory] = nil

            element.data.history[#element.data.history + 1] = element.data.currentDocId
            element.data.currentDocId = nextDocId

            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local nextDoc = docs[nextDocId]
            if nextDoc == nil then return end

            if element.children[2] then
                element.children[2]:DestroySelf()
            end
            local navArgs = DeepCopy(args) or {}
            navArgs.dialog = dialog
            navArgs.dialogPanel = dialog
            local newPanel = nextDoc:CreateInterface(navArgs)
            dialog:AddChild(newPanel)

            dialog:FireEventTree("refreshNavButtons")
        end,

        gui.DialogResizePanel(self, dialogWidth, dialogHeight),

    }

    args.dialog = dialog
    args.dialogPanel = dialog
    local mainPanel = self:CreateInterface(args)
    dialog:AddChild(mainPanel)

    return dialog
end

function CustomDocument:ShowDocument(args)
    self = (dmhub.GetTable(self.tableName) or {})[self.id] or self --get the most up-to-date version.
    args = args or {}

    local viewer = CustomDocument.GetOrCreateTabbedViewer()

    if viewer.parent == nil then
        GameHud.instance.documentsPanel:AddChild(viewer)
    end

    viewer:FireEvent("addTab", self, args)
end

function CustomDocument:MatchesSearch(search)
    return false
end

GameHud.RegisterPresentableDialog {
    id = "document",
    create = function(args)
        local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[args.docid]
        if doc ~= nil then
            doc:ShowDocument()
        end
        return nil
    end,
    keeplocal = true,
}

----------------------------------------------------------------------
-- PanelDocument
-- -------------
-- A transient document wrapping a registered dockable panel, so panel
-- content can be hosted on document-system surfaces: standalone
-- PresentDocument windows now (the icon-rail prototype), viewer tabs
-- and journal links later for free via CreateInterface.
--
-- Instances are NEVER uploaded to the documents table. They are cached
-- per session (one per panel) so a panel window's remembered location
-- (_tmp_location, maintained by PresentDocument's drag handler)
-- survives close and reopen within the session.
----------------------------------------------------------------------

RegisterGameType("PanelDocument", "CustomDocument")
PanelDocument.nodeType = "panel"
PanelDocument.docType = "note"
PanelDocument.panelName = ""

--Default window size: the dock content width plus chrome, and a height
--in the ballpark of the design's compact rail windows.
PanelDocument.DefaultWidth = 380
PanelDocument.DefaultHeight = 520

--Declared here rather than beside its other uses further down: PresentPanel
--needs it, and a local is not in lexical scope for code written above it.
local g_panelDocumentHeaderHeight = 32

--Clamp a window height to the panel's DECLARED bounds. Dockable panels
--register minHeight/maxHeight (DockablePanel.lua, defaulting 40/1080) and
--several are FIXED -- Dice declares min == max == 160, Audio 470 -- so
--rendering every rail window at the generic DefaultHeight left Dice in a box
--three times taller than its content. The registration's bounds describe the
--CONTENT, so the window adds its own header on top, the same way the dock
--adds its 40px tab strip when it computes container metrics.
--Applied to explicit heights too, not just the default: a restored pin must
--not violate the panel's bounds either.
function PanelDocument.ClampHeight(panelName, height)
    if panelName == nil or type(height) ~= "number" then
        return height
    end
    local reg = DockablePanel.GetRegistration(panelName)
    if reg == nil then
        return height
    end
    local content = height - g_panelDocumentHeaderHeight
    local minH, maxH = nil, nil
    pcall(function() minH = reg.minHeight end)
    pcall(function() maxH = reg.maxHeight end)
    if type(minH) == "number" and content < minH then
        content = minH
    end
    if type(maxH) == "number" and content > maxH then
        content = maxH
    end
    return content + g_panelDocumentHeaderHeight
end

local g_panelDocuments = {}

--Get (or create) the session-cached PanelDocument for a registered
--dockable panel name. Returns nil when no such panel is registered or
--it is not available to this user (dmonly/devonly).
function PanelDocument.Get(panelName)
    local reg = DockablePanel.GetRegistration(panelName)
    if reg == nil then
        return nil
    end
    if reg.dmonly and not dmhub.isDM then
        return nil
    end
    if reg.devonly and not devmode() then
        return nil
    end

    local key = string.lower(reg.name)
    local doc = g_panelDocuments[key]
    if doc == nil then
        doc = PanelDocument.new{
            id = "panel:" .. key,
            description = reg.name,
            panelName = reg.name,
        }
        g_panelDocuments[key] = doc
    end
    return doc
end

--Open this panel's standalone window, or raise the existing one.
--Placement args (x, y, width, height) pass through to PresentDocument.
--Returns the window panel.
function PanelDocument:PresentPanel(args)
    args = args or {}

    local existing = self:try_get("_tmp_dialog")
    if existing ~= nil and existing.valid then
        existing:SetAsLastSibling()
        return existing
    end

    args.width = args.width or PanelDocument.DefaultWidth
    args.height = PanelDocument.ClampHeight(
        self:try_get("panelName"),
        args.height or PanelDocument.DefaultHeight)

    local dialog = self:PresentDocument(args)
    self._tmp_dialog = dialog
    GameHud.instance.documentsPanel:AddChild(dialog)
    return dialog
end

--Close this panel's standalone window if it is open.
function PanelDocument:ClosePanel()
    local existing = self:try_get("_tmp_dialog")
    if existing ~= nil and existing.valid then
        existing:DestroySelf()
    end
    self._tmp_dialog = nil
end

function PanelDocument:PresentDocumentOpen()
    local existing = self:try_get("_tmp_dialog")
    return existing ~= nil and existing.valid
end

--Panel documents never open in the tabbed journal viewer implicitly;
--the rail flow presents standalone windows.
function PanelDocument:ShowDocument(args)
    self:PresentPanel(args)
end

----------------------------------------------------------------------
-- CharacterPanelDocument
-- ----------------------
-- A panel document showing ONE character's panel: the same summary and
-- details stack the sidebar Character panel builds, but bound to a
-- chosen character instead of following map selection. Journal surfaces
-- (the tree's Characters section, party islands) open these, so a
-- character's panel is FRAMED rather than reimplemented -- improvements
-- to the sidebar panel appear here with no extra maintenance.
--
-- The panel content is not a registered dockable panel, so this subtype
-- supplies a synthetic registration instead of looking one up.
----------------------------------------------------------------------

RegisterGameType("CharacterPanelDocument", "PanelDocument")
CharacterPanelDocument.charid = ""
CharacterPanelDocument.DefaultWidth = 400
CharacterPanelDocument.DefaultHeight = 640

--Get (or create) the session-cached document for a character. Returns
--nil when there is no such character. Shares g_panelDocuments so the
--"already shown somewhere" checks cover character windows too.
function CharacterPanelDocument.Get(charid)
    if charid == nil or charid == "" then
        return nil
    end
    local token = dmhub.GetCharacterById(charid)
    if token == nil then
        return nil
    end

    local key = "character:" .. charid
    local doc = g_panelDocuments[key]
    if doc == nil then
        doc = CharacterPanelDocument.new{
            id = "panel:" .. key,
            description = token.name or "Character",
            panelName = key,
            charid = charid,
        }
        g_panelDocuments[key] = doc
    else
        --names are editable; keep the window title current.
        doc.description = token.name or doc.description
    end
    return doc
end

function CharacterPanelDocument:GetHostRegistration()
    local charid = self.charid
    local token = dmhub.GetCharacterById(charid)
    local name = "Character"
    if token ~= nil and token.name ~= nil and token.name ~= "" then
        name = token.name
    end

    return {
        name = name,
        --the sidebar Character panel's own icon, so the window reads as
        --that panel rather than as a new kind of thing.
        icon = "icons/standard/Icon_App_Character.png",
        vscroll = true,
        hideObjectsOutOfScroll = false,
        content = function()
            return CharacterPanel.CreatePinnedCharacterPanel(charid)
        end,
    }
end

--Open (or raise) a character's panel window. The global entry point for
--journal surfaces; guarded callers use rawget since this file loads
--after the panels that call it.
function ShowCharacterPanelDocument(charid)
    local doc = CharacterPanelDocument.Get(charid)
    if doc == nil then
        return nil
    end
    return doc:PresentPanel()
end

--"Share to Journal" on a map token's right-click menu: puts that
--character in the journal's Characters section, where clicking it opens
--this panel. The client builds that menu, so we contribute an entry via
--the GameHud hook; the token comes from the cursor, because
--right-clicking a token does not select it.
if rawget(_G, "RegisterGameContextMenuContributor") ~= nil then
    RegisterGameContextMenuContributor("journalcharacter", function(entries)
        if not dmhub.isDM or rawget(_G, "JournalShareCharacter") == nil then
            return
        end
        local token = GameContextMenuTokenUnderCursor()
        if token == nil then
            return
        end
        local charid = token.charid
        if charid == nil then
            return
        end

        if JournalHasCharacter(charid) then
            entries[#entries + 1] = {
                text = "Remove from Journal",
                click = function()
                    JournalUnshareCharacter(charid)
                end,
            }
        else
            entries[#entries + 1] = {
                text = "Share to Journal",
                click = function()
                    JournalShareCharacter(charid)
                end,
            }
        end
    end)
end

--Resolve a rail/layout key to the panel document behind it. Registered
--panels are keyed by their (lowercased) name; characters by the
--"character:<charid>" panelName CharacterPanelDocument uses -- so
--character shortcuts get the rail's open/close, pinning, tab-raising
--and Views machinery without any of it special-casing them.
local function RailPanelDocument(key)
    if key == nil then
        return nil
    end
    local charid = string.match(key, "^character:(.+)$")
    if charid ~= nil then
        return CharacterPanelDocument.Get(charid)
    end
    return PanelDocument.Get(key)
end

--The rail's curated panel list, in display order (from the Player Icon
--Rail design). Used by the rail buttons AND by the panel window's
--add-tab menu. Panels missing a registration, or not available to this
--user (dmonly/devonly), are skipped wherever the list is consumed.
local g_iconRailPanels = {
    "Character",
    "Heroes",
    "Dice",
    "Chat",
    "Action Log",
    "Journal",
    "Campaign Tracker",
    "Downtime Projects",
    "Triggers",
    "Audio",
    "Safety Tools",
}

--Find the open panel window (standalone dialog) that shows the given
--panel key, either as its own panel or as an added tab. nil when the
--panel is not visible anywhere.
function PanelDocument.FindHostDialog(key)
    key = string.lower(key)
    for k, doc in pairs(g_panelDocuments) do
        local d = doc:try_get("_tmp_dialog")
        if d ~= nil and d.valid then
            local tabs = d.data.panelTabs
            if tabs ~= nil then
                for _, t in ipairs(tabs) do
                    if t == key then
                        return d
                    end
                end
            elseif k == key then
                return d
            end
        end
    end
    return nil
end

function PanelDocument.IsPanelShown(key)
    return PanelDocument.FindHostDialog(key) ~= nil
end

--The registration describing this document's own panel content. The
--base type resolves its panelName against the dockable panel registry;
--subtypes (CharacterPanelDocument) return a synthetic registration
--instead, and the interface machinery below treats both the same.
function PanelDocument:GetHostRegistration()
    return DockablePanel.GetRegistration(self.panelName)
end

function PanelDocument:CreateInterface(args)
    args = args or {}

    local hostReg = self:GetHostRegistration()
    if hostReg == nil then
        return gui.Label{
            classes = {"modalMessage"},
            text = string.format("Unknown panel: %s", self.panelName),
            width = "100%",
            height = "auto",
            valign = "center",
        }
    end

    local dialog = args.dialog

    --tab support only applies to the standalone panel window; when hosted
    --inside a foreign dialog (e.g. as a journal viewer tab), render as a
    --plain single panel.
    local tabbed = not args.suppressCloseButton

    --pinned to the top-right so it stays put when the tab strip wraps to
    --extra rows and the header grows.
    local closeButton = gui.Button{
        classes = {"closeButton", "sizeXs"},
        halign = "right",
        valign = "top",
        rmargin = 6,
        tmargin = 8,
        click = function(element)
            if args.close ~= nil then
                args.close()
            elseif dialog ~= nil and dialog.valid then
                dialog:DestroySelf()
            end
        end,
    }
    if args.suppressCloseButton then
        closeButton:SetClass("collapsed", true)
    end

    --===== tab model =====
    --The window can host several panels as tabs (added via right-click on
    --the title bar). Ordered list of {key, reg, chip, wrapper}; content
    --wrappers realize lazily on first activation.
    local m_tabs = {}
    local m_activeKey = nil
    local m_constructing = true
    local tabStrip
    local addTabButton
    local contentArea
    local hairline
    local header

    local m_shaded = false
    local m_savedHeight = nil
    local m_lastShadeToggle = nil

    --The header's real rendered height: it grows when tab chips wrap to
    --extra rows, so anything sized against it must measure, not assume.
    local function HeaderHeight()
        local h = nil
        if header ~= nil and header.valid then
            h = header.renderedHeight
        end
        if type(h) ~= "number" or h < g_panelDocumentHeaderHeight then
            return g_panelDocumentHeaderHeight
        end
        return math.ceil(h)
    end

    --Set the window height and keep the floating resize handles in sync:
    --they only track size changes via "resize" delta events (the same
    --contract as the tabbed viewer's SetViewerHeight). The resize panel
    --is the dialog's first child, built by PresentDocument.
    local function SetWindowHeight(newHeight)
        local old = dialog.selfStyle.height
        if type(old) ~= "number" then
            old = dialog.renderedHeight
        end
        dialog.selfStyle.height = newHeight
        local resizePanel = dialog.children[1]
        if type(old) == "number" and resizePanel ~= nil and resizePanel.valid and math.abs(newHeight - old) > 0.5 then
            resizePanel:FireEventTree("resize", nil, {deltay = newHeight - old})
        end
    end

    --window-shade: double-clicking the header rolls the window up to just
    --the title bar (same gesture as the journal viewer's tab strip) and
    --rolls it back down.
    local function ToggleShade()
        if dialog == nil or not dialog.valid or args.suppressCloseButton then
            return
        end
        --the engine can deliver a double-click to overlapping panels;
        --debounce so multi-delivery nets a single toggle.
        local now = dmhub.Time()
        if m_lastShadeToggle ~= nil and now - m_lastShadeToggle < 0.25 then
            return
        end
        m_lastShadeToggle = now

        m_shaded = not m_shaded
        if contentArea ~= nil and contentArea.valid then
            contentArea:SetClass("collapsed", m_shaded)
        end
        if hairline ~= nil and hairline.valid then
            hairline:SetClass("collapsed", m_shaded)
        end
        if m_shaded then
            local cur = dialog.selfStyle.height
            if type(cur) ~= "number" then
                cur = dialog.renderedHeight
            end
            m_savedHeight = cur
            SetWindowHeight(HeaderHeight() + 2)
        else
            SetWindowHeight(m_savedHeight or 520)
        end
        --a drag while shaded records the rolled-up height into
        --_tmp_location; keep the remembered height the full one so a
        --later reopen is never squashed.
        local loc = self:try_get("_tmp_location")
        if loc ~= nil and m_savedHeight ~= nil then
            loc.height = m_savedHeight
        end
    end

    local function FindTab(key)
        for i, t in ipairs(m_tabs) do
            if t.key == key then
                return t, i
            end
        end
        return nil
    end

    --Mirror the dock host's content contract (CreateDockablePanelInstance):
    --content() inside a vscroll parent unless the registration opts out.
    --Content anchors to the top of the window: the dock sizes its slots
    --to hug content, but our window height is fixed, and a short panel
    --left to the default centering floats in a void.
    local function BuildContentWrapper(reg)
        local content = reg.content()
        content.selfStyle.valign = "top"
        --anchor the hosted content left as well: without an alignment
        --from an ancestor, panel content centers in the window host
        --(never in the dock, which supplies one). This is the correct
        --level for the fix -- forcing halign inside content styles (the
        --old approach) overrides flow positioning row by row and
        --scrambles layouts like the journal tree's folder headers.
        content.selfStyle.halign = "left"
        if reg.vscroll ~= false then
            local hideObjectsOutOfScroll = reg.hideObjectsOutOfScroll
            if hideObjectsOutOfScroll == nil then
                hideObjectsOutOfScroll = true
            end
            return gui.Panel{
                idprefix = "panelDocumentScrollParent",
                width = "100%-4",
                height = "100%",
                pad = 2,
                vscroll = true,
                hideObjectsOutOfScroll = hideObjectsOutOfScroll,
                children = {
                    content,
                },
            }
        end
        return gui.Panel{
            idprefix = "panelDocumentNoScrollParent",
            width = "100%",
            height = "100%",
            children = {
                content,
            },
        }
    end

    --publish the tab list on the dialog (so the rail and other windows
    --can see which panels are visible here) and notify the host.
    local function SyncDialogTabs()
        if not tabbed then
            return
        end
        if dialog ~= nil and dialog.valid then
            local keys = {}
            for _, t in ipairs(m_tabs) do
                keys[#keys + 1] = t.key
            end
            dialog.data.panelTabs = keys
            if args.onTabsChanged ~= nil and not m_constructing then
                args.onTabsChanged(keys)
            end
        end
    end

    local function SwitchTab(key)
        local tab = FindTab(key)
        if tab == nil then
            return
        end
        if tab.wrapper == nil then
            tab.wrapper = BuildContentWrapper(tab.reg)
            tab.wrapper:SetClass("collapsed", true)
            contentArea:AddChild(tab.wrapper)
        end
        m_activeKey = key
        for _, t in ipairs(m_tabs) do
            if t.wrapper ~= nil and t.wrapper.valid then
                t.wrapper:SetClass("collapsed", t.key ~= key)
            end
            if t.chip ~= nil and t.chip.valid then
                t.chip:SetClass("selected", t.key == key)
            end
        end
    end

    local AddTab

    --entries for the add-a-panel menu: curated panels available to this
    --user and not already visible in this or any other window.
    local function BuildAddEntries(parentElement)
        local entries = {}
        for _, name in ipairs(g_iconRailPanels) do
            local k = string.lower(name)
            if FindTab(k) == nil and (not PanelDocument.IsPanelShown(k)) and PanelDocument.Get(name) ~= nil then
                entries[#entries + 1] = {
                    text = name,
                    click = function(element)
                        parentElement.popup = nil
                        AddTab(k)
                    end,
                }
            end
        end
        return entries
    end

    local function ShowAddMenu(element)
        if not tabbed then
            return
        end
        local entries = BuildAddEntries(element)
        if #entries == 0 then
            return
        end
        element.popup = gui.ContextMenu{
            entries = entries,
        }
    end

    --each chip carries its own close x, shown even when it is the only
    --tab (Lisa+David review 2026-07-19: closing the last tab closes the
    --whole window). Hidden only in non-tabbed hosts (e.g. the journal
    --viewer), where the host owns closing.
    local function SyncChipCloseButtons()
        for _, t in ipairs(m_tabs) do
            if t.chipClose ~= nil and t.chipClose.valid then
                t.chipClose:SetClass("collapsed", not tabbed)
            end
        end
    end

    local function RemoveTab(key)
        local tab, idx = FindTab(key)
        if tab == nil then
            return
        end
        --closing the ONLY tab closes the whole window: same path as the
        --header close button (Lisa+David review 2026-07-19).
        if #m_tabs <= 1 then
            if args.close ~= nil then
                args.close()
            elseif dialog ~= nil and dialog.valid then
                dialog:DestroySelf()
            end
            return
        end
        table.remove(m_tabs, idx)
        if tab.chip ~= nil and tab.chip.valid then
            tab.chip:DestroySelf()
        end
        if tab.wrapper ~= nil and tab.wrapper.valid then
            tab.wrapper:DestroySelf()
        end
        if m_activeKey == key then
            SwitchTab(m_tabs[1].key)
        end
        SyncDialogTabs()
        SyncChipCloseButtons()
        --the strip may have dropped a row; re-measure after layout.
        if header ~= nil and header.valid then
            header:ScheduleEvent("syncPanelHeader", 0.05)
        end
    end

    local function BuildChip(tab)
        return gui.Panel{
            classes = {"panelDocumentTab"},
            flow = "horizontal",
            width = "auto",
            height = g_panelDocumentHeaderHeight - 6,
            bgimage = true,
            halign = "left",
            valign = "center",
            hmargin = 1,
            vmargin = 3,

            click = function(element)
                SwitchTab(tab.key)
            end,
            doubleclick = function(element)
                ToggleShade()
            end,
            rightClick = function(element)
                if not tabbed then
                    return
                end
                local entries = BuildAddEntries(element)
                if #m_tabs > 1 then
                    entries[#entries + 1] = {
                        text = string.format("Close Tab: %s", tab.reg.name),
                        click = function(el)
                            element.popup = nil
                            RemoveTab(tab.key)
                        end,
                    }
                end
                if #entries > 0 then
                    element.popup = gui.ContextMenu{
                        entries = entries,
                    }
                end
            end,

            gui.Panel{
                classes = {"panelDocumentHeaderIcon"},
                bgimage = tab.reg.icon or "icons/icon_app/icon_app_107.png",
                width = 16,
                height = 16,
                halign = "left",
                valign = "center",
                lmargin = 8,
            },
            gui.Label{
                classes = {"panelDocumentTitle"},
                text = string.upper(tab.reg.name),
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 6,
                rmargin = 4,
            },
            (function()
                tab.chipClose = gui.Button{
                    classes = {"closeButton", "sizeXxs", "collapsed"},
                    valign = "center",
                    rmargin = 6,
                    click = function(element)
                        RemoveTab(tab.key)
                    end,
                }
                return tab.chipClose
            end)(),
        }
    end

    AddTab = function(key)
        if FindTab(key) ~= nil then
            SwitchTab(key)
            return
        end
        --the window's own panel may be a synthetic registration (e.g. a
        --pinned character); everything else comes from the dock registry.
        local reg
        if key == string.lower(self.panelName) then
            reg = hostReg
        else
            reg = DockablePanel.GetRegistration(key)
        end
        if reg == nil then
            return
        end
        local tab = {
            key = key,
            reg = reg,
        }
        m_tabs[#m_tabs + 1] = tab
        tab.chip = BuildChip(tab)
        tabStrip:AddChild(tab.chip)
        --the + affordance stays after the last chip.
        if addTabButton ~= nil and addTabButton.valid then
            addTabButton:SetAsLastSibling()
        end
        SwitchTab(tab.key)
        SyncDialogTabs()
        SyncChipCloseButtons()
        --the strip may have wrapped to another row; re-measure once the
        --new chip has been through a layout pass.
        if header ~= nil and header.valid then
            header:ScheduleEvent("syncPanelHeader", 0.05)
        end
    end

    --the + at the end of the tab strip: same add-a-panel menu as
    --right-clicking the bar, in the tab chips' visual language
    --(Lisa+David review 2026-07-19). Kept as the strip's last child as
    --chips come and go.
    if tabbed then
        addTabButton = gui.Panel{
            classes = {"panelDocumentTab"},
            flow = "none",
            width = g_panelDocumentHeaderHeight - 6,
            height = g_panelDocumentHeaderHeight - 6,
            bgimage = true,
            halign = "left",
            valign = "center",
            hmargin = 1,
            vmargin = 3,

            click = function(element)
                ShowAddMenu(element)
            end,

            gui.Label{
                classes = {"panelDocumentTitle"},
                text = "+",
                fontSize = 16,
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
    end

    --Tab chips wrap to extra rows when the strip runs out of width (the
    --engine reserves a phantom row when a line fills to within a few
    --pixels, so leave real slack before the close button).
    tabStrip = gui.Panel{
        width = "100%-50",
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "left",
        valign = "center",
        addTabButton,
    }

    header = gui.Panel{
        classes = {"panelDocumentHeader"},
        width = "100%",
        height = "auto",
        minHeight = g_panelDocumentHeaderHeight,
        flow = "horizontal",
        bgimage = true,
        --NO swallowPress here: the press must propagate to the dialog,
        --whose draggable is what makes the window movable by its bar.
        --Map-menu containment lives on the dialog root instead.

        doubleclick = function(element)
            ToggleShade()
        end,
        --right-click on the bar: add another panel to this window as a tab.
        rightClick = function(element)
            ShowAddMenu(element)
        end,

        --keep the content area (and a shaded window's height) tracking the
        --header's real height as chip rows come and go.
        syncPanelHeader = function(element)
            local h = HeaderHeight()
            if contentArea ~= nil and contentArea.valid then
                contentArea.selfStyle.height = string.format("100%%-%d", h + 1)
            end
            if m_shaded then
                SetWindowHeight(h + 2)
            end
        end,

        tabStrip,
        closeButton,
    }

    hairline = gui.Panel{
        classes = {"panelDocumentHairline"},
        width = "100%",
        height = 1,
        bgimage = true,
    }

    contentArea = gui.Panel{
        width = "100%",
        height = string.format("100%%-%d", g_panelDocumentHeaderHeight + 1),
        flow = "none",
    }

    local resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",

        --Dockable panel content is written against the dock contract: it
        --finds its ancestor with class "dock" and asks data.TooltipAlignment()
        --which side tooltips should open on. Satisfy that contract here so
        --panel content runs unmodified inside a document window. No theme
        --rules target the bare "dock" class (only dockFrame/dockablePanel/
        --dockTab/dockHandle), so the class is style-inert on this root.
        classes = {"dock"},
        data = {
            floating = true,
            TooltipAlignment = function()
                --tooltips open away from whichever half of the screen the
                --window sits on. Measure the parent layer's width; the
                --aspect formula over-estimates it (see IconRailUIWidth).
                local d = args.dialog
                if d ~= nil and d.valid then
                    local uiWidth = nil
                    if d.parent ~= nil and d.parent.valid then
                        uiWidth = d.parent.renderedWidth
                    end
                    if type(uiWidth) ~= "number" or uiWidth <= 100 then
                        uiWidth = 1080 * (dmhub.screenDimensionsBelowTitlebar.x / dmhub.screenDimensionsBelowTitlebar.y)
                    end
                    local center = (d.x or 0) + (d.renderedWidth or 0) / 2
                    if center > uiWidth / 2 then
                        return "left"
                    end
                end
                return "right"
            end,
        },

        --Component-local theme extras: header strip on the alt surface,
        --hairline under it, tab chips that read like the dock's tabs.
        --App icons are full-colour; "white" is the image-tint-neutral value.
        styles = ThemeEngine.MergeTokens({
            {
                selectors = {"panelDocumentHeader"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"panelDocumentHairline"},
                bgcolor = "@border",
            },
            {
                selectors = {"panelDocumentHeaderIcon"},
                bgcolor = "white",
            },
            --Chips carry no outline; the active tab is read from fill +
            --weight, following the design system's canonical {tab}: rest @bg,
            --selected the LIGHTER @bgAlt. Note the direction -- @bg (#0A0A0B)
            --is the darkest token in the ladder, so there is nothing below it
            --to "deepen" into; separation has to come from lifting the
            --selected chip, not sinking it.
            {
                selectors = {"panelDocumentTab"},
                bgcolor = "@bg",
                border = 1,
                borderColor = "clear",
                cornerRadius = 4,
                transitionTime = 0.15,
            },
            {
                selectors = {"panelDocumentTab", "hover"},
                bgcolor = "@fgMuted",
            },
            {
                selectors = {"panelDocumentTab", "selected"},
                bgcolor = "@bgAlt",
                borderColor = "clear",
            },
            --weight is the second half of the signal: rest is regular, the
            --selected chip goes bold. bold was previously on the base rule,
            --so every chip was bold and the weight said nothing.
            {
                selectors = {"label", "panelDocumentTitle"},
                color = "@fg",
                fontSize = 12,
                bold = false,
            },
            {
                selectors = {"label", "panelDocumentTitle", "parent:selected"},
                color = "@fgStrong",
                bold = true,
            },
        }),

        --tab plumbing for outside callers (the rail, pin restore):
        --fired via dialog:FireEventTree.
        addPanelTab = function(element, key)
            AddTab(string.lower(key))
        end,
        activatePanelTab = function(element, key)
            SwitchTab(string.lower(key))
        end,

        header,
        hairline,
        contentArea,
    }

    --the window opens with its own panel as the first tab.
    AddTab(string.lower(self.panelName))
    m_constructing = false

    return resultPanel
end

----------------------------------------------------------------------
-- Panel icon rail
-- ---------------
-- Experimental alternative host for the dockable panels: a translucent
-- icon rail on the left edge of the screen. Clicking an icon opens the
-- panel in a document window beside the rail (one such "transient"
-- window at a time); dragging a window pins it where it lands, and any
-- number of pinned windows can stay open. Pins persist per game.
--
-- Off by default; per-user trial mode via /toggle iconrail. The dock
-- system is untouched while the rail is off.
----------------------------------------------------------------------

setting{
    id = "iconrail",
    description = "Panel Icon Rail",
    help = "Experimental: summon panels as floating windows from an icon rail on the left edge of the screen.",
    storage = "preference",
    default = false,
    onchange = function()
        if mod.unloaded then
            return
        end
        EnsureIconRail()
    end,
}

--Pinned rail windows for this game: { [panelKey] = {x = ..., y = ..., tabs = {...}} }.
setting{
    id = "iconrailpins",
    storage = "pergamepreference",
    default = {},
}

--Which rail each panel button lives on and in what order:
--{ [panelKey] = { side = "left"|"right", ord = number } }. Panels absent
--from the table default to the left rail in curated order. Written when
--the user drags a button to rearrange.
setting{
    id = "iconraillayout",
    storage = "pergamepreference",
    default = {},
}

--g_iconRailPanels (the curated panel list) is declared above the
--PanelDocument interface, which also uses it for the add-tab menu.

local ICON_RAIL_BUTTON = 40
local ICON_RAIL_GAP = 8
local ICON_RAIL_LEFT = 12
local ICON_RAIL_TOP = 64
--vertical space the dock/tray button and its separator occupy above the
--panel buttons (button + 12px separator strip). Both rails carry a tray.
local ICON_RAIL_TRAY_OFFSET = ICON_RAIL_BUTTON + 12

--the two rails, keyed "left"/"right".
local g_iconRails = {}
--the panel key of the current click-opened (un-pinned) window. Shared
--across both rails: there is one transient window, whichever side it
--was summoned from.
local g_railTransientKey = nil
--set when a button drag ends, so the click the engine may deliver on
--release does not also toggle a window.
local g_railDragTime = nil
--the layout key that just landed from a drop: the rebuild marks that
--button "justDropped" so it settles in with a scale-down animation.
local g_railJustDropped = nil

local function IconRailPins()
    return dmhub.GetSettingValue("iconrailpins") or {}
end

local function SetIconRailPins(pins)
    dmhub.SetSettingValue("iconrailpins", pins)
end

--the width of the rail's coordinate space. MEASURED from the documents
--panel (the parent everything rail-related lives in): computing it from
--the screen aspect over-estimates by ~40 units (the layer is 1048 UI
--units tall, not 1080), which visibly pushed right-anchored ghosts and
--windows past the right rail. Falls back to the aspect formula before
--the first layout pass.
local function IconRailUIWidth()
    if GameHud.instance ~= nil and GameHud.instance.documentsPanel ~= nil and GameHud.instance.documentsPanel.valid then
        local w = GameHud.instance.documentsPanel.renderedWidth
        if type(w) == "number" and w > 100 then
            return w
        end
    end
    return 1080 * (dmhub.screenDimensionsBelowTitlebar.x / dmhub.screenDimensionsBelowTitlebar.y)
end

--Buttons occupy SLOTS on their rail: a sparse column where empty slots
--render as gaps, so users can leave blank spots between buttons. Slot
--pitch is one button plus one gap.
local ICON_RAIL_MAX_SLOT = 16

--The current button layout. Returns TWO values:
--  sides: available panels partitioned onto the two rails -- each a list
--    of {key, name, slot} sorted by slot (holes allowed = blank spots).
--  inert: entries preserved in storage but not rendered -- panels that
--    are unavailable here (absent mod, dmonly for this user, devonly)
--    or parked with side = "off". Inert entries must survive every save
--    so applying and re-saving a layout in a reduced context never
--    strips panels from it (Views brief, amendment A3).
--ANY registered panel may appear in the layout; the curated
--g_iconRailPanels list only provides first-run defaults for panels
--without a stored entry. Legacy entries (ord, no slot) compact into the
--lowest free slots; slot collisions bump downward.
local function RailLayout()
    local stored = dmhub.GetSettingValue("iconraillayout") or {}
    local sides = { left = {}, right = {} }
    local inert = {}
    local seen = {}

    local function place(key, displayName, entry, defaultOrd)
        if seen[key] then
            return
        end
        seen[key] = true

        local side = "left"
        local slot = nil
        local ord = defaultOrd or 9999
        if entry ~= nil then
            if entry.side == "right" or entry.side == "off" then
                side = entry.side
            end
            if entry.slot ~= nil then
                slot = entry.slot
            end
            if entry.ord ~= nil then
                ord = entry.ord
            end
        end

        if side == "off" then
            --parked off the rails; only worth remembering if stored.
            if entry ~= nil then
                inert[#inert + 1] = { key = key, side = "off", slot = slot }
            end
            return
        end

        --"doc:<id>" entries are journal document shortcuts,
        --"character:<charid>" entries are character panels; anything
        --else is a registered panel.
        local available
        local docid = string.match(key, "^doc:(.+)$")
        local charid = string.match(key, "^character:(.+)$")
        if docid ~= nil then
            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local doc = docs[docid]
            available = doc ~= nil and (not doc.hidden)
            if available then
                displayName = doc.description or "Document"
            end
        elseif charid ~= nil then
            local token = dmhub.GetCharacterById(charid)
            available = token ~= nil
            if available then
                displayName = token.name or "Character"
            end
        else
            available = PanelDocument.Get(displayName) ~= nil
        end

        if not available then
            --unavailable in this game/for this role: keep the stored
            --entry inert; render nothing.
            if entry ~= nil then
                inert[#inert + 1] = { key = key, side = side, slot = slot }
            end
            return
        end
        local list = sides[side]
        list[#list + 1] = { key = key, name = displayName, slot = slot, ord = ord, docid = docid, charid = charid }
    end

    --curated panels first: they carry the first-run default ordering.
    for i, name in ipairs(g_iconRailPanels) do
        place(string.lower(name), name, stored[string.lower(name)], i * 10)
    end
    --then any other stored panels (put on the rail by views or menus).
    for key, entry in pairs(stored) do
        if type(entry) == "table" then
            local reg = DockablePanel.GetRegistration(key)
            place(key, (reg ~= nil and reg.name) or key, entry, nil)
        end
    end

    for _, sideList in pairs(sides) do
        --explicit slots first (ascending), then default entries by ord.
        table.sort(sideList, function(a, b)
            if (a.slot ~= nil) ~= (b.slot ~= nil) then
                return a.slot ~= nil
            end
            if a.slot ~= nil then
                return a.slot < b.slot
            end
            return a.ord < b.ord
        end)
        --Dense list: the rail always packs from the top with no gaps. The
        --stored slot only drives the sort above; blank spacer slots are not
        --preserved. (Prototype of the dense-list reorder model -- reordering
        --shifts neighbours by one and never opens a hole, matching how a
        --tab strip / bookmark bar / dock behaves.)
        for i, e in ipairs(sideList) do
            e.slot = i - 1
        end
    end
    return sides, inert
end

local function SaveRailLayout(sides, inert)
    local stored = {}
    for side, list in pairs(sides) do
        for _, e in ipairs(list) do
            stored[e.key] = { side = side, slot = e.slot }
        end
    end
    for _, e in ipairs(inert or {}) do
        if stored[e.key] == nil then
            stored[e.key] = { side = e.side, slot = e.slot }
        end
    end
    dmhub.SetSettingValue("iconraillayout", stored)
end

--Where a window summoned from a rail icon lands: beside that rail,
--level with the icon, clamped on screen. Computed at click time so it
--tracks the live screen width.
local function RailAnchor(side, index)
    local anchorY = ICON_RAIL_TOP + ICON_RAIL_TRAY_OFFSET + index * (ICON_RAIL_BUTTON + ICON_RAIL_GAP)
    local maxY = 1080 - PanelDocument.DefaultHeight - 40
    if anchorY > maxY then
        anchorY = maxY
    end
    local anchorX
    if side == "left" then
        anchorX = ICON_RAIL_LEFT + ICON_RAIL_BUTTON + 10
    else
        anchorX = IconRailUIWidth() - ICON_RAIL_LEFT - ICON_RAIL_BUTTON - 10 - PanelDocument.DefaultWidth
    end
    return anchorX, anchorY
end

local function RefreshRails()
    for _, rail in pairs(g_iconRails) do
        if rail ~= nil and rail.valid then
            rail:FireEventTree("refreshRail")
        end
    end
end

--Where a button being dragged from (side, slot) would land right now:
--which rail (screen half) and which slot. Shared by the live ghost and
--the drop itself so they can never disagree.
local function RailDropTarget(side, slot, element)
    local baseX = cond(side == "left", ICON_RAIL_LEFT, IconRailUIWidth() - ICON_RAIL_LEFT - ICON_RAIL_BUTTON)
    local baseY = ICON_RAIL_TOP + ICON_RAIL_TRAY_OFFSET + slot * (ICON_RAIL_BUTTON + ICON_RAIL_GAP)
    local dropX = baseX + (element.xdrag or 0) + ICON_RAIL_BUTTON / 2
    local dropY = baseY + (element.ydrag or 0)

    local targetSide = cond(dropX > IconRailUIWidth() / 2, "right", "left")
    local targetSlot = math.floor((dropY - ICON_RAIL_TOP - ICON_RAIL_TRAY_OFFSET) / (ICON_RAIL_BUTTON + ICON_RAIL_GAP) + 0.5)
    if targetSlot < 0 then
        targetSlot = 0
    end
    --Dense list: you can only drop between existing icons or at the end, so
    --clamp to the target rail's length. This keeps the ghost preview in step
    --with where the drop actually lands -- no aiming into empty space and
    --getting snapped back to the tail.
    local sides = RailLayout()
    local count = #(sides[targetSide] or {})
    if targetSlot > count then
        targetSlot = count
    end
    return targetSide, targetSlot
end

--The layer the rails and panel windows live on, or nil when the hud is
--not up. GameHud.instance is FALSE (not nil) while the hud is down --
--notably during a Lua reload -- so the obvious `~= nil` test passes and
--the following index throws "attempt to index a boolean value". Every
--reach for the documents layer goes through here.
local function DocumentsLayer()
    local hud = GameHud.instance
    if not hud then
        return nil
    end
    local panel = nil
    pcall(function() panel = hud.documentsPanel end)
    if panel == nil or not panel.valid then
        return nil
    end
    return panel
end

--the drag ghost panel and its helpers live below IconRailStyles, which
--they depend on.
local g_railDragGhost = nil
local ShowRailGhost
local HideRailGhost

--Whether a slot on a side holds a button other than excludeKey (the
--dragged button's own slot never reads as occupied).
local function RailSlotOccupied(side, slot, excludeKey)
    local sides = RailLayout()
    for _, e in ipairs(sides[side]) do
        if e.slot == slot and e.key ~= excludeKey then
            return true
        end
    end
    return false
end

--While the rail is on, the docks' own slide-away handle tabs are
--redundant (each rail's tray button owns its dock's visibility), so we
--hide them; they come back the moment the mode is turned off. Docks are
--rebuilt by reloads and theme changes, so the rail's think re-applies
--this continuously rather than relying on a one-shot.
local function SyncDockHandles()
    if gamehud == nil or rawget(gamehud, "leftDock") == nil then
        return
    end
    local railOn = dmhub.GetSettingValue("iconrail") == true and devmode()
    for _, dock in ipairs({gamehud.leftDock, gamehud.rightDock}) do
        if dock ~= nil and dock.valid then
            for _, child in ipairs(dock.children) do
                if child.valid and child:HasClass("dockHandle") then
                    child:SetClass("collapsed", railOn)
                end
            end
        end
    end
end

--Open a rail window for the named panel. placement = {x=,y=,tabs=} anchors
--it (and restores added tabs); nil lets PresentDocument use the
--session-remembered location.
local function OpenIconRailWindow(panelName, placement)
    --accepts a registered panel name OR a layout key (character
    --shortcuts pass "character:<charid>", which is not a panel name).
    local doc = RailPanelDocument(panelName)
    if doc == nil then
        return
    end
    local key = string.lower(panelName)

    local args = {
        --dragging a rail window pins it where it lands, tabs and all.
        onMoved = function(element)
            local pins = IconRailPins()
            pins[key] = { x = element.x, y = element.y, tabs = element.data.panelTabs }
            SetIconRailPins(pins)
            if g_railTransientKey == key then
                g_railTransientKey = nil
            end
        end,

        --the header close button: closing forgets the pin.
        close = function()
            local pins = IconRailPins()
            if pins[key] ~= nil then
                pins[key] = nil
                SetIconRailPins(pins)
            end
            if g_railTransientKey == key then
                g_railTransientKey = nil
            end
            doc:ClosePanel()
            RefreshRails()
        end,

        --adding or removing a tab pins the window: a multi-panel window
        --is an arrangement worth keeping.
        onTabsChanged = function(keys)
            local d = doc:try_get("_tmp_dialog")
            if d == nil or not d.valid then
                return
            end
            local pins = IconRailPins()
            pins[key] = { x = d.x, y = d.y, tabs = keys }
            SetIconRailPins(pins)
            if g_railTransientKey == key then
                g_railTransientKey = nil
            end
            RefreshRails()
        end,
    }
    if placement ~= nil then
        args.x = placement.x
        args.y = placement.y
    end

    local dlg = doc:PresentPanel(args)

    --restore this pin's added tabs (beyond the window's own panel), then
    --land on the window's own tab rather than the last one added.
    if placement ~= nil and placement.tabs ~= nil and dlg ~= nil and dlg.valid then
        local added = false
        for _, k in ipairs(placement.tabs) do
            if k ~= key then
                dlg:FireEventTree("addPanelTab", k)
                added = true
            end
        end
        if added then
            dlg:FireEventTree("activatePanelTab", key)
        end
    end
end

--Rail styling: the over-map scrim ladder from the B&W design system --
--warm black at graded alphas with the single white accent for borders
--and icons. These values are intentionally scheme-independent (the rail
--floats over the battlemap, not over a themed surface). Shared by the
--rails and the dock-mounted tray button, which lives outside the rail
--cascade.
local function IconRailStyles()
    return ThemeEngine.MergeTokens({
        --buttons are borderless (Lisa+David review 2026-07-19), on a
        --black partially-transparent frosted backdrop (Lisa 2026-07-19
        --follow-up: black + blur; blurBackground is set on the button
        --panels). Icons wear the panels' font color (@fg) so the rail
        --matches the panel windows; hover/active brighten to @fgStrong.
        --The active state stays icon + underline, never a border.
        {
            selectors = {"iconRailButton"},
            bgcolor = "#000000cc",
            border = 0,
            cornerRadius = 8,
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailButton", "hover"},
            bgcolor = "#000000ee",
        },
        --a freshly dropped button lands slightly oversized and settles
        --to rest through the transition when the class clears.
        {
            selectors = {"iconRailButton", "justDropped"},
            scale = 1.25,
        },
        {
            selectors = {"iconRailIcon"},
            bgcolor = "@fg",
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailIcon", "parent:hover"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"iconRailIcon", "parent:active"},
            bgcolor = "@fgStrong",
        },
        --the active underline: a short bar under the icon of any button
        --whose panel is currently visible.
        {
            selectors = {"iconRailActiveMark"},
            bgcolor = "@fgStrong",
            opacity = 0,
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailActiveMark", "parent:active"},
            opacity = 1,
        },
        --the dock-handle art is coloured; desaturate + brighten it into
        --the rail's language (same treatment the dock handle itself
        --gets), tinted to the panels' font color like the other icons.
        --Mirrored on the left to match the left dock's handle; the
        --right keeps the art's native facing.
        {
            selectors = {"iconRailTrayIcon"},
            bgcolor = "@fg",
            saturation = 0,
            brightness = 2,
            scale = {x = -1},
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailTrayIcon", "rightSide"},
            scale = {x = 1},
        },
        {
            selectors = {"iconRailTrayIcon", "parent:hover"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"iconRailTrayIcon", "parent:active"},
            bgcolor = "@fgStrong",
        },
        --The RAIL's tray glyph: a phosphor sidebar icon reading as a panel
        --sliding out from the screen edge. Kept separate from
        --iconRailTrayIcon above, which the dock-mounted tray button still
        --uses with the coloured dock-handle art. Phosphor art is already a
        --monochrome white mask, so it takes the @fg tint but NOT the
        --saturation/brightness treatment that exists to tame the handle art
        --(brightness 2 on a white mask just clips it). Facing is the
        --OPPOSITE of the handle's: native on the left, where the glyph's bar
        --already sits on its left edge and matches the left dock, and
        --mirrored on the right so the bar sits on that side instead.
        {
            selectors = {"iconRailTrayGlyph"},
            bgcolor = "@fg",
            scale = {x = 1},
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailTrayGlyph", "rightSide"},
            scale = {x = -1},
        },
        {
            selectors = {"iconRailTrayGlyph", "parent:hover"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"iconRailTrayGlyph", "parent:active"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"iconRailHairline"},
            bgcolor = "#ffffff26",
        },
        --the drop placeholder: a dotted-outline box marking the slot a
        --dragged button/document will land in (the buttons below shift
        --down live to open the gap it sits in). The outline is built from
        --dash panels -- the engine has no dotted border style, and no
        --dotted 9-slice image ships with the app -- over a very faint
        --fill so the box still reads against a busy map.
        {
            selectors = {"iconRailGhost"},
            bgcolor = "#ffffff14",
            border = 0,
            cornerRadius = 8,
        },
        {
            selectors = {"iconRailGhost", "hidden"},
            hidden = 1,
        },
        {
            selectors = {"iconRailGhostDash"},
            bgcolor = "#ffffff8c",
        },
        --the Views toast box and its text (the chip itself is gone --
        --Lisa+David review 2026-07-19 -- but the toast reuses its look).
        {
            selectors = {"iconRailViewChip"},
            bgcolor = "#0a0a0bb3",
            border = 1,
            borderColor = "#ffffff2e",
            cornerRadius = 6,
            transitionTime = 0.15,
        },
        {
            selectors = {"label", "iconRailViewChipLabel"},
            color = "#e8e8e8",
            fontSize = 11,
            bold = true,
        },
        {
            selectors = {"label", "iconRailViewToastUndo"},
            color = "#ffffff",
            fontSize = 11,
            bold = true,
        },
        {
            selectors = {"label", "iconRailLabel"},
            opacity = 0,
            bgcolor = "#0a0a0beb",
            border = 1,
            --@border (white @ 0.16) rather than the old hard-coded #ffffff47
            --(0.28): the design system's quiet-edge standard, and it follows
            --the colour scheme instead of pinning white in every theme.
            borderColor = "@border",
            cornerRadius = 6,
            color = "@fg",
            fontSize = 11,
            bold = true,
            transitionTime = 0.15,
        },
        {
            selectors = {"label", "iconRailLabel", "parent:hover"},
            opacity = 1,
        },
    })
end

--The buttons currently shifted to open a drag gap ({panel, base}), and
--the signature of the shift so a drag hovering the same slot doesn't
--re-apply margins every frame. (selfStyle properties are write-mostly:
--reading them back is unreliable, so we track what we shifted.)
local g_railShifted = {}
local g_railShiftSig = nil

--Undo any gap ShowRailGhost opened: shifted buttons return to their
--constructed margins.
local function RailRestoreShift()
    for _, info in ipairs(g_railShifted) do
        if info.panel ~= nil and info.panel.valid then
            info.panel.selfStyle.tmargin = info.base
        end
    end
    g_railShifted = {}
    g_railShiftSig = nil
end

HideRailGhost = function()
    RailRestoreShift()
    if g_railDragGhost ~= nil and g_railDragGhost.valid then
        g_railDragGhost:SetClass("hidden", true)
    end
end

--Live preview of where a dragged button/document will land (Lisa+David
--review 2026-07-19): a lightly filled placeholder box sits at the target
--slot, and when that slot is occupied the buttons from it down SHIFT to
--open a real gap for the box (extra tmargin on the first affected
--button; vertical flow carries everything below it along). excludeKey
--is the dragged button's own key: its slot never reads as occupied and
--it never shifts (the engine is already moving it with the cursor).
--Build the four dashed edges of the drop placeholder. The engine exposes
--no dotted border style and ships no dotted 9-slice image, so each edge is
--a flow of small dash panels; DASH and the gap between dashes are equal, so
--`count` dashes tile the edge evenly. Corners are left open, which is what
--a dotted outline looks like anyway.
local function DottedOutlineChildren(size)
    local DASH = 4
    local THICK = 2
    local count = math.max(2, math.floor(size / (DASH * 2)))

    local function edge(horizontal, align)
        local dashes = {}
        for i = 1, count do
            dashes[#dashes+1] = gui.Panel{
                classes = {"iconRailGhostDash"},
                bgimage = true,
                width = cond(horizontal, DASH, THICK),
                height = cond(horizontal, THICK, DASH),
                halign = "center",
                valign = "center",
                hmargin = cond(horizontal, DASH / 2, 0),
                vmargin = cond(horizontal, 0, DASH / 2),
            }
        end
        return gui.Panel{
            width = cond(horizontal, "100%", THICK),
            height = cond(horizontal, THICK, "100%"),
            flow = cond(horizontal, "horizontal", "vertical"),
            halign = cond(horizontal, "center", align),
            valign = cond(horizontal, align, "center"),
            interactable = false,
            children = dashes,
        }
    end

    return {
        edge(true, "top"),
        edge(true, "bottom"),
        edge(false, "left"),
        edge(false, "right"),
    }
end

ShowRailGhost = function(side, slot, excludeKey)
    local layer = DocumentsLayer()
    if layer == nil then
        return
    end
    --Insertion LINE (dense-list model): a thin bright bar in the gap where the
    --dragged icon will land, rather than a box occupying a slot with the
    --buttons below shoved down. The line reads as "it goes HERE" and the rail
    --stays still -- no shuffling, which was jittery and reinforced the old
    --absolute-cell feel. excludeKey is unused now (nothing shifts).
    if g_railDragGhost == nil or not g_railDragGhost.valid then
        g_railDragGhost = gui.Panel{
            classes = {"iconRailGhostLine"},
            bgimage = "panels/square.png",
            bgcolor = "#ffffffe0",
            cornerRadius = 2,
            width = ICON_RAIL_BUTTON,
            height = 3,
            halign = "left",
            valign = "top",
            interactable = false,
        }
        layer:AddChild(g_railDragGhost)
    end

    local railX = cond(side == "left", ICON_RAIL_LEFT, IconRailUIWidth() - ICON_RAIL_LEFT - ICON_RAIL_BUTTON)
    local slotTop = ICON_RAIL_TOP + ICON_RAIL_TRAY_OFFSET + slot * (ICON_RAIL_BUTTON + ICON_RAIL_GAP)
    g_railDragGhost.x = railX
    --centre the line in the gap ABOVE the target slot (between the previous
    --icon and this one); slotTop is that slot's top edge.
    g_railDragGhost.y = slotTop - ICON_RAIL_GAP / 2 - 1
    g_railDragGhost:SetClass("hidden", false)
end

local ICON_RAIL_DOCK_HEADER_HEIGHT = 30

--The dock's own header bar: a dock-LEVEL strip across the top of each dock,
--which is where dock-level controls belong. The sidebar toggle used to be a
--tenant of the topmost panel's title bar, which meant it rode whichever panel
--happened to be on top and had to shove that panel's minimize/collapse arrows
--sideways to fit. A header of its own removes both problems and leaves room
--for further dock-level controls later.
--
--Safe to add as a dock child: the dock's own layout and save paths
--(fitChildren, layoutChanged, Serialize) all go through class-filtered
--lookups for "dockablePanelContainer", so an extra child is ignored by them.
--It is NOT floating -- it sits in the dock's flow so the panels below start
--underneath it rather than behind it.
local function CreateDockHeader(side)
    local dockSettingId = side .. "dockoffscreen"

    local iconClasses = {"iconRailTrayGlyph"}
    if side == "right" then
        iconClasses[#iconClasses + 1] = "rightSide"
    end

    local button = gui.Panel{
        classes = {"iconRailDockButton"},
        bgimage = true,
        width = 20,
        height = 20,
        flow = "none",
        --hard against the edge nearest screen centre: the left dock's inner
        --edge is its RIGHT, the right dock's is its LEFT.
        valign = "center",
        halign = cond(side == "left", "right", "left"),
        hmargin = 8,

        gui.Panel{
            classes = iconClasses,
            bgimage = "phosphor/sidebar-simple-light.png",
            width = 18,
            height = 18,
            halign = "center",
            valign = "center",
        },

        click = function(element)
            dmhub.SetSettingValue(dockSettingId, true)
            for _, rail in pairs(g_iconRails) do
                if rail ~= nil and rail.valid then
                    rail:FireEvent("syncDockMode")
                end
            end
        end,
    }

    return gui.Panel{
        classes = {"iconRailDockHeader"},
        styles = IconRailStyles(),
        bgimage = "panels/square.png",
        bgcolor = "@bgAlt",
        width = "100%",
        height = ICON_RAIL_DOCK_HEADER_HEIGHT,
        flow = "none",
        valign = "top",

        button,

        --hairline along the bottom edge, matching the dock's other seams.
        gui.Panel{
            bgimage = "panels/square.png",
            bgcolor = "@border",
            width = "100%",
            height = 1,
            halign = "center",
            valign = "bottom",
        },
    }
end

--Keep a header bar mounted on each dock while the rail mode is on, and remove
--it when the mode is off. Docks rebuild their child lists on layout changes,
--so this is re-applied from the rail's think.
local function EnsureDockTrayButtons()
    if gamehud == nil or rawget(gamehud, "leftDock") == nil then
        return
    end
    local railOn = dmhub.GetSettingValue("iconrail") == true and devmode()
    for _, info in ipairs({ { dock = gamehud.leftDock, side = "left" }, { dock = gamehud.rightDock, side = "right" } }) do
        local dock = info.dock
        if dock ~= nil and dock.valid then
            local header = nil
            for _, child in ipairs(dock.children) do
                if child.valid and child:HasClass("iconRailDockHeader") then
                    if railOn and header == nil then
                        header = child
                    else
                        --mode off, or a duplicate from a rebuild.
                        child:DestroySelf()
                    end
                end
            end

            --Sweep any button left inside a panel's title bar by the previous
            --arrangement, so upgrading mid-session does not strand one there.
            for _, child in ipairs(dock.children) do
                if child.valid and child:HasClass("dockablePanelContainer") then
                    local wrapper = child.children[1]
                    if wrapper ~= nil and wrapper.valid then
                        for _, g in ipairs(wrapper.children or {}) do
                            if g.valid and g:HasClass("iconRailDockButton") then
                                g:DestroySelf()
                            end
                        end
                    end
                end
            end

            if railOn and header == nil then
                dock:AddChild(CreateDockHeader(info.side))
                --AddChild appends, which would put the header BELOW the panels
                --in the dock's flow. Push every container after it instead --
                --SetAsLastSibling preserves their relative order, so walking
                --them in order leaves the header first and the panels intact.
                for _, child in ipairs(dock.children) do
                    if child.valid and child:HasClass("dockablePanelContainer") then
                        child:SetAsLastSibling()
                    end
                end
                dock:FireEvent("fitChildren")
            end
        end
    end
end

--forward-declared: button drag handlers rebuild the rails.
local RebuildIconRails

--Non-drag rearrangement (accessibility parity, Views brief A9a): the
--same moves dragging performs, driven from the rail-button context menu.
--op: "up" | "down" | "side" | "remove".
local function RailMovePanel(key, op)
    local sides, inert = RailLayout()
    local entry, sideName, list, idx
    for sn, l in pairs(sides) do
        for i, e in ipairs(l) do
            if e.key == key then
                entry, sideName, list, idx = e, sn, l, i
            end
        end
    end
    if entry == nil then
        return
    end

    if op == "up" or op == "down" then
        local target = entry.slot + cond(op == "up", -1, 1)
        if target < 0 then
            return
        end
        for _, e in ipairs(list) do
            if e ~= entry and e.slot == target then
                e.slot = entry.slot
            end
        end
        entry.slot = target
    elseif op == "side" then
        table.remove(list, idx)
        local otherList = sides[cond(sideName == "left", "right", "left")]
        table.insert(otherList, entry)
        table.sort(otherList, function(a, b)
            if a.slot == b.slot then
                return a == entry
            end
            return a.slot < b.slot
        end)
        local used = {}
        for _, e in ipairs(otherList) do
            local s = e.slot
            while used[s] do
                s = s + 1
            end
            used[s] = true
            e.slot = s
        end
    elseif op == "remove" then
        table.remove(list, idx)
        inert[#inert + 1] = { key = key, side = "off", slot = entry.slot }
    end

    SaveRailLayout(sides, inert)
    RebuildIconRails()
end

--Add a panel to a rail at the next free slot (the inverse of "Remove
--from rail"; also how non-curated panels first reach the rail).
local function RailAddPanel(name, side)
    local sides, inert = RailLayout()
    local key = string.lower(name)
    for _, l in pairs(sides) do
        for _, e in ipairs(l) do
            if e.key == key then
                return
            end
        end
    end
    for i, e in ipairs(inert) do
        if e.key == key then
            table.remove(inert, i)
            break
        end
    end
    local list = sides[side]
    local maxSlot = -1
    for _, e in ipairs(list) do
        if e.slot > maxSlot then
            maxSlot = e.slot
        end
    end
    list[#list + 1] = { key = key, name = name, slot = maxSlot + 1 }
    SaveRailLayout(sides, inert)
    RebuildIconRails()
end

--Rail mode gate, exported so other surfaces (the Panels menu, the
--journal) can ask without repeating the setting+devmode pair.
function RailModeActive()
    return dmhub.GetSettingValue("iconrail") == true and devmode()
end

--Whether a registered panel currently has a rail button.
function RailHasPanel(name)
    local key = string.lower(name)
    local sides = RailLayout()
    for _, l in pairs(sides) do
        for _, e in ipairs(l) do
            if e.key == key then
                return true
            end
        end
    end
    return false
end

--Add or remove a panel's rail button. In rail mode the Panels menu picks
--SHORTCUTS rather than opening panels (Lisa, 2026-07-20), so this is the
--verb behind every panel entry in that menu.
function RailTogglePanel(name, side)
    if RailHasPanel(name) then
        RailMovePanel(string.lower(name), "remove")
    else
        RailAddPanel(name, side or "left")
    end
end

--Which rail slot a drag target corresponds to: a rail button maps to
--its own slot (the drop inserts there), the rail background or the tray
--appends to the end of that side. nil when the target is not a rail.
local function RailNextFreeSlot(side)
    local sides = RailLayout()
    local maxSlot = -1
    for _, e in ipairs(sides[side]) do
        if e.slot > maxSlot then
            maxSlot = e.slot
        end
    end
    return maxSlot + 1
end

local function RailDocDropSlot(target)
    if target == nil or not target.valid then
        return nil
    end
    if target:HasClass("iconRailButton") then
        local rail = target.parent
        if rail ~= nil and rail.valid and rail:HasClass("iconRail") then
            local slot = nil
            pcall(function() slot = target.data.slot end)
            if slot ~= nil then
                return rail.data.side, slot
            end
            return rail.data.side, RailNextFreeSlot(rail.data.side)
        end
        return nil
    end
    if target:HasClass("iconRail") then
        return target.data.side, RailNextFreeSlot(target.data.side)
    end
    return nil
end

--Journal-to-rail shortcut API, called from the journal panel's document
--rows (Journal.lua): dragging a document over a rail previews the slot
--with the ghost; dropping stores a "doc:<id>" layout entry there.
function IconRailDocDragging(target)
    local side, slot = RailDocDropSlot(target)
    if side ~= nil then
        ShowRailGhost(side, slot, nil)
    else
        HideRailGhost()
    end
end

--Drop an arbitrary layout key onto the rail slot under `target`. Shared by
--the document and character drop paths -- both are just a key landing in a
--slot, so the placement logic lives here once.
local function RailKeyDrop(key, target)
    local side, slot = RailDocDropSlot(target)
    if side == nil or key == nil then
        return false
    end

    local sides, inert = RailLayout()
    --already on a rail (or parked inert): move rather than duplicate.
    for _, l in pairs(sides) do
        for i, e in ipairs(l) do
            if e.key == key then
                table.remove(l, i)
                break
            end
        end
    end
    for i, e in ipairs(inert) do
        if e.key == key then
            table.remove(inert, i)
            break
        end
    end

    local list = sides[side]
    local entry = { key = key, slot = slot }
    g_railJustDropped = key
    table.insert(list, entry)
    table.sort(list, function(a, b)
        if a.slot == b.slot then
            return a == entry
        end
        return a.slot < b.slot
    end)
    local used = {}
    for _, e in ipairs(list) do
        local s = e.slot
        while used[s] do
            s = s + 1
        end
        used[s] = true
        e.slot = s
    end

    SaveRailLayout(sides, inert)
    RebuildIconRails()
    return true
end

function IconRailDocDrop(docid, target)
    HideRailGhost()
    if docid == nil then
        return false
    end
    local docs = dmhub.GetTable(CustomDocument.tableName) or {}
    if docs[docid] == nil then
        return false
    end
    return RailKeyDrop("doc:" .. docid, target)
end

--The character equivalent: dragging a character out of the journal's
--Characters section onto a rail drops a "character:<charid>" shortcut,
--exactly as a document row drops a "doc:<id>" one.
function IconRailCharacterDrop(charid, target)
    HideRailGhost()
    if charid == nil or dmhub.GetCharacterById(charid) == nil then
        return false
    end
    return RailKeyDrop("character:" .. charid, target)
end

--Append a shortcut for an arbitrary layout key to the end of one rail,
--moving it there if it is already on a rail.
local function RailAddKey(key, side)
    if side ~= "left" and side ~= "right" then
        side = "left"
    end
    local sides, inert = RailLayout()
    for _, l in pairs(sides) do
        for i, e in ipairs(l) do
            if e.key == key then
                table.remove(l, i)
                break
            end
        end
    end
    for i, e in ipairs(inert) do
        if e.key == key then
            table.remove(inert, i)
            break
        end
    end
    local list = sides[side]
    local maxSlot = -1
    for _, e in ipairs(list) do
        if e.slot > maxSlot then
            maxSlot = e.slot
        end
    end
    list[#list + 1] = { key = key, slot = maxSlot + 1 }
    SaveRailLayout(sides, inert)
    RebuildIconRails()
    return true
end

--Menu path (no drag): append a document shortcut to the given rail.
--The non-drag parity for the journal-to-rail gesture (A9a).
function IconRailDocAdd(docid, side)
    local docs = dmhub.GetTable(CustomDocument.tableName) or {}
    if docid == nil or docs[docid] == nil then
        return false
    end
    return RailAddKey("doc:" .. docid, side)
end

--Menu path: put a character's panel on the given rail. The key is the
--CharacterPanelDocument's panelName, so the rail's open/close, pinning
--and Views machinery treat it exactly like a panel button.
function IconRailCharacterAdd(charid, side)
    if charid == nil or dmhub.GetCharacterById(charid) == nil then
        return false
    end
    return RailAddKey("character:" .. charid, side)
end

--Closing a panel from a dock (its right-click > Close) also takes its
--button off the rail and saves the layout. The dock and the rail are two
--views of one workspace: without this the button stays, and the panel
--comes straight back the next time the dock is filled from the rail.
if rawget(_G, "RegisterDockablePanelClosedHandler") ~= nil then
    RegisterDockablePanelClosedHandler("iconrail", function(panelName)
        if not (dmhub.GetSettingValue("iconrail") and devmode()) then
            return
        end
        --no-ops when the panel is not on a rail.
        RailMovePanel(string.lower(panelName), "remove")
    end)
end

local function CreateIconRail(side, entries)
    local buttons = {}

    --This side's dock-visibility setting: each rail's tray button drives
    --its own dock independently.
    local dockSettingId = side .. "dockoffscreen"

    --The dock/tray button: sits above the panel icons and toggles this
    --side's classic dock back on screen. Lit while that dock is visible.
    --Carries the phosphor sidebar glyph (a panel sliding out from the edge)
    --rather than the docks' own slide-handle art; the dock-MOUNTED tray
    --button still uses the handle, hence the separate glyph class.
    local trayIconClasses = {"iconRailTrayGlyph"}
    if side == "right" then
        trayIconClasses[#trayIconClasses + 1] = "rightSide"
    end

    --halign is EXPLICIT on both sides. Without it the label defaults to
    --centred on its x anchor and grows in BOTH directions, so a long title
    --spills back across the button it belongs to; anchoring the near edge
    --makes it grow away from the rail whatever its length.
    local trayLabelArgs
    if side == "left" then
        trayLabelArgs = { halign = "left", x = ICON_RAIL_BUTTON + 10 }
    else
        trayLabelArgs = { halign = "right", x = -(ICON_RAIL_BUTTON + 10) }
    end

    buttons[#buttons + 1] = gui.Panel{
        classes = {"iconRailButton"},
        bgimage = true,
        blurBackground = true,
        width = ICON_RAIL_BUTTON,
        height = ICON_RAIL_BUTTON,
        flow = "none",
        swallowPress = true,
        --empty data so the drag-reflow sweeps can read .data on every
        --rail child without the engine logging index errors.
        data = {},

        gui.Panel{
            classes = trayIconClasses,
            --square: phosphor glyphs are square art, unlike the 14x28 handle.
            bgimage = "phosphor/sidebar-simple-light.png",
            width = 20,
            height = 20,
            halign = "center",
            valign = "center",
        },

        gui.Label{
            classes = {"iconRailLabel"},
            floating = true,
            --the label opens over whatever the rail sits next to, and rail
            --windows left open sit between it and the viewer -- so it drew
            --BEHIND them and was unreadable. renderOnTop puts it on the
            --top-most sorting canvas.
            renderOnTop = true,
            x = trayLabelArgs.x,
            halign = trayLabelArgs.halign,
            valign = "center",
            interactable = false,
            bgimage = true,
            text = "DOCK",
            width = "auto",
            height = "auto",
            hpad = 8,
            vpad = 4,
            borderBox = true,
            textWrap = false,
        },

        click = function(element)
            local restoring = dmhub.GetSettingValue(dockSettingId) == true
            if restoring then
                --the dock mirrors this rail: same panels, same order --
                --and it takes over hosting them, so this side's open
                --rail windows close (pins stay saved in the setting).
                local entries = RailLayout()[side]
                local names = {}
                for _, e in ipairs(entries) do
                    --only registered panels can live in a dock; document
                    --and character shortcuts stay rail-only.
                    if e.docid == nil and e.charid == nil then
                        names[#names + 1] = e.name
                    end
                end
                DockablePanel.SetDockPanels(side, names)
                for _, e in ipairs(entries) do
                    local doc = RailPanelDocument(e.key)
                    if doc ~= nil and doc:PresentDocumentOpen() then
                        if g_railTransientKey == e.key then
                            g_railTransientKey = nil
                        end
                        doc:ClosePanel()
                    end
                end
            end
            dmhub.SetSettingValue(dockSettingId, not dmhub.GetSettingValue(dockSettingId))
            element:FireEvent("refreshRail")
            for _, rail in pairs(g_iconRails) do
                if rail ~= nil and rail.valid then
                    rail:FireEvent("syncDockMode")
                end
            end
        end,

        refreshRail = function(element)
            element:SetClass("active", not dmhub.GetSettingValue(dockSettingId))
        end,

        --right-click the tray: add any available panel to this rail
        --(the inverse of "Remove from rail", and the door for the ~40
        --registered panels beyond the curated defaults).
        rightClick = function(element)
            local onRail = {}
            local sides = RailLayout()
            for _, l in pairs(sides) do
                for _, e in ipairs(l) do
                    onRail[e.key] = true
                end
            end
            local entries = {}
            local items = DockablePanel.GetMenuItems(true)
            table.sort(items, function(a, b) return (a.text or "") < (b.text or "") end)
            for _, item in ipairs(items) do
                local name = item.text
                if name ~= nil and not onRail[string.lower(name)] and PanelDocument.Get(name) ~= nil then
                    entries[#entries + 1] = {
                        text = "Add: " .. name,
                        click = function()
                            element.popup = nil
                            RailAddPanel(name, side)
                        end,
                    }
                end
            end
            if #entries > 0 then
                element.popup = gui.ContextMenu{
                    entries = entries,
                }
            end
        end,
    }

    --separator between the tray button and the panel icons; pointless on
    --a rail with no panel buttons (a fresh right rail is just the tray).
    if #entries > 0 then
        buttons[#buttons + 1] = gui.Panel{
            width = "100%",
            height = 12,
            flow = "none",
            data = {},
            gui.Panel{
                classes = {"iconRailHairline"},
                bgimage = true,
                width = 24,
                height = 1,
                halign = "center",
                valign = "center",
            },
        }
    end

    local prevSlot = -1
    for i, entry in ipairs(entries) do
        local panelName = entry.name
        local key = entry.key
        local docid = entry.docid
        local charid = entry.charid

        --panel buttons draw their registration icon; document shortcuts
        --draw the doc's semantic-type icon; character shortcuts draw the
        --character's portrait (untinted, cropped square).
        local reg = nil
        local buttonIcon = "icons/icon_app/icon_app_107.png"
        local buttonIconTint = nil
        local buttonIconRect = nil
        if charid ~= nil then
            buttonIcon = "icons/standard/Icon_App_Character.png"
            local token = dmhub.GetCharacterById(charid)
            if token ~= nil then
                local portrait = nil
                pcall(function() portrait = token.offTokenPortrait end)
                if portrait ~= nil and portrait ~= "" then
                    buttonIcon = portrait
                    buttonIconTint = "white"
                    pcall(function()
                        buttonIconRect = token:GetPortraitRectForAspect(1, portrait)
                    end)
                end
            end
        elseif docid == nil then
            reg = DockablePanel.GetRegistration(panelName)
            if reg ~= nil and reg.icon ~= nil then
                buttonIcon = reg.icon
            end
        else
            buttonIcon = "icons/standard/Icon_App_Journal.png"
            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local doc = docs[docid]
            if doc ~= nil then
                pcall(function() buttonIcon = CustomDocument.DocTypeIcon(doc) end)
            end
        end
        --buttons sit at their SLOT: gaps between occupied slots render
        --as blank space. A button's top edge is slot * pitch from the
        --start of the panel area, so its margin is the distance from the
        --previous button's bottom edge (or the area start).
        local index = entry.slot
        local pitch = ICON_RAIL_BUTTON + ICON_RAIL_GAP
        local buttonMargin
        if prevSlot < 0 then
            buttonMargin = index * pitch
        else
            buttonMargin = (index - prevSlot) * pitch - ICON_RAIL_BUTTON
        end
        prevSlot = index

        --hover labels open toward the screen centre: right of the button
        --on the left rail, left of the button on the right rail. halign is
        --EXPLICIT on both sides -- without it the label defaults to centred on
        --its x anchor and grows in BOTH directions, so a long panel name
        --spilled back across its own button. Anchoring the near edge makes the
        --label grow away from the rail at any length.
        local labelArgs
        if side == "left" then
            labelArgs = { halign = "left", x = ICON_RAIL_BUTTON + 10 }
        else
            labelArgs = { halign = "right", x = -(ICON_RAIL_BUTTON + 10) }
        end

        --a button rebuilt right after landing from a drop settles in with
        --a scale-down animation: it constructs oversized (justDropped)
        --and sheds the class a moment later, riding the transition.
        local buttonClasses = {"iconRailButton"}
        if g_railJustDropped ~= nil and g_railJustDropped == key then
            buttonClasses[#buttonClasses + 1] = "justDropped"
            g_railJustDropped = nil
        end

        buttons[#buttons + 1] = gui.Panel{
            classes = buttonClasses,
            bgimage = true,
            blurBackground = true,
            width = ICON_RAIL_BUTTON,
            height = ICON_RAIL_BUTTON,
            flow = "none",
            tmargin = buttonMargin,
            --without this, a real right-click ALSO reaches the map and
            --the map's context menu replaces ours (popups are exclusive).
            swallowPress = true,
            --journal documents can be dropped onto buttons (insert at
            --this slot); data.slot is how the drop finds it. key and
            --baseMargin are for the live drag reflow (ShowRailGhost).
            dragTarget = true,
            data = { slot = index, key = key, baseMargin = buttonMargin },

            create = function(element)
                if element:HasClass("justDropped") then
                    element:ScheduleEvent("settleDrop", 0.05)
                end
            end,
            settleDrop = function(element)
                element:SetClass("justDropped", false)
            end,

            gui.Panel{
                classes = {"iconRailIcon"},
                bgimage = buttonIcon,
                width = 20,
                height = 20,
                halign = "center",
                valign = "center",
                cornerRadius = cond(charid ~= nil, 10, 0),
                create = function(element)
                    --portraits are full-colour art: opt them out of the
                    --icon tinting, and crop them square.
                    if buttonIconTint ~= nil then
                        element.selfStyle.bgcolor = buttonIconTint
                    end
                    if buttonIconRect ~= nil then
                        element.selfStyle.imageRect = buttonIconRect
                    end
                end,
            },

            --the active underline (chromeless buttons: the open state is
            --a full-white icon plus this small bar, not a box).
            gui.Panel{
                classes = {"iconRailActiveMark"},
                bgimage = true,
                width = 16,
                height = 2,
                halign = "center",
                valign = "bottom",
                y = -3,
                interactable = false,
            },

            gui.Label{
                classes = {"iconRailLabel"},
                floating = true,
                --see the tray label: rail windows left open sit over the rail,
                --so without this the hover label drew behind them.
                renderOnTop = true,
                x = labelArgs.x,
                halign = labelArgs.halign,
                valign = "center",
                interactable = false,
                bgimage = true,
                text = string.upper(panelName),
                width = "auto",
                height = "auto",
                hpad = 8,
                vpad = 4,
                borderBox = true,
                textWrap = false,
            },

            --drag a button to rearrange: drop position decides which rail
            --it lands on (screen half) and which slot. While dragging, a
            --placeholder box marks the landing slot and occupied buttons
            --below shift down live to open the gap. Empty slots stay
            --empty (blank spots are part of the layout); dropping onto an
            --occupied slot bumps the occupant down.
            draggable = true,
            dragging = function(element)
                local targetSide, targetSlot = RailDropTarget(side, index, element)
                ShowRailGhost(targetSide, targetSlot, key)
            end,
            drag = function(element)
                g_railDragTime = dmhub.Time()
                HideRailGhost()

                local targetSide, targetSlot = RailDropTarget(side, index, element)
                if targetSide == side and targetSlot == index then
                    --Landed on the slot it started from, so nothing was
                    --rearranged -- the user meant to CLICK this button.
                    --That is the common case, not an edge case: the
                    --engine turns a press with even one or two pixels of
                    --motion into a drag and never delivers the click, so
                    --without this an ordinary slightly-imprecise click on
                    --a rail icon did nothing at all.
                    element:FireEvent("activateRailButton")
                    RebuildIconRails()
                    return
                end

                local sides, inert = RailLayout()

                local dragged = nil
                for _, sideList in pairs(sides) do
                    for j, e in ipairs(sideList) do
                        if e.key == key then
                            dragged = table.remove(sideList, j)
                            break
                        end
                    end
                end
                if dragged == nil then
                    return
                end

                dragged.slot = targetSlot
                local targetList = sides[targetSide]
                table.insert(targetList, dragged)

                --Dense insert: the dragged button takes the contested slot and
                --everything renumbers contiguously, so it lands just before
                --whatever held that slot and the list stays packed -- no hole
                --where it came from, nothing bumped into a blank spot. The
                --dragged button wins the tie so it sorts into its target slot.
                table.sort(targetList, function(a, b)
                    if a.slot == b.slot then
                        return a == dragged
                    end
                    return a.slot < b.slot
                end)
                for i, e in ipairs(targetList) do
                    e.slot = i - 1
                end

                --A cross-rail move leaves a gap in the SOURCE rail's numbering
                --(the dragged entry was pulled out mid-list); repack it too so
                --both rails stay dense immediately, not just after the next
                --RailLayout read.
                for sn, sideList in pairs(sides) do
                    if sn ~= targetSide then
                        table.sort(sideList, function(a, b) return a.slot < b.slot end)
                        for i, e in ipairs(sideList) do
                            e.slot = i - 1
                        end
                    end
                end

                g_railJustDropped = key
                SaveRailLayout(sides, inert)
                RebuildIconRails()
            end,

            --Open/close this button's window. Fired by the click handler
            --AND by a drag that ended where it began -- see the drag
            --handler for why that is the same gesture.
            activateRailButton = function(element)
                --document shortcut: open the doc in the journal viewer.
                if docid ~= nil then
                    local docs = dmhub.GetTable(CustomDocument.tableName) or {}
                    local d = docs[docid]
                    if d ~= nil then
                        d:ShowDocument()
                    end
                    RefreshRails()
                    return
                end

                local doc = RailPanelDocument(key)
                if doc == nil then
                    return
                end

                if doc:PresentDocumentOpen() then
                    --clicking the icon of an open window closes it,
                    --pinned or not.
                    local pins = IconRailPins()
                    if pins[key] ~= nil then
                        pins[key] = nil
                        SetIconRailPins(pins)
                    end
                    doc:ClosePanel()
                    if g_railTransientKey == key then
                        g_railTransientKey = nil
                    end
                elseif PanelDocument.FindHostDialog(key) ~= nil then
                    --the panel lives as a tab in another window: raise
                    --that window and switch to the tab.
                    local host = PanelDocument.FindHostDialog(key)
                    host:SetAsLastSibling()
                    host:FireEventTree("activatePanelTab", key)
                else
                    --one transient window at a time: opening a panel
                    --closes the previous un-pinned one.
                    if g_railTransientKey ~= nil and g_railTransientKey ~= key then
                        local prev = RailPanelDocument(g_railTransientKey)
                        if prev ~= nil then
                            prev:ClosePanel()
                        end
                    end
                    g_railTransientKey = key

                    local anchorX, anchorY = RailAnchor(side, index)
                    OpenIconRailWindow(key, {
                        x = anchorX,
                        y = anchorY,
                    })
                end

                RefreshRails()
            end,

            click = function(element)
                --the release at the end of a rearrange drag can also
                --deliver a click; ignore it.
                if g_railDragTime ~= nil and dmhub.Time() - g_railDragTime < 0.3 then
                    return
                end

                element:FireEvent("activateRailButton")
            end,

            --right-click: context menu with the non-drag equivalents of
            --every rail gesture (Views brief A9a) plus the pinned-open
            --act that used to BE the bare right-click.
            rightClick = function(element)
                if g_railDragTime ~= nil and dmhub.Time() - g_railDragTime < 0.3 then
                    return
                end

                --shortcuts (documents, characters) get the reduced menu:
                --open + moves. They are not part of the curated panel
                --set, so "open pinned" has nothing to pin against.
                if docid ~= nil or charid ~= nil then
                    element.popup = gui.ContextMenu{
                        entries = {
                            {
                                text = "Open",
                                click = function()
                                    element.popup = nil
                                    element:FireEvent("click")
                                end,
                            },
                            {
                                text = "Move up",
                                click = function()
                                    element.popup = nil
                                    RailMovePanel(key, "up")
                                end,
                            },
                            {
                                text = "Move down",
                                click = function()
                                    element.popup = nil
                                    RailMovePanel(key, "down")
                                end,
                            },
                            {
                                text = "Move to other side",
                                click = function()
                                    element.popup = nil
                                    RailMovePanel(key, "side")
                                end,
                            },
                            {
                                text = "Remove from rail",
                                click = function()
                                    element.popup = nil
                                    RailMovePanel(key, "remove")
                                end,
                            },
                        },
                    }
                    return
                end

                local function openPinned()
                    local doc = RailPanelDocument(key)
                    if doc == nil then
                        return
                    end
                    if doc:PresentDocumentOpen() then
                        local pins = IconRailPins()
                        if pins[key] == nil then
                            local d = doc:try_get("_tmp_dialog")
                            if d ~= nil and d.valid then
                                pins[key] = { x = d.x, y = d.y, tabs = d.data.panelTabs }
                                SetIconRailPins(pins)
                                if g_railTransientKey == key then
                                    g_railTransientKey = nil
                                end
                            end
                        end
                    elseif PanelDocument.FindHostDialog(key) ~= nil then
                        local host = PanelDocument.FindHostDialog(key)
                        host:SetAsLastSibling()
                        host:FireEventTree("activatePanelTab", key)
                    else
                        local anchorX, anchorY = RailAnchor(side, index)
                        local pins = IconRailPins()
                        pins[key] = { x = anchorX, y = anchorY }
                        SetIconRailPins(pins)
                        OpenIconRailWindow(key, {
                            x = anchorX,
                            y = anchorY,
                        })
                    end
                    RefreshRails()
                end

                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Open",
                            click = function()
                                element.popup = nil
                                element:FireEvent("click")
                            end,
                        },
                        {
                            text = "Open pinned",
                            click = function()
                                element.popup = nil
                                openPinned()
                            end,
                        },
                        {
                            text = "Move up",
                            click = function()
                                element.popup = nil
                                RailMovePanel(key, "up")
                            end,
                        },
                        {
                            text = "Move down",
                            click = function()
                                element.popup = nil
                                RailMovePanel(key, "down")
                            end,
                        },
                        {
                            text = "Move to other side",
                            click = function()
                                element.popup = nil
                                RailMovePanel(key, "side")
                            end,
                        },
                        {
                            text = "Remove from rail",
                            click = function()
                                element.popup = nil
                                RailMovePanel(key, "remove")
                            end,
                        },
                    },
                }
            end,

            refreshRail = function(element)
                if docid ~= nil then
                    --a document shortcut is lit while its doc is open as
                    --a tab in the journal viewer.
                    local lit = false
                    if g_tabbedViewer ~= nil and g_tabbedViewer.valid then
                        for _, tab in ipairs(g_tabbedViewer.data.tabs or {}) do
                            if tab.docId == docid then
                                lit = true
                            end
                        end
                    end
                    element:SetClass("active", lit)
                    return
                end
                --lit while the panel is visible anywhere: its own
                --window or a tab in another window.
                element:SetClass("active", PanelDocument.IsPanelShown(key))
            end,
        }
    end

    return gui.Panel{
        classes = {"iconRail"},
        halign = side,
        valign = "top",
        lmargin = cond(side == "left", ICON_RAIL_LEFT, 0),
        rmargin = cond(side == "right", ICON_RAIL_LEFT, 0),
        tmargin = ICON_RAIL_TOP,
        width = ICON_RAIL_BUTTON,
        height = "auto",
        flow = "vertical",
        --journal documents dropped on the rail background append to the
        --end of this side. The near-invisible surface gives the root a
        --hit area so drops between/around buttons resolve, not just
        --drops exactly on a button (field-tested: the bare container
        --never resolved as a drag target).
        dragTarget = true,
        bgimage = true,
        bgcolor = "#00000001",

        data = {
            side = side,
        },

        --each rail and its own side's dock are mutually exclusive: while
        --this side's dock is on screen the whole rail collapses (the
        --dock-mounted tray button is the way back); the other side is
        --unaffected. Children collapse individually rather than the rail
        --root so the root's think keeps running to un-collapse later.
        --The map's drawable area must be recalculated when dock
        --visibility changes: the dock handles used to do this from their
        --monitor events, but the rail collapses those handles and
        --collapsed panels don't process events -- without this call the
        --map stays squeezed as if the docks were still on screen.
        syncDockMode = function(element)
            local dockVisible = not dmhub.GetSettingValue(side .. "dockoffscreen")
            if element.data.lastDockVisible ~= dockVisible then
                element.data.lastDockVisible = dockVisible
                dmhub.UpdateScreenHudArea(1)
            end
            for _, child in ipairs(element.children) do
                if child.valid then
                    child:SetClass("collapsed", dockVisible)
                end
            end
        end,

        create = function(element)
            element:FireEvent("syncDockMode")
        end,

        --self-heal: track windows closed by any path and keep the active
        --states honest. Panels survive a Lua reload while their module
        --state does not, so a rail from an unloaded generation destroys
        --itself rather than running stale closures.
        thinkTime = 0.5,
        think = function(element)
            if mod.unloaded then
                element:DestroySelf()
                return
            end
            if g_railTransientKey ~= nil then
                local doc = RailPanelDocument(g_railTransientKey)
                if doc == nil or not doc:PresentDocumentOpen() then
                    g_railTransientKey = nil
                end
            end
            element:FireEventTree("refreshRail")
            --docks may have been toggled from the Panels menu, and docks
            --rebuild their children on layout changes; keep the rail's
            --collapsed state, the hidden dock handles, and the
            --dock-mounted tray buttons all in step.
            element:FireEvent("syncDockMode")
            if side == "left" then
                SyncDockHandles()
                EnsureDockTrayButtons()
            end
            --NOTE: the dock is only mirrored from the rail ONCE, when the
            --tray opens it. No continuous enforcement here: a running
            --sync fought the user's own dock management (closing a
            --rail-layout panel in the dock snapped it back open within
            --half a second; earlier it also destroyed panels opened via
            --the Panels menu). The dock is free-form while open;
            --re-toggling the tray re-syncs it to the rail.
        end,

        --Rail styling: shared with the dock-mounted tray button, see
        --IconRailStyles.
        styles = IconRailStyles(),

        children = buttons,
    }
end

local function BuildIconRails()
    local layer = DocumentsLayer()
    if layer == nil then
        return
    end
    local sides = RailLayout()
    for _, side in ipairs({"left", "right"}) do
        local rail = CreateIconRail(side, sides[side])
        g_iconRails[side] = rail
        layer:AddChild(rail)
    end
end

local function DestroyIconRails()
    --any drag-gap shift dies with the buttons that carried it.
    g_railShifted = {}
    g_railShiftSig = nil
    for side, rail in pairs(g_iconRails) do
        if rail ~= nil and rail.valid then
            rail:DestroySelf()
        end
        g_iconRails[side] = nil
    end
    if g_railDragGhost ~= nil and g_railDragGhost.valid then
        g_railDragGhost:DestroySelf()
    end
    g_railDragGhost = nil
end

--Tear down and rebuild both rails from the saved layout (after a button
--drag rearranges them). Open windows are untouched.
RebuildIconRails = function()
    DestroyIconRails()
    if dmhub.GetSettingValue("iconrail") and devmode() and DocumentsLayer() ~= nil then
        BuildIconRails()
    end
end

--Create or destroy the rails to match the setting; restore pinned windows
--when they come up. Safe to call any time.
function EnsureIconRail()
    --DEV-GATED trial: the rail (and everything riding it -- Views, doc
    --shortcuts, dock handoff) only activates in devmode, so shipping
    --this code exposes nothing to users until we deliberately open it.
    local enabled = dmhub.GetSettingValue("iconrail") == true and devmode()

    if not enabled then
        DestroyIconRails()
        --restore the docks' own handles and remove the dock-mounted
        --tray buttons.
        SyncDockHandles()
        EnsureDockTrayButtons()
        dmhub.UpdateScreenHudArea(1)
        return
    end

    local existing = g_iconRails.left
    if existing ~= nil and existing.valid then
        return
    end

    local layer = DocumentsLayer()
    if layer == nil then
        return
    end

    --sweep rails (and dock tray buttons) left behind by a previous
    --module generation: panels outlive a Lua reload, and a stale rail's
    --closures reference dead module state (it renders identically,
    --stacked under the new one, and its clicks open windows the new
    --generation cannot see).
    for _, child in ipairs(layer.children) do
        if child.valid and (child:HasClass("iconRail") or child:HasClass("iconRailGhost") or child:HasClass("iconRailViewChip") or child:HasClass("iconRailViewToast")) then
            child:DestroySelf()
        end
    end
    if gamehud ~= nil and rawget(gamehud, "leftDock") ~= nil then
        for _, dock in ipairs({gamehud.leftDock, gamehud.rightDock}) do
            if dock ~= nil and dock.valid then
                for _, child in ipairs(dock.children) do
                    if child.valid and child:HasClass("iconRailDockButton") then
                        child:DestroySelf()
                    end
                end
            end
        end
    end

    --Panel windows from a previous generation are orphans for the same
    --reason: no PanelDocument in THIS generation points at them, so
    --restoring pins below would open a second copy of each beside them.
    --Windows this generation knows about are left alone.
    local knownDialogs = {}
    for _, doc in pairs(g_panelDocuments) do
        local d = doc:try_get("_tmp_dialog")
        if d ~= nil and d.valid then
            knownDialogs[d] = true
        end
    end
    for _, child in ipairs(layer.children) do
        if child.valid and not knownDialogs[child] then
            local tabs = nil
            pcall(function() tabs = child.data.panelTabs end)
            if tabs ~= nil then
                child:DestroySelf()
            end
        end
    end

    BuildIconRails()
    SyncDockHandles()
    EnsureDockTrayButtons()
    --recalculate the map's drawable area (see syncDockMode): fixes a
    --stale squeeze left from before the rail owned this.
    dmhub.UpdateScreenHudArea(1)

    for key, p in pairs(IconRailPins()) do
        OpenIconRailWindow(key, { x = p.x, y = p.y, tabs = p.tabs })
    end
end

--A Lua reload starts a fresh module generation: the previous one's rails
--destroy themselves (their think sees mod.unloaded) and nothing rebuilds
--them, because EnterGame -- the only other builder -- does not fire
--again on reload. The rails would simply vanish for the rest of the
--session. Rebuild shortly after load; EnsureIconRail no-ops when the
--rails already exist or the hud is not up yet (title screen, first
--launch), so this is only ever the reload path.
--Rebuild the rails after a Lua reload. EnterGame does not fire again, and
--a reload takes the existing rail panels with it, so without this the
--rails stay gone for the rest of the session. Event REGISTRATIONS made at
--file scope are reliable (unlike deferred callbacks -- dmhub.Schedule and
--dmhub.Coroutine at file scope run only sometimes, which made earlier
--attempts here work intermittently), and refreshTables fires as the
--tables come back up after a reload. EnsureIconRail no-ops when the rails
--already exist or the hud is not up, so this is cheap on every other fire.
--Rebuild the rails after a Lua reload: a reload takes the existing rail
--panels with it and EnterGame -- the only other builder -- does not fire
--again, so without this the rails stay gone for the rest of the session.
--Polls rather than firing once, because the hud is down for a while
--after a reload (that is exactly when GameHud.instance is `false`).
--Gives up after a few seconds so loading with no game running costs
--nothing; EnterGame builds the rails for a real game entry.
dmhub.Coroutine(function()
    for i = 1, 60 do
        if mod.unloaded then
            return
        end
        if DocumentsLayer() ~= nil then
            EnsureIconRail()
            return
        end
        coroutine.yield(0.1)
    end
end)

dmhub.RegisterEventHandler("EnterGame", function()
    if mod.unloaded then
        return
    end

    dmhub.Coroutine(function()
        while DocumentsLayer() == nil do
            coroutine.yield()
        end

        for i = 1, 5 do
            coroutine.yield()
        end

        if mod.unloaded then
            return
        end

        EnsureIconRail()

        --Players get the Player built-in view applied on first entry
        --(Lisa+David review 2026-07-19: switching views is an advanced
        --feature, so the default is chosen for them; the Director's
        --default stays Custom). Only when the rail mode is on, no view
        --is active, and there is no evidence they have ever used views
        --(an empty per-game stash is the proxy) -- so it applies once,
        --and never tramples an arrangement they've built.
        if (not dmhub.isDM) and devmode() and dmhub.GetSettingValue("iconrail") == true and (dmhub.GetSettingValue("viewsactive") or "") == "" then
            local stash = dmhub.GetSettingValue("viewsstash")
            local stashEmpty = true
            if type(stash) == "table" then
                for _ in pairs(stash) do
                    stashEmpty = false
                    break
                end
            end
            if stashEmpty and rawget(_G, "ViewsSwitchTo") ~= nil then
                ViewsSwitchTo("builtin:player")
            end
        end
    end)
end)

----------------------------------------------------------------------
-- Workspace Views
-- ---------------
-- Named saved workspace arrangements (rail sides/slots/blanks, pinned
-- windows with tabs, dock contents and visibility), switchable from a
-- chip on the left rail and the Panels menu. Built-ins: Map Maker /
-- Director / Player (code templates; a user's Save on a built-in stores
-- a personal overlay). Design brief (LOCKED 2026-07-19):
-- principlesnstuff/views-brief.md. Key semantics:
--  - Switching is NON-destructive (A1): the outgoing view's live
--    arrangement stashes per-game under its id; switching back restores
--    it. The saved definition only applies when no stash exists, or via
--    the explicit Reset to saved.
--  - Unavailable panels filter at render, never at save (A3).
--  - Apply diffs live windows rather than rebuilding them (A4).
--  - The no-view state is "Custom" (A5): active id "", stash key
--    "custom"; nothing is applied until the user's first explicit act.
----------------------------------------------------------------------

--Personal view library, follows the user across games and machines:
--{ [viewid] = { name=, layout=, seededFrom=?, registry=?, savedAt=? } }.
--Built-in overlays use the built-in's id ("builtin:director"); customs
--use "view:<guid>".
setting{
    id = "viewslibrary",
    storage = "account",
    default = {},
}

--The active view id in this game ("" = the Custom/no-view state).
setting{
    id = "viewsactive",
    storage = "pergamepreference",
    default = "",
}

--Per-game working-state stashes, keyed by view id (or "custom"):
--{ [key] = layoutPayload }. Written on every switch (A1).
setting{
    id = "viewsstash",
    storage = "pergamepreference",
    default = {},
}

--Built-in templates (Views brief D4: no pins, docks closed, both rails).
--Editable freely: these are the stock arrangements, iterated in-app.
local g_viewBuiltins = {
    {
        id = "builtin:mapmaker",
        name = "Map Maker",
        dmonly = true,
        layout = {
            rail = {
                ["terrain editor"] = { side = "left", slot = 0 },
                ["objects"] = { side = "left", slot = 1 },
                ["building editor"] = { side = "left", slot = 2 },
                ["effects editor"] = { side = "left", slot = 3 },
                ["elevation editor"] = { side = "left", slot = 4 },
                ["floors & layers"] = { side = "left", slot = 5 },
                ["map settings"] = { side = "right", slot = 0 },
                ["editor settings"] = { side = "right", slot = 1 },
                ["time of day/lighting"] = { side = "right", slot = 2 },
                ["weather"] = { side = "right", slot = 3 },
                ["clipboard"] = { side = "right", slot = 4 },
            },
            pins = {},
            docks = { left = {}, right = {} },
            leftDockOff = true,
            rightDockOff = true,
        },
    },
    {
        id = "builtin:director",
        name = "Director",
        dmonly = true,
        layout = {
            rail = {
                ["run"] = { side = "left", slot = 0 },
                ["journal"] = { side = "left", slot = 1 },
                ["campaign tracker"] = { side = "left", slot = 2 },
                ["encounter creator"] = { side = "left", slot = 3 },
                ["bestiary"] = { side = "left", slot = 4 },
                ["heroes"] = { side = "left", slot = 5 },
                ["action log"] = { side = "right", slot = 0 },
                ["dice"] = { side = "right", slot = 1 },
                ["triggers"] = { side = "right", slot = 2 },
                ["audio"] = { side = "right", slot = 3 },
                ["game controls"] = { side = "right", slot = 4 },
                ["safety tools"] = { side = "right", slot = 5 },
            },
            pins = {},
            docks = { left = {}, right = {} },
            leftDockOff = true,
            rightDockOff = true,
        },
    },
    {
        id = "builtin:player",
        name = "Player",
        dmonly = false,
        layout = {
            rail = {
                ["character"] = { side = "left", slot = 0 },
                ["heroes"] = { side = "left", slot = 1 },
                ["dice"] = { side = "left", slot = 2 },
                ["action log"] = { side = "left", slot = 3 },
                ["journal"] = { side = "left", slot = 4 },
                ["campaign tracker"] = { side = "right", slot = 0 },
                ["downtime projects"] = { side = "right", slot = 1 },
                ["triggers"] = { side = "right", slot = 2 },
                ["audio"] = { side = "right", slot = 3 },
                ["safety tools"] = { side = "right", slot = 4 },
            },
            pins = {},
            docks = { left = {}, right = {} },
            leftDockOff = true,
            rightDockOff = true,
        },
    },
}

local function ViewsDeepEqual(a, b)
    if a == b then
        return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for k, v in pairs(a) do
        if not ViewsDeepEqual(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function ViewsLibrary()
    local lib = dmhub.GetSettingValue("viewslibrary")
    if type(lib) ~= "table" then
        return {}
    end
    return lib
end

--The active view id, or nil for the Custom (no-view) state.
function ViewsActiveId()
    local v = dmhub.GetSettingValue("viewsactive")
    if v == nil or v == "" then
        return nil
    end
    return v
end

local function ViewsBuiltinTemplate(id)
    for _, b in ipairs(g_viewBuiltins) do
        if b.id == id then
            return b
        end
    end
    return nil
end

--The resolved definition of a view: a library entry (custom view, or a
--personal overlay of a built-in -- A2) beats the built-in template.
--Returns { name, layout, builtin?, seededFrom?, registry? } or nil.
function ViewsGetDefinition(id)
    local lib = ViewsLibrary()
    local entry = lib[id]
    local template = ViewsBuiltinTemplate(id)
    if entry ~= nil then
        return {
            name = (template ~= nil and template.name) or entry.name or id,
            layout = entry.layout,
            builtin = template ~= nil,
            overlaid = template ~= nil,
            seededFrom = entry.seededFrom,
            registry = entry.registry,
        }
    end
    if template ~= nil then
        return { name = template.name, layout = template.layout, builtin = true }
    end
    return nil
end

--All views this user can see here, in display order: built-ins (role
--gated, D6) then customs by name.
function ViewsListForUser()
    local result = {}
    for _, b in ipairs(g_viewBuiltins) do
        if (not b.dmonly) or dmhub.isDM then
            result[#result + 1] = { id = b.id, name = b.name, builtin = true }
        end
    end
    local customs = {}
    for id, entry in pairs(ViewsLibrary()) do
        if ViewsBuiltinTemplate(id) == nil and type(entry) == "table" then
            customs[#customs + 1] = { id = id, name = entry.name or id, builtin = false }
        end
    end
    table.sort(customs, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    for _, c in ipairs(customs) do
        result[#result + 1] = c
    end
    return result
end

--Snapshot of the current working layout (the capture side of a view).
function ViewsCaptureLayout()
    return {
        rail = DeepCopy(dmhub.GetSettingValue("iconraillayout") or {}),
        pins = DeepCopy(dmhub.GetSettingValue("iconrailpins") or {}),
        docks = {
            left = DockablePanel.GetDockPanels("left"),
            right = DockablePanel.GetDockPanels("right"),
        },
        leftDockOff = dmhub.GetSettingValue("leftdockoffscreen") == true,
        rightDockOff = dmhub.GetSettingValue("rightdockoffscreen") == true,
    }
end

--The current list of registered panel names (for A8 registry stamps).
local function ViewsRegistrySnapshot()
    local names = {}
    for _, item in ipairs(DockablePanel.GetMenuItems(true)) do
        if item.text ~= nil then
            names[#names + 1] = string.lower(item.text)
        end
    end
    table.sort(names)
    return names
end

--Why a layout entry can't render here, or nil if it can. Returns
--{name, reason} -- reasons: "Director only", "dev only", "deleted",
--"not in this game". Used for the A3 skip notices, which name the
--skipped panels rather than just counting them.
function ViewsEntryUnavailable(key)
    local docid = string.match(key, "^doc:(.+)$")
    if docid ~= nil then
        local docs = dmhub.GetTable(CustomDocument.tableName) or {}
        local d = docs[docid]
        if d ~= nil and not d.hidden then
            return nil
        end
        if d ~= nil then
            return { name = d.description or "a journal document", reason = "deleted" }
        end
        return { name = "a journal document", reason = "not in this game" }
    end
    local charid = string.match(key, "^character:(.+)$")
    if charid ~= nil then
        local token = dmhub.GetCharacterById(charid)
        if token ~= nil then
            return nil
        end
        return { name = "a character", reason = "not in this game" }
    end
    if PanelDocument.Get(key) ~= nil then
        return nil
    end
    local reg = DockablePanel.GetRegistration(key)
    if reg == nil then
        return { name = key, reason = "not in this game" }
    end
    if reg.dmonly and not dmhub.isDM then
        return { name = reg.name, reason = "Director only" }
    end
    if reg.devonly then
        return { name = reg.name, reason = "dev only" }
    end
    return { name = reg.name, reason = "unavailable" }
end

--Everything in a view's saved layout that can't render here, deduped:
--list of {name, reason}. Used by apply notices and the Manage dialog.
function ViewsUnavailableForLayout(layout)
    layout = layout or {}
    local result = {}
    local seen = {}
    local function check(key)
        local info = ViewsEntryUnavailable(key)
        if info ~= nil and not seen[info.name] then
            seen[info.name] = true
            result[#result + 1] = info
        end
    end
    for key in pairs(layout.rail or {}) do
        check(key)
    end
    for key in pairs(layout.pins or {}) do
        check(key)
    end
    local docks = layout.docks or {}
    for _, side in ipairs({"left", "right"}) do
        for _, name in ipairs(docks[side] or {}) do
            check(string.lower(name))
        end
    end
    return result
end

--Apply a layout payload to the live workspace. Diff-based (A4): open
--windows shared between the outgoing and incoming arrangements keep
--their live instances and are repositioned; dock panel instances are
--reused by SetDockPanels. Pins clamp to the current screen (A7).
--Returns the list of skipped-as-unavailable entries ({name, reason};
--A3).
function ViewsApplyLayout(layout)
    layout = layout or {}
    local skipped = ViewsUnavailableForLayout(layout)

    --rail layout: store verbatim (unavailable entries stay inert -- A3;
    --RailLayout filters at render).
    local rail = DeepCopy(layout.rail or {})
    dmhub.SetSettingValue("iconraillayout", rail)

    --pins: clamp to this screen (A7).
    local pins = DeepCopy(layout.pins or {})
    local uiW = IconRailUIWidth()
    for key, p in pairs(pins) do
        if type(p) == "table" then
            if type(p.x) == "number" then
                p.x = math.max(8, math.min(p.x, uiW - PanelDocument.DefaultWidth - 8))
            end
            if type(p.y) == "number" then
                p.y = math.max(40, math.min(p.y, 1000 - PanelDocument.DefaultHeight / 8))
            end
        end
    end
    dmhub.SetSettingValue("iconrailpins", pins)

    --windows: close what the incoming layout doesn't pin; reposition
    --survivors in place (A4); open what's newly pinned.
    g_railTransientKey = nil
    for key, doc in pairs(g_panelDocuments) do
        local dlg = doc:try_get("_tmp_dialog")
        if dlg ~= nil and dlg.valid then
            local pin = pins[key]
            if pin == nil then
                doc:ClosePanel()
            else
                dlg.x = pin.x or dlg.x
                dlg.y = pin.y or dlg.y
                if pin.tabs ~= nil then
                    for _, k in ipairs(pin.tabs) do
                        dlg:FireEventTree("addPanelTab", k)
                    end
                end
            end
        end
    end
    for key, pin in pairs(pins) do
        if type(pin) == "table" then
            local doc = RailPanelDocument(key)
            if doc ~= nil and not doc:PresentDocumentOpen() then
                OpenIconRailWindow(key, { x = pin.x, y = pin.y, tabs = pin.tabs })
            end
        end
    end

    --docks: contents filtered to available panels at apply time (the
    --stored view keeps the full list -- A3), then visibility.
    local docks = layout.docks or {}
    for _, side in ipairs({"left", "right"}) do
        local names = {}
        for _, name in ipairs(docks[side] or {}) do
            if PanelDocument.Get(name) ~= nil then
                names[#names + 1] = name
            end
        end
        DockablePanel.SetDockPanels(side, names)
    end
    dmhub.SetSettingValue("leftdockoffscreen", layout.leftDockOff ~= false)
    dmhub.SetSettingValue("rightdockoffscreen", layout.rightDockOff ~= false)

    RebuildIconRails()
    return skipped
end

--Switch to a view (id), or to the Custom no-view state (id nil). The
--outgoing arrangement stashes under its key; the incoming view restores
--its stash, falling back to its saved definition (A1). Returns skipped
--panel count, or nil if the switch did not happen.
function ViewsSwitchTo(id)
    local currentKey = ViewsActiveId() or "custom"
    local targetKey = id or "custom"
    if currentKey == targetKey then
        return {}
    end

    local incomingLayout = nil
    local stash = DeepCopy(dmhub.GetSettingValue("viewsstash") or {})
    if id ~= nil then
        local def = ViewsGetDefinition(id)
        if def == nil then
            return nil
        end
        incomingLayout = stash[targetKey] or def.layout
    else
        --Custom: restore the stashed pre-view arrangement; with no stash
        --there is nothing to restore -- keep the current arrangement.
        incomingLayout = stash[targetKey]
    end

    stash[currentKey] = ViewsCaptureLayout()
    dmhub.SetSettingValue("viewsstash", stash)
    dmhub.SetSettingValue("viewsactive", id or "")

    if incomingLayout == nil then
        return {}
    end
    return ViewsApplyLayout(DeepCopy(incomingLayout))
end

--Save the working layout into the active view: a custom view updates in
--place; a built-in takes a personal overlay (A2). Keeps the previous
--snapshot for one-step undo (A9d). No-op in the Custom state (Save-as
--is the verb there -- A5).
function ViewsSave()
    local id = ViewsActiveId()
    if id == nil then
        return false
    end
    local lib = DeepCopy(ViewsLibrary())
    local template = ViewsBuiltinTemplate(id)
    local entry = lib[id]
    if entry == nil then
        entry = { name = (template ~= nil and template.name) or id }
    end
    entry.previous = entry.layout
    entry.layout = ViewsCaptureLayout()
    entry.registry = ViewsRegistrySnapshot()
    lib[id] = entry
    dmhub.SetSettingValue("viewslibrary", lib)
    return true
end

--Undo the last Save/Reset on the active view (A9d).
function ViewsUndoSave()
    local id = ViewsActiveId()
    if id == nil then
        return false
    end
    local lib = DeepCopy(ViewsLibrary())
    local entry = lib[id]
    if entry == nil or entry.previous == nil then
        return false
    end
    entry.layout, entry.previous = entry.previous, entry.layout
    lib[id] = entry
    dmhub.SetSettingValue("viewslibrary", lib)
    return true
end

--Save the working layout as a new custom view and make it active.
function ViewsSaveAs(name)
    local id = "view:" .. dmhub.GenerateGuid()
    local lib = DeepCopy(ViewsLibrary())
    lib[id] = {
        name = name,
        layout = ViewsCaptureLayout(),
        seededFrom = ViewsActiveId(),
        registry = ViewsRegistrySnapshot(),
    }
    dmhub.SetSettingValue("viewslibrary", lib)
    dmhub.SetSettingValue("viewsactive", id)
    return id
end

--Re-apply the active view's saved definition, discarding working drift
--(the explicit act that replaced the switch confirm -- A1).
function ViewsResetToSaved()
    local id = ViewsActiveId()
    if id == nil then
        return nil
    end
    local def = ViewsGetDefinition(id)
    if def == nil then
        return nil
    end
    return ViewsApplyLayout(DeepCopy(def.layout))
end

--Clear a built-in's personal overlay (Manage: "Reset to stock" -- A2).
function ViewsResetToStock(id)
    if ViewsBuiltinTemplate(id) == nil then
        return false
    end
    local lib = DeepCopy(ViewsLibrary())
    if lib[id] == nil then
        return false
    end
    lib[id] = nil
    dmhub.SetSettingValue("viewslibrary", lib)
    if ViewsActiveId() == id then
        ViewsApplyLayout(DeepCopy(ViewsBuiltinTemplate(id).layout))
    end
    return true
end

--Whether the working layout differs from the active view's saved
--definition (the chip dot + drift text; suppressed in Custom -- A5).
function ViewsIsDrifted()
    local id = ViewsActiveId()
    if id == nil then
        return false
    end
    local def = ViewsGetDefinition(id)
    if def == nil then
        return false
    end
    return not ViewsDeepEqual(ViewsCaptureLayout(), def.layout)
end

--Panels registered since the active view was last saved (A8 notice).
function ViewsNewPanelsSinceSaved(id)
    local def = ViewsGetDefinition(id or ViewsActiveId() or "")
    if def == nil or def.registry == nil then
        return {}
    end
    local known = {}
    for _, n in ipairs(def.registry) do
        known[n] = true
    end
    local result = {}
    for _, n in ipairs(ViewsRegistrySnapshot()) do
        if not known[n] then
            local reg = DockablePanel.GetRegistration(n)
            result[#result + 1] = (reg ~= nil and reg.name) or n
        end
    end
    return result
end

----------------------------------------------------------------------
-- Views UI: the save-undo toast (A9d), the save-as naming dialog and
-- the Manage dialog. The rail chip was removed by Lisa+David's review
-- (2026-07-19): the Panels menu (CodexTitleBar.lua) is the only
-- switcher UI, and it drives these globals.
----------------------------------------------------------------------

--transient confirmation with one-step undo (A9d); self-destructs after
--a few seconds. Global: the Panels-menu Views group uses it too.
function ViewsToast(text, undoFn)
    if GameHud.instance == nil or (not GameHud.instance.documentsPanel) or (not GameHud.instance.documentsPanel.valid) then
        return
    end
    local toast
    local children = {
        gui.Label{
            classes = {"iconRailViewChipLabel"},
            text = text,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            textWrap = false,
        },
    }
    if undoFn ~= nil then
        children[#children + 1] = gui.Label{
            classes = {"iconRailViewToastUndo"},
            text = "Undo",
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 10,
            textWrap = false,
            click = function(element)
                undoFn()
                if toast ~= nil and toast.valid then
                    toast:DestroySelf()
                end
            end,
        }
    end
    toast = gui.Panel{
        classes = {"iconRailViewChip", "iconRailViewToast"},
        styles = IconRailStyles(),
        bgimage = true,
        halign = "left",
        valign = "top",
        --where the view chip used to sit, above the left rail.
        x = ICON_RAIL_LEFT,
        y = ICON_RAIL_TOP - 34,
        width = "auto",
        height = 26,
        flow = "horizontal",
        hpad = 9,
        children = children,
    }
    GameHud.instance.documentsPanel:AddChild(toast)
    dmhub.Schedule(5.0, function()
        if toast ~= nil and toast.valid then
            toast:DestroySelf()
        end
    end)
end

--Passive post-apply notices (A3 skipped panels -- named, with reasons
--where they help -- and A8 new-since-saved). Global for the Panels-menu
--switch path.
function ViewsPostApplyNotices(id, skipped)
    local parts = {}
    if type(skipped) == "table" and #skipped > 0 then
        local names = {}
        for i, s in ipairs(skipped) do
            if i <= 4 then
                local n = s.name
                if s.reason == "Director only" or s.reason == "deleted" then
                    n = string.format("%s (%s)", n, s.reason)
                end
                names[#names + 1] = n
            end
        end
        local text = "Unavailable here: " .. table.concat(names, ", ")
        if #skipped > 4 then
            text = text .. string.format(" +%d more", #skipped - 4)
        end
        parts[#parts + 1] = text
    end
    if id ~= nil then
        local newPanels = ViewsNewPanelsSinceSaved(id)
        if #newPanels > 0 then
            parts[#parts + 1] = "New since saved: " .. table.concat(newPanels, ", ")
        end
    end
    if #parts > 0 then
        ViewsToast(table.concat(parts, "  -  "))
    end
end

--Library lifecycle verbs (Manage dialog; D5 -- names and deletion only,
--never arrangement).
function ViewsRename(id, name)
    if ViewsBuiltinTemplate(id) ~= nil or name == nil or name == "" then
        return false
    end
    local lib = DeepCopy(ViewsLibrary())
    if lib[id] == nil then
        return false
    end
    lib[id].name = name
    dmhub.SetSettingValue("viewslibrary", lib)
    return true
end

function ViewsDuplicate(id)
    local def = ViewsGetDefinition(id)
    if def == nil then
        return nil
    end
    local newId = "view:" .. dmhub.GenerateGuid()
    local lib = DeepCopy(ViewsLibrary())
    lib[newId] = {
        name = "Copy of " .. def.name,
        layout = DeepCopy(def.layout),
        seededFrom = id,
        registry = def.registry or ViewsRegistrySnapshot(),
    }
    dmhub.SetSettingValue("viewslibrary", lib)
    return newId
end

function ViewsDelete(id)
    if ViewsBuiltinTemplate(id) ~= nil then
        return false
    end
    local lib = DeepCopy(ViewsLibrary())
    if lib[id] == nil then
        return false
    end
    lib[id] = nil
    dmhub.SetSettingValue("viewslibrary", lib)
    if ViewsActiveId() == id then
        dmhub.SetSettingValue("viewsactive", "")
    end
    return true
end

--Global: opened from the Panels-menu Views group.
ViewsManageDialog = function()
    local lib = ViewsLibrary()
    local rows = {}

    for _, v in ipairs(ViewsListForUser()) do
        local vid = v.id
        local isBuiltin = v.builtin
        local hasOverlay = isBuiltin and lib[vid] ~= nil

        local nameControl
        if isBuiltin then
            nameControl = gui.Label{
                text = v.name .. cond(hasOverlay, " (customized)", ""),
                width = 240,
                height = "auto",
                fontSize = 16,
                halign = "left",
                valign = "center",
            }
        else
            nameControl = gui.Input{
                text = v.name,
                width = 240,
                height = 26,
                halign = "left",
                valign = "center",
                change = function(element)
                    ViewsRename(vid, element.text)
                end,
            }
        end

        local actionButtons = {}
        actionButtons[#actionButtons + 1] = gui.Button{
            classes = {"sizeS"},
            text = "Duplicate",
            halign = "right",
            valign = "center",
            hmargin = 4,
            click = function(element)
                ViewsDuplicate(vid)
                gamehud:CloseModal()
                ViewsManageDialog()
            end,
        }
        if isBuiltin then
            if hasOverlay then
                actionButtons[#actionButtons + 1] = gui.Button{
                    classes = {"sizeS"},
                    text = "Reset to stock",
                    halign = "right",
                    valign = "center",
                    hmargin = 4,
                    click = function(element)
                        ViewsResetToStock(vid)
                        gamehud:CloseModal()
                        ViewsManageDialog()
                    end,
                }
            end
        else
            --two-step delete: first click arms, second confirms. Avoids
            --stacking modals while still guarding the destructive act.
            actionButtons[#actionButtons + 1] = gui.Button{
                classes = {"sizeS"},
                text = "Delete",
                halign = "right",
                valign = "center",
                hmargin = 4,
                data = { armed = false },
                click = function(element)
                    if not element.data.armed then
                        element.data.armed = true
                        element.text = "Confirm delete?"
                        return
                    end
                    ViewsDelete(vid)
                    gamehud:CloseModal()
                    ViewsManageDialog()
                end,
            }
        end

        local rowChildren = { nameControl }
        for _, b in ipairs(actionButtons) do
            rowChildren[#rowChildren + 1] = b
        end
        rows[#rows + 1] = gui.Panel{
            width = "100%",
            height = 38,
            flow = "horizontal",
            children = rowChildren,
        }

        --A3: name what this view can't show here, and why.
        local def = ViewsGetDefinition(vid)
        local unavailable = def ~= nil and ViewsUnavailableForLayout(def.layout) or {}
        if #unavailable > 0 then
            local names = {}
            for _, s in ipairs(unavailable) do
                names[#names + 1] = string.format("%s (%s)", s.name, s.reason)
            end
            rows[#rows + 1] = gui.Label{
                width = "100%",
                height = "auto",
                fontSize = 12,
                color = "#999999",
                bmargin = 6,
                text = "Unavailable here: " .. table.concat(names, ", "),
            }
        end
    end

    --ModalDialog consumes width/height for the dialog frame, leaving the
    --client panel auto-sized; an explicit inner container keeps the rows
    --full width. The rows stack inside an auto-height content panel so
    --the scroll region doesn't distribute them across its height.
    gamehud:ModalDialog{
        title = "Manage Views",
        width = 620,
        height = 500,
        flow = "vertical",
        gui.Panel{
            width = 560,
            height = 320,
            halign = "center",
            valign = "top",
            vscroll = true,
            gui.Panel{
                width = "100%",
                height = "auto",
                valign = "top",
                flow = "vertical",
                vpad = 8,
                children = rows,
            },
        },
    }
end

--Global: opened from the Panels-menu Views group.
function ViewsSaveAsDialog()
    local input = gui.Input{
        text = "",
        placeholderText = "View name",
        width = 300,
        height = 28,
        halign = "center",
        valign = "center",
    }
    gamehud:ModalDialog{
        title = "Save as new view",
        width = 480,
        height = 220,
        flow = "vertical",
        buttons = {
            {
                text = "Save",
                click = function()
                    local name = input.text
                    if name == nil or name == "" then
                        name = "New View"
                    end
                    ViewsSaveAs(name)
                    ViewsToast(string.format("Saved view: %s", name))
                end,
            },
            {
                text = "Cancel",
                escapeActivates = true,
            },
        },
        input,
    }
end

