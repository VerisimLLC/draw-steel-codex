--[[
    Selector panels
]]
CBFeatureSelector = RegisterGameType("CBFeatureSelector")

local _characterHasLevelChoice = CharacterBuilder._characterHasLevelChoice
local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getHero = CharacterBuilder._getHero

--- Build a feature panel with selections
--- @return Panel|nil
function CBFeatureSelector.Panel(feature)
    -- print("THC:: FEATUREPANEL::", feature.name, feature)
    -- print("THC:: FEATUREPANEL::", feature.name, json(feature))

    local typeName = feature.typeName or ""
    if typeName == "CharacterDeityChoice" then
    elseif typeName == "CharacterFeatChoice" then
        return CBFeatureSelector.PerkPanel(feature)
    elseif typeName == "CharacterFeatureChoice" then
        return CBFeatureSelector.FeaturePanel(feature)
    elseif typeName == "CharacterLanguageChoice" then
        return CBFeatureSelector.LanguagePanel(feature)
    elseif typeName == "CharacterSkillChoice" then
        return CBFeatureSelector.SkillPanel(feature)
    elseif typeName == "CharacterSubclassChoice" then
    elseif typeName == "CharacterAncestryInheritanceChoice" then
        return CBFeatureSelector.AncestryInheritancePanel(feature)
    end

    return nil
end

