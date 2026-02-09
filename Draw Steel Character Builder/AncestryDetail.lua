--[[
    Ancestry detail / selectors
]]
CBAncestryDetail = RegisterGameType("CBAncestryDetail")

local mod = dmhub.GetModLoading()

local SELECTOR = CharacterBuilder.SELECTOR.ANCESTRY
local INITIAL_CATEGORY = "overview"
local AVAILABLE_WITHOUT_ANCESTRY = {overview = true, lore = true}

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getHero = CharacterBuilder._getHero
local _makeDetailNavButton = CharacterBuilder._makeDetailNavButton

--- Generate the Ancestry Category Navigation panel
--- @return Panel
function CBAncestryDetail._navPanel()

    local overviewButton = _makeDetailNavButton(SELECTOR, {
        text = "Overview",
        data = { category = INITIAL_CATEGORY },
    })

    local loreButton = _makeDetailNavButton(SELECTOR, {
        text = "Lore",
        data = { category = "lore" },
    })

    local changeButton = gui.Button{
        classes = {"changeAncestry", "builder-base", "button", "selector", "destructive"},
        text = "Change Ancestry",
        bold = false,
        data = { category = "change" },
        press = function(element)
            _fireControllerEvent("removeAncestry")
        end,
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local isAvailable = hero:try_get("raceid") ~= nil
                element:SetClass("collapsed", not isAvailable)
                element:FireEvent("setAvailable", isAvailable)
            end
        end,
    }

    local selectButton = gui.Button{
        classes = {"changeAncestry", "builder-base", "button", "selector"},
        text = "Select Ancestry",
        bold = false,
        data = { category = "select" },
        press = function(element)
            _fireControllerEvent("applyCurrentAncestry")
        end,
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            local isAvailable = state:Get(SELECTOR .. ".selectedId") ~= nil and hero:try_get("raceid") == nil
            element:SetClass("collapsed", not isAvailable)
            element:FireEvent("setAvailable", isAvailable)
        end,
    }

    return gui.Panel{
        classes = {"categoryNavPanel", "builder-base", "panel-base", "detail-nav-panel"},
        vscroll = true,

        create = function(element)
            _fireControllerEvent("updateState", {
                key = SELECTOR .. ".category.selectedId",
                value = INITIAL_CATEGORY,
            })
        end,

        registerFeatureButton = function(element, button)
            element:AddChild(button)
            element.children = CharacterBuilder._sortButtons(element.children)
        end,

        destroyFeature = function(element, featureId)
            local child = element:FindChildRecursive(function(e)
                return e.data and e.data.featureId == featureId
            end)
            if child then
                child:DestroySelf()
            end
        end,

        selectButton,
        changeButton,
        overviewButton,
        loreButton,
    }
end

