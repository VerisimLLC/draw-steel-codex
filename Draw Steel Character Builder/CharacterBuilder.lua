--[[
 Character Builder:  Building a character step by step.
 Functions standalone or as a tab in CharacterSheet.

 - Overall Design
 - Responding to Events
 - Managing State
 - Helper Functions
 - Opptimization Opportunities
 
 OVERALL DESIGN

 The builder uses an MVC approach, as best it can. Its main window is
 the controller, which contains a state object (see MANAGING STATE).
 All interactions with the token or character, like setting values into
 the character, should be executed in events on the controller. There are
 helper functions (see HELPER FUNCTIONS) to make this a little easier.

 Big UI panels are typically lazy-loaded, meaning their UI is not created
 until it is needed.

 RESPONDING TO EVENTS

 The main window in MainPanel.lua handles the __refreshToken__ event.
 In return, it fires the __refreshBuilderState__ event on its entire tree.
 refreshBuilderState is the preferred method to responding to changes
 because it always receives a state object, which contains the token
 and so much more. See MANAGING STATE below.

 MANAGING STATE

 State is managed via a state object that is carried on the main window
 and passed through to all children via FireEventTree("refreshBuilderState", state).
 The State object contains information about the state of the token being
 edited and the rest of the builder, so that is preferable to using any other
 method to obtain this type of data.

 The State object stores data in keys, with a naming convention using dots to
 separate ideas, like "ancestry.selectedId", the currently selected GUID for
 Ancestry in the builder. It's important to note that these are not necessarily
 stored in a table structure. So, while "token" is a key, you cannot use
 "token.properties" to get the creature on the token.

 Typically you will only need the state object when responding to refreshBuilderState
 and that event always provides it. There is a helper function to get state. See
 HELPER FUNCTIONS below.

 HELPER FUNCTIONS

 There are several helper functions to make it easier for you to do things.
 These helper functions are all managed in this file and aliased as locals in
 the files where they're used.

 The helper functions used most frequently include:

 _fireControllerEvent(element, eventName, ...)
 Fires an event on the main window / controller. Pass the current UI element.

 _getHero(source)
 Returns the character in the token in the state object. Source can be any UI
 element or the state object. Ensures the value returned is a hero via :IsHero()
 or returns nil.

 _getToken(source)
 Returns the token in the state object. Source can be any UI element or the
 state object.

 OPTIMIZATION OPPORTUNITIES

 When responding to refreshBuilderState, if your element might not be visible,
 check that first. If it's not visible, then don't bother calculating anything
 else unless it needs to be used elsewhere.
 
 We might consider re-using the choice selection UI - panels built in
 FeatureSelector.lua.
]]

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

