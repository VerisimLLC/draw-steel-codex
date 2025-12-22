local mod = dmhub.GetModLoading()

function SettingMatchesSearch(settingid, str)
	str = string.lower(str)
	local settingInfo = Settings[settingid]
	if settingInfo == nil then
		return false
	end

	for k,v in pairs(settingInfo) do
		if type(v) == "string" and string.find(string.lower(v), str, 1, true) then
			return true
		end
	end

	return false
end

setting{
    id = "disableparallax",
    description = "Disable Parallax",
    storage = "preference",
	section = "General",
    editor = "check",
    default = false,
}

setting{
	id = "sensitivity",
	description = "Scroll Sensitivity",
	help = "Controls the speed which the screen moves when panning.",
	storage = "preference",

	editor = "slider",
	format = "F2",
	default = 0.5,
	min = 0.1,
	max = 2,
}

setting{
	id = "wheelsensitivity",
	description = "Mousewheel sensitivity",
	help = "Controls how sensitive the scrollwheel is when zooming in and out of the map.",
	storage = "preference",
    section = "game",

	editor = "slider",
	format = "F2",
	default = 1.0,
	min = 0.1,
	max = 2,
}

setting{
	id = "uiwheelsensitivity",
	description = "UI Mousewheel sensitivity",
	help = "Controls how sensitive the scrollwheel is when using UI elements.",
	storage = "preference",
	editor = "slider",
	format = "F2",
	default = 1.0,
	min = 0.1,
	max = 2,
}

setting{
	id = "terraintool",
	description = "Tool",
	help = "Controls which tool to use to draw terrain",
	storage = "transient",
	editor = "iconbuttons",

	default = 'rectangle',

	enum = {
		{
			value = 'rectangle',
			icon = 'game-icons/square.png',
			help = "Rectangle tool",
		},
		{
			value = 'oval',
			icon = 'game-icons/circle.png',
			help = "Circle & Oval tool",
		},
		{
			value = 'shape',
			icon = 'game-icons/polygon-segments.png',
			help = "Shape tool",
		},
		{
			value = 'curve',
			icon = 'game-icons/curve.png',
			help = "Curves tool",
		},
		{
			value = 'free',
			icon = 'panels/hud/icon_line_tool_82.png',
			help = "Free draw tool",
		},
		{
			value = 'brush',
			icon = 'panels/hud/paint-brush.png',
			help = "Brush tool",
		},
		{
			value = 'picker',
			icon = 'panels/hud/icon-eyedropper.png',
			help = "Picker",
		},
	},
}

setting{
	id = "effectstool",
	description = "Tool",
	help = "Controls which tool to use to draw effects",
	storage = "transient",
	editor = "iconbuttons",

	default = 'brush',

	enum = {
		{
			value = 'rectangle',
			icon = 'game-icons/square.png',
			help = "Rectangle tool",
		},
		{
			value = 'oval',
			icon = 'game-icons/circle.png',
			help = "Circle & Oval tool",
		},
		{
			value = 'shape',
			icon = 'game-icons/polygon-segments.png',
			help = "Shape tool",
		},
		{
			value = 'curve',
			icon = 'game-icons/curve.png',
			help = "Curves tool",
		},
		{
			value = 'free',
			icon = 'panels/hud/icon_line_tool_82.png',
			help = "Free draw tool",
		},
		{
			value = 'brush',
			icon = 'panels/hud/paint-brush.png',
			help = "Brush tool",
		},
		{
			value = 'picker',
			icon = 'panels/hud/icon-eyedropper.png',
			help = "Picker",
		},
	},
}

setting{
	id = "rasterterrainbrush",
	description = "Brush",
	help = "The style of brush to use when drawing terrain.",
	storage = "preference",
	default = "7de378a0-3096-421a-a662-23d2c1acf23b",

	editor = "iconlibrary",
	library = "brush",

	monitorVisible = {'terraintool'},
	visible = function()
		return dmhub.GetSettingValue('terraintool') == 'brush'
	end
}

setting{
	id = "buildingbrush",
	description = "Brush",
	help = "The style of brush to use when drawing buildings.",
	storage = "preference",
	default = "7de378a0-3096-421a-a662-23d2c1acf23b",
	editor = "iconlibrary",
	library = "brush",

	monitorVisible = {'buildingtool'},
	visible = function()
		return dmhub.GetSettingValue('buildingtool') == 'brush'
	end
}

setting{
	id = "rastereffectsbrush",
	description = "Brush",
	help = "The style of brush to use when drawing effects.",
	storage = "preference",
	default = "7de378a0-3096-421a-a662-23d2c1acf23b",
	editor = "iconlibrary",
	library = "brush",

	monitorVisible = {'effectstool'},
	visible = function()
		return dmhub.GetSettingValue('effectstool') == 'brush'
	end
}

setting{
	id = "terrainbrushstyle",
	description = "Brush",
	help = "Controls which style brush to use when drawing terrain",
	storage = "preference",
	editor = "iconbuttons",

	default = 'filled',

	enum = {
		{
			value = 'filled',
			icon = 'game-icons/plain-circle.png',
			help = "A solid, filled in brush",
		},
		{
			value = 'faded',
			icon = 'ui-icons/faded-circle.png',
			help = "A brush which fades at the edges",
		},
	},

	monitorVisible = {'terraintool'},
	visible = function()
		return dmhub.GetSettingValue('terraintool') == 'brush'
	end
}

setting{
	id = "effectsbrushstyle",
	description = "Brush",
	help = "Controls which style brush to use when drawing effects",
	storage = "preference",
	editor = "iconbuttons",

	default = 'filled',

	enum = {
		{
			value = 'filled',
			icon = 'game-icons/plain-circle.png',
			help = "A solid, filled in brush",
		},
		{
			value = 'faded',
			icon = 'ui-icons/faded-circle.png',
			help = "A brush which fades at the edges",
		},
	},

	monitorVisible = {'effectstool'},
	visible = function()
		return dmhub.GetSettingValue('effectstool') == 'brush'
	end
}

