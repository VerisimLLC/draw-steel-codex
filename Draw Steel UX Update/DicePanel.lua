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

----------------------------------------------------------------
-- Physical Dice (GoDice) integration
----------------------------------------------------------------
do

--[[
================================================================
Go Dice — Codex mod
================================================================

Intercepts Codex roll dialogs and routes the dice through a local
HTTP service (the Python "Codex GoDice Bridge"). The physical
GoDice pass their face values engine via rollArgs.forcedDice, 
and the engine resolves the original roll expression as if it had 
rolled those values itself — populating rollInfo.rolls, naturalRoll, 
nat1/nat20, total, tier, and firing the crit audio cue when appropriate.

PAIRED WITH: codex-godice-bridge (Python). The HTTP contract is
documented in that repo's README. Both must update together when
the contract changes.

USER SURFACE:
  - Settings panel ("General" section) provides the toggle, the
    bridge URL, and the bridge program path. These are the canonical
    configuration.
  - Ticking "Use Physical Dice" auto-starts the bridge process via
    dmhub.StartDiceBridge (engine-side DiceBridgeProcess); unticking
    stops it. If the bridge dies mid-roll the mod falls back to a
    virtual roll rather than hanging the dialog.
  - /godice chat commands stay for diagnostics and runtime probing.

SCOPE:
  - Ability rolls (RollDialog.OnBeforeRoll), single- and multi-
    target. Single roll resolves against all targets; per-target
    boons in args.multitargets[i] applied by the engine.
  - Re-roll (OnReroll) and table roll (OnBeforeTableRoll):
    not yet registered. The hook-snapshot infra is in place so
    they're a one-line add when ready.
  - Multi-dice-expression rolls like "1d20 + 1d4" not yet handled
    (bridge returns a single combined total).
]]--

----------------------------------------------------------------
-- Settings (user-facing panel under General)
----------------------------------------------------------------
-- These create the persistent settings AND the entries in the
-- Codex preferences UI. 

local SETTING_ENABLED  = "externaldice:enabled"
local SETTING_BRIDGE   = "externaldice:bridgeurl"
local SETTING_BRIDGEPATH = "externaldice:bridgepath"
local DEFAULT_BRIDGE   = "http://127.0.0.1:17211"

-- Sending chat before the local user has a game session (e.g. the character
-- creation lobby, or before the session is established at startup) crashes the
-- engine: ChatPanel.SendChat indexes usersToSessions[effectiveUserId] without a
-- guard. GetSessionInfo reads that same dictionary safely, so gate on it.
local function chatNotify(msg)
    local chatLib = rawget(_G, "chat")
    if chatLib == nil or chatLib.Send == nil then
        return
    end
    if dmhub.GetSessionInfo == nil or dmhub.GetSessionInfo(dmhub.userid) == nil then
        return
    end
    chatLib.Send(msg)
end

-- Start/stop the bridge process alongside the checkbox. The engine
-- resolves the executable itself (the bridgepath preference below, or
-- godice-bridge.exe next to the player executable) so this API can't be
-- pointed at an arbitrary binary. Guarded for engine builds that predate
-- dmhub.StartDiceBridge. `announce` posts feedback to chat -- pass false for
-- non-interactive calls (e.g. startup auto-start) so a normal game load stays
-- quiet.
local function syncBridgeProcess(enabled, announce)
    if enabled then
        if dmhub.StartDiceBridge ~= nil then
            if dmhub.StartDiceBridge() then
                -- The bridge runs windowless, so without this there is no
                -- visible sign the checkbox did anything.
                if announce then
                    chatNotify("GoDice bridge started. Wake your dice (give them a shake) and they will connect within a few seconds -- check with /godice status.")
                end
            else
                if announce then
                    chatNotify("Could not start the GoDice bridge. Set 'Physical Dice Bridge Program' in settings to the bridge executable, or start it manually.")
                end
            end
        end
    else
        if dmhub.StopDiceBridge ~= nil then
            dmhub.StopDiceBridge()
        end
        if announce then
            chatNotify("GoDice bridge stopped.")
        end
    end
end

local g_externalDiceEnabled = setting{
    id = SETTING_ENABLED,
    description = "Use Physical Dice",
    help = "Route dice rolls through a localhost bridge to physical GoDice. The bridge program starts automatically when checked.",
    storage = "preference",
    section = "General",
    default = false,
    editor = "check",
    onchange = function()
        syncBridgeProcess(dmhub.GetSettingValue(SETTING_ENABLED) == true, true)
    end,
}

