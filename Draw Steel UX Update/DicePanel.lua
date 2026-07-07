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
	minHeight = 160,
	maxHeight = 160,
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

		-- 3D mode: replace the static #DiceIcon tile with a LIVE cage, like the shop's "try dice"
		-- (see MakeTryDiceCage in CodexShopScreen.lua). A real, numberless die rests on the tile,
		-- spins on hover, and rolls seamlessly on click/drag as a real (chat, networked) roll -- the
		-- same resting die tumbles into the result, its text label vanishes and its numbers fade in.
		-- The non-3D (Default set) path below is unchanged.
		if use3D then
			-- shadowLabel/faceLabel are the "Power Roll"/"3"/"6"/"10" text drawn on top of the
			-- resting die; forward-declared so the roll handlers can hide/show them.
			local shadowLabel
			local faceLabel

			local function setLabelsHidden(hidden)
				if shadowLabel ~= nil and shadowLabel.valid then shadowLabel:SetClass("hidden", hidden) end
				if faceLabel ~= nil and faceLabel.valid then faceLabel:SetClass("hidden", hidden) end
			end

			-- Invisible-but-hittable cage filling the tile. The die anchors to its world centre; the
			-- labels are SIBLINGS drawn on top, so hiding a label never touches the cage and the
			-- cage's opacity-0 invisibility never touches the labels. All engine calls are
			-- pcall-guarded so a Lua-only reload against an older binary degrades gracefully.
			-- gui.DicePreview is a dedicated dice-preview cage panel type. Fall back to a plain
			-- gui.Panel on an older binary (Lua-only reload) that predates it; the dice field/
			-- method calls below are already pcall-guarded so they no-op on the fallback.
			-- (gui is engine userdata, so index via pcall rather than rawget.)
			local diceCageCtor = gui.Panel
			pcall(function() diceCageCtor = gui.DicePreview or gui.Panel end)
			local cage = diceCageCtor{
				width = "100%",
				height = "100%",
				halign = "center",
				valign = "center",
				floating = true,
				bgimage = true,
				bgcolor = "white",
				styles = { gui.Style{ opacity = 0 } },
				draggable = true,
				dragMove = false,
				-- rolling: true from the moment a click/drag launches a roll until the next
				-- seedDie, so the dehover handler knows not to restore the labels mid-roll.
				data = { reseedPending = false, rolling = false },

				create = function(element)
					pcall(function() element:SetAsDicePreviewPanel(true) end)
					-- Resting dice render "virtually" (an off-screen texture shown as a regular
					-- image inside the panel) so dialogs opened over the dock cover them; they
					-- seamlessly become real 3D dice while hovered, dragged or rolling.
					pcall(function() element.dicePreviewVirtual = true end)
					-- Per-cage preview tuning (previously process-globals, which leaked into
					-- the shop and roll-dialog cages while the dock existed): thrown dice roll
					-- out across the whole screen, the Power Roll d10 pair sits closer
					-- together, and resting dice sit small on the tiles (they grow back to
					-- full size when hovered/thrown; hover/roll sizes are unaffected).
					-- The scale animation moves at a fixed rate, so this cage's larger
					-- rest->hover size gap needs the speed boost below to pop quickly on
					-- hover instead of sluggishly inflating.
					pcall(function()
						element.dicePreviewScreenBounds = true
						element.dicePreviewSpacing = 0.78
						element.dicePreviewRestScale = 0.6
						element.dicePreviewScaleSpeed = 5
					end)
					if selectedGeo == "power" then
						-- The Power Roll PAIR rests a bit bigger and tighter than the
						-- single-die tiles; on hover both relax back to the standard
						-- full size and the spread dicePreviewSpacing authored, so the
						-- scaled-up pose is identical to the other tiles' behavior.
						-- Separate pcall, RestSpacing FIRST: on an older binary without
						-- it the pcall aborts before touching RestScale, leaving the
						-- tile on the standard tuning above instead of half-applied.
						pcall(function()
							element.dicePreviewRestSpacing = 0.7
							element.dicePreviewRestScale = 0.7
						end)
					end
					element:FireEvent("seedDie")
				end,
				destroy = function(element)
					pcall(function() element:CancelDicePreviewRoll() end)
					pcall(function() element:SetAsDicePreviewPanel(false) end)
				end,

				-- Seed a resting, numberless die in the equipped set, armed so a click/drag throws it
				-- as a real roll. Unlike the shop we OMIT ["local"]/silent (the shop titlescreen has
				-- no chat/network) and amendable (each tile rolls standalone). Re-seed after the roll
				-- finishes or a too-weak drag cancels, so a fresh die is always resting here.
				seedDie = function(element)
					if not element.valid then
						return
					end
					element.data.reseedPending = false
					element.data.rolling = false
					pcall(function() element:CancelDicePreviewRoll() end)
					setLabelsHidden(false)
					dmhub.Roll{
						preview = true, previewPanel = element, hideNumbers = true,
						numDice = selectedNum, numFaces = selectedFaces, numKeep = 0,
						description = "Custom Roll",
						complete = function()
							if element.valid then element:FireEvent("requestReseed") end
						end,
						cancel = function()
							if element.valid then element:FireEvent("requestReseed") end
						end,
					}
				end,

				requestReseed = function(element)
					if not element.valid or element.data.reseedPending then
						return
					end
					element.data.reseedPending = true
					element:ScheduleEvent("seedDie", 0.6)
				end,

				-- Hover wobble + click/drag-to-roll, scoped to THIS cage's dice. Hovering
				-- fades the die's real numbers in (engine-side, keyed off the same
				-- mouseover state), so the text label hides while the mouse is on the
				-- tile and returns on dehover -- unless a roll is in flight, in which
				-- case the label stays hidden until the reseed shows it again.
				hover = function(element)
					setLabelsHidden(true)
					pcall(function() element:DicePreviewMouseEnter() end)
				end,
				dehover = function(element)
					if not element.data.rolling then
						setLabelsHidden(false)
					end
					pcall(function() element:DicePreviewMouseLeave() end)
				end,
				dragging = function(element)
					pcall(function() element:DicePreviewDragThink() end)
				end,
				drag = function(element)
					element.data.rolling = true
					setLabelsHidden(true)
					pcall(function() element:DicePreviewDragEnd() end)
				end,
				click = function(element)
					element.data.rolling = true
					setLabelsHidden(true)
					pcall(function() element:DicePreviewClick() end)
				end,
			}

			-- Drop-shadow + foreground roll-type label, floating (overlaid) and non-interactable so
			-- clicks fall through to the cage below. As LATER SIBLINGS of the cage they draw above
			-- the virtual die's embedded image; while the die is hovered or rolling it becomes a
			-- real 3D die compositing over the whole UI (and the labels hide during rolls).
			shadowLabel = gui.Label{
				floating = true,
				interactable = false,
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
				x = 1,
			}
			faceLabel = gui.Label{
				floating = true,
				interactable = false,
				width = "100%",
				height = "auto",
				fontFace = "Book",
				fontSize = selectedFontSize,
				color = "white",
				halign = "center",
				valign = "center",
				textAlignment = "center",
				text = selectedString,
				y = selectedYAdjust,
			}

			-- The visible tile is just a transparent container (the resting die is the cage's
			-- embedded dice image; hovered/rolling dice composite over the whole UI).
			-- saturation/brightness override the dimming baked into the "dice" style.
			local cageArgs = {
				classes = "dice",
				saturation = 1,
				brightness = 1,
				cage,
				shadowLabel,
				faceLabel,
			}

			if params ~= nil then
				for k,v in pairs(params) do
					cageArgs[k] = v
				end
			end

			return gui.Panel(cageArgs)
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
			-- Re-seed the 3D cages so a director-visibility toggle takes effect on the very next
			-- roll (each resting die captured its dmonly at seed time).
			element:FireEventTree("requestReseed")
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
			height = "100%",
			valign = "top",
			halign = "center",
			bgimage = "panels/square.png",
			bgcolor = "clear",
			flow = "vertical",
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
                        gui.Panel{
                            width = "100%",
                            height = "auto",
                            y = -16,
						    CreateDice(20, {uiscale = 2.65, y = 2, width = 60}),						
                        },
                        gui.Divider{ y = -26, brightness = 0.1},
                        gui.Panel{
                            width = "70%",
                            height = "auto",
                            halign = "center",
                            flow = "horizontal",
                            y = -27,
                            CreateDice(3, {uiscale = 1.3}),
                            CreateDice(6, {uiscale = 1.3}),
                            --CreateDice(8),
                            --CreateDice(20, {uiscale = 1.65, y = 2}),
                            CreateDice(10, {uiscale = 1.5, y = 2}),
                            --CreateDice(12),
                            --CreateDice(100, {rotate = 180}),
                        },
					}
			        resultPanel:SetClassTree("gmonly", dmhub.GetSettingValue("privaterolls") == "dm")

						-- The screen-bounds/spacing/rest-scale tuning is set PER-CAGE in each
						-- tile's cage create handler (dicePreviewScreenBounds / Spacing /
						-- RestScale in CreateDice above), not via the dice.SetPreview* globals:
						-- the dock coexists with the shop and the in-game roll dialog, and the
						-- globals leaked this panel's tuning into their cages.
					end,
				}
			},
	}

	resultPanel:SetClassTree("gmonly", dmhub.GetSettingValue("privaterolls") == "dm")

	return resultPanel

end