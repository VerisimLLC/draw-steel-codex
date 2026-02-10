local mod = dmhub.GetModLoading()

local _gui = gui

--- @class gui
gui = {
}

setmetatable(gui, {
	__index = function(t, n)
		return _gui[n]
	end
})

local m_focus = nil

--- If a panel has the focus.
--- @return boolean
function gui.HasFocus()
	if m_focus and m_focus.valid then
		return true
	else
		return false
	end
end

--- Gets the panel that is focused.
--- @return nil|Panel
function gui.GetFocus()
	if m_focus and m_focus.valid then
		return m_focus
	end

	return nil
end

dmhub.GetFocus = gui.GetFocus

--- Set the focus to a given element.
--- @param newFocus nil|Panel
function gui.SetFocus(newFocus)
	if newFocus == m_focus then
		return
	end

	local focusInfo = {
		oldFocus = m_focus,
		newFocus = newFocus,
	}

	if m_focus and m_focus.valid then
		m_focus:RemoveClass('focus')
		m_focus:FireEvent('defocus', newFocus)
		local p = m_focus
		while p ~= nil do
			p:FireEvent("childdefocus", focusInfo)
			p = p.parent
		end
	end

	m_focus = focusInfo.newFocus

	if m_focus then
		if m_focus.canFocus then
			m_focus.hasFocus = true
		end
		m_focus:AddClass('focus')
		m_focus:FireEvent('focus')

		local p = m_focus
		while p ~= nil do
			p:FireEvent("childfocus")
			p = p.parent
		end

		--we want to keep the dialog capturing escape since it will take care of defocusing on escape.
		if gamehud.dialog ~= nil and gamehud.dialog.sheet ~= nil then
			gamehud.dialog.sheet.captureEscape = true
		end
	else
		if gamehud.dialog ~= nil and gamehud.dialog.sheet ~= nil then
			gamehud.dialog.sheet.captureEscape = false
		end
	end
end

--- If a child in the hierarchy has the focus.
--- @return boolean
function gui.ChildHasFocus(panel)
	return panel ~= nil and panel.valid and panel.enabled and m_focus ~= nil and m_focus.valid and m_focus:IsDescendantOf(panel)
end

--- Get the main dialog panel which dialogs can be parented to.
--- @return Panel
function gui.DialogPanel()
	return gamehud.mainDialogPanel
end

