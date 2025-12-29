--[[
    Selector panels
]]
CBFeatureSelector = RegisterGameType("CBFeatureSelector")

local _characterHasLevelChoice = CharacterBuilder._characterHasLevelChoice
local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getHero = CharacterBuilder._getHero

--- Determine if the builder cares about the feature and, if so,
--- return a structure defining how to interact with it.
--- @param feature CharacterFeature
--- @return table|nil
function CBFeatureSelector.EvaluateFeature(feature)
    local typeName = feature.typeName or ""
    if #typeName == 0 then return nil end

    local typeOrder = {
        CharacterAncestryInheritanceChoice  = 1,
        CharacterDeityChoice                = 2,
        CharacterDomainChoice               = 3,
        CharacterSubclassChoice             = 4,
        CharacterFeatureChoice              = 5,
        CharacterSkillChoice                = 6,
        CharacterLanguageChoice             = 7,
        CharacterFeatChoice                 = 8,
        CharacterIncidentChoice             = 9,
    }

    local configs = {
        CharacterAncestryInheritanceChoice = {
            category = "Inherited Ancestry",
            panelFn = CBFeatureSelector.AncestryInheritancePanel,
        },
        CharacterDeityChoice = {
            category = "Deity",
            panelFn = CBFeatureSelector.DeityPanel,
        },
        CharacterDomainChoice = {
            category = "Domain",
            panelFn = CBFeatureSelector.DomainPanel,
        },
        CharacterFeatChoice = {
            category = "Perk",
            panelFn = CBFeatureSelector.PerkPanel,
        },
        CharacterFeatureChoice = {
            category = "Feature",
            panelFn = CBFeatureSelector.FeaturePanel,
        },
        CharacterIncidentChoice = {
            category = "Incident",
            panelFn = CBFeatureSelector.IncidentPanel,
        },
        CharacterLanguageChoice = {
            category = "Language",
            panelFn = CBFeatureSelector.LanguagePanel,
        },
        CharacterSkillChoice = {
            category = "Skill",
            panelFn = CBFeatureSelector.SkillPanel,
        },
        -- CharacterSubclassChoice = {
        --     category = "Subclass",
        --     panelFn = nil,
        -- },
    }

    local item = configs[typeName]
    if item then
        local catOrder = typeOrder[typeName] or 99
        item.catOrder = catOrder
        item.order = string.format("%02d-%s", catOrder, feature.name)
        item.feature = feature
    end
    return item
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
                element:AddChild(CBFeatureSelector._targetPanel{ feature = feature, itemIndex = i })
            end
        end,
    }

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(CBFeatureSelector._optionPanel({
                    feature = feature,
                    itemIsSelected = function(state, featureGuid, item)
                        local hero = _getHero(state)
                        if hero then
                            local levelChoices = hero:GetLevelChoices()
                            if levelChoices then
                                local selectedItems = levelChoices[featureGuid]
                                if selectedItems then
                                    for _, selectedId in ipairs(selectedItems) do
                                        return selectedId == item.id
                                    end
                                end
                            end
                        end
                        return false
                    end,
                }))
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, child in ipairs(element.children) do
                local choice = currentChoices[i]
                child:FireEvent("assignItem", choice and dmhub.GetTable(Race.tableName)[choice.id] or nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel{
        feature = feature,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
    }
end

--- Render deity choice panel
--- @param feature CharacterDeityChoice
--- @return Panel
function CBFeatureSelector.DeityPanel(feature)

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
                element.data.itemCache[choice.id] = dmhub.GetTableVisible(Deity.tableName)[choice.id]
            end

            for i = #element.children + 1, numChoices do
                element:AddChild(CBFeatureSelector._targetPanel{ feature = feature, itemIndex = i })
            end
        end,
    }

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(CBFeatureSelector._optionPanel({
                    feature = feature,
                    itemIsSelected = function(state, featureGuid, item)
                        local hero = _getHero(state)
                        if hero then
                            local levelChoices = hero:GetLevelChoices()
                            if levelChoices then
                                local selectedItems = levelChoices[featureGuid]
                                if selectedItems then
                                    for _, selectedId in ipairs(selectedItems) do
                                        return selectedId == item.id
                                    end
                                end
                            end
                        end
                        return false
                    end,
                }))
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, child in ipairs(element.children) do
                local choice = currentChoices[i]
                child:FireEvent("assignItem", choice and dmhub.GetTable(Deity.tableName)[choice.id] or nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel{
        feature = feature,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
    }
end

--- Render deity choice panel
--- @param feature CharacterDomainChoice
--- @return Panel
function CBFeatureSelector.DomainPanel(feature)
    print("THC:: DOMAINPANEL::", feature)
    print("THC:: DOMAINPANEL::", json(feature))

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
                element.data.itemCache[choice.id] = dmhub.GetTableVisible(DeityDomain.tableName)[choice.id]
            end

            for i = #element.children + 1, numChoices do
                element:AddChild(CBFeatureSelector._targetPanel{ feature = feature, itemIndex = i })
            end
        end,
    }

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(CBFeatureSelector._optionPanel({
                    feature = feature,
                    itemIsSelected = function(state, featureGuid, item)
                        local hero = _getHero(state)
                        if hero then
                            local levelChoices = hero:GetLevelChoices()
                            if levelChoices then
                                local selectedItems = levelChoices[featureGuid]
                                if selectedItems then
                                    for _, selectedId in ipairs(selectedItems) do
                                        return selectedId == item.id
                                    end
                                end
                            end
                        end
                        return false
                    end,
                }))
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, child in ipairs(element.children) do
                local choice = currentChoices[i]
                child:FireEvent("assignItem", choice and dmhub.GetTable(DeityDomain.tableName)[choice.id] or nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel{
        feature = feature,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
    }
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
                element:AddChild(CBFeatureSelector._targetPanel({
                    feature = feature,
                    itemIndex = i,
                    useDesc = true,
                    idFieldName = "guid",
                    formatName = formatOptionName,
                }))
            end
        end,
    }

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentOptions = feature:GetOptions(levelChoices)

            local numOptions = #currentOptions

            for _ = #element.children + 1, numOptions do
                element:AddChild(CBFeatureSelector._optionPanel({
                    feature = feature,
                    idFieldName = "guid",
                    useDesc = true,
                    formatName = formatOptionName,
                    itemIsSelected = function(state, featureGuid, item)
                        local hero = _getHero(state)
                        if hero then
                            return _characterHasLevelChoice(hero, featureGuid, item.guid)
                        end
                    end,
                }))
            end

            table.sort(currentOptions, function(a, b) return a.name < b.name end)

            for i, child in ipairs(element.children) do
                child:FireEvent("assignItem", currentOptions[i])
            end
        end,
    }

    return CBFeatureSelector._mainPanel{
        feature = feature,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
    }
