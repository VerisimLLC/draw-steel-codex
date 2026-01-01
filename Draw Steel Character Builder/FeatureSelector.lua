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
]]
CBFeatureSelector = RegisterGameType("CBFeatureSelector")

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

    -- Build selectButton
    local selectButtonDef = _mergeKeyedTables({
        data = {},
    }, overrides.selectButton)
    local selectButton = overrides.selectButton and CharacterBuilder._makeSelectButton(selectButtonDef)

    local scrollPanel = gui.Panel{
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
            targetsContainer,
            _functionOrValue(injections.afterTargets),
            gui.MCDMDivider{
                classes = {"builder-divider"},
                layout = "v",
                width = "96%",
                vpad = 4,
                bgcolor = CBStyles.COLORS.GOLD,
            },
            _functionOrValue(injections.beforeOptions),
            optionsContainer,
            _functionOrValue(injections.afterOptions),
        },
    }

    local bottomDivider = gui.MCDMDivider{
        classes = {"builder-divider"},
        layout = "line",
        width = "96%",
        vpad = 4,
        bgcolor = "white"
    }

    -- Build children array
    local children = { scrollPanel, bottomDivider, selectButton }
    table.move(extraChildren, 1, #extraChildren, #children + 1, children)

    -- Build mainPanel - merge but protect children
    local mainPanelDef = _mergeKeyedTables({
        classes = {controllerClass, "builder-base", "panel-base"},
        width = "100%",
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
            click = function(element)
                if not element.data.option then return end

                -- Remove the item
                local state = _getState(element)
                if state then
                    local hero = _getHero(state)
                    local cachedFeature = getCachedFeature(state, element.data.featureId)
                    if cachedFeature and hero then
                        if cachedFeature:RemoveSelection(hero, element.data.option) then
                            _fireControllerEvent(element, "tokenDataChanged")
                            return
                        end
                    end
                end
            end,
            dehover = function(element)
                element:FireEventTree("onDeHover")
            end,
            hover = function(element)
                element:FireEventTree("onHover")
            end,
            linger = function(element)
                if element.data.option then
                    gui.Tooltip("Press to delete")(element)
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
                if option and cachedFeature then
                    local choice = cachedFeature:GetChoice(option:GetGuid())
                    element:FireEventTree("customPanel", choice and choice:Panel())
                end
                element:SetClass("filled", option ~= nil)
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
                onDeHover = function(element)
                    element:SetClass("collapsed-anim", true)
                end,
                onHover = function(element)
                    local visible = element.data.panelFn ~= nil and element.parent:HasClass("filled")
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
            assignItem = function(element, option)
                element.data.option = option
            end,
            click = function(element)
                if element.data.option == nil then return end
                local controller = getFeatureSelController(element)
                if controller then
                    controller:FireEvent("selectItem", element.data.option:GetGuid())
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
        },
        click = function(element)
            local controller = getFeatureSelController(element)
            if controller then
                controller:FireEvent("applyCurrentItem")
            end
        end,
        refreshBuilderState = function(element, state)
            local visible = false
            local enabled = false
            local cachedFeature = getCachedFeature(state, element.data.featureId)
            if cachedFeature then
                visible = true
                enabled = cachedFeature:AllowCurrentSelection()
            end
            element:SetClass("collapsed", not visible)
            element:SetClass("disabled", not enabled)
            element.interactable = visible and enabled
        end,
    }

    local mainPanel = {
        data = {
            featureId = feature:GetGuid(),
        },
        applyCurrentItem = function(element)
            local state = _getState(element)
            if state then
                local cachedFeature = getCachedFeature(state, element.data.featureId)
                if cachedFeature then
                    local selectedOption = cachedFeature:GetSelectedOption()
                    if selectedOption then

                        -- Save it via the feature wrapper
                        local hero = _getHero(state)
                        if hero then
                            if cachedFeature:SaveSelection(hero, selectedOption) then
                                _fireControllerEvent(element, "tokenDataChanged")
                                return
                            end
                        end
                    end
                end
            end
        end,
        selectItem = function(element, itemId)
            local state = _getState(element)
            if state then
                local cachedFeature = getCachedFeature(state, element.data.featureId)
                if cachedFeature then
                    if cachedFeature:SetSelectedOption(itemId) then
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
            click = function(element)
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
                        element.parent:FireEvent("selectItem", row.id)
                        element.parent:FireEvent("applyCurrentItem")

                        element:SetClass("collapsed-anim", false)
                    end,
                }
            end,
        }
    end

    return CBFeatureSelector.BuildSelectorPanel{
        controllerClass = controllerClass,
        header = header,
        targetsContainer = targetsContainer,
        optionsContainer = optionsContainer,
        selectButton = selectButton,
        mainPanel = mainPanel,
        extraChildren = roller and { roller } or {},
        injections = feature:UIInjections(),
    }
end