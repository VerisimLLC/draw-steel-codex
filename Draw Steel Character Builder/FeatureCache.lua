--[[
    A cache and wrappers for our features
    to support the builder
]]
CBFeatureCache = RegisterGameType("CBFeatureCache")
CBFeatureWrapper = RegisterGameType("CBFeatureWrapper")
CBOptionWrapper = RegisterGameType("CBOptionWrapper")

local _formatOrder = CharacterBuilder._formatOrder
local _hasFn = CharacterBuilder._hasFn
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

--- @param guid string
--- @return CBFeatureWrapper|nil
function CBFeatureCache:GetFeature(guid)
    return self.keyed[guid]
end

--- @return table
function CBFeatureCache:GetFlattenedFeatures()
    return self.flattened
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

    local function addFeature(feature)
        if not passesPrereq(feature) then return end
        local cacheFeature = CBFeatureWrapper.CreateNew(hero, feature)
        if cacheFeature then
            local guid = cacheFeature:GetGuid()
            keyed[guid] = cacheFeature
            sorted[#sorted+1] = { guid = guid, order = cacheFeature:GetOrder() }
            if opts.allFeaturesComplete then opts.allFeaturesComplete = cacheFeature:IsComplete() end
        end
    end

    opts.allFeaturesComplete = true

    for _,item in ipairs(features) do
        if item.features ~= nil then
            for _,feature in ipairs(item.features) do
                flattened[#flattened+1] = { feature = feature }
                addFeature(feature)
            end
        elseif item.feature ~= nil then
            addFeature(item.feature)
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
--- @return CBFeatureWrapper|nil
function CBFeatureWrapper.CreateNew(hero, feature)
    if not feature.IsDerivedFrom("CharacterChoice") then return nil end

    local category = CBFeatureWrapper._deriveCategory(feature)
    local nameOrder, categoryOrder = CBFeatureWrapper._deriveOrder(feature, category)

    local newObj = CBFeatureWrapper.new{
        feature = feature,
        category = category,
        order = nameOrder,
        categoryOrder = categoryOrder,
        currentOptionId = nil,
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

--- Get the maximum number of target panels that should be visible
--- @return number
function CBFeatureWrapper:GetMaxVisibleTargets()
    return #self:GetSelected() + self:GetAvailableSlots()
end

--- @return string|nil
function CBFeatureWrapper:GetName()
    return self.feature:try_get("name", "Unnamed Feature")
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
            local pointCost = string.format(" (%d Points)", option:GetPointsCost())
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
    return self:GetSelectedValue() >= self:GetNumChoices()
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

function CBFeatureWrapper:UIChoicesFilter()
    local fn = self:_hasFn("OfferFilter")
    return fn and fn() or false
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
--- @return string nameOrder
--- @return string categoryOrder
function CBFeatureWrapper._deriveOrder(feature, category)
    local typeOrder = {
        -- Low numbers are reserved - stay between 100 & 998
        CharacterAspectChoice               = 101,
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

    local orderNum = typeOrder[feature.typeName] or 999
    local nameOrder = _formatOrder(orderNum, feature:try_get("name", "Unnamed Feature"))
    local catOrder = _formatOrder(orderNum, category)

    return nameOrder, catOrder
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
    local featureOptions = self.feature:GetOptions(levelChoices, hero)
    for _,option in ipairs(featureOptions) do
        local wrappedOption = CBOptionWrapper.CreateNew(option)
        options[#options+1] = wrappedOption
        optionsKeyed[wrappedOption:GetGuid()] = wrappedOption
    end
    table.sort(options, function(a,b) return a:GetOrder() < b:GetOrder() end)
    self.options = options
    self.optionsKeyed = optionsKeyed

    local choices = {}
    local choicesKeyed = {}
    local featureChoices = self.feature:Choices(1, self.selected, hero) or {}
    for _,choice in ipairs(featureChoices) do
        if _safeGet(choice, "hidden", false) == false then
            local wrappedChoice = CBOptionWrapper.CreateNew(choice)
            choices[#choices+1] = wrappedChoice
            choicesKeyed[wrappedChoice:GetGuid()] = wrappedChoice
        end
    end
    table.sort(choices, function(a,b) return a:GetOrder() < b:GetOrder() end)
    self.choices = choices
    self.choicesKeyed = choicesKeyed

    local pointsSpent = 0
    local selectedNames = {}
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

--- @return boolean
function CBOptionWrapper:HasCustomPanel()
    return _safeGet(self.option, "hasCustomPanel", false)
        and _safeGet(self.option, "panel", nil) ~= nil
end

--- @return function|nil
function CBOptionWrapper:Panel()
    return _safeGet(self.option, "panel", nil)
end

--- Set whether this option is selected on the hero.
function CBOptionWrapper:SetSelected(selected)
    self.isSelected = selected
end
