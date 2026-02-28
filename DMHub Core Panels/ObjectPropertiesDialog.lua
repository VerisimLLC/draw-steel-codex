local mod = dmhub.GetModLoading()

mod.shared.objectDragAcceptors = {}

local CreateEditorPanel = function(fieldInfo, displayInfo, options, valueIndex, resultOptions)

    print("EDITOR::", fieldInfo.type)
    if fieldInfo.type == "document" then
        editorPanel = gui.Button{
            width = 96,
            height = 24,
            fontSize = 14,
            text = "Document",
			halign = "right",
			valign = "center",
            click = function(element)
                local changes =false
                local groupid = dmhub.GenerateGuid()
                local docid = nil
                local documentTable = dmhub.GetTable(MarkdownDocument.tableName or {})
                for i,fieldInstance in ipairs(fieldInfo.fieldList) do
                    local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
                    if val == nil or val == '' or documentTable[val] == nil then
                        docid = dmhub.GenerateGuid()
                        local doc = MarkdownDocument.new{
                            id = docid,
                            description = "Sign",
                            parentFolder = game.currentMapId,
                            content = "# Sign Title\nDesign this sign.",
                            annotations = {},
                        }

                        dmhub.SetAndUploadTableItem(MarkdownDocument.tableName, doc)

					    fieldInstance:SetValue(docid, valueIndex)
						fieldInstance:Upload(groupid)
                        changes = true
                    elseif docid == nil then
                        docid = val
                    end
                end

                if changes then
				    options.onchange()
                end

                if docid ~= nil then
                    local documentTable = dmhub.GetTable(MarkdownDocument.tableName or {})
                    local doc = documentTable[docid]
                    doc:ShowDocument{edit = true}
                end
            end,
        }
	elseif fieldInfo.type == 'audio' then
		editorPanel = gui.AudioEditor{
			width = 64,
			height = 64,
			halign = "right",
			valign = "center",
			value = fieldInfo.fieldList[1]:GetValue(valueIndex),

			change = function(element)
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(element.value, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid)
					end
				end

				options.onchange()
			end,
			refreshObjects = function(element)
				element.value = fieldInfo.fieldList[1]:GetValue(valueIndex)
			end,
		}
	elseif fieldInfo.type == 'assetid' then
		local dataType = fieldInfo.fieldList[1].arguments[1]
		local dataTable = nil
		if dataType == "emote" then
			dataTable = assets.emojiTable
		end

		local choices = {}

		if dataTable ~= nil then
			for k,v in pairs(dataTable) do
				choices[#choices+1] = {
					id = k,
					text = v.description,
				}
			end
		end

		table.sort(choices, function(a,b)
			return a.text < b.text
		end)

		table.insert(choices, 1, {
			id = "",
			text = "(No Asset)",
		})

		
		editorPanel = gui.Dropdown{
			hasSearch = true,
			x = -10,
			width = 100,
			height = 24,
			halign = 'right',
			valign = 'center',
			fontSize = 12,
			idChosen = fieldInfo.fieldList[1]:GetValue(valueIndex) or "",

			options = choices,
		
			events = {
				change = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.idChosen, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
					options.onchange()
				end,
				refreshObjects = function(element)
					element.idChosen = fieldInfo.fieldList[1]:GetValue(valueIndex) or ""
				end,
			},

		}
	elseif fieldInfo.type == 'image' then
		editorPanel = gui.IconEditor{
			library = fieldInfo.fieldList[1].arguments[1],
			categoriesHidden = true,
			searchHidden = true,
			bgcolor = "white",
			width = 64,
			height = 64,
			halign = "right",
			valign = "center",
			hideButton = true,
            allowNone = true,
			value = fieldInfo.fieldList[1]:GetValue(valueIndex),

			change = function(element)
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(element.value, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid)
					end
				end

				options.onchange()
			end,
			refreshObjects = function(element)
				element.value = fieldInfo.fieldList[1]:GetValue(valueIndex)
			end,
		}
	elseif fieldInfo.type == 'imageswap' then
		editorPanel = gui.Panel{
			classes = {'accept-objects'},
			width = 64,
			height = 64,
			halign = "right",
			valign = "center",
			dragTarget = true,
			dragTargetPriority = 0,
			flow = "none",

			bgimage = "panels/square.png",
			styles = {

				{
					selectors = {"accept-objects"},
					bgcolor = "black",
					borderWidth = 2,
					borderColor = "black",
				},
				{
					selectors = {"accept-objects", "drag-target"},
					borderColor = "white",
				},
				{
					selectors = {"accept-objects", "drag-target-hover"},
					borderColor = "yellow",
				},
			},

			dragObject = function(element, nodeid)
				dmhub.Debug(string.format("DRAG ONTO: %s", nodeid))
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(nodeid, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid)
					end
				end

				element:FireEvent("create")
			end,

			destroy = function(element)
				mod.shared.objectDragAcceptors[element.id] = nil
			end,

			create = function(element)
				mod.shared.objectDragAcceptors[element.id] = element

				local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
				if val == nil or val == '' then
					element.children = {
						gui.Label{
							textAlignment = "center",
							halign = "center",
							valign = "center",
							fontSize = 12,
							color = 'white',
							width = "100%",
							height = "auto",
							text = "Drag Object Here",
						}
					}
				else
					element.children = {
						gui.Panel{
							bgimage = val,
							bgcolor = 'white',
							halign = 'center',
							valign = 'center',
							width = '100%',
							height = '100%',
							imageLoaded = function(element)
								local maxDim = max(element.bgsprite.dimensions.x, element.bgsprite.dimensions.y)
								if maxDim > 0 then
									local xratio = element.bgsprite.dimensions.x/maxDim
									local yratio = element.bgsprite.dimensions.y/maxDim
									element.selfStyle.width = tostring(xratio*100) .. '%'
									element.selfStyle.height = tostring(yratio*100) .. '%'
								end
							end,
						}
					}
				end
			end,
		}
	elseif fieldInfo.type == "curve" then
		resultOptions.showLabel = false
		local ignoreCurveRefresh = 0
		local currentValue = fieldInfo.fieldList[1]:GetValue(valueIndex)

		local RecalculateEndpointGradients = function(element)
			local run = 1
			local rise = currentValue.points[#currentValue.points].y - currentValue.points[1].y

			currentValue.points[1].z = rise/run
			currentValue.points[#currentValue.points].z = rise/run
		end

		editorPanel = gui.Panel{
			bgimage = 'panels/square.png',
			bgcolor = 'black',
			height = "auto",
			width = "auto",
			flow = "vertical",
			swallowPress = true,
			refreshObjects = function(element)
				currentValue = fieldInfo.fieldList[1]:GetValue(valueIndex)
			end,
			styles = {
					{
						cornerRadius = 0,
					},
					{
						selectors = {"input"},
						priority = 20,
						width = 30,
						height = 14,
						hmargin = 6,
						pad = 2,
						fontSize = 12,
						borderWidth = 1,
						valign = "center",
					},
					{
						selectors = {"label"},
						width = "auto",
						height = "auto",
						fontSize = 16,
						valign = "center",
					},
					{
						selectors = {"curveSettings"},
						width = "100%",
						vmargin = 2,
						height = 16,
					},
			},
			gui.Panel{
				flow = "none",
				halign = "center",
				valign = "top",
				width = 200,
				height = 200,
				gui.Curve{
					halign = "left",
					valign = "top",
					width = 180,
					height = 180,
					value = currentValue,

					--this will draw lines on the chart showing where the value is currently being sampled.
					showEditorInfo = function(element)
						local info = fieldInfo.fieldList[1]:GetEditingInfo()
						if info ~= nil then
							element:FireEvent("updateEditorInfo", { x = info.x, y = info.y })
						end
					end,

					refreshObjects = function(element)
						if ignoreCurveRefresh > 0 then
							ignoreCurveRefresh = ignoreCurveRefresh-1
							return
						end
						element.value = currentValue
					end,


					confirm = function(element)
						local groupid = dmhub.GenerateGuid()
						ignoreCurveRefresh = ignoreCurveRefresh+1
						local value = element.value
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(value, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,
				},

				gui.Panel{
					floating = true,
					width = 180,
					height = 18,
					halign = "left",
					valign = "bottom",
					flow = "horizontal",
					gui.Label{
						fontSize = 12,
						width = "auto",
						height = "auto",
						halign = "left",
						valign = "center",
						text = currentValue.xmapping.x,
						refreshObjects = function(element)
							element.text = currentValue.xmapping.x
						end,
					},
					gui.Label{
						fontSize = 14,
						color = "white",
						width = "auto",
						height = "auto",
						halign = "center",
						valign = "center",
						text = displayInfo.xlabel,
						refreshObjects = function(element)
							element.text = displayInfo.xlabel
						end,
					},
					gui.Label{
						fontSize = 12,
						width = "auto",
						height = "auto",
						halign = "right",
						valign = "center",
						text = string.format("%.1f", currentValue.xmapping.y),
						refreshObjects = function(element)
							element.text = string.format("%.1f", fieldInfo.fieldList[1]:GetValue(valueIndex).xmapping.y)
						end,
					},
				},

				--labels along the right side.
				gui.Panel{
					width = 20,
					height = 180,
					halign = "right",
					valign = "top",
					flow = "vertical",


					gui.Label{
						fontSize = 10,
						width = "auto",
						height = "auto",
						halign = "center",
						valign = "top",
						text = string.format("%.1f", currentValue.displayRange.y),
						refreshObjects = function(element)
							element.text = string.format("%.1f", currentValue.displayRange.y)
						end,
					},

					gui.Label{
						fontSize = 10,
						width = "auto",
						height = "auto",
						halign = "center",
						valign = "bottom",
						text = string.format("%.1f", currentValue.displayRange.x),
						refreshObjects = function(element)
							element.text = string.format("%.1f", currentValue.displayRange.x)
						end,
					},

				},

				gui.Panel{
					width = 20,
					height = 20,
					halign = "right",
					valign = "center",
					gui.Label{
						floating = true,
						fontSize = 14,
						rotate = 270,
						halign = "center",
						valign = "center",
						color = "white",
						width = "auto",
						height = "100% width",
						text = displayInfo.ylabel,
						refreshObjects = function(element)
							element.text = displayInfo.ylabel
						end,
					},
				}


			},

			gui.Panel{
				classes = {"curveSettings"},
				gui.Label{
					color = "white",
					text = "Period:",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},
				gui.Input{
					text = currentValue.xmapping.y,
					refreshObjects = function(element)
						element.text = currentValue.xmapping.y
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local value = currentValue
						value.xmapping = { x = value.xmapping.x, y = tonumber(element.text) or 0 }
						if value.xmapping.y < value.xmapping.x+0.1 then
							value.xmapping.y = value.xmapping.x+0.1
						end
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(value, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,

				},
			},

			gui.Panel{
				classes = {"curveSettings"},

				gui.Label{
					color = "white",
					text = "Range:",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},
				gui.Input{
					text = currentValue.displayRange.x,
					refreshObjects = function(element)
						element.text = currentValue.displayRange.x
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local value = currentValue
						value.displayRange = { x = tonumber(element.text) or 0, y = value.displayRange.y }
						if value.displayRange.y < value.displayRange.x+1 then
							value.displayRange.y = value.displayRange.x+1
						end
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(value, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,

				},
				gui.Label{
					color = "white",
					text = " to ",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},
				gui.Input{
					text = currentValue.displayRange.y,
					refreshObjects = function(element)
						element.text = currentValue.displayRange.y
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local value = currentValue
						value.displayRange = { x = value.displayRange.x, y = tonumber(element.text) or 0}
						if value.displayRange.y < value.displayRange.x+1 then
							value.displayRange.y = value.displayRange.x+1
						end
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(value, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,
				},
			},

			gui.Panel{
				classes = {"curveSettings"},

				gui.Label{
					color = "white",
					text = "Value:",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},

				gui.Input{
					text = currentValue.points[1].y,
					refreshObjects = function(element)
						element.text = currentValue.points[1].y
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local num = tonumber(element.text) or 0
						currentValue.points[1] = { x = currentValue.points[1].x, y = num, z = currentValue.points[1].z }
						RecalculateEndpointGradients()
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(currentValue, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,
				},

				gui.Label{
					color = "white",
					text = " to ",
					fontSize = 12,
					width = "auto",
					height = "auto",
				},
				gui.Input{
					text = currentValue.points[#currentValue.points].y,
					refreshObjects = function(element)
						element.text = currentValue.points[#currentValue.points].y
					end,

					change = function(element)
						local groupid = dmhub.GenerateGuid()
						local num = tonumber(element.text) or 0
						currentValue.points[#currentValue.points] = { x = currentValue.points[#currentValue.points].x, y = num, z = currentValue.points[#currentValue.points].z }
						RecalculateEndpointGradients()
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(currentValue, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end,
				},

			},

		}
	elseif fieldInfo.type == 'path' then
		editorPanel = gui.Panel{
			halign = "right",
			valign = "center",
			width = 100,
			height = "auto",
			flow = "vertical",
			styles = {
				{
					wrap = false,
				},
				{
					selectors = {"button"},
					fontSize = 11,
					width = 50,
					height = 20,
					cornerRadius = 0,
				}
			},

			create = function(element)

				local text = "(no path)"
				local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
				if val ~= nil then
					local len = val.length
					if len > 0 then
						text = string.format("%d foot path", round(len*5))
					end
				end
				element.children = {
					gui.Button{
						text = "Set Path",
						click = function(button)
							element:FireEvent("setpath")
						end,
					},
					gui.Button{
						text = "Edit Path",
						click = function(button)
							element:FireEvent("editpath")
						end,
					},
                    gui.Button{
                        text = "Clear Path",
                        click = function(button)
							element:FireEvent("clearpath")
                        end,
                    },

					gui.Label{
						text = text,
						hmargin = 4,
						fontSize = 12,
						width = "auto",
						height = "auto",
					},
				}
			end,

            clearpath = function(element)
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(nil, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid) --upload if possible.
					end
                end
				element:FireEvent("create")
            end,

			setpath = function(element)
				element.children = {
					gui.Label{
						halign = "left",
						fontSize = 10,
						color = "white",
						width = "auto",
						height = "auto",
						text = "Draw path...",

						think = function(label)
							local eventSource = editor:SetMapTool{
								tool = "free",
								expires = 1,
								closed = false,
								stabilization = label:Get("objectSmoothingSlider").value,
							}

							eventSource:Listen(label)
						end,
						thinkTime = 0.5,

						tool = function(label, path)
							local groupid = dmhub.GenerateGuid()
							for i,fieldInstance in ipairs(fieldInfo.fieldList) do
								fieldInstance:SetValue(path, valueIndex)
								if options.objectInstances then
									fieldInstance:Upload(groupid) --upload if possible.
								end
							end

							element:FireEvent("create")
						end,

					},

					gui.Panel{
						width = "auto",
						height = "auto",
						flow = "horizontal",
						gui.Label{
							fontSize = 10,
							width = "auto",
							height = "auto",
							valign = "center",
							text = "Smooth:",
						},
						gui.Slider{
							id = "objectSmoothingSlider",
							value = 2,
							minValue = 0,
							maxValue = 5,
							sliderWidth = 60,
							labelWidth = 20,
							labelFormat = "%d",
							style = {
								height = 20,
								fontSize = 12,
								flow = "none",
								width = 90,
								valign = "center",
							},
							events = {
								confirm = function(element)
									
								end,
							},

						},
					},

					gui.Button{
						halign = "right",
						text = "Cancel",
						click = function(button)
							element:FireEvent("create")
						end,
					},
				}
			end,

			editpath = function(element)
				element.children = {
					gui.Label{
						halign = "left",
						fontSize = 10,
						color = "white",
						width = "auto",
						height = "auto",
						text = "Edit path...",

						think = function(label)
							local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
							local eventSource = editor:SetMapTool{
								tool = "objectpoints",
								expires = 0.5,
								path = val,
							}

							eventSource:Listen(label)
						end,
						thinkTime = 0.2,

						tool = function(label, path)
							local groupid = dmhub.GenerateGuid()
							for i,fieldInstance in ipairs(fieldInfo.fieldList) do
								fieldInstance:SetValue(path, valueIndex)
								if options.objectInstances then
									fieldInstance:Upload(groupid) --upload if possible.
								end
							end
						end,
					},

					gui.Button{
						halign = "right",
						text = "Finish",
						click = function(button)
							element:FireEvent("create")
						end,
					},
				}
			end,



		}

	elseif fieldInfo.type == 'color' then
		editorPanel = gui.ColorPicker{
			value = fieldInfo.fieldList[1]:GetValue(valueIndex),
			popupAlignment = 'left',
			hasAlpha = true,
			x = -10,
			events = {
				change = function(element)
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.value, valueIndex)
					end
				end,
				confirm = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.value, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
				end,
				refreshObjects = function(element)
					element.value = fieldInfo.fieldList[1]:GetValue(valueIndex)
				end,
			},
			styles = {
				{
					halign = 'right',
					valign = 'center',
					height = 24,
					width = 24,
					borderWidth = 2,
					borderColor = '#ffffff77',
					fontSize = '30%',
					cornerRadius = 0,
				},
				{
					selectors = 'hover',
					borderColor = '#ffffffbb',
				},
				{
					selectors = 'press',
					borderColor = '#ffffffdd',
				},
			},
		}
	elseif fieldInfo.type == 'float' then

		local minValue = fieldInfo.fieldList[1].arguments[1] or 0
		local maxValue = fieldInfo.fieldList[1].arguments[2] or 1
		local labelFormat = "%.1f"

		if maxValue >= 100 then
			labelFormat = "%d"
		end

		local fieldOptions = fieldInfo.fieldList[1].options

		local sliderWidth = options.sliderWidth or 240
		local labelWidth = options.labelWidth or 40
		editorPanel = gui.Slider{
			value = fieldInfo.fieldList[1]:GetValue(valueIndex),
			minValue = minValue,
			maxValue = maxValue,
			unclamped = true,
			sliderWidth = sliderWidth,
			labelWidth = labelWidth,
			labelFormat = labelFormat,
			wrap = fieldOptions.rotateControls,
			data = {
				randomSpread = {},

			},
			style = {
				halign = 'right',
				valign = 'center',
				bgcolor = 'white',
				fontSize = '30%',
				height = 24,
				width = math.floor((sliderWidth + labelWidth)*1.05),
				flow = 'none',
			},
			events = {
				change = function(element)
					dmhub.Debug("SLIDER:: CHANGE")
					if dmhub.modKeys.ctrl and #element.data.randomSpread == 0 then
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							element.data.randomSpread[#element.data.randomSpread+1] = {
								r = math.random(),
								startValue = element.value, --should this be for each element?
							}
						end
					end

					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						local val = element.value
						if i ~= 1 and dmhub.modKeys.ctrl then
							--when control is held we do a random value spread.
							val = lerp(element.data.randomSpread[i].startValue, val, element.data.randomSpread[i].r)
						end
						fieldInstance:SetValue(val, valueIndex)
					end
					options.onchange()
				end,
				confirm = function(element)
					local groupid = dmhub.GenerateGuid()
					printf("SLIDER:: CONFIRM: %s", groupid)
					element.data.randomSpread = {}
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						if options.objectInstances then
							fieldInstance:Upload(groupid) --upload if possible.
						end
					end
					options.onchange()
				end,
				refreshObjects = function(element)
					element.data.setValueNoEvent(fieldInfo.fieldList[1]:GetValue(valueIndex))
				end,
			},
		}

		if fieldOptions.rotateControls then
			local slider = editorPanel
			editorPanel = gui.Panel{
				halign = 'right',
				valign = 'center',
				width = "auto",
				height = "auto",
				slider,
				gui.Panel{
					width = "auto",
					height = "auto",
					flow = "horizontal",
					halign = "right",
                    rmargin = 8,
                    y = -20,
                    floating = true,

					gui.Panel{
						bgimage = "panels/hud/anticlockwise-rotation.png",
						bgcolor = "white",
						width = 16,
						height = 16,
						press = function()
							local val = slider.value
							val = val + 90
							if val >= 360 then
								val = val - 360
							end

							slider.value = val
							slider:FireEvent("confirm")
						end,
					},

					gui.Panel{
						bgimage = "panels/hud/clockwise-rotation.png",
						bgcolor = "white",
						width = 16,
						height = 16,
						press = function()
							local val = slider.value
							val = val - 90
							if val < 0 then
								val = val + 360
							end

							slider.value = val
							slider:FireEvent("confirm")
						end,
					},

				}
			}
		end
	elseif fieldInfo.type == 'vector' then
		editorPanel = gui.Panel{
			width = 140,
			height = 24,
			halign = "right",
			valign = "center",
			wrap = false,
			create = function(element)
				local fields = {"x", "y", "z"}
				local children = {}

				for _,field in ipairs(fields) do
					children[#children+1] = gui.FloatInput{
						hmargin = 3,
						bgimage = "panels/square.png",
						bgcolor = "black",
						cornerRadius = 4,
						opacity = 0.5,
						width = 40,
						valign = "center",
						halign = "center",
						allowNegative = true,
						value = fieldInfo.fieldList[1]:GetValue(valueIndex)[field],
						refreshObjects = function(element)
							element.value = fieldInfo.fieldList[1]:GetValue(valueIndex)[field]
						end,
						change = function(element)
							local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
							val[field] = element.value
							for i,fieldInstance in ipairs(fieldInfo.fieldList) do
								fieldInstance:SetValue(val, valueIndex)
							end
							options.onchange()
						end,
						confirm = function(element)
							local groupid = dmhub.GenerateGuid()
							local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
							val[field] = element.value

							for i,fieldInstance in ipairs(fieldInfo.fieldList) do
								fieldInstance:SetValue(val, valueIndex)
								if options.objectInstances then
									fieldInstance:Upload(groupid)
								end
							end
							options.onchange()
						end,
					}
				end

				element.children = children
			end,

		}
	elseif fieldInfo.type == 'int' then

		editorPanel = gui.Input{
			text = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex)),
			halign = 'right',
			valign = 'center',
			hmargin = 8,
			height = 20,
			width = 60,
			fontSize = 14,
			events = {
				change = function(element)
					local num = tonumber(element.text)
					if num ~= nil then
						local groupid = dmhub.GenerateGuid()
						num = math.floor(num)
						for i,fieldInstance in ipairs(fieldInfo.fieldList) do
							fieldInstance:SetValue(num, valueIndex)
							if options.objectInstances then
								fieldInstance:Upload(groupid)
							end
						end
					end
				end,
				refreshObjects = function(element)
					element.text = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex))
				end,
			},
		}

	elseif fieldInfo.type == 'string' then
		local multiline = fieldInfo.fieldList[1].arguments[1] or false
		editorPanel = gui.Input{
			text = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex)),
			halign = 'right',
			multiline = multiline,
			hmargin = 4,
			height = cond(multiline, "auto", 24),
			minHeight = 24,
			width = 110,
			cornerRadius = 2,
			events = {
				change = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.text, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
				end,
				refreshObjects = function(element)
					element.text = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex))
				end,
			},
		}
	elseif fieldInfo.type == 'goblinscript' then
		editorPanel = gui.GoblinScriptInput{
			value = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex)),
			width = 160,
			halign = "right",
			displayTypes = "none",

			documentation = {
				help = "This GoblinScript is used to determine if a creature passes the filter.",
				output = "boolean",
				subject = creature.helpSymbols,
				subjectDescription = "The creature being examined.",
				symbols = {},
				examples = {},
			},

			change = function(element)
				local groupid = dmhub.GenerateGuid()
				for i,fieldInstance in ipairs(fieldInfo.fieldList) do
					fieldInstance:SetValue(element.value, valueIndex)
					if options.objectInstances then
						fieldInstance:Upload(groupid)
					end
				end
			end,
			refreshObjects = function(element)
				element.value = tostring(fieldInfo.fieldList[1]:GetValue(valueIndex))
			end,
		}

	elseif fieldInfo.type == "enum" then
		editorPanel = gui.Dropdown{
			id = 'EnumDropdown',
			options = displayInfo.enum,
			idChosen = fieldInfo.fieldList[1]:GetValue(valueIndex),
			width = 180,
			height = 24,
			halign = 'left',
			valign = 'center',
			fontSize = 12,

			events = {
				change = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.idChosen, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
				end,
				refreshObjects = function(element)
					element.options = displayInfo.enum
					element.idChosen = fieldInfo.fieldList[1]:GetValue(valueIndex)
				end,
			},

		}
	elseif fieldInfo.type == 'bool' then
		editorPanel = gui.Dropdown{
			id = 'BoolDropdown',
			options = {'Yes', 'No'},
			optionChosen = cond(fieldInfo.fieldList[1]:GetValue(valueIndex), 'Yes', 'No'),
			width = 180,
			height = 24,
            fontSize = 12,
			halign = 'left',
			valign = 'center',
			events = {
				change = function(element)
					local groupid = dmhub.GenerateGuid()
					local newValue = element.optionChosen == 'Yes'
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(newValue, valueIndex)
						if options.objectInstances then
							fieldInstance:Upload(groupid)
						end
					end
				end,
				refreshObjects = function(element)
					element.optionChosen = cond(fieldInfo.fieldList[1]:GetValue(valueIndex), 'Yes', 'No')
				end,
			},
		}
	elseif fieldInfo.type == 'particle' then
		local val = fieldInfo.fieldList[1]:GetValue(valueIndex)
		local fieldOptions = fieldInfo.fieldList[1].options
		editorPanel = gui.ParticleValue{
			halign = "right",
			valign = "center",
			width = 140,
			value = val,
			allowNegative = fieldOptions.allowNegative,

			events = {
				change = function(element)
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						fieldInstance:SetValue(element.value, valueIndex)
					end
					options.onchange()
				end,
				confirm = function(element)
					local groupid = dmhub.GenerateGuid()
					for i,fieldInstance in ipairs(fieldInfo.fieldList) do
						if options.objectInstances then
							fieldInstance:Upload(groupid) --upload if possible.
						end
					end
					options.onchange()
				end,
				refreshObjects = function(element)
					element.data.setValueNoEvent(fieldInfo.fieldList[1]:GetValue(valueIndex))
				end,
			}
		}
	end

	return editorPanel
