--[[
    Character Panel
]]
CBCharPanel = RegisterGameType("CBCharPanel")

local _blankToDashes = CharacterBuilder._blankToDashes
local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _formatOrder = CharacterBuilder._formatOrder
local _getHero = CharacterBuilder._getHero
local _getState = CharacterBuilder._getState
local _getToken = CharacterBuilder._getToken
local _ucFirst = CharacterBuilder._ucFirst

local INITIAL_TAB = "description"
local SEL = CharacterBuilder.SELECTOR

--- Create a panel displaying feature information for a single feature type
--- @return Panel
function CBCharPanel._statusEntryRow()
    local idLabel = gui.Label{
        classes = {"builder-base", "label", "charpanel", "builder-category"},
        assignItem = function(element, entry)
            element.text = entry.id
        end,
    }
    local statusLabel = gui.Label{
        classes = {"builder-base", "label", "charpanel", "builder-status"},
        assignItem = function(element, entry)
            element.text = string.format("%d/%d", entry.selected, entry.available)
        end,
    }
    local detailLabel = gui.Label{
        classes = {"builder-base", "label", "charpanel", "builder-detail"},
        assignItem = function(element, entry)
            element.text = table.concat(entry.selectedDetail, "\n")
        end
    }
    return gui.Panel{
        classes = {"builder-base", "panel-base", "charpanel", "builder-feature-content"},

        assignItem = function(element, entry)
            local visible = entry ~= nil
            element:SetClass("collapsed", not visible)
            if not visible then element:HaltEventPropagation() end
        end,

        idLabel,
        statusLabel,
        detailLabel,
    }
end

