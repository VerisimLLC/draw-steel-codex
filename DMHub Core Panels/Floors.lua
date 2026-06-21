local mod = dmhub.GetModLoading()

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

local CreateLayersPanel

DockablePanel.Register{
	name = "Floors & Layers",
	icon = "icons/standard/Icon_App_FloorsLayers.png",
	minHeight = 100,
	vscroll = false,
	dmonly = true,
	content = function()
		track("panel_open", {
			panel = "Floors & Layers",
			dailyLimit = 30,
		})
		return CreateLayersPanel()
	end,
}

--Find the map LevelObject (an object carrying a "Map" component) associated with a floor or layer, if
--any. Searches the floor's own objects first, then -- for a top-level floor -- every layer beneath it.
local function FindMapObjectForFloor(floor)
	for _, obj in pairs(floor.objects) do
		if obj:GetComponent("Map") ~= nil then
			return obj
		end
	end

	if floor.parentFloor == nil then
		local layers = game.currentMap:GetLayersForFloor(floor.floorid)
		if layers ~= nil then
			for _, layer in ipairs(layers) do
				for _, obj in pairs(layer.objects) do
					if obj:GetComponent("Map") ~= nil then
						return obj
					end
				end
			end
		end
	end

	return nil
end

--Custom themed styling for the map-appearance gallery tiles. Hover/selected states live in the style
--cascade (not inline) so they can flip on mouse-over and recolor with the active scheme. Colors use
--@tokens so the highlight tracks the user's color scheme.
local appearanceTileStyles = {
	--Image thumbnail tile: themed border, accent border when selected. Brighten-on-hover comes from the
	--composed "hoverable" class.
	{
		selectors = {"mapAppearanceTile"},
		bgimage = true,
		border = 2,
		borderColor = "@border",
		transitionTime = 0.1,
	},
	{
		selectors = {"mapAppearanceTile", "selected"},
		border = 3,
		borderColor = "@accent",
		priority = 10,
	},
	--The "add appearance" tile: themed surface; the accent border on hover (plus "hoverable" brighten)
	--signals that it is responsive.
	{
		selectors = {"mapAppearanceAdd"},
		bgimage = true,
		border = 2,
		borderColor = "@border",
		bgcolor = "@bgAlt",
		transitionTime = 0.1,
		priority = 1,
	},
	{
		selectors = {"mapAppearanceAdd", "hover"},
		border = 3,
		borderColor = "@accent",
		priority = 5,
	},
}

