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
    return string.format("Click to View '%s'", self.description)
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

function CustomDocument:CreateInterface(args)
    args = args or {}
    local readPanel = self:DisplayPanel()
    local writePanel = self:EditPanel(args)

    writePanel:SetClass("collapsed", true)

    local m_presentButton
    local m_playerPreviewButton

    local m_titlePanel = args.titlePanel or gui.Label {
        lmargin = 6,
        halign = "left",
        valign = "top",
        minWidth = "40%",
        maxWidth = "100%-240",
        textAlignment = "left",
        width = "auto",
        height = "auto",
        fontSize = 18,
        tmargin = 4,
        textOverflow = "ellipsis",
        textWrap = false,
        text = self.description,
        bold = false,
        editable = self:HaveEditPermissions(),
        characterLimit = 48,
        refreshDocument = function(element, doc)
            self = doc or self
        end,
        change = function(element)
            local original = DeepCopy(self)
            self.description = element.text
            if writePanel ~= nil and not writePanel:HasClass("collapsed") then
                writePanel:FireEventTree("savedoc")
            end
            self:Upload(original)
        end,
    }

    local m_editingButton


    local resultPanel



    if dmhub.isDM and not args.presentationMode then
        m_presentButton = gui.SimpleIconButton {
            escapeActivates = false,
            width = 16,
            height = 16,
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
            width = 16,
            height = 16,
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
            width = 16,
            height = 16,
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

    local m_controlMenu

    m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.SimpleIconButton {
        escapeActivates = false,
        width = 16,
        height = 16,
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
        width = 16,
        height = 16,
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
        m_controlMenuButtons[#m_controlMenuButtons + 1] = m_presentButton

        if self:HaveEditPermissions() then
            m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.SimpleIconButton {
                escapeActivates = false,
                width = 16,
                height = 16,
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

        m_controlMenuButtons[#m_controlMenuButtons + 1] = gui.CloseButton {
            classes = { cond(args.dialog == nil and args.close == nil, "collapsed") },
            width = 16,
            height = 16,
            hmargin = 4,
            closedocuments = function(element)
                element:FireEvent("press")
            end,
            press = function(element)
                if not writePanel:HasClass("collapsed") then
                    local needSave = {save = false}
                    writePanel:FireEventTree("needsave", needSave)
                    if not needSave.save then
                        if args.close then
                            args.close()
                        else
                            args.dialog:DestroySelf()
                        end
                        return
                    end
                    gui.ModalMessage {
                        title = "Unsaved Changes",
                        message = "You have unsaved changes. Are you sure you want to close without saving?",
                        options = {
                            { text = "Cancel" },
                            {
                                text = "Save",
                                execute = function()
                                    resultPanel:FireEventTree("savedoc")
                                    if not dmhub.DeepEqual(self, resultPanel.data.original) then
                                        self:Upload(resultPanel.data.original)
                                    end
                                    if args.close then
                                        args.close()
                                    else
                                        args.dialog:DestroySelf()
                                    end
                                end,
                            },
                            {
                                text = "Don't Save",
                                execute = function()
                                    if args.close then
                                        args.close()
                                    else
                                        args.dialog:DestroySelf()
                                    end
                                end,
                            },
                        },
                    }
                else
                    if args.close then
                        args.close()
                    else
                        args.dialog:DestroySelf()
                    end
                end
            end,
        }
    end

    m_controlMenu = gui.Panel {
        hmargin = 2,
        vmargin = 2,
        halign = "right",
        valign = "top",
        width = "auto",
        height = "auto",
        flow = "horizontal",
        children = m_controlMenuButtons,

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

        gui.Panel {
            bgimage = true,
            bgcolor = Styles.RichBlack02,
            width = "100%",
            height = 32,
            floating = true,
            halign = "center",
            valign = "top",
            cornerRadius = { x1 = 4, y1 = 4, x2 = 0, y2 = 0 },

        },

        m_titlePanel,

        gui.Panel {
            width = "100%-24",
            height = "100%-48",
            vscroll = self.vscroll,
            halign = "center",
            valign = "bottom",
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
        m_controlMenu,
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
        classes = { "framedPanel" },
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

        gui.DialogResizePanel(self, dialogWidth, dialogHeight),

    }

    local a = table.shallow_copy(args)
    args.dialog = dialog
    local mainPanel = self:CreateInterface(args)
    dialog:AddChild(mainPanel)

    return dialog
end

function CustomDocument:ShowDocument(args)
    self = (dmhub.GetTable(self.tableName) or {})[self.id] or self --get the most up-to-date version.
    GameHud.instance.documentsPanel:AddChild(self:PresentDocument(args))
end

function CustomDocument:MatchesSearch(search)
    return false
end

GameHud.RegisterPresentableDialog {
    id = "document",
    create = function(args)
        local doc = (dmhub.GetTable(CustomDocument.tableName) or {})[args.docid]
        if doc ~= nil then
            return doc:PresentDocument {
                presentationMode = true,
            }
        end
    end,
    keeplocal = true,
}
