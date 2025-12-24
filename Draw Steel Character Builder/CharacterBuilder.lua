--- Character Sheet Builder  building a character step by step
--- Functions standalone or plugs in to CharacterSheet
--- 
--- - State of the builder is managed via the main window's data.state object,
---   which you should always pass to the `refreshBuilderState` event.
---   Reference `CharacterBuilderState` to understand this object.
--- - You should always update the state object via firing the updateState event
---   on the main window and passing {key = x, value = y} to it. It will then
---   fire the `refreshBuilderState` event tree for you.
--- - There are lots of helper functions, the most frequently used of which
---   are probably `_fireControllerEvent()`, `_getCreature()`, and `_getToken()`. 
--- - Do not respond to `refreshToken`. The controller processes this event and
---   translates into call to `refreshBuilderState`. Respond to that instead.
CharacterBuilder = RegisterGameType("CharacterBuilder")

CharacterBuilder.CONTROLLER_CLASS = "builderPanel"
CharacterBuilder.ROOT_CHAR_SHEET_CLASS = "characterSheetHarness"

CharacterBuilder.STRINGS = {}

CharacterBuilder.STRINGS.ANCESTRY = {}
CharacterBuilder.STRINGS.ANCESTRY.INTRO = [[
Fantastic peoples inhabit the worlds of Draw Steel. Among them are devils, dwarves, elves, time raiders--and of course humans, whose culture and history dominates many worlds.]]
CharacterBuilder.STRINGS.ANCESTRY.OVERVIEW = [[
Ancestry describes how you were born. Culture (part of Chapter 4: Background) describes how you grew up. If you want to be a wode elf who was raised in a forest among other wode elves, you can do that! If you want to play a wode elf who was raised in an underground city of dwarves, humans, and orcs, you can do that too!

Your hero is one of these folks! The fantastic ancestry you choose bestows benefits that come from your anatomy and physiology. This choice doesn't grant you cultural benefits, such as crafting or lore skills, though. While many game settings have cultures made of mostly one ancestry, other cultures and worlds have a cosmopolitan mix of peoples.]]

CharacterBuilder.STRINGS.CAREER = {}
CharacterBuilder.STRINGS.CAREER.INTRO = [[
Being a hero isn't a job. It's a calling. But before you answered that call, you had a different job or vocation that paid the bills. Thank the gods for that, because the experience you gained in that career is now helping you save lives and slay monsters.]]
CharacterBuilder.STRINGS.CAREER.OVERVIEW = [[
Your career describes what your life was before you became a hero. When you select a career, you gain a number of benefits, the details of which are specified in the career's description.]]

--[[
    Register selectors - controls down the left side of the window
]]

CharacterBuilder.Selectors = {}
CharacterBuilder.SelectorLookup = {}

function CharacterBuilder.ClearBuilderTabs()
    CharacterBuilder.Selectors = {}
end

function CharacterBuilder.RegisterSelector(selector)
    CharacterBuilder.Selectors[#CharacterBuilder.Selectors+1] = selector
    CharacterBuilder.SelectorLookup[selector.id] = selector
    CharacterBuilder._sortArrayByProperty(CharacterBuilder.Selectors, "ord")
end

--[[
    Utilities
]]

--- If the string passed is nil or empty returns '--'
--- @param s? string The string to evaluate
--- @return string
function CharacterBuilder._blankToDashes(s)
    if s == nil or #s == 0 then return "--" end
    return s
end

--- Determine if we can find the specified item ID in the feature ID in the character's level choices
--- @param character character
--- @param featureId string
--- @param itemId string
--- @return boolean
function CharacterBuilder._characterHasLevelChoice(character, featureId, itemId)
    if character then
        local levelChoices = character:GetLevelChoices()
        if levelChoices and levelChoices[featureId] then
            for _,selectedId in ipairs(levelChoices[featureId]) do
                if itemId == selectedId then return true end
            end
        end
    end
    return false
end

--- Return the count of items in a keyed table
--- @param t table
--- @return integer numItems
function CharacterBuilder._countKeyedTable(t)
    local numItems = 0
    for _ in pairs(t) do
        numItems = numItems + 1
    end
    return numItems
end

--- Fires an event on the main builder panel
--- @param element Panel The element calling this method
--- @param eventName string
--- @param info any|nil
function CharacterBuilder._fireControllerEvent(element, eventName, info)
    local controller = CharacterBuilder._getController(element)
    if controller then controller:FireEvent(eventName, info) end
end

--- Returns the character sheet instance if we're operating inside it
--- @return CharacterSheet|nil
function CharacterBuilder._getCharacterSheet(element)
    return element:FindParentWithClass(CharacterBuilder.ROOT_CHAR_SHEET_CLASS)
end

--- Returns the builder controller
--- @return Panel
function CharacterBuilder._getController(element)
    if element.data == nil then element.data = {} end
    if element.data.controller == nil then
        element.data.controller = element:FindParentWithClass(CharacterBuilder.CONTROLLER_CLASS)
    end
    return element.data.controller
end

--- Returns the creature (character) we're working on
--- @param source CharacterBuilderState|Panel
--- @return creature|nil
function CharacterBuilder._getCreature(source)
    local token = CharacterBuilder._getToken(source)
    if token then return token.properties end
    return nil
end

--- Returns the builder state
--- @return @CharacterBuilderState|nil
function CharacterBuilder._getState(element)
    local controller = CharacterBuilder._getController(element)
    if controller then return controller.data.state end
    return nil
end

--- Returns the character token we are working with or nil if we can't get to it
--- @param source CharacterBuilderState|Panel
--- @return LuaCharacterToken|nil
function CharacterBuilder._getToken(source)
    if source.typeName == "CharacterBuilderState" then
        return source:Get("token")
    end
    local state = CharacterBuilder._getState(source)
    if state then return state:Get("token") end
    return nil
end

function CharacterBuilder._inCharSheet(element)
    return CharacterBuilder._getCharacterSheet(element) ~= nil
end

function CharacterBuilder._sortArrayByProperty(items, propertyName)
    table.sort(items, function(a,b) return a[propertyName] < b[propertyName] end)
    return items
end

function CharacterBuilder._stripSignatureTrait(str)
    local result = regex.MatchGroups(str, "(?i)^signature\\s+trait:?\\s*(?<name>.*)$")
    if result and result.name then return result.name end
    return str
end

function CharacterBuilder._toArray(t)
    local a = {}
    for _,item in pairs(t) do
        a[#a+1] = item
    end
    return a
end

function CharacterBuilder._ucFirst(str)
    if str and #str > 0 then
        return str:sub(1,1):upper() .. str:sub(2)
    end
    return str
end

--- Trims and truncates a string to a maximum length
--- @param str string The string to process
--- @param maxLength number The maximum length before truncation
--- @return string The processed string
function CharacterBuilder._trimToLength(str, maxLength)
    -- Trim leading whitespace
    str = str:match("^%s*(.*)") or str

    -- Cut at first newline if exists
    local newlinePos = str:find("\n")
    if newlinePos then
        str = str:sub(1, newlinePos - 1)
    end

    -- Check if length is within acceptable range
    if #str <= maxLength + 3 then
        return str
    end

    -- Truncate and add ellipsis
    return str:sub(1, maxLength) .. "..."
end

--[[
    Consistent UI
]]

--- Build a Category button, forcing consistent styling.
--- Be sure to add behaviors for click and refreshBuilderState
--- @param options ButtonOptions
--- @return SelectorButton|Panel
function CharacterBuilder._makeCategoryButton(options)
    options.width = CBStyles.SIZES.CATEGORY_BUTTON_WIDTH
    options.height = CBStyles.SIZES.CATEGORY_BUTTON_HEIGHT
    options.valign = "top"
    options.bmargin = CBStyles.SIZES.CATEGORY_BUTTON_MARGIN
    options.bgcolor = CBStyles.COLORS.BLACK03
    options.borderColor = CBStyles.COLORS.GRAY02
    return gui.SelectorButton(options)
end

--- Build a nav button for the detail pane
--- @param selector string The selector name the detail panel resides under
--- @param options table 
--- @return SelectorButton|Panel
function CharacterBuilder._makeDetailNavButton(selector, options)
    if options.click == nil then
        options.click = function(element)
            CharacterBuilder._fireControllerEvent(element, "updateState", {
                key = selector .. ".category.selectedId",
                value = element.data.category
            })
        end
    end
    if options.refreshBuilderState == nil then
        options.refreshBuilderState = function(element, state)
            element:FireEvent("setAvailable", state:Get(selector .. ".selectedId") ~= nil)
            element:FireEvent("setSelected", state:Get(selector .. ".category.selectedId") == element.data.category)
        end
    end
    return CharacterBuilder._makeCategoryButton(options)
end

--- Create a registry entry for a feature - a button and an editor panel
--- @parameter feature CharacterFeature
--- @parameter selectorId string The selector this is a category under
--- @parameter selectedId string The unique identifier of the item associated with the feature
--- @parameter getSelected function(creature)
--- @return Panel|nil
function CharacterBuilder._makeFeatureRegistry(feature, selectorId, selectedId, getSelected)

    local featurePanel = CBFeatureSelector.Panel(feature)

    if featurePanel then
        return {
            button = CharacterBuilder._makeCategoryButton{
                text = CharacterBuilder._stripSignatureTrait(feature.name),
                data = {
                    featureId = feature.guid,
                    selectedId = selectedId,
                },
                click = function(element)
                    CharacterBuilder._fireControllerEvent(element, "updateState", {
                        key = selectorId .. ".category.selectedId",
                        value = element.data.featureId
                    })
                end,
                refreshBuilderState = function(element, state)
                    local tokenSelected = getSelected(CharacterBuilder._getCreature(state)) or "nil"
                    local isVisible = tokenSelected == element.data.selectedId
                    element:FireEvent("setAvailable", isVisible)
                    element:FireEvent("setSelected", element.data.featureId == state:Get(selectorId .. ".category.selectedId"))
                    element:SetClass("collapsed", not isVisible)
                end,
            },
            panel = gui.Panel{
                classes = {"featurePanel", "builder-base", "panel-base", "collapsed"},
                width = "100%",
                height = "98%",
                flow = "vertical",
                valign = "top",
                halign = "center",
                tmargin = 12,
                -- vscroll = true,
                data = {
                    featureId = feature.guid,
                },
                refreshBuilderState = function(element, state)
                    local isVisible = element.data.featureId == state:Get(selectorId .. ".category.selectedId")
                    element:SetClass("collapsed", not isVisible)
                end,
                featurePanel,
            },
        }
    end

    return nil
end

--- Build a Select button, forcing consistent styling
--- @param options ButtonOptions 
--- @return PrettyButton|Panel
function CharacterBuilder._makeSelectButton(options)
    local opts = dmhub.DeepCopy(options)

    opts.classes = {"builder-base", "button", "select"}
    if options.classes then
        table.move(options.classes, 1, #options.classes, #opts.classes + 1, opts.classes)
    end
    opts.width = CBStyles.SIZES.SELECT_BUTTON_WIDTH
    opts.height = CBStyles.SIZES.SELECT_BUTTON_HEIGHT
    opts.text = "SELECT"
    opts.floating = true
    opts.halign = "center"
    opts.valign = "bottom"
    opts.bmargin = -10
    opts.fontSize = 24
    opts.bold = true
    opts.cornerRadius = 5
    opts.border = 1
    opts.borderWidth = 1
    opts.borderColor = CBStyles.COLORS.CREAM03

    return gui.PrettyButton(opts)
end
