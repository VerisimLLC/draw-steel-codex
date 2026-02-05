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
                element:FireEvent("refreshBuilderState", _getState())
            end,

            press = function(element)
                _fireControllerEvent("selectItem", {
                    selector = config.selectorName,
                    id = element.data.id,
                })
            end,

            refreshBuilderState = function(element, state)
                local hero = _getHero()
                if hero then
                    local tokenSelected = config.getSelected(hero)
                    element:SetClass("collapsed", tokenSelected and tokenSelected ~= nil) --element.data.id)
                    element:FireEvent("setAvailable", not tokenSelected or tokenSelected == element.data.id)
                    if tokenSelected and tokenSelected == element.data.id and tokenSelected ~= state:Get(config.selectorName .. ".selectedId") then
                        element:FireEvent("press")
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

        selectorClick = function(element, selector)
            _fireControllerEvent("selectorChange", selector)
        end,

        children = selectors,
    }

    return selectorsPanel
end

--- Factory for selector buttons with default event handlers.
--- @param options table Button options; must include `data.selector`
--- @return Panel
function CBSelectors._makeButton(options)

    options.button.valign = "top"
    options.button.available = true

    options.classes = {"builder-base", "panel-base"}
    options.valign = "top"
    options.tmargin = CBStyles.SIZES.BUTTON_SPACING
    if options.press == nil then
        options.press = function(element)
            local selectorsPanel = element:FindParentWithClass("selectorsPanel")
            if selectorsPanel then
                selectorsPanel:FireEvent("selectorClick", element.data.selector)
            end
        end
    end
    if options.refreshBuilderState == nil then
        options.refreshBuilderState = function(element, state)
            element:FireEventTree("setSelected", state:Get("activeSelector") == element.data.selector)
        end
    end

    local button = dmhub.DeepCopy(options.button)
    options.button = nil

    options.children = {
        gui.ActionButton(button),
        CharacterBuilder.ProgressPip(1, {
            classes = {"builder-base", "panel-base", "progress-pip", "solo"},
            floating = true,
            halign = "center",
            valign = "top",
            height = 12,
            width = 12,
            borderColor = CBStyles.COLORS.GOLD03,
            refreshBuilderState = function(element, state)
                for i = 0, 100, 10 do
                    element:SetClass("progress-gradient-" .. i, false)
                end
                local selector = element.parent.data.selector
                local selectionStatus = state:Get(selector .. ".selectionStatus")
                if selectionStatus then
                    local done, slots = selectionStatus:GetStatusSummary()
                    if slots > 0 then
                        local pctComplete = math.floor((done / slots * 100) + 5)
                        pctComplete = math.floor(pctComplete / 10) * 10
                        element:SetClass("progress-gradient-" .. pctComplete, true)
                    end
                end
            end,
        }),
        CharacterBuilder.ProgressBar{
            refreshBuilderState = function(element, state)
                local selector = element.parent.data.selector
                local visible = state:Get(selector .. ".blockFeatureSelection") ~= true
                if visible then
                    local selectionStatus = state:Get(selector .. ".selectionStatus")
                    if selectionStatus then
                        local done, slots = selectionStatus:GetStatusSummary()
                        element:FireEventTree("updateProgress", {
                            slots = slots,
                            done = done,
                        })
                    end
                end
                element:SetClass("collapsed", not visible)
            end,
        }
    }

    return gui.Panel(options)
end

--- Creates a selector button that lazily loads a detail panel when selected.
--- @param config {text: string, selectorName: string, createChoicesPane: fun(): Panel}
--- @return Panel
function CBSelectors._makeDetailed(config)
    local selectorButton = CBSelectors._makeButton{
        data = {
            defaultText = config.text,
            selector = config.selectorName
        },
        refreshBuilderState = function(element, state)
            local selfSelected = state:Get("activeSelector") == element.data.selector
            local parentPane = element:FindParentWithClass(config.selectorName .. "-selector")
            if parentPane then
                element:FireEventTree("setSelected", selfSelected)
                parentPane:FireEventTree("showDetail", selfSelected)
            end
            local text = element.data.defaultText
            if config.selectedText ~= nil then
                local hero = _getHero()
                local heroText = hero and config.selectedText(hero)
                if heroText and #heroText > 0 then
                    text = heroText
                end
            end
            element:FireEventTree("setText", text)
        end,
        button = {
            text = config.text,
        }
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
            selectorButton,
        },
    }

    return selector
end

--- @return Panel Back button (hidden when in CharSheet)
function CBSelectors._back()
    return CBSelectors._makeButton{
        text = "BACK",
        data = { selector = SEL.BACK },
        create = function(element)
            element:SetClass("collapsed", CharacterBuilder._inCharSheet(element))
        end,
        press = function(element)
            print("THC:: TODO:: Not in CharSheet. Close the window, probably?")
        end,
        button = {
            text = "BACK",
        }
    }
end

--- @return Panel Character selector button
function CBSelectors._character()
    return CBSelectors._makeButton{
        text = "Character",
        data = { selector = SEL.CHARACTER },
        button = {
            text = "Character",
        }
    }
end

--- @return Panel Ancestry selector with detail panel
function CBSelectors._ancestry()
    return CBSelectors._makeDetailed{
        text = "Ancestry",
        selectorName = SEL.ANCESTRY,
        createChoicesPane = CBSelectors._ancestryItems,
        selectedText = function(hero)
            local ancestryId = hero:try_get("raceid")
            if ancestryId then
                local ancestryItem = dmhub.GetTableVisible(Race.tableName)[ancestryId]
                if ancestryItem then return ancestryItem.name end
            end
            return nil
        end,
        button = {
        }
    }
