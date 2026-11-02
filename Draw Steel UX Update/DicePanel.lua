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

-- Content height of the panel: the dice strip, a hairline, and the last-roll line. The panel
-- is pinned to it (min == max) so the window never shows empty space under the dice.
local STRIP_HEIGHT = 96
local READOUT_HEIGHT = 30
local PANEL_HEIGHT = STRIP_HEIGHT + 1 + READOUT_HEIGHT

DockablePanel.Register{
	name = "Dice",
	icon = "ui-icons/dsdice/djordice-d10.png",
	notitle = true,
	vscroll = false,
    dmonly = false,
	minHeight = PANEL_HEIGHT,
	maxHeight = PANEL_HEIGHT,
	content = function()
		track("panel_open", {
			panel = "Dice",
			dailyLimit = 30,
		})
		return CreateDicePanel()
	end,
}

-- The panel's own rules. @tokens resolve through ThemeEngine.MergeTokens (see the panel root),
-- so the captions, seams and tier pips follow the user's color scheme.
local function BuildDicePanelStyles()
	return {

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

		-- Hairlines between the Power Roll tile and the small dice, and above the readout.
		{
			classes = {"diceSeam"},
			bgcolor = "@border",
			opacity = 0.6,
		},

		-- Tier pips in the readout: three dots, the first <tier> of them lit.
		{
			classes = {"diceTierPip"},
			bgcolor = "@border",
			cornerRadius = 3,
		},
		{
			classes = {"diceTierPip", "lit"},
			bgcolor = "@fgStrong",
		},
	}
end

