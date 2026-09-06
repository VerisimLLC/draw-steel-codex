local mod = dmhub.GetModLoading()

--Map Markup: footstep surfaces - registry, settings, per-map variations and
--the painted-surface storage.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--============================================================================
--Footsteps (mode id "surfaces"): painted footstep-SOUND regions. Zone-like
--records (category = "surface", schema above) that feed ONE thing: the
--surfaceType tile rule, which the footstep pipeline reads when a creature
--walks there. Deliberately lower priority than real conditions: the
--playback dispatch (AudioMain.TokenMovingOnPath) checks flying / burrowing
--/ water BEFORE the surface sound, so water always sounds like water and
--flyers never footstep, regardless of what is painted here.
--
--The palette is the fixed AudioSurfaceTypes registry (accessed at runtime:
--it loads from another module), not a per-map palette like walls/zones.
--============================================================================

local function SurfaceRegistry()
    local registry = rawget(_G, "AudioSurfaceTypes")
    if registry ~= nil and registry.surfaces ~= nil then
        return registry.surfaces
    end
    return {}
end

local function SurfaceInfoById(surfaceId)
    for _,info in ipairs(SurfaceRegistry()) do
        if info.id == surfaceId then
            return info
        end
    end
    return nil
end

--Overlay tint per surface family (labels always render too, so color is
--never the sole signifier). Families added to the registry later fall back.
K.SURFACE_COLORS = {
    [1] = "#b0a99b", --Generic
    [2] = "#8a5a2e", --Dirt
    [3] = "#4a9e3d", --Grass
    [4] = "#8fa6bf", --Hollow Metal
    [5] = "#52616e", --Solid Metal
    [6] = "#8c8c94", --Stone
    [7] = "#b5813f", --Wood
    [8] = "#3d8fd9", --Puddle
    [9] = "#d9e8f2", --Snow
}
K.SURFACE_FALLBACK_COLOR = "#9a9a9a"

local function SurfaceColor(surfaceId)
    return K.SURFACE_COLORS[surfaceId] or K.SURFACE_FALLBACK_COLOR
end