-- Where the bridge executable lives. Read by the ENGINE (DiceBridgeProcess),
-- not by this mod. Empty means "godice-bridge.exe next to the player
-- executable"; during development point it at your built bridge.exe.
local g_externalDiceBridgePath = setting{
    id = SETTING_BRIDGEPATH,
    description = "Physical Dice Bridge Program",
    help = "Path to the GoDice bridge executable. Leave empty to use godice-bridge.exe next to the Codex executable.",
    characterLimit = 400,
    editor = "input",
    storage = "preference",
    section = "General",
    default = "",
}

local g_externalDiceBridgeUrl = setting{
    id = SETTING_BRIDGE,
    description = "Physical Dice Bridge URL",
    characterLimit = 200,
    editor = "input",
    storage = "preference",
    section = "General",
    default = DEFAULT_BRIDGE,
}

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

-- Use rawget on _G so Codex's strict-globals metatable doesn't error
-- on the read when CodexGoDiceBridge isn't initialized yet (which it
-- won't be on the first of Codex's two load passes). Same trick is
-- used below for RollDialog / Commands / chat / json — any global we
-- test with `if X` first needs the rawget guard.
CodexGoDiceBridge = rawget(_G, "CodexGoDiceBridge") or {
    -- Long-poll wait per round-trip. Bridge clamps to [0, 60].
    waitSeconds = 25,

    -- Cached snapshot of which RollDialog.On* fields existed at load.
    codexDeclaredHooks = nil,

    -- Set true to dump the full args table on each OnBeforeRoll.
    debugDump = false,
}

local CGB = CodexGoDiceBridge

-- Read the current bridge URL from preferences. Falls back to the
-- default if the setting is missing or empty so we still try a
-- sensible endpoint instead of failing with an empty URL.
function CGB.getBaseUrl()
    local url = dmhub.GetSettingValue(SETTING_BRIDGE)
    if type(url) ~= "string" or url == "" then return DEFAULT_BRIDGE end
    return url
end

-- The "Use Physical Dice" toggle is the master switch. Interception
-- only happens when this is true.
function CGB.isEnabled()
    return dmhub.GetSettingValue(SETTING_ENABLED) == true
end

----------------------------------------------------------------
-- Logging
----------------------------------------------------------------
-- `print` writes to Codex's in-app console. Reserve chat.Send
-- for output the user actually wants to see at the table.
-- Note: Codex loads Main.lua twice per startup, so expect each
-- load-time log line to appear twice. Harmless.
local function log(fmt, ...)
    print("CGB: " .. string.format(fmt, ...))
end

----------------------------------------------------------------
-- HTTP helpers
----------------------------------------------------------------
-- Codex's net.Get / net.Post are async, JSON-bodied, single-callback.
--   net.Get{ url=..., success=fn(result), error=fn(err) }
--   net.Post{ url=..., data=table, success=fn(result), error=fn(err) }

local function decodeBody(result)
    if type(result) == "table" then return result end
    if type(result) == "string" then
        if dmhub and dmhub.FromJson then return dmhub.FromJson(result) end
        local jsonLib = rawget(_G, "json")
        if jsonLib and jsonLib.parse then return jsonLib.parse(result) end
        log("decodeBody: no JSON parser available; result was string")
    end
    return nil
end

function CGB.bridgeStatus(onResult)
    net.Get{
        url = CGB.getBaseUrl() .. "/v1/status",
        success = function(result) onResult(true, decodeBody(result)) end,
        error   = function(err)    onResult(false, err) end,
    }
end

function CGB.createRoll(diceList, timeoutMs, onResult)
    net.Post{
        url = CGB.getBaseUrl() .. "/v1/rolls",
        data = { dice = diceList, timeout_ms = timeoutMs or 30000 },
        success = function(result) onResult(true, decodeBody(result)) end,
        error   = function(err)    onResult(false, err) end,
    }
end

function CGB.pollRoll(requestId, onResult)
    net.Get{
        url = CGB.getBaseUrl() .. "/v1/rolls/" .. requestId .. "?wait=" .. tostring(CGB.waitSeconds),
        success = function(result) onResult(true, decodeBody(result)) end,
        error   = function(err)    onResult(false, err) end,
    }
end

function CGB.cancelRoll(requestId)
    net.Post{
        url = CGB.getBaseUrl() .. "/v1/rolls/" .. requestId .. "/cancel",
        data = {},
        success = function(_) end,
        error   = function(_) end,
    }
end

----------------------------------------------------------------
-- "Waiting for physical dice" notice
----------------------------------------------------------------
-- Shown while an intercepted roll is waiting on the bridge. Gives the
-- user visible feedback that the game wants physical dice, and an
-- escape hatch to roll this one virtually instead (cancels the bridge
-- request). One notice at most; module-level so a new intercept
-- replaces any stale one.

local m_waitingNotice = nil