CreateDicePanel = function()

	local amendableRoll = nil

	-- The last-roll line under the strip. Forward-declared so every die tile can report its
	-- finished roll to it (kind is "power", "d3", "d6", "d10" or "custom" for a mixed roll).
	local readoutPanel
	local function recordRoll(kind, rollInfo)
		if readoutPanel ~= nil and readoutPanel.valid and rollInfo ~= nil then
			readoutPanel:FireEvent("showRoll", kind, rollInfo)
		end
	end

	local diceStyle = dmhub.GetDiceStyling(dmhub.GetSettingValue("diceequipped"), dmhub.GetSettingValue("playercolor"))

	-- When a non-default dice set is equipped, draw each die as its real 3D model rendered
	-- off-screen (transparent, numberless) instead of the flat PNG icon. equipped/use3D are
	-- recomputed by the diceequipped/playercolor monitor below so the panel rebuilds on change.
	local equipped = dmhub.GetSettingValue("diceequipped")
	local use3D = equipped ~= nil and equipped ~= "" and equipped ~= "Default"

	-- params applies to whichever tile we build; params2D is merged over it for the flat-icon
	-- (Default set) path only. The two need different sizes: a 3D cage rests its die well inside
	-- the tile (see dicePreviewRestScale below), whereas the flat PNG fills the tile edge to edge,
	-- so the scale a cage wants blows the flat icon up past its cell.
	local CreateDice = function(faces, params, params2D)

		local selectedDie = nil
		local selectedDieFilled = nil
		local selectedNum = nil
		local selectedFaces = nil
		-- What recordRoll calls a roll from this tile ("power" for the 2d10 pair).
		local selectedKind = nil
		-- Which 3D die geometry this tile renders when use3D (d3 uses the d6 model; the d20
		-- "Power Roll" renders as the two-d10 pair). nil = fall back to the whitelabel default.
		local selectedGeo = nil

		if faces == 3 then
			selectedDie = "ui-icons/dsdice/djordice-d6.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d6-filled.png"
			selectedNum = 1
			selectedFaces = 3
			selectedKind = "d3"
			selectedGeo = "d6"
		elseif faces == 6 then
			selectedDie = "ui-icons/dsdice/djordice-d6.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d6-filled.png"
			selectedNum = 1
			selectedFaces = 6
			selectedKind = "d6"
			selectedGeo = "d6"
		elseif faces == 10 then
			selectedDie = "ui-icons/dsdice/djordice-d10.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-d10-filled.png"
			selectedNum = 1
			selectedFaces = 10
			selectedKind = "d10"
			selectedGeo = "d10"
		elseif faces == 20 then
			selectedDie = "ui-icons/dsdice/djordice-2d10.png"
			selectedDieFilled = "ui-icons/dsdice/djordice-2d10-filled.png"
			selectedNum = 2
			selectedFaces = 10
			selectedKind = "power"
			selectedGeo = "power"
		end

		-- 3D mode: replace the static #DiceIcon tile with a LIVE cage, like the shop's "try dice"
		-- (see MakeTryDiceCage in CodexShopScreen.lua). A real die, numbers showing, rests on the tile,
		-- spins on hover, and rolls seamlessly on click/drag as a real (chat, networked) roll. The
		-- tile's name is the caption under it (built by the panel), so nothing is drawn over the die.
		-- The non-3D (Default set) path below is unchanged.
		if use3D then
			-- Invisible-but-hittable cage filling the tile. The die anchors to its world centre.
			-- All engine calls are pcall-guarded so a Lua-only reload against an older binary
			-- degrades gracefully.
			-- gui.DicePreview is a dedicated dice-preview cage panel type. Fall back to a plain
			-- gui.Panel on an older binary (Lua-only reload) that predates it; the dice field/
			-- method calls below are already pcall-guarded so they no-op on the fallback.
			-- (gui is engine userdata, so index via pcall rather than rawget.)
			local diceCageCtor = gui.Panel
			pcall(function() diceCageCtor = gui.DicePreview or gui.Panel end)
			-- The cage stays FULL-TILE but is inert to the mouse: its rect is the
			-- resting-dice image area (DiceEmbeddedImage shows the cage's screen
			-- region of the dice RT, so shrinking it would clip the resting dice)
			-- and the dice anchor. The HIT box is the separate hitPanel sibling below.
			local cage = diceCageCtor{
				width = "100%",
				height = "100%",
				halign = "center",
				valign = "center",
				floating = true,
				interactable = false,
				bgimage = true,
				bgcolor = "white",
				styles = { gui.Style{ opacity = 0 } },
				data = { reseedPending = false },

				create = function(element)
					--the cage (see the cast after its constructor).
					---@cast element DicePreview
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
					-- Resting tiles show the bare die: no particle effects until the mouse is
					-- on them (and while they are dragged/thrown), then they are stripped again
					-- on mouse-off. Dice FX always composite over the whole UI, so a resting
					-- tile's effects would show through dialogs that cover the (virtual) die
					-- itself, and a row of idle tiles quietly emitting embers is just noise.
					-- Its own pcall so an older binary without the field keeps the tuning above.
					pcall(function()
						element.dicePreviewHoverFx = true
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
							element.dicePreviewRestSpacing = 0.58
							element.dicePreviewRestScale = 0.7
						end)
						-- Hovered, the pair grows to full size; 0.78 makes them overlap at that size.
						pcall(function() element.dicePreviewSpacing = 0.88 end)
					end
					element:FireEvent("seedDie")
				end,
				destroy = function(element)
					pcall(function() element:CancelDicePreviewRoll() end)
					pcall(function() element:SetAsDicePreviewPanel(false) end)
				end,

				-- Seed a resting die (face numbers showing) in the equipped set, armed so a click/drag throws it
				-- as a real roll. Unlike the shop we OMIT ["local"]/silent (the shop titlescreen has
				-- no chat/network) and amendable (each tile rolls standalone). Re-seed after the roll
				-- finishes or a too-weak drag cancels, so a fresh die is always resting here.
				seedDie = function(element)
					if not element.valid then
						return
					end
					element.data.reseedPending = false
					pcall(function() element:CancelDicePreviewRoll() end)
					dmhub.Roll{
						preview = true, previewPanel = element, hideNumbers = false,
						numDice = selectedNum, numFaces = selectedFaces, numKeep = 0,
						description = "Custom Roll",
						complete = function(rollInfo)
							recordRoll(selectedKind, rollInfo)
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
			}
			--a gui.DicePreview cage; only a pre-DicePreview binary builds a plain Panel, and every
			--DicePreview call on it is pcall-guarded.
			---@cast cage DicePreview

			-- The mouse-facing side of the cage: hover wobble + click/drag-to-roll,
			-- scoped to the cage's dice. The engine preview calls are made ON the
			-- cage (they are mouse/scope-based, so which panel received the input
			-- does not matter). Hovering fades the die's real numbers in
			-- (engine-side, keyed off the same mouseover state).
			local hitPanel = gui.Panel{
				width = "100%",
				height = "100%",
				halign = "center",
				valign = "center",
				floating = true,
				bgimage = true,
				bgcolor = "clear",
				draggable = true,
				dragMove = false,

				hover = function(element)
					pcall(function() cage:DicePreviewMouseEnter() end)
				end,
				dehover = function(element)
					pcall(function() cage:DicePreviewMouseLeave() end)
				end,
				dragging = function(element)
					pcall(function() cage:DicePreviewDragThink() end)
				end,
				drag = function(element)
					pcall(function() cage:DicePreviewDragEnd() end)
				end,
				click = function(element)
					pcall(function() cage:DicePreviewClick() end)
				end,
			}

			-- The visible tile is just a transparent container (the resting die is the cage's
			-- embedded dice image; hovered/rolling dice composite over the whole UI).
			-- saturation/brightness override the dimming baked into the "dice" style.
			local cageArgs = {
				classes = "dice",
				saturation = 1,
				brightness = 1,
				cage,
				hitPanel,
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

		-- Amended rolls mix dice from several tiles, so the readout labels them "custom".
		local function onComplete(kind)
			return function(rollInfo)
				recordRoll(kind, rollInfo)
			end
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
					complete = onComplete(selectedKind),
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
						complete = onComplete("custom"),
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
					complete = onComplete(selectedKind),
                }
            end,
		}

		-- The flat colored die outline only makes sense for the 2D icon; in 3D mode the model
		-- replaces it.
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

		if params2D ~= nil then
			for k,v in pairs(params2D) do
				args[k] = v
			end
		end

		local result = gui.Panel(args)
		return result
	end

	-- One tile of the strip: the die centred in a fixed-height well, its name underneath.
	-- Fixed wells keep every caption on one baseline whatever size each die is drawn at.
	local function DiceCell(width, die, captionText, bold)
		return gui.Panel{
			width = width,
			height = "100%",
			flow = "vertical",
			gui.Panel{
				width = "100%",
				height = STRIP_HEIGHT - 28,
				flow = "none",
				valign = "top",
				die,
			},
			gui.Label{
				classes = cond(bold, {"label", "sizeXs", "bold"}, {"label", "sizeXs", "fgMuted"}),
				width = "auto",
				height = "auto",
				halign = "center",
				valign = "top",
				text = captionText,
			},
		}
	end

	local function VerticalSeam()
		return gui.Panel{
			classes = {"diceSeam"},
			bgimage = true,
			width = 1,
			height = "60%",
			valign = "center",
		}
	end

	-- Tier pips for a Power Roll result; "lit" is toggled by showRoll.
	local tierPips = {}
	for i = 1, 3 do
		tierPips[i] = gui.Panel{
			classes = {"diceTierPip"},
			bgimage = true,
			width = 6,
			height = 6,
			valign = "center",
			rmargin = 3,
		}
	end

	local hintLabel = gui.Label{
		classes = {"label", "sizeXs", "fgMuted"},
		width = "auto",
		height = "auto",
		halign = "left",
		valign = "center",
		text = "Click a die to roll it. Drag to throw it.",
	}
	local lastLabel = gui.Label{
		classes = {"label", "sizeXxs", "fgMuted", "collapsed"},
		width = "auto",
		height = "auto",
		halign = "left",
		valign = "center",
		rmargin = 8,
		text = "LAST",
	}
	local totalLabel = gui.Label{
		classes = {"label", "sizeL", "bold", "collapsed"},
		width = "auto",
		height = "auto",
		halign = "left",
		valign = "center",
		rmargin = 8,
		text = "",
	}
	local tierPanel = gui.Panel{
		classes = {"collapsed"},
		width = "auto",
		height = "auto",
		flow = "horizontal",
		halign = "left",
		valign = "center",
		tierPips[1],
		tierPips[2],
		tierPips[3],
		gui.Label{
			classes = {"label", "sizeXs"},
			width = "auto",
			height = "auto",
			valign = "center",
			lmargin = 3,
			text = "",
			showTier = function(element, tier)
				element.text = string.format("Tier %d", tier)
			end,
		},
	}
	local detailLabel = gui.Label{
		classes = {"label", "sizeXs", "fgMuted", "collapsed"},
		width = "auto",
		height = "auto",
		halign = "right",
		valign = "center",
		text = "",
	}

	readoutPanel = gui.Panel{
		width = "100%",
		height = READOUT_HEIGHT,
		flow = "horizontal",
		hpad = 12,
		borderBox = true,
		hintLabel,
		lastLabel,
		totalLabel,
		tierPanel,
		detailLabel,

		-- Swap the hint for the result of the roll that just finished.
		showRoll = function(element, kind, rollInfo)
			local faces = {}
			pcall(function()
				for _, r in ipairs(rollInfo.rolls or {}) do
					if not r.dropped then
						faces[#faces+1] = tostring(r.result)
					end
				end
			end)

			local total = rollInfo.total
			if total == nil then
				return
			end

			hintLabel:SetClass("collapsed", true)
			lastLabel:SetClass("collapsed", false)
			totalLabel:SetClass("collapsed", false)
			detailLabel:SetClass("collapsed", false)
			totalLabel.text = tostring(math.tointeger(total) or total)

			-- Only a Power Roll has a tier; RollUtils is the codex's shared tier rule.
			local tier = nil
			if kind == "power" then
				pcall(function() tier = RollUtils.DiceResultToTier(rollInfo) end)
			end
			tierPanel:SetClass("collapsed", tier == nil)
			if tier ~= nil then
				for i = 1, 3 do
					tierPips[i]:SetClass("lit", i <= tier)
				end
				tierPanel:FireEventTree("showTier", tier)
			end

			if kind == "power" or kind == "custom" then
				detailLabel.text = table.concat(faces, " + ")
			else
				detailLabel.text = kind
			end
		end,
	}

    local resultPanel
	resultPanel = gui.Panel{

		width = "100%",
		height = "100%",
		flow = "vertical",
		styles = ThemeEngine.MergeTokens(BuildDicePanelStyles()),

		bgimage = "panels/square.png",
		bgcolor = "clear",

		multimonitor = {"privaterolls"},
		monitor = function(element)
			element:SetClassTree("gmonly", GetRollVisibility() == "dm")
			-- Re-seed the 3D cages so a director-visibility toggle takes effect on the very next
			-- roll (each resting die captured its dmonly at seed time).
			element:FireEventTree("requestReseed")
		end,

		rightClick = function(element)
			local entries = {}

			--a directorless game does not offer the Director-only toggle.
			if RollPrivacyAllowed() then
				entries[#entries+1] = {
					text = "Rolls Visible Only to Director",
					check = dmhub.GetSettingValue("privaterolls") == "dm",
					click = function()
						dmhub.SetSettingValue("privaterolls", cond(dmhub.GetSettingValue("privaterolls") == "dm", "visible", "dm"))
						element.popup = nil
					end,
				}
			end

			-- The dice sets this account owns, the same list as the Settings "Dice Set"
			-- dropdown. Picking one equips it; the strip's diceequipped monitor redraws the dice.
			local sets = {}
			pcall(function() sets = dice.GetAvailableDice() end)
			table.sort(sets, function(a,b) return tostring(a.text) < tostring(b.text) end)

			local current = dmhub.GetSettingValue("diceequipped")
			local setEntries = {}
			for _,set in ipairs(sets) do
				local setid = set.value
				setEntries[#setEntries+1] = {
					text = set.text,
					check = setid == current,
					click = function()
						dmhub.SetSettingValue("diceequipped", setid)
						element.popup = nil
					end,
				}
			end

			if #setEntries > 0 then
				entries[#entries+1] = {
					text = "Dice Set",
					submenu = setEntries,
				}
			end

			if #entries == 0 then
				return
			end

			element.popup = gui.ContextMenu{
				entries = entries,
			}
		end,

		-- The dice strip: four equal-height tiles, Power Roll first and wider. Rebuilt when the
		-- equipped dice set or player color changes; the readout below survives the rebuild.
		gui.Panel{

			width = "100%",
			height = STRIP_HEIGHT,
			flow = "horizontal",
			vpad = 6,
			borderBox = true,

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
						-- Wide tile: the resting pair is drawn only inside the tile's rect, so it must
						-- span both dice and the gap between them or their outer edges get cut off.
						DiceCell("34%-1", CreateDice(20, {uiscale = 1.35, width = 84}, {uiscale = 1.0, width = 60}), "POWER ROLL", true),
						VerticalSeam(),
						DiceCell("22%", CreateDice(3, {uiscale = 1.1}, {uiscale = 0.95}), "d3"),
						DiceCell("22%", CreateDice(6, {uiscale = 1.1}, {uiscale = 0.95}), "d6"),
						DiceCell("22%", CreateDice(10, {uiscale = 1.2}), "d10"),
					}
					resultPanel:SetClassTree("gmonly", GetRollVisibility() == "dm")

					-- The screen-bounds/spacing/rest-scale tuning is set PER-CAGE in each
					-- tile's cage create handler (dicePreviewScreenBounds / Spacing /
					-- RestScale in CreateDice above), not via the dice.SetPreview* globals:
					-- the dock coexists with the shop and the in-game roll dialog, and the
					-- globals leaked this panel's tuning into their cages.
				end,
			}
		},

		gui.Panel{
			classes = {"diceSeam"},
			bgimage = true,
			width = "100%",
			height = 1,
		},

		readoutPanel,
	}

	ThemeEngine.OnThemeChanged(mod, function()
		if resultPanel ~= nil and resultPanel.valid then
			resultPanel.styles = ThemeEngine.MergeTokens(BuildDicePanelStyles()) --[[@as StyleArgs[] ]]
		end
	end)

	resultPanel:SetClassTree("gmonly", GetRollVisibility() == "dm")

	return resultPanel