end


local CreateFieldEditor = function(fieldInfo, options)

	local displayInfo = fieldInfo.component:GetFieldDisplayInfo(fieldInfo.object, fieldInfo.id)

	local editorPanel = nil
	local resultOptions = {
		showLabel = true
	}

	local editorPanel

	if fieldInfo.array then
		editorPanel = gui.Panel{
			width = "auto",
			height = "auto",
			halign = "left",
			flow = "vertical",

			create = function(element)
				local children = {}

				for i = 1,fieldInfo.fieldList[1].count do
					local index = i
					children[#children+1] = gui.Panel{
						flow = "horizontal",

						--TODO: work out why 'auto' causes jumping problems with these.
						width = 160,
						height = "auto",
						wrap = false,

						CreateEditorPanel(fieldInfo, displayInfo, options, i, resultOptions),
						gui.CloseButton{
							width = 16,
							height = 16,
							valign = "center",
							cornerRadius = 0,
							escapeActivates = false,
							click = function(element)
								local groupid = dmhub.GenerateGuid()
								for i,fieldInstance in ipairs(fieldInfo.fieldList) do
									fieldInstance:Remove(index)
									if options.objectInstances then
										element.parent:DestroySelf()
										fieldInstance:Upload(groupid)
									end
								end
							end,
						},
					}
				end

                local emptyLabel = nil
                if fieldInfo.fieldList[1].count == 0 then
                    emptyLabel = gui.Label{
                        fontSize = 10,
                        valign = "center",
                        hmargin = 4,
                        text = string.format("%s empty", fieldInfo.prettyName),
                        width = "auto",
                        height = "auto",
                    }
                end

				children[#children+1] =
                gui.Panel{
                    flow = "horizontal",
                    width = "auto",
                    height = "auto",
                    gui.AddButton{
                        cornerRadius = 0,
                        click = function(element)
                            local groupid = dmhub.GenerateGuid()
                            for i,fieldInstance in ipairs(fieldInfo.fieldList) do
                                fieldInstance:Append()
                                if options.objectInstances then
                                    fieldInstance:Upload(groupid)
                                end
                            end

                            element:FireEventOnParents("refreshObjects")
                        end
                    },
                    emptyLabel,
                }

				element.children = children
			end,

			refreshObjects = function(element)
				element:FireEvent("create")
			end,
		}
	else
		editorPanel = CreateEditorPanel(fieldInfo, displayInfo, options, 1, resultOptions)
	end

	local resultPanel = gui.Panel{
		bgimage = 'panels/square.png',
		classes = {'field-editor-panel', cond(displayInfo ~= nil and displayInfo.hidden, 'collapsed')},
        flow = "vertical",
        height = "auto",
		refreshObjects = function(element)
			displayInfo = fieldInfo.component:GetFieldDisplayInfo(fieldInfo.object, fieldInfo.id)
			element:SetClass('collapsed', displayInfo ~= nil and displayInfo.hidden)
		end,
		children = {
			gui.Label{
				text = fieldInfo.prettyName,
				classes = {'field-description-label', cond(resultOptions.showLabel, nil, 'collapsed')},
				selfStyle = {
					hmargin = 4,
                    bmargin = 4,
				},
			},

            gui.Panel{
			    editorPanel,
                hmargin = 4,
                width = "auto",
                height = "auto",
                halign = "left",
            },
		},
	}

	return resultPanel
end

local CreateArtistAndKeywordsPanel = function(nodes, options)

	local node = nodes[1]

	local keywordsProperty = nil
	
	if options.blueprint then
		keywordsProperty = node.keywords or ''
	end

	local artistProperty = node.artist
	for i,node in ipairs(nodes) do
		if keywordsProperty ~= nil and keywordsProperty ~= node.keywords then
			keywordsProperty = nil
		end
		if artistProperty ~= node.artist then
			artistProperty = 'multi'
		end
	end

	local artistInfo = nil
	local artistOptions = { { id = 'null', text = '(None)' } }
	for key,option in pairs(assets.artists) do
		artistOptions[#artistOptions+1] = { id = key, text = option.name }
		if key == artistProperty then
			artistInfo = option
		end
	end

	if artistProperty == nil then
		artistProperty = 'null'
	elseif artistProperty == 'multi' then
		artistOptions[#artistOptions+1] = { id = 'multi', text = '(Multiple values)' }
	end

	local artistPanel = nil
	
	if (dmhub.isAdminAccount and options.blueprint) then

		local fieldPanel = gui.Dropdown{
			id = 'artist-dropdown',
			options = artistOptions,
			idChosen = artistProperty,
			style = {
				valign = "center",
				fontSize = '30%',
				width = '50%',
				height = 34,
				cornerRadius = 0,
			},
			events = {
				change = function(element)
					for i,n in ipairs(nodes) do
						n.artist = element.idChosen
					end
				end,
			},
		}

		artistPanel = gui.Panel{
			selfStyle = {
				width = "100%",
				height = "auto",
				flow = "horizontal",
				hmargin = 0,
				vmargin = 0,
			},
			children = {
				gui.Label{
					classes = {'property-label'},
					text = 'Artist:',
				},
				fieldPanel,

			},
		}
	end

	return gui.Panel{
		id = "ArtistsAndKeywords",
		style = {
			vmargin = 2,
		},
		children = {
			artistPanel,
		},
	}
end

local CreateObjectEditor = function(nodes, options)

	local mainPanel

	local previewFloor = nil

	local previewType
	
	if not options.objectInstances then
		previewType = nodes[1].previewType
		previewFloor = game.currentMap:CreatePreviewFloor("ObjectPreview")

	end

	local objectLocked = false
	
	if options.objectInstances then
		objectLocked = nodes[1].locked
	end

	local previewTimeOfDayIndex = 1

	options = options or {}

	local previewTokenId = nil
	local previewObjects = nil

	local selectedComponentName = nil

	options.onchange = function() end

	if options.objectInstances then
		for i,node in ipairs(nodes) do
			node:MarkUndo()
			if selectedComponentName == nil and node.editingInfo ~= nil then
				selectedComponentName = node.editingInfo.selectedComponentName
			end
		end

	end

	if not options.objectInstances then
		options.onchange = function()

			if previewTokenId ~= nil then
				local token = dmhub.GetTokenById(previewTokenId)
				if token ~= nil then
					token:InvalidateObjects()
				end
			end
		end
	end


	local components
	
	local CalculateComponents = function()
		components = {}

		local startingComponentName = nil
		local startingComponentPriority = nil
		for i,node in ipairs(nodes) do
			local ordinals = {} --mapping of name -> number of components of this name we have.
			for k,component in pairs(node.components) do
				local name = component.name
				local ordinal = ordinals[name] or 0
				ordinals[name] = ordinal+1

				component.ordinal = ordinal

				if ordinal > 0 then
					name = string.format("%s-%d", name, ordinal)
				end

				if startingComponentPriority == nil or component.displayPriority < startingComponentPriority then
					startingComponentName = name
					startingComponentPriority = component.displayPriority
				end

				components[name] = components[name] or {
					componentsList = {},
					name = name,
				}
				local componentsList = components[name].componentsList
				componentsList[#componentsList+1] = {
					object = node,
					componentid = k,
					component = component,
				}
			end
		end

		if selectedComponentName == nil then
			selectedComponentName = startingComponentName
		end

		--fill up the components and previews lists to include preview elements.
		for k,component in pairs(components) do
			local componentsAndPreviews = {}
			for i,element in ipairs(component.componentsList) do
				componentsAndPreviews[#componentsAndPreviews+1] = element
			end
			component.componentsAndPreviews = componentsAndPreviews
		end

		if not options.objectInstances then
			if previewObjects ~= nil then
				for _,obj in ipairs(previewObjects) do
					obj:Destroy()
				end
			end

			--create preview object instances. These are objects in the preview scene.
			previewObjects = {}
			for i,node in ipairs(nodes) do
				local previews = {}

				if previewType == "wield" then
					if previewTokenId == nil then
						previewTokenId = previewFloor:CreateToken(-20, 0)

						dmhub.ScheduleWhen(function() return dmhub.GetTokenById(previewTokenId) ~= nil end,
						function()

							local token = dmhub.GetTokenById(previewTokenId)

							previewFloor.cameraPos = {x = -20, y = 0}
							previewFloor.cameraSize = 1


							local itemid = nil
							local gearTable = dmhub.GetTable("tbl_Gear")
							for k,v in pairs(gearTable) do
								if v:try_get("itemObjectId") == node.id then
									itemid = k
								end
							end

							if itemid ~= nil then
								token.wieldedObjectsOverride = {
									mainhand = itemid,
								}
							end
							game.Refresh()
						end)

					else
						local token = dmhub.GetTokenById(previewTokenId)
						if token ~= nil then
							token:InvalidateObjects()
						end

					end
				else


					local objects = {}
					local newObj = previewFloor:CreateObjectCopy(node)
					newObj.x = 1
					newObj.y = -2
					previewObjects[#previewObjects+1] = newObj

					local newObj = previewFloor:CreateObjectCopy(node)
					newObj.x = 1
					newObj.y = 3
					previewObjects[#previewObjects+1] = newObj

					for i,obj in ipairs(previewObjects) do
						previews[#previews+1] = obj
						for k,component in pairs(obj.components) do
							local name = component.name
							local componentsAndPreviews = components[name].componentsAndPreviews
							componentsAndPreviews[#componentsAndPreviews+1] = {
								object = obj,
								componentid = k,
								component = component,
							}
						end
					end

				end

			end
			game.Refresh()
		end
	end

	CalculateComponents()

	local propertiesLabel = gui.Label{
		classes = {"label-text"},
		text = "Properties",
	}

	local leftPanel

	local addText = options.addPropertyText or "Add Property..."

	local multiComponents = {
		["Path Animation"] = true,
		["Animation Curve"] = true,
		["Mount"] = true,
		["Light"] = true,
	}

	local addPropertiesOptions = assets.objectComponentOptions
	addPropertiesOptions[#addPropertiesOptions+1] = addText

	local artistAndKeywordsPanel = CreateArtistAndKeywordsPanel(nodes, options)

	local editorPanel

	leftPanel = gui.Panel{
		bgimage = 'panels/square.png',
		classes = {'left-panel'},
		vscroll = true,
		selfStyle = {
			cornerRadius = 8,
			bgcolor = '#33333399',
		},
		styles = {
			{
				flow = 'vertical',
				valign = 'top',
				hmargin = 8,
				vmargin = 8,
				borderWidth = 0,
			},
			{
				selectors = {'component-header'},
				bgcolor = '#444444',
				color = '#dddddd',
				fontSize = 14,
				width = '90%',
				height = 30,
				valign = 'top',
				halign = cond(options.objectInstances, 'left', 'center'),
				textAlignment = 'center',
				borderWidth = 1,
				borderColor = '#bbbbbb',
				cornerRadius = 4,
			},
			{
				--style to use when only some objects have this component.
				selectors = {'component-header','incomplete'},
				color = '#aaaaaa',
			},
			{
				selectors = {'component-header','hover'},
				color = '#ffffff',
				borderColor = '#ffffff',
				fontSize = 18,
			},
			{
				selectors = {'component-header','press'},
				bgcolor = '#555555',
				borderColor = '#dddddd',
			},
			{
				selectors = {'component-header','selected'},
				borderColor = '#ffffff',
				borderWidth = 2,
			},
			{
				selectors = {'component-header','disabled'},
				brightness = 0.4,
				italics = true,
			},
		},
		children = {
			propertiesLabel,
		},

		events = {
			create = function(element)
				local children = {}
				for k,componentInfo in pairs(components) do
					local componentName = k
					local completeClass = cond(#componentInfo.componentsList == #nodes, 'complete', 'incomplete')
					componentInfo.panel = componentInfo.panel or gui.Label{
						bgimage = 'panels/square.png',
						text = componentInfo.name,
						classes = {'component-header', cond(componentInfo.componentsList[1].component.disabled, "disabled"), completeClass},
						data = {
							ord = componentInfo.componentsList[1].component.displayPriority,
						},
						events = {
							hover = gui.Tooltip(componentInfo.componentsList[1].component.tooltip),
							click = function(element)
								if components[selectedComponentName] ~= nil and components[selectedComponentName].panel ~= nil then
									components[selectedComponentName].panel:SetClass('selected', false)
								end
								selectedComponentName = componentName
								element:SetClass('selected', true)

								--mark our selected component so we can restore it when this object is re-selected.
								if options.objectInstances then
									for i,node in ipairs(nodes) do
										if node.editingInfo == nil then
											node.editingInfo = {}
										end

										node.editingInfo.selectedComponentName = selectedComponentName
									end
								end

								editorPanel:FireEventTree('refresh')
							end,
							rightClick = function(element)

								local menuItems = {}

								local obj = components[componentName].componentsList[1].object

								if componentInfo.componentsList[1].component.deletable then

									local disable = not componentInfo.componentsList[1].component.disabled

									menuItems[#menuItems+1] = {
										text = cond(componentInfo.componentsList[1].component.disabled, 'Enable Property', 'Disable Property'),
										click = function()
											for i,entry in ipairs(components[componentName].componentsList) do
												entry.component.disabled = disable
												break
											end
											componentInfo.panel:SetClass("disabled", disable)
											element.popup = nil
										end,
									}
								end

								if obj ~= nil and obj:IsValidComponentJson(dmhub.GetInternalClipboard()) then
									menuItems[#menuItems+1] = {
										text = "Paste Property",
										click = function()
											local groupid = dmhub.GenerateGuid()
											for i,entry in ipairs(components[componentName].componentsList) do
												entry.object:ConstructComponent(dmhub.GetInternalClipboard())
												entry.object:Upload(groupid)
											end
											element.popup = nil
											CalculateComponents()
											leftPanel:FireEvent('create') --refresh list of properties available for this object.
										end,
									}
								end

								menuItems[#menuItems+1] = {
									text = 'Copy Property',
									click = function()
										for i,entry in ipairs(components[componentName].componentsList) do
                                            print("JSON:: COPY PROPERTY...")
											dmhub.CopyToInternalClipboard(entry.object:ComponentToJson(entry.componentid))
											break
										end
										element.popup = nil
									end,
								}

								if (not objectLocked) and components[componentName].componentsList[1].component.deletable then
									menuItems[#menuItems+1] = {
										text = 'Delete Property',
										click = function()
											local groupid = dmhub.GenerateGuid()
											for i,entry in ipairs(components[componentName].componentsList) do
												entry.object:RemoveComponent(entry.componentid)
												entry.object:Upload(groupid)
											end

											element.popup = nil
											components[componentName] = nil
											if selectedComponentName == componentName then
												selectedComponentName = 'Core'
												editorPanel:FireEventTree('refresh')
											end
											leftPanel:FireEventTree('create')

											CalculateComponents()
										end,
									}
								end

								if #menuItems > 0 then
									element.popup = gui.ContextMenu{
										entries = menuItems
									}
								end
							end,
						},
					}

					componentInfo.panel:SetClass('selected', selectedComponentName == k)

					children[#children+1] = componentInfo.panel
				end

				table.sort(children, function(a,b)
					return a.data.ord < b.data.ord
				end)

				--now we have sorted, put the properties label first.
				table.insert(children, 1, propertiesLabel)

				local addPropertiesDropdown = gui.Dropdown{
					options = addPropertiesOptions,
					idChosen = "none",
					textOverride = addText,
					menuWidth = 200,
					classes = {'add-property-dropdown'},
					events = {
						create = function(element)
							local options = {}
							local availableOptions = assets.objectComponentOptions
							for i,optionInfo in ipairs(availableOptions) do
								if optionInfo.submenu ~= nil then
									local submenuOptions = {}
									for i,subOptionInfo in ipairs(optionInfo.submenu) do
										if components[subOptionInfo.id] == nil or #components[subOptionInfo.id].componentsList < #nodes or multiComponents[subOptionInfo.id] then
											submenuOptions[#submenuOptions+1] = subOptionInfo
										end
									end

									if #submenuOptions > 0 then
										options[#options+1] = {
											text = optionInfo.text,
											submenu = submenuOptions,
										}
									end
								else
									if components[optionInfo.id] == nil or #components[optionInfo.id].componentsList < #nodes or multiComponents[optionInfo.id] then
										options[#options+1] = optionInfo
									end
								end
							end
							element.options = options
						end,
						change = function(element)
							local groupid = dmhub.GenerateGuid()
							local componentName = element.optionChosen
							for i,node in ipairs(nodes) do
								local hasComponent = false
								for k,component in pairs(node.components) do
									local name = component.name
									if name == componentName then
										hasComponent = true
									end
								end

								if hasComponent == false or multiComponents[element.optionChosen] then
									node:AddComponent(componentName)
									if options.objectInstances then
										node:Upload(groupid)
									end
								end
							end

							CalculateComponents()
							element:FireEvent('create') --refresh this dropdown to only have properties not available.
							element.idChosen = "none"
							leftPanel:FireEvent('create') --refresh list of properties available for this object.

							--wait a moment, then select the new component.
							dmhub.Schedule(0.05, function()
								if element == nil or not element.valid then
									return
								end
								for k,component in pairs(components) do
									if component.name == componentName then
										component.panel:FireEvent('click')
									end
								end
							end)
						end,

						lock = function(element, lock)
							element:SetClass("hidden", lock)
						end,
					},
				}

				children[#children+1] = addPropertiesDropdown
				children[#children+1] = artistAndKeywordsPanel

				element.children = children
			end,
		},
	}

	local lockPanel = gui.Panel{
		classes = {"hidden"},
		floating = true,
		bgimage = "panels/square.png",
		bgcolor = "black",
		opacity = 0.9,
		width = "100%",
		height = "100%-60",
		valign = "bottom",
		lock = function(element, lock)
			element:SetClass("hidden", not lock)
		end,

		gui.Panel{
			bgimage = "icons/icon_tool/icon_tool_30.png",
			halign = "center",
			valign = "center",
			bgcolor = "white",
			width = 128,
			height = 128,
		},
	}

	local fieldsPanel = gui.Panel{
		vscroll = true,
		thinkTime = 0.1,
		styles = {
			{
				flow = 'horizontal',
				valign = 'top',
				width = cond(options.objectInstances, '100%', '90%'),
				height = "100% available", --cond(options.objectInstances, cond(dmhub.GetSettingValue("dev"), '80%', '90%'), '50%'),
				borderWidth = 0,
				wrap = true,
			}
		},
		children = {
		},
		events = {
			create = function(element)
				element:FireEventTree('refresh')
			end,
			think = function(element)
				local componentInfo = components[selectedComponentName]
				if componentInfo == nil then
					return
				end
				for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
					componentInfo.component:ThinkEdit()
				end

			end,
			refresh = function(element)
				local componentInfo = components[selectedComponentName]
				if componentInfo == nil then
					for k,component in pairs(components) do
						if componentInfo == nil then
							selectedComponentName = k
							componentInfo = component
						end
					end

					if componentInfo == nil then
						return
					end
				end
				local children = {}
				local fieldInfo = {}
				local fieldKeysOrdered = {}
				for i,component in ipairs(componentInfo.componentsAndPreviews) do
					local fields = component.component.fields
					for i,field in ipairs(fields) do
						if fieldInfo[field.id] == nil then
							fieldKeysOrdered[#fieldKeysOrdered+1] = field.id
						end
						fieldInfo[field.id] = fieldInfo[field.id] or { type = field.fieldType, array = field.array, id = field.id, prettyName = field.prettyName, fieldList = {}, object = component.component.objectInstance, component = component.component }
						local fieldList = fieldInfo[field.id].fieldList
						fieldList[#fieldList+1] = field
					end
				end

				local groupedPanels = {}
				local groupedPanelsChildren = {}

				for _,fieldName in ipairs(fieldKeysOrdered) do
					local fieldEntry = fieldInfo[fieldName]
					local fieldOptions = fieldEntry.fieldList[1].options
					local editor = CreateFieldEditor(fieldEntry, options)

					if type(fieldOptions.group) == "string" then
						local group = groupedPanels[fieldOptions.group]

						if group == nil then
							local childrenPanel = gui.Panel{
								classes = {"groupingPanel", "collapsed"},
								flow = "vertical",
								width = "100%",
								height = "auto",
								vpad = 5,
							}
							group = gui.Panel{
								width = "95%",
								height = "auto",
								flow = "vertical",
								bgimage = 'panels/square.png',
								bgcolor = "#222222ff",
								cornerRadius = 12,
								vmargin = 4,

								styles = {
									{
										wrap = false,
									},
								},

								gui.Panel{
									flow = "horizontal",
									width = "90%",
									height = "auto",
									halign = "left",
                                    hpad = 2,
									vpad = 0,
									gui.Panel{
										bgimage = 'panels/triangle.png',
										styles = gui.TriangleStyles,
										press = function(element)
											element:SetClass("expanded", not element:HasClass("expanded"))
											childrenPanel:SetClass("collapsed", not element:HasClass("expanded"))
										end,
									},
									gui.Label{
										fontSize = 14,
										width = "auto",
										height = "auto",
										text = fieldOptions.group,
									},
								},

								childrenPanel,
							}
							groupedPanels[fieldOptions.group] = group
							groupedPanelsChildren[fieldOptions.group] = {}
							children[#children+1] = group
						end

						local childList = groupedPanelsChildren[fieldOptions.group]
						childList[#childList+1] = editor
					else
						children[#children+1] = editor
					end
				end

				--assign the children to the grouped panels.
				for k,v in pairs(groupedPanels) do
					local panelChildren = groupedPanelsChildren[k]
					v.children[2].children = panelChildren
				end

                local customEditor
				if #componentInfo.componentsAndPreviews == 1 then
					local component = componentInfo.componentsAndPreviews[1].component
					customEditor = component:CreateCustomEditor()

                elseif #componentInfo.componentsAndPreviews > 1 then
                    local components = {}
                    for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
                        local component = componentInfo.component
                        components[#components+1] = component
                    end

					local component = componentInfo.componentsAndPreviews[1].component
					customEditor = component:CreateMultiCustomEditor(components)
				end

				if customEditor ~= nil then

					local containerPanel = gui.Panel{
						bgimage = 'panels/square.png',
						classes = {'field-editor-panel'},
						refreshObjects = function(element)
						end,

						customEditor,
					}

					children[#children+1] = containerPanel
				end




				--add command buttons.
                local commandsAdded = {}
				for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
					for j,cmd in ipairs(componentInfo.component.commands) do
						children[#children+1] = gui.Button{
							text = cmd,
							fontSize = 12,
							width = 120,
							height = 20,
							vmargin = 8,
							halign = "right",
							hmargin = 40,
							cornerRadius = 0,
							click = function(element)
                                local commands = commandsAdded[cmd]
                                for _,fn in ipairs(commands) do
                                    fn()
                                end
							end,
						}

                        commandsAdded[cmd] = commandsAdded[cmd] or {}
                        commandsAdded[cmd][#commandsAdded[cmd]+1] = function()
                            componentInfo.component:Execute(cmd)
                        end
					end
				end

				if selectedComponentName == "Core" and options.objectInstances then

					children[#children+1] = gui.Button{
						text = "Save to Blueprint",
						fontSize = 12,
						width = 140,
						height = 20,
						vmargin = 8,
						halign = "right",
						hmargin = 40,
						cornerRadius = 0,
						click = function(element)

							for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
								componentInfo.component:UpdateBlueprint(false)
							end
						end,
					}

					children[#children+1] = gui.Button{
						text = "Save to New Blueprint",
						fontSize = 12,
						width = 140,
						height = 20,
						vmargin = 8,
						halign = "right",
						hmargin = 40,
						cornerRadius = 0,
						click = function(element)
							for i,componentInfo in ipairs(componentInfo.componentsAndPreviews) do
								componentInfo.component:UpdateBlueprint(true)
							end
						end,
					}

				end

				element.children = children
			end,
		},
	}

	local lockIcon = nil

	if options.objectInstances then
		lockIcon = gui.Panel{
			bgimage = cond(objectLocked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png"),
			bgcolor = cond(objectLocked, "white", "grey"),
			width = 16,
			height = 16,
			halign = "right",
			valign = "right",
			vmargin = 12,
            hmargin = 8,
			press = function(element)
				objectLocked = not objectLocked
				element.bgimage = cond(objectLocked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png")
				element.selfStyle.bgcolor = cond(objectLocked, "white", "grey")
				local groupid = dmhub.GenerateGuid()
				for i,currentNode in ipairs(nodes) do
					currentNode.locked = objectLocked
					currentNode:Upload(groupid)
				end

				mainPanel:FireEventTree("lock", objectLocked)
			end,
		}
	end

	local idPanel

	if dmhub.GetSettingValue("dev") then
		idPanel = gui.Panel{
			bgimage = "panels/square.png",

			selfStyle = {
				vmargin = 8,
			},

			styles = {
				{
					cornerRadius = 8,
					width = '90%',
					height = '40',
					bgcolor = '#33333399',
					flow = 'none',
					borderWidth = 0,
					valign = 'top',
				}
			},

			click = function(element)
				dmhub.CopyToClipboard(nodes[1].id)
				gui.Tooltip("copied to clipboard")(element)
			end,

			gui.Label{
				classes = {'field-description-label', 'field-name-label'},
				bgimage = 'panels/square.png',
				selfStyle = {
					halign = 'center',
					valign = 'center',
					textAlignment = 'center',
				},

				text = nodes[1].id,
			}
		}
	end

	local childObjectsPanel = nil

	if options.objectInstances and #nodes == 1 then
		local childids = nodes[1].childids
		if childids ~= nil and #childids > 0 then
			local m_childrenLocked = false
			for _,childid in ipairs(childids) do
				local childNode = game.currentFloor:GetObject(childid)
				if childNode ~= nil and childNode.locked then
					m_childrenLocked = true
					break
				end
			end
			childObjectsPanel = gui.Panel{
				bgimage = 'panels/square.png',
				vmargin = 8,
				cornerRadius = 8,
				width = '90%',
				height = 40,
				bgcolor = '#33333399',
				flow = 'horizontal',
				borderWidth = 0,
				valign = 'top',

				gui.Label{
					text = string.format("Child Objects: %d", #childids),
					classes = {'field-description-label', 'field-name-label'},
					halign = "left",
					valign = "center",
				},

				gui.Panel{
					bgimage = cond(m_childrenLocked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png"),
					bgcolor = cond(m_childrenLocked, "white", "grey"),
					width = 16,
					height = 16,
					halign = "right",
					valign = "right",
					vmargin = 12,
					press = function(element)
						m_childrenLocked = not m_childrenLocked
						element.bgimage = cond(m_childrenLocked, "icons/icon_tool/icon_tool_30.png", "icons/icon_tool/icon_tool_30_unlocked.png")
						element.selfStyle.bgcolor = cond(m_childrenLocked, "white", "grey")
						
						local cmdgroup = dmhub.GenerateGuid()

						for _,childid in ipairs(childids) do
							local childNode = game.currentFloor:GetObject(childid)
							if childNode ~= nil then
								childNode.locked = m_childrenLocked
								childNode:Upload(cmdgroup)
							end
						end
					end,
				},
			}
		end
	end

	local multiselectPanel = nil

	local needMultiselect = false
	if options.objectInstances and #nodes > 1 then
		local assetid = nodes[1].assetid
		for _,node in ipairs(nodes) do
			if node.assetid ~= assetid then
				needMultiselect = true
				break
			end
		end
	end

	if needMultiselect then

		local children = {}

		local assetidToIndex = {}

		for _,node in ipairs(nodes) do
			local imageid = node.imageid
			local index = assetidToIndex[imageid] or (#children+1)
			if index > 32 then
				break
			end

			children[index] = children[index] or gui.Panel{
				classes = {"multiPanel"},
				flow = "none",
				data = {
					nodes = {},
				},

				gui.Panel{
					autosizeimage = true,
					maxWidth = 32,
					maxHeight = 32,
					halign = "center",
					valign = "center",
					bgcolor = "white",
					bgimage = imageid,
				},

				gui.Label{
					halign = "right",
					valign = "bottom",
					bgcolor = "black",
					bgimage = "panels/square.png",
					borderFade = true,
					borderWidth = 2,
					cornerRadius = 3,
					pad = 2,
					fontSize = 10,
					color = "white",
					width = "auto",
					height = "auto",

					quantity = function(element, quantity)
						element:SetClass("hidden", quantity <= 1)
						element.text = "x" .. tostring(quantity)
					end,

				},

				gui.DeleteItemButton{
					halign = "right",
					valign = "top",
					width = 12,
					height = 12,
					click = function(element)
						if options.recreate ~= nil then
							local newNodes = {}
							for i,node in ipairs(nodes) do
								if node.imageid ~= imageid then
									newNodes[#newNodes+1] = node
								end
							end
							options.recreate(mainPanel, newNodes)
						end
					end,

				}
			}

			assetidToIndex[imageid] = index

			local child = children[index]
			child.data.nodes[#child.data.nodes+1] = node
			child:FireEventTree("quantity", #child.data.nodes)
		end

		multiselectPanel = gui.Panel{
			bgimage = 'panels/square.png',

			vmargin = 8,
			cornerRadius = 8,
			width = '90%',
			height = "auto",
			bgcolor = '#33333399',
			flow = 'horizontal',
			wrap = true,
			borderWidth = 0,
			valign = 'top',

			styles = {
				{
					selectors = {"multiPanel"},
					width = 32,
					height = 32,
				},
				{
					selectors = {"deleteItemButton"},
					opacity = 0,
				},
				{
					selectors = {"deleteItemButton", "parent:hover"},
					opacity = 1,
				},
			},

			children = children,
		}
	end



	local namePanel = gui.Panel{
		bgimage = 'panels/square.png',

		selfStyle = {
			vmargin = 8,
		},

		styles = {
			{
				cornerRadius = 8,
				width = '90%',
				height = '40',
				bgcolor = '#33333399',
				flow = 'none',
				borderWidth = 0,
				valign = 'top',
			}
		},

		children = {
            gui.Panel{
                flow = "vertical",
                width = "auto",
                height = "auto",
                halign = "left",
                valign = "center",
                gui.Label{
                    text = 'Name:',
                    classes = {'field-description-label'},
                    styles = {
                        {
                            hmargin = 4,
                            halign = 'left',
                            valign = 'center',
                        }
                    }
                },

                gui.Label{
                    text = nodes[1].description,
                    editable = not options.objectInstances,
                    classes = {'field-description-label', 'field-name-label'},
                    bgimage = 'panels/square.png',
                    selfStyle = {
                        halign = 'left',
                        valign = 'center',
                        hmargin = 4,
                        fontSize = 14,
                        bold = true,
                    },
                    events = {
                        change = function(element)
                            for i,node in ipairs(nodes) do
                                node.description = element.text
                            end
                        end,
                    },
                },
            },

			lockIcon,
		}
	}

	local keywordsPanel = nil
	
	if not options.objectInstances then
		keywordsPanel = gui.Panel{
			bgimage = 'panels/square.png',
			selfStyle = {
				vmargin = 8,
			},

			styles = {
				{
					cornerRadius = 8,
					width = '90%',
					height = '40',
					bgcolor = '#33333399',
					flow = 'none',
					borderWidth = 0,
					valign = 'top',
				}
			},
			children = {
				gui.Label{
					text = 'Keywords:',
					classes = {'field-description-label'},
					styles = {
						{
							hmargin = 4,
							halign = 'left',
							valign = 'center',
						}
					}
				},

				gui.Input{
					text = nodes[1].keywords,
					placeholderText = "Enter Keywords...",
					editable = not options.objectInstances,
					classes = {'field-description-label', 'field-name-label'},
					bgimage = 'panels/square.png',
					selfStyle = {
						width = 400,
						halign = 'center',
						valign = 'center',
						textAlignment = 'left',
					},
					events = {
						change = function(element)
							for i,node in ipairs(nodes) do
								node.keywords = element.text
							end
						end,
					},
				},

				lockIcon,
			}
		}
	end



	local previewImage
	local previewSelector

	if not options.objectInstances then

		previewImage = gui.Panel{
			id = "MapPreviewImage",
			bgimage = "#MapPreview" .. previewFloor.floorid,
			selfStyle = {
				bgcolor = "white",
				halign = 'center',
				width = 960/2,
				height = 540/2,
			},

			destroy = function(element)
				game.currentMap:DestroyPreviewFloor(previewFloor)
				game.Refresh()
			end,
		}
		--[[
		local timeofdayLabel = gui.Label{
			text = PreviewLightingTypes[previewTimeOfDayIndex],
			selfStyle = {
				height = "100%",
				width = 200,
				textAlignment = 'center',
			},
			events = {
				refresh = function(element)
					element.text = PreviewLightingTypes[previewTimeOfDayIndex]
				end,
			},
		}
		previewSelector = gui.Panel{
			styles = {
				{
					width = 960/2,
					height = 40,
					flow = "horizontal",
					halign = "center",
					valign = "center",
					bgcolor = 'white',
					fontSize = "40%",
					borderWidth = 0,
				},
				{
					selectors = {"paging-arrow"},
					height = "100%",
					width = "50% height",
				},
				{
					selectors = {'hover', 'paging-arrow'},
					brightness = 2,
					scale = 1.2,
				},
				{
					selectors = {'press', 'paging-arrow'},
					brightness = 0.7,
				},
			},
			children = {
				gui.Panel{
					classes = {"paging-arrow"},
					bgimage = "panels/InventoryArrow.png",
					events = {
						click = function(element)
							previewTimeOfDayIndex = previewTimeOfDayIndex-1
							if previewTimeOfDayIndex < 1 then
								previewTimeOfDayIndex = #PreviewLightingTypes
							end
							timeofdayLabel:FireEvent("refresh")
							previewScene:SetTimeOfDay(PreviewLightingTypes[previewTimeOfDayIndex])
						end,
					},
				},
				timeofdayLabel,
				gui.Panel{
					classes = {"paging-arrow"},
					bgimage = "panels/InventoryArrow.png",
					selfStyle = {scale = {x = -1, y = 1}},
					events = {
						click = function(element)
							previewTimeOfDayIndex = previewTimeOfDayIndex+1
							if previewTimeOfDayIndex > #PreviewLightingTypes then
								previewTimeOfDayIndex = 1
							end
							timeofdayLabel:FireEvent("refresh")
							previewScene:SetTimeOfDay(PreviewLightingTypes[previewTimeOfDayIndex])
						end,
					},
				},
			},
		}
		--]]
	end

	editorPanel = gui.Panel{
		classes = {'editor-panel'},
		children = {
			multiselectPanel,
			namePanel,
			childObjectsPanel,
			idPanel,
			keywordsPanel,
			previewImage,
			previewSelector,
			fieldsPanel,
			lockPanel,
		},
	}

	mainPanel = gui.Panel{
		id = 'MainObjectPropertiesPanel',
		children = {
			leftPanel,
			editorPanel,
		},
		events = {
			refreshGame = function(element)

				--when refreshing the game, check that components are still valid, and remove any that aren't.
				local deletes = {}
				for componentKey,info in pairs(components) do
					local removeComponents = false
					for _,item in ipairs(info.componentsList) do
						if item.component == nil or not item.component.valid then
							removeComponents = true
						end
					end

					if removeComponents then
						local newComponents = {}
						for _,item in ipairs(info.componentsList) do
							if item.component ~= nil and item.component.valid then
								newComponents[#newComponents+1] = item
							end
						end

						info.componentsList = newComponents

						if #info.componentsList == 0 then
							deletes[#deletes+1] = componentKey
						end
					end
				end

				--if any components have been removed from all selected objects (the common case when components are deleted)
				--then remove their entries and fire appropriate events.
				if #deletes > 0 then
					local refreshSelected = false
					for _,del in ipairs(deletes) do
						components[del] = nil
						if selectedComponentName == del then
							refreshSelected = true
						end
					end

					if refreshSelected then
						selectedComponentName = 'Core'
						editorPanel:FireEventTree('refresh')
					end
					leftPanel:FireEventTree('create')
				end

				if element.enabled then
					element:FireEventTree("refreshObjects")
				end


			end,
		},
	}

	--monitor the game objects and if they change we want to trigger a refresh
	if options.objectInstances then
		mainPanel.monitorGame = dmhub.activeObjectsPath
	end

	if objectLocked then
		mainPanel:FireEventTree("lock", true)
	end
	
	return mainPanel
end

local m_objectEditor = nil

local function CreateObjectEditorPanel()
	local DialogWidth = 440
	local DialogHeight = 500
	if dmhub.GetSettingValue("dev") then
		DialogHeight = DialogHeight + 60
	end
	local resultPanel
	resultPanel = gui.Panel{
		classes = {"framedPanel"},
		draggable = true,

		destroy = function(element)
			if m_objectEditor == element then
				m_objectEditor = nil
			end
		end,

		beginDrag = function(element)
		end,

		drag = function(element, target)
			element.x = element.x + element.dragDelta.x
			element.y = element.y + element.dragDelta.y
		end,

		styles = {
			Styles.Panel,

			{
				width = DialogWidth,
				height = DialogHeight,
				flow = 'vertical',
				halign = "left",
				valign = "top",
			},
			{
				selectors = {"framedPanel", "hasBanner"},
				height = DialogHeight + DialogWidth/4 + 8,
			},
			{
				selectors = {"framedPanel"},
				collapsed = 1,
				opacity = 0,
				uiscale = {x = 0.01, y = 0.01},
			},
			{
				selectors = {"framedPanel", "show"},
				collapsed = 0,
				opacity = 1,
				transitionTime = 0.0,
				uiscale = {x = 1, y = 1},
			},
			{
				selectors = {"framedPanel", "show", "left"},
				x = -400,
				transitionTime = 0.0,
			},
			{
				selectors = {"framedPanel", "show", "right"},
				x = 400,
				transitionTime = 0.0,
			},
			{
				selectors = {"framedPanel", "show", "above"},
				y = -250,
				transitionTime = 0.0,
			},
			{
				selectors = {"framedPanel", "show", "below"},
				y = 250,
				transitionTime = 0.0,
			},
			{
				selectors = {'#MainObjectPropertiesPanel'},
				flow = 'horizontal',
				height = '100% available',
			},
			{
				selectors = {'editor-panel'},
				priority = 5,
				flow = 'vertical',
				width = '70%-20',
				height = '100%-20',
			},
			{
				selectors = {'add-property-dropdown'},
				priority = 5,
				cornerRadius = 0,
				width = '90%',
				height = 30,
			},
			{
				selectors = {'dropdown-option'},
				priority = 10,
				cornerRadius = 0,
				width = '200%',
				height = 30,
				fontSize = 12,
			},
			{
				selectors = {'left-panel'},
				priority = 5,
				width = '30%',
				height = '100%-20',
			},
			{
				selectors = {"label-text"},
				priority = 4,
				fontSize = 14,
				width = "auto",
				height = "auto",
			},
			{
				selectors = {"field-editor-panel"},
				bgcolor = '#222222ff',
				width = "90%",
				minHeight = 40,
				height = "auto",
				priority = 4,
				cornerRadius = 8,
				borderWidth = 0,
				pad = 4,
				margin = 4,
				flow = 'vertical',
			},
            {
                selectors = {"field-editor-panel", "parent:groupingPanel"},
                width = "100%",
            },
			{
				selectors = {"field-description-label"},
				priority = 4,
				fontSize = 12,
				minFontSize = 10,
				textWrap = false,

				width = 80,
				height = "auto",
				halign = 'left',
				valign = 'center',
			},
			{
				selectors = {"field-name-label"},
				priority = 5,
				maxWidth = 240,
			},
			{
				selectors = {'property-label'},
				priority = 5,
				width = 'auto',
				height = 'auto',
				fontSize = 12,
				margin = 8,
				halign = 'right',
			},
			{
				selectors = {"#ArtistsAndKeywords"},
				priority = 5,
				hmargin = 0,
				valign = "bottom",
				width = "100%",
				height = "auto",
				flow = "vertical",
			},
		},
		
		data = {
			objectsShown = {},

			ShowObjects = function(objects)
				resultPanel.data.objectsShown = objects

				--resultPanel.selfStyle.width = DialogWidth
				--resultPanel.selfStyle.height = DialogHeight + DialogWidth/4 + 8

				local closeButton = gui.CloseButton{
					floating = true,
					halign = "right",
					valign = "top",
					click = function(element)
						resultPanel:DestroySelf()
					end,
				}

				local m_anchorDrag = nil

				local resizePanel = gui.Panel{
					classes = {"collapsed"},
					floating = true,
					halign = "right",
					valign = "bottom",
					width = 32,
					height = 32,
					bgimage = "panels/square.png",
					bgcolor = "clear",
					hoverCursor = "diagonal-expand",
					dragBounds = { x1 = 100, y1 = -1000, x2 = 1000, y2 = -100 },
					draggable = true,
					swallowPress = true,

					beginDrag = function(element)
						m_anchorDrag = {x = resultPanel.selfStyle.width, y = resultPanel.selfStyle.height}
					end,

					dragging = function(element)
						if m_anchorDrag ~= nil then
							resultPanel.selfStyle.width = math.max(DialogWidth, m_anchorDrag.x + element.xdrag)
							resultPanel.selfStyle.height = math.max(DialogHeight, m_anchorDrag.y + element.ydrag)
						end
					end,
					drag = function(element)
						--element.x = element.xdrag
						--element.y = element.ydrag
					end,
				}

				local banner = nil

				local panel
				local createEditorFunction
				createEditorFunction = function()
					return CreateObjectEditor(objects, {
						sliderWidth = 220,
						labelWidth = 30,
						addPropertyText = 'Add...', --the text to use to add properties. This is the short version for a smaller area.
						objectInstances = true, --this signals that we are editing actual object instances, not blueprints.
						recreate = function(element, newObjects)
							objects = newObjects
							resultPanel.data.objectsShown = objects
							panel = createEditorFunction()
							resultPanel.children = {banner, panel, resizePanel, closeButton}
						end,
					})
					
				end

				panel = createEditorFunction()


				--see if there is a single artist for all objects.

				local artist = nil
				for _,obj in ipairs(objects) do
					if obj.artist ~= nil then
						if artist ~= nil and artist ~= obj.artist then
							artist = nil
							break
						end

						artist = obj.artist
					end
				end

				if artist ~= nil then
					local artistInfo = assets.artists[artist]
					if artistInfo ~= nil and artistInfo.bannerImage ~= nil and artistInfo.bannerImage ~= "" and dmhub.whiteLabel ~= "mcdm" then
						resultPanel:SetClass("hasBanner", true)
						banner = gui.Panel{
							width = "100%-4",
							height = "25% width",
							halign = "center",
							vmargin = 2,
							cornerRadius = 4,
							bgimage = artistInfo.bannerImage,
							bgcolor = "white",
							hoverCursor = "hand",
							click = function(element)
								if dmhub.hasStoreAccess then
									GameHud.instance.mainDialogPanel:AddChild(CreateShopScreen{ titlescreen = GameHud.instance, artistid = artist })
								else
									dmhub.OpenArtistPage(artist)
								end
							end,
						}
					end
				end

				resultPanel.children = { banner, panel, resizePanel, closeButton }

				if not resultPanel:HasClass("show") then
					if resultPanel.parent.mousePoint ~= nil then
						resultPanel.x = resultPanel.parent.renderedWidth*resultPanel.parent.mousePoint.x - DialogWidth*0.5
						resultPanel.y = resultPanel.parent.renderedHeight*(1 - resultPanel.parent.mousePoint.y) - DialogHeight * 0.5

						resultPanel:SetClass("above", resultPanel.parent.mousePoint.y < 0.25)
						resultPanel:SetClass("below", resultPanel.parent.mousePoint.y > 0.75)
						resultPanel:SetClass("left", resultPanel.parent.mousePoint.x > 0.5)
						resultPanel:SetClass("right", not resultPanel:HasClass("left"))
					end
					resultPanel:SetClass('show', true)
				end
				return resultPanel
			end,

			ClearObjects = function()
				resultPanel.data.objectsShown = {}
				resultPanel.children = {}
				resultPanel:SetClass('show', false)
			end,
		},
	}

	return resultPanel
end

mod.shared.EditObjectDialog = function(nodeids)

	local nodes = {}
	local node = assets:GetObjectNode(nodeids[#nodeids])
	for i,nodeid in ipairs(nodeids) do
		nodes[#nodes+1] = assets:GetObjectNode(nodeid)
	end

	local backups = {}
	for i,node in ipairs(nodes) do
		backups[#backups+1] = node:Backup()
	end

	local mainPanel = CreateObjectEditor(nodes, { blueprint = true })

	local changeAllCheck = gui.Check{
		id = 'change-all-objects-check',
		text = 'Update all objects created with this blueprint',
		value = true,
		x = 270,
		style = {
			cornerRadius = 0,
			borderWidth = 0,
			height = 30,
			width = '40%',
			fontSize = '40%',
			halign = 'left',
		}
	}

	local buttonPanel = gui.Panel{
		id = 'BottomButtons',
		style = {
			width = '90%',
			height = 80,
			margin = 8,
			bgcolor = 'white',
			valign = 'bottom',
			halign = 'center',
			flow = 'horizontal',
		},

		children = {

			gui.PrettyButton{
				text = 'Confirm',
				style = {
					margin = 0,
					width = 200,
					height = 60,
					halign = 'center',
					valign = 'center',
				},

				events = {
					click = function(element)
						gui.CloseModal()

						local groupid = dmhub.GenerateGuid()
						for i,currentNode in ipairs(nodes) do
							currentNode:Upload(groupid)
							if changeAllCheck.value then
								currentNode:UpdateObjectInstances()
							end
						end

					end,
				}
			},

			gui.PrettyButton{
				text = 'Cancel',
				style = {
					margin = 0,
					width = 200,
					height = 60,
					halign = 'center',
					valign = 'center',
				},

				events = {
					click = function(element)
						for i,node in ipairs(nodes) do
							node:Restore(backups[i])
						end
						gui.CloseModal()
					end,
				}
			},

		}
	}

	local DialogWidth = 1200
	local DialogHeight = 1000

	local dialogPanel = gui.Panel{
		id = 'EditObjectDialog',
		classes = {"framedPanel"},

		styles = {
			Styles.Panel,
			{
				width = DialogWidth,
				height = DialogHeight,
				flow = 'vertical',
			},
			{
				selectors = {'#MainObjectPropertiesPanel'},
				flow = 'horizontal',
				height = '100%-140',
			},
			{
				selectors = {'editor-panel'},
				priority = 5,
				flow = 'vertical',
				width = '80%',
				height = '100%',
			},
			{
				selectors = {'dropdown-option'},
				priority = 10,
				cornerRadius = 0,
				width = '200%',
				height = "100%",
				fontSize = 12,
			},
			{
				selectors = {'add-property-dropdown'},
				priority = 5,
				cornerRadius = 0,
				width = '90%',
				height = 40,
			},
			{
				selectors = {'left-panel'},
				priority = 5,
				width = '20%',
				height = '100%',
			},
			{
				selectors = {"label-text"},
				priority = 4,
				fontSize = 18,
				width = "auto",
				height = "auto",
			},
			{
				selectors = {"field-editor-panel"},
				bgcolor = '#33333399',
				width = "40%",
				minHeight = 40,
				height = "auto",
				priority = 4,
				cornerRadius = 8,
				borderWidth = 0,
				pad = 4,
				margin = 4,
				flow = 'none',
			},
			{
				selectors = {"field-description-label"},
				priority = 4,
				fontSize = 18,
				width = "auto",
				height = "auto",
				halign = 'left',
				valign = 'center',
			},
			{
				selectors = {"#ArtistsAndKeywords"},
				priority = 5,
				valign = "bottom",
				width = "100%",
				height = "auto",
				flow = "vertical",
			},
			{
				selectors = {'property-label'},
				priority = 5,
				width = 'auto',
				height = 'auto',
				fontSize = 12,
				margin = 8,
				halign = 'right',
			},
			{
				selectors = {'property-pane'},
				width = "auto",
				height = "auto",
				priority = 5,
				flow = 'horizontal',
			},
		},

		children = {
			mainPanel,
			changeAllCheck,
			buttonPanel,
		}
	}

	gui.ShowModal(dialogPanel)
end

dmhub.EditObjectDialog = mod.shared.EditObjectDialog


local m_objectsScheduledToShow = nil

--called by DMHub when the selected objects change.
dmhub.ObjectsSelected = function(objects)
	m_objectsScheduledToShow = objects

	--schedule this to make sure it happens early in the frame.
	dmhub.Schedule(0.01, function()
		objects = m_objectsScheduledToShow
		m_objectsScheduledToShow = nil
		
		if objects == nil then
			--we had multiple calls in the same frame and this one isn't needed.
			return
		end

		--get only valid objects
		local validObjects = {}
		for _,obj in ipairs(objects) do
			if obj.valid then
				validObjects[#validObjects+1] = obj
			end
		end

		objects = validObjects

		if #objects == 0 then
			if m_objectEditor ~= nil then
				m_objectEditor.data.ClearObjects()
			end
			return
		end

		if m_objectEditor ~= nil and #m_objectEditor.data.objectsShown == #objects then
			--if we are selecting the exact same objects again then de-select
			local same = true
			for i=1,#objects do
				if objects[i].objid ~= m_objectEditor.data.objectsShown[i].objid or objects[i].floorid ~= m_objectEditor.data.objectsShown[i].floorid then
					same = false
					break
				end
			end

			if same then
				m_objectEditor.data.ClearObjects()
				return
			end
		end

		if m_objectEditor == nil then
			m_objectEditor = CreateObjectEditorPanel()
			gui.ShowDialogOverMap(mod, m_objectEditor, { nofade = true})
		end

		m_objectEditor.data.ShowObjects(objects)
	end)
end
