local mod = dmhub.GetModLoading()

--Map Markup: zone types - presets, stripe colors, the zone palette, entire-map
--keywords, dynamic light thresholds, zone height and keyword summaries.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

--============================================================================
--Zones: named tile regions carrying an Environmental Keyword, applied to the
--game through the aura system (design brief section 5, storage model Z1).
--
--Storage: per-floor markup zone records via the engine's
--floor:SetMarkupZone / floor:RemoveMarkupZone / floor.markupZones API
--(undo + multiplayer sync are the engine's ExecuteCommand). Record schema
--(owned here, opaque to the engine):
--  {
--    name = "Lava",                  -- display name (also the overlay label)
--    keyword = "<keyword id>",       -- environmentalKeywords table key
--    locs = { {x=0,y=0}, ... },      -- tiles, plain x/y pairs (floor implied)
--    altitude = 0,                   -- base altitude of the vertical range
--    height = 2,                     -- affects up to this many tiles above
--                                    -- altitude; ABSENT = unlimited height
--    playerVisible = true,           -- players see the overlay stripes
--                                    -- (stamped from the keyword's
--                                    -- defaultPlayerVisible, which is true
--                                    -- unless set; the Edit Zone dialog turns
--                                    -- it off per zone)
--    pattern = { color = "#rrggbb", angle = <radians> },
--    ord = 1,                        -- creation order (stable list sorting)
--  }
--
--The same store also holds the Footsteps mode's surface records, marked by
--category (records without a category are zone records). One record per
--surface family per floor, id "surface-<id>" - surfaces are exclusive per
--tile, so there is no naming/splitting machinery like zones have:
--  {
--    category = "surface",
--    surface = 6,                    -- AudioSurfaceTypes.surfaces index
--    surfaceName = "Stone",          -- informational (debugging/healing)
--    locs = { {x=0,y=0}, ... },
--  }
--
--Runtime: ZoneManager (MapMarkupZoneRuntime.lua) builds one AuraInstance per zone from the
--records and hands them to the engine via dmhub.GetMapAuras (re-polled on
--every aura rebuild). The keyword's difficultTerrain/water/concealment/
--climbable flags ride the aura into tile rules, its CharacterModifiers reach
--creatures via
--the normal FillModifiersFromAuras path, and the height field drives the
--engine's vertical-overlap test (a height-2 Lava zone burns a ground token
--and ignores a flyer at altitude 3).
--
--Rendering: dmhub.GetMarkupZones feeds the tile height overlay, which draws
--each zone as diagonal stripes + a name label. DM-only unless the zone is
--marked playerVisible - which new zones are by default, so a painted hazard
--reads to the table without the DM remembering to publish each one. A zone the
--DM wants kept secret is turned off individually in the Edit Zone dialog; a
--whole type that is nearly always secret is turned off once on the keyword
--("New Zones Visible to Players"), which CreateZone stamps onto each new zone.
--
--This file loads before EnvironmentalKeyword.lua (main.lua order), so every
--reference to the EnvironmentalKeyword global is runtime + rawget-guarded.
--============================================================================

--Built-in zone types (design: built-ins ARE Environmental Keywords - ship as
--presets that lazily materialize into the environmentalKeywords table on
--first use, exactly like wall presets materialize wall assets). Colors match
--the tile height overlay's built-in stripe colors so the readout stays
--consistent with un-zoned tiles that carry the same rules.
K.ZONE_PRESETS = {
    {
        key = "difficult",
        name = "Difficult Terrain",
        summary = "Costs double to move through",
        color = "#8c5926",
        description = "This area is difficult terrain.",
        fields = { difficultTerrain = true },
    },
    {
        key = "water",
        name = "Water",
        summary = "Water - swim or wade",
        color = "#3373d9",
        description = "This area is water.",
        fields = { water = true },
    },
    {
        key = "concealing",
        name = "Concealing",
        summary = "Grants concealment",
        color = "#4d594d",
        description = "Creatures in this area have concealment.",
        fields = { concealment = true },
    },
}

K.ZONE_PRESETS_BY_KEY = {}
for _,preset in ipairs(K.ZONE_PRESETS) do
    K.ZONE_PRESETS_BY_KEY[preset.key] = preset
end

--Fallback chip/stripe colors for keywords whose icon color is white/unset.
K.ZONE_FALLBACK_COLORS = {
    "#d94a3d", "#7a3dd9", "#3dd9c8", "#d9b83d", "#d93d9e", "#4ad93d",
}

K.ZONE_ANGLE_A = math.pi * 0.25
K.ZONE_ANGLE_B = math.pi * 0.75

--Zone stripes, shared by the map overlay and the panel's little zone swatches.
--Kept in one table rather than as several file-level locals, grouping the
--related state (same reason as m.dispelState in MapMarkupZoneRuntime.lua).
--
--  .HashAngle(id)        angle from the keyword id alone
--  .AngleForKeyword(id)  the angle actually used - the map-wide assignment when
--                        there is one, else the hash
--  .Assign(zoneCache)    recomputes that assignment (defined below KeywordColor,
--                        which it needs; see the note there)
--  .Swatch(color, angle) the panel's little striped zone chip
--
--`assignment` starts empty, so everything falls back to the hash until the zone
--cache has been built at least once for the current map.
m.zoneStripes = { gradients = {}, assignment = {}, swatchPeriod = 0.28 }

