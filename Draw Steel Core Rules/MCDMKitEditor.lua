local mod = dmhub.GetModLoading()

local SetKit = function(tableName, kitPanel, kitid)
	local kitTable = dmhub.GetTable(tableName) or {}
	local kit = kitTable[kitid]
	local UploadKit = function()
		dmhub.SetAndUploadTableItem(tableName, kit)
	end

	local children = {}

	children[#children+1] = gui.Panel{
		flow = "vertical",
		width = 196,
		height = "auto",
		floating = true,
		halign = "right",
		valign = "top",
		gui.IconEditor{
		value = kit.portraitid,
		library = "Avatar",
			width = "100%",
		height = "150% width",
		autosizeimage = true,
		allowPaste = true,
		borderColor = Styles.textColor,
		borderWidth = 2,
		change = function(element)
			kit.portraitid = element.value
			UploadKit()
		end,
		},

		gui.Label{
			text = "1000x1500 image",
			width = "auto",
			height = "auto",
			halign = "center",
			color = Styles.textColor,
			fontSize = 12,
		}
	}


	--the name of the kit.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = kit.name,
			change = function(element)
				kit.name = element.text
				UploadKit()
			end,
		},
	}

	children[#children+1] = gui.Input{
		fontSize = 14,
		vmargin = 4,
		width = 600,
		minHeight = 30,
		height = 'auto',
		multiline = true,
		text = kit.description,
		textAlignment = "topleft",
		placeholderText = "Enter kit description...",
		change = function(element)
			kit.description = element.text
			UploadKit()
		end,
	}

	--whether the kit has an implement
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Check{
			text = "Has Implement",
			value = kit.implement,
			change = function(element)
				kit.implement = element.value
				UploadKit()
			end,
		}
	}

	children[#children+1] = gui.Dropdown{
		vmargin = 4,
		idChosen = kit.type,
		options = Kit.kitTypes,
		change = function(element)
			kit.type = element.idChosen
			UploadKit()
			element.parent:FireEventTree("changeType")
		end,
	}

	for _,damageBonus in ipairs(Kit.damageBonusTypes) do
		children[#children+1] = gui.Panel{
			classes = {'formPanel', cond(damageBonus.kitType ~= kit.type and (not Kit.lockedKitTypes[kit.type]), "collapsed")},
			changeType = function(element)
				element:SetClass("collapsed", damageBonus.kitType ~= kit.type and (not Kit.lockedKitTypes[kit.type]))
			end,
			gui.Label{
				text = string.format("%s Damage Bonus:", damageBonus.text),
				minFontSize = 10,
				valign = 'center',
				minWidth = 240,
			},
			gui.Input{
				text = kit:FormatDamageBonus(damageBonus.id) or "+0/+0/+0",
				change = function(element)
					local match = regex.MatchGroups(element.text, Kit.damageBonusMatchPattern)
					if match ~= nil then
						kit:DamageBonuses()[damageBonus.id] = {tonumber(match.tier1), tonumber(match.tier2), tonumber(match.tier3)}
					end

					element.text = kit:FormatDamageBonus(damageBonus.id) or "+0/+0/+0"

					UploadKit()
				end,
			},
		}
	end

	children[#children+1] = gui.Multiselect{
		value = kit.weapons,
		options = Kit.weaponTypes,
		addItemText = "Add Weapon...",
		change = function(element, value)
			kit.weapons = value
			UploadKit()
		end,
	}

	children[#children+1] = gui.Dropdown{
		idChosen = kit.armor,
		options = Kit.armorTypes,
		change = function(element)
			kit.armor = element.idChosen
			UploadKit()
		end,
	}

	local stats = {
		{ id = "health", text = "Health" },
		{ id = "speed", text = "Speed" },
		{ id = "damage", text = "Damage" },
		{ id = "range", text = "Range" },
		{ id = "reach", text = "Reach" },
		{ id = "area", text = "Area" },
		{ id = "stability", text = "Stability" },
		{ id = "disengage", text = "Disengage" },
	}

	for _,stat in ipairs(stats) do
		children[#children+1] = gui.Panel{
			classes = {'formPanel'},
			gui.Label{
				text = string.format("%s:", stat.text),
				valign = 'center',
				minWidth = 240,
			},

			gui.Input{
				text = kit[stat.id],
				change = function(element)
					local n = tonumber(element.text)
					if n ~= nil then
						n = round(n)
						kit[stat.id] = n
					end

					element.text = kit[stat.id]

					UploadKit()
				end,
			},
		}
	end


	children[#children+1] = gui.Button{
		text = "Signature Ability",
		width = 180,
		height = 24,
		vmargin = 4,
		fontSize = 18,
		click = function(element)
			local fn = function(element, kit, savefn)
				if kit.signatureAbility == false then
					kit.signatureAbility = ActivatedAbility.Create()
				end
				element.root:AddChild(kit.signatureAbility:ShowEditActivatedAbilityDialog{
					close = function(element)
						UploadKit()
					end,
				})	
			end

			element.root:FireEventTree("editCompendiumFeature", kit, fn)

			fn(element, kit)
		end,
	}

	children[#children+1] = kit:GetClassLevel():CreateEditor(kit, 0, {
		width = 800,
		change = function(element)
			kitPanel:FireEvent("change")
			UploadKit()
		end,
	})
	kitPanel.children = children
