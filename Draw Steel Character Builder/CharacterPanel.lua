--[[
    Character Panel
]]

local mod = dmhub.GetModLoading()

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getState = CharacterBuilder._getState
local _getToken = CharacterBuilder._getToken

local INITIAL_TAB = "builder"

function CharacterBuilder._characterBuilderPanel(tabId)
    return gui.Panel {
        classes = {"builder-base", "panel-base", "panel-charpanel-detail"},
        -- width = "96%",
        -- height = "60%",
        -- halign = "center",
        -- valign = "top",
        data = {
            id = tabId,
        },

        _refreshTabs = function(element, tabId)
            element:SetClass("collapsed", tabId ~= element.data.id)
        end,

        gui.Label{
            classes = {"builder-base", "label-panel-placeholder"},
            text = "Builder content here...",
        }
    }
end

function CharacterBuilder._descriptorsPanel()

    local function makeDescriptionLabel(labelText, eventHandlers)
        local itemConfig = {
            classes = {"label", "label-desc-item"},
            width = "50%",
            halign = "right",
            text = "--",
        }

        if eventHandlers then
            for k, v in pairs(eventHandlers) do
                itemConfig[k] = v
            end
        end

        return gui.Panel{
            height = "auto",
            halign = "left",
            width = "auto",
            flow = "horizontal",
            gui.Label{
                classes = {"label", "label-description"},
                halign = "left",
                width = "50%",
                text = labelText .. ":",
            },
            gui.Label(itemConfig)
        }
    end

    local weight = makeDescriptionLabel("Weight", {
        updateState = function(element, state)
            -- TODO: Update the label's .text property from the state
        end,
    })
    local height = makeDescriptionLabel("Height", {
        updateState = function(element, state)
            -- TODO: Update the label's .text property from the state
        end,
    })
    local hair = makeDescriptionLabel("Hair", {
        updateState = function(element, state)
            -- TODO: Update the label's .text property from the state
        end,
    })
    local eyes = makeDescriptionLabel("Eyes", {
        updateState = function(element, state)
            -- TODO: Update the label's .text property from the state
        end,
    })
    local build = makeDescriptionLabel("Build", {
        updateState = function(element, state)
            -- TODO: Update the label's .text property from the state
        end,
    })
    local skin = makeDescriptionLabel("Skin", {
        updateState = function(element, state)
            -- TODO: Update the label's .text property from the state
        end,
    })
    local gender = makeDescriptionLabel("Gender", {
        updateState = function(element, state)
            -- TODO: Update the label's .text property from the state
        end,
    })
    local pronouns = makeDescriptionLabel("Pronouns", {
        updateState = function(element, state)
            -- TODO: Update the label's .text property from the state
        end,
    })

    return gui.Panel{
        classes = {"panel-base"},
        width = "100%",
        height = "auto",
        valign = "top",
        flow = "horizontal",
        -- vmargin = 14,
        vpad = 14,
        bgimage = true,
        borderColor = Styles.textColor,
        border = {y1 = 1, y2 = 0, x1 = 0, x2 = 0},

        -- Left Side
        gui.Panel{
            classes = {"panel-base"},
            width = "50%-12",
            height = "auto",
            hmargin = 4,
            valign = "top",
            flow = "vertical",
            borderColor = "teal",
            border = 1,
            height,
            weight,
            hair,
            eyes,
        },

        -- Right Side
        gui.Panel{
            classes = {"panel-base"},
            width = "50%-12",
            height = "auto",
            hmargin = 4,
            valign = "top",
            flow = "vertical",
            borderColor = "teal",
            border = 1,
            build,
            skin,
            gender,
            pronouns,
        },
    }
end

