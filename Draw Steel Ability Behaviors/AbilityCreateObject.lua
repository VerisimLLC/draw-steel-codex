local mod = dmhub.GetModLoading()

--- @class ActivatedAbilityCreateObjectBehavior:ActivatedAbilityBehavior
ActivatedAbilityCreateObjectBehavior = RegisterGameType("ActivatedAbilityCreateObjectBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityCreateObjectBehavior.summary = 'Create Object'
ActivatedAbilityCreateObjectBehavior.randomize = false
ActivatedAbilityCreateObjectBehavior.targetFloor = 0

ActivatedAbility.RegisterType
{
	id = 'create_object',
	text = 'Create Object',
	createBehavior = function()
		return ActivatedAbilityCreateObjectBehavior.new{
            objectid = false
		}
	end
}

--Objects placed by this behavior are stamped with the id of the map modification
--record they belong to, so the record can find and destroy them when it is reverted.
--The engine's own revert only knows how to collapse wall-voxel columns (verified: a
--plain spawned object survives DeleteMapModification), so the teardown is done from
--Lua -- see DestroyRecordedObjects, called by the Map Modifications folder in
--DMHub Core Panels/CharacterPanel.lua. Mirrors how AbilityBuildWall stamps
--wallcreator/wallcastid onto Targetable properties; must be set before Upload to persist.
local function StampRecordKey(obj, key)
    if obj == nil or key == nil then
        return
    end

    local targetable = obj:GetComponent("Targetable")
    if targetable ~= nil and targetable.properties ~= nil then
        targetable.properties.mapmodkey = key
    end
end

--True if this aura definition carries any onenter/end-of-turn trigger, counting
--sub-aura triggers (a split aura normally keeps its triggers on the child payload).
local function AuraDefHasTriggers(auraDef)
    if auraDef == nil then
        return false
    end

    if #auraDef:try_get("triggers", {}) > 0 then
        return true
    end

    for _, childDef in ipairs(auraDef:try_get("subauras", {})) do
        if #childDef:try_get("triggers", {}) > 0 then
            return true
        end
    end

    return false
end

--Object assets bake a FIXED AuraInstance guid, so every object spawned from one asset
--shares it. creature.aurasEntered dedupes aura triggers by that guid for the rest of the
--turn (see creature:EnterAuraHaltsMovement), which collapses a whole wall of spawned
--squares into a SINGLE trigger slot: enter any one square and no other square can fire
--again that turn. Worse, the slot is burned by entries that produce nothing -- starting a
--turn inside the area, or walking in before being pushed in -- so the trigger looks
--intermittent. Give each spawned object its own instance guid so squares dedupe
--independently. Child instances derive their guid from the parent's, so the sub-aura
--carrying the triggers becomes distinct too.
--
--Restricted to auras that actually have triggers. A trigger-less aura has nothing to
--dedupe, and its guid still feeds EnterAuraHaltsMovement -- making those unique would
--start halting movement at EVERY square of existing content (the Delian Tomb brambles)
--rather than once per turn, which is a gameplay change nobody asked for.
local function FreshenSpawnedAuraGuid(auraInstance)
    if auraInstance == nil or (not AuraDefHasTriggers(auraInstance.aura)) then
        return
    end

    auraInstance.guid = dmhub.GenerateGuid()
end

