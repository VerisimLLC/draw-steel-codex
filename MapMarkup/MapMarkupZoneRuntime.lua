local mod = dmhub.GetModLoading()

--Map Markup: the zone/surface runtime. Caches, aura instance builders, the
--GetMapAuras / GetMarkupZones engine hooks and dynamic light sampling. Runs
--on every client, whether or not the panel is open.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--============================================================================
--ZoneManager: the cache of zone records resolved against their keywords,
--rebuilt whenever the records (dmhub.markupZonesSeq), the map, or the
--compendium tables change. Feeds both engine hooks.
--============================================================================

--Engine support probe: the zone storage API, the GetMapAuras hook and the
--overlay feed all shipped in the same engine build as dmhub.markupZonesSeq.
m.zoneEngineSupport = nil
local function ZonesSupported()
    if m.zoneEngineSupport == nil then
        local ok = pcall(function()
            return dmhub.markupZonesSeq
        end)
        m.zoneEngineSupport = ok
    end
    return m.zoneEngineSupport
end

--Forward declarations: assigned in the panel-state section below. Used by the
--overlay feed's panel-open backstop and its mode report.
m.markupHudRef = function() return nil end
m.markupModeRef = function() return "walls" end

m.zoneCache = nil            --list of resolved zone entries, all floors
m.surfaceCache = nil         --list of resolved footstep-surface entries, all floors
m.zoneCacheSeq = nil
m.zoneCacheMapid = nil
m.zoneCacheTablesGen = nil
m.zoneTablesGen = 0          --bumped on refreshTables (keyword edits)
m.zoneRevision = 0           --bumped on every cache rebuild; overlay cache key
m.zoneAuraInstances = {}     --what dmhub.GetMapAuras returns
m.zoneOverlayZones = {}      --GetMarkupZones list: the rules zones
m.surfaceOverlayZones = {}   --footstep-surface region overlay entries
m.footstepsOverlayZones = {} --GetMarkupZones list in footsteps mode:
                                   --the surface regions + water rules zones
--(The feed's last-reported footstepsMode/panelOpen flags used to be two
--file-level locals here; they now live on m.dispelState as feedFootstepsMode /
--feedPanelOpen, alongside its feedZoneFilter.)

--Dispel suppression state (EnvironmentalKeyword.dispels): live auras whose
--keyword dispels other keywords temporarily carve their tiles out of zones
--of the dispelled keywords -- rules and overlay both -- with the records left
--untouched, so the zones come back when the aura moves on or expires.
--One table rather than several locals plus a function, grouping the related
--state.
--  signature      what the active footprints looked like when the derived
--                 lists were last built (false = must rebuild)
--  footprints     list of {floorIndex, locKeys = set of "x,y", dispelledIds}
--  auraInstances  m.zoneAuraInstances with dispelled tiles removed, or nil
--                 when nothing is suppressed (use the base list)
--  overlayZones   m.zoneOverlayZones likewise, or nil
--  auraSources    index-aligned with m.zoneAuraInstances: the m.zoneCache
--                 entry an instance was built from (absent for surfaces and
--                 holes -- both pass through RebuildLists untouched)
--  overlaySources index-aligned with m.zoneOverlayZones, same idea
--  RebuildLists   derives auraInstances/overlayZones from the base lists
--  feedFootstepsMode / feedPanelOpen / feedZoneFilter
--                 the overlay feed's last-reported state; a flip bumps
--                 m.zoneRevision so the overlay mesh rebuilds (fields here
--                 rather than file-level locals)
m.dispelState = {
    signature = false,
    footprints = {},
    auraInstances = nil,
    overlayZones = nil,
    auraSources = {},
    overlaySources = {},
}

--============================================================================
--Markup "Hole" zones: regions that cut a REAL hole through the floor, using
--the same tech as the excavate hole object (ObjectComponentExcavate).
--
--Storage: one markupZones record per drawn stroke, category "hole":
--  { category = "hole", polygons = { <polygon>, ... }, locs = {{x,y},...} }
--where <polygon> is a flat {x1,y1,x2,y2,...} ring as painted (v1), or a
--structured { points = ring, holes = {ring, ...} } entry once the eraser has
--clipped it (a rect erased from the middle of a hole leaves a donut). The
--cache normalizes both to the structured form on read. The drawn rings are
--kept (they shape the smooth visual cut, the way drawing floors keeps its
--polygons); the rasterized locs drive gameplay per tile, like zone records.
--
--Runtime: one AuraInstance per record with `hole = true` on its Aura
--definition (read by AuraInstance:GetHole). The engine turns that into
--forceGameRules.hole (GetTileRulesAtLoc reports no floor there), registers
--MapGeometry holes from the aura's tiles (creatures fall through), and builds
--the excavation visual from the polygons (MarkupHoleVisuals) -- the same
--alpha-punch material the excavate object uses, so the floor beneath shows
--through. While the Map Markup panel is open the engine hides the visual cut
--and the overlay feed stripes the holes like zones instead.
--
--Holes have no keyword and are not editable like zone types: no Edit dialog,
--no height, no Entire Map pill. The zone eraser CLIPS holes like floor
--erasing clips floors: the erase region is subtracted from the polygons via
--dmhub.ClipPolygons (trim, bisect, or donut; empty result deletes the
--record). On engines without ClipPolygons it falls back to deleting touched
--shapes whole.
--
--One table rather than several file-level locals, grouping the related state.
--============================================================================
m.holes = {
    color = "#555555",   --stripe/swatch color; holes have no keyword to color them
    cache = {},          --resolved hole entries, all floors; rebuilt with the zone cache
    overlayZones = {},   --stripe overlay entries, fed only while the panel is open
    engineSupport = nil,
    --opacity-slider group key for the Holes group in the zone list. Holes
    --have no keywordid, so they need a reserved key that no real keyword can
    --collide with (m.zoneStripes.GroupKey's name: fallback would collide
    --with a keyword literally named "Hole").
    groupKey = "hole:builtin",
}

--Engine capability probe. On a stale engine the hole aura registers as a
--harmless no-op aura and no hole appears, so painting refuses instead of
--appearing to do nothing. (Unknown dmhub properties read as nil silently, so
--== true is the whole test; see supportsObjectEditingFilter for the pattern.)
function m.holes.Supported()
    if m.holes.engineSupport == nil then
        m.holes.engineSupport = (dmhub.supportsMarkupHoles == true)
    end
    return m.holes.engineSupport
end

--The aura that makes a hole real: `hole = true` rides AuraInstance:GetHole
--into the engine (forceGameRules.hole + fall-through map geometry + the
--excavation visual); the polygons ride AuraInstance:GetHolePolygons into the
--visual's mesh.
function m.holes.BuildAuraInstance(entry)
    local auraType = rawget(_G, "Aura")
    local auraInstanceType = rawget(_G, "AuraInstance")
    if auraType == nil or auraInstanceType == nil then
        return nil
    end
    if entry.locsUserdata == nil or #entry.locsUserdata == 0 then
        return nil
    end

    local okShape, shape = pcall(function()
        return dmhub.CalculateShape{
            shape = "locations",
            locations = entry.locsUserdata,
            locOverride = entry.locsUserdata[1],
            range = 0,
            radius = 0,
            checklos = false,
        }
    end)
    if not okShape or shape == nil then
        return nil
    end

    local auraDef = auraType.Create{
        name = "Hole",
        applyto = "all",
        modifiers = {},
        hole = true,
    }

    --No casterid, no duration: permanent and floor-scoped, like zone auras.
    --guid = the record id so the aura identity is stable across rebuilds.
    return auraInstanceType.new{
        aura = auraDef,
        guid = entry.zoneid,
        name = "Hole",
        iconid = "ui-icons/skills/1.png",
        display = { bgcolor = m.holes.color, hueshift = 0, saturation = 1, brightness = 1 },
        area = shape,
        holePolygons = entry.polygons,
    }
end

