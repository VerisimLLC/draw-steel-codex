--[[
    Selectors - managing the options on the left side of the builder
]]
CBSelectors = RegisterGameType("CBSelectors")

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getCreature = CharacterBuilder._getCreature
local _getState = CharacterBuilder._getState

--- Creates a panel of selectable item buttons that expands when its selector is active.
--- Items must have `id` and `name` fields.
--- @param config {items: table[], selectorName: string, getSelected: fun(creature): table|nil, getItem: fun(id): table|nil}
--- @return Panel
function CBSelectors._makeItemsPanel(config)
    local selectorPanel
    local buttons = {}

    for _,item in ipairs(config.items) do
        buttons[#buttons+1] = gui.SelectorButton{
            classes = {"builder-base", "button", "category"},
            width = CBStyles.SIZES.SELECTOR_BUTTON_WIDTH,
            height = CBStyles.SIZES.SELECTOR_BUTTON_HEIGHT,
            valign = "top",
            tmargin = CBStyles.SIZES.BUTTON_SPACING,
            bmargin = 0,
            text = item.name,
            data = { id = item.id },
            available = true,

            create = function(element)
                element:FireEvent("refreshBuilderState", _getState(element))
            end,

            click = function(element)
                _fireControllerEvent(element, "selectItem", {
                    selector = config.selectorName,
                    id = element.data.id,
                })
            end,

            refreshBuilderState = function(element, state)
                local creature = _getCreature(state)
                if creature then
                    local tokenSelected = config.getSelected(creature)
                    element:SetClass("collapsed", tokenSelected and tokenSelected ~= element.data.id)
                    element:FireEvent("setAvailable", not tokenSelected or tokenSelected == element.data.id)
                    if tokenSelected and tokenSelected == element.data.id and tokenSelected ~= state:Get(config.selectorName .. ".selectedId") then
                        element:FireEvent("click")
                    end
                end
                element:FireEvent("setSelected", state:Get(config.selectorName .. ".selectedId") == element.data.id)
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
function CBSelectors._ancestryItems()
    return CBSelectors._makeItemsPanel{
        items = CharacterBuilder._sortArrayByProperty(CharacterBuilder._toArray(dmhub.GetTableVisible(Race.tableName)), "name"),
        selectorName = "ancestry",
        getSelected = function(creature)
            return creature:try_get("raceid")
        end,
        getItem = function(id)
            return dmhub.GetTableVisible(Race.tableName)[id]
        end,
    }
end

--- @return Panel Career selector panel
function CBSelectors._careerItems()
    return CBSelectors._makeItemsPanel{
        items = CharacterBuilder._sortArrayByProperty(CharacterBuilder._toArray(dmhub.GetTableVisible(Background.tableName)), "name"),
        selectorName = "career",
        getSelected = function(creature)
            return creature:try_get("backgroundid")
        end,
        getItem = function(id)
            return dmhub.GetTableVisible(Background.tableName)[id]
        end,
    }
end

--- @return Panel Class selector panel
function CBSelectors._classItems()
    return CBSelectors._makeItemsPanel{
        items = CharacterBuilder._sortArrayByProperty(CharacterBuilder._toArray(dmhub.GetTableVisible(Class.tableName)), "name"),
        selectorName = "class",
        getSelected = function(creature)
            local c = creature:GetClass()
            return c and c.id or nil
        end,
        getItem = function(id)
            return dmhub.GetTableVisible(Class.tableName)[id]
        end,
    }
end

--- @return Panel Culture category selector panel
function CBSelectors._cultureItems()
    local cultureCats = dmhub.DeepCopy(CultureAspect.categories)
    for _,item in ipairs(cultureCats) do
        item.name = item.text
    end
    return CBSelectors._makeItemsPanel{
        items = CharacterBuilder._sortArrayByProperty(cultureCats, "name"),
        selectorName = "culture",
        getSelected = function(creature) return nil end,
    }
end

--- Creates the main selectors panel containing all registered selectors.
--- @return Panel
function CBSelectors.CreatePanel()

    local selectors = {}
    for _,selector in ipairs(CharacterBuilder.Selectors) do
        selectors[#selectors+1] = selector.selector()
    end

    local selectorsPanel = gui.Panel{
        classes = {"selectorsPanel", "builder-base", "panel-base"},
        width = CBStyles.SIZES.BUTTON_PANEL_WIDTH,
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
function CBSelectors._makeButton(options)
    options.valign = "top"
    options.tmargin = CBStyles.SIZES.BUTTON_SPACING
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
function CBSelectors._makeDetailed(config)
    local selectorButton = CBSelectors._makeButton{
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
function CBSelectors._back()
    return CBSelectors._makeButton{
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
function CBSelectors._character()
    return CBSelectors._makeButton{
        text = "Character",
        data = { selector = "character" },
    }
end

--- @return Panel Ancestry selector with detail panel
function CBSelectors._ancestry()
    return CBSelectors._makeDetailed{
        text = "Ancestry",
        selectorName = "ancestry",
        createChoicesPane = CBSelectors._ancestryItems,
    }
end

--- @return Panel Culture selector with detail panel
function CBSelectors._culture()
    return CBSelectors._makeDetailed{
        text = "Culture",
        selectorName = "culture",
        createChoicesPane = CBSelectors._cultureItems,
    }
end

--- @return Panel Career selector with detail panel
function CBSelectors._career()
    return CBSelectors._makeDetailed{
        text = "Career",
        selectorName = "career",
        createChoicesPane = CBSelectors._careerItems,
    }
end

--- @return Panel Class selector with detail panel
function CBSelectors._class()
    return CBSelectors._makeDetailed{
        text = "Class",
        selectorName = "class",
        createChoicesPane = CBSelectors._classItems,
    }
end

--- @return ActionButton Kit selector button
function CBSelectors._kit()
    return CBSelectors._makeButton{
        text = "Kit",
        data = { selector = "kit" },
        refreshBuilderState = function(element, state)
            local c = _getCreature(state)
            element:SetClass("collapsed", not c or not c:IsHero() or not c:CanHaveKits() )
        end,
    }
end

--- @return ActionButton Complication selector button
function CBSelectors._complication()
    return CBSelectors._makeButton{
        text = "Complication",
        data = { selector = "complication" },
    }
end

CharacterBuilder.RegisterSelector{
    id = "back",
    ord = 1,
    selector = CBSelectors._back
}

CharacterBuilder.RegisterSelector{
    id = "character",
    ord = 2,
    selector = CBSelectors._character,
    detail = CBDescriptionDetail.CreatePanel,
}

CharacterBuilder.RegisterSelector{
    id = "ancestry",
    ord = 3,
    selector = CBSelectors._ancestry,
    detail = CBAncestryDetail.CreatePanel,
}

CharacterBuilder.RegisterSelector{
    id = "culture",
    ord = 4,
    selector = CBSelectors._culture
}

CharacterBuilder.RegisterSelector{
    id = "career",
    ord = 5,
    selector = CBSelectors._career,
    detail = CBCareerDetail.CreatePanel
}

CharacterBuilder.RegisterSelector{
    id = "class",
    ord = 6,
    selector = CBSelectors._class
}

CharacterBuilder.RegisterSelector{
    id = "kit",
    ord = 7,
    selector = CBSelectors._kit
}

CharacterBuilder.RegisterSelector{
    id = "complication",
    ord = 8,
    selector = CBSelectors._complication
}