--Two angles only. Which one a keyword gets is decided in .Assign below; this is
--the starting point and the tiebreak - a stable function of the keyword id, so
--a keyword with nothing to clash with stripes the same way on every map.
function m.zoneStripes.HashAngle(keywordid)
    if type(keywordid) ~= "string" or keywordid == "" then
        return K.ZONE_ANGLE_A
    end

    local hash = 0
    for i = 1,string.len(keywordid) do
        hash = (hash * 31 + string.byte(keywordid, i)) % 65536
    end

    --a middle bit rather than the low one: with an odd multiplier the low bit
    --is just the parity of the byte sum, which clumps for similar ids.
    if math.floor(hash / 128) % 2 == 1 then
        return K.ZONE_ANGLE_B
    end

    return K.ZONE_ANGLE_A
end

--The stripe angle for a keyword. This is a property of the KEYWORD, not of
--paint order: every Darkness zone on a map stripes one way and every Sunlight
--zone the other, so same-keyword regions read as one thing at a glance. (It
--used to alternate with the number of zones already on the floor, which gave
--two zones of the same keyword different angles.)
function m.zoneStripes.AngleForKeyword(keywordid)
    if type(keywordid) ~= "string" or keywordid == "" then
        return K.ZONE_ANGLE_A
    end

    return m.zoneStripes.assignment[keywordid] or m.zoneStripes.HashAngle(keywordid)
end

--============================================================================
--Per-zone-type fade: the opacity slider on each group in the Zones list.
--
--Purely a local viewing aid, in the same spirit as Fade Map above: it dims
--one zone TYPE on the map so the others (or the map art under them) read
--clearly. Session-only - nothing is written to a setting, a preference or the
--map record - so it starts at 100% on every load, and it is applied only
--while the Map Markup panel is open, so a slider left at 20% cannot follow
--the Director back to the table or reach a player.
--
--It is applied to the COLOUR the overlay feed hands the engine, not to any
--stored data, which is why it costs an overlay re-mesh (the colours are baked
--into the mesh) and nothing else. Zone labels take the same colour
--(TileHeightOverlay.EmitMarkupZones sets textColor = zone.color), so a faded
--type's labels fade with its stripes.
--
--  .opacity[key]    0..1 per group key; ABSENT means full strength
--  .opacitySeq      bumped on every real change - the feed's re-mesh signal
--  .opacityFeedSeq  the seq the feed last published (see dmhub.GetMarkupZones)
--
--(Fields on m.zoneStripes rather than file-level locals, same reason the
--rest of this table exists.)
--============================================================================
m.zoneStripes.opacity = {}
m.zoneStripes.opacitySeq = 0
m.zoneStripes.opacityFeedSeq = 0

--Zones group by keyword - one group, one slider, per zone type. A record
--whose keyword id could not be resolved (dead id from the table-creation
--race; see MaterializeZonePreset) falls back to its stored keyword NAME, so
--it still groups with its siblings instead of splitting off on its own.
function m.zoneStripes.GroupKey(entry)
    if type(entry.keywordid) == "string" and entry.keywordid ~= "" then
        return entry.keywordid
    end
    return "name:" .. tostring(entry.keywordName or "Zone")
end

function m.zoneStripes.Opacity(key)
    if type(key) ~= "string" or key == "" then
        return 1
    end
    return m.zoneStripes.opacity[key] or 1
end

function m.zoneStripes.SetOpacity(key, value)
    if type(key) ~= "string" or key == "" then
        return
    end

    local v = tonumber(value) or 1
    if v < 0 then
        v = 0
    elseif v > 1 then
        v = 1
    end
    --quantized to the slider's own 1% display resolution: a drag fires an
    --event per frame and every distinct value costs an overlay re-mesh, so
    --sub-percent jitter is not worth re-meshing for.
    v = math.floor(v * 100 + 0.5) / 100

    --full strength is stored as absent, so AnyFade below is a plain emptiness
    --test and the feed can skip the whole pass in the common case.
    local stored = nil
    if v < 1 then
        stored = v
    end

    if m.zoneStripes.opacity[key] == stored then
        return
    end

    m.zoneStripes.opacity[key] = stored
    m.zoneStripes.opacitySeq = m.zoneStripes.opacitySeq + 1
end

function m.zoneStripes.AnyFade()
    for _,_ in pairs(m.zoneStripes.opacity) do
        return true
    end
    return false
end

--The stripe colour scaled by a fade factor. Only the "#rrggbb"/"#rrggbbaa"
--forms can be scaled; anything else (a named colour) passes through, matching
--ZoneOverlayColor's own rule.
function m.zoneStripes.FadeColor(color, opacity)
    if opacity >= 1 or type(color) ~= "string" or string.sub(color, 1, 1) ~= "#" then
        return color
    end

    local len = string.len(color)
    local alpha = 255
    if len == 9 then
        alpha = tonumber(string.sub(color, 8, 9), 16) or 255
    elseif len ~= 7 then
        return color
    end

    alpha = math.floor(alpha * opacity + 0.5)
    if alpha < 0 then
        alpha = 0
    elseif alpha > 255 then
        alpha = 255
    end

    return string.format("%s%02x", string.sub(color, 1, 7), alpha)
end

--Muted, compact styling for the group opacity sliders, matching the per-floor
--sliders in the Floors panel. Passed at the PercentSlider call site: the
--control attaches its OWN styles list, which outranks the panel's cascade
--rules, so muting it from the cascade is a no-op. Resolved via MergeTokens at
--build time (the list rebuilds on every refresh, so a live theme switch is
--picked up on the next refresh).
function m.zoneStripes.OpacitySliderStyles()
    return ThemeEngine.MergeTokens{
        {
            selectors = {"percentSlider"},
            borderWidth = 1,
            borderColor = "@border",
            cornerRadius = 2,
            bgimage = "panels/square.png",
            bgcolor = "@bg",
            height = 12,
            flow = "none",
        },
        {
            selectors = {"percentSliderLabel"},
            color = "@fg",
            fontSize = 10,
            bold = true,
            halign = "left",
            valign = "center",
            width = 40,
            textAlignment = "center",
            height = "auto",
        },
        --the clipped duplicate that shows over the filled portion needs the
        --inverse treatment to stay legible against the fill.
        {
            selectors = {"percentSliderLabel", "fill"},
            color = "@bg",
        },
        {
            selectors = {"percentFill"},
            bgcolor = "@fgMuted",
            height = "100%",
            width = "0%",
            halign = "left",
            cornerRadius = 2,
        },
    }