--- Render an ancestry inheritance choice panel (e.g., for Revenant's "former ancestry")
--- @param feature CharacterAncestryInheritanceChoice
--- @return Panel
function CBFeatureSelector.AncestryInheritancePanel(feature)

    local targetsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        data = {
            numChoices = 1,
            itemCache = {},
        },
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local numChoices = feature:NumChoices(hero)
            element.data.numChoices = numChoices

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)
            element.data.itemCache = {}
            for _, choice in ipairs(currentChoices) do
                element.data.itemCache[choice.id] = dmhub.GetTableVisible(Race.tableName)[choice.id]
            end

            for i = #element.children + 1, numChoices do
                element:AddChild(CBFeatureSelector._createTargetPanel({ feature = feature, itemIndex = i }))
            end
        end,
    }

    local function createOptionPanel()
        return gui.Panel{
            classes = {"builder-base", "panel-base", "feature-choice"},
            valign = "top",
            data = {
                choice = nil,
            },
            click = function(element)
                if not element.data.choice then return end
                local parent = element:FindParentWithClass("featureSelector")
                if parent then
                    parent:FireEvent("selectItem", element.data.choice.id)
                end
            end,
            refreshBuilderState = function(element, state)
                if not element.data.choice then
                    element:SetClass("collapsed", true)
                    return
                end

                local hero = _getHero(state)
                if hero then
                    local levelChoices = hero:GetLevelChoices()
                    if levelChoices then
                        local selectedItems = levelChoices[feature.guid]
                        if selectedItems then
                            for _, selectedId in ipairs(selectedItems) do
                                if selectedId == element.data.choice.id then
                                    element:SetClass("collapsed", true)
                                    return
                                end
                            end
                        end
                    end
                end

                element:FireEventTree("updateText", element.data.choice.text)
                element:SetClass("collapsed", false)
            end,
            refreshSelection = function(element, selectedId)
                element:SetClass("selected", element.data.choice and selectedId == element.data.choice.id)
            end,
            assignChoice = function(element, choice)
                element.data.choice = choice
            end,
            gui.Label{
                classes = {"builder-base", "label", "feature-choice"},
                text = "",
                updateText = function(element, text)
                    if element.text ~= text then element.text = text end
                end,
            }
        }
    end

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(createOptionPanel())
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, choice in ipairs(currentChoices) do
                element.children[i]:FireEvent("assignChoice", choice)
            end

            for i = numOptions + 1, #element.children do
                element.children[i]:FireEvent("assignChoice", nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel(feature, targetsContainer, optionsContainer)
end

--- Render a feature choice panel
--- @param feature CharacterFeatureChoice
--- @return Panel
function CBFeatureSelector.FeaturePanel(feature)

    local function formatOptionName(option)
        local s = option.name
        local pointCost = option:try_get("pointsCost")
        if pointCost then
            s = string.format("%s (%d point%s)", s, pointCost, pointCost ~= 1 and "s" or "")
        end
        return s
    end

    local targetsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        data = {
            numChoices = 1,
            itemCache = {},
        },
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local numChoices = feature:NumChoices(hero)
            element.data.numChoices = numChoices

            local levelChoices = hero:GetLevelChoices()
            local currentOptions = feature:GetOptions(levelChoices)
            element.data.itemCache = {}
            for _, option in ipairs(currentOptions) do
                element.data.itemCache[option.guid] = option
            end

            for i = #element.children + 1, numChoices do
                element:AddChild(CBFeatureSelector._createTargetPanel({
                    feature = feature,
                    itemIndex = i,
                    useDesc = true,
                    idFieldName = "guid",
                    formatName = formatOptionName,
                }))
            end
        end,
    }

    local function createOptionPanel()
        return gui.Panel{
            classes = {"builder-base", "panel-base", "feature-choice"},
            data = {
                choice = nil,
            },
            click = function(element)
                if not element.data.choice then return end
                local parent = element:FindParentWithClass("featureSelector")
                if parent then
                    parent:FireEvent("selectItem", element.data.choice.guid)
                end
            end,
            refreshBuilderState = function(element, state)
                if not element.data.choice then
                    element:SetClass("collapsed", true)
                    return
                end

                local hero = _getHero(state)
                if hero then
                    local collapsed = _characterHasLevelChoice(hero, feature.guid, element.data.choice.guid)
                    element:SetClass("collapsed", collapsed)
                    if collapsed then return end
                end

                element:FireEventTree("updateName", formatOptionName(element.data.choice))
                element:FireEventTree("updateDesc", element.data.choice.description)
                element:SetClass("collapsed", false)
            end,
            refreshSelection = function(element, selectedId)
                local selected = element.data.choice and selectedId == element.data.choice.guid
                element:SetClass("selected", selected)
            end,
            assignChoice = function(element, choice)
                element.data.choice = choice
            end,
            gui.Label{
                classes = {"builder-base", "label", "feature-choice"},
                text = "",
                updateName = function(element, text)
                    if element.text ~= text then element.text = text end
                end,
            },
            gui.Label{
                classes = {"builder-base", "label", "feature-choice", "desc"},
                textAlignment = "left",
                text = "",
                updateDesc = function(element, text)
                    if element.text ~= text then element.text = text end
                end,
            },
        }
    end

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentOptions = feature:GetOptions(levelChoices)

            local numOptions = #currentOptions

            for _ = #element.children + 1, numOptions do
                element:AddChild(createOptionPanel())
            end

            table.sort(currentOptions, function(a, b) return a.name < b.name end)

            for i, option in ipairs(currentOptions) do
                element.children[i]:FireEvent("assignChoice", option)
            end

            for i = numOptions + 1, #element.children do
                element.children[i]:FireEvent("assignChoice", nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel(feature, targetsContainer, optionsContainer)
end

--- Render a language choice panel
--- @param feature CharacterLanguageChoice
--- @return Panel
function CBFeatureSelector.LanguagePanel(feature)

    local targetsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        data = {
            numChoices = 1,
            itemCache = {},
        },
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local numChoices = feature:NumChoices(hero)
            element.data.numChoices = numChoices

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)
            element.data.itemCache = {}
            for _, choice in ipairs(currentChoices) do
                element.data.itemCache[choice.id] = dmhub.GetTableVisible(Language.tableName)[choice.id]
            end

            for i = #element.children + 1, numChoices do
                element:AddChild(CBFeatureSelector._createTargetPanel({ feature = feature, itemIndex = i }))
            end
        end,
    }

    local function createOptionPanel()
        return gui.Panel{
            classes = {"builder-base", "panel-base", "feature-choice"},
            valign = "top",
            data = {
                choice = nil,
            },
            click = function(element)
                if not element.data.choice then return end
                local parent = element:FindParentWithClass("featureSelector")
                if parent then
                    parent:FireEvent("selectItem", element.data.choice.id)
                end
            end,
            refreshBuilderState = function(element, state)
                if not element.data.choice then
                    element:SetClass("collapsed", true)
                    return
                end

                if element.data.choice.unique then
                    local hero = _getHero(state)
                    if hero then
                        local langsKnown = hero:LanguagesKnown()
                        if langsKnown and langsKnown[element.data.choice.id] then
                            element:SetClass("collapsed", true)
                            return
                        end
                    end
                end

                element:FireEventTree("updateText", element.data.choice.text)
                element:SetClass("collapsed", false)
            end,
            refreshSelection = function(element, selectedId)
                element:SetClass("selected", element.data.choice and selectedId == element.data.choice.id)
            end,
            assignChoice = function(element, choice)
                element.data.choice = choice
            end,
            gui.Label{
                classes = {"builder-base", "label", "feature-choice"},
                text = "",
                updateText = function(element, text)
                    if element.text ~= text then element.text = text end
                end,
            }
        }
    end

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(createOptionPanel())
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, choice in ipairs(currentChoices) do
                element.children[i]:FireEvent("assignChoice", choice)
            end

            for i = numOptions + 1, #element.children do
                element.children[i]:FireEvent("assignChoice", nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel(feature, targetsContainer, optionsContainer)
end

--- Render a perk choice panel
--- @param feature CharacterFeatChoice
--- @return Panel
function CBFeatureSelector.PerkPanel(feature)

    local targetsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        data = {
            numChoices = 1,
            itemCache = {},
        },
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local numChoices = feature:NumChoices(hero)
            element.data.numChoices = numChoices

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)
            element.data.itemCache = {}
            for _, choice in ipairs(currentChoices) do
                element.data.itemCache[choice.id] = dmhub.GetTableVisible(CharacterFeat.tableName)[choice.id]
            end

            for i = #element.children + 1, numChoices do
                element:AddChild(CBFeatureSelector._createTargetPanel({ feature = feature, itemIndex = i, useDesc = true }))
            end
        end,
    }

    local function createOptionPanel()
        return gui.Panel{
            classes = {"builder-base", "panel-base", "feature-choice"},
            valign = "top",
            data = {
                choice = nil,
            },
            click = function(element)
                if not element.data.choice then return end
                local parent = element:FindParentWithClass("featureSelector")
                if parent then
                    parent:FireEvent("selectItem", element.data.choice.id)
                end
            end,
            refreshBuilderState = function(element, state)
                if not element.data.choice then
                    element:SetClass("collapsed", true)
                    return
                end

                local cachedPerks = state:Get("cachedPerks")
                local collapsed = cachedPerks and cachedPerks[element.data.choice.id]
                element:SetClass("collapsed", collapsed)
                if collapsed then return end

                local perk = dmhub.GetTableVisible(CharacterFeat.tableName)[element.data.choice.id]
                local desc = perk and perk.description or ""
                element:FireEventTree("updateText", element.data.choice.text)
                element:FireEventTree("updateDesc", desc)
            end,
            refreshSelection = function(element, selectedId)
                element:SetClass("selected", element.data.choice and selectedId == element.data.choice.id)
            end,
            assignChoice = function(element, choice)
                element.data.choice = choice
            end,
            gui.Label{
                classes = {"builder-base", "label", "feature-choice"},
                text = "",
                updateText = function(element, text)
                    if element.text ~= text then element.text = text end
                end,
            },
            gui.Label{
                classes = {"builder-base", "label", "feature-choice", "desc"},
                textAlignment = "left",
                text = "",
                updateDesc = function(element, text)
                    if element.text ~= text then element.text = text end
                end,
            },
        }
    end

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(createOptionPanel())
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, choice in ipairs(currentChoices) do
                element.children[i]:FireEvent("assignChoice", choice)
            end

            for i = numOptions + 1, #element.children do
                element.children[i]:FireEvent("assignChoice", nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel(feature, targetsContainer, optionsContainer)
end

--- Render a skill choice panel
--- @param feature CharacterSkillChoice
--- @return Panel
function CBFeatureSelector.SkillPanel(feature)

    local targetsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        data = {
            numChoices = 1,
            itemCache = {},
        },
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local numChoices = feature:NumChoices(hero)
            element.data.numChoices = numChoices

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)
            element.data.itemCache = {}
            for _, choice in ipairs(currentChoices) do
                element.data.itemCache[choice.id] = dmhub.GetTableVisible(Skill.tableName)[choice.id]
            end

            for i = #element.children + 1, numChoices do
                element:AddChild(CBFeatureSelector._createTargetPanel({ feature = feature, itemIndex = i }))
            end
        end,
    }

    local function createOptionPanel()
        return gui.Panel{
            classes = {"builder-base", "panel-base", "feature-choice"},
            valign = "top",
            data = {
                choice = nil,
            },
            click = function(element)
                if not element.data.choice then return end
                local parent = element:FindParentWithClass("featureSelector")
                if parent then
                    parent:FireEvent("selectItem", element.data.choice.id)
                end
            end,
            refreshBuilderState = function(element, state)
                if not element.data.choice then
                    element:SetClass("collapsed", true)
                    return
                end

                if element.data.choice.unique ~= nil and element.data.choice.unique then
                    local hero = _getHero(state)
                    if hero then
                        -- local skill = dmhub.GetTableVisible(Skill.tableName)[element.data.choice.id]
                        if hero:ProficientInSkill(element.data.choice) then
                            element:SetClass("collapsed", true)
                            return
                        end
                    end
                end

                element:FireEventTree("updateText", element.data.choice.text)
                element:SetClass("collapsed", false)
            end,
            refreshSelection = function(element, selectedId)
                element:SetClass("selected", element.data.choice and selectedId == element.data.choice.id)
            end,
            assignChoice = function(element, choice)
                element.data.choice = choice
            end,
            gui.Label{
                classes = {"builder-base", "label", "feature-choice"},
                text = "",
                updateText = function(element, text)
                    if element.text ~= text then element.text = text end
                end,
            }
        }
    end

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(createOptionPanel())
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, choice in ipairs(currentChoices) do
                element.children[i]:FireEvent("assignChoice", choice)
            end

            for i = numOptions + 1, #element.children do
                element.children[i]:FireEvent("assignChoice", nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel(feature, targetsContainer, optionsContainer)
end

--- Build a consistent list of targets and children
--- @param feature table
--- @param targetsContainer Panel The container panel for targets
--- @param optionsContainer Panel The container panel for options
--- @return table children
function CBFeatureSelector._buildChildren(feature, targetsContainer, optionsContainer)
    local children = {}

    children[#children+1] = gui.Label {
        classes = {"builder-base", "label", "feature-header", "name"},
        text = feature.name,
    }

    children[#children+1] = gui.Label {
        classes = {"builder-base", "label", "feature-header", "desc"},
        text = feature:GetDescription(),
    }

    children[#children+1] = targetsContainer

    children[#children+1] = gui.MCDMDivider{
        classes = {"builder-divider"},
        layout = "v",
        width = "96%",
        vpad = 4,
        bgcolor = CBStyles.COLORS.GOLD,
    }

    children[#children+1] = optionsContainer

    return children
end

--- Create a target panel for a feature
--- @param config table Configuration: feature, itemIndex, useDesc, idFieldName, formatName
--- @return Panel
function CBFeatureSelector._createTargetPanel(config)
    local feature = config.feature
    local itemIndex = config.itemIndex
    local useDesc = config.useDesc or false
    local costsPoints = feature:try_get("costsPoints", false)
    local idFieldName = config.idFieldName or "id"
    local formatName = config.formatName or function(item) return item:try_get("name") end

    return gui.Panel{
        classes = {"builder-base", "panel-base", "feature-target", "empty"},
        data = {
            featureGuid = feature.guid,
            costsPoints = costsPoints,
            itemIndex = itemIndex,
            item = nil,
            useDesc = useDesc,
        },
        click = function(element)
            if not element.data.item then return end
            _fireControllerEvent(element, "removeLevelChoice", {
                levelChoiceGuid = element.data.featureGuid,
                selectedId = element.data.item[idFieldName],
            })
        end,
        linger = function(element)
            if element.data.item then
                gui.Tooltip("Press to delete")(element)
            end
        end,
        refreshBuilderState = function(element, state)
            local numChoices = element.parent.data.numChoices or 1
            if element.data.itemIndex > numChoices then
                element:SetClass("collapsed", true)
                return
            end
            element:SetClass("collapsed", false)

            local item = nil
            local hero = _getHero(state)
            if hero then
                local levelChoices = hero:GetLevelChoices()
                if levelChoices then
                    local selectedItems = levelChoices[element.data.featureGuid]
                    if selectedItems and #selectedItems >= element.data.itemIndex then
                        local selectedId = selectedItems[element.data.itemIndex]
                        if selectedId then
                            local itemCache = element.parent.data.itemCache or {}
                            item = itemCache[selectedId]
                        end
                    end
                end
            end

            element.data.item = item
            local newText = item and formatName(item) or "Empty Slot"
            local newDesc = element.data.useDesc and item and item:try_get("description", "") or ""
            element:FireEventTree("updateName", newText)
            element:FireEventTree("updateDesc", newDesc)
            element:SetClass("filled", item ~= nil)
            element:FireEvent("setVisibility")
        end,
        setVisibility = function(element)
            local visible = true
            local numChoices = element.parent.data.numChoices or 1
            if element.data.costsPoints and element.data.item == nil then
                local container = element.parent
                if container then
                    local pointsSelected = 0
                    for _,child in ipairs(container.children) do
                        local childItem = child.data and child.data.item
                        if childItem then
                            pointsSelected = pointsSelected + childItem:try_get("pointsCost", 1)
                        end
                    end
                    visible = pointsSelected < numChoices
                end
            end
            element:SetClass("collapsed-anim", not visible)
        end,
        gui.Label{
            classes = {"builder-base", "label", "feature-target"},
            text = "Empty Slot",
            updateName = function(element, text)
                if element.text ~= text then element.text = text end
            end,
        },
        gui.Label{
            classes = {"builder-base", "label", "feature-target", "desc"},
            updateDesc = function(element, text)
                if element.text ~= text then element.text = text end
            end,
        }
    }
end

--- Build a consistent main panel
--- @param feature table
--- @param targetsContainer Panel The container panel for targets
--- @param optionsContainer Panel The container panel for options
--- @return Panel
function CBFeatureSelector._mainPanel(feature, targetsContainer, optionsContainer)

    local children = CBFeatureSelector._buildChildren(feature, targetsContainer, optionsContainer)

    local scrollPanel = CBFeatureSelector._scrollPanel(children)

    local selectButton = CharacterBuilder._makeSelectButton{
        click = function(element)
            local parent = element:FindParentWithClass("featureSelector")
            if parent then
                parent:FireEvent("applyCurrentItem")
            end
        end,
        refreshBuilderState = function(element, state)
            -- TODO:
        end,
    }

    return gui.Panel{
        classes = {"featureSelector", "builder-base", "panel"},
        width = "100%",
        height = "100%",
        halign = "left",
        flow = "vertical",

        data = {
            feature = feature,
            selectedId = nil,   -- The item currently selected in the options list
        },

        applyCurrentItem = function(element)
            if element.data.selectedId then
                _fireControllerEvent(element, "applyLevelChoice", {
                    feature = feature,
                    selectedId = element.data.selectedId
                })
            end
        end,

        selectItem = function(element, itemId)
            element.data.selectedId = itemId
            element:FireEventTree("refreshSelection", itemId)
        end,

        scrollPanel,
        gui.MCDMDivider{
            classes = {"builder-divider"},
            layout = "line",
            width = "96%",
            vpad = 4,
            bgcolor = "white"
        },
        selectButton,
    }
end

--- Build a container panel for the list of targets or options
--- @param children table The list of child elements
--- @return Panel
function CBFeatureSelector._containerPanel(children)
    return gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        children = children,
    }
end

--- Build a consistent scrollable panel for choices
--- @param children table The list of child elements to scroll
--- @return Panel
function CBFeatureSelector._scrollPanel(children)
    return gui.Panel {
        classes = {"builder-base", "panel-base"},
        width = "100%",
        height = "100%-60",
        halign = "left",
        valign = "top",
        flow = "vertical",
        vscroll = true,
        gui.Panel{
            classes = {"builder-base", "panel-base", "container"},
            flow = "vertical",
            children = children,
        },
    }
end