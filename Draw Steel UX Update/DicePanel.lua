local mod = dmhub.GetModLoading()

local function track(eventType, fields)
	if dmhub.GetSettingValue("telemetry_enabled") == false then
		return
	end
	fields.type = eventType
	fields.userid = dmhub.userid
	fields.gameid = dmhub.gameid
	fields.version = dmhub.version
	analytics.Event(fields)
end

local CreateDicePanel

DockablePanel.Register{
	name = "Dice",
	icon = "ui-icons/dsdice/djordice-d10.png",
	notitle = true,
	vscroll = false,
    dmonly = false,
	minHeight = 68,
	maxHeight = 68,
	content = function()
		track("panel_open", {
			panel = "Dice",
			dailyLimit = 30,
		})
		return CreateDicePanel()
	end,
}

local styles = {

	{
		classes = "dice",
		bgcolor = "white",
		width = 40,
		height = 40,
		valign = "center",
		halign = "center",
		uiscale = 0.95,
		saturation = 0.7,
		brightness = 0.4,
	},

	{
		classes = {"dice", "gmonly"},
		saturation = 0.3,
		brightness = 0.2,
	},
	
	{
	
		classes = {"dice", "hover"},
		scale = 1.2,
		brightness = 1.2,
	},

	{
		classes = {"diceLines", "gmonly"},
		saturation = 0.5,
		brightness = 0.5,
	},
}

CreateDicePanel = function()

	local amendableRoll = nil

	local diceStyle = dmhub.GetDiceStyling(dmhub.GetSettingValue("diceequipped"), dmhub.GetSettingValue("playercolor"))
	
	local CreateDice = function(faces, params)

		local imageFaces = faces
		local selectedDie = nil
		local selectedDieFilled = nil
		local selectedNum = nil
		local selectedFaces = nil
		local selectedString = nil
		local textColor = nil

		if imageFaces == 3 then
			selectedDie = "ui-icons/dsdice/djordice-d6.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d6-filled.png"			
			selectedNum = 1
			selectedFaces = 3
			selectedString = "3"
			selectedFontSize = 18
			selectedYAdjust = 2		
		elseif imageFaces == 6 then
			selectedDie = "ui-icons/dsdice/djordice-d6.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d6-filled.png"	
			selectedNum = 1
			selectedFaces = 6
			selectedString = "6"
			selectedFontSize = 18
			selectedYAdjust = 2			
		elseif imageFaces == 10 then
			selectedDie = "ui-icons/dsdice/djordice-d10.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d10-filled.png"	
			selectedNum = 1
			selectedFaces = 10
			selectedString = "10"
			selectedFontSize = 14
			selectedYAdjust = 0			
		elseif imageFaces == 20 then
			selectedDie = "ui-icons/dsdice/djordice-2d10.png"	
			selectedDieFilled = "ui-icons/dsdice/djordice-2d10-filled.png"		
			selectedNum = 2
			selectedFaces = 10
			selectedString = "Power Roll"
			selectedFontSize = 10		
			selectedYAdjust = 0
		end

	
		--a single dice
		local args = {
		
			classes = "dice",
			bgimage = selectedDieFilled,
			--bgimage = string.format("ui-icons/d%d-filled.png", imageFaces),
			bgcolor = diceStyle.bgcolor,

            dragMove = false,
            draggable = true,
            beginDrag = function(self)
                dmhub.Roll{
                    drag = true,
                    numDice = selectedNum,
                    numFaces = selectedFaces,
					numKeep = 0,
                    description = "Custom Roll",
                }
            end,

			click = function(panel)
				if amendableRoll ~= nil and amendableRoll.amendable then
					amendableRoll = amendableRoll:Amend{
						numDice = selectedNum,
						numFaces = selectedFaces,
						numKeep = 0,
						description = "Custom Roll",
						amendable = true,
					}

					return
				end


				printf("Roll: rolling with numDice = 1; numFaces = %d", math.tointeger(faces))
                amendableRoll = dmhub.Roll{
                    numDice = selectedNum,
                    numFaces = selectedFaces,
					numKeep = 0,
                    description = "Custom Roll",
					amendable = true,
                }
            end,

			--hover = gui.Tooltip(string.format("D%d", faces)),

			gui.Panel{
				classes = {"diceLines"},
				interactable = false,
				width = "100%",
				height = "100%",
				bgimage = selectedDie,
				--bgimage = string.format("ui-icons/d%d.png", imageFaces),
				bgcolor = diceStyle.trimcolor,
			},

			checklighting = function(element)
				local lightbg = TokenHud.UseLightBackgroundColor(core.Color(textColor))
				if lightbg then
					bglabel.selfStyle.color = textColor
					element.selfStyle.color = "white"
				else
					bglabel.selfStyle.color = "black"
					element.selfStyle.color = textColor
				end
			end,

			-- Drop Shadow for the Die Face Number
			gui.Label{
				width = "100%",
				height = "auto",
				fontFace = "Book",
				fontSize = selectedFontSize,
				color = "black",
				halign = "center",
				valign = "center",			
				textAlignment = "center",				
				text = selectedString,
				y = selectedYAdjust + 1,
				x = 1
			},			

			-- Text for the Die Face Number
			gui.Label{
				width = "100%",
				height = "auto",
				fontFace = "Book",
				fontSize = selectedFontSize,
				color = "white",
				halign = "center",
				valign = "center",			
				textAlignment = "center",				
				text = selectedString,
				y = selectedYAdjust
			}

		}

		if params ~= nil then
			for k,v in pairs(params) do
				args[k] = v
			end
		end

		local result = gui.Panel(args)
		print ("dj", result.events)
		return result
	end
	
	
    local resultPanel
	resultPanel = gui.Panel{
	
		width = "100%",
		height = "100%",
		styles = styles,

		bgimage = "panels/square.png",
		bgcolor = "clear",

		multimonitor = {"privaterolls"},
		monitor = function(element)
			element:SetClassTree("gmonly", dmhub.GetSettingValue("privaterolls") == "dm")
		end,

		rightClick = function(element)
			element.popup = gui.ContextMenu{
				entries = {
					{
						text = "Rolls Visible Only to Director",
						check = dmhub.GetSettingValue("privaterolls") == "dm",
						click = function()
							dmhub.SetSettingValue("privaterolls", cond(dmhub.GetSettingValue("privaterolls") == "dm", "visible", "dm"))
							element.popup = nil
						end,
					},
				}

			}
		end,
		
		
		gui.Panel{
		
			width = "105%",
			height = "60%",
			valign = "center",
			halign = "center",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			flow = "horizontal",
			y = -1,


			multimonitor = {"diceequipped", "playercolor"},

			events = {
				monitor = function(element)
					diceStyle = dmhub.GetDiceStyling(dmhub.GetSettingValue("diceequipped"), dmhub.GetSettingValue("playercolor"))
					element:FireEvent("create")
				end,

				create = function(element)
					element.children = {
						CreateDice(3, {uiscale = 1.1}),
						CreateDice(6, {uiscale = 1.2}),
						--CreateDice(8),
						--CreateDice(20, {uiscale = 1.65, y = 2}),
						CreateDice(10, {uiscale = 1.5, y = 2}),
						CreateDice(20, {uiscale = 1.65, y = 2, width = 60}),						
						--CreateDice(12),
						--CreateDice(100, {rotate = 180}),
					}
			        resultPanel:SetClassTree("gmonly", dmhub.GetSettingValue("privaterolls") == "dm")
				end,
			}
		},
	}

	resultPanel:SetClassTree("gmonly", dmhub.GetSettingValue("privaterolls") == "dm")

	return resultPanel

end