--[[
    Main panel of the Character Builder
]]
local _filterFeatures = CharacterBuilder._filterFeatures
local _getHero = CharacterBuilder._getHero
local _getToken = CharacterBuilder._getToken

--- Minimal implementation for the center panel. Non-reactive.
function CharacterBuilder._detailPanel()
    local detailPanel

    detailPanel = gui.Panel{
        id = "detailPanel",
        classes = {"detailPanel", "panel-base", "builder-base"},
        width = CBStyles.SIZES.CENTER_PANEL_WIDTH,
        height = "99%",
        valign = "center",
        borderColor = "blue",
    }

    return detailPanel
end

--- Create the main panel for the builder.
--- Supports being placed inside the CharacterSheet as a tab
--- or as a stand-alone dialog.
--- In the CharacterSheet, it will instantly update the token.
--- @return Panel
function CharacterBuilder.CreatePanel()

    local selectorsPanel = CBSelectors.CreatePanel()
    local detailPanel = CharacterBuilder._detailPanel()
    local characterPanel = CBCharPanel.CreatePanel()

    return gui.Panel{
        id = CharacterBuilder.CONTROLLER_CLASS,
        styles = CBStyles.GetStyles(),
        classes = {"panel-base", "builder-base", CharacterBuilder.CONTROLLER_CLASS},
        width = "99%",
        height = "99%",
        halign = "center",
        valign = "center",
        flow = "horizontal",

        data = {
            state = CharacterBuilderState:new(),

            detailPanels = {},

            cachedCharSheetInstance = false,
            charSheetInstance = nil,

            _cacheToken = function(element)
                -- Importantly, we might not be running in the context of a character sheet
                -- so we can't just grab the singleton object. This code is designed to
                -- help us retrieve the token from the context we're running under.
                if element.data.charSheetInstance == nil and not element.data.cachedCharSheetInstance then
                    element.data.charSheetInstance = CharacterBuilder._getCharacterSheet(element)
                    element.data.cachedCharSheetInstance = true
                end
                if element.data.charSheetInstance and element.data.charSheetInstance.data and element.data.charSheetInstance.data.info then
                    element.data.state:Set{key = "token", value = element.data.charSheetInstance.data.info.token}
                else
                    -- TODO: Can we create a token without attaching it to the game immediately?
                end
                return _getToken(element.data.state)
            end,
        },

        applyCurrentAncestry = function(element)
            local ancestryId = element.data.state:Get("ancestry.selectedId")
            if ancestryId then
                local hero = _getHero(element.data.state)
                if hero then
                    hero.raceid = ancestryId
                    element:FireEvent("tokenDataChanged")
                end
            end
        end,

        applyCurrentCareer = function(element)
            local careerId = element.data.state:Get("career.selectedId")
            if careerId then
                local hero = _getHero(element.data.state)
                if hero then
                    hero.backgroundid = careerId
                    element:FireEvent("tokenDataChanged")
                end
            end
        end,

        applyCurrentClass = function(element)
            local classId = element.data.state:Get("class.selectedId")
            if classId then
                local hero = _getHero(element.data.state)
                if hero then
                    local classes = hero:get_or_add("classes", {})
                    classes[1] = {
                        classid = classId,
                        level = hero:CharacterLevel(),
                    }
                    element:FireEvent("tokenDataChanged")
                end
            end
        end,

        applyLevelChoice = function(element, info)
            local feature = info.feature
            local hero = _getHero(element.data.state)
            if hero then
                local levelChoices = hero:GetLevelChoices()
                if levelChoices then
                    local choiceId = feature.guid
                    local selectedId = info.selectedId
                    local numChoices = feature:NumChoices(hero)
                    if numChoices == nil or numChoices < 1 then numChoices = 1 end
                    if (levelChoices[choiceId] == nil or numChoices == 1) and levelChoices[choiceId] ~= selectedId then
                        levelChoices[choiceId] = { selectedId }
                        element:FireEvent("tokenDataChanged")
                    else
                        local alreadySelected = false
                        for _,id in ipairs(levelChoices[choiceId]) do
                            if id == selectedId then
                                alreadySelected = true
                                break
                            end
                        end
                        if not alreadySelected then
                            local numSelected = #levelChoices[choiceId]
                            local selectedCost = 1
                            if #levelChoices[choiceId] > 0 and feature:try_get("costsPoints") then
                                for _,option in ipairs(feature.options) do
                                    local pointsCost = math.max(1, option:try_get("pointsCost", 1))
                                    if option.guid == info.selectedId then selectedCost = pointsCost end
                                    for _,guid in ipairs(levelChoices[choiceId]) do
                                        if info.selectedId == guid then
                                            numSelected = numSelected + (pointsCost - 1)
                                            break
                                        end
                                    end
                                end
                            end
                            if numChoices >= numSelected + selectedCost then
                                if numChoices > 1 then
                                    levelChoices[choiceId][#levelChoices[choiceId]+1] = selectedId
                                else
                                    levelChoices[choiceId][1] = selectedId
                                end
                                element:FireEvent("tokenDataChanged")
                            end
                        end
                    end
                end
            end
        end,

        cacheLevelChoices = function(element)
            local state = element.data.state
            local hero = _getHero(state)
            if hero then
                local levelChoices = hero:GetLevelChoices()
                state:Set{ key = "levelChoices", value = dmhub.DeepCopy(levelChoices) }
            end
        end,

        cachePerks = function(element)
            local state = element.data.state
            local hero = _getHero(state)
            local levelChoices = hero and hero:GetLevelChoices()

            if not levelChoices or not next(levelChoices) then
                state:Set{ key = "cachedPerks", value = {} }
                return
            end

            local cachedLevelChoices = state:Get("levelChoices")
            if dmhub.DeepEqual(cachedLevelChoices, levelChoices) then
                return
            end

            local perks = {}
            local features = hero:GetClassFeaturesAndChoicesWithDetails()
            if features then
                for _,f in ipairs(features) do
                    if f.feature and f.feature.typeName == "CharacterFeatChoice" then
                        local choices = levelChoices[f.feature.guid]
                        if choices then
                            for _,guid in ipairs(choices) do
                                perks[guid] = true
                            end
                        end
                    end
                end
            end

            state:Set{ key = "cachedPerks", value = perks }
        end,

        create = function(element)
            if element.data._cacheToken(element) ~= nil then
                element:FireEventTree("refreshToken")
            end
        end,

        removeAncestry = function(element)
            local hero = _getHero(element.data.state)
            if hero and (hero:try_get("raceid") or hero:try_get("subraceid")) then
                hero.raceid = nil
                hero.subraceid = nil
                element:FireEvent("tokenDataChanged")
            end
        end,

        removeCareer = function(element)
            local hero = _getHero(element.data.state)
            if hero then
                hero.backgroundid = nil
                element:FireEvent("tokenDataChanged")
            end
        end,

        removeClass = function(element)
            local hero = _getHero(element.data.state)
            if hero then
                hero.classes = {}
                element:FireEvent("tokenDataChanged")
            end
        end,

        removeLevelChoice = function(element, info)
            local hero = _getHero(element.data.state)
            if hero then
                local levelChoices = hero:GetLevelChoices()
                if levelChoices then
                    local levelChoice = levelChoices[info.levelChoiceGuid]
                    if levelChoice then
                        for i = #levelChoice, 1, -1 do
                            if levelChoice[i] == info.selectedId then
                                table.remove(levelChoice, i)
                                element:FireEvent("tokenDataChanged")
                                break
                            end
                        end
                    end
                end
            end
        end,

        refreshBuilderState = function(element, state)
            -- We shouldn't do anything here; we fire this event
            -- print("THC:: MAIN:: RBS::")
        end,

        refreshToken = function(element, info)
            -- print("THC:: MAIN:: REFRESHTOKEN::")
            local token
            if info then
                token = info.token
                element.data.state:Set{key = "token", value = token}
            else
                token = element.data._cacheToken(element)
            end

            if token then
                local creature = token.properties
                if creature:IsHero() then
                    local ancestryId = creature:try_get("raceid")
                    if ancestryId  then
                        element:FireEvent("selectAncestry", ancestryId, true)
                    end

                    local careerItem = creature:Background()
                    if careerItem then
                        element:FireEvent("selectCareer", careerItem.id, true)
                    end

                    local classItem = creature:GetClass()
                    if classItem then
                        element:FireEvent("selectClass", classItem.id, true)
                    end

                    -- TODO: Remaining data stored into state

                    element:FireEvent("cachePerks")
                    element:FireEvent("cacheLevelChoices")

                    element:FireEventTree("refreshBuilderState", element.data.state)
                end
            end
            -- This should never be processed by children. Use refreshBuilderState instead.
            element:HaltEventPropagation()
        end,

        selectAncestry = function(element, ancestryId, noFire)
            local state = element.data.state

            local cachedAncestryId = state:Get("ancestry.selectedId")
            local cachedInheritedAncestryId = state:Get("ancestry.inheritedId")
            local cachedLevelChoices = state:Get("levelChoices")

            local hero = _getHero(state)
            local levelChoices = hero and hero:GetLevelChoices() or {}
            local inheritedAncestry = hero:InheritedAncestry()
            local inheritedAncestryId = inheritedAncestry and inheritedAncestry.id or nil

            local ancestryChanged = ancestryId ~= cachedAncestryId or inheritedAncestryId ~= cachedInheritedAncestryId
            local levelChoicesChanged = not dmhub.DeepEqual(cachedLevelChoices, levelChoices)

            if not (ancestryChanged or levelChoicesChanged) then return end

            local newState = {
                { key = "ancestry.selectedId", value = ancestryId },
            }
            local ancestryItem = dmhub.GetTableVisible(Race.tableName)[ancestryId]
            if ancestryItem then
                local featureDetails = {}
                ancestryItem:FillFeatureDetails(nil, levelChoices, featureDetails)
                
                local filteredFeatures = _filterFeatures(featureDetails)

                newState[#newState+1] = { key = "ancestry.selectedItem", value = ancestryItem }
                newState[#newState+1] = { key = "ancestry.inheritedId", value = inheritedAncestryId }
                newState[#newState+1] = { key = "ancestry.featureDetails", value = featureDetails }
                newState[#newState+1] = { key = "ancestry.filteredFeatures", value = filteredFeatures }
            end
            state:Set(newState)
            if not noFire then
                element:FireEventTree("refreshBuilderState", state)
            end
        end,

        selectCareer = function(element, careerId, noFire)
            local state = element.data.state
            local cachedCareerId = state:Get("career.selectedId")
            local cachedLevelChoices = state:Get("levelChoices")
            local hero = _getHero(state)
            local levelChoices = hero and hero:GetLevelChoices() or {}

            local careerChanged = careerId ~= cachedCareerId
            local levelChoicesChanged = not dmhub.DeepEqual(cachedLevelChoices, levelChoices)

            if not (careerChanged or levelChoicesChanged) then
                return
            end

            local newState = {
                { key = "career.selectedId", value = careerId },
            }
            local careerItem = dmhub.GetTableVisible(Background.tableName)[careerId]
            if careerItem then
                local featureDetails = {}
                careerItem:FillFeatureDetails(levelChoices, featureDetails)

                -- Special case: Make inciting incidents look like features
                for _,item in ipairs(careerItem:try_get("characteristics", {})) do
                    local feature = CharacterIncidentChoice:new(item)
                    if feature then
                        featureDetails[#featureDetails+1] = {
                            feature = feature,
                            background = careerItem,
                        }
                        local levelChoice = {}
                        local notes = hero:GetNotesForTable(feature.guid)
                        if notes and #notes > 0 then
                            for _,note in ipairs(notes) do
                                levelChoice[#levelChoice+1] = note.rowid
                            end
                        end
                        levelChoices[feature.guid] = levelChoice
                    end
                end

                local filteredFeatures = _filterFeatures(featureDetails)

                newState[#newState+1] = { key = "career.selectedItem", value = careerItem }
                newState[#newState+1] = { key = "career.featureDetails", value = featureDetails }
                newState[#newState+1] = { key = "career.filteredFeatures", value = filteredFeatures }
            end
            state:Set(newState)
            if not noFire then
                element:FireEventTree("refreshBuilderState", state)
            end
        end,

        selectClass = function(element, classId, noFire)
            -- Read our cache
            local state = element.data.state
            local cachedClassId = state:Get("class.selectedId")
            local cachedLevel = state:Get("class.level")
            local cachedSubclasses = state:Get("class.selectedSubclasses")
            local cachedLevelChoices = state:Get("levelChoices")

            -- Read current state / selections
            local hero = _getHero(state)
            local level = hero and hero:GetClassLevel()
            local levelChoices = hero and hero:GetLevelChoices() or {}
            local classAndSubClasses = hero and hero:GetClassesAndSubClasses() or {}

            -- If nothing changed, we can stop processing
            local classChanged = classId ~= cachedClassId
            local levelChanged = level ~= cachedLevel
            local subclassChanged = dmhub.DeepEqual(cachedSubclasses, classAndSubClasses) ~= true
            local levelChoicesChanged = dmhub.DeepEqual(cachedLevelChoices, levelChoices) ~= true
            if not (classChanged or levelChanged or subclassChanged or levelChoicesChanged) then
                return
            end

            -- Something changed so we need to process it
            local newState = {
                { key = "class.selectedId", value = classId },
                { key = "class.level", value = level },
            }
            local classItem = dmhub.GetTableVisible(Class.tableName)[classId]
            if classItem then
                local classFill = {}
                for _,entry in ipairs(classAndSubClasses) do
                    entry.class:FillFeatureDetailsForLevel(levelChoices, entry.level, false, "nonprimary", classFill)
                end
                local filteredFeatures, featureDetails = _filterFeatures(classFill)

                newState[#newState+1] = { key = "class.selectedItem", value = classItem }
                newState[#newState+1] = { key = "class.selectedSubclasses", value = classAndSubClasses }
                newState[#newState+1] = { key = "class.featureDetails", value = featureDetails }
                newState[#newState+1] = { key = "class.filteredFeatures", value = filteredFeatures }
            else
                newState[#newState+1] = { key = "class.selectedItem", nil }
                newState[#newState+1] = { key = "class.selectedSubclasses", nil }
                newState[#newState+1] = { key = "class.featureDetails", nil }
                newState[#newState+1] = { key = "class.filteredFeatures", nil }
            end
            state:Set(newState)
            if not noFire then
                element:FireEventTree("refreshBuilderState", state)
            end
        end,

        selectItem = function(element, info)
            if info.selector == "ancestry" then
                element:FireEvent("selectAncestry", info.id)
            elseif info.selector == "career" then
                element:FireEvent("selectCareer", info.id)
            elseif info.selector == "class" then
                element:FireEvent("selectClass", info.id)
            end
        end,

        selectorChange = function(element, newSelector)
            local selectorDetail = element.data.detailPanels[newSelector]
            if not selectorDetail then
                local selector = CharacterBuilder.SelectorLookup[newSelector]
                if selector and selector.detail then
                    selectorDetail = selector.detail()
                    element.data.detailPanels[newSelector] = selectorDetail
                    detailPanel:AddChild(selectorDetail)
                end
            end
            element.data.state:Set{ key = "activeSelector", value = newSelector }
            element:FireEventTree("refreshBuilderState", element.data.state)
        end,

        tokenDataChanged = function(element)
            if element.data.charSheetInstance then
                element.data.charSheetInstance:FireEvent("refreshAll")
            else
                element:FireEventTree("refreshBuilderState", element.data.state)
            end
        end,

        updateState = function(element, info)
            if info then element.data.state:Set(info) end
            element:FireEventTree("refreshBuilderState", element.data.state)
        end,

        selectorsPanel,
        detailPanel,
        characterPanel,
    }
end

-- TODO: Remove the gate on dev mode
if devmode() then

--- Our tab in the character sheet
CharSheet.RegisterTab {
    id = "builder2",
    text = "Builder (WIP)",
	visible = function(c)
		return c ~= nil and c:IsHero()
	end,
    panel = CharacterBuilder.CreatePanel
}
dmhub.RefreshCharacterSheet()

end
