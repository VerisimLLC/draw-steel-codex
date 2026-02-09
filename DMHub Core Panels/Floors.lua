local mod = dmhub.GetModLoading()

local CreateLayersPanel

DockablePanel.Register{
	name = "Floors & Layers",
	icon = "icons/standard/Icon_App_FloorsLayers.png",
	minHeight = 100,
	vscroll = false,
	dmonly = true,
	content = function()
		return CreateLayersPanel()
	end,
}

local function ShowFloorSettings(floor)

	local shadowCastOptions = {
		{
			id = 'this',
			text = "Cast Shadows",
		},
		{
			id = 'none',
			text = 'No Shadows',
		},
	}

	for i,floorInfo in ipairs(game.currentMap.floors) do
		if floorInfo.floorid ~= floor.floorid then
			shadowCastOptions[#shadowCastOptions+1] =
			{
				id = floorInfo.floorid,
				text = string.format('Cast Shadows Onto %s', floorInfo.description),
			}
		end
	end

	local dialogPanelRoofLayerOptions = gui.Panel{
				width = 500,
				height = "auto",
				flow = "vertical",
				bgimage = "panels/square.png",

				classes = cond(floor.roof, nil, 'collapsed'),

				gui.Check{
					text = "Hide roof when players are inside",
					value = not floor.roofShowWhenInside,
					style = {
						height = 20,
						width = '40%',
						fontSize = 18,
					},
					events = {
						change = function(element)
							floor.roofShowWhenInside = not element.value
						end,
						linger = gui.Tooltip("This layer will be hidden when players are inside."),
					},
				},

				gui.Panel{
					classes = {"formPanel"},
					flow = "horizontal",
					width = "auto",
					height = "auto",
					gui.Label{
						text = "Vision Multiplier:",
						color = 'white',
						width = '50%',
						height = 'auto',
						fontSize = 18,
						linger = gui.Tooltip("The vision multiplier allows players to see further on the roof layer than they can on other layers."),
					},

					gui.Slider{
						style = {
							height = 20,
							width = 200,
							valign = "center",
							fontSize = 14,
						},
						sliderWidth = 140,
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
					classes = {"formPanel"},
					flow = "horizontal",
					width = "auto",
					height = "auto",
					gui.Label{
						text = "Roof Cutaway Radius:",
						color = 'white',
						width = '50%',
						height = 'auto',
						fontSize = 18,
						linger = gui.Tooltip("The cutaway radius is the distance to which we prefer to show the radius the player is on if they have vision of it instead of the roof layer. For roofs of buildings you most likely want this to be 100%, but for tree foliage you might want it lower than 100%. The lower it is the more elements on the roof layer will occlude vision."),
					},

					gui.Slider{
						style = {
							height = 20,
							width = 200,
							valign = "center",
							fontSize = 14,
						},
						sliderWidth = 140,
						minValue = 0.0,
						maxValue = 1.0,
						labelWidth = 60,
						labelFormat = "rawpercent",
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
					classes = {"formPanel"},
					flow = "horizontal",
					width = "auto",
					height = "auto",
					gui.Label{
						text = "Roof Cutaway Fade:",
						color = 'white',
						width = '50%',
						height = 'auto',
						fontSize = 18,
						linger = gui.Tooltip("The roof cutaway fade controls how quickly vision fades from showing the layer the player is on to the roof layer."),
					},

					gui.Slider{
						style = {
							height = 20,
							width = 200,
							valign = "center",
							fontSize = 14,
						},
						sliderWidth = 140,
						labelFormat = "rawpercent",
						minValue = 0.0,
						maxValue = 1.0,
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
					classes = {"formPanel"},
					flow = "horizontal",
					width = "auto",
					height = "auto",
					gui.Label{
						text = "Roof Minimum Opacity:",
						color = 'white',
						width = '50%',
						height = 'auto',
						fontSize = 18,
						linger = gui.Tooltip("The minimum opacity that the roof layer will have when it is cut away to show the layer the player is on."),
					},

					gui.Slider{
						style = {
							height = 20,
							width = 200,
							valign = "center",
							fontSize = 14,
						},
						sliderWidth = 140,
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

	local dialogPanel = gui.Panel{
		classes = {'framedPanel'},
		width = 1000,
		height = 800,
		styles = {
			Styles.Panel,
		},

		gui.Panel{
			vscroll = true,
			halign = 'center',
			valign = 'top',
			vmargin = 20,
			flow = 'vertical',
			width = 600,
			height = 600,

			styles = {
				{
					valign = "top",
				},
				{
					selectors = {"formPanel"},
					vmargin = 4,
				},
			},

			gui.Panel{
				valign = 'top',
				flow = 'horizontal',
				width = '100%',
				height = 40,

				gui.Label{
					text = "Name:",
					width = "auto",
					height = "auto",
					color = "white",
					fontSize = 18,
				},

				gui.Input{
					width = 180,
					height = 24,
					fontSize = 18,
					text = floor.description,
					change = function(element)
						floor.description = element.text
					end,
				},
			},

			gui.Check{
				text = "Roof Layer",
				value = floor.roof,
				style = {
					height = 20,
					width = '40%',
					fontSize = 18,
				},
				events = {
					change = function(element)
						floor.roof = element.value
						dialogPanelRoofLayerOptions:SetClass('collapsed', not floor.roof)
					end,
					linger = gui.Tooltip("A roof layer will be displayed for players who are on a floor beneath it. It will only be displayed in areas they can't see."),
				},
			},

			dialogPanelRoofLayerOptions,

		},

		gui.Panel{
			classes = {'modal-button-panel'},

			gui.PrettyButton{
				text = 'Close',
				escapeActivates = true,
				escapePriority = EscapePriority.EXIT_DIALOG,
				style = {
					width = 140,
					height = 60,
					halign = 'right',
					fontSize = 36,
				},
				events = {
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
		classes = {"floorOrLayerDragTarget", string.format('%sDragTarget', layerType)},
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
		gui.AddButton{
			halign = 'center',
			valign = 'top',
			width = 20,
			height = 20,
			vmargin = 2,
			click = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Add New Floor",
                            click = function()
                                element.popup = nil
                                game.currentMap:CreateFloor()
                            end,
                        },
                    }
                }
			end,
			hover = gui.Tooltip("Add a new floor"),
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
						text = "Ground",
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
								width = 44,
								height = 20,
								halign = "left",
								fontSize = 11,
                                minFontSize = 8,
								elevation = function(element, amount)
									element.text = MeasurementSystem.NativeToDisplayUnits(amount*dmhub.unitsPerSquare)
								end,
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

							gui.Panel{
								classes = {'settingsButton'},
								floating = true,
								click = function(element)
									mod.shared.CreateLayersDisplay()
								end,
							},

							data = {
								floorLabel = floorLabel,
								layersPanel = layersPanel,
							},

							rightClick = function(element)
								if #currentMap.floorsWithoutLayers > 1 then
									element.popup = gui.ContextMenu{
										entries = {
											{
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
											},
										}
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

	local highlightGradient = core.Gradient{
		point_a = { x = 0, y = 0 },
		point_b = { x = 1, y = 0 },
		stops = {
			{
				position = 0,
				color = 'srgb:#C0957100',
			},
			{
				position = 0.6,
				color = 'srgb:#C09571BB',
			},
			{
				position = 1.0,
				color = 'srgb:#C0957100',
			},
		},
	}


	local aspect = (dmhub.screenDimensionsBelowTitlebar.y/dmhub.screenDimensions.x) / (1080/1920)
	local resultPanel = gui.Panel{
		width = "100%",
		height = "100%",
		flow = 'vertical',

		styles = {
			Styles.Panel,

			{
				selectors = {'settingsButton'},
				bgimage = 'ui-icons/skills/98.png',
				bgcolor = 'white',
				height = '30%',
				width = '100% height',
				blend = 'add',
				brightness = 0.7,
				halign = 'right',
				valign = 'top',
			},
			{
				selectors = {'settingsButton','hover'},
				brightness = 1.0,
				scale = 1.1,
			},
			{
				selectors = {'settingsButton','press'},
				brightness = 0.9,
			},
			{
				selectors = {'floorOrLayerDragTarget'},
				bgimage = 'panels/square.png',
				bgcolor = '#00000077',
				height = 2,
				width = '100%',
			},
			{
				selectors = {'floorOrLayerDragTarget', 'drag-target'},
				bgcolor = '#ffffff77',
			},
			{
				selectors = {'floorOrLayerDragTarget', 'drag-target-hover'},
				bgcolor = '#ffff00aa',
			},
			{
				selectors = {'floorPanel'},
				flow = "horizontal",
				bgimage = 'panels/square.png',
				bgcolor = '#00000077',
				halign = "left",
				hmargin = 8,
				height = 40,
				width = '92%',
				fontSize = 16,
				color = 'white',
			},
			{
				selectors = {'floorPanel', 'selected'},
				bgcolor = "white",
				gradient = highlightGradient,

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
				bgcolor = "#ffffff55",
			},
			{
				selectors = {'floorOptionIcon', 'enabled'},
				bgcolor = "white",
			},
			{
				selectors = {'floorPanelMinimap'},
				bgimage = "panels/square.png",
				bgcolor = "black",
				borderColor = Styles.textColor,
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
				color = Styles.textColor,
				hmargin = 6,
				valign = "top",
				halign = "left",
				height = "auto",
				width = "auto",
			},
			{
				selectors = {'floorLabel', 'selected'},
				color = "black",

			},
		},

		floorsList,

	}

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

							gui.Panel{
								classes = {'settingsButton'},
								floating = true,
								click = function(element)
		mod.shared.CreateLayersDisplay()
			--						ShowFloorSettings(floor)
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

		gui.AddButton{
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