end

--- Render a roll table panel
--- @param feature CharacterIncidentChoice
--- @return Panel
function CBFeatureSelector.IncidentPanel(feature)

    -- Special case - these aren't stored in levelChoices.
    local function applyCurrentItem(element)
        -- Runs in the context of the main feature container
        local hero = _getHero(element)
        if not hero then return end

        local data = element.data
        hero:RemoveNotesForTable(data.feature.guid)
        local noteItem = hero:GetOrAddNoteForTableRow(data.feature.guid, data.selectedId)
        if noteItem then
            noteItem.title = data.feature.name
            for _,o in ipairs(data.feature.options) do
                if o.guid == data.selectedId then
                    noteItem.text = o.row.value:ToString()
                    break
                end
            end
        end
    end
    local function selectedItem(element, hero)
        -- Runs in the context of a target panel
        local notes = hero:GetNotesForTable(element.data.featureGuid)
        if notes and #notes > 0 then
            local itemCache = element.parent.data.itemCache or {}
            return itemCache[notes[1].rowid]
        end
        return nil
    end
    local function unselectItem(element)
        -- Runs in the context of a target panel
        local hero = _getHero(element)
        if hero then
            local data = element.data
            hero:RemoveNoteForTableRow(data.featureGuid, data.item.guid)
        end
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
                element:AddChild(CBFeatureSelector._targetPanel{
                    feature = feature,
                    itemIndex = i,
                    useDesc = true,
                    idFieldName = "guid",
                    selectedItem = selectedItem,
                    unselectItem = unselectItem,
                })
            end
        end,
    }

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentOptions = feature:GetOptions(levelChoices)

            local numOptions = #currentOptions

            for _ = #element.children + 1, numOptions do
                element:AddChild(CBFeatureSelector._optionPanel{
                    feature = feature,
                    idFieldName = "guid",
                    useDesc = true,
                    itemIsSelected = function(state, featureGuid, item)
                        local hero = _getHero(state)
                        if hero then
                            return hero:GetNoteForTableRow(featureGuid, item.guid) ~= nil
                        end
                    end,
                })
            end

            table.sort(currentOptions, function(a, b) return a.name < b.name end)

            for i, child in ipairs(element.children) do
                child:FireEvent("assignItem", currentOptions[i])
            end
        end,
    }

    local mainPanel = CBFeatureSelector._mainPanel{
        feature = feature,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
        applyCurrentItem = applyCurrentItem,
    }

    local rollTable = feature.characteristic:GetRollTable()
    local rollInfo = rollTable:CalculateRollInfo()
    local faces = CharacterBuilder._validateRollFaces(rollInfo.rollFaces)
    local dice = gui.UserDice{
        floating = true,
        halign = "left",
        valign = "bottom",
        hmargin = CBStyles.SIZES.SELECT_BUTTON_HEIGHT,
        vmargin = -8,
        width = CBStyles.SIZES.SELECT_BUTTON_HEIGHT,
        height = CBStyles.SIZES.SELECT_BUTTON_HEIGHT,
        faces = faces,
        click = function(element)
            local hero = _getHero(element)
            if hero == nil then return end
            element:SetClass("collapsed-anim", true)
            dmhub.Roll{
                roll = rollInfo.roll,
                description = string.format(feature.name),
                tokenid = dmhub.LookupTokenId(hero),
                begin = function(rollInfo)

                end,
                complete = function(rollInfo)
                    local rowIndex = rollTable:RowIndexFromDiceResult(rollInfo.total)
                    if rowIndex == nil then return end

                    local row = rollTable.rows[rowIndex]
                    element.parent:FireEvent("selectItem", row.id)
                    element.parent:FireEvent("applyCurrentItem")

                    element:SetClass("collapsed-anim", false)
                end,
            }
        end,
    }

    mainPanel:AddChild(dice)

    return mainPanel
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
                element:AddChild(CBFeatureSelector._targetPanel({ feature = feature, itemIndex = i }))
            end
        end,
    }

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(CBFeatureSelector._optionPanel({
                    feature = feature,
                    itemIsSelected = function(state, featureGuid, item)
                        local hero = _getHero(state)
                        if hero then
                            local langsKnown = hero:LanguagesKnown()
                            return langsKnown and langsKnown[item.id]
                        end
                    end,
                }))
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, child in ipairs(element.children) do
                local choice = currentChoices[i]
                child:FireEvent("assignItem", choice and dmhub.GetTableVisible(Language.tableName)[choice.id] or nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel{
        feature = feature,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
    }
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
                element:AddChild(CBFeatureSelector._targetPanel({ feature = feature, itemIndex = i, useDesc = true }))
            end
        end,
    }

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(CBFeatureSelector._optionPanel({
                    feature = feature,
                    useDesc = true,
                    formatName = function(item) return item.name end,
                    itemIsSelected = function(state, featureGuid, item)
                        local cachedPerks = state:Get("cachedPerks")
                        return cachedPerks and cachedPerks[item.id]
                    end,
                }))
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, child in ipairs(element.children) do
                local choice = currentChoices[i]
                child:FireEvent("assignItem", choice and dmhub.GetTableVisible(CharacterFeat.tableName)[choice.id] or nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel{
        feature = feature,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
    }
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
                element:AddChild(CBFeatureSelector._targetPanel({ feature = feature, itemIndex = i }))
            end
        end,
    }

    local optionsContainer = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            if not hero then return end

            local levelChoices = hero:GetLevelChoices()
            local currentChoices = feature:Choices(nil, levelChoices, hero)

            local numOptions = #currentChoices

            for _ = #element.children + 1, numOptions do
                element:AddChild(CBFeatureSelector._optionPanel{
                    feature = feature,
                    itemIsSelected = function(state, featureGuid, item)
                        local hero = _getHero(state)
                        return hero and hero:ProficientInSkill(item)
                    end,
                })
            end

            table.sort(currentChoices, function(a, b) return a.text < b.text end)

            for i, child in ipairs(element.children) do
                local choice = currentChoices[i]
                child:FireEvent("assignItem", choice and dmhub.GetTableVisible(Skill.tableName)[choice.id] or nil)
            end
        end,
    }

    return CBFeatureSelector._mainPanel{
        feature = feature,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
    }
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