--- Create a panel to display an element of builder status
--- @param selector string The primary selector for querying state
--- @param visible? boolean|function(hero) Whether the panel should be visible
--- @param suppressRow1? boolean Whether to suppress the first row of detail
--- @return Panel
function CBCharPanel._statusItem(selector, visible, suppressRow1)
    if visible == nil then visible = true end
    if suppressRow1 == nil then suppressRow1 = false end

    local headingText = _ucFirst(selector)

    local headerPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "charpanel", "builder-header"},
        press = function(element)
            local controller = element:FindParentWithClass("panelStatusController")
            if controller then controller:FireEvent("toggleExpanded") end
        end,
        gui.Label{
            classes = {"builder-base", "label", "charpanel", "builder-header"},
            text = headingText,
        },
        gui.Panel{
            classes = {"builder-base", "panel-base", "charpanel", "builder-check"},
            setStatus = function(element, info)
                element:SetClass("complete", info.complete)
            end,
        },
        gui.Label{
            classes = {"builder-base", "label", "charpanel", "builder-header"},
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
        flow = "vertical",
        data = {
            heading = headingText,
            statusEntries = {},
        },

        create = function(element)
            element:FireEvent("refreshBuilderState", _getState())
        end,

        calculateComplete = function(element)
            local available = 0
            local selected = 0
            for _,entry in pairs(element.data.statusEntries) do
                available = available + entry.available
                selected = selected + entry.selected
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
            local hero = _getHero()
            local featureCache = state:Get(selector .. ".featureCache")
            local statusEntries = {}
            if not suppressRow1 then
                statusEntries[headingText] = {
                    id = headingText,
                    order = _formatOrder(0, headingText),
                    available = 1,
                    selected = 0,
                    selectedDetail = {},
                }
            end

            if hero and featureCache then
                if not suppressRow1 then
                    statusEntries[headingText].selected = 1
                    statusEntries[headingText].selectedDetail = { featureCache:GetSelectedName() }
                end

                for _,item in ipairs(featureCache:GetSortedFeatures()) do
                    local feature = featureCache:GetFeature(item.guid)
                    local key = feature:GetCategoryOrder()
                    if statusEntries[key] == nil then
                        statusEntries[key] = {
                            id = feature:GetCategory(),
                            order = key,
                            available = 0,
                            selected = 0,
                            selectedDetail = {},
                        }
                    end
                    local statusEntry = statusEntries[key]
                    local featureStatus = feature:GetStatus()
                    statusEntry.available = statusEntry.available + featureStatus.numChoices --feature:GetNumChoices()
                    statusEntry.selected = statusEntry.selected + featureStatus.selected --feature:GetSelectedValue()
                    local selectedNames = featureStatus.selectedNames --feature:GetSelectedNames()
                    table.move(selectedNames, 1, #selectedNames, #statusEntry.selectedDetail + 1, statusEntry.selectedDetail)
                    table.sort(statusEntry.selectedDetail)
                end
            end

            statusEntries = CharacterBuilder._toArray(statusEntries)
            table.sort(statusEntries, function(a,b) return a.order < b.order end)

            element.data.statusEntries = statusEntries
        end,

        reconcileChildren = function(element)
            local statusEntries = element.data.statusEntries
            if not statusEntries then return end

            local children = element.children
            local numEntries = #statusEntries
            local numChildren = #children

            -- Ensure we have enough children
            for _ = numChildren + 1, numEntries do
                element:AddChild(CBCharPanel._statusEntryRow())
            end

            -- Refresh children reference after adding
            children = element.children

            -- Update children with corresponding status entries
            for i, entry in ipairs(statusEntries) do
                children[i]:FireEventTree("assignItem", entry)
            end

            -- Clear excess children
            for i = numEntries + 1, #children do
                children[i]:FireEventTree("assignItem", nil)
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
        classes = {"builder-base", "panel-base", "builder-content-entry", "panelStatusController"},
        flow = "vertical",
        data = {
            expanded = nil,
            visible = visible,
        },
        refreshBuilderState = function(element, state)
            local visible = element.data.visible
            if type(visible) == "function" then
                local hero = _getHero()
                visible = visible(hero)
            else
                visible = element.data.visible == true
            end
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
            end
        end,
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

function CBCharPanel._builderPanel(tabId)

    local ancestryStatusItem = CBCharPanel._statusItem(SEL.ANCESTRY, true)
    local cultureStatusItem = CBCharPanel._statusItem(SEL.CULTURE, true, true)
    local careerStatusItem = CBCharPanel._statusItem(SEL.CAREER, true)
    local classStatusItem = CBCharPanel._statusItem(SEL.CLASS, true)
    local kitStatusItem = CBCharPanel._statusItem(SEL.KIT, function(hero)
        return hero:CanHaveKits()
    end, true)
    local complicationStatusItem = CBCharPanel._statusItem(SEL.COMPLICATION, true, true)

    return gui.Panel {
        classes = {"builder-base", "panel-base", "charpanel", "tab-content"},
        height = "100% available",
        vscroll = true,
        data = {
            id = tabId,
        },

        create = function(element)
            element:FireEventTree("refreshBuilderState", _getState())
        end,

        _refreshTabs = function(element, tabId)
            element:SetClass("collapsed", tabId ~= element.data.id)
        end,

        ancestryStatusItem,
        cultureStatusItem,
        careerStatusItem,
        classStatusItem,
        kitStatusItem,
        complicationStatusItem,
    }
end

function CBCharPanel._descriptorsPanel()

    local function makeDescriptionLabel(labelText, eventHandlers)
        local itemConfig = {
            classes = {"label", "charpanel", "desc-item-detail"},
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
                classes = {"label", "charpanel", "desc-item-label"},
                halign = "left",
                width = "50%",
                text = labelText .. ":",
            },
            gui.Label(itemConfig)
        }
    end

    local weight = makeDescriptionLabel("Weight", {
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local desc = hero:Description()
                if desc then element.text = _blankToDashes(desc:GetWeight()) end
            end
        end,
    })
    local height = makeDescriptionLabel("Height", {
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local desc = hero:Description()
                if desc then element.text = _blankToDashes(desc:GetHeight()) end
            end
        end,
    })
    local hair = makeDescriptionLabel("Hair", {
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local desc = hero:Description()
                if desc then element.text = _blankToDashes(desc:GetHair()) end
            end
        end,
    })
    local eyes = makeDescriptionLabel("Eyes", {
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local desc = hero:Description()
                if desc then element.text = _blankToDashes(desc:GetEyes()) end
            end
        end,
    })
    local build = makeDescriptionLabel("Build", {
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local desc = hero:Description()
                if desc then element.text = _blankToDashes(desc:GetBuild()) end
            end
        end,
    })
    local skin = makeDescriptionLabel("Skin", {
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local desc = hero:Description()
                if desc then element.text = _blankToDashes(desc:GetSkinTone()) end
            end
        end,
    })
    local gender = makeDescriptionLabel("Gender", {
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local desc = hero:Description()
                if desc then element.text = _blankToDashes(desc:GetGenderPresentation()) end
            end
        end,
    })
    local pronouns = makeDescriptionLabel("Pronouns", {
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local desc = hero:Description()
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

function CBCharPanel._descriptionPanel(tabId)

    local descriptorsPanel = CBCharPanel._descriptorsPanel()

    local physicalFeaturesPanel = gui.Panel{
        classes = {"panel-base"},
        width = "98%",
        height = "80%",
        valign = "top",
        halign = "center",
        flow = "vertical",
        vscroll = true,

        gui.Label{
            classes = {"label", "charpanel", "desc-item-label"},
            halign = "left",
            valign = "top",
            width = "auto",
            text = "Physical Features:",
        },
        gui.Label{
            classes = {"label", "charpanel", "desc-item-detail"},
            hmargin = 4,
            width = "98%",
            halign = "left",
            valign = "top",
            text = "--",
            -- bgimage = true,
            border = 1,
            borderColor = "purple",
            refreshBuilderState = function(element, state)
                local hero = _getHero()
                if hero then
                    local desc = hero:Description()
                    if desc then element.text = _blankToDashes(desc:GetPhysicalFeatures()) end
                end
            end,
        }
    }

    return gui.Panel {
        classes = {"builder-base", "panel-base", "charpanel", "tab-content"},
        data = {
            id = tabId,
        },

        create = function(element)
            element:FireEventTree("refreshBuilderState", _getState())
        end,

        _refreshTabs = function(element, tabId)
            element:SetClass("collapsed", tabId ~= element.data.id)
        end,

        descriptorsPanel,
        physicalFeaturesPanel,
    }
end

function CBCharPanel._explorationPanel(tabId)

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
                classes = {"builder-base", "label", "charpanel", "desc-item-label"},
                text = "Skills",
            }
        },

        gui.Label{
            classes = {"builder-base", "label", "charpanel", "desc-item-detail"},
            width = "98%",
            valign = "top",
            text = "calculating...",

            refreshBuilderState = function(element, state)
                local hero = _getHero()
                if hero then
                    local catSkills = hero:GetCategorizedSkills()
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
                classes = {"builder-base", "label", "charpanel", "desc-item-label"},
                text = "Languages",
            }
        },

        gui.Label{
            classes = {"builder-base", "label", "charpanel", "desc-item-detail"},
            width = "98%",
            valign = "top",
            text = "calculating...",

            refreshBuilderState = function(element, state)
                local hero = _getHero()
                if hero then
                    local knownLangs = {}
                    local langs = hero:LanguagesKnown()
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
        classes = {"builder-base", "panel-base", "charpanel", "tab-content"},
        data = {
            id = tabId,
        },
        create = function(element)
            element:FireEventTree("refreshBuilderState", _getState())
        end,
        _refreshTabs = function(element, tabId)
            element:SetClass("collapsed", tabId ~= element.data.id)
        end,
        skillsPane,
        languagesPane,
    }
