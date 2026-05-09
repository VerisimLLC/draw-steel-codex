local mod = dmhub.GetModLoading()

CharSheet.carouselDescriptionStyles = {
    {
        selectors = {"separator"},
        bgimage = "panels/square.png",
        bgcolor = Styles.textColor,
        height = 2,
        width = "100%",
        halign = "center",
        valign = "top",
        vmargin = 8,
    },
    {
        selectors = {"padding"},
        width = 2,
        height = 20,
    },
    {
        selectors = {"sectionTitle"},
        fontSize = 22,
        height = 30,
        bold = false,
    },
    {
        selectors = {"featureDescription"},
        width = "100%",
        height = "auto",
    },
    {
        selectors = {"collapsibleHeading"},
        width = "100%",
        height = 30,
        bgimage = "panels/square.png",
        bgcolor = "#ffffff00",
    },
    {
        selectors = {"collapsibleHeading", "hover"},
        bgcolor = "#ffffff11",
    },
}

function CharSheet.StartingEquipmentDisplay(claimedKey, hasclassStyle)

    hasclassStyle = hasclassStyle or "hasclass"

    local class = nil

    local catsToItems = EquipmentCategory.GetCategoriesToItems()

    local equipmentPanels = {}

    local m_startingEquipment

    local resultPanel

    resultPanel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",

        styles = {
            {
                classes = {"equipmentIcon"},
                bgimage = "white",
                width = 48,
                height = 48,
                bgcolor = "white",
            },
            {
                classes = {"equipmentIcon", "fade"},
                opacity = 0,
                transitionTime = 0.4,
            },
            {
                classes = {"equipmentOptionPanel"},
                pad = 4,
                width = 220,
                height = "auto",
                valign = "center",
                minHeight = 40,
                flow = "vertical",
            },

            {
                classes = {"equipmentOptionPanel", hasclassStyle, "hover", "~selected", "~claimed"},
                transitionTime = 0.2,
                bgcolor = "#ffffff22",
                borderWidth = 2,
                borderColor = "white",
            },

            {
                classes = {"equipmentOptionPanel", hasclassStyle, "selected"},
                transitionTime = 0.2,
                borderWidth = 2,
                borderColor = Styles.textColor,
            },

            {
                classes = {"dropdown", "claimed"},
                collapsed = 1,
            },
        },

        collectStartingEquipment = function(element, info)
            info.equipment = m_startingEquipment
        end,

        refreshStartingEquipment = function(element, creature, classArg)
            class = classArg

            m_startingEquipment = class:try_get("startingEquipment", {})
            local changed = false
            while #equipmentPanels > #m_startingEquipment do
                equipmentPanels[#equipmentPanels] = nil
                changed = true
            end

            while #equipmentPanels < #m_startingEquipment do
                local equipmentPanelIndex = #equipmentPanels + 1
                equipmentPanels[#equipmentPanels+1] = gui.Panel{
                    width = "auto",
                    height = "auto",
                    flow = "horizontal",
                    halign = "center",
                    vmargin = 4,

                    data = {
                        optionPanels = {},
                        dividerPanels = {},
                    },

                    collectStartingEquipment = function(element, info)
                        if #element.data.optionPanels > 1 then
                            local selected = false
                            for _,p in ipairs(element.data.optionPanels) do
                                if p:HasClass("selected") then
                                    selected = true
                                end
                            end

                            if not selected then
                                info.pending = true
                            end
                        end
                    end,

                    refreshStartingEquipment = function(element)
                        local equipmentEntry = m_startingEquipment[equipmentPanelIndex]

                        local changed = false
                        while #element.data.optionPanels > #equipmentEntry.options do
                            element.data.optionPanels[#element.data.optionPanels] = nil
                            if #element.data.dividerPanels > 0 then
                                element.data.dividerPanels[#element.data.dividerPanels] = nil
                            end
                            changed = true
                        end

                        while #element.data.optionPanels < #equipmentEntry.options do
                            local optionPanelIndex = #element.data.optionPanels+1
                            if optionPanelIndex > 1 then
                                element.data.dividerPanels[#element.data.dividerPanels+1] = gui.Label{
                                    fontSize = 14,
                                    width = "auto",
                                    height = 16,
                                    hpad = 6,
                                    textAlignment = "center",
                                    valign = "center",
                                    halign = "center",
                                    bold = false,
                                    text = tr("or"),
                                }
                            end
                            element.data.optionPanels[#element.data.optionPanels+1] = gui.Panel{
                                classes = {"equipmentOptionPanel", cond(resultPanel:HasClass(hasclassStyle), hasclassStyle)},

                                bgimage = "panels/square.png",


                                data = {
                                    itemPanels = {},
                                    dropdownOptions = {},
                                    dropdownItemPanels = {}, --each dropdown has a chosen item panel associated with it.
                                },


                                claimEquipment = function(element, creature)
                                    if element.enabled and element:HasClass("selected") then
                                        local choiceEntry = m_startingEquipment[equipmentPanelIndex]
                                        local optionEntry = choiceEntry.options[optionPanelIndex]
                                        for i,itemEntry in ipairs(optionEntry.items) do
                                            local inventoryTable = dmhub.GetTable("tbl_Gear")

                                            local itemInfo = inventoryTable[itemEntry.itemid]
                                            if itemInfo ~= nil then
                                                creature:GiveItem(itemEntry.itemid, itemEntry.quantity)
                                            else
                                                local currencyTable = dmhub.GetTable(Currency.tableName)
                                                local currencyInfo = currencyTable[itemEntry.itemid]
                                                if currencyInfo ~= nil then
                                                    creature:SetCurrency(itemEntry.itemid, creature:GetCurrency(itemEntry.itemid) + itemEntry.quantity, tr("Starting currency"))
                                                end
                                            end
                                        end
                                    end
                                end,
                

                                press = function(element)
                                    if element:HasClass("claimed") then
                                        return
                                    end

                                    local creature = CharacterSheet.instance.data.info.token.properties
                                    local choiceEntry = m_startingEquipment[equipmentPanelIndex]
                                    local optionEntry = choiceEntry.options[optionPanelIndex]
                                    if element:HasClass(hasclassStyle) then
                                        local creatureEquipmentChoices = creature:try_get("equipmentChoices", {})
                                        creatureEquipmentChoices[choiceEntry.guid] = optionEntry.guid
                                        creature.equipmentChoices = creatureEquipmentChoices
                                    end

                                    element.parent:FireEventTree("refreshStartingEquipment", creature, class)
                                    CharacterSheet.instance:FireEvent("refreshAll")
                                    CharacterSheet.instance:FireEventTree("refreshBuilder")
                                end,

                                refreshStartingEquipment = function(element)
                                    local creature = CharacterSheet.instance.data.info.token.properties
                                    local choiceEntry = m_startingEquipment[equipmentPanelIndex]
                                    local optionEntry = choiceEntry.options[optionPanelIndex]

                                    local creatureEquipmentChoices = creature:try_get("equipmentChoices", {})
                                    local optionChoice = creatureEquipmentChoices[choiceEntry.guid]

                                    element:SetClass("selected", #choiceEntry.options == 1 or optionChoice == optionEntry.guid)

                                    local changed = false

                                    while #element.data.itemPanels > #optionEntry.items do
                                        element.data.itemPanels[#element.data.itemPanels] = nil
                                        changed = true
                                    end

                                    while #element.data.itemPanels < #optionEntry.items do
                                        local itemIndex = #element.data.itemPanels+1

                                        local iconPanelCrossfade = nil
                                        local crossfading = false
                                        local fadeIndex = 1

                                        local mainPanel = nil
                                        local fadedPanel = nil

                                        local displayedItem = nil

                                        local iconPanel
                                        iconPanel = gui.Panel{
                                            classes = {"equipmentIcon"},
                                            bgimage = "panels/square.png",

                                            crossfade = function(element, imageid)
                                                if crossfading == false then
                                                    crossfading = true
                                                    element.bgimage = imageid
                                                    return
                                                end

                                                if iconPanelCrossfade == nil then
                                                    iconPanelCrossfade = 
                                                        gui.Panel{
                                                            classes = {"equipmentIcon", "fade"},
                                                            bgimage = "panels/square.png",
                                                        }
                                                    iconPanel.children = { iconPanelCrossfade }
                                                    mainPanel = iconPanel
                                                    fadedPanel = iconPanelCrossfade
                                                end

                                                fadedPanel.bgimage = imageid
                                                mainPanel:SetClass("fade", true)
                                                fadedPanel:SetClass("fade", false)

                                                local swap = mainPanel
                                                mainPanel = fadedPanel
                                                fadedPanel = swap
                                            end,

                                            removeCrossfade = function(element)
                                                element.children = {}
                                                element.thinkTime = nil
                                                iconPanelCrossfade = nil
                                                mainPanel = nil
                                                fadedPanel = nil
                                                crossfading = false
                                                element:SetClassTreeImmediate("fade", false)
                                            end,

                                            hover = function(element)
                                                if displayedItem ~= nil then
                                                    element.tooltip = CreateItemTooltip(displayedItem, {})
                                                end
                                            end,
                                        }

                                        element.data.itemPanels[#element.data.itemPanels+1] = gui.Panel{
                                            width = "100%",
                                            height = "auto",
                                            flow = "horizontal",

                                            iconPanel,

                                            gui.Label{
                                                classes = {"featureDescription"},
                                                valign = "center",
                                                width = "100%-56",

                                                data = {
                                                    imageList = nil,
                                                    imageListIndex = 1,
                                                },

                                                think = function(element)
                                                    if element.data.imageList ~= nil and #element.data.imageList > 0 then
                                                        element.data.imageListIndex = element.data.imageListIndex + 1
                                                        local itemid = element.data.imageList[1 + (element.data.imageListIndex%#element.data.imageList)]
                                                        local inventoryTable = dmhub.GetTable("tbl_Gear")
                                                        local itemInfo = inventoryTable[itemid]
                                                        if itemInfo ~= nil then
                                                            iconPanel:FireEvent("crossfade", itemInfo.iconid)
                                                        end
                                                    else
                                                        element.thinkTime = nil
                                                    end
                                                end,

                                                refreshStartingEquipment = function(element)
                                                    local itemEntry = m_startingEquipment[equipmentPanelIndex].options[optionPanelIndex].items[itemIndex]

                                                    local inventoryTable = dmhub.GetTable("tbl_Gear")
                                                    local equipmentCategoriesTable = dmhub.GetTable(EquipmentCategory.tableName)
                                                    local currencyTable = dmhub.GetTable(Currency.tableName)

                                                    local itemInfo = inventoryTable[itemEntry.itemid]
                                                    
                                                    if itemInfo == nil then
                                                        itemInfo = equipmentCategoriesTable[itemEntry.itemid]
                                                        if itemInfo ~= nil then
                                                            element.data.imageList = catsToItems[itemEntry.itemid]
                                                            if element.data.imageList ~= nil then
                                                                element:FireEvent("think")
                                                                element.thinkTime = 1.2
                                                            else
                                                                element.thinkTime = nil
                                                            end
                                                        else
                                                            itemInfo = currencyTable[itemEntry.itemid]
                                                            if itemInfo ~= nil then
                                                                --is a currency.
                                                                if crossfading then
                                                                    iconPanel:FireEvent("removeCrossfade")
                                                                end

                                                                iconPanel.bgimage = itemInfo.iconid
                                                                element.data.imageList = nil
                                                                element.thinkTime = nil
                                                            end
                                                        end
                                                    else
                                                        if crossfading then
                                                            iconPanel:FireEvent("removeCrossfade")
                                                        end

                                                        iconPanel.bgimage = itemInfo.iconid
                                                        element.data.imageList = nil
                                                        element.thinkTime = nil
                                                    end

                                                    displayedItem = itemInfo
                                                    element.text = string.format("%s x %d", tr(itemInfo.name), itemEntry.quantity)

                                                end,
                                            }
                                        }

                                        changed = true
                                    end

                                    if element:HasClass(hasclassStyle) then
                                        local dropdownIndex = 1
                                        local equipmentCategoriesTable = dmhub.GetTable(EquipmentCategory.tableName)
                                        local inventoryTable = dmhub.GetTable("tbl_Gear")
                                        for itemIndex,itemEntry in ipairs(optionEntry.items) do

                                            if equipmentCategoriesTable[itemEntry.itemid] ~= nil then

                                                --if any dropdown has selected for this category we hide the category and just use the dropdowns.
                                                local hasDropdownSelection = false

                                                for i=1,itemEntry.quantity do
                                                    changed = true
                                                    local dropdown = element.data.dropdownOptions[dropdownIndex]
                                                    local dropdownItemPanel = element.data.dropdownItemPanels[dropdownIndex]
                                                    if dropdown == nil then

                                                        dropdown = gui.Dropdown{
                                                            idChosen = "choose",
                                                            fontSize = 14,
                                                            width = 180,
                                                            height = 20,
                                                            change = function(element)
                                                                local equipmentChoiceId = string.format("%s-%d", itemEntry.guid, i)
                                                                creature = CharacterSheet.instance.data.info.token.properties
                                                                creatureEquipmentChoices = creature:try_get("equipmentChoices", {})
                                                                creatureEquipmentChoices[equipmentChoiceId] = element.idChosen
                                                                creature.equipmentChoices = creatureEquipmentChoices
                                                                CharacterSheet.instance:FireEvent("refreshAll")
                                                                CharacterSheet.instance:FireEventTree("refreshBuilder")
                                                            end,

                                                            collectStartingEquipment = function(element, info)
                                                                if element:HasClass("hidden") == false and element.idChosen == "choose" then
                                                                    info.pending = true
                                                                end
                                                            end,


                                                            claimEquipment = function(element, creature)
                                                                if element.enabled then
                                                                    local inventoryTable = dmhub.GetTable("tbl_Gear")
                                                                    local itemInfo = inventoryTable[element.idChosen]
                                                                    if itemInfo ~= nil then
                                                                        creature:GiveItem(element.idChosen, 1)
                                                                    end
                                                                end
                                                            end,

                                                        }

                                                        dropdownItemPanel = gui.Panel{
                                                            width = "100%",
                                                            height = "auto",
                                                            flow = "horizontal",
                                                            gui.Panel{
                                                                data = {
                                                                    item = nil,
                                                                },
                                                                classes = {"equipmentIcon"},
                                                                hover = function(element)
                                                                    if element.data.item ~= nil then
                                                                        element.tooltip = CreateItemTooltip(element.data.item, {})
                                                                    end
                                                                end,
                                                                item = function(element, item)
                                                                    element.data.item = item
                                                                    element.bgimage = item.iconid
                                                                end,
                                                            },

                                                            gui.Label{
                                                                classes = {"featureDescription"},
                                                                item = function(element, item)
                                                                    element.text = item.name
                                                                end,
                                                            },
                                                        }

                                                        element.data.dropdownOptions[dropdownIndex] = dropdown
                                                        element.data.dropdownItemPanels[dropdownIndex] = dropdownItemPanel
                                                    end


                                                    local options = {}
                                                    local itemList = catsToItems[itemEntry.itemid] or {}

                                                    for _,itemid in ipairs(itemList) do
                                                        local itemInfo = inventoryTable[itemid]
                                                        if itemInfo ~= nil and itemInfo:try_get("hidden", false) == false and EquipmentCategory.IsMagical(itemInfo) == false and EquipmentCategory.IsTreasure(itemInfo) == false then
                                                            options[#options+1] = {
                                                                id = itemid,
                                                                text = inventoryTable[itemid].name,
                                                            }
                                                        end
                                                    end

                                                    table.sort(options, function(a,b) return a.text < b.text end)
                                                    options[#options+1] = {
                                                        id = "choose",
                                                        text = "Choose Equipment...",
                                                    }

                                                    dropdown.options = options

                                                    local itemChosen = creatureEquipmentChoices[string.format("%s-%d", itemEntry.guid, i)] or "choose"
                                                    dropdown.idChosen = itemChosen

                                                    if itemChosen ~= "choose" then
                                                        hasDropdownSelection = true
                                                    end

                                                    if itemChosen == "choose" then
                                                        dropdownItemPanel:SetClass("collapsed", true)
                                                    else
                                                        dropdownItemPanel:SetClass("collapsed", false)
                                                        dropdownItemPanel:FireEventTree("item", inventoryTable[itemChosen])
                                                    end

                                                    dropdownIndex = dropdownIndex+1

                                                    dropdown:SetClass("hidden", not element:HasClass("selected"))
                                                end


                                                --if any dropdown selected an item then hide the category selection dialog.
                                                element.data.itemPanels[itemIndex]:SetClass("collapsed", hasDropdownSelection)
                                            end
                                        end

                                        while #element.data.dropdownOptions >= dropdownIndex do
                                            element.data.dropdownOptions[#element.data.dropdownOptions] = nil
                                            element.data.dropdownItemPanels[#element.data.dropdownItemPanels] = nil
                                            changed = true
                                        end

                                    elseif #element.data.dropdownOptions > 0 then
                                        element.data.dropdownOptions = {}
                                        element.data.dropdownItemPanels = {}
                                        changed = true
                                    end

                                    if changed then
                                        element.children = {element.data.itemPanels, element.data.dropdownItemPanels, element.data.dropdownOptions}
                                    end

                                    element:SetClassTree("claimed", creatureEquipmentChoices[claimedKey or "claimed"] == true)

                                end,
                            }
                            changed = true
                        end

                        if changed then
                            local children = {}

                            for i,optionPanels in ipairs(element.data.optionPanels) do
                                if i > 1 then
                                    children[#children+1] = element.data.dividerPanels[i-1]
                                end
                                children[#children+1] = optionPanels
                            end

                            element.children = children
                        end
                    end,
                }
                changed = true
            end

            if changed then
                element.children = equipmentPanels
            end
        end,
    }

    return resultPanel
end

function CharSheet.HitpointsPanel(classIndex)

    if GameSystem.CharacterBuilderShowsHitpoints == false then
        return gui.Panel{
            width = "100%",
            height = 1,
        }
    end

	local hitpointsPanels = {}
 
	local hitpointsPanel = gui.Panel{
        classes = {"hitpointsPanel"},
		width = "100%",
		flow = "vertical",
        vmargin = 8,

        styles = {
            {
                selectors = {"hitpointsPanel"},
                height = "auto",
            },
            {
                selectors = {"hitpointsPanel", "hidden"},
                height = 8,
            }
        },

		refreshBuilder = function(element)
            local creature = CharacterSheet.instance.data.info.token.properties
            local classes = creature:try_get("classes", {})

            if classIndex > #classes then
                element:SetClass("hidden", true)
                return
            end

            element:SetClass("hidden", false)

			local newHitpointsPanels = {}
			local children = {}

			local classesTable = dmhub.GetTable("classes")
			local conMod = GameSystem.BonusHitpointsForLevel(creature)

			newHitpointsPanels["conMod"] = hitpointsPanels["conMod"] or gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"featureDescription"},
					text = string.format("%s:", GameSystem.bonusHitpointsForLevelRulesText),
				},
				gui.Label{
					classes = {"featureDescription"},
					refreshBuilder = function(element)
						element.text = ModStr(conMod)
					end,
				},
			}

			children[#children+1] = newHitpointsPanels["conMod"]

			if creature.override_hitpoints then
				local overridePanel = hitpointsPanels["override"] or gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"featureDescription"},
						text = "Hitpoints:",
					},
					gui.Input{
						classes = {"smallNumberInput"},
						characterLimit = 3,
						change = function(element)
							local num = tonumber(element.text)
							if num ~= nil then
								creature.max_hitpoints = math.floor(num)
							end
							CharacterSheet.instance:FireEvent("refreshAll")
							CharacterSheet.instance:FireEventTree("refreshBuilder")
						end,
					},
				}

				overridePanel.children[2].text = tostring(creature.max_hitpoints)

				newHitpointsPanels["override"] = overridePanel
				children[#children+1] = overridePanel

				local notesPanel = hitpointsPanels["notes"] or gui.Input{
					classes = {"notesInput"},
					placeholderText = "Enter hitpoints notes...",
					multiline = true,
					change = function(element)
						creature.override_hitpoints_note = element.text
						CharacterSheet.instance:FireEvent("refreshAll")
						CharacterSheet.instance:FireEventTree("refreshBuilder")
					end,
				}

				notesPanel.text = creature.override_hitpoints_note

				newHitpointsPanels["notes"] = notesPanel
				children[#children+1] = notesPanel
			else
				for classNum,classInfo in ipairs(creature:get_or_add("classes", {})) do

					local c = classesTable[classInfo.classid]
					if c ~= nil then
						newHitpointsPanels[classInfo.classid] = hitpointsPanels[classInfo.classid] or gui.Label{
							classes = {"featureDescription"},
						}

						newHitpointsPanels[classInfo.classid].text = string.format("%s (d%d)\n", c.name, c.hit_die)
						children[#children+1] = newHitpointsPanels[classInfo.classid]

						for levelNum=1,classInfo.level do
							local key = string.format("%s-%d", classInfo.classid, levelNum)
							newHitpointsPanels[key] = hitpointsPanels[key] or gui.Panel{
								x = 20,
								classes = {"formPanel"},
                                vmargin = 0,
								gui.Label{
									classes = {"featureDescription"},
									text = string.format("Level %d", levelNum)
								},

								gui.Label{
									classes = {"featureDescription"},
									width = 40,
									characterLimit = 2,

									change = function(element)
										local num = tonumber(element.text)

                                        if num ~= nil then
                                            num = round(num)
                                        end


										local key = string.format("%s-%d", classInfo.classid, levelNum)
										local hitpointRolls = creature:get_or_add("hitpointRolls", {})
										local rollData = hitpointRolls[key]
										if rollData == nil then
											rollData = {
												history = {}
											}
											hitpointRolls[key] = rollData
										end

										rollData.roll = num
										if #rollData.history > 8 then
											table.remove(rollData.history, 1)
										end
										rollData.history[#rollData.history+1] = {
											timestamp = ServerTimestamp(),
											roll = rollData.total,
											manual = true,
										}
										
										CharacterSheet.instance:FireEvent("refreshAll")
										CharacterSheet.instance:FireEventTree("refreshBuilder")
									end,
								},

								gui.UserDice{
                                    valign = "center",
                                    width = 24,
                                    height = 24,
                                    faces = c.hit_die,
									click = function(element)
										element:SetClass("hidden", true)
										dmhub.Roll{
											roll = string.format("1d%d", c.hit_die),
											description = string.format("Level Hitpoints"),
											tokenid = dmhub.LookupTokenId(creature),
											complete = function(rollInfo)
												local key = string.format("%s-%d", classInfo.classid, levelNum)
												local hitpointRolls = creature:get_or_add("hitpointRolls", {})
												local rollData = hitpointRolls[key]
												if rollData == nil then
													rollData = {
														history = {}
													}
													hitpointRolls[key] = rollData
												end

												rollData.roll = rollInfo.total
												if #rollData.history > 8 then
													table.remove(rollData.history, 1)
												end
												rollData.history[#rollData.history+1] = {
													timestamp = ServerTimestamp(),
													roll = rollData.total,
												}

												CharacterSheet.instance:FireEvent("refreshAll")
												CharacterSheet.instance:FireEventTree("refreshBuilder")
											end,
										}
									end,
								},

								gui.Label{
									classes = {"featureDescription"},
									width = 40,
								},
							}

							local num = nil
							local editable = false
							
							if creature.roll_hitpoints and (levelNum ~= 1 or classNum ~= 1) then
								local hitpointRolls = creature:try_get("hitpointRolls", {})
								local roll = hitpointRolls[string.format("%s-%d", classInfo.classid, levelNum)]
								if roll ~= nil then
									num = roll.roll
								end

								editable = true
							else
								num = GameSystem.FixedHitpointsForLevel(c, levelNum == 1 and classNum == 1)
							end

							newHitpointsPanels[key].children[2].editable = editable


							if tonumber(num) == nil then
								newHitpointsPanels[key].children[2].text = "--"
								newHitpointsPanels[key].children[3]:SetClass("hidden", false)
								newHitpointsPanels[key].children[3].bgimage = string.format("ui-icons/d%d.png", c.hit_die)
                                element:FindParentWithClass("classTopLevelPanel"):FireEvent("alert")
							else
								newHitpointsPanels[key].children[2].text = tostring(num)
								newHitpointsPanels[key].children[3]:SetClass("hidden", true)
							end

							newHitpointsPanels[key].children[4].text = ModStr(conMod)

							children[#children+1] = newHitpointsPanels[key]
						end
					end
				end --end for loop over levels.
			end --end if hitpoints override


			local text = ""
			local baseHitpoints = creature:BaseHitpoints()
			local mods = creature:DescribeModifications("hitpoints", baseHitpoints)
			if mods ~= nil and #mods ~= 0 then
				text = string.format("%sBase Hitpoints: %d\n", text, baseHitpoints)
				for i,mod in ipairs(mods) do
					text = string.format("%s%s: %s\n", text, mod.key, mod.value)
				end
			end
			text = string.format("%sTotal Hitpoints: %d\n", text, creature:MaxHitpoints())

			local descriptionLabel = hitpointsPanels["descriptionLabel"] or gui.Label{
				classes = {"sheetLabel", "featureDescription"},
				width = "100%",
			}

			descriptionLabel.text = text

			newHitpointsPanels["descriptionLabel"] = descriptionLabel
			children[#children+1] = descriptionLabel

			hitpointsPanels = newHitpointsPanels
			element.children = children
		end,
	}   

    return hitpointsPanel

end

--[==[ DEAD_CODE - overridden by Draw Steel Core Rules\MCDMClassCarousel.lua:844
function CharSheet.ClassChoicePanel(options, classIndex)
    local resultPanel

    local leftPanel
    local rightPanel

    local classesTable = dmhub.GetTable(Class.tableName)

    local classPanels = {}

    local carousel

    local GetTargetIndex = function()
        local result = 1 - round(carousel.targetPosition)
        if result < 1 then
            result = 1
        end

        if result > #classPanels then
            result = #classPanels
        end
        return result
    end

    local SetTargetIndex = function(index)
        carousel.targetPosition = -(index-1)
    end

    local GetCurrentIndex = function()
        local index1 = clamp(1 - math.floor(carousel.currentPosition), 1, #classPanels)
        local index2 = clamp(1 - math.ceil(carousel.currentPosition), 1, #classPanels)

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

    for k,class in pairs(classesTable) do
        if class:try_get("hidden", false) == false then
            local portraitPanel = gui.Panel{
                classes = {"classPortrait"},
                bgimage = class.portraitid,

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
                classes = {"classPortraitContainer"},
                portraitPanel,
            }
            local shadow = gui.Panel{
                classes = {"classPortraitShadow"},
                interactable = false,
            }
            classPanels[#classPanels+1] = gui.Panel{
                data = {
                    index = 0,
                    class = class,
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
                data = {
                    class = class,
                },
                classes = {"classPanel"},
                shadow,
                portraitContainer,
            }
        end
    end

    table.sort(classPanels, function(a, b) return a.data.class.name < b.data.class.name end)
    for i,panel in ipairs(classPanels) do
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

        children = classPanels,



         refreshBuilder = function(element)
             local creature = CharacterSheet.instance.data.info.token.properties
             if creature:try_get("classes", {})[classIndex] ~= nil then
                element.draggable = false
                for i,panel in ipairs(classPanels) do
                    if panel.data.class.id == creature.classes[classIndex].classid then
                        element.currentPosition = -(i-1)
                        element.targetPosition = -(i-1)
                        panel:SetClass("hidden", false)
                    else
                        panel:SetClass("hidden", true)
                    end
                end
             else
                for i,panel in ipairs(classPanels) do
                    panel:SetClass("hidden", false)
                end
                element.draggable = true
             end
         end,

        enable = function(element)
            element.targetPosition = 0
            element.currentPosition = 0
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
                selectors = {"classPanel"},
                width = 400,
                height = "150% width",
                halign = "center",
                valign = "center",
            },
            {
                selectors = {"classPortraitContainer"},
                width = "100%",
                height = "100%",
                bgcolor = "black",
                borderColor = Styles.textColor,
                borderWidth = 2,
                bgimage = "panels/square.png",
            },
            {
                selectors = {"classPortraitContainer", "parent:hover", "~hasclass"},
                brightness = 1.5,
            },
            {
                selectors = {"classPortrait"},
                width = "100%-4",
                height = "100%-4",
                halign = "center",
                valign = "center",
                bgcolor = "white",
            },
            {
                selectors = {"classPortraitShadow"},
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
                selectors = {"paging-arrow", "hasclass"},
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

                element.text = classPanels[info.primary].data.class.name
                element.selfStyle.opacity = 1 - info.ratio

                child.text = classPanels[info.secondary].data.class.name
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
                if GetTargetIndex() < #classPanels then
                    SetTargetIndex(GetTargetIndex()+1)
                end
                resultPanel:FireEventTree("targetIndexChanged")
            end,
            targetIndexChanged = function(element)
                element:SetClass("hidden", GetTargetIndex() >= #classPanels)
            end,
        },
    }

    local displayedIndex = nil

    local GetSelectedClass = function()
		local creature = CharacterSheet.instance.data.info.token.properties
        if creature:try_get("classes", {})[classIndex] ~= nil then
            return classesTable[creature.classes[classIndex].classid]
        end

        if classPanels == nil or displayedIndex == nil or classPanels[displayedIndex] == nil then
            return nil
        end

        local class = classPanels[displayedIndex].data.class
        return class
    end


    --starting equipment panel
    local startingEquipmentPanel
    if classIndex == 1 then
        local startingEquipmentDisplay = CharSheet.StartingEquipmentDisplay()
        local claimEquipmentButton = gui.Button{
            text = "Claim Equipment",
            fontSize = 22,
            halign = "center",

            click = function(element)
                local creature = CharacterSheet.instance.data.info.token.properties
                startingEquipmentPanel:FireEventTree("claimEquipment", creature)

                local creatureEquipmentChoices = creature:try_get("equipmentChoices", {})
                creatureEquipmentChoices.claimed = true
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
                    element:Get("startingEquipment"):SetClass("collapsed", element:HasClass("collapseSet") or method ~= "equipment")
                    element:Get("startingGold"):SetClass("collapsed", element:HasClass("collapseSet") or method ~= "gold")
                end,
                gui.Label{
                    classes = {"sectionTitle"},
                    text = tr("Starting Equipment"),
                    refreshBuilder = function(element)
                        local creature = CharacterSheet.instance.data.info.token.properties
                        if creature:try_get("equipmentMethod", "equipment") == "gold" then
                            element.text = tr(string.format("Starting %s", Currency.GetMainCurrencyName()))
                        else
                            element.text = tr("Starting Equipment")
                        end
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

            gui.Panel{
                id = "startingGold",
                width = "100%",
                height = "auto",
                flow = "vertical",
                gui.Label{
                    classes = {"featureDescription"},
                    text = tr(string.format("Starting %s", Currency.GetMainCurrencyName())),
                    refreshBuilder = function(element)
                        element:FireEvent("refreshDescription")
                    end,

                    refreshDescription = function(element)
                        local creature = CharacterSheet.instance.data.info.token.properties
                        if creature:has_key("startingCurrencyReceived") then
                            element.text = string.format(tr("%s %s was added to your inventory to buy your starting equipment."), tostring(creature.startingCurrencyReceived), Currency.GetMainCurrencyName())
                            return
                        end

                        local class = GetSelectedClass()
                        if class == nil then
                            return
                        end

                        if not class:has_key("startingCurrency") then
                            element.text = string.format(tr("Your class grants you no starting %s."), Currency.GetMainCurrencyName())
                            return
                        end

                        local startingCurrency = class.startingCurrency
                        startingCurrency = string.gsub(startingCurrency, "%*", Styles.multiplySign)
                        element.text = string.format(tr("You begin with %s %s to purchase items with."), startingCurrency, Currency.GetMainCurrencyName())
                    end,
                },

                gui.Panel{
                    styles = CharSheet.DiceStyles,
                    classes = {"dice"},
					bgimage = "ui-icons/d20.png",

                    halign = "left",
                    click = function(element)
                        local creature = CharacterSheet.instance.data.info.token.properties
                        local class = GetSelectedClass()
                        dmhub.Roll{
                            roll = class.startingCurrency,
                            description = tr(string.format("Starting %s", Currency.GetMainCurrencyName())),
                            tokenid = dmhub.LookupTokenId(creature),

                            begin = function(rollInfo)
                                element:SetClass("hidden", true)
                            end,

							complete = function(rollInfo)
                                local creature = CharacterSheet.instance.data.info.token.properties

                                creature:SetCurrency(Currency.GetMainCurrencyStandard(), creature:GetCurrency(Currency.GetMainCurrencyStandard()) + rollInfo.total, tr(string.format("Starting %s", Currency.GetMainCurrencyName())))
                                creature.startingCurrencyReceived = rollInfo.total

                                CharacterSheet.instance:FireEvent("refreshAll")
                                CharacterSheet.instance:FireEventTree("refreshBuilder")
                            end,
                        }
                    end,
                    refreshBuilder = function(element)
                        local creature = CharacterSheet.instance.data.info.token.properties
                        local class = GetSelectedClass()
                        if class == nil or (not class:has_key("startingCurrency")) or creature:has_key("startingCurrencyReceived") then
                            element:SetClass("collapsed", true)
                            return
                        end

                        element:SetClass("collapsed", false)
                    end,
                },
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
                        local hasClass = creature:try_get("classes", {})[classIndex] ~= nil
                        element:SetClass("collapsed", not hasClass)
                        if hasClass then
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
                            if creatureEquipmentChoices.claimed then
                                claimEquipmentButton:SetClass("hidden", true)
                                equipmentClaimedLabel:SetClass("hidden", false)
                            else
                                claimEquipmentButton:SetClass("hidden", false)
                                equipmentClaimedLabel:SetClass("hidden", true)
                            end
                        end
                    end,
                },

                refreshDescription = function(element, class)
                    if class == nil then
                        return
                    end

                    local creature = CharacterSheet.instance.data.info.token.properties
                    element:FireEventTree("refreshStartingEquipment", creature, class)
                end,


                refreshBuilder = function(element)
                    local class = GetSelectedClass()
                    if class == nil then
                        return
                    end
                    local creature = CharacterSheet.instance.data.info.token.properties
                    if creature:try_get("equipmentMethod", "equipment") == "gold" then
                        return
                    end

                    element:FireEventTree("refreshDescription", class, true)
                end,

            },

            gui.Panel{
                classes = {"padding"},
            },
        }
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

            local class = GetSelectedClass()

            if class ~= nil then
                element:FireEventTree("refreshDescription", class)
            end

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

                gui.Panel{
                    flow = "horizontal",
                    width = "100%",
                    height = "auto",
                    gui.Label{
                        bold = false,
                        fontSize = 32,
                        valign = "top",
                        halign = "left",
                        height = 36,
                        width = "120% auto",
                        minWidth = 200,
                        textAlignment = "left",
                        
                        refreshDescription = function(element, class)
                            element.text = class.name
                        end,

                        fade = function(element,ratio)
                            element.selfStyle.opacity = ratio
                        end,

                    },

                    gui.Label{
                        bold = false,
                        fontSize = 26,
                        width = "auto",
                        height = "auto",
                        textAlignment = "left",
                        text = "Level",

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            local classes = creature:try_get("classes", {})
                            local collapse = classIndex == (#classes + 1)
                            element:SetClass("collapsed", collapse)
                        end,
                    },

                    gui.Label{
                        bold = false,
                        fontSize = 26,
                        width = 34,
                        height = "auto",
                        textAlignment = "left",
                        text = "1",
                        hmargin = 12,
                        editable = dmhub.isDM,

                        change = function(element)

                            local n = tonumber(element.text)
                            if n ~= nil then
                                local creature = CharacterSheet.instance.data.info.token.properties
                                local classes = creature.classes
                                n = clamp(round(n), 0, 20)
                                if n == 0 then
                                    table.remove(classes, classIndex)
                                else
                                    classes[classIndex].level = n
                                end
                            end

                            CharacterSheet.instance:FireEvent("refreshAll")
                            CharacterSheet.instance:FireEventTree("refreshBuilder")
                        end,

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            local classes = creature:try_get("classes", {})
                            local collapse = classIndex == (#classes + 1)
                            element:SetClass("collapsed", collapse)
                            if collapse then
                                return
                            end

                            element.text = tostring(classes[classIndex].level)
                        end,
                    },

                    gui.Panel{
                        flow = "vertical",
                        width = "auto",
                        height = 32,
                        valign = "center",

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            local classes = creature:try_get("classes", {})
                            if classes[classIndex] == nil then
                                element:SetClass("hidden", true)
                                return
                            end

                            element:SetClass("hidden", false)

                            local children = element.children
                            local chosenLevel = creature:CharacterLevelFromChosenClasses()
                            local level = creature:CharacterLevel()

                            children[1]:SetClass("hidden", chosenLevel >= 20)
                            children[2]:SetClass("hidden", chosenLevel <= 1 or classes[classIndex].level <= 1)
                        end,

                        gui.Panel{
                            classes = {"clickableIcon"},
                            bgimage = "panels/hud/down-arrow.png",
                            bgcolor = "white",
                            scale = {x = 1, y = -1},
                            height = "75% width",
                            valign = "center",

                            click = function(element)
                                local creature = CharacterSheet.instance.data.info.token.properties
                                local classes = creature:try_get("classes", {})
                                classes[classIndex].level = classes[classIndex].level + 1
                                CharacterSheet.instance:FireEvent("refreshAll")
                                CharacterSheet.instance:FireEventTree("refreshBuilder")
                            end,
                        },
                        gui.Panel{
                            classes = {"clickableIcon"},
                            bgimage = "panels/hud/down-arrow.png",
                            bgcolor = "white",
                            height = "75% width",
                            valign = "center",

                            click = function(element)
                                local creature = CharacterSheet.instance.data.info.token.properties
                                local classes = creature:try_get("classes", {})
                                classes[classIndex].level = classes[classIndex].level - 1
                                CharacterSheet.instance:FireEvent("refreshAll")
                                CharacterSheet.instance:FireEventTree("refreshBuilder")
                            end,
                        },
                    },


                    gui.Button{
                        text = tr("Remove Class"),
                        halign = "right",
                        valign = "top",
                        fontSize = 14,

                        refreshBuilder = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            element:SetClass("collapsed", classIndex ~= #creature:try_get("classes", {}))
                        end,

                        click = function(element)
                            local creature = CharacterSheet.instance.data.info.token.properties
                            creature.classes[#creature.classes] = nil

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
                        element:Get("classOverview"):SetClass("collapsed", element:HasClass("collapseSet"))
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
                    id = "classOverview",
                    classes = {"featureDescription"},
                    width = "100%",
                    wrap = true,
                    height = "auto",
                    refreshDescription = function(element, class)
                        element.text = class.details
                    end,

                    fade = function(element,ratio)
                        element.selfStyle.opacity = ratio
                    end,
                },

                gui.Panel{
                    classes = {"padding"},
                },

                gui.Panel{
                    classes = {"collapsibleHeading"},
                    click = function(element)
                        element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                        element:Get("classRules"):SetClass("collapsed", element:HasClass("collapseSet"))
                    end,
                    gui.Label{
                        classes = {"sectionTitle"},
                        text = tr("Class Attributes"),
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
                    id = "classRules",
                    width = "100%",
                    height = "auto",
                    flow = "vertical",

                    gui.Label{
                        classes = {"featureDescription"},
                        width = "100%",
                        height = "auto",
                        wrap = true,
                    },

                    --hitpoints config panel.
                    CharSheet.HitpointsPanel(classIndex),

                    gui.Label{
                        classes = {"featureDescription"},
                        width = "100%",
                        height = "auto",
                        wrap = true,
                    },

                    CharSheet.FeatureDetailsPanel{
                        alert = function(element)
                            resultPanel:FireEvent("alert")
                        end,
                    },

                    data = {
                        hitpointsPanel = nil,
                        descriptionPanel = nil,
                        featureDetailsPanel = nil,
                    },

                    refreshBuilder = function(element)
                        local class = GetSelectedClass()
                        if class == nil then
                            return
                        end

                        element:FireEvent("refreshDescription", class, true)
                    end,

                    refreshDescription = function(element, class, nofire)
                        if element.data.featureDetailsPanel == nil then
                            local children = element.children
                            element.data.hitpointsPanel = children[1]
                            element.data.descriptionPanel = children[3]
                            element.data.featureDetailsPanel = children[4]
                        end
                        local featureDetailsPanel = element.data.featureDetailsPanel

                        local hitpointsText = GameSystem.GenerateClassHitpointsRulesText(class)
                       
                        local savingThrows = nil

                        for i,saveid in ipairs(creature.savingThrowIds) do
                            local found = false
                            for i,haveid in ipairs(class.savingThrows) do
                                if haveid == saveid then
                                    found = true
                                    break
                                end
                            end

                            if found then
                                local saveInfo = creature.savingThrowInfo[saveid]
                                if savingThrows == nil then
                                    savingThrows = saveInfo.description
                                else
                                    savingThrows = string.format("%s, %s", savingThrows, saveInfo.description)
                                end
                            end
                        end

                        local proficienciesText = string.format(tr([[<size=120%%><smallcaps><b>Proficiencies</b></smallcaps></size>
<b>Saving Throws:</b> %s]]),
                            savingThrows or "None")

                        if not element:HasClass("hasclass") then
                            local featureDetails = {}
                            class:FillFeaturesForLevel({}, 0, nil, classIndex ~= 1, featureDetails)
                            for _,feature in ipairs(featureDetails) do
                                local text = string.format("<b>%s:</b> %s", feature.name, feature:GetRulesText())
                                if text ~= nil then
                                    proficienciesText = proficienciesText .. "\n" .. text
                                end
                            end

                            featureDetailsPanel.data.hide = true
                        else
                            featureDetailsPanel.data.hide = false
                            featureDetailsPanel.data.criteria = { class = class, maxlevel = 0 }
                        end


                        if not nofire then
                            featureDetailsPanel:FireEventTree("refreshBuilder")
                        end

                        element.data.hitpointsPanel.text = hitpointsText
                        element.data.descriptionPanel.text = proficienciesText
                    end,

                    fade = function(element,ratio)
                        element.selfStyle.opacity = ratio
                    end,
                },

                gui.Panel{
                    classes = {"padding"},
                },

                startingEquipmentPanel,

                gui.Panel{
                    classes = {"collapsibleHeading"},
                    click = function(element)
                        element:SetClassTree("collapseSet", not element:HasClass("collapseSet"))
                        element:Get("traits"):SetClass("collapsed", element:HasClass("collapseSet"))
                    end,
                    gui.Label{
                        classes = {"sectionTitle"},
                        text = tr("Class Features"),
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

                    --class
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
                        local class = GetSelectedClass()
                        if class == nil then
                            return
                        end

                        element:FireEvent("refreshDescription", class, true)
                    end,

                    refreshDescription = function(element, class, nofire)
                        if element.data.featureDetailsPanels == nil then
                            element.data.featureDetailsPanels = element.children
                        end

                        local detailsPanels = element.data.featureDetailsPanels

                        local textItems = {
                        }

                        if not element:HasClass("hasclass") then
                            for i,p in ipairs(detailsPanels) do
                                p.data.hide = true
                            end

                            local featureDetails = {}
                            class:FillFeaturesForLevel({}, 1, nil, "noprimary", featureDetails)

                            for _,feature in ipairs(featureDetails) do
                                local text = feature:GetSummaryText()
                                if text ~= nil then
                                    textItems[#textItems+1] = text
                                end
                            end
                        else
			                local creature = CharacterSheet.instance.data.info.token.properties
                            local classes = {class}
                            local subclass = creature:GetSubClass(class)
                            if subclass ~= nil then
                                classes[#classes+1] = subclass
                            end
                            detailsPanels[1].data.hide = false
                            detailsPanels[1].data.criteria = { class = classes, minlevel = 1 }
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
                    selectors = {"#carouselContainer", "hasclass"},
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
                element:SetClass("collapsed", creature:try_get("classes", {})[classIndex] ~= nil)
            end,

            click = function(element)
			    local creature = CharacterSheet.instance.data.info.token.properties

                local class = GetSelectedClass()

                creature:SetClass(class.id, 1)

				CharacterSheet.instance:FireEvent("refreshAll")
				CharacterSheet.instance:FireEventTree("refreshBuilder")
            end,
        },
    }

    local m_lastTokenId = nil

    local args = {
        classes = {"classTopLevelPanel"},
		width = "100%",
		height = "100%",
		flow = "horizontal",
		halign = "center",
		valign = "center",

        refreshBuilder = function(element)

            local newChar = m_lastTokenId ~= CharacterSheet.instance.data.info.token.charid
            m_lastTokenId = CharacterSheet.instance.data.info.token.charid

            local creature = CharacterSheet.instance.data.info.token.properties
            local hasClass = creature:try_get("classes", {})[classIndex] ~= nil

            if newChar then
                element:SetClassTreeImmediate("hasclass", hasClass)
            else
                element:SetClassTree("hasclass", hasClass)
            end
            if not hasClass then
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
--]==]
