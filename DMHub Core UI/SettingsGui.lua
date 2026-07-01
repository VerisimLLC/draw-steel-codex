local mod = dmhub.GetModLoading()

local GetSettingEnum = function(var)
	if var.enumCalc ~= nil then
		return var.enumCalc()
	end

	return var.enum
end

local CreateEditorPanel = function(var, editor, changeFunction, args)
	args = args or {}
	-- Opt-in label-above-control layout. When passed via the editor's options
	-- table (e.g. CreateSettingsEditor("foo", {stacked = true})), the row
	-- flows vertically with a smaller formStacked-themed label sitting above
	-- the editor instead of beside it. Callers that don't pass `stacked` keep
	-- the legacy horizontal layout.
	local stacked = args.stacked

	local label = nil
	if not var.hidelabel then
		label = gui.Label{
			classes = stacked and {"formStacked", "sizeXs"} or {"form"},
			width = stacked and "98%" or "60%",
			text = string.format("%s:", var.description),
		}
	end

	return gui.Panel{
		styles = {
			{
				width = stacked and "98%" or "90%",
				height = stacked and "auto" or 48,
				flow = stacked and "vertical" or "horizontal",
				hmargin = 2,
				vmargin = stacked and 4 or 0,
			},
			args.panelStyle,
		},

		monitor = var.id,
		events = {
			monitor = function(element)
				if changeFunction ~= nil then
					changeFunction(dmhub.GetSettingValue(var.id))
				end
			end,
			linger = gui.Tooltip(var.help),
		},

		children = {
			label,
			editor,
		}
	}
end

