local mod = dmhub.GetModLoading()

function CharSheet.BackgroundChoicePanel(options)
    local resultPanel

    local leftPanel
    local rightPanel

    local careersTable = dmhub.GetTable(Background.tableName)

    local m_careerHovered = nil

    local GetSelectedBackground = function()
		local creature = CharacterSheet.instance.data.info.token.properties
        if creature:has_key("backgroundid") then
            return creature:Background()
        end

        return careersTable[m_careerHovered]
    end

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

                refreshBuilder = function(element)
                    element:SetClass("collapsed", GetSelectedBackground() == nil)
                end,

                gui.Label{
                    bold = false,
                    fontSize = 32,
                    valign = "top",
                    halign = "left",
                    height = 36,
                    width = "100%",
                    textAlignment = "left",
                    
                    refreshBuilder = function(element)
                        local career = GetSelectedBackground()
                        if career ~= nil then
                            element.text = career.name
                        end
                    end,

                    gui.Button{
                        text = string.format("Clear %s", GameSystem.BackgroundName),
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
                    refreshBuilder = function(element)
                        local career = GetSelectedBackground()
                        if career ~= nil then
                            element.text = career.description
                        end
                    end,
                },

                gui.Panel{
                    classes = {"padding"},
                },


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
        width = "50%",
        height = "100%",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        styles = {
            {
                classes = {"careerPanel"},
                bgcolor = "clear",
                borderWidth = 2,
                borderColor = Styles.textColor,
            },
            {
                classes = {"haveselection", "selected"},
                brightness = 1.8,
            },
            {
                classes = {"haveselection", "~selected"},
                brightness = 0.5,
            },
            {
                selectors = {"careerPanel", "hover"},
                borderWidth = 4,
                bgcolor = "#ffffff22",
            },
            {
                selectors = {"careerLabel", "parent:haveselection", "~parent:selected"},
                opacity = 0.4,
            },
            {
                selectors = {"careerIcon"},
                saturation = 0.8,
            },
            {
                selectors = {"careerIcon", "parent:hover"},
                saturation = 1.0,
            },
        },

        create = function(element)

            local colors = { "#ff0000", "#00ff00", "#0000ff", "#ffff00", "#ff00ff", "#00ffff", "#ff7f00", "#7f00ff", "#00ff7f", "#7fff00", "#ff007f", "#007fff", "#7f7f00", "#7f007f", "#007f7f", "#ff3f3f", "#3fff3f", "#3f3fff", }
            local colorsIndex = 0

            local careerPanels = {}

            for k,career in pairs(careersTable) do
                if not career:try_get("hidden") then
                    colorsIndex = colorsIndex + 1
                    if colorsIndex > #colors then
                        colorsIndex = 1
                    end

                    local iconColor = colors[colorsIndex]

                    local careerPanel = gui.Panel{
                        data = {
                            ord = career.name,
                        },
                        classes = {"careerPanel"},
                        flow = "horizontal",
                        width = "28%",
                        hmargin = 20,
                        vmargin = 30,
                        height = 80,
                        halign = "left",
                        valign = "center",
                        bgimage = "panels/square.png",

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            local haveBackground = creature:has_key("backgroundid")
                            element:SetClass("haveselection", haveBackground)
                            if haveBackground then
                                element:SetClass("selected", creature.backgroundid == k)
                            end
                        end,

                        hover = function(element)
                            m_careerHovered = k
                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,

                        dehover = function(element)
                            if m_careerHovered == k then
                                m_careerHovered = nil
                            end
                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,

                        press = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties

                            if creature:try_get("backgroundid") == k then
                                creature.backgroundid = nil
                            else
                                creature.backgroundid = k
                            end

                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,

                        gui.Panel{
                            classes = {"careerIcon"},
                            interactable = false,
                            width = 64,
                            height = 64,
                            valign = "center",
                            hmargin = 8,
                            bgimage = "panels/square.png",
                            bgcolor = iconColor,
                        },
                        gui.Label{
                            classes = {"careerLabel"},
                            interactable = false,
                            text = career.name,
                            fontSize = 24,
                            minFontSize = 8,
                            color = Styles.textColor,
                            maxWidth = 180,
                            textWrap = false,
                            width = "auto",
                            height = "auto",
                            halign = "left",
                        }
                    }

                    careerPanels[#careerPanels+1] = careerPanel
                end
            end

            table.sort(careerPanels, function(a,b) return a.data.ord < b.data.ord end)

            leftPanel.children = careerPanels

            element:FireEventTree("refreshBuilder")
        end,
    }

    rightPanel = gui.Panel{
        width = "40%",
        height = "100%",
        halign = "center",
        flow = "vertical",

        descriptionContainer,
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

                    ---@type BackgroundCharacteristic
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
                                        ---@type RollTableRow
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
                                                markdown = true,
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

                                                if element:HasClass("selected") then
                                                    element:FireEvent("remove")
                                                else
                                                    element:FireEvent("select")
                                                end

                                                CharacterSheet.instance:FireEvent("refreshAll")
                                                CharacterSheet.instance:FireEventTree("refreshBuilder")
                                            end,

                                            select = function(element)
                                                local creature = CharacterSheet.instance.data.info.token.properties
                                                characteristicsContent:FireEventTree("remove")

                                                local note = creature:GetOrAddNoteForTableRow(m_characteristic.tableid, m_currentRow.id)
                                                note.title = m_characteristic:Name()
                                                note.text = m_currentRow.value:ToString()
                                            end,

                                            remove = function(element)
                                                if element:HasClass("selected") then
                                                    local creature = CharacterSheet.instance.data.info.token.properties
                                                    creature:RemoveNoteForTableRow(m_characteristic.tableid, m_currentRow.id)
                                                end
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
                                                            --the row's second child is the outcome gui.Label.
                                                            local outcomeLabel = element.children[2] --[[@as Label]]
                                                            outcomeLabel:BeginEditing()
                                                        end,
                                                    }
                                                end


                                                entries[#entries+1] =
                                                {
                                                    text = cond(element:HasClass("selected"), "Remove", "Add"),
                                                    click = function()
                                                        local creature = CharacterSheet.instance.data.info.token.properties

                                                        if element:HasClass("selected") then
                                                            element:FireEvent("remove")
                                                        else
                                                            element:FireEvent("select")

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
                                        characteristicsContent:FireEventTree("remove")
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

            element:FireEventTree("refreshDescription", background, true)
        end,       
    }
end
local mod = dmhub.GetModLoading()

function CharSheet.BackgroundChoicePanel(options)
    local resultPanel

    local leftPanel
    local rightPanel

    local careersTable = dmhub.GetTable(Background.tableName)

    local m_careerHovered = nil

    local GetSelectedBackground = function()
		local creature = CharacterSheet.instance.data.info.token.properties
        if creature:has_key("backgroundid") then
            return creature:Background()
        end

        return careersTable[m_careerHovered]
    end

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

                refreshBuilder = function(element)
                    element:SetClass("collapsed", GetSelectedBackground() == nil)
                end,

                gui.Label{
                    bold = false,
                    fontSize = 32,
                    valign = "top",
                    halign = "left",
                    height = 36,
                    width = "100%",
                    textAlignment = "left",
                    
                    refreshBuilder = function(element)
                        local career = GetSelectedBackground()
                        if career ~= nil then
                            element.text = career.name
                        end
                    end,

                    gui.Button{
                        text = string.format("Clear %s", GameSystem.BackgroundName),
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
                    refreshBuilder = function(element)
                        local career = GetSelectedBackground()
                        if career ~= nil then
                            element.text = career.description
                        end
                    end,
                },

                gui.Panel{
                    classes = {"padding"},
                },


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

                        children[#children+1] = gui.Label{

                            classes = {"sheetLabel", "featureDescription"},



                            text = string.format("<b>Project points: </b>" .. background.projectpoints),


                        }

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
        width = "50%",
        height = "100%",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        styles = {
            {
                classes = {"careerPanel"},
                bgcolor = "clear",
                borderWidth = 2,
                borderColor = Styles.textColor,
            },
            {
                classes = {"haveselection", "selected"},
                brightness = 1.8,
            },
            {
                classes = {"haveselection", "~selected"},
                brightness = 0.5,
            },
            {
                selectors = {"careerPanel", "hover"},
                borderWidth = 4,
                bgcolor = "#ffffff22",
            },
            {
                selectors = {"careerLabel", "parent:haveselection", "~parent:selected"},
                opacity = 0.4,
            },
            {
                selectors = {"careerIcon"},
                saturation = 0.8,
            },
            {
                selectors = {"careerIcon", "parent:hover"},
                saturation = 1.0,
            },
        },

        create = function(element)

            local colors = { "#ff0000", "#00ff00", "#0000ff", "#ffff00", "#ff00ff", "#00ffff", "#ff7f00", "#7f00ff", "#00ff7f", "#7fff00", "#ff007f", "#007fff", "#7f7f00", "#7f007f", "#007f7f", "#ff3f3f", "#3fff3f", "#3f3fff", }
            local colorsIndex = 0

            local careerPanels = {}

            for k,career in pairs(careersTable) do
                if not career:try_get("hidden") then
                    colorsIndex = colorsIndex + 1
                    if colorsIndex > #colors then
                        colorsIndex = 1
                    end

                    local iconColor = colors[colorsIndex]

                    local careerPanel = gui.Panel{
                        data = {
                            ord = career.name,
                        },
                        classes = {"careerPanel"},
                        flow = "horizontal",
                        width = "28%",
                        hmargin = 20,
                        vmargin = 30,
                        height = 80,
                        halign = "left",
                        valign = "center",
                        bgimage = "panels/square.png",

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            local haveBackground = creature:has_key("backgroundid")
                            element:SetClass("haveselection", haveBackground)
                            if haveBackground then
                                element:SetClass("selected", creature.backgroundid == k)
                            end
                        end,

                        hover = function(element)
                            m_careerHovered = k
                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,

                        dehover = function(element)
                            if m_careerHovered == k then
                                m_careerHovered = nil
                            end
                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,

                        press = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties

                            if creature:try_get("backgroundid") == k then
                                creature.backgroundid = nil
                            else
                                creature.backgroundid = k
                            end

                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,

                        gui.Panel{
                            classes = {"careerIcon"},
                            interactable = false,
                            width = 64,
                            height = 64,
                            valign = "center",
                            hmargin = 8,
                            bgimage = "panels/square.png",
                            bgcolor = iconColor,
                        },
                        gui.Label{
                            classes = {"careerLabel"},
                            interactable = false,
                            text = career.name,
                            fontSize = 24,
                            minFontSize = 8,
                            color = Styles.textColor,
                            maxWidth = 180,
                            textWrap = false,
                            width = "auto",
                            height = "auto",
                            halign = "left",
                        }
                    }

                    careerPanels[#careerPanels+1] = careerPanel
                end
            end

            table.sort(careerPanels, function(a,b) return a.data.ord < b.data.ord end)

            leftPanel.children = careerPanels

            element:FireEventTree("refreshBuilder")
        end,
    }

    rightPanel = gui.Panel{
        width = "40%",
        height = "100%",
        halign = "center",
        flow = "vertical",

        descriptionContainer,
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

                    ---@type BackgroundCharacteristic
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
                                        ---@type RollTableRow
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
                                                markdown = true,
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

                                                if element:HasClass("selected") then
                                                    element:FireEvent("remove")
                                                else
                                                    element:FireEvent("select")
                                                end

                                                CharacterSheet.instance:FireEvent("refreshAll")
                                                CharacterSheet.instance:FireEventTree("refreshBuilder")
                                            end,

                                            select = function(element)
                                                local creature = CharacterSheet.instance.data.info.token.properties
                                                characteristicsContent:FireEventTree("remove")

                                                local note = creature:GetOrAddNoteForTableRow(m_characteristic.tableid, m_currentRow.id)
                                                note.title = m_characteristic:Name()
                                                note.text = m_currentRow.value:ToString()
                                            end,

                                            remove = function(element)
                                                if element:HasClass("selected") then
                                                    local creature = CharacterSheet.instance.data.info.token.properties
                                                    creature:RemoveNoteForTableRow(m_characteristic.tableid, m_currentRow.id)
                                                end
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
                                                            --the row's second child is the outcome gui.Label.
                                                            local outcomeLabel = element.children[2] --[[@as Label]]
                                                            outcomeLabel:BeginEditing()
                                                        end,
                                                    }
                                                end


                                                entries[#entries+1] =
                                                {
                                                    text = cond(element:HasClass("selected"), "Remove", "Add"),
                                                    click = function()
                                                        local creature = CharacterSheet.instance.data.info.token.properties

                                                        if element:HasClass("selected") then
                                                            element:FireEvent("remove")
                                                        else
                                                            element:FireEvent("select")

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
                                        characteristicsContent:FireEventTree("remove")
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

            element:FireEventTree("refreshDescription", background, true)
        end,       
    }
end