local mod = dmhub.GetModLoading()

local CreateDiceStudioPanel

-- The root panel of the currently-open Dice Studio dockable, captured in CreateDiceStudioPanel
-- and cleared on its destroy. Lets RefreshDiceStudioInterface() drive a full widget re-sync from
-- outside the panel (e.g. after mutating dicestudio.* from a dice script or the MCP bridge).
local g_studioPanelRoot = nil

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

-- Re-syncs the open Dice Studio panel's widgets to the live dice set, exactly as picking a set in
-- the "Dice:" dropdown does: bump the 3D preview (RefreshDice), then broadcast "newmaterial"
-- (rebuilds the material/particle/sound rows from current values) and "refreshDice" (re-reads the
-- per-property widgets and the 2D preview chips). Call this after mutating dicestudio.* from
-- outside the panel's own event handlers -- e.g. a dice script edit, a chat macro, or the MCP
-- bridge -- so the panel reflects the change instead of showing stale slider/dropdown/chip values.
-- Global on purpose so it is reachable from those external contexts. No-op (returns false) when
-- the panel is closed; returns true when it drove a refresh.
function RefreshDiceStudioInterface()
	RefreshDice()
	if g_studioPanelRoot == nil or not g_studioPanelRoot.valid then
		return false
	end
	g_studioPanelRoot:FireEventTree("newmaterial")
	g_studioPanelRoot:FireEventTree("refreshDice")
	return true
end

