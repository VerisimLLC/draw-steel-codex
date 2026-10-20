local mod = dmhub.GetModLoading()

setting{
	id = "truediagonals",
	classes = {"dmonly"},
	description = "True Diagonals",
	help = "Count diagonals as 1.5 spaces",
	storage = "game", 
	section = "game",

	editor = "check",
	default = true, 
}

setting{
	id = "canlookup",
	description = "Can Look Up",
	help = "Controls whether players can look up to see higher floors. 'Under Opening' only allows looking up when there is a hole in the floor above. 'Always' allows looking up even under solid floors. 'Never' prevents looking up entirely.",
	storage = "map",
	editor = "dropdown",
	default = "opening",
	enum = {
		{ value = "never", text = "Never" },
		{ value = "opening", text = "Under Opening" },
		{ value = "always", text = "Always" },
	},
}

setting{
	id = "maxlookup",
	description = "Max Look Up",
	help = "The maximum number of floors a creature can look up on this map",
	storage = "map",
	editor = "dropdown",
	default = -1,
	monitorVisible = {"canlookup"},
	visible = function()
		return dmhub.GetSettingValue("canlookup") ~= "never"
	end,
	enum = {
		{ value = 0, text = "None" },
		{ value = 1, text = "One floor" },
		{ value = 2, text = "Two floors" },
		{ value = 3, text = "Three floors" },
		{ value = 4, text = "Four floors" },
		{ value = 5, text = "Five floors" },
		{ value = -1, text = "Unlimited floors" },
	},
}

setting{
	id = "map:playerviewable",
	description = "Player Viewable",
	help = "If enabled, all players can see this map: they get full vision (no fog of war) on it, and it always appears in their Maps list even if they have no tokens on it. Right-click the share button on the map's window to turn it on for chosen players only.",
	storage = "map",
	editor = "check",
	default = false,
}

setting{
	id = "map:playerinfobubbles",
	description = "Players See Map Info Bubbles",
	help = "If enabled, players can see the info bubbles on this map and click them to read their documents. Only applies to Player Viewable maps.",
	storage = "map",
	editor = "check",
	default = false,
	monitorVisible = {"map:playerviewable"},
	visible = function()
		return dmhub.GetSettingValue("map:playerviewable")
	end,
}

setting{
	id = "map:parallaxscale",
	description = "Parallax Scale",
	help = "Multiplies the parallax effect on this map relative to the game-wide Parallax setting. 1 leaves it unchanged, 0 disables parallax on this map, higher values make it more pronounced.",
	classes = {"dmonly"},
	storage = "map",
	editor = "slider",
	format = "F2",
	labelFormat = "%.2f",
	default = 1,
	min = 0,
	max = 3,
}

local function track(eventType, fields)
	if dmhub.GetSettingValue("telemetry_enabled") == false then
		return
	end
	fields.type = eventType
	fields.userid = dmhub.userid
	fields.gameid = dmhub.gameid
	fields.version = dmhub.version
	analytics.Event(fields)
end

local CreateMapSettings
local CreateEditorSettings

DockablePanel.Register{
	name = "Map Settings",
	icon = "phosphor/gear-six-bold.png",
	vscroll = true,
    dmonly = true,
	minHeight = 100,
	content = function()
		track("panel_open", {
			panel = "Map Settings",
			dailyLimit = 30,
		})
		return CreateMapSettings()
	end,
}

DockablePanel.Register{
	name = "Editor Settings",
	folder = "Map Editing",
	icon = mod.images.editorSettingsIcon,
	vscroll = true,
    dmonly = true,
	minHeight = 100,
	content = function()
		track("panel_open", {
			panel = "Editor Settings",
			dailyLimit = 30,
		})
		return CreateEditorSettings()
	end,
}



local SettingsPanelHeight = 30

