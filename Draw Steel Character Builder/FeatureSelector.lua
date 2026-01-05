--[[
    The UI in which the user selects pretty much any
    type of feature - skills, languages, really anything
    derived from CharacterChoice.

    Anything derived from CharacterChoice should plug in
    to SelectionPanel() automagically, if you ensure you
    follow the guidelines:
      - Implement :GetDescription()
      - Implement :GetOptions()
      - Implement :Choices()
      - Name the class Character___Choice or update the
        translation list in _deriveCategory in
        FeatureCache.lua.
      - Add it to the sort order list in _deriveOrder in
        FeatureCache.lua.
      - If selections aren't stored in levelChoices, implement
        SaveSelection and RemoveSelection on the feature class.
      - Your feature class can also inject custom UI at certain
        points in the UI. The injection can be any descendant of
        gui.Panel or a function that returns the same. Valid
        injection keys are:
        - afterHeader
        - afterTargets
        - beforeOptions
        - afterOptions
        - extraChildren (an array)
]]
CBFeatureSelector = RegisterGameType("CBFeatureSelector")

local SELECT_MODES = {SELECT = "SELECT", REMOVE = "REMOVE"}

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _functionOrValue = CharacterBuilder._functionOrValue
local _getHero = CharacterBuilder._getHero
local _getState = CharacterBuilder._getState
local _mergeKeyedTables = CharacterBuilder._mergeKeyedTables