-- Remembers which dice set was last opened in Dice Studio so it reopens on the same
-- set across sessions. Stored per-user as the dice set's local-file id.
local g_lastEditedDiceSetSetting = setting{
	id = "dicestudio:lastedited",
	default = "",
	storage = "preference",
}

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
		-- The shader gates the surface matcap on _EnableMatcap (not _UseMatcap, which it never
		-- reads), so write the flag the shader actually samples -- otherwise setting a surface
		-- matcap texture in the studio never turned the matcap on.
		flag = "_EnableMatcap",
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
	-- Font Glow Solid: render the landed result-face number as a SOLID color (using the Font
	-- Glow color as the number's albedo) instead of an additive glow. The glow is emissive and
	-- can only brighten, so on a bright / fiery die a black glow color does nothing; with this
	-- on, set Font Glow to black to get a readable solid-black number on the face that lands.
	-- Appears on landing (same trigger as the glow). See _FontGlowSolid in DMHub-Dice-Generic.shader.
	{
		name = "_FontGlowSolid",
		description = "Font Glow Solid",
		type = "Bool",
	},
	-- Font Matcap: paints the numbers with a matcap (lit-sphere) reflection instead of a
	-- flat fill, for chrome / gold / holographic / glass-looking numbers. Setting a texture
	-- turns it on (the flag writes 1 to _EnableFontMatcap, which the shader reads); clearing
	-- it turns it back off. _FontTint tints the matcap (white = pure matcap), _FontMatcapPower
	-- scales its brightness. See DMHub-Dice-Generic.shader.
	{
		type = "Texture",
		flag = "_EnableFontMatcap",
		name = "_FontMatcapTexture",
		description = "Font Matcap",
		library = "Matcap",
	},
	{
		type = "Range",
		name = "_FontMatcapPower",
		description = "Font Matcap Power",
		min = 0,
		max = 2,
		default = 1,
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




	},

	-- Generic PBR surface material driven entirely by a cloud-delivered texture set
	-- (ambientCG / Poly Haven style: Color + NormalGL + Roughness + Displacement). Upload
	-- the maps as cloud image assets, then assign them here -- they ship with the dice set.
	-- The normal/roughness/height maps are decoded linear engine-side (see
	-- DiceMaterialStudioProperties.IsLinearDataProperty); the normal map must be raw RGB,
	-- OpenGL convention (use "_NormalGL", or tick Flip Normal Y for a "_NormalDX" map).
	PBRTexturedDiceMaterial = {
		{
			name = "_BaseMap",
			type = "Texture",
			library = "Textures",
			description = "Albedo / Color",
		},
		{
			name = "_BaseColor",
			type = "Color",
			description = "Tint",
		},
		{
			name = "_NormalMap",
			type = "Texture",
			library = "Normal",
			description = "Normal Map (GL)",
		},
		{
			name = "_NormalStrength",
			type = "Range",
			min = 0,
			max = 3,
			default = 1,
			description = "Normal Strength",
		},
		{
			name = "_NormalFlipY",
			type = "Bool",
			description = "Flip Normal Y (DX)",
		},
		{
			name = "_RoughnessMap",
			type = "Texture",
			library = "Textures",
			description = "Roughness Map",
		},
		{
			name = "_RoughnessScale",
			type = "Range",
			min = 0,
			max = 2,
			default = 1,
			description = "Roughness Scale",
		},
		{
			name = "_Brightness",
			type = "Range",
			min = 0,
			max = 3,
			default = 1,
			description = "Brightness",
		},
		{
			name = "_Ambient",
			type = "Range",
			min = 0,
			max = 1,
			default = 0.4,
			description = "Ambient",
		},
		{
			name = "_SpecStrength",
			type = "Range",
			min = 0,
			max = 2,
			default = 0.6,
			description = "Specular Strength",
		},
		{
			name = "_HeightMap",
			type = "Texture",
			library = "Textures",
			description = "Height / Displacement",
		},
		{
			name = "_ParallaxScale",
			type = "Range",
			min = 0,
			max = 0.15,
			default = 0.03,
			description = "Parallax Depth",
		},
		{
			name = "_ParallaxSteps",
			type = "Range",
			min = 1,
			max = 32,
			default = 12,
			description = "Parallax Steps",
		},
		{
			name = "_OcclusionFromHeight",
			type = "Range",
			min = 0,
			max = 1,
			default = 0,
			description = "AO From Height",
		},
		{
			name = "_Tiling",
			type = "Range",
			min = 0.1,
			max = 8,
			default = 1,
			description = "Tiling",
		},
	},

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

	-- Maps this panel's material category to the dice-script handle used to set its properties,
	-- so each property row can show a tooltip with the exact script call. The builtin material is
	-- the base die material (die.material); a default or per-die surface override is die.surface.
	-- The text material is not exposed to dice scripts.
	local ScriptHandleName = function()
		if matid == "builtin" then
			return "die.material"
		elseif matid == "text" then
			return nil
		end
		return "die.surface"
	end

	-- Returns a hover handler (gui.Tooltip) hinting how to set property p from a dice script, or
	-- nil when it isn't script-settable (textures) or the material isn't script-exposed. The
	-- tooltip shows the shader property NAME (the stable script identifier) rather than the UI
	-- label, since the label is a renamable description.
	local ScriptHint = function(p)
		local handle = ScriptHandleName()
		if handle == nil then
			return nil
		end
		if p.type == "Color" then
			return gui.Tooltip(string.format('Script: %s:SetColor("%s", "#rrggbb")', handle, p.name))
		elseif p.type == "Bool" then
			return gui.Tooltip(string.format('Script: %s:SetFloat("%s", 0 or 1)', handle, p.name))
		elseif p.type == "Float" or p.type == "Range" then
			return gui.Tooltip(string.format('Script: %s:SetFloat("%s", value)  -- range %s..%s', handle, p.name, tostring(p.min or 0), tostring(p.max or 1)))
		elseif p.type == "Texture" then
			return gui.Tooltip(string.format('Shader property "%s" (textures cannot be set from a dice script)', p.name))
		end
		return nil
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
						hover = ScriptHint(p),
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
						hover = ScriptHint(p),
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
						hover = ScriptHint(p),
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
						hover = ScriptHint(p),
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
										liveEdit = true,
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
											liveEdit = true,
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

	-- Prefer the dice set the user last edited (persisted across sessions), as long as it
	-- still exists on disk; otherwise fall back to the first available set.
	local initialDiceChoice = localFiles[1] and localFiles[1].id
	local savedDiceChoice = dmhub.GetSettingValue("dicestudio:lastedited")
	if type(savedDiceChoice) == "string" and savedDiceChoice ~= "" then
		for _,f in ipairs(localFiles) do
			if f.id == savedDiceChoice then
				initialDiceChoice = savedDiceChoice
				break
			end
		end
	end

	local diceDropdown = gui.Dropdown{
		width = 160,
		height = 30,
		fontSize = 14,
		options = localFiles,
		idChosen = initialDiceChoice,
		create = function(element)
			if localFiles[1] ~= nil then
				element:FireEvent("change")
			end
		end,
		change = function(element)
			studio:Load(element.idChosen)
			dmhub.SetSettingValue("dicestudio:lastedited", element.idChosen)
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

	-- currentName highlights the tile for the effect this picker is editing (an event can have
	-- several effects, so it is passed in per-instance rather than read from the event).
	local MakeParticleBrowser
	MakeParticleBrowser = function(owner, eventName, titleText, onPick, currentName)
		local COLS, ROWS = 4, 3
		local PAGE = COLS*ROWS
		local PREVIEW = 144
		local TILE_W = 174
		local TILE_H = PREVIEW + 30

		local current = currentName or ""

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
            edit = function(element)
				searchText = element.text or ""
				Filter()
				npage = 1
				g_particleBrowserPage[eventName] = 1
				element.root:FireEventTree("refreshSearch")
            end,
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

	-- Builds the row for a SINGLE effect instance within an event (an event can bind several).
	-- Contains the effect picker, a Raw debug button, the per-effect tunables, and a delete
	-- button. binding is a DiceEventEffectBindingLua wrapper; pulse marks a pulse event (vs a
	-- persistent state effect) and gates the Linger/Fade rows; rebuildFn rebuilds the owning
	-- event's instance list after a remove changes the count.
	local MakeEffectInstanceRow = function(eventName, label, binding, pulse, rebuildFn)
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
			local cur = binding.effectName
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
				-- Picking an effect rebinds this instance; picking "(None)" removes it.
				element.popup = MakeParticleBrowser(element, eventName, label, function(name)
					if name == "" then
						studio:RemoveEventEffect(binding)
						rebuildFn()
						RefreshDice()
					else
						binding.effectName = name
						element.root:FireEventTree("refreshDice")
						RefreshDice()
					end
				end, binding.effectName)
			end,
		}
		-- Per-effect on/off. Checked by default; unchecking suppresses playback without
		-- removing the effect (or its tunables) from the list. Re-reads its state on the
		-- newmaterial/refreshDice tree events so a freshly loaded set shows the saved value.
		local enabledCheck = gui.Check{
			text = "",
			tooltip = "Enable or disable this effect (keeps it in the list).",
			halign = "left",
			valign = "center",
			hmargin = 4,
			-- The default "checkbox" style reserves minWidth=200 for a label row; this is a
			-- bare box (empty text), so collapse it to hug just the check mark.
			width = "auto",
			minWidth = 0,
			height = 30,
			-- "enabled unless explicitly false" so a binding that predates the field (nil)
			-- reads as checked, matching the C# default.
			value = binding.enabled ~= false,
			newmaterial = function(element)
				element.value = binding.enabled ~= false
			end,
			refreshDice = function(element)
				element.value = binding.enabled ~= false
			end,
			change = function(element)
				binding.enabled = element.value
				RefreshDice()
			end,
		}

		local controlsChildren = { enabledCheck, previewButton }
		controlsChildren[#controlsChildren+1] = gui.Button{
			text = "Raw",
			width = 50,
			height = 30,
			fontSize = 12,
			hmargin = 4,
			click = function(element)
				studio:PlayRawBinding(binding)
			end,
		}
		controlsChildren[#controlsChildren+1] = gui.DeleteItemButton{
			width = 16,
			height = 16,
			valign = "center",
			hmargin = 4,
			click = function(element)
				studio:RemoveEventEffect(binding)
				rebuildFn()
				RefreshDice()
			end,
		}

		--A labelled slider bound to one of this effect's tunables. getFn/setFn close over the
		--binding wrapper. Re-reads its value on the newmaterial/refreshDice tree events.
		--Optional tooltip is shown on the label (used to explain the Linger/Fade defaults). It is
		--attached as a lazy hover handler via gui.Tooltip rather than the eager 'tooltip' field,
		--which on a gui.Label builds the tooltip panel detached at construction and spams a
		--"created but not attached to a parent" warning. gui.Tooltip(nil) returns nil (no handler).
		local function ParamSlider(slabel, minV, maxV, getFn, setFn, tooltip)
			return gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = slabel,
					hover = gui.Tooltip(tooltip),
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

		--Above/Below opacity sliders. Only meaningful when Layer is "Above & Below" (which spawns
		--two identical copies, one above the dice and one below); the engine multiplies each copy's
		--tint alpha and brightness by these so a faint copy can be laid over a stronger one (e.g.
		--above = 0.2). Hidden for every other Layer value. Its collapsed state is re-evaluated on
		--the tree refresh events AND driven directly by the Layer dropdown's change handler
		--(RefreshDice alone does not broadcast "refreshDice").
		local opacityPanel
		local function RefreshOpacityPanel(element)
			element:SetClass("collapsed", binding.layerPlacement ~= "abovebelow")
		end
		opacityPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			create = RefreshOpacityPanel,
			newmaterial = RefreshOpacityPanel,
			refreshDice = RefreshOpacityPanel,

			ParamSlider("Above Opacity:", 0, 1,
				function() return binding.aboveOpacity end,
				function(v) binding.aboveOpacity = v end,
				"Opacity of the copy spawned ABOVE the dice (multiplies its tint alpha and brightness, so both alpha-blended and additive effects dim). Lower it to lay a faint copy over a stronger one below. Only used when Layer is 'Above & Below'."),
			ParamSlider("Below Opacity:", 0, 1,
				function() return binding.belowOpacity end,
				function(v) binding.belowOpacity = v end,
				"Opacity of the copy spawned BELOW the dice (multiplies its tint alpha and brightness, so both alpha-blended and additive effects dim). Only used when Layer is 'Above & Below'."),
		}

		--Tunables collapse while this slot is unbound ("(None)"), since there's nothing to tune.
		local tunablesPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			lmargin = 12,
			create = function(element)
				element:SetClass("collapsed", binding.effectName == "")
			end,
			newmaterial = function(element)
				element:SetClass("collapsed", binding.effectName == "")
			end,
			refreshDice = function(element)
				element:SetClass("collapsed", binding.effectName == "")
			end,

			ParamSlider("Scale:", 0.1, 4,
				function() return binding.scale end,
				function(v) binding.scale = v end),
			ParamSlider("Speed:", 0.1, 4,
				function() return binding.speed end,
				function(v) binding.speed = v end),
			ParamSlider("Hue:", 0, 1,
				function() return binding.hueShift end,
				function(v) binding.hueShift = v end),
			ParamSlider("Brightness:", 0.1, 4,
				function() return binding.brightness end,
				function(v) binding.brightness = v end),

			-- Linger/Fade: how long a PULSE effect lasts after firing before it fades out and is
			-- destroyed (engine: DiceEventEffectBinding.linger/fade). Linger 0 = legacy (a 12s cap,
			-- no managed fade); raise it to stop a long Exit effect lingering after the die
			-- disappears (the die is gone ~3.5s after the roll ends). Fade is the tail fade-out.
			-- State effects (Roll Waiting, Travel Tail) live for the die's whole life and ignore
			-- this, so the rows are collapsed for them.
			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				create = function(element)
					element:SetClass("collapsed", not pulse)
				end,
				ParamSlider("Linger (s):", 0, 10,
					function() return binding.linger end,
					function(v) binding.linger = v end,
					"Seconds the effect lasts after it fires before fading out and being destroyed (default 4). Lower it to clear the effect sooner; set to 0 for the legacy uncapped behavior (a 12s safety cap, no fade)."),
				ParamSlider("Fade (s):", 0, 5,
					function() return binding.fade end,
					function(v) binding.fade = v end,
					"Length of the opacity fade-out at the end of the Linger window (capped at Linger; default 1). 0 = snap off with no fade. Ignored when Linger is 0."),
			},

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
					value = binding.tint,
					newmaterial = function(element)
						element.value = binding.tint
					end,
					refreshDice = function(element)
						element.value = binding.tint
					end,
					change = function(element)
						binding.tint = element.value
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
					idChosen = tostring(binding.xRotation),
					newmaterial = function(element)
						element.idChosen = tostring(binding.xRotation)
					end,
					refreshDice = function(element)
						element.idChosen = tostring(binding.xRotation)
					end,
					change = function(element)
						binding.xRotation = tonumber(element.idChosen) or 0
						RefreshDice()
					end,
				},
			},

			-- Force the effect above or beneath the dice. "Auto" keeps the prefab's
			-- own TopLayer/BottomLayer convention (the historical behavior). "Above & Below"
			-- spawns two copies (one above, one below), each dimmed by the opacity sliders.
			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = "Layer:",
				},
				gui.Dropdown{
					width = 140,
					height = 30,
					fontSize = 14,
					halign = "left",
					options = {
						{ id = "auto",       text = "Auto" },
						{ id = "above",      text = "Above Dice" },
						{ id = "below",      text = "Below Dice" },
						{ id = "abovebelow", text = "Above & Below" },
					},
					idChosen = binding.layerPlacement,
					newmaterial = function(element)
						element.idChosen = binding.layerPlacement
					end,
					refreshDice = function(element)
						element.idChosen = binding.layerPlacement
					end,
					change = function(element)
						binding.layerPlacement = element.idChosen
						-- RefreshDice() does not broadcast "refreshDice", so toggle the opacity
						-- sliders' visibility directly here.
						RefreshOpacityPanel(opacityPanel)
						RefreshDice()
					end,
				},
			},

			opacityPanel,
		}

		return gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			vmargin = 2,

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "horizontal",
				table.unpack(controlsChildren),
			},

			tunablesPanel,
		}
	end

	-- Builds the block for one dice lifecycle event. The header has the event label, a Test
	-- button (pulse events only) firing the whole event on the preview dice, an "Add Effect"
	-- button, and (optional) a remove-event button. Below the header is the list of effect
	-- instances bound to the event -- an event can have several, each its own prefab + tunables.
	local MakeStageEffectRow = function(eventName, label, pulse, removeEventFn)
		local instancesPanel
		local function RebuildInstances()
			local children = {}
			for _,binding in ipairs(studio:GetEventEffectList(eventName)) do
				children[#children+1] = MakeEffectInstanceRow(eventName, label, binding, pulse, function()
					RebuildInstances()
				end)
			end
			instancesPanel.children = children
		end
		instancesPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			lmargin = 12,
			create = function(element)
				RebuildInstances()
			end,
			newmaterial = function(element)
				RebuildInstances()
			end,
		}

		local headerChildren = {}
		headerChildren[#headerChildren+1] = gui.Label{
			classes = {"formLabel"},
			width = 110,
			halign = "left",
			text = label,
		}
		if pulse then
			headerChildren[#headerChildren+1] = gui.Button{
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
		headerChildren[#headerChildren+1] = gui.Button{
			text = "Add Effect",
			width = 90,
			height = 30,
			fontSize = 12,
			hmargin = 4,
			click = function(element)
				-- Open the picker; on pick, append a new effect to this event.
				element.popup = MakeParticleBrowser(element, eventName, label, function(name)
					if name ~= "" then
						studio:AddEventEffect(eventName, name)
						RebuildInstances()
						RefreshDice()
					end
				end, "")
			end,
		}
		if removeEventFn ~= nil then
			headerChildren[#headerChildren+1] = gui.DeleteItemButton{
				width = 16,
				height = 16,
				valign = "center",
				hmargin = 4,
				click = function(element)
					removeEventFn()
				end,
			}
		end

		return gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			vmargin = 4,

			gui.Panel{
				classes = {"formPanel"},
				width = "100%",
				height = "auto",
				flow = "horizontal",
				table.unpack(headerChildren),
			},

			instancesPanel,
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

	-- An event block is shown when it has at least one bound effect OR the user added it this
	-- session (data.added). Once shown it is marked added, so it stays put even after its last
	-- effect is removed; the block's remove (X) button clears every effect and hides it again.
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
			-- A freshly loaded dice set has its own events; drop session-added state and the
			-- cached blocks so the list rebuilds purely from what the new set has bound.
			element.data.added = {}
			element.data.panels = {}
			element:FireEvent("refreshDice")
		end,
		refreshDice = function(element)
			local children = {}
			local newPanels = {}
			for _,info in ipairs(diceEventList) do
				if element.data.added[info.event] or #studio:GetEventEffectList(info.event) > 0 then
					-- Mark added so visibility and the Add Event list stay consistent even
					-- after the event's last effect is removed.
					element.data.added[info.event] = true
					local panel = element.data.panels[info.event]
					if panel == nil then
						local ev = info.event
						panel = MakeStageEffectRow(ev, info.label, info.pulse, function()
							studio:ClearEventEffects(ev)
							diceEventRows.data.added[ev] = nil
							diceEventRows.data.panels[ev] = nil
							diceEventRows.root:FireEventTree("refreshDice")
							RefreshDice()
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
	-- block so effects can then be added to it.
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
				if not (diceEventRows.data.added[info.event] or #studio:GetEventEffectList(info.event) > 0) then
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

	-- Sounds section. Per-dice-set sound bindings, one sound per lifecycle event. Simpler than
	-- the Particles section: a fixed row per event with a sound dropdown (drawn from ALL
	-- registered sound events, plus a "(None)" entry) and a volume multiplier. Unbound events
	-- fall back to the engine's built-in behavior (Throw/Impact keep their defaults; the
	-- spawn/teleport/settle events are silent unless bound). "ThrowStart" is a per-roll sound;
	-- the rest fire per die. "Teleport" fires when a teleport-movement die begins its jump and
	-- "Reappear" when it arrives -- "Disappear" is now end-of-roll removal only. Labels are
	-- author-friendly (BounceHit -> "Impact", Exit -> "Settle").
	local diceSoundEventList = {
		{ event = "ThrowStart", label = "Throw:"      },
		{ event = "Appearance", label = "Appearance:" },
		{ event = "BounceHit",  label = "Impact:"     },
		{ event = "Disappear",  label = "Disappear:"  },
		{ event = "Teleport",   label = "Teleport:"   },
		{ event = "Reappear",   label = "Reappear:"   },
		{ event = "Exit",       label = "Settle:"     },
	}

	-- "(None)" sentinel + one entry per registered sound event, sorted by the engine.
	local function BuildSoundOptions()
		local options = { { id = "none", text = "(None)" } }
		for _,name in ipairs(studio:GetSoundEventOptions()) do
			options[#options+1] = { id = name, text = name }
		end
		return options
	end

	local function MakeSoundRow(eventName, labelText)
		local function CurrentId()
			local bound = studio:GetEventSound(eventName)
			if bound == nil or bound == "" then
				return "none"
			end
			return bound
		end

		local volumeRow
		volumeRow = gui.Panel{
			classes = {"formPanel"},
			create = function(element)
				element:SetClass("collapsed", CurrentId() == "none")
			end,
			newmaterial = function(element)
				element:SetClass("collapsed", CurrentId() == "none")
			end,
			refreshDice = function(element)
				element:SetClass("collapsed", CurrentId() == "none")
			end,
			gui.Label{
				classes = {"formLabel"},
				halign = "left",
				text = "Volume:",
			},
			gui.Slider{
				style = { height = 26, width = 240, fontSize = 14 },
				sliderWidth = 150,
				labelWidth = 50,
				minValue = 0,
				maxValue = 2,
				value = studio:GetEventSoundVolume(eventName),
				newmaterial = function(element)
					element.value = studio:GetEventSoundVolume(eventName)
				end,
				refreshDice = function(element)
					element.value = studio:GetEventSoundVolume(eventName)
				end,
				change = function(element)
					studio:SetEventSoundVolume(eventName, element.value)
				end,
			},
		}

		local dropdown
		dropdown = gui.Dropdown{
			width = 220,
			height = 30,
			fontSize = 14,
			halign = "left",
			hmargin = 4,
            hasSearch = true,
			create = function(element)
				element.options = BuildSoundOptions()
				element.idChosen = CurrentId()
			end,
			newmaterial = function(element)
				element.options = BuildSoundOptions()
				element.idChosen = CurrentId()
			end,
			refreshDice = function(element)
				element.idChosen = CurrentId()
			end,
			change = function(element)
				local id = element.idChosen
				studio:SetEventSound(eventName, id == "none" and "" or id)
				volumeRow:SetClass("collapsed", id == "none")
				RefreshDice()
			end,
		}

		return gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			gui.Panel{
				classes = {"formPanel"},
				width = "100%",
				height = "auto",
				flow = "horizontal",
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = labelText,
				},
				dropdown,
				gui.Button{
					text = "Test",
					width = 50,
					height = 30,
					fontSize = 12,
					hmargin = 4,
					click = function(element)
						studio:FirePreviewSound(eventName)
					end,
				},
			},
			volumeRow,
		}
	end

	local diceSoundRows = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		create = function(element)
			local rows = {}
			for _,info in ipairs(diceSoundEventList) do
				rows[#rows+1] = MakeSoundRow(info.event, info.label)
			end
			element.children = rows
		end,
	}

	-- Script section. Attaches a sandboxed custom Lua script to the dice set. The script runs
	-- once per die instance as a coroutine (see DiceInstanceLua) and can recolor/animate each die.
	-- It is edited in the user's external text editor via a watched temp file (the same
	-- OpenTextFileInConnectedEditor mechanism the document editor uses); saving the file validates
	-- the script, stores it on the set, and live-rebinds any preview dice so the effect shows
	-- immediately. The source ships and uploads with the dice set, so it runs in a locked-down
	-- environment with no engine API access (only math/table/string/coroutine + Wait()).
	local g_scriptTemplate = [[
-- Custom dice script. Runs once per die instance as a coroutine.
-- 'die' lets you inspect state (die.state, die.speed, die.face, die.alive, ...)
-- and set sticky appearance overrides (die.hue, die.color, die.alpha,
-- die.material:SetFloat/SetColor, ...). Call Wait() to give up the frame.
return function(die)
    while die.alive do
        if die.rolling then
            -- shift hue with speed while tumbling
            die.hue = math.min(1, die.speed / 18)
        elseif die.state == "result" and die.isMax then
            -- glow gold on a natural max
            die.color = "#ffd700"
        end
        Wait()
    end
end
]]

	local g_scriptWatcher = nil
	local scriptStatusLabel
	local scriptSnippetLabel

	local function ScriptSnippet()
		local src = dicestudio.script or ""
		if src == "" then
			return "(no script attached)"
		end
		if #src > 240 then
			return string.sub(src, 1, 240) .. "..."
		end
		return src
	end

	local function DestroyScriptWatcher()
		if g_scriptWatcher ~= nil then
			g_scriptWatcher:Destroy()
			g_scriptWatcher = nil
		end
	end

	local function RefreshScriptUI()
		if scriptSnippetLabel ~= nil then
			scriptSnippetLabel.text = ScriptSnippet()
		end
		if scriptStatusLabel ~= nil then
			local src = dicestudio.script or ""
			local err = dicestudio:ValidateScript(src)
			if err ~= "" then
				scriptStatusLabel.text = "Error: " .. err
				scriptStatusLabel.selfStyle.color = "#ff8888ff"
			elseif src == "" then
				scriptStatusLabel.text = "No script attached."
				scriptStatusLabel.selfStyle.color = "#bbbbbbff"
			else
				scriptStatusLabel.text = "Script OK."
				scriptStatusLabel.selfStyle.color = "#88ff88ff"
			end
		end
	end

	scriptStatusLabel = gui.Label{
		width = "100%",
		height = "auto",
		halign = "left",
		vmargin = 4,
		fontSize = 13,
		color = "#bbbbbbff",
		text = "No script attached.",
	}

	scriptSnippetLabel = gui.Label{
		width = "100%",
		height = "auto",
		halign = "left",
		vmargin = 4,
		fontSize = 12,
		color = "#888888ff",
		bgimage = "panels/square.png",
		bgcolor = "#00000055",
		pad = 6,
		borderBox = true,
		text = "(no script attached)",
	}

	local scriptSection = gui.TreeNode{
		text = "Script",
		width = "100%",
		contentPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			-- Tear down the file watcher when the panel goes away.
			destroy = function(element)
				DestroyScriptWatcher()
			end,
			-- A different set was loaded: the watched temp file is now stale, so stop watching
			-- and refresh the snippet/status from the newly loaded set's script.
			newmaterial = function(element)
				DestroyScriptWatcher()
				RefreshScriptUI()
			end,
			refreshDice = function(element)
				RefreshScriptUI()
			end,
			create = function(element)
				RefreshScriptUI()
			end,

			gui.Label{
				width = "100%",
				height = "auto",
				halign = "left",
				fontSize = 12,
				color = "#bbbbbbff",
				text = "Attach a custom Lua script that runs once per die. The script must end with 'return function(die) ... end' and may inspect and recolor each die. It runs in a locked-down sandbox.",
			},

			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "horizontal",
				vmargin = 4,

				gui.Button{
					text = "Edit Script...",
					width = 140,
					height = 26,
					fontSize = 16,
					click = function(element)
						DestroyScriptWatcher()

						local seed = dicestudio.script or ""
						if seed == "" then
							seed = g_scriptTemplate
						end

						local filename = "dicescript-" .. tostring(diceDropdown.idChosen or "set") .. ".lua"
						g_scriptWatcher = dmhub.OpenTextFileInConnectedEditor(filename, seed, function(contents)
							dicestudio.script = contents
							RefreshScriptUI()
							RefreshDice()
						end)

						if g_scriptWatcher == nil then
							gui.ModalMessage{
								title = "Could not open editor",
								message = "Could not spawn an external text editor for the dice script.",
							}
						end
					end,
				},

				gui.Button{
					text = "Clear",
					width = 80,
					height = 26,
					fontSize = 16,
					hmargin = 8,
					click = function(element)
						DestroyScriptWatcher()
						dicestudio.script = ""
						RefreshScriptUI()
						RefreshDice()
					end,
				},
			},

			scriptStatusLabel,
			scriptSnippetLabel,
		},
	}

	-- Halo / outline: a glowing outline that hugs each die. Authored per set (dicestudio.halo*)
	-- and overridable per die from a dice script (die.halo / die.haloColor / die.haloRadius).
	-- The color/radius/softness/intensity rows collapse while the effect is disabled.
	local haloSection = gui.TreeNode{
		text = "Halo / Outline",
		width = "100%",
		contentPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",

			gui.Label{
				width = "100%",
				height = "auto",
				halign = "left",
				fontSize = 12,
				color = "#bbbbbbff",
				text = "Draws a glowing outline that hugs each die. A dice script can override this per die (die.halo, die.haloColor, die.haloRadius).",
			},

			-- Enabled
			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = "Enabled:",
				},
				gui.Check{
					text = "",
					halign = "left",
					-- The default checkbox style reserves minWidth for a label row; this is a bare
					-- box (the "Enabled:" label is the formLabel above), so collapse to the mark.
					width = "auto",
					minWidth = 0,
					value = dicestudio.haloEnabled,
					newmaterial = function(element)
						element.value = dicestudio.haloEnabled
					end,
					change = function(element)
						dicestudio.haloEnabled = element.value
						RefreshDice()
						element.root:FireEventTree("refreshDice")
					end,
				},
			},

			-- Color / radius / softness / intensity (collapsed while disabled)
			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",

				create = function(element)
					element:SetClass("collapsed", dicestudio.haloEnabled == false)
				end,
				refreshDice = function(element)
					element:SetClass("collapsed", dicestudio.haloEnabled == false)
				end,

				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Color:",
					},
					gui.ColorPicker{
						border = 2,
						borderColor = "white",
						width = 16,
						height = 16,
						-- The "or default" fallbacks only fire before a build ships the C#
						-- dicestudio.halo* bridge properties (they return nil then); post-build
						-- they are always non-nil so the authored value flows through.
						value = dicestudio.haloColor or "#59a6ff",
						newmaterial = function(element)
							element.value = dicestudio.haloColor or "#59a6ff"
						end,
						change = function(element)
							dicestudio.haloColor = element.value
							RefreshDice()
						end,
					},
				},

				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Radius:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 0,
						maxValue = 0.25,
						value = dicestudio.haloRadius or 0.06,
						newmaterial = function(element)
							element.value = dicestudio.haloRadius or 0.06
						end,
						change = function(element)
							dicestudio.haloRadius = element.value
							RefreshDice()
						end,
					},
				},

				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Softness:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 0,
						maxValue = 1,
						value = dicestudio.haloSoftness or 0.5,
						newmaterial = function(element)
							element.value = dicestudio.haloSoftness or 0.5
						end,
						change = function(element)
							dicestudio.haloSoftness = element.value
							RefreshDice()
						end,
					},
				},

				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Intensity:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 0,
						maxValue = 8,
						value = dicestudio.haloIntensity or 1.5,
						newmaterial = function(element)
							element.value = dicestudio.haloIntensity or 1.5
						end,
						change = function(element)
							dicestudio.haloIntensity = element.value
							RefreshDice()
						end,
					},
				},
			},
		},
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

		-- Drop the captured root when the panel is torn down, so RefreshDiceStudioInterface()
		-- no-ops instead of firing events at a destroyed element tree.
		destroy = function(element)
			if g_studioPanelRoot == element then
				g_studioPanelRoot = nil
			end
		end,

		gui.Label{
			classes = {"panelTitle"},
            fontSize = 18,
            width = "auto",
            height = "auto",
			text = "Dice Studio",
		},

		dropdownForm,

		-- Admin tool: pull an already-uploaded ("cloud") dice set down to a local file
		-- so it shows up in the "Dice:" dropdown above. The local copy keeps the cloud
		-- name and id (see DiceStudioLua.DownloadCloudDice), so editing it and then
		-- hitting Save/Upload updates the same cloud document. Lives outside dropdownForm
		-- on purpose -- dropdownForm collapses when there are zero local files, which is
		-- exactly when you want to download one.
		gui.Button{
			text = "Download from Cloud...",
			width = "62%",
			height = 24,
			fontSize = 16,
			click = function(buttonElement)
				local cloudDice = dice.GetAllDice()
				table.sort(cloudDice, function(a, b)
					return string.lower(a.text) < string.lower(b.text)
				end)

				if #cloudDice == 0 then
					gui.ShowModal(gui.Panel{
						classes = {"framedPanel"},
						width = 400,
						height = "auto",
						halign = "center",
						valign = "center",
						flow = "vertical",
						styles = ThemeEngine.GetStyles(),

						gui.Label{
							width = "auto",
							height = "auto",
							halign = "center",
							valign = "center",
							vmargin = 24,
							color = "white",
							fontSize = 18,
							text = "No uploaded dice sets were found.",
						},

						gui.Panel{
							width = 360,
							height = 48,
							halign = "center",
							valign = "bottom",

							gui.Button{
								classes = {"sizeM"},
								halign = "center",
								text = "Close",
								escapeActivates = true,
								click = function(element)
									gui.CloseModal()
								end,
							},
						},
					})
					return
				end

				-- Currently-selected cloud dice id; updated by the dropdown below.
				local chosenId = cloudDice[1].id

				-- framedPanel supplies the themed background + border; ThemeEngine.GetStyles()
				-- gives the full themed cascade the inner controls (dropdown, sizeM buttons,
				-- modalTitle) need. A ShowModal dialog is re-rooted at the modal layer, so it
				-- can't inherit the Dice Studio panel's cascade -- it has to bring its own.
				gui.ShowModal(gui.Panel{
					classes = {"framedPanel"},
					width = 460,
					height = "auto",
					halign = "center",
					valign = "center",
					flow = "vertical",
					styles = ThemeEngine.GetStyles(),

					gui.Panel{
						halign = "center",
						valign = "top",
						vmargin = 20,
						flow = "vertical",
						width = 400,
						height = "auto",

						gui.Label{
							classes = {"modalTitle"},
							text = "Download Dice Set",
							halign = "center",
							width = "auto",
							height = "auto",
						},

						gui.Panel{
							flow = "horizontal",
							halign = "center",
							width = "auto",
							height = 40,
							valign = "center",
							vmargin = 12,

							gui.Label{
								text = "Uploaded:",
								width = "auto",
								height = "auto",
								color = "white",
								fontSize = 18,
								valign = "center",
								hmargin = 8,
							},

							gui.Dropdown{
								width = 260,
								height = 30,
								fontSize = 14,
								valign = "center",
								options = cloudDice,
								idChosen = chosenId,
								change = function(element)
									chosenId = element.idChosen
								end,
							},
						},
					},

					gui.Panel{
						width = 400,
						height = 48,
						halign = "center",
						valign = "bottom",

						gui.Button{
							classes = {"sizeM"},
							halign = "left",
							text = "Download",
							click = function(element)
								local name = dicestudio:DownloadCloudDice(chosenId)
								gui.CloseModal()
								if name == nil then
									return
								end

								-- Refresh the local "Dice:" dropdown and select the
								-- freshly downloaded set, loading it into the editor.
								localFiles = dicestudio:GetLocalFiles()
								dropdownForm:SetClass("collapsed", false)
								diceDropdown.options = localFiles
								diceDropdown.idChosen = name
								diceDropdown:FireEvent("change")
							end,
						},

						gui.Button{
							classes = {"sizeM"},
							halign = "right",
							text = "Cancel",
							escapeActivates = true,
							click = function(element)
								gui.CloseModal()
							end,
						},
					},
				})
			end,
		},

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
					--Reset the spin AXIS to vertical: the shared preview scene is a
					--singleton, so a non-zero spinAxisAngle left over from a shop
					--banner (a Dice item's spinDirection) would otherwise tilt this
					--recording. pcall-guarded for older engine binaries that lack it.
					pcall(function() scene.spinAxisAngle = 0 end)
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
				gui.Label{
					classes = {"formLabel"},
					halign = "left",
					text = "Special Movement:",
				},
				gui.Dropdown{
					width = "100%-24",
					height = 30,
					fontSize = 14,
					options = {
						{ id = "none",     text = "None" },
						{ id = "teleport", text = "Teleport" },
						{ id = "portal",   text = "Portal" },
					},
					idChosen = studio.specialMovement,
					newmaterial = function(element)
						element.idChosen = studio.specialMovement
					end,
					change = function(element)
						studio.specialMovement = element.idChosen
						RefreshDice()
						element.root:FireEventTree("refreshDice")
					end,
				},
			},

			-- Teleport tunables: only shown while mode == teleport.
			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",

				create = function(element)
					element:SetClass("collapsed", studio.specialMovement ~= "teleport")
				end,
				refreshDice = function(element)
					element:SetClass("collapsed", studio.specialMovement ~= "teleport")
				end,
				newmaterial = function(element)
					element:SetClass("collapsed", studio.specialMovement ~= "teleport")
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

			-- Portal effect: only shown while mode == portal. Reuses MakeStageEffectRow so the
			-- effect picker and its tunables (scale/speed/hue/brightness/tint/rotate) match the
			-- Particles node exactly. The "Portal" event resolves its catalog from the full
			-- effect library on the engine side (DiceIndex.GetEventEffectNames).
			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",

				create = function(element)
					element:SetClass("collapsed", studio.specialMovement ~= "portal")
				end,
				refreshDice = function(element)
					element:SetClass("collapsed", studio.specialMovement ~= "portal")
				end,
				newmaterial = function(element)
					element:SetClass("collapsed", studio.specialMovement ~= "portal")
				end,

				-- Seconds the die must be airborne before its first wall/floor collision sends it
				-- through a portal; also the lead time the portals are shown before the impact.
				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Portal Creation Time:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 0,
						maxValue = 0.5,
						value = studio.portalCreationTime or 0.1,
						newmaterial = function(element)
							element.value = studio.portalCreationTime or 0.1
						end,
						change = function(element)
							studio.portalCreationTime = element.value
							RefreshDice()
						end,
					},
				},

				-- Duration of the brightness flash the die pulses as it enters the portal. The
				-- flash peaks exactly at the moment of entry (it begins half this period before).
				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Portal Flash Period:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 0,
						maxValue = 1,
						value = studio.portalFlashPeriod or 0.2,
						newmaterial = function(element)
							element.value = studio.portalFlashPeriod or 0.2
						end,
						change = function(element)
							studio.portalFlashPeriod = element.value
							RefreshDice()
						end,
					},
				},

				-- Peak brightness multiplier of that flash (1 = no flash).
				gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						halign = "left",
						text = "Portal Flash Intensity:",
					},
					gui.Slider{
						style = { height = 26, width = 240, fontSize = 14 },
						sliderWidth = 180,
						labelWidth = 50,
						minValue = 1,
						maxValue = 16,
						value = studio.portalFlashIntensity or 4,
						newmaterial = function(element)
							element.value = studio.portalFlashIntensity or 4
						end,
						change = function(element)
							studio.portalFlashIntensity = element.value
							RefreshDice()
						end,
					},
				},

				MakeStageEffectRow("Portal", "Portal Effect:", true),
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
			text = "Sounds",
			width = "100%",
			contentPanel = gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				diceSoundRows,
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

		haloSection,

		scriptSection,

	}

	g_studioPanelRoot = resultPanel

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

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				classes = {"formLabel"},
				halign = "left",
				text = "Preview Size:",
			},
			gui.Slider{
				style = { height = 26, width = 240, fontSize = 14 },
				sliderWidth = 180,
				labelWidth = 50,
				minValue = 0.5,
				maxValue = 8,
				value = studio.previewScale,
				newmaterial = function(element)
					element.value = studio.previewScale
				end,
				change = function(element)
					studio.previewScale = element.value
				end,
			},
		},

		CreateColorEditor("bgcolor", "Preview Color"),
		CreateColorEditor("trimcolor", "Preview Trim"),
		CreateColorEditor("color", "Preview Text"),
	}

	return resultPanel

end