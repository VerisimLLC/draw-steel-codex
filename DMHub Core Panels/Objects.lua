local mod = dmhub.GetModLoading()

DockablePanel.Register{
	name = "Objects",
	icon = mod.images.objectsIcon,
	vscroll = true,
	hideObjectsOutOfScroll = false,
	minHeight = 200,
	dmonly = true,
	folder = "Map Editing",
	stickyFocus = true,
	content = function()
		return mod.shared.CreateObjectEditor()
	end,
	hasNewContent = function()
		return module.HasNovelContent("object")
	end,
}

local function Indent(depth)
	if depth <= 1 or depth >= 6 then
		return 0
	end

	return 14
end

local CreateObjectNode

mod.shared.selectedObjectEntries = {}

local ObjectPanelHeight = 30

local function IsObjectNodeSelfOrChildOf(nodeid, childid)
	if nodeid == childid then
		return true
	end

	if childid == '' then
		return false
	end

	local node = assets:GetObjectNode(childid)
	if node == nil then
		return false
	end

	return IsObjectNodeSelfOrChildOf(nodeid, node.parentFolder)
end

local ShowObjectTooltip = function(element)
	local dock = element:FindParentWithClass("dock")
	assert(dock ~= nil)
	
	local node = assets:GetObjectNode(element.data.nodeid)

	local duplicatedText = {}

	local behaviorText = ''

	if node.components ~= nil then
		for k,component in pairs(node.components) do
			if component.behaviorDescription ~= nil and (not duplicatedText[component.behaviorDescription]) then
				behaviorText = behaviorText .. component.behaviorDescription .. '\n'
				duplicatedText[component.behaviorDescription] = true
			end
		end
	end

	if behaviorText == '' then
		behaviorText = '<b>Cosmetic</b>: This object is purely cosmetic and does not affect lighting, pathfinding, or have any other special properties.'
	end

	local gridPanel = gui.Panel{
		style = {
			width = '100%',
			height = '100%',
			flow = 'none',
			opacity = 0.5,
		}
	}

	local imageDim = 240

	element.tooltipParent = dock

	local artistInfo = assets.artists[node.artist]
	local artistLabel = nil
	if artistInfo ~= nil then
		artistLabel = gui.Label{
			text = "Artist: " .. artistInfo.name,
			style = {
				italics = true,
				fontSize = '40%',
				width = '90%',
				height = 'auto',
				color = '#bbbbbbff',
			},
		}
	end

	local tooltip = gui.TooltipFrame(
		gui.Panel{
			interactable = false,
			style = {
				fontSize = '80%',
				width = 300,
				height = 'auto',
				flow = 'vertical',
			},

			children = {
				--title text.
				gui.Label{
					text = node.description,
					style = {
						minFontSize = 14,
						halign = 'left',
						valign = 'top',
						hpad = 2,
						vpad = 2,
						color = 'white',
						borderWidth = 0,
						height = 'auto',
						width = 'auto',
						maxWidth = 280,
					}
				},

				--some padding.
				gui.Panel{ style = { width = '100%', height = 8 } },

				--image of the object, with a fancy grid behind and scaling behavior and things.
				gui.Panel{
					style = {
						width = imageDim,
						height = imageDim,
						bgcolor = 'white',
						hpad = 0,
						vpad = 0,
						borderWidth = 0,
						halign = 'center',
						valign = 'center',
						hmargin = 0,
						vmargin = 0,
						flow = 'none',
					},
					
					children = {
						gridPanel,
						gui.Panel{
							bgimage = node.thumbnailId,
							selfStyle = {
								width = imageDim,
								height = imageDim,
								bgcolor = 'white',
								borderWidth = 0,
								hueshift = node.hue,
								saturation = node.saturation,
								brightness = node.brightness,
							},
							events = {
								imageDimensions = function(element, info)
									if element.bgsprite == nil then
										dmhub.Debug('NO BG SPRITE')
									end
									local maxDim = max(info.width, info.height)*node.scale
									local xratio = (info.width*node.scale)/maxDim
									local yratio = (info.height*node.scale)/maxDim
									local dim = maxDim / info.ppu

									--the dimensions/number of tiles we will display this object on.
									local numTiles = max(2, math.ceil(dim))

									local percent = dim/numTiles

									element.selfStyle.width = tostring(percent*100*xratio) .. '%'
									element.selfStyle.height = tostring(percent*100*yratio) .. '%'

									dmhub.Debug(string.format('BG SPRITE DIMENSIONS: %f', dim))

									local lines = {}
									local lineSpacing = imageDim/numTiles

									local i = 0
									while i < numTiles/2 do
										local index = 0.5 + i
										lines[#lines+1] = gui.Panel{
											bgimage = 'panels/square.png',
											x = -index*lineSpacing,
											style = {
												width = 1,
												height = '100%',
												bgcolor = 'white',
											}
										}
										lines[#lines+1] = gui.Panel{
											bgimage = 'panels/square.png',
											x = index*lineSpacing,
											style = {
												width = 1,
												height = '100%',
												bgcolor = 'white',
											}
										}
										lines[#lines+1] = gui.Panel{
											bgimage = 'panels/square.png',
											y = -index*lineSpacing,
											style = {
												width = '100%',
												height = 1,
												bgcolor = 'white',
											}
										}
										lines[#lines+1] = gui.Panel{
											bgimage = 'panels/square.png',
											y = index*lineSpacing,
											style = {
												width = '100%',
												height = 1,
												bgcolor = 'white',
											}
										}

										i = i + 1
									end

									gridPanel.children = lines
								end,
							}
						},
					},
				},

				--some padding.
				gui.Panel{ style = { width = '100%', height = 8 } },

				--text describing object properties.
				gui.Label{
					text = behaviorText,
					style = {
						vmargin = 8,
						fontSize = '60%',
						width = '90%',
						height = 'auto',
						color = 'white',
					}
				},

				artistLabel,

			},
		},
		{
			valign = 'center',
			halign = dock.data.TooltipAlignment(),

		}
	)

    gui.GetImageDimensionsCallback(node.image, function(info)
        tooltip:FireEventTree("imageDimensions", info)
    end)

	element.tooltip = tooltip
end