--The map's default footstep surface: what unpainted tiles (surfaceType 0)
--sound like. Read at playback time by AudioMain.TokenMovingOnPath and
--creature.PlayLandingFootstep via dmhub.GetSettingValue. Map storage: DM
--writes it, it syncs to every client (players play their own footsteps),
--and it changes with the map. 0 = no default (the engine's Generic).
gs.footstepDefaultSetting = setting{
    id = "markup:footstepdefault",
    description = "Map Default Footsteps",
    storage = "map",
    default = 0,
}

--Per-variation footstep defaults. A map whose Map object carries several
--appearances (the Floors panel's Map Appearance gallery: e.g. a "Flooded"
--alternate) can give each appearance its own default footstep surface, on
--top of the map-wide default above. One map-storage table: appearance image
--key -> surface id (0 = "None - Use Tile Surfaces", the same meaning as the
--map-wide value). Keyed by the appearance's IMAGE id - the base image's
--asset id (or "base" when the map has none), a swap's image id - rather than
--its index, so an override follows its image through "Set as Default"
--promotions and removals. An absent key means "use the map-wide default".
--Read at playback by MapMarkupFootsteps.GetVariationDefaultSurface.
gs.footstepVariationSetting = setting{
    id = "markup:footstepvariations",
    description = "Map Variation Footsteps",
    storage = "map",
    default = {},
}

--Fires a one-shot preview of a surface family's footstep sound - the same
--event playback uses, including the puddle splash overlay.
local function PlaySurfaceSample(surfaceInfo)
    local sound = "Foot.Generic_Generic"
    if surfaceInfo ~= nil and surfaceInfo.sound ~= nil then
        sound = surfaceInfo.sound
    end
    audio.FireSoundEvent(sound, { volume = 1 })
    if surfaceInfo ~= nil and surfaceInfo.puddleSound then
        audio.FireSoundEvent("Foot.Swim_Generic", { volume = 0.4 })
    end
end

--============================================================================
--Map variation footsteps: helpers shared by the Footsteps tab's default
--control and the playback lookup (MapMarkupFootsteps below). On m rather
--than as locals so the Footsteps tab (MapMarkupFootstepsMode.lua) can reach
--them.
--============================================================================
do
    --The map's variation override table as a FRESH copy: the setting hands
    --back its stored table by reference, and Set() compares old and new by
    --content (ScriptSerialize.LuaValueEqual), so mutating the stored table
    --in place and setting it back would register as no change and never
    --upload. Keys are strings, values whole numbers; anything else dropped.
    m.ReadFootstepVariations = function()
        local result = {}
        local ok, stored = pcall(function()
            return gs.footstepVariationSetting:Get()
        end)
        if ok and type(stored) == "table" then
            for k,v in pairs(stored) do
                local n = tonumber(v)
                if type(k) == "string" and n ~= nil then
                    result[k] = math.floor(n)
                end
            end
        end
        return result
    end

    --Writes the override table. Setting a fresh table (see above) is what
    --makes the change register and upload.
    m.WriteFootstepVariations = function(overrides)
        local fresh = {}
        for k,v in pairs(overrides) do
            fresh[k] = v
        end
        gs.footstepVariationSetting:Set(fresh)
    end

    --The Map object (an object carrying a "Map" component) for a floor: the
    --floor's own objects first, then - for a top-level floor - its layers.
    --Mirrors FindMapObjectForFloor in DMHub Core Panels/Floors.lua, which
    --owns the appearance gallery this feature keys off.
    local function FindMapObject(floor)
        for _,obj in pairs(floor.objects or {}) do
            if obj:GetComponent("Map") ~= nil then
                return obj
            end
        end

        if floor.parentFloor == nil and game.currentMap ~= nil then
            local layers = game.currentMap:GetLayersForFloor(floor.floorid)
            for _,layer in ipairs(layers or {}) do
                for _,obj in pairs(layer.objects or {}) do
                    if obj:GetComponent("Map") ~= nil then
                        return obj
                    end
                end
            end
        end
        return nil
    end

    --A floor's map-appearance state, or nil when the floor has no Map object
    --or that object has no alternates - the cases where the Footsteps tab
    --shows its plain map-wide control. Otherwise:
    --  key      the selected appearance's override key (see the setting)
    --  name     its display name
    --  keys     index -> key, 0 = the base image
    --  names    index -> display name
    --  selected the selected index (clamped into range)
    --  objid    the Map object's id
    m.GetFootstepVariationState = function(floorid)
        if floorid == nil then
            return nil
        end
        local floor = game.GetFloor(floorid)
        if floor == nil then
            return nil
        end
        local obj = FindMapObject(floor)
        if obj == nil or not obj.valid then
            return nil
        end
        local comp = obj:GetComponent("Appearance")
        if comp == nil or not comp.valid then
            return nil
        end
        local doc = obj:ComponentToJson(comp.componentid)
        if doc == nil then
            return nil
        end
        local swaps = doc.imageSwaps or {}
        if #swaps == 0 then
            return nil
        end
        local swapNames = doc.imageSwapNames or {}

        local baseKey = obj.assetid
        if baseKey == nil or baseKey == "" then
            baseKey = "base"
        end
        local baseName = doc.imageDefaultName
        if baseName == nil or baseName == "" then
            baseName = "Default"
        end

        local keys = { [0] = baseKey }
        local names = { [0] = baseName }
        for i = 1, #swaps do
            keys[i] = swaps[i]
            names[i] = swapNames[i] or string.format("Appearance %d", i)
        end

        local selected = math.floor(tonumber(doc.imageNumber) or 0)
        if selected < 0 or selected > #swaps then
            selected = 0
        end

        return {
            key = keys[selected],
            name = names[selected],
            keys = keys,
            names = names,
            selected = selected,
            objid = obj.id,
        }
    end

    --Playback-side: the selected appearance's key for a floor, cached for a
    --second per floor. Footsteps fire several times a second while a token
    --moves, and resolving the floor's Map object walks its object list.
    m.footstepVariationKeyCache = {}
    m.CurrentFootstepVariationKey = function(floorid)
        local now = dmhub.Time()
        local cached = m.footstepVariationKeyCache[floorid]
        if cached ~= nil and now - cached.time < 1 then
            return cached.key
        end
        local state = m.GetFootstepVariationState(floorid)
        local key = nil
        if state ~= nil then
            key = state.key
        end
        m.footstepVariationKeyCache[floorid] = { time = now, key = key }
        return key
    end
end

--============================================================================
--Footstep-surface editing operations (paint / erase). Surfaces are exclusive
--per tile: painting one family removes those tiles from every other family.
--No naming or contiguity machinery - one record per family per floor.
--============================================================================

local function SurfacesOnFloor(floorid)
    MM.EnsureZoneCache()
    local result = {}
    for _,entry in ipairs(m.surfaceCache or {}) do
        if entry.floorid == floorid then
            result[#result+1] = entry
        end
    end
    return result
end

--Writes a surface family's loc set on a floor, removing the record when the
--set goes empty. Record ids are deterministic per family ("surface-6"), so
--painting the same family always merges into its one record.
local function WriteSurfaceLocs(floor, surfaceId, locs)
    local recordId = string.format("surface-%d", surfaceId)
    if locs == nil or #locs == 0 then
        floor:RemoveMarkupZone(recordId)
        return
    end

    local surfaceInfo = SurfaceInfoById(surfaceId)
    local cleanLocs = {}
    for _,l in ipairs(locs) do
        cleanLocs[#cleanLocs+1] = { x = l.x, y = l.y }
    end

    floor:SetMarkupZone(recordId, {
        category = "surface",
        surface = surfaceId,
        surfaceName = (surfaceInfo ~= nil and surfaceInfo.text) or "Surface",
        locs = cleanLocs,
    })
end

--============================================================================
--Public footstep lookup for the audio layer (AudioMain.TokenMovingOnPath and
--creature.PlayLandingFootstep). The map default footstep surface overrides
--tile-DERIVED surfaces (imported map backgrounds often carry a surfaceType of
--their own), but painted footstep regions must keep theirs - and at playback
--both are just ints. This lookup is how the audio code tells them apart.
--Rebuilt lazily from the surface cache whenever the records change.
--============================================================================

m.paintedSurfaceLookup = nil    --floorid -> { "x,y" -> surface id }
m.paintedSurfaceLookupRev = nil

MapMarkupFootsteps = {
    --Returns the painted footstep-surface family id at a tile, or nil when no
    --footstep region is painted there.
    GetPaintedSurfaceAt = function(floorid, x, y)
        if floorid == nil or x == nil or y == nil or not MM.ZonesSupported() then
            return nil
        end
        MM.EnsureZoneCache()

        if m.paintedSurfaceLookup == nil or m.paintedSurfaceLookupRev ~= m.zoneRevision then
            m.paintedSurfaceLookupRev = m.zoneRevision
            m.paintedSurfaceLookup = {}
            for _,entry in ipairs(m.surfaceCache or {}) do
                local floorMap = m.paintedSurfaceLookup[entry.floorid]
                if floorMap == nil then
                    floorMap = {}
                    m.paintedSurfaceLookup[entry.floorid] = floorMap
                end
                for _,l in ipairs(entry.locs) do
                    floorMap[MM.ZoneLocKey(l.x, l.y)] = entry.surface
                end
            end
        end

        local floorMap = m.paintedSurfaceLookup[floorid]
        if floorMap == nil then
            return nil
        end
        return floorMap[MM.ZoneLocKey(x, y)]
    end,

    --Returns the default footstep surface the floor's SELECTED map
    --appearance overrides the map-wide default with, or nil when the map has
    --no appearance alternates or the selected one carries no override (use
    --the map-wide "markup:footstepdefault"). 0 is a real answer: "None - Use
    --Tile Surfaces" for this appearance, even if the map-wide default names
    --a surface. Cheap when the feature is unused: an empty override table
    --returns before any object lookup.
    GetVariationDefaultSurface = function(floorid)
        if floorid == nil then
            return nil
        end
        local ok, stored = pcall(function()
            return gs.footstepVariationSetting:Get()
        end)
        if not ok or type(stored) ~= "table" or next(stored) == nil then
            return nil
        end
        local key = m.CurrentFootstepVariationKey(floorid)
        if key == nil then
            return nil
        end
        local n = tonumber(stored[key])
        if n == nil then
            return nil
        end
        return math.floor(n)
    end,
}


--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.PlaySurfaceSample = PlaySurfaceSample
MM.SurfaceColor = SurfaceColor
MM.SurfaceInfoById = SurfaceInfoById
MM.SurfaceRegistry = SurfaceRegistry
MM.SurfacesOnFloor = SurfacesOnFloor
MM.WriteSurfaceLocs = WriteSurfaceLocs
