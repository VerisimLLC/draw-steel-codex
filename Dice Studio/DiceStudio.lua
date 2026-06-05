local mod = dmhub.GetModLoading()

local CreateDiceStudioPanel

print("DiceStudio:: Register")
DockablePanel.Register{
	name = "Dice Studio",
	icon = "ui-icons/d8.png",
	vscroll = true,
	minHeight = 100,
	content = function()
        print("DiceStudio:: CreatePanel")
		return CreateDiceStudioPanel()
	end,
}

local function RefreshDice()
	local save = dmhub.GetSettingValue("diceequipped")
	dmhub.SetSettingValue("diceequipped", "xxx")
	dmhub.SetSettingValue("diceequipped", save)
	dicestudio:UpdateMaterial()
end

-- Favorite particle effects: a per-user set of effect names hearted in the particle picker.
-- Stored as a map {name = true} in a preference setting; surfaced via the heart toggle on each
-- browser tile and the /favoriteeffects chat macro.
local g_favoriteEffectsSetting = setting{
	id = "diceeffects:favorites",
	default = {},
	storage = "preference",
}

local function GetFavoriteEffects()
	local t = dmhub.GetSettingValue("diceeffects:favorites")
	if type(t) ~= "table" then
		return {}
	end
	return t
end

local function IsFavoriteEffect(name)
	return GetFavoriteEffects()[name] == true
end

local function ToggleFavoriteEffect(name)
	local current = GetFavoriteEffects()
	local copy = {}
	for k,v in pairs(current) do
		copy[k] = v
	end
	if copy[name] then
		copy[name] = nil
	else
		copy[name] = true
	end
	dmhub.SetSettingValue("diceeffects:favorites", copy)
end