function CharacterBuilder._characterDescriptionPanel(tabId)

    local descriptorsPanel = CharacterBuilder._descriptorsPanel()

    local physicalFeaturesPanel = gui.Panel{
        classes = {"panel-base"},
        width = "98%",
        height = "80%",
        valign = "top",
        halign = "center",
        flow = "vertical",
        vscroll = true,

        gui.Label{
            classes = {"label", "label-description"},
            halign = "left",
            valign = "top",
            width = "auto",
            text = "Physical Features:",
        },
        gui.Label{
            classes = {"label", "label-desc-item"},
            hmargin = 4,
            width = "98%",
            halign = "left",
            valign = "top",
            text = "--",
            -- bgimage = true,
            border = 1,
            borderColor = "purple",
            updateState = function(element, state)
                -- TODO: Update the label's .text property from the state
            end,
        }
    }

    return gui.Panel {
        classes = {"builder-base", "panel-base", "panel-charpanel-detail"},
        -- width = "96%",
        -- height = "60%",
        -- halign = "center",
        -- valign = "top",
        -- bgimage = true,
        data = {
            id = tabId,
        },

        _refreshTabs = function(element, tabId)
            element:SetClass("collapsed", tabId ~= element.data.id)
        end,

        descriptorsPanel,
        physicalFeaturesPanel,
    }
end