--- Build a selector panel with customizable components
--- @param overrides table Optional overrides for panel components
--- @return Panel
function CBFeatureSelector.BuildSelectorPanel(overrides)
    overrides = overrides or {}

    local controllerClass = overrides.controllerClass or "featureSelector"
    local header = overrides.header or { name = "", description = "" }
    local extraChildren = overrides.extraChildren or {}
    local injections = overrides.injections or {}

    -- Merge extra children from injections
    for _,item in ipairs(injections.extraChildren or {}) do
        extraChildren[#extraChildren+1] = _functionOrValue(item)
    end

    -- Build targetsContainer
    local targetsContainerDef = _mergeKeyedTables({
        classes = {"builder-base", "panel-base", "container"},
        flow = "vertical",
        data = {},
    }, overrides.targetsContainer)
    local targetsContainer = overrides.targetsContainer and gui.Panel(targetsContainerDef)

    -- Build optionsContainer
    local optionsContainerDef = _mergeKeyedTables({
        classes = {"builder-base", "panel-base", "container"},
        data = {},
    }, overrides.optionsContainer)
    local optionsContainer = overrides.optionsContainer and gui.Panel(optionsContainerDef)

    local headerPanel = gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",
        gui.Label{
            classes = {"builder-base", "label", "feature-header", "name"},
            text = header.name,
            markdown = true,
            updateHeaderName = function(element, text)
                element.text = text
            end,
        },
        gui.Label{
            classes = {"builder-base", "label", "feature-header", "desc"},
            text = header.description,
            markdown = true,
            updateHeaderDesc = function(element, text)
                element.text = text
                element:SetClass("collapsed", element.text == nil or #element.text == 0)
            end,
        },
        _functionOrValue(injections.afterHeader),
    }

    local targetsPanel = gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "100%",
        height = "auto",
        halign = "left",
        valign = "top",
        flow = "vertical",
        targetsContainer,
        _functionOrValue(injections.afterTargets),
        gui.MCDMDivider{
            classes = {"builder-divider"},
            layout = "v",
            width = "100%",
            vpad = 4,
            bgcolor = CBStyles.COLORS.GOLD,
        },
    }

    local scrollPanel = gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "100%",
        height = "100%",
        halign = "left",
        valign = "top",
        flow = "vertical",
        vscroll = true,
        gui.Panel{
            classes = {"builder-base", "panel-base", "feature-choice-container"},
            optionsContainer,
        },
    }

    local optionsPanel = gui.Panel{
        classes = {"builder-base", "panel-base"},
        width = "100%",
        height = "100% available",
        flow = "vertical",
        _functionOrValue(injections.beforeOptions),
        scrollPanel,
        _functionOrValue(injections.afterOptions),
    }

    local bottomDivider = gui.MCDMDivider{
        classes = {"builder-divider"},
        layout = "line",
        width = "96%",
        vpad = 4,
        bgcolor = "white"
    }

    -- Build selectButton
    local selectButtonDef = _mergeKeyedTables({
        data = {},
    }, overrides.selectButton)
    local selectButton = overrides.selectButton and CharacterBuilder._makeSelectButton(selectButtonDef)

    -- Build children array
    local children = { headerPanel, targetsPanel, optionsPanel, bottomDivider, selectButton }
    table.move(extraChildren, 1, #extraChildren, #children + 1, children)

    -- Build mainPanel - merge but protect children
    local mainPanelDef = _mergeKeyedTables({
        classes = {controllerClass, "builder-base", "panel-base"},
        width = "98%",
        height = "100%",
        halign = "left",
        flow = "vertical",
        data = {},
    }, overrides.mainPanel)

    mainPanelDef.children = children

    return gui.Panel(mainPanelDef)
end

--- Render a feature choice panel
--- @param selector string The main selector we're operating under
--- @param feature CBFeatureWrapper
--- @return Panel
function CBFeatureSelector.SelectionPanel(selector, feature)

    local controllerClass = "featureSelector"
    local function getFeatureSelController(element)
        return element:FindParentWithClass(controllerClass)
    end

    local featureCacheKey = selector .. ".featureCache"
    local function getCachedFeature(state, featureId)
        local featureCache = state:Get(featureCacheKey)
        if featureCache then
            return featureCache:GetFeature(featureId)
        end
        return nil
    end

    local header = {
        name = feature:GetName(),
        description = feature:GetDescription(),
    }

    local targetPanel = function(featureId, itemIndex)
        return gui.Panel{
            classes = {"builder-base", "panel-base", "feature-target", "empty"},
            data = {
                featureId = featureId,
                itemIndex = itemIndex,
                option = nil,
            },
            press = function(element)
                if element.data.option == nil then return end
                local controller = getFeatureSelController(element)
                if controller then
                    controller:FireEvent("selectTarget", element.data.option:GetGuid())
                end
            end,
            refreshBuilderState = function(element, state)
                local cachedFeature = getCachedFeature(state, element.data.featureId)
                local visible = false

                if cachedFeature then
                    local optionId = cachedFeature:GetSelected()[element.data.itemIndex]
                    element.data.option = optionId and cachedFeature:GetOption(optionId) or nil
                    visible = element.data.option ~= nil or element.data.itemIndex <= cachedFeature:GetMaxVisibleTargets()
                end

                element:SetClass("collapsed", not visible)
                if not visible then
                    element:HaltEventPropagation()
                end

                local option = element.data.option
                local name = option and option:GetName() or "Empty Slot"
                if cachedFeature and option then
                    name = cachedFeature:GetOptionDisplayName(option)
                end
                element:FireEventTree("updateName", name)
                element:FireEventTree("updateDesc", option and option:GetDescription() or "")

                -- Workaround: Options never have panels but choices do.
                local isSelected = false
                if option and cachedFeature then
                    isSelected = cachedFeature:GetSelectedOptionId() == option:GetGuid()
                    local choice = cachedFeature:GetChoice(option:GetGuid())
                    element:FireEventTree("customPanel", choice and choice:Panel())
                end
                element:SetClass("filled", option ~= nil)
                element:SetClass("selected", isSelected)
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
                    element:SetClass("collapsed", #element.text == 0)
                end,
            },
            gui.Panel{
                classes = {"builder-base", "panel-base", "ability-card", "collapsed-anim"},
                width = "90%",
                height = "auto",
                halign = "center",
                valign = "top",
                data = {
                    panelFn = nil,
                },
                customPanel = function(element, panelFn)
                    if panelFn ~= element.data.panelFn then
                        for i = #element.children, 1, -1 do
                            element.children[i]:DestroySelf()
                        end
                        element.data.panelFn = panelFn
                    end
                    if element.data.panelFn then element:AddChild(element.data.panelFn()) end
                end,
                refreshBuilderState = function(element, state)
                    local visible = element.data.panelFn ~= nil and element.parent:HasClass("selected")
                    element:SetClass("collapsed-anim", not visible)
                end,
            }
        }
    end

    local targetsContainer = {
        data = {
            featureId = feature:GetGuid(),
        },
        refreshBuilderState = function(element, state)
            local cachedFeature = getCachedFeature(state, element.data.featureId)
            if cachedFeature == nil then return end
            local numTargets = cachedFeature:GetNumChoices()
            for i = #element.children + 1, numTargets do
                element:AddChild(targetPanel(element.data.featureId, i))
            end
        end,
    }

    local optionPanel = function(featureId)
        return gui.Panel{
            classes = {"builder-base", "panel-base", "feature-choice"},
            valign = "top",
            data = {
                featureId = featureId,
                option = nil,
            },
            applyFilter = function(element, filterText)
                if element.data.option == nil then return end
                local option = element.data.option
                local cachedFeature = getCachedFeature(_getState(element), element.data.featureId)
                local optionSelected = cachedFeature and cachedFeature:GetSelectedOptionId() == option:GetGuid()
                local filterMatch = optionSelected or CharacterBuilder._matchesFilter(filterText, option:GetName())
                element:SetClass("filtered", not filterMatch)
            end,
            assignItem = function(element, option)
                element.data.option = option
            end,
            press = function(element)
                if element.data.option == nil then return end
                local controller = getFeatureSelController(element)
                if controller then
                    controller:FireEvent("selectChoice", element.data.option:GetGuid())
                end
            end,
            refreshBuilderState = function(element, state)
                local option = element.data.option
                local visible = option ~= nil and (option:GetUnique() == false or option:GetSelected() == false)
                element:SetClass("collapsed", not visible)
                if not visible then
                    element:HaltEventPropagation()
                    return
                end
                local name = option:GetName()
                local cachedFeature = getCachedFeature(state, element.data.featureId)
                if cachedFeature then
                    name = cachedFeature:GetOptionDisplayName(option)
                    element:SetClass("selected", cachedFeature:GetSelectedOptionId() == option:GetGuid())
                end
                element:FireEventTree("updateName", name)
                element:FireEventTree("updateDesc", option:GetDescription())
                element:FireEventTree("customPanel", option:Panel())
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
                    element:SetClass("collapsed", #element.text == 0)
                end,
            },
            gui.Panel{
                classes = {"builder-base", "panel-base", "collapsed-anim"},
                width = "90%",
                height = "auto",
                halign = "center",
                valign = "top",
                data = {
                    panelFn = nil,
                },
                customPanel = function(element, panelFn)
                    if panelFn ~= element.data.panelFn then
                        for i = #element.children, 1, -1 do
                            element.children[i]:DestroySelf()
                        end
                        element.data.panelFn = panelFn
                    end
                    if element.data.panelFn then element:AddChild(element.data.panelFn()) end
                end,
                refreshBuilderState = function(element, state)
                    local visible = element.data.panelFn ~= nil and element.parent:HasClass("selected")
                    element:SetClass("collapsed-anim", not visible)
                end,
            }
        }
    end

    local optionsContainer = {
        data = {
            featureId = feature:GetGuid(),
        },
        refreshBuilderState = function(element, state)
            local cachedFeature = getCachedFeature(state, element.data.featureId)
            if cachedFeature == nil then return end
            local options = cachedFeature:GetChoices()
            if options == nil or #options == 0 then return end

            for _ = #element.children + 1, #options do
                element:AddChild(optionPanel(element.data.featureId))
            end

            for i, child in ipairs(element.children) do
                child:FireEventTree("assignItem", options[i])
            end
        end,
    }

    local selectButton = {
        data = {
            featureId = feature:GetGuid(),
            selectMode = SELECT_MODES.SELECT,
        },
        press = function(element)
            local controller = getFeatureSelController(element)
            if controller then
                controller:FireEvent("applyCurrentItem", element.data.selectMode)
            end
        end,
        refreshBuilderState = function(element, state)
            local mode = element.data.selectMode
            local visible = false
            local enabled = false
            local cachedFeature = getCachedFeature(state, element.data.featureId)
            if cachedFeature then
                visible = true
                enabled = SELECT_MODES[mode] ~= nil and (SELECT_MODES[mode] == SELECT_MODES.REMOVE or cachedFeature:AllowCurrentSelection())
            end
            element.text = string.upper(SELECT_MODES[mode] or "unknown mode")
            element:SetClass("collapsed", not visible)
            element:SetClass("disabled", not enabled)
            element.interactable = visible and enabled
        end,
        setSelectMode = function(element, mode)
            element.data.selectMode = mode
        end,
    }

    local mainPanel = {
        data = {
            featureId = feature:GetGuid(),
        },
        applyCurrentItem = function(element, mode)
            if SELECT_MODES[mode] == nil then return end
            local state = _getState(element)
            if state then
                local cachedFeature = getCachedFeature(state, element.data.featureId)
                if cachedFeature then
                    local selectedOption = cachedFeature:GetSelectedOption()
                    if selectedOption then
                        local hero = _getHero(state)
                        if hero then
                            local actionComplete = false
                            if mode == SELECT_MODES.REMOVE then
                                actionComplete = cachedFeature:RemoveSelection(hero, selectedOption)
                            else
                                actionComplete = cachedFeature:SaveSelection(hero, selectedOption)
                            end
                            if actionComplete then
                                _fireControllerEvent("tokenDataChanged")
                                return
                            end
                        end
                    end
                end
            end
        end,
        selectChoice = function(element, itemId)
            local state = _getState(element)
            if state then
                local cachedFeature = getCachedFeature(state, element.data.featureId)
                if cachedFeature then
                    if cachedFeature:SetSelectedOption(itemId) then
                        element:FireEventTree("setSelectMode", SELECT_MODES.SELECT)
                        element:FireEventTree("refreshBuilderState", state)
                    end
                end
            end
        end,
        selectTarget = function(element, itemId)
            local state = _getState(element)
            if state then
                local cachedFeature = getCachedFeature(state, element.data.featureId)
                if cachedFeature then
                    if cachedFeature:SetSelectedOption(itemId) then
                        element:FireEventTree("setSelectMode", SELECT_MODES.REMOVE)
                        element:FireEventTree("refreshBuilderState", state)
                    end
                end
            end
        end,
    }

    -- Build roller if feature has roll
    local roller = nil
    if feature:HasRoll() then
        local rollTable = feature:GetRollTable()
        local rollInfo = rollTable:CalculateRollInfo()
        local faces = CharacterBuilder._validateRollFaces(rollInfo.rollFaces)
        roller = gui.UserDice{
            floating = true,
            halign = "left",
            valign = "bottom",
            hmargin = CBStyles.SIZES.SELECT_BUTTON_HEIGHT,
            vmargin = -8,
            width = CBStyles.SIZES.SELECT_BUTTON_HEIGHT,
            height = CBStyles.SIZES.SELECT_BUTTON_HEIGHT,
            faces = faces,
            press = function(element)
                local hero = _getHero(element)
                if hero == nil then return end
                element:SetClass("collapsed-anim", true)
                dmhub.Roll{
                    roll = rollInfo.roll,
                    description = string.format(feature:GetName()),
                    tokenid = dmhub.LookupTokenId(hero),
                    complete = function(rollResult)
                        local rowIndex = rollTable:RowIndexFromDiceResult(rollResult.total)
                        if rowIndex == nil then return end

                        local row = rollTable.rows[rowIndex]
                        element.parent:FireEvent("selectChoice", row.id)
                        element.parent:FireEvent("applyCurrentItem", SELECT_MODES.SELECT)

                        element:SetClass("collapsed-anim", false)
                    end,
                }
            end,
        }
    end

    local injections = feature:UIInjections() or {}
    if feature:UIChoicesFilter() then
        local injectedBeforeOptions = injections.beforeOptions
        injections.beforeOptions = function()
            if injectedBeforeOptions ~= nil then _functionOrValue(injectedBeforeOptions) end
            return gui.Input{
                classes = {"builder-base", "input", "primary"},
                width = "94%",
                halign = "center",
                placeholderText = "Start typing to filter...",
                editlag = 0.5,
                data = {
                    featureId = feature:GetGuid()
                },
                edit = function(element)
                    element.parent:FireEventTreeVisible("applyFilter", element.text or "")
                end,
                refreshBuilderState = function(element, state)
                    local cachedFeature = getCachedFeature(state, element.data.featureId)
                    local numOptions = cachedFeature and feature:GetOptionsCount()
                    element:SetClass("collapsed", numOptions < CharacterBuilder.FILTER_VISIBLE_COUNT)
                end,
            }
        end
    end

    return CBFeatureSelector.BuildSelectorPanel{
        controllerClass = controllerClass,
        header = header,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
        selectButton = selectButton,
        mainPanel = mainPanel,
        extraChildren = roller and { roller } or {},
        injections = injections,
    }
end