--Panel-local styles for Map Settings, on the STYLE_GUIDE section-header and
--row grammar (see MapsPanel.lua / Floors.lua for the reference panels).
local function BuildMapSettingsStyles()
	return {
		{
			selectors = {"msSectionHeader"},
			flow = "horizontal",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			width = "100%",
			height = 30,
			tmargin = 6,
			hpad = 8,
			borderBox = true,
			halign = "left",
			valign = "top",
		},
		{
			selectors = {"msSectionHeader", "hover"},
			bgcolor = "@bgAlt",
			transitionTime = 0.1,
		},
		{
			selectors = {"msSectionLabel"},
			fontSize = 13,
			bold = true,
			color = "@fg",
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "center",
			lmargin = 4,
		},
		{
			selectors = {"msSectionLabel", "parent:hover"},
			color = "@fgStrong",
			transitionTime = 0.1,
		},
		{
			selectors = {"msSectionCount"},
			fontSize = 11,
			color = "@fgMuted",
			width = "auto",
			height = "auto",
			halign = "right",
			valign = "center",
		},
		--Header caret, sized for a 30px header.
		{
			selectors = {"triangle"},
			width = 14,
			height = 14,
			valign = "center",
			priority = 10,
		},
		{
			selectors = {"msSectionRule"},
			bgcolor = "@border",
			opacity = 0.35,
			width = "100%",
			height = 1,
		},
		{
			selectors = {"msSectionBody"},
			flow = "vertical",
			width = "100%",
			height = "auto",
			hpad = 8,
			vpad = 4,
			borderBox = true,
		},
		--The shared stacked-editor labels ("Fog of War:") sit muted above
		--their control, so the controls and checkbox names carry the eye.
		{
			selectors = {"label", "formStacked", "sizeXs"},
			color = "@fgMuted",
			fontSize = 12,
			priority = 5,
		},
		--Floor rows: transparent at rest, @bgAlt on hover, the current
		--floor marked with the accent edge and a bold name.
		{
			selectors = {"msFloorRow"},
			flow = "horizontal",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			width = "100%",
			height = 34,
			hpad = 8,
			borderBox = true,
		},
		{
			selectors = {"msFloorRow", "hover"},
			bgcolor = "@bgAlt",
			transitionTime = 0.1,
		},
		{
			selectors = {"msFloorRow", "selected"},
			bgcolor = "@bgAlt",
			border = {x1 = 3, x2 = 0, y1 = 0, y2 = 0},
			borderColor = "@accent",
		},
		{
			selectors = {"msFloorName"},
			fontSize = 14,
			color = "@fg",
			width = "100%-120",
			height = "auto",
			halign = "left",
			valign = "center",
			textWrap = false,
			textOverflow = "ellipsis",
		},
		{
			selectors = {"msFloorName", "parent:selected"},
			color = "@fgStrong",
			bold = true,
		},
		{
			selectors = {"msFloorSeam"},
			bgcolor = "@border",
			opacity = 0.2,
			width = "100%",
			height = 1,
		},
		--Same editable height box as the Floors panel (floorHeightValue).
		{
			selectors = {"msFloorHeight"},
			bgimage = "panels/square.png",
			bgcolor = "clear",
			border = 1,
			borderColor = "@border",
			cornerRadius = 3,
			fontSize = 14,
			color = "@fg",
			width = 34,
			height = 20,
			halign = "left",
			valign = "center",
			textAlignment = "center",
		},
		{
			selectors = {"msFloorHeight", "hover"},
			borderColor = "@accent",
		},
		{
			selectors = {"msFloorHeight", "invalid"},
			priority = 20,
			color = "@danger",
			borderColor = "@danger",
			transitionTime = 0.6,
		},
		{
			selectors = {"msFloorUnit"},
			fontSize = 10,
			color = "@fgMuted",
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "center",
			lmargin = 3,
		},
		--The per-floor actions menu: muted at rest, full strength on hover.
		{
			selectors = {"msRowMenu"},
			bgcolor = "@fgMuted",
			opacity = 0.5,
			width = 18,
			height = 18,
			halign = "right",
			valign = "center",
			lmargin = 8,
		},
		{
			selectors = {"msRowMenu", "hover"},
			bgcolor = "@fg",
			opacity = 1,
			transitionTime = 0.1,
		},
	}