Commands.RegisterMacro{
	name = "favoriteeffects",
	summary = "List favorite particle effects",
	doc = "Usage: /favoriteeffects\nPrints the particle effects you have hearted in the Dice Studio picker.",
	command = function(str)
		local favs = GetFavoriteEffects()
		local names = {}
		for name,v in pairs(favs) do
			if v then
				names[#names+1] = name
			end
		end
		table.sort(names)
		if #names == 0 then
			chat.Send("No favorite effects yet. Open the Dice Studio particle picker and click the heart on the effects you want.")
			return
		end
		chat.Send("Favorite effects (" .. #names .. "):\n" .. table.concat(names, "\n"))
	end,
}

local g_builtinFields = {
	{
		type = "Texture",
		name = "_SurfaceTexture",
		description = "Surface Texture",
	},
	{
		type = "Texture",
		flag = "_UseMatcap",
		name = "_MatcapTexture",
		description = "Matcap Texture",
		library = "Matcap",
	},
	{
		type = "Texture",
		name = "_SurfaceNormals",
		description = "Normal Map",
		library = "Normal",
	},
	{
		type = "Float",
		name = "_SurfaceNormalStrength",
		description = "Normal Strength",
		default = 1,
	},
	{
		type = "Color",
		name = "_SurfaceTint",
		description = "Surface Tint",
	},
	{
		type = "Color",
		name = "_CageTint",
		description = "Border Tint",
	},
	{
		type = "Color",
		name = "_FontTint",
		description = "Font Tint",
	},
	-- Font Brightness self-illuminates the number in its Font Tint color, so the
	-- normal (non-rolling) display can read brighter than the dice-scene lighting
	-- alone allows. Separate from "Font Glow", which is the programmatic landing
	-- result glow. 0 = lit by scene only (original look).
	{
		type = "Range",
		name = "_FontBrightness",
		description = "Font Brightness",
		min = 0,
		max = 2,
	},
	{
		type = "Color",
		name = "_FontGlowColor",
		description = "Font Glow",
	},
	{
		type = "Float",
		name = "_SurfaceMetallic",
		description = "Surface Metallic",
	},
	{
		type = "Float",
		name = "_CageMetallic",
		description = "Border Metallic",
	},
	{
		type = "Float",
		name = "_FontMetallic",
		description = "Font Metallic",
	},
	{
		type = "Float",
		name = "_SurfaceSmoothness",
		description = "Surface Smoothness",
	},
	{
		type = "Float",
		name = "_CageSmoothness",
		description = "Border Smoothness",
	},
	{
		type = "Float",
		name = "_FontSmoothness",
		description = "Font Smoothness",
	},
	{
		type = "Float",
		name = "_CageNormalStrength",
		description = "Border Extrusion",
	},
	{
		type = "Float",
		name = "_FontNormalStrength1",
		description = "Font Extrusion",
		default = 1,
	},
	{
		type = "Float",
		name = "_MasterAlpha",
		description = "Master Alpha",
		default = 1,
	},
}

local g_materialFields = {
	MatCapDiceMaterial = {
		{
			name = "_MatcapColor",
			type = "Color",
			description = "Color",
		},

		{
			name = "_MatcapBorder",
			description = "Border",
			type = "Range",
			min = 0,
			max = 5,
		},

		{
			name = "_Matcap",
			type = "Texture",
			library = "Matcap",
			description = "MatCap",
		},

		{
			name = "_MatcapMask",
			type = "Texture",
			library = "TextureMask",
			description = "Mask",
		},

		{
			name = "_Matcap0NormalMap",
			--flag = "_Matcap0CustomNormal",
			type = "Texture",
			library = "Normal",
			description = "Normal Map",
		},

		{
			name = "_Matcap0NormalMapScale",
			type = "Range",
			description = "Normal Scale",
		},

		{
			name = "_MatcapHueShift",
			description = "Hue Shift",
			type = "Range",
			min = 0,
			max = 1,
		},
		{
			name = "_MatcapEmissionStrength",
			description = "Emission",
			type = "Range",
			min = 0,
			max = 20,
		},
		{
			name = "_MatcapIntensity",
			description = "Intensity",
			type = "Range",
			min = 0,
			max = 5,
			default = 1,
		},

		{
			name = "_MatcapReplace",
			description = "Replace",
			type = "Range",
			min = 0,
			max = 1,
			default = 1,
		},

		{
			name = "_MatcapMultiply",
			description = "Multiply",
			type = "Range",
			min = 0,
			max = 1,
			default = 0,
		},

		{
			name = "_MatcapAdd",
			description = "Add",
			type = "Range",
			min = 0,
			max = 1,
			default = 0,
		},

		{
			name = "_Matcap2Enable",
			description = "Use Matcap2",
			type = "Bool",
		},

		{
			name = "_Matcap2",
			type = "Texture",
			library = "Matcap",
			description = "MatCap",
			requires = "_Matcap2Enable",
		},

		{
			name = "_Matcap2Mask",
			type = "Texture",
			library = "TextureMask",
			description = "Mask",
			requires = "_Matcap2Enable",
		},

		{
			name = "_Matcap1NormalMap",
			--flag = "_Matcap1CustomNormal",
			requires = "_Matcap2Enable",
			type = "Texture",
			library = "Normal",
			description = "Normal Map",
		},

		{
			name = "_Matcap1NormalMapScale",
			requires = "_Matcap1CustomNormal",
			requires = "_Matcap2Enable",
			type = "Range",
			description = "Normal Scale",
		},



		{
			name = "_Matcap2HueShift",
			description = "Hue Shift",
			type = "Range",
			min = 0,
			max = 1,
			requires = "_Matcap2Enable",
		},
		{
			name = "_Matcap2EmissionStrength",
			description = "Emission",
			type = "Range",
			min = 0,
			max = 20,
			requires = "_Matcap2Enable",
		},
		{
			name = "_Matcap2Intensity",
			description = "Intensity",
			type = "Range",
			min = 0,
			max = 5,
			requires = "_Matcap2Enable",
		},

		{
			name = "_Matcap2Replace",
			description = "Replace",
			type = "Range",
			min = 0,
			max = 1,
			default = 1,
			requires = "_Matcap2Enable",
		},

		{
			name = "_Matcap2Multiply",
			description = "Multiply",
			type = "Range",
			min = 0,
			max = 1,
			default = 0,
			requires = "_Matcap2Enable",
		},

		{
			name = "_Matcap2Add",
			description = "Add",
			type = "Range",
			min = 0,
			max = 1,
			default = 0,
			requires = "_Matcap2Enable",
		},




	}

}

local CreateDicePanel

-- Builds a panel that edits the tuned shader properties of a dice material.
-- opts identifies which material's properties this panel edits:
--   opts.matid    -- a built-in/default material category ("builtin", "material", "text").
--   opts.numFaces -- a per-die-type surface material override (4, 6, 8, 10, 12, 20).
-- Exactly one of matid / numFaces should be set. opts.propertiesOverride supplies an
-- explicit field list (used by the builtin material whose fields are hand-authored).
local CreateMaterialPropertiesPanel = function(opts)
	local matid = opts.matid
	local numFaces = opts.numFaces
	local propertiesOverride = opts.propertiesOverride

	-- The DiceMaterialStudioProperties this panel edits: a per-die-type override
	-- when numFaces is set, otherwise the default material identified by matid.
	local GetProps = function()
		if numFaces ~= nil then
			return dicestudio:GetMaterialPropertiesForType(numFaces)
		end
		return dicestudio:GetMaterialProperties(matid)
	end

	-- The DiceMaterialLua backing this panel (used for shader-property discovery
	-- and to look up the hand-authored field list in g_materialFields).
	local GetMat = function()
		if numFaces ~= nil then
			return dicestudio:GetMaterialForType(numFaces)
		end
		return dicestudio:GetMaterial(matid)
	end

	return gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		styles = {
			{
				selectors = {"formLabel"},
				width = 160,
				textOverflow = "truncate",
				fontSize = 12,
			},
		},

		create = function(element)
			element:FireEvent("newmaterial")
		end,

		newmaterial = function(element)
			local studio = dicestudio
			local children = {}

			local mat = GetMat()
			local key = ""
			if mat ~= nil then
				key = mat.displayName
			end
			local properties = propertiesOverride or g_materialFields[key]
			printf("PROPERTIES:: %s -> %s", matid or numFaces, json(properties ~= nil))
			if properties == nil and mat ~= nil then
				properties = mat:GetProperties()
			end

			properties = properties or {}
			
			for _,p in ipairs(properties) do
				if p.type == "Bool" then

					children[#children+1] = gui.Panel{
						classes = {"formPanel"},
						gui.Check{
							halign = "left",
							text = string.format("%s", p.description),
							value = cond(GetProps():GetFloat(p.name, p.default) ~= 0, true, false),
							change = function(element)
								GetProps():SetFloat(p.name, cond(element.value, 1, 0))
								RefreshDice()
								element.root:FireEventTree("refreshDice")
							end,
						},
					}

				elseif p.type == "Float" or p.type == "Range" then
					printf("DICESET:: mat prop: %s / %s -> %s", matid, p.name, json(GetProps():GetFloat(p.name)))

					children[#children+1] = gui.Panel{
						classes = {"formPanel"},
                    	refreshDice = function(element)
							printf("REFRESHDICE: %s", json(p.requires))
							element:SetClass("collapsed", p.requires ~= nil and GetProps():GetFloat(p.requires) == 0)
						end,
						gui.Label{
							classes = {"formLabel"},
							halign = "left",
							text = string.format("%s:", p.description),
						},
						gui.Slider{
							style = {
								height = 26,
								width = 240,
								fontSize = 14,
							},

							sliderWidth = 180,
							labelWidth = 50,
							minValue = p.min or 0,
							maxValue = p.max or 1,

							value = GetProps():GetFloat(p.name, p.default),
							change = function(element)
								GetProps():SetFloat(p.name, element.value)
								RefreshDice()
							end,
						},
					}

				elseif p.type == "Color" then

					printf("DICESET:: Property %s / %s = %s", matid, p.name, json(GetProps():GetColor(p.name)))
					children[#children+1] = gui.Panel{
						classes = {"formPanel"},
                    	refreshDice = function(element)
							element:SetClass("collapsed", p.requires ~= nil and GetProps():GetFloat(p.requires) == 0)
						end,
						gui.Label{
							classes = {"formLabel"},
							halign = "left",
							text = string.format("%s:", p.description),
						},
						gui.ColorPicker{
							border = 2,
							borderColor = "white",
							width = 16,
							height = 16,
							value = GetProps():GetColor(p.name),
							change = function(element)
								GetProps():SetColor(p.name, element.value)
								RefreshDice()
							end,
						},
					}

				elseif p.type == "Texture" then
					printf("DICESET:: Property Texture %s / %s = %s", matid, p.name, json(GetProps():GetColor(p.name)))
					children[#children+1] = gui.Panel{
						classes = {"formPanel"},
						data = {
							is_array = nil,
						},
                    	refreshDice = function(element)
							element:SetClass("collapsed", p.requires ~= nil and GetProps():GetFloat(p.requires) == 0)

							if element:HasClass("collapsed") then
								return
							end

							local prop = GetProps()
							local is_array = prop:HasTextureArray(p.name)

							if is_array == element.data.is_array then
								return
							end

							element.data.is_array = is_array

							printf("DICE:: Property %s / %s; is_array = %s", json(matid), json(p.name), json(is_array))

							if not is_array then
								element.children = {
									gui.Label{
										classes = {"formLabel"},
										halign = "left",
										text = string.format("%s:", p.description),
									},

									gui.IconEditor{
										border = 2,
										borderColor = "white",
										width = 32,
										height = 32,
										allowNone = true,
										library = p.library or "Textures",
										searchHidden = true,
										categoriesHidden = true,
										value = GetProps():GetTexture(p.name),
										change = function(element)
											GetProps():SetTexture(p.name, element.value)
											if p.flag ~= nil then
												GetProps():SetFloat(p.flag, cond(element.value ~= nil and element.value ~= "", 1, 0))
											end
											RefreshDice()
											element.root:FireEventTree("refreshDice")
										end,
									},

									gui.Button{
										classes = {"tiny"},
										text = "Array",
										width = 50,
										height = 18,
										fontSize = 11,
										hmargin = 8,
										click = function(element)
											local prop = GetProps()
											prop:CreateTextureArray(p.name)
											RefreshDice()
											element.root:FireEventTree("refreshDice")
										end,
									}
								}
							else
								local dicePanels = {}
								local dice = {4,6,8,10,12,20}
								for index,faces in ipairs(dice) do
									dicePanels[#dicePanels+1] = gui.Panel{
										classes = {"formPanel"},
										gui.Label{
											classes = {"formLabel"},
											halign = "left",
											text = string.format("%s d%d:", p.description, faces),
										},

										gui.IconEditor{
											border = 2,
											borderColor = "white",
											width = 32,
											height = 32,
											allowNone = true,
											library = p.library or "Textures",
											searchHidden = true,
											categoriesHidden = true,
											value = GetProps():GetTexture(p.name, index),
											change = function(element)
												GetProps():SetTexture(p.name, element.value, index)
												if p.flag ~= nil then
													GetProps():SetFloat(p.flag, cond(element.value ~= nil and element.value ~= "", 1, 0))
												end
												RefreshDice()
												element.root:FireEventTree("refreshDice")
											end,
										},
									}
								end

								local children = {
									gui.Panel{
										classes = {"formPanel"},
										gui.Label{
											classes = {"formLabel"},
											halign = "left",
											text = string.format("%s", p.description),
										},

										gui.Button{
											classes = {"tiny"},
											text = "Remove",
											width = 60,
											height = 18,
											fontSize = 11,
											hmargin = 8,
											click = function(element)
												local prop = GetProps()
												prop:DestroyTextureArray(p.name)
												RefreshDice()
												element.root:FireEventTree("refreshDice")
											end,
										},
									}
								}

								for _,p in ipairs(dicePanels) do
									children[#children+1] = p
								end

								element.children = {
									gui.Panel{
										flow = "vertical",
										width = "100%",
										height = "auto",

										children = children,
									}
								}
							end
						end,

					}
				end
			end

			element.children = children
			element:FireEventTree("refreshDice")
		end,
	}
end


CreateDiceStudioPanel = function()
	local studio = dicestudio
	studio:Activate()

	local materials = studio.availableMaterials
	local materialOptions
	local idToMaterial

	local CalculateMaterialOptions = function()
		materialOptions = {}
		idToMaterial = {}

		materialOptions[#materialOptions+1] = {
			id = "none",
			text = "(None)",
		}

		for _,mat in ipairs(materials) do
			materialOptions[#materialOptions+1] = {
				id = mat.displayName,
				text = mat.displayName,
			}

			idToMaterial[mat.displayName] = mat
		end
	end

	CalculateMaterialOptions()

	local builtinPropertiesPanel = CreateMaterialPropertiesPanel{ matid = "builtin", propertiesOverride = g_builtinFields }
	local materialPropertiesPanel = CreateMaterialPropertiesPanel{ matid = "material" }

	-- Builds one row of the per-die-type surface material override UI: a material
	-- dropdown plus the properties panel for that die type. The dropdown's
	-- "(Default)" entry means "no override -- inherit the default Material above".
	-- d3/d4/d6/d8/d10/d12/d20 each have their own override slot; d100 shares the
	-- d10 slot (see DiceFacesToSurfaceMaterialIndex on the engine side).
	local CreatePerDieMaterialPanel = function(faces)
		-- Forward-declared so the dropdown's change handler can rebuild the whole row.
		local rowPanel

		local propsPanel = CreateMaterialPropertiesPanel{ numFaces = faces }

		-- The default material list with "(None)" swapped for a "(Default)" entry
		-- that clears this die's override.
		local PerDieOptions = function()
			local opts = { { id = "default", text = "(Default)" } }
			for _,o in ipairs(materialOptions) do
				if o.id ~= "none" then
					opts[#opts+1] = o
				end
			end
			return opts
		end

		local initialChoice = "default"
		if studio:HasMaterialForType(faces) then
			initialChoice = studio:GetMaterialForType(faces).displayName
		end

		local dropdown = gui.Dropdown{
			width = 160,
			height = 30,
			fontSize = 14,
			options = PerDieOptions(),
			idChosen = initialChoice,
			newmaterial = function(element)
				CalculateMaterialOptions()
				element.options = PerDieOptions()
				if studio:HasMaterialForType(faces) then
					element.idChosen = studio:GetMaterialForType(faces).displayName
				else
					element.idChosen = "default"
				end
			end,
			change = function(element)
				if element.idChosen == "default" then
					studio:SetMaterialForType(faces, nil)
				else
					studio:SetMaterialForType(faces, idToMaterial[element.idChosen])
				end
				RefreshDice()
				rowPanel:FireEventTree("newmaterial")
			end,
		}

		-- This die's material property editor, kept in a collapsed tree node so
		-- swapping materials never reflows the dropdowns. The node is only shown
		-- once the die has an override; with no override there is nothing to tune.
		local propsWrapper = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			create = function(element)
				element:SetClass("collapsed", not studio:HasMaterialForType(faces))
			end,
			newmaterial = function(element)
				element:SetClass("collapsed", not studio:HasMaterialForType(faces))
			end,
			gui.TreeNode{
				text = string.format("d%d Properties", faces),
				width = "100%",
				contentPanel = propsPanel,
			},
		}

		rowPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = string.format("d%d:", faces),
				},
				dropdown,
			},

			propsWrapper,
		}

		return rowPanel
	end

	local localFiles = dicestudio:GetLocalFiles()

	local diceDropdown = gui.Dropdown{
		width = 160,
		height = 30,
		fontSize = 14,
		options = localFiles,
		idChosen = localFiles[1] and localFiles[1].id,
		create = function(element)
			if localFiles[1] ~= nil then
				element:FireEvent("change")
			end
		end,
		change = function(element)
			studio:Load(element.idChosen)
			RefreshDice()
			element.root:FireEventTree("newmaterial")
			element.root:FireEventTree("refreshDice")
		end,
	}

	local dropdownForm = gui.Panel{
		classes = {"formPanel", cond(#localFiles == 0, "collapsed")},
		gui.Label{
			classes = {"formLabel"},
			halign = "left",
			text = "Dice:",
		},
		diceDropdown,
	}

	local videobg = "#00ff00ff"

	-- Modal browser for picking a particle effect for an event. Each tile shows a live rendered
	-- preview ("#particlepreview:<name>") plus the effect name, paginated and searchable -- same
	-- reusable-tile + refreshSearch + paging pattern as IconEditor. onPick(name) receives the
	-- chosen name ("" clears the binding); the popup closes itself on pick or close.
	local g_particleBrowserPage = {}

	local MakeParticleBrowser
	MakeParticleBrowser = function(owner, eventName, titleText, onPick)
		local COLS, ROWS = 4, 3
		local PAGE = COLS*ROWS
		local PREVIEW = 144
		local TILE_W = 174
		local TILE_H = PREVIEW + 30

		local current = studio:GetEventEffect(eventName)

		local allNames = {}
		for _,n in ipairs(studio:GetEventEffectOptions(eventName)) do
			allNames[#allNames+1] = n
		end
		table.sort(allNames)

		local filtered = {}
		local npage = g_particleBrowserPage[eventName] or 1
		local searchText = ""

		local function Filter()
			filtered = { "" }
			local q = string.lower(searchText)
			for _,n in ipairs(allNames) do
				if q == "" or string.find(string.lower(n), q, 1, true) ~= nil then
					filtered[#filtered+1] = n
				end
			end
		end
		Filter()

		local function NumPages()
			local p = math.ceil(#filtered / PAGE)
			if p < 1 then p = 1 end
			return p
		end

		local function Close()
			owner.popup = nil
		end

		local function MakeTile()
			local m_name = nil
			local thumb = gui.Panel{
				classes = {"effectThumb"},
                bgcolor = "white",
				width = PREVIEW,
				height = PREVIEW,
				halign = "center",
			}
			local nameLabel = gui.Label{
				classes = {"effectTileLabel"},
                textAlignment = "right",
				width = "100%-40",
				height = 26,
                rmargin = 4,
				halign = "center",
				valign = "center",
				fontSize = 11,
			}
			-- Heart toggle: favorites/unfavorites the effect (HaltEventPropagation keeps the click
			-- from also selecting the tile). State reflects the per-user favorites setting.
			local heart = gui.Panel{
				classes = {"favHeart"},
				width = 20,
				height = 20,
				valign = "center",
				styles = {
					{ bgcolor = "white", bgimage = "ui-icons/heartunclicked.png" },
					{ selectors = {"on"}, bgimage = "ui-icons/heartclicked.png" },
					{ selectors = {"hover"}, brightness = 1.6 },
				},
				click = function(element)
					element:HaltEventPropagation()
					if m_name ~= nil and m_name ~= "" then
						ToggleFavoriteEffect(m_name)
						element:SetClass("on", IsFavoriteEffect(m_name))
					end
				end,
			}
			local footer = gui.Panel{
				flow = "horizontal",
				width = "100%",
				height = "auto",
				valign = "bottom",
				children = { nameLabel, heart },
			}
			local tile
			tile = gui.Panel{
				classes = {"effectTile"},
				flow = "vertical",
				width = TILE_W,
				height = TILE_H,
				hmargin = 3,
				vmargin = 3,
				halign = "center",
				data = {
					setName = function(name)
						m_name = name
						if name == "" then
							thumb.bgimage = "panels/square.png"
							thumb.selfStyle.bgcolor = "white"
							nameLabel.text = "(None)"
							heart:SetClass("collapsed", true)
						else
							thumb.bgimage = "#particlepreview:" .. name
							thumb.selfStyle.bgcolor = "white"
							nameLabel.text = name
							heart:SetClass("collapsed", false)
							heart:SetClass("on", IsFavoriteEffect(name))
						end
						tile:SetClass("selected", name == current)
					end,
				},
				children = { thumb, footer },
				click = function(element)
					onPick(m_name)
					Close()
				end,
			}
			return tile
		end

		local tiles = {}
		while #tiles < PAGE do
			tiles[#tiles+1] = MakeTile()
		end

		local grid = gui.Panel{
			width = COLS*(TILE_W+6),
			height = ROWS*(TILE_H+6),
			flow = "horizontal",
			wrap = true,
			halign = "center",
			children = tiles,
			refreshSearch = function(element)
				for i,tile in ipairs(tiles) do
					local nm = filtered[(npage-1)*PAGE + i]
					if nm == nil then
						tile:SetClass("hidden", true)
					else
						tile.data.setName(nm)
						tile:SetClass("hidden", false)
					end
				end
			end,
		}

		local searchInput = gui.SearchInput{
			placeholderText = "Search effects...",
			width = 360,
			height = 28,
			fontSize = 14,
			editlag = 0.2,
			halign = "center",
			change = function(element)
				searchText = element.text or ""
				Filter()
				npage = 1
				g_particleBrowserPage[eventName] = 1
				element.root:FireEventTree("refreshSearch")
			end,
		}

		local pagingPanel = gui.Panel{
			width = "100%",
			height = 32,
			flow = "horizontal",
			halign = "center",
			valign = "center",
			gui.Button{
				text = "<",
				width = 40,
				height = 28,
				fontSize = 16,
                halign = "center",
				click = function(element)
					if npage > 1 then
						npage = npage - 1
						g_particleBrowserPage[eventName] = npage
						element.root:FireEventTree("refreshSearch")
					end
				end,
			},
			-- Editable current-page field: type a page number and press enter to jump.
            gui.Panel{
                flow = "horizontal",
                width = "auto",
                height = "auto",
                halign = "center",
                valign = "center",
                gui.Label{
                    width = 44,
                    height = 24,
                    halign = "center",
                    valign = "center",
                    fontSize = 14,
                    editable = true,
                    textAlignment = "center",
                    characterLimit = 4,
                    refreshSearch = function(element)
                        -- Don't clobber what the user is currently typing.
                        if element.hasInputFocus then
                            return
                        end
                        element.text = tostring(npage)
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil then
                            n = npage
                        end
                        n = math.floor(n)
                        if n < 1 then n = 1 end
                        local maxPage = NumPages()
                        if n > maxPage then n = maxPage end
                        npage = n
                        g_particleBrowserPage[eventName] = npage
                        element.root:FireEventTree("refreshSearch")
                    end,
                },
                gui.Label{
                    width = "auto",
                    height = "auto",
                    halign = "center",
                    valign = "center",
                    fontSize = 14,
                    hmargin = 4,
                    refreshSearch = function(element)
                        element.text = string.format("/ %d", NumPages())
                    end,
                },
            },
			gui.Button{
				text = ">",
				width = 40,
				height = 28,
				fontSize = 16,
                halign = "center",
				click = function(element)
					if npage < NumPages() then
						npage = npage + 1
						g_particleBrowserPage[eventName] = npage
						element.root:FireEventTree("refreshSearch")
					end
				end,
			},
		}

		return gui.Panel{
			classes = {"framedPanel"},
			bgimage = true,
			-- A popup is its own style island, so the global framedPanel cascade does not reach
			-- it -- include Styles.Default so the frame (bgimage/gradient/border) actually renders.
			styles = {
				Styles.Default,
				Styles.Panel,
				{ selectors = {"effectTile"}, borderWidth = 2, borderColor = "clear" },
				{ selectors = {"effectTile", "hover"}, borderColor = "#888888ff" },
				{ selectors = {"effectTile", "selected"}, borderColor = "#f5c518ff" },
				{ selectors = {"effectThumb"}, bgcolor = "white", borderWidth = 1, borderColor = "#000000ff" },
				{ selectors = {"effectTileLabel"}, color = "white" },
			},
			width = 780,
			height = "auto",
			flow = "vertical",
			halign = "center",
			valign = "center",
			pad = 16,
			borderBox = true,
			create = function(element)
				element:FireEventTree("refreshSearch")
			end,
			gui.Label{
				text = titleText,
				width = "auto",
				height = "auto",
				halign = "center",
				fontSize = 18,
				bold = true,
				vmargin = 4,
			},
			searchInput,
			grid,
			pagingPanel,
			gui.CloseButton{
				halign = "right",
				valign = "top",
				floating = true,
				escapeActivates = true,
				click = function(element)
					Close()
				end,
			},
		}
	end

	-- Builds one row of the Particles tree node for a single dice lifecycle event.
	-- Pulse events get a "Test" button that fires the bound prefab on the current
	-- studio preview dice via dicestudio:FirePreviewEffect. State events (RollWaiting,
	-- TravelTail) are already always-attached, so no button. removeFn (optional) adds a
	-- delete button that unbinds the event and removes its row.
	local MakeStageEffectRow = function(eventName, label, pulse, removeFn)
		-- The effect picker: a compact button showing the current effect preview thumbnail and
		-- name; clicking opens the browsable particle picker (MakeParticleBrowser).
		local previewThumb = gui.Panel{
			width = 34,
			height = 34,
			halign = "left",
			valign = "center",
			bgcolor = "white",
		}
		local previewName = gui.Label{
			width = 120,
			height = "auto",
			halign = "left",
			valign = "center",
			hmargin = 6,
			fontSize = 14,
		}
		local function RefreshPreviewButton()
			local cur = studio:GetEventEffect(eventName)
			if cur == "" then
				previewThumb.bgimage = "panels/square.png"
				previewThumb.selfStyle.bgcolor = "white"
				previewName.text = "(None)"
			else
				previewThumb.bgimage = "#particlepreview:" .. cur
				previewThumb.selfStyle.bgcolor = "white"
				previewName.text = cur
			end
		end
		local previewButton = gui.Panel{
			flow = "horizontal",
			width = 170,
			height = 40,
			valign = "center",
			borderWidth = 1,
			borderColor = "#666666ff",
			children = { previewThumb, previewName },
			create = function(element)
				RefreshPreviewButton()
			end,
			newmaterial = function(element)
				RefreshPreviewButton()
			end,
			refreshDice = function(element)
				RefreshPreviewButton()
			end,
			click = function(element)
				element.popup = MakeParticleBrowser(element, eventName, label, function(name)
					studio:SetEventEffect(eventName, name)
					element.root:FireEventTree("refreshDice")
				end)
			end,
		}
		local controlsChildren = { previewButton }
		if pulse then
			controlsChildren[#controlsChildren+1] = gui.Button{
				text = "Test",
				width = 50,
				height = 30,
				fontSize = 12,
				hmargin = 4,
				click = function(element)
					studio:FirePreviewEffect(eventName)
				end,
			}
		end
		controlsChildren[#controlsChildren+1] = gui.Button{
			text = "Raw",
			width = 50,
			height = 30,
			fontSize = 12,
			hmargin = 4,
			click = function(element)
				studio:PlayRawEffect(eventName)
			end,
		}

		if removeFn ~= nil then
			controlsChildren[#controlsChildren+1] = gui.DeleteItemButton{
				width = 16,
				height = 16,
				valign = "center",
				hmargin = 4,
				click = function(element)
					removeFn()
				end,
			}
		end

		--True when an effect is actually bound to this event; the tunable sliders below
		--only have a binding to write to in that case, so the whole block collapses when
		--"(None)" is selected.
		local function HasEffect()
			return studio:GetEventEffect(eventName) ~= ""
		end

		--A labelled slider bound to one of the per-effect tunables. getFn/setFn close over
		--eventName so each row drives this event's binding. Re-reads its value on the
		--newmaterial/refreshDice tree events (fired when the dropdown selection changes).
		local function ParamSlider(slabel, minV, maxV, getFn, setFn)
			return gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = slabel,
				},
				gui.Slider{
					style = { height = 26, width = 240, fontSize = 14 },
					sliderWidth = 150,
					labelWidth = 50,
					minValue = minV,
					maxValue = maxV,
					value = getFn(),
					newmaterial = function(element)
						element.value = getFn()
					end,
					refreshDice = function(element)
						element.value = getFn()
					end,
					change = function(element)
						setFn(element.value)
						RefreshDice()
					end,
				},
			}
		end

		local tunablesPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			lmargin = 12,
			create = function(element)
				element:SetClass("collapsed", not HasEffect())
			end,
			newmaterial = function(element)
				element:SetClass("collapsed", not HasEffect())
			end,
			refreshDice = function(element)
				element:SetClass("collapsed", not HasEffect())
			end,

			ParamSlider("Scale:", 0.1, 4,
				function() return studio:GetEventEffectScale(eventName) end,
				function(v) studio:SetEventEffectScale(eventName, v) end),
			ParamSlider("Speed:", 0.1, 4,
				function() return studio:GetEventEffectSpeed(eventName) end,
				function(v) studio:SetEventEffectSpeed(eventName, v) end),
			ParamSlider("Hue:", 0, 1,
				function() return studio:GetEventEffectHueShift(eventName) end,
				function(v) studio:SetEventEffectHueShift(eventName, v) end),
			ParamSlider("Brightness:", 0.1, 4,
				function() return studio:GetEventEffectBrightness(eventName) end,
				function(v) studio:SetEventEffectBrightness(eventName, v) end),

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = "Tint:",
				},
				gui.ColorPicker{
					border = 2,
					borderColor = "white",
					width = 16,
					height = 16,
					value = studio:GetEventEffectTint(eventName),
					newmaterial = function(element)
						element.value = studio:GetEventEffectTint(eventName)
					end,
					refreshDice = function(element)
						element.value = studio:GetEventEffectTint(eventName)
					end,
					change = function(element)
						studio:SetEventEffectTint(eventName, element.value)
						RefreshDice()
					end,
				},
			},

			-- Rotate the whole effect about its X axis in 90-degree steps, to flip prefabs
			-- authored "z up" vs "y up" so they sit correctly on the dice.
			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = "Rotate X:",
				},
				gui.Dropdown{
					width = 90,
					height = 30,
					fontSize = 14,
					halign = "left",
					options = {
						{ id = "0",   text = "0" },
						{ id = "90",  text = "90" },
						{ id = "180", text = "180" },
						{ id = "270", text = "270" },
					},
					idChosen = tostring(studio:GetEventEffectXRotation(eventName)),
					newmaterial = function(element)
						element.idChosen = tostring(studio:GetEventEffectXRotation(eventName))
					end,
					refreshDice = function(element)
						element.idChosen = tostring(studio:GetEventEffectXRotation(eventName))
					end,
					change = function(element)
						studio:SetEventEffectXRotation(eventName, tonumber(element.idChosen) or 0)
						RefreshDice()
					end,
				},
			},
		}

		return gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = label,
				},
				gui.Panel{
					width = "100%",
					height = "auto",
					flow = "horizontal",
					table.unpack(controlsChildren),
				},
			},

			tunablesPanel,
		}
	end

	-- Canonical dice lifecycle events, in display order, for the Particles node.
	local diceEventList = {
		{ event = "Appearance",  label = "Appearance:",   pulse = true  },
		{ event = "BounceHit",   label = "Bounce Hit:",   pulse = true  },
		{ event = "Disappear",   label = "Disappear:",    pulse = true  },
		{ event = "Reappear",    label = "Reappear:",     pulse = true  },
		{ event = "Exit",        label = "Exit:",         pulse = true  },
		{ event = "RollWaiting", label = "Roll Waiting:", pulse = false },
		{ event = "TravelTail",  label = "Travel Tail:",  pulse = false },
	}

	-- An event row is shown when it has a bound effect OR the user added it this
	-- session (data.added). Removing a row unbinds the event and hides it again.
	local diceEventRows
	diceEventRows = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		data = {
			panels = {},
			added = {},
		},
		create = function(element)
			element:FireEvent("refreshDice")
		end,
		newmaterial = function(element)
			element:FireEvent("refreshDice")
		end,
		refreshDice = function(element)
			local children = {}
			local newPanels = {}
			for _,info in ipairs(diceEventList) do
				if element.data.added[info.event] or studio:GetEventEffect(info.event) ~= "" then
					local panel = element.data.panels[info.event]
					if panel == nil then
						local ev = info.event
						panel = MakeStageEffectRow(ev, info.label, info.pulse, function()
							studio:SetEventEffect(ev, "")
							diceEventRows.data.added[ev] = nil
							diceEventRows.data.panels[ev] = nil
							diceEventRows.root:FireEventTree("refreshDice")
						end)
					end
					newPanels[info.event] = panel
					children[#children+1] = panel
				end
			end
			element.data.panels = newPanels
			element.children = children
		end,
	}

	-- "Add Event..." lists only events not already shown; choosing one reveals its
	-- row so an effect can then be bound to it.
	local addDiceEventControl = gui.Dropdown{
		textOverride = "Add Event...",
		width = 160,
		height = 30,
		fontSize = 14,
		halign = "left",
		vmargin = 6,
		create = function(element)
			local choices = {}
			for _,info in ipairs(diceEventList) do
				if not (diceEventRows.data.added[info.event] or studio:GetEventEffect(info.event) ~= "") then
					choices[#choices+1] = { id = info.event, text = string.gsub(info.label, ":", "") }
				end
			end
			element.options = choices
			element.idChosen = ""
		end,
		refreshDice = function(element)
			element:FireEvent("create")
		end,
		change = function(element)
			if element.idChosen ~= "" then
				diceEventRows.data.added[element.idChosen] = true
				element.root:FireEventTree("refreshDice")
			end
		end,
	}

	local resultPanel

	resultPanel = gui.Panel{
		styles = {
			Styles.Form,
			{
				selectors = {"formPanel"},
				flow = "vertical",
				vmargin = 6,
				lmargin = 12,
			},
			{
				selectors = {"formLabel"},
				minWidth = 0,
				width = "auto",
				halign = "left",
				hmargin = 2,
				fontSize = 14,
			},
			{
				selectors = {"headingLabel"},
				bold = true,
				fontSize = 18,
				width = "auto",
				height = "auto",
			},
		},
		width = "100%",
		height = "auto",
		flow = "vertical",

		gui.Label{
			classes = {"panelTitle"},
            fontSize = 18,
            width = "auto",
            height = "auto",
			text = "Dice Studio",
		},

		dropdownForm,

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "horizontal",

				gui.Button{
					text = "Save",
					width = "30%",
					height = 24,
					fontSize = 18,
					click = function(element)
						if studio.canSave then
							studio:Save()
						else
							element.parent.parent:FireEventTree("saveas")
						end
					end,
				},
				gui.Button{
					text = "Save As...",
					width = "30%",
					height = 24,
					fontSize = 18,
					click = function(element)
						element.parent.parent:FireEventTree("saveas")
					end,
				},

				gui.Button{
					text = "Revert",
					width = "30%",
					height = 24,
					fontSize = 18,
					click = function(element)
						diceDropdown:FireEvent("change")
					end,
				},

			},


			gui.Panel{
				classes = {"collapsed"},
				width = "100%",
				height = "auto",
				flow = "horizontal",

				saveas = function(element)
					element:SetClass("collapsed", false)
				end,


				gui.Input{
					height = 22,
					fontSize = 18,
					width = "60%",
					placeholderText = "Enter dice name...",
					text = "",
					saveas = function(element)
						element.textNoNotify = ""
						element.hasInputFocus = true
					end,
					change = function(element)
						if element.text ~= "" then
							studio:SaveAs(element.text)
							dropdownForm:SetClass("collapsed", false)
							localFiles = dicestudio:GetLocalFiles()
							diceDropdown.options = localFiles
							diceDropdown.idChosen = element.text
							element.root:FireEventTree("refreshDice")
						end
						element.parent:SetClass("collapsed", true)
					end,
				},
				gui.Button{
					text = "Cancel",
					width = "30%",
					height = 20,
					fontSize = 12,
					click = function(element)
						element.parent:SetClass("collapsed", true)
					end,
				},
			},

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "horizontal",
				gui.Button{
					text = "Upload",
					width = "30%",
					height = 20,
					fontSize = 12,
                    refreshDice = function(element)
						printf("refreshDice: %s", json(dicestudio.canSave))
						element:SetClass("collapsed", not dicestudio.canSave)
                    end,
					click = function(element)
						dicestudio:Upload()
						element.parent:FireEventTree("upload")
					end,
				},

				gui.Label{
					classes = {"collapsed"},
					hmargin = 4,
					fontSize = 12,
					width = "auto",
					height = "auto",
					valign = "center",
					text = "Uploaded.",
					upload = function(element)
						element:SetClass("collapsed", false)
						element:ScheduleEvent("collapse", 3)
					end,
					collapse = function(element)
						element:SetClass("collapsed", true)
					end,
				}
			},
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"formLabel"},
				halign = "left",
				text = "Video background:",
			},
			gui.ColorPicker{
				border = 2,
				borderColor = "white",
				width = 16,
				height = 16,
				value = videobg,
				change = function(element)
					videobg = element.value.tostring
				end,
			},
		},

		gui.Button{
			width = 180,
			height = 24,
			text = "Create Video...",
			click = function(element)

				--DicePreviewScene's layout differs by white label:
				--  MCDM: 2 paired d10s (the Power Roll), both in slot 0,
				--    offset symmetrically around the camera's focal point.
				--    Showing one solo would land it ~3.6*diceScale units off
				--    to the side, so we keep both visible to stay centered.
				--    Smaller scale leaves room for the pair in frame.
				--  Other: 6 dice at indices 0..5; the d20 (index 5) sits at
				--    the focal point on its own, so solo + scale 4 works.
				local mcdmMode = (dmhub.whiteLabel == "mcdm")

				local applySceneParams = function(scene)
					scene.assetid = "DEFAULT"
					scene.selectedIndex = cond(mcdmMode, 0, 5)
					scene.solo = not mcdmMode
					scene.fixedTime = true
					scene.initialRotation = 90
					scene.diceScale = cond(mcdmMode, 2.5, 4)
					scene.bgcolor = videobg
				end

				--Two stale states in C# DicePreviewScene have to be
				--cleared before the recording can show centered, spinning
				--dice:
				--  1. solo's SetActive(false) is sticky -- there's no else
				--     branch that re-enables dice when solo flips back, so
				--     hidden dice stay hidden until ClearDice respawns them.
				--     Respawn fires when _studiomode flips.
				--  2. UpdateLua only calls InitPreviewRotation when
				--     _luaInit == false, and that's the only place the per-
				--     die previewRotate vector gets set. _luaInit is reset
				--     by ResetLua, which only runs when luamode == false.
				--     So freshly respawned dice have previewRotate = (0,0,0)
				--     and don't spin unless we first force luamode false for
				--     a frame.
				--Setting assetid to a non-DEFAULT sentinel and not touching
				--the scene for >5 frames lets luaUpdateFrame go stale; on
				--the next Update the C# falls into the else branch with
				--luamode = false, which both flips _studiomode (respawn) and
				--runs ResetLua. After that the real params can be applied
				--cleanly.
				local scene = dice.GetPreviewScene()
				scene.assetid = "FORCE_RESPAWN"

				dmhub.Schedule(0.2, function()
					applySceneParams(dice.GetPreviewScene())

					gui.ShowModal(gui.Panel{
						width = 1024,
						height = 1024,
						halign = "center",
						valign = "center",
						bgimage = "#DicePreview",
						bgcolor = "white",

						--Light-touch: just keep the scene alive. Re-applying
						--params here is what previously kept luaUpdateFrame
						--perpetually fresh and blocked the ResetLua path.
						thinkTime = 0.1,
						think = function(element)
							dice.GetPreviewScene()
						end,

						gui.Label{
							valign = "bottom",
							halign = "center",
							width = "auto",
							height = "auto",
							color = "white",
							text = "Rendering Dice...",
							fontSize = 24,
						}
					})

					dicestudio:RecordPreviewVideo(function()
						gui.CloseModal()
					end)
				end)

			end,
		},


		CreateDicePanel(),

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"formLabel"},
				halign = "left",
				text = "Font:",
			},
			gui.Dropdown{
				width = "100%-24",
				height = 30,
				fontSize = 14,
				options = studio.fontOptions,
				optionChosen = studio.font,
				newmaterial = function(element)
					element.optionChosen = studio.font
				end,
				change = function(element)
					studio.font = element.optionChosen
				end,
			},
		},
	
		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"formLabel"},
				halign = "left",
				text = "Border:",
			},
			gui.Dropdown{
				width = "100%-24",
				height = 30,
				fontSize = 14,
				options = studio.borderOptions,
				optionChosen = studio.border,
				newmaterial = function(element)
					element.optionChosen = studio.border
				end,
				change = function(element)
					studio.border = element.optionChosen
				end,
			},
		},

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			gui.Panel{
				classes = {"formPanel"},
				gui.Check{
					halign = "left",
					text = "Teleporting",
					value = studio.teleporting,
					newmaterial = function(element)
						element.value = studio.teleporting
					end,
					change = function(element)
						studio.teleporting = element.value
						RefreshDice()
						element.root:FireEventTree("refreshDice")
					end,
				},
			},

			-- Teleport tunables: only shown while Teleporting is checked.
			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",

				create = function(element)
					element:SetClass("collapsed", not studio.teleporting)
				end,
				refreshDice = function(element)
					element:SetClass("collapsed", not studio.teleporting)
				end,
				newmaterial = function(element)
					element:SetClass("collapsed", not studio.teleporting)
				end,

				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Teleport At Speed:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 0,
						maxValue = 10,
						value = studio.teleportVelocity or 1.5,
						newmaterial = function(element)
							element.value = studio.teleportVelocity or 1.5
						end,
						change = function(element)
							studio.teleportVelocity = element.value
							RefreshDice()
						end,
					},
				},

				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Teleport Distance:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 0,
						maxValue = 1,
						value = studio.teleportDistance or 0.333,
						newmaterial = function(element)
							element.value = studio.teleportDistance or 0.333
						end,
						change = function(element)
							studio.teleportDistance = element.value
							RefreshDice()
						end,
					},
				},

				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Teleport Duration:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 0.02,
						maxValue = 0.5,
						value = studio.teleportDuration or 0.1,
						newmaterial = function(element)
							element.value = studio.teleportDuration or 0.1
						end,
						change = function(element)
							studio.teleportDuration = element.value
							RefreshDice()
						end,
					},
				},
			},
		},



		builtinPropertiesPanel,

        gui.TreeNode{
            text = "Video Effect",
			width = "100%",
            contentPanel = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",

                gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        halign = "left",
                        text = "Video:",
                    },
                    gui.IconEditor{
                        width = 32,
                        height = 32,
                        library = "diceVideos",
                        categoriesHidden = true,
                        bgcolor = "white",
                        value = dicestudio.finishVideoEffect.video,
                        refreshDice = function(element)
                            element.value = dicestudio.finishVideoEffect.video
							printf("Init video to %s -> %s", dicestudio.finishVideoEffect.video, element.value)
                        end,
                        change = function(element)
                            dicestudio.finishVideoEffect.video = element.value
                            printf("Set video to %s -> %s", element.value, dicestudio.finishVideoEffect.video)
                            RefreshDice()
                            materialPropertiesPanel:FireEvent("newmaterial")
                        end,
                    },
                },
                gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        halign = "left",
                        text = "Scale:",
                    },
                    gui.Slider{


						style = {
							height = 26,
							width = 120,
							fontSize = 14,
						},

						sliderWidth = 80,
						labelWidth = 40,
						minValue = 0,
						maxValue = 8,

                        value = dicestudio.finishVideoEffect.scaleNumber,

                        refreshDice = function(element)
                            element.value = dicestudio.finishVideoEffect.scaleNumber
                        end,
                        confirm = function(element)
                            dicestudio.finishVideoEffect.scaleNumber = element.value
                            RefreshDice()
                            materialPropertiesPanel:FireEvent("newmaterial")
                        end,
                    },
                },
            }
        },

        gui.TreeNode{
            text = "Surface Material",
			width = "100%",
            contentPanel = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",


                gui.Panel{
                    classes = {"formPanel"},
                    gui.Label{
                        classes = {"formLabel"},
                        halign = "left",
                        text = "Default Material:",
                    },
                    gui.Dropdown{
                        width = 160,
                        height = 30,
                        fontSize = 14,
                        options = materialOptions,
                        idChosen = studio.surfaceMaterialName or "none",
                        newmaterial = function(element)
                            CalculateMaterialOptions()
                            element.options = materialOptions

                            if element.idChosen ~= studio.surfaceMaterialName then
                                element.idChosen = studio.surfaceMaterialName or "none"
                            end

                        end,
                        change = function(element)
                            studio.material = idToMaterial[element.idChosen]
                            RefreshDice()
                            materialPropertiesPanel:FireEvent("newmaterial")
                        end,
                    },
                },

                -- Per-die-type surface material overrides. Each die can either use
                -- its own material or "(Default)" to inherit the Default Material above.
                -- Sits directly under the Default Material picker; the default
                -- material's property editor follows below.
                gui.Label{
                    bold = true,
                    width = "auto",
                    height = "auto",
                    halign = "left",
                    lmargin = 12,
                    vmargin = 8,
                    fontSize = 14,
                    text = "Per-Die Overrides",
                },

                CreatePerDieMaterialPanel(3),
                CreatePerDieMaterialPanel(4),
                CreatePerDieMaterialPanel(6),
                CreatePerDieMaterialPanel(8),
                CreatePerDieMaterialPanel(10),
                CreatePerDieMaterialPanel(12),
                CreatePerDieMaterialPanel(20),

                materialPropertiesPanel,
            }
        },

		gui.TreeNode{
			text = "Particles",
			width = "100%",
			contentPanel = gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				diceEventRows,
				addDiceEventControl,
			},
		},

		gui.TreeNode{
            text = "Animations",
			width = "100%",
            contentPanel = gui.Panel{
                width = "100%",
                height = "auto",
                flow = "vertical",

				gui.Panel{
					data = {
						panels = {},
					},
					width = "100%",
					height = "auto",
					flow = "vertical",
					refreshDice = function(element)
						local newPanels = {}
						local children = {}

						local curves = studio.curves

						for i,curveItem in ipairs(curves) do
							local curve = curveItem
							local panel = element.data.panels[i] or gui.Panel{
								flow = "vertical",
								width = "100%",
								height = "auto",
								refreshDice = function(element)
									curve = studio.curves[i]
								end,


								gui.Panel{
									bgimage = "panels/square.png",
									bgcolor = "black",
									halign = "left",
									valign = "top",
									pad = 8,
									width = 240,
									height = 240,

									gui.Curve{
										width = 240,
										height = 240,
										value = curve.curve,
										refreshDice = function(element)
											element.value = studio.curves[i].curve
										end,
										confirm = function(element)
											curve.curve = element.value
										end,
									},
								},

								gui.Panel{
									classes = {"formPanel"},
									gui.Label{
										classes = {"formLabel"},
										halign = "left",
										text = "Input:",
									},

									gui.Dropdown{
										textDefault = "Choose Input...",
										options = dicestudio.allCurveInputs,
										idChosen = curve.input,
										width = 160,
										refreshDice = function(element)
											element.idChosen = studio.curves[i].input
										end,
										change = function(element)
											curve.curve = element.value
										end,
									}
								},

								gui.DeleteItemButton{
									halign = "right",
									valign = "top",
									floating = true,
									width = 16,
									height = 16,
									click = function(element)
										local curves = studio.curves
										table.remove(curves, i)
										studio.curves = curves
										element.root:FireEventTree("refreshDice")
									end,
								},
							}

							newPanels[i] = panel
							children[#children+1] = panel
						end

						element.children = children
						element.data.panels = newPanels
					end,
				},

				gui.AddButton{
					width = 16,
					height = 16,
					halign = "right",
					hmargin = 4,
					click = function(element)
						studio:AddCurve()
						element.root:FireEventTree("refreshDice")
					end,
				}
			},
		},


	}

	return resultPanel
