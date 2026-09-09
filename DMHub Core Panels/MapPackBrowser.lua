local mod = dmhub.GetModLoading()

--Map pack tiles: shared pieces for browsing the map pack index (synced and
--cached by the engine, see MapPackIndexLua / the mappacks global). The
--Create Map dialog hosts the grid; this file only owns the tile widgets and
--their styles. Map packs are never installed whole; see MAP_PACKS_PLAN.md at
--the repo root.

--every tile is the same fixed 3:4 cell so a page of the grid is always
--exactly two rows. The thumbnail is scaled to cover the cell (no
--letterboxing) and clipped, showing the map's right/bottom side; hovering
--pans it along the overflowing axis to reveal the rest.
local TILE_WIDTH = 150
local TILE_HEIGHT = 200
local TILE_MARGIN = 6

--hover pan: average speed in pixels per second of the swing between the
--two sides of the map, the shortest full swing period in seconds (so small
--overflows do not twitch), and how quickly the image eases home on mouse-out.
local PAN_SPEED = 20
local PAN_MIN_PERIOD = 6
local PAN_RETURN_RATE = 2

--exported so the Create Map details pane's zoom windows share the same pan
--feel as the grid tiles.
mod.shared.MapPackPanTuning = {
	speed = PAN_SPEED,
	minPeriod = PAN_MIN_PERIOD,
	returnRate = PAN_RETURN_RATE,
}

--the grid cell's footprint including margins, for laying out pages.
mod.shared.MapPackTileCellSize = function()
	return TILE_WIDTH + TILE_MARGIN * 2, TILE_HEIGHT + TILE_MARGIN * 2
end

--the smallest size with the map's aspect ratio that covers maxW x maxH.
mod.shared.MapPackCoverSize = function(entry, maxW, maxH)
	local w = tonumber(entry.tilesW) or 1
	local h = tonumber(entry.tilesH) or 1
	if w < 1 then w = 1 end
	if h < 1 then h = 1 end
	local scale = math.max(maxW / w, maxH / h)
	return math.max(maxW, math.ceil(w * scale)), math.max(maxH, math.ceil(h * scale))
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
			bgimage = "panels/square.png",
			bgcolor = "#00000066",
			cornerRadius = 6,
			width = TILE_WIDTH,
			height = TILE_HEIGHT,
			margin = TILE_MARGIN,
		},
		{
			selectors = {"mapPackTileImage"},
			bgcolor = "white",
			halign = "right",
			valign = "bottom",
		},
		{
			selectors = {"mapPackTileViewport"},
			width = "100%",
			height = "100%",
			bgimage = "panels/square.png",
			cornerRadius = 6,
		},
		{
			selectors = {"mapPackTileFrame"},
			width = "100%",
			height = "100%",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			cornerRadius = 6,
			borderWidth = 2,
			borderColor = "clear",
		},
		{
			selectors = {"mapPackTileFrame", "parent:hover"},
			borderColor = "@accent",
		},
		{
			selectors = {"mapPackTileFrame", "parent:selected"},
			borderColor = "@fg",
		},
		--the dark backing lives on a full-width band, not the label itself:
		--a percent-width label loses its hpad from the resolved width, so a
		--label-borne background stops 4px short of the tile's edges. The
		--band's bottom corners follow the tile frame's rounding.
		{
			selectors = {"mapPackTileLabelBand"},
			width = "100%",
			height = "auto",
			bgimage = "panels/square.png",
			bgcolor = "#000000aa",
			cornerRadius = {x1 = 0, y1 = 0, x2 = 6, y2 = 6},
		},
		{
			selectors = {"mapPackTileLabel"},
			width = "100%",
			height = "auto",
			halign = "center",
			valign = "bottom",
			color = "white",
			fontSize = 12,
			textAlignment = "center",
			hpad = 4,
			vpad = 2,
			borderBox = true,
			textWrap = true,
		},
		{
			selectors = {"mapPackTileEnhancements"},
			width = "auto",
			height = "auto",
			halign = "center",
			flow = "horizontal",
			bgimage = "panels/square.png",
			bgcolor = "#000000aa",
			cornerRadius = 4,
			hpad = 5,
			vpad = 2,
			bmargin = 2,
		},
		{
			selectors = {"mapPackTileEnhancementsLogo"},
			width = 12,
			height = 12,
			valign = "center",
			rmargin = 4,
			bgimage = "ui-icons/codex-logo.png",
			bgcolor = "white",
		},
		{
			selectors = {"mapPackTileEnhancementsText"},
			width = "auto",
			height = "auto",
			valign = "center",
			color = "white",
			fontSize = 10,
			bold = true,
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
			flow = "horizontal",
			halign = "left",
			hpad = 8,
			vpad = 3,
			margin = 3,
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
		},
		{
			selectors = {"mapPackChipText"},
			width = "auto",
			height = "auto",
			valign = "center",
			fontSize = 12,
		},
		{
			selectors = {"mapPackChipText", "parent:selected"},
			bold = true,
		},
		--an appearance the account cannot add reads dimmer than the rest.
		{
			selectors = {"mapPackChipText", "parent:locked"},
			opacity = 0.6,
		},
		{
			selectors = {"mapPackPatreonIcon"},
			width = 14,
			height = 14,
			valign = "center",
			rmargin = 4,
			bgcolor = "white",
		},
	})