local function destroyWaitingNotice()
    if m_waitingNotice ~= nil then
        if m_waitingNotice.valid then
            m_waitingNotice:DestroySelf()
        end
        m_waitingNotice = nil
    end
end

local function showWaitingNotice(onUseVirtual)
    destroyWaitingNotice()

    local hudLib = rawget(_G, "GameHud")
    local hud = hudLib and hudLib.instance
    if hud == nil then return end
    -- dialog.sheet is the screen-space hud root; MainDialogPanel is NOT
    -- screen-anchored (a panel parented there renders off the bottom edge).
    local parent = hud.dialog and hud.dialog.sheet
    if parent == nil and hud.MainDialogPanel ~= nil then
        parent = hud:MainDialogPanel()
    end
    if parent == nil then return end

    m_waitingNotice = gui.Panel{
        floating = true,
        halign = "center",
        valign = "center",
        width = 320,
        height = "auto",
        flow = "vertical",
        bgimage = "panels/square.png",
        bgcolor = "#000000dd",
        borderWidth = 1,
        borderColor = "#999999",
        cornerRadius = 8,
        pad = 10,
        borderBox = true,

        gui.Label{
            text = "Waiting for physical dice...",
            fontSize = 16,
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            color = "white",
        },

        gui.Button{
            text = "Use Virtual Dice",
            fontSize = 14,
            width = 150,
            height = 26,
            halign = "center",
            vmargin = 8,
            click = function(element)
                onUseVirtual()
            end,
        },
    }

    parent:AddChild(m_waitingNotice)
end

----------------------------------------------------------------
-- Roll-string parsing — dice list extraction only
----------------------------------------------------------------
-- We only need the ordered dice list to send to the bridge. The
-- engine handles all modifiers, boons/banes, tier, and natural-roll
-- effects when it resolves the original expression with our
-- rollArgs.forcedDice. We do NOT collapse the expression here.

local SUPPORTED_DICE = {
    d4 = true, d6 = true, d8 = true,
    d10 = true, d12 = true, d20 = true,
}

local function extractDiceList(rollStr)
    if type(rollStr) ~= "string" then return nil end
    if not (dmhub and dmhub.ParseRoll and dmhub.RollToString) then
        log("dmhub.ParseRoll/RollToString unavailable")
        return nil
    end

    local parsed = dmhub.ParseRoll(rollStr)
    if parsed == nil then return nil end

    -- Strip boons so the dice regex doesn't have to know about them.
    parsed.boons = nil
    parsed.banes = nil
    local cleanRoll = dmhub.RollToString(parsed) or rollStr

    local diceList = {}
    for n, sides in string.gmatch(cleanRoll, "(%d*)d(%d+)") do
        local count = tonumber(n) or 1
        local key = "d" .. sides
        if not SUPPORTED_DICE[key] then return nil end
        for _ = 1, count do table.insert(diceList, key) end
    end
    if #diceList == 0 then return nil end
    return diceList
end

----------------------------------------------------------------
-- Roll interception
----------------------------------------------------------------
-- Returning "intercept" from a hook tells the dialog NOT to run the
-- roll itself; we own completion and must eventually complete exactly
-- once (dmhub.Roll for fresh rolls, amendWithResult for rerolls) or
-- the dialog hangs forever.
--
-- IMPORTANT: shallow-copy rollArgs before mutating. Codex holds the
-- same reference in g_activeRollArgs and a re-roll dialog reads it
-- back -- mutating in place breaks re-rolls silently.

local function shallowCopy(t)
    local out = {}
    for k, v in pairs(t or {}) do out[k] = v end
    return out
end

local function logRollArgs(args)
    if not CGB.debugDump then return end
    log("OnBeforeRoll args dump:")
    for k, v in pairs(args or {}) do
        log("  args.%s = %s (%s)", tostring(k), tostring(v), type(v))
    end
    if args and args.rollArgs then
        for k, v in pairs(args.rollArgs) do
            log("  args.rollArgs.%s = %s (%s)", tostring(k), tostring(v), type(v))
        end
    end
end

