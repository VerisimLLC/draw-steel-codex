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

-- Tab system colors
local TAB_RICH_BLACK = "#040807"
local TAB_CREAM = "#FFFEF8"
local TAB_ACTIVE_BG = "#191A18"
local TAB_INACTIVE_BG = "#10110F"
local TAB_GOLD = "#966D4B"
local TAB_REMOVE_RED = "#D53031"
local TAB_REMOVE_BG = "#241c1a"

-- Tab system sizes
local TAB_HEIGHT = 18
local TAB_MAX_WIDTH = 200
local TAB_FONT_SIZE = 12
local TAB_CLOSE_SIZE = 16
local TAB_CLOSE_FONT = 10
local TAB_BAR_HEIGHT = TAB_HEIGHT + 6
local TAB_ARROW_WIDTH = 20

local JournalTabStyles = {
    {
        selectors = {"panel", "journalTabBar"},
        bgimage = true,
        bgcolor = TAB_RICH_BLACK,
        height = TAB_BAR_HEIGHT,
        width = "100%-70",
        flow = "horizontal",
        halign = "left",
        valign = "top",
        borderColor = TAB_GOLD,
        border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 },
    },
    {
        selectors = {"panel", "journalTab"},
        bgimage = true,
        bgcolor = TAB_INACTIVE_BG,
        height = TAB_HEIGHT,
        width = "auto",
        maxWidth = TAB_MAX_WIDTH,
        flow = "horizontal",
        halign = "left",
        valign = "bottom",
        hpad = 8,
        vpad = 4,
        cornerRadius = { x1 = 4, y1 = 4, x2 = 0, y2 = 0 },
        border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 },
        borderColor = TAB_GOLD,
    },
    {
        selectors = {"panel", "journalTab", "hover"},
        brightness = 1.3,
        transitionTime = 0.15,
    },
    {
        selectors = {"panel", "journalTab", "selected"},
        bgcolor = TAB_ACTIVE_BG,
        brightness = 1,
        border = { x1 = 1, y1 = 0, x2 = 1, y2 = 1 },
        borderColor = TAB_GOLD,
    },
    {
        selectors = {"label", "journalTabLabel"},
        width = "auto",
        height = "auto",
        fontSize = TAB_FONT_SIZE,
        color = TAB_CREAM,
        valign = "center",
        textWrap = false,
        textOverflow = "ellipsis",
        maxWidth = TAB_MAX_WIDTH - 40,
        rmargin = 6,
    },
    {
        selectors = {"panel", "journalTabClose"},
        width = TAB_CLOSE_SIZE,
        height = TAB_CLOSE_SIZE,
        halign = "right",
        valign = "center",
        bgimage = true,
        bgcolor = TAB_REMOVE_BG,
        border = 1,
        borderColor = TAB_REMOVE_RED,
        cornerRadius = 2,
    },
    {
        selectors = {"panel", "journalTabClose", "hover"},
        brightness = 1.5,
    },
    {
        selectors = {"label", "journalTabCloseLabel"},
        width = "100%",
        height = "100%",
        halign = "center",
        valign = "center",
        textAlignment = "center",
        fontSize = TAB_CLOSE_FONT,
        color = TAB_REMOVE_RED,
    },
    -- Tab scroll arrows
    {
        selectors = {"journalTabArrow"},
        height = TAB_BAR_HEIGHT,
        width = TAB_ARROW_WIDTH,
        valign = "center",
    },
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
    print("TYPE:: DESERIALIZE", self.textStorage)
    if self.textStorage and not getmetatable(self.textStorage) then
        self.textStorage = nil
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
    local editInput = gui.Input {
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
        reversed[#reversed + 1] = parts[i]
    end
    reversed[#reversed + 1] = "**" .. (doc.description or "Untitled") .. "**"
    return table.concat(reversed, " > ")
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
--- @return Panel The popup panel
local function buildJournalTree(currentDocId, dialogPanel)
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

    -- Build foldersToMembers map (folders + custom docs only)
    local foldersToMembers = {}
    local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
    for k, doc in pairs(customDocs) do
        if not doc.hidden and (dmhub.isDM or not doc.hiddenFromPlayers) then
            local pf = doc.parentFolder or "private"
            foldersToMembers[pf] = foldersToMembers[pf] or {}
            foldersToMembers[pf][k] = { type = "doc", id = k, description = doc.description or "Untitled" }
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

        local arrow = gui.CollapseArrow {
            classes = { cond(isCollapsed, "collapseSet") },
            width = 10,
            height = 10,
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
            styles = {
                { bgcolor = "clear" },
                { selectors = {"hover"}, bgcolor = "#ffffff44" },
            },
            press = function(element)
                isCollapsed = not isCollapsed
                contentPanel:SetClass("collapsed", isCollapsed)
                arrow:SetClass("collapseSet", isCollapsed)
            end,

            arrow,
            gui.Label {
                text = description,
                fontSize = 12,
                color = "#cccccc",
                width = "auto",
                height = "auto",
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
            if a.type ~= b.type then return a.type == "folder" end
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
                    styles = {
                        { bgcolor = cond(isCurrentDoc, "#ffffff22", "clear") },
                        { selectors = {"hover"}, bgcolor = "#ffffff44" },
                    },
                    press = function(element)
                        if member.id == currentDocId then return end
                        if dialogPanel and dialogPanel.data then
                            dialogPanel:FireEvent("navigateToDocument", member.id)
                        end
                    end,

                    gui.Panel {
                        bgimage = "icons/icon_app/icon_app_107.png",
                        bgcolor = cond(isCurrentDoc, "white", "#aaaaaa"),
                        width = 14,
                        height = 14,
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

    if #rootChildren == 0 then
        return nil
    end

    return gui.Panel {
        width = 0,
        height = 0,
        halign = "left",
        valign = "bottom",

        gui.Panel {
            styles = {Styles.Default},
            classes = {"journalTreePopup"},
            bgimage = "panels/square.png",
            bgcolor = "#1a1a1a",
            border = 1,
            borderColor = "#555555",
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
                children = rootChildren,
            },
        },
    }
end

function CustomDocument:CreateInterface(args)

    local buttonSize = 20

    args = args or {}
    local readPanel = self:DisplayPanel()
    local writePanel = self:EditPanel(args)

    writePanel:SetClass("collapsed", true)

    local m_presentButton
    local m_playerPreviewButton

    local m_titlePanel = args.titlePanel or gui.Panel {
        classes = {cond(self:HaveEditPermissions(), "", "collapsed")},
        halign = "right",
        valign = "center",
        width = "auto",
        height = "auto",
        flow = "horizontal",
        rmargin = 4,
        gui.Label {
            text = "Document Name:",
            fontSize = 16,
            fontFace = "Berling",
            color = "#999999",
            width = "auto",
            height = "auto",
            valign = "center",
            rmargin = 12,
            lmargin = 12,
        },
        gui.Input {
            text = self.description,
            fontSize = 14,
            width = 200,
            height = 18,
            valign = "center",
            characterLimit = 48,
            editable = self:HaveEditPermissions(),
            editlag = 1.0,
            border = {x1 = 1, y1 = 1, x2 = 0, y2 = 0},
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



    if dmhub.isDM then --and not args.presentationMode then
        m_presentButton = gui.SimpleIconButton {
            escapeActivates = false,
            width = buttonSize,
            height = buttonSize,
            bgimage = "icons/icon_app/icon_app_34.png",
            thinkTime = 0.2,
            think = function(element)
                local presentedDialog = GameHud.instance.GetCurrentlyPresentedDialog()
                if presentedDialog ~= nil and presentedDialog.dialog == "document" and presentedDialog.args.docid == self.id then
                    element:SetClass("active", true)
                else
                    element:SetClass("active", false)
                end
            end,
            press = function(element)
                if element:HasClass("active") then
                    GameHud.HidePresentedDialog()
                else
                    --make it so just closing out of present mode doesn't close the dialog for us.
                    element.parent.data.persistAfterPresentation = true
                    GameHud.PresentDialogToUsers(element.parent, "document", { docid = self.id })
                end
            end,
            destroy = function(element)
                --make sure when we close this dialog we stop it being presented.
                if element:HasClass("active") then
                    GameHud.HidePresentedDialog()
                end
            end,
            hover = function(element)
                gui.Tooltip("Present to Players")(element)
            end,
        }
    end



    if self:HaveEditPermissions() and not args.presentationMode then
        m_playerPreviewButton = gui.SimpleIconButton {
            escapeActivates = false,
            width = buttonSize,
            height = buttonSize,
            bgimage = "icons/icon_game/icon_game_193.png",
            press = function(element)
                if m_editingButton ~= nil and m_editingButton:HasClass("active") then
                    --if we are editing, stop editing.
                    m_editingButton:FireEvent("press")
                end
                resultPanel:SetClass("playerPreview", not resultPanel:HasClass("playerPreview"))
                element:SetClass("playerPreview", resultPanel:HasClass("playerPreview"))
                resultPanel:SetClass("active", not resultPanel:HasClass("active"))
                element:SetClass("active", resultPanel:HasClass("active"))
                resultPanel:FireEventTree("refreshDocument")
            end,
            hover = function(element)
                gui.Tooltip("Preview as Player")(element)
            end,
        }

        --editing button.
        m_editingButton = gui.SimpleIconButton {
            escapeActivates = false,
            width = buttonSize,
            height = buttonSize,
            hmargin = 0,
            bgimage = "icons/icon_tool/icon_tool_79.png",
            press = function(element)
                if not writePanel:HasClass("collapsed") then
                    resultPanel:FireEventTree("savedoc")
                    if not dmhub.DeepEqual(self, resultPanel.data.original) then
                        self:Upload(resultPanel.data.original)
                    end
                else
                    resultPanel.data.original = DeepCopy(self)
                end
                writePanel:SetClass("collapsed", not writePanel:HasClass("collapsed"))
                readPanel:SetClass("collapsed", not readPanel:HasClass("collapsed"))
                element:SetClass("active", not writePanel:HasClass("collapsed"))

                element.thinkTime = cond(element:HasClass("active"), 1)
            end,

            think = function(element)
                writePanel:FireEventTree("checkChanges", resultPanel.data.original)
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
    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.SimpleIconButton {
        escapeActivates = false,
        width = buttonSize,
        height = buttonSize,
        bgimage = "icons/icon_arrow/icon_arrow_28.png",
        rotate = 180,
        bgcolor = "#666666",
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
            element.selfStyle.bgcolor = hasHistory and "white" or "#666666"
        end,
    }

    -- Forward button
    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.SimpleIconButton {
        escapeActivates = false,
        width = buttonSize,
        height = buttonSize,
        bgimage = "icons/icon_arrow/icon_arrow_28.png",
        bgcolor = "#666666",
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
            element.selfStyle.bgcolor = hasForward and "white" or "#666666"
        end,
    }

    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.SimpleIconButton {
        escapeActivates = false,
        width = buttonSize,
        height = buttonSize,
        bgimage = "icons/icon_tool/icon_tool_41.png",
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

    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.SimpleIconButton {
        escapeActivates = false,
        width = buttonSize,
        height = buttonSize,
        bgimage = "icons/icon_tool/icon_tool_40.png",
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

    if not args.presentationMode then
        m_controlMenuButtons[#m_controlMenuButtons + 1] = m_playerPreviewButton
    end

    m_controlMenuButtons[#m_controlMenuButtons + 1] = m_presentButton

    if not args.presentationMode then
        if self:HaveEditPermissions() then
            m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.SimpleIconButton {
                escapeActivates = false,
                width = buttonSize,
                height = buttonSize,
                bgimage = "ui-icons/icon-scale.png",
                press = function(element)
                    if resultPanel.data.watcher ~= nil then
                        resultPanel.data.watcher:Destroy()
                        resultPanel.data.watcher = nil
                        element:SetClass("active", resultPanel.data.watcher ~= nil)
                        return
                    end
                    resultPanel.data.watcherContent = self:GetTextContent()
                    resultPanel.data.watcher = dmhub.OpenTextFileInConnectedEditor(self.description, self:GetTextContent(),
                        function(contents)
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
                    element:SetClass("active", resultPanel.data.watcher ~= nil)
                end,
                hover = function(element)
                    gui.Tooltip("Edit in External Editor")(element)
                end,
            }
        end

        m_controlMenuButtons[#m_controlMenuButtons + 1] = m_editingButton
    end

    m_controlMenuButtons[#m_controlMenuButtons + 1] = m_titlePanel

    local m_closeButton = gui.CloseButton {
        classes = { cond(args.suppressCloseButton or args.presentationMode or (args.dialog == nil and args.close == nil), "collapsed") },
        width = buttonSize,
        height = buttonSize,
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
        text = buildBreadcrumbText(self),
        halign = "left",
        valign = "center",
        width = "auto",
        maxWidth = "60%",
        height = "auto",
        fontSize = 16,
        markdown = true,
        color = "#999999",
        lmargin = 8,
        textOverflow = "ellipsis",
        textWrap = false,
        styles = {
            { color = "#999999" },
            { selectors = {"hover"}, color = "#ffffff" },
        },
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

    local m_searchInput = gui.SearchInput {
        width = 200,
        height = 16,
        halign = "right",
        valign = "center",
        fontSize = 12,
        rmargin = 4,
        border = 0,
        bgcolor = "clear",
        placeholderText = "Search journal...",
        popupPositioning = "panel",
        search = function(element, text)
            if text == nil or text == "" then
                element.popup = nil
                return
            end

            local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
            local accessibleRoots = CustomDocument.GetAccessibleRoots()
            local results = {}
            for docId, doc in pairs(customDocs) do
                if not doc.hidden and (dmhub.isDM or not doc.hiddenFromPlayers) and CustomDocument.IsDocInAccessibleRoot(doc, accessibleRoots) then
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
                            text = string.format("<b>%s</b>", name),
                            score = score,
                            click = function()
                                element.popup = nil
                                element.text = ""
                                if args.dialogPanel and args.dialogPanel.data then
                                    args.dialogPanel:FireEvent("navigateToDocument", docId)
                                end
                            end,
                        }
                    end
                end
            end

            table.stable_sort(results, function(a, b) return a.score > b.score end)
            while #results > 10 do
                table.remove(results)
            end

            if #results == 0 then
                element.popup = gui.Label {
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "bottom",
                    fontSize = 14,
                    bgimage = true,
                    bgcolor = "black",
                    pad = 8,
                    text = "No results found",
                }
                return
            end

            element.popup = gui.Panel {
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "bottom",
                flow = "vertical",
                gui.ContextMenu {
                    width = 300,
                    valign = "bottom",
                    entries = results,
                    click = function()
                        element.popup = nil
                    end,
                },
            }
        end,
    }

    local m_topBar = gui.Panel {
        bgimage = true,
        bgcolor = Styles.RichBlack02,
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        flow = "vertical",
        cornerRadius = { x1 = 4, y1 = 4, x2 = 0, y2 = 0 },

        -- Row 1: breadcrumb + search + close
        gui.Panel {
            width = "100%",
            height = 24,
            flow = "horizontal",

            m_breadcrumb,
            m_searchInput,
            m_closeButton,
        },

        -- Row 2: tool buttons + document name
        gui.Panel {
            width = "auto",
            height = 28,
            flow = "horizontal",
            halign = "left",
            valign = "center",
            hmargin = 2,
            children = m_controlMenuButtons,
        },
    }

    local monitorGame = nil
    if not self.readonly then
        monitorGame = "/assets/objectTables/documents/table/" .. self.id
    end

    resultPanel = gui.Panel {
        classes = {"documentPanel"},
        styles = {
            Styles.Default,
            {
                selectors = { "iconButton", "active" },
                brightness = 2,
                priority = 20,
                bgcolor = "yellow",
            },
        },
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

            if writePanel ~= nil and not writePanel:HasClass("collapsed") then

                if resultPanel.data.pendingUpload ~= nil and doc.updateid == resultPanel.data.pendingUpload then
                    --we got a confirmation of our save going through.
                    resultPanel.data.saveConfirmed = true
                    element:FireEventTree("saveConfirmed")
                end

                --if we are editing, don't refresh the document.
                return
            end

            element:FireEventTree("refreshDocument", doc)
        end,

        saveDocument = function(element)
            resultPanel:FireEventTree("savedoc")
            if not dmhub.DeepEqual(self, resultPanel.data.original) then
                --our original is different, or we are the same object upload.

                resultPanel.data.pendingUpload = self:Upload(resultPanel.data.original)
                resultPanel.data.original = DeepCopy(self)
                writePanel:FireEventTree("checkChanges", resultPanel.data.original)
            end
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
                local newReadPanel = self:DisplayPanel()
                newReadPanel:SetClass("collapsed", readPanel:HasClass("collapsed"))
                readPanel = newReadPanel

                local children = element.children
                children[#children] = newReadPanel
                element.children = children
            end,
        },
    }

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

local function CreateTabButton(doc, tabbedViewer)
    local tabButton
    tabButton = gui.Panel {
        classes = {"panel", "journalTab"},
        data = { docId = doc.id },
        press = function(element)
            tabbedViewer:FireEvent("switchToTab", element.data.docId)
        end,

        gui.Label {
            classes = {"label", "journalTabLabel"},
            text = doc.description or "Untitled",
            refreshTabTitle = function(element, docId, newTitle)
                if docId == tabButton.data.docId then
                    element.text = newTitle
                end
            end,
        },

        gui.Panel {
            classes = {"panel", "journalTabClose"},
            press = function(element)
                tabbedViewer:FireEvent("closeTab", tabButton.data.docId)
            end,
            gui.Label {
                classes = {"label", "journalTabCloseLabel"},
                text = "X",
            },
        },
    }
    return tabButton
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

    local tabScrollLeft = gui.PagingArrow {
        facing = -1,
        height = TAB_BAR_HEIGHT / 2,
        valign = "center",
        halign = "right",
        press = function(element)
            local v = element:FindParentWithClass("journalTabbedViewer")
            local tabs = v.data.tabs
            for i, tab in ipairs(tabs) do
                if tab.docId == v.data.activeDocId and i > 1 then
                    v:FireEvent("switchToTab", tabs[i - 1].docId)
                    break
                end
            end
        end,
    }

    local tabScrollRight = gui.PagingArrow {
        facing = 1,
        height = TAB_BAR_HEIGHT / 2,
        valign = "center",
        halign = "right",
        hmargin = 8,
        press = function(element)
            local v = element:FindParentWithClass("journalTabbedViewer")
            local tabs = v.data.tabs
            for i, tab in ipairs(tabs) do
                if tab.docId == v.data.activeDocId and i < #tabs then
                    v:FireEvent("switchToTab", tabs[i + 1].docId)
                    break
                end
            end
        end,
    }

    local tabButtonsPanel = gui.Panel {
        classes = {"panel", "journalTabBar"},
    }

    local tabArrowsPanel = gui.Panel {
        width = 60,
        height = TAB_BAR_HEIGHT,
        halign = "right",
        flow = "horizontal",
        tabScrollLeft,
        tabScrollRight,
    }

    local tabBar = gui.Panel {
        width = "100%",
        height = TAB_BAR_HEIGHT,
        flow = "horizontal",
        bgimage = true,
        bgcolor = TAB_RICH_BLACK,
        borderColor = TAB_GOLD,
        border = { x1 = 0, y1 = 1, x2 = 0, y2 = 0 },
        tabButtonsPanel,
        tabArrowsPanel,
    }

    refreshTabVisibility = function(element)
        local tabs = element.data.tabs
        local offset = element.data.scrollOffset
        local panelWidth = tabButtonsPanel.renderedWidth or (dialogWidth - 60)

        -- Find active tab index
        local activeIdx = 0
        for i, tab in ipairs(tabs) do
            if tab.docId == element.data.activeDocId then
                activeIdx = i
                break
            end
        end

        -- Compute how many tabs fit starting from a given offset
        local function countVisible(fromOffset)
            local count = 0
            local used = 0
            for i = fromOffset + 1, #tabs do
                local w = tabs[i].tabButton.renderedWidth or TAB_MAX_WIDTH
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

        tabScrollLeft:SetClass("hidden", activeIdx <= 1)
        tabScrollRight:SetClass("hidden", activeIdx >= #tabs or #tabs <= 1)

        element.data.visibleCount = visibleCount
    end

    local contentArea = gui.Panel {
        classes = {"journalTabContent"},
        width = "100%",
        height = "100% available",
        halign = "center",
        valign = "top",
    }

    local innerPanel = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",
        tabBar,
        contentArea,
    }

    local viewer

    local function findActiveTab(element)
        for _, tab in ipairs(element.data.tabs) do
            if tab.docId == element.data.activeDocId then
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

    local viewerStyles = {
        Styles.Panel,
        gui.Style {
            classes = {"framedPanel"},
            priority = 5,
            opacity = 0.98,
            borderWidth = 0,
            borderColor = "clear",
        },
        gui.Style {
            classes = {"framedPanel", "~uiblur"},
            priority = 5,
            opacity = 1,
        },
    }
    for _, s in ipairs(JournalTabStyles) do
        viewerStyles[#viewerStyles + 1] = s
    end

    viewer = gui.Panel {
        styles = viewerStyles,
        classes = {"framedPanel", "journalViewer", "journalTabbedViewer"},
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
        end,
        click = function(element)
            element:SetAsLastSibling()
        end,

        captureEscape = true,
        escapePriority = EscapePriority.EXIT_DIALOG,
        escape = function(element)
            if element.data.activeDocId then
                element:FireEvent("closeTab", element.data.activeDocId)
            end
        end,

        data = {
            tabs = {},
            activeDocId = nil,
            scrollOffset = 0,
            history = {},
            forwardHistory = {},
        },

        addTab = function(element, doc, args)
            for _, tab in ipairs(element.data.tabs) do
                if tab.docId == doc.id then
                    element:FireEvent("switchToTab", doc.id)
                    return
                end
            end

            local tabArgs = DeepCopy(args) or {}
            tabArgs.dialog = viewer
            tabArgs.dialogPanel = viewer
            tabArgs.suppressCloseButton = true

            local tabData = {
                docId = doc.id,
                history = {},
                forwardHistory = {},
            }

            tabArgs.close = function()
                local idx = nil
                for i, t in ipairs(element.data.tabs) do
                    if t.docId == tabData.docId then
                        idx = i
                        break
                    end
                end
                if idx == nil then return end

                tabData.tabButton:DestroySelf()
                tabData.contentPanel:DestroySelf()
                table.remove(element.data.tabs, idx)

                if #element.data.tabs == 0 then
                    viewer:DestroySelf()
                    g_tabbedViewer = nil
                    return
                end

                if element.data.activeDocId == tabData.docId then
                    local newIndex = math.min(idx, #element.data.tabs)
                    element:FireEvent("switchToTab", element.data.tabs[newIndex].docId)
                else
                    refreshTabVisibility(element)
                end
            end
            tabData.close = tabArgs.close

            local contentPanel = doc:CreateInterface(tabArgs)
            contentPanel:SetClass("collapsed", true)

            local tabButton = CreateTabButton(doc, viewer)

            tabData.tabButton = tabButton
            tabData.contentPanel = contentPanel
            element.data.tabs[#element.data.tabs + 1] = tabData

            tabButtonsPanel:AddChild(tabButton)
            contentArea:AddChild(contentPanel)

            refreshTabVisibility(element)
            element:FireEvent("switchToTab", doc.id)
        end,

        switchToTab = function(element, docId)
            element.data.activeDocId = docId
            for _, tab in ipairs(element.data.tabs) do
                tab.contentPanel:SetClass("collapsed", tab.docId ~= docId)
                tab.tabButton:SetClass("selected", tab.docId == docId)
            end
            refreshTabVisibility(element)
            syncNavState(element)
            element:FireEventTree("refreshNavButtons")
        end,

        closeTab = function(element, docId)
            for _, tab in ipairs(element.data.tabs) do
                if tab.docId == docId then
                    tab.contentPanel:FireEvent("closetab")
                    return
                end
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
            element.data.activeDocId = docId

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
            element.data.activeDocId = prevDocId

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
            element.data.activeDocId = nextDocId

            syncNavState(element)
            element:FireEventTree("refreshNavButtons")
        end,

        DialogResizePanel(nil, dialogWidth, dialogHeight),

        innerPanel,
    }

    g_tabbedViewer = viewer
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

    dialog = gui.Panel {
        styles = {
            Styles.Panel,
            gui.Style {
                classes = { "framedPanel" },
                priority = 5,
                opacity = 0.98,
                borderWidth = 0,
                borderColor = "clear",
            },
            gui.Style {
                classes = { "framedPanel", "~uiblur" },
                priority = 5,
                opacity = 1,
            },
        },
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
