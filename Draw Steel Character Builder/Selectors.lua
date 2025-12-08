--[[
    Selectors - managing the options on the left side of the builder
]]

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getCreature = CharacterBuilder._getCreature
local _getToken = CharacterBuilder._getToken

--- Creates a panel of selectable item buttons that expands when its selector is active.
--- Items must have `id` and `name` fields.
--- @param config {items: table[], selectorName: string, getSelected: fun(creature): table|nil}
--- @return Panel
function CharacterBuilder._createDetailedSelectorPanel(config)
    local selectorPanel
    local buttons = {}

    for _,item in ipairs(config.items) do
        buttons[#buttons+1] = gui.SelectorButton{
            classes = {"builder-base", "button", "category"},
            width = CharacterBuilder.SIZES.SELECTOR_BUTTON_WIDTH,
            height = CharacterBuilder.SIZES.SELECTOR_BUTTON_HEIGHT,
            valign = "top",
            tmargin = CharacterBuilder.SIZES.BUTTON_SPACING,
            bmargin = 0,
            text = item.name,
            data = { id = item.id },
            available = true,
            create = function(element)
                element:FireEvent("refreshToken")
            end,
            refreshBuilderState = function(element, state)
                if state then
                    element:FireEvent("setSelected", state:Get(config.selectorName .. ".selectedId") == element.data.id)
                end
            end,
            refreshToken = function(element)
                local creature = _getCreature(element)
                if creature then
                    local selected = config.getSelected(creature)
                    element:FireEvent("setAvailable", not selected or selected == element.data.id)
                    element:FireEvent("setSelected", selected == element.data.id)
                    element:SetClass("collapsed", selected and selected ~= element.data.id)
                    if selected and selected == element.data.id then
                        element:FireEvent("click")
                    end
                end
            end,
            click = function(element)
                _fireControllerEvent(element, "updateState", {
                    key = config.selectorName .. ".selectedId",
                    value = element.data.id
                })
            end,
        }
    end

    selectorPanel = gui.Panel {
        classes = {"collapsed"},
        width = "90%",
        height = "auto",
        valign = "top",
        halign = "right",
        flow = "vertical",
        data = { selector = config.selectorName },
        refreshBuilderState = function(element, state)
            element:SetClass("collapsed", state:Get("activeSelector") ~= element.data.selector)
        end,
        children = buttons,
    }

    return selectorPanel
end

--- @return Panel Ancestry selector panel
function CharacterBuilder._ancestrySelectorPanel()
    return CharacterBuilder._createDetailedSelectorPanel{
        items = CharacterBuilder._sortArrayByProperty(CharacterBuilder._toArray(dmhub.GetTableVisible(Race.tableName)), "name"),
        selectorName = "ancestry",
        getSelected = function(creature) return creature:try_get("raceid") end,
    }
end

--- @return Panel Career selector panel
function CharacterBuilder._careerSelectorPanel()
    return CharacterBuilder._createDetailedSelectorPanel{
        items = CharacterBuilder._sortArrayByProperty(CharacterBuilder._toArray(dmhub.GetTableVisible(Background.tableName)), "name"),
        selectorName = "career",
        getSelected = function(creature)
            local bg = creature:Background()
            return bg and bg.id or nil
        end,
    }
end

--- @return Panel Class selector panel
function CharacterBuilder._classSelectorPanel()
    return CharacterBuilder._createDetailedSelectorPanel{
        items = CharacterBuilder._sortArrayByProperty(CharacterBuilder._toArray(dmhub.GetTableVisible(Class.tableName)), "name"),
        selectorName = "class",
        getSelected = function(creature)
            local c = creature:GetClass()
            return c and c.id or nil
        end,
    }
end

--- @return Panel Culture category selector panel
function CharacterBuilder._cultureSelectorPanel()
    local cultureCats = dmhub.DeepCopy(CultureAspect.categories)
    for _,item in ipairs(cultureCats) do
        item.name = item.text
    end
    return CharacterBuilder._createDetailedSelectorPanel{
        items = CharacterBuilder._sortArrayByProperty(cultureCats, "name"),
        selectorName = "culture",
        getSelected = function(creature) return nil end,
    }
end

