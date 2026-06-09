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

-- Command context for the PDF viewer. While the viewer modal is open we push this
-- context (dmhub.PushCommandContext) so the left/right arrow keys page through the
-- document via the pdfprevpage/pdfnextpage commands instead of falling through to
-- the global 'tokenmove' bindings. The viewer's command handler responds to these.
-- Because they live in a named context, they only override the arrows while the
-- viewer is the active modal; everywhere else the arrows still move tokens.
local PDF_COMMAND_CONTEXT = "journalpdf"
local g_pdfBindingsInitialized = false
local function EnsurePdfCommandBindings()
    if g_pdfBindingsInitialized then
        return
    end
    g_pdfBindingsInitialized = true
    dmhub.SetCommandBinding("left", "pdfprevpage", PDF_COMMAND_CONTEXT)
    dmhub.SetCommandBinding("right", "pdfnextpage", PDF_COMMAND_CONTEXT)
end

setting {
    id = "pdfbrightness",
    description = "Brightness",
    editor = "slider",
    default = 1,
    storage = "preference",
}

setting {
    id = "pdfdark",
    description = "Dark Mode",
    editor = "slider",
    default = 0,
    storage = "preference",
}

local function CopyToClipboard(text)
    if text == nil then return end
    dmhub.CopyToClipboard(text:gsub(" +", " "))
end

--- @param text LuaUnicodeString
--- @param index number
--- @param dir number
--- @param delimiters string
local function FindTextBoundaryInDirection(text, index, dir, delimiters)
    local thisChar = text:Substring(index, index)
    while index + dir >= 1 and index + dir <= text.Length do
        local nextChar = text:Substring(index + dir, index + dir)
        local a = string.find(delimiters, thisChar, 1, true) ~= nil
        local b = string.find(delimiters, nextChar, 1, true) ~= nil
        if a ~= b then
            return index
        end
        index = index + dir
    end

    return index
end

--- @param text LuaUnicodeString
--- @param index number
--- @param delimiters string
local function FindTextBoundaries(text, index, delimiters)
    return FindTextBoundaryInDirection(text, index, -1, delimiters),
        FindTextBoundaryInDirection(text, index, 1, delimiters)
end

--- @param layout nil|{mergedRects: {rect: {y1: number, y2: number, x1: number, x2: number}, a: integer, b: integer, breaks: number[]}[]}
--- @param index number
--- @return nil|{charIndex: number, rectIndex: number, breakIndex: number}
local function CharacterIndexToLocation(layout, index)
    if layout == nil then
        return nil
    end

    for i, r in ipairs(layout.mergedRects) do
        if r.a <= index and r.b >= index then
            return {
                charIndex = index,
                rectIndex = i,
                breakIndex = index - r.a,
            }
        end
    end

    return nil
end

