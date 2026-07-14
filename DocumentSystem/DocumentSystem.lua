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

function CustomDocument:GetTextContent()
    if (not self.textStorage) or not getmetatable(self.textStorage) then
        return self.content or ""
    end

    return self.textStorage:GetContent() or ""
end

function CustomDocument:SetTextContent(str)
    --self.content = nil

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
    if writePanel:HasClass("collapsed") then
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
        if not doc.hidden and doc.nodeType == "custom" and (dmhub.isDM or not doc.hiddenFromPlayers) then
            local pf = doc.parentFolder or "private"
            foldersToMembers[pf] = foldersToMembers[pf] or {}
            foldersToMembers[pf][k] = { type = "doc", id = k, description = doc.description or "Untitled" }
        end
    end
    --PDF books, same filter as the journal panel (hidden covers the
    --Patreon variants that share book names). Opened via OpenContent,
    --never navigated to in a viewer tab.
    for k, doc in pairs(assets.pdfDocumentsTable or {}) do
        if not doc.hidden then
            local pf = doc.parentFolder or "private"
            foldersToMembers[pf] = foldersToMembers[pf] or {}
            foldersToMembers[pf][k] = { type = "pdf", id = k, description = doc.description or "PDF", pdfDoc = doc }
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

    -- Build a single folder entry (row + collapsible children)
    local function buildFolderEntry(folderId, description, isExpanded, childrenPanels)
        local isCollapsed = not isExpanded

        local contentPanel = gui.Panel {
            width = "100%",
            height = "auto",
            flow = "vertical",
            lmargin = 16,
            classes = { cond(isCollapsed, "collapsed") },
            children = childrenPanels,
        }

        local arrow = gui.ExpandoArrow {
            classes = cond(not isCollapsed, {"expanded"}),
            halign = "left",
            valign = "center",
            lmargin = 4,
        }

        local folderRow = gui.Panel {
            width = "100%",
            height = 22,
            flow = "horizontal",
            halign = "left",
            valign = "center",
            bgimage = "panels/square.png",
            styles = ThemeEngine.MergeTokens({
                { bgcolor = "clear" },
                { selectors = {"hover"}, bgcolor = "@fgMuted" },
            }),
            press = function(element)
                isCollapsed = not isCollapsed
                contentPanel:SetClass("collapsed", isCollapsed)
                arrow:SetClass("expanded", not isCollapsed)
            end,

            arrow,
            gui.Label {
                classes = {"fgMuted"},
                text = description,
                fontSize = 12,
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                lmargin = 4,
                textWrap = false,
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
                children[#children + 1] = gui.Panel {
                    width = "100%",
                    height = 22,
                    flow = "horizontal",
                    halign = "left",
                    valign = "center",
                    bgimage = "panels/square.png",
                    classes = isCurrentDoc and {"currentDoc"} or {},
                    styles = ThemeEngine.MergeTokens({
                        { bgcolor = "clear" },
                        { selectors = {"currentDoc"}, bgcolor = "@bgAlt" },
                        { selectors = {"hover"}, bgcolor = "@fgMuted" },
                    }),
                    press = function(element)
                        if m_pickHandled then return end
                        --PDFs open in the PDF viewer in every context;
                        --they are never a viewer tab or a nav target.
                        if member.type == "pdf" then
                            m_pickHandled = true
                            element:ScheduleEvent("resetPickLatch", 0.1)
                            CustomDocument.OpenContent(member.pdfDoc)
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

                    gui.Panel {
                        bgimage = cond(member.type == "pdf",
                            "icons/icon_app/icon_app_137.png", "icons/icon_app/icon_app_107.png"),
                        bgcolor = cond(isCurrentDoc, "white", "#aaaaaa"),
                        width = 14,
                        height = 14,
                        halign = "left",
                        valign = "center",
                        lmargin = 4,
                    },
                    gui.Label {
                        text = member.description,
                        fontSize = 12,
                        color = cond(isCurrentDoc, "white", "#cccccc"),
                        bold = isCurrentDoc,
                        width = "auto",
                        height = "auto",
                        halign = "left",
                        valign = "center",
                        lmargin = 4,
                        textWrap = false,
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
                local expandThis = isAncestorOf(rootId, currentDocId)
                    or (customDocs[currentDocId] and (customDocs[currentDocId].parentFolder or "private") == rootId)
                rootChildren[#rootChildren + 1] = buildFolderEntry(rootId, root.description, expandThis, subChildren)
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
                width = "100%",
                height = 22,
                flow = "horizontal",
                halign = "left",
                valign = "center",
                bgimage = "panels/square.png",
                styles = ThemeEngine.MergeTokens({
                    { bgcolor = "clear" },
                    { selectors = {"hover"}, bgcolor = "@fgMuted" },
                }),
                press = function(element)
                    if m_pickHandled then return end
                    m_pickHandled = true
                    element:ScheduleEvent("resetPickLatch", 0.1)
                    opts.onNewDocument(v)
                end,
                resetPickLatch = function(element)
                    m_pickHandled = false
                end,
                gui.Panel {
                    bgimage = "icons/icon_app/icon_app_107.png",
                    bgcolor = "#aaaaaa",
                    width = 14,
                    height = 14,
                    halign = "left",
                    valign = "center",
                    lmargin = 4,
                },
                gui.Label {
                    text = v.text,
                    fontSize = 12,
                    color = "#cccccc",
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    valign = "center",
                    lmargin = 4,
                    textWrap = false,
                },
            }
        end

        headerPanels[#headerPanels + 1] = buildFolderEntry("newdocument", "New Document", false, typeRows)
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
            children = popupChildren,
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
                children = popupChildren,
            },
        },
    }
end

function CustomDocument:CreateInterface(args)

    local buttonSize = 20

    args = args or {}
    local readPanel = self:DisplayPanel{ relatedFooter = true }
    local writePanel = self:EditPanel(args)

    writePanel:SetClass("collapsed", true)

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

        writePanel:FireEventTree("checkChanges", resultPanel.data.pendingOriginal)
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
                if not writePanel:HasClass("collapsed") then
                    resultPanel:FireEventTree("savedoc")
                    if not dmhub.DeepEqual(self, resultPanel.data.original) then
                        self:Upload(resultPanel.data.original)
                    end
                else
                    resultPanel.data.original = DeepCopy(self)
                    resultPanel.data.pendingOriginal = nil
                    resultPanel.data.pendingUpload = nil
                end
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
                writePanel:FireEventTree("checkChanges", resultPanel.data.pendingOriginal or resultPanel.data.original)
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
        {
            selectors = { "iconButton", "selected" },
            bgcolor = "#ffffff1f",
            borderColor = "#ffffff99",
        },
        {
            selectors = { "iconButton", "selected", "hover" },
            bgcolor = "#ffffff59",
            borderColor = "#ffffff99",
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
        classes = {"surfaceLinear"},
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#0d0d0d",
        styles = ThemeEngine.MergeTokens(dsTopBarStyles),

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
            if resultPanel.data.firstEditTime ~= nil and not writePanel:HasClass("collapsed") then
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

        gui.Panel {
            width = "100%-24",
            height = "100% available",
            vscroll = self.vscroll,
            halign = "center",
            bmargin = 8,
            writePanel,
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
        },
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

    local treeToggleIcon = gui.Panel {
        bgimage = "icons/standard/Icon_App_Journal.png",
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
    local treeRailScroll = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",
        vscroll = true,
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
            if not element.data.treeDirty and element.data.builtForDocId == currentDocId then
                return
            end
            element.data.treeDirty = false
            element.data.builtForDocId = currentDocId

            local tree = buildJournalTree(currentDocId, nil, {
                bare = true,
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
            })
            treeRailScroll.children = { tree }
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

    local function replaceTabContent(activeTab, newDoc, navArgs)
        activeTab.contentPanel:DestroySelf()
        activeTab.contentPanel = newDoc:CreateInterface(navArgs)
        contentArea:AddChild(activeTab.contentPanel)
    end

    -- Build a tab's content panel on demand. No-op if already realized.
    -- tabData.tabArgs is the full args table captured at addTab time (dialog,
    -- close, bubbleIcon, etc), so the lazily-built panel is identical to the
    -- one addTab used to build eagerly. switchToTab calls this on activation
    -- so opening the journal only builds the tab the user actually lands on.
    local function realizeTab(tabData)
        if tabData.contentPanel ~= nil then return end
        local docs = dmhub.GetTable(CustomDocument.tableName) or {}
        -- Prefer the most up-to-date table copy, but fall back to the in-memory
        -- doc captured at addTab time. Transient docs (e.g. an item/spell link
        -- wrapped via MarkdownRender.RenderToMarkdown) are never written to the
        -- table, so a table-only lookup would render a blank tab for them.
        local doc = docs[tabData.docId] or tabData.doc
        if doc == nil then return end

        local contentPanel = doc:CreateInterface(tabData.tabArgs)
        contentPanel:SetClass("collapsed", true)  -- switchToTab un-collapses the active one
        tabData.contentPanel = contentPanel
        contentArea:AddChild(contentPanel)
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
        end,

        data = {
            tabs = {},
            activeTabId = nil,
            nextTabId = 1,
            scrollOffset = 0,
            history = {},
            forwardHistory = {},
        },

        addTab = function(element, doc, args)
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

        gui.DialogResizePanel({}, dialogWidth, dialogHeight),

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

function CustomDocument:PresentDocument(args)
    args = args or {}

    local dialogWidth = 1100
    local dialogHeight = 940

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
