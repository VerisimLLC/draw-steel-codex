local mod = dmhub.GetModLoading()

local PenPressureSettingsDialog = function()
	gui.ModalMessage{
		title = "Pen Settings",
		panel = gui.Panel{
			width = 300,
			height = 300,
			floating = true,
			gui.Curve{
				halign = "left",
				valign = "top",
				width = 280,
				height = 280,
				value = dmhub.GetSettingValue("penpressurecurve"),
				confirm = function(element)
					dmhub.SetSettingValue("penpressurecurve", element.value)
				end,
			},

			gui.Label{
				floating = true,
				fontSize = 14,
				width = "auto",
				height = "auto",
				text = "Pen Input",
				halign = "center",
				valign = "bottom",
			},

			gui.Label{
				floating = true,
				fontSize = 14,
				width = "auto",
				height = "auto",
				text = "Output",
				halign = "right",
				valign = "center",
				rotate = 270,
			},

		},
	}
	
end

local BrushFieldEditors = {
	texture = function(args)
		local asset = args.asset

		return gui.Panel{
			classes = {"formValue"},
			gui.IconEditor{
				library = args.library,
				allowNone = args.allowNone,
				categoriesHidden = true,
				searchHidden = true,
				bgcolor = "white",
				width = 32,
				height = 32,
				hideButton = true,
				value = asset[args.field],
				valign = "center",

				events = {
					change = function(element)
						asset[args.field] = element.value
						--if not args.temporary then
							asset:Upload()
						--end
					end,
				}
			},
		}
	end,

	enum = function(args)

		local asset = args.asset
		local options = args.options
		local expandedOptions = {}
		for option in ipairs(options) do
			if type(option) == "string" then
				expandedOptions[#expandedOptions+1] = {
					id = option,
					text = option,
				}
			else
				expandedOptions[#expandedOptions+1] = option
			end
		end

		return gui.Dropdown{
			classes = {"formDropdown"},
			options = args.options,

			idChosen = asset[args.field],

			change = function(element)
				asset[args.field] = element.idChosen
				--if not args.temporary then
					asset:Upload()
				--end
			end,
		}
	end,

	slider = function(args)

		local asset = args.asset

		local resultPanel
		local penIcon = nil
		
		if not args.temporary then
			penIcon = gui.Panel{
				width = 16,
				height = 16,
				halign = "right",
				valign = "center",
				styles = {
					{
						bgimage = "icons/icon_tool/icon_tool_79.png",
						bgcolor = "#999999",
					},
					{
						selectors = {"visible"},
						bgimage = "icons/icon_tool/icon_tool_79.png",
						bgcolor = "white",
					},
				},

				classes = {cond(asset:GetParameter(args.field) ~= nil, "visible")},

				linger = gui.Tooltip(cond(dmhub.HasStylus(), "Change this property dynamically based on pen pressure or other settings.", "Change this property dynamically based on velocity or other settings.")),

				click = function(element)
					if asset:GetParameter(args.field) == nil then
						asset:SetParameter(args.field, {
							source = "Pressure",
						})
					else
						asset:SetParameter(args.field, nil)
					end

					element:SetClass("visible", asset:GetParameter(args.field) ~= nil)

					asset:Upload()

					args.paramsPanel:FireEventTree("refreshParameter")
				end,
			}

			--pass this out so BrushField can place it at the right edge of
			--the formPanel (alongside displayIcon/formLabel/editorPanel),
			--rather than next to the slider control.
			args.penIcon = penIcon

			--pass this out to display below us.
			args.paramsPanel = gui.Panel{
				width = "auto",
				height = "auto",
				flow = "vertical",

				create = function(element)
					local param = asset:GetParameter(args.field)
					if param == nil then
						element.children = {}
						element:SetClass("collapsed", true)
						return
					end

					element:SetClass("collapsed", false)

					local children = {

						gui.Panel{
							classes = {"formPanel"},
							valign = "top",
							gui.Label{
								classes = {"formLabel"},
								text = "Source:",
							},
							gui.Dropdown{
								classes = {"formDropdown"},
								options = {
									{
										id = "Pressure",
										text = "Pen Pressure",
									},
									{
										id = "Velocity",
										text = "Velocity",
									},
								},

								idChosen = param.source,
								change = function(element)
									param = asset:GetParameter(args.field)
									param.source = element.idChosen
									asset:SetParameter(args.field, param)
									asset:Upload()
								end,
							},
							gui.Panel{
								width = 16,
								height = 16,
								hmargin = 4,
								bgimage = "icons/icon_tool/icon_tool_2.png",
								monitorAssets = "brush",
								refreshAssets = function(element)
									local param = asset:GetParameter(args.field)
									if param ~= nil and param.source == "Pressure" then
										element:SetClass("hidden", false)
									else
										element:SetClass("hidden", true)
									end
								end,
								create = function(element)
									element:FireEvent("refreshAssets")
								end,
								click = function(element)
									PenPressureSettingsDialog()
								end,
								styles = {
									{
										bgcolor = "#ffffff99",
									},
									{
										selectors = {"hover"},
										bgcolor = "#ffffffff",
									},
									{
										selectors = {"press"},
										bgcolor = "#999999ff",
									},
								},
							},
						},

						gui.Panel{
							classes = {"formPanel"},
							valign = "top",
							gui.Label{
								classes = {"formLabel"},
								text = "Min. Value:",
							},
							gui.Slider{
								value = param.min,
								minValue = 0,
								maxValue = 1,
								classes = {"formDropdown"},

								sliderWidth = 100,
								labelWidth = 40,

								height = 20,
								width = 150,
								valign = "center",
								halign = "right",
								style = {
									fontSize = 12,
								},

								labelFormat = "percent",

								confirm = function(element)
									param = asset:GetParameter(args.field)
									param.min = element.value
									asset:SetParameter(args.field, param)
									asset:Upload()
								end,
							}
						},

					}

					element.children = children
				end,
				refreshParameter = function(element)
					element:FireEvent("create")
				end,
			}
		end

		local sliderArgs = {
			value = asset[args.field],
			minValue = args.minValue or 0,
			maxValue = args.maxValue or 1,
			sliderWidth = 120,
			labelWidth = 50,

			height = 20,
			width = 180,
			valign = "center",
			halign = "right",
			style = {
				fontSize = 14,
			},

			commands = args.commands,

			labelFormat = args.labelFormat,
			formatFunction = args.formatFunction,
			deformatFunction = args.deformatFunction,

			events = {
				confirm = function(element)
					asset[args.field] = element.value
					--if not args.temporary then
						asset:Upload()
					--end
				end,
			},
		}

		for _,cmd in ipairs(args.commands or {}) do
			sliderArgs.events[cmd] = args[cmd]
		end

		resultPanel = gui.Panel{
			flow = "vertical",
			classes = {"formValue"},
			width = "auto",
			height = "auto",
			gui.Slider(sliderArgs),
		}

		return resultPanel
	end
}

local BrushField = function(args)
	local editorPanel = BrushFieldEditors[args.type](args)
	local hidden = args.hidden
	local asset = args.asset

	local displayIcon

	if (not args.temporary) and (not args.alwaysDisplayed) then
		displayIcon = gui.Panel{
			width = 16,
			height = 16,
			halign = "left",
			valign = "center",
			classes = {cond(asset:GetDisplayField(args.field), "visible")},
			styles = {
				{
					bgimage = "icons/icon_tool/icon_tool_60.png",
					bgcolor = "#999999",
				},
				{
					selectors = {"visible"},
					bgimage = "icons/icon_tool/icon_tool_59.png",
					bgcolor = "white",
				},
			},

			linger = gui.Tooltip("Display this property in the sidebar"),

			click = function(element)
				asset:SetDisplayField(args.field, not asset:GetDisplayField(args.field))
				element:SetClass("visible", asset:GetDisplayField(args.field))
				asset:Upload()
			end,

		}
	end

	return gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",
		valign = "top",
		gui.Panel{
			classes = {"formPanel", cond(hidden ~= nil and hidden(args.asset), 'collapsed-anim')},
			monitorAssets = cond(hidden ~= nil, "brush"),
			refreshAssets = function(element)
				if hidden ~= nil then
					element:SetClass("collapsed-anim", hidden(args.asset))
				end
			end,
			displayIcon,
			gui.Label{
				classes = {"formLabel"},
				valign = "center",
				text = string.format("%s:", args.name),
			},

			editorPanel,
			args.penIcon,
			data = {
				asset = asset,
			},
		},

		--if they also passed out a params panel.
		args.paramsPanel,
	}