end

--{h, s, v} in 0..1 for a "#rrggbb" / "#rrggbbaa" colour; nil for anything else
--(named colours, which the panel's colours never are in practice).
function m.zoneStripes.HSV(color)
    if type(color) ~= "string" or string.sub(color, 1, 1) ~= "#" then
        return nil
    end

    local len = string.len(color)
    if len ~= 7 and len ~= 9 then
        return nil
    end

    local r = tonumber(string.sub(color, 2, 3), 16)
    local g = tonumber(string.sub(color, 4, 5), 16)
    local b = tonumber(string.sub(color, 6, 7), 16)
    if r == nil or g == nil or b == nil then
        return nil
    end

    r = r / 255
    g = g / 255
    b = b / 255

    local maxc = math.max(r, g, b)
    local minc = math.min(r, g, b)
    local delta = maxc - minc

    local h = 0
    if delta > 0 then
        if maxc == r then
            --Lua's % is floored, so the negative case wraps to 0..6 correctly.
            h = ((g - b) / delta) % 6
        elseif maxc == g then
            h = (b - r) / delta + 2
        else
            h = (r - g) / delta + 4
        end
        h = h / 6
    end

    local s = 0
    if maxc > 0 then
        s = delta / maxc
    end

    return { h = h, s = s, v = maxc }
end

--"How hard would these two be to tell apart as stripe washes over map art."
--Not a real perceptual metric - hue carries most of it, because the stripes are
--translucent and lose a lot of their value/saturation to whatever is under
--them. Greys have no meaningful hue, so hue only counts as far as the LESS
--saturated of the two is actually coloured. 0 = identical; .similarThreshold is
--about where two colours stop reading as the same wash.
m.zoneStripes.similarThreshold = 0.25

function m.zoneStripes.ColorDistance(a, b)
    local dh = math.abs(a.h - b.h)
    if dh > 0.5 then
        dh = 1 - dh
    end

    return dh * 2 * math.min(a.s, b.s)
        + math.abs(a.v - b.v) * 0.6
        + math.abs(a.s - b.s) * 0.3
end

--Diagonal stripes as a gradient: a linear gradient along (cos angle, sin
--angle) - the same direction vector the overlay shader uses, so the panel
--stripes run the same way the map ones do - that flips hard between the colour
--and its transparent form. The a->b vector is one stripe period long and the
--gradient wraps ('repeat'), so period is a fraction of the swatch, not of the
--gradient. Returns nil for colours we can't build a transparent twin of (named
--colours), in which case callers fall back to a flat chip.
function m.zoneStripes.Gradient(color, angle)
    if type(color) ~= "string" or string.sub(color, 1, 1) ~= "#" then
        return nil
    end

    local len = string.len(color)
    if len ~= 7 and len ~= 9 then
        return nil
    end

    angle = angle or K.ZONE_ANGLE_A

    local rgb = string.sub(color, 1, 7)
    local key = rgb .. "/" .. tostring(angle)
    if m.zoneStripes.gradients[key] ~= nil then
        return m.zoneStripes.gradients[key]
    end

    --the transparent stop keeps the same RGB so the (narrow) blend band
    --between stripe and gap doesn't darken towards black.
    local result = gui.Gradient{
        type = "linear",
        point_a = {x = 0.5, y = 0.5},
        point_b = {
            x = 0.5 + math.cos(angle) * m.zoneStripes.swatchPeriod,
            y = 0.5 + math.sin(angle) * m.zoneStripes.swatchPeriod,
        },
        ["repeat"] = true,
        stops = {
            {position = 0.00, color = rgb .. "ff"},
            {position = 0.48, color = rgb .. "ff"},
            {position = 0.52, color = rgb .. "00"},
            {position = 1.00, color = rgb .. "00"},
        },
    }

    m.zoneStripes.gradients[key] = result
    return result
end

--The little 14x14 zone swatch used by the palette chips and the zone list.
function m.zoneStripes.Swatch(color, angle)
    local gradient = m.zoneStripes.Gradient(color, angle)

    --the gradient MULTIPLIES the panel's own colour, so with a gradient the
    --colour lives in the stops and the panel itself must be white.
    local bgcolor = color
    if gradient ~= nil then
        bgcolor = "white"
    end

    return gui.Panel{
        width = 14,
        height = 14,
        valign = "center",
        bgimage = true,
        bgcolor = bgcolor,
        gradient = gradient,
        borderWidth = 1,
        borderColor = "@border",
    }
end

--Per-map zone palette, exactly like the wall palette: ';'-joined tokens.
--  "preset:<key>"            built-in not yet materialized as a keyword
--  "preset:<key>:<id>"       built-in materialized as keyword <id>
--  "keyword:<id>"            keyword added from the library / created new
--  "none"                    explicitly empty
K.DEFAULT_ZONE_PALETTE = "preset:difficult;preset:water;preset:concealing"

gs.zonePaletteSetting = setting{
    id = "markup:zonepalette",
    description = "Map Markup Zone Palette",
    storage = "map",
    default = K.DEFAULT_ZONE_PALETTE,
}

