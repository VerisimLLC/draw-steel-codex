local mod = dmhub.GetModLoading()

--Map pack tiles: shared pieces for browsing the map pack index (synced and
--cached by the engine, see MapPackIndexLua / the mappacks global). The
--Create Map dialog hosts the grid; this file only owns the tile widgets and
--their styles. Map packs are never installed whole; see MAP_PACKS_PLAN.md at
--the repo root.

local TILE_WIDTH = 150
local TILE_MIN_HEIGHT = 90
local TILE_MAX_HEIGHT = 260

mod.shared.MapPackTileHeight = function(entry)
	local w = tonumber(entry.tilesW) or 0
	local h = tonumber(entry.tilesH) or 0
	if w <= 0 or h <= 0 then
		return TILE_WIDTH
	end
	local result = TILE_WIDTH * h / w
	if result < TILE_MIN_HEIGHT then
		result = TILE_MIN_HEIGHT
	elseif result > TILE_MAX_HEIGHT then
		result = TILE_MAX_HEIGHT
	end
	return math.floor(result)
end

--raw content-addressed image ids display through the md5: prefix.
mod.shared.MapPackThumbImage = function(entry)
	if entry.thumb ~= nil and entry.thumb ~= "" then
		return "md5:" .. entry.thumb
	end
	return "panels/square.png"
end

mod.shared.MapPackTileStyles = function()
	return ThemeEngine.MergeTokens({
		{
			selectors = {"mapPackTile"},
			bgimage = true,
			bgcolor = "white",
			cornerRadius = 6,
			width = TILE_WIDTH,
			height = TILE_WIDTH,
			margin = 6,
			borderWidth = 2,
			borderColor = "clear",
		},
		{
			selectors = {"mapPackTile", "hover"},
			borderColor = "@accent",
		},
		{
			selectors = {"mapPackTile", "selected"},
			borderColor = "@fg",
		},
		{
			selectors = {"mapPackTileLabel"},
			width = "100%",
			height = "auto",
			halign = "center",
			valign = "bottom",
			bgimage = "panels/square.png",
			bgcolor = "#000000aa",
			color = "white",
			fontSize = 12,
			textAlignment = "center",
			hpad = 4,
			vpad = 2,
			borderBox = true,
			textWrap = true,
		},
		{
			selectors = {"mapPackStatus"},
			fontSize = 14,
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "center",
			hmargin = 12,
		},
	})
end

--one grid tile for an index entry (a map appearance variant). onPress is
--called with the entry when the tile is clicked.
mod.shared.CreateMapPackTile = function(entry, onPress)
	return gui.Panel{
		classes = {"mapPackTile"},
		height = mod.shared.MapPackTileHeight(entry),
		bgimage = mod.shared.MapPackThumbImage(entry),
		data = { entry = entry },
		press = function(element)
			onPress(element.data.entry)
		end,
		hover = gui.Tooltip(entry.name),
		gui.Label{
			classes = {"mapPackTileLabel"},
			text = entry.name,
			interactable = false,
		},
	}
end