local function SmartImporterPanel(doc)
    local header = {
        {
            role = "system",
            content =
            "You are going to be given statblocks of D&D content, such as definitions of monsters, items, or spells. When you receive a statblock, output JSON format data describing the statblock that you see. Include a type field which will have a value such as \"monster\", \"item\", \"spell\" etc. When providing monster attributes, provide the raw value for the attribute, not the modifier. For instance if Strength is 15 (+2) output 15, not +2",
        },
    }

    local m_tokensPanel = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "left",

        gui.Panel {
            width = 12,
            height = 12,
            cornerRadius = 6,
            bgimage = "panels/square.png",
            bgcolor = Styles.textColor,
            hmargin = 2,
            halign = "right",
            valign = "center",
            linger = gui.Tooltip(tr("The number of AI tokens you have. Tokens are used when you use the AI. Support DMHub on Patreon to get more tokens.")),
        },

        gui.Label {
            width = 32,
            height = 24,
            textAlignment = "left",
            halign = "right",
            valign = "center",
            hmargin = 6,
            fontSize = 16,
            minFontSize = 10,
            color = Styles.textColor,

            thinkTime = 0.2,

            --- @param element Panel
            create = function(element)
                element:FireEvent("think")
            end,

            --- @param element Panel
            think = function(element)
                local tokensAvailable = round(ai.NumberOfAvailableTokens())
                element.text = string.format("%d", tokensAvailable)
            end,
        }
    }


    local m_init = false
    return gui.Panel {
        classes = { "collapsed" },
        styles = {
            {
                selectors = { "label" },
                fontSize = 14,
                width = "auto",
                height = "auto",
            },
            {
                selectors = { "label", "error" },
                color = "red",
            },
        },
        width = "100%",
        height = "auto",
        flow = "vertical",
        valign = "top",
        activate = function(element, val)
            element:SetClass("collapsed", not val)
        end,

        import = function(element, text, dragPanel, source)
            if not m_init then
                element.children = { m_tokensPanel }
                m_init = true
            end

            printf("IMPORT:: text = (%s)", json(text))

            if text == nil or text == "" then
                if dragPanel ~= nil and dragPanel.valid then
                    dragPanel:FireEvent("fadeaway")
                end
                return
            end

            local m_cancel = false

            local panel

            local deleteButton = gui.Button {
                classes = {"deleteButton", "sizeXs"},
                halign = "right",
                valign = "top",
                floating = true,
                click = function(element)
                    m_cancel = true
                    panel:DestroySelf()
                    if dragPanel ~= nil and dragPanel.valid then
                        dragPanel:FireEvent("fadeaway")
                    end
                end,
            }

            panel = gui.Panel {
                width = "100%",
                height = "auto",
                flow = "vertical",
                halign = "left",
                deleteButton,
                gui.Label {
                    halign = "left",
                    textAlignment = "left",
                    text = "Importing",
                    thinkTime = 0.2,
                    think = function(element)
                        element.text = element.text .. "."
                        if element.text == "Importing...." then
                            element.text = "Importing"
                        end

                        if dragPanel ~= nil and dragPanel.valid then
                            dragPanel:PulseClass("pulse")
                        end
                    end,
                }
            }

            local children = element.children
            children[#children + 1] = panel
            element.children = children

            local message = DeepCopy(header)
            message[#message + 1] = {
                role = "user",
                content = text,
            }

            ai.Chat {
                messages = message,
                temperature = 0,
                timeout = 120,
                success = function(msg)
                    if m_cancel or (not panel.valid) then
                        return
                    end

                    local importer = import.CreateImporter()
                    importer:ClearState()
                    importer:SetActiveImporter("generic_json")
                    importer:ImportFromText(msg)
                    local imports = importer:GetImports()

                    local children = {}

                    for tableid, tableInfo in pairs(imports) do
                        for key, asset in pairs(tableInfo) do
                            asset.source = source
                            children[#children + 1] =
                                gui.Panel {
                                    flow = "horizontal",
                                    halign = "left",
                                    width = "auto",
                                    height = "auto",
                                    gui.Label {
                                        width = 160,
                                        text = string.format("%s: %s", tableid, asset.name),
                                        hover = function(element)
                                            local tooltip = gui.TooltipFrame(asset:Render { pad = 4, width = 800 },
                                                { halign = "right" })
                                            tooltip:MakeNonInteractiveRecursive()
                                            element.tooltip = tooltip
                                        end,
                                    },
                                    gui.Label {
                                        classes = { "link" },
                                        width = 20,
                                        fontSize = 10,
                                        text = "Info",
                                        data = {
                                            msg = nil,
                                        },
                                        press = function(element)
                                            if element.tooltip ~= nil then
                                                CopyToClipboard(element.data.msg)
                                                gui.Tooltip("Copied to clipboard!")(element)
                                            end
                                        end,
                                        hover = function(element)
                                            element.data.msg = msg
                                            local tooltip = gui.TooltipFrame(gui.Label {
                                                width = "auto",
                                                height = "auto",
                                                maxWidth = 1200,
                                                fontSize = 11,
                                                text = msg,
                                            }, {
                                                halign = "right",
                                            })
                                            tooltip:MakeNonInteractiveRecursive()
                                            element.tooltip = tooltip
                                        end,
                                    },
                                    gui.Button {
                                        classes = { "tiny" },
                                        text = cond(importer:IsReimport(asset), "Update", "Add"),
                                        linger = gui.Tooltip(cond(importer:IsReimport(asset), "This entry already exists in your compendium. It will be updated with these new stats.", "Add this entry to your compendium.")),
                                        click = function(element)
                                            importer:CompleteImportStep()
                                            element:SetClass("hidden", true)
                                        end,
                                    }
                                }
                        end
                    end

                    if dragPanel ~= nil and dragPanel.valid then
                        dragPanel:FireEvent("outcome", cond(#children > 0, "success", "error"))
                    end

                    if #children == 0 then
                        children[#children + 1] = gui.Label {
                            classes = { "error" },
                            text = "Could not recognize",
                            hover = gui.Tooltip(msg),
                            press = function(element)
                                CopyToClipboard(msg)
                                gui.Tooltip("Copied to clipboard!")(element)
                            end,
                        }
                    end

                    children[#children + 1] = deleteButton

                    panel.children = children
                end,

                error = function(msg)
                    if m_cancel then
                        return
                    end

                    if dragPanel ~= nil and dragPanel.valid then
                        dragPanel:SetClass("error", true)
                    end

                    panel.children = {
                        gui.Label {
                            classes = { "error" },
                            text = msg,
                        },
                        deleteButton,
                    }
                end,
            }
        end,

        m_tokensPanel,
        gui.Label {
            width = "100%",
            height = "auto",
            fontSize = 14,
            text = "Drag a rectangle around a statblock to import it.",
        },
    }
end

local ShowPDFViewerDialogInternal = function(doc, starting_page)
    print("PDF:: SHOW WITH", type(starting_page), json(starting_page))
    local document = doc.doc
    printf("PAGES: %d", document.summary.npages)

    local m_settingsKey = string.format("pdf-browse-%s", doc.id)
    local m_settings = dmhub.GetPref(m_settingsKey) or {}

    local WriteSettings = function()
        dmhub.SetPref(m_settingsKey, m_settings)
    end

    local m_npage = tonumber(m_settings.page) or 0

    if starting_page ~= nil then
        if type(starting_page) == "string" then
            starting_page = trim(string.lower(starting_page))
        elseif type(starting_page) == "number" then
            m_npage = starting_page
        end
        for i, label in ipairs(document.summary.pageLabels) do
            if starting_page == string.lower(label) then
                m_npage = i - 1
                break
            end
        end
    end

    local m_zoom = tonumber(m_settings.zoom) or 1
    local m_importer = false
    local m_importerPanel = SmartImporterPanel(doc)

    local m_dragAnchor = nil

    local CreateDragPanel
    local m_dragPanel

    local m_searchText = nil
    local m_searchResults = nil
    local m_searchIndex = nil
    local m_searchLen = nil

    local RefreshPage

    CreateDragPanel = function()
        return gui.Panel {
            classes = { "dragPanel", "hidden" },
            bgimage = "panels/square.png",
            halign = "left",
            valign = "top",
            styles = {
                {
                    selectors = { "dragPanel" },
                    opacity = 1,
                    bgcolor = "#ffffff44",
                    borderWidth = 1,
                    borderColor = "blue",
                },
                {
                    selectors = { "dragPanel", "pulse" },
                    brightness = 1.5,
                    transitionTime = 0.1,
                },
                {
                    selectors = { "dragPanel", "importing" },
                    bgcolor = "#0000ff44",
                    borderColor = "blue",
                    transitionTime = 0.2,
                },
                {
                    selectors = { "dragPanel", "importing", "success" },
                    bgcolor = "#00ff0044",
                    borderColor = "green",
                    transitionTime = 0.2,
                },
                {
                    selectors = { "dragPanel", "importing", "error" },
                    bgcolor = "#ff000044",
                    borderColor = "red",
                    transitionTime = 0.2,
                },
            },
            selfStyle = {
                width = 100,
                height = 100,
            },
            update = function(element, parentElement)
                local mousePoint = parentElement.mousePoint
                local imageWidth = parentElement.renderedWidth
                local imageHeight = parentElement.renderedHeight

                local x1 = math.min(m_dragAnchor.x, mousePoint.x)
                local y1 = math.min(1 - m_dragAnchor.y, 1 - mousePoint.y)
                local x2 = math.max(m_dragAnchor.x, mousePoint.x)
                local y2 = math.max(1 - m_dragAnchor.y, 1 - mousePoint.y)
                x1 = clamp(x1, 0, 1)
                x2 = clamp(x2, 0, 1)
                y1 = clamp(y1, 0, 1)
                y2 = clamp(y2, 0, 1)

                element.x = x1 * imageWidth
                element.y = y1 * imageHeight
                element.selfStyle.width = (x2 - x1) * imageWidth
                element.selfStyle.height = (y2 - y1) * imageHeight
            end,
            finish = function(element, parentElement)
                local mousePoint = parentElement.mousePoint
                local imageWidth = parentElement.renderedWidth
                local imageHeight = parentElement.renderedHeight

                local x1 = math.min(m_dragAnchor.x, mousePoint.x)
                local y1 = math.min(m_dragAnchor.y, mousePoint.y)
                local x2 = math.max(m_dragAnchor.x, mousePoint.x)
                local y2 = math.max(m_dragAnchor.y, mousePoint.y)
                x1 = clamp(x1, 0, 1)
                x2 = clamp(x2, 0, 1)
                y1 = clamp(y1, 0, 1)
                y2 = clamp(y2, 0, 1)

                print("SELECT::", x1, y1, x2, y2)

                if math.abs(x1 - x2) < 0.02 or math.abs(y1 - y2) < 0.02 then
                    element:FireEvent("hide")
                    return
                end

                element:FireEvent("menu", { x1 = x1, y1 = y1, x2 = x2, y2 = y2 })

            end,
            menu = function(element, args)
                element.children = {
                    gui.Panel {
                        halign = "left",
                        valign = "top",
                        flow = "horizontal",
                        width = "auto",
                        height = "auto",

                        gui.Button {
                            classes = {"bordered", "sizeM"},
                            icon = mod.images.chatIcon,
                            swallowPress = true,
                            linger = gui.Tooltip("Share to chat"),
                            click = function(element)
                                chat.ShareData(PDFFragment.new {
                                    refid = doc.id,
                                    page = m_npage,
                                    area = { args.x1, args.y1, args.x2, args.y2 },
                                    width = document.summary.pageWidth * (args.x2 - args.x1),
                                    height = document.summary.pageHeight * (args.y2 - args.y1),
                                })
                                m_dragPanel.children = {}
                                m_dragPanel:SetClass("hidden", true)
                            end,
                        },

                        gui.Button {
                            classes = {"bordered", "sizeM"},
                            icon = "game-icons/bookmarklet.png",
                            swallowPress = true,
                            linger = gui.Tooltip("Add to Journal"),
                            click = function(element)
                                m_dragPanel.children = {}
                                m_dragPanel:SetClass("hidden", true)

                                local frag = PDFFragment.new {
                                    refid = doc.id,
                                    description = "",
                                    page = m_npage,
                                    area = { args.x1, args.y1, args.x2, args.y2 },
                                    width = document.summary.pageWidth * (args.x2 - args.x1),
                                    height = document.summary.pageHeight * (args.y2 - args.y1),
                                }

                                local dialog
                                dialog = gui.Panel {
                                    width = 600,
                                    height = 600,
                                    classes = { "framedPanel" },
                                    styles = Styles.Panel,
                                    flow = "vertical",
                                    gui.Label {
                                        classes = { "dialogTitle" },
                                        text = "Add to Journal",
                                        vmargin = 16,
                                    },
                                    gui.Input {
                                        text = frag.description,
                                        change = function(element)
                                            frag.description = trim(element.text)
                                        end,
                                        submit = function(element)
                                            frag.description = trim(element.text)
                                            element:Get("addToJournalButton"):FireEvent("click")
                                        end,
                                        edit = function(element)
                                            frag.description = trim(element.text)
                                            element:Get("addToJournalButton"):SetClass("hidden", trim(element.text) == "")
                                        end,
                                        placeholderText = "Enter name for journal entry",
                                        hasInputFocus = true,
                                        halign = "center",
                                        valign = "center",
                                        width = 400,
                                        height = 24,
                                        fontSize = 18,
                                        characterLimit = 48,
                                    },

                                    gui.Panel {
                                        width = "80%",
                                        height = 30,
                                        halign = "center",
                                        valign = "bottom",
                                        vmargin = 24,
                                        flow = "horizontal",
                                        gui.Button {
                                            halign = "left",
                                            text = "Cancel",
                                            width = 180,
                                            click = function(element)
                                                gui.CloseModal()
                                            end,
                                        },
                                        gui.Button {
                                            classes = { "hidden" },
                                            id = "addToJournalButton",
                                            halign = "right",
                                            text = "Add",
                                            width = 180,
                                            click = function(element)
                                                gui.CloseModal()
                                                dmhub.SetAndUploadTableItem(PDFFragment.tableName, frag)
                                            end,
                                        }
                                    }
                                }

                                gui.ShowModal(dialog)
                            end,
                        },

                        gui.Button {
                            classes = {"bordered", "sizeM"},
                            icon = "icons/icon_app/icon_app_29.png",
                            swallowPress = true,
                            linger = gui.Tooltip("Add to image library"),
                            click = function(element)
                                document:RenderToData(m_npage, document.summary.pageWidth * (args.x2 - args.x1),
                                    document.summary.pageHeight * (args.y2 - args.y1), args, function(data)
                                        if data == nil then
                                            return
                                        end

                                        local assetid
                                        assetid = assets:UploadImageAsset {
                                            data = data,
                                            imageType = "Avatar",
                                            error = function(text)
                                                gui.ModalMessage {
                                                    title = 'Error Uploading',
                                                    message = "There was an error uploading the image: " .. text,
                                                }
                                            end,
                                            upload = function(imageid)
                                                local libraries = assets.imageLibrariesTable
                                                local assetid = nil
                                                for k, v in pairs(libraries) do
                                                    printf("AVIMAGE:: EXISTING DOC %s vs src = %s", doc.id,
                                                        json(v.docsourceid))
                                                    if v.docsourceid == doc.id then
                                                        assetid = k
                                                        break
                                                    end
                                                end

                                                if assetid ~= nil then
                                                    printf("AVIMAGE:: Upload to found library %s", assetid)
                                                    dmhub.AddAndUploadImageToLibrary(assetid, imageid)
                                                else
                                                    assetid = assets:CreateNewImageLibrary {
                                                        name = doc.description,
                                                        docsourceid = doc.id,
                                                        images = { imageid },
                                                    }
                                                    printf("AVIMAGE:: CREATED NEW LIBRARY %s", assetid)
                                                end

                                                gui.ModalMessage {
                                                    title = 'Image uploaded',
                                                    message = "The image was added to your avatar collection.",
                                                }
                                            end,
                                        }
                                    end)


                                m_dragPanel.children = {}
                                m_dragPanel:SetClass("hidden", true)
                            end,
                        },

                        gui.Button {
                            classes = {"bordered", "sizeM"},
                            icon = "icons/icon_app/icon_app_182.png",
                            swallowPress = true,
                            linger = gui.Tooltip("Import as a Map"),
                            click = function(element)
                                document:RenderToData(m_npage, document.summary.pageWidth * (args.x2 - args.x1) * 2,
                                    document.summary.pageHeight * (args.y2 - args.y1) * 2, args, function(data)
                                        if data == nil then
                                            return
                                        end

                                        local path = data:TemporaryFilePath()

                                        mod.shared.ImportMap({
                                            paths = { path },
                                            finish = function(info)
                                                mod.shared.FinishMapImport(
                                                    string.format("%s page %d", doc.description, m_npage + 1), info)
                                                gui.CloseModal()
                                            end,
                                        })
                                    end)


                                m_dragPanel.children = {}
                                m_dragPanel:SetClass("hidden", true)
                            end,
                        },

                    }
                }
            end,

            hide = function(element)
                element.children = {}
                element:SetClass("hidden", true)
            end,

            page = function(element)
                if element:HasClass("importing") then
                    element:SetClass("hidden", true)
                end
            end,
            outcome = function(element, outcome)
                element:SetClass(outcome, true)
                element:ScheduleEvent("fadeaway", 0.6)
            end,
            fadeaway = function(element)
                element:SetClass("fade", true)
                element:ScheduleEvent("die", 0.2)
            end,
            die = function(element)
                element:DestroySelf()
            end,
        }
    end

    local AddBookmarkPanel = function(options)
        local m_text = "New Bookmark"
        if options.bookmark ~= nil then
            m_text = options.bookmark.title
        end

        local dialog
        dialog = gui.Panel {
            width = 600,
            height = 600,
            classes = { "framedPanel" },
            styles = Styles.Panel,
            flow = "vertical",
            gui.Label {
                classes = { "dialogTitle" },
                text = cond(options.bookmark ~= nil, "Edit Bookmark", "Add Bookmark"),
                vmargin = 16,
            },
            gui.Input {
                text = m_text,
                change = function(element)
                    m_text = element.text
                end,
                submit = function(element)
                    m_text = element.text
                    element:Get("addBookmarkButton"):FireEvent("click")
                end,
                hasInputFocus = true,
                halign = "center",
                valign = "center",
                width = 400,
                height = 24,
                fontSize = 18,
                characterLimit = 32,
            },

            gui.Panel {
                width = "80%",
                height = 30,
                halign = "center",
                valign = "bottom",
                vmargin = 24,
                flow = "horizontal",
                gui.Button {
                    halign = "left",
                    text = "Cancel",
                    width = 180,
                    click = function(element)
                        gui.CloseModal()
                    end,
                },
                gui.Button {
                    id = "addBookmarkButton",
                    halign = "right",
                    text = cond(options.bookmark ~= nil, "Update", "Add"),
                    width = 180,
                    click = function(element)
                        local bookmarks = doc.bookmarks
                        bookmarks[options.guid] = {
                            page = options.npage,
                            title = m_text,
                        }
                        doc.bookmarks = bookmarks
                        doc:Upload()
                        gui.CloseModal()
                    end,
                }
            }
        }

        gui.ShowModal(dialog)
    end

    m_dragPanel = CreateDragPanel()

    local CreateSearchResultsPanel = function()
        local m_pagePanels = {}

        local pageHeight = (document.summary.pageHeight / document.summary.pageWidth) * 200
        local pageMargin = 16

        return gui.Panel {
            width = 250,
            height = "100%",
            flow = "vertical",
            vscroll = true,

            styles = {
                {
                    selectors = { "listItem" },
                    bgimage = "panels/square.png",
                    bgcolor = "clear",
                    flow = "horizontal",
                    valign = "top",
                    width = "100%",
                    height = 20,
                },
                {
                    selectors = { "listItem", "hover" },
                    bgcolor = Styles.textColor,
                },
                {
                    selectors = { "listItem", "selected" },
                    bgcolor = Styles.textColor,
                },
                {
                    selectors = { "label" },
                    fontSize = 14,
                    minFontSize = 8,
                    height = 18,
                    textWrap = false,
                    color = Styles.textColor,
                    textAlignment = "left",
                },
                {
                    selectors = { "label", "parent:hover" },
                    color = "black",
                },
                {
                    selectors = { "label", "parent:selected" },
                    color = "black",
                },
            },

            page = function(element)
                element:SetClass("collapsed", m_searchResults == nil)
            end,

            executeSearch = function(element, results)
                local currentSearch = nil

                local children = {}
                for i, result in ipairs(results) do
                    local searchText = m_searchText

                    children[#children + 1] = gui.Panel {
                        classes = { "listItem" },
                        gui.Label {
                            width = 40,
                            fontSize = 12,
                            text = string.format("p. %s", document.summary.pageLabels[result.page + 1] or (result.page + 1)),
                        },

                        gui.Label {
                            width = "100%-46",
                            rmargin = 4,
                            --- @param layout {text: LuaUnicodeString, textRects: Vector4[], charRects: Vector4[], mergedRects: { rect: Vector4, a: integer, b: integer, breaks: number[]}}
                            layout = function(element, layout)
                                if (not element.valid) or searchText ~= m_searchText then
                                    return
                                end

                                local startingCharIndex = result.index
                                local endingCharIndex = startingCharIndex + #m_searchText
                                for _, rect in ipairs(layout.mergedRects) do
                                    if rect.a <= startingCharIndex and rect.b >= startingCharIndex then
                                        local contextWindow = 12

                                        local a = rect.a
                                        local b = rect.b

                                        if startingCharIndex == rect.a or endingCharIndex == rect.b then
                                            contextWindow = contextWindow * 2
                                        end

                                        if a < startingCharIndex - contextWindow then
                                            a = startingCharIndex - contextWindow
                                        end
                                        if b > endingCharIndex + contextWindow then
                                            b = endingCharIndex + contextWindow
                                        end

                                        local text = layout.text:Substring(a, b)

                                        local spaceAtStart = startingCharIndex - a
                                        if a ~= rect.a then
                                            while spaceAtStart > 0 and (not string.starts_with(text, " ")) do
                                                text = string.sub(text, 2)
                                                spaceAtStart = spaceAtStart - 1
                                            end

                                            if string.starts_with(text, " ") then
                                                text = string.sub(text, 2)
                                                spaceAtStart = spaceAtStart - 1
                                            end
                                        end

                                        local spaceAtEnd = b - endingCharIndex
                                        if b ~= rect.b then
                                            while spaceAtEnd > 0 and (not string.ends_with(text, " ")) do
                                                text = string.sub(text, 1, #text - 1)
                                                spaceAtEnd = spaceAtEnd - 1
                                            end

                                            if string.ends_with(text, " ") then
                                                text = string.sub(text, 1, #text - 1)
                                                spaceAtEnd = spaceAtEnd - 1
                                            end
                                        end

                                        --put bold around the text.
                                        local startPos = spaceAtStart + 1
                                        local endPos = #text - spaceAtEnd
                                        text = text:sub(1, startPos - 1) ..
                                            "<b>" .. text:sub(startPos, endPos) .. "</b>" .. text:sub(endPos + 1)

                                        if a > rect.a then
                                            text = "..." .. text
                                        end

                                        if b < rect.b then
                                            text = text .. "..."
                                        end

                                        element.text = text
                                    end
                                end
                            end,

                            create = function(element)
                                document:TextLayout(result.page,
                                    function(layout)
                                        element:FireEvent("layout", layout)
                                    end)
                            end,
                        },
                        create = function(element)
                            element:FireEvent("page")
                        end,
                        page = function(element)
                            element:SetClass("selected", m_searchIndex == i)
                        end,
                        press = function(element)
                            m_searchIndex = i
                            RefreshPage()
                        end,
                    }
                end

                element.children = children
            end,
        }
    end

    local CreateContentsPanel = function()
        local m_pagePanels = {}

        local pageHeight = (document.summary.pageHeight / document.summary.pageWidth) * 200
        local pageMargin = 16

        --contents panel.
        return gui.Panel {
            width = 240,
            height = "100%",
            flow = "vertical",

            page = function(element)
                element:SetClass("collapsed", m_searchResults ~= nil)
            end,

            m_importerPanel,

            gui.Panel {
                vmargin = 16,
                width = "100%",
                height = "100% available",
                vscroll = true,

                gui.Panel {
                    width = 200,
                    height = (pageHeight + pageMargin) * document.summary.npages,
                    valign = "top",
                    halign = "center",
                    flow = "vertical",

                    styles = {
                        {
                            selectors = { "page" },
                            bgcolor = "white",
                            cornerRadius = 2,
                        },
                        {
                            selectors = { "page", "loaded" },
                            opacity = 0,
                        },
                        {
                            selectors = { "page", "hover" },
                            transitionTime = 0.1,
                            brightness = 2,
                            opacity = 1,
                        },
                        {
                            selectors = { "page", "selected", "loaded" },
                            transitionTime = 0.1,
                            bgcolor = Styles.textColor,
                            brightness = 10,
                            opacity = 1,
                        },
                        {
                            selectors = { "pageImage" },
                            bgcolor = "white",
                            halign = "center",
                            valign = "center",
                            width = "100%-4",
                            height = "100%-4",
                        },
                        {
                            selectors = { "pageImage", "parent:selected" },
                            borderWidth = 2.5,
                            borderColor = "black",
                        },
                        {
                            selectors = { "pageFooter" },
                            color = Styles.textColor,
                            fontSize = 12,
                            width = "auto",
                            height = 12,
                            valign = "bottom",
                            halign = "center",
                        },
                        {
                            selectors = { "pageFooter", "parent:selected" },
                            color = "white",
                            fontWeight = "bold",
                        },
                    },

                    data = {
                        lastpos = nil,
                        lastParentHeight = nil,
                        lastHeight = nil,
                        lastPage = nil,
                        invalidated = false,
                    },

                    create = function(element)
                        --element:FireEvent("page")
                        element:ScheduleEvent("page", 0.01)
                    end,

                    page = function(element)
                        local parent = element.parent
                        local parentHeight = parent.renderedHeight
                        local height = element.renderedHeight
                        if height == 0 or parentHeight == 0 or (parentHeight / height) == 1 then
                            return
                        end

                        local pos = 1 - parent.vscrollPosition

                        local windowTop = (height - parentHeight) * pos
                        local windowBottom = windowTop + parentHeight

                        local firstPageInWindow = math.floor(windowTop / (pageHeight + pageMargin))
                        local lastPageInWindow = math.floor(windowBottom / (pageHeight + pageMargin))

                        pos = m_npage / document.summary.npages

                        local pos_a = pos - parentHeight / height + 1 / document.summary.npages
                        pos_a = pos_a / (1 - parentHeight / height)

                        local pos_b = pos
                        pos_b = pos_b / (1 - parentHeight / height)

                        if pos_a > (1 - parent.vscrollPosition) then
                            parent.vscrollPosition = 1 - pos_a
                            print("PDFScroll: Set", 1 - pos_a)
                        elseif pos_b < (1 - parent.vscrollPosition) then
                            parent.vscrollPosition = 1 - pos_b
                            print("PDFScroll: Set", 1 - pos_b)
                        end

                        --if firstPageInWindow > m_npage or lastPageInWindow < m_npage then
                        --    local desiredPos = (m_npage / document.summary.npages) - (parentHeight/height)*0.5
                        --    parent.vscrollPosition = 1 - desiredPos
                        --    printf("WINDOW: pos = %s -> %s", json(1 - desiredPos), json(parent.vscrollPosition))
                        --end
                    end,

                    monitorAssets = "Documents",
                    refreshAssets = function(element)
                        element.data.invalidated = true
                    end,

                    thinkTime = 0.01,
                    think = function(element)
                        local parent = element.parent
                        local parentHeight = parent.renderedHeight
                        local height = element.renderedHeight

                        if parentHeight <= 0 or height <= 0 then
                            return
                        end

                        --pos = 0 at the top, 1 at the bottom
                        local pos = 1 - parent.vscrollPosition

                        if element.data.invalidated == false and pos == element.data.lastpos and height == element.data.lastHeight and parentHeight == element.data.lastParentHeight and m_npage == element.data.lastPage then
                            return
                        end

                        element.data.invalidated = false

                        element.data.lastHeight = height
                        element.data.lastParentHeight = parentHeight
                        element.data.lastpos = pos
                        element.data.lastPage = m_npage


                        local windowTop = (height - parentHeight) * pos
                        local windowBottom = windowTop + parentHeight

                        local firstPageInWindow = math.floor(windowTop / (pageHeight + pageMargin))
                        local lastPageInWindow = math.ceil(windowBottom / (pageHeight + pageMargin))

                        if firstPageInWindow < 0 then
                            firstPageInWindow = 0
                        end

                        if lastPageInWindow >= document.summary.npages then
                            lastPageInWindow = document.summary.npages - 1
                        end

                        local bookmarks = doc.bookmarks

                        for i = firstPageInWindow, lastPageInWindow do
                            local index = (i - firstPageInWindow) + 1

                            local page = m_pagePanels[index] or gui.Panel {
                                data = {
                                    bgimage = nil,
                                    npage = nil,
                                    imagePanel = nil,
                                    bookmark = nil
                                },
                                idprefix = "journal-page",
                                classes = { "page" },
                                bgimage = "panels/square.png",
                                width = "100%",
                                height = pageHeight,
                                valign = "top",
                                vmargin = pageMargin / 2,
                                floating = true,



                                bookmark = function(element, bookmark)
                                    element.data.bookmark = bookmark
                                end,

                                press = function(element)
                                    m_npage = element.data.npage
                                    m_searchResults = nil
                                    m_searchText = nil
                                    RefreshPage()
                                end,

                                rightClick = function(element)
                                    local menuItems = {}

                                    local bookmarks = doc.bookmarks

                                    local bookmarkid = nil
                                    for k, v in pairs(bookmarks) do
                                        if v.page == element.data.npage then
                                            bookmarkid = k
                                            break
                                        end
                                    end


                                    if bookmarkid ~= nil then
                                        menuItems[#menuItems + 1] = {
                                            text = "Edit Bookmark",
                                            click = function()
                                                AddBookmarkPanel { npage = element.data.npage, bookmark = bookmarks[bookmarkid], guid = bookmarkid }
                                                element.popup = nil
                                            end,
                                        }
                                        menuItems[#menuItems + 1] = {
                                            text = "Remove Bookmark",
                                            click = function()
                                                local bookmarks = doc.bookmarks
                                                bookmarks[bookmarkid] = nil
                                                doc.bookmarks = bookmarks
                                                doc:Upload()
                                                element.popup = nil
                                            end,
                                        }
                                    else
                                        menuItems[#menuItems + 1] = {
                                            text = "Add Bookmark",
                                            click = function()
                                                AddBookmarkPanel { npage = element.data.npage, guid = dmhub.GenerateGuid() }
                                                element.popup = nil
                                            end,
                                        }
                                    end

                                    element.popup = gui.ContextMenu {
                                        entries = menuItems,
                                    }
                                end,

                                --the actual panel that has the image of the page.
                                gui.Panel {
                                    idprefix = "journal-page-image",
                                    classes = { "pageImage" },
                                    imageLoaded = function(element)
                                        element.parent:SetClassTree("loaded", true)
                                    end,

                                    inversion = dmhub.GetSettingValue("pdfdark"),
                                    brightness = dmhub.GetSettingValue("pdfbrightness"),
                                    multimonitor = { "pdfbrightness", "pdfdark" },
                                    monitor = function(element)
                                        element.selfStyle.brightness = dmhub.GetSettingValue("pdfbrightness")
                                        element.selfStyle.inversion = dmhub.GetSettingValue("pdfdark")
                                    end,

                                    gui.Panel {
                                        data = {
                                            bookmark = nil
                                        },
                                        classes = { "hidden" },
                                        bgimage = "icons/icon_app/document-bookmark.png",
                                        floating = true,
                                        x = -8,
                                        y = -6,
                                        width = 48,
                                        height = 48,
                                        halign = "right",
                                        valign = "top",
                                        bgcolor = "#770000",
                                        bookmark = function(element, bookmark)
                                            element.data.bookmark = bookmark
                                            element:SetClass("hidden", bookmark == nil)
                                        end,
                                        linger = function(element)
                                            if element.data.bookmark ~= nil then
                                                gui.Tooltip(string.format("Bookmark: %s", element.data.bookmark.title))(
                                                    element)
                                            end
                                        end,
                                    },



                                },

                                gui.Label {
                                    classes = { "pageFooter" },
                                    floating = true,
                                    y = 12,
                                    npage = function(element, npage)
                                        local text = document.summary.pageLabels[npage + 1] or
                                            string.format("%d", npage + 1)
                                        element.text = text
                                    end,
                                },
                            }

                            if m_pagePanels[index] == nil then
                                page.data.imagePanel = page.children[1]
                            end

                            local bgimage = document:GetPageThumbnailId(i)

                            if bgimage ~= page.data.bgimage then
                                page:SetClassTree("loaded", false)
                                page.data.bgimage = bgimage
                                --page.data.imagePanel.bgimageInit = false
                                page.data.imagePanel.bgimage = bgimage
                            end

                            local bookmark = nil
                            for k, v in pairs(bookmarks) do
                                if v.page == i then
                                    bookmark = v
                                    break
                                end
                            end

                            if bookmark ~= page.data.bookmark then
                                page:FireEventTree("bookmark", bookmark)
                            end

                            page.y = i * (pageHeight + pageMargin)
                            page.data.npage = i
                            page:FireEventTree("npage", i)
                            page:SetClass("hidden", false)
                            page:SetClass("selected", i == m_npage)

                            m_pagePanels[index] = page
                        end

                        for i = lastPageInWindow + 2, #m_pagePanels do
                            m_pagePanels[i]:SetClass("hidden", true)
                        end

                        element.children = m_pagePanels
                    end,
                }
            }

        }
    end


    local currentSearchGuid = nil
    local dialogPanel


    --view panel.
    local pdfScrollViewPanel = gui.Panel {
        id = "pdfScrollView",
        width = "100%-260",
        height = "100%",
        vscroll = true,
        data = {
            pos = nil,
        },
        create = function(element)
            if m_settings.vscroll ~= nil then
                element.vscrollPosition = m_settings.vscroll
                print("PDFScroll: Set", m_settings.vscroll)
            end
            element.data.pos = element.vscrollPosition
        end,
        thinkTime = 0.2,
        think = function(element)
            if element.data.pos ~= element.vscrollPosition then
                element.data.pos = element.vscrollPosition

                m_settings.page = m_npage
                m_settings.zoom = m_zoom
                m_settings.vscroll = element.vscrollPosition
                WriteSettings()
            end
        end,
        gui.Panel {
            id = "pdfViewPanel",
            bgcolor = "white",
            bgimage = "panels/square.png",
            halign = "center",
            width = "100%",
            height = "100% width",
            valign = "top",
            draggable = true,
            dragMove = false,

            styles = {
                {
                    selectors = { "loading" },
                    opacity = 1,
                },
                {
                    selectors = { "highlight" },
                    halign = "left",
                    valign = "top",
                    bgcolor = "#0000ff77",
                    borderWidth = 1,
                    borderColor = "blue",
                }
            },

            --augmentation overlays: image panels that sit on top of the page
            --and replace parts of it. Data-driven from PDFAugmentations (see
            --JournalPDFAugmentation.lua). interactable=false so the page text
            --underneath stays selectable.
            gui.Panel {
                id = "pdfAugmentations",
                floating = true,
                interactable = false,
                halign = "left",
                valign = "top",
                width = "100%",
                height = "100%",
                data = {
                    panels = {},
                    dirty = true,
                    lastW = 0,
                    lastH = 0,
                    lastPage = nil,
                    activeAugs = {},     --augmentations matched on the current page
                    detectors = {},      --aug id -> gesture detector
                    gestureName = {},    --aug id -> currently-reported gesture, or nil
                    graceUntil = {},     --aug id -> off-area grace deadline (dmhub.Time)
                },

                --fired by RefreshPage on page/zoom change; mark for relayout.
                page = function(element)
                    element.data.dirty = true
                end,

                --small thinkTime so gesture sampling is roughly per-frame; the
                --relayout below is gated and cheap when nothing changed.
                thinkTime = 0.01,
                think = function(element)
                    local parent = element.parent
                    if parent == nil then
                        return
                    end

                    local w = parent.renderedWidth
                    local h = parent.renderedHeight
                    if w <= 0 or h <= 0 then
                        return
                    end

                    --(1) Relayout overlays only when the page changed or the
                    --panel resized (covers zoom and window resize).
                    if element.data.dirty or w ~= element.data.lastW or h ~= element.data.lastH or m_npage ~= element.data.lastPage then
                        element.data.dirty = false
                        element.data.lastW = w
                        element.data.lastH = h
                        element.data.lastPage = m_npage

                        --the page number as displayed in the page input box: the
                        --page label if the PDF has one, else the 1-based index.
                        local pageShown = document.summary.pageLabels[m_npage + 1] or (m_npage + 1)

                        --O(1) lookup of just this page's augmentations -- no walk
                        --of the whole registry. GetForPage returns a shared list,
                        --so shallow-copy it before sorting for render order.
                        local PDFAug = rawget(_G, "PDFAugmentations")
                        local pageAugs = (PDFAug ~= nil and PDFAug.GetForPage ~= nil) and PDFAug.GetForPage(doc.description, pageShown) or {}
                        local matches = {}
                        for i = 1, #pageAugs do
                            matches[i] = pageAugs[i]
                        end

                        --sort ascending by zorder: GUI panels have no z-index
                        --property, render order is sibling array order (later
                        --children draw on top), so the highest zorder must land
                        --last in element.children below.
                        table.sort(matches, function(a, b)
                            return (a.zorder or 0) < (b.zorder or 0)
                        end)

                        local children = {}
                        for i, aug in ipairs(matches) do
                            local area = aug.area

                            local p = element.data.panels[i] or gui.Panel {
                                floating = true,
                                interactable = false,
                                halign = "left",
                                valign = "top",
                                bgimage = "panels/square.png",
                            }

                            --area is {x1, y1, x2, y2} normalized, in the same
                            --convention as the SELECT:: print in the drag handler:
                            --y is bottom-origin (0 at the bottom of the page, 1 at
                            --the top), so the panel's top edge maps from y2.
                            p.selfStyle.x = w * area[1]
                            p.selfStyle.y = h * (1 - area[4])
                            p.selfStyle.width = w * (area[3] - area[1])
                            p.selfStyle.height = h * (area[4] - area[2])

                            p.bgimage = aug.image or "panels/square.png"
                            p.selfStyle.bgcolor = aug.bgcolor or "white"

                            --pass the blend mode straight through (e.g.
                            --"premultiplied"); nil resets to the default so a
                            --pooled panel reused by a non-blended augmentation
                            --doesn't keep a stale blend.
                            p.selfStyle.blend = aug.blend

                            p:SetClass("hidden", false)
                            element.data.panels[i] = p
                            children[i] = p
                        end

                        for i = #matches + 1, #element.data.panels do
                            element.data.panels[i]:SetClass("hidden", true)
                            children[#children + 1] = element.data.panels[i]
                        end

                        element.children = children
                        element.data.activeAugs = matches
                    end

                    --(2) Gesture detection every tick, for augmentations that
                    --declare a gesture handler. The cursor position and guards
                    --come from the parent (pdfViewPanel) because this overlay is
                    --interactable=false; the augmentation 'area' is normalized
                    --over the page, the same space as parent.mousePoint.
                    local PDFAug = rawget(_G, "PDFAugmentations")
                    if PDFAug == nil or PDFAug.NewGestureDetector == nil then
                        return
                    end

                    local now = dmhub.Time()
                    local mp = parent.mousePoint
                    local hover = parent:HasClass("hover")
                    local buttonHeld = parent:GetMouseButton(0) or parent:GetMouseButton(1) or parent:GetMouseButton(2)

                    local relevant = {}
                    for _, aug in ipairs(element.data.activeAugs) do
                        if type(aug.gesture) == "function" then
                            local id = aug.id
                            relevant[id] = true

                            local area = aug.area
                            local inside = false
                            if hover and mp ~= nil then
                                inside = mp.x >= area[1] and mp.x <= area[3] and mp.y >= area[2] and mp.y <= area[4]
                            end

                            --a brief grace after the cursor strays off the area
                            --keeps a stroke that overshoots the box alive; the
                            --button guard still applies every tick.
                            if inside then
                                element.data.graceUntil[id] = now + 0.35
                            end
                            local active = (now < (element.data.graceUntil[id] or 0)) and (not buttonHeld)

                            local detector = element.data.detectors[id]
                            if detector == nil then
                                detector = PDFAug.NewGestureDetector()
                                element.data.detectors[id] = detector
                            end

                            --feed pixel-space position so the detector's pixel
                            --thresholds (minStrokeDistance etc.) stay meaningful.
                            local mx, my = 0, 0
                            if mp ~= nil then
                                mx = mp.x * w
                                my = mp.y * h
                            end

                            local petting = detector:Tick(mx, my, now, active)
                            local name = petting and "pet" or nil
                            if name ~= nil then
                                --continuous stream of calls while the gesture is
                                --active (acts as a keepalive for the handler).
                                aug.gesture(name)
                            elseif element.data.gestureName[id] ~= nil then
                                --falling edge: signal the end once.
                                aug.gesture(nil)
                            end
                            element.data.gestureName[id] = name
                        end
                    end

                    --send a stop (nil) for any augmentation that was mid-gesture
                    --but is no longer on this page (e.g. the user changed pages).
                    for id, name in pairs(element.data.gestureName) do
                        if name ~= nil and not relevant[id] then
                            element.data.gestureName[id] = nil
                            if element.data.detectors[id] ~= nil then
                                element.data.detectors[id]:Reset()
                            end
                            local aug = PDFAug.Get(id)
                            if aug ~= nil and type(aug.gesture) == "function" then
                                aug.gesture(nil)
                            end
                        end
                    end
                end,
            },

            m_dragPanel,

            data = {
                pageDisplayed = nil,
                setCursor = false,

                anchorTextDrag = nil,
                textLayout = nil,

                highlightPanels = {},

                FindMouseoverChar = function(element)
                    local layout = element.data.textLayout

                    if layout == nil then
                        return nil
                    end

                    local mousePoint = element.mousePoint

                    local x = mousePoint.x * document.summary.pageWidth
                    local y = mousePoint.y * document.summary.pageHeight

                    for j, r in ipairs(layout.mergedRects) do
                        local rect = r.rect
                        if x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2 then
                            local breaks = r.breaks
                            if x < breaks[1] then
                                return r.a
                            end

                            local smallestDiff = nil
                            local closestIndex = nil
                            for i = 1, #breaks do
                                local diff = math.abs(breaks[i] - x)
                                if smallestDiff == nil or diff < smallestDiff then
                                    closestIndex = i
                                    smallestDiff = diff
                                end
                            end

                            if closestIndex ~= nil then
                                return {
                                    rectIndex = j,
                                    breakIndex = closestIndex,
                                    charIndex = r.a + (closestIndex - 1),
                                }
                            end
                        end
                    end

                    return nil
                end,

                FindMouseToRightOf = function(element)
                    local layout = element.data.textLayout

                    if layout == nil then
                        return nil
                    end

                    local mousePoint = element.mousePoint

                    local x = mousePoint.x * document.summary.pageWidth
                    local y = mousePoint.y * document.summary.pageHeight

                    local bestIndex = nil
                    local bestDist = nil

                    for j, r in ipairs(layout.mergedRects) do
                        local rect = r.rect
                        if x >= rect.x2 and y >= rect.y1 and y <= rect.y2 then
                            if bestIndex == nil or rect.x2 > bestDist then
                                bestIndex = j
                                bestDist = rect.x2
                            end
                        end
                    end

                    if bestIndex ~= nil then
                        return {
                            rectIndex = bestIndex,
                            breakIndex = #layout.mergedRects[bestIndex].breaks,
                            charIndex = layout.mergedRects[bestIndex].b,
                        }
                    end

                    return nil
                end,

                FindMouseBelow = function(element)
                    local layout = element.data.textLayout

                    if layout == nil then
                        return nil
                    end

                    local mousePoint = element.mousePoint

                    local x = mousePoint.x * document.summary.pageWidth
                    local y = mousePoint.y * document.summary.pageHeight

                    local bestIndex = nil
                    local bestDist = nil

                    for j, r in ipairs(layout.mergedRects) do
                        local rect = r.rect
                        if y <= rect.y1 and x >= rect.x1 and x <= rect.x2 then
                            if bestIndex == nil or rect.y1 < bestDist then
                                bestIndex = j
                                bestDist = rect.y1
                            end
                        end
                    end

                    if bestIndex ~= nil then
                        return {
                            rectIndex = bestIndex,
                            breakIndex = #layout.mergedRects[bestIndex].breaks,
                            charIndex = layout.mergedRects[bestIndex].b,
                        }
                    end

                    return nil
                end,



            },

            inputEvents = { "copy" },

            copy = function(element)
                if element.data.selectedText == nil then
                    return
                end

                CopyToClipboard(element.data.selectedText)
            end,

            rightClick = function(element)
                local menuItems = {}

                if element.data.selectedText ~= nil then
                    menuItems[#menuItems + 1] = {
                        text = "Copy",
                        click = function()
                            element.popup = nil
                            if element.data.selectedText == nil then
                                return
                            end

                            CopyToClipboard(element.data.selectedText)
                        end,
                    }
                end

                menuItems[#menuItems + 1] = {
                    text = "Copy All",
                    click = function()
                        element.popup = nil

                        local layout = element.data.textLayout
                        if layout == nil then
                            return
                        end

                        CopyToClipboard(layout.text:Substring(1, layout.text.Length))
                    end,
                }

                element.popup = gui.ContextMenu {
                    entries = menuItems,
                }
            end,

            --- @param element Panel
            --- @param rects {x1: number, x2: number, y1: number, y2: number}[]
            --- @param text string
            highlight = function(element, rects, text, args)
                args = args or {}
                element.data.lastHighlight = DeepCopy(rects)
                element.data.selectedText = text

                local hasSearch = args.changepage and m_searchIndex ~= nil and m_searchResults ~= nil

                if m_searchResults ~= nil and m_searchResults[m_searchIndex] ~= nil and element.data.textLayout ~= nil then
                    local match = m_searchResults[m_searchIndex]
                    if match.page == m_npage then
                        local matchIndex = match.index
                        local matchEnd = matchIndex + m_searchLen
                        rects = DeepCopy(rects) or {}
                        for _, r in ipairs(element.data.textLayout.mergedRects) do
                            if matchIndex >= r.a and matchIndex <= r.b then
                                local startIndex = (matchIndex - r.a) + 1
                                local endIndex = math.min(startIndex + m_searchLen, r.b - r.a) + 1

                                local rect = DeepCopy(r.rect)
                                rect.x1 = r.breaks[startIndex]
                                rect.x2 = r.breaks[endIndex]

                                rects[#rects + 1] = rect

                                matchIndex = matchIndex + (endIndex - startIndex)
                                if matchIndex >= matchEnd then
                                    break
                                end
                            end
                        end
                    end
                end

                local newChildren = {}
                for i, r in ipairs(rects or {}) do
                    if hasSearch then
                        hasSearch = false
                        local contentHeight = element.renderedHeight
                        local viewportHeight = element.parent.renderedHeight
                        if contentHeight > viewportHeight + 20 then
                            local desiredCenter = ((r.y1 + r.y2) * 0.5) / document.summary.pageHeight
                            desiredCenter = desiredCenter - (viewportHeight / contentHeight) * 0.5

                            local scrollPosition = desiredCenter / ((contentHeight - viewportHeight) / contentHeight)

                            print("PDFScroll: Set to", scrollPosition)
                            element.parent.vscrollPosition = scrollPosition
                        end
                    end


                    local p = element.data.highlightPanels[i] or gui.Panel {
                        classes = { "highlight" },
                        bgimage = "panels/square.png",
                        floating = true,
                    }

                    p.selfStyle.x = (element.renderedWidth * r.x1) / document.summary.pageWidth
                    p.selfStyle.y = element.renderedHeight - (element.renderedHeight * r.y2) /
                        document.summary.pageHeight
                    p.selfStyle.width = element.renderedWidth * (r.x2 - r.x1) / document.summary.pageWidth
                    p.selfStyle.height = element.renderedHeight * (r.y2 - r.y1) / document.summary.pageHeight


                    p:SetClass("hidden", false)

                    if element.data.highlightPanels[i] == nil then
                        element.data.highlightPanels[i] = p
                        newChildren[#newChildren + 1] = p
                    end
                end

                for i = #rects + 1, #element.data.highlightPanels do
                    element.data.highlightPanels[i]:SetClass("hidden", true)
                end

                if #newChildren > 0 then
                    local children = element.children
                    for _, child in ipairs(newChildren) do
                        children[#children + 1] = child
                    end

                    element.children = children
                end
            end,

            thinkTime = 0.01,

            think = function(element)
                if element:HasClass("hover") == false or element.data.textLayout == nil then
                    if element.data.anchorTextDrag ~= nil then
                        dmhub.OverrideMouseCursor("text", 0.2)
                        element.data.setCursor = true
                    elseif element.data.setCursor then
                        dmhub.OverrideMouseCursor(nil, 0)
                        element.data.setCursor = false
                    end
                    element.data.prev_drag = nil
                    return
                end

                local mousePoint = element.mousePoint

                local x = mousePoint.x * document.summary.pageWidth
                local y = mousePoint.y * document.summary.pageHeight

                local middleButtonDown = element:GetMouseButton(2)

                if middleButtonDown then
                    local dx = 0
                    local dy = 0
                    if element.data.prev_drag ~= nil then
                        dx = mousePoint.x - element.data.prev_drag.x
                        dy = mousePoint.y - element.data.prev_drag.y

                        element.x = element.x + dx * element.renderedWidth
                        element.parent.vscrollPosition = element.parent.vscrollPosition -
                            dy / ((element.renderedHeight - element.parent.renderedHeight) / element.renderedHeight)
                        print("PDFScroll: Set")
                    end

                    element.data.prev_drag = { x = mousePoint.x - dx, y = mousePoint.y - dy }
                else
                    element.data.prev_drag = nil
                end


                local hit = false
                for _, r in ipairs(element.data.textLayout.mergedRects) do
                    local rect = r.rect
                    if x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2 then
                        hit = true
                    end
                end

                local hitlink = nil
                for _, link in ipairs(element.data.textLayout.links or {}) do
                    local rect = link.rect
                    if x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2 then
                        hitlink = link
                    end
                end

                element.data.hoveredLink = hitlink

                --don't allow text cursor if we're over the drag panel.
                if hit and element:FindChildRecursive(function(p) return p:HasClass("hover") and p:HasClass("dragPanel") end) ~= nil then
                    hit = false
                end

                if (not middleButtonDown) and element.data.anchorTextDrag == nil and hitlink then
                    dmhub.OverrideMouseCursor("hand", 0.2)
                elseif (not middleButtonDown) and (hit or element.data.anchorTextDrag ~= nil) then
                    dmhub.OverrideMouseCursor("text", 0.2)
                else
                    dmhub.OverrideMouseCursor(nil, 0)
                end
            end,

            inversion = dmhub.GetSettingValue("pdfdark"),
            brightness = dmhub.GetSettingValue("pdfbrightness"),
            multimonitor = { "pdfbrightness", "pdfdark" },
            monitor = function(element)
                element.selfStyle.brightness = dmhub.GetSettingValue("pdfbrightness")
                element.selfStyle.inversion = dmhub.GetSettingValue("pdfdark")
            end,

            imageLoaded = function(element)
                element:SetClass("loading", false)
            end,
            page = function(element)
                element.selfStyle.width = string.format("%f%%", m_zoom * 100)
                element.selfStyle.height = string.format("%f%% width",
                    (document.summary.pageHeight / document.summary.pageWidth) * 100)

                if element.data.pageDisplayed ~= m_npage then
                    element.data.lastHighlight = {}
                    --element.bgimageInit = false
                    element.data.pageDisplayed = m_npage
                    element:SetClass("loading", true)

                    element.data.textLayout = nil
                    element.bgimage = document:GetPageImageId(m_npage)
                    document:TextLayout(m_npage, function(info)
                        if not element.valid then
                            return
                        end
                        element.data.textLayout = info
                        element:FireEvent("highlight", {}, nil, { changepage = true })
                    end)
                elseif m_searchIndex ~= nil then
                    element:FireEvent("highlight", element.data.lastHighlight)
                end
            end,

            press = function(element)
                if element.data.hoveredLink and element.popup == nil and (m_dragPanel == nil or m_dragPanel:HasClass("hidden")) then
                    --see if we are over a link we can jump to.
                    m_npage = element.data.hoveredLink.destpage
                    m_searchResults = nil
                    RefreshPage()
                    return
                end

                m_dragPanel:FireEvent("hide")
                element:FireEvent("highlight", {})
                element.popup = nil



                local pressCharacter = element.data.FindMouseoverChar(element)
                if pressCharacter ~= nil then
                    local t = dmhub.Time()

                    if dmhub.DeepEqual(element.data.lastPressCharacter, pressCharacter) and (t - (element.data.lastPressCharacterTime or 0)) < 1 then
                        local delimiters
                        if element.data.doubleClickCharacter then
                            element.data.doubleClickCharacter = false

                            --triple click
                            delimiters = "\n\r"

                            --disable back to a normal click.
                            t = nil
                        else
                            --double click
                            delimiters = " \n\r"

                            element.data.doubleClickCharacter = true
                        end

                        local layout = element.data.textLayout

                        if layout ~= nil then
                            local index = pressCharacter.charIndex
                            local index1, index2 = FindTextBoundaries(layout.text, index, delimiters)
                            local a = CharacterIndexToLocation(layout, index1)
                            local b = CharacterIndexToLocation(layout, index2)

                            local rects = {}

                            for i = a.rectIndex, b.rectIndex do
                                local r = DeepCopy(element.data.textLayout.mergedRects[i].rect)
                                if i == a.rectIndex then
                                    local breakIndex = a.breakIndex
                                    if breakIndex < 1 then
                                        breakIndex = 1
                                    end
                                    r.x1 = element.data.textLayout.mergedRects[i].breaks[breakIndex]
                                end

                                if i == b.rectIndex then
                                    local breakIndex = b.breakIndex + 2
                                    if breakIndex > #element.data.textLayout.mergedRects[i].breaks then
                                        breakIndex = #element.data.textLayout.mergedRects[i].breaks
                                    end
                                    r.x2 = element.data.textLayout.mergedRects[i].breaks[breakIndex]
                                end

                                rects[#rects + 1] = r
                            end

                            element:FireEvent("highlight", rects,
                                element.data.textLayout.text:Substring(a.charIndex, b.charIndex))
                        end
                    else
                        element.data.doubleClickCharacter = false
                    end

                    element.data.lastPressCharacterTime = t
                    element.data.lastPressCharacter = pressCharacter
                end
            end,


            dragThreshold = 2,

            beginDrag = function(element)
                element.data.anchorTextDrag = nil
                if (not m_importer) and element.data.textLayout ~= nil then
                    element.data.anchorTextDrag = element.data.FindMouseoverChar(element)
                    if element.data.anchorTextDrag ~= nil then
                        return
                    end
                end

                m_dragAnchor = element.mousePoint
                m_dragPanel:SetClass("hidden", false)
                m_dragPanel:FireEvent("update", element)
            end,

            dragging = function(element)
                if element.data.anchorTextDrag ~= nil then
                    local b = element.data.FindMouseoverChar(element)
                    if b == nil then
                        b = element.data.FindMouseToRightOf(element)
                    end
                    if b == nil then
                        b = element.data.FindMouseBelow(element)
                    end
                    if b ~= nil then
                        local a = element.data.anchorTextDrag
                        if a.charIndex > b.charIndex then
                            local c = a
                            a = b
                            b = c
                        end

                        local rects = {}

                        for i = a.rectIndex, b.rectIndex do
                            local r = DeepCopy(element.data.textLayout.mergedRects[i].rect)
                            if i == a.rectIndex then
                                r.x1 = element.data.textLayout.mergedRects[i].breaks[a.breakIndex]
                            end

                            if i == b.rectIndex then
                                r.x2 = element.data.textLayout.mergedRects[i].breaks[b.breakIndex]
                            end

                            rects[#rects + 1] = r
                        end

                        element:FireEvent("highlight", rects,
                            element.data.textLayout.text:Substring(a.charIndex, b.charIndex))
                    end

                    return
                end

                m_dragPanel:FireEvent("update", element)
            end,

            drag = function(element)
                element.data.anchorTextDrag = nil

                if m_dragPanel:HasClass("hidden") or m_dragAnchor == nil then
                    return
                end

                m_dragPanel:FireEvent("finish", element)
            end,

        }
    }

    dialogPanel = gui.Panel {
        width = "100%",
        height = "100%",
        flow = "vertical",
        id = "pdfViewerDialog",

        styles = {
            {
                valign = "center",
                halign = "center",
                bgcolor = "clear",
            }
        },

        popout = function(element)
            --hacky code to make sure we don't block game interaction.
            --this can be removed once engine support catches up.
            local visit
            visit = function(s)
                s.blocksGameInteraction = false
                for k, v in pairs(s.children) do
                    visit(v)
                end
            end

            visit(element.parent.parent)
        end,

        gotopage = function(element, npage)
            if type(npage) == "string" then
                npage = trim(string.lower(npage))
            end

            m_npage = nil
            for i, label in ipairs(document.summary.pageLabels) do
                if npage == string.lower(label) then
                    m_npage = i - 1
                    break
                end
            end

            m_npage = m_npage or tonumber(npage) or 1

            m_searchResults = nil
            m_searchText = nil
            RefreshPage()
        end,

        -- Page navigation keyboard shortcuts. While the viewer modal is open the
        -- 'journalpdf' command context (pushed in ShowPDFViewerDialog) binds the
        -- left/right arrows to these commands, which are delivered here as 'command'
        -- events. This fires for the whole active modal tree, so the always-present
        -- viewer root is the right place to handle it.
        command = function(element, cmd)
            if cmd == "pdfprevpage" then
                m_npage = m_npage - 1
                m_searchResults = nil
                m_searchText = nil
                RefreshPage()
            elseif cmd == "pdfnextpage" then
                m_npage = m_npage + 1
                m_searchResults = nil
                m_searchText = nil
                RefreshPage()
            end
        end,

        --header panel.
        gui.Panel {
            width = "100%",
            height = 30,
            bmargin = 4,

            gui.Panel {
                width = "auto",
                height = "100%",
                flow = "horizontal",
                halign = "center",

                --                gui.Panel{
                --                    width = 200,
                --                    height = "100%",
                --                    CreateSettingsEditor("pdfbrightness"),
                --                },

                --search bar.
                gui.Panel {
                    width = 300,
                    height = "100%",
                    flow = "horizontal",
                    hpad = 80,
                    gui.SearchInput {
                        placeholderText = "Search...",
                        width = 180,
                        data = {
                            searchid = 0,
                        },

                        inputEvents = { "find" },

                        selectAllOnFocus = true,

                        --- @param element Panel
                        find = function(element)
                            element:ScheduleEvent("dofocus", 0.1)
                        end,

                        dofocus = function(element)
                            gui.SetFocus(nil)
                            gui.SetFocus(element)
                        end,

                        page = function(element)
                            if m_searchResults == nil then
                                element.text = ""
                            end
                        end,
                        search = function(element)
                            print("PDFSEARCH:: Searching... ", element.text)
                            --no change in search.
                            if m_searchText == element.text then
                                print("PDFSEARCH:: Unchanged...")
                                return
                            end

                            if element.text == "" then
                                m_searchText = nil
                                m_searchIndex = nil
                                m_searchResults = nil
                                RefreshPage()
                                print("PDFSEARCH:: CLEAR")
                                return
                            end

                            element.data.searchid = element.data.searchid + 1

                            local searchResults = document:Search(element.text)
                            if searchResults == nil or searchResults == "pending" then
                                element:ScheduleEvent("repeatSearch", 0.1, element.data.searchid)
                                print("PDFSEARCH:: results pending", searchResults)
                                return
                            end

                            m_searchText = element.text

                            if searchResults == "toomany" then
                                print("PDFSEARCH:: toomany")
                                track("search_journal_pdf", {
                                    query = element.text,
                                    hasResults = true,
                                    tooMany = true,
                                    deduplicate = 0.5,
                                    dailyLimit = 50,
                                })
                                return
                            end

                            if type(searchResults) ~= "table" then
                                printf("Unexpected search results: %s", json(searchResults))
                                print("PDFSEARCH:: Unexpected results", searchResults)
                                return
                            end

                            print("PDFSEARCH:: execute!", searchResults)
                            m_searchLen = #element.text
                            dialogPanel:FireEventTree("executeSearch", searchResults)
                            track("search_journal_pdf", {
                                query = element.text,
                                hasResults = #searchResults > 0,
                                resultCount = #searchResults,
                                deduplicate = 0.5,
                                dailyLimit = 50,
                            })
                        end,

                        repeatSearch = function(element, searchid)
                            if searchid ~= element.data.searchid then
                                return
                            end

                            element:FireEvent("search")
                        end,
                    },
                    gui.Panel {
                        width = 100,
                        height = "100%",
                        flow = "horizontal",
                        classes = { "hidden" },

                        page = function(element)
                            element:SetClass("hidden", m_searchResults == nil)
                        end,

                        executeSearch = function(element, searchResults)
                            m_searchResults = searchResults

                            --set the search index to the next page that has a result.
                            m_searchIndex = 1
                            while searchResults[m_searchIndex] ~= nil and searchResults[m_searchIndex].page < m_npage do
                                m_searchIndex = m_searchIndex + 1
                            end

                            if m_searchIndex > #searchResults then
                                m_searchIndex = 1
                            end

                            RefreshPage()
                        end,

                        gui.Label {
                            classes = {"sizeS"},
                            minFontSize = 10,
                            page = function(element)
                                if m_searchResults ~= nil and m_searchResults[m_searchIndex] ~= nil then
                                    element.text = string.format("%d/%d", m_searchIndex, #m_searchResults)
                                else
                                    element.text = "0/0"
                                end
                            end,
                        },

                        gui.Button {
                            classes = {"pagingArrow", "sizeS"},
                            lmargin = 20,
                            page = function(element)
                                element:SetClass("hidden",
                                    not (m_searchResults ~= nil and m_searchResults[m_searchIndex] ~= nil))
                            end,
                            press = function(element)
                                m_searchIndex = m_searchIndex - 1
                                if m_searchIndex <= 0 then
                                    m_searchIndex = #m_searchResults
                                end
                                RefreshPage()
                            end,
                        },

                        gui.Button {
                            classes = {"pagingArrow", "right", "sizeS"},
                            lmargin = 4,
                            page = function(element)
                                element:SetClass("hidden",
                                    not (m_searchResults ~= nil and m_searchResults[m_searchIndex] ~= nil))
                            end,
                            press = function(element)
                                m_searchIndex = m_searchIndex + 1
                                if m_searchIndex > #m_searchResults then
                                    m_searchIndex = 1
                                end
                                RefreshPage()
                            end,
                        },
                    },
                },

                gui.Button {
                    classes = {"pagingArrow", "sizeS"},
                    hmargin = 4,
                    press = function(element)
                        m_npage = m_npage - 1
                        m_searchResults = nil
                        RefreshPage()
                    end,
                },
                gui.Label {
                    classes = {"sizeXs"},
                    hmargin = 4,
                    width = "auto",
                    height = "auto",
                    text = "Page",
                },
                gui.Input {
                    classes = {"sizeXs"},
                    width = 40,
                    characterLimit = 4,
                    textAlignment = "right",
                    hmargin = 4,
                    page = function(element)
                        element.text = document.summary.pageLabels[m_npage + 1] or string.format("%d", m_npage + 1)
                    end,
                    change = function(element)
                        local text = trim(string.lower(element.text))
                        for i, label in ipairs(document.summary.pageLabels) do
                            if text == string.lower(label) then
                                m_npage = i - 1
                                m_searchResults = nil
                                RefreshPage()
                                return
                            end
                        end

                        m_npage = round((tonumber(element.text) or 1) - 1)
                        m_searchResults = nil
                        RefreshPage()
                    end,
                },
                gui.Label {
                    classes = {"sizeXs"},
                    width = "auto",
                    height = "auto",
                    hmargin = "4",
                    text = "/ " .. (document.summary.pageLabels[#document.summary.pageLabels] or string.format("%d", document.summary.npages)),
                },
                gui.Button {
                    classes = {"pagingArrow", "right", "sizeS"},
                    hmargin = 4,
                    press = function(element)
                        m_npage = m_npage + 1
                        m_searchResults = nil
                        m_searchText = nil
                        RefreshPage()
                    end,
                },

                gui.Panel {
                    flow = "horizontal",
                    height = "auto",
                    width = "auto",
                    hmargin = 32,
                    gui.Label {
                        classes = {"sizeXs"},
                        width = "auto",
                        height = "auto",
                        text = "Zoom:",
                    },

                    gui.Input {
                        classes = {"sizeXs"},
                        width = 40,
                        hmargin = 4,
                        valign = "center",
                        text = string.format("%d", round(m_zoom * 100)),
                        change = function(element)
                            m_zoom = clamp((tonumber(element.text) / 100) or m_zoom, 0.05, 8)
                            element.text = string.format("%d", round(m_zoom * 100)),
                                RefreshPage()
                        end,

                        command = function(element, cmd)
                            if cmd == "zoomin" or cmd == "zoomout" then
                                m_zoom = clamp(m_zoom + cond(cmd == "zoomout", -0.2, 0.2), 0.05, 8)
                                element.text = string.format("%d", round(m_zoom * 100)),
                                    RefreshPage()
                            end
                        end,
                    },

                    gui.Label {
                        classes = {"sizeXs"},
                        width = "auto",
                        height = "auto",
                        text = "%",
                    },

                    gui.Button {
                        -- bgcolor = Styles.textColor,
                        classes = {"sizeXs"},
                        icon = "icons/icon_tool/icon_tool_41.png",
                        lmargin = 16,
                        halign = "right",
                        press = function(element)
                            element.parent:FireEventTree("command", "zoomout")
                        end,
                        styles = {
                            {
                                selectors = { "hover" },
                                brightness = 2,
                            },
                        },
                    },
                    gui.Button {
                        -- bgcolor = Styles.textColor,
                        classes = {"sizeXs"},
                        icon = "icons/icon_tool/icon_tool_40.png",
                        halign = "right",
                        press = function(element)
                            element.parent:FireEventTree("command", "zoomin")
                        end,
                        styles = {
                            {
                                selectors = { "hover" },
                                brightness = 2,
                            },
                        },
                    },
                },

                gui.Button {
                    classes = {"settingsButton", "sizeS"},
                    halign = "right",
                    valign = "center",
                    floating = true,
                    hmargin = -32,

                    data = {},

                    press = function(element)
                        if element.data.settingsDialog ~= nil and element.data.settingsDialog.valid then
                            element.data.settingsDialog:DestroySelf()
                            element.data.settingsDialog = nil
                            return
                        end

                        local dialog
                        dialog = gui.Panel {
                            width = 600,
                            height = 200,
                            classes = { "framedPanel" },
                            styles = ThemeEngine.GetStyles(),
                            halign = "center",
                            valign = "center",
                            flow = "vertical",

                            destroy = function()
                                if element ~= nil and element.valid and element.data.settingsDialog == dialog then
                                    element.data.settingsDialog = nil
                                end
                            end,

                            gui.Button {
                                classes = {"closeButton"},
                                floating = true,
                                halign = "right",
                                valign = "top",
                                click = function(element)
                                    dialog:DestroySelf()
                                end,
                            },

                            gui.Label {
                                classes = { "dialogTitle" },
                                width = "auto",
                                height = "auto",
                                text = "PDF Settings",
                                halign = "center",
                                valign = "top",
                            },

                            gui.Panel {
                                tmargin = 60,
                                floating = true,
                                valign = "top",
                                halign = "center",
                                width = "80%",
                                height = "auto",
                                flow = "vertical",

                                CreateSettingsEditor("pdfdark"),
                                CreateSettingsEditor("pdfbrightness"),
                            },
                        }

                        element.data.settingsDialog = dialog

                        gui.ShowModal(dialog)
                    end,
                },
            },
        },

        gui.Panel {
            flow = "horizontal",
            width = "100%",
            height = "100% available",

            CreateSearchResultsPanel(),
            CreateContentsPanel(),

            pdfScrollViewPanel,

        },
    }

    RefreshPage = function()
        if m_searchResults ~= nil and m_searchResults[m_searchIndex] ~= nil then
            m_npage = m_searchResults[m_searchIndex].page
        end

        if m_npage < 0 then
            m_npage = 0
        end

        if m_npage >= document.summary.npages then
            m_npage = document.summary.npages - 1
        end

        m_dragPanel.children = {}
        m_dragPanel:SetClass("hidden", true)

        dialogPanel:FireEventTree("page")

        if m_settings.page ~= m_npage or m_settings.zoom ~= m_zoom then
            m_settings.page = m_npage
            m_settings.zoom = m_zoom
            m_settings.vscroll = pdfScrollViewPanel.vscrollPosition
            WriteSettings()
        end
    end

    RefreshPage()

    return dialogPanel
end

local g_journalWindowedSetting = setting {
    id = "journal:windowed",
    description = "Journal is windowed",
    editor = "check",
    default = false,
    storage = "preference",
}

local g_pdfViewerDialog = nil

mod.shared.ShowPDFViewerDialog = function(doc, starting_page)
    if g_pdfViewerDialog ~= nil and g_pdfViewerDialog.valid then
        if g_pdfViewerDialog.data.doc == doc then
            if starting_page == nil then
                --opening the document that is already open with no page specified toggles it.
                gui.CloseModal()
            else
                g_pdfViewerDialog:FireEventTree("gotopage", starting_page)
            end
            return
        end
        g_pdfViewerDialog:DestroySelf()
    end

    local aspectRatio = dmhub.screenDimensionsBelowTitlebar.x / dmhub.screenDimensionsBelowTitlebar.y

    local document = doc.doc

    local dialogPanel
    dialogPanel = gui.Panel {
        classes = { "framedPanel", cond(g_journalWindowedSetting:Get(), "windowed") },
        pad = 8,
        flow = "vertical",
        data = {
            doc = doc,
        },
        styles = {
            ThemeEngine.GetStyles(),

            {
                selectors = { "framedPanel" },
                width = "100%",
                height = "100%",
            },
            {
                selectors = { "framedPanel", "windowed" },
                width = "100%-776",
                transitionTime = 0.1,
            },
        },



        resize = function(element, width, height)
            element.selfStyle.width = width
            element.selfStyle.height = height
        end,

        destroy = function(element)
            -- Balance the PushCommandContext from when this dialog opened. Keyed on a
            -- per-element flag (not g_pdfViewerDialog) so it pops exactly once for THIS
            -- dialog regardless of destroy ordering: 'destroy' is also fired manually on
            -- the pop-out path, and a reopened-on-a-different-doc dialog may have already
            -- reassigned g_pdfViewerDialog before this old dialog's destroy runs.
            if element.data.pdfContextActive then
                element.data.pdfContextActive = false
                dmhub.PopCommandContext(PDF_COMMAND_CONTEXT)
            end

            if g_pdfViewerDialog == element then
                g_pdfViewerDialog = nil
                GameHud.instance.modalPanel.interactable = true
            end
        end,

        gui.Panel {
            width = "100%-30",
            height = "100%-30",
            halign = "center",
            valign = "center",

            create = function(element)
                element:FireEvent("loading")
            end,

            loading = function(element)
                if document.summary ~= nil then
                    element.children = { ShowPDFViewerDialogInternal(doc, starting_page) }
                else
                    element:ScheduleEvent("loading", 0.01)
                end
            end,

            gui.LoadingIndicator {},
        },

        gui.Panel {
            flow = "horizontal",
            floating = true,
            width = "auto",
            height = 20,
            halign = "right",
            valign = "top",
            hmargin = 0,
            vmargin = 0,

            popout = function(element)
                element:SetClass("hidden", true)
            end,

            gui.Button {
                classes = { "sizeXs" },
                icon = "ui-icons/icon-scale.png",
                valign = "center",
                rmargin = 6,
                linger = function(element)
                    gui.Tooltip("Pop out window")(element)
                end,
                click = function(element)
                    dialogPanel:FireEvent("destroy")
                    dialogPanel:FireEventTree("popout")
                    dialogPanel:MoveToNativeWindow {
                        scaling = 0.9,
                        resizeable = true,
                        updateFrequencyDefocused = 30,
                    }
                    gui.CloseModal()
                end,
            },

            gui.Button {
                classes = { "sizeXs" },
                icon = "drawsteel/Icons_Nav_MinWindow.png",
                valign = "center",
                linger = function(element)
                    gui.Tooltip("Maximize window")(element)
                end,
                setResizeIcon = function(element)
                    local isWindowed = g_journalWindowedSetting:Get()
                    dialogPanel:SetClass("windowed", isWindowed)
                    element:FireEvent("setIcon", isWindowed and "drawsteel/Icons_Nav_MaxWindow.png" or "drawsteel/Icons_Nav_MinWindow.png")
                end,
                create = function(element)
                    element:FireEvent("setResizeIcon")
                end,
                click = function(element)
                    g_journalWindowedSetting:Set(not g_journalWindowedSetting:Get())
                    element:FireEvent("setResizeIcon")
                end,
            },

            gui.Button{
                classes = {"closeButton", "sizeXs"},
                valign = "center",
                escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
                press = function(element)
                    gui.CloseModal()
                    
                end,
            },
        },
    }

    g_pdfViewerDialog = dialogPanel

    -- Activate the PDF page-navigation arrow keys for as long as this modal is up.
    -- The matching PopCommandContext runs in the dialog's destroy handler above,
    -- gated on this same per-element flag so the push/pop stay balanced.
    EnsurePdfCommandBindings()
    dialogPanel.data.pdfContextActive = true
    dmhub.PushCommandContext(PDF_COMMAND_CONTEXT)

    gui.ShowModal(dialogPanel)
    GameHud.instance.modalPanel.interactable = false
end

local function ParseDocumentURL(url)
    local i = string.find(url, ":")
    local doctype = string.sub(url, 1, i - 1)
    url = string.sub(url, i + 1, #url)

    local items = string.split(url, "&")

    local id = items[1]

    local args = {}

    for j = 2, #items do
        local kv = string.split(items[j], "=")
        args[kv[1]] = kv[2]
    end

    return {
        type = doctype,
        id = id,
        args = args,
    }
end

function OpenPDFDocument(doc, page)
    mod.shared.ShowPDFViewerDialog(doc, page)
end

dmhub.OpenDocument = function(url)
    local info = ParseDocumentURL(url)

    if info.type == "pdf" and info.id ~= nil then
        local docs = assets.pdfDocumentsTable
        local doc = docs[info.id]
        if doc ~= nil then
            mod.shared.ShowPDFViewerDialog(doc, info.args.page)
        end
    end
end

dmhub.DescribeDocument = function(url)
    local info = ParseDocumentURL(url)
    if info.type == "pdf" and info.id ~= nil then
        local docs = assets.pdfDocumentsTable
        local doc = docs[info.id]
        if doc ~= nil then
            local result = doc.description
            if tonumber(info.args.page) ~= nil then
                result = string.format("%s, p. %d", result, tonumber(info.args.page) + 1)
            end
            return result
        end
    end

    return "(Unknown)"
end

RegisterGameType("ImageDocument")

ImageDocument.type = "image"
ImageDocument.imageid = ""

function ImageDocument:Render(options)
    options = options or {}
    local summary = options.summary
    options.summary = nil

    local minAspectRatio = 0.5

    local ourAspect = self.width / self.height

    local panelWidth = "100%"
    if ourAspect < minAspectRatio then
        panelWidth = string.format("%f%%", 100 * ourAspect / minAspectRatio)
    end

    local args = {
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Panel {
            width = panelWidth,
            height = string.format("%f%% width", 100 * self.height / self.width),
            bgcolor = "white",
            hoverCursor = cond(summary, "hand"),
            bgimage = self.imageid,
            click = function(element)
                if summary then
                    GameHud.instance:ViewCompendiumEntryModal(self)
                end
            end,
        },
    }

    for k, v in pairs(options) do
        args[k] = v
    end

    return gui.Panel(args)
end

RegisterGameType("PDFWrapper")

PDFWrapper.docid = ""
PDFWrapper.width = 1024
PDFWrapper.height = 1024

function PDFWrapper:Render(options)
    options = options or {}
    local summary = options.summary
    options.summary = nil

    local minAspectRatio = 0.5

    local ourAspect = self.width / self.height

    local panelWidth = "100%"
    if ourAspect < minAspectRatio then
        panelWidth = string.format("%f%%", 100 * ourAspect / minAspectRatio)
    end

    local args = {
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Panel {
            width = panelWidth,
            height = string.format("%f%% width", 100 * self.height / self.width),
            bgcolor = "white",
            hoverCursor = cond(summary, "hand"),
            bgimage = string.format("#PDF:%s|0", self.docid),
            click = function(element)
                if summary then
                    mod.shared.ShowPDFViewerDialog(assets.pdfDocumentsTable[self.docid])
                end
            end,
        },
    }

    for k, v in pairs(options) do
        args[k] = v
    end

    return gui.Panel(args)
end

RegisterGameType("PDFFragment")

PDFFragment.tableName = "pdfReferences"
PDFFragment.refid = "none" --the PDF document we refer to.
PDFFragment.name = "PDF Fragment"
PDFFragment.ord = 0
PDFFragment.AddAlias("description", "name")
PDFFragment.hidden = false
PDFFragment.parentFolder = false
PDFFragment.ownerid = false
PDFFragment.nodeType = "pdffragment"
PDFFragment.width = 1024
PDFFragment.height = 1024
PDFFragment.page = 0
PDFFragment.area = { 0, 0, 1, 1 }
PDFFragment.bookmarks = {}

function PDFFragment:Upload()
    dmhub.SetAndUploadTableItem(self.tableName, self)
end

function PDFFragment:HaveEditPermissions()
    return dmhub.isDM or (self.ownerid == dmhub.loginUserid)
end

function PDFFragment:Render(options)
    options = options or {}
    local summary = options.summary
    options.summary = nil

    local minAspectRatio = 0.5

    local ourAspect = self.width / self.height


    local panelWidth = "100%"
    if ourAspect < minAspectRatio then
        panelWidth = string.format("%f%%", 100 * ourAspect / minAspectRatio)
    end

    printf("Fragment: Render...")

    local link = nil
    local doc = assets.pdfDocumentsTable[self.refid]


    if doc ~= nil and doc.canView then
        local document = doc.doc
        local pagelabel = nil

        local text = nil
        
        --if we have access to this document give a link to the source.
        link = gui.Label {
            classes = { "link" },
            halign = "center",
            fontSize = 14,
            maxWidth = 300,
            width = "auto",
            height = "auto",
            hoverCursor = "hand",
            swallowPress = true,
            click = function(element)
                if pagelabel == nil then
                    return
                end
                local link = string.format("pdf:%s&page=%s", self.refid, pagelabel)
                dmhub.OpenDocument(link)
            end,
            create = function(element)
                if document.summary ~= nil then
                    pagelabel = document.summary.pageLabels[self.page+1]
                    element.text = string.format("%s Page %s", doc.description, pagelabel)
                else
                    element:ScheduleEvent("create", 0.1)
                end
            end,
        }

        if dmhub.isDM then
            link = gui.Panel {
                width = "auto",
                height = "auto",
                flow = "horizontal",
                link,
                gui.VisibilityPanel {
                    hmargin = 2,
                    visible = not doc.hiddenFromPlayers,
                    linger = function(element)
                        gui.Tooltip(cond(doc.hiddenFromPlayers,
                            "This link is hidden from players since they don't have access to the document.",
                            "This link is visible to players since they have access to the document."))(element)
                    end
                },
            }
        end
    end


    local args = {
        width = "100%",
        height = "auto",
        flow = "vertical",
        gui.Panel {
            width = panelWidth,
            height = string.format("%f%% width", 100 * self.height / self.width),
            bgcolor = "white",
            hoverCursor = cond(summary, "hand"),
            bgimage = string.format("#PDF-Fragment:%s|%d,%f,%f,%f,%f", self.refid, self.page, self.area[1], self.area[2], self.area[3], self.area[4]),
            click = function(element)
                if summary then
                    GameHud.instance:ViewCompendiumEntryModal(self)
                end
            end,
        },
        link,

    }

    for k, v in pairs(options) do
        args[k] = v
    end

    return gui.Panel(args)
end
