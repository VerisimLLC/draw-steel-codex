local mod = dmhub.GetModLoading()
print("CHECKPOINT:: CREATE APPEARANCE")

local g_previewToken = nil
local g_previewTokenId = nil

local AppearanceStyles = {
    {
        selectors = { "#appearancePanel" },
        width = "100%",
        height = "100%",
        flow = "horizontal",
    },
    {
        selectors = { "#avatarSelectionPanel" },
        width = "50%",
        height = "50%",
        flow = "vertical",
        halign = "center",
        valign = "center",
    },
    {
        selectors = { "#avatarSelectionPanel", "popout" },
        width = "25%",
        height = "50%",
    },
    {
        selectors = { "avatarEditor", "popout" },
        uiscale = 0.5,
    },

    {
        selectors = { "#portraitSelectionPanel" },
        collapsed = 0,
        width = "25%",
        height = 400,
    },

    {
        selectors = { "#avatarSelectionList" },
        hmargin = 4,
        width = "100%",
        height = "50%",
        flow = "vertical",
        halign = "left",
    },

    {
        selectors = { "#frameSelectionPanel" },
        hmargin = 4,
        width = 196,
        height = 226,
        flow = "vertical",
        halign = "left",
    },

    {
        selectors = { "#ribbonSelectionPanel" },
        hmargin = 4,
        vmargin = 10,
        width = "100%",
        height = "42%",
        flow = "vertical",
        halign = "left",
    },

    {
        selectors = { "#avatarDisplay" },
        bgcolor = "white",
        halign = "center",
        valign = "center",
    },

    {
        selectors = { "selectionPanel" },
        bgimage = "panels/square.png",
        bgcolor = "clear",
    },
    {
        selectors = { "selectionPanel", "hover" },
        borderColor = "grey",
        borderWidth = 2,
    },
    {
        selectors = { "selectionPanel", "press" },
        borderColor = "black",
    },
    {
        selectors = { "selectionPanel", "selected" },
        borderColor = "white",
        borderWidth = 2,
    },

    {
        selectors = { "framePanel" },
        halign = "left",
        width = 60,
        height = 60,
    },
    {
        selectors = { "ribbonPanel" },
        halign = "left",
        width = 120,
        height = 30,
    },
    {
        selectors = { "frameImage" },
        bgcolor = "white",
        halign = "center",
        valign = "center",
        width = "90%",
        height = "90%",
    },
    {
        selectors = { "ribbonImage" },
        bgcolor = "white",
        halign = "center",
        valign = "center",
        width = "auto",
        height = "auto",
        autosizeimage = true,
        minWidth = 100,
        minHeight = 25,
        maxWidth = 100,
        maxHeight = 25,
    },

    {
        selectors = { "avatarPanel" },
        halign = "left",
        width = 60,
        height = 60,
    },

    {
        selectors = { "avatarPanelImage" },
        bgcolor = "white",
        halign = "center",
        valign = "center",
        autosizeimage = true,
        width = "auto",
        height = "auto",
        maxWidth = 54,
        maxHeight = 54,
        minWidth = 54,
        minHeight = 54,
    },

    {
        selectors = { "titleLabel" },
        vmargin = 6,
        halign = "center",
        valign = "top",
        width = "auto",
        height = "auto",
        uppercase = true,
    },
}

gui.RegisterTheme("charsheet", "Appearance", AppearanceStyles)

function CharSheet.CharacterNameLabel()
    return gui.Label {
        id = "characterNameLabel",
        classes = { "statsLabel", "heading" },
        width = "90%",
        textAlignment = "center",
        characterLimit = 30,
        halign = "center",
        valign = "center",
        textWrap = false,
        editable = false,
        text = "TEST",
        minHeight = 26,
        minFontSize = 8,

        click = function(element)
            if element.editing then
                --sometimes pressing space triggers this. Investigate why?
                return
            end
            local info = CharacterSheet.instance.data.info
            local name = info.token.name
            if name == nil or name == "" then
                element.text = ""
            end
            element:BeginEditing()
        end,

        rightClick = function(element)
            local info = CharacterSheet.instance.data.info
            local generator = info.token.properties:GetNameGeneratorTable()
            if generator == nil or #generator.rows == 0 then
                return
            end

            local parentElement = element

            local menuItems = {}

            if generator:IsChoice() then
                for i, row in ipairs(generator.rows) do
                    menuItems[#menuItems + 1] = {
                        text = string.format("Generate %s Name", generator:RowName(i)),
                        click = function()
                            parentElement.popup = nil

                            local result = generator:Roll(i)
                            info.token.name = result:JoinString(" ")
                            info.token:UploadAppearance()
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,
                    }
                end
            else
                menuItems[#menuItems + 1] = {
                    text = "Generate Name",
                    click = function()
                        parentElement.popup = nil

                        local result = generator:Roll()
                        info.token.name = result:JoinString(" ")
                        info.token:UploadAppearance()
                        CharacterSheet.instance:FireEvent("refreshAll")
                    end,
                }
            end

            parentElement.popup = gui.ContextMenu {
                entries = menuItems,
            }
        end,

        change = function(element)
            local info = CharacterSheet.instance.data.info
            info.token.name = element.text
            info.token:UploadAppearance()
            CharacterSheet.instance:FireEvent("refreshAll")
        end,
        refreshAppearance = function(element, info)
            local name = info.token.name
            if name == nil or name == "" then
                element.text = "(No name chosen)"
                element:SetClass("invalid", true)
            else
                element.text = name
                element:SetClass("invalid", false)
            end
        end,

        gui.Panel {
            classes = { "privacyIcon" },
            floating = true,
            swallowPress = true,
            refreshToken = function(element, info)
                if info.token.name == nil or info.token.name == "" and not info.token.namePrivate then
                    element:SetClass("hidden", true)
                    return
                end

                element:SetClass("hidden", false)
                element:SetClass("inactive", not info.token.namePrivate)
            end,
            press = function(element)
                CharacterSheet.instance.data.info.token.namePrivate = not CharacterSheet.instance.data.info.token
                .namePrivate
                CharacterSheet.instance.data.info.token:UploadAppearance()
                element:SetClass("inactive", not element:HasClass("inactive"))
                if element.tooltip ~= nil then
                    element.tooltip = nil
                    element:FireEvent("linger")
                end
            end,
            linger = function(element)
                local tip
                if CharacterSheet.instance.data.info.token.namePrivate then
                    tip = "This token's name is private to the Director and the player(s) who control it"
                else
                    tip = "This token's name can be seen by anyone who can see the token"
                end
                gui.Tooltip(tip)(element)
            end,
        },
    }
end