end

local brushFields = {

	{
		type = "texture",
		library = "brush",
		name = "Tip",
		field = "tipAsset",
	},

	{
		type = "slider",
		name = "Size",
		field = "radius",
		labelFormat = "%.1f",
		minValue = 0.2,
		maxValue = 6,
		alwaysDisplayed = true,

		commands = {"increasebrush", "decreasebrush"},
		increasebrush = function(element)
			element.value = element.value + 0.5
			element:FireEvent("confirm")
		end,
		decreasebrush = function(element)
			element.value = element.value - 0.5
			element:FireEvent("confirm")
		end,
	},



	{
		type = "enum",
		name = "Rotation",
		field = "tipRotation",
		options = {
			{
				id = "Fixed",
				text = "Fixed",
			},
			{
				id = "StrokeDirection",
				text = "Stroke Direction",
			},
		},
	},

	{
		type = "slider",
		name = "Opacity",
		field = "opacity",
		labelFormat = "percent",
	},


	{
		type = "slider",
		name = "Fade",
		field = "fadeRadius",
		labelFormat = "percent",
		minValue = 0,
		maxValue = 1,
	},

	{
		type = "enum",
		name = "Blend",
		field = "blend",
		options = { "Add", "Max", },
	},

	{
		type = "texture",
		library = "brushTexture",
		name = "Texture",
		field = "textureAsset",
		allowNone = true,
	},

	{
		type = "slider",
		name = "Texture Scale",
		field = "textureScale",
		minValue = -4,
		maxValue = 4,
		hidden = function(asset)
			return asset.textureAsset == nil or asset.textureAsset == ""
		end,

		formatFunction = function(num) return
			string.format('%d%%', round((2^num)*100))
		end,
		deformatFunction = function(num)
			local n = num*0.01
			return math.log(n)/math.log(2)
		end,
	},
}