--Stamp the caster onto a spawned object's aura so the aura knows who made it.
--Without this an object-hosted aura has no casterid, which leaves every
--caster-relative audience ("All Other Creatures", "Enemies", ...) resolving
--against nobody. That matters beyond modifiers: the engine evaluates the aura's
--audience PER CREATURE when computing cover, so a caster-less aura marked
--blocks_line_of_effect blocks line of effect for its own creator too (the Thorn
--Dragon's Bramble Barricade is meant to block for everyone except the dragon).
--Must be set before Upload so it persists.
local function StampAuraCaster(obj, casterToken)
    if obj == nil or casterToken == nil or (not casterToken.valid) then
        return
    end

    local auraComponent = obj:GetComponent("Aura")
    if auraComponent == nil or auraComponent.properties == nil then
        return
    end

    local auraInstance = auraComponent.properties:try_get("aura")
    if auraInstance ~= nil then
        auraInstance.casterid = casterToken.id
    end
end

--Give a spawned object's aura its own identity (see FreshenSpawnedAuraGuid). Split out
--from StampAuraCaster because this applies even to objects created with no caster.
local function StampAuraIdentity(obj)
    if obj == nil then
        return
    end

    local auraComponent = obj:GetComponent("Aura")
    if auraComponent == nil or auraComponent.properties == nil then
        return
    end

    FreshenSpawnedAuraGuid(auraComponent.properties:try_get("aura"))
end

--record a spawned object into the active map modification recording, so the
--placement shows up in the character panel's Map Modifications folder and can be
--removed from there. Nil-guarded for engine builds that predate the API.
local function RecordObjectInModification(obj)
    if obj == nil or rawget(_G, "game") == nil or game.AddMapModificationVoxel == nil then
        return
    end

    game.AddMapModificationVoxel(obj)
end

--- Destroy every object placed by the map modification record with the given key.
--- Called from the Map Modifications folder before the record itself is deleted.
--- @param key nil|string The record's key (the placing cast's castid).
--- @return nil
function ActivatedAbilityCreateObjectBehavior.DestroyRecordedObjects(key)
    if key == nil or key == "" or rawget(_G, "game") == nil or game.currentMap == nil then
        return
    end

    --Scanning the floors directly rather than Encounter.GetTargetableObjectsWithKeyword:
    --created objects carry whatever keywords their asset happens to define, so there is no
    --single keyword to look them up by.
    local victims = {}
    for _, floor in ipairs(game.currentMap.floors) do
        for _, obj in pairs(floor.objects) do
            if obj.valid then
                local targetable = obj:GetComponent("Targetable")
                if targetable ~= nil and targetable.properties ~= nil and targetable.properties:try_get("mapmodkey") == key then
                    victims[#victims + 1] = obj
                end
            end
        end
    end

    for _, obj in ipairs(victims) do
        obj:DestroyWithBehavior {
            ttl = 3,
        }
    end
end

function ActivatedAbilityCreateObjectBehavior:Cast(ability, casterToken, targets, options)
    local targetArea = options.targetArea
    local locations = nil
    print("CAST:: AREA:", targetArea)
    if targetArea ~= nil then
        locations = targetArea.locations
    else
        locations = {}

        for _,target in ipairs(targets or {}) do
            if target.loc ~= nil then
                locations[#locations+1] = target.loc
            end
        end
    end

    if locations == nil or #locations == 0 then
        print("CAST:: NO LOCATIONS")
        return
    end

    print("CAST:: LOCATIONS:", #locations)

    --make sure we do the top locations first so their zorder is behind.
    table.sort(locations, function(a, b) return a.y > b.y end)

    --Group every object this cast places into one revertible map modification record,
    --keyed by castid (the same key BeginMapModificationRecording derives), so the
    --Director can clear the placement from the character panel later.
    local recordKey = nil
    if options.symbols ~= nil then
        recordKey = options.symbols.castid
    end
    ActivatedAbility.BeginMapModificationRecording(ability, casterToken, options, locations[1])

    for _,loc in ipairs(locations) do
        local targetFloor = game.currentMap:GetFloorFromLoc(loc)
        print("CAST:: TARGET FLOOR:", targetFloor)
        if targetFloor ~= nil then
            local spawnOptions = {
                spawnChildren = true,
                outChildren = {},
            }

            local xdelta = 0
            local ydelta = 0
            if options.symbols.cast.auraObject then
                spawnOptions.parentid = options.symbols.cast.auraObject.objid
                xdelta = -options.symbols.cast.auraObject.x
                ydelta = -options.symbols.cast.auraObject.y
            end
            local obj = targetFloor:SpawnObjectLocal(self.objectid, spawnOptions)
            if obj ~= nil then
                obj.x = loc.x + xdelta
                obj.y = loc.y + ydelta
                StampRecordKey(obj, recordKey)
                StampAuraIdentity(obj)
                StampAuraCaster(obj, casterToken)
                RecordObjectInModification(obj)
                for _,child in ipairs(spawnOptions.outChildren) do
                    if self.randomize then
                        for _,component in pairs(child.components) do
                            component:Randomize{
                                hue = 0.2,
                                playbackSpeed = 0.1,
                                xflip = true,
                            }
                        end
                    end

                    child:Upload()
                end
            end
        end
    end

    --commit to paying so the ability's cost (including consumable item usage) is
    --applied. Without this, an ability whose only behavior is Create Object never
    --sets options.pay, so ConsumeResources is skipped and a consumable item is not
    --removed from inventory on use. Mirrors AbilityChangeTerrain / AbilityBuildWall.
    ability:CommitToPaying(casterToken, options)

    ActivatedAbility.EndMapModificationRecording()
end

--=============================================================================
-- create_lane_object: place a directional lane object from a line-targeted
-- ability (e.g. the Time Raider Helix's Kinetic Lane maneuver).
--
-- Spawns ONE copy of the chosen object, anchored at the end of the targeted
-- line nearest the line's origin and rotated to face the far end. The lane
-- aura's area is stamped with the EXACT squares of the targeted line (so the
-- lane matches what the director drew), along with the transform stamps the
-- lane watcher in DMHub Game Rules/Aura.lua uses to know the area is current.
-- Tokens already standing in the area are slid immediately (the rules'
-- "before they slide" - put a damage behavior BEFORE this one for cast-time
-- damage). See Aura.laneInternal for the shared lane machinery.
--=============================================================================

--- @class ActivatedAbilityCreateLaneObjectBehavior:ActivatedAbilityBehavior
ActivatedAbilityCreateLaneObjectBehavior = RegisterGameType("ActivatedAbilityCreateLaneObjectBehavior", "ActivatedAbilityBehavior")

ActivatedAbilityCreateLaneObjectBehavior.summary = 'Create Lane Object'
ActivatedAbilityCreateLaneObjectBehavior.objectid = false

ActivatedAbility.RegisterType
{
    id = 'create_lane_object',
    text = 'Create Lane Object',
    createBehavior = function()
        return ActivatedAbilityCreateLaneObjectBehavior.new{
        }
    end
}

--- Quantize an arbitrary offset to the nearest of the 8 compass directions.
--- @param dx number
--- @param dy number
--- @return nil|{x: number, y: number}
local function QuantizeLaneDirection(dx, dy)
    local adx = math.abs(dx)
    local ady = math.abs(dy)
    local m = math.max(adx, ady)
    if m <= 0 then
        return nil
    end

    local nx = dx / m
    local ny = dy / m
    local result = {x = 0, y = 0}
    if nx > 0.5 then
        result.x = 1
    elseif nx < -0.5 then
        result.x = -1
    end
    if ny > 0.5 then
        result.y = 1
    elseif ny < -0.5 then
        result.y = -1
    end

    if result.x == 0 and result.y == 0 then
        return nil
    end

    return result
end

--- Object rotation (degrees) whose lane direction matches dir.
--- @param dir {x: number, y: number}
--- @return number
local function LaneRotationFromDirection(dir)
    for index = 0, 7 do
        local candidate = Aura.laneInternal.directions[index]
        if candidate.x == dir.x and candidate.y == dir.y then
            return index * 45
        end
    end
    return 0
end

function ActivatedAbilityCreateLaneObjectBehavior:Cast(ability, casterToken, targets, options)
    if not self.objectid then
        return
    end

    local targetArea = options.targetArea
    if targetArea == nil or targetArea.locations == nil or #targetArea.locations == 0 then
        printf("LANE:: create lane object: no target area")
        return
    end

    local locations = {}
    for _,loc in ipairs(targetArea.locations) do
        locations[#locations+1] = loc
    end

    --The lane runs from the end of the area nearest the line's origin (where
    --the director anchored the line) toward the far end.
    local origin = targetArea.origin
    local nearLoc = locations[1]
    local farLoc = locations[#locations]
    if origin ~= nil then
        local nearDist = nil
        local farDist = nil
        for _,loc in ipairs(locations) do
            local d = loc:DistanceInTiles(origin)
            if nearDist == nil or d < nearDist then
                nearDist = d
                nearLoc = loc
            end
            if farDist == nil or d > farDist then
                farDist = d
                farLoc = loc
            end
        end
    end

    local dir = QuantizeLaneDirection(farLoc.x - nearLoc.x, farLoc.y - nearLoc.y)
    if dir == nil then
        printf("LANE:: create lane object: degenerate area, cannot determine direction")
        return
    end

    local rotation = LaneRotationFromDirection(dir)

    local targetFloor = game.currentMap:GetFloorFromLoc(nearLoc)
    if targetFloor == nil then
        printf("LANE:: create lane object: no floor at target")
        return
    end

    local obj = targetFloor:SpawnObjectLocal(self.objectid)
    if obj == nil then
        printf("LANE:: create lane object: could not spawn object %s", tostring(self.objectid))
        return
    end

    obj.x = nearLoc.x
    obj.y = nearLoc.y
    obj.rotation = rotation

    local slideDist = Aura.laneSlideDistance
    local comp = obj:GetComponent("Aura")
    if comp ~= nil and comp.properties ~= nil and comp.properties:has_key("aura") then
        local inst = comp.properties.aura
        pcall(function()
            slideDist = tonumber(inst.aura:try_get("laneSlideDistance", slideDist)) or slideDist
        end)
        inst.guid = dmhub.GenerateGuid()
        inst.laneObjId = obj.objid
        inst.laneDirection = {x = dir.x, y = dir.y}
        inst.laneSyncX = obj.x
        inst.laneSyncY = obj.y
        inst.laneSyncRot = obj.rotation
        inst.area = dmhub.CalculateShape{
            shape = "locations",
            locOverride = nearLoc,
            targetPoint = core.Vector3(nearLoc.x + 0.5, nearLoc.y + 0.5, 0),
            range = #locations*2,
            radius = 0,
            checklos = false,
            locations = locations,
        }
    end

    obj:Upload()

    --Slide every token already standing in the area ("...before they slide").
    --Pre-mark them as inside so the lane watcher does not treat them as fresh
    --entrants on its next tick.
    local state = Aura.laneInternal.GetOrCreateLaneState(obj.floorid .. "/" .. obj.objid)

    local seen = {}
    for _,loc in ipairs(locations) do
        for _,tok in ipairs(game.GetTokensAtLoc(loc) or {}) do
            if tok.valid and (not tok.isObject) and (not seen[tok.id]) then
                seen[tok.id] = true
                state.insideTokens[tok.id] = true
                if tok.properties ~= nil and (not tok.properties:IsDead()) and Aura.laneInternal.TokenMaySlide(tok.id) then
                    Aura.laneInternal.SlideToken(tok, dir, slideDist, state)
                end
            end
        end
    end
end

function ActivatedAbilityCreateLaneObjectBehavior:EditorItems(parentPanel)
    local result = {}

    local objectOptions = {}
    for _,object in pairs(assets.allObjects) do
        local keywords = nil
        if object.components ~= nil then
            local coreComponent = object.components["CORE"]
            if coreComponent ~= nil then
                for _,field in ipairs(coreComponent.fields) do
                    if field.id == "keywords" then
                        keywords = field.currentValue
                        break
                    end
                end
            end
        end

        if keywords ~= nil and table.contains(keywords, "summonable") then
            objectOptions[#objectOptions+1] = { id = object.id, text = object.description }
        end
    end

    result[#result+1] = gui.Panel{
        classes = {"formPanel"},
        gui.Label{
            classes = {"formLabel"},
            text = "Object:",
        },
        gui.Dropdown{
            options = objectOptions,
            textDefault = "Choose Object...",
            hasSearch = true,
            idChosen = self.objectid,
            change = function(element)
                self.objectid = element.idChosen
            end,
        }
    }

    return result
end

function ActivatedAbilityCreateObjectBehavior:EditorItems(parentPanel)
    local panel = gui.Panel{
        width = "100%",
        height = "auto",
        flow = "vertical",
    }

    local objectOptions = {}
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

        if keywords ~= nil and #keywords ~= 0 then
            print("KEYWORDS::", keywords)
        end
        if keywords ~= nil and table.contains(keywords, "summonable") then
            print("KEYWORDS:: SELECT", object, object.description)
            objectOptions[#objectOptions+1] = { id = object.id, text = object.description }
        end
    end

    local Refresh
    Refresh = function()
        local children = {}

    	self:ApplyToEditor(parentPanel, children)

        children[#children+1] = gui.Panel{
            classes = {"formPanel"},
            gui.Label{
                classes = {"formLabel"},
                text = "Object:",
            },
            gui.Dropdown{
                options = objectOptions,
                textDefault = "Choose Object...",
                idChosen = self.objectid,
                change = function(element)
                    self.objectid = element.idChosen
                    Refresh()
                end,
            }
        }

        children[#children+1] = gui.Check{
            text = "Randomize Objects",
            value = self.randomize,
            change = function(element)
                self.randomize = element.value
                Refresh()
            end,
        }

        panel.children = children
    end

    Refresh()

    return {panel}


end