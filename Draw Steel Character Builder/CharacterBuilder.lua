--[[
 Character Builder:  Building a character step by step.
 Functions standalone or as a tab in CharacterSheet.

 TODO::
 - Old builder attributes are in MCDMClassCarousel.lua start line 1481
 - Slow start rules aren't honored - still pulling full level 1 class features

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
 state:Get("token.properties") to get the creature on the token. Instead you
 would use state:Get(token).properties.

 Typically you will only need the state object when responding to refreshBuilderState
 and that event always provides it. There is a helper function to get state. See
 HELPER FUNCTIONS below.

 HELPER FUNCTIONS

 There are several helper functions to make it easier for you to do things.
 These helper functions are all managed in this file and aliased as locals in
 the files where they're used.

 The helper functions used most frequently include:

 _fireControllerEvent(eventName, ...)
 Fires an event on the main window / controller. Pass the current UI element.

 _getHero(source)
 Returns the character in the token in the state object. Source can be any UI
 element or the state object. Ensures the object returned is a hero via :IsHero()
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

-- The filter on feature lists is visible only when the count
-- of available options is >= this number
CharacterBuilder.FILTER_VISIBLE_COUNT = 20

--- Trim long text on overview pages to this length
CharacterBuilder.OVERVIEW_MAX_LENGTH = 1200

CharacterBuilder.SELECTOR = {
    BACK        = "back",
    CHARACTER   = "character",
    ANCESTRY    = "ancestry",
    CULTURE     = "culture",
    CAREER      = "career",
    CLASS       = "class",
    KIT         = "kit",
    COMPLICATION = "complication",
}
CharacterBuilder.INITIAL_SELECTOR = CharacterBuilder.SELECTOR.CHARACTER

CharacterBuilder.STRINGS = {}

CharacterBuilder.STRINGS.ANCESTRY = {}
CharacterBuilder.STRINGS.ANCESTRY.INTRO = [[
Fantastic peoples inhabit the worlds of Draw Steel. Among them are devils, dwarves, elves, time raiders--and of course humans, whose culture and history dominates many worlds.]]
CharacterBuilder.STRINGS.ANCESTRY.OVERVIEW = [[
Ancestry describes how you were born. Culture (part of Chapter 4: Background) describes how you grew up. If you want to be a wode elf who was raised in a forest among other wode elves, you can do that! If you want to play a wode elf who was raised in an underground city of dwarves, humans, and orcs, you can do that too!

Your hero is one of these folks! The fantastic ancestry you choose bestows benefits that come from your anatomy and physiology. This choice doesn't grant you cultural benefits, such as crafting or lore skills, though. While many game settings have cultures made of mostly one ancestry, other cultures and worlds have a cosmopolitan mix of peoples.]]

CharacterBuilder.STRINGS.CULTURE = {}
CharacterBuilder.STRINGS.CULTURE.INTRO = [[
A hero's culture describes the beliefs, customs, values, and way of life held by the community in which they were raised. This community provides life experiences that give a character some of their game statistics. Even if a hero doesn't share their culture's values, those values shaped their early development and way of life. In fact, some people become heroes primarily from the rejection of the ways of their culture.]]
CharacterBuilder.STRINGS.CULTURE.OVERVIEW = [[
Select one from each culture aspect:
- Environment
- Organization
- Upbringing]]

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

CharacterBuilder.STRINGS.KIT = {}
CharacterBuilder.STRINGS.KIT.INTRO = [[
The knight in shining armor. The warrior priest. The sniper. Censors, furies, shadows, tacticians, and troubadours can tap into these and many more archetypal concepts using kits. A kit is a combination of weapons, armor, and fighting techniques that lets you personalize your martial hero for battle.]]
CharacterBuilder.STRINGS.KIT.OVERVIEW = [[
# Customizing Equipment Appearances
You should absolutely feel free to describe your equipment in a way that makes sense for the story of your game and hero. For instance, if your hero uses a weapon in the whip category as part of their kit, they could use a leather whip, a spiked chain, or a dagger tied to a knotted rope. A hero who wears heavy armor might wear a suit of chain mail, plate armor, or heavy wooden planks tied together. Your choices for equipment aren't limited just to the examples in this book.]]

CharacterBuilder.STRINGS.COMPLICATION = {}
CharacterBuilder.STRINGS.COMPLICATION.INTRO = [[
Beyond the abilities and features bestowed by ancestry and class, your hero might have something else that makes them ... unusual. Perhaps an earth elemental lives in your body. Maybe your eldritch blade devastates enemies but feeds on your own vitality. A complication is an optional feature you can select to enrich your hero's backstory, with any complication providing you both a positive benefit and a negative drawback.]]

--[[
    Ability to register selectors - controls down the left side of the window
]]

CharacterBuilder.Selectors = {}
CharacterBuilder.SelectorLookup = {}

--- Clear all registered builder tabs
function CharacterBuilder.ClearBuilderTabs()
    CharacterBuilder.Selectors = {}
end

--- Register a selector for the builder
function CharacterBuilder.RegisterSelector(selector)
    CharacterBuilder.Selectors[#CharacterBuilder.Selectors+1] = selector
    CharacterBuilder.SelectorLookup[selector.id] = selector
    CharacterBuilder._sortArrayByProperty(CharacterBuilder.Selectors, "ord")
end

--[[
    Utilities
]]

--- Find a proper attribute name given an ID
--- @param attrId string
--- @return string
function CharacterBuilder._attrNameFromId(attrId)
    local info = creature.attributesInfo[attrId]
    return info and info.description or "Unknown"
end

--- If the string passed is nil or empty returns '--'
--- @param s? string The string to evaluate
--- @return string
function CharacterBuilder._blankToDashes(s)
    if s == nil or #s == 0 then return "--" end
    return s
end

--- Attempt to derive an attribute build from the hero and its class's base characteristics
--- @param hero character
--- @param baseChars table
--- @return table|nil
function CharacterBuilder._deriveAttributeBuild(hero, baseChars)
    local heroAttrs = hero:try_get("attributes")
    if heroAttrs == nil then return nil end
    local allAttrs = character.attributesInfo

    local searchAttrs = {}
    for _,attrDef in pairs(allAttrs) do
        local baseAttrItem = baseChars[attrDef.id]
        if baseAttrItem ~= nil then
            if baseAttrItem ~= heroAttrs[attrDef.id].baseValue then return nil end
        else
            searchAttrs[attrDef.id] = true
        end
    end

    -- Build ordered list of search attributes with their hero values
    local searchList = {}
    for attrId, _ in pairs(searchAttrs) do
        local attrInfo = allAttrs[attrId]
        searchList[#searchList + 1] = {
            id = attrId,
            order = attrInfo and attrInfo.order or 999,
            value = heroAttrs[attrId].baseValue
        }
    end
    table.sort(searchList, function(a, b) return a.order < b.order end)

    -- Extract hero values for comparison
    local heroValues = {}
    for i, item in ipairs(searchList) do
        heroValues[i] = item.value
    end

    -- Try each array to find a match
    for arrayIdx, arr in ipairs(baseChars.arrays) do
        if #arr == #searchList then
            -- Sort both for multiset comparison
            local arrSorted = {}
            for i = 1, #arr do arrSorted[i] = arr[i] end
            table.sort(arrSorted)

            local heroSorted = {}
            for i = 1, #heroValues do heroSorted[i] = heroValues[i] end
            table.sort(heroSorted)

            -- Compare multisets
            local match = true
            for i = 1, #arrSorted do
                if arrSorted[i] ~= heroSorted[i] then
                    match = false
                    break
                end
            end

            if match then
                -- Find specific assignment: which array index -> which attribute
                local assignment = {}
                local usedIndices = {}

                for _, item in ipairs(searchList) do
                    for j = 1, #arr do
                        if not usedIndices[j] and arr[j] == item.value then
                            assignment[item.id] = j
                            usedIndices[j] = true
                            break
                        end
                    end
                end

                assignment.array = arrayIdx
                return assignment
            end
        end
    end

    return nil
end

--- Fires an event on the main builder panel
--- @param element Panel The element calling this method
--- @param eventName string
--- @param ... any|nil
function CharacterBuilder._fireControllerEvent(eventName, ...)
    local controller = CharacterBuilder._getController()
    if controller then controller:FireEvent(eventName, ...) end
end

--- Format an order string for sorting
--- @param n number|nil The numeric order value
--- @param s string|nil The text portion
--- @return string
function CharacterBuilder._formatOrder(n, s)
    return string.format("%03d-%s", n or 999, (s and #s > 0) and s or "zzzunknown-item")
end

--- If the parameter is a function, return its return value else return the item
--- @param item any
--- @return any
function CharacterBuilder._functionOrValue(item)
    if item == nil then return nil end
    if type(item) == "function" then return item() end
    return item
end

--- Returns the character sheet instance if we're operating inside it
--- @return Panel|nil
function CharacterBuilder._getCharacterSheet()
    local controller = CharacterBuilder._getController()
    if controller then
        return controller:FindParentWithClass(CharacterBuilder.ROOT_CHAR_SHEET_CLASS)
    end
    return nil
end

--- Returns the builder controller
--- @return Panel
function CharacterBuilder._getController()
    return CharacterBuilder:try_get("builderPanel")
end

--- Returns the hero (character where :IsHero() is true) we're working on
--- @return character|nil
function CharacterBuilder._getHero()
    local token = CharacterBuilder._getToken()
    if token and token.properties and token.properties:IsHero() then
        return token.properties
    end
    return nil
end

--- Returns the builder state
--- @return @CharacterBuilderState|nil
function CharacterBuilder._getState()
    local controller = CharacterBuilder._getController()
    if controller then return controller.data.state end
    return nil
end

--- Returns the character token we are working with or nil if we can't get to it
--- @return LuaCharacterToken|nil
function CharacterBuilder._getToken()
    local state = CharacterBuilder._getState()
    if state then return state:Get("token") end
    return nil
end

--- Return the named function on the object, if it exists, else nil
--- @param object any
--- @param fnName string The name of the desired function
--- @return function|nil
function CharacterBuilder._hasFn(object, fnName)
    local typeName = object.typeName
    if typeName == nil then return nil end
    local classTable = rawget(_G, typeName)
    return classTable and type(classTable) == "table" and rawget(classTable, fnName)
end

--- @return boolean
function CharacterBuilder._inCharSheet(element)
    return CharacterBuilder._getCharacterSheet(element) ~= nil
end

--- Filters a string against filter text with special operators
--- @param needle string The filter pattern (supports >, <, !, -)
--- @param haystack string The text to filter
--- @return boolean matches Whether the text matches the filter
function CharacterBuilder._matchesFilter(needle, haystack)
    if needle == nil or #needle == 0 then return true end

    local pattern = needle
    local isNegative = false

    -- Check for negation
    if pattern:sub(1, 1) == "!" or pattern:sub(1, 1) == "-" then
        isNegative = true
        pattern = pattern:sub(2)
    end

    -- Convert > to ^ (start of string)
    if pattern:sub(1, 1) == ">" then
        pattern = "^" .. pattern:sub(2)
    end

    -- Convert < to $ (end of string)
    if pattern:sub(-1) == "<" then
        pattern = pattern:sub(1, -2) .. "$"
    end

    -- Escape other special regex characters
    pattern = pattern:gsub("([%.%[%]%(%)%*%+%?])", "%%%1")

    -- Apply case-insensitive flag
    pattern = "(?i)" .. pattern

    local matches = regex.MatchGroups(haystack, pattern) ~= nil

    return isNegative and not matches or matches
end

--- Merge two tables, with custom values overwriting defaults
--- @param defaults table
--- @param custom table|nil
--- @return table
function CharacterBuilder._mergeKeyedTables(defaults, custom)
    custom = custom or {}
    local result = {}
    for k, v in pairs(defaults) do result[k] = v end
    for k, v in pairs(custom) do result[k] = v end
    return result
end

--- Parse starting characteristics into a description string
--- @param baseChars table Keyed table of attribute ids to values
--- @return string
function CharacterBuilder._parseStartingCharacteristics(baseChars)

    local vowels = {a=true, e=true, i=true, o=true, u=true}

    local attrInfo = character.attributesInfo

    local items = {}
    for k,def in pairs(attrInfo) do
        local item = baseChars[k]
        if item then
            local firstChar = def.description:sub(1,1):lower()
            local article = vowels[firstChar] and "n" or ""
            items[#items+1] = {
                text = string.format("a%s **%s** of %d", article, def.description, item),
                order = def.order,
            }
        end
    end
    table.sort(items, function(a,b) return a.order < b.order end)

    local str = "Could not find starting characteristics."
    local numItems = #items
    if numItems > 0 then
        str = string.format("You start with %s", items[1].text)
        if numItems == 2 then
            str = string.format("%s and %s", str, items[2].text)  -- Fixed: added %s for items[2].text
        elseif numItems > 1 then
            for i = 2, numItems - 1 do
                str = string.format("%s, %s", str, items[i].text)
            end
            str = string.format("%s, and %s", str, items[numItems].text)
        end
        str = string.format("%s, and you can choose one of the following arrays for your other characteristic scores.\nSelect an array, then drag and drop scores to rearrange them.", str)  -- Fixed: added str
    end

    return str
end

--- Gets a safe display name for a feature
--- @param feature table The feature object
--- @return string The feature name
function CharacterBuilder._safeFeatureName(feature)
    local name = feature:try_get("name")
    if name then
        return name
    end

    -- Extract type name without "Character" prefix
    local typeName = feature.typeName:sub(10)  -- Remove "Character"

    -- Add spaces before capitals (except first char)
    return typeName:sub(1, 1) .. typeName:sub(2):gsub("(%u)", " %1")
end

--- Safely get a named property from an item, defaulting to nil
--- Works with both class instances (with try_get) and plain tables
--- @param item table The item to check
--- @param propertyName string
--- @param defaultValue? any
--- @return any
function CharacterBuilder._safeGet(item, propertyName, defaultValue)
    if item.try_get then
        return item:try_get(propertyName, defaultValue)
    end
    local value = item[propertyName]
    if value == nil then value = defaultValue end
    return value
end

--- @return table
function CharacterBuilder._sortArrayByProperty(items, propertyName)
    table.sort(items, function(a,b) return a[propertyName] < b[propertyName] end)
    return items
end

--- @return string
function CharacterBuilder._stripSignatureTrait(str)
    local result = regex.MatchGroups(str, "(?i)^signature\\s+trait:?\\s*(?<name>.*)$")
    if result and result.name then return result.name end
    return str
end

--- Transform a keyed list into an array
--- @param t table A keyed list
--- @return table a An array
function CharacterBuilder._toArray(t)
    local a = {}
    for _,item in pairs(t) do
        a[#a+1] = item
    end
    return a
end

--- Trims and truncates a string to a maximum length
--- @param str string The string to process
--- @param maxLength number The maximum length before truncation
--- @param stopAtNewline? boolean Whether to trim to the first newline
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

--- @return string
function CharacterBuilder._ucFirst(str)
    if str and #str > 0 then
        return str:sub(1,1):upper() .. str:sub(2)
    end
    return str
end

--- Return the closest number of faces to an actual die (equal to or above the value passed)
--- @param rollFaces integer
--- @return integer rollFaces
function CharacterBuilder._validateRollFaces(rollFaces)
    local validFaces = {2, 3, 6, 8, 10, 12, 20, 100}
    for _, faces in ipairs(validFaces) do
        if faces >= rollFaces then
            if faces == 10 then return 20 end
            return faces
        end
    end
    return 100
end

--[[
    Consistent UI
]]

--- Display a confrmation dialog, calling callbacks as necessary
--- @param opts table {title, message, confirmText, cancelText, onConfirm, onCancel}
function CharacterBuilder._confirmDialog(opts)
    local title = (opts.title and opts.title ~= "") and opts.title or "Confirm"
    local message = (opts.message and opts.message ~= "") and opts.message or "Are you sure you want to take this action?"
    local confirmText = (opts.confirmText and opts.confirmText ~= "") and opts.confirmText or "Confirm"
    local cancelText = (opts.cancelText and opts.cancelText ~= "") and opts.cancelText or "Cancel"

    local onCancel = function()
        if opts.onCancel and type(opts.onCancel) == "function" then
            opts.onCancel()
        end
    end

    local onConfirm = function()
        if opts.onConfirm and type(opts.onConfirm) == "function" then
            opts.onConfirm()
        end
    end

    local resultPanel = nil
    resultPanel = gui.Panel {
        styles = CBStyles.GetStyles(),
        classes = {"confirmDialogController", "builder-base", "panel-base", "dialog"},
        width = 500,
        height = 300,
        floating = true,
        escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
        captureEscape = true,
        data = {
            close = function()
                resultPanel:DestroySelf()
            end,
        },

        close = function(element)
            element.data.close()
        end,

        escape = function(element)
            onCancel()
            element:FireEvent("close")
        end,

        children = {
            -- Header
            gui.Label{
                classes = {"builder-base", "label", "dialog-header"},
                text = title,
            },
            gui.MCDMDivider{
                classes = {"builder-divider"},
                layout = "dot",
                width = "50%",
                vpad = 4,
                -- bgcolor = CBStyles.COLORS.GOLD,
            },

            -- Confirmation message
            gui.Label{
                classes = {"builder-base", "label", "dialog-message"},
                text = message,
            },

            -- Button panel
            gui.Panel{
                classes = {"builder-base", "panel-base", "container"},
                -- width = "100%",
                height = 40,
                halign = "center",
                valign = "bottom",
                flow = "horizontal",
                gui.Button{
                    classes = {"builder-base", "button", "dialog"},
                    width = 120,
                    text = cancelText,
                    click = function(element)
                        local controller = element:FindParentWithClass("confirmDialogController")
                        if controller then
                            controller:FireEvent("escape")
                        end
                    end
                },
                gui.Button{
                    classes = {"builder-base", "button", "dialog"},
                    width = 120,
                    halign = "right",
                    text = confirmText,
                    click = function(element)
                        onConfirm()
                        local controller = element:FindParentWithClass("confirmDialogController")
                        if controller then controller:FireEvent("close") end
                    end
                }
            }
        },
    }

    return resultPanel
end

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
    if options.press == nil then
        options.press = function(element)
            CharacterBuilder._fireControllerEvent("updateState", {
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

--- Build a feature panel container with consistent structure
--- @param options table Additional options to merge (data, events, children)
--- @return Panel
function CharacterBuilder._makeFeaturePanelContainer(options)
    options = options or {}
    local panelDef = CharacterBuilder._mergeKeyedTables({
        classes = {"featurePanel", "builder-base", "panel-base", "collapsed"},
        width = "100%",
        height = "98%",
        flow = "vertical",
        valign = "top",
        halign = "center",
        tmargin = 12,
    }, options)
    return gui.Panel(panelDef)
end

--- @class CBFeatureRegistryOptions
--- @field feature CBFeatureWrapper
--- @field selector string The selector we're running under
--- @field selectedId string The id of the item selected on the hero
--- @field checkAvailable? function (state, selector, featureId)
--- @field getSelected function(hero) Return the currently selected value - match to or replace selectedId

--- Create a registry entry for a feature - a button & an editor panel
--- @param options CBFeatureRegistryOptions
--- @param feature CBFeatureWrapper
--- @return table|nil
function CharacterBuilder._makeFeatureRegistry(options)
    local feature = options.feature
    local selector = options.selector
    local selectedId = options.selectedId
    local getSelected = options.getSelected

    local featurePanel = CBFeatureSelector.SelectionPanel(selector, feature)

    if featurePanel then
        return {
            button = gui.Panel{
                classes = {"builder-base", "panel-base"},
                valign= "top",
                data = {
                    featureId = feature:GetGuid(),
                    selectedId = selectedId,
                    order = feature:GetOrder(),
                    level = feature:GetLevel(),
                    visible = true,
                },
                press = function(element)
                    CharacterBuilder._fireControllerEvent("updateState", {
                        key = selector .. ".category.selectedId",
                        value = element.data.featureId
                    })
                end,
                showLevel = function(element, level, expanded)
                    if element.data.level == level then
                        element.data.visible = expanded
                    end
                    element:SetClass("collapsed-anim", not element.data.visible)
                end,
                CharacterBuilder._makeCategoryButton{
                    text = CharacterBuilder._stripSignatureTrait(feature:GetName()),
                    press = function(element)
                        CharacterBuilder._fireControllerEvent("updateState", {
                            key = selector .. ".category.selectedId",
                            value = element.parent.data.featureId
                        })
                    end,
                    refreshBuilderState = function(element, state)
                        local tokenSelected = getSelected(CharacterBuilder._getHero()) or "nil"
                        local featureCache = state:Get(selector .. ".featureCache")
                        feature = featureCache and featureCache:GetFeature(element.parent.data.featureId)
                        local featureAvailable = feature ~= nil
                        local visible = (tokenSelected == element.parent.data.selectedId) and featureAvailable
                        element:FireEvent("setAvailable", visible)
                        element:FireEvent("setSelected", element.parent.data.featureId == state:Get(selector .. ".category.selectedId"))
                        element:SetClass("collapsed", not visible)
                    end,
                },
                CharacterBuilder.ProgressPip(1, {
                    rotate = 0,
                    classes = {"builder-base", "panel-base", "progress-pip", "secondary"},
                    halign = "right",
                    valign = "top",
                    hmargin = 3,
                    vmargin = 3,
                    width = 12,
                    height = 12,
                    refreshBuilderState = function(element, state)
                        local visible = state:Get(selector .. ".blockFeatureSelection") ~= true
                        if visible then
                            local featureCache = state:Get(selector .. ".featureCache")
                            local feature = featureCache and featureCache:GetFeature(element.parent.data.featureId)
                            visible = visible and (feature and not feature:SuppressStatus())
                            local filled = feature and feature:IsComplete()
                            element:SetClass("filled", filled)
                        end
                        element:SetClass("collapsed", not visible)
                    end,
                }),
            },
            panel = CharacterBuilder._makeFeaturePanelContainer{
                data = {
                    featureId = feature:GetGuid(),
                },
                refreshBuilderState = function(element, state)
                    local visible = element.data.featureId == state:Get(selector .. ".category.selectedId")
                    element:SetClass("collapsed", not visible)
                    if not visible then
                        element:HaltEventPropagation()
                    end
                end,
                children = { featurePanel },
            },
        }
    end

    return nil
end

--- Build a Select button, forcing consistent styling
--- @param options ButtonOptions 
--- @return PrettyButton|Panel
function CharacterBuilder._makeSelectButton(options)
    local opts = {
        classes = {"builder-base", "button", "select"},
        width = CBStyles.SIZES.SELECT_BUTTON_WIDTH,
        height = CBStyles.SIZES.SELECT_BUTTON_HEIGHT,
        text = "SELECT",
        floating = true,
        halign = "center",
        valign = "bottom",
        bmargin = -10,
        fontSize = 24,
        bold = true,
        cornerRadius = 5,
        border = 1,
        borderWidth = 1,
        borderColor = CBStyles.COLORS.CREAM03,
    }
    for k, v in pairs(options) do
        if k == "classes" or k == "styles" then
            table.move(v, 1, #v, #opts[k] + 1, opts[k])
        else
            opts[k] = v
        end
    end

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

--- @return Panel
function CharacterBuilder.ProgressPip(index, opts)
    local options = {
        classes = {"builder-base", "panel-base", "progress-pip"},
        rotate = 45,
        data = {
            index = index,
        },
        updateProgress = function(element, progress)
            local visible = element.parent.data.visible
            element:SetClass("collapsed", not visible)
            if not visible then return end

            local maxPips = math.min(progress.slots, 20)
            local filled
            if progress.slots > 20 then
                local filledCount = math.floor((progress.done / progress.slots) * 20)
                filled = element.data.index <= filledCount
            else
                filled = progress.done >= element.data.index
            end
            element:SetClass("filled", filled)
            element:SetClass("collapsed", element.data.index > maxPips)
        end
    }

    for k,v in pairs(opts or {}) do
        options[k] = v
    end

    return gui.Panel(options)
end

--- @return Panel
function CharacterBuilder.ProgressBar(opts)

    local minPips = opts.minPips or 2
    opts.minPips = nil

    local options = {
        classes = {"builder-base", "panel-base", "progress-bar"},
        floating = true,
        valign = "bottom",
        halign = "center",
        vmargin = 4, --CBStyles.SIZES.PROGRESS_PIP_SIZE,
        data = {
            visible = false,
        },
        updateProgress = function(element, progress)
            element.data.visible = progress.slots >= minPips
            element:SetClass("collapsed", not element.data.visible)
            if not element.data.visible then return end

            local maxPips = math.min(progress.slots, 20)
            for i = #element.children + 1, maxPips do
                element:AddChild(CharacterBuilder.ProgressPip(i, {
                    rotate = 0,
                }))
            end
        end,
    }

    for k,v in pairs(opts) do
        options[k] = v
    end

    return gui.Panel(options)
end