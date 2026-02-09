--[[
    Kit detail / selectors
]]
CBKitDetail = RegisterGameType("CBKitDetail")

local mod = dmhub.GetModLoading()

local SELECTOR = CharacterBuilder.SELECTOR.KIT

local _fireControllerEvent = CharacterBuilder._fireControllerEvent
local _getHero = CharacterBuilder._getHero
local _getState = CharacterBuilder._getState

function CBKitDetail._navPanel()
    return gui.Panel{
        classes = {"categoryNavPanel", "builder-base", "panel-base", "wide", "detail-nav-panel"},
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

    local function makeBonusChoicePanel(bonusItem)
        local kitKey = "kitBonusChoices"

        local choiceLabels = {}
        for i = 1, 2 do
            choiceLabels[i] = gui.Label{
                classes = {"builder-base", "label", "info", "overview", "bonus-selector"},
                textWrap = true,
                width = "auto",
                lmargin = 8,
                data = {
                    index = i,
                    kits = {},
                    bonusItemId = bonusItem.id,
                },
                assignKits = function(element, values)
                    element.data.kits = {
                        values[1] and values[1].item,
                        values[2] and values[2].item
                    }
                    element.text = values[element.data.index].text
                    element:FireEvent("refreshBuilderState", element, _getState())
                end,
                press = function(element)
                    if #element.data.kits < element.data.index then return end
                    element.parent:FireEvent("selectKit", element.data.kits[element.data.index])
                end,
                refreshBuilderState = function(element, state)
                    local hero = _getHero()
                    local kits = element.data.kits or {}
                    local selected1 = Kit.DamageBonusSelected(hero, element.data.bonusItemId, kits[1], kits[2])
                    element:SetClass("selected", (selected1 and element.data.index == 1) or (not selected1 and element.data.index == 2))
                end,
            }
        end

        return gui.Panel{
            classes = {"builder-base", "panel-base", "info", "overview", "container"},
            width = "100%",
            flow = "horizontal",
            data = {
                bonusItemId = bonusItem.id
            },
            selectKit = function(element, kit)
                local hero = _getHero()
                if hero == nil or kit == nil then return end
                local levelChoices = hero:GetLevelChoices() or {}
                local bonusChoices = levelChoices[kitKey] or {}
                bonusChoices[element.data.bonusItemId] = kit.id
                levelChoices[kitKey] = bonusChoices
                hero.levelChoices = levelChoices
                _fireControllerEvent("tokenDataChanged")
            end,
            gui.Label{
                classes = {"builder-base", "label", "info", "overview"},
                width = "auto",
                textWrap = false,
                bold = true,
                text = bonusItem.text .. ": ",
            },
            choiceLabels[1],
            choiceLabels[2],
        }
    end

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
                and ((kitItem.equipmentDescription and #kitItem.equipmentDescription > 0)
                or (kitItem2 and kitItem2.equipmentDescription and #kitItem2.equipmentDescription > 0))
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
                local text = kitItem and kitItem.equipmentDescription
                if kitItem2 and #kitItem2.equipmentDescription > 0 then
                    if #text > 0 then text = text .. "\n" end
                    text = text .. kitItem2.equipmentDescription
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
            data = {
                panels = {},
            },
            updateSelectedKit = function(element, kitItem, kitItem2)
                if kitItem == nil or kitItem2 == nil then
                    element:SetClass("collapsed", true)
                    return
                end
                local newPanels = {}
                local children = {}
                for _,bonusEntry in ipairs(Kit.damageBonusTypes) do
                    local bonusText1 = kitItem and kitItem:FormatDamageBonus(bonusEntry.id)
                    local bonusText2 = kitItem2 and kitItem2:FormatDamageBonus(bonusEntry.id)
                    if #(bonusText1 or "") > 0 and #(bonusText2 or "") > 0 then
                        newPanels[bonusEntry.id] = element.data.panels[bonusEntry.id] or makeBonusChoicePanel(bonusEntry)
                        children[#children+1] = newPanels[bonusEntry.id]
                        local kits = {
                            { item = kitItem, text = bonusText1, },
                            { item = kitItem2, text = bonusText2, },
                        }
                        newPanels[bonusEntry.id]:FireEventTree("assignKits", kits)
                    end
                end
                element.data.panels = newPanels
                element.children = children
                element:SetClass("collapsed", false)
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
        classes = {"builder-base", "panel-base", "inner-detail-panel", "xwide", "classDetailpanel"},

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
                local kitItems = {}
                kitItems[#kitItems+1] = dmhub.GetTableVisible(Kit.tableName)[kitId]

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
                            kitItems[#kitItems+1] = dmhub.GetTableVisible(Kit.tableName)[kitId2]
                        end
                    end
                end
                if #kitItems > 1 then
                    table.sort(kitItems, function(a,b) return a.name < b.name end)
                end

                kitPanel:FireEventTree("updateSelectedKit", kitItems[1], kitItems[2])
            end
        end,
    }
end