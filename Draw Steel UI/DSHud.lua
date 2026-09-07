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

    --No legal route exists, so the engine's flat fallback route is what we're being handed
    --(see the longer note on the "No path found" line below). Its step count, elevation
    --delta and terrain breakdown are all fiction -- a wall the creature cannot climb reads
    --as a one-square step -- so suppress the entire movement-cost line rather than quote
    --numbers that make no sense. What survives is the creature's speed, the hazards, and
    --the "No path found" advisory.
    local noPath = (not path.valid) and (not path.teleport) and (not path.forced)

	local text = ""
    local altitudeDelta = path.destination.altitude - path.origin.altitude

    if not noPath then
        text = string.format(tr('%sMovement: %s %s'), forcedText, MeasurementSystem.NativeToDisplayString(distance), string.lower(MeasurementSystem.UnitName()))

        if altitudeDelta < 0 then
            text = string.format(tr("%s (%d elevation)"), text, round(altitudeDelta))
        elseif altitudeDelta > 0 then
            text = string.format(tr("%s (+%d elevation)"), text, round(altitudeDelta))
        end
    end

    --Predicted collision/fall damage numbers, forwarded to the movement
    --cross-section diagram (movingPathDamages below) so it draws the same red
    --"-N" annotations the forced-move targeting labels show on the map.
    local diagramCollisionDamage = nil
    local diagramFallDamage = nil

    if path.forced then
        if path.collisionSpeed > 0 then
            local collideCreatures = path:GetCreaturesCollidingWith(token)
            local collideObjects = path:GetObjectsCollidingWith(token)

            if collideCreatures == nil or #collideCreatures == 0 then
                text = string.format(tr("%s\n<color=#ff0000>Pushing %d tiles into an object, inflicting %d damage.</color>"), text, path.forcedMovementTotalDistance, path.collisionSpeed+2)
                diagramCollisionDamage = path.collisionSpeed + 2
            else
                text = string.format(tr("%s\n<color=#ff0000>Pushing %d tiles, inflicting %d damage.</color>"), text, path.forcedMovementTotalDistance, path.collisionSpeed)
                diagramCollisionDamage = path.collisionSpeed
            end
        end

        if token.properties:Stability() > 0 then
            text = string.format(tr("%s\nNote: This creature has <b>%d stability</b>"), text, token.properties:Stability())
        end
    end

	local walkAndSwim = false

	--All of these are ";"-suffixes on the movement-cost line, and all read off the same
	--fallback route, so they go away with it.
	if token.properties ~= nil and not path.forced and not noPath then
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
        local safe = token.properties ~= nil and token.properties:SafeFallDistance(path.landsInWater) or 0
        if path.fallDistance <= safe then
            --Green to match the cross-section diagram's "Falls Safely" drop arrow (MovementCrossSection.ColSafeDrop).
            statusText = statusText .. "\n" .. string.format(tr("<color=#4dc74d>Safely drops %d squares.</color>"), path.fallDistance)
        else
            local predicted = token.properties ~= nil and token.properties:PredictedFallDamage(path.fallDistance, path.landsInWater) or 0
            if predicted > 0 then
                statusText = statusText .. "\n" .. string.format(tr("<color=#ff0000>Falls %d squares, taking %d damage.</color>"), path.fallDistance, predicted)
            else
                statusText = statusText .. "\n" .. string.format(tr("<color=#ff0000>Falls %d squares, taking damage.</color>"), path.fallDistance)
            end
        end
    end

    --Fall-damage number for the cross-section diagram: any damaging end-of-move
    --fall, INCLUDING forced movement (the red tooltip line above deliberately
    --excludes forced paths, but the diagram draws their fall arrow and should
    --number it). Flyers hover rather than fall.
    if path.fallDistance > 0 and not path.teleport and token.properties ~= nil and not token.properties:CanFly() then
        local predicted = token.properties:PredictedFallDamage(path.fallDistance, path.landsInWater)
        if predicted > 0 then
            diagramFallDamage = predicted
        end
    end

	if path.teleport then
        local distance = path.origin:DistanceInTiles(path.destination)
        --Teleport cost is the largest single dimension of the jump. DistanceInTiles only
        --covers the lateral (x/y) dimensions, so fold in the vertical (altitudeDelta was
        --computed above): a purely upward teleport is charged for its climb instead of
        --reading as near-zero distance.
        distance = math.max(distance, math.abs(altitudeDelta))
		text = string.format(tr('Teleport: %d %s'), distance, string.lower(MeasurementSystem.UnitName()))
	end

	local floorDelta = nil

	if path.destination.floor ~= token.loc.floor then
		local diff = token.loc:FloorDifference(path.destination)
		floorDelta = diff
		--floorDelta still feeds the cross-section diagram; only the text suffix, which
		--hangs off the suppressed movement line, is skipped.
		if noPath then
			--no movement line to suffix.
		elseif diff == 1 then
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
		if not path.valid then
			--No legal route to the destination exists. When the real pathfinder fails the engine
			--re-routes with a FLAT fallback cost function (10 orthogonal / 15 diagonal per tile,
			--CharacterToken.cs ~18357) that emits no climb, elevation or difficult-terrain flags at
			--all -- so path.cost is fiction: stepping onto a 3-square-high wall comes back as "uses
			--1" instead of 7 (bug CHV77QCP). There is no legal path, so there is no cost worth
			--quoting: state the creature's speed and leave it at that. The GM additionally gets the
			--"No path found" line below.
			text = string.format(tr("%s\n%s %s %s %s per round"), text, creature.GetTokenDescription(token), string.lower(creature:CurrentMoveTypeInfo().tense), MeasurementSystem.NativeToDisplayString(creature:GetEffectiveSpeed(creature:CurrentMoveType())), string.lower(MeasurementSystem.UnitName()))
		else
			--How much this move actually spends. Mirror creature:CreatureMove exactly (path.cost/10
			--with the same diagonal rounding) so the reported "Uses N" matches what will be deducted,
			--INCLUDING climbing and difficult terrain -- neither of which is visible in the top-line
			--square count (that uses path.numSteps, the flat tile count).
			local usedTiles = path.cost/10
			local newDiagonals = cond(usedTiles > math.floor(usedTiles), 1, 0)
			usedTiles = math.floor(usedTiles)
			if dmhub.GetSettingValue("truediagonals") and newDiagonals > 0 and (creature:DiagonalsMovedThisTurn()%2) == 1 then
				usedTiles = usedTiles + 1
			end

			text = string.format(tr("%s\nUses %s of %s's %s %s allowed by Advance Move Action"), text, MeasurementSystem.NativeToDisplayString(usedTiles*dmhub.FeetPerTile), creature.GetTokenDescription(token), MeasurementSystem.NativeToDisplayString(creature:GetEffectiveSpeed(creature:CurrentMoveType())), string.lower(MeasurementSystem.UnitName()))
		end

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

        if (creature:CalculateNamedCustomAttribute("Shift Disabled") or 0) > 0 then
            local reason = nil
            for _,modification in ipairs(creature:DescribeModificationsToNamedCustomAttribute("Shift Disabled")) do
                reason = modification.key
            end
            if reason ~= nil then
                statusText = statusText .. "\n" .. string.format(tr("<color=#ff0000><b>You cannot shift.</b> (%s)</color>"), reason)
            else
                statusText = statusText .. "\n" .. tr("<color=#ff0000><b>You cannot shift.</b></color>")
            end
        end
	end

    local hazards = path:CalculateHazards(token)
    local damageHazards = {}
    if hazards ~= nil then
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

    --Damaging-terrain advisory: a red warning when the path moves into terrain
    --flagged as damaging (Aura:IsDamaging -- an entry power roll like Lava,
    --per-tile move damage, or an explicit `damaging` flag on the aura). Auras
    --already itemized above with exact move-damage numbers are skipped, as are
    --friendly-only auras and an includeAdjacent aura's adjacent-extension
    --tiles (standing next to lava is not moving into it). Footprint-based like
    --the rest of the tooltip: vertical bands are ignored. pcall throughout --
    --scratch auras that do not implement the AuraInstance interface must not
    --take the tooltip down.
    do
        local reportedNames = {}
        for _,hazard in ipairs(damageHazards) do
            reportedNames[hazard.name] = true
        end

        local seenNames = {}
        local damagingNames = {}
        local steps = path.steps or {}
        for i = 2, #steps do
            local auras = game.GetAurasAtLoc(steps[i])
            if auras ~= nil then
                for _,aura in ipairs(auras) do
                    pcall(function()
                        local instance = aura.auraInstance
                        if instance == nil then
                            return
                        end

                        local auraDef = instance:try_get("aura")
                        if auraDef == nil or auraDef:IsDamaging() ~= true then
                            return
                        end

                        local name = auraDef:try_get("name", "Hazard")
                        if reportedNames[name] or seenNames[name] then
                            return
                        end

                        local applyto = instance:GetApplyTo()
                        if applyto == "friends" or applyto == "selfandfriends" then
                            return
                        end

                        if EnvironmentalKeyword.AuraLocOnlyAdjacent(aura, steps[i]) then
                            return
                        end

                        if auraDef:CreaturePassesFilter(token.properties, instance) == false then
                            return
                        end

                        seenNames[name] = true
                        damagingNames[#damagingNames+1] = name
                    end)
                end
            end
        end

        if #damagingNames > 0 then
            text = string.format(tr("%s\n<color=#ff0000>Moving into damaging terrain (%s)!</color>"), text, table.concat(damagingNames, ", "))
        end
    end

	if noPath and dmhub.isDM then
		text = string.format('%s\nNo path found, move through walls or hold control to teleport.', text)
	end


    local modifiers = token.properties:GetActiveModifiers()
    for _,mod in ipairs(modifiers) do
        text = mod.mod:MovementAdvisoryText(token.properties, path, text)
    end

    text = text .. statusText

    --Everything after the movement line is written as a "\n"-prefixed continuation, so when
    --that line is suppressed (noPath) the tooltip would start with a blank line.
    text = string.gsub(text, "^\n+", "")

    if path.properties ~= nil and path.properties.overrideText then
        text = path.properties.overrideText
    end

	--Anchor the tooltip outside the path's bounding box so it never covers the mover, the
	--destination or the arrow. Shared with ability movement targeting; see GameHud.MovementTooltipPlacement.
	local anchor, halign, valign = GameHud.MovementTooltipPlacement(token, path)

	self.dialog.sheet:FireEvent("tiletooltip", {
		--a world-space point, which FloatTooltipNearTile accepts as well as a Loc;
		--halign/valign push the tooltip off that edge, away from the box.
		loc = anchor,
		text = text,
		halign = halign,
		valign = valign,
		floorDelta = floorDelta,

		--used by the movement cross-section diagram in the tooltip
		--(see CreateMovementDiagramPanel in GameHud.lua).
		movingToken = token,
		movingPath = path,
		movingPathDamages = { collision = diagramCollisionDamage, fall = diagramFallDamage },
	})
end