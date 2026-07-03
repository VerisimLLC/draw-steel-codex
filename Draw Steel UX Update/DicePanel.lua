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

	-- When a non-default dice set is equipped, draw each die as its real 3D model rendered
	-- off-screen (transparent, numberless) instead of the flat PNG icon. equipped/use3D are
	-- recomputed by the diceequipped/playercolor monitor below so the panel rebuilds on change.
	local equipped = dmhub.GetSettingValue("diceequipped")
	local use3D = equipped ~= nil and equipped ~= "" and equipped ~= "Default"

	local CreateDice = function(faces, params)

		local imageFaces = faces
		local selectedDie = nil
		local selectedDieFilled = nil
		local selectedNum = nil
		local selectedFaces = nil
		local selectedString = nil
		local textColor = nil
		-- Which 3D die geometry this tile renders when use3D (d3 uses the d6 model; the d20
		-- "Power Roll" renders as the two-d10 pair). nil = fall back to the whitelabel default.
		local selectedGeo = nil

		if imageFaces == 3 then
			selectedDie = "ui-icons/dsdice/djordice-d6.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d6-filled.png"
			selectedNum = 1
			selectedFaces = 3
			selectedString = "3"
			selectedFontSize = 18
			selectedYAdjust = 2
			selectedGeo = "d6"
		elseif imageFaces == 6 then
			selectedDie = "ui-icons/dsdice/djordice-d6.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d6-filled.png"
			selectedNum = 1
			selectedFaces = 6
			selectedString = "6"
			selectedFontSize = 18
			selectedYAdjust = 2
			selectedGeo = "d6"
		elseif imageFaces == 10 then
			selectedDie = "ui-icons/dsdice/djordice-d10.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d10-filled.png"
			selectedNum = 1
			selectedFaces = 10
			selectedString = "10"
			selectedFontSize = 14
			selectedYAdjust = 0
			selectedGeo = "d10"
		elseif imageFaces == 20 then
			selectedDie = "ui-icons/dsdice/djordice-2d10.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-2d10-filled.png"
			selectedNum = 2
			selectedFaces = 10
			selectedString = "Power Roll"
			selectedFontSize = 10
			selectedYAdjust = 0
			selectedGeo = "power"
		end

	
		--a single dice

		-- In 3D mode draw the real die rendered off-screen (transparent, numberless) as the panel
		-- background; otherwise keep the flat filled PNG icon.
		local dieBgImage = selectedDieFilled
		local dieBgColor = diceStyle.bgcolor
		if use3D then
			-- Static, numberless icon rendered once from the real 3D die and cached (see
			-- DiceIconManager). Same (assetid, geo) is shared across tiles and panel rebuilds.
			dieBgImage = string.format("#DiceIcon:%s:%s", tostring(equipped), tostring(selectedGeo))
			dieBgColor = "white"
		end

		local args = {

			classes = "dice",
			bgimage = dieBgImage,
			bgcolor = dieBgColor,

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

		-- The flat colored die outline only makes sense for the 2D icon; in 3D mode the model
		-- replaces it. Insert it as the first (bottom) child so the labels still sit on top.
		if not use3D then
			table.insert(args, 1, gui.Panel{
				classes = {"diceLines"},
				interactable = false,
				width = "100%",
				height = "100%",
				bgimage = selectedDie,
				bgcolor = diceStyle.trimcolor,
			})
		else
			-- Show the live 3D die in its natural color, not dimmed by the flat-icon "dice" style.
			args.saturation = 1
			args.brightness = 1
		end

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
					equipped = dmhub.GetSettingValue("diceequipped")
					use3D = equipped ~= nil and equipped ~= "" and equipped ~= "Default"
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