--- Build a consistent main panel
--- @param options table Configuration: feature, targetsContainer, optionsContainer, applyCurrentItem
--- @return Panel
function CBFeatureSelector._mainPanel(options)
    local feature = options.feature
    local targetsContainer = options.targetsContainer
    local optionsContainer = options.optionsContainer
    local onApplyCurrentItem = options.applyCurrentItem

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
                if onApplyCurrentItem then onApplyCurrentItem(element) end
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

--- Create an option panel for a feature choice
--- @param options table Configuration: feature, idFieldName, useDesc, formatName, itemIsSelected
--- @return Panel
function CBFeatureSelector._optionPanel(options)
    local feature = options.feature
    local idFieldName = options.idFieldName or "id"
    local useDesc = options.useDesc or false
    local formatName = options.formatName or function(item) return item.name or item.text end
    local itemIsSelected = options.itemIsSelected

    return gui.Panel{
        classes = {"builder-base", "panel-base", "feature-choice"},
        valign = "top",
        data = {
            featureGuid = feature.guid,
            item = nil,
            useDesc = useDesc,
        },
        assignItem = function(element, item)
            element.data.item = item
        end,
        click = function(element)
            if not element.data.item then return end
            local parent = element:FindParentWithClass("featureSelector")
            if parent then
                parent:FireEvent("selectItem", element.data.item[idFieldName])
            end
        end,
        refreshBuilderState = function(element, state)
            local item = element.data.item
            local visible = item ~= nil and (item:try_get("unique", true) == false or not itemIsSelected(state, element.data.featureGuid, item))
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end
            element:FireEventTree("updateName", formatName(item))
            if element.data.useDesc then
                element:FireEventTree("updateDesc", item.description or "")
            end
        end,
        refreshSelection = function(element, selectedId)
            element:SetClass("selected", element.data.item and selectedId == element.data.item[idFieldName])
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

--- Create a target panel for a feature
--- @param config table Configuration: feature, itemIndex, useDesc, idFieldName, formatName, unselectItem
--- @return Panel
function CBFeatureSelector._targetPanel(config)
    local feature = config.feature
    local itemIndex = config.itemIndex
    local useDesc = config.useDesc or false
    local costsPoints = feature:try_get("costsPoints", false)
    local idFieldName = config.idFieldName or "id"
    local formatName = config.formatName or function(item) return item:try_get("name") end
    local selectedItem = config.selectedItem or function(element, hero)
        local levelChoices = hero:GetLevelChoices()
        if levelChoices then
            local selectedItems = levelChoices[element.data.featureGuid]
            if selectedItems and #selectedItems >= element.data.itemIndex then
                local selectedId = selectedItems[element.data.itemIndex]
                if selectedId then
                    local itemCache = element.parent.data.itemCache or {}
                    return itemCache[selectedId]
                end
            end
        end
    end
    local onUnselectItem = config.unselectItem

    return gui.Panel{
        classes = {"builder-base", "panel-base", "feature-target", "empty"},
        data = {
            featureGuid = feature:try_get("guid", feature:try_get("tableid")),
            costsPoints = costsPoints,
            itemIndex = itemIndex,
            item = nil,
            useDesc = useDesc,
        },
        click = function(element)
            if not element.data.item then return end
            if onUnselectItem then onUnselectItem(element) end
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
            if hero then item = selectedItem(element, hero) end

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