end

--Patreon gating. A premium pack's index entries carry a tier: the minimum
--monthly pledge (cents) to the pack's creator organization that unlocks
--that appearance, 0 meaning free for everyone; the engine sets entry.owned
--live against the account's pledges. State is nil for a free appearance,
--"locked" when it needs a pledge the account lacks, "unlocked" when the
--pledge covers it.
mod.shared.MapPackPatreonState = function(entry)
	if (tonumber(entry.tier) or 0) <= 0 then
		return nil
	end
	if entry.owned then
		return "unlocked"
	end
	return "locked"
end

--the glyph for a gated appearance, nil when nothing applies. Always the
--solid filled logo: the duotone variant's translucent layer reads as a
--washed-out smudge at badge size, and locked vs unlocked is already told
--by the accompanying text and tooltips.
mod.shared.MapPackPatreonIcon = function(entry)
	if mod.shared.MapPackPatreonState(entry) == nil then
		return nil
	end
	return "phosphor/patreon-logo-fill.png"
end

--"$5/month" for a tier in cents.
mod.shared.MapPackTierText = function(cents)
	cents = tonumber(cents) or 0
	if cents % 100 == 0 then
		return string.format("$%d/month", math.floor(cents / 100))
	end
	return string.format("$%.2f/month", cents / 100)
end

--one line explaining an appearance's Patreon status to the user, or nil for
--a free one. creatorName is optional.
mod.shared.MapPackPatreonText = function(entry, creatorName)
	local state = mod.shared.MapPackPatreonState(entry)
	if state == nil then
		return nil
	end
	local who = cond(creatorName ~= nil and creatorName ~= "", creatorName, "the creator")
	if state == "unlocked" then
		return string.format("Included with your %s Patreon membership", who)
	end
	return string.format("Requires a %s Patreon membership with %s", mod.shared.MapPackTierText(entry.tier), who)
end

--an appearance chip: the variant's name with the Patreon glyph in front when
--the appearance is gated. options: entry, text, selected, press(element).
--The chip carries data.entry like the grid tiles do.
mod.shared.CreateMapPackChip = function(options)
	local entry = options.entry
	local state = mod.shared.MapPackPatreonState(entry)
	local children = {}
	local icon = mod.shared.MapPackPatreonIcon(entry)
	if icon ~= nil then
		children[#children + 1] = gui.Panel{
			classes = {"mapPackPatreonIcon"},
			bgimage = icon,
			interactable = false,
		}
	end
	children[#children + 1] = gui.Label{
		classes = {"mapPackChipText"},
		text = options.text,
		interactable = false,
	}
	local tooltipText = mod.shared.MapPackPatreonText(entry, options.creatorName)
	local hoverFn = nil
	if tooltipText ~= nil then
		hoverFn = gui.Tooltip(tooltipText)
	end
	return gui.Panel{
		classes = {"mapPackChip", cond(options.selected, "selected"), cond(state == "locked", "locked")},
		data = { entry = entry },
		press = options.press,
		hover = hoverFn,
		children = children,
	}
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

