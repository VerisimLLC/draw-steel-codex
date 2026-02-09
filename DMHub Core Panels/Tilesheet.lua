local mod = dmhub.GetModLoading()

mod.shared.assetsCreated = {}

mod.shared.CreateTerrainAssetFromPath = function(assetType, path) --assetType is 'terrain', 'floor', or 'effects'.
	dmhub.Debug(string.format("CREATE ASSET: %s", path))
	local confirmUpload = false
	local uploadDialog = nil
	local operation
	local assetid = assets:CreateTilesheetFromFile{
		floor = (assetType == 'floor'),
		effects = (assetType == 'effects'),
		path = path,
		args = {
			useAlphaThreshold = (path == '#EffectTexture'),
		},
		error = function(text)
			gui.ModalMessage{
				title = 'Error creating tilesheet',
				message = text,
			}
		end,
		upload = function(tileid)
			if operation ~= nil then
				operation.progress = 1
			end
		end,
		progress = function(percent)
			if uploadDialog ~= nil and uploadDialog.valid then
				dmhub.Debug(string.format("PERCENT:: %f", percent))
				operation.progress = percent
			end
		end,
	}

	if assetid ~= nil then
		operation = dmhub.CreateNetworkOperation()
		operation.description = "Uploading Tilesheet..."
		operation.status = "Uploading..."
		operation.progress = 0.0
		mod.shared.assetsCreated[assetid] = true
	end
end

mod.shared.CreateTerrainAsset = function(assetType) --assetType is 'terrain', 'floor', or 'effects'.
	dmhub.OpenFileDialog{
		id = "TerrainSheet",
		extensions = {"jpeg", "jpg", "png", "webm", "webp", "mp4"},
		multiFiles = true,
		prompt = string.format("Choose image or video to use for %s", assetType),
		open = function(path)
			mod.shared.CreateTerrainAssetFromPath(assetType, path)

		end,
	}
end

mod.shared.DuplicateTilesheetAsset = function(tileid)
	assets:DuplicateTilesheet(tileid)
end

mod.shared.DuplicateWallAsset = function(tileid)
	assets:DuplicateWall(tileid)
end

