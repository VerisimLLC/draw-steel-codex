--- Character Sheet Builder  building a character step by step
--- Functions standalone or plugs in to CharacterSheet
--- 
--- - Data is managed in the main window state.
---   Respond to event `refreshBuilderState` which receives a state object
---   Send state updates back to the controller by using `_fireControllerEvent("updateState", {key = x, value = y})`
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
    return element:FindParentWithClass(CharacterBuilder.CONTROLLER_CLASS)
end

--- Returns the creature (character) we're working on
--- @return creature|nil
function CharacterBuilder._getCreature(element)
    local token = CharacterBuilder._getToken(element)
    if token then return token.properties end
    return nil
end

--- Returns the selector data
--- @return table|nil
function CharacterBuilder._getData(element)
    local controller = CharacterBuilder._getController(element)
    if controller then return controller.data.selectorData end
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
--- @return LuaCharacterToken|nil
function CharacterBuilder._getToken(element)
    if element.data == nil then element.data = {} end
    if element.data.controller == nil then
        element.data.controller = CharacterBuilder._getController(element)
    end
    if element.data.controller then
        return element.data.controller.data.GetToken(element.data.controller)
    end
    return nil
end

function CharacterBuilder._inCharSheet(element)
    return CharacterBuilder._getCharacterSheet(element) ~= nil
end

function CharacterBuilder._sortArrayByProperty(items, propertyName)
    table.sort(items, function(a,b) return a[propertyName] < b[propertyName] end)
    return items
end

function CharacterBuilder._toArray(t)
    local a = {}
    for _,item in pairs(t) do
        a[#a+1] = item
    end
    return a
end
