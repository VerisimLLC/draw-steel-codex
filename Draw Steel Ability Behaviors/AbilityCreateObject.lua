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