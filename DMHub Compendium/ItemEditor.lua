local mod = dmhub.GetModLoading()

--This file implements the editing sheet for items.


DataTables.tbl_Gear = {}

--[==[ DEAD_CODE - overridden by Draw Steel UI\DSInventoryEditor.lua:8
function DataTables.tbl_Gear.ReadSQL(row)
	local type = row.Get("type")

	local ParseNum = function(item)
		if item == nil then
			return nil
		end

		return tonumber(item)
	end

	if type == "Weapon" then
		return weapon.new {
			name = row.Get("name"),
			type = 'Weapon',
			category = row.Get("category") or 'Simple',
			costInGold = tonumber(row.Get("costInGold")),
			specialDescription = row.Get("specialDescription"),
			iconid = row.Get("iconid") or '',
			description = row.Get("description") or '',
			weight = row.Get("weight"),

			damage = row.Get("damage") or 1,
			damageType = row.Get("damageType") or 'slashing',
			range = row.Get("range"),
			ammo = row.Get("ammo"),
			thrown = row.Get("thrown"),
			hands = row.Get("hands") or 'One-handed',
			loading = row.Get("loading"),
			light = row.Get("light"),
			heavy = row.Get("heavy"),
			versatileDamage = row.Get("versatileDamage"),
			finesse = row.Get("finesse"),
			reach = row.Get("reach"),
		}
	elseif type == "Armor" then
		return armor.new {
			name = row.Get("name"),
			type = 'Armor',
			category = row.Get("category") or 'Light',
			costInGold = tonumber(row.Get("costInGold")),
			specialDescription = row.Get("specialDescription"),
			iconid = row.Get("iconid") or '',
			description = row.Get("description") or '',
			weight = row.Get("weight"),

			armorClass = tonumber(row.Get("armorClass")),
			strength = row.Get("strength"),
			stealth = row.Get("stealth"),
			dexterityLimit = ParseNum(row.Get("ModifierLimit")),
		}
	elseif type == "Shield" then
		return shield.new {
			name = row.Get("name"),
			type = 'Shield',
			category = row.Get("category") or '',
			costInGold = tonumber(row.Get("costInGold")),
			specialDescription = row.Get("specialDescription"),
			iconid = row.Get("iconid") or '',
			description = row.Get("description") or '',
			weight = row.Get("weight"),
			armorClassModifier = tonumber(row.Get("armorClass")),
		}
	else
		return equipment.new {
			name = row.Get("name"),
			type = row.Get("type") or 'Gear',
			category = row.Get("category") or 'Gear',
			costInGold = tonumber(row.Get("costInGold")),
			specialDescription = row.Get("specialDescription"),
			iconid = row.Get("iconid") or '',
			description = row.Get("description") or '',
			weight = row.Get("weight"),
		}
	end
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel UI\DSInventoryEditor.lua:85
function DataTables.tbl_Gear.WriteSQL(obj)
	local category = rawget(obj, "category")
	if category == nil then
		category = 'Adventuring Gear'
	end

	return {
		name = rawget(obj, "name"),
		type = rawget(obj, "type"),
		category = category,
		costInGold = rawget(obj, "costInGold"),
		specialDescription = rawget(obj, "specialDescription"),
		iconid = rawget(obj, "iconid") or '',
		description = rawget(obj, "description"),
		weight = rawget(obj, "weight"),
		damage = rawget(obj, "damage") or '1d6',
		damageType = rawget(obj, "damageType") or 'slashing',
		range = rawget(obj, "range") or "NULL",
		ammo = rawget(obj, "ammo"),
		thrown = rawget(obj, "thrown"),
		hands = rawget(obj, "hands"),
		loading = rawget(obj, "loading"),
		light = rawget(obj, "light"),
		heavy = rawget(obj, "heavy"),
		versatileDamage = rawget(obj, "versatileDamage"),
		finesse = rawget(obj, "finesse"),
		reach = rawget(obj, "reach"),
		armorClass = rawget(obj, "armorClass") or rawget(obj, "armorClassModifier"),
		strength = rawget(obj, "strength"),
		stealth = rawget(obj, "stealth"),

		--in the database it's called "ModifierLimit" (and also has an ostensibly unneeded 'Modifier'
		--field associated with it, but we will call it dexterityLimit since that makes more sense.)
		ModifierLimit = rawget(obj, "dexterityLimit"),
	}
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel UI\DSInventoryEditor.lua:122
function DataTables.tbl_Gear.CreateNew()
	return weapon.new{
		name = 'New Item',
		type = 'Weapon',
		hands = 'One-handed',
		description = '',
		iconid = '',
		category = 'Simple',
		costInGold = 10,
		weight = '2 lbs',
		damage = '1d6',
		damageType = 'slashing',
	}
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel UI\DSInventoryEditor.lua:137
function DataTables.tbl_Gear.Input(document, text, attr, options)
	local x = 0
	local y = 0
	local inputWidth = 200
	if options ~= nil then
		if options['x'] ~= nil then
			x = options['x']
		end
		if options['y'] ~= nil then
			y = options['y']
		end
		if options['width'] ~= nil then
			inputWidth = options['width']
		end
	end

	return gui.Panel({
		id = attr,
		x = x,
		y = y,
		style = {
			flow = 'horizontal',
			width = 400,
			height = 50,
			valign = 'center',
		},
		children = {
			gui.Label({
				text = text,
				style = {
					width = 200,
					height = 50,
				}
			}),
			gui.Input({
				text = document:try_get(attr, ''),
				id = 'Input' .. text,
				events = {
					change = function(element)
						document[attr] = element.text
					end,
				},
				style = {
					width = inputWidth,
				}
			}),
		},
	})
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel UI\DSInventoryEditor.lua:187
function DataTables.tbl_Gear.Dropdown(document, text, attr, options, unused, onchange)

	if onchange == nil then
		onchange = function(element)
			document[attr] = element.optionChosen
			DataTables.tbl_Gear.RecalculateForm(element)
		end
	end

	return gui.Panel({
		style = {
			flow = 'horizontal',
			width = 400,
			height = 50,
		},
		children = {
			gui.Label({
				text = text,
				style = {
					width = 200,
					height = 50,
				}
			}),
			gui.Dropdown({
				id = 'TypeDropdown',
				options = options,
				optionChosen = document:try_get(attr, options[1]),
				events = {
					change = onchange,
				},
				style = {
					width = 200,
					height = 50,
				}
			}),
		}
	})
end
--]==]