function CharacterBuilder._characterExplorationPanel(tabId)

    local skillsPane = gui.Panel{
        classes = {"panel-base"},
        width = "98%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        gui.Panel{
            classes = {"panel-base"},
            width = "100%",
            height = "auto",
            valign = "top",
            flow = "horizontal",
            bgimage = true,
            borderColor = Styles.textColor,
            border = {y1 = 1, y2 = 0, x1 = 0, x2 = 0},
            gui.Label{
                classes = {"builder-base", "label", "label-description"},
                text = "Skills",
            }
        },

        gui.Label{
            classes = {"builder-base", "label", "label-desc-item"},
            width = "98%",
            valign = "top",
            text = "calculating...",

            refreshBuilderState = function(element, state)
                local creature = state:Get("token").properties
                if creature then
                    local catSkills = creature:GetCategorizedSkills()
                    if catSkills then
                        local allSkills = ""
                        for _,cat in ipairs(catSkills) do
                            local skillStr = ""
                            for _,skill in ipairs(cat.skills) do
                                if #skillStr > 0 then skillStr = skillStr .. ", " end
                                skillStr = skillStr .. skill.name
                            end

                            if #skillStr == 0 then skillStr = "--" end
                            allSkills = string.format("%s%s<b>%s:</b> %s",
                                allSkills,
                                #allSkills > 0 and "\n" or "",
                                cat.id:sub(1,1):upper() .. cat.id:sub(2),
                                skillStr)
                        end
                        element.text = allSkills
                    end
                end
            end
        }
    }

    local languagesPane = gui.Panel{
        classes = {"panel-base"},
        width = "98%",
        height = "auto",
        halign = "center",
        tmargin = 14,
        flow = "vertical",

        gui.Panel{
            classes = {"panel-base"},
            width = "100%",
            height = "auto",
            valign = "top",
            flow = "horizontal",
            bgimage = true,
            borderColor = Styles.textColor,
            border = {y1 = 1, y2 = 0, x1 = 0, x2 = 0},
            gui.Label{
                classes = {"builder-base", "label", "label-description"},
                text = "Languages",
            }
        },

        gui.Label{
            classes = {"builder-base", "label", "label-desc-item"},
            width = "98%",
            valign = "top",
            text = "calculating...",

            refreshBuilderState = function(element, state)
                local creature = state:Get("token").properties
                if creature then
                    local knownLangs = {}
                    local langs = creature:LanguagesKnown()
                    local langTable = dmhub.GetTableVisible(Language.tableName)
                    for k,_ in pairs(langs) do
                        local lang = langTable[k]
                        if lang then
                            local speakers = (lang.speakers and #lang.speakers > 0) and string.format(" (%s)", lang.speakers) or ""
                            knownLangs[#knownLangs+1] = lang.name .. speakers
                        end
                    end
                    local langString = "--"
                    if #knownLangs > 0 then
                        table.sort(knownLangs)
                        langString = table.concat(knownLangs, ", ")
                    end
                    element.text = langString
                end
            end
        }
    }

    return gui.Panel {
        classes = {"builder-base", "panel-base", "panel-charpanel-detail"},
        data = {
            id = tabId,
        },

        create = function(element)
            element:FireEventTree("refreshBuilderState", _getState(element))
        end,

        _refreshTabs = function(element, tabId)
            element:SetClass("collapsed", tabId ~= element.data.id)
        end,

        skillsPane,
        languagesPane,
    }
end

function CharacterBuilder._characterTacticalPanel(tabId)
    return gui.Panel {
        classes = {"builder-base", "panel-base", "panel-charpanel-detail"},
        -- width = "96%",
        -- height = "60%",
        -- halign = "center",
        -- valign = "top",
        vscroll = true,
        data = {
            id = tabId,
        },

        create = function(element)
            element:FireEventTree("refreshBuilderState", _getState(element))
        end,

        _refreshTabs = function(element, tabId)
            element:SetClass("collapsed", tabId ~= element.data.id)
        end,

        refreshBuilderState = function(element, state)
            local t = state:Get("token")
            if #element.children == 0 then
                print("THC:: CREATEPANEL::")
                element:AddChild(CharacterPanel.CreateCharacterDetailsPanel(t))
                element:AddChild(gui.Label{
                    width = "auto",
                    height= "auto",
                    fontSize = 60,
                    floating = true,
                    valign = "center",
                    halign = "center",
                    rotate = 35,
                    color = "red",
                    textAlignment = "center",
                    text = "PLACEHOLDER",
                })
            else
                print("THC:: REFRESHTOKEN::")
                element:FireEventTree("refreshToken", t)
            end
        end
    }
end

--- Create the tabbed detail panel for the character pane
--- @return Panel
function CharacterBuilder._characterDetailPanel()

    local detailPanel

    local tabs = {
        builder = {
            icon = "panels/gamescreen/settings.png",
            content = CharacterBuilder._characterBuilderPanel,
        },
        description = {
            icon = "icons/icon_app/icon_app_31.png",
            content = CharacterBuilder._characterDescriptionPanel,
        },
        exploration = {
            icon = "game-icons/treasure-map.png",
            content = CharacterBuilder._characterExplorationPanel,
        },
        tactical = {
            icon = "panels/initiative/initiative-icon.png",
            content = CharacterBuilder._characterTacticalPanel,
        }
    }
    local tabOrder = {"builder", "description", "exploration", "tactical"}

    local tabButtons = {}
    for _,tabId in ipairs(tabOrder) do
        local tabInfo = tabs[tabId]
        local btn = gui.Panel{
            classes = {"char-tab-btn"},
            halign = "right",
            hmargin = 8,
            bgimage = tabInfo.icon,

            data = {
                id = tabId,
            },

            linger = function(element)
                gui.Tooltip(element.data.id:sub(1,1):upper() .. element.data.id:sub(2))(element)
            end,

            _refreshTabs = function(element, activeTabId)
                element:SetClass("selected", activeTabId == element.data.id)
            end,

            press = function(element)
                detailPanel:FireEvent("tabClick", tabId)
            end,
        }
        tabButtons[#tabButtons+1] = btn
    end

    local tabPanel = gui.Panel{
        width = "100%",
        height = 24,
        tmargin = 8,
        vpad = 4,
        flow = "horizontal",
        bgimage = true,
        borderColor = CharacterBuilder.COLORS.GOLD03,
        border = { y2 = 0, y1 = 1, x2 = 0, x1 = 0 },

        children = tabButtons,
    }

    local contentPanel = gui.Panel{
        width = "100%",
        height = "auto",
        halign = "center",
        valign = "top",
        vscroll = true,

        data = {
            madeContent = {},
        },

        _refreshTabs = function(element, tabId)
            if element.data.madeContent[tabId] == nil then
                element:AddChild(tabs[tabId].content(tabId))
                element.data.madeContent[tabId] = true
            end
        end
    }

    detailPanel = gui.Panel{
        width = "100%",
        height = "100%-" .. CharacterBuilder.SIZES.CHARACTER_PANEL_HEADER_HEIGHT,
        flow = "vertical",

        create = function(element)
            element:FireEvent("tabClick", INITIAL_TAB)
        end,

        tabClick = function(element, tabId)
            element:FireEventTree("_refreshTabs", tabId)
        end,

        tabPanel,
        contentPanel,
    }

    return detailPanel
end

--- Create the header panel for the character pane
--- @return Panel
function CharacterBuilder._characterHeaderPanel()

    local popoutAvatar = gui.Panel {
        classes = { "hidden" },
        interactable = false,
        width = 800,
        height = 800,
        halign = "center",
        valign = "center",
        bgcolor = "white",
    }

    local avatar = gui.IconEditor {
        library = cond(dmhub.GetSettingValue("popoutavatars"), "popoutavatars", "Avatar"),
        restrictImageType = "Avatar",
        allowPaste = true,
        borderColor = Styles.textColor,
        borderWidth = 2,
        cornerRadius = math.floor(0.5 * CharacterBuilder.SIZES.AVATAR_DIAMETER),
        width = CharacterBuilder.SIZES.AVATAR_DIAMETER,
        height = CharacterBuilder.SIZES.AVATAR_DIAMETER,
        autosizeimage = true,
        halign = "center",
        valign = "top",
        tmargin = 20,
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
                popoutAvatar.selfStyle.scale = .25
                element.bgimage = false --"panels/square.png"
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
            -- local info = CharacterSheet.instance.data.info
            -- info.token.portrait = element.value
            -- info.token:UploadAppearance()
            -- CharacterSheet.instance:FireEvent("refreshAll")
            -- element:FireEvent("imageLoaded")
        end,
    }

    local characterName = gui.Label {
        classes = {"builder-base", "label", "label-charname"},
        text = "calculating...",
        editable = true,
        data = {
            text = "",
        },
        refreshBuilderState = function(element, state)
            local t = state:Get("token")
            element.data.text = (t and t.name and #t.name > 0) and t.name or "Unnamed Character"
            element.text = string.upper(element.data.text)
        end,
        change = function(element)
            if element.data.text ~= element.text then
                element.data.text = element.text
                local t = _getToken(element)
                if t then
                    t.name = element.data.text
                    _fireControllerEvent(element, "tokenDataChanged")
                end
            end
        end,
    }

    local levelClass = gui.Label {
        classes = {"builder-base", "label", "label-charname"},
        text = "(class & level)",
        tmargin = 4,
        refreshBuilderState = function(element, state)
            local c = state:Get("token").properties
            if c then
                local class = c:GetClass()
                if class then
                    local level = c:GetLevelInClass(class.id)
                    element.text = string.format("Level %d %s", level, class.name):upper()
                end
            end
        end,
    }

    return gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "99%",
        height = CharacterBuilder.SIZES.CHARACTER_PANEL_HEADER_HEIGHT,
        flow = "vertical",
        halign = "center",
        valign = "top",
        avatar,
        characterName,
        levelClass,
    }
end

--- Generate the character panel
--- @return Panel
function CharacterBuilder._characterPanel()

    local headerPanel = CharacterBuilder._characterHeaderPanel()
    local detailPanel = CharacterBuilder._characterDetailPanel()

    return gui.Panel{
        id = "characterPanel",
        classes = {"builder-base", "panel-base", "panel-border", "characterPanel"},
        width = CharacterBuilder.SIZES.CHARACTER_PANEL_WIDTH,
        height = "99%",
        valign = "center",
        bgimage = true,
        -- halign = "right",
        flow = "vertical",

        headerPanel,
        detailPanel,
    }
end
