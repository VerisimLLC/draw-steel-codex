local mod = dmhub.GetModLoading()

--[[
    Ancestry detail / selectors
]]

local SELECTOR = "ancestry"
local INITIAL_CATEGORY = "overview"
local AVAILABLE_WITHOUT_ANCESTRY = {overview = true, lore = true}

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getCreature = CharacterBuilder._getCreature
local _getState = CharacterBuilder._getState
local _makeCategoryButton = CharacterBuilder._makeCategoryButton

--- Generate the Ancestry Category Navigation panel
--- @return Panel
function CharacterBuilder._ancestryNavPanel()

    local function makeCategoryButton(options)
        if options.click == nil then
            options.click = function(element)
                _fireControllerEvent(element, "updateState", {
                    key = SELECTOR .. ".category.selectedId",
                    value = element.data.category
                })
            end
        end
        if options.refreshBuilderState == nil then
            options.refreshBuilderState = function(element, state)
                element:FireEvent("setAvailable", state:Get(SELECTOR .. ".selectedId") ~= nil)
                element:FireEvent("setSelected", state:Get(SELECTOR .. ".category.selectedId") == element.data.category)
            end
        end
        return _makeCategoryButton(options)
    end

    local overview = makeCategoryButton{
        text = "Overview",
        data = { category = INITIAL_CATEGORY },
    }
    local lore = makeCategoryButton{
        text = "Lore",
        data = { category = "lore" },
    }
    local change = makeCategoryButton{
        classes = {"changeAncestry"},
        text = "Change Ancestry",
        data = { category = "change" },
        click = function(element)
            local creature = _getCreature(element)
            if creature then
                creature.raceid = nil
                creature.subraceid = nil
                _fireControllerEvent(element, "tokenDataChanged")
            end
        end,
        refreshBuilderState = function(element, state)
            local creature = state:Get("token").properties
            if creature then
                element:FireEvent("setAvailable", creature:try_get("raceid") ~= nil)
            end
        end,
    }

    return gui.Panel{
        classes = {"categoryNavPanel", "panel-base", "builder-base"},
        width = CharacterBuilder.SIZES.BUTTON_PANEL_WIDTH + 20,
        height = "99%",
        valign = "top",
        vpad = CharacterBuilder.SIZES.ACTION_BUTTON_HEIGHT,
        flow = "vertical",
        vscroll = true,
        borderColor = "teal",

        create = function(element)
            _fireControllerEvent(element, "updateState", {
                key = SELECTOR .. ".category.selectedId",
                value = INITIAL_CATEGORY,
            })
        end,

        registerFeatureButton = function(element, button)
            element:AddChild(button)
            local changeButton = element:FindChildRecursive(function(element) return element:HasClass("changeAncestry") end)
            if changeButton then changeButton:SetAsLastSibling() end
        end,

        overview,
        lore,
        change,
    }
end

