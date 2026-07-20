local mod = dmhub.GetModLoading()
print("CHECKPOINT:: CREATE APPEARANCE")

local g_previewToken = nil
local g_previewTokenId = nil

--Dev gate for the Teleportation animation picker on the character sheet. Off by default so
--the average player doesn't see it; flip on with /set dev:customizeteleport true.
local g_customizeTeleportSetting = setting{
    id = "dev:customizeteleport",
    description = "Show the Teleportation animation picker on the character sheet.",
    default = false,
    storage = "preference",
}

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
        bgimage = true,
        bgcolor = "clear",
    },
    {
        selectors = { "selectionPanel", "hover" },
        borderColor = "@border",
        borderWidth = 2,
    },
    {
        selectors = { "selectionPanel", "press" },
        borderColor = "@fgStrong",
    },
    {
        selectors = { "selectionPanel", "selected" },
        borderColor = "@accent",
        borderWidth = 2,
    },

    {
        selectors = { "appearancePreviewFrame" },
        borderColor = "@border",
        borderWidth = 2,
    },
    {
        selectors = { "appearanceDivider" },
        bgcolor = "@border",
    },
    {
        selectors = { "appearanceIconFrame" },
        borderColor = "@border",
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
        color = "@fgStrong",
    },
}

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
                        classes = {"sizeS"},
                        text = "(None)",
                        halign = "center",
                        width = "auto",
                        height = "auto",
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
                                classes = {"appearancePreviewFrame"},
                                bgimage = "#MapPreview" .. previewFloor.floorid,
                                bgcolor = "white",
                                width = "100%",
                                height = "100%",
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
                                        g_previewToken.properties = DeepCopy(info.token.properties)
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
            classes = {"appearanceDivider"},
            bgimage = true,
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
                    },


                    refreshAppearance = function(element, info)
                        element.value = info.token.tokenScale
                    end,

                    valign = "center",
                    labelFormat = "rawpercent",
                    unclamped = true,
                    sliderWidth = 340,
                    labelWidth = 50,
                    -- Hard minimum: a tokenScale below 0.3 shrinks the rendered token
                    -- to (near) nothing, making it invisible-but-selectable. The engine
                    -- also clamps to 0.3 (CharacterAppearance.MinTokenScaling) as a backstop.
                    minValue = 0.3,
                    maxValue = 2,
                    events = {
                        change = function(element)
                            local v = math.max(0.3, element.value)
                            if g_previewToken ~= nil and g_previewToken.valid then
                                g_previewToken.tokenScale = v
                                game.Refresh {
                                    tokens = { g_previewTokenId },
                                }
                            end
                        end,
                        confirm = function(element)
                            CharacterSheet.instance.data.info.token.tokenScale = math.max(0.3, element.value)
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
                classes = {"sizeM"},
                halign = "center",
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

        --Unframed tokens shape their drop shadow from the portrait image's alpha, so an
        --opaque (non-transparent) image casts a full square shadow. Let the user turn the
        --shadow off. Only shown for unframed, non-popout tokens (framed/popout shadows are
        --masked to the frame and never square).
        gui.Check {
            id = "castShadowCheck",
            text = "Cast Shadow",
            halign = "center",
            vmargin = 8,
            refreshAppearance = function(element, info)
                local hasFrame = info.token.portraitFrame ~= nil and info.token.portraitFrame ~= ''
                local unframed = (not hasFrame) and (not info.token.popoutPortrait)
                element:SetClass("collapsed", not unframed)
                element.value = (info.token.hideShadow == false)
                if g_previewToken ~= nil and g_previewToken.valid then
                    g_previewToken.hideShadow = info.token.hideShadow
                end
            end,
            change = function(element)
                local info = CharacterSheet.instance.data.info
                info.token.hideShadow = (element.value == false)
                if g_previewToken ~= nil and g_previewToken.valid then
                    g_previewToken.hideShadow = info.token.hideShadow
                    game.Refresh { tokens = { g_previewTokenId } }
                end
                info.token:UploadAppearance()
                CharacterSheet.instance:FireEvent("refreshAll")
            end,
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
            classes = {"appearanceIconFrame"},
            id = "avatarIconEditor",
            library = "Avatar",
            restrictImageType = "Avatar",
            allowPaste = true,
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
            classes = {"statsLabel", "titleLabel", "sizeXl"},
            uppercase = false,
            text = "Portrait",
            halign = "center",
            valign = "bottom",
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
                classes = {"appearanceIconFrame"},
                library = "Avatar",
                restrictImageType = "Avatar",
                allowPaste = true,
                cornerRadius = 200,
                width = 400,
                height = 400,
                autosizeimage = true,
                halign = "center",
                valign = "center",
                bgcolor = "white",

                children = { popoutAvatar, },

                rightClick = function(element)
                    if not dmhub.GetSettingValue("dev") then return end
                    element.popup = gui.ContextMenu{
                        entries = {
                            {
                                text = "Open URL",
                                click = function()
                                    element.popup = nil
                                    local imageid = element.value
                                    if (imageid == nil or imageid == "") and popoutAvatar.bgimage ~= nil and popoutAvatar.bgimage ~= "" then
                                        imageid = popoutAvatar.bgimage
                                    end
                                    dmhub.OpenImageAssetURL(imageid)
                                end,
                            }
                        },
                    }
                end,

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
                styles = ThemeEngine.MergeTokens{
                    {
                        width = 24,
                        height = 24,
                        cornerRadius = 12,
                        borderWidth = 1,
                        borderColor = "@border",
                    },
                    {
                        selectors = { "hover" },
                        borderColor = "@accent",
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

        gui.Label{
            classes = {"link"},
            fontSize = 16,
            text = "TitanCraft Token Builder",
            width = "auto",
            height = "auto",
            halign = "center",
            valign = "bottom",
            click = function(element)
                dmhub.OpenURL("https://titancraft.com/?ref=codex")
            end,
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

--Builds a plain table with the monster's appearance plus the custom look on
--top, in the shape gui.CreateTokenImage's "token" event expects.
local function MakeSummonLookToken(monster, look)
    local info = monster.info
    local fake = {
        portrait = info.portrait,
        portraitFrame = info.portraitFrame,
        portraitFrameHueShift = info.portraitFrameHueShift,
        portraitRect = info.portraitRect,
        popoutPortrait = false,
    }

    if look ~= nil then
        if look.portrait ~= nil and look.portrait ~= "" then
            fake.portrait = look.portrait
            fake.portraitRect = { x1 = 0, y1 = 0, x2 = 1, y2 = 1 }
        end
        if look.portraitFrame ~= nil then
            fake.portraitFrame = look.portraitFrame
        end
        if look.portraitFrameHueShift ~= nil then
            fake.portraitFrameHueShift = look.portraitFrameHueShift
        end
    end

    return fake
end

local function SummonMonsterName(monster)
    local name = monster.name
    if name == nil or name == "" then
        name = monster.properties:try_get("monster_type", "Summon")
    end
    return name
end

--Per-character cache of the customizable-summons list. Cleared when the
--Appearance tab is opened so newly summoned creatures show up.
local g_summonListCacheCharid = nil
local g_summonListCache = nil

local function GetCustomizableSummonsCached(token)
    if ActivatedAbilitySummonBehavior == nil then
        return {}
    end
    if g_summonListCache == nil or g_summonListCacheCharid ~= token.charid then
        g_summonListCacheCharid = token.charid
        g_summonListCache = ActivatedAbilitySummonBehavior.GetCustomizableSummons(token)
    end
    return g_summonListCache
end

local function InvalidateSummonListCache()
    g_summonListCache = nil
end

--Which summon is selected in the Summons sub-tab. File-scope because the
--editor panel and the right-column preview panel both use it. Changes are
--broadcast sheet-wide via the "refreshSummonLook" event.
local g_summonSelectedKey = nil
local g_summonSelectedMonster = nil

local function GetSummonLook()
    if g_summonSelectedKey == nil then
        return nil
    end
    return CharacterSheet.instance.data.info.token.properties:GetSummonAppearance(g_summonSelectedKey)
end

local function SaveSummonLook(mutator)
    if g_summonSelectedKey == nil then
        return
    end
    local lookKey = g_summonSelectedKey
    local tok = CharacterSheet.instance.data.info.token
    tok:ModifyProperties{
        description = "Change summon appearance",
        execute = function()
            local t = tok.properties:get_or_add("summonAppearances", {})
            local look = t[lookKey] or {}
            mutator(look)
            if next(look) == nil then
                look = nil
            end
            t[lookKey] = look

            --so the creature stays listed after its live summons are gone.
            tok.properties:RecordSummonHistory(lookKey)
        end,
    }
    ActivatedAbilitySummonBehavior.RestyleLiveSummons(tok, lookKey)
    CharacterSheet.instance:FireEvent("refreshAll")
    CharacterSheet.instance:FireEventTree("refreshSummonLook")
end

local function RevertSummonLook(lookKey)
    local tok = CharacterSheet.instance.data.info.token
    tok:ModifyProperties{
        description = "Change summon appearance",
        execute = function()
            local t = tok.properties:try_get("summonAppearances")
            if t ~= nil then
                t[lookKey] = nil
            end
        end,
    }
    ActivatedAbilitySummonBehavior.RestyleLiveSummons(tok, lookKey)
    CharacterSheet.instance:FireEvent("refreshAll")
    CharacterSheet.instance:FireEventTree("refreshSummonLook")
end

--The "Summons" sub-tab: swatch list of summoned creatures on the left, editor
--for the selected one (avatar, frame, hue, revert) on the right.
function CharSheet.SummonsAppearancePanel()
    local resultPanel

    local m_swatchPanels = {}

    local function UpdateSelectionClasses()
        for key,panel in pairs(m_swatchPanels) do
            panel:SetClassTree("selected", key == g_summonSelectedKey)
        end
    end

    local swatchContainer = gui.Panel{
        flow = "horizontal",
        wrap = true,
        width = 220,
        height = "auto",
        halign = "center",
        valign = "top",
    }

    local listPanel = gui.Panel{
        width = 240,
        height = "100%",
        valign = "top",
        halign = "left",
        flow = "vertical",

        gui.Label{
            classes = { "statsLabel", "titleLabel" },
            halign = "center",
            vmargin = 8,
            text = "Summons",
            linger = function(element)
                gui.Tooltip("Customize how the creatures you summon look.")(element)
            end,
        },

        gui.Panel{
            width = "100%",
            height = "100%-40",
            valign = "top",
            vscroll = true,
            swatchContainer,
        },
    }

    local previewPanel
    previewPanel = gui.Panel{
        width = 140,
        height = 140,
        halign = "center",
        vmargin = 8,

        gui.CreateTokenImage(nil, {
            width = 130,
            height = 130,
            halign = "center",
            valign = "center",
        }),

        refreshSummonLook = function(element)
            if g_summonSelectedMonster == nil then
                return
            end
            element:FireEventTree("token", MakeSummonLookToken(g_summonSelectedMonster, GetSummonLook()))
        end,

        --live preview while the hue slider is dragged, before confirm.
        previewHue = function(element, value)
            if g_summonSelectedMonster == nil then
                return
            end
            local fake = MakeSummonLookToken(g_summonSelectedMonster, GetSummonLook())
            fake.portraitFrameHueShift = value
            element:FireEventTree("token", fake)
        end,
    }

    local editorPanel = gui.Panel{
        width = "100%-260",
        height = "100%",
        halign = "right",
        valign = "top",
        flow = "vertical",

        refreshSummonLook = function(element)
            element:SetClass("hidden", g_summonSelectedKey == nil)
        end,

        gui.Label{
            classes = { "statsLabel", "titleLabel" },
            halign = "center",
            vmargin = 8,
            text = "",
            refreshSummonLook = function(element)
                if g_summonSelectedMonster ~= nil then
                    element.text = SummonMonsterName(g_summonSelectedMonster)
                end
            end,
        },

        previewPanel,

        gui.Panel{
            width = "100%",
            height = "auto",
            flow = "horizontal",
            halign = "center",
            tmargin = 12,

            gui.Panel{
                width = "50%",
                height = "auto",
                flow = "vertical",

                gui.IconEditor{
                    library = "Avatar",
                    restrictImageType = "Avatar",
                    allowPaste = true,
                    cornerRadius = 100,
                    width = 200,
                    height = 200,
                    halign = "center",
                    bgcolor = "white",
                    refreshSummonLook = function(element)
                        if g_summonSelectedMonster == nil then
                            return
                        end
                        local look = GetSummonLook()
                        local value = g_summonSelectedMonster.info.portrait
                        if look ~= nil and look.portrait ~= nil and look.portrait ~= "" then
                            value = look.portrait
                        end
                        element.SetValue(element, value, false)
                    end,
                    change = function(element)
                        SaveSummonLook(function(look)
                            if element.value == nil or element.value == "" or (g_summonSelectedMonster ~= nil and element.value == g_summonSelectedMonster.info.portrait) then
                                look.portrait = nil
                            else
                                look.portrait = element.value
                            end
                        end)
                    end,
                },

                gui.Label{
                    classes = { "statsLabel", "titleLabel" },
                    halign = "center",
                    tmargin = 6,
                    text = "Avatar",
                },
            },

            gui.Panel{
                width = "50%",
                height = "auto",
                flow = "vertical",

                gui.IconEditor{
                    library = "AvatarFrame",
                    allowNone = true,
                    width = 200,
                    height = 200,
                    halign = "center",
                    bgcolor = "white",
                    refreshSummonLook = function(element)
                        if g_summonSelectedMonster == nil then
                            return
                        end
                        local look = GetSummonLook()
                        local value = g_summonSelectedMonster.info.portraitFrame
                        if look ~= nil and look.portraitFrame ~= nil then
                            value = look.portraitFrame
                        end
                        element.SetValue(element, value, false)
                    end,
                    change = function(element)
                        SaveSummonLook(function(look)
                            look.portraitFrame = element.value or ""
                        end)
                    end,
                },

                gui.Label{
                    classes = { "statsLabel", "titleLabel" },
                    halign = "center",
                    tmargin = 6,
                    text = "Frame",
                },
            },
        },

        gui.Panel{
            classes = { "formPanel", "appearanceSlider" },
            halign = "center",
            tmargin = 12,

            gui.Label{
                classes = { "statsLabel", "sliderLabel" },
                text = "Hue:",
            },
            gui.Slider{
                style = {
                    height = 30,
                    width = 420,
                },
                valign = "center",
                labelFormat = "percent",
                sliderWidth = 340,
                labelWidth = 50,
                minValue = 0,
                maxValue = 1,
                refreshSummonLook = function(element)
                    if g_summonSelectedMonster == nil then
                        return
                    end
                    local look = GetSummonLook()
                    local value = g_summonSelectedMonster.info.portraitFrameHueShift or 0
                    if look ~= nil and look.portraitFrameHueShift ~= nil then
                        value = look.portraitFrameHueShift
                    end
                    element.value = value
                end,
                events = {
                    change = function(element)
                        previewPanel:FireEvent("previewHue", element.value)
                    end,
                    confirm = function(element)
                        SaveSummonLook(function(look)
                            look.portraitFrameHueShift = element.value
                        end)
                    end,
                },
            },
        },

        gui.Button{
            text = "Revert to Default",
            width = 180,
            height = 40,
            halign = "center",
            tmargin = 16,
            click = function(element)
                if g_summonSelectedKey ~= nil then
                    RevertSummonLook(g_summonSelectedKey)
                end
            end,
        },
    }

    resultPanel = gui.Panel{
        id = "summonsAppearancePanel",
        classes = { "collapsed" },
        width = "100%",
        height = "100%-30",
        valign = "bottom",
        flow = "horizontal",

        styles = ThemeEngine.MergeTokens{
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
                borderColor = "@border",
                border = 3,
                bgimage = true,
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
                borderColor = "@accent",
                border = 4,
                brightness = 1.5,
            },
            {
                selectors = { "variationBorder", "parent:customized" },
                borderColor = "@accent",
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

        listPanel,
        editorPanel,

        --clear the cache when the Appearance tab opens so new summons show up.
        charsheetActivate = function(element, active)
            if active then
                InvalidateSummonListCache()
            end
        end,

        refreshAppearance = function(element, info)
            local list = GetCustomizableSummonsCached(info.token)

            --keep the selection valid; default to the first summon.
            local found = false
            for _,entry in ipairs(list) do
                if entry.key == g_summonSelectedKey then
                    g_summonSelectedMonster = entry.monster
                    found = true
                    break
                end
            end
            if not found then
                g_summonSelectedKey = nil
                g_summonSelectedMonster = nil
                if #list > 0 then
                    g_summonSelectedKey = list[1].key
                    g_summonSelectedMonster = list[1].monster
                end
            end

            local newSwatchPanels = {}
            local children = {}
            for _,entry in ipairs(list) do
                local lookKey = entry.key
                local monster = entry.monster
                local panel = m_swatchPanels[lookKey] or gui.Panel{
                    flow = "vertical",
                    width = "auto",
                    height = "auto",

                    press = function(element)
                        g_summonSelectedKey = lookKey
                        g_summonSelectedMonster = monster
                        UpdateSelectionClasses()
                        CharacterSheet.instance:FireEventTree("refreshSummonLook")
                    end,

                    rightClick = function(element)
                        local tok = CharacterSheet.instance.data.info.token
                        if tok.properties:GetSummonAppearance(lookKey) == nil then
                            return
                        end
                        element.popup = gui.ContextMenu {
                            entries = {
                                {
                                    text = "Revert",
                                    click = function()
                                        element.popup = nil
                                        RevertSummonLook(lookKey)
                                    end,
                                }
                            }
                        }
                    end,

                    linger = function(element)
                        gui.Tooltip(string.format("%s - right-click to revert.", SummonMonsterName(monster)))(element)
                    end,

                    gui.Panel{
                        classes = { "variation" },
                        gui.CreateTokenImage(monster.info, {
                            halign = "center",
                            valign = "center",
                            width = 94,
                            height = 94,
                        }),

                        gui.Panel { classes = { "variationBorder" } },
                    },

                    gui.Label{
                        classes = {"sizeS"},
                        textAlignment = "center",
                        halign = "center",
                        width = 84,
                        height = "auto",
                        text = SummonMonsterName(monster),
                    },
                }
                newSwatchPanels[lookKey] = panel

                local look = info.token.properties:GetSummonAppearance(lookKey)
                panel:FireEventTree("token", MakeSummonLookToken(monster, look))
                panel:SetClassTree("customized", look ~= nil)

                children[#children+1] = panel
            end

            m_swatchPanels = newSwatchPanels
            swatchContainer.children = children

            UpdateSelectionClasses()
            element:FireEventTree("refreshSummonLook")
        end,
    }

    return resultPanel
end

--Right column for the Summons sub-tab: an in-game preview of the selected
--summon plus Scale/Zoom sliders that save into its look. The preview floor
--only exists while this sub-tab is visible.
function CharSheet.SummonPreviewPanel()
    local resultPanel

    local m_floor = nil
    local m_tokenid = nil
    local m_token = nil
    local m_tabSelected = false
    local m_creatureSize = 1

    local function RecalculateCamera()
        if m_floor == nil then
            return
        end

        local x = 0
        local y = 0
        if m_creatureSize == 2 then
            x = 0.5
            y = 0.5
            m_floor.cameraSize = 1.5
        elseif m_creatureSize == 3 then
            x = 1
            y = 1
            m_floor.cameraSize = 2
        elseif m_creatureSize == 4 then
            x = 1.5
            y = 1.5
            m_floor.cameraSize = 2
        elseif m_creatureSize >= 5 then
            x = 2.0
            y = 2.0
            m_floor.cameraSize = 2.5
        else
            m_floor.cameraSize = 1
        end

        m_floor.cameraPos = { x = 0 + x, y = -4 + y }
    end

    local mapImagePanel = gui.Panel{
        classes = {"appearancePreviewFrame"},
        bgcolor = "white",
        width = "100%",
        height = "100%",
    }

    local function PopulatePreview()
        if m_floor == nil or m_token == nil or (not m_token.valid) then
            return
        end
        if g_summonSelectedKey == nil then
            return
        end
        local monsterid, monster = ActivatedAbilitySummonBehavior.ResolveSummonLookMonster(g_summonSelectedKey)
        if monster == nil then
            return
        end

        m_token.properties = DeepCopy(monster.properties)

        --bestiary defaults first, then the custom look, same as a real spawn.
        m_token.portrait = monster.info.portrait
        m_token.portraitFrame = monster.info.portraitFrame
        m_token.portraitFrameHueShift = monster.info.portraitFrameHueShift
        m_token.tokenScale = monster.info.tokenScale
        m_token.portraitZoom = monster.info.portraitZoom
        m_token.portraitOffset = monster.info.portraitOffset
        ActivatedAbilitySummonBehavior.ApplySummonLook(CharacterSheet.instance.data.info.token, m_token, g_summonSelectedKey)

        game.Refresh {
            floors = { m_floor.floorid },
            tokens = { m_tokenid },
        }

        local creatureSizeInfo = dmhub.rules.CreatureSizes[m_token.creatureSizeNumber]
        m_creatureSize = creatureSizeInfo.tiles
        RecalculateCamera()
    end

    local function DestroyPreview()
        if m_floor == nil then
            return
        end
        local args = {
            currentMap = true,
            floors = { m_floor.floorid },
            tokens = { m_tokenid },
        }
        game.currentMap:DestroyPreviewFloor(m_floor)
        game.Refresh(args)
        m_floor = nil
        m_tokenid = nil
        m_token = nil
        mapImagePanel.bgimage = nil
    end

    local function CreatePreview()
        if m_floor ~= nil then
            return
        end
        m_floor = game.currentMap:CreatePreviewFloor("ObjectPreview")
        m_floor.cameraPos = { x = 0, y = -4 }
        m_floor.cameraSize = 1

        m_tokenid = m_floor:CreateToken(0, -4)

        game.Refresh {
            currentMap = true,
            floors = { m_floor.floorid },
            tokens = { m_tokenid },
        }

        m_token = dmhub.GetTokenById(m_tokenid)
        mapImagePanel.bgimage = "#MapPreview" .. m_floor.floorid

        PopulatePreview()
    end

    resultPanel = gui.Panel {
        id = "summonPreviewPanel",
        classes = { "collapsed" },
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

            mapImagePanel,

            gui.Label {
                text = "This is what your summon looks like in-game",
                classes = { "statsLabel" },
                halign = "center",
                valign = "top",
            },
        },

        --separator.
        gui.Panel {
            classes = {"appearanceDivider"},
            bgimage = true,
            width = "100%",
            height = 1.5,
            vmargin = 48,
            halign = "center",
        },

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
                },
                valign = "center",
                labelFormat = "rawpercent",
                unclamped = true,
                sliderWidth = 340,
                labelWidth = 50,
                --below 0.3 the token becomes too small to see; engine clamps there too.
                minValue = 0.3,
                maxValue = 2,
                refreshSummonLook = function(element)
                    if g_summonSelectedMonster == nil then
                        return
                    end
                    local look = GetSummonLook()
                    local value = g_summonSelectedMonster.info.tokenScale or 1
                    if look ~= nil and look.tokenScale ~= nil then
                        value = look.tokenScale
                    end
                    element.value = value
                end,
                events = {
                    change = function(element)
                        if m_token ~= nil and m_token.valid then
                            m_token.tokenScale = math.max(0.3, element.value)
                            game.Refresh {
                                tokens = { m_tokenid },
                            }
                        end
                    end,
                    confirm = function(element)
                        local v = math.max(0.3, element.value)
                        SaveSummonLook(function(look)
                            look.tokenScale = v
                        end)
                    end,
                },
            },
        },

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
                },
                valign = "center",
                labelFormat = "rawpercent",
                unclamped = true,
                sliderWidth = 340,
                labelWidth = 50,
                minValue = 0,
                maxValue = 2,
                refreshSummonLook = function(element)
                    if g_summonSelectedMonster == nil then
                        return
                    end
                    local look = GetSummonLook()
                    local value = g_summonSelectedMonster.info.portraitZoom or 1
                    if look ~= nil and look.portraitZoom ~= nil then
                        value = look.portraitZoom
                    end
                    element.value = value
                end,
                events = {
                    change = function(element)
                        if m_token ~= nil and m_token.valid then
                            m_token.portraitZoom = element.value
                            game.Refresh {
                                tokens = { m_tokenid },
                            }
                        end
                    end,
                    confirm = function(element)
                        local v = element.value
                        SaveSummonLook(function(look)
                            look.portraitZoom = v
                        end)
                    end,
                },
            },
        },

        gui.Button {
            classes = {"sizeM"},
            halign = "center",
            vmargin = 12,
            text = "Reset Placement",
            click = function(element)
                SaveSummonLook(function(look)
                    look.tokenScale = nil
                    look.portraitZoom = nil
                    look.portraitOffset = nil
                end)
            end,
        },

        --fired by the sub-tab bar when this sub-tab is entered or left.
        summonsTabSelected = function(element, val)
            m_tabSelected = val
            element:SetClass("collapsed", not val)
            if val then
                CreatePreview()
                element:FireEventTree("refreshSummonLook")
            else
                DestroyPreview()
            end
        end,

        --fired when the Appearance tab as a whole is shown or hidden.
        charsheetActivate = function(element, val)
            if not val then
                DestroyPreview()
            elseif m_tabSelected then
                CreatePreview()
                element:FireEventTree("refreshSummonLook")
            end
        end,

        refreshSummonLook = function(element)
            PopulatePreview()
        end,

        destroy = function(element)
            DestroyPreview()
        end,
    }

    return resultPanel
