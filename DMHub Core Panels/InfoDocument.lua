local mod = dmhub.GetModLoading()

---@class InfoDocument
---@field docid string|false a reference to a markdown document in the journal.
InfoDocument = RegisterGameType("InfoDocument")
RegisterGameType("InfoDocumentSection")

--a reference to a markdown document in the journal.
InfoDocument.docid = false
InfoDocument.sections = {}

function InfoDocument:GetMarkdownDocument()
    local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[self.docid]
    return doc
end

function InfoDocument.OnDeserialize(self)
    self:get_or_add("ord", 0)
end

function InfoDocument:AddSection()
    self.sections[#self.sections + 1] = InfoDocumentSection.new {
        title = "Description",
        text = "",
    }
end

--called by DMHub to validate an info document is valid.
function IsValidInfoDocument(doc)
    return doc ~= nil and doc.typeName == "InfoDocument"
end

--called by DMHub to create an info document.
function CreateInfoDocument(description)
    local maxOrd = 1
    for k, p in pairs(dmhub.infoBubbles) do
        if p.document ~= nil and p.document.ord ~= nil and p.document.ord > maxOrd then
            maxOrd = p.document.ord
        end
    end

    local docid = dmhub.GenerateGuid()
    local description = description or "Room 1"
    local markdownDoc = MarkdownDocument.new {
        id = docid,
        description = description or "Room 1",
        parentFolder = game.currentMapId,
        content = "# " .. description,
        annotations = {},
    }

    markdownDoc:ShowCreateDialog()
    dmhub.SetAndUploadTableItem(MarkdownDocument.tableName, markdownDoc)

    return InfoDocument.new {
        ord = maxOrd + 1,
        docid = docid,
    }
end

function GameHud:CreateDocumentsPanel()
    local result = gui.Panel {
        id = 'document-dialog-panel',
        bgimage = 'panels/square.png',
        interactable = false,

        styles = {
            {
                width = self.dialog.width,
                height = self.dialog.height,
                valign = 'center',
                halign = 'center',
                bgcolor = 'clear',
            },
            {
                selectors = { 'document-dialog' },
                priority = 5,
                valign = 'top',
                halign = 'left',
                cornerRadius = 12,
                borderColor = 'black',
                borderWidth = 2,
                bgcolor = 'grey',
            },
        }
    }

    self.documentsPanel = result

    return result
end

