--[[
    Selectors - managing the options on the left side of the builder
]]
CBSelectors = RegisterGameType("CBSelectors")

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getHero = CharacterBuilder._getHero
local _getState = CharacterBuilder._getState
local SEL = CharacterBuilder.SELECTOR

--- Creates a panel of selectable item buttons that expands when its selector is active.
--- Items must have `id` and `name` fields.
--- @param config {items: table[], selectorName: string, getSelected: fun(character): table|nil, getItem: fun(id): table|nil}
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
                local hero = _getHero(state)
                if hero then
                    local tokenSelected = config.getSelected(hero)
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
        classes = {"collapsed-anim"},
        width = "90%",
        height = "auto",
        valign = "top",
        halign = "right",
        flow = "vertical",
        data = { selector = config.selectorName },
        refreshBuilderState = function(element, state)
            local visible = state:Get("activeSelector") == element.data.selector
            element:SetClass("collapsed-anim", not visible)
            if not visible then
                element:HaltEventPropagation()
            end
        end,
        children = buttons,
    }

    return selectorPanel
end

--- @return Panel Ancestry selector panel
function CBSelectors._ancestryItems()
    return CBSelectors._makeItemsPanel{
        items = CharacterBuilder._sortArrayByProperty(CharacterBuilder._toArray(dmhub.GetTableVisible(Race.tableName)), "name"),
        selectorName = SEL.ANCESTRY,
        getSelected = function(hero)
            return hero:try_get("raceid")
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
        selectorName = SEL.CAREER,
        getSelected = function(hero)
            return hero:try_get("backgroundid")
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
        selectorName = SEL.CLASS,
        getSelected = function(hero)
            local c = hero:GetClass()
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
        selectorName = SEL.CULTURE,
        getSelected = function(hero) return nil end,
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
        data = { selector = SEL.BACK },
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
        data = { selector = SEL.CHARACTER },
    }
end

--- @return Panel Ancestry selector with detail panel
function CBSelectors._ancestry()
    return CBSelectors._makeDetailed{
        text = "Ancestry",
        selectorName = SEL.ANCESTRY,
        createChoicesPane = CBSelectors._ancestryItems,
    }
end

--- @return Panel Culture selector with detail panel
function CBSelectors._culture()
    return CBSelectors._makeDetailed{
        text = "Culture",
        selectorName = SEL.CULTURE,
        createChoicesPane = CBSelectors._cultureItems,
    }
end

--- @return Panel Career selector with detail panel
function CBSelectors._career()
    return CBSelectors._makeDetailed{
        text = "Career",
        selectorName = SEL.CAREER,
        createChoicesPane = CBSelectors._careerItems,
    }
end

--- @return Panel Class selector with detail panel
function CBSelectors._class()
    return CBSelectors._makeDetailed{
        text = "Class",
        selectorName = SEL.CLASS,
        createChoicesPane = CBSelectors._classItems,
    }
end

--- @return ActionButton Kit selector button
function CBSelectors._kit()
    return CBSelectors._makeButton{
        text = "Kit",
        data = { selector = SEL.KIT },
        refreshBuilderState = function(element, state)
            local hero = _getHero(state)
            element:SetClass("collapsed", not hero or not hero:CanHaveKits() )
        end,
    }
end

--- @return ActionButton Complication selector button
function CBSelectors._complication()
    return CBSelectors._makeButton{
        text = "Complication",
        data = { selector = SEL.COMPLICATION },
    }
end

CharacterBuilder.RegisterSelector{
    id = SEL.BACK,
    ord = 1,
    selector = CBSelectors._back
}

CharacterBuilder.RegisterSelector{
    id = SEL.CHARACTER,
    ord = 2,
    selector = CBSelectors._character,
    detail = CBDescriptionDetail.CreatePanel,
}

CharacterBuilder.RegisterSelector{
    id = SEL.ANCESTRY,
    ord = 3,
    selector = CBSelectors._ancestry,
    detail = CBAncestryDetail.CreatePanel,
}

CharacterBuilder.RegisterSelector{
    id = SEL.CULTURE,
    ord = 4,
    selector = CBSelectors._culture
}

CharacterBuilder.RegisterSelector{
    id = SEL.CAREER,
    ord = 5,
    selector = CBSelectors._career,
    detail = CBCareerDetail.CreatePanel
}

CharacterBuilder.RegisterSelector{
    id = SEL.CLASS,
    ord = 6,
    selector = CBSelectors._class,
    detail = CBClassDetail.CreatePanel,
}

CharacterBuilder.RegisterSelector{
    id = SEL.KIT,
    ord = 7,
    selector = CBSelectors._kit
}

CharacterBuilder.RegisterSelector{
    id = SEL.COMPLICATION,
    ord = 8,
    selector = CBSelectors._complication
}

--[[
    Sharing information about testing status
    TODO: Remove before release
]]
CharacterBuilder.INITIAL_SELECTOR = "test"
local TEST_DETAIL = [[
# Testing the New Builder

***Thank you** so much for testing this work in progress. We appreciate your effort. Your feedback will help us prepare this feature for release.*

# Feedback Needed

*We're looking for feedback in the following areas:*

- For What's Working (below), stuff that doesn't work! *(Probably first echelon only until you hear we've released more, then that, too.)*
- How it looks / renders on your screen. If it's bad, please include a screen shot with your bug submission.
- How it performs on your machine. If it seems slow, please let us know your processor, RAM, video card, and operating system.
- Your experience using the builder - what feels good, what feels not so good, how might we improve it?

*You're welcome to test with custom configured elements like ancestries, careers, classes, etc. Please validate that any issues aren't configuration before logging them.*

# What *(we think)* Is Working

*Our initial objective is to function at par with the existing builder. That means that you should be able to see and edit everything that the other builder tab does, just with a different user experience.*

**Character Section**
- Everything

**Ancestry Section**
- Everything

**Career Section**
- Everything

**Class Section**
- Everything

**Character Panel**
- Description Tab: Everything
- Builder Tab: Everything
- Exploration Tab: Everything

# Known Issues

- Second tier selection buttons, like after you've selected a class, are displayed in a long (albeit sorted) list instead of categorized.
- In the selection lists, we sometimes display redundant, empty, or meaningless extra info / description info.

# Reporing Issues

- Please use the bug forum on the Codex / DMHub Discord.
- Where applicable, please verify the old builder tab works as expected while new builder fails. If both tabs behave the same, please log as a configuration issue.
- Detailed reproduction steps, especially each thing you chose along your path, help immensely.
]]
local function _testDetail()
    return gui.Panel{
        id = "testPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "testPanel"},
        data = {
            selector = "test",
            features = {},
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get("activeSelector") == element.data.selector
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end
        end,

        gui.Panel{
            classes = {"builder-base", "panel-base"},
            width = "98%",
            height = "98%",
            vscroll = true,
            gui.Label{
                classes = {"builder-base", "label"},
                width = "98%",
                height = "auto",
                valign = "top",
                fontSize = 18,
                textAlignment = "topleft",
                markdown = true,
                text = TEST_DETAIL,
            }
        }
    }
end
function CBSelectors._test()
    return CBSelectors._makeButton{
        text = "Testing Info",
        data = { selector = "test" },
    }
end
CharacterBuilder.RegisterSelector{
    id = "test",
    ord = 9,
    selector = CBSelectors._test,
    detail = _testDetail,
}