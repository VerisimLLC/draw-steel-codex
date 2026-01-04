--[[
    Kit detail / selectors
    mcdmkitbuilder.lua
      Kit merge ~607
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
        classes = {"builder-base", "label", "info", "overview", "header"},
        text = "KIT",

        updateSelectedKit = function(element, kitItem, kitItem2)
            local text = "KIT"
            if kitItem then
                local kitNames = {
                    kitItem.name
                }
                if kitItem2 then
                    kitNames[#kitNames+1] = kitItem2.name
                    table.sort(kitNames)
                end
                text = table.concat(kitNames, " & ")
            end
            element.text = text
        end,
    }

    local kitTypeLabel = gui.Label{
        classes = {"builder-base", "label", "info", "overview", "collapsed"},
        updateSelectedKit = function(element, kitItem, kitItem2)
            local text = ""
            if kitItem then
                for _,t in ipairs(Kit.kitTypes) do
                    if t.id == kitItem.type then
                        text = string.format("%s Kit", t.text)
                        break
                    end
                end
            end
            element.text = text
            element:SetClass("collapsed", #text == 0)
        end,
    }

    local introLabel = gui.Label{
        classes = {"builder-base", "label", "info", "overview"},
        vpad = 6,
        bmargin = 12,
        markdown = true,
        text = CharacterBuilder.STRINGS.KIT.INTRO,

        updateSelectedKit = function(element, kitItem, kitItem2)
            local visible = kitItem2 == nil
            element:SetClass("collapsed", not visible)
            if not visible then return end

            local text = CharacterBuilder.STRINGS.KIT.INTRO
            text = kitItem and kitItem.description or text
            element.text = text
        end,
    }

    local equipmentPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "info", "overview", "container"},
        vpad = 6,
        bmargin = 12,
        updateSelectedKit = function(element, kitItem, kitItem2)
            local visible = kitItem ~= nil 
                and ((kitItem.description and #kitItem.description > 0)
                or (kitItem2 and kitItem2.description and #kitItem2.description > 0))
            element:SetClass("collapsed", not visible)
            if not visible then 
                element:HaltEventPropagation()
                return
            end
        end,
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "detail-header"},
            text = "Equipment",
        },
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            updateSelectedKit = function(element, kitItem, kitItem2)
                local text = kitItem and kitItem.description
                if kitItem2 and #kitItem2.description > 0 then
                    if #text > 0 then text = text .. "\n" end
                    text = text .. kitItem2.description
                end
                element.text = #text > 0 and text or "No equipment description found."
            end,
        }
    }

    local bonusesPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "info", "overview", "container"},
        vpad = 6,
        bmargin = 12,
        updateSelectedKit = function(element, kitItem)
            local visible = kitItem ~= nil
            element:SetClass("collapsed", not visible)
            if not visible then
                element:HaltEventPropagation()
                return
            end
        end,
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "detail-header"},
            text = "Bonuses",
        },
        gui.Label{
            classes = {"builder-base", "label", "info", "overview"},
            markdown = true,
            updateSelectedKit = function(element, kitItem, kitItem2)
                if kitItem == nil then return end
                local bonuses = {}
                local health = math.max(kitItem.health or 0, kitItem2 and kitItem2.health or 0)
                if health ~= 0 then
                    bonuses[#bonuses+1] = string.format("**%s** +%d per echelon", tr("Stamina Bonus:"), health)
                end
                local speed = math.max(kitItem.speed or 0, kitItem2 and kitItem2.speed or 0)
                if speed ~= 0 then
                    bonuses[#bonuses+1] = string.format("**%s** +%d", tr("Speed Bonus:"), speed)
                end
                local range = math.max(kitItem.range or 0, kitItem2 and kitItem2.range or 0)
                if range ~= 0 then
                    bonuses[#bonuses+1] = string.format("**%s** +%d", tr("Distance Bonus:"), range)
                end
                local reach = math.max(kitItem.reach or 0, kitItem2 and kitItem2.reach or 0)
                if reach ~= 0 then
                    bonuses[#bonuses+1] = string.format("**%s** +%d", tr("Reach Bonus:"), reach)
                end
                local area = math.max(kitItem.area or 0, kitItem2 and kitItem2.area or 0)
                if area ~= 0 then
                    bonuses[#bonuses+1] = string.format("**%s** +%d", tr("Area Bonus:"), area)
                end
                local disengage = math.max(kitItem.disengage or 0, kitItem2 and kitItem2.disengage or 0)
                if disengage ~= 0 then
                    bonuses[#bonuses+1] = string.format("**%s** +%d", tr("Disengage Bonus:"), disengage)
                end
                local stability = math.max(kitItem.stability or 0, kitItem2 and kitItem2.stability or 0)
                if stability ~= 0 then
                    bonuses[#bonuses+1] = string.format("**%s** +%d", tr("Stability Bonus:"), stability)
                end

                -- Bonus damge that id not duplicated. Dups require different UI - next panel down.
                for _,bonusEntry in ipairs(Kit.damageBonusTypes) do
                    local bonusText1 = kitItem and kitItem:FormatDamageBonus(bonusEntry.id)
                    local bonusText2 = kitItem2 and kitItem2:FormatDamageBonus(bonusEntry.id)
                    if bonusText1 and #(bonusText2 or "") == 0 then
                        bonuses[#bonuses+1] = string.format("**%s:** %s", bonusEntry.text, bonusText1)
                    end
                    if bonusText2 and #(bonusText1 or "") == 0 then
                        bonuses[#bonuses+1] = string.format("**%s:** %s", bonusEntry.text, bonusText2)
                    end
                end

                local text = table.concat(bonuses, "\n")
                element.text = text
            end,
        },
        gui.Panel{
            classes = {"container"},
            height = "auto",
            updateSelectedKit = function(element, kitItem, kitItem2)
                if kitItem == nil or kitItem2 == nil then
                    element:SetClass("collapsed")
                    return
                end
                -- TODO: Bonus selection when we have 2 kits and they both have
                -- the same bonus type

                -- for _,bonusEntry in ipairs(Kit.damageBonusTypes) do
                --     local bonusText1 = kitItem and kitItem:FormatDamageBonus(bonusEntry.id)
                --     local bonusText2 = kitItem2 and kitItem2:FormatDamageBonus(bonusEntry.id)
                --     if bonusText1 then
                --         bonuses[#bonuses+1] = string.format("**%s:** %s", bonusEntry.text, bonusText1)
                --     end
                --     if bonusText2 then
                --         bonuses[#bonuses+1] = string.format("**%s:** %s", bonusEntry.text, bonusText2)
                --     end
                -- end
            end,
        }
    }

    local abilityPanel = gui.Panel{
        classes = {"builder-base", "panel-base", "info", "overview", "container"},
        vpad = 6,
        bmargin = 12,
        updateSelectedKit = function(element, kitItem)
            local visible = kitItem ~= nil
            element:SetClass("collapsed", not visible)
            if not visible then 
                element:HaltEventPropagation()
                return
            end
        end,
        gui.Label{
            classes = {"builder-base", "label", "info", "overview", "detail-header"},
            text = "Signature Ability",
        },
        gui.Panel{
            classes = {"builder-base", "panel-base", "container"},
            height = "44%",
            vscroll = true,
            bgimage = true,
            bgcolor = "#10110FE5",
            updateSelectedKit = function(element, kitItem, kitItem2)
                local children = {}
                local function processAbilities(item)
                    for _,ability in ipairs(item:SignatureAbilities()) do
                        children[#children+1] = ability:Render({
                            width = "90%",
                            halign = "left",
                            valign = "top",
                            hmargin = 40,
                            vmargin = 6,
                        }, {})
                    end
                end
                if kitItem then
                    processAbilities(kitItem)
                    if kitItem2 then processAbilities(kitItem2) end
                    element.children = children
                end
            end
        }
    }

    local detailLabel = gui.Label{
        classes = {"builder-base", "label", "info", "overview"},
        vpad = 6,
        tmargin = 12,
        bold = false,
        markdown = true,
        text = CharacterBuilder.STRINGS.KIT.OVERVIEW,

        updateSelectedKit = function(element, kitItem)
            element:SetClass("collapsed", kitItem ~= nil)
        end
    }

    return gui.Panel{
        id = "kitOverviewPanel",
        classes = {"kitOverviewPanel", "builder-base", "panel-base", "detail-overview-panel", "border"},
        bgimage = mod.images.kitHome,

        updateSelectedKit = function(element, kitItem, kitItem2)
            local bgImage = mod.images.kitHome
            if kitItem and kitItem:try_get("portraitid") and #kitItem.portraitid > 0 then
                bgImage = kitItem.portraitid
            end
            if bgImage == mod.images.kitHome and kitItem2 and kitItem2:try_get("portraitid") and #kitItem2.portraitid > 0 then
                bgImage = kitItem2.portraitid
            end
            if element.bgimage ~= bgImage then
                element.bgimage = bgImage
            end
            element:SetClass("has-kit", kitItem ~= nil)
        end,

        gui.Panel{
            classes = {"builder-base", "panel-base", "detail-overview-labels"},
            nameLabel,
            kitTypeLabel,
            introLabel,
            equipmentPanel,
            bonusesPanel,
            abilityPanel,
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
        id = "kitPanel",
        classes = {"builder-base", "panel-base", "detail-panel", "kitPanel"},
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

--- CharacterKitChoice injects this into FeatureSelector. It listens
--- for the FeatureSelector's refreshBuilderState event and fires
--- a custom event back into the parent panel so we can update the
--- overview panel. We do not want to re-fire refreshBuilderState
--- because that would duplicate effort inside the child panel.
--- @return Panel
function CBKitDetail.Listener()
    return gui.Panel{
        classes = {"listener", "collapsed"},
        refreshBuilderState = function (element, state)
            local featureCache = state:Get(SELECTOR .. ".featureCache")
            local kitPanel = element:FindParentWithClass("kitPanel")
            if featureCache and kitPanel then
                local feature = featureCache:GetFeature(featureCache:GetSelectedId())
                local kitId = feature and feature:GetSelectedOptionId()
                local kitItem = dmhub.GetTableVisible(Kit.tableName)[kitId]
                local kitItem2

                -- Special case: If the hero can choose >1 kits and the kit selected
                -- is one of them, we need to send both along to updateSelectedKit
                if feature and feature:GetNumChoices() > 1 then
                    local heroSelected = feature:GetSelected() or {}
                    if heroSelected and #heroSelected > 0 then
                        local kitId2
                        local foundKit1 = false
                        for _,item in ipairs(heroSelected) do
                            if item == kitId then
                                foundKit1 = true
                            else
                                kitId2 = item
                            end
                        end
                        if foundKit1 and kitId2 ~= nil and #kitId2 > 0 then
                            kitItem2 = dmhub.GetTableVisible(Kit.tableName)[kitId2]
                        end
                    end
                end

                kitPanel:FireEventTree("updateSelectedKit", kitItem, kitItem2)
            end
        end,
    }
end