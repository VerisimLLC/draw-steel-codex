local mod = dmhub.GetModLoading()

RegisterGameType("ActivatedAbilityRelocateCreatureBehavior", "ActivatedAbilityBehavior")


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

ActivatedAbilityRelocateCreatureBehavior.summary = 'Relocate Creatures'
ActivatedAbilityRelocateCreatureBehavior.swapCreatures = false
ActivatedAbilityRelocateCreatureBehavior.targetMoveVicinity = false
ActivatedAbilityRelocateCreatureBehavior.vicinity = 0
ActivatedAbilityRelocateCreatureBehavior.vicinityFilter = ""
ActivatedAbilityRelocateCreatureBehavior.movementType = "teleport"

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

        local startingOpportunityAttacks = casterToken.properties._tmp_triggeredOpportunityAttacks

		local swapTokens = nil
		if self.swapCreatures then
			swapTokens = game.GetTokensAtLoc(targets[1].loc)
			if swapTokens ~= nil and ability.targetType == 'emptyspacefriend' and (not casterToken:IsFriend(swapTokens[1])) then
				--can only swap with friends.
				swapTokens = nil
			end
		end

		if swapTokens ~= nil then
			casterToken:SwapPositions(swapTokens[1])
		elseif movementType == "teleport" then
            local distance = casterToken:Distance(targets[1].loc)
            if distance > 0 then
			    options.symbols.cast.spacesMoved = options.symbols.cast.spacesMoved + distance
            end

            local loc = targets[1].loc
        	casterToken:Teleport(loc.withGroundAltitude)
        elseif movementType == "jump" then
		    local path = casterToken:Move(targets[#targets].loc, { ignoreFalling = true, straightline = true, moveThroughFriends = true, ignorecreatures = true, maxCost = 30000, movementType = "jump" })
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
			if (ability.targeting == "straightline" or ability.targetType == "line") and casterToken.properties:CalculateNamedCustomAttribute("No Damage From Forced Movement") == 0 then
				local movementInfo = casterToken:MarkMovementArrow(targets[1].loc, {waypoints = options.symbols.waypoints, straightline = true, ignorecreatures = (ability.targetType == "line")})
				if movementInfo ~= nil then

					local loc = targets[1].loc

					local path = movementInfo.path
                print("RELOCATE:: to", loc.x, loc.y, loc.altitude, "->", path.destination.x, path.destination.y, path.destination.altitude)
					local abilityDist = ability:GetRange(casterToken.properties)/dmhub.unitsPerSquare
					local requestDist = math.min(loc:DistanceInTiles(path.origin), abilityDist)
					local pathDist = path.destination:DistanceInTiles(path.origin)

                    local overshoot = 0
                    print("PATHFIND:: DIST =", pathDist, "requestDist=", requestDist)

					if pathDist < requestDist then
						overshoot = abilityDist - pathDist

						collisionInfo = {
							speed = overshoot,
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
                            collision = overshoot,
                            collidewithobject = overshoot > 0 and collisionInfo ~= nil and #(collisionInfo.collideWith or {}) == 0,
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


			local path = casterToken:Move(targets[#targets].loc, { waypoints = waypoints, straightline = (ability.targeting == "straightline" or ability.targeting == "straightpath" or ability.targeting == "straightpathignorecreatures" or ability.targetType == "line"), moveThroughFriends = (ability.targeting ~= "straightline"), ignorecreatures = (ability.targeting == "straightpathignorecreatures" or ability.targetType == "line"), maxCost = 30000, movementType = movementType })

            --make forced movement happen after the movement so they are in the new location.
            if forcemoveEvent ~= nil then
                casterToken.properties:DispatchEvent("forcemove", forcemoveEvent)
            end

			if path ~= nil then
				options.symbols.cast.spacesMoved = options.symbols.cast.spacesMoved + path.numSteps
			end

			if collisionInfo ~= nil then
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
                print("TRIGGERCOLLIDE:: objects =", #objectsCollidedWith, collisionInfo.speed, withobject, collisionInfo.collideWith)
				casterToken.properties:TriggerEvent("collide", {
					speed = collisionInfo.speed,
                    withobject = withobject,
                    withcreature = not withobject,
                    pusher = options.symbols.invoker,
                    haspusher = options.symbols.invoker ~= nil,
                    movementtype = forcedMovementType,
				})

                if casterToken.isObject then
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
					tok.properties:TriggerEvent("collide", {
						speed = collisionInfo.speed,
                        withobject = withobject,
                        withcreature = not withobject,
                        pusher = options.symbols.invoker,
                        haspusher = options.symbols.invoker ~= nil,
                        movementtype = forcedMovementType,
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
		end

        local opportunityAttacks = casterToken.properties._tmp_triggeredOpportunityAttacks - startingOpportunityAttacks
        options.symbols.cast.opportunityAttacksTriggered = options.symbols.cast.opportunityAttacksTriggered + opportunityAttacks

        ability:CommitToPaying(casterToken, options)
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
