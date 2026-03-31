local mod = dmhub.GetModLoading()


function CharSheet.BackgroundChoicePanel(options)
    local resultPanel

    local leftPanel
    local rightPanel

    local backgroundsTable = dmhub.GetTable(Background.tableName)

    local backgroundPanels = {}

    local carousel

    local GetTargetIndex = function()
        local result = 1 - round(carousel.targetPosition)
        if result < 1 then
            result = 1
        end

        if result > #backgroundPanels then
            result = #backgroundPanels
        end
        return result
    end

    local SetTargetIndex = function(index)
        carousel.targetPosition = -(index-1)
    end

    local GetCurrentIndex = function()
        local index1 = clamp(1 - math.floor(carousel.currentPosition), 1, #backgroundPanels)
        local index2 = clamp(1 - math.ceil(carousel.currentPosition), 1, #backgroundPanels)

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

    for k,background in pairs(backgroundsTable) do
        if background:try_get("hidden", false) == false then
            local portraitPanel = gui.Panel{
                classes = {"backgroundPortrait"},
                bgimage = background.portraitid,

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
                classes = {"backgroundPortraitContainer"},
                portraitPanel,
            }
            local shadow = gui.Panel{
                classes = {"backgroundPortraitShadow"},
                interactable = false,
            }
            backgroundPanels[#backgroundPanels+1] = gui.Panel{
                data = {
                    index = 0,
                    background = background,
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
                classes = {"backgroundPanel"},
                shadow,
                portraitContainer,
            }
        end
    end

    table.sort(backgroundPanels, function(a, b) return a.data.background.name < b.data.background.name end)
    for i,panel in ipairs(backgroundPanels) do
        panel.data.index = i
    end

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

        children = backgroundPanels,



         refreshBuilder = function(element)
             local creature = CharacterSheet.instance.data.info.token.properties
             if creature:try_get("backgroundid") ~= nil then
                element.draggable = false
                for i,panel in ipairs(backgroundPanels) do
                    if panel.data.background.id == creature.backgroundid then
                        element.currentPosition = -(i-1)
                        element.targetPosition = -(i-1)
                        panel:SetClass("hidden", false)
                    else
                        panel:SetClass("hidden", true)
                    end
                end
             else
                for i,panel in ipairs(backgroundPanels) do
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
                selectors = {"backgroundPanel"},
                width = 400,
                height = "150% width",
                halign = "center",
                valign = "center",
            },
            {
                selectors = {"backgroundPortraitContainer"},
                width = "100%",
                height = "100%",
                bgcolor = "black",
                borderColor = Styles.textColor,
                borderWidth = 2,
                bgimage = "panels/square.png",
            },
            {
                selectors = {"backgroundPortraitContainer", "parent:hover", "~hasbackground"},
                brightness = 1.5,
            },
            {
                selectors = {"backgroundPortrait"},
                width = "100%-4",
                height = "100%-4",
                halign = "center",
                valign = "center",
                bgcolor = "white",
            },
            {
                selectors = {"backgroundPortraitShadow"},
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
                selectors = {"paging-arrow", "hasbackground"},
                collapsed = 1,
            }
        },

        gui.PagingArrow{
            facing = -1,
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

                element.text = backgroundPanels[info.primary].data.background.name
                element.selfStyle.opacity = 1 - info.ratio

                child.text = backgroundPanels[info.secondary].data.background.name
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

        gui.PagingArrow{
            facing = 1,
            press = function(element)
                if GetTargetIndex() < #backgroundPanels then
                    SetTargetIndex(GetTargetIndex()+1)
                end
                resultPanel:FireEventTree("targetIndexChanged")
            end,
            targetIndexChanged = function(element)
                element:SetClass("hidden", GetTargetIndex() >= #backgroundPanels)
            end,
        },
    }

    local displayedIndex = nil

    local GetSelectedBackground = function()
		local creature = CharacterSheet.instance.data.info.token.properties
        if creature:has_key("backgroundid") then
            return creature:Background()
        end

        if backgroundPanels == nil or displayedIndex == nil or backgroundPanels[displayedIndex] == nil then
            return nil
        end

        local background = backgroundPanels[displayedIndex].data.background
        return background
    end

    --starting equipment panel
    local startingEquipmentPanel
    local startingEquipmentDisplay = CharSheet.StartingEquipmentDisplay("claimedBackground", "hasbackground")
    local claimEquipmentButton = gui.Button{
        text = "Claim Equipment",
        fontSize = 22,
        halign = "center",

        click = function(element)
            local creature = CharacterSheet.instance.data.info.token.properties
            startingEquipmentPanel:FireEventTree("claimEquipment", creature)

            local creatureEquipmentChoices = creature:try_get("equipmentChoices", {})
            creatureEquipmentChoices.claimedBackground = true
            creature.equipmentChoices = creatureEquipmentChoices

            CharacterSheet.instance:FireEvent("refreshAll")
            CharacterSheet.instance:FireEventTree("refreshBuilder")
        end,
    }

    local equipmentClaimedLabel = gui.Label{
        text = "Your starting equipment was added to your inventory.",
        width = "auto",
        height = "auto",
        halign = "center",
        valign = "center",
        fontSize = 16,
    }

    startingEquipmentPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        gui.Panel{
            classes = {"collapsibleHeading"},
            click = function(element)
                element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                element:FireEvent("refreshBuilder")
            end,
            refreshBuilder = function(element)
                local creature = CharacterSheet.instance.data.info.token.properties
                local method = creature:try_get("equipmentMethod", "equipment")
                element:Get("startingEquipment"):SetClass("collapsed", element:HasClass("collapseSet"))
                element:SetClass("collapsed", method ~= "equipment")
            end,
            gui.Label{
                classes = {"sectionTitle"},
                text = tr("Starting Equipment"),
            },
            gui.CollapseArrow{
                halign = "right",
                valign = "center",
            },
        },

        gui.Panel{
            classes = {"separator"},
        },

        gui.Panel{
            id = "startingEquipment",
            width = "100%",
            height = "auto",
            flow = "vertical",

            data = {
            },

            startingEquipmentDisplay,
            gui.Panel{
                flow = "none",
                width = "100%",
                height = 46,
                claimEquipmentButton,
                equipmentClaimedLabel,
                refreshDescription = function(element, class)
                    local creature = CharacterSheet.instance.data.info.token.properties
                    local hasBackground = creature:has_key("backgroundid")
                    element:SetClass("collapsed", not hasBackground)
                    if hasBackground then
                        local info = {}
                        startingEquipmentDisplay:FireEventTree("collectStartingEquipment", info)
                        if #info.equipment == 0 then
                            element:SetClass("collapsed", true)
                            return
                        end

                        if info.pending then
                            element:SetClass("hidden", true)
                            return
                        end

                        element:SetClass("hidden", false)


                        local creatureEquipmentChoices = creature:try_get("equipmentChoices", {})
                        if creatureEquipmentChoices.claimedBackground then
                            claimEquipmentButton:SetClass("hidden", true)
                            equipmentClaimedLabel:SetClass("hidden", false)
                        else
                            claimEquipmentButton:SetClass("hidden", false)
                            equipmentClaimedLabel:SetClass("hidden", true)
                        end
                    end
                end,
            },

            refreshDescription = function(element, background)
                if background == nil then
                    return
                end

                local creature = CharacterSheet.instance.data.info.token.properties
                element:FireEventTree("refreshStartingEquipment", creature, background)
            end,


            refreshBuilder = function(element)
                local background = GetSelectedBackground()
                if background == nil then
                    return
                end
                local creature = CharacterSheet.instance.data.info.token.properties
                if creature:try_get("equipmentMethod", "equipment") == "gold" then
                    return
                end

                element:FireEventTree("refreshDescription", background, true)
            end,

        },

        gui.Panel{
            classes = {"padding"},
        },
    }
    --end starting equipment panel

    local characteristicsPanel = CharSheet.BackgroundCharacteristicPanel{
        GetSelectedBackground = GetSelectedBackground,
        selectedStyle = "hasbackground",
    }

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


        refreshCarousel = function(element)
            local child = element.children[1]

            local info = GetCurrentIndex()

            --we don't cross-fade, just fade-in.
            local ratio = 1 - info.ratio*2

            if displayedIndex == info.primary then
                element:FireEventTree("fade", ratio)
                return
            end

            displayedIndex = info.primary

            local background = GetSelectedBackground()

            element:FireEventTree("refreshDescription", background)
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
                    
                    refreshDescription = function(element, background)
                        element.text = background.name
                    end,

                    fade = function(element,ratio)
                        element.selfStyle.opacity = ratio
                    end,

                    gui.Button{
                        text = string.format("Change %s", GameSystem.BackgroundName),
                        halign = "right",
                        valign = "top",
                        fontSize = 14,

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            element:SetClass("collapsed", creature:try_get("backgroundid") == nil)
                        end,

                        click = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            creature.backgroundid = nil

                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,
                    }
                },

                gui.Panel{
                    classes = {"separator"},
                },

                gui.Panel{
                    classes = {"padding"},
                },

                gui.Panel{
                    classes = {"collapsibleHeading"},
                    click = function(element)
                        element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                        element:Get("backgroundOverview"):SetClass("collapsed", element:HasClass("collapseSet"))
                    end,
                    gui.Label{
                        classes = {"sectionTitle"},
                        text = tr("Overview"),
                    },
                    gui.CollapseArrow{
                        halign = "right",
                        valign = "center",
                    },
                },

                gui.Panel{
                    classes = {"separator"},
                },

                gui.Label{
                    id = "backgroundOverview",
                    classes = {"featureDescription"},
                    width = "100%",
                    wrap = true,
                    height = "auto",
                    refreshDescription = function(element, background)
                        element.text = background.description
                    end,

                    fade = function(element,ratio)
                        element.selfStyle.opacity = ratio
                    end,
                },

                gui.Panel{
                    classes = {"padding"},
                },

                startingEquipmentPanel,

                characteristicsPanel,

                gui.Panel{
                    classes = {"collapsibleHeading"},
                    click = function(element)
                        element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                        element:Get("traits"):SetClass("collapsed", element:HasClass("collapseSet"))
                    end,
                    gui.Label{
                        classes = {"sectionTitle"},
                        text = tr("Traits"),
                    },
                    gui.CollapseArrow{
                        halign = "right",
                        valign = "center",
                    },
                },

                gui.Panel{
                    classes = {"separator"},
                },

                gui.Panel{
                    id = "traits",
                    width = "100%",
                    height = "auto",
                    flow = "vertical",

                    --background
                    CharSheet.FeatureDetailsPanel{
                        alert = function(element)
                            resultPanel:FireEvent("alert")
                        end,
                    },

                    data = {
                        featurePanels = {},
                        featureDetailsPanels = nil,
                    },

                    refreshBuilder = function(element)
                        local background = GetSelectedBackground()
                        if background == nil then
                            return
                        end

                        element:FireEvent("refreshDescription", background, true)
                    end,
                    refreshDescription = function(element, background, nofire)
                        if element.data.featureDetailsPanels == nil then
                            element.data.featureDetailsPanels = element.children
                        end

                        local detailsPanels = element.data.featureDetailsPanels

                        local textItems = {
                        }

                        if not element:HasClass("hasbackground") then


                            for i,p in ipairs(detailsPanels) do
                                p.data.hide = true
                            end

                            local featureDetails = {}
                            background:FillFeatureDetails({}, featureDetails)

                            for _,f in ipairs(featureDetails) do
                                local text = f.feature:GetSummaryText()
                                if text ~= nil then
                                    textItems[#textItems+1] = text
                                end
                            end

                        else
                            detailsPanels[1].data.hide = false

                            detailsPanels[1].data.criteria = { background = background }
                        end


                        local featurePanels = element.data.featurePanels

                        for i,text in ipairs(textItems) do
                            featurePanels[i] = featurePanels[i] or gui.Label{
                                classes = {"featureDescription"},
                            }

                            featurePanels[i].text = text
                        end

                        for i,p in ipairs(featurePanels) do
                            p:SetClass("collapsed", i > #textItems)
                        end



                        local children = {}
                        for i,p in ipairs(featurePanels) do
                            children[#children+1] = p
                        end

                        for i,p in ipairs(detailsPanels) do
                            children[#children+1] = p
                        end

                        element.children = children

                        if not nofire then
                            for i,p in ipairs(detailsPanels) do
                                p:FireEventTree("refreshBuilder")
                            end
                        end

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
                    selectors = {"#carouselContainer", "hasbackground"},
                    y = 132,
                    scale = 1.4,
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
                element:SetClass("collapsed", creature:try_get("backgroundid") ~= nil)
            end,

            click = function(element)
			    local creature = CharacterSheet.instance.data.info.token.properties

                local background = GetSelectedBackground()

                creature.backgroundid = background.id

				CharacterSheet.instance:FireEvent("refreshAll")
				CharacterSheet.instance:FireEventTree("refreshBuilder")
            end,
        },
    }

    local args = {
		width = "100%",
		height = "100%",
		flow = "horizontal",
		halign = "center",
		valign = "center",

        refreshBuilder = function(element)
            local creature = CharacterSheet.instance.data.info.token.properties
            local hasBackground = creature:has_key("backgroundid")
            element:SetClassTree("hasbackground", hasBackground)
            if not hasBackground then
                resultPanel:FireEvent("alert")
            end
        end,

        leftPanel,
        rightPanel,
    }

    for k,v in pairs(options) do
        args[k] = v
    end

    resultPanel = gui.Panel(args)

    resultPanel:FireEventTree("targetIndexChanged")

    return resultPanel
end

function CharSheet.BackgroundCharacteristicPanel(options)

    local selectedStyle = options.selectedStyle or "always"
    local notSelected = "~" .. selectedStyle

    local individualCharacteristicsPanels = {}
    return gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        styles = {
            {
                selectors = {"row"},
                height = "auto",
                width = "100%",
                bgimage = "panels/square.png",
                bgcolor = "black",
                flow = "horizontal",
            },
            {
                selectors = {"row", "oddRow", "~selected", "~hover"},
                opacity = 0.8,
            },
            {
                selectors = {"row", "evenRow", "~selected", "~hover"},
                opacity = 0.4,
            },
            {
                selectors = {"row", "oddRow", "~selected", notSelected},
                opacity = 0.8,
            },
            {
                selectors = {"row", "evenRow", "~selected", notSelected},
                opacity = 0.4,
            },
            {
                selectors = {"row", "hover", selectedStyle},
                bgcolor = Styles.textColor,
                brightness = 0.5,
            },
            {
                selectors = {"row", "selected", selectedStyle},
                bgcolor = Styles.textColor,
            },
            {
                selectors = {"row", "selected", "hover", selectedStyle},
                brightness = 1.2,
            },
            {
                selectors = {"row", "preview", selectedStyle},
                bgcolor = Styles.textColor,
            },
            {
                selectors = {"row", "press", selectedStyle},
                brightness = 0.4,
            },
            {
                selectors = {"rollLabel"},
                width = 40,
                height = "auto",
                textAlignment = "center",
                valign = "center",
                bold = true,
            },
            {
                selectors = {"outcomeLabel"},
                width = 660,
                height = "auto",
                brightness = 0.8,
                halign = "right",
                valign = "center",
                textAlignment = "left",
                hmargin = 8,
            },
            {
                selectors = {"outcomeLabel", "parent:selected", selectedStyle},
                color = "black",
            },
            {
                selectors = {"rollLabel", "parent:selected", selectedStyle},
                color = "black",
            },
            {
                selectors = {"outcomeLabel", "parent:hover", selectedStyle},
                color = "black",
            },
            {
                selectors = {"rollLabel", "parent:hover", selectedStyle},
                color = "black",
            },
            {
                selectors = {"outcomeLabel", "parent:preview", selectedStyle},
                color = "black",
            },
            {
                selectors = {"rollLabel", "parent:preview", selectedStyle},
                color = "black",
            },
            {
                selectors = {"dice", notSelected},
                collapsed = 1,
            },
        },

        refreshDescription = function(element, background)
            if background == nil then
                return
            end

            --ensure all elements get the memo about this being selected.
            if selectedStyle ~= "always" then
                element:SetClassTree(selectedStyle, element:HasClass(selectedStyle))
            end

            local newCharacteristicsPanels = {}

		    for i,characteristic in ipairs(background:try_get("characteristics", {})) do
                newCharacteristicsPanels[i] = individualCharacteristicsPanels[i]

                if newCharacteristicsPanels[i] == nil then

                    local currentRows = {}

                    local m_characteristic = nil

                    local characteristicsContent
                    characteristicsContent = gui.Panel{
                        width = "100%",
                        height = "auto",
                        flow = "vertical",

                        gui.Label{
                            classes = {"featureDescription"},
                            background = function(element, background, characteristic)
                                element.text = characteristic:GetRulesText()
                            end,
                        },

                        gui.Table{
                            width = "100%",
                            height = "auto",

                            beginRoll = function(element, rollInfo)

								for i,roll in ipairs(rollInfo.rolls) do
                                    local events = chat.DiceEvents(roll.guid)
                                    if events ~= nil then
                                        events:Listen(element)
                                    end
                                end
                            end,

                            completeRoll = function(element, rollInfo)
                                element:SetClassTree("preview", false)
                            end,

							diceface = function(element, diceguid, num)
                                local rowIndex = m_characteristic:GetRollTable():RowIndexFromDiceResult(num) 
                                element:FireEventTree("preview", rowIndex)
                            end,

                            background = function(element, background, characteristic)
                                m_characteristic = characteristic

                                local rollTable = characteristic:GetRollTable()
                                local rollInfo = rollTable:CalculateRollInfo()
                                if #rollTable.rows ~= #currentRows then
                                    local newRows = {}
                                    for i,row in ipairs(rollTable.rows) do
                                        local m_currentRow = nil
                                        local rowPanel = currentRows[i] or gui.TableRow{
                                            gui.Label{
                                                classes = {"featureDescription", "rollLabel"},
                                                row = function(element, row, range, note)
                                                    if range == nil or range.min == nil then
                                                        element.text = "--"
                                                    elseif range.min == range.max then
                                                        element.text = tostring(round(range.min))
                                                    else
                                                        element.text = string.format("%d%s%d", round(range.min), Styles.emdash, round(range.max))
                                                    end
                                                end,
                                            },
                                            gui.Label{
                                                data = {
                                                    note = nil
                                                },
                                                classes = {"featureDescription", "outcomeLabel"},
                                                row = function(element, row, range, note)
                                                    element.data.note = note

                                                    if note ~= nil and note.text ~= nil then
                                                        --user has overridden the text.
                                                        element.text = note.text
                                                    else
                                                        element.text = row.value:ToString()
                                                    end
                                                end,

                                                change = function(element)
                                                    if element.data.note ~= nil then
                                                        element.data.note.text = element.text
                                                    end
                                                end,
                                            },

                                            preview = function(element, index)
                                                element:SetClass("preview", index == i)
                                            end,

                                            row = function(element, row, range, note)
                                                element:SetClass("selected", note ~= nil)
                                                m_currentRow = row
                                            end,

                                            click = function(element)
                                                if not element:HasClass(selectedStyle) then
                                                    return
                                                end

                                                local creature = CharacterSheet.instance.data.info.token.properties
                                                local note = creature:GetOrAddNoteForTableRow(m_characteristic.tableid, m_currentRow.id)

                                                if note.title == "" then
                                                    note.title = m_characteristic:Name()
                                                end

                                                if note.text == "" then
                                                    note.text = m_currentRow.value:ToString()
                                                end

                                                CharacterSheet.instance:FireEvent("refreshAll")
                                                CharacterSheet.instance:FireEventTree("refreshBuilder")
                                            end,

                                            rightClick = function(element)
                                                if not element:HasClass(selectedStyle) then
                                                    return
                                                end

                                                local entries = {}

                                                if element:HasClass("selected") then
                                                    entries[#entries+1] =
                                                    {
                                                        text = "Customize Text...",
                                                        click = function()
                                                            element.popup = nil
                                                            element.children[2]:BeginEditing()
                                                        end,
                                                    }
                                                end


                                                entries[#entries+1] =
                                                {
                                                    text = cond(element:HasClass("selected"), "Remove Characteristic", "Add Characteristic"),
                                                    click = function()
                                                        local creature = CharacterSheet.instance.data.info.token.properties

                                                        if element:HasClass("selected") then
                                                            creature:RemoveNoteForTableRow(m_characteristic.tableid, m_currentRow.id)
                                                        else
                                                            local note = creature:GetOrAddNoteForTableRow(m_characteristic.tableid, m_currentRow.id)
                                                            if note.title ~= "" then
                                                                note.title = m_characteristic:Name()
                                                            end

                                                            if note.text ~= "" then
                                                                note.text = m_currentRow.value:ToString()
                                                            end
                                                        end

                                                        CharacterSheet.instance:FireEvent("refreshAll")
                                                        CharacterSheet.instance:FireEventTree("refreshBuilder")

                                                        element.popup = nil
                                                    end,
                                                }

                                                element.popup = gui.ContextMenu{
                                                    entries = entries,
                                                }
                                            end,
                                        }

                                        newRows[i] = rowPanel
                                    end

                                    currentRows = newRows
                                    element.children = newRows
                                end


                                local creature = CharacterSheet.instance.data.info.token.properties

                                --iterate over the table and update the rows, including providing the ranges needed for each outcome.
                                for i,row in ipairs(rollTable.rows) do
                                    currentRows[i]:FireEventTree("row", row, rollInfo.rollRanges[i], creature:GetNoteForTableRow(m_characteristic.tableid, row.id))
                                end
                            end,
                        },


						gui.UserDice{
                            halign = "center",
                            valign = "center",
                            vmargin = 5,
                            width = 48,
                            height = 48,
                            faces = 20,
							click = function(element)
                                local creature = CharacterSheet.instance.data.info.token.properties
                                local rollTable = m_characteristic:GetRollTable()
                                local rollInfo = rollTable:CalculateRollInfo()

								element:SetClass("hidden", true)
								dmhub.Roll{
									roll = rollInfo.roll,
									description = string.format("Characteristic"),
									tokenid = dmhub.LookupTokenId(creature),

                                    begin = function(rollInfo)
                                        characteristicsContent:FireEventTree("beginRoll", rollInfo)
                                    end,

									complete = function(rollInfo)
                                        characteristicsContent:FireEventTree("completeRoll", rollInfo)

                                        local creature = CharacterSheet.instance.data.info.token.properties

                                        local rowIndex = rollTable:RowIndexFromDiceResult(rollInfo.total)
                                        if rowIndex == nil then
                                            return
                                        end

                                        local row = rollTable.rows[rowIndex]

                                        local note = creature:GetOrAddNoteForTableRow(m_characteristic.tableid, row.id)

                                        if note.title == "" then
                                            note.title = m_characteristic:Name()
                                        end

                                        if note.text == "" then
                                            note.text = row.value:ToString()
                                        end

                                        element:SetClass("hidden", false)

										CharacterSheet.instance:FireEvent("refreshAll")
										CharacterSheet.instance:FireEventTree("refreshBuilder")
									end,
								}
							end,
						},

                    }

                    newCharacteristicsPanels[i] = gui.Panel{

                        width = "100%",
                        height = "auto",
                        flow = "vertical",

                        gui.Panel{
                            classes = {"collapsibleHeading"},
                            click = function(element)
                                element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                                characteristicsContent:SetClass("collapsed", element:HasClass("collapseSet"))
                            end,
                            gui.Label{
                                classes = {"sectionTitle"},
                                text = tr(""),
                                background = function(element, background, characteristic)
                                    element.text = characteristic:Name()
                                end,
                            },
                            gui.CollapseArrow{
                                halign = "right",
                                valign = "center",
                            },
                        },

                        gui.Panel{
                            classes = {"separator"},
                        },


                        characteristicsContent,

                        gui.Panel{
                            classes = {"padding"},
                        },
                    }
                end

                newCharacteristicsPanels[i]:FireEventTree("background", background, background.characteristics[i])
            end

            element.children = newCharacteristicsPanels
            individualCharacteristicsPanels = newCharacteristicsPanels
        end,
 
        refreshBuilder = function(element)
            local background = options.GetSelectedBackground()
            if background == nil then
                return
            end
            local creature = CharacterSheet.instance.data.info.token.properties

            element:FireEventTree("refreshDescription", background, true)
        end,       
    }
end