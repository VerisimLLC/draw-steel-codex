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