setting{
	id = "effectsbrushintensity",
	description = "Brush Intensity",
	help = "Controls how intense the brush is",
	storage = "preference",

	editor = "slider",
	format = "F0",
	default = 20,
	min = 0,
	max = 100,
}

setting{
	id = "effectsbrushmode",
	description = "Mode",
	storage = "preference",
	
	editor = "dropdown",
	default = "airbrush",

	enum = {
		{
			value = "airbrush",
			text = "Airbrush",
		},
		{
			value = "set",
			text = "Paint",
		},
	}
}

setting{
	id = "terrainedgesmoothing",
	description = "Fade Edges",
	help = "Makes the edges smooth when drawing tiles",
	storage = "preference",
	
	editor = "slider",
	format = "F1",
	default = 0.5,
	min = 0,
	max = 1,
	monitorVisible = {'terraintool'},
	visible = function()
		return dmhub.GetSettingValue('terraintool') ~= 'brush'
	end,
}

setting{
	id = "effectsedgesmoothing",
	description = "Fade Edges",
	help = "Makes the edges smooth when drawing tiles",
	storage = "preference",
	
	editor = "slider",
	format = "F1",
	default = 0.5,
	min = 0,
	max = 1,
	monitorVisible = {'effectstool'},
	visible = function()
		return dmhub.GetSettingValue('effectstool') ~= 'brush'
	end,
}

setting{
	id = "heightmaptool",
	description = "Tool",
	help = "Controls which tool to use to draw height maps",
	storage = "transient",
	editor = "iconbuttons",

	default = 'rectangle',

	enum = {
		{
			value = 'rectangle',
			icon = 'game-icons/square.png',
			help = "Rectangle tool",
		},
		{
			value = 'oval',
			icon = 'game-icons/circle.png',
			help = "Circle & Oval tool",
		},
		{
			value = 'shape',
			icon = 'game-icons/polygon-segments.png',
			help = "Shape tool",
		},
--		{
--			value = 'curve',
--			icon = 'game-icons/curve.png',
--			help = "Curves tool",
--		},
--		{
--			value = 'free',
--			icon = 'panels/hud/icon_line_tool_82.png',
--			help = "Free draw tool",
--		},
		{
			value = 'brush',
			icon = 'panels/hud/paint-brush.png',
			help = "Brush tool",
		},
		{
			value = 'picker',
			icon = 'panels/hud/icon-eyedropper.png',
			help = "Picker",
		},
	},
}

setting{
	id = "heightmapbrush",
	description = "Brush",
	help = "The style of brush to use when drawing terrain.",
	storage = "preference",
	default = "7de378a0-3096-421a-a662-23d2c1acf23b",

	editor = "iconlibrary",
	library = "brush",

	monitorVisible = {'heightmaptool'},
	visible = function()
		return dmhub.GetSettingValue('heightmaptool') == 'brush'
	end
}



setting{
	id = "selectiontool",
	description = "Tool",
	help = "Controls which tool to use to select areas",
	storage = "transient",
	editor = "iconbuttons",


	default = 'none',

	enum = {
		{
			value = 'rectangle',
			icon = 'game-icons/square.png',
			help = "Rectangle tool",
		},
		{
			value = 'oval',
			icon = 'game-icons/circle.png',
			help = "Circle & Oval tool",
		},
		{
			value = 'shape',
			icon = 'game-icons/polygon-segments.png',
			help = "Shape tool",
		},
		{
			value = 'curve',
			icon = 'game-icons/curve.png',
			help = "Curves tool",
		},
		{
			value = 'free',
			icon = 'panels/hud/icon_line_tool_82.png',
			help = "Free draw tool",
		},
		{
			value = 'translate',
			icon = 'ui-icons/icon-translate.png',
			help = "Move the selected area",
		},
		{
			value = 'scale',
			icon = 'ui-icons/icon-scale.png',
			help = "Scale the selected area",
		},
		{
			value = 'rotate',
			icon = 'ui-icons/icon-rotate.png',
			help = "Rotate the selected area",
		},
	},
}

setting{
	id = "buildingtool",
	description = "Tool",
	help = "Controls which tool to use to draw buildings",
	storage = "transient",
	editor = "iconbuttons",

	default = 'rectangle',

	enum = {
		{
			value = 'rectangle',
			icon = 'game-icons/square.png',
			help = "Rectangle tool",
		},
		{
			value = 'oval',
			icon = 'game-icons/circle.png',
			help = "Circle & Oval tool",
		},
		{
			value = 'shape',
			icon = 'game-icons/polygon-segments.png',
			help = "Shape tool",
		},
		{
			value = 'curve',
			icon = 'game-icons/curve.png',
			help = "Curves tool",
		},
		{
			value = 'free',
			icon = 'panels/hud/icon_line_tool_82.png',
			help = "Free draw tool",
		},
		{
			value = 'brush',
			icon = 'panels/hud/paint-brush.png',
			help = "Brush tool",
		},
		{
			value = 'picker',
			icon = 'panels/hud/icon-eyedropper.png',
			help = "Picker",
		},
		{
			value = 'points',
			icon = 'icons/icon_gesture/icon_gesture_47.png',
			help = "Edit Points",
		},
	},
}

--grid setting for this map, controlled by the DM.
setting{
	id = "gridcolor",
	description = "Grid Color",
	help = "Color of the grid overlaying the map",
	storage = "map",

	editor = "color",
	default = core.Color('#00000044'),
}

--a grid on/off setting for players.
setting{
	id = "showgrid",
	description = "Show Grid",
	help = "Show the map grid",
	storage = "preference",

	editor = "check",
	default = true,
}

