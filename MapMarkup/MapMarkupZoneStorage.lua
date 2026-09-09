local mod = dmhub.GetModLoading()

--Map Markup: zone storage - zone records, CreateZone, contiguous splitting,
--calculated zones, normalization, and the flash/jump-to-zone helpers.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--============================================================================
--Zone editing operations (paint / erase / create / update / delete).
--ZoneLocKey lives up with the keyword helpers: the ZoneManager uses it too.
--============================================================================

--Rasterizes a closed stroke polygon (interleaved x,y world coords) to the
--tiles whose CENTERS it contains. Tile (x,y)'s center is world (x,y) on
--square grids (Loc-centered convention; snap = Round). If the polygon is so
--small it contains no center, falls back to the tile under its centroid so
--a click-sized stroke still paints one tile.
local function PolygonToLocs(points)
    local n = #points
    if n < 6 then
        return {}
    end

    local minX, minY = points[1], points[2]
    local maxX, maxY = points[1], points[2]
    local cxSum, cySum, npts = 0, 0, 0
    for i = 1, n - 1, 2 do
        local px, py = points[i], points[i+1]
        if px < minX then minX = px end
        if px > maxX then maxX = px end
        if py < minY then minY = py end
        if py > maxY then maxY = py end
        cxSum = cxSum + px
        cySum = cySum + py
        npts = npts + 1
    end

    local function PointInPolygon(px, py)
        local inside = false
        local j = n - 1
        for i = 1, n - 1, 2 do
            local ax, ay = points[i], points[i+1]
            local bx, by = points[j], points[j+1]
            if (ay > py) ~= (by > py) then
                local t = (py - ay) / (by - ay)
                if px < ax + t * (bx - ax) then
                    inside = not inside
                end
            end
            j = i
        end
        return inside
    end

    local result = {}
    for ty = math.floor(minY + 0.5), math.floor(maxY + 0.5) do
        for tx = math.floor(minX + 0.5), math.floor(maxX + 0.5) do
            if PointInPolygon(tx, ty) then
                result[#result+1] = { x = tx, y = ty }
            end
        end
    end

    if #result == 0 and npts > 0 then
        result[#result+1] = {
            x = math.floor(cxSum / npts + 0.5),
            y = math.floor(cySum / npts + 0.5),
        }
    end

    return result
end

--Even-odd point-in-ring test against a flat {x1,y1,x2,y2,...} ring, matching
--PolygonToLocs' fill rule.
function m.holes.PointInRing(ring, px, py)
    local n = #ring
    local inside = false
    local j = n - 1
    for i = 1, n - 1, 2 do
        local ax, ay = ring[i], ring[i+1]
        local bx, by = ring[j], ring[j+1]
        if (ay > py) ~= (by > py) then
            local t = (py - ay) / (by - ay)
            if px < ax + t * (bx - ax) then
                inside = not inside
            end
        end
        j = i
    end
    return inside
end

--Tiles covered by a hole's structured polygon list: each outer ring
--rasterizes like a paint stroke, minus tiles whose center falls in one of
--its clipped-out hole rings. Merged and deduplicated across entries.
function m.holes.EntryLocs(polygons)
    local seen = {}
    local result = {}
    for _,entry in ipairs(polygons or {}) do
        for _,l in ipairs(PolygonToLocs(entry.points or {})) do
            local inHole = false
            for _,holeRing in ipairs(entry.holes or {}) do
                if m.holes.PointInRing(holeRing, l.x, l.y) then
                    inHole = true
                    break
                end
            end
            if not inHole then
                local key = MM.ZoneLocKey(l.x, l.y)
                if not seen[key] then
                    seen[key] = true
                    result[#result+1] = { x = l.x, y = l.y }
                end
            end
        end
    end
    return result
end

--A fresh storable record built from a cache entry with replacement fields.
--Always build fresh tables for writes: the engine's markupZones getter hands
--back the stored table itself, and mutating it in place corrupts undo.
local function BuildZoneRecord(entry, overrides)
    overrides = overrides or {}
    local locs = {}
    for _,l in ipairs(overrides.locs or entry.locs) do
        locs[#locs+1] = { x = l.x, y = l.y }
    end

    local record = {
        name = overrides.name or entry.name,
        --entry.keywordid is the RESOLVED id (possibly healed by name), so
        --rewriting the record here also repairs a dead stored id.
        keyword = entry.keywordid,
        keywordName = entry.keywordName,
        locs = locs,
        altitude = entry.altitude or 0,
        playerVisible = entry.playerVisible == true,
        pattern = {
            color = entry.patternColor,
            angle = entry.patternAngle,
        },
        ord = entry.ord or 0,
    }

    --height: nil means unlimited and stays absent from the record.
    if overrides.clearHeight then
        record.height = nil
    elseif overrides.height ~= nil then
        record.height = overrides.height
    else
        record.height = entry.height
    end

    --visuals: the shown state is the default and stays absent from the record.
    if entry.hideAppearance == true then
        record.hideAppearance = true
    end
    if overrides.hideAppearance ~= nil then
        record.hideAppearance = (overrides.hideAppearance == true) or nil
    end

    if overrides.name ~= nil then record.name = overrides.name end
    if overrides.playerVisible ~= nil then record.playerVisible = overrides.playerVisible end

    return record
end

--Zone entries on the given floor, in list order.
local function ZonesOnFloor(floorid)
    MM.EnsureZoneCache()
    local result = {}
    for _,entry in ipairs(m.zoneCache or {}) do
        if entry.floorid == floorid then
            result[#result+1] = entry
        end
    end
    return result
end

local function FindZoneEntry(zoneid)
    MM.EnsureZoneCache()
    for _,entry in ipairs(m.zoneCache or {}) do
        if entry.zoneid == zoneid then
            return entry
        end
    end
    return nil
end

--A unique display name for a new zone of the given keyword on a floor:
--"Lava", then "Lava 2", "Lava 3", ...
local function UniqueZoneName(floorid, baseName)
    local taken = {}
    for _,entry in ipairs(ZonesOnFloor(floorid)) do
        taken[entry.name] = true
    end

    if not taken[baseName] then
        return baseName
    end

    local i = 2
    while taken[string.format("%s %d", baseName, i)] do
        i = i + 1
    end
    return string.format("%s %d", baseName, i)
end

--Creates a new zone record of the given keyword on the current floor and
--returns its id. locs may be empty (a fresh separate zone to paint into).
--fallbackInfo ({name, color}, optional) covers the keyword-upload race: the
--keyword may not be locally visible yet, but the caller knows what it is.
local function CreateZone(keywordid, locs, fallbackInfo)
    local floor = game.currentFloor
    if floor == nil then
        return nil
    end

    local kw = MM.GetKeyword(keywordid)
    local kwName = nil
    if kw ~= nil and kw.name ~= nil then
        kwName = kw.name
    elseif fallbackInfo ~= nil then
        kwName = fallbackInfo.name
    end
    kwName = kwName or "Zone"

    local floorZones = ZonesOnFloor(floor.floorid)
    local maxOrd = 0
    for _,entry in ipairs(floorZones) do
        if (entry.ord or 0) > maxOrd then
            maxOrd = entry.ord
        end
    end

    --stripe angle is a function of the keyword, so every zone of a keyword on
    --this map stripes the same way. (The overlay feed re-derives it anyway;
    --this is only what gets stored on the record.)
    local angle = m.zoneStripes.AngleForKeyword(keywordid)

    local color = MM.KeywordColor(keywordid, kw)
    if kw == nil and fallbackInfo ~= nil and fallbackInfo.color ~= nil then
        color = fallbackInfo.color
    end

    local zoneid = dmhub.GenerateGuid()
    local record = {
        name = UniqueZoneName(floor.floorid, kwName),
        keyword = keywordid,
        keywordName = kwName,
        locs = locs or {},
        altitude = 0,
        --new zones are player-visible: a painted zone is nearly always terrain
        --the table is meant to see (and players still have to turn the tile
        --overlay on). Secret zones are turned off in the Edit Zone dialog, and
        --a whole type that is nearly always secret is turned off once on the
        --keyword - stamped on below, beside the height and visuals defaults.
        playerVisible = true,
        pattern = {
            color = color,
            angle = angle,
        },
        ord = maxOrd + 1,
    }

    --The zone TYPE's default height is stamped on at paint time; the zone owns
    --it from here on (Edit Zone dialog), so re-defaulting the type later leaves
    --zones already painted alone. nil = unlimited and stays off the record.
    record.height = m.zoneHeight.Get(kw)

    --Same deal for the type's "draw with visuals" toggle (the Visuals pill on
    --the palette chip): pill off = the new zone starts with its visual
    --representation hidden. The zone owns the flag from here on (the Visuals
    --badge on its list row), so flipping the pill later leaves painted zones
    --alone. Shown is the default and stays off the record.
    pcall(function()
        if kw ~= nil and kw:try_get("appearanceDefaultOff", false) == true then
            record.hideAppearance = true
        end
    end)

    --Same deal for the type's player-visibility default ("New Zones Visible to
    --Players" in the keyword editor): a type whose zones are scenery stays
    --visible, a type that is a secret hazard starts hidden. The zone owns the
    --flag from here on (Edit Zone dialog), so flipping the type default later
    --leaves painted zones alone. Visible is the default and needs no write.
    pcall(function()
        if kw ~= nil and kw:try_get("defaultPlayerVisible", true) ~= true then
            record.playerVisible = false
        end
    end)

    floor:SetMarkupZone(zoneid, record)
    return zoneid
end

--Splits a loc set into 4-connected contiguous components, largest first.
--Contiguity matches the overlay's per-block labelling, so one component =
--one labelled region on the map.
local function SplitContiguousComponents(locs)
    local remaining = {}
    local orderedKeys = {}
    for _,l in ipairs(locs) do
        local key = MM.ZoneLocKey(l.x, l.y)
        if remaining[key] == nil then
            remaining[key] = { x = l.x, y = l.y }
            orderedKeys[#orderedKeys+1] = key
        end
    end

    local components = {}
    for _,startKey in ipairs(orderedKeys) do
        if remaining[startKey] ~= nil then
            local component = {}
            local queue = { remaining[startKey] }
            remaining[startKey] = nil

            while #queue > 0 do
                local cell = table.remove(queue)
                component[#component+1] = cell

                local neighborKeys = {
                    MM.ZoneLocKey(cell.x + 1, cell.y),
                    MM.ZoneLocKey(cell.x - 1, cell.y),
                    MM.ZoneLocKey(cell.x, cell.y + 1),
                    MM.ZoneLocKey(cell.x, cell.y - 1),
                }
                for _,nkey in ipairs(neighborKeys) do
                    local ncell = remaining[nkey]
                    if ncell ~= nil then
                        remaining[nkey] = nil
                        queue[#queue+1] = ncell
                    end
                end
            end

            components[#components+1] = component
        end
    end

    table.sort(components, function(a, b) return #a > #b end)
    return components
end

--Calculated zones: regions the rules see that nobody painted as a zone,
--listed alongside the painted zones so "Zones on This Floor" is a complete
--account of the floor. Two feeds:
--  * tiles beside climbable walls (and climbable Solid objects):
--    CalculateMapLogicJob.CalculateClimbableFromWalls stamps both tiles
--    adjacent to every climbable wall segment into wallClimbableTiles, which
--    CharacterToken reads directly -- they never reach GetTileRulesAtLoc, so
--    nothing else in the panel knows about them;
--  * the built-in tile rules (water / difficult terrain / concealment /
--    climbable) the terrain tiles and object Floor components grant, minus
--    additive aura contributions (markup zones) -- exactly the set the Zones
--    tab's built-in stripes draw. Attributed to the object that forces them
--    when there is one, else to the terrain.
--Each feed is bucketed by rule and source and cut into 4-connected regions
--(SplitContiguousComponents, the same contiguity as the overlay's labels), one
--row per region. They are read-only: no record, no paint target, no menu --
--the row jumps the camera and pulses the tiles, nothing more. Kept OUT of
--m.zoneCache so ZonesOnFloor (and every paint/erase path built on it) never
--sees them. All on one table, grouping the related state.
m.calculatedZones = {
    cache = nil,
    cacheKey = nil,
    groupKey = "calculated:zones",
    --the engine's built-in stripe colours (TileHeightOverlay ZoneWater /
    --ZoneDifficult / ZoneConcealment / ZoneClimbable), so each swatch matches
    --the stripes the Zones tab already draws for that rule.
    rules = {
        { flag = "climbable", name = "Climbable", color = "#66cc66", angle = K.ZONE_ANGLE_B },
        { flag = "water", name = "Water", color = "#3373d9", angle = K.ZONE_ANGLE_A },
        { flag = "difficultTerrain", name = "Difficult Terrain", color = "#8c5926", angle = K.ZONE_ANGLE_B },
        { flag = "concealment", name = "Concealment", color = "#333333", angle = K.ZONE_ANGLE_A },
    },
    wallVariants = {
        { field = "AllCreatures", name = "Climbable Walls", angle = K.ZONE_ANGLE_B },
        { field = "ClimbersOnly", name = "Climbable Walls (Climbers Only)", angle = K.ZONE_ANGLE_A },
    },
}

--The calculated zone entries for the given floor, shaped like m.zoneCache
--entries (the list row builder, ZoneAreaDescription and JumpToZone all read
--them) plus calculated=true, calculatedSource (the tooltip's "Calculated from
--X") and calculatedMeta (the row's "calculated from x"). Only the CURRENT
--floor can be answered: the engine keys tiles by floorIndex, which other
--floors may not even have. Cached against dmhub.tileRulesSeq, which folds in
--every signal that can move either feed (walls, solids, floor patches, object
--aura rebuilds, tilesheet edits).
function m.calculatedZones.Entries(floorid)
    local floor = game.currentFloor
    if floorid == nil or floor == nil or floor.floorid ~= floorid then
        return {}
    end
    local floorIndex = floor.floorIndex
    if floorIndex == nil or floorIndex < 0 then
        return {}
    end

    local key = string.format("%s:%d:%d", floorid, floorIndex, dmhub.tileRulesSeq)
    if m.calculatedZones.cache ~= nil and m.calculatedZones.cacheKey == key then
        return m.calculatedZones.cache
    end

    local result = {}
    local AddZone = function(args)
        local locsUserdata = {}
        for _,l in ipairs(args.locs) do
            locsUserdata[#locsUserdata+1] = core.Loc{ x = l.x, y = l.y, floorIndex = floorIndex }
        end
        result[#result+1] = {
            zoneid = string.format("calculated-%s-%s", args.key, floorid),
            calculated = true,
            calculatedSource = args.source,
            calculatedMeta = args.meta,
            floorid = floorid,
            floorIndex = floorIndex,
            name = args.name,
            keywordName = args.name,
            locs = args.locs,
            locsUserdata = locsUserdata,
            patternColor = args.color,
            patternAngle = args.angle,
        }
    end

    --feed 1: wall-adjacent climbable tiles, one row per contiguous strip.
    local walls = dmhub.GetWallClimbableTilesOnFloor(floorid) or {}
    for _,variant in ipairs(m.calculatedZones.wallVariants) do
        local locs = {}
        for _,l in ipairs(walls[variant.field] or {}) do
            locs[#locs+1] = { x = l.x, y = l.y }
        end
        for i,component in ipairs(SplitContiguousComponents(locs)) do
            AddZone{
                key = string.format("walls-%s-%d", variant.field, i),
                name = variant.name,
                source = "Climbable Walls",
                meta = "calculated from climbable walls",
                locs = component,
                color = "#66cc66",
                angle = variant.angle,
            }
        end
    end

    --feed 2: built-in tile rules, bucketed by rule then by source. Climbable
    --buckets also split on climbers-only, since that changes the row's name.
    local tiles = dmhub.GetBuiltinTerrainZonesOnFloor(floorid) or {}
    for _,rule in ipairs(m.calculatedZones.rules) do
        local buckets = {}
        local bucketOrder = {}
        for _,t in ipairs(tiles) do
            if t[rule.flag] == true then
                local climbersOnly = rule.flag == "climbable" and t.climbersOnly == true
                local bucketKey = (t.sourceid or "terrain") .. cond(climbersOnly, ":climbers", "")
                local bucket = buckets[bucketKey]
                if bucket == nil then
                    local name = rule.name
                    if climbersOnly then
                        name = "Climbable (Climbers Only)"
                    end
                    local source, meta
                    if t.sourceid ~= nil then
                        source = string.format("the object \"%s\"", t.source or "Object")
                        meta = string.format("calculated from object \"%s\"", t.source or "Object")
                    else
                        source = "the terrain"
                        meta = "calculated from the terrain"
                    end
                    bucket = { key = bucketKey, name = name, source = source, meta = meta, locs = {} }
                    buckets[bucketKey] = bucket
                    bucketOrder[#bucketOrder+1] = bucket
                end
                bucket.locs[#bucket.locs+1] = { x = t.loc.x, y = t.loc.y }
            end
        end

        for _,bucket in ipairs(bucketOrder) do
            for i,component in ipairs(SplitContiguousComponents(bucket.locs)) do
                AddZone{
                    key = string.format("%s-%s-%d", rule.flag, bucket.key, i),
                    name = bucket.name,
                    source = bucket.source,
                    meta = bucket.meta,
                    locs = component,
                    color = rule.color,
                    angle = rule.angle,
                }
            end
        end
    end

    m.calculatedZones.cache = result
    m.calculatedZones.cacheKey = key
    return result
end

--Writes a zone's new loc set, automatically separating non-contiguous
--regions into their own zone records: the largest region keeps the zone's
--identity (id, name, settings), each additional region becomes a new zone
--of the same type and settings named "<Base> 2", "<Base> 3", ... An empty
--set deletes the zone. Callers wrap multi-zone operations in a transaction.
local function WriteZoneLocsSplitting(floor, entry, newLocs)
    local components = SplitContiguousComponents(newLocs)
    if #components == 0 then
        --NOTE: a stale m.zoneTargetId pointing at the removed zone is
        --harmless - target lookups search the cache by id and just miss.
        floor:RemoveMarkupZone(entry.zoneid)
        return
    end

    floor:SetMarkupZone(entry.zoneid, BuildZoneRecord(entry, { locs = components[1] }))

    if #components > 1 then
        --split-off names derive from the zone's own name with any trailing
        --number stripped, so "Lava 2" splits into "Lava 3", not "Lava 2 2".
        local baseName = string.gsub(entry.name, "%s+%d+$", "")
        if baseName == "" then
            baseName = entry.name
        end

        for i = 2, #components do
            local record = BuildZoneRecord(entry, { locs = components[i] })
            --UniqueZoneName consults the freshly-written records (local
            --writes apply synchronously), so each split gets a fresh name.
            record.name = UniqueZoneName(floor.floorid, baseName)
            floor:SetMarkupZone(dmhub.GenerateGuid(), record)
        end
    end
end

--Splits any multi-region zone records on the current floor into one record
--per contiguous region. Auto-splitting normally happens as strokes are
--written, but records created before that existed (or written by an older
--client) can still hold disjoint regions - the zones list runs this before
--refreshing so such zones separate as soon as the DM looks at them. One
--undo step for the whole pass; a no-op when everything is already split.
local function NormalizeZonesOnFloor(floorid)
    if not MM.ZonesSupported() then
        return
    end

    local floor = game.currentFloor
    if floor == nil or floor.floorid ~= floorid then
        return
    end

    local needSplit = {}
    for _,entry in ipairs(ZonesOnFloor(floorid)) do
        if #entry.locs > 0 and #SplitContiguousComponents(entry.locs) > 1 then
            needSplit[#needSplit+1] = entry
        end
    end

    if #needSplit == 0 then
        return
    end

    dmhub.BeginTransaction()
    for _,entry in ipairs(needSplit) do
        WriteZoneLocsSplitting(floor, entry, entry.locs)
    end
    dmhub.EndTransaction()
end

--============================================================================
--Zone flash: clicking a row in the zones list pans the camera to the zone
--and briefly pulses a highlight over its tiles so the user can spot it.
--============================================================================

m.zoneFlashMarks = nil
m.zoneFlashGen = 0

local function ClearZoneFlash()
    if m.zoneFlashMarks ~= nil then
        pcall(function()
            m.zoneFlashMarks:Destroy()
        end)
        m.zoneFlashMarks = nil
    end
end

local function JumpToZone(entry)
    if entry == nil or entry.locs == nil or #entry.locs == 0 then
        return
    end

    --camera target: the zone tile nearest the centroid, so an L-shaped or
    --sprawling region centers on actual zone tiles rather than a gap.
    local cx, cy = 0, 0
    for _,l in ipairs(entry.locs) do
        cx = cx + l.x
        cy = cy + l.y
    end
    cx = cx / #entry.locs
    cy = cy / #entry.locs

    local best = entry.locs[1]
    local bestD = nil
    for _,l in ipairs(entry.locs) do
        local d = (l.x - cx) * (l.x - cx) + (l.y - cy) * (l.y - cy)
        if bestD == nil or d < bestD then
            bestD = d
            best = l
        end
    end

    dmhub.CenterOnLoc{
        x = best.x,
        y = best.y,
        floorid = entry.floorid,
        smooth = true,
    }

    --pulse the zone's area: on / off / on, then clear. A newer flash (or a
    --reload) cancels the remainder of an older one via the generation guard.
    ClearZoneFlash()
    m.zoneFlashGen = m.zoneFlashGen + 1
    local gen = m.zoneFlashGen

    local locsUserdata = entry.locsUserdata
    if locsUserdata == nil then
        return
    end

    local okShape, shape = pcall(function()
        return dmhub.CalculateShape{
            shape = "locations",
            locations = locsUserdata,
            locOverride = locsUserdata[1],
            range = 0,
            radius = 0,
            checklos = false,
        }
    end)
    if not okShape or shape == nil then
        return
    end

    local PULSE_STEPS = { 0.4, 0.15, 0.4 } --on, off, on (seconds)

    local ShowPulse
    ShowPulse = function(step)
        if (mod ~= nil and mod.unloaded) or gen ~= m.zoneFlashGen then
            return
        end
        if step > #PULSE_STEPS then
            ClearZoneFlash()
            return
        end

        if step % 2 == 1 then
            local ok, marks = pcall(function()
                return shape:Mark{
                    color = entry.patternColor,
                    video = "divinationline.webm",
                }
            end)
            if ok then
                m.zoneFlashMarks = marks
            end
        else
            ClearZoneFlash()
        end

        dmhub.Schedule(PULSE_STEPS[step], function()
            ShowPulse(step + 1)
        end)
    end
    ShowPulse(1)
end


--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.BuildZoneRecord = BuildZoneRecord
MM.ClearZoneFlash = ClearZoneFlash
MM.CreateZone = CreateZone
MM.FindZoneEntry = FindZoneEntry
MM.JumpToZone = JumpToZone
MM.NormalizeZonesOnFloor = NormalizeZonesOnFloor
MM.PolygonToLocs = PolygonToLocs
MM.SplitContiguousComponents = SplitContiguousComponents
MM.UniqueZoneName = UniqueZoneName
MM.WriteZoneLocsSplitting = WriteZoneLocsSplitting
MM.ZonesOnFloor = ZonesOnFloor
