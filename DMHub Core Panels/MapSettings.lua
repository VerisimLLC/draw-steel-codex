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
	help = "If enabled, all players can see this map: they get full vision (no fog of war) on it, and it always appears in their Maps list even if they have no tokens on it.",
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
	icon = "phosphor/map-pin-simple-area-bold.png",
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

CreateMapSettings = function()

	local stackedOpts = {stacked = true}

	local children = {
		CreateSettingsEditor("map:playerviewable", stackedOpts),
		CreateSettingsEditor("map:playerinfobubbles", stackedOpts),
		CreateSettingsEditor("map:parallaxscale", stackedOpts),
		CreateSettingsEditor('gridcolor', stackedOpts),
		CreateSettingsEditorsForSection('vision', stackedOpts),

		CreateSettingsEditor("maplayout:tiletype", stackedOpts),
		CreateSettingsEditor("maplayout:stagger", stackedOpts),
		CreateSettingsEditor("maplayout:tilewidth", stackedOpts),
		CreateSettingsEditor("maplayout:tileheight", stackedOpts),
		CreateSettingsEditor("maplayout:hexslant", stackedOpts),

		CreateSettingsEditor("editor:showpathfinding", stackedOpts),
		CreateSettingsEditor("canlookup", stackedOpts),
		CreateSettingsEditor("maxlookup", stackedOpts),
	}

	--Map Scripts live in the Draw Steel module set; rawget so this core panel
	--still works when that module is not loaded.
	local mapScript = rawget(_G, "MapScript")
	if mapScript ~= nil then
		children[#children+1] = gui.Label{
			classes = {"bold"},
			width = "100%",
			height = "auto",
			fontSize = 16,
			tmargin = 8,
			text = "Map Scripts",
		}
		children[#children+1] = mapScript.CreateSettingsPanel()
	end

	local contentPanel = gui.Panel{
		id = "mapSettingsPanel",
		flow = "vertical",
		style = {
			pivot = { x = 0, y = 1 },
			width = '100%',
			height = 'auto',
		},
		children = children,
	}

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