setting{
	id = "indoorlighting",
	description = "Indoor Lighting",
	help = "Color of the indoor lighting",
	storage = "map",
	hasAlpha = false,

	editor = "color",
	default = core.Color('#ffffffff'),
}

setting{
	id = "outdoorlighting",
	description = "Outdoor Lighting",
	help = "Color of the outdoor lighting",
	storage = "map",
	hasAlpha = false,

	editor = "color",
	default = core.Color('#ffffffff'),
}

setting{
	id = "vision:lineofsight",
	section = "vision",
	description = "Line of Sight",
	help = "Players can only see things that are within their line of sight",
	storage = "map",

	editor = "check",
	default = true,
}

setting{
	id = "vision:shared",
	section = "vision",
	description = "Players Shared Vision",
	help = "Players share vision with each other",
	storage = "game",

	editor = "check",
	default = true,
}

setting{
	id = "vision:limitrange",
	section = "vision",
	description = "Limit Vision Range",
	help = "Creatures can see a limited distance",
	storage = "map",

	editor = "check",
	default = false,
}

setting{
	id = "vision:range",
	section = "vision",
	description = "Range",
	help = "Number of units a unit can see",
	storage = "map",
	
	editor = "slider",
	format = "F0",
	default = 20,
	min = 2,
	max = 60,

	monitorVisible = {'vision:limitrange'},
	visible = function()
		return dmhub.GetSettingValue('vision:limitrange')
	end
}

setting{
	id = "vision:limitfieldofview",
	section = "vision",
	description = "Limit Field of View",
	help = "Make it so creatures can only see in front of them",
	storage = "map",

	editor = "check",
	default = false,
}

setting{
	id = "vision:fieldofview",
	section = "vision",
	description = "Field of View",
	help = "Degrees in front of them that creatures can see",
	storage = "map",
	
	editor = "slider",
	format = "F0",
	default = 120,
	min = 30,
	max = 360,

	monitorVisible = {'vision:limitfieldofview'},
	visible = function()
		return dmhub.GetSettingValue('vision:limitfieldofview')
	end
}

--basic radius of full vision range they get even with field of view set.
setting{
	id = "vision:fieldofviewfullvisionrange",
	section = "vision",
	description = "Full Vision Radius",
	help = "Radius that tokens can see in all directions even with field of view set",
	storage = "map",
	
	editor = "slider",
	format = "F0",
	default = 1,
	min = 0,
	max = 8,

	monitorVisible = {'vision:limitfieldofview'},
	visible = function()
		return dmhub.GetSettingValue('vision:limitfieldofview')
	end
}

setting{
	id = "vision:fogofwar",
	section = "vision",
	description = "Fog of War",
	help = "Controls what players see in areas not directly visible to them.",
	storage = "map",

	editor = "dropdown",
	default = false,

    enum = {
        {
            value = false,
            text = "Darkness",
        },
        {
            value = true,
            text = "Memory",
        },
        {
            value = "dither",
            text = "Dim",
        },
    }
}

setting{
	id = "vision:fogofwarclear",
	section = "vision",
	description = "Clear Map Memory",
	help = "Players lose memory of areas of the map they have seen",
	storage = "map",

	editor = "buttonincrement",
	default = 0,
}

setting{
	id = "vision:blur",
	section = "vision",
	description = "Map Vision Blur",
	help = "Blur on the edge of vision.",
	storage = "game",

	min = 0,
	max = 1,

	editor = "slider",
	default = 0.6,
}

setting{
	id = "blurkernel",
	min = 0,
	max = 16,
	default = 4,
	editor = "slider"
}

setting{
	id = "tabletop",
	default = false,
}


setting{
	id = "dev",
	description = "Developer Mode",
	storage = "preference",

	editor = "check",
	default = false,
}

setting{
	id = "debug",
	description = "Debugging",
	storage = "preference",
	editor = "check",
	default = false,
}

setting{
	id = "showdeleted",
	description = "Shows library items that have been deleted",
	storage = "preference",

	editor = "check",
	default = false,
}

setting{
	id = "ribbons",
	description = "Show token ribbons",
	storage = "preference",

	editor = "check",
	default = false,
}

setting{
	id = "camerafollow",
	description = "Camera Follows Your Token",
	storage = "preference",

	editor = "check",
	default = true,
}

setting{
	id = "perf:autoarchive",
	description = "Optimize game performance",
	storage = "game",
	editor = "check",

	default = false,
}

setting{
	id = "perf:postprocess",
	description = "Camera Filters",
	storage = "preference",
	editor = "check",

	default = true,
}

setting{
	id = "perf:hideftextures",
	description = "High Definition Textures",
	storage = "preference",
	editor = "check",

	default = true,
}

setting{
	id = "perf:hidefdice",
	description = "High Definition Dice",
	storage = "preference",
	editor = "check",

	default = true,
}

setting{
	id = "hidef",
	description = "High Definition",
	storage = "preference",
	editor = "check",

	default = true,
}

setting{
	id = "perf:castshadows",
	description = "Lights Cast Shadows",
	storage = "preference",
	editor = "check",

	default = true,
}

setting{
	id = "perf:hdr",
	description = "HDR Rendering",
	storage = "preference",
	editor = "check",

	default = true,
}

setting{
	id = "perf:msaa",
	description = "MSAA",
	storage = "preference",
	editor = "check",

	default = true,
}

setting{
    id = "perf:nocompress",
    description = "Uncompressed Textures",
    storage = "preference",
    editor = "check",
    default = false,
}



setting{
	id = "fullscreen",
	description = "Fullscreen",
	storage = "preference",

	editor = "check",
	default = true,
}

setting{
	id = "edgepan",
	description = "Scroll Screen When Mouse at Edge",
	storage = "preference",

	editor = "check",
	default = false,
}

