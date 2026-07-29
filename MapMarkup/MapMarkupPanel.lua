local mod = dmhub.GetModLoading()

--============================================================================
--Map Markup panel: mark up an imported map image with the gameplay layer
--(walls, doors, zones, surfaces, elevation, props) without touching the
--map's art. Design brief:
--  docs/superpowers/specs/2026-07-22-map-markup-panel-design.md
--
--This file implements the panel shell (mode tabs), the Walls mode, the
--Zones mode and the Footsteps mode (including the zone/surface storage/
--aura/overlay runtime, which runs on every client whether or not the panel
--is open). Footsteps (mode id "surfaces") paints footstep-SOUND regions:
--it only affects the footstep sounds played for creatures moving there.
--Props is a placeholder tab for now.
--
--How wall drawing works: the engine polls dmhub.GetSelectedWall every frame
--(DMSheetHud.selectedWallId). The Building editor publishes its selection
--when it has focus; we chain onto the same hook and publish our selected
--markup wall when this panel has focus instead. Since we never publish a
--floor, the engine is in walls-only mode, where the shape tool draws open
--polylines - which is exactly the markup "Line" tool.
--============================================================================

local function track(eventType, fields)
    if dmhub.GetSettingValue("telemetry_enabled") == false then
        return
    end
    fields.type = eventType
    fields.userid = dmhub.userid
    fields.gameid = dmhub.gameid
    fields.version = dmhub.version
    analytics.Event(fields)
end

--The Core invisible ("see-thru") wall asset markup wall types are duplicated
--from. Wall assets require an image (ImageAsset.ValidationCheck), so presets
--cannot be created from scratch; we duplicate this invisible base and set
--gameplay fields on the copy. Same asset MapImport uses for invisible walls.
local BASE_INVISIBLE_WALL_ID = "eae7f3fe-d278-455c-853a-ac43f948c743"

--The Core "Invisible Floor" tilesheet (invisible=true, Building layer): the
--shared TOP face of every markup solid block. The top face of an invisible
--tilesheet never renders on player clients (and only faintly for the DM while
--an editing tool is open), so one shared sheet serves every solid type - the
--per-type differences live entirely in the wall asset.
local INVISIBLE_TILESHEET_ID = "-MGAVDxkFE-ZzzNYBV0D"

--============================================================================
--Openable walls (doors).
--
--An "openable" wall type is an ordinary markup wall type with
--WallAsset.openable set: it draws REAL wall geometry with the normal thin
--wall tools, so the full drawn stroke blocks exactly like any wall of its
--type. What openable adds is per-stroke door state, engine-side: every
--building operation drawn with an openable wall type is a door. The engine
--(MarkupDoorController) floats a door icon at the operation's midpoint -
--always for the Director, and for players whose token is within 2 tiles
--with line of sight. Clicking it toggles the operation's doorOpen flag
--(clone op + fresh timestamp + patch swap, the Points-tool pattern), and an
--OPEN door op simply contributes no walls at all
--(TerrainLayerInfo.ApplyWallOperation skips it), so movement, vision,
--light, cover and sound occlusion all stop at once and undo/multiplayer
--sync are free. The Director can right-click the icon to lock/unlock the
--door (padlock badge; players see the icon but cannot use it). The open and
--close sounds come from the wall asset (openSound/closeSound) and play as
--networked game sound events.
--============================================================================

--Draw Steel door open/close audio assets (data/audio/ds-opendoor-wav.yaml /
--ds-closedoor-wav.yaml), stamped onto openable wall assets so the engine's
--door toggle plays them for every client.
local DOOR_OPEN_SOUND_ID = "f6bc62cc-7225-48cf-b719-b86280ea198d"
local DOOR_CLOSE_SOUND_ID = "e9950541-0c22-41d3-baba-f7f307b3e81a"

--Gameplay fields stamped on the wall asset backing a new openable type: a
--closed door blocks like a stone wall; opening it disables all of this.
local DOOR_TYPE_FIELDS = {
    blocksMovement = true,
    blocksForcedMovement = true,
    occludesVision = true,
    occludesLight = true,
    cover = "Full",
    soundOcclusion = 0.9,
    climbable = "NotClimbable",
    openable = true,
}

--Preset roster from the design brief (section 4; stats PROPOSED pending
--sign-off). height is the per-placement wall height stamped into the height
--setting when the preset is selected (nil = full height); wall height is a
--property of the drawing operation, not of the wall asset.
local WALL_PRESETS = {
    {
        key = "stone",
        name = "Stone Wall",
        summary = "Blocks all - full cover",
        height = nil,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = true,
            occludesLight = true,
            cover = "Full",
            soundOcclusion = 0.9,
            climbable = "NotClimbable",
        },
    },
    {
        key = "window",
        name = "Window",
        summary = "See-through - half cover",
        height = nil,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = false,
            occludesLight = false,
            cover = "Half",
            soundOcclusion = 0.5,
            climbable = "NotClimbable",
        },
    },
    {
        key = "fence",
        name = "Wooden Fence",
        summary = "Height 1 - climbable",
        height = 1,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = false,
            occludesLight = false,
            cover = "Half",
            soundOcclusion = 0.1,
            climbable = "AllCreatures",
        },
    },
    {
        key = "lowwall",
        name = "Low Wall",
        summary = "Height 1 - half cover",
        height = 1,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = false,
            occludesLight = false,
            cover = "Half",
            soundOcclusion = 0.2,
            climbable = "AllCreatures",
        },
    },
    {
        key = "curtain",
        name = "Curtain",
        summary = "Blocks sight only",
        height = nil,
        fields = {
            blocksMovement = false,
            blocksForcedMovement = false,
            occludesVision = true,
            occludesLight = true,
            cover = "None",
            soundOcclusion = 0.3,
            climbable = "NotClimbable",
        },
    },
    {
        key = "barrier",
        name = "Invisible Barrier",
        summary = "Blocks movement only",
        height = nil,
        fields = {
            blocksMovement = true,
            blocksForcedMovement = true,
            occludesVision = false,
            occludesLight = false,
            cover = "None",
            soundOcclusion = 0,
            climbable = "NotClimbable",
        },
    },
}

local WALL_PRESETS_BY_KEY = {}
for _,preset in ipairs(WALL_PRESETS) do
    WALL_PRESETS_BY_KEY[preset.key] = preset
end

--============================================================================
--Breakability. Any markup wall - thin or solid - can be made breakable: a
--creature shoved into it with enough force smashes through instead of
--stopping. The force needed is the wall's breakStamina.
--
--The material is DERIVED from breakStamina rather than stored: the wall asset
--has no material field, and 1/3/6 map back to Glass/Wood/Stone unambiguously.
--Anything else reads as Custom, so a hand-typed value round-trips as Custom
--and a typed 3 simply reads back as Wood (which it is, mechanically).
--============================================================================

local BREAK_MATERIALS = {
    {
        id = "glass",
        text = "Glass",
        stamina = 1,
    },
    {
        id = "wood",
        text = "Wood",
        stamina = 3,
    },
    {
        id = "stone",
        text = "Stone",
        stamina = 6,
    },
    {
        id = "custom",
        text = "Custom",
        stamina = nil,
    },
}

local DEFAULT_BREAK_STAMINA = 3

local function BreakMaterialForStamina(stamina)
    for _,material in ipairs(BREAK_MATERIALS) do
        if material.stamina ~= nil and material.stamina == stamina then
            return material.id
        end
    end
    return "custom"
end

local function BreakMaterialById(id)
    for _,material in ipairs(BREAK_MATERIALS) do
        if material.id == id then
            return material
        end
    end
    return nil
end

local function AssetIsBreakable(asset)
    return asset ~= nil and asset.solidity ~= "Unbreakable" and (asset.breakStamina or 0) > 0
end

--Writes breakability onto a wall asset.
--
--`solidity` is the engine's BREAK BEHAVIOR selector, not a "is this a solid
--block" flag: WallSolidity.Thin punches a hole through a thin wall,
--WallSolidity.Solid tunnels a cavity through a filled block. Since a markup
--wall type can now be drawn EITHER way, the asset can't know which applies -
--so markup walls are marked Thin and the engine picks the cavity branch from
--the drawn geometry instead (a broken wall that bounds a real solid region
--carves). See MAP_MARKUP_REFERENCE.md "Breakability".
--
--rubble fields stay empty: smashing an invisible wall over imported art must
--not spawn visible debris the DM never placed.
local function SetAssetBreakable(asset, breakable, stamina)
    if breakable then
        asset.solidity = "Thin"
        asset.breakStamina = math.max(1, math.floor((stamina or DEFAULT_BREAK_STAMINA) + 0.5))
    else
        asset.solidity = "Unbreakable"
        asset.breakStamina = 0
    end
    asset.rubbleKeyword = ""
    asset.rubbleTerrainId = ""
end

--============================================================================
--Per-map palette storage.
--
--The palette is stored in a map-scoped setting as a ';'-joined token list:
--  "preset:<key>"          preset not yet materialized as a wall asset
--  "preset:<key>:<guid>"   preset materialized as game wall asset <guid>
--  "custom:<guid>"         custom markup wall created from this panel
--  "wall:<guid>"           existing wall asset added from the library
--  "none"                  explicitly empty palette (distinct from default)
--
--Note there is no door token kind: openable-ness is a property of the WALL
--ASSET (WallAsset.openable), so door types are ordinary custom/wall chips.
--
--Note there is no solid-vs-thin distinction here: solidity is a DRAW MODE
--(the Thin/Solid toggle by the tool strip), not a property of a wall type -
--every palette entry can be drawn either way.
--============================================================================

local DEFAULT_PALETTE = "preset:stone;preset:window;preset:fence;preset:lowwall;preset:curtain;preset:barrier"

local g_paletteSetting = setting{
    id = "markup:wallpalette",
    description = "Map Markup Wall Palette",
    storage = "map",
    default = DEFAULT_PALETTE,
}

local function ParsePalette()
    local result = {}
    local str = g_paletteSetting:Get()
    if type(str) ~= "string" or str == "" or str == "none" then
        return result
    end

    for _,token in ipairs(string.split(str, ";")) do
        local parts = string.split(token, ":")
        if parts[1] == "preset" and parts[2] ~= nil then
            result[#result+1] = {
                kind = "preset",
                key = parts[2],
                guid = parts[3],
            }
        elseif (parts[1] == "wall" or parts[1] == "custom") and parts[2] ~= nil then
            result[#result+1] = {
                kind = parts[1],
                guid = parts[2],
            }
        end
    end

    return result
end

local function SerializePalette(entries)
    local tokens = {}
    for _,entry in ipairs(entries) do
        if entry.kind == "preset" then
            if entry.guid ~= nil then
                tokens[#tokens+1] = string.format("preset:%s:%s", entry.key, entry.guid)
            else
                tokens[#tokens+1] = string.format("preset:%s", entry.key)
            end
        elseif entry.guid ~= nil then
            tokens[#tokens+1] = string.format("%s:%s", entry.kind, entry.guid)
        end
    end

    if #tokens == 0 then
        return "none"
    end
    return table.concat(tokens, ";")
end

local function SavePalette(entries)
    g_paletteSetting:Set(SerializePalette(entries))
end

--============================================================================
--Palette entry helpers.
--============================================================================

local function EntryWallAsset(entry)
    if entry == nil or entry.guid == nil then
        return nil
    end
    return assets.walls[entry.guid]
end

--Engine gate: WallAsset.openable (and the door icon/toggle machinery) needs
--an engine build. NOTE: reading an unknown property on engine userdata does
--NOT error - it silently returns nil (verified live 2026-07-27) - so the
--probe must check the VALUE is non-nil, not just that the read succeeded.
--On a supporting build the accessor returns a real boolean. Cached: chips
--and dialogs consult this repeatedly.
local m_openableSupport = nil
local function OpenableWallsSupported()
    if m_openableSupport ~= nil then
        return m_openableSupport
    end
    local probe = assets.walls[BASE_INVISIBLE_WALL_ID]
    if probe == nil then
        for _,wall in pairs(assets.walls) do
            probe = wall
            break
        end
    end
    if probe == nil then
        --no wall assets at all; leave undecided so we re-probe later.
        return false
    end
    local ok, value = pcall(function()
        return probe.openable
    end)
    m_openableSupport = ok and value ~= nil
    return m_openableSupport
end

local function AssetIsOpenable(asset)
    if asset == nil then
        return false
    end
    local ok, openable = pcall(function()
        return asset.openable
    end)
    return ok and openable == true
end

--Openable wall types draw real wall geometry; each stroke is a door the
--engine floats a toggle icon over.
local function EntryIsOpenable(entry)
    return AssetIsOpenable(EntryWallAsset(entry))
end

--Single writer for an asset's openable state. Enabling stamps the Draw
--Steel door sounds if the asset has none, so engine door toggles are
--audible on every client by default.
local function SetAssetOpenable(asset, openable)
    local ok = pcall(function()
        asset.openable = openable == true
        if openable then
            if asset.openSound == nil or asset.openSound == "" then
                asset.openSound = DOOR_OPEN_SOUND_ID
            end
            if asset.closeSound == nil or asset.closeSound == "" then
                asset.closeSound = DOOR_CLOSE_SOUND_ID
            end
        end
    end)
    return ok
end

--The preset table behind a palette entry, or nil for library/custom walls.
local function PresetForEntry(entry)
    if entry == nil or entry.kind ~= "preset" then
        return nil
    end
    return WALL_PRESETS_BY_KEY[entry.key]
end

local function EntryDisplayName(entry)
    local asset = EntryWallAsset(entry)
    if asset ~= nil then
        return asset.description or "Wall"
    end
    local preset = PresetForEntry(entry)
    if preset ~= nil then
        return preset.name
    end
    return "Unknown Wall"
end

local function AssetFields(asset)
    return {
        blocksMovement = asset.blocksMovement,
        blocksForcedMovement = asset.blocksForcedMovement,
        occludesVision = asset.occludesVision,
        occludesLight = asset.occludesLight,
        visionOneWay = asset.visionOneWay,
        movementOneWay = asset.movementOneWay,
        cover = asset.cover,
        soundOcclusion = asset.soundOcclusion,
        climbable = asset.climbable,
    }
end

local function EntryFields(entry)
    local asset = EntryWallAsset(entry)
    if asset ~= nil then
        return AssetFields(asset)
    end
    local preset = PresetForEntry(entry)
    if preset ~= nil then
        return preset.fields
    end
    return nil
end

--Short consequence readout generated from a wall's gameplay flags. Kept to
--two clauses so it fits on one line of a palette tile; presets carry a
--curated summary string instead.
local function SummarizeFields(fields)
    if fields == nil then
        return "Wall asset missing"
    end

    local result
    if fields.blocksMovement and fields.occludesVision then
        result = "Blocks all"
    elseif fields.blocksMovement then
        result = "Blocks movement"
    elseif fields.occludesVision then
        result = "Blocks sight"
    else
        result = "Passable"
    end

    local coverNames = {
        Half = "half cover",
        ThreeQuarters = "3/4 cover",
        Full = "full cover",
    }
    local coverName = coverNames[fields.cover or "None"]
    if coverName ~= nil then
        result = result .. " - " .. coverName
    end

    return result
end

local function SummarizeEntry(entry)
    if EntryIsOpenable(entry) then
        return "Openable - click icon to open/close"
    end
    local preset = PresetForEntry(entry)
    if preset ~= nil and preset.summary ~= nil then
        return preset.summary
    end
    return SummarizeFields(EntryFields(entry))
end

--A miniature of the skeleton centerline the engine draws for this wall in
--the building tools: solid = occludes light/vision, dashed = blocks movement
--only, dotted = blocks forced movement only, ">" = one-way. Mirrors the
--classification in WallMesh.BuildSkeleton.
local function CreateWallLinePreview(fields)
    local segments = {}

    local dashed = false
    local dotted = false
    if fields ~= nil and (not fields.occludesLight) and (not fields.occludesVision) then
        if fields.blocksMovement then
            dashed = true
        elseif fields.blocksForcedMovement then
            dotted = true
        end
    end

    if dashed then
        for _ = 1,7 do
            segments[#segments+1] = gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                width = 10,
                height = 3,
                hmargin = 3,
                valign = "center",
            }
        end
    elseif dotted then
        for _ = 1,12 do
            segments[#segments+1] = gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                width = 3,
                height = 3,
                hmargin = 3,
                valign = "center",
            }
        end
    else
        segments[#segments+1] = gui.Panel{
            classes = {"markupWallLine"},
            bgimage = true,
            width = "100%",
            height = 3,
            valign = "center",
        }
    end

    if fields ~= nil and (fields.visionOneWay or fields.movementOneWay) then
        segments[#segments+1] = gui.Label{
            classes = {"bold"},
            floating = true,
            halign = "center",
            valign = "center",
            text = ">",
            width = "auto",
            height = "auto",
        }
    end

    return gui.Panel{
        width = "100%",
        height = 8,
        flow = "horizontal",
        halign = "center",
        children = segments,
    }
end

--Door chips mirror what the map draws over an openable segment: the wall
--line thickening into a thin filled rectangle - the door leaf - with the
--door glyph the engine floats on top of it. "This type is the clickable
--door." The leaf is drawn filled because that is a CLOSED door, the state a
--freshly drawn door starts in; open doors draw the same rectangle hollow,
--which a static chip has no way to show.
local function CreateDoorLinePreview()
    return gui.Panel{
        width = "100%",
        height = 14,
        halign = "center",

        gui.Panel{
            width = "100%",
            height = "100%",
            flow = "horizontal",
            halign = "center",
            valign = "center",

            gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                width = "22%",
                height = 3,
                valign = "center",
            },
            gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                width = "46%",
                height = 9,
                valign = "center",
            },
            gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                width = "22%",
                height = 3,
                valign = "center",
            },
        },

        --floating so the glyph can overhang the 9px leaf the way it overhangs
        --the leaf rectangle on the map.
        gui.Panel{
            floating = true,
            width = 14,
            height = 14,
            halign = "center",
            valign = "center",
            bgimage = "game-icons/exit-door.png",
            bgcolor = "@fgColor",
        },
    }
end

--Solid chips render a filled-region preview - a bordered box of diagonal
--stripes, echoing how the tile height overlay draws solid blocks on the map -
--instead of the thin chips' line preview. This is the "fills area" marker.
local function CreateSolidBlockPreview()
    local stripes = {}
    for _ = 1,7 do
        stripes[#stripes+1] = gui.Panel{
            classes = {"markupWallLine"},
            bgimage = true,
            width = 3,
            height = 12,
            hmargin = 3,
            valign = "center",
            rotate = 45,
        }
    end

    return gui.Panel{
        width = "70%",
        height = 12,
        halign = "center",
        flow = "horizontal",
        bgimage = true,
        bgcolor = "clear",
        borderWidth = 1,
        borderColor = "@fgMuted",
        children = stripes,
    }
end

local function ApplyFieldsToWall(wall, fields)
    wall.invisible = true
    wall.blocksMovement = fields.blocksMovement == true
    wall.blocksForcedMovement = fields.blocksForcedMovement == true
    wall.occludesVision = fields.occludesVision == true
    wall.occludesLight = fields.occludesLight == true
    wall.cover = fields.cover or "None"
    wall.soundOcclusion = fields.soundOcclusion or 0
    wall.climbable = fields.climbable or "NotClimbable"
    --The base asset we duplicate from is the Core "One-Direction See-Thru"
    --wall, so both one-way flags must be reset explicitly or every markup
    --wall inherits one-way vision (and the one-way skeleton triangles).
    wall.visionOneWay = fields.visionOneWay == true
    wall.movementOneWay = false

    --Breakability is opt-in per wall type (Edit Wall -> Breakable). Set it
    --explicitly rather than letting it inherit: the Core base asset simply
    --omits solidity/breakStamina, so today it lands on the engine's
    --Unbreakable default by luck, and would change silently if that asset did.
    local stamina = fields.breakStamina or 0
    SetAssetBreakable(wall, stamina > 0, stamina)

    --Openable (door) types: engine-build gated, so this quietly does nothing
    --on a stale engine and the type behaves as a plain wall.
    SetAssetOpenable(wall, fields.openable == true)
end

--Creates a game wall asset by duplicating the invisible base and applying
--the given name + gameplay fields. Returns the new guid, or nil on failure.
local function CreateMarkupWallAsset(name, fields)
    if assets.walls[BASE_INVISIBLE_WALL_ID] == nil then
        dmhub.Debug("MARKUP:: base invisible wall asset is not available in this game")
        return nil
    end

    local guid = assets:DuplicateWall(BASE_INVISIBLE_WALL_ID)
    if guid == nil then
        return nil
    end

    local wall = assets.walls[guid]
    wall.description = name
    ApplyFieldsToWall(wall, fields)
    wall:Upload()
    return guid
end

--============================================================================
--Wall height helpers. The markup height stepper drives the same settings the
--Building editor uses, which dmhub.GetWallHeight (Terrain.lua) already reads,
--so per-placement heights stamp onto operations with no extra plumbing.
--============================================================================

local function GetWallHeightSetting()
    if dmhub.GetSettingValue("building:specifywallheight") then
        return dmhub.GetSettingValue("building:wallheightvalue")
    end
    return nil
end

local function SetWallHeightSetting(height)
    if height == nil then
        dmhub.SetSettingValue("building:specifywallheight", false)
    else
        dmhub.SetSettingValue("building:specifywallheight", true)
        dmhub.SetSettingValue("building:wallheightvalue", height)
    end
