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

    -- Record the movement delta on the Aura component so the engine plays the slide animation
    -- from the old position to the new one.
    local objAura = obj:GetComponent("Aura")
    if objAura ~= nil then
        objAura:SetAndUploadProperties{
            moveTimestamp = dmhub.serverTime,
            movex = destx - obj.x,
            movey = desty - obj.y,
        }
    end

    -- Move the object to the destination and upload the change.
    obj:SetAndUploadPos(destx, desty)

    dmhub.EndTransaction()
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

--- Every placed portal of the given aura name on the given floor, read straight off the
--- map objects.
---
--- The map is deliberately the source of truth here rather than the trigger's "aura"
--- symbol or the owner's aura list. An aura trigger can be handed to the controlling
--- client, and SendTriggerCastToController (DMHub Game Rules/TriggeredAbility.lua)
--- serializes symbols by unwrapping each closure with v("self"). AuraInstance.lookupSymbols
--- has no "self" key, so the "aura" symbol is silently dropped in transit and is nil on the
--- receiving machine -- which is precisely the case where somebody else moved the token.
--- Map objects are present and identical on every client.
--- @param auraName string Aura name to match (case-insensitive).
--- @param floorIndex number Only portals on this floor are collected.
--- @return table[] A list of { loc = Loc, casterid = string }.
local function CollectPortals(auraName, floorIndex)
    local result = {}
    if auraName == "" then
        return result
    end

    local wanted = string.lower(auraName)
    for _, floor in ipairs(game.currentMap.floors) do
        for _, obj in pairs(floor.objects) do
            if obj.valid and obj.floorIndex == floorIndex then
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
                    local portalLoc = core.Loc{
                        x = math.floor(obj.x + 0.5),
                        y = math.floor(obj.y + 0.5),
                    }:WithDifferentFloor(floorIndex)

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
--- @param portals table[] All placed portals as { loc, altitude, casterid }.
--- @param loc Loc The chosen destination square.
--- @return nil|number
local function EmergeAltitudeFor(portals, loc)
    local result = nil
    for _, portal in ipairs(portals) do
        if portal.altitude ~= nil and portal.loc:DistanceInTiles(loc) <= 1 then
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
--- @return nil|Loc
local function ChooseTransitDestination(travelToken, candidates, symbols, chooserToken)
    local capturedLoc = nil

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
    pickAbility.name = "Portal Transit"
    pickAbility.targetType = "emptyspace"
    pickAbility.range = tostring((maxDist + 1) * dmhub.unitsPerSquare)
    pickAbility.numTargets = "1"
    pickAbility.countsAsCast = false
    pickAbility.skippable = true
    pickAbility.promptOverride = "Choose where you emerge"
    pickAbility.behaviors = { captureBehavior }
    pickAbility._tmp_restrictLocs = candidates

    -- The cast is always centred on the traveller (that is what the reticle and range use, and
    -- what a nil-return cancel leaves in place). Only the INVOKER varies, which is what feeds
    -- the AI auto-answer callback and the invoke symbols. The prompt itself opens on whichever
    -- client is running this code, so callers must already be executing there.
    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(chooserToken or travelToken, pickAbility, travelToken, "prompt", symbols or {}, {})

    return capturedLoc
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
    local previousFreeMovement = travelToken.properties:try_get("_tmp_freeMovement", false)
    travelToken.properties._tmp_freeMovement = true
    travelToken:Teleport(teleportLoc)
    travelToken.properties._tmp_freeMovement = previousFreeMovement

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

    local portals = CollectPortals(self:try_get("auraName", ""), travelToken.loc.floor)

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

    local portals = CollectPortals(PORTAL_AURA_NAME, movedToken.loc.floor)
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
