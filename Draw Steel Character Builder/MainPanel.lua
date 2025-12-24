--[[
    Main panel of the Character Builder
]]
local _getCreature = CharacterBuilder._getCreature
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
                local creature = _getCreature(element.data.state)
                if creature then
                    creature.raceid = ancestryId
                    element:FireEvent("tokenDataChanged")
                end
            end
        end,

        applyLevelChoice = function(element, info)
            local feature = info.feature
            local creature = _getCreature(element.data.state)
            if creature then
                local levelChoices = creature:GetLevelChoices()
                if levelChoices then
                    local choiceId = feature.guid
                    local selectedId = info.selectedId
                    local numChoices = feature:NumChoices(creature)
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

        create = function(element)
            if element.data._cacheToken(element) ~= nil then
                element:FireEventTree("refreshToken")
            end
        end,

        removeLevelChoice = function(element, info)
            local creature = _getCreature(element.data.state)
            if creature then
                local levelChoices = creature:GetLevelChoices()
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
                    if ancestryId and ancestryId ~= element.data.state:Get("ancestry.selectedId") then
                        element:FireEvent("selectAncestry", ancestryId, true)
                    end

                    local careerItem = creature:Background()
                    if careerItem and careerItem.id ~= element.data.state:Get("career.selectedId") then
                        element:FireEvent("selectCareer", careerItem.id, true)
                    end

                    element:FireEventTree("refreshBuilderState", element.data.state)
                end
            end
        end,

        selectAncestry = function(element, ancestryId, noFire)
            if ancestryId ~= element.data.state:Get("ancestry.selectedId") then
                local state = {
                    { key = "ancestry.selectedId", value = ancestryId },
                }
                local ancestryItem = dmhub.GetTableVisible(Race.tableName)[ancestryId]
                if ancestryItem then
                    local featureDetails = {}
                    ancestryItem:FillFeatureDetails(nil, {}, featureDetails)
                    state[#state+1] = { key = "ancestry.selectedItem", value = ancestryItem }
                    state[#state+1] = { key = "ancestry.featureDetails", value = featureDetails }
                end
                element.data.state:Set(state)
                if not noFire then
                    element:FireEventTree("refreshBuilderState", element.data.state)
                end
            end
        end,

        selectCareer = function(element, careerId, noFire)
            if careerId ~= element.data.state:Get("career.selectedId") then
                local state = {
                    { key = "career.selectedId", value = careerId },
                }
                local careerItem = dmhub.GetTableVisible(Background.tableName)[careerId]
                if careerItem then
                    local featureDetails = {}
                    careerItem:FillFeatureDetails({}, featureDetails)
                    state[#state+1] = { key = "career.selectedItem", value = careerItem }
                    state[#state+1] = { key = "career.featureDetails", value = featureDetails }
                end
                element.data.state:Set(state)
                if not noFire then
                    element:FireEventTree("refreshBuilderState", element.data.state)
                end
            end
        end,

        selectItem = function(element, info)
            if info.selector == "ancestry" then
                element:FireEvent("selectAncestry", info.id)
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
            element.data.state:Set({key = "activeSelector", value = newSelector})
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
