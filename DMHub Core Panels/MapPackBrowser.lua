local mod = dmhub.GetModLoading()

--Map pack browser: search every published map pack's index (synced and
--cached by the engine, see MapPackIndexLua) and add a single map to the
--current game with the chosen appearance variant armed. Map packs are never
--installed whole; see MAP_PACKS_PLAN.md at the repo root.

local TILE_WIDTH = 150
local TILE_MIN_HEIGHT = 90
local TILE_MAX_HEIGHT = 260
local MAX_RESULTS = 400

local function TileHeightFor(entry)
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
local function ThumbImage(entry)
	if entry.thumb ~= nil and entry.thumb ~= "" then
		return "md5:" .. entry.thumb
	end
	return "panels/square.png"
end

local function BuildStyles()
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
			selectors = {"mapPackDetailTitle"},
			fontSize = 22,
			bold = true,
			width = "100%",
			height = "auto",
			textWrap = true,
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
			bgcolor = "@accent",
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

mod.shared.ShowMapPackBrowser = function()
	local m_search = ""
	local m_entries = {}
	local m_selected = nil
	local m_adding = false
	local m_dialog = nil

	local statusLabel = gui.Label{
		classes = {"mapPackStatus"},
		text = "Syncing map packs...",
	}

	local gridPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "horizontal",
		wrap = true,
		valign = "top",
		halign = "left",
	}

	local gridScroll = gui.Panel{
		width = 900,
		height = "100%",
		vscroll = true,
		valign = "top",
		gridPanel,
	}

	--details pane -------------------------------------------------------
	local detailImage = gui.Panel{
		width = 360,
		height = 360,
		halign = "center",
		bgimage = "panels/square.png",
		bgcolor = "white",
		cornerRadius = 6,
	}

	local detailTitle = gui.Label{ classes = {"mapPackDetailTitle"}, text = "" }
	local detailInfo = gui.Label{ classes = {"mapPackDetailText"}, text = "" }
	local detailKeywords = gui.Label{ classes = {"mapPackDetailText"}, text = "" }

	local variantsPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "horizontal",
		wrap = true,
		halign = "left",
	}

	local addButton
	local RefreshDetails
	local SelectEntry

	local function ShowError(title, message)
		gui.ModalMessage{
			owner = m_dialog,
			title = title,
			message = message,
		}
	end

	local function AddSelectedToGame()
		if m_selected == nil or m_adding then
			return
		end
		local entry = m_selected
		m_adding = true
		addButton:SetClass("hidden", true)
		statusLabel.text = string.format("Adding %s...", entry.name)
		mappacks.AddMapToGame{
			pack = entry.pack,
			mapid = entry.id,
			variantIndex = entry.variantIndex,
			success = function(mapid)
				m_adding = false
				if m_dialog == nil or not m_dialog.valid then
					return
				end
				gui.CloseModal()
				dmhub.Coroutine(function()
					for i = 1, 200 do
						if game.GetMap(mapid) ~= nil then
							break
						end
						coroutine.yield(0.05)
					end
					local map = game.GetMap(mapid)
					if map ~= nil then
						map:Travel()
					end
				end)
			end,
			error = function(msg)
				m_adding = false
				if m_dialog == nil or not m_dialog.valid then
					return
				end
				addButton:SetClass("hidden", false)
				statusLabel.text = ""
				ShowError("Could not add map", msg)
			end,
		}
	end

	addButton = gui.Button{
		classes = {"sizeL", "hidden"},
		halign = "center",
		vmargin = 12,
		text = "Add to Game",
		click = function(element)
			AddSelectedToGame()
		end,
	}

	local detailPanel = gui.Panel{
		width = 400,
		height = "100%",
		flow = "vertical",
		valign = "top",
		hmargin = 12,
		detailImage,
		detailTitle,
		detailInfo,
		gui.Label{
			classes = {"mapPackDetailText"},
			bold = true,
			text = "Appearances",
		},
		variantsPanel,
		detailKeywords,
		addButton,
	}

	--all index entries for the same map as the selection, in variant order.
	local function SiblingVariants(entry)
		local result = {}
		for _, other in ipairs(m_entries) do
			if other.pack == entry.pack and other.id == entry.id then
				result[#result + 1] = other
			end
		end
		table.sort(result, function(a, b) return a.variantIndex < b.variantIndex end)
		return result
	end

	RefreshDetails = function()
		local entry = m_selected
		if entry == nil then
			detailImage.bgimage = "panels/square.png"
			detailTitle.text = "Select a map"
			detailInfo.text = ""
			detailKeywords.text = ""
			variantsPanel.children = {}
			addButton:SetClass("hidden", true)
			return
		end

		detailImage.bgimage = ThumbImage(entry)
		detailImage.height = TileHeightFor(entry) * 360 / TILE_WIDTH
		if detailImage.height > 400 then
			detailImage.height = 400
		end
		detailTitle.text = entry.name
		detailInfo.text = string.format("%s\n%d x %d tiles\nPack: %s", entry.description ~= "" and entry.description or entry.sceneName, entry.tilesW, entry.tilesH, entry.pack)
		detailKeywords.text = "Keywords: " .. table.concat(entry.keywords, ", ")

		local chips = {}
		for _, sibling in ipairs(SiblingVariants(entry)) do
			chips[#chips + 1] = gui.Label{
				classes = {"mapPackChip", cond(sibling == entry, "selected")},
				text = sibling.variant ~= "" and sibling.variant or "Default",
				data = { entry = sibling },
				press = function(element)
					SelectEntry(element.data.entry)
				end,
			}
		end
		variantsPanel.children = chips
		addButton:SetClass("hidden", m_adding)
	end

	SelectEntry = function(entry)
		m_selected = entry
		for _, tile in ipairs(gridPanel.children) do
			tile:SetClass("selected", tile.data.entry == entry)
		end
		RefreshDetails()
	end

	local function CreateTile(entry)
		return gui.Panel{
			classes = {"mapPackTile"},
			height = TileHeightFor(entry),
			bgimage = ThumbImage(entry),
			data = { entry = entry },
			press = function(element)
				SelectEntry(element.data.entry)
			end,
			hover = gui.Tooltip(entry.name),
			gui.Label{
				classes = {"mapPackTileLabel"},
				text = entry.name,
				interactable = false,
			},
		}
	end

	local function Refresh()
		if m_dialog == nil or not m_dialog.valid then
			return
		end
		if not mappacks.synced then
			return
		end

		m_entries = mappacks.Search{
			text = m_search,
			maxResults = MAX_RESULTS,
		}

		local tiles = {}
		local stillSelected = nil
		for _, entry in ipairs(m_entries) do
			tiles[#tiles + 1] = CreateTile(entry)
			if m_selected ~= nil and entry.pack == m_selected.pack and entry.id == m_selected.id and entry.variantIndex == m_selected.variantIndex then
				stillSelected = entry
			end
		end
		gridPanel.children = tiles

		if mappacks.count == 0 then
			statusLabel.text = "No map packs are published yet."
		elseif #m_entries == 0 then
			statusLabel.text = "No maps match your search."
		elseif #m_entries >= MAX_RESULTS then
			statusLabel.text = string.format("Showing the first %d matches; refine your search.", MAX_RESULTS)
		else
			statusLabel.text = string.format("%d of %d maps", #m_entries, mappacks.count)
		end

		m_selected = stillSelected
		if m_selected ~= nil then
			SelectEntry(m_selected)
		else
			RefreshDetails()
		end
	end

	local searchInput = gui.Input{
		classes = {"form"},
		width = 400,
		placeholderText = "Search maps...",
		editlag = 0.25,
		edit = function(element)
			m_search = element.text
			Refresh()
		end,
		change = function(element)
			m_search = element.text
			Refresh()
		end,
	}

	m_dialog = gui.Panel{
		classes = {"framedPanel"},
		width = 1400,
		height = 940,
		styles = ThemeEngine.MergeStyles(BuildStyles()),

		gui.Panel{
			width = "100%-24",
			height = "100%-48",
			halign = "center",
			valign = "center",
			flow = "vertical",

			gui.Label{
				classes = {"modalTitle"},
				text = "Map Packs",
			},

			gui.Panel{
				width = "100%",
				height = 40,
				flow = "horizontal",
				vmargin = 8,
				searchInput,
				statusLabel,
			},

			gui.Panel{
				width = "100%",
				height = "100%-140",
				flow = "horizontal",
				valign = "top",
				gridScroll,
				detailPanel,
			},

			gui.Panel{
				width = "100%",
				height = 48,
				valign = "bottom",
				gui.Button{
					classes = {"sizeL"},
					halign = "right",
					text = "Close",
					escapeActivates = true,
					escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
					click = function(element)
						gui.CloseModal()
					end,
				},
			},
		},
	}

	gui.ShowModal(m_dialog)

	if mappacks.synced then
		Refresh()
	end

	--always re-sync on open so newly published packs show up; the engine
	--only downloads the packs whose index blob changed.
	mappacks.Sync{
		success = function()
			Refresh()
		end,
		error = function(msg)
			Refresh()
			if m_dialog ~= nil and m_dialog.valid then
				statusLabel.text = msg
			end
		end,
	}
end
