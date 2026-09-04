local mod = dmhub.GetModLoading()

local GetSettingEnum = function(var)
	if var.enumCalc ~= nil then
		return var.enumCalc()
	end

	return var.enum
end

--Command-builder entries for an enum/dropdown setting: one "Set X to <option>"
--menu item per enum value. Evaluated at click time so dynamic option lists
--(var.getOptions) stay fresh. The recorded command is the engine's plain
--"<settingid> <value>" setter. String values are ALWAYS quoted: an unquoted
--arg goes through SetValue(string) -> ScriptSerialize.JsonToLua, which
--mangles any non-JSON token (a dice asset id parses as a number prefix or
--nil). Quoting makes ExecuteCommand strip the quotes and pass the raw
--string straight through.
local DropdownLightningEntries = function(var)
	return function(element)
		local name = var.description or var.id

		local opts
		if var.getOptions ~= nil then
			opts = var.getOptions()
		else
			opts = {}
			for i,item in ipairs(GetSettingEnum(var)) do
				opts[#opts+1] = {
					id = item.value,
					text = item.text or item.value,
				}
			end
		end

		local entries = {}
		for _,opt in ipairs(opts) do
			local value = opt.id
			local optionText = tostring(opt.text or value)
			local command
			if type(value) == "string" then
				command = string.format('%s "%s"', var.id, value)
			else
				command = string.format("%s %s", var.id, tostring(value))
			end
			entries[#entries+1] = {
				text = string.format("Set %s to %s", name, optionText),
				command = command,
				stepText = string.format("%s = %s", name, optionText),
			}
		end
		return entries
	end
end

--Command-builder popup for a slider setting: a mini slider (same range,
--rounding, and value formatting as the row's editor) plus an Add Step
--button, so the user can record "set this setting to any chosen value".
--The recorded command sets the setting's STORED value (%g keeps floats
--compact); the chip shows the formatted display value.
local SliderLightningPopup = function(var, formatFunction, deformatFunction)
	return function(iconElement)
		local name = var.description or var.id
		local m_value = dmhub.GetSettingValue(var.id)

		local FormatValue = function(value)
			if formatFunction ~= nil then
				return formatFunction(value)
			end
			return string.format(var.labelFormat or "%.1f", value)
		end

		local slider = gui.Slider{
			minValue = var.min,
			maxValue = var.max,
			value = m_value,
			round = var.round,

			formatFunction = formatFunction,
			deformatFunction = deformatFunction,

			sliderWidth = 140,
			labelWidth = 48,
			labelFormat = var.labelFormat or "%.1f",
			events = {
				change = function(element)
					m_value = element.data.getValue()
				end,
				confirm = function(element)
					m_value = element.data.getValue()
				end,
			},
			style = {
				width = 220,
				height = 28,
				fontSize = 12,
			},
		}

		return gui.Panel{
			classes = {"bordered", "bg"},
			width = "auto",
			height = "auto",
			flow = "vertical",
			pad = 8,

			gui.Label{
				text = string.format("Set %s to:", name),
				fontSize = 12,
				width = "auto",
				height = "auto",
			},

			slider,

			gui.Button{
				text = "Add Step",
				fontSize = 12,
				width = "auto",
				height = 24,
				hpad = 10,
				borderBox = true,
				halign = "right",
				vmargin = 4,
				click = function(element)
					CommandBuilder.RecordStep{
						command = string.format("%s %g", var.id, m_value),
						text = string.format("%s = %s", name, FormatValue(m_value)),
					}
					iconElement.popup = nil
				end,
			},
		}
	end
end

