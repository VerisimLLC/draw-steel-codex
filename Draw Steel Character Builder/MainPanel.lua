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
                local hero = _getHero(state)
                if hero then
                    local classes = hero:get_or_add("classes", {})
                    classes[1] = {
                        classid = classId,
                        level = hero:CharacterLevel(),
                    }

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
            -- print("THC:: MAIN:: RBS::")
        end,

        refreshToken = function(element, info)
            -- print("THC:: MAIN:: REFRESHTOKEN::")
            local cachedToken = _getToken(element.data.state)
            local token
            if info then
                token = info.token
                element.data.state:Set{key = "token", value = token}
            else
                token = element.data._cacheToken(element)
            end

            if token then
                if cachedToken and cachedToken.id ~= token.id then
                    element.data.state = CharacterBuilderState:new()
                    element.data.state:Set({key = "token", value = token})
                    element:FireEvent("ensureActiveSelector")
                end

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

                    -- Always cache levelChoices last. Other actions depend
                    -- on determining the difference between cache and current.
                    element:FireEvent("cachePerks")
                    element:FireEvent("cacheLevelChoices")

                    element:FireEventTree("refreshBuilderState", element.data.state)
                end
            end
            -- This event should never be processed by children.
            -- Use refreshBuilderState instead.
            element:HaltEventPropagation()
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
                for _,attr in pairs(hero:try_get("attributes" or {})) do
                    attr.baseValue = 0
                end
                hero.attributeBuild = {}
                hero.kitid = nil
                hero.kitid2 = nil
                element:FireEvent("tokenDataChanged")
            end
        end,

        selectAncestry = function(element, ancestryId, noFire)
            local state = element.data.state

            local cachedAncestryId = state:Get(SEL.ANCESTRY .. ".selectedId")
            local cachedInheritedAncestryId = state:Get(SEL.ANCESTRY .. ".inheritedId")
            local cachedLevelChoices = state:Get("levelChoices")

            local hero = _getHero(state)
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

                local featureCache = CBFeatureCache:new(hero, ancestryId, ancestryItem.name, featureDetails)

                newState[#newState+1] = { key = SEL.ANCESTRY .. ".selectedItem", value = ancestryItem }
                newState[#newState+1] = { key = SEL.ANCESTRY .. ".inheritedId", value = inheritedAncestryId }
                newState[#newState+1] = { key = SEL.ANCESTRY .. ".featureCache", value = featureCache }
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
            local hero = _getHero(state)
            local levelChoices = hero and hero:GetLevelChoices() or {}

            local careerChanged = careerId ~= cachedCareerId
            local levelChoicesChanged = not dmhub.DeepEqual(cachedLevelChoices, levelChoices)

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

                local featureCache = CBFeatureCache:new(hero, careerId, careerItem.name, featureDetails)

                newState[#newState+1] = { key = SEL.CAREER .. ".selectedItem", value = careerItem }
                newState[#newState+1] = { key = SEL.CAREER .. ".featureCache", value = featureCache }
            end
            state:Set(newState)
            if not noFire then
                element:FireEventTree("refreshBuilderState", state)
            end
        end,

        selectClass = function(element, classId, noFire)
            local state = element.data.state
            local hero = _getHero(state)
            local level = hero and hero:GetClassLevel()
            local levelChoices = hero and hero:GetLevelChoices() or {}
            local classAndSubClasses = hero and hero:GetClassesAndSubClasses() or {}

            -- TODO: For performance we might try to determine if anything changed
            -- before doing all this work, but that's complicated because so much
            -- is associated to class.

            local newState = {
                { key = SEL.CLASS .. ".selectedId", value = classId },
                { key = SEL.CLASS .. ".level", value = level },
            }
            local classItem = dmhub.GetTableVisible(Class.tableName)[classId]
            if classItem then
                local classFill = {}

                -- Special case: Adapt baseCharacteristics to behave like a feature choice
                local feature = CharacterCharacteristicChoice:new(classItem)
                if feature then
                    classFill[#classFill+1] = {
                        feature = feature,
                        class = classItem,
                    }
                end

                local extraLevelInfo = hero:ExtraLevelInfo()
                if #classAndSubClasses > 0 then
                    for i,entry in ipairs(classAndSubClasses) do
                        entry.class:FillFeatureDetailsForLevel(levelChoices, entry.level, extraLevelInfo, i ~= 1, classFill)
                    end
                else
                    classItem:FillFeatureDetailsForLevel(levelChoices, 1, extraLevelInfo, "nonprimary", classFill)
                end
                local featureCache = CBFeatureCache:new(hero, classId, classItem.name, classFill)

                newState[#newState+1] = { key = SEL.CLASS .. ".selectedItem", value = classItem }
                newState[#newState+1] = { key = SEL.CLASS .. ".selectedSubclasses", value = classAndSubClasses }
                newState[#newState+1] = { key = SEL.CLASS .. ".featureCache", value = featureCache }

                local kitFeature = CharacterKitChoice:new(hero)
                if kitFeature then
                    local features = {
                        { feature = kitFeature }
                    }
                    local kitFeatureCache = CBFeatureCache:new(hero, classItem.id, classItem.name, features)
                    newState[#newState+1] = { key = SEL.KIT .. ".featureCache", value = kitFeatureCache }
                else
                    newState[#newState+1] = { key = SEL.KIT .. ".featureCache", value = nil }
                end                    
            else
                newState[#newState+1] = { key = SEL.CLASS .. ".selectedItem", value = nil }
                newState[#newState+1] = { key = SEL.CLASS .. ".selectedSubclasses", value = nil }
                newState[#newState+1] = { key = SEL.CLASS .. ".featureCache", value = nil }
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
end

-- TODO: Remove the gate on the setting
setting{
    id = "testwipbuilder",
    description = "Test WIP Builder",
    editor = "check",
    default = false,
    storage = "Game",
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
