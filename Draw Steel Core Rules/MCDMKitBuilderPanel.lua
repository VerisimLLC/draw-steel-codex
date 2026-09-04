local mod = dmhub.GetModLoading()

local g_kitid = "kitid"

function CharSheet.KitChoicePanel(options)
    local resultPanel

    local leftPanel
    local rightPanel

    local kitsTable = dmhub.GetTable(Kit.tableName)

    local kitPanels = {}

    local carousel

    local GetTargetIndex = function()
        local result = 1 - round(carousel.targetPosition)
        if result < 1 then
            result = 1
        end

        if result > #kitPanels then
            result = #kitPanels
        end
        return result
    end

    local SetTargetIndex = function(index)
        carousel.targetPosition = -(index-1)
    end

    local GetCurrentIndex = function()
        local index1 = clamp(1 - math.floor(carousel.currentPosition), 1, #kitPanels)
        local index2 = clamp(1 - math.ceil(carousel.currentPosition), 1, #kitPanels)

        if index1 == index2 then
            return {
                primary = index1,
                secondary = index2,
                ratio = 0,
            }
        end

        local deadzone = 0.2
        local ratio = carousel.currentPosition - math.floor(carousel.currentPosition)
        if ratio < deadzone then
            ratio = 0
        elseif ratio > (1 - deadzone) then
            ratio = 1
        else
            ratio = (ratio - deadzone) / (1 - deadzone*2)
        end

        if ratio > 0.5 then
            ratio = 1 - ratio
            return {
                primary = index2,
                secondary = index1,
                ratio = ratio,
            }
        else
            return {
                primary = index1,
                secondary = index2,
                ratio = ratio,
            }
        end
    end

    local m_kitsAllowed = {}
    local m_kitPanelsById = {}

    local calculateKits = function()
        local creature = CharacterSheet.instance.data.info.token.properties
        local kitTypes = creature:KitTypesAllowed()
        local newKitPanels = {}
        kitPanels = {}
        m_kitsAllowed = kitTypes
        for k,kit in pairs(kitsTable) do
            if kit:try_get("hidden", false) == false and kitTypes[kit.type] then
                if m_kitPanelsById[k] then
                    newKitPanels[k] = m_kitPanelsById[k]
                else
                    local portraitPanel = gui.Panel{
                        classes = {"kitPortrait"},
                        bgimage = kit.portraitid,

                        imageLoaded = function(element)
                            if element.bgimageWidth*1.5 < element.bgimageHeight then
                                element.selfStyle.imageRect = {
                                    x1 = 0,
                                    x2 = 1,
                                    y1 = 0,
                                    y2 = (element.bgimageWidth/element.bgimageHeight)*1.5,
                                }
                            else
                                element.selfStyle.imageRect = {
                                    x1 = 0,
                                    x2 = (element.bgimageHeight/element.bgimageWidth)/1.5,
                                    y1 = 0,
                                    y2 = 1,
                                }
                            end
                        end,


                    }
                    local portraitContainer = gui.Panel{
                        classes = {"kitPortraitContainer"},
                        portraitPanel,
                    }
                    local shadow = gui.Panel{
                        classes = {"kitPortraitShadow"},
                        interactable = false,
                    }
                    newKitPanels[k] = gui.Panel{
                        data = {
                            index = 0,
                            kit = kit,
                            last_carousel = nil,
                        },
                        flow = "none",
                        carousel = function(element, f)
                            if f == element.data.last_carousel then
                                return
                            end

                            element.data.last_carousel = f

                            local x = math.abs(f)
                            element.selfStyle.scale = 1/(x*0.3+1)
                            element.selfStyle.y = x*30

                            local opacity = clamp(2.5 - x, 0, 1)

                            shadow.selfStyle.opacity = opacity
                            portraitContainer.selfStyle.opacity = opacity
                            portraitPanel.selfStyle.opacity = opacity

                        end,
                        click = function(element)
                            SetTargetIndex(element.data.index)
                            resultPanel:FireEventTree("targetIndexChanged")
                        end,
                        classes = {"kitPanel", kit.type},
                        shadow,
                        portraitContainer,
                    }
                end
                kitPanels[#kitPanels+1] = newKitPanels[k]
            end
        end

        local kitOrd = function(a)
            return tostring(Kit.kitTypeToDisplayOrd[a.data.kit.type]) .. a.data.kit.name
        end
        table.sort(kitPanels, function(a, b) return kitOrd(a) < kitOrd(b) end)
        for i,panel in ipairs(kitPanels) do
            panel.data.index = i
        end

        m_kitPanelsById = newKitPanels
        print("CalculateKits:: ", #kitPanels)
    end

    calculateKits()

    carousel = gui.Carousel{
        data = {
            last_pos = nil,
        },
		horizontalCurve = 0.2,
        verticalCurve = 0.1,
		maximumVelocity = 2,

        halign = "center",
        valign = "top",

        itemSpacing = 220,
        vmargin = 32,
        width = 800,
        height = 600,

        children = kitPanels,



         refreshBuilder = function(element)
             local creature = CharacterSheet.instance.data.info.token.properties
             local kitTypes = creature:KitTypesAllowed()
             local kitTypesChanged = false
             for k,v in pairs(kitTypes) do
                 if m_kitsAllowed[k] ~= v then
                     kitTypesChanged = true
                     break
                 end
             end
             if kitTypesChanged then
                 calculateKits()
                 element.children = kitPanels
             end

             if creature:try_get(g_kitid) ~= nil then
                element.draggable = false
                for i,panel in ipairs(kitPanels) do
                    if panel.data.kit.id == creature[g_kitid] then
                        element.currentPosition = -(i-1)
                        element.targetPosition = -(i-1)
                        panel:SetClass("hidden", false)
                    else
                        panel:SetClass("hidden", true)
                    end
                end
             else
                for i,panel in ipairs(kitPanels) do
                    panel:SetClass("hidden", false)
                end
                element.draggable = true
             end
         end,

        create = function(element)
            element.targetPosition = 0
            element:FireEvent("refreshBuilder")
        end,

        move = function(element)
            if element.currentPosition ~= element.data.last_pos then
                element.data.last_pos = element.currentPosition
                resultPanel:FireEventTree("refreshCarousel")
            end

        end,

		drag = function(element)
			element.targetPosition = round(element.currentPosition)
            resultPanel:FireEventTree("targetIndexChanged")
		end,

        styles = {
            {
                selectors = {"kitPanel"},
                width = 400,
                height = "150% width",
                halign = "center",
                valign = "center",
            },
            {
                selectors = {"kitPortraitContainer"},
                width = "100%",
                height = "100%",
                bgcolor = "black",
                borderColor = Styles.textColor,
                borderWidth = 2,
                bgimage = "panels/square.png",
            },
            {
                selectors = {"kitPortraitContainer", "parent:caster"},
                borderColor = "#aa00aa",
            },
            {
                selectors = {"kitPortraitContainer", "parent:hover", "~haskit"},
                brightness = 1.5,
            },
            {
                selectors = {"kitPortrait"},
                width = "100%-4",
                height = "100%-4",
                halign = "center",
                valign = "center",
                bgcolor = "white",
            },
            {
                selectors = {"kitPortraitShadow"},
                bgimage = "panels/square.png",
                bgcolor = "#00000099",
                width = "100%+64",
                height = "100%+64",
                halign = "center",
                valign = "center",
		        cornerRadius = 8,
                borderColor = "#00000099",
                borderWidth = 32,
                borderFade = true,
            }
        }
    }

    local selectionPanel = gui.Panel{
        width = 280,
        height = 40,
        halign = "center",
        valign = "top",
        flow = "horizontal",

        styles = {
            {
                selectors = {"paging-arrow", "haskit"},
                collapsed = 1,
            }
        },

        gui.Button{
            classes = {"pagingArrow"},
            press = function(element)
                if GetTargetIndex() > 1 then
                    SetTargetIndex(GetTargetIndex()-1)
                end
                resultPanel:FireEventTree("targetIndexChanged")
            end,

            targetIndexChanged = function(element)
                element:SetClass("hidden", GetTargetIndex() <= 1)
            end,
        },

        gui.Label{
            text = "Elf",
            halign = "center",
            valign = "center",
            fontSize = 32,
            minFontSize = 10,
            bold = false,
            width = "80%",
            height = "100%",
            textAlignment = "center",

            refreshCarousel = function(element)
                local child = element.children[1]

                local info = GetCurrentIndex()

                element.text = kitPanels[info.primary].data.kit.name
                element.selfStyle.opacity = 1 - info.ratio

                child.text = kitPanels[info.secondary].data.kit.name
                child.selfStyle.opacity = info.ratio
            end,

            gui.Label{
                fontSize = 32,
                minFontSize = 10,
                bold = false,
                width = "100%",
                height = "100%",
                textAlignment = "center",
            },
        },

        gui.Button{
            classes = {"pagingArrow", "right"},
            press = function(element)
                if GetTargetIndex() < #kitPanels then
                    SetTargetIndex(GetTargetIndex()+1)
                end
                resultPanel:FireEventTree("targetIndexChanged")
            end,
            targetIndexChanged = function(element)
                element:SetClass("hidden", GetTargetIndex() >= #kitPanels)
            end,
        },
    }

    local m_displayedIndex = nil

    local GetSelectedKit = function()
		local creature = CharacterSheet.instance.data.info.token.properties
        if creature:has_key(g_kitid) then
            return creature:Kit()
        end

        if kitPanels == nil or m_displayedIndex == nil or kitPanels[m_displayedIndex] == nil then
            return nil
        end

        local kit = kitPanels[m_displayedIndex].data.kit
        return kit
    end

    local descriptionContainer = gui.Panel{
        halign = "center",
        valign = "top",
        borderWidth = 2,
        borderColor = Styles.textColor,
        vmargin = 24,
        width = "100%",
        height = "100% available",
        bgimage = "panels/square.png",
        bgcolor = "clear",
        flow = "vertical",


        refreshCarousel = function(element, force)
            local child = element.children[1]

            local info = GetCurrentIndex()

            --we don't cross-fade, just fade-in.
            local ratio = 1 - info.ratio*2

            if m_displayedIndex == info.primary and (not force) then
                element:FireEventTree("fade", ratio)
                return
            end

            m_displayedIndex = info.primary

            local kit = GetSelectedKit()

            element:FireEventTree("refreshDescription", kit)
            element:FireEventTree("fade", ratio)

        end,

        gui.Panel{
            vscroll = true,
            height = "100%",
            width = "100%",

            styles = CharSheet.carouselDescriptionStyles,

            gui.Panel{
                width = "95%",
                height = "auto",
                halign = "center",
                flow = "vertical",
                vmargin = 32,

                gui.Label{
                    bold = false,
                    fontSize = 32,
                    valign = "top",
                    halign = "left",
                    height = 36,
                    width = "100%",
                    textAlignment = "left",
                    
                    refreshDescription = function(element, kit)
                        element.text = kit.name
                    end,

                    fade = function(element,ratio)
                        element.selfStyle.opacity = ratio
                    end,

                    gui.Button{
                        text = tr("Change Kit"),
                        halign = "right",
                        valign = "top",
                        fontSize = 14,

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            element:SetClass("collapsed", creature:try_get(g_kitid) == nil)
                        end,

                        click = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            creature[g_kitid] = nil

                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                            resultPanel:FireEventTree("refreshCarousel", true)
                        end,
                    }
                },

                gui.Label{
                    bold = false,
                    fontSize = 18,
                    valign = "top",
                    halign = "left",
                    height = 18,
                    width = "100%",
                    textAlignment = "left",
                    
                    refreshDescription = function(element, kit)
                        for _,t in ipairs(Kit.kitTypes) do
                            if t.id == kit.type then
                                element.text = string.format("%s Kit", t.text)
                                break
                            end
                        end
                    end,

                    fade = function(element,ratio)
                        element.selfStyle.opacity = ratio
                    end,
                },

                gui.Panel{
                    classes = {"separator"},
                },

                gui.Label{
                    id = "kitOverview",
                    classes = {"featureDescription"},
                    width = "100%",
                    wrap = true,
                    height = "auto",
                    refreshDescription = function(element, kit)
                        element.text = kit.description
                    end,

                    fade = function(element,ratio)
                        element.selfStyle.opacity = ratio
                    end,
                },

                gui.Panel{
                    classes = {"padding"},
                },

                gui.Label{
                    classes = {"sectionTitle"},
                    text = tr("Equipment"),
                },

                gui.Panel{
                    classes = {"separator"},
                },

                gui.Label{
                    id = "kitOverview",
                    classes = {"featureDescription"},
                    width = "100%",
                    wrap = true,
                    height = "auto",
                    refreshDescription = function(element, kit)
                        element.text = kit.equipmentDescription
                    end,

                    fade = function(element,ratio)
                        element.selfStyle.opacity = ratio
                    end,
                },

                gui.Panel{
                    classes = {"padding"},
                },

                gui.Label{
                    classes = {"sectionTitle"},
                    text = tr("Bonuses"),
                },

                gui.Panel{
                    classes = {"separator"},
                },

                gui.Label{
                    id = "traits",
                    classes = {"featureDescription"},
                    width = "100%",
                    wrap = true,
                    height = "auto",
                    bmargin = 0,

                    refreshBuilder = function(element)
                        local kit = GetSelectedKit()
                        if kit == nil then
                            return
                        end

                        element:FireEvent("refreshDescription", kit, true)
                    end,
                    refreshDescription = function(element, kit, nofire)

                        local bonuses = {}
                        if kit.health ~= 0 then
                            bonuses[#bonuses+1] = string.format("<b>%s</b> +%d per echelon", tr("Stamina Bonus:"), kit.health)
                        end

                        if kit.speed ~= 0 then
                            bonuses[#bonuses+1] = string.format("<b>%s</b> +%d", tr("Speed Bonus:"), kit.speed)
                        end

                        if kit.range ~= 0 then
                            bonuses[#bonuses+1] = string.format("<b>%s</b> +%d", tr("Distance Bonus:"), kit.range)
                        end

                        if kit.reach ~= 0 then
                            bonuses[#bonuses+1] = string.format("<b>%s</b> +%d", tr("Reach Bonus:"), kit.reach)
                        end

                        if kit.area ~= 0 then
                            bonuses[#bonuses+1] = string.format("<b>%s</b> +%d", tr("Area Bonus:"), kit.area)
                        end

                        if kit.disengage ~= 0 then
                            bonuses[#bonuses+1] = string.format("<b>%s</b> +%d", tr("Disengage Bonus:"), kit.disengage)
                        end

                        if kit.stability ~= 0 then
                            bonuses[#bonuses+1] = string.format("<b>%s</b> +%d", tr("Stability Bonus:"), kit.stability)
                        end

                        local text = table.concat(bonuses, "\n")

                        element.text = text

                    end,

                },

                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    data = {
                        panels = {},
                    },

                    styles = {
                        {
                            selectors = {"selected", "bonusLabel"},
                            color = "white",
                        },
                        {
                            selectors = {"~selected", "bonusLabel"},
                            color = "#777777",
                        },
                        {
                            selectors = {"~selected", "bonusLabel", "hover"},
                            color = "white",
                        },
                    },

                    refreshBuilder = function(element)
                        local kit = GetSelectedKit()
                        if kit == nil then
                            return
                        end

                        element:FireEvent("refreshDescription", kit, true)
                    end,
                    refreshDescription = function(element, kit, nofire)

                        local creature = CharacterSheet.instance.data.info.token.properties
                        local nkits = creature:GetNumberOfKits()
                        local bonusChoices = nil
                        local kit2 = nil
                        if nkits > 1 and creature:has_key("kitid") and creature:has_key("kitid2") then
                            --this creature has two kits.

                            local k = kitsTable[creature.kitid]
                            local k2 = kitsTable[creature.kitid2]

                            if k ~= nil and k2 ~= nil then
                                kit = k
                                kit2 = k2
                            end
                        end

                        local children = {}
                        local newPanels = {}

                        for _,bonusEntry in ipairs(Kit.damageBonusTypes) do
                            local bonusText = kit:FormatDamageBonus(bonusEntry.id)
                            local bonusText2 = nil
                            if kit2 ~= nil then
                                bonusText2 = kit2:FormatDamageBonus(bonusEntry.id)
                            end

                            if bonusText ~= nil or bonusText2 ~= nil then
                                newPanels[bonusEntry.id] = element.data.panels[bonusEntry.id] or gui.Panel{
                                    width = "100%",
                                    height = "auto",
                                    flow = "horizontal",
                                    vmargin = 0,
                                    vpad = 0,

                                    gui.Label{
                                        classes = {"featureDescription"},
                                        bold = true,
                                        textWrap = true,
                                        width = "auto",
                                        height = "auto",
                                        color = "white",
                                        vmargin = 0,
                                        text = bonusEntry.text .. ": ",
                                    },

                                    gui.Label{
                                        classes = {"featureDescription", "bonusLabel"},
                                        data = {
                                            kit = nil,
                                        },
                                        textWrap = true,
                                        width = "auto",
                                        height = "auto",
                                        vmargin = 0,
                                        lmargin = 8,

                                        press = function(element)
                                            local kit = element.data.kit

                                            local levelChoices = creature:GetLevelChoices() or {}
                                            local bonusChoices = levelChoices["kitBonusChoices"] or {}
                                            bonusChoices[bonusEntry.id] = kit.id
                                            levelChoices["kitBonusChoices"] = bonusChoices
                                            creature.levelChoices = levelChoices

                                            CharacterSheet.instance:FireEvent("refreshAll")
						                    CharacterSheet.instance:FireEventTree("refreshBuilder")
                                        end,

                                        showtext = function(element, text, selected, targetkit)
                                            element.data.kit = targetkit
                                            element:SetClass("selected", selected)
                                            if text == nil then
                                                element:SetClass("collapsed", true)
                                            else
                                                element:SetClass("collapsed", false)
                                                element.text = text
                                            end
                                        end,
                                    },

                                    gui.Label{
                                        classes = {"featureDescription", "bonusLabel"},
                                        data = {
                                            kit = nil,
                                        },
                                        textWrap = true,
                                        width = "auto",
                                        height = "auto",
                                        vmargin = 0,
                                        lmargin = 8,

                                        press = function(element)
                                            local kit = element.data.kit

                                            local levelChoices = creature:GetLevelChoices() or {}
                                            local bonusChoices = levelChoices["kitBonusChoices"] or {}
                                            bonusChoices[bonusEntry.id] = kit.id
                                            levelChoices["kitBonusChoices"] = bonusChoices
                                            creature.levelChoices = levelChoices

                                            CharacterSheet.instance:FireEvent("refreshAll")
						                    CharacterSheet.instance:FireEventTree("refreshBuilder")
                                        end,

                                        showtext2 = function(element, text, selected, targetkit)
                                            element.data.kit = targetkit
                                            element:SetClass("selected", selected)
                                            if text == nil then
                                                element:SetClass("collapsed", true)
                                            else
                                                element:SetClass("collapsed", false)
                                                element.text = text
                                            end
                                        end,
                                    },
                                }

                                local selection = true

                                if kit2 ~= nil then
                                    selection = Kit.DamageBonusSelected(creature, bonusEntry.id, kit, kit2)
                                end

                                newPanels[bonusEntry.id]:FireEventTree("showtext", bonusText, selection, kit)
                                newPanels[bonusEntry.id]:FireEventTree("showtext2", bonusText2, not selection, kit2)
                                children[#children+1] = newPanels[bonusEntry.id]
                            end
                        end

                        element.data.panels = newPanels
                        element.children = children
                    end,

                },

                gui.Panel{
                    classes = {"padding"},
                },

                gui.Label{
                    classes = {"sectionTitle"},
                    text = tr("Signature Ability"),
                },

                gui.Panel{
                    classes = {"separator"},
                },

                gui.Panel{
                    width = "100%",
                    height = "auto",
                    flow = "vertical",
                    styles = {
                        {
                            selectors = {"label"},
                            priority = 100,
                            color = Styles.textColor,
                        }
                    },

                    refreshBuilder = function(element)
                        local kit = GetSelectedKit()
                        if kit == nil then
                            return
                        end

                        element:FireEvent("refreshDescription", kit, true)
                    end,
                    refreshDescription = function(element, kit, nofire)
                        local panels = {}

                        for _,ability in ipairs(kit:SignatureAbilities()) do
                            panels[#panels+1] = ability:Render({
                                width = "100%",
                                vmargin = 6,
                            }, {
                            })
                        end

                        element.children = panels
                    end,
                },
            },
        },
    }

    leftPanel = gui.Panel{
        id = "leftPanel",
        width = "40%",
        height = "100%",
        halign = "center",
        flow = "vertical",
        
        gui.Panel{
            id = "carouselContainer",
            flow = "vertical",
            width = "100%",
            height = "auto",
            carousel,
            selectionPanel,

            styles = {
                {
                    selectors = {"#carouselContainer", "haskit"},
                    y = 132,
                    scale = 1.25,
                    transitionTime = 0.4,
                }
            },
        },
    }


    rightPanel = gui.Panel{
        width = "40%",
        height = "100%",
        halign = "center",
        flow = "vertical",

        descriptionContainer,

        gui.Button{
            text = "Select",
            halign = "center",
            fontSize = 26,
            bold = true,
            vmargin = 24,
            width = 196,
            height = 64,

			refreshBuilder = function(element)
			    local creature = CharacterSheet.instance.data.info.token.properties
                element:SetClass("collapsed", creature:try_get(g_kitid) ~= nil)
            end,

            click = function(element)
			    local creature = CharacterSheet.instance.data.info.token.properties

                local kit = kitPanels[m_displayedIndex].data.kit

                creature[g_kitid] = kit.id

				CharacterSheet.instance:FireEvent("refreshAll")
				CharacterSheet.instance:FireEventTree("refreshBuilder")
                resultPanel:FireEventTree("refreshCarousel", true)
            end,
        },
    }

    local selectionHeader = gui.Panel{
        width = "93%",
        height = "4%",
        halign = "center",

        gui.Dropdown{
            options = {
                {
                    id = "kitid",
                    text = "Kit 1",
                },
                {
                    id = "kitid2",
                    text = "Kit 2",
                },
            },
            idChosen = "kitid",
            width = 200,
            height = 26,
            change = function(element)
                g_kitid = element.idChosen
                resultPanel:FireEventTree("refreshBuilder")
            end,
        }
    }

    local horizontalPanel = gui.Panel{
        width = "93%",
        height = "93%",
        flow = "horizontal",
        halign = "center",
        valign = "center",
        leftPanel,
        rightPanel,
    }

    local args = {
		width = "100%",
		height = "100%",
		flow = "vertical",
		halign = "center",
		valign = "center",

        refreshBuilder = function(element)
            local creature = CharacterSheet.instance.data.info.token.properties

            --we only support one or two kits. This could be generalized if really needed, but not sure it will be.
            local nkits = creature:GetNumberOfKits()
            if nkits > 1 then
                selectionHeader:SetClass("collapsed", false)
            else
                selectionHeader:SetClass("collapsed", true)
                g_kitid = "kitid"
            end

            local hasKit = creature:has_key(g_kitid)
            element:SetClassTree("haskit", hasKit)
            if not hasKit then
                resultPanel:FireEvent("alert")
            end
        end,

        selectionHeader,
        horizontalPanel,
    }

    for k,v in pairs(options) do
        args[k] = v
    end

    resultPanel = gui.Panel(args)

    resultPanel:FireEventTree("targetIndexChanged")

    return resultPanel
end