local function ParseZonePalette()
    local result = {}
    local str = gs.zonePaletteSetting:Get()
    if type(str) ~= "string" or str == "" or str == "none" then
        return result
    end

    for _,token in ipairs(string.split(str, ";")) do
        local parts = string.split(token, ":")
        if parts[1] == "preset" and parts[2] ~= nil then
            result[#result+1] = {
                kind = "preset",
                key = parts[2],
                keywordid = parts[3],
            }
        elseif parts[1] == "keyword" and parts[2] ~= nil then
            result[#result+1] = {
                kind = "keyword",
                keywordid = parts[2],
            }
        end
    end

    return result
end

local function SerializeZonePalette(entries)
    local tokens = {}
    for _,entry in ipairs(entries) do
        if entry.kind == "preset" then
            if entry.keywordid ~= nil then
                tokens[#tokens+1] = string.format("preset:%s:%s", entry.key, entry.keywordid)
            else
                tokens[#tokens+1] = string.format("preset:%s", entry.key)
            end
        elseif entry.keywordid ~= nil then
            tokens[#tokens+1] = string.format("keyword:%s", entry.keywordid)
        end
    end

    if #tokens == 0 then
        return "none"
    end
    return table.concat(tokens, ";")
end

local function SaveZonePalette(entries)
    gs.zonePaletteSetting:Set(SerializeZonePalette(entries))
end

--============================================================================
--"Entire Map" zone types: a type the whole map carries by default, with no
--painted region. Stored per map as a ';'-joined list of keyword ids, exactly
--like the palette above; the palette chip's "Entire Map" button toggles it.
--
--A blanket type registers one aura per floor covering every tile of the map's
--extent EXCEPT the tiles of painted zones that interact with it: zones of the
--same keyword (which would otherwise double up on those tiles), zones whose
--keyword dispels it, and zones of keywords it dispels. Explicit painting
--always wins over the blanket -- which is also what keeps a blanketed map
--paintable, since the paint-time dispel rules only ever consult painted
--records (ZonesOnFloor), never these entries.
--
--Blankets deliberately do NOT feed the overlay: striping every tile of the
--map would bury the painted zones the DM is actually working with. The lit
--button on the palette chip is the indicator.
--
--One table rather than a handful of file-level locals, grouping the related
--state (same reason as m.zoneStripes and m.dispelState). Rebuild is assigned
--in MapMarkupZoneRuntime.lua, where the zone cache it reads lives.
--============================================================================
m.entireMap = {
    --resolved blanket entries (same shape as m.zoneCache entries, plus
    --entireMap = true); rebuilt with the zone cache.
    entries = {},

    --the CacheKey value the entries were built from; see EnsureZoneCache.
    cacheKey = false,

    setting = setting{
        id = "markup:zoneentiremap",
        description = "Map Markup Entire-Map Zone Types",
        storage = "map",
        default = "",
    },
}

--pcall-guarded: this is read from EnsureZoneCache, which runs on every aura
--poll -- including polls that land before there is a map to scope a
--map-storage setting to (boot, map switches).
function m.entireMap.Serialized()
    local str = nil
    pcall(function()
        str = m.entireMap.setting:Get()
    end)
    if type(str) ~= "string" then
        return ""
    end
    return str
end

--Set of keyword ids this map blankets.
function m.entireMap.Keywords()
    local result = {}
    for _,id in ipairs(string.split(m.entireMap.Serialized(), ";")) do
        if id ~= "" then
            result[id] = true
        end
    end
    return result
end

function m.entireMap.IsSet(keywordid)
    if keywordid == nil then
        return false
    end
    return m.entireMap.Keywords()[keywordid] == true
end

--Turns the blanket on or off for a keyword. Ids are stored sorted so the
--serialized value is stable: it doubles as part of the zone cache's validity
--key, and a reordering would rebuild the cache for nothing.
function m.entireMap.Set(keywordid, value)
    if keywordid == nil then
        return
    end

    local ids = m.entireMap.Keywords()
    if (ids[keywordid] == true) == (value == true) then
        return
    end

    if value == true then
        ids[keywordid] = true
    else
        ids[keywordid] = nil
    end

    local sorted = {}
    for id,_ in pairs(ids) do
        sorted[#sorted+1] = id
    end
    table.sort(sorted)
    m.entireMap.setting:Set(table.concat(sorted, ";"))
end

--The zone cache's validity key for blankets. The setting can change without
--any zone record changing (and can change on another client), so the cache
--compares this rather than trusting a callback. The map extent rides along
--because that is exactly what a blanket covers: resizing the map has to
--rebuild it. Empty string when nothing is blanketed -- the common case, and
--the reason the extent is only read when it can matter (this runs on every
--aura poll).
function m.entireMap.CacheKey()
    local str = m.entireMap.Serialized()
    if str == "" then
        return ""
    end

    local dims = nil
    pcall(function()
        local map = game.currentMap
        if map ~= nil then
            dims = map.dimensions
        end
    end)
    if dims == nil then
        return str
    end

    return string.format("%s@%d,%d,%d,%d", str,
        math.floor(dims.x), math.floor(dims.y), math.floor(dims.z), math.floor(dims.w))
end

K.ENVIRONMENTAL_KEYWORDS_TABLE = "environmentalKeywords"

local function GetKeywordTable()
    return dmhub.GetTable(K.ENVIRONMENTAL_KEYWORDS_TABLE) or {}
end

local function GetKeyword(keywordid)
    if keywordid == nil then
        return nil
    end
    return GetKeywordTable()[keywordid]
end

--"x,y" key for a tile. Defined here (not with the editing operations in
--MapMarkupZoneStorage.lua) because the ZoneManager's dispel machinery keys
--tiles too.
local function ZoneLocKey(x, y)
    return string.format("%d,%d", x, y)
end

--Dynamic-light zone types: a zone type can be set to only apply where the map's
--light level is below a per-type threshold (the flagship use: Darkness that is
--dynamically calculated from the light on the map). The engine samples light
--deterministically (dmhub.GetDarkTiles: ambient day/night + token/object lights
--with wall shadowing, animation-free), and the sampled dark sets carve the
--type's footprints -- painted zones AND its Entire Map blanket -- exactly like
--the dispel machinery carves them: records are untouched, the auras and overlay
--stripes just skip lit tiles.
--
--Per-map setting "kwid:pct;kwid:pct" (pct = light threshold percent; below it a
--tile counts as dark), sorted for a stable cache key. Sampled state lives here
--too: [floorid.."@"..pct] = {state=<engine hash>, dark={[lockey]=true}}, with
--`serial` bumped on every change so EnsureZoneCache rebuilds. All of it on ONE
--table, grouping the related state (see m.entireMap).
m.dynamicLight = {
    setting = setting{
        id = "markup:zonedynamiclight",
        description = "Map Markup Dynamic-Light Zone Types",
        storage = "map",
        default = "",
    },

    --nil = not probed yet; the engine API is new, so the UI hides on old builds.
    supported = nil,

    states = {},
    serial = 0,

    --the CacheKey value the current zone cache was built from (EnsureZoneCache).
    cacheKey = false,
}

function m.dynamicLight.Supported()
    if m.dynamicLight.supported == nil then
        local ok, value = pcall(function()
            return dmhub.supportsDynamicLightZones
        end)
        m.dynamicLight.supported = (ok and value == true)
    end
    return m.dynamicLight.supported
end

--pcall-guarded like m.entireMap.Serialized: read on aura polls that can land
--before there is a map to scope a map-storage setting to.
function m.dynamicLight.Serialized()
    local str = nil
    pcall(function()
        str = m.dynamicLight.setting:Get()
    end)
    if type(str) ~= "string" then
        return ""
    end
    return str
end

--{ keywordid -> threshold percent (integer 1..100) }. Only keywords whose
--compendium entry has "Can Use Dynamic Light" checked count: unchecking the
--flag disables an already-configured threshold everywhere (carve, sampling,
--chip UI) without deleting it -- re-checking restores it. The flag lives on
--the keyword so the palette only offers Dynamic Light where it makes sense
--(Darkness), not on every chip. refreshTables bumps m.zoneTablesGen, which
--is already part of the zone cache key, so a flag flip rebuilds promptly.
function m.dynamicLight.Thresholds()
    local result = {}
    for _,item in ipairs(string.split(m.dynamicLight.Serialized(), ";")) do
        if item ~= "" then
            local kwid, pct = string.match(item, "^(.-):(%d+)$")
            pct = tonumber(pct)
            if kwid ~= nil and kwid ~= "" and pct ~= nil and pct > 0 then
                local allowed = false
                local kw = GetKeyword(kwid)
                if kw ~= nil then
                    --pcall: this file loads before EnvironmentalKeyword, so
                    --keyword instances are only known well-typed at runtime.
                    pcall(function()
                        allowed = kw:try_get("dynamicLight", false) == true
                    end)
                end
                if allowed then
                    result[kwid] = pct
                end
            end
        end
    end
    return result
end

function m.dynamicLight.GetThreshold(keywordid)
    if keywordid == nil then
        return nil
    end
    return m.dynamicLight.Thresholds()[keywordid]
end

--Sets or clears (pct = nil) the threshold for a keyword. Stored sorted so the
--serialized value is stable: it is part of the zone cache's validity key.
function m.dynamicLight.Set(keywordid, pct)
    if keywordid == nil then
        return
    end

    local thresholds = m.dynamicLight.Thresholds()
    if thresholds[keywordid] == pct then
        return
    end
    thresholds[keywordid] = pct

    local sorted = {}
    for id,value in pairs(thresholds) do
        sorted[#sorted+1] = string.format("%s:%d", id, value)
    end
    table.sort(sorted)
    m.dynamicLight.setting:Set(table.concat(sorted, ";"))
end

--The zone cache's validity key for dynamic light: the configuration plus the
--sampling serial (a sample changing what is dark must rebuild the footprints).
--Empty string when the feature is off -- the common case.
function m.dynamicLight.CacheKey()
    local str = m.dynamicLight.Serialized()
    if str == "" then
        return ""
    end
    return string.format("%s#%d", str, m.dynamicLight.serial)
end

function m.dynamicLight.StateKey(floorid, pct)
    return string.format("%s@%d", floorid, pct)
end

--entry.locs filtered to the currently-dark tiles when the entry's keyword is
--light-gated; entry.locs itself otherwise. NEVER mutates entry.locs -- the
--record locs also drive painting/splitting, and a filtered list written back
--would drop lit tiles from the record on its next write. An unsampled
--(floor, threshold) applies the zone unfiltered: painted zones stay in force
--until the first sample lands (<1s), rather than flashing off.
function m.dynamicLight.ApplyFilter(thresholds, entry)
    local pct = nil
    if entry.keywordid ~= nil then
        pct = thresholds[entry.keywordid]
    end
    if pct == nil then
        return entry.locs
    end

    local darkState = m.dynamicLight.states[m.dynamicLight.StateKey(entry.floorid, pct)]
    if darkState == nil then
        return entry.locs
    end

    local filtered = {}
    for _,l in ipairs(entry.locs) do
        local key = ZoneLocKey(l.x, l.y)
        --a tile the sampler has never seen (just painted; next sample is
        --<1s away) defaults to applying, like an unsampled floor does --
        --absent from `sampled` means unknown, not lit. Rect-mode samples
        --(blankets) have sampled == nil: the rect covers the whole map.
        if darkState.dark[key] ~= nil
            or (darkState.sampled ~= nil and darkState.sampled[key] == nil) then
            filtered[#filtered+1] = l
        end
    end
    return filtered
end

--The keyword's stripe/chip color: its icon background color when it has a
--real one, otherwise a fallback picked stably from the keyword id.
local function KeywordColor(keywordid, kw)
    local color = nil
    if kw ~= nil then
        pcall(function()
            local display = kw:try_get("display")
            if display ~= nil then
                color = display.bgcolor
            end
        end)
    end

    --the compendium color picker persists its value as a Color USERDATA
    --(the standard display.bgcolor idiom across compendium editors); its
    --.tostring PROPERTY is the real "#RRGGBBAA" hex string. Presets and
    --older items store plain strings. Normalize to a string, and trim a
    --fully-opaque alpha suffix so the overlay's standard stripe alpha
    --still applies (ZoneOverlayColor only decorates 7-char "#rrggbb").
    if type(color) == "userdata" then
        local ok, str = pcall(function() return color.tostring end)
        if ok and type(str) == "string" then
            color = str
        else
            color = nil
        end
    end
    if type(color) == "string" and string.len(color) == 9
        and string.lower(string.sub(color, 8, 9)) == "ff" then
        color = string.sub(color, 1, 7)
    end

    if type(color) == "string" and color ~= "" and string.lower(color) ~= "white"
        and string.lower(color) ~= "#ffffff" and string.lower(color) ~= "#ffffffff" then
        return color
    end

    local hash = 0
    for i = 1, #(keywordid or "") do
        hash = (hash * 31 + string.byte(keywordid, i)) % 65536
    end
    return K.ZONE_FALLBACK_COLORS[(hash % #K.ZONE_FALLBACK_COLORS) + 1]
end

--Picks a stripe angle for every keyword on the map in ONE pass over the whole
--set, so keywords whose colours are close can be pushed to opposite angles:
--two similar reds side by side then read as two regions instead of one blur.
--(Lives here rather than up with the rest of m.zoneStripes because it needs
--KeywordColor and ParseZonePalette, and a closure written above a file-level
--local can't see it - it would compile to a global read and come back nil.)
--
--The set is the keywords with painted zones plus the ones in the map's palette.
--Live auras are deliberately NOT included: they come and go mid-encounter and
--would restripe the painted map underneath them.
--
--Greedy, in sorted-id order. Each keyword takes whichever angle leaves it the
--most colour distance from what is already on that angle, and keeps its hash
--angle when nothing assigned is close enough to be confusable. With only two
--angles a chain of three or more similar colours cannot be fully separated -
--this keeps the closest pairs apart and accepts the rest. Deterministic given
--the set, so an angle only moves when the map's zone types actually change.
local function AssignZoneStripeAngles(zoneCache)
    local colors = {}
    local ids = {}

    local function Add(keywordid)
        if type(keywordid) ~= "string" or keywordid == "" or colors[keywordid] ~= nil then
            return
        end

        local hsv = m.zoneStripes.HSV(KeywordColor(keywordid, GetKeyword(keywordid)))
        if hsv == nil then
            return
        end

        colors[keywordid] = hsv
        ids[#ids+1] = keywordid
    end

    for _,entry in ipairs(zoneCache or {}) do
        Add(entry.keywordid)
    end
    for _,entry in ipairs(ParseZonePalette()) do
        Add(entry.keywordid)
    end

    table.sort(ids)

    local assignment = {}
    for _,id in ipairs(ids) do
        --closest already-assigned colour on each angle.
        local nearA = nil
        local nearB = nil
        for otherid,otherAngle in pairs(assignment) do
            local d = m.zoneStripes.ColorDistance(colors[id], colors[otherid])
            if otherAngle == K.ZONE_ANGLE_A then
                if nearA == nil or d < nearA then
                    nearA = d
                end
            else
                if nearB == nil or d < nearB then
                    nearB = d
                end
            end
        end

        local angle = m.zoneStripes.HashAngle(id)
        if (nearA ~= nil and nearA < m.zoneStripes.similarThreshold)
            or (nearB ~= nil and nearB < m.zoneStripes.similarThreshold) then
            local a = nearA or math.huge
            local b = nearB or math.huge
            if a > b then
                angle = K.ZONE_ANGLE_A
            elseif b > a then
                angle = K.ZONE_ANGLE_B
            end
        end

        assignment[id] = angle
    end

    m.zoneStripes.assignment = assignment
end

--Effective rule flags a keyword contributes to tiles. try_get throughout:
--older serialized keywords predate some fields, and game-typed instances
--raise on unknown-field reads.
local function KeywordFlags(kw)
    local flags = { difficultTerrain = false, water = false, concealment = false, climbable = false, climbersOnly = false }
    if kw == nil then
        return flags
    end
    pcall(function()
        flags.difficultTerrain = kw:try_get("difficultTerrain", false) == true
        flags.water = kw:try_get("water", false) == true
        flags.concealment = kw:try_get("concealment", false) == true
        flags.climbable = kw:try_get("climbable", false) == true
        flags.climbersOnly = kw:try_get("climbersOnly", false) == true
    end)
    return flags
end

--Set of keyword ids this keyword dispels (EnvironmentalKeyword.dispels), as
--a lookup table. Empty for nil keywords and keywords predating the field.
local function KeywordDispels(kw)
    local result = {}
    if kw == nil then
        return result
    end
    pcall(function()
        for _,id in ipairs(kw:try_get("dispels", {})) do
            result[id] = true
        end
    end)
    return result
end

--============================================================================
--Default zone height, per zone TYPE. The height a zone reaches is a property
--of what the zone is - lava is ground only, a gas cloud is a couple of tiles,
--darkness fills the room - so the default lives on the EnvironmentalKeyword
--(field defaultHeight) rather than on the map or the tool. It is stamped onto
--each zone by CreateZone as it is painted; the zone owns its height from then
--on (Edit Zone dialog), so changing the type later does not disturb zones
--already on a map.
--
--Values: nil = unlimited, 0 = ground only, N = up to N tiles above the ground.
--Bands are GROUND-RELATIVE (BuildZoneAuraInstance sets auraGroundRelative), so
--"ground only" covers a creature standing in the zone whether the zone sits on
--flat ground, in a pit, or on a raised ledge, and excludes anything flying
--over it.
--
--Everything hangs off this ONE table, grouping the related state.
m.zoneHeight = {}

--The type's default height, or nil for unlimited. try_get + pcall: keywords
--serialized before this field exist, and game-typed instances raise on
--unknown-field reads.
function m.zoneHeight.Get(kw)
    if kw == nil then
        return nil
    end
    local result = nil
    pcall(function()
        local value = kw:try_get("defaultHeight")
        if value ~= nil then
            result = math.max(0, math.floor(tonumber(value) or 0))
        end
    end)
    return result
end

--Writes the default onto the keyword. nil clears it back to unlimited (the
--same nil-assign the keyword editor uses to clear mapid).
function m.zoneHeight.Set(keywordid, height)
    local kw = GetKeyword(keywordid)
    if kw == nil then
        return
    end
    if height == nil then
        kw.defaultHeight = nil
    else
        kw.defaultHeight = math.max(0, math.floor(height))
    end
    dmhub.SetAndUploadTableItem(K.ENVIRONMENTAL_KEYWORDS_TABLE, kw)
end

--Human-readable height for chip summaries, list rows and menus. Unlimited is
--the default and reads as clutter everywhere, so it describes as nil.
function m.zoneHeight.Describe(height)
    if height == nil then
        return nil
    end
    if height <= 0 then
        return "Ground only"
    end
    if height == 1 then
        return "Up to 1 tile high"
    end
    return string.format("Up to %d tiles high", height)
end

local function KeywordModifierCount(kw)
    local count = 0
    if kw == nil then
        return 0
    end
    pcall(function()
        local modifiers = kw:try_get("modifiers")
        if modifiers ~= nil then
            count = #modifiers
        end
    end)
    return count
end

local function KeywordSummary(kw)
    local parts = {}
    local flags = KeywordFlags(kw)
    if flags.difficultTerrain then parts[#parts+1] = "Difficult terrain" end
    if flags.water then parts[#parts+1] = "Water" end
    if flags.concealment then parts[#parts+1] = "Concealment" end
    if flags.climbable then
        if flags.climbersOnly then
            parts[#parts+1] = "Climbable (climbers only)"
        else
            parts[#parts+1] = "Climbable"
        end
    end
    pcall(function()
        local movedamage = kw:try_get("movedamage", "none")
        if movedamage ~= nil and movedamage ~= "none" then
            local amount = math.floor(tonumber(kw:try_get("damage", 0)) or 0)
            parts[#parts+1] = string.format("%d %s on move", amount, movedamage)
        end
    end)
    pcall(function()
        if kw:try_get("powerRollEnabled", false) and kw:try_get("powerRollTiers") ~= nil then
            parts[#parts+1] = "Damaging"
        end
    end)
    pcall(function()
        if kw:try_get("includeAdjacent", false) == true then
            parts[#parts+1] = "Affects adjacent"
        end
    end)
    --a keyword restricted to some creatures reads very differently from one
    --that catches everyone, so the palette says so without quoting the script.
    pcall(function()
        if kw:try_get("creatureFilter", "") ~= "" then
            parts[#parts+1] = "Filtered"
        end
    end)
    --the default height a zone of this type is painted with; unlimited (the
    --default) describes as nil and stays out of the summary.
    local heightText = m.zoneHeight.Describe(m.zoneHeight.Get(kw))
    if heightText ~= nil then
        parts[#parts+1] = heightText
    end
    pcall(function()
        local dispels = kw:try_get("dispels")
        if dispels ~= nil and #dispels > 0 then
            local names = {}
            local dataTable = GetKeywordTable()
            for _,id in ipairs(dispels) do
                local target = dataTable[id]
                if target ~= nil and target.name ~= nil then
                    names[#names+1] = target.name
                end
            end
            if #names > 0 then
                parts[#parts+1] = "Dispels " .. table.concat(names, ", ")
            end
        end
    end)
    pcall(function()
        if kw:try_get("mapid") ~= nil then
            parts[#parts+1] = "This map only"
        end
    end)
    local nmods = KeywordModifierCount(kw)
    if nmods == 1 then
        parts[#parts+1] = "1 modifier"
    elseif nmods > 1 then
        parts[#parts+1] = string.format("%d modifiers", nmods)
    end
    if #parts == 0 then
        return "No effects yet"
    end
    return table.concat(parts, " - ")
end

--Whether a keyword is usable on the current map: full keywords always are;
--map-scoped zone types (mapid set; see EnvironmentalKeyword.mapid) only on
--the map they were created on.
local function KeywordAvailableOnThisMap(kw)
    local mapid = nil
    pcall(function() mapid = kw:try_get("mapid") end)
    return mapid == nil or mapid == game.currentMapId
end

--Finds a keyword id by (case-insensitive) name, or nil. Skips zone types
--scoped to other maps so preset adoption and dead-id healing never cross maps.
local function FindKeywordIdByName(name)
    if name == nil or name == "" then
        return nil
    end
    for k,kw in unhidden_pairs(GetKeywordTable()) do
        if string.lower(kw.name or "") == string.lower(name) and KeywordAvailableOnThisMap(kw) then
            return k
        end
    end
    return nil
end

--Whether any zone record on the current map still uses this keyword. Records
--reference keywords by id but heal dead ids by stored name (see
--RebuildZoneCache), so a record whose id no longer resolves and whose
--keywordName matches counts as using it too. Assigned here rather than in
--the m.mapScope constructor because it needs GetKeyword, which is declared
--below that constructor (a closure written above a file-level local compiles
--to a global read and comes back nil).
m.mapScope.KeywordInUseOnMap = function(keywordid, kw)
    local map = game.currentMap
    if map == nil then
        --can't tell; report in-use so the caller keeps the keyword.
        return true
    end
    local kwName = nil
    pcall(function() kwName = kw.name end)
    for _,floor in ipairs(map.floors or {}) do
        local zones = nil
        pcall(function() zones = floor.markupZones end)
        if zones ~= nil then
            for _,record in pairs(zones) do
                if type(record) == "table" and record.category == nil then
                    if record.keyword == keywordid then
                        return true
                    end
                    if kwName ~= nil and record.keywordName ~= nil
                        and GetKeyword(record.keyword) == nil
                        and string.lower(record.keywordName) == string.lower(kwName) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--Deletes a map-scoped zone type when removing its chip orphans it: scoped to
--THIS map (mapid set; so no other map's palette, zones, or dropdowns can
--reference it), no zone records still using it, and no other chip pointing
--at it. Promoted and compendium keywords are shared content and are never
--deleted here. The blanket/dynamic-light configs are cleared by the removal
--path before this runs.
m.mapScope.DeleteKeywordIfOrphaned = function(keywordid, remainingEntries)
    local kw = GetKeyword(keywordid)
    if kw == nil then
        return
    end
    local mapid = nil
    pcall(function() mapid = kw:try_get("mapid") end)
    if mapid == nil or mapid ~= game.currentMapId then
        return
    end
    for _,entry in ipairs(remainingEntries or {}) do
        if entry.keywordid == keywordid then
            return
        end
    end
    if m.mapScope.KeywordInUseOnMap(keywordid, kw) then
        return
    end
    kw.hidden = true
    dmhub.SetAndUploadTableItem(K.ENVIRONMENTAL_KEYWORDS_TABLE, kw)
end

--Materializes a built-in zone preset as a real Environmental Keyword in this
--game's table (or adopts an existing keyword with the same name - e.g. one
--another map's palette already created). Returns the keyword id, or nil when
--the EnvironmentalKeyword type isn't available.
--
--GOTCHA (hit live 2026-07-26): the very first SetAndUploadTableItem into a
--game auto-creates the environmentalKeywords table server-side, and items
--uploaded during that window can be lost when the server's authoritative
--table arrives - leaving palette/zone records pointing at keyword ids that
--no longer exist. That is why zone records also store keywordName and the
--zone cache heals dead ids by name (see RebuildZoneCache).
local function MaterializeZonePreset(preset)
    local keywordType = rawget(_G, "EnvironmentalKeyword")
    if keywordType == nil then
        dmhub.Debug("MARKUP:: EnvironmentalKeyword type not loaded; cannot materialize zone preset")
        return nil
    end

    local existing = FindKeywordIdByName(preset.name)
    if existing ~= nil then
        return existing
    end

    local kw = keywordType.CreateNew()
    kw.name = preset.name
    kw.description = preset.description
    kw.display = {
        bgcolor = preset.color,
        hueshift = 0,
        saturation = 1,
        brightness = 1,
    }
    for field,value in pairs(preset.fields) do
        kw[field] = value
    end

    --NOTE: the item's TABLE ID is assigned by SetAndUploadTableItem and
    --returned (also stamped onto kw.id); it is NOT kw.guid. Referencing
    --kw.guid here left palette entries and zone records stranded on ids
    --that never existed in the table (masked by the heal-by-name path).
    local keywordid = dmhub.SetAndUploadTableItem(K.ENVIRONMENTAL_KEYWORDS_TABLE, kw)

    if GetKeyword(keywordid) == nil then
        --table-creation race: the item isn't locally visible yet. Zone
        --records created against this id heal by keywordName once the
        --table settles.
        dmhub.Debug("MARKUP:: keyword '" .. preset.name .. "' not yet visible after upload (table creation race); records will heal by name")
    end

    return keywordid
end


--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.AssignZoneStripeAngles = AssignZoneStripeAngles
MM.FindKeywordIdByName = FindKeywordIdByName
MM.GetKeyword = GetKeyword
MM.GetKeywordTable = GetKeywordTable
MM.KeywordAvailableOnThisMap = KeywordAvailableOnThisMap
MM.KeywordColor = KeywordColor
MM.KeywordDispels = KeywordDispels
MM.KeywordFlags = KeywordFlags
MM.KeywordModifierCount = KeywordModifierCount
MM.KeywordSummary = KeywordSummary
MM.MaterializeZonePreset = MaterializeZonePreset
MM.ParseZonePalette = ParseZonePalette
MM.SaveZonePalette = SaveZonePalette
MM.SerializeZonePalette = SerializeZonePalette
MM.ZoneLocKey = ZoneLocKey
