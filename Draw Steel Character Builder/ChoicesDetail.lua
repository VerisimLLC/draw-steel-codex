--[[
    Choices Detail

    Catch-all section for any CharacterChoice-derived features that aren't
    covered by the per-source tabs (Ancestry, Class, Career, etc.). Currently
    used by the monster builder path; can be extended to heroes later.
]]
CBChoicesDetail = RegisterGameType("CBChoicesDetail")

local SEL = CharacterBuilder.SELECTOR
local _getHero = CharacterBuilder._getHero
local _getCreature = CharacterBuilder._getCreature
local _safeGet = CharacterBuilder._safeGet
local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _makeDetailNavButton = CharacterBuilder._makeDetailNavButton

local mod = dmhub.GetModLoading()

local SELECTOR = SEL.CHOICES
local INITIAL_CATEGORY = "overview"
local CHOICES_SENTINEL = "choices"

function CBChoicesDetail._navPanel()

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

--- Build a single overview entry for a feature that grants choices: its
--- title and (when present) its description text.
--- @param title string|nil Omitted when the feature name is already the section header.
--- @param description string|nil
--- @return Panel
local function _featureOverviewEntry(title, description)
    local children = {}

    if title ~= nil and title ~= "" then
        children[#children+1] = gui.Label{
            classes = {"builder-base", "label", "info", "overview", "detail-header"},
            text = title,
        }
    end

    if description ~= nil and description ~= "" then
        children[#children+1] = gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            vpad = 6,
            markdown = true,
            text = description,
        }
    end

    return gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        children = children,
    }
end

--- Return the cached features that actually grant choices, in sorted order.
--- The cache can hold features whose choices are accounted for elsewhere
--- (or who grant none); those report zero choices and are filtered out here.
--- @param featureCache CBFeatureCache|nil
--- @return CBFeatureWrapper[]
local function _featuresWithChoices(featureCache)
    local result = {}
    if featureCache == nil then return result end
    for _,item in ipairs(featureCache:GetSortedFeatures()) do
        local feature = featureCache:GetFeature(item.guid)
        if feature ~= nil and feature:GetNumChoices() > 0 then
            result[#result+1] = feature
        end
    end
    return result
end

--- Resolve the title for the Choices overview header.
---
--- Choice features are usually sub-choices housed under a single parent --
--- a feat, template, or monster group (e.g. four "Choice of X Traits"
--- features all granted by an "Animal Traits" template). When every
--- choice feature traces back to the same parent, that parent's name
--- titles the section. A lone choice feature with no parent titles the
--- section with its own name. Anything else falls back to "CHOICES".
--- @param features CBFeatureWrapper[] The choice-granting features (from _featuresWithChoices).
--- @param creature creature|nil
--- @return string
local function _choicesTitle(features, creature)
    if #features == 0 then
        return "CHOICES"
    end

    -- Map each choice feature's guid to the parent that houses it. The
    -- builder's own choice enumeration carries the originating feat /
    -- template / monster group alongside each flattened choice feature.
    local parents = {}
    if creature ~= nil and creature.GetBuilderChoiceFeatures ~= nil then
        for _,entry in ipairs(creature:GetBuilderChoiceFeatures()) do
            local feature = entry.feature
            local parent = entry.feat or entry.monsterGroup
            if feature ~= nil and parent ~= nil then
                parents[feature.guid] = parent
            end
        end
    end

    -- Every choice feature must resolve to the same owner for the header to
    -- adopt its name. A choice's owner is its parent when it has one, else
    -- the choice itself; compare owners by object identity.
    local ownerKey = nil
    local ownerName = nil
    for _,feature in ipairs(features) do
        local parent = parents[feature:GetGuid()]
        local key, name
        if parent ~= nil then
            key = parent
            name = _safeGet(parent, "name", "")
        else
            key = feature:GetGuid()
            name = feature:GetName()
        end

        if ownerKey == nil then
            ownerKey = key
            ownerName = name
        elseif ownerKey ~= key then
            return "CHOICES"
        end
    end

    if ownerName == nil or ownerName == "" then
        return "CHOICES"
    end
    return ownerName
end

function CBChoicesDetail._overviewPanel()

    -- Section header. Its text is set by featureListPanel's refreshBuilderState
    -- (via _choicesTitle) so the title and the feature list stay in sync.
    local headerLabel = gui.Label{
        classes = {"builder-base", "label", "info", "overview", "header"},
        text = "CHOICES",
    }

    local nameLabel = gui.Panel{
        classes = {"builder-base", "panel-base", "detail-overview-labels"},
        headerLabel,
    }

    -- Built on demand only when no features actually grant choices yet.
    -- Created lazily so an unused instance is never left orphaned.
    local function makeEmptyLabel()
        return gui.Panel{
            classes = {"builder-base", "panel-base", "detail-overview-labels"},
            gui.Label{
                classes = {"builder-base", "label", "info", "overview"},
                vpad = 6,
                markdown = true,
                text = CharacterBuilder.STRINGS.CHOICES.INTRO,
            },
        }
    end

    -- Lists the features granting additional choices, showing each feature's
    -- title and description rather than generic boilerplate text.
    local featureListPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "container"},
        width = "100%",
        height = "auto",
        flow = "vertical",

        data = {
            -- Signature of the currently-rendered feature set; used to skip
            -- rebuilding the child panels when nothing relevant changed.
            signature = nil,
        },

        refreshBuilderState = function(element, state)
            local featureCache = state:Get(SELECTOR .. ".featureCache")
            local features = _featuresWithChoices(featureCache)

            local sigParts = {}
            for _,feature in ipairs(features) do
                sigParts[#sigParts+1] = feature:GetGuid()
            end
            local signature = table.concat(sigParts, "|")
            if signature == element.data.signature then return end
            element.data.signature = signature

            -- Keep the section header in sync with the feature set: a shared
            -- parent feature's name when there is one, else "CHOICES".
            headerLabel.text = _choicesTitle(features, _getCreature())

            -- A single feature's name already titles the section, so omit
            -- the redundant per-entry title in that case.
            local single = #features == 1

            local children = {}
            for _,feature in ipairs(features) do
                local title = nil
                if not single then
                    title = feature:GetName()
                end
                children[#children+1] = _featureOverviewEntry(title, feature:GetDescription())
            end

            if #children == 0 then
                children = {makeEmptyLabel()}
            end

            element.children = children
        end,
    }

    return gui.Panel{
        id = "choicesOverviewPanel",
        -- No artwork for the Choices section: surfaceLinear paints a theme
        -- gradient over the detail-overview-panel's white default.
        classes = {"choicesOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "surfaceLinear", "border", "collapsed"},

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
            tmargin = 32,
            valign = "top",
            vscroll = true,
            nameLabel,
            featureListPanel,
        }
    }
end

function CBChoicesDetail._detailPanel()

    local overviewPanel = CBChoicesDetail._overviewPanel()

    return gui.Panel{
        id = "choicesDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "choicesDetailPanel"},

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

function CBChoicesDetail.CreatePanel()

    local navPanel = CBChoicesDetail._navPanel()
    local detailPanel = CBChoicesDetail._detailPanel()

    return gui.Panel{
        id = "choicesPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "choicesPanel"},
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
                            selectedId = CHOICES_SENTINEL,
                            getSelected = function(hero)
                                return CHOICES_SENTINEL
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

            for id,active in pairs(element.data.features) do
                if active == false then
                    navPanel:FireEvent("destroyFeature", id)
                    detailPanel:FireEvent("destroyFeature", id)
                    element.data.features[id] = nil
                end
            end
        end,

        navPanel,
        detailPanel,
    }
end
