local mod = dmhub.GetModLoading()

local function ResolveFunction(functionOrValue)
    if type(functionOrValue) == "function" then
        return functionOrValue()
    else
        return functionOrValue
    end
end

-- Open-state styling (dropdownBorder, dropdownMenuSub, dropdownOption, etc.)
-- now lives in DefaultStyles.lua's default theme. The popup inherits its
-- styles from the nearest ancestor of the trigger that has a `styles`
-- property set (falling back to ThemeEngine.GetStyles() if none does), so
-- the open-state subtree matches the trigger's cascade — including locked
-- overrides like ThemeEngine.GetStyles("default", "default") used by the
-- theme settings dialog. Same selectors are visible to gui.Multiselect's
-- internal dropdown, so both render identically.

--- @class DropdownOption
--- @field id string|true|false
--- @field text string
--- @field tooltip nil|string|fun():string Tooltip text to show when hovering over this option.

--- @class Dropdown:Panel
--- @field idChosen nil|true|false|string The id of the option currently chosen.
--- @field options DropdownOption[] The possible options to choose from
 

--- @class DropdownArgs:PanelArgs
--- @field idChosen nil|true|false|string The id of the option currently chosen.
--- @field textOverride nil|string The text to set on the dropdown, instead of showing the currently chosen option.
--- @field textDefault nil|string The text to display for the dropdown if there is no option currently chosen.
--- @field options DropdownOption[] The possible options to choose from
--- @field hasSearch nil|boolean If true, this dropdown will provide an input field to search it. Good to use on dropdowns with many options.
--- @field sort nil|boolean Sorts @see options before displaying.
--- @field centerPopup nil|boolean If true, the menu that displays from this dropdown will appear parented to the root of the panel hierarchy and in the center -- i.e. it should pop up in the middle of the screen rather than attached to the dropdown.