-- Shared bridge-roll driver used by fresh rolls and rerolls. Owns the
-- waiting notice, the single-completion guard, the dialog-cancel
-- bookkeeping, and the poll loop. Exactly one of the callbacks fires:
--   opts.onForced(forcedDice)  physical dice settled
--   opts.onVirtual()           any fallback (bridge failure, timeout,
--                              or the user's Use Virtual Dice button)
-- Nothing fires when the roll dialog is cancelled (RollDialog.
-- OnRollCancelled) -- the dialog is gone, so no roll should happen;
-- the pending bridge request is aborted so the dice stop flashing.
local function runBridgeRoll(diceList, opts)
    local m_finished = false
    local function finish(fn)
        if m_finished then return end
        m_finished = true
        CGB.activeCancel = nil
        destroyWaitingNotice()
        fn()
    end

    local function fallbackToVirtual(reason)
        finish(function()
            log("falling back to virtual roll: %s", tostring(reason))
            local chatLib = rawget(_G, "chat")
            if chatLib and chatLib.Send then
                chatLib.Send("GoDice: " .. tostring(reason) .. " -- rolling virtually.")
            end
            opts.onVirtual()
        end)
    end

    CGB.createRoll(diceList, 30000, function(ok, body)
        if not ok or not body or not body.request_id then
            fallbackToVirtual("bridge unreachable (check /godice status)")
            return
        end

        local requestId = body.request_id

        -- Wired to RollDialog.OnRollCancelled: abort the bridge request
        -- (dice stop flashing, request marked cancelled server-side) and
        -- complete nothing, since the dialog is gone.
        CGB.activeCancel = function()
            finish(function()
                log("roll dialog cancelled; aborting bridge request %s", requestId)
                CGB.cancelRoll(requestId)
            end)
        end

        -- Visible feedback plus a per-roll opt-out. The button cancels
        -- the bridge request and completes with the engine's virtual dice.
        showWaitingNotice(function()
            finish(function()
                log("user chose virtual dice for request %s", requestId)
                CGB.cancelRoll(requestId)
                opts.onVirtual()
            end)
        end)

        local function continuePoll()
            CGB.pollRoll(requestId, function(pOk, pBody)
                if m_finished then
                    return
                end

                if not pOk or not pBody then
                    fallbackToVirtual("bridge stopped responding")
                    return
                end

                local status = pBody.status

                if status == "still_waiting" then
                    continuePoll()
                    return
                end

                if status == "complete" then
                    local forcedDice = {}
                    if type(pBody.slots) == "table" then
                        for _, slot in ipairs(pBody.slots) do
                            local sides = tonumber(string.match(tostring(slot.type or ""), "d(%d+)"))
                            local value = tonumber(slot.value)
                            if sides and value then
                                table.insert(forcedDice, { numFaces = sides, result = value })
                            end
                        end
                    end

                    if #forcedDice ~= #diceList then
                        log("WARN forcedDice count (%d) != expected diceList count (%d) for request %s",
                            #forcedDice, #diceList, requestId)
                    end

                    log("complete request=%s forcedDice=%d", requestId, #forcedDice)
                    finish(function() opts.onForced(forcedDice) end)
                elseif status == "timeout" then
                    fallbackToVirtual("no physical dice rolled in time")
                else
                    -- "cancelled" from outside this flow, or an unknown
                    -- terminal status. The dialog still needs completion,
                    -- so roll virtually.
                    fallbackToVirtual("roll " .. tostring(status))
                end
            end)
        end

        continuePoll()
    end)
end

local function handleOnBeforeRoll(args)
    if not CGB.isEnabled() then return nil end
    logRollArgs(args)

    local rollStr = (args.rollArgs and args.rollArgs.roll) or args.roll
    local diceList = extractDiceList(rollStr)
    if not diceList then
        log("unparseable roll '%s'; falling back to virtual", tostring(rollStr))
        return nil
    end

    log("intercepting '%s' (%d dice)", tostring(rollStr), #diceList)
    local rollArgsCopy = shallowCopy(args.rollArgs or args)

    -- The dialog hands us setActiveRoll so it can track the roll WE start.
    -- Without this the dialog's g_activeRoll stays nil and everything that
    -- needs the roll handle (the Re-roll button especially) silently
    -- no-ops for physical rolls.
    local setActiveRoll = args.setActiveRoll

    local function runRoll()
        local activeRoll = dmhub.Roll(rollArgsCopy)
        if setActiveRoll ~= nil and activeRoll ~= nil then
            setActiveRoll(activeRoll)
        end
    end

    runBridgeRoll(diceList, {
        onForced = function(forcedDice)
            -- No instant/silent overrides: the virtual dice tumble and land
            -- showing the physical values (engine ForceResultFace), and the
            -- dialog's normal completion flow updates the displayed result.
            rollArgsCopy.roll       = rollStr
            rollArgsCopy.forcedDice = forcedDice
            runRoll()
        end,
        onVirtual = function()
            runRoll()
        end,
    })

    return "intercept"
end

-- Reroll interception: same bridge flow, but completion amends the
-- existing roll through the dialog-provided amendWithResult so the
-- dialog's begin/broadcast wiring stays intact. Relies on the dialogs'
-- doRerollAmend accepting an extraFields table (forcedDice etc.).
local function handleOnReroll(args)
    if not CGB.isEnabled() then return nil end
    if args.amendWithResult == nil then return nil end

    local rollStr = args.originalRoll
    local diceList = extractDiceList(rollStr)
    if not diceList then
        log("unparseable reroll '%s'; falling back to virtual", tostring(rollStr))
        return nil
    end

    log("intercepting reroll '%s' (%d dice)", tostring(rollStr), #diceList)

    runBridgeRoll(diceList, {
        onForced = function(forcedDice)
            -- forcedDice only -- the dialog's own instant/silent settings
            -- apply, so its begin/completion flow runs exactly as a normal
            -- reroll and the displayed result updates.
            args.amendWithResult(rollStr, {
                forcedDice = forcedDice,
            })
        end,
        onVirtual = function()
            args.amendWithResult(rollStr)
        end,
    })

    return "intercept"
end

-- Fired by the dialogs' Cancel path. Abandon any in-flight bridge
-- request; never rolls.
local function handleOnRollCancelled()
    if CGB.activeCancel ~= nil then
        local cancel = CGB.activeCancel
        CGB.activeCancel = nil
        cancel()
    end
end

----------------------------------------------------------------
-- Hook registration
----------------------------------------------------------------

local HOOK_SPECS = {
    { name = "OnBeforeRoll", fn = handleOnBeforeRoll, label = "ability rolls" },
    { name = "OnReroll", fn = handleOnReroll, label = "rerolls" },
    { name = "OnRollCancelled", fn = handleOnRollCancelled, label = "dialog cancel" },
}

local function registerHooks()
    local rd = rawget(_G, "RollDialog")
    if rd == nil then
        log("RollDialog is nil; cannot register hooks. Is this Codex?")
        return
    end

    -- Rebuilt every load (older cached snapshots go stale when the
    -- dialogs gain new hook points).
    local snapshot = {}
    for _, spec in ipairs(HOOK_SPECS) do
        snapshot[spec.name] = (rd[spec.name] ~= nil)
    end
    CGB.codexDeclaredHooks = snapshot

    for _, spec in ipairs(HOOK_SPECS) do
        if CGB.codexDeclaredHooks[spec.name] then
            rd[spec.name] = spec.fn
            log("registered RollDialog.%s (%s)", spec.name, spec.label)
        else
            log("RollDialog.%s missing; %s left as virtual", spec.name, spec.label)
        end
    end
end

----------------------------------------------------------------
-- Chat commands
----------------------------------------------------------------

local function splitArgs(str)
    local parts = {}
    for word in string.gmatch(str or "", "%S+") do
        table.insert(parts, word)
    end
    return parts
end

local function cmdStatus()
    CGB.bridgeStatus(function(ok, body)
        if ok and body then
            chat.Send(string.format(
                "GoDice bridge: ok=%s version=%s dice=%d pending=%d (mod enabled=%s url=%s)",
                tostring(body.ok),
                tostring(body.version),
                body.dice_count or 0,
                body.pending_rolls or 0,
                tostring(CGB.isEnabled()),
                CGB.getBaseUrl()))
            local hooks = CGB.codexDeclaredHooks or {}
            for name, present in pairs(hooks) do
                chat.Send(string.format("  hook %s: %s", name, present and "registered" or "missing"))
            end
        else
            chat.Send("GoDice bridge: unreachable (" .. tostring(body) .. ")")
        end
    end)
end

local commandsLib = rawget(_G, "Commands")
if commandsLib and commandsLib.RegisterMacro then
    commandsLib.RegisterMacro{
        name = "godice",
        summary = "control the GoDice bridge mod",
        doc = "Usage: /godice [status|on|off|debug on|debug off|probe|register]\n"
            .. "  status     — show bridge health and registered hooks\n"
            .. "  on / off   — enable/disable roll interception (writes the preference)\n"
            .. "  debug on/off — toggle dump of rollArgs on each intercept\n"
            .. "  probe      — check live state of RollDialog.OnBeforeRoll\n"
            .. "  register   — re-register hooks",
        completions = function(args, argIndex)
            if argIndex == 1 then
                return {
                    {text = "status",   summary = "show bridge health"},
                    {text = "on",       summary = "enable interception"},
                    {text = "off",      summary = "disable interception"},
                    {text = "debug",    summary = "toggle rollArgs dump"},
                    {text = "probe",    summary = "check live state of OnBeforeRoll"},
                    {text = "register", summary = "re-register hooks"},
                }
            elseif argIndex == 2 and args and args[1] == "debug" then
                return {
                    {text = "on",  summary = "start dumping rollArgs"},
                    {text = "off", summary = "stop dumping rollArgs"},
                }
            end
            return {}
        end,
        command = function(str)
            -- First line ever to run on a /godice invocation: confirms
            -- the macro fired at all. If you don't see this in the console
            -- after typing /godice anything, registration didn't take.
            print("CGB: /godice fired, raw='" .. tostring(str) .. "'")

            local parts = splitArgs(str)
            local sub = parts[1] or "status"
            if sub == "status" then
                cmdStatus()
            elseif sub == "on" then
                dmhub.SetSettingValue(SETTING_ENABLED, true)
                chat.Send("GoDice bridge: ENABLED (preference saved)")
            elseif sub == "off" then
                dmhub.SetSettingValue(SETTING_ENABLED, false)
                chat.Send("GoDice bridge: DISABLED (preference saved)")
            elseif sub == "debug" then
                CGB.debugDump = (parts[2] == "on")
                chat.Send("GoDice debug dump: " .. (CGB.debugDump and "on" or "off"))
            elseif sub == "probe" then
                local rd = rawget(_G, "RollDialog")
                local hook = rd and rd.OnBeforeRoll
                local handlerType = type(hook)
                local handlerStr = tostring(hook)
                local matchesOurs = (hook == handleOnBeforeRoll)
                chat.Send(string.format(
                    "RollDialog.OnBeforeRoll = %s (%s); matches our handler: %s",
                    handlerStr, handlerType, tostring(matchesOurs)))
                if not matchesOurs then
                    chat.Send("Re-registering hooks...")
                    registerHooks()
                end
            elseif sub == "register" then
                registerHooks()
                chat.Send("Hooks re-registered.")
            else
                chat.Send("Usage: /godice [status|on|off|debug on|debug off|probe|register]")
            end
        end,
    }
else
    log("Commands.RegisterMacro not available; chat commands not registered.")
end

----------------------------------------------------------------
-- Heartbeat to the bridge
----------------------------------------------------------------
-- The launcher EXE we ship spawns the bridge as a hidden child process
-- and kills it on Codex exit. If the launcher crashes, or the user
-- launches Codex directly (bypassing the launcher), or kills Codex via
-- Task Manager, the bridge would otherwise linger forever.
--
-- We tick a /v1/heartbeat POST every 5 seconds while the mod is enabled.
-- The bridge has an idle timeout (~60s); no heartbeats for that long and
-- it exits on its own.
--
-- Guarded against Codex's twice-per-startup file reload (idempotent).

function CGB.sendHeartbeat()
    net.Post{
        url = CGB.getBaseUrl() .. "/v1/heartbeat",
        data = {},
        success = function(_) end,
        error   = function(_) end,  -- silent; bridge may be down
    }
end

-- Generation counter, NOT a started flag: the CGB global survives code
-- reloads but scheduled callbacks do not, so a "started once" flag leaves
-- the loop dead after any reload (the bridge then hits its 60s idle
-- timeout and exits, killing rolls in flight). Every load starts a fresh
-- chain; stale chains from previous loads see the bumped generation and
-- stop, so Codex's double-load never stacks two chains.
CGB._heartbeatGen = (CGB._heartbeatGen or 0) + 1
local g_heartbeatGen = CGB._heartbeatGen

local function heartbeatLoop()
    if CGB._heartbeatGen ~= g_heartbeatGen then
        return  -- superseded by a newer load of this file
    end
    if CGB.isEnabled() then
        CGB.sendHeartbeat()
        -- Self-heal: if the bridge died (crash, idle timeout) while the
        -- feature is on, bring it back rather than waiting for the user
        -- to toggle the checkbox.
        if dmhub.IsDiceBridgeRunning ~= nil and dmhub.StartDiceBridge ~= nil
                and not dmhub.IsDiceBridgeRunning() then
            log("bridge process not running; restarting")
            dmhub.StartDiceBridge()
        end
    end
    dmhub.Schedule(5, heartbeatLoop)
end

dmhub.Schedule(2, heartbeatLoop)

----------------------------------------------------------------
-- Physical Dice dockable panel
----------------------------------------------------------------
-- The bridge runs windowless, so this panel is the visible face of
-- the integration: bridge reachability, each paired die with a
-- connection dot and battery, and a blink button to identify which
-- physical die is which. Polls the bridge every few seconds while
-- the panel is open; shows a hint when the feature is disabled.

local DIE_TYPE_OPTIONS = {
    {id = "d4",  text = "d4"},
    {id = "d6",  text = "d6"},
    {id = "d8",  text = "d8"},
    {id = "d10", text = "d10"},
    {id = "d12", text = "d12"},
    {id = "d20", text = "d20"},
}

-- onChanged is called after any action that alters the paired-dice list or
-- a die's declared type, so the panel re-polls immediately instead of
-- waiting for the next think tick.
local function CreateDieRow(die, onChanged)
    local connected = die.connected == true
    -- Battery is nil until the bridge's first real read after connect
    -- (there is no cached value for a sleeping die).
    local batteryText = "asleep"
    if connected then
        if die.battery ~= nil then
            batteryText = string.format("%d%%", tonumber(die.battery) or 0)
        else
            batteryText = "--"
        end
    end
    return gui.Panel{
        flow = "horizontal",
        width = "100%",
        height = 26,
        vmargin = 2,

        gui.Panel{
            width = 12,
            height = 12,
            halign = "left",
            valign = "center",
            hmargin = 4,
            bgimage = "panels/square.png",
            bgcolor = connected and "#40c040" or "#707070",
            cornerRadius = 6,
        },

        gui.Label{
            text = tostring(die.name or die.id),
            fontSize = 14,
            width = "26%",
            height = "auto",
            halign = "left",
            valign = "center",
            color = connected and "white" or "#aaaaaa",
        },

        gui.Label{
            text = batteryText,
            fontSize = 12,
            width = 44,
            height = "auto",
            valign = "center",
            color = "#aaaaaa",
        },

        -- Declared die size. GoDice do not self-report which shell is
        -- snapped on, so this is the user's declaration; changing it saves
        -- to the bridge config and rebinds the connection.
        gui.Dropdown{
            width = 64,
            height = 22,
            fontSize = 12,
            valign = "center",
            options = DIE_TYPE_OPTIONS,
            idChosen = tostring(die.type),
            change = function(element)
                net.Post{
                    url = CGB.getBaseUrl() .. "/v1/dice/" .. die.id .. "/type",
                    data = { type = element.idChosen },
                    success = function(_) onChanged() end,
                    error = function(_) end,
                }
            end,
        },

        gui.Button{
            text = "Blink",
            fontSize = 12,
            width = 48,
            height = 22,
            valign = "center",
            interactable = connected,
            click = function(element)
                net.Post{
                    url = CGB.getBaseUrl() .. "/v1/dice/" .. die.id .. "/blink",
                    data = { color = {80, 255, 80}, pulses = 4 },
                    success = function(_) end,
                    error = function(_) end,
                }
            end,
        },

        gui.Button{
            text = "x",
            fontSize = 12,
            width = 22,
            height = 22,
            valign = "center",
            hmargin = 2,
            hover = gui.Tooltip("Unpair this die"),
            click = function(element)
                net.Post{
                    url = CGB.getBaseUrl() .. "/v1/dice/" .. die.id .. "/unpair",
                    data = {},
                    success = function(_) onChanged() end,
                    error = function(_) end,
                }
            end,
        },
    }
end

local function CreatePhysicalDicePanel()
    local m_statusLabel
    local m_diceList

    local resultPanel

    local function refresh()
        if not CGB.isEnabled() then
            m_statusLabel.text = "Physical dice are disabled."
            m_diceList.children = {}
            return
        end

        CGB.bridgeStatus(function(ok, body)
            if resultPanel == nil or not resultPanel.valid then return end
            if not ok or body == nil then
                m_statusLabel.text = "Bridge: not responding (starting up?)"
                m_diceList.children = {}
                return
            end

            m_statusLabel.text = "Bridge: running"

            net.Get{
                url = CGB.getBaseUrl() .. "/v1/dice",
                success = function(result)
                    if resultPanel == nil or not resultPanel.valid then return end
                    local diceBody = decodeBody(result)
                    local rows = {}
                    if diceBody ~= nil and type(diceBody.dice) == "table" then
                        for _, die in ipairs(diceBody.dice) do
                            rows[#rows+1] = CreateDieRow(die, refresh)
                        end
                    end
                    if #rows == 0 then
                        rows[1] = gui.Label{
                            text = "No dice paired. Wake your dice and use Scan for Dice below.",
                            fontSize = 12,
                            width = "90%",
                            height = "auto",
                            color = "#aaaaaa",
                        }
                    end
                    m_diceList.children = rows
                end,
                error = function(_) end,
            }
        end)
    end

    m_statusLabel = gui.Label{
        text = "Bridge: ...",
        fontSize = 14,
        width = "100%",
        height = "auto",
        vmargin = 4,
    }

    m_diceList = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
    }

    -- Discovered-but-unpaired dice from the last scan, each with a Pair
    -- button. Pairing defaults to d10 (the Draw Steel workhorse); adjust
    -- with the row's size dropdown afterwards.
    local m_scanResults = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
    }

    local m_scanButton
    m_scanButton = gui.Button{
        text = "Scan for Dice",
        fontSize = 14,
        width = 140,
        height = 26,
        halign = "left",
        vmargin = 6,
        hover = gui.Tooltip("Searches for nearby GoDice for ~8 seconds. Wake your dice first (give them a shake)."),
        click = function(element)
            if not CGB.isEnabled() then return end
            m_scanButton.text = "Scanning..."
            m_scanButton.interactable = false
            net.Post{
                url = CGB.getBaseUrl() .. "/v1/scan",
                data = { timeout_s = 8 },
                timeout = 25,  -- the scan blocks server-side for ~8s
                success = function(result)
                    if resultPanel == nil or not resultPanel.valid then return end
                    m_scanButton.text = "Scan for Dice"
                    m_scanButton.interactable = true

                    local body = decodeBody(result)
                    local rows = {}
                    if body ~= nil and type(body.dice) == "table" then
                        for _, found in ipairs(body.dice) do
                            if not found.paired then
                                rows[#rows+1] = gui.Panel{
                                    flow = "horizontal",
                                    width = "100%",
                                    height = 26,
                                    vmargin = 2,
                                    gui.Label{
                                        text = string.format("%s (%s)", tostring(found.name), tostring(found.address)),
                                        fontSize = 12,
                                        width = "60%",
                                        height = "auto",
                                        halign = "left",
                                        valign = "center",
                                    },
                                    gui.Button{
                                        text = "Pair",
                                        fontSize = 12,
                                        width = 50,
                                        height = 22,
                                        valign = "center",
                                        click = function(btn)
                                            net.Post{
                                                url = CGB.getBaseUrl() .. "/v1/dice/pair",
                                                data = { address = found.address, type = "d10" },
                                                success = function(_)
                                                    if resultPanel ~= nil and resultPanel.valid then
                                                        m_scanResults.children = {}
                                                        refresh()
                                                    end
                                                end,
                                                error = function(_) end,
                                            }
                                        end,
                                    },
                                }
                            end
                        end
                    end
                    if #rows == 0 then
                        rows[1] = gui.Label{
                            text = "No new dice found. Make sure they are awake (shake them) and nearby.",
                            fontSize = 12,
                            width = "90%",
                            height = "auto",
                            color = "#aaaaaa",
                        }
                    end
                    m_scanResults.children = rows
                end,
                error = function(_)
                    if resultPanel == nil or not resultPanel.valid then return end
                    m_scanButton.text = "Scan for Dice"
                    m_scanButton.interactable = true
                    m_scanResults.children = {
                        gui.Label{
                            text = "Scan failed -- is the bridge running in BLE mode?",
                            fontSize = 12,
                            width = "90%",
                            height = "auto",
                            color = "#cc6666",
                        },
                    }
                end,
            }
        end,
    }

    local children = {}
    -- Standard settings-checkbox editor for the enable toggle, when the
    -- codex UI library is available (it always is in practice; guarded so
    -- the panel still works if the helper is renamed upstream).
    local createEditor = rawget(_G, "CreateSettingsEditor")
    if createEditor ~= nil then
        children[#children+1] = createEditor(SETTING_ENABLED)
    end
    children[#children+1] = m_statusLabel
    children[#children+1] = m_diceList
    children[#children+1] = m_scanButton
    children[#children+1] = m_scanResults

    resultPanel = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",

        thinkTime = 3,
        think = refresh,
        create = refresh,

        children = children,
    }

    return resultPanel
end

-- DockablePanel is defined by the DMHub Core UI mod, and code-mod load
-- order is not guaranteed -- if this mod loads first, registering
-- immediately would silently do nothing (and every code reload re-runs
-- this race, since unloading a mod purges its panels). Retry until the
-- registry exists.
local function registerDockablePanel()
    local dockablePanelLib = rawget(_G, "DockablePanel")
    if dockablePanelLib == nil or dockablePanelLib.Register == nil then
        dmhub.Schedule(0.5, registerDockablePanel)
        return
    end
    -- Register overwrites an existing panel with the same name, so running
    -- twice (Codex loads mod files twice per startup) is harmless.
    dockablePanelLib.Register{
        name = "Physical Dice",
        icon = "icons/standard/Icon_App_GameControls.png",
        vscroll = true,
        minHeight = 140,
        content = function()
            return CreatePhysicalDicePanel()
        end,
    }
end
registerDockablePanel()

----------------------------------------------------------------
-- Init
----------------------------------------------------------------
log("loaded; bridge=%s wait=%ds enabled=%s",
    CGB.getBaseUrl(), CGB.waitSeconds, tostring(CGB.isEnabled()))
registerHooks()

-- If the user left the checkbox on last session, bring the bridge up now.
-- EnsureRunning is idempotent, so the twice-per-startup file reload is fine.
-- announce=false: this runs before the session exists, and a boot-time bridge
-- message would be both crash-prone and noisy.
if CGB.isEnabled() then
    syncBridgeProcess(true, false)
end

end
