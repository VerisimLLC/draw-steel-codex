--[[
    Character Panel
]]

local mod = dmhub.GetModLoading()

local _blankToDashes = CharacterBuilder._blankToDashes
local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getState = CharacterBuilder._getState
local _getToken = CharacterBuilder._getToken
local _ucFirst = CharacterBuilder._ucFirst

local INITIAL_TAB = "description"

local function processFeature(feature)

    local modifiers = feature:try_get("modifiers")
    if modifiers then
        local choiceInfo = {}
        for _,item in ipairs(modifiers) do
            if item.typeName and item.typeName == "CharacterModifier" then
                
            end
        end
    end

    return nil
end

local function processChoice(feature, levelChoices)

    local function translateTypeName(typeName)
        local s = typeName:match("Character(.+)Choice")
    end

    local guid = feature:try_get("guid")
    if guid then
        local selected = levelChoices[guid]
        return {{
            guid = guid,
            type = translateTypeName(feature.typeName),
            numChoices = feature:try_get("numChoices", 1),
            numSelected = selected and #selected or 0
        }}
    end

    return nil
end

local function aggregateBuilderChoices(creature)
    local choices = {}

    local function typeNameIsChoice(typeName)
        return typeName == "CharacterDeityChoice"
            or typeName == "CharacterFeatChoice"
            or typeName == "CharacterFeatureChoice"
            or typeName == "CharacterLanguageChoice"
            or typeName == "CharacterSkillChoice"
            or typeName == "CharacterSubclassChoice"
    end

    if creature then
        local levelChoices = creature:GetLevelChoices()
        local selectedFeatures = creature:GetClassFeaturesAndChoicesWithDetails()

        for _,item in ipairs(selectedFeatures) do
            local typeName = item.feature and item.feature.typeName
            if typeName then
                local choiceInfo
                if typeNameIsChoice(typeName) then
                    choiceInfo = processChoice(item.feature, levelChoices)
                elseif typeName == "CharacterFeatureList" then
                    -- iterate over feature.features #39
                elseif typeName == "CharacterFeature" then
                end
            end
        end
    end

    return choices
end

--- Create a panel displaying feature information for a single feature type
--- @param featureTypeInfo table
--- @return Panel
function CharacterBuilder._characterBuilderPanelStatusFeature(featureTypeInfo)
    local idLabel = gui.Label{
        classes = {"builder-base", "label", "feature-detail-id-label"},
        refreshDetail = function(element, info)
            element.text = info.id
        end,
    }
    local statusLabel = gui.Label{
        classes = {"builder-base", "label", "feature-detail-status-label"},
        refreshDetail = function(element, info)
            element.text = string.format("%d/%d", info.selected, info.available)
        end,
    }
    local detailLabel = gui.Label{
        classes = {"builder-base", "label", "feature-detail-detail-label"},
        refreshDetail = function(element, info)
            element.text = table.concat(info.selectedDetail, "\n\n")
        end
    }
    return gui.Panel{
        classes = {"builder-base", "panel-base", "feature-detail-panel"},
        data = featureTypeInfo,
        refreshBuilderState = function(element, state)
            local visible = element.data and element.data.available > 0
            element:SetClass("collapsed", not visible)
            if visible then
                element:FireEventTree("refreshDetail", element.data)
            end
        end,
        idLabel,
        statusLabel,
        detailLabel,
    }
end