--- Create a Dropdown panel
--- @param args DropdownArgs
--- @return Dropdown
function gui.Dropdown(args)

    local debug = args.debug
    args.debug = nil


	local sort = args.sort
	args.sort = nil

	local textOverride = args.textOverride
	args.textOverride = nil

	local textDefault = args.textDefault or "(Invalid)"
	args.textDefault = nil

	local m_options = {}
	local m_idChosen = nil
 
	local hasSearch = args.hasSearch
	args.hasSearch = nil

    local m_centerPopup = args.centerPopup
    args.centerPopup = nil

    local m_searchFocus = nil
    local ClearSearchFocus = function()
        if m_searchFocus ~= nil and m_searchFocus.valid then
            m_searchFocus:SetClass("searchfocus", false)
        end

        m_searchFocus = nil
    end

    local SearchFocus = function(panel)
        ClearSearchFocus()
        panel:SetClass("searchfocus", true)
        m_searchFocus = panel
    end
 
	local dropdownParent = nil
 
	local menuHeight = args.menuHeight or args.dropdownHeight or 300
	args.menuHeight = nil
	args.dropdownHeight = nil

	local menuWidth = args.menuWidth
	args.menuWidth = nil
 
	local npopup = 0
 
	local m_idToIndex = {}

	local m_keybinds = nil

	local hasSubmenus = false
	for _,option in ipairs(args.options or {}) do
		if type(option) == "table" and option.submenu ~= nil then
			hasSubmenus = true
		end
	end
 
	local label = gui.Label{
		classes = {"dropdownLabel"},
		text = textOverride or textDefault,
        fontSize = args.fontSize,
		create = function(element)
			element:FireEvent("refreshDropdown")
		end,
		refreshDropdown = function(element)
			if textOverride == nil and m_idChosen ~= nil and m_idToIndex[m_idChosen] ~= nil then
				element.text = m_options[m_idToIndex[m_idChosen]].text
			else
				element.text = textOverride or textDefault
			end
		end,
	}

	local tri = gui.Panel{
		classes = {"dropdownTriangle"},
		bgimage = "panels/triangle.png",
		width = "160% height",
		height = "30%",
		valign = "center",
	}
 
	local arguments = {
		classes = {"dropdown"},
		bgimage = "panels/square.png",
		press = function(element)
			local parentPanel = element
			local selfDropdown = element

			if m_centerPopup then
				parentPanel = element.root
			end

			if parentPanel.popup ~= nil then
				parentPanel.popup = nil
				return
			end
 
			npopup = npopup + 1
			local curpopup = npopup

			local valign = "bottom"
			local distances = parentPanel.distancesToScreenEdge
			local showTop = distances.y1 < menuHeight
			if showTop then
				valign = "top"
			end

            if m_centerPopup then
                valign = "center"
                showTop = false
            end
 
			local children = {}

			if showTop then
				--padding
				children[#children+1] = gui.Panel{
					width = 1,
					height = 4,
				}
			end

			local sortedOptions = m_options

			if sort then
				sortedOptions = {}
				for _,option in ipairs(m_options) do
					sortedOptions[#sortedOptions+1] = option
				end

				table.sort(sortedOptions, function(a,b)
					if a.unsorted ~= b.unsorted then
						if a.unsorted then
							return true
						else
							return false
						end
					end

					return ResolveFunction(a.text) < ResolveFunction(b.text)
				end)
			end

			local CreateLabel = function(option)
                local tooltip = option.tooltip
				local text = ResolveFunction(option.text)
				if m_keybinds ~= nil then
					for _,keybind in ipairs(m_keybinds) do
						if keybind.id == option.id then
							text = text .. " (" .. keybind.defaultBind .. ")"
						end
					end
				end
				local classes = {"dropdownOption"}
				if option.classes ~= nil then
					for _,c in ipairs(option.classes) do
						classes[#classes+1] = c
					end
				end

                local panel = ResolveFunction(option.panel)
                if panel == nil then
                    local hover = nil
                    if tooltip ~= nil then
                        hover = function(element)
                            local tip = ResolveFunction(tooltip)
                            if type(tip) == "string" then
                                gui.Tooltip(tip)(element)
                            else
                                element.tooltip = tip
                            end
                        end
                    end
                    panel = gui.Label{
                        classes = classes,
                        fontSize = args.fontSize,
                        text = text,
                        hover = hover,
                    }
                end

                if panel.events == nil then
                    panel.events = {}
                end

                local baseHover = panel.events.hover
                panel.events.hover = function(element)
                    ClearSearchFocus()

                    if baseHover ~= nil then
                        baseHover(element)
                    end
                end

                panel.events.press = function(element)
					if element:HasClass("disabled") then
						return
					end

                    parentPanel.popup = nil
                    dropdownParent.idChosen = option.id
                    selfDropdown:FireEvent("change")
                end

                panel.events.search = function(element, text, info)
                    element:SetClass("collapsed", string.find(string.lower(element.text), text) == nil)
                    if element:HasClass("collapsed") == false and info ~= nil and info.panelsShown ~= nil then
                        info.panelsShown[#info.panelsShown+1] = element
                    end
                end

                return panel
			end

			for i,option in ipairs(sortedOptions) do
				if not ResolveFunction(option.hidden) then

					if option.submenu ~= nil then
						local submenuChildren = {}
						for _,subOption in ipairs(option.submenu) do
							submenuChildren[#submenuChildren+1] = CreateLabel(subOption)
						end

						children[#children+1] = gui.Label{
							classes = {"dropdownOption"},
							fontSize = args.fontSize,
							text = ResolveFunction(option.text),

							gui.Panel{
								classes = {"submenuArrow"},
								bgimage = 'panels/triangle.png',
								selfStyle = { rotate = 90 },
								rotate = 90,
								halign = 'right',
								valign = 'center',
								rmargin = 4,
								width = 8,
								height = 8,
							},

							gui.Panel{
								classes = {"dropdownMenuSub"},
								floating = true,
								children = submenuChildren,
								create = function(element)
									dmhub.Schedule(0.05, function()
										if element ~= nil and element.valid and element.parent ~= nil then
											element.x = element.parent.renderedWidth
										end
									end)
								end,
							},
						}
					else
						children[#children+1] = CreateLabel(option)
					end
				end
			end
 
			if (not showTop) and (not m_centerPopup) then
				--padding
				children[#children+1] = gui.Panel{
					width = 1,
					height = 4,
				}
			end
 
			local searchInput
			if hasSearch then
				searchInput = gui.Input{
					classes = {"searchInput"},
					-- color / bgcolor / borderColor / borderWidth come from the
					-- {searchInput} theme rule. fontSize bumped to 18 here for
					-- the dropdown variant; theme default is 16.
					fontSize = 14,
					floating = true,
					valign = cond(showTop, "bottom", "top"),
					x = 2,
					y = cond(showTop, 1, -1) * (parentPanel.renderedHeight-2),
					width = (parentPanel.renderedWidth - 18) * parentPanel.renderedScale.x,
					height = parentPanel.renderedHeight - 2,
					halign = "left",
					hasFocus = true,
					placeholderText = "Search...",
					edit = function(element)
                        ClearSearchFocus()
                        local searchInfo = {panelsShown = {}}
						element.parent:FireEventTree("search", string.lower(element.text), searchInfo)
                        if #searchInfo.panelsShown > 0 and #searchInfo.panelsShown < #m_options then
                            SearchFocus(searchInfo.panelsShown[1])
                        end
					end,
                    submit = function(element)
                        if m_searchFocus ~= nil and m_searchFocus.valid and (not m_searchFocus:HasClass("disabled")) then
                            m_searchFocus:FireEvent("press")
                        end
                    end,
                    destroy = function(element)
                        m_searchFocus = nil
                    end,
				}
			end
 
			local menu = gui.Panel{
				classes = {"dropdownMenu"},
				width = menuWidth or element.renderedWidth,
				height = "auto",
				valign = "center",
				maxHeight = cond(not hasSubmenus, menuHeight),
				flow = "vertical",
				vscroll = cond(hasSubmenus, false, true),
				children = children,
				destroy = function(element)
					if curpopup == npopup and selfDropdown.valid then
						selfDropdown:SetClass("search", false)
						selfDropdown:SetClass("expanded", false)
						selfDropdown:SetClass("expandedBottom", false)
						selfDropdown:SetClass("expandedTop", false)
					end
				end,
			}
 
			element:SetClass("search", hasSearch)
			element:SetClass("expanded", true)
            if m_centerPopup then
                element:SetClass("expandedTop", false)
                element:SetClass("expandedBottom", false)
            elseif showTop then
				element:SetClass("expandedTop", true)
				element:SetClass("expandedBottom", false)
			else
				element:SetClass("expandedTop", false)
				element:SetClass("expandedBottom", true)
			end
 
			local popup = gui.Panel{
				-- styles = InheritedStyles(parentPanel),
				width = "auto",
				height = menuHeight + cond(m_centerPopup, 16, 0),
				scale = parentPanel.renderedScale.x,
				valign = valign,
				halign = "center",
                gui.Panel{
                    classes = {"dropdownBorder", cond(menuWidth ~= nil, "detached")},
				    bgimage = "panels/square.png",
                    width = menuWidth or element.renderedWidth,
                    height = "auto",
                    valign = cond(m_centerPopup, "center", cond(showTop, "bottom", "top")),
                    maxHeight = cond(not hasSubmenus, menuHeight),
				    menu,
                },
				searchInput,
			}
 
            if m_centerPopup then
                popup:SetClassTree("vcenter", true)
            end

			if showTop then
				popup:SetClassTree("top", showTop)
			end
 
			parentPanel.popupPositioning = "panel"
            parentPanel.popupsInheritStyles = true
			parentPanel.popup = popup
		end,
 
		label,
		tri,

		GetOptions = function()
			return m_options
		end,

		SetOptions = function(op)
			local hasCopy = false
			m_options = op
			m_idToIndex = {}

			local keybinds = nil
 
			for i=1,#m_options do

				if type(m_options[i]) == "string" then
					if hasCopy == false then
						hasCopy = true
						m_options = shallow_copy_list(m_options)
					end

					m_options[i] = {
						id = m_options[i],
						text = m_options[i],
						keybind = m_options[i].keybind,
					}
				end
			
				if m_options[i].submenu == nil then
					m_idToIndex[m_options[i].id] = i
				end

				if m_options[i].keybind ~= nil then
					if keybinds == nil then
						keybinds = {}
					end

					keybinds[#keybinds+1] = {
						id = m_options[i].id,
						defaultBind = m_options[i].keybind,
					}
				end
			end

			if m_idChosen ~= nil then
				dropdownParent:FireEventTree("refreshDropdown")
			end

			dropdownParent.keybinds = keybinds
			m_keybinds = keybinds
		end,

		GetIDChosen = function()
			return m_idChosen
		end,

		SetIDChosen = function(val)
			m_idChosen = val

			if #m_options > 0 then
				dropdownParent:FireEventTree("refreshDropdown")
			end
		end,


		GetOptionChosen = function()
			return m_idChosen
		end,

		SetOptionChosen = function(val)
			m_idChosen = val
			dropdownParent:FireEventTree("refreshDropdown")
		end,

		GetValue = function()
			for i=1,#m_options do
				if m_options[i].submenu == nil and m_options[i].id == m_idChosen then
					return i-1
				end
			end

			return 0
		end,

		SetValue = function(i)
			if m_options[i+1] ~= nil then
				dropdownParent.idChosen = m_options[i+1].id
				dropdownParent:FireEventTree("refreshDropdown")
			end
		end,
	}

	local options = args.options
	args.options = nil
 
	local idChosen = args.idChosen
    
    if idChosen == nil then
        idChosen = args.optionChosen
    end

	args.idChosen = nil
	args.optionChosen = nil
 
	for k,v in pairs(args) do
		if k == "classes" then
            if type(v) == "string" then
                arguments.classes[#arguments.classes+1] = v

            else
                for _,a in ipairs(v) do
                    arguments.classes[#arguments.classes+1] = a
                end
            end
		else
			arguments[k] = v
		end
	end

	arguments.events = arguments.events or {}
	arguments.events.keybind = function(element, id)
		dropdownParent.idChosen = id
		dropdownParent:FireEvent("change")
	end
 
	dropdownParent = gui.Panel(arguments)

	if options ~= nil then
		dropdownParent.options = options
	end

	if idChosen ~= nil then
		dropdownParent.idChosen = idChosen
	end

	return dropdownParent
end