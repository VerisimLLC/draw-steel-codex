--[[
    Main panel of the Character Builder
]]
local _getHero = CharacterBuilder._getHero
local _getToken = CharacterBuilder._getToken
local SEL = CharacterBuilder.SELECTOR

--- Minimal implementation for the center panel. Non-reactive.
--- @return Panel
function CharacterBuilder._detailPanel()
    return gui.Panel{
        id = "detailPanel",
        classes = {"detailPanel", "panel-base", "builder-base"},
        width = CBStyles.SIZES.CENTER_PANEL_WIDTH,
        height = "99%",
        valign = "center",
        borderColor = "blue",
    }
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

    CharacterBuilder.builderPanel = gui.Panel{
        id = CharacterBuilder.CONTROLLER_CLASS,
        styles = CBStyles.GetStyles(),
        classes = {"panel-base", "builder-base", CharacterBuilder.CONTROLLER_CLASS},
        width = "99%",
        height = "99%",
        halign = "center",
        valign = "center",
        flow = "horizontal",

        data = {
            state = CharacterBuilderState.CreateNew(),

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
                    local newToken = element.data.charSheetInstance.data.info.token
                    element.data.state:Set{ key = "token", value = newToken }
                else
                    -- TODO: Can we create a token without attaching it to the game immediately?
                end
                return _getToken(element.data.state)
            end,
        },

        applyCurrentAncestry = function(element)
            local ancestryId = element.data.state:Get(SEL.ANCESTRY .. ".selectedId")
            if ancestryId then
                local hero = _getHero(element.data.state)
                if hero then
                    hero.raceid = ancestryId
                    element:FireEvent("tokenDataChanged")
                end
            end
        end,

        applyCurrentCareer = function(element)
            local careerId = element.data.state:Get(SEL.CAREER .. ".selectedId")
            if careerId then
                local hero = _getHero(element.data.state)
                if hero then
                    hero.backgroundid = careerId
                    element:FireEvent("tokenDataChanged")
                end
            end
        end,

        applyCurrentClass = function(element)
            local state = element.data.state
            local classId = state:Get(SEL.CLASS .. ".selectedId")
            if classId then
                local hero = _getHero()
                if hero then
                    local classes = hero:get_or_add("classes", {})
                    classes[1] = {
                        classid = classId,
                        level = hero:CharacterLevel(),
                    }

                    hero.kitid = nil
                    hero.kitid2 = nil

                    hero.attributeBuild = {}

                    local classItem = state:Get(SEL.CLASS .. ".selectedItem")
                    if classItem then
                        local baseChars = classItem:try_get("baseCharacteristics")
                        local heroAttrs = hero:try_get("attributes")
                        if baseChars and heroAttrs then
                            for k,attr in pairs(heroAttrs) do
                                attr.baseValue = baseChars[k] or 0
                            end
                        end
                    end

                    element:FireEvent("tokenDataChanged")
                end
            end
        end,

        cacheComplication = function(element, hero)
            local state = element.data.state
            local complicationFeature = CharacterComplicationChoice.CreateNew(hero)
            if complicationFeature then
                local levelChoices = hero:GetLevelChoices()
                local features = {
                    { feature = complicationFeature }
                }
                local selected = complicationFeature:GetSelected()
                local items = dmhub.GetTableVisible(CharacterComplication.tableName)
                for _,id in ipairs(selected) do
                    local item = items[id]
                    if item then
                        item:FillFeatureDetails(levelChoices, features)
                    end
                end
                local featureCache = CBFeatureCache.CreateNew(hero, SEL.COMPLICATION, "Complication", features)
                state:Set{ key = SEL.COMPLICATION .. ".featureCache", value = featureCache }
            else
                state:Set{ key = SEL.COMPLICATION .. ".featureCache", value = nil }
            end
        end,

        cacheCultures = function(element, hero)
            local aspectFeatures = CharacterAspectChoice.CreateAll()
            if aspectFeatures then
                local levelChoices = hero:GetLevelChoices()

                local cultureFeatures = {}
                local cultureItem = hero:GetCulture()
                if cultureItem then
                    cultureItem:FillFeatureDetails(levelChoices, cultureFeatures)
                end

                cultureFeatures = table.append_arrays(aspectFeatures, cultureFeatures)
                local featureCache = CBFeatureCache.CreateNew(hero, SEL.CULTURE, "Culture", cultureFeatures)
                element.data.state:Set{ key = SEL.CULTURE .. ".featureCache", value = featureCache }
            end
        end,

        cacheLevelChoices = function(element)
            local state = element.data.state
            local hero = _getHero()
            if hero then
                local levelChoices = hero:GetLevelChoices()
                state:Set{ key = "levelChoices", value = dmhub.DeepCopy(levelChoices) }
            end
        end,

        cachePerks = function(element)
            local state = element.data.state
            local hero = _getHero()
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
                element:FireEvent("refreshToken")
            end
            element:FireEvent("ensureActiveState")
        end,

        ensureActiveSelector = function(element)
            if element.data.state:Get("activeSelector") == nil then
                element:FireEvent("selectorChange", CharacterBuilder.INITIAL_SELECTOR)
            end
        end,

        refreshBuilderState = function(element, state)
            -- We shouldn't do anything here; we fire this event
            -- print("THC:: MAIN:: RBS::", json(state))
        end,

        refreshToken = function(element, info)
            -- print("THC:: MAIN:: REFRESHTOKEN::", os.date("%Y-%m-%d %H:%M:%S"))
            local state = element.data.state

            local cachedToken = _getToken(state)
            local token
            if info then
                token = info.token
                state:Set{key = "token", value = token}
            else
                token = element.data._cacheToken(element)
            end

            if token then
                if cachedToken and cachedToken.id ~= token.id then
                    state = CharacterBuilderState.CreateNew()
                    state:Set({key = "token", value = token})
                end
                element:FireEvent("ensureActiveSelector")

                local creature = token.properties
                if creature:IsHero() then
                    local hero = creature

                    local ancestryId = creature:try_get("raceid")
                    if ancestryId  then
                        element:FireEvent("selectAncestry", ancestryId, true)
                    end

                    element:FireEvent("cacheComplication", hero)

                    element:FireEvent("cacheCultures", hero)

                    local careerItem = creature:Background()
                    if careerItem then
                        element:FireEvent("selectCareer", careerItem.id, true)
                    end

                    local classItem = creature:GetClass()
                    if classItem then
                        element:FireEvent("selectClass", classItem.id, true)
                    end

                    local kitCache = state:Get(SEL.KIT .. ".featureCache")
                    if kitCache then
                        for _,featureEntry in ipairs(kitCache:GetSortedFeatures()) do
                            local feature = kitCache:GetFeature(featureEntry.guid)
                            if feature then feature:Update(hero) end
                        end
                    end

                    -- TODO: Remaining data stored into state

                    -- Always cache levelChoices last. Other actions depend
                    -- on determining the difference between cache and current.
                    element:FireEvent("cachePerks")
                    element:FireEvent("cacheLevelChoices")

                    element:FireEventTree("refreshBuilderState", state)
                end
            end
            -- This event should never be processed by children.
            -- Use refreshBuilderState instead.
            element:HaltEventPropagation()
        end,

        removeAncestry = function(element)
            local state = element.data.state
            local hero = _getHero(state)
            if hero and (hero:try_get("raceid") or hero:try_get("subraceid")) then
                element:AddChild(CharacterBuilder._confirmDialog{
                    title = "Confirm Change Ancestry",
                    message = "Click Confirm to remove your Ancestry and all related selections.",
                    onConfirm = function()
                        hero.raceid = nil
                        hero.subraceid = nil
                        state:Set{ key = SEL.ANCESTRY .. ".blockFeatureSelection", value = true }
                        element:FireEvent("tokenDataChanged")
                    end,
                })
            end
        end,

        removeCareer = function(element)
            local state = element.data.state
            local hero = _getHero(state)
            if hero then
                element:AddChild(CharacterBuilder._confirmDialog{
                    title = "Confirm Change Career",
                    message = "Click Confirm to remove your Career and all related selections.",
                    onConfirm = function()
                        hero.backgroundid = nil
                        state:Set{ key = SEL.CAREER .. ".blockFeatureSelection", value = true }
                        element:FireEvent("tokenDataChanged")
                    end,
                })
            end
        end,

        removeClass = function(element)
            local state = element.data.state
            local hero = _getHero(state)
            if hero then
                element:AddChild(CharacterBuilder._confirmDialog{
                    title = "Confirm Change Class",
                    message = "Click Confirm to remove your Class and all related selections.",
                    onConfirm = function()
                        hero.classes = {}
                        for _,attr in pairs(hero:try_get("attributes" or {})) do
                            attr.baseValue = 0
                        end
                        hero.attributeBuild = {}
                        hero.kitid = nil
                        hero.kitid2 = nil
                        local levelChoices = hero:GetLevelChoices() or {}
                        if levelChoices["kitBonusChoices"] then
                            levelChoices["kitBonusChoices"] = nil
                        end
                        state:Set{ key = SEL.CLASS .. ".blockFeatureSelection", value = true }
                        element:FireEvent("tokenDataChanged")
                    end,
                })
            end
        end,

        selectAncestry = function(element, ancestryId, noFire)
            local state = element.data.state

            local cachedAncestryId = state:Get(SEL.ANCESTRY .. ".selectedId")
            local cachedInheritedAncestryId = state:Get(SEL.ANCESTRY .. ".inheritedId")
            local cachedLevelChoices = state:Get("levelChoices")

            local hero = _getHero()
            local levelChoices = hero and hero:GetLevelChoices() or {}
            local inheritedAncestry = hero:InheritedAncestry()
            local inheritedAncestryId = inheritedAncestry and inheritedAncestry.id or nil

            local ancestryChanged = ancestryId ~= cachedAncestryId or inheritedAncestryId ~= cachedInheritedAncestryId
            local levelChoicesChanged = not dmhub.DeepEqual(cachedLevelChoices, levelChoices)

            if not (ancestryChanged or levelChoicesChanged) then return end

            local newState = {
                { key = SEL.ANCESTRY .. ".selectedId", value = ancestryId },
            }
            local ancestryItem = dmhub.GetTableVisible(Race.tableName)[ancestryId]
            if ancestryItem then
                local featureDetails = {}
                ancestryItem:FillFeatureDetails(nil, levelChoices, featureDetails)

                local featureCache = CBFeatureCache.CreateNew(hero, ancestryId, ancestryItem.name, featureDetails)

                newState[#newState+1] = { key = SEL.ANCESTRY .. ".selectedItem", value = ancestryItem }
                newState[#newState+1] = { key = SEL.ANCESTRY .. ".inheritedId", value = inheritedAncestryId }
                newState[#newState+1] = { key = SEL.ANCESTRY .. ".featureCache", value = featureCache }
                newState[#newState+1] = { key = SEL.ANCESTRY .. ".blockFeatureSelection", value = hero:try_get("raceid") == nil}
            end
            state:Set(newState)
            if not noFire then
                element:FireEventTree("refreshBuilderState", state)
            end
        end,

        selectCareer = function(element, careerId, noFire)
            local state = element.data.state

            local cachedCareerId = state:Get(SEL.CAREER .. ".selectedId")
            local cachedLevelChoices = state:Get("levelChoices")
            
            local hero = _getHero()
            local levelChoices = hero and hero:GetLevelChoices() or {}

            local careerChanged = careerId ~= cachedCareerId
            local levelChoicesChanged = not dmhub.DeepEqual(cachedLevelChoices, levelChoices)

            -- Always update blockFeatureSelection based on current hero state
            local blockFeatureSelection = hero == nil or hero:try_get("backgroundid") == nil
            local cachedBlock = state:Get(SEL.CAREER .. ".blockFeatureSelection")
            if cachedBlock ~= blockFeatureSelection then
                state:Set{ key = SEL.CAREER .. ".blockFeatureSelection", value = blockFeatureSelection }
            end

            if not (careerChanged or levelChoicesChanged) then
                return
            end

            local newState = {
                { key = SEL.CAREER .. ".selectedId", value = careerId },
            }
            local careerItem = dmhub.GetTableVisible(Background.tableName)[careerId]
            if careerItem then
                local featureDetails = {}
                careerItem:FillFeatureDetails(levelChoices, featureDetails)

                -- Special case: Adapt inciting incidents to behave like features
                for _,item in ipairs(careerItem:try_get("characteristics", {})) do
                    local feature = CharacterIncidentChoice.CreateNew(item)
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

                local featureCache = CBFeatureCache.CreateNew(hero, careerId, careerItem.name, featureDetails)

                newState[#newState+1] = { key = SEL.CAREER .. ".selectedItem", value = careerItem }
                newState[#newState+1] = { key = SEL.CAREER .. ".featureCache", value = featureCache }
                newState[#newState+1] = { key = SEL.CAREER .. ".blockFeatureSelection", value = hero:try_get("backgroundid") == nil}
            end
            state:Set(newState)
            if not noFire then
                element:FireEventTree("refreshBuilderState", state)
            end
        end,

        selectClass = function(element, classId, noFire)
            local state = element.data.state
            local cachedClassId = state:Get(SEL.CLASS .. ".selectedId")
            local cachedLevel = state:Get(SEL.CLASS .. ".level")
            local cachedExtraLevel = state:Get(SEL.CLASS .. ".extraLevel")
            local cachedSubclasses = state:Get(SEL.CLASS .. ".selectedSubclasses")
            local cachedLevelChoices = state:Get("levelChoices")
            local cachedKitId = state:Get(SEL.KIT .. ".selectedId")

            local hero = _getHero()
            local level = hero and hero:CharacterLevel()
            local extraLevelInfo = hero:ExtraLevelInfo()
            local classAndSubClasses = hero and hero:GetClassesAndSubClasses() or {}
            local levelChoices = hero and hero:GetLevelChoices() or {}

            -- If nothing changed, there's nothing to do
            local classChanged = classId ~= cachedClassId
            local levelChanged = level ~= cachedLevel or extraLevelInfo ~= cachedExtraLevel
            local subclassesChanged = dmhub.DeepEqual(classAndSubClasses, cachedSubclasses) ~= true
            local levelChoicesChanged = dmhub.DeepEqual(levelChoices, cachedLevelChoices) ~= true

            -- Always update blockFeatureSelection based on current hero state
            local heroHasClass = hero ~= nil and hero:GetClass() ~= nil
            local blockFeatureSelection = not heroHasClass
            local cachedBlock = state:Get(SEL.CLASS .. ".blockFeatureSelection")
            if cachedBlock ~= blockFeatureSelection then
                state:Set{ key = SEL.CLASS .. ".blockFeatureSelection", value = blockFeatureSelection }
            end

            if not (classChanged or levelChanged or subclassesChanged or levelChoicesChanged) then
                -- Caching is not working. Calculate always.
                -- return
            end

            --[[
                if Class changed then
                    Redo everything
                elseif level or Subclass or levelChoices changed then
                    Redo feature fill 
                end
            ]]

            local newState = {
                { key = SEL.CLASS .. ".selectedId", value = classId },
                { key = SEL.CLASS .. ".level", value = level },
                { key = SEL.CLASS .. ".extraLevel", value = extraLevelInfo },
            }
            local classItem = dmhub.GetTableVisible(Class.tableName)[classId]
            if classItem then
                -- Cache isn't changing. Calculate always.
                if true or classChanged or levelChanged or subclassesChanged or levelChoicesChanged then
                    local classFill = {}

                    -- Special case: Adapt baseCharacteristics to behave like a feature choice
                    local feature = CharacterCharacteristicChoice.CreateNew(classItem)
                    if feature then
                        classFill[#classFill+1] = {
                            feature = feature,
                            class = classItem,
                        }
                    end

                    
                    if #classAndSubClasses > 0 then
                        for i,entry in ipairs(classAndSubClasses) do
                            entry.class:FillFeatureDetailsForLevel(levelChoices, entry.level, extraLevelInfo, i ~= 1, classFill)
                        end
                    else
                        classItem:FillFeatureDetailsForLevel(levelChoices, 1, extraLevelInfo, "nonprimary", classFill)
                    end
                    local featureCache = CBFeatureCache.CreateNew(hero, classId, classItem.name, classFill)

                    newState[#newState+1] = { key = SEL.CLASS .. ".selectedItem", value = classItem }
                    newState[#newState+1] = { key = SEL.CLASS .. ".selectedSubclasses", value = classAndSubClasses }
                    newState[#newState+1] = { key = SEL.CLASS .. ".featureCache", value = featureCache }
                end
                if cachedKitId ~= classId then
                    local kitFeature = CharacterKitChoice.CreateNew(hero)
                    if kitFeature then
                        local features = {
                            { feature = kitFeature }
                        }
                        local kitFeatureCache = CBFeatureCache.CreateNew(hero, classItem.id, classItem.name, features)
                        newState[#newState+1] = { key = SEL.KIT .. ".selectedId", value = classId }
                        newState[#newState+1] = { key = SEL.KIT .. ".featureCache", value = kitFeatureCache }
                    else
                        newState[#newState+1] = { key = SEL.KIT .. ".selectedId", value = nil }
                        newState[#newState+1] = { key = SEL.KIT .. ".featureCache", value = nil }
                    end
                end
            else
                newState[#newState+1] = { key = SEL.CLASS .. ".selectedItem", value = nil }
                newState[#newState+1] = { key = SEL.CLASS .. ".selectedSubclasses", value = nil }
                newState[#newState+1] = { key = SEL.CLASS .. ".featureCache", value = nil }
                newState[#newState+1] = { key = SEL.KIT .. ".selectedId", value = nil }
                newState[#newState+1] = { key = SEL.KIT .. ".featureCache", value = nil }
            end
            state:Set(newState)
            if not noFire then
                element:FireEventTree("refreshBuilderState", state)
            end
        end,

        selectItem = function(element, info)
            local events = {
                [SEL.ANCESTRY]  = "selectAncestry",
                [SEL.CAREER]    = "selectCareer",
                [SEL.CLASS]     = "selectClass",
                [SEL.KIT]       = "selectKit",
            }
            local eventName = events[info.selector]
            if eventName then
                element:FireEvent(eventName, info.id)
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
                -- The character sheet fires refreshToken which in turn
                -- fires refreshBuilderState
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

    return CharacterBuilder.builderPanel
end

-- TODO: Remove the gate on the setting
setting{
    id = "testwipbuilder",
    description = "Test WIP Builder",
    editor = "check",
    default = false,
    storage = "preference",
    section = "game",
}

--- Our tab in the character sheet
CharSheet.RegisterTab {
    id = "builder2",
    text = "Builder (WIP)",
	visible = function(c)
		return c ~= nil and c:IsHero() and dmhub.GetSettingValue("testwipbuilder") == true
	end,
    panel = CharacterBuilder.CreatePanel
}
dmhub.RefreshCharacterSheet()