setting{
	id = "editor:showpathfinding",
	section = "editor",
	description = "Show Pathfinding Overlay",
	help = "Displays an overlay with the pathfinding logic DMHub has calculated based on your map",
	storage = "transient",

	editor = "check",
	default = false,
}

setting{
	id = "editor:snaptogrid",
	section = "editor",
	description = "Snap to Grid",
	help = "Edits will be snapped to the grid",
	storage = "preference",

	editor = "check",
	default = true,
}

setting{
	id = "editor:snaptogridobjects",
	section = "editor",
	description = "Snap Objects to Grid",
	help = "Objects will be snapped to the grid",
	storage = "preference",

	editor = "check",
	default = false,
}

setting{
	id = "blackbarsoff",
	description = "Transparent UI",
	storage = "preference",

	invalidatesStyles = true,
	editor = "check",
	default = true,
}

setting{
	id = "terrain:stabilization",
	description = "Smoothing",
	storage = "preference",

	editor = "slider",
	default = 0,
	min = 0,
	max = 10,
	round = true,
	labelFormat = '%d',

	monitorVisible = {'terraintool'},
	visible = function()
		return dmhub.GetSettingValue('terraintool') == 'free'
	end
}

setting{
	id = "effects:stabilization",
	description = "Smoothing",
	storage = "preference",

	editor = "slider",
	default = 0,
	min = 0,
	max = 10,
	round = true,
	labelFormat = '%d',

	monitorVisible = {'effectstool'},
	visible = function()
		return dmhub.GetSettingValue('effectstool') == 'free'
	end
}

setting{
	id = "building:wallsnapradius",
	description = "The radius in which to snap walls when using the free draw tool or polygon tool",
	storage = "preference",

	default = 0.2,
	min = 0,
	max = 1,
}

setting{
	id = "building:wallheight",
	storage = "preference",

	default = 0,
	min = 0,
	max = 10,
}

setting{
	id = "building:stabilization",
	description = "Smoothing",
	storage = "preference",

	editor = "slider",
	default = 0,
	min = 0,
	max = 10,
	round = true,
	labelFormat = '%d',

	monitorVisible = {'buildingtool'},
	visible = function()
		return dmhub.GetSettingValue('buildingtool') == 'free'
	end
}

setting{
	id = "terrain:lockopacity",
	description = "Lock Opacity",
	storage = "transient",

	editor = "check",
	default = false,
}

setting{
	id = "building:erase",
	description = "Erase",
	storage = "transient",

	editor = "check",
	default = false,
}

setting{
	id = "terrain:erase",
	description = "Erase",
	storage = "transient",

	editor = "check",
	default = false,
}

setting{
	id = "effects:erase",
	description = "Erase",
	storage = "transient",

	editor = "check",
	default = false,
}

setting{
	id = "dm:showinvisibletokens",
	description = "Show Invisible Tokens",
	storage = "preference",

	editor = "check",
	default = true,
}

setting{
	id = "theme.charsheet",
	description = "Character Sheet Theme",
	help = "Which theme to use when displaying character sheets",
	storage = "account",
	editor = "dropdown",

	default = 'default',

	enumCalc = function()
		local result = {
			{
				value = 'default',
				text = 'Default',
			}
		}

		for k,theme in pairs(assets.themes) do
			result[#result+1] = {
				value = k,
				text = theme.description,
			}
		end

		return result
	end,
}

setting{
	id = "theme.DockablePanel",
	storage = "account",
	default = "default",
}

setting{
	id = "itemsAcknowledged",
	storage = "account",
	default = {},
}

setting{
	id = "leftdockoffscreen",
	storage = "pergamepreference",
	default = false,
}

setting{
	id = "rightdockoffscreen",
	storage = "pergamepreference",
	default = false,
}

setting{
	id = "diceequipped",
	description = "Dice Set",
	help = "Which dice set to use for dice rolls",
	storage = "account",
	editor = "dropdown",

	default = 'Default',
	enumCalc = function()
		local result = dice.GetAvailableDice()
		table.sort(result, function(a,b) return a.text < b.text end)
		return result
	end,
}

local diceWithColors = { "Default", "Chalk Stone", "Chrome", "Shiny Marble", }
local diceWithColorsMap = {}
for _,d in ipairs(diceWithColors) do
	diceWithColorsMap[d] = true
end

setting{
	id = "dicecolor",
	description = "Dice Color",

	storage = 'account',
	editor = 'color',
	hasAlpha = false,
	default = core.Color('#ff0000ff'),

	monitorVisible = {'diceequipped'},
	visible = function()
		return diceWithColorsMap[dmhub.GetSettingValue('diceequipped')] 
	end
}

setting{
	id = "displayname",
	description = "Display Name",
	characterLimit = 24,
	editor = 'input',
	storage = 'account',

	default = '',
}

setting{
	id = "playercolor",
	description = "Player Color",

	storage = 'account',
	editor = "color",
	default = core.Color('#ffffffff'),
}

setting{
	id = "dice:gravity",
	description = "Dice Gravity",

	storage = "transient",
	editor = "slider",
	default = 22,
	min = 0.1,
	max = 30,
}

setting{
	id = "dice:velocity",
	description = "Dice Velocity",

	storage = "transient",
	editor = "slider",
	default = 5.0,
	min = 1,
	max = 30,
}

setting{
	id = "dice:drag",
	description = "Dice Drag",

	storage = "transient",
	editor = "slider",
	default = 1.5,
	min = 0,
	max = 5,
}

setting{
	id = "dice:angulardrag",
	description = "Dice Angular Drag",

	storage = "transient",
	editor = "slider",
	default = 1,
	min = 0,
	max = 5,
}


setting{
	id = "dice:bounciness",
	description = "Dice Bounciness",

	storage = "transient",
	editor = "slider",
	default = 0.8,
	min = 0,
	max = 1,
}

