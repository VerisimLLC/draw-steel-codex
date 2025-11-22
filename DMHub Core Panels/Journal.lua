local mod = dmhub.GetModLoading()

local CreateJournalPanel

local docid = "journal"

RegisterGameType("CustomDocument")

Commands.doc = function(str)
    local args = str:split(" ")

    if #args == 0 then
        print("Provide document as argument.")
        return
    end

    local doc = assets.pdfDocumentsTable[args[1]]
    if doc == nil then
        print("Document not found.")
        return
    end

    local page = tonumber(args[2])

    mod.shared.ShowPDFViewerDialog(doc, page)
end


local g_adventureDocumentId = "adventureDocs"

function GetCurrentAdventuresDocument()
    local doc = mod:GetDocumentSnapshot(g_adventureDocumentId)
    return doc
end

Commands.setadventuredocument = function(str)
    if str == "help" then
        dmhub.Log(
            "Usage: /setadventuredocument <slotnumber> <document name>\n Sets the given slot number to the given document name as the current adventure document.")
        return
    end

    local args = Commands.SplitArgs(str)
    if #args ~= 2 or tonumber(args[1]) == nil then
        print("LINK:: INVALID")
        return
    end

    local slot = tonumber(args[1])
    if slot ~= 1 and slot ~= 2 then
        dmhub.Log("Only slots 1 and 2 are valid for adventure documents.")
        return
    end

    local name = string.lower(args[2])

    local customDocs = dmhub.GetTable(CustomDocument.tableName) or {}
    for k, doc in unhidden_pairs(customDocs) do
        if string.lower(doc.name) == name then
            local doc = mod:GetDocumentSnapshot(g_adventureDocumentId)
            doc:BeginChange()
            local slots = doc.data.slots or {}
            doc.data.slots = slots
            slots[string.format("slot%d", slot)] = k
            doc:CompleteChange("Change variable")
            print("LINK:: Changed mod document")
            return
        end
    end

    print("LINK:: COULD NOT FIND DOC", name)
end