end

function CBCharPanel._tacticalPanel(tabId)
    return gui.Panel {
        classes = {"builder-base", "panel-base", "charpanel", "tab-content"},
        vscroll = true,
        data = {
            id = tabId,
        },

        create = function(element)
            element:FireEventTree("refreshBuilderState", _getState())
        end,

        _refreshTabs = function(element, tabId)
            element:SetClass("collapsed", tabId ~= element.data.id)
        end,

        refreshBuilderState = function(element, state)
            local token = state:Get("token")
            if token then
                if #element.children == 0 then
                    -- element:AddChild(CharacterPanel.CreateCharacterDetailsPanel(token))
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
                    element:FireEventTree("refreshToken", token)
                end
            end
        end
    }
end

--- Create the tabbed detail panel for the character pane
--- @return Panel
function CBCharPanel._detailPanel()

    local detailPanel

    local tabs = {
        builder = {
            icon = "panels/gamescreen/settings.png",
            text = "Builder",
            content = CBCharPanel._builderPanel,
        },
        description = {
            icon = "icons/icon_app/icon_app_31.png",
            text = "Description",
            content = CBCharPanel._descriptionPanel,
        },
        exploration = {
            icon = "game-icons/treasure-map.png",
            text = "Exploration",
            content = CBCharPanel._explorationPanel,
        },
        -- tactical = {
        --     icon = "panels/initiative/initiative-icon.png",
        --     text = "Tactical",
        --     content = CBCharPanel._tacticalPanel,
        -- }
    }
    local tabOrder = {"description", "builder", "exploration"} --, "tactical"}

    local tabButtons = {}
    for _,tabId in ipairs(tabOrder) do
        local tabInfo = tabs[tabId]
        local btn = gui.Panel{
            classes = {"charpanel", "tab-icon"},
            halign = "right",
            hmargin = 8,
            bgimage = tabInfo.icon,
            -- interactable = false,
            data = {
                id = tabId,
            },
            _refreshTabs = function(element, activeTabId)
                element:SetClass("selected", activeTabId == element.data.id)
            end,
        }
        local label = gui.Label{
            classes = {"builder-base", "label", "charpanel", "tab-label"},
            height = "auto",
            width = "auto",
            hpad = 8,
            color = CBStyles.COLORS.CREAM03,
            -- fontSize = 18,
            text = tabInfo.text,
            data = {
                id = tabId,
            },
            _refreshTabs = function(element, activeTabId)
                element:SetClass("collapsed", activeTabId ~= element.data.id)
            end,
        }
        local tab = gui.Panel{
            classes = {"builder-base", "panel", "charpanel", "tab-button"},
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
        borderColor = CBStyles.COLORS.GOLD03,
        border = { y2 = 0, y1 = 1, x2 = 0, x1 = 0 },
        children = tabButtons,
    }

    local contentPanel = gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "98%",
        height = "90%",
        halign = "left",
        valign = "top",
        flow = "vertical",
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

    detailPanel =  gui.Panel{
        width = "100%",
        height = "100%-" .. CBStyles.SIZES.CHARACTER_PANEL_HEADER_HEIGHT,
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
function CBCharPanel._headerPanel()

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
        cornerRadius = math.floor(0.5 * CBStyles.SIZES.AVATAR_DIAMETER),
        width = CBStyles.SIZES.AVATAR_DIAMETER,
        height = CBStyles.SIZES.AVATAR_DIAMETER,
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
            local token = _getToken(element)
            element.SetValue(element, token.portrait, false)
            element:FireEvent("imageLoaded")
            element:FireEvent("updatePopout", token.popoutPortrait)
        end,

        change = function(element)
            local token = _getToken(element)
            token.portrait = element.value
            token:UploadAppearance()
        end,
    }

    local characterName = gui.Label {
        classes = {"builder-base", "label", "charname"},
        text = "calculating...",
        editable = true,
        data = {
            text = "",
        },
        change = function(element)
            if element.data.text ~= element.text then
                element.data.text = element.text
                local token = _getToken(element)
                if token then
                    if token.name ~= element.data.text then
                        token.name = element.data.text
                        _fireControllerEvent("tokenDataChanged")
                    end
                end
            end
        end,
        refreshBuilderState = function(element, state)
            local token = state:Get("token")
            element.data.text = (token and token.name and #token.name > 0) and token.name or "Unnamed Character"
            element.text = string.upper(element.data.text)
        end,
    }

    local levelClass = gui.Label {
        classes = {"builder-base", "label", "charname"},
        text = "(class & level)",
        tmargin = 4,
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local class = hero:GetClass()
                local level = hero:CharacterLevel()
                if class or level then
                    element.text = string.format("Level %d %s", level, class and class.name or ""):upper()
                end
            end
        end,
    }

    return gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "99%",
        height = CBStyles.SIZES.CHARACTER_PANEL_HEADER_HEIGHT,
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
function CBCharPanel.CreatePanel()

    local headerPanel = CBCharPanel._headerPanel()
    local detailPanel = CBCharPanel._detailPanel()

    return gui.Panel{
        id = "characterPanel",
        classes = {"builder-base", "panel-base", "border", "characterPanel"},
        width = CBStyles.SIZES.CHARACTER_PANEL_WIDTH,
        height = "99%",
        valign = "center",
        bgimage = true,
        flow = "vertical",

        headerPanel,
        detailPanel,
    }
end