setting{
	id = "weather",
	description = "Weather",

	storage = "map",
	editor = "dropdown",

	default = 'none',

	assetsRefresh = true,

	getOptions = function(element)
		local result = { { id = 'none', text = 'None' } }

		local weatherEffects = assets.weatherEffects
		for k,effect in pairs(weatherEffects) do
			result[#result+1] = { id = k, text = effect.description }
		end

		return result
	end,
}

setting{
	id = "zoom",
	description = "Zoom",

	storage = "pergamepreference",
	editor = "slider",
	default = 0.75,
	max = 1,
	min = 0,
}

setting{
	id = "showplayervision",
	description = "Show Player Vision",

	default = true,
	editor = "check",
	storage = "preference",
}

setting{
    id = "playervisionoverlay",
    description = "Player Vision Overlay",
	classes = {"dmonly"},
	section = "General",
    default = false,
    editor = "check",
    storage = "preference",
}

--ensure playervisionoverlay is reset.
setting{
    id = "playervisionoverlay_version",
    default = 1,
    storage = "preference",
}

if dmhub.GetSettingValue("playervisionoverlay_version") < 3 then
    dmhub.SetSettingValue("playervisionoverlay", false)
    dmhub.SetSettingValue("playervisionoverlay_version", 3)
end

setting{
	id = "dmillumination",
	description = "GM Darkvision",

	default = true,
	editor = "check",
	storage = "preference",
}

setting{
	id = "arrowcolor",
	description = "Arrow Color",

	editor = "color",
	default = core.Color('#521f1e'),

	storage = "preference",
}

setting{
	id = "arrowimage",
	description = "Arrow Image",
	default = "panels/arrow.png",

	storage = "preference",
}

setting{
	id = "fakelag",
	default = 0,
	storage = "transient",
}

setting{
	id = "lightflickerspeed",
	default = 2.7,
	storage = "transient",
}

setting{
	id = "lightflickercolorchange",
	default = 2,
	storage = "transient",
}

setting {
	id = "volume",
	description = "Master Volume",
	section = "Audio",
	editor = "slider",
	ord = "AAA",
	min = 0,
	max = 100,
	default = 100,
	labelFormat = "%d",
	storage = "preference",
}


setting {
	id = "dicethreshold",
	description = "Dice Threshold",
	editor = "slider",
	min = 0,
	max = 1,
	default = 0.99,
	storage = "preference",
}

setting {
	id = "dicesolver",
	description = "Dice Solver",
	editor = "slider",
	min = 10,
	max = 100,
	default = 10,
	storage = "preference",
}

setting{
	id = "randomizeMonsters",
	classes = {"dmonly"},
	description = "Auto-Randomize Monster Hitpoints",
	editor = "check",
	default = true,
	storage = "game",
}

setting{
	id = "autorollall",
	description = "Auto-roll all dice",
	editor = "check",
	default = false,
	storage = "game",
}

--this will be in the format { (rollid) = { autoroll = bool, hideFromPlayers = bool, quickRoll = bool }}
setting{
	id = "monsterSaves:autoroll",
	classes = {"dmonly"},
	description = "Auto-roll saving throws for monsters",
	editor = "check",
	default = false,
	storage = "preference",
}

setting{
	id = "preroll",
	classes = {"dmonly"},
	description = "DM Pre-rolls",
	editor = "check",
	default = false,
	storage = "preference",
}


setting{
	id = "monsterSaves:hideFromPlayers",
	classes = {"dmonly"},
	description = "Hide saving throws for monsters from players",
	editor = "check",
	default = false,
	storage = "preference",
}

setting{
	id = "monsterSaves:quickRoll",
	classes = {"dmonly"},
	description = "Instantly roll monster saving throws",
	editor = "check",
	default = false,
	storage = "preference",
}

setting{
	id = "individualMonsterInitiative",
	classes = {"dmonly"},
	description = "Individual monster initiative",
	editor = "check",
	default = false,
	storage = "game",
}

setting{
	id = "realtimetokenupdates",
	classes = {"dmonly"},
	description = "Show player movement previews",
	editor = "check",
	default = false,
	storage = "game",
}

setting{
	id = "longclicktime",
	description = "Time required to hold down mouse to classify as a long click",
	default = 0.35,
	storage = "preference",
}

setting{
	id = "permissions.playerlibrary",
	description = "Allow players to access the library",
	default = true,
	storage = "game",
}

setting{
	id = "particles:max",
	default = 1000,
	storage = "game",
}

setting{
	id = "hideinvisobjects",
	description = "When set, objects that are invisible to players are also hidden from the DM.",
	default = false,
	storage = "transient",
}


setting{
	id = "measure:shape",
	description = "Shape",
	default = "ruler",
	editor = "dropdown",
	enum = {
		{
			value = "ruler",
			text = "Ruler",
			bind = "alt+r",
		},
		{
			value = "circle",
			text = "Circle",
			bind = "alt+c",
		},
		{
			value = "square",
			text = "Square",
			bind = "alt+s",
		},
		{
			value = "cone",
			text = "Cone",
			bind = "alt+o",
		},
		{
			value = "line",
			text = "Line",
			bind = "alt+l",
		},
		{
			value = "rectangle",
			text = "Rectangle",
			bind = "ctrl+r",
		},
        {
            value = "polygon",
            text = "Custom Shape",
            bind = "ctrl+p",
        },
	},
}

setting{
	id = "measure:coneangle",
	description = "Cone Angle",
	default = 60,
	editor = "dropdown",
	enum = {
		{
			value = 30,
			text = "30",
		},
		{
			value = 45,
			text = "45",
		},
		{
			value = 60,
			text = "60",
		},
	},

	monitorVisible = {'measure:shape'},
	visible = function()
		return dmhub.GetSettingValue('measure:shape') == "cone"
	end,
}

setting{
	id = "measure:linewidth",
	description = "Line Width",
	default = 4,
	editor = "slider",
	format = "F0",
	default = 1,
	min = 1,
	max = 16,
	monitorVisible = {'measure:shape'},
	visible = function()
		return dmhub.GetSettingValue('measure:shape') == "line"
	end,

}


setting{
	id = "measure:share",
	description = "Display to others",
	default = false,
	editor = "check",
	storage = "preference",
}

setting{
	id = "measure:snap",
	description = "Snap",
	storage = "preference",

	editor = "dropdown",
	default = "none",

	enum = {
		{
			value = "none",
			text = "None",
		},
		{
			value = "center",
			text = "Center",
		},
		{
			value = "corner",
			text = "Corner",
		},
	},
}

setting{
	id = "measure:persistent",
	description = "Persist on Map",
	storage = "preference",

	bind = "alt+p",

	editor = "check",
	default = false,
	classes = {"dmonly"},
}

setting{
	id = "inventory:treasure",
	description = "Show Treasure",
	default = false,
	editor = "check",
	storage = "preference",
}

setting{
	id = "inventory:magicalitems",
	description = "Show Magical Items",
	default = false,
	editor = "check",
	storage = "preference",
}

setting{
	id = "inventory:generationclears",
	description = "Generating Inventory Clears Existing Inventory",
	default = true,
	editor = "check",
	storage = "preference",
}

--internal setting modified when dice are being previewed.
setting{
	id = "__previewdice",
	default = false,
	storage = "transient",
}

--how much moving one brush radius reduces pen pressure by.
setting{
	id = "penpressuremovement",
	default = 0.2,
	storage = "preference",
}

--how much one second of holding increases pen pressure by.
setting{
	id = "penpressuretime",
	default = 0.2,
	storage = "preference",
}

setting{
	id = "penpressurecurve",
	default = {
		points = {
			{x = 0, y = 0, z = 0},
			{x = 0.5, y = 0.4, z = 0},
			{x = 1, y = 1, z = 0},
		},
		displayRange = {x = 0, y = 1},
		xmapping = {x = 0, y = 1},
	},
	storage = "preference",
}

setting{
	id = "favoriteemoji",
	default = nil,
	storage = "preference",
}

setting{
	id = "showtutorial",
	default = true,
	storage = "preference",
}

setting{
	id = "hideactionbar",
	default = false,
	storage = "transient",
}

setting{
	id = "dicespeed",
	description = "Dice Speed",
	storage = "game",
	classes = {"dmonly"},

	editor = "dropdown",
	default = "normal",

	enum = {
		{
			value = "normal",
			text = "Normal",
		},
		{
			value = "fast",
			text = "Fast",
		},
		{
			value = "veryfast",
			text = "Instant",
		},
	}
}

setting{
	id = "module:lastpublished",
	description = "The ID of the last module you published",
	storage = "preference",
	default = "new",
}

setting{
	id = "lang",
	description = "The language being used",
	storage = "preference",
	default = "",
}

--time inside the game, a number where 0 = midnight, 0.5 = midday, 1 = midnight again.
setting{
	id = "gametime",
	description = "Time",

	storage = "game",
	editor = "slider",
	default = 0.5,
}

--the server time which gametime corresponds to.
setting{
	id = "gametimebasis",
	description = "Time Basis",

	storage = "game",
	default = 1618116759,
}

setting{
	id = "rendermode",
	storage = "transient",
	default = "all",
}

setting{
	id = "renderfloor",
	storage = "transient",
	default = -1,
}

setting{
	id = "constraintogrid",
	description = "Constrain Tokens to Grid",
	editor ="dropdown",
	storage = "game",
	default = "always",
	enum = {
		{
			value = "always",
			text = "Always",
		},
		{
			value = "combat",
			text = "During Combat",
		},
	},
}

--setting{
--	id = "dev:webm",
--	description = "Webm video",
--	storage = "preference",
--	default = false,
--	editor = "check",
--}
--
--setting{
--	id = "dev:mp4",
--	description = "MP4 video",
--	storage = "preference",
--	default = false,
--	editor = "check",
--}

setting{
	id = "diagonals",
	description = " Diagonal Movement Rules",
	editor = "dropdown",
	storage = "game",
	section = "Game",
	default = cond(dmhub.whiteLabel == "mcdm", "free", "weighted"),
	enum = {
		{
			value = "free",
			text = "Move Freely",
		},
		{
			value = "weighted",
			text = "Weighted Diagonals",
		},
		{
			value = "manhattan",
			text = "Manhattan Distances",
		},
	},

}


setting{
	id = "tokenmovementradius",
	description = "Show Movement Radius",
	editor = "dropdown",
	storage = "preference",
	default = "turn",
	section = "General",

	enum = {
		{
			value = "turn",
			text = "On Character's Turn",
		},
		{
			value = "combat",
			text = "During combat",
		},
		{
			value = "always",
			text = "Always",
		},
		{
			value = "never",
			text = "Never",
		},
	}
}

--DEPRECATED
setting{
	id = "mapmemorygradient",
	description = "Map Memory Gradient",
	default = "d0023f28-a2f6-46a9-a724-0a41505cd3f3",
}

setting{
	id = "maxmoveduration",
	description = "Max. Character Movement Duration",
	editor = "slider",
	storage = "game",
	default = 1,
	min = 0,
	max = 5,
}

setting{
	id = "movespeed",
	description = "Character Movement Speed",
	editor = "slider",
	storage = "game",
	default = 5,
	min = 1,
	max = 20,
}

setting{
	id = "maxplayerzoom",
	description = "Maximum the map can be zoomed out by players",
	editor = "slider",
	storage = "game",
	default = 0,
	min = 0,
	max = 1,
}

setting{
	id = "maxzoom",
	description = "Maximum the map can be zoomed out",
	editor = "slider",
	storage = "preference",
	default = 120,
	min = 50,
	max = 300,
}

setting{
	id = "tokentracker",
	description = "Show off-screen token trackers",
	editor = "check",
	storage = "preference",
	default = true,
	section = "General",
}

setting{
	id = "simpleradiusmarker",
	description = "Make the radius marker not use a video",
	default = false,
	storage = "preference",
}

setting{
	id = "codemod:safemode",
	description = "Disable Local Mods",
	default = false,
	editor = "check",
	storage = "preference",
}

setting{
	id = "maplayout:tiletype",
	description = "Map Tiling",
	storage = "map",
	default = "squares",
	onchange = function() dmhub.RefreshMapLayout(); game.Refresh() end,
	editor = "iconbuttons",
	enum = {
		{
			value = "squares",
			text = "Squares",

			icon = 'ui-icons/tile-square.png',
			help = "Squares",
		},
		{
			value = "flattop",
			text = "Hexes (Flat Top)",

			icon = 'ui-icons/tile-flathex.png',
			help = "Flat-top hexes",

		},
		{
			value = "pointtop",
			text = "Hexes (Pointy Top)",

			icon = 'ui-icons/tile-pointyhex.png',
			help = "Pointy-top hexes",
		},
--	{
--		value = "isometric",
--		text = "Isometric",
--		icon = 'ui-icons/tile-isometric.png',
--		help = "Isometric tiles",
--	},
		{
			value = "custom",
			text = "Custom",
			icon = 'ui-icons/tile-custom.png',
			help = "Custom tiles",
		},
	},
}

setting{
	id = "maplayout:stagger",
	description = "Tile Shape",
	storage = "map",
	default = "none",
	monitorVisible = {'maplayout:tiletype'},
	visible = function()
		return dmhub.GetSettingValue('maplayout:tiletype') == 'custom'
	end,
	onchange = function() dmhub.RefreshMapLayout(); game.Refresh() end,
	editor = "dropdown",


	enum = {
		{
			value = "none",
			text = "Squares",
		},
		{
			value = "vertical",
			text = "Hexes (Flat Top)",
		},
		{
			value = "horizontal",
			text = "Hexes (Pointy Top)",
		},
	}
}

setting{
	id = "maplayout:tilewidth",
	description = "Tile Width",
	editor = "slider",
	storage = "map",
	default = 1,
	min = 0.5,
	max = 2,
	monitorVisible = {'maplayout:tiletype'},
	onchange = function() dmhub.RefreshMapLayout(); game.Refresh() end,
	visible = function()
		return dmhub.GetSettingValue('maplayout:tiletype') == 'custom'
	end,
}

setting{
	id = "maplayout:tileheight",
	description = "Tile Height",
	editor = "slider",
	storage = "map",
	default = 1,
	min = 0.5,
	max = 2,
	monitorVisible = {'maplayout:tiletype'},
	onchange = function() dmhub.RefreshMapLayout(); game.Refresh() end,
	visible = function()
		return dmhub.GetSettingValue('maplayout:tiletype') == 'custom'
	end,
}

setting{
	id = "maplayout:hexslant",
	description = "Hex Slant",
	storage = "map",
	editor = "slider",
	default = 0,
	min = 0,
	max = 0.5,
	monitorVisible = {'maplayout:tiletype'},
	onchange = function() dmhub.RefreshMapLayout(); game.Refresh() end,
	visible = function()
		return dmhub.GetSettingValue('maplayout:tiletype') == 'custom'
	end,
}

setting{
	id = "dev:testbandwidthlimit",
	description = "Test Bandwidth Limit",
	storage = "transient",
	default = -1,
}

setting{
	id = "showshop",
	description = "Show the shop",
	storage = "transient",
	default = false,
}

setting{
	id = "dev:testdicemodel",
	default = "",
	storage = "transient",
}

--fog setting for this game, controlled by the DM.
setting{
	id = "fogcolor",
	description = "Map Memory Color",
	help = "Color of the area that players remember but can no longer see",
	storage = "game",

	editor = "color",
	default = core.Color('#CC6D29FF'),
}

setting{
	id = "selectedtokenvision",
	description = "Show vision of selected tokens",
	storage = "preference",

	classes = {"dmonly"},

	editor = "check",

	default = false,
}

setting{
	id = "hidedicebehinddialogs",
	description = "Hide Dice Rolls During Dialogs",
	help = "Dice rolls from other players will be hidden when you have a dialog open",
	storage = "preference",
	editor = "check",
	default = false,
	section = "General",
}

setting{
	id = "graphics:uiblur",
	description = "Transparent UI",
	default = true,
	editor = "check",
	storage = "preference",
}

setting{
	id = "graphics:usegamma",
	description = "Use Gamma Correction",
	default = false,
	editor = "check",
	storage = "preference",
}

setting{
	id = "graphics:gamma",
	description = "Gamma Correction",
	default = 0.5,
	storage = "preference",
	
	editor = "slider",
	format = "F1",
	default = 0,
	min = -1,
	max = 1,
}

setting{
	id = "osr:shade4",
	description = "Bright Level 4",
	editor = "color",
	default = core.Color('#FFFFFFFF'),
	storage = "game",
	section = "GameLighting",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,

}

setting{
	id = "osr:shade3",
	description = "Bright Level 3",
	editor = "color",
	default = core.Color('#DDDDDDFF'),
	storage = "game",
	section = "GameLighting",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,

}

setting{
	id = "osr:shade2",
	description = "Bright Level 2",
	editor = "color",
	default = core.Color('#AAAAAAFF'),
	storage = "game",
	section = "GameLighting",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,

}

setting{
	id = "osr:shade1",
	description = "Bright Level 1",
	editor = "color",
	default = core.Color('#777777FF'),
	storage = "game",
	section = "GameLighting",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,

}

setting{
	id = "osr:threshold4",
	description = "Bright Threshold 4",
	default = 1.4,
	min = 0,
	max = 2,
	storage = "game",
	section = "GameLighting",
	
	editor = "slider",
	format = "F1",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,

}

setting{
	id = "osr:threshold3",
	description = "Bright Threshold 3",
	default = 1,
	min = 0,
	max = 2,
	storage = "game",
	section = "GameLighting",
	
	editor = "slider",
	format = "F1",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,

}

setting{
	id = "osr:threshold2",
	description = "Bright Threshold 2",
	default = 0.6,
	min = 0,
	max = 2,
	storage = "game",
	section = "GameLighting",
	
	editor = "slider",
	format = "F1",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,

}

setting{
	id = "osr:threshold1",
	description = "Bright Threshold 1",
	default = 0.3,
	min = 0,
	max = 2,
	storage = "game",
	section = "GameLighting",
	
	editor = "slider",
	format = "F1",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,
}

setting{
	id = "osr:blend",
	description = "Brightness Blending",
	default = 0.5,
	min = 0,
	max = 1,
	storage = "game",
	section = "GameLighting",

	editor = "slider",
	format = "F1",
	monitorVisible = {'lightingengine'},
	visible = function()
		return dmhub.GetSettingValue('lightingengine') == 'oldschool'
	end,
}


setting{
	id = "lightingengine",
	ord = "AAA", --put ahead of any other lighting settings.
	description = "Lighting Engine",
	editor = "dropdown",
	default = "default",
	storage = "game",
	section = "GameLighting",


	enum = {
		{
			value = "default",
			text = "Default",
		},
		{
			value = "oldschool",
			text = "Old School",
		},
	}

}

setting{
	id = "wallsfollowparallax",
	description = "Walls will use the parallax map settings",
	default = false,
	storage = "map",
}

setting{
	id = "popoutavatars",
	description = "Allow Popout Avatars",
	default = false,
	storage = "game",
}

setting{
	id = "dmillegalmoves",
	description = "The DM can make illegal moves",
	default = true,
	storage = "game",
}

setting{
	id = "vsync",
	description = "VSync",
	storage = "preference",
	editor = "dropdown",
	default = 1,
	enum = {
		{
			value = 1,
			text = "Use Vsync",
		},
		{
			value = 0,
			text = "No Vsync",
		}
	},
}

setting{
	id = "fps",
	description = "FPS",
	default = 60,
	storage = "preference",
	editor = "dropdown",

	monitorVisible = {'vsync'},
	visible = function()
		return dmhub.GetSettingValue('vsync') == 0
	end,

	enum = {
		{
			value = 24,
			text = "24",
		},
		{
			value = 30,
			text = "30",
		},
		{
			value = 60,
			text = "60",
		},
	}
}

setting{
	id = "backgroundfps",
	description = "Reduce FPS in background",
	editor = "check",
	default = true,
	storage = "preference",
}

setting{
	id = "showcanopy",
	description = "Show Tree Canopies",
	default = true,
	storage = "preference",
}

setting{
	id = "gmbroadcastmouse",
	description = "GM Mouse Position Shared",
	classes = {"dmonly"},
	section = "Game",
	default = 1,
	storage = "game",
	editor = "check",
}

setting{
	id = "playerbroadcastmouse",
	description = "Player Mouse Positions Shared",
	classes = {"dmonly"},
	section = "Game",
	default = 1,
	storage = "game",
	editor = "check",
}

setting{
	id = "ignorebroadcastmouse",
	description = "Hide Other Player's Cursors",
	section = "General",
	default = false,
	storage = "preference",
	editor = "check",
}

setting{
	id = "useparallax",
	description = "Use Parallax",
	classes = {"dmonly"},
	--section = "Game",
	default = false,
	storage = "game",
	editor = "check",
}

setting{
	id = "parallaxratio",
	description = "Parallax",
	classes = {"dmonly"},
	default = 0.6,
	section = "Game",
	storage = "game",
	editor = "dropdown",
	enum = {
		{
			value = 0,
			text = "None",
		},
		{
			value = 0.3,
			text = "Slight",
		},
		{
			value = 0.6,
			text = "Normal",
		},
		{
			value = 1,
			text = "Pronounced",
		},
	},
}

setting{
	id = "hideitems",
	description = "Item info hidden from players by default",
	classes = {"dmonly"},
	default = false,
	section = "Game",
	storage = "game",
	editor = "check",
}

setting{
	id = "audiodev",
	description = "If we are in audio development",
	storage = "preference",
	editor = "check",
	default = false,
}

setting{
	id = "autoreloadlua",
	description = "Auto Reload Lua Changes",
	default = true,
	editor = "check",
}

setting{
	id = "discord",
	description = "Discord Integration",
	default = true,
	editor = "check",
	section = "General",
}

setting{
	id = "vision:eyesapart",
	description = "Distance eyes are apart",
	default = 0,
	editor = "slider",
	format = "F1",
	min = 0,
	max = 2,
}

setting{
	id = "imageeditor",
	description = "The program to use for editing images",
	default = "",
	storage = "preference",
}

setting{
	id = "fontsize",
	description = "Font Size",
	section = "General",
	default = 100,
	storage = "preference",
	editor = "dropdown",
		enum = {
		{
			value = 80,
			text = "80%",
		},
		{
			value = 90,
			text = "90%",
		},
		{
			value = 100,
			text = "100%",
		},
		{
			value = 110,
			text = "110%",
		},
		{
			value = 120,
			text = "120%",
		},
		{
			value = 130,
			text = "130%",
		},
		{
			value = 140,
			text = "140%",
		},
	},
}