--- Create a panel to display an element of builder status
--- @param selector string The primary selector for querying state
--- @param getSelected function(character) Return the selected item on the character
--- @return Panel
function CharacterBuilder._characterBuilderPanelStatusItem(selector, getSelected)

    local function translateTypeName(typeName)
        local s = typeName:match("Character(.+)Choice")
        return s
    end

    local function typeNameIsChoice(typeName)
        return typeName == "CharacterDeityChoice"
            or typeName == "CharacterFeatChoice"
            or typeName == "CharacterFeatureChoice"
            or typeName == "CharacterLanguageChoice"
            or typeName == "CharacterSkillChoice"
            or typeName == "CharacterSubclassChoice"
    end

    local function typeNameOrder(typeName)
        -- The input is translated
        local typeOrders = { Subclass = 1, Feature = 2, Skill = 3, Language = 4, Feat = 5, Deity = 6, }
        return string.format("%d-%s", typeOrders[typeName] or 9, typeName)
    end

    local function typeNameToTableName(typeName)
        if typeName == "CharacterDeityChoice" then return Deity.tableName end
        if typeName == "CharacterFeatChoice" then return CharacterFeat.tableName end
        if typeName == "CharacterFeatureChoice" then return nil end
        if typeName == "CharacterLanguageChoice" then return Language.tableName end
        if typeName == "CharacterSkillChoice" then return Skill.tableName end
        if typeName == "CharacterSubclassChoice" then return Class.tableName end
    end

    local headingText = _ucFirst(selector)

    local headerPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "charpanel-detail-header"},
        click = function(element)
            local controller = element:FindParentWithClass("panelStatusController")
            if controller then controller:FireEvent("toggleExpanded") end
        end,
        gui.Label{
            classes = {"builder-base", "label", "charpanel-detail-header-label"},
            text = headingText,
        },
        gui.Panel{
            classes = {"builder-base", "panel-base", "charpanel-check"},
            setStatus = function(element, info)
                element:SetClass("complete", info.complete)
            end,
        },
        gui.Label{
            classes = {"builder-base", "label", "charpanel-detail-header-label"},
            width = "auto",
            halign = "right",
            hmargin = 40,
            setStatus = function(element, info)
                element.text = string.format("%d/%d", info.selected, info.available)
                element:SetClass("collapsed", info.complete)
            end,
        },
        gui.CollapseArrow{
            halign = "right",
            valign = "center",
            setExpanded = function(element, expanded)
                element:SetClass("collapseSet", not expanded)
            end
        }
    }

    local detailPanel = gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "100%",
        height = "auto",
        valign = "top",
        flow = "vertical",
        data = {
            heading = headingText,
            featureTypes = {},
        },
        create = function(element)
            element:FireEvent("refreshBuilderState", _getState(element))
        end,
        calculateComplete = function(element)
            local available = 0
            local selected = 0
            for _,ft in pairs(element.data.featureTypes) do
                available = available + ft.available
                selected = selected + ft.selected
            end
            local parent = element:FindParentWithClass("panelStatusController")
            if parent then
                parent:FireEventTree("setStatus", {
                    available = available,
                    selected = selected,
                    complete = selected == available,
                })
            end
        end,
        calculateStatus = function(element, state)
            local featureTypes = element.data.featureTypes
            featureTypes = {
                [headingText] = {
                    id = headingText,
                    order = "0-".. headingText,
                    available = 1,
                    selected = 0,
                    selectedDetail = {},
                },
            }
            local character = state:Get("token").properties
            local featureDetails = state:Get(selector .. ".featureDetails")
            if character and featureDetails then
                local selectedItem = getSelected(character)
                if selectedItem then
                    featureTypes[element.data.heading].selected = 1
                    featureTypes[element.data.heading].selectedDetail = { selectedItem.name }

                    local levelChoices = character:GetLevelChoices()
                    if levelChoices then
                        for _,f in ipairs(featureDetails) do
                            local guid = f.feature:try_get("guid")
                            if guid and typeNameIsChoice(f.feature.typeName) then
                                local typeName = translateTypeName(f.feature.typeName)                                
                                if featureTypes[typeName] == nil then
                                    featureTypes[typeName] = {
                                        id = typeName,
                                        order = typeNameOrder(typeName),
                                        available = 0,
                                        selected = 0,
                                        selectedDetail = {},
                                    }
                                end

                                local numChoices = f.feature:NumChoices() or 1
                                if numChoices < 1 then numChoices = 1 end
                                featureTypes[typeName].available = featureTypes[typeName].available + numChoices

                                if levelChoices[guid] then
                                    featureTypes[typeName].selected = featureTypes[typeName].selected + #levelChoices[guid]

                                    local detail = {}
                                    local itemTable = dmhub.GetTableVisible(typeNameToTableName(f.feature.typeName))
                                    if itemTable then
                                        for _,id in ipairs(levelChoices[guid]) do
                                            local item = itemTable[id]
                                            if item then detail[#detail+1] = item.name end
                                        end
                                    end
                                    if #detail then
                                        table.move(detail, 1, #detail, #featureTypes[typeName].selectedDetail + 1, featureTypes[typeName].selectedDetail)
                                    end
                                end

                            end
                        end
                    end
                end
            end
            element.data.featureTypes = featureTypes
        end,
        reconcileChildren = function(element)
            if element.data.featureTypes then
                local children = element.children
                local featureTypes = element.data.featureTypes
                local numChildren = #children
                local index = 0

                for _,featureType in pairs(featureTypes) do
                    index = index + 1
                    if children[index] then
                        children[index].data = featureType
                    else
                        children[index] = CharacterBuilder._characterBuilderPanelStatusFeature(featureType)
                    end
                end

                for i = index + 1, numChildren do
                    children[i].data = nil
                end

                table.sort(children, function(a,b)
                    local aOrd = a.data and a.data.order or "999"
                    local bOrd = b.data and b.data.order or "999"
                    return aOrd < bOrd
                end)

                element.children = children
            end
        end,
        refreshBuilderState = function(element, state)
            element:FireEvent("calculateStatus", state)
            element:FireEvent("reconcileChildren")
            element:FireEvent("calculateComplete")
        end,
        setExpanded = function(element, expanded)
            element:SetClass("collapsed-anim", not expanded)
        end,
    }

    return gui.Panel{
        classes = {"builder-base", "panel-base", "panelStatusController"},
        width = "100%",
        height = "auto",
        valign = "top",
        flow = "vertical",
        data = {
            expanded = nil,
        },
        setStatus = function(element, info)
            element.data.expanded = not info.complete
            element:FireEventTree("setExpanded", element.data.expanded)
        end,
        toggleExpanded = function(element)
            element.data.expanded = not element.data.expanded
            element:FireEventTree("setExpanded", element.data.expanded)
        end,
        headerPanel,
        detailPanel,
    }
end

function CharacterBuilder._characterBuilderPanel(tabId)

    local ancestryStatusItem = CharacterBuilder._characterBuilderPanelStatusItem("ancestry", function(character)
        return character:Race()
    end)
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

        ancestryStatusItem,
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
        refreshBuilderState = function(element, state)
            local character = state:Get("token").properties
            if character and character:IsHero() then
                local desc = character:Description()
                if desc then element.text = _blankToDashes(desc:GetWeight()) end
            end
        end,
    })
    local height = makeDescriptionLabel("Height", {
        refreshBuilderState = function(element, state)
            local character = state:Get("token").properties
            if character and character:IsHero() then
                local desc = character:Description()
                if desc then element.text = _blankToDashes(desc:GetHeight()) end
            end
        end,
    })
    local hair = makeDescriptionLabel("Hair", {
        refreshBuilderState = function(element, state)
            local character = state:Get("token").properties
            if character and character:IsHero() then
                local desc = character:Description()
                if desc then element.text = _blankToDashes(desc:GetHair()) end
            end
        end,
    })
    local eyes = makeDescriptionLabel("Eyes", {
        refreshBuilderState = function(element, state)
            local character = state:Get("token").properties
            if character and character:IsHero() then
                local desc = character:Description()
                if desc then element.text = _blankToDashes(desc:GetEyes()) end
            end
        end,
    })
    local build = makeDescriptionLabel("Build", {
        refreshBuilderState = function(element, state)
            local character = state:Get("token").properties
            if character and character:IsHero() then
                local desc = character:Description()
                if desc then element.text = _blankToDashes(desc:GetBuild()) end
            end
        end,
    })
    local skin = makeDescriptionLabel("Skin", {
        refreshBuilderState = function(element, state)
            local character = state:Get("token").properties
            if character and character:IsHero() then
                local desc = character:Description()
                if desc then element.text = _blankToDashes(desc:GetSkinTone()) end
            end
        end,
    })
    local gender = makeDescriptionLabel("Gender", {
        refreshBuilderState = function(element, state)
            local character = state:Get("token").properties
            if character and character:IsHero() then
                local desc = character:Description()
                if desc then element.text = _blankToDashes(desc:GetGenderPresentation()) end
            end
        end,
    })
    local pronouns = makeDescriptionLabel("Pronouns", {
        refreshBuilderState = function(element, state)
            local character = state:Get("token").properties
            if character and character:IsHero() then
                local desc = character:Description()
                if desc then element.text = _blankToDashes(desc:GetPronouns()) end
            end
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
            refreshBuilderState = function(element, state)
                local character = state:Get("token").properties
                if character and character:IsHero() then
                    local desc = character:Description()
                    if desc then element.text = _blankToDashes(desc:GetPhysicalFeatures()) end
                end
            end,
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
            text = "Builder",
            content = CharacterBuilder._characterBuilderPanel,
        },
        description = {
            icon = "icons/icon_app/icon_app_31.png",
            text = "Description",
            content = CharacterBuilder._characterDescriptionPanel,
        },
        exploration = {
            icon = "game-icons/treasure-map.png",
            text = "Exploration",
            content = CharacterBuilder._characterExplorationPanel,
        },
        tactical = {
            icon = "panels/initiative/initiative-icon.png",
            text = "Tactical",
            content = CharacterBuilder._characterTacticalPanel,
        }
    }
    local tabOrder = {"description", "builder", "exploration", "tactical"}

    local tabButtons = {}
    for _,tabId in ipairs(tabOrder) do
        local tabInfo = tabs[tabId]
        local btn = gui.Panel{
            classes = {"char-tab-icon"},
            halign = "right",
            hmargin = 8,
            bgimage = tabInfo.icon,
            -- interactable = false,
            data = { id = tabId, },
            _refreshTabs = function(element, activeTabId)
                element:SetClass("selected", activeTabId == element.data.id)
            end,
        }
        local label = gui.Label{
            classes = {"builder-base", "label", "char-tab-label"},
            height = "auto",
            width = "auto",
            hpad = 8,
            color = CharacterBuilder.COLORS.CREAM03,
            -- fontSize = 18,
            text = tabInfo.text,
            data = { id = tabId, },
            _refreshTabs = function(element, activeTabId)
                element:SetClass("collapsed", activeTabId ~= element.data.id)
            end,
        }
        local tab = gui.Panel{
            classes = {"builder-base", "panel", "char-tab-btn"},
            width = "auto",
            height = "100%",
            halign = "right",
            hmargin = 8,
            flow = "horizontal",
            data = {
                id = tabId,
            },
            _refreshTabs = function(element, activeTabId)
                element:SetClass("selected", activeTabId == element.data.id)
            end,
            linger = function(element)
                gui.Tooltip(tabInfo.text)(element)
            end,
            press = function(element)
                detailPanel:FireEvent("tabClick", tabId)
            end,

            btn,
            label,
        }
        tabButtons[#tabButtons+1] = tab
    end

    local tabPanel = gui.Panel{
        width = "100%",
        height = 26,
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
            if c and c:IsHero() then
                local class = c:GetClass()
                local level = c:CharacterLevel()
                if class or level then
                    element.text = string.format("Level %d %s", level, class and class.name or ""):upper()
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
        flow = "vertical",

        headerPanel,
        detailPanel,
    }
end