end

----------------------------------------------------------------
-- Physical Dice (Bluetooth dice) integration
----------------------------------------------------------------
do

--[[
================================================================
Physical Dice (GoDice + Pixels) - Codex integration
================================================================

Intercepts Codex roll dialogs and routes the dice through a local
HTTP service (the Python "Codex Dice Bridge"). The physical
dice (GoDice, Pixels) pass their face values to the engine via
rollArgs.forcedDice, 
and the engine resolves the original roll expression as if it had 
rolled those values itself, populating rollInfo.rolls, naturalRoll, 
nat1/nat20, total, tier, and firing the crit audio cue when appropriate.

PAIRED WITH: dice-bridge/ in the DMHub repo (Python). The HTTP
contract is documented in its README. Both must update together
when the contract changes.

USER SURFACE:
  - Settings panel ("General" section) provides the Physical Dice
    mode (Off / Bluetooth Dice / Manual Input), the bridge URL, and
    the bridge program path. These are the canonical configuration.
  - Bluetooth mode auto-starts the bridge process via
    dmhub.StartDiceBridge (engine-side DiceBridgeProcess); leaving it
    stops it. If the bridge dies mid-roll the mod falls back to a
    virtual roll rather than hanging the dialog.
  - Manual Input mode needs no bridge: the player rolls real dice and
    types each face into a box (runInputRoll). The typed faces travel
    the same forcedDice path as Bluetooth faces.
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

local SETTING_MODE     = "externaldice:mode"
local SETTING_ENABLED  = "externaldice:enabled"  -- legacy checkbox, migrated to SETTING_MODE
local SETTING_BRIDGE   = "externaldice:bridgeurl"
local SETTING_BRIDGEPATH = "externaldice:bridgepath"
local DEFAULT_BRIDGE   = "http://127.0.0.1:17211"

-- "off", "bluetooth" or "input". Any other saved value counts as off.
local function getPhysicalDiceMode()
    local mode = dmhub.GetSettingValue(SETTING_MODE)
    if mode ~= "bluetooth" and mode ~= "input" then return "off" end
    return mode
end

-- True only when the bridge should be running.
local function isBluetoothMode()
    return getPhysicalDiceMode() == "bluetooth"
end

-- Start/stop the bridge process alongside the checkbox. The engine
-- resolves the executable itself (the bridgepath preference below, or
-- dice-bridge.exe next to the player executable) so this API can't be
-- pointed at an arbitrary binary. Guarded for engine builds that predate
-- dmhub.StartDiceBridge. Lifecycle feedback goes to the dev console, not
-- chat (the Physical Dice panel's status line is the user-facing surface).
local function syncBridgeProcess(enabled)
    -- A settings toggle is the user saying "try again": clear the
    -- heartbeat loop's failed-start pause.
    CodexGoDiceBridge.bridgeStartFailed = false
    if enabled then
        if dmhub.StartDiceBridge ~= nil then
            if dmhub.StartDiceBridge() then
                print("CGB: dice bridge started")
            else
                CodexGoDiceBridge.bridgeStartFailed = true
                print("CGB: could not start the dice bridge -- set 'Physical Dice Bridge Program' in settings to the bridge executable, or start it manually")
            end
        end
    else
        if dmhub.StopDiceBridge ~= nil then
            dmhub.StopDiceBridge()
        end
        print("CGB: dice bridge stopped")
    end
end

local g_externalDiceMode = setting{
    id = SETTING_MODE,
    description = "Physical Dice",
    help = "Roll real dice instead of virtual ones. Bluetooth reads GoDice or Pixels dice through the dice bridge, which starts automatically. Manual Input asks you to type each die's result; your bonuses are still added for you.",
    storage = "preference",
    section = "General",
    default = "off",
    editor = "dropdown",
    enum = {
        { value = "off", text = "Off" },
        { value = "bluetooth", text = "Bluetooth Dice" },
        { value = "input", text = "Manual Input" },
    },
    onchange = function()
        syncBridgeProcess(isBluetoothMode())
    end,
}

-- The old on/off checkbox. No editor, so it is hidden; it stays registered
-- only so the Init migration can read what a user saved before the mode
-- dropdown existed.
local g_externalDiceEnabled = setting{
    id = SETTING_ENABLED,
    storage = "preference",
    default = false,
}

-- Where the bridge executable lives. Read by the ENGINE (DiceBridgeProcess),
-- not by this mod. Empty means "dice-bridge.exe next to the player
-- executable"; during development point it at your built bridge.exe.
local g_externalDiceBridgePath = setting{
    id = SETTING_BRIDGEPATH,
    description = "Physical Dice Bridge Program",
    help = "Path to the dice bridge executable. Leave empty to use dice-bridge.exe next to the Codex executable.",
    characterLimit = 400,
    editor = "input",
    storage = "preference",
    section = "General",
    default = "",
    visible = isBluetoothMode,
    monitorVisible = {SETTING_MODE},
}

local g_externalDiceBridgeUrl = setting{
    id = SETTING_BRIDGE,
    description = "Physical Dice Bridge URL",
    help = "Where the game looks for the dice bridge. Leave as "
        .. DEFAULT_BRIDGE .. " -- the auto-started bridge always runs there. "
        .. "Only change this if you run the bridge manually on another port.",
    characterLimit = 200,
    editor = "input",
    storage = "preference",
    section = "General",
    default = DEFAULT_BRIDGE,
    visible = isBluetoothMode,
    monitorVisible = {SETTING_MODE},
}

----------------------------------------------------------------
-- Module state
----------------------------------------------------------------

-- Use rawget on _G so Codex's strict-globals metatable doesn't error
-- on the read when CodexGoDiceBridge isn't initialized yet (which it
-- won't be on the first of Codex's two load passes). Same trick is
-- used below for RollDialog / Commands / chat / json: any global we
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

CGB.getMode = getPhysicalDiceMode
CGB.isBluetooth = isBluetoothMode

-- True in either physical mode: rolls get intercepted.
function CGB.isEnabled()
    return getPhysicalDiceMode() ~= "off"
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

-- The few rules the stock theme classes don't cover. Colors are @ tokens so
-- the notices follow the user's color scheme.
local function BuildDiceNoticeStyles()
    return {
        {
            selectors = {"diceNoticeSeam"},
            width = "90%",
            height = 1,
            halign = "center",
            bgimage = true,
            bgcolor = "@border",
            opacity = 0.35,
        },
        {
            selectors = {"input", "diceEntryInvalid"},
            color = "@danger",
            borderColor = "@danger",
            priority = 5,
        },
    }
end

-- Recolor an open notice when the user switches theme, scheme or font size.
-- Subscribed on first use, not at load: ThemeEngine may not exist yet while
-- this file loads.
local m_themeSubscribed = false
local function subscribeNoticeTheme()
    if m_themeSubscribed then return end
    m_themeSubscribed = true
    ThemeEngine.OnThemeChanged(mod, function()
        if m_waitingNotice ~= nil and m_waitingNotice.valid then
            m_waitingNotice.styles = ThemeEngine.MergeStyles(BuildDiceNoticeStyles())
        end
    end)
end

-- Mounts a centered, draggable notice box on the hud, replacing any
-- current one. Sizes are in sp so the box grows with the Font Size setting.
-- Returns false when there is no hud to show it on.
local function mountNotice(width, children)
    destroyWaitingNotice()

    local hudLib = rawget(_G, "GameHud")
    local hud = hudLib and hudLib.instance
    if hud == nil then return false end
    -- dialog.sheet is the screen-space hud root; MainDialogPanel is NOT
    -- screen-anchored (a panel parented there renders off the bottom edge).
    local parent = hud.dialog and hud.dialog.sheet
    if parent == nil and hud.MainDialogPanel ~= nil then
        parent = hud:MainDialogPanel()
    end
    if parent == nil then return false end

    subscribeNoticeTheme()
    m_waitingNotice = gui.Panel{
        styles = ThemeEngine.MergeStyles(BuildDiceNoticeStyles()),
        classes = {"framedPanel"},
        floating = true,
        halign = "center",
        valign = "center",
        width = width,
        height = "auto",
        flow = "vertical",
        pad = 20,
        borderBox = true,
        draggable = true,
        drag = function(element)
            element.x = element.xdrag
            element.y = element.ydrag
        end,
        children = children,
    }

    parent:AddChild(m_waitingNotice)
    return true
end

local function createUseVirtualButton(onUseVirtual)
    return gui.Button{
        classes = {"sizeM"},
        text = "Use Virtual Dice",
        halign = "center",
        click = function(element)
            onUseVirtual()
        end,
    }
end

local function showWaitingNotice(onUseVirtual)
    mountNotice("340sp", {
        gui.Label{
            classes = {"sizeM"},
            text = "Waiting for physical dice...",
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            bmargin = 12,
        },
        createUseVirtualButton(onUseVirtual),
    })
end

-- Manual Input box: one input per die, each 1..faces. Confirm stays
-- disabled until every die is valid; Enter jumps to the next empty input,
-- or confirms when all are filled.
-- Returns false when there is no hud to show it on.
local function showInputNotice(diceList, onSubmit, onUseVirtual)
    local m_inputs = {}
    local m_rollButton
    local m_totalLabel

    local function readFace(index)
        local sides = tonumber(string.match(diceList[index], "d(%d+)"))
        local value = tonumber(m_inputs[index].text)
        if value == nil or value ~= math.floor(value) or value < 1 or value > sides then
            return nil, sides
        end
        return value, sides
    end

    local function refreshState()
        local total = 0
        local allValid = true
        for i = 1, #m_inputs do
            local value = readFace(i)
            local hasText = m_inputs[i].text ~= ""
            -- Red only for a wrong entry, not for a box not filled in yet.
            m_inputs[i]:SetClass("diceEntryInvalid", hasText and value == nil)
            if value == nil then
                allValid = false
            else
                total = total + value
            end
        end
        m_rollButton.interactable = allValid
        m_rollButton:SetClass("disabled", not allValid)
        m_totalLabel.text = allValid and string.format("Natural roll: %d", total) or ""
        return allValid
    end

    local function trySubmit()
        if not refreshState() then return end
        local forcedDice = {}
        for i = 1, #m_inputs do
            local value, sides = readFace(i)
            forcedDice[#forcedDice+1] = { numFaces = sides, result = value }
        end
        onSubmit(forcedDice)
    end

    local dieColumns = {}
    for i, dieType in ipairs(diceList) do
        local sides = string.match(dieType, "d(%d+)")
        m_inputs[i] = gui.Input{
            classes = {"bordered", "sizeXl"},
            width = "40sp",
            height = "40sp",
            halign = "center",
            textAlignment = "center",
            numeric = true,
            characterLimit = #sides,
            selectAllOnFocus = true,
            placeholderText = "-",
            text = "",
            edit = function(element)
                refreshState()
            end,
            submit = function(element)
                if refreshState() then
                    trySubmit()
                    return
                end
                for j = 1, #m_inputs do
                    if readFace(j) == nil then
                        gui.SetFocus(m_inputs[j])
                        return
                    end
                end
            end,
        }
        dieColumns[i] = gui.Panel{
            flow = "vertical",
            width = "72sp",
            height = "auto",
            hmargin = 8,
            gui.Label{
                classes = {"sizeXs", "fgMuted"},
                text = dieType,
                width = "100%",
                height = "auto",
                textAlignment = "center",
                bmargin = 4,
            },
            m_inputs[i],
        }
    end

    m_totalLabel = gui.Label{
        classes = {"sizeS", "fgMuted"},
        text = "",
        width = "100%",
        height = "22sp",
        textAlignment = "center",
        vmargin = 10,
    }

    m_rollButton = gui.Button{
        classes = {"sizeL", "disabled"},
        text = "Confirm",
        halign = "center",
        interactable = false,
        click = function(element)
            trySubmit()
        end,
    }

    local shown = mountNotice(string.format("%dsp", math.max(400, #diceList * 88 + 56)), {
        gui.Label{
            classes = {"sizeL", "bold"},
            text = "Enter Dice Results",
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
        },
        gui.Label{
            classes = {"sizeS", "fgMuted"},
            text = "Enter just the dice. Your bonuses are added for you.",
            width = "100%",
            height = "auto",
            halign = "center",
            textAlignment = "center",
            tmargin = 6,
        },
        gui.Panel{
            flow = "horizontal",
            width = "auto",
            height = "auto",
            halign = "center",
            tmargin = 18,
            children = dieColumns,
        },
        m_totalLabel,
        m_rollButton,
        -- The divider keeps Use Virtual Dice from reading as a Confirm twin.
        gui.Panel{
            classes = {"diceNoticeSeam"},
            tmargin = 20,
            bmargin = 12,
        },
        createUseVirtualButton(onUseVirtual),
    })

    if shown then
        -- Focus a frame later: a just-added input does not take focus yet.
        dmhub.Schedule(0.01, function()
            if mod.unloaded then return end
            if m_inputs[1] ~= nil and m_inputs[1].valid then
                gui.SetFocus(m_inputs[1])
            end
        end)
    end
    return shown
end

----------------------------------------------------------------
-- Roll-string parsing: dice list extraction only
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

-- A roll must complete exactly once, or its dialog hangs. finish(fn) runs fn
-- only on the first call and closes the notice; isFinished() lets late async
-- replies see that the roll is already done.
local function makeFinisher()
    local finished = false
    local function finish(fn)
        if finished then return end
        finished = true
        CGB.activeCancel = nil
        destroyWaitingNotice()
        fn()
    end
    local function isFinished()
        return finished
    end
    return finish, isFinished
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
    local finish, isFinished = makeFinisher()

    local function fallbackToVirtual(reason)
        finish(function()
            log("falling back to virtual roll: %s", tostring(reason))
            local chatLib = rawget(_G, "chat")
            if chatLib and chatLib.Send then
                chatLib.Send("Physical dice: " .. tostring(reason) .. " -- rolling virtually.")
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
                if isFinished() then
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

-- Manual Input counterpart of runBridgeRoll, with the same callback
-- contract: the typed faces go to opts.onForced, so the virtual dice still
-- tumble and land on them. No timeout: the player takes as long as they need.
local function runInputRoll(diceList, opts)
    -- A new box replaces any open one, and the old box's roll could then never
    -- finish. Roll that one virtually first so its dialog does not hang.
    if CGB.rollPendingInputVirtually ~= nil then
        CGB.rollPendingInputVirtually()
    end

    local finishRoll = makeFinisher()
    local function finish(fn)
        finishRoll(function()
            CGB.rollPendingInputVirtually = nil
            fn()
        end)
    end

    CGB.rollPendingInputVirtually = function()
        finish(function()
            log("another roll opened a dice entry box; rolling this one virtually")
            opts.onVirtual()
        end)
    end

    -- Dialog cancelled: close the entry box and roll nothing.
    CGB.activeCancel = function()
        finish(function() log("roll dialog cancelled; closing dice entry") end)
    end

    local shown = showInputNotice(diceList,
        function(forcedDice)
            log("manual input forcedDice=%d", #forcedDice)
            finish(function() opts.onForced(forcedDice) end)
        end,
        function()
            finish(function()
                log("user chose virtual dice instead of manual input")
                opts.onVirtual()
            end)
        end)

    -- No hud to type into would hang the dialog, so roll virtually.
    if not shown then
        finish(function()
            log("no hud for the dice entry box; rolling virtually")
            opts.onVirtual()
        end)
    end
end

-- Both modes share one callback contract, so the hooks never need to know
-- which one is on.
local function runPhysicalRoll(diceList, opts)
    if CGB.getMode() == "input" then
        runInputRoll(diceList, opts)
    else
        runBridgeRoll(diceList, opts)
    end
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

    runPhysicalRoll(diceList, {
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

    runPhysicalRoll(diceList, {
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
                "Dice bridge: ok=%s version=%s dice=%d pending=%d (mode=%s url=%s)",
                tostring(body.ok),
                tostring(body.version),
                body.dice_count or 0,
                body.pending_rolls or 0,
                CGB.getMode(),
                CGB.getBaseUrl()))
            local hooks = CGB.codexDeclaredHooks or {}
            for name, present in pairs(hooks) do
                chat.Send(string.format("  hook %s: %s", name, present and "registered" or "missing"))
            end
        else
            chat.Send("Dice bridge: unreachable (" .. tostring(body) .. ")")
        end
    end)
end

local commandsLib = rawget(_G, "Commands")
if commandsLib and commandsLib.RegisterMacro then
    commandsLib.RegisterMacro{
        name = "godice",
        summary = "control the dice bridge integration",
        doc = "Usage: /godice [status|on|off|debug on|debug off|probe|register]\n"
            .. "  status     - show bridge health and registered hooks\n"
            .. "  on / off   - set Physical Dice to Bluetooth / Off (writes the preference)\n"
            .. "  debug on/off - toggle dump of rollArgs on each intercept\n"
            .. "  probe      - check live state of RollDialog.OnBeforeRoll\n"
            .. "  register   - re-register hooks",
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
                dmhub.SetSettingValue(SETTING_MODE, "bluetooth")
                chat.Send("Dice bridge: ENABLED (preference saved)")
            elseif sub == "off" then
                dmhub.SetSettingValue(SETTING_MODE, "off")
                chat.Send("Dice bridge: DISABLED (preference saved)")
            elseif sub == "debug" then
                CGB.debugDump = (parts[2] == "on")
                chat.Send("Dice bridge debug dump: " .. (CGB.debugDump and "on" or "off"))
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
    if CGB.isBluetooth() then
        CGB.sendHeartbeat()
        -- Self-heal: if the bridge died (crash, idle timeout) while the
        -- feature is on, bring it back rather than waiting for the user
        -- to toggle the checkbox. But when a start attempt FAILS (usually
        -- no bridge executable in this install), stop trying: retrying
        -- every tick can never succeed and floods the log. Toggling the
        -- setting clears the pause.
        if dmhub.IsDiceBridgeRunning ~= nil and dmhub.StartDiceBridge ~= nil
                and not dmhub.IsDiceBridgeRunning()
                and not CGB.bridgeStartFailed then
            log("bridge process not running; restarting")
            if not dmhub.StartDiceBridge() then
                CGB.bridgeStartFailed = true
                log("bridge failed to start (no executable?); pausing auto-restart until Use Physical Dice is toggled")
            end
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
    local isPixels = die.vendor == "pixels"
    -- Pixels: the physical die type as self-reported over BLE. `die.type`
    -- is what it plays as -- a pixels d20 can play as a d10 (the bridge
    -- folds 11..20 onto 1..10), since Pixels only make d20s.
    local hwType = die.hw_type
    if hwType == "" then hwType = nil end
    local folded = isPixels and hwType ~= nil and hwType ~= die.type
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

        -- Connection dot; hover for the die's details (brand, size, MAC).
        gui.Panel{
            width = 12,
            height = 12,
            halign = "left",
            valign = "center",
            hmargin = 4,
            bgimage = "panels/square.png",
            bgcolor = connected and "#40c040" or "#707070",
            cornerRadius = 6,
            hover = gui.Tooltip(string.format("%s %s\n%s",
                isPixels and "Pixels" or "GoDice",
                folded and string.format("%s played as %s", tostring(hwType), tostring(die.type))
                       or tostring(die.type),
                tostring(die.id))),
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

        -- Die size. GoDice do not self-report which shell is snapped on,
        -- so it's a free user declaration (full dropdown; changing it saves
        -- to the bridge config and rebinds the connection). Pixels report
        -- their own type over BLE -- the hardware is authoritative, so
        -- there's no free choice; but a pixels d20 can PLAY AS a d10 (the
        -- bridge folds 11..20 onto 1..10), so d20s get a two-option
        -- dropdown and everything else just a spacer.
        (isPixels and hwType == "d20") and gui.Dropdown{
            width = 64,
            height = 22,
            fontSize = 12,
            valign = "center",
            options = {
                {id = "d20", text = "d20"},
                {id = "d10", text = "as d10"},
            },
            idChosen = tostring(die.type),
            change = function(element)
                ---@cast element Dropdown
                net.Post{
                    url = CGB.getBaseUrl() .. "/v1/dice/" .. die.id .. "/type",
                    data = { type = element.idChosen },
                    success = function(_) onChanged() end,
                    error = function(_) end,
                }
            end,
        }
        or isPixels and gui.Panel{ width = 64, height = 22, valign = "center" }
        or gui.Dropdown{
            width = 64,
            height = 22,
            fontSize = 12,
            valign = "center",
            options = DIE_TYPE_OPTIONS,
            idChosen = tostring(die.type),
            change = function(element)
                ---@cast element Dropdown
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
    local m_scanResults
    local m_scanButton

    local resultPanel

    local function refresh()
        -- Scanning and the paired-dice list are Bluetooth-only.
        m_scanButton:SetClass("hidden", not CGB.isBluetooth())
        local mode = CGB.getMode()
        if mode ~= "bluetooth" then
            if mode == "input" then
                m_statusLabel.text = "Manual Input: when you roll, you'll be asked to type each die's result."
            else
                m_statusLabel.text = "Physical dice are disabled."
            end
            m_diceList.children = {}
            m_scanResults.children = {}
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
    -- button. GoDice pair as d10 by default (the Draw Steel workhorse;
    -- adjust with the row's size dropdown afterwards). Pixels advertise
    -- their die type, so they pair as exactly what they are.
    m_scanResults = gui.Panel{
        flow = "vertical",
        width = "100%",
        height = "auto",
    }

    m_scanButton = gui.Button{
        text = "Scan for Dice",
        fontSize = 14,
        width = 140,
        height = 26,
        halign = "left",
        vmargin = 6,
        hover = gui.Tooltip("Searches for nearby GoDice and Pixels dice for ~8 seconds. Wake your dice first (give them a shake)."),
        click = function(element)
            if not CGB.isBluetooth() then return end
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
                                local isPixels = found.vendor == "pixels"
                                local label
                                if isPixels then
                                    -- Pixels self-report their type in the ad,
                                    -- e.g. Pixel d20 'Fudge'.
                                    label = string.format("Pixel %s '%s'", tostring(found.type or "?"), tostring(found.name))
                                else
                                    label = string.format("%s (%s)", tostring(found.name), tostring(found.address))
                                end
                                rows[#rows+1] = gui.Panel{
                                    flow = "horizontal",
                                    width = "100%",
                                    height = 26,
                                    vmargin = 2,
                                    gui.Label{
                                        text = label,
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
                                                data = {
                                                    address = found.address,
                                                    vendor = found.vendor or "godice",
                                                    type = isPixels and found.type or "d10",
                                                    name = isPixels and found.name or nil,
                                                },
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
        children[#children+1] = createEditor(SETTING_MODE)
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
        icon = "phosphor/dice-six.png",
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
-- One-time move from the old checkbox: anyone who had it ticked was using
-- Bluetooth dice. Runs here, not at the setting, because the mode's
-- onchange needs CGB to exist.
if dmhub.GetSettingValue(SETTING_ENABLED) == true then
    dmhub.SetSettingValue(SETTING_ENABLED, false)
    dmhub.SetSettingValue(SETTING_MODE, "bluetooth")
end

log("loaded; bridge=%s wait=%ds mode=%s",
    CGB.getBaseUrl(), CGB.waitSeconds, CGB.getMode())
registerHooks()

-- If Bluetooth mode was left on last session, bring the bridge up now.
-- EnsureRunning is idempotent, so the twice-per-startup file reload is fine.
if CGB.isBluetooth() then
    syncBridgeProcess(true)
end

end
