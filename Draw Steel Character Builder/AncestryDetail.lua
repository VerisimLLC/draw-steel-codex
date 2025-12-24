--[[
    Ancestry detail / selectors
]]
CBAncestryDetail = RegisterGameType("CBAncestryDetail")

local mod = dmhub.GetModLoading()

local SELECTOR = "ancestry"
local INITIAL_CATEGORY = "overview"
local AVAILABLE_WITHOUT_ANCESTRY = {overview = true, lore = true}

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getCreature = CharacterBuilder._getCreature
local _getState = CharacterBuilder._getState
local _makeCategoryButton = CharacterBuilder._makeCategoryButton

--- Generate the Ancestry Category Navigation panel
--- @return Panel
function CBAncestryDetail._navPanel()

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
            local creature = _getCreature(state)
            if creature then
                element:FireEvent("setAvailable", creature:try_get("raceid") ~= nil)
            end
        end,
    }

    return gui.Panel{
        classes = {"categoryNavPanel", "panel-base", "builder-base"},
        width = CBStyles.SIZES.BUTTON_PANEL_WIDTH + 20,
        height = "99%",
        valign = "top",
        vpad = CBStyles.SIZES.ACTION_BUTTON_HEIGHT,
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
function CBAncestryDetail._overviewPanel()

    local nameLabel = gui.Label{
        classes = {"builder-base", "label", "info", "header"},
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
        classes = {"builder-base", "label", "info"},
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
        classes = {"builder-base", "label", "info"},
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
        classes = {"ancestryOverviewPanel", "builder-base", "panel-base", "border", "collapsed"},
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
function CBAncestryDetail._lorePanel()
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
            classes = {"builder-base", "label", "info"},
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

--- Build the Ancestry Select button
--- @return PrettyButton|Panel
function CBAncestryDetail._selectButton()
    return CharacterBuilder._makeSelectButton{
        classes = {"ancestrySelectButton"},
        click = function(element)
            _fireControllerEvent(element, "applyCurrentAncestry")
        end,
        refreshBuilderState = function(element, state)
            local creature = _getCreature(state)
            if creature then
                local canSelect = creature:try_get("raceid") == nil and state:Get(SELECTOR .. ".selectedId") ~= nil
                element:SetClass("collapsed", not canSelect)
            end
        end,
    }
end

--- Build the Ancestry Detail Panel - the main center panel for Ancestry work
--- @return Panel
function CBAncestryDetail.CreatePanel()

    local ancestryNavPanel = CBAncestryDetail._navPanel()

    local ancestryOverviewPanel = CBAncestryDetail._overviewPanel()
    local ancestryLorePanel = CBAncestryDetail._lorePanel()

    local ancestrySelectButton = CBAncestryDetail._selectButton()

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
            local selectButton = element:FindChildRecursive(function(e) return e:HasClass("ancestrySelectButton") end)
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
                local creature = _getCreature(state)
                if creature then
                    local creatureAncestry = creature:try_get("raceid")

                    if creatureAncestry ~= nil then
                        for _,f in pairs(state:Get(SELECTOR .. ".featureDetails")) do
                            local featureId = f.feature:try_get("guid")
                            if featureId and element.data.features[featureId] == nil then
                                local featureRegistry = CharacterBuilder._makeFeatureRegistry(f.feature, SELECTOR, creatureAncestry, function(creature)
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
