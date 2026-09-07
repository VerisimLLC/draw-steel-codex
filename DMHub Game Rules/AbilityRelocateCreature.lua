local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityRelocateCreatureBehavior:ActivatedAbilityBehavior
--- Behavior that moves (relocates) the target creature along a chosen path.
ActivatedAbilityRelocateCreatureBehavior = RegisterGameType("ActivatedAbilityRelocateCreatureBehavior", "ActivatedAbilityBehavior")


ActivatedAbility.RegisterType
{
	id = 'relocate_creature',
	text = 'Relocate Creature',
	createBehavior = function()
		return ActivatedAbilityRelocateCreatureBehavior.new{
		}
	end
}

--- @param casterToken CharacterToken
--- @param path LuaPath
--- @return nil|(CharacterToken[])
function ActivatedAbility:FindTargetsInMovementVicinity(casterToken, path)
    for i,behavior in ipairs(self.behaviors) do
        local result = behavior:FindTargetsInMovementVicinity(self, casterToken, path)
        if result ~= nil then
            return result
        end
    end

    return nil
end

--- @param casterToken CharacterToken
--- @param path LuaPath
--- @return nil|(CharacterToken[])
function ActivatedAbilityBehavior:FindTargetsInMovementVicinity(ability, casterToken, path)
    return nil
end

--- @param casterToken CharacterToken
--- @param path LuaPath
--- @return nil|(Loc[])
function ActivatedAbility:FindPassedSquareLocs(casterToken, path)
    for i,behavior in ipairs(self.behaviors) do
        local result = behavior:FindPassedSquareLocs(self, casterToken, path)
        if result ~= nil then
            return result
        end
    end

    return nil
end

--- @param casterToken CharacterToken
--- @param path LuaPath
--- @return nil|(Loc[])
function ActivatedAbilityBehavior:FindPassedSquareLocs(ability, casterToken, path)
    return nil
end