function DataTables.tbl_Gear.GetAvailableProperties(document)

	local allProperties = WeaponProperty.DropdownOptions(document)
	local options = {}

	for i = 1, #allProperties do
		if not document:HasProperty(allProperties[i].id) then
			options[#options+1] = allProperties[i]
		end
	end

	return options
end

--[==[ DEAD_CODE - overridden by Draw Steel UI\DSInventoryEditor.lua:238
function DataTables.tbl_Gear.DescribeProperties(document)
	local properties = DataTables.tbl_Gear.GetAvailableProperties(document)
	local result = {}
	for i = 1, #properties do
		result[#result+1] = properties[i].text
	end

	return result
end
--]==]

--[==[ DEAD_CODE - overridden by Draw Steel UI\DSInventoryEditor.lua:248
function DataTables.tbl_Gear.DeleteProperty(document, propid)
	document[propid] = nil
end
--]==]

local SetEquipmentType = function(document, typeStr)

	document.type = typeStr
	if typeStr == 'Weapon' then
		weapon.new(document)
		document.category = 'Simple'
	elseif typeStr == 'Armor' then
		armor.new(document)
		document.category = 'Light'
	elseif typeStr == 'Shield' then
		shield.new(document)
	else
		equipment.new(document)
	end

end

function DataTables.tbl_Gear.GenerateEditor(document, options)
	options = options or {}

	local resultPanel = nil
	local description = options.description or 'Create Item'

	local Refresh = function()
		resultPanel:FireEventTree('refresh')
	end

	local EnsureWieldObject = function(callback)
		if document:try_get("itemObjectId") ~= nil then
			if callback ~= nil then
				callback()
			end
			return
		end

		local objectJson = document:GetWieldObject()
		local guid = assets:UploadNewObject{
			description = document.name,
			previewType = "wield",
			imageId = objectJson.asset.imageId,
			hidden = true,
			components = objectJson.components,
		}


		dmhub.ScheduleWhen(function()
			local result = assets:GetObjectNode(guid) ~= nil
			return result
		end,
		function()
			document.itemObjectId = guid
			if callback ~= nil then
				callback()
			end
			Refresh()
		end)
	end



	local emojiOptions = {}

	for k,emoji in pairs(assets.emojiTable) do
		if emoji.emojiType == "Accessory" then
			emojiOptions[#emojiOptions+1] = {
				id = k,
				text = emoji.description,
			}
		end
	end

	table.sort(emojiOptions, function(a,b) return a.text < b.text end)
	table.insert(emojiOptions, 1, { id = "none", text = "None" })

	--function to create a simple Name: <child> panel.
	local FormPanel = function(options)

		local dmOnly = options.dmOnly

		local calculateCollapse = function()
			if dmOnly and not dmhub.isDM then
				return true
			end

			if options.collapse ~= nil and options.collapse() then
				return true
			end

			if options.types == nil then
				return false
			end

			local found = false
			for i,v in ipairs(options.types) do
				if v == document.type then
					found = true
				end
			end

			return not found
		end

		--make a function to make this collapse if the type it's specified for doesn't exist.
		local shouldCollapse = nil
		if options.types ~= nil or options.collapse ~= nil then
			shouldCollapse = function(element)

				element:SetClass('collapsed-anim', calculateCollapse())
			end
		end

		return gui.Panel{
			classes = options.classes or {
				--start it off collapsed if it should collapse.
				['collapsed-anim'] = calculateCollapse()
			},
			events = {
				refresh = shouldCollapse,
			},
			style = {
				width = '100%',
				height = 'auto',
				flow = 'horizontal',
				hmargin = 8,
				vmargin = 4,
			},
			children = {
				gui.Label{
					text = options.text,
					style = {
						valign = 'center',
						halign = 'left',
						width = '50%',
						height = 'auto',
						textAlignment = 'right',
					},
				},
				options.child,
			},
		}
	end

	local leftPanel = gui.Panel{
		style = {
			width = '45%',
			height = 'auto',
			halign = 'center',
			flow = 'vertical',
		},
		children = {
			gui.Panel{
				id = "equipmentTypePanel",
				width = "100%",
				height = 'auto',
				flow = 'vertical',
				create = function(element)
					local parentElement = element

					local children = {}

					local catTable = dmhub.GetTable('equipmentCategories') or {}

					local typeNames = {'Type:', 'Category:', 'Sub-Category:'}

					local selection = { '' }

					local equipmentCat = document:try_get("equipmentCategory")
					if equipmentCat ~= nil then

						local catInfo = catTable[equipmentCat]
						local count = 1
						while catInfo ~= nil and count < 10 do

							table.insert(selection, 2, catInfo.id)

							if catInfo:try_get("superset") ~= nil then
								catInfo = catTable[catInfo.superset]
							else
								catInfo = nil
							end
							count = count+1
						end
					end

					for i,item in ipairs(selection) do
						local options = {
							{
								id = 'choose',
								text = 'Select Category...',
								hidden = true,
							}
						}
						for k,cat in pairs(catTable) do
							if cat:try_get('superset', '') == item and (not cat:try_get("hidden", false)) then
								options[#options+1] = {
									id = cat.id,
									text = cat.name,
								}
							end
						end

						if #options > 1 then
							local idchosen = 'choose'
							if i+1 <= #selection then
								idchosen = selection[i+1]
							end

							table.sort(options, function(a,b) return a.text < b.text end)

							children[#children+1] = FormPanel{
								text = typeNames[i] or typeNames[#typeNames],
								child = gui.Dropdown{
									options = options,
									idChosen = idchosen,
									width = 180,
									height = 26,
									fontSize = 18,
									change = function(element)
										if element.idChosen ~= 'choose' then
											document.equipmentCategory = element.idChosen
											parentElement:FireEvent("create")
											local catInfo = catTable[element.idChosen]
											if catInfo ~= nil and catInfo.editorType ~= document.type then
												SetEquipmentType(document, catInfo.editorType)
												Refresh()
											end
										end
									end,
								}
							}
						end
					end

					element.children = children
				end,
			},

			FormPanel{
				text = "Base Item:",
				collapse = function()
					return document:try_get("equipmentCategory") == nil
				end,
				child = gui.Dropdown{
					data = {
						catid = nil,
						itemidsKnown = {},
					},
					change = function(element)
						if element.idChosen == "none" then
							document.baseid = nil
						else
							document.baseid = element.idChosen
						end
					end,
					refresh = function(element)
						local cat = document:try_get("equipmentCategory")
						if cat == nil then
							return
						end

						if cat ~= element.data.catid then
							element.data.catid = cat

							local catsToItems = EquipmentCategory.GetCategoriesToItems(false)
							local itemList = catsToItems[element.data.catid]
							if itemList == nil or #itemList == 0 then
								element.parent:SetClass("hidden", true)
							end

							local inventoryTable = dmhub.GetTable("tbl_Gear")
							local options = {
								{
									id = "none",
									text = "(None)",
								}
							}

							element.data.itemidsKnown = {}
							for _,itemid in ipairs(itemList or {}) do
								local item = inventoryTable[itemid]
								if item ~= nil then
									options[#options+1] = {
										id = itemid,
										text = item.name,
									}

									element.data.itemidsKnown[itemid] = true
								end
							end

							element.options = options
						end

						element.parent:SetClass("hidden", false)

						local id = document:try_get("baseid", document.id)
						if element.data.itemidsKnown[id] then
							element.idChosen = id
						else
							element.idChosen = "none"
						end
					end,

				},


			},

			FormPanel{
				text = "ID:",
				collapse = function()
					return not devmode()
				end,
				child = gui.Input{
					id = "equipment-id-input",
					text = document:try_get("id", "(unassigned)"),
					refresh = function(element)
						element.text = document:try_get("id", "(unassigned)")
					end,
				},
			},

			FormPanel{
				text = 'Name:',
				child = gui.Input{
					id = 'equipment-name-input',
					
					events = {
						refresh = function(element)
							element.text = document.name
						end,
						change = function(element)
							if document:has_key("consumable") then
								--if we have a consumable ability then remap its name with ours.
								if document.consumable.name == document.name then
									document.consumable.name = element.text
								end
							end

							document.name = element.text
							Refresh()
						end,
					}
				},
			},

			FormPanel{
				text = "Implementation:",
				child = gui.ImplementationStatusPanel{
					value = document:try_get("implementation", 1),
					change = function(element)
						document.implementation = element.value
					end,
				},
			},

			FormPanel{
				text = 'Rarity:',
				collapse = function()
					return (not EquipmentCategory.IsMagical(document)) and (not EquipmentCategory.IsTreasure(document))
				end,
				child = gui.Dropdown{
					id = 'equipment-rarity-input',

					options = equipment.rarities,
					
					events = {
						refresh = function(element)
							element.idChosen = document:try_get("rarity", "common")
						end,
						change = function(element)
							document.rarity = element.idChosen
							Refresh()
						end,
					}
				},
			},

			FormPanel{
				text = '',
				dmOnly = true,
				child = gui.Check{
					id = 'checkbox-hidden-from-players',
					text = 'Hide from Players',
					style = {
						halign = "left",
						height = 40,
						width = '40%',
						fontSize = '60%',
					},

					events = {
						hover = gui.Tooltip('Players will not be shown this item in list of all possible items. They will only see it if it is in their inventory.'),
						refresh = function(element)
							element.value = document:try_get('hiddenFromPlayers', dmhub.GetSettingValue("hideitems"))
						end,
						
						change = function(element)
							if element.value then
								document.hiddenFromPlayers = true
							else
								document.hiddenFromPlayers = false
							end
						end,
					}
				},
			},

			FormPanel{
				text = '',
				child = gui.Check{
					id = 'checkbox-magical-item',
					text = 'Magical Item',
					style = {
						halign = "left",
						height = 40,
						width = '40%',
						fontSize = '60%',
					},

					events = {
						hover = gui.Tooltip('This is a magical item with special properties.'),
						refresh = function(element)
							element.value = document:has_key('magicalItem')
						end,
						
						change = function(element)
							if element.value then
								document.magicalItem = "magical" --make it match on searches for 'magic'.
							else
								document.magicalItem = nil
							end
							Refresh()
						end,
					}
				},
			},

			FormPanel{
				text = '',
				collapse = function()
					return not document:has_key("magicalItem")
				end,
				child = gui.Check{
					id = 'checkbox-attuned-item',
					text = 'Requires Attunement',
					style = {
						halign = "left",
						height = 40,
						width = '40%',
						fontSize = '60%',
					},

					events = {
						hover = gui.Tooltip('This magical item requires attunement to use its magical powers.'),
						refresh = function(element)
							element.value = document:has_key('requiresAttunement')
						end,
						
						change = function(element)
							if element.value then
								document.requiresAttunement = true
							else
								document.requiresAttunement = nil
							end
							Refresh()
						end,
					}
				},
			},

			FormPanel{
				text = 'Destroy Chance:',
				collapse = function()
					return not document:IsAmmoForWeapon()
				end,
				child = gui.Input{
					refresh = function(element)
						local destroyChance = document:AmmoDestroyChance()
						element.text = string.format("%d", round(destroyChance*100))
					end,
					change = function(element)
						local n = tonumber(element.text)
						if n ~= nil and n >= 0 and n <= 100 then
							document.destroyChance = round(n)
						end
						Refresh()
					end,

				},
			},

			gui.Panel{
				classes = {cond(document:IsAmmoForWeapon(), "collapsed-anim")},
				width = "auto",
				height = "auto",
				halign = "right",
				refresh = function(element)
					element:SetClass("collapsed-anim", document:IsAmmoForWeapon())
				end,
				CharacterFeature.ListEditor(document, "features", {
					dialog = gamehud.dialog.sheet,
					createOptions = {
						addText = "Add Magical Property",
						itemAttached = true,
						name = "Item Feature",
						source = "Item",
					}
				}),
			},


			gui.Panel{
				id = "ammoAugmentPanel",
				styles = {
					Styles.Form,
					CharacterFeature.ModifierStyles,
					{
						classes = {"formLabel"},
						halign = "left",
						width = 180,
					},
					{
						classes = {"formPanel"},
						width = "100%",
					},
				},
				width = 540,
				height = "auto",
				halign = "left",
				flow = "vertical",
				bgimage = "panels/square.png",
				bgcolor = "clear",
				borderWidth = 1,
				borderColor = "white",
				pad = 4,
				classes = {cond(not document:IsAmmoForWeapon(), 'collapsed-anim')},

				refreshModifier = function(element)
				end,

				refresh = function(element)
					element:SetClass('collapsed-anim', not document:IsAmmoForWeapon())
					if element:HasClass("collapsed-anim") then
						return
					end

					if document:try_get("ammoAugmentation") == nil then
						local augmentation = CharacterModifier.new{
							behavior = 'modifyability',
							guid = dmhub.GenerateGuid(),
							name = "Ammo Modification",
							source = "Ammunition",
							description = "Ammunition modifies",
							unconditional = true,
						}

						CharacterModifier.TypeInfo.modifyability.init(augmentation)
						document.ammoAugmentation = augmentation
					end

					CharacterModifier.TypeInfo.modifyability.createEditor(document.ammoAugmentation, element.children[2])
				end,

				gui.Label{
					classes = {"form-heading"},
					text = "Modify Attacks",
					bold = true,
					halign = "left",
					hmargin = 2,
				},

				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
				},
			},

			gui.Panel{
				id = "weaponBehaviorPanel",
				styles = {
					Styles.Form,
					CharacterFeature.ModifierStyles,
					{
						classes = {"formLabel"},
						halign = "left",
						width = 180,
					},
					{
						classes = {"formPanel"},
						width = "100%",
					},
				},
				width = 540,
				height = "auto",
				halign = "left",
				flow = "vertical",
				bgimage = "panels/square.png",
				bgcolor = "clear",
				borderWidth = 1,
				borderColor = "white",
				pad = 4,
				classes = {cond(not document.isWeapon, 'collapsed-anim')},

				refreshModifier = function(element)
				end,

				refresh = function(element)
					element:SetClass('collapsed-anim', not document.isWeapon)
					if element:HasClass("collapsed-anim") then
						return
					end

					if document:try_get("weaponBehavior") == nil then
						local augmentation = CharacterModifier.new{
							behavior = 'modifyability',
							guid = dmhub.GenerateGuid(),
							name = "Weapon Modification",
							source = "Weapon",
							description = "Weapon modifiers",
							unconditional = true,
						}

						CharacterModifier.TypeInfo.modifyability.init(augmentation)
						document.weaponBehavior = augmentation
					end

					CharacterModifier.TypeInfo.modifyability.createEditor(document.weaponBehavior, element.children[2])
				end,

				gui.Label{
					classes = {"form-heading"},
					text = "Modify Attacks",
					bold = true,
					halign = "left",
					hmargin = 2,
				},

				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "vertical",
				},
			},

			gui.Panel{
				id = "packEditor",
				flow = "vertical",
				width = 300,
				height = "auto",
				vmargin = 8,
				hmargin = 8,
				pad = 8,
				bgimage = "panels/square.png",
				bgcolor = "clear",
				borderWidth = 2,
				borderColor = Styles.textColor,

				gui.Label{
					halign = "center",
					valign = "top",
					width = "auto",
					height = "auto",
					fontSize = 26,
					text = "Pack Items",
				},

				gui.Dropdown{
					options = {},
					idChosen = "add",
					hasSearch = true,
					halign = "right",
					refresh = function(element)
						if element.parent:HasClass("collapsed") then
							return
						end

	
						local itemOptions = {}

						local inventoryTable = dmhub.GetTable("tbl_Gear")
						for k,item in pairs(inventoryTable) do
							if (not item:try_get("hidden", false)) and (not EquipmentCategory.IsTreasure(item)) and (not EquipmentCategory.IsMagical(item)) then
								itemOptions[#itemOptions+1] = {
									id = k,
									text = item.name,
								}
							end
						end

						table.sort(itemOptions, function(a, b) return a.text < b.text end)

						itemOptions[#itemOptions+1] = {
							id = "add",
							text = "Add Item...",
						}

						element.options = itemOptions

						element.idChosen = "add"
					end,

					change = function(element)
						if element.idChosen ~= "new" then
							document.packItems = document:try_get("packItems", {})
							document.packItems[#document.packItems+1] = {
								itemid = element.idChosen,
								quantity = 1,
							}
							Refresh()
						end
					end,
				},

				refresh = function(element)
					element:SetClass("collapsed", not EquipmentCategory.IsPack(document))
					if element:HasClass("collapsed") then
						return
					end

					local children = element.children

					local label = children[1]

					table.remove(children, 1)

					local dropdown = children[#children]
					children[#children] = nil

					local newChildren = {label}

					local packItems = document:try_get("packItems", {})
					for i,packItem in ipairs(packItems) do
						local panel = children[i] or gui.Panel{
							width = "100%",
							height = 30,
							flow = "horizontal",
							gui.Label{
								fontSize = 20,
								width = 200,
								height = "auto",
								item = function(element, item)
									local inventoryTable = dmhub.GetTable("tbl_Gear")
									element.text = inventoryTable[item.itemid].name
								end,
							},

							gui.Input{
								fontSize = 20,
								width = 60,
								item = function(element, item)
									element.text = tostring(item.quantity)
								end,
								change = function(element)
									local n = tonumber(element.text)
									if n ~= nil then
										n = round(n)
										if n <= 0 then
											table.remove(document.packItems, i)
										else
											document.packItems[i].quantity = n
										end
									end

									Refresh()
								end,
							},

							gui.DeleteItemButton{
								press = function(element)
									table.remove(document.packItems, i)
									Refresh()
								end,
							},
						}

						newChildren[#newChildren+1] = panel
						panel:FireEventTree("item", packItem)
					end

					newChildren[#newChildren+1] = dropdown
					element.children = newChildren
				end,
			},



			FormPanel{
				text = 'Weight (lbs):',
				child = gui.Input{
					id = 'equipment-weight-input',
					
					events = {
						refresh = function(element)
							element.text = tostring(document.weight)
						end,
						change = function(element)
							document.weight = tonumber(element.text)
							Refresh()
						end,
					}
				},
			},

			FormPanel{

				text = 'Cost:',
				child = gui.CurrencyEditor{
					value = document:GetCurrencyCost(),
					change = function(element)
						document:SetCurrencyCost(element.value)
						Refresh()
					end,
				},
			},

			FormPanel{
				text = "Quantity:",
				classes = {
					['collapsed-anim'] = (document:has_key("equipmentCategory") == false or not EquipmentCategory.quantityCategories[document.equipmentCategory]),
				},
				child = gui.Input{
					text = string.format("%d", document:try_get("massQuantity", 1)),
					change = function(element)
						document.massQuantity = tonumber(element.text)
						Refresh()
					end,
					refresh = function(element)
						element.text = string.format("%d", document:try_get("massQuantity", 1))
						element.parent:SetClass("collapsed-anim", (document:has_key("equipmentCategory") == false or not EquipmentCategory.quantityCategories[document.equipmentCategory]))
					end,
				},
			},

			--gear-specific fields.

			FormPanel{
				text = '',
				types = {'Gear'},
				child = gui.Check{
					id = 'checkbox-has-light',
					text = 'Light',
					halign = "left",
					style = {
						height = 40,
						width = '40%',
						fontSize = '60%',
					},

					events = {
						hover = gui.Tooltip('This item emits light and can be equipped as a light source.'),
						refresh = function(element)
							element.value = document:has_key('emitLight')
							if document:has_key("emitLight") then
								EnsureWieldObject()
							end
						end,
						
						change = function(element)
							if element.value then
								document.emitLight = document:try_get('emitLight', Light.Create())
								EnsureWieldObject()
							else
								document.emitLight = nil
							end
							Refresh()
						end,
					}
				},
			},

			FormPanel{
				text = '',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear' or document:try_get("emitLight") or document.isWeapon or document.isShield),
				},
				types = {'Gear'},
				child = gui.Check{
					id = 'checkbox-equip-belt',
					text = 'Can Hold in Hand',
					halign = "left",
					style = {
						height = 40,
						width = '40%',
						fontSize = '60%',
					},

					events = {
						hover = gui.Tooltip("This item can be wielded in a character's hand."),
						refresh = function(element)
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear' or document:try_get("emitLight") or document.isWeapon or document.isShield)
							element.value = document:try_get("canWield", false)
						end,
						
						change = function(element)
							document.canWield = element.value
							if element.value then
								EnsureWieldObject()
							end
							Refresh()
						end,
					}
				},
			},



			FormPanel{
				text = '',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear'),
				},
				types = {'Gear'},
				child = gui.Check{
					id = 'checkbox-equip-belt',
					text = 'Can Equip on Belt',
					halign = "left",
					style = {
						height = 40,
						width = '40%',
						fontSize = '60%',
					},

					events = {
						hover = gui.Tooltip("This item can be equipped on a character's belt."),
						refresh = function(element)
							local light = document:try_get('emitLight')
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear')
							element.value = document:try_get("equipOnBelt", false)
						end,
						
						change = function(element)
							document.equipOnBelt = element.value
							if element.value then
								EnsureWieldObject()
							end
							Refresh()
						end,
					}
				},
			},

--[[
			FormPanel{
				text = 'Light Color:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear' or document:try_get('emitLight') == nil),
				},
				child = gui.ColorPicker{
					id = 'color-picker-light',
					styles = {
						{
							valign = 'center',
							height = 24,
							width = 24,
						},
					},

					events = {
						refresh = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								element.value = light.color
							end
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear' or light == nil)
						end,
						
						change = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								light.color = element.value
							end
						end,
					}
				},
			},
--]]
			FormPanel{
				text = 'Bright Radius:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear' or document:try_get('emitLight') == nil),
				},
				child = gui.Slider{
					id = 'slider-light-inner-radius',
					style = {
						height = 40,
						width = 200,
						fontSize = 14,
					},

					unclamped = true,

					sliderWidth = 140,
					labelWidth = 50,

					minValue = 1,
					maxValue = 20,

					formatFunction = function(num)
						return string.format('%s %s', MeasurementSystem.NativeToDisplayString(round(num)*5), MeasurementSystem.Abbrev())
					end,

					deformatFunction = function(num)
						return MeasurementSystem.DisplayToNative(num/5)
					end,

					events = {
						refresh = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								element.value = light.innerRadius
							end
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear' or light == nil)
						end,
						
						change = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								light.innerRadius = round(element.value)
							end
						end,
					}
				},
			},

			FormPanel{
				text = 'Dim Radius:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear' or document:try_get('emitLight') == nil),
				},
				child = gui.Slider{
					id = 'slider-light-radius',
					style = {
						height = 40,
						width = 200,
						fontSize = 14,
					},

					unclamped = true,

					sliderWidth = 140,
					labelWidth = 50,

					minValue = 1,
					maxValue = 20,

					formatFunction = function(num)
						return string.format('%d ft', round(num)*5)
					end,

					deformatFunction = function(num)
						return MeasurementSystem.DisplayToNative(num/5)
					end,

					events = {
						refresh = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								element.value = light.radius
							end
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear' or light == nil)
						end,
						
						change = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								light.radius = round(element.value)
							end
						end,
					}
				},
			},