mod.shared.EditTilesheetAssetDialog = function(tileid, startingValues)

	dmhub.Debug('TILESHEET ASSET: ' .. tileid)
	local asset = assets.tilesheets[tileid]

	if not asset.loaded then
		--the asset does not have its image loaded so we wait until it does before showing this dialog.
		dmhub.Schedule(0.1, function() mod.shared.EditTilesheetAssetDialog(tileid, startingValues) end)
		return
	end

	local undoValues = DeepCopy(startingValues or {})

	if undoValues.brightness == nil then
		undoValues.brightness = asset.brightness
	end

	if undoValues.saturation == nil then
		undoValues.saturation = asset.saturation
	end

	if undoValues.hueshift == nil then
		undoValues.hueshift = asset.hueshift
	end

	if undoValues.contrast == nil then
		undoValues.contrast = asset.contrast
	end

	if undoValues.scale == nil then
		undoValues.scale = asset.scale
	end

	if undoValues.effectLayer == nil then
		undoValues.effectLayer = asset.effectLayer
	end

	if undoValues.oneLargeTile == nil then
		undoValues.oneLargeTile = asset.oneLargeTile
	end

	if undoValues.useAlphaThreshold == nil then
		undoValues.useAlphaThreshold = asset.useAlphaThreshold
	end

	if undoValues.water == nil then
		undoValues.water = asset.rules.water
	end

	if undoValues.difficultTerrain == nil then
		undoValues.difficultTerrain = asset.rules.difficultTerrain
	end

	if undoValues.movement == nil then
		undoValues.movement = asset.movement
	end

	if undoValues.distortion == nil then
		undoValues.distortion = asset.distortion
	end

	if asset == nil then
		dmhub.Debug('ASSET IS NIL')
	end

	local buttonPanel = gui.Panel{
		id = 'BottomButtons',
		style = {
			width = '90%',
			height = 100,
			margin = 8,
			bgcolor = 'white',
			valign = 'bottom',
			halign = 'center',
			flow = 'horizontal',
		},

		children = {
			gui.PrettyButton{
				text = 'Save & Close',
				width = 200,
				height = 80,

				events = {
					click = function(element)
						gui.CloseModal()
						asset:Upload()
					end,
				}
			},
		}
	}


	local previewFloor = nil

	local imageDim = 512
	local imagePanel = gui.Panel{
		id = 'tile-image',
		width = imageDim,
		height = imageDim,
		cornerRadius = 12,
		bgcolor = "white",
		halign = "right",
		valign = "top",
		margin = 8,

		create = function(element)
            previewFloor = game.currentMap:CreatePreviewFloor()
            previewFloor.cameraWidth = 1024
            previewFloor.cameraHeight = 1024
            previewFloor.cameraPos = {x = 0, y = 0}
			previewFloor.cameraSize = 4

            game.Refresh{
                currentMap = true,
                floors = {previewFloor.floorid},
            }

			previewFloor:ExecuteRectangleOperation{
				rect = {x1 = -10, y1 = -10, x2 = 10, y2 = 10},
				layer = cond(asset.isfloor, "Floor", "Ground"),
				tileid = tileid,
				wallid = nil,
				walls = false,
				floor = true,
			}

			element.bgimage = previewFloor.textureid

		end,

		destroy = function(element)
			if previewFloor ~= nil then
				game.currentMap:DestroyPreviewFloor(previewFloor)
				previewFloor = nil
			end
		end,
	}

	local tilesheetStyleDropdown = nil
	local tilesheetDimensionsWarning = nil
	local randomOrientationCheck = nil
	local effectLayerDropdown = nil
	local effectAlphaThresholdDropdown = nil
	
	if asset.isfloor then

		local tilesheetTypeChosen = "onelarge"
		if asset.oneLargeTile == false then
			tilesheetTypeChosen = "tilesheet"
		end

		local calculateOrientationVisibility = function()
			randomOrientationCheck:SetClass('hidden', asset.oneLargeTile)
		end

		tilesheetStyleDropdown = gui.Panel{
			classes = {"formPanel"},

			children = {
				gui.Label{
					text = 'Tiling:',
					classes = {"formLabel"},
				},

				gui.Dropdown{
					classes = {"formDropdown"},
					options = {
						{
							id = "onelarge",
							text = "One Large Tile",
						},
						{
							id = "tilesheet",
							text = "Tilesheet",
						}
					},
					idChosen = tilesheetTypeChosen,

					events = {
						change = function(element)
							asset.oneLargeTile = (element.idChosen == "onelarge")
							assets:RefreshAssets("Tilesheet")
							calculateOrientationVisibility()
						end,
					},
				},

			}
		}

		tilesheetDimensionsWarning = gui.Label{
			text = 'Warning: It is recommended to use a square image when using "One Large Tile" mode.',
			classes = {'collapsed'},
			style = {
				width = 400,
				height = 'auto',
				fontSize = '50%',
				color = 'red',
			},
			events = {
				create = function(element)
					element:FireEvent('refreshAssets')
				end,
				refreshAssets = function(element)
					element:SetClass('collapsed', asset.oneLargeTile == false or (asset.width == asset.height))
				end,
			}
		}

		randomOrientationCheck = gui.Check{
			value = asset.randomOrientation,
			text = "Randomize Tile Orientation",
			style = {
				width = '70%',
				height = 48,
				flow = 'horizontal',
				fontSize = '60%',
				borderWidth = 0,
			},
			events = {
				change = function(element)
					asset.randomOrientation = element.value
					assets:RefreshAssets("Tilesheet")
				end,
			},
		}

		calculateOrientationVisibility()

	end

	if asset.iseffect then

		--should match EffectTileLayer enum.
		local effectLayers = {
			{ id = "Ground", text = "Above Terrain" },
			{ id = "Floor", text = "Above Floors" },
			{ id = "Walls", text = "Above Walls" },
			{ id = "Objects", text = "Above Objects" },
			{ id = "Tokens", text = "Above Creatures" },
		}

		effectLayerDropdown = gui.Panel{
			style = {
				width = '40%',
				height = 48,
				flow = 'horizontal',
				fontSize = '60%',
				borderWidth = 0,
			},

			children = {
				gui.Label{
					text = 'Layer:',
					classes = {"formLabel"},
				},

				gui.Dropdown{
					classes = {"formDropdown"},
					options = effectLayers,
					idChosen = asset.effectLayer,

					events = {
						change = function(element)
							asset.effectLayer = element.idChosen
							assets:RefreshAssets("Tilesheet")
						end,
					},
				},

			}
		}

		effectAlphaThresholdDropdown = gui.Panel{
			classes = {"formPanel"},

			children = {
				gui.Label{
					text = 'Alpha:',
					classes = {"formLabel"},
				},

				gui.Dropdown{
					options = { { id = 'blend', text = 'Blend' }, { id = 'threshold', text = 'Threshold' } },
					idChosen = cond(asset.useAlphaThreshold, 'threshold', 'blend'),
					classes = {"formDropdown"},

					events = {
						change = function(element)
							asset.useAlphaThreshold = cond(element.idChosen == 'blend', false, true)
							assets:RefreshAssets("Tilesheet")
						end,
					},
				},

			}
		}
	end

	local waterCheck
	local difficultCheck
	local distortionPanel
	local movementPanel
    local surfaceTypePanel

	waterCheck = gui.Check{
		value = asset.rules.water,
		text = "Is Water",
		style = {
			width = '70%',
			height = 48,
			flow = 'horizontal',
			fontSize = '60%',
			borderWidth = 0,
		},
		events = {
			change = function(element)
				asset.rules.water = element.value
				assets:RefreshAssets("Tilesheet")
			end,
		},
	}

	difficultCheck = gui.Check{
		value = asset.rules.difficultTerrain,
		text = "Difficult Terrain",
		style = {
			width = '70%',
			height = 48,
			flow = 'horizontal',
			fontSize = '60%',
			borderWidth = 0,
		},
		events = {
			change = function(element)
				asset.rules.difficultTerrain = element.value
				assets:RefreshAssets("Tilesheet")
			end,
		},
	}

	local distortionProperties = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",

		create = function(element)
			element:FireEvent("refreshHidden")
		end,
		
		refreshHidden = function(element)
			element:SetClass("collapsed", not asset.distortion)
		end,

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Horizontal:",
				classes = {"formLabel"},
			},
			gui.Slider{
				value = asset.distortx,
				unclamped = true,
				minValue = 0,
				maxValue = 1,
				sliderWidth = 300,
				labelWidth = 60,
				labelFormat = "percent",
				change = function(element)
					asset.distortx = element.value
					assets:RefreshAssets("Tilesheet")
				end,
				confirm = function(element)
					asset.distortx = element.value
					assets:RefreshAssets("Tilesheet")
				end,

				style = {
					fontSize = '80%',
					valign = 'center',
					halign = 'right',
					height = '50%',
					width = '100%',
					borderWidth = 0,
				},

			},
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Vertical:",
				classes = {"formLabel"},
			},
			gui.Slider{
				value = asset.distorty,
				unclamped = true,
				minValue = 0,
				maxValue = 1,
				sliderWidth = 300,
				labelWidth = 60,
				labelFormat = "percent",
				change = function(element)
					asset.distorty = element.value
					assets:RefreshAssets("Tilesheet")
				end,
				confirm = function(element)
					asset.distorty = element.value
					assets:RefreshAssets("Tilesheet")
				end,

				style = {
					fontSize = '80%',
					valign = 'center',
					halign = 'right',
					height = '50%',
					width = '100%',
					borderWidth = 0,
				},
			},
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Scaling:",
				classes = {"formLabel"},
			},
			gui.Slider{
				value = asset.distortWave,
				unclamped = true,
				minValue = 0,
				maxValue = 1,
				sliderWidth = 300,
				labelWidth = 60,
				labelFormat = "percent",
				change = function(element)
					asset.distortWave = element.value
					assets:RefreshAssets("Tilesheet")
				end,
				confirm = function(element)
					asset.distortWave = element.value
					assets:RefreshAssets("Tilesheet")
				end,

				style = {
					fontSize = '80%',
					valign = 'center',
					halign = 'right',
					height = '50%',
					width = '100%',
					borderWidth = 0,
				},
			},
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Speed:",
				classes = {"formLabel"},
			},
			gui.Slider{
				value = asset.distortTime,
				unclamped = true,
				minValue = 0,
				maxValue = 1,
				sliderWidth = 300,
				labelWidth = 60,
				labelFormat = "percent",
				change = function(element)
					asset.distortTime = element.value
					assets:RefreshAssets("Tilesheet")
				end,
				confirm = function(element)
					asset.distortTime = element.value
					assets:RefreshAssets("Tilesheet")
				end,

				style = {
					fontSize = '80%',
					valign = 'center',
					halign = 'right',
					height = '50%',
					width = '100%',
					borderWidth = 0,
				},
			},
		},

	}

	distortionPanel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		gui.Check{
			value = asset.distortion,
			text = "Distortion Effect",
			style = {
				width = '70%',
				height = 48,
				flow = 'horizontal',
				fontSize = '60%',
				borderWidth = 0,
			},
			events = {
				change = function(element)
					asset.distortion = element.value
					assets:RefreshAssets("Tilesheet")
					distortionProperties:FireEventTree("refreshHidden")
				end,
			},
		},

		distortionProperties,
	}

	local movementProperties = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",

		create = function(element)
			element:FireEvent("refreshHidden")
		end,
		
		refreshHidden = function(element)
			element:SetClass("collapsed", not asset.movement)
		end,

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Horizontal:",
				classes = {"formLabel"},
			},
			gui.Slider{
				value = asset.movex,
				unclamped = true,
				minValue = 0,
				maxValue = 1,
				sliderWidth = 300,
				labelWidth = 60,
				labelFormat = "%.1f",
				change = function(element)
					asset.movex = element.value
					assets:RefreshAssets("Tilesheet")
				end,
				confirm = function(element)
					asset.movex = element.value
					assets:RefreshAssets("Tilesheet")
				end,

				style = {
					fontSize = '80%',
					valign = 'center',
					halign = 'right',
					height = '50%',
					width = '100%',
					borderWidth = 0,
				},
			},
		},

		gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = "Vertical:",
				classes = {"formLabel"},
			},
			gui.Slider{
				value = asset.movey,
				unclamped = true,
				minValue = 0,
				maxValue = 1,
				sliderWidth = 300,
				labelWidth = 60,
				labelFormat = "%.1f",
				change = function(element)
					asset.movey = element.value
					assets:RefreshAssets("Tilesheet")
				end,
				confirm = function(element)
					asset.movey = element.value
					assets:RefreshAssets("Tilesheet")
				end,

				style = {
					fontSize = '80%',
					valign = 'center',
					halign = 'right',
					height = '50%',
					width = '100%',
					borderWidth = 0,
				},
			},
		},
	}

	movementPanel = gui.Panel{
		flow = "vertical",
		width = "100%",
		height = "auto",
		gui.Check{
			value = asset.movement,
			text = "Movement",
			style = {
				width = '70%',
				height = 48,
				flow = 'horizontal',
				fontSize = '60%',
				borderWidth = 0,
			},
			events = {
				change = function(element)
					asset.movement = element.value
					assets:RefreshAssets("Tilesheet")
					movementProperties:FireEventTree("refreshHidden")
				end,
			},
		},

		movementProperties,
	}

    surfaceTypePanel = gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = "auto",
        gui.Label{
            fontSize = 14,
            text = "Surface Type:",
            width = "auto",
            height = "auto",
            rmargin = 4,
        },
        gui.Dropdown{
            options = AudioSurfaceTypes.surfaces,
            idChosen = asset.rules.surfaceType or 1,
            change = function(element)
                asset.rules.surfaceType = element.idChosen
				assets:RefreshAssets("Tilesheet")
				movementProperties:FireEventTree("refreshHidden")
            end,
        }
    }


	local idpanel = nil
	if dmhub.GetSettingValue("dev") then
		idpanel = gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = 'ID:',
				classes = {"formLabel"},
			},
			gui.Input{
				bgimage = 'panels/square.png',
				editable = false,
				text = asset.id,
				style = {
					bgcolor = 'black',
					margin = 4,
					valign = 'center',
					width = 360,
					height = '80%',
					cornerRadius = 0,
				},
			},
		}
	end


	local fieldsPanel
	fieldsPanel = gui.Panel{
		vscroll = true,
		style = {
			halign = 'left',
			valign = 'top',
			flow = 'vertical',
			width = '50%',
			height = '85%',
			vmargin = 2,
		},
		selfStyle = {
			hmargin = 4,
		},

		data = {
			updateRequest = nil,
		},

		updateAsset = function(element)
			if element.data.updateRequest == nil then
				element.data.updateRequest = dmhub.Time()
			end

			assets:RefreshAssets("Tilesheet")
		end,

		thinkTime = 0.1,
		
		think = function(element)
			if element.data.updateRequest ~= nil and element.data.updateRequest < dmhub.Time()-1.0 then
				assets:RefreshAssets("Tilesheet")
				element.data.updateRequest = nil
			end
		end,

		children = {

			idpanel,

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Order:',
						classes = {"formLabel"},
					},
					gui.Input{
						bgimage = 'panels/square.png',
						text = string.format("%f", asset.ord),
						characterLimit = 24,
						style = {
							fontSize = 18,
							bgcolor = 'black',
							margin = 4,
							valign = 'center',
							width = 360,
							height = 30,
							cornerRadius = 0,
						},

						events = {
							change = function(element)
								asset.ord = tonumber(element.text) or 0
                                element.text = string.format("%f", asset.ord)
								fieldsPanel:FireEvent("updateAsset")
							end,
						}
					},
				},


			},
		

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Description:',
						classes = {"formLabel"},
					},
					gui.Input{
						bgimage = 'panels/square.png',
						text = asset.description,
						characterLimit = 24,
						style = {
							fontSize = 18,
							bgcolor = 'black',
							margin = 4,
							valign = 'center',
							width = 360,
							height = 30,
							cornerRadius = 0,
						},

						events = {
							change = function(element)
								asset.description = element.text
							end,
						}
					},
				},


			},
			
			effectLayerDropdown,
			effectAlphaThresholdDropdown,
			tilesheetStyleDropdown,
			tilesheetDimensionsWarning,
			randomOrientationCheck,

			gui.Panel{
				classes = {"formPanel"},

				children = {

					gui.Label{
						text = 'Scale:',
						classes = {"formLabel"},
					},

					gui.Slider{
						value = -asset.scale,
						minValue = -4,
						maxValue = 4,
						sliderWidth = 300,
						labelWidth = 60,

						formatFunction = function(num) return
							string.format('%d%%', round((2^num)*100))
						end,
						deformatFunction = function(num)
							local n = num*0.01
							return math.log(n)/math.log(2)
						end,

						events = {
							change = function(element)
								asset.scale = -element.value
								fieldsPanel:FireEvent("updateAsset")
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},

					},
				},


			},

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Hue Shift:',
						classes = {"formLabel"},
					},

					gui.Slider{
						value = asset.hueshift,
						minValue = 0,
						maxValue = 1,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.hueshift = element.value
								fieldsPanel:FireEvent("updateAsset")
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},


			},

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Saturation:',
						classes = {"formLabel"},
					},

					gui.Slider{
						value = asset.saturation,
						minValue = -1,
						maxValue = 1,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.saturation = element.value
								fieldsPanel:FireEvent("updateAsset")
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},


			},

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Brightness:',
						classes = {"formLabel"},
					},

					gui.Slider{
						value = asset.brightness,
						minValue = -1,
						maxValue = 1,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.brightness = element.value
								fieldsPanel:FireEvent("updateAsset")
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},
			},

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Contrast:',
						classes = {"formLabel"},
					},

					gui.Slider{
						value = asset.contrast,
						minValue = 0,
						maxValue = 4,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.contrast = element.value
								fieldsPanel:FireEvent("updateAsset")
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},
			},

			--rules
			waterCheck,
			difficultCheck,
			distortionPanel,
			movementPanel,
            surfaceTypePanel,

			--padding until the buttons.
			gui.Panel{
				style = {
					width = 10,
					height = 80,
				}
			},

			gui.PrettyButton{
				text = 'Default Values',
				margin = 0,
				width = 200,
				height = 60,
				halign = 'left',
				valign = 'top',

				events = {
					click = function()
						asset.contrast = 1
						asset.brightness = 0
						asset.saturation = 0
						asset.hueshift = 0
						asset.scale = 0
						asset.effectLayer = "Ground"
						asset.rules.difficultTerrain = false
						asset.rules.water = false
						asset.distortion = false
						asset.movement = false
						fieldsPanel:FireEvent("updateAsset")

						gui.CloseModal()
						mod.shared.EditTilesheetAssetDialog(tileid, undoValues)

					end
				}
			},

			gui.PrettyButton{
				text = 'Undo Changes',
				captureEscape = true,
				escapePriority = EscapePriority.EXIT_DIALOG,
				margin = 0,
				width = 200,
				height = 60,
				halign = 'left',
				valign = 'top',

				events = {
					click = function(element)
						--undo changes and close the dialog, then re-open it.
						element:FireEvent('escape')
						mod.shared.EditTilesheetAssetDialog(tileid, undoValues)
					end,

					escape = function()
						asset.brightness = undoValues.brightness
						asset.saturation = undoValues.saturation
						asset.contrast = undoValues.contrast
						asset.hueshift = undoValues.hueshift
						asset.scale = undoValues.scale
						asset.effectLayer = undoValues.effectLayer
						asset.oneLargeTile = undoValues.oneLargeTile
						asset.useAlphaThreshold = undoValues.useAlphaThreshold
						asset.rules.water = undoValues.water
						asset.rules.difficultTerrain = undoValues.difficultTerrain
						asset.distortion = undoValues.distortion
						asset.movement = undoValues.movement
						fieldsPanel:FireEvent("updateAsset")

						gui.CloseModal()
					end,
				}
			},

		},
	}

	local dialogPanel = gui.Panel{
		id = 'CreateTerrainDialog',
		classes = {"framedPanel"},
		pad = 8,
		styles = {
			Styles.Panel,
			Styles.Form,
			{
				classes = {"formLabel"},
				halign = "left",
				valign = "center",
			},
			{
				classes = {"slider"},
				height = 30,
				width = "40%",
				halign = "left",
			},
			{
				classes = {"sliderLabel"},
				fontSize = 14,
			},
		},
		style = {
			width = 1200,
			height = 800,
			flow = 'none',
		},
		children = {
			fieldsPanel,
			imagePanel,
			buttonPanel,
		}
	}

	gui.ShowModal(dialogPanel)