local SettingsEditors = {

	input = function(var, options)
		options = options or {}
		local stacked = options.stacked
		local input = gui.Input{
			classes = {stacked and "formStacked" or "form"},
			text = dmhub.GetSettingValue(var.id),

			characterLimit = var.characterLimit,

			events = {
				change = function(element)
					dmhub.SetSettingValue(var.id, element.text)
					if var.onchange then
						var.onchange()
					end
				end
			}
		}

		return CreateEditorPanel(var, input, nil, options)
	end,

	sliderexponential = function(var)

		local sign = var.sign or 1

		local formatFunction = nil
		local deformatFunction = nil
		if var.percent ~= false then
			formatFunction = function(num)
				return string.format('%d%%', round((2^num)*100))
			end
			deformatFunction = function(num)
				local n = num*0.01
				return math.log(n)/math.log(2)
			end
		else
			formatFunction = function(num)
				return string.format('%d', round((2^num)))
			end
			deformatFunction = function(num)
				local n = num
				return math.log(n)/math.log(2)
			end
		end

		local sliderElement = gui.Slider{
			minValue = var.min,
			maxValue = var.max,
			value = dmhub.GetSettingValue(var.id),
			round = var.round,

			sliderWidth = 110,
			labelWidth = 40,

			formatFunction = formatFunction,
			deformatFunction = deformatFunction,

			labelFormat = var.labelFormat or '%.1f',
			events = {
				
				change = function(element)
					dmhub.SetSettingValue(var.id, element.data.getValue())
					if var.onchange then
						var.onchange()
					end

					element:FireEventOnParents("childsetting", var.id)
				end,
			},
			style = {
				halign = 'right',
				valign = 'center',
				fontSize = '30%',
				height = 28,
				width = 160,
			}
		}

		return CreateEditorPanel(var, sliderElement, function(newValue) sliderElement.data.setValueNoEvent(newValue) end)
	end,

	slider = function(var, options)
		options = options or {}
		local stacked = options.stacked

		local formatFunction = nil
		local deformatFunction = nil
		if var.percent then
			formatFunction = function(num)
				return string.format('%d%%', round(num*100))
			end
			deformatFunction = function(num)
				local n = num*0.01
				return n
			end
		end

		local sliderElement = gui.Slider{
			minValue = var.min,
			maxValue = var.max,
			value = dmhub.GetSettingValue(var.id),
			round = var.round,

			formatFunction = formatFunction,
			deformatFunction = deformatFunction,

			sliderWidth = 110,
			labelWidth = 40,
			labelFormat = var.labelFormat or '%.1f',
			events = {

				change = function(element)
					dmhub.PreviewSettingValue(var.id, element.data.getValue())
				end,

				confirm = function(element)
					dmhub.SetSettingValue(var.id, element.data.getValue())
					if var.onchange then
						var.onchange()
					end

					element:FireEventOnParents("childsetting", var.id)
				end,
			},
			styles = {
				{
					halign = stacked and 'left' or 'right',
					valign = 'center',
					fontSize = 12,
					height = 28,
					width = 160,
					lmargin = stacked and 6 or 0,
				},
				options.style,
			},
		}

		return CreateEditorPanel(var, sliderElement, function(newValue) sliderElement.data.setValueNoEvent(newValue) end, options)

	end,

	check = function(var, options)
		options = options or {}

		local keybinds = nil

		if var.bind ~= nil then
			keybinds = {
				{
					id = var.id,
					defaultBind = var.bind,
				}
			}
		end

		return
		gui.Panel{
			width = "90%",
			height = "auto",
			gui.Check{
				value = dmhub.GetSettingValue(var.id),
				text = var.description,
				tooltip = var.help,
				halign = options.halign or "left",
				keybinds = keybinds,

				style = {
					width = options.width or "100%",
					height = options.height or 40,
					fontSize = options.fontSize or 14,
					hpad = 0,
				},

				monitor = var.id,

				events = {
					monitor = function(element)
						element.value = dmhub.GetSettingValue(var.id)
					end,

					change = function(element)
						dmhub.SetSettingValue(var.id, element.value)
						if var.onchange then
							var.onchange()
						end

						element:FireEventOnParents("childsetting", var.id)
					end,
				},
			}
		}
	end,

    enumslider = function(var, args)
		local value = dmhub.GetSettingValue(var.id)

        local editor = gui.EnumeratedSliderControl{
            options = GetSettingEnum(var),
            value = value,

            monitor = var.id,
            events = {
				monitor = function(element)
					value = dmhub.GetSettingValue(var.id)
                    element.SetValue(element, value, false)
				end,

                change = function(element)
                    dmhub.SetSettingValue(var.id, element:GetValue())
                    if var.onchange then
                        var.onchange()
                    end
                end,
            }
        }

        return editor
    end,

	dropdown = function(var, args)
		local value = dmhub.GetSettingValue(var.id)

		args = args or {}
		local stacked = args.stacked

		local options = {}

		if var.getOptions ~= nil then
			options = var.getOptions()
		else
			for i,item in ipairs(GetSettingEnum(var)) do
				options[#options+1] = {
					id = item.value,
					text = item.text or item.value,
					keybind = cond(item.bind, item.bind),
				}

				if item.bind ~= nil then
					print("BIND:: DROPDOWN: ", options[#options])
				end
			end
		end

		local editor = gui.Dropdown{
				classes = {stacked and "formStacked" or "form"},
				width = stacked and "98%" or "33%",
				halign = stacked and "left" or "right",
				lmargin = stacked and 6 or 0,
				options = options,
				idChosen = value,
				monitor = var.id,
				events = {
					monitor = function(element)
						value = dmhub.GetSettingValue(var.id)
						element.idChosen = value
					end,
					change = function(element)
						dmhub.SetSettingValue(var.id, element.idChosen)
						if var.onchange then
							var.onchange()
						end
					end,
					refreshAssets = function(element)
						if var.getOptions ~= nil then
							element.options = var.getOptions()
						end
					end,
				}
			}
		
		return CreateEditorPanel(var, editor, nil, args)

	end,

	iconlibrary = function(var)
		local iconPanel = gui.IconEditor{
			library = var.library,
			categoriesHidden = true,
			searchHidden = true,
			bgcolor = "white",
			width = 32,
			height = 32,
			hideButton = true,
			value = dmhub.GetSettingValue(var.id),
			valign = "center",

			monitor = var.id,
			events = {
				change = function(element)
					dmhub.SetSettingValue(var.id, element.value)
					element:FireEventOnParents("childsetting", var.id)
				end,

				monitor = function(element)
					element.value = dmhub.GetSettingValue(var.id)
				end,
			}
		}

		return gui.Panel{
			style = {
				width = "100%",
				height = 48,
				flow = 'horizontal',
				hmargin = 2,
			},

			children = {
				gui.Label({
					text = string.format("%s:", var.description),
					style = {
						width = "auto",
						height = "auto",
						fontSize = '50%',
						valign = 'center',
						textAlignment = 'center',
					},
				}),

				iconPanel,
			},
		}
	end,

	iconbuttons = function(var)

		local buttons = {}
		local value = dmhub.GetSettingValue(var.id)
		local selectedIndex = nil
		local valueToIndex = {}

		for i,item in ipairs(GetSettingEnum(var)) do
			local enumItem = item
			local currentIndex = i
			local classes = {"sizeL", "bordered"}
			if item.value == value then
				classes[#classes+1] = "selected"
				selectedIndex = i
			end

			valueToIndex[enumItem.value] = i

			buttons[#buttons+1] = gui.Button{
				classes = classes,
				icon = enumItem.icon,
				tooltip = enumItem.help,
				valign = "center",
				hmargin = 2,
				press = function(element)
					if selectedIndex ~= nil then
						buttons[selectedIndex]:RemoveClass("selected")
					end

					gui.SetFocus(element)

					selectedIndex = currentIndex
					element:AddClass("selected")
					dmhub.SetSettingValue(var.id, enumItem.value)
					if var.onchange then
						var.onchange()
					end
				end,
			}
		end

		return gui.Panel{
			width = "100%",
			height = 48,
			flow = "horizontal",
			halign = "center",

			monitor = var.id,
			events = {
				monitor = function(element)
					local index = valueToIndex[element.monitorValue]
					if index ~= nil and index ~= selectedIndex then
						buttons[index]:FireEvent("press")
					end
				end,

				pressfirst = function(element)
					buttons[1]:FireEvent("press")
				end,
			},

			children = {
				buttons,
			},
		}

	end,

	color = function(var, options)
		options = options or {}
		local stacked = options.stacked
		local picker = gui.ColorPicker{
					value = dmhub.GetSettingValue(var.id),
					popupAlignment = 'left',

					hasAlpha = var.hasAlpha,

					monitor = var.id,

					events = {
						confirm = function(element)
							dmhub.SetSettingValue(var.id, element.value) --now we are confirmed we will set, unlocking the value.
							if var.onchange then
								var.onchange()
							end
						end,

						change = function(element)
							dmhub.SetSettingValue(var.id, element.value, true) --set the value and lock it until we confirm.
						end,

						monitor = function(element)
							local newValue = dmhub.GetSettingValue(var.id)

							if element.value == newValue then
								return
							end

							element.value = newValue
						end,
					},
					styles = {
						{
							halign = stacked and 'left' or 'right',
							valign = 'center',
							fontSize = '30%',
							height = 24,
							width = 24,
							lmargin = stacked and 6 or 0,
						},
					}

				}

		return CreateEditorPanel(var, picker, nil, options)
	end,

	buttonincrement = function(var)
		local button = gui.Button{
			classes = {"sizeL"},
			text = var.description,
			width = 260,
			events = {
				click = function(element)
					dmhub.SetSettingValue(var.id, dmhub.GetSettingValue(var.id)+1)
					if var.onchange then
						var.onchange()
					end
				end
			},
		}

		return button
	end,
}

function CreateSettingsDisplay(var, options)
	local setting = Settings[var]
	if setting == nil then
		dmhub.Error('Unknown setting: ' .. var)
		return nil
	end

	options = options or {}

	local args = {
		width = 'auto',
		height = 'auto',
		text = GetSettingPrettyValue(setting),
		multimonitor = var.monitorVisible,
		monitor = function(element)
			if setting.visible ~= nil then
				element:SetClass('collapsed', not setting.visible())
			end

			element.text = GetSettingPrettyValue(setting)
		end,
	}

	for k,option in pairs(options) do
		args[k] = option
	end

	return gui.Label(args)
end

-- Whether the running engine exposes the per-map setting default API (dmhub.SettingVariesFromDefault
-- etc., added to the C# engine alongside this code). Detected with pcall so that loading this Lua on
-- an engine build that predates the API does not error -- the "Default Value" row is simply omitted
-- until the engine is rebuilt.
local g_mapDefaultsSupported
local function MapDefaultsSupported()
	if g_mapDefaultsSupported == nil then
		local ok, fn = pcall(function() return dmhub.SettingVariesFromDefault end)
		g_mapDefaultsSupported = (ok and fn ~= nil) or false
	end
	return g_mapDefaultsSupported
end

-- For a per-map setting, an info row shown beneath its editor when the current map's value differs
-- from the established (game-wide) default. Reads as a directional sentence so the two actions are
-- unambiguous: "Revert to Default" pulls the default onto THIS map (clearing its override so it tracks
-- the default); "Make This the Default" pushes this map's value up to become the default for ALL maps.
-- Backed by the engine's 'mapdefault:<id>' companion variable; monitors both the setting and its
-- companion so it refreshes live as either changes.
local function CreateMapSettingDefaultRow(var, options)
	options = options or {}
	local stacked = options.stacked

	local statusLabel = gui.Label{
		width = "auto",
		height = "auto",
		fontSize = 12,
		color = "@fgMuted",
		halign = "left",
		text = "",
	}

	local revertLink = gui.Label{
		-- 'link' gives accent color + hover/press states; 'underline' adds the at-rest hyperlink
		-- affordance so the action reads as clickable even in monochrome schemes where @accent is grey.
		classes = {"link", "underline"},
		width = "auto",
		height = "auto",
		fontSize = 12,
		valign = "center",
		text = "Revert to Default",
		events = {
			click = function(element)
				dmhub.ResetSettingToDefault(var.id)
			end,
			linger = gui.Tooltip("Discard this map's value and use the default instead."),
		},
	}

	local divider = gui.Label{
		width = "auto",
		height = "auto",
		fontSize = 12,
		color = "@fgMuted",
		valign = "center",
		hmargin = 8,
		text = "|",
	}

	local makeDefaultLink = gui.Label{
		classes = {"link", "underline"},
		width = "auto",
		height = "auto",
		fontSize = 12,
		valign = "center",
		text = "Make This the Default",
		events = {
			click = function(element)
				dmhub.ChangeSettingDefault(var.id)
			end,
			linger = gui.Tooltip("Use this map's value as the default for all maps that haven't set their own."),
		},
	}

	local actionsRow = gui.Panel{
		flow = "horizontal",
		width = "auto",
		height = "auto",
		halign = "left",
		valign = "center",
		children = { revertLink, divider, makeDefaultLink },
	}

	local row
	row = gui.Panel{
		classes = {"collapsed"},
		flow = "vertical",
		width = stacked and "98%" or "90%",
		height = "auto",
		halign = stacked and "left" or "center",
		valign = "center",
		vmargin = 2,
		lmargin = stacked and 6 or 0,

		multimonitor = { var.id, "mapdefault:" .. var.id },

		create = function(element)
			element:FireEvent("monitor")
		end,

		events = {
			monitor = function(element)
				local varies = dmhub.SettingVariesFromDefault(var.id)
				element:SetClass("collapsed", not varies)
				if varies then
					statusLabel.text = string.format("Overrides the default (%s).", dmhub.GetSettingDefaultFormatted(var.id))
				end
			end,
		},

		children = { statusLabel, actionsRow },
	}

	return row
end

function CreateSettingsEditor(var, options)
	if type(var) == 'string' then
		local setting = Settings[var]
		if setting == nil then
			dmhub.Error('Unknown setting: ' .. var)
			return nil
		end

		var = setting
	end

	if var.editor ~= nil then
		local panel = SettingsEditors[var.editor](var, options)
		if panel ~= nil then
			-- Per-map settings get a "Default Value: ... [Reset to Default] [Change Default]" row
			-- beneath the editor (only on engine builds that expose the API).
			local defaultRow = nil
			if var.storage == "map" and MapDefaultsSupported() then
				defaultRow = CreateMapSettingDefaultRow(var, options)
			end

			local function ContainerChildren()
				if defaultRow ~= nil then
					return { panel, defaultRow }
				end
				return { panel }
			end

			local container = gui.Panel({
				classes = var.classes,
				halign = "center",
				flow = "vertical",
				selfStyle = {
					width = 'auto',
					height = 'auto',
					pad = 0,
					margin = 0,
				},

				multimonitor = var.monitorVisible,
				events = {
					monitor = function(element)
						if var.visible ~= nil then
							panel:SetClass('collapsed', not var.visible())
						end
					end,
				},

				children = ContainerChildren()
			})

			if var.assetsRefresh then
				container.events.refreshAssets = function(element)
					panel = SettingsEditors[var.editor](var, options)
					container.children = ContainerChildren()
				end
			end

			if var.visible ~= nil then
				container:FireEvent('monitor')
			end

			return container
		end
	end

	return nil
end

function CreateSettingsEditorsForSection(section, options)
	local result = {}
	for i,setting in ipairs(SettingsOrdered) do
		if setting.section == section then
			result[#result+1] = CreateSettingsEditor(setting, options)
		end
	end
	return result
end