--[[
			FormPanel{
				text = 'Softness:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear' or document:try_get('emitLight') == nil),
				},
				child = gui.Slider{
					id = 'slider-light-angle',
					style = {
						height = 40,
						width = 200,
						fontSize = 14,
					},

					sliderWidth = 140,
					labelWidth = 50,

					minValue = 0,
					maxValue = 1,

					formatFunction = function(num)
						return string.format('%.1f', num)
					end,

					deformatFunction = function(num)
						return num
					end,

					events = {
						refresh = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								element.value = light.size
							end
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear' or light == nil)
						end,
						
						change = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								light.size = element.value
							end
						end,
					}
				},
			},

			FormPanel{
				text = 'Light Angle:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear' or document:try_get('emitLight') == nil),
				},
				child = gui.Slider{
					id = 'slider-light-angle',
					style = {
						height = 40,
						width = 200,
						fontSize = 14,
					},

					sliderWidth = 140,
					labelWidth = 50,

					minValue = 1,
					maxValue = 360,

					formatFunction = function(num)
						return string.format('%d', round(num))
					end,

					deformatFunction = function(num)
						return num
					end,

					events = {
						refresh = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								element.value = light.angle
							end
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear' or light == nil)
						end,
						
						change = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								light.angle = round(element.value)
							end
						end,
					}
				},
			},

			FormPanel{
				text = 'Light Flicker:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Gear' or document:try_get('emitLight') == nil),
				},
				child = gui.Slider{
					id = 'slider-light-flicker',
					style = {
						height = 40,
						width = 200,
						fontSize = 14,
					},

					sliderWidth = 140,
					labelWidth = 50,

					minValue = 0,
					maxValue = 1,

					formatFunction = function(num)
						return string.format('%d%%', round(num*100))
					end,

					deformatFunction = function(num)
						return num*0.01
					end,

					events = {
						refresh = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								element.value = light:try_get('flicker', 0)
							end
							element.parent:SetClass('collapsed-anim', document.type ~= 'Gear' or light == nil)
						end,
						
						change = function(element)
							local light = document:try_get('emitLight')
							if light ~= nil then
								light.flicker = element.value
							end
						end,
					}
				},
			},