end


--WALL EDITING

mod.shared.CreateWallAsset = function()
	dmhub.OpenFileDialog{
		id = "WallSheet",
		extensions = {"jpeg", "jpg", "png", "webm", "webp", "mp4"},
		prompt = string.format("Choose image to use for your new wall"),
		open = function(path)
			local uploadDialog = nil
			local operation
			local assetid = assets:CreateWallAssetFromFile{
				path = path,
				error = function(text)
					gui.ModalMessage{
						title = 'Error creating wall',
						message = text,
					}
				end,
				upload = function(tileid)
					if operation ~= nil then
						operation.progress = 1
					end
				end,
				progress = function(percent)
					if operation ~= nil then
						dmhub.Debug(string.format("PERCENT:: %f", percent))
						operation.progress = percent*0.01
					end
				end,
			}

			if assetid ~= nil then
				operation = dmhub.CreateNetworkOperation()
				operation.description = "Uploading Wall..."
				operation.status = "Uploading..."
				operation.progress = 0.0
				mod.shared.assetsCreated[assetid] = true
			end
		end,
	}
end

mod.shared.EditWallAssetDialog = function(tileid, startingValues)

	local asset = assets.walls[tileid]

	if not asset.loaded then
		--the asset does not have its image loaded so we wait until it does before showing this dialog.
		dmhub.Schedule(0.1, function() mod.shared.EditWallAssetDialog(tileid, startingValues) end)
		return
	end

	local undoValues = DeepCopy(startingValues or {})

	if undoValues.tint == nil then
		undoValues.tint = asset.tint
	end

	if undoValues.shadowMask == nil then
		undoValues.shadowMask = asset.shadowMask
	end

	if undoValues.brightness == nil then
		undoValues.brightness = asset.brightness
	end

	if undoValues.saturation == nil then
		undoValues.saturation = asset.saturation
	end

	if undoValues.contrast == nil then
		undoValues.contrast = asset.contrast
	end

	if undoValues.hueshift == nil then
		undoValues.hueshift = asset.hueshift
	end

	if undoValues.renderParallax == nil then
		undoValues.renderParallax = asset.renderParallax
	end

	if undoValues.invisible == nil then
		undoValues.invisible = asset.invisible
	end

	if undoValues.occludesVision == nil then
		undoValues.occludesVision = asset.occludesVision
	end

	if undoValues.blocksMovement == nil then
		undoValues.blocksMovement = asset.blocksMovement
	end

	if undoValues.soundOcclusion == nil then
		undoValues.soundOcclusion = asset.soundOcclusion
	end

	if undoValues.cover == nil then
		undoValues.cover = asset.cover
	end

	if undoValues.shadowDistortion == nil then
		undoValues.shadowDistortion = asset.shadowDistortion
	end

	if undoValues.wallHeight == nil then
		undoValues.wallHeight = asset.wallHeight
	end

	if undoValues.taper == nil then
		undoValues.taper = asset.taper
	end

	if undoValues.shadowGlowThickness == nil then
		undoValues.shadowGlowThickness = asset.shadowGlowThickness
	end


	local buttonPanel = gui.Panel{
		id = 'BottomButtons',
		style = {
			width = '90%',
			height = 100,
			margin = 8,
			bgcolor = 'white',
			valign = 'bottom',
			halign = 'center',
			flow = 'horizontal',
		},

		children = {
			gui.PrettyButton{
				text = 'Save & Close',
				margin = 0,
				width = 240,
				height = 80,
				halign = 'right',
				valign = 'center',

				events = {
					click = function(element)
						gui.CloseModal()
						asset:Upload()
					end,
				}
			},
		}
	}



	local imageDim = 512
	local imagePanel = gui.Panel{
		bgimage = tileid,
		id = 'tile-image',
		selfStyle = {
			bgcolor = asset.tint,
			hueshift = asset.hueshift,
			saturation = 1+asset.saturation,
			brightness = 1+asset.brightness,
			contrast = asset.contrast,
			borderWidth = 1,
		},
		style = {
			width = imageDim,
			height = imageDim,
			halign = 'right',
			valign = 'top',
			margin = 8,
			flow = 'none',
		},

		events = {
			create = function(element)
				element:FireEvent('refreshAssets')
			end,

			refreshAssets = function(element)
				element.style.width = 512
				element.style.height = 512 * (asset.height/asset.width)
			end,
		}
	}

	local idpanel = nil
	if dmhub.GetSettingValue("dev") then
		idpanel = gui.Panel{
			classes = {"formPanel"},
			gui.Label{
				text = 'ID:',
				style = {
					margin = 4,
					valign = 'center',
					width = 'auto',
					height = 'auto',
				}
			},
			gui.Input{
				bgimage = 'panels/square.png',
				editable = false,
				text = asset.id,
				style = {
					bgcolor = 'black',
					margin = 4,
					valign = 'center',
					width = 360,
					height = '80%',
					cornerRadius = 0,
				},
			},
		}
	end


	local fieldsPanel

	local RefreshAssets = function()
		assets:RefreshAssets()
		fieldsPanel:FireEventTree("refreshAssets")
	end


	fieldsPanel = gui.Panel{
		style = {
			halign = 'left',
			valign = 'top',
			flow = 'vertical',
			width = '48%',
			height = '80%',
			vmargin = 2,
		},
		selfStyle = {
			hmargin = 4,
		},
		hpad = 4,
		vscroll = true,
		styles = {
			{
				selectors = {"formPanel"},
				width = '40%',
				height = 30,
				flow = 'horizontal',
			},
			{
				selectors = {"label"},
				fontSize = 14,
				height = 30,
			}
		},

		children = {

			idpanel,

			gui.Panel{
				classes = {"formPanel"},

				children = {

					gui.Label{
						text = 'Description:',
						style = {
							margin = 4,
							valign = 'center',
							width = 'auto',
							height = 'auto',
						}
					},
					gui.Input{
						bgimage = 'panels/square.png',
						text = asset.description,
						characterLimit = 40,
						style = {
							bgcolor = 'black',
							margin = 4,
							valign = 'center',
							width = 360,
							height = '80%',
							cornerRadius = 0,
						},

						events = {
							change = function(element)
								asset.description = element.text
							end,
						}
					},

				},


			},

			gui.Panel{
				classes = {"formPanel"},
				height = 64,

				children = {
					gui.Label{
						text = "Shadow Mask:",
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						}
					},

					gui.IconEditor{
						style = { bgcolor = "white", width = 64, height = 64},
						imageRect = { x1 = 0, x2 = 1, y1 = 0.05, y2 = 0.95},
						value = asset.shadowMask,
						library = "WallShadow",
						categoriesHidden = true,
						allowNone = true,
						hideButton = true,
						change = function(element)
							asset.shadowMask = element.value
						end,
					},
				},

			},

			gui.Panel{
				classes = {"formPanel"},

				gui.Label{
					text = "Tint:",
					margin = 4,
					valign = 'center',
					width = 140,
					height = 'auto',
				},

				gui.ColorPicker{
					value = asset.tint,
					width = 32,
					height = 32,
					change = function(element)
						asset.tint = element.value
						imagePanel.selfStyle.bgcolor = asset.tint
						RefreshAssets()
					end,
				}
			},

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Scale:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						}
					},

					gui.Slider{
						value = asset.scale,
						minValue = 0,
						maxValue = 2,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.scale = element.value
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},


			},

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Hue Shift:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						}
					},

					gui.Slider{
						value = asset.hueshift,
						minValue = 0,
						maxValue = 1,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.hueshift = element.value
								imagePanel.selfStyle.hueshift = asset.hueshift
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},


			},

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Saturation:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						}
					},

					gui.Slider{
						value = asset.saturation,
						minValue = -1,
						maxValue = 1,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.saturation = element.value
								imagePanel.selfStyle.saturation = 1+asset.saturation
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},


			},

			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Brightness:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						}
					},

					gui.Slider{
						value = asset.brightness,
						minValue = -1,
						maxValue = 1,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.brightness = element.value
								imagePanel.selfStyle.brightness = 1+asset.brightness
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},
			},

			--audio occlusion.
			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Blocks Sounds:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						}
					},

					gui.Slider{
						value = asset.soundOcclusion,
						minValue = 0,
						maxValue = 1,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.soundOcclusion = element.value
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},
			},

			--height.
			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Wall Height:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						}
					},

					gui.Slider{
						value = asset.wallHeight,
						minValue = 0,
						maxValue = 2,
						sliderWidth = 300,
						labelWidth = 60,
						unclamped = true,

						events = {
							change = function(element)
								asset.wallHeight = element.value
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},


			},


			--shadow distortion.
			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Shadow Distortion:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						}
					},

					gui.Slider{
						value = asset.shadowDistortion,
						minValue = 0,
						maxValue = 5,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.shadowDistortion = element.value
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},


			},


			--taper.
			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Taper:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						},
						hover = gui.Tooltip("How much the wall should taper off at its end caps."),
					},

					gui.Slider{
						value = asset.taper,
						minValue = 0,
						maxValue = 2,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.taper = element.value
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},
			},

			--corner size.
			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Corner Size:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						},
						hover = gui.Tooltip("How much the wall should taper off at its end caps."),
					},

					gui.Slider{
						value = asset.cornerSize,
						minValue = 0,
						maxValue = 2,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.cornerSize = element.value
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},
			},


			--internal shadow.
			gui.Panel{
				classes = {"formPanel"},

				children = {
					gui.Label{
						text = 'Internal Shadow:',
						style = {
							margin = 4,
							valign = 'center',
							width = 140,
							height = 'auto',
						},
						hover = gui.Tooltip("The width of the ambient shadow that appears around the wall."),
					},

					gui.Slider{
						value = asset.shadowGlowThickness,
						minValue = 0,
						maxValue = 5,
						sliderWidth = 300,
						labelWidth = 60,

						events = {
							change = function(element)
								asset.shadowGlowThickness = element.value
								RefreshAssets()
							end,
						},

						style = {
							fontSize = '80%',
							valign = 'center',
							halign = 'right',
							height = '50%',
							width = '100%',
							borderWidth = 0,
						},
					},
				},


			},

			gui.Check{
				id = "renderParallaxCheck",
				text = "Use Parallax",
				width = "auto",
				height = 30,
				borderWidth = 0,
				value = asset.renderParallax,
				change = function(element)
					asset.renderParallax = element.value
					RefreshAssets()
				end,
			},

			gui.Check{
				id = "invisibleCheck",
				text = "Invisible",
				width = "auto",
				height = 30,
				borderWidth = 0,
				value = asset.invisible,
				change = function(element)
					asset.invisible = element.value
					RefreshAssets()
				end,
			},

			gui.Check{
				id = "blocksLightCheck",
				text = "Blocks Light",
				width = "auto",
				height = 30,
				borderWidth = 0,
				value = asset.occludesLight,
				change = function(element)
					asset.occludesLight = element.value
					RefreshAssets()
				end,
			},

			gui.Check{
				id = "blocksVisionCheck",
				text = "Blocks Vision",
				width = "auto",
				height = 30,
				borderWidth = 0,
				value = asset.occludesVision,
				change = function(element)
					asset.occludesVision = element.value
					RefreshAssets()
				end,
			},

			gui.Check{
				id = "onewayVisionCheck",
				classes = {cond((not asset.occludesVision) and (not asset.occludesLight), "collapsed-anim")},
				refreshAssets = function(element)
					element:SetClass('collapsed-anim', (not asset.occludesVision) and (not asset.occludesLight))
				end,
				text = "Single Direction Light&Vision",
				width = "auto",
				height = 30,
				borderWidth = 0,
				value = asset.visionOneWay,
				change = function(element)
					asset.visionOneWay = element.value
					RefreshAssets()
				end,
			},





			gui.Check{
				id = "blocksMovementCheck",
				text = "Blocks Movement",
				width = "auto",
				height = 30,
				borderWidth = 0,
				value = asset.blocksMovement,
				change = function(element)
					asset.blocksMovement = element.value
					RefreshAssets()
				end,
			},

			--needs implementation of one-way movement.