end

--One collapsible section: a caret + title header with an underline, over
--a body that holds the section's controls. Whether it is collapsed is a
--per-user preference, so the panel reopens the way it was left.
--options.count: optional muted number at the header's right edge.
local function CreateSection(id, title, children, options)
	options = options or {}
	local prefKey = "mapsettings:collapsed:" .. id
	local collapsed = dmhub.GetPref(prefKey) == true

	local body = gui.Panel{
		classes = {"msSectionBody", cond(collapsed, "collapsed")},
		children = children,
	}

	local caret = gui.ExpandoArrow{
		bgimage = "phosphor/caret-down-fill.png",
		classes = cond(collapsed, nil, {"expanded"}),
		interactable = false,
	}

	local headerChildren = {
		caret,
		gui.Label{
			classes = {"msSectionLabel"},
			text = title,
		},
	}
	if options.count ~= nil then
		headerChildren[#headerChildren+1] = gui.Label{
			classes = {"msSectionCount"},
			text = tostring(options.count),
		}
	end

	return gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		gui.Panel{
			classes = {"msSectionHeader"},
			children = headerChildren,
			click = function(element)
				local nowCollapsed = not body:HasClass("collapsed")
				body:SetClass("collapsed", nowCollapsed)
				caret:SetClass("expanded", not nowCollapsed)
				dmhub.SetPref(prefKey, nowCollapsed)
			end,
		},
		gui.Panel{
			classes = {"msSectionRule"},
			bgimage = "panels/square.png",
		},
		body,
	}
end

--The object carrying a "Map" component on a floor or any of its layers:
--the imported map image that Reimport Map Sizing / Realign Floor act on.
local function FindFloorMapObject(floor)
	for _, layer in ipairs(game.currentMap:GetLayersForFloor(floor.floorid) or {}) do
		for _, obj in pairs(layer.objects) do
			if obj:GetComponent("Map") ~= nil then
				return obj, layer
			end
		end
	end
	return nil, nil
end

local function FloorHeightText(floor)
	return MeasurementSystem.NativeToDisplayString(floor.floorHeightInTiles*dmhub.unitsPerSquare)
end

