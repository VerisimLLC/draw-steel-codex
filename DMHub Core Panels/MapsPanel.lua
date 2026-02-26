local mod = dmhub.GetModLoading()

local CreateMapDialog

LaunchablePanel.Register{
	name = "Maps",
    menu = "game",
	icon = "panels/hud/56_map.png",
	halign = "left",
	valign = "top",
	vmargin = 1,
	hmargin = 4,
	draggable = false,
	filtered = function()
		return not dmhub.isDM
	end,
	content = function()
		return CreateMapDialog()
	end,
	hasNewContent = function()
		return module.HasNovelContent("map")
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


local CreateMapNode = function(map)
	local resultPanel
	local tokenPanels = {}

	local newMapMarker = nil
	local novelMaps = module.GetNovelContent("map")
	if novelMaps ~= nil and novelMaps[map.id] then
		newMapMarker = gui.NewContentAlert{
			info = novelMaps[map.id]
		}
	end

	local nameLabel = gui.Label{
		idprefix = "map-label",
		classes = {"map"},
		text = map.description,
		characterLimit = 32,
        minWidth = 240,

		editable = false,
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
				element:SetClass("selected", map.id == game.currentMapId)
			end
		end,

		newMapMarker,
	}

	local tokenContainer = gui.Panel{
		idprefix = "map-token-container",
		flow = "horizontal",
		halign = "right",
		valign = "center",
		width = "auto",
		maxWidth = 32*6,
		height = "auto",
		wrap = true,
		refreshMaps = function(element)
			local newTokenPanels = {}
			local children = {}

			local tokens = g_mapDialog.data.tokensPerMap[map.id] or {}

			for i,tok in ipairs(tokens) do
				local charid = tok.charid
				local tokenPanel = tokenPanels[charid] or gui.CreateTokenImage(tok,{
					idprefix = "map-token-image",
					width = 32,
					height = 32,
					halign = "left",
					interactable = true,
					click = function(element)
						resultPanel:FireEvent("click")
					end,
					linger = function(element)
						dmhub.Debug(string.format("LINGER:: TOKEN: %s", charid))
						local tok = dmhub.GetCharacterById(charid)
						if tok == nil or (not tok.valid) then
							return
						end

						local partyid = tok.partyid
						local party = GetParty(partyid)
						if party ~= nil then
						dmhub.Debug(string.format("LINGER:: TOOLTIP: %s", charid))
							gui.Tooltip(string.format("%s -- %s", tok.description, party.name))(element)
						end
					end,

					gui.Panel{
						idprefix = "map-token-player",
						classes = {cond(not tok.playerControlledAndPrimary, "hidden")},
						width = 12,
						height = 12,
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

			tokenPanels = newTokenPanels
			element.children = children
		end,
	}

	local editArea = gui.Panel{
		classes = {"collapsed-anim"},
		flow = "horizontal",
		width = "100%",
		height = "auto",
		vmargin = 4,

		gui.IconEditor{
			library = "coverart",
			bgcolor = "white",
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

		gui.Button{
			width = 100,
			height = 36,
			text = "Enter Map",
			fontSize = 16,
			halign = "right",
			click = function(element)
				if newMapMarker ~= nil then
					newMapMarker:DestroySelf()
					module.RemoveNovelContent("map", map.id)
				end

				map:Travel()
			end,
		},


	}

	resultPanel = gui.Panel{
		idprefix = "map-panel",
		bgimage = "panels/square.png",
		classes = {"row", "map"},
		flow = "vertical",
		draggable = true,
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

		click = function(element)
			if element.popup ~= nil then
				element.popup = nil
				return
			end

			if g_mapDialog.data.focusMap ~= resultPanel then
				if g_mapDialog.data.focusMap ~= nil then
					g_mapDialog.data.focusMap:FireEvent("defocusMap")
				end

				element:FireEvent("focusMap")
				g_mapDialog.data.focusMap = resultPanel
			end
		end,

		focusMap = function(element)
			nameLabel.editable = true
			editArea:SetClass("collapsed-anim", false)
		end,

		defocusMap = function(element)
			nameLabel.editable = false
			editArea:SetClass("collapsed-anim", true)
		end,


		data = {
			data = map
		},

		gui.Panel{
			flow = "horizontal",
			width = "100%",
			height = "auto",
			valign = "center",

			nameLabel,

			tokenContainer,

		},

		editArea,
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

			for i,child in ipairs(children) do
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

local triangleStyles = {
	gui.Style{
		classes = {"triangle"},
		bgimage = "panels/triangle.png",
		bgcolor = "white",
		hmargin = 4,
		halign = "left",
		valign = "center",
		height = 12,
		width = 12,
		rotate = 90,
	},
	gui.Style{
		classes = {"triangle", "expanded"},
		rotate = 0,
		transitionTime = 0.2,
	},
	gui.Style{
		classes = {"triangle", "hover"},
		bgcolor = "yellow",
	},
	gui.Style{
		classes = {"triangle", "press"},
		bgcolor = "gray",
	},
}

CreateFolderPanel = function(folder)
	local childPanel = CreateFolderChildPanel(folder)

	local prefKey = string.format("mapfolder:%s:%s", dmhub.gameid, folder.id)

	local folderClosed = dmhub.GetPref(prefKey)

	if folderClosed then
		childPanel:SetClass("collapsed", true)
	end


	local triangle = gui.Panel{
		idprefix = "map-triangle",
		classes = {"triangle", cond(folderClosed, nil, "expanded")},
		styles = triangleStyles,

		create = function(element)
			printf("FOLDER:: %s / %s", dmhub.gameid, folder.id)
		end,

		click = function(element)
			element:SetClass("expanded", not element:HasClass("expanded"))
			childPanel:SetClass("collapsed", not element:HasClass("expanded"))
			dmhub.SetPref(prefKey, not element:HasClass("expanded"))
		end,

		search = function(element, str)
			childPanel:SetClass("collapsed", str == "" and (not element:HasClass("expanded")))
		end,
	}

	local headerPanel = gui.Panel{
		idprefix = "map-header",
		classes = {"row", "mapDragTarget"},
		bgimage = "panels/square.png",
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
			text = cond(trim(folder.description) == "", "(Unnamed)", folder.description),
			characterLimit = 32,
            minWidth = 240,

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
		gui.Panel{
			idprefix = "map-folder-body-main",
			width = "100%-16",
			halign = "right",
			height = "auto",
			childPanel,
		}
	}
end

CreateMapDialog = function()
	local treeInnerPanel = gui.Panel{
		idprefix = "map-tree-inner-panel",
		width = "96%",
		height = "auto",
		halign = "left",
		valign = "top",
		flow = "vertical",
		CreateFolderChildPanel(game.rootMapFolder),

	}

	local treeScrollPanel
	treeScrollPanel = gui.Panel{
		idprefix = "map-tree-scroll-panel",
		width = "96%",
		height = "85%",
		halign = "center",
		valign = "top",
		vscroll = true,
		treeInnerPanel,
	}

	local filterInput = gui.Input{
		width = "80%",
		height = 24,
		fontSize = 18,
		halign = "left",
		valign = "top",
		vmargin = 8,
		placeholderText = "Search Maps...",
		edit = function(element)
			printf("SEARCH: search for %s", element.text)
			treeScrollPanel:FireEventTree("search", element.text)
		end,
	}



	return gui.Panel{
		id = "map-dialog",

		halign = "left",
		valign = "top",
		width = 400,
		height = 700,
		flow = "vertical",
		
		data = {
			tokensPerMap = {},
			focusMap = nil,
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

		draggable = true,
		drag = function(element)
			element.x = element.xdrag
			element.y = element.ydrag
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

		styles = {
			{
				classes = {"row"},
				height = 24,
				width = "100%",
				halign = "left",
				valign = "top",
				flow = "horizontal",
				bgcolor = "#00000044",
			},
			{
				classes = {"row", "map"},
				height = "auto",
				minHeight = 24,
			},
			{
				classes = {"row", "hover"},
				transitionTime = 0.1,
				bgcolor = "#88000077",
			},
			{
				classes = {"row", "dragging"},
				bgcolor = "#88000077",
			},
			{
				classes = {"label"},
				halign = "left",
				width = "auto",
				height = "auto",
				fontSize = 16,
				margin = 4,
				color = "#aaaaaa",
			},
			{
				classes = {"label", "selected"},
				color = "#ffffff",
			},
			{
				classes = {"label", "deleting"},
				color = "#ff0000",
			},
			{
				classes = {"dragPanel"},
				width = "100%",
				height = 2,
				bgcolor = "#ffffff00",
				bgimage = "panels/square.png",
				vmargin = 2,
			},
			{
				classes = {"drag-target"},
				bgcolor = "#ffffff55",
			},
			{
				classes = {"drag-target-hover"},
				bgcolor = "#ffffff88",
				bgimage = "panels/square.png",
			}

		},

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
			gui.AddButton{
				id = "map-dialog-button-open-folder",
				hmargin = 4,
				bgimage = "game-icons/open-folder.png",
				click = function(element)
					game.CreateMapFolder()
				end,
				hover = gui.Tooltip("Create a Folder"),
			},
			gui.AddButton{
				id = "map-dialog-button-create-map",
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
end