--- Show the given dialog. Pass the mod to ensure the dialog will be destroyed if your mod is unloaded.
--- @param mod nil|CodeModInterface
--- @param dialog Panel
function gui.ShowDialog(mod, dialog)
	if dialog == nil then
		return
	end

	gamehud.mainDialogPanel:AddChild(dialog)
	dialog:PulseClass("fadein")

	if mod ~= nil then
		mod.unloadHandlers[#mod.unloadHandlers+1] = function()
			if dialog ~= nil and dialog.valid then
				dialog:DestroySelf()
			end
		end
	end
end

--- Show the given dialog over the map area. Pass the mod to ensure the dialog will be destroyed if your mod is unloaded.
--- @param mod nil|CodeModInterface
--- @param dialog Panel
function gui.ShowDialogOverMap(mod, dialog)
	if dialog == nil or rawget(_G, "gamehud") == nil then
		return
	end

	gamehud.dialogWorldPanel:AddChild(dialog)
	dialog:PulseClass("fadein")

	if mod ~= nil then
		mod.unloadHandlers[#mod.unloadHandlers+1] = function()
			if dialog ~= nil and dialog.valid then
				dialog:DestroySelf()
			end
		end
	end
end


--- Show a modal dialog.
--- @param panel Panel
--- @options {nofade: nil|boolean}
function gui.ShowModal(panel, options)
	gamehud:ShowModal(panel, options)
end

--- Close the modal dialog that is currently displayed.
function gui.CloseModal()
	gamehud:CloseModal()
end

--- Get the currently displayed modal dialog.
--- @return nil|Panel
function gui.GetModal()
	return gamehud:GetModal()
end

--- Display a modal message dialog.
--- @param args ModalMessageArgs
function gui.ModalMessage(args)
	gamehud:ModalMessage(args)
end

--- Show an upload dialog.
--- @param args UploadDialogArgs
function gui.UploadDialog(args)
	return gamehud:UploadDialog(args)
end



--- Create a button.
--- @param options LabelArgs
--- @return Label
function gui.Button(options)
	local args = {
		classes = {'button'},
	}

	if options.tooltip ~= nil then
		options.events = options.events or {}
		options.events.hover = gui.Tooltip(options.tooltip)
		options.tooltip = nil
	end

	if options.classes ~= nil then
		for _,c in ipairs(options.classes) do
			args.classes[#args.classes+1] = c
		end

		options.classes = nil
	end

	if options.icon ~= nil then
		args[#args+1] = gui.Panel{
			width = "100%",
			height = "100%",
			bgcolor = options.color or "white",
			bgimage = options.icon,
		}

		options.icon = nil
	end

	for k,option in pairs(options) do
		args[k] = option
	end

	return gui.Label(args)
end

--- Create a diamond shaped button.
--- @param options PanelArgs
--- @return Panel
function gui.DiamondButton(options)

	local icon = options.icon or "ui-icons/Plus.png"
	options.icon = nil

	local iconPanel = gui.Panel{
			width = "70%",
			height = "70%",
			bgimage = icon,
			bgcolor = options.color or "white",
			halign = "center",
			valign = "center",
		}
	
	options.color = nil


	local params = {
		flow = "none",
		borderWidth = 0,
		gui.Panel{
			--this panel is a background that isn't normally displayed, but can offer a backing if needed..
			classes = {"iconBackground"},
			width = "90%",
			height = "90%",
			bgimage = "panels/square.png",
			rotate = 45,
			halign = "center",
			valign = "center",
		},
		iconPanel,
		gui.Panel{
			classes = {"iconBorder"},
			styles = {
				gui.Style{
					selectors = {"iconBorder"},
					borderColor = options.borderColor or Styles.textColor,
				}
			},
			width = "80%",
			height = "80%",
			rotate = 45,
			borderWidth = options.borderWidth or 2,
			bgcolor = "clear",
			bgimage = "panels/square.png",
			halign = "center",
			valign = "center",
		},


		icon = function(element, iconid)
			iconPanel.bgimage = iconid
		end,
		display = function(element, display)
			for k,v in pairs(display) do
				iconPanel.selfStyle[k] = v
			end
		end,
	}

	options.borderWidth = nil
	options.borderColor = nil

	for k,v in pairs(options) do
		params[k] = v
	end

	return gui.Panel(params)
end

--- A little "plus" button for adding new items.
--- @param options PanelArgs
--- @return Panel
function gui.AddButton(options)

	local args = {
		classes = {'plus-button', "addButton"},
		bgimage = 'ui-icons/Plus.png',
		bgcolor = "white",
	}

	if options.tooltip ~= nil then
		options.events = options.events or {}
		options.events.hover = gui.Tooltip(options.tooltip)
		options.tooltip = nil
	end

	if options.classes ~= nil then
		for _,c in ipairs(options.classes) do
			args.classes[#args.classes+1] = c
		end

		options.classes = nil
	end

	for k,option in pairs(options) do
		args[k] = option
	end

	return gui.Panel(args)
end

--- A generic button in the same style as the "close button"
--- @param options PanelArgs
--- @return Panel
function gui.SimpleIconButton(options)
	local args = {
		classes = {'close-button', "closeButton", "iconButton"},
		bgimage = 'ui-icons/close.png',
	}

	if options.classes ~= nil then
		for _,c in ipairs(options.classes) do
			args.classes[#args.classes+1] = c
		end

		options.classes = nil
	end

	for k,option in pairs(options) do
		args[k] = option
	end

	return gui.Panel(args)
end


--- An "x" button for closing out dialogs.
--- @param options PanelArgs
--- @return Panel
function gui.CloseButton(options)
	local args = {
		classes = {'close-button', "closeButton"},
		bgimage = 'ui-icons/close.png',
		escapeActivates = true,
		escapePriority = EscapePriority.EXIT_DIALOG,
	}

	if options.classes ~= nil then
		for _,c in ipairs(options.classes) do
			args.classes[#args.classes+1] = c
		end

		options.classes = nil
	end

	for k,option in pairs(options) do
		args[k] = option
	end

	if options.press ~= nil then
		args.press = function (element)
			audio.FireSoundEvent("UI.WindowClose")
			options.press(element)
		end
	end


	return gui.Panel(args)
end

local g_deleteButtonStyles = {
	{
		priority = 10,
		selectors = {'delete-item-button'},
		bgcolor = "white",
	},
	{
		priority = 10,
		selectors = {'delete-item-button','hover'},
		bgcolor = "red",
	},
	{
		priority = 10,
		selectors = {'delete-item-button','press'},
		bgcolor = "#990000",
	},

}

--- A "trash can" button for deleting elements.
--- @param options PanelArgs
--- @return Panel
function gui.DeleteItemButton(options)
    local requireConfirm = options.requireConfirm or false
    options.requireConfirm = nil

	local args = {
		classes = {'delete-item-button', "deleteItemButton"},
		bgimage = 'icons/icon_tool/icon_tool_44.png',
		borderWidth = 0,
		styles = g_deleteButtonStyles,
	}

	if options.classes then
		for i,item in ipairs(options.classes) do
			args.classes[#args.classes+1] = item
		end
		options.classes = nil
	end

	if options.styles then
		local styles = {}
		for i,s in ipairs(args.styles) do
			styles[#styles+1] = s
		end
		for i,item in ipairs(options.styles) do
			styles[#styles+1] = item
		end
		options.styles = nil
		args.styles = styles
	end

	for k,option in pairs(options) do
		args[k] = option
	end

    for _,clickid in ipairs({"click", "press"}) do
        if requireConfirm and args[clickid] then
            local oldClick = args[clickid]
            args[clickid] = function(element)
                gui.ModalMessage{
                    title = "Confirm Delete",
                    message = "Are you sure you want to delete this item?",
                    options = {
                        {
                            text = "Cancel",
                            execute = function()
                                gui.CloseModal()
                            end,
                        },
                        {
                            text = "Delete",
                            execute = function()
                                oldClick(element)
                                gui.CloseModal()
                            end,
                        },
                    },
                }
            end
        end
    end

	return gui.Panel(args)
end

--- A "copy" button for copying items to the clipboard.
--- @param options PanelArgs
--- @return Panel
function gui.CopyButton(options)
	local args = {
		classes = {"iconButton"},
		bgimage = "icons/icon_app/icon_app_108.png",
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Panel(args)
end

--- A "gear" settings button.
--- @param options PanelArgs
--- @return Panel
function gui.SettingsButton(options)
	local args = {
		classes = {'iconButton', "settingsButton"},
		bgimage = 'ui-icons/skills/98.png',
	}

	if options.classes then
		for i,item in ipairs(options.classes) do
			args.classes[#args.classes+1] = item
		end
		options.classes = nil
	end

	for k,option in pairs(options) do
		if k == "icon" then
			--hack for old 'icon' key.
			args['bgimage'] = option
		else
			args[k] = option
		end
	end

	return gui.Panel(args)
end

--- A little icon button to show in the hud.
--- @param options PanelArgs
--- @return Panel
function gui.HudIconButton(options)
	local args = {
		classes = {"hudIconButton"},
		children = {
			gui.Panel{
				classes = {"hudIconButtonIcon"},
				interactable = false,
				bgimage = options.icon,
				seticon = function(element, icon)
					element.bgimage = icon
				end,

			}
		},
	}

	for _,c in ipairs(options.classes or {}) do
		args.classes[#args.classes+1] = c
	end
	options.classes = nil

	for k,option in pairs(options) do
		if k ~= 'icon' then
			args[k] = options[k]
		end
	end

	return gui.Panel(args)
end

--- A panel to put on top of a dialog and show a nice border.
--- @return Panel
function gui.DialogBorder()
	return gui.Panel{
		classes = {'dialog-border', "dialogBorder"},
		floating = true,
		interactable = false,
	}
end

--- A panel to border some parent element which has children inside of it.
--- @param args {image: nil|string, width: number, border: nil|number, grow: nil|number}
--- @return Panel
function gui.Border(args)
	return gui.Panel{
		bgimage = args.image or 'panels/InventorySlot_Border.png',
		floating = true,
		interactable = false,

		selfStyle = {
			bgcolor = "white",
			bgslice = args.width,
			border = args.border,
			width = '100%+' .. ((args.grow or 0)*2),
			height = '100%+' .. ((args.grow or 0)*2),
			halign = 'center',
			valign = 'center',
		}
	}
end

--- A panel to border some parent element which has children inside of it.
--- @param args {image: nil|string, width: number, border: nil|number, grow: nil|number}
--- @return Panel
function gui.PrettyBorder(args)
	local options = DeepCopy(args or {})
	if options.grow == nil then
		options.grow = 10
	end

	if options.width == nil then
		options.width = 18
	end

	return gui.Border(options)
end

local iconButtonIconStyle = gui.Style{
	width = '90%',
	height = '90%',
}

local iconButtonIconStyleFlipped = gui.Style{
	width = '90%',
	height = '90%',
	scale = {x = -1, y = 1},
}

--- A small button with an icon on it.
--- @param args PanelArgs
--- @return Panel
function gui.IconButton(args)
	local iconPanel = gui.Panel{
						bgimage = args.icon,
						styles = {
							cond(args.flipicon, iconButtonIconStyleFlipped, iconButtonIconStyle)
						},
					}
	local mainPanel = gui.Panel{
		bgimage = 'panels/ButtonSquareBackground.png',
		interactable = false,
		style = {
			margin = 0,
		},

		children = {
			gui.Panel{
				bgimage = 'panels/ButtonForegroundRed.png',
				styles = {
					{
						width = '80%',
						height = '80%',
						valign = 'center',
						halign = 'center',
					},
					{
						selectors = 'hover',
						brightness = 1.5,
						transitionTime = 0.1,
					},
					{
						selectors = 'press',
						brightness = 0.5,
					},
				},

				children = {
					iconPanel,
				}
			},
		},
	}

	local options = DeepCopy(args)
	options.icon = nil
	options.flipicon = nil
	options.children = {mainPanel}
	options.interactable = false

	options.style = options.style or {}
	options.style.bgcolor = 'white'

	options.data = options.data or {}
	options.data.SetIcon = function(iconid)
		iconPanel.bgimage = iconid
	end

	if options.tooltip ~= nil then
		options.events = options.events or {}
		options.events.hover = gui.Tooltip(options.tooltip)
		options.tooltip = nil
	end

	return gui.Panel(options)
end

local prettyButtonStyles = {
	gui.Style{
		classes = {'fancy-button'},
		width = 200,
		height = 80,
		opacity = 0,
	},
	gui.Style{
		classes = {'fancy-button-bg'},
		width = "100%",
		height = "100%",
		bgcolor = 'white',
		bgimage = 'panels/ButtonBackground.png',
		bgslice = 14,
		border = 8,
	},
	gui.Style{
		classes = {'fancy-button-fg'},
		width = "100%-10",
		height = "100%-10",
		halign = "center",
		valign = "center",
		bgcolor = '#ff463d',
		bgimage = 'panels/Button_RL_Foreground.png',
	},
	gui.Style{
		classes = {'fancy-button-fg', 'parent:hover'},
		brightness = 1.6,
		transitionTime = 0.2,
	},
	gui.Style{
		classes = {'fancy-button-fg', 'parent:press'},
		brightness = 0.8,
		width = "100%-12",
		height = "100%-12",
		transitionTime = 0.1,
	},
	gui.Style{
		classes = {'fancy-button-fg-overlay'},
		width = '100%',
		height = '100%',
		bgcolor = 'white',
		opacity = 0.15,
	},
	gui.Style{
		classes = {'fancy-button-label'},
		width = 'auto',
		height = 'auto',
		fontSize = 48,
		fontFace = 'SellYourSoul',
		color = '#ffedcf',
		halign = 'center',
		valign = 'center',
	},
	gui.Style{
		classes = {'fancy-button-label', 'parent:hover'},
		transitionTime = 0.1,
		brightness = 1.4,
	},
	gui.Style{
		classes = {'fancy-button-label', 'parent:press'},
		transitionTime = 0.1,
		brightness = 0.8,
	},
}

--- A fancy looking button
--- @param options PanelArgs
--- @return Panel
function gui.FancyButton(options)
	options = dmhub.DeepCopy(options or {})

	local text = options.text or ''
	options.text = nil
	
	local fontSize = options.fontSize
	options.fontSize = nil

	local panel = {
		classes = {'fancy-button'},
		styles = prettyButtonStyles,
		bgimage = 'panels/square.png',

		gui.Panel{
			classes = {'fancy-button-bg'},
			interactable = false,
		},

		gui.Panel{
			classes = {'fancy-button-fg'},
			interactable = false,
			gui.Panel{
				classes = {'fancy-button-fg-overlay'},
				interactable = false,
				bgimage = 'panels/Button_RL_Overlay1.png',
			},
			gui.Panel{
				classes = {'fancy-button-fg-overlay'},
				interactable = false,
				bgimage = 'panels/Button_RL_Overlay2.png',
			},
		},

		gui.Label{
			classes = {'fancy-button-label'},
			interactable = false,
			text = text,
			fontSize = fontSize,

		},


	}

	for k,v in pairs(options) do
		panel[k] = v
	end

	return gui.Panel(panel)
end

local PrettyButtonBackgroundStyles = {
	gui.Style{
		width = "100%-12",
		height = "100%-12",
		halign = 'center',
		valign = 'center',
	},
	gui.Style{
		selectors = 'hover',
		brightness = 1.5,
		transitionTime = 0.1,
	},
	gui.Style{
		selectors = 'press',
		brightness = 2,
	},

	gui.Style{
		selectors = 'disabled',
		brightness = 0.5,
	},

}

--- A pretty looking button
--- @param options PanelArgs
--- @return Panel
function gui.PrettyButton(args)
	local classes = args.classes or {}
	if type(classes) == "string" then
		classes = {classes}
	end
	classes[#classes+1] = "prettyButton"
	args.classes = classes
	return gui.Button(args)

--local mainPanel = gui.Panel({
--	bgimage = 'panels/ButtonBackground.png',
--	interactable = false,
--	style = {
--		width = '100%',
--		height = '100%',
--		bgslice = 12,
--		margin = 0,
--	},

--	children = {
--		gui.Panel{
--			bgimage = 'panels/ButtonForegroundRed.png',
--			styles = PrettyButtonBackgroundStyles,

--			children = {
--				gui.Label{
--					classes = {'pretty-button-label'},
--					text = args.text or 'TEXT',
--					fontSize = args.fontSize or "100%",
--					settext = function(element, t)
--						element.text = t
--					end,
--				}
--			}
--		}
--	}
--})

--local style = DeepCopy(args.style) or {}

--style.margin = style.margin or 0
--style.pad = style.pad or 0
--style.flow = 'none'
--style.bgcolor = style.bgcolor or 'white'

--local options = DeepCopy(args)
--if type(options.classes) == "string" then
--	options.classes = {options.classes}
--end
--options.classes = options.classes or {}
--options.classes[#options.classes+1] = 'pretty-button'
--options.text = nil
--options.style = style
--options.children = { mainPanel }
--options.interactable = false

--return gui.Panel(options)
end

-- diamond

--- A diamond shaped panel
--- @param options PanelArgs
--- @return Panel
function gui.Diamond(options)

	local editable = options.editable
	if editable == nil then
		editable = true
	end

	options.editable = nil

	local fill = 
				gui.Panel{
				
					classes = {cond(options.value, "on")},
					width = 20,
					height = 20,
					halign = "center",
					valign = "center",
					bgimage = "panels/square.png",
				
					styles = {
						{
							bgcolor = "clear",
						},
						
						{
							selectors = {"on"},
							transitionTime = 0.15,
							bgcolor = options.fillColor or Styles.textColor,
						},
					},
				}
				
	options.fillColor = nil
	options.value = nil
				
	
	local defaults = {
		
		width = 30,
		height = 30,
		halign = "left",
		bgimage = "panels/square.png",
		bgcolor = Styles.backgroundColor,
		border = 3,
		borderColor = Styles.textColor,
		tmargin = 20,
		rotate = 45,
		
		click = function(self)
			if not editable then
				return
			end
			if fill:HasClass("on") then
				fill:SetClass("on", false)
			else
				fill:SetClass("on", true)
			end

			self:FireEvent("change")
	
		end,
		
		fill,
	}
	
	--override defaults for diamond with new style options
	for name, value in pairs (options) do
		
		defaults[name] = value
	
	end


	defaults.GetValue = function(element, val)
		return fill:HasClass("on")
	end

	defaults.SetValue = function(element, val, firechange)

		if fill:HasClass("on") ~= val then
			fill:SetClass("on", val)
			if firechange ~= false then
				element:FireEvent('change')
			end
		end
	end
		
	return gui.Panel(defaults)
		
end

--- @class CheckBoxArgs:PanelArgs
--- @field text string
--- @field customPanel nil|Panel
--- @field placement nil|"left"|"right"
--- @field value boolean Whether the checkbox is checked or not.

--- A check box.
--- @param args CheckBoxArgs
--- @return Panel
function gui.Check(args)

	local customPanel = args.customPanel
	args.customPanel = nil

	local placement = args.placement or "left"
	args.placement = nil

	local fontSize = args.fontSize
	args.fontSize = nil

    local tooltip = args.tooltip
    args.tooltip = nil

	local colon = cond(placement == "right", ":", "")
	
	local options = dmhub.DeepCopy(args)
	local checked = options.value or false
	options.value = nil

	local checkMark = gui.Panel{
		classes = {'check-mark'},
		hmargin = 0,
		vmargin = 0,
        floating = true,
	}

	options.GetValue = function(element, val)
		return checked
	end

	options.SetValue = function(element, val, firechange)
		checkMark:SetClass('hidden', not val)

		if checked ~= val then
			checked = val
			if firechange ~= false then
				element:FireEvent('change')
			end
		end
	end

	checkMark:SetClass('hidden', not checked)

	local checkPanel = gui.Panel{
		classes = {'check-background'},

		children = {
			checkMark
		},
	}

	local text = options.text
	options.text = nil

	local label = gui.Label{
		classes = {'checkbox-label', cond(placement == "right", "rightAlign")},
		text = text .. colon,
		fontSize = fontSize,
	}

	local resultPanel

	options.classes = options.classes or {}
	if type(options.classes) == "string" then
		--allow options.classes to be passed in as a string.
		options.classes = {options.classes}
	end
	options.classes[#options.classes+1] = 'checkbox'

	if placement == "left" then
		options.children = {checkPanel, customPanel, label}
	else
		options.children = {label, customPanel, checkPanel}
	end

	options.events = options.events or {}
	options.events.press = function(element)
		if resultPanel:HasClass("disabled") then
			return
		end
		element.value = not checked
	end

	options.events.keybind = function(element, key)
		options.events.press(element)
	end

    if tooltip ~= nil then
        options.events.linger = gui.Tooltip(tooltip)
    end

	options.data = options.data or {}
	options.data.GetText = function()
		return text
	end
	options.data.SetText = function(t)
		text = t
		label.text = text .. colon
	end


	resultPanel = gui.Panel(options)
	return resultPanel
end


local PercentSliderStyles = {
	gui.Style{
		classes = {"percentSlider"},
		borderWidth = 1,
		borderColor = Styles.textColor,
		cornerRadius = 2,
		bgimage = "panels/square.png",
		bgcolor = "black",
		height = 14,
		flow = "none",
	},
	gui.Style{
		classes = {"percentSliderLabel"},
		color = Styles.textColor,
		bold = true,
		fontSize = 10,
		halign = "left",
		valign = "center",
		width = 40,
		textAlignment = "center",
		height = "auto",
	},
	gui.Style{
		classes = {"percentSliderLabel", "fill"},
		color = "black",
	},
	gui.Style{
		classes = {"percentFill"},
		bgcolor = Styles.textColor,
		height = "100%",
		width = "0%",
		halign = "left",
		cornerRadius = 2,
	},
}

--- A percentage slider.
--- @param args PanelArgs
--- @return Panel
function gui.PercentSlider(args)
	local resultPanel

	local value = args.value or 0
	args.value = nil

	local width = args.width or 80
	args.width = width

	local label = gui.Label{
		classes = {"percentSliderLabel"},
		text = "100%",
		x = (width-40)/2,
		refreshValue = function(element)
			element.text = string.format("%d%%", round(value*100))
		end,
	}

	local fillLabel = gui.Label{
		classes = {"percentSliderLabel", "fill"},
		text = "100%",
		x = (width-40)/2,
		refreshValue = function(element)
			element.text = string.format("%d%%", round(value*100))
		end,
	}

	local fill = gui.Panel{
		id = "clipFill",
		classes = {"percentFill"},
		bgimage = "panels/square.png",
		clip = true,
		clipHidden = false,
		fillLabel,
		refreshValue = function(element)
			element.selfStyle.width = string.format("%d%%", round(value*100))
		end,
	}

	local params = {
		debugLogging = true,

		classes = {"percentSlider"},
		styles = PercentSliderStyles,
		swallowPress = true,
		label,
		fill,

		draggable = true,
		dragMove = false,

		click = function(element)
		end,

		press = function(element)
			local x = element.mousePoint.x
			element.value = clamp(x, 0, 1)
			element:FireEvent("confirm")
		end,

		dragging = function(element)
			local x = element.mousePoint.x
			element.value = clamp(x, 0, 1)
			element:FireEvent("preview")
		end,

		drag = function(element)
			element:FireEvent("confirm")
		end,

		GetValue = function(element)
			return value
		end,

		SetValue = function(element, val, fireEvent)
			value = val or 0
			resultPanel:FireEventTree("refreshValue")
            if fireEvent then
			    element:FireEvent("change")
            end
		end,
	}

	for k,a in pairs(args) do
		params[k] = a
	end

	resultPanel = gui.Panel(params)

	resultPanel:FireEventTree("refreshValue")

	return resultPanel
end

--- @class SliderArgs:PanelArgs
--- @field handleSize nil|number|string Can be an absolute number or a percent.
--- @field notchHeight nil|number
--- @field notchColor nil|string|Color
--- @field fillColor nil|string|Color
--- @field notchAlign nil|string

--- Slider. Fires 'change' whenever the value changes and 'confirm' when a change is completed
--- through editing (through dragging and finishing the drag or through editing the label).
--- change is fired if the value is changed programmatically but data.setValueNoEvent() is provided
--- to allow calling without firing change.
--- also fires 'preview' specifically when dragging, and guaranteed to have a 'confirm' once dragging finishes.
--- @param args SliderArgs
--- @return Panel
function gui.Slider(args)

	local handleItem
	local sliderFill

	local handleSize = args.handleSize or "100%"
	args.handleSize = nil

	local notchHeight = args.notchHeight or 2
	args.notchHeight = nil

	local notchColor = args.notchColor or 'grey'
	args.notchColor = nil

	local fillColor = args.fillColor or '#880000'
	args.fillColor = nil

	local notchAlign = args.notchAlign or 'center'
	args.notchAlign = nil

	local options = dmhub.DeepCopy(args)

	local unclamped = options.unclamped or false
	options.unclamped = nil

	local clampfn = clamp
	if unclamped then
		clampfn = function(value)
			return value
		end
	end

	options.className = 'slider'

	local formatFunction = options.formatFunction or nil
	options.formatFunction = nil

	local deformatFunction = options.deformatFunction or nil
	options.deformatFunction = nil

	local wrap = options.wrap
	options.wrap = nil

	local roundValues = options.round or false
	options.round = nil

	local minValue = options.minValue
	options.minValue = nil
	minValue = tonum(minValue)

	local maxValue = options.maxValue
	options.maxValue = nil
	maxValue = tonum(maxValue, 1)

	local value = options.value
	options.value = nil
	if value == nil then
		value = minValue
	end

	value = clampfn(value, minValue, maxValue)

	maxValue = max(value, maxValue)
	minValue = min(value, minValue)

	local NormalizedValue = function()
		return (value - minValue) / (maxValue - minValue)
	end

	local sliderWidth = options.sliderWidth or 100
	options.sliderWidth = nil

	local labelWidth = options.labelWidth
	options.labelWidth = nil

	local labelFormat = options.labelFormat
	options.labelFormat = nil

	options.events = options.events or {}

	options.events.hover = function(element)
		handleItem.bgimage = 'panels/slider-active.png'
	end

	options.events.dehover = function(element)
		handleItem.bgimage = 'panels/slider-inactive.png'
	end

	options.flow = 'horizontal'

	local mainPanel

	if options.doubleclick == nil then
		local defaultValue = options.defaultValue
		if defaultValue == nil then
			defaultValue = value
		end

		options.doubleclick = function(element)
			if defaultValue ~= nil then
				element.value = defaultValue
			end
		end
	end

	options.defaultValue = nil



	mainPanel = gui.Panel(options)

	mainPanel.data.getValue = function() return value end
	mainPanel.data.setValue = function(val, fireevent)
		if roundValues then
			val = round(val)
		end

		local newValue = clampfn(val, minValue, maxValue)

		if newValue ~= value then
			value = newValue

			--if unclamped then we reconsider min/max.
			maxValue = max(value, maxValue)
			minValue = min(value, minValue)

			if fireevent ~= false then
				mainPanel:FireEventTree('updateValue')
				mainPanel:FireEvent('change')
			end
		else
			if fireevent ~= false then
				mainPanel:FireEventTree('updateValue')
			end
		end
	end
	mainPanel.data.setValueNoEvent = function(val)
		if roundValues then
			val = round(val)
		end

		local newValue = clampfn(val, minValue, maxValue)
		if value == newValue then
			return
		end

		value = newValue

		--if unclamped then we reconsider min/max.
		maxValue = max(value, maxValue)
		minValue = min(value, minValue)

		mainPanel:FireEventTree('updateValue')
	end
	mainPanel.data.setNormalizedValue = function(val)
		mainPanel.data.setValue(minValue + (maxValue-minValue)*val)
	end

	mainPanel.GetValue = mainPanel.data.getValue
	mainPanel.SetValue = function(element, val, fireevent) mainPanel.data.setValue(val, fireevent) end

	handleItem = gui.Panel{
		height = handleSize,
		width = "100% height",

		gui.Panel{
			classes = {"sliderHandleBorder"},
			rotate = 45,
			pivot = {0.5,0.5},

		},

		gui.Panel{
			classes = {"sliderHandleInner"},
			rotate = 45,
			pivot = {0.5,0.5},
		},

		margin = 0,
		pad = 0,
		halign = 'center',
		valign = 'center',
	}


	local handley = cond(notchAlign == "top", 4, 0)
	local handle = gui.Panel({
		id = 'slider-handle',
		draggable = true,
		dragBounds = { x1 = 0, y1 = handley, x2 = sliderWidth, y2 = handley },
		dragxwrap = wrap,

		style = {
			y = -handley,
			width = 1,
			height = "100%",
			valign = notchAlign,
			halign = 'left',
			flow = 'none',
		},

		children = {
			handleItem,
		},

		events = {
			setwrap = function(element, val)
				wrap = val
				element.dragxwrap = val
			end,

			drag = function(element)
				--mainPanel.data.setNormalizedValue(clamp(element.xdrag / sliderWidth, 0, 1))
				mainPanel.data.setNormalizedValue(NormalizedValue())
				mainPanel:FireEvent('confirm')
			end,
			dragging = function(element)
				mainPanel.data.setNormalizedValue(clamp(element.xdrag / sliderWidth, 0, 1))
				mainPanel:FireEvent('preview')
			end,
			updateValue = function(element)
				if element.dragging == false then
					element.x = sliderWidth * NormalizedValue()
				end
			end
		},
	})

	mainPanel.data.handle = handleItem

	sliderFill = gui.Panel{
		id = 'slider-fill',
		bgimage = 'panels/square.png',
		selfStyle = {
			width = 1,
			height = 2,
			borderWidth = 0,
			bgcolor = "white",
			halign = 'left',
			valign = notchAlign,
		},
		events = {
			updateValue = function(element)
				element.selfStyle.width = math.floor(sliderWidth * NormalizedValue())
			end,
		},
	}

	local sliderPanel = gui.Panel({
		id = 'slider-panel',
		style = {
			cornerRadius = 0,
			width = sliderWidth,
			height = '100%',
			halign = 'left',
			pad = 0,
			margin = 0,
			hmargin = 0,
			vmargin = 0,
			flow = 'none',
		},
		children = {
			--the slider notch.
			gui.Panel{
				id = 'slider-notch',
				bgimage = 'panels/square.png',
				style = {
					width = '100%',
					height = notchHeight,
					borderWidth = 0,
					bgcolor = notchColor,
					valign = notchAlign,
					halign = 'center',
				}
			},

			sliderFill,

			--clickable area.
			gui.Panel{
				id = 'slider-click-area',
				bgimage = 'panels/square.png',
				styles = {
					{
						width = '100%',
						height = '100%',
						opacity = 0,
						bgcolor = 'white',
					},

				},

				events = {
					press = function(element)
						mainPanel.data.setNormalizedValue(element.mousePoint.x)
						mainPanel:FireEvent('confirm')
					end
				},
			},
			handle,
		}
	})

	local formatStr = nil
	if labelFormat == 'percent' or labelFormat == 'rawpercent' then
		formatStr = '{0}%'
	end

	local labelPanel = nil
	if labelWidth then
		labelPanel = gui.Label({
			id = 'slider-label',
			text = 'LAB',
			classes = {"sliderLabel"},
			editable = true,
			format = formatStr,
			style = {
				halign = 'right',
				valign = 'center',
				width = labelWidth,
				height = "auto",
				textAlignment = 'center',
				hmargin = 2,
			},

			events = {
				updateValue = function(element)
					if formatFunction ~= nil then
						element.text = formatFunction(value)
					elseif labelFormat == 'percent' then
						element.text = string.format('%d', round(NormalizedValue()*100))
					elseif labelFormat == 'rawpercent' then
						element.text = string.format('%d', round(value*100))
					elseif labelFormat ~= nil then
						local val = value
						if string.find(labelFormat, "%%d") then
							val = round(val)
						end

						element.text = string.format(labelFormat, val)
					else
						element.text = string.format('%.2f', value)
					end
				end,
				change = function(element)
					local num = tonumber(element.text)
					if num == nil then
						mainPanel.data.setValue(mainPanel.data.getValue())
					else
						if deformatFunction ~= nil then
							mainPanel.data.setValue(deformatFunction(num))
						elseif labelFormat == 'percent' then
							num = num/100
							mainPanel.data.setNormalizedValue(num)
						elseif labelFormat == 'rawpercent' then
							num = num/100
							mainPanel.data.setValue(num)
						else
							mainPanel.data.setValue(num)
						end

						mainPanel:FireEvent('confirm')
					end
				end
			},
		})
	end

	mainPanel.children = {
		sliderPanel,
		labelPanel,
	}

	mainPanel:FireEventTree('updateValue')

	return mainPanel
end

--- @class ColorPickerArgs:PanelArgs
--- @field hasAlpha nil|boolean @Default=true Whether the picker has a bar for alpha.
--- @field hdrRange nil|boolean @Default=1 Set to above 1 to allow this color to include colors brighter than 100%.
--- @field value nil|Color|string The color value selected in the picker.

--- @class ColorPicker:Panel
--- @field value string|Color The color value picked by the color picker.

--- Create a color picker.
--- @param args ColorPickerArgs
--- @return ColorPicker
function gui.ColorPicker(args)
	local options = dmhub.DeepCopy(args)

	local hasAlpha = options.hasAlpha
	if hasAlpha == nil then
		hasAlpha = true
	end

	local hdrRange = options.hdrRange or 1

	options.hasAlpha = nil
	options.hdrRange = nil

	local popupAlignment = options.popupAlignment or 'right'
	options.popupAlignment = nil

	local color = core.Color(options.value)
	options.value = nil

	options.className = 'color-picker'

	if options.data == nil then
		options.data = {}
	end

	local mainPanel = nil

	options.data.getColor = function()
		return color
	end

	options.data.setColor = function(val, fireevent)
		if type(val) == "string" then
			val = core.Color(val)
		end
		color = val
		if fireevent ~= false then
			mainPanel:FireEvent('valueChanged')
		end
	end

	if options.events == nil then
		options.events = {}
	end

	local CreateChannelSlider = function(channelName, channel)
		

		local slider = 
				gui.Slider({
					bgimage = 'panels/square.png',
					value = color[channel],
					minValue = 0,
					maxValue = 1,
					labelFormat = 'percent',
					sliderWidth = 400,
					labelWidth = 40,

					style = {
						bgcolor = 'white',
						borderWidth = 0,
						fontSize = '30%',
						height = 24,
						width = 460,
						halign = 'left',
					},

					data = {
					},

					events = {
						create = function(element)
							element:FireEvent('valueChanged')

							local stops = {}

							local col = nil
							
							if channel == 'hue' then
								col = core.Color('red')
							else
								col = core.Color('white')
							end

							col[channel] = 0
							stops[#stops+1] = { position = 0, color = DeepCopy(col) }
							
							if channel == 'hue' then
								local a = 0.1
								while a <= 0.9 do
									col[channel] = a
									stops[#stops+1] = { position = a, color = DeepCopy(col) }
									a = a + 0.1
								end
							end

							col[channel] = 1
							stops[#stops+1] = { position = 0.99, color = DeepCopy(col) }

							col['alpha'] = 0
							stops[#stops+1] = { position = 1, color = DeepCopy(col) }


							element.selfStyle.gradient = {
								point_a = {x = 0, y = 0},
								point_b = {x = 4.0/4.6, y = 0},
								stops = stops
							}

						end,
						change = function(element)
							color[channel] = element.data.getValue()
							options.data.setColor(color)
						end,
						valueChanged = function(element)

							element.data.setValueNoEvent(color[channel])
							if channel == 'hue' then
								element.data.handle.selfStyle.bgcolor = color:Modify{a = 1}
							end
							element.data.handle.selfStyle.height = '100%'
							element.data.handle.selfStyle.width = '100% height'
							element.data.handle.selfStyle.cornerRadius = '50% height'
						end,
					},

				})

		return gui.Panel({
			style = {
				halign = 'left',
				flow = 'horizontal',
				height = 24,
				width = 'auto',
			},

			children = {
				gui.Label{
					text =  channelName .. ':',
					classes = {"channelLabel"},
				},

				slider,
			},
		})
	end

	local CreateGradientPanel = function()
		local w = 512
		local h = 196
		return gui.Panel{
			bgimage = 'panels/square.png',
			selfStyle = {
				bgcolor = "white",
				gradient = {
					point_a = {x = 0, y = 0},
					point_b = {x = 1, y = 0},
					stops = {
						{position = 0, color = core.Color{r = 1*hdrRange, g = 1*hdrRange, b = 1*hdrRange, a = 1}},
						{position = 1, color = core.Color{r = 1, g = 0, b = 0, a = 1}},
					}
				}
			},
			styles = {
				borderWidth = 0,
				valign = 'top',
				width = w,
				height = h,
				flow = 'none',
			},

			events = {
				create = function(element)
					element:FireEvent('valueChanged')
				end,
				valueChanged = function(element)
					local saturatedColor = DeepCopy(color)
					saturatedColor.a = 1
					saturatedColor.saturation = 1
					saturatedColor.value = 1
					local desaturatedColor = DeepCopy(saturatedColor)
					desaturatedColor.saturation = 0
					element.selfStyle.gradient = {
						point_a = {x = 0, y = 0},
						point_b = {x = 1, y = 0},
						stops = {
							{position = 0, color = desaturatedColor},
							{position = 1, color = saturatedColor},
						}
					}
				end,

				click = function(element)
					color.saturation = element.mousePoint.x
					color.value = LinearTosRGB(element.mousePoint.y*hdrRange)
					options.data.setColor(color)
				end
			},

			children = {
				gui.Panel{
					bgimage = 'panels/square.png',
					interactable = false,
					selfStyle = {
						bgcolor = "white",
						gradient = {
							point_a = {x = 0, y = 0},
							point_b = {x = 0, y = 1},
							stops = {
								{position = 0, color = core.Color{r = 0, g = 0, b = 0, a = 1}},
								{position = 0.1, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.9)}},
								{position = 0.2, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.8)}},
								{position = 0.3, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.7)}},
								{position = 0.4, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.6)}},
								{position = 0.5, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.5)}},
								{position = 0.6, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.4)}},
								{position = 0.7, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.3)}},
								{position = 0.8, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.2)}},
								{position = 0.9, color = core.Color{r = 0, g = 0, b = 0, a = LinearTosRGB(0.1)}},
								{position = 1, color = core.Color{r = 0, g = 0, b = 0, a = 0}},
							}
						},
					},

					styles = {
						width = '100%',
						height = '100%',
					},
				},

				--the main handle we can drag around.
				gui.Panel{
					bgimage = 'panels/square.png',
					draggable = true,
					dragBounds = { x1 = -w*0.5, y1 = -h*0.5, x2 = w*0.5, y2 = h*0.5 },

					events = {
						create = function(element)
							element:FireEvent('valueChanged')
						end,
						drag = function(element)
							color.saturation = (element.xdrag + w*0.5)/w
												color.value = LinearTosRGB(element.mousePoint.y*hdrRange)

							color.value = LinearTosRGB(hdrRange*(-element.ydrag + h*0.5)/h)
							options.data.setColor(color)
						end,
						dragging = function(element)
							color.saturation = (element.xdrag + w*0.5)/w
							color.value = LinearTosRGB(hdrRange*(-element.ydrag + h*0.5)/h)
							options.data.setColor(color)
						end,
						valueChanged = function(element)
							element.selfStyle.bgcolor = color:Modify{a = 1}
							if element.dragging == false then
								element.x = -w*0.5 + color.saturation*w
								element.y = h*0.5 - (sRGBToLinear(color.value)/hdrRange)*h
							end
						end
					},

					selfStyle = {},

					styles = {
						{
							width = 24,
							height = 24,
							cornerRadius = 12,
							borderWidth = 2,
							borderColor = 'black',
							valign = 'center',
							halign = 'center',
						},
						{
							selectors = 'hover',
							borderColor = 'white',
						},
					}
				}
			}
		}
	end

	local startPopupColor = nil

	options.events.click = function(element)
		if element.popup ~= nil then
			element.popup = nil
			return
		end

		local alphaSlider = nil
		if hasAlpha then
			alphaSlider = CreateChannelSlider('Opacity', 'alpha')
		end

		local hexInput = gui.Input{
			width = 128,
			height = 20,
			fontSize = 14,
			halign = "left",
			text = color.tostring,
			change = function(element)
				color.tostring = element.text
				options.data.setColor(color)
			end,
			valueChanged = function(element)
				element.text = color.tostring
			end,
		}

		local hexPanel = gui.Panel{
			flow = "horizontal",
			halign = "left",
			height = 24,
			gui.Label{
				text =  "Hex:",
				classes = {"channelLabel"},
			},

			hexInput,
		}



		startPopupColor = color.tostring

		element.popupPositioning = 'panel' --signal that we want the popup positioned relative to the panel, not the mouse.
		element.popup = gui.Panel({
			id = 'color-picker-popup',
			bgimage = 'panels/square.png',
			captureEscape = true,
			styles = {
				Styles.Default,
				{
					halign = popupAlignment,
					valign = 'center',
					width = 512,
					height = 280,
					bgcolor = 'grey',
					borderWidth = 2,
					borderColor = 'black',
					flow = 'vertical',
				},
				{
					selectors = {"channelLabel"},
					fontSize = '35%',
					width = '10%',
					halign = 'left',
					valign = 'center',
					textAlignment = 'right',
					hmargin = 4,
				},
			},

			children = {
				CreateGradientPanel(),
				--CreateChannelSlider('Red'),
				--CreateChannelSlider('Green'),
				--CreateChannelSlider('Blue'),
				CreateChannelSlider('Hue', 'hue'),
				alphaSlider,
				hexPanel,
				--CreateChannelSlider('Saturation'),
				--CreateChannelSlider('Value'),
			},

			events = {
				escape = function(popup)
					element.popup = nil
				end
			},
		})
	end

	options.events.valueChanged = function(element)
		mainPanel.selfStyle.bgcolor = color
		if element.popup ~= nil then
			mainPanel:FireEvent('change')
			element.popup:FireEventTree('valueChanged')
		end
	end

	options.events.closePopup = function(element)
		if color.tostring ~= startPopupColor then
			element:FireEvent('confirm')
		end
	end

	if options.bgimage == nil then
		options.bgimage = 'panels/square.png'
	end

	local styles = {
		{
			width = '100%',
			height = '100%',
		}
	}

	if options.styles ~= nil then
		for i,s in ipairs(options.styles) do
			styles[#styles+1] = s
		end
	end

	options.styles = styles

	if options.selfStyle == nil then
		options.selfStyle = {}
	end

	mainPanel = gui.Panel(options)

	mainPanel.selfStyle.bgcolor = color

	mainPanel.GetValue = function(element)
		return options.data.getColor()
	end

	mainPanel.SetValue = function(element, col, fireevent)
		options.data.setColor(col, fireevent)
	end

	return mainPanel
end

local triangleStyles = {

	gui.Style{
		bgcolor = 'white',
		width = 8,
		height = 8,
		halign = 'left',
		margin = 5,
		rotate = 90,
		valign = "center",
	},
	gui.Style{
		selectors = {'hover'},
		transitionTime = 0.1,
		bgcolor = 'yellow',
	},
	gui.Style{
		selectors = {'expanded'},
		transitionTime = 0.2,
		rotate = 0,
	},
}

gui.TriangleStyles = triangleStyles

--- @class TreeNodeArgs:PanelArgs
--- @field text string
--- @field panelHeight nil|number
--- @field contentPanel Panel
--- @field editable nil|boolean
--- @field characterLimit nil|integer
--- @field collapsedClass nil|string (Default="collapsed") set to make this use a different class to indicate collapsed.

--- Create a node in a tree. When collapsed, its contentPanel will be hidden.
--- @param args TreeNodeArgs
--- @return Panel
function gui.TreeNode(args)

	local options = dmhub.DeepCopy(args)

	local text = options.text
	options.text = nil

	local panelHeight = options.panelHeight or 30
	options.panelHeight = nil

	local contentPanel = options.contentPanel
	options.contentPanel = nil

	local editable = options.editable
	options.editable = nil

	local characterLimit = options.characterLimit or 32
	options.characterLimit = nil

	local dragTarget = options.dragTarget
	options.dragTarget = nil

	local collapsedClass = options.collapsedClass or "collapsed"
	options.collapsedClass = nil

	if contentPanel == nil then
		dmhub.Error('gui.TreeNode must have a contentPanel')
	end

	local isCollapsed = not options.expanded
	options.expanded = nil

	local refreshCollapsed = function()
		contentPanel:SetClass(collapsedClass, isCollapsed)
		if not isCollapsed then
			contentPanel:FireEvent('expand')
		end
	end

	refreshCollapsed()

	local resultPanel = nil

	local triangle = gui.Panel({
				id = 'Triangle',
				bgimage = 'panels/triangle.png',
				classes = {"triangle", cond(not isCollapsed, "expanded")},
				styles = triangleStyles,


				events = {
					click = function(element)
						element:FireEvent("toggle")
					end,
					create = function(element)
						element:SetClass('expanded', not isCollapsed)
					end,
					toggle = function(element)
						isCollapsed = not isCollapsed
						element:SetClass('expanded', not isCollapsed)
						refreshCollapsed()

						if not isCollapsed then
							resultPanel:FireEvent('expand')
						end
					end,
				},
			})

	local headerPanel = gui.Panel({
		
		classes = {"folder"},
		bgimage = 'panels/square.png',

		dragTarget = dragTarget,

		selfStyle = {
			valign = 'top',
			halign = 'left',
			width = "100%",
			height = panelHeight,
			flow = 'horizontal',
		},

		styles = {
			{
				borderWidth = 0,
				bgcolor = '#ffffff00',
			},
			{
				selectors = {'hover'},
				bgcolor = '#ffffff88',
			},
		},

		events = {
			rightClick = function(element)
				resultPanel:FireEvent('contextMenu')
			end,
		},

		children = {
			triangle,

			gui.Label({
				classes = {"folderLabel"},
				editable = editable,
				text = text,
				characterLimit = characterLimit,
				events = {
					text = function(element, newText)
						element.text = newText
						text = newText
					end,
					change = function(element)
						resultPanel:FireEvent('change', element.text)
					end,
				},
				styles = {
					{
						fontSize = "70%",
						width = 'auto',
						height = 'auto',
						halign = 'left',
						valign = 'center',
					}
				}
			}),
		},
	})

	if options.style == nil then
		options.style = {}
	end

	if options.selfStyle == nil then
		options.selfStyle = {}
	end

	options.style.valign = 'top'
	options.style.height = 'auto'

	options.selfStyle.pivot = { x = 0, y = 1 }
	options.selfStyle.pad = 0
	options.selfStyle.margin = 0
	options.selfStyle.flow = 'vertical'
	options.data = options.data or {}
	options.data.isCollapsed = function() return isCollapsed end
	options.data.toggleCollapsed = function() triangle:FireEvent('click') end

	options.setempty = function(element, val)
		triangle:SetClass("empty", val)
	end

	options.click = function(element)
		triangle:FireEvent("toggle")
	end

	options.children = {
		headerPanel,
		contentPanel,
	}

	resultPanel = gui.Panel(options)

	return resultPanel
end

--- Given a panel, returns it nicely framed in a tooltip.
--- @param panel Panel The panel containing the contents of the tooltip.
--- @param params PanelArgs
--- @return Panel
function gui.TooltipFrame(panel, params)
	params = params or {}
	local args = {
		classes = {"tooltipFrame"},
		bgimage = "panels/square.png",
		hpad = 24,
		vpad = 14,
		width = "auto",
		height = "auto",
		cornerRadius = 10,
		bgcolor = "#000000fa",
		borderColor = "#000000fa",
		borderWidth = 10,
		borderFade = true,
		valign = "bottom",
		halign = "center",
		children = {panel},
		interactable = false,
	}

	for k,v in pairs(params) do
		args[k] = v
	end

	return gui.Panel(args)
end

--- function called by DMHub to create a tooltip from text.
--- @param args string|LabelArgs
--- @return Panel
function CreateTooltipPanel(args)
	local style = {
			fontSize = '60%',
			hpad = 24,
			vpad = 14,
			cornerRadius = 10,
			bgcolor = '#000000fa',
			borderColor = '#000000fa',
			borderWidth = 10,
			borderFade = true,
			maxWidth = 500,
			width = 'auto',
			height = 'auto',
			valign = 'bottom',
			halign = 'center',
	}

	local text = nil
	if type(args) == 'string' then
		text = args
	else
		text = args.text
		for k,v in pairs(args) do
			if k ~= 'text' then
				style[k] = v
			end
		end
	end

	return gui.Label({
		classes = {'tooltip'},
		bgimage = 'panels/square.png',
        markdown = true,
		text = text,
		interactable = false,
		styles = {
			style,
			{
				selectors = {"create"},
				transitionTime = 0.2,
				opacity = 0,
			},
		},
	})
end

--- Returns a function that works as an event handler to create a tooltip.
--- @param args string|LabelArgs Can be passed as just a plain string in which case a sensible tooltip will be created, or a panel styled however you choose.
--- @return nil|function
function gui.Tooltip(args)
    if args == nil then
        return nil
    end

	return function(element)
		local result = CreateTooltipPanel(args)
		element.tooltip = result
		return result
	end
end

--- Given a history of stats @see StatsHistory will render a tooltip displaying it.
--- provide text to give extra text that will display
--- @param args {entries: StatHistoryEntry[], description: string, text = nil|string}
--- @return Panel
function gui.StatsHistoryTooltip(args)
	local entries = {}

	local refreshid = nil

	for i,entry in ipairs(args.entries) do
		if entry.refreshid ~= refreshid then
			entries = {}
		end

		entries[#entries+1] = entry
		refreshid = entry.refreshid
	end


	local entryPanels = {}

    if args.text then
        entryPanels[#entryPanels+1] = {
            gui.Label{
                text = args.text,
                style = {
                    width = "auto",
                    height = "auto",
                    margin = 2,
                    fontSize = 20,
                }
            }
        }
    end

	if #entries == 0 then
        entryPanels[#entryPanels+1] = {
            gui.Label{
                text = "No changes recorded for " .. args.description,
                style = {
                    width = "auto",
                    height = "auto",
                    margin = 2,
                    fontSize = 20,
                }
            }
        }
    else
        entryPanels[#entryPanels+1] = {
            gui.Label{
                text = "Recent changes to " .. args.description,
                style = {
                    width = "auto",
                    height = "auto",
                    margin = 2,
                    fontSize = 20,
                }
            }
        }
	end

	for i,entry in ipairs(entries) do
		local val = entry.value
		if tonumber(val) ~= nil then
			val = round(tonumber(val))
		end
		local description = string.format("Set to <b>%s</b> by <b>%s</b> %s (%s)", val, entry.who, entry.when, entry.note or "")
		entryPanels[#entryPanels+1] = gui.Panel{
			style = {
				flow = 'horizontal',
				width = 'auto',
				height = 'auto',
				margin = 2,
				color = entry.color,
				fontSize = 16,
			},
			children = {
				gui.Label{
					text = description,
				},
			}
		}
	end

	local resultPanel = nil

	resultPanel = gui.Panel{
		bgimage = 'panels/square.png',
		selfStyle = {
			width = 'auto',
			height = 'auto',
			bgcolor = '#000000dd',
			pad = 4,
			flow = 'vertical',
		},
		styles = {
			{
				selectors = {"create"},
				transitionTime = 0.2,
				opacity = 0,
			},
		},
		children = entryPanels,
	}

	return resultPanel
end

function gui.FlattenContextMenuItems(items, result)
	if result == nil then
		result = {}
	end

	for _,item in ipairs(items) do
		if item.submenu then
			gui.FlattenContextMenuItems(item.submenu, result)
		else
			result[#result+1] = item
		end
	end

	return result
end

--- @class ContextMenuEntry
--- @field text string
--- @field click fun():nil
--- @field group nil|string When consecutive elements have a different group, a divider is drawn between them.
--- @field check nil|boolean
--- @field disabled nil|boolean
--- @field submenu nil|(ContextMenuEntry[])
--- @field bind nil|string The keybind the entry has
--- @field hasNewContent nil|boolean If true, this has new content and will be marked as such.




--- Create a single context menu item.
--- @param args ContextMenuEntry
--- @param params {click: function} "click" indicates an additional click that is global to the context menu.
function gui.ContextMenuItem(args, params)
	local submenu = nil
	local arrow = nil

	if args.submenu then
		submenu = gui.ContextMenu({submenu = true, floating = true, entries = args.submenu, click = params.click})
		if submenu ~= nil then
			submenu.constrainToScreen = true
			dmhub.Schedule(0.05, function()
				if submenu ~= nil and submenu.valid and submenu.parent ~= nil then
					submenu.x = submenu.parent.renderedWidth
				end
			end)
		end
		arrow = gui.Panel{
			classes = {'arrow'},
			bgimage = 'panels/triangle.png',
			selfStyle = { rotate = 90 },
		}
	end

	local rightClickMenu = nil

	local labelClass = nil
	local checkPanel = nil
	local iconPanel = nil
	if args.check ~= nil then
		labelClass = "have-check"

		checkPanel = gui.Panel{
			classes = {"context-menu-check", cond(args.check, "checked"), cond(args.check == "partial", "partial")},
			halign = "left",
			bgimage = "icons/icon_common/icon_common_29.png",
			width = 16,
			height = 16,
			valign = "center",
			hmargin = 0,
		}
	end

	if args.icon ~= nil then
		labelClass = "have-icon"
		iconPanel = gui.Panel{
			classes = {"context-menu-icon", cond(args.check == false, "context-menu-icon-unchecked")},
			bgimage = args.icon,
		}
	end

	local bindLabel = nil
	if args.bind ~= nil then
		bindLabel = gui.Label{
			classes = {"context-menu-bind", cond(args.disabled, "disabled")},
			text = args.bind,
		}
	end

	local newContentMarker = nil
	if args.hasNewContent ~= nil and args.hasNewContent() then
		newContentMarker = gui.NewContentAlert{}
	end

	return gui.Panel{
		id = args.id,
		bgimage = 'panels/square.png',
		classes = {'context-menu-item', cond(args.hidden, "collapsed")},
		swallowPress = true,

		events = {
			press = function(element)
				if args.click ~= nil and not args.disabled then
					args.click(args)

					if params.click ~= nil then
						--this is a global click for all items in the menu.
						params.click()
					end
				end
			end,
			rightClick = function(element)
				if args.rightClickMenu ~= nil and not args.disabled then
					if rightClickMenu ~= nil then
						rightClickMenu:DestroySelf()
						rightClickMenu = nil
					else
						rightClickMenu = gui.ContextMenu{ halign = "left", floating = true, entries = args.rightClickMenu, click = params.click }
						element:AddChild(rightClickMenu)
					end
				end
			end,

			hover = function(element)
				if not args.disabled then
					element.parent:FireEvent('hoverChild')
					element:SetClass('hover-linger', true)

					if args.tooltip ~= nil then
						gui.Tooltip(args.tooltip)(element)
					end
				end
			end,
		},

		children = {
			checkPanel,
			iconPanel,
			gui.Label{
				classes = {"context-menu-label", labelClass, cond(args.disabled, "disabled")},
				text = args.text,
				newContentMarker,
			},
			bindLabel,
			arrow,
			submenu,
		},
	}
end

--- Create a context menu. This is suitable to be set as a panel's @Panel.popup field.
--- @param args {entries: ContextMenuEntry[], click: function, halign: nil|"left"|"center"|"right", valign = nil|"left"|"center"|"right", submenu: nil|boolean}
--- @return Panel|nil
function gui.ContextMenu(args)
	local items = {}
	for i,entry in ipairs(args.entries) do

		if entry and not entry.hidden then
			items[#items+1] = gui.ContextMenuItem(entry, {click = args.click})

			--add a divider if we are going to a different group
			if i > 1 and i < #args.entries and args.entries[i+1] ~= nil and entry.group ~= args.entries[i+1].group then
				items[#items+1] = gui.Panel{
					classes = {'context-menu-div'},
				}
			end
		end
	end

	if #items == 0 then
		return nil
	end

	local halign = args.halign

	if args.submenu then
		halign = "left"
	end

	return gui.Panel{
		x = args.x or 0,
		floating = args.floating or false,
		classes = {'context-menu', cond(args.submenu, 'context-menu-sub', 'context-menu-parent')},
		vscroll = cond(args.submenu, true),
		halign = halign,
        valign = args.valign,
		styles = {
			{
				selectors = {'context-menu'},
				bgimage = 'panels/square.png',
				bgcolor = "white",
				gradient = Styles.dialogGradient,
				borderColor = Styles.textColor,
				border = 2,
				pad = 8,

				margin = 4,
				width = "auto",
				height = 'auto',
				flow = 'vertical',
				halign = 'right',
				valign = 'bottom',
			},
			{
				selectors = {'context-menu-sub'},
				valign = 'top',
				hidden = 1,
				maxHeight = 400,
			},
			{
				selectors = {'context-menu-sub','parent:hover-linger'},
				hidden = 0,
			},

			{
				selectors = {'context-menu-label'},
				color = Styles.textColor,
				fontFace = "dubai",
				fontSize = 18,
				textAlignment = 'left',
				hmargin = 2,
				height = "auto",
				width = "auto",
			},
			{
				selectors = {'context-menu-label', 'disabled'},
				color = "#777777",
			},
			{
				selectors = {'context-menu-label', 'have-check'},
				--hmargin = 20,
			},
			{
				selectors = {'context-menu-label', 'have-icon'},
				--hmargin = 20,
			},
			{
				selectors = {'context-menu-label', 'parent:hover'},
				color = "black",
			},
			{
				selectors = {'context-menu-bind'},
				color = Styles.textColor,
				fontFace = "dubai",
				fontSize = 16,
				textAlignment = 'right',
				hmargin = 2,
				height = "auto",
				width = "auto",
				halign = "right",
			},
			{
				selectors = {'context-menu-bind', 'disabled'},
				color = "#777777",
			},
			{
				selectors = {'context-menu-bind', 'parent:hover'},
				color = "black",
			},
			{
				selectors = {'context-menu-icon'},
				width = 16,
				height = 16,
				valign = "center",
				halign = "left",
				hmargin = 2,
				bgcolor = Styles.textColor,
			},

			{
				selectors = {'context-menu-icon-unchecked'},
				opacity = 0.1,
			},

			{
				selectors = {'context-menu-check'},
				bgcolor = Styles.textColor,
				opacity = 0.1,
			},
			{
				selectors = {'context-menu-check', 'checked'},
				opacity = 1,
			},
			{
				selectors = {'context-menu-check', 'partial'},
				opacity = 0.4,
			},
			{
				selectors = {'context-menu-check', '~checked', '~partial', 'parent:hover'},
				opacity = 0.4,
			},

			{
				selectors = {'context-menu-icon', 'parent:hover'},
				bgcolor = "black",
				opacity = 1,
			},

			{
				selectors = {'context-menu-check', 'parent:hover'},
				bgcolor = "black",
			},

			{
				selectors = {'context-menu-item'},
				bgimage = 'panels/context-menu-background.png',
				height = 'auto',
				minWidth = args.width or 200,
				width = "auto",
				halign = 'left',
				valign = 'top',
				borderWidth = 0,
				borderColor = 'white',
				bgcolor = '#ffffff00',
				color = 'white',
				vmargin = 0,
				hmargin = 0,
				pad = 2,
				flow = 'horizontal',
			},
			{
				selectors = {'context-menu-item','hover'},
				bgimage = 'panels/square.png',
				bgcolor = 'white',
				color = "black",
			},
			{
				selectors = {'context-menu-item','press'},
				bgcolor = '#aaaaaa66',
			},
			{
				selectors = {'context-menu-div'},
				bgimage = "panels/square.png",
				hmargin = 0,
				width = args.width or 200,
				halign = "center",
				height = 1,
				opacity = 1,
				bgcolor = Styles.textColor,
			},
			{
				selectors = {'arrow'},
				halign = 'right',
				valign = 'center',
				width = 10,
				height = 10,
				bgcolor = Styles.textColor,
			},
		},

		events = {
			hoverChild = function(element)
				for i,child in ipairs(element.children) do
					child:SetClass('hover-linger', false)
				end
			end,
		},

		children = items,
	}
end

--- Creates a progress bar. Set the 'value' field to set the percentage complete.
--- @param args PanelArgs
--- @return Panel
function gui.ProgressBar(args)
	args = DeepCopy(args)

	local value = args.value or 0
	args.value = nil

	local fillPanel = gui.Panel{
		bgimage = "panels/progressbar/endcap.png",
		bgcolor = "white",
		flow = "horizontal",
		halign = "left",
		height = "100%",
		bgslice = {x1 = 0, x2 = 128, y1 = 0, y2 = 0},
		border = {x1 = 0, x2 = 32, y1 = 0, y2 = 0},

		refresh = function(element)
			element.selfStyle.width = string.format("%f%%", value*100)
		end,
	}

	local innerPanel = gui.Panel{
		width = "100%-60",
		height = "100%-16",
		halign = "center",
		valign = "center",
		flow = "none",

		gui.Panel{
			height = "100%",
			width = "100%",
			halign = "left",
			flow = "horizontal",
			fillPanel,
		},

		gui.Label{
			fontFace = "SupernaturalKnight",
			halign = "center",
			valign = "center",
			width = "30%",
			height = "auto",
			textAlignment = "center",
			color = "#ffedcf",
			fontSize = args.fontSize or 30,
			text = "TEST",

			refresh = function(element)
				element.text = string.format("%d%%", math.floor(value*100))
			end,
		},
	}

	local params = {
		flow = "none",
		idprefix = "ProgressBar",

		create = function(element)
			element:FireEventTree("refresh")
		end,

		GetValue = function() return value end,
		SetValue = function(element, val, fireevent)
			value = clamp(val, 0, 1)
			element:FireEventTree("refresh")
		end,

		progress = function(element, val)
			element.value = val
		end,

		innerPanel,
		gui.Panel{
			classes = {"progressBarFrame"},
			bgimage = "panels/progressbar/frame.png",
			bgcolor = "white",
			width = "100%",
			height = "100%",
			bgslice = {x1 = 200, x2 = 200, y1 = 32, y2 = 32},
			border = {x1 = 50, x2 = 50, y1 = 8, y2 = 8},
		},
	}

	for k,v in pairs(args) do
		params[k] = v
	end

	return gui.Panel(params)
end

--- @return Panel
local MakeSpectrumSamplePanel = function()
	return gui.Panel{
		bgimage = "panels/square.png",
		bgcolor = "white",
		opacity = 0.05,
		valign = "center",
		halign = "center",
		width = 3,
		height = 4,
		cornerRadius = 1.5,
	}
end

--- Creates a panel for picking an audio asset. Use the 'value' field to query the assetid of the audio selected.
--- @param args PanelArgs
--- @return Panel
function gui.AudioEditor(args)
	local resultPanel

	local spectrumPanel = nil

	args = DeepCopy(args)

	local value = args.value or nil
	args.value = nil

	local autoplayId = nil
	local autoplayInstance = nil
	local autoplay = args.autoplay
	args.autoplay = nil

	local autoplayVolume = args.autoplayvolume
	if autoplayVolume == nil then
		autoplayVolume = 1
	end

	local StopAutoplay = function()
		if autoplayInstance ~= nil then
			autoplayInstance:Stop()
			autoplayInstance = nil
		end

		autoplayId = nil
		spectrumPanel:FireEvent("stop")
		resultPanel:SetClassTree("playing", false)
	end

	local UpdateAutoplay = function()
		if resultPanel.valid and resultPanel.enabled and autoplayId == value then
			return
		end

		StopAutoplay()

		if resultPanel.valid and resultPanel.enabled and autoplay and value ~= nil and value ~= "" then
			autoplayId = value

			local asset = assets.audioTable[value]
			if asset ~= nil then
				autoplayInstance = asset:Play()
				autoplayInstance.volume = autoplayVolume
                autoplayInstance.solo = true
				spectrumPanel:FireEvent("play")
				resultPanel:SetClassTree("playing", true)
			end
		end
	end

	local musicIcon = gui.Panel{
		width = "75%",
		height = "75%",
		bgimage = "icons/icon_media/icon_media_5.png",
		halign = "center",
		valign = "center",
		styles = {
			{
				bgcolor = Styles.textColor,
			},
			{
				selectors = {"parent:hover"},
				bgcolor = "black",
				transitionTime = 0.2,
			},
		},
	}

	spectrumPanel = gui.Panel{
		classes = {"collapsed"},
		width = "80%",
		height = "40%",
		halign = "center",
		valign = "center",
		flow = "horizontal",

		data = {
			init = false,
			samples = {},
		},

		think = function()
			if spectrumPanel:HasClass("collapsed") then
				return
			end

			local samples = dmhub.GetAudioSpectrum()
			for i,s in ipairs(spectrumPanel.data.samples) do
				local y = 1 - 1/math.pow(100*i, samples[i])
				s.selfStyle.height = 4 + y*60
			end

		end,

		play = function()
			spectrumPanel:SetClass("collapsed", false)
			spectrumPanel.thinkTime = 0.01			
			musicIcon:SetClass("collapsed", true)

			if spectrumPanel.data.init == false then
				spectrumPanel.data.init = true
				local children = {}
				for i=1,16 do
					local p = MakeSpectrumSamplePanel()
					children[#children+1] = p
					spectrumPanel.data.samples[#spectrumPanel.data.samples+1] = p
				end

				spectrumPanel.children = children
			end
		end,

		stop = function()
			spectrumPanel.thinkTime = 10
			spectrumPanel:SetClass("collapsed", true)
			musicIcon:SetClass("collapsed", false)
		end,


	}




	local width = args.width or 128
	local height = args.height or 128
	local scaling = width/128

	local options = {
		classes = {"audioPanel"},
		cornerRadius = width/2,
		flow = "none",

		enable = function(element)
			UpdateAutoplay()
		end,

		disable = function(element)
			UpdateAutoplay()
		end,

		volume = function(element, vol)
			if autoplayInstance ~= nil then
				autoplayInstance.volume = vol
			end

			autoplayVolume = vol
		end,

		styles = {
			{
				selectors = {"audioPanel"},
				borderWidth = 2,
				borderColor = Styles.textColor,
				bgimage = "panels/square.png",
				bgcolor = "black",
			},
			{
				selectors = {"audioPanel", "hover"},
				bgcolor = Styles.textColor,
				transitionTime = 0.2,
				brightness = 1.2,
			},
		},

		musicIcon,
		spectrumPanel,

		gui.Label{
			width = "90%",
			height = "90%",
			halign = "center",
			valign = "center",
			textWrap = true,
			textAlignment = "center",
			text = "Sound",
			fontSize = 16 * scaling,

			styles = {
				{
					color = Styles.textColor,
				},
				{
					selectors = {"parent:hover"},
					color = "black",
					transitionTime = 0.2,
				}
			},
			create = function(element)
				if value == nil or assets.audioTable[value] == nil then
					element.text = "(No Sound)"
				else
					element.text = assets.audioTable[value].description
				end
			end,
			changeValue = function(element)
				element:FireEvent("create")
			end
		},

		press = function(element)

			local popupPanel = nil

			local CreateEntry = function()

				local audioAsset = nil
				local playingEvent = nil
				local label = gui.Label{
					fontSize = 16,
					color = "white",
					halign = "left",
					textAlignment = "left",
					width = "auto",
					height = "auto",
					interactable = false,
				}

				local playButton
				playButton = gui.IconButton{
					icon = "ui-icons/AudioPlayButton.png",
					style = {
						width = 32,
						height = 32,
						valign = "center",
						halign = "right",
						vmargin = 4,
					},

					think = function(element)
						if playingEvent == nil then
							element.thinkTime = nil
							return
						end

						if not playingEvent.playing then
							playingEvent = nil
							playButton.data.SetIcon("ui-icons/AudioPlayButton.png")
							element.thinkTime = nil
						end
					end,

					click = function(element)
						if playingEvent ~= nil then
							playingEvent:Stop()
							playingEvent = nil
							playButton.data.SetIcon("ui-icons/AudioPlayButton.png")
							element.thinkTime = nil
						elseif audioAsset ~= nil then
							playingEvent = audioAsset:Play()
							playButton.data.SetIcon("panels/square.png")
							element.thinkTime = 0.1
						end
					end,

					destroy = function(element)
						if playingEvent ~= nil then
							playingEvent:Stop()
							playingEvent = nil
						end
					end,
				}

				local entryPanel = gui.Panel{
					classes = {"audioEntry"},
					flow = "horizontal",
					halign = "center",
					width = "90%",
					height = 40,
					cornerRadius = 8,
					bgimage = "panels/square.png",
					click = function(element)
						if audioAsset ~= nil then
							value = audioAsset.id
						else
							value = nil
						end

						resultPanel:FireEvent("change", value)
						resultPanel:FireEventTree("changeValue", value)
						resultPanel.popup = nil
					end,

					styles = {
						{
							selectors = {"audioEntry"},
							bgcolor = "black",
						},
						{
							selectors = {"audioEntry", "hover"},
							bgcolor = "#770000",
						},
					},

					data = {
						SetId = function(id)
							if id == "none" then
								playButton:SetClass("hidden", true)
								label.text = "(No Sound)"
							else
								audioAsset = assets.audioTable[id]
								label.text = audioAsset.description
								playButton:SetClass("hidden", false)
							end
						end,
					},

					label,

					playButton,

				}

				return entryPanel
			end

			local soundIds = {}
			local sounds = {}

			local rows = 10
			local npage = 1

			local GetNumPages = function()
				local numPages = math.ceil(#soundIds / rows)
				if numPages < 1 then
					numPages = 1
				end

				return numPages
			end

			while #sounds < rows do
				sounds[#sounds+1] = CreateEntry()
			end

			local soundsGrid = gui.Panel{
				flow = 'horizontal',
				wrap = true,
				margin = 0,
				pad = 0,
				width = 400,
				height = rows*40,

				halign = 'center',

				children = sounds,

				events = {
					refreshSearch = function()
						for i,sound in ipairs(sounds) do
							local searchIndex = (npage-1)*rows + i
							local soundId = soundIds[searchIndex]
							if soundId == nil then
								sound:SetClass('hidden', true)
							else
								sound.data.SetId(soundId)
								sound:SetClass('hidden', false)
							end
						end
					end
				}
			}

			local pagingPanel = gui.Panel{
				id = 'paging-panel',
				styles = {
					{
						width = '100%',
						height = 32,
						flow = 'horizontal',
					},
					{
						selectors = {'hover', 'paging-arrow'},
						brightness = 2,
					},
					{
						selectors = {'press', 'paging-arrow'},
						brightness = 0.7,
					},
				},

				children = {
					gui.Panel{
						bgimage = 'panels/InventoryArrow.png',
						className = 'paging-arrow',
						style = {
							height = '100%',
							width = '50% height',
							halign = 'left',
							hmargin = 40,
						},

						events = {
							refreshSearch = function(element)
								element:SetClass('hidden', npage == 1)
							end,

							click = function(element)
								npage = npage - 1
								if npage < 1 then
									npage = 1
								end
								popupPanel:FireEventTree('refreshSearch')
							end,
						},

					},

					gui.Panel{
						style = {
							flow = 'horizontal',
							width = 'auto',
							height = 'auto',
							halign = 'center',
						},

						gui.Label{
							style = {
								fontSize = '35%',
								color = 'white',
								width = 'auto',
								height = 'auto',
								halign = 'center',
							},
							text = 'Page',
						},

						--padding.
						gui.Panel{
							style = {
								height = 1,
								width = 8,
							},
						},

						gui.Label{
							editable = true,
							style = {
								fontSize = '35%',
								color = 'white',
								width = 'auto',
								height = 'auto',
								halign = 'center',
							},
							events = {
								refreshSearch = function(element)
									element.text = string.format('%d', math.tointeger(npage))
								end,
								change = function(element)
									local newPage = tonumber(element.text)
									if newPage == nil or newPage < 1 or newPage > GetNumPages() then
										newPage = npage
									end

									npage = newPage
									popupPanel:FireEventTree('refreshSearch')

								end,
							}
						},

						gui.Label{
							style = {
								fontSize = '35%',
								color = 'white',
								width = 'auto',
								height = 'auto',
								halign = 'center',
							},
							events = {
								refreshSearch = function(element)
									element.text = string.format('/%d', math.tointeger(GetNumPages()))
								end,
							}
						},

					},

					gui.Panel{
						bgimage = 'panels/InventoryArrow.png',
						className = 'paging-arrow',
						style = {
							scale = {x = -1, y = 1},
							height = '100%',
							width = '50% height',
							halign = 'right',
							hmargin = 40,
						},

						events = {
							refreshSearch = function(element)
								element:SetClass('hidden', npage == GetNumPages())
							end,

							click = function(element)
								npage = npage + 1
								if npage > GetNumPages() then
									npage = GetNumPages()
								end
								popupPanel:FireEventTree('refreshSearch')
							end,
						},
					},

				},
			}

			local searchInput = gui.Input{
				placeholderText = 'Search for sounds...',
				hasFocus = true,
				style = {
					width = 200,
					height = 30,
					fontSize = '40%',
					bgcolor = 'black',
					hmargin = 8,
				},

				events = {
					change = function(element)
						soundIds = dmhub.SearchSounds(element.text)
						table.insert(soundIds, 1, "none")
						npage = 1
						popupPanel:FireEventTree('refreshSearch')
					end,
				},
			}

			local uploadButton = gui.PrettyButton{
				text = 'Upload Audio',
				width = "auto",
				height = "auto",
				width = 200,
				height = 44,
				fontSize = 20,
				hmargin = 12,
				vmargin = 12,
				halign = "left",
				valign = "bottom",
				events = {
					click = function(element)
					
						local uploadDialog = nil
						dmhub.OpenFileDialog{
							id = 'AudioAssets',
							extensions = {'ogg', 'mp3', 'wav', 'flac'},
							multiFiles = true,
							prompt = "Choose audio to load",
							open = function(path)
								local operation

								local assetid = assets:UploadAudioAsset{
									path = path,
									error = function(text)
										--clear the operation.
										if operation ~= nil then
											operation.progress = 1
											operation:Update()
										end

										gui.ModalMessage{
											title = 'Error creating audio',
											message = text,
										}
									end,
									upload = function(id)
										if operation ~= nil then
											operation.progress = 1
											operation:Update()
										end

										--set this asset as the chosen one.
										value = id
										if resultPanel ~= nil and resultPanel.valid then
											resultPanel:FireEvent("change", value)
											resultPanel:FireEventTree("changeValue", value)
											resultPanel.popup = nil
										end


									end,
									progress = function(percent)
										if operation ~= nil then
											operation.progress = percent
											operation:Update()
										end
									end,
								}

								if assetid ~= nil then
									operation = dmhub.CreateNetworkOperation()
									operation.description = "Uploading Audio..."
									operation.status = "Uploading..."
									operation.progress = 0.0
									operation:Update()
								end
							end,
						}
					end,
				},
			}
			
			popupPanel = gui.Panel{
				classes = {"framedPanel"},
				styles = {
					Styles.Default,
					Styles.Panel,
					{
						flow = 'vertical',
						halign = 'left',
						valign = 'center',
						width = 600,
						height = 820,
						borderWidth = 0,
						bgcolor = 'white',
					},
				},
				children = {
					searchInput,
					soundsGrid,
					pagingPanel,
					uploadButton,
				},
			}

			searchInput:FireEvent('change')

			resultPanel.popupPositioning = 'panel'
			resultPanel.popup = popupPanel

		end,


	}

	for k,p in pairs(args) do
		options[k] = p
	end

	resultPanel = gui.Panel(options)

	resultPanel.GetValue = function() return value end
	resultPanel.SetValue = function(element, val, fireevent)
		value = val
		if fireevent then
			resultPanel:FireEvent("change", val)
		end

		element:FireEventTree("create")
		UpdateAutoplay()
	end

	UpdateAutoplay()

	return resultPanel
	
end

--- given a token returns a panel with an image of the token.  Use the classes token-image and token-image-frame to customize.
--- @param tokenArg nil|CharacterToken
--- @param options nil|PanelArgs
--- @return Panel
function gui.CreateTokenImage(tokenArg, options)

	options = options or {}

	local popoutBorder = 0.14

	local token = tokenArg

	local bgimage = nil
	if token ~= nil then
		bgimage = token.portrait
	end

	local portraitPanel = gui.Panel{
		idprefix = "token-portrait",
		classes = 'token-image-portrait',
		interactable = false,

		bgimage = bgimage,

		imageLoaded = function(element)
			--now we have loaded the portrait for sure, make sure the rect is right.
			if token.popoutPortrait then
				element.selfStyle.imageRect = {x1 = popoutBorder, y1 = popoutBorder, x2 = 1 - popoutBorder, y2 = 1 - popoutBorder}
                element.selfStyle.scale = 1/token.popoutScale
			else
				element.selfStyle.imageRect = token.portraitRect
                element.selfStyle.scale = 1
			end
		end,

		token = function(element, tok)
			element.bgimage = tok.portrait

			if tok.popoutPortrait then
				element.bgimageTokenMask = nil
				element.selfStyle.imageRect = {x1 = popoutBorder, y1 = popoutBorder, x2 = 1 - popoutBorder, y2 = 1 - popoutBorder}
                element.selfStyle.scale = 1/token.popoutScale
			else
				element.bgimageTokenMask = tok.portraitFrame
				element.selfStyle.imageRect = tok.portraitRect
                element.selfStyle.scale = 1
			end
		end,
	}

	local framePanel = gui.Panel{
		idprefix = "token-frame",
		floating = true,
		classes = 'token-image-frame',
		bgcolor = 'white',
		interactable = options.interactable or false,

		token = function(element, tok)
			element.bgimage = tok.portraitFrame
			element.selfStyle.hueshift = tok.portraitFrameHueShift
		end,
	}

	
	local info = {
		idprefix = "token-image",
		classes = 'token-image',
		children = {portraitPanel, framePanel},
		token = function(element, tok)
			token = tok
			if tok.popoutPortrait then
				element.children = {framePanel, portraitPanel}
			else
				element.children = {portraitPanel, framePanel}
			end
		end,
	}

	if options ~= nil then
		for k,v in pairs(options) do
			info[k] = v
		end
	end

	local resultPanel = gui.Panel(info)

	if token ~= nil then
		resultPanel:FireEventTree("token", token)
	end
	return resultPanel
end

--- Given a monster token renders it as an image.
--- @param monster CharacterToken
--- @param options PanelOptions
--- @return Panel
function gui.CreateMonsterImage(monster, options)

	local width = options.width
	local height = options.height
	options.width = nil
	options.height = nil

	local result = {
		bgimageStreamed = monster.portrait,
		bgimageTokenMask = monster.portraitFrame,

		selfStyle = {
			imageRect = monster.portraitRect,
		},

		style = {
			bgcolor = 'white',
			halign = 'left',
			valign = 'center',
			width = width,
			height = height,
		},

		events = {
			refreshAssets = function(element)
				element.bgimageStreamed = monster.portrait
				element.bgimageTokenMask = monster.portraitFrame
				element.selfStyle.imageRect = monster.portraitRect
			end,
		},

		children = {
			gui.Panel({
				bgimage = monster.portraitFrame,
				selfStyle = {
					bgcolor = 'white',
					hueshift = monster.portraitFrameHueShift,
					width = width,
					height = height,
				}
			})
		},
	}

	for k,v in pairs(options) do
		result[k] = v
	end

	return gui.Panel(result)

end

local g_collapseArrowStyles = {
	{
		selectors = {"collapseArrow", "collapseSet"},
		scale = {x = 1, y = -1},
		transitionTime = 0.2,
	}
}

function gui.CombineFields(existingField, newField)
    if type(existingField) == "table" and type(newField) == "table" and #existingField > 0 and #newField > 0 then
        local resultField = {}

        for i,v in ipairs(existingField) do
            resultField[#resultField+1] = v
        end
        for i,v in ipairs(newField) do
            resultField[#resultField+1] = v
        end
        return resultField
    end

    return newField
end

--- An arrow that can be used to collapse an area below it.
--- @param options PanelArgs
--- @return Panel
function gui.CollapseArrow(options)
	local args = {
		classes = {"collapseArrow"},
		styles = g_collapseArrowStyles,
		height = 16,
		width = "200% height",
		bgimage = "panels/hud/down-arrow.png",
		bgcolor = "white",
	}

	for k,v in pairs(options) do
		args[k] = gui.CombineFields(args[k], v)
	end

	return gui.Panel(args)
end



local g_pagingArrowStyles = {
	gui.Style{
		selectors = {"paging-arrow", "hover"},
		brightness = 2,
	}
}

--- @class PagingArrowArgs:PanelArgs
--- @field facing nil|-1|1 Choose if the arrow faces left or right.

--- An arrow suitable for paging through different sections.
--- @param options PagingArrowArgs
--- @return Panel
function gui.PagingArrow(options)
	local facing = options.facing or 1
	options.facing = nil
	local args = {
		styles = g_pagingArrowStyles,
		scale = { x = -facing, y = 1 },
		height = "100%",
		width = "50% height",
		bgimage = "panels/InventoryArrow.png",
		bgcolor = "white",
		className = "paging-arrow",
		halign = cond(facing == 1, "right", "left"),
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Panel(args)
end

--- An input styled ready to search.
--- @param options InputArgs
--- @return Input
function gui.SearchInput(options)
	local ParseString = function(str)
		str = trim(string.lower(str))
		if string.len(str) == 1 then
			str = ""
		end

		return str
	end

	local args = {
		classes = {"searchInput"},
		placeholderText = "Search...",
		editlag = 0.25,

		edit = function(element)
			element:FireEvent("search",ParseString(element.text))
		end,
		change = function(element)
			element:FireEvent("search", ParseString(element.text))
		end,

		gui.Panel{
			bgimage = "icons/icon_tool/icon_tool_42.png",
			floating = true,
			vmargin = 0,
			halign = "right",
			valign = "top",
			height = "100%",
			width = "100% height",
            bgcolor = cond(dmhub.whiteLabel == "mcdm", "white", "black"),
		},
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Input(args)
end

--- An input styled to look fancy
--- @param options InputArgs
--- @return Input
function gui.FancyInput(options)
	local args = {
		bgimage = "panels/input/InputField_Background.png",
		bgcolor = "white",
		pad = 16,

		gui.Panel{
			halign = "left",
			valign = "center",
			bgimage = "panels/input/InputField_OrnamentInside.png",
			bgcolor = "white",
			height = "100%",
			width = "100% height",
		},

		gui.Panel{
			halign = "right",
			valign = "center",
			scale = {x = -1},
			bgimage = "panels/input/InputField_OrnamentInside.png",
			bgcolor = "white",
			height = "100%",
			width = "100% height",
		},

		gui.Panel{
			x = -64,
			halign = "left",
			valign = "center",
			bgimage = "panels/input/InputField_OrnamentOutside.png",
			bgcolor = "white",
			height = "140%",
			width = "60% height",
		},

		gui.Panel{
			x = 64,
			halign = "right",
			valign = "center",
			scale = {x = -1},
			bgimage = "panels/input/InputField_OrnamentOutside.png",
			bgcolor = "white",
			height = "140%",
			width = "60% height",
		},

		gui.Border{
			image = "panels/input/InputField_Border.png",
			width = 40,
			grow = 36,
		}
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Input(args)
end

gui.ImplementationStatusValues = {
	[0] = "Wont Implement",
	[1] = "Unimplemented",
	[2] = "Bronze",
	[3] = "Silver",
	[4] = "Gold",
}

gui.ImplementationStatus = {
    WontImplement = 0,
	Unimplemented = 1,
    Bronze = 2,
    Silver = 3,
    Gold = 4,
}

--- A panel for editing implementation status of a feature. Set value to status: 0 = won't implement, 1 = unimplemented, 2 = bronze, 3 = silver, 4 = gold.
--- @param options PanelArgs
--- @return Panel
function gui.ImplementationStatusPanel(options)
	local resultPanel

	local ClampValue = function(num)
		num = tonumber(num)
		if num == nil then
			num = 0
		end

		if num < 0 then
			num = 4
		end

		if num > 4 then
			num = 0
		end
		return num
	end

	local value = ClampValue(options.value)
	options.value = nil

	local types = gui.ImplementationStatusValues

	local textLabel = gui.Label{
		width = 110,
		height = 24,
		fontSize = 14,
		color = "white",
		text = types[value],
		textAlignment = "center",
		halign = "center",
	}


	resultPanel = {
		width = 148,
		height = 32,
		flow = "horizontal",

		GetValue = function(element)
			return value
		end,

		SetValue = function(element, val, firechange)
			local num = ClampValue(val)
			textLabel.text = types[num]
			value = num
			if firechange then
				element:FireEvent("change")
			end
		end,


		gui.Panel{
			bgimage = 'panels/InventoryArrow.png',
			bgcolor = "white",
			halign = "left",
			valign = "center",
			height = 24,
			width = "50% height",
			press = function(element)
				resultPanel.value = value-1
				resultPanel:FireEvent("change")
			end,
		},

		textLabel,

		gui.Panel{
			bgimage = 'panels/InventoryArrow.png',
			scale = {x = -1, y = 1},
			bgcolor = "white",
			halign = "right",
			valign = "center",
			height = 32,
			width = "50% height",
			press = function(element)
				resultPanel.value = value+1
				resultPanel:FireEvent("change")
			end,
		},
	}

	for k,v in pairs(options) do
		resultPanel[k] = v
	end

	resultPanel = gui.Panel(resultPanel)

	return resultPanel
end

local statusIconImplementationEvent = function(element, implementation)
	element:SetClass("wontimplement", implementation == 0)
	element:SetClass("unimplemented", implementation == 1)
	element:SetClass("bronze", implementation == 2)
	element:SetClass("silver", implementation == 3)
	element:SetClass("gold", implementation == 4)
end

--- @class ImplementationStatusIconArgs:PanelArgs
--- @field implementation 0|1|2|3|4

--- An icon for showing implementation status of a feature. Set value to status: 0 - won't implement, 1 - unimplemented, 2 - bronze, 3 - silver, 4 - gold.
--- @param args ImplementationStatusIconArgs
--- @return Panel
function gui.ImplementationStatusIcon(args)
	local params = {
		classes = {"spellImplementationIcon"},
		implementation = statusIconImplementationEvent,
	}

	for k,v in pairs(args) do
		if k ~= "implementation" then
			params[k] = v
		end
	end

	local result = gui.Panel(params)

	result:FireEvent("implementation", args.implementation)

	return result
end



--- A curve editor panel
--- @param options PanelArgs
--- @return Panel
function gui.Curve(options)

	--the current value. Refers to a curve representing the current value.
	local currentValue = dmhub.DeepCopy(options.value)
	options.value = nil

	--normalizes and returns a table representing a point. Normalizes the range to our [0-1] values.
	local NormalizePoint = function(point)
		local x = point.x
		local y = (point.y - currentValue.displayRange.x) / (currentValue.displayRange.y - currentValue.displayRange.x)
		local z = point.z / (currentValue.displayRange.y - currentValue.displayRange.x)
		return {x = x, y = y, z = z}
	end

	--converts the point back to 'real' units from our normalized units
	local DenormalizePoint = function(point)
		local x = point.x
		local y = currentValue.displayRange.x + (currentValue.displayRange.y - currentValue.displayRange.x)*point.y
		local z = point.z * (currentValue.displayRange.y - currentValue.displayRange.x)
		return {x = x, y = y, z = z}
	end

	local points = {}

	--the id of the shape that created the path currently displayed
	local pathid = nil

	--the id of shapes made by editor info.
	local editorInfoIds = {}

	--the actual point that the tangent is for.
	local tangentPoint = nil

	--the id of the shape displaying the current tangent.
	local tangentid = nil

	--true if we are dragging the tangent.
	local draggingTangent = false

	--the index referencing the point we have *selected* (i.e. last clicked on)
	local selectedIndex = nil

	--the index referencing the point we are currently mouseover.
	local highlightedIndex = nil

	--if true, then highlightedIndex is being dragged
	local dragging = nil

	--the mouse position and original position of the start of the drag.
	local dragAnchor = nil
	local dragStartPos = nil

	local CloseToTangent = function(point)
		if tangentid == nil then
			return false
		end

		if tangentPoint.z < -1 or tangentPoint.z > 1 then
			local g = 1/tangentPoint.z
			local dy = point.y - tangentPoint.y
			local x = tangentPoint.x + g*dy
			if math.abs(x - point.x) < 0.01 then
				return true
			end
		else
			local dx = point.x - tangentPoint.x
			local y = tangentPoint.y + tangentPoint.z*dx
			if math.abs(y - point.y) < 0.01 then
				return true
			end
		end

		return false
	end

	local RefreshTangent = function(element)
		if tangentid ~= nil then
			element.shapes:Remove(tangentid)
		end

		if selectedIndex ~= nil then
			local point = points[selectedIndex]
			local gradient = point.z or 0
			local dx
			local dy

			if gradient < -1 or gradient > 1 then
				dy = 1
				dx = dy/gradient
			else
				dx = 1
				dy = dx*gradient
			end

			local a = { x = point.x - dx, y = point.y - dy }
			local b = { x = point.x + dx, y = point.y + dy }

			tangentPoint = point

			element.shapes.pencolor = "#ccccccff"
			tangentid = element.shapes:AddLine{
				a = a,
				b = b,
			}
		end

	end

	local args = {
		GetValue = function(element, val)
			currentValue.points = {}
			for i,p in ipairs(points) do
				currentValue.points[#currentValue.points+1] = DenormalizePoint(p)
			end
			return currentValue
		end,

		SetValue = function(element, val, firechange)
			currentValue = dmhub.DeepCopy(val)

			for i,p in ipairs(points) do
				element.shapes:Remove(p.discid)
			end

			points = {}
			for i,p in ipairs(val.points) do
				element:FireEvent("addPoint", NormalizePoint(p))
			end

			element.data.points = points

			selectedIndex = nil
			highlightedIndex = nil
			dragging = nil

			element:FireEvent("refresh")
	
			
			if firechange then
				element:FireEvent("change")
			end
		end,

		data = {
			points = points,
		},

		updateEditorInfo = function(element, arg)
			for i,id in ipairs(editorInfoIds) do
				element.shapes:Remove(id)
			end

			editorInfoIds = {}

			element.shapes:PushStyle()
			element.shapes.pencolor = "red"
			element.shapes.thickness = 2
			editorInfoIds[#editorInfoIds+1] = element.shapes:AddLine{ a = { x = arg.x, y = 0 }, b = { x = arg.x, y = 1 } }

			local y = (arg.y - currentValue.displayRange.x) / (currentValue.displayRange.y - currentValue.displayRange.x)
			editorInfoIds[#editorInfoIds+1] = element.shapes:AddLine{ a = { x = 0, y = y }, b = { x = 1, y = y } }
			element.shapes:PopStyle()

		end,

		thinkTime = 0.01,

		think = function(element)
			element:FireEvent("showEditorInfo")

			local point = element.mousePoint

			if dragging then
				if point == nil or (dragging == nil and (not element:HasClass("hover"))) then
					dragging = nil
					return
				end

				local highlightedPoint = points[highlightedIndex]

				if highlightedIndex ~= 1 and highlightedIndex ~= #points then
					highlightedPoint.x = clamp(dragStartPos.x + (point.x - dragAnchor.x), 0, 1)
				end
				highlightedPoint.y = dragStartPos.y + (point.y - dragAnchor.y)

				--make sure the point we are dragging is still in the correct ordering.
				while highlightedIndex > 2 and points[highlightedIndex].x < points[highlightedIndex-1].x do
					points[highlightedIndex] = points[highlightedIndex-1]
					points[highlightedIndex-1] = highlightedPoint
					highlightedIndex = highlightedIndex-1
				end

				while highlightedIndex < #points-1 and points[highlightedIndex].x > points[highlightedIndex+1].x do
					points[highlightedIndex] = points[highlightedIndex+1]
					points[highlightedIndex+1] = highlightedPoint
					highlightedIndex = highlightedIndex+1
				end

				element.shapes:Remove(highlightedPoint.discid)
				highlightedPoint.discid = element.shapes:AddDisc{ point = highlightedPoint, radius = 0.02 }
				element.shapes:SetColor(highlightedPoint.discid, 'yellow')

				element:FireEvent("refresh")
				element:FireEvent("change")
				

				return
			end

			if draggingTangent then
				if point == nil or not element:HasClass("hover") then
					draggingTangent = false
					element:FireEvent("confirm")
					return
				end

				local dx = point.x - tangentPoint.x
				local dy = point.y - tangentPoint.y

				if dx == 0 then
					dx = 0.0001
				end

				local g = dy/dx

				tangentPoint.z = g
				element:FireEvent("refresh")
				element:FireEvent("change")

				return
			end

			if highlightedIndex ~= nil then
				element.shapes:SetColor(points[highlightedIndex].discid, 'red')
				highlightedIndex = nil
			end

			local threshold = 0.025*0.025
			local closestPoint = nil
			if point == nil or not element:HasClass("hover") then
				return
			end

			for i,p in ipairs(points) do
				local xdelta = p.x - point.x
				local ydelta = p.y - point.y
				local distSqr = xdelta*xdelta + ydelta*ydelta
				if distSqr < threshold and p.discid ~= nil then
					threshold = distSqr
					closestPoint = i
				end
			end

			if closestPoint ~= nil then
				highlightedIndex = closestPoint
				element.shapes:SetColor(points[highlightedIndex].discid, 'yellow')
			end

			if tangentid ~= nil then
				element.shapes:SetColor(tangentid, '#ccccccff')
			end
			if closestPoint == nil and tangentid ~= nil then
				--see if we can edit the tangent.
				if CloseToTangent(element.mousePoint) then
					element.shapes:SetColor(tangentid, 'yellow')
				end

			end
		end,

		refresh = function(element)
			if pathid then
				element.shapes:Remove(pathid)
			end

			local curve = element.shapes:GetCurvePoints(points, 100)
			local curvePath = {}
			for i,y in ipairs(curve) do
				curvePath[#curvePath+1] = { x = i/100, y = y }
			end

			element.shapes.pencolor = "blue"
			pathid = element.shapes:AddPath{ path = curvePath }

			RefreshTangent(element)
		end,

		rightClick = function(element)
			if highlightedIndex ~= nil and highlightedIndex ~= 1 and highlightedIndex ~= #points then
				element.shapes:Remove(points[highlightedIndex].discid)
				table.remove(points, highlightedIndex)

				if tangentid ~= nil then
					element.shapes:Remove(tangentid)
				end
				tangentid = nil
				dragging = nil
				tangentPoint = nil
				selectedIndex = nil
				highlightedIndex = nil
				element:FireEvent("refresh")
				element:FireEvent("change")
				element:FireEvent("confirm")
			end
		end,

		unpress = function(element)
			if draggingTangent or dragging then
				element:FireEvent("confirm")
			end
			draggingTangent = false
			dragging = nil
		end,

		press = function(element)
			element.hasFocus = true

			if highlightedIndex ~= nil then
				selectedIndex = highlightedIndex
				RefreshTangent(element)

				dragging = true
				dragAnchor = element.mousePoint
				dragStartPos = { x = points[highlightedIndex].x, y = points[highlightedIndex].y }
				return
			end

			if tangentid ~= nil then
				if CloseToTangent(element.mousePoint) then
					draggingTangent = true
					return
				end

				element.shapes:Remove(tangentid)
				tangentid = nil
				selectedIndex = nil
				return
			end

			local newPoint = { x = element.mousePoint.x, y = element.mousePoint.y, z = 0 }
			element:FireEvent("addPoint", newPoint)

			element:FireEvent("refresh")
			element:FireEvent("change")
			element:FireEvent("confirm")
		end,

		addPoint = function(element, newPoint)
			local index = -1
			for i,p in ipairs(points) do
				if index == -1 and p.x > newPoint.x then
					index = i
				end
			end

			if index == -1 then
				points[#points+1] = newPoint
			else
				table.insert(points, index, newPoint)
			end

			element.shapes.pencolor = "red"
			local discid = element.shapes:AddDisc{ point = newPoint, radius = 0.02 }
			newPoint.discid = discid
		end,
	}


	options.value = nil

	for k,op in pairs(options) do
		args[k] = op
	end

	local panel = gui.Panel(args)

	local shapes = panel.shapes

	shapes.thickness = 1
	for i=0,10 do
		local r = i/10
		if i == 0 or i == 10 then
			shapes.pencolor = "white"
		else
			shapes.pencolor = "#999999ff"
		end
		shapes:AddLine{ a = { x = r, y = 0 }, b = { x = r, y = 1 } }
	end
	for i=0,10 do
		local r = i/10
		if i == 0 or i == 10 then
			shapes.pencolor = "white"
		else
			shapes.pencolor = "#999999ff"
		end
		shapes:AddLine{ a = { x = 0, y = r }, b = { x = 1, y = r } }
	end

	shapes.pencolor = "red"
	shapes.thickness = 5

	
	--convert input format to tables.
	for i,p in ipairs(currentValue.points) do
		panel:FireEvent("addPoint", NormalizePoint(p))
	end
	panel:FireEvent("refresh")

	return panel
end


--- A panel suitable for maximizing a dockable panel.
--- @return Panel
function gui.DockablePanelMaximizeButton()
	return gui.Panel{
		bgimage = "panels/hud/down-arrow.png",
		width = 256/8,
		height = 128/8,
		bgcolor = "white",
		halign = "center",
		valign = "top",
		vmargin = 4,
		styles = {
			{
				selectors = {"hover"},
				brightness = 1.5,
			},
			{
				selectors = {"maximized"},
				scale = {x = 1, y = -1},
			},
		},

		minimize = function(element)
			element:SetClass("maximized", false)
		end,

		maximize = function(element)
			element:SetClass("maximized", true)
		end,

		press = function(element)
			element:SetClass("maximized", not element:HasClass("maximized"))
			if element:HasClass("maximized") then
				element:FireEventOnParents("maximizeChild", element)
			else
				element:FireEventOnParents("minimizeChild", element)
			end
		end,
	}
end

--- A panel for alerting to new content.
--- @param args PanelArgs
--- @return Panel
function gui.NewContentAlert(args)
	args = args or {}
	local info = args.info
	args.info = nil

	local params = {
		halign = "right",
		valign = "center",
		floating = true,
		width = 6,
		height = 6,
		bgimage = "panels/square.png",
		bgcolor = Styles.textColor,
		cornerRadius = 3,
		x = 14,
		brightness = 1.5,
	}

	for k,v in pairs(args) do
		params[k] = v
	end


	return gui.Panel(params)
end

--- Will create a new content alert if the key within the given kind of content has new content. Otherwise returns nil.
--- @param contentType string
--- @param key string
--- @return nil|Panel
function gui.NewContentAlertConditional(contentType, key, args)
	if module.HasNovelContent(contentType, key) then
		return gui.NewContentAlert(args)
	end
	return nil
end

function gui.CurrencyEditor(options)

	options = options or {}

	local resultPanel
	local standard = options.standard or Currency.GetMainCurrencyStandard()
	options.standard = nil

	local currentValue = options.value or {}
	options.value = nil

	local currencyInputs = {}

	local function ReadInputs()
		local newValue = {}
		for currencyid,input in pairs(currencyInputs) do
			local amount = tonumber(input.text)
			if amount == nil then
				input.text = tostring(value[currencyid]) or "0"
				amount = value[currencyid]
			end

			if amount ~= 0 then
				newValue[currencyid] = amount
			end
		end

		currentValue = newValue
		resultPanel:FireEvent("change")
	end

	local currencyPanels = {}
	local currencyTable = dmhub.GetTableVisible(Currency.tableName) or {}
	for currencyid,currencyInfo in pairs(currencyTable) do
		if currencyInfo.standard == standard then
			local text = tostring(currentValue[currencyid] or 0)
			local input = gui.Input{
				characterLimit = 7,
				hmargin = 0,
				width = "auto",
				minWidth = 20,
				height = 20,
				fontSize = 16,
				text = text,
				hpad = 4,
				change = function(element)
					ReadInputs()
				end,
			}

			local icon = gui.Panel{
				width = 16,
				height = 16,
				hmargin = 0,
				valign = "center",
				bgimage = currencyInfo.iconid,
				bgcolor = "white",
			}

			local panel = gui.Panel{
				flow = "horizontal",
				width = "auto",
				height = "auto",
				halign = "center",
				hmargin = 2,
				data = {
					ord = -currencyInfo.value
				},

				icon,
				input,
			}

			currencyInputs[currencyid] = input
			currencyPanels[#currencyPanels+1] = panel
		end
	end

	table.sort(currencyPanels, function(a, b) return a.data.ord < b.data.ord end)

	if not options.hideNormalize then
		local normalizeButton = gui.Panel{
			bgimage = "ui-icons/icon-rotate.png",
			width = 16,
			height = 16,
			valign = "center",

			styles = {
				{
					bgcolor = Styles.textColor,
				},
				{
					selectors = {"hover"},
					bgcolor = "white",
				}
			},

			press = function(element)
				ReadInputs()
				local spend = Currency.CalculateSpend(nil, Currency.CalculatePriceInStandard(currentValue, standard), standard, true)
				if spend == nil then
					printf("Could not calculate spend")
					return
				end
				resultPanel.value = spend
			end,
		}

		currencyPanels[#currencyPanels+1] = normalizeButton
	end

	options.hideNormalize = nil

	local args = {
		width = "auto",
		height = "auto",
		children = currencyPanels,
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	resultPanel = gui.Panel(args)


	resultPanel.GetValue = function(element)
		return currentValue
	end
	resultPanel.SetValue = function(element, val, fireevent)

		currentValue = val

		for currencyid,input in pairs(currencyInputs) do
			input.text = tostring(currentValue[currencyid] or 0)
		end

		if fireevent then
			element:FireEvent("change")
		end
	end


	return resultPanel
end

--- @class DiceArgs:PanelArgs
--- @field faces nil|number

--- Creates a user dice panel showing dice styled in the current user's styling.
--- @param params DiceArgs
--- @return Panel
function gui.UserDice(params)
	local faces = params.faces or 20
	params.faces = nil

	local diceStyle = dmhub.GetDiceStyling(dmhub.GetSettingValue("diceequipped"), dmhub.GetSettingValue("playercolor"))

	local args = {
	
		classes = {"clickableIcon", "dice"},
		bgimage = string.format("ui-icons/d%d-filled.png", faces),
		bgcolor = diceStyle.bgcolor,
		saturation = 0.7,
		brightness = 0.4,

		gui.Panel{
			classes = {"dice"},
			interactable = false,
			width = "100%",
			height = "100%",
			bgimage = string.format("ui-icons/d%d.png", faces),
			bgcolor = diceStyle.trimcolor,
		}
	}

	for k,v in pairs(params) do
		args[k] = v
	end

	return gui.Panel(args)

end

local g_LoadingIndicatorStyles = {
	gui.Style{
		selectors = {"dot"},
		width = 8,
		height = 8,
		bgimage = "panels/square.png",
		bgcolor = Styles.textColor,
		cornerRadius = 4,
		valign = "center",
		halign = "center",
	},
	gui.Style{
		selectors = {"dot", "active"},
		transitionTime = 0.1,
		scale = 2,
	},
}

--- Creates a loading indicator panel.
--- @param options PanelArgs
--- @return Panel
function gui.LoadingIndicator(options)
	local children = {}
	for i=1,3 do
		children[#children+1] = gui.Panel{
			classes = {"dot"},
		}
	end
	local n = 1
	local args = {
		children = children,
		width = 64,
		height = 64,
		halign = "center",
		valign = "center",
		flow = "horizontal",
		styles = g_LoadingIndicatorStyles,
		thinkTime = 0.2,
		think = function(element)
			n = n+1
			for i,p in ipairs(children) do
				p:SetClass("active", (n%3) == (i%3))
			end
		end,
		children = children,
	}

	for k,v in pairs(options or {}) do
		args[k] = v
	end

	return gui.Panel(args)
end

--- @class VisibilityPanelArgs:PanelArgs
--- @field visible nil|boolean

--- A button suitable for toggling visibility. Check for the "visible" class being on this panel to check status.
--- @param options VisibilityPanelArgs
--- @return Panel
function gui.VisibilityPanel(options)
	local visible = options.visible
	options.visible = nil

	local args = {
		classes = {"visibilityPanel", cond(visible, "visible")},
		opacity = 0.6,
		width = 16,
		height = 16,
		bgcolor = "white",
		bgimage = cond(visible, "ui-icons/eye.png", "ui-icons/eye-closed.png"),
		visible = function(element, val)
			visible = val
			element.bgimage = cond(visible, "ui-icons/eye.png", "ui-icons/eye-closed.png")
			element:SetClass("visible", visible)
		end,
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Panel(args)
end

--- @class DividerArgs:PanelArgs
--- @field layout? nil|"line"|"dot"|"peak"|"v"|"vdot" To style the divider as an MCDM divider
local mcdmLayouts = { line = true, dot = true, peak = true, v = true, vdot = true }

--- @param options DividerArgs
--- @return Panel
--- Create a divider panel with layout aligning with MCDM book design
function gui.MCDMDivider(options)
	options = options or {}
	local layout = options.layout and #options.layout > 0 and options.layout:lower()

	options.layout = nil
	options.bgimage = nil

	local args = {
		tmargin = 4,
		bmargin = 0,
		height = 1,
		width = "80%",
		halign = "center",
		bgimage = "panels/square.png",
		bgcolor = Styles.textColor,
	}

	if layout and mcdmLayouts[layout] then

		for k,v in pairs(options) do
			args[k] = v
		end
		args.height = (args.height and args.height > 1) and args.height or 12
		args.tmargin = 0
		args.bgimage = nil
		args.gradient = nil
		args.flow = "horizontal"
		
		local lineWidth = "50%-" .. math.floor(args.height/2)
		local bgcolor = args.bgcolor or Styles.textColor
		local leftPanel = gui.Panel{
			height = args.height,
			width = lineWidth,
			halign = "right",
			valign = "center",
			pad = 0,
			margin = 0,
			bgimage = mod.images.line,
			bgcolor = bgcolor
		}
		local midPanel = gui.Panel{
			height = args.height,
			width = args.height,
			halign = "center",
			valign = "center",
			pad = 0,
			margin = 0,
			bgimage = mod.images[layout],
			bgcolor = bgcolor
		}
		local rightPanel = gui.Panel{
			height = args.height,
			width = lineWidth,
			halign = "left",
			valign = "center",
			pad = 0,
			margin = 0,
			bgimage = mod.images.line,
			bgcolor = bgcolor
		}

		args.children = {
			leftPanel, midPanel, rightPanel,
		}

		return gui.Panel(args)
	end

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Panel(args)

end

--- Create a divider panel.
--- @param options DividerArgs
--- @return Panel
function gui.Divider(options)
	options = options or {}

	local layout = options.layout and #options.layout > 0 and options.layout:lower()
	if layout and mcdmLayouts[layout] then
		return gui.MCDMDivider(options)
	end
	options.layout = nil

	local args = {
		tmargin = 4,
		bmargin = 0,
		height = 1,
		width = "80%",
		halign = "center",
		bgimage = "panels/square.png",
		bgcolor = Styles.textColor,
		gradient = Styles.horizontalGradient,
	}

	for k,v in pairs(options) do
		args[k] = v
	end

	return gui.Panel(args)
end

--should have Styles.TriggerStyles present to use this.
function gui.TriggerPanel(args)
    local width = args.width or 32
    local height = args.height or 32
    local type = args.type
    args.type = nil

    args.classes = args.classes or {}

    args.classes[#args.classes+1] = "triggeredActionPanel"

    local params = {
        bgimage = true,
        text = "!",
        width = width,
        height = height,
        cornerRadius = width/5,
        color = Styles.Triggers.textColor,
        fontSize = width,
    }

    for k,v in pairs(args) do
        params[k] = v
    end

    return gui.Label(params)
end