--One floor: its name, its editable height (same rules as the Floors
--panel: whole tiles, 1-20), and a menu with the map-image actions when the
--floor has an imported map.
local function CreateFloorRow(floor, index)
	local mapObj, mapLayer = FindFloorMapObject(floor)

	local function ShowMenu(element)
		if mapObj == nil then
			return
		end
		element.popup = gui.ContextMenu{
			entries = {
				{
					text = "Reimport Map Sizing",
					click = function()
						element.popup = nil
						mod.shared.ReimportMapSizing(mapLayer, mapObj)
					end,
				},
				{
					text = "Realign Floor...",
					click = function()
						element.popup = nil
						mod.shared.ShowFloorRealignDialog(mapLayer, mapObj)
					end,
				},
			},
		}
	end

	local name = floor.description
	if name == nil or name == "" then
		name = string.format("Floor %d", index)
	end

	---@type Panel[]
	local children = {
		gui.Label{
			classes = {"msFloorName"},
			text = name,
		},
	}

	--Floor heights only matter with parallax on; the Floors panel hides
	--them otherwise, and so does this.
	children[#children+1] = gui.Panel{
		classes = {cond(not dmhub.useParallax, "collapsed")},
		flow = "horizontal",
		width = "auto",
		height = 20,
		halign = "right",
		valign = "center",
		monitor = "useparallax",
		events = {
			monitor = function(element)
				element:SetClass("collapsed", not dmhub.useParallax)
			end,
		},
		gui.Label{
			classes = {"msFloorHeight"},
			text = FloorHeightText(floor),
			editable = true,
			characterLimit = 4,
			hover = gui.Tooltip(string.format("Height of this floor from its base to its ceiling, in %s.", string.lower(MeasurementSystem.UnitName()))),
			change = function(element)
				local n = MeasurementSystem.DisplayToNative(tonumber(element.text))
				if n ~= nil then
					n = n/dmhub.unitsPerSquare
				end
				if n == nil or n ~= round(n) or n < 1 or n > 20 then
					--rejected: restore the stored height and flash the box.
					element.text = FloorHeightText(floor)
					element:PulseClass("invalid")
					return
				end
				if n ~= floor.floorHeightInTiles then
					floor.floorHeightInTiles = n
				end
				element.text = FloorHeightText(floor)
			end,
			refreshFloors = function(element)
				if floor.valid and not element.hasFocus then
					element.text = FloorHeightText(floor)
				end
			end,
		},
		gui.Label{
			classes = {"msFloorUnit", cond(MeasurementSystem.Abbrev() == "", "collapsed")},
			text = MeasurementSystem.Abbrev(),
		},
	}

	if mapObj ~= nil then
		children[#children+1] = gui.Panel{
			classes = {"msRowMenu"},
			bgimage = "phosphor/dots-three-bold.png",
			hover = gui.Tooltip("Map image options"),
			click = ShowMenu,
		}
	end

	return gui.Panel{
		classes = {"msFloorRow", cond(floor.floorid == game.currentFloorId, "selected")},
		rightClick = ShowMenu,
		refreshFloors = function(element)
			element:SetClass("selected", floor.valid and floor.floorid == game.currentFloorId)
		end,
		children = children,
	}
end