DockablePanel.Register {
    name = "Journal",
    icon = "icons/standard/Icon_App_Journal.png",
    vscroll = false,
    dmonly = false,
    minHeight = 160,
    content = function()
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
        styles = {
            Styles.Default,
            Styles.Panel,
        },

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
                width = "auto",
                height = "auto",
                fontSize = 14,
                create = function(element)
                    element.text = string.format("This file is %.1fMB\nBandwidth remaining this month: %.1fMB", pathSize,
                        allowedSize)
                    element:SetClass("error", allowedSize < pathSize)
                end,
            },
            gui.Label {
                classes = { "link" },
                width = "auto",
                height = "auto",
                fontSize = 14,
                text = "Support us on Patreon for more bandwidth.",
                click = function(element)
                    dmhub.OpenRegisteredURL("Patreon")
                end,
            },
        },

        gui.PrettyButton {
            valign = "bottom",
            halign = "center",
            width = 240,
            height = 40,
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

        gui.CloseButton {
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

local CreateFolderContentsPanel

local function CreateFolderPanel(journalPanel, folderid)
    local builtinFolder = folderid == "private" or folderid == "public" or folderid == "templates" or folderid == "adventure" or
        folderid == game.currentMapId or folderid == dmhub.loginUserid
    local m_contentPanel = CreateFolderContentsPanel(journalPanel, folderid)

    if folderid == "adventure" then
        return m_contentPanel
    end

    local resultPanel
    resultPanel = gui.TreeNode {
        classes = { "documentFolder" },
        editable = not builtinFolder,
        width = "100%",
        dragTarget = true,
        dragTargetPriority = 100,
        data = {
            folderid = folderid,
        },

        expanded = builtinFolder,

        draggable = not builtinFolder,
        canDragOnto = function(element, target)
            return target ~= nil and (target:HasClass("folder") or target:HasClass("contentPanel")) and
                target:FindParentWithClass("documentFolder") ~= nil
        end,
        drag = function(element, target)
            if target == nil then
                return
            end

            target = target:FindParentWithClass("documentFolder")
            if target == nil then
                return
            end

            local folders = journalPanel.data.documentFoldersTable
            local folder = folders[folderid]
            if folder == nil then
                return
            end

            folder.parentFolder = target.data.folderid
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

local g_adventurePanelStyles = {
    gui.Style{
        selectors = {"label"},
        bold = true,
        fontSize = 22,
    }
}

CreateFolderContentsPanel = function(journalPanel, folderid)
    local m_documentPanels = {}
    local contentPanel
    local m_invalidated = true

    local dragTarget = folderid ~= "adventure"

    local styles
    if folderid == "adventure" then
        styles = g_adventurePanelStyles
    end


    contentPanel = gui.Panel {
        width = "100%+12", --make it take the whole space of the parent + scrollbar area
        height = "auto",
        flow = "vertical",
        dragTarget = dragTarget,
        dragTargetPriority = 1,
        styles = styles,
        classes = { "contentPanel" },
        x = cond(folderid == "", 0, 8),

        expand = function(element)
            if m_invalidated then
                element:FireEventTree("refreshDocuments")
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

                if member.nodeType == "pdf" or member.nodeType == "image" or member.nodeType == "pdffragment" or member.nodeType == "custom" then
                    p = m_documentPanels[k] or gui.Panel {
                        draggable = dragTarget,
                        hover = function(element)
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
                            return target ~= nil and (target:HasClass("folder") or target:HasClass("contentPanel")) and
                                target:FindParentWithClass("documentFolder") ~= nil
                        end,
                        drag = function(element, target)
                            if target == nil then
                                return
                            end

                            target = target:FindParentWithClass("documentFolder")
                            if target == nil then
                                return
                            end


                            element.data.doc.parentFolder = target.data.folderid
                            element.data.doc:Upload()
                        end,
                        data = {
                            showBookmarks = false,

                        },
                        classes = { "itemContainer" },
                        click = function(element)
                            CustomDocument.OpenContent(member)
                        end,

                        rightClick = function(element)
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
                                    text = "Rename",
                                    hidden = not member:HaveEditPermissions(),
                                    click = function()
                                        element.popup = nil
                                        element:FireEventTree("rename")
                                    end,
                                },
                                {
                                    text = "Delete",
                                    hidden = not member:HaveEditPermissions(),
                                    click = function()
                                        element.popup = nil
                                        element.data.doc.hidden = true
                                        element.data.doc:Upload()
                                    end,
                                }
                            }

                            if member.nodeType == "pdf" then
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

                            element.popup = gui.ContextMenu {
                                entries = entries,
                            }
                        end,


                        refreshDoc = function(element, doc)
                            local parentElement = element
                            element.data.ord = string.lower("b" .. doc.description)
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
                                    element.data.ord = string.format("b%09d-%s", ord, doc.description)
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
                                    children = { children[1] }
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
                                            x = 8,
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

                                table.insert(children, 1, element.children[1])

                                element.data.bookmarks = newBookmarks
                                element.children = children

                                element:FireEventTree("updateBookmarks", bookmarks)
                            end
                        end, --end refreshDoc

                        gui.Panel {
                            classes = { "item" },

                            gui.Panel {
                                bgimage = 'panels/triangle.png',
                                classes = { "triangle", "collapsed" },
                                styles = gui.TriangleStyles,

                                refreshDoc = function(element, doc)
                                    element:SetClass("collapsed", doc.bookmarks == nil or next(doc.bookmarks) == nil)
                                end,

                                press = function(element)
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
                            gui.Label{
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
                                        element.bgimage = cond(member.nodeType == "pdf", "icons/icon_app/icon_app_137.png", "icons/icon_app/icon_app_34.png") --choose pdf or image icon.
                                    end
                                end,
                            },
                            gui.Label {
                                data = {},
                                characterLimit = 64,
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
                    p.data.ord = string.lower("a" .. member.description)
                end


                newDocumentPanels[k] = p
                children[#children + 1] = p
            end

            table.sort(children, function(a, b) return a.data.ord < b.data.ord end)

            m_documentPanels = newDocumentPanels
            element.children = children

            contentPanel:SetClass("empty", #children == 0)
        end,
    }

    return contentPanel
end

CreateJournalPanel = function()
    local journalPanel
    journalPanel = gui.Panel {
        id = "journalPanel",
        width = "100%",
        height = "100%",
        flow = "vertical",

        data = {
            foldersToMembers = {},

            --A copy of assets.documentFoldersTable with added built-in tables.
            documentFoldersTable = {},
        },

        gui.Panel {
            vscroll = true,
            flow = "vertical",
            width = "100%",
            height = "100% available",

            styles = {
                {
                    selectors = { "icon" },
                    width = 16,
                    height = 16,
                    bgcolor = Styles.textColor,
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
                    color = Styles.textColor,
                    fontSize = 14,
                    hmargin = 4,
                    width = "auto",
                    height = "auto",
                    valign = "center",
                },
                {
                    selectors = { "item", "hover" },
                    bgcolor = Styles.textColor,
                },
                {
                    selectors = { "label", "parent:hover" },
                    color = "black",
                },
                {
                    selectors = { "icon", "parent:hover" },
                    bgcolor = "black",
                },
                {
                    priority = 5,
                    selectors = { "folder" },
                    bgcolor = "black",
                },
                {
                    priority = 5,
                    selectors = { "folder", "hover" },
                    bgcolor = Styles.textColor,
                    color = "black",
                },
                {
                    priority = 5,
                    selectors = { "folder", "drag-target" },
                    bgcolor = Styles.textColor,
                    color = "black",
                },
                {
                    priority = 5,
                    selectors = { "folder", "drag-target-hover" },
                    brightness = 2,
                },
                {
                    priority = 5,
                    selectors = { "folderLabel" },
                    color = Styles.textColor,
                    fontSize = 14,
                },
                {
                    priority = 5,
                    selectors = { "folderLabel", "parent:hover" },
                    color = "black",
                },
                {
                    priority = 5,
                    selectors = { "folderLabel", "parent:drag-target" },
                    color = "black",
                },
                {
                    priority = 5,
                    selectors = { "triangle" },
                    bgcolor = Styles.textColor,
                },
                {
                    priority = 5,
                    selectors = { "triangle", "parent:hover" },
                    bgcolor = "black",
                },
                {
                    priority = 5,
                    selectors = { "triangle", "parent:drag-target" },
                    bgcolor = "black",
                },
                {
                    priority = 5,
                    selectors = { "triangle", "empty" },
                    bgcolor = "grey",
                },
            },


            create = function(element)
                element.children = {
                    CreateFolderContentsPanel(journalPanel, ""),
                }
                element:FireEvent("refreshAssets")
            end,

            monitorGame = cond(dmhub.isDM, mod:GetDocumentSnapshot(g_adventureDocumentId).path),
            monitorGameEvent = "refreshAssets",

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
                    journalPanel.data.documentFoldersTable.adventure = {
                        description = "Current Adventure",
                        parentFolder = "",
                        nodeType = "builtinFolder",
                    }

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
                if dmhub.isDM then
                    local adventureDocuments = mod:GetDocumentSnapshot(g_adventureDocumentId)
                    if adventureDocuments ~= nil and adventureDocuments.data ~= nil and adventureDocuments.data.slots ~= nil then
                        for i=1,2 do
                            local key = string.format("slot%d", i)
                            local docid = adventureDocuments.data.slots[key]
                            if docid ~= nil and docid ~= "" then
                                local doc = customDocs[docid]
                                if doc ~= nil and not doc.hidden then
                                    local parentFolder = "adventure"
                                    local members = foldersToMembers[parentFolder] or {}
                                    members[docid] = doc
                                    foldersToMembers[parentFolder] = members
                                end
                            end
                        end
                    end
                end

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
            width = "100%",
            height = 32,
            flow = "horizontal",

            gui.Panel {
                classes = { "clickableIcon" },
                width = 24,
                height = 24,
                halign = "right",
                bgimage = "game-icons/open-folder.png",
                linger = gui.Tooltip("Create a new folder"),
                press = function(element)
                    assets:UploadNewDocumentFolder {
                        description = "Documents",
                    }
                end,
            },

            gui.AddButton {
                halign = "right",
                valign = "center",
                width = 24,
                height = 24,
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