end

function Kit.CreateEditor()
	local kitPanel
	kitPanel = gui.Panel{
		data = {
			SetKit = function(tableName, kitid)
				SetKit(tableName, kitPanel, kitid)
			end,
		},
		vscroll = true,
		classes = 'class-panel',
		styles = {
			{
				halign = "left",
			},
			{
				classes = {'class-panel'},
				width = 1200,
				height = '90%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
			{
				classes = {'label'},
				color = 'white',
				fontSize = 22,
				width = 'auto',
				height = 'auto',
			},
			{
				classes = {'input'},
				width = 200,
				height = 26,
				fontSize = 18,
				color = 'white',
			},
			{
				classes = {'formPanel'},
				flow = 'horizontal',
				width = 'auto',
				height = 'auto',
				halign = 'left',
				vmargin = 2,
			},

		},
	}

	return kitPanel
end


local ShowKitsPanel = function(parentPanel)
	local tableName = Kit.tableName

	local kitPanel = Kit.CreateEditor()

	local itemsListPanel = nil

	local kitItems = {}

	itemsListPanel = gui.Panel{
		classes = {'list-panel'},
		vscroll = true,
		monitorAssets = true,
		refreshAssets = function(element)


			local children = {}
			local kitsTable = dmhub.GetTable(tableName) or {}
			local newKitItems = {}

			local kitTypeOrd = {}
			for i,v in ipairs(Kit.kitTypes) do
				kitTypeOrd[v.id] = i

				--heading for kit section.
				children[#children+1] = kitItems[i] or gui.Label{
					fontSize = 18,
					bold = true,
					width = "auto",
					height = "auto",
					hmargin = 4,
					text = v.text,
					color = "white",
					data = {
						ord = string.format("%d", i),
					},
				}

				newKitItems[i] = children[#children]
			end

			for k,item in pairs(kitsTable) do
				newKitItems[k] = kitItems[k] or Compendium.CreateListItem{
					select = element.aliveTime > 0.2,
					tableName = tableName,
					key = k,
                    imported = item:try_get("imported"),
					click = function()
						kitPanel.data.SetKit(tableName, k)
					end,
				}

				print("KitType: ", item.type, kitTypeOrd[item.type], "FROM", json(kitTypeOrd))
				newKitItems[k].data.ord = string.format("%d-%s", kitTypeOrd[item.type] or 1, item.name)
				newKitItems[k].text = item.name

				children[#children+1] = newKitItems[k]
			end

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)

			kitItems = newKitItems
			itemsListPanel.children = children
		end,
	}

	itemsListPanel:FireEvent('refreshAssets')

	local leftPanel = gui.Panel{
		selfStyle = {
			flow = 'vertical',
			height = '100%',
			width = 'auto',
		},

		itemsListPanel,
		Compendium.AddButton{

			click = function(element)
				dmhub.SetAndUploadTableItem(tableName, Kit.CreateNew{
				})
			end,
		}
	}

	parentPanel.children = {leftPanel, kitPanel}
end

Compendium.Register{
	section = "Character",
	text = 'Kits',
	contentType = "kits",
	click = function(contentPanel)
		ShowKitsPanel(contentPanel)
	end,
}
