--[[
    Kit detail / selectors
    mcdmkitbuilder.lua
]]
CBKitDetail = RegisterGameType("CBKitDetail")

local mod = dmhub.GetModLoading()

local SELECTOR = CharacterBuilder.SELECTOR.KIT

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getHero = CharacterBuilder._getHero

function CBKitDetail._navPanel()
    -- TODO: Maybe put inside another panel to shrink vertically.
    return gui.Panel{
        classes = {"categoryNavPanel", "builder-base", "panel-base", "detail-nav-panel"},
        vscroll = true,

        data = {
            classId = nil,
        },

        refreshBuilderState = function(element, state)
            local classId = state:Get(CharacterBuilder.SELECTOR.CLASS .. ".selectedId")
            if classId ~= element.data.classId then
                for i = #element.children, 1, -1 do
                    element.children[i]:DestroySelf()
                end
            end

            if #element.children == 0 then
                if classId ~= nil then
                    local featureCache = state:Get(SELECTOR .. ".featureCache")
                    if featureCache ~= nil then
                        local feature = featureCache:GetFeature(classId)
                        if feature ~= nil then
                            element:AddChild(CBFeatureSelector.SelectionPanel(SELECTOR, feature))
                        end
                    end
                end
            end
        end,
    }
end

--- The panel for showing information about kits or the selected kit
--- @return Panel
function CBKitDetail._overviewPanel()

    local nameLabel = gui.Label{
        classes = {"builder-base", "label", "info", "header"},
        width = "100%",
        height = "auto",
        hpad = 12,
        text = "KIT",
        textAlignment = "left",

        refreshBuilderState = function(element, state)
            -- TODO: Selected kit name
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
        markdown = true,
        text = CharacterBuilder.STRINGS.KIT.INTRO,

        refreshBuilderState = function(element, state)
            local text = CharacterBuilder.STRINGS.KIT.INTRO
            -- TODO: Selected kit description
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
        markdown = true,
        text = CharacterBuilder.STRINGS.KIT.OVERVIEW,

        refreshBuilderState = function(element, state)
            local text = CharacterBuilder.STRINGS.KIT.OVERVIEW
            -- TODO: Selected kit detail
            element.text = text
        end
    }

    return gui.Panel{
        id = "kitOverviewPanel",
        classes = {"kitOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "border"},
        bgimage = mod.images.kitHome,

        refreshBuilderState = function(element, state)
        end,

        gui.Panel{
            classes = {"builder-base", "panel-base", "detail-overview-labels"},
            nameLabel,
            introLabel,
            detailLabel,
        }
    }
end

--- The right side panel for the kit editor
--- @return Panel
function CBKitDetail._detailPanel()

    local overviewPanel = CBKitDetail._overviewPanel()

    return gui.Panel{
        id = "classDetailPanel",
        classes = {"builder-base", "panel-base", "inner-detail-panel", "wide", "classDetailpanel"},

        refreshBuilderState = function(element, state)
        end,

        overviewPanel,
    }
end

--- The main panel for working with kits
--- @return Panel
function CBKitDetail.CreatePanel()

    local navPanel = CBKitDetail._navPanel()

    local detailPanel = CBKitDetail._detailPanel()

    return gui.Panel{
        id = "classPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "classPanel"},
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
        end,

        navPanel,
        detailPanel,
    }
end