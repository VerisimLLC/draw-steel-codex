local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityRelocateAuraBehavior:ActivatedAbilityBehavior
--- A selectable ability behavior that relocates one of the caster's placed auras (by name) to the
--- ability's targeted location. Mirrors the built-in "Can relocate" aura option (see
--- ActivatedAbilityMoveAuraBehavior in DMHub Game Rules/Aura.lua), but usable from any ability.
--- The host ability must use a point/area target type so that options.targetArea is populated.
--- @field summary string Short label shown in the behavior list in the ability editor.
--- @field auraName string Name of the caster's aura to relocate (matched against AuraInstance.name).
RegisterGameType("ActivatedAbilityRelocateAuraBehavior", "ActivatedAbilityBehavior")

-- Register this behavior so it can be selected and added to any ability in the ability editor.
ActivatedAbility.RegisterType{
    id = 'relocate_aura',
    text = 'Relocate Aura',
    createBehavior = function()
        return ActivatedAbilityRelocateAuraBehavior.new{ auraName = "" }
    end,
}

-- Default field values (see @field annotations above).
ActivatedAbilityRelocateAuraBehavior.summary = 'Relocate Aura'
ActivatedAbilityRelocateAuraBehavior.auraName = ""

--- Returns the human-readable summary shown for this behavior in the ability editor.
--- @param ability ActivatedAbility The ability that owns this behavior.
--- @param creatureLookup table Map of creature ids to creatures (unused here).
--- @return string
function ActivatedAbilityRelocateAuraBehavior:SummarizeBehavior(ability, creatureLookup)
    if self.auraName ~= "" then
        return string.format("Relocate aura: %s", self.auraName)
    end
    return "Relocate Aura"
end

--- Executes the behavior: finds the caster's placed aura matching auraName and moves it to the
--- ability's target location, replicating the slide animation used by the built-in relocate option.
--- Does not consume resources -- the host ability's normal cast/cost flow handles payment.
--- @param ability ActivatedAbility The ability being cast.
--- @param casterToken CharacterToken The token casting the ability (owns the aura).
--- @param targets table[] The ability's resolved targets (unused; we relocate to the target area).
--- @param options table Cast options; options.targetArea provides the destination (xpos/ypos).
--- @return nil
function ActivatedAbilityRelocateAuraBehavior:Cast(ability, casterToken, targets, options)
    -- Need a target location to move to, and a valid caster that can own auras.
    if options.targetArea == nil or casterToken == nil or casterToken.properties == nil then
        return
    end

    -- Find a matching placed aura owned by the caster. Try an exact name match first, then fall
    -- back to a case-insensitive match. Only auras that have actually been placed on the map
    -- (those with an "object" reference) can be relocated.
    local auras = casterToken.properties:try_get("auras", {})
    local match = nil
    local wanted = self.auraName
    for _, a in ipairs(auras) do
        if a.name == wanted and a:try_get("object") ~= nil then
            match = a
            break
        end
    end
    if match == nil then
        local lower = string.lower(wanted)
        for _, a in ipairs(auras) do
            if string.lower(a.name) == lower and a:try_get("object") ~= nil then
                match = a
                break
            end
        end
    end
    if match == nil then
        return
    end

    -- Resolve the placed map object that represents the aura.
    local obj = game.LookupObject(match.object.floorid, match.object.objid)
    if obj == nil then
        return
    end

    dmhub.BeginTransaction()

    -- Destination coordinates come from the ability's targeted area.
    local destx = options.targetArea.xpos
    local desty = options.targetArea.ypos
    local dx = destx - obj.x
    local dy = desty - obj.y

    -- Record the movement delta on the Aura component so the engine plays the slide animation
    -- from the old position to the new one.
    local objAura = obj:GetComponent("Aura")
    if objAura ~= nil then
        objAura:SetAndUploadProperties{
            moveTimestamp = dmhub.serverTime,
            movex = dx,
            movey = dy,
        }
    end

    -- Move the object to the destination and upload the change.
    obj:SetAndUploadPos(destx, desty)

    dmhub.EndTransaction()

    -- Moving the object only moves the VISUAL: the mechanical area lives in
    -- serialized AuraInstance copies on the object's Aura component (the one
    -- the engine registers) and in the caster's auras list. The shared helper
    -- in DMHub Game Rules/Aura.lua updates both, converting the area to an
    -- explicit-locations shape so the engine's recipe recompute cannot clamp
    -- it back toward the original cast position.
    ActivatedAbilityMoveAuraBehavior.SetCasterAuraArea(obj, options.targetArea)
end

--- Builds the editor UI for this behavior: a single text input for the aura's name.
--- @param parentPanel Panel The parent editor panel (unused here).
--- @return Panel[] The list of editor panels to display.
function ActivatedAbilityRelocateAuraBehavior:EditorItems(parentPanel)
    local result = {}
    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Aura Name:" },
        gui.Input{
            classes = { "formInput" },
            text = self:try_get("auraName", ""),
            placeholderText = "Name of the aura to move",
            change = function(element)
                self.auraName = element.text
            end,
        },
    }
    return result
end

