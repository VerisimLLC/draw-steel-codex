--[[
    A cache and wrappers for our features
    to support the builder
]]
CBFeatureCache = RegisterGameType("CBFeatureCache")
CBFeatureWrapper = RegisterGameType("CBFeatureWrapper")
CBOptionWrapper = RegisterGameType("CBOptionWrapper")

local _formatOrder = CharacterBuilder._formatOrder
local _hasFn = CharacterBuilder._hasFn
local _safeFeatureName = CharacterBuilder._safeFeatureName
local _safeGet = CharacterBuilder._safeGet

--[[
    Feature Cache
]]

--- Create a new feature cache
--- @param hero character The hero character
--- @param selectedId string GUID of the selected item
--- @param selectedName string Display name of the selected item
--- @param features table Array of feature details
--- @return CBFeatureCache
function CBFeatureCache.CreateNew(hero, selectedId, selectedName, features)

    local opts = {
        selectedId = selectedId,
        selectedName = selectedName,
    }

    CBFeatureCache._processFeatures(opts, hero, features)

    return CBFeatureCache.new(opts)
end

--- @return boolean
function CBFeatureCache:AllFeaturesComplete()
    return self:try_get("allFeaturesComplete", false)
end

--- Calculate and return status
--- @return table
function CBFeatureCache:CalculateStatus()
    local statusEntries = self:try_get("statusEntries", {})
    if #statusEntries > 0 then return statusEntries end

    local numSelected = 0
    local numAvailable = 0

    for _,item in ipairs(self:GetSortedFeatures()) do
        local feature = self:GetFeature(item.guid)
        if not feature:SuppressStatus() then
            local key = feature:GetCategoryOrder()
            if statusEntries[key] == nil then
                statusEntries[key] = {
                    id = feature:GetCategory(),
                    order = key,
                    available = 0,
                    selected = 0,
                    selectedDetail = {},
                }
            end
            local statusEntry = statusEntries[key]
            local featureStatus = feature:GetStatus()
            statusEntry.available = statusEntry.available + featureStatus.numChoices
            statusEntry.selected = statusEntry.selected + featureStatus.selected

            numSelected = numSelected + featureStatus.selected
            numAvailable = numAvailable + featureStatus.numChoices

            local selectedNames = featureStatus.selectedNames
            table.move(selectedNames, 1, #selectedNames, #statusEntry.selectedDetail + 1, statusEntry.selectedDetail)
            table.sort(statusEntry.selectedDetail)
        end
    end

    statusEntries = CharacterBuilder._toArray(statusEntries)

    self.numSelected = numSelected
    self.numAvailable = numAvailable
    self.statusEntries = statusEntries
    return statusEntries
end

--- @param guid string
--- @return CBFeatureWrapper|nil
function CBFeatureCache:GetFeature(guid)
    return self.keyed[guid]
end

--- @return table
function CBFeatureCache:GetFlattenedFeatures()
    return self.flattened
end

--- @return table
function CBFeatureCache:GetKeyedFeatures()
    return self.keyed
end

--- @return string key The key of the item selected on the hero
function CBFeatureCache:GetSelectedId()
    return self.selectedId
end

--- @return string name The name of the item selected on the hero
function CBFeatureCache:GetSelectedName()
    return self.selectedName
end

--- @return table
function CBFeatureCache:GetSortedFeatures()
    return self.sorted
end

--- @return integer numSelected
--- @return integer numAvailable
function CBFeatureCache:GetStatusSummary(hero)
    self:CalculateStatus(hero)
    return self:try_get("numSelected", 0), self:try_get("numAvailable", 0)
end

--- @param guid string
--- @return boolean|nil isComplete Whether that specific feature is complete or nil if we don't know about the feature
function CBFeatureCache:IsFeatureComplete(guid)
    local feature = self:GetFeature(guid)
    if feature then return feature:IsComplete() end
    return nil
end

--- @param opts table
--- @param hero character
--- @param features table
--- @private
function CBFeatureCache._processFeatures(opts, hero, features)
    local sorted = {}
    local flattened = {}
    local keyed = {}

    local function passesPrereq(feature)
        local prereq = feature:try_get("prerequisites")
        if prereq and #prereq > 0 then
            for _,pre in ipairs(prereq) do
                if not pre:Met(hero) then return false end
            end
        end
        return true
    end

    local function addFeature(feature, level)
        if not passesPrereq(feature) then return end
        local cacheFeature = CBFeatureWrapper.CreateNew(hero, feature, level)
        if cacheFeature then
            local guid = cacheFeature:GetGuid()
            keyed[guid] = cacheFeature
            sorted[#sorted+1] = { guid = guid, order = cacheFeature:GetOrder() }
            if opts.allFeaturesComplete then opts.allFeaturesComplete = cacheFeature:IsComplete() end
        end
    end

    opts.allFeaturesComplete = true

    for _,item in ipairs(features) do
        local itemFeatures = _safeGet(item, "features")
        local itemFeature = _safeGet(item, "feature")
        local levels = _safeGet(item, "levels")
        local level = levels and levels[1] or 0
        if itemFeatures ~= nil then
            for _,feature in ipairs(itemFeatures) do
                flattened[#flattened+1] = { feature = feature }
                addFeature(feature, level)
            end
        elseif itemFeature ~= nil then
            addFeature(item.feature, level)
        else
            flattened[#flattened+1] = { feature = item }
            addFeature(item, level)
        end
    end

    table.sort(sorted, function(a,b) return a.order < b.order end)

    opts.sorted = sorted
    opts.keyed = keyed
    opts.flattened = #flattened > 0 and flattened or features
end

--[[
    Feature Wrapper
]]

--- Create a new feature wrapper
--- @param hero character
--- @param feature CharacterChoice
--- @param level integer
--- @return CBFeatureWrapper|nil
function CBFeatureWrapper.CreateNew(hero, feature, level)
    if not feature.IsDerivedFrom("CharacterChoice") then return nil end

    -- if feature.name == "Zeitgeist" then print("THC:: FEATURE::", json(feature)) end

    local category = CBFeatureWrapper._deriveCategory(feature)
    local nameOrder, categoryOrder = CBFeatureWrapper._deriveOrder(feature, category, level)

    local newObj = CBFeatureWrapper.new{
        feature = feature,
        category = category,
        order = nameOrder,
        categoryOrder = categoryOrder,
        currentOptionId = nil,
        level = level,
    }

    newObj:Update(hero)

    return newObj
end

--- Determine whether to allow the current selected option
--- in the UI to be added to the hero.
--- @return boolean
function CBFeatureWrapper:AllowCurrentSelection()
    return self:AllowSelection(self:GetSelectedOptionId())
end

--- Determine whether we'll let the user select items into
--- the hero while items are already selected
--- @return boolean
function CBFeatureWrapper:AllowOverselect()
    return self:GetNumChoices() == 1
end

--- Determine whether to allow selection of a specific item
--- @id string
--- @return boolean
function CBFeatureWrapper:AllowSelection(id)
    local option = self:GetOption(id)
    if option == nil then return false end
    if self:AllowOverselect() then return true end
    local curVal = self:GetSelectedValue()
    return curVal + option:GetPointsCost() <= self:GetNumChoices()
end

--- @return boolean
function CBFeatureWrapper:CostsPoints()
    return self.feature:try_get("costsPoints", false)
end

--- @return number The number of slots available / unassigned on the hero
function CBFeatureWrapper:GetAvailableSlots()
    return math.max(0, self:GetNumChoices() - self:GetSelectedValue())
end

--- @return string
function CBFeatureWrapper:GetCategory()
    return self.category
end

function CBFeatureWrapper:GetCategoryOrder()
    return self:try_get("categoryOrder", _formatOrder(999, "zzz"))
end

--- @return CBOptionWrapper|nil
function CBFeatureWrapper:GetChoice(choiceId)
    return self:GetChoicesKeyed()[choiceId]
end

--- @return table
function CBFeatureWrapper:GetChoices()
    return self:try_get("choices", {})
end

--- @return table
function CBFeatureWrapper:GetChoicesKeyed()
    return self:try_get("choicesKeyed", {})
end

--- @return string
function CBFeatureWrapper:GetDescription()
    return self.feature:GetDescription()
end

--- @return string
function CBFeatureWrapper:GetDetailedSummaryText()
    if self:_hasFn("GetDetailedSummaryText") then
        return self.feature:GetDetailedSummaryText()
    end
    return self.feature:GetSummaryText()
end

--- Get the underlying feature
--- @return CharacterChoice
function CBFeatureWrapper:GetFeature()
    return self.feature
end

--- @return string
function CBFeatureWrapper:GetGuid()
    return self.feature.guid
end

--- @return integer|nil
function CBFeatureWrapper:GetLevel()
    return self:try_get("level")
end

--- Get the maximum number of target panels that should be visible
--- @return number
function CBFeatureWrapper:GetMaxVisibleTargets()
    return #self:GetSelected() + self:GetAvailableSlots()
end

--- @return string|nil
function CBFeatureWrapper:GetName()
    return _safeFeatureName(self.feature) --self.feature:try_get("name", "Unnamed Feature")
end

--- @return number
function CBFeatureWrapper:GetNumChoices()
    return self:try_get("numChoices", 1)
end

--- @return CBOptionWrapper|nil
function CBFeatureWrapper:GetOption(optionId)
    return self:GetOptionsKeyed()[optionId]
end

--- Calculate a display name including point cost if present
--- @param option CBOptionWrapper
--- @return string
function CBFeatureWrapper:GetOptionDisplayName(option)
    local name = option:GetName()
    if self:CostsPoints() then
        if not name:lower():find(" points)") then
            local pointCost = string.format(" (%d %s)", option:GetPointsCost(), self:GetPointsName())
            name = string.format("%s%s", name, pointCost)
        end
    end
    return name
end

--- Get the options as an array
--- @return table
function CBFeatureWrapper:GetOptions()
    return self:try_get("options", {})
end

function CBFeatureWrapper:GetOptionsCount()
    return #self:try_get("options", {})
end

--- @return table
function CBFeatureWrapper:GetOptionsKeyed()
    return self:try_get("optionsKeyed", {})
end

--- @return string
function CBFeatureWrapper:GetOrder()
    return self:try_get("order", _formatOrder(999, "zzz"))
end

--- @return string
function CBFeatureWrapper:GetPointsName()
    return _safeGet(self.feature, "pointsName", "Points")
end

--- @return RollTableReference
function CBFeatureWrapper:GetRollTable()
    return self.feature.characteristic:GetRollTable()
end

--- Get the list of items selected on the hero.
--- This is from levelChoices.
--- @return table
function CBFeatureWrapper:GetSelected()
    return self:try_get("selected", {})
end

--- Get the list of item names selected on the
--- hero as a sorted array. This is derived from
--- levelChoices.
--- @return table
function CBFeatureWrapper:GetSelectedNames()
    return self:try_get("selectedNames", {})
end

--- Get the option object currently selected
--- in the UI.
--- @return CBOptionWrapper|nil
function CBFeatureWrapper:GetSelectedOption()
    local id = self:GetSelectedOptionId()
    if id == nil then return nil end
    return self:GetOption(id)
end

--- Get the GUID of the option object currently
--- selected in the UI.
--- @return string|nil
function CBFeatureWrapper:GetSelectedOptionId()
    return self:try_get("currentOptionId")
end

--- Get the number of points spent on this feature
--- on the hero.
--- @return number
function CBFeatureWrapper:GetSelectedValue()
    return self:try_get("selectedValue", 0)
end

--- Return a status table with status details
--- @return table
function CBFeatureWrapper:GetStatus()
    local status = {
        numChoices = self:GetNumChoices(),
        selected = self:GetSelectedValue(),
        selectedNames = self:GetSelectedNames(),
    }
    local fn = self:_hasFn("GetStatus")
    if fn then
        local innerStatus = self.feature:GetStatus()
        for k,v in pairs(innerStatus) do
            status[k] = v
        end
    end
    return status
end

--- @return boolean
function CBFeatureWrapper:HasRoll()
    return self:try_get("hasRoll", false)
end

--- @return boolean
function CBFeatureWrapper:IsComplete()
    local status = self:GetStatus()
    return status.selected >= status.numChoices
end

--- Callback to support custom unsetting
--- @param hero character
--- @param optionWrapper CBOptionWrapper
--- @return boolean stopSave Return true to skip default save behavior
function CBFeatureWrapper:RemoveSelection(hero, optionWrapper)
    local fn = self:_hasFn("RemoveSelection")
    local haltSave = fn
        and type(fn) == "function"
        and fn(self:GetFeature(), hero, optionWrapper:GetOption())

    if haltSave then return true end

    return self:_removeLevelChoice(hero, optionWrapper)
end

--- Callback to support custom setting
--- @param hero character
--- @param optionWrapper CBOptionWrapper
--- @return boolean stopSave Return true to skip default save behavior
function CBFeatureWrapper:SaveSelection(hero, optionWrapper)
    local fn = self:_hasFn("SaveSelection")
    local haltSave = fn
        and type(fn) == "function"
        and fn(self:GetFeature(), hero, optionWrapper:GetOption())

    if haltSave then return true end

    return self:_applylevelChoice(hero, optionWrapper)
end

--- @return boolean Allowed - was the selection allowed
function CBFeatureWrapper:SetSelectedOption(optionId)
    local option = self:GetOption(optionId)
    if optionId == nil or option ~= nil then
        self.currentOptionId = optionId
        return true
    end
    return false
end

--- @return boolean
function CBFeatureWrapper:SuppressStatus()
    local fn = self:_hasFn("SuppressStatus")
    return fn and fn() or false
end

--- @return boolean
function CBFeatureWrapper:UIChoicesFilter()
    local filterDefaults = {
        CharacterFeatChoice = true,
        CharacterLanguageChoice = true,
        CharacterSkillChoice = true,
    }
    local fn = self:_hasFn("OfferFilter")
    if fn then return fn() end

    return filterDefaults[self.feature.typeName] or false
end

--- Return a structure of UI injections or nil
--- @return table
function CBFeatureWrapper:UIInjections()
    if self:_hasFn("UIInjections") then
        return self:GetFeature():UIInjections() or {}
    end
    return {}
end

--- Store data into the hero's levelChoices list
--- @param hero character
--- @param optionWrapper CBOptionWrapper
--- @return boolean saveSuccessful
function CBFeatureWrapper:_applylevelChoice(hero, optionWrapper)

    local levelChoices = hero:GetLevelChoices()
    if levelChoices then
        local choiceId = self:GetGuid()
        local selectedId = optionWrapper:GetGuid()
        local numChoices = self:GetNumChoices()
        if numChoices == nil or numChoices < 1 then numChoices = 1 end
        if (levelChoices[choiceId] == nil or numChoices == 1) and levelChoices[choiceId] ~= selectedId then
            levelChoices[choiceId] = { selectedId }
            return true
        else
            local alreadySelected = false
            for _,id in ipairs(levelChoices[choiceId]) do
                if id == selectedId then
                    alreadySelected = true
                    break
                end
            end
            if not alreadySelected then
                local option = self:GetOption(selectedId)
                local numChoices = self:GetNumChoices()
                local valueSelected = self:GetSelectedValue()
                local selectedCost = option:GetPointsCost()
                if numChoices >= valueSelected + selectedCost then
                    if numChoices > 1 then
                        levelChoices[choiceId][#levelChoices[choiceId]+1] = selectedId
                    else
                        levelChoices[choiceId][1] = selectedId
                    end
                    return true
                end
            end
        end
    end

    return false
end

--- Derive a category name from a feature
--- @param feature CharacterChoice
--- @return string
function CBFeatureWrapper._deriveCategory(feature)
    local translations = {
        CharacterAncestryInheritanceChoice = "Inherited Ancestry",
        CharacterFeatChoice = "Perk",
    }
    local typeName = feature.typeName
    if translations[typeName] then return translations[typeName] end

    -- Try to parse intelligently from the class name
    local catName = typeName:match("Character(.+)Choice")
    return catName:sub(1,1).. catName:sub(2):gsub("(%u)", " %1")
end

--- Derive sort order from feature type
--- @param feature CharacterChoice
--- @param category string
--- @param level integer
--- @return string nameOrder
--- @return string categoryOrder
function CBFeatureWrapper._deriveOrder(feature, category, level)
    local typeOrderTable = {
        -- Low numbers are reserved - stay between 100 & 998
        CharacterCultureAggregateChoice     = 102,
        CharacterAspectChoice               = 103,
        CharacterComplicationChoice         = 105,
        CharacterAncestryInheritanceChoice  = 110,
        CharacterCharacteristicChoice       = 120,
        CharacterDeityChoice                = 130,
        CharacterDomainChoice               = 140,
        CharacterSubclassChoice             = 150,
        CharacterFeatureChoice              = 160,
        CharacterSkillChoice                = 170,
        CharacterLanguageChoice             = 180,
        CharacterFeatChoice                 = 190,
        CharacterIncidentChoice             = 200,
    }

    local typeOrder = typeOrderTable[feature.typeName] or 999
    local levelOrder = level or 99
    local nameOrder = _formatOrder(levelOrder, _formatOrder(typeOrder, _safeFeatureName(feature)))
    local catOrder = _formatOrder(typeOrder, category)

    return nameOrder, catOrder
end

--- Determine whether to exclude the choice based on hero state
--- @param hero character
--- @param choice CBOptionWrapper
--- @return boolean
function CBFeatureWrapper:_excludeChoice(hero, choice)
    if choice:GetUnique() == false then return false end

    local validators = {
        CharacterDeityChoice = function(hero, choice)
            local levelChoices = hero:GetLevelChoices() or {}
            local featureId = self:GetGuid()
            local featureChoices = levelChoices[featureId] or {}
            local choiceId = choice:GetGuid()
            for _,id in ipairs(featureChoices) do
                if id == choiceId then return true end
            end
        end,
        CharacterLanguageChoice = function(hero, choice)
            local langsKnown = hero:LanguagesKnown() or {}
            return langsKnown[choice:GetGuid()] or false
        end,
        CharacterSkillChoice = function(hero, choice)
            local skillItem = dmhub.GetTableVisible(Skill.tableName)[choice:GetGuid()]
            if skillItem then return hero:ProficientInSkill(skillItem) end
            return false
        end,
    }

    local fn = validators[self.feature.typeName]
    if fn then return fn(hero, choice) end

    -- Look for it in any level choice
    local choiceId = choice:GetGuid()
    local levelChoices = hero:GetLevelChoices() or {}
    for _,featureChoices in pairs(levelChoices) do
        for _,id in ipairs(featureChoices) do
            if id == choiceId then return true end
        end
    end
    -- local featureChoices = levelChoices[self:GetGuid()] or {}
    -- for _,id in ipairs(featureChoices) do
    --     if id == choiceId then return true end
    -- end

    return false
end

--- Get the selected value, attempting to call the underlying feature to get it
--- @param hero character
--- @return table
function CBFeatureWrapper:_getSelected(hero)
    local fn = self:_hasFn("GetSelected")
    if fn then return fn(self:GetFeature(), hero) end
    local levelChoices = hero:GetLevelChoices()
    return levelChoices[self:GetGuid()] or {}
end

--- Determine if our wrapped feature has a specific function
--- @param fnName string
--- @return function|nil
function CBFeatureWrapper:_hasFn(fnName)
    return _hasFn(self:GetFeature(), fnName)
end

--- Remove an option from the hero's levelChoices list
--- @param hero character
--- @param optionWrapper CBOptionWrapper
--- @return boolean removeSuccessful
function CBFeatureWrapper:_removeLevelChoice(hero, optionWrapper)

    local levelChoices = hero:GetLevelChoices()
    if levelChoices == nil then return false end

    local levelChoice = levelChoices[self:GetGuid()]
    if levelChoice == nil then return false end

    for i = #levelChoice, 1, -1 do
        if levelChoice[i] == optionWrapper:GetGuid() then
            table.remove(levelChoice, i)
            return true
        end
    end

    return false
end

--- Update cached state from current hero selections
--- TODO: Perf optimization: Call this only when first accessing a method.
--- @param hero character
function CBFeatureWrapper:Update(hero)
    local levelChoices = hero:GetLevelChoices()

    self.selected = self:_getSelected(hero)
    self.numChoices = self.feature:NumChoices(hero)

    local options = {}
    local optionsKeyed = {}
    local choices = {}
    local choicesKeyed = {}
    local pointsSpent = 0
    local selectedNames = {}

    if _hasFn(self.feature, "GetEntries") then
        local featureEntries = self.feature:GetEntries(hero)
        for _,entry in ipairs(featureEntries) do
            local wrappedEntry = CBOptionWrapper.CreateNew(entry)
            options[#options+1] = wrappedEntry
            optionsKeyed[wrappedEntry:GetGuid()] = wrappedEntry
            if _safeGet(entry, "hidden", false) == false then
                if not self:_excludeChoice(hero, wrappedEntry) then
                    choices[#choices+1] = wrappedEntry
                    choicesKeyed[wrappedEntry:GetGuid()] = wrappedEntry
                end
            end
        end
    else
        -- TODO: Remove this once we've refactored all choice types
        local featureOptions = self.feature:GetOptions(levelChoices, hero)
        for _,option in ipairs(featureOptions) do
            local wrappedOption = CBOptionWrapper.CreateNew(option)
            options[#options+1] = wrappedOption
            optionsKeyed[wrappedOption:GetGuid()] = wrappedOption
        end
        local featureChoices = self.feature:Choices(1, self.selected, hero) or {}
        for _,choice in ipairs(featureChoices) do
            if _safeGet(choice, "hidden", false) == false then
                local wrappedChoice = CBOptionWrapper.CreateNew(choice)
                if not self:_excludeChoice(hero, wrappedChoice) then
                    choices[#choices+1] = wrappedChoice
                    choicesKeyed[wrappedChoice:GetGuid()] = wrappedChoice
                end
            end
        end
    end

    table.sort(options, function(a,b) return a:GetOrder() < b:GetOrder() end)
    table.sort(choices, function(a,b) return a:GetOrder() < b:GetOrder() end)

    self.options = options
    self.optionsKeyed = optionsKeyed
    self.choices = choices
    self.choicesKeyed = choicesKeyed

    for _,id in ipairs(self.selected) do
        if optionsKeyed[id] then
            pointsSpent = pointsSpent + optionsKeyed[id]:GetPointsCost()
            selectedNames[#selectedNames+1] = optionsKeyed[id]:GetName()
            optionsKeyed[id]:SetSelected(true)
        end
        if choicesKeyed[id] then
            choicesKeyed[id]:SetSelected(true)
        end
    end
    table.sort(selectedNames)
    self.selectedValue = pointsSpent
    self.selectedNames = selectedNames

    self.hasRoll = self.feature:try_get("characteristic") ~= nil
end

--[[
    Option Wrapper
]]

--- @param option table
--- @return CBOptionWrapper
function CBOptionWrapper.CreateNew(option)
    return CBOptionWrapper.new{
        option = option,
        isSelected = false,
    }
end

--- @return string|nil
function CBOptionWrapper:GetDescription()
    return _safeGet(self.option, "description")
end

--- @return string
function CBOptionWrapper:GetGuid()
    return _safeGet(self.option, "guid", _safeGet(self.option, "id"))
end

--- @return string
function CBOptionWrapper:GetName()
    return _safeGet(self.option, "name", _safeGet(self.option, "text"))
end

--- Get the underlying option object
--- @return table
function CBOptionWrapper:GetOption()
    return self.option
end

--- @return string
function CBOptionWrapper:GetOrder()
    return _safeGet(self.option, "order", self:GetName())
end

--- @return number
function CBOptionWrapper:GetPointsCost()
    return _safeGet(self.option, "pointsCost", 1)
end

--- @return string|nil
function CBOptionWrapper:GetRollRange()
    return _safeGet(self.option, "rollRange")
end

--- @return table
function CBOptionWrapper:GetRow()
    return self.option.row
end

--- Get whether this option is selected on the hero.
--- @return boolean
function CBOptionWrapper:GetSelected()
    return self:try_get("isSelected", false)
end

--- @return boolean
function CBOptionWrapper:GetUnique()
    -- TODO: Maybe the default should be false
    return _safeGet(self.option, "unique", true)
end

--- @return function|nil
function CBOptionWrapper:Panel()
    -- if self:GetName() == "Harsh Critic" then print("THC:: PANEL::", json(self.option)) end

    local function evaluateModifier(modifier)
        -- if self:GetName() == "Harsh Critic" then print("THC:: EVALMOD::", modifier.behavior or "nil", json(modifier)) end
        if modifier.behavior == "activated" or modifier.behavior == "triggerdisplay" or modifier.behavior == "routine" then
            local ability = rawget(modifier, cond(modifier.behavior == "activated", "activatedAbility", "ability"))
            -- if self:GetName() == "Harsh Critic" then print("THC:: EVALMOD::", ability ~= nil, json(ability)) end
            if ability ~= nil then
                -- if self:GetName() == "Harsh Critic" then print("THC:: RETURNPANEL::") end
                return function()
                    return ability:Render({
                        width = "96%",
                        halign = "center",
                        bgimage = true,
                        bgcolor = CBStyles.COLORS.BLACK03}, {})
                end
            end
        end
    end

    -- if self:GetName() == "Harsh Critic" then print("THC:: STEP_1::") end
    -- See if we can calculate a panel from modifiers
    local function processModifiers(modifiers)
        for _,modifier in ipairs(modifiers) do
            local fn = evaluateModifier(modifier)
            if fn then return fn end
        end
    end
    local modifiers = _safeGet(self.option, "modifiers", {})
    local fn = processModifiers(modifiers)
    if fn then return fn end

    -- if self:GetName() == "Harsh Critic" then print("THC:: STEP_2::") end
    -- See if we can calculate a panel from modifierInfo
    local modifierInfo = _safeGet(self.option, "modifierInfo")
    if modifierInfo then
        for _,feature in ipairs(modifierInfo:try_get("features", {})) do
            for _,modifier in ipairs(feature:try_get("modifiers", {})) do
                local fn = evaluateModifier(modifier)
                if fn then return fn end
            end
        end
    end

    -- Check if we can calculate a panel from features
    local features = _safeGet(self.option, "features")
    if features then
        local panelFn = {}
        local text = {}
        for _,feature in ipairs(features) do
            local modifiers = _safeGet(feature, "modifiers", {})
            local fn = processModifiers(modifiers)
            if fn then
                panelFn[#panelFn+1] = fn
            elseif _hasFn(feature, "GetDescription") then
                local t = feature:GetDescription()
                if t and #t > 0 then text[#text+1] = t end
            end
        end
        if #panelFn == 1 and #text == 0 then return panelFn[1] end
        if #panelFn > 0 or #text > 0 then
            local t = table.concat(text, "\n")
            return function()
                local children = {}
                if #t > 0 then
                    children[#children+1] = gui.Label{
                        classes = {"builder-base", "label", "info"},
                        width = "98%",
                        height = "auto",
                        halign = "left",
                        vmargin = 12,
                        textAlignment = "topleft",
                        text = t,
                    }
                end
                for _,fn in ipairs(panelFn) do
                    children[#children+1] = fn()
                end
                return gui.Panel{
                    classes = {"builder-base", "panel-base", "container"},
                    width = "90%",
                    height = "auto",
                    halign = "center",
                    valign = "top",
                    children = children,
                }
            end
        end
    end

    -- if self:GetName() == "Harsh Critic" then print("THC:: STEP_3::") end
    -- Check if raw option has CreateDropdownPanel method (from GetOptions())
    local option = self.option
    if type(_safeGet(option, "CreateDropdownPanel")) == "function" then
        return function()
            return option:CreateDropdownPanel(self:GetName())
        end
    end

    if type(_safeGet(option, "render")) == "function" then
        return option.render
    end

    -- It has a panel built in (from Choices())
    -- local fn = _safeGet(self.option, "panel", nil)
    -- if fn ~= nil then return fn end

    -- if self:GetName() == "Harsh Critic" then print("THC:: STEP_4::") end
    -- No panel
    return nil
end

--- Set whether this option is selected on the hero.
function CBOptionWrapper:SetSelected(selected)
    self.isSelected = selected
end
