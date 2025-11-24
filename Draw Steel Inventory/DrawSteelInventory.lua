local mod = dmhub.GetModLoading()

--this file implements the inventory screen obtained by pressing 'i' while having a character selected.

local function GetBasicInventoryDialog(element)
    local charSheetPanel = element:FindParentWithClass("characterSheetPanel")
    if charSheetPanel == nil then
        return nil
    end

    return charSheetPanel.data.basicInventoryDialog
end

local function GetTradeInventoryDialog(element)
    local charSheetPanel = element:FindParentWithClass("characterSheetPanel")
    if charSheetPanel == nil then
        return nil
    end

    return charSheetPanel.data.tradeInventoryDialog
end


local SlotDim = 72

local g_SlotHighlightStyles = {
	{
		bgimage = true,
        bgcolor = "clear",
		width = 70,
		height = 70,
		halign = 'center',
		valign = 'center',
		opacity = 0,
        borderWidth = 2,
        borderColor = "white",
	},

	{
		opacity = 0.5,
		selectors = 'drag-target',
	},
	{
		opacity = 0.8,
		selectors = 'drag-target-hover',
	},
	{
		selectors = {"parent:drag-target"},
		opacity = 0.5,
	},
	{
		selectors = {"parent:drag-target-hover"},
		opacity = 1,
	},
	{
		selectors = {"highlight"},
		opacity = 1,
	},
}

local SlotStyles = {
	gui.Style{
		classes = {"slotBorder"},
        hidden = 1,
		bgimage = 'panels/InventorySlot_Border.png',
		bgcolor = "white",
		width = '100%+20',
		height = '100%+20',
	},
	gui.Style{
		classes = {"slotBorder", "uncommon"},
	},
	gui.Style{
		classes = {"slotBorder", "rare"},
	},
	gui.Style{
		classes = {"slotBorder", "very rare"},
	},
	gui.Style{
		classes = {"slotBorder", "legendary"},
	},
}

local g_InventoryStyles = {
    gui.Style{
        selectors = {"inventorySlot"},
		--bgimage = 'panels/InventorySlot_Background.png',
        bgimage = "panels/square.png",
        bgcolor = "#00000055",
        borderWidth = 1,
        borderColor = "#ffffff22",
        margin = 2,
    },
}
 
local g_SlotStyles = {
	gui.Style{
		flow = 'none',
		width = SlotDim-4,
		height = SlotDim-4,
		margin = 0,
		pad = 0,
	},
	gui.Style{
		selectors = {'adding', 'hover'},
		brightness = 1.5,
	},
	gui.Style{
		selectors = {'accessParty', 'hover'},
		brightness = 1.5,
	},
	gui.Style{
		selectors = {'adding', 'press'},
		brightness = 0.8,
	},
	gui.Style{
		selectors = {'accessParty', 'press'},
		brightness = 0.8,
	},
}




local framesByRarity = {
	common = 'panels/InventorySlot_Border.png',
	uncommon = 'panels/InventorySlot_uncommon-border.png',
	rare = 'panels/InventorySlot_rare-border.png',
	["very rare"] = 'panels/InventorySlot_very-rare-border.png',
	legendary = 'panels/InventorySlot-legendary-border.png',
}

local SlotBorder = function(args)
	args = DeepCopy(args or {})
	if args.width == nil then
		args.width = 18
	end
	if args.grow == nil then
		args.grow = 10
	end

	local rarity = nil

	local resultPanel
	resultPanel = gui.Panel{
	id = string.format("slotBorder-%s", dmhub.GenerateGuid()),
		classes = {"slotBorder", args.rarity},
		floating = true,
		interactable = false,

		data = {
			SetRarity = function(newRarity)
				if rarity == newRarity then
					return
				end
				if rarity ~= nil then
					resultPanel:SetClass(rarity, false)
				end
				rarity = newRarity
				if rarity ~= nil then
					resultPanel:SetClass(rarity, true)
				end
				resultPanel.bgimage = framesByRarity[rarity or "common"]
			end,
		},


		selfStyle = {
		--	bgcolor = "white",
			bgslice = args.width,
			border = args.border,
			halign = 'center',
			valign = 'center',
		}
	}

	resultPanel.data.SetRarity(args.rarity)

	return resultPanel
end

local QuantityPopup = function(options)
	if options.value == 1 and options.maxValue == 1 then
		--just auto-execute if there are no choices.
		options.confirm(1)
		return
	end

	local slider =

			gui.Slider{
				style = {
					height = 40,
					width = 200,
					fontSize = 14,
					halign = 'center',
				},

				sliderWidth = 140,
				labelWidth = 50,
				value = options.value,
				minValue = 1,
				maxValue = options.maxValue,

				formatFunction = function(num)
					return string.format('%d', round(num))
				end,

				deformatFunction = function(num)
					return num
				end,
			}
	return gui.Panel{
		classes = {"framedPanel"},
		styles = {Styles.Default, Styles.Panel},
		selfStyle = {
			halign = 'center',
			valign = 'center',
			width = 240,
			height = "auto",
			flow = 'vertical',
		},
		children = {

			gui.CloseButton{
				halign = "right",
				valign = "top",
				floating = true,
				click = function(element)
					options.cancel()
				end,
			},

			gui.Label{
				text = options.title or 'Quantity',
				selfStyle = {
					vmargin = 16,
					height = 'auto',
					width = 'auto',
					halign = 'center',
					fontSize = 24,
				}
			},

			slider,

			gui.Button{
				text = 'Confirm',
				vmargin = 16,
				halign = 'center',
				fontSize = 16,
				events = {
					click = function(element)
						options.confirm(round(slider.value))
					end
				},
			},
		}
	}
end

function CreateItemTooltip(item, options, token)

	options = options or {}


	local tooltipResult = gui.TooltipFrame(gui.Panel{
		id = 'inventory-item-tooltip',
		styles = {
			{
				textWrap = true,
				halign = options.tooltipAlign or 'left',
				valign = 'top',
				height = 'auto',
				width = options.width or 400,
				bgcolor = 'black',
				flow = 'vertical',
				color = 'white',
				margin = 0,
			},
		},

		valign = "center",
		maxHeight = 1080,

		item:Render(options, token),

	}, {
		halign = options.tooltipAlign or 'left',
		valign = options.valign or 'center',
	})

	tooltipResult:MakeNonInteractiveRecursive()

	return tooltipResult
end