--callback({displayName = string, logo = nil|string, url = nil|string,
--campaignUrl = nil|string, campaignName = nil|string}); fires synchronously
--when the creator is already cached. campaignUrl is the org's linked
--Patreon campaign page (where a pledge unlocks tiered appearances), url its
--website.
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
			local campaign = rawget(info, "patreonCampaign")
			finish({
				displayName = info.displayName or id,
				logo = rawget(info, "logo"),
				url = rawget(info, "url"),
				campaignUrl = campaign ~= nil and rawget(campaign, "url") or nil,
				campaignName = campaign ~= nil and rawget(campaign, "name") or nil,
			})
		end,
		failure = function(msg)
			finish({ displayName = id, logo = nil })
		end,
	}
end

--which maps of a pack have shared markup (Codex Enhancements), fetched once
--per pack so the grid can badge tiles. callback(set) with set[mapid] = true;
--fires synchronously when the pack is already cached. A failed fetch is
--treated as an empty set and not retried this session.
local g_markupMaps = {}
local g_markupMapsWaiting = {}

mod.shared.GetMapPackMarkupMaps = function(pack, callback)
	if pack == nil or pack == "" then
		callback({})
		return
	end
	local cached = g_markupMaps[pack]
	if cached ~= nil then
		callback(cached)
		return
	end
	if g_markupMapsWaiting[pack] ~= nil then
		table.insert(g_markupMapsWaiting[pack], callback)
		return
	end
	g_markupMapsWaiting[pack] = { callback }

	local function finish(set)
		g_markupMaps[pack] = set
		local queue = g_markupMapsWaiting[pack]
		g_markupMapsWaiting[pack] = nil
		for _, fn in ipairs(queue or {}) do
			fn(set)
		end
	end

	mappacks.ListMarkupMaps{
		pack = pack,
		success = function(mapids)
			local set = {}
			for _, mapid in ipairs(mapids) do
				set[mapid] = true
			end
			finish(set)
		end,
		error = function(msg)
			finish({})
		end,
	}
end

--a "Codex Enhancements" badge: the Codex logo beside the text, on a dark
--backing so it reads over the map.
mod.shared.CodexEnhancementsBadge = function(args)
	local result = {
		classes = {"mapPackTileEnhancements"},
		interactable = false,
		gui.Panel{
			classes = {"mapPackTileEnhancementsLogo"},
			interactable = false,
		},
		gui.Label{
			classes = {"mapPackTileEnhancementsText"},
			text = "Codex Enhancements",
			interactable = false,
		},
	}
	for k, v in pairs(args or {}) do
		result[k] = v
	end
	return gui.Panel(result)
end

