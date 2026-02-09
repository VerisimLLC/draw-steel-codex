--[[
    Career detail / selectors
]]
CBCareerDetail = RegisterGameType("CBCareerDetail")

local mod = dmhub.GetModLoading()

local SELECTOR = CharacterBuilder.SELECTOR.CAREER
local INITIAL_CATEGORY = "overview"
local AVAILABLE_WITHOUT_CAREER = {overview = true}

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getHero = CharacterBuilder._getHero
local _makeDetailNavButton = CharacterBuilder._makeDetailNavButton

--- Build the overview panel
--- @return Panel
function CBCareerDetail._overviewPanel()

    local nameLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "header"},
            text = GameSystem.BackgroundName:upper(),

            refreshBuilderState = function(element, state)
                local text = GameSystem.BackgroundName:upper()
                local careerId = state:Get(SELECTOR .. ".selectedId")
                if careerId then
                    local careerItem = state:Get(SELECTOR .. ".selectedItem")
                    if careerItem then
                        text = careerItem.name
                    end
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
            text = CharacterBuilder.STRINGS.CAREER.INTRO,

            refreshBuilderState = function(element, state)
                local text = CharacterBuilder.STRINGS.CAREER.INTRO
                local careerId = state:Get(SELECTOR .. ".selectedId")
                if careerId then
                    local careerItem = state:Get(SELECTOR .. ".selectedItem")
                    if careerItem then
                        text = careerItem.description
                    end
                end
                element.text = text
            end,
        }
    }

    local detailLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            bold = false,
            text = CharacterBuilder.STRINGS.CAREER.OVERVIEW,

            refreshBuilderState = function(element, state)
                local text = CharacterBuilder.STRINGS.CAREER.OVERVIEW
                local careerId = state:Get(SELECTOR .. ".selectedId")
                if careerId then
                    local careerItem = state:Get(SELECTOR .. ".selectedItem")
                    if careerItem then
                        local featureCache = state:Get(SELECTOR .. ".featureCache")
                        local featureDetails = featureCache:GetFlattenedFeatures()
                        if featureDetails then
                            local textItems = {}
                            for _,item in ipairs(featureDetails) do
                                local s = item.feature:GetSummaryText()
                                if s ~= nil and #s > 0 then
                                    textItems[#textItems+1] = s
                                end
                            end
                            text = table.concat(textItems, "\n\n")
                        end
                    end
                end
                element.text = text
            end
        }
    }

    local spacerPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        width = "50%",
        height = "66%",
    }

    return gui.Panel{
        id = "careerOverviewPanel",
        classes = {"careerOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "border", "collapsed"},
        bgimage = mod.images.careerHome,

        data = {
            category = "overview",
        },

        refreshBuilderState = function(element, state)
            local careerId = state:Get(SELECTOR .. ".selectedId")

            local visible = careerId == nil or state:Get(SELECTOR .. ".category.selectedId") == element.data.category
            element:SetClass("collapsed", not visible)

            if not visible then
                element:HaltEventPropagation()
                return
            end

            if careerId == nil then
                element.bgimage = mod.images.careerHome
                return
            end
            -- TODO: Selected career image?
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

--- Generate the navigation panel
--- @return Panel
function CBCareerDetail._navPanel()

    local overviewButton = _makeDetailNavButton(SELECTOR, {
        text = "Overview",
        data = { category = INITIAL_CATEGORY },
    })

    local changeButton = gui.PrettyButton{
        classes = {"changeCareer", "builder-base", "button", "selector", "destructive"},
        width = CBStyles.SIZES.CATEGORY_BUTTON_WIDTH,
        height = CBStyles.SIZES.CATEGORY_BUTTON_HEIGHT,
        text = "Change Career",
        data = { category = "change" },
        press = function(element)
            _fireControllerEvent("removeCareer")
        end,
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            if hero then
                local isAvailable = hero:try_get("backgroundid") ~= nil
                element:SetClass("collapsed", not isAvailable)
                element:FireEvent("setAvailable", isAvailable)
            end
        end,
    }

    local selectButton = gui.PrettyButton{
        classes = {"changeCareer", "builder-base", "button", "selector"},
        width = CBStyles.SIZES.CATEGORY_BUTTON_WIDTH,
        height = CBStyles.SIZES.CATEGORY_BUTTON_HEIGHT,
        text = "Select Career",
        data = { category = "select" },
        press = function(element)
            _fireControllerEvent("applyCurrentCareer")
        end,
        refreshBuilderState = function(element, state)
            local hero = _getHero()
            local isAvailable = state:Get(SELECTOR .. ".selectedId") ~= nil and hero:try_get("backgroundid") == nil
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
    }
end

--- Build the career detail panel - the main central panel for Career work
--- @return Panel
function CBCareerDetail.CreatePanel()

    local navPanel = CBCareerDetail._navPanel()
    local overviewPanel = CBCareerDetail._overviewPanel()

    local detailPanel = gui.Panel{
        id = "careerDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "careerDetailpanel"},

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
    }

    return gui.Panel{
        id = "careerPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "careerPanel"},
        data = {
            selector = SELECTOR,
            features = {},
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get("activeSelector") == element.data.selector
            element:SetClass("collapsed-anim", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end

            local categoryKey = SELECTOR .. ".category.selectedId"
            local currentCategory = state:Get(categoryKey) or INITIAL_CATEGORY
            local hero = _getHero()
            if hero then
                local heroCareer = state:Get(SELECTOR .. ".selectedId") --hero:try_get("backgroundid")

                if heroCareer ~= nil then
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
                                    selectedId = heroCareer,
                                    getSelected = function(hero)
                                        return heroCareer
                                    end,
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

                    -- Clean up orphaned features
                    for id, active in pairs(element.data.features) do
                        if active == false then
                            navPanel:FireEvent("destroyFeature", id)
                            detailPanel:FireEvent("destroyFeature", id)
                            element.data.features[id] = nil
                        end
                    end
                else
                    if not AVAILABLE_WITHOUT_CAREER[currentCategory] then
                        currentCategory = INITIAL_CATEGORY
                    end
                end
            end

            -- Which category to show?
            if not AVAILABLE_WITHOUT_CAREER[currentCategory] then
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