--- @class ActivatedAbilityPortalTransitBehavior:ActivatedAbilityBehavior
--- Fired from a portal aura's "onenter" trigger (see Aura.TriggerConditions in
--- DMHub Game Rules/Aura.lua). The creature that stepped onto the portal is offered every
--- unoccupied square adjacent to any OTHER portal aura of the same name owned by the same
--- creature, and teleports to whichever square it picks. Declining leaves it standing on
--- the portal it entered.
---
--- Used by the Elementalist Void subclass ability "There Is No Space Between". This replaces
--- the engine's ObjectComponentTeleporter, which teleports blind: it offers no destination
--- choice and has no Lua surface to hook.
--- @field summary string Short label shown in the behavior list in the ability editor.
--- @field auraName string Name of the portal aura to link (matched against the placed aura's name).
RegisterGameType("ActivatedAbilityPortalTransitBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType{
    id = "portal_transit",
    text = "Portal Transit",
    createBehavior = function()
        return ActivatedAbilityPortalTransitBehavior.new{ auraName = "" }
    end,
}

ActivatedAbilityPortalTransitBehavior.summary = "Portal Transit"
ActivatedAbilityPortalTransitBehavior.auraName = ""

--- Every placed portal of the given aura name anywhere on the map, read straight off the
--- map objects.
---
--- The network is floor-agnostic: portals connect to each other, not to a floor, and a pair
--- opened on two different floors has to link. Each record carries its OWN floor, because
--- every consumer below keys squares on xyfloorOnly.str.
---
--- The map is deliberately the source of truth here rather than the trigger's "aura"
--- symbol or the owner's aura list. An aura trigger can be handed to the controlling
--- client, and SendTriggerCastToController (DMHub Game Rules/TriggeredAbility.lua)
--- serializes symbols by unwrapping each closure with v("self"). AuraInstance.lookupSymbols
--- has no "self" key, so the "aura" symbol is silently dropped in transit and is nil on the
--- receiving machine -- which is precisely the case where somebody else moved the token.
--- Map objects are present and identical on every client.
--- @param auraName string Aura name to match (case-insensitive).
--- @return table[] A list of { loc = Loc, casterid = string }.
local function CollectPortals(auraName)
    local result = {}
    if auraName == "" then
        return result
    end

    local wanted = string.lower(auraName)
    for _, floor in ipairs(game.currentMap.floors) do
        for _, obj in pairs(floor.objects) do
            if obj.valid then
                local component = obj:GetComponent("Aura")
                local props = nil
                if component ~= nil then
                    props = component.properties
                end

                local auraInstance = nil
                if props ~= nil then
                    auraInstance = props:try_get("aura")
                end

                if auraInstance ~= nil and string.lower(auraInstance:try_get("name", "")) == wanted then
                    -- core.Loc carries no floor of its own, so WithDifferentFloor is the only
                    -- thing that sets one, and it must be the OBJECT's floor.
                    local portalLoc = core.Loc{
                        x = math.floor(obj.x + 0.5),
                        y = math.floor(obj.y + 0.5),
                    }:WithDifferentFloor(obj.floorIndex)

                    -- A placed object stores no elevation of its own: LuaObjectInstance exposes
                    -- only x/y/floorIndex, and the aura's shape altitude is not bound to Lua. A
                    -- portal sits on the ground, so its elevation is the ground altitude of its
                    -- square (altitude is measured in whole tiles).
                    result[#result+1] = {
                        loc = portalLoc,
                        altitude = portalLoc.withGroundAltitude.altitude,
                        casterid = props:try_get("casterid"),
                        -- Key the engine uses to remember which auras a creature has already
                        -- entered this turn; see ForgetPortalEntries.
                        auraGuid = auraInstance:try_get("guid"),
                    }
                end
            end
        end
    end

    return result
end

--- True if `travelToken` could come to rest at `loc`: every square it would occupy there is
--- on the map, free of other tokens, and clear of any portal. Size-aware, so a size 2
--- creature is never offered a square it cannot actually fit in.
--- @param travelToken CharacterToken The creature that would move there.
--- @param loc Loc The candidate anchor location.
--- @param portalSquares table<string, boolean> Set of portal squares, keyed by xyfloorOnly.str.
--- @return boolean
local function LocIsFreeFor(travelToken, loc, portalSquares)
    local locs = travelToken:LocsOccupyingWhenAt(loc)
    if locs == nil or #locs == 0 then
        return false
    end

    for _, occLoc in ipairs(locs) do
        if not occLoc.isOnMap then
            return false
        end

        -- Never come to rest overlapping a portal. Checking every occupied square rather
        -- than just the anchor matters for size 2+ creatures: one offered a square beside
        -- portal B can still cover portal C with a far quadrant, which would immediately
        -- offer it another trip and chain across the network.
        if portalSquares[occLoc.xyfloorOnly.str] then
            return false
        end

        for _, tok in ipairs(dmhub.GetTokensAtLoc(occLoc) or {}) do
            if tok.id ~= travelToken.id then
                return false
            end
        end
    end

    return true
end

--- The unoccupied squares adjacent to every portal the creature is NOT currently standing on.
--- A portal's own square is never a destination: the rule is an empty space adjacent to one,
--- and landing on a portal would immediately offer another trip.
---
--- Destinations are scoped to the network the creature actually stepped into: the portal
--- under its feet identifies the owner, and only that owner's portals are offered. Without
--- this, two Elementalists' portals on the same map would link into one network.
--- @param travelToken CharacterToken The transiting creature.
--- @param portals table[] All placed portals as { loc, casterid }.
--- @param standingLocs Loc[] The squares the transiting creature currently occupies.
--- @param originPortal nil|table The portal being travelled OUT of. Defaults to whichever portal
--- the creature is standing on. Passed explicitly by the touch path, where the creature stands
--- BESIDE the portal rather than on it, so there is no portal underfoot to infer it from.
--- @return Loc[] candidates, nil|table originPortal The portal departed from, if any.
local function BuildTransitCandidates(travelToken, portals, standingLocs, originPortal)
    local occupiedByUs = {}
    for _, loc in ipairs(standingLocs or {}) do
        occupiedByUs[loc.xyfloorOnly.str] = true
    end

    local portalSquares = {}
    local underfoot = originPortal
    local ownerid = nil
    if underfoot ~= nil then
        ownerid = underfoot.casterid
    end

    for _, portal in ipairs(portals) do
        local key = portal.loc.xyfloorOnly.str
        portalSquares[key] = true
        if occupiedByUs[key] and underfoot == nil then
            underfoot = portal
            ownerid = portal.casterid
        end
    end

    local originKey = nil
    if underfoot ~= nil then
        originKey = underfoot.loc.xyfloorOnly.str
    end

    local destinations = {}
    for _, portal in ipairs(portals) do
        local key = portal.loc.xyfloorOnly.str
        -- You never come out of the portal you went in by, whether you were standing on it or
        -- touching it from an adjacent square.
        local isOrigin = occupiedByUs[key] or (originKey ~= nil and key == originKey)
        local sameNetwork = (ownerid == nil) or (portal.casterid == ownerid)
        if (not isOrigin) and sameNetwork then
            destinations[#destinations+1] = portal
        end
    end

    local seen = {}
    local result = {}
    for _, portal in ipairs(destinations) do
        for _, loc in ipairs(portal.loc:LocsInRadius(1)) do
            local key = loc.xyfloorOnly.str
            if not seen[key] then
                seen[key] = true
                if LocIsFreeFor(travelToken, loc, portalSquares) then
                    result[#result+1] = loc
                end
            end
        end
    end

    return result, underfoot
end

--- The elevation a creature should emerge at when it steps out beside `loc`: the elevation of
--- the portal it came out of. Portals store no altitude of their own, so this is the ground
--- under each portal, recorded by CollectPortals.
---
--- A square can border more than one portal, and the design has no "choose which portal" step,
--- so the ambiguity is resolved with the LOWEST bordering portal. Emerging high is not
--- recoverable -- it drops the creature and deals falling damage nobody chose -- whereas
--- emerging low is harmless and is then clamped up to the destination's own ground anyway.
--- This matches the direction the pit clamp in PerformTransit already resolves ties.
---
--- The floor is compared explicitly because DistanceInTiles measures the lateral (x/y)
--- dimensions ONLY (see the teleport-cost note in Draw Steel UI/DSHud.lua). The network
--- spans floors, so without it a portal directly overhead reads as adjacent and donates its
--- altitude to an emergence on another floor. FloorDifference rather than a floor equality
--- test: a portal on a layer of the destination's floor is still on that floor.
--- @param portals table[] All placed portals as { loc, altitude, casterid }.
--- @param loc Loc The chosen destination square.
--- @return nil|number
local function EmergeAltitudeFor(portals, loc)
    local result = nil
    for _, portal in ipairs(portals) do
        if portal.altitude ~= nil and portal.loc:FloorDifference(loc) == 0 and portal.loc:DistanceInTiles(loc) <= 1 then
            if result == nil or portal.altitude < result then
                result = portal.altitude
            end
        end
    end

    return result
end

--- Resolve the creature that actually travels: the one that stepped onto the portal.
---
--- This is deliberately NOT the ability's `casterToken`. For an aura-sourced trigger the cast
--- is re-attributed to the aura's OWNER partway through -- verified live: an ally entering a
--- portal reaches this behavior with casterToken = the Elementalist who placed it, while
--- `targets[1]` and the `target` symbol both remain the creature that entered. That is why
--- shipping aura triggers (e.g. the Hobgoblin Bloodlord's "Skulls Abound") apply their effects
--- to targets rather than to the caster.
--- @param casterToken CharacterToken Last-resort fallback.
--- @param targets table[] The ability's resolved targets.
--- @param options table Cast options.
--- @return nil|CharacterToken
local function ResolveTravellerToken(casterToken, targets, options)
    for _, target in ipairs(targets or {}) do
        if target.token ~= nil and target.token.valid then
            return target.token
        end
    end

    if options ~= nil and options.symbols ~= nil then
        local entering = options.symbols.target
        if type(entering) == "function" then
            entering = entering("self")
        end

        if entering ~= nil then
            local token = dmhub.LookupToken(entering)
            if token ~= nil and token.valid then
                return token
            end
        end
    end

    return casterToken
end

--- Prompt the transiting creature's controller to pick one of `candidates`, returning the
--- chosen Loc or nil if it was cancelled. Mirrors the restrict-to-squares pick used by the
--- wall shift in AbilityBuildWall.lua (whose helper is file-local, so it is reimplemented
--- here rather than called).
---
--- _tmp_restrictLocs only replaces the ability's target-loc FILTER predicate; the targeting
--- reticle is still bounded by the ability's range, and ActivatedAbility.range defaults to a
--- single square. Range is therefore derived from the furthest candidate, otherwise a portal
--- placed across the map would be unreachable.
--- @param travelToken CharacterToken The transiting creature.
--- @param candidates Loc[] The squares that may be chosen.
--- @param symbols table GoblinScript symbols to pass through to the invoke.
--- @param chooserToken nil|CharacterToken Who makes the choice; defaults to the traveller. Only
--- the invoker slot varies -- the cast must stay centred on the traveller, because the candidate
--- squares cluster around the far portal and the reticle's range is measured from the caster.
--- @param labels nil|{name: string, prompt: string} Optional pick-ability name and prompt text,
--- so a non-portal caller (e.g. the hurl behavior below) does not talk about emerging from a portal.
--- @return nil|Loc
local function ChooseTransitDestination(travelToken, candidates, symbols, chooserToken, labels)
    labels = labels or {}
    local capturedLoc = nil

    --- Resolve a picked square back onto the candidate it represents, so the FLOOR comes from
    --- the candidate rather than from the click.
    ---
    --- The map hands back a loc on whichever floor the click resolved against, and for a player
    --- that is their own token's floor: "look up" is a view overlay, not a change of the
    --- interactive floor, so clicking a highlighted square one floor UP returns those x/y
    --- coordinates stamped with the traveller's floor. Teleporting there leaves them where they
    --- started. Clicking DOWN happens to work because lower floors are part of the same
    --- rendered stack and resolve to their own floor.
    ---
    --- An exact match wins outright. Otherwise a unique x/y match identifies the square
    --- unambiguously and its floor is trusted over the click's. Anything else (no match, or the
    --- same x/y offered on two floors at once) is left exactly as picked rather than guessed at.
    --- @param picked nil|Loc
    --- @param candidateLocs Loc[]
    --- @return nil|Loc
    local function SnapToCandidate(picked, candidateLocs)
        if picked == nil then
            return nil
        end

        local match = nil
        local matchCount = 0
        for _, candidate in ipairs(candidateLocs) do
            if candidate.x == picked.x and candidate.y == picked.y then
                if candidate.floor == picked.floor then
                    return candidate
                end

                match = candidate
                matchCount = matchCount + 1
            end
        end

        if matchCount == 1 then
            return match
        end

        return picked
    end

    local captureBehavior = ActivatedAbilityBehavior.new{
        instant = true,
    }
    captureBehavior.Cast = function(behaviorSelf, captureAbility, captureCasterToken, captureTargets, captureOptions)
        if captureTargets ~= nil and #captureTargets > 0 then
            capturedLoc = captureTargets[1].loc
        end
    end

    local maxDist = 1
    for _, loc in ipairs(candidates) do
        local dist = loc:DistanceInTiles(travelToken.loc)
        if dist > maxDist then
            maxDist = dist
        end
    end

    local pickAbility = ActivatedAbility.Create()
    pickAbility.name = labels.name or "Portal Transit"
    pickAbility.targetType = "emptyspace"
    pickAbility.range = tostring((maxDist + 1) * dmhub.unitsPerSquare)
    pickAbility.numTargets = "1"
    pickAbility.countsAsCast = false
    pickAbility.skippable = true
    pickAbility.promptOverride = labels.prompt or "Choose where you emerge"
    pickAbility.behaviors = { captureBehavior }
    pickAbility._tmp_restrictLocs = candidates

    -- The cast is always centred on the traveller (that is what the reticle and range use, and
    -- what a nil-return cancel leaves in place). Only the INVOKER varies, which is what feeds
    -- the AI auto-answer callback and the invoke symbols. The prompt itself opens on whichever
    -- client is running this code, so callers must already be executing there.
    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(chooserToken or travelToken, pickAbility, travelToken, "prompt", symbols or {}, {})

    return SnapToCandidate(capturedLoc, candidates)
end

--- Forget that this creature has entered these portals this turn.
---
--- The engine only lets a creature trigger a given aura ONCE per turn: `creature:EnterAura`
--- records the aura in `aurasEntered`, and `creature:EnterAuraHaltsMovement` then refuses to halt
--- or re-fire for it (DMHub Game Rules/creature.lua). That is right for a damage aura ("the first
--- time in a round or when it starts its turn there") but wrong for a portal, which should work
--- every time somebody steps on it.
---
--- Clearing only the portal auras leaves the once-per-turn rule intact for every other aura.
--- `aurasEntered` is real persisted state, so the edit goes through ModifyProperties.
--- @param travelToken CharacterToken
--- @param portals table[] All placed portals as returned by CollectPortals.
--- @return nil
local function ForgetPortalEntries(travelToken, portals)
    local entered = travelToken.properties:try_get("aurasEntered")
    if entered == nil then
        return
    end

    local stale = false
    for _, portal in ipairs(portals) do
        if portal.auraGuid ~= nil and entered[portal.auraGuid] ~= nil then
            stale = true
            break
        end
    end

    if not stale then
        return
    end

    travelToken:ModifyProperties{
        description = "Portal Re-entry",
        undoable = false,
        execute = function()
            local live = travelToken.properties:try_get("aurasEntered")
            if live == nil then
                return
            end

            for _, portal in ipairs(portals) do
                if portal.auraGuid ~= nil then
                    live[portal.auraGuid] = nil
                end
            end
        end,
    }
end

--- Prompt for a destination and move the creature there. Shared by both entry points: the
--- voluntary path (traveller chooses) and the forced path (pusher chooses).
--- @param travelToken CharacterToken The creature that travels.
--- @param portals table[] All placed portals.
--- @param candidates Loc[] The squares that may be chosen.
--- @param symbols table GoblinScript symbols to pass through to the invoke.
--- @param chooserToken nil|CharacterToken Who picks; defaults to the traveller.
--- @return boolean True if the creature actually transited.
local function PerformTransit(travelToken, portals, candidates, symbols, chooserToken)
    if candidates == nil or #candidates == 0 then
        return false
    end

    local destLoc = ChooseTransitDestination(travelToken, candidates, symbols, chooserToken)
    if destLoc == nil then
        -- Cancelled: stay standing on the portal.
        return false
    end

    -- Emerge at the elevation of the portal stepped out of, not at the ground under the chosen
    -- square. Clamped up to that square's own ground so a portal in a pit never buries the
    -- creature; a portal on a clifftop leaves them in mid-air over the drop.
    local groundLoc = destLoc.withGroundAltitude
    local targetAltitude = groundLoc.altitude
    local portalAltitude = EmergeAltitudeFor(portals, destLoc)
    if portalAltitude ~= nil and portalAltitude > targetAltitude then
        targetAltitude = portalAltitude
    end

    local teleportLoc = groundLoc:WithAltitude(targetAltitude)

    -- Mark the hop as free movement so the teleport is not billed against whatever movement the
    -- creature has left. Saved and restored rather than cleared outright so this never stomps a
    -- value an enclosing flow is relying on.
    local originLoc = travelToken.loc

    local previousFreeMovement = travelToken.properties:try_get("_tmp_freeMovement", false)
    travelToken.properties._tmp_freeMovement = true
    travelToken:Teleport(teleportLoc)
    travelToken.properties._tmp_freeMovement = previousFreeMovement

    -- Arriving on a floor ABOVE the one departed leaves the "look up" view (FloorNavigation.
    -- LookRelative, DMHub Core Panels/Floors.lua) pointing one or more floors past where the
    -- creature now stands: the offset is measured from whatever floor the token is on, and it
    -- was raised to see the destination in the first place. Drop back to Forward so the view
    -- lands on the floor just arrived at.
    --
    -- "lookup" is a client-local VIEW setting, not token state, so this is applied only on the
    -- client whose own token travelled. The forced path runs on the PUSHER's client, where
    -- resetting the view because somebody else moved would be wrong.
    if originLoc:FloorDifference(teleportLoc) > 0 then
        local localToken = dmhub.currentToken
        if localToken ~= nil and localToken.id == travelToken.id and dmhub.GetSettingValue("lookup") ~= 0 then
            dmhub.SetSettingValue("lookup", 0)
        end
    end

    -- Emerging above the ground means falling; the engine does not resolve that on its own.
    -- Structured exactly like the teleport branch of DMHub Game Rules/AbilityRelocateCreature.lua:
    -- only the settle wait is conditional, while TryFall is called unconditionally because it
    -- already self-noops for a grounded or flying creature. The wait gives the teleport a full
    -- game update (plus a short beat, hard capped) to commit the token to the air, otherwise the
    -- falling rules read stale state.
    if teleportLoc.altitude > groundLoc.altitude then
        local updateAtTeleport = dmhub.ngameupdate
        local startTime = dmhub.Time()
        while (dmhub.ngameupdate <= updateAtTeleport or dmhub.Time() < startTime + 0.5) and dmhub.Time() < startTime + 2 do
            coroutine.yield(0.1)
        end
    end

    if travelToken.valid then
        travelToken:TryFall()
    end

    return true
end

--- Returns the human-readable summary shown for this behavior in the ability editor.
--- @param ability ActivatedAbility The ability that owns this behavior.
--- @param creatureLookup table Map of creature ids to creatures (unused here).
--- @return string
function ActivatedAbilityPortalTransitBehavior:SummarizeBehavior(ability, creatureLookup)
    local auraName = self:try_get("auraName", "")
    if auraName ~= "" then
        return string.format("Portal transit between: %s", auraName)
    end
    return "Portal Transit"
end

--- Offers the entering creature a trip to a square beside one of the owner's other portals.
--- @param ability ActivatedAbility The triggered ability being cast.
--- @param casterToken CharacterToken The ability's caster -- for an aura trigger this is the
--- portal's OWNER, not the creature that entered. See ResolveTravellerToken.
--- @param targets table[] Resolved targets (unused; the caster is the one who travels).
--- @param options table Cast options; options.symbols.aura identifies the portal's owner.
--- @return nil
function ActivatedAbilityPortalTransitBehavior:Cast(ability, casterToken, targets, options)
    local travelToken = ResolveTravellerToken(casterToken, targets, options)
    if travelToken == nil or (not travelToken.valid) or travelToken.properties == nil then
        return
    end

    -- This trigger fires on ANY entry into the portal square, so a creature that was SHOVED in
    -- looks identical to one that walked in. Only allies reach here (the aura's creatureFilter
    -- excludes enemies), and an ally who was force moved must NOT be teleported -- the movement
    -- was not theirs to choose. Enemies are handled separately by TryForcedTransit below, where
    -- the pusher gets the choice.
    --
    -- The forced-movement wrapper in Draw Steel Core Rules/MCDMAbilityBehavior.lua records the
    -- square a shove ended on; this cast is deferred until after that wrapper returns, so the
    -- marker is read (and consumed) here rather than being a flag held across the move.
    local forcedDest = travelToken.properties:try_get("_tmp_portalForcedMoveDest")
    local wasShovedHere = false
    if forcedDest ~= nil then
        travelToken.properties._tmp_portalForcedMoveDest = nil
        wasShovedHere = forcedDest == travelToken.loc.xyfloorOnly.str
    end

    local portals = CollectPortals(self:try_get("auraName", ""))

    -- Lift the engine's once-per-turn-per-aura lock off the portals, so a creature can keep using
    -- them. Done before the shove check as well: an ally who was shoved onto a portal still
    -- registered the entry, and without this they could not walk into that portal again this turn.
    ForgetPortalEntries(travelToken, portals)

    if wasShovedHere then
        return
    end

    if #portals < 2 then
        -- A lone portal is a dead end: there is nowhere to emerge.
        return
    end

    local symbols = {}
    if options ~= nil and options.symbols ~= nil then
        symbols = options.symbols
    end

    local standingLocs = travelToken:LocsOccupyingWhenAt(travelToken.loc)
    local candidates = BuildTransitCandidates(travelToken, portals, standingLocs)
    PerformTransit(travelToken, portals, candidates, symbols, nil)
end

--Name of the portal aura used by the forced-movement entry point below. The behavior itself
--takes a configurable auraName, but the forced-movement hook has no behavior instance to read
--from, so the Void Portal name is fixed here. If the aura is ever renamed or reskinned, this
--must be kept in step with the behavior's auraName in the subclass YAML, or forced transit
--silently stops working while voluntary transit keeps going.
local PORTAL_AURA_NAME = "Void Portal"

--- Namespace for entry points called from outside this file.
--- Declared with rawget because reading an undeclared global raises in this runtime.
DrawSteelPortalTransit = rawget(_G, "DrawSteelPortalTransit") or {}

--- Offer a portal transit to a creature that was FORCE MOVED onto a portal.
---
--- Called from the forced-movement wrapper in Draw Steel Core Rules/MCDMAbilityBehavior.lua once
--- the move has completed, so "came to rest on a portal" is directly observable -- at aura-entry
--- time it is not, because the only live signals there cannot distinguish a push from a walk
--- (`_tmp_lastpusher` is never cleared anywhere, and `_tmp_forcedMovementCast` is set only after
--- the move returns).
---
--- That wrapper runs inside the PUSHING ability's own cast, i.e. already on the pusher's client,
--- which is why the picker opens for the right player with no remote-invoke machinery.
---
--- Restricted to ENEMIES of the portal's owner. Allies are served by the aura's `onenter`
--- trigger and pick their own exit, so this gate is also what stops both paths firing for a
--- single move.
--- @param movedToken CharacterToken The creature that was force moved.
--- @param pusherToken nil|CharacterToken The creature that forced the movement; it chooses.
--- @param originLoc nil|Loc Where the creature stood BEFORE the forced move.
--- @return nil
function DrawSteelPortalTransit.TryForcedTransit(movedToken, pusherToken, originLoc)
    if movedToken == nil or (not movedToken.valid) or movedToken.properties == nil then
        return
    end

    -- The rule is "force moved INTO a portal", so the move has to have actually put them there.
    -- Without this a creature left standing on a portal (say it declined a previous transit) is
    -- offered a fresh free teleport by every later push that moves it zero squares.
    if originLoc == nil or originLoc:Equals(movedToken.loc) then
        return
    end

    -- The pusher is the one who chooses. With no identifiable pusher there is nobody to make
    -- that choice, and defaulting it to the moved creature would hand an enemy a free escape.
    if pusherToken == nil or (not pusherToken.valid) then
        return
    end

    local portals = CollectPortals(PORTAL_AURA_NAME)
    if #portals < 2 then
        -- A lone portal is a dead end: there is nowhere to emerge.
        return
    end

    local standingLocs = movedToken:LocsOccupyingWhenAt(movedToken.loc)
    local candidates, underfoot = BuildTransitCandidates(movedToken, portals, standingLocs)
    if underfoot == nil or #candidates == 0 then
        -- The push ended somewhere other than a portal, or there is nowhere legal to emerge.
        return
    end

    -- Only enemies of the portal's OWNER transit this way. Allies are served by the aura's
    -- onenter trigger and pick their own exit, so this gate is also what stops both paths
    -- firing for a single move. Deliberately mirrors the aura's creatureFilter
    -- ("Self = Caster or Self.IsFriend(Caster)") rather than using IsFriendForTargeting: the
    -- targeting helper honours "Count Allies as Enemies", which would disagree with the filter
    -- and let both paths fire at once.
    local ownerToken = nil
    if underfoot.casterid ~= nil then
        ownerToken = dmhub.GetTokenById(underfoot.casterid)
    end

    if ownerToken == nil or (not ownerToken.valid) then
        return
    end

    if ownerToken.id == movedToken.id or ownerToken:IsFriend(movedToken) then
        return
    end

    PerformTransit(movedToken, portals, candidates, {}, pusherToken)
end

--- Builds the editor UI for this behavior: a single text input for the portal aura's name.
--- @param parentPanel Panel The parent editor panel (unused here).
--- @return Panel[] The list of editor panels to display.
function ActivatedAbilityPortalTransitBehavior:EditorItems(parentPanel)
    local result = {}
    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Portal Aura Name:" },
        gui.Input{
            classes = { "formInput" },
            text = self:try_get("auraName", ""),
            placeholderText = "Name of the portal aura",
            change = function(element)
                self.auraName = element.text
            end,
        },
    }
    return result
end

--- @class ActivatedAbilityHurlGrabbedBehavior:ActivatedAbilityBehavior
--- Throws a creature the caster is grabbing down a line ability (Ogre Goon "People Bowling").
--- Runs with applyto = caster on a line-targeted ability, BEFORE its power roll:
---   1. picks the grabbed creature (prompting only if several pass hurlFilter),
---   2. ends the grab and teleports it to the last square of the line, or to the nearest
---      unoccupied square around that end (a prompt when there is more than one nearest square),
---   3. appends it to the cast's target list so the power roll that follows rolls against it too.
--- Lives in this file to reuse ChooseTransitDestination (the restrict-to-squares pick), which is
--- file-local. It is NOT forced movement: no stability, no collision, no distance reduction.
--- @field hurlFilter string GoblinScript on the grabbed creature; only creatures passing it can be hurled.
--- @field searchRadius number How far (squares) around the line's end to look for a free landing square.
--- @field addAsTarget boolean Append the hurled creature to the cast's targets for later behaviors.
--- @field promptText string Prompt shown when the director must choose between equally near squares.
RegisterGameType("ActivatedAbilityHurlGrabbedBehavior", "ActivatedAbilityBehavior")

ActivatedAbility.RegisterType{
    id = 'hurl_grabbed',
    text = 'Hurl Grabbed Creature',
    createBehavior = function()
        return ActivatedAbilityHurlGrabbedBehavior.new{
            applyto = "caster",
        }
    end,
}

ActivatedAbilityHurlGrabbedBehavior.summary = 'Hurl Grabbed Creature'
ActivatedAbilityHurlGrabbedBehavior.hurlFilter = "Size < 5"
ActivatedAbilityHurlGrabbedBehavior.searchRadius = 3
ActivatedAbilityHurlGrabbedBehavior.addAsTarget = true
ActivatedAbilityHurlGrabbedBehavior.promptText = "Choose where the hurled creature lands"

--The Grabbed condition id (same constant as Creature.lua / AbilityRelocateCreature.lua).
local g_hurlGrabbedConditionId = "70504ebe-3899-41d3-9f60-74b52ce35e39"

--- @param ability ActivatedAbility
--- @param creatureLookup table
--- @return string
function ActivatedAbilityHurlGrabbedBehavior:SummarizeBehavior(ability, creatureLookup)
    return "Hurl a grabbed creature to the end of the line"
end

--- The creatures the caster is grabbing that pass hurlFilter.
--- @param casterToken CharacterToken
--- @return CharacterToken[]
function ActivatedAbilityHurlGrabbedBehavior:FindGrabbedCandidates(casterToken)
    local result = {}
    local filter = self:try_get("hurlFilter", "")
    casterToken.properties:VisitConditionCasterSource(function(conditionid, grabbedTok)
        if conditionid ~= g_hurlGrabbedConditionId or grabbedTok == nil or (not grabbedTok.valid) then
            return
        end
        local passes = true
        if filter ~= "" then
            local value = ExecuteGoblinScript(filter, grabbedTok.properties:LookupSymbol({}), 1, "Hurl grabbed filter")
            passes = GoblinScriptTrue(value)
        end
        if passes then
            result[#result+1] = grabbedTok
        end
    end)
    return result
end

--- Ask the caster's controller which grabbed creature to throw when more than one qualifies.
--- Returns nil if the prompt was cancelled.
--- @param casterToken CharacterToken
--- @param candidates CharacterToken[]
--- @param symbols table
--- @return nil|CharacterToken
local function ChooseHurledCreature(casterToken, candidates, symbols)
    local allowed = {}
    for _, tok in ipairs(candidates) do
        allowed[tok.charid] = true
    end

    local chosen = nil
    local captureBehavior = ActivatedAbilityBehavior.new{ instant = true }
    captureBehavior.Cast = function(behaviorSelf, captureAbility, captureCasterToken, captureTargets, captureOptions)
        for _, t in ipairs(captureTargets or {}) do
            if t.token ~= nil and allowed[t.token.charid] then
                chosen = t.token
            end
        end
    end

    local pickAbility = ActivatedAbility.Create()
    pickAbility.name = "Hurl Grabbed Creature"
    pickAbility.targetType = "target"
    pickAbility.range = "2"
    pickAbility.numTargets = "1"
    pickAbility.countsAsCast = false
    pickAbility.skippable = true
    pickAbility.objectTarget = true
    pickAbility.targetFilter = 'ConditionCaster("Grabbed") = Caster'
    pickAbility.promptOverride = "Choose the grabbed creature to hurl"
    pickAbility.behaviors = { captureBehavior }
    --Transient list the Monster AI prompt handler (MonsterAIPrompts.lua) picks from.
    pickAbility._tmp_hurlCandidates = candidates

    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(casterToken, pickAbility, casterToken, "prompt", symbols, {})
    return chosen
end

--- True if `hurledToken` could come to rest at `loc`: every square of its footprint is on the
--- map and holds no other token. Size-aware like LocIsFreeFor above (which is portal-specific).
--- @param hurledToken CharacterToken
--- @param loc Loc
--- @return boolean
local function LocIsFreeForHurl(hurledToken, loc)
    local locs = hurledToken:LocsOccupyingWhenAt(loc)
    if locs == nil or #locs == 0 then
        return false
    end
    for _, occLoc in ipairs(locs) do
        if not occLoc.isOnMap then
            return false
        end
        for _, tok in ipairs(dmhub.GetTokensAtLoc(occLoc) or {}) do
            if tok.id ~= hurledToken.id then
                return false
            end
        end
    end
    return true
end

--- The last square of the line: the one furthest from the caster (matches how
--- ActivatedAbilityRelocateCreatureBehavior finds the end of a line).
--- @param casterToken CharacterToken
--- @param targetArea table|nil options.targetArea of the cast.
--- @return nil|Loc
local function FindLineEnd(casterToken, targetArea)
    local locs = targetArea and targetArea.locations
    if locs == nil or #locs == 0 then
        return nil
    end
    local best = locs[1]
    for i = 2, #locs do
        if locs[i]:DistanceInTiles(casterToken.loc) > best:DistanceInTiles(casterToken.loc) then
            best = locs[i]
        end
    end
    return best
end

--- Landing candidates: the line's end square if free, otherwise every free square nearest to it
--- (ties are all returned so the caster can choose). The caster must be able to see a fallback
--- square, so the throw is never resolved through a wall.
--- @param casterToken CharacterToken
--- @param hurledToken CharacterToken
--- @param endLoc Loc
--- @param searchRadius number
--- @return Loc[]
local function FindLandingCandidates(casterToken, hurledToken, endLoc, searchRadius)
    if LocIsFreeForHurl(hurledToken, endLoc) then
        return { endLoc }
    end

    local nearest = {}
    local nearestDist = nil
    for _, loc in ipairs(endLoc:LocsInRadius(searchRadius) or {}) do
        local dist = loc:DistanceInTiles(endLoc)
        if dist > 0 and (nearestDist == nil or dist <= nearestDist) and LocIsFreeForHurl(hurledToken, loc) then
            --GetLineOfSight accepts a Loc; guard it anyway so an engine change never blocks the throw.
            local visible = true
            local ok, los = pcall(function() return casterToken:GetLineOfSight(loc) end)
            if ok and type(los) == "number" then
                visible = los > 0
            end
            if visible then
                if nearestDist == nil or dist < nearestDist then
                    nearest = { loc }
                    nearestDist = dist
                else
                    nearest[#nearest+1] = loc
                end
            end
        end
    end
    return nearest
end

--- @param ability ActivatedAbility
--- @param casterToken CharacterToken
--- @param targets table
--- @param options table
function ActivatedAbilityHurlGrabbedBehavior:Cast(ability, casterToken, targets, options)
    local symbols = options.symbols or {}

    local candidates = self:FindGrabbedCandidates(casterToken)
    if #candidates == 0 then
        casterToken.properties:FloatLabel("Nothing to hurl", "red")
        return
    end

    local hurled = candidates[1]
    if #candidates > 1 then
        hurled = ChooseHurledCreature(casterToken, candidates, symbols)
        if hurled == nil then
            return
        end
    end

    local endLoc = FindLineEnd(casterToken, options.targetArea)
    if endLoc == nil then
        casterToken.properties:FloatLabel("Hurl needs a line target", "red")
        return
    end

    local landing = FindLandingCandidates(casterToken, hurled, endLoc, self:try_get("searchRadius", 3))
    if #landing == 0 then
        casterToken.properties:FloatLabel("No room to land", "red")
        return
    end

    local dest = landing[1]
    if #landing > 1 then
        dest = ChooseTransitDestination(hurled, landing, symbols, casterToken, {
            name = "Hurl Landing Square",
            prompt = self:try_get("promptText", ""),
        })
        if dest == nil then
            return
        end
    end

    local origLoc = hurled.loc

    --The throw ends the grab. Purge only this caster's grab so another grabber keeps theirs.
    hurled:ModifyProperties{
        description = "Hurled",
        execute = function()
            hurled.properties:InflictCondition(g_hurlGrabbedConditionId, {
                purge = true,
                casterInfo = { tokenid = casterToken.charid },
            })
        end,
    }

    --Fly the creature down the line like a push: straight-line forced moves that
    --pass over creatures, are not its own move action, and do not provoke. The
    --grab was ended above, so the Grabbed condition's forcemove trigger (drag
    --the grabber along) never fires. Not a rules forced move: no
    --forcedMovementDistance, so a blocked path just stops with no collision
    --damage. When the landing square is off the line's end, the throw still
    --runs the whole line to its end square and then hops (jump animation)
    --into the square the director chose.
    local function WaitForGameUpdate()
        local updateAt = dmhub.ngameupdate
        local startTime = dmhub.Time()
        while dmhub.ngameupdate <= updateAt and dmhub.Time() < startTime + 2 do
            coroutine.yield(0.05)
        end
    end

    local function ThrowMove(toLoc, movementType)
        hurled.properties._tmp_freeMovement = true
        local path = hurled:Move(toLoc.withGroundAltitude, {
            straightline = true,
            ignorecreatures = true,
            moveThroughFriends = true,
            maxCost = 30000,
            movementType = movementType,
            jumpHeight = 2,
            ignoreFalling = (movementType == "jump"),
            freeMovement = true,
            forced = true,
        })
        hurled.properties._tmp_freeMovement = false
        return path ~= nil
    end

    --The push always runs the full line, even onto a square another creature
    --or object already holds (creatures are ignored, so the engine lets the
    --thrown creature pass over and stop there); only then does it hop into
    --the square the director chose. Skip the push if it already stands there.
    local legs = {}
    if hurled.loc.xyfloorOnly.str ~= endLoc.xyfloorOnly.str then
        legs[#legs+1] = { loc = endLoc, movementType = "move" }
    end
    if dest.xyfloorOnly.str ~= endLoc.xyfloorOnly.str then
        legs[#legs+1] = { loc = dest, movementType = "jump" }
    end

    local moved = true
    for i, leg in ipairs(legs) do
        if i > 1 then
            WaitForGameUpdate()
        end
        moved = ThrowMove(leg.loc, leg.movementType)
        if not moved then
            break
        end
    end

    --Fall back to a silent teleport if the engine refused a leg: the creature
    --must still land somewhere.
    if not moved then
        print("HurlGrabbed:: MOVE REFUSED, teleporting instead. dest =", dest.str)
        hurled.properties._tmp_suppressTeleportEvent = true
        hurled:Teleport(dest.withGroundAltitude)
        hurled.properties._tmp_suppressTeleportEvent = nil
    end
    hurled.properties:FloatLabel("Hurled!", "white")

    --Let the move land before anything rolls against the creature.
    WaitForGameUpdate()
    if hurled.valid then
        hurled:TryFall()
    end

    --Commit to the cost once the throw has actually happened, so a cancelled
    --pick above never charges the maneuver. (Ending a grab mid-cast logs one
    --engine "already in a transaction" line; the engine's own Grabbed teleport
    --trigger does the same, and state stays correct.)
    ability:CommitToPaying(casterToken, options)

    if self:try_get("addAsTarget", true) and options.targets ~= nil and hurled.valid then
        local present = false
        for _, existing in ipairs(options.targets) do
            if existing.token ~= nil and existing.token.charid == hurled.charid then
                present = true
                break
            end
        end
        if not present then
            options.targets[#options.targets+1] = { token = hurled, origLoc = origLoc }
        end
        if symbols.cast ~= nil then
            symbols.cast.targets = options.targets
        end
    end
end

--- @param parentPanel Panel
--- @return Panel[]
function ActivatedAbilityHurlGrabbedBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)

    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Hurl Filter:" },
        gui.GoblinScriptInput{
            classes = { "formInput" },
            value = self:try_get("hurlFilter", ""),
            change = function(element)
                self.hurlFilter = element.value
            end,
            documentation = {
                help = "Which grabbed creatures may be hurled. Evaluated on each creature the caster is grabbing.",
                output = "boolean",
                subject = creature.helpSymbols,
                subjectDescription = "A creature the caster is grabbing",
                examples = {
                    { script = "Size < 5", text = "Only Size 1 creatures can be hurled." },
                },
            },
        },
    }

    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Landing Search Radius:" },
        gui.Input{
            classes = { "formInput" },
            text = tostring(self:try_get("searchRadius", 3)),
            change = function(element)
                self.searchRadius = tonumber(element.text) or 3
                element.text = tostring(self.searchRadius)
            end,
        },
    }

    result[#result+1] = gui.Panel{
        classes = { "formPanel" },
        gui.Label{ classes = { "formLabel" }, text = "Prompt Text:" },
        gui.Input{
            classes = { "formInput" },
            text = self:try_get("promptText", ""),
            change = function(element)
                self.promptText = element.text
            end,
        },
    }

    result[#result+1] = gui.Check{
        text = "Add Hurled Creature To Targets",
        value = self:try_get("addAsTarget", true),
        change = function(element)
            self.addAsTarget = element.value
        end,
    }

    return result
end
