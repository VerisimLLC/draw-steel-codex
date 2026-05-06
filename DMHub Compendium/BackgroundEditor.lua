local mod = dmhub.GetModLoading()


local SetBackground = function(tableName, backgroundPanel, backgroundid)
	local backgroundTable = dmhub.GetTable(tableName) or {}
	local background = backgroundTable[backgroundid]
	local UploadBackground = function()
		dmhub.SetAndUploadTableItem(tableName, background)
	end

	local children = {}

	children[#children+1] = gui.Panel{
		flow = "vertical",
		width = 196,
		height = "auto",
		floating = true,
		halign = "right",
		valign = "top",
		gui.IconEditor{
		value = background.portraitid,
		library = "Avatar",
			width = "100%",
		height = "150% width",
		autosizeimage = true,
		allowPaste = true,
		borderWidth = 2,
		change = function(element)
			background.portraitid = element.value
			UploadBackground()
		end,
		},

		gui.Label{
			text = "1000x1500 image",
			width = "auto",
			height = "auto",
			halign = "center",
			fontSize = 12,
		}
	}


	--the name of the background.
	children[#children+1] = gui.Panel{
		classes = {'formPanel'},
		gui.Label{
			text = 'Name:',
			valign = 'center',
			minWidth = 240,
		},
		gui.Input{
			text = background.name,
			change = function(element)
				background.name = element.text
				UploadBackground()
			end,
		},
	}

	children[#children+1] = gui.Input{
		fontSize = 14,
		vmargin = 4,
		width = 600,
		minHeight = 30,
		height = 'auto',
		multiline = true,
		text = background.description,
		textAlignment = "topleft",
		placeholderText = "Enter background description...",
		change = function(element)
			background.description = element.text
		end,
	}

	--starting equipment editor.
	children[#children+1] = gui.Panel{
		width = "auto",
		height = "auto",
		flow = "vertical",
		gui.Panel{
			flow = "horizontal",
			width = "auto",
			height = 30,
			bgimage = "panels/square.png",
			bgcolor = "clear",

			press = function(element)
				local tri = element.children[1]
				tri:SetClass("expanded", not tri:HasClass("expanded"))

				local siblings = element.parent.children
				if #siblings == 1 then
					siblings[#siblings+1] = mod.shared.StartingEquipmentEditor{
						featureInfo = background,
						change = function(element)
							UploadBackground()
						end,
					}

					element.parent.children = siblings
				end

				siblings[2]:SetClass("collapsed", not tri:HasClass("expanded"))
			end,

			gui.Panel{
				classes = {"triangle"},
				halign = "left",
				valign = "center",
				styles = {
					{
						selectors = {"triangle"},
						rotate = 90,
						transitionTime = 0.2,
					},
					{
						selectors = {"triangle", "expanded"},
						rotate = 0,
						transitionTime = 0.2,
					},
				},
			},

			gui.Label{
				text = "Starting Equipment",
				fontSize = 20,
				hmargin = 4,
				width = "auto",
				height = "auto",
				valign = "center",
			}
		},
	}

	BackgroundCharacteristic.EmbedEditor(background, children, function()
		backgroundPanel:FireEvent("change")
		UploadBackground()
	end)

	children[#children+1] = background:GetClassLevel():CreateEditor(background, 0, {
		width = 800,
		change = function(element)
			backgroundPanel:FireEvent("change")
			UploadBackground()
		end,
	})
	backgroundPanel.children = children
end

function Background.CreateEditor()
	local backgroundPanel
	backgroundPanel = gui.Panel{
		data = {
			SetBackground = function(tableName, backgroundid)
				SetBackground(tableName, backgroundPanel, backgroundid)
			end,
		},
		vscroll = true,
		classes = 'class-panel',
		styles = {
			{
				classes = {'class-panel'},
				width = 1200,
				height = '90%',
				halign = 'left',
				flow = 'vertical',
				pad = 20,
			},
		},
	}

	return backgroundPanel
end

