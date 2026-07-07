local mod = dmhub.GetModLoading()

--functions called by dmhud to indicate that a token is moving or has finished moving.
function GameHud.TokenMoving(self, token, path)
	
	local diagonals = dmhub.GetSettingValue("truediagonals") and math.floor(path.numDiagonals/2) or 0

	local distance = path.numSteps + diagonals
	distance = distance * dmhub.FeetPerTile

    local forcedText = ""

    if path.forced then
        forcedText = "Forced "
    end

    local statusText = ""
	local text = string.format(tr('%sMovement: %s %s'), forcedText, MeasurementSystem.NativeToDisplayString(distance), string.lower(MeasurementSystem.UnitName()))

    local altitudeDelta = path.destination.altitude - path.origin.altitude
    if altitudeDelta < 0 then
        text = string.format(tr("%s (%d elevation)"), text, round(altitudeDelta))
    elseif altitudeDelta > 0 then
        text = string.format(tr("%s (+%d elevation)"), text, round(altitudeDelta))
    end

    if path.forced then
        if path.collisionSpeed > 0 then
            local collideCreatures = path:GetCreaturesCollidingWith(token)
            local collideObjects = path:GetObjectsCollidingWith(token)

            if collideCreatures == nil or #collideCreatures == 0 then
                text = string.format(tr("%s\n<color=#ff0000>Pushing %d tiles into an object, inflicting %d damage.</color>"), text, path.forcedMovementTotalDistance, path.collisionSpeed+2)
            else
                text = string.format(tr("%s\n<color=#ff0000>Pushing %d tiles, inflicting %d damage.</color>"), text, path.forcedMovementTotalDistance, path.collisionSpeed)
            end
        end

        if token.properties:Stability() > 0 then
            text = string.format(tr("%s\nNote: This creature has <b>%d stability</b>"), text, token.properties:Stability())
        end
    end

	local walkAndSwim = false

	if token.properties ~= nil and not path.forced then
		if path.mount then
			text = string.format(tr("%s\nMounting or dismounting takes half of movement for the round."), text)
		end

		local moveType = token.properties:CurrentMoveType()
		if moveType == "walk" or moveType == "swim" then

			local waterSteps = math.floor(path.waterSteps) * dmhub.FeetPerTile
			if waterSteps > 0 and waterSteps < distance then
				text = string.format(tr("%s; swim %s %s"), text, MeasurementSystem.NativeToDisplayString(waterSteps), string.lower(MeasurementSystem.UnitName()))
				walkAndSwim = true
			end

			local difficultDistance = math.floor(path.difficultSteps) * dmhub.FeetPerTile
			if difficultDistance == distance and distance > 0 then
				text = string.format(tr("%s; all in difficult terrain"), text)
			elseif difficultDistance > 0 then
				text = string.format(tr("%s; %s %s in difficult terrain"), text, MeasurementSystem.NativeToDisplayString(difficultDistance), string.lower(MeasurementSystem.UnitName()))
			end

            if difficultDistance > 0 and path.shifting then
                local canNavigate = token.properties:CanNavigateDifficultTerrain{shifting = true}
                if not canNavigate then
                    statusText = statusText .. "\n" .. tr("<color=#ff0000>Cannot shift through difficult terrain</color>")
                else
                    local modifications = token.properties:DescribeModificationsToNamedCustomAttribute("Can Shift In Difficult Terrain")
                    local reason = nil
                    for _,mod in ipairs(modifications) do
                        reason = mod.key
                    end
                    if reason ~= nil then
                        statusText = statusText .. "\n" .. tr("<color=#00ff00>" .. reason .. " allows shifting through difficult terrain</color>")
                    else
                        statusText = statusText .. "\n" .. tr("<color=#00ff00>Can shift through difficult terrain</color>")
                    end
                end
            end

			local squeezeDistance = math.floor(path.squeezeSteps) * dmhub.FeetPerTile
			if squeezeDistance == distance and distance > 0 then
				text = string.format(tr("%s; squeezing through a tight space"), text)
			elseif squeezeDistance > 0 then
				text = string.format(tr("%s; %s %s squeezing through tight spaces"), text, MeasurementSystem.NativeToDisplayString(squeezeDistance), string.lower(MeasurementSystem.UnitName()))
			end
		end
	end

    if path.hasClimbing then
        statusText = statusText .. "\n" .. tr("<color=#ff0000>This path requires climbing.</color>")
    end

    if path.fallDistance > 0 and not path.forced and not path.teleport then
        statusText = statusText .. "\n" .. string.format(tr("<color=#ff0000>You will fall %d squares. Hold shift to climb down instead.</color>"), path.fallDistance)
    end

	if path.teleport then
        local distance = path.origin:DistanceInTiles(path.destination)
		text = string.format(tr('Teleport: %d %s'), distance, string.lower(MeasurementSystem.UnitName()))
	end

	local floorDelta = nil

	if path.destination.floor ~= token.loc.floor then
		local diff = token.loc:FloorDifference(path.destination)
		floorDelta = diff
		if diff == 1 then
			text = text .. tr(' (+1 Floor)')
		elseif diff == -1 then
			text = text .. tr(' (-1 Floor)')
		else
			local prefix = '+'
			if diff < 0 then
				prefix = '-'
				diff = -diff
			end

			text = text .. tr(' (' .. prefix .. tostring(diff) .. ' Floors)')
		end
	end

	local creature = token.properties
	if creature ~= nil and (not path.teleport) and (not path.forced) and (not path.shifting) then
		text = string.format(tr('%s\n%s %s %s %s per round'), text, creature.GetTokenDescription(token), string.lower(creature:CurrentMoveTypeInfo().tense), MeasurementSystem.NativeToDisplayString(creature:GetEffectiveSpeed(creature:CurrentMoveType())), string.lower(MeasurementSystem.UnitName()))

		if walkAndSwim then
			local otherMode = "walk"
			if creature:CurrentMoveType() == "walk" then
				otherMode = "swim"
			end

			text = string.format(tr("%s\n%s %s %s %s per round"), text, creature.GetTokenDescription(token), string.lower(creature.movementTypeById[otherMode].tense), MeasurementSystem.NativeToDisplayString(creature:GetEffectiveSpeed(otherMode)), string.lower(MeasurementSystem.UnitName()))
		end

		local distMoved = creature:DistanceMovedThisTurn()
		if distMoved > 0 then
			text = string.format(tr("%s\nAlready moved %s %s this turn."), text, MeasurementSystem.NativeToDisplayString(distMoved*dmhub.FeetPerTile), string.lower(MeasurementSystem.UnitName()))
		end

		if creature:CanTeleport() then
			text = string.format(tr("%s\n<color=#00ff00>This token can teleport. Hold ctrl to teleport.</color>"), text)
		end
    elseif creature ~= nil and path.shifting then
		text = string.format(tr('%s\n%s moves %s %s per round when using <b>disengage</b> to shift'), text, creature.GetTokenDescription(token), MeasurementSystem.NativeToDisplayString(creature:CarefulMovementSpeed()), string.lower(MeasurementSystem.UnitName()))

	end

    local hazards = path:CalculateHazards(token)
    if hazards ~= nil then
        local damageHazards = {}
        for _,hazard in ipairs(hazards) do
            if hazard.type == "damage" then
                local found = false

                for _,existing in ipairs(damageHazards) do
                    if existing.type == hazard.damageType and existing.name == hazard.aura.aura.name then
                        existing.damage = existing.damage + hazard.damageAmount
                        found = true
                        break
                    end
                end

                if not found then
                    damageHazards[#damageHazards+1] = {damage = hazard.damageAmount, type = hazard.damageType, name = hazard.aura.aura.name}
                end
            end
        end

        for _,hazard in ipairs(damageHazards) do
            if hazard.type == "normal" or hazard.type == "untyped" then
                text = string.format("%s\n<color=#ff6666>%d damage from %s</color>", text, hazard.damage, hazard.name)
            else
                text = string.format("%s\n<color=#ff6666>%d %s damage from %s</color>", text, hazard.damage, hazard.type, hazard.name)
            end
        end
    end

	if (not path.valid) and (not path.teleport) and (not path.forced) and dmhub.isDM then
		text = string.format('%s\nNo path found, move through walls or hold control to teleport.', text)
	end


    local modifiers = token.properties:GetActiveModifiers()
    for _,mod in ipairs(modifiers) do
        text = mod.mod:MovementAdvisoryText(token.properties, path, text)
    end

    text = text .. statusText

    if path.properties ~= nil and path.properties.overrideText then
        text = path.properties.overrideText
    end

	--Place the movement tooltip so it can NEVER cover the moving token, the destination, or any part of
	--the arrow. We build the axis-aligned bounding box of the WHOLE path -- every tile the mover steps
	--through, each expanded by the mover's footprint (so both end tokens sit fully inside) plus a little
	--for the arrow ribbon -- and then place the tooltip entirely OUTSIDE that box on one of its four
	--sides. Anchoring at the box EDGE (rather than the old midpoint + perpendicular nudge) pins the
	--tooltip's near, box-facing edge to the box boundary independent of the tooltip's size, so it clears
	--the entire path at any move angle or length; it also removes the one-frame size-lag wobble the old
	--version had (where the previously hovered tile appeared to influence the placement). We choose the
	--side with the most room for the tooltip, computed from the camera's usable world bounds (the same
	--rect Panel.ShowTooltip clamps to) so the on-screen clamp won't drag it back over the box. Everything
	--here is in world coordinates: PosAtLoc, cameraUsableBounds and the ShowTooltip anchor share that
	--space (valign 'top' = higher world y, halign 'right' = higher world x).

	--Bounding box of the whole path, expanded by the mover's footprint (+ a bit for the arrow ribbon).
	local pad = (token.tileSize or 1)*0.5 + 0.15
	local minx, miny, maxx, maxy = nil, nil, nil, nil
	for _,step in ipairs(path.steps) do
		local p = token:PosAtLoc(step)
		if minx == nil then
			minx, miny, maxx, maxy = p.x, p.y, p.x, p.y
		else
			if p.x < minx then minx = p.x elseif p.x > maxx then maxx = p.x end
			if p.y < miny then miny = p.y elseif p.y > maxy then maxy = p.y end
		end
	end
	if minx == nil then
		local p = token:PosAtLoc(path.destination)
		minx, miny, maxx, maxy = p.x, p.y, p.x, p.y
	end
	minx, miny, maxx, maxy = minx - pad, miny - pad, maxx + pad, maxy + pad

	local cx = (minx + maxx)*0.5
	local cy = (miny + maxy)*0.5
	local gap = 0.3

	--rough OVER-estimate of the tooltip's world size (text + diagram), used only to pick the roomiest
	--side. Over-estimating is safe: it just biases us away from a side that is too tight.
	local worldPerPixel = 0.1
	local screenDims = dmhub.screenDimensions
	if dmhub.cameraZoom ~= nil and screenDims ~= nil and screenDims.y > 0 then
		worldPerPixel = (dmhub.cameraZoom*2) / screenDims.y
	end
	local ttW = 430 * worldPerPixel
	local ttH = 640 * worldPerPixel

	--Four candidate placements: tooltip fully outside the box, one per side. `slack` is how much room is
	--left over after fitting the tooltip on that side (positive = fits without the clamp shoving it back).
	local halign, valign, anchorx, anchory
	local bounds = dmhub.cameraUsableBounds
	if bounds == nil then
		halign, valign, anchorx, anchory = 'right', 'center', maxx + gap, cy
	else
		local candidates = {
			{ slack = (bounds.x2 - maxx) - ttW, halign = 'right',  valign = 'center', anchorx = maxx + gap, anchory = cy },
			{ slack = (minx - bounds.x1) - ttW, halign = 'left',   valign = 'center', anchorx = minx - gap, anchory = cy },
			{ slack = (bounds.y2 - maxy) - ttH, halign = 'center', valign = 'top',    anchorx = cx, anchory = maxy + gap },
			{ slack = (miny - bounds.y1) - ttH, halign = 'center', valign = 'bottom', anchorx = cx, anchory = miny - gap },
		}
		local best = candidates[1]
		for i = 2, #candidates do
			if candidates[i].slack > best.slack then best = candidates[i] end
		end
		halign, valign, anchorx, anchory = best.halign, best.valign, best.anchorx, best.anchory
	end

	self.dialog.sheet:FireEvent("tiletooltip", {
		--anchor at the chosen edge of the path bounding box (a world-space point, which
		--FloatTooltipNearTile accepts as well as a Loc); halign/valign then push the tooltip off that
		--edge, away from the box.
		loc = core.Vector2(anchorx, anchory),
		text = text,
		halign = halign,
		valign = valign,
		floorDelta = floorDelta,

		--used by the movement cross-section diagram in the tooltip
		--(see CreateMovementDiagramPanel in GameHud.lua).
		movingToken = token,
		movingPath = path,
	})
end