end

CreateDicePanel = function()

	local studio = dicestudio

	local mcdmMode = (dmhub.whiteLabel == "mcdm")

	local styles = {
		{
			classes = "dice",
			bgcolor = "white",
			width = 40,
			height = 40,
			valign = "center",
			halign = "center",
			uiscale = 0.95,
		},

		{
			classes = {"dice", "hover"},
			scale = 1.1,
			brightness = 2,
		},
	}

	if mcdmMode then
		--match the Draw Steel dice panel: dimmed idle, brighter on hover.
		styles = {
			{
				classes = "dice",
				bgcolor = "white",
				width = 40,
				height = 40,
				valign = "center",
				halign = "center",
				uiscale = 0.95,
				saturation = 0.7,
				brightness = 0.4,
			},

			{
				classes = {"dice", "hover"},
				scale = 1.2,
				brightness = 1.2,
			},
		}
	end

	--Draw Steel dice button: djordice art + face-number drop shadow,
	--mirroring Draw Steel UX Update/DicePanel.lua so the studio preview
	--matches what players see in the rolling panel.
	local CreateMCDMDice = function(faces, params)
		params = params or {}

		local selectedDie, selectedDieFilled
		local selectedFaces
		local selectedString, selectedFontSize, selectedYAdjust = "", 14, 0

		if faces == 3 then
			selectedDie = "ui-icons/dsdice/djordice-d6.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d6-filled.png"
			selectedFaces = 3
			selectedString = "3"
			selectedFontSize = 18
			selectedYAdjust = 2
		elseif faces == 6 then
			selectedDie = "ui-icons/dsdice/djordice-d6.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d6-filled.png"
			selectedFaces = 6
			selectedString = "6"
			selectedFontSize = 18
			selectedYAdjust = 2
		elseif faces == 10 then
			selectedDie = "ui-icons/dsdice/djordice-d10.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d10-filled.png"
			selectedFaces = 10
			selectedString = "10"
			selectedFontSize = 14
			selectedYAdjust = 0
		elseif faces == 20 then
			selectedDie = "ui-icons/dsdice/djordice-2d10.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-2d10-filled.png"
			selectedFaces = 10
			selectedString = "Power Roll"
			selectedFontSize = 10
			selectedYAdjust = 0
		end

		local args = {
			classes = "dice",
			bgimage = selectedDieFilled,
			bgcolor = studio.dicePanelStyles.bgcolor,

			refreshDice = function(element)
				element.selfStyle.bgcolor = studio.dicePanelStyles.bgcolor
			end,

			press = function(panel)
				dicestudio:SpawnPreview(selectedFaces)
			end,

			gui.Panel{
				classes = {"diceLines"},
				interactable = false,
				width = "100%",
				height = "100%",
				bgimage = selectedDie,
				bgcolor = studio.dicePanelStyles.trimcolor,
				refreshDice = function(element)
					element.selfStyle.bgcolor = studio.dicePanelStyles.trimcolor
				end,
			},

			--drop shadow for the face number
			gui.Label{
				width = "100%",
				height = "auto",
				fontFace = "Book",
				fontSize = selectedFontSize,
				color = "black",
				halign = "center",
				valign = "center",
				textAlignment = "center",
				text = selectedString,
				y = selectedYAdjust + 1,
				x = 1,
			},

			--main face-number label, bound to the studio's preview text color
			gui.Label{
				width = "100%",
				height = "auto",
				fontFace = "Book",
				fontSize = selectedFontSize,
				color = studio.dicePanelStyles.color,
				halign = "center",
				valign = "center",
				textAlignment = "center",
				text = selectedString,
				y = selectedYAdjust,
				refreshDice = function(element)
					element.selfStyle.color = studio.dicePanelStyles.color
				end,
			},
		}

		for k,v in pairs(params) do
			args[k] = v
		end

		return gui.Panel(args)
	end

	local CreateDice = function(faces, params)
		params = params or {}

		--allow the displayed icon to differ from the rolled face count
		--(e.g. show a d20-shaped icon for a d10 in MCDM, where d10 uses a
		--d20 mesh).
		local imageFaces = params.iconFaces or faces
		if imageFaces == 100 then
			imageFaces = 10
		end
		--no d3 icon ships with the engine; reuse d6 art for the d3 button.
		if imageFaces == 3 then
			imageFaces = 6
		end


		--a single dice
		local args = {

			classes = "dice",
			bgimage = string.format("ui-icons/d%d-filled.png", imageFaces),
			bgcolor = studio.dicePanelStyles.bgcolor,

			refreshDice = function(element)
				element.selfStyle.bgcolor = studio.dicePanelStyles.bgcolor
			end,

			press = function(panel)
				dicestudio:SpawnPreview(faces)
            end,

			gui.Panel{
				interactable = false,
				width = "100%",
				height = "100%",
				bgimage = string.format("ui-icons/d%d.png", imageFaces),
				bgcolor = studio.dicePanelStyles.trimcolor,
				refreshDice = function(element)
					element.selfStyle.bgcolor = studio.dicePanelStyles.trimcolor
				end,
			}
		}

		for k,v in pairs(params) do
			if k ~= "iconFaces" then
				args[k] = v
			end
		end

		return gui.Panel(args)
	end
	
	
	local diceDisplayPanel = gui.Panel{
	
		width = "100%",
		height = "auto",
		styles = styles,
		flow = "vertical",

		gui.Label{
			classes = {"headingLabel"},
			vmargin = 8,
			text = "Dice Panel",
		},
		
		gui.Panel{
		
			width = "105%",
			height = "auto",
			valign = "top",
			halign = "center",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			flow = "horizontal",
			y = -1,

			events = {
				create = function(element)
					if mcdmMode then
						--mirror Draw Steel UX Update/DicePanel.lua so the
						--studio preview matches the live rolling panel
						--(d3, d6, d10, Power Roll = 2d10).
						element.children = {
							CreateMCDMDice(3, {uiscale = 1.1}),
							CreateMCDMDice(6, {uiscale = 1.2}),
							CreateMCDMDice(10, {uiscale = 1.5, y = 2}),
							CreateMCDMDice(20, {uiscale = 1.65, y = 2, width = 60}),
						}
					else
						element.children = {
							CreateDice(4),
							CreateDice(6),
							CreateDice(8),
							CreateDice(20, {uiscale = 1.65, y = 4}),
							CreateDice(10),
							CreateDice(12),
							CreateDice(100, {rotate = 180}),
						}
					end
				end
			}
		},
	}


	local CreateColorEditor = function(id, description)

		return gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"formLabel"},
				halign = "left",
				text = string.format("%s:", description),
			},
			gui.ColorPicker{
				border = 2,
				borderColor = "white",
				width = 16,
				height = 16,
				value = studio.dicePanelStyles[id],
				change = function(element)
					studio.dicePanelStyles[id] = element.value.tostring
					diceDisplayPanel:FireEventTree("refreshDice")
				end,
			},
		}

	end


	local resultPanel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		diceDisplayPanel,

		CreateColorEditor("bgcolor", "Preview Color"),
		CreateColorEditor("trimcolor", "Preview Trim"),
		CreateColorEditor("color", "Preview Text"),
	}

	return resultPanel

end