--- Creates the main selectors panel containing all registered selectors.
--- @return Panel
function CharacterBuilder._selectorsPanel()

    local selectors = {}
    for _,selector in ipairs(CharacterBuilder.Selectors) do
        selectors[#selectors+1] = selector.selector()
    end

    local selectorsPanel = gui.Panel{
        classes = {"selectorsPanel", "builder-base", "panel-base"},
        width = CharacterBuilder.SIZES.BUTTON_PANEL_WIDTH,
        height = "99%",
        halign = "left",
        valign = "top",
        flow = "vertical",
        vscroll = true,
        borderColor = "blue",
        data = {
            activeSelector = "",
        },

        selectorClick = function(element, selector)
            if element.data.activeSelector ~= selector then
                element.data.activeSelector = selector
                _fireControllerEvent(element, "selectorChange", selector)
            end
        end,

        children = selectors,
    }

    return selectorsPanel
end

--- Factory for selector buttons with default event handlers.
--- @param options table Button options; must include `data.selector`
--- @return ActionButton
function CharacterBuilder._makeSelectorButton(options)
    options.valign = "top"
    options.tmargin = CharacterBuilder.SIZES.BUTTON_SPACING
    options.available = true
    if options.click == nil then
        options.click = function(element)
            local selectorsPanel = element:FindParentWithClass("selectorsPanel")
            if selectorsPanel then
                selectorsPanel:FireEvent("selectorClick", element.data.selector)
            end
        end
    end
    if options.refreshBuilderState == nil then
        options.refreshBuilderState = function(element, state)
            element:FireEvent("setSelected", state:Get("activeSelector") == element.data.selector)
        end
    end
    return gui.ActionButton(options)
end

--- Creates a selector button that lazily loads a detail panel when selected.
--- @param config {text: string, selectorName: string, createChoicesPane: fun(): Panel}
--- @return Panel
function CharacterBuilder._createDetailedSelector(config)
    local selectorButton = CharacterBuilder._makeSelectorButton{
        text = config.text,
        data = { selector = config.selectorName },
        refreshBuilderState = function(element, state)
            local selfSelected = state:Get("activeSelector") == element.data.selector
            local parentPane = element:FindParentWithClass(config.selectorName .. "-selector")
            if parentPane then
                element:FireEvent("setSelected", selfSelected)
                parentPane:FireEvent("showDetail", selfSelected)
            end
        end,
    }

    local selector = gui.Panel{
        classes = {config.selectorName .. "-selector"},
        width = "100%",
        height = "auto",
        pad = 0,
        margin = 0,
        flow = "vertical",
        data = { choicesPane = nil },

        showDetail = function(element, show)
            if show then
                if not element.data.choicesPane then
                    element.data.choicesPane = config.createChoicesPane()
                    element:AddChild(element.data.choicesPane)
                end
            end
            if element.data.choicesPane then
                element.data.choicesPane:SetClass("collapsed", not show)
            end
        end,

        children = {
            selectorButton
        },
    }

    return selector
end

--- @return ActionButton Back button (hidden when in CharSheet)
function CharacterBuilder._backSelector()
    return CharacterBuilder._makeSelectorButton{
        text = "BACK",
        data = { selector = "back" },
        create = function(element)
            element:SetClass("collapsed", CharacterBuilder._inCharSheet(element))
        end,
        click = function(element)
            print("THC:: TODO:: Not in CharSheet. Close the window, probably?")
        end,
    }
end

--- @return ActionButton Character selector button
function CharacterBuilder._characterSelector()
    return CharacterBuilder._makeSelectorButton{
        text = "Character",
        data = { selector = "character" },
    }
end

--- @return Panel Ancestry selector with detail panel
function CharacterBuilder._ancestrySelector()
    return CharacterBuilder._createDetailedSelector{
        text = "Ancestry",
        selectorName = "ancestry",
        createChoicesPane = CharacterBuilder._ancestrySelectorPanel,
    }
end

--- @return Panel Culture selector with detail panel
function CharacterBuilder._cultureSelector()
    return CharacterBuilder._createDetailedSelector{
        text = "Culture",
        selectorName = "culture",
        createChoicesPane = CharacterBuilder._cultureSelectorPanel,
    }
end

--- @return Panel Career selector with detail panel
function CharacterBuilder._careerSelector()
    return CharacterBuilder._createDetailedSelector{
        text = "Career",
        selectorName = "career",
        createChoicesPane = CharacterBuilder._careerSelectorPanel,
    }
end

--- @return Panel Class selector with detail panel
function CharacterBuilder._classSelector()
    return CharacterBuilder._createDetailedSelector{
        text = "Class",
        selectorName = "class",
        createChoicesPane = CharacterBuilder._classSelectorPanel,
    }
end

--- @return ActionButton Kit selector button
function CharacterBuilder._kitSelector()
    return CharacterBuilder._makeSelectorButton{
        text = "Kit",
        data = { selector = "kit" },
        refreshToken = function(element)
            local c = _getCreature(element)
            element:SetClass("collapsed", not c or not c:IsHero() or not c:CanHaveKits() )
        end,
    }
end

--- @return ActionButton Complication selector button
function CharacterBuilder._complicationSelector()
    return CharacterBuilder._makeSelectorButton{
        text = "Complication",
        data = { selector = "complication" },
    }
end

CharacterBuilder.RegisterSelector{
    id = "back",
    ord = 1,
    selector = CharacterBuilder._backSelector
}

CharacterBuilder.RegisterSelector{
    id = "character",
    ord = 2,
    selector = CharacterBuilder._characterSelector
}

CharacterBuilder.RegisterSelector{
    id = "ancestry",
    ord = 3,
    selector = CharacterBuilder._ancestrySelector,
    detail = CharacterBuilder._ancestryDetail,
}

CharacterBuilder.RegisterSelector{
    id = "culture",
    ord = 4,
    selector = CharacterBuilder._cultureSelector
}

CharacterBuilder.RegisterSelector{
    id = "career",
    ord = 5,
    selector = CharacterBuilder._careerSelector
}

CharacterBuilder.RegisterSelector{
    id = "class",
    ord = 6,
    selector = CharacterBuilder._classSelector
}

CharacterBuilder.RegisterSelector{
    id = "kit",
    ord = 7,
    selector = CharacterBuilder._kitSelector
}

CharacterBuilder.RegisterSelector{
    id = "complication",
    ord = 8,
    selector = CharacterBuilder._complicationSelector
}
