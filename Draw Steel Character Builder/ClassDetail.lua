--[[
    Class detail / selectors
]]
CBClassDetail = RegisterGameType("CBClassDetail")

local mod = dmhub.GetModLoading()

local SELECTOR = CharacterBuilder.SELECTOR.CLASS
local INITIAL_CATEGORY = "overview"

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _formatOrder = CharacterBuilder._formatOrder
local _getHero = CharacterBuilder._getHero

--- Recognise an overview-style category id ("overview" or "overview:N").
--- @param category any
--- @return boolean
local function _isOverviewCategory(category)
    if type(category) ~= "string" then return false end
    if category == INITIAL_CATEGORY then return true end
    return category:sub(1, #INITIAL_CATEGORY + 1) == (INITIAL_CATEGORY .. ":")
end

--- Pull the level number out of a per-level overview category. Returns nil
--- for the bare "overview" category (which represents the no-class intro).
--- @param category any
--- @return integer|nil
local function _parseOverviewLevel(category)
    if type(category) ~= "string" then return nil end
    local levelStr = category:match("^" .. INITIAL_CATEGORY .. ":(%d+)$")
    if levelStr then return tonumber(levelStr) end
    return nil
end

--- Generate the navigation panel
--- @return Panel
function CBClassDetail._navPanel()

    local changeButton = gui.PrettyButton{
        classes = {"changeClass", "builder-base", "button", "selector", "destructive"},
        width = CBStyles.SIZES.CATEGORY_BUTTON_WIDTH,
        height = CBStyles.SIZES.CATEGORY_BUTTON_HEIGHT,
        text = "Change Class",
        data = { category = "change" },
        press = function(element)
            _fireControllerEvent("removeClass")
        end,
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local classes = hero:try_get("classes", {})
                local isAvailable = #classes > 0
                element:SetClass("collapsed", not isAvailable)
                element:FireEvent("setAvailable", isAvailable)
            end
        end,
    }

    local selectButton = gui.PrettyButton{
        classes = {"changeClass", "builder-base", "button", "selector"},
        width = CBStyles.SIZES.CATEGORY_BUTTON_WIDTH,
        height = CBStyles.SIZES.CATEGORY_BUTTON_HEIGHT,
        text = "Select Class",
        bold = false,
        data = { category = "select" },
        press = function(element)
            _fireControllerEvent("applyCurrentClass")
        end,
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            local heroClass = hero and hero:GetClass()
            local isAvailable = state:Get(SELECTOR .. ".selectedId") ~= nil and heroClass == nil
            element:SetClass("collapsed", not isAvailable)
            element:FireEvent("setAvailable", isAvailable)
        end,
    }

    return gui.Panel{
        classes = {"categoryNavPanel", "builder-base", "panel-base", "detail-nav-panel"},
        vscroll = true,

        data = {
            levelPanels = {}
        },

        create = function(element)
            _fireControllerEvent("updateState", {
                key = SELECTOR .. ".category.selectedId",
                value = INITIAL_CATEGORY,
            })
        end,

        refreshBuilderState = function(element, state)
            local featureCache = state:Get(SELECTOR .. ".featureCache")
            if featureCache then
                local levelStatus = {}
                local features = featureCache:GetKeyedFeatures()
                for _,feature in pairs(features) do
                    local level = feature:GetLevel()
                    if level and level > 0 then
                        if levelStatus[level] == nil then
                            levelStatus[level] = {
                                available = 0,
                                selected = 0,
                                complete = false,
                            }
                        end
                        local item = levelStatus[level]
                        local featureStatus = feature:GetStatus()
                        item.available = item.available + featureStatus.numChoices
                        item.selected = item.selected + featureStatus.selected
                        item.complete = item.selected >= item.available
                    end
                end

                element:FireEventTree("updateLevelStatus", levelStatus)
            end
        end,

        registerFeatureButton = function(element, button)
            local level = button.data.level
            if level and level > 0 then
                if element.data.levelPanels[level] == nil then
                    local labelText = string.format("Level %d", level)
                    local levelPanel = gui.Panel{
                        classes = {"builder-base", "panel-base", "class-divider", "builder-header"},
                        width = CBStyles.SIZES.CATEGORY_BUTTON_WIDTH + 20,
                        valign = "top",
                        halign = "center",
                        vmargin = 8,
                        data = {
                            level = level,
                            order = _formatOrder(level or 99, _formatOrder(0, labelText)),
                            expanded = true,
                        },
                        press = function(element)
                            local data = element.data
                            data.expanded = not data.expanded
                            element.parent:FireEventTree("showLevel", data.level, data.expanded)
                        end,
                        gui.Label{
                            classes = {"builder-base", "label", "class-divider", "builder-header"},
                            text = labelText,
                        },
                        gui.Panel{
                            classes = {"builder-base", "panel-base", "class-divider", "builder-check"},
                            updateLevelStatus = function(element, levelStatus)
                                local level = element.parent.data.level
                                if level and level > 0 then
                                    local info = levelStatus[level]
                                    if info then
                                        element:SetClass("complete", info.complete)
                                    end
                                end
                            end,
                        },
                        gui.Label{
                            classes = {"builder-base", "label", "class-divider", "builder-header"},
                            width = "auto",
                            halign = "right",
                            hmargin = 40,
                            updateLevelStatus = function(element, levelStatus)
                                local level = element.parent.data.level
                                if level and level > 0 then
                                    local info = levelStatus[level]
                                    if info then
                                        element.text = string.format("%d/%d", info.selected, info.available)
                                        element:SetClass("collapsed", info.complete)
                                    end
                                end
                            end,
                        },
                        gui.CollapseArrow{
                            halign = "right",
                            valign = "center",
                            bgcolor = CBStyles.COLORS.GOLD03,
                            showLevel = function(element, level, expanded)
                                if level == element.parent.data.level then
                                    element:SetClass("collapseSet", not expanded)
                                end
                            end,
                        }
                    }
                    element.data.levelPanels[level] = levelPanel
                    element:AddChild(levelPanel)

                    local overviewCategory = INITIAL_CATEGORY .. ":" .. tostring(level)
                    local overviewButtonPanel
                    overviewButtonPanel = gui.Panel{
                        classes = {"builder-base", "panel-base"},
                        valign = "top",
                        data = {
                            level = level,
                            order = _formatOrder(level, _formatOrder(1, "Overview")),
                            category = overviewCategory,
                            visible = true,
                        },
                        press = function(panelEl)
                            _fireControllerEvent("updateState", {
                                key = SELECTOR .. ".category.selectedId",
                                value = panelEl.data.category,
                            })
                        end,
                        showLevel = function(panelEl, showLvl, expanded)
                            if panelEl.data.level == showLvl then
                                panelEl.data.visible = expanded
                            end
                            panelEl:SetClass("collapsed-anim", not panelEl.data.visible)
                        end,
                        CharacterBuilder._makeCategoryButton{
                            text = "Overview",
                            press = function(buttonEl)
                                _fireControllerEvent("updateState", {
                                    key = SELECTOR .. ".category.selectedId",
                                    value = buttonEl.parent.data.category,
                                })
                            end,
                            refreshBuilderState = function(buttonEl, state)
                                buttonEl:FireEvent("setAvailable", state:Get(SELECTOR .. ".selectedId") ~= nil)
                                buttonEl:FireEvent("setSelected", state:Get(SELECTOR .. ".category.selectedId") == buttonEl.parent.data.category)
                            end,
                        },
                    }
                    element:AddChild(overviewButtonPanel)
                end
            end
            element:AddChild(button)
            element.children = CharacterBuilder._sortButtons(element.children)
        end,

        destroyFeature = function(element, featureId)
            local child = element:FindChildRecursive(function(e)
                return e.data and e.data.featureId == featureId
            end)
            if child then
                child:DestroySelf()
            end
        end,

        selectButton,
        changeButton,
    }
end

--- Build the overview panel
--- Used when no Class is selected and to overview the selected class
--- @return Panel
function CBClassDetail._overviewPanel()

    local nameLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "header"},
            text = "CLASS",

            refreshBuilderState = function(element, state)
                local text = "CLASS"
                local classId = state:Get(SELECTOR .. ".selectedId")
                if classId then
                    local class = state:Get(SELECTOR .. ".selectedItem")
                    if not class then
                        class = dmhub.GetTable(Class.tableName)[classId]
                    end
                    if class then text = class.name end
                end
                local level = _parseOverviewLevel(state:Get(SELECTOR .. ".category.selectedId"))
                if level then
                    text = string.format("%s - Level %d", text, level)
                end
                element.text = text
            end
        }
    }

    local introLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        refreshBuilderState = function(element, state)
            local level = _parseOverviewLevel(state:Get(SELECTOR .. ".category.selectedId"))
            element:SetClass("collapsed", level ~= nil)
        end,
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            bmargin = 12,
            markdown = true,
            text = CharacterBuilder.STRINGS.CLASS.INTRO,

            refreshBuilderState = function(element, state)
                local text = CharacterBuilder.STRINGS.CLASS.INTRO
                local classId = state:Get(SELECTOR .. ".selectedId")
                if classId then
                    local class = state:Get(SELECTOR .. ".selectedItem")
                    if not class then
                        class = dmhub.GetTable(Class.tableName)[classId]
                    end
                    if class then text = class.details end
                end
                element.text = text
            end,
        }
    }

    local detailLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            tmargin = 12,
            bold = false,
            markdown = true,
            text = CharacterBuilder.STRINGS.CLASS.OVERVIEW,

            refreshBuilderState = function(element, state)
                local text = CharacterBuilder.STRINGS.CLASS.OVERVIEW
                local classId = state:Get(SELECTOR .. ".selectedId")
                if classId then
                    local textItems = {}

                    local featureCache = state:Get(SELECTOR .. ".featureCache")
                    local filterLevel = _parseOverviewLevel(state:Get(SELECTOR .. ".category.selectedId"))
                    local featureDetails = featureCache:GetFlattenedFeatures()
                    for _,item in ipairs(featureDetails) do
                        local include = true
                        if filterLevel then
                            include = false
                            local itemLevels = item.levels
                            if itemLevels then
                                for _,l in ipairs(itemLevels) do
                                    if l == filterLevel then
                                        include = true
                                        break
                                    end
                                end
                            end
                        end
                        if include then
                            local s = item.feature:GetDetailedSummaryText()
                            if s ~= nil and #s > 0 then
                                textItems[#textItems+1] = s
                            end
                        end
                    end

                    text = table.concat(textItems, "\n\n")
                end
                element.text = text
            end
        }
    }

    local spacerPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        width = "50%",
        height = "66%",
    }

    return gui.Panel{
        id = "classOverviewPanel",
        classes = {"classOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "border", "collapsed"},
        bgimage = mod.images.classHome,

        data = {
            category = "overview",
        },

        refreshBuilderState = function(element, state)
            local classId = state:Get(SELECTOR .. ".selectedId")
            local category = state:Get(SELECTOR .. ".category.selectedId")

            local visible = classId == nil or _isOverviewCategory(category)
            element:SetClass("collapsed", not visible)

            if visible then
                if classId == nil then
                    element.bgimage = mod.images.classHome
                    return
                end
                local class = state:Get(SELECTOR .. ".selectedItem")
                if not class then
                    class = dmhub.GetTable(Class.tableName)[classId]
                end
                if class then element.bgimage = class.portraitid end
            end
        end,

        gui.Panel{
            classes = {"builder-base", "panel-base", "container"},
            height = "100%-80",
            bmargin = 32,
            valign = "bottom",
            vscroll = true,
            data = {
                lastSelected = nil,
            },

            refreshBuilderState = function(element, state)
                local currentSelected = state:Get(SELECTOR .. ".selectedId")
                if currentSelected ~= element.data.lastSelected then
                    element.data.lastSelected = currentSelected
                    element.vscrollPosition = 1
                end
            end,

            spacerPanel,
            nameLabel,
            introLabel,
            detailLabel,
        }
    }
end

--- The main panel for working with class
--- @return Panel
function CBClassDetail.CreatePanel()

    local navPanel = CBClassDetail._navPanel()

    local overviewPanel = CBClassDetail._overviewPanel()

    local detailPanel = gui.Panel{
        id = "classDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "classDetailpanel"},

        registerFeaturePanel = function(element, panel)
            element:AddChild(panel)
            local selectButton = element:FindChildRecursive(function(e) return e:HasClass("selectButton") end)
            if selectButton then selectButton:SetAsLastSibling() end
        end,

        destroyFeature = function(element, featureId)
            local child = element:FindChildRecursive(function(e)
                return e.data and e.data.featureId == featureId
            end)
            if child then
                child:DestroySelf()
            end
        end,

        overviewPanel,
    }

    return gui.Panel{
        id = "classPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "classPanel"},
        data = {
            selector = SELECTOR,
            features = {},
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get("activeSelector") == element.data.selector
            element:SetClass("collapsed-anim", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end

            local categoryKey = SELECTOR .. ".category.selectedId"
            local currentCategory = state:Get(categoryKey) or INITIAL_CATEGORY
            local hero = _getHero()
            if hero then
                local heroClass = state:Get(SELECTOR .. ".selectedId")

                if heroClass ~= nil then
                    for id,_ in pairs(element.data.features) do
                        element.data.features[id] = false
                    end

                    local featureCache = state:Get(SELECTOR .. ".featureCache")
                    local features = featureCache:GetSortedFeatures()
                    for _,f in ipairs(features) do
                        local featureId = f.guid
                        local feature = featureCache:GetFeature(featureId)
                        if feature then
                            if element.data.features[featureId] == nil then
                                local featureRegistry = CharacterBuilder._makeFeatureRegistry{
                                    feature = feature,
                                    selector = SELECTOR,
                                    selectedId = heroClass,
                                    getSelected = function(hero)
                                        return heroClass
                                    end,
                                }
                                if featureRegistry then
                                    element.data.features[featureId] = true
                                    navPanel:FireEvent("registerFeatureButton", featureRegistry.button)
                                    detailPanel:FireEvent("registerFeaturePanel", featureRegistry.panel)
                                end
                            else
                                element.data.features[featureId] = true
                            end
                        end
                    end

                    for id, active in pairs(element.data.features) do
                        if active == false then
                            navPanel:FireEvent("destroyFeature", id)
                            detailPanel:FireEvent("destroyFeature", id)
                            element.data.features[id] = nil
                        end
                    end
                else
                    -- No class selected: only the bare "overview" intro applies.
                    if currentCategory ~= INITIAL_CATEGORY then
                        currentCategory = INITIAL_CATEGORY
                    end
                end
            end

            -- Which category to show?
            if not _isOverviewCategory(currentCategory) and not element.data.features[currentCategory] then
                currentCategory = INITIAL_CATEGORY
            end
            state:Set{ key = categoryKey, value = currentCategory }
        end,

        navPanel,
        detailPanel,
    }
end

--- Build the characteristic editor panel, leveraged by injection
--- through CharacterCharacteristicChoice into the feature editor.
--- @return Panel
function CBClassDetail._characteristicPanel()

    local function attrPanel(attr)
        return gui.Panel{
            classes = {"builder-base", "panel-base", "attr-item"},
            flow = "vertical",
            data = {
                attr = attr,
                locked = true,
            },
            refreshBuilderState = function(element, state)
                local classItem = state:Get(SELECTOR .. ".selectedItem")
                if classItem then
                    local baseChars = classItem:try_get("baseCharacteristics", {})
                    element.data.locked = baseChars[element.data.attr.id] ~= nil
                end
                element:SetClass("locked", element.data.locked)
            end,
            gui.Label{
                classes = {"builder-base", "label", "attr-name"},
                text = attr.description:upper()
            },
            gui.Label{
                classes = {"builder-base", "label", "attr-value"},
                canDragOnto = function(element, target)
                    return target ~= nil and target:HasClass("attr-value") and not target:HasClass("parent:locked")
                end,
                drag = function(element, target)
                    if target == nil then return end
                    local hero = _getHero()
                    if hero == nil then return end
                    local attributes = hero:try_get("attributes")
                    if attributes == nil then return end

                    -- Assign the base attributes
                    local attrId1 = element.parent.data.attr.id
                    local attrId2 = target.parent.data.attr.id
                    local attrVal1 = attributes[attrId1].baseValue or 0
                    local attrVal2 = attributes[attrId2].baseValue or 0

                    if attrVal1 == attrVal2 then return end

                    attributes[attrId1].baseValue = attrVal2
                    attributes[attrId2].baseValue = attrVal1

                    -- Update the attribute build
                    local attributeBuild = hero:try_get("attributeBuild")
                    if attributeBuild then
                        local attrIdx1 = attributeBuild[attrId1] or 0
                        local attrIdx2 = attributeBuild[attrId2] or 0
                        attributeBuild[attrId1] = attrIdx2
                        attributeBuild[attrId2] = attrIdx1
                    end

                    _fireControllerEvent("tokenDataChanged")
                end,
                refreshBuilderState = function(element, state)
                    local blockSel = state:Get(SELECTOR .. ".blockFeatureSelection") == true
                    local locked = element.parent:HasClass("locked")
                    local baseValue = locked and 2 or 0
                    if not blockSel then
                        local hero = _getHero()
                        local attributes = hero:try_get("attributes")
                        baseValue = attributes and attributes[attr.id] and attributes[attr.id].baseValue or 0
                    end
                    element.text = string.format("%+d", baseValue)
                    local draggable = element.parent.data.locked == false
                    element.draggable = draggable
                    element.dragTarget = draggable
                    element.hoverCursor = draggable and "hand" or nil
                end,
            },
            gui.Panel{
                classes = {"builder-base", "panel-base", "attr-lock"},
                floating = true,
            }
        }
    end

    return gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        gui.MCDMDivider{
            classes = {"builder-divider"},
            layout = "line",
            width = "96%",
            vpad = 4,
            bgcolor = CBStyles.COLORS.GOLD
        },
        gui.Panel{
            classes = {"builder-base", "panel-base", "container", "attr-container"},
            flow = "horizontal",
            valign = "top",

            refreshBuilderState = function(element, state)
                if #element.children == 0 then
                    local attrInfo = CharacterBuilder._toArray(creature.attributesInfo)
                    CharacterBuilder._sortArrayByProperty(attrInfo, "order")
                    for _,attr in ipairs(attrInfo) do
                        element:AddChild(attrPanel(attr))
                    end
                end
            end,
        },
        gui.MCDMDivider{
            classes = {"builder-divider"},
            layout = "line",
            width = "96%",
            vpad = 4,
            bgcolor = CBStyles.COLORS.GOLD
        },
    }
end