end

--- @return Panel
function CBSelectors._culture()
    return CBSelectors._makeButton{
        text = "Culture",
        data = { selector = SEL.CULTURE },
        button = {
            text = "Culture",
        }
    }
end

--- @return Panel Career selector with detail panel
function CBSelectors._career()
    return CBSelectors._makeDetailed{
        text = "Career",
        selectorName = SEL.CAREER,
        createChoicesPane = CBSelectors._careerItems,
        selectedText = function(hero)
            local careerId = hero:try_get("backgroundid")
            if careerId then
                local careerItem = dmhub.GetTableVisible(Background.tableName)[careerId]
                if careerItem then return careerItem.name end
            end
            return nil
        end,
        button = {
            text = "Culture",
        }
    }
end

--- @return Panel Class selector with detail panel
function CBSelectors._class()
    return CBSelectors._makeDetailed{
        text = "Class",
        selectorName = SEL.CLASS,
        createChoicesPane = CBSelectors._classItems,
        selectedText = function(hero)
            local classItem = hero:GetClass()
            if classItem then return classItem.name end
            return nil
        end,
        button = {
            text = "Class",
        }
    }
end

--- @return Panel Kit selector button
function CBSelectors._kit()
    return CBSelectors._makeButton{
        text = "Kit",
        data = { selector = SEL.KIT },
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            local visible = hero and hero:CanHaveKits()
            element:SetClass("collapsed", not visible)
            if not visible then return end
            element:FireEventTree("setSelected", state:Get("activeSelector") == element.data.selector)
        end,
        button = {
            text = "Kit",
        }
    }
end

--- @return Panel Complication selector button
function CBSelectors._complication()
    return CBSelectors._makeButton{
        text = "Complication",
        data = { selector = SEL.COMPLICATION },
        button = {
            text = "Complication",
        }
    }
end

CharacterBuilder.RegisterSelector{
    id = SEL.BACK,
    ord = 1,
    selector = CBSelectors._back
}

CharacterBuilder.RegisterSelector{
    id = SEL.CHARACTER,
    ord = 3,
    selector = CBSelectors._character,
    detail = CBDescriptionDetail.CreatePanel,
}

CharacterBuilder.RegisterSelector{
    id = SEL.ANCESTRY,
    ord = 2,
    selector = CBSelectors._ancestry,
    detail = CBAncestryDetail.CreatePanel,
}

CharacterBuilder.RegisterSelector{
    id = SEL.CULTURE,
    ord = 4,
    selector = CBSelectors._culture,
    detail = CBCultureDetail.CreatePanel,
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
    selector = CBSelectors._kit,
    detail = CBKitDetail.CreatePanel,
}

CharacterBuilder.RegisterSelector{
    id = SEL.COMPLICATION,
    ord = 8,
    selector = CBSelectors._complication,
    detail = CBComplicationDetail.CreatePanel,
}

--[[
    Sharing information about testing status
    TODO: Remove here to end of file before release
]]
CharacterBuilder.INITIAL_SELECTOR = "test"
local TEST_DETAIL = [[
# Testing the New Builder

***Thank you** so much for testing this work in progress. We appreciate your effort. Your feedback will help us prepare this feature for release.*

# Feedback Needed

*We're looking for feedback in the following areas:*

* How it looks / renders on your screen. If it's bad, please include a screen shot with your bug submission.
* How it performs on your machine. If it seems slow, please let us know your processor, RAM, video card, and operating system.
* Your experience using the builder - what feels good, what feels not so good, how might we improve it?

*You're welcome to test with custom configured elements like ancestries, careers, classes, etc. Please validate that any issues aren't configuration before logging them.*

# Recent Updates *(Please test!)*

**Latest Release**

* Feature selection entries now show when they have more info to display.
* Fixed bug preventing complication additional information from displaying.
* Added Perks display to right side Exploration tab.

**Previous Releases**

* Resolved issue with (sometimes?) not displaying ability cards in selected features.
* Added filter to Complications, Languages, Perks, and Skills selectors when they have >~20 entries.
* Added level groupings to Class feature selection (col2).
* Resolved ability cards painting outside the "lines".
* Removed redundant extra information when expanding a feature choice.
* Reordered right side tabs.

* Swapped order of Ancestry & Character buttons.
* Removed the debug data randomizer on character description.
* Resolved issue w/ status indicators displaying inaccurately on Ancestry, Career, and Class when switching between characters.
* We should not see any more "Unnamed Feature" buttons. If you do, please let us know how you got to it.
* Resolved issue with trimming off the top of some Ancestry Lore entries.
* Added hover tooltip to remind you to choose your main feature before choosing sub-features.
* Aggregate cultures that have langages now set their cultural language.
* Everyone is opted in. Happy testing. Let us know what we broke.
* Added double-click as a way to select & deselect features (column 3).
* Added drag & drop as a way to select & deselect features (column 3).
* Changed the select feature icon / button to a + (column 3) & added hover tooltip.
* Added the ability to select aggregate cultures as starting points, then you can still change individual aspects.

# Known Issues

* *None?*

# Reporting Issues

* Please use the bug forum on the Codex / DMHub Discord.
* Where applicable, please verify the old builder tab works as expected while new builder fails. If both tabs behave the same, please log as a configuration issue.
* Detailed reproduction steps, especially each thing you chose along your path, help immensely.
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
        data = { selector = "test" },
        button = {
            text = "Testing Info (README)",
        }
    }
end
CharacterBuilder.RegisterSelector{
    id = "test",
    ord = 9,
    selector = CBSelectors._test,
    detail = _testDetail,
}