--- Build the Ancestry Overview panel
--- @return Panel
function CBAncestryDetail._overviewPanel()

    local nameLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "header"},
            text = GameSystem.RaceName:upper(),

            refreshBuilderState = function(element, state)
                local text = GameSystem.RaceName:upper()
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
    }

    local introLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            markdown = true,
            text = CharacterBuilder.STRINGS.ANCESTRY.INTRO,

            refreshBuilderState = function(element, state)
                local text = CharacterBuilder.STRINGS.ANCESTRY.INTRO
                local ancestryId = state:Get(SELECTOR .. ".selectedId")
                if ancestryId then
                    local raceItem = state:Get(SELECTOR .. ".selectedItem")
                    if not raceItem then
                        raceItem = dmhub.GetTable(Race.tableName)[ancestryId]
                    end
                    if raceItem then text = raceItem.details end
                end
                element.text = text
            end,
        },
    }

    local detailLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            bold = false,
            markdown = true,
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

                    local featureCache = state:Get(SELECTOR .. ".featureCache")
                    local featureDetails = featureCache:GetFlattenedFeatures()
                    for _,item in ipairs(featureDetails) do
                        local s = item.feature:GetDetailedSummaryText()
                        if s ~= nil and #s > 0 then
                            textItems[#textItems+1] = s
                        end
                    end

                    text = table.concat(textItems, "\n\n")
                end
                element.text = text
            end
        },
    }

    local spacerPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        width = "50%",
        height = "66%",
    }

    return gui.Panel{
        id = "ancestryOverviewPanel",
        classes = {"ancestryOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "border", "collapsed"},
        bgimage = mod.images.ancestryHome,

        data = {
            category = "overview",
        },

        refreshBuilderState = function(element, state)
            local ancestryId = state:Get(SELECTOR .. ".selectedId")

            local visible = ancestryId == nil or state:Get(SELECTOR .. ".category.selectedId") == element.data.category
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end

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
            classes = {"builder-base", "panel-base", "container"},
            height = "100%-40",
            bmargin = 32,
            valign = "bottom",
            vscroll = true,
            data = {
                lastSelected = nil,
            },

            refreshBuilderState = function(element, state)
                local currentSelected = state:Get(SELECTOR .. ".selectedId")
                if currentSelected ~= element.data.lastSelected then
                    element.data.lastSelected = currentSelected
                    element.vscrollPosition = 1
                end
            end,

            spacerPanel,
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
            local visible = state:Get(SELECTOR .. ".category.selectedId") == element.data.category
            element:SetClass("collapsed", not visible)
        end,

        gui.Panel{
            classes = {"builder-base", "panel-base", "container"},
            width = "100%",
            height = "auto",
            valign = "top",
            gui.Label{
                classes = {"builder-base", "label", "info", "overview"},
                halign = "center",
                height = "auto",
                tmargin = 20,
                text = "",
                wrap = true,
                textAlignment = "topLeft",

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
            },
        },
    }
end

--- Build the Ancestry Detail Panel - the main center panel for Ancestry work
--- @return Panel
function CBAncestryDetail.CreatePanel()

    local navPanel = CBAncestryDetail._navPanel()

    local overviewPanel = CBAncestryDetail._overviewPanel()
    local lorePanel = CBAncestryDetail._lorePanel()

    local detailPanel = gui.Panel{
        id = "ancestryDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "ancestryDetailpanel"},

        registerFeaturePanel = function(element, panel)
            element:AddChild(panel)
            local selectButton = element:FindChildRecursive(function(e) return e:HasClass("selectButton") end)
            if selectButton then selectButton:SetAsLastSibling() end
        end,

        destroyFeature = function(element, featureId)
            local child = element:FindChildRecursive(function(e)
                return e.data and e.data.featureId == featureId
            end)
            if child then
                child:DestroySelf()
            end
        end,

        overviewPanel,
        lorePanel,
    }

    return gui.Panel{
        id = "ancestryPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "ancestryPanel"},
        data = {
            selector = SELECTOR,
            features = {},
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get("activeSelector") == element.data.selector
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end

            local categoryKey = SELECTOR .. ".category.selectedId"
            local currentCategory = state:Get(categoryKey) or INITIAL_CATEGORY
            local hero = _getHero()
            if hero then
                local heroAncestry = state:Get(SELECTOR .. ".selectedId") --hero:try_get("raceid")

                if heroAncestry ~= nil then
                    for id,_ in pairs(element.data.features) do
                        element.data.features[id] = false
                    end

                    local featureCache = state:Get(SELECTOR .. ".featureCache")
                    local features = featureCache:GetSortedFeatures()
                    for _,f in ipairs(features) do
                        local featureId = f.guid
                        local feature = featureCache:GetFeature(featureId)
                        if feature then
                            if element.data.features[featureId] == nil then
                                local featureRegistry = CharacterBuilder._makeFeatureRegistry{
                                    feature = feature,
                                    selector = SELECTOR,
                                    selectedId = heroAncestry,
                                    getSelected = function(hero)
                                        return heroAncestry --hero:try_get("raceid")
                                    end
                                }
                                if featureRegistry then
                                    element.data.features[featureId] = true
                                    navPanel:FireEvent("registerFeatureButton", featureRegistry.button)
                                    detailPanel:FireEvent("registerFeaturePanel", featureRegistry.panel)
                                end
                            else
                                element.data.features[featureId] = true
                            end
                        end
                    end

                    for id,active in pairs(element.data.features) do
                        if active == false then
                            navPanel:FireEvent("destroyFeature", id)
                            detailPanel:FireEvent("destroyFeature", id)
                            element.data.features[id] = nil
                        end
                    end
                else
                    if not AVAILABLE_WITHOUT_ANCESTRY[currentCategory] then
                        currentCategory = INITIAL_CATEGORY
                    end
                end
            end

            -- Which category to show?
            if not AVAILABLE_WITHOUT_ANCESTRY[currentCategory] then
                if not element.data.features[currentCategory] then
                    currentCategory = INITIAL_CATEGORY
                end
            end
            state:Set{ key = categoryKey, value = currentCategory }
        end,

        navPanel,
        detailPanel,
    }
end
