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
    --book-open-text, NOT quotes: at the tree's 16px the quotes glyph reads
    --as the text "99" rather than quotation marks.
    narration   = { text = "Narration",   icon = "phosphor/book-open-text.png",       beat = true,  glyph = "N", ord = 10 },
    exploration = { text = "Exploration", icon = "phosphor/compass.png",              beat = true,  glyph = "E", ord = 20 },
    combat      = { text = "Combat",      icon = "phosphor/sword.png",                beat = true,  glyph = "C", ord = 30 },
    montage     = { text = "Montage",     icon = "phosphor/film-slate.png",           beat = true,  glyph = "M", ord = 40 },
    --Heroic Test: one skill test prepped as a beat (Draw Steel: Encounters ch.4).
    --dice-six is a PLACEHOLDER icon -- it reads as "a roll" and is confirmed
    --imported; swap it when a distinct glyph is commissioned.
    heroictest  = { text = "Heroic Test", icon = "phosphor/dice-six.png",             beat = true,  glyph = "T", ord = 45 },
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

--Upload this document to the cloud. Returns the freshly-generated updateid
--synchronously; that is NOT a confirmation the write landed. To be notified when
--the async cloud write actually succeeds or fails, pass options.success /
--options.failure -- these are threaded straight through to SetAndUploadTableItem.
--originalDocument stays the first positional arg so all existing callers (which
--pass a delta base or nothing) are unaffected; callers wanting only callbacks
--pass nil as originalDocument: doc:Upload(nil, {success=..., failure=...}).
--@param originalDocument nil|CustomDocument delta base; nil uploads the full item
--@param options nil|{ success: (fun():nil), failure: (fun(message: string): nil) }
function CustomDocument:Upload(originalDocument, options)
    self.updateid = dmhub.GenerateGuid()
    local uploadOptions = {delta = originalDocument ~= nil, deltaFrom = originalDocument}
    if options ~= nil then
        uploadOptions.success = options.success
        uploadOptions.failure = options.failure
    end
    dmhub.SetAndUploadTableItem(self.tableName, self, uploadOptions)
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

--Default creation behaviour for document types that register in the journal's
--"+" palette without supplying their own create dialog (montage, negotiation).
--The caller (Journal.lua) has already assigned id / ownerid / parentFolder, so
--persist the document and open it for editing -- the same thing the tab bar's
--"New Document" path does via onNewDocument. This used to be an empty stub, so
--those types were built in memory and then silently dropped: the menu entry
--appeared and clicking it did nothing at all, with no error to show for it.
--MarkdownDocument overrides this with its own template-picker dialog.
function CustomDocument:ShowCreateDialog()
    self:Upload()
    self:ShowDocument{edit = true}
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
            --arm the shell's periodic autosave (see documentEdited in
            --CreateInterface).
            CustomDocument.NotifyEdited(element)
        end,
        savedoc = function(element)
            self:SetTextContent(element.text)
        end,
        --this editor buffers text in the control rather than writing into the
        --document object, so the shell's DeepEqual fallback cannot see dirty
        --state; answer needsave from the buffer.
        needsave = function(element, result)
            result.responded = true
            if element.text ~= (self:GetTextContent() or "") then
                result.save = true
            end
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

--Editors call this from every change handler to tell the hosting document
--interface (the CreateInterface shell, class "documentPanel") that the user
--edited the document. The shell arms its periodic autosave off this event --
--the same "documentEdited" the seamless markdown editor fires from its edit
--hook. A no-op when the editor is hosted outside the shell (the compendium
--montage editor hosts EditPanel with its own Save button).
function CustomDocument.NotifyEdited(element)
    local host = element:FindParentWithClass("documentPanel")
    if host ~= nil then
        host:FireEvent("documentEdited")
    end
end

local function checkUnsavedChanges(writePanel, resultPanel, doc, onProceed)
    --writePanel is nil until the user first enters edit mode (it is built
    --lazily); no edit panel means nothing unsaved.
    if writePanel == nil or writePanel:HasClass("collapsed") then
        onProceed()
        return
    end
    local needSave = {save = false, responded = false}
    writePanel:FireEventTree("needsave", needSave)
    if not needSave.responded then
        --No editor answered needsave. The form editors (montage, heroic test,
        --negotiation) write into the document object directly from their
        --change handlers rather than buffering, so unsaved work shows up as a
        --divergence from the last saved baseline. pendingOriginal is preferred
        --so a save already in flight (awaiting server confirmation) does not
        --read as unsaved. Editors that DO buffer state outside the document
        --object must answer needsave themselves and set responded = true.
        local baseline = resultPanel.data.pendingOriginal or resultPanel.data.original
        needSave.save = baseline ~= nil and not dmhub.DeepEqual(doc, baseline)
    end
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

--The tabbed viewer owns its whole style cascade while POPPED OUT into a
--native OS window: nothing above it supplies Styles.Default (normally the
--GameHud root) there. In-app the extra copy duplicates rules already
--arriving from the hud root, which is harmless (the compendium popout and
--the character-sheet harness use the same pattern). The rules table is a
--stable local because MergeStyles caches by the table's identity.
local g_viewerPopoutRules = {
    {
        selectors = {"journalTabbedViewer", "poppedOut"},
        priority = 6,
        --popped out, the panel IS the OS window surface: opaque (there is
        --no app surface behind it to blur through) and square (rounded
        --corners would show the companion's black clear color).
        opacity = 1,
        cornerRadius = 0,
    },
}

--In-app the viewer hangs under the hud's documentsPanel, whose style
--block opens with this unconditional selector-less default rule
--(InfoDocument.lua, CreateDocumentsPanel) -- document content leans on
--those defaults (e.g. the markdown toolbar's dropdowns declare no
--valign and sit centered only because of it). Popped out the viewer is
--its own cascade root, so the same rule must ride along, in the same
--cascade position: after Styles.Default, before the theme.
local g_viewerCascadeDefaults = {
    {
        width = "100%",
        height = "100%",
        valign = "center",
        halign = "center",
        bgcolor = "clear",
    },
}

local function TabbedViewerStyles()
    return {
        Styles.Default,
        g_viewerCascadeDefaults,
        ThemeEngine.MergeStyles(g_viewerPopoutRules),
    }
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

    --"Pop out": move the journal into its own native OS window (the
    --companion-app mechanism the compendium and character sheet use).
    --Hidden while popped (the pop-in button takes its place).
    local popoutButton = gui.Button{
        classes = {"sizeXs"},
        icon = "drawsteel/Icons_Nav_MaxWindow.png",
        borderWidth = 0,
        valign = "center",
        --the close-all X to our right pulls itself 4px left (hmargin -4),
        --so leave enough right margin that it lands beside, not on, us.
        lmargin = 4,
        rmargin = 10,
        linger = function(element)
            gui.Tooltip("Pop out into its own window")(element)
        end,
        popout = function(element)
            element:SetClass("collapsed", true)
        end,
        click = function(element)
            local v = element:FindParentWithClass("journalTabbedViewer")
            if v ~= nil then
                v:FireEvent("popoutJournal")
            end
        end,
    }

    --"Pop in": only visible while popped out. Closes the OS window and
    --reopens the same document tabs in-app. The viewer is destroyed and
    --rebuilt through the normal ShowDocument path, so the relaunch must
    --wait a tick for the destroy to land (DestroySelf is end-of-frame).
    local popinButton = gui.Button{
        classes = {"sizeXs", "collapsed"},
        icon = "drawsteel/Icons_Nav_MinWindow.png",
        borderWidth = 0,
        valign = "center",
        lmargin = 4,
        rmargin = 10,
        linger = function(element)
            gui.Tooltip("Return to the app")(element)
        end,
        popout = function(element)
            element:SetClass("collapsed", false)
        end,
        click = function(element)
            local v = element:FindParentWithClass("journalTabbedViewer")
            if v == nil or (not v.data.poppedOut) then
                return
            end

            --capture the open tabs; a tab's doc member goes stale after
            --in-tab navigation, so prefer the live table entry by docId
            --and keep the in-memory doc only as the transient-doc fallback.
            local docsTable = dmhub.GetTable(CustomDocument.tableName) or {}
            local reopen = {}
            local activeDocId = nil
            for _, tab in ipairs(v.data.tabs) do
                local doc = docsTable[tab.docId] or tab.doc
                if doc ~= nil then
                    reopen[#reopen + 1] = doc
                    if tab.tabId == v.data.activeTabId then
                        activeDocId = tab.docId
                    end
                end
            end

            --destroying the popped viewer closes the OS window (the
            --engine sweeps native windows whose panel died).
            v:DestroySelf()
            g_tabbedViewer = nil

            dmhub.Schedule(0.1, function()
                if mod.unloaded then
                    return
                end
                for _, doc in ipairs(reopen) do
                    doc:ShowDocument{skipRefresh = true}
                end
                local nv = g_tabbedViewer
                if nv == nil or (not nv.valid) then
                    return
                end
                local targetTabId = nil
                for _, tab in ipairs(nv.data.tabs) do
                    if targetTabId == nil or tab.docId == activeDocId then
                        targetTabId = tab.tabId
                    end
                end
                if targetTabId ~= nil then
                    nv:FireEvent("switchToTab", targetTabId)
                end
            end)
        end,
    }

    local tabArrowsPanel = gui.Panel {
        width = "auto",
        height = TAB_BAR_HEIGHT,
        halign = "right",
        rmargin = 8,
        flow = "horizontal",
        tabScrollLeft,
        tabScrollRight,
        popoutButton,
        popinButton,
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
        styles = TabbedViewerStyles(),
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
            --while popped out the OS window is what moves; a release of a
            --(suppressed) drag must not teleport the panel inside it.
            if element.data.poppedOut then
                return
            end
            element.x = element.xdrag
            element.y = element.ydrag
            element:SetAsLastSibling()
        end,
        click = function(element)
            --raise above other in-app dialogs; meaningless (and an engine
            --NRE) once the panel is the root of its own OS window.
            if element.data.poppedOut then
                return
            end
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
            poppedOut = false,
        },

        --pop the viewer out into its own native OS window (the
        --companion-app mechanism the compendium and character sheet use).
        popoutJournal = function(element)
            if element.data.poppedOut then
                return
            end

            --unshade first: the move measures the panel's rect to size
            --the OS window, and a shaded window is just the tab strip.
            if element.data.shaded then
                element:FireEvent("toggleShade")
            end

            element.data.poppedOut = true
            --owner-routed modals fired from inside the journal land in
            --this window's own modal layer rather than the main window.
            element.data.nativeWindowRoot = true

            --the poppedOut rule pins opacity 1 / square corners; the
            --theme's framedPanel rules keep painting the background.
            element:SetClass("poppedOut", true)
            element.selfStyle.opacity = 1

            --the OS window owns moving and resizing now; the in-app
            --affordances would fight it. dragMove (not draggable) so the
            --press is still consumed rather than falling through.
            element.dragMove = false
            resizePanel:SetClass("collapsed", true)

            --park far off-screen for the layout passes between here and
            --MoveToNativeWindow: the move measures the panel's rect, so
            --it must lay out in-hierarchy first, but must never be
            --user-visible in the app.
            element.x = -30000

            element:FireEventTree("popout")
            element:ScheduleEvent("popoutToNativeWindow", 0.15)
        end,

        popoutToNativeWindow = function(element)
            if mod.unloaded or (not element.valid) or (not element.data.poppedOut) then
                return
            end
            element:MoveToNativeWindow{
                resizeable = true,
                title = "Journal",
            }
        end,

        --fired by the native-window canvas when the popped-out window is
        --created and whenever the user resizes it (dims arrive in layout
        --units): adopt the window's client size. The viewer's content is
        --all percentages, so it reflows on its own.
        resize = function(element, w, h)
            if not element.data.poppedOut then
                return
            end
            element.x = 0
            element.y = 0
            element.selfStyle.width = w
            element.selfStyle.height = h
        end,

        --window-shade: roll the window up so only the tab strip remains,
        --or roll it back down. Toggled by double-clicking the tab strip.
        toggleShade = function(element)
            --shading would shrink the panel out from under its OS window.
            if element.data.poppedOut then
                return
            end
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
            --UpdateStyle: assigning styles alone never marks the tree
            --style-dirty, so the recolor would wait for an unrelated
            --event. See the panel-window listener for the full note.
            g_tabbedViewer.styles = TabbedViewerStyles()
            g_tabbedViewer:UpdateStyle()
        end
    end)

    return viewer
end

--Resize behavior for this document's standalone window (PresentDocument):
--the options table handed to gui.WindowResizePanel. Subtypes refine it --
--panel windows derive their bounds and axis locks from the dockable
--panel registration.
function CustomDocument:WindowResizeOptions()
    return {
        minWidth = 400,
        minHeight = 300,
    }
end

--The style cascade for a document/panel window: the whole active theme
--plus this window's own chrome rules. A FUNCTION, not a table, because
--GetStyles resolves against the ACTIVE theme and scheme at call time --
--the window re-runs it on a theme switch (see the dialog's create /
--destroy) so a scheme change recolors open windows instead of waiting
--for them to be reopened.
--
--COPY the theme styles before appending: ThemeEngine.GetStyles() returns
--its shared cached table, and appending to it directly injects these
--window-chrome rules (borderless framedPanel, dockingIntoRail shrink)
--into the global theme cascade for every later GetStyles/MergeStyles
--caller -- which is how every framedPanel in the app lost its border.
local function DocumentWindowStyles()
    local dialogStyles = {}
    for _, rule in ipairs(ThemeEngine.GetStyles()) do
        dialogStyles[#dialogStyles + 1] = rule
    end
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
    --while a drag holds the window inside the icon-rail band, the window
    --disappears entirely -- the rail's live card preview IS the panel now
    --(see CharacterWindowDragging); dragging back out of the band grows it
    --back mid-drag. SCALE, not opacity or hidden: opacity is per-panel
    --(it fades only this root's own background, never the children), and
    --a hidden panel stops processing, which would kill the very drag this
    --rides on. Scale is a transform, so it collapses the whole subtree.
    dialogStyles[#dialogStyles + 1] = gui.Style {
        classes = { "framedPanel", "dockingIntoRail" },
        priority = 10,
        scale = 0.01,
        opacity = 0,
        transitionTime = 0.15,
    }
    return dialogStyles
end

--args may carry placement overrides for the window:
--  width/height: initial size (defaults to the full document dialog size;
--      a location remembered from a drag/resize this session still wins).
--  x/y: explicit position. Beats both the default centering and the
--      remembered location -- callers anchoring a window to a fixed spot
--      (e.g. restoring a stuck window at its recorded coordinates) always
--      get the spot they asked for.
--  anchor: marks x/y as a DEFAULT spot rather than an absolute one (the
--      rail icons pass it: "open beside my button, unless this window
--      already has a home"). A position the user established by dragging
--      the window this session then wins, so a rail window reopens where
--      it was left -- exactly as its size does.
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
    --a location remembered from a drag/resize this session, discarded if
    --the screen has changed size under it. moved = the user physically
    --put the window somewhere (a drag, or a left/top-edge resize that
    --shifted it) -- as opposed to the coordinates it merely happened to
    --be sitting at when it was resized, which are the opener's anchor.
    local userPlaced = false
    if self:has_key("_tmp_location") and self._tmp_location.screenx == dmhub.screenDimensionsBelowTitlebar.x and self._tmp_location.screeny == dmhub.screenDimensionsBelowTitlebar.y then
        loc.x = self._tmp_location.x or loc.x
        loc.y = self._tmp_location.y or loc.y
        loc.width = self._tmp_location.width or loc.width
        loc.height = self._tmp_location.height or loc.height
        userPlaced = self._tmp_location.moved == true and self._tmp_location.x ~= nil and self._tmp_location.y ~= nil
    end

    --an anchored placement yields to a window the user has moved; an
    --unanchored one is absolute (restores, Views, token-side placement).
    local anchored = args.anchor == true and userPlaced
    if args.x ~= nil and not anchored then
        loc.x = args.x
    end
    if args.y ~= nil and not anchored then
        loc.y = args.y
    end

    dialogWidth = loc.width
    dialogHeight = loc.height

    local dialog

    --A PINNED window is locked in place: no drag, no resize, no close.
    --The caller supplies the live predicate (PanelDocument does; journal
    --documents don't pin, so it is absent and this reads false).
    local function DialogPinned()
        return args.IsPinned ~= nil and args.IsPinned() == true
    end

    --a resize that drags the left/top edges moves the window; callers
    --tracking window position (the icon rail's open-window record) observe
    --it the same way they observe a window drag.
    local resizeOptions = self:WindowResizeOptions()
    resizeOptions.onResized = function(element, moved)
        if moved and args.onMoved ~= nil then
            args.onMoved(element)
        end
        --a plain resize places nothing, but callers persisting window
        --geometry (the icon rail's open-window record) still track it.
        if args.onResized ~= nil then
            args.onResized(element)
        end
        --a width change re-fits the tab chips (compact vs full labels)
        --and the header height tracks any row change. Tabbed panel
        --windows handle this event; everywhere else it is a no-op.
        if dialog ~= nil and dialog.valid then
            dialog:FireEventTree("syncPanelHeader")
        end
    end
    --and DURING the drag too, so the chips compress in the same frame
    --the width changes instead of wrapping until release. The fit pass
    --works from the declared width (see AvailableStripWidth), so it is
    --not a frame behind the drag.
    resizeOptions.onResizing = function(element)
        if dialog ~= nil and dialog.valid then
            dialog:FireEventTree("syncPanelHeader")
        end
    end

    dialog = gui.Panel {
        styles = DocumentWindowStyles(),
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
            --pinned windows still receive drag events (they only clear
            --dragMove -- see refreshPanelPinned); dropping the event here
            --is what keeps the remembered location untouched too.
            if DialogPinned() then
                return
            end
            element.x = element.xdrag
            element.y = element.ydrag
            element:SetAsLastSibling()

            self._tmp_location = {
                x = dialog.x,
                y = dialog.y,
                width = dialog.selfStyle.width,
                height = dialog.selfStyle.height,
                --the user has chosen where this window lives, so an
                --anchored reopen (a rail icon) yields to this position.
                moved = true,
                screenx = dmhub.screenDimensionsBelowTitlebar.x,
                screeny = dmhub.screenDimensionsBelowTitlebar.y
            }

            --callers that care where the window lands (e.g. the icon rail
            --pinning a dragged panel window) can observe the move.
            if args.onMoved ~= nil then
                args.onMoved(element)
            end
        end,
        --live drag observation (fires every frame of the drag, with the
        --in-flight position in xdrag/ydrag): the icon rail uses it to
        --dock a character window into the rail as a card WHILE dragging.
        dragging = function(element)
            if DialogPinned() then
                return
            end
            if args.onDragging ~= nil then
                args.onDragging(element)
            end
        end,
        click = function(element)
            element:SetAsLastSibling()
        end,

        --A press on EMPTY space inside the window -- the pane below a
        --short panel's content, the gap beside it -- lands here, on the
        --window's own surface: the content wrappers carry no bgimage, so
        --they are not raycast targets at all. This dialog is their
        --PARENT, and events travel up, so the interface panel that wants
        --to claim focus would never see it. Send it back down.
        press = function(element)
            element:FireEventTree("hostPanelPressed")
        end,

        data = {
            history = {},
            forwardHistory = {},
            currentDocId = self.id,
        },

        --Recolor on a theme / color-scheme switch. This window OWNS its
        --cascade (it is a top-level dialog, not a child of anything
        --themed), and DocumentWindowStyles resolved the tokens once, at
        --open time -- so without this an open panel window keeps the old
        --scheme until it is closed and reopened. The subscription is
        --per-window and dies with the window; the rail does the same for
        --its buttons.
        --
        --UpdateStyle() is required after the assignment: writing
        --`panel.styles` only marks the style-APPLICATION cache stale
        --(SheetPanel.cs bumps styleUpdateSeq but, unlike the `selfStyle`
        --setter, never calls SetStyleDirty), so nothing schedules the
        --restyle pass and the new colors sit dormant until some unrelated
        --event dirties the tree. UpdateStyle IS SetStyleDirty, and the
        --dirty time propagates to every descendant, so this one call
        --recolors the window's whole contents -- inside the same frame,
        --under the theme dialog's crossfade.
        create = function(element)
            element.data.themeListener = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = DocumentWindowStyles()
                    element:UpdateStyle()
                end
            end)
        end,

        destroy = function(element)
            if element.data.themeListener ~= nil then
                element.data.themeListener:Deregister()
                element.data.themeListener = nil
            end
        end,

        navigateToDocument = function(element, docId)
            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local newDoc = docs[docId]
            if newDoc == nil then return end

            -- Push current onto history, clear forward
            element.data.history[#element.data.history + 1] = element.data.currentDocId
            element.data.forwardHistory = {}
            element.data.currentDocId = docId

            -- Replace the content panel (child index 1; the resize overlay
            -- is the last child and must stay last, so re-raise it).
            if element.children[1] then
                element.children[1]:DestroySelf()
            end
            local navArgs = DeepCopy(args) or {}
            navArgs.dialog = dialog
            navArgs.dialogPanel = dialog
            local newPanel = newDoc:CreateInterface(navArgs)
            dialog:AddChild(newPanel)
            if dialog.data.resizePanel ~= nil and dialog.data.resizePanel.valid then
                dialog.data.resizePanel:SetAsLastSibling()
            end

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

            if element.children[1] then
                element.children[1]:DestroySelf()
            end
            local navArgs = DeepCopy(args) or {}
            navArgs.dialog = dialog
            navArgs.dialogPanel = dialog
            local newPanel = prevDoc:CreateInterface(navArgs)
            dialog:AddChild(newPanel)
            if dialog.data.resizePanel ~= nil and dialog.data.resizePanel.valid then
                dialog.data.resizePanel:SetAsLastSibling()
            end

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

            if element.children[1] then
                element.children[1]:DestroySelf()
            end
            local navArgs = DeepCopy(args) or {}
            navArgs.dialog = dialog
            navArgs.dialogPanel = dialog
            local newPanel = nextDoc:CreateInterface(navArgs)
            dialog:AddChild(newPanel)
            if dialog.data.resizePanel ~= nil and dialog.data.resizePanel.valid then
                dialog.data.resizePanel:SetAsLastSibling()
            end

            dialog:FireEventTree("refreshNavButtons")
        end,

        --pin state changed.
        --A pinned window clears dragMove, NOT draggable. The engine moves
        --a dragging panel itself every frame and only fires "drag" on
        --release, so merely declining the drag below let the window be
        --hauled around and snap back; dragMove = false means it is never
        --moved at all. Clearing `draggable` instead would stop the drag
        --earlier but also stop the press being consumed, and the drag
        --would fall through to the map and pan it.
        --The resize overlay is floating, so collapsing it costs nothing in
        --layout and stops its handles processing events. The window's
        --other pinned chrome lives in CreateInterface, which handles this
        --same event.
        refreshPanelPinned = function(element)
            element.dragMove = not DialogPinned()
            local resize = element.data.resizePanel
            if resize ~= nil and resize.valid then
                resize:SetClass("collapsed", DialogPinned())
            end
        end,

    }

    args.dialog = dialog
    args.dialogPanel = dialog
    local mainPanel = self:CreateInterface(args)
    dialog:AddChild(mainPanel)

    --the resize overlay must be the LAST child so its handles sit above
    --window content in z-order (sibling order is z-order): content that
    --reaches or overhangs the border -- the header bar, the Dice tray --
    --would otherwise shadow the handles and turn resize drags into window
    --drags. Anything replacing the content must keep it last (the
    --navigate* handlers above re-raise it); external size changes reach
    --it through dialog.data.resizePanel.
    local resizePanel = gui.WindowResizePanel(self, dialogWidth, dialogHeight, resizeOptions)
    dialog:AddChild(resizePanel)
    dialog.data.resizePanel = resizePanel
    dialog:FireEvent("refreshPanelPinned")

    return dialog
end

function CustomDocument:ShowDocument(args)
    self = (dmhub.GetTable(self.tableName) or {})[self.id] or self --get the most up-to-date version.
    args = args or {}

    local viewer = CustomDocument.GetOrCreateTabbedViewer()

    if viewer.data.poppedOut then
        --the viewer lives in its own native OS window; never re-adopt it
        --into the hud tree -- just bring its window to the front. pcall
        --for engines that predate RaiseNativeWindow.
        pcall(function() viewer:RaiseNativeWindow() end)
    elseif viewer.parent == nil then
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

--Resize constraints for a panel window, from the panel's dock
--registration: minWidth/maxWidth/minHeight/maxHeight bound the CONTENT
--(the window adds its header on top, the same accounting as ClampHeight),
--and registering resizableWidth/resizableHeight = false locks that axis
--outright. A panel registering a FIXED height (minHeight == maxHeight,
--e.g. Dice) locks the vertical axis automatically. Everything else is
--freely resizable on both axes.
function PanelDocument:WindowResizeOptions()
    local options = {
        minWidth = 300,
        minHeight = 140,
    }
    local reg = self:GetHostRegistration()
    if reg == nil then
        return options
    end
    if type(reg.minWidth) == "number" then
        options.minWidth = reg.minWidth
    end
    if type(reg.maxWidth) == "number" then
        options.maxWidth = reg.maxWidth
    end
    if type(reg.minHeight) == "number" then
        options.minHeight = reg.minHeight + g_panelDocumentHeaderHeight
    end
    if type(reg.maxHeight) == "number" then
        options.maxHeight = reg.maxHeight + g_panelDocumentHeaderHeight
    end
    options.resizeWidth = reg.resizableWidth ~= false
    options.resizeHeight = reg.resizableHeight ~= false
    if type(reg.minHeight) == "number" and reg.maxHeight == reg.minHeight then
        options.resizeHeight = false
    end
    return options
end

local g_panelDocuments = {}

--Measured tab-chip label widths by registration name, shared across all
--panel windows for the session. Lets a freshly built strip decide chip
--compaction BEFORE its first layout pass (no flash of full labels), with
--8px-per-character as the estimate until a name has been measured once.
local g_chipLabelWidthCache = {}

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

--PINNED panel windows for this game: { [panelKey] = true }. A pinned
--window is LOCKED IN PLACE -- no close button, no drag, no resize, and
--its rail button no longer toggles it shut -- and it is restored with
--the rails. Not to be confused with the rail's "iconrailpins" setting,
--which is the (legacy-named) record of which windows are open and where;
--see RailRestoreWindows.
setting{
    id = "iconrailpanelpinned",
    storage = "pergamepreference",
    default = {},
}

--The tabs each panel window carries: { [panelKey] = {"chat", "dice"} }.
--Stored independently of whether the window is open, so closing a window
--and reopening it brings its tab arrangement back.
setting{
    id = "iconrailtabs",
    storage = "pergamepreference",
    default = {},
}

--Forward-declared: the icon-rail section assigns this so a pin toggled
--from a window's own title bar also enters the rail's restore record and
--relights the rail buttons. Left nil when the rail code is not loaded.
local g_onPanelPinnedChanged

--Forward-declared likewise: fired when a window's tab set changes, i.e.
--when a GROUP forms or breaks up. The rails rebuild, because grouping
--adds a badge to one button and takes another off the rail entirely.
local g_onPanelGroupChanged

function PanelDocument.IsPinned(key)
    if key == nil then
        return false
    end
    return (dmhub.GetSettingValue("iconrailpanelpinned") or {})[string.lower(key)] == true
end

function PanelDocument.SetPinned(key, on)
    if key == nil then
        return
    end
    key = string.lower(key)
    local pinned = dmhub.GetSettingValue("iconrailpanelpinned") or {}
    if on then
        pinned[key] = true
    else
        pinned[key] = nil
    end
    dmhub.SetSettingValue("iconrailpanelpinned", pinned)

    --a live window changes its chrome without being rebuilt.
    local doc = g_panelDocuments[key]
    if doc ~= nil then
        local dlg = doc:try_get("_tmp_dialog")
        if dlg ~= nil and dlg.valid then
            dlg:FireEventTree("refreshPanelPinned")
        end
    end

    if g_onPanelPinnedChanged ~= nil then
        g_onPanelPinnedChanged(key, on == true)
    end
end

--The stored member list for a panel's folder (owner included), or nil
--when the panel has no folder beyond itself.
function PanelDocument.StoredTabs(key)
    if key == nil then
        return nil
    end
    local tabs = (dmhub.GetSettingValue("iconrailtabs") or {})[string.lower(key)]
    if type(tabs) ~= "table" or #tabs <= 1 then
        return nil
    end
    return tabs
end

local function TabsSignature(tabs)
    if type(tabs) ~= "table" then
        return ""
    end
    return table.concat(tabs, "|")
end

function PanelDocument.SetStoredTabs(key, keys)
    if key == nil then
        return
    end
    key = string.lower(key)
    local stored = dmhub.GetSettingValue("iconrailtabs") or {}
    local changed = false

    if type(keys) ~= "table" or #keys <= 1 then
        if stored[key] ~= nil then
            stored[key] = nil
            changed = true
        end
    else
        if TabsSignature(keys) ~= TabsSignature(stored[key]) then
            stored[key] = keys
            changed = true
        end

        --A panel lives in exactly ONE folder, so everything now grouped
        --here -- this folder's own panel included -- is released from
        --every other group. Both directions matter: a member that also
        --owned a group would have no rail button to reach that group
        --from, and an owner that was also somebody else's member would
        --be hidden behind two badges at once.
        local claimed = {}
        for _, k in ipairs(keys) do
            claimed[string.lower(k)] = true
        end
        for owner, tabs in pairs(stored) do
            if owner ~= key and type(tabs) == "table" then
                if claimed[owner] then
                    --this owner is now a member here; its own group goes.
                    stored[owner] = nil
                    changed = true
                else
                    local kept = {}
                    for _, k in ipairs(tabs) do
                        if not claimed[string.lower(k)] then
                            kept[#kept + 1] = k
                        end
                    end
                    if #kept ~= #tabs then
                        changed = true
                        --a group down to just its owner is no group.
                        stored[owner] = cond(#kept > 1, kept, nil)
                    end
                end
            end
        end
    end

    --Restoring a window re-adds exactly the tabs it already had, so
    --without this guard every restore would fire a rail rebuild.
    if not changed then
        return
    end

    dmhub.SetSettingValue("iconrailtabs", stored)
    if g_onPanelGroupChanged ~= nil then
        g_onPanelGroupChanged()
    end
end

--GROUPS. A group is a FOLDER on the rail: a category of panels filed
--under one button. The panel whose button it is owns the group, the
--rest are members. A member has no rail button of its own -- the
--owner's button carries a stack marker and a hover flyout with the
--members' buttons, and every panel in the folder (owner included)
--opens and closes its OWN window independently. The stored list
--("iconrailtabs", a name kept for compatibility with saved layouts)
--is purely the folder membership -- windows are always single-panel.

--{ [memberKey] = ownerKey } across every stored group. Owners never
--appear as members (SetStoredTabs enforces it), so this cannot chain.
function PanelDocument.GroupOwners()
    local result = {}
    for owner, tabs in pairs(dmhub.GetSettingValue("iconrailtabs") or {}) do
        if type(tabs) == "table" and #tabs > 1 then
            for _, k in ipairs(tabs) do
                if k ~= owner then
                    result[k] = owner
                end
            end
        end
    end
    return result
end

--The other panels filed in this panel's folder, in strip order, or nil
--when it stands alone.
function PanelDocument.GroupMembers(key)
    if key == nil then
        return nil
    end
    key = string.lower(key)
    local tabs = PanelDocument.StoredTabs(key)
    if tabs == nil then
        return nil
    end
    local result = {}
    for _, k in ipairs(tabs) do
        if k ~= key then
            result[#result + 1] = k
        end
    end
    if #result == 0 then
        return nil
    end
    return result
end

--The full member list of the folder OWNED by this key, owner included
--and owner first when no stored order says otherwise. A panel that owns
--no folder returns just itself, so callers can treat every window's tab
--set the same way.
function PanelDocument.FolderTabs(ownerKey)
    ownerKey = string.lower(ownerKey)
    local tabs = PanelDocument.StoredTabs(ownerKey)
    local list = {}
    local seenOwner = false
    if tabs ~= nil then
        for _, k in ipairs(tabs) do
            k = string.lower(k)
            if k == ownerKey then
                seenOwner = true
            end
            list[#list + 1] = k
        end
    end
    if not seenOwner then
        table.insert(list, 1, ownerKey)
    end
    return list
end

--The panel whose WINDOW hosts this key. A folder is the tab set of a
--single window owned by the folder's owner, so a member resolves to its
--owner and everything else is its own host. Owners never chain
--(SetStoredTabs enforces it), so one lookup is enough.
function PanelDocument.WindowOwner(key)
    if key == nil then
        return nil
    end
    key = string.lower(key)
    return PanelDocument.GroupOwners()[key] or key
end

--Open this panel's standalone window, or raise the existing one.
--Placement args (x, y, width, height) pass through to PresentDocument.
--args.activeKey selects which of the window's tabs starts active
--(defaults to the owner's own panel).
--Returns the window panel.
function PanelDocument:PresentPanel(args)
    args = args or {}

    local existing = self:try_get("_tmp_dialog")
    if existing ~= nil and existing.valid then
        existing:SetAsLastSibling()
        if args.activeKey ~= nil then
            existing:FireEventTree("selectPanelTab", string.lower(args.activeKey))
        end
        return existing
    end

    args.width = args.width or PanelDocument.DefaultWidth
    args.height = PanelDocument.ClampHeight(
        self:try_get("panelName"),
        args.height or PanelDocument.DefaultHeight)

    --the live pin predicate the window's chrome (drag, resize, close,
    --tab closes) consults. Read fresh every time so unpinning takes
    --effect without rebuilding the window.
    local pinKey = string.lower(self:try_get("panelName") or "")
    args.IsPinned = function()
        return PanelDocument.IsPinned(pinKey)
    end

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
            --deferBuild: the window frame appears the instant it is
            --requested; the (expensive) character content populates on
            --the next frame, which reads much snappier.
            return CharacterPanel.CreatePinnedCharacterPanel(charid, { deferBuild = true })
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

--What a press on this panel's rail button (or its chip in a folder's
--hover strip) should DO. A folder is one window with one tab per member,
--so a press means three different things depending on what is already up:
--
--  "open"   -- nothing is open; open the window on this panel's tab
--  "switch" -- the window is open on a DIFFERENT tab; bring this one up
--  "close"  -- the window is open on THIS tab; the press closes it
--  "raise"  -- as "close", but the window is pinned, so it only raises
--
--Returns the verb, the owner key, the owner's document, and the open
--dialog (nil when there is none).
local function RailActivation(key)
    key = string.lower(key)
    local ownerKey = PanelDocument.WindowOwner(key)
    local doc = RailPanelDocument(ownerKey)
    if doc == nil then
        return nil, ownerKey, nil, nil
    end
    local dialog = doc:try_get("_tmp_dialog")
    if dialog == nil or not dialog.valid then
        return "open", ownerKey, doc, nil
    end
    --a folder window sitting on another member's tab: the press is a
    --tab switch, never a close. Closing is reserved for pressing the
    --panel you are already looking at (and for the window's own x).
    local active = nil
    pcall(function() active = dialog.data.activePanelTab end)
    if active ~= nil and active ~= key then
        return "switch", ownerKey, doc, dialog
    end
    if PanelDocument.IsPinned(ownerKey) then
        return "raise", ownerKey, doc, dialog
    end
    return "close", ownerKey, doc, dialog
end

--The rail's curated panel list, in display order (from the Player Icon
--Rail design). Panels missing a registration, or not available to this
--user (dmonly/devonly), are skipped wherever the list is consumed.
local g_iconRailPanels = {
    "Character",
    --"Heroes" was removed 2026-08-08: it is not a registered dockable
    --panel at all any more -- the title bar's connectivity panel hosts
    --it as a popout. Stored rail entries for it go inert (registration
    --lookup fails), same as any unavailable panel.
    "Dice",
    "Chat",
    "Action Log",
    "Journal",
    "Campaign Tracker",
    "Downtime Projects",
    "Triggers",
    "Audio",
    "Safety",
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

--Panels currently popped out into native OS windows (MoveToNativeWindow,
--the PDF viewer's companion-app mechanism): key -> the host root panel.
--Entries clear themselves in the host's destroy handler, which fires on
--every close path alike -- the pop-in button, the OS window's close
--button (the engine destroys the popped hierarchy), and the unload
--sweep below (the engine then closes windows whose panel died).
local g_panelPopouts = {}

--A Lua reload rebuilds the hud but never reaches popped-out hosts: they
--are unparented from the hud tree, so without this they would survive
--the reload as orphans -- live windows running the OLD module instance,
--invisible to the new instance's registry and rail bookkeeping. Destroy
--them with the module; the engine closes their native windows, and the
--rail's restore records reopen the panels in-app.
mod.unloadHandlers[#mod.unloadHandlers + 1] = function()
    for _, host in pairs(g_panelPopouts) do
        if host ~= nil and host.valid then
            host:DestroySelf()
        end
    end
    g_panelPopouts = {}

    --the tabbed journal viewer, likewise, never survives a reload while
    --popped out: it is unparented from the hud tree, so the hud rebuild
    --cannot reach it. Destroy it and the engine closes its window.
    if g_tabbedViewer ~= nil and g_tabbedViewer.valid and g_tabbedViewer.data.poppedOut then
        g_tabbedViewer:DestroySelf()
        g_tabbedViewer = nil
    end
end

function PanelDocument.PopoutHost(key)
    local host = g_panelPopouts[string.lower(key)]
    if host ~= nil and host.valid then
        return host
    end
    return nil
end

function PanelDocument.IsPoppedOut(key)
    return PanelDocument.PopoutHost(key) ~= nil
end

function PanelDocument.IsPanelShown(key)
    return PanelDocument.FindHostDialog(key) ~= nil or PanelDocument.IsPoppedOut(key)
end

--Whether this panel is the one its window is actually DISPLAYING. A
--folder window hosts every member as a tab but shows one at a time, so
--"lives in an open window" (IsPanelShown) and "is on screen" are
--different questions: a member filed in an open folder is reachable in
--one click but not visible. Buttons light, and offer Close instead of
--Open, for the panel you are looking at.
function PanelDocument.IsPanelActive(key)
    local dialog = PanelDocument.FindHostDialog(key)
    if dialog == nil then
        return false
    end
    local active = nil
    pcall(function() active = dialog.data.activePanelTab end)
    --a window that has not published an active tab yet is showing its
    --only panel.
    if active == nil then
        return true
    end
    return active == string.lower(key)
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

    --This window's panel key, and whether it is currently PINNED (locked
    --in place). Only standalone windows pin -- a panel hosted inside the
    --journal viewer is the host's to close.
    local panelKey = string.lower(self:try_get("panelName") or "")
    local function Pinned()
        return tabbed and PanelDocument.IsPinned(panelKey)
    end

    --forward-declared: resultPanel is declared up here so
    --SyncPinnedState can toggle its escape capture.
    local pinButton
    local SyncPinnedState
    local SyncArmedState
    local resultPanel

    --The window's close x owns the header's top-right corner -- the
    --universal window convention (one close control only: two x's in
    --one header read as a bug -- Venla 2026-08-12). While pinned it
    --stays exactly where it is and dims (SyncPinnedState): a pinned
    --window cannot be closed, but the control must not move.
    --A plain panel with the phosphor x, NOT the legacy closeButton
    --widget: the old glyph read dated, its top-anchored offset sat
    --below the header's centre line, and the widget kind's default
    --escape activation would race the window root's own escape handler.
    local closeButton = gui.Panel{
        classes = {"panelDocumentCloseButton"},
        bgimage = "phosphor/x-bold.png",
        width = 18,
        height = 18,
        --In-flow inside headerControls (which does the floating and the
        --corner anchoring for both controls), centred against the
        --header's real height so it stays put when the chip strip
        --changes form or wraps to a second row.
        valign = "center",
        swallowPress = true,
        click = function(element)
            if Pinned() then
                return
            end
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

    --"Pop out": move this panel into its own native OS window (the
    --companion-app mechanism the PDF viewer uses). Only offered when the
    --hosting flow supplies the gesture (rail windows do; a panel hosted
    --inside the journal viewer is the host's to manage). Pinned means
    --locked in place, so the click is inert while pinned, matching the
    --close x.
    --
    --In-flow inside headerControls like the other two, so all three share
    --one corner anchor rather than each carrying a hand-tuned offset.
    local popoutButton = nil
    if args.popout ~= nil then
        popoutButton = gui.Panel{
            classes = {"panelDocumentCloseButton"},
            bgimage = "drawsteel/Icons_Nav_MaxWindow.png",
            width = 16,
            height = 16,
            valign = "center",
            rmargin = 6,
            swallowPress = true,
            linger = function(element)
                gui.Tooltip("Pop out into its own window")(element)
            end,
            click = function(element)
                if Pinned() then
                    return
                end
                args.popout()
            end,
        }
    end

    --The pin toggle: locks the WINDOW in place (no close, no drag, no
    --resize) and marks it to be restored with the rails. Quiet until
    --hovered or pinned, so the header stays clean.
    --
    --A window property, not a tab one: it lives in the header beside the
    --close x, not inside a title chip. With a folder's whole membership
    --on the strip, a pin per chip would ask "pin which tab?" of a state
    --that only ever meant "leave this window where it is".
    pinButton = gui.Panel{
        classes = {"panelDocumentPinButton"},
        bgimage = "phosphor/push-pin-simple-light.png",
        width = 14,
        height = 14,
        valign = "center",
        rmargin = 6,
        --the header under it drags and shades on (double)click; the
        --pin's own click must not double as those.
        swallowPress = true,
        click = function(element)
            PanelDocument.SetPinned(panelKey, not Pinned())
        end,
    }
    if not tabbed then
        pinButton:SetClass("collapsed", true)
    end

    --The header controls ride in one floating right-anchored row, so
    --they share one corner anchor instead of hand-tuned offsets each.
    --None of them ever leaves the row (a pinned window dims its x rather
    --than hiding it), so the set holds its position in every state.
    --
    --popoutButton is nil when the hosting flow supplies no popout
    --gesture, so the children are listed explicitly: a nil in the middle
    --of a positional table constructor truncates the list after it.
    local headerControlChildren = {}
    if popoutButton ~= nil then
        headerControlChildren[#headerControlChildren+1] = popoutButton
    end
    headerControlChildren[#headerControlChildren+1] = pinButton
    headerControlChildren[#headerControlChildren+1] = closeButton

    local headerControls = gui.Panel{
        width = "auto",
        height = "auto",
        flow = "horizontal",
        floating = true,
        halign = "right",
        valign = "center",
        x = -6,
        children = headerControlChildren,
    }

    --===== tab model =====
    --The window's tabs ARE its rail folder: one entry per panel filed
    --under this one, in strip order, owner first. A panel that owns no
    --folder gives a one-entry list, which is the same machinery with
    --nothing to switch between. Each entry is {key, reg, chip, wrapper},
    --and a wrapper is only built when its tab is first activated.
    --
    --There is deliberately no per-tab close: membership is a rail
    --decision (drag a button onto another to file it), so a window
    --cannot dissolve the arrangement the user made. The header's x
    --closes the whole folder.
    local m_tabs = {}
    local m_activeKey = nil
    local m_constructing = true
    local SyncChipCompaction

    --The inline name belongs to the ACTIVE chip and only ever moves on a
    --real tab switch. Hovering deliberately does NOT move it: a hovered
    --chip that grew its name in place shifted every other chip 86px
    --(measured, six-member folder), so sweeping the strip slid the chip
    --you were aiming at out from under the cursor. Layout does not
    --reflow under the pointer; the hover name is a separate floating
    --label instead (see BuildChip).
    local tabStrip
    local contentArea
    local hairline
    local header

    local m_shaded = false
    local m_savedHeight = nil
    local m_lastShadeToggle = nil
    --Set by a chip's double-click. The chip cannot swallow the event
    --without costing the window its drag area, so instead it claims the
    --shade the header is about to perform (see BuildChip).
    local m_suppressShadeUntil = nil

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
    --contract as the tabbed viewer's SetViewerHeight). PresentDocument
    --publishes the resize overlay at dialog.data.resizePanel (it is the
    --dialog's LAST child, so its handles sit above window content).
    local function SetWindowHeight(newHeight)
        local old = dialog.selfStyle.height
        if type(old) ~= "number" then
            old = dialog.renderedHeight
        end
        dialog.selfStyle.height = newHeight
        local resizePanel = dialog.data.resizePanel
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
        --a tab chip claimed this double-click (see BuildChip): switching
        --tabs quickly must never roll the window up.
        if m_suppressShadeUntil ~= nil and dmhub.Time() < m_suppressShadeUntil then
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
        --later reopen is never squashed. Announce the repair the same way
        --a resize is announced, so a caller persisting window geometry
        --(the icon rail's open-window record) picks it up too.
        local loc = self:try_get("_tmp_location")
        if loc ~= nil and m_savedHeight ~= nil then
            loc.height = m_savedHeight
            if args.onResized ~= nil and dialog ~= nil and dialog.valid then
                args.onResized(dialog)
            end
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

    --Complete a focus grab for a tab whose content exists. Two flavors,
    --by registration flag: a focusOnClick panel (the map-mode tools)
    --takes real GUI focus on its content root, which is what arms its
    --map mode; an autoFocusInput panel (Chat) just wants its input
    --field focused so the user can start typing -- the content tree
    --handles "focusPanelInput" and moves focus to the field itself.
    local function ClaimTabFocus(tab)
        local content = tab.contentRoot
        if content == nil or not content.valid then
            return
        end
        if tab.reg.focusOnClick then
            --Already ours: leave focus exactly where it is. See the dock's
            --copy in FocusPanelContent -- a press on one of the panel's own
            --controls bubbles up here too (presses do not swallow by
            --default), and re-grabbing to the content root wipes focus
            --state the panel's controls track themselves. The Objects
            --palette's ctrl/shift multi-select reads the previously focused
            --entry inside its click handler, and press runs first, so the
            --unguarded grab broke it outright (report YYDRFNXP).
            if gui.ChildHasFocus(content) then
                return
            end
            gui.SetFocus(content)
            content:FireEventTree("panelFocused")
        elseif tab.reg.autoFocusInput then
            content:FireEventTree("focusPanelInput")
        end
    end

    --Mirror the dock host's content contract (CreateDockablePanelInstance):
    --content() inside a vscroll parent unless the registration opts out.
    --Content anchors to the top of the window: the dock sizes its slots
    --to hug content, but our window height is fixed, and a short panel
    --left to the default centering floats in a void.
    --
    --DEFERRED BUILD: the wrapper (and the window chrome around it)
    --renders on the frame the window opens; reg.content() -- the
    --expensive part -- runs one tick later via "buildPanelContent"
    --(scheduled by SwitchTab). The window therefore appears instantly
    --and its contents pop in a moment later, which reads much snappier
    --than blocking the click on the full build.
    --tab.contentRoot is set once the content exists -- click-to-focus
    --has to focus that exact element (focus-gated panels test
    --gui.ChildHasFocus on their own root, which does not count
    --ancestors). Anything that wants focus before the content exists
    --records the intent as tab.focusWhenBuilt and the build completes
    --the grab (see FocusActiveTab).
    local function BuildContentWrapper(tab)
        local reg = tab.reg

        local buildContent = function(element)
            if mod.unloaded or not element.valid or tab.contentRoot ~= nil then
                return
            end
            --LAZY: only the tab being shown builds. Building a hidden tab
            --(restored as part of the window's stored tab set) is wasted
            --work on open, and content can carry mount side-effects --
            --polled setting monitors, focus grabs -- that must not fire
            --for a tab nobody is looking at. SwitchTab re-arms the build
            --when the tab is first shown.
            if m_activeKey ~= tab.key then
                return
            end
            local content = reg.content()
            tab.contentRoot = content
            content.selfStyle.valign = "top"
            --anchor the hosted content left as well: without an alignment
            --from an ancestor, panel content centers in the window host
            --(never in the dock, which supplies one). This is the correct
            --level for the fix -- forcing halign inside content styles (the
            --old approach) overrides flow positioning row by row and
            --scrambles layouts like the journal tree's folder headers.
            content.selfStyle.halign = "left"
            element:AddChild(content)

            --panels that follow map selection (Character, Triggers) fill
            --themselves in from the hud-wide 'refresh' event, which the
            --engine only fires when something CHANGES (SheetHud marks it
            --dirty on selection/initiative changes). A panel mounted after
            --the fact therefore starts empty and stays that way until the
            --next change -- which is why opening the Character panel with a
            --token already selected showed nothing until you reselected it.
            --Prime it in the same tick it is built, so the content never
            --renders a frame of the wrong (unprimed) state and then
            --visibly swaps.
            element:FireEventTree("refresh")

            --a user-initiated open of a focus-hungry panel recorded its
            --focus grab here because the content did not exist yet;
            --complete it now that it does -- unless the user already
            --moved on to another tab.
            if tab.focusWhenBuilt then
                tab.focusWhenBuilt = nil
                if m_activeKey == tab.key and content.valid then
                    ClaimTabFocus(tab)
                end
            end

            --a "/" keystroke that summoned this window (RailSlashOpensChat)
            --recorded itself the same way; deliver it now that the chat
            --input exists.
            if tab.slashWhenBuilt then
                tab.slashWhenBuilt = nil
                if m_activeKey == tab.key and content.valid then
                    content:FireEventTree("slash")
                end
            end

            --the tab was switched to while this content did not exist yet,
            --so the fade-in was held until now. Starting it at switch time
            --would have run the ramp on an empty panel and then popped the
            --content in at full strength -- a flash, not a fade.
            element:SetClass("fading", false)
        end

        --Clears the fade for content that ALREADY existed when the tab was
        --switched to (SwitchTab schedules this a tick out so the style
        --system sees opacity 0 first and has something to animate from).
        local revealContent = function(element)
            element:SetClass("fading", false)
        end

        if reg.vscroll ~= false then
            local hideObjectsOutOfScroll = reg.hideObjectsOutOfScroll
            if hideObjectsOutOfScroll == nil then
                hideObjectsOutOfScroll = true
            end
            return gui.Panel{
                idprefix = "panelDocumentScrollParent",
                classes = {"panelDocumentTabContent"},
                revealTabContent = revealContent,
                width = "100%",
                height = "100%",
                pad = 2,
                --without borderBox the pad grew the panel 4px past its
                --declared size and the centered overflow poked 2px out
                --each end -- the scrollbar visibly rode over the header
                --hairline (Venla 2026-08-12). The old width was "100%-4"
                --purely to cancel that growth; with borderBox the honest
                --100% is what keeps the scrollbar flush at the right edge.
                borderBox = true,
                vscroll = true,
                hideObjectsOutOfScroll = hideObjectsOutOfScroll,
                buildPanelContent = buildContent,
            }
        end
        return gui.Panel{
            idprefix = "panelDocumentNoScrollParent",
            classes = {"panelDocumentTabContent"},
            revealTabContent = revealContent,
            width = "100%",
            height = "100%",
            buildPanelContent = buildContent,
        }
    end

    --publish the panel list on the dialog (the rail's window bookkeeping
    ---- FindHostDialog, orphan cleanup after a reload -- identifies panel
    --windows by this field). The list is the window's FOLDER: its own
    --panel plus every panel filed under it. Membership itself is stored
    --separately and owned by the rail's grouping verbs; the window reads
    --it and never writes it.
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
        end
    end

    local function SwitchTab(key)
        local tab = FindTab(key)
        if tab == nil then
            return
        end
        if tab.wrapper == nil then
            tab.wrapper = BuildContentWrapper(tab)
            tab.wrapper:SetClass("collapsed", true)
            --starts transparent so its first appearance is a fade rather
            --than a cut; buildContent clears this once content exists.
            tab.wrapper:SetClass("fading", true)
            contentArea:AddChild(tab.wrapper)
            --the shell mounts this frame; the content itself builds a
            --tick later (see BuildContentWrapper).
            tab.wrapper:ScheduleEvent("buildPanelContent", 0.01)
        elseif tab.contentRoot == nil then
            --the wrapper exists but its deferred build has not landed --
            --a tab that was collapsed away before ever activating (e.g.
            --restored in the background) can miss its scheduled event
            --entirely. Re-arm it; the build no-ops once content exists,
            --so a double fire is harmless.
            tab.wrapper:ScheduleEvent("buildPanelContent", 0.01)
        end
        m_activeKey = key
        --publish it: the rail reads the active tab to decide whether a
        --button press switches tabs or closes the window (see
        --RailActivation), and the restore record remembers it.
        if dialog ~= nil and dialog.valid then
            dialog.data.activePanelTab = key
        end
        for _, t in ipairs(m_tabs) do
            if t.wrapper ~= nil and t.wrapper.valid then
                local hidden = t.key ~= key
                t.wrapper:SetClass("collapsed", hidden)
                if hidden then
                    --a tab going away is left transparent, which is what
                    --the NEXT activation animates up from. The fade-out
                    --itself is unseen -- it collapses in the same frame --
                    --so the transition never runs on the outgoing panel
                    --and two tabs are never composited at once.
                    t.wrapper:SetClass("fading", true)
                elseif t.contentRoot ~= nil then
                    --content is already built: reveal a tick out so the
                    --style system registers opacity 0 first and has a
                    --value to animate from. A tab whose content does NOT
                    --exist yet is revealed by its build instead.
                    t.wrapper:ScheduleEvent("revealTabContent", 0.01)
                end
            end
            if t.chip ~= nil and t.chip.valid then
                t.chip:SetClass("selected", t.key == key)
            end
        end
        --the one visible label rides the active tab, so every switch
        --moves it -- and the width swap can change the header's row
        --count. Skipped during construction, which fits the strip once
        --after adding every chip.
        if not m_constructing and SyncChipCompaction ~= nil then
            SyncChipCompaction()
            if header ~= nil and header.valid then
                header:ScheduleEvent("syncPanelHeader", 0.05)
            end
        end
    end

    --Claim GUI focus for the active tab's panel, when that panel asked
    --for it (reg.focusOnClick -- the map-mode panels: Map Markup, the
    --Measuring Tool, Objects, Building, Terrain -- or reg.autoFocusInput
    --for Chat, which focuses its input field instead; see ClaimTabFocus).
    --For map-mode panels focus is what arms their mode, so this IS "put
    --the app into that panel's mode".
    --The content may still be a tick away from existing (deferred
    --build); recording focusWhenBuilt makes the build finish the grab,
    --so a user-initiated open still enters the mode immediately.
    local function FocusActiveTab()
        if not tabbed or m_activeKey == nil then
            return
        end
        local tab = FindTab(m_activeKey)
        if tab == nil or tab.reg == nil then
            return
        end
        if not (tab.reg.focusOnClick or tab.reg.autoFocusInput) then
            return
        end
        if tab.contentRoot ~= nil and tab.contentRoot.valid then
            ClaimTabFocus(tab)
        else
            tab.focusWhenBuilt = true
        end
    end

    local AddTab

    --Chip geometry, derived from live measurement: an active chip is 34px
    --of fixed chrome (the icon's 6+6 margins, the 16px icon itself, and
    --the label's 6px rmargin) plus its label text; an inactive chip
    --collapses the label and renders at 6+16+6 = 28. The 1px border adds
    --nothing to layout width. Each chip adds 2px of h-margins on top.
    local CHIP_FIXED = 34
    local CHIP_ICON_ONLY = 28

    --A tab's label width: measured when we have it (this window or any
    --earlier one -- the cache is per registration name), 8px per
    --character until then. The estimate leans wide on purpose: guessing
    --compact and relaxing is quieter than a row appearing and vanishing.
    local function LabelWidthOf(t)
        if t.labelWidth ~= nil then
            return t.labelWidth
        end
        local cached = g_chipLabelWidthCache[t.reg.name]
        if cached ~= nil then
            return cached
        end
        return 8 * #tostring(t.reg.name or "")
    end

    --The width the strip has to work with. Derived from the dialog's
    --DECLARED width (selfStyle is authoritative: construction and every
    --resize write it), minus the dialog-to-strip inset. The inset starts
    --at the tabStrip's declared -48 and self-calibrates from rendered
    --measurements once a layout pass has run. Working from the declared
    --width rather than the strip's renderedWidth is what keeps a
    --mid-drag fit frame-correct: renderedWidth is a frame stale while a
    --resize drag is rewriting the width every frame.
    local m_stripInset = 48
    local function AvailableStripWidth()
        local sw, dw
        if tabStrip ~= nil and tabStrip.valid then
            sw = tabStrip.renderedWidth
        end
        if dialog ~= nil and dialog.valid then
            dw = dialog.renderedWidth
        end
        if type(sw) == "number" and sw > 0 and type(dw) == "number" and dw > 0 then
            m_stripInset = dw - sw
        end
        local declared
        if dialog ~= nil and dialog.valid then
            declared = dialog.selfStyle.width
        end
        if type(declared) == "number" then
            return declared - m_stripInset
        end
        --non-numeric window width (never the case for panel windows
        --today): the measured strip is the best remaining answer.
        if type(sw) == "number" and sw > 0 then
            return sw
        end
        return nil
    end

    --Keep the strip to ONE ROW: the active chip wears its icon and name,
    --every other chip is its icon alone (the name moves to a hover
    --tooltip -- see BuildChip). This is the permanent form, not an
    --overflow response: with a folder's whole membership on the strip a
    --row of full labels would be unreadable, and a name that appears and
    --vanishes as you switch tabs is worse than one that never does. The
    --active chip carries the name because it is the window's title.
    --
    --The one adaptive stage left is for very narrow windows: when even
    --icon-only siblings plus the active name overflow, the active
    --label's maxWidth is capped to exactly the surplus-free width so it
    --shrinks toward minFontSize and then ellipsizes instead of pushing
    --the strip onto a second row. Wrapping remains the true fallback for
    --when the icons alone will not fit.
    --
    --Callable BEFORE the strip's first layout pass (estimates take over
    --for missing measurements), which is what lets a restored window
    --render its first frame already fitted instead of flashing full
    --labels and re-fitting.
    --
    --Returns true when it changed any chip -- the caller must let a
    --layout pass run and then re-measure anything sized off the header.
    SyncChipCompaction = function()
        local avail = AvailableStripWidth()
        if avail == nil then
            return false
        end

        --measure what is measurable and remember it across windows.
        --A width-capped label renders at its cap, not its natural width,
        --so it is excluded -- caching it would corrupt the full-width
        --estimates every later fit works from.
        for _, t in ipairs(m_tabs) do
            local lbl = t.chipLabel
            if lbl ~= nil and lbl.valid and not lbl:HasClass("collapsed") and t.labelCap == nil then
                local lw = lbl.renderedWidth
                if type(lw) == "number" and lw > 0 then
                    t.labelWidth = lw
                    g_chipLabelWidthCache[t.reg.name] = lw
                end
            end
        end

        --the width one row needs in that form. Exactly one chip spells
        --its name out: the active one.
        local named = m_activeKey
        local needed = 0
        for _, t in ipairs(m_tabs) do
            if t.chip ~= nil and t.chip.valid then
                if t.key == named then
                    needed = needed + CHIP_FIXED + LabelWidthOf(t) + 2
                else
                    needed = needed + CHIP_ICON_ONLY + 2
                end
            end
        end

        local changed = false
        for _, t in ipairs(m_tabs) do
            local lbl = t.chipLabel
            if lbl ~= nil and lbl.valid then
                local hide = t.key ~= named
                if lbl:HasClass("collapsed") ~= hide then
                    lbl:SetClass("collapsed", hide)
                    changed = true
                end
            end
        end

        --the narrow-window stage: cap the named label into whatever
        --width remains. The 30px floor keeps a few characters legible.
        for _, t in ipairs(m_tabs) do
            local lbl = t.chipLabel
            if lbl ~= nil and lbl.valid then
                local cap = nil
                if t.key == named then
                    local overflow = needed - avail
                    if overflow > 0 then
                        cap = math.max(30, math.ceil(LabelWidthOf(t) - overflow))
                    end
                end
                if cap ~= t.labelCap then
                    t.labelCap = cap
                    --relax to a huge cap rather than nil: clearing style
                    --numbers can pin them (see cornerRadius), and 9999
                    --is beyond any real label.
                    lbl.selfStyle.maxWidth = cap or 9999
                    changed = true
                end
            end
        end

        return changed
    end

    --ARMED = this window's active panel currently holds the GUI focus its
    --tool gates on, i.e. clicks on the map go to IT. Carried by the armed
    --panel's own NAME in the tab strip: with a folder's whole membership
    --on the strip, "something in this window is armed" is not enough, it
    --has to say WHICH.
    --
    --The hairline under the strip used to accent too and does not any
    --more (Venla 2026-08-15) -- a full-width rule was a lot of line for
    --the amount it said.
    SyncArmedState = function(armed)
        for _, t in ipairs(m_tabs) do
            if t.chip ~= nil and t.chip.valid then
                t.chip:SetClass("armed", armed and t.key == m_activeKey)
            end
        end
    end

    --Keep every piece of pin-sensitive chrome in step with the current
    --pin state. Fired on construction and whenever the pin toggles.
    SyncPinnedState = function()
        local pinned = Pinned()
        if pinButton ~= nil and pinButton.valid then
            pinButton:SetClass("pinned", pinned)
        end
        --A pinned window cannot be closed, and the x says so by DIMMING
        --rather than disappearing: hiding it let the pin reflow into the
        --corner, so pinning shuffled the header's controls around under
        --the cursor. The x holds its place and reads as unavailable
        --(Venla 2026-08-15). Only a host that suppresses it outright
        --(a panel rendered inside the journal viewer) collapses it.
        if closeButton ~= nil and closeButton.valid then
            closeButton:SetClass("collapsed", args.suppressCloseButton == true)
            closeButton:SetClass("disabled", pinned)
        end
        --a pinned window also stops listening for escape entirely -- the
        --press falls through to lower-priority handlers instead of being
        --swallowed by a no-op.
        if resultPanel ~= nil and resultPanel.valid then
            resultPanel.captureEscape = tabbed and not pinned
        end
    end

    local function BuildChip(tab)
        --Acting on the chip dismisses its hover name: the pointer is
        --still sitting on the chip after a click, so nothing else would
        --take the name down, and the tab it just selected now spells its
        --name out inline -- leaving the floating one up duplicates it.
        --A later hover re-reveals it only if it is still worth showing
        --(revealTabName's redundancy check).
        local function DismissHoverName()
            tab.hovering = false
            if tab.hoverLabel ~= nil and tab.hoverLabel.valid then
                tab.hoverLabel:SetClass("shown", false)
            end
        end

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
                DismissHoverName()
                SwitchTab(tab.key)
                --switching TO a map-mode tab arms it. The dialog's own
                --press already fired hostPanelPressed, but that ran
                --before this click and so focused the PREVIOUS tab.
                FocusActiveTab()
            end,
            --A double-click on a TAB is two switches, not a window-shade.
            --Chips deliberately do NOT swallow their events (the press
            --has to reach the dialog's draggable, which is what lets the
            --window be dragged by its whole bar, chips included), so the
            --header's own shade handler still receives this -- and used
            --to roll the window up when you double-clicked a tab
            --impatiently or while switching quickly. Rather than break
            --dragging, mark the shade that is about to arrive as spoken
            --for; ToggleShade honours the window.
            doubleclick = function(element)
                DismissHoverName()
                m_suppressShadeUntil = dmhub.Time() + 0.3
                SwitchTab(tab.key)
            end,

            --The hover name. DELAYED: the reveal waits out a short dwell
            --so names do not strobe as the pointer sweeps the strip on
            --its way somewhere else -- the same reason tooltips have a
            --delay. Nothing about this moves the chips.
            hover = function(element)
                tab.hovering = true
                element:ScheduleEvent("revealTabName", 0.3)
            end,
            dehover = function(element)
                tab.hovering = false
                if tab.hoverLabel ~= nil and tab.hoverLabel.valid then
                    tab.hoverLabel:SetClass("shown", false)
                end
            end,
            revealTabName = function(element)
                --the pointer may have left during the dwell.
                if not tab.hovering then
                    return
                end
                if tab.hoverLabel == nil or not tab.hoverLabel.valid then
                    return
                end
                --the active chip already spells its name out inline, so
                --naming it again is noise -- unless a narrow window has
                --capped that inline label, where it may be ellipsized
                --and the full name is genuinely not on screen.
                local redundant = (tab.key == m_activeKey and tab.labelCap == nil)
                tab.hoverLabel:SetClass("shown", not redundant)
            end,

            --The chip's horizontal insets live on its CHILDREN (it is an
            --auto-width panel, so its own edges are wherever they land):
            --6px outside the icon, 6px outside the label. That has to be
            --symmetric on the icon specifically, because an inactive chip
            --collapses its label away and is then nothing but this icon --
            --the old icon-only chip carried the 8px inset on its left
            --alone and sat the icon flush against its right edge
            --(Venla 2026-08-15). The icon's rmargin doubles as the gap
            --before the label, which is why the label needs no lmargin.
            gui.Panel{
                classes = {"panelDocumentHeaderIcon"},
                bgimage = tab.reg.icon or "icons/icon_app/icon_app_107.png",
                width = 16,
                height = 16,
                halign = "left",
                valign = "center",
                lmargin = 6,
                rmargin = 6,
            },
            (function()
                tab.chipLabel = gui.Label{
                    classes = {"panelDocumentTitle"},
                    text = string.upper(tab.reg.name),
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    rmargin = 6,
                    --when SyncChipCompaction caps this label's maxWidth
                    --(very narrow windows), shed width gracefully: shrink
                    --the font a little first, then ellipsize. At auto
                    --width with no cap these are inert.
                    minFontSize = 8,
                    textWrap = false,
                    textOverflow = "ellipsis",
                }
                return tab.chipLabel
            end)(),

            --The hover name, on a plate cut from the same cloth as the
            --chips (see the panelDocumentTabLabel styles). NO
            --textOutline: the engine draws textOutlineColor as a slab
            --hugging the string, which would double up with the real
            --background.
            --
            --BELOW the chip, not above. The chips sit in the window's TOP
            --edge, so a label above always draws outside the window: over
            --the app's menu bar for a window near its minimum y of 40,
            --and over arbitrary map art, where the plate would float on
            --nothing. Below, it lands on the window's own surface and can
            --never leave the window. Browsers put tab tooltips below the
            --tab strip for the same reason.
            (function()
                tab.hoverLabel = gui.Label{
                    classes = {"panelDocumentTabLabel"},
                    text = tab.reg.name,
                    floating = true,
                    --REQUIRED for the plate to paint at all: bgcolor
                    --alone draws nothing without a background image.
                    bgimage = true,
                    --it draws over panel content, which is a sibling
                    --subtree with its own draw order.
                    renderOnTop = true,
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "top",
                    --the chip is g_panelDocumentHeaderHeight-6 (26) tall
                    --and sits 3px down the header, so this clears the
                    --chip, the header's lower edge and the hairline and
                    --lands just inside the content area.
                    y = 32,
                    hpad = 8,
                    vpad = 3,
                    borderBox = true,
                    textWrap = false,
                    interactable = false,
                }
                return tab.hoverLabel
            end)(),
        }
    end

    --Add one panel to the window as a tab. `quiet` suppresses the
    --activation and the strip re-fit: bulk construction adds every
    --folder member and then activates ONE of them, and activating each
    --in turn would build every tab's content instead of just the one
    --the user asked for (SwitchTab is what materializes a wrapper).
    AddTab = function(key, quiet)
        if FindTab(key) ~= nil then
            if not quiet then
                SwitchTab(key)
            end
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
        SyncDialogTabs()
        if quiet then
            return
        end
        SwitchTab(tab.key)
        --fit the strip NOW, estimates standing in for the unmeasured new
        --chip, so the chip never renders a frame in a form (or row) it
        --immediately abandons.
        SyncChipCompaction()
        --re-measure once the new chip has been through a layout pass
        --(this corrects the estimate and re-syncs the header height).
        if header ~= nil and header.valid then
            header:ScheduleEvent("syncPanelHeader", 0.05)
        end
    end

    --Drop a panel from the window. Used when the folder membership
    --changes under an OPEN window (see refreshPanelTabs): the chip and
    --the tab's content both go. Never a user gesture -- there is no
    --per-tab close control; the folder is the tab set.
    local RemoveTab = function(key)
        local tab, index = FindTab(key)
        if tab == nil then
            return
        end
        table.remove(m_tabs, index)
        if tab.chip ~= nil and tab.chip.valid then
            tab.chip:DestroySelf()
        end
        if tab.wrapper ~= nil and tab.wrapper.valid then
            tab.wrapper:DestroySelf()
        end
        SyncDialogTabs()
        --the active tab going away hands the window to its neighbour.
        if m_activeKey == key then
            m_activeKey = nil
            local fallback = m_tabs[index] or m_tabs[index - 1] or m_tabs[1]
            if fallback ~= nil then
                SwitchTab(fallback.key)
            end
        end
    end

    tabStrip = gui.Panel{
        --leaves room for the right-side chrome: headerControls floats at
        --x -6 and runs about 40px wide (pin 14 + its 6 margin + x 18),
        --so 52 clears it with a small gap. The popout button adds itself
        --to the same row (16 + its 6 margin), so allow 22 more when the
        --hosting flow supplies that gesture.
        width = cond(args.popout ~= nil, "100%-74", "100%-52"),
        height = "auto",
        flow = "horizontal",
        wrap = true,
        halign = "left",
        valign = "center",
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

        --keep the content area (and a shaded window's height) tracking the
        --header's real height as chip rows come and go.
        syncPanelHeader = function(element)
            --fit pass first: compaction changes chip widths, which
            --changes the wrap and therefore the height measured below.
            --When it changed anything, wait out a layout pass and
            --re-enter with settled measurements.
            if SyncChipCompaction ~= nil and SyncChipCompaction() then
                element:ScheduleEvent("syncPanelHeader", 0.05)
                return
            end
            local h = HeaderHeight()
            if contentArea ~= nil and contentArea.valid then
                contentArea.selfStyle.height = string.format("100%%-%d", h + 1)
            end
            if m_shaded then
                SetWindowHeight(h + 2)
            end
        end,

        tabStrip,
        headerControls,
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

    --The FOCUS EDGE: a bright accent line down the window's left side
    --while this window's content holds the GUI focus -- the docks'
    --dockPanelFocusOutline treatment, restored to the rail windows
    --(David 2026-08-15). It was removed with the tab-strip rework in
    --favor of the header chip's "armed" accent; both live now -- the
    --chip names WHICH tab is armed, the edge is the at-a-glance "this
    --window is the active one" a name cannot give from peripheral
    --vision. A floating child rather than a border on the window root:
    --the root's border is set inline and selfStyle beats class styles.
    local focusEdge = gui.Panel{
        classes = {"panelWindowFocusEdge"},
        bgimage = true,
        floating = true,
        interactable = false,
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        --the one-sided border is INLINE: a border TABLE in a styles list
        --verifiably never reaches the panel (scalar properties do; see
        --the dock's copy in DockablePanel.lua). Color and opacity still
        --come from the panelWindowFocusEdge rules, so theming is intact.
        border = {x1 = 4, x2 = 0, y1 = 0, y2 = 0},
    }

    --ARMED indication lives in the HEADER now -- see SyncArmedState and
    --the panelDocumentTitle "armed" style. The old
    --4px accent edge down the window's left side is gone: it sat in
    --peripheral vision, away from the identity the user reads a window
    --by, and it lit for EVERY focused window even though only five
    --registrations (Map Markup, Objects, the two Terrain panels, the
    --Measuring Tool) gate any behavior on focus -- so most of the time it
    --announced nothing and taught people to stop looking at it.

    --The window ROOT already rounds itself: it carries the `framedPanel`
    --class and its styles snapshot is the theme's, so a rounded theme's
    --cornerRadius reaches it through the ordinary cascade. What does not
    --follow is the chrome painted ON TOP of it -- the header strip is an
    --opaque @bgAlt panel spanning the full width, so under a rounded theme
    --it sat square across the window's rounded top corners (and overhung
    --them). Anything covering a themed surface has to state the same
    --radius, which means reading the number out of the theme rather than
    --letting the cascade apply it.
    --
    --Only a plain number is turned into a top-corner pair; a theme
    --expressing framedPanel's radius per-corner or as a dimension string
    --(e.g. "50% height") leaves the header square rather than guessing at
    --a rounding that would not match the root. Non-tabbed hosts (a panel
    --rendered as a tab inside the journal viewer) leave it square too --
    --there the header sits in the middle of somebody else's window, not
    --along its top edge.
    local themeCornerRadius = ThemeEngine.ResolveStyleProperty({"framedPanel"}, "cornerRadius", 0)
    local headerCornerRadius = 0
    if tabbed and type(themeCornerRadius) == "number" and themeCornerRadius > 0 then
        headerCornerRadius = {x1 = themeCornerRadius, y1 = themeCornerRadius, x2 = 0, y2 = 0}
    end

    resultPanel = gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",

        --Escape closes the ENTIRE window -- one gesture, one window --
        --leaving the rail's records (keep-open, folders) untouched so
        --the arrangement comes back intact on reopen. The chip x has its
        --kind-default escape activation disabled: as the newest listener
        --it won the escape race. Pinned windows clear captureEscape in
        --SyncPinnedState.
        captureEscape = tabbed,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            if Pinned() then
                return
            end
            --THE PANEL GETS FIRST REFUSAL. A panel holding a mode the user
            --would expect Escape to leave -- an armed map tool, a half-made
            --placement -- claims the press by setting claimed on the table
            --it is handed, and the window stays open. Without this the
            --window's own capture wins the race outright and a single
            --Escape closes the whole thing out from under a user who only
            --meant to put their tool down.
            --
            --A table rather than a return value because this travels as a
            --FireEventTree, which fans out to every handler and discards
            --what they return. Only the ACTIVE tab is asked: a background
            --tab's mode is not on screen to be escaped from.
            local tab = FindTab(m_activeKey)
            if tab ~= nil and tab.contentRoot ~= nil and tab.contentRoot.valid then
                local claim = {claimed = false}
                tab.contentRoot:FireEventTree("panelEscape", claim)
                if claim.claimed then
                    return
                end
            end
            if args.escapeClose ~= nil then
                args.escapeClose()
            elseif args.close ~= nil then
                args.close()
            elseif dialog ~= nil and dialog.valid then
                dialog:DestroySelf()
            end
        end,

        --Press anywhere on the window -- its title bar, an empty stretch of
        --content -- claims focus for the active tab's panel, when that
        --panel asked for it. Driven by the dialog rather than by our own
        --`press`: presses on the header propagate UP to us, but presses on
        --empty pane space never reach us at all (see the dialog's press
        --handler), so the dialog catches both and fires this downward.
        hostPanelPressed = function(element)
            FocusActiveTab()
        end,

        thinkTime = 0.25,
        think = function(element)
            if not tabbed then
                return
            end
            --GUI focus, and nothing else -- singular by construction, so
            --exactly one panel can be the active tool. See the dock's copy.
            --
            --The focus EDGE lights for ANY focused window, matching the
            --dock's behavior: it answers "which window is active", not
            --"which panel is armed".
            local focused = gui.ChildHasFocus(element)
            if focusEdge.valid then
                focusEdge:SetClass("focused", focused)
            end
            --The chip accent stays GATED on the active tab actually CARING
            --about focus: only a focusOnClick panel has a map mode riding
            --on it, and naming an armed tool on a window with no tool made
            --the signal ambient and therefore unreadable.
            local active = focused
            if active then
                local tab = FindTab(m_activeKey)
                if tab == nil or tab.reg == nil or not tab.reg.focusOnClick then
                    active = false
                end
            end
            if element.data.hasPanelFocus ~= active then
                element.data.hasPanelFocus = active
                SyncArmedState(active)
            end
        end,

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
                --top corners only: the strip is flush with the window's top
                --edge, and the hairline plus the content area below it are
                --square. Shading the window rolls it up to header + 2px, so
                --the root's own rounded bottom is what shows there.
                cornerRadius = headerCornerRadius,
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
                --the name slot animates: collapsing/uncollapsing this
                --label is how a chip sheds or grows its name (on hover
                --and on tab switch), and transitionTime is what makes
                --that a slide out of the icon rather than a snap.
                transitionTime = 0.15,
            },
            {
                selectors = {"label", "panelDocumentTitle", "parent:selected"},
                color = "@fgStrong",
                bold = true,
            },
            --...and the armed panel's own NAME goes accent with the rule.
            --Only the active chip is ever given "armed", so this names
            --WHICH panel in the folder is taking map clicks -- "something
            --in this window is armed" would not be enough with a whole
            --folder on the strip. Priority outranks parent:selected,
            --which sets the colour this has to win.
            {
                selectors = {"label", "panelDocumentTitle", "parent:armed"},
                color = "@accent",
                bold = true,
                priority = 10,
            },
            --The focus edge. Repeated here rather than inherited from
            --DefaultStyles (where the docks' copy lives): panels on the
            --documents layer do NOT get that global cascade, which is
            --exactly why everything here carries its own `styles`. Without
            --these two rules the edge panel exists, sits in the right
            --place, and draws nothing at all.
            {
                selectors = {"panelWindowFocusEdge"},
                bgcolor = "clear",
                borderColor = "@accent",
                opacity = 0,
                transitionTime = 0.15,
            },
            {
                selectors = {"panelWindowFocusEdge", "focused"},
                opacity = 1,
            },
            --the pin toggle: nearly invisible at rest so it does not
            --compete with the tabs, lifting on hover and staying lit
            --(and upright rather than tilted) while the window is pinned.
            {
                selectors = {"panelDocumentPinButton"},
                bgcolor = "@fgMuted",
                opacity = 0.35,
                rotate = 45,
                transitionTime = 0.15,
            },
            {
                selectors = {"panelDocumentPinButton", "hover"},
                opacity = 1,
                bgcolor = "@fgStrong",
            },
            {
                selectors = {"panelDocumentPinButton", "pinned"},
                opacity = 1,
                bgcolor = "@fgStrong",
                rotate = 0,
            },
            --the corner close x: the phosphor glyph tinted like the rest
            --of the chrome -- present but calm at rest, full-strength on
            --hover (STYLE_GUIDE icon states).
            {
                selectors = {"panelDocumentCloseButton"},
                bgcolor = "@fg",
                opacity = 0.7,
                transitionTime = 0.15,
            },
            {
                selectors = {"panelDocumentCloseButton", "hover"},
                opacity = 1,
                bgcolor = "@fgStrong",
            },
            --Tab content fades up when its tab is switched to, so the
            --swap is not a hard cut while the chip beside it animates.
            --Asymmetric on purpose: the transitionTime lives on the
            --VISIBLE rule only, so going transparent is instantaneous
            --(the outgoing tab collapses in the same frame -- animating
            --it would just composite two panels for no benefit) while
            --coming back is a ramp.
            {
                selectors = {"panelDocumentTabContent"},
                opacity = 1,
                transitionTime = 0.12,
            },
            {
                selectors = {"panelDocumentTabContent", "fading"},
                opacity = 0,
                transitionTime = 0,
            },
            --The chip's hover name. It wears the CHIPS' own plate -- same
            --cornerRadius and clear border, one step up the fill ladder
            --(@bgAlt, what a selected chip uses) so it reads against the
            --panel content it covers. Plain text alone lost its fight
            --with whatever sat under it, and matching the chips keeps it
            --from reading as a foreign tooltip.
            --
            --NO transitionTime: it appears outright. The dwell delay
            --before it shows (see the chip's revealTabName) is what stops
            --names strobing across a sweep; a fade on top of that just
            --made the name feel slow to arrive.
            --
            --Driven by an explicit "shown" class rather than parent:hover
            --because that dwell cannot be expressed as a style state.
            {
                selectors = {"label", "panelDocumentTabLabel"},
                opacity = 0,
                bgcolor = "@bgAlt",
                border = 1,
                borderColor = "clear",
                cornerRadius = 4,
                color = "@fgStrong",
                fontSize = 12,
                bold = true,
            },
            {
                selectors = {"label", "panelDocumentTabLabel", "shown"},
                opacity = 1,
            },
            --pinned: the window cannot be closed, so the x stays put and
            --fades back to read as unavailable. @fgMuted rather than a
            --dimmer @fg -- it is the token for de-emphasized/disabled
            --foreground (DefaultStyles.md), and it is what dropdown
            --options and other disabled chrome already dim to, so the
            --state matches the rest of the app instead of just being
            --faint. Listed AFTER the hover rule and repeating the muted
            --values so hovering a pinned x does not light it up like a
            --live control.
            {
                selectors = {"panelDocumentCloseButton", "disabled"},
                opacity = 0.2,
                bgcolor = "@fgMuted",
            },
            {
                selectors = {"panelDocumentCloseButton", "disabled", "hover"},
                opacity = 0.2,
                bgcolor = "@fgMuted",
            },
        }),

        --Bring one of this window's tabs to the front. Fired when an
        --already-open folder window is asked for a panel it hosts (the
        --rail button, a strip member, the panel-open handler): the
        --window raises and switches rather than opening anything.
        selectPanelTab = function(element, key)
            if key == nil then
                return
            end
            SwitchTab(string.lower(key))
        end,

        --The folder's membership changed while this window was open.
        --The tab set IS the folder, so reconcile in place: add chips for
        --new members, drop chips for departed ones, and keep the window
        --standing. Closing and rebuilding would be simpler but makes a
        --rail drag blink every affected window shut.
        refreshPanelTabs = function(element)
            if not tabbed then
                return
            end
            local wanted = PanelDocument.FolderTabs(string.lower(self.panelName))
            local keep = {}
            for _, k in ipairs(wanted) do
                keep[k] = true
                AddTab(k, true)
            end
            --iterate a copy: RemoveTab mutates m_tabs.
            local present = {}
            for _, t in ipairs(m_tabs) do
                present[#present + 1] = t.key
            end
            for _, k in ipairs(present) do
                if not keep[k] then
                    RemoveTab(k)
                end
            end
            --re-order the chips to the folder's order: AddTab appends,
            --so a member inserted in the middle of the strip would
            --otherwise land at the end.
            for _, k in ipairs(wanted) do
                local t = FindTab(k)
                if t ~= nil and t.chip ~= nil and t.chip.valid then
                    t.chip:SetAsLastSibling()
                end
            end
            SyncChipCompaction()
            if header ~= nil and header.valid then
                header:ScheduleEvent("syncPanelHeader", 0.05)
            end
        end,

        --a user gesture that SHOWS a panel (rail icon, group flyout, the
        --panel-open handler) wants a map-mode panel ARMED, not just
        --visible: this claims focus for the panel when it is a
        --focusOnClick panel. Session restores never fire it -- a pinned
        --Map Markup window coming back at load must not silently put
        --the app into markup mode.
        --
        --A key naming a tab that is not active switches to it first: the
        --gesture asked for THAT panel, and with folder windows the panel
        --asked for is often a background tab.
        focusPanelTab = function(element, key)
            if key ~= nil then
                key = string.lower(key)
                if FindTab(key) == nil then
                    return
                end
                SwitchTab(key)
            end
            FocusActiveTab()
        end,
        --"/" pressed with no chat input on screen (RailSlashOpensChat):
        --this window IS the chat window, so hand the keystroke to its
        --input. The input may not exist yet -- a freshly opened window
        --builds a tick later -- so record the intent and let the build
        --complete it, the same way focus grabs work.
        slashChat = function(element)
            local tab = FindTab("chat")
            if tab == nil then
                return
            end
            SwitchTab("chat")
            if tab.contentRoot ~= nil and tab.contentRoot.valid then
                tab.contentRoot:FireEventTree("slash")
            else
                tab.slashWhenBuilt = true
            end
        end,
        --the window's pin state changed (from its own toggle or from the
        --rail's context menu): re-sync the chrome it governs.
        refreshPanelPinned = function(element)
            SyncPinnedState()
        end,

        header,
        hairline,
        contentArea,
        focusEdge,
    }

    --The window's tab set IS its folder: every panel filed under this
    --one gets a chip up front, opened or not, so the strip is a complete
    --quick-switcher for the folder and the membership the user arranged
    --on the rail is what they see. A panel owning no folder is simply a
    --one-tab window. Only the standalone window is tabbed -- hosted
    --inside a foreign dialog (a journal viewer tab) a panel is alone.
    --
    --Every chip is added quiet and exactly one is then activated, so
    --only the panel actually being shown builds its content; the rest
    --stay unbuilt until their chip is clicked.
    local ownKey = string.lower(self.panelName)
    if tabbed then
        for _, memberKey in ipairs(PanelDocument.FolderTabs(ownKey)) do
            AddTab(memberKey, true)
        end
    else
        AddTab(ownKey, true)
    end
    local startKey = args.activeKey
    if startKey ~= nil then
        startKey = string.lower(startKey)
    end
    if startKey == nil or FindTab(startKey) == nil then
        startKey = ownKey
    end
    SwitchTab(startKey)
    SyncChipCompaction()
    m_constructing = false
    SyncPinnedState()

    --a USER-initiated open (rail icon press, context menu, panel-open
    --handler) of a map-mode panel arms it the moment it is constructed.
    --The content is still a tick away (deferred build), so this records
    --the grab and the build completes it. Restores never pass autoFocus.
    if args.autoFocus then
        FocusActiveTab()
    end

    return resultPanel
end

----------------------------------------------------------------------
-- Panel icon rail
-- ---------------
-- Experimental alternative host for the dockable panels: translucent
-- icon rails down the left and right edges of the screen. Clicking an
-- icon opens the panel in a document window beside the rail (one such
-- "transient" window at a time); dragging a window makes it stick where
-- it lands, and any number of stuck windows can stay open. Which windows
-- are open and where persists per game. Windows are single-panel;
-- related panels are organized into rail FOLDERS (see GROUPS above),
-- each opening its own window from the folder's hover strip.
--
-- A window can also be PINNED (the push-pin in its title bar, or the
-- rail button's context menu): a pinned window is locked in place -- no
-- close, no drag, no resize -- and always comes back with the rails.
--
-- Off by default; opted into per-user from Settings > General ("New
-- Experimental UI"), or via /toggle iconrail. The dock system is
-- untouched while the rail is off; while it is on, each side's dock is
-- slid away and its handle tab hidden, so the rails are the way panels
-- are reached (the Panels menu still toggles the docks).
----------------------------------------------------------------------

--forward-declared (defined next to SyncDockHandles): slides the docks
--off screen when the rail mode turns on and back on screen when it
--turns off.
local SyncDocksToRailMode

setting{
    id = "iconrail",
    description = "New Experimental UI",
    help = "Experimental: replace the side docks with icon rails on the screen edges, and summon panels as floating windows from them.",
    storage = "preference",
    editor = "check",
    default = false,
    onchange = function()
        if mod.unloaded then
            return
        end
        --docks first, so the rails built below see the updated dock
        --visibility and come up uncollapsed immediately (syncDockMode
        --reads the dock settings at rail create).
        if SyncDocksToRailMode ~= nil then
            SyncDocksToRailMode()
        end
        EnsureIconRail()
    end,
}

--Which rail windows are open and where, for this game:
--{ [panelKey] = {x = ..., y = ..., width = ..., height = ...} }.
--Restored when the rails come up. width/height are optional (records
--predating them restore at the panel's default size). Records written
--before rail folders replaced tabbed windows may also carry a `tabs`
--list; nothing reads it any more except the key-rename migration.
--NOTE the setting id is a legacy name: these are NOT the user-facing
--"pinned" windows (that is PanelDocument.IsPinned -- locked in place).
--The id is kept so existing arrangements and saved Views still load.
setting{
    id = "iconrailpins",
    storage = "pergamepreference",
    default = {},
}

--Which panels are popped out into native OS windows, and where:
--{ [panelKey] = {x = ..., y = ..., width = ..., height = ..., session = ...} }.
--x/y are the OS window's top-left in SCREEN pixels (reported by the
--companion); width/height are panel units, same space as the iconrailpins
--records. session identifies the app run that wrote the record (see
--popoutsessionid below): the rails-up sweep only reopens records stamped
--by THIS run and prunes the rest, so popouts survive a mid-session Lua
--reload but deliberately do NOT come back when the app is relaunched.
--Cleared by the deliberate close gestures (pop-in, escape, the OS close
--button) and by the startup prune -- never by teardown (Lua reload).
setting{
    id = "popoutwindows",
    storage = "pergamepreference",
    default = {},
}

--This app run's identity stamp for popout records. Transient settings
--live in engine memory: the value survives Lua reloads but dies with
--the process, which is exactly the lifetime popout auto-restore should
--have. Lazily minted by PopoutSessionId().
setting{
    id = "popoutsessionid",
    storage = "transient",
    default = "",
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

--User-defined TOOLKITS: floating horizontal strips of tool buttons,
--opened from a rail button of their own ("toolkit:<id>" layout keys).
--v1 items are panel buttons ({type = "panel", panel = <lowercase panel
--name>}); items carry an explicit `type` so later versions can add
--action buttons and live widgets (Spend Recovery, stamina bars) without
--a data migration. Keyed by toolkit id:
--{ [id] = { name, items = {...}, x, y } } -- x/y is where the strip
--last sat, so it reopens where the user left it.
setting{
    id = "iconrailtoolkits",
    storage = "pergamepreference",
    default = {},
}

--Standalone script BUTTONS: single custom buttons living directly on
--the rail ("button:<id>" layout keys), no toolkit required (owner
--decision 2026-08-17: "you shouldn't have to create a new tool panel
--just to create a new button"). Keyed by id:
--{ [id] = { type = "script", name, icon, script, description,
--  pack? (community pack it was added FROM),
--  packid? (pack it is shared TO -- minted by Share Your Buttons) } }
setting{
    id = "iconrailscriptbuttons",
    storage = "pergamepreference",
    default = {},
}

--g_iconRailPanels (the curated panel list) is declared above the
--PanelDocument interface.

----------------------------------------------------------------------
-- Renamed panels
-- -------------
-- Every stored arrangement -- rail slots, groups, open windows, saved
-- views -- keys off the REGISTERED PANEL NAME, so renaming a panel
-- turns each stored occurrence into a dead key. The damage is visible:
-- a dead group member has no registration, so the flyout renders it
-- under its raw key with the fallback icon, while the renamed panel,
-- being curated, auto-places itself back onto the rail as a second
-- button. That is exactly what "Safety Tools" -> "Safety" produced
-- (field report 2026-08-08: both showing at once).
--
-- ADD AN ENTRY HERE WHENEVER YOU RENAME A REGISTERED PANEL. Keys are
-- lowercase, as every stored key is. The rewrite runs on entering a
-- game (EnsureIconRail) and is idempotent -- it writes nothing once
-- there is nothing left to rename.
----------------------------------------------------------------------
local g_railRenamedPanels = {
    ["safety tools"] = "safety",
}

--Rewrite the keys of a stored { [panelKey] = value } table in place.
--When both the old and the new key are present the old one is dropped:
--the entry already under the new name is the live one.
local function RailRenameKeyedTable(t, renames)
    if type(t) ~= "table" then
        return false
    end
    --collected first: assigning a NEW key during a pairs() traversal is
    --undefined in Lua (clearing one is not).
    local hits = nil
    for key in pairs(t) do
        local newKey = type(key) == "string" and renames[string.lower(key)] or nil
        if newKey ~= nil then
            hits = hits or {}
            hits[#hits + 1] = { key, newKey }
        end
    end
    if hits == nil then
        return false
    end
    for _, hit in ipairs(hits) do
        local key, newKey = hit[1], hit[2]
        local value = t[key]
        t[key] = nil
        if t[newKey] == nil then
            t[newKey] = value
        end
    end
    return true
end

--Rewrite a stored list of panel keys (tab lists) in place, dropping any
--duplicate the rename produces.
local function RailRenameKeyList(list, renames)
    if type(list) ~= "table" then
        return false
    end
    local changed = false
    local seen = {}
    local kept = {}
    for _, key in ipairs(list) do
        if type(key) == "string" then
            local newKey = renames[string.lower(key)]
            if newKey ~= nil then
                key = newKey
                changed = true
            end
        end
        if seen[key] then
            changed = true
        else
            seen[key] = true
            kept[#kept + 1] = key
        end
    end
    for i = 1, math.max(#list, #kept) do
        list[i] = kept[i]
    end
    return changed
end

--Dock lists hold DISPLAY names rather than keys, so they match
--case-insensitively and take the renamed panel's registered name.
local function RailRenameNameList(list, renames)
    if type(list) ~= "table" then
        return false
    end
    local changed = false
    for i, name in ipairs(list) do
        if type(name) == "string" then
            local newKey = renames[string.lower(name)]
            if newKey ~= nil then
                local reg = DockablePanel.GetRegistration(newKey)
                list[i] = (reg ~= nil and reg.name) or newKey
                changed = true
            end
        end
    end
    return changed
end

--Rewrite a view layout payload (the shape ViewsCaptureLayout produces).
local function RailRenameLayout(layout, renames)
    if type(layout) ~= "table" then
        return false
    end
    local changed = false
    changed = RailRenameKeyedTable(layout.rail, renames) or changed
    changed = RailRenameKeyedTable(layout.pinned, renames) or changed
    if type(layout.pins) == "table" then
        changed = RailRenameKeyedTable(layout.pins, renames) or changed
        for _, window in pairs(layout.pins) do
            if type(window) == "table" then
                changed = RailRenameKeyList(window.tabs, renames) or changed
            end
        end
    end
    if type(layout.tabs) == "table" then
        changed = RailRenameKeyedTable(layout.tabs, renames) or changed
        for _, tabs in pairs(layout.tabs) do
            changed = RailRenameKeyList(tabs, renames) or changed
        end
    end
    if type(layout.docks) == "table" then
        for _, side in ipairs({"left", "right"}) do
            changed = RailRenameNameList(layout.docks[side], renames) or changed
        end
    end
    return changed
end

--A panel lives in exactly ONE window (SetStoredTabs enforces it). A
--rename can break that invariant -- the renamed panel may already have
--been grouped under its new name somewhere else -- so drop the repeats.
--Which group keeps it is arbitrary when that happens; it cannot be
--anything else, since two groups both claiming it is already wrong.
local function RailDedupeGroupMembership(tabsBySide)
    local changed = false
    local claimed = {}
    for owner, tabs in pairs(tabsBySide) do
        if type(tabs) == "table" then
            local kept = {}
            for _, key in ipairs(tabs) do
                if key == owner or claimed[key] == nil then
                    claimed[key] = owner
                    kept[#kept + 1] = key
                else
                    changed = true
                end
            end
            if #kept <= 1 then
                tabsBySide[owner] = nil
            else
                tabsBySide[owner] = kept
            end
        end
    end
    return changed
end

--Repair every stored arrangement that still names a renamed panel: this
--game's live rail state, its view stashes and update baselines, and the
--account-wide view library. Writes only what actually changed, so it
--settles to a no-op after the first game entry following a rename.
local function RailMigrateRenamedPanels()
    if next(g_railRenamedPanels) == nil then
        return false
    end
    local renames = g_railRenamedPanels
    local anyChanged = false

    --live per-game rail state.
    for _, id in ipairs({"iconraillayout", "iconrailpanelpinned"}) do
        local value = DeepCopy(dmhub.GetSettingValue(id) or {})
        if RailRenameKeyedTable(value, renames) then
            dmhub.SetSettingValue(id, value)
            anyChanged = true
        end
    end

    local windows = DeepCopy(dmhub.GetSettingValue("iconrailpins") or {})
    local windowsChanged = RailRenameKeyedTable(windows, renames)
    for _, window in pairs(windows) do
        if type(window) == "table" then
            windowsChanged = RailRenameKeyList(window.tabs, renames) or windowsChanged
        end
    end
    if windowsChanged then
        dmhub.SetSettingValue("iconrailpins", windows)
        anyChanged = true
    end

    local tabs = DeepCopy(dmhub.GetSettingValue("iconrailtabs") or {})
    local tabsChanged = RailRenameKeyedTable(tabs, renames)
    for _, list in pairs(tabs) do
        tabsChanged = RailRenameKeyList(list, renames) or tabsChanged
    end
    if tabsChanged then
        RailDedupeGroupMembership(tabs)
        dmhub.SetSettingValue("iconrailtabs", tabs)
        anyChanged = true
    end

    --this game's per-view working stashes.
    local stash = DeepCopy(dmhub.GetSettingValue("viewsstash") or {})
    local stashChanged = false
    for _, layout in pairs(stash) do
        stashChanged = RailRenameLayout(layout, renames) or stashChanged
    end
    if stashChanged then
        dmhub.SetSettingValue("viewsstash", stash)
        anyChanged = true
    end

    --the built-in update baselines. These MUST be migrated alongside the
    --live state: the on-entry update check compares the two, and a
    --baseline left un-renamed would read as "the user rearranged this"
    --and raise a take-it/keep-mine prompt over our own repair.
    local stamps = DeepCopy(dmhub.GetSettingValue("viewsbuiltinversion") or {})
    local stampsChanged = false
    for _, rec in pairs(stamps) do
        if type(rec) == "table" then
            stampsChanged = RailRenameLayout(rec.layout, renames) or stampsChanged
        end
    end
    if stampsChanged then
        dmhub.SetSettingValue("viewsbuiltinversion", stamps)
        anyChanged = true
    end

    --the account-wide view library (personal overlays and customs),
    --which follows the user into every other game.
    local lib = DeepCopy(dmhub.GetSettingValue("viewslibrary") or {})
    local libChanged = false
    for _, entry in pairs(lib) do
        if type(entry) == "table" then
            libChanged = RailRenameLayout(entry.layout, renames) or libChanged
        end
    end
    if libChanged then
        dmhub.SetSettingValue("viewslibrary", lib)
        anyChanged = true
    end

    return anyChanged
end

local ICON_RAIL_BUTTON = 40
local ICON_RAIL_GAP = 8
local ICON_RAIL_LEFT = 12
local ICON_RAIL_TOP = 64
--the group-shadow image (core cloud asset, uploaded 2026-08-08): a
--40x40 rounded card with the rail button's own silhouette subtracted
--at the (-5,+5) stack offset, so the shadow's inner edge follows the
--button's rounded corner instead of its bounding box. White shape,
--tinted by the iconRailGroupShadow style's bgcolor. Authored for the
--LEFT rail; the right rail mirrors it with a negative x scale.
local ICON_RAIL_GROUP_SHADOW_IMAGE = "f4955b26-d987-418e-9706-b1e90c7cbf49"
--the rearrange-mode trash zone: larger than a button so it reads as a
--zone rather than another slot, floated at the very bottom of the column.
local ICON_RAIL_TRASH = 60

--the two rails, keyed "left"/"right".
local g_iconRails = {}
--the panel key of the current click-opened window -- the one that closes
--when the next icon is clicked. Shared across both rails: there is one
--transient window, whichever side it was summoned from.
local g_railTransientKey = nil
--set when a button drag ends, so the click the engine may deliver on
--release does not also toggle a window.
local g_railDragTime = nil
--the layout key that just landed from a drop: the rebuild marks that
--button "justDropped" so it settles in with a scale-down animation.
local g_railJustDropped = nil
--rail button hover/press sounds stand down until this time; stamped by
--DestroyIconRails so a rebuild under the cursor does not tick (see
--RailButtonSound).
local g_railSoundQuietUntil = nil
--The one group strip currently slid open, as {owner = <button panel>,
--close = <fn>}. Leaving a button closes its strip on a short deferred
--timer (the grace period that lets the pointer reach INTO the strip
--without shutting it), but that grace is pure lag when the pointer has
--already landed on a different button -- two strips were visible at once
--for those frames. So arriving on any rail button shuts the previous
--strip synchronously, before its own opens.
local g_railOpenFlyout = nil
--How long a strip survives the pointer leaving it. This only has to
--bridge the frame in which the pointer is between the owner button and
--its own strip (they are flush, so that is at most a frame or two) --
--anything longer is a visible hang after the pointer has moved on.
local RAIL_FLYOUT_CLOSE_GRACE = 0.05
--Close the open strip unless it belongs to `owner` (re-entering the
--button that owns it must not shut it).
local function RailCloseOpenFlyout(owner)
    local entry = g_railOpenFlyout
    if entry == nil or entry.owner == owner then
        return
    end
    g_railOpenFlyout = nil
    entry.close()
end
--Drop the registration when a strip closes by any other route, so a
--later hover elsewhere does not try to close an already-closed strip.
local function RailForgetOpenFlyout(owner)
    if g_railOpenFlyout ~= nil and g_railOpenFlyout.owner == owner then
        g_railOpenFlyout = nil
    end
end
--forward-declared: button drag handlers, and anything that changes which
--buttons exist (grouping), rebuild the rails.
local RebuildIconRails

--DEV GATE for the entire Panel Library feature: the rail's + button
--and everything only it opens (the library window, community
--spotlight/browser, and the Share Your Buttons dialog). The + shipped
--WITH the library (commit 142fa78e), so gating the button gates the
--whole surface; the rail's right-click menu is older and stays. No
--`editor`, so it appears on no settings screen -- flip it from the
--console: dmhub.SetSettingValue("dev:panellibrary", true).
setting{
    id = "dev:panellibrary",
    storage = "preference",
    default = false,
    onchange = function()
        if RebuildIconRails ~= nil then
            RebuildIconRails()
        end
    end,
}

--The open-window record (see the "iconrailpins" setting above): which
--panel windows to restore, and where. Named for what it does, not for
--the legacy setting id -- "pinned" now means locked in place, which is
--PanelDocument.IsPinned. (Old records may carry a `tabs` list from the
--retired tabbed-window era; it is simply ignored.)
local function RailRestoreWindows()
    return dmhub.GetSettingValue("iconrailpins") or {}
end

local function SetRailRestoreWindows(windows)
    dmhub.SetSettingValue("iconrailpins", windows)
end

--The window size worth recording alongside a placement: the doc's
--session-remembered geometry, if it has one. Read from _tmp_location
--rather than the live dialog because the shade toggle keeps its height
--the full, un-rolled-up one. nil when the window was never dragged or
--resized this session -- the caller falls back to what the record
--already holds, and a restore falls back to the panel defaults.
local function RailWindowSize(doc)
    local loc = nil
    if doc ~= nil then
        loc = doc:try_get("_tmp_location")
    end
    if loc == nil then
        return nil, nil
    end
    return loc.width, loc.height
end

--Record (or forget) an open window's placement, so it comes back next
--time the rails are built. doc (optional) contributes the window's size
--to the record; a placement with no fresh size to offer -- e.g. keep-open
--on a window untouched since it was restored -- keeps the recorded one.
--
--Records are keyed by the panel that OWNS the window. A folder is one
--window hosting the whole folder, so recording a member key would
--restore a window that panel does not have -- which also means the size
--lookup below has to happen AFTER the key is resolved, or a member would
--inherit sizes from a record nobody writes.
local function RailRememberWindow(key, x, y, doc)
    key = PanelDocument.WindowOwner(key)
    local windows = RailRestoreWindows()
    local width, height = RailWindowSize(doc)
    local prev = windows[key]
    if type(prev) == "table" then
        width = width or prev.width
        height = height or prev.height
    end
    local record = { x = x, y = y, width = width, height = height }
    --remember which tab was on screen, so a folder window comes back
    --showing the panel the user left it on rather than always its owner.
    local ownerDoc = RailPanelDocument(key)
    if ownerDoc ~= nil then
        local dialog = ownerDoc:try_get("_tmp_dialog")
        if dialog ~= nil and dialog.valid then
            pcall(function() record.tab = dialog.data.activePanelTab end)
        end
    end
    windows[key] = record
    SetRailRestoreWindows(windows)
    if g_railTransientKey == key then
        g_railTransientKey = nil
    end
end

--A resize keeps a remembered window's recorded size current. It never
--CREATES a record: only a real placement (a drag, keep-open, tabs) makes
--a window stick, exactly as for position.
local function RailRememberWindowSize(key, doc)
    local windows = RailRestoreWindows()
    local w = windows[key]
    if type(w) ~= "table" then
        return
    end
    local width, height = RailWindowSize(doc)
    if width == nil and height == nil then
        return
    end
    w.width = width or w.width
    w.height = height or w.height
    SetRailRestoreWindows(windows)
end

local function RailForgetWindow(key)
    key = PanelDocument.WindowOwner(key)
    local windows = RailRestoreWindows()
    if windows[key] ~= nil then
        windows[key] = nil
        SetRailRestoreWindows(windows)
    end
    if g_railTransientKey == key then
        g_railTransientKey = nil
    end
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

--the height of the rail's coordinate space, measured the same way (the
--layer is ~1048 units tall, not 1080; see IconRailUIWidth).
local function IconRailUIHeight()
    if GameHud.instance ~= nil and GameHud.instance.documentsPanel ~= nil and GameHud.instance.documentsPanel.valid then
        local h = GameHud.instance.documentsPanel.renderedHeight
        if type(h) == "number" and h > 100 then
            return h
        end
    end
    return 1080
end

--Buttons occupy SLOTS on their rail: a sparse column where empty slots
--render as gaps, so users can leave blank spots between buttons. Slot
--pitch is one button plus one gap. MAX_SLOT is the rearrange-drop clamp:
--slot 16 bottoms out around y=924 in the ~1048-unit-tall layer, keeping
--every droppable slot clear of the trash zone at the column's foot.
local ICON_RAIL_MAX_SLOT = 16

--Style directives a script button's Lua code can carry (they are shown
--to authors in SCRIPT_BUTTON_TEMPLATE): comment lines of the form
--"-- @directive value", each at the START of its line -- anchoring is
--what keeps the template's indented example lines inert. Parsed with
--string matching only, never executed, so buttons downloaded from
--community packs style safely. Unknown directives and out-of-range
--values are ignored.
--  @slots N               rail slots the button spans, like a character card (1-4)
--  @bgcolor #rrggbb       the button face's background color (also #rrggbbaa)
--  @bggradient #c1 #c2    top-to-bottom background gradient
--  @opacity 0..1          the button's overall opacity
--  @label <goblinscript>  a live value shown INSTEAD of the icon,
--                         evaluated against the player's current
--                         character (a formula, not Lua -- which is
--                         what keeps render-time evaluation safe)
local function ScriptButtonHexColor(c)
    return c ~= nil and (string.match(c, "^#%x%x%x%x%x%x$") ~= nil or string.match(c, "^#%x%x%x%x%x%x%x%x$") ~= nil)
end

local function ScriptButtonStyle(def)
    local style = { slots = 1 }
    if type(def) ~= "table" or type(def.script) ~= "string" then
        return style
    end
    for line in string.gmatch(def.script, "[^\r\n]+") do
        local key, value = string.match(line, "^%s*%-%-%s*@(%w+)%s+(.-)%s*$")
        if key == nil then
            --the BARE form, matching the engine's own @if preprocessor
            --style; ScriptButtonCode comments these lines out before the
            --code reaches the Lua parser.
            key, value = string.match(line, "^%s*@(%w+)%s+(.-)%s*$")
        end
        --value is the whole rest of the line; single-token directives
        --take its first word so trailing commentary stays harmless.
        local tok = nil
        if value ~= nil then
            tok = string.match(value, "^%S+")
        end
        if key == "slots" then
            local n = tonumber(tok)
            if n ~= nil then
                style.slots = math.max(1, math.min(4, math.floor(n)))
            end
        elseif key == "bgcolor" then
            if ScriptButtonHexColor(tok) then
                style.bgcolor = tok
            end
        elseif key == "bggradient" then
            local c1, c2 = string.match(value, "^(%S+)%s+(%S+)")
            if ScriptButtonHexColor(c1) and ScriptButtonHexColor(c2) then
                style.gradient = { c1, c2 }
            end
        elseif key == "opacity" then
            local o = tonumber(tok)
            if o ~= nil then
                style.opacity = math.max(0.05, math.min(1, o))
            end
        elseif key == "label" then
            if value ~= nil and value ~= "" then
                style.label = value
            end
        end
    end
    return style
end

--A script button's code as the Lua parser should see it: BARE directive
--lines ("@slots 2" with no leading --) are commented out, the same way
--LuaPreprocessor.cs handles the engine's @if directives. Line count is
--preserved, so error line numbers still match the author's file. The
--comment form needs no help; every load of a button's script must go
--through here so the bare form never reaches the parser as syntax.
local function ScriptButtonCode(script)
    if type(script) ~= "string" then
        return script
    end
    --[ \t] rather than %s: %s matches newlines, so with a blank line
    --before a directive the "--" landed on the blank line instead.
    script = string.gsub(script, "^([ \t]*@%w+)", "--%1")
    script = string.gsub(script, "\n([ \t]*@%w+)", "\n--%1")
    return script
end

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
        --"character:<charid>" entries are character panels,
        --"toolkit:<id>" entries are user-defined toolkit strips,
        --"button:<id>" entries are standalone script buttons;
        --anything else is a registered panel.
        local available
        local docid = string.match(key, "^doc:(.+)$")
        local charid = string.match(key, "^character:(.+)$")
        local toolkitid = string.match(key, "^toolkit:(.+)$")
        local sbuttonid = string.match(key, "^button:(.+)$")
        local sbuttonSpan = 1
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
        elseif toolkitid ~= nil then
            local tk = (dmhub.GetSettingValue("iconrailtoolkits") or {})[toolkitid]
            available = tk ~= nil
            if available then
                displayName = tk.name or "Toolkit"
            end
        elseif sbuttonid ~= nil then
            local def = (dmhub.GetSettingValue("iconrailscriptbuttons") or {})[sbuttonid]
            available = type(def) == "table"
            if available then
                displayName = def.name or "Button"
                sbuttonSpan = ScriptButtonStyle(def).slots
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
        --character entries render as a CARD spanning two slots (portrait +
        --stamina + hero resources) rather than a one-slot icon button.
        --script buttons can ask for extra slots via the @slots directive.
        --span is derived here, never persisted: the stored layout stays
        --{side, slot} for every entry.
        local span = 1
        if charid ~= nil then
            span = 2
        elseif sbuttonid ~= nil then
            span = sbuttonSpan
        end
        list[#list + 1] = { key = key, name = displayName, slot = slot, ord = ord, docid = docid, charid = charid, toolkitid = toolkitid, sbuttonid = sbuttonid, span = span }
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

    --GROUPED panels lose their own button: the owner's button carries
    --them. Only when that owner actually has a button here -- otherwise
    --the member would have no way in at all. Done BEFORE the slot
    --resolution below and routed through `inert`, so a member keeps its
    --STORED slot (nil included) and drops straight back into it when
    --the group breaks up -- but never occupies a slot meanwhile. When
    --this ran after resolution, hidden members consumed slots (slotless
    --ones were even assigned the lowest free slots below the rail), and
    --a button dropped into such a phantom-occupied "open" slot collided
    --on the next rebuild and bumped one space down (field report
    --2026-08-08: bottom drops landing one too far).
    local owners = PanelDocument.GroupOwners()
    if next(owners) ~= nil then
        local onRail = {}
        for _, sideList in pairs(sides) do
            for _, e in ipairs(sideList) do
                onRail[e.key] = true
            end
        end
        for sideName, sideList in pairs(sides) do
            local kept = {}
            for _, e in ipairs(sideList) do
                local owner = owners[e.key]
                if owner ~= nil and onRail[owner] then
                    inert[#inert + 1] = { key = e.key, side = sideName, slot = e.slot }
                else
                    kept[#kept + 1] = e
                end
            end
            sides[sideName] = kept
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
        --Sparse column: entries KEEP their stored slots, so empty slots
        --render as gaps and rearrange mode can drop into them (the
        --dense-list experiment that repacked from the top is retired --
        --blank spots are part of the layout again). Slot collisions bump
        --downward to the next free slot; legacy/default entries (ord, no
        --slot) fill the lowest free slots in order.
        --Multi-slot entries (character cards) reserve EVERY slot they
        --span, and bump downward until their whole span is free. The
        --simpler single-slot bump logic in the drop paths can briefly
        --store overlapping slots; this pass is the final authority that
        --resolves them, since every rebuild renders through it.
        local used = {}
        local nextFree = 0
        for _, e in ipairs(sideList) do
            local span = e.span or 1
            local s = e.slot
            if s == nil then
                s = nextFree
            end
            local function SpanFree(s0)
                for i = 0, span - 1 do
                    if used[s0 + i] then
                        return false
                    end
                end
                return true
            end
            while not SpanFree(s) do
                s = s + 1
            end
            for i = 0, span - 1 do
                used[s + i] = true
            end
            e.slot = s
            while used[nextFree] do
                nextFree = nextFree + 1
            end
        end
        --a slotless entry may have been assigned a gap ABOVE slotted
        --entries; consumers (button construction's margin chain) need
        --the list in final-slot order.
        table.sort(sideList, function(a, b) return a.slot < b.slot end)
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
    local anchorY = ICON_RAIL_TOP + index * (ICON_RAIL_BUTTON + ICON_RAIL_GAP)
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

--A window pinned from its own title bar is one to bring back, so fold it
--into the restore record (which also stops it being the transient
--window). Unpinning leaves the record alone -- the window is still open,
--and closing it is what forgets it.
g_onPanelPinnedChanged = function(key, pinned)
    if pinned then
        local doc = RailPanelDocument(key)
        local dlg = nil
        if doc ~= nil then
            dlg = doc:try_get("_tmp_dialog")
        end
        if dlg ~= nil and dlg.valid then
            RailRememberWindow(key, dlg.x, dlg.y, doc)
        end
    end
    RefreshRails()
end

--forward-declared: the live drag-preview card ghost. Defined below with
--the rail styling (it needs IconRailStyles); callers here run at event
--time, when the assignments have long since happened.
local ShowRailCardGhost
local HideRailCardGhost

--How far past the screen edge the window must be pushed before it docks.
--Deliberately demanding: merely nearing the rail must not grab the window
--(field feedback: an edge-adjacent band docked far too eagerly). Breaking
--OUT of the screen is an unambiguous gesture -- you cannot leave a window
--usefully parked 60 units off-screen, so nothing legitimate is stolen.
local RAIL_DOCK_OVERSHOOT = 60
--...and the companion signal for drags that grabbed the title bar near a
--corner: there the window's edge can never overshoot (it stops with the
--cursor at the screen edge), but the CURSOR pressed against the edge is
--the same shove-it-into-the-side gesture.
local RAIL_DOCK_CURSOR_EDGE = 6

--The cursor's x in the document layer's units, or nil if it cannot be
--determined. There is no screen-space mouse API in Lua; the world-space
--point mapped through the camera's visible bounds covers the full
--screen, the same mapping TokenWindowPlacement uses.
local function CursorUIX()
    local b = dmhub.cameraBounds
    if b == nil or b.x2 <= b.x1 then
        return nil
    end
    local p = dmhub.GetMouseWorldPoint()
    if p == nil then
        return nil
    end
    return (p.x - b.x1) / (b.x2 - b.x1) * IconRailUIWidth()
end

--Which rail band (if any) a dragged character window position is in,
--and the slot nearest that height. lx/ly is the window's in-flight
--top-left (xdrag/ydrag during a drag, x/y at the drop). The window only
--counts as in a band once it has broken OUT of the screen: its edge
--pushed RAIL_DOCK_OVERSHOOT past the screen edge, or the cursor itself
--pinned against that edge. Returns side, desiredSlot or nil.
local function RailBandTarget(dialog, lx, ly)
    local uiW = IconRailUIWidth()
    local cursorX = CursorUIX()
    local side = nil
    if lx <= -RAIL_DOCK_OVERSHOOT or (cursorX ~= nil and cursorX <= RAIL_DOCK_CURSOR_EDGE) then
        side = "left"
    else
        local w = dialog.renderedWidth
        if type(w) ~= "number" or w <= 0 then
            w = PanelDocument.DefaultWidth
        end
        if lx + w >= uiW + RAIL_DOCK_OVERSHOOT or (cursorX ~= nil and cursorX >= uiW - RAIL_DOCK_CURSOR_EDGE) then
            side = "right"
        end
    end
    if side == nil then
        return nil
    end

    local span = 2
    local pitch = ICON_RAIL_BUTTON + ICON_RAIL_GAP
    local desired = math.floor((ly - ICON_RAIL_TOP) / pitch + 0.5)
    local maxTop = ICON_RAIL_MAX_SLOT - (span - 1)
    if desired < 0 then
        desired = 0
    elseif desired > maxTop then
        desired = maxTop
    end
    return side, desired
end

--The nearest slot to desiredSlot on `side` where a card's full span is
--free, searching outward; entries for excludeKey do not block (a card
--being re-docked should be able to land back on its own spot). Shared
--by the live drag preview and the actual dock so they always agree.
local function RailNearestFreeCardSlot(sides, side, desiredSlot, excludeKey)
    local span = 2
    local maxTop = ICON_RAIL_MAX_SLOT - (span - 1)

    local used = {}
    local maxUsed = -1
    for _, e in ipairs(sides[side]) do
        if e.key ~= excludeKey then
            for i = 0, (e.span or 1) - 1 do
                used[e.slot + i] = true
            end
            if e.slot + (e.span or 1) - 1 > maxUsed then
                maxUsed = e.slot + (e.span or 1) - 1
            end
        end
    end
    local function Fits(s)
        if s < 0 then
            return false
        end
        for i = 0, span - 1 do
            if used[s + i] then
                return false
            end
        end
        return true
    end

    for delta = 0, math.max(maxTop, desiredSlot) + span do
        if Fits(desiredSlot + delta) then
            return desiredSlot + delta
        end
        if delta > 0 and Fits(desiredSlot - delta) then
            return desiredSlot - delta
        end
    end
    return maxUsed + 1
end

--Dock a character card onto a rail at (or as near as possible to) the
--desired slot: removes any existing entry for the key, then lands on
--the nearest position where the card's full span is free.
local function RailDockCharacterCard(key, side, desiredSlot)
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

    local slot = RailNearestFreeCardSlot(sides, side, desiredSlot, key)

    g_railJustDropped = key
    table.insert(sides[side], { key = key, slot = slot })
    SaveRailLayout(sides, inert)
    RebuildIconRails()
end

--Dragging a character panel window into the rail band at the left or
--right screen edge MINIMIZES it: the window closes and the character
--docks into that side's rail as a card, at the slot nearest the drop
--height. Returns true when it consumed the drop (callers skip their
--normal window-stuck bookkeeping). Fired from the window's onMoved,
--which the dialog raises on drag release.
local function MaybeMinimizeCharacterWindow(key, dialog)
    --the drop always retires the live drag preview, docked or not.
    if HideRailCardGhost ~= nil then
        HideRailCardGhost()
    end
    if dialog ~= nil and dialog.valid then
        dialog:SetClass("dockingIntoRail", false)
    end

    if rawget(_G, "RailModeActive") == nil or not RailModeActive() then
        return false
    end
    local charid = string.match(key, "^character:(.+)$")
    if charid == nil then
        return false
    end
    if dialog == nil or not dialog.valid then
        return false
    end

    local side, desired = RailBandTarget(dialog, dialog.x, dialog.y)
    if side == nil then
        return false
    end

    RailDockCharacterCard(key, side, desired)

    RailForgetWindow(key)
    local doc = RailPanelDocument(key)
    if doc ~= nil then
        doc:ClosePanel()
    end
    RefreshRails()
    return true
end

--The live half of the gesture: fires every frame of a character window
--drag. Inside a rail band the window fades to a wisp and a card-shaped
--preview docks into the rail at the slot the drop would use, sliding
--up and down as the drag moves; leaving the band restores the window
--mid-drag, so dragging back out re-emerges the full panel.
local function CharacterWindowDragging(key, dialog)
    if rawget(_G, "RailModeActive") == nil or not RailModeActive() then
        return
    end
    local charid = string.match(key, "^character:(.+)$")
    if charid == nil then
        return
    end
    if dialog == nil or not dialog.valid then
        return
    end

    local lx = dialog.xdrag
    local ly = dialog.ydrag
    if type(lx) ~= "number" or type(ly) ~= "number" then
        lx = dialog.x
        ly = dialog.y
    end

    local side, desired = RailBandTarget(dialog, lx, ly)
    if side == nil then
        if HideRailCardGhost ~= nil then
            HideRailCardGhost()
        end
        dialog:SetClass("dockingIntoRail", false)
        return
    end

    --preview the SLOT the drop will actually use, not the raw nearest:
    --occupied slots deflect the card exactly as RailDockCharacterCard
    --will on release.
    local slot = RailNearestFreeCardSlot(RailLayout(), side, desired, key)
    if ShowRailCardGhost ~= nil then
        ShowRailCardGhost(side, slot, charid)
    end
    dialog:SetClass("dockingIntoRail", true)
end

--Where to put a window of the given size so it sits BESIDE a token
--rather than covering it: on the token's roomier horizontal side when
--the window fits there, else above/below, else clamped to the screen.
--Returns {x, y} in the document layer's coordinate space (origin top
--left, y down -- the same space PresentDocument's args.x/y use), or nil
--when the token cannot be located (no camera bounds, invalid token).
local function TokenWindowPlacement(token, width, height)
    local b = dmhub.cameraBounds
    if token == nil or (not token.valid) or b == nil or b.x2 <= b.x1 or b.y2 <= b.y1 then
        return nil
    end

    local uiW = IconRailUIWidth()
    local uiH = IconRailUIHeight()

    --the token's center, mapped from world space through the camera's
    --visible bounds into the layer's units. cameraBounds has y up;
    --the layer has y down.
    local pos = token.pos
    local tokenX = (pos.x - b.x1) / (b.x2 - b.x1) * uiW
    local tokenY = (1 - (pos.y - b.y1) / (b.y2 - b.y1)) * uiH

    --the token's half-extent in layer units, from the tiles it occupies.
    local unitsPerWorld = uiW / (b.x2 - b.x1)
    local across = 1
    local locs = token.locsOccupying
    if locs ~= nil and #locs > 1 then
        across = math.sqrt(#locs)
    end
    local half = across * 0.5 * unitsPerWorld
    local gap = 24
    local margin = 8

    local ClampX = function(x)
        return math.max(margin, math.min(x, uiW - width - margin))
    end
    local ClampY = function(y)
        return math.max(margin, math.min(y, uiH - height - margin))
    end

    --beside the token, on whichever side has more room first.
    local horiz = {
        { x = tokenX + half + gap, fits = function(x) return x + width <= uiW - margin end },
        { x = tokenX - half - gap - width, fits = function(x) return x >= margin end },
    }
    if tokenX >= uiW / 2 then
        horiz[1], horiz[2] = horiz[2], horiz[1]
    end
    for _, h in ipairs(horiz) do
        if h.fits(h.x) then
            return { x = h.x, y = ClampY(tokenY - height / 2) }
        end
    end

    --no horizontal room (zoomed way in): above or below instead.
    local vert = {
        { y = tokenY + half + gap, fits = function(y) return y + height <= uiH - margin end },
        { y = tokenY - half - gap - height, fits = function(y) return y >= margin end },
    }
    if tokenY >= uiH / 2 then
        vert[1], vert[2] = vert[2], vert[1]
    end
    for _, v in ipairs(vert) do
        if v.fits(v.y) then
            return { x = ClampX(tokenX - width / 2), y = v.y }
        end
    end

    --the token effectively fills the screen; covering it is unavoidable.
    return { x = ClampX(horiz[1].x), y = ClampY(tokenY - height / 2) }
end

--Toggle a character's panel window: open it if closed, close it if
--open. The token-corner launcher's entry point. Mirrors the rail icons'
--click semantics -- a PINNED window is raised rather than closed, a
--panel living as a tab in another window raises that window and
--switches to its tab, and closing forgets the window's restore record
--so it does not come back on the next session. Defined down here (not
--next to ShowCharacterPanelDocument) so RailForgetWindow and
--RefreshRails are in scope to capture.
--anchorToken (optional): open the window beside that token rather than
--at its default/remembered position.
function ToggleCharacterPanelDocument(charid, anchorToken)
    local doc = CharacterPanelDocument.Get(charid)
    if doc == nil then
        return
    end
    local key = string.lower(doc.panelName)

    if doc:PresentDocumentOpen() then
        if PanelDocument.IsPinned(key) then
            local d = doc:try_get("_tmp_dialog")
            if d ~= nil and d.valid then
                d:SetAsLastSibling()
            end
        else
            RailForgetWindow(key)
            doc:ClosePanel()
        end
        RefreshRails()
        return
    end

    local presentArgs = {}
    if anchorToken ~= nil then
        --mirror PresentPanel/PresentDocument's size resolution so the
        --placement math uses the size the window will actually open at:
        --the defaults, unless a drag/resize this session is remembered
        --for this screen size.
        local width = PanelDocument.DefaultWidth
        local height = PanelDocument.ClampHeight(doc.panelName, PanelDocument.DefaultHeight)
        local tmploc = doc:try_get("_tmp_location")
        if tmploc ~= nil and tmploc.screenx == dmhub.screenDimensionsBelowTitlebar.x and tmploc.screeny == dmhub.screenDimensionsBelowTitlebar.y then
            width = tmploc.width or width
            height = tmploc.height or height
        end
        local placement = TokenWindowPlacement(anchorToken, width, height)
        if placement ~= nil then
            presentArgs.x = placement.x
            presentArgs.y = placement.y
        end
    end

    if rawget(_G, "RailModeActive") ~= nil and RailModeActive() then
        --while the rail hosts windows, character windows opened from the
        --token launcher behave like rail windows: dragging one makes it
        --stick where it lands (or docks it as a rail card at the screen
        --edge), and closing it forgets the stuck record.
        presentArgs.onMoved = function(element)
            if MaybeMinimizeCharacterWindow(key, element) then
                return
            end
            RailRememberWindow(key, element.x, element.y, doc)
        end
        --a plain resize keeps a stuck window's recorded size current
        --(a transient window has no record and this is a no-op).
        presentArgs.onResized = function(element)
            RailRememberWindowSize(key, doc)
        end
        presentArgs.onDragging = function(element)
            CharacterWindowDragging(key, element)
        end
        presentArgs.close = function()
            RailForgetWindow(key)
            doc:ClosePanel()
            RefreshRails()
        end
        --escape: dismiss without touching the rail records, same as the
        --rail windows' escapeClose.
        presentArgs.escapeClose = function()
            doc:ClosePanel()
            RefreshRails()
        end
    end

    doc:PresentPanel(presentArgs)
    RefreshRails()
end

--A group formed or broke up: which buttons exist has changed (the owner
--gains a badge and a flyout, each member loses its own button), so this
--needs a full rebuild rather than a refresh. SetStoredTabs only fires it
--on a real change, so restoring windows does not churn the rails.
--
--Open windows have to be reconciled too, because a window's tab set IS
--its folder. Two cases:
--  * a window whose panel is still its own host keeps standing and just
--    gains/loses chips (refreshPanelTabs) -- a rail drag must not blink
--    every affected window shut;
--  * a window whose panel has just been FILED under someone else is no
--    longer a legitimate host, so it closes. Its panel did not go
--    anywhere: it is a tab in its new owner's window now, one click away
--    on the rail.
g_onPanelGroupChanged = function()
    for key, doc in pairs(g_panelDocuments) do
        local dialog = doc:try_get("_tmp_dialog")
        if dialog ~= nil and dialog.valid then
            if PanelDocument.WindowOwner(key) ~= key then
                RailForgetWindow(key)
                doc:ClosePanel()
            else
                dialog:FireEventTree("refreshPanelTabs")
            end
        end
    end
    if RebuildIconRails ~= nil then
        RebuildIconRails()
    end
end

--Where a drag at screen point (dropX, dropY) would land: which rail
--(screen half) and which slot. Shared by the live ghost and the drop
--itself so they can never disagree.
local function RailDropPoint(dropX, dropY, excludeKey)
    local targetSide = cond(dropX > IconRailUIWidth() / 2, "right", "left")
    --dropY is the POINTER (RailDragPointer), so the slot is whichever
    --band CONTAINS it -- a slot's button plus half the gap on each
    --side. The previous round() mapping assumed dropY was the dragged
    --panel's TOP edge; fed the pointer instead, it read a hit in the
    --lower half of a slot as the next slot down (field report
    --2026-08-08: vacant-slot drops landing one space too low).
    local targetSlot = math.floor((dropY - ICON_RAIL_TOP + ICON_RAIL_GAP / 2) / (ICON_RAIL_BUTTON + ICON_RAIL_GAP))
    if targetSlot < 0 then
        targetSlot = 0
    end
    --Sparse column: empty slots are legitimate targets -- aiming into the
    --blank space below the last icon lands there and stays there. But a
    --drop past the column's capacity used to CLAMP to MAX_SLOT, flinging
    --the button to slot 16 well above the drop point with a void over it
    --(field report 2026-08-08: "adds an empty space instead of landing
    --where I dropped"). A drop in that dead zone now lands right after
    --the column's last button instead -- excludeKey keeps the dragged
    --button's own slot out of that measurement.
    if targetSlot > ICON_RAIL_MAX_SLOT then
        local maxOcc = -1
        local sides = RailLayout()
        for _, e in ipairs(sides[targetSide]) do
            if e.key ~= excludeKey then
                local bottom = e.slot + (e.span or 1) - 1
                if bottom > maxOcc then
                    maxOcc = bottom
                end
            end
        end
        targetSlot = maxOcc + 1
        if targetSlot > ICON_RAIL_MAX_SLOT then
            targetSlot = ICON_RAIL_MAX_SLOT
        end
    end
    return targetSide, targetSlot
end

--The POINTER's position during a drag of `element`, in the layer's
--coordinate space, given the element's resting top-left corner. The
--engine's own drag-target resolution scores candidates by PANEL-CENTRE
--distance (SheetPanel.FindDragTargetHovering), and the dragged panel's
--centre sits wherever the user gripped it -- up to half a button from
--the pointer, enough to pick the wrong zone. element.mousePoint is the
--grab point in normalized panel coords (x 0=left..1=right, y
--0=BOTTOM..1=top -- note the flip) and stays fixed under the cursor
--for the whole drag, so base + drag offset + grab point IS the
--pointer. Falls back to the panel centre if the point is unavailable.
local function RailDragPointer(baseX, baseY, element)
    local w = element.renderedWidth
    local h = element.renderedHeight
    if w == nil or w <= 0 then w = ICON_RAIL_BUTTON end
    if h == nil or h <= 0 then h = ICON_RAIL_BUTTON end
    local gx = w / 2
    local gy = h / 2
    local mp = element.mousePoint
    if mp ~= nil then
        gx = math.max(0, math.min(1, mp.x)) * w
        gy = (1 - math.max(0, math.min(1, mp.y))) * h
    end
    return baseX + (element.xdrag or 0) + gx, baseY + (element.ydrag or 0) + gy
end

--Pointer position for a dragged rail button resting at (side, slot).
--Whether an open rail-band window intersects the given band (top-left
--anchored layer coordinates -- the rails and the panel windows are both
--top-left anchored in near-identical full-screen layers, so their x/y
--are comparable to within a few pixels). The group flyout strips use
--this to decide their dress: chromeless over bare map, the opaque
--"stripCard" treatment only when the strip would actually draw over a
--window -- a card floating over nothing reads as clutter.
local function RailWindowIntersectsBand(x1, y1, x2, y2)
    for _, doc in pairs(g_panelDocuments) do
        local d = doc:try_get("_tmp_dialog")
        if d ~= nil and d.valid then
            local wx = tonumber(d.x) or 0
            local wy = tonumber(d.y) or 0
            local ww = tonumber(d.renderedWidth) or 0
            local wh = tonumber(d.renderedHeight) or 0
            if ww > 0 and wh > 0 and x1 < wx + ww and x2 > wx and y1 < wy + wh and y2 > wy then
                return true
            end
        end
    end
    return false
end

local function RailButtonDragPointer(side, slot, element)
    local baseX = cond(side == "left", ICON_RAIL_LEFT, IconRailUIWidth() - ICON_RAIL_LEFT - ICON_RAIL_BUTTON)
    local baseY = ICON_RAIL_TOP + slot * (ICON_RAIL_BUTTON + ICON_RAIL_GAP)
    return RailDragPointer(baseX, baseY, element)
end

--The group-member variant: a dragged member starts from its spot in the
--expanded strip beside the owner, not from a rail slot, so its base
--position is the strip's geometry (member `memberIndex` of
--`memberCount`, owner sitting at `ownerSlot`). The strip is anchored
--flush against the owner and grows toward the screen centre; on the
--right rail that means the strip's RIGHT edge sits at the owner's left
--edge and the first member is the farthest from the rail.
local function RailMemberDragPointer(side, ownerSlot, memberIndex, memberCount, element)
    local railX = cond(side == "left", ICON_RAIL_LEFT, IconRailUIWidth() - ICON_RAIL_LEFT - ICON_RAIL_BUTTON)
    --member buttons carry hmargin 4, so their pitch is button + 8.
    local pitch = ICON_RAIL_BUTTON + 8
    local baseX
    if side == "left" then
        baseX = railX + ICON_RAIL_BUTTON + 4 + (memberIndex - 1) * pitch
    else
        --the right rail's strip is anchored by its RIGHT edge, and in
        --rearrange mode (the only time members drag) the trailing
        --cut-out box widens the strip by one more pitch, pushing every
        --member that much further left.
        baseX = railX - (memberCount + 1) * pitch + 4 + (memberIndex - 1) * pitch
    end
    local baseY = ICON_RAIL_TOP + ownerSlot * (ICON_RAIL_BUTTON + ICON_RAIL_GAP)
    return RailDragPointer(baseX, baseY, element)
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

--the drag ghost panels and their helpers live below IconRailStyles,
--which they depend on. TWO ghosts for the two drop behaviors: the
--dotted BOX previews landing in an empty slot, the thin LINE previews
--inserting between existing buttons.
local g_railDragGhost = nil
local g_railDragGhostLine = nil
local ShowRailGhost
local HideRailGhost
--the rearrange-mode trash zones, keyed "left"/"right". They are LAYER
--children beside the rails, not rail children: the rail is a vertical
--flow sized to its content, and giving it a fixed full-column height
--to anchor a bottom trash makes the flow distribute the buttons across
--it (field-tested: the icons spread apart and the slot geometry broke).
local g_railTrashZones = {}

--The grouping drop zones of every expanded strip, registered as the
--rails build: {side, ownerKey, ownerSlot, memberCount, members,
--dividers (panel per boundary), cutout (panel)}. Zone CHOICE during a
--drag is pointer-based (RailGroupZoneAt below) rather than delegated
--to the engine's drag-target resolution -- see RailDragPointer for why
--panel-centre scoring aims wrong -- so these panels are plain visuals,
--not dragTargets, and the highlight is the "dropHover" class managed
--by RailSetZoneHover.
local g_railStripZones = {}
local g_railZoneHover = nil

local function RailSetZoneHover(panel)
    if g_railZoneHover == panel then
        return
    end
    if g_railZoneHover ~= nil and g_railZoneHover.valid then
        g_railZoneHover:SetClass("dropHover", false)
    end
    g_railZoneHover = panel
    if panel ~= nil and panel.valid then
        panel:SetClass("dropHover", true)
    end
end

--Which grouping boundary the pointer is over, or nil when it is not in
--any strip's band (the geometric slot semantics apply then). Boundaries
--sit every member-pitch along the strip: boundary j (0-based) is
--"insert before member j+1", drawn by that divider; the last boundary
--region is the trailing cut-out box, "append to the group" (beforeKey
--nil). The dragged panel's own strip is skipped. Callers gate the
--dragged key's groupability (document/character shortcuts never call
--in here); zones only exist for group-capable owners by construction.
local function RailGroupZoneAt(px, py, draggedKey)
    if draggedKey == nil then
        return nil
    end
    draggedKey = string.lower(draggedKey)
    local rowPitch = ICON_RAIL_BUTTON + ICON_RAIL_GAP
    local pitch = ICON_RAIL_BUTTON + 8
    for _, z in ipairs(g_railStripZones) do
        if string.lower(z.ownerKey) ~= draggedKey then
            local rowTop = ICON_RAIL_TOP + z.ownerSlot * rowPitch
            if py >= rowTop - ICON_RAIL_GAP / 2 and py <= rowTop + ICON_RAIL_BUTTON + ICON_RAIL_GAP / 2 then
                local railX = cond(z.side == "left", ICON_RAIL_LEFT, IconRailUIWidth() - ICON_RAIL_LEFT - ICON_RAIL_BUTTON)
                local stripStart = cond(z.side == "left", railX + ICON_RAIL_BUTTON, railX - (z.memberCount + 1) * pitch)
                local dx = px - stripStart
                if dx >= -4 and dx <= (z.memberCount + 1) * pitch + 4 then
                    local j = math.floor(dx / pitch + 0.5)
                    if j < 0 then
                        j = 0
                    end
                    if j >= z.memberCount then
                        return { ownerKey = z.ownerKey, beforeKey = nil, panel = z.cutout }
                    end
                    return { ownerKey = z.ownerKey, beforeKey = z.members[j + 1], panel = z.dividers[j + 1] }
                end
            end
        end
    end
    return nil
end

--Whether a slot on a side holds a button other than excludeKey (the
--dragged button's own slot never reads as occupied).
local function RailSlotOccupied(side, slot, excludeKey)
    local sides = RailLayout()
    for _, e in ipairs(sides[side]) do
        --a multi-slot card occupies every slot it spans.
        if e.key ~= excludeKey and slot >= e.slot and slot < e.slot + (e.span or 1) then
            return true
        end
    end
    return false
end

--While the rail is on, the rails ARE how panels are reached, so the
--docks' own slide-away handle tabs are hidden; they come back the moment
--the mode is turned off. (Dock visibility itself is still toggleable
--from the Panels menu and by Views.) Docks are rebuilt by reloads and
--theme changes, so the rail's think re-applies this continuously rather
--than relying on a one-shot.
local function SyncDockHandles()
    if gamehud == nil or rawget(gamehud, "leftDock") == nil then
        return
    end
    local railOn = RailModeActive()
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

--Toggling the rail moves the docks with it: rail ON slides both docks
--off screen (the rail replaces them); rail OFF slides both back in.
--Called ONLY from the iconrail setting's onchange -- EnsureIconRail
--also runs at EnterGame and after a Lua reload, where forcing the
--docks would trample a dock the user deliberately re-opened from the
--Panels menu while in rail mode.
--The "offscreen" class is applied to the docks DIRECTLY as well as via
--the dock settings: normally the dock handle's monitor event applies
--it, but SyncDockHandles collapses those handles in rail mode and
--collapsed panels process no events -- which is why flipping the
--setting used to leave the docks stranded on screen until a restart.
SyncDocksToRailMode = function()
    local railOn = RailModeActive()
    dmhub.SetSettingValue("leftdockoffscreen", railOn)
    dmhub.SetSettingValue("rightdockoffscreen", railOn)
    if gamehud ~= nil and rawget(gamehud, "leftDock") ~= nil then
        for _, dock in ipairs({gamehud.leftDock, gamehud.rightDock}) do
            if dock ~= nil and dock.valid then
                dock:SetClass("offscreen", railOn)
            end
        end
    end
    --recalculate the map's drawable area for the new dock state, same
    --as the handle's monitor would: 0 = docks gone, map full width.
    dmhub.UpdateScreenHudArea(cond(railOn, 0, 1))
end

--forward-declared: defined below OpenIconRailWindow (the two call each
--other -- the window's popout button closes the window and opens the
--popout; the popout's pop-in button does the reverse).
local OpenPanelPopout

--Open a rail window for the named panel. placement = {x=,y=,width=,
--height=} places and sizes it; nil lets PresentDocument use the
--session-remembered location and size. (There is no `tabs` override any
--more -- a window's tab set is its rail folder, read from the folder
--store, and nothing passes a list in.)
--placement.anchor marks x/y as the icon's spot rather than an absolute
--position: a window the user has dragged somewhere this session reopens
--there instead, the way its size already comes back. Restores and Views
--leave it off -- their coordinates ARE the remembered position.
--placement.autoFocus marks a USER-initiated open: a focusOnClick panel
--(Map Markup and the other map-mode tools) grabs focus -- and so arms its
--mode -- the moment the window is constructed. Restores omit it.
--
--A panel filed in a FOLDER has no window of its own: the folder's owner
--hosts one window whose tabs are the whole folder, so asking for a
--member opens (or raises) the owner's window with that member's tab
--active. Everything the window remembers -- position, size, pin -- is
--therefore keyed by the owner.
local function OpenIconRailWindow(panelName, placement)
    local requested = string.lower(panelName)
    local key = PanelDocument.WindowOwner(requested)
    --accepts a registered panel name OR a layout key (character
    --shortcuts pass "character:<charid>", which is not a panel name).
    local doc = RailPanelDocument(key)
    if doc == nil then
        return
    end

    local args = {
        --dragging a rail window makes it stick where it lands: it stops
        --being the transient window and comes back next time the rails
        --are built. A character window dragged into the rail band at
        --either screen edge minimizes into a rail card instead.
        onMoved = function(element)
            if MaybeMinimizeCharacterWindow(key, element) then
                return
            end
            RailRememberWindow(key, element.x, element.y, doc)
        end,

        --a plain resize keeps a stuck window's recorded size current
        --(a transient window has no record and this is a no-op).
        onResized = function(element)
            RailRememberWindowSize(key, doc)
        end,

        --the live half of the same gesture: while the drag is inside the
        --band, the rail previews the docked card and the window fades.
        onDragging = function(element)
            CharacterWindowDragging(key, element)
        end,

        --the header close button: closing forgets the window.
        close = function()
            RailForgetWindow(key)
            doc:ClosePanel()
            RefreshRails()
        end,

        --escape: dismiss the window but keep EVERYTHING -- the keep-open
        --record stays too, so escape never edits the rail.
        escapeClose = function()
            doc:ClosePanel()
            RefreshRails()
        end,

        --the header popout button: move this panel into its own native
        --OS window. Closes the in-app window but keeps the rail's
        --records -- the panel is still open, just living elsewhere -- and
        --hands the popout the window's current size so the panel keeps
        --its footprint across the transition.
        popout = function()
            local d = doc:try_get("_tmp_dialog")
            local geometry = nil
            if d ~= nil and d.valid then
                geometry = { width = d.renderedWidth, height = d.renderedHeight }
            end
            doc:ClosePanel()
            OpenPanelPopout(key, geometry)
            RefreshRails()
        end,
    }
    if placement ~= nil then
        args.x = placement.x
        args.y = placement.y
        args.width = placement.width
        args.height = placement.height
        args.anchor = placement.anchor
        args.autoFocus = placement.autoFocus
    end
    --the tab the caller actually asked for (the owner's own panel when
    --the request was not for a folder member).
    args.activeKey = requested

    doc:PresentPanel(args)
end

----------------------------------------------------------------------
-- Panel popouts
-- -------------
-- A rail panel moved into its own native OS window via
-- MoveToNativeWindow (the PDF viewer's companion-app mechanism). The
-- host built here replaces the rail window: it owns the panel's whole
-- style cascade -- a popped-out panel is the ROOT of its own hierarchy,
-- so nothing above it supplies Styles.Default (normally the GameHud
-- root) or the theme (normally the docks / the rail window root). Both
-- ride here explicitly, plus the popout's own chrome rules.
--
-- Known Phase-1 limits (see POPOUT_PANELS_PLAN.md at the repo root):
-- keyboard input beyond basic typing, escape/command routing, and
-- modals still land in the main window; those are engine work.

local function PopoutWindowStyles()
    return {
        Styles.Default,
        DocumentWindowStyles(),
        ThemeEngine.MergeTokens({
            {
                selectors = {"framedPanel", "popoutWindow"},
                priority = 6,
                --the panel IS the OS window: opaque (there is no app
                --surface behind it to blur through) and square (rounded
                --corners would cut into a rectangular window and show
                --the companion's black clear color).
                opacity = 1,
                cornerRadius = 0,
            },
            --the same chrome vocabulary the rail window's interface
            --defines locally (its MergeTokens extras do not travel with
            --the panel, so the popout host restates the rules it uses).
            {
                selectors = {"panelDocumentHeader"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"panelDocumentHairline"},
                bgcolor = "@border",
            },
            {
                selectors = {"label", "panelDocumentTitle"},
                color = "@fgStrong",
                fontSize = 12,
                bold = true,
            },
            {
                selectors = {"panelDocumentCloseButton"},
                bgcolor = "@fg",
                opacity = 0.7,
                transitionTime = 0.15,
            },
            {
                selectors = {"panelDocumentCloseButton", "hover"},
                opacity = 1,
                bgcolor = "@fgStrong",
            },
        }),
    }
end

--The popout persistence record (see the "popoutwindows" setting above).
local function PopoutRestoreRecords()
    return dmhub.GetSettingValue("popoutwindows") or {}
end

--The stamp marking records written by THIS run of the app; minted on
--first use, then stable across Lua reloads (transient storage).
local function PopoutSessionId()
    local id = dmhub.GetSettingValue("popoutsessionid")
    if id == nil or id == "" then
        id = dmhub.GenerateGuid()
        dmhub.SetSettingValue("popoutsessionid", id)
    end
    return id
end

local function PopoutRememberWindow(key, geometry)
    local records = PopoutRestoreRecords()
    local prev = records[key]
    if type(prev) == "table" then
        --a record with no fresh value to offer keeps the recorded one
        --(e.g. a resize arriving before the first move report).
        geometry.x = geometry.x or prev.x
        geometry.y = geometry.y or prev.y
        geometry.width = geometry.width or prev.width
        geometry.height = geometry.height or prev.height
    end
    geometry.session = PopoutSessionId()
    records[key] = geometry
    dmhub.SetSettingValue("popoutwindows", records)
end

local function PopoutForgetWindow(key)
    local records = PopoutRestoreRecords()
    if records[key] ~= nil then
        records[key] = nil
        dmhub.SetSettingValue("popoutwindows", records)
    end
end

--Open the named panel in a native OS popout window. geometry (optional)
--carries {width=,height=} -- the rail flow passes the in-app window's
--size so the panel keeps its footprint across the transition -- and,
--on a persistence restore, {x=,y=}: the remembered OS screen position.
OpenPanelPopout = function(panelName, geometry)
    local key = string.lower(panelName)
    if PanelDocument.PopoutHost(key) ~= nil then
        return
    end
    if not GameHud.instance then
        return
    end
    local reg = DockablePanel.GetRegistration(panelName)
    if reg == nil then
        return
    end

    local width = (geometry ~= nil and geometry.width) or PanelDocument.DefaultWidth
    local height = PanelDocument.ClampHeight(panelName,
        (geometry ~= nil and geometry.height) or PanelDocument.DefaultHeight)

    local host

    --the content wrapper: BuildContentWrapper's essential contract
    --(deferred build, 'refresh' priming for selection-following panels,
    --forced top-left alignment, vscroll per registration) without the
    --tab machinery -- a popout window is always exactly one panel.
    local buildContent = function(element)
        if mod.unloaded or (not element.valid) or element.data.contentRoot ~= nil then
            return
        end
        local content = reg.content()
        element.data.contentRoot = content
        content.selfStyle.valign = "top"
        content.selfStyle.halign = "left"
        element:AddChild(content)
        element:FireEventTree("refresh")
    end

    local wrapper
    if reg.vscroll ~= false then
        local hideObjectsOutOfScroll = reg.hideObjectsOutOfScroll
        if hideObjectsOutOfScroll == nil then
            hideObjectsOutOfScroll = true
        end
        wrapper = gui.Panel{
            idprefix = "panelPopoutScrollParent",
            width = "100%-4",
            height = "100%",
            pad = 2,
            vscroll = true,
            hideObjectsOutOfScroll = hideObjectsOutOfScroll,
            data = {},
            buildPanelContent = buildContent,
        }
    else
        wrapper = gui.Panel{
            idprefix = "panelPopoutNoScrollParent",
            width = "100%",
            height = "100%",
            data = {},
            buildPanelContent = buildContent,
        }
    end

    local popInButton = gui.Panel{
        classes = {"panelDocumentCloseButton"},
        bgimage = "drawsteel/Icons_Nav_MinWindow.png",
        width = 16,
        height = 16,
        floating = true,
        halign = "right",
        valign = "center",
        x = -8,
        swallowPress = true,
        linger = function(element)
            gui.Tooltip("Return to the app")(element)
        end,
        click = function(element)
            --restore the in-app rail window first, then tear the popout
            --down: destroying the host is what closes the OS window (the
            --engine sweeps native windows whose panel died). The panel
            --is back in the app, so the persistence record goes too.
            PopoutForgetWindow(key)
            OpenIconRailWindow(key)
            if host ~= nil and host.valid then
                host:DestroySelf()
            end
            RefreshRails()
        end,
    }

    local header = gui.Panel{
        classes = {"panelDocumentHeader"},
        width = "100%",
        height = g_panelDocumentHeaderHeight,
        flow = "horizontal",
        bgimage = true,

        gui.Label{
            classes = {"panelDocumentTitle"},
            text = reg.name or panelName,
            width = "auto",
            height = "auto",
            valign = "center",
            lmargin = 10,
        },
        popInButton,
    }

    local hairline = gui.Panel{
        classes = {"panelDocumentHairline"},
        width = "100%",
        height = 1,
        bgimage = true,
    }

    local contentArea = gui.Panel{
        width = "100%",
        height = string.format("100%%-%d", g_panelDocumentHeaderHeight + 1),
        flow = "none",
        wrapper,
    }

    host = gui.Panel{
        id = "panelPopout-" .. key,
        --"dock" satisfies the dockable-panel content contract (content
        --reaches up for an ancestor with that class and asks
        --data.TooltipAlignment(); the class itself is style-inert --
        --see the rail window's copy of this note).
        classes = {"framedPanel", "popoutWindow", "dock"},
        styles = PopoutWindowStyles(),
        bgimage = true,
        width = width,
        height = height,
        flow = "vertical",
        halign = "left",
        valign = "top",
        --parked far off-screen for the layout passes between AddChild
        --and MoveToNativeWindow: the move measures the panel's rect to
        --size the OS window, so it must lay out in-hierarchy first, but
        --it must never be user-visible in the app.
        x = -30000,
        y = 0,

        data = {
            floating = true,
            popoutPanelKey = key,
            --marks this root as living in a native OS window: modals with
            --an owner under this root route into the window's own modal
            --layer (Hud.ResolveModalLayer) instead of the main window's.
            nativeWindowRoot = true,
            --the live geometry record: width/height in panel units, x/y
            --in OS screen pixels once the companion reports them.
            popoutGeometry = {
                x = geometry ~= nil and geometry.x or nil,
                y = geometry ~= nil and geometry.y or nil,
                width = width,
                height = height,
            },
            popoutSavePending = false,
            TooltipAlignment = function()
                --the popout is its own surface; tooltips clamp inside
                --the window either way, so the side is cosmetic.
                return "right"
            end,
        },

        --fired by NativeWindowCanvas when the user resizes the OS window.
        resize = function(element, w, h)
            element.selfStyle.width = w
            element.selfStyle.height = h
            element.data.popoutGeometry.width = w
            element.data.popoutGeometry.height = h
            element:FireEvent("queuePopoutSave")
        end,

        --fired by the engine when the OS window moves (and once at
        --creation, with wherever the OS placed it). Screen pixels.
        nativeWindowMoved = function(element, x, y)
            element.data.popoutGeometry.x = x
            element.data.popoutGeometry.y = y
            element:FireEvent("queuePopoutSave")
        end,

        --debounce: moves stream at drag rate, and every event schedules
        --nothing while a save is already pending.
        queuePopoutSave = function(element)
            if element.data.popoutSavePending then
                return
            end
            element.data.popoutSavePending = true
            element:ScheduleEvent("savePopoutGeometry", 1)
        end,

        savePopoutGeometry = function(element)
            element.data.popoutSavePending = false
            if mod.unloaded or (not element.valid) then
                return
            end
            local geo = element.data.popoutGeometry
            PopoutRememberWindow(key, {
                x = geo.x, y = geo.y, width = geo.width, height = geo.height,
            })
        end,

        --fired by the engine when the user closes the OS window with its
        --own close button: the panel is deliberately closed, so it must
        --not come back next session. (Teardown paths -- pop-in, reload,
        --app exit -- never fire this.)
        nativeWindowClosed = function(element)
            PopoutForgetWindow(key)
        end,

        --Escape pressed IN the popout window (the engine routes it to this
        --window's own escape chain; popups in the window outrank us via
        --listener priority). Closing = destroying the host -- the engine
        --closes the OS window, and the rail's records stay, same contract
        --as the rail window's escape. A deliberate dismissal, so the
        --persistence record goes too.
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            PopoutForgetWindow(key)
            element:DestroySelf()
        end,

        --recolor on a theme / color-scheme switch, exactly like the rail
        --window root: this host owns its cascade, so nothing else will.
        --UpdateStyle() is required after the assignment (see the note on
        --the rail window's create handler).
        create = function(element)
            element.data.themeListener = ThemeEngine.OnThemeChanged(mod, function()
                if element.valid then
                    element.styles = PopoutWindowStyles()
                    element:UpdateStyle()
                end
            end)
        end,

        destroy = function(element)
            if element.data.themeListener ~= nil then
                element.data.themeListener:Deregister()
                element.data.themeListener = nil
            end
            if g_panelPopouts[key] == element then
                g_panelPopouts[key] = nil
            end
            if (not mod.unloaded) and GameHud.instance then
                RefreshRails()
            end
        end,

        --the two-step popout: content builds while the host is parked
        --off-screen (so panels mount inside a normal hierarchy), then
        --the whole tree moves to the native window once built.
        popoutToNativeWindow = function(element)
            if mod.unloaded or (not element.valid) then
                return
            end
            element:FireEventTree("popout")
            element:MoveToNativeWindow{
                resizeable = true,
                title = reg.name or panelName,
                --a persistence restore reopens the window where it was;
                --nil lets the OS place it (older engines ignore these).
                x = element.data.popoutGeometry.x,
                y = element.data.popoutGeometry.y,
            }
        end,

        header,
        hairline,
        contentArea,
    }

    GameHud.instance.documentsPanel:AddChild(host)
    g_panelPopouts[key] = host

    --record the popout immediately so it survives a Lua reload that
    --happens before the first move/resize report arrives.
    PopoutRememberWindow(key, {
        x = geometry ~= nil and geometry.x or nil,
        y = geometry ~= nil and geometry.y or nil,
        width = width,
        height = height,
    })

    wrapper:ScheduleEvent("buildPanelContent", 0.01)
    host:ScheduleEvent("popoutToNativeWindow", 0.15)
end

--public alias: other surfaces (and test tooling) can open a popout
--without going through a rail window's header button.
PanelDocument.OpenPopout = function(panelName, geometry)
    OpenPanelPopout(panelName, geometry)
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
        --a script button whose chunk just errored: the stop-button red,
        --cleared on a short timer by the runner.
        {
            selectors = {"iconRailButton", "scriptError"},
            bgcolor = "#8c1d2bcc",
            transitionTime = 0.15,
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
        --the background-process gear: a small spinning cog on the button's
        --bottom-left corner while the panel has a registered background
        --process running (DockablePanel.StartProcess) -- the panel's work
        --carries on even when the panel is closed, and the gear is the
        --always-on sign of it. The one scheme-colored element on the
        --monochrome rail (the scheme's accent/trim color), so it reads as
        --live status rather than part of the icon.
        {
            selectors = {"iconRailProcessGear"},
            bgcolor = "@accent",
        },
        --the group shadow: a second button-shaped card peeking out from
        --behind a button whose window hosts other panels as tabs -- the
        --"stack of cards" read, replacing an unreadably small corner
        --glyph. The bgcolor TINTS the white pre-shaped image (rounded
        --corners and the button-silhouette cutout are baked into it),
        --which is why there is no cornerRadius here.
        {
            selectors = {"iconRailGroupShadow"},
            bgcolor = "#000000f2",
            opacity = 1,
            transitionTime = 0.1,
        },
        --the marker card fades out while the stack is "visually spent":
        --the strip is expanded into the band, OR the group's window is
        --open (popping back at window-open read glitchy). ONE class for
        --both reasons, deliberately: StyleSelected blends rules by
        --per-rule match ratio, so swapping between two opacity-0 rules
        --in the same frame (strip class off + window class on) had
        --neither at full ratio mid-transition and the card bulged to
        --~25% opacity for the crossfade -- a visible flicker on every
        --open. A single class never crossfades with itself.
        --transitionTime must be on THIS rule, not just the base: the
        --engine reads it per-rule when the rule's selector match
        --changes, so a rule without its own transitionTime snaps
        --instantly. The same value drives both directions.
        {
            selectors = {"iconRailGroupShadow", "groupOpen"},
            opacity = 0,
            transitionTime = 0.1,
        },
        --the hover flyout: the grouped panels' own buttons, opening
        --toward the screen centre beside the owner. At rest over the bare
        --map the strip is just a hover bridge (a barely-there fill so the
        --gaps between members still hit-test -- fully "clear" would not).
        --When the strip would draw over an open window it becomes an
        --opaque rounded card instead; that fill is applied via selfStyle
        --in the owner's hover handler, NOT here -- a fill switched by a
        --class rule verifiably never repainted this panel. The "stripCard"
        --class still marks the state for anything that wants to key off it.
        {
            selectors = {"iconRailGroupFlyout"},
            bgcolor = "#00000001",
        },
        {
            selectors = {"iconRailGroupMember"},
            bgcolor = "#000000cc",
            border = 0,
            cornerRadius = 8,
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailGroupMember", "hover"},
            bgcolor = "#000000ee",
        },
        --the explicit grouping drop zones (rearrange mode only): the
        --dotted cut-out box beside a button ("drop here to group") and
        --the dashed dividers between an expanded strip's members ("slot
        --in here"). Quiet at rest; the "dropHover" class -- managed by
        --RailSetZoneHover from the drag handlers' pointer math, NOT by
        --the engine's drag-target machinery -- fills the hovered one in.
        {
            selectors = {"iconRailGroupCutout"},
            bgcolor = "#ffffff0a",
            border = 0,
            cornerRadius = 8,
            transitionTime = 0.15,
        },
        --the cut-out doubles as a button (click the "+" to pick a panel
        --to add), so it also lights under the pointer -- more softly
        --than a drag hovering it, which stays the loudest state.
        {
            selectors = {"iconRailGroupCutout", "hover"},
            bgcolor = "#ffffff1c",
        },
        {
            selectors = {"iconRailGroupCutout", "dropHover"},
            bgcolor = "#ffffff2e",
        },
        {
            selectors = {"iconRailGroupCutoutPlus"},
            bgcolor = "@fg",
            opacity = 0.5,
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailGroupCutoutPlus", "parent:hover"},
            bgcolor = "@fgStrong",
            opacity = 1,
        },
        {
            selectors = {"iconRailGroupCutoutPlus", "parent:dropHover"},
            bgcolor = "@fgStrong",
            opacity = 1,
        },
        {
            selectors = {"iconRailGroupDivider"},
            bgcolor = "#00000001",
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailGroupDivider", "dropHover"},
            bgcolor = "#ffffff2e",
        },
        {
            selectors = {"iconRailGroupDividerDash"},
            bgcolor = "#ffffff8c",
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailGroupDividerDash", "parent:dropHover"},
            bgcolor = "#ffffff",
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
        --rearrange mode: every button rocks between +/-3 degrees AND
        --breathes between 97% and 103% scale (the iOS home-screen
        --wiggle). Rotation and scale run on separate event loops with
        --different periods ("wiggle" / "wigglePulse"), so their phases
        --drift against each other and the motion reads organic rather
        --than metronomic; neighbours also start desynced. The cascade
        --is per-property: wigglePhase overrides only rotate, pulsePhase
        --only scale, both inheriting the rest from the base rule.
        {
            selectors = {"iconRailButton", "rearranging"},
            rotate = 3,
            scale = 1.03,
            transitionTime = 0.12,
        },
        {
            selectors = {"iconRailButton", "rearranging", "wigglePhase"},
            rotate = -3,
        },
        {
            selectors = {"iconRailButton", "rearranging", "pulsePhase"},
            scale = 0.97,
        },
        --the stop-rearranging X: the one deliberately coloured control
        --on the monochrome rail, so "exit this mode" cannot be read as
        --just another wiggling icon.
        {
            selectors = {"iconRailStopButton"},
            bgcolor = "#8c1d2bcc",
            border = 0,
            cornerRadius = 8,
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailStopButton", "hover"},
            bgcolor = "#b3243aee",
        },
        {
            selectors = {"iconRailStopIcon"},
            bgcolor = "#ffffff",
            transitionTime = 0.15,
        },
        --the trash drop zone: quiet until a dragged button is over it,
        --then red to signal the destructive drop. priority 6 outranks
        --the global drag-target styles (priority 5 in DefaultStyles),
        --which would otherwise accent-tint it like any drop target.
        --The + button's picker. Carries the rail's own scrim palette
        --(these rules ride in IconRailStyles, which the popup takes as its
        --styles root) so it reads as part of the rail rather than as a
        --themed dialog that happened to open next to it.
        {
            selectors = {"railPicker"},
            bgcolor = "#000000ee",
            border = 1,
            borderColor = "#ffffff22",
            cornerRadius = 8,
            vpad = 6,
            borderBox = true,
        },
        {
            selectors = {"label", "railPickerHeader"},
            color = "#ffffff66",
            fontSize = 11,
            bold = true,
            hmargin = 10,
            tmargin = 8,
            bmargin = 2,
        },
        {
            selectors = {"railPickerRow"},
            bgcolor = "#00000000",
            cornerRadius = 4,
            hmargin = 4,
            transitionTime = 0.1,
        },
        {
            selectors = {"railPickerRow", "hover"},
            bgcolor = "#ffffff1a",
        },
        {
            selectors = {"railPickerRowIcon"},
            bgcolor = "#ffffffcc",
        },
        {
            selectors = {"railPickerRowIcon", "parent:hover"},
            bgcolor = "#ffffff",
        },
        {
            selectors = {"label", "railPickerRowLabel"},
            color = "#ffffffcc",
            fontSize = 14,
        },
        {
            selectors = {"label", "railPickerRowLabel", "parent:hover"},
            color = "#ffffff",
        },
        --The + affordance: absent until the rail is hovered, and quiet
        --even then -- it is an authoring control sitting among the panels
        --you actually use, so it should never compete with them. It keeps
        --its layout slot at rest (opacity, not collapsed) so revealing it
        --moves nothing.
        --transitionTime is repeated on EVERY state, not just the rest
        --rule: the engine takes the duration from the state being moved
        --TO, so a rest-only duration faded out gracefully and snapped
        --back in. A control that appears near the pointer has to arrive
        --softly -- popping reads as a glitch rather than an invitation.
        {
            selectors = {"iconRailAddButton"},
            opacity = 0,
            bgcolor = "#00000000",
            transitionTime = 0.18,
        },
        {
            selectors = {"iconRailAddButton", "shown"},
            opacity = 0.55,
            bgcolor = "#000000cc",
            transitionTime = 0.18,
        },
        --brightening under the pointer is a response to something the
        --user just did, so it wants to feel immediate rather than languid.
        {
            selectors = {"iconRailAddButton", "shown", "hover"},
            opacity = 1,
            bgcolor = "#000000ee",
            transitionTime = 0.1,
        },
        --HELD OPEN: its list is up, so the button stays at full strength
        --whether or not the pointer is still on it -- the pointer is off
        --in the picker, and a source control that dims while its own menu
        --is open loses the thread between the two. priority outranks the
        --plain shown rule, which would otherwise pull it back to 0.55.
        {
            selectors = {"iconRailAddButton", "open"},
            opacity = 1,
            bgcolor = "#000000ee",
            transitionTime = 0.1,
            priority = 10,
        },
        --The glyph hides and shows on its own. Parent opacity does not
        --cascade to children in this engine, so without these the + kept
        --drawing over the map while its button was fully transparent --
        --and it needs its own durations for the same reason, or the plate
        --fades while the + inside it blinks.
        {
            selectors = {"iconRailAddIcon"},
            opacity = 0,
            transitionTime = 0.18,
        },
        {
            selectors = {"iconRailAddIcon", "parent:shown"},
            opacity = 1,
            transitionTime = 0.18,
        },
        --...and the + steps aside for the whole time the list is up, not
        --just while hovered: the x IS the button's glyph in that state, so
        --the two must never be drawn at once or they smudge into one mark.
        {
            selectors = {"iconRailAddIcon", "parent:open"},
            opacity = 0,
            transitionTime = 0.1,
            priority = 20,
        },
        {
            selectors = {"iconRailTrash"},
            bgcolor = "#000000cc",
            border = 0,
            cornerRadius = 12,
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailTrash", "drag-target"},
            bgcolor = "#000000cc",
            priority = 6,
        },
        {
            selectors = {"iconRailTrash", "drag-target-hover"},
            bgcolor = "#8c1d2bee",
            borderWidth = 2,
            borderColor = "#ff4a5c",
            priority = 6,
        },
        {
            selectors = {"iconRailTrashIcon"},
            bgcolor = "@fg",
            transitionTime = 0.15,
        },
        {
            selectors = {"iconRailTrashIcon", "parent:drag-target-hover"},
            bgcolor = "#ffffff",
            priority = 6,
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
            --Plain flyout text, no chip: the old boxed background (dark
            --fill + border + rounded corners) read as a panel colliding
            --with the buttons around it.
            --NO textOutline either: the engine renders textOutlineColor as
            --a snug PLATE behind the whole text, not a per-glyph stroke --
            --it was the mystery grey box hugging these labels.
            bgcolor = "clear",
            border = 0,
            color = "@fgStrong",
            fontSize = 12,
            bold = true,
            transitionTime = 0.15,
        },
        {
            selectors = {"label", "iconRailLabel", "parent:hover"},
            opacity = 1,
        },
        --No label while the button's panel is already open: the window
        --sits flush beside the rail, exactly where the label draws, and
        --the name of an open panel is information the user already has.
        --priority outranks the parent:hover fade-in above.
        {
            selectors = {"label", "iconRailLabel", "parent:active"},
            opacity = 0,
            priority = 10,
        },
        --Same reasoning for the + once its picker is up: acting on a
        --control dismisses that control's label, and the list now sitting
        --beside the rail says what the + does far better than the word
        --does. Only the + is ever given "open", so this is scoped to it.
        {
            selectors = {"label", "iconRailLabel", "parent:open"},
            opacity = 0,
            priority = 10,
        },
        --The flyout strip's name slot. No textOutline -- the engine draws
        --it as a plate hugging the text, not a glyph stroke (see the
        --iconRailLabel note).
        {
            selectors = {"label", "iconRailStripLabel"},
            color = "@fgStrong",
            fontSize = 12,
            bold = true,
        },
        --Close hint: hovering a button whose panel is open means a click
        --will CLOSE it -- the icon recedes and an X takes its place.
        {
            selectors = {"iconRailIcon", "parent:active", "parent:hover"},
            opacity = 0.15,
        },
        {
            selectors = {"iconRailCloseHint"},
            bgcolor = "@fg",
            opacity = 0,
            transitionTime = 0.12,
        },
        {
            selectors = {"iconRailCloseHint", "parent:active", "parent:hover"},
            opacity = 1,
        },
        --The + shows the same hint while ITS thing -- the picker -- is up,
        --and unlike the rail's buttons it shows it WITHOUT waiting for
        --hover. The rail's version is a hint about what a click would do,
        --so it only appears under the pointer; this one is the button's
        --actual state while its list is up, and a glyph that swaps only
        --when the pointer happens to be over it reads as flickery rather
        --than informative (Venla 2026-08-15).
        {
            selectors = {"iconRailAddCloseHint", "parent:open"},
            opacity = 1,
            priority = 20,
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
    if g_railDragGhostLine ~= nil and g_railDragGhostLine.valid then
        g_railDragGhostLine:SetClass("hidden", true)
    end
end

--Live preview of where a dragged button/document will land: a dotted
--placeholder box sits at the target slot -- including an EMPTY slot in
--the blank space below the last icon, which the sparse column makes a
--legitimate target. The rail itself stays still while dragging: no live
--shuffling (it read as jitter -- Lisa+David review 2026-07-19); a drop
--on an occupied slot chain-bumps the occupants at drop time instead.
--excludeKey is accepted for signature compatibility but unused now:
--nothing shifts, so nothing needs excluding.
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

    local railX = cond(side == "left", ICON_RAIL_LEFT, IconRailUIWidth() - ICON_RAIL_LEFT - ICON_RAIL_BUTTON)
    local slotTop = ICON_RAIL_TOP + slot * (ICON_RAIL_BUTTON + ICON_RAIL_GAP)

    --An OCCUPIED slot gets the insertion LINE in the gap above it ("slots
    --in between these two"); an EMPTY slot gets the dotted BOX ("lands in
    --this blank spot") -- matching the two drop behaviors. excludeKey
    --keeps the dragged button's own slot reading as empty, so hovering
    --home shows the box it would snap back into.
    if RailSlotOccupied(side, slot, excludeKey) then
        if g_railDragGhost ~= nil and g_railDragGhost.valid then
            g_railDragGhost:SetClass("hidden", true)
        end
        if g_railDragGhostLine == nil or not g_railDragGhostLine.valid then
            g_railDragGhostLine = gui.Panel{
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
            layer:AddChild(g_railDragGhostLine)
        end
        g_railDragGhostLine.x = railX
        --centred in the gap ABOVE the target slot: the drop inserts just
        --above that slot's occupant.
        g_railDragGhostLine.y = slotTop - ICON_RAIL_GAP / 2 - 1
        g_railDragGhostLine:SetClass("hidden", false)
        return
    end

    if g_railDragGhostLine ~= nil and g_railDragGhostLine.valid then
        g_railDragGhostLine:SetClass("hidden", true)
    end
    if g_railDragGhost == nil or not g_railDragGhost.valid then
        g_railDragGhost = gui.Panel{
            classes = {"iconRailGhost"},
            --a layer child sits outside the rails' style cascade, so it
            --carries the rail styles itself.
            styles = IconRailStyles(),
            bgimage = "panels/square.png",
            width = ICON_RAIL_BUTTON,
            height = ICON_RAIL_BUTTON,
            halign = "left",
            valign = "top",
            interactable = false,
            children = DottedOutlineChildren(ICON_RAIL_BUTTON),
        }
        layer:AddChild(g_railDragGhost)
    end
    g_railDragGhost.x = railX
    g_railDragGhost.y = slotTop
    g_railDragGhost:SetClass("hidden", false)
end

--The card face a character rail entry shows: portrait on top, stamina
--below, and (for heroes) heroic resource + surges. Shared by the docked
--cards themselves (CreateIconRail) and the live drag-preview ghost.
--Values populate at create and follow the creature on refreshRail
--events; the ghost never receives those, but a drag preview's snapshot
--values are fine.
local function CreateCharacterCardVisual(charid)
    --portrait resolution: same rules as the rail's button icons.
    local portraitIcon = "icons/standard/Icon_App_Character.png"
    local portraitTint = nil
    local portraitRect = nil
    local charToken = dmhub.GetCharacterById(charid)
    if charToken ~= nil then
        local portrait = nil
        pcall(function() portrait = charToken.offTokenPortrait end)
        if portrait ~= nil and portrait ~= "" then
            portraitIcon = portrait
            portraitTint = "white"
            pcall(function()
                portraitRect = charToken:GetPortraitRectForAspect(1, portrait)
            end)
        end
    end

    local staminaFill
    local staminaLabel
    local recoveryRow
    local recoveryIcon
    local recoveryLabel
    local heroRow
    local resourceLabel
    local surgeLabel

    local UpdateCard = function()
        local token = dmhub.GetCharacterById(charid)
        if token == nil or token.properties == nil then
            return
        end
        local c = token.properties
        local cur, max = 0, 0
        pcall(function()
            cur = c:CurrentHitpoints()
            max = c:MaxHitpoints()
        end)
        if staminaLabel ~= nil and staminaLabel.valid then
            staminaLabel.text = string.format("%d/%d", cur, max)
        end
        if staminaFill ~= nil and staminaFill.valid then
            local ratio = 0
            if max > 0 then
                ratio = math.max(0, math.min(1, cur / max))
            end
            staminaFill.selfStyle.width = string.format("%d%%", math.floor(ratio * 100 + 0.5))
            local color = "#3f9d4b"
            if cur <= 0 then
                color = "#8c1d2b"
            elseif cur < max / 2 then
                --winded.
                color = "#c1731f"
            end
            staminaFill.selfStyle.bgcolor = color
        end

        --recoveries sit right under the stamina bar. They are a resource,
        --not a creature field, so they come out of the resource table;
        --creatures with no recoveries at all (most monsters) collapse the
        --row rather than showing 0/0.
        local recMax, recNow = 0, 0
        pcall(function()
            recMax = c:GetResources()[CharacterResource.recoveryResourceId] or 0
            local used = c:GetResourceUsage(CharacterResource.recoveryResourceId, "long") or 0
            recNow = math.max(0, recMax - used)
        end)
        if recoveryRow ~= nil and recoveryRow.valid then
            recoveryRow:SetClass("collapsed", recMax <= 0)
        end
        if recoveryLabel ~= nil and recoveryLabel.valid then
            recoveryLabel.text = string.format("%d/%d", recNow, recMax)
        end

        local isHero = false
        pcall(function() isHero = c:IsHero() end)
        if heroRow ~= nil and heroRow.valid then
            heroRow:SetClass("collapsed", not isHero)
        end
        if isHero then
            local hr = 0
            pcall(function() hr = c:GetHeroicOrMaliceResources() or 0 end)
            if resourceLabel ~= nil and resourceLabel.valid then
                resourceLabel.text = tostring(hr)
            end
            if surgeLabel ~= nil and surgeLabel.valid then
                --surges are not a creature field: they live in the
                --unbounded resource table and are combat-scoped, so they
                --have to come from the accessor. try_get("surges") always
                --fell through to the default and pinned the label at 0.
                local surges = 0
                pcall(function() surges = c:GetAvailableSurges() or 0 end)
                surgeLabel.text = tostring(surges)
            end
        end
    end

    staminaFill = gui.Panel{
        bgimage = true,
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "center",
        cornerRadius = 3,
        interactable = false,
    }
    staminaLabel = gui.Label{
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = 9,
        bold = true,
        color = "#ffffff",
        interactable = false,
        text = "",
    }

    recoveryIcon = gui.Panel{
        --NOT the Recovery resource's own compendium icon: that art is
        --detailed and turns to mush at 9px. A solid phosphor glyph is the
        --only thing that still reads at card size.
        bgimage = "phosphor/heart-fill.png",
        --the recovery green, matching the healthy stamina fill.
        bgcolor = "#7cc489",
        width = 9,
        height = 9,
        valign = "center",
        rmargin = 3,
        interactable = false,
    }
    recoveryLabel = gui.Label{
        width = "auto",
        height = "auto",
        valign = "center",
        fontSize = 9,
        bold = true,
        color = "#7cc489",
        interactable = false,
        text = "",
    }
    recoveryRow = gui.Panel{
        classes = {"collapsed"},
        width = "auto",
        height = 11,
        flow = "horizontal",
        halign = "center",
        tmargin = 2,
        interactable = false,

        recoveryIcon,
        recoveryLabel,
    }

    resourceLabel = gui.Label{
        width = "auto",
        height = "auto",
        valign = "center",
        fontSize = 11,
        bold = true,
        --the heroic resource's conventional gold.
        color = "#e8c56a",
        interactable = false,
        text = "",
    }
    surgeLabel = gui.Label{
        width = "auto",
        height = "auto",
        valign = "center",
        fontSize = 11,
        bold = true,
        color = "#ffffff",
        interactable = false,
        text = "",
    }
    heroRow = gui.Panel{
        classes = {"collapsed"},
        width = "auto",
        height = 14,
        flow = "horizontal",
        halign = "center",
        tmargin = 2,
        interactable = false,

        resourceLabel,
        gui.Panel{
            bgimage = "game-icons/surge.png",
            bgcolor = "#ffffff",
            width = 11,
            height = 11,
            valign = "center",
            lmargin = 5,
            rmargin = 1,
            interactable = false,
        },
        surgeLabel,
    }

    return gui.Panel{
        width = "100%",
        height = "100%",
        flow = "vertical",
        interactable = false,

        gui.Panel{
            classes = {"iconRailCardPortrait"},
            bgimage = portraitIcon,
            width = 30,
            height = 30,
            halign = "center",
            tmargin = 5,
            cornerRadius = 15,
            interactable = false,
            create = function(element)
                --portraits are full-colour art: opt them out of the
                --icon tinting, and crop them square.
                if portraitTint ~= nil then
                    element.selfStyle.bgcolor = portraitTint
                end
                if portraitRect ~= nil then
                    element.selfStyle.imageRect = portraitRect
                end
            end,
        },

        gui.Panel{
            width = 32,
            height = 12,
            halign = "center",
            tmargin = 4,
            flow = "none",
            bgimage = true,
            bgcolor = "#000000b0",
            borderWidth = 1,
            borderColor = "#ffffff2e",
            cornerRadius = 3,
            interactable = false,

            staminaFill,
            staminaLabel,
        },

        recoveryRow,
        heroRow,

        refreshRail = function(element)
            UpdateCard()
        end,
        create = function(element)
            UpdateCard()
        end,
    }
end

--The live drag-preview ghost: a card-shaped preview showing a dragged
--character window already docked into the rail, at the slot the drop
--will use. Assigns the forward-declared locals CharacterWindowDragging
--and MaybeMinimizeCharacterWindow call.
local g_railCardGhost = nil
local g_railCardGhostCharid = nil

ShowRailCardGhost = function(side, slot, charid)
    local layer = DocumentsLayer()
    if layer == nil then
        return
    end

    if g_railCardGhost ~= nil and g_railCardGhost.valid and g_railCardGhostCharid ~= charid then
        g_railCardGhost:DestroySelf()
        g_railCardGhost = nil
    end

    if g_railCardGhost == nil or not g_railCardGhost.valid then
        local pitch = ICON_RAIL_BUTTON + ICON_RAIL_GAP
        g_railCardGhost = gui.Panel{
            classes = {"iconRailCardGhost"},
            styles = {
                gui.Style{
                    selectors = {"iconRailCardGhost", "hidden"},
                    hidden = 1,
                },
            },
            bgimage = true,
            bgcolor = "#000000cc",
            cornerRadius = 8,
            borderWidth = 1,
            borderColor = "#ffffff47",
            width = ICON_RAIL_BUTTON,
            height = 2 * pitch - ICON_RAIL_GAP,
            halign = "left",
            valign = "top",
            flow = "none",
            interactable = false,

            CreateCharacterCardVisual(charid),
        }
        g_railCardGhostCharid = charid
        layer:AddChild(g_railCardGhost)
    end

    g_railCardGhost.x = cond(side == "left", ICON_RAIL_LEFT, IconRailUIWidth() - ICON_RAIL_LEFT - ICON_RAIL_BUTTON)
    g_railCardGhost.y = ICON_RAIL_TOP + slot * (ICON_RAIL_BUTTON + ICON_RAIL_GAP)
    g_railCardGhost:SetClass("hidden", false)
end

HideRailCardGhost = function()
    if g_railCardGhost ~= nil and g_railCardGhost.valid then
        g_railCardGhost:SetClass("hidden", true)
    end
end

--Remove any dock header bar left mounted on a dock by an older build:
--the rail no longer hands panels over to the docks, so its dock-side
--chrome is gone. Docks outlive a Lua reload, so this sweeps rather than
--assuming a fresh dock.
local function RemoveDockTrayButtons()
    if gamehud == nil or rawget(gamehud, "leftDock") == nil then
        return
    end
    for _, dock in ipairs({gamehud.leftDock, gamehud.rightDock}) do
        if dock ~= nil and dock.valid then
            for _, child in ipairs(dock.children) do
                if child.valid and child:HasClass("iconRailDockHeader") then
                    child:DestroySelf()
                end
            end
            --...and any button an even older build left inside a panel's
            --own title bar.
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
        end
    end
end


--Rearrange mode (context menu > Rearrange...): the only time rail
--buttons can be dragged. While on, buttons wiggle, the tray button
--becomes the red stop-X (Escape also exits), and a trash drop zone
--appears at the bottom of each rail. Session state, never saved.
local g_railRearranging = false

local function RailSetRearranging(on)
    if g_railRearranging == on then
        return
    end
    g_railRearranging = on
    RebuildIconRails()
end

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
        if target < 0 or target > ICON_RAIL_MAX_SLOT then
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
        --tie-break: the moved entry sorts above the occupant of its
        --slot. The `b ~= entry` half is LOAD-BEARING: table.sort may
        --compare an element with itself, and a comparator that returns
        --true for (entry, entry) is not a strict weak order -- Lua 5.4
        --detects that and throws "invalid order function for sorting".
        table.sort(otherList, function(a, b)
            if a.slot == b.slot then
                return a == entry and b ~= entry
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
--journal) can ask without repeating the setting lookup. The mode is
--opt-in per user from Settings > General ("New Experimental UI"); it
--used to additionally require devmode() while the rail was a dev-only
--trial.
function RailModeActive()
    return dmhub.GetSettingValue("iconrail") == true
end

--How deeply floating rail panel windows currently intrude into the
--right edge of the screen, in UI units, clamped to [0, maxDepth].
--A window counts only when it actually reaches into the rightmost
--maxDepth band; the answer is how far the leftmost such window's left
--edge sits from the right screen edge. 0 means the band is clear.
--Exported for the right-side ability sidebar / roll host (GameHud),
--which in rail mode sit near the right edge unless windows float there.
function RailWindowsRightIntrusion(maxDepth)
    local uiW = IconRailUIWidth()
    local result = 0
    for _, doc in pairs(g_panelDocuments) do
        local d = doc:try_get("_tmp_dialog")
        if d ~= nil and d.valid then
            local w = d.renderedWidth
            if type(w) ~= "number" or w <= 0 then
                w = PanelDocument.DefaultWidth
            end
            if d.x + w > uiW - maxDepth then
                local intrusion = uiW - d.x
                if intrusion > result then
                    result = intrusion
                end
            end
        end
    end
    if result > maxDepth then
        result = maxDepth
    elseif result < 0 then
        result = 0
    end
    return result
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

--Add or remove a panel's rail button. This used to be the verb behind
--the Panels menu's rows (Lisa, 2026-07-20); those rows now use the
--default togglepanel click, which opens/closes the panel and only ever
--ADDS a shortcut (David, 2026-08-08). Kept as the membership toggle for
--any surface that wants one.
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

--Place a layout key at (side, slot): remove it from wherever it lives
--(either rail, or parked inert), insert it there, and chain-bump any
--occupants down into the first free slot. Shared by the document and
--character drop paths and by a group member dragged out onto the rail --
--all are just a key landing in a slot.
local function RailPlaceKeyAt(key, side, slot)
    if key == nil or side == nil or slot == nil then
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
    --`b ~= entry` is LOAD-BEARING: see RailMovePanel's sort -- a
    --comparator returning true for (entry, entry) makes table.sort
    --throw "invalid order function for sorting".
    table.sort(list, function(a, b)
        if a.slot == b.slot then
            return a == entry and b ~= entry
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

--Drop an arbitrary layout key onto the rail slot under `target`.
local function RailKeyDrop(key, target)
    local side, slot = RailDocDropSlot(target)
    if side == nil then
        return false
    end
    return RailPlaceKeyAt(key, side, slot)
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
        if not RailModeActive() then
            return
        end
        --no-ops when the panel is not on a rail.
        RailMovePanel(string.lower(panelName), "remove")
    end)
end

--Which rail a panel's button sits on, and in which slot, or nil when it
--has no button (never added, parked "off", or grouped under another
--panel).
local function RailFindButton(key)
    local sides = RailLayout()
    for sideName, list in pairs(sides) do
        for _, e in ipairs(list) do
            if e.key == key then
                return sideName, e.slot
            end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Group rearrangement verbs
-- -------------------------
-- Rearrange mode edits GROUPS as well as slots: any panel button can be
-- dragged into another window's "child space" (onto its button, or into
-- its expanded member strip), members can be reordered, dragged out to
-- their own slot, or dropped onto their owner to take the group over.
-- These are the storage-level verbs behind those gestures (and their
-- non-drag context-menu parity).
----------------------------------------------------------------------

--Whether a layout key can live as a tab in another panel's window.
--Journal-document shortcuts open in the viewer and character cards host
--synthetic registrations; neither can be a group member or owner.
local function RailIsGroupableKey(key)
    if key == nil then
        return false
    end
    key = string.lower(key)
    return string.match(key, "^doc:") == nil
        and string.match(key, "^character:") == nil
        and string.match(key, "^toolkit:") == nil
end

--(Grouping edits reach open windows through g_onPanelGroupChanged,
--which reconciles each window's chips against the new membership in
--place. Windows READ the folder store and never write it -- that
--one-way flow is what lets a window stay up through a rail drag instead
--of being closed to stop it clobbering the new arrangement.)

--The full stored member list for a folder (owner included, owner first
--when it has no stored list yet). The window's tab set is built from the
--same list -- PanelDocument.FolderTabs is the one definition.
local RailGroupTabs = PanelDocument.FolderTabs

--Put `draggedKey` into `ownerKey`'s group, before member `beforeKey`
--(nil = at the end). Doubles as the reorder verb: a panel already in
--the group just changes position. If the dragged panel OWNS a group of
--its own, its whole group comes along as a block in its tab order --
--without this, SetStoredTabs's one-window enforcement dissolved the
--dragged group and orphaned its members back onto the rail as loose
--buttons (David, 2026-08-08). SetStoredTabs still releases every key
--in the block from wherever else it lived.
local function RailGroupInsert(draggedKey, ownerKey, beforeKey)
    draggedKey = string.lower(draggedKey)
    ownerKey = string.lower(ownerKey)
    if draggedKey == ownerKey or not RailIsGroupableKey(draggedKey) or not RailIsGroupableKey(ownerKey) then
        return
    end

    --the dragged panel plus its own members, in their tab order. For a
    --dragged MEMBER (reorder case) this is just the panel itself --
    --members never own groups (SetStoredTabs enforces it).
    local block = { draggedKey }
    local draggedMembers = PanelDocument.GroupMembers(draggedKey)
    if draggedMembers ~= nil then
        for _, m in ipairs(draggedMembers) do
            block[#block + 1] = string.lower(m)
        end
    end
    local inBlock = {}
    for _, k in ipairs(block) do
        inBlock[k] = true
    end

    local list = {}
    for _, k in ipairs(RailGroupTabs(ownerKey)) do
        if not inBlock[k] then
            list[#list + 1] = k
        end
    end
    local pos = #list + 1
    if beforeKey ~= nil then
        for i, k in ipairs(list) do
            if k == string.lower(beforeKey) then
                pos = i
                break
            end
        end
    end
    for bi = #block, 1, -1 do
        table.insert(list, pos, block[bi])
    end
    PanelDocument.SetStoredTabs(ownerKey, list)
end

--Take `memberKey` out of `ownerKey`'s group (storage only: the freed
--panel's layout entry -- preserved inert while it was grouped -- puts
--its button back on the rail at its remembered slot).
local function RailUngroup(memberKey, ownerKey)
    memberKey = string.lower(memberKey)
    ownerKey = string.lower(ownerKey)
    local tabs = PanelDocument.StoredTabs(ownerKey)
    if tabs == nil then
        return
    end
    local kept = {}
    for _, k in ipairs(tabs) do
        if string.lower(k) ~= memberKey then
            kept[#kept + 1] = string.lower(k)
        end
    end
    PanelDocument.SetStoredTabs(ownerKey, kept)
end

--Dissolve `ownerKey`'s group entirely: every member returns to its own
--rail slot.
local function RailUngroupAll(ownerKey)
    ownerKey = string.lower(ownerKey)
    if PanelDocument.StoredTabs(ownerKey) == nil then
        return
    end
    PanelDocument.SetStoredTabs(ownerKey, nil)
end

--Invert a child-parent relationship: `memberKey` becomes the group's
--owner (its button carries the stack and fronts the folder) and
--the old owner becomes an ordinary member. The group's button keeps its
--rail position: the new owner takes the old owner's slot, and the old
--owner inherits the new owner's remembered slot as its own resting
--place should it ever leave the group.
local function RailGroupInvert(memberKey, ownerKey)
    memberKey = string.lower(memberKey)
    ownerKey = string.lower(ownerKey)
    if memberKey == ownerKey then
        return
    end
    local tabs = PanelDocument.StoredTabs(ownerKey)
    if tabs == nil then
        return
    end
    local list = {}
    for _, k in ipairs(tabs) do
        list[#list + 1] = string.lower(k)
    end

    local layout = dmhub.GetSettingValue("iconraillayout") or {}
    local prevMember = layout[memberKey]
    local side, slot = RailFindButton(ownerKey)
    if side ~= nil then
        layout[memberKey] = { side = side, slot = slot }
    elseif layout[ownerKey] ~= nil then
        layout[memberKey] = layout[ownerKey]
    end
    if prevMember ~= nil then
        layout[ownerKey] = prevMember
    end
    dmhub.SetSettingValue("iconraillayout", layout)

    --storing the same list under the new owner releases every key from
    --the old owner's entry (one-window enforcement) in a single write,
    --which also fires the rail rebuild.
    PanelDocument.SetStoredTabs(memberKey, list)
end

--Non-drag reorder parity: move `memberKey` one step left/right among
--the owner's members (the strip lays members out left-to-right in tab
--order on both rails).
local function RailGroupShiftMember(memberKey, ownerKey, delta)
    memberKey = string.lower(memberKey)
    ownerKey = string.lower(ownerKey)
    local members = PanelDocument.GroupMembers(ownerKey)
    if members == nil then
        return
    end
    local idx = nil
    for i, k in ipairs(members) do
        if string.lower(k) == memberKey then
            idx = i
        end
    end
    if idx == nil then
        return
    end
    local target = idx + delta
    if target < 1 or target > #members then
        return
    end
    members[idx], members[target] = members[target], members[idx]
    local list = { ownerKey }
    for _, k in ipairs(members) do
        list[#list + 1] = string.lower(k)
    end
    PanelDocument.SetStoredTabs(ownerKey, list)
end

--Entries for the "+" cut-out at the end of a strip: every available
--registered panel that is not already in this window's group, sorted by
--name. This is the non-drag door into grouping -- the cut-out reads as
--an empty child space, and clicking it should be able to fill that
--space, not only receive a drag.
--
--Panels already sitting elsewhere on the rail are offered too and
--picking one MOVES it in (SetStoredTabs releases a key from wherever
--else it lived); RailLayout parks its own button inert while it is a
--member, so ungrouping later drops it back on its remembered slot. A
--panel that is on no rail at all needs no layout entry to be a member.
local function RailGroupAddEntries(element, ownerKey)
    ownerKey = string.lower(ownerKey)
    local inGroup = {}
    for _, k in ipairs(RailGroupTabs(ownerKey)) do
        inGroup[k] = true
    end

    local entries = {}
    local items = DockablePanel.GetMenuItems(true)
    table.sort(items, function(a, b) return (a.text or "") < (b.text or "") end)
    for _, item in ipairs(items) do
        local name = item.text
        if name ~= nil then
            local memberKey = string.lower(name)
            if not inGroup[memberKey] and RailIsGroupableKey(memberKey) and PanelDocument.Get(name) ~= nil then
                entries[#entries + 1] = {
                    text = name,
                    click = function()
                        element.popup = nil
                        --beforeKey nil = append, so the new panel lands
                        --in the space the "+" itself occupies.
                        RailGroupInsert(memberKey, ownerKey, nil)
                    end,
                }
            end
        end
    end

    if #entries == 0 then
        entries[#entries + 1] = {
            text = "(no panels available)",
            click = function()
                element.popup = nil
            end,
        }
    end
    return entries
end

--While the rail is on, the RAIL hosts panels -- not the docks. Opening a
--panel from a menu, a keybind or a by-name request used to build a dock
--container regardless, and because the docks are slid away in rail mode
--the dock path pulled one back on screen to show it. Take ownership
--instead and do exactly what pressing the panel's rail button does.
if rawget(_G, "RegisterDockablePanelOpenHandler") ~= nil then
    RegisterDockablePanelOpenHandler("iconrail", function(panelName, operation)
        if not RailModeActive() then
            return false
        end
        if DocumentsLayer() == nil then
            return false
        end

        local key = string.lower(panelName)
        --a folder member is shown by its OWNER's window, on its own tab.
        local ownerKey = PanelDocument.WindowOwner(key)
        local doc = RailPanelDocument(ownerKey)
        if doc == nil then
            --not something the rail can host; let the dock have it.
            return false
        end

        local function Raise()
            local d = doc:try_get("_tmp_dialog")
            if d ~= nil and d.valid then
                d:SetAsLastSibling()
                --raising via an explicit user request re-arms a map-mode
                --panel's tool, same as pressing its rail icon -- and
                --brings the requested panel's tab up when the window is
                --sitting on a sibling.
                d:FireEventTree("focusPanelTab", key)
            end
        end

        local function Close()
            --a pinned window is locked open; the icon only raises it.
            if PanelDocument.IsPinned(ownerKey) then
                Raise()
                return
            end
            RailForgetWindow(ownerKey)
            doc:ClosePanel()
        end

        if doc:PresentDocumentOpen() then
            if operation == "show" then
                Raise()
            else
                Close()
            end
            RefreshRails()
            return true
        end

        if operation == "hide" then
            --already closed.
            return true
        end

        --a folder member has no rail button of its own; its window opens
        --anchored at the OWNER's button, the same as clicking it in the
        --group flyout. It must not be given a loose button of its own --
        --it is still filed in the folder.
        local side, slot
        if ownerKey ~= key then
            side, slot = RailFindButton(ownerKey)
        else
            side, slot = RailFindButton(key)
            --give it a button if it has none, so it stays reachable once
            --this window is closed again.
            if side == nil then
                RailAddPanel(panelName, "left")
                side, slot = RailFindButton(key)
            end
        end

        --one transient window at a time, as the rail buttons enforce.
        if g_railTransientKey ~= nil and g_railTransientKey ~= ownerKey then
            local prev = RailPanelDocument(g_railTransientKey)
            if prev ~= nil and not PanelDocument.IsPinned(g_railTransientKey) then
                prev:ClosePanel()
            end
        end
        g_railTransientKey = ownerKey

        local placement = { autoFocus = true }
        if side ~= nil then
            local x, y = RailAnchor(side, slot)
            placement.x = x
            placement.y = y
            placement.anchor = true
        end
        OpenIconRailWindow(key, placement)
        RefreshRails()
        return true
    end)
end

--The "/" hotkey (ChatPanel.cs fires a "slash" chat event when the key is
--pressed with no UI element focused) exists to focus the chat input and
--start typing a command. It only ever reached a chat panel that was
--already built, which in rail mode is usually none at all: the docks are
--slid off screen and chat is summoned as a window. So "/" did nothing.
--
--Here the rail treats "/" as "open chat and start typing": summon the
--chat window exactly as its rail button would, then hand the keystroke
--on via the window's "slashChat" event, which activates the chat tab
--and delivers a "slash" to the input once the deferred build has made
--one. When a dock hosting chat is on screen (rail off / dock slid back
--in), this does nothing and the dock input's own slash handler keeps
--the focus, as before.
local function RailSlashOpensChat()
    local doc = PanelDocument.Get("Chat")
    if doc == nil then
        return
    end

    --already hosted in a rail window -- its own, or as a tab in another
    --window. The engine's slash event only reaches a chat input that is
    --already BUILT, and a background tab may never have built one: raise
    --the host and let it activate the tab and deliver the keystroke.
    --(When the input does exist it also got the engine's event directly;
    --the second "slash" sets the same "/" text and focus, harmlessly.)
    local host = PanelDocument.FindHostDialog("chat")
    if host ~= nil then
        host:SetAsLastSibling()
        host:FireEventTree("slashChat")
        return
    end

    --...or sitting in a dock. Only a dock that is on screen counts: the
    --whole point of this is that the offscreen copy cannot be typed into.
    local reg = DockablePanel.GetRegistration("Chat")
    if reg ~= nil and reg.identifier ~= nil then
        local instance = DockablePanel.FindInstance(reg.identifier)
        if instance ~= nil and instance.valid and instance:FindParentWithClass("offscreen") == nil then
            return
        end
    end

    --the same summon the rail button performs: one transient window at a
    --time (pinned windows are not ours to close), anchored beside the
    --chat icon on whichever rail carries it.
    if g_railTransientKey ~= nil and g_railTransientKey ~= "chat" then
        local prev = RailPanelDocument(g_railTransientKey)
        if prev ~= nil and not PanelDocument.IsPinned(g_railTransientKey) then
            prev:ClosePanel()
        end
    end
    g_railTransientKey = "chat"

    --nil placement is fine: the chat button may have been taken off the
    --rail entirely, in which case PresentDocument uses the remembered spot.
    local placement = nil
    local sides = RailLayout()
    for railSide, list in pairs(sides) do
        for _, e in ipairs(list) do
            if e.key == "chat" then
                local anchorX, anchorY = RailAnchor(railSide, e.slot)
                placement = { x = anchorX, y = anchorY, anchor = true }
            end
        end
    end

    OpenIconRailWindow("Chat", placement)
    RefreshRails()

    local dialog = doc:try_get("_tmp_dialog")
    if dialog ~= nil and dialog.valid then
        dialog:FireEventTree("slashChat")
    end
end

--Entries for "add a panel to this rail": every available registered
--panel not already on a rail, alphabetical. Lives on the rail
--background's context menu (it used to hang off the dock/tray button,
--which is gone) and is the door to the ~40 registered panels beyond the
--curated defaults.
--Forward-declared: the + button is built above the picker that it opens.
local RailShowAddPicker

--Report pointer-on-rail from anywhere inside the column. Every rail child
--calls this because hovering a child does NOT hover the rail root, so the
--root cannot see the pointer by itself. The root owns the dwell and the
--grace period; this only reports.
local function RailNotifyProximity(element, near)
    local rail = element:FindParentWithClass("iconRail")
    if rail == nil or not rail.valid then
        return
    end
    rail:FireEvent("railProximity", near)
end

local function RailAddPanelEntries(element, side)
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
    return entries
end

--Every button on the rail -- panel icons, group members, the rearrange
--STOP button -- sounds the same: the standard UI tick on hover, the
--standard click on press, and on leaving, that same hover tick played
--quieter and detuned down. Our sound list has no dedicated "unhover"
--event, and a softer, lower echo of the hover reads as the gesture
--running backwards without adding a new sound to the library.
--
--The QUIET WINDOW is load-bearing: destroying a hovered panel fires
--dehover (SheetPanel.OnDestroy -> RemoveHover), so any rail rebuild with
--the pointer over a button would tick on the way out and again on the way
--in -- a double click-clack on every drop, pin, group change or layout
--save. RebuildIconRails stamps g_railSoundQuietUntil and the ticks stand
--down for a moment either side of it. Real pointer movement is never that
--close behind a rebuild.
local function RailButtonSound(kind)
    if g_railSoundQuietUntil ~= nil and dmhub.Time() < g_railSoundQuietUntil then
        return
    end
    if kind == "press" then
        audio.FireSoundEvent("Mouse.Click")
    elseif kind == "dehover" then
        audio.FireSoundEvent("Mouse.Hover", { volume = 0.35, pitch = 0.75 })
    else
        audio.FireSoundEvent("Mouse.Hover")
    end
end

----------------------------------------------------------------------
-- Toolkits
-- --------
-- A toolkit is a user-composed floating strip of tool buttons, opened
-- from a rail button of its own ("toolkit:<id>" layout keys). v1 items
-- are panel buttons -- each toggles its panel's window exactly like the
-- panel's own rail button would. The item model is typed (see the
-- iconrailtoolkits setting) so action buttons and live character
-- widgets (Spend Recovery, stamina) can join later without migration.
--
-- Strips are DOCUMENTS-LAYER children like panel windows: they float
-- over the map, drag anywhere, remember their position, and survive
-- rail rebuilds. A Lua reload orphans them; the stale-generation sweep
-- in EnsureIconRail catches them by their iconRailToolkitStrip class.
----------------------------------------------------------------------

local function RailToolkits()
    return dmhub.GetSettingValue("iconrailtoolkits") or {}
end

--writes WITHOUT a rail rebuild: strip drags save their position here
--every frame of the gesture, and the strip is not a rail child anyway.
--Edits that change what the RAIL shows (create/delete/rename) follow up
--with RebuildIconRails themselves.
local function RailWriteToolkits(toolkits)
    dmhub.SetSettingValue("iconrailtoolkits", toolkits)
end

--the open strips, keyed by toolkit id.
local g_railToolkitStrips = {}

local function RailToolkitStripOpen(id)
    local strip = g_railToolkitStrips[id]
    return strip ~= nil and strip.valid
end

--forward-declared: the strip's own chrome closes it, and edits rebuild
--it in place.
local HideToolkitStrip
local ShowToolkitStrip

--forward-declared: summoned from the strip's + menu, but built on the
--icon picker defined further down with the toolkit dialogs.
local RailScriptButtonDialog

--Kill-switch cache for community button packs: packid -> message for
--every remotely disabled pack (PANEL_LIBRARY_BRIEF.md). Fetched once
--the first time it is needed and refreshed whenever the Panel Library
--opens; checked before any PACK-sourced button runs. nil = not yet
--fetched (a fetch is kicked off and the check errs on the side of
--running -- the cache converges within seconds of first use).
local g_buttonPackKilled = nil
local function RefreshButtonPackKilled()
    --older engine builds have no buttonpack bridge; everything
    --pack-related degrades to absent.
    if rawget(_G, "buttonpack") == nil then
        return
    end
    buttonpack.QueryKilled{
        success = function(killed)
            if mod.unloaded then
                return
            end
            g_buttonPackKilled = killed
        end,
        failure = function(err)
            --keep whatever cache we had; a transient failure must not
            --unkill anything.
        end,
    }
end

--How many VM instructions a pack button may execute per click before
--the watchdog kills it: generous for real work, fatal for infinite
--loops. Local buttons are exempt (the author's own machine).
local SCRIPT_BUTTON_INSTRUCTION_BUDGET = 20000000

--Run a script button's Lua chunk. Plain chunk, standard global
--environment, full engine access -- the same trust posture as mods and
--dice scripts (PANEL_LIBRARY_BRIEF.md, "Script button action
--contract"). Failures are LOUD: the button flashes the error state and
--the message opens in a dialog; a broken button must never fail
--silently.
--
--Buttons that came from a community pack (item.pack = packid) run
--INSULATED: the kill switch is checked first, and the chunk executes
--under an instruction-count watchdog so a runaway script cannot wedge
--the app.
local function RunToolkitScriptButton(item, element)
    local packid = item.pack
    if packid ~= nil then
        if g_buttonPackKilled == nil then
            RefreshButtonPackKilled()
        end
        local killedMessage = nil
        if g_buttonPackKilled ~= nil then
            killedMessage = g_buttonPackKilled[packid]
        end
        if killedMessage ~= nil then
            local message = "This button's pack has been disabled."
            if type(killedMessage) == "string" and killedMessage ~= "" then
                message = message .. "\n\n" .. killedMessage
            end
            gui.ModalMessage{
                title = "Button disabled",
                message = message,
            }
            return
        end
    end

    local chunk, loadErr = load(ScriptButtonCode(item.script or ""), "script-button:" .. (item.name or "button"))
    local ok, err
    if chunk == nil then
        ok, err = false, loadErr
    elseif packid ~= nil then
        debug.sethook(function()
            debug.sethook()
            error("this button exceeded its execution budget and was stopped", 2)
        end, "", SCRIPT_BUTTON_INSTRUCTION_BUDGET)
        ok, err = pcall(chunk)
        debug.sethook()
    else
        ok, err = pcall(chunk)
    end
    if ok then
        return
    end
    if element ~= nil and element.valid then
        element:SetClass("scriptError", true)
        dmhub.Schedule(1.2, function()
            if mod.unloaded then
                return
            end
            if element.valid then
                element:SetClass("scriptError", false)
            end
        end)
    end
    gui.ModalMessage{
        title = "Script button error",
        message = tostring(err),
    }
end

--Toggle a panel from a toolkit button: the same open/close/raise the
--panel's own rail button performs (transient-window rule included),
--anchored beside the strip rather than beside the rail.
local function ToolkitTogglePanel(panelKey, strip)
    local key = string.lower(panelKey)
    local verb, ownerKey, doc, d = RailActivation(key)
    if doc == nil then
        return
    end
    if verb == "switch" or verb == "raise" then
        --a pinned window cannot be closed from its button, and a folder
        --window sitting on a sibling tab switches rather than closing.
        d:SetAsLastSibling()
        d:FireEventTree("focusPanelTab", key)
        RefreshRails()
        return
    end
    if verb == "close" then
        RailForgetWindow(ownerKey)
        doc:ClosePanel()
        RefreshRails()
        return
    end

    --one transient window at a time, as everywhere else.
    if g_railTransientKey ~= nil and g_railTransientKey ~= ownerKey then
        local prev = RailPanelDocument(g_railTransientKey)
        if prev ~= nil and not PanelDocument.IsPinned(g_railTransientKey) then
            prev:ClosePanel()
        end
    end
    g_railTransientKey = ownerKey

    local placement = { autoFocus = true }
    if strip ~= nil and strip.valid then
        --just under the strip, so the window reads as summoned by it.
        --An anchored open still yields to wherever the user last dragged
        --this panel's window.
        placement.x = strip.x
        placement.y = strip.y + 64
        placement.anchor = true
    end
    OpenIconRailWindow(key, placement)
    RefreshRails()
end

HideToolkitStrip = function(id)
    local strip = g_railToolkitStrips[id]
    g_railToolkitStrips[id] = nil
    if strip ~= nil and strip.valid then
        strip:DestroySelf()
    end
end

ShowToolkitStrip = function(id, anchorX, anchorY)
    if RailToolkitStripOpen(id) then
        g_railToolkitStrips[id]:SetAsLastSibling()
        return
    end
    local layer = DocumentsLayer()
    local tk = RailToolkits()[id]
    if layer == nil or tk == nil then
        return
    end

    local strip

    --Item and name edits rewrite the record and rebuild the strip in
    --place -- simpler than in-place child surgery, imperceptible at this
    --size. Rail chrome that shows the toolkit's name/state follows via
    --the rebuild/refresh the specific edit asks for.
    local function EditToolkit(fn, rebuildRail)
        local t = RailToolkits()
        local rec = t[id]
        if rec == nil then
            return
        end
        fn(rec)
        RailWriteToolkits(t)
        local x, y = nil, nil
        if strip ~= nil and strip.valid then
            x = strip.x
            y = strip.y
        end
        HideToolkitStrip(id)
        ShowToolkitStrip(id, x, y)
        if rebuildRail then
            RebuildIconRails()
        else
            RefreshRails()
        end
    end

    --the add-a-panel menu: curated panels not already in the toolkit.
    --(A panel may be on the rail AND in a toolkit -- toolkits are
    --shortcuts, not filing.)
    local function AddPanelEntries(parentElement)
        local have = {}
        for _, item in ipairs(RailToolkits()[id] and RailToolkits()[id].items or {}) do
            if item.type == "panel" then
                have[string.lower(item.panel or "")] = true
            end
        end
        local entries = {}
        for _, name in ipairs(g_iconRailPanels) do
            local k = string.lower(name)
            if not have[k] and PanelDocument.Get(name) ~= nil then
                entries[#entries + 1] = {
                    text = "Add: " .. name,
                    click = function()
                        parentElement.popup = nil
                        EditToolkit(function(rec)
                            rec.items = rec.items or {}
                            rec.items[#rec.items + 1] = { type = "panel", panel = k }
                        end)
                    end,
                }
            end
        end
        return entries
    end

    local buttonPanels = {}
    for i, item in ipairs(tk.items or {}) do
        --unknown item types are skipped: a future version's action or
        --widget items degrade to nothing rather than erroring here.
        if item.type == "panel" then
            local itemKey = string.lower(item.panel or "")
            local reg = DockablePanel.GetRegistration(itemKey)
            local itemName = (reg ~= nil and reg.name) or item.panel or "?"
            local itemIcon = (reg ~= nil and reg.icon) or "icons/icon_app/icon_app_107.png"
            local idx = i
            local button
            button = gui.Panel{
                classes = {"iconRailButton", cond(PanelDocument.IsPanelActive(itemKey), "active")},
                bgimage = true,
                blurBackground = true,
                width = ICON_RAIL_BUTTON,
                height = ICON_RAIL_BUTTON,
                flow = "none",
                hmargin = 2,
                swallowPress = true,

                hover = function(element)
                    RailButtonSound("hover")
                    gui.Tooltip(string.upper(itemName))(element)
                end,
                dehover = function(element)
                    RailButtonSound("dehover")
                end,
                press = function(element)
                    RailButtonSound("press")
                end,
                click = function(element)
                    ToolkitTogglePanel(itemKey, strip)
                    if strip ~= nil and strip.valid then
                        strip:FireEventTree("refreshToolkit")
                    end
                end,
                rightClick = function(element)
                    local entries = {
                        {
                            text = cond(PanelDocument.IsPanelActive(itemKey), "Close", "Open"),
                            click = function()
                                element.popup = nil
                                ToolkitTogglePanel(itemKey, strip)
                            end,
                        },
                    }
                    if idx > 1 then
                        entries[#entries + 1] = {
                            text = "Move left",
                            click = function()
                                element.popup = nil
                                EditToolkit(function(rec)
                                    rec.items[idx], rec.items[idx - 1] = rec.items[idx - 1], rec.items[idx]
                                end)
                            end,
                        }
                    end
                    if idx < #(tk.items or {}) then
                        entries[#entries + 1] = {
                            text = "Move right",
                            click = function()
                                element.popup = nil
                                EditToolkit(function(rec)
                                    rec.items[idx], rec.items[idx + 1] = rec.items[idx + 1], rec.items[idx]
                                end)
                            end,
                        }
                    end
                    entries[#entries + 1] = {
                        text = "Remove from Toolkit",
                        click = function()
                            element.popup = nil
                            EditToolkit(function(rec)
                                table.remove(rec.items, idx)
                            end)
                        end,
                    }
                    element.popup = gui.ContextMenu{ entries = entries }
                end,

                --keeps the lit state honest as the panel opens and closes
                --by any path (fired on the strip's think cadence and after
                --every toolkit click).
                refreshToolkit = function(element)
                    element:SetClass("active", PanelDocument.IsPanelActive(itemKey))
                end,

                gui.Panel{
                    classes = {"iconRailIcon"},
                    bgimage = itemIcon,
                    width = 20,
                    height = 20,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },

                --the same close hint the rail buttons carry: hovering a
                --button whose panel is open means a click will close it.
                gui.Panel{
                    classes = {"iconRailCloseHint"},
                    floating = true,
                    bgimage = "phosphor/x-bold.png",
                    width = 16,
                    height = 16,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            }
            buttonPanels[#buttonPanels + 1] = button
        elseif item.type == "script" then
            --a custom script button: click runs the stored Lua chunk.
            local idx = i
            local itemRef = item
            local itemName = item.name or "Script"
            local button
            button = gui.Panel{
                classes = {"iconRailButton"},
                bgimage = true,
                blurBackground = true,
                width = ICON_RAIL_BUTTON,
                height = ICON_RAIL_BUTTON,
                flow = "none",
                hmargin = 2,
                swallowPress = true,

                hover = function(element)
                    RailButtonSound("hover")
                    gui.Tooltip(string.upper(itemName))(element)
                end,
                dehover = function(element)
                    RailButtonSound("dehover")
                end,
                press = function(element)
                    RailButtonSound("press")
                end,
                click = function(element)
                    RunToolkitScriptButton(itemRef, element)
                end,
                rightClick = function(element)
                    local entries = {
                        {
                            text = "Run",
                            click = function()
                                element.popup = nil
                                RunToolkitScriptButton(itemRef, element)
                            end,
                        },
                        {
                            text = "Edit Script...",
                            click = function()
                                element.popup = nil
                                RailScriptButtonDialog(id, idx)
                            end,
                        },
                    }
                    if idx > 1 then
                        entries[#entries + 1] = {
                            text = "Move left",
                            click = function()
                                element.popup = nil
                                EditToolkit(function(rec)
                                    rec.items[idx], rec.items[idx - 1] = rec.items[idx - 1], rec.items[idx]
                                end)
                            end,
                        }
                    end
                    if idx < #(tk.items or {}) then
                        entries[#entries + 1] = {
                            text = "Move right",
                            click = function()
                                element.popup = nil
                                EditToolkit(function(rec)
                                    rec.items[idx], rec.items[idx + 1] = rec.items[idx + 1], rec.items[idx]
                                end)
                            end,
                        }
                    end
                    entries[#entries + 1] = {
                        text = "Remove from Toolkit",
                        click = function()
                            element.popup = nil
                            EditToolkit(function(rec)
                                table.remove(rec.items, idx)
                            end)
                        end,
                    }
                    element.popup = gui.ContextMenu{ entries = entries }
                end,

                gui.Panel{
                    classes = {"iconRailIcon"},
                    bgimage = item.icon or "phosphor/lightning.png",
                    width = 20,
                    height = 20,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            }
            buttonPanels[#buttonPanels + 1] = button
        end
    end

    --the + at the strip's end: quiet until hovered, same voice as the
    --rail's own add affordances.
    buttonPanels[#buttonPanels + 1] = gui.Panel{
        classes = {"iconRailButton"},
        bgimage = true,
        width = ICON_RAIL_BUTTON,
        height = ICON_RAIL_BUTTON,
        flow = "none",
        hmargin = 2,
        swallowPress = true,
        hover = function(element)
            RailButtonSound("hover")
            gui.Tooltip("Add to this toolkit")(element)
        end,
        press = function(element)
            RailButtonSound("press")
            local entries = AddPanelEntries(element)
            entries[#entries + 1] = {
                text = "New script button...",
                click = function()
                    element.popup = nil
                    RailScriptButtonDialog(id, nil)
                end,
            }
            element.popup = gui.ContextMenu{ entries = entries }
        end,
        gui.Panel{
            classes = {"iconRailIcon"},
            bgimage = "phosphor/plus-bold.png",
            width = 16,
            height = 16,
            halign = "center",
            valign = "center",
            interactable = false,
        },
    }

    --starting position: remembered spot, else beside the summoning
    --button, else a sane default; clamped on screen.
    local x = tk.x or anchorX or 200
    local y = tk.y or anchorY or 200
    local uiW = IconRailUIWidth()
    x = math.max(8, math.min(x, uiW - 240))
    y = math.max(40, math.min(y, 940))

    strip = gui.Panel{
        classes = {"iconRailToolkitStrip"},
        styles = ThemeEngine.MergeStyles(IconRailStyles()),
        bgimage = true,
        --the card takes the DARK panel fill and the buttons keep their
        --frosted rail-button look on top of it, so the tiles read
        --raised against the card (Venla 2026-08-12).
        bgcolor = "#0a0a0b",
        border = 0,
        cornerRadius = 8,
        halign = "left",
        valign = "top",
        x = x,
        y = y,
        width = "auto",
        height = "auto",
        flow = "vertical",
        swallowPress = true,
        draggable = true,

        drag = function(element)
            element.x = element.xdrag
            element.y = element.ydrag
            element:SetAsLastSibling()
            local t = RailToolkits()
            if t[id] ~= nil then
                t[id].x = element.x
                t[id].y = element.y
                RailWriteToolkits(t)
            end
        end,
        click = function(element)
            element:SetAsLastSibling()
        end,

        --the lit states poll, like the rail's own refresh cadence.
        thinkTime = 0.5,
        think = function(element)
            element:FireEventTree("refreshToolkit")
        end,

        destroy = function(element)
            --only clear our own registration: a rebuild registers the
            --replacement under the same id before this fires.
            if g_railToolkitStrips[id] == element then
                g_railToolkitStrips[id] = nil
            end
        end,

        --title row: the toolkit's name (rename on double-click) and its
        --close x.
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = 20,
            halign = "left",
            tmargin = 6,
            lmargin = 10,
            rmargin = 8,

            gui.Label{
                text = tk.name or "Toolkit",
                uppercase = true,
                fontSize = 12,
                bold = true,
                color = "#F2EDE1",
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 8,
                textWrap = false,
                editableOnDoubleClick = true,
                characterLimit = 24,
                change = function(element)
                    local newName = element.text
                    EditToolkit(function(rec)
                        rec.name = newName
                    end, true)
                end,
            },

            gui.Panel{
                classes = {"panelDocumentCloseButton"},
                bgimage = "phosphor/x-bold.png",
                width = 12,
                height = 12,
                valign = "center",
                swallowPress = true,
                click = function(element)
                    HideToolkitStrip(id)
                    RefreshRails()
                end,
            },
        },

        --the tool buttons themselves.
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "left",
            margin = 6,
            children = buttonPanels,
        },
    }

    layer:AddChild(strip)
    g_railToolkitStrips[id] = strip
end

local function ToggleToolkitStrip(id, anchorX, anchorY)
    if RailToolkitStripOpen(id) then
        HideToolkitStrip(id)
    else
        ShowToolkitStrip(id, anchorX, anchorY)
    end
end

--Create a toolkit with the given name and icon, give it a rail button on
--`side`, and open its strip beside that button so the + affordance is
--immediately in reach.
local function RailCreateToolkitNamed(side, name, icon)
    local toolkits = RailToolkits()
    local id = string.lower(dmhub.GenerateGuid())
    toolkits[id] = { name = name, icon = icon, items = {} }
    RailWriteToolkits(toolkits)
    RailAddPanel("toolkit:" .. id, side)
    local bside, slot = RailFindButton("toolkit:" .. id)
    local ax, ay
    if bside ~= nil then
        ax, ay = RailAnchor(bside, slot)
    end
    ShowToolkitStrip(id, ax, ay)
    RefreshRails()
end

--The icons offered for a toolkit's rail button: a curated slice of the
--Phosphor pack (the icon set the rest of the rail chrome draws from), so
--a custom toolkit sits on the rail in the same visual language as the
--built-in buttons. Curated rather than searchable-all-9k because the
--picker's job is "make this button recognizably mine" and a screenful of
--themed choices answers that faster than a search box. Ordered in rough
--themes: tools/authoring, combat, exploration, story/lore, people,
--treasure, nature, time/misc.
local g_toolkitIconOptions = {
    "toolbox", "wrench", "hammer", "gear", "sliders-horizontal", "paint-brush", "palette", "pencil-simple",
    "ruler", "compass", "map-trifold", "map-pin", "sword", "shield", "crosshair-simple", "skull",
    "dice-six", "target", "strategy", "cards", "flag-banner", "campfire", "tent", "horse",
    "book-open-text", "books", "scroll", "bookmark-simple", "folder", "image", "film-slate", "music-notes",
    "users-three", "handshake", "chat-circle", "crown", "ghost", "eye", "heart", "star",
    "treasure-chest", "coins", "backpack", "key", "lock", "flask", "magic-wand", "sparkle",
    "fire", "lightning", "sun", "moon", "tree-evergreen", "mountains", "castle-turret", "paw-print",
    "bell", "clock", "calendar", "lightbulb",
}

--Shared width of the icon grid, so the name input row in both dialogs
--can align its edges to the grid exactly (10 cells at 36px pitch).
local TOOLKIT_ICON_GRID_WIDTH = 10 * 36

--A grid of the curated icons, one click to select. Exposes .value like
--gui.IconEditor did so the dialogs' save paths stay unchanged. An icon
--from before this picker existed (e.g. an ability-library image) simply
--has no cell selected; the value is kept unless a cell is clicked.
local function RailToolkitIconPicker(initialValue)
    local m_value = initialValue
    local cells = {}
    for _, name in ipairs(g_toolkitIconOptions) do
        local iconid = "phosphor/" .. name .. ".png"
        cells[#cells + 1] = gui.Panel{
            classes = {"toolkitIconCell", cond(iconid == m_value, "selected")},
            width = 34,
            height = 34,
            margin = 1,
            bgimage = true,
            data = {icon = iconid},
            click = function(element)
                m_value = iconid
                for _, cell in ipairs(cells) do
                    cell:SetClass("selected", cell.data.icon == m_value)
                end
            end,
            gui.Panel{
                classes = {"toolkitIconGlyph"},
                bgimage = iconid,
                width = 22,
                height = 22,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        }
    end

    return gui.Panel{
        flow = "horizontal",
        wrap = true,
        width = TOOLKIT_ICON_GRID_WIDTH,
        height = "auto",
        halign = "center",
        valign = "center",
        vmargin = 6,
        styles = ThemeEngine.MergeStyles({
            {
                selectors = {"toolkitIconCell"},
                bgcolor = "clear",
                cornerRadius = 4,
                transitionTime = 0.1,
            },
            {
                selectors = {"toolkitIconCell", "hover"},
                bgcolor = "@bgAlt",
            },
            {
                selectors = {"toolkitIconCell", "selected"},
                bgcolor = "@bgAlt",
                border = 2,
                borderColor = "@accent",
            },
            {
                selectors = {"toolkitIconGlyph"},
                bgcolor = "@fg",
            },
            {
                selectors = {"toolkitIconGlyph", "parent:hover"},
                bgcolor = "@fgStrong",
            },
            {
                selectors = {"toolkitIconGlyph", "parent:selected"},
                bgcolor = "@fgStrong",
            },
        }),
        GetValue = function(element)
            return m_value
        end,
        SetValue = function(element, val)
            m_value = val
            for _, cell in ipairs(cells) do
                cell:SetClass("selected", cell.data.icon == m_value)
            end
        end,
        children = cells,
    }
end

--The same two fields, for a toolkit that already exists. Shares its shape
--with the create dialog on purpose: the thing you are editing is the same
--thing you were asked for when you made it.
local function RailEditToolkit(id)
    local toolkits = RailToolkits()
    local tk = toolkits[id]
    if tk == nil then
        return
    end

    --the input theme class pads additively (hpad 10): subtract it so the
    --rendered box spans exactly the grid width below.
    local nameInput = gui.Input{
        text = tk.name or "Toolkit",
        placeholderText = "Toolkit name",
        width = TOOLKIT_ICON_GRID_WIDTH - 20,
        height = 28,
        halign = "center",
        valign = "center",
    }

    local iconEditor = RailToolkitIconPicker(tk.icon or "phosphor/toolbox.png")

    gamehud:ModalDialog{
        title = "Edit tool panel",
        width = 480,
        height = 470,
        buttonsHalign = "center",
        flow = "vertical",
        --ModalDialog strips width/height from its client-panel args to size
        --the dialog frame, leaving the client panel at the 100x100 default
        --with our taller content centered on -- and overflowing -- it.
        --selfStyle passes through, so size the client panel to its content.
        selfStyle = {
            width = "100%",
            height = "auto",
        },
        buttons = {
            {
                text = "Save",
                click = function()
                    local current = RailToolkits()
                    local entry = current[id]
                    if entry == nil then
                        return
                    end
                    local name = nameInput.text
                    if name == nil or name == "" then
                        name = "Toolkit"
                    end
                    entry.name = name
                    local icon = nil
                    pcall(function() icon = iconEditor.value end)
                    if icon == "" then
                        icon = nil
                    end
                    entry.icon = icon
                    RailWriteToolkits(current)
                    RefreshRails()
                end,
            },
            {
                text = "Cancel",
                escapeActivates = true,
            },
        },

        nameInput,
        iconEditor,
    }
end

--Ask for a name and an icon FIRST, then create. A toolkit is a thing the
--user is making rather than a panel they are summoning, and the two
--things that make it theirs -- what it is called and what it looks like
--on the rail -- are exactly what a wall of identical unnamed toolboxes
--would cost them. Both are optional: dismissing the fields still yields a
--usable toolkit with the old defaults.
local function RailCreateToolkit(side)
    --fills the row up to the info icon (24px + 8px gap), so the input's
    --left edge and the icon's right edge align with the grid below. The
    --input theme class pads ADDITIVELY (hpad 10, deliberately no
    --borderBox -- see DefaultStyles' input rule), so the rendered box is
    --20 wider than asked: subtract it here or the icon overshoots.
    local nameInput = gui.Input{
        text = "",
        placeholderText = "Toolkit name",
        width = TOOLKIT_ICON_GRID_WIDTH - 32 - 20,
        height = 28,
        valign = "center",
    }

    --seeded with the rail's own toolbox so the preview is never empty and
    --"just press Create" still gives a sensible button.
    local iconEditor = RailToolkitIconPicker("phosphor/toolbox.png")

    gamehud:ModalDialog{
        title = "New tool panel",
        width = 480,
        height = 470,
        buttonsHalign = "center",
        flow = "vertical",
        --see RailEditToolkit: size the client panel to its content, since
        --ModalDialog strips width/height and would leave it 100x100.
        selfStyle = {
            width = "100%",
            height = "auto",
        },
        buttons = {
            {
                text = "Create",
                click = function()
                    local name = nameInput.text
                    if name == nil or name == "" then
                        name = "Toolkit"
                    end
                    local icon = nil
                    pcall(function() icon = iconEditor.value end)
                    if icon == "" then
                        icon = nil
                    end
                    RailCreateToolkitNamed(side, name, icon)
                end,
            },
            {
                text = "Cancel",
                escapeActivates = true,
            },
        },

        gui.Panel{
            flow = "horizontal",
            width = TOOLKIT_ICON_GRID_WIDTH,
            height = "auto",
            halign = "center",
            vmargin = 4,
            nameInput,
            gui.Panel{
                classes = {"iconButton"},
                bgimage = "phosphor/info.png",
                lmargin = 8,
                valign = "center",
                linger = gui.Tooltip("Name and icon can be changed later from the toolkit's right-click menu."),
            },
        },
        iconEditor,
    }
end

--Seed for a brand-new script button's Lua file (see Edit code in the
--dialog below): a working example plus a short tour of favorite APIs.
--Script buttons run with the full engine API (RunToolkitScriptButton),
--so everything shown here is real and clickable as-is.
local SCRIPT_BUTTON_TEMPLATE = [[-- Hello! Here is a guide on custom buttons.
--
-- The code you write here runs every time you click your button.
-- Replace the example below with your own code.
-- Save this file and the button picks up the change instantly.



chat.Send("Hello from my new button!")


-- The full DMHub Lua API is available. Some examples you can use:
--
--   chat.Send("Hello, table!")                        -- post to chat
--   dmhub.Roll{ roll = "2d6", description = "Luck" }  -- roll dice on screen
--
--   local token = dmhub.currentToken                  -- your character
--   if token ~= nil then
--       chat.Send(token.name .. " waves!")
--   end
--
-- You can also style the rail button itself with directives: comment
-- lines like the ones below, each at the START of its own line.
-- (The examples here are indented so they stay switched off.)
--
--   -- @slots 2            take two rail spots, like a character card
--   -- @bgcolor #2244aa    tint the button's background
--   -- @bggradient #88bbee #224466   top-to-bottom gradient background
--   -- @opacity 0.5        make the button see-through
--   -- @label Recoveries Available To Spend
--                          show a live value (a GoblinScript formula,
--                          evaluated on your character) instead of the icon
--
-- A bare form works too ("@slots 2" on its own line, no leading --),
-- but your editor's Lua checker will underline it; the -- form keeps
-- your editor quiet.
--
]]

--Create (idx == nil) or edit (idx set) a script button on a toolkit.
--Assigned to the forward declaration next to the strip code, which
--summons this from the strip's + menu and each button's context menu.
RailScriptButtonDialog = function(toolkitid, idx)
    local toolkits = RailToolkits()
    local existing = nil

    --"button:<id>" targets edit a STANDALONE rail button rather than a
    --toolkit item.
    local sbuttonEditId = nil
    if toolkitid ~= nil then
        sbuttonEditId = string.match(toolkitid, "^button:(.+)$")
    end
    if sbuttonEditId ~= nil then
        existing = (dmhub.GetSettingValue("iconrailscriptbuttons") or {})[sbuttonEditId]
        if type(existing) ~= "table" then
            return
        end
    elseif toolkitid ~= nil then
        local tk = toolkits[toolkitid]
        if tk == nil then
            return
        end
        if idx ~= nil then
            existing = (tk.items or {})[idx]
            if existing == nil or existing.type ~= "script" then
                return
            end
        end
    end

    --LIBRARY MODE (no target named -- the Panel Library's "New button"
    --tile): the dialog grows an "Add to" dropdown. The DEFAULT is a
    --standalone button directly on the rail -- no tool panel required
    --(owner decision 2026-08-17); toolkits and "New tool panel" remain
    --as destinations for people organizing buttons into strips.
    local targetDropdown = nil
    if toolkitid == nil then
        local sorted = {}
        for tid, rec in pairs(toolkits) do
            if type(rec) == "table" then
                sorted[#sorted + 1] = { id = tid, name = rec.name or "Toolkit" }
            end
        end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        local options = {
            { id = "__rail", text = "On the rail" },
        }
        for _, e in ipairs(sorted) do
            options[#options + 1] = { id = e.id, text = e.name }
        end
        options[#options + 1] = { id = "__new", text = "New tool panel" }
        targetDropdown = gui.Dropdown{
            options = options,
            idChosen = "__rail",
            width = 200,
            height = 26,
            valign = "center",
        }
    end

    local nameInput = gui.Input{
        text = (existing ~= nil and existing.name) or "",
        placeholderText = "Button name",
        width = TOOLKIT_ICON_GRID_WIDTH - 20,
        height = 28,
        halign = "center",
        valign = "center",
    }

    --a one-line description: shown on the community card if this button
    --is ever published.
    local buttonDescInput = gui.Input{
        text = (existing ~= nil and existing.description) or "",
        placeholderText = "Short description (shown when shared)",
        width = TOOLKIT_ICON_GRID_WIDTH - 20,
        height = 28,
        halign = "center",
        valign = "center",
    }

    local iconEditor = RailToolkitIconPicker((existing ~= nil and existing.icon) or "phosphor/lightning.png")

    --pure Lua, nothing between the author and the engine (Option A --
    --see the ledger's amended action-contract decision) -- but authored
    --in the user's own editor rather than an inline text box: Edit code
    --opens a watched .lua file (seeded from SCRIPT_BUTTON_TEMPLATE when
    --the button has no code yet) and every save in the editor flows
    --back here; Create/Save then commits it like before. Same rig as
    --the Dice Studio's script section.
    local m_script = (existing ~= nil and existing.script) or ""
    local m_watcher = nil
    local scriptStatusLabel
    local scriptSnippetLabel

    local function DestroyScriptWatcher()
        if m_watcher ~= nil then
            m_watcher:Destroy()
            m_watcher = nil
        end
    end

    local function RefreshScriptStatus()
        if scriptStatusLabel == nil or not scriptStatusLabel.valid then
            return
        end
        if m_script == "" then
            scriptStatusLabel.text = "No code yet. Edit code opens a Lua file in your text editor; every save lands here."
            scriptStatusLabel.selfStyle.color = "#bbbbbbff"
        else
            --syntax check only: load compiles without executing. Bare
            --@directive lines are commented out first, exactly as the
            --click path does.
            local chunk, err = load(ScriptButtonCode(m_script), "script-button")
            if chunk == nil then
                scriptStatusLabel.text = "Syntax error: " .. tostring(err)
                scriptStatusLabel.selfStyle.color = "#ff8888ff"
            else
                scriptStatusLabel.text = "Code OK."
                scriptStatusLabel.selfStyle.color = "#88ff88ff"
            end
        end
        if scriptSnippetLabel ~= nil and scriptSnippetLabel.valid then
            local snippet = m_script
            if snippet == "" then
                snippet = "(no code attached)"
            elseif #snippet > 240 then
                snippet = string.sub(snippet, 1, 240) .. "..."
            end
            scriptSnippetLabel.text = snippet
        end
    end

    scriptStatusLabel = gui.Label{
        width = "100%",
        height = "auto",
        halign = "left",
        vmargin = 4,
        fontSize = 13,
        color = "#bbbbbbff",
        text = "",
    }

    scriptSnippetLabel = gui.Label{
        width = "100%",
        height = "auto",
        halign = "left",
        fontSize = 12,
        color = "#888888ff",
        bgimage = "panels/square.png",
        bgcolor = "#00000055",
        pad = 6,
        borderBox = true,
        text = "(no code attached)",
    }

    local codeSection = gui.Panel{
        flow = "vertical",
        width = TOOLKIT_ICON_GRID_WIDTH - 20,
        height = "auto",
        halign = "center",
        destroy = function()
            DestroyScriptWatcher()
        end,
        create = function()
            RefreshScriptStatus()
        end,
        gui.Button{
            text = "Edit code...",
            width = 160,
            height = 28,
            halign = "left",
            fontSize = 16,
            click = function()
                DestroyScriptWatcher()

                local seed = m_script
                if seed == "" then
                    seed = SCRIPT_BUTTON_TEMPLATE
                end

                --OpenTextFileInConnectedEditor caps filenames at 48
                --chars: "railbutton-" (11) + up to 33 of the name + ".lua".
                local base = string.gsub(nameInput.text or "", "[^%w%-]", "")
                if base == "" then
                    base = "button"
                end
                local filename = string.sub("railbutton-" .. base, 1, 44) .. ".lua"
                m_watcher = dmhub.OpenTextFileInConnectedEditor(filename, seed, function(contents)
                    m_script = contents or ""
                    RefreshScriptStatus()
                end)
                if m_watcher == nil then
                    gui.ModalMessage{
                        title = "Could not open editor",
                        message = "Could not open an external text editor for the button's code.",
                    }
                end
            end,
        },
        scriptStatusLabel,
        scriptSnippetLabel,
    }

    gamehud:ModalDialog{
        title = cond(existing == nil, "New script button", "Edit script button"),
        width = 480,
        height = 660,
        buttonsHalign = "center",
        flow = "vertical",
        --see RailEditToolkit: size the client panel to its content, since
        --ModalDialog strips width/height and would leave it 100x100.
        selfStyle = {
            width = "100%",
            height = "auto",
        },
        buttons = {
            {
                text = cond(existing == nil, "Create", "Save"),
                click = function()
                    local name = nameInput.text
                    if name == nil or name == "" then
                        name = "Script"
                    end
                    local icon = nil
                    pcall(function() icon = iconEditor.value end)
                    if icon == nil or icon == "" then
                        icon = "phosphor/lightning.png"
                    end
                    local item = { type = "script", name = name, icon = icon, script = m_script or "" }
                    local desc = buttonDescInput.text
                    if desc ~= nil and desc ~= "" then
                        item.description = desc
                    end

                    --standalone edit: update the definition in place and
                    --redraw the rail (name/icon may have changed). pack
                    --(came from the community) and packid (shared BY the
                    --user) both survive the rebuild.
                    if sbuttonEditId ~= nil then
                        item.pack = existing.pack
                        item.packid = existing.packid
                        local defs = dmhub.GetSettingValue("iconrailscriptbuttons") or {}
                        defs[sbuttonEditId] = item
                        dmhub.SetSettingValue("iconrailscriptbuttons", defs)
                        RebuildIconRails()
                        return
                    end

                    --library mode with "On the rail" chosen: mint a
                    --standalone button, no toolkit involved.
                    local railChoice = nil
                    if toolkitid == nil then
                        railChoice = "__rail"
                        pcall(function() railChoice = targetDropdown.idChosen end)
                    end
                    if railChoice == "__rail" then
                        local id = string.lower(dmhub.GenerateGuid())
                        local defs = dmhub.GetSettingValue("iconrailscriptbuttons") or {}
                        defs[id] = item
                        dmhub.SetSettingValue("iconrailscriptbuttons", defs)
                        RailAddPanel("button:" .. id, "left")
                        return
                    end

                    local t = RailToolkits()
                    local target = toolkitid
                    if target == nil then
                        if railChoice ~= "__new" and t[railChoice] ~= nil then
                            target = railChoice
                        else
                            target = string.lower(dmhub.GenerateGuid())
                            t[target] = { name = "My Buttons", icon = "phosphor/lightning.png", items = {} }
                        end
                    end
                    local rec = t[target]
                    if rec == nil then
                        return
                    end
                    rec.items = rec.items or {}
                    if idx ~= nil and rec.items[idx] ~= nil then
                        --a shared toolkit item keeps its packid through
                        --the rebuild, so Update still targets its pack.
                        item.packid = rec.items[idx].packid
                        rec.items[idx] = item
                    else
                        rec.items[#rec.items + 1] = item
                    end
                    RailWriteToolkits(t)
                    if toolkitid == nil then
                        --from the library: make the result visible. The
                        --toolkit gets its rail button (no-op if already
                        --there) and its strip opens beside it.
                        RailAddPanel("toolkit:" .. target, "left")
                        local bside, slot = RailFindButton("toolkit:" .. target)
                        local ax, ay
                        if bside ~= nil then
                            ax, ay = RailAnchor(bside, slot)
                        end
                        HideToolkitStrip(target)
                        ShowToolkitStrip(target, ax, ay)
                        RefreshRails()
                    else
                        --rebuild the strip in place if it is open.
                        local strip = g_railToolkitStrips[target]
                        local x, y = nil, nil
                        if strip ~= nil and strip.valid then
                            x = strip.x
                            y = strip.y
                        end
                        HideToolkitStrip(target)
                        ShowToolkitStrip(target, x, y)
                        RefreshRails()
                    end
                end,
            },
            {
                text = "Cancel",
                escapeActivates = true,
            },
        },

        gui.Panel{
            classes = {cond(targetDropdown == nil, "collapsed")},
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",
            vmargin = 2,
            gui.Label{
                text = "Add to:",
                fontSize = 13,
                width = "auto",
                height = "auto",
                valign = "center",
                rmargin = 8,
            },
            targetDropdown,
        },
        nameInput,
        buttonDescInput,
        codeSection,
        iconEditor,
    }
end

--Publishing moved BUTTON-first (owner decision 2026-08-18: "you aren't
--supposed to be able to publish toolkits -- it's just for buttons").
--The old toolkit right-click "Publish..." (RailPublishToolkitDialog)
--is gone; sharing now happens per button through the SHARE YOUR
--BUTTONS dialog (RailShareButtonsDialog, defined after the community
--fetch pipeline it sits beside), reached from the library's COMMUNITY
--section. Under the hood each shared button is its own single-button
--pack -- the pack stays the backend unit of versioning, kill, and
--stats, exactly as before.

--Delete a toolkit: its strip, its definition, and its rail button.
--The layout entry is purged outright rather than RailMovePanel("remove"):
--with the definition already deleted, RailLayout files the entry under
--inert, where RailMovePanel cannot find it -- it early-returned without
--rebuilding, leaving a stale button on the rail until the next rebuild.
--And unlike "Remove from rail", deletion should not park an entry for a
--toolkit that no longer exists.
local function RailDeleteToolkit(id)
    HideToolkitStrip(id)
    local toolkits = RailToolkits()
    toolkits[id] = nil
    RailWriteToolkits(toolkits)

    local key = "toolkit:" .. id
    local sides, inert = RailLayout()
    for _, list in pairs(sides) do
        for i, e in ipairs(list) do
            if e.key == key then
                table.remove(list, i)
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
    SaveRailLayout(sides, inert)
    RebuildIconRails()
end

--Delete a standalone script button: its definition and its rail button.
--Same purge-the-layout-entry logic as RailDeleteToolkit, and for the
--same reason: with the definition gone RailLayout files the entry under
--inert, where RailMovePanel cannot find it, and a deleted button should
--not leave a parked entry behind.
local function RailDeleteScriptButton(id)
    local defs = dmhub.GetSettingValue("iconrailscriptbuttons") or {}
    defs[id] = nil
    dmhub.SetSettingValue("iconrailscriptbuttons", defs)

    local key = "button:" .. id
    local sides, inert = RailLayout()
    for _, list in pairs(sides) do
        for i, e in ipairs(list) do
            if e.key == key then
                table.remove(list, i)
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
    SaveRailLayout(sides, inert)
    RebuildIconRails()
end

--A pack's buttons as a clean 1..n list. Defensive about the shape the
--JSON round-trip hands back: a Firebase array normally returns as a
--list-style table, but numeric-string keys appear when the array was
--stored sparse; both normalize here.
local function ButtonPackButtonsList(pack)
    local buttons = pack.buttons
    if type(buttons) ~= "table" then
        return {}
    end
    if #buttons > 0 then
        return buttons
    end
    local keyed = {}
    for k, v in pairs(buttons) do
        local n = tonumber(k)
        if n ~= nil and type(v) == "table" then
            keyed[#keyed + 1] = { n = n, v = v }
        end
    end
    table.sort(keyed, function(a, b) return a.n < b.n end)
    local result = {}
    for _, e in ipairs(keyed) do
        result[#result + 1] = e.v
    end
    return result
end

--Theme rules shared by the Panel Library and the Community Browser, so
--the two surfaces render identically.
local function PanelLibraryStyles()
    return ThemeEngine.MergeStyles({
        {
            selectors = {"label", "libSection"},
            color = "@fgMuted",
            fontSize = 11,
            bold = true,
        },
        {
            selectors = {"libRule"},
            bgcolor = "@border",
        },
        --the replica face mirrors the rail's iconRailButton rules; the
        --hex is deliberate (it must match the rail's own scrim exactly).
        {
            selectors = {"libButtonFace"},
            bgcolor = "#000000cc",
            cornerRadius = 8,
            transitionTime = 0.15,
        },
        {
            selectors = {"libButtonFace", "parent:hover"},
            bgcolor = "#000000ee",
        },
        {
            selectors = {"libButtonFace", "create"},
            bgcolor = "#00000066",
            border = 1,
            borderColor = "@accent",
        },
        {
            selectors = {"libButtonIcon"},
            bgcolor = "@fg",
            transitionTime = 0.15,
        },
        {
            selectors = {"libButtonIcon", "parent:hover"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"label", "libButtonLabel"},
            color = "@fg",
            fontSize = 12,
            transitionTime = 0.15,
        },
        {
            selectors = {"label", "libButtonLabel", "parent:hover"},
            color = "@fgStrong",
        },
        {
            selectors = {"libRow"},
            bgcolor = "clear",
            cornerRadius = 6,
            transitionTime = 0.1,
        },
        --scheme-independent hover lift, matching the rail picker's own
        --translucent-white grammar.
        {
            selectors = {"libRow", "hover"},
            bgcolor = "#ffffff0d",
        },
        {
            selectors = {"libRowIcon"},
            bgcolor = "@fg",
        },
        {
            selectors = {"libRowIcon", "parent:hover"},
            bgcolor = "@fgStrong",
        },
        {
            selectors = {"label", "libRowLabel"},
            color = "@fg",
            fontSize = 13,
        },
        {
            selectors = {"label", "libRowLabel", "parent:hover"},
            color = "@fgStrong",
        },
        {
            selectors = {"libCommunityCard"},
            bgcolor = "@bg",
            border = 1,
            borderColor = "@border",
            cornerRadius = 8,
        },
        --community button cards: module-style card chrome around the
        --replica face -- name, description, author, downloads, hearts.
        {
            selectors = {"libPackCard"},
            bgcolor = "@bg",
            border = 1,
            borderColor = "@border",
            cornerRadius = 8,
            transitionTime = 0.1,
        },
        {
            selectors = {"libPackCard", "hover"},
            bgcolor = "#ffffff08",
            borderColor = "@accent",
        },
        --an added card is inert: no hover response, or the card would
        --promise a click it refuses to honor.
        {
            selectors = {"libPackCard", "added", "hover"},
            bgcolor = "@bg",
            borderColor = "@border",
        },
        {
            selectors = {"label", "libCardName"},
            color = "@fgStrong",
            fontSize = 13,
            bold = true,
        },
        {
            selectors = {"label", "libCardMeta"},
            color = "@fgMuted",
            fontSize = 11,
        },
        {
            selectors = {"libCardStatIcon"},
            bgcolor = "@fgMuted",
            transitionTime = 0.1,
        },
        {
            selectors = {"libCardStatIcon", "hover"},
            bgcolor = "@fgStrong",
        },
        --a hearted heart glows danger-red, the one deliberate splash of
        --color on the card.
        {
            selectors = {"libCardStatIcon", "hearted"},
            bgcolor = "@danger",
        },
        --the SHARE YOUR BUTTONS dialog's rows and their Share/Update
        --control (RailShareButtonsDialog). Defined here rather than on
        --the dialog's own subtree: a nested MergeStyles sheet REPLACES
        --the inherited one, which would strip the libButtonFace/Icon
        --and card rules from the rows.
        {
            selectors = {"libShareRow"},
            bgcolor = "@bg",
            border = 1,
            borderColor = "@border",
            cornerRadius = 8,
        },
        {
            selectors = {"libShareButton"},
            bgcolor = "clear",
            border = 1,
            borderColor = "@border",
            cornerRadius = 6,
            transitionTime = 0.1,
        },
        {
            selectors = {"libShareButton", "hover"},
            bgcolor = "#ffffff0d",
            borderColor = "@accent",
        },
        {
            selectors = {"label", "libShareButtonLabel"},
            color = "@fg",
            fontSize = 12,
            bold = true,
        },
        {
            selectors = {"label", "libShareButtonLabel", "parent:hover"},
            color = "@fgStrong",
        },
    })
end

--Distinct users behind a stats mark table ({uid = true, ...}).
local function CountStatMarks(t)
    local n = 0
    if type(t) == "table" then
        for k in pairs(t) do
            if k ~= "_luaTable" then
                n = n + 1
            end
        end
    end
    return n
end

--Does the user already have this community button? Standalone buttons
--(the modern add path) and legacy materialized pack toolkits both count.
local function CommunityButtonIsAdded(packid, buttonName)
    if buttonName == nil then
        return false
    end
    for _, def in pairs(dmhub.GetSettingValue("iconrailscriptbuttons") or {}) do
        if type(def) == "table" and def.pack == packid and def.name == buttonName then
            return true
        end
    end
    for _, rec in pairs(RailToolkits()) do
        if type(rec) == "table" and rec.pack == packid then
            for _, item in ipairs(rec.items or {}) do
                if item.name == buttonName then
                    return true
                end
            end
        end
    end
    return false
end

--SEAMLESS ADD, standalone edition (owner decision 2026-08-17: community
--adds land in YOUR BUTTONS): the button becomes a standalone rail
--button, pack-stamped so it runs insulated, kill-checked, and keeps its
--update semantics. Re-adding the same button refreshes its definition
--in place rather than duplicating.
local function CommunityAddButton(pack, button, side)
    local packid = pack.id
    local defs = dmhub.GetSettingValue("iconrailscriptbuttons") or {}
    local id = nil
    for existingId, def in pairs(defs) do
        if type(def) == "table" and def.pack == packid and def.name == button.name then
            id = existingId
        end
    end
    if id == nil then
        id = string.lower(dmhub.GenerateGuid())
    end
    defs[id] = {
        type = button.type or "script",
        name = button.name,
        icon = button.icon,
        script = button.script,
        panel = button.panel,
        description = button.description,
        pack = packid,
        packVersion = pack.version,
    }
    dmhub.SetSettingValue("iconrailscriptbuttons", defs)
    --per-user download mark for the pack's card counts (pcall: engine
    --builds without the stats API just skip the mark).
    pcall(function()
        buttonpack.RecordDownload{ packid = packid }
    end)
    RailAddPanel("button:" .. id, side)
    RebuildIconRails()
end

--One community button as a module-style card, shared by the library's
--COMMUNITY SPOTLIGHT and the Community Browser: replica face, name,
--description, author, the pack's download/heart counts, a toggleable
--heart, and the ADDED overlay for buttons the user already owns.
--opts: side (which rail an add lands on), onAdded (host callback after
--a successful add -- close the surface, typically).
local function CommunityButtonCard(pack, button, packStats, opts)
    opts = opts or {}
    local packid = pack.id
    if type(packStats) ~= "table" then
        packStats = {}
    end
    local downloads = CountStatMarks(packStats.downloads)
    local hearts = CountStatMarks(packStats.hearts)
    local myid = dmhub.loginUserid
    local hearted = type(packStats.hearts) == "table" and myid ~= nil and packStats.hearts[myid] ~= nil

    local description = button.description
    if description == nil or description == "" then
        description = pack.description or ""
    end
    local author = pack.authorName or "unknown"
    local isAdded = CommunityButtonIsAdded(packid, button.name)

    local heartIcon
    local heartCount
    heartCount = gui.Label{
        classes = {"libCardMeta"},
        text = tostring(hearts),
        width = "auto",
        height = "auto",
        valign = "center",
        lmargin = 4,
        interactable = false,
    }
    heartIcon = gui.Panel{
        classes = {"libCardStatIcon", cond(hearted, "hearted")},
        bgimage = cond(hearted, "phosphor/heart-fill.png", "phosphor/heart.png"),
        width = 14,
        height = 14,
        valign = "center",
        --its own click target: hearting must not add the button.
        swallowPress = true,
        click = function(element)
            hearted = not hearted
            hearts = hearts + cond(hearted, 1, -1)
            if hearts < 0 then
                hearts = 0
            end
            element:SetClass("hearted", hearted)
            element.bgimage = cond(hearted, "phosphor/heart-fill.png", "phosphor/heart.png")
            heartCount.text = tostring(hearts)
            pcall(function()
                buttonpack.SetHeart{ packid = packid, heart = hearted }
            end)
        end,
    }

    --the ADDED overlay: darkens the card and labels it, so it reads as
    --done rather than clickable. interactable = false so the heart
    --beneath still receives its clicks; the add-click gate is in the
    --card's own handler.
    local addedOverlay = nil
    if isAdded then
        addedOverlay = gui.Panel{
            floating = true,
            width = "100%",
            height = "100%",
            bgimage = true,
            bgcolor = "#000000a6",
            cornerRadius = 8,
            interactable = false,
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                interactable = false,
                gui.Panel{
                    classes = {"libCardStatIcon"},
                    bgimage = "phosphor/check-circle-fill.png",
                    width = 16,
                    height = 16,
                    valign = "center",
                    rmargin = 6,
                    interactable = false,
                },
                gui.Label{
                    classes = {"libCardName"},
                    text = "Added",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    interactable = false,
                },
            },
        }
    end

    return gui.Panel{
        classes = {"libPackCard", cond(isAdded, "added")},
        width = 410,
        height = 70,
        bgimage = true,
        borderBox = true,
        flow = "horizontal",
        margin = 4,
        click = function()
            if isAdded then
                return
            end
            CommunityAddButton(pack, button, opts.side or "left")
            if opts.onAdded ~= nil then
                opts.onAdded()
            end
        end,

        --the true rail-button face.
        gui.Panel{
            classes = {"libButtonFace"},
            width = 40,
            height = 40,
            bgimage = true,
            valign = "center",
            lmargin = 10,
            interactable = false,
            gui.Panel{
                classes = {"libButtonIcon"},
                bgimage = button.icon or "phosphor/lightning.png",
                width = 20,
                height = 20,
                halign = "center",
                valign = "center",
                interactable = false,
            },
        },

        --name, description, author.
        gui.Panel{
            flow = "vertical",
            width = "100%-140",
            height = "auto",
            valign = "center",
            lmargin = 10,
            interactable = false,
            gui.Label{
                classes = {"libCardName"},
                text = button.name or "Button",
                width = "100%",
                height = "auto",
                halign = "left",
                textAlignment = "left",
                textWrap = false,
                interactable = false,
            },
            gui.Label{
                classes = {"libCardMeta"},
                text = description,
                width = "100%",
                height = "auto",
                halign = "left",
                textAlignment = "left",
                textWrap = false,
                tmargin = 2,
                interactable = false,
            },
            gui.Label{
                classes = {"libCardMeta"},
                text = "by " .. author,
                width = "100%",
                height = "auto",
                halign = "left",
                textAlignment = "left",
                textWrap = false,
                tmargin = 2,
                interactable = false,
            },
        },

        --stats: downloads (informational) and the heart toggle.
        gui.Panel{
            flow = "vertical",
            width = 60,
            height = "auto",
            valign = "center",
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "left",
                gui.Panel{
                    classes = {"libCardStatIcon"},
                    bgimage = "phosphor/download-simple.png",
                    width = 14,
                    height = 14,
                    valign = "center",
                    interactable = false,
                },
                gui.Label{
                    classes = {"libCardMeta"},
                    text = tostring(downloads),
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    lmargin = 4,
                    interactable = false,
                },
            },
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "left",
                tmargin = 6,
                heartIcon,
                heartCount,
            },
        },

        --nil when not added; last so it draws over the whole card.
        addedOverlay,
    }
end

--Fetch everything the community surfaces need -- kill switch, index,
--stats, and every live pack -- then cb(packs, stats). Packs arrive
--sorted by heart count (then downloads, then name), so the SPOTLIGHT
--is simply the front of the list. cb(nil) on failure or when the
--engine has no buttonpack bridge.
local function CommunityFetchRemote(cb)
    if rawget(_G, "buttonpack") == nil then
        cb(nil)
        return
    end
    RefreshButtonPackKilled()
    buttonpack.QueryIndex{
        success = function(index)
            if mod.unloaded then
                return
            end
            local packids = {}
            for packid, entry in pairs(index) do
                if type(entry) == "table" and string.sub(tostring(packid), 1, 1) ~= "_" then
                    --killed packs are not offered.
                    if g_buttonPackKilled == nil or g_buttonPackKilled[packid] == nil then
                        packids[#packids + 1] = packid
                    end
                end
            end

            local packs = {}
            local stats = {}
            local ncomplete = 0
            local npending = #packids + 1
            local function OneComplete()
                ncomplete = ncomplete + 1
                if ncomplete < npending then
                    return
                end
                if mod.unloaded then
                    return
                end
                table.sort(packs, function(a, b)
                    local sa = stats[a.id] or {}
                    local sb = stats[b.id] or {}
                    if type(sa) ~= "table" then sa = {} end
                    if type(sb) ~= "table" then sb = {} end
                    local ha = CountStatMarks(sa.hearts)
                    local hb = CountStatMarks(sb.hearts)
                    if ha ~= hb then
                        return ha > hb
                    end
                    local da = CountStatMarks(sa.downloads)
                    local db = CountStatMarks(sb.downloads)
                    if da ~= db then
                        return da > db
                    end
                    return (a.name or "") < (b.name or "")
                end)
                cb(packs, stats)
            end

            --stats API may not exist on older engine builds; count it
            --complete immediately then.
            local statsDispatched = pcall(function()
                buttonpack.QueryStats{
                    success = function(result)
                        stats = result or {}
                        OneComplete()
                    end,
                    failure = function(err)
                        OneComplete()
                    end,
                }
            end)
            if not statsDispatched then
                OneComplete()
            end

            for _, packid in ipairs(packids) do
                buttonpack.Download{
                    packid = packid,
                    success = function(pack)
                        packs[#packs + 1] = pack
                        OneComplete()
                    end,
                    failure = function(err)
                        --a pack that fails to download is simply not
                        --offered.
                        OneComplete()
                    end,
                }
            end
        end,
        failure = function(err)
            if mod.unloaded then
                return
            end
            cb(nil)
        end,
    }
end

--Session cache over CommunityFetchRemote. The first fetch of the session
--is live; afterwards surfaces render instantly from the cache (no loading
--flash, no reflow when the network answers) while a fresh fetch runs
--behind. The callback fires a SECOND time only when the fresh result
--actually differs from what was rendered, so an unchanged catalog never
--replaces -- and never reflows -- the panels it drew.
local g_communityCache = nil

local function CommunitySignature(packs, stats)
    local parts = {}
    for _, pack in ipairs(packs) do
        local s = stats[pack.id]
        if type(s) ~= "table" then
            s = {}
        end
        parts[#parts + 1] = string.format("%s:%s:%d:%d:%d",
            tostring(pack.id), tostring(pack.mtime or 0),
            #ButtonPackButtonsList(pack),
            CountStatMarks(s.hearts), CountStatMarks(s.downloads))
    end
    return table.concat(parts, "|")
end

local function CommunityFetch(cb)
    if g_communityCache == nil then
        CommunityFetchRemote(function(packs, stats)
            if packs ~= nil then
                g_communityCache = { packs = packs, stats = stats, sig = CommunitySignature(packs, stats) }
            end
            cb(packs, stats)
        end)
        return
    end

    cb(g_communityCache.packs, g_communityCache.stats)
    CommunityFetchRemote(function(packs, stats)
        --a failed refresh keeps the cached render: failure is not worth
        --replacing content the user is already looking at.
        if packs == nil then
            return
        end
        local sig = CommunitySignature(packs, stats)
        local changed = sig ~= g_communityCache.sig
        g_communityCache = { packs = packs, stats = stats, sig = sig }
        if changed then
            cb(packs, stats)
        end
    end)
end

--The COMMUNITY BROWSER: the full catalog of community buttons in its
--own window -- search, sort, every card -- opened from the library's
--spotlight (owner decision 2026-08-17: the library shows a SPOTLIGHT;
--the browser is where you go to see everything).
local g_communityBrowser = nil
--opts.onBack, when given, puts a back arrow in the header that closes
--the browser and returns to the surface that opened it (the library).
local function RailShowCommunityBrowser(side, opts)
    opts = opts or {}
    if g_communityBrowser ~= nil and g_communityBrowser.valid then
        g_communityBrowser:SetAsLastSibling()
        return
    end
    local layer = DocumentsLayer()
    if layer == nil then
        return
    end

    local m_packs = nil
    local m_stats = nil
    local m_search = ""
    local m_sort = "hearts"

    local window
    local cardsPanel

    local function CloseBrowser()
        if window ~= nil and window.valid then
            window:DestroySelf()
        end
        g_communityBrowser = nil
    end

    local function RenderCards()
        if cardsPanel == nil or not cardsPanel.valid then
            return
        end
        if m_packs == nil then
            cardsPanel.children = {
                gui.Label{
                    classes = {"libSection"},
                    text = "Could not load community buttons.",
                    width = "100%",
                    height = "auto",
                    tmargin = 8,
                },
            }
            return
        end

        local flattened = {}
        for _, pack in ipairs(m_packs) do
            for _, button in ipairs(ButtonPackButtonsList(pack)) do
                if type(button) == "table" then
                    flattened[#flattened + 1] = { pack = pack, button = button }
                end
            end
        end

        if m_search ~= "" then
            local filter = string.lower(m_search)
            local filtered = {}
            for _, e in ipairs(flattened) do
                local hay = string.lower(table.concat({
                    e.button.name or "",
                    e.button.description or "",
                    e.pack.name or "",
                    e.pack.description or "",
                    e.pack.authorName or "",
                }, " "))
                if string.find(hay, filter, 1, true) then
                    filtered[#filtered + 1] = e
                end
            end
            flattened = filtered
        end

        --packs arrive hearts-sorted from CommunityFetch; the other sorts
        --reorder here.
        if m_sort == "downloads" then
            table.sort(flattened, function(a, b)
                local sa = (m_stats or {})[a.pack.id]
                local sb = (m_stats or {})[b.pack.id]
                if type(sa) ~= "table" then sa = {} end
                if type(sb) ~= "table" then sb = {} end
                local da = CountStatMarks(sa.downloads)
                local db = CountStatMarks(sb.downloads)
                if da ~= db then
                    return da > db
                end
                return (a.button.name or "") < (b.button.name or "")
            end)
        elseif m_sort == "newest" then
            table.sort(flattened, function(a, b)
                local ma = a.pack.mtime or 0
                local mb = b.pack.mtime or 0
                if ma ~= mb then
                    return ma > mb
                end
                return (a.button.name or "") < (b.button.name or "")
            end)
        end

        local cards = {}
        for _, e in ipairs(flattened) do
            cards[#cards + 1] = CommunityButtonCard(e.pack, e.button, (m_stats or {})[e.pack.id], {
                side = side,
                onAdded = CloseBrowser,
            })
        end
        if #cards == 0 then
            cardsPanel.children = {
                gui.Label{
                    classes = {"libSection"},
                    text = cond(m_search ~= "", "No buttons match your search.", "No community buttons published yet."),
                    width = "100%",
                    height = "auto",
                    tmargin = 8,
                },
            }
            return
        end
        cardsPanel.children = {
            gui.Panel{
                flow = "horizontal",
                wrap = true,
                width = "100%",
                height = "auto",
                valign = "top",
                children = cards,
            },
        }
    end

    cardsPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100%-56",
        vscroll = true,
        gui.Label{
            classes = {"libSection"},
            text = "Loading community buttons...",
            width = "100%",
            height = "auto",
            tmargin = 8,
        },
    }

    window = gui.Panel{
        classes = {"framedPanel", "toplevel"},
        styles = PanelLibraryStyles(),
        floating = true,
        halign = "center",
        valign = "center",
        width = 900,
        height = 700,
        pad = 28,
        borderBox = true,
        flow = "vertical",
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function()
            CloseBrowser()
        end,
        destroy = function(element)
            if g_communityBrowser == element then
                g_communityBrowser = nil
            end
        end,

        --header: back (when opened from the library), title, search,
        --sort, close.
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 40,
            opts.onBack ~= nil and gui.Panel{
                bgimage = "phosphor/arrow-left-bold.png",
                width = 18,
                height = 18,
                halign = "left",
                valign = "center",
                rmargin = 12,
                bgcolor = "#ffffff88",
                styles = {
                    {
                        selectors = {"hover"},
                        bgcolor = "#ffffff",
                        transitionTime = 0.1,
                    },
                },
                click = function()
                    CloseBrowser()
                    opts.onBack()
                end,
            } or nil,
            gui.Label{
                classes = {"modalTitle"},
                text = "Community Buttons",
                width = "auto",
                height = "auto",
                valign = "center",
                halign = "left",
            },
            gui.SearchInput{
                placeholderText = "Search buttons...",
                width = 220,
                height = 28,
                halign = "right",
                valign = "center",
                hmargin = 12,
                hasFocus = true,
                editlag = 0.15,
                edit = function(searchElement)
                    m_search = searchElement.text or ""
                    RenderCards()
                end,
                change = function(searchElement)
                    searchElement:FireEvent("edit")
                end,
            },
            gui.Dropdown{
                options = {
                    { id = "hearts", text = "Most hearted" },
                    { id = "downloads", text = "Most downloaded" },
                    { id = "newest", text = "Newest" },
                },
                idChosen = "hearts",
                width = 160,
                height = 26,
                halign = "right",
                valign = "center",
                rmargin = 32,
                change = function(dropdownElement)
                    m_sort = dropdownElement.idChosen or "hearts"
                    RenderCards()
                end,
            },
            gui.Panel{
                bgimage = "phosphor/x-bold.png",
                width = 16,
                height = 16,
                halign = "right",
                valign = "center",
                bgcolor = "#ffffff88",
                styles = {
                    {
                        selectors = {"hover"},
                        bgcolor = "#ffffff",
                        transitionTime = 0.1,
                    },
                },
                click = function()
                    CloseBrowser()
                end,
            },
        },

        cardsPanel,
    }

    layer:AddChild(window)
    g_communityBrowser = window

    CommunityFetch(function(packs, stats)
        if window == nil or not window.valid then
            return
        end
        m_packs = packs
        m_stats = stats
        RenderCards()
    end)
end

--Every button the user can share: their own standalone rail buttons
--plus the script buttons inside their toolkits. Buttons that CAME from
--the community (def.pack set) and legacy materialized pack toolkits
--are excluded -- you share your own work, not someone else's.
local function ShareableButtons()
    local entries = {}
    for id, def in pairs(dmhub.GetSettingValue("iconrailscriptbuttons") or {}) do
        if type(def) == "table" and def.type == "script" and def.pack == nil then
            entries[#entries + 1] = { kind = "standalone", id = id, item = def, source = "On the rail" }
        end
    end
    for tid, rec in pairs(RailToolkits()) do
        if type(rec) == "table" and rec.pack == nil then
            for idx, item in ipairs(rec.items or {}) do
                if type(item) == "table" and item.type == "script" and item.pack == nil then
                    entries[#entries + 1] = { kind = "toolkit", toolkitid = tid, idx = idx, item = item, source = rec.name or "Toolkit" }
                end
            end
        end
    end
    table.sort(entries, function(a, b)
        local na = string.lower(a.item.name or "")
        local nb = string.lower(b.item.name or "")
        if na ~= nb then
            return na < nb
        end
        return a.source < b.source
    end)
    return entries
end

--The SHARE YOUR BUTTONS dialog: the discoverable path to the publish
--flow (PANEL_LIBRARY_BRIEF.md -- endorsed 2026-08-17, built
--2026-08-18). Sharing is BUTTON-first: each of the user's own script
--buttons publishes as its own single-button pack via the buttonpack
--bridge (the pack stays the backend unit of versioning, kill, and
--stats), so the community only ever sees buttons. The minted packid is
--remembered on the button's definition, so Share becomes Update and
--republishing refreshes the same pack instead of minting a duplicate.
--opts.onBack, when given, puts a back arrow in the header that returns
--to the surface that opened it (the library).
local g_shareButtonsDialog = nil
local function RailShareButtonsDialog(opts)
    opts = opts or {}
    if g_shareButtonsDialog ~= nil and g_shareButtonsDialog.valid then
        g_shareButtonsDialog:SetAsLastSibling()
        return
    end
    if rawget(_G, "buttonpack") == nil then
        gui.ModalMessage{
            title = "Not available",
            message = "This build does not support sharing buttons yet.",
        }
        return
    end
    local layer = DocumentsLayer()
    if layer == nil then
        return
    end

    local window
    local rowsPanel
    local statusLabel
    local RenderRows

    local function CloseDialog()
        if window ~= nil and window.valid then
            window:DestroySelf()
        end
        g_shareButtonsDialog = nil
    end

    --write the minted packid back onto the LIVE definition, so the next
    --share of this button updates the same pack.
    local function RememberPackid(entry, packid)
        if entry.kind == "standalone" then
            local defs = dmhub.GetSettingValue("iconrailscriptbuttons") or {}
            local def = defs[entry.id]
            if type(def) == "table" then
                def.packid = packid
                dmhub.SetSettingValue("iconrailscriptbuttons", defs)
            end
        else
            local toolkits = RailToolkits()
            local rec = toolkits[entry.toolkitid]
            local item = nil
            if type(rec) == "table" then
                item = (rec.items or {})[entry.idx]
            end
            if type(item) == "table" then
                item.packid = packid
                RailWriteToolkits(toolkits)
            end
        end
    end

    --publish one button as its own single-button pack. Re-reads the
    --LIVE definition at click time -- the dialog's snapshot may be
    --stale (an edit or delete can land while it is open).
    local function ShareEntry(entry)
        local item = nil
        if entry.kind == "standalone" then
            item = (dmhub.GetSettingValue("iconrailscriptbuttons") or {})[entry.id]
        else
            local rec = RailToolkits()[entry.toolkitid]
            if type(rec) == "table" then
                item = (rec.items or {})[entry.idx]
            end
        end
        if type(item) ~= "table" then
            --the button vanished under us; re-render to match reality.
            RenderRows()
            return
        end
        local buttonName = item.name or "Button"
        local firstShare = (item.packid == nil)
        buttonpack.Publish{
            pack = {
                id = item.packid,
                name = buttonName,
                description = item.description or "",
                icon = item.icon,
                buttons = {
                    {
                        type = item.type,
                        name = item.name,
                        icon = item.icon,
                        script = item.script,
                        panel = item.panel,
                        description = item.description,
                    },
                },
            },
            success = function(packid)
                if mod.unloaded then
                    return
                end
                RememberPackid(entry, packid)
                if statusLabel ~= nil and statusLabel.valid then
                    if firstShare then
                        statusLabel.text = string.format("%s is now shared with the community.", buttonName)
                    else
                        statusLabel.text = string.format("%s has been updated.", buttonName)
                    end
                end
                RenderRows()
            end,
            failure = function(err)
                if mod.unloaded then
                    return
                end
                gui.ModalMessage{
                    title = "Could not share",
                    message = tostring(err),
                }
            end,
        }
    end

    --one shareable button as a card row: replica face, name,
    --description, where it lives, and the Share / Update control.
    local function ShareRow(entry)
        local item = entry.item
        local shared = (item.packid ~= nil)
        local description = item.description
        if description == nil or description == "" then
            description = "No description -- edit the button to add one."
        end
        local sharedMark = nil
        if shared then
            sharedMark = gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "right",
                valign = "center",
                rmargin = 10,
                interactable = false,
                gui.Panel{
                    classes = {"libCardStatIcon"},
                    bgimage = "phosphor/check-circle-fill.png",
                    width = 14,
                    height = 14,
                    valign = "center",
                    rmargin = 4,
                    interactable = false,
                },
                gui.Label{
                    classes = {"libCardMeta"},
                    text = "Shared",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    interactable = false,
                },
            }
        end
        return gui.Panel{
            classes = {"libShareRow"},
            width = "100%",
            height = 64,
            bgimage = true,
            borderBox = true,
            flow = "horizontal",
            vmargin = 4,

            --the true rail-button face, same grammar as the community
            --cards.
            gui.Panel{
                classes = {"libButtonFace"},
                width = 40,
                height = 40,
                bgimage = true,
                valign = "center",
                lmargin = 10,
                interactable = false,
                gui.Panel{
                    classes = {"libButtonIcon"},
                    bgimage = item.icon or "phosphor/lightning.png",
                    width = 20,
                    height = 20,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            },

            gui.Panel{
                flow = "vertical",
                width = "100%-230",
                height = "auto",
                valign = "center",
                lmargin = 10,
                interactable = false,
                gui.Label{
                    classes = {"libCardName"},
                    text = item.name or "Button",
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    textAlignment = "left",
                    textWrap = false,
                    interactable = false,
                },
                gui.Label{
                    classes = {"libCardMeta"},
                    text = description,
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    textAlignment = "left",
                    textWrap = false,
                    tmargin = 2,
                    interactable = false,
                },
                gui.Label{
                    classes = {"libCardMeta"},
                    text = entry.source,
                    width = "100%",
                    height = "auto",
                    halign = "left",
                    textAlignment = "left",
                    textWrap = false,
                    tmargin = 2,
                    interactable = false,
                },
            },

            sharedMark,

            gui.Panel{
                classes = {"libShareButton"},
                width = 90,
                height = 30,
                bgimage = true,
                borderBox = true,
                halign = "right",
                valign = "center",
                rmargin = 12,
                click = function()
                    ShareEntry(entry)
                end,
                gui.Label{
                    classes = {"libShareButtonLabel"},
                    text = cond(shared, "Update", "Share"),
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            },
        }
    end

    rowsPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "100%-110",
        vscroll = true,
    }

    RenderRows = function()
        if rowsPanel == nil or not rowsPanel.valid then
            return
        end
        local rows = {}
        for _, entry in ipairs(ShareableButtons()) do
            rows[#rows + 1] = ShareRow(entry)
        end
        if #rows == 0 then
            rows = {
                gui.Label{
                    classes = {"libSection"},
                    text = "No buttons to share yet. Create one from the Panel Library's New button tile.",
                    width = "100%",
                    height = "auto",
                    tmargin = 8,
                },
            }
        end
        --a single auto-height child inside the fixed-height scroll
        --panel, so the rows stack instead of distributing over it (the
        --community browser's cardsPanel does the same).
        rowsPanel.children = {
            gui.Panel{
                flow = "vertical",
                width = "100%",
                height = "auto",
                valign = "top",
                children = rows,
            },
        }
    end

    statusLabel = gui.Label{
        classes = {"libCardMeta"},
        text = "",
        width = "100%",
        height = 16,
        halign = "left",
        tmargin = 6,
    }

    window = gui.Panel{
        classes = {"framedPanel", "toplevel"},
        styles = PanelLibraryStyles(),
        floating = true,
        halign = "center",
        valign = "center",
        width = 560,
        height = 620,
        pad = 28,
        borderBox = true,
        flow = "vertical",
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function()
            CloseDialog()
        end,
        destroy = function(element)
            if g_shareButtonsDialog == element then
                g_shareButtonsDialog = nil
            end
        end,

        --header: back (when opened from the library), title, close.
        gui.Panel{
            flow = "horizontal",
            width = "100%",
            height = 40,
            opts.onBack ~= nil and gui.Panel{
                bgimage = "phosphor/arrow-left-bold.png",
                width = 18,
                height = 18,
                halign = "left",
                valign = "center",
                rmargin = 12,
                bgcolor = "#ffffff88",
                styles = {
                    {
                        selectors = {"hover"},
                        bgcolor = "#ffffff",
                        transitionTime = 0.1,
                    },
                },
                click = function()
                    CloseDialog()
                    opts.onBack()
                end,
            } or nil,
            gui.Label{
                classes = {"modalTitle"},
                text = "Share Your Buttons",
                width = "auto",
                height = "auto",
                valign = "center",
                halign = "left",
            },
            gui.Panel{
                bgimage = "phosphor/x-bold.png",
                width = 16,
                height = 16,
                halign = "right",
                valign = "center",
                bgcolor = "#ffffff88",
                styles = {
                    {
                        selectors = {"hover"},
                        bgcolor = "#ffffff",
                        transitionTime = 0.1,
                    },
                },
                click = function()
                    CloseDialog()
                end,
            },
        },
        gui.Label{
            classes = {"libCardMeta"},
            text = "Sharing publishes a button for every Codex player to add from Community Buttons. Update pushes your latest edits to a button you have already shared.",
            width = "100%",
            height = "auto",
            bmargin = 8,
        },
        rowsPanel,
        statusLabel,
    }

    layer:AddChild(window)
    g_shareButtonsDialog = window
    RenderRows()
end

--The + button's target: the PANEL LIBRARY (see PANEL_LIBRARY_BRIEF.md).
--A large floating themed window rather than the old anchored menu: rail
--adds are rare configuration acts, so the surface optimizes for
--discovery -- recommended buttons, a searchable list of every panel,
--the user's toolkits with creation, and (phased later) community
--content. The Recommended and toolkit sections render faithful
--rail-button REPLICAS -- the exact 40px face, glyph size, and tints --
--so what you click is literally what lands on the rail.
--
--Still summoned through element.popup: the popup layer supplies
--click-outside dismissal and captureEscape supplies esc, which together
--are the library's dismiss grammar. A single add auto-closes.
--
--("Community buttons" is the deliberate absence now: a custom action
--button needs a decision about what an action IS before it can be
--offered. The toolkit item schema already carries an explicit `type`
--for it, and the COMMUNITY section below is its reserved landing spot.)
RailShowAddPicker = function(element, side)
    --"already got it" is BOTH senses: a panel with its own rail button,
    --and a panel filed inside somebody's folder. A folder member has no
    --button by design -- its owner's window hosts it as a tab -- so it
    --never appears in the rail layout, and a naive layout-only filter
    --offers you panels you already have. It then "adds" them to no
    --visible effect, because the member still has no button of its own.
    local onRail = {}
    for _, l in pairs(RailLayout()) do
        for _, e in ipairs(l) do
            onRail[e.key] = true
        end
    end
    for memberKey in pairs(PanelDocument.GroupOwners()) do
        onRail[memberKey] = true
    end

    --RECOMMENDED is the curated rail order filtered to what is not
    --already on a rail; ALL PANELS is every available panel (curated
    --ones included -- the library's list is complete, so search always
    --finds a panel by name), alphabetical.
    local recommended, all = {}, {}
    for _, name in ipairs(g_iconRailPanels) do
        local key = string.lower(name)
        if not onRail[key] and PanelDocument.Get(name) ~= nil then
            recommended[#recommended + 1] = name
        end
    end
    local items = DockablePanel.GetMenuItems(true)
    table.sort(items, function(a, b) return (a.text or "") < (b.text or "") end)
    for _, item in ipairs(items) do
        local name = item.text
        if name ~= nil then
            local key = string.lower(name)
            if not onRail[key] and PanelDocument.Get(name) ~= nil then
                all[#all + 1] = name
            end
        end
    end

    --the user's toolkits that are not currently on a rail: clicking one
    --puts its button back. On-rail toolkits are omitted (this is an
    --"add" surface, same rule as the panel lists).
    local toolkits = {}
    for id, tk in pairs(RailToolkits()) do
        if type(tk) == "table" and not onRail["toolkit:" .. id] then
            toolkits[#toolkits + 1] = { id = id, name = tk.name or "Toolkit", icon = tk.icon or "phosphor/toolbox.png" }
        end
    end
    table.sort(toolkits, function(a, b) return a.name < b.name end)

    --likewise the user's standalone script buttons parked off the rail:
    --without this they would have no way back on.
    local standaloneButtons = {}
    for id, def in pairs(dmhub.GetSettingValue("iconrailscriptbuttons") or {}) do
        if type(def) == "table" and not onRail["button:" .. id] then
            standaloneButtons[#standaloneButtons + 1] = { id = id, name = def.name or "Button", icon = def.icon or "phosphor/lightning.png" }
        end
    end
    table.sort(standaloneButtons, function(a, b) return a.name < b.name end)

    local function CloseLibrary()
        if element ~= nil and element.valid then
            element.popup = nil
            element:SetClass("open", false)
        end
    end

    --a faithful rail-button replica (the rail's 40px #000000cc rounded
    --face, 20px @fg glyph) with its name beneath: an honest preview of
    --exactly what lands on the rail.
    local function ButtonReplica(icon, text, opts)
        opts = opts or {}
        return gui.Panel{
            flow = "vertical",
            width = 72,
            height = "auto",
            hmargin = 5,
            bgimage = true,
            click = opts.click,
            linger = cond(opts.tooltip ~= nil, gui.Tooltip(opts.tooltip or "")),
            gui.Panel{
                classes = {"libButtonFace", cond(opts.create, "create")},
                width = 40,
                height = 40,
                bgimage = true,
                halign = "center",
                gui.Panel{
                    classes = {"libButtonIcon"},
                    bgimage = icon,
                    width = 20,
                    height = 20,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                },
            },
            gui.Label{
                classes = {"libButtonLabel"},
                text = text,
                width = "100%",
                height = "auto",
                textAlignment = "center",
                halign = "center",
                tmargin = 6,
                textWrap = false,
                interactable = false,
            },
        }
    end

    local function SectionHeader(text)
        return gui.Panel{
            flow = "vertical",
            width = "100%",
            height = "auto",
            tmargin = 20,
            bmargin = 10,
            gui.Label{
                classes = {"libSection"},
                text = text,
                width = "auto",
                height = "auto",
                halign = "left",
            },
            gui.Panel{
                classes = {"libRule"},
                bgimage = true,
                width = "100%",
                height = 1,
                tmargin = 5,
            },
        }
    end

    --ALL PANELS rows, collected so the search box can filter them.
    local searchRows = {}
    local function PanelRow(name)
        local reg = DockablePanel.GetRegistration(string.lower(name))
        local row = gui.Panel{
            classes = {"libRow"},
            width = 420,
            height = 32,
            bgimage = true,
            flow = "horizontal",
            data = { searchText = string.lower(name) },
            click = function()
                RailAddPanel(name, side)
                CloseLibrary()
            end,
            gui.Panel{
                classes = {"libRowIcon"},
                bgimage = (reg ~= nil and reg.icon) or "icons/icon_app/icon_app_107.png",
                width = 18,
                height = 18,
                valign = "center",
                lmargin = 10,
                rmargin = 10,
                interactable = false,
            },
            gui.Label{
                classes = {"libRowLabel"},
                text = name,
                --fills the rest of the row: a horizontal flow centres its
                --children as a group, so the label eating the remaining
                --width is what pins each icon+label pair to the left.
                width = "100%-38",
                height = "auto",
                halign = "left",
                textAlignment = "left",
                valign = "center",
                textWrap = false,
                interactable = false,
            },
        }
        searchRows[#searchRows + 1] = row
        return row
    end

    local recTiles = {}
    for _, name in ipairs(recommended) do
        local reg = DockablePanel.GetRegistration(string.lower(name))
        recTiles[#recTiles + 1] = ButtonReplica(
            (reg ~= nil and reg.icon) or "icons/icon_app/icon_app_107.png", name,
            { click = function()
                RailAddPanel(name, side)
                CloseLibrary()
            end })
    end

    local allRows = {}
    for _, name in ipairs(all) do
        allRows[#allRows + 1] = PanelRow(name)
    end
    if #allRows == 0 then
        allRows[1] = gui.Label{
            classes = {"libSection"},
            text = "Every panel is already on a rail.",
            width = "100%",
            height = "auto",
            tmargin = 8,
        }
    end

    --each user section leads with its own create tile: tool panels are
    --one kind of thing, buttons another (owner decision 2026-08-17 --
    --"new button can't be under tool panels").
    local tkTiles = {
        ButtonReplica("phosphor/plus-bold.png", "New tool panel", {
            create = true,
            click = function()
                CloseLibrary()
                RailCreateToolkit(side)
            end,
        }),
    }
    for _, tk in ipairs(toolkits) do
        tkTiles[#tkTiles + 1] = ButtonReplica(tk.icon, tk.name, {
            click = function()
                RailAddPanel("toolkit:" .. tk.id, side)
                CloseLibrary()
            end,
        })
    end

    local buttonTiles = {
        ButtonReplica("phosphor/lightning.png", "New button", {
            create = true,
            click = function()
                CloseLibrary()
                RailScriptButtonDialog(nil, nil)
            end,
        }),
    }
    for _, b in ipairs(standaloneButtons) do
        buttonTiles[#buttonTiles + 1] = ButtonReplica(b.icon, b.name, {
            click = function()
                RailAddPanel("button:" .. b.id, side)
                CloseLibrary()
            end,
        })
    end

    local libraryStyles = PanelLibraryStyles()

    --The popup root is an AUTO-sized wrapper that only positions; the
    --sized, styled panel is its child (the working pattern is the
    --journal's -- see the popup at the top of this file).
    --constrainToScreen keeps the window on screen regardless of where
    --the + sits in the column. The library carries its own explicit
    --theme root (NOT popupsInheritStyles): it is a self-contained themed
    --window, not part of the rail's scrim.
    element.popupsInheritStyles = false
    --centered on SCREEN, not on the +: popups position relative to their
    --owner by default, which with halign center parks the window at the
    --left edge. Anchoring to the full-screen documents layer makes
    --center mean the middle of the screen -- the library is a
    --destination surface, not a flyout of the + button.
    if GameHud.instance ~= nil and GameHud.instance.documentsPanel ~= nil then
        element.popupPositioning = GameHud.instance.documentsPanel
    end
    element.popup = gui.Panel{
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        constrainToScreen = true,
        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(pickerElement)
            CloseLibrary()
        end,
        styles = libraryStyles,

        gui.Panel{
            classes = {"framedPanel", "toplevel"},
            width = 900,
            --FIXED height, matching the community browser exactly: the two
            --windows read as the same surface, so navigating between them
            --must not change the frame (owner decision 2026-08-17). The
            --ALL PANELS scroll region absorbs the slack via "available".
            height = 700,
            flow = "vertical",
            pad = 28,
            borderBox = true,
            bgimage = true,

            --header: title, live search, close.
            gui.Panel{
                flow = "horizontal",
                width = "100%",
                height = 40,
                gui.Label{
                    classes = {"modalTitle"},
                    text = "Panel Library",
                    width = "auto",
                    height = "auto",
                    valign = "center",
                    halign = "left",
                },
                gui.SearchInput{
                    placeholderText = "Search panels...",
                    width = 260,
                    height = 28,
                    halign = "right",
                    valign = "center",
                    hmargin = 44,
                    hasFocus = true,
                    editlag = 0.15,
                    edit = function(searchElement)
                        local filter = string.lower(searchElement.text or "")
                        for _, row in ipairs(searchRows) do
                            row:SetClass("collapsed", #filter > 0 and not string.find(row.data.searchText, filter, 1, true))
                        end
                    end,
                    change = function(searchElement)
                        searchElement:FireEvent("edit")
                    end,
                },
                gui.Panel{
                    bgimage = "phosphor/x-bold.png",
                    width = 16,
                    height = 16,
                    halign = "right",
                    valign = "center",
                    bgcolor = "#ffffff88",
                    styles = {
                        {
                            selectors = {"hover"},
                            bgcolor = "#ffffff",
                            transitionTime = 0.1,
                        },
                    },
                    click = function()
                        CloseLibrary()
                    end,
                },
            },

            --the recommended section COLLAPSES entirely when empty (an
            --always-present-but-empty recommendation row trains people
            --to ignore it).
            gui.Panel{
                classes = {cond(#recTiles == 0, "collapsed")},
                flow = "vertical",
                width = "100%",
                height = "auto",
                SectionHeader("RECOMMENDED"),
                gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    children = recTiles,
                },
            },

            SectionHeader("ALL PANELS"),
            gui.Panel{
                width = "100%",
                --fills whatever the fixed window leaves over, so variable
                --sections below (spotlight rows, recommendations) squeeze
                --this list instead of growing the window. No minHeight: a
                --min clamp counts toward occupancy before the engine hands
                --out the leftover, so any leftover smaller than the min
                --becomes a dead gap at the window bottom instead of growth.
                height = "100% available",
                vscroll = true,
                gui.Panel{
                    flow = "horizontal",
                    wrap = true,
                    width = "100%",
                    height = "auto",
                    valign = "top",
                    children = allRows,
                },
            },

            SectionHeader("YOUR TOOL PANELS"),
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "left",
                children = tkTiles,
            },

            SectionHeader("YOUR BUTTONS"),
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "left",
                children = buttonTiles,
            },

            SectionHeader("COMMUNITY SPOTLIGHT"),
            --no scroll region: the spotlight is bounded at four cards by
            --design, so the section just takes the height it needs.
            --minHeight reserves the loaded one-row footprint (card row 78
            --incl margins + browse row 32 + its tmargin 4 + share row 32
            --+ its tmargin 4) while the "Loading..." label is up, so the
            --async fill does not reflow the library. (minHeight is safe
            --on this auto child; it is only the "available" sibling it
            --must never be put on.)
            gui.Panel{
                flow = "vertical",
                width = "100%",
                height = "auto",
                minHeight = 150,
                create = function(communityElement)
                    --older engine builds have no buttonpack bridge:
                    --keep the reserved-section card.
                    if rawget(_G, "buttonpack") == nil then
                        communityElement.children = {
                            gui.Label{
                                classes = {"libSection"},
                                text = "Buttons made by other players -- coming soon.",
                                fontSize = 13,
                                width = "100%",
                                height = "auto",
                                tmargin = 4,
                            },
                        }
                        return
                    end

                    communityElement.children = {
                        gui.Label{
                            classes = {"libSection"},
                            text = "Loading community buttons...",
                            width = "100%",
                            height = "auto",
                            tmargin = 4,
                        },
                    }

                    --the SPOTLIGHT: the four most-hearted community
                    --buttons (CommunityFetch pre-sorts by hearts), plus
                    --the door to the full browser.
                    CommunityFetch(function(packs, stats)
                        if mod.unloaded or communityElement == nil or not communityElement.valid then
                            return
                        end

                        --the discoverable path to the publish flow
                        --(endorsed 2026-08-17, built 2026-08-18): share
                        --your own buttons with the community. Present
                        --even when the index fetch failed -- sharing
                        --does not depend on browsing.
                        local shareRow = gui.Panel{
                            classes = {"libRow"},
                            width = "100%",
                            height = 32,
                            bgimage = true,
                            flow = "horizontal",
                            tmargin = 4,
                            click = function()
                                CloseLibrary()
                                RailShareButtonsDialog{
                                    --back returns to the library, same
                                    --contract as the browser row below.
                                    onBack = function()
                                        if element ~= nil and element.valid then
                                            RailShowAddPicker(element, side)
                                            element:SetClass("open", true)
                                        end
                                    end,
                                }
                            end,
                            gui.Panel{
                                classes = {"libRowIcon"},
                                bgimage = "phosphor/share-network.png",
                                width = 18,
                                height = 18,
                                valign = "center",
                                lmargin = 10,
                                rmargin = 10,
                                interactable = false,
                            },
                            gui.Label{
                                classes = {"libRowLabel"},
                                text = "Share your buttons...",
                                width = "100%-38",
                                height = "auto",
                                halign = "left",
                                valign = "center",
                                textAlignment = "left",
                                textWrap = false,
                                interactable = false,
                            },
                        }

                        if packs == nil then
                            communityElement.children = {
                                gui.Label{
                                    classes = {"libSection"},
                                    text = "Could not load community buttons.",
                                    width = "100%",
                                    height = "auto",
                                    tmargin = 4,
                                },
                                shareRow,
                            }
                            return
                        end

                        local cards = {}
                        for _, pack in ipairs(packs) do
                            for _, button in ipairs(ButtonPackButtonsList(pack)) do
                                if type(button) == "table" and #cards < 4 then
                                    cards[#cards + 1] = CommunityButtonCard(pack, button, stats[pack.id], {
                                        side = side,
                                        onAdded = CloseLibrary,
                                    })
                                end
                            end
                        end

                        local children = {}
                        if #cards > 0 then
                            children[#children + 1] = gui.Panel{
                                flow = "horizontal",
                                wrap = true,
                                width = "100%",
                                height = "auto",
                                valign = "top",
                                children = cards,
                            }
                        else
                            children[#children + 1] = gui.Label{
                                classes = {"libSection"},
                                text = "No community buttons published yet. Be the first -- share yours below!",
                                width = "100%",
                                height = "auto",
                                tmargin = 4,
                            }
                        end
                        --the door to everything else.
                        children[#children + 1] = gui.Panel{
                            classes = {"libRow"},
                            width = "100%",
                            height = 32,
                            bgimage = true,
                            flow = "horizontal",
                            tmargin = 4,
                            click = function()
                                CloseLibrary()
                                RailShowCommunityBrowser(side, {
                                    --back returns to the library: reopen
                                    --the picker popup on the same + button,
                                    --held open exactly as its own click
                                    --handler does.
                                    onBack = function()
                                        if element ~= nil and element.valid then
                                            RailShowAddPicker(element, side)
                                            element:SetClass("open", true)
                                        end
                                    end,
                                })
                            end,
                            gui.Panel{
                                classes = {"libRowIcon"},
                                bgimage = "phosphor/users-three.png",
                                width = 18,
                                height = 18,
                                valign = "center",
                                lmargin = 10,
                                rmargin = 10,
                                interactable = false,
                            },
                            gui.Label{
                                classes = {"libRowLabel"},
                                text = "Browse all community buttons...",
                                width = "100%-38",
                                height = "auto",
                                halign = "left",
                                valign = "center",
                                textAlignment = "left",
                                textWrap = false,
                                interactable = false,
                            },
                        }
                        children[#children + 1] = shareRow
                        communityElement.children = children
                    end)
                end,
            },
        },
    }
end

--The rail's + button. Hidden at rest; the rail root reveals it after a
--short dwell (see the root's hover handlers) so a pointer merely crossing
--the rail on its way elsewhere does not flash it.
--
--`shown` is a real class rather than a bare parent:hover style rule
--because it does two jobs: it fades the glyph in, and it gates the click.
--The + holds its layout slot while invisible (that is what keeps the rail
--from reshuffling as it appears), so without the gate an invisible button
--would sit there swallowing clicks in the empty column below the rail.
local function CreateRailAddButton(side)
    --Reachable when the + is up OR when the pointer is simply on the rail.
    --The `shown` class alone was too strict: it only turns on after the
    --reveal dwell, so a click arriving in the same input event as the
    --pointer -- before the engine has processed hover on this button --
    --was thrown away. Asking the rail whether the pointer is anywhere in
    --the column answers the real question ("is the user working the rail
    --right now?") without depending on the order two events are delivered.
    local function Reachable(element)
        if element:HasClass("shown") then
            return true
        end
        local rail = element:FindParentWithClass("iconRail")
        return rail ~= nil and rail.valid and (rail.data.railInside or 0) > 0
    end

    local button
    button = gui.Panel{
        classes = {"iconRailButton", "iconRailAddButton"},
        bgimage = true,
        --NO blurBackground, unlike every other rail button. A blurred
        --backdrop paints whether or not the panel is transparent, so with
        --it the + stayed visible as a ghostly pane at opacity 0 -- an
        --always-visible control, which is the design we rejected. Losing
        --the blur costs this one button a little depth; keeping it cost
        --the entire hover-reveal.
        width = ICON_RAIL_BUTTON,
        height = ICON_RAIL_BUTTON,
        flow = "none",
        halign = "center",
        tmargin = ICON_RAIL_GAP,
        swallowPress = true,
        data = {},

        --The + reports its OWN proximity like every other rail child.
        --Without this, stepping off the last panel button and onto the +
        --decremented the count to zero with nothing to put it back, so
        --the button vanished the instant the pointer arrived on it: the
        --reveal region has to include the thing being revealed, or you
        --can never reach it.
        hover = function(element)
            RailNotifyProximity(element, true)
        end,
        dehover = function(element)
            RailNotifyProximity(element, false)
        end,

        press = function(element)
            if not Reachable(element) then
                return
            end
            RailButtonSound("press")
        end,

        click = function(element)
            --invisible and untouched means not there: a click in the empty
            --column below the rail must not open anything.
            if not Reachable(element) then
                return
            end
            --Already open? Then the x the user is looking at is what they
            --clicked, so close. Reading the popup rather than tracking a
            --flag keeps this honest if the list was dismissed some other
            --way in between.
            local menuOpen = false
            pcall(function() menuOpen = element.popup ~= nil end)
            if menuOpen then
                element.popup = nil
                element:SetClass("open", false)
                return
            end
            RailShowAddPicker(element, side)
            --Held open (and held DARK) for as long as its menu is up. The
            --pointer's next move is into the picker, which is off the
            --rail, so the proximity count drops to zero and the ordinary
            --fade-out would pull the button out from under its own open
            --list. hideRailAdd defers to the popup instead.
            element:SetClass("open", true)
        end,

        --Carries iconRailAddIcon as well as the shared icon class: a
        --parent's opacity does NOT reach its children here (measured --
        --the button's own fill vanished at opacity 0 while this glyph
        --kept painting), so the glyph has to be hidden by its own rule
        --keyed on the parent's shown state.
        gui.Panel{
            classes = {"iconRailIcon", "iconRailAddIcon"},
            bgimage = "phosphor/plus-bold.png",
            width = 18,
            height = 18,
            halign = "center",
            valign = "center",
            interactable = false,
        },

        --The close hint, exactly as the rail's own buttons carry it: an x
        --that takes over the glyph while you hover a button whose thing is
        --already open. Here "already open" is the picker rather than a
        --panel window, so it keys on `open` instead of `active`. Offering
        --the x and then not closing on click would be a lie, so the click
        --handler toggles.
        gui.Panel{
            classes = {"iconRailCloseHint", "iconRailAddCloseHint"},
            floating = true,
            bgimage = "phosphor/x-bold.png",
            width = 16,
            height = 16,
            halign = "center",
            valign = "center",
            interactable = false,
        },

        gui.Label{
            classes = {"iconRailLabel"},
            floating = true,
            renderOnTop = true,
            x = cond(side == "left", ICON_RAIL_BUTTON + 10, -(ICON_RAIL_BUTTON + 10)),
            halign = cond(side == "left", "left", "right"),
            valign = "center",
            interactable = false,
            --no bgimage: see the main hover label's note.
            text = "ADD TO RAIL",
            width = "auto",
            height = "auto",
            hpad = 8,
            vpad = 4,
            borderBox = true,
            textWrap = false,
        },
    }
    return button
end

local function CreateIconRail(side, entries)
    local buttons = {}

    --halign is EXPLICIT on both sides. Without it the label defaults to
    --centred on its x anchor and grows in BOTH directions, so a long title
    --spills back across the button it belongs to; anchoring the near edge
    --makes it grow away from the rail whatever its length.
    local nearSideLabel
    if side == "left" then
        nearSideLabel = { halign = "left", x = ICON_RAIL_BUTTON + 10 }
    else
        nearSideLabel = { halign = "right", x = -(ICON_RAIL_BUTTON + 10) }
    end

    --Rearrange mode grows a STOP button: a red X -- the one deliberately
    --coloured control on the monochrome rail, so "exit this mode" cannot
    --be read as another wiggling icon. It FLOATS above the column rather
    --than sitting in the flow: slot 0 is the top of the rail now that
    --nothing else lives up there, and a button in the flow would push
    --every icon down and invalidate the slot geometry (RailDropPoint).
    --Escape exits the mode too: escapeActivates fires the click handler.
    if g_railRearranging then
        buttons[#buttons + 1] = gui.Panel{
            classes = {"iconRailButton", "iconRailStopButton"},
            bgimage = true,
            blurBackground = true,
            floating = true,
            y = -(ICON_RAIL_BUTTON + 12),
            width = ICON_RAIL_BUTTON,
            height = ICON_RAIL_BUTTON,
            flow = "none",
            halign = "center",
            valign = "top",
            swallowPress = true,
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            data = {},

            gui.Panel{
                classes = {"iconRailStopIcon"},
                bgimage = "phosphor/x-bold.png",
                width = 20,
                height = 20,
                halign = "center",
                valign = "center",
            },

            gui.Label{
                classes = {"iconRailLabel"},
                floating = true,
                renderOnTop = true,
                x = nearSideLabel.x,
                halign = nearSideLabel.halign,
                valign = "center",
                interactable = false,
                --no bgimage: see the main hover label's note.
                text = "STOP REARRANGING",
                width = "auto",
                height = "auto",
                hpad = 8,
                vpad = 4,
                borderBox = true,
                textWrap = false,
            },

            hover = function(element)
                RailButtonSound("hover")
            end,
            dehover = function(element)
                RailButtonSound("dehover")
            end,
            press = function(element)
                RailButtonSound("press")
            end,

            click = function(element)
                RailSetRearranging(false)
            end,
        }
    end

    local prevBottom = nil
    for i, entry in ipairs(entries) do
        local panelName = entry.name
        local key = entry.key
        local docid = entry.docid
        local charid = entry.charid
        local toolkitid = entry.toolkitid
        local sbuttonid = entry.sbuttonid

        --panel buttons draw their registration icon; document shortcuts
        --draw the doc's semantic-type icon; character shortcuts draw the
        --character's portrait (untinted, cropped square); toolkits draw
        --the toolbox; standalone script buttons draw their chosen icon.
        local reg = nil
        local buttonIcon = "icons/icon_app/icon_app_107.png"
        local buttonIconTint = nil
        local buttonIconRect = nil
        local sbuttonStyle = nil
        if toolkitid ~= nil then
            --the user's chosen icon, falling back to the toolbox for
            --toolkits made before icons existed (and for anyone who left
            --the picker alone).
            buttonIcon = "phosphor/toolbox.png"
            local tk = (dmhub.GetSettingValue("iconrailtoolkits") or {})[toolkitid]
            if tk ~= nil and tk.icon ~= nil and tk.icon ~= "" then
                buttonIcon = tk.icon
            end
        elseif sbuttonid ~= nil then
            buttonIcon = "phosphor/lightning.png"
            local def = (dmhub.GetSettingValue("iconrailscriptbuttons") or {})[sbuttonid]
            if type(def) == "table" and def.icon ~= nil and def.icon ~= "" then
                buttonIcon = def.icon
            end
            --the author's @bgcolor/@opacity directives (span was already
            --resolved in RailLayout; the face styling applies below).
            sbuttonStyle = ScriptButtonStyle(def)
        elseif charid ~= nil then
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
        --previous button's bottom edge (or the area start). A multi-slot
        --card is taller than one button (it swallows the gaps inside its
        --span), so the chain tracks the previous entry's actual bottom
        --edge rather than assuming button-sized entries.
        local index = entry.slot
        local pitch = ICON_RAIL_BUTTON + ICON_RAIL_GAP
        local span = entry.span or 1
        local buttonHeight = span * pitch - ICON_RAIL_GAP
        local buttonTop = index * pitch
        local buttonMargin
        if prevBottom == nil then
            buttonMargin = buttonTop
        else
            buttonMargin = buttonTop - prevBottom
        end
        prevBottom = buttonTop + buttonHeight

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

        --GROUP: the panels sharing this button's window as tabs. They have
        --no rail button of their own (RailLayout parks them), so this
        --button represents the whole group: a badge in the corner, and a
        --flyout of their buttons on hover.
        local groupMembers = PanelDocument.GroupMembers(key)
        --whether this button's panel can host a group at all (document,
        --character and toolkit shortcuts cannot be folder members or
        --owners, either way round).
        local groupCapable = docid == nil and charid == nil and toolkitid == nil
        --forward-declared: ToggleGroupMember below closes the strip, and
        --a local declared after it would not be in that closure's scope.
        local groupFlyout
        --A press on the owner opens its window into exactly the band the
        --strip occupies, leaving the strip overlapping the thing it just
        --opened. So a press HIDES the strip, and this flag keeps it hidden
        --while the pointer sits on the button (hover has already fired, so
        --nothing would re-open it anyway -- but the flag also makes the
        --next press the "show it again" gesture). Cleared on dehover, so a
        --fresh hover always opens the strip.
        local groupFlyoutSuppressed = false
        --the "second card" group marker behind the button. It fades out
        --(the "groupOpen" class) while the strip is expanded OR the
        --group's window is open, and fades back when both are done. One
        --class covers both reasons -- see the style rule for why two
        --classes crossfading in the same frame flickered. Forward-
        --declared for the same reason as groupFlyout.
        local groupShadow
        local groupStripExpanded = false
        local function GroupShadowHidden()
            if groupStripExpanded or g_railRearranging or PanelDocument.IsPanelShown(key) then
                return true
            end
            --a member's open window counts too: member windows anchor in
            --the same band beside this button, so the marker popping back
            --next to one reads as the same glitch the owner case did.
            for _, m in ipairs(groupMembers or {}) do
                if PanelDocument.IsPanelShown(m) then
                    return true
                end
            end
            return false
        end
        local function UpdateGroupShadow()
            if groupShadow == nil or not groupShadow.valid then
                return
            end
            if GroupShadowHidden() then
                groupShadow:SetClass("groupOpen", true)
            else
                --clears are deferred a frame and re-checked: a press that
                --opens the group's window collapses the strip (clear) and
                --refreshes the rails (set) in the same call stack, and the
                --engine restarts a re-added class's transition ramp from
                --zero (SetClassActive resets activeTime), which flashed
                --the card fully visible for the 0.1s fade. Deferring means
                --a clear immediately followed by a set never lands at all.
                dmhub.Schedule(0.02, function()
                    if mod.unloaded then
                        return
                    end
                    if groupShadow ~= nil and groupShadow.valid and not GroupShadowHidden() then
                        groupShadow:SetClass("groupOpen", false)
                    end
                end)
            end
        end
        local function SetGroupExpanded(expanded)
            groupStripExpanded = expanded
            UpdateGroupShadow()
        end
        --the owner's own button, captured on create so the members can
        --schedule the close on it.
        local ownerButton
        --Fold the strip away, from any route: the deferred close, a press,
        --a member opening its tab, or another button taking over the rail.
        --Every route goes through here so the strip, the marker card and
        --the g_railOpenFlyout registration can never disagree.
        local function CollapseGroupFlyout()
            if groupFlyout ~= nil and groupFlyout.valid then
                groupFlyout:SetClass("collapsed", true)
            end
            SetGroupExpanded(false)
            RailForgetOpenFlyout(ownerButton)
        end
        --Every panel that counts as "the pointer is still in the group
        --UI". The engine sets the "hover" class ONLY on the panel directly
        --under the pointer -- ancestors do not get it (parent:hover
        --selectors are resolved by walking up at style time instead). So
        --hovering a member button left both the owner and the strip
        --reading un-hovered, and the flyout closed the moment you reached
        --for it. Every hoverable piece has to be listed here.
        local groupHoverPanels = {}
        local function GroupHovered()
            for _, p in ipairs(groupHoverPanels) do
                if p ~= nil and p.valid then
                    if p:HasClass("hover") then
                        return true
                    end
                    --a member's context menu counts as "still in the group
                    --UI": the pointer is on the popup, not the strip, and
                    --the strip closing would orphan the menu's anchor.
                    local hasPopup = false
                    pcall(function() hasPopup = p.popup ~= nil end)
                    if hasPopup then
                        return true
                    end
                end
            end
            return false
        end

        --Activate a folder member from the hover strip. The folder is ONE
        --window with a tab per member, so a member the window is not
        --currently showing is a tab switch -- only pressing the member
        --already on screen closes the window (and a pinned window just
        --raises). The window anchors beside the folder's button -- the
        --member has no button of its own to anchor to.
        local function ToggleGroupMember(memberKey)
            memberKey = string.lower(memberKey)
            local verb, ownerKey, doc, d = RailActivation(memberKey)
            if doc == nil then
                return
            end

            if verb == "switch" or verb == "raise" then
                d:SetAsLastSibling()
                d:FireEventTree("focusPanelTab", memberKey)
                --the strip stays up: the pointer is still on it, likely
                --headed for a sibling.
                RefreshRails()
                return
            end

            if verb == "close" then
                RailForgetWindow(ownerKey)
                doc:ClosePanel()
                RefreshRails()
                return
            end

            --the same one-transient-window rule the icon's own click
            --follows.
            if g_railTransientKey ~= nil and g_railTransientKey ~= ownerKey then
                local prev = RailPanelDocument(g_railTransientKey)
                if prev ~= nil and not PanelDocument.IsPinned(g_railTransientKey) then
                    prev:ClosePanel()
                end
            end
            g_railTransientKey = ownerKey
            local anchorX, anchorY = RailAnchor(side, index)
            OpenIconRailWindow(memberKey, { x = anchorX, y = anchorY, anchor = true, autoFocus = true })
            --the strip has done its job, and the window it just opened
            --lands on top of it.
            CollapseGroupFlyout()
            RefreshRails()
        end

        --The hover label doubles as the hotkey reminder: append the
        --keystroke bound to this panel's "togglepanel" command (the same
        --command the settings screen's User Interface section binds).
        --Panels only -- document and character shortcuts have no
        --togglepanel command. Recomputed from refreshRail because a
        --binding can change in the settings screen (or via this button's
        --own Set Keybind... entry) without the rails rebuilding.
        --(Defined up here, before the flyout strip: the strip's name slot
        --shows this text while the owner is hovered.)
        local function HoverLabelText()
            if docid == nil and charid == nil and toolkitid == nil then
                local bind = dmhub.GetCommandBinding(string.format("togglepanel %s", key))
                if bind ~= nil and bind ~= "" then
                    return string.format("%s  (%s)", string.upper(panelName), bind)
                end
            end
            return string.upper(panelName)
        end

        --The flyout itself: the members' own buttons in a strip beside the
        --owner, opening toward the screen centre like the hover labels do.
        --Hidden with "collapsed" rather than opacity: an opacity-0 panel
        --still renders AND still hit-tests, which would leave an invisible
        --strip swallowing clicks over the map.
        --Built even when there is no group (empty and collapsed): a nil in
        --the button's children array would truncate it and drop the label
        --after it.
        --The strip is an opaque rounded CARD (see its construction): loose
        --translucent buttons floating over an open rail window read as an
        --accidental overlap. Its last slot is the NAME of whatever the
        --pointer is on -- the owner, or the hovered member -- so the group
        --case needs no floating labels at all.
        local stripLabel = nil
        --the card FILL is a separate backdrop layer sized to the CURRENT
        --name, not to the name slot: the slot is fixed-width (longest
        --name in the group) so the strip never repositions, but painting
        --that full width left a slab of empty card after a short name
        --(field report 2026-08-12). The backdrop hugs the text; the
        --slot's invisible tail still hit-tests, keeping the strip's
        --geometry constant. Defined in the strip's construction block;
        --forward-declared so the member hover handlers can call it.
        local stripCardBackdrop = nil
        local UpdateStripCard = nil
        local memberLabelTexts = {}
        local memberButtons = {}
        if groupMembers ~= nil then
            for mi, memberKey in ipairs(groupMembers) do
                local memberReg = DockablePanel.GetRegistration(memberKey)
                local memberName = (memberReg ~= nil and memberReg.name) or memberKey
                local memberIcon = "icons/icon_app/icon_app_107.png"
                if memberReg ~= nil and memberReg.icon ~= nil then
                    memberIcon = memberReg.icon
                end
                local memberLabel = string.upper(memberName)
                local memberBind = dmhub.GetCommandBinding(string.format("togglepanel %s", memberKey))
                if memberBind ~= nil and memberBind ~= "" then
                    memberLabel = string.format("%s  (%s)", memberLabel, memberBind)
                end
                memberLabelTexts[#memberLabelTexts + 1] = memberLabel

                --in rearrange mode members wiggle like the rail's own
                --buttons, seeded by strip position so neighbours start
                --desynced.
                local memberClasses = {"iconRailButton", "iconRailGroupMember"}
                --lit for the member the folder's window is SHOWING. Every
                --member lives in that window as a tab, so lighting all of
                --them (IsPanelShown) would light the whole strip the
                --moment the folder opened.
                if PanelDocument.IsPanelActive(memberKey) then
                    memberClasses[#memberClasses + 1] = "active"
                end
                if g_railRearranging then
                    memberClasses[#memberClasses + 1] = "rearranging"
                    if mi % 2 == 1 then
                        memberClasses[#memberClasses + 1] = "wigglePhase"
                    end
                    if mi % 4 >= 2 then
                        memberClasses[#memberClasses + 1] = "pulsePhase"
                    end
                end

                local memberButton
                memberButton = gui.Panel{
                    classes = memberClasses,
                    bgimage = true,
                    blurBackground = true,
                    width = ICON_RAIL_BUTTON,
                    height = ICON_RAIL_BUTTON,
                    flow = "none",
                    --no leading margin on the FIRST member: the strip card
                    --starts exactly at its edge (see flyoutArgs), so the
                    --card's border-to-button alignment is pixel-perfect.
                    lmargin = cond(mi == 1, 0, 4),
                    rmargin = 4,
                    swallowPress = true,
                    draggable = g_railRearranging,
                    data = { ownerKey = key, memberKey = memberKey, memberIndex = mi },

                    hover = function(element)
                        RailButtonSound("hover")
                        --the strip's name slot follows the pointer, and
                        --the card backdrop resizes to the new name.
                        if stripLabel ~= nil and stripLabel.valid then
                            stripLabel.text = memberLabel
                        end
                        if UpdateStripCard ~= nil then
                            UpdateStripCard(memberLabel)
                        end
                    end,

                    --leaving a member re-arms the close; the handler
                    --re-checks the whole group, so moving to a sibling
                    --member or back to the owner keeps the strip open.
                    dehover = function(element)
                        RailButtonSound("dehover")
                        if g_railRearranging then
                            return
                        end
                        if ownerButton ~= nil and ownerButton.valid then
                            ownerButton:ScheduleEvent("closeGroupFlyout", RAIL_FLYOUT_CLOSE_GRACE)
                        end
                    end,

                    create = function(element)
                        if g_railRearranging then
                            element:ScheduleEvent("wiggle", 0.12 + (mi % 3) * 0.04)
                            element:ScheduleEvent("wigglePulse", 0.17 + (mi % 4) * 0.05)
                        end
                    end,
                    wiggle = function(element)
                        if mod.unloaded or not g_railRearranging or not element.valid then
                            return
                        end
                        element:SetClass("wigglePhase", not element:HasClass("wigglePhase"))
                        element:ScheduleEvent("wiggle", 0.12)
                    end,
                    wigglePulse = function(element)
                        if mod.unloaded or not g_railRearranging or not element.valid then
                            return
                        end
                        element:SetClass("pulsePhase", not element:HasClass("pulsePhase"))
                        element:ScheduleEvent("wigglePulse", 0.17)
                    end,

                    --Rearrange-mode drags. A member's drop verbs, chosen
                    --by POINTER position (see RailGroupZoneAt):
                    --  trash                      -> out of the group AND off the rail
                    --  a divider boundary         -> slot in at that position
                    --                               (own strip = reorder)
                    --  a cut-out (any button's)   -> append to that window's group
                    --  rail column / empty space  -> out of the group, into that slot
                    --Making it the group's OWNER is menu-only ("Make
                    --group owner").
                    canDragOnto = function(element, target)
                        return target:HasClass("iconRailTrash")
                    end,
                    dragging = function(element, target)
                        if target ~= nil and target.valid and target:HasClass("iconRailTrash") then
                            HideRailGhost()
                            RailSetZoneHover(nil)
                            return
                        end
                        local px, py = RailMemberDragPointer(side, index, mi, #groupMembers, element)
                        local zone = RailGroupZoneAt(px, py, memberKey)
                        if zone ~= nil then
                            HideRailGhost()
                            RailSetZoneHover(zone.panel)
                            return
                        end
                        RailSetZoneHover(nil)
                        local targetSide, targetSlot = RailDropPoint(px, py, nil)
                        ShowRailGhost(targetSide, targetSlot, nil)
                    end,
                    drag = function(element, target)
                        g_railDragTime = dmhub.Time()
                        HideRailGhost()
                        RailSetZoneHover(nil)

                        if target ~= nil and target.valid and target:HasClass("iconRailTrash") then
                            RailUngroup(memberKey, key)
                            RailMovePanel(string.lower(memberKey), "remove")
                            return
                        end

                        local px, py = RailMemberDragPointer(side, index, mi, #groupMembers, element)
                        local zone = RailGroupZoneAt(px, py, memberKey)
                        if zone ~= nil then
                            --own strip = reorder; another strip = adopt.
                            RailGroupInsert(memberKey, zone.ownerKey, zone.beforeKey)
                            return
                        end

                        local targetSide, targetSlot = RailDropPoint(px, py, nil)
                        RailUngroup(memberKey, key)
                        RailPlaceKeyAt(string.lower(memberKey), targetSide, targetSlot)
                    end,

                    gui.Panel{
                        classes = {"iconRailIcon"},
                        bgimage = memberIcon,
                        width = 20,
                        height = 20,
                        halign = "center",
                        valign = "center",
                        interactable = false,
                    },

                    --the same close hint the rail's own buttons carry:
                    --hovering a member whose panel is open means a click
                    --will close it (the active+hover style rules reveal
                    --it and recede the icon).
                    gui.Panel{
                        classes = {"iconRailCloseHint"},
                        floating = true,
                        bgimage = "phosphor/x-bold.png",
                        width = 16,
                        height = 16,
                        halign = "center",
                        valign = "center",
                        interactable = false,
                    },

                    --keeps the lit state honest as the folder's window
                    --opens, closes and switches tabs by any path.
                    refreshRail = function(element)
                        element:SetClass("active", PanelDocument.IsPanelActive(memberKey))
                    end,

                    --(the member's name shows in the strip card's own name
                    --slot -- see stripLabel -- rather than as a floating
                    --label of its own.)

                    --A strip member is still "the pointer is on the rail"
                    --as far as the + is concerned. Without this, reaching
                    --into a folder's flyout dropped the proximity count to
                    --zero -- the owner button had been left, and nothing
                    --in the strip reported taking over -- so the + faded
                    --out and back in every time you moved along a folder's
                    --members. The engine only marks the panel directly
                    --under the pointer (see groupHoverPanels' note), so
                    --every hoverable piece has to say so itself.
                    hover = function(element)
                        RailNotifyProximity(element, true)
                    end,
                    dehover = function(element)
                        RailNotifyProximity(element, false)
                    end,

                    --the click sound still goes on PRESS: it acknowledges
                    --the mouse going down, which is when the gesture reads
                    --as committed even though the open waits for the click.
                    press = function(element)
                        RailButtonSound("press")
                    end,

                    --click, NOT press like the rail's own buttons: the
                    --member's window opens beside the rail, i.e. exactly
                    --where this strip is, so on press the mouse-up landed
                    --on the window chrome that had just appeared under
                    --the cursor. On click the selection is already
                    --complete.
                    click = function(element)
                        --in rearrange mode member presses begin drags.
                        if g_railRearranging then
                            return
                        end
                        ToggleGroupMember(memberKey)
                    end,

                    --non-drag parity for the member gestures (the same
                    --A9a principle the rail buttons follow).
                    rightClick = function(element)
                        if g_railRearranging then
                            return
                        end
                        local entries = {
                            {
                                --Close only for the member on screen:
                                --pressing any other member switches the
                                --folder's window to its tab.
                                text = cond(PanelDocument.IsPanelActive(memberKey), "Close", "Open"),
                                click = function()
                                    element.popup = nil
                                    ToggleGroupMember(memberKey)
                                end,
                            },
                            {
                                text = "Make group owner",
                                click = function()
                                    element.popup = nil
                                    RailGroupInvert(memberKey, key)
                                end,
                            },
                        }
                        if mi > 1 then
                            entries[#entries + 1] = {
                                text = "Move left in group",
                                click = function()
                                    element.popup = nil
                                    RailGroupShiftMember(memberKey, key, -1)
                                end,
                            }
                        end
                        if mi < #groupMembers then
                            entries[#entries + 1] = {
                                text = "Move right in group",
                                click = function()
                                    element.popup = nil
                                    RailGroupShiftMember(memberKey, key, 1)
                                end,
                            }
                        end
                        entries[#entries + 1] = {
                            text = "Remove from group",
                            click = function()
                                element.popup = nil
                                RailUngroup(memberKey, key)
                            end,
                        }
                        element.popup = gui.ContextMenu{
                            entries = entries,
                        }
                    end,
                }
                memberButtons[#memberButtons + 1] = memberButton
                groupHoverPanels[#groupHoverPanels + 1] = memberButton
            end
        end

        do
            --the strip starts 4px off the owner (the old inter-button gap),
            --with its edge exactly on the first member button -- the card's
            --outline hugs the buttons instead of poking a bare sliver out
            --toward the owner. The 4px pointer gap to the owner is covered
            --by the same close-grace that covers the gaps between members.
            local flyoutArgs
            if side == "left" then
                flyoutArgs = { halign = "left", x = ICON_RAIL_BUTTON + 4 }
            else
                flyoutArgs = { halign = "right", x = -(ICON_RAIL_BUTTON + 4) }
            end

            --in rearrange mode every group EXPANDS: the strip constructs
            --open (and stays open -- the hover close logic stands down),
            --so members are visible, draggable, and drop targets. The
            --strip also grows the EXPLICIT grouping drop zones:
            --  * dashed DIVIDERS floating over the gaps between members
            --    ("slot in before this member") -- floating, so the
            --    member geometry RailMemberDragPointer derives stays true;
            --  * a dotted CUT-OUT box at the end ("add to this group") --
            --    in the flow AFTER the members, so it extends the strip
            --    without moving them. Ungrouped (group-capable) buttons
            --    get the cut-out alone: the visible "child space" the
            --    user drops a panel into to form a group.
            local flyoutClasses = {"iconRailGroupFlyout"}
            if g_railRearranging and groupCapable then
                --railStripPinned marks a strip built expanded, so the
                --rail's syncDockMode can re-assert the open state without
                --also popping open the EMPTY collapsed flyouts that
                --document/character buttons carry.
                flyoutClasses[#flyoutClasses + 1] = "railStripPinned"
            else
                flyoutClasses[#flyoutClasses + 1] = "collapsed"
            end
            if g_railRearranging and groupCapable then
                local memberPitch = ICON_RAIL_BUTTON + 8
                local memberCount = 0
                if groupMembers ~= nil then
                    memberCount = #groupMembers
                end
                --the zones are VISUALS ONLY (interactable false, not
                --dragTargets): which one a drag is over is decided by
                --pointer position (RailGroupZoneAt), and the highlight
                --is the "dropHover" class it manages. One divider per
                --boundary, INCLUDING before the first member.
                local dividerPanels = {}
                for di = 1, memberCount do
                    local dashes = {}
                    for _ = 1, 5 do
                        dashes[#dashes + 1] = gui.Panel{
                            classes = {"iconRailGroupDividerDash"},
                            bgimage = true,
                            width = 2,
                            height = 4,
                            halign = "center",
                            vmargin = 2,
                            interactable = false,
                        }
                    end
                    local divider = gui.Panel{
                        classes = {"iconRailGroupDivider"},
                        floating = true,
                        flow = "vertical",
                        bgimage = true,
                        width = 10,
                        height = ICON_RAIL_BUTTON,
                        halign = "left",
                        valign = "center",
                        --centred on the boundary before member di
                        --(strip-local coordinates).
                        x = (di - 1) * memberPitch - 5,
                        interactable = false,
                        children = dashes,
                    }
                    dividerPanels[di] = divider
                    memberButtons[#memberButtons + 1] = divider
                end

                local cutoutChildren = DottedOutlineChildren(ICON_RAIL_BUTTON)
                cutoutChildren[#cutoutChildren + 1] = gui.Panel{
                    classes = {"iconRailGroupCutoutPlus"},
                    bgimage = "phosphor/plus-bold.png",
                    width = 16,
                    height = 16,
                    halign = "center",
                    valign = "center",
                    interactable = false,
                }
                --The cut-out is the one zone that is also a BUTTON: the
                --dividers are pure drag affordances, but "add a panel to
                --this row" has an obvious non-drag form, so clicking the
                --"+" drops a menu of the panels that could fill the
                --space. It is still not a dragTarget -- drops are
                --resolved by RailGroupZoneAt's pointer math, and the
                --dragged buttons' canDragOnto approves only the trash --
                --so making it interactable changes nothing about drags.
                local cutoutPanel
                cutoutPanel = gui.Panel{
                    classes = {"iconRailGroupCutout"},
                    bgimage = true,
                    flow = "none",
                    width = ICON_RAIL_BUTTON,
                    height = ICON_RAIL_BUTTON,
                    hmargin = 4,
                    swallowPress = true,
                    children = cutoutChildren,

                    hover = function(element)
                        RailButtonSound("hover")
                    end,
                    dehover = function(element)
                        RailButtonSound("dehover")
                    end,

                    --click, not press: the menu is a popup and press
                    --would open it under a pointer that has not lifted
                    --yet. A click landing right after a drop is the
                    --release of that drag, not a new gesture.
                    click = function(element)
                        if g_railDragTime ~= nil and dmhub.Time() - g_railDragTime < 0.3 then
                            return
                        end
                        RailButtonSound("press")
                        element.popup = gui.ContextMenu{
                            entries = RailGroupAddEntries(element, key),
                        }
                    end,
                }
                memberButtons[#memberButtons + 1] = cutoutPanel

                g_railStripZones[#g_railStripZones + 1] = {
                    side = side,
                    ownerKey = key,
                    ownerSlot = index,
                    memberCount = memberCount,
                    members = groupMembers or {},
                    dividers = dividerPanels,
                    cutout = cutoutPanel,
                }
            end

            --the card's name slot: the owner's name while the owner is
            --hovered, a member's while the pointer is on that member.
            --FIXED width, sized for the longest name in the group: the
            --flyout is width-auto, so a name slot that resized with its
            --text shifted the whole open strip sideways whenever the
            --pointer moved between owner and members. ~8px per character
            --of the 12px small-caps font, with a little slack -- a
            --slightly roomy slot beats a moving strip.
            local nameSlotChars = #HoverLabelText()
            for _, t in ipairs(memberLabelTexts) do
                if #t > nameSlotChars then
                    nameSlotChars = #t
                end
            end
            stripLabel = gui.Label{
                classes = {"iconRailStripLabel"},
                text = HoverLabelText(),
                interactable = false,
                width = nameSlotChars * 8 + 12,
                height = "auto",
                valign = "center",
                textAlignment = "left",
                hmargin = 6,
                textWrap = false,
            }
            memberButtons[#memberButtons + 1] = stripLabel

            --the card fill (see the forward declaration): drawn UNDER the
            --member buttons (first sibling), anchored to the strip's left
            --edge on both rails -- the name slot is the last flow child
            --on both, so the unused slot tail is always on the right.
            --Fill and radius live on selfStyle, not a class rule: cascade
            --bgcolor swaps verifiably fail to repaint these panels.
            stripCardBackdrop = gui.Panel{
                classes = {"iconRailStripCardBackdrop", "collapsed"},
                floating = true,
                interactable = false,
                bgimage = true,
                bgcolor = "#0a0a0b",
                cornerRadius = 8,
                halign = "left",
                valign = "top",
                height = ICON_RAIL_BUTTON,
                width = 10,
            }
            table.insert(memberButtons, 1, stripCardBackdrop)

            --size the backdrop to the members plus the CURRENT name (8px
            --per character, same estimate the slot uses, plus breathing
            --room). shown=nil leaves visibility as it is (member hovers
            --only rename; the owner's hover decides card-vs-chromeless).
            UpdateStripCard = function(text, shown)
                if stripCardBackdrop == nil or not stripCardBackdrop.valid then
                    return
                end
                if shown ~= nil then
                    stripCardBackdrop:SetClass("collapsed", not shown)
                end
                local memberCount = 0
                if groupMembers ~= nil then
                    memberCount = #groupMembers
                end
                --members span 48px per slot minus the first one's missing
                --lead-in margin; rearrange mode adds the 48px cut-out box.
                local span = memberCount * 48 - 4
                if g_railRearranging and groupCapable then
                    span = span + 48
                end
                stripCardBackdrop.selfStyle.width = span + 6 + #tostring(text or "") * 8 + 12
            end

            groupFlyout = gui.Panel{
                classes = flyoutClasses,
                floating = true,
                --NO renderOnTop here, unlike the hover labels: it puts the
                --panel on the top-most sorting canvas, which the raycaster
                --does not reach -- the strip drew but could not be clicked.
                --Rail windows are what would otherwise cover it, so the
                --owner's hover raises the whole rail instead.
                flow = "horizontal",
                width = "auto",
                height = ICON_RAIL_BUTTON,
                --a SIBLING of the button parked at its slot's row (the
                --shadow-card pattern), NOT a child: the button wiggles
                --with rotate+scale in rearrange mode, and a child strip
                --inherits that transform and swings around the button's
                --pivot like a lever -- a long row of members visibly
                --jumped back and forth. The rail root is exactly one
                --button wide, so the same halign/x anchor the strip
                --flush against the button.
                halign = flyoutArgs.halign,
                valign = "top",
                x = flyoutArgs.x,
                y = buttonTop,
                --a barely-there hit surface at rest (the iconRailGroupFlyout
                --rule); when the strip would overlap an open window, the
                --owner's hover handler swaps in an opaque rounded card via
                --selfStyle (see the RailWindowIntersectsBand check there).
                --NOTE the strip's total width must stay CONSTANT while it
                --is open: a width change repositions the auto-width panel
                --and the whole strip visibly shifts (and re-anchoring via
                --pivot desyncs the hit geometry -- field-tested). The name
                --slot is fixed-width for exactly this reason.
                bgimage = true,
                --the raycaster hands "hover" to the hit panel plus its
                --ancestors, stopping at the first swallowPress panel. The
                --member buttons swallow, but without this the strip's own
                --background (the gaps between members) does not -- so the
                --OWNER button gained hover over the gaps and lost it over
                --the members, pulsing its hover style as the pointer swept
                --the strip. Stop the chain here: the owner only reads
                --hovered when the pointer is actually on it.
                swallowPress = true,

                --the strip's own background counts as rail proximity too,
                --so sweeping across the GAPS between members does not blink
                --the + the way crossing the members themselves used to.
                hover = function(element)
                    RailNotifyProximity(element, true)
                end,

                dehover = function(element)
                    RailNotifyProximity(element, false)
                    if g_railRearranging then
                        return
                    end
                    if ownerButton ~= nil and ownerButton.valid then
                        ownerButton:ScheduleEvent("closeGroupFlyout", RAIL_FLYOUT_CLOSE_GRACE)
                    end
                end,

                children = memberButtons,
            }
            groupHoverPanels[#groupHoverPanels + 1] = groupFlyout
        end

        --Character entries render as a CARD spanning two slots: portrait
        --on top, stamina below it, and -- for heroes -- heroic resource +
        --surges. Values track the live creature via refreshRail, which
        --the rail root fires on its think cadence, so the card stays
        --current without its own polling. The face itself is shared with
        --the drag-preview ghost (CreateCharacterCardVisual).
        local buttonContent
        if charid ~= nil then
            buttonContent = CreateCharacterCardVisual(charid)
        elseif sbuttonStyle ~= nil and sbuttonStyle.label ~= nil then
            --@label: a live value instead of the icon. The directive is a
            --GoblinScript formula (data, never Lua code) evaluated against
            --the player's current character, re-checked on the rail's
            --refreshRail cadence like the character card's numbers.
            local labelFormula = sbuttonStyle.label
            local function LabelText()
                local token = dmhub.currentToken
                if token == nil or token.properties == nil then
                    return "-"
                end
                local value = nil
                pcall(function()
                    value = ExecuteGoblinScript(labelFormula, token.properties:LookupSymbol{}, 0, "rail button label")
                end)
                if value == nil then
                    return "-"
                end
                local n = tonumber(value)
                if n ~= nil then
                    if n == math.floor(n) then
                        return string.format("%d", n)
                    end
                    return string.format("%.1f", n)
                end
                return tostring(value)
            end
            buttonContent = gui.Label{
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                fontSize = 18,
                bold = true,
                color = "#ffffffee",
                interactable = false,
                text = LabelText(),
                refreshRail = function(element)
                    element.text = LabelText()
                end,
            }
        else
            buttonContent = gui.Panel{
                classes = {"iconRailIcon"},
                bgimage = buttonIcon,
                width = 20,
                height = 20,
                halign = "center",
                valign = "center",
                create = function(element)
                    if buttonIconTint ~= nil then
                        element.selfStyle.bgcolor = buttonIconTint
                    end
                    if buttonIconRect ~= nil then
                        element.selfStyle.imageRect = buttonIconRect
                    end
                end,
            }
        end

        --a button rebuilt right after landing from a drop settles in with
        --a scale-down animation: it constructs oversized (justDropped)
        --and sheds the class a moment later, riding the transition.
        local buttonClasses = {"iconRailButton"}
        if g_railJustDropped ~= nil and g_railJustDropped == key then
            buttonClasses[#buttonClasses + 1] = "justDropped"
            g_railJustDropped = nil
        end
        --rearrange mode: wiggle, with neighbours desynced from the
        --start (odd slots begin counter-tilted, alternating pairs
        --begin contracted).
        if g_railRearranging then
            buttonClasses[#buttonClasses + 1] = "rearranging"
            if index % 2 == 1 then
                buttonClasses[#buttonClasses + 1] = "wigglePhase"
            end
            if index % 4 >= 2 then
                buttonClasses[#buttonClasses + 1] = "pulsePhase"
            end
        end

        --new-content marker: a registered panel that declares hasNewContent
        --(e.g. Bestiary -> module.HasNovelContent("monsters") after a
        --module install adds or updates monsters; Chat -> unread messages)
        --shows the standard alert marker in the button's top-left corner --
        --top-right belongs to the group badge. The optional registration
        --fields extend it: newContentCount() supplies a number (2+ renders
        --inside the marker as a badge; 1 stays a plain dot), and
        --markContentSeen() is called while the panel is on screen so the
        --registration can retire its "new" state (how Chat absorbs unread
        --messages), and clearNewContent() retires it on demand -- the
        --right-click "Clear Alerts" entry, for the panels whose alerts do
        --NOT retire by being looked at (novel module content clears only
        --per item, and only from the handful of rows wired to do it).
        --Everything re-checks on the rail's refreshRail cadence, and the
        --marker hides while the panel itself is shown.
        local novelMarker = nil
        if reg ~= nil and reg.hasNewContent ~= nil then
            local hasNewContent = reg.hasNewContent
            local newContentCount = reg.newContentCount
            local markContentSeen = reg.markContentSeen
            local m_shownCount = nil --count the marker currently displays; nil = hidden.
            --the container is a 1x1 anchor sitting ON the button's
            --top-right corner; the badge centers on it, so it pops out
            --of the button bounds like an iOS app badge. Anchored from
            --the left edge plus the button width so the corner position
            --is explicit rather than relying on halign mirroring.
            novelMarker = gui.Panel{
                floating = true,
                halign = "left",
                valign = "top",
                --nudged 2px in from the corner so the badge does not
                --crowd the button edge.
                x = ICON_RAIL_BUTTON - 3,
                y = 2,
                width = 1,
                height = 1,
                flow = "none",
                interactable = false,
                create = function(element)
                    element:FireEvent("refreshRail")
                end,
                refreshRail = function(element)
                    --IsPanelActive, NOT IsPanelShown: a folder window
                    --hosts every member as a tab, so "shown" is true for
                    --panels filed in an open folder that you cannot see.
                    --Marking those seen absorbed Chat's unread messages
                    --while the window sat on a sibling tab.
                    local panelShown = PanelDocument.IsPanelActive(key)
                    if panelShown and markContentSeen ~= nil then
                        markContentSeen()
                    end
                    local count = nil
                    if (not panelShown) and hasNewContent() then
                        count = 1
                        if newContentCount ~= nil then
                            count = newContentCount() or 1
                        end
                        if count < 1 then
                            count = 1
                        end
                    end
                    if count == m_shownCount then
                        return
                    end
                    m_shownCount = count
                    if count == nil then
                        element.children = {}
                    else
                        element.children = {
                            gui.NewContentAlert{
                                count = count,
                                size = 16,
                                halign = "center",
                                valign = "center",
                                x = 0,
                                y = 0,
                                interactable = false,
                            },
                        }
                    end
                end,
            }
        end

        --background-process gear: a registered panel with a running
        --background process (DockablePanel.StartProcess -- e.g. the Monster
        --AI while the AI is playing turns) wears a small spinning cog on the
        --button's bottom-left corner. The process outlives the panel, so the
        --gear shows whether the panel is open or closed: it marks "this
        --panel has live work going on" and where to go to stop it. Same
        --anchor pattern as the new-content marker (a 1x1 floating point the
        --cog centers on); liveness re-checks on the rail's refreshRail
        --cadence, and the cog child only exists -- and only pays its spin
        --think -- while a process is actually running.
        local processGear = nil
        if reg ~= nil then
            local m_gearShown = false
            processGear = gui.Panel{
                floating = true,
                halign = "left",
                valign = "top",
                --nudged 2px in from the corner, mirroring the new-content
                --badge's inset on the opposite corner.
                x = 3,
                y = buttonHeight - 3,
                width = 1,
                height = 1,
                flow = "none",
                interactable = false,
                create = function(element)
                    element:FireEvent("refreshRail")
                end,
                refreshRail = function(element)
                    local active = DockablePanel.HasActiveProcess(panelName)
                    if active == m_gearShown then
                        return
                    end
                    m_gearShown = active
                    if not active then
                        element.children = {}
                    else
                        element.children = {
                            gui.Panel{
                                classes = {"iconRailProcessGear"},
                                bgimage = "phosphor/gear-fine-fill.png",
                                width = 26,
                                height = 26,
                                halign = "center",
                                valign = "center",
                                interactable = false,
                                data = { angle = 0 },
                                --the constant spin: ~1 revolution every 3
                                --seconds, stepped at 20Hz. Driven by think
                                --rather than a style transition because the
                                --rotation never settles; the angle stays
                                --wrapped so a long session cannot grow it
                                --unbounded.
                                thinkTime = 0.05,
                                think = function(element)
                                    element.data.angle = (element.data.angle + 6) % 360
                                    element.selfStyle.rotate = element.data.angle
                                end,
                            },
                        }
                    end
                end,
            }
        end

        --GROUP marker: a second card peeking out from behind the button
        --(up and toward the screen centre), so a grouped button reads as
        --a small stack. A floating SIBLING appended before the button --
        --z-order is sibling order and a child can never draw behind its
        --parent's own bgimage. Positioned at the slot's absolute top
        --(floating panels sit outside the flow), so ghost-reflow margin
        --shifts don't move it -- the rails rebuild on any real layout
        --change anyway, grouping included.
        --The button face is translucent (frosted black), so a plain card
        --behind it showed THROUGH it, and clip-rect strips left an ugly
        --square inner corner against the button's rounded one. The card
        --is a pre-shaped image instead (see ICON_RAIL_GROUP_SHADOW_IMAGE):
        --the button's silhouette is subtracted from it, so nothing ever
        --renders under the face and the inner edge follows the button's
        --curve exactly. The image is authored for the left rail; the
        --right rail mirrors it about the panel centre with a negative x
        --scale (scale does not affect layout, and the panel is not
        --interactable, so hit-testing is moot).
        if groupMembers ~= nil then
            --constructs already faded out when the strip starts expanded
            --(rearrange mode) or any of the folder's windows is already
            --open, so a rail rebuild never flashes the card in.
            local shadowClasses = {"iconRailGroupShadow"}
            if GroupShadowHidden() then
                shadowClasses[#shadowClasses + 1] = "groupOpen"
            end
            groupShadow = gui.Panel{
                classes = shadowClasses,
                bgimage = ICON_RAIL_GROUP_SHADOW_IMAGE,
                floating = true,
                interactable = false,
                width = ICON_RAIL_BUTTON,
                height = buttonHeight,
                halign = cond(side == "left", "left", "right"),
                valign = "top",
                x = cond(side == "left", 5, -5),
                y = buttonTop - 5,
                scale = cond(side == "left", 1, {x = -1, y = 1}),
                --keeps the hidden state honest as the window opens and
                --closes by any path (rail click, tab close, hotkey).
                refreshRail = function(element)
                    UpdateGroupShadow()
                end,
            }
            buttons[#buttons + 1] = groupShadow
        end

        buttons[#buttons + 1] = gui.Panel{
            classes = buttonClasses,
            bgimage = true,
            --a blurred backdrop paints at full strength whatever the
            --panel's own opacity (the + button learned this the hard
            --way), so a button whose author asked for @opacity drops
            --the blur -- otherwise the transparency never reads.
            blurBackground = not (sbuttonStyle ~= nil and sbuttonStyle.opacity ~= nil),
            width = ICON_RAIL_BUTTON,
            --a character card spans several slots; ordinary buttons are
            --one slot tall.
            height = buttonHeight,
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

            --the group flyout opens on hover and closes when the pointer
            --leaves BOTH the button and the strip. The close is deferred a
            --moment and re-checks the live hover classes, so travelling
            --from the button into the strip never shuts it mid-reach.
            hover = function(element)
                RailButtonSound("hover")
                --Tell the rail the pointer is on it, so the + reveals.
                --Hovering a CHILD does not deliver hover to the rail root
                --(measured: the root's handler never fired while the
                --pointer sat on a button), so the buttons have to report
                --it or the + would only ever appear when you were already
                --on top of it -- which is the whole thing this affordance
                --exists to avoid.
                RailNotifyProximity(element, true)
                --Arriving anywhere on the rail shuts whatever strip is
                --open, right now -- including on buttons that have no
                --strip of their own. The neighbour's deferred close would
                --get there eventually, and that wait was exactly the
                --window in which two strips were on screen at once.
                if not g_railRearranging then
                    RailCloseOpenFlyout(element)
                end
                if groupMembers == nil or groupFlyout == nil or not groupFlyout.valid then
                    return
                end
                --The strip opens even while this button's own window is
                --open: members are independent panels now, and the strip
                --is the only way to reach them. (The owner's own button
                --still reads as the close affordance -- the icon's X
                --hint -- while its window is up.)
                --arriving on the button is always a fresh reach for the
                --strip, whatever a previous press did.
                groupFlyoutSuppressed = false
                --the strip opens into the band rail windows are anchored
                --in, and z-order is sibling order, so raise the rail over
                --them. Clicking a window raises it back.
                local rail = element:FindParentWithClass("iconRail")
                if rail ~= nil and rail.valid then
                    rail:SetAsLastSibling()
                end
                groupFlyout:SetClass("collapsed", false)
                --dress for the occasion: the card treatment only when the
                --strip's own band actually intersects an open window.
                --Width covers the member slots plus the name slot (a
                --generous allowance; erring toward the card near an edge
                --beats loose buttons over a window).
                local stripWidth = #groupMembers * (ICON_RAIL_BUTTON + 8) + 160
                local sy = ICON_RAIL_TOP + buttonTop
                local sx1
                if side == "left" then
                    sx1 = ICON_RAIL_LEFT + ICON_RAIL_BUTTON
                else
                    sx1 = (dmhub.screenDimensionsBelowTitlebar.x - ICON_RAIL_LEFT - ICON_RAIL_BUTTON) - stripWidth
                end
                local overPanel = RailWindowIntersectsBand(sx1, sy, sx1 + stripWidth, sy + ICON_RAIL_BUTTON)
                --docks are not panel-document windows, but a dock visible
                --on this side always underlies the strip band -- the strip
                --opens straight across it. Err toward the card: text and
                --loose buttons over ANY panel is the failure mode.
                if not overPanel then
                    overPanel = dmhub.GetSettingValue(string.format("%sdockoffscreen", side)) == false
                end
                --the fill lives on the backdrop layer, sized to the
                --current name (see UpdateStripCard); the flyout itself
                --stays the barely-there full-width hit surface. The class
                --stays set for anything else keying off the state.
                groupFlyout:SetClass("stripCard", overPanel)
                --arriving back on the owner, the card's name slot shows
                --the owner's own name again.
                if stripLabel ~= nil and stripLabel.valid then
                    stripLabel.text = HoverLabelText()
                end
                if UpdateStripCard ~= nil then
                    UpdateStripCard(HoverLabelText(), overPanel)
                end
                --the stack is now expanded into the strip: the marker
                --card behind the button fades out while it is open.
                SetGroupExpanded(true)
                if not g_railRearranging then
                    g_railOpenFlyout = { owner = element, close = CollapseGroupFlyout }
                end
            end,
            dehover = function(element)
                RailButtonSound("dehover")
                --the rail's own grace period decides whether this actually
                --hides the + (travelling between buttons must not).
                RailNotifyProximity(element, false)
                if groupMembers == nil or g_railRearranging then
                    return
                end
                --leaving the button re-arms the strip: a press-hidden
                --strip comes back on the next hover.
                groupFlyoutSuppressed = false
                element:ScheduleEvent("closeGroupFlyout", RAIL_FLYOUT_CLOSE_GRACE)
            end,
            closeGroupFlyout = function(element)
                --in rearrange mode the strip is pinned open.
                if g_railRearranging then
                    return
                end
                if groupFlyout == nil or not groupFlyout.valid or not element.valid then
                    return
                end
                if element:HasClass("hover") or GroupHovered() then
                    return
                end
                CollapseGroupFlyout()
            end,

            create = function(element)
                ownerButton = element
                --the author's style directives land as selfStyle
                --overrides: they win over the theme's class rules
                --(including hover's bgcolor -- a custom-colored button
                --keeps its color under the pointer).
                if sbuttonStyle ~= nil then
                    if sbuttonStyle.bgcolor ~= nil then
                        element.selfStyle.bgcolor = sbuttonStyle.bgcolor
                    end
                    if sbuttonStyle.gradient ~= nil then
                        --the gradient multiplies against bgcolor, so
                        --default the base to white for true stop colors;
                        --an explicit @bgcolor still tints.
                        if sbuttonStyle.bgcolor == nil then
                            element.selfStyle.bgcolor = "#ffffff"
                        end
                        element.selfStyle.gradient = gui.Gradient{
                            point_a = {x = 0, y = 1},
                            point_b = {x = 0, y = 0},
                            stops = {
                                { position = 0, color = sbuttonStyle.gradient[1] },
                                { position = 1, color = sbuttonStyle.gradient[2] },
                            },
                        }
                    end
                    if sbuttonStyle.opacity ~= nil then
                        element.selfStyle.opacity = sbuttonStyle.opacity
                    end
                end
                if element:HasClass("justDropped") then
                    element:ScheduleEvent("settleDrop", 0.05)
                end
                if g_railRearranging then
                    --stagger the first flips by slot so the rail
                    --shimmers rather than ticking in lockstep.
                    element:ScheduleEvent("wiggle", 0.12 + (index % 3) * 0.04)
                    element:ScheduleEvent("wigglePulse", 0.17 + (index % 4) * 0.05)
                end
            end,
            settleDrop = function(element)
                element:SetClass("justDropped", false)
            end,
            --the rearrange-mode wiggle: two loops on different periods
            --("wiggle" flips the tilt, "wigglePulse" the scale) so the
            --phases drift and the motion stays organic. The loops die
            --with the button -- exiting the mode rebuilds the rails --
            --but guard anyway for events landing mid-teardown.
            wiggle = function(element)
                if mod.unloaded or not g_railRearranging or not element.valid then
                    return
                end
                element:SetClass("wigglePhase", not element:HasClass("wigglePhase"))
                element:ScheduleEvent("wiggle", 0.12)
            end,
            wigglePulse = function(element)
                if mod.unloaded or not g_railRearranging or not element.valid then
                    return
                end
                element:SetClass("pulsePhase", not element:HasClass("pulsePhase"))
                element:ScheduleEvent("wigglePulse", 0.17)
            end,

            buttonContent,

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

            --the close hint that replaces the icon while hovering an OPEN
            --panel's button (see the iconRailCloseHint styles). Present on
            --every button unconditionally -- keeping the children list
            --hole-free -- but only the "active" class ever reveals it, and
            --character-card shortcuts never carry that class.
            gui.Panel{
                classes = {"iconRailCloseHint"},
                floating = true,
                bgimage = "phosphor/x-bold.png",
                width = 16,
                height = 16,
                halign = "center",
                valign = "center",
                interactable = false,
            },

            gui.Label{
                classes = {"iconRailLabel", cond(groupMembers ~= nil, "collapsed")},
                floating = true,
                --see the tray label: rail windows left open sit over the rail,
                --so without this the hover label drew behind them.
                renderOnTop = true,
                --The label sits on the MAP side of the button, vertically
                --centred on its row -- the one place guaranteed free of
                --other controls, so it never overlaps a neighbouring
                --button. GROUPED buttons collapse this label entirely: the
                --flyout strip card carries its own name slot (stripLabel),
                --which follows the pointer across owner and members. The
                --rearrange-mode cut-out on a group-capable button still
                --shifts the label one slot outward.
                x = labelArgs.x + cond(side == "left", 1, -1) * (
                    cond(g_railRearranging and groupCapable, 1, 0) * (ICON_RAIL_BUTTON + 8)),
                halign = labelArgs.halign,
                valign = "center",
                y = 0,
                interactable = false,
                --NO bgimage: the label is plain text, and a bgimage panel
                --can flash its plate at default tint for a frame when the
                --rails rebuild mid-hover, before the cascade's clear
                --bgcolor lands. No image, no plate, no race.
                text = HoverLabelText(),
                refreshRail = function(element)
                    local text = HoverLabelText()
                    if element.text ~= text then
                        element.text = text
                    end
                end,
                width = "auto",
                height = "auto",
                hpad = 8,
                vpad = 4,
                borderBox = true,
                textWrap = false,
            },

            --before novelMarker: novelMarker can be nil and must stay the
            --LAST positional entry (a nil mid-constructor would hole the
            --array and drop everything after it). processGear is non-nil
            --whenever novelMarker is (both require reg), so this order can
            --never create a hole.
            processGear,

            novelMarker,

            --Buttons can only be dragged in rearrange mode (context
            --menu > Rearrange...). Drop position decides which rail it
            --lands on (screen half) and which slot. The drop is hybrid:
            --an EMPTY slot takes the button as-is (leaving a hole
            --behind), an OCCUPIED slot means "insert in between" and
            --shuffles the run without creating holes. The ghost
            --previews which one you will get (dotted box vs insertion
            --line). Dropping on the trash zone removes the button from
            --the rail instead.
            draggable = g_railRearranging,
            --LOAD-BEARING: the engine resolves drag targets only for
            --panels that define canDragOnto (a nil handler means "no
            --targets at all"), so without this the drag handlers below
            --would never see the trash. ONLY the trash is engine-
            --resolved: the grouping zones (cut-outs, dividers) are
            --chosen by POINTER position (RailGroupZoneAt) because the
            --engine scores overlap candidates by panel-centre distance,
            --which aims wrong by the grab offset. Everything else --
            --buttons, gaps, empty space -- is geometric slot placement.
            canDragOnto = function(element, target)
                return target:HasClass("iconRailTrash")
            end,
            dragging = function(element, target)
                --over the trash: the previews would lie (this drop
                --removes, not moves), so clear them. The trash itself
                --lights up via the drag-target-hover styles.
                if target ~= nil and target.valid and target:HasClass("iconRailTrash") then
                    HideRailGhost()
                    RailSetZoneHover(nil)
                    return
                end
                local px, py = RailButtonDragPointer(side, index, element)
                if docid == nil and charid == nil then
                    local zone = RailGroupZoneAt(px, py, key)
                    if zone ~= nil then
                        HideRailGhost()
                        RailSetZoneHover(zone.panel)
                        return
                    end
                end
                RailSetZoneHover(nil)
                local targetSide, targetSlot = RailDropPoint(px, py, key)
                ShowRailGhost(targetSide, targetSlot, key)
            end,
            drag = function(element, target)
                g_railDragTime = dmhub.Time()
                HideRailGhost()
                RailSetZoneHover(nil)

                --dropped on the trash: take the button off the rail
                --(parks the layout entry inert, exactly like the
                --context menu's "Remove from rail").
                if target ~= nil and target.valid and target:HasClass("iconRailTrash") then
                    RailMovePanel(key, "remove")
                    return
                end

                local px, py = RailButtonDragPointer(side, index, element)

                --dropped into another window's child space (its cut-out
                --box, or a divider boundary in its expanded strip): this
                --panel becomes a tab of that window. Its own layout
                --entry stays behind inert, so ungrouping later returns
                --it home.
                if docid == nil and charid == nil then
                    local zone = RailGroupZoneAt(px, py, key)
                    if zone ~= nil then
                        RailGroupInsert(key, zone.ownerKey, zone.beforeKey)
                        return
                    end
                end

                local targetSide, targetSlot = RailDropPoint(px, py, key)
                if targetSide == side and targetSlot == index then
                    --landed on the slot it started from: nothing was
                    --rearranged, just snap the button back home.
                    RebuildIconRails()
                    return
                end

                local sides, inert = RailLayout()

                --locate the dragged entry; it stays in place for now --
                --the run boundaries below are computed over the pristine
                --layout, and which branch runs decides how it moves.
                local dragged, sourceList, sourceIdx, sourceSlot
                for _, sideList in pairs(sides) do
                    for j, e in ipairs(sideList) do
                        if e.key == key then
                            dragged, sourceList, sourceIdx, sourceSlot = e, sideList, j, e.slot
                        end
                    end
                end
                if dragged == nil then
                    return
                end

                local targetList = sides[targetSide]
                local function anyAt(list, s)
                    for _, e in ipairs(list) do
                        if e.slot == s then
                            return true
                        end
                    end
                    return false
                end
                local function occupiedByOther(list, s)
                    for _, e in ipairs(list) do
                        if e.slot == s and e ~= dragged then
                            return true
                        end
                    end
                    return false
                end

                if not occupiedByOther(targetList, targetSlot) then
                    --EMPTY target slot: sparse placement. Land exactly
                    --there and leave a hole where the button came from --
                    --blank spots are part of the layout, and dragging a
                    --button into empty space is how they are made.
                    table.remove(sourceList, sourceIdx)
                    dragged.slot = targetSlot
                    table.insert(targetList, dragged)
                    table.sort(targetList, function(a, b) return a.slot < b.slot end)
                else
                    --OCCUPIED target slot: reorder semantics -- this drop
                    --means "in between", never "make a gap". The shape of
                    --the shuffle depends on whether the button comes from
                    --inside or outside the contiguous occupied run around
                    --the target.
                    local runStart = targetSlot
                    while runStart > 0 and anyAt(targetList, runStart - 1) do
                        runStart = runStart - 1
                    end
                    local runEnd = targetSlot
                    while anyAt(targetList, runEnd + 1) do
                        runEnd = runEnd + 1
                    end

                    if sourceList == targetList and sourceSlot >= runStart and sourceSlot <= runEnd then
                        --Reorder WITHIN one run (the packed-rail common
                        --case): the dragged button slots in just above the
                        --occupant of the target slot and the neighbours
                        --slide toward the spot it vacated. The run's slot
                        --numbers are reassigned as the SAME set, so the
                        --shuffle never opens a hole and never disturbs the
                        --blank space around the run.
                        local runSlots, runEntries = {}, {}
                        for _, e in ipairs(targetList) do
                            if e.slot >= runStart and e.slot <= runEnd then
                                runSlots[#runSlots + 1] = e.slot
                                runEntries[#runEntries + 1] = e
                            end
                        end
                        dragged.slot = targetSlot
                        --`b ~= dragged` is LOAD-BEARING: dragged now
                        --shares a slot with the target's occupant, and a
                        --comparator returning true for (dragged, dragged)
                        --is not a strict weak order -- table.sort throws
                        --"invalid order function for sorting" (hit live
                        --2026-08-08).
                        table.sort(runEntries, function(a, b)
                            if a.slot == b.slot then
                                return a == dragged and b ~= dragged
                            end
                            return a.slot < b.slot
                        end)
                        for i, e in ipairs(runEntries) do
                            e.slot = runSlots[i]
                        end
                        table.sort(targetList, function(a, b) return a.slot < b.slot end)
                    else
                        --Insert from OUTSIDE the run (another cluster, an
                        --isolated button, or the other rail): the dragged
                        --button takes the slot and the occupants chain-bump
                        --down into the first free slot. The cluster it left
                        --closes up behind it -- reorder-type drops never
                        --leave holes; only drops into empty space do.
                        local sourceEnd = sourceSlot
                        while anyAt(sourceList, sourceEnd + 1) do
                            sourceEnd = sourceEnd + 1
                        end
                        table.remove(sourceList, sourceIdx)
                        for _, e in ipairs(sourceList) do
                            if e.slot > sourceSlot and e.slot <= sourceEnd then
                                e.slot = e.slot - 1
                            end
                        end

                        dragged.slot = targetSlot
                        table.insert(targetList, dragged)
                        --`b ~= dragged`: same strict-weak-order guard as
                        --the within-run sort above.
                        table.sort(targetList, function(a, b)
                            if a.slot == b.slot then
                                return a == dragged and b ~= dragged
                            end
                            return a.slot < b.slot
                        end)
                        local used = {}
                        for _, e in ipairs(targetList) do
                            local s = e.slot
                            while used[s] do
                                s = s + 1
                            end
                            used[s] = true
                            e.slot = s
                        end
                    end
                end

                g_railJustDropped = key
                SaveRailLayout(sides, inert)
                RebuildIconRails()
            end,

            --Open/close this button's window. Fired by the press handler
            --and by the context menu's "Open" entry.
            activateRailButton = function(element)
                --standalone script button: clicking IS the action --
                --run the stored chunk (insulated + kill-checked when it
                --came from a pack). A pack button of type "panel" is a
                --panel shortcut rather than a script: open that panel.
                if sbuttonid ~= nil then
                    local def = (dmhub.GetSettingValue("iconrailscriptbuttons") or {})[sbuttonid]
                    if type(def) == "table" then
                        if def.type == "panel" and def.panel ~= nil then
                            DockablePanel.ShowPanelByName(def.panel)
                            RefreshRails()
                        else
                            RunToolkitScriptButton(def, element)
                        end
                    end
                    return
                end

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

                --toolkit: toggle its floating strip, anchored beside
                --this button on first open (it remembers its own spot
                --thereafter).
                if toolkitid ~= nil then
                    local ax, ay = RailAnchor(side, index)
                    ToggleToolkitStrip(toolkitid, ax, ay)
                    RefreshRails()
                    return
                end

                local doc = RailPanelDocument(key)
                if doc == nil then
                    return
                end

                --character card: any click that SHOWS the panel also
                --brings the camera to the token when it is off-screen
                --(FocusToken no-ops for tokens not on the loaded map).
                local function CenterOnCharacter()
                    if charid == nil then
                        return
                    end
                    local tok = dmhub.GetTokenById(charid)
                    if tok == nil or not tok.valid then
                        return
                    end
                    local b = dmhub.cameraBounds
                    local p = tok.pos
                    if b ~= nil and p ~= nil and p.x >= b.x1 and p.x <= b.x2 and p.y >= b.y1 and p.y <= b.y2 then
                        return
                    end
                    dmhub.FocusToken(charid)
                end

                --A popped-out panel is not in any window this rail owns,
                --so it never reaches RailActivation below: its icon
                --raises the OS window (or flashes its taskbar button when
                --the OS denies the focus steal) rather than opening a
                --copy. It comes home via the popout's own pop-in button.
                --pcall: RaiseNativeWindow needs an engine build newer
                --than this file; on an older build the click is a no-op.
                if PanelDocument.IsPoppedOut(key) then
                    local popoutHost = PanelDocument.PopoutHost(key)
                    if popoutHost ~= nil and popoutHost.valid then
                        pcall(function()
                            popoutHost:RaiseNativeWindow()
                        end)
                    end
                    CenterOnCharacter()
                    RefreshRails()
                    return
                end

                --A folder button's window carries the whole folder as
                --tabs, so the icon has the same three meanings a strip
                --member does: raise/switch, close, or open. (For a rail
                --BUTTON the owner is always the key itself -- members
                --have no button -- but routing through the same helper
                --keeps the two paths honest.)
                local verb, ownerKey, ownerDoc, d = RailActivation(key)
                if ownerDoc == nil then
                    return
                end

                if verb == "switch" or verb == "raise" then
                    --a PINNED window cannot be closed by its icon either;
                    --the icon just raises it (and re-arms a map-mode
                    --panel's tool -- you clicked it, you mean to use it).
                    d:SetAsLastSibling()
                    d:FireEventTree("focusPanelTab", key)
                    CenterOnCharacter()
                elseif verb == "close" then
                    --clicking the icon of the panel already on screen
                    --closes its window -- the whole folder with it.
                    RailForgetWindow(ownerKey)
                    ownerDoc:ClosePanel()
                else
                    --one transient window at a time: opening a panel
                    --closes the previous un-pinned one.
                    if g_railTransientKey ~= nil and g_railTransientKey ~= ownerKey then
                        local prev = RailPanelDocument(g_railTransientKey)
                        if prev ~= nil then
                            prev:ClosePanel()
                        end
                    end
                    g_railTransientKey = ownerKey

                    local anchorX, anchorY = RailAnchor(side, index)
                    OpenIconRailWindow(key, {
                        x = anchorX,
                        y = anchorY,
                        anchor = true,
                        autoFocus = true,
                    })
                    CenterOnCharacter()
                end

                RefreshRails()
            end,

            --Open on PRESS, not click: the window appears the moment the
            --mouse goes down, which reads as snappier -- and since the
            --buttons are not draggable outside rearrange mode, there is
            --no press-vs-drag ambiguity to wait out.
            press = function(element)
                RailButtonSound("press")

                --in rearrange mode presses begin drags, never open.
                if g_railRearranging then
                    return
                end

                --The window this press opens lands right where the flyout
                --strip is, so the press folds the strip away first (and a
                --second press brings it back). Only the visual state is
                --toggled -- which panels are in the group is untouched.
                if groupMembers ~= nil and groupFlyout ~= nil and groupFlyout.valid then
                    groupFlyoutSuppressed = not groupFlyoutSuppressed
                    if groupFlyoutSuppressed then
                        CollapseGroupFlyout()
                    else
                        groupFlyout:SetClass("collapsed", false)
                        SetGroupExpanded(true)
                        g_railOpenFlyout = { owner = element, close = CollapseGroupFlyout }
                    end
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
                --rearrange mode has exactly two verbs -- drag and stop --
                --so no menus over the wiggling buttons.
                if g_railRearranging then
                    return
                end

                --Open the window if it is not already up, then lock it in
                --place (or release it). SetPinned's hook records it and
                --refreshes the rails.
                local function togglePin()
                    local doc = RailPanelDocument(key)
                    if doc == nil then
                        return
                    end
                    local pinning = not PanelDocument.IsPinned(key)
                    if pinning and not doc:PresentDocumentOpen() then
                        local anchorX, anchorY = RailAnchor(side, index)
                        OpenIconRailWindow(key, { x = anchorX, y = anchorY, anchor = true, autoFocus = true })
                    end
                    PanelDocument.SetPinned(key, pinning)
                end

                --the move/remove entries every rail button carries.
                local function moveEntries()
                    return {
                        {
                            text = "Rearrange...",
                            click = function()
                                element.popup = nil
                                RailSetRearranging(true)
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
                    }
                end

                --standalone script buttons: run + edit + moves + delete.
                if sbuttonid ~= nil then
                    local entries = moveEntries()
                    table.insert(entries, 1, {
                        text = "Run",
                        click = function()
                            element.popup = nil
                            element:FireEvent("activateRailButton")
                        end,
                    })
                    entries[#entries + 1] = {
                        text = "Edit Script...",
                        click = function()
                            element.popup = nil
                            RailScriptButtonDialog("button:" .. sbuttonid, nil)
                        end,
                    }
                    entries[#entries + 1] = {
                        text = "Delete Button",
                        click = function()
                            element.popup = nil
                            RailDeleteScriptButton(sbuttonid)
                        end,
                    }
                    element.popup = gui.ContextMenu{
                        entries = entries,
                    }
                    return
                end

                --toolkits: open/close + rename + moves + delete. No pin
                --or keep-open -- the strip manages its own persistence.
                if toolkitid ~= nil then
                    local entries = moveEntries()
                    table.insert(entries, 1, {
                        text = cond(RailToolkitStripOpen(toolkitid), "Close", "Open"),
                        click = function()
                            element.popup = nil
                            element:FireEvent("activateRailButton")
                        end,
                    })
                    entries[#entries + 1] = {
                        text = "Rename / Change Icon...",
                        click = function()
                            element.popup = nil
                            RailEditToolkit(toolkitid)
                        end,
                    }
                    entries[#entries + 1] = {
                        text = "Delete Toolkit",
                        click = function()
                            element.popup = nil
                            RailDeleteToolkit(toolkitid)
                        end,
                    }
                    element.popup = gui.ContextMenu{
                        entries = entries,
                    }
                    return
                end

                --shortcuts (documents, characters) get the reduced menu:
                --open + moves, plus pinning for characters (they are real
                --panel windows; journal documents open in the viewer and
                --have no window of their own to pin).
                if docid ~= nil or charid ~= nil then
                    local entries = moveEntries()
                    if charid ~= nil then
                        table.insert(entries, 1, {
                            text = cond(PanelDocument.IsPinned(key), "Unpin", "Pin in place"),
                            click = function()
                                element.popup = nil
                                togglePin()
                            end,
                        })
                    end
                    table.insert(entries, 1, {
                        text = "Open",
                        click = function()
                            element.popup = nil
                            element:FireEvent("activateRailButton")
                        end,
                    })
                    element.popup = gui.ContextMenu{
                        entries = entries,
                    }
                    return
                end

                --"Keep open": open the window (or adopt the open one) and
                --record it, so it survives the next click on another icon
                --and comes back with the rails. This is the non-locking
                --half of what "pinned" used to mean here.
                local function keepOpen()
                    local doc = RailPanelDocument(key)
                    if doc == nil then
                        return
                    end
                    if doc:PresentDocumentOpen() then
                        local d = doc:try_get("_tmp_dialog")
                        if d ~= nil and d.valid then
                            RailRememberWindow(key, d.x, d.y, doc)
                        end
                    else
                        local anchorX, anchorY = RailAnchor(side, index)
                        OpenIconRailWindow(key, {
                            x = anchorX,
                            y = anchorY,
                            anchor = true,
                            autoFocus = true,
                        })
                        --record where it ACTUALLY landed, not the anchor:
                        --an anchored open yields to a position the user
                        --dragged this window to earlier in the session.
                        local d = doc:try_get("_tmp_dialog")
                        if d ~= nil and d.valid then
                            RailRememberWindow(key, d.x, d.y, doc)
                        else
                            RailRememberWindow(key, anchorX, anchorY, doc)
                        end
                    end
                    RefreshRails()
                end

                local entries = moveEntries()

                --a grouped window's button can dissolve the whole group:
                --every member returns to its own remembered rail slot.
                if groupMembers ~= nil then
                    entries[#entries + 1] = {
                        text = "Ungroup",
                        click = function()
                            element.popup = nil
                            RailUngroupAll(key)
                        end,
                    }
                end

                --bind a hotkey to this panel's "togglepanel" command --
                --the same command (and the same popup) the settings
                --screen's User Interface section uses, so the binding
                --shows up there too. The hover label and the Open entry
                --both display it.
                local bindCommand = string.format("togglepanel %s", key)
                entries[#entries + 1] = {
                    text = "Set Keybind...",
                    bind = dmhub.GetCommandBinding(bindCommand),
                    click = function()
                        element.popup = Keybinds.ShowBindPopup{
                            command = bindCommand,
                            name = panelName,
                            --open toward the screen centre so the dialog
                            --sits beside the rail instead of over its
                            --buttons (centered-on-anchor, the default,
                            --straddles the rail column).
                            halign = cond(side == "left", "right", "left"),
                            valign = "center",
                            close = function()
                                if element.valid then
                                    element.popup = nil
                                end
                            end,
                            destroy = function()
                                --the hover labels re-read the binding from
                                --refreshRail; nudge them so the new key
                                --shows without waiting on the think tick.
                                if not mod.unloaded then
                                    RefreshRails()
                                end
                            end,
                        }
                    end,
                }

                --"Clear Alerts": retire the new-content marker in one act,
                --for the registrations that can do it -- clearNewContent
                --(a bulk wipe, e.g. Bestiary dropping every novel monster)
                --or, failing that, markContentSeen (what Chat already uses
                --to absorb unread). ONLY offered while there is actually an
                --alert on this button: a permanently-present "Clear Alerts"
                --over a clean icon is noise, and reads as if something were
                --there to clear.
                local clearAlerts = nil
                local numAlerted = 0
                if reg ~= nil and reg.hasNewContent ~= nil and reg.hasNewContent() then
                    clearAlerts = reg.clearNewContent or reg.markContentSeen
                    numAlerted = #DockablePanel.GetAlertedRegistrations()
                end

                table.insert(entries, 1, {
                    text = cond(PanelDocument.IsPinned(key), "Unpin", "Pin in place"),
                    click = function()
                        element.popup = nil
                        togglePin()
                    end,
                })
                table.insert(entries, 1, {
                    text = "Keep open",
                    click = function()
                        element.popup = nil
                        keepOpen()
                    end,
                })
                table.insert(entries, 1, {
                    text = "Open",
                    bind = dmhub.GetCommandBinding(bindCommand),
                    click = function()
                        element.popup = nil
                        element:FireEvent("activateRailButton")
                    end,
                })

                --slotted in after the three open/keep/pin verbs, ahead of
                --the move verbs: it acts on this panel, not on where the
                --button lives.
                if clearAlerts ~= nil then
                    table.insert(entries, 4, {
                        text = "Clear Alerts",
                        click = function()
                            element.popup = nil
                            clearAlerts()
                            RefreshRails()
                        end,
                    })

                    --when other panels have alerts too, offer the sweep:
                    --every alerted registration retires in one act.
                    if numAlerted > 1 then
                        table.insert(entries, 5, {
                            text = "Clear All Alerts",
                            click = function()
                                element.popup = nil
                                --re-fetched at click time: alerts may have
                                --changed while the menu sat open.
                                for _,p in ipairs(DockablePanel.GetAlertedRegistrations()) do
                                    local clear = p.clearNewContent or p.markContentSeen
                                    clear()
                                end
                                RefreshRails()
                            end,
                        })
                    end
                end

                element.popup = gui.ContextMenu{
                    entries = entries,
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
                --a toolkit button is lit while its strip is up.
                if toolkitid ~= nil then
                    element:SetClass("active", RailToolkitStripOpen(toolkitid))
                    return
                end
                --lit while the panel's window is open.
                element:SetClass("active", PanelDocument.IsPanelShown(key))
            end,
        }

        --the member strip rides BESIDE the button as a later sibling
        --(see its construction): after the button so it draws over it,
        --and outside it so the rearrange wiggle cannot swing the row.
        buttons[#buttons + 1] = groupFlyout
    end

    --The ADD (+) affordance, last in the column.
    --
    --Everything it opens -- add a panel, new toolkit -- has been reachable
    --by right-clicking the rail all along, and essentially undiscoverable
    --there: customising your rail is the one activity where the people who
    --want it are the people who do not know the menu exists.
    --
    --Revealed by hovering the RAIL rather than sitting there permanently.
    --Hover-on-the-container is the standard pattern for "add to this
    --collection" (Notion's block handles, GitHub's line +), and it works
    --here because the rail is somewhere the user already goes constantly
    --to open panels -- unlike a screen corner, which nobody visits by
    --accident, and where a hover-revealed control would be no more
    --findable than the right-click it replaces.
    --
    --LAST in the flow on purpose: revealing it can then never displace a
    --button somebody is aiming at. It also keeps its slot in the layout
    --while invisible, so nothing moves when it appears -- and because the
    --rail root's own hit area grows to include that slot, travelling
    --towards the + keeps the rail hovered instead of dismissing the thing
    --you are reaching for.
    --
    --Suppressed in rearrange mode: that is the trash zone's territory, and
    --the two verbs never apply at once.
    --
    --Suppressed entirely while the dev:panellibrary gate is off: the +
    --exists to open the Panel Library, so without the feature there is
    --nothing for it to do. Every later addButton reference is already
    --nil-guarded (rearrange mode leaves it nil the same way).
    local addButton = nil
    if not g_railRearranging and dmhub.GetSettingValue("dev:panellibrary") then
        addButton = CreateRailAddButton(side)
        buttons[#buttons + 1] = addButton
    end

    return gui.Panel{
        classes = {"iconRail"},
        halign = side,
        valign = "top",
        lmargin = cond(side == "left", ICON_RAIL_LEFT, 0),
        rmargin = cond(side == "right", ICON_RAIL_LEFT, 0),
        tmargin = ICON_RAIL_TOP,
        width = ICON_RAIL_BUTTON,
        --ALWAYS auto, never a fixed column height: the vertical flow
        --distributes children across a fixed height, spreading the
        --buttons apart and breaking the slot geometry (field-tested).
        --This is why the rearrange-mode trash zone lives on the layer
        --rather than in the rail.
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
        --without this the right-click below ALSO reaches the map, and the
        --map's context menu replaces ours (popups are exclusive) -- the
        --same reason the buttons swallow their presses.
        swallowPress = true,

        data = {
            side = side,
        },

        --Reveal the + on hovering ANYWHERE on the rail, not just on the +
        --itself. The root's hit area spans the whole column including the
        --+'s slot, so this covers the buttons, the gaps between them, and
        --the approach to the + -- which is what stops it vanishing as the
        --pointer travels toward it.
        --
        --Dwell before showing so sweeping past the rail on the way
        --somewhere else does not flash it. Hiding is immediate: by then
        --the pointer has left the column entirely.
        --Pointer entered or left the rail. Fired by the root's own
        --hover/dehover (the gaps and background) AND by every child via
        --RailNotifyProximity, because a child's hover never reaches here.
        --A COUNT of how many rail elements currently hold the pointer, not
        --a boolean. Crossing from one button to the next delivers the new
        --element's hover BEFORE the old element's dehover, so a flag gets
        --set true and then immediately stamped back to false by the
        --dehover that arrives late -- and the + went dark exactly as you
        --walked to it, with the click gate then discarding your click.
        --Counting is order-independent: enter/leave pairs net out and the
        --total only reaches zero when the pointer has genuinely left the
        --column. (The tab chips hit this same trap earlier today; there
        --the fix was to check who still owned the state.)
        railProximity = function(element, near)
            if addButton == nil or not addButton.valid then
                return
            end
            local inside = element.data.railInside or 0
            if near then
                element.data.railInside = inside + 1
                --already up: leave it alone. Re-arming the dwell on every
                --crossing would restart the delay forever.
                if addButton:HasClass("shown") then
                    return
                end
                element:ScheduleEvent("revealRailAdd", 0.25)
                return
            end
            inside = inside - 1
            if inside < 0 then
                inside = 0
            end
            element.data.railInside = inside
            --LAZY hide even at zero: a pointer that clips the edge of the
            --column for a frame should not have to re-earn the dwell.
            element:ScheduleEvent("hideRailAdd", 0.4)
        end,
        hover = function(element)
            element:FireEvent("railProximity", true)
        end,
        dehover = function(element)
            element:FireEvent("railProximity", false)
        end,
        revealRailAdd = function(element)
            --the pointer may have left during the dwell.
            if (element.data.railInside or 0) <= 0 then
                return
            end
            if addButton ~= nil and addButton.valid then
                addButton:SetClass("shown", true)
            end
        end,
        hideRailAdd = function(element)
            if addButton == nil or not addButton.valid then
                return
            end
            --The picker is the authority while it is up: the button stays
            --visible and dark until the list closes, whether that is by
            --choosing something, pressing escape, or clicking away. The
            --popup lives ON the button, so its presence IS the state --
            --nothing extra to keep in sync, and no way for a flag to be
            --left set by a close path nobody remembered to hook.
            --
            --Re-arms itself rather than giving up: this is the only clock
            --running while the pointer is off the rail using the menu.
            local menuOpen = false
            pcall(function() menuOpen = addButton.popup ~= nil end)
            if menuOpen then
                element:ScheduleEvent("hideRailAdd", 0.3)
                return
            end
            addButton:SetClass("open", false)
            --still somewhere on the rail (or came back during the grace).
            if (element.data.railInside or 0) > 0 then
                return
            end
            addButton:SetClass("shown", false)
        end,

        --right-click the rail background: add a panel to this rail. This
        --menu used to hang off the dock/tray button at the top of the
        --column, which no longer exists.
        rightClick = function(element)
            if g_railRearranging then
                return
            end
            local menuEntries = RailAddPanelEntries(element, side)
            table.insert(menuEntries, 1, {
                text = "Rearrange...",
                click = function()
                    element.popup = nil
                    RailSetRearranging(true)
                end,
            })
            table.insert(menuEntries, 2, {
                text = "New Toolkit",
                click = function()
                    element.popup = nil
                    RailCreateToolkit(side)
                end,
            })
            element.popup = gui.ContextMenu{
                entries = menuEntries,
            }
        end,

        --each rail and its own side's dock are mutually exclusive: while
        --this side's dock is on screen the whole rail collapses (the
        --Panels menu is the way back); the other side is unaffected.
        --Children collapse individually rather than the rail root so the
        --root's think keeps running to un-collapse later.
        --The map's drawable area must be recalculated when dock
        --visibility changes: the dock handles used to do this from their
        --monitor events, but the rail collapses those handles and
        --collapsed panels don't process events -- without this call the
        --map stays squeezed as if the docks were still on screen.
        syncDockMode = function(element)
            local dockVisible = not dmhub.GetSettingValue(side .. "dockoffscreen")
            if element.data.lastDockVisible ~= dockVisible then
                element.data.lastDockVisible = dockVisible
                --mirror the dock's slide class here too: its own
                --handle's monitor normally applies it, but the rail
                --collapses the handles (collapsed panels process no
                --events), so without this a Panels-menu dock toggle
                --changes the setting and the dock never moves.
                if gamehud ~= nil and rawget(gamehud, "leftDock") ~= nil then
                    local dock = cond(side == "right", gamehud.rightDock, gamehud.leftDock)
                    if dock ~= nil and dock.valid then
                        dock:SetClass("offscreen", not dockVisible)
                    end
                end
                dmhub.UpdateScreenHudArea(1)
            end
            for _, child in ipairs(element.children) do
                if child.valid then
                    if child:HasClass("iconRailGroupFlyout") then
                        --the member strips live on the root now (siblings
                        --of their buttons, see the flyout construction)
                        --and manage their own collapsed state -- hover
                        --opens them, rearrange mode pins them open. The
                        --dock sync may only ever HIDE them; blanket
                        --un-collapsing here popped every strip open on
                        --the think cadence (field report 2026-08-08).
                        if dockVisible then
                            child:SetClass("collapsed", true)
                        elseif child:HasClass("railStripPinned") then
                            --rearrange mode pins strips open; re-assert it
                            --in case a dock toggle hid them mid-mode.
                            child:SetClass("collapsed", false)
                        end
                    else
                        child:SetClass("collapsed", dockVisible)
                    end
                end
            end
        end,

        create = function(element)
            element:FireEvent("syncDockMode")
        end,

        --"/" with nothing focused: summon chat and start typing. Only the
        --left rail is registered as a chat listener (see BuildIconRails) so
        --this runs once, whichever rail the chat button lives on.
        slash = function(element)
            RailSlashOpensChat()
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
                RemoveDockTrayButtons()
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

--The rearrange-mode trash zone for one side: floats at the very bottom
--of the rail's column, slightly inset from the screen edge and larger
--than a rail button so it reads as a zone rather than another slot.
--Dragging a button onto it removes it from the rail; the drag handlers
--find it by the iconRailTrash class. It sits below ICON_RAIL_MAX_SLOT's
--reach, so no droppable slot hides under it. Deliberately NOT an
--iconRailButton: RailDocDropSlot treats that class as a slot, and a
--journal document dropped on the trash must not be ADDED to the rail.
local function CreateRailTrashZone(side)
    return gui.Panel{
        classes = {"iconRailTrash"},
        --a layer child sits outside the rails' style cascade, so it
        --carries the rail styles itself.
        styles = IconRailStyles(),
        bgimage = true,
        blurBackground = true,
        width = ICON_RAIL_TRASH,
        height = ICON_RAIL_TRASH,
        flow = "none",
        halign = side,
        valign = "bottom",
        lmargin = cond(side == "left", ICON_RAIL_LEFT + 10, 0),
        rmargin = cond(side == "right", ICON_RAIL_LEFT + 10, 0),
        bmargin = 16,
        swallowPress = true,
        dragTarget = true,
        --outrank the rail background (and any button) when the dragged
        --button overlaps more than one target.
        dragTargetPriority = 10,
        data = {},

        gui.Panel{
            classes = {"iconRailTrashIcon"},
            bgimage = "phosphor/trash-light.png",
            width = 28,
            height = 28,
            halign = "center",
            valign = "center",
        },

        gui.Label{
            classes = {"iconRailLabel"},
            floating = true,
            renderOnTop = true,
            x = cond(side == "left", ICON_RAIL_TRASH + 10, -(ICON_RAIL_TRASH + 10)),
            halign = cond(side == "left", "left", "right"),
            valign = "center",
            interactable = false,
            --no bgimage: see the main hover label's note.
            text = "DRAG HERE TO REMOVE",
            width = "auto",
            height = "auto",
            hpad = 8,
            vpad = 4,
            borderBox = true,
            textWrap = false,
        },
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
        if g_railRearranging then
            local trash = CreateRailTrashZone(side)
            g_railTrashZones[side] = trash
            layer:AddChild(trash)
        end
    end

    --One chat listener for both rails, so the "/" hotkey opens one window.
    --The rail ROOT is the listener on purpose: while its own dock is on
    --screen the rail collapses its children (and collapsed panels process
    --no events), but the root itself stays live.
    if g_iconRails.left ~= nil then
        chat.events:Listen(g_iconRails.left)
    end
end

local function DestroyIconRails()
    --destroying a hovered button fires its dehover, and the rebuild that
    --follows fires hover on the button that replaces it under the cursor:
    --silence both, or every drop/pin/group change click-clacks.
    g_railSoundQuietUntil = dmhub.Time() + 0.3
    --any drag-gap shift dies with the buttons that carried it.
    g_railShifted = {}
    g_railShiftSig = nil
    --the strip drop zones (and any hover on one) die with the rails too.
    g_railStripZones = {}
    g_railZoneHover = nil
    --and so does whichever group strip was slid open: its close closure
    --captures panels that are about to be destroyed.
    g_railOpenFlyout = nil
    for side, rail in pairs(g_iconRails) do
        if rail ~= nil and rail.valid then
            rail:DestroySelf()
        end
        g_iconRails[side] = nil
    end
    for side, trash in pairs(g_railTrashZones) do
        if trash ~= nil and trash.valid then
            trash:DestroySelf()
        end
        g_railTrashZones[side] = nil
    end
    if g_railDragGhost ~= nil and g_railDragGhost.valid then
        g_railDragGhost:DestroySelf()
    end
    g_railDragGhost = nil
    if g_railDragGhostLine ~= nil and g_railDragGhostLine.valid then
        g_railDragGhostLine:DestroySelf()
    end
    g_railDragGhostLine = nil
    if g_railCardGhost ~= nil and g_railCardGhost.valid then
        g_railCardGhost:DestroySelf()
    end
    g_railCardGhost = nil
    g_railCardGhostCharid = nil
end

--Tear down and rebuild both rails from the saved layout (after a button
--drag rearranges them). Open windows are untouched.
RebuildIconRails = function()
    DestroyIconRails()
    if RailModeActive() and DocumentsLayer() ~= nil then
        BuildIconRails()
    end
end

--Recolor the rails when the theme or color scheme changes. IconRailStyles
--resolves its tokens (@fg, @fgStrong, the accent on the process gear)
--ONCE, at construction, and nothing rebuilds the rails on a scheme
--switch -- so without this the buttons keep the old scheme's colors until
--something else tears the rails down (a rearrange, a reload, a restart).
--Re-resolving and reassigning styles is the standard MergeTokens
--follow-up; it disturbs neither the layout nor any open window.
--
--The trash zone and the drag ghost are layer children, outside the rail's
--style cascade, so they carry their own copy and need their own
--reassignment. Each gets a FRESH array rather than a shared one: panels
--that append to their own styles later must not edit their neighbours'.
--
--UpdateStyle() after each assignment is REQUIRED, not belt-and-braces.
--Writing `panel.styles` marks only the style-APPLICATION cache stale
--(SheetPanel.cs:806 bumps styleUpdateSeq); unlike the `selfStyle` setter
--it never calls SetStyleDirty, so the root never learns a restyle pass is
--due and the new colors sit dormant until some unrelated event dirties
--the tree -- a hover, a class change, a relayout -- which is why the rail
--used to recolor a beat after the crossfade instead of under it.
--UpdateStyle is exactly SetStyleDirty, and the dirty time propagates down
--to every descendant, so one call per styled root does the whole subtree.
--ThemeSettingsDialog's Apply pokes the docks the same way.
ThemeEngine.OnThemeChanged(mod, function()
    for _, rail in pairs(g_iconRails) do
        if rail ~= nil and rail.valid then
            rail.styles = IconRailStyles()
            rail:UpdateStyle()
        end
    end
    for _, trash in pairs(g_railTrashZones) do
        if trash ~= nil and trash.valid then
            trash.styles = IconRailStyles()
            trash:UpdateStyle()
        end
    end
    if g_railDragGhost ~= nil and g_railDragGhost.valid then
        g_railDragGhost.styles = IconRailStyles()
        g_railDragGhost:UpdateStyle()
    end
end)

--Create or destroy the rails to match the setting; restore pinned windows
--when they come up. Safe to call any time.
function EnsureIconRail()
    --OPT-IN trial: the rail (and everything riding it -- Views, doc
    --shortcuts, dock handoff) activates only for users who tick "New
    --Experimental UI" in Settings > General. (It was additionally
    --devmode-gated while the rail was a dev-only trial.)
    local enabled = RailModeActive()

    if not enabled then
        --don't strand rearrange mode across a disable/re-enable (the
        --setter is not used here: it would rebuild rails we are about
        --to destroy).
        g_railRearranging = false
        --toolkit strips ride the rail mode: they survive rail REBUILDS
        --(they are layer children), but the mode turning off takes them
        --with it.
        for tkid in pairs(g_railToolkitStrips) do
            HideToolkitStrip(tkid)
        end
        DestroyIconRails()
        --restore the docks' own handles and remove the dock-mounted
        --tray buttons.
        SyncDockHandles()
        RemoveDockTrayButtons()
        dmhub.UpdateScreenHudArea(1)
        return
    end

    --before anything reads the stored arrangement: rewrite entries left
    --behind by a panel rename (see g_railRenamedPanels). Runs on every
    --call and costs a handful of settings reads once it is clean.
    local renamed = RailMigrateRenamedPanels()

    local existing = g_iconRails.left
    if existing ~= nil and existing.valid then
        --rails already up: they were built from the pre-rename state, so
        --the repair has to reach the screen on its own. A window still
        --open under an old key references a document the repaired state
        --no longer points at, so it closes too.
        if renamed then
            local wanted = {}
            for oldKey in pairs(g_railRenamedPanels) do
                wanted[string.lower(oldKey)] = true
            end
            for k, doc in pairs(g_panelDocuments) do
                if wanted[string.lower(k)] then
                    local d = doc:try_get("_tmp_dialog")
                    if d ~= nil and d.valid then
                        RailForgetWindow(string.lower(k))
                        doc:ClosePanel()
                    end
                end
            end
            if RebuildIconRails ~= nil then
                RebuildIconRails()
            end
        end
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
        if child.valid and (child:HasClass("iconRail") or child:HasClass("iconRailGhost") or child:HasClass("iconRailGhostLine") or child:HasClass("iconRailCardGhost") or child:HasClass("iconRailTrash") or child:HasClass("iconRailViewChip") or child:HasClass("iconRailViewToast") or child:HasClass("iconRailToolkitStrip")) then
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
    RemoveDockTrayButtons()
    --recalculate the map's drawable area (see syncDockMode): fixes a
    --stale squeeze left from before the rail owned this.
    dmhub.UpdateScreenHudArea(1)

    --restore popped-out panels first: a panel living in its own OS
    --window must not also restore an in-app rail window below. Only
    --records stamped by THIS app run reopen -- that is what brings
    --popouts back after a Lua reload (the unload sweep destroys the
    --hosts; the records survive it) without windows from a previous
    --launch reappearing at startup; stale records are pruned.
    local session = PopoutSessionId()
    local popouts = DeepCopy(dmhub.GetSettingValue("popoutwindows") or {})
    for key, p in pairs(popouts) do
        if p.session ~= session then
            PopoutForgetWindow(key)
        elseif not PanelDocument.IsPoppedOut(key) then
            OpenPanelPopout(key, { x = p.x, y = p.y, width = p.width, height = p.height })
        end
    end

    --restore the recorded windows, plus any pinned panel that is not in
    --the record (a pinned window is always meant to be up).
    local restore = DeepCopy(RailRestoreWindows())
    for key in pairs(dmhub.GetSettingValue("iconrailpanelpinned") or {}) do
        if restore[key] == nil then
            restore[key] = {}
        end
    end
    for key, p in pairs(restore) do
        --a panel already restored into its own OS window above must not
        --also be opened as a rail window here.
        if PanelDocument.FindHostDialog(key) == nil and not PanelDocument.IsPoppedOut(key) then
            --come back on the tab the window was left on. A remembered
            --tab that has since been refiled into some OTHER folder is
            --ignored: opening it would restore that folder's window
            --instead of this one.
            local open = key
            if p.tab ~= nil and PanelDocument.WindowOwner(p.tab) == key then
                open = p.tab
            end
            OpenIconRailWindow(open, { x = p.x, y = p.y, width = p.width, height = p.height })
        end
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

        --A retired built-in (Map Maker, 2026-08-08) can still be named as
        --the active view in a game that used it. Its arrangement is
        --live on screen and is left exactly as it is -- but with no
        --definition behind it there is nothing to save to, reset to, or
        --check in the menu, which is precisely the Custom state. An
        --overlaid one survives on its own: ViewsListForUser re-reads a
        --library entry whose template is gone as an ordinary custom view.
        if rawget(_G, "ViewsActiveId") ~= nil then
            local activeId = ViewsActiveId()
            if activeId ~= nil and ViewsGetDefinition(activeId) == nil then
                dmhub.SetSettingValue("viewsactive", "")
            end
        end

        --Each role gets its built-in view applied on first entry:
        --switching views is an advanced feature, so the default is
        --chosen for them (Lisa+David review 2026-07-19 for players;
        --David 2026-08-08 extended it to Directors, whose default used
        --to be Custom). Only when the rail mode is on, no view is
        --active, and there is no evidence they have ever used views (an
        --empty per-game stash is the proxy -- Custom always stashes on
        --the first switch away from it) -- so it applies once, and never
        --tramples an arrangement they've built.
        if RailModeActive() and (dmhub.GetSettingValue("viewsactive") or "") == "" then
            local stash = dmhub.GetSettingValue("viewsstash")
            local stashEmpty = true
            if type(stash) == "table" then
                for _ in pairs(stash) do
                    stashEmpty = false
                    break
                end
            end
            if stashEmpty and rawget(_G, "ViewsSwitchTo") ~= nil then
                if dmhub.isDM then
                    ViewsSwitchTo("builtin:director")
                else
                    ViewsSwitchTo("builtin:player")
                end
            end
        end

        --Already on a built-in? Pick up any stock layout we have shipped
        --since it was applied. Runs after the block above so a view just
        --auto-applied is already stamped current and this no-ops.
        if RailModeActive() and rawget(_G, "ViewsCheckForBuiltinUpdateOnEntry") ~= nil then
            ViewsCheckForBuiltinUpdateOnEntry()
        end
    end)
end)

----------------------------------------------------------------------
-- Workspace Views
-- ---------------
-- Named saved workspace arrangements (rail sides/slots/blanks, pinned
-- windows with tabs, dock contents and visibility), switchable from a
-- chip on the left rail and the Panels menu. Built-ins: Director /
-- Player (code templates; a user's Save on a built-in stores a personal
-- overlay). Map Maker was retired 2026-08-08 -- its panels are a group
-- on the Director rail now. Design brief (LOCKED 2026-07-19):
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
--{ [key] = layoutPayload }. Written on every switch (A1), and dropped
--again the moment the stash matches the definition it came from -- see
--ViewsSwitchTo, which is what lets a shipped template update reach a
--user who never customized.
setting{
    id = "viewsstash",
    storage = "pergamepreference",
    default = {},
}

--What we last applied for a built-in view in this game:
--{ [builtinid] = { version = N, layout = <the payload applied> } }.
--The version answers "has a newer template shipped since?"; the layout
--is a baseline answering "has the user rearranged it since?" -- live
--rail drift is recorded nowhere else (the stash only captures on switch
--away), and without it the on-entry update could not tell an untouched
--old layout from an arrangement someone built by hand.
setting{
    id = "viewsbuiltinversion",
    storage = "pergamepreference",
    default = {},
}

--Built-in templates (Views brief D4: no pins, docks closed, both rails).
--Editable freely: these are the stock arrangements, iterated in-app.
--
--BUMP `version` WHENEVER YOU CHANGE A LAYOUT HERE. Users who never
--customized the view pick the change up silently; users who did (a
--personal overlay, or working drift stashed in a game) are offered it
--once, on their next switch to the view, and keep theirs if they
--decline. Without the bump neither group ever sees the new layout,
--because both the overlay and the stash are preferred over the template.
--Unversioned entries read as version 1, so the first release of this
--mechanism is a no-op for everyone already out there.
local g_viewBuiltins = {
    --One button per subject on the left rail, and every one of them a
    --GROUP: the owner wears the badge and its flyout reaches the rest,
    --so ten slots cover twenty-five panels. The right rail is left
    --deliberately empty (David 2026-08-08). Heroes has no entry: it is
    --not a registered panel any more (v3) -- the title bar's
    --connectivity panel hosts it as a popout. Group members need no
    --rail entry of their own; RailLayout reads membership from `tabs`.
    {
        id = "builtin:director",
        name = "Director",
        version = 6,
        dmonly = true,
        layout = {
            rail = {
                ["character"] = { side = "left", slot = 0 },
                --the two map-level groups sit directly under Character
                --(David 2026-08-08): what map you are on, then how it is
                --stacked and lit. Map *editing* stays down at "map
                --markup" -- these are about picking and framing a map,
                --not painting one.
                ["maps"] = { side = "left", slot = 1 },
                ["floors & layers"] = { side = "left", slot = 2 },
                ["bestiary"] = { side = "left", slot = 3 },
                ["journal"] = { side = "left", slot = 4 },
                ["dice"] = { side = "left", slot = 5 },
                ["measuring tool"] = { side = "left", slot = 6 },
                ["chat"] = { side = "left", slot = 7 },
                ["audio"] = { side = "left", slot = 8 },
                ["map markup"] = { side = "left", slot = 9 },
            },
            tabs = {
                ["character"] = { "character", "triggers", "downtime projects" },
                ["maps"] = { "maps", "map settings" },
                ["floors & layers"] = { "floors & layers", "time of day/lighting" },
                ["bestiary"] = { "bestiary", "encounters" },
                ["journal"] = { "journal", "campaign tracker" },
                ["dice"] = { "dice", "physical dice" },
                ["measuring tool"] = { "measuring tool", "whiteboard" },
                --every key here MUST be the full registered panel name:
                --a dead key orphans that panel from the group, and a
                --curated one then auto-places itself back onto the rail
                --at the bottom as a second button. "safety" was
                --"safety tools" until the panel was renamed -- stored
                --copies of the old key are repaired by
                --g_railRenamedPanels, so no version bump is needed for
                --this edit (see the rename block up there).
                ["chat"] = { "chat", "action log", "safety" },
                ["map markup"] = {
                    "map markup",
                    "building editor",
                    "terrain editor",
                    "effects editor",
                    "objects",
                    "editor settings",
                },
            },
            pins = {},
            docks = { left = {}, right = {} },
            leftDockOff = true,
            rightDockOff = true,
        },
    },
    --The Director rail with the Director-only panels taken out, same
    --items in the same order (David 2026-08-08). Three slots change:
    --Bestiary and Encounters are both dmonly, so that group goes
    --entirely; Map Settings is dmonly so Maps keeps its slot but loses
    --its group and rides alone; and Floors & Layers, Time of
    --Day/Lighting and every panel in the map-editing group are all
    --dmonly, so those two groups go too and the rail ends at Audio.
    --Heroes has no entry -- not a registered panel any more (v3), hosted
    --by the title bar's connectivity popout instead.
    --
    --v7: Encounters dropped. It shipped here at slot 2 because it was the
    --one director panel missing `dmonly`, so players read the director's
    --un-spawned encounter roster off their own rail (JA9XNYG3, 8B4CZRUA,
    --BUZ6SY69). The flag is on the registration now; this drops the empty
    --slot it would otherwise leave behind.
    {
        id = "builtin:player",
        name = "Player",
        version = 7,
        dmonly = false,
        layout = {
            rail = {
                ["character"] = { side = "left", slot = 0 },
                ["maps"] = { side = "left", slot = 1 },
                ["journal"] = { side = "left", slot = 2 },
                ["dice"] = { side = "left", slot = 3 },
                ["measuring tool"] = { side = "left", slot = 4 },
                ["chat"] = { side = "left", slot = 5 },
                ["audio"] = { side = "left", slot = 6 },
            },
            tabs = {
                ["character"] = { "character", "triggers", "downtime projects" },
                ["journal"] = { "journal", "campaign tracker" },
                ["dice"] = { "dice", "physical dice" },
                ["measuring tool"] = { "measuring tool", "whiteboard" },
                --every key here MUST be the full registered panel name:
                --a dead key orphans that panel from the group, and a
                --curated one then auto-places itself back onto the rail
                --at the bottom as a second button. "safety" was
                --"safety tools" until the panel was renamed -- stored
                --copies of the old key are repaired by
                --g_railRenamedPanels, so no version bump is needed for
                --this edit (see the rename block up there).
                ["chat"] = { "chat", "action log", "safety" },
            },
            pins = {},
            docks = { left = {}, right = {} },
            leftDockOff = true,
            rightDockOff = true,
        },
    },
}

--A missing table and an empty one mean the same thing in a layout
--payload: views written before `pinned`/`tabs` existed simply omit them,
--and the built-in templates omit every key they leave at the default.
--ViewsApplyLayout already reads them as empty (`layout.tabs or {}`), so
--comparison has to agree -- otherwise a stock built-in reports drifted
--the instant it is applied (capture always fills those keys in), which
--makes "unsaved changes" permanent and the pristine-stash rule below
--dead code.
local function ViewsEmptyish(v)
    return v == nil or (type(v) == "table" and next(v) == nil)
end

local function ViewsDeepEqual(a, b)
    if a == b then
        return true
    end
    if ViewsEmptyish(a) and ViewsEmptyish(b) then
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
    for k, v in pairs(b) do
        if a[k] == nil and not ViewsEmptyish(v) then
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

----------------------------------------------------------------------
-- Built-in template versioning
-- ---------------------------
-- Two layers shadow a built-in template, and both win over it forever:
-- the user's personal overlay (viewslibrary[id], A2) and this game's
-- working stash (viewsstash[id], A1). So shipping a new stock layout
-- reaches nobody who has ever touched the view. The reconciliation:
--   * no overlay and no stash -> the template applies as-is; nothing to
--     do. Un-customized users track every update silently.
--   * overlay or stash present -> it carries the version it was built
--     from. A newer template makes an update AVAILABLE, offered once per
--     shipped version on the next switch to the view (and from Manage),
--     never applied behind the user's back.
----------------------------------------------------------------------

--The version of the stock template (1 for entries written before
--versioning), or nil if `id` is not a built-in.
local function ViewsBuiltinVersion(id)
    local template = ViewsBuiltinTemplate(id)
    if template == nil then
        return nil
    end
    return template.version or 1
end

--The template version a built-in's resolved DEFINITION represents: an
--overlay carries its own stamp, the stock template the current one.
local function ViewsDefinitionVersion(id)
    if ViewsBuiltinTemplate(id) == nil then
        return nil
    end
    local entry = ViewsLibrary()[id]
    if entry ~= nil then
        return entry.builtinVersion or 1
    end
    return ViewsBuiltinVersion(id)
end

--What we last applied for `id`, or nil. Tolerates the bare-number shape
--the field briefly had before it carried a baseline layout too.
local function ViewsAppliedRecord(id)
    local rec = (dmhub.GetSettingValue("viewsbuiltinversion") or {})[id]
    if type(rec) == "number" then
        return { version = rec }
    end
    if type(rec) ~= "table" then
        return nil
    end
    return rec
end

--Record what we just put on screen for `id`: the version it came from
--and the payload itself, as the baseline for "untouched since". No-op
--for customs. Called wherever a definition is applied.
local function ViewsStampBuiltin(id, version, layout)
    version = version or ViewsDefinitionVersion(id)
    if version == nil then
        return
    end
    local stamps = DeepCopy(dmhub.GetSettingValue("viewsbuiltinversion") or {})
    stamps[id] = { version = version, layout = DeepCopy(layout) }
    dmhub.SetSettingValue("viewsbuiltinversion", stamps)
end

--The template version the user's material for `id` is based on, or nil
--when they have no material at all (pristine -- the template applies
--directly, so there is nothing to reconcile). The stash is checked
--first: it is what a switch would actually restore.
local function ViewsBuiltinSeenVersion(id)
    if ViewsBuiltinTemplate(id) == nil then
        return nil
    end
    local stash = dmhub.GetSettingValue("viewsstash") or {}
    if type(stash[id]) == "table" then
        local rec = ViewsAppliedRecord(id)
        return (rec ~= nil and rec.version) or 1
    end
    local entry = ViewsLibrary()[id]
    if entry ~= nil then
        return entry.builtinVersion or 1
    end
    return nil
end

--Whether a newer stock layout has shipped than the one this user's
--overlay/stash was built from.
function ViewsBuiltinUpdateAvailable(id)
    local version = ViewsBuiltinVersion(id)
    if version == nil then
        return false
    end
    local seen = ViewsBuiltinSeenVersion(id)
    return seen ~= nil and version > seen
end

--Take the new stock layout: the personal overlay and this game's stash
--both go (they are exactly what was shadowing it), and the view re-reads
--from the template. Applies live only when it is the active view --
--from Manage it just clears the way for the next switch. Returns the
--skipped-as-unavailable list when it applied, else nil.
function ViewsTakeBuiltinUpdate(id)
    local template = ViewsBuiltinTemplate(id)
    if template == nil then
        return nil
    end

    local lib = DeepCopy(ViewsLibrary())
    if lib[id] ~= nil then
        lib[id] = nil
        dmhub.SetSettingValue("viewslibrary", lib)
    end

    local stash = DeepCopy(dmhub.GetSettingValue("viewsstash") or {})
    if stash[id] ~= nil then
        stash[id] = nil
        dmhub.SetSettingValue("viewsstash", stash)
    end

    ViewsStampBuiltin(id, template.version or 1, template.layout)

    if ViewsActiveId() ~= id then
        return nil
    end
    return ViewsApplyLayout(DeepCopy(template.layout))
end

--Keep the user's own arrangement and stop offering this update: stamp
--their material as current, wherever it lives. The layout is untouched.
function ViewsDismissBuiltinUpdate(id)
    local version = ViewsBuiltinVersion(id)
    if version == nil then
        return false
    end
    --their arrangement stays exactly as it is, and becomes the baseline:
    --this is the version they decided to keep it against.
    ViewsStampBuiltin(id, version, ViewsCaptureLayout())
    local lib = DeepCopy(ViewsLibrary())
    if lib[id] ~= nil then
        lib[id].builtinVersion = version
        dmhub.SetSettingValue("viewslibrary", lib)
    end
    return true
end

--Called on entering a game. A shipped template update only ever reached
--people at the moment they SWITCHED to a view, so anyone parked on one
--never saw it -- this is the other door. It TAKES the update outright
--when nothing of the user's is at risk: no personal overlay, no stashed
--arrangement for this view, and the rail untouched since we last applied
--it. Undo on the toast covers the rest. Anything else raises the same
--take-it/keep-mine prompt a switch would, and changes nothing until
--answered. Returns true if the layout was replaced.
function ViewsCheckForBuiltinUpdateOnEntry()
    local id = ViewsActiveId()
    if id == nil then
        return false
    end
    local template = ViewsBuiltinTemplate(id)
    if template == nil then
        return false
    end
    local version = template.version or 1

    local rec = ViewsAppliedRecord(id)
    if rec ~= nil and rec.version ~= nil and rec.version >= version then
        return false
    end

    --no baseline recorded at all means this view was applied before we
    --started stamping; combined with no overlay and no stash, there is
    --no arrangement of theirs anywhere and the old template is simply
    --still on screen.
    local untouched = rec == nil
        or rec.layout == nil
        or ViewsDeepEqual(ViewsCaptureLayout(), rec.layout)
    local hasOverlay = ViewsLibrary()[id] ~= nil
    local hasStash = type((dmhub.GetSettingValue("viewsstash") or {})[id]) == "table"

    if hasOverlay or hasStash or (not untouched) then
        ViewsToast(string.format("%s has been updated", template.name), nil, {
            {
                text = "Use new layout",
                click = function()
                    ViewsTakeBuiltinUpdate(id)
                end,
            },
            {
                text = "Keep mine",
                click = function()
                    ViewsDismissBuiltinUpdate(id)
                end,
            },
        })
        return false
    end

    local previous = ViewsCaptureLayout()
    ViewsApplyLayout(DeepCopy(template.layout))
    ViewsStampBuiltin(id, version, template.layout)
    ViewsToast(string.format("%s updated to the latest layout", template.name), function()
        ViewsApplyLayout(previous)
    end)
    return true
end

--All views this user can see here, in display order: built-ins (role
--gated, D6) then customs by name.
function ViewsListForUser()
    local result = {}
    for _, b in ipairs(g_viewBuiltins) do
        if (not b.dmonly) or dmhub.isDM then
            result[#result + 1] = {
                id = b.id,
                name = b.name,
                builtin = true,
                updated = ViewsBuiltinUpdateAvailable(b.id),
            }
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
        --"pins" is the legacy key for the open-window record; "pinned" is
        --the newer locked-in-place set, and "tabs" the per-window tab
        --arrangements. Views written before those existed simply omit
        --them, and apply treats a missing table as empty.
        pins = DeepCopy(dmhub.GetSettingValue("iconrailpins") or {}),
        pinned = DeepCopy(dmhub.GetSettingValue("iconrailpanelpinned") or {}),
        tabs = DeepCopy(dmhub.GetSettingValue("iconrailtabs") or {}),
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
    local toolkitid = string.match(key, "^toolkit:(.+)$")
    if toolkitid ~= nil then
        local tk = (dmhub.GetSettingValue("iconrailtoolkits") or {})[toolkitid]
        if tk ~= nil then
            return nil
        end
        return { name = "a toolkit", reason = "deleted" }
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
    for key in pairs(layout.pinned or {}) do
        check(key)
    end
    --grouped members have no rail entry of their own, so without this
    --they would go unreported entirely -- and a view can put most of
    --its panels in groups (the Director built-in puts 13 of 21 there).
    for owner, tabs in pairs(layout.tabs or {}) do
        check(owner)
        for _, key in ipairs(tabs) do
            check(key)
        end
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

    --locked-in-place windows and folder groupings travel with the view.
    --Applied BEFORE the windows are opened below so restored windows
    --come up already pinned and the rail builds with the right folders.
    dmhub.SetSettingValue("iconrailpanelpinned", DeepCopy(layout.pinned or {}))
    dmhub.SetSettingValue("iconrailtabs", DeepCopy(layout.tabs or {}))
    --a pinned window is always meant to be up: fold any pin the record
    --doesn't already carry into it.
    for key in pairs(layout.pinned or {}) do
        if pins[key] == nil then
            pins[key] = {}
        end
    end

    --windows: close what the incoming layout doesn't record; reposition
    --survivors in place (A4); open what's newly recorded.
    g_railTransientKey = nil
    for key, doc in pairs(g_panelDocuments) do
        local dlg = doc:try_get("_tmp_dialog")
        if dlg ~= nil and dlg.valid then
            local pin = pins[key]
            --a panel the incoming view files under someone else no
            --longer hosts a window, whatever the record says.
            if pin == nil or PanelDocument.WindowOwner(key) ~= key then
                doc:ClosePanel()
            else
                dlg.x = pin.x or dlg.x
                dlg.y = pin.y or dlg.y
                --the view brought its own folder membership with it
                --(iconrailtabs, set above), so a surviving window's tab
                --set has to be reconciled against it.
                dlg:FireEventTree("refreshPanelTabs")
                dlg:FireEventTree("refreshPanelPinned")
                if pin.tab ~= nil and PanelDocument.WindowOwner(pin.tab) == key then
                    dlg:FireEventTree("selectPanelTab", pin.tab)
                end
            end
        end
    end
    for key, pin in pairs(pins) do
        if type(pin) == "table" then
            local doc = RailPanelDocument(key)
            if doc ~= nil and not doc:PresentDocumentOpen() then
                local open = key
                if pin.tab ~= nil and PanelDocument.WindowOwner(pin.tab) == key then
                    open = pin.tab
                end
                OpenIconRailWindow(open, { x = pin.x, y = pin.y, width = pin.width, height = pin.height })
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
        if stash[targetKey] == nil then
            --coming up from the definition: whatever version that
            --definition represents is what any stash written from here
            --on is based on, and the definition itself is the baseline.
            ViewsStampBuiltin(id, nil, def.layout)
        end
    else
        --Custom: restore the stashed pre-view arrangement; with no stash
        --there is nothing to restore -- keep the current arrangement.
        incomingLayout = stash[targetKey]
    end

    --The outgoing arrangement stashes so switching back restores it
    --(A1) -- but only when it actually differs from what its definition
    --would rebuild. A pristine stash restores nothing the definition
    --wouldn't, and it would pin the user to today's copy of a built-in
    --forever (the stash is preferred over the definition above), so no
    --shipped update could ever reach them. Custom has no definition, so
    --it always stashes.
    local outgoingDef = nil
    if currentKey ~= "custom" then
        outgoingDef = ViewsGetDefinition(currentKey)
    end
    local captured = ViewsCaptureLayout()
    if outgoingDef ~= nil and ViewsDeepEqual(captured, outgoingDef.layout) then
        stash[currentKey] = nil
    else
        stash[currentKey] = captured
    end
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
    --saving over a built-in makes this arrangement the user's: it is a
    --deliberate customization of the template as it stands today, so it
    --starts out current and is not offered an update until we ship a
    --newer one.
    if template ~= nil then
        entry.builtinVersion = ViewsBuiltinVersion(id)
        ViewsStampBuiltin(id, entry.builtinVersion, entry.layout)
    end
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
    ViewsStampBuiltin(id, nil, def.layout)
    return ViewsApplyLayout(DeepCopy(def.layout))
end

--Clear a built-in's personal overlay (Manage: "Reset to stock" -- A2).
function ViewsResetToStock(id)
    local template = ViewsBuiltinTemplate(id)
    if template == nil then
        return false
    end
    local lib = DeepCopy(ViewsLibrary())
    if lib[id] == nil then
        return false
    end
    lib[id] = nil
    dmhub.SetSettingValue("viewslibrary", lib)
    --the overlay was only half of what was shadowing the template: this
    --game's stash outranks it, so a reset that left the stash behind
    --would come straight back on the next switch.
    local stash = DeepCopy(dmhub.GetSettingValue("viewsstash") or {})
    if stash[id] ~= nil then
        stash[id] = nil
        dmhub.SetSettingValue("viewsstash", stash)
    end
    ViewsStampBuiltin(id, template.version or 1, template.layout)
    if ViewsActiveId() == id then
        ViewsApplyLayout(DeepCopy(template.layout))
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
--a few seconds. `actions` adds further verbs beside Undo, each
--{text=, click=} and each dismissing the toast -- the built-in-update
--prompt uses a pair of them. Global: the Panels-menu Views group uses
--it too.
function ViewsToast(text, undoFn, actions)
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
    local verbs = {}
    if undoFn ~= nil then
        verbs[#verbs + 1] = { text = "Undo", click = undoFn }
    end
    for _, a in ipairs(actions or {}) do
        verbs[#verbs + 1] = a
    end
    for _, verb in ipairs(verbs) do
        local fn = verb.click
        children[#children + 1] = gui.Label{
            classes = {"iconRailViewToastUndo"},
            text = verb.text,
            width = "auto",
            height = "auto",
            halign = "left",
            valign = "center",
            lmargin = 10,
            textWrap = false,
            click = function(element)
                if fn ~= nil then
                    fn()
                end
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
    local actions = nil

    --A shipped built-in update the user has not reconciled leads the
    --notice and carries the two verbs. Folded into the SAME toast as the
    --passive notices below rather than raised as a second one: they
    --occupy the same fixed spot on screen and would sit on top of each
    --other. Offered once per shipped version -- "Keep mine" stamps their
    --arrangement current, and Manage keeps the verb available either way.
    if id ~= nil and ViewsBuiltinUpdateAvailable(id) then
        local def = ViewsGetDefinition(id)
        local name = (def ~= nil and def.name) or "This view"
        parts[#parts + 1] = string.format("%s has been updated", name)
        actions = {
            {
                text = "Use new layout",
                click = function()
                    ViewsTakeBuiltinUpdate(id)
                    ViewsToast(string.format("%s reset to the latest layout", name))
                end,
            },
            {
                text = "Keep mine",
                click = function()
                    ViewsDismissBuiltinUpdate(id)
                end,
            },
        }
    end

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
        ViewsToast(table.concat(parts, "  -  "), nil, actions)
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
            local suffix = cond(hasOverlay, " (customized)", "")
            if v.updated then
                suffix = suffix .. " (update available)"
            end
            nameControl = gui.Label{
                text = v.name .. suffix,
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
            --the standing route to a shipped update, for anyone who let
            --the switch-time prompt time out unanswered. (An explicit
            --"Keep mine" stamps their copy current, which clears this
            --too; "Reset to stock" and "Reset view to saved" are the
            --ways back after that.)
            if v.updated then
                actionButtons[#actionButtons + 1] = gui.Button{
                    classes = {"sizeS"},
                    text = "Update to latest",
                    halign = "right",
                    valign = "center",
                    hmargin = 4,
                    click = function(element)
                        ViewsTakeBuiltinUpdate(vid)
                        gamehud:CloseModal()
                        ViewsManageDialog()
                    end,
                }
            end
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

