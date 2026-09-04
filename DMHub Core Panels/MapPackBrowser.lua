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
		{
			selectors = {"mapPackDetailTitle"},
			fontSize = 22,
			bold = true,
			width = "100%",
			height = "auto",
			textWrap = true,
			vmargin = 6,
		},
		{
			selectors = {"mapPackDetailText"},
			fontSize = 14,
			width = "100%",
			height = "auto",
			textWrap = true,
			vmargin = 4,
		},
		{
			selectors = {"mapPackChip"},
			bgimage = "panels/square.png",
			bgcolor = "@bg",
			cornerRadius = 10,
			width = "auto",
			height = "auto",
			hpad = 8,
			vpad = 3,
			margin = 3,
			fontSize = 12,
			borderWidth = 1,
			borderColor = "@fg",
		},
		{
			selectors = {"mapPackChip", "hover"},
			borderColor = "@accent",
		},
		{
			selectors = {"mapPackChip", "selected"},
			borderWidth = 2,
			borderColor = "@accent",
			bold = true,
		},
	})
end

--Creator branding: the pack id is "<author>-<module>", and the author id is a
--/ModuleAuthor record (a creator organization, or a plain author id) whose
--displayName and logo we show. Looked up once per author and cached for the
--session; callers waiting on the same lookup are queued.
local g_creators = {}
local g_creatorWaiting = {}

mod.shared.MapPackCreatorId = function(entry)
	local pack = entry.pack or ""
	local dash = string.find(pack, "-", 1, true)
	if dash == nil then
		return pack
	end
	return string.sub(pack, 1, dash - 1)
end

--callback({displayName = string, logo = nil|string}); fires synchronously
--when the creator is already cached.
mod.shared.GetMapPackCreator = function(entry, callback)
	local id = mod.shared.MapPackCreatorId(entry)
	if id == "" then
		callback({ displayName = "", logo = nil })
		return
	end
	local cached = g_creators[id]
	if cached ~= nil then
		callback(cached)
		return
	end
	if g_creatorWaiting[id] ~= nil then
		table.insert(g_creatorWaiting[id], callback)
		return
	end
	g_creatorWaiting[id] = { callback }

	local function finish(info)
		g_creators[id] = info
		local queue = g_creatorWaiting[id]
		g_creatorWaiting[id] = nil
		for _, fn in ipairs(queue or {}) do
			fn(info)
		end
	end

	module.GetOrganizationInfo{
		orgid = id,
		success = function(info)
			finish({ displayName = info.displayName or id, logo = rawget(info, "logo") })
		end,
		failure = function(msg)
			finish({ displayName = id, logo = nil })
		end,
	}
end

--one grid tile for an index entry (a map appearance variant). onPress is
--called with the entry when the tile is clicked. The creator's logo sits in
--the top-right corner once its record has loaded.
mod.shared.CreateMapPackTile = function(entry, onPress)
	local logoImage = gui.Panel{
		width = "auto",
		height = "auto",
		maxWidth = 56,
		maxHeight = 22,
		autosizeimage = true,
		bgcolor = "white",
		interactable = false,
	}
	--dark backing so a white-on-transparent logo reads over bright maps.
	local logoPanel = gui.Panel{
		classes = {"hidden"},
		floating = true,
		halign = "right",
		valign = "top",
		x = -4,
		y = 4,
		width = "auto",
		height = "auto",
		pad = 3,
		bgimage = "panels/square.png",
		bgcolor = "#000000aa",
		cornerRadius = 4,
		interactable = false,
		logoImage,
	}

	local tile = gui.Panel{
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
		logoPanel,
	}

	mod.shared.GetMapPackCreator(entry, function(info)
		if not logoPanel.valid then
			return
		end
		if info.logo ~= nil and info.logo ~= "" then
			logoImage.bgimage = info.logo
			logoPanel:SetClass("hidden", false)
		end
	end)

	return tile
end