--- @param casterToken CharacterToken
--- @param path LuaPath
--- @return nil|(CharacterToken[])
function ActivatedAbilityRelocateCreatureBehavior:FindTargetsInMovementVicinity(ability, casterToken, path)
    if not self.targetMoveVicinity then
        return nil
    end

    print("VICINITY:: SEARCH...")

    local locs = {}
    for i,loc in ipairs(path.steps) do
        local newLocs = casterToken:LocsOccupyingWhenAt(loc)
        for i,newLoc in ipairs(newLocs) do
            locs[newLoc.xyfloorOnly.str] = true
            if self.vicinity > 0 then
                for _,adjLoc in ipairs(newLoc:LocsInRadius(self.vicinity)) do
                    locs[adjLoc.xyfloorOnly.str] = true
                end
            end
        end
    end

    local result = {}

    local index = 0
    for key,_ in pairs(locs) do
        local loc = core.Loc(key)
        index = index+1
        local tokens = game.GetTokensAtLoc(loc)

        for i,token in ipairs(tokens or {}) do
            for _,tok in ipairs(result) do
                if tok.id == token.id then
                    token = nil
                    break
                end
            end

            if token ~= nil and token.id ~= casterToken.id and ability:TargetPassesFilter(casterToken, token, {}, self.vicinityFilter) then
                result[#result+1] = token
            end
        end
    end

    return result
end

--- @param casterToken CharacterToken
--- @param path LuaPath
--- @return nil|(Loc[])  Every square the creature stood in along its path (starting square included), or nil if the option is off.
function ActivatedAbilityRelocateCreatureBehavior:FindPassedSquareLocs(ability, casterToken, path)
    if not self.targetPassedSquares then
        return nil
    end

    local result = {}
    local seen = {}

    --Walk the path and collect every square the creature stood in, including
    --its starting square. Each square is only added once.
    for i = 1, #path.steps do
        local loc = path.steps[i]
        local occupied = casterToken:LocsOccupyingWhenAt(loc)
        for _, occLoc in ipairs(occupied) do
            local key = occLoc.xyfloorOnly.str
            if not seen[key] then
                seen[key] = true
                result[#result+1] = occLoc
            end
        end
    end

    return result
end

ActivatedAbilityRelocateCreatureBehavior.summary = 'Relocate Creatures'
ActivatedAbilityRelocateCreatureBehavior.swapCreatures = false
ActivatedAbilityRelocateCreatureBehavior.targetMoveVicinity = false
ActivatedAbilityRelocateCreatureBehavior.vicinity = 0
ActivatedAbilityRelocateCreatureBehavior.vicinityFilter = ""
ActivatedAbilityRelocateCreatureBehavior.targetPassedSquares = false
ActivatedAbilityRelocateCreatureBehavior.movementType = "teleport"
ActivatedAbilityRelocateCreatureBehavior.expendFullMovement = false

--A relocate never charges movement (see the _tmp_freeMovement flag in Cast), so
--when "Expend Full Movement" is set we bill the creature's entire remaining
--movement for the turn no matter how far it actually travelled. Only meaningful
--on the creature's own turn -- a creature shoved around on someone else's turn
--has no movement pool to spend.
function ActivatedAbilityRelocateCreatureBehavior:ExpendMovementIfNeeded(casterToken)
    if not self.expendFullMovement then
        return
    end

    if dmhub.initiativeQueue == nil or dmhub.initiativeQueue.hidden then
        return
    end

    if not casterToken.properties:IsOurTurn() then
        return
    end

    casterToken:ModifyProperties{
        description = "Expend Movement",
        undoable = false,
        execute = function()
            local speed = casterToken.properties:CurrentMovementSpeed()
            casterToken.properties.moveDistance = math.max(casterToken.properties:DistanceMovedThisTurn(), speed)
            casterToken.properties.moveDistanceRoundId = dmhub.initiativeQueue:GetTurnId()
        end,
    }
end

--Movement type used by targeting previews (ActivatedAbility:GetMovementType).
--A shift the user has overridden to be a regular move reports "move".
function ActivatedAbilityRelocateCreatureBehavior:BehaviorMovementType(symbols)
    if symbols ~= nil and symbols.shiftingOverride ~= nil then
        if self.movementType == "shift" and (not symbols.shiftingOverride) then
            return "move"
        end
    end

    return self.movementType
end

--After a shortfall, only offer the ordinary charge selector when an affordable
--charge attack can legally reach a creature from the actual landing square.
function ActivatedAbilityRelocateCreatureBehavior:HasChargeAttackTarget(casterToken)
    local attackSelector = dmhub.GetTable("standardAbilities")["923bf32c-4233-4fec-8895-7ce18da28744"]
    if attackSelector == nil then
        return false
    end
    local props = casterToken.properties
    for _, attack in ipairs(attackSelector:SynthesizeAbilities(props) or {}) do
        if attack:try_get("suppressExplanation") == nil
            and attack:AbilityFilterFailureMessage(props) == nil and attack:GetCost(casterToken).canAfford then
            local symbols = {caster = props}
            local range = attack:GetRange(props, symbols) + dmhub.unitsPerSquare
            for _, target in ipairs(dmhub.allTokens) do
                local hiddenFromStrike = false
                if target.valid and attack:HasKeyword("Strike") and target.properties:HasNamedCondition("Hidden") then
                    local ignoreRange = props:CalculateNamedCustomAttribute("Ignore Hidden Within Range") or 0
                    hiddenFromStrike = ignoreRange <= 0 or casterToken:Distance(target) > ignoreRange
                end
                if target.valid and attack:TargetPassesFilter(casterToken, target, symbols)
                    and not hiddenFromStrike
                    and casterToken:Distance(target) < range
                    and math.abs(casterToken.altitude - target.altitude) * dmhub.unitsPerSquare < range
                    and casterToken:GetLineOfSight(target, props:GetPierceWalls()) > 0 then
                    return true
                end
            end
        end
    end
    return false
end

--Keep the chosen takeoff and landing fixed when a charge needs a jump test.
--Only the rolled jump segment can fall short; the rest of that route is discarded.
function ActivatedAbilityRelocateCreatureBehavior:ExecuteGuaranteedCharge(casterToken, targetLoc, chargeOptions, options, ability)
    local function abortCharge()
        options.abort = true
        options.stopProcessing = true
    end
    local ok, plan = pcall(function() return casterToken:PlanCharge(targetLoc, chargeOptions) end)
    if not ok or plan == nil or plan.validCharge ~= true then
        abortCharge()
        return
    end

    casterToken:ClearMovementArrow()
    local moved = 0
    for _, segment in ipairs(plan.chargeSegments) do
        if not casterToken.valid or casterToken.properties:IsDead() then
            abortCharge()
            return
        end
        --Movement reactions can change speed or knock the charger prone at
        --takeoff. Check the remaining allowance before starting each segment.
        local current = chargeOptions
        if ability ~= nil then
            current = ability:GetChargeJumpOptions(casterToken, options.symbols)
            local segmentDistance = casterToken.loc:DistanceInTiles(segment.expectedLoc)
            if current == nil or current.chargeDistance - moved < segmentDistance
                or (segment.jump and not plan.requiresRoll and (current.chargeJumpDistance < segmentDistance
                    or current.chargeJumpHeight < segment.jumpHeight)) then
                abortCharge()
                return
            end
        end

        if segment.jump and plan.requiresRoll and current.jumpBehavior == nil then
            abortCharge()
            return
        end

        --Once the approach starts, canceling at takeoff cannot refund Charge.
        --The Jump test below uses its own modifiers but never pays for Jump.
        if ability ~= nil and not options.pay then
            ability:CommitToPaying(casterToken, options)
        end

        local outcome = nil
        if segment.jump and plan.requiresRoll then
            local takeoffLoc = casterToken.loc
            if current.jumpBehavior == nil or current.chargeJumpTierDistances == nil then
                abortCharge()
                return
            end
            local distances = current.jumpBehavior:GetTierDistances(current.jumpAbility, casterToken,
                math.max(0, current.chargeDistance - moved))
            local heights = current.jumpBehavior:GetTierHeights(current.jumpAbility, casterToken)
            local tier = plan.requiredTier
            if tier > current.chargeJumpGuaranteedTier then
                tier = current.jumpBehavior:RollForTier(current.jumpAbility, casterToken, options,
                    distances, heights, plan.requiredTier, segment.expectedLoc, {
                        commitPayment = false,
                        markPreview = function(previewTier)
                            casterToken:MarkMovementArrow(segment.expectedLoc, {
                                jump = true, chargeJumpOutcome = true,
                                chargeJumpDistance = distances[previewTier], jumpHeight = heights[previewTier],
                            })
                        end,
                    })
                if tier == nil then
                    abortCharge()
                    return
                end
            end

            --A reaction while the dice dialog was open can remove the ability
            --to jump or change the remaining distance. Use the current limits.
            if not casterToken.valid or casterToken.loc.str ~= takeoffLoc.str then
                abortCharge()
                return
            end
            current = ability:GetChargeJumpOptions(casterToken, options.symbols)
            if current == nil or current.jumpBehavior == nil
                or current.chargeDistance - moved <= 0 then
                abortCharge()
                return
            end
            distances = current.jumpBehavior:GetTierDistances(current.jumpAbility, casterToken,
                math.max(0, current.chargeDistance - moved))
            heights = current.jumpBehavior:GetTierHeights(current.jumpAbility, casterToken)
            local outcomeOk
            outcomeOk, outcome = pcall(function()
                return casterToken:PlanChargeJumpOutcome(casterToken.loc, segment.expectedLoc,
                    distances[tier], heights[tier])
            end)
            if not outcomeOk or outcome == nil then
                abortCharge()
                return
            end
            casterToken:ClearMovementArrow()
        end

        local moveOptions = {
            straightline = true,
            moveThroughFriends = false,
            ignorecreatures = segment.jump,
            ignoreFalling = segment.jump,
            maxCost = math.floor(chargeOptions.chargeDistance * 1000 + 100),
            movementType = cond(segment.jump, "jump", "walk"),
            jumpHeight = segment.jumpHeight,
            chargeDistance = chargeOptions.chargeDistance,
            chargeJumpLanding = segment.jump,
            freeMovement = true,
        }
        if outcome ~= nil then
            moveOptions.chargeJumpLanding = false
            moveOptions.chargeJumpOutcome = true
            moveOptions.chargeJumpDistance = outcome.jumpDistance
            moveOptions.jumpHeight = outcome.jumpHeight
        end
        local path = casterToken:Move(outcome and outcome.loc or segment.loc, moveOptions)
        if path ~= nil then
            moved = moved + path.numSteps
            options.symbols.cast.spacesMoved = options.symbols.cast.spacesMoved + path.numSteps
        end
        while casterToken.valid and casterToken.isMoving do
            coroutine.yield(0.05)
        end
        local expectedLoc = outcome and outcome.expectedLoc or segment.expectedLoc
        if path == nil or not casterToken.valid or casterToken.properties:IsDead()
            or casterToken.loc.str ~= expectedLoc.str then
            abortCharge()
            return
        end
        if outcome ~= nil and not outcome.reachesJumpEnd then
            --The normal charge attack selector now uses the actual landing.
            --Prone can still strike with its normal bane; attack availability
            --and target legality determine whether the selector is useful.
            if casterToken.properties:IsDead() or not self:HasChargeAttackTarget(casterToken) then
                abortCharge()
            end
            return
        end
    end
end

function ActivatedAbilityRelocateCreatureBehavior:Cast(ability, casterToken, targets, options)
    print("Relocate:: Cast relocate", #targets)

    casterToken.properties._tmp_freeMovement = true

    if ability.targetType == 'line' and options.targetArea ~= nil then

        local locs = options.targetArea.locations
        if locs ~= nil and #locs > 0 then
            --relocate to the end of the line.
            local furthestLoc = locs[1]
            for i=2,#locs do
                if locs[i]:DistanceInTiles(casterToken.loc) > furthestLoc:DistanceInTiles(casterToken.loc) then
                    furthestLoc = locs[i]
                end
            end

            targets = {{
                loc = furthestLoc,
                token = nil,
            }}
        end
    end

    print("RELOCATE:: TARGETS ==", targets)
    if #targets > 0 then
        local movementType = self.movementType
        if options.symbols.shiftingOverride == false then
            --the user overrode this to be a move instead of a shift.
            movementType = "move"
        end

        -- Charge-jump override (e.g., Panther's Mighty Spring): a creature with
        -- the "Charge Uses Jump" custom attribute leaps instead of running when
        -- the Charge action's relocate runs. We identify Charge by ability name
        -- rather than the Charging momentary attribute because the action bar's
        -- destructor (from ApplyOnCasting in DrawSteelActionBar.lua) fires at
        -- finishCasting AFTER Cast() returns but BEFORE the cast coroutine
        -- reaches this behavior, and `table.remove_value` strips ALL copies of
        -- the effect, so even the duplicate added by ApplyAbilityDurationEffect's
        -- :Cast is wiped before we'd see Charging > 0 here.
        if movementType == "move"
            and ability.name == "Charge"
            and casterToken.properties:CalculateNamedCustomAttribute("Charge Uses Jump") > 0 then
            movementType = "jump"
        end

        local startingOpportunityAttacks = casterToken.properties._tmp_triggeredOpportunityAttacks

		local swapTokens = nil
		if self.swapCreatures then
			swapTokens = game.GetTokensAtLoc(targets[1].loc)
			if swapTokens ~= nil and ability.targetType == 'emptyspacefriend' and (not casterToken:IsFriend(swapTokens[1])) then
				--can only swap with friends.
				swapTokens = nil
			end
		end

        local chargeOptions = nil
        if movementType == "move" then
            chargeOptions = ability:GetChargeJumpOptions(casterToken, options.symbols)
        end

        if chargeOptions ~= nil then
            self:ExecuteGuaranteedCharge(casterToken, targets[#targets].loc, chargeOptions, options, ability)
            if options.abort then
                --Stopping before the attack also skips Charge's final cleanup.
                --Run its purge now so the temporary Charging effect cannot linger.
                for _, behavior in ipairs(ability.behaviors) do
                    if behavior.typeName == "ActivatedAbilityPurgeEffectsBehavior" then
                        behavior:Cast(ability, casterToken,
                            behavior:ApplyToTargets(ability, casterToken, targets, options), options)
                    end
                end
            end
        elseif swapTokens ~= nil then
			--Mirror the teleport branch: track distance moved on the cast so
			--downstream behaviors (e.g. activationCondition gates like
			--`Cast.Spaces Moved > 0`) can detect that the swap actually happened.
			local swapDistance = casterToken:Distance(targets[1].loc)
			if swapDistance > 0 then
				options.symbols.cast.spacesMoved = options.symbols.cast.spacesMoved + swapDistance
				--teleport-style distance: counted in spacesMoved (above) but excluded
				--from Cast.SpacesMovedThisInvocation.
				options.symbols.cast:CountTeleportDistance(swapDistance)
			end
			casterToken:SwapPositions(swapTokens[1])
		elseif movementType == "teleport" or movementType == "relocate" then
            --Some `applyto` handlers (caster_summoner, caster_companion, etc.) build
            --target entries as { token = X } without a `loc` field. Fall back to the
            --token's current loc so teleport works for those targets too.
            local destLoc = targets[1].loc
            if destLoc == nil and targets[1].token ~= nil and targets[1].token.valid then
                destLoc = targets[1].token.loc
            end
            if destLoc == nil then
                print("Relocate:: teleport target has no loc; skipping")
                return
            end

            local distance = casterToken:Distance(destLoc)
            if distance > 0 then
			    options.symbols.cast.spacesMoved = options.symbols.cast.spacesMoved + distance
                --teleport-style distance: counted in spacesMoved (above) but excluded
                --from Cast.SpacesMovedThisInvocation.
                options.symbols.cast:CountTeleportDistance(distance)
            end

            if movementType == "relocate" then
                casterToken.properties._tmp_suppressTeleportEvent = true
            end

            --Custom attribute "Force Bring Grabbed Creature": if the teleporting
            --creature has it set, gather the list of creatures it is currently
            --grabbing BEFORE we teleport (so we know their pre-teleport positions
            --for the "closest adjacent" placement heuristic). We do the actual
            --bring-along teleports AFTER the caster has moved.
            local bringGrabbed = casterToken.properties:CalculateNamedCustomAttribute("Force Bring Grabbed Creature") > 0
            local grabbedToBring = nil
            if bringGrabbed then
                local g_grabbedid = "70504ebe-3899-41d3-9f60-74b52ce35e39"
                grabbedToBring = {}
                casterToken.properties:VisitConditionCasterSource(function(condid, grabbedTok)
                    if condid == g_grabbedid and grabbedTok ~= nil and grabbedTok.valid then
                        grabbedToBring[#grabbedToBring+1] = grabbedTok
                    end
                end)
            end

            --The action bar's altitude controller resolves the target loc to an
            --ABSOLUTE altitude (bounded by the teleport distance), and it is only
            --offered for teleport targeting -- see
            --ActivatedAbility:TargetLocMaxElevationChangeFunction. A relocate never
            --gets one, so its target loc is the raw map-click loc, whose altitude is
            --a meaningless 0 (Token.GetMouseWorldLoc -> TileUtils.PosToLoc). Taking
            --the max against that 0 stranded the creature in mid-air over any ground
            --below altitude 0: relocating out of an 8-deep pit landed it at altitude
            --0, eight squares up, and the TryFall below immediately dropped it again
            --for full falling damage. Land on the ground unless a deliberately chosen
            --altitude could actually have been supplied.
            local groundLoc = destLoc.withGroundAltitude
            local landingAltitude = groundLoc.altitude
            if movementType == "teleport" and (ability.targetType == "emptyspace" or ability.targetType == "anyspace") then
                landingAltitude = math.max(groundLoc.altitude, destLoc.altitude)
            end
            local teleportLoc = groundLoc:WithAltitude(landingAltitude)

            --Teleport bypasses OnMove's leaveadjacent dispatch, so capture enemies
            --with "Opportunity Attack On Any Movement" adjacent to the origin now
            --(relocate is a silent reposition that does not provoke, so gate on
            --teleport only).
            local teleportOAObservers = nil
            if movementType == "teleport" then
                teleportOAObservers = casterToken.properties:CaptureTeleportOpportunityAttackers(casterToken.loc)
            end

        	casterToken:Teleport(teleportLoc)

            casterToken.properties._tmp_suppressTeleportEvent = nil

            --After the caster teleports, bring along any grabbed creatures.
            --Placement: closest legal adjacent square (within radius 1 of caster's
            --new position) to each grabbed creature's pre-teleport location, with
            --first-come-first-served reservation so two grabbed creatures don't
            --land on the same square. If no legal square exists for a creature,
            --it is left behind (its own teleport-trigger / forcemove distance
            --check will then end the grab normally).
            if grabbedToBring ~= nil and #grabbedToBring > 0 then
                local adjacentLocs = casterToken:GetLocsWithinRadius(1)
                local reserved = {}
                for _,grabbedTok in ipairs(grabbedToBring) do
                    if grabbedTok.valid then
                        local prevLoc = grabbedTok.loc
                        local bestLoc = nil
                        local bestDist = nil
                        for _,candidate in ipairs(adjacentLocs) do
                            local key = candidate.xyfloorOnly.str
                            if not reserved[key] then
                                --Don't drop them on top of the caster's own occupied tiles.
                                local occupants = game.GetTokensAtLoc(candidate) or {}
                                local blocked = false
                                for _,occ in ipairs(occupants) do
                                    if occ.id ~= grabbedTok.id then
                                        blocked = true
                                        break
                                    end
                                end
                                if not blocked then
                                    local d = candidate:DistanceInTiles(prevLoc)
                                    if bestDist == nil or d < bestDist then
                                        bestDist = d
                                        bestLoc = candidate
                                    end
                                end
                            end
                        end

                        if bestLoc ~= nil then
                            reserved[bestLoc.xyfloorOnly.str] = true
                            --Suppress the grabbed creature's own teleport trigger
                            --(which would end the Grabbed condition per the
                            --"if you teleport while Grappled, the condition
                            --ends" rule) just for this forced relocation.
                            grabbedTok.properties._tmp_suppressTeleportEvent = true
                            grabbedTok:Teleport(bestLoc.withGroundAltitude)
                            grabbedTok.properties._tmp_suppressTeleportEvent = nil
                        end
                    end
                end
            end

            --Fall check: a creature that teleports into midair falls unless it
            --can fly (TryFall is a no-op for grounded or flying creatures).
            --Give the teleport a moment to breathe first: wait for a full game
            --update to land with the creature in the air (plus a short beat so
            --the teleport animation can resolve) before the falling rules
            --engage. Time-capped so a stalled update can't hang the cast.
            if teleportLoc.altitude > groundLoc.altitude then
                local updateAtTeleport = dmhub.ngameupdate
                local startTime = dmhub.Time()
                while (dmhub.ngameupdate <= updateAtTeleport or dmhub.Time() < startTime + 0.5) and dmhub.Time() < startTime + 2 do
                    coroutine.yield(0.1)
                end
            end
            if casterToken.valid then
                casterToken:TryFall()
            end

            --Now that the teleport (and any fall) has resolved, let flagged enemies
            --that are no longer adjacent opportunity-attack the departure.
            if teleportOAObservers ~= nil and casterToken.valid then
                casterToken.properties:DispatchTeleportOpportunityAttacks(teleportOAObservers)
            end
        elseif movementType == "jump" then
            print("JUMP:: TARGET =", targets[1].loc.floor)
            --The jump distance (in tiles) is also the height the jump can clear: a "jump N" sails over
            --any height-limited wall/block up to N tiles tall (engine wall-height model). Pass it as
            --jumpHeight so the straight-line jump path clears those walls instead of being blocked.
            local jumpHeight = math.floor((ability:GetRange(casterToken.properties)/dmhub.unitsPerSquare) + 0.5)
		    local path = casterToken:Move(targets[#targets].loc, { ignoreFalling = true, straightline = true, moveThroughFriends = true, ignorecreatures = true, maxCost = 30000, movementType = "jump", jumpHeight = jumpHeight })
            if path ~= nil then
                options.symbols.cast.spacesMoved = options.symbols.cast.spacesMoved + path.numSteps
            end
		else

            if options.symbols.invoker ~= nil then
                local invoker = options.symbols.invoker
                if type(invoker) == "function" then
                    invoker = invoker("self")
                end

                if invoker ~= nil then
                    casterToken.properties._tmp_lastpusher = invoker
                end
            end

            local forcemoveEvent = nil
			local collisionInfo = nil
			local throughCreatures = ability:try_get("forcedMovementThroughCreatures", false)
			local forcedPushOptions = casterToken.properties:GetForcedPushOptions()
			local abilityDist = ability:GetRange(casterToken.properties)/dmhub.unitsPerSquare
			if ability.targeting == "straightline" or ability.targetType == "line" then
				local abilityDistForArrow = abilityDist
				local isVerticalSlide = (options.symbols.forcedmovement or ability:try_get("forcedMovement", "slide")) == "vertical_slide"
				local movementInfo = casterToken:MarkMovementArrow(targets[1].loc, {waypoints = options.symbols.waypoints, straightline = true, ignorecreatures = (ability.targetType == "line" or throughCreatures), forcedMovementDistance = abilityDistForArrow, rebound = forcedPushOptions.rebound, maxBounces = forcedPushOptions.maxBounces, slide = isVerticalSlide})
				if movementInfo ~= nil then

					local loc = targets[1].loc

					local path = movementInfo.path
                print("RELOCATE:: to", loc.x, loc.y, loc.altitude, "->", path.destination.x, path.destination.y, path.destination.altitude)
					local requestDist = math.min(loc:DistanceInTiles(path.origin), abilityDist)
					local pathDist = path.destination:DistanceInTiles(path.origin)

                    local freeMovement = path.freeMovementSteps
                    -- If the path is actually blocked (collision with wall/creature),
                    -- use full ability distance so collision force reflects max available force.
                    if path.hasCollision and requestDist < abilityDist then
                        requestDist = abilityDist
                    end
                    local hasCollision = freeMovement < requestDist
                    local collisionSpeed = requestDist - freeMovement

                    -- The engine reports the true force remaining at the moment of
                    -- collision (path.collisionForce >= 0): distance travelled AND
                    -- stamina spent breaking earlier walls (e.g. targetable wall
                    -- voxels) are already deducted, so a second wall or creature is
                    -- hit with reduced momentum. -1 means the engine recorded no
                    -- collision -- force spent purely on wall breaks is not a
                    -- collision, so a clean smash-through deals no collision damage.
                    local collisionForce = path.collisionForce
                    if collisionForce ~= nil then
                        if collisionForce >= 0 then
                            hasCollision = true
                            collisionSpeed = collisionForce
                        elseif not path.hasCollision then
                            hasCollision = false
                            collisionSpeed = 0
                        end
                    end
                    print("PATHFIND:: DIST =", pathDist, "freeMovement=", freeMovement, "requestDist=", requestDist, "hasCollision=", hasCollision, "collisionSpeed=", collisionSpeed, "collisionForce=", collisionForce)

					if hasCollision then
						collisionInfo = {
							speed = collisionSpeed,
							collideWith = movementInfo.collideWith,
						}

						options.symbols.cast.forcedMovementCollision = true
					end

                    if movementType == "move" then
                        local args = {
                            attacker = options.symbols.invoker,
                            hasattacker = options.symbols.invoker ~= nil,
                            type = options.symbols.forcedmovement or ability:try_get("forcedMovement", "slide"),
                            vertical = ability:try_get("forcedMovement", "slide") == "vertical_push" or ability:try_get("forcedMovement", "slide") == "vertical_pull",
                            collision = hasCollision and collisionSpeed or 0,
                            collidewithobject = hasCollision and collisionInfo ~= nil and #(collisionInfo.collideWith or {}) == 0,
                        }
                        
                        --search for if one of the tokens is considered an object.
                        if (not args.collidewithobject) and collisionInfo ~= nil then
                            for _,tok in ipairs(collisionInfo.collideWith or {}) do
                                if tok.isObject then
                                    args.collidewithobject = true
                                    break
                                end
                            end
                        end
                        forcemoveEvent = args
                    end

                    options.symbols.cast:RecordForcedMovementPath(path)
                    options.symbols.cast:RecordForcedMovementCreature(casterToken.charid)
				end

				casterToken:ClearMovementArrow()
			end

            if movementType == "teleport" then
                casterToken.properties:DispatchEvent("teleport")
            end

            local waypoints = {}

            --only include waypoints that don't coincide with the next target location.
            for i=1,#targets-1 do
                local s = targets[i].loc.str
                if s ~= targets[i+1].loc.str then
                    waypoints[#waypoints+1] = targets[i].loc
                end
            end


			local isVerticalSlideCast = (options.symbols.forcedmovement or ability:try_get("forcedMovement", "slide")) == "vertical_slide"

			--freeMovement mirrors the _tmp_freeMovement flag set at the top of Cast: an
			--ability-granted shift/move is not the creature's move action, so the engine must
			--not clamp it to the creature's remaining strict:movement budget. Without it, a
			--caster that already used its movement this turn has a negative budget and the
			--engine rejects the move outright (report 7BE97X9P).
			--forced tells the engine the creature is being pushed, pulled or slid. The engine
			--already spots a straight-line shove on its own; this covers a forced move aimed
			--around a corner, which walks its path like any other move.
			local path = casterToken:Move(targets[#targets].loc, { waypoints = waypoints, straightline = (ability.targeting == "straightline" or ability.targeting == "straightpath" or ability.targeting == "straightpathignorecreatures" or ability.targetType == "line"), moveThroughFriends = (ability.targeting ~= "straightline"), ignorecreatures = (ability.targeting == "straightpathignorecreatures" or ability.targetType == "line" or throughCreatures), maxCost = 30000, movementType = movementType, forcedMovementDistance = abilityDist, rebound = forcedPushOptions.rebound, maxBounces = forcedPushOptions.maxBounces, slide = isVerticalSlideCast, freeMovement = true, forced = (options.symbols.forcedmovement ~= nil or ability:try_get("forcedMovement") ~= nil) })

            --A nil path means the engine refused the move outright (no route, or a budget/legality
            --clamp). There is nothing to fall back on here, but the cast used to continue in total
            --silence and look like the relocate had happened, so make the failure traceable.
            if path == nil then
                print("Relocate:: MOVE REFUSED -- caster did not move. movementType =", movementType, "dest =", targets[#targets].loc.str, "ability =", ability.name)
            end

            --fire wallbreak events for any walls broken during the move
            --(wall erasure and rubble spawning are handled by the engine in TryStraightLineMove)
            if path ~= nil and path.wallBreaks ~= nil then
                for _,wb in ipairs(path.wallBreaks) do
                    casterToken.properties:TriggerEvent("wallbreak", {
                        speed = wb.staminaCost,
                        wallType = wb.solidity,
                        loc = wb.breakLoc,
                    })
                end
            end

            --make forced movement happen after the movement so they are in the new location.
            if forcemoveEvent ~= nil then
                --Expose how far the creature was actually moved and whether the forcing
                --ability had the Melee keyword, so triggered abilities (e.g. the Orc
                --Chainlock's "Chain Link") can react to melee forced movement and reuse
                --the distance. path.numSteps is the real distance moved -- it may be less
                --than requested if the path was blocked. ability is the forced-movement
                --clone, which InvokeAbility populates with the parent ability's keywords.
                forcemoveEvent.distance = math.floor((path ~= nil and path.numSteps) or 0)
                forcemoveEvent.melee = ability.keywords ~= nil and ability.keywords["Melee"] == true
                casterToken.properties:DispatchEvent("forcemove", forcemoveEvent)
            end

			if path ~= nil then
				options.symbols.cast.spacesMoved = options.symbols.cast.spacesMoved + path.numSteps
			end

			--when moving through creatures, trigger collision on each creature in the path.
			if throughCreatures and path ~= nil and path.steps ~= nil then
				local forcedMovementType = ability:try_get("forcedMovement", "slide")
				local hitCreatures = {}
				for _,step in ipairs(path.steps) do
					local tokensAtLoc = game.GetTokensAtLoc(step)
					for _,tok in ipairs(tokensAtLoc or {}) do
						if tok.id ~= casterToken.id and hitCreatures[tok.id] == nil then
							hitCreatures[tok.id] = true
							--see the note on suppressCollisionDamage below.
							local suppressPassthroughDamage = TargetableObject.TokenSuppressesCollisionDamage(tok)
							--each side of the collision gets a handle on the other:
							--the creature passed through sees the mover, the mover
							--sees the creature it passed through.
							tok.properties._tmp_forcedMovementCast = options.symbols.cast
							tok.properties:TriggerEvent("collide", {
								speed = 1,
								withobject = false,
								withcreature = true,
								nocollisiondamage = suppressPassthroughDamage,
								pusher = options.symbols.invoker,
								haspusher = options.symbols.invoker ~= nil,
								movementtype = forcedMovementType,
								target = casterToken.properties,
								hastarget = true,
								collidedwith = {casterToken.properties},
							})
							casterToken.properties._tmp_forcedMovementCast = options.symbols.cast
							casterToken.properties:TriggerEvent("collide", {
								speed = 1,
								withobject = false,
								withcreature = true,
								nocollisiondamage = suppressPassthroughDamage,
								pusher = options.symbols.invoker,
								haspusher = options.symbols.invoker ~= nil,
								movementtype = forcedMovementType,
								target = tok.properties,
								hastarget = true,
								collidedwith = {tok.properties},
							})
						end
					end
				end
			end

			--filter out passthrough creatures from collision.
		if collisionInfo ~= nil and collisionInfo.collideWith ~= nil and #collisionInfo.collideWith > 0 then
			local filtered = {}
			for _,tok in ipairs(collisionInfo.collideWith) do
				if tok.properties:CalculateNamedCustomAttribute("Passthrough") == 0 then
					filtered[#filtered+1] = tok
				end
			end
			collisionInfo.collideWith = filtered
			if #filtered == 0 then
				collisionInfo = nil
			end
		end

		if collisionInfo ~= nil then
                -- Keep the terminal post-passthrough creature collision on the
                -- cast so later behaviors can identify every participant.
                options.symbols.cast:RecordForcedMovementCreatureCollision(casterToken, collisionInfo.collideWith)

                local forcedMovementType = ability:try_get("forcedMovement", "slide")
                local withobject = #(collisionInfo.collideWith or {}) == 0

                local objectsCollidedWith = {}

                if not withobject then
                    for _,tok in ipairs(collisionInfo.collideWith or {}) do
                        if tok.isObject then
                            withobject = true
                            objectsCollidedWith[#objectsCollidedWith+1] = tok
                        end
                    end
                end
                --Objects flagged "No Collision Damage" run their own collision behavior
                --instead of the standard damage exchange, so neither side takes the
                --Collision global rule's damage. Only suppress when everything we hit is
                --such an object -- a mixed pile, or a plain wall (empty collideWith),
                --still deals normal damage.
                local suppressCollisionDamage = #(collisionInfo.collideWith or {}) > 0
                for _,tok in ipairs(collisionInfo.collideWith or {}) do
                    if not TargetableObject.TokenSuppressesCollisionDamage(tok) then
                        suppressCollisionDamage = false
                        break
                    end
                end

                --Expose what was actually hit. The mover sees everything it ran
                --into; each thing it ran into sees the mover. A wall collision
                --has an empty collideWith, so hastarget is false there and
                --Target is left nil rather than pointing at something wrong.
                local collidedWithProps = {}
                for _,tok in ipairs(collisionInfo.collideWith or {}) do
                    collidedWithProps[#collidedWithProps+1] = tok.properties
                end

                print("TRIGGERCOLLIDE:: objects =", #objectsCollidedWith, collisionInfo.speed, withobject, collisionInfo.collideWith)
                if casterToken.properties:CalculateNamedCustomAttribute("No Damage From Forced Movement") == 0 then
                    casterToken.properties._tmp_forcedMovementCast = options.symbols.cast
                    casterToken.properties:TriggerEvent("collide", {
                        speed = collisionInfo.speed,
                        withobject = withobject,
                        withcreature = not withobject,
                        nocollisiondamage = suppressCollisionDamage,
                        pusher = options.symbols.invoker,
                        haspusher = options.symbols.invoker ~= nil,
                        movementtype = forcedMovementType,
                        target = collidedWithProps[1],
                        hastarget = #collidedWithProps > 0,
                        collidedwith = collidedWithProps,
                    })
                end

                if casterToken.isObject and not TargetableObject.TokenSuppressesCollisionDamage(casterToken) then
                    --hard code damage equal to speed.
                    casterToken:ModifyProperties{
                        description = "Collision",
                        undoable = false,
                        execute = function()
                            casterToken.properties:InflictDamageInstance(collisionInfo.speed, "untyped", {}, "Collision", {})
                        end,
                    }
                end

				for _,tok in ipairs(collisionInfo.collideWith or {}) do
                    tok.properties._tmp_forcedMovementCast = options.symbols.cast
					tok.properties:TriggerEvent("collide", {
						speed = collisionInfo.speed,
                        withobject = withobject,
                        withcreature = not withobject,
                        nocollisiondamage = suppressCollisionDamage,
                        pusher = options.symbols.invoker,
                        haspusher = options.symbols.invoker ~= nil,
                        movementtype = forcedMovementType,
                        target = casterToken.properties,
                        hastarget = true,
                        collidedwith = {casterToken.properties},
					})
				end

                for _,tokobj in ipairs(objectsCollidedWith) do
                    local component = tokobj.objectComponent
                    if component ~= nil and component.properties ~= nil then
                        component.properties:OnCollide(casterToken, {
                            speed = collisionInfo.speed,
                            haspusher = options.symbols.invoker or false,
                            withobject = false,
                        })
                    end
                end
			end

			--handle collisions from rebound bounces.
			if path ~= nil and path.bounceCollisions ~= nil then
				local forcedMovementType = ability:try_get("forcedMovement", "slide")
				for _,collision in ipairs(path.bounceCollisions) do
					local collideWith = collision.collideWith or {}
					local withobject = #collideWith == 0

					if not withobject then
						for _,tok in ipairs(collideWith) do
							if tok.isObject then
								withobject = true
								break
							end
						end
					end

					--see the note on suppressCollisionDamage above.
					local suppressBounceDamage = #collideWith > 0
					for _,tok in ipairs(collideWith) do
						if not TargetableObject.TokenSuppressesCollisionDamage(tok) then
							suppressBounceDamage = false
							break
						end
					end

					--see the note on collidedWithProps above.
					local bounceCollidedWithProps = {}
					for _,tok in ipairs(collideWith) do
						bounceCollidedWithProps[#bounceCollidedWithProps+1] = tok.properties
					end

					casterToken.properties._tmp_forcedMovementCast = options.symbols.cast
					casterToken.properties:TriggerEvent("collide", {
						speed = collision.speed,
						withobject = withobject,
						withcreature = not withobject,
						nocollisiondamage = suppressBounceDamage,
						pusher = options.symbols.invoker,
						haspusher = options.symbols.invoker ~= nil,
						movementtype = forcedMovementType,
						target = bounceCollidedWithProps[1],
						hastarget = #bounceCollidedWithProps > 0,
						collidedwith = bounceCollidedWithProps,
					})

					for _,tok in ipairs(collideWith) do
						tok.properties._tmp_forcedMovementCast = options.symbols.cast
						tok.properties:TriggerEvent("collide", {
							speed = collision.speed,
							withobject = withobject,
							withcreature = not withobject,
							nocollisiondamage = suppressBounceDamage,
							pusher = options.symbols.invoker,
							haspusher = options.symbols.invoker ~= nil,
							movementtype = forcedMovementType,
							target = casterToken.properties,
							hastarget = true,
							collidedwith = {casterToken.properties},
						})
					end
				end
			end

            if path ~= nil and self.targetMoveVicinity then
                local targets = ability:FindTargetsInMovementVicinity(casterToken, path)
                if targets ~= nil then
                    local newTargets = {}
                    for i,target in ipairs(targets) do
                        newTargets[#newTargets+1] = {
                            token = target,
                        }
                    end

                    if options.originalTargets == nil then
                        options.originalTargets = table.shallow_copy(options.targets)
                    end

                    --don't just reassign options.targets, we want to destroy and recreate the table.
                    while #options.targets > 0 do
                        options.targets[#options.targets] = nil
                    end
                    for i,target in ipairs(newTargets) do
                        options.targets[i] = target
                    end

                    options.symbols.cast.targets = options.targets
                end

            end

            --Hand every square the creature moved through to the next behavior
            --(usually an aura) as a target area. The engine can only make an area
            --out of squares that touch side-by-side, not corner-to-corner, so a
            --diagonal step splits the trail into separate areas. A path with no
            --diagonal steps gives one single area.
            if path ~= nil and self.targetPassedSquares then
                local squares = ability:FindPassedSquareLocs(casterToken, path)
                if squares ~= nil and #squares > 0 then
                    --Group the squares into runs that touch side-by-side.
                    local segments = {}
                    local assigned = {}
                    for i = 1, #squares do
                        if not assigned[i] then
                            assigned[i] = true
                            local seg = { squares[i] }
                            local cursor = 1
                            while cursor <= #seg do
                                local cur = seg[cursor]
                                for j = 1, #squares do
                                    if not assigned[j] then
                                        local other = squares[j]
                                        if math.abs(cur.x - other.x) + math.abs(cur.y - other.y) == 1 then
                                            assigned[j] = true
                                            seg[#seg+1] = other
                                        end
                                    end
                                end
                                cursor = cursor + 1
                            end
                            segments[#segments+1] = seg
                        end
                    end

                    --Make one area shape per group. These are the same arguments wall
                    --targeting uses to build its area; leaving any of them out makes
                    --the engine shrink the area down to a single square. checklos is
                    --false so line of sight cannot remove squares the creature really
                    --walked through.
                    local areas = {}
                    for _, seg in ipairs(segments) do
                        local anchorLoc = seg[1]
                        areas[#areas+1] = dmhub.CalculateShape{
                            shape = "locations",
                            targetPoint = casterToken:PosAtLoc(anchorLoc),
                            token = casterToken,
                            range = #path.steps + 2,
                            radius = 0,
                            checklos = false,
                            locOverride = anchorLoc,
                            locations = seg,
                        }
                    end

                    if #areas == 1 then
                        options.targetArea = areas[1]
                    else
                        options.targetAreaList = areas
                    end
                end
            end
		end

        local opportunityAttacks = casterToken.properties._tmp_triggeredOpportunityAttacks - startingOpportunityAttacks
        options.symbols.cast.opportunityAttacksTriggered = options.symbols.cast.opportunityAttacksTriggered + opportunityAttacks

        self:ExpendMovementIfNeeded(casterToken)

        if chargeOptions == nil or (not options.pay and not options.abort) then
            ability:CommitToPaying(casterToken, options)
        end
    end

    casterToken.properties._tmp_freeMovement = false
end

function ActivatedAbilityRelocateCreatureBehavior:EditorItems(parentPanel)
	local result = {}
	--self:ApplyToEditor(parentPanel, result)
	--self:FilterEditor(parentPanel, result)

	result[#result+1] = gui.Panel{
		classes = {"formPanel"},
		gui.Label{
			classes = "formLabel",
			text = "Movement:",
		},

		gui.Dropdown{
			classes = "formDropdown",
			options = {
				{id = "teleport", text = "Teleport"},
				{id = "relocate", text = "Relocate"},
				{id = "move", text = "Move"},
				{id = "shift", text = "Shift"},
				{id = "jump", text = "Jump"},
			},
			idChosen = self.movementType,
			change = function(element)
				self.movementType = element.idChosen
			end,
		},
	}

	result[#result+1] = gui.Check{
		text = "Expend Full Movement",
		tooltip = "If set, the creature uses up all of its movement for the turn, no matter how many squares it actually moved.",
		value = self.expendFullMovement,
		change = function(element)
			self.expendFullMovement = element.value
		end,
	}

	result[#result+1] = gui.Check{
		text = "Swap Creatures",
		value = self.swapCreatures,
		change = function(element)
			self.swapCreatures = element.value
		end,
	}

	result[#result+1] = gui.Check{
		text = "Target Creatures in Move Vicinity",
        --tooltip = "If set, the targets set for this ability will be replaced with the creatures in the vicinity of the movement.",
		value = self.targetMoveVicinity,
		change = function(element)
			self.targetMoveVicinity = element.value
            parentPanel:FireEventTree("refreshVicinity")
		end,
	}

	result[#result+1] = gui.Check{
		text = "Target Each Square Passed Through",
		tooltip = "If set, the squares the creature moves through become the target area (including the starting square). Overrides Move Vicinity.",
		value = self.targetPassedSquares,
		change = function(element)
			self.targetPassedSquares = element.value
		end,
	}

    result[#result+1] = gui.Panel{
        classes = {"formPanel", cond(self.targetMoveVicinity, nil, "collapsed")},
        refreshVicinity = function(element)
            element:SetClass("collapsed", not self.targetMoveVicinity)
        end,
        gui.Label{
            classes = "formLabel",
            text = "Vicinity:",
        },
        gui.Input{
            classes = "formInput",
            characterLimit = 3,
            text = self.vicinity,
            change = function(element)
                self.vicinity = tonumber(element.text) or self.vicinity
                element.text = self.vicinity
            end,
        }
    }

    result[#result+1] = gui.Panel{
        classes = {"formPanel", cond(self.targetMoveVicinity, nil, "collapsed")},
        refreshVicinity = function(element)
            element:SetClass("collapsed", not self.targetMoveVicinity)
        end,
        gui.Label{
            classes = "formLabel",
            text = "Target Filter:",
        },
        gui.GoblinScriptInput{
            classes = "formInput",
            value = self.vicinityFilter,
            change = function(element)
                self.vicinityFilter = element.value
            end,

            documentation = {
                help = "This GoblinScript is used when you Relocate a creature and choose to add targets within the vicinity of the movement. It determines which targets within the vicinity will be added and which will not.",
                output = "boolean",
                examples = {
                    {
                        script = "enemy",
                        text = "Make the ability affect creatures that are enemies of the ability's caster.",
                    },
                    {
                        script = "not enemy and type is not undead",
                        text = "Make the ability affect creatures that are not enemies of the ability's caster. The ability won't affect undead creatures.",
                    },
                    {
                        script = "Target Number = 2",
                        text = "Make this behavior affect only the second target of the spell.",
                    },
                },
                subject = creature.helpSymbols,
                subjectDescription = "A creature in the ability's area of effect ",
                symbols = {
                    caster = {
                        name = "Caster",
                        type = "creature",
                        desc = "The caster of this spell.",
                    },
                    enemy = {
                        name = "Enemy",
                        type = "boolean",
                        desc = "True if the subject is an enemy of the creature casting the ability. Otherwise this is False.",
                    },
                    target = {
                        name = "Target",
                        type = "creature",
                        desc = "The target of this spell. This is the same as the subject of this GoblinScript.",
                    },
                    targetnumber = {
                        name = "Target Number",
                        type = "number",
                        desc = "1 for the first target, 2 for the second target, etc.",
                    },
                    numberoftargets = {
                        name = "Number of Targets",
                        type = "number",
                        desc = "The number of creatures this spell is targeting.",
                    },
                },
            },

        },
    }




	return result
end
