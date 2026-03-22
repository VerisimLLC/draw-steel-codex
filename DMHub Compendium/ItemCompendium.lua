local mod = dmhub.GetModLoading()

setting{
    id = "compendium:showmagicitems",
    default = false,
    storage = "preference",
}

setting{
    id = "compendium:showtreasure",
    default = false,
    storage = "preference",
}

setting{
    id = "compendium:showuniqueitems",
    default = false,
    storage = "preference",
}

mod.shared.InventoryCompendiumEditor = function(categories)
    if categories then
        local newcats = {}
        for _,catid in ipairs(categories) do
            newcats[catid] = true
        end
        categories = newcats
    end

	local catsTable = dmhub.GetTable('equipmentCategories') or {}

	local resultPanel

	local leftPanel
	local displayPanel

	local searchTerms = nil

	local searchPanel = gui.Input{
		width = "100%",
		placeholderText = "Filter Inventory...",

		editlag = 0.2,
		edit = function(element)
			if string.len(element.text) <= 0 then
				searchTerms = nil
			else
				searchTerms = string.split(string.lower(element.text))
			end

			resultPanel:FireEventTree("search")
		end,
	}


    local showUnique = dmhub.GetSettingValue("compendium:showuniqueitems")

    local uniqueCheck = gui.Check{
        text = "Show Unique Items",
        value = showUnique,
        change = function(element)
            dmhub.SetSettingValue("compendium:showuniqueitems", element.value)
            showUnique = element.value
            resultPanel:FireEventTree("refreshInventory")
        end,
    }

	local itemPanels = {}

	local itemScrollPanel = gui.Panel{
		width = "100%",
		height = "100%-110",
		flow = "vertical",
		vscroll = true,
		hideObjectsOutOfScroll = true,

		create = function(element)
			element:FireEventTree("refreshInventory")
		end,

		refreshInventory = function(element)
			local newItemPanels = {}
			local children = {}
			local itemsTable = dmhub.GetTable("tbl_Gear")
			local itemsHiddenByDefault = dmhub.GetSettingValue("hideitems")
			for k,item in pairs(itemsTable) do
				local itemid = k

				if (not item:try_get("hidden", false)) and
                   (categories == nil or categories[item:try_get("equipmentCategory", "")]) and
                   (showUnique or (not item:has_key("uniqueItem"))) and
                   (dmhub.isDM or (not item:try_get("hiddenFromPlayers", itemsHiddenByDefault))) then
					local itemPanel = itemPanels[k] or gui.Panel{
						data = {
							item = item,
							init = false,
						},

						classes = {"itemPanel"},

						draggable = true,

                        press = function(element)
                            displayPanel:FireEvent("select", item)
                            for i,el in ipairs(element.parent.children) do
                                el:SetClass("selected", false)
                            end

                            element:SetClass("selected", true)
                        end,

                        hover = function(element)
                            displayPanel:FireEvent("show", item)
                        end,
                        dehover = function(element)
                            displayPanel:FireEvent("hide", item)
                        end,

						drag = function(element, target)
							if target == nil then
								return
							end

							local itemList = target.data.itemList
							if not itemList.items[k] then
								itemList.items[k] = true
								dmhub.SetAndUploadTableItem(ItemList.tableName, itemList)
								resultPanel:FireEventTree("refreshItemLists")
							end
						end,


						canDragOnto = function(element, target)
							return target:HasClass("itemListPanel")
						end,

						rightClick = function(element)
						
							local entries = {}

							entries[#entries+1] = {
								text = "Duplicate Item",
								click = function()
									local newItem = DeepCopy(item)
									newItem.id = dmhub.GenerateGuid()
									newItem.name = string.format("%s (Dup.)", newItem.name)
									dmhub.SetAndUploadTableItem("tbl_Gear", newItem)
									element.popup = nil
									resultPanel:FireEventTree("refreshInventory")
								end,
							}


							entries[#entries+1] = {
								text = "Delete Item",
								click = function()
									item.hidden = true
									dmhub.SetAndUploadTableItem("tbl_Gear", item)
									element.popup = nil
									element:DestroySelf()
								end,
							}

							element.popup = gui.ContextMenu{
								entries = entries,
							}
						end,

						search = function(element)
							if searchTerms == nil then
								element:SetClass("collapsed", false)
								return
							end

							local match = true
							local cat = catsTable[item:try_get("equipmentCategory", "")]
							local catName = cat ~= nil and string.lower(cat.name) or ""
							for _,term in ipairs(searchTerms) do
								if match then
									match = false
									if TextSearch(item.name, term) or TextSearch(catName, term) then
										match = true
									end
								end
							end

							element:SetClass("collapsed", not match)
							if match and element.data.init == false then
								element:FireEvent("expose")
							end
						end,

						expose = function(element)
							if element.data.init == false then

								element.data.init = true
								element.children = {
									gui.Label{
										classes = {"itemNameLabel"},
                                        selfStyle = {
                                            color = "white",
                                        },
										refreshInventory = function(element)
											element.text = item.name
                                            element.selfStyle.color = equipment.rarityColors[item:try_get("rarity", "common")]
										end,

										gui.NewContentAlertConditional("tbl_Gear", item.id, {x = -2}),
									},

                                    gui.Label{
										classes = {"itemCategoryLabel"},

										refreshInventory = function(element)
	                                        local cat = catsTable[item:try_get("equipmentCategory", '')]
                                            if cat == nil then
                                                element.text = "---"
                                            else
											    element.text = cat.name

                                            end
										end,
                                    },



									gui.ImplementationStatusIcon{
										refreshInventory = function(element)
											element:FireEvent("implementation", item:try_get("implementation", 1))
										end,
									},

									gui.SettingsButton{
										width = 16,
										height = 16,
										click = function(element)
									        gamehud.createItemDialog.data.show(resultPanel, item)
										end,
									}
								}

								element:FireEventTree("refreshInventory")
							end

						end,

					}

					children[#children+1] = itemPanel
					newItemPanels[k] = itemPanel
				end

			end

			table.sort(children, function(a,b) return a.data.item.name < b.data.item.name end)

			element.children = children
			itemPanels = newItemPanels
		end,
	}

	local addItemButton = gui.AddButton{
		width = 24,
		height = 24,
		halign = "right",
		click = function(element)
			gamehud.createItemDialog.data.show(resultPanel)
		end,
	}

	leftPanel = gui.Panel{
		height = "100%",
		width = 480,
		flow = "vertical",
		halign = "left",

		searchPanel,
        uniqueCheck,
		itemScrollPanel,
		addItemButton
	}

    displayPanel = gui.Panel{
        height = 1000,
        width = 840,
        hmargin = 16,
        halign = "top",
        vscroll = true,
        styles = {
            {
                selectors = {"label"},
                fontSize = 34,
            },
        },
        data = {
            selected = nil,
            shown = nil,
        },
        select = function(element, item)
            element.data.selected = item
            element:FireEvent("show", item)
        end,
        show = function(element, item)
            if item ~= nil then
                element.children = {CreateItemTooltip(item, {width = 800, valign = "top"})}
                element.data.shown = item
            else
                element:FireEvent("hide")
            end
        end,
        hide = function(element, item)
            if item == nil or (item == element.data.shown and item ~= element.data.selected) then
                element.children = {}
                element.data.shown = nil

                if element.data.selected ~= nil then
                    element:FireEvent("show", element.data.selected)
                end
            end

        end,
    }

	resultPanel = gui.Panel{
		width = "100%",
		height = "100%",
		flow = "horizontal",

        newItem = function(element)
            element:FireEventTree("refreshInventory")
        end,

		leftPanel,
        displayPanel,

		styles = {
			{
				selectors = {"itemPanel"},
				bgimage = "panels/square.png",
				bgcolor = "clear",
				height = 22,
				width = "100%",
				flow = "horizontal",
			},
			{
				selectors = {"itemPanel", "hover"},
				bgcolor = "#770000",
			},
			{
				selectors = {"itemPanel", "selected"},
				bgcolor = "#770000",
			},
			{
				selectors = {"itemNameLabel"},
				fontSize = 16,
				minFontSize = 10,
				textWrap = false,
				bold = true,
				hmargin = 4,
				width = 200,
				height = "auto",
				textAlignment = "left",
			},
			{
				selectors = {"itemCategoryLabel"},
				fontSize = 16,
				hmargin = 4,
				width = 200,
				height = "auto",
				textAlignment = "left",
			},
			{
				selectors = {"itemSchoolLabel"},
				fontSize = 16,
				width = 120,
				height = "auto",
				textAlignment = "left",
				hmargin = 4,
			},
            {
                selectors = {"checkbox-label"},
                fontSize = 12,
            },
			Styles.ImplementationIcon,
		},
	}

	return resultPanel
end

Compendium.InventoryEditor = mod.shared.InventoryCompendiumEditor