--clear out any selected objects from parents other than the listed one. This is
--necessary event if ctrl or shift is held when focusing an object entry because
--you can't multi-select objects from multiple different nodes.
local function ClearSelectedObjectEntriesFromOtherParents(parentElement)
	local newEntries = {}
	for i,entry in ipairs(mod.shared.selectedObjectEntries) do
		if entry.data.parentElement ~= parentElement then
			entry:SetClass('selected', false)
		else
			newEntries[#newEntries+1] = entry
		end
	end

	mod.shared.selectedObjectEntries = newEntries
end

--clear all objects in the palette which are 'selected'.
local function ClearSelectedObjectEntries()
	for i,entry in ipairs(mod.shared.selectedObjectEntries) do
		if entry ~= nil and entry.valid then
			entry:SetClass('selected', false)
		end
	end

	mod.shared.selectedObjectEntries = {}
end

--mark an object in the palette as 'selected' which means it is not necessarily
--focused but is part of the current selection.
local function SelectObjectEntry(entry)
	local alreadyPresent = false
	for i,e in ipairs(mod.shared.selectedObjectEntries) do
		if e == entry then
			alreadyPresent = true
		end
	end
	
	if alreadyPresent then
		return
	end

	mod.shared.selectedObjectEntries[#mod.shared.selectedObjectEntries+1] = entry
	entry:SetClass('selected', true)
end

--move the focused object to another object within the current selection of objects.
local function ScrollObjectEntries(delta)
	if gui.GetFocus() == nil or #mod.shared.selectedObjectEntries == 0 then
		return
	end

	local best = nil
	local bestScore = nil
	local targetIndex = gui.GetFocus().siblingIndex

	for i,entry in ipairs(mod.shared.selectedObjectEntries) do
		if entry ~= gui.GetFocus() and entry.data.parentElement == gui.GetFocus().data.parentElement then
			local index = entry.siblingIndex
			local score = index
			if index > targetIndex then
				score = score - 10000
			end

			score = -score*delta

			if best == nil or score < bestScore then
				bestScore = score
				best = entry
			end
		end
	end

	if best ~= nil then
		if gui.GetFocus():HasClass('selected') == false then
			SelectObjectEntry(gui.GetFocus())
		end
		gui.SetFocus(best)
	end
end

Commands.nextobj = function()
	ScrollObjectEntries(1)
end

Commands.prevobj = function()
	ScrollObjectEntries(-1)
end

--randomize which object is selected out of the list.
local function RandomizeObjectSelection()
	if gui.GetFocus() == nil or #mod.shared.selectedObjectEntries == 0 then
		return
	end
	
	local index = math.random(#mod.shared.selectedObjectEntries)
	local best = mod.shared.selectedObjectEntries[index]
	if best ~= nil then
		if gui.GetFocus() ~= nil and gui.GetFocus():HasClass('selected') == false then
			SelectObjectEntry(gui.GetFocus())
		end
		gui.SetFocus(best)
	end
end

Commands.randobj = RandomizeObjectSelection

local g_objectEntryStyles = {
	gui.Style{
		color = '#ccccccff',
		valign = 'top',
		bgcolor = '#ffffff00',
		width = 40,
		height = 40,
		borderWidth = 0,
		borderColor = 'black',
		flow = 'none',
	},

	gui.Style{
		selectors = {'selected'},
		borderWidth = 2,
		borderColor = '#ffffff99',
	},

	gui.Style{
		selectors = {'focus'},
		bgcolor = '#ffffff66',
		color = '#ffffffff',
		borderWidth = 2,
		borderColor = 'white',
	},

	gui.Style{
		selectors = {'hover'},
		bgcolor = Styles.textColor,
	},

	gui.Style{
		selectors = {'drag-target'},
		borderWidth = 2,
		borderColor = '#0000ff44',
	},

	gui.Style{
		selectors = {'drag-target-hover'},
		borderWidth = 2,
		borderColor = '#0000ffff',
	},

}

local function CreateObjectEntry(nodeid, parentElement, options)
	local node = assets:GetObjectNode(nodeid)

	local searchActive = false
	local matchesSearch = true
	local parentCollapsed = false

	local resultPanel = nil


	local objImagePanel = gui.Panel{
		bgimage = node.thumbnailId,

		bgcolor = 'white',
		halign = 'center',
		valign = 'center',
		width = '100%',
		height = '100%',
		hueshift = node.hue,
		saturation = node.saturation,
		brightness = node.brightness,

		events = {
			imageLoaded = function(element)
				local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
				if maxDim > 0 then
					local xratio = element.bgsprite.dimensions.x/maxDim
					local yratio = element.bgsprite.dimensions.y/maxDim
					element.selfStyle.width = tostring(xratio*100) .. '%'
					element.selfStyle.height = tostring(yratio*100) .. '%'
				end
			end,
		},
	}


	resultPanel = gui.Panel({
		bgimage = 'panels/square.png',
		classes = {'object-entry'},
		--dragTarget = true,
		draggable = true,
		canDragOnto = function(element, target)
			if target:HasClass('accept-objects') then
				return true
			end
			if target:HasClass('dm-hud-sidebar') then
				return true
			end
			return (target:HasClass('object-drag-target') or (target:HasClass('object-entry') and element.parent == target.parent)) and not IsObjectNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
		end,
		styles = g_objectEntryStyles,

		events = {
			dragging = function(element, target)
				if target == nil and mod.shared.CreateEffectDialog == nil then
					if next(mod.shared.objectDragAcceptors) ~= nil then
						--there is at least one object, so don't go into mode to drag object onto map.
						return
					end

					element.dragging = false
					dmhub.SetDraggingObject()
				end
			end,
			drag = function(element, target)
				if target == nil or target:HasClass('dm-hud-sidebar') then
					return
				end

				if target:HasClass('accept-objects') then
					target:FireEvent('dragObject', nodeid)
					return
				end

				if target:HasClass('object-entry') then

					--we are dragging onto another object in the same folder.
					--Iterate the objects and make sure they all have appropriate ords,
					--swapping the objects that are subject of the drag.
					local sourceNode = assets:GetObjectNode(element.data.nodeid)
					local targetNode = assets:GetObjectNode(target.data.nodeid)

					local sourceOrd = sourceNode.ord
					local targetOrd = targetNode.ord

					sourceNode.ord = targetOrd
					targetNode.ord = sourceOrd

					sourceNode:Upload()
					targetNode:Upload()

					local childElements = {}
					local childNodes = {}
					for i,v in ipairs(parentElement.data.childObjectPanels) do
						local node = nil
						local childElement = nil
						--swap the target node and source node, otherwise keep nodes the same.
						if v.data.nodeid == element.data.nodeid then
							node = targetNode
							childElement = target
						elseif v.data.nodeid == target.data.nodeid then
							node = sourceNode
							childElement = element
						else
							node = assets:GetObjectNode(v.data.nodeid)
							childElement = v
						end
						
						childNodes[#childNodes+1] = node
						childElements[#childElements+1] = childElement
					end

					--fast and dirty image swap with the other object.
					local bgimage = objImagePanel.bgimage
					objImagePanel.bgimage = target.data.objImagePanel.bgimage
					target.data.objImagePanel.bgimage = bgimage

				else

					--dragging into a folder.
					local draggingItems = mod.shared.selectedObjectEntries
					if draggingItems == nil or #draggingItems == 0 then
						draggingItems = {element}
					end

					local maxOrd = 1
					local targetNode = assets:GetObjectNode(target.data.nodeid)

					if targetNode == nil then
						return
					end

					for i,v in ipairs(targetNode.children) do
						if v.ord > maxOrd then
							maxOrd = v.ord
						end
					end

					for i,v in ipairs(draggingItems) do
						local draggingNode = assets:GetObjectNode(v.data.nodeid)
						if draggingNode ~= nil and draggingNode ~= targetNode then
							draggingNode.parentNode = target.data.nodeid
							maxOrd = maxOrd+1
							draggingNode.ord = maxOrd
							draggingNode:Upload()

							--hide this element after dragging so it doesn't flash back to its original
							--position for a moment. It will be re-created when the asset refresh occurs.
							v:SetClass('collapsed', true)
						end
					end

					ClearSelectedObjectEntries()



				end
			end,

			refreshAssets = function(element)
				node = assets:GetObjectNode(nodeid)
				objImagePanel.bgimage = node.thumbnailId

				if element:HasClass('focus') then
					element:FireEvent('focus')
				end

				element.x = Indent(element.data.depth)
			end,

			beginDrag = function(element)
				--cancel any focus so we force focus this object.
				if element:HasClass('selected') == false then
					gui.SetFocus(nil)
					ClearSelectedObjectEntries()

					if next(mod.shared.objectDragAcceptors) == nil then
						--if there isn't an external sheet we're trying to drag on then also treat as a click.
						element:FireEvent('click')
					end

				end
			end,

			click = function(element)
				if gui.GetFocus() == element then
					gui.SetFocus(nil)
				else
					local modKeys = dmhub.modKeys

					if (not modKeys['ctrl']) and (not modKeys['shift']) then
						ClearSelectedObjectEntries()
					else
						ClearSelectedObjectEntriesFromOtherParents(resultPanel.data.parentElement)
					end

					--if we press shift or control while clicking we multi-select objects.
					if gui.GetFocus() and gui.GetFocus().data.objectid and gui.GetFocus().data.parentElement == element.data.parentElement then
						if modKeys['ctrl'] then
							SelectObjectEntry(gui.GetFocus())
						elseif modKeys['shift'] then
							local i1 = math.min(gui.GetFocus().siblingIndex, element.siblingIndex)
							local i2 = math.max(gui.GetFocus().siblingIndex, element.siblingIndex)
							for i,entry in ipairs(gui.GetFocus().parent.children) do
								if entry.data.objectid and i >= i1 and i <= i2 and entry:HasClass("collapsed") == false then
									SelectObjectEntry(entry)
								end
							end
						end
					end

					gui.SetFocus(element)
				end

				if element.popup ~= nil then
					element.popup = nil
				end
			end,

			rightClick = function(element)
				--create the context menu for this object.
				local menuItems = {}
				local parentElement = element

				if nodeid ~= '' then

					--Edit object.
					menuItems[#menuItems+1] = {
						text = 'Edit Object',

						click = function()
							local nodeids = {}
							local found = false
							for i,entry in ipairs(mod.shared.selectedObjectEntries) do
								nodeids[#nodeids+1] = entry.data.nodeid
								if entry.data.nodeid == nodeid then
									found = true
								end
							end
							
							if found == false then
								nodeids[#nodeids+1] = nodeid
							end


							mod.shared.EditObjectDialog(nodeids)
							parentElement.popup = nil
						end,
					}

					--Duplicate object.
					menuItems[#menuItems+1] = {
						text = 'Duplicate Object',

						click = function()
							node:Duplicate()
							parentElement.popup = nil
						end,
					}

					--Delete object.
					menuItems[#menuItems+1] = {
						text = 'Delete Object',

						click = function()

							local nodeids = {}
							local found = false
							for i,entry in ipairs(mod.shared.selectedObjectEntries) do
								nodeids[#nodeids+1] = entry.data.nodeid
								if entry.data.nodeid == nodeid then
									found = true
								end
							end
							
							if found == false then
								nodeids[#nodeids+1] = nodeid
							end

							local exec = function()
								for _,nodeid in ipairs(nodeids) do	
									local node = assets:GetObjectNode(nodeid)
									if node ~= nil then
										node:Delete()
									end
								end
							end

							if #nodeids <= 1 then
								exec()
							else
							gui.ModalMessage({
								title = 'Delete Objects',
								message = string.format("Do you really want to delete %d selected objects?", #nodeids),
								options = {
									{
										text = 'Okay',
										execute = exec,
									},
									{
										text = 'Cancel',
									},
								}
							})
							end

							parentElement.popup = nil
						end,
					}


					if devmode() then
						menuItems[#menuItems+1] = {
							text = 'Get Object Image',
							click = function()
								node:OpenImageUrl()
								parentElement.popup = nil
							end,
						}

						menuItems[#menuItems+1] = {
							text = "Copy Image ID",
							click = function()
								dmhub.CopyToClipboard(node.imageFileId)
								parentElement.popup = nil
							end,
						}

						menuItems[#menuItems+1] = {
							text = "Copy Object ID",
							click = function()
								dmhub.CopyToClipboard(nodeid)
								parentElement.popup = nil
							end,
						}
					end


				end

				element.popupPositioning = 'mouse'
				element.popup = gui.ContextMenu{
					entries = menuItems,
				}
			end,

			focus = function(element)
			end,

			hover = function(element)
				ShowObjectTooltip(element)
                local nhighlights = 0

                local objects = game.currentFloor.objects
                for _,obj in pairs(objects) do
                    local assetid = obj.assetid
                    if assetid == nodeid then
                        obj.editorFocus = true
                        nhighlights = nhighlights + 1
                    end
                end

                element.data.nhighlights = nhighlights
			end,

			dehover = function(element)
                if (element.data.nhighlights or 0) > 0 then
                    local objects = game.currentFloor.objects
                    for _,obj in pairs(objects) do
                        local assetid = obj.assetid
                        if assetid == nodeid then
                            obj.editorFocus = false
                        end
                    end
                end
			end,
		},

		data = {
			objImagePanel = objImagePanel,

			parentElement = parentElement, --the parentElement that owns this.

			nodeid = nodeid, --storing the nodeid with the panel for drag and drop.

			objectid = nodeid, --this field is read by DMHud.GetSelectedObject to query if there is a selected object when this is focused.

			node = function()
				return node
			end,

			search = function(text, matchedParent)
				searchActive = text ~= ''
				matchesSearch = matchedParent or text == '' or node:MatchesSearch(text)

				resultPanel:SetClass('collapsed', (parentCollapsed and not searchActive) or (not matchesSearch))

				return matchesSearch
			end,

			--recursively turn search status off, for when we collapse a searched node. This doesn't globally disable
			--the search but makes us stop respecting it on this node.
			setSearchInactive = function(element)
				searchActive = false
			end,

			setParentCollapsed = function(element, newValue)
				parentCollapsed = newValue
				element:SetClass('collapsed', (parentCollapsed and not searchActive) or (not matchesSearch))
			end,

			SetDepth = function(element, depth)
				element.data.depth = depth
			end,

			depth = 0,
		},

		children = {
			objImagePanel,
			gui.NewContentAlertConditional("object", nodeid, {x = -4}),
		}
	})

	return resultPanel
end

local DragHandleStyles = {
	gui.Style{
		bgcolor = "clear",
	},
	gui.Style{
		selectors = {"drag-target"},
		bgcolor = "#111111ff",
	},
	gui.Style{
		selectors = {"drag-target-hover"},
		bgcolor = "white",
		brightness = 1.5,
	},
}

local function CreateObjectFolder(nodeid, parentElement, options)
	local matchesSearch = true
	local searchActive = false
	local parentCollapsed = false
	local isCollapsed = true
	local refreshAssetsDirty = false
	local node = assets:GetObjectNode(nodeid)

	local folderPane = nil

	--the root folder gets additional UI, such as a search and ways to add objects.
	local rootPanel = nil
	local clearSearchButton = nil
	if nodeid == '' then

		isCollapsed = false

		local updateSearch = function(element)
			clearSearchButton:SetClass('collapsed', element.text == '')
			local text = element.text
			if string.len(text) <= 1 then
				--one character searches just count as no search.
				text = ""
			end
			if text ~= "" then
				local nodeids = node:GetNodeIdsMatchingSearch(element.text)
				local count = 0
				for k,v in pairs(nodeids) do
					count = count + 1
				end
				printf("PrepareSearch: (%s) / %d", text, count)
				folderPane:FireEventTree("prepareSearch", nodeids)
			end
			folderPane.data.search(text)
		end

		local searchInput = gui.Input{
			id = 'ObjectSearch',
			placeholderText = 'Search Objects...',
			style = {
				fontSize = '50%',
				width = '80%',
				height = '100%',
				halign = 'left',
				valign = 'center',
			},

			editlag = 0.25,
			events = {
				change = updateSearch,
				edit = function(element)
					updateSearch(element)
				end,
			}
		}

		clearSearchButton = gui.Button{
			icon = 'ui-icons/close.png',
			classes = {'collapsed'},
			width = 16,
			height = 16,
			halign = 'left',
			valign = 'center',

			events = {
				click = function(element)
					searchInput.text = ''
					updateSearch(searchInput)
				end,
			}
		}


		rootPanel =
		gui.Panel{
			id = 'RootUIPanel',
			x = 10,
			style = {
				height = 'auto',
				width = '90%',
				flow = 'vertical',
			},

			children = {
				gui.Panel{
					id = 'ObjectSearchPanel',
					style = {
						height = 30,
						width = '100%',
						flow = 'horizontal',
					},
					children = {
						searchInput,
						clearSearchButton,
					},
				},

				gui.Panel{
					id = 'AddNodesPanel',
					style = {
						height = 30,
						width = '100%',
						flow = 'horizontal',
					},
					children = {

						gui.Panel{
							classes = {"clickableIcon"},
							width = 24,
							height = 24,
							halign = "right",
							bgimage = "game-icons/open-folder.png",
							linger = gui.Tooltip("Create a new folder"),
							press = function(element)
								dmhub.AddObjectFolder()
							end,
						},

						gui.Panel{
							classes = {"clickableIcon"},
							width = 24,
							height = 24,
							halign = "right",
							id = "ImportMapObjectButton",
							bgimage = 'game-icons/treasure-map.png',
							linger = gui.Tooltip('Import a new map object from an image'),
							press = function(element)
								mod.shared.ImportMap{ imagesOnly = true }
							end,
						},

						gui.AddButton{
							height = '100%',
							width = '100% height',
							halign = 'right',
							events = {
								linger = gui.Tooltip("Import new objects from an image"),
								click = function(element)
									mod.shared.ImportObjects()
									--dmhub.ImportObjects()
								end,
							}
						},
					}
				},
			},
		}
	end

	local triangle = nil
	triangle = gui.Panel({
				bgimage = 'panels/triangle.png',
				classes = {"triangle", cond(nodeid == "", "collapsed") },

				styles =
				{

					{
						rotate = 90,
					},
					{
						selectors = {'expanded'},
						transitionTime = 0.2,
						rotate = 0,
					},
					{
						selectors = {'search'},
						transitionTime = 0,
						rotate = 0,
					},
				},

				events = {
					create = function(element)
						element:SetClass('expanded', not isCollapsed)

						element:FireEvent("refreshAssets")
					end,
					refreshAssets = function(element)
						local nchildren = #node.children
						if nchildren > 0 and options.hideobjects then
							nchildren = 0
							for _,child in ipairs(node.children) do
								if child.isfolder then
									nchildren = nchildren+1
									break
								end
							end

						end
						element:SetClass('empty', nchildren < 1)
					end,
					refreshCollapse = function(element)
						element:SetClass('expanded', not isCollapsed)
					end,
					press = function(element)
						if element:HasClass("collapsed") then
							--this is on the root where we don't want to show a triangle at all.
							return
						end
						isCollapsed = not isCollapsed

						if (not isCollapsed) and refreshAssetsDirty then
							folderPane:FireEventTree("refreshAssets")
						end

						if rootPanel ~= nil and isCollapsed then
							--when we collapse the root panel we clear out any object selection state.
							ClearSelectedObjectEntries()
						end

						if searchActive then
							isCollapsed = true
							folderPane.data.setSearchInactive(folderPane)
							element:SetClass('search', false)
							searchActive = false

							if clearSearchButton ~= nil then --is root panel, clear search.
								clearSearchButton:FireEvent('click')
							end
						end

						triangle:SetClass('expanded', not isCollapsed)
						folderPane.data.refreshCollapsed(folderPane)

						if rootPanel ~= nil and not isCollapsed then
							--send the parent of the objects an expand event to collapse other areas.
							folderPane.parent:FireEvent('expand')
						end
					end,
				},
			})

	local palettePanel = gui.Panel{
		selfStyle = {
			width = 300,
			height = 'auto',
			flow = 'horizontal',
			wrap = true,
		},

		classes = {'object-drag-target'},
		dragTarget = true,
		dragTargetPriority = 0,

		children = {},
		data = {
			nodeid = nodeid, --store the node id here so it can be conveniently accessed when dragging.
		},
	}

	local newContentAlert = gui.NewContentAlertConditional("object", nodeid)

	local headerPanel = gui.Panel({
		
		bgimage = 'panels/square.png',
		classes = {'folderHeader','object-drag-target'},
		dragTarget = true,

		draggable = nodeid ~= '',
		canDragOnto = function(element, target)
			return target:HasClass('object-drag-target') and not IsObjectNodeSelfOrChildOf(element.data.nodeid, target.data.nodeid)
		end,

		data = {
			nodeid = nodeid, --store the node id here so it can be conveniently accessed when dragging.
		},

		events = {
			refreshAssets = function(element)
			end,

			drag = mod.shared.CreateDragTargetFunction(node, function(nodeid) return assets:GetObjectNode(nodeid) end, "Objects"),

			clearselection = function(element)
				element:SetClass("selected", false)
			end,

			findselected = function(element, output)
				if element:HasClass("selected") then
					output.nodeid = element.data.nodeid
				end
			end,

			--used to select a node with a given id.
			findnode = function(element, id, output)
				if element.data.nodeid == id then
					output.element = element
				end
			end,

			click = function(element)
				if options.selectfolders then
					local parentFolder = element:FindParentWithClass("foldersPanel")
					if parentFolder ~= nil then
						parentFolder:FireEventTree("clearselection")
					end
					element:SetClass("selected", true)
				end
			end,
		},

		children = {
			triangle,
			

			gui.Label({
				text = 'Object Library',
				editableOnDoubleClick = (nodeid ~= ''), --all folders except the root Object folder can be renamed.
				characterLimit = 52,
				events = {
					moduleInstalled = function(element)
						if newContentAlert ~= nil then
							if not module.HasNovelContent("object", nodeid) then
								newContentAlert:DestroySelf()
								newContentAlert = nil
							end
						else
							newContentAlert = gui.NewContentAlertConditional("object", nodeid)
							if newContentAlert ~= nil then
								element:AddChild(newContentAlert)
							end
						end
					end,
					change = function(element)
						node.description = element.text
						node:Upload()
					end,
					prepareSearch = function(element, matchingIds)
						element.text = node.description
					end,
					refreshAssets = function(element)
						element.text = node.description
					end,
					click = function()
						triangle:FireEvent('press')
					end,
				},
				selfStyle = {
					fontSize = "70%",
					width = 'auto',
					height = 'auto',
					halign = 'left',
					valign = 'center',
				},


				newContentAlert,
			}),

		},
	})

	local elements = {}

	folderPane = gui.Panel({
		selfStyle = {
			pivot = { x = 0, y = 1 },
			pad = 0,
			margin = 0,
			width = "100%",
			valign = 'top',
			flow = 'vertical',
			--height = ObjectPanelHeight,
			height = 'auto',
		},

		data = {
			node = function()
				return node
			end,

			isCollapsed = function()
				return isCollapsed
			end,

			toggleCollapsed = function(element)
				triangle:FireEvent('press')
			end,

			search = function(text, matchedParent)
				local selfMatches = matchedParent or node:MatchesSearch(text)
				matchesSearch = selfMatches or (nodeid == '') --root node always matches searches.
				for k,el in pairs(elements) do
					if el.data.search(text, selfMatches) then
						matchesSearch = true
					end
				end

				searchActive = text ~= ''

				folderPane:SetClass('collapsed', (parentCollapsed and not searchActive) or (not matchesSearch))

				triangle:SetClass('search', searchActive)

				return matchesSearch
			end,

			setParentCollapsed = function(element, newValue)
				parentCollapsed = newValue
				element:SetClass('collapsed', (parentCollapsed and not searchActive) or (not matchesSearch))
			end,

			--recursively turn search status off, for when we collapse a searched node. This doesn't globally disable
			--the search but makes us stop respecting it on this node.
			setSearchInactive = function(element)
				searchActive = false
				for k,v in pairs(elements) do
					v.data.setSearchInactive(v)
				end
			end,

			refreshCollapsed = function(element)

				if rootPanel ~= nil then
					rootPanel:SetClass('collapsed', isCollapsed)
				end

				for k,v in pairs(elements) do
					v.data.setParentCollapsed(v, isCollapsed)
				end
			end,

			SetDepth = function(element, depth)
				element.data.depth = depth
				element.x = Indent(element.data.depth)
				palettePanel.selfStyle.width = 280
			end,

			depth = 0,

			childObjectPanels = {},
		},

		events = {

			press = function(element)
				--pressing on this gets rid of the context menu.
				element.popup = nil
			end,

			rightClick = function(element)
				--create the context menu for this folder.
				local menuItems = {}
				local parentElement = element

				--Create a new folder as a child of this one.
				menuItems[#menuItems+1] = {
					text = 'Create Folder',
					click = function(element)
						local maxOrd = 0
						for i,entry in ipairs(node.children) do
							if entry.ord > maxOrd then
								maxOrd = entry.ord
							end
						end

						assets:UploadNewObjectFolder({
							description = 'New Folder',
							parentFolder = nodeid,
							ord = maxOrd+1,
						})

						parentElement.popup = nil
					end,
				}

				--Delete folder option.
				menuItems[#menuItems+1] = {
					text = 'Delete Folder',

					click = function(element)
						local CountObjectEntries = nil
						CountObjectEntries = function(n)
							local result = 0
							for i,v in ipairs(n.children) do
								if v.isfolder then
									result = result + CountObjectEntries(v)
								else
									result = result + 1
								end
							end

							return result
						end

						local numChildren = CountObjectEntries(node)

						if numChildren == 0 then
							--delete an empty folder without prompting.
							node:Delete()
						else
							local msg = string.format('Do you really want to delete %s and the %d object entries within?', node.description, numChildren)
							if numChildren == 1 then
								msg = string.format('Do you really want to delete %s and the object entry within?', node.description)
							end

							gui.ModalMessage({
								title = 'Delete Folder',
								message = msg,
								options = {
									{
										text = 'Okay',
										execute = function()
											node:Delete()
										end,
									},
									{
										text = 'Cancel',
									},
								}
							})
						end

						parentElement.popup = nil
					end,
				}


				element.popupPositioning = 'mouse'
				element.popup = gui.ContextMenu{ entries = menuItems }
			end,

			--make sure we have instanced anything matching the search.
			prepareSearch = function(element, matchingIds)
				if (not matchingIds[nodeid]) or (not refreshAssetsDirty) or (not isCollapsed) then
					return
				end

				local node = assets:GetObjectNode(nodeid)
				element:FireEvent("refreshAssets", matchingIds)
			end,

			refreshAssets = function(element, searchNodes)

				refreshAssetsDirty = isCollapsed

				node = assets:GetObjectNode(nodeid)

				if (not isCollapsed) or searchNodes ~= nil then
					local newElements = {}
					for i,v in ipairs(node.children) do
						if (not options.hideobjects) or v.isfolder then
							--if we are searching, only create the elements that match the search.
							if elements[v.id] == nil and ((not isCollapsed) or searchNodes == nil or searchNodes[v.id]) then
								newElements[v.id] = CreateObjectNode(v, folderPane, options)
								if searchNodes ~= nil then
									newElements[v.id]:FireEvent("refreshAssets")
								end
							else
								newElements[v.id] = elements[v.id]
							end

							if newElements[v.id] ~= nil then
								newElements[v.id].data.SetDepth(newElements[v.id], element.data.depth+1)
							end
						end
					end

					local newChildren = {headerPanel, rootPanel}
					local newPalette = {}

					element.data.childObjectPanels = {}

					local folderChildren = {}

					for i,v in ipairs(node.children) do
						if v.isfolder then
							folderChildren[#folderChildren+1] = newElements[v.id]
						else
							newPalette[#newPalette+1] = newElements[v.id]
							element.data.childObjectPanels[#element.data.childObjectPanels+1] = newElements[v.id]
						end
					end

					table.sort(folderChildren, function(a,b) return a.data.node().description < b.data.node().description end)
					for _,folder in ipairs(folderChildren) do
						newChildren[#newChildren+1] = folder
					end

					table.sort(newPalette, function(a,b) return a.data.node().description < b.data.node().description end)

					newChildren[#newChildren+1] = palettePanel
					palettePanel.children = newPalette

					elements = newElements

					element.children = newChildren
				end

				element.x = Indent(element.data.depth)

				element.data.refreshCollapsed(element)
			end,
		},

		children = {
			headerPanel,
			rootPanel,
			palettePanel,
		}
	})

	return folderPane

end

CreateObjectNode = function(node, parentElement, options)

	if node.isfolder then
		return CreateObjectFolder(node.id, parentElement, options)
	else
		return CreateObjectEntry(node.id, parentElement, options)
	end
end

local CreateObjectInstanceChildPanel
local function CreateObjectInstanceView(nodeid, rootPanel)

	local m_obj = rootPanel.data.objects[nodeid]
	local node = assets:GetObjectNode(m_obj.assetid)
	if node == nil then
		return nil
	end

	local resultPanel

	local childPanel

	local triangle

	local label = gui.Label{
		text = m_obj.description,
	}

	local headingPanel = gui.Panel{
		classes = {"folderHeader", "objectInstance"},
		bgimage = "panels/square.png",

		dragTarget = true,

		data = {

			GetDragParent = function()
				return nodeid
			end,
			GetTargetZ = function()
				return 1
			end,
		},

		hover = function(element)
			m_obj.editorFocus = true
		end,

		dehover = function(element)
			m_obj.editorFocus = false
		end,

		rightClick = function(element)
			local entries = {}
			entries[#entries+1] = {
				text = "Delete Object",
				click = function()
					m_obj:Destroy()
				end,
			}

			element.popup = gui.ContextMenu{ entries = entries }
		end,

		click = function(element)
			local status = not m_obj.editorSelection
			if (not dmhub.modKeys.shift) and (not dmhub.modKeys.ctrl) then
				dmhub.ClearSelectedObjects()
			end

			if status and dmhub.modKeys.shift then
				local siblings = resultPanel.parent.children
				local beginIndex = nil
				local endIndex = nil
				local ourIndex = nil
				local found = false
				for i,sibling in ipairs(siblings) do
					printf("SIBLING:: %d -> %s", i, json(sibling.data.selected()))
					if sibling == resultPanel then
						ourIndex = i
						found = true
					elseif found == false then
						if sibling.data.selected() then
							beginIndex = i
						end
					else
						if sibling.data.selected() then
							endIndex = i
							break
						end
					end
				end

				printf("SIBLING:: BEGIN = %s; END = %s; OUR = %s", json(beginIndex), json(endIndex), json(ourIndex))

				if ourIndex ~= nil and beginIndex ~= nil then
					for i=beginIndex,ourIndex do
						siblings[i]:FireEvent("select", true)
					end
				end

				if ourIndex ~= nil and endIndex ~= nil then
					for i=ourIndex,endIndex do
						siblings[i]:FireEvent("select", true)
					end
				end
			end

			resultPanel:FireEvent("select", status)
		end,

		refreshHighlights = function(element)
			if triangle ~= nil then
				triangle:SetClass("drilldownFocus", m_obj.childEditorFocus)
				triangle:SetClass("drilldownSelect", m_obj.childEditorSelection)
			end

			element:SetClass("focus", m_obj.editorFocus)
			element:SetClass("selected", m_obj.editorSelection)
			label:SetClass("selected", m_obj.editorSelection)

		end,

		gui.Panel{
			classes = {"objectIcon"},

			gui.Panel{
				bgimageStreamed = m_obj.assetid,

				selfStyle = gui.Style{
					bgcolor = 'white',
					halign = 'center',
					valign = 'center',
					width = '100%',
					height = '100%',
					hueshift = node.hue,
					saturation = node.saturation,
					brightness = node.brightness,
				},

				events = {
					imageLoaded = function(element)
						local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
						if maxDim > 0 then
							local xratio = element.bgsprite.dimensions.x/maxDim
							local yratio = element.bgsprite.dimensions.y/maxDim
							element.selfStyle.width = tostring(xratio*100) .. '%'
							element.selfStyle.height = tostring(yratio*100) .. '%'
						end
					end,
				},
			},
		},
		label,
	}

	local dragBelowPanel = gui.Panel{
		classes = {"dragBelowPanel", "objectInstance"},
		bgimage = "panels/square.png",
		dragTarget = true,
		data = {
			GetDragParent = function()
				return m_obj.parentid
			end,
			GetTargetZ = function()
				return m_obj.zorder + 1
			end,
		},
	}

	resultPanel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",

		draggable = true,

		data = {
			obj = function()
				return m_obj
			end,

			selected = function()
				return m_obj.editorSelection
			end,

			canDragOnto = function(element, target)
				if target ~= nil and target:HasClass("objectInstance") then
					local t = target
					local count = 0
					while t ~= nil and count < 100 do
						if t == resultPanel then
							return false
						end
						t = t.parent
						count = count+1
					end

					return true
				end

				return false
			end,
		},

		select = function(element, status)
			m_obj.editorSelection = status
		end,


		refreshObjectInstances = function(element)
			label.text = string.format("%s -- %s", m_obj.description, json(m_obj.zorder))

			if dmhub.GetSettingValue("dev") then
				label.text = string.format("%s %s", string.sub(m_obj.id, 1, 8), label.text)
			end


			local childids = m_obj.childids
			if childids ~= nil and triangle == nil then
				triangle = gui.Panel{
					bgimage = 'panels/triangle.png',
					classes = {"triangle"},

					styles =
					{
						{
							rotate = 90,
						},
						{
							selectors = {'expanded'},
							transitionTime = 0.2,
							rotate = 0,
						},
					},

					press = function(element)
						element:SetClass("expanded", not element:HasClass("expanded"))

						if childPanel == nil then
							childPanel = CreateObjectInstanceChildPanel(rootPanel, nodeid)
							resultPanel:AddChild(childPanel)
						end

						childPanel:SetClass("collapsed", not element:HasClass("expanded"))
						if childPanel:HasClass("collapsed") == false then
							childPanel:FireEventTree("refreshObjectInstances")
							childPanel:FireEventTree("refreshHighlights")
						end
					end,
				}

				local headingChildren = headingPanel.children
				table.insert(headingChildren, 1, triangle)
				headingPanel.children = headingChildren
			elseif childids == nil and triangle ~= nil then
				triangle:DestroySelf()
				triangle = nil
			end
		end,

		canDragOnto = function(element, target)
			return element.data.canDragOnto(element, target)
		end,

		drag = function(element, target)
			if target == nil then
				return
			end
			
			local draggableObjects = {}
			local nodeidSet = {}
			rootPanel:FireEventTree("accumulateDraggable", element, target, draggableObjects, nodeidSet)

			table.sort(draggableObjects, function(a, b) return a.zorder < b.zorder end)

			printf("DRAGGABLE:: %d", #draggableObjects)

			local zorder = target.data.GetTargetZ()
			for i,obj in ipairs(draggableObjects) do
				obj.parentid = target.data.GetDragParent()
				obj.zorder = zorder+(i-1)
				printf("DRAGGABLE:: SET %d -> %d", i, zorder-(i-1))
				obj:Upload()
			end

			for k,v in pairs(rootPanel.data.objects) do

				if nodeidSet[k] == nil and v.parentid == target.data.GetDragParent() and v.zorder >= zorder then
					v:SetAndUploadZOrder(v.zorder+#draggableObjects)
				end
			end

			rootPanel:FireEventTree("refreshObjectInstances")
		end,

		accumulateDraggable = function(element, dragged, target, draggableObjects, nodeidSet)
			if element == dragged or (element.data.selected() and element.data.canDragOnto(element, target)) then
				draggableObjects[#draggableObjects+1] = element.data.obj()
				nodeidSet[nodeid] = true
			end
		end,

		headingPanel,
		dragBelowPanel,
	}

	return resultPanel
end

CreateObjectInstanceChildPanel = function(rootPanel, objid)

	local m_children = {}

	local resultPanel

	resultPanel = gui.Panel{
		width = "100%-8",
		height = "auto",
		flow = "vertical",
		x = 16,
		refreshObjectInstances = function(element)
			local objectMap = rootPanel.data.objects
			local childMap = {}
			local children = {}

			if objid == nil then
				for k,v in pairs(objectMap) do
					if v.parentid == "" then
						childMap[k] = m_children[k] or CreateObjectInstanceView(k, rootPanel)
						if childMap[k] ~= nil then
							childMap[k].data.ord = v.zorder
							children[#children+1] = childMap[k]
						end
					end
				end
			else
				local obj = objectMap[objid]
				if obj ~= nil then
					local childids = obj.childids
					if childids ~= nil then
						for _,k in ipairs(childids) do
							local v = objectMap[k]
							if v ~= nil then
								childMap[k] = m_children[k] or CreateObjectInstanceView(k, rootPanel)
								if childMap[k] ~= nil then
									childMap[k].data.ord = v.zorder
									children[#children+1] = childMap[k]
								end
							end
						end
					end
				end
			end

			m_children = childMap

			table.sort(children, function(a,b) return a.data.ord < b.data.ord end)
			element.children = children
		end,
	}

	return resultPanel
end

local function CreateObjectInstanceHierarchy()
	local resultPanel

	local m_currentFloorId = nil
	local bodyPanel = nil

	local triangle = nil
	triangle = gui.Panel{

				bgimage = 'panels/triangle.png',
				classes = {"triangle"},

				styles =
				{
					{
						rotate = 90,
					},
					{
						selectors = {'expanded'},
						transitionTime = 0.2,
						rotate = 0,
					},
				},

				events = {
					create = function(element)
					end,
					refreshAssets = function(element)
					end,
					refreshCollapse = function(element)
					end,
					press = function(element)
						element:SetClass("expanded", not element:HasClass("expanded"))

						if bodyPanel == nil then
							bodyPanel = gui.Panel{
								width = "100%",
								height = "auto",

								create = function(element)
									element.data.eventid = dmhub.RegisterEventHandler("ChangeSelectedObjects", function()
										if element:HasClass("collapsed") then
											return
										end

										element:FireEventTreeVisible("refreshHighlights")
									end)
								end,

								destroy = function(element)
									dmhub.DeregisterEventHandler(element.data.eventid)
								end,

								monitorGame = string.format("/mapFloors/%s/objects", game.currentFloorId),

								refreshGame = function(element)
									element:FireEventTreeVisible("refreshObjectInstances")
								end,

								thinkTime = 0.3,
								think = function(element)
									if bodyPanel:HasClass("collapsed") then
										return
									end

									if m_currentFloorId ~= game.currentFloorId then
										element.monitorGame = string.format("/mapFloors/%s/objects", game.currentFloorId)
										bodyPanel:FireEventTreeVisible("refreshObjectInstances")
									end
								end,

								refreshObjectInstances = function(element)
									if bodyPanel:HasClass("collapsed") then
										return
									end

									m_currentFloorId = game.currentFloorId

									element.data.objects = game.currentFloor.objects
								end,

								data = {
									objects = {},
								},

							}

							bodyPanel:AddChild(CreateObjectInstanceChildPanel(bodyPanel))
							resultPanel:AddChild(bodyPanel)
						end

						bodyPanel:SetClass("collapsed", not element:HasClass("expanded"))

						bodyPanel:FireEventTree("refreshObjectInstances")
						bodyPanel:FireEventTreeVisible("refreshHighlights")
					end,
				},
			}


	local headingPanel = gui.Panel{
		classes = {"folderHeader"},
		bgimage = 'panels/square.png',
		triangle,
		gui.Label{
			text = "Objects on current floor",
		},
	}

	resultPanel = gui.Panel{
		styles = {
			{
				selectors = {"triangle"},
				halign = 'left',
				valign = 'center',
				margin = 5,
			},
			{
				selectors = {"triangle", "drilldownFocus"},
				transitionTime = 0.1,
				bgcolor = "white",
			},
			{
				selectors = {"triangle", "drilldownSelect"},
				transitionTime = 0.1,
				bgcolor = "white",
				brightness = 1.5,
			},
			{
				selectors = {"triangle", "hover"},
				transitionTime = 0.1,
				bgcolor = 'yellow',
			},
			{
				selectors = {"objectPanel"},
				bgimage = "panels/square.png",
				bgcolor = "clear",
				flow = "horizontal",
				height = 24,
				width = 300,
			},
			{
				selectors = {"objectPanel", "selected"},
				bgcolor = "#ffffff44",
			},
			{
				selectors = {"objectPanel", "focus"},
				bgcolor = "#ffffff44",
			},
			{
				selectors = {"objectPanel", "drag-target"},
				bgcolor = "#ffff8866",
			},
			{
				selectors = {"objectPanel", "drag-target-hover"},
				bgcolor = "#ffff8888",
			},
			{
				selectors = {"objectIcon"},
				width = 24,
				height = 24,
			},
			{
				selectors = {"label"},
				fontSize = 14,
				width = "auto",
				height = "auto",
				maxWidth = 260,
				halign = "left",
				valign = "center",
				hmargin = 8,
			},
		},

		width = "100%",
		height = "auto",
		flow = "vertical",

		headingPanel,
	}

	return resultPanel
end

local m_objectEditor = nil

mod.shared.CreateObjectEditor = function(options)
	options = options or {}
	local objectInstances = nil
	if (not options.noinstances) then
		objectInstances = CreateObjectInstanceHierarchy()
	end
	local folderPanel = CreateObjectFolder('', nil, options)
	local resultPanel = gui.Panel{
		id = "object-editor",
		interactable = false,
		selfStyle = {
			width = '100%',
			height = 'auto',
			valign = 'top',
			flow = 'vertical',
		},
		styles = {
			{
				selectors = {"label"},
				fontSize = 18,
				color = Styles.textColor,
			},
			{
				selectors = {"label", "parent:hover"},
				color = "black",
			},
			{
				selectors = {"label", "parent:selected"},
				color = "black",
			},
			{
				selectors = {"label", "parent:drag-target"},
				color = "black",
			},

			{
				selectors = {"folderHeader"},
				valign = 'top',
				halign = 'left',
				width = "100%",
				height = ObjectPanelHeight,
				flow = 'horizontal',
				bgcolor = "clear",
				borderWidth = 0,
			},
			{
				selectors = {'folderHeader','hover'},
				bgcolor = Styles.textColor,
			},

			{
				selectors = {"folderHeader", "selected"},
				bgcolor = Styles.textColor,
			},

			{
				selectors = {'folderHeader','drag-target'},
				bgcolor = Styles.textColor,
				transitionTime = 0.2,
			},
			{
				selectors = {'folderHeader','drag-target-hover'},
				brightness = 1.5,
				transitionTime = 0.2,
			},


			{
				selectors = {"triangle"},
				bgcolor = Styles.textColor,
				width = 8,
				height = 8,
				halign = 'left',
				valign = 'center',
				margin = 5,
				rotate = 90,
			},
			{
				selectors = {"triangle",'empty'},
				bgcolor = 'grey',
			},
			{
				selectors = {"triangle", "parent:hover"},
				bgcolor = "black",
			},
			{
				selectors = {"triangle", "parent:selected"},
				bgcolor = "black",
			},
			{
				selectors = {"triangle", "parent:drag-target"},
				bgcolor = "black",
			},
			{
				selectors = {"triangle",'hover'},
				transitionTime = 0.1,
				bgcolor = 'yellow',
			},
			{
				selectors = {"dragBelowPanel"},
				width = 300,
				height = 1,
				bgcolor = "clear",
			},
			{
				selectors = {"dragBelowPanel", "drag-target"},
				bgcolor = "#bbbbbb",
			},
			{
				selectors = {"dragBelowPanel", "drag-target-hover"},
				bgcolor = "white",
				brightness = 1.5,
			},
		},
		monitorAssets = "objects",

		children = {objectInstances, folderPanel},
 
		refreshAssets = function(element)
			for _,child in ipairs(element.children) do
				child:FireEventTree("refreshAssets")
			end
		end,

		press = function(element)
			if not gui.ChildHasFocus(element) then
				gui.SetFocus(element)
			end
		end,

        childfocus = function(element)
			local dockablePanel = element:FindParentWithClass("dockablePanel")
			if dockablePanel ~= nil then
            	dockablePanel:SetClass("highlightPanel", true)
			end
        end,

        childdefocus = function(element, focusInfo)
			local dockablePanel = element:FindParentWithClass("dockablePanel")
			if dockablePanel ~= nil then
            	dockablePanel:SetClass("highlightPanel", false)
			end

			if focusInfo.oldFocus ~= element and focusInfo.newFocus == nil and (not dmhub.KeyPressed("escape")) then
				focusInfo.newFocus = element
			end
        end,

        clickpanel = function(element)
            element:FireEvent("showpanel")
        end,

        showpanel = function(element)
            if not gui.ChildHasFocus(element) then
                gui.SetFocus(element)
            end
        end,

        hidepanel = function(element)
            if gui.ChildHasFocus(element) then
				gui.SetFocus(element) --focus here first.
                gui.SetFocus(nil)
            end
        end,

		destroy = function(element)
			if m_objectEditor == element then
				m_objectEditor = nil
			end
		end,
	}

	resultPanel:FireEventTree("refreshAssets")

	if not options.temporary then
		m_objectEditor = resultPanel
	end

	return resultPanel
end

dmhub.CancelEditing = function()
	--if dmhub.ObjectEditingEnabled() and dmhub.GetSelectedObject() ~= nil and gui.GetFocus() ~= nil then
	if dmhub.GetSelectedObject() ~= nil and gui.GetFocus() ~= nil then
		gui.SetFocus(gui.GetFocus():Get("object-editor"))
		ClearSelectedObjectEntries()
		return true
	end

	return false
end

dmhub.GetSelectedObject = function()
	if gui.GetFocus() == nil then
		return nil
	end

	return gui.GetFocus().data.objectid
end

dmhub.ObjectEditingEnabled = function()
	if m_objectEditor == nil or (not m_objectEditor.valid) then
		return false
	end
	if m_objectEditor:FindParentWithClass("dockablePanel") == nil then
		return false
	end

	if gui.ChildHasFocus(m_objectEditor) then
		m_objectEditor:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", true)
		return true
	end

	--attempt to index nil setclass.
	m_objectEditor:FindParentWithClass("dockablePanel"):SetClass("highlightPanel", false)
	return false


end