local function ShowFloorSettings(floor)

	--Sub-layers (parentFloor ~= nil) are layers within a floor rather than floors in their
	--own right. The roof/canopy/vision options only take effect on top-level floors, so for a
	--sub-layer we collapse that whole section and just expose the name.
	local isLayer = floor.parentFloor ~= nil

	--Canopy-only options (vision multiplier + cutaway controls). Shown when the layer type is
	--"Canopy"; a plain roof has none of these -- it renders transparent where the player has
	--vision and opaque elsewhere. Canopy adds the vision multiplier and cutaway tuning.
	local canopyOptions = gui.Panel{
		classes = cond(floor.canopy, nil, "collapsed"),
		width = "100%",
		height = "auto",
		flow = "vertical",

		gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Vision Multiplier:",
				linger = gui.Tooltip("The vision multiplier allows players to see further on the canopy layer than they can on other layers."),
			},
			gui.Slider{
				classes = {"formStacked"},
				style = { height = 22, width = 220, valign = "center" },
				sliderWidth = 150,
				minValue = 0.1,
				maxValue = 8,
				labelWidth = 60,
				value = floor.visionMultiplier,
				labelFormat = "rawpercent",
				events = {
					change = function(element)
						floor.visionMultiplierNoUpload = element.value
					end,
					confirm = function(element)
						floor.visionMultiplier = element.value
					end,
				},
			},
		},

		gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Cutaway Radius:",
				linger = gui.Tooltip("The cutaway radius (in tiles) around any token with vision. Pixels of the canopy within this distance of a token are cut away to reveal the layer below. Set negative to disable the cutaway entirely (the canopy will always be fully shown). For tree foliage, try a small value like 6-10."),
			},
			gui.Slider{
				classes = {"formStacked"},
				style = { height = 22, width = 220, valign = "center" },
				sliderWidth = 150,
				minValue = -1,
				maxValue = 40,
				labelWidth = 60,
				labelFormat = "%d",
				value = floor.roofVisionExclusion,
				events = {
					change = function(element)
						floor.roofVisionExclusionNoUpload = element.value
					end,
					confirm = function(element)
						floor.roofVisionExclusion = element.value
					end,
				},
			},
		},

		gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Cutaway Fade:",
				linger = gui.Tooltip("Width (in tiles) of the smooth fade band at the outer edge of the cutaway. Larger values give a softer transition back to the full canopy; a fade of 0 produces a hard edge."),
			},
			gui.Slider{
				classes = {"formStacked"},
				style = { height = 22, width = 220, valign = "center" },
				sliderWidth = 150,
				labelFormat = "%.1f",
				minValue = 0,
				maxValue = 2,
				labelWidth = 60,
				value = floor.roofVisionExclusionFade,
				events = {
					change = function(element)
						floor.roofVisionExclusionFadeNoUpload = element.value
					end,
					confirm = function(element)
						floor.roofVisionExclusionFade = element.value
					end,
				},
			},
		},

		gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Minimum Opacity:",
				linger = gui.Tooltip("The minimum opacity that the canopy layer will have within the cutaway zone. 0 means fully transparent at the token; raise it to keep some of the canopy visible even directly above a token."),
			},
			gui.Slider{
				classes = {"formStacked"},
				style = { height = 22, width = 220, valign = "center" },
				sliderWidth = 150,
				labelFormat = "rawpercent",
				minValue = 0.0,
				maxValue = 1.0,
				labelWidth = 60,
				value = floor.roofMinimumOpacity,
				events = {
					change = function(element)
						floor.roofMinimumOpacityNoUpload = element.value
					end,
					confirm = function(element)
						floor.roofMinimumOpacity = element.value
					end,
				},
			},
		},
	}

	--Roof options. Shown for both "Roof" and "Canopy"; canopy stacks its extra controls on top.
	local roofOptions = gui.Panel{
		classes = cond(floor.roof, nil, "collapsed"),
		width = "100%",
		height = "auto",
		flow = "vertical",

		gui.Check{
			text = "Hide roof when players are inside",
			value = not floor.roofShowWhenInside,
			lmargin = 12,
			vmargin = 4,
			events = {
				change = function(element)
					floor.roofShowWhenInside = not element.value
				end,
				linger = gui.Tooltip("This layer will be hidden when players are inside."),
			},
		},

		canopyOptions,
	}

	local function CurrentLayerType()
		if floor.canopy then
			return "canopy"
		elseif floor.roof then
			return "roof"
		else
			return "floor"
		end
	end

	--Layer type selector + its dependent roof/canopy options. Collapsed entirely for sub-layers.
	local typeSection = gui.Panel{
		classes = cond(isLayer, "collapsed"),
		width = "100%",
		height = "auto",
		flow = "vertical",

		gui.Panel{
			classes = {"formStackedRow"},
			gui.Label{
				classes = {"formStacked"},
				text = "Layer Type:",
				linger = gui.Tooltip("Floor: a normal map level. Roof: hidden for players beneath it except where they can't see. Canopy: a roof that cuts away around tokens (tree foliage etc)."),
			},
			gui.Dropdown{
				classes = {"formStacked"},
				options = {
					{id = "floor", text = "Floor"},
					{id = "roof", text = "Roof"},
					{id = "canopy", text = "Canopy"},
				},
				idChosen = CurrentLayerType(),
				change = function(element)
					local id = element.idChosen
					if id == "floor" then
						floor.roof = false
						floor.canopy = false
					elseif id == "roof" then
						floor.roof = true
						floor.canopy = false
					elseif id == "canopy" then
						floor.roof = true
						floor.canopy = true
					end
					roofOptions:SetClass("collapsed", not floor.roof)
					canopyOptions:SetClass("collapsed", not floor.canopy)
				end,
			},
		},

		roofOptions,
	}

	local nameValue
	if isLayer then
		nameValue = floor.layerDescription or ""
	else
		nameValue = floor.description or ""
	end

	--Map appearance picker. If this floor (or one of its layers) carries a Map object, expose a small
	--gallery for switching the map's image between named alternates (e.g. a "Flooded" version). This
	--drives the map object's Appearance component image-swap list, auto-creating the component on first
	--use so the user never has to touch the raw component editor.
	local mapObj = FindMapObjectForFloor(floor)
	local appearanceSection

	if mapObj ~= nil then
		--Dialog-local mirror of the Appearance component's swap state, kept index-aligned:
		--  selected == 0       -> the map's own base image ("Default")
		--  selected == i (>=1) -> swaps[i], displayed with name names[i]
		local swaps = {}
		local names = {}
		local selected = 0
		local uploading = false
		local baseName = ""

		local existing = mapObj:GetComponent("Appearance")
		if existing ~= nil and existing.valid then
			local doc = mapObj:ComponentToJson(existing.componentid)
			if doc ~= nil then
				swaps = doc.imageSwaps or {}
				names = doc.imageSwapNames or {}
				selected = doc.imageNumber or 0
				baseName = doc.imageDefaultName or ""
			end
		end

		--Pad names so every swap has a label even for pre-existing swaps saved without names.
		for i = 1, #swaps do
			if names[i] == nil then
				names[i] = string.format("Appearance %d", i)
			end
		end

		--Write the local swap state back to the map object's Appearance component, creating the component
		--if it does not exist yet. Existing components patch transactionally (keeping the component id
		--stable); the create path sets the fields in-memory then does a single MarkUndo/Upload.
		local function Persist(description)
			local comp = mapObj:GetComponent("Appearance")
			if comp ~= nil and comp.valid then
				comp:SetAndUploadProperties{
					imageSwaps = swaps,
					imageSwapNames = names,
					imageDefaultName = baseName,
					imageNumber = selected,
				}
			else
				mapObj:MarkUndo()
				mapObj:AddComponent("Appearance")
				comp = mapObj:GetComponent("Appearance")
				if comp == nil then
					return
				end
				comp:SetProperty("imageSwaps", swaps)
				comp:SetProperty("imageSwapNames", names)
				comp:SetProperty("imageDefaultName", baseName)
				comp:SetProperty("imageNumber", selected)
				mapObj:Upload()
			end
		end

		local function FileBaseName(path)
			local base = string.match(path, "[^/\\]+$") or path
			base = string.gsub(base, "%.[^.]*$", "")
			return base
		end

		local tilesPanel = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "horizontal",
			wrap = true,
			valign = "top",
		}

		local RefreshTiles

		--Let the user pick an image file off disk, upload it, then append it as a new named appearance.
		local function AddAppearance()
			if uploading then
				return
			end
			dmhub.OpenFileDialog{
				id = "MapAppearanceImage",
				extensions = {"jpeg", "jpg", "png", "webp", "bmp"},
				prompt = "Choose a map image to use as an alternate appearance",
				multiFiles = false,
				open = function(path)
					uploading = true
					RefreshTiles()
					local defaultName = FileBaseName(path)
					assets:UploadImageAsset{
						path = path,
						error = function(text)
							uploading = false
							if mod.unloaded then return end
							RefreshTiles()
							gui.ModalMessage{
								title = "Error loading image",
								message = text,
							}
						end,
						upload = function(imageid)
							uploading = false
							if mod.unloaded then return end
							swaps[#swaps+1] = imageid
							names[#names+1] = defaultName
							selected = #swaps
							Persist("Add map appearance")
							RefreshTiles()
						end,
					}
				end,
			}
		end

		--Promote a swap to be the object's literal base/default image: re-encode the object to use that
		--image, and demote the old default into the swap's now-vacant slot. Both the base and the swaps
		--are GUID-addressable, so this is a clean swap. Requires a GUID-backed map (mapObj.assetid set).
		--The image change (asset) and the swap-list change (component) are uploaded as one transaction.
		local function SetAsDefault(index)
			local newGuid = swaps[index]
			local oldBaseGuid = mapObj.assetid
			if newGuid == nil or oldBaseGuid == nil or oldBaseGuid == "" then
				return
			end

			local promotedName = names[index] or string.format("Appearance %d", index)
			local oldDefaultName = (baseName ~= nil and baseName ~= "") and baseName or "Default"

			mapObj:MarkUndo()
			if not mapObj:SetBaseImageFromAsset(newGuid) then
				return
			end

			--The promoted appearance is now the default; the old default takes its slot.
			swaps[index] = oldBaseGuid
			names[index] = oldDefaultName
			baseName = promotedName
			selected = 0

			local comp = mapObj:GetComponent("Appearance")
			if comp ~= nil and comp.valid then
				comp:SetProperty("imageSwaps", swaps)
				comp:SetProperty("imageSwapNames", names)
				comp:SetProperty("imageDefaultName", baseName)
				comp:SetProperty("imageNumber", selected)
			end
			mapObj:Upload()
			RefreshTiles()
		end

		--Build one gallery tile. index 0 is the base/default image.
		local function CreateTile(index)
			local isBase = index == 0
			local imageId = cond(isBase, mapObj.imageid, swaps[index])
			local isSelected = selected == index

			--Border/hover/selected coloring comes from the themed mapAppearanceTile styles; "image" keeps
			--the bgcolor white so the map image shows untinted. "selected" drives the accent highlight.
			local thumb = gui.Panel{
				classes = {"mapAppearanceTile", "image", "hoverable", cond(isSelected, "selected")},
				width = 104,
				height = 78,
				halign = "center",
				valign = "top",
				bgimage = imageId or "panels/square.png",
				cornerRadius = 6,
				click = function()
					--Clicking the base when there are no alternates is a no-op (nothing to switch to).
					if isBase and #swaps == 0 then
						return
					end
					selected = index
					Persist("Switch map appearance")
					RefreshTiles()
				end,
			}

			local caption
			if isBase then
				if #swaps > 0 then
					--An appearance component exists, so the default appearance carries an editable name too
					--(it travels with the image when an alternate is promoted via "Set as Default").
					caption = gui.Input{
						text = (baseName ~= nil and baseName ~= "") and baseName or "Default",
						width = 104,
						height = 24,
						halign = "center",
						fontSize = 12,
						vmargin = 2,
						change = function(element)
							baseName = element.text
							Persist("Rename default appearance")
						end,
					}
				else
					caption = gui.Label{
						text = "Default",
						width = 104,
						height = 22,
						halign = "center",
						textAlignment = "center",
						fontSize = 12,
						vmargin = 2,
					}
				end
			else
				caption = gui.Input{
					text = names[index] or string.format("Appearance %d", index),
					width = 104,
					height = 24,
					halign = "center",
					fontSize = 12,
					vmargin = 2,
					change = function(element)
						names[index] = element.text
						Persist("Rename map appearance")
					end,
				}
			end

			local tileArgs = {
				width = 112,
				height = "auto",
				flow = "vertical",
				hmargin = 4,
				vmargin = 4,
				halign = "left",
				valign = "top",
				children = { thumb, caption },
			}

			if not isBase then
				tileArgs.rightClick = function(element)
					local entries = {}

					--"Set as Default" makes this appearance the object's literal main image. Only offered
					--for GUID-backed maps, where the old default has a stable id to demote into this slot.
					if mapObj.assetid ~= nil and mapObj.assetid ~= "" then
						entries[#entries+1] = {
							text = "Set as Default",
							click = function()
								element.popup = nil
								SetAsDefault(index)
							end,
						}
					end

					entries[#entries+1] = {
						text = "Remove Appearance",
						click = function()
							element.popup = nil
							table.remove(swaps, index)
							table.remove(names, index)
							if selected == index then
								selected = 0
							elseif selected > index then
								selected = selected - 1
							end
							Persist("Remove map appearance")
							RefreshTiles()
						end,
					}

					element.popup = gui.ContextMenu{ entries = entries }
				end
			end

			return gui.Panel(tileArgs)
		end

		--The trailing "add" tile.
		local function CreateAddTile()
			--Border/surface/hover coloring comes from the themed mapAppearanceAdd styles so the tile shows
			--it is responsive (accent border + brighten on mouse-over) and tracks the active scheme.
			local thumb = gui.Panel{
				classes = {"mapAppearanceAdd", "hoverable"},
				width = 104,
				height = 78,
				halign = "center",
				valign = "top",
				bgimage = true,
				cornerRadius = 6,
				click = function()
					AddAppearance()
				end,
				gui.Label{
					text = cond(uploading, "...", "+"),
					halign = "center",
					valign = "center",
					fontSize = 40,
				},
			}

			return gui.Panel{
				width = 112,
				height = "auto",
				flow = "vertical",
				hmargin = 4,
				vmargin = 4,
				halign = "left",
				valign = "top",
				children = {
					thumb,
					gui.Label{
						text = cond(uploading, "Uploading...", "Add"),
						width = 104,
						height = 22,
						halign = "center",
						textAlignment = "center",
						fontSize = 12,
						vmargin = 2,
					},
				},
			}
		end

		RefreshTiles = function()
			local children = { CreateTile(0) }
			for i = 1, #swaps do
				children[#children+1] = CreateTile(i)
			end
			children[#children+1] = CreateAddTile()
			tilesPanel.children = children
		end

		local resolutionLabel = gui.Label{
			classes = {"formStacked"},
			text = "Checking map size...",
			fontSize = 12,
			bold = false,
			bmargin = 4,
		}

		dmhub.GetImageInfo(mapObj.imageid, function(info)
			if mod.unloaded then return end
			if info ~= nil then
				resolutionLabel.text = string.format("Map size: %d x %d. For a clean swap, use an image of the same size.", info.width, info.height)
			else
				resolutionLabel.text = "Add an alternate full-map image to swap how this map looks."
			end
		end)

		RefreshTiles()

		appearanceSection = gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			vmargin = 8,
			children = {
				gui.Label{
					classes = {"formStacked"},
					text = "Map Appearance",
				},
				resolutionLabel,
				tilesPanel,
			},
		}
	else
		--No map object on this floor; render an empty, collapsed placeholder so the dialog's child list
		--always has a valid panel in this slot.
		appearanceSection = gui.Panel{ classes = {"collapsed"}, width = "100%", height = 0 }
	end

	local dialogPanel = gui.Panel{
		classes = {"framedPanel"},
		width = 480,
		height = "auto",
		styles = ThemeEngine.MergeStyles(appearanceTileStyles),

		gui.Panel{
			width = "100%-48",
			height = "auto",
			halign = "center",
			valign = "top",
			flow = "vertical",
			vmargin = 24,

			gui.Label{
				classes = {"modalTitle"},
				text = isLayer and "Layer Settings" or "Floor Settings",
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
					text = nameValue,
					change = function(element)
						if isLayer then
							floor.layerDescription = element.text
						else
							floor.description = element.text
						end
					end,
				},
			},

			typeSection,

			appearanceSection,

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


local CreateDragTarget = function(index, belowGround, layerType)
	layerType = layerType or "floor"
	return gui.Panel{
		classes = {"floorOrLayerDragTarget", "drag-target", string.format('%sDragTarget', layerType)},
		dragTarget = true,
		data = {
			index = index,
			belowGround = belowGround,
		},

	}
end



local CreateLayersList

CreateLayersPanel = function()

	local floorItems = {}
	local currentFloorId = nil
	local groundLevelPanel = nil


	local addFloorButton = gui.Panel{
		width = "100%",
		height = "auto",
		halign = "left",
		gui.Button{
			classes = {"addButton", "sizeS"},
			halign = 'center',
			valign = 'top',
			vmargin = 2,
			tooltip = "Add a new floor",
			click = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Add New Empty Floor",
                            click = function()
                                element.popup = nil
                                game.currentMap:CreateFloor()
                            end,
                        },
                        {
                            text = "Import New Floor",
                            click = function()
                                element.popup = nil
                                mod.shared.ImportMap{
                                    imagesOnly = true,
                                    floorImport = true,
                                    finish = function(info)
                                        mod.shared.ShowFloorAlignmentDialog(info)
                                    end,
                                }
                            end,
                        },
                    }
                }
			end,
		}
	}



	local floorsList

	floorsList = gui.Panel{
		width = '100%',
		height = "100%",
		hmargin = 12,
		halign = 'left',
		valign = 'top',
		flow = 'vertical',
		vscroll = true,

		addFloorButton,

		create = function(element)
			element:ScheduleEvent("tick", 0.5)
		end,

		tick = function(element)
			element:ScheduleEvent("tick", 0.5)
			if currentFloorId ~= game.currentFloorId then
				element:FireEvent("refreshGame")
			end
		end,

		monitorGame = '/mapManifests',
		monitorGameEvent = "refreshGameRecursive",

		refreshGameRecursive = function(element)
			printf("FLOORS:: refreshGameRecursive")
			element:FireEventTree("refreshGame")
		end,

		refreshGame = function(element)

			local currentMap = game.currentMap
			local currentFloor = game.currentFloor

			currentFloorId = currentFloor.floorid
			printf("FLOORID:: %s", currentFloorId)

			if groundLevelPanel == nil then
				groundLevelPanel = gui.Panel{
					classes = {"groundLevel"},
					flow = 'none',
					height = 12,
					width = '100%',

					draggable = true,
					canDragOnto = function(element, target)
						return target:HasClass('floorDragTarget')
					end,

					drag = function(element, target)

						if target == nil then
							return
						end

						local targetIndex = target.data.index
						currentMap.groundLevel = targetIndex
						element:FireEvent("refreshGame")
					end,

					gui.Panel{
						halign = 'center',
						valign = 'center',
						bgimage = 'panels/square.png',
						width = '100%',
						height = 1,
						bgcolor = Styles.textColor,
					},

					gui.Label{
						bgimage = 'panels/square.png',
						bgcolor = 'black',
						width = 'auto',
						height = 'auto',
						fontSize = 10,
						halign = 'center',
						valign = 'center',
						color = Styles.textColor,
						text = "Ground Level",
					},
				}
			end
			
			local floors = currentMap.floors or {}
			local children = {CreateDragTarget(#floors+1)}

			if currentMap.groundLevel == #floors+1 then
				children[#children+1] = groundLevelPanel
				children[#children+1] = CreateDragTarget(#floors+1, true)
			end

			local newFloorItems = {}


			printf("FLOORS:: UPDATE FLOORS: %d", #floors)

			for i = #floors, 1, -1 do
				local floor = floors[i]

				if floor.parentFloor == nil then
					local floorPanel = floorItems[floor.floorid]

					if floorPanel == nil then

						local icons = gui.Panel{
							classes = {'floorPanelLeftIconsPanel'},

							gui.Panel{
								classes = {'floorPanelIconPanel'},
								press = function(element)
									floor.floorInvisible = not floor.floorInvisible
									element:FireEventTree("refreshGame")
								end,
								gui.Panel{
									classes = {'floorOptionIcon', cond(not floor.floorInvisible, 'enabled')},
									bgimage = cond(floor.floorInvisible, Styles.icons.hidden, Styles.icons.visible),

									refreshGame = function(element)
										element.bgimage = cond(floor.floorInvisible, Styles.icons.hidden, Styles.icons.visible)
										element:SetClass('enabled', not floor.floorInvisible)
									end,

								},
							},
							gui.Panel{
								classes = {'floorPanelIconPanel'},
								click = function(element)
									floor.locked = not floor.locked
									element:FireEventTree("refreshGame")
								end,
								gui.Panel{
									classes = {'floorOptionIcon', cond(floor.locked, 'enabled')},
									bgimage = cond(floor.locked, Styles.icons.locked, Styles.icons.unlocked),
									refreshGame = function(element)
										element.bgimage = cond(floor.locked, Styles.icons.locked, Styles.icons.unlocked)
										element:SetClass('enabled', floor.locked)
									end,
								},
							},
						}

						local minimapPanels = {}

						local minimap = gui.Panel{
							classes = {'floorPanelMinimap'},
							flow = "none",

							create = function(element)
								element:FireEvent("refreshGame")
							end,

							refreshGame = function(element)

								--we get all the layers on this floor and make a panel for each on top of each other.
								local dim = game.currentMap.dimensions
								local w = dim.x2 - dim.x1
								local h = dim.y2 - dim.y1
								local maxdim = max(w, h)

								local newMinimapPanels = {}
								local children = {}

								local layers = game.currentMap:GetLayersForFloor(floor.floorid)
								for i=#layers,1,-1 do

									local layer = layers[i]
									local layerPanel = minimapPanels[layer.floorid] or gui.Panel{
										bgimage = "#Minimap-" .. layer.floorid,
										halign = "center",
										valign = "center",
										bgcolor = "white",
										selfStyle = {},
									}

									layerPanel.selfStyle.width = tostring((95*w)/maxdim) .. "%"
									layerPanel.selfStyle.height = tostring((95*h)/maxdim) .. "%"

									newMinimapPanels[layer.floorid] = layerPanel
									children[#children+1] = layerPanel
								end

								minimapPanels = newMinimapPanels
								element.children = children
							end,
						}

						local floorLabel = gui.Label{
							classes = {'floorLabel'},
							--editable = true,
							editableOnDoubleClick = true,
							change = function(element)
								floor.description = element.text
							end,
						}

						local elevationLabel =
						gui.Panel{
							classes = {cond(not dmhub.useParallax, "collapsed")},
							monitor = "useparallax",
							events = {
								monitor = function(element)
									element:SetClass("collapsed", not dmhub.useParallax)
								end,
							},
							flow = "horizontal",
							width = 80,
							height = 20,
							gui.Label{
								classes = {"floorLabel"},
								text = "0",
								width = 40,
								height = 20,
								halign = "left",
								textAlignment = "right",
								characterLimit = 3,
								editableOnDoubleClick = true,
								data = {
									elevation = nil,
								},
								change = function(element)
									local n = MeasurementSystem.DisplayToNative(tonumber(element.text))
									if n ~= nil then
										n = n/dmhub.unitsPerSquare
									end

									if n == nil or n ~= round(n) then
										element:FireEvent("elevation", element.data.elevation)
										return
									end

									--calculate the floor below us and what their height is.
									local elevationLevel = 0
									local mapFloors = currentMap.floors
									local thisFloor = nil
									for j=1,#mapFloors do
										local f = mapFloors[j]
										if f.parentFloor == nil then
											elevationLevel = elevationLevel + f.floorHeightInTiles
											thisFloor = f
											if mapFloors[j].floorid == floor.floorid then
												break
											end
										end
									end

									if thisFloor == nil then
										element:FireEvent("elevation", element.data.elevation)
										return
									end

									local diff = n - elevationLevel
									local newHeight = thisFloor.floorHeightInTiles + diff
									if newHeight <= 0 or newHeight > 20 then
										element:FireEvent("elevation", element.data.elevation)
										return
									end
									
									thisFloor.floorHeightInTiles = newHeight
									floorsList:FireEventTree("refreshGame")
								end,
								elevation = function(element, amount)
									element.data.elevation = amount
									element.text = MeasurementSystem.NativeToDisplayString(amount*dmhub.unitsPerSquare)
								end,
							},
							gui.Label{
								classes = {"floorLabel"},
                                text = "Height",
								width = 44,
								height = 20,
								halign = "left",
								fontSize = 11,
                                minFontSize = 8,
							},
						}

						local displayedCharacters = nil
						local floorTokensPanel = gui.Panel{
							classes = {"floorTokensPanel"},
							styles = {
								{
									selectors = {"token-image"},
									width = 20,
									height = 20,
									halign = "left",
									valign = "center",
								}
							},
							monitorGame = '/characters',

							refreshGame = function(element)
								local characters = floor.playerCharactersOnFloor

								--see if the displayed characters have changed vs last time.
								if displayedCharacters ~= nil and #displayedCharacters == #characters then
									local diffs = false
									for i,c in ipairs(characters) do
										if c.charid ~= displayedCharacters[i].charid then
											diffs = true
										end
									end

									if diffs == false then
										--no changes, so just return.
										return
									end
								end

								displayedCharacters = characters

								local children = {}

								for i,c in ipairs(characters) do
									if i <= 10 then
										children[#children+1] = gui.CreateTokenImage(c,{
										})
									end
								end

								element.children = children
							end,
						}

						local opacitySlider = gui.PercentSlider{
							halign = "left",
							valign = "bottom",
							hmargin = 6,
							value = floor.floorOpacity * 0.01,
							change = function(element)
								local num = round(element.value*100)
								floor.floorOpacityNoUpload = num
							end,
							confirm = function(element)
								local num = round(element.value*100)
								floor.floorOpacity = num
							end,
						}

						local floorDetailsPanel = gui.Panel{
							classes = {'floorDetailsPanel'},

							floorLabel,
							opacitySlider,
						}

						local layersPanel = gui.Panel{
							width = "90%",
							height = "auto",
							flow = "vertical",
							expanded = function(element, expanded)
								if not expanded then
									element.children = {}
									return
								end

								element.children = {CreateLayersList(floor)}
							end,
						}

						local triangle = gui.Panel{
							styles = {
								Styles.Triangle,
								{
									selectors = {"triangle", "~expanded"},
									transitionTime = 0.2,
									rotate = 90,
								}
							},
							classes = {"triangle"},
							bgimage = "panels/triangle.png",
							press = function(element)
								element:SetClass("expanded", not element:HasClass("expanded"))
								layersPanel:FireEvent("expanded", element:HasClass("expanded"))
							end,
							click = function(element)
							end,
						}

						floorPanel = gui.Panel{
							bgimage = 'panels/square.png',
							classes = {'floorPanel'},
							monitorGame = '/mapFloors/' .. floor.floorid .. '/description',
							draggable = true,
							dragBounds = { x1 = 0, x2 = 0, y1 = -1000, y2 = 1000},

							icons,
							minimap,

							gui.Panel{
								valign = "center",
								height = 32,
								width = 32,

								triangle,
							},

							floorDetailsPanel,

							gui.Panel{
								flow = "vertical",
								width = "auto",
								height = "100%",
								elevationLabel,
								floorTokensPanel,
							},

							gui.Button{
								classes = {'settingsButton'},
								floating = true,
								halign = "right",
								valign = "top",
								width = 12,
								height = 12,
								click = function(element)
									ShowFloorSettings(floor)
								end,
							},

							data = {
								floorLabel = floorLabel,
								layersPanel = layersPanel,
							},

							rightClick = function(element)
								local floorEntries = {}

								-- Check if any layer on this floor has a map object.
								local mapObj = nil
								local mapLayer = nil
								for _, layer in ipairs(currentMap:GetLayersForFloor(floor.floorid)) do
									for _, obj in pairs(layer.objects) do
										if obj:GetComponent("Map") ~= nil then
											mapObj = obj
											mapLayer = layer
											break
										end
									end
									if mapObj ~= nil then break end
								end

								if mapObj ~= nil then
									floorEntries[#floorEntries+1] = {
										text = "Reimport Map Sizing",
										click = function()
											element.popup = nil
											mod.shared.ReimportMapSizing(mapLayer, mapObj)
										end,
									}
									floorEntries[#floorEntries+1] = {
										text = "Realign Floor...",
										click = function()
											element.popup = nil
											mod.shared.ShowFloorRealignDialog(mapLayer, mapObj)
										end,
									}
								end

								if #currentMap.floorsWithoutLayers > 1 then
									floorEntries[#floorEntries+1] = {
										text = 'Delete Floor',
										click = function()
											element.popup = nil

											if element:HasClass("selected") then
												--if this floor is selected, switch to a different floor.
												local newFloor = nil
												for k,f in pairs(floorItems) do
													if k ~= floor.floorid then
														newFloor = k
													end
												end

												if newFloor ~= nil then
													floorItems[newFloor]:FireEvent("click")
												end
											end

											local chars = floor.playerCharactersOnFloor
											if #chars > 0 then
												local players = false
												for i,c in ipairs(chars) do
													if c.playerControlled then
														players = true
													end
												end

												if players then
													gui.ModalMessage{
														title = "Cannot Delete Players",
														message = "You cannot delete a floor with players on it. Delete them first or teleport them elsewhere before deleting this floor.",
													}
												else

													gui.ModalMessage{
														title = "Delete Floor?",
														message = "This floor includes tokens on it. Do you really want to delete it?",
														options = {
															{
																text = "Yes",
																execute = function()
																	game.DeleteFloor(floor.floorid)
																end,
															},
															{
																text = "No",
																execute = function() end,
															}
														}
													}

												end
												return
											end


											game.DeleteFloor(floor.floorid)
										end,
									}
								end

								if #floorEntries > 0 then
									element.popup = gui.ContextMenu{
										entries = floorEntries
									}
								end
							end,

							canDragOnto = function(element, target)
								return target:HasClass('floorDragTarget')
							end,
							beginDrag = function(element)
								local y1 = -element.renderedHeight*0.9
								local y2 = element.renderedHeight*0.9

								--set our drag bounds based on the other elements in here.
								local seenSelf = false
								for i,el in ipairs(element.parent.children) do
									if el == element then
										seenSelf = true
									elseif seenSelf then
										y1 = y1 - el.renderedHeight
									else
										y2 = y2 + el.renderedHeight
									end
								end

								element.dragBounds = { x1 = 0, x2 = 0, y1 = y1, y2 = y2}
							end,
							drag = function(element, target)

								if target == nil then
									return
								end

								local index = element.data.index
								floors = currentMap.floors

								local layers = currentMap:GetLayersForFloor(floor.floorid)

								local indexes = {}
								for i,floor in ipairs(floors) do
									local found = false
									for _,layer in ipairs(layers) do
										if layer.floorid == floor.floorid then
											found = true
										end
									end

									if found then
										indexes[#indexes+1] = i
									end
								end

								table.sort(indexes)

								--make sure our layers are ordered correctly.
								layers = {}
								for _,i in ipairs(indexes) do
									layers[#layers+1] = floors[i]
								end

								local targetIndex = target.data.index

								local aboveGroundBefore = index >= currentMap.groundLevel
								local aboveGroundAfter = targetIndex >= currentMap.groundLevel and not target.data.belowGround

								if aboveGroundBefore and not aboveGroundAfter then
									currentMap.groundLevel = currentMap.groundLevel+#layers
								end

								if aboveGroundAfter and not aboveGroundBefore then
									currentMap.groundLevel = currentMap.groundLevel-#layers
								end

								if targetIndex > index then

									--insert with the last one first so they end up in order, since we insert before the index.
									for i=#layers,1,-1 do
										table.insert(floors, targetIndex, layers[i])
									end

									for i=#indexes,1,-1 do
										table.remove(floors, indexes[i])
									end
								else
									for i=#indexes,1,-1 do
										table.remove(floors, indexes[i])
									end

									for i=#layers,1,-1 do
										if targetIndex == 0 or targetIndex < 1 or targetIndex > #floors+1 then
											local message = ""
											for j,debugIndex in ipairs(indexes) do
												message = string.format("%s %d", message, debugIndex)
											end

											message = string.format("Illegal index %d / %d after removing indexes %s", targetIndex, #floors, message)
											dmhub.CloudError(message)
											return
										end
										table.insert(floors, targetIndex, layers[i])
									end
								end

								currentMap.floors = floors
								floorsList:FireEventTree("refreshGame")
							end,
							refreshGame = function(element)
								if not floor.valid then
									return
								end

								floorLabel.text = floor.description
								if floorLabel.text == '' then
									floorLabel.text = string.format("Floor %d", i)
								end
							end,

							refreshFloorSelection = function(element)
								floorPanel:SetClassTree('selected', game.currentFloor.actualFloor == floor.actualFloor)
							end,
							click = function(element)
								element.popup = nil

								if game.currentFloor.actualFloor ~= floor.floorid then
									game.ChangeMap(game.currentMap, floor)
									element:FindParentWithClass("dockablePanel"):FireEventTree("refreshFloorSelection")
								end
							end,


						}
					end


					--calculate the elevation level of this floor.

					local elevationLevel = 0
					for j=1,#floors do
						local f = floors[j]
						if f.parentFloor == nil then
							elevationLevel = elevationLevel + f.floorHeightInTiles
							if f.floorid == floor.floorid then
								break
							end
						end
					end

					floorPanel:FireEventTree("elevation", elevationLevel)


					elevationLevel = elevationLevel + floor.floorHeightInTiles

					floorPanel.data.index = i

					floorPanel:SetClassTree('selected', currentFloor.actualFloor == floor.actualFloor)

					floorPanel.data.floorLabel.text = floor.description
					if floorPanel.data.floorLabel.text == '' then
						floorPanel.data.floorLabel.text = string.format("Floor %d", i)
					end

					newFloorItems[floor.floorid] = floorPanel

					children[#children+1] = floorPanel
					children[#children+1] = floorPanel.data.layersPanel

					local dragTargetLevel = i --this should be the earliest level that matches.
					local groundLevel = cond(currentMap.groundLevel == i, i)

					for j = #floors, 1, -1 do

						if j < dragTargetLevel and floors[j].parentFloor == floor.floorid then
							dragTargetLevel = j
						end

						if currentMap.groundLevel == j and floors[j].parentFloor == floor.floorid then
							groundLevel = j
						end
					end


					children[#children+1] = CreateDragTarget(dragTargetLevel)

					if groundLevel ~= nil then
						children[#children+1] = groundLevelPanel
						children[#children+1] = CreateDragTarget(groundLevel, true)
					end
				end
			end

			children[#children+1] = addFloorButton

			element.children = children
			floorItems = newFloorItems
		end,
	}

	local resultPanel

	-- Local rule set for this panel's custom selectors. The @token refs are
	-- resolved by MergeTokens at call time; OnThemeChanged below re-runs the
	-- assignment so the panel recolors live when the user switches theme/scheme.
	local function buildLocalStyles()
		return {
			{
				selectors = {'floorOrLayerDragTarget'},
				bgimage = true,
				bgcolor = '@bgAlt',
				height = 2,
				width = '100%',
			},
			{
				selectors = {"floorOrLayerDragTarget", "drag-target-hover"},
				height = 10,
			},
			{
				selectors = {'floorPanel'},
				flow = "horizontal",
				bgimage = true,
				bgcolor = '@bgAlt',
				halign = "left",
				hmargin = 8,
				height = 40,
				width = '92%',
				fontSize = 16,
				color = '@fg',
			},
			{
				selectors = {'floorPanel', 'selected'},
				bgcolor = "@accent",
				gradient = "@maskHorizontal",
			},
			{
				selectors = {'floorPanel', 'dragging'},
				opacity = 0.2,
			},
			{
				selectors = {'floorPanelLeftIconsPanel'},
				height = "90%",
				width = "50% height",
				valign = "center",
				halign = "left",
				hmargin = 2,
				flow = "vertical",
			},
			{
				selectors = {'floorPanelIconPanel'},
				valign = "center",
				halign = "center",
				width = "90%",
				height = "100% width",
			},
			{
				selectors = {'floorOptionIcon'},
				width = "80%",
				height = "80%",
				halign = "center",
				valign = "center",
				bgcolor = "@fgMuted",
			},
			{
				selectors = {'floorOptionIcon', 'enabled'},
				bgcolor = "@fg",
			},
			{
				selectors = {'floorPanelMinimap'},
				bgimage = "panels/square.png",
				bgcolor = "@bg",
				borderColor = "@border",
				borderWidth = 1,
				cornerRadius = 3,
				width = "100% height",
				height = "100%",
				halign = "left",
				valign = "center",
				hmargin = 2,
			},
			{
				selectors = {'floorTokensPanel'},
				flow = "horizontal",
				halign = "left",
				valign = "bottom",
				height = "auto",
				width = "auto",
				maxWidth = 100,
				hmargin = 10,
			},
			{
				selectors = {'floorDetailsPanel'},
				flow = "vertical",
				halign = "left",
				valign = "top",
				width = 100,
				height = "90%",
			},
			{
				selectors = {'floorLabel'},
				fontSize = 14,
				color = "@fg",
				hmargin = 6,
				valign = "top",
				halign = "left",
				height = "auto",
				width = "auto",
			},
			{
				selectors = {'floorLabel', 'selected'},
				color = "@fgInverse",
			},
		}
	end

	local aspect = (dmhub.screenDimensionsBelowTitlebar.y/dmhub.screenDimensions.x) / (1080/1920)
	resultPanel = gui.Panel{
		width = "100%",
		height = "100%",
		flow = 'vertical',

		styles = ThemeEngine.MergeTokens(buildLocalStyles()),

		floorsList,
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if resultPanel ~= nil and resultPanel.valid then
			resultPanel.styles = ThemeEngine.MergeTokens(buildLocalStyles())
		end
	end)

	return resultPanel
end

CreateLayersList = function(parentFloor)

	local floorItems = {}

	local listPanel = gui.Panel{
		width = "100%",
		height = "auto",
		hmargin = 32,
		flow = "vertical",

		create = function(element)
			element:FireEvent("refreshGame")
		end,

		refreshGame = function(element)

			local children = {}

			local newFloorItems = {}

			local floors = game.currentMap.floors

			for i = #floors, 1, -1 do
				local floor = floors[i]

				if floor.floorid == parentFloor.floorid or floor.parentFloor == parentFloor.floorid then
					local floorPanel = floorItems[floor.floorid]

					if floorPanel == nil then

						local icons = gui.Panel{
							classes = {'floorPanelLeftIconsPanel'},

							gui.Panel{
								classes = {'floorPanelIconPanel'},
								click = function(element)
									floor.invisible = not floor.invisible
									element:FireEventTree("refreshGame")
								end,
								gui.Panel{
									classes = {'floorOptionIcon', cond(not floor.invisible, 'enabled')},
									bgimage = cond(floor.invisible, 'icons/icon_tool/icon_tool_60.png', 'icons/icon_tool/icon_tool_59.png'),

									refreshGame = function(element)
										element.bgimage = cond(floor.invisible, 'icons/icon_tool/icon_tool_60.png', 'icons/icon_tool/icon_tool_59.png')
										element:SetClass('enabled', not floor.invisible)
									end,

								},
							},
							gui.Panel{
								classes = {'floorPanelIconPanel'},
								click = function(element)
									floor.locked = not floor.locked
									element:FireEventTree("refreshGame")
								end,
								gui.Panel{
									classes = {'floorOptionIcon', cond(floor.locked, 'enabled')},
									bgimage = cond(floor.locked, 'icons/icon_tool/icon_tool_30.png', 'icons/icon_tool/icon_tool_30_unlocked.png'),
									refreshGame = function(element)
										element.bgimage = cond(floor.locked, 'icons/icon_tool/icon_tool_30.png', 'icons/icon_tool/icon_tool_30_unlocked.png')
										element:SetClass('enabled', floor.locked)
									end,
								},
							},
						}

						local minimap = gui.Panel{
							classes = {'floorPanelMinimap'},
							gui.Panel{
								bgimage = "#Minimap-" .. floor.floorid,
								halign = "center",
								valign = "center",
								bgcolor = "white",
								selfStyle = {
								},
								create = function(element)
									local dim = game.currentMap.dimensions
									local w = dim.x2 - dim.x1
									local h = dim.y2 - dim.y1
									local maxdim = max(w, h)
									element.selfStyle.width = tostring((95*w)/maxdim) .. "%"
									element.selfStyle.height = tostring((95*h)/maxdim) .. "%"
								end,
								refreshGame = function(element)
									element:FireEvent("create")
								end,

							}
						}

						local floorLabel = gui.Label{
							classes = {'floorLabel'},
							--editable = true,
							editableOnDoubleClick = true,
							change = function(element)
								floor.layerDescription = element.text
							end,
						}

						local displayedCharacters = nil
						local floorTokensPanel = gui.Panel{
							classes = {"floorTokensPanel"},
							styles = {
								{
									selectors = {"token-image"},
									width = 20,
									height = 20,
									halign = "center",
									valign = "center",
								}
							},
							monitorGame = '/characters',

							refreshGame = function(element)
								local characters = floor.playerCharactersOnFloor

								--see if the displayed characters have changed vs last time.
								if displayedCharacters ~= nil and #displayedCharacters == #characters then
									local diffs = false
									for i,c in ipairs(characters) do
										if c.charid ~= displayedCharacters[i].charid then
											diffs = true
										end
									end

									if diffs == false then
										--no changes, so just return.
										return
									end
								end

								displayedCharacters = characters

								local children = {}

								for i,c in ipairs(characters) do
									if i <= 10 then
										children[#children+1] = gui.CreateTokenImage(c,{
										})
									end
								end

								element.children = children
							end,
						}

						local opacitySlider = gui.PercentSlider{
							halign = "left",
							valign = "bottom",
							hmargin = 6,
							value = floor.opacity * 0.01,
							change = function(element)
								local num = round(element.value*100)
								floor.opacityNoUpload = num
							end,
							confirm = function(element)
								local num = round(element.value*100)
								floor.opacity = num
							end,
						}

						local floorDetailsPanel = gui.Panel{
							classes = {'floorDetailsPanel'},

							floorLabel,
							opacitySlider,
						}

						floorPanel = gui.Panel{
							bgimage = 'panels/square.png',
							classes = {'floorPanel'},
							monitorGame = '/mapFloors/' .. floor.floorid .. '/layerDescription',
							draggable = true,
							dragBounds = { x1 = 0, x2 = 0, y1 = -1000, y2 = 1000},

							icons,
							minimap,

							floorDetailsPanel,

							gui.Panel{
								flow = "vertical",
								width = "auto",
								height = "100%",
								floorTokensPanel,
							},

							gui.Button{
								classes = {'settingsButton'},
								floating = true,
								halign = "right",
								valign = "top",
								width = 12,
								height = 12,
								click = function(element)
									ShowFloorSettings(floor)
								end,
							},

							data = {
								floor = floor,
								floorLabel = floorLabel,
								index = i,
							},

							rightClick = function(element)
								local floors = game.currentMap.floors
								local entries = {}

								local i = element.data.index

								if floors[i-1] ~= nil and floors[i-1].actualFloor == floor.actualFloor then
									entries[#entries+1] = {
										text = 'Merge Down',
										click = function()
											element.popup = nil

											--select the main layer for this floor.
											for k,f in pairs(floorItems) do
												if f.data.floor.parentFloor == nil then
													f:FireEvent("click")
												end
											end

											game.MergeFloors(floors[i-1].floorid, floors[i].floorid)
										end,
									}
								end

								if floor.parentFloor ~= nil then
									entries[#entries+1] =
									{
										text = 'Delete Layer',
										click = function()
											element.popup = nil

											if element:HasClass("selected") then
												--if this floor is selected, switch to a different floor.
												local newFloor = nil
												for k,f in pairs(floorItems) do
													if k ~= floor.floorid then
														newFloor = k
													end
												end

												if newFloor ~= nil then
													floorItems[newFloor]:FireEvent("click")
												end
											end

											local chars = floor.playerCharactersOnLayer
											if #chars > 0 then
												local players = false
												for i,c in ipairs(chars) do
													if c.playerControlled then
														players = true
													end
												end

												if players then
													gui.ModalMessage{
														title = "Cannot Delete Players",
														message = "You cannot delete a floor with players on it. Delete them first or teleport them elsewhere before deleting this floor.",
													}
												else

													gui.ModalMessage{
														title = "Delete Layer?",
														message = "This Layer includes tokens on it. Do you really want to delete it?",
														options = {
															{
																text = "Yes",
																execute = function()
																	game.DeleteFloor(floor.floorid)
																end,
															},
															{
																text = "No",
																execute = function() end,
															}
														}
													}

												end
												return
											end


											game.DeleteFloor(floor.floorid)
										end,
									}
								end

								-- Check if this layer has a map object for reimport.
								local mapObj = nil
								local mapObjId = nil
								for objKey, obj in pairs(floor.objects) do
									if obj:GetComponent("Map") ~= nil then
										mapObj = obj
										mapObjId = objKey
										break
									end
								end

								if mapObj ~= nil then
									entries[#entries+1] = {
										text = "Reimport Map Sizing",
										click = function()
											element.popup = nil
											mod.shared.ReimportMapSizing(floor, mapObj)
										end,
									}
								end

								if #entries > 0 then
									element.popup = gui.ContextMenu{
										entries = entries
									}
								end
							end,

							canDragOnto = function(element, target)
								return target:HasClass('layerDragTarget')
							end,
							beginDrag = function(element)
								local y1 = -element.renderedHeight*0.9
								local y2 = element.renderedHeight*0.9

								--set our drag bounds based on the other elements in here.
								local seenSelf = false
								for i,el in ipairs(element.parent.children) do
									if el == element then
										seenSelf = true
									elseif seenSelf then
										y1 = y1 - el.renderedHeight
									else
										y2 = y2 + el.renderedHeight
									end
								end

								element.dragBounds = { x1 = 0, x2 = 0, y1 = y1, y2 = y2}
							end,
							drag = function(element, target)

								if target == nil then
									return
								end

								local index = element.data.index
								floors = game.currentMap.floors

								local targetIndex = target.data.index

								if targetIndex > index then
									table.insert(floors, targetIndex, floor)
									table.remove(floors, index)
								else
									table.remove(floors, index)
									table.insert(floors, targetIndex, floor)
								end

								game.currentMap.floors = floors
        						element:FindParentWithClass("dockablePanel"):FireEventTree("refreshGame")
							end,
							refreshGame = function(element)
								if not floor.valid then
									return
								end


								local text
								if floor.isPrimaryLayerOnFloor then
									text = "Primary Layer"
									floorLabel.editableOnDoubleClick = false
								else
									text = floor.layerDescription
									floorLabel.editableOnDoubleClick = true
								end

								if text == '' then
									text = string.format("Layer %d", i)
								end

								floorLabel.text = text
							end,
							refreshFloorSelection = function(element)
								floorPanel:SetClassTree('selected', game.currentFloor.floorid == floor.floorid)
							end,
							click = function(element)
								element.popup = nil
								game.ChangeMap(game.currentMap, floor)
        						element:FindParentWithClass("dockablePanel"):FireEventTree("refreshFloorSelection")
							end,

						}
					end

					floorPanel.data.index = i

					floorPanel:SetClassTree('selected', game.currentFloor.floorid == floor.floorid)

					floorPanel.data.floorLabel.text = floor.layerDescription
					if floorPanel.data.floorLabel.text == '' then
						floorPanel.data.floorLabel.text = string.format("Layer %d", i)
					end

					newFloorItems[floor.floorid] = floorPanel

					if #children == 0 then
						children[#children+1] = CreateDragTarget(i+1, false, "layer")
					end

					children[#children+1] = floorPanel
					children[#children+1] = CreateDragTarget(i, false, "layer")
				end
			end

			floorItems = newFloorItems
			element.children = children

		end,
	}

	return gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		listPanel,

		gui.Button{
			classes = {"addButton", "sizeS"},
			halign = 'right',
			valign = 'bottom',
			margin = 0,
			click = function(element)
				game.currentMap:CreateFloor{
                    parentFloor = parentFloor.floorid
                }
			end,
			hover = gui.Tooltip("Add a new layer"),
		},

	}

end