local mod = dmhub.GetModLoading()

mod.shared.CreateEffectDialog = nil

mod.shared.CreateEffectsLayerTexture = function()

	local dialogPanel = nil
	local objectsList = nil

	local seed = math.random(1000)
	local numObjectsExp = 0
	local spreadAmount = 0

	local RecalculateTexture = function()
		local objects = {}
		for i,child in ipairs(objectsList.children) do
			objects[#objects+1] = {
				objectid = child.data.objectid,
				weight = child.data.weight,
				scale = child.data.scale,
				randomScale = child.data.randomScale,
				randomRotation = child.data.randomRotation,
				randomHue = child.data.randomHue,
				randomSaturation = child.data.randomSaturation,
				randomLuminance = child.data.randomLuminance,
				zorder = child.data.zorder,
				randomZorder = child.data.randomZorder,
			}
		end
		dmhub.Debug('refresh texture')
		local numObjects = round((2^numObjectsExp)*100)
		effectsBrush:BuildBrush{
			objects = objects,
			options = {
				numObjects = numObjects,
				seed = seed,
				spreadIterations = round(spreadAmount*10),
				spreadMult = 10/numObjects,
			},
		}
	end

	local _dirty = false

	local RefreshTexture = function()
		_dirty = true
	end

	local globalPropertiesPanel = gui.Panel{

		classes = {'hidden'},
		events = {
			refreshChosenObjects = function(element)
				if #objectsList.children == 0 then
					element:SetClass('hidden', true)
				else
					element:SetClass('hidden', false)
				end
			end,
		},
		
		selfStyle = {
			halign = 'left',
			valign = 'top',
			flow = 'vertical',
			width = 'auto',
			height = 'auto',
		},
		children = {
			gui.Panel{
				id = 'seed-property',
				classes = {'properties-entry'},
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Seed:',
					},
					gui.Input{
						id = 'EffectsSeedInput',
						classes = {'property-value'},
						text = tostring(seed),
						events = {
							change = function(element)
								seed = round(tonumber(element.text) or 0)
								RefreshTexture()
							end,
						}
					},
					gui.IconButton{
						icon = 'game-icons/clockwise-rotation.png',
						style = {
							width = 24,
							height = 24,
						},
						events = {
							click = function(element)
								seed = math.random(1000)
								element:Get('EffectsSeedInput').text = tostring(seed)
								RefreshTexture()
							end,
						}
					},
				}
			},

			gui.Panel{
				classes = {'properties-entry'},
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Object Count:',
					},
					gui.Slider{
						sliderWidth = 140,
						labelWidth = 50,
						value = numObjectsExp,
						minValue = -2,
						maxValue = math.log(50)/math.log(2),
						formatFunction = function(num)
							return string.format('%d', round((2^num)*100))
						end,
						deformatFunction = function(num)
							local n = num*0.01
							return math.log(n)/math.log(2)
						end,
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								numObjectsExp = element.value
								RefreshTexture()
							end,
						},
					},
				},
			},

			gui.Panel{
				classes = {'properties-entry'},
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Spread:',
					},
					gui.Slider{
						sliderWidth = 140,
						labelWidth = 50,
						value = spreadAmount,
						minValue = 0,
						maxValue = 1,
						labelFormat = 'percent',
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								spreadAmount = element.value
								RefreshTexture()
							end,
						},
					},
				},
			},

		}
	}

	local panelsSelected = {}

	local objectPropertiesPanel = gui.Panel{

		classes = {'object-properties-panel', 'hidden'},
		events = {
			refreshSelection = function(element)
				if #panelsSelected == 0 then
					element:SetClass('hidden', true)
				else
					element:SetClass('hidden', false)
				end
			end,
		},

		children = {

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Frequency:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 100,
						minValue = 0,
						maxValue = 5,
						labelFormat = '%.1f',
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.weight = element.value
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.weight
								end
							end,
						},
					},

				},
			},

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Base Scale:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 100,
						minValue = 10,
						maxValue = 400,
						labelFormat = 'percent',
						formatFunction = function(num)
							return string.format('%d', round(num))
						end,
						deformatFunction = function(num)
							return num
						end,
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.scale = element.value*0.01
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.scale*100
								end
							end,
						},
					},

				},
			},

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Random Scale:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 10,
						minValue = 0,
						maxValue = 100,
						labelFormat = 'percent',
						formatFunction = function(num)
							return string.format('%d', round(num))
						end,
						deformatFunction = function(num)
							return num
						end,
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.randomScale = element.value*0.01
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.randomScale*100
								end
							end,
						},
					},

				},
			},

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Random Rotation:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 10,
						minValue = 0,
						maxValue = 360,
						labelFormat = '%d',
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.randomRotation = element.value
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.randomRotation
								end
							end,
						},
					},

				},
			},

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Random Hue:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 10,
						minValue = 0,
						maxValue = 360,
						labelFormat = '%d',
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.randomHue = element.value
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.randomHue
								end
							end,
						},
					},

				},
			},

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Random Saturation:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 0,
						minValue = 0,
						maxValue = 1,
						labelFormat = 'percent',
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.randomSaturation = element.value
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.randomSaturation
								end
							end,
						},
					},

				},
			},

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Random Brightness:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 0,
						minValue = 0,
						maxValue = 1,
						labelFormat = 'percent',
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.randomLuminance = element.value
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.randomLuminance
								end
							end,
						},
					},

				},
			},

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Height:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 0,
						minValue = 0,
						maxValue = 1,
						labelFormat = 'percent',
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.zorder = element.value
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.zorder
								end
							end,
						},
					},

				},
			},

			gui.Panel{
				classes = 'properties-entry',
				children = {
					gui.Label{
						classes = {'property-label'},
						text = 'Random Height:',
					},
					gui.Slider{
						sliderWidth = 120,
						labelWidth = 60,
						value = 0,
						minValue = 0,
						maxValue = 1,
						labelFormat = 'percent',
						style = {
							width = 200,
							height = 30,
							fontSize = 18,
						},
						events = {
							change = function(element)
								for i,p in ipairs(panelsSelected) do
									p.data.randomZorder = element.value
								end

								RefreshTexture()
							end,
							refreshSelection = function(element)
								if #panelsSelected > 0 then
									element.value = panelsSelected[1].data.randomZorder
								end
							end,
						},
					},

				},
			},

		},
	}

	local buttonPanel = gui.Panel{
		id = 'BottomButtons',
		style = {
			width = '90%',
			height = 70,
			margin = 8,
			bgcolor = 'white',
			valign = 'bottom',
			halign = 'center',
			flow = 'horizontal',
		},

		children = {

			gui.Button{
				text = 'Create Brush',
				classes = {"sizeXl", 'hidden'},
				style = {
					margin = 0,
					halign = 'center',
					valign = 'center',
				},

				events = {

					refreshChosenObjects = function(element)
						if #objectsList.children == 0 then
							element:SetClass('hidden', true)
						else
							element:SetClass('hidden', false)
						end
					end,
					click = function(element)
						mod.shared.CreateEffectDialog = nil
						dialogPanel:DestroySelf()
						mod.shared.CreateTerrainAssetFromPath('effects', '#EffectTexture')
						dialogPanel:FireEventTree('refreshChosenObjects')
					end,
				}
			},

			gui.Button{
				text = 'Close',
				classes = {"sizeXl"},
				style = {
					margin = 0,
					halign = 'center',
					valign = 'center',
				},

				events = {
					click = function(element)
						mod.shared.CreateEffectDialog = nil
						dialogPanel:DestroySelf()
					end,
				}
			},

		}
	}

	local imagePreviewPanel = gui.Panel{
		bgimage = '#EffectTexture',
		classes = {'preview-panel'},
		selfStyle = {
			alphaThreshold = 1,
			alphaThresholdFade = 0.1,
		},
	}

	local imagePreviewAlphaSlider = gui.Panel {
		classes = {'properties-entry'},
		children = {
			gui.Label{
				classes = {'property-label'},
				text = 'Preview Intensity:',
			},
			
			gui.Slider{
				sliderWidth = 140,
				labelWidth = 50,
				value = 1,
				labelFormat = 'percent',
				minValue = 0,
				maxValue = 1,
				style = {
					width = 200,
					height = 30,
					fontSize = 18,
				},
				events = {
					change = function(element)
						imagePreviewPanel.selfStyle.alphaThreshold = element.value
					end,
				},
			},
		}
	}

	local imagePreviewPanelContainer = gui.Panel{
		id = 'PreviewPanelContainer',

		classes = {'hidden'},
		events = {
			refreshChosenObjects = function(element)
				if #objectsList.children == 0 then
					element:SetClass('hidden', true)
				else
					element:SetClass('hidden', false)
				end
			end,
		},
	
		bgimage = 'panels/square.png',
		selfStyle = {
			bgcolor = 'black',
			width = 'auto',
			height = 'auto',
			margin = 20,
			halign = 'right',
			valign = 'top',
			flow = 'vertical',
		},
		children = {
			imagePreviewPanel,
			imagePreviewAlphaSlider,
		},
	}

	local createLabel = gui.Label{
		text = "Let's create a brush! Start dragging objects here to add them to the brush.",
		events = {
			refreshChosenObjects = function(element)
				if #objectsList.children == 0 then
					element:SetClass('hidden', false)
				else
					element:SetClass('hidden', true)
				end
			end,
		},
	
		selfStyle = {
			halign = 'center',
			valign = 'center',
			fontSize = 28,
			maxWidth = 500,
			width = 'auto',
			height = 'auto',
		}
	}

	local ClearSelectedPanels = function()
		for i,p in ipairs(panelsSelected) do
			p.data.SetSelected(false)
		end

		panelsSelected = {}
		objectPropertiesPanel:FireEventTree('refreshSelection')
	end

	local SelectPanel = function(panel)
		if panel.data.IsSelected() == false then
			panel.data.SetSelected(true)
			panelsSelected[#panelsSelected+1] = panel
			objectPropertiesPanel:FireEventTree('refreshSelection')
		end
	end

	local CreateObjectPanel = function(objid)
		local objnode = assets:GetObjectNode(objid)

		local imagePanel = gui.Panel{
			classes = {'object-icon'},
			bgimage = objnode.image,
			events = {
				imageLoaded = function(element)
					local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
					if maxDim > 0 then
						local xratio = element.bgsprite.dimensions.x/maxDim
						local yratio = element.bgsprite.dimensions.y/maxDim
						element.selfStyle.width = tostring(xratio*100) .. '%'
						element.selfStyle.height = tostring(yratio*100) .. '%'
					end
				end
			},
		}

		local resultPanel = nil

		local selectionPanel = gui.Panel{
			bgimage = 'panels/square.png',
			classes = {'object-selection'},
			events = {
				click = function(element)
					if (not dmhub.modKeys['shift']) and (not dmhub.modKeys['ctrl']) then
						ClearSelectedPanels()
					end

					SelectPanel(resultPanel)
				end,
				rightClick = function(element)
					element:FireEvent('click')
					element.popup = gui.ContextMenu{
						entries = {
							{
								text = "Remove Object",
								click = function()
									element.popup = nil
									resultPanel:FireEvent('delete')
								end,
							}
						},
					}
				end,
			},
		}

		resultPanel = gui.Panel{
			classes = {'object-panel'},
			children = {
				imagePanel,
				selectionPanel,
			},
			data = {
				objectid = objid,
				weight = 1,
				scale = 1,
				randomScale = 0.1,
				randomRotation = 360,
				randomHue = 36,
				randomSaturation = 0.1,
				randomLuminance = 0.1,
				zorder = 0.0,
				randomZorder = 1.0,
				IsSelected = function()
					return selectionPanel:HasClass('is-selected')
				end,
				SetSelected = function(val)
					selectionPanel:SetClass('is-selected', val)
				end,
			},
			events = {
				delete = function()
					for i,p in ipairs(panelsSelected) do
						p:DestroySelf()
					end
					panelsSelected = {}
					objectPropertiesPanel:FireEventTree('refreshSelection')
					RefreshTexture()
				end,
			},
		}

		return resultPanel
	end

	objectsList = gui.Panel{
		vscroll = true,
		selfStyle = {
			halign = 'left',
			valign = 'bottom',
		},
		style = {
			width = 300,
			height = 256,
			flow = 'horizontal',
			wrap = true,
		},
	}

	dialogPanel = gui.Panel{
		id = 'CreateEffectsDialogPanel',
		bgimage = 'panels/square.png',
		dragTarget = true,
		classes = {'accept-objects', 'dialog'},
		styles = {
			{
				width = 1000,
				height = 860,
				bgcolor = '#888888ff',
				flow = 'none',
				halign = 'center',
				valign = 'center',
			},
			{
				selectors = {'dialog'},
				borderWidth = 2,
				borderColor = 'black',
				cornerRadius = 8,
			},
			{
				selectors = {'drag-target'},
				borderColor = 'white',
				transitionTime = 0.4,
			},
			{
				selectors = {'drag-target-hover'},
				borderColor = 'yellow',
				transitionTime = 0.2,
			},
			{
				selectors = {'object-panel'},
				priority = 5,
				width = 64,
				height = 64,
				halign = 'left',
				valign = 'top',
				margin = 2,
				flow = 'none',
			},
			{
				selectors = {'object-selection'},
				priority = 5,
				bgcolor = 'clear',
				width = '100%',
				height = '100%',
				margin = 0,
				pad = 0,
			},
			{
				selectors = {'object-selection','hover'},
				priority = 5,
				borderWidth = 2,
				borderColor = 'yellow',
			},
			{
				selectors = {'object-selection','press'},
				priority = 5,
				borderWidth = 2,
				borderColor = '#ff7777ff',
			},
			{
				selectors = {'object-selection', 'is-selected'},
				priority = 5,
				borderWidth = 2,
				borderColor = 'white',
			},
			{
				selectors = {'object-icon'},
				bgcolor = 'white',
			},
			{
				selectors = {'preview-panel'},
				priority = 5,
				bgcolor = 'white',
				halign = 'right',
				valign = 'top',
				width = 396,
				height = 396,
			},
			{
				selectors = {'properties-entry'},
				priority = 5,
				valign = 'top',
				flow = 'horizontal',
				width = 'auto',
				height = 'auto',
			},
			{
				selectors = {'property-label'},
				priority = 5,
				fontSize = 18,
				minWidth = 140,
				width = 'auto',
				height = 'auto',
				textAlignment = 'right',
			},
			{
				selectors = {'property-value'},
				priority = 10,
				width = 200,
				height = 26,
				fontSize = 18,
				hmargin = 8
			},
			{
				selectors = {'property-value', 'input'},
				priority = 3,
			},
			{
				selectors = {'object-properties-panel'},
				priority = 5,
				y = -70,
				halign = 'right',
				valign = 'bottom',
				width = '50%',
				height = '35%',
				flow = 'vertical',
			},
		},
		children = {
			imagePreviewPanelContainer,
			globalPropertiesPanel,
			objectsList,
			objectPropertiesPanel,
			buttonPanel,
			createLabel,
		},
		thinkTime = 0.05,
		events = {
			think = function(element)
				if _dirty then
					RecalculateTexture()
					_dirty = false
				end
			end,
			dragObject = function(element, objid)
				local nodeids = {}
				local found = false
				for i,entry in ipairs(mod.shared.selectedObjectEntries) do
					nodeids[#nodeids+1] = entry.data.nodeid
					if entry.data.nodeid == objid then
						found = true
					end
				end

				if not found then
					nodeids[#nodeids+1] = objid
				end

				local children = objectsList.children

				for i,nodeid in ipairs(nodeids) do
					local objnode = assets:GetObjectNode(nodeid)
					local panel = CreateObjectPanel(nodeid)
					children[#children+1] = panel
				end

				objectsList.children = children
				dialogPanel:FireEventTree('refreshChosenObjects')

				RefreshTexture()

				if #children ~= 0 then
					children[#children]:FireEventTree('click')
				end
			end,
		},
	}

	mod.shared.CreateEffectDialog = dialogPanel

	local children = gui.DialogPanel().children
	children[#children+1] = dialogPanel
	gui.DialogPanel().children = children
end


