--[[
    Culture Detail
]]
CBCultureDetail = RegisterGameType("CBCultureDetail")

local SEL = CharacterBuilder.SELECTOR
local _getHero = CharacterBuilder._getHero
local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _makeDetailNavButton = CharacterBuilder._makeDetailNavButton

local mod = dmhub.GetModLoading()

local SELECTOR = SEL.CULTURE
local INITIAL_CATEGORY = "overview"
local CULTURE_GUID = "46e8555b-a2c7-4ec4-883f-34a4885856c6"
local ALWAYS_AVAILABLE = {overview = true,}

function CBCultureDetail._navPanel()

    local overviewButton = _makeDetailNavButton(SELECTOR, {
        text = "Overview",
        data = { category = INITIAL_CATEGORY },
        refreshBuilderState = function(element, state)
            element:FireEvent("setAvailable", true)
            element:FireEvent("setSelected", state:Get(SELECTOR .. ".category.selectedId") == element.data.category)
        end,
    })

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
            local changeButton = element:FindChildRecursive(function(element) return element:HasClass("changeCareer") end)
            if changeButton then changeButton:SetAsLastSibling() end
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

        overviewButton,
    }
end

function CBCultureDetail._overviewPanel()

    local nameLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "header"},
            text = "CULTURE",
        }
    }

    local introLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            markdown = true,
            text = CharacterBuilder.STRINGS.CULTURE.INTRO,
        },
    }

    local detailLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            bold = false,
            markdown = true,
            text = CharacterBuilder.STRINGS.CULTURE.OVERVIEW,
        },
    }

    return gui.Panel{
        id = "cultureOverviewPanel",
        classes = {"cultureOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "border", "collapsed"},
        bgimage = mod.images.cultureHome,

        data = {
            category = "overview",
        },

        refreshBuilderState = function(element, state)
            local visible = state:Get(SELECTOR .. ".category.selectedId") == element.data.category
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end
        end,

        gui.Panel{
            classes = {"builder-base", "panel-base", "container"},
            height = "100%-40",
            bmargin = 32,
            valign = "bottom",
            vscroll = true,
            nameLabel,
            introLabel,
            detailLabel,
        }
    }
end

function CBCultureDetail._detailPanel()

    local overviewPanel = CBCultureDetail._overviewPanel()

    return gui.Panel{
        id = "cultureDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "cultureDetailPanel"},

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
end

function CBCultureDetail.CreatePanel()

    local navPanel = CBCultureDetail._navPanel()
    local detailPanel = CBCultureDetail._detailPanel()

    return gui.Panel{
        id = "culturePanel",
        classes = {"builder-base", "panel-base", "detail-panel", "culturePanel"},
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
                                selectedId = CULTURE_GUID,
                                getSelected = function(hero)
                                    return CULTURE_GUID
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
                currentCategory = INITIAL_CATEGORY
            end

            -- Which category to show?
            if not ALWAYS_AVAILABLE[currentCategory] then
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