--this is the panel that appears on the right sidebar which gives immediate brush controls.
mod.shared.BrushEditorPanel = function(settingid)
	local CreateBrushButton = function(key, asset)
		local resultPanel = gui.Panel{
			classes = {"brushPanel"},
			data = {
				asset = asset,
			},

			monitor = settingid,
			events = {
				create = function(element)
					element:FireEvent("monitor")
				end,
				monitor = function(element)
					element:SetClass("selected", dmhub.GetSettingValue(settingid) == key)
				end,

				click = function(element)
					dmhub.SetSettingValue(settingid, key)
                    gui.SetFocus(element)
				end,

				rightClick = function(element)
					element.popup = gui.ContextMenu{
						entries = {
							{
								text = "Edit Brush",
								click = function()
									mod.shared.ShowBrushEditor(key)
									element.popup = nil
								end,
							},
							{
								text = "Delete Brush",
								click = function()
									asset.hidden = true
									asset:Upload()

								end,
							}
						},
					}
				end,
			},

			gui.Panel{
				classes = {"brushIcon"},
				monitorAssets = "brush",
				data = {
					fadeRadius = nil,
				},
				events = {
					create = function(element)
						element:FireEvent("refreshAssets")
					end,
					refreshAssets = function(element)
						local brushInfo = assets.brushes[key]

						if brushInfo.textureAsset ~= nil then
							--matches tilesAcross in the engine's BrushTool.cs
							local tilesAcross = 16*math.pow(2, brushInfo.textureScale-1)

							local tipAcross = 2 * brushInfo.radius

							local scaling = tipAcross/tilesAcross

							element.bgimageMaskRect = {x1 = 0, y1 = 0, x2 = scaling, y2 = scaling}


						end

						element.bgimage = brushInfo.tipAsset
						element.bgimageMask = brushInfo.textureAsset
						element.selfStyle.opacity = brushInfo.opacity

						if element.data.fadeRadius ~= brushInfo.fadeRadius then
							element.data.fadeRadius = brushInfo.fadeRadius
							if brushInfo.fadeRadius >= 1 then
								element.selfStyle.gradient = nil
							else
								element.selfStyle.gradient = {
									type = 'radial',
									point_a = { x = 0.5, y = 0.5 },
									point_b = { x = 0.5, y = 1 },
									stops = {
										{
											position = 0,
											color = '#ffffffff',
										},
										{
											position = brushInfo.fadeRadius,
											color = '#ffffffff',
										},
										{
											position = 1,
											color = '#ffffff00',
										},
									}
								}
							end
						end
					end,
				},
			},
		}

		return resultPanel
	end

	local numBrushes = -1
	local panels = {}

	local addPanel = nil

	local palettePanel = gui.Panel{
		id = "brushEditor",
		flow = "horizontal",
		height = "auto",
		hmargin = 8,
		vmargin = 4,

		styles = {
			{
				selectors = {"brushPanel"},
				width = 64,
				height = 64,
				cornerRadius = 8,
				saturation = 0.5,
				bgcolor = 'white',
				bgimage = "panels/hud/button_09_frame_custom.png",
			},
			{
				selectors = {"brushPanel", "selected"},
				brightness = 2.5,
				saturation = 1.4,
			},
			{
				selectors = {"brushPanel", "hover"},
				brightness = 2.5,
				transitionTime = 0.1,
			},
			{
				selectors = {"brushPanel", "press"},
				brightness = 0.8,
				transitionTime = 0.1,
			},
			{
				selectors = {"brushIcon"},
				bgcolor = "white",
				width = 48,
				height = 48,
				halign = "center",
				valign = "center",
			},
		},

		gui.Panel{
			width = 320,
			height = "auto",
			flow = "horizontal",
			wrap = true,

			monitorAssets = "brush",

			create = function(element)
				element:FireEvent("refreshAssets")
			end,

			refreshAssets = function(element)
				local newBrushes = false
				local brushCount = 0
				for k,brush in pairs(assets.brushes) do
					if not brush.hidden then
						brushCount = brushCount+1
						if panels[k] == nil then
							newBrushes = true
						end
					end
				end

				if (not newBrushes) and brushCount == numBrushes then
					return
				end

				numBrushes = brushCount

				local newPanels = {}
				local children = {}

				for k,brush in pairs(assets.brushes) do
					if not brush.hidden then
						newPanels[k] = panels[k] or CreateBrushButton(k, brush)
						children[#children+1] = newPanels[k]
					end
				end

				table.sort(children, function(a,b) return a.data.asset.ord < b.data.asset.ord end)

				if addPanel == nil then
					addPanel = gui.AddButton{
						width = 64,
						height = 64,
						click = function(element)
							local brush = assets:CreateBrush()
							brush:Upload()
						end,
						tooltip = "Create a new brush",
					}
				end

				children[#children+1] = addPanel

				element.children = children
				panels = newPanels
			end,
		},
	}

	--any properties that this brush exposes to the sidebar.
	local propertiesPanels = {}
	local brushid = dmhub.GetSettingValue(settingid)
	local brushAsset = assets.brushes[brushid]
	local brushPropertiesPanel = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",
		monitor = settingid,
		monitorAssets = "brush",
		styles = {
			Styles.Form,
			{
				selectors = {"formLabel"},
				halign = "left",
				valign = "center",
				width = 80,
			},
		},

		events = {
			create = function(element)
				element:FireEvent("recalculate")
			end,
			monitor = function(element)
				brushid = dmhub.GetSettingValue(settingid)
				brushAsset = assets.brushes[brushid]
				element:FireEvent("recalculate")
			end,
			refreshAssets = function(element)
				brushAsset = assets.brushes[brushid]
				element:FireEvent("recalculate")
			end,

			recalculate = function(element)
				if brushAsset == nil then
					return
				end

				local children = {}
				local newPropertiesPanels = {}
				for _,field in ipairs(brushFields) do
					if field.alwaysDisplayed or brushAsset:GetDisplayField(field.field) then
						local currentPanel = propertiesPanels[field.field]
						if currentPanel == nil or currentPanel.data.asset ~= brushAsset then
							local fieldInfo = DeepCopy(field)
							fieldInfo.asset = brushAsset
							fieldInfo.temporary = true
							currentPanel = BrushField(fieldInfo)
						end
						
						newPropertiesPanels[field.field] = currentPanel
						children[#children+1] = currentPanel
					end
				end

				propertiesPanels = newPropertiesPanels
				element.children = children
			end,
		},
	}

	local resultPanel = gui.Panel{
		flow = "vertical",
		width = "auto",
		height = "auto",
		styles = {
			{
				selectors = {"sliderNotch"},
				bgimage = true,
				bgcolor = "#A0A0A0",
				width = "100%",
				halign = "center",
				borderWidth = 0,
			},
		},
		palettePanel,
		brushPropertiesPanel,
	}

	return resultPanel
end


--a full brush editor dialog.
mod.shared.ShowBrushEditor = function(brushid, startingValues)

	local asset = assets.brushes[brushid]

	local dialogWidth = 500
	local dialogHeight = 600

	local resultPanel

	local brushPropertiesFields = {
		gui.Label{
			width = "auto",
			height = "auto",
			vpad = 4,
			halign = "center",
			valign = "top",
			text = "Brush Properties",
			bold = true,
			fontSize = 22,
		},


		gui.Panel{
			classes = {"formPanel"},
			valign = "top",
			gui.Label{
				classes = {"formLabel"},
				text = "Description:",
			},
			gui.Input{
				classes = {"formInput"},
				text = asset.description,
				change = function(element)
					asset.description = element.text
					asset:Upload()
				end,
			},
		},
	}

	for _,field in ipairs(brushFields) do
		local fieldInfo = DeepCopy(field)
		fieldInfo.asset = asset
		brushPropertiesFields[#brushPropertiesFields+1] = BrushField(fieldInfo)
	end

	local dialogPanel = gui.Panel{
		selfStyle = {
			width = dialogWidth,
			height = dialogHeight,
		},
		children = {
			gui.Panel{
				flow = "vertical",
				vscroll = true,
				width = "90%",
				height = "90%",
				halign = "center",
				valign = "center",

				styles = {
					{
						halign = "left",
					}
				},

				children = brushPropertiesFields,
			},

		},
	}

	resultPanel = gui.Panel{
		classes = {"framedPanel"},
		draggable = true,
		drag = function(element)
			element.x = element.xdrag
			element.y = element.ydrag
		end,

		selfStyle = {
			halign = 'center',
			valign = 'center',
			width = "auto",
			height = "auto",
		},

		styles = ThemeEngine.MergeStyles{

			Styles.Panel,
			Styles.Form,
			{
				selectors = {"formPanel"},
				valign = "top",
				height = "auto",
				width = "90%",
				halign = "center",
			},
			{
				selectors = {"formLabel"},
				textAlignment = "right",
			},
		},

		children = {
			dialogPanel,
			gui.CloseButton{
				floating = true,
				valign = "top",
				halign = "right",
				click = function(element)
					resultPanel:DestroySelf()
				end,
			},
		}
	}

	gui.ShowDialogOverMap(nil, resultPanel)
end

