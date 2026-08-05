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