--The map's floors, top floor first like the Floors panel. Layers are
--left out: they share their floor's height.
local function CreateFloorRows()
	local floors = game.currentMap.floors or {}
	local rows = {}
	local count = 0
	for i = #floors, 1, -1 do
		local floor = floors[i]
		if floor.parentFloor == nil then
			if count > 0 then
				rows[#rows+1] = gui.Panel{
					classes = {"msFloorSeam"},
					bgimage = "panels/square.png",
				}
			end
			count = count + 1
			rows[#rows+1] = CreateFloorRow(floor, i)
		end
	end
	return rows, count
end

--The map water level (WATER_LEVEL_REFERENCE.md): ground lower than the level is
--under water -- 1 tile or more is deep (swimming), less is shallow (difficult
--terrain for creatures without a swim speed). The record lives on the map
--(game.currentMap.water); every control writes it as one undoable change.
local WaterLevelStep = 0.5

local function WaterRecord()
	return game.currentMap.water
end

--Merge a partial record into the map's water ({level=..} or {visual={..}}).
local function UpdateWater(patch)
	if WaterRecord() == nil then
		return
	end
	game.currentMap.water = patch
end

local function WaterLevelText(level)
	if level == nil then
		return ""
	end
	if level == math.floor(level) then
		return string.format("%d", level)
	end
	return string.format("%.1f", level)
end

--Terrain tilesheets for the surface texture: the built-in Water first, then
--other water terrains, then everything else, by name.
local function WaterTextureOptions()
	local options = {}
	for id, tile in pairs(assets.tilesheets) do
		local ok, isTerrain = pcall(function() return tile.isterrain end)
		if ok and isTerrain then
			local water = false
			pcall(function() water = tile.rules.water end)
			local name = tile.description
			if name == nil or name == "" then
				name = "Terrain"
			end
			options[#options+1] = { id = id, text = name, water = water }
		end
	end
	table.sort(options, function(a, b)
		local ab = (a.id == "fa021543-8a84-4856-8645-47dcb516abe3") and 0 or (a.water and 1 or 2)
		local bb = (b.id == "fa021543-8a84-4856-8645-47dcb516abe3") and 0 or (b.water and 1 or 2)
		if ab ~= bb then
			return ab < bb
		end
		return a.text < b.text
	end)
	local result = {}
	for _, opt in ipairs(options) do
		result[#result+1] = { id = opt.id, text = opt.text }
	end
	return result
end

local function WaterFloorOptions()
	local result = {}
	local floors = game.currentMap.floors or {}
	for i = #floors, 1, -1 do
		local floor = floors[i]
		if floor.parentFloor == nil then
			local name = floor.description
			if name == nil or name == "" then
				name = string.format("Floor %d", i)
			end
			result[#result+1] = { id = floor.floorid, text = name }
		end
	end
	return result
end

local function WaterFieldLabel(text)
	return gui.Label{
		classes = {"formStacked", "sizeXs"},
		width = "98%",
		height = "auto",
		hmargin = 2,
		tmargin = 6,
		text = text,
	}
end

--a stacked slider bound to one visual field.
local function WaterSlider(label, field, minValue, maxValue, labelFormat, roundValue)
	local function Read()
		local water = WaterRecord()
		return water ~= nil and water.visual[field] or minValue
	end
	return gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",
		WaterFieldLabel(label),
		gui.Slider{
			minValue = minValue,
			maxValue = maxValue,
			value = Read(),
			round = roundValue,
			sliderWidth = 150,
			labelWidth = 40,
			labelFormat = labelFormat,
			style = {
				halign = "left",
				lmargin = 6,
				fontSize = "30%",
				height = 24,
				width = 200,
			},
			events = {
				confirm = function(element)
					UpdateWater{ visual = { [field] = element.data.getValue() } }
				end,
				refreshFloors = function(element)
					if WaterRecord() ~= nil then
						element.data.setValueNoEvent(Read())
					end
				end,
			},
		},
	}
end

local function WaterCheck(text, field, tooltip)
	return gui.Check{
		text = text,
		tooltip = tooltip,
		value = WaterRecord() ~= nil and WaterRecord().visual[field] == true,
		style = {
			width = "100%",
			height = 28,
			fontSize = 14,
			hpad = 0,
		},
		change = function(element)
			UpdateWater{ visual = { [field] = element.value } }
		end,
		refreshFloors = function(element)
			local water = WaterRecord()
			if water ~= nil then
				element.value = water.visual[field] == true
			end
		end,
	}
end

local function WaterColor(text, field)
	return gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = 28,
		gui.Label{
			classes = {"formStacked", "sizeXs"},
			width = 110,
			height = "auto",
			valign = "center",
			hmargin = 2,
			text = text,
		},
		gui.ColorPicker{
			value = WaterRecord() ~= nil and tostring(WaterRecord().visual[field]) or "#ffffffff",
			hasAlpha = false,
			width = 24,
			height = 24,
			valign = "center",
			confirm = function(element)
				UpdateWater{ visual = { [field] = element.value } }
			end,
			refreshFloors = function(element)
				local water = WaterRecord()
				if water ~= nil then
					element.value = tostring(water.visual[field])
				end
			end,
		},
	}
end

local function CreateWaterSection()
	local function HasWater()
		return WaterRecord() ~= nil
	end

	local levelLabel
	levelLabel = gui.Label{
		classes = {"msFloorHeight"},
		halign = "left",
		valign = "center",
		text = WaterLevelText(HasWater() and WaterRecord().level or 0),
		editable = true,
		characterLimit = 5,
		hover = gui.Tooltip("The water's surface, in tiles above the floor's base. Ground 1 tile or more below it is deep water; less than 1 is shallow water."),
		change = function(element)
			local n = tonumber(element.text)
			if n == nil or HasWater() == false then
				element.text = WaterLevelText(HasWater() and WaterRecord().level or 0)
				element:PulseClass("invalid")
				return
			end
			game.currentMap:SetWaterLevel(n)
			element.text = WaterLevelText(round(n / WaterLevelStep) * WaterLevelStep)
		end,
		refreshFloors = function(element)
			if HasWater() and not element.hasFocus then
				element.text = WaterLevelText(WaterRecord().level)
			end
		end,
	}

	local function Step(delta)
		if HasWater() then
			game.currentMap:SetWaterLevel(WaterRecord().level + delta)
		end
	end

	local levelRow = gui.Panel{
		flow = "horizontal",
		width = "100%",
		height = 28,
		gui.Label{
			classes = {"formStacked", "sizeXs"},
			width = 110,
			height = "auto",
			valign = "center",
			hmargin = 2,
			text = "Water Level:",
		},
		levelLabel,
		gui.Button{
			text = "-",
			width = 22,
			height = 22,
			lmargin = 8,
			halign = "left",
			valign = "center",
			hover = gui.Tooltip("Lower the water by half a tile."),
			click = function() Step(-WaterLevelStep) end,
		},
		gui.Button{
			text = "+",
			width = 22,
			height = 22,
			lmargin = 4,
			halign = "left",
			valign = "center",
			hover = gui.Tooltip("Raise the water by half a tile."),
			click = function() Step(WaterLevelStep) end,
		},
	}

	---@type Panel[]
	local settings = { levelRow }

	local floorOptions = WaterFloorOptions()
	if #floorOptions > 1 then
		settings[#settings+1] = WaterFieldLabel("Floor:")
		settings[#settings+1] = gui.Dropdown{
			classes = {"formStacked"},
			width = "98%",
			halign = "left",
			lmargin = 6,
			options = floorOptions,
			idChosen = HasWater() and WaterRecord().floor or floorOptions[1].id,
			change = function(element)
				---@cast element Dropdown
				UpdateWater{ floor = element.idChosen }
			end,
			refreshFloors = function(element)
				---@cast element Dropdown
				if HasWater() then
					element.idChosen = WaterRecord().floor
				end
			end,
		}
	end

	--optional zone limit: only squares in zones of one type can flood (a lake
	--beside a dry trench at the same height).
	local zoneOptions = { { id = "", text = "Anywhere low enough" } }
	local zoneTypes = {}
	for id, kw in unhidden_pairs(dmhub.GetTable("environmentalKeywords") or {}) do
		zoneTypes[#zoneTypes+1] = { id = id, text = string.format("Only in %s zones", kw.name or "?") }
	end
	table.sort(zoneTypes, function(a, b) return a.text < b.text end)
	for _, opt in ipairs(zoneTypes) do
		zoneOptions[#zoneOptions+1] = opt
	end
	settings[#settings+1] = WaterFieldLabel("Water Reaches:")
	settings[#settings+1] = gui.Dropdown{
		classes = {"formStacked"},
		width = "98%",
		halign = "left",
		lmargin = 6,
		options = zoneOptions,
		idChosen = HasWater() and WaterRecord().zone or "",
		hover = gui.Tooltip("Where the water can be. Normally everywhere lower than the level; limit it to a zone type when other low ground on the map should stay dry."),
		change = function(element)
			---@cast element Dropdown
			UpdateWater{ zone = element.idChosen }
		end,
		refreshFloors = function(element)
			---@cast element Dropdown
			if HasWater() then
				element.idChosen = WaterRecord().zone
			end
		end,
	}

	settings[#settings+1] = WaterFieldLabel("Appearance:")
	settings[#settings+1] = gui.Dropdown{
		classes = {"formStacked"},
		width = "98%",
		halign = "left",
		lmargin = 6,
		options = {
			{ id = "surface", text = "Draw the water" },
			{ id = "none", text = "Don't draw it (the map art shows it)" },
		},
		idChosen = HasWater() and WaterRecord().visual.mode or "surface",
		change = function(element)
			---@cast element Dropdown
			UpdateWater{ visual = { mode = element.idChosen } }
		end,
		refreshFloors = function(element)
			---@cast element Dropdown
			if HasWater() then
				element.idChosen = WaterRecord().visual.mode
			end
		end,
	}

	--how the drawn water looks; hidden when it is not drawn.
	local appearance = gui.Panel{
		classes = {cond(HasWater() and WaterRecord().visual.mode == "none", "collapsed")},
		width = "100%",
		height = "auto",
		flow = "vertical",
		refreshFloors = function(element)
			element:SetClass("collapsed", HasWater() and WaterRecord().visual.mode == "none")
		end,

		WaterFieldLabel("Surface Texture:"),
		gui.Dropdown{
			classes = {"formStacked"},
			width = "98%",
			halign = "left",
			lmargin = 6,
			options = WaterTextureOptions(),
			idChosen = (HasWater() and WaterRecord().visual.tilesheet ~= "") and WaterRecord().visual.tilesheet or "fa021543-8a84-4856-8645-47dcb516abe3",
			change = function(element)
				---@cast element Dropdown
				UpdateWater{ visual = { tilesheet = element.idChosen } }
			end,
		},
		WaterColor("Shallow Color:", "shallowColor"),
		WaterColor("Deep Color:", "deepColor"),
		WaterSlider("Shallow Opacity:", "minOpacity", 0, 1, "%.2f"),
		WaterSlider("Deep Opacity:", "maxOpacity", 0, 1, "%.2f"),
		WaterSlider("Fully Deep At (tiles):", "fullDepth", 1, 10, "%.1f"),
		WaterSlider("Depth Layers:", "layers", 0, 4, "%d", true),
		WaterCheck("Shoreline foam", "foam", "White foam where the water meets the shore."),
		WaterCheck("Depth lines", "depthLines", "Faint lines on the surface: where the water becomes deep enough to swim, and every further tile."),
		gui.Check{
			text = "Map art already shows this water",
			tooltip = "Only draw water above the current level -- for maps whose art already shows the water. Rising water is drawn over the art; the art's own water is left alone.",
			value = HasWater() and WaterRecord().visual.artLevel ~= nil,
			style = {
				width = "100%",
				height = 28,
				fontSize = 14,
				hpad = 0,
			},
			change = function(element)
				if element.value then
					UpdateWater{ visual = { artLevel = WaterRecord().level } }
				else
					UpdateWater{ visual = { artLevel = false } }
				end
			end,
			refreshFloors = function(element)
				if HasWater() then
					element.value = WaterRecord().visual.artLevel ~= nil
				end
			end,
		},
	}
	settings[#settings+1] = appearance

	local body = gui.Panel{
		classes = {cond(not HasWater(), "collapsed")},
		width = "100%",
		height = "auto",
		flow = "vertical",
		children = settings,
		refreshFloors = function(element)
			element:SetClass("collapsed", not HasWater())
		end,
	}

	return {
		gui.Check{
			text = "Water level",
			tooltip = "Fill everything lower than a water level with water. Creatures float on deep water and can dive; shallow water is difficult terrain for creatures without a swim speed.",
			value = HasWater(),
			style = {
				width = "100%",
				height = 28,
				fontSize = 14,
				hpad = 0,
			},
			change = function(element)
				if element.value then
					if not HasWater() then
						game.currentMap:SetWaterLevel(0)
					end
				else
					game.currentMap.water = nil
				end
			end,
			refreshFloors = function(element)
				element.value = HasWater()
			end,
		},
		body,
	}
end

CreateMapSettings = function()

	local stackedOpts = {stacked = true, height = 28}

	local function Editors(ids)
		local result = {}
		for _, id in ipairs(ids) do
			result[#result+1] = CreateSettingsEditor(id, stackedOpts)
		end
		return result
	end

	local contentPanel

	--All the sections. The map-specific ones (appearance, floors) are why
	--this is rebuilt when the map, floor or floor list changes; the settings
	--editors would follow the map on their own through their monitors.
	local function BuildSections()
		local sections = {}

		--rawget: CodexTitleBar is in another module and may be absent.
		local titleBar = rawget(_G, "CodexTitleBar")
		local appearance = nil
		if titleBar ~= nil and titleBar.CreateMapAppearancePicker ~= nil then
			appearance = titleBar.CreateMapAppearancePicker()
		end
		if appearance ~= nil then
			sections[#sections+1] = CreateSection("appearance", "Map Appearance", { appearance })
		end

		local floorRows, floorCount = CreateFloorRows()
		sections[#sections+1] = CreateSection("floors", "Floors", floorRows, { count = floorCount })

		sections[#sections+1] = CreateSection("players", "Players", Editors{
			"map:playerviewable",
			"map:playerinfobubbles",
		})

		local vision = CreateSettingsEditorsForSection("vision", stackedOpts)
		for _, editor in ipairs(Editors{ "canlookup", "maxlookup" }) do
			vision[#vision+1] = editor
		end
		sections[#sections+1] = CreateSection("vision", "Vision", vision)

		--the tile-type editor is a bare row of icons; name it like the
		--stacked editors around it.
		---@type Panel[]
		local grid = {
			gui.Label{
				classes = {"formStacked", "sizeXs"},
				width = "98%",
				height = "auto",
				hmargin = 2,
				tmargin = 4,
				text = "Grid Type:",
			},
		}
		for _, editor in ipairs(Editors{
			"maplayout:tiletype",
			"maplayout:stagger",
			"maplayout:tilewidth",
			"maplayout:tileheight",
			"maplayout:hexslant",
			"gridcolor",
		}) do
			grid[#grid+1] = editor
		end
		sections[#sections+1] = CreateSection("grid", "Grid", grid)

		sections[#sections+1] = CreateSection("water", "Water", CreateWaterSection())

		sections[#sections+1] = CreateSection("display", "Display", Editors{
			"map:parallaxscale",
			"editor:showpathfinding",
		})

		--Map Scripts live in the Draw Steel module set; rawget so this core panel
		--still works when that module is not loaded.
		local mapScript = rawget(_G, "MapScript")
		if mapScript ~= nil then
			sections[#sections+1] = CreateSection("scripts", "Map Scripts", { mapScript.CreateSettingsPanel() })
		end

		return sections
	end

	--What the map-specific sections were built from: the map, the floor we
	--are on (the appearance gallery is per floor), and each floor's id and name.
	local function Signature()
		local parts = { game.currentMapId or "", game.currentFloorId or "" }
		for _, floor in ipairs(game.currentMap.floors or {}) do
			parts[#parts+1] = string.format("%s=%s", floor.floorid, floor.description or "")
		end
		return table.concat(parts, "|")
	end

	contentPanel = gui.Panel{
		id = "mapSettingsPanel",
		flow = "vertical",
		width = "100%",
		height = "auto",
		bmargin = 8,
		styles = ThemeEngine.MergeTokens(BuildMapSettingsStyles()),
		data = { sig = Signature() },
		children = BuildSections(),

		--height edits from anywhere (this panel, the Floors panel, another client).
		monitorGame = "/mapManifests",
		refreshGame = function(element)
			element:FireEventTree("refreshFloors")
		end,

		--polled: changing the current floor raises no game-data event.
		thinkTime = 0.5,
		think = function(element)
			local sig = Signature()
			if sig == element.data.sig then
				return
			end
			element.data.sig = sig
			element.children = BuildSections()
		end,
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if contentPanel ~= nil and contentPanel.valid then
			contentPanel.styles = ThemeEngine.MergeTokens(BuildMapSettingsStyles()) --[[@as StyleArgs[] ]]
		end
	end)

	return contentPanel

end

CreateEditorSettings = function()

	local contentPanel = gui.Panel{
		flow = "vertical",
		style = {
			pivot = { x = 0, y = 1 },
			width = '100%',
			height = 'auto',
		},
		children = {
			CreateSettingsEditorsForSection('editor'),
			CreateSettingsEditor('dm:showinvisibletokens'),
			CreateSettingsEditor('arrowcolor'),

		},
	}

	return contentPanel
end