local CreateInventorySlot = function(dmhud, options)
	local guid = dmhub.GenerateGuid()
	--the current token this pertains to.
	local token = nil

	--if this slot is set up to add a new item.
	local adding = false

	--if adding is true and this function is set, this function will be called instead.
	local addingFunction = nil
	local addingTooltip = nil

	--if this slot is set up to allow us to access party inventory
	local accessParty = false

	local item = nil

	local m_quantityNum = 1


	local slotPanel = nil

	--will be populated with the parent dialog that owns this.
	local parentDialog = nil

	local testVisibilityFunction = nil

	local highlightPanel = gui.Panel{
        classes = {"slotHighlight"},
		interactable = false,

		styles = g_SlotHighlightStyles,
	}

	local iconPanel = gui.Panel{
		id = 'inventory-slot-icon',
		draggable = false,

		canDragOnto = function(element, target)
			if options.rearrange and target.data.singleInventorySlot and token ~= nil and target.data.GetToken() == token then
				return target.data.GetGuid() ~= gui --return true as long as it's not literally the same slot.
			elseif token ~= nil and target.data.GetToken ~= nil and target.data.GetToken() == token then
				return false
			end

			if options.basicInventory or options.tradeInventory then
				return target.data.inventoryDragTarget
			elseif target.data.equipmentSlot ~= nil then
				local slotInfo = creature.EquipmentSlots[target.data.equipmentSlot]
                if slotInfo.categories ~= nil then
                    if slotInfo.categories[item:CategoryId()] then
                        return true
                    end 

                    return false
                end

                if slotInfo.type == "trinket" and EquipmentCategory.IsTrinket(item) then
                    return true
                elseif slotInfo.type == "leveled" and EquipmentCategory.IsLeveledTreasure(item) then
                    return true
                end

			else
				return target.data.inventoryDragTarget
			end

			return false
		end,

		styles = {
			{
				width = 64,
				height = 64,
				halign = 'center',
				valign = 'center',
			},
			{
				selectors = 'new',
				scale = 1.5,
				brightness = 2,
				rotate = 20,
				transitionTime = 0.5,
			},
		},

		events = {
			drag = function(element, target)
				if target ~= nil then
					if target.data.singleInventorySlot then
						--rearrange a slot.
						if token ~= nil and token.valid then
							local quantityMoving = m_quantityNum

							token:BeginChanges()
							if target.data.GetItem() ~= nil then
								token.properties:RearrangeInventory(target.data.GetItem().id, target.data.inventoryIndex, slotPanel.data.inventoryIndex, target.data.GetQuantity())
							end
							token.properties:RearrangeInventory(item.id, slotPanel.data.inventoryIndex, target.data.inventoryIndex, quantityMoving)
							token:CompleteChanges("Rearrange inventory")
							parentDialog:FireEventTree('refreshInventory')
						end
						return
					end

					if (not target.data.equipmentSlot) and token ~= nil and token.valid then
						local shopping = token.type == "component" and token.shop
						local targetSpends = nil
						if shopping then
							local price = token.properties:GetItemPrice(item.id)
							local targetToken = target.data.GetToken()
							if targetToken ~= nil and targetToken.valid then
								targetSpends = Currency.CalculateSpend(targetToken.properties, Currency.CalculatePriceInStandard(price))
								if targetSpends == nil then
									target.data.CannotAfford()
									return
								end
							end
						end

						--is a full trade.
						token:BeginChanges()
						local quantity

						local quantityAvailable = token.properties:QuantityInSlot(item.id, slotPanel.data.inventoryIndex)

						if shopping then
							quantity = math.min(quantityAvailable, item:TradedQuantity())
						else
							quantity = quantityAvailable
						end

						token.properties:SetItemQuantity(item.id, token.properties:GetItemQuantity(item.id) - quantity, slotPanel.data.inventoryIndex)
						token:CompleteChanges('Trade item')
						target.data.AddItem(item, quantity, { currencyChanges = targetSpends })
						parentDialog:FireEventTree('refreshInventory')

						if token.type == "component" and token.destroyOnEmpty and token.properties:Empty() then
							if parentDialog ~= nil then
								parentDialog.data.close()
							end
							token:DestroyObject()
						end
					else
						target.data.AddItem(item, item:TradedQuantity(), { slot = slotPanel.data.inventoryIndex })
					end
				end
			end,
		},
	}

	local iconEffectPanel = gui.Panel{
		id = 'inventory-slot-effect',
		selfStyle = {},
		styles = {
			{
				width = 64,
				height = 64,
				halign = 'center',
				valign = 'center',
			},
		},
	}

	local stackQuantity = 0

	local quantityLabel = gui.Label{
		id = 'inventory-slot-quantity',
		editable = true,
		halign = "right",
		valign = "bottom",
		styles = {
			{
				width = 30,
				height = 20,
				bold = true,
				margin = 4,
				color = 'white',
				fontSize = '40%',
				textAlignment = 'bottomright',
			},
			{
				selectors = {'invisible'},
				opacity = 0,
			},
		},
		events = {
			quantity = function(element, quantity)
				m_quantityNum = quantity
				stackQuantity = quantity

				if item ~= nil and item:try_get("consumable") and item:try_get("consumableCharges", 1) > 1 then
					local consumed = item:try_get("consumableChargesConsumed", 0)
					local remaining = math.max(0, item.consumableCharges - consumed)

					element.text = string.format("%d/%d", remaining, item.consumableCharges)
					element:SetClass('invisible', false)
					return
				end

				element:SetClass('invisible', quantity <= 1)
				element.text = string.format("%d", math.tointeger(quantity))
			end,
			change = function(element)

				if item ~= nil and item:try_get("consumable") and item:try_get("consumableCharges", 1) > 1 then
					--an item with charges.
					local a,b = string.match(element.text, "(%d+)/(%d+)")
					if a ~= nil and b ~= nil and b >= a then
						item.consumableCharges = tonumber(b)
						item.consumableChargesConsumed = tonumber(b) - tonumber(a)
					else
						local a = string.match(element.text, "(%d+)")
						if a ~= nil then
							a = tonumber(a)
							if a > item.consumableCharges then
								item.consumableCharges = a
							end

							item.consumableChargesConsumed = item.consumableCharges - a
						end
					end
					element.text = string.format("%d/%d", item.consumableCharges - item.consumableChargesConsumed, item.consumableCharges)
					dmhub.SetAndUploadTableItem("tbl_Gear", item)
					return
				end


				local quantity = tonumber(element.text)
				if quantity ~= nil and token ~= nil and token.valid then
					quantity = round(quantity)

					--work out the new total quantity of this item
					local delta = quantity - stackQuantity
					local newQuantity = token.properties:GetItemQuantity(item.id) + delta

					token:BeginChanges()
					token.properties:SetItemQuantity(item.id, newQuantity, slotPanel.data.inventoryIndex)
					token:CompleteChanges('Set Item Quantity')

					slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')
					
				end
			end,
		},
	}

	local priceDisplayCurrency = nil
	local priceLabel = gui.Label{
		id = 'inventory-slot-price',
		editable = true,
		minWidth = 14,
		width = "auto",
		height = 20,
		bold = true,
		margin = 4,
		color = '#ffff99ff',
		fontSize = '40%',
		halign = 'right',
		valign = 'center',
		textAlignment = 'topright',
		events = {
			change = function(element)
				local price = tonumber(element.text)
				if price ~= nil and priceDisplayCurrency ~= nil then
					token:BeginChanges()
					token.properties:SetItemPrice(item.id, {[priceDisplayCurrency] = price})
					printf("PRICE:: %s -> %s : %s", item.id, json({[priceDisplayCurrency] = price}), json(token.properties:GetItemPrice(item.id)))
					token:CompleteChanges('Set Item Price')

					slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')
				end
			end,
		},
	}

	local priceIcon = gui.Panel{
		bgimage = "panels/square.png",
		bgcolor = "white",
		height = 14,
		width = 14,
		halign = "right",
	}

	local pricePanel = gui.Panel{
		flow = "horizontal",
		halign = "right",
		valign = "top",
		height = 20,
		width = 60,
		priceIcon,
		priceLabel,
	}

	local currentRarity = nil
	local border = SlotBorder{}
	local SetRarity = function(rarity)
		if currentRarity == rarity then
			return
		end

		border.data.SetRarity(rarity)

	--if currentRarity ~= nil then
	--	border:SetClass(currentRarity, false)
	--end
	--
	--if rarity ~= nil then
	--	border:SetClass(rarity, true)
	--end

		currentRarity = rarity
	end

	slotPanel = gui.Panel{
		id = 'inventory-slot',
        classes = {"inventorySlot"},

		dragTarget = options.rearrange,

		styles = g_SlotStyles,
       
		children = {
			iconPanel,
			border,
			highlightPanel,
			iconEffectPanel,
			quantityLabel,
			pricePanel,
		},

		events = {
			refreshInventory = function(element)
				element:SetClass("hidden", testVisibilityFunction ~= nil and testVisibilityFunction() == false)
			end,

			hover = function(element)
				if item ~= nil then
					element.tooltipParent = element.data.inventoryDialog

					local itemOptions = DeepCopy(options)
					if token ~= nil then
						itemOptions.costOverride = token.properties:GetItemPrice(item.id)
					end
					element.tooltip = CreateItemTooltip(item, itemOptions, token)
					highlightPanel:SetClass('highlight', true)
				elseif slotPanel:HasClass('adding') then
					element.tooltipParent = nil

					local tooltip = addingTooltip
					if type(tooltip) == "function" then
						tooltip = tooltip()
					end

					gui.Tooltip(tooltip or 'Add Items')(element)
					highlightPanel:SetClass('highlight', true)
				elseif slotPanel:HasClass('accessParty') then
					element.tooltipParent = nil
					gui.Tooltip('Access Party Inventory')(element)
					highlightPanel:SetClass('highlight', true)
				end
			end,
			dehover = function(element)
				highlightPanel:SetClass('highlight', false)
			end,

			click = function(element)
                local basicInventoryDialog = GetBasicInventoryDialog(element) or dmhud.basicInventoryDialog
                local tradeInventoryDialog = GetTradeInventoryDialog(element) or dmhud.tradeInventoryDialog
				element.popup = nil
				if adding then
					if addingFunction ~= nil then
                        print("ADD:: AddingFunction()")
						addingFunction()
					else
						tradeInventoryDialog.data.close()
                        print("ADD:: ToggleOpen()")
						basicInventoryDialog.data.toggleOpen()
					end
				elseif accessParty and token ~= nil and token.partyid ~= nil then
					dmhub.Debug("OPEN::TRY")
					local partyInfo = dmhub.GetPartyInfo(token.partyid)
					basicInventoryDialog.data.close()
					tradeInventoryDialog.data.toggleOpen(partyInfo, { isobject = true, partyinventory = true, title = 'Party Inventory', tradewith = token })
				elseif item ~= nil then
					--inspect the item.
					if item:has_key("inspectionImage") then
						dmhub.ViewSign(item:try_get("inspectionImage", item.iconid))
					else
						GameHud.instance:ViewCompendiumEntryModal(item, token)
					end
				end
			end,

			rightClick = function(element)
				if options.basicInventory and item ~= nil and not adding then

					element.popup = gui.ContextMenu {
						entries = {
							{
								text = 'Share to Chat',
								click = function()
									element.popup = nil
									chat.ShareObjectInfo("tbl_Gear", item.id)
								end,
							},
							{
								text = 'Edit Item',
								click = function()
                                    local basicInventoryDialog = GetBasicInventoryDialog(element) or dmhud.basicInventoryDialog
									element.popup = nil
									dmhud.createItemDialog.data.show(basicInventoryDialog, item)
								end,
							},
							{
								text = 'Duplicate Item',
								click = function()
									element.popup = nil

									local newItem = DeepCopy(item)
									newItem.id = dmhub.GenerateGuid()
									newItem.name = string.format("%s (Dup.)", newItem.name)

									if newItem:has_key("itemObjectId") then
										--the item has an object that represents it when it appears on the character.
										--we need to create a duplicate of this item.
										local asset = assets:GetObjectNode(newItem.itemObjectId)
										if asset ~= nil then
											newItem.itemObjectId = asset:Duplicate()
										end
									end

									if newItem:has_key("consumable") and newItem.consumable:has_key("consumables") then
										--remap any consumable this item has to consume the new type, not the old type.
										newItem.consumable.consumables[item.id] = nil
										newItem.consumable.consumables[newItem.id] = 1
									end
									dmhub.SetAndUploadTableItem("tbl_Gear", newItem)
									slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')
								end,
							},
							{
								text = 'Delete Item',
								click = function()
									element.popup = nil
									item.hidden = true
									dmhub.SetAndUploadTableItem('tbl_Gear', item)
									slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')
								end,
							},
						}
					}

				elseif (not options.basicInventory) and ((not options.tradeInventory) or token ~= nil and token.type == 'party') and item ~= nil and (not adding) and token ~= nil then

					local unpackPack = nil
					if EquipmentCategory.IsPack(item) then
						unpackPack = {
							text = "Unpack",
							click = function()
								element.popup = nil

								token:BeginChanges()
								token.properties:SetItemQuantity(item.id, token.properties:GetItemQuantity(item.id)-1)
								for i,entry in ipairs(item:try_get("packItems", {})) do
									token.properties:GiveItem(entry.itemid, entry.quantity)
								end

								token:CompleteChanges(string.format(tr('Unpack %s'), item.name))
							end,
						}
					end

					local contextMenuItems = {
						unpackPack,
						{
							text = 'Share to Chat',
							click = function()
								element.popup = nil
								chat.ShareObjectInfo("tbl_Gear", item.id)
							end,
						},
					}


					local sendToPages = {}
					local sendToItems = {}
					if not options.isobject then

						if parentDialog.data.GetFreeSlotsInPages ~= nil then
							local freeSlots = parentDialog.data.GetFreeSlotsInPages()
							for _,slot in ipairs(freeSlots) do
								if slot.npage ~= parentDialog.data.CurrentPage() then
									sendToPages[#sendToPages+1] = {
										text = string.format("Page %d%s", math.tointeger(slot.npage), cond(slot.newPage, " (New Page)", "")),
										click = function()
											element.popup = nil

											if item.id ~= nil then
												token:BeginChanges()
												token.properties:RearrangeInventory(item.id, slotPanel.data.inventoryIndex, slot.slot)
												token:CompleteChanges("Rearrange inventory")
												parentDialog:FireEventTree('refreshInventory')
											end
										end,
									}
								end
							end
						end

						local items = {}

						if token.partyid ~= nil and token.type ~= 'party' then
							items[#items+1] = {
								token = dmhub.GetPartyInfo(token.partyid),
								name = "Party Stash",
							}
						end

						for i,otherToken in pairs(dmhud.tokenInfo.tokens) do
							if otherToken.playerControlled and otherToken.id ~= token.id and otherToken.properties ~= nil then
								items[#items+1] = {
									token = otherToken,
									name = otherToken.name,
								}
							end
						end

						for i,entry in pairs(items) do
							local otherToken = entry.token
							sendToItems[#sendToItems+1] = {
								text = entry.name,
								click = function()

									element.popup = nil
									local GiveItem = function(quantity)
										if otherToken.valid then
											otherToken:BeginChanges()
											otherToken.properties:GiveItem(item.id, quantity)
											otherToken:CompleteChanges('Receive item')

											token:BeginChanges()
											token.properties:GiveItem(item.id, -quantity, slotPanel.data.inventoryDialog.data.GetDefaultSlotForItem(item.id))
											token:CompleteChanges('Give item')

											slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')
										end
									end


									local quantity = token.properties.inventory[item.id].quantity
									if quantity == 1 then
										dmhub.Debug('GIVE ITEM')
										GiveItem(1)
									elseif quantity > 1 then
										element.popup = QuantityPopup{
											value = quantity,
											maxValue = quantity,
											confirm = function(numItems)
												element.popup = nil
												GiveItem(numItems)
											end,
											cancel = function()
												element.popup = nil
											end,
										}
									end
								end,
							}
						end

					end

					if #sendToItems > 0 then
						contextMenuItems[#contextMenuItems+1] =
							{
								text = 'Give To',
								submenu = sendToItems
							}
					end

					if #sendToPages > 0 then
						contextMenuItems[#contextMenuItems+1] =
							{
								text = 'Move To Page',
								submenu = sendToPages
							}
					end

					local quantity = token.properties:QuantityInSlot(item.id, slotPanel.data.inventoryIndex)
					local totalQuantity = token.properties:GetItemQuantity(item.id)

					if totalQuantity > quantity and (not item.unique) then
						contextMenuItems[#contextMenuItems+1] =
						{
							text = "Merge Stack",
							click = function()
								element.popup = nil

								token:BeginChanges()
								token.properties:MergeInventoryStack(item.id, slotPanel.data.inventoryIndex)
								token:CompleteChanges('Merge Inventory Stack')

								slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')
							end,
						}
					end

					if quantity >= 1 and not item.unique then

						contextMenuItems[#contextMenuItems+1] =
						{
							text = "Split Stack",
							click = function()
								element.popup = QuantityPopup{
									value = math.floor(quantity/2),
									maxValue = quantity-1,
									confirm = function(numItems)
										element.popup = nil

										local targetSlot = parentDialog.data.GetFirstFreeSlotAfter(slotPanel.data.inventoryIndex)

										token:BeginChanges()
										token.properties:SplitInventory(item.id, slotPanel.data.inventoryIndex, targetSlot, numItems)
										token:CompleteChanges('Split Inventory Stack')

										slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')
									end,
									cancel = function()
										element.popup = nil
									end,
								}
							end,
						}

						if not item:try_get("hidden") then
							contextMenuItems[#contextMenuItems+1] =
								{
									text = 'Make Unique',
									click = function()
										element.popup = nil

										local itemCopy = dmhub.DeepCopy(item)
										if not string.starts_with(item.name, "Unique") then
											itemCopy.name = string.format("Unique %s", item.name)
										end

										itemCopy.id = dmhub.GenerateGuid()
										itemCopy.baseid = item.id

										if itemCopy:has_key("itemObjectId") then
											--the item has an object that represents it when it appears on the character.
											--we need to create a duplicate of this item.
											local asset = assets:GetObjectNode(itemCopy.itemObjectId)
											if asset ~= nil then
												itemCopy.itemObjectId = asset:Duplicate()
											end
										end

										if itemCopy:has_key("consumable") and itemCopy.consumable:has_key("consumables") then
											--remap any consumable this item has to consume the new type, not the old type.
											itemCopy.consumable.consumables[item.id] = nil
											itemCopy.consumable.consumables[itemCopy.id] = 1
										end

										if not itemCopy:IsAmmoForWeapon() then
											itemCopy.unique = true
										end

										itemCopy.hidden = true
										dmhub.SetAndUploadTableItem('tbl_Gear', itemCopy)

										local quantity = token.properties:GetItemQuantity(item.id)

										token:BeginChanges()
										token.properties:SetItemQuantity(item.id, quantity-1, slotPanel.data.inventoryIndex)
										token.properties:SetItemQuantity(itemCopy.id, 1, cond(quantity <= 1, slotPanel.data.inventoryIndex))
										token:CompleteChanges('Make Unique Item')

										slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')

									end,
								}
						end
						
					end

					if item.unique or item:try_get("hidden") then

						contextMenuItems[#contextMenuItems+1] =
							{
								text = 'Edit Item',
								click = function()
									element.popup = nil
									dmhud.createItemDialog.data.show(parentDialog, item)
								end,
							}

						contextMenuItems[#contextMenuItems+1] =
							{
								text = 'Duplicate Item',
								click = function()
									element.popup = nil
									local itemCopy = dmhub.DeepCopy(item)
									itemCopy.id = dmhub.GenerateGuid()

									if itemCopy:has_key("itemObjectId") then
										--the item has an object that represents it when it appears on the character.
										--we need to create a duplicate of this item.
										local asset = assets:GetObjectNode(itemCopy.itemObjectId)
										if asset ~= nil then
											itemCopy.itemObjectId = asset:Duplicate()
										end
									end

									if itemCopy:has_key("consumable") and itemCopy.consumable:has_key("consumables") then
										--remap any consumable this item has to consume the new type, not the old type.
										itemCopy.consumable.consumables[item.id] = nil
										itemCopy.consumable.consumables[itemCopy.id] = 1
									end


									dmhub.SetAndUploadTableItem('tbl_Gear', itemCopy)

									token:BeginChanges()
									token.properties:SetItemQuantity(itemCopy.id, 1, parentDialog.data.GetFirstFreeSlotAfter(slotPanel.data.inventoryIndex))
									token:CompleteChanges('Make Unique Item')
								end,
							}

					end

					if not item.unique then

						contextMenuItems[#contextMenuItems+1] =
							{
								text = 'Set Quantity',
								click = function()
									element.popup = nil
									quantityLabel:SetClass('invisible', false)
									quantityLabel:BeginEditing()
								end,
							}

					else
						contextMenuItems[#contextMenuItems+1] =
							{
								text = 'Add to Compendium',
								click = function()
									element.popup = nil
									item.unique = nil
									item.hidden = nil
									local itemid = dmhub.SetAndUploadTableItem('tbl_Gear', item)

                                    local basicInventoryDialog = GetBasicInventoryDialog(element) or dmhud.basicInventoryDialog
									basicInventoryDialog:FireEventTreeVisible("newItem", itemid)
								end,
							}
					end

					if not token.properties.isLoot then
						contextMenuItems[#contextMenuItems+1] =
						{
							text = 'Drop Item',
							click = function()
								element.popup = nil

								local gearTable = dmhub.GetTable('tbl_Gear')
								local itemInfo = gearTable[item.id]
								local quantity = token.properties:QuantityInSlot(item.id, slotPanel.data.inventoryIndex)

								token:BeginChanges()
								token.properties:SetItemQuantity(item.id, token.properties:GetItemQuantity(item.id) - quantity, slotPanel.data.inventoryIndex)
								token:CompleteChanges('Drop Item')

								local floor = game.GetFloor(token.floorid)
								if floor ~= nil and itemInfo ~= nil then
									--make an instance of the object which is lootable on the map.
									floor:CreateObject{
										asset = {
											description = "Item",
											imageId = dmhub.GetRawImageId(itemInfo.iconid),
											hidden = false,
										},
										components = {
											CORE = {
												["@class"] = "ObjectComponentCore",
												hasShadow = false,
												height = 1,
												pivot_x = 0.5,
												pivot_y = 0.5,
												rotation = 0,
												scale = 0.4,
												sprite_invisible_to_players = false,
											},

											LOOT = {
												["@class"] = "ObjectComponentLoot",
												destroyOnEmpty = true,
												instantLoot = true,
												locked = false,
												properties = {
													__typeName = "loot",
													inventory = {
														[item.id] = {
															quantity = quantity,
														},
													},
												},
											},

											MOVEABLE = {
												["@class"] = "ObjectComponentMoveable",
											},
										},
										assetid = "none",
										inactive = false,
										pos = {
											x = token.loc.x + 0.5,
											y = token.loc.y - 0.5,
										},

										zorder = 1,
									}
								end


								slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')
							end,
						}
					end

					contextMenuItems[#contextMenuItems+1] =
						{
							text = 'Destroy Item',
							click = function()
								element.popup = nil

								local quantity = token.properties:QuantityInSlot(item.id, slotPanel.data.inventoryIndex)

								token:BeginChanges()
								token.properties:SetItemQuantity(item.id, token.properties:GetItemQuantity(item.id) - quantity, slotPanel.data.inventoryIndex)
								token:CompleteChanges('Destroy Item')

								slotPanel.data.inventoryDialog:FireEventTree('refreshInventory')

							end,
						}

					element.popup = gui.ContextMenu {
						entries = contextMenuItems,
					}

				end
			end,

		},

		data = {
			inventoryIndex = -1,

			GetGuid = function()
				return guid
			end,

			FlashNew = function()
				iconPanel:PulseClass('new')
			end,

			singleInventorySlot = true,

			GetItem = function()
				return item
			end,

			GetQuantity = function()
				return m_quantityNum
			end,

			GetToken = function()
				return token
			end,

			SetSlot = function(info, tok, dialog)
				parentDialog = dialog
				token = tok
				slotPanel:SetClass('adding', false)
				slotPanel:SetClass('accessParty', false)

				if info == nil then
					iconPanel.draggable = false
					quantityLabel:SetClass('invisible', true)
					iconPanel:SetClass('hidden', true)
					pricePanel:SetClass("hidden", true)
					iconEffectPanel:SetClass('hidden', true)
					item = nil
					SetRarity(nil)
				else
					if info.item == nil then
						dmhub.Debug(string.format("UNKNOWN ITEM: %s", info.id))
					end

					item = info.item

					quantityLabel:FireEvent("quantity", info.entry.quantity)

					iconPanel:SetClass('hidden', false)
					iconPanel.draggable = true
					iconPanel.bgimage = info.item:GetIcon()
					SetRarity(info.item:try_get("rarity"))

					--set up the icon effect.
					local iconEffectId = info.item:try_get('iconEffect')
					local iconEffect = nil
					if iconEffectId then
						iconEffect = ItemEffects[iconEffectId]
					end

					iconEffectPanel:SetClass('hidden', iconEffect == nil)
					if iconEffect ~= nil then
						iconEffectPanel.bgimage = iconEffect.video
						iconEffectPanel.selfStyle.opacity = iconEffect.opacity or 1
						iconEffectPanel.bgimageMask = cond(iconEffect.mask, info.item:GetIcon())
					end


					if dialog.data.options.isshop then
						--TODO: Work out how to break down prices into copper/silver/etc.
						pricePanel:SetClass("hidden", false)

						local priceMap = token.properties:GetItemPrice(item.id)

						local currencyTable = dmhub.GetTable(Currency.tableName) or {}
						local standard = nil
						local count = 0
						local currencyidVal
						local amountVal = 0
						local iconid = nil
						for currencyid,amount in pairs(priceMap) do
							if amount > 0 then
								currencyidVal = currencyid
								amountVal = amount

								count = count+1

								local currencyInfo = currencyTable[currencyid]
								standard = currencyInfo.standard
								iconid = currencyInfo.iconid
							end
						end

						if count == 1 then
							priceLabel.text = string.format("%d", amountVal)
							priceDisplayCurrency = currencyidVal
							priceIcon.bgimage = iconid

						elseif standard ~= nil then
							priceLabel.text = string.format("%d", round(Currency.CalculatePriceInStandard(tok.properties:GetItemPrice(item.id), standard)))
							priceDisplayCurrency = standard
							--priceIcon.bgimage = dialog.data.currencyStandard.iconid
							priceIcon.bgimage = currencyTable[standard].iconid

						end
					else
						pricePanel:SetClass("hidden", true)
					end
				end
				testVisibilityFunction = nil
				adding = false
				addingFunction = nil
				addingTooltip = nil
				accessParty = false
			end,
			SetAdd = function(fromParty, tok, options)
				SetRarity(nil)
				options = options or {}
				addingFunction = options.click
				addingTooltip = options.tooltip
				iconPanel.draggable = false
				slotPanel:SetClass('adding', cond(fromParty, false, true))
				slotPanel:SetClass('accessParty', cond(fromParty, true, false))
				iconPanel:SetClass('hidden', false)
				pricePanel:SetClass("hidden", true)
				iconEffectPanel:SetClass('hidden', true)
				quantityLabel:SetClass('invisible', true)
				iconPanel.bgimage = options.icon or cond(fromParty, 'icons/icon_app/icon_app_18.png', 'ui-icons/Plus.png')
				slotPanel.bgimage = 'panels/ButtonForegroundRed.png'
				testVisibilityFunction = options.testVisible
				item = nil
				adding = cond(fromParty, false, true)
				accessParty = cond(fromParty, true, false)
				token = tok
			end,
		},
	}

	return slotPanel
end

function GameHud.LootAll(token, tokenTradingWith, inventoryDialog)
	token:BeginChanges()
	tokenTradingWith:BeginChanges()

	local itemKeys = {}

	local gearTable = dmhub.GetTable('tbl_Gear')
	for k,item in pairs(token.properties:try_get("inventory", {})) do
		if gearTable[k] ~= nil then
			tokenTradingWith.properties:GiveItem(k, item.quantity)
			itemKeys[#itemKeys+1] = k

			if inventoryDialog ~= nil then
				inventoryDialog.data.SetItemNew(k)
			end
		end
	end

	for i,k in ipairs(itemKeys) do
		token.properties:SetItemQuantity(k, 0)
	end

	--currency.
	for currencyid,_ in pairs(token.properties:try_get("currency", {})) do
		tokenTradingWith.properties:SetCurrency(currencyid, tokenTradingWith.properties:GetCurrency(currencyid) + token.properties:GetCurrency(currencyid))
		token.properties:SetCurrency(currencyid, 0)
	end

	token:CompleteChanges('Loot Item')
	tokenTradingWith:CompleteChanges('Loot Item')
end

function GameHud.CreateInventoryDialog(self, options)

	local NumRows = options.numRows or 6
	local NumCols = options.numCols or 4

	local dialogWidth = options.dialogWidth or 350
	local dialogHeight = options.dialogHeight or 680

	options = options or {}
	local permanentOptions = options

	local _opened = false

	--the main token that is trading with us.
	local tokenTradingWith = nil

	local inventoryDialogTitle = options.title

	local equipmentPanel = nil
	local currencyPanel = nil
	local currencyAddPanel = nil

	local encumbrancePanel = nil
	local discountPanel = nil

	local search = ''

	local basicInventory = options.basicInventory
	local tradeInventory = options.tradeInventory
	local playerInventory = (not options.basicInventory) and (not options.tradeInventory)

	local categoryMatches = {
		All = {Weapon = true, Armor = true, Shield = true, Gear = true, Consumable = true, Item = true},
		Weapon = {Weapon = true},
		Armor = {Armor = true, Shield = true},
		Gear = {Gear = true},
		Consumable = {Consumable = true},
		Item = {Item = true},
	}

    local equipmentCategories = {
        {
            id = "all",
            text = "All",
        },
        {
            id = EquipmentCategory.LightSourceId,
            text = "Light Sources",
        },
        {
            id = EquipmentCategory.ConsumableId,
            text = "Consumables",
        },
        {
            id = EquipmentCategory.TrinketId,
            text = "Trinkets",
        },
        {
            id = EquipmentCategory.LeveledTreasureId,
            text = "Leveled Treasures",
        },
    }
	local catIndex = 1

	local newItems = {}

	local npage = 1

	local token = nil
	local inventory = nil
	local sortedInventory = nil
	local focusItem = nil
	local gearTable = nil
	
	local resultPanel = nil

	local itemsPerPage = NumRows*NumCols

	local hasAddItem = playerInventory

	local addItemSlot = nil
	local partyItemsSlot = nil
	local generateShopSlot = nil
	local refreshShopSlot = nil
	local addItemsPanel = nil


	if hasAddItem then
		if dmhub.isDM then
			--generateShopSlot = CreateInventorySlot(self, options)
			refreshShopSlot = CreateInventorySlot(self, options)
		end

		partyItemsSlot = CreateInventorySlot(self, options)
		addItemSlot = CreateInventorySlot(self, options)
		addItemsPanel = gui.Panel{
			id = "addItemsPanel",
			halign = "right",
			valign = "top",
			width = "auto",
			height = "auto",
			hpad = 6,
			gui.Panel{
				width = "auto",
				height = "auto",
				uiscale = 0.7,
				flow = "horizontal",
				refreshShopSlot,
				generateShopSlot,
				partyItemsSlot,
				addItemSlot,
			}
		}
	end

	local displayedItems = {}
	local NumPages = function()
		local numItems = #displayedItems
		if numItems < 1 then
			numItems = 1
		end
		return math.ceil(numItems / itemsPerPage)
	end

	local slots = {}
	while #slots < NumRows*NumCols do
		slots[#slots+1] = CreateInventorySlot(self, options)
	end


	local GetFreeSlotsInPages = function()
		displayedItems[#displayedItems+1] = false --make sure there's an open slot on the last page.
		local result = {}
		local pagesFound = {}
		for slotIndex,slotInfo in ipairs(displayedItems) do
			if slotInfo == false then
				local npage = math.ceil(slotIndex/itemsPerPage)
				if pagesFound[npage] == nil then
					pagesFound[npage] = true

					result[#result+1] = {
						npage = npage,
						slot = slotIndex,
					}
				end
			end
		end
		displayedItems[#displayedItems] = nil

		--the next page.
		if not pagesFound[NumPages()+1] then
			result[#result+1] = {
				npage = NumPages()+1,
				slot = NumPages()*itemsPerPage + 1,
				newPage = true,
			}
		end

		return result
	end

	local ShowInventory = function(items)
		printf("Show Inventory")
		displayedItems = items
		if npage > NumPages() then
			npage = NumPages()
		end
		for i,slot in ipairs(slots) do
			local inventoryIndex = (npage-1)*itemsPerPage + i
			local item = items[inventoryIndex]
			if item == false then
				item = nil
			end

			slot.data.inventoryIndex = inventoryIndex
			slot.data.SetSlot(item, token, resultPanel)

			if item ~= nil and newItems[item.id] then
				slot.data.FlashNew()
			end
		end

		newItems = {}

		if addItemSlot ~= nil then
			addItemSlot.data.SetAdd()
		end

		if refreshShopSlot ~= nil and token ~= nil then
			refreshShopSlot.data.SetAdd(false, nil, {
				testVisible = function()
					return token ~= nil and token.properties:has_key("lootTable")
				end,
				click = function()
					token:BeginChanges()

					token.properties:RollLoot{
						clear = true,
						newItems = newItems,
					}

					token:CompleteChanges('Generate loot')
					resultPanel:FireEventTree('refreshInventory')
				end,

				tooltip = function()
					if token ~= nil and token.properties:has_key("lootTable") then
						local dataTable = dmhub.GetTableVisible("lootTables")

						local lootTable = dataTable[token.properties.lootTable.key]
						if lootTable ~= nil then
							return string.format("Re-roll Loot: %s", lootTable:Describe(token.properties.lootTable.choiceIndex))
						end
					end

					return "Regenerate Loot"
				end,
				icon = "panels/hud/clockwise-rotation.png",
			})
		end

		if generateShopSlot ~= nil and token ~= nil then
			generateShopSlot.data.SetAdd(false, nil, {
				click = function()
					local clearInventoryCheck
					clearInventoryCheck = {
						text = "Clear existing inventory",
						value = dmhub.GetSettingValue("inventory:generationclears"),
						change = function(val)
							dmhub.SetSettingValue("inventory:generationclears", val)
						end,
					}
					ShowRollableTableSelectionDialog{
						root = resultPanel.root,
						tableName = "lootTables",
						checkboxes = {
							clearInventoryCheck,
						},

						--items is a list of {key -> val, choiceIndex -> val}. There will be at least one
						--item and here we only use one.
						click = function(element, items)
					printf("CLEAR:: CHECK = %s", json(clearInventoryCheck))
							local dataTable = dmhub.GetTableVisible("lootTables")
							token:BeginChanges()

							token.properties:RollLoot{
								lootTable = items[1],
								clear = dmhub.GetSettingValue("inventory:generationclears"),
								newItems = newItems,
							}

							token:CompleteChanges('Generate loot')
							resultPanel:FireEventTree('refreshInventory')
						end,
					}
				end,
				tooltip = "Generate Inventory from Table",
				icon = "ui-icons/d20.png",
			})
		end

		if partyItemsSlot ~= nil then
			if token == nil or token.partyid == nil then
				partyItemsSlot:SetClass("collapsed", true)
			else
				partyItemsSlot:SetClass("collapsed", false)
				partyItemsSlot.data.SetAdd(true, token)
			end
		end
	end

	local AddItem = function(item, quantity, options)
		local currencyChanges = options.currencyChanges
		if token ~= nil then
			if item:MustBeUniqueInInventory() then
				local itemCopy = dmhub.DeepCopy(item)
				itemCopy.id = dmhub.GenerateGuid()
				itemCopy.baseid = item.id
				itemCopy.hidden = true

				if itemCopy:has_key("consumable") and itemCopy.consumable:has_key("consumables") then
					--remap any consumable this item has to consume the new type, not the old type.
					itemCopy.consumable.consumables[item.id] = nil
					itemCopy.consumable.consumables[itemCopy.id] = 1
				end

				dmhub.SetAndUploadTableItem('tbl_Gear', itemCopy)

				item = itemCopy
			end


			token:BeginChanges()
			token.properties:GiveItem(item.id, quantity, resultPanel.data.GetDefaultSlotForItem(item.id))

			if currencyChanges ~= nil then
				for currencyid,amount in pairs(currencyChanges) do
					token.properties:SetCurrency(currencyid, token.properties:GetCurrency(currencyid) - amount)
				end
			end

			token:CompleteChanges('Add item to inventory')
			newItems[item.id] = true
			resultPanel:FireEventTree('refreshInventory')
		end
	end

	local slotsContainer = gui.Panel{

		styles = {
			{
				flow = 'horizontal',
				wrap = true,
				width = '100%',
				height = '100%',
			},
		},

		children = {
			slots,
		},

		events = {
			newItem = function(element, itemid)
				focusItem = itemid
				resultPanel:FireEventTree('refreshInventory')
			end,
			refreshInventory = function(element)
				if not _opened then
					return
				end

				local unarrangedInventory = inventory
				local arrangedInventory = {}
				if not basicInventory then
					--refresh the inventory from the token.
					token.properties:SanitizeInventory()
					inventory = token.properties.inventory

					--divide into unarranged inventory and the inventory that has been manually arranged.
					--iterate over the unarranged inventory and extract out arranged parts.
					unarrangedInventory = dmhub.DeepCopy(inventory)
					for k,entry in pairs(inventory) do
						if entry.slots ~= nil then
							local mutableEntry = unarrangedInventory[k]
							for _,slotEntry in ipairs(entry.slots) do
								if slotEntry.slot > 0 then
									local quantity = slotEntry.quantity
									if quantity == nil then
										quantity = token.properties:UnslottedQuantity(k)
									end

									arrangedInventory[#arrangedInventory+1] = {
										id = k,
										slot = slotEntry.slot,
										entry = {
											quantity = quantity,
										},
										item = gearTable[k],
									}
									if slotEntry.quantity == nil or slotEntry.quantity >= mutableEntry.quantity then
										unarrangedInventory[k] = nil
									else
										mutableEntry.quantity = mutableEntry.quantity - slotEntry.quantity
									end
								end
							end
						end
					end

					table.sort(arrangedInventory, function(a,b)
						return a.slot < b.slot
					end)
				end


				sortedInventory = {}

                local categoryInfo = equipmentCategories[catIndex]
				for k,entry in pairs(unarrangedInventory) do
					if gearTable[k] ~= nil and (categoryInfo.id == "all" or gearTable[k]:try_get("equipmentCategory") == categoryInfo.id) then
						sortedInventory[#sortedInventory+1] = {
							id = k,
							entry = entry,
							item = gearTable[k],
						}
					end
				end

				if basicInventory then
					table.sort(sortedInventory, function(a,b) return a.item.name < b.item.name end)
				end

				--merge unarranged and arranged inventory together.
				if #arrangedInventory > 0 then
					local sorted = sortedInventory
					sortedInventory = {}
					local i = 1
					for _,item in ipairs(sorted) do
						while i <= #arrangedInventory and arrangedInventory[i].slot <= #sortedInventory+1 do
							sortedInventory[#sortedInventory+1] = arrangedInventory[i]
							i = i+1
						end
						
						sortedInventory[#sortedInventory+1] = item
					end

					while i <= #arrangedInventory do
						while #sortedInventory+1 < arrangedInventory[i].slot do
							sortedInventory[#sortedInventory+1] = false
						end

						sortedInventory[#sortedInventory+1] = arrangedInventory[i]
						i = i+1
					end
				end

				if focusItem ~= nil then
					for i,item in ipairs(sortedInventory) do
						if focusItem ~= nil and item.id == focusItem then
							local newPage = math.ceil(i / itemsPerPage)
							newItems[item.id] = true
							focusItem = nil

							if newPage ~= npage then
								npage = math.ceil(i / itemsPerPage)

								--Fire the event again with the correct page set now.
								resultPanel:FireEventTree('refreshInventory')
								return
							end
						end
					end
				end

				ShowInventory(sortedInventory)
			end
		},

	}

	local dragTarget = nil
	
	if not basicInventory then
		dragTarget = gui.Panel{
			bgimage = true,
            bgcolor = "clear",
			dragTarget = true,
			interactable = false,

			styles = {
				{
					width = '100%',
					height = '100%',
				},

				{
					selectors = 'drag-target',
                    borderWidth = 2,
                    borderColor = "#FFFFFF88",
				},
				{
					selectors = 'drag-target-hover',
                    borderWidth = 2,
                    borderColor = "#FFFFFFFF",
				},

			},

			data = {
				AddItem = AddItem,
				inventoryDragTarget = not basicInventory,
				GetToken = function()
					return token
				end,

				CannotAfford = function()
					if currencyPanel ~= nil then
						currencyPanel:FireEventTree("cannotAfford")
					end
				end,
			},
		}
	end

	local containerAndDragTarget = gui.Panel{
		style = {
			width = NumCols*SlotDim,
			height = NumRows*SlotDim,
			flow = 'none',
		},
		children = {
			slotsContainer,
			dragTarget,
		}
	}


	local searchInput = nil

	local searchInputElement = nil

	if basicInventory then

		searchInput = gui.Panel{
			style = {
				width = '80%',
				fontSize = '30%',
				height = 20,
				halign = 'center',
				valign = 'top',
				bgcolor = 'black',
				color = 'white',
				vmargin = 0,
			},
			children = {
				gui.Input{
					id = 'search-input',
					placeholderText = 'Search...',
					selfStyle = {
						borderWidth = 1,
						bgcolor = 'black',
						height = 14,
					},
					editlag = 0.25,
					events = {
						edit = function(element)
							npage = 1
							search = element.text
							resultPanel:FireEventTree('refreshInventory')
						end,
						change = function(element)
							if search ~= element.text then
								npage = 1
								search = element.text
								resultPanel:FireEventTree('refreshInventory')
							end
						end,
					},
				},

			}
		}

		searchInputElement = searchInput.children[1]
	end

	local categoryPaging = nil
	
	if basicInventory then

		categoryPaging = gui.Panel{
			id = 'category-paging-panel',
			styles = {
				{
					width = '100%',
					height = 32,
					flow = 'horizontal',
				},
				{
					selectors = {'hover', 'paging-arrow'},
					brightness = 2,
				},
				{
					selectors = {'press', 'paging-arrow'},
					brightness = 0.7,
				},
			},

			children = {
				gui.Panel{
					bgimage = 'panels/InventoryArrow.png',
					className = 'paging-arrow',
					style = {
						height = '100%',
						width = '50% height',
						halign = 'left',
						hmargin = 40,
					},

					events = {
						refreshInventory = function(element)
						end,

						click = function(element)
							catIndex = catIndex - 1
							npage = 1
							if catIndex < 1 then
								catIndex = #equipmentCategories
							end
							resultPanel:FireEventTree('refreshInventory')
						end,
					},

				},

				gui.Label{
					style = {
						fontSize = '35%',
						color = 'white',
						width = 'auto',
						height = 'auto',
						halign = 'center',
					},
					events = {
						refreshInventory = function(element)
							if not _opened then
								return
							end
							element.text = equipmentCategories[catIndex].text
						end,
					}
				},

				gui.Panel{
					bgimage = 'panels/InventoryArrow.png',
					className = 'paging-arrow',
					style = {
						scale = {x = -1, y = 1},
						height = '100%',
						width = '50% height',
						halign = 'right',
						hmargin = 40,
					},

					events = {
						refreshInventory = function(element)
						end,

						click = function(element)
							catIndex = catIndex + 1
							npage = 1
							if catIndex > #equipmentCategories then
								catIndex = 1
							end
							resultPanel:FireEventTree('refreshInventory')
						end,
					},
				},

			},
		}

	end

	local newItemButton = nil
	
	if basicInventory then
		newItemButton = gui.AddButton{
			id = 'create-item-inventory-button',
			width = 32,
			height = 32,
			halign = 'right',
			valign = 'bottom',
			events = {
				hover = gui.Tooltip('Add New Item'),
				click = function(element)
					self.createItemDialog.data.show(resultPanel)
				end,
			},
		}
	end


	if options.currency then


		local CreateCurrencyIcon = function(id, iconid)

			return gui.Panel{
				bgimage = iconid,
				styles = {
					{
						height = '100%',
						width = '100% height',
						bgcolor = "white",
					},
					{
						selectors = {"cannotAfford"},
						bgcolor = "#880000",
					},

				},

				rightClick = function(element)

					if (not options.basicInventory) and ((not options.tradeInventory) or token ~= nil and token.type == 'party') and token ~= nil then

						local items = {}

						if token.partyid ~= nil and token.type ~= 'party' then
							items[#items+1] = {
								token = dmhub.GetPartyInfo(token.partyid),
								name = "Party Stash",
							}
						end

						for i,otherToken in pairs(self.tokenInfo.tokens) do
							if otherToken.playerControlled and otherToken.id ~= token.id and otherToken.properties ~= nil then
								items[#items+1] = {
									token = otherToken,
									name = otherToken.name,
								}
							end
						end

						local sendToItems = {}
						for i,entry in pairs(items) do
							local otherToken = entry.token
							sendToItems[#sendToItems+1] = {
								text = entry.name,
								click = function()

									element.popup = nil
									local GiveItem = function(quantity)
										if otherToken.valid then
											otherToken:BeginChanges()
											otherToken.properties:SetCurrency(id, otherToken.properties:GetCurrency(id) + quantity, string.format(tr("Given by %s"), token.name or tr("Unknown")))
											otherToken:CompleteChanges(tr('Receive currency'))

											token:BeginChanges()
											token.properties:SetCurrency(id, token.properties:GetCurrency(id) - quantity, string.format(tr("Transferred to %s"), otherToken.name or tr("Unknown")))
											token:CompleteChanges(tr('Give currency'))

											resultPanel:FireEventTree('refreshInventory')
										end
									end


									local quantity = token.properties:GetCurrency(id)
									if quantity == 1 then
										dmhub.Debug('GIVE ITEM')
										GiveItem(1)
									elseif quantity > 1 then
										element.popup = QuantityPopup{
											value = quantity,
											maxValue = quantity,
											confirm = function(numItems)
												element.popup = nil
												GiveItem(numItems)
											end,
											cancel = function()
												element.popup = nil
											end,
										}
									end
								end,
							}
						end

						local contextMenuItems = {}
						contextMenuItems[#contextMenuItems+1] =
							{
								text = 'Give To',
								submenu = sendToItems
							}
						

						element.popup = gui.ContextMenu {
							entries = contextMenuItems,
						}
					end



				end,

				cannotAffordOn = function(element)
					element:SetClass("cannotAfford", true)
				end,

				cannotAffordOff = function(element)
					element:SetClass("cannotAfford", false)
				end,

				cannotAfford = function(element)
					element:FireEvent("cannotAffordOn")
					element:ScheduleEvent("cannotAffordOff", 0.1)
					element:ScheduleEvent("cannotAffordOn", 0.2)
					element:ScheduleEvent("cannotAffordOff", 0.3)
					element:ScheduleEvent("cannotAffordOn", 0.4)
					element:ScheduleEvent("cannotAffordOff", 0.5)
				end,

				linger = function(element)
					local currencyTable = dmhub.GetTable(Currency.tableName) or {}
					local currency = currencyTable[id]
					if currency == nil then
						return
					end

					local totalValue = 0
					for k,c in pairs(currencyTable) do
						if c.standard == currency.standard and (not c.hidden) then
							totalValue = totalValue + c:UnitValue()*token.properties:GetCurrency(k)
						end
					end
					local text = currency.name
					if currency.details ~= '' then
						text = string.format("%s: %s", text, currency.details)
					end

					local standardCurrency = currencyTable[currency.standard]
					if currency:UnitValue() ~= 1 and token.properties:GetCurrency(id) ~= 0 and standardCurrency ~= nil then
						text = string.format("%s\n%s %s = %s %s", text, format_decimal(token.properties:GetCurrency(id)), currency.name, format_decimal(token.properties:GetCurrency(id)*currency:UnitValue()), standardCurrency.name)
					end

					if standardCurrency ~= nil then
						text = string.format("%s\nTotal = %s %s", text, format_decimal(totalValue), standardCurrency.name)
						
					end

					element.tooltip = gui.Tooltip(text)(element)
				end,
			}
		end

		local CreateCurrencyEntry = function(input)
			return gui.Panel{
				style = {
					height = '80%',
					width = "auto",
					valign = 'center',
					hmargin = 2,
				},

				children = {
					input,
				},
			}
		end

		local currencyMainPanel
		local currencyChildPanels = {}

		local currencyTable = dmhub.GetTable(Currency.tableName) or {}

		--mapping of currency id of standard -> list of currencies using this standard.
		local currencyStandards = Currency.MonetaryStandards()

		for k,standardEntry in pairs(currencyStandards) do
			local standardid = k

			local childItems = {}
			for i,currency in ipairs(standardEntry) do
				childItems[#childItems+1] = CreateCurrencyIcon(currency.id, currency.iconid)

				local currencyid = currency.id

				local input = gui.Label{
					minWidth = 30,
					width = 'auto',
					editable = true,
					text = '5',
					events = {
						change = function(element)
							local baseval = 0
							local mult = 1
							local val = element.text
							local note = nil
							if string.starts_with(val, "+") then
								baseval = token.properties:GetCurrency(currencyid)
								val = string.sub(val, 2)
								note = string.format("Added %s", val)
							elseif string.starts_with(val, "-") then
								val = string.sub(val, 2)
								baseval = token.properties:GetCurrency(currencyid)
								mult = -1
								note = string.format("Subtracted %s", val)
							end

							local num = tonumber(val)
							if num == nil then
								element.text = tostring(token.properties:GetCurrency(currencyid))
								return
							end

							num = baseval + num*mult

							--we are going negative, so re-normalize our currency.
							if num < 0 then

								local val = {}
								for i,currency in ipairs(standardEntry) do
									local quantity

									if currencyid == currency.id then
										quantity = num
									else
										quantity = token.properties:GetCurrency(currency.id)
									end

									val[currency.id] = quantity
								end

								local spend = Currency.CalculateSpend(nil, Currency.CalculatePriceInStandard(val, standardid), standardid, true)

								printf("SPEND:: %s", json(spend))

								local canAfford = true
								for k,v in pairs(spend) do
									if v < 0 then
										canAfford = false
									end
								end

								if canAfford then

									token:BeginChanges()
									for i,currency in ipairs(standardEntry) do
										local currencyid = currency.id
										token.properties:SetCurrency(currencyid, spend[currencyid] or 0)
									end
									token:CompleteChanges('Normalized currency')

								else
									currencyMainPanel:FireEventTree('cannotAfford')
									element.text = tostring(token.properties:GetCurrency(currencyid))
								end

							else
								element.text = tostring(num)
								token:BeginChanges()
								token.properties:SetCurrency(currencyid, num, note)
								token:CompleteChanges("Changed currency")
							end

						end,
						refreshInventory = function(element)
							if token == nil then
								dmhub.Debug(string.format("TOKEN IS NULL: %s", permanentOptions.title or "(no title)"))
								return
							end
							element.text = string.format("%d", toint(token.properties:GetCurrency(currencyid)))
						end,
					}
				}
				childItems[#childItems+1] = CreateCurrencyEntry(input)
			end

			childItems[#childItems+1] = gui.Panel{
				id = "normalizeInventoryButton",
				bgimage = "ui-icons/icon-rotate.png",
				width = 16,
				height = 16,
				valign = "center",

				styles = {
					{
						bgcolor = Styles.textColor,
					},
					{
						selectors = {"hover"},
						bgcolor = "white",
					}
				},


				press = function(element)
					local val = {}
					for i,currency in ipairs(standardEntry) do
						local currencyid = currency.id
						val[currencyid] = token.properties:GetCurrency(currencyid)
					end

					local spend = Currency.CalculateSpend(nil, Currency.CalculatePriceInStandard(val, standardid), standardid, true)

					token:BeginChanges()
					for i,currency in ipairs(standardEntry) do
						local currencyid = currency.id
						token.properties:SetCurrency(currencyid, spend[currencyid] or 0)
					end
					token:CompleteChanges('Normalized currency')

				end,
			}

			currencyMainPanel = gui.Panel{
				styles = {
					{
						flow = 'horizontal',
						height = 30,
						width = '80%',
						halign = 'left',
						valign = 'top',
					}
				},

				children = childItems,
			}

			currencyChildPanels[#currencyChildPanels+1] = currencyMainPanel
		end

		currencyPanel = gui.Panel{
			style = {
				width = '100%',
				height = 'auto',
				fontSize = '40%',
			},
			children = currencyChildPanels,
		}
	end

	if options.equipment and GameSystem.encumbrance then
		encumbrancePanel = gui.Panel{
			width = 160,
			height = 20,
			floating = true,
			halign = "right",
			valign = "bottom",
			flow = "horizontal",
			halign = "left",
			vmargin = 20,
			hmargin = 20,
			refreshInventory = function(element)
				element:SetClass("hidden", permanentOptions.isshop)
			end,

			hover = function(element)
				local capacity = token.properties:CarryingCapacity()
				local weight = round(token.properties:GetInventoryWeight()*100)*0.01
				local text = string.format("Weight: %s lbs.", tostring(weight))
				if capacity ~= nil then
					text = text .. string.format("\nCarrying Capacity: %s lbs.", tostring(capacity))
				end
				gui.Tooltip(text)(element)
			end,

			gui.Panel{
				bgimage = mod.images.weight,
				width = 20,
				height = 20,
				bgcolor = Styles.textColor,
				halign = "left",
			},

			gui.Label{
				height = "auto",
				width = "auto",
				fontSize = 16,
				halign = "left",
				hmargin = 4,
				color = Styles.textColor,
				text = "Encumbrance",
				refreshInventory = function(element)
					if permanentOptions.isshop then
						return
					end

					local capacity = token.properties:CarryingCapacity()
					local weight = token.properties:GetInventoryWeight()
					if capacity ~= nil then
						element.text = string.format("%s/%s", tostring(math.floor(weight)), tostring(capacity))
						if weight > capacity then
							element.selfStyle.color = "red"
						else
							element.selfStyle.color = Styles.textColor
						end
					else
						element.text = tostring(weight)
						element.selfStyle.color = Styles.textColor
					end
				end,
			},
		}

		if dmhub.isDM then
			discountPanel = gui.Panel{

				width = 160,
				height = 20,
				floating = true,
				halign = "right",
				valign = "bottom",
				flow = "horizontal",
				halign = "left",
				vmargin = 20,
				hmargin = 20,

				refreshInventory = function(element)
					element:SetClass("hidden", not permanentOptions.isshop)
				end,

				gui.Label{
					textAlignment = "right",
					width = 40,
					height = "100%",
					fontSize = 16,
					characterLimit = 4,
					halign = "left",
					editable = true,
					refreshInventory = function(element)
						if permanentOptions.isshop then
							element.text = tonumber(token.properties.discount)
						end
					end,

					change = function(element)
						local n = tonumber(element.text)
						if n ~= nil then
							n = round(n)
							token:BeginChanges()
							token.properties.discount = n
							token:CompleteChanges("Changed discount")
						end

						resultPanel:FireEventTree('refreshInventory')
					end,
				},
				gui.Label{
					width = "auto",
					height = "100%",
					fontSize = 16,
					halign = "left",
					text = "% Discount",

				},
			}
		end
	end

	if options.equipment then
		equipmentPanel = self:CreateEquipmentDialog(options)
	end

	local takeAllButton = nil
	local lootPanel = nil
	if tradeInventory then
		takeAllButton = gui.Button{
            text = "<<Take All",
            width = "auto",
            height = "auto",
            pad = 2,
            fontSize = 14,
			events = {
				refreshInventory = function(element)
					if not _opened then
						return
					end

					local totalCurrency = 0
					for k,_ in pairs(token.properties:try_get("currency", {})) do
						totalCurrency = totalCurrency + token.properties:GetCurrency(k)
					end
					element:SetClass('hidden', permanentOptions.isshop or ((token.properties.inventory == nil or next(token.properties.inventory) == nil) and totalCurrency == 0))
				end,
				click = function(element)
					if tokenTradingWith == nil then
						return
					end

					GameHud.LootAll(token, tokenTradingWith, self.inventoryDialog)

					resultPanel:FireEventTree('refreshInventory')
					self.inventoryDialog:FireEventTree('refreshInventory')

					takeAllButton:SetClass('hidden', true)

					if token.type == "component" and token.destroyOnEmpty then
						resultPanel.data.close()
						token:DestroyObject()
					end

				end,
			},
		}

		lootPanel = gui.Panel{
			floating = true,
			styles = {
				{
					halign = 'left',
					valign = 'top',
					width = 'auto',
					height = 'auto',
                    vmargin = 34,
					flow = 'vertical',
				}
			},
			children = {
				takeAllButton,

			}
		}
	end

	local slotBorder
	local inventoryTitleLabel
	if not options.charsheet then
		slotBorder = SlotBorder{}
		inventoryTitleLabel = gui.Label{
			id = 'inventory-title',
			text = '',
			style = {
				textAlignment = 'center',
				fontSize = '70%',
				vmargin = 4,
				width = '100%',
				height = 'auto',
				halign = 'center',
				valign = 'top',
				color = 'white',
				bold = true,
			},

			events = {
				refreshInventory = function(element)
					if not _opened then
						return
					end
					if inventoryDialogTitle or token.name then
						element.text = inventoryDialogTitle or string.format("%s's Inventory", token.description or token.name)
					else
						element.text = 'Inventory'
					end
				end,
			},

			children = {

				gui.CloseButton{
					halign = 'right',
					refreshInventory = function(element)
						if not _opened then
							return
						end
						element:SetClass('hidden', tradeInventory)
					end,
					click = function(element)
						resultPanel.data.close()
					end,
				},

			},
		}
	end



	resultPanel = gui.Panel{
		id = 'inventory-dialog',
		bgimage = cond(options.charsheet, nil, 'panels/InventorySlot_Background.png'),
        blurBackground = true,

		classes = {'hidden'},

		captureEscape = not options.charsheet,
		escapePriority = EscapePriority.EXIT_INVENTORY_DIALOG,

		styles = {
			{
				width = dialogWidth,
				height = dialogHeight,
				halign = 'center',
				valign = 'center',
				bgcolor = 'white',
				flow = 'none',
			},
			SlotStyles,
            g_InventoryStyles,
		},

		events = {
			escape = function(element)
				resultPanel.data.close()
			end,
			refreshInventory = function(element)
				if not _opened then
					return
				end
				if search == '' then
					gearTable = dmhub.GetTable('tbl_Gear')
				else
					gearTable = dmhub.SearchTable('tbl_Gear', search)

					--see if any item categories match and coalesce them.
					local matchingCategories = dmhub.SearchTable(EquipmentCategory.tableName, search)
					if matchingCategories ~= nil then
						local itemsTable = dmhub.GetTable('tbl_Gear')
						local categoriesToItems = EquipmentCategory.GetCategoriesToItems()
						for k,cat in pairs(matchingCategories) do
							local additionalItems = categoriesToItems[k]
							if additionalItems ~= nil then
								for _,itemkey in ipairs(additionalItems) do
									gearTable[itemkey] = itemsTable[itemkey]
								end
							end
						end
					end
				end
				if basicInventory then
					local itemsHiddenByDefault = dmhub.GetSettingValue("hideitems")
					local showTreasure = true
					inventory = {}
					for k,item in pairs(gearTable) do
						if (not item:has_key('hidden')) and (not item:has_key('uniqueItem')) and (dmhub.isDM or not item:try_get('hiddenFromPlayers', itemsHiddenByDefault)) and (showTreasure or (not EquipmentCategory.IsTreasure(item))) then
							inventory[k] = {
								quantity = 1,
							}
						end
					end

				end
			end,

			refreshGame = function(element)
				--the token we have been modifying has changed, so refresh us.
				element:FireEventTree('refreshInventory')
			end,

		},

		data = {
			options = {},

			GetFreeSlotsInPages = GetFreeSlotsInPages,

			CurrentPage = function()
				return npage
			end,

			GetFirstFreeSlotAfter = function(slotIndex)
				for i=slotIndex,#displayedItems do
					if displayedItems[i] == false then
						return math.max(1, i)
					end
				end
				return math.max(1, #displayedItems+1)
			end,

			GetDefaultSlotForItem = function(itemid)
				local defaultSlot = resultPanel.data.GetFirstFreeSlotAfter((npage-1)*itemsPerPage+1)
				return token.properties:GetDefaultInventorySlotForItem(itemid, defaultSlot)
			end,

			SetItemNew = function(itemid)
				newItems[itemid] = true
			end,

			isOpen = function()
				return not resultPanel:HasClass('hidden')
			end,
			
			toggleOpen = function(tok, options)
				if resultPanel.data.isOpen() then
					resultPanel.data.close()
				else
					resultPanel.data.open(tok, options)
				end
			end,

			open = function(tok, options)

				self.openInventoryDialogs[#self.openInventoryDialogs+1] = resultPanel

				for _,dialog in ipairs(self.openInventoryDialogs) do
					dialog:SetAsLastSibling()
				end

				_opened = true
				options = options or {}

				resultPanel.data.options = options

				tradeInventory = permanentOptions.tradeInventory and not options.partyinventory

				permanentOptions.isobject = options.isobject
				permanentOptions.isshop = options.isshop

				if options.isshop then
					--make the dialog know about which currencies are used. For now default to gold.
					local currencyStandard = Currency.GetMainCurrencyStandard()
					local currencyTable = dmhub.GetTable(Currency.tableName) or {}

					local currenciesAccepted = {}
					for k,currency in pairs(currencyTable) do
						if currency.standard == currencyStandard and (not currency.hidden) then
							currenciesAccepted[#currenciesAccepted+1] = currency
						end
					end

					resultPanel.data.currenciesAccepted = currenciesAccepted
					resultPanel.data.currencyStandard = currencyTable[currencyStandard]
				end

				tokenTradingWith = options.tradewith

				inventoryDialogTitle = options.title or inventoryDialogTitle

				npage = 1

				if currencyAddPanel ~= nil then
					currencyAddPanel:SetClass('collapsed', true)
				end

				if tok ~= nil and equipmentPanel ~= nil and not options.isobject then
					equipmentPanel.data.open(tok)
				elseif equipmentPanel ~= nil then
					equipmentPanel.data.close()
				end

				if basicInventory then

					--sets the dialog up to show basic inventory.
					token = nil

					searchInputElement.text = ''
					search = ''

					resultPanel.monitorGame = nil

				else

					--opens the dialog to show the inventory for a given token.
					if tok == nil or tok.properties == nil then
						dmhub.Debug('Token does not have a valid inventory')
						if tok == nil then
							dmhub.Debug('token is null!')
						end
						resultPanel:SetClass('hidden', true)
						resultPanel.monitorGame = nil
						return
					end

					if not tok.properties:has_key('inventory') then
						tok.properties.inventory = {}
					end

					tok.properties:SanitizeInventory()

					token = tok
					inventory = token.properties.inventory

					--make it so refreshGame will be fired when this token is changed, so if someone else changes
					--our inventory we can refresh.
					if token.type == "token" then
						resultPanel.monitorGame = string.format("/characters/%s", token.id)
					elseif token.type == "party" then
						resultPanel.monitorGame = string.format("/partyInfo/%s", token.id)
					end
				end

				if options.showBasic then
                    local basicInventoryDialog = GetBasicInventoryDialog(resultPanel) or self.basicInventoryDialog
                    local tradeInventoryDialog = GetTradeInventoryDialog(resultPanel) or self.tradeInventoryDialog

					tradeInventoryDialog.data.close()
					basicInventoryDialog.data.open()
				end

				resultPanel:SetClass('hidden', false)
				resultPanel:FireEventTree('refreshInventory')
			end,

			close = function()
				local removeIndexes = {}
				for i,dialog in ipairs(self.openInventoryDialogs) do
					if dialog == resultPanel then
						removeIndexes[#removeIndexes+1] = i
					end
				end

				for i=#removeIndexes,1,-1 do
					table.remove(self.openInventoryDialogs, removeIndexes[i])
				end


				resultPanel.monitorGame = nil
				_opened = false
				resultPanel:SetClass('hidden', true)
				if playerInventory then
					--make sure the basic inventory and trade dialogs are also closed.
                    local basicInventoryDialog = GetBasicInventoryDialog(resultPanel) or self.basicInventoryDialog
                    local tradeInventoryDialog = GetTradeInventoryDialog(resultPanel) or self.tradeInventoryDialog
					basicInventoryDialog.data.close()
					tradeInventoryDialog.data.close()
				end
			end,
		},


		children = {

			slotBorder,

			gui.Panel{
				id = 'inventory-main',
				style = {
					width = 300,
					height = dialogHeight-14,
					valign = 'center',
					flow = 'vertical',
				},

				children = {
					inventoryTitleLabel,

					currencyPanel,

					categoryPaging,
					searchInput,

					containerAndDragTarget,

					addItemsPanel,

					lootPanel,

					gui.Panel{
						id = 'paging-panel',
						styles = {
							{
								width = '100%',
								height = 32,
								flow = 'horizontal',
							},
							{
								selectors = {'hover', 'paging-arrow'},
								brightness = 2,
							},
							{
								selectors = {'press', 'paging-arrow'},
								brightness = 0.7,
							},
						},

						children = {
							gui.Panel{
								bgimage = 'panels/InventoryArrow.png',
								className = 'paging-arrow',
								style = {
									height = '100%',
									width = '50% height',
									halign = 'left',
									hmargin = 40,
								},

								events = {
									refreshInventory = function(element)
										if not _opened then
											return
										end
										element:SetClass('hidden', npage == 1)
									end,

									click = function(element)
										npage = npage - 1
										resultPanel:FireEventTree('refreshInventory')
									end,
								},

							},

							gui.Label{
								style = {
									fontSize = '35%',
									color = 'white',
									width = 'auto',
									height = 'auto',
									halign = 'center',
								},
								events = {
									refreshInventory = function(element)
										if not _opened then
											return
										end
										element.text = string.format('Page %d/%d', math.tointeger(npage), math.tointeger(NumPages()))
									end,
								}
							},

							gui.Panel{
								bgimage = 'panels/InventoryArrow.png',
								className = 'paging-arrow',
								style = {
									scale = {x = -1, y = 1},
									height = '100%',
									width = '50% height',
									halign = 'right',
									hmargin = 40,
								},

								events = {
									refreshInventory = function(element)
										if not _opened then
											return
										end
										element:SetClass('hidden', npage == NumPages())
									end,

									click = function(element)
										npage = npage + 1
										resultPanel:FireEventTree('refreshInventory')
									end,
								},
							},

						},
					},

					newItemButton,

				},
			},

			equipmentPanel,
			encumbrancePanel,
			discountPanel,
		}
	}

	for i,slot in ipairs(slots) do
		slot.data.inventoryDialog = resultPanel
	end

	return resultPanel
end

function GameHud.CreateAddItemDialog(self, options)
	local dialogWidth = 1200
	local dialogHeight = 920
	local resultPanel = nil

	--the panel to notify that we added an item.
	local panelNotify = nil

	local mainFormPanel = gui.Panel{
		style = {
			bgcolor = 'white',
			pad = 0,
			margin = 0,
			width = 1060,
			height = 800,
		},
	}

	local newItem = nil

	local confirmCancelPanel = 
		gui.Panel{
			style = {
				valign = 'bottom',
				flow = 'horizontal',
				height = 60,
				width = '100%',
				fontSize = '60%',
				vmargin = 0,
			},

			children = {
				gui.PrettyButton{
					text = 'Create',
					style = {
						height = 60,
						width = 160,
						bgcolor = 'white',
					},
					events = {
						click = function(element)
							--Add the new item and upload it to the game.
							local itemid = dmhub.SetAndUploadTableItem('tbl_Gear', newItem)
							resultPanel.data.close()

							if panelNotify ~= nil then
								panelNotify:FireEventTree('newItem', itemid)
							end

						end,
					},
				},
				gui.PrettyButton{
					text = 'Cancel',
                    escapeActivates = true,
                    escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
					style = {
						height = 60,
						width = 160,
						bgcolor = 'white',
					},
					events = {
						click = function(element)
							resultPanel.data.close()
						end,
					}
				},
			},
		}

	local closePanel = 
		gui.Panel{
			style = {
				valign = 'bottom',
				flow = 'horizontal',
				height = 60,
				width = '100%',
				fontSize = '60%',
				vmargin = 0,
			},

			children = {
				gui.PrettyButton{
					text = 'Close',
					fontSize = 24,
					hpad = 10,
					vpad = 6,
					escapeActivates = true,
					escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
					events = {
						click = function(element)
							--Add the new item and upload it to the game.
							local itemid = dmhub.SetAndUploadTableItem('tbl_Gear', newItem)
							resultPanel.data.close()

							if panelNotify ~= nil then
								panelNotify:FireEventTree('refreshInventory')
							end
						end,
					},
				},
			},
		}

	resultPanel = gui.Panel{
		id = "createItemDialog",
		classes = {'framedPanel', 'hidden'},
		style = {
			bgcolor = 'white',
			width = dialogWidth,
			height = dialogHeight,
			halign = 'center',
			valign = 'center',
		},
		styles = {
			SlotStyles,
			Styles.Panel,
		},

		data = {
			show = function(notify, editItem)
				resultPanel:SetAsLastSibling()
				panelNotify = notify

				if editItem then
					newItem = editItem
					confirmCancelPanel:SetClass('collapsed', true)
					closePanel:SetClass('collapsed', false)
				else
					newItem = equipment.new {
						id = dmhub.GenerateGuid(),
						name = 'New Item',
						type = 'Gear',
						category = 'Gear',
						specialDescription = '',
						description = '',
						weight = 1,
					}
					confirmCancelPanel:SetClass('collapsed', false)
					closePanel:SetClass('collapsed', true)
				end

				local title = 'Create New Item'
				if editItem then
					title = 'Edit Item'
				end

				mainFormPanel.children = {
					DataTables.tbl_Gear.GenerateEditor(newItem, {
						description = title,
					})
				}

				resultPanel:SetClass('hidden', false)

			end,
			close = function()
				mainFormPanel.children = {} --important to let preview scenes etc die.
				resultPanel:SetClass('hidden', true)
			end,
		},

		children = {
			gui.Panel{
				id = 'content',
				style = {
					halign = 'center',
					valign = 'center',
					width = '94%',
					height = '94%',
					flow = 'vertical',
				},
				children = {
					mainFormPanel,
					confirmCancelPanel,
					closePanel,

				},
			},
		},
	}

	return resultPanel
end


local CreateEquipmentSlot = function(dmhud, options)
	local slotPanel = nil
	local token = nil
	local item = nil --the item currently in the slot.

	local slotName = options.slot

	local highlightPanel = gui.Panel{
        classes = {"slotHighlight"},
		id = 'equipment-slot-' .. options.slot,
		interactable = false,
		dragTarget = true,
		styles = g_SlotHighlightStyles,

		data = {
			equipmentSlot = options.slot,

			AddItem = function(item, quantity, options)
				token:BeginChanges()

				local slotid = slotName

				token.properties:Unequip(slotid)

				local slotInfo = creature.EquipmentSlots[slotid]

				if item:TwoHanded() and slotInfo.loadout ~= nil and slotInfo.otherhand ~= nil then
					if not slotInfo.main then
						slotid = slotInfo.otherhand
						slotInfo = creature.EquipmentSlots[slotid]
					end

					token.properties:Unequip(slotInfo.otherhand)

					token.properties:EquipmentMetaSlot(slotid).twohanded = true
					token.properties:EquipmentMetaSlot(slotInfo.otherhand).twohanded = true
				end

				--clear any share info. It may be set again in onadd.
				token.properties:EquipmentMetaSlot(slotid).share = nil

				if options.onadd ~= nil then
					options.onadd(token.properties)
				end

				local existingItem = token.properties:GetEquipmentInSlot(slotid)
				if existingItem ~= nil then
					--put the existing item back in their inventory.
					token.properties:GiveItem(existingItem, 1)
				end

				if not options.noitem then
					token.properties:SetItemQuantity(item.id, token.properties:GetItemQuantity(item.id) - 1, options.slot)
				end
				token.properties:Equipment()[slotid] = item.id
				token:CompleteChanges('Equipped gear')

				for _,dialog in ipairs(dmhud.openInventoryDialogs) do
					dialog:FireEventTree('refreshInventory')
				end
			end,
		},
	}

	local scaling = 1
	if options.slot == 'armor' then
		scaling = 2
	end

	local iconEffectPanel = gui.Panel{
		id = 'inventory-slot-effect',
		selfStyle = {},
		styles = {
			{
				width = 64,
				height = 64,
				halign = 'center',
				valign = 'center',
			},
		},
	}

	local item = nil

	local Unequip = function()
		local itemid = token.properties:GetEquipmentOrShadowInSlot(slotName)
		if itemid == nil then
			--item was vacated since context menu shown
			return
		end

		token:BeginChanges()
		token.properties:Unequip(slotName)
		token:CompleteChanges('Unequip Gear')

		for _,dialog in ipairs(dmhud.openInventoryDialogs) do
			dialog:FireEventTree('refreshInventory')
		end
	end

	local iconPanel
    
    local icon = creature.EquipmentSlots[options.slot].icon
    if icon ~= nil then
        icon = string.format("ui-icons/slot-%s.png", icon)
    else
        icon = "panels/square.png"
    end
    
    iconPanel = gui.Panel{
        id = 'inventory-slot-icon',
        bgimage = icon,
        draggable = false,

        drag = function(element, target)
            if target ~= nil then
                if target.data.equipmentSlot == slotName then
                    return
                end

                if target.data.equipmentSlot then
                    target.data.AddItem(item, 1, {
                        onadd = function(creature)

                            --see if we can share between these slots.
                            local slotInfo = creature.EquipmentSlots[slotName]
                            local otherSlotInfo = creature.EquipmentSlots[target.data.equipmentSlot]
                            if slotInfo ~= nil and otherSlotInfo ~= nil and slotInfo.loadout and otherSlotInfo.loadout and (slotInfo.main == otherSlotInfo.main) then
                                --we can share between these slots.
                                local metaSlot = creature:EquipmentMetaSlot(slotName)
                                if metaSlot.share == nil then
                                    metaSlot.share = dmhub.GenerateGuid()
                                end

                                creature:EquipmentMetaSlot(target.data.equipmentSlot).share = metaSlot.share
                                printf("SHARE:: %s, %s -> %s", slotName, target.data.equipmentSlot, metaSlot.share)

                            else
                                local share = creature:EquipmentMetaSlot(slotName).share
                                if share ~= nil then
                                    --purge this share entirely.
                                    local purgeList = {}
                                    for key,info in pairs(creature:EquipmentMeta()) do
                                        if info.share == share then
                                            purgeList[#purgeList+1] = key

                                        end
                                    end

                                    for _,key in ipairs(purgeList) do
                                        printf("SHARE:: PURGING: %s", key)
                                        creature:SetEquipmentInSlot(key, nil)
                                    end
                                end

                                --when adding to a slot, remove from this slot.
                                creature:SetEquipmentInSlot(slotName, nil)
                                creature:ClearEquipmentMetaSlot(slotName)
                            end

                        end,

                        --don't deduct from items.
                        noitem = true,
                    })
                elseif token ~= nil and token.valid then
                    Unequip()
                end
            end
        end,

        canDragOnto = function(element, target)
            if target.data.equipmentSlot ~= nil then

                local slotInfo = creature.EquipmentSlots[target.data.equipmentSlot]
                if slotInfo == nil or item == nil then
                    return false
                end
                if slotInfo.type == 'armor' and item.type == 'Armor' then
                    return true
                elseif item:CanWield() and slotInfo.loadout ~= nil then
                    local sourceSlotInfo = creature.EquipmentSlots[slotName]
                    if sourceSlotInfo ~= nil and sourceSlotInfo.loadout ~= nil and slotInfo.loadout == sourceSlotInfo.loadout then
                        --dragging from one hand to the other.
                        if item:TwoHanded() then
                            --can't change hands for a two handed weapon.
                            return false
                        end

                    end
                    return true
                elseif item:try_get('requiresAttunement') and slotInfo.attune then
                    return true
                end

            else
                return target.data.inventoryDragTarget and target.data.GetToken() == token
            end

            return false
        end,

        selfStyle = {
            saturation = 0.2,
            brightness = 1,
        },
        styles = {
            {
                width = 64,
                height = 64,
                halign = 'center',
                valign = 'center',
            },
            {
                selectors = 'new',
                scale = 1.5,
                brightness = 2,
                rotate = 20,
                transitionTime = 0.5,
            },
        },
    }

	slotPanel = gui.Panel{
		id = 'inventory-slot',
        classes = {"inventorySlot"},
        styles = g_SlotStyles,

		selfStyle = {
			scale = scaling,
		},

		children = {
			SlotBorder{},
			highlightPanel,
			iconPanel,
			iconEffectPanel,
		},

		events = {
			hover = function(element)
				local itemid = token.properties:GetEquipmentInSlot(slotName)
				local item = nil
				if itemid then
					local gearTable = dmhub.GetTable('tbl_Gear')
					item = gearTable[itemid]
				end

				element.tooltipParent = element.data.inventoryDialog
				if item ~= nil then
					element.tooltip = CreateItemTooltip(item, {}, token)
				else
					local slotInfo = creature.EquipmentSlots[slotName]
					if slotInfo ~= nil and slotInfo.tooltip ~= nil then
						element.tooltip = slotInfo.tooltip
					end
				end
			end,
			dehover = function(element)
			end,

			click = function(element)
			end,

			rightClick = function(element)
				if token.properties:GetEquipmentInSlot(slotName) ~= nil then
					element.popup = gui.ContextMenu {
						entries = {
							{
								text = 'Share to Chat',
								click = function()
									element.popup = nil
									local itemid = token.properties:GetEquipmentInSlot(slotName)
									chat.ShareObjectInfo("tbl_Gear", itemid)
								end,
							},
							{
								text = 'Unequip Item',
								click = function()
									element.popup = nil

									Unequip()

								end,
							},
						}
					}
				end
			end,
		},

		data = {
			slot = slotName,

			FlashNew = function()
				iconPanel:PulseClass('new')
			end,

			SetItem = function(newItem, shadow)
				item = newItem
				if item then
					iconPanel.bgimage = item:GetIcon()
					iconPanel.selfStyle.brightness = cond(shadow, 0.4, 1)
					iconPanel.selfStyle.opacity = 1
					iconPanel.selfStyle.saturation = cond(shadow, 0.2, 1)
					iconPanel.draggable = true

					local iconEffectId = item:try_get('iconEffect')
					local iconEffect = nil
					if iconEffectId ~= nil then
						iconEffect = ItemEffects[iconEffectId]
					end

					iconEffectPanel:SetClass('hidden', iconEffect == nil)
					if iconEffect ~= nil then
						iconEffectPanel.bgimage = iconEffect.video
						iconEffectPanel.selfStyle.opacity = iconEffect.opacity or 1
						iconEffectPanel.bgimageMask = cond(iconEffect.mask, item:GetIcon())
					end

				else
                    local icon = creature.EquipmentSlots[options.slot].icon
                    if icon == nil then
					    iconPanel.bgimage = "panels/square.png"
					    iconPanel.selfStyle.opacity = 0
                    else
					    iconPanel.bgimage = string.format("ui-icons/slot-%s.png", icon)
					    iconPanel.selfStyle.opacity = 0.5
                    end
					iconPanel.selfStyle.brightness = 1
					iconPanel.selfStyle.saturation = 0.5
					iconPanel.draggable = false
					iconEffectPanel:SetClass('hidden', true)
				end
			end,

			SetToken = function(tok)
				token = tok

				local itemid = token.properties:GetEquipmentInSlot(slotName)

				local shadow = false

				if itemid == nil then
					itemid = token.properties:GetEquipmentShadowOrTwoHandInSlot(slotName)
					if itemid ~= nil then
						shadow = true
					end
				end

				local item = nil
				if itemid then
					local gearTable = dmhub.GetTable('tbl_Gear')
					item = gearTable[itemid]
				end

				slotPanel.data.SetItem(item, shadow)
			end,
		},
	}

	return slotPanel
end

function GameHud.CreateEquipmentDialog(self, options)

	local _opened = false

	local dialogWidth = 420
	local dialogHeight = 680

	local token = nil

	local avatarPanel
	if not options.charsheet then
		avatarPanel = gui.Panel{

			selfStyle = {},
			
			styles = {
				{
					vmargin = 16,
					width = dialogWidth - 80,
					height = '100% width',
					valign = 'top',
				}
			},

			events = {
				refreshInventory = function(element)
					if token ~= nil and token.valid and _opened then
						element.bgimage = token.portrait
						element.selfStyle.imageRect = token.portraitRect
					end
				end,
			},
			children = {
				SlotBorder{},
			},
		}
	end

	local titleLabel = gui.Label{
		text = 'Equipped Treasures',
		selfStyle = {
			width = 'auto',
			height = 'auto',
			halign = 'center',
			valign = 'top',
			fontSize = '70%',
			bold = true,
		}
	}

	local allSlots = {}

    local leveledSlots = {}
    local trinketSlots = {}

    for i=1,5 do
        leveledSlots[i] = CreateEquipmentSlot(self, { slot = string.format('leveled%d', i) })
    end

    for i=1,10 do
        trinketSlots[i] = CreateEquipmentSlot(self, { slot = string.format('trinket%d', i) })
    end



    for i,slot in ipairs(leveledSlots) do
        allSlots[#allSlots+1] = slot
    end

    for i,slot in ipairs(trinketSlots) do
        allSlots[#allSlots+1] = slot
    end



    local trinketSlotsArea = gui.Panel{
        valign = "top",
        width = '90%',
        height = 'auto',
        wrap = true,
        flow = 'horizontal',
        children = trinketSlots,
    }

    local leveledSlotsArea = gui.Panel{
        valign = "top",
        width = '90%',
        height = 'auto',
        flow = 'horizontal',
        children = leveledSlots,
    }

	local contentArea = gui.Panel{
		styles = {
			{
				halign = 'center',
				valign = 'center',
				width = '100%',
				height = '100%',
				flow = 'vertical',
			}
		},

		children = {
			titleLabel,
			avatarPanel,

            gui.Label{
                width = "auto",
                height = "auto",
                halign = "center",
                bold = true,
                fontSize = 16,
                text = "Leveled Treasures",
                valign = "top",
                tmargin = 8,
                bmargin = 4,
            },
            
            leveledSlotsArea,

            gui.Label{
                width = "auto",
                height = "auto",
                halign = "center",
                bold = true,
                fontSize = 16,
                text = "Trinkets",
                valign = "top",
                tmargin = 8,
                bmargin = 4,
            },

            trinketSlotsArea,
		}
	}

	local slotBorder
	if not options.charsheet then
		slotBorder = SlotBorder()
	end

	local resultPanel = nil
	resultPanel = gui.Panel{
		x = -600,
        blurBackground = true,
		bgimage = cond(not options.charsheet, 'panels/InventorySlot_Background.png'),

		styles = {
			{
				width = dialogWidth,
				height = dialogHeight,
				halign = 'center',
				valign = 'center',
				bgcolor = 'white',
				flow = 'none',
			},
		},
		
		children = {
			slotBorder,
			contentArea,
		},

		events = {
			refreshInventory = function()
				if token == nil or (not token.valid) or (not _opened) then
					resultPanel.monitorGame = nil
					return
				end

				resultPanel.monitorGame = string.format("/characters/%s", token.id)

				local gearTable = dmhub.GetTable('tbl_Gear')

				for i,slot in ipairs(allSlots) do
					local itemid = token.properties:Equipment()[slot.data.slot]
					local shadow = false
					if itemid == nil then
						itemid = token.properties:GetEquipmentShadowOrTwoHandInSlot(slot.data.slot)
						if itemid ~= nil then
							shadow = true
						end
					end
					slot.data.SetItem(gearTable[itemid], shadow)
				end
			end,

			refreshGame = function(element)
				dmhub.Debug('REFRESH INVENTORY')
				element:FireEventTree('refreshInventory')
			end,
		},

		data = {
			open = function(tok)
				_opened = true
				token = tok
				for i,slot in ipairs(allSlots) do
					slot.data.SetToken(token)
				end
				resultPanel:SetClass('hidden', false)
			end,
			close = function()
				_opened = false
				token = nil
				resultPanel:SetClass('hidden', true)
			end,
		}
	}

	return resultPanel
end


local CreateCharSheetInventory = function()

	local mainInventory = gamehud:CreateInventoryDialog{
		rearrange = true, --the user can rearrange the items in the inventory by dragging it.
		equipment = true,
		currency = false, --turned off for Draw Steel.
		charsheet = true,
		numRows = 6,
		numCols = 8,
		dialogWidth = 650,
	}

	local basicInventoryDialog = gamehud:CreateInventoryDialog{
		title = 'Available Items',
		basicInventory = true,
		tooltipAlign = 'right',
	}
	basicInventoryDialog.x = 600

	local tradeInventoryDialog = gamehud:CreateInventoryDialog{
		title = 'Trade',
		tradeInventory = true,
		tooltipAlign = 'right',
		currency = false, --switch this to true if we want to enable currencies.
	}
	tradeInventoryDialog.x = 600


	local resultPanel
	resultPanel = gui.Panel{
		classes = {"characterSheetPanel", "hidden"},
		width = "100%",
		height = "100%",
		flow = "none",

        data = {
            basicInventoryDialog = basicInventoryDialog,
            tradeInventoryDialog = tradeInventoryDialog,
        },

        styles = g_InventoryStyles,

		charsheetActivate = function(element, val)
			if not val then
				return
			end
			local tok = CharacterSheet.instance.data.info.token
			mainInventory.data.open(tok, {})

		end,

		mainInventory,
        basicInventoryDialog,
        tradeInventoryDialog,
	}

	return resultPanel
end

CharSheet.RegisterTab{
	id = "Inventory",
	text = "Inventory",
	panel = CreateCharSheetInventory,
}

dmhub.RefreshCharacterSheet()
GameHud.InvalidateGameHud()