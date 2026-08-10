local mod = dmhub.GetModLoading()

local CreateMapDialog

--Returns a set { [mapid] = true } of the maps the local player is allowed to
--browse: maps they have a controllable token on, plus maps flagged
--"Player Viewable". For the DM this is unused (they see every map).
local GetPlayerAccessibleMaps

DockablePanel.Register{
	name = "Maps",
    menu = "game",
	icon = "phosphor/map-trifold.png",
	--summoned from the Game menu it opens as a floating window over the
	--map (like the launchable dialog it used to be), not docked. It can
	--still be dragged into a dock.
	preferFloating = true,
	--the map list scrolls itself (it is a tree with its own scroll
	--region), so no wrapper scroll here.
	vscroll = false,
	minHeight = 200,
	maxHeight = 900,
	filtered = function()
		if dmhub.isDM then
			return false
		end

		--players only get the Maps panel if there is at least one map they
		--can browse.
		return next(GetPlayerAccessibleMaps()) == nil
	end,
	content = function()
		return CreateMapDialog()
	end,
	hasNewContent = function()
		return module.HasNovelContent("map")
	end,
	newContentCount = function()
		return gui.NovelContentCount("map")
	end,
}

local g_mapDialog = nil

local DragNode = function(element, target)
	if target == nil then
		return
	end
	local a = element.data.data
	local b = target.data.data
	if a == nil or b == nil or (not a.valid) or (not b.valid) then
		return
	end
	
	if a.id == b.id then
		return
	end

	--check to make sure we're not dragging onto a child or sub-child.
	local count = 0
	local parentFolder = b.parentFolder
	while parentFolder ~= nil and count < 20 do
		if parentFolder.id == a.id then
			return
		end
		
		parentFolder = parentFolder.parentFolder
		count = count+1
	end

	if target.data.isfolder then
		local ord = 1
		for _,item in ipairs(target.data.data.childFolders) do
			if item.ord > ord then
				ord = item.ord
			end
		end

		for _,item in ipairs(target.data.data.childMaps) do
			if item.ord > ord then
				ord = item.ord
			end
		end

		a:MarkUndo()
		a.ord = ord + 1
		a.parentFolder = target.data.data
		a:Upload("Re-order maps")
		g_mapDialog:FireEventTree("refreshMaps")
		return
	end

	local dataItems = {}
	local items = target.parent.children
	for _,item in ipairs(items) do
		if item == target then
			dataItems[#dataItems+1] = a
		elseif not item:HasClass('dragPanel') and item ~= element then
			dataItems[#dataItems+1] = item.data.data
		end
	end

	for ord,item in ipairs(dataItems) do
		item:MarkUndo()
		item.parentFolder = b.parentFolder
		item.ord = ord
		item:Upload("Re-order maps")
	end

	g_mapDialog:FireEventTree("refreshMaps")
end

--Per-map settings dialog, mirroring the Floors panel's per-floor settings
--dialog: the row's gear (and the right-click menu) opens it. Holds the
--rename field and the loading-screen cover art picker that used to live in
--the row's click-to-focus edit strip.
local function ShowMapSettings(map)
	local dialogPanel = gui.Panel{
		classes = {"framedPanel"},
		width = 480,
		height = "auto",
		styles = ThemeEngine.GetStyles(),

		gui.Panel{
			width = "100%-48",
			height = "auto",
			halign = "center",
			valign = "top",
			flow = "vertical",
			vmargin = 24,

			gui.Label{
				classes = {"modalTitle"},
				text = "Map Settings",
			},

			gui.Panel{
				classes = {"formStackedRow"},
				vmargin = 8,
				gui.Label{
					classes = {"formStacked"},
					text = "Name:",
				},
				gui.Input{
					classes = {"formStacked"},
					text = map.description,
					change = function(element)
						if trim(element.text) == "" then
							if map.valid then
								element.text = map.description
							end
							return
						end
						if map.valid then
							map:MarkUndo()
							map.description = element.text
							map:Upload("Renamed map")
							if g_mapDialog ~= nil and g_mapDialog.valid then
								g_mapDialog:FireEventTree("refreshMaps")
							end
						end
					end,
				},
			},

			gui.Panel{
				classes = {"formStackedRow"},
				vmargin = 8,
				gui.Label{
					classes = {"formStacked"},
					text = "Cover Art:",
					linger = gui.Tooltip("Shown as the loading screen when entering this map."),
				},
				gui.IconEditor{
					library = "coverart",
					classes = {"image"},
					width = "auto",
					height = "auto",
					hideIcon = true,
					allowNone = true,
					aspect = 1080/1920,
					noneImage = game.coverart,
					hideButton = true,
					maxWidth = 128,
					maxHeight = 128,
					autosizeimage = true,
					halign = "left",
					value = map.loadingScreenImage,
					change = function(element)
						map:MarkUndo()
						map.loadingScreenImage = element.value
						map:Upload("Set map loading screen")
					end,

					gui.Panel{
						classes = {"coverArtRibbon"},
						interactable = false,
						width = 128,
						height = 20,
						halign = "center",
						valign = "center",
						bgcolor = "black",
						opacity = 0.8,
						bgimage = "panels/square.png",
						styles = {
							{
								selectors = {"coverArtRibbon"},
								hidden = 1,
							},
							{
								selectors = {"coverArtRibbon", "parent:hover"},
								hidden = 0,
							}
						},

						gui.Label{
							interactable = false,
							fontSize = 12,
							width = "auto",
							height = "auto",
							color = "white",
							bold = true,
							halign = "center",
							valign = "center",
							text = "Choose Cover Art",
						}
					}
				},
			},

			gui.Panel{
				width = "100%",
				height = 40,
				valign = "bottom",
				vmargin = 12,

				gui.Button{
					classes = {"sizeM"},
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

	gui.ShowModal(dialogPanel)
end


--Local rule set for the maps list's custom selectors, matching the Floors &
--Layers row grammar: quiet transparent rows that surface on hover, an
--accent-edged current row (never a fill louder than the identity it marks),
--faint seam hairlines, and section-header folders. @tokens are resolved by
--MergeStyles at call time; the dialogs reassign on OnThemeChanged so a
--scheme switch recolors live.
local function BuildMapListStyles()
	return {
		{
			selectors = {"mapRow"},
			flow = "horizontal",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			width = "100%",
			height = 34,
			halign = "left",
			valign = "top",
			hpad = 12,
			borderBox = true,
		},
		{
			selectors = {"mapRow", "hover"},
			bgcolor = "@bgAlt",
			transitionTime = 0.1,
		},
		{
			selectors = {"mapRow", "selected"},
			bgcolor = "@bgAlt",
			border = {x1 = 3, x2 = 0, y1 = 0, y2 = 0},
			borderColor = "@accent",
			priority = 5,
		},
		{
			selectors = {"mapName"},
			fontSize = 14,
			color = "@fg",
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "center",
		},
		{
			selectors = {"mapName", "parent:selected"},
			color = "@fgStrong",
			bold = true,
		},
		{
			selectors = {"mapName", "deleting"},
			color = "@danger",
		},
		--Row separator, same recipe as the floors list: @border taken down
		--to a hint of structure rather than a table grid line.
		{
			selectors = {"mapSeamLine"},
			bgcolor = "@border",
			opacity = 0.2,
			width = "100%",
			height = 1,
		},
		--Folder section headers: the GROUND LEVEL grammar. Small bold muted
		--label after the caret, hairline underline, map count at the right.
		{
			selectors = {"mapFolderHeader"},
			flow = "horizontal",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			width = "100%",
			height = 30,
			tmargin = 8,
			hpad = 12,
			borderBox = true,
			halign = "left",
			valign = "top",
		},
		{
			selectors = {"mapFolderLabel"},
			fontSize = 13,
			bold = true,
			color = "@fg",
			width = "auto",
			height = "auto",
			halign = "left",
			valign = "center",
			lmargin = 6,
		},
		{
			selectors = {"mapFolderLabel", "parent:hover"},
			color = "@fgStrong",
			transitionTime = 0.1,
		},
		{
			selectors = {"mapFolderCount"},
			fontSize = 11,
			color = "@fgMuted",
			width = "auto",
			height = "auto",
			halign = "right",
			valign = "center",
		},
		--The header's underline: brighter than row seams so groups read a
		--step above the rows they contain.
		{
			selectors = {"mapFolderRule"},
			bgcolor = "@border",
			opacity = 0.35,
			width = "100%",
			height = 1,
		},
		{
			selectors = {"mapTokenOverflow"},
			fontSize = 11,
			bold = true,
			color = "@fgMuted",
			width = "auto",
			height = "auto",
			valign = "center",
			lmargin = 4,
		},
		--The search field: DefaultStyles ships searchInput borderless (its
		--comment says surfaces wanting a frame add one locally); use the
		--title bar's thin @border treatment, with quieter type than the
		--16px bold default so the field does not outshout the rows.
		{
			selectors = {"searchInput"},
			fontSize = 13,
			bold = false,
			borderWidth = 1,
			borderColor = "@border",
			priority = 10,
		},
		{
			selectors = {"searchInput", "focus"},
			borderColor = "@fgStrong",
			priority = 10,
		},
		--The create-map button takes the Phosphor plus instead of the shared
		--ui-icons/Plus.png, matching the caret/gear masks used in this panel
		--(and the same swap the floors list makes). Scoped here so the
		--app-wide addButton icon is untouched.
		{
			selectors = {"panel", "buttonIcon", "parent:addButton"},
			bgimage = "phosphor/plus-bold.png",
			priority = 10,
		},
		--A gear on every row at full strength reads as a button column;
		--recede at rest, brighten when the pointer reaches the gear. The
		--gear graphic is the button's buttonIcon child, so the rules target
		--that; "parent:" matches only the direct parent, so scoping comes
		--from these styles living on the Maps dialog root rather than from
		--a mapRow selector. priority outranks the theme's generic
		--buttonIcon color rules.
		{
			selectors = {"buttonIcon", "parent:settingsButton"},
			bgcolor = "@fgMuted",
			opacity = 0.5,
			priority = 10,
		},
		{
			selectors = {"buttonIcon", "parent:settingsButton", "parent:hover"},
			bgcolor = "@fg",
			opacity = 1,
			priority = 15,
			transitionTime = 0.1,
		},
	}
end

local CreateMapSeamLine = function()
	return gui.Panel{
		classes = {"mapSeamLine"},
		interactable = false,
		bgimage = "panels/square.png",
		--While a search filter hides arbitrary rows, the seams between them
		--would survive as stray hairlines; hide them all instead.
		search = function(element, str)
			element:SetClass("collapsed", str ~= "")
		end,
	}
end

--Builds the row of party-token portraits shown next to a map. Shared by the
--DM map node and the player map node. Capped at a single quiet run -- up to
--five 20px portraits plus a "+N" chip for the rest -- so a busy map never
--grows its row (the old 32px wrapping cluster reached four rows deep).
--onClick fires when a portrait is clicked (the node passes a handler that
--activates the row).
local g_maxMapPortraits = 5

local CreateMapTokenContainer = function(map, onClick)
	local tokenPanels = {}
	local overflowLabel = nil

	return gui.Panel{
		idprefix = "map-token-container",
		flow = "horizontal",
		halign = "right",
		valign = "center",
		width = "auto",
		height = "auto",
		--clear the row's floating settings gear.
		rmargin = 26,
		refreshMaps = function(element)
			local newTokenPanels = {}
			local children = {}

			local tokens = g_mapDialog.data.tokensPerMap[map.id] or {}

			for i,tok in ipairs(tokens) do
				if i > g_maxMapPortraits then
					break
				end

				local charid = tok.charid
				local tokenPanel = tokenPanels[charid] or gui.CreateTokenImage(tok,{
					idprefix = "map-token-image",
					width = 20,
					height = 20,
					halign = "left",
					interactable = true,
					click = function(element)
						onClick()
					end,
					linger = function(element)
						local tok = dmhub.GetCharacterById(charid)
						if tok == nil or (not tok.valid) then
							return
						end

						local partyid = tok.partyid
						local party = GetParty(partyid)
						if party ~= nil then
							gui.Tooltip(string.format("%s -- %s", tok.description, party.name))(element)
						end
					end,

					gui.Panel{
						idprefix = "map-token-player",
						classes = {cond(not tok.playerControlledAndPrimary, "hidden")},
						width = 9,
						height = 9,
						halign = "right",
						valign = "bottom",
						floating = true,
						bgimage = "icons/icon_simpleshape/icon_simpleshape_31.png",
						bgcolor = "#ffffaaff",
					},
				})

				newTokenPanels[charid] = tokenPanel
				children[#children+1] = tokenPanel
			end

			if #tokens > g_maxMapPortraits then
				overflowLabel = overflowLabel or gui.Label{
					idprefix = "map-token-overflow",
					classes = {"mapTokenOverflow"},
					hover = gui.Tooltip("Click the map to see everyone on it."),
				}
				overflowLabel.text = string.format("+%d", #tokens - g_maxMapPortraits)
				children[#children+1] = overflowLabel
			end

			tokenPanels = newTokenPanels
			element.children = children
		end,
	}
end


local CreateMapNode = function(map)
	local resultPanel

	local newMapMarker = nil
	local novelMaps = module.GetNovelContent("map")
	if novelMaps ~= nil and novelMaps[map.id] then
		newMapMarker = gui.NewContentAlert{
			info = novelMaps[map.id]
		}
	end

	local nameLabel = gui.Label{
		idprefix = "map-label",
		classes = {"mapName"},
		text = map.description,
		characterLimit = 32,

		--Rename in place with a double-click, like the floor rows. The
		--settings dialog's Name field is the discoverable path.
		editableOnDoubleClick = true,
		change = function(element)
			if element.text == "" then
				if map.valid then
					element.text = map.description
				end

				return
			end
			if map.valid then
				map:MarkUndo()
				map.description = element.text
				map:Upload("Renamed map")
			end
		end,
		refreshMaps = function(element)
			if map.valid then
				element.text = map.description
			end
		end,

		newMapMarker,
	}

	local tokenContainer = CreateMapTokenContainer(map, function()
		resultPanel:FireEvent("click")
	end)

	resultPanel = gui.Panel{
		idprefix = "map-panel",
		classes = {"mapRow"},
		draggable = true,

		refreshMaps = function(element)
			element:SetClass("selected", map.valid and map.id == game.currentMapId)
		end,

		canDragOnto = function(element, target)
            return target ~= nil and target:HasClass("mapDragTarget")
		end,
		drag = DragNode,

		search = function(element, text)
			local mapName = string.lower(map.description)
			local searchText = string.lower(text)

			if string.find(mapName, searchText) ~= nil then
				--matches the search
				element:SetClass("collapsed", false)
			else
				--doesn't match the search
				element:SetClass("collapsed", true)
			end
		end,

		rightClick = function(element)
			local entries = {}

			entries[#entries+1] = {
				text = "Map Settings...",
				click = function()
					element.popup = nil
					ShowMapSettings(map)
				end,
			}

            if module.IsMapAvailableInModule(map.id) then
                entries[#entries+1] = {
                    text = "Reset Map",
                    click = function()
                        element.popup = nil
                        module.ReinstallMap(map.id, function(success)
                            print("ReinstallMap::", success)
                        end)
                    end,
                }
            end

			entries[#entries+1] = {
					text = "Duplicate Map",
					click = function()
						element.popup = nil

						if map.id ~= game.currentMapId then
							gui.ModalMessage{
								title = "Enter Map",
								message = "You must enter the map before duplicating it.",
							}
							return
						end
						
						local operation = dmhub.CreateNetworkOperation()
						operation.description = "Duplicate Map"
						operation.status = "Duplicating..."
						operation.progress = 0.0
						operation:Update()

						game.DuplicateMap(map.id, function()
							operation.progress = 1
							operation:Update()
						end)
					end,
				}

			entries[#entries+1] =
			{
				text = "Delete Map",
				click = function()
					element.popup = nil

					if map.id == game.currentMapId then
						gui.ModalMessage{
							title = "Cannot Delete Current Map",
							message = "You cannot delete the map you are currently in. Switch to a different map first.",
						}
					else
						nameLabel:SetClass("deleting", true)
						map:Delete()
					end

				end,
			}


			element.popup = gui.ContextMenu{
				entries = entries,
			}
		end,

		--Click = enter the map, matching the floor rows' one-click grammar.
		--The old click-to-focus edit strip is gone; its rename and cover
		--art live in the settings dialog (gear or right-click).
		click = function(element)
			if element.popup ~= nil then
				element.popup = nil
				return
			end

			if (not map.valid) or map.id == game.currentMapId then
				return
			end

			if newMapMarker ~= nil then
				newMapMarker:DestroySelf()
				newMapMarker = nil
				module.RemoveNovelContent("map", map.id)
			end

			map:Travel()
		end,

		data = {
			data = map
		},

		nameLabel,

		tokenContainer,

		--Settings floats at the row's right edge, out of the reading path:
		--the same corner-gear pattern as the floor rows.
		gui.Button{
			classes = {"settingsButton"},
			floating = true,
			halign = "right",
			valign = "center",
			width = 16,
			height = 16,
			hmargin = 6,
			click = function(element)
				ShowMapSettings(map)
			end,
		},
	}

	return resultPanel
end

local CreateFolderPanel
local CreateFolderChildPanel

local CreateDragTargetPanel = function(folder)
	return gui.Panel{
		idprefix = "map-drag-target",
		classes = {"dragPanel", "mapDragTarget"},
		dragTarget = true,
		styles = ThemeEngine.MergeTokens({
			{
				selectors = {"dragPanel"},
				bgimage = true,
				bgcolor = "clear",
				width = "100%",
				height = 2,
				vmargin = 2,
			},
			{
				selectors = {"dragPanel", "drag-target-hover"},
				height = 10,
				bgcolor = "@accent",
			},
		}),
		search = function(element, str)
			element:SetClass("collapsed", str ~= "")
		end,
		data  = {
			data = nil,
		},
	}
end

CreateFolderChildPanel = function(folder)
	local childNodes = {}
	return gui.Panel{
		idprefix = "map-folder-child",
		width = "100%",
		height = "auto",
		flow = "vertical",
		valign = "top",
		data = {
			numChildren = 0,
		},
		create = function(element)
			element:FireEvent("refreshMaps")
		end,

		refreshMaps = function(element)
			local newChildNodes = {}
			local children = {}
			for _,map in ipairs(folder.childMaps) do
				local newChild = childNodes[map.mapid] or CreateMapNode(map)
				children[#children+1] = newChild
				newChildNodes[map.mapid] = newChild
			end
			for _,f in ipairs(folder.childFolders) do
				local newChild = childNodes[f.folderid] or CreateFolderPanel(f)
				children[#children+1] = newChild
				newChildNodes[f.folderid] = newChild
			end
			element.data.numChildren = #children
			table.sort(children, function(pa,pb)
				local a = pa.data.data
				local b = pb.data.data
				if (not a.valid) and (not a.valid) then
					return false
				end

				if not a.valid then
					return true
				end

				if not b.valid then
					return false
				end

				if a.ord ~= b.ord then
					return a.ord < b.ord
				end

				return a.description < b.description

			end)

			local childrenWithDrag = {
			}

			--Interleave drag targets, plus a faint seam hairline between
			--adjacent map rows (not around folder headers -- those carry
			--their own underline).
			local prevWasMap = false
			for i,child in ipairs(children) do
				local isFolder = child.data.isfolder == true
				if prevWasMap and not isFolder then
					local seamKey = string.format("seam-%d", i)
					local seam = childNodes[seamKey] or CreateMapSeamLine()
					newChildNodes[seamKey] = seam
					childrenWithDrag[#childrenWithDrag+1] = seam
				end
				prevWasMap = not isFolder

				local key = string.format("drag-%d", i)
				local dragPanel = childNodes[key] or CreateDragTargetPanel(folder)
				dragPanel.data.data = child.data.data
				newChildNodes[key] = dragPanel
				childrenWithDrag[#childrenWithDrag+1] = dragPanel
				childrenWithDrag[#childrenWithDrag+1] = child
			end

			if #children > 0 then
				local key = string.format("drag-%d", #children+1)
				local dragPanel = childNodes[key] or CreateDragTargetPanel(folder)
				dragPanel.data.data = children[#children].data.data
				dragPanel.data.after = true
				newChildNodes[key] = dragPanel
				childrenWithDrag[#childrenWithDrag+1] = dragPanel
			end

			element.children = childrenWithDrag
			childNodes = newChildNodes
		end,
	}
end

CreateFolderPanel = function(folder)
	local childPanel = CreateFolderChildPanel(folder)

	local prefKey = string.format("mapfolder:%s:%s", dmhub.gameid, folder.id)

	local folderClosed = dmhub.GetPref(prefKey)

	if folderClosed then
		childPanel:SetClass("collapsed", true)
	end


	--A Phosphor mask rather than the default panels/triangle.png, for the
	--same reason as the floors list: the 64x64 bitmap reads fuzzy when
	--downscaled to header size.
	local triangle = gui.ExpandoArrow{
		idprefix = "map-triangle",
		bgimage = "phosphor/caret-down-fill.png",
		classes = cond(folderClosed, nil, {"expanded"}),

		click = function(element)
			local nowExpanded = not element:HasClass("expanded")
			element:SetClass("expanded", nowExpanded)
			childPanel:SetClass("collapsed", not nowExpanded)
			dmhub.SetPref(prefKey, not nowExpanded)
		end,

		search = function(element, str)
			childPanel:SetClass("collapsed", str == "" and (not element:HasClass("expanded")))
		end,
	}

	local headerPanel = gui.Panel{
		idprefix = "map-header",
		classes = {"mapFolderHeader", "mapDragTarget"},
		dragTarget = true,

		data = {
			data = folder,
			isfolder = true,
		},

		search = function(element, str)
			element:SetClass("collapsed", str ~= "")
		end,

		triangle,
		gui.Label{
			idprefix = "folder-label",
			classes = {"mapFolderLabel"},
			text = cond(trim(folder.description) == "", "(Unnamed)", folder.description),
			characterLimit = 32,

			editable = true,


			rightClick = function(element)
				dmhub.Debug("RIGHT CLICK")
				if childPanel.data.numChildren ~= 0 then
					--can't delete non-empty folders.
					return
				end

				local entries = {
					{
						text = "Delete Folder",
						click = function()
							folder:Delete()
							element.popup = nil
						end,
					},
				}

				element.popup = gui.ContextMenu{
					entries = entries,
				}
			end,



			change = function(element)
				if trim(element.text) == "" then
					if folder.valid then
						element.text = folder.description
					end

					return
				end
				if folder.valid then
					folder:MarkUndo()
					folder.description = element.text
					folder:Upload("Renamed folder")
				end
			end,
			refreshMaps = function(element)
				if folder.valid then
					element.text = cond(trim(folder.description) == "", "(Unnamed)", folder.description)
				end
			end,
		},

		--Glanceable size of the group: how many maps sit directly inside.
		gui.Label{
			idprefix = "folder-count",
			classes = {"mapFolderCount"},
			text = tostring(#folder.childMaps),
			refreshMaps = function(element)
				if folder.valid then
					element.text = tostring(#folder.childMaps)
				end
			end,
		},
	}

	--The header's underline, running the full row width. A separate in-flow
	--hairline rather than a rule inside the header: the label is
	--variable-width and this layout has no fill-remaining primitive.
	local headerRule = gui.Panel{
		idprefix = "map-header-rule",
		classes = {"mapFolderRule"},
		interactable = false,
		bgimage = "panels/square.png",
		search = function(element, str)
			element:SetClass("collapsed", str ~= "")
		end,
	}

	return gui.Panel{
		idprefix = "map-folder-body",
		flow = "vertical",
		width = "100%",
		height = "auto",
		draggable = true,
		canDragOnto = function(element, target)
            return target ~= nil and target:HasClass("mapDragTarget")
		end,
		drag = DragNode,

		data = {
			data = folder,
			isfolder = true,
		},
		headerPanel,
		headerRule,
		gui.Panel{
			idprefix = "map-folder-body-main",
			width = "100%-16",
			halign = "right",
			height = "auto",
			childPanel,
		}
	}
end

GetPlayerAccessibleMaps = function()
	local result = {}

	--maps explicitly flagged "Player Viewable" by the DM.
	for _,m in ipairs(game.maps) do
		if m.valid and m.playerViewable then
			result[m.id] = true
		end
	end

	--maps the local player has a controllable token on.
	for _,partyid in ipairs(GetAllParties()) do
		for _,charid in ipairs(dmhub.GetCharacterIdsInParty(partyid)) do
			local token = dmhub.GetCharacterById(charid)
			if token ~= nil and token.canControl and token.mapid ~= nil then
				result[token.mapid] = true
			end
		end
	end

	return result
end

--Read-only map row shown to players. Unlike CreateMapNode it has no rename,
--drag, delete/duplicate context menu or cover-art editor -- clicking the row
--simply travels to the map.
local CreatePlayerMapNode = function(map)
	local resultPanel

	local nameLabel = gui.Label{
		idprefix = "player-map-label",
		classes = {"mapName"},
		text = map.description,
		characterLimit = 32,
		editable = false,
		refreshMaps = function(element)
			if map.valid then
				element.text = map.description
			end
		end,
	}

	local tokenContainer = CreateMapTokenContainer(map, function()
		resultPanel:FireEvent("click")
	end)

	resultPanel = gui.Panel{
		idprefix = "player-map-panel",
		classes = {"mapRow"},

		refreshMaps = function(element)
			element:SetClass("selected", map.valid and map.id == game.currentMapId)
		end,

		search = function(element, text)
			local mapName = string.lower(map.description)
			local searchText = string.lower(text)
			element:SetClass("collapsed", string.find(mapName, searchText) == nil)
		end,

		click = function(element)
			if map.valid and map.id ~= game.currentMapId then
				map:Travel()
			end
		end,

		data = {
			data = map,
		},

		nameLabel,
		tokenContainer,
	}

	return resultPanel
end

--The player-facing Maps panel: a flat, read-only, searchable list of the
--maps the player is allowed to browse (see GetPlayerAccessibleMaps).
local CreatePlayerMapDialog = function()
	local mapNodes = {}

	local listPanel = gui.Panel{
		idprefix = "player-map-list",
		--rows run flush to the panel edges (they carry their own 12px inset).
		width = "100%",
		halign = "center",
		valign = "top",
		height = "auto",
		flow = "vertical",

		refreshMaps = function(element)
			local accessible = GetPlayerAccessibleMaps()

			local maps = {}
			for _,m in ipairs(game.maps) do
				if m.valid and accessible[m.id] then
					maps[#maps+1] = m
				end
			end

			table.sort(maps, function(a,b)
				if a.ord ~= b.ord then
					return a.ord < b.ord
				end
				return a.description < b.description
			end)

			local newNodes = {}
			local children = {}
			for i,m in ipairs(maps) do
				local node = mapNodes[m.id] or CreatePlayerMapNode(m)
				newNodes[m.id] = node
				if i > 1 then
					local seamKey = string.format("seam-%d", i)
					local seam = mapNodes[seamKey] or CreateMapSeamLine()
					newNodes[seamKey] = seam
					children[#children+1] = seam
				end
				children[#children+1] = node
			end

			mapNodes = newNodes
			element.children = children

			--tokensPerMap is populated by the dialog's own refreshMaps
			--handler (fired first, top-down), so refresh every node now
			--that the list is in place.
			for _,node in ipairs(children) do
				node:FireEventTree("refreshMaps")
			end
		end,
	}

	local treeScrollPanel = gui.Panel{
		idprefix = "player-map-scroll-panel",
		width = "100%",
		--fill whatever height the host gives us, minus the search input row
		--(24 tall + 8/8 vmargins).
		height = "100%-48",
		halign = "center",
		valign = "top",
		vscroll = true,
		listPanel,
	}

	local filterInput = gui.SearchInput{
		width = "100%-24",
		height = 24,
		--gui.SearchInput ships hpad = 24 (room for the magnifier) without
		--borderBox, so the padding ADDS to the declared width and the field
		--overflows the panel's right edge by that much. borderBox keeps the
		--declared width inclusive of it.
		borderBox = true,
		halign = "center",
		valign = "top",
		vmargin = 8,
		placeholderText = "Search Maps...",
		edit = function(element)
			treeScrollPanel:FireEventTree("search", element.text)
		end,
	}

	local resultPanel
	resultPanel = gui.Panel{
		id = "map-dialog",

		halign = "left",
		valign = "top",
		--fill the hosting window/dock slot so the panel stays inside it and
		--stretches when the window is resized. No horizontal inset: rows own
		--their edge-to-edge fills, like the floors list.
		width = "100%",
		height = "100%",
		vpad = 12,
		borderBox = true,
		flow = "vertical",

		data = {
			tokensPerMap = {},
		},

		create = function(element)
			g_mapDialog = element
			element:FireEventTree("refreshMaps")
		end,

		destroy = function(element)
			if g_mapDialog == element then
				g_mapDialog = nil
			end
		end,

		monitorGame = {"/mapManifests", "/characters"},
		refreshGame = function(element)
			element:FireEventTree("refreshMaps")
		end,

		refreshMaps = function(element)
			element.data.tokensPerMap = {}
			for _,partyid in ipairs(GetAllParties()) do
				for _,charid in ipairs(dmhub.GetCharacterIdsInParty(partyid)) do
					local token = dmhub.GetCharacterById(charid)
					if token ~= nil and token.mapid then
						local mapTokens = element.data.tokensPerMap[token.mapid] or {}
						element.data.tokensPerMap[token.mapid] = mapTokens
						mapTokens[#mapTokens+1] = token
					end
				end
			end
		end,

		styles = ThemeEngine.MergeStyles(BuildMapListStyles()),

		filterInput,
		treeScrollPanel,
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if resultPanel ~= nil and resultPanel.valid then
			resultPanel.styles = ThemeEngine.MergeStyles(BuildMapListStyles())
		end
	end)

	return resultPanel
end

CreateMapDialog = function()
	if not dmhub.isDM then
		return CreatePlayerMapDialog()
	end

	local treeInnerPanel = gui.Panel{
		idprefix = "map-tree-inner-panel",
		--rows run flush to the panel edges (they carry their own 12px inset).
		width = "100%",
		height = "auto",
		halign = "left",
		valign = "top",
		flow = "vertical",
		CreateFolderChildPanel(game.rootMapFolder),

	}

	local treeScrollPanel
	treeScrollPanel = gui.Panel{
		idprefix = "map-tree-scroll-panel",
		width = "100%",
		--fill the host height minus the search input row (24 + 8/8 vmargins)
		--and the floating create-folder/create-map buttons at the bottom
		--(36 + margins).
		height = "100%-88",
		halign = "center",
		valign = "top",
		vscroll = true,
		treeInnerPanel,
	}

	local filterInput = gui.SearchInput{
		width = "100%-24",
		height = 24,
		--gui.SearchInput ships hpad = 24 (room for the magnifier) without
		--borderBox, so the padding ADDS to the declared width and the field
		--overflows the panel's right edge by that much. borderBox keeps the
		--declared width inclusive of it.
		borderBox = true,
		halign = "center",
		valign = "top",
		vmargin = 8,
		placeholderText = "Search Maps...",
		edit = function(element)
			printf("SEARCH: search for %s", element.text)
			treeScrollPanel:FireEventTree("search", element.text)
		end,
	}



	local resultPanel
	resultPanel = gui.Panel{
		id = "map-dialog",

		halign = "left",
		valign = "top",
		--fill the hosting window/dock slot so the panel stays inside it and
		--stretches when the window is resized. No horizontal inset: rows own
		--their edge-to-edge fills, like the floors list.
		width = "100%",
		height = "100%",
		vpad = 12,
		borderBox = true,
		flow = "vertical",

		data = {
			tokensPerMap = {},
		},

		create = function(element)
            module.SyncModuleSnapshots()
			g_mapDialog = element
		end,

		destroy = function(element)
			if g_mapDialog == element then
				g_mapDialog = nil
			end
		end,

		monitorGame = {"/mapManifests", "/mapFolders"},
		refreshGame = function(element)
			element:FireEventTree("refreshMaps")
		end,

		refreshMaps = function(element)
			element.data.tokensPerMap = {}
			local allParties = GetAllParties()
			for _,k in ipairs(allParties) do
				local partyMembers = dmhub.GetCharacterIdsInParty(k)
				for _,charid in ipairs(partyMembers) do
					local token = dmhub.GetCharacterById(charid)
					if token.mapid then
						local mapTokens = element.data.tokensPerMap[token.mapid] or {}

						element.data.tokensPerMap[token.mapid] = mapTokens

						mapTokens[#mapTokens+1] = token
					end
				end
				
			end
			
		end,

		styles = ThemeEngine.MergeStyles(BuildMapListStyles()),

		filterInput,
		treeScrollPanel,

		gui.Panel{
			id = "map-dialog-buttons",
			flow = "horizontal",
			margin = 6,
			floating = true,
			halign = 'right',
			valign = 'bottom',
			width = "auto",
			height = "auto",
			gui.Button{
				id = "map-dialog-button-open-folder",
				width = 26,
				height = 26,
				valign = "center",
				hmargin = 4,
				icon = "phosphor/folder-plus-duotone.png",
				click = function(element)
					game.CreateMapFolder()
				end,
				hover = gui.Tooltip("Create a Folder"),
			},
			gui.Button{
				id = "map-dialog-button-create-map",
				classes = {"addButton"},
				width = 26,
				height = 26,
				valign = "center",
				hmargin = 2,
				click = function(element)
					mod.shared.CompleteTutorial("Create a Map")
                    mod.shared.ShowCreateMapDialog()
					--game.CreateMap()
				end,
				hover = gui.Tooltip("Create a Map"),
			},
		},
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if resultPanel ~= nil and resultPanel.valid then
			resultPanel.styles = ThemeEngine.MergeStyles(BuildMapListStyles())
		end
	end)

	return resultPanel
end