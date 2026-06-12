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

-- Controls the ordering of choices in column 2 and the build summary
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
    SignatureAbilityPlaceholder         = 155,
    CharacterFeatureChoice              = 160,
    CharacterSkillChoice                = 170,
    CharacterLanguageChoice             = 180,
    CharacterFeatChoice                 = 190,
    CharacterIncidentChoice             = 200,
}

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
            local featureStatus = feature:GetStatus()
            local excludeFromTotals = featureStatus.excludeFromTotals == true
            local skip = excludeFromTotals
                and featureStatus.numChoices == 0
                and featureStatus.selected == 0
            if not skip then
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
                statusEntry.available = statusEntry.available + featureStatus.numChoices
                statusEntry.selected = statusEntry.selected + featureStatus.selected

                if excludeFromTotals then
                    statusEntry.excludeFromTotals = true
                else
                    numSelected = numSelected + featureStatus.selected
                    numAvailable = numAvailable + featureStatus.numChoices
                end

                local selectedNames = featureStatus.selectedNames
                table.move(selectedNames, 1, #selectedNames, #statusEntry.selectedDetail + 1, statusEntry.selectedDetail)
                table.sort(statusEntry.selectedDetail)
            end
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

--- Transfer UI-only selection state from an old cache to this one.
--- Preserves currentOptionId across cache rebuilds for features
--- that exist in both caches (matched by GUID).
--- @param oldCache CBFeatureCache|nil
function CBFeatureCache:TransferUISelections(oldCache)
    if oldCache == nil then return end
    for guid, feature in pairs(self.keyed) do
        local oldFeature = oldCache:GetFeature(guid)
        if oldFeature then
            local optionId = oldFeature:GetSelectedOptionId()
            if optionId then
                feature:SetSelectedOption(optionId)
            end
        end
    end
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

--- The display name a points pool falls back to when no explicit name is set.
--- Kept in sync with DEFAULT_POINTS_NAME in MCDMCustomRules.lua.
CBFeatureWrapper.DEFAULT_POINTS_NAME = "Points"

--- The display name of the points pool this feature draws from. Falls back to
--- CBFeatureWrapper.DEFAULT_POINTS_NAME ("Points") when the editor's "Points
--- name" field has been left blank.
--- @return string
function CBFeatureWrapper:GetPointsName()
    local name = self.feature:try_get("pointsName")
    if name == nil or name == "" then
        return CBFeatureWrapper.DEFAULT_POINTS_NAME
    end
    return name
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
    if self:IsUnbounded() then
        -- Show every filled slot plus one empty slot to fill next.
        return #self:GetSelected() + 1
    end
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

--- The choice count at or above which a feature is treated as offering an
--- effectively unbounded number of choices.
CBFeatureWrapper.UNBOUNDED_CHOICES = 99

--- Determine whether this feature offers an effectively unbounded number of
--- choices. When unbounded, the UI shows only the filled slots plus a single
--- extra empty slot rather than a slot for every possible choice.
--- @return boolean
function CBFeatureWrapper:IsUnbounded()
    return self:GetNumChoices() >= CBFeatureWrapper.UNBOUNDED_CHOICES
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
    -- An unbounded feature has no required number of selections, so it is
    -- never "incomplete" -- otherwise it could never be satisfied.
    if self:IsUnbounded() then return true end
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

--- Determine whether a table has a signature ability categorization within it, anywhere
--- @param t table
--- @return boolean
function CBFeatureWrapper._hasSignature(t, visited)
    visited = visited or {}
    if visited[t] then return false end
    visited[t] = true

    local searchText = "Signature Ability"
    if _safeGet(t, "categorization") == searchText then return true end

    for _,v in pairs(t) do
        if type(v) == "table" then
            if CBFeatureWrapper._hasSignature(v, visited) then
                return true
            end
        end
    end

    return false
end

--- Derive sort order from feature type
--- @param feature CharacterChoice
--- @param category string
--- @param level integer
--- @return string nameOrder
--- @return string categoryOrder
function CBFeatureWrapper._deriveOrder(feature, category, level)

    local hasSignature = false
    local options = feature:try_get("options")
    if options ~= nil and #options > 0 then
        hasSignature = CBFeatureWrapper._hasSignature(options[1])
    end
    local typeName = hasSignature and "SignatureAbilityPlaceholder" or feature.typeName
    local typeOrder =typeOrderTable[typeName] or 999
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
    local result = _safeGet(self.option, "description")


    --if we don't have a description set, but have an activated ability, then use its flavor text as a description
    if result == nil or result == "" then
        local modifiers = _safeGet(self.option, "modifiers", {})
        if modifiers ~= nil and #modifiers > 0 and modifiers[1].behavior == "activated" then
            local result = modifiers[1].activatedAbility:try_get("flavor", "")
            return result
        end
    end

    return result
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

--- Calculate a custom panel for the option. Typically used when
--- the option has an ability or other key descriptive text.
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

--[[
    Feature Categoriser  (search redesign -- chunk 3)

    A standalone, NO-UI module that produces a categorised per-creature feature
    index. It classifies every feature a creature has into a canonical display
    bucket (Ancestry / Culture / Career / Class / Kit / Perk / Title /
    Complication / Skill / Language / Trait / Treasure / Condition / Ongoing
    Effect / Aura) and returns both a flat list and a grouped-by-bucket view with
    counts. It changes no game state and renders nothing.

    Consumers (later chunks): the global-search "features on this creature"
    provider (ch4), the character-sheet Features tab redesign (ch5), and the
    tac-panel Features section (ch6). It lives here, alongside CBFeatureWrapper's
    CharacterFeatChoice -> "Perk" map, to satisfy the no-new-files constraint.

    It is a per-CREATURE capability: it runs on PCs, monsters, retainers and
    followers. For characters it reads the structured build pipeline
    GetClassFeaturesAndChoicesWithDetails(), which tags every entry with its true
    ORIGIN object (class / race / background / culture + aspects / kit / feat) and
    level metadata -- far more reliable than the flat feature "source" string,
    which mislabels Perks, Titles and Complications all as "Feat". For ALL
    creatures it then unions the active/equipped state -- direct creature features
    (monster traits), equipped treasures, active conditions, ongoing effects and
    auras -- and dedupes by guid. Game-wide global rule mods are deliberately
    excluded (identical on every creature; they belong to search, not a per-
    creature list, and never appear in the sources enumerated here anyway).

    Classification is three layers, in priority order:
      (1) origin-object type override -- a Title or CharacterComplication arrives
          under the generic "feat" origin key but is a distinct type, so the
          origin OBJECT's type wins;
      (2) choice-slot type override -- a CharacterFeatChoice / CharacterSkillChoice
          / CharacterLanguageChoice slot represents the thing being chosen (a
          Perk / Skill / Language), not its host level, so it is peeled out even
          when it arrives under a "class" origin key;
      (3) primary bucket from the origin key (class -> Class, race -> Ancestry,
          etc.), with a typeName-derived fallback.

    SAFETY: GetClassFeaturesAndChoicesWithDetails is a character-only method and
    the engine ERRORS (it does not return nil) if the field is even read on a
    monster, so the character branch is gated on creature.typeName == "character".
    Every engine call below is pcall-guarded so a single misbehaving source can
    never break the index or, more importantly, the load of this file.
]]

FeatureCategoriser = {}

--- Canonical buckets in display order. `id` is a stable grouping key (relied on
--- by later UI); `order` drives sorting. "other" is the catch-all backstop.
FeatureCategoriser.BUCKETS = {
    { id = "ancestry",     name = "Ancestry",        order = 100 },
    { id = "culture",      name = "Culture",         order = 110 },
    { id = "career",       name = "Career",          order = 120 },
    { id = "class",        name = "Class",           order = 130 },
    { id = "kit",          name = "Kit",             order = 140 },
    { id = "perk",         name = "Perk",            order = 150 },
    { id = "title",        name = "Title",           order = 160 },
    { id = "complication", name = "Complication",    order = 170 },
    { id = "skill",        name = "Skill",           order = 180 },
    { id = "language",     name = "Language",         order = 190 },
    { id = "trait",        name = "Trait",           order = 200 },
    { id = "treasure",     name = "Treasure",        order = 210 },
    { id = "condition",    name = "Condition",       order = 220 },
    { id = "effect",       name = "Ongoing Effect",  order = 230 },
    { id = "aura",         name = "Aura",            order = 240 },
    { id = "other",        name = "Other",           order = 900 },
}

--- id -> bucket descriptor
FeatureCategoriser.BUCKET_BY_ID = {}
for _,b in ipairs(FeatureCategoriser.BUCKETS) do
    FeatureCategoriser.BUCKET_BY_ID[b.id] = b
end

--- Origin key (the non-feature/levels key on a WithDetails entry) -> bucket id.
--- The culture aspects (environment / upbringing / organization) all roll up
--- into Culture. "feat" defaults to Perk; the Title / Complication overrides in
--- layer 1 peel those out first.
local CATEGORISER_ORIGIN_BUCKET = {
    class        = "class",
    race         = "ancestry",
    background    = "career",
    culture      = "culture",
    environment  = "culture",
    upbringing   = "culture",
    organization = "culture",
    kit          = "kit",
    feat         = "perk",
}

--- Choice-slot typeName -> bucket id. A choice slot stands in for the thing being
--- chosen, so it is bucketed by what it offers rather than by its host origin.
local CATEGORISER_CHOICE_BUCKET = {
    CharacterFeatChoice                = "perk",
    CharacterSkillChoice               = "skill",
    CharacterLanguageChoice            = "language",
    CharacterAncestryInheritanceChoice = "ancestry",
}

--- pcall-guarded IsDerivedFrom. The engine's type registry can error on an
--- unknown type name, so this never propagates.
--- @param obj any
--- @param typeName string
--- @return boolean
local function categoriserIsDerived(obj, typeName)
    if obj == nil or type(obj.IsDerivedFrom) ~= "function" then return false end
    local ok, res = pcall(function() return obj.IsDerivedFrom(typeName) end)
    return ok and res == true
end

--- The origin key + origin object carried on a WithDetails entry, e.g.
--- ("class", <Class>) or ("feat", <Title>). Returns nil,nil if absent.
--- @param entry table
--- @return string|nil originKey
--- @return any originObj
local function categoriserEntryOrigin(entry)
    for k,v in pairs(entry) do
        if k ~= "feature" and k ~= "levels" then return k, v end
    end
    return nil, nil
end

--- A human-readable name for an origin object (e.g. "Censor", "Human", "Agent").
--- @param originObj any
--- @return string|nil
local function categoriserOriginName(originObj)
    if originObj == nil then return nil end
    local name = _safeGet(originObj, "name")
    if name == nil or name == "" then return nil end
    return name
end

--- Classify a single GetClassFeaturesAndChoicesWithDetails entry into a bucket
--- id. Pure function (no creature state read); this is the validated core.
--- @param entry table { <originKey> = originObj, levels = {ints}?, feature = CharacterChoice|CharacterFeature }
--- @return string bucketId
function FeatureCategoriser.ClassifyEntry(entry)
    if entry == nil then return "other" end

    local originKey, originObj = categoriserEntryOrigin(entry)

    -- Layer 1: origin-object type override. Title and Complication both arrive
    -- under the "feat" origin key but are distinct types; the origin object's
    -- own type is the reliable discriminator (the resolved feature is a plain
    -- CharacterFeature and does not report these types).
    if categoriserIsDerived(originObj, "Title") then return "title" end
    if categoriserIsDerived(originObj, "CharacterComplication") then return "complication" end

    -- Layer 2: choice-slot type override. A Perk / Skill / Language slot is
    -- bucketed by what it offers, even when hosted under a "class" origin key
    -- (this is what rescues a Perk choice from being mislabelled Class).
    local feature = entry.feature
    local typeName = feature ~= nil and feature.typeName or nil
    if typeName ~= nil and CATEGORISER_CHOICE_BUCKET[typeName] ~= nil then
        return CATEGORISER_CHOICE_BUCKET[typeName]
    end

    -- Layer 3a: primary bucket from the origin key.
    if originKey ~= nil and CATEGORISER_ORIGIN_BUCKET[originKey] ~= nil then
        return CATEGORISER_ORIGIN_BUCKET[originKey]
    end

    -- Layer 3b: typeName-derived fallback for unmapped origins, mirroring
    -- CBFeatureWrapper._deriveCategory's "CharacterXChoice -> X" parse so novel
    -- choice types degrade to a sensible-ish bucket rather than "Other".
    if typeName ~= nil then
        local parsed = typeName:match("Character(.+)Choice")
        if parsed ~= nil then
            local lowered = parsed:lower()
            if FeatureCategoriser.BUCKET_BY_ID[lowered] ~= nil then return lowered end
        end
    end

    return "other"
end

--- Build a normalised entry table from already-extracted parts. Centralised so
--- every source emits the same shape.
--- @return table
local function categoriserNormalise(args)
    return {
        guid       = args.guid,
        name       = args.name,
        bucket     = args.bucket,
        source     = args.source,
        originName = args.originName,
        levels     = args.levels,
        level      = args.level,
        kind       = args.kind,
        feature    = args.feature,
        entry      = args.entry,
    }
end

--- Add the character build-pipeline features (character-only). No-op for any
--- non-character creature -- the field itself errors if read on a monster.
--- @param creature creature
--- @param addEntry function
local function categoriserAddBuildFeatures(creature, addEntry)
    if creature.typeName ~= "character" then return end

    local ok, details = pcall(function() return creature:GetClassFeaturesAndChoicesWithDetails() end)
    if not ok or type(details) ~= "table" then return end

    for _,entry in ipairs(details) do
        local feature = entry.feature
        if feature ~= nil then
            local _, originObj = categoriserEntryOrigin(entry)
            local levels = entry.levels
            addEntry(categoriserNormalise{
                guid       = _safeGet(feature, "guid"),
                name       = _safeFeatureName(feature),
                bucket     = FeatureCategoriser.ClassifyEntry(entry),
                source     = _safeGet(feature, "source"),
                originName = categoriserOriginName(originObj),
                levels     = levels,
                level      = (levels ~= nil and levels[1]) or nil,
                kind       = "build",
                feature    = feature,
                entry      = entry,
            })
        end
    end
end

--- Add direct creature features. For monsters these are traits (source
--- "Trait"); for characters this list usually holds special direct grants.
--- Classified as a Trait by default, but a Title / Complication grant is still
--- peeled out via its own type.
--- @param creature creature
--- @param addEntry function
local function categoriserAddCreatureFeatures(creature, addEntry)
    local ok, feats = pcall(function() return creature:try_get("characterFeatures", {}) end)
    if not ok or type(feats) ~= "table" then return end

    for _,feature in ipairs(feats) do
        if feature ~= nil then
            local bucket = "trait"
            if categoriserIsDerived(feature, "Title") then bucket = "title"
            elseif categoriserIsDerived(feature, "CharacterComplication") then bucket = "complication" end
            addEntry(categoriserNormalise{
                guid    = _safeGet(feature, "guid"),
                name    = _safeFeatureName(feature),
                bucket  = bucket,
                source  = _safeGet(feature, "source"),
                kind    = "trait",
                feature = feature,
            })
        end
    end
end

--- Add active ongoing effects. An effect instance carries no name of its own --
--- only an `ongoingEffectid` into the ongoing-effects table -- so the display
--- name is resolved there, and the instance `id` is the dedupe key.
--- @param creature creature
--- @param addEntry function
local function categoriserAddOngoingEffects(creature, addEntry)
    if type(creature.ActiveOngoingEffects) ~= "function" then return end
    local ok, effects = pcall(function() return creature:ActiveOngoingEffects() end)
    if not ok or type(effects) ~= "table" then return end

    local effectTable = nil
    if CharacterOngoingEffect ~= nil and CharacterOngoingEffect.tableName ~= nil then
        local okt, t = pcall(function() return dmhub.GetTable(CharacterOngoingEffect.tableName) end)
        if okt then effectTable = t end
    end

    for _,effect in ipairs(effects) do
        if effect ~= nil then
            local effectId = _safeGet(effect, "ongoingEffectid")
            local name = nil
            if effectTable ~= nil and effectId ~= nil and effectTable[effectId] ~= nil then
                name = _safeGet(effectTable[effectId], "name")
            end
            addEntry(categoriserNormalise{
                guid    = _safeGet(effect, "id", effectId),
                name    = name or "Ongoing Effect",
                bucket  = "effect",
                kind    = "effect",
                feature = effect,
            })
        end
    end
end

--- Add active conditions (the creature's currently inflicted conditions).
--- @param creature creature
--- @param addEntry function
local function categoriserAddConditions(creature, addEntry)
    local ok, conditions = pcall(function() return creature:try_get("inflictedConditions", {}) end)
    if not ok or type(conditions) ~= "table" then return end

    local condTable = nil
    if CharacterCondition ~= nil and CharacterCondition.tableName ~= nil then
        local okt, t = pcall(function() return dmhub.GetTable(CharacterCondition.tableName) end)
        if okt then condTable = t end
    end

    for key,instance in pairs(conditions) do
        -- The inflictedConditions map is keyed by condition id; resolve a display
        -- name from the conditions table when possible, else fall back to the key.
        local condId = (type(instance) == "table" and _safeGet(instance, "conditionid")) or key
        local name = nil
        if condTable ~= nil and condId ~= nil and condTable[condId] ~= nil then
            name = _safeGet(condTable[condId], "name")
        end
        addEntry(categoriserNormalise{
            guid    = tostring(condId),
            name    = name or tostring(condId),
            bucket  = "condition",
            kind    = "condition",
            feature = (type(instance) == "table") and instance or nil,
        })
    end
end

--- Add auras present on the creature.
--- @param creature creature
--- @param addEntry function
local function categoriserAddAuras(creature, addEntry)
    if type(creature.GetAuras) ~= "function" then return end
    local ok, auras = pcall(function() return creature:GetAuras() end)
    if not ok or type(auras) ~= "table" then return end

    for _,aura in ipairs(auras) do
        if aura ~= nil then
            addEntry(categoriserNormalise{
                guid    = _safeGet(aura, "guid"),
                name    = _safeGet(aura, "name", "Aura"),
                bucket  = "aura",
                kind    = "aura",
                feature = aura,
            })
        end
    end
end

--- Add equipped treasures (magic items / gear granting features). Best-effort:
--- Equipment() returns a { slotName -> itemGuid } map, so each guid is resolved
--- against the gear table for a display name. Dedupe by item guid handles an
--- item occupying multiple slots (e.g. a two-handed weapon).
--- @param creature creature
--- @param addEntry function
local function categoriserAddTreasures(creature, addEntry)
    if type(creature.Equipment) ~= "function" then return end
    local ok, equipment = pcall(function() return creature:Equipment() end)
    if not ok or type(equipment) ~= "table" then return end

    local gearTable = nil
    local okg, t = pcall(function() return dmhub.GetTable("tbl_Gear") end)
    if okg then gearTable = t end

    for _,itemGuid in pairs(equipment) do
        if type(itemGuid) == "string" then
            local item = gearTable ~= nil and gearTable[itemGuid] or nil
            local name = item ~= nil and _safeGet(item, "name") or nil
            addEntry(categoriserNormalise{
                guid    = itemGuid,
                name    = name or "Treasure",
                bucket  = "treasure",
                kind    = "treasure",
                feature = item,
            })
        end
    end
end

--- Build the categorised per-creature feature index.
---
--- Returns:
---   features : array of normalised entries (see categoriserNormalise) in source
---              order, deduped by guid.
---   groups   : { [bucketId] = { bucket = <descriptor>, items = { entry, ... } } }
---   order    : array of bucket ids that actually have entries, in display order.
---   counts   : { [bucketId] = n }
---   total    : total entry count.
---
--- @param creature creature
--- @return table index
function FeatureCategoriser.BuildIndex(creature)
    local features = {}
    local seenGuid = {}

    local function addEntry(norm)
        if norm == nil then return end
        local guid = norm.guid
        if guid ~= nil then
            if seenGuid[guid] then return end
            seenGuid[guid] = true
        end
        features[#features+1] = norm
    end

    if creature ~= nil then
        categoriserAddBuildFeatures(creature, addEntry)
        categoriserAddCreatureFeatures(creature, addEntry)
        categoriserAddTreasures(creature, addEntry)
        categoriserAddConditions(creature, addEntry)
        categoriserAddOngoingEffects(creature, addEntry)
        categoriserAddAuras(creature, addEntry)
    end

    -- Group + count.
    local groups = {}
    local counts = {}
    for _,entry in ipairs(features) do
        local bucketId = entry.bucket or "other"
        local group = groups[bucketId]
        if group == nil then
            group = { bucket = FeatureCategoriser.BUCKET_BY_ID[bucketId] or FeatureCategoriser.BUCKET_BY_ID["other"], items = {} }
            groups[bucketId] = group
        end
        group.items[#group.items+1] = entry
        counts[bucketId] = (counts[bucketId] or 0) + 1
    end

    -- Non-empty bucket ids in display order.
    local order = {}
    for _,b in ipairs(FeatureCategoriser.BUCKETS) do
        if groups[b.id] ~= nil then order[#order+1] = b.id end
    end

    return {
        features = features,
        groups   = groups,
        order    = order,
        counts   = counts,
        total    = #features,
    }
end

--- Short-TTL memo over BuildIndex. Features rarely change mid-keystroke, so a
--- 1-second time-to-live is simpler and sufficient (vs event-driven
--- invalidation) for the search provider's repeated calls. Keyed by the creature
--- table identity; the cache self-prunes lazily as stale entries are replaced.
local CATEGORISER_CACHE_TTL = 1.0
local g_categoriserCache = setmetatable({}, { __mode = "k" })

--- @param creature creature
--- @return table index
function FeatureCategoriser.BuildIndexCached(creature)
    if creature == nil then return FeatureCategoriser.BuildIndex(creature) end

    local now = dmhub.Time()
    local cached = g_categoriserCache[creature]
    if cached ~= nil and (now - cached.time) < CATEGORISER_CACHE_TTL then
        return cached.index
    end

    local index = FeatureCategoriser.BuildIndex(creature)
    g_categoriserCache[creature] = { time = now, index = index }
    return index
end

-- =============================================================================
-- Global-search provider: features on creatures (search redesign ch4).
--
-- Surfaces the categorised per-creature feature index (FeatureCategoriser,
-- above) in global search: searching "healing grace" finds the feature ON the
-- token that has it, not just its compendium definition. One result row per
-- (feature, token) pair -- the same feature on two tokens is two locations.
--
-- Activation is the COARSE click-through agreed in the plan review: select the
-- token, centre the camera on it, open its sheet and land on the Features tab
-- (via the selectSheetTab deep-link hook in DrawSteelChararcterSheet.lua).
-- When the ch5 Features-tab redesign lands this upgrades to filter-to-feature.
--
-- Visibility: a user only sees features on tokens they can control (owner /
-- party / GM -- token.canControl), so players never discover monster traits
-- or other GM content through search.
-- =============================================================================

local mod = dmhub.GetModLoading()

--- Open a token's character sheet landed on the Features tab. The sheet panel
--- is created on demand by the engine, so the tab selection retries briefly
--- until CharacterSheet.instance exists.
--- @param tokenid string
local function OpenSheetAtFeaturesTab(tokenid)
    local tok = dmhub.GetTokenById(tokenid)
    if tok == nil then
        return
    end

    tok:ShowSheet()

    local attempts = 0
    local function trySelect()
        if mod.unloaded then
            return
        end
        local sheet = rawget(CharacterSheet, "instance")
        if sheet ~= nil and sheet ~= false and sheet.valid then
            sheet:FireEventTree("selectSheetTab", "Features")
            return
        end
        attempts = attempts + 1
        if attempts < 20 then
            dmhub.Schedule(0.1, trySelect)
        end
    end
    trySelect()
end

Search.RegisterProvider{
    id = "creatureFeatures",
    bucket = "ingame",
    enumerate = function(needle)
        if not dmhub.inGame then
            return {}
        end

        local results = {}
        for _,token in ipairs(dmhub.allTokens) do
            local props = token.properties
            if props ~= nil and token.canControl then
                local tokenName = token.name
                if type(tokenName) ~= "string" or tokenName == "" then
                    tokenName = "Unnamed"
                end
                local index = FeatureCategoriser.BuildIndexCached(props)
                for _,entry in ipairs(index.features) do
                    local name = entry.name
                    if type(name) == "string" and Search.MatchesText(name, needle) then
                        local capturedId = token.id
                        local bucket = FeatureCategoriser.BUCKET_BY_ID[entry.bucket]
                        results[#results+1] = {
                            name = name,
                            score = Search.Score(name, needle),
                            typeLabel = (bucket ~= nil and bucket.name) or "Feature",
                            subLabel = string.format("On %s", tokenName),
                            activate = function()
                                dmhub.SelectToken(capturedId)
                                dmhub.CenterOnToken(capturedId)
                                OpenSheetAtFeaturesTab(capturedId)
                            end,
                        }
                    end
                end
            end
        end
        return results
    end,
}
