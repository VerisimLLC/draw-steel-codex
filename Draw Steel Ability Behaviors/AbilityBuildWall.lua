local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityBuildWallBehavior:ActivatedAbilityBehavior
--- Builds a wall out of "wall voxel" objects (e.g. Motivate Earth's "5 wall").
--- For each targeted square this spawns the configured object asset -- which must
--- carry an ObjectComponentWallVoxel component, normally alongside Targetable
--- (so the wall can be damaged) and optionally Aura components -- then syncs the
--- tile's wall voxel column so the engine materializes solid wall terrain there.
---
--- Intended ability setup: targetType = "emptyspace", targeting = "contiguous_wall",
--- numTargets = "N" (the wall size), range = the ability's range. With multiple
--- modes (e.g. Dirt/Stone/Metal), add one behavior per mode gated by modesSelected,
--- each with its own object asset.
---
--- Object assets are offered in the editor when they have the "wallvoxel" keyword.
---
--- Live placement: the action bar builds the wall square-by-square while the
--- player is still targeting (PlaceSquare/RemoveSquare below), so the wall
--- appears as you go. Cancelling targeting tears the placed squares back down;
--- a committed cast consumes the session instead of spawning the wall again.
ActivatedAbilityBuildWallBehavior = RegisterGameType("ActivatedAbilityBuildWallBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityBuildWallBehavior.summary = 'Build Wall'
ActivatedAbilityBuildWallBehavior.objectid = "none"

--when true, casting destroys every wall voxel this caster created in earlier
--casts before/as the new wall goes up (e.g. Living Labyrinth's "any wall
--created by the wallmaster in the previous round is destroyed or replaced").
ActivatedAbilityBuildWallBehavior.replacePrevious = false

ActivatedAbility.RegisterType
{
    id = 'build_wall',
    text = 'Build Wall',
    createBehavior = function()
        return ActivatedAbilityBuildWallBehavior.new{
        }
    end
}

--spawn one wall voxel object at the given square and sync the tile's column so
--the solid wall terrain materializes. Returns true on success.
--ownerTag (optional): { charid = ..., castid = ... } stamped onto the voxel's
--Targetable properties so abilities can later find walls made by a specific
--creature/cast (e.g. the Wallmaster's Living Labyrinth replacing last round's
--wall). Must be stamped before Upload so it persists.
local function SpawnWallVoxelAt(objectid, loc, ownerTag)
    local targetFloor = game.currentMap:GetFloorFromLoc(loc)
    if targetFloor == nil then
        return false
    end

    local spawnOptions = {
        spawnChildren = true,
        outChildren = {},
        posx = loc.x,
        posy = loc.y,
    }

    local obj = targetFloor:SpawnObjectLocal(objectid, spawnOptions)
    if obj == nil then
        return false
    end

    if ownerTag ~= nil then
        local targetable = obj:GetComponent("Targetable")
        if targetable ~= nil and targetable.properties ~= nil then
            targetable.properties.wallcreator = ownerTag.charid
            targetable.properties.wallcastid = ownerTag.castid
        end
    end

    --assign stack ordering, snap the voxel to the tile, and write the
    --solid-terrain building operation for this tile's voxel column.
    --Must run before Upload so the ordering/snap persist.
    targetFloor:SyncWallVoxelColumn(loc)

    for _,child in ipairs(spawnOptions.outChildren) do
        child:Upload()
    end

    return true
end

--destroy every wall voxel this caster created in a DIFFERENT cast. Used by the
--replacePrevious option ("any wall created in the previous round is destroyed
--or replaced"): voxels are tagged with wallcreator/wallcastid at spawn, so the
--old wall is found even if squares have since been moved or partially destroyed.
--Destruction goes through the Targetable death path, which folds the tile's
--column-op rewrite into the same patch.
local function DestroyPreviousWalls(casterToken, currentCastId)
    if casterToken == nil then
        return
    end

    local victims = {}
    for _,token in ipairs(Encounter.GetTargetableObjectsWithKeyword("wallvoxel")) do
        local props = token.properties
        if props ~= nil and props:try_get("wallcreator") == casterToken.charid and props:try_get("wallcastid") ~= currentCastId then
            victims[#victims+1] = token
        end
    end

    for _,token in ipairs(victims) do
        token:ModifyProperties{
            description = "Wall replaced",
            undoable = false,
            execute = function()
                token.properties:Destroy("Replaced by a new wall")
            end,
        }
    end
end

--find the Build Wall behavior that applies for the given mode index.
local function FindBehaviorForMode(ability, mode)
    for _,behavior in ipairs(ability:try_get("behaviors", {})) do
        if behavior.typeName == "ActivatedAbilityBuildWallBehavior" then
            local modes = behavior:try_get("modesSelected", {})
            if (not ability.multipleModes) or #modes == 0 or table.contains(modes, mode) then
                return behavior
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Live placement session.
--
-- The action bar drives this while a contiguous_wall ability is being targeted:
--   * PlaceSquare on every chosen square (builds the voxel immediately),
--   * RemoveSquare when a square is deselected,
--   * CommitPlacement just before the cast commits (behaviors run on a
--     coroutine AFTER the controller's finishCasting fires the casting
--     destructors, so the committed flag is what stops the destructor from
--     tearing the wall down on a successful cast),
--   * CancelPlacement from a casting destructor (no-op once committed).
--------------------------------------------------------------------------------
local g_session = nil

--- Build one wall square immediately during targeting. Returns true if a voxel
--- was placed (callers register a cancel destructor on the first success).
function ActivatedAbilityBuildWallBehavior.PlaceSquare(ability, casterToken, symbols, loc)
    if loc == nil then
        return false
    end

    local mode = 1
    if symbols ~= nil and symbols.mode ~= nil then
        mode = symbols.mode
    end

    local behavior = FindBehaviorForMode(ability, mode)
    if behavior == nil or behavior.objectid == "none" or behavior.objectid == false or behavior.objectid == nil then
        return false
    end

    --the session is created before the spawn so its castid can be stamped onto
    --the voxel (see SpawnWallVoxelAt's ownerTag).
    if g_session == nil or g_session.committed or g_session.abilityGuid ~= ability.guid then
        g_session = {
            abilityGuid = ability.guid,
            castid = dmhub.GenerateGuid(),
            committed = false,
            placements = {},
        }
    end

    local ownerTag = nil
    if casterToken ~= nil then
        ownerTag = { charid = casterToken.charid, castid = g_session.castid }
    end

    if not SpawnWallVoxelAt(behavior.objectid, loc, ownerTag) then
        return false
    end

    g_session.placements[#g_session.placements+1] = { loc = loc }
    return true
end

--- Remove the wall square placed at the given loc (deselection during targeting).
function ActivatedAbilityBuildWallBehavior.RemoveSquare(loc)
    if g_session == nil or g_session.committed or loc == nil then
        return
    end

    for i = #g_session.placements, 1, -1 do
        if g_session.placements[i].loc.str == loc.str then
            table.remove(g_session.placements, i)

            local floor = game.currentMap:GetFloorFromLoc(loc)
            if floor ~= nil then
                --our cubes are the newest on the tile, so the topmost cube is ours.
                floor:DestroyWallVoxel(loc, 9999)
            end
            break
        end
    end
end

--- Mark the session as committed: the cast is going through, so the wall stays.
function ActivatedAbilityBuildWallBehavior.CommitPlacement(ability)
    if g_session ~= nil and g_session.abilityGuid == ability.guid then
        g_session.committed = true
    end
end

--- Tear down all live-placed squares (targeting cancelled). No-op if committed.
function ActivatedAbilityBuildWallBehavior.CancelPlacement()
    if g_session == nil or g_session.committed then
        return
    end

    local session = g_session
    g_session = nil

    for i = #session.placements, 1, -1 do
        local placement = session.placements[i]
        local floor = game.currentMap:GetFloorFromLoc(placement.loc)
        if floor ~= nil then
            floor:DestroyWallVoxel(placement.loc, 9999)
        end
    end
end

--consume the session at cast time. Returns the session's castid if the wall was
--already built live during targeting (so Cast must not spawn it again), or nil.
local function ConsumeSession(ability)
    if g_session ~= nil and g_session.abilityGuid == ability.guid then
        local session = g_session
        g_session = nil
        if #session.placements > 0 then
            return session.castid
        end
    end

    return nil
end

function ActivatedAbilityBuildWallBehavior:Cast(ability, casterToken, targets, options)
    --if the wall was built live square-by-square during targeting it is already
    --on the map; destroy any replaced wall and just commit the ability cost.
    local sessionCastid = ConsumeSession(ability)
    if sessionCastid ~= nil then
        if self.replacePrevious then
            DestroyPreviousWalls(casterToken, sessionCastid)
        end
        ability:CommitToPaying(casterToken, options)
        return
    end

    if self.objectid == "none" or self.objectid == false or self.objectid == nil then
        print("BuildWall:: no wall voxel object configured; skipping")
        return
    end

    local locs = {}
    for _,target in ipairs(targets or {}) do
        if target.loc ~= nil then
            locs[#locs+1] = target.loc
        end
    end

    if #locs == 0 then
        return
    end

    local castid = dmhub.GenerateGuid()

    --"destroyed or replaced": tear down this caster's previous wall before the
    --new one goes up.
    if self.replacePrevious then
        DestroyPreviousWalls(casterToken, castid)
    end

    --record the wall construction as a revertible map modification, grouped
    --with any other map edits made by this cast. (Live-placed walls happen
    --during targeting, outside any cast recording -- this covers programmatic
    --casts only.)
    ActivatedAbility.BeginMapModificationRecording(ability, casterToken, options, locs[1])

    local ownerTag = nil
    if casterToken ~= nil then
        ownerTag = { charid = casterToken.charid, castid = castid }
    end

    for _,loc in ipairs(locs) do
        SpawnWallVoxelAt(self.objectid, loc, ownerTag)
    end

    ability:CommitToPaying(casterToken, options)

    ActivatedAbility.EndMapModificationRecording()
end

function ActivatedAbilityBuildWallBehavior:EditorItems(parentPanel)
    local result = {}

    local objectOptions = {
        {
            id = "none",
            text = "None",
        }
    }

    for _,object in pairs(assets.allObjects) do
        local keywords = nil
        if object.components ~= nil then
            local core = object.components["CORE"]
            if core ~= nil then
                for _,field in ipairs(core.fields) do
                    if field.id == "keywords" then
                        keywords = field.currentValue
                        break
                    end
                end
            end
        end

        if keywords ~= nil and table.contains(keywords, "wallvoxel") then
            objectOptions[#objectOptions+1] = { id = object.id, text = object.description }
        end
    end

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Wall Object:",
        },
        gui.Dropdown{
            options = objectOptions,
            hasSearch = true,
            sort = true,
            textDefault = "Choose Object...",
            idChosen = self.objectid,
            change = function(element)
                self.objectid = element.idChosen
            end,
        }
    }

    if #objectOptions == 1 then
        result[#result+1] = gui.Label{
            width = "90%",
            height = "auto",
            fontSize = 12,
            text = "No wall voxel objects found. Author an object with a Wall Voxel component and give it the keyword \"wallvoxel\" to make it available here.",
        }
    end

    result[#result+1] = gui.Check{
        text = "Replace Previous Wall",
        value = self.replacePrevious,
        change = function(element)
            self.replacePrevious = element.value
        end,
    }

    return result
end

--------------------------------------------------------------------------------
-- Shift Wall Voxel behavior.
--
-- Moves an already-placed wall voxel into a square the pushed creature vacated
-- (e.g. the Wallmaster's Dead End: "That square of wall pushes one target...
-- and shifts into any square they leave behind"). Intended ability shape:
--   * stage-1 targets are wall voxel object tokens (objectTarget = true),
--   * a manipulate_targets behavior replaces them with the pushed creature
--     (stamping target.origLoc with the creature's pre-push location),
--   * a power roll pushes the creature,
--   * this behavior runs last with applyto = "original_targets" so it sees the
--     wall voxel tokens again, while options.targets holds the pushed creature.
--
-- The vacated squares are approximated as the straight line from the creature's
-- pre-push square to (exclusive of) its current square. With more than one
-- vacated square the caster's controller picks one; the pick is restricted to
-- those squares via _tmp_restrictLocs (see TargetLocPassesFilterPredicate).
--------------------------------------------------------------------------------

--- @class ActivatedAbilityShiftWallVoxelBehavior:ActivatedAbilityBehavior
ActivatedAbilityShiftWallVoxelBehavior = RegisterGameType("ActivatedAbilityShiftWallVoxelBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityShiftWallVoxelBehavior.summary = 'Shift Wall Voxel'

ActivatedAbility.RegisterType
{
    id = 'shift_wall_voxel',
    text = 'Shift Wall Voxel',
    createBehavior = function()
        return ActivatedAbilityShiftWallVoxelBehavior.new{
        }
    end
}

--the straight-line squares from origLoc to (exclusive of) destLoc, including
--origLoc itself. Approximates the squares a pushed creature vacated.
local function VacatedSquares(origLoc, destLoc)
    local result = {}
    local loc = origLoc
    local sanity = 0
    while loc ~= nil and (not loc:Equals(destLoc)) and sanity < 100 do
        result[#result+1] = loc
        local dx = 0
        local dy = 0
        if destLoc.x > loc.x then dx = 1 elseif destLoc.x < loc.x then dx = -1 end
        if destLoc.y > loc.y then dy = 1 elseif destLoc.y < loc.y then dy = -1 end
        if dx == 0 and dy == 0 then
            break
        end
        loc = loc:dir(dx, dy)
        sanity = sanity + 1
    end

    return result
end

--prompt the caster's controller to pick one of the given squares. The invoked
--pick is centered on the wall token so the targeting radius draws around the
--wall rather than the caster. Returns the chosen loc, or nil if cancelled.
local function ChooseShiftDestination(wallToken, candidates, symbols)
    local capturedLoc = nil

    local captureBehavior = ActivatedAbilityBehavior.new{
        instant = true,
    }
    captureBehavior.Cast = function(behaviorSelf, captureAbility, captureCasterToken, captureTargets, captureOptions)
        if captureTargets ~= nil and #captureTargets > 0 then
            capturedLoc = captureTargets[1].loc
        end
    end

    local pickAbility = ActivatedAbility.Create()
    pickAbility.name = "Wall Shift"
    pickAbility.targetType = "emptyspace"
    pickAbility.range = "10"
    pickAbility.numTargets = "1"
    pickAbility.countsAsCast = false
    pickAbility.skippable = true
    pickAbility.promptOverride = "Choose the square the wall shifts into"
    pickAbility.behaviors = { captureBehavior }
    pickAbility._tmp_restrictLocs = candidates

    ActivatedAbilityInvokeAbilityBehavior.ExecuteInvoke(wallToken, pickAbility, wallToken, "prompt", symbols or {}, {})

    return capturedLoc
end

function ActivatedAbilityShiftWallVoxelBehavior:Cast(ability, casterToken, targets, options)
    ability:CommitToPaying(casterToken, options)

    for i,target in ipairs(targets) do
        local wallToken = target.token
        if wallToken ~= nil and wallToken.valid and wallToken.objectInstance ~= nil then
            --the pushed creature: pair up by index, falling back to the first.
            local creatureTarget = nil
            if options.targets ~= nil then
                creatureTarget = options.targets[i] or options.targets[1]
            end

            local origLoc = nil
            local currentLoc = nil
            if creatureTarget ~= nil and creatureTarget.token ~= nil and creatureTarget.token.valid then
                origLoc = creatureTarget.origLoc
                currentLoc = creatureTarget.token.loc
            end

            if origLoc ~= nil and currentLoc ~= nil and (not origLoc:Equals(currentLoc)) then
                local vacated = VacatedSquares(origLoc, currentLoc)

                local destLoc = nil
                if #vacated == 1 then
                    destLoc = vacated[1]
                elseif #vacated > 1 then
                    destLoc = ChooseShiftDestination(wallToken, vacated, options.symbols)
                    if destLoc == nil then
                        --cancelled/skipped: fall back to the square the push started from.
                        destLoc = origLoc
                    end
                end

                if destLoc ~= nil then
                    local oldLoc = wallToken.loc
                    wallToken.objectInstance:SetAndUploadPos(destLoc.x, destLoc.y)

                    --SetAndUploadPos does not resync voxel columns; rewrite the
                    --solid-terrain ops on both tiles.
                    local oldFloor = game.currentMap:GetFloorFromLoc(oldLoc)
                    if oldFloor ~= nil then
                        oldFloor:SyncWallVoxelColumn(oldLoc)
                    end
                    local newFloor = game.currentMap:GetFloorFromLoc(destLoc)
                    if newFloor ~= nil then
                        newFloor:SyncWallVoxelColumn(destLoc)
                    end
                end
            end
        end
    end
end

function ActivatedAbilityShiftWallVoxelBehavior:EditorItems(parentPanel)
    local result = {}
    self:ApplyToEditor(parentPanel, result)
    self:FilterEditor(parentPanel, result)
    return result
end