function CharSheet.RibbonSelectionPanel()
    if not dmhub.GetSettingValue("ribbons") then
        return
    end

    local resultPanel
    local tokenPanels = {}
    local selectedPanel = nil

    local created = false

    resultPanel = gui.Panel {
        id = "ribbonSelectionPanel",
        vscroll = true,
        bgimage = "panels/square.png",

        gui.Label {
            classes = { "statsLabel", "titleLabel" },
            text = "Avatar Ribbon",
        },

        gui.Panel {
            flow = "horizontal",
            width = "95%",
            height = "auto",
            halign = "center",
            valign = "top",
            wrap = true,
            bgimage = "panels/square.png",

            refreshAppearance = function(element, info)
                if created == false then
                    element:FireEvent("refreshCreate")
                    created = true
                end

                local ribbonSelected = info.token.portraitRibbon
                if ribbonSelected == nil then
                    ribbonSelected = 'none'
                end
                if ribbonSelected ~= selectedPanel then
                    if selectedPanel ~= nil then
                        tokenPanels[selectedPanel]:SetClass("selected", false)
                    end

                    if ribbonSelected ~= nil and tokenPanels[ribbonSelected] ~= nil then
                        tokenPanels[ribbonSelected]:SetClass("selected", true)
                        selectedPanel = ribbonSelected
                    end
                end
            end,

            create = function(element)
                if created == false then
                    element:FireEvent("refreshCreate")
                    created = true
                end
            end,

            refreshCreate = function(element)
                local children = {}

                local nonePanel = gui.Panel {
                    classes = { "framePanel", "ribbonPanel", "selectionPanel" },
                    data = { ord = -1000000 },

                    gui.Label {
                        text = "(None)",
                        halign = "center",
                        width = "auto",
                        height = "auto",
                        fontSize = 12,
                        interactable = false,
                    },

                    click = function(element)
                        local info = CharacterSheet.instance.data.info
                        info.token.portraitRibbon = nil
                        info.token:UploadAppearance()
                        CharacterSheet.instance:FireEvent("refreshAll")
                    end,

                }

                tokenPanels['none'] = nonePanel
                children[#children + 1] = nonePanel

                for k, asset in pairs(assets.imagesByTypeTable["AvatarRibbon"] or {}) do
                    local panel = gui.Panel {
                        classes = { "framePanel", "ribbonPanel", "selectionPanel" },

                        data = { ord = asset.ord },

                        gui.Panel {
                            classes = { "ribbonImage" },
                            interactable = false,
                            bgimage = k,
                        },

                        click = function(element)
                            local info = CharacterSheet.instance.data.info
                            info.token.portraitRibbon = k
                            info.token:UploadAppearance()
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,
                    }

                    tokenPanels[k] = panel

                    children[#children + 1] = panel
                end

                table.sort(children, function(a, b) return a.data.ord < b.data.ord end)


                element.children = children
            end,
        }
    }

    return resultPanel
end

function CharSheet.FrameSelectionPanel()
    local resultPanel

    local tokenPanels = {}
    local selectedPanel = nil

    local created = false

    resultPanel = gui.Panel {
        id = "frameSelectionPanel",
        bgimage = "panels/square.png",

        gui.IconEditor {
            library = "AvatarFrame",
            width = 196,
            height = 196,
            halign = "center",
            bgcolor = "white",
            allowNone = true,
            refreshAppearance = function(element, info)
                element.SetValue(element, info.token.portraitFrame, false)
            end,
            change = function(element)
                local info = CharacterSheet.instance.data.info
                info.token.portraitFrame = element.value
                info.token:UploadAppearance()
                CharacterSheet.instance:FireEvent("refreshAll")
            end,
        },

        gui.Label {
            classes = { "statsLabel", "titleLabel" },
            y = -16,
            text = "Frame",
        },
    }

    return resultPanel
end

function CharSheet.FramePreviewPanel()
    local resultPanel

    local previewFloor = nil
    g_previewToken = nil
    local newToken = false

    local m_previewCreatureSize = 1
    local m_previewLightingZoom = 1

    local RecalculatePreviewCamera = function()
        if previewFloor == nil then
            return
        end

        local x = 0
        local y = 0
        if m_previewCreatureSize == 2 then
            x = 0.5
            y = 0.5
            previewFloor.cameraSize = 1.5*m_previewLightingZoom
        elseif m_previewCreatureSize == 3 then
            x = 1
            y = 1
            previewFloor.cameraSize = 2*m_previewLightingZoom
        elseif m_previewCreatureSize == 4 then
            x = 1.5
            y = 1.5
            previewFloor.cameraSize = 2*m_previewLightingZoom
        elseif m_previewCreatureSize >= 5 then
            x = 2.0
            y = 2.0
            previewFloor.cameraSize = 2.5*m_previewLightingZoom
        else
            previewFloor.cameraSize = 1*m_previewLightingZoom
        end

        previewFloor.cameraPos = { x = 0 + x, y = -4 + y }
    end


    local previewLabel = gui.Label {
        text = "This is what your token looks like in-game",
        classes = { "statsLabel" },
        halign = "center",
        valign = "top",
    }

    resultPanel = gui.Panel {
        width = "90%",
        height = "100%",
        flow = "vertical",
        hmargin = 8,
        vmargin = 32,
        halign = "center",

        gui.Panel {
            width = math.floor(1920 / 4),
            height = math.floor(1080 / 4),
            vmargin = 8,
            flow = "vertical",
            halign = "center",

            previewLabel,

            refreshPreviewLighting = function(element)
                if previewFloor ~= nil and CharacterSheet.instance.data.GetPreviewLighting then
                    local lighting = CharacterSheet.instance.data.GetPreviewLighting()
                    previewFloor.lighting = lighting

                    local token = CharacterSheet.instance.data.info.token
                    if g_previewToken ~= nil and g_previewToken.valid then
                        if lighting.useLight then
                            g_previewToken.wieldedObjectsOverride = {
                                mainhand = token.properties:GetEquippedLightSource()
                            }
                        else
                            g_previewToken.wieldedObjectsOverride = {}
                        end

                        if (not dmhub.DeepEqual(g_previewToken.wieldedObjectsOverride, element.data.previousEquipment)) or (not dmhub.DeepEqual(lighting, element.data.previousLighting)) then
                            element.data.previousEquipment = DeepCopy(g_previewToken.wieldedObjectsOverride)
                            element.data.previousLighting = lighting
                            game.Refresh {
                                floors = { previewFloor.floorid },
                                tokens = { g_previewTokenId },
                            }
                        end

                        m_previewLightingZoom = lighting.previewZoom
                        RecalculatePreviewCamera()
                    end
                end
            end,

            refreshToken = function(element, info)
                element:FireEvent("refreshPreviewLighting")
            end,

            refreshAppearance = function(element, info)
                element:FireEvent("refreshPreviewLighting")
            end,

            --fired when this tab is activated or deactivated.
            charsheetActivate = function(element, val)
                dmhub.Debug(string.format("PREVIEW:: CHANGE SHOWING APPEARANCE: %s", tostring(val)))
                if val and previewFloor == nil then
                    previewFloor = game.currentMap:CreatePreviewFloor("ObjectPreview")
                    previewFloor.cameraPos = { x = 0, y = -4 }
                    previewFloor.cameraSize = 1

                    g_previewTokenId = previewFloor:CreateToken(0, -4)

                    game.Refresh {
                        currentMap = true,
                        floors = { previewFloor.floorid },
                        tokens = { g_previewTokenId },
                    }

                    g_previewToken = dmhub.GetTokenById(g_previewTokenId)
                    newToken = true
                    print("PREVIEW:: GET TOKEN:", g_previewTokenId, "TO", g_previewToken)

                    if g_previewToken ~= nil and g_previewToken.valid then
                        element:FireEvent("refreshPreviewLighting")

                        element.children = {
                            gui.Panel {
                                bgimage = "#MapPreview" .. previewFloor.floorid,
                                bgcolor = "white",
                                width = "100%",
                                height = "100%",
                                borderColor = Styles.textColor,
                                borderWidth = 2,
                                destroy = function(element)
                                    local args = {
                                        currentMap = true,
                                        floors = { previewFloor.floorid },
                                        tokens = { g_previewTokenId },
                                    }
                                    game.currentMap:DestroyPreviewFloor(previewFloor)
                                    game.Refresh(args)
                                    previewFloor = nil
                                    g_previewTokenId = nil
                                end,

                                create = function(element)
                                    element:FireEvent("refreshAppearance", CharacterSheet.instance.data.info)
                                end,

                                refreshAppearance = function(element, info)
                                    if g_previewToken == nil or not g_previewToken.valid then
                                        return
                                    end

                                    local sw = dmhub.Stopwatch()

                                    if g_previewToken.properties == nil then
                                        g_previewToken.properties = {}
                                    end

                                    local diffs = 0

                                    if newToken then
                                        g_previewToken.properties = dmhub.DeepCopy(info.token.properties)
                                        diffs = 1
                                    elseif dmhub.Patch(g_previewToken.properties, info.token.properties) then
                                        diffs = 1
                                    end

                                    newToken = false

                                    local fields = { "portraitFrame", "portrait", "portraitBackground", "portraitRibbon",
                                        "portraitFrameHueShift", "name", "ownerId", "portraitZoom", "portraitOffset",
                                        "saddles", "saddleSize", "saddlePositions", "popoutScale" }
                                    for i, field in ipairs(fields) do
                                        if g_previewToken[field] ~= info.token[field] then
                                            g_previewToken[field] = info.token[field]
                                            diffs = diffs + 1
                                        end
                                    end

                                    if diffs > 0 then
                                        game.Refresh {
                                            floors = { previewFloor.floorid },
                                            tokens = { g_previewTokenId },
                                        }

                                        local creatureSizeInfo = dmhub.rules.CreatureSizes[g_previewToken.creatureSizeNumber]

                                        m_previewCreatureSize = creatureSizeInfo.tiles
                                        RecalculatePreviewCamera()

                                        dmhub.Debug(string.format("DIFFS:: AFTER %d -> %s", diffs,
                                            g_previewToken.creatureSize))
                                    end
                                    sw:Report("refreshPortrait")
                                end,
                            },

                            previewLabel,
                        }
                    end

                    previewLabel:SetClass("collapsed", false)

                    dmhub.Debug(string.format("CHANGE SHOWING APPEARANCE: CREATE PREVIEW FLOOR %s", tostring(val)))
                elseif (not val) and previewFloor ~= nil then
                    dmhub.Debug(string.format("CHANGE SHOWING APPEARANCE: DESTROY PREVIEW FLOOR %s", tostring(val)))
                    element.children = { previewLabel }
                    previewLabel:SetClass("collapsed", true)
                end
            end,
        },

        --separator.
        gui.Panel {
            bgimage = "panels/square.png",
            bgcolor = Styles.textColor,
            width = "100%",
            height = 1.5,
            vmargin = 48,
            halign = "center",
        },


        --adjustments panel
        gui.Panel {
            id = "frameAdjustmentPanel",
            width = 256,
            height = 256,
            halign = "center",
            bgimage = "panels/square.png",
            bgcolor = "white",
            clip = true,
            clipHidden = true,
            data = {
                portrait = nil,
            },

            refreshAppearanceForce = function(element)
                CharacterSheet.instance:FireEventTree("refreshAppearance", CharacterSheet.instance.data.info)
            end,

            refreshAppearance = function(element, info)
                if (element.data.portrait ~= nil and info.token.portrait ~= element.data.portrait) or (element.data.offTokenPortrait ~= nil and info.token.offTokenPortrait ~= element.data.offTokenPortrait) then
                    --schedule a refresh event shortly to account for the new portrait being properly loaded.
                    element.data.portrait = info.token.portrait
                    element.data.offTokenPortrait = info.token.offTokenPortrait

                    element:ScheduleEvent("refreshAppearanceForce", 0.1)
                elseif #element.children == 0 then
                    local dragging = false
                    local dragAnchor = nil
                    local dragValue = nil
                    element.data.portrait = info.token.portrait
                    element.data.offTokenPortrait = info.token.offTokenPortrait
                    element.children = {
                        gui.Panel {
                            halign = "center",
                            valign = "center",
                            bgcolor = "#ffffff44",
                            bgimage = cond(info.token.popoutPortrait, info.token.offTokenPortrait, info.token.portrait),
                            refreshAppearance = function(element, info)
                                --element.bgimageInit = false
                                element.bgimage = cond(info.token.popoutPortrait, info.token.offTokenPortrait, info.token.portrait)
                                element:FireEvent("imageLoaded")
                            end,

                            selfStyle = {
                                width = "100%",
                                height = "100%",
                            },
                            data = {
                                xratio = 1,
                                yratio = 1,
                            },

                            press = function(element)
                                element.thinkTime = 0.02
                                dragging = true
                                dragAnchor = element.mousePoint
                                dragValue = CharacterSheet.instance.data.info.token.portraitOffset
                            end,

                            unpress = function(element)
                                element.thinkTime = nil
                                dragging = false
                                dragAnchor = nil
                                dragValue = nil

                                CharacterSheet.instance.data.info.token:UploadAppearance()
                                CharacterSheet.instance:FireEvent("refreshAppearanceOnly")
                            end,

                            think = function(element)
                                if dragging then
                                    local dx = element.mousePoint.x - dragAnchor.x
                                    local dy = element.mousePoint.y - dragAnchor.y
                                    local val = {
                                        x = dragValue.x + dx,
                                        y = dragValue.y + dy,
                                    }
                                    if g_previewToken ~= nil and g_previewToken.valid then
                                        g_previewToken.portraitOffset = val
                                    end
                                    CharacterSheet.instance.data.info.token.portraitOffset = val
                                    --game.Refresh()
                                    element:FireEventTree("recalculate")
                                end
                            end,
                            imageLoaded = function(element)
                                if element.bgsprite == nil then
                                    print("ImageLoaded:: NONE")
                                    return
                                end

                                print("ImageLoaded:: ", element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)

                                local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
                                local xratio = (element.bgsprite.dimensions.x) / maxDim
                                local yratio = (element.bgsprite.dimensions.y) / maxDim

                                element.data.xratio = xratio
                                element.data.yratio = yratio

                                element.selfStyle.width = string.format("%0.2f%%", 100 * xratio)
                                element.selfStyle.height = string.format("%0.2f%%", 100 * yratio)

                                element:FireEventTree("recalculate")
                            end,

                            gui.Panel {
                                floating = true,
                                bgimage = "panels/square.png",
                                bgcolor = "#ffffff66",
                                borderColor = "white",
                                halign = "left",
                                valign = "top",
                                interactable = false,

                                --the frame panel.
                                gui.Panel {
                                    width = "100%",
                                    height = "100%",
                                    bgcolor = "white",
                                },

                                selfStyle = {
                                },
                                recalculate = function(element)
                                    local framePanel = element.children[1] --the child frame.

                                    local tok = CharacterSheet.instance.data.info.token
                                    local portrait = cond(tok.popoutPortrait, tok.offTokenPortrait, tok.portrait)
                                    local rect = cond(tok.popoutPortrait, tok:GetPortraitRectForAspect(Styles.portraitWidthPercentOfHeight*0.01, portrait), tok.portraitRect)

                                    element.selfStyle.width = string.format("%.2f%%", (rect.x2 - rect.x1) * 100)
                                    element.selfStyle.height = string.format("%.2f%%", (rect.y2 - rect.y1) * 100)
                                    element.selfStyle.x = element.parent.data.xratio * 300 * rect.x1
                                    element.selfStyle.y = element.parent.data.yratio * 300 * (1 - rect.y2)

                                    if tok.portraitFrame ~= nil and tok.portraitFrame ~= '' and (not tok.popoutPortrait) then
                                        element.bgimage = portrait
                                        element.bgimageTokenMask = tok.portraitFrame
                                        element.selfStyle.imageRect = tok.portraitRect

                                        element.selfStyle.borderWidth = 0
                                        element.selfStyle.bgcolor = "white"
                                        framePanel.bgimage = tok.portraitFrame
                                        framePanel.selfStyle.hueshift = tok.portraitFrameHueShift
                                        framePanel:SetClass("hidden", false)
                                    else
                                        element.bgimage = "panels/square.png"
                                        element.bgimageTokenMask = nil
                                        element.selfStyle.imageRect = nil
                                        element.selfStyle.bgcolor = "#ffffff11"
                                        element.selfStyle.borderWidth = 2
                                        framePanel:SetClass("hidden", true)
                                    end

                                    if #element.children ~= 1 + info.token.saddles then
                                        local children = { framePanel }

                                        for i = 1, info.token.saddles do
                                            local n = i
                                            children[#children + 1] = gui.Panel {
                                                bgimage = "panels/horse-saddle.png",
                                                bgcolor = "white",
                                                swallowPress = true,
                                                width = 50,
                                                height = 50,
                                                floating = true,
                                                halign = "center",
                                                valign = "center",
                                                data = {},

                                                pos = function(element, pos)
                                                    local zoom = CharacterSheet.instance.data.info.token.portraitZoom
                                                    element.x = 300 * pos.x * zoom
                                                    element.y = -300 * pos.y * zoom
                                                end,

                                                refreshAppearance = function(element, info)
                                                    --saddle size is the creature size + 10%. Calculate that as the saddleSize divided by the creatureSize since
                                                    --canvas size is given by the mount size.
                                                    local mountRect = info.token.portraitRect
                                                    local mountSize = mountRect.x2 - mountRect.x1
                                                    local sizeRatio = dmhub.CreatureSizeToTokenScale(info.token
                                                    .saddleSize) /
                                                    dmhub.CreatureSizeToTokenScale(info.token.creatureSize)
                                                    element.selfStyle.width = mountSize * 300 * sizeRatio
                                                    element.selfStyle.height = mountSize * 300 * sizeRatio

                                                    local pos = info.token.saddlePositions[n]
                                                    if pos ~= nil then
                                                        element:FireEvent("pos", pos)
                                                    end
                                                end,

                                                press = function(element)
                                                    dmhub.Debug("PRESS:: " ..
                                                    dmhub.ToJson(element.parent.mousePoint ~= nil))
                                                    if element.parent.mousePoint ~= nil then
                                                        element.thinkTime = 0.02
                                                        element.data.dragging = true
                                                        element.data.dragAnchor = element.parent.mousePoint

                                                        local pos = info.token.saddlePositions[n]
                                                        element.data.anchorPos = { x = pos.x, y = pos.y }
                                                    end
                                                end,

                                                unpress = function(element)
                                                    element.thinkTime = nil
                                                    element.data.dragging = false
                                                    element.data.dragAnchor = nil
                                                    element.data.anchorPos = nil

                                                    CharacterSheet.instance.data.info.token:UploadAppearance()
                                                    CharacterSheet.instance:FireEvent("refreshAppearanceOnly")
                                                end,

                                                think = function(element)
                                                    if element.data.dragging and element.parent.mousePoint ~= nil then
                                                        local zoom = CharacterSheet.instance.data.info.token
                                                        .portraitZoom
                                                        local dx = (element.parent.mousePoint.x - element.data.dragAnchor.x)
                                                        local dy = (element.parent.mousePoint.y - element.data.dragAnchor.y)
                                                        local positions = info.token.saddlePositions
                                                        local pos = positions[n]
                                                        pos.x = element.data.anchorPos.x + dx
                                                        pos.y = element.data.anchorPos.y + dy
                                                        info.token.saddlePositions = positions

                                                        element:FireEvent("pos", pos)

                                                        --CharacterSheet.instance.data.info.token.portraitOffset = val
                                                    end
                                                end,
                                            }
                                        end

                                        element.children = children
                                    end
                                end,
                                refreshAppearance = function(element, info)
                                    element:FireEvent("recalculate")
                                end,
                            },
                        }
                    }
                end
            end,
        },

        gui.Panel {
            width = "auto",
            height = "auto",
            flow = "vertical",
            halign = "center",

            gui.Panel {
                classes = { "formPanel", "appearanceSlider" },
                gui.Label {
                    classes = { "statsLabel", "sliderLabel" },
                    text = "Scale:",
                },
                gui.Slider {
                    style = {
                        height = 30,
                        width = 420,
                        fontSize = 14,
                    },


                    refreshAppearance = function(element, info)
                        element.value = info.token.tokenScale
                    end,

                    valign = "center",
                    labelFormat = "rawpercent",
                    unclamped = true,
                    sliderWidth = 340,
                    labelWidth = 50,
                    minValue = 0,
                    maxValue = 2,
                    events = {
                        change = function(element)
                            if g_previewToken ~= nil and g_previewToken.valid then
                                g_previewToken.tokenScale = element.value
                                game.Refresh {
                                    tokens = { g_previewTokenId },
                                }
                            end
                        end,
                        confirm = function(element)
                            CharacterSheet.instance.data.info.token.tokenScale = element.value
                            CharacterSheet.instance.data.info.token:UploadAppearance()
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,
                    },
                },
            },

            --zoom.
            gui.Panel {
                classes = { "formPanel", "appearanceSlider" },
                gui.Label {
                    classes = { "statsLabel", "sliderLabel" },
                    text = "Zoom:",
                },
                gui.Slider {
                    style = {
                        height = 30,
                        width = 420,
                        fontSize = 14,
                    },


                    refreshAppearance = function(element, info)
                        printf("ZOOM:: refreshAppearance %s at %s", json(info.token.portraitZoom), traceback())
                        element.value = info.token.portraitZoom
                    end,


                    valign = "center",
                    labelFormat = "rawpercent",
                    sliderWidth = 340,
                    labelWidth = 50,
                    minValue = 0,
                    maxValue = 2,
                    unclamped = true,
                    events = {
                        create = function(element)
                        end,
                        change = function(element)
                            if g_previewToken ~= nil and g_previewToken.valid then
                                --refresh the zoom specifically
                                CharacterSheet.instance.data.info.token.portraitZoom = element.value

                                g_previewToken.portraitZoom = element.value
                                game.Refresh {
                                    tokens = { g_previewTokenId },
                                }

                                element:Get("frameAdjustmentPanel"):FireEventTree("recalculate")
                                --CharacterSheet.instance:FireEvent("refreshAppearance", CharacterSheet.instance.data.info)
                            end
                        end,
                        confirm = function(element)
                            CharacterSheet.instance.data.info.token.portraitZoom = element.value
                            CharacterSheet.instance.data.info.token:UploadAppearance()
                            CharacterSheet.instance:FireEvent("refreshAll")
                        end,
                    },
                },
            },

            gui.Button {
                halign = "center",
                fontSize = 16,
                vmargin = 12,
                text = "Reset Placement",
                click = function(element)
                    CharacterSheet.instance.data.info.token.portraitZoom = 1
                    CharacterSheet.instance.data.info.token.portraitOffset = { x = 0, y = 0 }
                    CharacterSheet.instance.data.info.token.saddlePositions = nil
                    CharacterSheet.instance.data.info.token:UploadAppearance()
                    CharacterSheet.instance:FireEvent("refreshAll")
                end,
            },
        },

        --some padding.
        gui.Panel {
            width = 1,
            height = 16,
        },

        gui.IconEditor {
            library = "AvatarBackground",
            width = 96,
            height = 96,
            cornerRadius = 96 / 2,
            halign = "center",
            bgcolor = "white",
            allowNone = true,
            categoriesHidden = true,
            refreshAppearance = function(element, info)
                element:SetClass("collapsed", not info.token.popoutPortrait)
                if element:HasClass("collapsed") == false then
                    element.SetValue(element, info.token.portraitBackground, false)
                end
            end,
            change = function(element)
                local info = CharacterSheet.instance.data.info
                info.token.portraitBackground = element.value
                info.token:UploadAppearance()
                CharacterSheet.instance:FireEvent("refreshAll")
            end,
        },

        gui.Label {
            classes = { "statsLabel", "titleLabel" },
            y = -16,
            text = "Background",
            refreshAppearance = function(element, info)
                element:SetClass("collapsed", not info.token.popoutPortrait)
            end,
        },

        gui.Slider {
            style = {
                height = 30,
                width = 260,
                fontSize = 14,
            },

            halign = "center",
            sliderWidth = 160,
            labelWidth = 50,
            minValue = 0,
            maxValue = 2,

            refreshAppearance = function(element, info)
                element:SetClass("collapsed", not info.token.popoutPortrait)
                print("PopoutScale: ", info.token.popoutScale)
                element.value = info.token.popoutScale
                if g_previewToken ~= nil and g_previewToken.valid then
                    g_previewToken.popoutScale = info.token.popoutScale
                end
            end,
            change = function(element)
                if g_previewToken ~= nil and g_previewToken.valid then
                    g_previewToken.popoutScale = element.value
                    game.Refresh {
                        tokens = { g_previewTokenId },
                    }
                end
            end,
            confirm = function(element)
                CharacterSheet.instance.data.info.token.popoutScale = element.value
                CharacterSheet.instance.data.info.token:UploadAppearance()
                CharacterSheet.instance:FireEvent("refreshAll")
            end,
        },


    }
    return resultPanel
end

local mountOptions = {
    {
        id = "0",
        text = "Not Mountable",
    },

    {
        id = "1",
        text = "One Saddle",
    },
    {
        id = "2",
        text = "Two Saddles",
    },
    {
        id = "3",
        text = "Three Saddles",
    },
    {
        id = "4",
        text = "Four Saddles",
    },
    {
        id = "5",
        text = "Five Saddles",
    },
    {
        id = "6",
        text = "Six Saddles",
    },
    {
        id = "7",
        text = "Seven Saddles",
    },
    {
        id = "8",
        text = "Eight Saddles",
    },
    {
        id = "9",
        text = "Nine Saddles",
    },
    {
        id = "10",
        text = "Ten Saddles",
    },
    {
        id = "11",
        text = "Eleven Saddles",
    },
    {
        id = "12",
        text = "Twelve Saddles",
    },
    {
        id = "13",
        text = "Thirteen Saddles",
    },
    {
        id = "14",
        text = "Fourteen Saddles",
    },
    {
        id = "15",
        text = "Fifteen Saddles",
    },
    {
        id = "16",
        text = "Sixteen Saddles",
    },
    {
        id = "17",
        text = "Seventeen Saddles",
    },
}

function CharSheet.PortraitSelectionPanel()
    local resultPanel

    resultPanel = gui.Panel {
        id = "portraitSelectionPanel",
        halign = "center",
        valign = "top",
        flow = "vertical",

        gui.IconEditor {
            id = "avatarIconEditor",
            library = "Avatar",
            restrictImageType = "Avatar",
            allowPaste = true,
            borderColor = Styles.textColor,
            borderWidth = 2,
            width = "auto",
            height = "auto",
            autosizeimage = true,
            maxWidth = 200,
            maxHeight = 200,
            halign = "center",
            valign = "center",
            bgcolor = "white",

            thinkTime = 0.2,
            think = function(element)
                element:FireEvent("imageLoaded")
            end,
--[[
           imageLoaded = function(element)
                if element.bgsprite == nil then
                    return
                end

                local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
                if maxDim > 0 then
                    local yratio = element.bgsprite.dimensions.x / maxDim
                    local xratio = element.bgsprite.dimensions.y / maxDim
                    element.selfStyle.imageRect = { x1 = 0, y1 = 1 - yratio, x2 = xratio, y2 = 1 }
                end
            end,
]]
            refreshAppearance = function(element, info)
                element.SetValue(element, info.token.offTokenPortrait, false)
                element:FireEvent("imageLoaded")
            end,
            change = function(element)
                local info = CharacterSheet.instance.data.info
                info.token.offTokenPortrait = element.value
                info.token:UploadAppearance()
                CharacterSheet.instance:FireEvent("refreshAll")
                element:FireEvent("imageLoaded")
            end,
        },

        gui.Label {
            classes = { "statsLabel", "titleLabel" },
            uppercase = false,
            text = "Portrait",
            halign = "center",
            valign = "bottom",
            fontSize = 26,
            bmargin = 40,
        },
    }

    return resultPanel
end

function CharSheet.AvatarSelectionPanel()
    local resultPanel
    local created = false
    local tokenPanels = {}
    local selectedPanel = nil

    local popoutAvatar = gui.Panel {
        classes = { "hidden" },
        interactable = false,
        width = 800,
        height = 800,
        halign = "center",
        valign = "center",
        bgcolor = "white",
    }

    resultPanel = gui.Panel {
        id = "avatarSelectionPanel",
        flow = "vertical",
        styles = {
            {
                selectors = "#characterNameLabel",
                vmargin = 16,
                fontSize = 36,
            },
            {
                selectors = { "#characterNameLabel", "popout" },
                fontSize = 24,
            },

        },

        gui.Panel {
            classes = { "avatarEditor" },
            width = 400,
            height = 400,
            halign = "center",

            gui.IconEditor {
                library = cond(dmhub.GetSettingValue("popoutavatars"), "popoutavatars", "Avatar"),
                restrictImageType = "Avatar",
                allowPaste = true,
                borderColor = Styles.textColor,
                borderWidth = 2,
                cornerRadius = 200,
                width = 400,
                height = 400,
                autosizeimage = true,
                halign = "center",
                valign = "center",
                bgcolor = "white",

                children = { popoutAvatar, },

                thinkTime = 0.2,
                think = function(element)
                    element:FireEvent("imageLoaded")
                end,

                updatePopout = function(element, ispopout)
                    if not ispopout then
                        popoutAvatar:SetClass("hidden", true)
                    else
                        popoutAvatar:SetClass("hidden", false)
                        popoutAvatar.bgimage = element.value
                        popoutAvatar.selfStyle.scale = 1/CharacterSheet.instance.data.info.token.popoutScale
                        element.bgimage = "panels/square.png"
                    end

                    local parent = element:FindParentWithClass("avatarSelectionParent")

                    if parent ~= nil then
                        parent:SetClassTree("popout", ispopout)
                    end
                end,

                imageLoaded = function(element)
                    if element.bgsprite == nil then
                        return
                    end

                    local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
                    if maxDim > 0 then
                        local yratio = element.bgsprite.dimensions.x / maxDim
                        local xratio = element.bgsprite.dimensions.y / maxDim
                        element.selfStyle.imageRect = { x1 = 0, y1 = 1 - yratio, x2 = xratio, y2 = 1 }
                    end
                end,

                refreshAppearance = function(element, info)
                    print("APPEARANCE:: Set avatar", info.token.portrait)
                    element.SetValue(element, info.token.portrait, false)
                    element:FireEvent("imageLoaded")
                    element:FireEvent("updatePopout", info.token.popoutPortrait)
                end,
                change = function(element)
                    local info = CharacterSheet.instance.data.info
                    info.token.portrait = element.value
                    info.token:UploadAppearance()
                    CharacterSheet.instance:FireEvent("refreshAll")
                    element:FireEvent("imageLoaded")
                end,
            },

        },

        CharSheet.CharacterNameLabel(),

        gui.Panel {
            flow = "vertical",
            width = "auto",
            height = "auto",
            halign = "center",
            refreshAppearance = function(element, info)
                element:SetClass("hidden", dmhub.isDM or (not info.token.canControl) or (not info.token.primaryCharacter))
            end,

            gui.Label {
                classes = { "statsLabel" },
                text = "Player Color:",
                halign = "center",
            },

            gui.ColorPicker {
                styles = {
                    {
                        width = 24,
                        height = 24,
                        cornerRadius = 12,
                        borderWidth = 1,
                        borderColor = "#aaaaaa",
                    },
                    {
                        selectors = { "hover" },
                        borderColor = "white",
                    }
                },
                vmargin = 4,
                halign = "center",
                hasAlpha = false,
                value = dmhub.GetSettingValue("playercolor"),
                change = function(element)
                    dmhub.SetSettingValue("playercolor", element.value)
                end,
            },
        },

    }

    return resultPanel
end

function CharSheet.MountablePanel()
    --saddles panel.
    return gui.Panel {
        id = "saddleSettings",
        width = "50%",
        height = "auto",
        halign = "right",
        flow = "vertical",
        refreshAppearance = function(element, info)

        end,

        gui.Dropdown {
            halign = "center",
            change = function(element)
                local info = CharacterSheet.instance.data.info
                info.token.saddles = tonumber(element.idChosen)
                info.token:UploadAppearance()
                CharacterSheet.instance:FireEvent("refreshAll")
            end,
            refreshAppearance = function(element, info)
                element.idChosen = tostring(info.token.saddles)
            end,

            options = mountOptions,

            idChosen = "none",
        },

        gui.Panel {
            width = "100%",
            flow = "vertical",
            refreshAppearance = function(element, info)
                element:SetClass("collapsed", info.token.saddles == 0)
            end,

            gui.Label {
                halign = "center",
                classes = { "statsLabel", "titleLabel" },
                text = "Can Carry...",
            },

            gui.Dropdown {
                halign = "center",
                options = creature.sizes,
                idChosen = "0",
                refreshAppearance = function(element, info)
                    element.idChosen = tostring(info.token.saddleSize)
                end,
                change = function(element)
                    local info = CharacterSheet.instance.data.info
                    info.token.saddleSize = element.idChosen
                    info.token:UploadAppearance()
                    CharacterSheet.instance:FireEvent("refreshAll")
                end,
            },

        },

    }
end

function CharSheet.AppearancePanel()
    local divider = gui.Panel {
        height = "100%-64",
        valign = "center",
        halign = "center",
        width = 1,
        bgimage = "panels/square.png",
        bgcolor = Styles.textColor,
        hmargin = 0,
    }

    local m_tokenPanels = {}


    local addVariationButton = gui.Panel {
        halign = "center",
        width = 80,
        height = 80,
        vmargin = 6,
        hmargin = 6,
        hover = gui.Tooltip("Add a variation to this creature's appearance"),
        gui.AddButton {
            halign = "center",
            valign = "center",
            width = 64,
            height = 64,

            refreshAppearance = function(element, info)
                element:SetClass("hidden", info.token.numAppearanceVariations > 7)
            end,


        },
        gui.Panel { classes = { "variationBorder" } },

        press = function(element)
            local info = CharacterSheet.instance.data.info
            info.token:SwitchAppearanceVariation(info.token.numAppearanceVariations)
            CharacterSheet.instance:FireEvent("refreshAll")
        end,
    }

    local m_alternateAppearancePanels = {}

    local avatarPanel = gui.Panel {
        width = "100%",
        height = "100%-30",
        valign = "bottom",
        flow = "vertical",

        --top panel on the left.
        gui.Panel {
            classes = { "avatarSelectionParent" },
            vmargin = 32,
            height = "auto",
            valign = "top",
            width = "100%",
            flow = "horizontal",

            CharSheet.AvatarSelectionPanel(),

            --only valid if we are using a popout avatar.
            CharSheet.PortraitSelectionPanel(),

            --panel allowing variation selection.
            gui.Panel {
                height = "auto",
                width = "auto",
                flow = "vertical",
                valign = "top",
                halign = "right",
                minWidth = 200,


                gui.Panel {
                    width = "auto",
                    height = 480,
                    flow = "vertical",
                    halign = "center",
                    wrap = true,

                    styles = {
                        {
                            selectors = { "variation" },
                            width = 80,
                            height = 80,
                            vmargin = 6,
                            hmargin = 6,
                            halign = "center",
                        },
                        {
                            selectors = { "variationBorder" },
                            borderColor = Styles.textColor,
                            border = 3,

                            bgimage = "panels/square.png",
                            bgcolor = "clear",
                            cornerRadius = 40,
                            width = "100%",
                            height = "100%",
                            brightness = 0.7,

                        },
                        {
                            selectors = { "variationBorder", "parent:hover" },
                            brightness = 1.5,
                        },
                        {
                            selectors = { "variationBorder", "parent:selected" },
                            brightness = 1.5,
                        },
                        {
                            selectors = { "token-image", "parent:hover" },
                            brightness = 1.5,
                        },
                        {
                            selectors = { "token-image", "parent:selected" },
                            brightness = 1.5,
                        },

                    },




                    addVariationButton,

                    refreshAppearance = function(element, info)
                        local nvariations = info.token.numAppearanceVariations
                        for i = 1, nvariations do
                            local index = i
                            if m_tokenPanels[i] == nil then
                                m_tokenPanels[i] = gui.Panel {
                                    classes = { "variation" },
                                    press = function(element)
                                        local info = CharacterSheet.instance.data.info
                                        info.token:SwitchAppearanceVariation(index - 1)
                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end,
                                    rightClick = function(element)
                                        if element:HasClass("selected") then
                                            return
                                        end

                                        element.popup = gui.ContextMenu {
                                            entries = {
                                                {
                                                    text = "Delete",
                                                    click = function()
                                                        CharacterSheet.instance.data.info.token
                                                            :DeleteAppearanceVariation(index - 1)
                                                        element.popup = nil
                                                        CharacterSheet.instance:FireEvent("refreshAll")
                                                    end,
                                                }
                                            }
                                        }
                                    end,
                                    gui.CreateTokenImage(info.token, {
                                        halign = "center",
                                        valign = "center",
                                        width = 94,
                                        height = 94,
                                    }),

                                    gui.Panel { classes = { "variationBorder" } },
                                }
                            end
                            m_tokenPanels[i]:FireEventTree("token", info.token:GetVariationInfo(i - 1))
                            m_tokenPanels[i]:SetClass("selected", info.token.alternateAppearanceOverride == nil and info.token.appearanceVariationIndex + 1 == i)
                        end

                        for index, panel in ipairs(m_tokenPanels) do
                            panel:SetClass("collapsed", index > nvariations)
                        end

                        local children = {}
                        for _, panel in ipairs(m_tokenPanels) do
                            children[#children + 1] = panel
                        end

                        children[#children + 1] = addVariationButton

                        local alternateAppearances = info.token.properties:GetAlternateAppearances()

                        local newAlternateAppearancePanels = {}
                        if alternateAppearances ~= nil then

                            local keys = table.keys(alternateAppearances)
                            table.sort(keys)
                            for _,key in ipairs(keys) do
                                local appearanceInfo = alternateAppearances[key]
                                local panel = m_alternateAppearancePanels[key] or gui.Panel{
                                    flow = "vertical",
                                    width = "auto",
                                    height = "auto",
                                    disable = function(element)
                                        if element:HasClass("selected") then
                                            local info = CharacterSheet.instance.data.info
                                            if info ~= nil and info.token ~= nil and info.token.valid then
                                                info.token:SwitchAppearanceVariation(0)
                                            end
                                        end
                                    end,
                                    press = function(element)
                                        local defaultToken = nil
                                        local monster = assets.monsters[appearanceInfo.monsterDefault]
                                        if monster ~= nil then
                                            defaultToken = monster.info
                                        end 
                                        local info = CharacterSheet.instance.data.info
                                        info.token:OverrideAlternateAppearance(key, defaultToken)
                                        CharacterSheet.instance:FireEvent("refreshAll")
                                    end,
                                    rightClick = function(element)
                                        element.popup = gui.ContextMenu {
                                            entries = {
                                                {
                                                    text = "Revert",
                                                    click = function()
                                                        CharacterSheet.instance.data.info.token
                                                            :ClearAlternateAppearance(key)
                                                        element.popup = nil
                                                        CharacterSheet.instance:FireEvent("refreshAll")
                                                    end,
                                                }
                                            }
                                        }
                                    end,

                                    gui.Panel{
                                        classes = { "variation" },
                                        gui.CreateTokenImage(info.token, {
                                            halign = "center",
                                            valign = "center",
                                            width = 94,
                                            height = 94,
                                        }),

                                        gui.Panel { classes = { "variationBorder" } },
                                    },

                                    gui.Label{
                                        textAlignment = "center",
                                        halign = "center",
                                        fontSize = 14,
                                        width = 84,
                                        height = "auto",
                                        text = key,
                                    },
                                }

                                local appearance = info.token:GetAlternateAppearanceInfo(key)
                                if appearance ~= nil then
                                    panel:FireEventTree("token", appearance)
                                elseif appearanceInfo.monsterDefault ~= "none" then
                                    local monster = assets.monsters[appearanceInfo.monsterDefault]
                                    if monster ~= nil then
                                        panel:FireEventTree("token", monster.info)
                                    else
                                        panel:FireEventTree("token", info.token)
                                    end
                                end

                                panel:SetClassTree("selected", info.token.alternateAppearanceOverride == key)
                                print("ALT::", key, info.token.alternateAppearanceOverride)

                                newAlternateAppearancePanels[key] = panel
                                children[#children+1] = panel
                            end
                        end

                        m_alternateAppearancePanels = newAlternateAppearancePanels

                        addVariationButton:SetClass("collapsed", nvariations >= 8)

                        element.children = children
                    end,
                },
            },
        },

        gui.Panel {
            flow = "horizontal",
            height = 196,
            width = "100%",
            valign = "top",
            y = -24,
            gui.Panel {
                id = "anthemPanel",
                flow = "vertical",
                hmargin = 4,
                width = 196,
                height = 190,
                gui.AudioEditor {
                    width = 140,
                    height = 140,
                    halign = "left",
                    valign = "center",
                    hmargin = 32,
                    autoplay = true,
                    refreshAppearance = function(element, info)
                        element.value = CharacterSheet.instance.data.info.token.anthem
                    end,
                    change = function(element)
                        CharacterSheet.instance.data.info.token.anthem = element.value
                        CharacterSheet.instance.data.info.token:UploadAppearance()
                        CharacterSheet.instance:FireEvent("refreshAll")
                    end,
                },

                gui.Label {
                    text = "Anthem",
                    y = -6,
                    classes = { "statsLabel", "titleLabel" },
                },

                gui.Slider {
                    floating = true,
                    valign = "bottom",
                    style = {
                        height = 16,
                        width = 80,
                    },

                    halign = "center",

                    sliderWidth = 80,
                    minValue = 0,
                    maxValue = 1,

                    change = function(element)
                        element:Get("anthemPanel"):FireEventTree("volume", element.value)
                    end,


                    confirm = function(element)
                        element:Get("anthemPanel"):FireEventTree("volume", element.value)
                        CharacterSheet.instance.data.info.token.anthemVolume = element.value
                        CharacterSheet.instance.data.info.token:UploadAppearance()
                    end,

                    refreshAppearance = function(element, info)
                        local anthem = CharacterSheet.instance.data.info.token.anthem
                        if anthem ~= nil and anthem ~= "" then
                            element:SetClass("hidden", false)
                            element.value = CharacterSheet.instance.data.info.token.anthemVolume
                        else
                            element:SetClass("hidden", true)
                        end
                    end,
                },
            },

            CharSheet.MountablePanel(),
        },

        gui.Panel {
            flow = "horizontal",
            height = 220,
            width = "100%",
            valign = "top",

            CharSheet.FrameSelectionPanel(),

            gui.Panel {
                width = "70%",
                height = "auto",
                flow = "vertical",
                valign = "top",

                gui.Panel {
                    classes = { "formPanel", "appearanceSlider" },
                    gui.Label {
                        classes = { "statsLabel", "sliderLabel" },
                        text = "Hue:",
                    },
                    gui.Slider {
                        style = {
                            height = 30,
                            width = 420,
                            fontSize = 14,
                        },


                        refreshAppearance = function(element, info)
                            element.value = info.token.portraitFrameHueShift
                        end,

                        valign = "center",
                        labelFormat = "percent",
                        sliderWidth = 340,
                        labelWidth = 50,
                        minValue = 0,
                        maxValue = 1,
                        events = {
                            change = function(element)
                                if g_previewToken ~= nil and g_previewToken.valid then
                                    g_previewToken.portraitFrameHueShift = element.value
                                    game.Refresh {
                                        tokens = { g_previewTokenId },
                                    }
                                end
                            end,
                            confirm = function(element)
                                CharacterSheet.instance.data.info.token.portraitFrameHueShift = element.value
                                CharacterSheet.instance.data.info.token:UploadAppearance()
                                CharacterSheet.instance:FireEvent("refreshAll")
                            end,
                        },
                    },
                },

                gui.Panel {
                    classes = { "formPanel", "appearanceSlider" },
                    gui.Label {
                        classes = { "statsLabel", "sliderLabel" },
                        text = "Saturation:",
                    },
                    gui.Slider {
                        style = {
                            height = 30,
                            width = 420,
                            fontSize = 14,
                        },


                        refreshAppearance = function(element, info)
                            element.value = info.token.portraitFrameSaturation
                        end,

                        valign = "center",
                        labelFormat = "percent",
                        sliderWidth = 340,
                        labelWidth = 50,
                        minValue = 0,
                        maxValue = 1,
                        events = {
                            change = function(element)
                                if g_previewToken ~= nil and g_previewToken.valid then
                                    g_previewToken.portraitFrameSaturation = element.value
                                    game.Refresh {
                                        tokens = { g_previewTokenId },
                                    }
                                end
                            end,
                            confirm = function(element)
                                CharacterSheet.instance.data.info.token.portraitFrameSaturation = element.value
                                CharacterSheet.instance.data.info.token:UploadAppearance()
                                CharacterSheet.instance:FireEvent("refreshAll")
                            end,
                        },
                    },
                },

                gui.Panel {
                    classes = { "formPanel", "appearanceSlider" },
                    gui.Label {
                        classes = { "statsLabel", "sliderLabel" },
                        text = "Brightness:",
                    },
                    gui.Slider {
                        style = {
                            height = 30,
                            width = 420,
                            fontSize = 14,
                        },


                        refreshAppearance = function(element, info)
                            element.value = info.token.portraitFrameBrightness
                        end,

                        valign = "center",
                        labelFormat = "percent",
                        sliderWidth = 340,
                        labelWidth = 50,
                        minValue = 0,
                        maxValue = 1,
                        events = {
                            change = function(element)
                                if g_previewToken ~= nil and g_previewToken.valid then
                                    g_previewToken.portraitFrameBrightness = element.value
                                    game.Refresh {
                                        tokens = { g_previewTokenId },
                                    }
                                end
                            end,
                            confirm = function(element)
                                CharacterSheet.instance.data.info.token.portraitFrameBrightness = element.value
                                CharacterSheet.instance.data.info.token:UploadAppearance()
                                CharacterSheet.instance:FireEvent("refreshAll")
                            end,
                        },
                    },
                },

            },
        },
    }

    local effectsPanel = gui.Panel {
        width = "100%",
        height = "100%-30",
        valign = "bottom",
        flow = "vertical",

        gui.Panel {
            vmargin = 16,
            flow = "horizontal",
            halign = "center",
            valign = "top",
            width = 400,
            height = 24,
            gui.Label {
                text = "Light Style:",
                width = "auto",
                height = "auto",
                fontSize = 16,
                halign = "left",
                valign = "center",
            },
            gui.Dropdown {
                width = 180,
                height = 26,
                valign = "center",
                halign = "right",
                fontSize = 20,
                options = {},
                change = function(element)
                    local info = CharacterSheet.instance.data.info
                    local equipment = info.token.properties:Equipment()
                    if element.idChosen == "none" then
                        equipment.mainhand1 = nil
                    else
                        equipment.mainhand1 = element.idChosen
                    end
                    info.token.properties.initLight = true
                    CharacterSheet.instance:FireEvent("refreshAll")
                end,
                refreshAppearance = function(element, info)
                    local ismonster = info.token.properties:IsMonster()
                    local customLights = info.token.properties:GetCustomLightSources()
                    local options = {}
                    local equipmentTable = dmhub.GetTable(equipment.tableName)
                    for k, entry in unhidden_pairs(equipmentTable) do
                        if EquipmentCategory.IsLightSource(entry) and (entry:try_get("availability", "available") == "available" or customLights[entry.id] or (ismonster and entry:try_get("availability") == "monsters")) then
                            options[#options + 1] = {
                                id = entry.id,
                                text = entry.name,
                            }


                        end

                        
                    end

                    table.sort(options, function(a, b)
                        return a.text < b.text
                    end)
                    table.insert(options, 1, { id = "none", text = "None" })
                    element.options = options

                    local token = info.token
                    local light = token.properties:GetEquippedLightSource()

                    if light == nil or equipmentTable[light] == nil then
                        element.idChosen = "none"
                    else
                        element.idChosen = light
                    end
                end,
            }
        }
    }

    local m_currentPreviewLighting = 1
    local m_previewLighting = {
        {
            useLight = false,
            previewZoom = 1,
            outdoors = "#ffffff",
            indoors = "#ffffff",
            illumination = 1,
            shadow = {
                dir = core.Vector2(3, 0.6),
                color = "#00000088",
            }
        },
        {
            useLight = true,
            previewZoom = 3,
            outdoors = "#312c5a",
            indoors = "#312c5a",
            illumination = 0.4,
        }
    }


    local m_tabs = { avatarPanel, effectsPanel }

    local appearanceTabPanel = gui.Panel {
        flow = "horizontal",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "top",
        vmargin = 6,

        create = function(element)
            CharacterSheet.instance.data.GetPreviewLighting = function()
                return m_previewLighting[m_currentPreviewLighting]
            end
        end,

        styles = Styles.Tabs,

        selectTab = function(element, tab)
            for i, child in ipairs(element.children) do
                if child == tab then
                    m_currentPreviewLighting = i
                end
                child:SetClass("selected", child == tab)
                m_tabs[i]:SetClass("collapsed", child ~= tab)
            end

            CharacterSheet.instance:FireEventTree("refreshPreviewLighting")
        end,

        gui.Label {
            classes = { "tab", "selected" },
            text = "Avatar",
            press = function(element)
                element.parent:FireEvent("selectTab", element)
            end,
        },
        gui.Label {
            classes = { "tab" },
            text = "Effects",
            press = function(element)
                element.parent:FireEvent("selectTab", element)
            end,
        },
    }

    local leftPanel = gui.Panel {
        id = "leftPanel",
        height = "100%",
        halign = "center",
        valign = "center",
        width = "48%",
        flow = "vertical",

        appearanceTabPanel,
        avatarPanel,
        effectsPanel,
    }

    local rightPanel = gui.Panel {
        id = "rightPanel",
        height = "100%",
        halign = "center",
        valign = "center",
        width = "48%",
        flow = "vertical",


        CharSheet.FramePreviewPanel(),
    }


    return gui.Panel {
        theme = "charsheet.Appearance",
        id = "appearancePanel",
        classes = { "characterSheetParentPanel", "appearance", "hidden" },
        floating = true,
        flow = "horizontal",
        bgimage = "panels/square.png",

        styles = {
            {
                selectors = { "sliderLabel" },
                minWidth = 120,
                valign = "center",
            },
            {
                selectors = { "appearanceSlider" },
                width = "auto",
                height = 50,
                halign = "center",
                valign = "top",
                flow = "horizontal",
                bgimage = "panels/square.png",
                bgcolor = "clear",
                border = { y1 = 2, x1 = 0, x2 = 0, y2 = 0 },
                borderColor = Styles.textColor,

            }
        },

        leftPanel,
        divider,
        rightPanel,



        --main avatar editing.
        gui.Panel {
            classes = { "collapsed" },
            width = "100%",
            height = "100%-48",
            flow = "horizontal",

            CharSheet.AvatarSelectionPanel(),

            gui.Panel {
                width = "25%",
                height = "100%",
                flow = "vertical",
                CharSheet.FrameSelectionPanel(),
                CharSheet.RibbonSelectionPanel(),
            },
            --CharSheet.FramePreviewPanel(),
        },

    }
end

CharSheet.RegisterTab {
    id = "Appearance",
    text = "Appearance",
    panel = CharSheet.AppearancePanel,
}