end

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
--    playerVisible = false,          -- players see the overlay stripes
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
--Runtime: ZoneManager (below) builds one AuraInstance per zone from the
--records and hands them to the engine via dmhub.GetMapAuras (re-polled on
--every aura rebuild). The keyword's difficultTerrain/water/concealment flags
--ride the aura into tile rules, its CharacterModifiers reach creatures via
--the normal FillModifiersFromAuras path, and the height field drives the
--engine's vertical-overlap test (a height-2 Lava zone burns a ground token
--and ignores a flyer at altitude 3).
--
--Rendering: dmhub.GetMarkupZones feeds the tile height overlay, which draws
--each zone as diagonal stripes + a name label. DM-only unless the zone is
--marked playerVisible.
--
--This file loads before EnvironmentalKeyword.lua (main.lua order), so every
--reference to the EnvironmentalKeyword global is runtime + rawget-guarded.
--============================================================================

--Built-in zone types (design: built-ins ARE Environmental Keywords - ship as
--presets that lazily materialize into the environmentalKeywords table on
--first use, exactly like wall presets materialize wall assets). Colors match
--the tile height overlay's built-in stripe colors so the readout stays
--consistent with un-zoned tiles that carry the same rules.
local ZONE_PRESETS = {
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

local ZONE_PRESETS_BY_KEY = {}
for _,preset in ipairs(ZONE_PRESETS) do
    ZONE_PRESETS_BY_KEY[preset.key] = preset
end

--Fallback chip/stripe colors for keywords whose icon color is white/unset.
local ZONE_FALLBACK_COLORS = {
    "#d94a3d", "#7a3dd9", "#3dd9c8", "#d9b83d", "#d93d9e", "#4ad93d",
}

local ZONE_ANGLE_A = math.pi * 0.25
local ZONE_ANGLE_B = math.pi * 0.75

--Per-map zone palette, exactly like the wall palette: ';'-joined tokens.
--  "preset:<key>"            built-in not yet materialized as a keyword
--  "preset:<key>:<id>"       built-in materialized as keyword <id>
--  "keyword:<id>"            keyword added from the library / created new
--  "none"                    explicitly empty
local DEFAULT_ZONE_PALETTE = "preset:difficult;preset:water;preset:concealing"

local g_zonePaletteSetting = setting{
    id = "markup:zonepalette",
    description = "Map Markup Zone Palette",
    storage = "map",
    default = DEFAULT_ZONE_PALETTE,
}

local function ParseZonePalette()
    local result = {}
    local str = g_zonePaletteSetting:Get()
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
    g_zonePaletteSetting:Set(SerializeZonePalette(entries))
end

local ENVIRONMENTAL_KEYWORDS_TABLE = "environmentalKeywords"

local function GetKeywordTable()
    return dmhub.GetTable(ENVIRONMENTAL_KEYWORDS_TABLE) or {}
end

local function GetKeyword(keywordid)
    if keywordid == nil then
        return nil
    end
    return GetKeywordTable()[keywordid]
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
    if type(color) == "string" and color ~= "" and string.lower(color) ~= "white"
        and string.lower(color) ~= "#ffffff" and string.lower(color) ~= "#ffffffff" then
        return color
    end

    local hash = 0
    for i = 1, #(keywordid or "") do
        hash = (hash * 31 + string.byte(keywordid, i)) % 65536
    end
    return ZONE_FALLBACK_COLORS[(hash % #ZONE_FALLBACK_COLORS) + 1]
end

--Effective rule flags a keyword contributes to tiles. try_get throughout:
--older serialized keywords predate some fields, and game-typed instances
--raise on unknown-field reads.
local function KeywordFlags(kw)
    local flags = { difficultTerrain = false, water = false, concealment = false }
    if kw == nil then
        return flags
    end
    pcall(function()
        flags.difficultTerrain = kw:try_get("difficultTerrain", false) == true
        flags.water = kw:try_get("water", false) == true
        flags.concealment = kw:try_get("concealment", false) == true
    end)
    return flags
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

--Finds a keyword id by (case-insensitive) name, or nil.
local function FindKeywordIdByName(name)
    if name == nil or name == "" then
        return nil
    end
    for k,kw in unhidden_pairs(GetKeywordTable()) do
        if string.lower(kw.name or "") == string.lower(name) then
            return k
        end
    end
    return nil
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

    dmhub.SetAndUploadTableItem(ENVIRONMENTAL_KEYWORDS_TABLE, kw)

    if GetKeyword(kw.guid) == nil then
        --table-creation race: the item isn't locally visible yet. Zone
        --records created against this id heal by keywordName once the
        --table settles.
        dmhub.Debug("MARKUP:: keyword '" .. preset.name .. "' not yet visible after upload (table creation race); records will heal by name")
    end

    return kw.guid
end

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
local SURFACE_COLORS = {
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
local SURFACE_FALLBACK_COLOR = "#9a9a9a"

local function SurfaceColor(surfaceId)
    return SURFACE_COLORS[surfaceId] or SURFACE_FALLBACK_COLOR
end

--The map's default footstep surface: what unpainted tiles (surfaceType 0)
--sound like. Read at playback time by AudioMain.TokenMovingOnPath and
--creature.PlayLandingFootstep via dmhub.GetSettingValue. Map storage: DM
--writes it, it syncs to every client (players play their own footsteps),
--and it changes with the map. 0 = no default (the engine's Generic).
local g_footstepDefaultSetting = setting{
    id = "markup:footstepdefault",
    description = "Map Default Footsteps",
    storage = "map",
    default = 0,
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
--ZoneManager: the cache of zone records resolved against their keywords,
--rebuilt whenever the records (dmhub.markupZonesSeq), the map, or the
--compendium tables change. Feeds both engine hooks.
--============================================================================

--Engine support probe: the zone storage API, the GetMapAuras hook and the
--overlay feed all shipped in the same engine build as dmhub.markupZonesSeq.
local m_zoneEngineSupport = nil
local function ZonesSupported()
    if m_zoneEngineSupport == nil then
        local ok = pcall(function()
            return dmhub.markupZonesSeq
        end)
        m_zoneEngineSupport = ok
    end
    return m_zoneEngineSupport
end

--Forward declarations: assigned in the panel-state section below. Used by the
--overlay feed's panel-open backstop and its mode report.
local m_markupHudRef = function() return nil end
local m_markupModeRef = function() return "walls" end

local m_zoneCache = nil            --list of resolved zone entries, all floors
local m_surfaceCache = nil         --list of resolved footstep-surface entries, all floors
local m_zoneCacheSeq = nil
local m_zoneCacheMapid = nil
local m_zoneCacheTablesGen = nil
local m_zoneTablesGen = 0          --bumped on refreshTables (keyword edits)
local m_zoneRevision = 0           --bumped on every cache rebuild; overlay cache key
local m_zoneAuraInstances = {}     --what dmhub.GetMapAuras returns
local m_zoneOverlayZones = {}      --GetMarkupZones list: the rules zones
local m_surfaceOverlayZones = {}   --footstep-surface region overlay entries
local m_footstepsOverlayZones = {} --GetMarkupZones list in footsteps mode:
                                   --the surface regions + water rules zones
local m_lastFeedFootstepsMode = nil --last footstepsMode the feed reported; a flip
                                   --bumps m_zoneRevision so old and new engine
                                   --builds alike rebuild the overlay mesh
local m_zonePanelOpen = false      --tracked from the panel's show/hide events

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
local ZONE_AREA_NAMES = {
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

    return ZONE_AREA_NAMES[row][col]
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

    --Deep-copy the keyword's modifiers: GetModifiers stamps transient symbol
    --state onto the modifier objects, and the table's own copies are shared
    --with the compendium editor and every other zone.
    local modifiers = {}
    pcall(function()
        local kwModifiers = entry.keywordInfo:try_get("modifiers")
        if kwModifiers ~= nil then
            for _,m in ipairs(kwModifiers) do
                modifiers[#modifiers+1] = dmhub.DeepCopy(m)
            end
        end
    end)

    local auraDef = auraType.Create{
        name = entry.name,
        applyto = "all",
        modifiers = modifiers,
        difficult_terrain = entry.flags.difficultTerrain,
        concealment = entry.flags.concealment,
        water = entry.flags.water,
    }
    if entry.height ~= nil then
        auraDef.auraHeight = entry.height
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

    --No casterid, no tokenAttached, no duration: a permanent, floor-scoped,
    --uncontrolled aura. guid = zoneid so triggers/entered-tracking key stably.
    return auraInstanceType.new{
        aura = auraDef,
        guid = entry.zoneid,
        name = entry.name,
        iconid = iconid,
        display = display,
        area = shape,
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

local function RebuildZoneCache()
    m_zoneCache = {}
    m_surfaceCache = {}
    m_zoneAuraInstances = {}
    m_zoneOverlayZones = {}
    m_surfaceOverlayZones = {}
    m_footstepsOverlayZones = {}

    local map = game.currentMap
    if map == nil then
        return
    end

    for _,floor in ipairs(map.floors or {}) do
        local zones = nil
        local floorIndex = nil
        pcall(function()
            zones = floor.markupZones
            floorIndex = floor.floorIndex
        end)

        --floorIndex is -1 when the floor isn't currently visible (e.g. the
        --title screen); keep the records in the cache (the zone list needs
        --them) and skip only the aura/overlay build below.
        if zones ~= nil and floorIndex ~= nil then
            local floorid = floor.floorid
            for zoneid,record in pairs(zones) do
                if type(record) == "table" and record.category == "surface" then
                    local surfaceId = math.floor(tonumber(record.surface) or 0)
                    local surfaceInfo = SurfaceInfoById(surfaceId)
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

                    m_surfaceCache[#m_surfaceCache+1] = {
                        zoneid = zoneid,
                        floorid = floorid,
                        floorIndex = floorIndex,
                        surface = surfaceId,
                        name = name,
                        locs = locs,
                        patternColor = SurfaceColor(surfaceId),
                    }
                elseif type(record) == "table" and record.category == nil then
                    --resolve the keyword by id, healing dead ids by stored
                    --name (ids can be lost to the objectTable-creation race;
                    --see MaterializeZonePreset). The healed id flows back
                    --into the record on the zone's next write.
                    local kwId = record.keyword
                    local kw = GetKeyword(kwId)
                    if kw == nil and record.keywordName ~= nil then
                        local healedId = FindKeywordIdByName(record.keywordName)
                        if healedId ~= nil then
                            kwId = healedId
                            kw = GetKeyword(healedId)
                        end
                    end
                    local kwName = record.keywordName
                    if kw ~= nil and kw.name ~= nil then
                        kwName = kw.name
                    end
                    local pattern = record.pattern or {}
                    local locs = {}
                    for _,l in ipairs(record.locs or {}) do
                        if type(l) == "table" and l.x ~= nil and l.y ~= nil then
                            locs[#locs+1] = { x = math.floor(l.x), y = math.floor(l.y) }
                        end
                    end

                    m_zoneCache[#m_zoneCache+1] = {
                        zoneid = zoneid,
                        floorid = floorid,
                        floorIndex = floorIndex,
                        name = record.name or "Zone",
                        keywordid = kwId,
                        keywordName = kwName,
                        keywordInfo = kw,
                        flags = KeywordFlags(kw),
                        locs = locs,
                        altitude = record.altitude or 0,
                        height = record.height,
                        playerVisible = record.playerVisible == true,
                        patternColor = pattern.color or KeywordColor(kwId, kw),
                        patternAngle = pattern.angle or ZONE_ANGLE_A,
                        ord = record.ord or 0,
                    }
                end
            end
        end
    end

    table.sort(m_surfaceCache, function(a, b)
        if a.floorid ~= b.floorid then
            return a.floorid < b.floorid
        end
        return a.surface < b.surface
    end)

    --Surface overlay entries go in their own list: the feed hands the engine
    --the rules zones normally, or - on the Footsteps tab - the footstep
    --surface regions plus the water rules zones (assembled into
    --m_footstepsOverlayZones below; see dmhub.GetMarkupZones). Surfaces
    --render in the normal zone-stripe style, distinguished by the footprints
    --icon on their labels; the stripe angle alternates by family so adjacent
    --regions of similar colors still read as distinct.
    for _,entry in ipairs(m_surfaceCache) do
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

            local angle = ZONE_ANGLE_A
            if entry.surface % 2 == 0 then
                angle = ZONE_ANGLE_B
            end

            m_surfaceOverlayZones[#m_surfaceOverlayZones+1] = {
                locs = locsUserdata,
                color = ZoneOverlayColor(entry.patternColor),
                angleRadians = angle,
                label = entry.name,
                labelIcon = "phosphor/footprints-fill.png",
                playerVisible = false,
                floorIndex = entry.floorIndex,
            }

            local instance = BuildSurfaceAuraInstance(entry)
            if instance ~= nil then
                m_zoneAuraInstances[#m_zoneAuraInstances+1] = instance
            end
        end
    end

    table.sort(m_zoneCache, function(a, b)
        if a.floorid ~= b.floorid then
            return a.floorid < b.floorid
        end
        if a.ord ~= b.ord then
            return a.ord < b.ord
        end
        return a.zoneid < b.zoneid
    end)

    for _,entry in ipairs(m_zoneCache) do
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

            m_zoneOverlayZones[#m_zoneOverlayZones+1] = {
                locs = locsUserdata,
                color = ZoneOverlayColor(entry.patternColor),
                angleRadians = entry.patternAngle,
                label = ZoneOverlayLabel(entry),
                playerVisible = entry.playerVisible,
                difficultTerrain = entry.flags.difficultTerrain,
                water = entry.flags.water,
                concealment = entry.flags.concealment,
                floorIndex = entry.floorIndex,
            }

            local instance = BuildZoneAuraInstance(entry)
            if instance ~= nil then
                m_zoneAuraInstances[#m_zoneAuraInstances+1] = instance
            end
        end
    end

    --Footsteps-mode feed list: the surface regions plus any WATER rules
    --zones. A water tile plays water sounds over any painted footstep
    --surface, so the DM needs to see water while painting footsteps. Water
    --zones go last so they draw over surface stripes where the two overlap
    --(the water sound is what actually wins there).
    for _,overlayZone in ipairs(m_surfaceOverlayZones) do
        m_footstepsOverlayZones[#m_footstepsOverlayZones+1] = overlayZone
    end
    for _,overlayZone in ipairs(m_zoneOverlayZones) do
        if overlayZone.water then
            m_footstepsOverlayZones[#m_footstepsOverlayZones+1] = overlayZone
        end
    end
end

local function EnsureZoneCache()
    if not ZonesSupported() then
        return
    end

    local seq = dmhub.markupZonesSeq
    local mapid = game.currentMapId
    if m_zoneCache ~= nil and seq == m_zoneCacheSeq and mapid == m_zoneCacheMapid
        and m_zoneCacheTablesGen == m_zoneTablesGen then
        return
    end

    m_zoneCacheSeq = seq
    m_zoneCacheMapid = mapid
    m_zoneCacheTablesGen = m_zoneTablesGen
    m_zoneRevision = m_zoneRevision + 1
    RebuildZoneCache()
end

--The engine hooks. Assigned inside pcall: on a stale engine build these
--dmhub properties don't exist and assignment raises - zones then simply
--don't register or render, and the panel shows its needs-an-engine-build
--notice. We own these hooks outright (no chaining like GetSelectedWall):
--reassignment on reload just replaces our own stale closure.
pcall(function()
    dmhub.GetMapAuras = function()
        EnsureZoneCache()
        return m_zoneAuraInstances
    end
end)

--The show/hide event bookkeeping can go stale: a saved dock layout can build
--the panel content without ever showing it, and an orphaned/discarded panel
--gets no hide/destroy events. Backstop with the live panel: open means the
--content exists, is alive, and is actually parented into the UI.
local function MarkupPanelIsOpen()
    if not m_zonePanelOpen then
        return false
    end
    local hud = m_markupHudRef()
    if hud == nil or not hud.valid then
        return false
    end
    local ok, parent = pcall(function() return hud.parent end)
    if not ok or parent == nil then
        return false
    end
    return true
end

pcall(function()
    dmhub.GetMarkupZones = function()
        EnsureZoneCache()
        local panelOpen = MarkupPanelIsOpen()
        local mode = m_markupModeRef()

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
        if footstepsMode ~= m_lastFeedFootstepsMode then
            m_lastFeedFootstepsMode = footstepsMode
            m_zoneRevision = m_zoneRevision + 1
        end

        local zones = m_zoneOverlayZones
        if footstepsMode then
            zones = m_footstepsOverlayZones
        end

        return {
            panelOpen = panelOpen,
            --The Zones tab also lights up the overlay's built-in terrain-rule
            --striping (water/difficult/concealment/climbable), so the user
            --sees existing terrain conditions alongside the zones they are
            --painting - without needing the tileheight:overlay preference.
            terrainZones = panelOpen and mode == "zones",
            footstepsMode = footstepsMode,
            revision = m_zoneRevision,
            zones = zones,
        }
    end
end)

--Keyword edits (refreshTables) change what zone auras contribute: invalidate
--the cache, and if this map actually has zones, rebuild the aura index so
--the changes reach creatures without waiting for an unrelated rebuild.
dmhub.RegisterEventHandler("refreshTables", function()
    m_zoneTablesGen = m_zoneTablesGen + 1
    if not ZonesSupported() then
        return
    end
    EnsureZoneCache()
    if m_zoneCache ~= nil and #m_zoneCache > 0 then
        pcall(function()
            dmhub.RefreshMapAuras()
        end)
    end
end)

--============================================================================
--Zone editing operations (paint / erase / create / update / delete).
--============================================================================

local function ZoneLocKey(x, y)
    return string.format("%d,%d", x, y)
end

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

    if overrides.name ~= nil then record.name = overrides.name end
    if overrides.playerVisible ~= nil then record.playerVisible = overrides.playerVisible end

    return record
end

--Zone entries on the given floor, in list order.
local function ZonesOnFloor(floorid)
    EnsureZoneCache()
    local result = {}
    for _,entry in ipairs(m_zoneCache or {}) do
        if entry.floorid == floorid then
            result[#result+1] = entry
        end
    end
    return result
end

local function FindZoneEntry(zoneid)
    EnsureZoneCache()
    for _,entry in ipairs(m_zoneCache or {}) do
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

    local kw = GetKeyword(keywordid)
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

    --stripe angle alternates per zone on the floor so neighbouring zones of
    --similar colors still read as distinct regions.
    local angle = ZONE_ANGLE_A
    if #floorZones % 2 == 1 then
        angle = ZONE_ANGLE_B
    end

    local color = KeywordColor(keywordid, kw)
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
        playerVisible = false,
        pattern = {
            color = color,
            angle = angle,
        },
        ord = maxOrd + 1,
    }

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
        local key = ZoneLocKey(l.x, l.y)
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
                    ZoneLocKey(cell.x + 1, cell.y),
                    ZoneLocKey(cell.x - 1, cell.y),
                    ZoneLocKey(cell.x, cell.y + 1),
                    ZoneLocKey(cell.x, cell.y - 1),
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

--Writes a zone's new loc set, automatically separating non-contiguous
--regions into their own zone records: the largest region keeps the zone's
--identity (id, name, settings), each additional region becomes a new zone
--of the same type and settings named "<Base> 2", "<Base> 3", ... An empty
--set deletes the zone. Callers wrap multi-zone operations in a transaction.
local function WriteZoneLocsSplitting(floor, entry, newLocs)
    local components = SplitContiguousComponents(newLocs)
    if #components == 0 then
        --NOTE: a stale m_zoneTargetId pointing at the removed zone is
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
    if not ZonesSupported() then
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
--Footstep-surface editing operations (paint / erase). Surfaces are exclusive
--per tile: painting one family removes those tiles from every other family.
--No naming or contiguity machinery - one record per family per floor.
--============================================================================

local function SurfacesOnFloor(floorid)
    EnsureZoneCache()
    local result = {}
    for _,entry in ipairs(m_surfaceCache or {}) do
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

local m_paintedSurfaceLookup = nil    --floorid -> { "x,y" -> surface id }
local m_paintedSurfaceLookupRev = nil

MapMarkupFootsteps = {
    --Returns the painted footstep-surface family id at a tile, or nil when no
    --footstep region is painted there.
    GetPaintedSurfaceAt = function(floorid, x, y)
        if floorid == nil or x == nil or y == nil or not ZonesSupported() then
            return nil
        end
        EnsureZoneCache()

        if m_paintedSurfaceLookup == nil or m_paintedSurfaceLookupRev ~= m_zoneRevision then
            m_paintedSurfaceLookupRev = m_zoneRevision
            m_paintedSurfaceLookup = {}
            for _,entry in ipairs(m_surfaceCache or {}) do
                local floorMap = m_paintedSurfaceLookup[entry.floorid]
                if floorMap == nil then
                    floorMap = {}
                    m_paintedSurfaceLookup[entry.floorid] = floorMap
                end
                for _,l in ipairs(entry.locs) do
                    floorMap[ZoneLocKey(l.x, l.y)] = entry.surface
                end
            end
        end

        local floorMap = m_paintedSurfaceLookup[floorid]
        if floorMap == nil then
            return nil
        end
        return floorMap[ZoneLocKey(x, y)]
    end,
}

--============================================================================
--Zone flash: clicking a row in the zones list pans the camera to the zone
--and briefly pulses a highlight over its tiles so the user can spot it.
--============================================================================

local m_zoneFlashMarks = nil
local m_zoneFlashGen = 0

local function ClearZoneFlash()
    if m_zoneFlashMarks ~= nil then
        pcall(function()
            m_zoneFlashMarks:Destroy()
        end)
        m_zoneFlashMarks = nil
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
    m_zoneFlashGen = m_zoneFlashGen + 1
    local gen = m_zoneFlashGen

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
        if (mod ~= nil and mod.unloaded) or gen ~= m_zoneFlashGen then
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
                m_zoneFlashMarks = marks
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
--Panel state + the engine-polled selection hook.
--============================================================================

local m_markupHud = nil
m_markupHudRef = function() return m_markupHud end
local m_mode = "walls"
m_markupModeRef = function() return m_mode end
local m_selectedIndex = 1
local m_paletteEntries = {}
--"rectangle" / "line" / "free" draw walls through the engine building tools,
--and "points" drives the engine's wall vertex-editing tool the same way;
--"erase" / "delete" and the solid shape tools are custom map tools driven
--from this panel. Reset to each mode's first tool when the panel is built.
local m_toolId = "rectangle"
--Draw mode, independent of which wall type is selected: false draws thin
--walls (barriers on a tile boundary), true draws area-filling solid blocks
--of the SAME wall type. Toggled by the Thin/Solid control by the tool strip.
local m_solidMode = false

--Zones mode state: the selected zone-type chip (index into
--m_zonePaletteEntries), the active zone tool, and the target zone new
--strokes merge into (nil = auto-pick / create by selected type).
local m_zonePaletteEntries = {}
local m_zoneSelectedType = 1
local m_zoneToolId = "zonerect"
local m_zoneTargetId = nil

--Footsteps mode state: the selected surface family (AudioSurfaceTypes id)
--and the active paint tool.
local m_footstepSelected = 1
local m_footstepToolId = "footrect"

--============================================================================
--Props mode: preset invisible gameplay objects (lights, mounts, teleporters,
--stairways) placed on the map. Every prop is one invisible object instance
--spawned from the Core "Invisible Light Source" asset, tagged with keywords
--("markup" plus "markup:<type>") and locked so it is inert everywhere except
--this panel. The engine's object-editing filter (dmhub.GetObjectEditingFilter,
--needs an engine build) makes only the selected type visible and draggable
--while the Props tab is focused.
--============================================================================

--The Core asset every prop spawns from: Core + Light components, invisible to
--players. Non-light prop types remove/replace the Light component on the
--spawned instance, so no additional Core assets are needed.
local PROP_BASE_OBJECT_ID = "-MGBXtOnKAXNhhLK89_9"

--Stamped on every placed prop, alongside the per-type "markup:<type>" tag.
local MARKUP_PROP_KEYWORD = "markup"

local PROP_TYPES = {
    {
        id = "light",
        text = "Light",
        icon = "phosphor/lightbulb-fill.png",
        implemented = true,
        summary = "An invisible light source: players see the light it casts, never the marker.",
    },
    {
        id = "mount",
        text = "Mount",
        icon = "phosphor/armchair-fill.png",
        implemented = false,
        summary = "A spot a token can move onto and occupy - a chair, bench, or perch drawn into the map art. (Coming soon.)",
    },
    {
        id = "teleporter",
        text = "Teleporter",
        icon = "phosphor/arrows-left-right-fill.png",
        implemented = false,
        summary = "A linked pair: a token entering one end comes out at the other. (Coming soon.)",
    },
    {
        id = "stairway",
        text = "Stairway",
        icon = "phosphor/stairs-fill.png",
        implemented = false,
        summary = "Connects this floor to the floor above. (Coming soon.)",
    },
}

--Props mode state: the selected prop type (id into PROP_TYPES), the placed
--prop currently bound to the property editors (clicked on the map), and
--session defaults stamped onto newly placed props. The defaults track the
--last values edited, so consecutive placements inherit them.
local m_props = {
    selected = "light",
    editingId = nil,
    defaults = {
        light = { color = "#ffffff", intensity = 0.5, radius = 4, flicker = 0 },
    },
}

--The props engine half (the object-editing filter) needs an engine build. A
--stale build shows a muted message instead of the props UI - placing props it
--cannot show or manipulate would strand them invisibly on the map.
--
--GOTCHA: the callback itself CANNOT be probed. Unknown properties on the dmhub
--bridge read as nil AND accept writes silently (verified live 2026-07-28), so
--both "read it" and "assign it, read it back" succeed on a stale engine. Hence
--the dedicated supportsObjectEditingFilter probe property, the same pattern as
--floor.supportsSolidOperations. pcall + == true: nil on older builds.
local function PropsSupported()
    local supported = false
    pcall(function()
        supported = dmhub.supportsObjectEditingFilter == true
    end)
    return supported
end

--Props mode's half of the engine's object-editing filter poll. Non-nil makes
--objects tagged with the returned keyword visible/selectable/draggable (and
--everything else inert) - so it must be non-nil only while the Props tab is
--focused and a type is selected.
local function GetMarkupObjectEditingFilter()
    if m_mode ~= "props" or m_props.selected == nil then
        return nil
    end

    if m_markupHud == nil or not m_markupHud.valid or not gui.ChildHasFocus(m_markupHud) then
        return nil
    end

    return "markup:" .. m_props.selected
end

--Props mode's half of the engine's object-selection callback: when the Props
--tab is focused and everything selected is a markup prop, bind the selection
--to the panel's property editors and suppress the generic object-properties
--dialog. The engine passes LuaObjectInstance userdata (not id strings,
--despite the stub). Returns true when the selection was consumed.
local function MarkupHandleObjectsSelected(objects)
    if m_mode ~= "props" then
        return false
    end

    if m_markupHud == nil or not m_markupHud.valid or not gui.ChildHasFocus(m_markupHud) then
        return false
    end

    local valid = {}
    for _,obj in ipairs(objects or {}) do
        if obj.valid then
            valid[#valid+1] = obj
        end
    end

    if #valid == 0 then
        --selection cleared: unbind our editors, but let the generic dialog
        --see the clear too in case it is open.
        if m_props.editingId ~= nil then
            m_props.editingId = nil
            m_markupHud:FireEventTree("refreshprops")
        end
        return false
    end

    for _,obj in ipairs(valid) do
        local kw = obj.keywords
        if kw == nil or kw[MARKUP_PROP_KEYWORD] == nil then
            return false
        end
    end

    m_props.editingId = valid[1].objid
    m_markupHud:FireEventTree("refreshprops")
    return true
end

--Elevation editing is a patron feature: ElevationPanel.lua only registers the
--Elevation Editor dock panel when patronTier > 0, and the engine returns a nil
--heightEditingInfo for non-patrons even while isHeightEditingEnabled is true.
--Gate our clone the same way so we can never put the engine in that state.
local function ElevationSupported()
    return dmhub.patronTier > 0
end

--Elevation mode's half of the engine's height-editing poll. The engine calls
--dmhub.GetHeightEditingInfo every frame; non-nil turns height painting on and
--carries the brush parameters. Same shape (and the same settings) as
--ElevationPanel.lua's version, focus-gated the same way -- the wrapper at the
--bottom of this file chains the two so whichever panel has focus wins.
local function GetMarkupHeightEditingInfo()
    if m_mode ~= "elevation" or not ElevationSupported() then
        return nil
    end

    if m_markupHud == nil or (not m_markupHud.valid) or (not gui.ChildHasFocus(m_markupHud)) then
        return nil
    end

    return {
        height = dmhub.GetSettingValue("heightmap:height"),
        directional = dmhub.GetSettingValue("heightmap:gradient") == "slope",
        opacity = dmhub.GetSettingValue("heightmap:opacity"),
        blend = dmhub.GetSettingValue("heightmap:blend"),
    }
end

local function GetMarkupSelectedWall()
    if m_markupHud == nil or not m_markupHud.valid then
        return nil
    end

    --The dock ancestor is optional: panel content can be hosted outside the
    --dock (e.g. the document system's PanelDocument bridge), so only use it
    --for the highlight, never as a gate.
    local dockPanel = m_markupHud:FindParentWithClass("dockablePanel")

    --erase/delete are custom map tools, not wall drawing: publish no wall so
    --the engine building tools stay inactive while they run.
    if m_mode ~= "walls" or m_toolId == "erase" or m_toolId == "delete" or not gui.ChildHasFocus(m_markupHud) then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    local entry = m_paletteEntries[m_selectedIndex or 0]

    --Solid draw mode publishes no wall: solid strokes run through custom map
    --tools + ExecutePolygonOperation{solid=true}, not the engine building
    --tools. Publishing here would let the building tools draw THIN walls
    --while the panel is in Solid mode.
    if m_solidMode then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    local guid = nil
    if entry ~= nil then
        guid = entry.guid
    end

    if guid == nil or assets.walls[guid] == nil then
        --The points tool edits existing walls, so the published wall is only
        --the engine's activation token: fall back to the base invisible wall
        --when the palette selection is unmaterialized (fresh preset chips have
        --no asset until first clicked). Gated on the engine tool actually
        --being "points" so the fallback can never leak into wall DRAWING.
        if m_toolId == "points" and dmhub.GetSettingValue("buildingtool") == "points" then
            if assets.walls[BASE_INVISIBLE_WALL_ID] ~= nil then
                guid = BASE_INVISIBLE_WALL_ID
            end
        end
    end

    if guid == nil or assets.walls[guid] == nil then
        if dockPanel ~= nil then
            dockPanel:SetClass("highlightPanel", false)
        end
        return nil
    end

    if dockPanel ~= nil then
        dockPanel:SetClass("highlightPanel", true)
    end
    return guid
end

--============================================================================
--Edit dialog for markup walls: the gameplay fields only, none of the art
--fields that are meaningless on an invisible wall.
--============================================================================

local function ShowMarkupWallDialog(wallid)
    local asset = assets.walls[wallid]
    if asset == nil then
        return
    end

    local originalValues = {
        description = asset.description,
        blocksMovement = asset.blocksMovement,
        blocksForcedMovement = asset.blocksForcedMovement,
        occludesVision = asset.occludesVision,
        occludesLight = asset.occludesLight,
        visionOneWay = asset.visionOneWay,
        cover = asset.cover,
        soundOcclusion = asset.soundOcclusion,
        climbable = asset.climbable,
        solidity = asset.solidity,
        breakStamina = asset.breakStamina,
        rubbleKeyword = asset.rubbleKeyword,
        rubbleTerrainId = asset.rubbleTerrainId,
    }

    local RevertChanges = function()
        asset.description = originalValues.description
        asset.blocksMovement = originalValues.blocksMovement
        asset.blocksForcedMovement = originalValues.blocksForcedMovement
        asset.occludesVision = originalValues.occludesVision
        asset.occludesLight = originalValues.occludesLight
        asset.visionOneWay = originalValues.visionOneWay
        asset.cover = originalValues.cover
        asset.soundOcclusion = originalValues.soundOcclusion
        asset.climbable = originalValues.climbable
        asset.solidity = originalValues.solidity
        asset.breakStamina = originalValues.breakStamina
        asset.rubbleKeyword = originalValues.rubbleKeyword
        asset.rubbleTerrainId = originalValues.rubbleTerrainId
        if originalValues.openable ~= nil then
            pcall(function()
                asset.openable = originalValues.openable
                asset.openSound = originalValues.openSound
                asset.closeSound = originalValues.closeSound
            end)
        end
    end

    --Breakability working state. The material is derived from the stamina on
    --open (see BreakMaterialForStamina) and both live here until Save, so
    --Cancel reverts cleanly like every other field in this dialog.
    local breakable = AssetIsBreakable(asset)
    local breakStamina = asset.breakStamina or 0
    if breakable and breakStamina <= 0 then
        breakStamina = DEFAULT_BREAK_STAMINA
    end
    local breakMaterialId = BreakMaterialForStamina(breakStamina)

    --Openable (door) state lives on the WALL ASSET (WallAsset.openable, plus
    --the open/close sounds SetAssetOpenable stamps). Applied live like every
    --other field: Save uploads, Cancel reverts. Needs the engine build - the
    --checkbox only shows when the asset supports the field.
    local canBeOpenable = OpenableWallsSupported()
    local openable = AssetIsOpenable(asset)
    if canBeOpenable then
        originalValues.openable = openable
        pcall(function()
            originalValues.openSound = asset.openSound
            originalValues.closeSound = asset.closeSound
        end)
    end

    --Pushes the working break state onto the asset. Called on every change so
    --the live asset always matches the controls; Save uploads, Cancel reverts.
    local ApplyBreakToAsset = function()
        SetAssetBreakable(asset, breakable, breakStamina)
    end

    local dialogPanel
    dialogPanel = gui.Panel{
        id = "MarkupWallDialog",
        classes = {"framedPanel"},
        width = 460,
        height = "auto",
        pad = 16,
        borderBox = true,
        flow = "vertical",
        styles = ThemeEngine.MergeStyles{
            Styles.Panel,
            Styles.Form,
            {
                classes = {"formStackedRow"},
                width = "96%",
            },
            {
                classes = {"slider"},
                height = 30,
            },
            {
                classes = {"sliderLabel"},
                fontSize = 14,
            },
            {
                classes = {"formCheck"},
                lmargin = 8,
                vmargin = 2,
            },
        },

        children = {
            gui.Label{
                classes = {"dialogTitle"},
                text = "Edit Markup Wall",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = asset.description or "",
                    change = function(element)
                        asset.description = element.text
                    end,
                },
            },

            gui.Check{
                classes = {"formCheck", cond(canBeOpenable, nil, "collapsed")},
                text = "Openable (Door)",
                tooltip = "When set, every wall segment drawn with this type is a door: a clickable icon floats over it, and opening it disables the whole segment's blocking until it is closed again. The Director can right-click the icon to lock the door.",
                value = openable,
                change = function(element)
                    openable = element.value
                    SetAssetOpenable(asset, openable)
                    dialogPanel:FireEventTree("refreshopenable")
                end,
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "While closed, the door blocks exactly like this wall type (all the settings below apply). Opening it via its icon disables the drawn segment entirely; the sound plays for everyone. The Director always sees door icons and can right-click them to lock or unlock; players can use a door within 2 tiles and line of sight.",
                width = "96%",
                height = "auto",
                halign = "center",
                vmargin = 2,
                refreshopenable = function(element)
                    element:SetClass("collapsed", not openable)
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Movement",
                value = asset.blocksMovement == true,
                change = function(element)
                    asset.blocksMovement = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Forced Movement",
                value = asset.blocksForcedMovement == true,
                change = function(element)
                    asset.blocksForcedMovement = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Vision",
                value = asset.occludesVision == true,
                change = function(element)
                    asset.occludesVision = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Blocks Light",
                value = asset.occludesLight == true,
                change = function(element)
                    asset.occludesLight = element.value
                end,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "One-Way Vision & Light",
                tooltip = "When set, the wall only blocks vision and light from one side. The side depends on the direction the wall was drawn in.",
                value = asset.visionOneWay == true,
                change = function(element)
                    asset.visionOneWay = element.value
                end,
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Cover:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = asset.cover or "None",
                    options = {
                        {
                            id = "None",
                            text = "No Cover",
                        },
                        {
                            id = "Half",
                            text = "Half Cover",
                        },
                        {
                            id = "ThreeQuarters",
                            text = "Three-Quarters Cover",
                        },
                        {
                            id = "Full",
                            text = "Full Cover",
                        },
                    },
                    change = function(element)
                        asset.cover = element.idChosen
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Climbable:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = asset.climbable or "NotClimbable",
                    options = {
                        {
                            id = "NotClimbable",
                            text = "Not Climbable",
                        },
                        {
                            id = "ClimbersOnly",
                            text = "Climbable (Climbers Only)",
                        },
                        {
                            id = "AllCreatures",
                            text = "Climbable (All Creatures)",
                        },
                    },
                    change = function(element)
                        asset.climbable = element.idChosen
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Blocks Sounds:",
                },
                gui.Slider{
                    value = asset.soundOcclusion or 0,
                    minValue = 0,
                    maxValue = 1,
                    sliderWidth = 240,
                    labelWidth = 50,
                    events = {
                        change = function(element)
                            asset.soundOcclusion = element.value
                        end,
                    },
                },
            },

            --Breakable: a creature shoved into this wall with enough force
            --smashes through it. Applies to thin walls and solid blocks
            --alike. The material rows below stay hidden until it is on.
            gui.Check{
                classes = {"formCheck"},
                text = "Breakable",
                tooltip = "When set, a creature shoved into this wall hard enough smashes through it instead of stopping. The force needed is the wall's stamina.",
                value = breakable,
                change = function(element)
                    breakable = element.value
                    ApplyBreakToAsset()
                    dialogPanel:FireEventTree("refreshbreak")
                end,
            },

            gui.Panel{
                classes = {"formStackedRow"},
                refreshbreak = function(element)
                    element:SetClass("collapsed", not breakable)
                end,

                gui.Label{
                    classes = {"formStacked"},
                    text = "Material:",
                },
                gui.Dropdown{
                    classes = {"formStacked"},
                    idChosen = breakMaterialId,
                    options = (function()
                        local result = {}
                        for _,material in ipairs(BREAK_MATERIALS) do
                            result[#result+1] = {
                                id = material.id,
                                text = material.text,
                            }
                        end
                        return result
                    end)(),
                    change = function(element)
                        breakMaterialId = element.idChosen
                        local material = BreakMaterialById(breakMaterialId)
                        --Presets stamp their stamina; Custom keeps whatever
                        --value was already there as the starting point.
                        if material ~= nil and material.stamina ~= nil then
                            breakStamina = material.stamina
                        end
                        ApplyBreakToAsset()
                        dialogPanel:FireEventTree("refreshbreak")
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                refreshbreak = function(element)
                    element:SetClass("collapsed", not breakable)
                end,

                gui.Label{
                    classes = {"formStacked"},
                    text = "Stamina:",
                },

                --Preset materials show their fixed value; only Custom is
                --editable. Both live here and swap by collapse so the row
                --keeps its layout either way.
                gui.Label{
                    classes = {"formStacked"},
                    text = "",
                    refreshbreak = function(element)
                        element:SetClass("collapsed", breakMaterialId == "custom")
                        element.text = string.format("%d", breakStamina)
                    end,
                },

                gui.Input{
                    classes = {"formStacked"},
                    text = string.format("%d", breakStamina),
                    width = 60,
                    characterLimit = 3,
                    numeric = true,
                    selectAllOnFocus = true,
                    refreshbreak = function(element)
                        element:SetClass("collapsed", breakMaterialId ~= "custom")
                    end,
                    change = function(element)
                        local n = tonumber(element.text)
                        if n == nil or n < 1 then
                            --reject non-numeric / zero: restore the last good
                            --value rather than silently making it unbreakable.
                            element.text = string.format("%d", breakStamina)
                            return
                        end
                        breakStamina = math.floor(n + 0.5)
                        element.text = string.format("%d", breakStamina)
                        ApplyBreakToAsset()
                    end,
                },
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            RevertChanges()
                            gui.CloseModal()
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = "Save",
                    halign = "center",
                    events = {
                        click = function()
                            asset:Upload()
                            gui.CloseModal()
                        end,
                    },
                },
            },
        },
    }

    --settle the breakability + openable rows' initial collapse state + values.
    dialogPanel:FireEventTree("refreshbreak")
    dialogPanel:FireEventTree("refreshopenable")

    gui.ShowModal(dialogPanel)
end

--============================================================================
--The panel.
--============================================================================

local MODES = {
    {
        id = "walls",
        text = "Walls",
    },
    {
        id = "zones",
        text = "Zones",
    },
    {
        id = "surfaces",
        text = "Footsteps",
    },
    {
        id = "elevation",
        text = "Elevation",
    },
    {
        id = "props",
        text = "Props",
    },
}

--Tools with a `tool` field drive the engine building tools (drawing).
--Tools with a `mapTool` field are custom map tools (editor.SetMapTool) whose
--strokes come back to this panel as 'tool' events. The eraser and Delete
--Wall tools are shared between the thin and solid tool strips.
local TOOL_ERASE = {
    id = "erase",
    icon = "phosphor/eraser-fill.png",
    mapTool = "rectangle",
    mapToolClosed = true,
    help = "Eraser: drag a rectangle to erase every markup wall (and markup solid block) inside it. Visible art walls are not affected.",
}

local TOOL_DELETE = {
    id = "delete",
    icon = "ui-icons/close.png",
    --Inert sentinel: keeping a custom map tool alive (wallSkeletons=true)
    --leaves the grey wall skeleton overlay up so the user can see the walls
    --they are removing. This string matches no real map tool ("free",
    --"rectangle", "shape"...), so it captures no drawing - the Delete tool's
    --input comes from map focus (maphover/mappress) instead. See the think
    --loop and the maphover/mappress handlers below.
    mapTool = "markupdelete",
    mapToolClosed = false,
    help = "Delete Wall: hover a markup wall to highlight the segment under the cursor, then click to remove just that segment. Visible art walls are not affected.",
}

--`shape` pairs a tool with its counterpart in the other draw mode, so switching
--Thin <-> Solid keeps the shape the user picked instead of resetting the strip.
--Both strips lead with the rectangle so the two modes read the same.
local TOOLS = {
    {
        id = "rectangle",
        shape = "rect",
        icon = "game-icons/square.png",
        tool = "rectangle",
        help = "Rectangle tool: drag to draw a rectangle of walls.",
    },
    {
        id = "line",
        shape = "poly",
        icon = "game-icons/polygon-segments.png",
        tool = "shape",
        help = "Line tool: click to chain wall segments; double-click or press Enter to finish.",
    },
    {
        id = "free",
        shape = "free",
        icon = "panels/hud/icon_line_tool_82.png",
        tool = "free",
        help = "Freehand tool: drag to draw walls along the cursor.",
    },
    {
        id = "points",
        icon = "icons/icon_gesture/icon_gesture_47.png",
        tool = "points",
        help = "Edit Points: drag a wall vertex to move it. Right-click a vertex to delete it, click on a wall line to add a vertex, and click a one-way wall's direction marker to flip its facing.",
    },
    TOOL_ERASE,
    TOOL_DELETE,
}

--Tool strip in SOLID draw mode: a solid block is a filled region, not an open
--polyline, so the drawing tools are closed shapes running as custom map tools
--(like the eraser) - never the engine building tools. Their strokes come back
--as 'tool' events and turn into ExecutePolygonOperation{solid=true} (see
--markupsolid below). No Points tool: PointEditingTool skips floor-type ops
--(PointEditingTool.cs "op.Value.erase || op.Value.floor"), and a solid op is
--a floor op, so solid regions have no editable vertices.
local SOLID_TOOLS = {
    {
        id = "solidrect",
        shape = "rect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        mapToolClosed = true,
        help = "Rectangle block: drag to fill a rectangle with a solid block of the selected wall type.",
    },
    {
        id = "solidpoly",
        shape = "poly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        mapToolClosed = true,
        help = "Polygon block: click to chain vertices around the area to fill; double-click or press Enter to finish.",
    },
    {
        id = "solidfree",
        shape = "free",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        mapToolClosed = true,
        help = "Freehand block: drag to trace the outline of the area to fill.",
    },
    TOOL_ERASE,
    TOOL_DELETE,
}

--Zone painting tools: all closed-shape custom map tools (a zone is a filled
--tile region). Strokes come back as 'tool' events and rasterize to the tiles
--whose centers the stroke contains.
local ZONE_TOOLS = {
    {
        id = "zonerect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        help = "Rectangle: drag to paint the selected zone type over an area.",
    },
    {
        id = "zonepoly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        help = "Polygon: click to chain vertices around the area to paint; double-click or press Enter to finish.",
    },
    {
        id = "zonefree",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        help = "Freehand: drag to trace the outline of the area to paint.",
    },
    {
        id = "zoneerase",
        icon = "phosphor/eraser-fill.png",
        mapTool = "rectangle",
        erase = true,
        help = "Eraser: drag a rectangle to remove zone tiles from every zone in the region.",
    },
}

local function ZoneToolById(id)
    for _,toolInfo in ipairs(ZONE_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--Footsteps mode paint tools: the same closed-shape custom map tools as the
--zone tools, painting the selected surface family instead of a keyword.
local FOOTSTEP_TOOLS = {
    {
        id = "footrect",
        icon = "game-icons/square.png",
        mapTool = "rectangle",
        help = "Rectangle: drag to paint the selected footstep surface over an area.",
    },
    {
        id = "footpoly",
        icon = "game-icons/polygon-segments.png",
        mapTool = "shape",
        help = "Polygon: click to chain vertices around the area to paint; double-click or press Enter to finish.",
    },
    {
        id = "footfree",
        icon = "panels/hud/icon_line_tool_82.png",
        mapTool = "free",
        help = "Freehand: drag to trace the outline of the area to paint.",
    },
    {
        id = "footerase",
        icon = "phosphor/eraser-fill.png",
        mapTool = "rectangle",
        erase = true,
        help = "Eraser: drag a rectangle to clear painted footstep surfaces from the region.",
    },
}

local function FootstepToolById(id)
    for _,toolInfo in ipairs(FOOTSTEP_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--Looks a tool id up in either strip (the draw-mode switch needs the OUTGOING
--tool's shape, which by then is no longer in the active strip).
local function FindToolInfo(id)
    for _,toolInfo in ipairs(TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    for _,toolInfo in ipairs(SOLID_TOOLS) do
        if toolInfo.id == id then
            return toolInfo
        end
    end
    return nil
end

--The active tool strip follows the DRAW MODE, not the selected wall type:
--thin mode drives the engine building tools, solid mode drives closed-shape
--custom map tools. Openable (door) types are thin-only - selecting one
--forces thin mode (SelectChip) - so no separate strip is needed.
local function ActiveToolInfos()
    if m_solidMode and not EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]) then
        return SOLID_TOOLS
    end
    return TOOLS
end

--Chip rules are shared between the panel and the library modal: modals
--re-root the style cascade, so the modal needs its own copy of these rules.
local function MarkupChipStyles()
    return {
        {
            selectors = {"markupChip"},
            borderWidth = 1,
            borderColor = "@border",
            bgcolor = "clear",
        },
        {
            selectors = {"markupChip", "hover"},
            borderColor = "@fg",
        },
        {
            selectors = {"markupChip", "selected"},
            bgcolor = "@bgAlt",
            borderColor = "@fg",
        },
        {
            selectors = {"markupWallLine"},
            bgcolor = "@fgMuted",
        },

        --gui.Slider deliberately sets NO default width/height (Gui.lua: doing
        --so would be selfStyle and would beat any cascade rule the caller
        --supplied), and it sizes its handle off its own height
        --(handle width = "100% height", holding a 60% square rotated 45).
        --An unsized slider therefore renders as a giant diamond. The Edit
        --Wall dialog solves this with the same two rules; the panel body
        --needs its own copy because that dialog is a separate modal with
        --separate styles. Width leaves room for the row's 80px name label.
        {
            selectors = {"slider"},
            width = "100%-84",
            height = 24,
            valign = "center",
        },
        {
            selectors = {"sliderLabel"},
            fontSize = 14,
        },
    }
end

local function GetPanelStyles()
    return ThemeEngine.MergeStyles{
        MarkupChipStyles(),
    }
end

--============================================================================
--Delete tool helpers.
--
--The Delete tool is a hover-then-click interaction driven by map focus
--(maphover/mappress), not a stroke: moving over a wall highlights the single
--segment (edge) under the cursor, and a click erases just that edge. The
--engine's GetNearestWallSegment returns the nearest wall's WHOLE centerline
--path; we pick the nearest edge of that path ourselves so a click removes only
--the touched segment instead of the entire wall (which is what erasing the
--full path used to do - "deletes large swathes of wall").
--============================================================================

--The highlighted "about to delete" line, plus a key identifying its segment so
--the marker is only rebuilt when the target segment actually changes (maphover
--fires on every mouse move).
local m_deleteHighlight = nil
local m_deleteHighlightKey = nil
--Warn once, not every mouse move, if the engine build lacks GetNearestWallSegment.
local m_deleteWarnedNoEngine = false

local function DistancePointToSegment(px, py, ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local lenSq = dx*dx + dy*dy
    local t = 0
    if lenSq > 0.00000001 then
        t = ((px - ax)*dx + (py - ay)*dy) / lenSq
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local cx = ax + t*dx
    local cy = ay + t*dy
    local ex = px - cx
    local ey = py - cy
    return math.sqrt(ex*ex + ey*ey)
end

--Returns { a = {x,y}, b = {x,y} } for the nearest invisible-wall edge to the
--cursor world point - or, when a markup DOOR's segment is nearer, that
--segment with its object in the `door` field - or nil if nothing is within
--reach / the point is off-map.
local function FindNearestDeleteSegment(point)
    if point == nil then
        return nil
    end
    local floor = game.currentFloor
    if floor == nil then
        return nil
    end

    --The maphover/mappress point is parallax-adjusted using the mouseover
    --floor's heightmap only, but walls render projected by the full surface
    --altitude (heightmap + elevation overlay + platforms). On ground raised or
    --lowered from 0 the two disagree, so the selection landed off the wall
    --under the cursor. editor.mouseEditSurfacePoint uses the same projection
    --as wall rendering; pcall so a stale engine build degrades to the event
    --point instead of erroring every mouse move.
    local okSurface, surfacePoint = pcall(function()
        return editor.mouseEditSurfacePoint
    end)
    if okSurface and surfacePoint ~= nil then
        point = surfacePoint
    end

    --pcall: maphover fires every frame, so a stale engine build (no
    --GetNearestWallSegment) must degrade quietly instead of erroring per move.
    --atMouse: engines that support it ignore x/y and match walls in projected
    --screen space against the actual cursor -- the only approach that stays
    --accurate on steep slopes, where a wall renders far from its stored
    --coordinates and any converted point comparison can exceed maxDistance.
    --Older engines ignore the flag and use x/y as before.
    local ok, seg = pcall(function()
        return floor:GetNearestWallSegment{
            x = point.x,
            y = point.y,
            atMouse = true,
            maxDistance = 0.7,
            invisibleOnly = true,
        }
    end)
    if not ok then
        if not m_deleteWarnedNoEngine then
            m_deleteWarnedNoEngine = true
            dmhub.Debug("MARKUP:: delete tool needs an engine build with GetNearestWallSegment support")
        end
        return nil
    end
    if seg == nil then
        return nil
    end

    --Engines with atMouse support hand back the nearest edge directly (matched
    --in projected screen space, so it is the edge visually under the cursor
    --even on steep slopes). Prefer it over re-deriving the edge here.
    if seg.segment ~= nil and #seg.segment >= 4 then
        return {
            a = { x = seg.segment[1], y = seg.segment[2] },
            b = { x = seg.segment[3], y = seg.segment[4] },
        }
    end

    local pts = seg.points
    if pts == nil or #pts < 4 then
        return nil
    end

    --Older engines: pts is an interleaved x,y list of the wall's whole path;
    --find the single edge (consecutive vertex pair) closest to the cursor.
    local bestDist = nil
    local best = nil
    for i = 1, #pts - 3, 2 do
        local ax, ay = pts[i], pts[i+1]
        local bx, by = pts[i+2], pts[i+3]
        local d = DistancePointToSegment(point.x, point.y, ax, ay, bx, by)
        if bestDist == nil or d < bestDist then
            bestDist = d
            best = { a = { x = ax, y = ay }, b = { x = bx, y = by } }
        end
    end
    return best
end

--A hair-thin open-path erase EXACTLY along the wall centerline is unreliable on
--short segments: clipper's collinear-overlap handling (the ribbon sits right on
--the wall line) is numerically unstable -> "sometimes deletes nothing". So we
--erase a CLOSED box oriented along the segment: the wall centerline runs
--through the box INTERIOR (no collinear edge, so clipper is stable).
--
--DELETE_MIN_GAP guarantees the cut survives the engine's wall endpoint
--auto-merge (WallInfo.PointsCloseEnoughToMerge). That threshold used to be 0.3
--tiles - which forced MIN_GAP to 0.4 and made deleting one fine segment clear
--its neighbours too. The engine now welds only within 0.01, so the gap can be
--near-exact and a click removes just the touched segment.
--REQUIRES that engine build: against an older engine (0.3 weld) gaps this
--small heal straight back and deletion appears to do nothing.
local DELETE_MIN_GAP = 0.05      --min cleared length along the wall (> 0.01 merge threshold)
local DELETE_HALF_WIDTH = 0.05   --box half-width; keeps the centerline off the box edges
local DELETE_END_OVERSHOOT = 0.02 --push the cut just past a long segment's ends so both are removed

--Given a touched edge { a = {x,y}, b = {x,y} } returns:
--  a, b : the two axis endpoints of the cleared span (for the highlight preview)
--  box  : an interleaved-coord closed quad to feed ExecutePolygonOperation
local function DeleteSegmentGeometry(seg)
    local ax, ay = seg.a.x, seg.a.y
    local bx, by = seg.b.x, seg.b.y
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx*dx + dy*dy)
    if len < 0.0001 then
        --degenerate edge: clear an axis-aligned chunk around the point.
        dx, dy, len = 1, 0, 1
    end
    local ux, uy = dx/len, dy/len   --unit along the segment
    local nx, ny = -uy, ux          --unit perpendicular to it
    local mx, my = (ax + bx)*0.5, (ay + by)*0.5
    local halfLen = math.max(len*0.5 + DELETE_END_OVERSHOOT, DELETE_MIN_GAP*0.5)
    local hw = DELETE_HALF_WIDTH

    local e1x, e1y = mx + ux*halfLen, my + uy*halfLen
    local e2x, e2y = mx - ux*halfLen, my - uy*halfLen

    return {
        a = { x = e1x, y = e1y },
        b = { x = e2x, y = e2y },
        box = {
            e1x + nx*hw, e1y + ny*hw,
            e1x - nx*hw, e1y - ny*hw,
            e2x - nx*hw, e2y - ny*hw,
            e2x + nx*hw, e2y + ny*hw,
        },
    }
end

local function ClearDeleteHighlight()
    if m_deleteHighlight ~= nil then
        m_deleteHighlight:Destroy()
        m_deleteHighlight = nil
    end
    m_deleteHighlightKey = nil
end

local function ShowDeleteHighlight(seg)
    local key = string.format("%.4f,%.4f,%.4f,%.4f", seg.a.x, seg.a.y, seg.b.x, seg.b.y)
    if key == m_deleteHighlightKey and m_deleteHighlight ~= nil then
        return
    end
    ClearDeleteHighlight()
    --terrainParallax: the wall skeleton parallax-shifts with the camera + terrain
    --height every frame, so a flat (z=0) line drifts off the wall wherever the
    --map has parallax. This projects the highlight with the same parallax.
    m_deleteHighlight = dmhub.HighlightLine{
        color = "#ff4d4d",
        a = core.Vector2(seg.a.x, seg.a.y),
        b = core.Vector2(seg.b.x, seg.b.y),
        floorIndex = game.currentFloorIndex,
        terrainParallax = true,
    }
    m_deleteHighlightKey = key
end

local CreateMarkupEditor

DockablePanel.Register{
    name = "Map Markup",
    icon = "icons/standard/Icon_App_Whiteboard.png",
    vscroll = true,
    dmonly = true,
    minHeight = 200,
    folder = "Map Editing",
    stickyFocus = true,
    content = function()
        track("panel_open", {
            panel = "Map Markup",
            dailyLimit = 30,
        })
        return CreateMarkupEditor()
    end,
}

CreateMarkupEditor = function()
    local contentPanel
    local palettePanel
    --forward-declared: the draw-mode toggle rebuilds the tool strip and
    --relabels the height stepper, so it must close over both. SetDrawMode is
    --forward-declared because SelectChip forces thin mode for openable types.
    local toolsPanel
    local drawModePanel
    local heightPanel
    local SelectChip
    local AddPaletteEntry
    local RemovePaletteEntry
    local SetDrawMode

    m_paletteEntries = ParsePalette()
    if m_selectedIndex ~= nil and m_selectedIndex > #m_paletteEntries then
        m_selectedIndex = nil
    end
    if m_selectedIndex == nil and #m_paletteEntries > 0 then
        m_selectedIndex = 1
    end

    --Each mode's default drawing tool is its first: the rectangle, in both.
    --Solid mode's tools are custom map tools, so it leaves the shared
    --building-tool settings alone. Openable (door) types are thin-only.
    if m_solidMode and EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]) then
        m_solidMode = false
    end
    if m_solidMode then
        m_toolId = "solidrect"
    else
        m_toolId = "rectangle"
        dmhub.SetSettingValue("buildingtool", "rectangle")
        dmhub.SetSettingValue("building:erase", false)
    end

    --Materializes the wall asset behind a preset entry if needed, returning
    --the asset guid or nil.
    local MaterializeEntry = function(entry)
        if entry.guid ~= nil and assets.walls[entry.guid] ~= nil then
            return entry.guid
        end

        local preset = PresetForEntry(entry)
        if preset == nil then
            return nil
        end

        local guid = CreateMarkupWallAsset(preset.name, preset.fields)
        if guid == nil then
            return nil
        end

        entry.guid = guid
        SavePalette(m_paletteEntries)
        return guid
    end

    SelectChip = function(index)
        local entry = m_paletteEntries[index]
        if entry == nil then
            return
        end

        m_selectedIndex = index

        local preset = PresetForEntry(entry)
        if preset ~= nil then
            MaterializeEntry(entry)
            SetWallHeightSetting(preset.height)
        end

        if palettePanel ~= nil and palettePanel.valid then
            palettePanel:FireEvent("refreshchips")
            gui.SetFocus(palettePanel)
        end

        --Openable (door) types draw thin walls only: force thin mode so the
        --strokes are real wall operations the engine can attach door state
        --to. SetDrawMode also rebuilds the tool strip and pushes the shared
        --building-tool setting.
        if m_solidMode and EntryIsOpenable(entry) then
            SetDrawMode(false)
        end

        --the selection can flip between openable and plain types, which
        --hides/shows the Draw As toggle.
        if contentPanel ~= nil and contentPanel.valid then
            contentPanel:FireEventTree("refreshdoorchip")
        end
    end

    AddPaletteEntry = function(entry)
        m_paletteEntries[#m_paletteEntries+1] = entry
        m_selectedIndex = #m_paletteEntries
        SavePalette(m_paletteEntries)
        SelectChip(m_selectedIndex)
    end

    RemovePaletteEntry = function(index)
        if m_paletteEntries[index] == nil then
            return
        end

        table.remove(m_paletteEntries, index)
        if m_selectedIndex ~= nil then
            if m_selectedIndex == index then
                m_selectedIndex = nil
            elseif m_selectedIndex > index then
                m_selectedIndex = m_selectedIndex - 1
            end
        end
        SavePalette(m_paletteEntries)
    end

    local CreateChipContextMenuItems = function(element, index)
        local entry = m_paletteEntries[index]
        local result = {}

        if entry ~= nil and (entry.kind == "preset" or entry.kind == "solid" or entry.kind == "custom") and entry.guid ~= nil and assets.walls[entry.guid] ~= nil then
            result[#result+1] = {
                text = "Edit Wall...",
                click = function()
                    element.popup = nil
                    ShowMarkupWallDialog(entry.guid)
                end,
            }
        end

        result[#result+1] = {
            text = "Remove from Palette",
            click = function()
                element.popup = nil
                RemovePaletteEntry(index)
            end,
        }

        return result
    end

    --A palette tile: name, then a preview of the line the wall draws on the
    --map, then a one-line summary; laid out two per row. The preview shows
    --the wall's own behavior (blocks / one-way), which is the same whether it
    --is drawn thin or solid, so it does not vary with the draw mode.
    local CreateWallChip = function(index, entry)
        local preview
        if EntryIsOpenable(entry) then
            preview = CreateDoorLinePreview()
        else
            preview = CreateWallLinePreview(EntryFields(entry))
        end
        return gui.Panel{
            classes = {"markupChip", cond(index == m_selectedIndex, "selected")},
            width = "48%",
            height = 62,
            flow = "vertical",
            bgimage = true,
            pad = 6,
            borderBox = true,
            hmargin = 2,
            vmargin = 2,

            data = {
                index = index,
            },

            press = function(element)
                SelectChip(element.data.index)
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = CreateChipContextMenuItems(element, element.data.index),
                }
            end,

            gui.Label{
                classes = {"bold"},
                text = EntryDisplayName(entry),
                width = "100%",
                height = "auto",
            },

            preview,

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = SummarizeEntry(entry),
                width = "100%",
                height = "auto",
            },
        }
    end

    --Horizontal strip of mode tabs across the top of the panel.
    local modeTabs = gui.Panel{
        classes = {"tabBar"},
        width = "98%",
        height = 26,
        halign = "center",
        vmargin = 4,
        flow = "horizontal",
        children = (function()
            local result = {}
            for _,modeInfo in ipairs(MODES) do
                result[#result+1] = gui.Label{
                    classes = {"tab", cond(modeInfo.id == m_mode, "selected")},
                    text = modeInfo.text,
                    --The theme's tab sizing (130x40 / 18pt) is for full-width
                    --tab strips; five tabs must fit in the dock width.
                    width = "20%",
                    height = "100%",
                    fontSize = 13,
                    hpad = 0,
                    data = {
                        modeid = modeInfo.id,
                        modetext = modeInfo.text,
                    },
                    press = function(element)
                        m_mode = element.data.modeid
                        for _,tab in ipairs(element.parent.children) do
                            tab:SetClass("selected", tab.data.modeid == m_mode)
                        end
                        contentPanel:FireEventTree("markupmode")
                    end,
                }
            end
            return result
        end)(),
    }

    palettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        monitorAssets = "Tilesheet",
        multimonitor = {"markup:wallpalette"},

        events = {
            --the palette setting changed: our own write, another DM's, or a
            --map switch changing the effective value.
            monitor = function(element)
                element:FireEvent("refreshpalette")
            end,

            refreshAssets = function(element)
                element:FireEvent("refreshpalette")
            end,

            refreshpalette = function(element)
                m_paletteEntries = ParsePalette()
                if m_selectedIndex ~= nil and m_selectedIndex > #m_paletteEntries then
                    m_selectedIndex = nil
                end

                local children = {}
                for i,entry in ipairs(m_paletteEntries) do
                    children[#children+1] = CreateWallChip(i, entry)
                end
                element.children = children

                --the selected chip can have become openable (Edit Wall on it,
                --or a remote change); openable types are thin-only.
                if m_solidMode and EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]) and SetDrawMode ~= nil then
                    SetDrawMode(false)
                end

                --the selection (and with it the thin-vs-solid tool strip) can
                --change with the palette contents.
                if toolsPanel ~= nil and toolsPanel.valid then
                    toolsPanel:FireEvent("rebuildtools")
                end
                if contentPanel ~= nil and contentPanel.valid then
                    contentPanel:FireEventTree("refreshdoorchip")
                end
            end,

            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    chip:SetClass("selected", chip.data.index == m_selectedIndex)
                end
            end,
        },
    }

    local addButton
    addButton = gui.Button{
        classes = {"sizeM"},
        text = "+ Add Wall Type",
        halign = "center",
        vmargin = 4,
        events = {
            click = function(element)
                local entries = {}

                for _,preset in ipairs(WALL_PRESETS) do
                    local inPalette = false
                    for _,entry in ipairs(m_paletteEntries) do
                        if entry.kind == "preset" and entry.key == preset.key then
                            inPalette = true
                            break
                        end
                    end

                    if not inPalette then
                        entries[#entries+1] = {
                            text = preset.name,
                            click = function()
                                element.popup = nil
                                AddPaletteEntry{
                                    kind = "preset",
                                    key = preset.key,
                                }
                            end,
                        }
                    end
                end

                entries[#entries+1] = {
                    text = "Door (Openable)",
                    click = function()
                        element.popup = nil
                        --openable lives on the wall asset, which needs the
                        --engine build; refuse with a message rather than
                        --quietly adding a plain wall.
                        if not OpenableWallsSupported() then
                            gui.ModalMessage{
                                title = "Door (Openable)",
                                message = "Openable walls need an engine build with door support.",
                            }
                            return
                        end
                        local guid = CreateMarkupWallAsset("Door", DOOR_TYPE_FIELDS)
                        if guid ~= nil then
                            AddPaletteEntry{
                                kind = "custom",
                                guid = guid,
                            }
                        end
                    end,
                }

                entries[#entries+1] = {
                    text = "Other Invisible Walls...",
                    click = function()
                        element.popup = nil
                        element:FireEvent("showlibrary")
                    end,
                }

                entries[#entries+1] = {
                    text = "Custom...",
                    click = function()
                        element.popup = nil
                        local guid = CreateMarkupWallAsset("Custom Markup Wall", WALL_PRESETS_BY_KEY["stone"].fields)
                        if guid ~= nil then
                            AddPaletteEntry{
                                kind = "custom",
                                guid = guid,
                            }
                            ShowMarkupWallDialog(guid)
                        end
                    end,
                }

                element.popup = gui.ContextMenu{
                    entries = entries,
                }
            end,

            showlibrary = function(element)
                --Markup is invisible-walls-only: visible art walls belong to
                --the Building editor. Also skip walls already in the palette.
                local paletteGuids = {}
                for _,entry in ipairs(m_paletteEntries) do
                    if entry.guid ~= nil then
                        paletteGuids[entry.guid] = true
                    end
                end

                local sortedWalls = {}
                for id,wall in pairs(assets.walls) do
                    if (not wall.hidden) and wall.invisible == true and (not paletteGuids[id]) then
                        sortedWalls[#sortedWalls+1] = {
                            id = id,
                            wall = wall,
                        }
                    end
                end
                table.sort(sortedWalls, function(a, b)
                    local aname = a.wall.description or a.id
                    local bname = b.wall.description or b.id
                    return aname < bname or (aname == bname and a.id < b.id)
                end)

                local rows = {}
                for _,info in ipairs(sortedWalls) do
                    rows[#rows+1] = gui.Panel{
                        classes = {"markupChip"},
                        width = "96%",
                        height = 32,
                        halign = "center",
                        flow = "horizontal",
                        bgimage = true,
                        pad = 4,
                        borderBox = true,
                        vmargin = 1,

                        data = {
                            wallid = info.id,
                        },

                        press = function(rowElement)
                            AddPaletteEntry{
                                kind = "wall",
                                guid = rowElement.data.wallid,
                            }
                            gui.CloseModal()
                        end,

                        gui.Panel{
                            width = 110,
                            height = "100%",
                            valign = "center",
                            flow = "horizontal",
                            CreateWallLinePreview(AssetFields(info.wall)),
                        },

                        gui.Label{
                            text = info.wall.description or info.id,
                            width = "auto",
                            height = "auto",
                            hmargin = 8,
                            valign = "center",
                        },
                    }
                end

                if #rows == 0 then
                    rows[#rows+1] = gui.Label{
                        classes = {"fgMuted"},
                        text = "No other invisible wall types in this game.",
                        width = "90%",
                        height = "auto",
                        halign = "center",
                        vmargin = 12,
                        textAlignment = "center",
                    }
                end

                local dialogPanel = gui.Panel{
                    id = "MarkupWallLibraryDialog",
                    classes = {"framedPanel"},
                    width = 440,
                    height = 620,
                    pad = 16,
                    borderBox = true,
                    flow = "vertical",
                    styles = ThemeEngine.MergeStyles{
                        Styles.Panel,
                        MarkupChipStyles(),
                    },

                    gui.Label{
                        classes = {"dialogTitle"},
                        text = "Add Invisible Wall",
                    },

                    gui.Panel{
                        width = "100%",
                        height = "100%-100",
                        vscroll = true,
                        flow = "vertical",
                        children = rows,
                    },

                    gui.Button{
                        classes = {"sizeM"},
                        text = "Cancel",
                        halign = "center",
                        valign = "bottom",
                        vmargin = 8,
                        captureEscape = true,
                        escapePriority = EscapePriority.EXIT_DIALOG,
                        events = {
                            click = function(buttonElement)
                                buttonElement:FireEvent("escape")
                            end,
                            escape = function()
                                gui.CloseModal()
                            end,
                        },
                    },
                }

                gui.ShowModal(dialogPanel)
            end,
        },
    }

    --Tool selection strip: icon buttons in the same style the settings
    --system's iconbuttons editor uses (SettingsGui.lua). Thin-wall drawing
    --tools write the shared engine building-tool settings; solid drawing
    --tools, erase and delete run as custom map tools kept alive by this
    --panel's think loop, with their strokes coming back as 'tool' events.
    --The strip's buttons are rebuilt when the selected chip flips between
    --thin and solid (rebuildtools).
    local BuildToolButtons = function()
        local result = {}
        for _,toolInfo in ipairs(ActiveToolInfos()) do
            result[#result+1] = gui.Button{
                classes = {"sizeL", "bordered", cond(toolInfo.id == m_toolId, "selected")},
                icon = toolInfo.icon,
                tooltip = toolInfo.help,
                valign = "center",
                hmargin = 2,
                data = {
                    toolid = toolInfo.id,
                    tool = toolInfo.tool,
                },
                press = function(element)
                    m_toolId = element.data.toolid
                    if element.data.tool ~= nil then
                        dmhub.SetSettingValue("building:erase", false)
                        dmhub.SetSettingValue("buildingtool", element.data.tool)
                    end
                    toolsPanel:FireEvent("refreshtools")
                    --take focus back: the Building editor's palette
                    --monitors buildingtool and refocuses itself when the
                    --tool changes.
                    gui.SetFocus(element)
                    --immediately register the custom tool (it requires
                    --focus, so this must come after SetFocus) rather than
                    --waiting for the next think tick.
                    toolsPanel:FireEvent("think")
                end,
            }
        end
        return result
    end

    toolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        multimonitor = {"buildingtool", "building:erase"},

        --keep the custom map tool alive while erase/delete is active. The
        --engine expires custom tools after ~1s, so this must re-register
        --faster than that; each registration returns a fresh event source
        --that has to be listened to again.
        thinkTime = 0.3,

        events = {
            monitor = function(element)
                element:FireEvent("refreshtools")
            end,

            refreshtools = function(element)
                --custom map tools (erase, delete, the solid shape tools) are
                --owned by this panel outright; engine drawing tools reflect
                --the shared building-tool settings, so if the Building editor
                --switched the shape (or turned its erase checkbox on) no
                --markup chip shows selected.
                local tools = ActiveToolInfos()
                local activeInfo = nil
                for _,toolInfo in ipairs(tools) do
                    if toolInfo.id == m_toolId then
                        activeInfo = toolInfo
                    end
                end

                local activeid = m_toolId
                if activeInfo == nil or activeInfo.mapTool == nil then
                    activeid = nil
                    if not dmhub.GetSettingValue("building:erase") then
                        local tool = dmhub.GetSettingValue("buildingtool")
                        for _,toolInfo in ipairs(tools) do
                            if toolInfo.tool == tool then
                                activeid = toolInfo.id
                            end
                        end
                    end
                end

                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolid == activeid)
                end
            end,

            --the selected chip flipped between thin and solid (or the palette
            --changed under us): swap the button set for the matching tool
            --strip. If the active tool doesn't exist in the new strip, fall
            --back to its default drawing tool - without touching the shared
            --building-tool settings, since this can fire from a remote
            --palette change while the Building editor is in use.
            rebuildtools = function(element)
                local tools = ActiveToolInfos()

                local validTool = false
                for _,toolInfo in ipairs(tools) do
                    if toolInfo.id == m_toolId then
                        validTool = true
                    end
                end

                if not validTool then
                    --carry the equivalent shape across the mode switch (rect stays
                    --rect, polygon stays polygon) so only the strip changes, not the
                    --user's choice; otherwise fall back to the first tool.
                    local outgoing = FindToolInfo(m_toolId)
                    local wantShape = nil
                    if outgoing ~= nil then
                        wantShape = outgoing.shape
                    end

                    m_toolId = nil
                    if wantShape ~= nil then
                        for _,toolInfo in ipairs(tools) do
                            if toolInfo.shape == wantShape then
                                m_toolId = toolInfo.id
                            end
                        end
                    end
                    if m_toolId == nil then
                        m_toolId = tools[1].id
                    end
                end

                element.children = BuildToolButtons()
                element:FireEvent("refreshtools")
            end,

            think = function(element)
                --The Delete tool takes map focus so it gets maphover/mappress
                --(hover-highlight + click-to-delete-one-segment). Own map focus
                --only while Delete is the active markup tool and this panel is
                --focused; release it and drop any highlight otherwise. Gating on
                --focus keeps us from stealing map focus from ability targeting
                --etc. This runs before the m_mode guard so switching mode/tool
                --tears the overlay down promptly.
                local wantDelete = m_mode == "walls" and m_toolId == "delete"
                    and m_markupHud ~= nil and m_markupHud.valid
                    and gui.ChildHasFocus(m_markupHud)

                if wantDelete then
                    if not element.mapfocus then
                        element.mapfocus = true
                    end
                else
                    if element.mapfocus then
                        element.mapfocus = false
                    end
                    ClearDeleteHighlight()
                end

                if m_mode ~= "walls" then
                    return
                end

                local toolInfo = nil
                for _,t in ipairs(ActiveToolInfos()) do
                    if t.id == m_toolId and t.mapTool ~= nil then
                        toolInfo = t
                    end
                end
                if toolInfo == nil then
                    return
                end

                if m_markupHud == nil or not m_markupHud.valid or not gui.ChildHasFocus(m_markupHud) then
                    return
                end

                --Both erase (rectangle) and delete (the inert "markupdelete"
                --sentinel) keep a custom map tool alive purely so the engine
                --leaves the wall skeleton overlay up (wallSkeletons) - the user
                --needs to see the walls they are removing. The sentinel captures
                --no drawing; delete's real input arrives via map focus.
                local eventSource = editor:SetMapTool{
                    tool = toolInfo.mapTool,
                    closed = toolInfo.mapToolClosed,
                    expires = 1,
                    stabilization = 0,
                    wallSkeletons = true,
                    --These tools draw/erase MAP GEOMETRY, so they snap like the
                    --building tools (and honor ctrl to invert). Without it a
                    --custom tool falls through to the separate OBJECT snap
                    --setting, since it publishes no wall selection -- which is
                    --why solid blocks did not snap while thin walls did.
                    --Needs an engine build; older engines ignore the field.
                    snapToGrid = true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m_mode ~= "walls" or path == nil then
                    return
                end
                --Erase (rectangle) and the solid shape tools deliver strokes.
                --Delete's sentinel map tool captures nothing; its input
                --arrives via maphover/mappress.
                if m_toolId == "erase" then
                    element:FireEvent("markuperase", path)
                elseif m_toolId == "solidrect" or m_toolId == "solidpoly" or m_toolId == "solidfree" then
                    element:FireEvent("markupsolid", path)
                end
            end,

            --rectangle stroke: erase every invisible wall - and, on engine
            --builds that support it, every invisible solid block - in the
            --region.
            markuperase = function(element, path)
                local floor = game.currentFloor
                if floor == nil then
                    return
                end

                --path.points needs the engine half of this feature; guard so
                --a stale engine build logs instead of erroring.
                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 4 then
                    if not ok then
                        dmhub.Debug("MARKUP:: eraser needs an engine build with MapPath points support")
                    end
                    return
                end

                --floor=true routes the op through the floor-erase path, which
                --carves markup solid blocks; the engine only honors
                --eraseInvisibleOnly there on builds with the solid support, so
                --older engines keep the walls-only op (a type-blind floor
                --erase would destroy art). One op = one undo step.
                local okSupport, supportsSolids = pcall(function()
                    return floor.supportsSolidOperations
                end)
                local carveSolids = okSupport and supportsSolids == true

                floor:ExecutePolygonOperation{
                    points = {points},
                    erase = true,
                    eraseInvisibleOnly = true,
                    walls = true,
                    floor = carveSolids,
                    closed = path.closed,
                }
            end,

            --closed solid stroke: fill the region with an invisible solid
            --block of the selected solid wall type, at the height stepper's
            --height (blank/To Roof = 0 = floor-to-ceiling, no standable top).
            markupsolid = function(element, path)
                local floor = game.currentFloor
                if floor == nil then
                    return
                end

                local entry = m_paletteEntries[m_selectedIndex or 0]
                if entry == nil or not m_solidMode then
                    return
                end

                --Engine gate: a stale engine ignores solid=true and would
                --draw a plain (invisible) floor over the map's ground tiles
                --instead - visually silent but destructive. The probe
                --property only exists on builds with the passthrough.
                local okSupport, supportsSolids = pcall(function()
                    return floor.supportsSolidOperations
                end)
                if not okSupport or supportsSolids ~= true then
                    dmhub.Debug("MARKUP:: solid walls need an engine build with ExecutePolygonOperation solid support")
                    return
                end

                if assets.tilesheets[INVISIBLE_TILESHEET_ID] == nil then
                    dmhub.Debug("MARKUP:: the Core invisible tilesheet is not available in this game")
                    return
                end

                local guid = MaterializeEntry(entry)
                if guid == nil then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    return
                end

                local height = GetWallHeightSetting()

                floor:ExecutePolygonOperation{
                    points = {points},
                    wallid = guid,
                    tileid = INVISIBLE_TILESHEET_ID,
                    wallheight = math.floor((height or 0) + 0.5),
                    solid = true,
                    walls = true,
                    floor = true,
                    closed = true,
                }
            end,

            --Delete tool hover: highlight the single wall segment nearest the
            --cursor so the user sees exactly what a click will remove.
            maphover = function(element, loc, point)
                if m_mode ~= "walls" or m_toolId ~= "delete" then
                    ClearDeleteHighlight()
                    return
                end
                local seg = FindNearestDeleteSegment(point)
                if seg == nil then
                    ClearDeleteHighlight()
                    return
                end
                --highlight the span that will actually be cleared (>= the
                --touched edge on short segments) so the preview is honest.
                ShowDeleteHighlight(DeleteSegmentGeometry(seg))
            end,

            --Delete tool click: clear just the segment under the cursor (or the
            --minimum stable span around it - see DeleteSegmentGeometry), leaving
            --the rest of the wall intact, instead of wiping the whole wall.
            mappress = function(element, loc, point)
                if m_mode ~= "walls" or m_toolId ~= "delete" then
                    return
                end
                local floor = game.currentFloor
                if floor == nil then
                    return
                end
                local seg = FindNearestDeleteSegment(point)
                if seg == nil then
                    return
                end

                --Erase a closed box straddling the segment (see
                --DeleteSegmentGeometry): stable on short segments where a
                --hair-thin centerline erase either did nothing or got healed
                --straight back by the wall auto-merge.
                local geom = DeleteSegmentGeometry(seg)
                floor:ExecutePolygonOperation{
                    points = { geom.box },
                    erase = true,
                    eraseInvisibleOnly = true,
                    walls = true,
                    floor = false,
                    closed = true,
                }

                --the highlighted segment is gone now; drop the marker so the
                --next hover recomputes against the updated walls.
                ClearDeleteHighlight()
            end,

            --Release map focus and clear any highlight if the panel goes away
            --while the Delete tool is active.
            destroy = function(element)
                if element.mapfocus then
                    element.mapfocus = false
                end
                ClearDeleteHighlight()
            end,
        },

        children = BuildToolButtons(),
    }

    --Draw-mode toggle: the SAME selected wall type can be drawn either as a
    --thin barrier on a tile boundary or as an area-filling solid block. Sits
    --directly under the tool strip because it changes which tools are shown.
    --(Forward-declared at the top of CreateMarkupEditor.)
    SetDrawMode = function(solid)
        if m_solidMode == solid then
            return
        end
        m_solidMode = solid

        --swaps the tool strip and, if the active tool has no counterpart in
        --the new mode, falls back to that mode's default drawing tool.
        if toolsPanel ~= nil and toolsPanel.valid then
            toolsPanel:FireEvent("rebuildtools")
        end

        --Thin mode's drawing tools ARE the engine building tools, so the
        --shared setting has to be pushed when we land on one. (rebuildtools
        --deliberately never writes settings - it also fires on remote palette
        --changes, where stealing the Building editor's tool would be rude.)
        if not m_solidMode then
            for _,toolInfo in ipairs(ActiveToolInfos()) do
                if toolInfo.id == m_toolId and toolInfo.tool ~= nil then
                    dmhub.SetSettingValue("building:erase", false)
                    dmhub.SetSettingValue("buildingtool", toolInfo.tool)
                end
            end
        end

        if drawModePanel ~= nil and drawModePanel.valid then
            drawModePanel:FireEventTree("refreshdrawmode")
        end
        --the stepper is labelled Wall Height / Block Height by mode.
        if heightPanel ~= nil and heightPanel.valid then
            heightPanel:FireEventTree("refreshheight")
        end

        --Solid mode draws with custom map tools, which need focus and expire
        --after ~1s; register immediately instead of waiting for the think tick.
        if toolsPanel ~= nil and toolsPanel.valid then
            toolsPanel:FireEvent("think")
        end
    end

    local CreateDrawModeChip = function(solid)
        --NOT cond(): it evaluates both arguments, which would build an orphan
        --gui.Panel every time this chip is created.
        local preview
        if solid then
            preview = CreateSolidBlockPreview()
        else
            preview = CreateWallLinePreview(nil)
        end

        return gui.Panel{
            classes = {"markupChip", cond(m_solidMode == solid, "selected")},
            width = "48%",
            height = "100%",
            flow = "vertical",
            bgimage = true,
            pad = 4,
            borderBox = true,
            hmargin = 2,

            data = {
                solid = solid,
            },

            press = function(element)
                --focus first: SetDrawMode registers the custom map tool, and
                --the think handler that does it is focus-gated.
                gui.SetFocus(element)
                SetDrawMode(element.data.solid)
            end,

            refreshdrawmode = function(element)
                element:SetClass("selected", m_solidMode == element.data.solid)
            end,

            --the same miniatures the palette uses, so the difference between
            --a line and a filled region is visible rather than just named.
            preview,

            gui.Label{
                classes = {"sizeXs"},
                text = cond(solid, "Solid Block", "Thin Wall"),
                width = "100%",
                height = "auto",
                textAlignment = "center",
            },
        }
    end

    drawModePanel = gui.Panel{
        width = "96%",
        height = 40,
        halign = "center",
        flow = "horizontal",
        vmargin = 2,

        hover = gui.Tooltip("Thin Wall draws a barrier along the line you trace. Solid Block fills the area you draw with volume: it has a height, can be stood on and climbed, and blocks sight up to its height. Both use the wall type selected above."),

        --openable (door) types are thin-only (their strokes must be wall
        --operations the engine attaches door state to), so the toggle hides.
        create = function(element)
            element:FireEvent("refreshdoorchip")
        end,
        refreshdoorchip = function(element)
            element:SetClass("collapsed", EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]))
        end,

        children = {
            CreateDrawModeChip(false),
            CreateDrawModeChip(true),
        },
    }

    --Wall height stepper: blank ("To Roof") means walls run floor to ceiling;
    --a number is the height in tiles stamped on each placement, letting
    --creatures fly, see, and climb over per the wall height rules. In solid
    --mode the same value is the block's height (To Roof = no standable top).
    heightPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 4,
        flow = "horizontal",

        multimonitor = {"building:specifywallheight", "building:wallheightvalue"},

        events = {
            monitor = function(element)
                element:FireEventTree("refreshheight")
            end,
        },

        hover = gui.Tooltip("Walls with a height can be flown over, seen over, and climbed over by creatures high enough. Walls set To Roof always block. For solid blocks the height is the block's height: a block with a height has a standable top, while To Roof fills floor to ceiling."),

        gui.Label{
            text = "Wall Height:",
            width = "auto",
            height = "auto",
            valign = "center",
            refreshheight = function(element)
                element.text = cond(m_solidMode, "Block Height:", "Wall Height:")
            end,
        },

        gui.Button{
            classes = {"sizeXs"},
            text = "-",
            width = 24,
            valign = "center",
            hmargin = 4,
            events = {
                click = function()
                    local height = GetWallHeightSetting()
                    if height == nil then
                        return
                    end
                    if height <= 1 then
                        SetWallHeightSetting(nil)
                    else
                        SetWallHeightSetting(height - 1)
                    end
                end,
            },
        },

        gui.Label{
            text = "",
            --wide enough for "To Roof" (the no-height label) without wrapping.
            width = 64,
            height = "auto",
            valign = "center",
            textAlignment = "center",
            create = function(element)
                element:FireEvent("refreshheight")
            end,
            refreshheight = function(element)
                local height = GetWallHeightSetting()
                if height == nil then
                    element.text = "To Roof"
                else
                    element.text = string.format("%d", math.floor(height + 0.5))
                end
            end,
        },

        gui.Button{
            classes = {"sizeXs"},
            text = "+",
            width = 24,
            valign = "center",
            hmargin = 4,
            events = {
                click = function()
                    local height = GetWallHeightSetting()
                    if height == nil then
                        SetWallHeightSetting(1)
                    elseif height < 10 then
                        SetWallHeightSetting(height + 1)
                    end
                end,
            },
        },
    }

    local wallsPanel = gui.Panel{
        classes = {cond(m_mode ~= "walls", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m_mode ~= "walls")
        end,

        gui.Label{
            classes = {"bold"},
            text = "Wall Types",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        palettePanel,

        addButton,

        gui.Label{
            classes = {"bold"},
            text = "Draw As",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
            create = function(element)
                element:FireEvent("refreshdoorchip")
            end,
            refreshdoorchip = function(element)
                element:SetClass("collapsed", EntryIsOpenable(m_paletteEntries[m_selectedIndex or 0]))
            end,
        },

        drawModePanel,

        gui.Label{
            classes = {"bold"},
            text = "Tool",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        toolsPanel,

        heightPanel,
    }

    --========================================================================
    --Zones mode UI: zone-type palette (Environmental Keywords), paint tools,
    --and the list of zones on the current floor.
    --========================================================================

    local zonePalettePanel
    local zoneToolsPanel
    local zoneListPanel
    local zonesPanel

    local RefreshZoneUI = function()
        if zonesPanel ~= nil and zonesPanel.valid then
            zonesPanel:FireEventTree("refreshzones")
        end
    end

    --Resolves a zone-type chip to a keyword id, materializing preset chips
    --into real Environmental Keywords on first use (recording the new id back
    --into the palette, like wall presets record their materialized asset).
    local EnsureZoneTypeKeyword = function(index)
        local entry = m_zonePaletteEntries[index or 0]
        if entry == nil then
            return nil
        end

        if entry.keywordid ~= nil then
            if GetKeyword(entry.keywordid) ~= nil then
                return entry.keywordid
            end
            if entry.kind ~= "preset" then
                --keyword chip whose keyword was deleted from the compendium.
                return nil
            end
        end

        if entry.kind == "preset" then
            local preset = ZONE_PRESETS_BY_KEY[entry.key]
            if preset == nil then
                return nil
            end
            local keywordid = MaterializeZonePreset(preset)
            if keywordid == nil then
                return nil
            end
            entry.keywordid = keywordid
            SaveZonePalette(m_zonePaletteEntries)
            return keywordid
        end

        return nil
    end

    local CreateZoneChip = function(index, entry)
        local kw = GetKeyword(entry.keywordid)
        local preset = nil
        if entry.kind == "preset" then
            preset = ZONE_PRESETS_BY_KEY[entry.key]
        end

        local name, color, summary
        if kw ~= nil then
            name = kw.name or "Keyword"
            color = KeywordColor(entry.keywordid, kw)
            summary = KeywordSummary(kw)
        elseif preset ~= nil then
            name = preset.name
            color = preset.color
            summary = preset.summary
        else
            name = "Unknown Keyword"
            color = "#666666"
            summary = "Missing from the compendium"
        end

        return gui.Panel{
            classes = {"markupChip", cond(index == m_zoneSelectedType, "selected")},
            width = "48%",
            height = 56,
            flow = "vertical",
            bgimage = true,
            pad = 6,
            borderBox = true,
            hmargin = 2,
            vmargin = 2,

            data = {
                index = index,
            },

            press = function(element)
                m_zoneSelectedType = element.data.index
                --a fresh type selection paints into that type's existing zone
                --(or a new one), not whatever zone was last targeted.
                m_zoneTargetId = nil
                zonePalettePanel:FireEvent("refreshchips")
                RefreshZoneUI()
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Remove from Palette",
                            click = function()
                                element.popup = nil
                                table.remove(m_zonePaletteEntries, element.data.index)
                                if m_zoneSelectedType > #m_zonePaletteEntries then
                                    m_zoneSelectedType = #m_zonePaletteEntries
                                end
                                if m_zoneSelectedType < 1 then
                                    m_zoneSelectedType = 1
                                end
                                SaveZonePalette(m_zonePaletteEntries)
                            end,
                        },
                    },
                }
            end,

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",

                gui.Panel{
                    width = 14,
                    height = 14,
                    valign = "center",
                    bgimage = true,
                    bgcolor = color,
                    borderWidth = 1,
                    borderColor = "@border",
                },

                gui.Label{
                    classes = {"bold"},
                    text = name,
                    width = "100%-18",
                    height = "auto",
                    hmargin = 4,
                    valign = "center",
                },
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = summary,
                width = "100%",
                height = "auto",
                vmargin = 2,
            },
        }
    end

    zonePalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        --monitorAssets: keyword table edits change chip names/colors/summaries.
        monitorAssets = true,
        multimonitor = {"markup:zonepalette"},

        events = {
            monitor = function(element)
                element:FireEvent("refreshzonepalette")
            end,

            refreshAssets = function(element)
                element:FireEvent("refreshzonepalette")
            end,

            refreshzonepalette = function(element)
                m_zonePaletteEntries = ParseZonePalette()
                if m_zoneSelectedType > #m_zonePaletteEntries then
                    m_zoneSelectedType = #m_zonePaletteEntries
                end
                if m_zoneSelectedType < 1 then
                    m_zoneSelectedType = 1
                end

                local children = {}
                for i,entry in ipairs(m_zonePaletteEntries) do
                    children[#children+1] = CreateZoneChip(i, entry)
                end
                element.children = children
            end,

            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    if chip.data ~= nil and chip.data.index ~= nil then
                        chip:SetClass("selected", chip.data.index == m_zoneSelectedType)
                    end
                end
            end,
        },
    }

    local zoneAddButton
    zoneAddButton = gui.Button{
        classes = {"sizeM"},
        text = "+ Add Zone Type",
        halign = "center",
        vmargin = 4,
        click = function(element)
            local entries = {}

            for _,preset in ipairs(ZONE_PRESETS) do
                local inPalette = false
                for _,entry in ipairs(m_zonePaletteEntries) do
                    if entry.kind == "preset" and entry.key == preset.key then
                        inPalette = true
                        break
                    end
                end

                if not inPalette then
                    entries[#entries+1] = {
                        text = preset.name,
                        click = function()
                            element.popup = nil
                            m_zonePaletteEntries[#m_zonePaletteEntries+1] = {
                                kind = "preset",
                                key = preset.key,
                            }
                            SaveZonePalette(m_zonePaletteEntries)
                        end,
                    }
                end
            end

            local paletteKeywords = {}
            for _,entry in ipairs(m_zonePaletteEntries) do
                if entry.keywordid ~= nil then
                    paletteKeywords[entry.keywordid] = true
                end
            end

            local sortedKeywords = {}
            for k,kw in unhidden_pairs(GetKeywordTable()) do
                if not paletteKeywords[k] then
                    sortedKeywords[#sortedKeywords+1] = {
                        id = k,
                        name = kw.name or k,
                    }
                end
            end
            table.sort(sortedKeywords, function(a, b) return a.name < b.name end)

            for _,info in ipairs(sortedKeywords) do
                entries[#entries+1] = {
                    text = info.name,
                    click = function()
                        element.popup = nil
                        m_zonePaletteEntries[#m_zonePaletteEntries+1] = {
                            kind = "keyword",
                            keywordid = info.id,
                        }
                        SaveZonePalette(m_zonePaletteEntries)
                    end,
                }
            end

            entries[#entries+1] = {
                text = "New Keyword...",
                click = function()
                    element.popup = nil
                    local keywordType = rawget(_G, "EnvironmentalKeyword")
                    if keywordType == nil then
                        dmhub.Debug("MARKUP:: EnvironmentalKeyword type not loaded")
                        return
                    end
                    --created with defaults; flags/modifiers/name are edited in
                    --Compendium > Rules > Environmental Keywords.
                    local kw = keywordType.CreateNew()
                    kw.name = "New Zone Keyword"
                    dmhub.SetAndUploadTableItem(ENVIRONMENTAL_KEYWORDS_TABLE, kw)
                    m_zonePaletteEntries[#m_zonePaletteEntries+1] = {
                        kind = "keyword",
                        keywordid = kw.guid,
                    }
                    SaveZonePalette(m_zonePaletteEntries)
                end,
            }

            element.popup = gui.ContextMenu{
                entries = entries,
            }
        end,
    }

    --Per-zone edit dialog: name, height limit, player visibility.
    local ShowZoneDialog = function(entry)
        local name = entry.name
        local heightText = ""
        if entry.height ~= nil then
            heightText = string.format("%d", entry.height)
        end
        local playerVisible = entry.playerVisible == true

        local dialogPanel
        dialogPanel = gui.Panel{
            id = "MarkupZoneDialog",
            classes = {"framedPanel"},
            width = 440,
            height = "auto",
            pad = 16,
            borderBox = true,
            flow = "vertical",
            styles = ThemeEngine.MergeStyles{
                Styles.Panel,
                MarkupChipStyles(),
            },

            gui.Label{
                classes = {"dialogTitle"},
                text = "Edit Zone",
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Name:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = name,
                    characterLimit = 60,
                    change = function(element)
                        if element.text ~= "" then
                            name = element.text
                        else
                            element.text = name
                        end
                    end,
                },
            },

            gui.Panel{
                classes = {"formStackedRow"},
                gui.Label{
                    classes = {"formStacked"},
                    text = "Affects up to height:",
                },
                gui.Input{
                    classes = {"formStacked"},
                    text = heightText,
                    width = 60,
                    characterLimit = 3,
                    numeric = true,
                    selectAllOnFocus = true,
                    change = function(element)
                        heightText = element.text
                    end,
                },
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = "Height in tiles above the ground. Blank = unlimited, so the zone also affects flying creatures. With a height set, creatures above the zone (e.g. flyers over lava) are unaffected.",
                width = "94%",
                height = "auto",
                halign = "center",
                vmargin = 2,
            },

            gui.Check{
                classes = {"formCheck"},
                text = "Visible to players",
                tooltip = "Players see this zone's stripes and name on their map when they turn on the tile overlay. Off by default: the map art usually already shows the hazard.",
                value = playerVisible,
                change = function(element)
                    playerVisible = element.value
                end,
            },

            gui.Panel{
                width = "100%",
                height = "auto",
                flow = "horizontal",
                halign = "center",
                vmargin = 8,

                gui.Button{
                    classes = {"sizeM"},
                    text = "Cancel",
                    halign = "center",
                    captureEscape = true,
                    escapePriority = EscapePriority.EXIT_DIALOG,
                    events = {
                        click = function(element)
                            element:FireEvent("escape")
                        end,
                        escape = function()
                            gui.CloseModal()
                        end,
                    },
                },

                gui.Button{
                    classes = {"sizeM"},
                    text = "Save",
                    halign = "center",
                    events = {
                        click = function()
                            local floor = game.currentFloor
                            if floor ~= nil then
                                local overrides = {
                                    name = name,
                                    playerVisible = playerVisible,
                                }
                                local n = tonumber(heightText)
                                if n == nil or n < 0 then
                                    overrides.clearHeight = true
                                else
                                    overrides.height = math.floor(n)
                                end
                                floor:SetMarkupZone(entry.zoneid, BuildZoneRecord(entry, overrides))
                                RefreshZoneUI()
                            end
                            gui.CloseModal()
                        end,
                    },
                },
            },
        }

        gui.ShowModal(dialogPanel)
    end

    local CreateZoneRow = function(entry)
        local meta = {}
        meta[#meta+1] = string.format("%d tiles", #entry.locs)
        if entry.height ~= nil then
            meta[#meta+1] = string.format("height %d", entry.height)
        end
        if entry.playerVisible then
            meta[#meta+1] = "visible to players"
        end

        --Rows read as "<type> -- <where>": the collapsed type/custom name
        --(same rule as the map labels) plus the zone's area of the map. The
        --raw numbered record name stays visible in the Edit Zone dialog.
        local displayName = ZoneOverlayLabel(entry)
        local area = ZoneAreaDescription(entry)
        if area ~= nil then
            displayName = displayName .. " -- " .. area
        end
        if #entry.locs == 0 then
            displayName = displayName .. " (empty)"
        end

        return gui.Panel{
            classes = {"markupChip", cond(entry.zoneid == m_zoneTargetId, "selected")},
            width = "96%",
            height = 36,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            data = {
                zoneid = entry.zoneid,
            },

            --NOTE: a bare `tooltip = "..."` arg on a plain gui.Panel eagerly
            --constructs an orphaned tooltip label at create time ("was created
            --but not attached to a parent" on game entry); the idiom for
            --hover tooltips on panels is gui.Tooltip as the hover handler.
            hover = gui.Tooltip("Click to select this zone and show it on the map. Right-click for options."),

            press = function(element)
                m_zoneTargetId = entry.zoneid
                --also select the matching type chip so continued painting
                --extends this zone rather than switching types.
                for i,paletteEntry in ipairs(m_zonePaletteEntries) do
                    if paletteEntry.keywordid ~= nil and paletteEntry.keywordid == entry.keywordid then
                        m_zoneSelectedType = i
                        break
                    end
                end
                zonePalettePanel:FireEvent("refreshchips")
                RefreshZoneUI()
                --pan to the zone and pulse a highlight over its tiles.
                JumpToZone(entry)
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Edit Zone...",
                            click = function()
                                element.popup = nil
                                ShowZoneDialog(entry)
                            end,
                        },
                        {
                            text = "Delete Zone",
                            click = function()
                                element.popup = nil
                                local floor = game.currentFloor
                                if floor ~= nil then
                                    floor:RemoveMarkupZone(entry.zoneid)
                                    if m_zoneTargetId == entry.zoneid then
                                        m_zoneTargetId = nil
                                    end
                                    RefreshZoneUI()
                                end
                            end,
                        },
                    },
                }
            end,

            gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimage = true,
                bgcolor = entry.patternColor,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Panel{
                width = "100%-20",
                height = "100%",
                flow = "vertical",
                hmargin = 4,

                gui.Label{
                    classes = {"bold", "sizeXs"},
                    text = displayName,
                    width = "100%",
                    height = "auto",
                },

                gui.Label{
                    classes = {"fgMuted", "sizeXs"},
                    text = table.concat(meta, ", "),
                    width = "100%",
                    height = "auto",
                },
            },
        }
    end

    local BuildZoneToolButtons = function()
        local result = {}
        for _,toolInfo in ipairs(ZONE_TOOLS) do
            result[#result+1] = gui.Button{
                classes = {"sizeL", "bordered", cond(toolInfo.id == m_zoneToolId, "selected")},
                icon = toolInfo.icon,
                tooltip = toolInfo.help,
                valign = "center",
                hmargin = 2,
                data = {
                    toolid = toolInfo.id,
                },
                press = function(element)
                    m_zoneToolId = element.data.toolid
                    zoneToolsPanel:FireEvent("refreshzonetools")
                    gui.SetFocus(element)
                    --register the custom tool immediately (requires focus, so
                    --after SetFocus) instead of waiting for the next think.
                    zoneToolsPanel:FireEvent("think")
                end,
            }
        end
        return result
    end

    zoneToolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        --keep the custom map tool alive: the engine expires custom tools
        --after ~1s, and every registration returns a fresh event source that
        --must be listened to again.
        thinkTime = 0.3,

        events = {
            refreshzonetools = function(element)
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolid == m_zoneToolId)
                end
            end,

            think = function(element)
                if m_mode ~= "zones" or not ZonesSupported() then
                    return
                end

                local toolInfo = ZoneToolById(m_zoneToolId)
                if toolInfo == nil then
                    return
                end

                if m_markupHud == nil or not m_markupHud.valid or not gui.ChildHasFocus(m_markupHud) then
                    return
                end

                local eventSource = editor:SetMapTool{
                    tool = toolInfo.mapTool,
                    closed = true,
                    expires = 1,
                    stabilization = 0,
                    snapToGrid = true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m_mode ~= "zones" or path == nil then
                    return
                end
                local toolInfo = ZoneToolById(m_zoneToolId)
                if toolInfo == nil then
                    return
                end
                if toolInfo.erase then
                    element:FireEvent("zoneerase", path)
                else
                    element:FireEvent("zonepaint", path)
                end
            end,

            --closed stroke: rasterize to tiles and merge into the target zone
            --of the selected type (creating one when none exists).
            zonepaint = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    if not ok then
                        dmhub.Debug("MARKUP:: zone painting needs an engine build with MapPath points support")
                    end
                    return
                end

                local locs = PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                local keywordid = EnsureZoneTypeKeyword(m_zoneSelectedType)
                if keywordid == nil then
                    dmhub.Debug("MARKUP:: no valid zone type selected; stroke ignored")
                    return
                end

                --what the selected chip calls this type: used to name a new
                --zone (and to heal by name) when the keyword upload hasn't
                --landed locally yet.
                local fallbackInfo = nil
                local paletteEntry = m_zonePaletteEntries[m_zoneSelectedType]
                if paletteEntry ~= nil and paletteEntry.kind == "preset" then
                    local preset = ZONE_PRESETS_BY_KEY[paletteEntry.key]
                    if preset ~= nil then
                        fallbackInfo = { name = preset.name, color = preset.color }
                    end
                end

                --Contiguity-based painting: the stroke joins the same-type
                --zones it overlaps or borders (bridging strokes unify them
                --into one record); a stroke touching none becomes its own
                --new zone. Non-contiguous results are auto-split, so one
                --zone record = one contiguous region on the map.
                local strokeSet = {}
                for _,l in ipairs(locs) do
                    strokeSet[ZoneLocKey(l.x, l.y)] = true
                end

                local touched = {}
                for _,entry in ipairs(ZonesOnFloor(floor.floorid)) do
                    if entry.keywordid == keywordid then
                        for _,l in ipairs(entry.locs) do
                            if strokeSet[ZoneLocKey(l.x, l.y)]
                                or strokeSet[ZoneLocKey(l.x + 1, l.y)]
                                or strokeSet[ZoneLocKey(l.x - 1, l.y)]
                                or strokeSet[ZoneLocKey(l.x, l.y + 1)]
                                or strokeSet[ZoneLocKey(l.x, l.y - 1)] then
                                touched[#touched+1] = entry
                                break
                            end
                        end
                    end
                end

                if #touched == 0 then
                    --a (rare) self-intersecting freehand stroke can rasterize
                    --to several separate regions: one zone per region.
                    local components = SplitContiguousComponents(locs)
                    dmhub.BeginTransaction()
                    for i,component in ipairs(components) do
                        local zoneid = CreateZone(keywordid, component, fallbackInfo)
                        if i == 1 then
                            m_zoneTargetId = zoneid
                        end
                    end
                    dmhub.EndTransaction()
                else
                    --primary keeps its identity/settings: the targeted zone
                    --when the stroke touches it, else the largest touched.
                    local primary = nil
                    for _,entry in ipairs(touched) do
                        if primary == nil or #entry.locs > #primary.locs then
                            primary = entry
                        end
                    end
                    for _,entry in ipairs(touched) do
                        if entry.zoneid == m_zoneTargetId then
                            primary = entry
                        end
                    end

                    local seen = {}
                    local newLocs = {}
                    local AddLoc = function(x, y)
                        local key = ZoneLocKey(x, y)
                        if not seen[key] then
                            seen[key] = true
                            newLocs[#newLocs+1] = { x = x, y = y }
                        end
                    end
                    for _,entry in ipairs(touched) do
                        for _,l in ipairs(entry.locs) do
                            AddLoc(l.x, l.y)
                        end
                    end
                    for _,l in ipairs(locs) do
                        AddLoc(l.x, l.y)
                    end

                    dmhub.BeginTransaction()
                    for _,entry in ipairs(touched) do
                        if entry.zoneid ~= primary.zoneid then
                            floor:RemoveMarkupZone(entry.zoneid)
                        end
                    end
                    WriteZoneLocsSplitting(floor, primary, newLocs)
                    dmhub.EndTransaction()

                    m_zoneTargetId = primary.zoneid
                end

                RefreshZoneUI()
            end,

            --eraser stroke: remove the region's tiles from every zone on the
            --floor; zones left empty are deleted. One undo step per stroke.
            zoneerase = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    return
                end

                local locs = PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                local remove = {}
                for _,l in ipairs(locs) do
                    remove[ZoneLocKey(l.x, l.y)] = true
                end

                local edits = {}
                for _,entry in ipairs(ZonesOnFloor(floor.floorid)) do
                    local kept = {}
                    local removedAny = false
                    for _,l in ipairs(entry.locs) do
                        if remove[ZoneLocKey(l.x, l.y)] then
                            removedAny = true
                        else
                            kept[#kept+1] = { x = l.x, y = l.y }
                        end
                    end
                    if removedAny then
                        edits[#edits+1] = { entry = entry, kept = kept }
                    end
                end

                if #edits == 0 then
                    return
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    --deletes emptied zones, and splits a zone the erase cut
                    --in half into separate records (one per region).
                    WriteZoneLocsSplitting(floor, edit.entry, edit.kept)
                    if #edit.kept == 0 and m_zoneTargetId == edit.entry.zoneid then
                        m_zoneTargetId = nil
                    end
                end
                dmhub.EndTransaction()

                RefreshZoneUI()
            end,
        },

        children = BuildZoneToolButtons(),
    }

    zoneListPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --cheap change detection: the records (any client) or the current
        --floor changing rebuilds the list.
        thinkTime = 0.5,

        data = {
            seq = nil,
            floorid = nil,
        },

        events = {
            think = function(element)
                if m_mode ~= "zones" or not ZonesSupported() then
                    return
                end
                if dmhub.markupZonesSeq ~= element.data.seq or game.currentFloorId ~= element.data.floorid then
                    element:FireEvent("refreshzones")
                end
            end,

            refreshzones = function(element)
                if not ZonesSupported() then
                    return
                end

                --split any legacy multi-region records first, THEN snapshot
                --the sequence: the snapshot includes the normalization writes,
                --so the think loop doesn't immediately re-fire this event.
                NormalizeZonesOnFloor(game.currentFloorId)

                element.data.seq = dmhub.markupZonesSeq
                element.data.floorid = game.currentFloorId

                local children = {}
                if element.data.floorid ~= nil then
                    for _,entry in ipairs(ZonesOnFloor(element.data.floorid)) do
                        children[#children+1] = CreateZoneRow(entry)
                    end
                end

                if #children == 0 then
                    children[#children+1] = gui.Label{
                        classes = {"fgMuted", "sizeXs"},
                        text = "No zones on this floor yet. Pick a zone type and paint on the map.",
                        width = "90%",
                        height = "auto",
                        halign = "center",
                        vmargin = 4,
                        textAlignment = "center",
                    }
                end

                element.children = children
            end,
        },
    }

    zonesPanel = gui.Panel{
        classes = {cond(m_mode ~= "zones", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m_mode ~= "zones")
            if m_mode == "zones" then
                zonePalettePanel:FireEvent("refreshzonepalette")
                zoneListPanel:FireEvent("refreshzones")
            end
        end,

        gui.Label{
            classes = {"fgMuted", cond(ZonesSupported(), "collapsed")},
            text = "Zones need an engine build with markup zone support.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        gui.Label{
            classes = {"bold"},
            text = "Zone Types",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        zonePalettePanel,

        zoneAddButton,

        gui.Label{
            classes = {"bold"},
            text = "Tool",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        zoneToolsPanel,

        gui.Label{
            classes = {"bold"},
            text = "Zones on This Floor",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        zoneListPanel,
    }

    --========================================================================
    --Footsteps mode UI: map default dropdown, the fixed surface-family
    --palette (with sound previews), paint tools, and the per-floor list.
    --========================================================================

    local footstepPalettePanel
    local footstepToolsPanel
    local footstepListPanel
    local footstepsPanel
    local footstepDefaultDropdown

    local RefreshFootstepUI = function()
        if footstepsPanel ~= nil and footstepsPanel.valid then
            footstepsPanel:FireEventTree("refreshfootsteps")
        end
    end

    local CreateFootstepChip = function(surfaceInfo)
        return gui.Panel{
            classes = {"markupChip", cond(surfaceInfo.id == m_footstepSelected, "selected")},
            width = "48%",
            height = 30,
            flow = "horizontal",
            bgimage = true,
            pad = 6,
            borderBox = true,
            hmargin = 2,
            vmargin = 2,

            data = {
                surfaceid = surfaceInfo.id,
            },

            press = function(element)
                m_footstepSelected = element.data.surfaceid
                footstepPalettePanel:FireEvent("refreshchips")
            end,

            gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimage = true,
                bgcolor = SurfaceColor(surfaceInfo.id),
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = surfaceInfo.text,
                width = "100%-40",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },

            gui.Panel{
                width = 16,
                height = 16,
                valign = "center",
                halign = "right",
                bgimage = "ui-icons/ph-play-fill.png",
                bgcolor = "@fgMuted",
                hover = gui.Tooltip("Preview this footstep sound."),
                press = function()
                    PlaySurfaceSample(surfaceInfo)
                end,
            },
        }
    end

    footstepPalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        events = {
            refreshchips = function(element)
                for _,chip in ipairs(element.children) do
                    if chip.data ~= nil and chip.data.surfaceid ~= nil then
                        chip:SetClass("selected", chip.data.surfaceid == m_footstepSelected)
                    end
                end
            end,
        },

        children = (function()
            local chips = {}
            for _,info in ipairs(SurfaceRegistry()) do
                chips[#chips+1] = CreateFootstepChip(info)
            end
            return chips
        end)(),
    }

    local BuildFootstepDefaultOptions = function()
        local options = {
            --0 = no default: tiles keep whatever surface their art carries
            --(Generic where none). Any other choice overrides tile-derived
            --surfaces map-wide; painted footstep regions and water still win.
            { id = "0", text = "None - Use Tile Surfaces" },
        }
        for _,info in ipairs(SurfaceRegistry()) do
            options[#options+1] = { id = tostring(info.id), text = info.text }
        end
        return options
    end

    footstepDefaultDropdown = gui.Dropdown{
        width = 200,
        height = 26,
        idChosen = tostring(math.floor(tonumber(g_footstepDefaultSetting:Get()) or 0)),
        options = BuildFootstepDefaultOptions(),
        change = function(element)
            g_footstepDefaultSetting:Set(tonumber(element.idChosen) or 0)
        end,
    }

    local footstepDefaultRow = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",

        --re-sync on remote changes and on map switches (the map's value is
        --the effective value; the monitor fires for both).
        multimonitor = {"markup:footstepdefault"},

        events = {
            monitor = function(element)
                local current = tostring(math.floor(tonumber(g_footstepDefaultSetting:Get()) or 0))
                if footstepDefaultDropdown.idChosen ~= current then
                    footstepDefaultDropdown.idChosen = current
                end
            end,
        },

        footstepDefaultDropdown,

        gui.Panel{
            width = 18,
            height = 18,
            valign = "center",
            hmargin = 8,
            bgimage = "ui-icons/ph-play-fill.png",
            bgcolor = "@fgMuted",
            hover = gui.Tooltip("Preview the default footstep sound."),
            press = function()
                local defaultSurface = math.floor(tonumber(g_footstepDefaultSetting:Get()) or 0)
                PlaySurfaceSample(SurfaceInfoById(defaultSurface))
            end,
        },
    }

    local BuildFootstepToolButtons = function()
        local result = {}
        for _,toolInfo in ipairs(FOOTSTEP_TOOLS) do
            result[#result+1] = gui.Button{
                classes = {"sizeL", "bordered", cond(toolInfo.id == m_footstepToolId, "selected")},
                icon = toolInfo.icon,
                tooltip = toolInfo.help,
                valign = "center",
                hmargin = 2,
                data = {
                    toolid = toolInfo.id,
                },
                press = function(element)
                    m_footstepToolId = element.data.toolid
                    footstepToolsPanel:FireEvent("refreshfoottools")
                    gui.SetFocus(element)
                    --register the custom tool immediately (requires focus, so
                    --after SetFocus) instead of waiting for the next think.
                    footstepToolsPanel:FireEvent("think")
                end,
            }
        end
        return result
    end

    footstepToolsPanel = gui.Panel{
        width = "96%",
        height = 48,
        halign = "center",
        flow = "horizontal",

        --keep the custom map tool alive: the engine expires custom tools
        --after ~1s, and every registration returns a fresh event source that
        --must be listened to again.
        thinkTime = 0.3,

        events = {
            refreshfoottools = function(element)
                for _,child in ipairs(element.children) do
                    child:SetClass("selected", child.data.toolid == m_footstepToolId)
                end
            end,

            think = function(element)
                if m_mode ~= "surfaces" or not ZonesSupported() then
                    return
                end

                local toolInfo = FootstepToolById(m_footstepToolId)
                if toolInfo == nil then
                    return
                end

                if m_markupHud == nil or not m_markupHud.valid or not gui.ChildHasFocus(m_markupHud) then
                    return
                end

                local eventSource = editor:SetMapTool{
                    tool = toolInfo.mapTool,
                    closed = true,
                    expires = 1,
                    stabilization = 0,
                    snapToGrid = true,
                }
                if eventSource ~= nil then
                    eventSource:Listen(element)
                end
            end,

            tool = function(element, path)
                if m_mode ~= "surfaces" or path == nil then
                    return
                end
                local toolInfo = FootstepToolById(m_footstepToolId)
                if toolInfo == nil then
                    return
                end
                if toolInfo.erase then
                    element:FireEvent("footerase", path)
                else
                    element:FireEvent("footpaint", path)
                end
            end,

            --closed stroke: rasterize to tiles, strip them from every other
            --surface family (exclusive per tile), and merge them into the
            --selected family's one record on this floor.
            footpaint = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    if not ok then
                        dmhub.Debug("MARKUP:: surface painting needs an engine build with MapPath points support")
                    end
                    return
                end

                local locs = PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                if SurfaceInfoById(m_footstepSelected) == nil then
                    dmhub.Debug("MARKUP:: no valid footstep surface selected; stroke ignored")
                    return
                end

                local strokeSet = {}
                for _,l in ipairs(locs) do
                    strokeSet[ZoneLocKey(l.x, l.y)] = true
                end

                local selectedLocs = nil
                local edits = {}
                for _,entry in ipairs(SurfacesOnFloor(floor.floorid)) do
                    if entry.surface == m_footstepSelected then
                        selectedLocs = entry.locs
                    else
                        local kept = {}
                        local removedAny = false
                        for _,l in ipairs(entry.locs) do
                            if strokeSet[ZoneLocKey(l.x, l.y)] then
                                removedAny = true
                            else
                                kept[#kept+1] = { x = l.x, y = l.y }
                            end
                        end
                        if removedAny then
                            edits[#edits+1] = { surface = entry.surface, locs = kept }
                        end
                    end
                end

                local seen = {}
                local newLocs = {}
                local AddLoc = function(x, y)
                    local key = ZoneLocKey(x, y)
                    if not seen[key] then
                        seen[key] = true
                        newLocs[#newLocs+1] = { x = x, y = y }
                    end
                end
                for _,l in ipairs(selectedLocs or {}) do
                    AddLoc(l.x, l.y)
                end
                for _,l in ipairs(locs) do
                    AddLoc(l.x, l.y)
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    WriteSurfaceLocs(floor, edit.surface, edit.locs)
                end
                WriteSurfaceLocs(floor, m_footstepSelected, newLocs)
                dmhub.EndTransaction()

                RefreshFootstepUI()
            end,

            --eraser stroke: clear the region's tiles from every surface
            --family on the floor. One undo step per stroke.
            footerase = function(element, path)
                local floor = game.currentFloor
                if floor == nil or not ZonesSupported() then
                    return
                end

                local ok, points = pcall(function()
                    return path.points
                end)
                if not ok or points == nil or #points < 6 then
                    return
                end

                local locs = PolygonToLocs(points)
                if #locs == 0 then
                    return
                end

                local remove = {}
                for _,l in ipairs(locs) do
                    remove[ZoneLocKey(l.x, l.y)] = true
                end

                local edits = {}
                for _,entry in ipairs(SurfacesOnFloor(floor.floorid)) do
                    local kept = {}
                    local removedAny = false
                    for _,l in ipairs(entry.locs) do
                        if remove[ZoneLocKey(l.x, l.y)] then
                            removedAny = true
                        else
                            kept[#kept+1] = { x = l.x, y = l.y }
                        end
                    end
                    if removedAny then
                        edits[#edits+1] = { surface = entry.surface, locs = kept }
                    end
                end

                if #edits == 0 then
                    return
                end

                dmhub.BeginTransaction()
                for _,edit in ipairs(edits) do
                    WriteSurfaceLocs(floor, edit.surface, edit.locs)
                end
                dmhub.EndTransaction()

                RefreshFootstepUI()
            end,
        },

        children = BuildFootstepToolButtons(),
    }

    local CreateFootstepRow = function(entry)
        return gui.Panel{
            classes = {"markupChip"},
            width = "96%",
            height = 30,
            halign = "center",
            flow = "horizontal",
            bgimage = true,
            pad = 4,
            borderBox = true,
            vmargin = 1,

            hover = gui.Tooltip("Click to select this surface and show it on the map. Right-click for options."),

            press = function(element)
                m_footstepSelected = entry.surface
                footstepPalettePanel:FireEvent("refreshchips")
                JumpToZone(entry)
            end,

            rightClick = function(element)
                element.popup = gui.ContextMenu{
                    entries = {
                        {
                            text = "Clear From This Floor",
                            click = function()
                                element.popup = nil
                                local floor = game.currentFloor
                                if floor ~= nil then
                                    WriteSurfaceLocs(floor, entry.surface, {})
                                    RefreshFootstepUI()
                                end
                            end,
                        },
                    },
                }
            end,

            gui.Panel{
                width = 14,
                height = 14,
                valign = "center",
                bgimage = true,
                bgcolor = entry.patternColor,
                borderWidth = 1,
                borderColor = "@border",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = entry.name,
                width = "50%",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },

            gui.Label{
                classes = {"fgMuted", "sizeXs"},
                text = string.format("%d tiles", #entry.locs),
                width = "auto",
                height = "auto",
                valign = "center",
            },
        }
    end

    footstepListPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        --cheap change detection: the records (any client) or the current
        --floor changing rebuilds the list.
        thinkTime = 0.5,

        data = {
            seq = nil,
            floorid = nil,
        },

        events = {
            think = function(element)
                if m_mode ~= "surfaces" or not ZonesSupported() then
                    return
                end
                if dmhub.markupZonesSeq ~= element.data.seq or game.currentFloorId ~= element.data.floorid then
                    element:FireEvent("refreshfootsteps")
                end
            end,

            refreshfootsteps = function(element)
                if not ZonesSupported() then
                    return
                end

                element.data.seq = dmhub.markupZonesSeq
                element.data.floorid = game.currentFloorId

                local children = {}
                if element.data.floorid ~= nil then
                    for _,entry in ipairs(SurfacesOnFloor(element.data.floorid)) do
                        children[#children+1] = CreateFootstepRow(entry)
                    end
                end

                if #children == 0 then
                    children[#children+1] = gui.Label{
                        classes = {"fgMuted", "sizeXs"},
                        text = "No footstep surfaces painted on this floor yet. Pick a surface and paint on the map.",
                        width = "90%",
                        height = "auto",
                        halign = "center",
                        vmargin = 4,
                        textAlignment = "center",
                    }
                end

                element.children = children
            end,
        },
    }

    footstepsPanel = gui.Panel{
        classes = {cond(m_mode ~= "surfaces", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m_mode ~= "surfaces")
            if m_mode == "surfaces" then
                footstepPalettePanel:FireEvent("refreshchips")
                footstepListPanel:FireEvent("refreshfootsteps")
            end
        end,

        gui.Label{
            classes = {"fgMuted", cond(ZonesSupported(), "collapsed")},
            text = "Footsteps need an engine build with markup zone support.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        gui.Label{
            classes = {"bold"},
            text = "Map Default",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        footstepDefaultRow,

        gui.Label{
            classes = {"fgMuted", "sizeXs"},
            text = "What this map's ground sounds like, overriding any surface the map's tiles carry. Painted regions override it; water always sounds like water, and flying creatures never make footsteps.",
            width = "94%",
            height = "auto",
            halign = "center",
            vmargin = 2,
        },

        gui.Label{
            classes = {"bold"},
            text = "Paint Surface",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        footstepPalettePanel,

        gui.Label{
            classes = {"bold"},
            text = "Tool",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        footstepToolsPanel,

        gui.Label{
            classes = {"bold"},
            text = "Footsteps on This Floor",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        footstepListPanel,
    }

    --========================================================================
    --Elevation mode UI: for now a straight clone of the Elevation Editor dock
    --panel (DMHub Core Panels/ElevationPanel.lua). It drives the very same
    --"heightmap:*" settings, so the two panels stay in sync automatically;
    --what makes painting actually happen from here is the focus-gated
    --GetHeightEditingInfo chain at the bottom of this file.
    --========================================================================

    --Every form-style setting in this mode uses the stacked (label-above-
    --control) layout, matching the Elevation Editor.
    local elevationStackedOpts = {stacked = true}

    local function SlopeHintVisible()
        local tool = dmhub.GetSettingValue("heightmaptool")
        local toolUsesGradient = tool == "rectangle" or tool == "oval" or tool == "shape"
        return toolUsesGradient and dmhub.GetSettingValue("heightmap:gradient") == "slope"
    end

    --The brush strip is owned by DMHub Core Panels/Brush.lua; that module
    --exports it as a global for us (mod.shared is per-module). rawget: reading
    --an undeclared global errors in the DMHub Lua runtime.
    local elevationBrushPanel = nil
    local brushEditorPanel = rawget(_G, "BrushEditorPanel")
    if brushEditorPanel ~= nil then
        elevationBrushPanel = gui.Panel{
            classes = {cond(dmhub.GetSettingValue("heightmaptool") ~= "brush", "collapsed")},
            width = "auto",
            height = "auto",
            halign = "center",
            monitor = "heightmaptool",
            events = {
                monitor = function(element)
                    element:SetClass("collapsed", dmhub.GetSettingValue("heightmaptool") ~= "brush")
                end,
            },
            brushEditorPanel("heightmapbrush"),
        }
    end

    --The editors themselves, hidden wholesale for non-patrons.
    --Built into an explicit list rather than a table literal: the brush strip
    --is nil when the Brush.lua export is missing, and a nil in the array part
    --of a literal would silently truncate every child after it.
    local elevationChildren = {}
    local AddElevationChild = function(child)
        if child ~= nil then
            elevationChildren[#elevationChildren+1] = child
        end
    end

    AddElevationChild(gui.Label{
        classes = {"bold"},
        text = "Tool",
        width = "96%",
        height = "auto",
        halign = "center",
        vmargin = 4,
    })

    AddElevationChild(CreateSettingsEditor("heightmaptool"))
    AddElevationChild(elevationBrushPanel)
    AddElevationChild(CreateSettingsEditor("heightmap:height", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:blend", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:opacity", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:gradient", elevationStackedOpts))

    AddElevationChild(gui.Label{
        classes = {"fgMuted", cond(not SlopeHintVisible(), "collapsed")},
        text = "Right-click while drawing to change direction",
        width = "90%",
        height = "auto",
        halign = "left",
        textAlignment = "center",
        fontSize = 12,
        italics = true,
        vmargin = 0,
        multimonitor = {"heightmap:gradient", "heightmaptool"},
        monitor = function(element)
            element:SetClass("collapsed", not SlopeHintVisible())
        end,
    })

    AddElevationChild(CreateSettingsEditor("heightmap:overlaytype", elevationStackedOpts))
    AddElevationChild(CreateSettingsEditor("heightmap:opacitysetting", elevationStackedOpts))

    local elevationEditorsPanel = gui.Panel{
        classes = {cond(not ElevationSupported(), "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        children = elevationChildren,
    }

    local elevationPanel = gui.Panel{
        classes = {cond(m_mode ~= "elevation", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        markupmode = function(element)
            element:SetClass("collapsed", m_mode ~= "elevation")
        end,

        gui.Label{
            classes = {"fgMuted", cond(ElevationSupported(), "collapsed")},
            text = "Elevation editing is a patron feature.",
            width = "90%",
            height = "auto",
            halign = "center",
            vmargin = 8,
            textAlignment = "center",
        },

        elevationEditorsPanel,
    }

    --========================================================================
    --Props mode UI: the prop-type palette, the selected type's properties
    --(bound to the map-selected prop when there is one, else to the defaults
    --for new placements), and click-to-place via map focus. Moving/selecting
    --placed props is the engine object tool, scoped by the object-editing
    --filter to just the selected type.
    --========================================================================

    local propPalettePanel
    local propPropertiesPanel
    local propsPanel

    local PropTypeInfo = function(typeid)
        for _,info in ipairs(PROP_TYPES) do
            if info.id == typeid then
                return info
            end
        end
        return nil
    end

    local PropKeywordFor = function(typeid)
        return "markup:" .. tostring(typeid)
    end

    --All placed markup props of the given type on the current floor.
    local PropsOnCurrentFloor = function(typeid)
        local result = {}
        local floor = game.currentFloor
        if floor == nil then
            return result
        end
        local keyword = PropKeywordFor(typeid)
        for _,obj in pairs(floor.objects) do
            local kw = obj.keywords
            if kw ~= nil and kw[keyword] ~= nil then
                result[#result+1] = obj
            end
        end
        return result
    end

    --The placed prop bound to the property editors, if it still exists and
    --matches the selected type.
    local GetEditingProp = function()
        if m_props.editingId == nil or m_props.selected == nil then
            return nil
        end
        local floor = game.currentFloor
        if floor == nil then
            return nil
        end
        local obj = floor:GetObject(m_props.editingId)
        if obj == nil then
            return nil
        end
        local kw = obj.keywords
        if kw == nil or kw[PropKeywordFor(m_props.selected)] == nil then
            return nil
        end
        return obj
    end

    --Component property writes want color userdata, not hex strings; the
    --defaults store whatever the picker last produced, so normalize on write.
    local ToColorValue = function(val)
        if type(val) == "string" then
            local ok, result = pcall(function() return core.Color(val) end)
            if ok and result ~= nil then
                return result
            end
            return core.Color("#ffffff")
        end
        return val
    end

    --Read a component field's live value (component.fields carries the
    --engine's reflected descriptors).
    local GetComponentFieldValue = function(comp, id)
        for _,f in ipairs(comp.fields) do
            if f.id == id then
                return f.currentValue
            end
        end
        return nil
    end

    local RefreshPropUI = function()
        if propsPanel ~= nil and propsPanel.valid then
            propsPanel:FireEventTree("refreshprops")
        end
    end

    --Apply a light property: always into the session defaults (the next
    --placement inherits it), and onto the map-selected light when one is
    --bound to the editors.
    local ApplyLightProperty = function(id, value)
        m_props.defaults.light[id] = value
        if m_props.selected ~= "light" then
            return
        end
        local obj = GetEditingProp()
        if obj == nil then
            return
        end
        local light = obj:GetComponent("Light")
        if light ~= nil then
            light:SetAndUploadProperties{ [id] = value }
        end
    end

    --The value feeding a light editor: the selected light's, else the
    --session default.
    local ReadLightProperty = function(id)
        if m_props.selected == "light" then
            local obj = GetEditingProp()
            if obj ~= nil then
                local light = obj:GetComponent("Light")
                if light ~= nil then
                    local value = GetComponentFieldValue(light, id)
                    if value ~= nil then
                        return value
                    end
                end
            end
        end
        return m_props.defaults.light[id]
    end

    --Place a new prop of the given type at a map point. One upload: spawn
    --locally, configure the components, then MarkUndo + Upload.
    local PlaceProp = function(typeid, point)
        local floor = game.currentFloor
        if floor == nil then
            return
        end

        local propInfo = PropTypeInfo(typeid)
        if propInfo == nil or not propInfo.implemented then
            return
        end

        --Hard gate: without the engine's object-editing filter a placed prop
        --is invisible AND unselectable, i.e. unremovable through the UI.
        if not PropsSupported() then
            return
        end

        local obj = floor:SpawnObjectLocal(PROP_BASE_OBJECT_ID, { posx = point.x, posy = point.y })
        if obj == nil then
            dmhub.Debug("MARKUP:: could not spawn the prop base object; is the Core asset missing?")
            return
        end

        local coreComponent = obj:GetComponent("Core")
        if coreComponent ~= nil then
            coreComponent:SetProperty("keywords", { MARKUP_PROP_KEYWORD, PropKeywordFor(typeid) })
        end

        obj.name = "Markup " .. propInfo.text
        --locked: inert to the object tool everywhere except this tab (the
        --object-editing filter treats matching props as unlocked).
        obj.locked = true

        if typeid == "light" then
            local light = obj:GetComponent("Light")
            if light ~= nil then
                local d = m_props.defaults.light
                light:SetProperty("color", ToColorValue(d.color))
                light:SetProperty("intensity", d.intensity)
                light:SetProperty("radius", d.radius)
                light:SetProperty("flicker", d.flicker)
            end
        end

        obj:MarkUndo()
        obj:Upload()

        track("markup_prop_place", { prop = typeid })

        RefreshPropUI()
    end

    local CreatePropChip = function(propInfo)
        return gui.Panel{
            classes = {"markupChip", cond(propInfo.id == m_props.selected, "selected")},
            width = "48%",
            height = 34,
            flow = "horizontal",
            bgimage = true,
            pad = 6,
            borderBox = true,
            hmargin = 2,
            vmargin = 2,

            data = {
                propid = propInfo.id,
            },

            hover = gui.Tooltip(propInfo.summary),

            press = function(element)
                m_props.selected = element.data.propid
                m_props.editingId = nil
                dmhub.ClearSelectedObjects()
                RefreshPropUI()
                --panel focus is what turns the object-editing filter on.
                gui.SetFocus(element)
                --Take map focus NOW rather than waiting up to thinkTime (0.3s)
                --for the next tick: without this, a click on the map in the
                --moment right after picking a type lands with no map focus and
                --silently does nothing. Must run after SetFocus - the think
                --handler gates on the panel having focus. (Same reason the
                --footstep/wall tool strips re-fire think on press.)
                if propsPanel ~= nil and propsPanel.valid then
                    propsPanel:FireEvent("think")
                end
            end,

            gui.Panel{
                width = 18,
                height = 18,
                valign = "center",
                bgimage = propInfo.icon,
                bgcolor = "@fg",
            },

            gui.Label{
                classes = {"bold", "sizeXs"},
                text = propInfo.text,
                width = "100%-26",
                height = "auto",
                hmargin = 4,
                valign = "center",
            },
        }
    end

    --NOTE the palette and the property editors render even when the engine
    --half is missing (PropsSupported false) - only PLACEMENT is gated. What a
    --stale engine breaks is showing/selecting/dragging placed props, so
    --placing would strand them; browsing the types and setting defaults is
    --harmless, and keeps the tab legible instead of a bare error line.
    propPalettePanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "horizontal",
        wrap = true,

        events = {
            refreshprops = function(element)
                for _,chip in ipairs(element.children) do
                    if chip.data ~= nil and chip.data.propid ~= nil then
                        chip:SetClass("selected", chip.data.propid == m_props.selected)
                    end
                end
            end,
        },

        children = (function()
            local chips = {}
            for _,info in ipairs(PROP_TYPES) do
                chips[#chips+1] = CreatePropChip(info)
            end
            return chips
        end)(),
    }

    local CreateLightSliderRow = function(labelText, fieldId, minValue, maxValue)
        return gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = labelText,
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.Slider{
                value = tonumber(m_props.defaults.light[fieldId]) or minValue,
                minValue = minValue,
                maxValue = maxValue,
                sliderWidth = 150,
                labelWidth = 40,
                valign = "center",
                data = {
                    refreshing = false,
                },
                events = {
                    --programmatically setting .value fires change; guard so
                    --refreshes don't echo back into uploads.
                    refreshprops = function(element)
                        element.data.refreshing = true
                        element.value = tonumber(ReadLightProperty(fieldId)) or minValue
                        element.data.refreshing = false
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyLightProperty(fieldId, element.value)
                    end,
                },
            },
        }
    end

    propPropertiesPanel = gui.Panel{
        classes = {cond(m_props.selected ~= "light", "collapsed")},
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",

        events = {
            refreshprops = function(element)
                element:SetClass("collapsed", m_props.selected ~= "light")
            end,
        },

        --which light the editors are bound to.
        gui.Label{
            classes = {"fgMuted", "sizeXs"},
            text = "Defaults for new lights. Click a placed light on the map to edit it.",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,

            refreshprops = function(element)
                if GetEditingProp() ~= nil then
                    element.text = "Editing the selected light."
                else
                    element.text = "Defaults for new lights. Click a placed light on the map to edit it."
                end
            end,
        },

        gui.Panel{
            width = "96%",
            height = 26,
            halign = "center",
            flow = "horizontal",
            vmargin = 2,

            gui.Label{
                classes = {"sizeXs"},
                text = "Color:",
                width = 80,
                height = "auto",
                valign = "center",
            },

            gui.ColorPicker{
                width = 24,
                height = 18,
                valign = "center",
                borderWidth = 1,
                borderColor = "@border",
                value = m_props.defaults.light.color,
                data = {
                    refreshing = false,
                },
                events = {
                    refreshprops = function(element)
                        element.data.refreshing = true
                        element.value = ReadLightProperty("color")
                        element.data.refreshing = false
                    end,
                    change = function(element)
                        if element.data.refreshing then
                            return
                        end
                        ApplyLightProperty("color", ToColorValue(element.value))
                    end,
                },
            },
        },

        CreateLightSliderRow("Brightness:", "intensity", 0, 2),
        CreateLightSliderRow("Radius:", "radius", 0, 25),
        CreateLightSliderRow("Flicker:", "flicker", 0, 1),

        gui.Button{
            classes = {"sizeM", "collapsed"},
            text = "Delete Light",
            halign = "center",
            vmargin = 4,

            refreshprops = function(element)
                element:SetClass("collapsed", GetEditingProp() == nil)
            end,

            click = function(element)
                local obj = GetEditingProp()
                if obj == nil then
                    return
                end
                dmhub.ClearSelectedObjects()
                m_props.editingId = nil
                obj:Destroy()
                track("markup_prop_delete", { prop = m_props.selected })
                RefreshPropUI()
            end,
        },
    }

    propsPanel = gui.Panel{
        classes = {cond(m_mode ~= "props", "collapsed")},
        width = "100%",
        height = "auto",
        flow = "vertical",

        --keeps map focus in sync with mode/focus/type; map focus is the
        --placement input surface (mappress) and suppresses token selection
        --while the tab is armed. The engine object tool is NOT suppressed by
        --map focus, which is exactly what lets placed props drag normally.
        thinkTime = 0.3,

        events = {
            markupmode = function(element)
                element:SetClass("collapsed", m_mode ~= "props")
                if m_mode == "props" then
                    element:FireEventTree("refreshprops")
                end
                --grab (or release) map focus on the mode switch itself, so the
                --first map click after switching tabs is not swallowed by the
                --think interval. Also releases promptly when switching away.
                element:FireEvent("think")
            end,

            think = function(element)
                local want = m_mode == "props" and PropsSupported()
                    and m_props.selected ~= nil
                    and m_markupHud ~= nil and m_markupHud.valid
                    and gui.ChildHasFocus(m_markupHud)

                if want then
                    if not element.mapfocus then
                        element.mapfocus = true
                    end
                else
                    if element.mapfocus then
                        element.mapfocus = false
                    end
                end
            end,

            mappress = function(element, loc, point)
                if m_mode ~= "props" or m_props.selected == nil then
                    return
                end

                --clicks on or near an existing prop of the selected type are
                --select/drag (the engine object tool owns those); only place
                --on empty ground.
                for _,obj in ipairs(PropsOnCurrentFloor(m_props.selected)) do
                    local dx = obj.x - point.x
                    local dy = obj.y - point.y
                    if dx*dx + dy*dy < 0.36 then
                        return
                    end
                end

                PlaceProp(m_props.selected, point)
            end,

            destroy = function(element)
                if element.mapfocus then
                    element.mapfocus = false
                end
            end,
        },

        children = {
            --NOT muted: this explains why clicking the map does nothing, and
            --muted small text got missed in exactly that situation.
            gui.Label{
                classes = {"bold", "sizeXs", cond(PropsSupported(), "collapsed")},
                text = "Placing props is DISABLED: this build cannot show or move placed props yet, so they would be stranded invisibly. Rebuild the app to enable it. The settings below still work.",
                width = "90%",
                height = "auto",
                halign = "center",
                vmargin = 8,
                textAlignment = "center",
            },

            propPalettePanel,
            propPropertiesPanel,

            --count + how-to hint for the selected type; the slow think keeps
            --the count fresh as props are added/moved/removed (including by
            --other clients).
            gui.Label{
                classes = {"fgMuted", "sizeXs", cond(not PropsSupported(), "collapsed")},
                text = "",
                width = "90%",
                height = "auto",
                halign = "center",
                vmargin = 6,
                textAlignment = "center",
                thinkTime = 1,

                think = function(element)
                    if m_mode == "props" then
                        element:FireEvent("refreshprops")
                    end
                end,

                refreshprops = function(element)
                    --the how-to line promises placing/dragging, which a stale
                    --engine cannot do; the banner above says so instead.
                    element:SetClass("collapsed", not PropsSupported())
                    if not PropsSupported() then
                        return
                    end
                    local propInfo = PropTypeInfo(m_props.selected)
                    if propInfo == nil then
                        element.text = ""
                        return
                    end
                    if not propInfo.implemented then
                        element.text = string.format("%s props are not implemented yet.", propInfo.text)
                        return
                    end
                    local count = #PropsOnCurrentFloor(propInfo.id)
                    element.text = string.format(
                        "%d %s%s on this floor. Click the map to place one; drag one to move it; click one to edit it or press Delete to remove it.",
                        count, propInfo.text, cond(count == 1, "", "s"))
                end,
            },
        },
    }

    --Placeholder for the modes that are not implemented yet.
    local placeholderPanel = gui.Label{
        classes = {"fgMuted", cond(m_mode == "walls" or m_mode == "zones" or m_mode == "surfaces" or m_mode == "elevation" or m_mode == "props", "collapsed")},
        text = "",
        width = "90%",
        height = "auto",
        halign = "center",
        vmargin = 16,
        textAlignment = "center",

        markupmode = function(element)
            local implemented = m_mode == "walls" or m_mode == "zones" or m_mode == "surfaces" or m_mode == "elevation" or m_mode == "props"
            element:SetClass("collapsed", implemented)
            if not implemented then
                local modeName = m_mode
                for _,modeInfo in ipairs(MODES) do
                    if modeInfo.id == m_mode then
                        modeName = modeInfo.text
                    end
                end
                element.text = string.format("The %s mode is not implemented yet.", modeName)
            end
        end,
    }

    --The tile height overlay (contour lines, height labels, wall lines colored
    --by cover) is the readout for everything drawn from this panel, so it gets
    --a toggle here as well as in Settings. CreateSettingsEditor monitors the
    --setting, so this checkbox and the settings screen stay in sync.
    local overlayPanel = gui.Panel{
        width = "96%",
        height = "auto",
        halign = "center",
        flow = "vertical",
        vmargin = 4,

        gui.Label{
            classes = {"bold"},
            text = "Overlay",
            width = "96%",
            height = "auto",
            halign = "center",
            vmargin = 4,
        },

        CreateSettingsEditor("tileheight:overlay"),
    }

    contentPanel = gui.Panel{
        id = "MapMarkupPanel",
        width = "100%",
        height = "auto",
        flow = "vertical",
        styles = GetPanelStyles(),

        showpanel = function(element)
            --the overlay renders markup zones whenever the panel is open,
            --independent of the tileheight:overlay preference.
            m_zonePanelOpen = true
            if not gui.ChildHasFocus(element) then
                gui.SetFocus(element)
            end
        end,

        hidepanel = function(element)
            m_zonePanelOpen = false
            if gui.ChildHasFocus(element) then
                gui.SetFocus(nil)
            end
        end,

        destroy = function(element)
            m_zonePanelOpen = false
        end,

        --The dockablePanel ancestor can be nil: content can be hosted outside
        --the dock (PanelDocument bridge), and focus events can fire while the
        --panel is detached. Guard like Objects.lua does.
        childfocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", true)
            end
        end,

        childdefocus = function(element)
            local dockPanel = element:FindParentWithClass("dockablePanel")
            if dockPanel ~= nil then
                dockPanel:SetClass("highlightPanel", false)
            end
        end,

        children = {
            modeTabs,
            wallsPanel,
            zonesPanel,
            footstepsPanel,
            elevationPanel,
            propsPanel,
            placeholderPanel,
            overlayPanel,
        },
    }

    ThemeEngine.OnThemeChanged(mod, function()
        if contentPanel ~= nil and contentPanel.valid then
            contentPanel.styles = GetPanelStyles()
        end
    end)

    --NOTE: m_zonePanelOpen is NOT set here. A saved dock layout builds this
    --content at startup without showing it; visibility comes solely from the
    --dock's showpanel/hidepanel events.
    m_markupHud = contentPanel

    palettePanel:FireEvent("refreshpalette")
    zonePalettePanel:FireEvent("refreshzonepalette")
    zoneListPanel:FireEvent("refreshzones")
    footstepListPanel:FireEvent("refreshfootsteps")
    propsPanel:FireEventTree("refreshprops")
    contentPanel:FireEventTree("markupmode")

    return contentPanel
end

--============================================================================
--Engine hook chaining. The Building editor (Terrain.lua, loaded before this
--module) assigns dmhub.GetSelectedWall / dmhub.GetBuildingSolid; we wrap
--them so whichever panel has focus wins. dmhub.GetWallHeight needs no wrap:
--it reads the building:specifywallheight settings, which our height stepper
--drives directly.
--============================================================================

--MapMarkupHooks survives reloads of this file. If dmhub.GetSelectedWall is
--already our own wrapper (this file reloaded without Terrain.lua reloading),
--unwrap to the function we chained to instead of chaining a stale wrapper.
--rawget: reading an undeclared global errors in the DMHub Lua runtime.
MapMarkupHooks = rawget(_G, "MapMarkupHooks") or {}

local g_priorGetSelectedWall = dmhub.GetSelectedWall
if g_priorGetSelectedWall == MapMarkupHooks.getSelectedWallWrapper then
    g_priorGetSelectedWall = MapMarkupHooks.priorGetSelectedWall
end
MapMarkupHooks.priorGetSelectedWall = g_priorGetSelectedWall
MapMarkupHooks.getSelectedWallWrapper = function()
    local result = nil
    if g_priorGetSelectedWall ~= nil then
        result = g_priorGetSelectedWall()
    end
    if result ~= nil then
        return result
    end
    return GetMarkupSelectedWall()
end
dmhub.GetSelectedWall = MapMarkupHooks.getSelectedWallWrapper

local g_priorGetBuildingSolid = dmhub.GetBuildingSolid
if g_priorGetBuildingSolid == MapMarkupHooks.getBuildingSolidWrapper then
    g_priorGetBuildingSolid = MapMarkupHooks.priorGetBuildingSolid
end
MapMarkupHooks.priorGetBuildingSolid = g_priorGetBuildingSolid
MapMarkupHooks.getBuildingSolidWrapper = function()
    --When the markup panel is driving wall drawing, never draw solid blocks,
    --even if the Building editor was left in Solid mode. (The Building
    --editor's solid flag is not focus-gated.)
    if GetMarkupSelectedWall() ~= nil then
        return false
    end
    if g_priorGetBuildingSolid ~= nil then
        return g_priorGetBuildingSolid()
    end
    return false
end
dmhub.GetBuildingSolid = MapMarkupHooks.getBuildingSolidWrapper

--Height editing. ElevationPanel.lua (DMHub Core Panels, loaded before this
--module) assigns dmhub.GetHeightEditingInfo, gated on its own dock panel
--having focus; we chain so whichever of the two panels has focus wins. Our
--half is nil unless this panel is focused AND in Elevation mode, so the
--Elevation Editor keeps working exactly as before.
local g_priorGetHeightEditingInfo = dmhub.GetHeightEditingInfo
if g_priorGetHeightEditingInfo == MapMarkupHooks.getHeightEditingInfoWrapper then
    g_priorGetHeightEditingInfo = MapMarkupHooks.priorGetHeightEditingInfo
end
MapMarkupHooks.priorGetHeightEditingInfo = g_priorGetHeightEditingInfo
MapMarkupHooks.getHeightEditingInfoWrapper = function()
    local result = GetMarkupHeightEditingInfo()
    if result ~= nil then
        return result
    end
    if g_priorGetHeightEditingInfo ~= nil then
        return g_priorGetHeightEditingInfo()
    end
    return nil
end
dmhub.GetHeightEditingInfo = MapMarkupHooks.getHeightEditingInfoWrapper

--Invisible-only scoping for the Edit Points tool. The engine polls
--dmhub.GetWallPointsInvisibleOnly while the points tool is active; returning
--true restricts the tool to walls with invisible assets, so vertex editing
--driven from this panel cannot disturb visible art walls (those belong to
--the Building editor - design ledger #11, same rule as erasing).
--pcall on read AND write: this hook needs an engine build. On a stale engine
--the property doesn't exist, reads/assignments raise, and the tool simply
--edits all walls like the Building editor's version does.
local g_priorGetWallPointsInvisibleOnly = nil
pcall(function()
    g_priorGetWallPointsInvisibleOnly = dmhub.GetWallPointsInvisibleOnly
end)
if g_priorGetWallPointsInvisibleOnly == MapMarkupHooks.getWallPointsInvisibleOnlyWrapper then
    g_priorGetWallPointsInvisibleOnly = MapMarkupHooks.priorGetWallPointsInvisibleOnly
end
MapMarkupHooks.priorGetWallPointsInvisibleOnly = g_priorGetWallPointsInvisibleOnly
MapMarkupHooks.getWallPointsInvisibleOnlyWrapper = function()
    --true only while THIS panel is the reason the points tool is active: the
    --shared tool setting is "points" and our (focus-gated) wall selection is
    --published. When the Building editor drives the tool instead, its own
    --selection wins the GetSelectedWall chain and we defer.
    if dmhub.GetSettingValue("buildingtool") == "points" and GetMarkupSelectedWall() ~= nil then
        return true
    end
    if g_priorGetWallPointsInvisibleOnly ~= nil then
        return g_priorGetWallPointsInvisibleOnly()
    end
    return false
end
pcall(function()
    dmhub.GetWallPointsInvisibleOnly = MapMarkupHooks.getWallPointsInvisibleOnlyWrapper
end)

--Object-editing filter for Props mode. The engine polls
--dmhub.GetObjectEditingFilter every frame; a non-nil keyword makes only
--matching (markup prop) objects visible/selectable/draggable and everything
--else inert to object selection. This hook is owned solely by this panel, so
--no chaining - but it needs an engine build: pcall on assignment so a stale
--engine (property does not exist -> assignment raises) leaves Props gated
--off (see PropsSupported).
MapMarkupHooks.getObjectEditingFilterWrapper = function()
    return GetMarkupObjectEditingFilter()
end
pcall(function()
    dmhub.GetObjectEditingFilter = MapMarkupHooks.getObjectEditingFilterWrapper
end)

--Object selection. ObjectPropertiesDialog (DMHub Core Panels, loaded before
--this module) assigns dmhub.ObjectsSelected to pop the generic object
--properties dialog; chain so markup props selected while the Props tab is
--focused bind to this panel's editors instead of opening that dialog.
local g_priorObjectsSelected = dmhub.ObjectsSelected
if g_priorObjectsSelected == MapMarkupHooks.objectsSelectedWrapper then
    g_priorObjectsSelected = MapMarkupHooks.priorObjectsSelected
end
MapMarkupHooks.priorObjectsSelected = g_priorObjectsSelected
MapMarkupHooks.objectsSelectedWrapper = function(objects)
    if MarkupHandleObjectsSelected(objects) then
        return
    end
    if g_priorObjectsSelected ~= nil then
        g_priorObjectsSelected(objects)
    end
end
dmhub.ObjectsSelected = MapMarkupHooks.objectsSelectedWrapper
