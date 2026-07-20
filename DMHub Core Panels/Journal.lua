local mod = dmhub.GetModLoading()

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

local CreateJournalPanel

local docid = "journal"

RegisterGameType("CustomDocument")

Commands.RegisterMacro{
    name = "doc",
    summary = "open a document",
    doc = "Usage: /doc <document ID> [page]\nOpens the given document (PDF or custom document) by ID.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {}
        local docs = dmhub.GetTable("documents")
        for k, v in unhidden_pairs(docs) do
            result[#result+1] = {text = k, summary = v.name or k}
        end
        table.sort(result, function(a, b) return a.summary < b.summary end)
        return result
    end,
    command = function(str)
        local args = str:split(" ")

        if #args == 0 then
            print("Provide document as argument.")
            return
        end

        local doc = assets.pdfDocumentsTable[args[1]]
        if doc == nil then
            local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[args[1]]
            if doc ~= nil then
                CustomDocument.OpenContent(doc)
                return
            end
            print("Document not found.")
            return
        end

        local page = tonumber(args[2])

        mod.shared.ShowPDFViewerDialog(doc, page)
    end,
}

Commands.RegisterMacro{
    name = "glossary",
    summary = "show a glossary definition",
    doc = "Usage: /glossary <term>\nShows the glossary definition for a rules term.",
    completions = function(args, argIndex)
        if argIndex ~= 1 then return {} end
        local result = {}
        for _, term in unhidden_pairs(dmhub.GetTable("glossaryTerms") or {}) do
            result[#result+1] = { text = term.name or "", summary = string.sub(term.definition or "", 1, 60) }
        end
        table.sort(result, function(a, b) return a.text < b.text end)
        return result
    end,
    command = function(str)
        local query = string.lower(trim(str or ""))
        if query == "" then
            print("Usage: /glossary <term>")
            return
        end
        local best = nil
        for _, term in unhidden_pairs(dmhub.GetTable("glossaryTerms") or {}) do
            local name = string.lower(term.name or "")
            if name == query then
                best = term
                break
            elseif best == nil and string.starts_with(name, query) then
                best = term
            end
        end
        if best == nil then
            print("No glossary entry found for '" .. str .. "'.")
            return
        end

        local card = MarkdownDocument.CreateGlossaryCard(best, {
            pinned = true,
            close = function()
                gui.CloseModal()
            end,
        })
        card.selfStyle.halign = "left"
        card.selfStyle.valign = "top"
        --hidden until placed at the cursor (below), so it never flashes at
        --the default position.
        card.selfStyle.opacity = 0

        --full-screen wrapper: places the card at the mouse position once
        --layout has run, and closes on click-away or escape.
        gui.ShowModal(gui.Panel{
            styles = ThemeEngine.GetStyles(),
            width = "100%",
            height = "100%",
            bgimage = "panels/square.png",
            bgcolor = "#00000000",
            captureEscape = true,
            escapePriority = EscapePriority.DMHUB_POPUP,
            escape = function(element)
                gui.CloseModal()
            end,
            press = function(element)
                gui.CloseModal()
            end,
            create = function(element)
                element:ScheduleEvent("placeGlossaryCard", 0.02)
            end,
            placeGlossaryCard = function(element)
                local w = element.renderedWidth or 0
                local h = element.renderedHeight or 0
                local px, py = nil, nil
                pcall(function()
                    local p = element.mousePoint
                    if p ~= nil and (p.x ~= 0 or p.y ~= 0) then
                        px = p.x * w
                        py = (1 - p.y) * h
                    end
                end)
                if px == nil or w <= 0 then
                    --cursor unavailable: fall back to center.
                    px = w * 0.5 - 190
                    py = h * 0.4
                end
                card.x = math.max(8, math.min(px + 10, w - 400))
                card.y = math.max(8, math.min(py - 40, h - 280))
                card.selfStyle.opacity = 1
            end,
            card,
        })
    end,
}

local g_adventureDocumentId = "adventureDocuments"

function GetCurrentAdventuresDocument()
    local doc = mod:GetDocumentSnapshot(g_adventureDocumentId)
    return doc
end

Commands.RegisterMacro{
    name = "clearadventuredocuments",
    summary = "clear adventure docs",
    doc = "Usage: /clearadventuredocuments\nClears the current adventure document list.",
    command = function(str)
        local doc = GetCurrentAdventuresDocument()
        doc:BeginChange()
        for k, v in pairs(doc.data) do
            if doc.data[k] ~= nil then
                doc.data[k] = nil
            end
        end
        doc:CompleteChange()
    end,
}

Commands.RegisterMacro{
    name = "setadventuredocumentstitle",
    summary = "set adventure title",
    doc = "Usage: /setadventuredocumentstitle name [icon]\nSets the title for adventure documents, and optionally an icon.",
    command = function(str)
        local args = Commands.SplitArgs(str)
        local doc = GetCurrentAdventuresDocument()
        doc:BeginChange()
        doc.data.meta = {
            name = args[1],
            icon = args[2],
        }
        doc:CompleteChange("Set adventure document title")
    end,
}

Commands.RegisterMacro{
    name = "setadventuredocument",
    summary = "set adventure doc",
    doc = "Usage: /setadventuredocument <order> <document name>\nSets a document as a 'current' adventure document. Use 'off' for order to remove.",
    completions = function(args, argIndex)
        if argIndex == 1 then
            return {{text = "off", summary = "remove document"}, {text = "0", summary = "slot 0"}, {text = "1", summary = "slot 1"}, {text = "2", summary = "slot 2"}, {text = "3", summary = "slot 3"}, {text = "4", summary = "slot 4"}}
        elseif argIndex == 2 then
            local result = {}
            local docs = dmhub.GetTable("documents")
            for k, v in unhidden_pairs(docs) do
                result[#result+1] = {text = v.name or k, summary = "document"}
            end
            table.sort(result, function(a, b) return a.text < b.text end)
            return result
        end
        return {}
    end,
    command = function(str)

    local args = Commands.SplitArgs(str)
    print("ADVENTURE:: SET", str, "->", args)
    if #args ~= 2 then
        print("ADVENTURE:: INVALID")
        return
    end

    local ord = tonumber(args[1])

    local name = string.lower(args[2])
    print("ADVENTURE:: SETTING", name, "TO", ord)

    local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
    for k, doc in unhidden_pairs(customDocs) do
        if string.lower(doc.name) == name then
            local doc = GetCurrentAdventuresDocument()
            doc:BeginChange()
            if ord == nil then
                doc.data[k] = nil
            else
                doc.data[k] = {
                    order = ord
                }
            end
            doc:CompleteChange("Change variable")
            print("ADVENTURE:: MODIFIED DOCUMENT")
            return
        end
    end

    print("ADVENTURE:: COULD NOT FIND DOC", name)
    end,
}



--Exported so other surfaces FRAME this panel rather than reimplement the
--tree. The journal viewer's tree rail is the first caller: it used to build
--its own tree, which meant every tree feature (the Characters section,
--per-type icons, the row context menu, drag-to-rail) had to be written
--twice and drifted apart.
--  options.embedded  drop dock-only furniture (the recent-documents strip)
--  options.onPick    called with a docId instead of opening a dialog
function JournalCreatePanel(options)
    return CreateJournalPanel(options)
end

DockablePanel.Register {
    name = "Journal",
    icon = "icons/standard/Icon_App_Journal.png",
    vscroll = false,
    dmonly = false,
    minHeight = 160,
    content = function()
        track("panel_open", {
            panel = "Journal",
            dailyLimit = 30,
        })
        return CreateJournalPanel()
    end,
}

local function ImportPDFDialog(path)
    local pathSize = assets.PathSizeInBytes(path) / (1024 * 1024)
    local allowedSize = dmhub.uploadQuotaRemaining / (1024 * 1024)

    local dialogPanel
    dialogPanel = gui.Panel {
        classes = { "framedPanel" },
        width = 1200,
        height = 800,
        pad = 8,
        flow = "vertical",
        styles = ThemeEngine.GetStyles(),

        destroy = function(element)
            if g_modalDialog == element then
                g_modalDialog = nil
            end
        end,

        gui.Label {
            classes = { "dialogTitle" },
            halign = "center",
            valign = "top",
            text = "Import PDF Document",
        },

        gui.Panel {
            bgimage = string.format("#PDF:path:%s|0", path),
            bgcolor = "white",
            maxWidth = 512,
            maxHeight = 512,
            autosizeimage = true,
            width = "auto",
            height = "auto",
        },

        gui.Panel {
            flow = "vertical",
            halign = "left",
            valign = "bottom",
            width = "auto",
            height = "auto",
            gui.Label {
                classes = { "sizeS" },
                width = "auto",
                height = "auto",
                create = function(element)
                    element.text = string.format("This file is %.1fMB\nBandwidth remaining this month: %.1fMB", pathSize,
                        allowedSize)
                    element:SetClass("danger", allowedSize < pathSize)
                end,
            },
            gui.Label {
                classes = { "link", "sizeS" },
                width = "auto",
                height = "auto",
                text = "Support us on Patreon for more bandwidth.",
                click = function(element)
                    dmhub.OpenRegisteredURL("Patreon")
                end,
            },
        },

        gui.Button {
            classes = { "sizeL" },
            valign = "bottom",
            halign = "center",
            text = "Import Document",
            click = function(element)
                gui.CloseModal()

                local operation = dmhub.CreateNetworkOperation()
                operation.description = "Uploading Document"
                operation.status = "Uploading..."
                operation.progress = 0.0
                operation:Update()

                local parentFolder = nil
                if not dmhub.isDM then
                    parentFolder = "public"
                end

                assets.UploadPDFDocumentAsset {
                    parentFolder = parentFolder,
                    progress = function(r)
                        operation.progress = r
                        operation:Update()
                    end,
                    upload = function(guid)
                        operation.progress = 1
                        operation:Update()
                    end,
                    error = function(msg)
                        gui.ModalMessage {
                            title = "Error importing PDF",
                            message = msg,
                        }
                        operation.progress = 1
                        operation:Update()
                    end,
                    path = path,
                }
            end,
        },

        gui.Button {
            classes = { "closeButton" },
            halign = "right",
            valign = "top",
            floating = true,
            escapeActivates = true,
            escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
            click = function()
                gui.CloseModal()
            end,
        },
    }

    gui.ShowModal(dialogPanel)
    g_modalDialog = dialogPanel
end

--Context-menu entries putting a journal document on the icon rail (the
--non-drag path for the shortcut feature). Returns a list to APPEND to
--the document row's normal context menu -- never a menu of its own,
--which would shadow the standard verbs (Share to Chat, Rename, ...).
--Empty when the rail trial mode is off (it is dev-gated).
local function RailAvailable()
    return dmhub.GetSettingValue("iconrail") and devmode()
end

local function RailAddMenuEntries(element, doc)
    local result = {}
    if doc == nil or rawget(_G, "IconRailDocAdd") == nil or not RailAvailable() then
        return result
    end
    result[#result + 1] = {
        text = "Add to left rail",
        click = function()
            element.popup = nil
            IconRailDocAdd(doc.id, "left")
        end,
    }
    result[#result + 1] = {
        text = "Add to right rail",
        click = function()
            element.popup = nil
            IconRailDocAdd(doc.id, "right")
        end,
    }
    return result
end

--The rail entries for a CHARACTER row, appended to its context menu the
--same way document rows get theirs.
local function RailAddCharacterEntries(element, charid)
    local result = {}
    if charid == nil or rawget(_G, "IconRailCharacterAdd") == nil or not RailAvailable() then
        return result
    end
    result[#result + 1] = {
        text = "Add to left rail",
        click = function()
            element.popup = nil
            IconRailCharacterAdd(charid, "left")
        end,
    }
    result[#result + 1] = {
        text = "Add to right rail",
        click = function()
            element.popup = nil
            IconRailCharacterAdd(charid, "right")
        end,
    }
    return result
end

--Whether a character has been claimed by a player. Sharing a character
--to chat is gated on this: unclaimed characters (pregens nobody has
--taken, Director-side NPCs) stay out of chat.
local function CharacterAssignedToPlayer(token)
    if token == nil then
        return false
    end
    if token.playerNameOrNil ~= nil then
        return true
    end
    local controlled = false
    pcall(function() controlled = token.playerControlled end)
    return controlled == true
end

local CreateFolderContentsPanel

----------------------------------------------------------------------
-- Characters shared into the journal
-- --------------------------------
-- Explicitly curated, not derived from party membership: a Director
-- shares a character (token right-click > Share to Journal, or the
-- party roster's right-click menu) and it appears in the journal's
-- Characters section for everyone. Lives in a shared cloud document so
-- the list syncs to every client.
----------------------------------------------------------------------

local JOURNAL_CHARACTERS_DOC = "journalcharacters"

--Panel monitor path for the shared list.
function JournalCharactersPath()
    return mod:GetDocumentPath(JOURNAL_CHARACTERS_DOC)
end

--The charids currently shared into the journal. Characters that have
--since been deleted from the game are skipped (the entry stays in the
--document, so it comes back if the character does).
function JournalSharedCharacterIds()
    local doc = mod:GetDocumentSnapshot(JOURNAL_CHARACTERS_DOC)
    local shared = doc.data.characters or {}
    local result = {}
    for charid, on in pairs(shared) do
        if on and dmhub.GetCharacterById(charid) ~= nil then
            result[#result + 1] = charid
        end
    end
    return result
end

function JournalHasCharacter(charid)
    if charid == nil then
        return false
    end
    local doc = mod:GetDocumentSnapshot(JOURNAL_CHARACTERS_DOC)
    local shared = doc.data.characters or {}
    return shared[charid] == true
end

function JournalShareCharacter(charid)
    if charid == nil or dmhub.GetCharacterById(charid) == nil then
        return false
    end
    local doc = mod:GetDocumentSnapshot(JOURNAL_CHARACTERS_DOC)
    doc:BeginChange()
    local shared = doc.data.characters or {}
    shared[charid] = true
    doc.data.characters = shared
    doc:CompleteChange("Share character to journal")
    return true
end

function JournalUnshareCharacter(charid)
    if charid == nil then
        return false
    end
    local doc = mod:GetDocumentSnapshot(JOURNAL_CHARACTERS_DOC)
    doc:BeginChange()
    local shared = doc.data.characters or {}
    shared[charid] = nil
    doc.data.characters = shared
    doc:CompleteChange("Remove character from journal")
    return true
end

--A row for one character in the journal's Characters section. Clicking
--frames that character's panel -- the same summary/details stack the
--sidebar Character panel builds -- in a document window.
local function CreateCharacterRow(charid)
    local iconPanel
    local nameLabel

    local resultPanel
    resultPanel = gui.Panel {
        classes = { "itemContainer" },
        data = {
            charid = charid,
            sortName = "",
        },

        click = function(element)
            if rawget(_G, "ShowCharacterPanelDocument") ~= nil then
                ShowCharacterPanelDocument(charid)
            end
        end,

        rightClick = function(element)
            local token = dmhub.GetCharacterById(charid)
            local entries = {
                {
                    text = "Open Character Panel",
                    click = function()
                        element.popup = nil
                        if rawget(_G, "ShowCharacterPanelDocument") ~= nil then
                            ShowCharacterPanelDocument(charid)
                        end
                    end,
                },
                {
                    text = "Character Sheet...",
                    click = function()
                        element.popup = nil
                        if token ~= nil then
                            token:ShowSheet()
                        end
                    end,
                },
                {
                    --the engine has no character card for chat (sharing a
                    --bare character posts an empty message), so this
                    --shares the portrait -- the "here is who this is"
                    --gesture. Only for characters a player has claimed.
                    text = "Share to Chat...",
                    hidden = not CharacterAssignedToPlayer(token),
                    click = function()
                        element.popup = nil
                        if token == nil then
                            return
                        end
                        local portrait = nil
                        pcall(function() portrait = token.offTokenPortrait end)
                        if portrait == nil or portrait == "" then
                            return
                        end
                        chat.ShareData(ImageDocument.new {
                            imageid = portrait,
                            width = 512,
                            height = 512,
                        })
                    end,
                },
            }

            for _, e in ipairs(RailAddCharacterEntries(element, charid)) do
                entries[#entries + 1] = e
            end

            entries[#entries + 1] = {
                text = "Remove from Journal",
                hidden = not dmhub.isDM,
                click = function()
                    element.popup = nil
                    JournalUnshareCharacter(charid)
                end,
            }

            element.popup = gui.ContextMenu {
                entries = entries,
            }
        end,

        --Drag a character onto a rail to make a shortcut button, the same
        --gesture document rows offer. Unlike documents these accept ONLY a
        --rail as a target: a character has no place in the folder tree, so
        --there is nothing to reparent it into.
        draggable = true,
        canDragOnto = function(element, target)
            if target == nil then
                return false
            end
            return target:HasClass("iconRail") or target:HasClass("iconRailButton")
        end,
        dragging = function(element, target)
            --slot preview; the doc-named helper is key-agnostic, it only
            --resolves the target to a side+slot and shows the ghost.
            if rawget(_G, "IconRailDocDragging") ~= nil then
                IconRailDocDragging(target)
            end
        end,
        drag = function(element, target)
            if target == nil then
                return
            end
            if target:HasClass("iconRail") or target:HasClass("iconRailButton") then
                if rawget(_G, "IconRailCharacterDrop") ~= nil then
                    IconRailCharacterDrop(charid, target)
                end
            end
        end,

        refreshCharacter = function(element)
            local token = dmhub.GetCharacterById(charid)
            if token == nil then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)
            nameLabel.text = token.name or "(Unnamed)"
            element.data.sortName = nameLabel.text

            --portrait when the token has one; the generic character icon
            --otherwise. Portraits are full-colour, so the tinting the
            --"icon" class applies has to be turned off for them.
            local portrait = nil
            pcall(function() portrait = token.offTokenPortrait end)
            if portrait ~= nil and portrait ~= "" then
                iconPanel.bgimage = portrait
                iconPanel.selfStyle.bgcolor = "white"
                pcall(function()
                    iconPanel.selfStyle.imageRect = token:GetPortraitRectForAspect(1, portrait)
                end)
            else
                iconPanel.bgimage = "icons/standard/Icon_App_Character.png"
                iconPanel.selfStyle.bgcolor = "white"
            end
        end,

        gui.Panel {
            classes = { "item" },

            --the ghost expander keeps this row on the same
            --[expander][icon][name] grammar as document rows, so the two
            --kinds of row line up in the tree.
            gui.Panel {
                bgimage = "panels/triangle.png",
                classes = { "triangle", "ghost" },
                styles = gui.TriangleStyles,
            },
            (function()
                iconPanel = gui.Panel {
                    classes = { "icon" },
                }
                return iconPanel
            end)(),
            (function()
                nameLabel = gui.Label {
                    text = "",
                }
                return nameLabel
            end)(),
        },
    }

    resultPanel:FireEvent("refreshCharacter")

    return resultPanel
end

--The journal's Characters section: party members, each opening their
--character panel in a window. Built directly rather than as a folder in
--the documents data model, so it can never be renamed, deleted, or
--become a drop target for documents.
local function CreateCharactersSection(journalPanel)
    local m_rows = {}
    local m_contentPanel

    m_contentPanel = gui.Panel {
        halign = "left",
        width = "100%-16",
        height = "auto",
        flow = "vertical",
        classes = { "contentPanel" },
        lmargin = 16,

        refreshCharacters = function(element)
            local children = {}
            local newRows = {}
            for _, charid in ipairs(JournalSharedCharacterIds()) do
                local row = m_rows[charid] or CreateCharacterRow(charid)
                newRows[charid] = row
                row:FireEvent("refreshCharacter")
                children[#children + 1] = row
            end

            table.sort(children, function(a, b)
                return string.lower(a.data.sortName or "") < string.lower(b.data.sortName or "")
            end)

            m_rows = newRows
            element.children = children
            element:SetClass("empty", #children == 0)
        end,
    }

    local resultPanel
    resultPanel = gui.TreeNode {
        classes = { "documentFolder" },
        text = "Characters",
        width = "100%",
        editable = false,
        draggable = false,
        expanded = false,
        contentPanel = m_contentPanel,

        --rebuilt whenever the journal refreshes its assets, and whenever
        --the shared list changes on any client. The whole section hides
        --when nothing has been shared -- an empty "Characters" header
        --would just be a dead end.
        refreshDocuments = function(element)
            m_contentPanel:FireEvent("refreshCharacters")
            local count = #m_contentPanel.children
            element:SetClass("collapsed", count == 0)
            element:FireEvent("setempty", count == 0)
        end,
    }

    return resultPanel
end

local function CreateFolderPanel(journalPanel, folderid)
    local builtinFolder = folderid == "private" or folderid == "public" or folderid == "templates" or
        folderid == game.currentMapId or folderid == dmhub.loginUserid
    local m_contentPanel = CreateFolderContentsPanel(journalPanel, folderid)

    local resultPanel
    resultPanel = gui.TreeNode {
        classes = cond(builtinFolder, { "documentFolder" }, { "documentFolder", "subfolder" }),
        headerExtraClasses = cond(not builtinFolder, {"subfolder"}, {}),
        editable = not builtinFolder,
        width = "100%",
        dragTarget = true,
        dragTargetPriority = 100,
        data = {
            folderid = folderid,
        },

        expanded = builtinFolder,
        queryNode = function(element, info)
            local folders = journalPanel.data.documentFoldersTable
            local folder = folders[folderid]
            info.node = folder
        end,

        draggable = not builtinFolder,
        canDragOnto = function(element, target)
            if target == nil then
                return false
            end
            --accept the folder ANY way the engine offers it: the TreeNode
            --root (class documentFolder) or its header (class "folder",
            --which is also where the dragTarget flag actually lands --
            --see gui.TreeNode).
            if target:HasClass("documentFolder") then
                return true
            end
            return (target:HasClass("folder") or target:HasClass("contentPanel") or target:HasClass("dragDocumentSiblingSpacer")) and
                target:FindParentWithClass("documentFolder") ~= nil
        end,
        drag = function(element, target)
            if target == nil then
                return
            end

            local originalTarget = target

            if not target:HasClass("documentFolder") then
                target = target:FindParentWithClass("documentFolder")
            end
            if target == nil then
                return
            end

            local folders = journalPanel.data.documentFoldersTable
            local folder = folders[folderid]
            if folder == nil then
                return
            end

            folder.parentFolder = target.data.folderid

            if originalTarget:HasClass("dragDocumentSiblingSpacer") then
                
            end

            folder:Upload()
        end,

        change = function(element, text)
            local folders = journalPanel.data.documentFoldersTable
            local folder = folders[folderid]
            if folder == nil then
                return
            end

            text = trim(text)
            if text == "" then
                element:FireEvent("text", folder.description)
                return
            end

            folder.description = text
            folder:Upload()
        end,

        contentPanel = m_contentPanel,

        refreshDocuments = function(element)
            local folders = journalPanel.data.documentFoldersTable
            local folder = folders[folderid]
            if folder == nil then
                return
            end
            resultPanel:FireEventTree("text", folder.description)

            --make sure the triangle greys out if we're empty.
            local foldersToMembers = journalPanel.data.foldersToMembers
            element:FireEvent("setempty", foldersToMembers[folderid] == nil or next(foldersToMembers[folderid]) == nil)
        end,

        contextMenu = function(element)
            if builtinFolder then
                return
            end

            element.popup = gui.ContextMenu {
                entries = {
                    {
                        text = "Delete Folder",
                        click = function()
                            element.popup = nil
                            local folders = journalPanel.data.documentFoldersTable
                            local folder = folders[folderid]
                            if folder == nil then
                                return
                            end

                            if m_contentPanel:HasClass("empty") then
                                folder.hidden = true
                                folder:Upload()
                            else
                                gui.ModalMessage {
                                    title = "Folder Not Empty",
                                    message = "You cannot delete a folder that contains documents. Please move or delete the documents first.",
                                }
                            end
                        end,
                    }
                }
            }
        end,
    }

    return resultPanel
end

CreateFolderContentsPanel = function(journalPanel, folderid)
    local m_documentPanels = {}
    local contentPanel
    local m_invalidated = true

    local dragTarget = true

    --The tree's indent ladder lives HERE and only here: every contents
    --panel shifts ALL of its children (document rows and subfolder
    --headers alike, so same-depth siblings share a left edge) one step
    --right of its folder's header. The root panel (folderid "") uses a
    --smaller step, which is the tree's left gutter.
    local indent = 16
    if folderid == "" then
        indent = 8
    end

    --the root of the tree also carries the Characters section, below the
    --document folders. Built on first refresh rather than here: a panel
    --constructed before it has a parent is reported as a leak.
    local m_charactersSection = nil

    local charactersMonitor = nil
    if folderid == "" then
        charactersMonitor = JournalCharactersPath()
    end

    contentPanel = gui.Panel {
        --explicit halign: a flow child with no alignment centers itself
        --in the icon-rail window host (the dock resolves it left). With
        --the old width overhang ("100%+12") centering both cancelled the
        --lmargin indent and shifted each level LEFT, collapsing the
        --ladder so nested rows drew left of root headers. Left-aligned
        --with a contained width, both hosts lay out identically.
        halign = "left",
        width = "100%-" .. indent,
        height = "auto",
        flow = "vertical",
        dragTarget = dragTarget,
        dragTargetPriority = 1,
        classes = { "contentPanel" },
        x = 0,
        --indent per nesting level, so folder membership is readable at a
        --glance. NOT a flat 16: the root gutter is 8, and the width above
        --subtracts this same value, so the two must stay in step.
        lmargin = indent,
        monitorGame = charactersMonitor,

        expand = function(element)
            if m_invalidated then
                element:FireEventTree("refreshDocuments")
            end
        end,

        --the shared characters list can change on any client; the root
        --contents panel carries the monitor because it is never
        --collapsed (a collapsed panel processes no events, so the
        --section itself cannot watch for its own arrival).
        refreshGame = function(element)
            if m_charactersSection ~= nil then
                m_charactersSection:FireEvent("refreshDocuments")
            end
        end,
        refreshDocuments = function(element)
            if element:HasClass("collapsed") then
                --will be refreshed when it is expanded.
                m_invalidated = true

                local foldersToMembers = journalPanel.data.foldersToMembers
                contentPanel:SetClass("empty",
                    foldersToMembers[folderid] == nil or next(foldersToMembers[folderid]) == nil)

                return
            end

            m_invalidated = false

            local children = {}
            local newDocumentPanels = {}
            local foldersToMembers = journalPanel.data.foldersToMembers
            local members = foldersToMembers[folderid] or {}
            for k, member in pairs(members) do
                local p

                if member.nodeType == "pdf" or member.nodeType == "image" or member.nodeType == "pdffragment" or member.nodeType == "custom" or member.nodeType == "negotiation" then
                    --One shared context menu for the whole document row: the
                    --container, the inner row, and the name label all route
                    --here, because right-clicks land on whichever child is
                    --topmost and press-family events don't bubble through
                    --interactive children. Holds the standard document verbs
                    --plus the icon-rail shortcut entries appended at the end.
                    local showDocumentMenu = function(element)
                        local container = element
                        if not container:HasClass("itemContainer") then
                            container = element:FindParentWithClass("itemContainer") or element
                        end
                        local entries = {
                            {
                                text = "Share to Chat...",
                                click = function()
                                    if member.nodeType == "pdf" then
                                        dmhub.Coroutine(function()
                                            local pdf = assets.pdfDocumentsTable[k]
                                            if pdf == nil then
                                                return
                                            end

                                            for i = 0, 300 do
                                                if pdf.doc.summary ~= nil and pdf.doc.summary.pageWidth ~= nil then
                                                    break
                                                end

                                                coroutine.yield(0.01)
                                            end

                                            if pdf.doc.summary == nil then
                                                --failed to load document.
                                                return
                                            end

                                            local wrapper = PDFWrapper.new {
                                                docid = k,
                                                width = pdf.doc.summary.pageWidth,
                                                height = pdf.doc.summary.pageHeight,
                                            }

                                            chat.ShareData(wrapper)
                                        end)
                                    elseif member.nodeType == "pdffragment" then
                                        chat.ShareData(member)
                                    elseif type(member) == "table" and member.IsDerivedFrom("CustomDocument") then
                                        chat.ShareData(CustomDocumentRef.new {
                                            docid = k
                                        })
                                    else
                                        local imageWrapper = ImageDocument.new {
                                            imageid = k,
                                            width = member.width,
                                            height = member.height,
                                        }

                                        chat.ShareData(imageWrapper)
                                    end

                                    element.popup = nil
                                end,
                            },
                            {
                                text = "Add to Run",
                                --documents only; the Run panel is Director-side, and the
                                --RunAgenda hook loads late (DocumentSystem), hence rawget.
                                hidden = member.nodeType ~= "custom" or not dmhub.isDM or rawget(_G, "RunAgenda") == nil,
                                click = function()
                                    element.popup = nil
                                    RunAgenda.AddDocument(member)
                                end,
                            },
                            {
                                text = "Rename",
                                hidden = not member:HaveEditPermissions(),
                                click = function()
                                    element.popup = nil
                                    container:FireEventTree("rename")
                                end,
                            },
                            {
                                text = "Duplicate",
                                hidden = member.nodeType ~= "custom",
                                click = function()
                                    element.popup = nil

                                    local newDoc = DeepCopy(member)
                                    newDoc.id = dmhub.GenerateGuid()
                                    newDoc.description = "Copy of " .. (member.description or "")
                                    newDoc.updateid = ""
                                    newDoc.ord = (member.ord or 0) + 0.5
                                    if not dmhub.isDM then
                                        newDoc.ownerid = dmhub.loginUserid
                                    end

                                    newDoc.textStorage = false
                                    newDoc:SetTextContent(member:GetTextContent())

                                    newDoc:Upload()
                                end,
                            },
                            {
                                text = "Delete",
                                hidden = not member:HaveEditPermissions(),
                                click = function()
                                    element.popup = nil
                                    local doc = container.data.doc or member
                                    doc.hidden = true
                                    doc:Upload()
                                end,
                            }
                        }

                        if member.nodeType == "pdf" or member.nodeType == "custom" then
                            entries[#entries + 1] = {
                                text = "Set Keybind...",
                                click = function()
                                    element.popup = Keybinds.ShowBindPopup {
                                        name = string.format("Open %s", member.description),
                                        command = string.format("doc %s", k),
                                        destroy = function(element)
                                        end,
                                    }
                                end,
                            }
                        end

                        for _, e in ipairs(RailAddMenuEntries(element, member)) do
                            entries[#entries + 1] = e
                        end

                        element.popup = gui.ContextMenu {
                            entries = entries,
                        }
                    end

                    p = m_documentPanels[k] or gui.Panel {
                        gui.Panel{
                            classes = {"dragDocumentSiblingSpacer"},
                            floating = true,
                            dragTarget = true,
                        },
                        draggable = dragTarget,
                        hover = function(element) --vback
                            if member.nodeType ~= "pdf" then
                                return
                            end

                            local halign = "left"
                            local xadjustment = -35
                            local dock = element:FindParentWithClass("dock")

                            if dock ~= nil then
                                halign = dock.data.TooltipAlignment()
                                if halign == "right" then
                                    xadjustment = 0
                                end
                            end

                            local document = member.doc
                            element.tooltip = gui.Panel {

                                bgimage = true,
                                bgcolor = "clear",
                                width = 180,
                                height = 180 * 1.3 + 24,
                                x = xadjustment,
                                y = 145,
                                cornerRadius = { x1 = 4, y1 = 4, x2 = 0, y2 = 0 },
                                halign = halign,

                                flow = "vertical",

                                gui.Panel {
                                    bgimage = true,
                                    bgcolor = Styles.RichBlack02,
                                    width = "100%",
                                    height = 24,
                                    halign = "center",
                                    valign = "top",
                                    cornerRadius = { x1 = 4, y1 = 4, x2 = 0, y2 = 0 },

                                    flow = "horizontal",

                                    gui.Label {
                                        text = member.description,
                                        fontFace = "newzald",
                                        lmargin = 5,
                                        fontSize = 10,
                                        width = 140,
                                        textWrap = false,
                                        textOverflow = "ellipsis",
                                        height = "100%",
                                        bold = true,
                                    },

                                    gui.Label {
                                        text = "",
                                        fontFace = "newzald",
                                        halign = "right",
                                        fontSize = 10,
                                        rmargin = 5,
                                        width = "auto",
                                        height = "100%",
                                        bold = true,


                                        create = function(element)
                                            if document.summary ~= nil then
                                                element.text = document.summary["npages"]
                                            else
                                                element:ScheduleEvent("create", 0.01)
                                            end
                                        end
                                    },
                                },

                                gui.Panel {
                                    bgimage = document:GetPageThumbnailId(0),
                                    bgcolor = "white",
                                    width = "100%",
                                    height = "100%-24",
                                    halign = "center",
                                    valign = "top",

                                },
                            }

                            element.tooltip:MakeNonInteractiveRecursive()
                        end,
                        canDragOnto = function(element, target)
                            if target == nil then
                                return false
                            end
                            --the icon rail accepts documents as shortcut
                            --buttons, alongside the existing folder
                            --reparent/reorder targets.
                            if target:HasClass("iconRail") or target:HasClass("iconRailButton") then
                                return true
                            end
                            --accept the folder as its TreeNode root
                            --(documentFolder) OR its header ("folder" --
                            --where the dragTarget flag actually lands).
                            if target:HasClass("documentFolder") then
                                return true
                            end
                            return (target:HasClass("folder") or target:HasClass("contentPanel") or target:HasClass("dragDocumentSiblingSpacer")) and
                                target:FindParentWithClass("documentFolder") ~= nil
                        end,
                        dragging = function(element, target)
                            --live slot preview while hovering a rail.
                            if rawget(_G, "IconRailDocDragging") ~= nil then
                                IconRailDocDragging(target)
                            end
                        end,
                        drag = function(element, target)
                            if target == nil then
                                return
                            end

                            --dropped on a rail: create a shortcut button
                            --there instead of reparenting.
                            if target:HasClass("iconRail") or target:HasClass("iconRailButton") then
                                if rawget(_G, "IconRailDocDrop") ~= nil then
                                    IconRailDocDrop(element.data.doc.id, target)
                                end
                                return
                            end

                            local originalTarget = target

                            if not target:HasClass("documentFolder") then
                                target = target:FindParentWithClass("documentFolder")
                            end
                            if target == nil then
                                return
                            end

                            if originalTarget:HasClass("dragDocumentSiblingSpacer") then
                                local parentNode = originalTarget.parent.parent
                                local ord = nil
                                for _,child in ipairs(parentNode.children) do
                                    local info = {}
                                    child:FireEvent("queryNode", info)
                                    if info.node ~= nil and info.node ~= element.data.doc then
                                        if ord ~= nil and info.node.ord <= ord then
                                            info.node.ord = ord + 1
                                            info.node:Upload()
                                        end
                                        if child == originalTarget.parent then
                                            if ord == nil then
                                                element.data.doc.ord = info.node.ord - 1
                                            else
                                                element.data.doc.ord = (ord + info.node.ord) / 2
                                            end
                                        end
                                        ord = info.node.ord
                                    end
                                end
                                
                            end

                            element.data.doc.parentFolder = target.data.folderid
                            element.data.doc:Upload()
                        end,
                        queryNode = function(element, info)
                            info.node = element.data.doc
                        end,
                        data = {
                            showBookmarks = false,

                        },
                        classes = { "itemContainer" },
                        click = function(element)
                            --When this panel is framed by another surface
                            --(the journal viewer's tree rail), picking a
                            --document navigates that host instead of
                            --opening a second window.
                            local root = element:FindParentWithClass("journalPanelRoot")
                            local onPick = nil
                            if root ~= nil and root.data ~= nil then
                                onPick = root.data.onPick
                            end
                            if onPick ~= nil then
                                onPick(member.id)
                                return
                            end
                            CustomDocument.OpenContent(member)
                        end,

                        rightClick = showDocumentMenu,


                        refreshDoc = function(element, doc)
                            local parentElement = element
                            element.data.ord = doc.ord
                            element.data.ordDesc = string.lower("b" .. doc.description)
                            element.data.doc = doc

                            --try to order according to info bubbles.
                            if member.nodeType == "custom" then
                                local ord = nil
                                local bubbles = dmhub.infoBubbles
                                for k, bubble in pairs(bubbles) do
                                    if bubble.document ~= nil then
                                        local doc = bubble.document:GetMarkdownDocument()
                                        if doc ~= nil and doc.id == member.id then
                                            ord = bubble.document.ord
                                        end
                                    end
                                end

                                if ord ~= nil then
                                    element.data.ord = doc.ord
                                    element.data.ordDesc = string.format("b%09d-%s", ord, doc.description)
                                end
                            end


                            if member.nodeType == "pdf" then
                                local bookmarks = doc.bookmarks
                                local bookmarksSorted = {}

                                if element.data.showBookmarks then
                                    for k, v in pairs(bookmarks) do
                                        if v.parentGuid == nil or v.parentGuid == "" then
                                            bookmarksSorted[#bookmarksSorted + 1] = {
                                                key = k,
                                                value = v,
                                            }
                                        end
                                    end
                                elseif element.data.bookmarks ~= nil then
                                    for k, v in pairs(element.data.bookmarks) do
                                        if v.valid then
                                            v:SetClass("collapsed", true)
                                        end
                                    end
                                    return
                                end

                                --common case, no bookmarks before or after, do nothing.
                                if #bookmarksSorted == 0 and element.data.bookmarks == nil then
                                    return
                                end

                                --no bookmarks anymore.
                                if #bookmarksSorted == 0 then
                                    element.data.bookmarks = nil
                                    local children = element.children
                                    --keep the two structural children: the floating drag spacer at [1] and the heading row at [2].
                                    children = { children[1], children[2] }
                                    element.children = children
                                    return
                                end

                                table.sort(bookmarksSorted,
                                    function(a, b)
                                        return a.value.page < b.value.page or
                                            (a.value.page == b.value.page and ((a.value.y or 0) < (b.value.y or 0)))
                                    end)
                                print("SORTED_BOOKMARKS::")

                                local children = {}

                                local existing = element.data.bookmarks or {}
                                local newBookmarks = {}
                                for _, v in ipairs(bookmarksSorted) do
                                    local key = v.key
                                    local page = v.value.page
                                    local existingBookmark = existing[v.key]
                                    if existingBookmark ~= nil then
                                        existingBookmark:SetClass("collapsed", false)
                                    else
                                        existingBookmark = gui.Panel {
                                            classes = { "item" },
                                            --bookmark rows have no expander slot; 34 puts a
                                            --bookmark's icon one 16px ladder step right of its
                                            --PDF row's icon (which sits at 18-slot + 4 margin).
                                            x = 34,
                                            click = function(element)
                                                mod.shared.ShowPDFViewerDialog(member, page)
                                            end,
                                            gui.Panel {
                                                classes = { "icon" },
                                                bgimage = "icons/icon_app/document-bookmark.png",
                                            },
                                            gui.Label {
                                                characterLimit = 32,
                                                updateBookmarks = function(element, bookmarks)
                                                    local bookmark = bookmarks[v.key]
                                                    local n = 0
                                                    local b = bookmark
                                                    local s = ""
                                                    print("SORTED_BOOKMARKS:: PARENT: " ..
                                                        v.key ..
                                                        " " ..
                                                        bookmark.title ..
                                                        " " .. bookmark.page .. " " .. (bookmark.parentGuid or "none"))
                                                    while b.parentGuid ~= nil and n < 100 do
                                                        b = bookmarks[b.parentGuid]
                                                        if b == nil then
                                                            break
                                                        end
                                                        n = n + 1
                                                        s = s .. "-"
                                                    end

                                                    element.text = s .. bookmark.title
                                                end,
                                                rename = function(element)
                                                    element:BeginEditing()
                                                end,
                                                change = function(element)
                                                    local bookmarks = doc.bookmarks
                                                    local bookmark = bookmarks[k]
                                                    if bookmark ~= nil then
                                                        bookmark.title = element.text
                                                    end
                                                    parentElement.data.doc.bookmarks = bookmarks
                                                    parentElement.data.doc:Upload()
                                                end,
                                            },

                                            rightClick = function(element)
                                                element.popup = gui.ContextMenu {
                                                    entries = {
                                                        {
                                                            text = "Share to Chat...",
                                                            click = function()
                                                                dmhub.Coroutine(function()
                                                                    local ncount = 0
                                                                    while parentElement.data.doc.doc.summary == nil do
                                                                        coroutine.yield(0.01)
                                                                        ncount = ncount + 1
                                                                        if ncount > 600 then
                                                                            return
                                                                        end
                                                                    end

                                                                    chat.ShareData(PDFFragment.new {
                                                                        refid = k,
                                                                        page = v.page,
                                                                        area = { 0, 0, 1, 1 },
                                                                        width = parentElement.data.doc.doc.summary.pageWidth,
                                                                        height = parentElement.data.doc.doc.summary.pageHeight,
                                                                    })
                                                                end)

                                                                element.popup = nil
                                                            end,
                                                        },
                                                        {
                                                            text = "Rename",
                                                            click = function()
                                                                element.popup = nil
                                                                element:FireEventTree("rename")
                                                            end,
                                                        },
                                                        {
                                                            text = "Delete",
                                                            click = function()
                                                                element.popup = nil
                                                                local bookmarks = parentElement.data.doc.bookmarks
                                                                bookmarks[key] = nil
                                                                parentElement.data.doc.bookmarks = bookmarks
                                                                parentElement.data.doc:Upload()
                                                            end,
                                                        }
                                                    }
                                                }
                                            end,


                                        }
                                    end

                                    newBookmarks[v.key] = existingBookmark
                                    children[#children + 1] = existingBookmark
                                end

                                --keep the two structural children ahead of the bookmark panels: the floating
                                --drag spacer at [1] and the heading row at [2]. Inserting at index 1 in this
                                --order leaves the final list as { spacer, heading, ...bookmarks }.
                                table.insert(children, 1, element.children[2])
                                table.insert(children, 1, element.children[1])

                                element.data.bookmarks = newBookmarks
                                element.children = children

                                element:FireEventTree("updateBookmarks", bookmarks)
                            end
                        end, --end refreshDoc

                        gui.Panel {
                            classes = { "item" },

                            rightClick = showDocumentMenu,

                            --Every document row carries this expander triangle so the
                            --row layout is one fixed grammar: [expander slot][icon][name].
                            --Rows that cannot expand (no PDF bookmarks) keep the slot but
                            --"ghost" it (invisible, inert) instead of collapsing it, so
                            --document icons line up with each other and with their
                            --sibling folder headers' triangles.
                            gui.Panel {
                                bgimage = 'panels/triangle.png',
                                classes = { "triangle", "ghost" },
                                styles = gui.TriangleStyles,

                                refreshDoc = function(element, doc)
                                    element:SetClass("ghost", doc.bookmarks == nil or next(doc.bookmarks) == nil)
                                end,

                                press = function(element)
                                    if element:HasClass("ghost") then
                                        return
                                    end

                                    local parentPanel = element:FindParentWithClass("itemContainer")
                                    if parentPanel == nil or parentPanel.data.doc == nil then
                                        return
                                    end

                                    element:SetClass("expanded", not element:HasClass("expanded"))

                                    parentPanel.data.showBookmarks = element:HasClass("expanded")

                                    parentPanel:FireEvent("refreshDoc", parentPanel.data.doc)
                                end,

                                click = function(element)
                                end,
                            },
                            gui.Label {
                                width = 18,
                                height = 18,
                                cornerRadius = 9,
                                borderWidth = 1,
                                borderColor = Styles.textColor,
                                bgimage = true,
                                bgcolor = "black",
                                textAlignment = "center",
                                textOverflow = "overflow",
                                textWrap = false,
                                color = Styles.textColor,
                                bold = true,
                                text = "1",
                                fontSize = 11,
                                minFontSize = 9,
                                create = function(element)
                                    if member.parentFolder == game.currentMapId then
                                        local found = false
                                        if member.nodeType == "custom" then
                                            local bubbles = dmhub.infoBubbles
                                            for k, bubble in pairs(bubbles) do
                                                if bubble.document ~= nil then
                                                    local doc = bubble.document:GetMarkdownDocument()
                                                    if doc ~= nil and doc.id == member.id then
                                                        element.text = bubble.icon
                                                        found = true
                                                        break
                                                    end
                                                end
                                            end
                                        end

                                        element:SetClass("collapsed", not found)
                                    else
                                        element:SetClass("collapsed", true)
                                    end
                                end,
                            },
                            gui.Panel {
                                classes = { "icon" },
                                create = function(element)
                                    if member.parentFolder == game.currentMapId then
                                        element:SetClass("collapsed", true)
                                    else
                                        element:SetClass("collapsed", false)
                                        if member.nodeType == "pdf" then
                                            element.bgimage = "icons/icon_app/icon_app_137.png"
                                        elseif member.nodeType == "custom" or member.nodeType == "negotiation" then
                                            --journal documents show their full-colour semantic-type
                                            --icon (narration/combat/montage/negotiation/note/...).
                                            local typeIcon = nil
                                            pcall(function() typeIcon = CustomDocument.DocTypeIcon(member) end)
                                            if typeIcon ~= nil then
                                                element.bgimage = typeIcon
                                                element.selfStyle.bgcolor = "white"
                                            else
                                                element.bgimage = "icons/icon_app/icon_app_34.png"
                                            end
                                        else
                                            element.bgimage = "icons/icon_app/icon_app_34.png" --image / fragment
                                        end
                                    end
                                end,
                            },
                            gui.Label {
                                data = {},
                                characterLimit = 64,
                                rightClick = showDocumentMenu,
                                rename = function(element)
                                    element:BeginEditing()
                                end,
                                refreshDoc = function(element, doc)
                                    element.text = doc.description
                                    element.data.doc = doc
                                end,
                                change = function(element)
                                    local doc = element.data.doc
                                    local text = trim(element.text)
                                    if text ~= "" then
                                        doc.description = text
                                        doc:Upload()
                                    end

                                    element.text = doc.description
                                end,
                            },
                        },
                    }

                    p:FireEventTree("refreshDoc", member)
                elseif member.nodeType == "folder" or member.nodeType == "builtinFolder" then
                    p = m_documentPanels[k] or CreateFolderPanel(journalPanel, k)
                    p.data.ord = member.ord
                    p.data.ordDesc = string.lower("a" .. member.description)
                end


                newDocumentPanels[k] = p
                children[#children + 1] = p
            end

            table.sort(children, function(a, b)
                --Built-in folders (and PDF/image/folder members) have no `ord`
                --field, so a.data.ord/b.data.ord can be nil. Custom documents
                --default to ord 0. Comparing nil against a number throws and
                --aborts the whole journal render, so coalesce to 0 first.
                local ao, bo = a.data.ord or 0, b.data.ord or 0
                if ao ~= bo then
                    return ao < bo
                end
                return (a.data.ordDesc or "") < (b.data.ordDesc or "")
            end)

            --characters sort after the document folders, as the last
            --section of the tree root.
            if folderid == "" then
                if m_charactersSection == nil then
                    m_charactersSection = CreateCharactersSection(journalPanel)
                end
                children[#children + 1] = m_charactersSection
            end

            m_documentPanels = newDocumentPanels
            element.children = children

            if m_charactersSection ~= nil then
                m_charactersSection:FireEvent("refreshDocuments")
            end

            contentPanel:SetClass("empty", #children == 0)
        end,
    }

    return contentPanel
end

Commands.RegisterMacro{
    name = "getdocument",
    summary = "list PDF documents",
    doc = "Prints all unhidden PDF document IDs and descriptions to the console.",
    command = function()
        local docs = assets.pdfDocumentsTable
        for k, doc in pairs(docs or {}) do
            if not doc.hidden then
                print("VENLA: ", k, doc.description)
            end
        end
    end,
}

local GetRecentDocumentsSetting = setting {

    id = "recentDocuments",
    description = "Recent Documents",
    storage = "preference",
    default = { { id = "e6cab5b7-a1c9-4b12-ad06-ed573f6ba904" }, { id = "cc66844a-04d0-49a0-8687-65ef83b15363" }, { id = "4dad1bc1-d23a-4780-ac6a-536a0f9cd9b9" } },

}

local GetRecentDocumentsSettingPlayers = setting {

    id = "recentDocumentsPlayers",
    description = "Recent Documents",
    storage = "preference",
    default = { { id = "e6cab5b7-a1c9-4b12-ad06-ed573f6ba904" } },

}


local function GetRecentDocuments()
    local result = {}
    local docs = assets.pdfDocumentsTable

    local setting = GetRecentDocumentsSetting

    if not dmhub.isDM then
        setting = GetRecentDocumentsSettingPlayers
    end

    for k, entry in ipairs(setting:Get()) do
        local doc = docs[entry.id]

        result[#result + 1] = doc
    end

    return result
end

local function MakeRecentDocumentPanel(documentnumber)
    local documents = GetRecentDocuments()

    if documents[documentnumber] == nil then
        return nil
    end

    return gui.Panel {
        flow = "horizontal",
        bgimage = documents[documentnumber].doc:GetPageThumbnailId(0),
        bgcolor = "white",
        width = 80,
        height = 110,
        tmargin = 10,
        halign = "center",

        click = function(element)
            audio.FireSoundEvent("Mouse.Click")
            CustomDocument.OpenContent(documents[documentnumber])
            element.parent.tooltip = nil
        end,




        dehover = function(element)
            element.selfStyle.borderWidth = 0
        end,

        hover = function(element)

            audio.FireSoundEvent("Mouse.Hover")

            element.selfStyle.borderWidth = 2
            element.selfStyle.borderColor = "white"

            local member = documents[documentnumber]

            if member.nodeType ~= "pdf" then
                return
            end

            local halign = "left"
            local xadjustment = -35
            local dock = element:FindParentWithClass("dock")



            if dock ~= nil then
                halign = dock.data.TooltipAlignment()
                if halign == "right" then
                    xadjustment = 0
                end
            end

            local document = member.doc
            element.parent.tooltip = gui.Panel {

                bgimage = true,
                bgcolor = "clear",
                width = 180,
                height = 180 * 1.3 + 24,
                x = xadjustment,
                y = 145,
                cornerRadius = { x1 = 4, y1 = 4, x2 = 0, y2 = 0 },
                halign = halign,

                flow = "vertical",

                gui.Panel {
                    bgimage = true,
                    bgcolor = Styles.RichBlack02,
                    width = "100%",
                    height = 24,
                    halign = "center",
                    valign = "top",
                    cornerRadius = { x1 = 4, y1 = 4, x2 = 0, y2 = 0 },

                    flow = "horizontal",

                    gui.Label {
                        text = member.description,
                        fontFace = "newzald",
                        lmargin = 5,
                        fontSize = 10,
                        width = 140,
                        textWrap = false,
                        textOverflow = "ellipsis",
                        height = "100%",
                        bold = true,
                    },

                    gui.Label {
                        text = "",
                        fontFace = "newzald",
                        halign = "right",
                        fontSize = 10,
                        rmargin = 5,
                        width = "auto",
                        height = "100%",
                        bold = true,


                        create = function(element)
                            if document.summary ~= nil then
                                element.text = document.summary["npages"]
                            else
                                element:ScheduleEvent("create", 0.01)
                            end
                        end
                    },
                },

                gui.Panel {
                    bgimage = document:GetPageThumbnailId(0),
                    bgcolor = "white",
                    width = "100%",
                    height = "100%-24",
                    halign = "center",
                    valign = "top",

                },
            }

            element.parent.tooltip:MakeNonInteractiveRecursive()
        end,
    }
end

CreateJournalPanel = function(options)
    options = options or {}

    --The recent-documents strip is dock furniture: three 130px cards do not
    --fit an embedded host such as the 250px tree rail. Built with a real
    --if, NOT cond() -- cond evaluates both branches, which would construct
    --the cards and leave them parentless. An empty placeholder rather than
    --nil, because a nil hole in the positional child list truncates it and
    --would drop the tree panel that follows.
    local recentDocumentsPanel
    if options.embedded then
        recentDocumentsPanel = gui.Panel {
            width = "100%",
            height = 0,
        }
    else
        recentDocumentsPanel = gui.Panel {
            flow = "horizontal",
            bgcolor = "clear",
            width = "100%",
            height = 130,

            MakeRecentDocumentPanel(1),
            MakeRecentDocumentPanel(2),
            MakeRecentDocumentPanel(3),
        }
    end

    local journalPanel
    journalPanel = gui.Panel {
        id = "journalPanel",
        --classed so descendants can find the root regardless of how deeply
        --the lazily-built tree nests them (see the document row's click).
        classes = { "journalPanelRoot" },
        width = "100%",
        height = "100%",
        flow = "vertical",

        data = {
            foldersToMembers = {},

            --A copy of assets.documentFoldersTable with added built-in tables.
            documentFoldersTable = {},

            --Set when this panel is FRAMED somewhere other than its dock
            --(the journal viewer's tree rail). onPick replaces "open the
            --document in a dialog" with the host's own navigation.
            onPick = options.onPick,
        },


        --built above; nil (and so absent) when embedded.
        recentDocumentsPanel,

        gui.Panel {
            vscroll = true,
            flow = "vertical",
            width = "100%",
            height = "100% available",

            --TREE LAYOUT MODEL: a classic ladder. Indentation comes from
            --exactly one place: each folder's contents panel (see
            --CreateFolderContentsPanel) indents ALL its children -- doc
            --rows and subfolder headers alike -- by one 16px step (8px at
            --the root, which is the gutter). Inside a row the grammar is
            --fixed: [expander slot 18px][icon][name], where the expander
            --slot is a folder's toggle triangle, a doc row's bookmark
            --triangle, or a ghosted triangle when the row cannot expand.
            --So expanders align at +5, and doc icons align with sibling
            --folder LABELS at +22. Do not add per-depth or per-kind
            --margins on top of this.
            styles = ThemeEngine.MergeTokens({
                {
                    selectors = { "icon" },
                    width = 16,
                    height = 16,
                    bgcolor = "@fg",
                    valign = "center",
                    hmargin = 4,
                },
                {
                    selectors = { "itemContainer" },
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                },
                {
                    selectors = { "item" },
                    width = "100%",
                    height = 20,
                    bgimage = "panels/square.png",
                    bgcolor = "clear",
                    flow = "horizontal",
                },
                {
                    selectors = { "label" },
                    color = "@fg",
                    fontSize = 14,
                    hmargin = 4,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
                --Anchor row children left EXPLICITLY: a horizontal-flow
                --child with no alignment centers itself in the icon-rail
                --window host (the dock resolves it left), and mixed
                --alignments overlap. Scoped to parent:item so labels
                --outside the tree rows are untouched.
                {
                    selectors = { "icon", "parent:item" },
                    halign = "left",
                },
                {
                    selectors = { "label", "parent:item" },
                    halign = "left",
                    lmargin = 4,
                },
                --small gap between a header's expand triangle and its
                --name; 4 here (after the triangle's own 5px margin) also
                --puts folder labels at +22, flush with doc-row icons.
                {
                    selectors = { "folderLabel" },
                    lmargin = 4,
                },
                --a ghosted expander holds its 18px slot in the row but is
                --invisible and never highlights (rows that cannot expand;
                --see the doc-row triangle in CreateFolderContentsPanel).
                {
                    priority = 10,
                    selectors = { "triangle", "ghost" },
                    bgcolor = "clear",
                },
                {
                    selectors = { "item", "hover" },
                    bgcolor = "@fgStrong",
                },
                {
                    selectors = { "label", "parent:hover" },
                    color = "@bg",
                },
                {
                    selectors = { "icon", "parent:hover" },
                    bgcolor = "@bg",
                },
                {
                    priority = 5,
                    selectors = { "folder" },
                    bgcolor = "@bg",
                },
                {
                    priority = 6,
                    selectors = { "folder", "parent:subfolder" },
                    bgcolor = "@bgAlt",
                },
                {
                    priority = 5,
                    selectors = { "folder", "hover" },
                    bgcolor = "@fgStrong",
                    color = "@bg",
                },
                {
                    priority = 5,
                    selectors = { "folder", "drag-target" },
                    bgcolor = "@fgStrong",
                    color = "@bg",
                },
                {
                    priority = 5,
                    selectors = { "folder", "drag-target-hover" },
                    brightness = 2,
                },
                {
                    selectors = {"dragDocumentSiblingSpacer"},
                    width = "100%",
                    height = 2,
                    valign = "top",
                    bgimage = "panels/square.png",
                    bgcolor = "clear",
                },
                {
                    selectors = {"dragDocumentSiblingSpacer", "drag-target-hover"},
                    bgcolor = "@accent",
                },
                {
                    selectors = {"dragDocumentSiblingSpacer", "parent:dragging"},
                    collapsed = 1,
                },
                {
                    priority = 5,
                    selectors = { "folderLabel" },
                    color = "@fg",
                    fontSize = 14,
                },
                {
                    priority = 5,
                    selectors = { "folderLabel", "parent:hover" },
                    color = "@bg",
                },
                {
                    priority = 5,
                    selectors = { "folderLabel", "parent:drag-target" },
                    color = "@bg",
                },
                {
                    priority = 6,
                    selectors = { "folderLabel", "parent:subfolder" },
                    color = "@fgMuted",
                },
                {
                    priority = 6,
                    selectors = { "folderLabel", "parent:subfolder", "parent:hover" },
                    color = "@fgStrong",
                },
                {
                    priority = 6,
                    selectors = { "folderLabel", "parent:subfolder", "parent:drag-target" },
                    color = "@fgStrong",
                },
                {
                    priority = 6,
                    selectors = { "folderLabel", "parent:subfolder", "parent:press" },
                    color = "@fgStrong",
                },
                {
                    priority = 6,
                    selectors = { "folderLabel", "parent:subfolder", "parent:expanded" },
                    color = "@fgStrong",
                },
                {
                    priority = 5,
                    selectors = { "triangle" },
                    bgcolor = "@fg",
                },
                {
                    priority = 5,
                    selectors = { "triangle", "parent:hover" },
                    bgcolor = "@bg",
                },
                {
                    priority = 5,
                    selectors = { "triangle", "parent:drag-target" },
                    bgcolor = "@bg",
                },
                {
                    priority = 5,
                    selectors = { "triangle", "empty" },
                    bgcolor = "@fgMuted",
                },
                {
                    priority = 6,
                    selectors = { "triangle", "parent:subfolder" },
                    bgcolor = "@fgMuted",
                },
                {
                    priority = 6,
                    selectors = { "triangle", "parent:subfolder", "parent:hover" },
                    bgcolor = "@fgStrong",
                },
                {
                    priority = 6,
                    selectors = { "triangle", "parent:subfolder", "parent:drag-target" },
                    bgcolor = "@fgStrong",
                },
                {
                    priority = 6,
                    selectors = { "triangle", "parent:subfolder", "parent:press" },
                    bgcolor = "@fgStrong",
                },
                {
                    priority = 6,
                    selectors = { "triangle", "parent:subfolder", "parent:expanded" },
                    bgcolor = "@fgStrong",
                },
            }),


            create = function(element)
                element.children = {
                    CreateFolderContentsPanel(journalPanel, ""),
                }
                element:FireEvent("refreshAssets")
            end,

            monitorAssets = { "documents", "images", "objecttables" },
            refreshAssets = function(element)
                journalPanel.data.documentFoldersTable = {
                    public = {
                        description = "Shared Documents",
                        parentFolder = "",
                        nodeType = "builtinFolder",
                    },
                }

                if dmhub.isDM then
                    journalPanel.data.documentFoldersTable.templates = {
                        description = "Templates",
                        parentFolder = "",
                        nodeType = "builtinFolder",
                    }

                    journalPanel.data.documentFoldersTable.private = {
                        description = "Private Documents",
                        parentFolder = "",
                        nodeType = "builtinFolder",
                    }

                    journalPanel.data.documentFoldersTable[game.currentMapId] = {
                        description = "Map Documents",
                        parentFolder = "",
                        nodeType = "builtinFolder",
                    }
                else
                    journalPanel.data.documentFoldersTable[dmhub.loginUserid] = {
                        description = "My Private Documents",
                        parentFolder = "",
                        nodeType = "builtinFolder",
                    }
                end

                local documentFolders = journalPanel.data.documentFoldersTable

                for k, v in pairs(assets.documentFoldersTable) do
                    if not v.hidden then
                        documentFolders[k] = v
                    end
                end

                local foldersToMembers = {}

                local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}

                local docs = assets.pdfDocumentsTable
                for k, doc in pairs(docs or {}) do
                    if not doc.hidden then
                        local parentFolder = doc.parentFolder or "private"
                        local members = foldersToMembers[parentFolder] or {}
                        members[k] = doc
                        foldersToMembers[parentFolder] = members
                    end
                end

                local images = assets.imagesByTypeTable.Document
                for k, image in pairs(images or {}) do
                    if not image.hidden then
                        local parentFolder = image.parentFolder or "private"
                        local members = foldersToMembers[parentFolder] or {}
                        members[k] = image
                        foldersToMembers[parentFolder] = members
                    end
                end

                local fragments = dmhub.GetTable(PDFFragment.tableName) or {}
                for k, fragment in unhidden_pairs(fragments) do
                    local parentFolder = fragment.parentFolder or "private"
                    local members = foldersToMembers[parentFolder] or {}
                    members[k] = fragment
                    foldersToMembers[parentFolder] = members
                    print("FRAGMENT::", k, fragment.description)
                end

                for k, doc in unhidden_pairs(customDocs) do
                    local parentFolder = doc.parentFolder
                    local members = foldersToMembers[parentFolder] or {}
                    members[k] = doc
                    foldersToMembers[parentFolder] = members
                end

                for k, folder in pairs(documentFolders) do
                    local parentFolder = folder.parentFolder or "private"
                    local members = foldersToMembers[parentFolder] or {}
                    members[k] = folder
                    foldersToMembers[parentFolder] = members
                end

                journalPanel.data.foldersToMembers = foldersToMembers

                element:FireEventTree("refreshDocuments")
            end,
        },

        gui.Panel {
            width = "auto",
            height = 32,
            halign = "right",
            hmargin = 12,
            flow = "horizontal",

            gui.Button {
                classes = { "sizeM" },
                halign = "right",
                icon = "game-icons/open-folder.png",
                linger = gui.Tooltip("Create a new folder"),
                press = function(element)
                    assets:UploadNewDocumentFolder {
                        description = "Documents",
                    }
                end,
            },

            gui.Button {
                classes = {"addButton", "sizeM"},
                halign = "right",
                valign = "center",
                click = function(element)
                    if element.popup ~= nil then
                        element.popup = nil
                        return
                    end

                    local newDocumentParentFolder = "private"
                    if not dmhub.isDM then
                        newDocumentParentFolder = dmhub.loginUserid
                    end

                    local entries = {}

                    for k, v in pairs(CustomDocument.documentTypes) do
                        entries[#entries + 1] = {
                            text = v.text,
                            click = function()
                                element.popup = nil
                                local doc = v.create()
                                doc.id = dmhub.GenerateGuid()
                                if not dmhub.isDM then
                                    doc.ownerid = dmhub.loginUserid
                                end
                                doc.parentFolder = newDocumentParentFolder
                                doc:ShowCreateDialog()
                            end,
                        }
                    end

                    entries[#entries + 1] = {
                        text = "Upload Document",
                        click = function()
                            element.popup = nil

                            dmhub.OpenFileDialog {
                                id = "PDF",
                                extensions = { "pdf", "png", "jpg", "jpeg", "webp" },
                                multiFiles = false,
                                prompt = "Choose an image or a PDF document file",
                                open = function(path)
                                    if path == nil then
                                        return
                                    end
                                    if string.ends_with(string.lower(path), "pdf") then
                                        ImportPDFDialog(path)
                                    else
                                        --get the filename without extension or folder.
                                        local filename = string.match(path, "([^/\\]+)$")
                                        filename = string.match(filename, "(.+)%..+$") or filename
                                        assets:UploadImageAsset {
                                            description = filename,
                                            path = path,
                                            imageType = "document",
                                            parentFolder = newDocumentParentFolder,

                                            progress = function(r)
                                                --element.progress = r
                                                --element:Update()
                                            end,
                                            upload = function(guid)
                                                --element.progress = 1
                                                --element:Update()
                                            end,
                                            error = function(msg)
                                                gui.ModalMessage {
                                                    title = "Error importing image",
                                                    message = msg,
                                                }
                                            end,
                                        }
                                    end
                                end,
                            }
                        end,
                    }

                    element.popupPositioning = "panel"
                    element.popup = gui.ContextMenu {
                        entries = entries,
                        valign = "top",
                    }
                end,
            }
        }
    }

    return journalPanel
end