CharacterBuilder.STRINGS.CLASS = {}
CharacterBuilder.STRINGS.CLASS.INTRO = [[
Choose your hero's class. This choice has the biggest impact on how your hero interacts with the rules of the game, particularly the rules for combat.]]
CharacterBuilder.STRINGS.CLASS.OVERVIEW = [[
While all your character creation decisions bear narrative weight, none influences the way you play the game like your choice of class. Your class determines how your hero battles the threats of the timescape and overcomes other obstacles. Do you bend elemental forces to your will through the practiced casting of magic spells? Do you channel the ferocity of the Primordial Chaos as you tear across the battlefield, felling foes left and right? Or do you belt out heroic ballads that give your allies a second wind and inspire them to ever-greater achievements?]]

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

--- Determine whether the requested characteristic is avialable in the list of options
--- @param state CharacterBuilderState
--- @param selectorId string The selector under which to find the option
--- @param tableId string The guid of the roll table we're looking for
--- @return boolean
function CharacterBuilder._careerCharacteristicAvailable(state, selectorId, tableId)
    local careerItem = state:Get(selectorId .. ".selectedItem")
    if careerItem then
        for _,c in ipairs(careerItem:try_get("characteristics", {})) do
            if c:try_get("tableid") == tableId then return true end
        end
    end
    return false
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

--- Determine whether the requested feature is avialable in the list of options
--- @param state CharacterBuilderState
--- @param selectorId string The selector under which to find the feature / option
--- @param featureId string The guid of the feature we're looking for
--- @return boolean
function CharacterBuilder._featureAvailable(state, selectorId, featureId)
    local featureDetails = state:Get(selectorId .. ".filteredFeatures")
    if featureDetails then
        for _,f in ipairs(featureDetails) do
            if f.feature then
                if f.feature.guid == featureId then return true end
            end
        end
    end
    return false
end

--- Filters and potentially flattens a feature list
--- @param featureDetails table list of character features
--- @return table filteredFeatures
--- @return table flattenedFeatures Populated only if featureDetails was not flat to begin with
function CharacterBuilder._filterFeatures(featureDetails)
    local filtered = {}
    local flattened = {}

    local function processFeature(feature)
        local opts = CBFeatureSelector.EvaluateFeature(feature)
        if opts then
            filtered[#filtered+1] = opts
        end
    end

    for _,item in ipairs(featureDetails) do
        if item.features ~= nil then
            for _,feature in ipairs(item.features) do
                flattened[#flattened+1] = { feature = feature }
                processFeature(feature)
            end
        elseif item.feature ~= nil then
            processFeature(item.feature)
        end
    end

    table.sort(filtered, function(a,b) return a.order < b.order end)

    return filtered, #flattened > 0 and flattened or featureDetails
end

--- Fires an event on the main builder panel
--- @param element Panel The element calling this method
--- @param eventName string
--- @param ... any|nil
function CharacterBuilder._fireControllerEvent(element, eventName, ...)
    local controller = CharacterBuilder._getController(element)
    if controller then controller:FireEvent(eventName, ...) end
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

--- Returns the hero (character where :IsHero() is true) we're working on
--- @param source CharacterBuilderState|Panel
--- @return character|nil
function CharacterBuilder._getHero(source)
    local token = CharacterBuilder._getToken(source)
    if token and token.properties and token.properties:IsHero() then
        return token.properties
    end
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
--- @param stopAtNewline boolean Whether to trim to the first newline
--- @return string The processed string
function CharacterBuilder._trimToLength(str, maxLength, stopAtNewline)
    stopAtNewline = stopAtNewline == nil and true or stopAtNewline

    -- Trim leading whitespace
    str = str:match("^%s*(.*)") or str

    -- Cut at first newline if exists
    local newlinePos = str:find("\n")
    if newlinePos and stopAtNewline then
        str = str:sub(1, newlinePos - 1)
    end

    -- Check if length is within acceptable range
    if #str <= maxLength + 3 then
        return str
    end

    -- Truncate and add ellipsis
    return str:sub(1, maxLength) .. "..."
end

--- Return the closest number of faces to an actual die (equal to or above the value passed)
--- @param rollFaces integer
--- @return integer rollFaces
function CharacterBuilder._validateRollFaces(rollFaces)
    local validFaces = {2, 3, 6, 8, 10, 12, 20, 100}
    for _, faces in ipairs(validFaces) do
        if faces >= rollFaces then
            return faces
        end
    end
    return 100
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
--- @parameter feature table{category, catOrder, order, panelFn, feature}
--- @parameter selectorId string The selector this is a category under
--- @parameter selectedId string The unique identifier of the item associated with the feature
--- @parameter checkAvailable function(state, selectorId, featureId)
--- @parameter getSelected function(character)
--- @return table{button,panel}|nil
function CharacterBuilder._makeFeatureRegistry(options)
    local featureDef = options.feature
    local feature = featureDef.feature
    local selectorId = options.selectorId
    local selectedId = options.selectedId
    local checkAvailable = options.checkAvailable or CharacterBuilder._featureAvailable
    local getSelected = options.getSelected

    local featurePanel = featureDef.panelFn(feature)

    if featurePanel then
        return {
            button = CharacterBuilder._makeCategoryButton{
                text = CharacterBuilder._stripSignatureTrait(feature.name),
                data = {
                    featureId = feature:try_get("guid", feature:try_get("tableid")),
                    selectedId = selectedId,
                    order = featureDef.order,
                },
                click = function(element)
                    CharacterBuilder._fireControllerEvent(element, "updateState", {
                        key = selectorId .. ".category.selectedId",
                        value = element.data.featureId
                    })
                end,
                refreshBuilderState = function(element, state)
                    local tokenSelected = getSelected(CharacterBuilder._getHero(state)) or "nil"
                    local isVisible = tokenSelected == element.data.selectedId and checkAvailable(state, selectorId, element.data.featureId)
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

--- Sort an array of child panels by .data.order, preserving unordered items at start/end
--- @param children table array of panel children
--- @return table sorted children array
function CharacterBuilder._sortButtons(children)
    local prefix = {}
    local ordered = {}
    local suffix = {}

    for _, child in ipairs(children) do
        if child.data and child.data.order then
            ordered[#ordered+1] = child
        elseif #ordered > 0 then
            suffix[#suffix+1] = child
        else
            prefix[#prefix+1] = child
        end
    end

    table.sort(ordered, function(a, b)
        return a.data.order < b.data.order
    end)

    local result = {}
    table.move(prefix, 1, #prefix, 1, result)
    table.move(ordered, 1, #ordered, #result + 1, result)
    table.move(suffix, 1, #suffix, #result + 1, result)

    return result
end