end

function CharSheet.AppearancePanel()
    local divider = gui.Panel {
        classes = {"appearanceDivider"},
        height = "100%-64",
        valign = "center",
        halign = "center",
        width = 1,
        bgimage = true,
        hmargin = 0,
    }

    local m_tokenPanels = {}


    local addVariationButton = gui.Button {
        classes = {"addButton"},
        halign = "center",
        width = 64,
        height = 64,
        vmargin = 6,
        hmargin = 6,
        linger = function(element)
            gui.Tooltip("Add a variation to this creature's appearance")(element)
        end,
        refreshAppearance = function(element, info)
            element:SetClass("hidden", info.token.numAppearanceVariations > 7)
        end,
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

            --panel allowing variation selection.
            gui.Panel {
                height = "auto",
                width = "auto",
                flow = "vertical",
                valign = "top",
                halign = "left",
                minWidth = 200,


                gui.Panel {
                    width = "auto",
                    height = 480,
                    flow = "vertical",
                    halign = "center",
                    wrap = true,

                    styles = ThemeEngine.MergeTokens{
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
                            borderColor = "@border",
                            border = 3,

                            bgimage = true,
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
                            borderColor = "@accent",
                            border = 4,
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
                                        if nvariations <= 1 then
                                            return
                                        end

                                        element.popup = gui.ContextMenu {
                                            entries = {
                                                {
                                                    text = "Delete",
                                                    click = function()

                                                        if element:HasClass("selected") then
                                                            local targetIndex = 1
                                                            if index == 1 then
                                                                targetIndex = 2
                                                            end

                                                            local info = CharacterSheet.instance.data.info
                                                            info.token:SwitchAppearanceVariation(targetIndex-1)
                                                        end

                                                        CharacterSheet.instance.data.info.token :DeleteAppearanceVariation(index - 1)
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

                        --If an alternate appearance is currently selected but the modifier that
                        --granted it is no longer active, revert to the variation we were on. This
                        --replaces a per-panel 'disable' handler that fired whenever the panel was
                        --collapsed/hidden/scrolled out of view (Unity OnDisable), silently reverting
                        --the user's selection on tab-switch or sheet close.
                        local alternateOverride = info.token.alternateAppearanceOverride
                        if alternateOverride ~= nil and (alternateAppearances == nil or alternateAppearances[alternateOverride] == nil) then
                            info.token:SwitchAppearanceVariation(info.token.appearanceVariationIndex)
                        end

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
                                        classes = {"sizeS"},
                                        textAlignment = "center",
                                        halign = "center",
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

            CharSheet.AvatarSelectionPanel(),

            --only valid if we are using a popout avatar.
            CharSheet.PortraitSelectionPanel(),
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
                classes = {"sizeM"},
                text = "Light Style:",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            gui.Dropdown {
                width = 180,
                valign = "center",
                halign = "right",
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
        },

        gui.Panel {
            vmargin = 16,
            flow = "horizontal",
            halign = "center",
            valign = "top",
            width = 400,
            height = 24,
            --Gated behind the dev:customizeteleport setting -- on every sheet refresh we
            --re-check the setting so flipping it via /set takes effect on the next sheet open.
            refreshAppearance = function(element, info)
                element:SetClass("collapsed", not g_customizeTeleportSetting:Get())
            end,
            gui.Label {
                classes = {"sizeM"},
                text = "Teleportation:",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
            },
            gui.Dropdown {
                width = 180,
                valign = "center",
                halign = "right",
                options = {},
                change = function(element)
                    local info = CharacterSheet.instance.data.info
                    info.token.teleportAnimation = element.idChosen or ""
                    info.token:UploadAppearance()
                    CharacterSheet.instance:FireEvent("refreshAll")
                end,
                refreshAppearance = function(element, info)
                    local options = {}
                    local registry = dmhub.tokenAnimations and dmhub.tokenAnimations.teleportAnimations
                    if registry ~= nil then
                        for id, entry in pairs(registry) do
                            options[#options+1] = { id = id, text = entry.name or id }
                        end
                    end
                    table.sort(options, function(a, b) return a.text < b.text end)
                    element.options = options

                    --Mirror the engine's fallback: a token with no explicit teleportAnimation
                    --plays the "default" entry. Show that as the selected option so the dropdown
                    --doesn't read as "(Invalid)" for never-set tokens.
                    local current = info.token.teleportAnimation or ""
                    if current == "" then current = "default" end
                    element.idChosen = current
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


    local summonsPanel = CharSheet.SummonsAppearancePanel()

    --right column: character preview for Avatar/Effects, summon preview for Summons.
    local framePreviewPanel = CharSheet.FramePreviewPanel()
    local summonPreviewPanel = CharSheet.SummonPreviewPanel()

    local m_tabs = { avatarPanel, effectsPanel, summonsPanel }

    local appearanceTabPanel = gui.Panel {
        classes = {"tabBar"},
        valign = "top",
        vmargin = 6,

        create = function(element)
            CharacterSheet.instance.data.GetPreviewLighting = function()
                return m_previewLighting[m_currentPreviewLighting]
            end
        end,

        selectTab = function(element, tab)
            for i, child in ipairs(element.children) do
                if child == tab and m_previewLighting[i] ~= nil then
                    m_currentPreviewLighting = i
                end
                child:SetClass("selected", child == tab)
                m_tabs[i]:SetClass("collapsed", child ~= tab)
            end

            --the Summons sub-tab swaps the right column to the summon preview.
            local isSummons = (tab == element.children[3])
            framePreviewPanel:SetClass("collapsed", isSummons)
            summonPreviewPanel:FireEvent("summonsTabSelected", isSummons)

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
        gui.Label {
            classes = { "tab" },
            text = "Summons",
            --hidden for characters with no summons to customize.
            refreshAppearance = function(element, info)
                local list = GetCustomizableSummonsCached(info.token)
                local none = (#list == 0)
                element:SetClass("collapsed", none)
                if none and element:HasClass("selected") then
                    element.parent:FireEvent("selectTab", element.parent.children[1])
                end
            end,
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
        summonsPanel,
    }

    local rightPanel = gui.Panel {
        id = "rightPanel",
        height = "100%",
        halign = "center",
        valign = "center",
        width = "48%",
        flow = "vertical",


        framePreviewPanel,
        summonPreviewPanel,
    }


    local function buildAppearanceStyles()
        return ThemeEngine.MergeStyles{
            AppearanceStyles,
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
                bgimage = true,
                bgcolor = "clear",
                border = { y1 = 2, x1 = 0, x2 = 0, y2 = 0 },
                borderColor = "@border",
            },
            {
                selectors = { "sliderNotch" },
                bgimage = true,
                bgcolor = "@fgMuted",
                width = "100%",
                halign = "center",
                borderWidth = 0,
            },
        }
    end

    local appearancePanel
    appearancePanel = gui.Panel {
        id = "appearancePanel",
        classes = { "characterSheetParentPanel", "appearance", "hidden", "surfaceRadial" },
        floating = true,
        flow = "horizontal",

        styles = buildAppearanceStyles(),

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

    ThemeEngine.OnThemeChanged(mod, function()
        if appearancePanel ~= nil and appearancePanel.valid then
            appearancePanel.styles = buildAppearanceStyles()
        end
    end)

    return appearancePanel
end

CharSheet.RegisterTab {
    id = "Appearance",
    text = "Appearance",
    panel = CharSheet.AppearancePanel,
}