function GameHud:CreateDocumentDialog()
    local dialogWidth = 700
    local dialogHeight = 800
    local resultPanel
    local mainPanel

    local currentInfo

    local leftPanelChildren = {}
    local leftPanel = gui.Panel {
        classes = { 'left-panel' },
        vscroll = true,

        events = {
            refreshBubbleDocument = function(element, info)
                local children = {}
                local newLeftPanelChildren = {}

                local bubbles = dmhub.infoBubbles
                local bubblesSorted = {}

                for k, bubble in pairs(bubbles) do
                    if bubble.document ~= nil then
                        bubblesSorted[#bubblesSorted + 1] = bubble
                    end
                end

                table.sort(bubblesSorted, function(a, b)
                    return a.document.ord < b.document.ord
                end)

                for i, bubble in ipairs(bubblesSorted) do
                    local id = bubble.id
                    local child = leftPanelChildren[bubble.id] or gui.Panel {
                        bgimage = 'panels/square.png',
                        classes = { 'left-panel-child' },
                        flow = "horizontal",

                        gui.Label {
                            classes = { 'left-panel-child-bubble' },
                            x = -4,
                            text = bubble.icon,
                            refreshBubbleDocument = function(element, info)
                                element.text = bubble.icon
                            end,
                        },


                        gui.Label {
                            classes = { 'left-panel-child-label' },
                            text = bubble.description,
                            refreshBubbleDocument = function(element, info)
                                element.text = bubble.description
                            end,
                        },

                        events = {
                            press = function(element)
                                resultPanel:FireEvent('refreshBubbleDocument', dmhub.infoBubbles[id])
                            end,
                            refreshBubbleDocument = function(element, info)
                                element:SetClassTree('selected', id == info.id)
                            end,
                            rightClick = function(element)
                                local currentInfo = dmhub.infoBubbles[id]
                                local maxOrd = nil
                                local minOrd = nil
                                for k, p in pairs(dmhub.infoBubbles) do
                                    if p.document ~= nil and p.document.ord ~= nil and (maxOrd == nil or p.document.ord > maxOrd) then
                                        maxOrd = p.document.ord
                                    end

                                    if p.document ~= nil and p.document.ord ~= nil and (minOrd == nil or p.document.ord < minOrd) then
                                        minOrd = p.document.ord
                                    end
                                end

                                local options = {
                                    {
                                        text = "Move to Top",
                                        click = function()
                                            currentInfo:BeginChanges()
                                            currentInfo.document.ord = minOrd-1
                                            currentInfo:CompleteChanges('Add Info Bubble Section')
                                            resultPanel:FireEventTree('refreshBubbleDocument', currentInfo)
                                            element.popup = nil
                                        end,
                                    },
                                    {
                                        text = "Move to Bottom",
                                        click = function()
                                            currentInfo:BeginChanges()
                                            currentInfo.document.ord = maxOrd+1
                                            currentInfo:CompleteChanges('Add Info Bubble Section')
                                            resultPanel:FireEventTree('refreshBubbleDocument', currentInfo)
                                            element.popup = nil
                                        end,
                                    }
                                }

                                element.popup = gui.ContextMenu{
                                    width = 180,
                                    entries = options,
                                }
                            end,
                        },
                    }
                    newLeftPanelChildren[bubble.id] = child
                    children[#children + 1] = child

                    child:SetClass('selected', bubble.id == info.id)
                end

                leftPanelChildren = newLeftPanelChildren
                element.children = children
            end,
        }
    }

    local title = gui.Label {
        bgimage = 'panels/square.png',
        editable = true,
        selfStyle = {
            fontSize = 20,
            color = 'white',
            bgcolor = 'clear',
            borderWidth = 0,

            minWidth = 100,
            width = 'auto',
            height = 'auto',
            halign = 'center',
            valign = 'top',
        },
        events = {
            refreshBubbleDocument = function(element, info)
                element.text = info.description
            end,
            change = function(element)
                currentInfo.description = element.text
                resultPanel:FireEventTree('refreshBubbleDocument', currentInfo)

                local doc = currentInfo.document:GetMarkdownDocument()
                if doc ~= nil then
                    doc.description = element.text
                    dmhub.SetAndUploadTableItem(MarkdownDocument.tableName, doc)
                end
            end,
        }
    }

    local bubbleIcon = gui.Label {
        bgimage = 'panels/square.png',
        characterLimit = 3,
        editable = true,
        selfStyle = {
            bgcolor = 'black',
            color = 'white',
            cornerRadius = '50% height',
            borderColor = 'white',
            borderWidth = 1,
            width = 25,
            height = 25,
            fontSize = 13,
            halign = "center",
            valign = "center",
            textAlignment = "center",
        },
        events = {
            refreshBubbleDocument = function(element, info)
                element.text = info.icon
            end,
            change = function(element)
                currentInfo.icon = element.text
            end,
        },
    }

    local lockIcon = gui.Panel {
        width = 16,
        height = 16,
        bgcolor = "white",
        selfStyle = {
            bgimage = "panels/square.png",
        },
        linger = gui.Tooltip("Unlock to allow dragging on the map"),
        refreshBubbleDocument = function(element, info)
            element.selfStyle.bgimage = cond(info.locked, 'icons/icon_tool/icon_tool_30.png',
                'icons/icon_tool/icon_tool_30_unlocked.png')
        end,

        press = function(element)
            currentInfo.locked = not currentInfo.locked
            element:FireEvent("refreshBubbleDocument", currentInfo)
        end,
    }

    local titlePanel = gui.Panel {
        selfStyle = {
            flow = 'horizontal',
            width = 'auto',
            height = 'auto',
            pad = 0,
            tmargin = 4,
            valign = 'top',
        },
        children = {
            title,
            --padding.
            gui.Panel {
                width = 8,
                height = 8,
            },
            bubbleIcon,
            --padding.
            gui.Panel {
                width = 30,
                height = 8,
            },
            lockIcon,
        }
    }

    local addPanel = gui.Label {
        bgimage = 'panels/square.png',
        text = '+',
        classes = { 'document-add' },
        events = {
            click = function(element)
                currentInfo:BeginChanges()
                currentInfo.document:AddSection()
                currentInfo:CompleteChanges('Add Info Bubble Section')
                resultPanel:FireEventTree('refreshBubbleDocument', currentInfo)
            end,
        },
    }

    local documentPanel = gui.Panel {
        bgimage = 'panels/square.png',
        classes = { 'document-panel' },
        vscroll = true,
        events = {
            refreshBubbleDocument = function(element, info)
                local children = {}
                for i, entry in ipairs(info.document.sections) do
                    local index = i
                    children[#children + 1] = gui.Panel {
                        bgimage = 'panels/square.png',
                        classes = { 'document-entry' },
                        children = {
                            gui.Label {
                                id = 'document-title',
                                editable = true,
                                classes = { 'document-title' },
                                text = entry.title,
                                events = {
                                    change = function(element)
                                        info:BeginChanges()
                                        info.document.sections[index].title = element.text
                                        info:CompleteChanges("Update Info Bubble Title")
                                    end,
                                },
                            },
                            gui.Input {
                                classes = { 'document-body' },
                                text = entry.text,
                                placeholderText = 'Enter info...',
                                multiline = true,
                                events = {
                                    change = function(element)
                                        info:BeginChanges()
                                        info.document.sections[index].text = element.text
                                        info:CompleteChanges("Update Info Bubble Text")
                                    end,
                                },
                            },
                            gui.DeleteItemButton {
                                floating = true,
                                width = 16,
                                rmargin = 4,
                                tmargin = 4,
                                height = 16,
                                halign = "right",
                                valign = "top",

                                events = {
                                    click = function(element)
                                        info:BeginChanges()
                                        table.remove(info.document.sections, index)
                                        info:CompleteChanges("Remove Info Bubble Section")
                                        resultPanel:FireEvent('refreshBubbleDocument', dmhub.infoBubbles[currentInfo.id])
                                    end,
                                },
                            },
                        },
                    }
                end
                element.children = children
            end
        },
    }

    local mainInnerPanel = gui.Panel {
        classes = { 'main-inner-panel' },
        children = { titlePanel, documentPanel },
    }

    local closeButton = gui.CloseButton {
        escapeActivates = true,
        valign = 'top',
        halign = 'right',
        events = {
            click = function(element)
                resultPanel:SetClass('hidden', true)
            end,
        },

        refreshBubbleDocument = function(element, info)
            if info.document.docid then
                element.selfStyle.collapsed = 1
            else
                element.selfStyle.collapsed = 0
            end
        end,
    }


    local dialogPanel

    local function createDocInterfaceArgs(docId)
        return {
            dialogPanel = dialogPanel,
            close = function(element)
                closeButton:FireEvent("click")
            end,
            titlePanel = gui.Panel {
                selfStyle = {
                    flow = 'horizontal',
                    width = 'auto',
                    height = 'auto',
                    pad = 0,
                    tmargin = 4,
                    lmargin = 20,
                    halign = "left",
                    valign = 'top',
                },
                children = {
                    title,
                    gui.Panel { width = 8, height = 8 },
                    bubbleIcon,
                    gui.Panel { width = 30, height = 8 },
                    lockIcon,
                }
            }
        }
    end

    local customDocPanel = gui.Panel {
        data = {
            docid = false,
            interfacePanel = nil,
        },
        width = "100%-4",
        height = "100%",
        rmargin = 4,
        refreshBubbleDocument = function(element, info)
            if info.document.docid then
                local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[info.document.docid]
                if doc ~= nil then
                    -- Reset history when switching entries
                    if dialogPanel then
                        dialogPanel.data.history = {}
                        dialogPanel.data.forwardHistory = {}
                        dialogPanel.data.currentDocId = info.document.docid
                    end

                    element.data.interfacePanel = doc:CreateInterface(createDocInterfaceArgs(info.document.docid))
                    element.children = { element.data.interfacePanel }
                    element.data.docid = info.document.docid
                end
            end
        end,
    }


    mainPanel = gui.Panel {
        classes = { 'main-panel' },
        children = { mainInnerPanel, addPanel, customDocPanel },
        refreshBubbleDocument = function(element, info)
            if info.document.docid then
                print("BUBBLE:: SHOW CUSTOM DOC PANEL")
                mainInnerPanel:SetClass("collapsed", true)
                addPanel:SetClass("collapsed", true)
                closeButton:SetClass("collapsed", true)
                customDocPanel:SetClass("collapsed", false)
            else
                mainInnerPanel:SetClass("collapsed", false)
                addPanel:SetClass("collapsed", false)
                closeButton:SetClass("collapsed", false)
                customDocPanel:SetClass("collapsed", true)
            end
        end,
    }

    dialogPanel = gui.Panel {
        classes = { "framedPanel" },
        valign = 'top',
        halign = 'left',
        blurBackground = true,
        opacity = 0.98,
        width = dialogWidth,
        height = dialogHeight,

        data = {
            history = {},
            forwardHistory = {},
            currentDocId = false,
        },

        navigateToDocument = function(element, docId)
            local docs = dmhub.GetTable(CustomDocument.tableName) or {}
            local newDoc = docs[docId]
            if newDoc == nil then return end

            element.data.history[#element.data.history + 1] = element.data.currentDocId
            element.data.forwardHistory = {}
            element.data.currentDocId = docId

            if customDocPanel.data.interfacePanel then
                customDocPanel.data.interfacePanel:DestroySelf()
            end
            customDocPanel.data.interfacePanel = newDoc:CreateInterface(createDocInterfaceArgs(docId))
            customDocPanel.children = { customDocPanel.data.interfacePanel }
            customDocPanel.data.docid = docId

            element:FireEventTree("refreshNavButtons")
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

            if customDocPanel.data.interfacePanel then
                customDocPanel.data.interfacePanel:DestroySelf()
            end
            customDocPanel.data.interfacePanel = prevDoc:CreateInterface(createDocInterfaceArgs(prevDocId))
            customDocPanel.children = { customDocPanel.data.interfacePanel }
            customDocPanel.data.docid = prevDocId

            element:FireEventTree("refreshNavButtons")
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

            if customDocPanel.data.interfacePanel then
                customDocPanel.data.interfacePanel:DestroySelf()
            end
            customDocPanel.data.interfacePanel = nextDoc:CreateInterface(createDocInterfaceArgs(nextDocId))
            customDocPanel.children = { customDocPanel.data.interfacePanel }
            customDocPanel.data.docid = nextDocId

            element:FireEventTree("refreshNavButtons")
        end,

        children = {
            leftPanel,
            mainPanel,
            closeButton,
            gui.DialogResizePanel(self, dialogWidth, dialogHeight),
        },
    }

    resultPanel = gui.Panel {
        draggable = true,
        x = -dialogWidth / 2,
        y = -dialogHeight / 2,
        events = {
            drag = function(element)
                element.x = element.xdrag
                element.y = element.ydrag
            end,

            refreshBubbleDocument = function(element, info)
                if info ~= nil then
                    currentInfo = info
                end

                if currentInfo == nil then
                    return
                end
                leftPanel:FireEventTree('refreshBubbleDocument', currentInfo)
                mainPanel:FireEventTree('refreshBubbleDocument', currentInfo)
            end,
        },
        selfStyle = {
            halign = 'center',
            valign = 'center',
            width = 1,
            height = 1,
        },

        styles = {
            Styles.Default,
            Styles.Panel,
            {
                selectors = { 'left-panel' },
                halign = 'left',
                height = '100%',
                valign = 'center',
                width = 220,
                x = -40,
                hmargin = 4,
                flow = 'vertical',
            },
            {
                selectors = { 'left-panel-child-label' },
                halign = 'left',
                width = "98%-56",
                height = 22,
                hmargin = 6,
                valign = "center",
                fontSize = 16,
                minFontSize = 12,
                color = Styles.textColor,
                textAlignment = 'left',
            },
            {
                selectors = { 'left-panel-child-label', 'selected' },
                color = "black",
            },
            {
                selectors = { 'left-panel-child-bubble' },
                halign = "left",
                valign = "center",
                width = 48,
                height = 48,
                bgimage = "panels/square.png",
                bgcolor = "black",
                borderWidth = 2,
                borderColor = Styles.textColor,
                cornerRadius = 24,
                textAlignment = "center",
                fontFace = "CrimsonText",
                fontSize = 32,
                minFontSize = 16,
            },
            {
                selectors = { 'left-panel-child-bubble', 'parent:hover' },
                bgcolor = Styles.textColor,
                color = "black",
            },
            {
                selectors = { 'left-panel-child' },
                flow = "horizontal",
                halign = 'left',
                valign = 'top',
                lmargin = 8,
                tmargin = 24,
                width = '95%',
                height = 26,
                y = -6,
                cornerRadius = 2,
                borderWidth = 2,
                borderColor = Styles.textColor,
                bgcolor = '#00000000',
            },
            {
                selectors = { 'left-panel-child', 'selected' },
                bgcolor = Styles.textColor,
            },
            {
                selectors = { 'left-panel-child', 'hover' },
            },
            {
                selectors = { 'left-panel-child', 'selected' },
            },
            {
                selectors = { 'main-inner-panel' },
                halign = "center",
                valign = "top",
                width = "100%-8",
                height = "100%-50",
                borderWidth = 2,
                borderColor = Styles.textColor,
                cornerRadius = 2,
                bgimage = "panels/square.png",
                bgcolor = "#00000000",
                flow = "vertical",
            },
            {
                selectors = { 'main-panel' },
                flow = 'vertical',
                width = '100%-180',
                height = '100%-12',
                halign = 'right',
                valign = 'center',
            },
            {
                selectors = { 'document-panel' },
                bgcolor = 'black',
                flow = 'vertical',
                width = '96%',
                height = '100%-70',
                valign = 'top',
                halign = 'center',
            },
            {
                selectors = { 'document-entry' },
                bgcolor = 'black',
                borderWidth = 2,
                borderColor = Styles.textColor,
                vmargin = 8,
                color = 'white',
                cornerRadius = 0,
                flow = 'vertical',
                halign = 'center',
                valign = 'top',
                width = '92%',
                height = 'auto',
                minHeight = 30,
            },
            {
                selectors = { 'document-add' },
                halign = "center",
                valign = 'top',
                bgcolor = 'black',
                color = Styles.textColor,
                cornerRadius = 2,
                borderWidth = 2,
                borderColor = Styles.textColor,
                tmargin = 8,
                width = '100%-8',
                height = 30,
                textAlignment = 'center',
                fontSize = 32,
            },
            {
                selectors = { 'document-add', 'hover' },
                borderColor = '#ffffff',
            },
            {
                selectors = { 'document-add', 'press' },
                borderColor = '#555555',
            },

            {
                selectors = { 'document-title' },
                priority = 10,
                color = Styles.textColor,
                fontSize = 14,
                vmargin = 4,
                hmargin = 4,
                halign = 'left',
                width = '80%',
                height = 24,
            },
            {
                priority = 10,
                selectors = { 'document-body' },
                borderWidth = 2,
                borderColor = Styles.textColor,
                color = Styles.textColor,
                vmargin = 4,
                width = '90%',
                height = 'auto',
                minHeight = 60,
                fontSize = 14,
                valign = 'center',
                halign = 'center',
                textAlignment = 'topleft',
            },
        },

        children = {
            dialogPanel,


        }
    }

    return resultPanel
end

function GameHud:IsDocumentDialogOpen()
    local documentDialog = self:try_get('documentDialog')
    if documentDialog == nil then
        return false
    end

    return not documentDialog:HasClass('hidden')
end

local loadid = dmhub.GenerateGuid()

function GameHud:DisplayDocument(info)
    local documentDialog = self:try_get('documentDialog')
    if documentDialog == nil or loadid ~= self:try_get("documentDialogLoadID") then
        if documentDialog ~= nil then
            documentDialog:DestroySelf()
        end

        documentDialog = self:CreateDocumentDialog()
        self.documentDialogLoadID = loadid
        self.documentDialog = documentDialog
        self.documentsPanel.children = { documentDialog }
    else
        documentDialog:SetClass('hidden', not documentDialog:HasClass('hidden'))
    end

    if not documentDialog:HasClass('hidden') then
        documentDialog:FireEvent("refreshBubbleDocument", info)
    end
end

--called by dmhub when we need to refresh the info bubbles dialog.
function GameHud:RefreshInfoBubbles()
    local documentDialog = self:try_get('documentDialog')
    if documentDialog ~= nil and not documentDialog:HasClass('hidden') then
        --don't do this right now because updating while editing is very problematic.
        --though this means multiple DM's editing at the same time won't work so well.
        --documentDialog:FireEvent("refreshBubbleDocument")
    end
end

--show the tip for an info bubble
function GameHud:ShowInfoBubbleTip(info)
    local markdownDoc = info.document:GetMarkdownDocument()
    if markdownDoc ~= nil then
        gamehud.popupPanel.popup = gui.TooltipFrame(
            markdownDoc:DisplayPanel {
                width = "100%",
                height = "auto",
                halign = "right",
                maxHeight = 1000,
                vscroll = false,
            },
            {
                width = 800,
                interactable = false,
            }
        )

        gamehud.popupPanel.popup:MakeNonInteractiveRecursive()

        return
    end


    local styles = {
        {
            selectors = { 'heading' },
            fontSize = 30,
            color = 'white',
            textAlignment = 'left',
            width = '95%',
            height = 'auto',
            halign = 'center',
            valign = 'top',
        },
        {
            selectors = { 'separator' },
            width     = '96%',
            height    = 2,
            halign    = 'center',
            bgcolor   = '#ffffff99',
            vmargin   = 4,
        },
        {
            selectors = { 'title' },
            fontSize = 24,
            color = 'white',
            textAlignment = 'left',
            width = '95%',
            height = 'auto',
            halign = 'center',
        },
        {
            selectors = { 'text' },
            fontSize = 14,
            color = 'white',
            textAlignment = 'left',
            width = '95%',
            height = 'auto',
            halign = 'center',
        },
    }

    local children = {}
    children[#children + 1] = gui.Label {
        classes = { 'heading' },
        text = info.description,
    }

    for i, section in ipairs(info.document.sections) do
        children[#children + 1] = gui.Panel {
            bgimage = 'panels/square.png',
            classes = { 'separator' },
        }
        children[#children + 1] = gui.Label {
            classes = { 'title' },
            text = section.title,
        }
        children[#children + 1] = gui.Label {
            classes = { 'text' },
            text = section.text,
        }
    end

    gamehud.popupPanel.popup = gui.Panel {
        interactable = false,
        bgimage = 'panels/square.png',
        selfStyle = {
            opacity = 1,
            bgcolor = 'black',
            borderWidth = 2,
            borderColor = 'white',
            width = 400,
            height = 'auto',
            flow = 'vertical',
            vpad = 4,
        },
        styles = styles,
        children = children,
    }
end

function GameHud:HideInfoBubbleTip(info)
    gamehud.popupPanel.popup = nil
end