--- Build the Ancestry Overview panel
--- Used when no Ancestry is selected and to overview a selected ancestry
--- @return Panel
function CharacterBuilder._ancestryOverviewPanel()

    local nameLabel = gui.Label{
        classes = {"builder-base", "label", "label-info", "label-header"},
        width = "100%",
        height = "auto",
        hpad = 12,
        text = "ANCESTRY",
        textAlignment = "left",

        refreshBuilderState = function(element, state)
            local text = "ANCESTRY"
            local ancestryId = state:Get(SELECTOR .. ".selectedId")
            if ancestryId then
                local race = state:Get(SELECTOR .. ".selectedItem")
                if not race then
                    race = dmhub.GetTable(Race.tableName)[ancestryId]
                end
                if race then text = race.name end
            end
            element.text = text
        end
    }

    local introLabel = gui.Label{
        classes = {"builder-base", "label", "label-info"},
        width = "100%",
        height = "auto",
        vpad = 6,
        hpad = 12,
        bmargin = 12,
        textAlignment = "left",
        text = CharacterBuilder.STRINGS.ANCESTRY.INTRO,

        refreshBuilderState = function(element, state)
            local text = CharacterBuilder.STRINGS.ANCESTRY.INTRO
            local ancestryId = state:Get(SELECTOR .. ".selectedId")
            if ancestryId then
                local race = state:Get(SELECTOR .. ".selectedItem")
                if not race then
                    race = dmhub.GetTable(Race.tableName)[ancestryId]
                end
                if race then text = CharacterBuilder._trimToLength(race.details, 300) end
            end
            element.text = text
        end,
    }

    local detailLabel = gui.Label{
        classes = {"builder-base", "label", "label-info"},
        width = "100%",
        height = "auto",
        vpad = 6,
        hpad = 12,
        tmargin = 12,
        textAlignment = "left",
        bold = false,
        text = CharacterBuilder.STRINGS.ANCESTRY.OVERVIEW,

        refreshBuilderState = function(element, state)
            local text = CharacterBuilder.STRINGS.ANCESTRY.OVERVIEW
            local ancestryId = state:Get(SELECTOR .. ".selectedId")
            if ancestryId then
                local race = state:Get(SELECTOR .. ".selectedItem")
                local textItems = {
                    string.format(tr("<b>Size.</b>  Your people are size %s creatures."), race.size),
                    string.format(tr("<b>Height.</b>  Your people are %s tall."), race.height),
                    string.format(tr("<b>Weight.</b>  Your people weigh %s pounds."), race.weight),
                    string.format(tr("<b>Life Expectancy.</b>  Your people live %s years."), race.lifeSpan),
                    string.format(tr("<b>Speed.</b>  Your base walking speed is %s"),
                        MeasurementSystem.NativeToDisplayStringWithUnits(race.moveSpeeds.walk)),
                }

                local featureDetails = state:Get(SELECTOR .. ".featureDetails")
                for _,item in ipairs(featureDetails) do
                    local s = item.feature:GetSummaryText()
                    if s ~= nil and #s > 0 then
                        textItems[#textItems+1] = s
                    end
                end

                text = table.concat(textItems, "\n\n")
            end
            element.text = text
        end
    }

    return gui.Panel{
        id = "ancestryOverviewPanel",
        classes = {"ancestryOverviewPanel", "builder-base", "panel-base", "panel-border", "collapsed"},
        width = "96%",
        height = "99%",
        valign = "center",
        halign = "center",
        bgimage = mod.images.ancestryHome,
        bgcolor = "white",

        data = {
            category = "overview",
        },

        refreshBuilderState = function(element, state)
            local ancestryId = state:Get(SELECTOR .. ".selectedId")

            local visible = ancestryId == nil or state:Get(SELECTOR .. ".category.selectedId") == element.data.category
            element:SetClass("collapsed", not visible)

            if ancestryId == nil then
                element.bgimage = mod.images.ancestryHome
                return
            end
            local race = state:Get(SELECTOR .. ".selectedItem")
            if not race then
                race = dmhub.GetTable(Race.tableName)[ancestryId]
            end
            if race then element.bgimage = race.portraitid end
        end,

        gui.Panel{
            width = "100%-2",
            height = "auto",
            valign = "bottom",
            vmargin = 32,
            flow = "vertical",
            bgimage = true,
            vpad = 8,
            nameLabel,
            introLabel,
            detailLabel,
        }
    }
end

--- Create the Ancestry Lore panel
--- @return Panel
function CharacterBuilder._ancestryLorePanel()
    return gui.Panel{
        id = "ancestryLorePanel",
        classes = {"ancestryLorePanel", "builder-base", "panel-base", "collapsed"},
        width = "96%",
        height = "96%",
        valign = "top",
        halign = "center",
        tmargin = 12,
        vscroll = true,

        data = {
            category = "lore",
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get(SELECTOR .. ".selectedId") ~= nil and state:Get(SELECTOR .. ".category.selectedId") == element.data.category
            element:SetClass("collapsed", not visible)
        end,

        gui.Label{
            classes = {"builder-base", "label", "label-info"},
            width = "96%",
            height = "auto",
            valign = "top",
            halign = "center",
            tmargin = 20,
            text = "",
            textAlignment = "left",

            refreshBuilderState = function(element, state)
                local ancestryId = state:Get(SELECTOR .. ".selectedId")
                if ancestryId then
                    local race = state:Get(SELECTOR .. ".selectedItem")
                    if not race then
                        race = dmhub.GetTable(Race.tableName)[ancestryId]
                    end
                    element.text = (race and race.lore and #race.lore > 0)
                        and race.lore
                        or string.format("No lore found for %s.", race.name)
                end
            end,
        }
    }
end

--- Render a skill choice panel
--- @param feature CharacterSkillChoice
--- @return Panel|nil
function CharacterBuilder._featureSkillChoicePanel(feature)

    local candidateSkills = {}
    local categories = feature:try_get("categories", {})
    local individual = feature:try_get("individual", {})
    if (categories and next(categories)) or (individual and next(individual)) then
        local skills = dmhub.GetTableVisible(Skill.tableName)
        for key,item in pairs(skills) do
            if (individual and individual[key]) or (categories and categories[item.category]) then
                candidateSkills[#candidateSkills+1] = { id = key, text = item.name }
            end
        end
        table.sort(candidateSkills, function(a,b) return a.text < b.text end)
    else
        candidateSkills = Skill.skillsDropdownOptions
    end

    local children = {}

    -- children[#children+1] = gui.Label {
    --     classes = {"builder-base", "label", "label-feature-name"},
    --     text = feature.name,
    -- }

    children[#children+1] = gui.Label {
        classes = {"builder-base", "label", "label-feature-desc"},
        text = feature:GetDescription(),
    }

    -- Selection targets
    local numChoices = feature:NumChoices(creature)
    for i = 1, numChoices do
        children[#children+1] = gui.Label{
            classes = {"builder-base", "label", "choice-selection", "empty"},
            text = "Empty Slot",
            data = {
                featureGuid = feature.guid,
                itemIndex = i,
                selectedId = nil,
            },
            click = function(element)
                _fireControllerEvent(element, "deleteSkill", {
                    levelChoiceGuid = element.data.featureGuid,
                    itemIndex = element.data.itemIndex,
                    selectedId = element.data.selectedId,
                })
            end,
            linger = function(element)
                if element.data.selectedId then
                    gui.Tooltip("Press to delete")(element)
                end
            end,
            refreshBuilderState = function(element, state)
                element.data.selectedId = nil
                element.text = "Empty Slot"
                local creature = state:Get("token").properties
                if creature then
                    local levelChoices = creature:GetLevelChoices()
                    if levelChoices then
                        local selectedItems = levelChoices[element.data.featureGuid]
                        if selectedItems and #selectedItems >= element.data.itemIndex then
                            element.data.selectedId = selectedItems[element.data.itemIndex]
                            if element.data.selectedId then
                                local skillItem = dmhub.GetTableVisible(Skill.tableName)[element.data.selectedId]
                                if skillItem then
                                    element.text = skillItem.name
                                end
                            end
                        end
                    end
                end
                element:SetClass("filled", element.data.selectedId ~= nil)
                element:SetClass("empty", element.data.selectedId == nil)
            end,
        }
    end

    children[#children+1] = gui.MCDMDivider{
        classes = {"builder-divider"},
        layout = "v",
        width = "100%",
        vpad = 4,
        bgcolor = CharacterBuilder.COLORS.GOLD,
    }

    -- Items to select
    for _,item in ipairs(candidateSkills) do
        children[#children+1] = gui.Label{
            classes = {"builder-base", "label", "choice-option"},
            text = item.text,
            data = {
                id = item.id,
            },
            click = function(element)
                local parent = element:FindParentWithClass("skillSelector")
                if parent then
                    parent:FireEvent("selectItem", element.data.id)
                end
            end,
            refreshSkillSelection = function(element, selectedId)
                element:SetClass("selected", selectedId == element.data.id)
            end,
        }
    end

    children[#children+1] = CharacterBuilder._selectButton{
        click = function(element)
            local parent = element:FindParentWithClass("skillSelector")
            if parent then
                parent:FireEvent("applyCurrentItem")
            end
        end,
        refreshBuilderState = function(element, state)
            -- TODO:
        end,
    }

    return gui.Panel{
        classes = {"skillSelector", "builder-base", "panel"},
        width = "96%",
        height = "auto",
        halign = "left",
        flow = "vertical",

        data = {
            feature = feature,
            selectedId = nil,
        },

        applyCurrentItem = function(element)
            if element.data.selectedId then
                _fireControllerEvent(element, "applyLevelChoice", {
                    feature = feature,
                    selectedId = element.data.selectedId
                })
            end
        end,

        refreshBuilderState = function(element, state)
            local creature = state:Get("token").properties
        end,

        selectItem = function(element, itemId)
            element.data.selectedId = itemId
            element:FireEventTree("refreshSkillSelection", itemId)
        end,

        children = children,
    }
end

--- Build a feature panel with selections
--- @return Panel|nil
function CharacterBuilder._featurePanel(feature)
    -- print("THC:: FEATUREPANEL::", feature)
    -- print("THC:: FEATUREPANEL::", json(feature))

    local typeName = feature.typeName or ""
    if typeName == "CharacterDeityChoice" then
    elseif typeName == "CharacterFeatChoice" then
    elseif typeName == "CharacterFeatureChoice" then
    elseif typeName == "CharacterLanguageChoice" then
    elseif typeName == "CharacterSkillChoice" then
        return CharacterBuilder._featureSkillChoicePanel(feature)
    elseif typeName == "CharacterSubclassChoice" then
    end

    return nil
end

--- Create the Ancestry Features panel
--- @parameter feature CharacterFeature
--- @parameter selectorId string The selector this is a category under
--- @parameter selectedId string The unique identifier of the item associated with the feature
--- @parameter getSelected function(creature)
--- @return Panel|nil
function CharacterBuilder._featureRegistry(feature, selectorId, selectedId, getSelected)

    local featurePanel = CharacterBuilder._featurePanel(feature)

    if featurePanel then
        return {
            button = _makeCategoryButton{
                text = feature.name,
                data = {
                    featureId = feature.guid,
                    selectedId = selectedId,
                },
                click = function(element)
                    _fireControllerEvent(element, "updateState", {
                        key = selectorId .. ".category.selectedId",
                        value = element.data.featureId
                    })
                end,
                refreshBuilderState = function(element, state)
                    local tokenSelected = getSelected(state:Get("token").properties) or "nil"
                    local isVisible = tokenSelected == element.data.selectedId
                    element:FireEvent("setAvailable", isVisible)
                    element:FireEvent("setSelected", element.data.featureId == state:Get(selectorId .. ".category.selectedId"))
                    element:SetClass("collapsed", not isVisible)
                end,
            },
            panel = gui.Panel{
                classes = {"featurePanel", "builder-base", "panel-base", "collapsed"},
                width = "96%",
                height = "96%",
                flow = "vertical",
                valign = "top",
                halign = "center",
                tmargin = 12,
                vscroll = true,
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

--- Build the Ancestry Select button
--- @return PrettyButton|Panel
function CharacterBuilder._ancestrySelectButton()
    return CharacterBuilder._selectButton{
        click = function(element)
            _fireControllerEvent(element, "applyCurrentAncestry")
        end,
        refreshBuilderState = function(element, state)
            local creature = state:Get("token").properties
            if creature then
                local canSelect = creature:try_get("raceid") == nil and state:Get(SELECTOR .. ".selectedId") ~= nil
                element:SetClass("collapsed", not canSelect)
            end
        end,
    }
end

--- Build the Ancestry Detail Panel - the main center panel for Ancestry work
--- @return Panel
function CharacterBuilder._ancestryDetail()

    local ancestryNavPanel = CharacterBuilder._ancestryNavPanel()

    local ancestryOverviewPanel = CharacterBuilder._ancestryOverviewPanel()
    local ancestryLorePanel = CharacterBuilder._ancestryLorePanel()

    local ancestrySelectButton = CharacterBuilder._ancestrySelectButton()

    local ancestryDetailPanel = gui.Panel{
        id = "ancestryDetailPanel",
        classes = {"builder-base", "panel-base", "ancestryDetailpanel"},
        width = 660,
        height = "99%",
        valign = "center",
        halign = "center",
        borderColor = "teal",

        registerFeaturePanel = function(element, panel)
            element:AddChild(panel)
            local selectButton = element:FindChildRecursive(function(element) return element:HasClass("button-select") end)
            if selectButton then selectButton:SetAsLastSibling() end
        end,

        ancestryOverviewPanel,
        ancestryLorePanel,
        ancestrySelectButton,
    }

    return gui.Panel{
        id = "ancestryPanel",
        classes = {"builder-base", "panel-base", "ancestryPanel"},
        width = "100%",
        height = "100%",
        flow = "horizontal",
        valign = "center",
        halign = "center",
        borderColor = "yellow",
        data = {
            selector = SELECTOR,
            features = {},
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get("activeSelector") == element.data.selector
            element:SetClass("collapsed", not visible)
            if visible then
                local creature = state:Get("token").properties
                if creature then
                    local creatureAncestry = creature:try_get("raceid")

                    if creatureAncestry ~= nil then
                        for _,f in pairs(state:Get(SELECTOR .. ".featureDetails")) do
                            local featureId = f.feature:try_get("guid")
                            if featureId and element.data.features[featureId] == nil then
                                local featureRegistry = CharacterBuilder._featureRegistry(f.feature, SELECTOR, creatureAncestry, function(creature)
                                    return creature:try_get("raceid")
                                end)
                                if featureRegistry then
                                    element.data.features[featureId] = true
                                    ancestryNavPanel:FireEvent("registerFeatureButton", featureRegistry.button)
                                    ancestryDetailPanel:FireEvent("registerFeaturePanel", featureRegistry.panel)
                                end
                            end
                        end
                    else
                        -- No ancestry selected on creature
                        local categoryKey = SELECTOR .. ".category.selectedId"
                        local currentCategory = state:Get(categoryKey)
                        if currentCategory and not AVAILABLE_WITHOUT_ANCESTRY[currentCategory] then
                            state:Set({key = categoryKey, value = INITIAL_CATEGORY})
                        end
                    end
                end
            end
        end,

        ancestryNavPanel,
        ancestryDetailPanel,
    }
end