--Command-builder popup for a color setting: a color picker (starting from
--the setting's current color) plus an Add Step button, so the user can
--record "set this setting to any chosen color". Color settings store a
--Color userdata, so the recorded command carries the engine's serialized
--userdata form -- {"__usertype":"LuaColor","h":...,"s":...,"v":...,"a":...}
---- which ExecuteCommand's setting path deserializes back into a proper
--Color value (a plain hex string would store a string and break C#-side
--readers of the setting). The chip shows the friendly hex form.
local ColorLightningPopup = function(var)
	return function(iconElement)
		local name = var.description or var.id

		--the picker opens its own popup when clicked; the engine keeps our
		--popup open because the picker is inside it (popup chains).
		local picker = gui.ColorPicker{
			value = dmhub.GetSettingValue(var.id),
			hasAlpha = var.hasAlpha,
			popupAlignment = 'left',
			styles = {
				{
					width = 24,
					height = 24,
					halign = "left",
					valign = "center",
				},
			},
		}

		return gui.Panel{
			classes = {"bordered", "bg"},
			width = "auto",
			height = "auto",
			flow = "vertical",
			pad = 8,

			gui.Label{
				text = string.format("Set %s to:", name),
				fontSize = 12,
				width = "auto",
				height = "auto",
			},

			picker,

			gui.Button{
				text = "Add Step",
				fontSize = 12,
				width = "auto",
				height = 24,
				hpad = 10,
				borderBox = true,
				halign = "right",
				vmargin = 4,
				click = function(element)
					local c = core.Color(picker.value)
					CommandBuilder.RecordStep{
						command = string.format('%s {"__usertype":"LuaColor","h":%g,"s":%g,"v":%g,"a":%g}', var.id, c.h, c.s, c.v, c.a),
						text = string.format("%s = %s", name, c.tostring),
					}
					iconElement.popup = nil
				end,
			},
		}
	end
end

local CreateEditorPanel = function(var, editor, changeFunction, args, lightning)
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

	-- Optional command-builder affordance (a CommandBuilder.LightningIcon
	-- options table). Built lazily on the first activation of command
	-- creation mode: while the mode is inactive the only cost is the extra
	-- monitor registration. The row watches both its own setting and the
	-- mode flag; the monitor event fires for either, and both reactions are
	-- cheap no-ops for the id that did not change.
	local attachLightning = nil
	if lightning ~= nil then
		attachLightning = function(element)
			CommandBuilder.EnsureLightningIcon(element, lightning)
		end
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

		monitor = lightning ~= nil and {var.id, "commandcreationmode"} or var.id,
		events = {
			monitor = function(element)
				if changeFunction ~= nil then
					changeFunction(dmhub.GetSettingValue(var.id))
				end
				if attachLightning ~= nil then
					attachLightning(element)
				end
			end,
			create = attachLightning,
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

		return CreateEditorPanel(var, sliderElement, function(newValue) sliderElement.data.setValueNoEvent(newValue) end, nil, {
			floating = true,
			halign = "right",
			valign = "center",
			--gutter column, consistent with every other editor type.
			rmargin = -26,
			createPopup = SliderLightningPopup(var, formatFunction, deformatFunction),
		})
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

		return CreateEditorPanel(var, sliderElement, function(newValue) sliderElement.data.setValueNoEvent(newValue) end, options, {
			floating = true,
			halign = "right",
			valign = "center",
			--gutter column, consistent with every other editor type.
			rmargin = -26,
			createPopup = SliderLightningPopup(var, formatFunction, deformatFunction),
		})

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

		--While command creation mode is active (see CommandBuilder.lua), a
		--lightning icon floats at the right edge of the row; its menu records
		--set/toggle steps for this setting into the command being built. The
		--icon is built lazily on the first activation of the mode -- a normal
		--settings open constructs nothing for it.
		local lightningOptions = {
			floating = true,
			halign = "right",
			valign = "center",
			--all lightning icons sit in one consistent column just outside
			--the row's right edge, in the gutter before the scrollbar --
			--dropdown/slider controls extend to the row edge, so inside the
			--row there is no overlap-free spot shared by every editor type.
			rmargin = -26,
			entries = function(element)
				local name = var.description or var.id
				return {
					{
						text = string.format("Turn %s on", name),
						command = string.format("%s true", var.id),
						stepText = string.format("%s on", name),
					},
					{
						text = string.format("Turn %s off", name),
						command = string.format("%s false", var.id),
						stepText = string.format("%s off", name),
					},
					{
						text = string.format("Toggle %s", name),
						command = string.format("toggle %s", var.id),
						stepText = string.format("Toggle %s", name),
					},
				}
			end,
		}

		local AttachLightning = function(element)
			CommandBuilder.EnsureLightningIcon(element, lightningOptions)
		end

		return
		gui.Panel{
			width = "90%",
			height = "auto",
			multimonitor = {"commandcreationmode"},
			create = AttachLightning,
			monitor = AttachLightning,
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

					--any boolean setting can be keybound to the engine's "toggle <id>"
					--command, which works globally, not just while this checkbox exists.
					--Bound settings are listed in the Shortcuts tab (see Keybinds.GetBindings).
					rightClick = function(element)
						local command = string.format("toggle %s", var.id)
						local binding = dmhub.GetCommandBinding(command)
						local menuText = "Configure Keybind"
						if binding ~= nil and binding ~= "" then
							menuText = string.format("Configure Keybind (%s)", binding)
						end
						element.popup = gui.ContextMenu{
							entries = {
								{
									text = menuText,
									click = function()
										element.popup = Keybinds.ShowBindPopup{
											command = command,
											name = var.description or var.id,
											destroy = function()
												if element.valid then
													element.root:FireEventTree("rebuildKeybinds")
												end
											end,
										}
									end,
								},
							},
						}
					end,
				},
			},
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
		
		return CreateEditorPanel(var, editor, nil, args, {
			floating = true,
			halign = "right",
			valign = "center",
			--gutter column, consistent with every other editor type.
			rmargin = -26,
			entries = DropdownLightningEntries(var),
		})

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

		return CreateEditorPanel(var, picker, nil, options, {
			floating = true,
			halign = "right",
			valign = "center",
			--gutter column, consistent with every other editor type.
			rmargin = -26,
			createPopup = ColorLightningPopup(var),
		})
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