--Writes a new hole record from a closed stroke. One record per stroke;
--overlapping holes simply overlap (the hole rule and the visual are both
--idempotent per tile), so there is none of the zones' merge/split machinery.
function m.holes.Paint(floor, points, locs)
    if not m.holes.Supported() then
        dmhub.Debug("MARKUP:: hole zones need an engine build with dmhub.supportsMarkupHoles")
        return
    end

    --copy the engine path's points into a plain flat array for storage.
    local polygon = {}
    for i = 1,#points do
        polygon[i] = points[i]
    end

    local cleanLocs = {}
    for _,l in ipairs(locs) do
        cleanLocs[#cleanLocs+1] = { x = l.x, y = l.y }
    end

    floor:SetMarkupZone(dmhub.GenerateGuid(), {
        category = "hole",
        polygons = { polygon },
        locs = cleanLocs,
    })
end

--The label the overlay paints on the map for a zone. Zone names exist to
--tell zones apart in the "Zones on This Floor" list; on the MAP the terrain
--type is the information, so auto-generated names ("Difficult Terrain",
--"Difficult Terrain 2") collapse to the bare type name. A zone the user
--deliberately renamed keeps its custom name on the map.
local function ZoneOverlayLabel(entry)
    local kwName = entry.keywordName
    if kwName == nil or kwName == "" then
        return entry.name
    end

    local name = entry.name or ""
    if name == kwName then
        return kwName
    end
    if string.gsub(name, "%s+%d+$", "") == kwName then
        return kwName
    end
    return name
end

--Rough location of a zone on the map for the "Zones on This Floor" list:
--the map's extent is cut into a 3x3 grid of areas, and the zone's centroid
--picks one. Indexed [row][col] with row 1 = south (low y), col 1 = west
--(low x); world +y is north (the top of the map).
K.ZONE_AREA_NAMES = {
    { "SW Corner", "South Side", "SE Corner" },
    { "West Side", "Center",     "East Side" },
    { "NW Corner", "North Side", "NE Corner" },
}

local function ZoneAreaDescription(entry)
    if entry.locs == nil or #entry.locs == 0 then
        return nil
    end

    local dims = nil
    pcall(function()
        local map = game.currentMap
        if map ~= nil then
            dims = map.dimensions
        end
    end)
    if dims == nil then
        return nil
    end

    --dimensions = (dimMin.x, dimMin.y, dimMax.x+1, dimMax.y+1) in tile-index
    --space: tiles from x to z-1 inclusive. A loc's cell spans [x, x+1) there.
    local w = dims.z - dims.x
    local h = dims.w - dims.y
    if w <= 0 or h <= 0 then
        return nil
    end

    local cx, cy = 0, 0
    for _,l in ipairs(entry.locs) do
        cx = cx + l.x
        cy = cy + l.y
    end
    cx = cx / #entry.locs
    cy = cy / #entry.locs

    local fx = (cx + 0.5 - dims.x) / w
    local fy = (cy + 0.5 - dims.y) / h

    local col = 1 + math.floor(fx * 3)
    local row = 1 + math.floor(fy * 3)
    if col < 1 then col = 1 elseif col > 3 then col = 3 end
    if row < 1 then row = 1 elseif row > 3 then row = 3 end

    return K.ZONE_AREA_NAMES[row][col]
end

--The stripe color handed to the overlay: the stored pattern color with a
--~75% alpha suffix (matching the built-in zone stripe translucency) unless
--the stored color already carries explicit alpha. Only "#rrggbb" strings can
--take the suffix; named colors ("red") and shorthand forms pass through.
local function ZoneOverlayColor(color)
    if type(color) ~= "string" or color == "" then
        return "#d94a3dbf"
    end
    if string.sub(color, 1, 1) ~= "#" then
        return color
    end
    if string.len(color) == 7 then
        return color .. "bf"
    end
    return color
end

local function BuildZoneAuraInstance(entry)
    local auraType = rawget(_G, "Aura")
    local auraInstanceType = rawget(_G, "AuraInstance")
    if auraType == nil or auraInstanceType == nil then
        return nil
    end
    if entry.keywordInfo == nil or entry.locsUserdata == nil or #entry.locsUserdata == 0 then
        return nil
    end

    local okShape, shape = pcall(function()
        return dmhub.CalculateShape{
            shape = "locations",
            locations = entry.locsUserdata,
            locOverride = entry.locsUserdata[1],
            range = 0,
            radius = 0,
            checklos = false,
        }
    end)
    if not okShape or shape == nil then
        return nil
    end

    local auraDef = auraType.Create{
        name = entry.name,
        applyto = "all",
    }

    --Everything the keyword contributes -- terrain flags, modifiers, move
    --damage, entry power roll -- plus the keyword's own table id, which zone
    --auras need because zone names are uniquified per floor and user-renameable,
    --so runtime code that must know WHICH keyword this came from (e.g. the
    --creature "Environment" symbol) resolves the id rather than the name.
    --
    --Shared with the ability-aura path (ActivatedAbilityAuraBehavior:CastOnArea)
    --so a keyword means the same thing whether the area was painted here or
    --created by an ability. EnvironmentalKeyword loads after this module, hence
    --the runtime lookup.
    local environmentalKeywordType = rawget(_G, "EnvironmentalKeyword")
    if environmentalKeywordType ~= nil then
        environmentalKeywordType.ApplyToAura(auraDef, entry.keywordid)
    end

    if entry.height ~= nil then
        auraDef.auraHeight = entry.height
        --Zone bands follow the terrain: the engine measures [altitude,
        --altitude+height] up from the GROUND under each tile tested rather
        --than from the floor's zero altitude (Aura.BandBaseAtLoc /
        --BandBaseForToken). Without this a "ground only" zone would miss a
        --creature standing on a ledge inside it, and a height-2 gas cloud
        --painted across a slope would sit at one absolute altitude instead of
        --hugging the ground. entry.altitude stays an offset above ground.
        auraDef.auraGroundRelative = true
    end
    if entry.altitude ~= nil and entry.altitude ~= 0 then
        auraDef.auraAltitude = entry.altitude
    end

    local iconid = "ui-icons/skills/1.png"
    local display = { bgcolor = entry.patternColor, hueshift = 0, saturation = 1, brightness = 1 }
    pcall(function()
        iconid = entry.keywordInfo:try_get("iconid", iconid)
        local kwDisplay = entry.keywordInfo:try_get("display")
        if kwDisplay ~= nil then
            display = dmhub.DeepCopy(kwDisplay)
        end
    end)

    --The zone type's optional visual representation rides on the INSTANCE
    --(like holePolygons): purely presentational, read by the engine through
    --the AuraInstance:GetAppearance hook and rendered by MarkupZoneVisuals.
    --The dispel machinery rebuilds suppressed zones through this same
    --function with carved locsUserdata, so the visuals follow the carving.
    --Blanket ("Entire Map") entries skip it deliberately: repainting the
    --whole map's floor or scattering thousands of sprites from a palette
    --pill is a footgun. A zone whose visuals are toggled off (the Visuals
    --badge in the zone list, or painted while the type's Visuals pill was
    --off) skips it too and renders as stripes only.
    local appearance = nil
    if entry.entireMap ~= true and entry.hideAppearance ~= true then
        pcall(function()
            local kwAppearance = entry.keywordInfo:try_get("appearance")
            if kwAppearance == nil or kwAppearance.mode == nil or kwAppearance.mode == "none" then
                return
            end
            --hash seed derived from the keyword id: sprite layout and organic
            --edge noise key on absolute world coords + this seed, so
            --every zone of a keyword renders identically on every client and
            --every rebuild. Sprite choices never reshuffle on surviving tiles;
            --organic noise remains anchored to its world-space coordinates.
            local keywordid = entry.keywordid or ""
            local seed = 0
            for i = 1, #keywordid do
                seed = (seed * 33 + string.byte(keywordid, i)) % 1000000007
            end

            if kwAppearance.mode == "floor" then
                if kwAppearance.tileid ~= nil or kwAppearance.edgeWallId ~= nil then
                    appearance = {
                        mode = "floor",
                        tileid = kwAppearance.tileid,
                        edgeWallId = kwAppearance.edgeWallId,
                        alpha = kwAppearance.alpha,
                        fractalEdge = kwAppearance.fractalEdge or 0,
                        edgeFade = kwAppearance.edgeFade or 0,
                        seed = seed,
                    }
                end
            elseif kwAppearance.mode == "sprites" then
                local sprites = kwAppearance.sprites
                if sprites ~= nil and #sprites > 0 then
                    appearance = {
                        mode = "sprites",
                        sprites = dmhub.DeepCopy(sprites),
                        spriteScale = kwAppearance.spriteScale,
                        spriteAlpha = kwAppearance.spriteAlpha,
                        seed = seed,
                    }
                end
            end
        end)
    end

    --No casterid, no tokenAttached, no duration: a permanent, floor-scoped,
    --uncontrolled aura. guid = zoneid so triggers/entered-tracking key stably.
    return auraInstanceType.new{
        aura = auraDef,
        guid = entry.zoneid,
        name = entry.name,
        iconid = iconid,
        display = display,
        area = shape,
        appearance = appearance,
    }
end

--Builds the aura that applies a footstep-surface region to the game: it
--carries ONLY surfaceType (no modifiers, no rule flags), so the region
--affects footstep sounds and nothing else. Water flags from tile art or
--Water zones co-exist on the same tiles and win at playback time.
local function BuildSurfaceAuraInstance(entry)
    local auraType = rawget(_G, "Aura")
    local auraInstanceType = rawget(_G, "AuraInstance")
    if auraType == nil or auraInstanceType == nil then
        return nil
    end
    if entry.locsUserdata == nil or #entry.locsUserdata == 0 then
        return nil
    end

    local okShape, shape = pcall(function()
        return dmhub.CalculateShape{
            shape = "locations",
            locations = entry.locsUserdata,
            locOverride = entry.locsUserdata[1],
            range = 0,
            radius = 0,
            checklos = false,
        }
    end)
    if not okShape or shape == nil then
        return nil
    end

    --"Footsteps: Stone" rather than a bare "Stone": the aura name is what any
    --aura-listing UI would show, and the region only changes footstep sounds.
    local auraName = string.format("Footsteps: %s", entry.name)
    local auraDef = auraType.Create{
        name = auraName,
        applyto = "all",
        modifiers = {},
        surfaceType = entry.surface,
    }

    --guid: surface record ids repeat across floors ("surface-6" on every
    --floor), so qualify with the floor for a stable unique aura identity.
    return auraInstanceType.new{
        aura = auraDef,
        guid = string.format("%s-%s", entry.floorid, entry.zoneid),
        name = auraName,
        iconid = "ui-icons/skills/1.png",
        display = { bgcolor = entry.patternColor, hueshift = 0, saturation = 1, brightness = 1 },
        area = shape,
    }
end