--		gui.Check{
--			id = "onewayMovementCheck",
--			classes = {cond((not asset.blocksMovement) and asset.cover == "None", "collapsed-anim")},
--			refreshAssets = function(element)
--				element:SetClass('collapsed-anim', (not asset.blocksMovement) and asset.cover == "None")
--			end,
--			text = "Single Direction Movement&Cover",
--			width = "auto",
--			height = 30,
--			borderWidth = 0,
--			value = asset.movementOneWay,
--			change = function(element)
--				asset.movementOneWay = element.value
--				RefreshAssets()
--			end,
--		},





			gui.Check{
				id = "blocksFlyingCheck",
				classes = {cond(not asset.blocksMovement, "collapsed-anim")},
				text = "Blocks Flying",
				width = "auto",
				height = 30,
				borderWidth = 0,
				value = asset.blocksFlying,
				refreshAssets = function(element)
					element:SetClass('collapsed-anim', not asset.blocksMovement)
				end,
				change = function(element)
					asset.blocksFlying = element.value
					RefreshAssets()
				end,
			},

			gui.Dropdown{
				id = "coverDropdown",
				idChosen = asset.cover,
				options = {
					{
						id = "None",
						text = "No Cover",
					},
					{
						id = "Half",
						text = "Cover",
					},
					{
						id = "Full",
						text = "Obstruction",
					},
				},
				change = function(element)
					asset.cover = element.idChosen
					RefreshAssets()
				end,
			},

			--padding until the buttons.
			gui.Panel{
				style = {
					width = 10,
					height = 80,
				}
			},

			gui.Button{
				text = 'Default Values',
				margin = 0,
				width = 160,
				height = 40,
				fontSize = 18,
				halign = 'left',
				valign = 'top',
				vmargin = 4,

				events = {
					click = function()
						asset.tint = "white"
						asset.brightness = 0
						asset.saturation = 0
						asset.hueshift = 0
						asset.contrast = 0
						RefreshAssets()

						gui.CloseModal()
						mod.shared.EditWallAssetDialog(tileid, undoValues)

					end
				}
			},

			gui.Button{
				text = 'Undo Changes',
				captureEscape = true,
				escapePriority = EscapePriority.EXIT_DIALOG,
				margin = 0,
				width = 160,
				height = 40,
				fontSize = 18,
				halign = 'left',
				valign = 'top',
				vmargin = 4,

				events = {
					click = function(element)
						--undo changes and close the dialog, then re-open it.
						element:FireEvent('escape')
						mod.shared.EditWallAssetDialog(tileid, undoValues)
					end,

					escape = function()
						asset.tint = undoValues.tint
						asset.shadowMask = undoValues.shadowMask
						asset.brightness = undoValues.brightness
						asset.saturation = undoValues.saturation
						asset.hueshift = undoValues.hueshift
						asset.contrast = undoValues.contrast
						RefreshAssets()

						gui.CloseModal()
					end,
				}
			},

		},
	}

	local dialogPanel = gui.Panel{
		id = 'CreateWallDialog',
		classes = {"framedPanel"},
		width = 1200,
		height = 900,
		pad = 8,
		styles = {
			Styles.Panel,
		},
		children = {
			fieldsPanel,
			imagePanel,
			buttonPanel,
		}
	}

	gui.ShowModal(dialogPanel)
end