--one grid tile for an index entry (a map appearance variant). onPress is
--called with the entry when the tile is clicked. The creator's logo sits in
--the top-right corner once its record has loaded, with the Patreon glyph
--beside it when the appearance is gated (filled = the account has access,
--duotone = it does not).
mod.shared.CreateMapPackTile = function(entry, onPress)
	local logoImage = gui.Panel{
		classes = {"hidden"},
		width = "auto",
		height = "auto",
		maxWidth = 56,
		maxHeight = 22,
		autosizeimage = true,
		bgcolor = "white",
		valign = "center",
		interactable = false,
	}
	local patreonIcon = mod.shared.MapPackPatreonIcon(entry)
	local patreonImage = gui.Panel{
		classes = {cond(patreonIcon == nil, "hidden")},
		width = 18,
		height = 18,
		lmargin = 4,
		valign = "center",
		bgimage = patreonIcon,
		bgcolor = "white",
		interactable = false,
	}
	--dark backing so a white-on-transparent logo reads over bright maps.
	local logoPanel = gui.Panel{
		classes = {cond(patreonIcon == nil, "hidden")},
		floating = true,
		halign = "right",
		valign = "top",
		x = -4,
		y = 4,
		width = "auto",
		height = "auto",
		flow = "horizontal",
		pad = 3,
		bgimage = "panels/square.png",
		bgcolor = "#000000aa",
		cornerRadius = 4,
		interactable = false,
		logoImage,
		patreonImage,
	}

	--the thumbnail covers the cell keeping the map's aspect ratio, anchored
	--right/bottom so that side shows. It lives inside a clipping viewport so
	--the overflow never escapes the cell, and the border is a separate
	--overlay drawn on top of it (see frame below).
	local imageW, imageH = mod.shared.MapPackCoverSize(entry, TILE_WIDTH, TILE_HEIGHT)
	local overflowX = imageW - TILE_WIDTH
	local overflowY = imageH - TILE_HEIGHT
	local thumb = gui.Panel{
		classes = {"mapPackTileImage"},
		width = imageW,
		height = imageH,
		bgimage = mod.shared.MapPackThumbImage(entry),
		interactable = false,
	}
	local viewport = gui.Panel{
		classes = {"mapPackTileViewport"},
		clip = true,
		clipHidden = true,
		interactable = false,
		thumb,
	}

	--hover pan: the thumbnail drifts along whichever axis overflows, easing
	--to a stop at each side of the map and easing back the other way while
	--hovered (a cosine swing), then glides back to the right/bottom side
	--after the mouse leaves. Offsets are positive (rightwards/downwards)
	--because the image is anchored right/bottom.
	local panRange = math.max(overflowX, overflowY)
	local panPeriod = math.max(PAN_MIN_PERIOD, 2 * panRange / PAN_SPEED)
	local panOffset = 0
	local panStart = nil   --time the current swing began (nil = not hovered)
	local lastThink = nil

	local ApplyPan = function()
		if overflowX > 0 then
			thumb.x = panOffset
		elseif overflowY > 0 then
			thumb.y = panOffset
		end
	end

	local enhancementsBadge = mod.shared.CodexEnhancementsBadge{ classes = {"mapPackTileEnhancements", "hidden"} }

	local tile = gui.Panel{
		classes = {"mapPackTile"},
		data = { entry = entry },
		press = function(element)
			onPress(element.data.entry)
		end,
		hover = function(element)
			if panRange <= 0 then
				return
			end
			--resume the swing from wherever the glide-back left us so the
			--image never jumps: invert offset = range*(1-cos(phase))/2.
			local phase = math.acos(1 - 2 * math.min(1, panOffset / panRange))
			panStart = dmhub.Time() - phase * panPeriod / (2 * math.pi)
			lastThink = dmhub.Time()
			element.thinkTime = 0.01
		end,
		dehover = function(element)
			panStart = nil
		end,
		think = function(element)
			local now = dmhub.Time()
			if panStart ~= nil then
				local phase = (now - panStart) * 2 * math.pi / panPeriod
				panOffset = panRange * (1 - math.cos(phase)) / 2
			else
				--ease back to the resting side, then stop thinking.
				local dt = now - (lastThink or now)
				panOffset = panOffset * math.exp(-dt * PAN_RETURN_RATE)
				if panOffset < 0.5 then
					panOffset = 0
					element.thinkTime = nil
				end
			end
			lastThink = now
			ApplyPan()
		end,
		viewport,
		--the name bar, with the Codex Enhancements badge stacked above it
		--once the pack's shared-markup listing says this map has one.
		gui.Panel{
			width = "100%",
			height = "auto",
			valign = "bottom",
			flow = "vertical",
			interactable = false,
			enhancementsBadge,
			gui.Panel{
				classes = {"mapPackTileLabelBand"},
				interactable = false,
				gui.Label{
					classes = {"mapPackTileLabel"},
					text = entry.name,
					interactable = false,
				},
			},
		},
		logoPanel,
		--border overlay: drawn last so it sits above the thumbnail.
		gui.Panel{
			classes = {"mapPackTileFrame"},
			interactable = false,
		},
	}

	mod.shared.GetMapPackMarkupMaps(entry.pack, function(set)
		if enhancementsBadge.valid and set[entry.id] then
			enhancementsBadge:SetClass("hidden", false)
		end
	end)

	mod.shared.GetMapPackCreator(entry, function(info)
		if not logoPanel.valid then
			return
		end
		if info.logo ~= nil and info.logo ~= "" then
			logoImage.bgimage = info.logo
			logoImage:SetClass("hidden", false)
			logoPanel:SetClass("hidden", false)
		end
	end)

	return tile
end
