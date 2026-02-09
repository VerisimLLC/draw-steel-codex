--[[
    Complication Detail
]]
CBComplicationDetail = RegisterGameType("CBComplicationDetail")

local SEL = CharacterBuilder.SELECTOR
local _getHero = CharacterBuilder._getHero
local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _makeDetailNavButton = CharacterBuilder._makeDetailNavButton

local mod = dmhub.GetModLoading()

local SELECTOR = SEL.COMPLICATION
local INITIAL_CATEGORY = "overview"
local COMPLICATION_GUID = "53fd20e0-c6c2-4858-b9de-80a2e3213871"

function CBComplicationDetail._navPanel()

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

function CBComplicationDetail._overviewPanel()

    local nameLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "header"},
            text = "COMPLICATION",
        }
    }

    local introLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            markdown = true,
            text = CharacterBuilder.STRINGS.COMPLICATION.INTRO,
        },
    }

    return gui.Panel{
        id = "complicationOverviewPanel",
        classes = {"complicationOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "border", "collapsed"},
        bgimage = mod.images.complicationHome,

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
            -- detailLabel,
        }
    }
end

function CBComplicationDetail._detailPanel()

    local overviewPanel = CBComplicationDetail._overviewPanel()

    return gui.Panel{
        id = "complicationDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "complicationDetailPanel"},

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

function CBComplicationDetail.CreatePanel()

    local navPanel = CBComplicationDetail._navPanel()
    local detailPanel = CBComplicationDetail._detailPanel()

    return gui.Panel{
        id = "complicationPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "complicationPanel"},
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
                local features = featureCache and featureCache:GetSortedFeatures() or {}
                for _,f in ipairs(features) do
                    local featureId = f.guid
                    local feature = featureCache:GetFeature(featureId)
                    if feature then
                        if element.data.features[featureId] == nil then
                            local featureRegistry = CharacterBuilder._makeFeatureRegistry{
                                feature = feature,
                                selector = SELECTOR,
                                selectedId = COMPLICATION_GUID,
                                getSelected = function(hero)
                                    return COMPLICATION_GUID
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
        end,

        navPanel,
        detailPanel,
    }
end