--Builds the blanket entries for the current map: one per (blanket keyword,
--floor), covering the map's whole extent minus the tiles of painted zones
--that interact with that keyword. Called from RebuildZoneCache after the
--record walk, because it carves against the painted zones that walk found.
--`floors` is the {floorid, floorIndex} list collected there.
function m.entireMap.Rebuild(floors)
    m.entireMap.entries = {}

    local ids = m.entireMap.Keywords()
    if next(ids) == nil then
        return
    end

    local dims = nil
    pcall(function()
        local map = game.currentMap
        if map ~= nil then
            dims = map.dimensions
        end
    end)
    if dims == nil then
        return
    end

    --dimensions = (dimMin.x, dimMin.y, dimMax.x+1, dimMax.y+1) in tile-index
    --space -- tiles run x..z-1 inclusive. See ZoneAreaDescription.
    local x0, y0 = math.floor(dims.x), math.floor(dims.y)
    local x1, y1 = math.floor(dims.z) - 1, math.floor(dims.w) - 1
    if x1 < x0 or y1 < y0 then
        return
    end

    local dynThresholds = m.dynamicLight.Thresholds()

    for keywordid,_ in pairs(ids) do
        local kw = MM.GetKeyword(keywordid)
        if kw ~= nil then
            local dispels = MM.KeywordDispels(kw)
            local kwName = kw.name or "Zone"
            local dynPct = dynThresholds[keywordid]

            for _,floorInfo in ipairs(floors) do
                --tiles the blanket yields to. Same keyword: a painted zone
                --already covers them (and a second aura would double up any
                --damage/modifier the keyword carries). Either dispel
                --direction: the explicitly painted zone takes the ground,
                --matching "last drawn wins" at paint time.
                local blocked = {}
                for _,entry in ipairs(m.zoneCache) do
                    if entry.floorid == floorInfo.floorid and entry.keywordid ~= nil
                        and (entry.keywordid == keywordid
                            or dispels[entry.keywordid] ~= nil
                            or MM.KeywordDispels(entry.keywordInfo)[keywordid] ~= nil) then
                        for _,l in ipairs(entry.locs) do
                            blocked[MM.ZoneLocKey(l.x, l.y)] = true
                        end
                    end
                end

                --a dynamic-light blanket covers only the tiles the light
                --sampler currently reports dark. No sample yet = covers
                --nothing: on a lit map that avoids a flash of whole-map
                --darkness in the second before the first sample lands.
                local darkState = nil
                if dynPct ~= nil then
                    darkState = m.dynamicLight.states[m.dynamicLight.StateKey(floorInfo.floorid, dynPct)]
                end

                local locs = {}
                if dynPct == nil or darkState ~= nil then
                    for y = y0, y1 do
                        for x = x0, x1 do
                            local key = MM.ZoneLocKey(x, y)
                            if blocked[key] == nil
                                and (dynPct == nil or darkState.dark[key] ~= nil) then
                                locs[#locs+1] = { x = x, y = y }
                            end
                        end
                    end
                end

                if #locs > 0 then
                    m.entireMap.entries[#m.entireMap.entries+1] = {
                        --stable per keyword+floor: the aura guid keys
                        --triggers and entered-tracking off it.
                        zoneid = string.format("entiremap-%s-%s", keywordid, floorInfo.floorid),
                        floorid = floorInfo.floorid,
                        floorIndex = floorInfo.floorIndex,
                        name = kwName,
                        keywordid = keywordid,
                        keywordName = kwName,
                        keywordInfo = kw,
                        flags = MM.KeywordFlags(kw),
                        locs = locs,
                        altitude = 0,
                        --height stays absent: unlimited, so the blanket
                        --reaches flyers as well as the ground.
                        playerVisible = false,
                        patternColor = MM.KeywordColor(keywordid, kw),
                        patternAngle = m.zoneStripes.AngleForKeyword(keywordid),
                        entireMap = true,
                    }
                end
            end
        end
    end
end

local function RebuildZoneCache()
    m.zoneCache = {}
    m.surfaceCache = {}
    m.zoneAuraInstances = {}
    m.zoneOverlayZones = {}
    m.surfaceOverlayZones = {}
    m.footstepsOverlayZones = {}
    m.holes.cache = {}
    m.holes.overlayZones = {}

    --any active dispel suppression must re-derive against the fresh lists;
    --signature=false forces that on the next EnsureKeywordAuraZones.
    m.dispelState.signature = false
    m.dispelState.auraInstances = nil
    m.dispelState.overlayZones = nil
    m.dispelState.auraSources = {}
    m.dispelState.overlaySources = {}

    local map = game.currentMap
    if map == nil then
        --no map = no zone instances: any running zone scripts must get their
        --exit routine. (EnvironmentalKeyword loads after this file, so it is
        --resolved at call time, rawget-guarded like the other keyword refs.)
        local keywordType = rawget(_G, "EnvironmentalKeyword")
        if keywordType ~= nil and rawget(keywordType, "SyncZoneScripts") ~= nil then
            keywordType.SyncZoneScripts({})
        end
        return
    end

    --every floor the map currently shows, for the "Entire Map" blanket pass
    --below. Layers are separate entries here with their own floorIndex, which
    --is right: a token stands on exactly one of them.
    local floorList = {}

    for _,floor in ipairs(map.floors or {}) do
        local zones = nil
        local floorIndex = nil
        pcall(function()
            zones = floor.markupZones
            floorIndex = floor.floorIndex
        end)

        if floorIndex ~= nil and floorIndex >= 0 then
            floorList[#floorList+1] = { floorid = floor.floorid, floorIndex = floorIndex }
        end

        --floorIndex is -1 when the floor isn't currently visible (e.g. the
        --title screen); keep the records in the cache (the zone list needs
        --them) and skip only the aura/overlay build below.
        if zones ~= nil and floorIndex ~= nil then
            local floorid = floor.floorid
            for zoneid,record in pairs(zones) do
                if type(record) == "table" and record.category == "surface" then
                    local surfaceId = math.floor(tonumber(record.surface) or 0)
                    local surfaceInfo = MM.SurfaceInfoById(surfaceId)
                    local locs = {}
                    for _,l in ipairs(record.locs or {}) do
                        if type(l) == "table" and l.x ~= nil and l.y ~= nil then
                            locs[#locs+1] = { x = math.floor(l.x), y = math.floor(l.y) }
                        end
                    end

                    local name = record.surfaceName or "Surface"
                    if surfaceInfo ~= nil then
                        name = surfaceInfo.text
                    end

                    m.surfaceCache[#m.surfaceCache+1] = {
                        zoneid = zoneid,
                        floorid = floorid,
                        floorIndex = floorIndex,
                        surface = surfaceId,
                        name = name,
                        locs = locs,
                        patternColor = MM.SurfaceColor(surfaceId),
                        --a surface family is exclusive per tile and has no
                        --keyword, so its angle just alternates by family id;
                        --stored here so the panel's swatch can match the map.
                        patternAngle = cond(surfaceId % 2 == 0, K.ZONE_ANGLE_B, K.ZONE_ANGLE_A),
                    }
                elseif type(record) == "table" and record.category == "hole" then
                    local locs = {}
                    for _,l in ipairs(record.locs or {}) do
                        if type(l) == "table" and l.x ~= nil and l.y ~= nil then
                            locs[#locs+1] = { x = math.floor(l.x), y = math.floor(l.y) }
                        end
                    end

                    --normalize each stored polygon to the structured form
                    --{points = flat ring, holes = {flat ring, ...}}. Paint
                    --writes flat rings (the v1 shape); the eraser's clip
                    --rewrites write structured entries. A valid ring is a
                    --flat array of at least three vertices.
                    local polygons = {}
                    for _,polygon in ipairs(record.polygons or {}) do
                        if type(polygon) == "table" then
                            if type(polygon[1]) == "number" then
                                if #polygon >= 6 then
                                    polygons[#polygons+1] = { points = polygon, holes = {} }
                                end
                            elseif type(polygon.points) == "table" and #polygon.points >= 6 then
                                local holeRings = {}
                                for _,holeRing in ipairs(polygon.holes or {}) do
                                    if type(holeRing) == "table" and #holeRing >= 6 then
                                        holeRings[#holeRings+1] = holeRing
                                    end
                                end
                                polygons[#polygons+1] = { points = polygon.points, holes = holeRings }
                            end
                        end
                    end

                    m.holes.cache[#m.holes.cache+1] = {
                        zoneid = zoneid,
                        floorid = floorid,
                        floorIndex = floorIndex,
                        locs = locs,
                        polygons = polygons,
                        --display fields so the "Zones on This Floor" list can
                        --render holes with the same row builder as zones. The
                        --hole flag is what the row branches on.
                        hole = true,
                        name = "Hole",
                        keywordName = "Hole",
                        patternColor = m.holes.color,
                        patternAngle = K.ZONE_ANGLE_A,
                    }
                elseif type(record) == "table" and record.category == nil then
                    --resolve the keyword by id, healing dead ids by stored
                    --name (ids can be lost to the objectTable-creation race;
                    --see MaterializeZonePreset). The healed id flows back
                    --into the record on the zone's next write.
                    local kwId = record.keyword
                    local kw = MM.GetKeyword(kwId)
                    if kw == nil and record.keywordName ~= nil then
                        local healedId = MM.FindKeywordIdByName(record.keywordName)
                        if healedId ~= nil then
                            kwId = healedId
                            kw = MM.GetKeyword(healedId)
                        end
                    end
                    local kwName = record.keywordName
                    if kw ~= nil and kw.name ~= nil then
                        kwName = kw.name
                    end
                    local pattern = record.pattern or {}

                    --the keyword's LIVE color wins so recoloring a keyword in
                    --the compendium recolors its painted zones. The color
                    --stored on the record is only a fallback for records
                    --whose keyword can't be resolved (dead id from the
                    --table-creation race; see MaterializeZonePreset).
                    local patternColor
                    if kw ~= nil then
                        patternColor = MM.KeywordColor(kwId, kw)
                    else
                        patternColor = pattern.color or MM.KeywordColor(kwId, kw)
                    end

                    --the angle is derived from the keyword for the same reason
                    --the color is: it must be the same for every zone of that
                    --keyword on the map, whatever angle happened to be stored
                    --when each one was painted. Deriving it needs the whole map
                    --at once (see AssignZoneStripeAngles), so this is only the
                    --fallback for records whose keyword can't be resolved; the
                    --second pass below overwrites the rest.
                    local locs = {}
                    for _,l in ipairs(record.locs or {}) do
                        if type(l) == "table" and l.x ~= nil and l.y ~= nil then
                            locs[#locs+1] = { x = math.floor(l.x), y = math.floor(l.y) }
                        end
                    end

                    m.zoneCache[#m.zoneCache+1] = {
                        zoneid = zoneid,
                        floorid = floorid,
                        floorIndex = floorIndex,
                        name = record.name or "Zone",
                        keywordid = kwId,
                        keywordName = kwName,
                        keywordInfo = kw,
                        flags = MM.KeywordFlags(kw),
                        locs = locs,
                        altitude = record.altitude or 0,
                        height = record.height,
                        playerVisible = record.playerVisible == true,
                        hideAppearance = record.hideAppearance == true,
                        patternColor = patternColor,
                        patternAngle = pattern.angle or K.ZONE_ANGLE_A,
                        ord = record.ord or 0,
                    }
                end
            end
        end
    end

    --Stripe angles are decided across the whole map at once so similar-coloured
    --keywords land on opposite angles, which can only happen once every zone is
    --in the cache. Records whose keyword didn't resolve keep the angle stored
    --on them (AngleForKeyword has nothing better to offer for a dead id).
    MM.AssignZoneStripeAngles(m.zoneCache)
    for _,entry in ipairs(m.zoneCache) do
        if entry.keywordid ~= nil then
            entry.patternAngle = m.zoneStripes.AngleForKeyword(entry.keywordid)
        end
    end

    table.sort(m.surfaceCache, function(a, b)
        if a.floorid ~= b.floorid then
            return a.floorid < b.floorid
        end
        return a.surface < b.surface
    end)

    --Surface overlay entries go in their own list: the feed hands the engine
    --the rules zones normally, or - on the Footsteps tab - the footstep
    --surface regions plus the water rules zones (assembled into
    --m.footstepsOverlayZones below; see dmhub.GetMarkupZones). Surfaces
    --render in the normal zone-stripe style, distinguished by the footprints
    --icon on their labels; the stripe angle alternates by family so adjacent
    --regions of similar colors still read as distinct.
    for _,entry in ipairs(m.surfaceCache) do
        if #entry.locs > 0 and entry.floorIndex >= 0 then
            local locsUserdata = {}
            for _,l in ipairs(entry.locs) do
                locsUserdata[#locsUserdata+1] = core.Loc{
                    x = l.x,
                    y = l.y,
                    floorIndex = entry.floorIndex,
                }
            end
            entry.locsUserdata = locsUserdata

            m.surfaceOverlayZones[#m.surfaceOverlayZones+1] = {
                locs = locsUserdata,
                color = ZoneOverlayColor(entry.patternColor),
                angleRadians = entry.patternAngle,
                label = entry.name,
                labelIcon = "phosphor/footprints-fill.png",
                playerVisible = false,
                floorIndex = entry.floorIndex,
            }

            local instance = BuildSurfaceAuraInstance(entry)
            if instance ~= nil then
                m.zoneAuraInstances[#m.zoneAuraInstances+1] = instance
            end
        end
    end

    table.sort(m.zoneCache, function(a, b)
        if a.floorid ~= b.floorid then
            return a.floorid < b.floorid
        end
        if a.ord ~= b.ord then
            return a.ord < b.ord
        end
        return a.zoneid < b.zoneid
    end)

    --dynamic-light types register/stripe only their currently-dark tiles; the
    --record locs (entry.locs) stay pristine -- they drive painting/splitting.
    local dynThresholds = m.dynamicLight.Thresholds()

    for _,entry in ipairs(m.zoneCache) do
        local paintLocs = m.dynamicLight.ApplyFilter(dynThresholds, entry)
        if #paintLocs > 0 and entry.floorIndex >= 0 then
            local locsUserdata = {}
            for _,l in ipairs(paintLocs) do
                locsUserdata[#locsUserdata+1] = core.Loc{
                    x = l.x,
                    y = l.y,
                    floorIndex = entry.floorIndex,
                }
            end
            entry.locsUserdata = locsUserdata

            m.zoneOverlayZones[#m.zoneOverlayZones+1] = {
                locs = locsUserdata,
                color = ZoneOverlayColor(entry.patternColor),
                angleRadians = entry.patternAngle,
                label = ZoneOverlayLabel(entry),
                playerVisible = entry.playerVisible,
                difficultTerrain = entry.flags.difficultTerrain,
                water = entry.flags.water,
                concealment = entry.flags.concealment,
                climbable = entry.flags.climbable,
                floorIndex = entry.floorIndex,
                --the engine ignores this; the feed uses it to filter zones by
                --the user's per-zone-type visibility preference.
                keywordid = entry.keywordid,
                --likewise ignored by the engine: the feed uses it to apply the
                --Zones list's per-group opacity slider. Separate from
                --keywordid because a record with an unresolvable keyword still
                --belongs to a group (see m.zoneStripes.GroupKey).
                zonegroup = m.zoneStripes.GroupKey(entry),
            }
            m.dispelState.overlaySources[#m.zoneOverlayZones] = entry

            local instance = BuildZoneAuraInstance(entry)
            if instance ~= nil then
                m.zoneAuraInstances[#m.zoneAuraInstances+1] = instance
                m.dispelState.auraSources[#m.zoneAuraInstances] = entry
            end
        end
    end

    --Markup holes: one aura per record. No dispel bookkeeping (holes have no
    --keyword): instances appended WITHOUT an auraSources entry pass through
    --m.dispelState.RebuildLists untouched, which is exactly right. The overlay
    --entries go in their own list; the feed appends them only while the panel
    --is open (with it closed the engine renders the actual hole instead).
    for _,entry in ipairs(m.holes.cache) do
        if #entry.locs > 0 and entry.floorIndex >= 0 then
            local locsUserdata = {}
            for _,l in ipairs(entry.locs) do
                locsUserdata[#locsUserdata+1] = core.Loc{
                    x = l.x,
                    y = l.y,
                    floorIndex = entry.floorIndex,
                }
            end
            entry.locsUserdata = locsUserdata

            m.holes.overlayZones[#m.holes.overlayZones+1] = {
                locs = locsUserdata,
                color = ZoneOverlayColor(m.holes.color),
                angleRadians = K.ZONE_ANGLE_A,
                label = "Hole",
                playerVisible = false,
                floorIndex = entry.floorIndex,
            }

            local instance = m.holes.BuildAuraInstance(entry)
            if instance ~= nil then
                m.zoneAuraInstances[#m.zoneAuraInstances+1] = instance
            end
        end
    end

    --"Entire Map" types: one aura per floor over everything the painted zones
    --left it, and NO overlay entry - a blanket that striped the whole map
    --would bury the zones the DM is painting. They go in auraSources like any
    --other zone so a live dispelling aura suppresses them the same way.
    m.entireMap.Rebuild(floorList)
    for _,entry in ipairs(m.entireMap.entries) do
        local locsUserdata = {}
        for _,l in ipairs(entry.locs) do
            locsUserdata[#locsUserdata+1] = core.Loc{
                x = l.x,
                y = l.y,
                floorIndex = entry.floorIndex,
            }
        end
        entry.locsUserdata = locsUserdata

        local instance = BuildZoneAuraInstance(entry)
        if instance ~= nil then
            m.zoneAuraInstances[#m.zoneAuraInstances+1] = instance
            m.dispelState.auraSources[#m.zoneAuraInstances] = entry
        end
    end

    --Footsteps-mode feed list: the surface regions plus any WATER rules
    --zones. A water tile plays water sounds over any painted footstep
    --surface, so the DM needs to see water while painting footsteps. Water
    --zones go last so they draw over surface stripes where the two overlap
    --(the water sound is what actually wins there).
    for _,overlayZone in ipairs(m.surfaceOverlayZones) do
        m.footstepsOverlayZones[#m.footstepsOverlayZones+1] = overlayZone
    end
    for _,overlayZone in ipairs(m.zoneOverlayZones) do
        if overlayZone.water then
            m.footstepsOverlayZones[#m.footstepsOverlayZones+1] = overlayZone
        end
    end

    --Zone scripts: one instance of a keyword's Lua script per zone of that
    --keyword on the map, Entire Map blankets included. The runtime lives in
    --EnvironmentalKeyword.lua; it diffs against the previous rebuild, so
    --zones that appeared here instantiate and zones that vanished run their
    --guaranteed exit routine. Runs LAST so every entry's locsUserdata (the
    --active tiles - dynamic light already applied) is in place.
    --(EnvironmentalKeyword loads after this file: resolve at call time,
    --rawget-guarded like the other keyword refs.)
    local keywordType = rawget(_G, "EnvironmentalKeyword")
    if keywordType ~= nil and rawget(keywordType, "SyncZoneScripts") ~= nil then
        keywordType.SyncZoneScripts({m.zoneCache, m.entireMap.entries})
    end
end

--Derives the dispel-suppressed lists from the base lists and the current
--footprints: zones of a dispelled keyword lose the tiles a dispelling aura
--covers, in both the registered aura (rules) and the overlay (stripes). The
--records are untouched -- when the aura leaves, the footprints change and
--the full zone comes back. nil derived lists mean "nothing suppressed, use
--the base lists". Coordinates are rounded before keying: aura-area locs are
--not guaranteed exact integers (see CollectKeywordAuraZones).
--(A field on m.dispelState rather than a chunk local: it groups the dispel state.)
function m.dispelState.RebuildLists()
    m.dispelState.auraInstances = nil
    m.dispelState.overlayZones = nil

    local footprints = m.dispelState.footprints or {}
    if #footprints == 0 then
        return
    end

    --zoneid -> set of suppressed "x,y" keys. Painted zones and "Entire Map"
    --blankets alike: a live dispelling aura carves both.
    local suppressedByZone = {}
    local CollectSuppressed = function(entries)
        for _,entry in ipairs(entries or {}) do
            if entry.keywordid ~= nil and entry.floorIndex ~= nil and entry.floorIndex >= 0 then
                local suppressed = nil
                for _,fp in ipairs(footprints) do
                    if fp.floorIndex == entry.floorIndex and fp.dispelledIds[entry.keywordid] ~= nil then
                        for _,l in ipairs(entry.locs) do
                            local key = MM.ZoneLocKey(l.x, l.y)
                            if fp.locKeys[key] ~= nil then
                                suppressed = suppressed or {}
                                suppressed[key] = true
                            end
                        end
                    end
                end
                if suppressed ~= nil then
                    suppressedByZone[entry.zoneid] = suppressed
                end
            end
        end
    end
    CollectSuppressed(m.zoneCache)
    CollectSuppressed(m.entireMap.entries)

    if next(suppressedByZone) == nil then
        return
    end

    local instances = {}
    for i,instance in ipairs(m.zoneAuraInstances) do
        local entry = m.dispelState.auraSources[i]
        local suppressed = nil
        if entry ~= nil then
            suppressed = suppressedByZone[entry.zoneid]
        end
        if suppressed == nil then
            instances[#instances+1] = instance
        else
            local filtered = {}
            for _,loc in ipairs(entry.locsUserdata or {}) do
                if suppressed[MM.ZoneLocKey(math.floor(loc.x + 0.5), math.floor(loc.y + 0.5))] == nil then
                    filtered[#filtered+1] = loc
                end
            end
            --a fully-suppressed zone registers no aura at all.
            if #filtered > 0 then
                local subEntry = {}
                for k,v in pairs(entry) do
                    subEntry[k] = v
                end
                subEntry.locsUserdata = filtered
                local subInstance = BuildZoneAuraInstance(subEntry)
                if subInstance ~= nil then
                    instances[#instances+1] = subInstance
                end
            end
        end
    end
    m.dispelState.auraInstances = instances

    local overlays = {}
    for i,zone in ipairs(m.zoneOverlayZones) do
        local entry = m.dispelState.overlaySources[i]
        local suppressed = nil
        if entry ~= nil then
            suppressed = suppressedByZone[entry.zoneid]
        end
        if suppressed == nil then
            overlays[#overlays+1] = zone
        else
            local filtered = {}
            for _,loc in ipairs(zone.locs or {}) do
                if suppressed[MM.ZoneLocKey(math.floor(loc.x + 0.5), math.floor(loc.y + 0.5))] == nil then
                    filtered[#filtered+1] = loc
                end
            end
            if #filtered > 0 then
                local copy = {}
                for k,v in pairs(zone) do
                    copy[k] = v
                end
                copy.locs = filtered
                overlays[#overlays+1] = copy
            end
        end
    end
    m.dispelState.overlayZones = overlays
end

local function EnsureZoneCache()
    if not ZonesSupported() then
        return
    end

    local seq = dmhub.markupZonesSeq
    local mapid = game.currentMapId
    --blankets live in a per-map setting, not in the zone records, so no
    --record write (and no seq bump) accompanies a change to them -- here or
    --on another client. Compare the value itself. Dynamic light is the same
    --shape: a per-map setting plus the sampling serial.
    local blanketKey = m.entireMap.CacheKey()
    local dynamicKey = m.dynamicLight.CacheKey()
    if m.zoneCache ~= nil and seq == m.zoneCacheSeq and mapid == m.zoneCacheMapid
        and m.zoneCacheTablesGen == m.zoneTablesGen and blanketKey == m.entireMap.cacheKey
        and dynamicKey == m.dynamicLight.cacheKey then
        return
    end

    m.zoneCacheSeq = seq
    m.zoneCacheMapid = mapid
    m.zoneCacheTablesGen = m.zoneTablesGen
    m.entireMap.cacheKey = blanketKey
    m.dynamicLight.cacheKey = dynamicKey
    m.zoneRevision = m.zoneRevision + 1
    RebuildZoneCache()
end

--The engine hooks (dmhub.GetMapAuras / dmhub.GetMarkupZones) are assigned
--BELOW EnsureKeywordAuraZones -- both closures call it, and a local is only
--captured when it is already in scope at closure creation (the same trap as
--m.markupHudRef above).

--Openness is read from the LIVE panel, not from the show/hide events.
--showpanel/hidepanel only fire on a dock TAB switch (DockablePanel.lua's
--buttonContainer `select`), so a tracked flag goes stale in two ways that
--both leave the overlay dark with the panel plainly on screen:
--  * a Lua reload rebuilds the panel content (refreshMod -> init -> content())
--    with no showpanel;
--  * a saved dock layout can build the content at startup without showing it.
--So: open means the content exists, is alive, is parented into the UI, and no
--ancestor is collapsed away. Every host hides this content with the
--"collapsed" class on some ancestor -- the dock on its dockablePanel, the
--rail panel window (DocumentSystem's PanelDocument host, which has NO
--dockablePanel ancestor) on both its per-tab wrapper (tab switched away) and
--its contentArea (window shaded) -- so walking the parent chain covers all of
--them, plus the harness, without host-specific casing. Checking only the
--dockablePanel ancestor here was exactly the bug that left the Fade Map
--slider dead when the panel was hosted in a rail window.
local function MarkupPanelIsOpen()
    local hud = m.markupHudRef()
    if hud == nil or not hud.valid then
        return false
    end
    local ok, parent = pcall(function() return hud.parent end)
    if not ok or parent == nil then
        return false
    end

    local p = parent
    while p ~= nil and p.valid do
        if p:HasClass("collapsed") then
            return false
        end
        local okParent, nextParent = pcall(function() return p.parent end)
        if not okParent then
            return false
        end
        p = nextParent
    end

    return true
end

--Live auras that name an Environmental Keyword paint like a hand-painted zone:
--the keyword's colour, the keyword's name, and the same stripe treatment, so
--darkness dropped by an ability reads identically to a Darkness zone painted
--here. Without this they fall through to the engine's built-in terrain-rule
--overlay, which flood-fills by rule flag and labels generically -- an ability's
--darkness came out as "Concealment" (TileHeightOverlay.cs ZoneLabelText).
--Routing them through this feed also suppresses the built-in stripe on their
--tiles (BuiltinZoneSuppressed), so the two treatments don't double up.
--
--Auras are reached through their owners: everything cast onto the map or granted
--by an aura modifier is registered on a creature (creature:AddAura). Auras on
--map OBJECTS (AuraComponent) are not reachable from Lua and so are not covered.
--Painted zones are not collected here either -- they reach the feed already,
--via m.zoneCache.
--
--State lives in one table rather than two locals, grouping the related state.
--`instances` holds the rules-only AuraInstance
--clones registered with the engine for keyword auras that have no other
--registration path (see CollectKeywordAuraZones below).
m.keywordAuraOverlay = { zones = {}, signature = false, instances = nil }

--Appends one overlay entry per (aura, keyword) pair, and accumulates into
--`signature` everything the resulting overlay mesh depends on. Also appends
--a dispel footprint per (aura, keyword-with-dispels) pair into `footprints`
--(the tiles where that keyword's dispelled zones are suppressed; see
--m.dispelState) and accumulates everything the suppression depends on into
--`dispelSignature`.
--
--`ruleSources` collects the aura instances that need ENGINE RULES
--registration through the dmhub.GetMapAuras feed: a placed (not
--token-attached) aura's tile rules normally reach the engine through its
--spawned map object, and a token-attached aura's through
--CharacterToken.CalculateAuras -- but a placed aura with NO object (the
--zone-styled ability auras, e.g. Shadow Drag's difficult terrain trail) has
--neither vehicle, so its difficult_terrain/water/move-damage rules would
--silently not exist. Those instances are cloned rules-only (modifiers
--stripped -- the token-aura walk already applies modifiers Lua-side, so
--carrying them here would double-apply) and returned from the GetMapAuras
--hook alongside the zone auras.
local function CollectKeywordAuraZones(auraInstance, keywordsTable, zones, signature, footprints, dispelSignature, ruleSources)
    local auraDef = auraInstance:try_get("aura")
    if auraDef == nil then
        return
    end

    --Parent and sub-auras each carry their own keyword and share one area, so a
    --single aura can paint its tiles with more than one keyword.
    local keywordIds = {}
    local seenKeywords = {}
    local function AddKeyword(keywordid)
        if keywordid ~= nil and seenKeywords[keywordid] == nil then
            seenKeywords[keywordid] = true
            keywordIds[#keywordIds+1] = keywordid
        end
    end

    AddKeyword(auraDef:try_get("environmentalKeywordId"))
    for _,childDef in ipairs(auraDef:try_get("subauras", {})) do
        AddKeyword(childDef:try_get("environmentalKeywordId"))
    end

    if #keywordIds == 0 then
        return
    end

    local area = auraInstance:GetArea()
    if area == nil then
        return
    end

    --One floor per entry, matching the engine's per-floor emit. An aura area
    --sits on a single floor in practice; the first location decides, and stray
    --locations from another floor are dropped rather than mislabelled there.
    --
    --The read accessor is loc.floor (Definitions/Loc.lua), NOT loc.floorIndex --
    --core.Loc{} takes floorIndex when CONSTRUCTING one, but reading that name
    --back yields nil silently, which drops every aura here.
    local locs = {}
    local floorIndex = nil
    for _,loc in ipairs(area.locations or {}) do
        if floorIndex == nil then
            floorIndex = loc.floor
        end
        if loc.floor == floorIndex then
            locs[#locs+1] = loc
            --plain concatenation, not string.format("%d"): that throws in 5.4 on
            --any coordinate without an exact integer representation, and this
            --runs inside a pcall where the throw would silently drop the aura.
            signature[#signature+1] = floorIndex .. "." .. loc.x .. "." .. loc.y
        end
    end

    if #locs == 0 or floorIndex == nil or floorIndex < 0 then
        return
    end

    --Needs engine-rules registration via GetMapAuras: placed (not
    --token-attached, so CharacterToken doesn't register it) and objectless
    --(so no spawned object registers it either).
    if not auraInstance:try_get("tokenAttached", false) and auraInstance:try_get("object") == nil then
        ruleSources[#ruleSources+1] = auraInstance
    end

    for _,keywordid in ipairs(keywordIds) do
        local keyword = keywordsTable[keywordid]
        if keyword ~= nil then
            local flags = MM.KeywordFlags(keyword)
            zones[#zones+1] = {
                locs = locs,
                color = ZoneOverlayColor(MM.KeywordColor(keywordid, keyword)),
                --same angle a painted zone of this keyword gets, so an
                --ability's darkness stripes identically to a Darkness zone.
                angleRadians = m.zoneStripes.AngleForKeyword(keywordid),
                label = keyword.name,
                --a painted zone can be DM-only, but an aura is already on screen
                --for everyone, so hiding just its label would be strange.
                playerVisible = true,
                difficultTerrain = flags.difficultTerrain,
                water = flags.water,
                concealment = flags.concealment,
                climbable = flags.climbable,
                floorIndex = floorIndex,
                --the engine ignores this; the feed uses it to filter zones by
                --the user's per-zone-type visibility preference.
                keywordid = keywordid,
            }
            signature[#signature+1] = keywordid

            --dispel footprint: the aura's tiles, keyed the way zone locs are
            --keyed. Rounded rather than %d-formatted for the same reason as
            --the concatenation note above: coordinates are not guaranteed to
            --be exact integers, and this runs inside a pcall where a throw
            --would silently drop the aura.
            local dispelledIds = MM.KeywordDispels(keyword)
            if next(dispelledIds) ~= nil then
                local locKeys = {}
                for _,loc in ipairs(locs) do
                    locKeys[MM.ZoneLocKey(math.floor(loc.x + 0.5), math.floor(loc.y + 0.5))] = true
                end
                footprints[#footprints+1] = {
                    floorIndex = floorIndex,
                    locKeys = locKeys,
                    dispelledIds = dispelledIds,
                }
                for dispelledId,_ in pairs(dispelledIds) do
                    dispelSignature[#dispelSignature+1] = keywordid .. ">" .. dispelledId
                end
                for _,loc in ipairs(locs) do
                    dispelSignature[#dispelSignature+1] = keywordid .. "@" .. floorIndex .. "." .. loc.x .. "." .. loc.y
                end
            end
        end
    end
end

--Rebuilds the keyword-aura overlay entries when anything they depend on moves.
--This runs on the every-frame feed, so the walk stays cheap (tokens and their
--aura lists) and the entries are only replaced -- and the overlay revision only
--bumped -- when the signature actually changes. Auras follow their token and
--expire mid-round, so the signature covers occupied tiles as well as identity:
--miss that and the overlay keeps drawing darkness that has already ended, or
--fails to draw one just cast. The signature is sorted so it identifies the SET
--of painted tiles: were it order-sensitive, any reshuffle of area.locations
--would bump the revision every frame and re-mesh the overlay continuously.
local function EnsureKeywordAuraZones(suppressAuraRefresh)
    local zones = {}
    local signature = {}
    local footprints = {}
    local dispelSignature = {}
    local ruleSources = {}

    pcall(function()
        local keywordsTable = dmhub.GetTable(K.ENVIRONMENTAL_KEYWORDS_TABLE) or {}
        for _,token in ipairs(dmhub.allTokensIncludingObjects) do
            local props = token.properties
            if props ~= nil then
                local auras = props:try_get("auras", {})
                local ok, generatedAuras = pcall(function()
                    if type(props.GetAuras) == "function" then
                        return props:GetAuras()
                    end
                end)
                if ok and generatedAuras ~= nil then
                    auras = generatedAuras
                end

                --one bad aura shouldn't cost the whole overlay.
                for _,auraInstance in ipairs(auras) do
                    pcall(function()
                        if not auraInstance:try_get("isChildAura", false) then
                            CollectKeywordAuraZones(auraInstance, keywordsTable, zones, signature, footprints, dispelSignature, ruleSources)
                        end
                    end)
                end
            end
        end
    end)

    table.sort(signature)
    local newSignature = table.concat(signature, "|")
    if newSignature ~= m.keywordAuraOverlay.signature then
        m.keywordAuraOverlay.signature = newSignature
        m.keywordAuraOverlay.zones = zones
        m.zoneRevision = m.zoneRevision + 1

        --Rebuild the rules-only clones the GetMapAuras hook hands the engine
        --(see the ruleSources note on CollectKeywordAuraZones). Rebuilt only on
        --signature change: this walk runs on the every-frame overlay feed, and
        --per-frame DeepCopies would be pure garbage churn. The clone shares the
        --source instance's guid (so entered-tracking keys the same) and its
        --area userdata, and carries casterid/casterPartyId so the engine's
        --ApplyTo allegiance gating of the tile rules keeps working.
        local instances = {}
        pcall(function()
            local auraInstanceType = rawget(_G, "AuraInstance")
            if auraInstanceType ~= nil then
                for _,src in ipairs(ruleSources) do
                    pcall(function()
                        local def = dmhub.DeepCopy(src:try_get("aura"))
                        def.modifiers = {}
                        for _,child in ipairs(def:try_get("subauras", {})) do
                            child.modifiers = {}
                        end
                        instances[#instances+1] = auraInstanceType.new{
                            aura = def,
                            guid = src:try_get("guid"),
                            name = src:try_get("name"),
                            iconid = src:try_get("iconid", "ui-icons/skills/1.png"),
                            display = src:try_get("display"),
                            casterid = src:try_get("casterid"),
                            casterPartyId = src:try_get("casterPartyId"),
                            area = src:GetArea(),
                        }
                    end)
                end
            end
        end)
        m.keywordAuraOverlay.instances = instances

        --The engine only learns about these rules by re-polling the map-aura
        --feed; most changes (a cast, an expiry) already trigger an aura
        --rebuild, but ask for one explicitly so the rules can never lag the
        --stripes. Suppressed while the engine is polling us right now.
        if not suppressAuraRefresh then
            pcall(function()
                dmhub.RefreshMapAuras()
            end)
        end
    end

    --Dispel suppression rides the same walk. When the footprints change
    --(a dispelling aura appeared, moved, or expired -- or the zone cache was
    --rebuilt, which resets the signature to false), re-derive the suppressed
    --lists; and when that actually changes what is suppressed, re-mesh the
    --overlay and ask the engine to re-poll the map auras. suppressAuraRefresh
    --skips the re-poll request when the engine is polling us RIGHT NOW
    --(dmhub.GetMapAuras below) -- the fresh lists are what it receives.
    table.sort(dispelSignature)
    local newDispelSignature = table.concat(dispelSignature, "|")
    if newDispelSignature ~= m.dispelState.signature then
        local hadSuppression = m.dispelState.auraInstances ~= nil
        m.dispelState.signature = newDispelSignature
        m.dispelState.footprints = footprints
        m.dispelState.RebuildLists()

        if hadSuppression or m.dispelState.auraInstances ~= nil then
            m.zoneRevision = m.zoneRevision + 1
            if not suppressAuraRefresh then
                pcall(function()
                    dmhub.RefreshMapAuras()
                end)
            end
        end
    end

    return m.keywordAuraOverlay.zones
end

--The engine hooks. Assigned inside pcall: on a stale engine build these
--dmhub properties don't exist and assignment raises - zones then simply
--don't register or render, and the panel shows its needs-an-engine-build
--notice. We own these hooks outright (no chaining like GetSelectedWall):
--reassignment on reload just replaces our own stale closure.
--
--GetMapAuras runs the keyword-aura walk too, so a dispelling aura that just
--moved, appeared, or expired takes effect in the very aura rebuild that is
--re-polling this hook.
pcall(function()
    dmhub.GetMapAuras = function()
        EnsureZoneCache()
        EnsureKeywordAuraZones(true)
        local base = m.zoneAuraInstances
        if m.dispelState.auraInstances ~= nil then
            base = m.dispelState.auraInstances
        end

        --Objectless keyword ability auras ride along as rules-only clones
        --(see EnsureKeywordAuraZones). Appended into a fresh list: the base
        --lists must not be mutated -- m.dispelState keeps index-aligned
        --source tables for both of them.
        local extra = m.keywordAuraOverlay.instances
        if extra == nil or #extra == 0 then
            return base
        end
        local combined = {}
        for _,inst in ipairs(base) do
            combined[#combined+1] = inst
        end
        for _,inst in ipairs(extra) do
            combined[#combined+1] = inst
        end
        return combined
    end
end)

pcall(function()
    dmhub.GetMarkupZones = function()
        EnsureZoneCache()
        local panelOpen = MarkupPanelIsOpen()
        local mode = m.markupModeRef()

        --The Footsteps tab swaps the overlay wholesale: the normal zone
        --striping (rules zones here, built-in terrain-rule stripes engine
        --side, both regardless of the tileheight:overlay preference) hides,
        --and the footstep-surface regions render in that same stripe style
        --instead - marked apart by the footprints icon on their labels.
        --WATER stays visible on both layers (water rules zones ride along in
        --the footsteps list; the engine keeps the built-in water striping):
        --water plays water sounds over any painted footstep surface.
        local footstepsMode = panelOpen and mode == "surfaces"

        --a mode flip changes the zones list without any record changing, so
        --bump the revision to invalidate the overlay mesh - this is what
        --makes the swap take effect on engine builds old and new alike.
        if footstepsMode ~= m.dispelState.feedFootstepsMode then
            m.dispelState.feedFootstepsMode = footstepsMode
            m.zoneRevision = m.zoneRevision + 1
        end

        --same reasoning for panelOpen: with the tileheight:overlay preference
        --off, this flag alone decides whether the zone layer draws at all, and
        --no record has changed when it flips (opening/closing the panel, or a
        --Lua reload re-deriving it). Bump the revision so the overlay mesh is
        --rebuilt rather than serving a cached empty layer.
        if panelOpen ~= m.dispelState.feedPanelOpen then
            m.dispelState.feedPanelOpen = panelOpen
            m.zoneRevision = m.zoneRevision + 1
        end

        local zones = m.zoneOverlayZones
        if footstepsMode then
            zones = m.footstepsOverlayZones
        else
            --Keyword auras ride on the normal zone layer. The Footsteps tab
            --swaps that layer wholesale for surface regions, so they sit that
            --one out. Called unconditionally otherwise, because it owns the
            --revision bumps that tell the engine to re-mesh when an aura
            --appears or expires -- including the dispel suppression, which is
            --why it must run BEFORE the overlay list is chosen: zones being
            --dispelled render with the suppressed tiles removed, matching
            --the reduced aura registered for them.
            local auraZones = EnsureKeywordAuraZones(false)
            if m.dispelState.overlayZones ~= nil then
                zones = m.dispelState.overlayZones
            end
            if #auraZones > 0 then
                local combined = {}
                for _,zone in ipairs(zones) do
                    combined[#combined+1] = zone
                end
                for _,zone in ipairs(auraZones) do
                    combined[#combined+1] = zone
                end
                zones = combined
            end
        end

        --Per-zone-type visibility: painted zone types default HIDDEN; the map
        --overlay menu (title bar terrain chip) opts types IN via the
        --mapoverlay:shownzones preference (';'-joined keyword ids), same shape
        --as the built-in terrain stripes. The ZONES tab overrides the filter -
        --you are editing the zones, so you see all of them - and so does the
        --Footsteps tab, whose water-zone readout must not depend on a display
        --preference. Only painted zones (zonegroup set) are subject to the
        --opt-in: keyword-aura zones (a monster's Darkness) are not map markup
        --and the aura is on screen for everyone already. A filter change is
        --invisible to the engine's other cache signals, so bump the revision
        --when the effective filter flips (including the tab overrides kicking
        --in and out). "*" = show everything.
        local shownStr = "*"
        if not (panelOpen and (mode == "zones" or mode == "surfaces")) then
            shownStr = tostring(dmhub.GetSettingValue("mapoverlay:shownzones") or "")
        end
        if shownStr ~= m.dispelState.feedZoneFilter then
            m.dispelState.feedZoneFilter = shownStr
            m.zoneRevision = m.zoneRevision + 1
        end
        if shownStr ~= "*" then
            local shown = {}
            for id in string.gmatch(shownStr, "[^;]+") do
                shown[id] = true
            end
            local filtered = {}
            for _,zone in ipairs(zones) do
                if zone.zonegroup == nil or shown[zone.keywordid] ~= nil then
                    filtered[#filtered+1] = zone
                end
            end
            zones = filtered
        end

        --Per-zone-type fade: the opacity slider on each group in the Zones
        --list, applied to the colours here rather than to any record (see the
        --m.zoneStripes.opacity block). Gated on the panel being open, so a
        --slider left part-way down has no effect once the panel closes. A
        --fade change is invisible to the engine's other cache signals, so the
        --published seq drives a revision bump the same way the zone-type
        --filter above does - including the whole feature switching off when
        --the last slider returns to 100%.
        local fadeSeq = 0
        if panelOpen and m.zoneStripes.AnyFade() then
            fadeSeq = m.zoneStripes.opacitySeq
        end
        if fadeSeq ~= m.zoneStripes.opacityFeedSeq then
            m.zoneStripes.opacityFeedSeq = fadeSeq
            m.zoneRevision = m.zoneRevision + 1
        end
        if fadeSeq ~= 0 then
            local faded = {}
            for _,zone in ipairs(zones) do
                --keyword-aura zones (a monster's Darkness) carry no zonegroup
                --but do carry a keyword, and fade with their painted kin.
                local opacity = m.zoneStripes.Opacity(zone.zonegroup or zone.keywordid)
                if opacity >= 1 then
                    faded[#faded+1] = zone
                else
                    --the cached entry is shared with the aura/dispel lists and
                    --must not be recoloured in place; the copy is shallow, so
                    --the loc list is shared rather than rebuilt per poll.
                    local copy = {}
                    for k,v in pairs(zone) do
                        copy[k] = v
                    end
                    copy.color = m.zoneStripes.FadeColor(zone.color, opacity)
                    faded[#faded+1] = copy
                end
            end
            zones = faded
        end

        --Markup holes stripe like zones while the panel is open (the actual
        --cut renders too; the stripe overlay draws into the CURRENT floor's
        --composite, above the punched art layer, so the stripes hover over
        --the empty space), and outside the panel when opted in via the map
        --overlay menu's Hole row -- stored as the reserved id "hole" in
        --mapoverlay:shownbuiltins (opt-IN like the built-ins: the default
        --with the panel closed stays "the map just has a hole in it"). The
        --engine ignores unknown ids in that setting. Holes carry no
        --keywordid/zonegroup, so the shown-zones filter and the fade pass
        --above both leave them alone; appended after both passes, with their
        --own fade applied here under the reserved m.holes.groupKey (the
        --Holes group's slider in the zone list).
        local holesShown = panelOpen
        if not holesShown and #m.holes.overlayZones > 0 then
            local shownStr = tostring(dmhub.GetSettingValue("mapoverlay:shownbuiltins") or "")
            for id in string.gmatch(shownStr, "[^;]+") do
                if id == "hole" then
                    holesShown = true
                    break
                end
            end
        end
        --a pref flip changes the list with no record write; bump the revision
        --so the overlay mesh rebuilds (panelOpen flips already bump above,
        --the redundant second bump is harmless).
        if holesShown ~= m.dispelState.feedHolesShown then
            m.dispelState.feedHolesShown = holesShown
            m.zoneRevision = m.zoneRevision + 1
        end
        if holesShown and #m.holes.overlayZones > 0 then
            local holeOpacity = 1
            if fadeSeq ~= 0 then
                holeOpacity = m.zoneStripes.Opacity(m.holes.groupKey)
            end
            local combined = {}
            for _,zone in ipairs(zones) do
                combined[#combined+1] = zone
            end
            for _,zone in ipairs(m.holes.overlayZones) do
                if holeOpacity >= 1 then
                    combined[#combined+1] = zone
                else
                    --shallow copy, same rule as the zone fade above: the
                    --cached entry must not be recoloured in place.
                    local copy = {}
                    for k,v in pairs(zone) do
                        copy[k] = v
                    end
                    copy.color = m.zoneStripes.FadeColor(zone.color, holeOpacity)
                    combined[#combined+1] = copy
                end
            end
            zones = combined
        end

        --"Entire Map" types draw nothing (that is the point - a blanket is
        --implied), but their auras still contribute terrain rules to every
        --tile, and the engine's BUILT-IN rule stripes/labels are driven off
        --GetTileRulesAtLoc. Without telling the overlay which flags the whole
        --floor now carries, turning a blanket on floods the map with built-in
        --stripes -- which looks exactly like the blanket drawing itself.
        --Flags only, no tiles: a per-tile suppression set would marshal the
        --whole map across the bridge on every poll of this feed.
        local blankets = {}
        for _,entry in ipairs(m.entireMap.entries) do
            blankets[#blankets+1] = {
                floorIndex = entry.floorIndex,
                difficultTerrain = entry.flags.difficultTerrain,
                water = entry.flags.water,
                concealment = entry.flags.concealment,
                climbable = entry.flags.climbable,
            }
        end

        return {
            panelOpen = panelOpen,
            blankets = blankets,
            --The Zones tab also lights up the overlay's built-in terrain-rule
            --striping (water/difficult/concealment/climbable), so the user
            --sees existing terrain conditions alongside the zones they are
            --painting - without needing the Show Terrain Features preference.
            terrainZones = panelOpen and mode == "zones",
            footstepsMode = footstepsMode,
            --The Walls tab force-renders solid-block interiors; any open tab
            --forces the wall cover lines. The Elevation tab force-renders the
            --height contours + number labels. Each rides on its mapoverlay:*
            --preference otherwise (see TileHeightOverlay.Update).
            wallsMode = panelOpen and mode == "walls",
            elevationMode = panelOpen and mode == "elevation",
            revision = m.zoneRevision,
            zones = zones,
        }
    end
end)

--Public API for the title bar's map overlay menu (CodexTitleBar): the zone
--types present on the current map, one entry per environmental keyword, as
--{ keywordid, name, color ("#rrggbb"), angleRadians, playerVisible }.
--playerVisible is true when at least one zone of the type is player-visible
--(keyword-aura zones - a monster's Darkness - are always on screen for
--everyone and count as player-visible). Non-DM clients only receive the
--player-visible types, so the menu cannot leak hidden zone types.
--Lives on a global table so the title bar can reach it with rawget: the
--module may be absent (lobby game) or not yet loaded.
if rawget(_G, "MapMarkup") == nil then
    MapMarkup = {}
end

function MapMarkup.GetZoneTypesOnMap()
    if not ZonesSupported() then
        return {}
    end
    EnsureZoneCache()
    pcall(function()
        EnsureKeywordAuraZones(false)
    end)

    local seen = {}
    local result = {}
    local function Add(keywordid, name, color, playerVisible)
        if keywordid == nil then
            return
        end
        --normalize colors to "#rrggbb": overlay feed colors carry the "bf"
        --stripe alpha, keyword colors can be 9-char too.
        if type(color) == "string" and string.len(color) == 9 then
            color = string.sub(color, 1, 7)
        end
        local entry = seen[keywordid]
        if entry == nil then
            entry = {
                keywordid = keywordid,
                name = name or "Zone",
                color = color,
                angleRadians = m.zoneStripes.AngleForKeyword(keywordid),
                playerVisible = playerVisible == true,
            }
            seen[keywordid] = entry
            result[#result+1] = entry
        elseif playerVisible == true then
            entry.playerVisible = true
        end
    end

    for _,entry in ipairs(m.zoneCache) do
        if entry.floorIndex ~= nil and entry.floorIndex >= 0 then
            Add(entry.keywordid, entry.keywordName or entry.name, entry.patternColor, entry.playerVisible)
        end
    end
    --"Entire Map" blankets: the type is in force even though nothing is drawn
    --for it. Never player-visible.
    for _,entry in ipairs(m.entireMap.entries) do
        Add(entry.keywordid, entry.keywordName or entry.name, entry.patternColor, false)
    end
    --keyword-carrying auras (abilities, monster traits): on screen for
    --everyone already.
    for _,zone in ipairs(m.keywordAuraOverlay.zones or {}) do
        Add(zone.keywordid, zone.label, zone.color, true)
    end

    if not dmhub.isDM then
        local filtered = {}
        for _,entry in ipairs(result) do
            if entry.playerVisible then
                filtered[#filtered+1] = entry
            end
        end
        result = filtered
    end

    table.sort(result, function(a, b)
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    return result
end

--Markup holes present on the current map, for the title bar's map overlay
--menu: {color, angleRadians}, or nil when the map has none. The menu shows an
--opt-IN row for it (reserved id "hole" in mapoverlay:shownbuiltins) -- with
--the Map Markup panel closed the default is just the actual cut, no stripes.
--DM-only: hole stripes are never player-visible, so players get no row.
function MapMarkup.GetHoleTypeOnMap()
    if not dmhub.isDM then
        return nil
    end
    if not ZonesSupported() then
        return nil
    end
    EnsureZoneCache()
    for _,entry in ipairs(m.holes.cache) do
        if entry.floorIndex ~= nil and entry.floorIndex >= 0 then
            return {
                color = m.holes.color,
                angleRadians = K.ZONE_ANGLE_A,
            }
        end
    end
    return nil
end

--Keyword edits (refreshTables) change what zone auras contribute: invalidate
--the cache, and if this map actually has zones, rebuild the aura index so
--the changes reach creatures without waiting for an unrelated rebuild.
dmhub.RegisterEventHandler("refreshTables", function()
    m.zoneTablesGen = m.zoneTablesGen + 1
    if not ZonesSupported() then
        return
    end
    EnsureZoneCache()
    if (m.zoneCache ~= nil and #m.zoneCache > 0) or #m.entireMap.entries > 0 then
        pcall(function()
            dmhub.RefreshMapAuras()
        end)
    end
end)

--============================================================================
--Dynamic-light sampling. A slow poll (below) asks the engine which candidate
--tiles are currently dark; when the answer changes (a torch moved, a door
--closed, night fell), the sampling serial bumps -- which invalidates the zone
--cache -- and the aura index is asked to re-poll dmhub.GetMapAuras. The
--engine hashes the dark set and returns nil while it matches knownState, so
--an unchanged poll marshals nothing and rebuilds nothing.
--============================================================================

--One engine call per (floor, distinct threshold): candidates are the whole
--map extent when any keyword at that threshold blankets the map, else the
--union of that threshold's painted zone tiles on the floor (built in stable
--cache order -- the candidate order is part of the engine's state hash).
function m.dynamicLight.Sample()
    if not m.dynamicLight.Supported() or not ZonesSupported() then
        return
    end

    local thresholds = m.dynamicLight.Thresholds()
    if next(thresholds) == nil then
        if next(m.dynamicLight.states) ~= nil then
            m.dynamicLight.states = {}
            m.dynamicLight.serial = m.dynamicLight.serial + 1
            --without this the carve lingers until some unrelated aura
            --rebuild happens to re-poll the zone cache.
            pcall(function()
                dmhub.RefreshMapAuras()
            end)
        end
        return
    end

    local map = game.currentMap
    if map == nil then
        return
    end

    EnsureZoneCache()

    local floors = {}
    for _,floor in ipairs(map.floors or {}) do
        pcall(function()
            local floorIndex = floor.floorIndex
            if floorIndex ~= nil and floorIndex >= 0 then
                floors[#floors+1] = { floorid = floor.floorid, floorIndex = floorIndex }
            end
        end)
    end

    local dims = nil
    pcall(function()
        dims = map.dimensions
    end)

    local blankets = m.entireMap.Keywords()

    --pct -> { kwids = set, blanket = bool }
    local groups = {}
    for kwid,pct in pairs(thresholds) do
        local group = groups[pct]
        if group == nil then
            group = { kwids = {}, blanket = false }
            groups[pct] = group
        end
        group.kwids[kwid] = true
        if blankets[kwid] == true then
            group.blanket = true
        end
    end

    local live = {}
    local changed = false

    for pct,group in pairs(groups) do
        for _,floorInfo in ipairs(floors) do
            local args = {
                floorIndex = floorInfo.floorIndex,
                threshold = pct / 100,
            }

            local haveCandidates = false
            if group.blanket and dims ~= nil then
                args.x1 = math.floor(dims.x)
                args.y1 = math.floor(dims.y)
                args.x2 = math.floor(dims.z) - 1
                args.y2 = math.floor(dims.w) - 1
                haveCandidates = args.x2 >= args.x1 and args.y2 >= args.y1
            else
                local locs = {}
                for _,entry in ipairs(m.zoneCache) do
                    if entry.floorid == floorInfo.floorid and entry.keywordid ~= nil
                        and group.kwids[entry.keywordid] == true then
                        for _,l in ipairs(entry.locs) do
                            locs[#locs+1] = l.x
                            locs[#locs+1] = l.y
                        end
                    end
                end
                if #locs > 0 then
                    args.locs = locs
                    haveCandidates = true
                end
            end

            if haveCandidates then
                local key = m.dynamicLight.StateKey(floorInfo.floorid, pct)
                live[key] = true

                local prev = m.dynamicLight.states[key]
                if prev ~= nil then
                    args.knownState = prev.state
                end

                local ok, result = pcall(function()
                    return dmhub.GetDarkTiles(args)
                end)
                if ok and result ~= nil then
                    local dark = {}
                    local resultLocs = result.locs or {}
                    for i = 1, #resultLocs - 1, 2 do
                        dark[MM.ZoneLocKey(resultLocs[i], resultLocs[i+1])] = true
                    end

                    --locs mode also records WHICH tiles were sampled, so
                    --ApplyFilter can tell "sampled and lit" (drop) from
                    --"never sampled" (keep until the next sample). Rect mode
                    --covers the whole map, so nothing is ever unknown there.
                    local sampled = nil
                    if args.locs ~= nil then
                        sampled = {}
                        for i = 1, #args.locs - 1, 2 do
                            sampled[MM.ZoneLocKey(args.locs[i], args.locs[i+1])] = true
                        end
                    end

                    m.dynamicLight.states[key] = { state = result.state, dark = dark, sampled = sampled }
                    changed = true
                end
            end
        end
    end

    --configuration/zones that stopped being sampled must not keep carving.
    for key,_ in pairs(m.dynamicLight.states) do
        if live[key] ~= true then
            m.dynamicLight.states[key] = nil
            changed = true
        end
    end

    if changed then
        m.dynamicLight.serial = m.dynamicLight.serial + 1
        pcall(function()
            dmhub.RefreshMapAuras()
        end)
    end
end

--reschedule-first so a Sample error can't kill the loop; cheap when the
--feature is unconfigured (one setting read).
function m.dynamicLight.Tick()
    if mod.unloaded then
        return
    end
    dmhub.Schedule(0.7, m.dynamicLight.Tick)
    pcall(m.dynamicLight.Sample)
end

dmhub.Schedule(0.7, m.dynamicLight.Tick)


--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.BuildSurfaceAuraInstance = BuildSurfaceAuraInstance
MM.BuildZoneAuraInstance = BuildZoneAuraInstance
MM.CollectKeywordAuraZones = CollectKeywordAuraZones
MM.EnsureKeywordAuraZones = EnsureKeywordAuraZones
MM.EnsureZoneCache = EnsureZoneCache
MM.MarkupPanelIsOpen = MarkupPanelIsOpen
MM.RebuildZoneCache = RebuildZoneCache
MM.ZoneAreaDescription = ZoneAreaDescription
MM.ZoneOverlayColor = ZoneOverlayColor
MM.ZoneOverlayLabel = ZoneOverlayLabel
MM.ZonesSupported = ZonesSupported