--]]

			FormPanel{
				text = '',
				types = {'Gear'},
				child = gui.Check{
					id = 'checkbox-consumable',
					text = 'Consumable',
					halign = "left",
					style = {
						height = 40,
						width = '40%',
						fontSize = '60%',
					},

					events = {
						hover = gui.Tooltip('This item can be consumed and will have an effect when it is'),
						refresh = function(element)
							element.value = document:has_key('consumable')
						end,
						
						change = function(element)
							if element.value then
								if not document:has_key("consumable") then
									document.consumable = ActivatedAbility.Create{
										name = document.name,
										iconid = document.iconid,
										attributeOverride = "no_attribute",
										description = '',
										range = 5,
										behaviors = {},
										consumables = { [document.id] = 1 },
									}
								end
							else
								document.consumable = nil
							end
							Refresh()
						end,
					}
				},
			},

			FormPanel{
				text = 'Charges',
				types = {'Gear'},
				classes = {
					['collapsed'] = (document.type ~= 'Gear' or document:try_get('consumable') == nil),
				},
				child = gui.Input{
					id = 'checkbox-consumable',
					characterLimit = 2,

					events = {
						refresh = function(element)
							element.parent:SetClass("collapsed", (document.type ~= 'Gear' or document:try_get('consumable') == nil))
							element.text = tostring(document:try_get('consumableCharges', 1))
						end,
						
						change = function(element)
							local n = tonumber(element.text)
							if n ~= nil then
								n = round(n)
								if n >= 1 and n <= 99 then
									document.consumableCharges = n
								end
							end

							element:FireEvent("refresh")
							Refresh()
						end,
					}
				},
			},



			FormPanel{
				types = {'Gear'},
				classes = {
					['collapsed'] = (document.type ~= 'Gear' or document:try_get('consumable') == nil),
				},

				child = gui.PrettyButton{
					width = 240,
					height = 60,
					text = "Consumable Ability",
					click = function(element)
						element.root:AddChild(document.consumable:ShowEditActivatedAbilityDialog())
					end,
					refresh = function(element)
						element.parent:SetClass("collapsed", (document.type ~= 'Gear' or document:try_get('consumable') == nil))
					end,

				}
			},

			--armor-specific fields.
			FormPanel{
				text = 'Armor Class:',
				types = {'Armor'},
				child = gui.Input{
					id = 'armor-class-input',

					events = {
						refresh = function(element)
							if element.parent:HasClass('collapsed-anim') then
								return
							end
							element.text = tostring(document.armorClass)
						end,
						change = function(element)
							if tonumber(element.text) ~= nil then
								document.armorClass = math.floor(tonumber(element.text))
							end
						end,
					}
				},
			},

			FormPanel{
				text = 'Strength Req.:',
				types = {'Armor'},
				child = gui.Input{
					id = 'armor-strength-req-input',

					events = {
						refresh = function(element)
							if element.parent:HasClass('collapsed-anim') then
								return
							end
							if document:has_key('strength') then
								element.text = tostring(document.strength)
							else
								element.text = ''
							end
						end,
						change = function(element)
							if tonumber(element.text) ~= nil then
								document.strength = math.floor(tonumber(element.text))
							else
								document.strength = nil
							end

							element:FireEvent('refresh') --normalize the value.
						end,
					}
				},
			},

			FormPanel{
				text = 'Effect on Stealth:',
				types = {'Armor'},
				child = gui.Dropdown{
					id = 'armor-stealth-effect-input',

					options = armor.possibleStealth,

					events = {
						refresh = function(element)
							if element.parent:HasClass('collapsed-anim') then
								return
							end
							element.optionChosen = document.stealth
						end,
						change = function(element)
							document.stealth = element.optionChosen
						end,
					}
				},
			},

			FormPanel{
				text = 'Dex. Mod. Limit:',
				types = {'Armor'},
				child = gui.Input{
					id = 'armor-dex-mod-limit-input',

					events = {
						refresh = function(element)
							if element.parent:HasClass('collapsed-anim') then
								return
							end

							if document:has_key('dexterityLimit') then
								element.text = tostring(document.dexterityLimit)
							else
								element.text = ''
							end
						end,
						change = function(element)
							if tonumber(element.text) ~= nil then
								document.dexterityLimit = math.floor(tonumber(element.text))
							else
								document.dexterityLimit = nil
							end

							element:FireEvent('refresh') --normalize the value.
						end,
					}
				},
			},

			--shield-specific fields.
			FormPanel{
				text = 'AC Modifier:',
				types = {'Shield'},
				child = gui.Input{
					id = 'shield-armor-class-modifier-input',

					events = {
						refresh = function(element)
							if element.parent:HasClass('collapsed-anim') then
								return
							end
							element.text = tostring(document.armorClassModifier)
						end,
						change = function(element)
							if tonumber(element.text) ~= nil then
								document.armorClassModifier = math.floor(tonumber(element.text))
							end

							element:FireEvent('refresh') --normalize the value.
						end,
					}
				},
			},


			--weapon-specific fields.
			FormPanel{
				text = 'Bonus to Hit:',
				types = {'Weapon'},
				child = gui.Input{
					id = 'weapon-bonus-input',
					events = {
						refresh = function(element)
							element.text = tostring(document:try_get('hitbonus', 0))
						end,
						change = function(element)
							document.hitbonus = tonumber(element.text) or nil
						end,
					},
				},
			},
			FormPanel{
				text = 'Damage:',
				types = {'Weapon'},
				child = gui.Input{
					id = 'weapon-damage-input',

					events = {
						refresh = function(element)
							element.text = tostring(document:try_get('damage', 1))
						end,
						change = function(element)
							document.damage = element.text
						end,
					}
				},
			},

			FormPanel{
				text = 'Versatile Damage:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Weapon' or document.hands ~= 'Versatile'),
				},
				child = gui.Input{
					id = 'weapon-versatile-damage-input',

					events = {
						refresh = function(element)
							element.text = tostring(document:try_get('versatileDamage', ''))
							element.parent:SetClass('collapsed-anim', document.type ~= 'Weapon' or document.hands ~= 'Versatile')
						end,
						change = function(element)
							document.versatileDamage = element.text
						end,
					}
				},
			},

			FormPanel{
				text = 'Range:',
				classes = {
					['collapsed-anim'] = (document.type ~= 'Weapon' or not document:IsRanged()),
				},
				child = gui.Input{
					id = 'weapon-range-input',
					events = {
						refresh = function(element)
							element.text = tostring(document:try_get('range', ''))
							element.parent:SetClass('collapsed-anim', document.type ~= 'Weapon' or not document:IsRanged())
						end,
						change = function(element)
							document.range = element.text
						end,
					}
				},
			},

			FormPanel{
				text = "Ammo:",
				classes = {
					['collapsed-anim'] = (document.type ~= 'Weapon' or not document:HasProperty('ammo')),
				},
				child = gui.Dropdown{
					options = EquipmentCategory.ammunitionOptions,
					idChosen = document:try_get("ammunitionType"),

					refresh = function(element)
						element.idChosen = document:try_get("ammunitionType")
						element.parent:SetClass("collapsed-anim", (document.type ~= 'Weapon' or not document:HasProperty('ammo')))
					end,

					change = function(element)
						document.ammunitionType = element.idChosen
						if document.ammunitionType == "none" then
							document.ammunitionType = nil
						end
						Refresh()
					end,
				},
			},

			FormPanel{
				text = 'Damage Type:',
				types = {'Weapon'},
				child = gui.Dropdown{
					id = 'weapon-damage-type',
					options = rules.damageTypesAvailable,
					optionChosen = document:try_get('damageType', 'slashing'),

					events = {
						refresh = function(element)
							element.optionChosen = document:try_get('damageType', 'slashing')
						end,
						
						change = function(element)
							document.damageType = element.optionChosen
							Refresh()
						end,
					}
				},
			},

			FormPanel{
				text = '',
				types = {'Weapon'},
				child = gui.Check{
					id = 'weapon-magical-damage-checkbox',
					text = 'Magical Damage',
					style = {
						height = 40,
						width = '40%',
						fontSize = '60%',
					},

					events = {
						refresh = function(element)
							element.value = document:has_key('damageMagical')
						end,
						
						change = function(element)
							if element.value then
								document.damageMagical = true
							else
								document.damageMagical = nil
							end
						end,
					}
				},
			},

			FormPanel{
			},

			FormPanel{
				text = 'Hands:',
				types = {'Weapon'},
				child = gui.Dropdown{
					id = 'weapon-hands-dropdown',
					options = weapon.handOptions,
					optionChosen = document:try_get('hands', 'One-handed'),

					events = {
						refresh = function(element)
							element.optionChosen = document:try_get('hands', 'One-handed')
						end,
						
						change = function(element)
							document.hands = element.optionChosen
							Refresh()
						end,
					}

				},
			},

			FormPanel{
				text = 'Properties:',
				collapse = function()
					return not document:IsEquippable()
				end,
				child = gui.Dropdown{
					id = 'weapon-properties-dropdown',

					textOverride = "Add Property...",

					events = {
						refresh = function(element)
							if document:IsEquippable() then
								local options = DataTables.tbl_Gear.GetAvailableProperties(document)
								element.options = options
							end
						end,
						
						change = function(element)
							document:SetProperty(element.idChosen, true)
							element.options = DataTables.tbl_Gear.GetAvailableProperties(document)
							Refresh()
						end,
					}
				},
			},

			gui.Panel{
				style = { flow = 'horizontal', wrap = true, width = '100%', height = 'auto' },
				data = {
					panels = {},
				},
				events = {
					refresh = function(element)
						if (not document:IsEquippable()) or document:try_get("properties") == nil then
							element.children = {}
							element.data.panels = {}
							return
						end

						local newPanels = {}
						local children = {}

						for k,p in pairs(document.properties) do
							local prop = WeaponProperty.Get(k)

							local newPanel = element.data.panels[k] or gui.Panel{
								bgimage = 'panels/square.png',
								selfStyle = { pad = 6 },
								classes = {'property-panel'},
								data = {
									ord = prop.name
								},
								styles = {
									{ cornerRadius = 8, bgcolor = '#000000ff', color = 'white', height = 'auto', width = 'auto', flow = 'horizontal', wrap = false },
									{
										selectors = 'hover',
										bgcolor = '#222222ff',
									},
									{
										selectors = 'pressed',
										bgcolor = '#111111ff',
									},
								},
								events = {
								},
								children = {
									gui.Label{
										style = {width = 'auto', height = 'auto', halign = 'center'},
										text = prop.name,
									},

									gui.Panel{
										width = "auto",
										height = "auto",
										flow = "horizontal",

										create = function(element)
											if not prop.hasValue then
												return
											end

											element.children = {
												gui.Label{
													fontSize = 18,
													valign = "center",
													hmargin = 4,
													color = "white",
													width = "auto",
													height = "auto",
													minWidth = 10,
													create = function(element)
														element:FireEvent("refreshValue")
													end,
													refreshValue = function(element)
														local val = document.properties[k]
														if val ~= nil then
															local n = 1
															if type(val) == "table" then
																n = val.value or 1
															end

															element.text = tostring(n)
														end
													end,
												},

												gui.Panel{
													flow = "none",
													hmargin = 8,
													width = 16,
													height = 16,
													gui.PagingArrow{
														y = -8,
														rotate = 90,

														click = function(element)
															local val = document.properties[k]
															if type(val) ~= "table" then
																val = {value = 1}
															end

															val.value = math.max(1, (val.value or 1) + 1)
															document.properties[k] = val
															element.parent.parent:FireEventTree("refreshValue")
														end,

													},
													gui.PagingArrow{
														y = 8,
														rotate = -90,
														click = function(element)
															local val = document.properties[k]
															if type(val) ~= "table" then
																val = {value = 1}
															end

															val.value = math.max(1, (val.value or 1) - 1)
															document.properties[k] = val
															element.parent.parent:FireEventTree("refreshValue")
														end,
													},
												}
											}

										end,
									},

									gui.Panel{
										bgimage = 'ui-icons/close.png',
										styles = {
											{
												halign = 'center',
												valign = 'center',
												bgcolor = 'grey',
												width = 16,
												height = 16,
												hmargin = 2,
											},
											{
												selectors = {'hover'},
												bgcolor = 'red',
												transitionTime = 0.2,
											},
										},

										click = function(element)
											document:RemoveProperty(prop.id)
											Refresh()
										end
									},
								}
							}

							children[#children+1] = newPanel
							newPanels[k] = newPanel
						end

						table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

						element.children = children
						element.data.panels = newPanels
					end,
				}
			},

		}
	}

	local iconEffectPanel = gui.Panel{
		style = { width = '100%', height = '100%', bgcolor = 'white' },
		selfStyle = {},
	}

	local UpdateIconEffectPanel = function()
		local iconEffect = document:try_get('iconEffect', 'none')
		iconEffectPanel:SetClass('hidden', iconEffect == 'none')
		if iconEffect ~= 'none' then
			local effect = ItemEffects[iconEffect]
			iconEffectPanel.bgimage = effect.video
			iconEffectPanel.selfStyle.opacity = effect.opacity or 1

			iconEffectPanel.bgimageMask = cond(effect.mask, document:GetIcon())
		end

	end

	UpdateIconEffectPanel()
	
	local rightPanel = gui.Panel{
		style = {
			width = '45%',
			height = 'auto',
			halign = 'center',
			flow = 'vertical',
		},

		children = {

			gui.Panel{
				style = {
					width = 128,
					height = 128,
					flow = 'none',
				},
				children = {
					gui.IconEditor{
						style = { bgcolor = 'white', width = 128, height = 128 },
						value = document.iconid,
						events = {
							change = function(element)
								if document:has_key("consumable") then
									--if we have a consumable ability then remap its icon with ours.
									if document.consumable.iconid == document.iconid then
										document.consumable.iconid = element.value
									end
								end

								if document:has_key("itemObjectId") then
									local asset = assets:GetObjectNode(document.itemObjectId)
										printf("RAW:: TRY GET ASSET...")
									if asset ~= nil then
										printf("RAW:: GET ASSET...")
										asset.imageId = dmhub.GetRawImageId(element.value)
										asset:Upload()
									end

								end

								document.iconid = element.value


								UpdateIconEffectPanel()
							end,
						},
					},
					iconEffectPanel,
				}
			},

			--this allowed us to select from different effects to put on items.
			--removed for now until we make our effects system decent.
		--gui.Dropdown{
		--	options = ItemEffectsDropdownOptions(),
		--	idChosen = document:try_get('iconEffect', 'none'),
		--	selfStyle = {
		--		halign = 'center',
		--	},
		--	style = {
		--		width = 200,
		--		height = 50,
		--	},
		--	events = {
		--		change = function(element)
		--			if element.idChosen == 'none' then
		--				document.iconEffect = nil
		--			else
		--				document.iconEffect = element.idChosen
		--			end
		--			UpdateIconEffectPanel()
		--		end,
		--	},
		--},

			gui.Panel{
				vmargin = 4,
				flow = "horizontal",
				width = "100%",
				height = "auto",
				gui.Label{
					fontSize = 18,
					width = "auto",
					height = "auto",
					text = "Accessory:",
				},
				gui.Dropdown{
					options = emojiOptions,
					idChosen = document:try_get("accessory", "none"),
					selfStyle = {
						halign = 'center',
					},
					style = {
						width = 200,
						height = 50,
					},
					change = function(element)
						if element.idChosen == 'none' then
							document.accessory = nil
						else
							document.accessory = element.idChosen
						end
					end,
				},
			},

			gui.Check{
				text = 'Has Inspection Image',
				style = {
					height = 40,
					width = '40%',
					fontSize = '60%',
				},
				refresh = function(element)
					element.value = document:has_key('inspectionImage')
				end,

				change = function(element)
					document.inspectionImage = cond(element.value, '')
					resultPanel:FireEventTree('refresh')
				end,
			},


			gui.Panel{
				classes = {cond(not document:has_key("inspectionImage"), "collapsed")},
				refresh = function(element)
					element:SetClass("collapsed", not document:has_key('inspectionImage'))
				end,
				style = {
					width = 128,
					height = 128,
					flow = 'none',
				},
				children = {
					gui.IconEditor{
						style = { bgcolor = 'white', width = 128, height = 128 },
						value = document:try_get("inspectionImage", ""),
						events = {
							change = function(element)
								document.inspectionImage = element.value
							end,
						},
					},
					iconEffectPanel,
				}
			},

			--Item description text area.
			gui.Input{
				selfStyle = { width = 400, height = 140, vmargin = 4, halign = 'center', textAlignment = "topleft" },
				placeholderText = "Enter Description...",
				multiline = true,
				text = document.description,
				events = {
					change = function(element)
						document.description = element.text
					end,
				}
			},

			gui.Check{
				halign = "center",
				height = 40,
				width = '40%',
				fontSize = '60%',

				text = "Display on Token",
				value = document:try_get("displayOnToken", true),
				classes = {
					['collapsed'] = document.iconid == "" or ((not document:CanWield()) and (not document:try_get("equipOnBelt", false)))
				},
				refresh = function(element)
					element:SetClass("collapsed", document.iconid == "" or ((not document:CanWield()) and (not document:try_get("equipOnBelt", false))))
				end,

				change = function(element)
					document.displayOnToken = element.value
					Refresh()
				end,
			},

			gui.PrettyButton{
				width = 160,
				height = 50,
				text = "Edit Object",
				classes = {
					['collapsed'] = (not document:try_get("displayOnToken", true)) or ((not document:CanWield()) and (not document:try_get("equipOnBelt", false)))
				},
				refresh = function(element)
					element:SetClass("collapsed", (not document:try_get("displayOnToken", true)) or ((not document:CanWield()) and (not document:try_get("equipOnBelt", false))))
				end,

				click = function(element)
					EnsureWieldObject(
						function()
							dmhub.EditObjectDialog({document.itemObjectId})
						end
					)

				end,
			},

			--ammo preview panel.
			gui.Panel{
				id = "ammoPreviewPanel",
				width = 400,
				height = "auto",
				flow = "vertical",
				classes = {
					['collapsed-anim'] = (document:has_key("equipmentCategory") == false or not EquipmentCategory.quantityCategories[document.equipmentCategory]) and not document:HasProperty("thrown"),
				},
				refresh = function(element)
					element:SetClass('collapsed-anim', (document:has_key("equipmentCategory") == false or not EquipmentCategory.quantityCategories[document.equipmentCategory]) and not document:HasProperty("thrown"))
					if element:HasClass("collapsed-anim") then
						element:FireEvent("destroy")
					elseif element.data.previewFloor == nil then
						local previewFloor = game.currentMap:CreatePreviewFloor("ObjectPreview")
						previewFloor.cameraPos = {x = -20, y = 0}
						previewFloor.cameraSize = 1
						element.data.previewFloor = previewFloor

						local previewObj = Projectile.CreateProjectileObj(previewFloor, document, -20, 0)

						local fieldMap = {}
						local fieldList = previewObj:GetComponent("Core").fields
						for _,field in ipairs(fieldList) do
							fieldMap[field.id] = field
						end

						element.data.fields = fieldMap

						game.Refresh{
							currentMap = true,
							floors = {previewFloor.floorid},
							tokens = {},
						}

						local children = element.children
						children[1].bgimage = string.format("#MapPreview%s", previewFloor.floorid)

					end

					if element.data.fields ~= nil then
						element.data.fields["scale"].currentValue = document:try_get("projectileScale", Projectile.DefaultScale)
						element.data.fields["rotation"].currentValue = document:try_get("projectileRotation", 0)
					end
				end,

				destroy = function(element)
					if element.data.previewFloor ~= nil then
						game.currentMap:DestroyPreviewFloor(element.data.previewFloor)
						game.Refresh()
						element.data.previewFloor = nil
						element.data.previewObj = nil
						element.data.fields = nil
					end
				end,

				data = {
					previewFloor = nil,
					previewObj = nil,
					fields = nil,
				},

				gui.Panel{
					width = 1920/6,
					height = 1080/6,
					cornerRadius = 12,
					bgcolor = "white",
					vmargin = 8,
				},

				FormPanel{
					text = 'Scale:',
					classes = {
					},
					child = gui.Slider{
						id = 'slider-light-inner-radius',
						style = {
							height = 40,
							width = 200,
							fontSize = 14,
						},

						sliderWidth = 140,
						labelWidth = 50,

						minValue = 0,
						maxValue = 1,
						value = document:try_get("projectileScale", Projectile.DefaultScale),

						events = {
							refresh = function(element)
								element.value = document:try_get("projectileScale", Projectile.DefaultScale)
							end,
							
							change = function(element)
								document.projectileScale = element.value
								Refresh()
							end,
						}
					},
				},

				FormPanel{
					text = 'Rotation:',
					classes = {
					},
					child = gui.Slider{
						id = 'slider-light-inner-radius',
						style = {
							height = 40,
							width = 200,
							fontSize = 14,
						},

						sliderWidth = 140,
						labelWidth = 50,

						minValue = 0,
						maxValue = 360,
						value = document:try_get("projectileRotation", 0),

						events = {
							refresh = function(element)
								element.value = document:try_get("projectileRotation", 0)
							end,
							
							change = function(element)
								document.projectileRotation = element.value
								Refresh()
							end,
						}
					},
				},

			},
		},
		
	}

	resultPanel = gui.Panel{
		id = "MainTableGearForm",

		vscroll = true,
		styles = {
			{
				bgcolor = 'black',
				width = 1060,
				height = 800,
				flow = 'vertical',
				fontSize = 18,
				margin = 0,
				valign = 'top',
			},
			{
				selectors = {'dropdown'},
				priority = 3,
				halign = 'left',
				width = 160,
				height = 28,
				valign = 'center',
			},
			{
				selectors = {'input'},
				priority = 3,
				width = 180,
				height = 20,
				halign = 'left',
			},
		},

		children = {
			gui.Label{
				text = options.description or 'Create Item',
				style = {
					width = 'auto',
					height = 'auto',
					textAlignment = 'center',
					fontSize = '200%',
					halign = 'center',
					color = 'white',
				}
			},

			gui.Panel{
				style = {
					width = '100%',
					height = 'auto',
					flow = 'horizontal',
				},
				children = {
					leftPanel,
					rightPanel,
				},
			}
			
		}
	}

	Refresh()

	return resultPanel
end

--[==[ DEAD_CODE - overridden by Draw Steel UI\DSInventoryEditor.lua:2137
function DataTables.tbl_Gear.GenerateForm(dialog, document)

	local description = 'Create Item'

	if dialog.isCreating == false then
		description = 'Edit Item'
	end
	dialog.sheet = DataTables.tbl_Gear.GenerateEditor(document, { description = description })
end
--]==]
