local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityFallBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'fall',
	text = 'Fall',
	createBehavior = function()
		return ActivatedAbilityFallBehavior.new{
		}
	end
}

ActivatedAbilityFallBehavior.summary = 'Fall'

function ActivatedAbilityFallBehavior:Cast(ability, casterToken, targets, options)
    for _, target in ipairs(targets) do
        if target.token ~= nil then
            target.token:TryFall()
        end
    end
end

function ActivatedAbilityFallBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)
	return result
end

--- @class ActivatedAbilityDigVerticalBehavior:ActivatedAbilityBehavior
--- The Dig maneuver's movement: the caster chooses a purely vertical distance
--- (straight up or down through the ground) up to its size, then moves there.
--- Unlike forced movement it never moves horizontally and never rises above
--- ground level (floor altitude 0). The distance is chosen with +/- buttons and
--- a Confirm button rather than by clicking the map.
RegisterGameType("ActivatedAbilityDigVerticalBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType
{
	id = 'dig_vertical',
	text = 'Dig Vertical Movement',
	createBehavior = function()
		return ActivatedAbilityDigVerticalBehavior.new{
		}
	end
}

ActivatedAbilityDigVerticalBehavior.summary = 'Dig Vertical Movement'

--Maximum vertical distance (in squares) the creature may move, as a GoblinScript
--formula evaluated against the caster. Defaults to the creature's size; set
--higher or lower for special dig abilities.
ActivatedAbilityDigVerticalBehavior.distance = "Tile Size"

local function DigVerticalDescribe(d)
	if d < 0 then
		return string.format("Down %d square%s", -d, cond(-d == 1, "", "s"))
	elseif d > 0 then
		return string.format("Up %d square%s", d, cond(d == 1, "", "s"))
	end
	return "No movement"
end

function ActivatedAbilityDigVerticalBehavior:Cast(ability, casterToken, targets, options)
	--Maximum vertical distance (in squares), from the GoblinScript distance
	--formula (defaults to the creature's size).
	local distanceFormula = self:try_get("distance", "Tile Size")
	local maxDist = math.floor(tonumber(dmhub.EvalGoblinScript(distanceFormula, casterToken.properties:LookupSymbol(options.symbols or {}), string.format("Vertical dig distance for %s", ability.name))) or 0)
	if maxDist < 0 then
		maxDist = 0
	end

	--Down up to maxDist (digging into the ground). Up is capped at the standable
	--surface above the creature's own column, so the player can never pick a height
	--the creature can't actually reach (which would otherwise confirm and do
	--nothing). On flat ground that surface is the ground itself -- a creature on the
	--surface can't rise at all -- while a solid column such as a tower puts the
	--surface higher and lets the creature dig further up. Altitudes are whole tiles.
	local curAlt = casterToken.floorAltitude
	local surfaceAltitude = casterToken.loc.withGroundAltitude.altitude
	local maxUp = math.max(0, math.floor(surfaceAltitude - casterToken.altitude))
	local deltaMin = -maxDist
	local deltaMax = math.min(maxDist, maxUp)

	local chosen = math.clamp(0, deltaMin, deltaMax)

	local finished = false
	local canceled = false

	local valueLabel
	local plusButton
	local minusButton

	local Refresh = function()
		if valueLabel ~= nil then
			valueLabel.text = DigVerticalDescribe(chosen)
		end
		if plusButton ~= nil then
			plusButton:SetClass("disabled", chosen >= deltaMax)
		end
		if minusButton ~= nil then
			minusButton:SetClass("disabled", chosen <= deltaMin)
		end
	end

	--Match the power-roll / ability panel's visual language: pull live theme
	--colors so the dialog reads as part of the same UI rather than a foreign
	--popup, and dock it on the right (like the power-roll menu) so it does not
	--cover the centre of the battlemap. The modal overlay is transparent, so the
	--map stays visible behind it.
	local C_bg = ThemeEngine.ResolveTokens("@bg")
	local C_bgAlt = ThemeEngine.ResolveTokens("@bgAlt")
	local C_fg = ThemeEngine.ResolveTokens("@fg")
	local C_fgMuted = ThemeEngine.ResolveTokens("@fgMuted")
	local C_accent = ThemeEngine.ResolveTokens("@accent")

	local stepStyles = {
		{
			selectors = {"dig-step"},
			width = 44,
			height = 44,
			bgimage = "panels/square.png",
			bgcolor = C_bg,
			border = 1,
			borderColor = C_accent,
			cornerRadius = 4,
			halign = "center",
			valign = "center",
			fontFace = "Berling",
			fontSize = 30,
			color = C_fg,
			textAlignment = "center",
		},
		{
			selectors = {"dig-step", "hover"},
			brightness = 1.4,
			transitionTime = 0.1,
		},
		{
			selectors = {"dig-step", "disabled"},
			brightness = 0.45,
			borderColor = C_fgMuted,
		},
	}

	minusButton = gui.Label{
		classes = {"dig-step"},
		text = "-",
		press = function()
			if chosen > deltaMin then
				chosen = math.max(deltaMin, chosen - 1)
				Refresh()
			end
		end,
	}

	plusButton = gui.Label{
		classes = {"dig-step"},
		text = "+",
		press = function()
			if chosen < deltaMax then
				chosen = math.min(deltaMax, chosen + 1)
				Refresh()
			end
		end,
	}

	valueLabel = gui.Label{
		width = 150,
		height = "auto",
		halign = "center",
		valign = "center",
		fontFace = "Berling",
		fontSize = 22,
		color = C_fg,
		textAlignment = "center",
		text = DigVerticalDescribe(chosen),
	}

	--Dock to the LEFT of the right-hand dock (which holds the ability/power-roll
	--panel) so the picker sits over the map and never covers the dock. The dock is
	--user-resizable, so read its live width rather than using a fixed margin, and
	--keep it in sync via think in case the dock is resized while the picker is open.
	local DOCK_GAP = 14
	local function CurrentDockInset()
		--Wrapped so a torn-down dock (whose userdata can throw on index during
		--teardown) can never break the think tick; fall back to just the gap.
		local ok, inset = pcall(function()
			local d = rawget(gamehud, "rightDock")
			if d ~= nil and d.valid and (not d:HasClass("offscreen")) then
				return (d.renderedWidth or 0) + DOCK_GAP
			end
			return DOCK_GAP
		end)
		if ok and type(inset) == "number" then
			return inset
		end
		return DOCK_GAP
	end

	--Track the applied inset in a local: the panel's rmargin is settable but not
	--readable (reading it errors), so we compare against this instead of the element.
	local lastInset = CurrentDockInset()

	local panel
	panel = gui.Panel{
		classes = {"dig-modal"},
		width = 340,
		height = "auto",
		halign = "right",
		valign = "center",
		rmargin = lastInset,
		thinkTime = 0.25,
		think = function(element)
			--Fully guarded: if a Lua reload ever orphans this dialog while it is
			--open, the leftover panel's think keeps firing against a torn-down
			--element. The pcall makes that a silent no-op instead of log spam.
			pcall(function()
				local inset = CurrentDockInset()
				if inset ~= lastInset then
					lastInset = inset
					element.rmargin = inset
				end
			end)
		end,
		flow = "vertical",
		bgimage = "panels/square.png",
		bgcolor = C_bgAlt,
		border = 2,
		borderColor = C_accent,
		cornerRadius = 6,
		pad = 18,
		borderBox = true,
		styles = stepStyles,

		gui.Label{
			width = "100%",
			height = "auto",
			halign = "center",
			fontFace = "Newzald",
			fontWeight = "black",
			fontSize = 20,
			color = C_fg,
			textAlignment = "center",
			text = "Choose vertical movement distance:",
		},

		gui.Label{
			width = "100%",
			height = "auto",
			halign = "center",
			tmargin = 6,
			fontFace = "Berling",
			fontSize = 13,
			color = C_fgMuted,
			textAlignment = "center",
			text = "Move straight up or down through the ground, up to your size.",
		},

		gui.Panel{
			width = "auto",
			height = "auto",
			halign = "center",
			valign = "center",
			flow = "horizontal",
			tmargin = 14,
			bmargin = 14,
			minusButton,
			valueLabel,
			plusButton,
		},

		gui.Panel{
			width = "100%",
			height = "auto",
			halign = "center",
			flow = "horizontal",

			gui.PrettyButton{
				text = "Confirm",
				style = {
					width = 130,
					height = 42,
					rmargin = 8,
					valign = "center",
				},
				events = {
					click = function()
						finished = true
						gui.CloseModal()
					end,
				},
			},

			gui.PrettyButton{
				text = "Cancel",
				style = {
					width = 130,
					height = 42,
					valign = "center",
				},
				events = {
					click = function()
						finished = true
						canceled = true
						gui.CloseModal()
					end,
				},
			},
		},

		escapeActivates = true,
		escapePriority = EscapePriority.EXIT_MODAL_DIALOG,
		escape = function()
			finished = true
			canceled = true
			gui.CloseModal()
		end,
	}

	Refresh()

	gui.ShowModal(panel)

	while not finished do
		coroutine.yield(0.1)
	end

	if canceled or chosen == 0 or not casterToken.valid then
		return
	end

	local newAlt = curAlt + chosen

	--Burrow for the move itself so the creature can travel through solid ground in
	--either direction (a walker can't move through the ground). MoveVertical only
	--relocates the creature where that is actually possible; it won't move a
	--burrower up into open air.
	local origMoveType = casterToken.properties:CurrentMoveType()
	local beforeAltitude = casterToken.altitude
	if casterToken.properties:CanBurrow() then
		casterToken.properties:SetAndUploadCurrentMoveType("burrow")
	end

	casterToken:MoveVertical(newAlt)

	if not casterToken.valid then
		return
	end

	--If nothing actually moved (e.g. the creature tried to dig up where there was
	--nothing to dig through), restore its move type and don't spend the maneuver.
	if casterToken.altitude == beforeAltitude then
		casterToken.properties:SetAndUploadCurrentMoveType(origMoveType)
		return
	end

	--Grabbed creatures are dragged along automatically: the engine moves any
	--creature this one is grabbing to follow a vertical MoveVertical (verified --
	--the grabbed creature snaps to the grabber's new altitude as a move, no
	--teleport). So Dig does NOT move them itself; doing so double-moved them.

	--Match the move type to where the creature ended up: still burrowing while
	--below a surface, walking once standing on one. floorAltitude is 0 on a
	--standable surface (including elevated terrain such as a tower top) and
	--negative below ground.
	if casterToken.floorAltitude < 0 then
		casterToken.properties:SetAndUploadCurrentMoveType("burrow")
	else
		casterToken.properties:SetAndUploadCurrentMoveType("walk")
	end

	ability:CommitToPaying(casterToken, options)
end

function ActivatedAbilityDigVerticalBehavior:EditorItems(parentPanel)
	local result = {}
	self:ApplyToEditor(parentPanel, result)
	self:FilterEditor(parentPanel, result)

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = {"formLabel"},
			text = "Max Vertical Distance:",
		},
		gui.GoblinScriptInput{
			classes = {"formInput"},
			value = self:try_get("distance", "Tile Size"),
			change = function(element)
				self.distance = element.value
			end,
			documentation = {
				help = "The maximum distance, in squares, the creature may move straight up or down when it uses this ability. Defaults to the creature's size.",
				output = "number",
				subject = creature.helpSymbols,
				subjectDescription = "The creature using the ability",
				examples = {
					{ script = "Tile Size", text = "Move up to a number of squares equal to the creature's size (the default)." },
					{ script = "Tile Size + 2", text = "Move further than normal -- the creature's size plus two squares." },
					{ script = "1", text = "Always allow exactly one square of vertical movement." },
				},
			},
		},
	}

	return result
end