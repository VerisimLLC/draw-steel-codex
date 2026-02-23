local mod = dmhub.GetModLoading()

--themes are still very much a work in progress, so there isn't much to see here yet.

--CURRENTLY THIS IS DEFINED AS A DMHUB CORE TYPE. DON'T REDEFINE IT.
--RegisterGameType("Theme")

local themeStyles = {
	Styles.Form,
	{
		selectors = {"label"},
		height = "auto",
		width = "auto",
	},
	{
		selectors = {"formLabel"},
		valign = "center",
	},
	{
		selectors = {"formInput"},
		valign = "center",
	},
	{
		selectors = {"formPanel"},
		halign = "left",
		hmargin = 4,
	},
}

function Theme.CreateEditor()
	local theme
	local themeid
	local resultPanel

	local sectionPanels = {}

	resultPanel = gui.Panel{
		width = 1000,
		height = "90%",
		flow = "vertical",
		styles = themeStyles,
		classes = {"hidden"},
		vscroll = true,

		refreshAssets = function(element)
		end,

		--left panel
		gui.Panel{
			width = "40%",
			halign = "left",
			height = "auto",
			flow = "vertical",
			gui.Panel{
				classes = {"formPanel"},
				gui.Label{
					classes = {"formLabel"},
					text = "Name:",
				},
				gui.Input{
					classes = {"formInput"},
					refreshTheme = function(element, theme)
						element.text = theme.description
					end,
					change = function(element)
						theme.description = element.text
						theme:Upload()
					end,
				},
			},

			--all the sections
			gui.Panel{
				width = "100%",
				height = "auto",
				flow = "vertical",
				refreshTheme = function(element, theme)
					local newSectionPanels = {}
					local children = {}

					for i,sectionid in ipairs(theme.editorSections) do
						local panel = sectionPanels[sectionid] or Theme.CreateEditorSection(sectionid)
						children[#children+1] = panel
						newSectionPanels[sectionid] = panel
					end


					element.children = children
					sectionPanels = newSectionPanels
				end,
			},
		},

		data = {
			SetTheme = function(themeType, newThemeid)
				themeid = newThemeid
				local themeInfo = assets.themes[themeid]
				theme = themeInfo

				if themeInfo ~= nil then
					resultPanel:FireEventTree("refreshTheme", themeInfo)
					resultPanel:SetClass("hidden", false)
				else
					resultPanel:SetClass("hidden", true)
				end
			end
		}

	}

	return resultPanel
end

function Theme.CreateEditorSection(sectionid)
	local resultPanel

	local styles
	local stylePanels = {}

	resultPanel = gui.Panel{
		width = "100%",
		height = "auto",
		flow = "vertical",

		gui.Label{
			fontSize = 24,
			text = sectionid,
			halign = "left",
		},

		gui.Panel{
			width = "100%",
			height = "auto",
			flow = "vertical",
			refreshTheme = function(element, theme)
				local newStylePanels = {}
				styles = DeepCopy(theme.GetSection(sectionid))
				for i,style in ipairs(styles) do
					local stylePanel = stylePanels[i] or Theme.CreateStylePanel{
						change = function(element)
							theme.SetSection(sectionid, styles)
							theme:Upload()
						end,
					}

					stylePanel:FireEvent("refreshStyle", style)
					newStylePanels[i] = stylePanel
				end

				stylePanels = newStylePanels
				element.children = newStylePanels
			end,
		},
	}

	return resultPanel
end

function Theme.CreateStylePanel(params)
	local attributePanels = {}
	local resultPanel
	local args = {
		width = "100%",
		height = "auto",

		refreshStyle = function(element, style)
			local children = {}
			local newAttributePanels = {}

			for k,val in pairs(style) do
				local panel = attributePanels[k] or gui.Panel{
					classes = {"formPanel"},
					gui.Label{
						classes = {"formLabel"},
						text = k,
					},

					gui.Input{
						classes = {"formInput"},
						refreshValue = function(element, val)
							element.text = dmhub.ToJson(val)
						end,
						change = function(element)
							local newVal = dmhub.FromJson(element.text)
							if newVal.success then
								element.text = dmhub.ToJson(newVal.result)
								style[k] = newVal.result
								resultPanel:FireEvent("change")
							end
						end,
					},
				}

				panel:FireEventTree("refreshValue", val)
				newAttributePanels[k] = panel
				children[#children+1] = panel
			end

			attributePanels = newAttributePanels
			element.children = children
		end,
	}

	for k,p in pairs(params) do
		args[k] = p
	end

	resultPanel = gui.Panel(args)
	return resultPanel

end
