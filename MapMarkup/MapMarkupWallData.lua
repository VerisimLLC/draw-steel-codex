local mod = dmhub.GetModLoading()

--Map Markup: wall palette, wall asset helpers and previews, wall height.
local MM = MapMarkupImpl
local K, m, gs = MM.K, MM.m, MM.gs

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

K.DEFAULT_PALETTE = "preset:stone;preset:window;preset:fence;preset:lowwall;preset:curtain;preset:barrier"

gs.paletteSetting = setting{
    id = "markup:wallpalette",
    description = "Map Markup Wall Palette",
    storage = "map",
    default = K.DEFAULT_PALETTE,
}

local function ParsePalette()
    local result = {}
    local str = gs.paletteSetting:Get()
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
    gs.paletteSetting:Set(SerializePalette(entries))
end

--============================================================================
--Popup survival across list rebuilds.
--
--Every list in this panel rebuilds its children wholesale from a monitor, and
--a monitor fires on the round trip of OUR OWN write just as readily as on
--another DM's edit. Destroying a panel destroys any popup it owns, so a
--refresh landing while the user has a color popout or a context menu open
--yanks it out from under the cursor: the popup appears to open and instantly
--close again. Rebuilds stand down while a popup is open and replay once it
--is gone - gui.RebuildDeferringPopups / gui.ThinkDeferredRebuild in Gui.lua.
--The list on screen is momentarily stale, but it matches the popup the user
--is interacting with, which is the more important consistency.
--============================================================================

--============================================================================
--Palette entry helpers.
--============================================================================

local function EntryWallAsset(entry)
    if entry == nil or entry.guid == nil then
        return nil
    end
    return assets.walls[entry.guid]
end

--============================================================================
--Map-private wall types.
--
--Every wall asset the panel creates (materialized presets, Custom, Door) is
--stamped with the current map's id (WallAsset.markupMapId, engine build
--required) and hidden from other maps' pickers until promoted via Edit
--Wall's "Make Available to All Maps" - the same lifecycle map-scoped zone
--types get from EnvironmentalKeyword.mapid. Removing an unused, map-private
--type from the palette deletes its asset outright: nothing can reference it
--at that point. On engine builds without the field everything degrades to
--the old behavior (game-wide walls, no deletion).
--
--One table rather than several locals (the openable probe's cache lives
--here as a field for the same reason); see the shared-namespace note in
--MapMarkupCore.lua. The keyword helpers are added as extra fields from
--MapMarkupZoneTypes.lua, next to the GetKeyword/FindKeywordIdByName helpers
--they need.
--============================================================================
m.mapScope = {
    openableSupport = nil,

    --Engine gate, same probe recipe as OpenableWallsSupported: the accessor
    --reads "" (never nil) when unset precisely so this probe works.
    wallSupportCache = nil,
    WallSupported = function()
        if m.mapScope.wallSupportCache ~= nil then
            return m.mapScope.wallSupportCache
        end
        local probe = assets.walls[K.BASE_INVISIBLE_WALL_ID]
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
        local value = nil
        pcall(function()
            value = probe.markupMapId
        end)
        m.mapScope.wallSupportCache = (value ~= nil)
        return m.mapScope.wallSupportCache
    end,

    --the map id a wall type is private to, or nil for game-wide/legacy walls
    --and pre-scoping engine builds.
    WallMapId = function(asset)
        if asset == nil then
            return nil
        end
        local result = nil
        pcall(function()
            local id = asset.markupMapId
            if type(id) == "string" and id ~= "" then
                result = id
            end
        end)
        return result
    end,

    --Whether a wall asset is usable on the current map: game-wide walls
    --always are; map-private ones only on the map they were created on.
    --The wall twin of KeywordAvailableOnThisMap.
    WallAvailableOnThisMap = function(asset)
        local mapid = m.mapScope.WallMapId(asset)
        return mapid == nil or mapid == game.currentMapId
    end,

    --Stamps a freshly created markup wall as private to the current map.
    --Quietly does nothing on engine builds without the field: the wall is
    --then simply game-wide, exactly as before this feature.
    StampWall = function(asset)
        pcall(function()
            asset.markupMapId = game.currentMapId
        end)
    end,

    --Whether any building operation on the current map still draws with this
    --wall type. Engine-gated (map:GetWallOperationCount): unknown = true, so
    --callers keep the asset rather than deleting something possibly in use.
    WallInUseOnMap = function(guid)
        local count = nil
        pcall(function()
            count = game.currentMap:GetWallOperationCount(guid)
        end)
        if count == nil then
            return true
        end
        return count > 0
    end,

    --Deletes a map-private wall type when removing its chip orphans it:
    --private to THIS map (so no other map's palette or geometry can
    --reference it), no walls drawn with it anywhere on the map, and no
    --other chip still pointing at the asset. Game-wide and library walls
    --are shared content and are never deleted here.
    DeleteWallIfOrphaned = function(guid, remainingEntries)
        local asset = assets.walls[guid]
        if asset == nil then
            return
        end
        local mapid = m.mapScope.WallMapId(asset)
        if mapid == nil or mapid ~= game.currentMapId then
            return
        end
        for _,entry in ipairs(remainingEntries or {}) do
            if entry.guid == guid then
                return
            end
        end
        if m.mapScope.WallInUseOnMap(guid) then
            return
        end
        asset:Delete()
    end,
}

--Engine gate: WallAsset.openable (and the door icon/toggle machinery) needs
--an engine build. NOTE: reading an unknown property on engine userdata does
--NOT error - it silently returns nil (verified live 2026-07-27) - so the
--probe must check the VALUE is non-nil, not just that the read succeeded.
--On a supporting build the accessor returns a real boolean. Cached (on
--m.mapScope, sparing a file-level local): chips and dialogs consult this
--repeatedly.
local function OpenableWallsSupported()
    if m.mapScope.openableSupport ~= nil then
        return m.mapScope.openableSupport
    end
    local probe = assets.walls[K.BASE_INVISIBLE_WALL_ID]
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
    m.mapScope.openableSupport = ok and value ~= nil
    return m.mapScope.openableSupport
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
                asset.openSound = K.DOOR_OPEN_SOUND_ID
            end
            if asset.closeSound == nil or asset.closeSound == "" then
                asset.closeSound = K.DOOR_CLOSE_SOUND_ID
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
    return K.WALL_PRESETS_BY_KEY[entry.key]
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
--classification in WallMesh.BuildSkeleton. color is the wall type's markup
--color ("#rrggbb" or nil): when set, the engine draws this type's skeleton
--in it, so the preview line tints to match. narrow trims the dash/dot
--counts to fit the palette chips' 70px preview column (the color swatches
--sit beside it); the library modal keeps the full-width pattern.
local function CreateWallLinePreview(fields, color, narrow)
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

    --Segment sizing keeps the widest pattern under the preview column width
    --(100px, or 70px narrow), so a dash never runs under the name.
    if dashed then
        for _ = 1,cond(narrow, 5, 7) do
            segments[#segments+1] = gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
                width = 9,
                height = 3,
                hmargin = 2,
                valign = "center",
            }
        end
    elseif dotted then
        for _ = 1,cond(narrow, 9, 12) do
            segments[#segments+1] = gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
                width = 3,
                height = 3,
                hmargin = 2,
                valign = "center",
            }
        end
    else
        segments[#segments+1] = gui.Panel{
            classes = {"markupWallLine"},
            bgimage = true,
            bgcolor = color,
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
--which a static chip has no way to show. color tints the wall line + leaf
--like CreateWallLinePreview's, matching the type's markup color on the map.
local function CreateDoorLinePreview(color)
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
                bgcolor = color,
                width = "22%",
                height = 3,
                valign = "center",
            },
            gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
                width = "46%",
                height = 9,
                valign = "center",
            },
            gui.Panel{
                classes = {"markupWallLine"},
                bgimage = true,
                bgcolor = color,
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
--Spans the chip's full width like the thin chip's line, so the two draw-mode
--previews read as equals. The stripe count deliberately OVERFILLS the box
--and clip trims the excess at the border, so the pattern reaches the right
--edge exactly at any chip width instead of stopping wherever a fixed count
--happens to end.
local function CreateSolidBlockPreview()
    local stripes = {}
    for _ = 1,24 do
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

    --Border on the outer panel, stripes clipped in an inner layer: clip uses
    --the panel's own bgimage as the mask (Unity Mask semantics) and clipHidden
    --keeps that mask image from drawing - the islandLayer recipe from
    --MarkdownDocument.lua. Clipping the border's panel itself would eat the
    --border pixels at the mask edge.
    return gui.Panel{
        width = "100%",
        height = 12,
        halign = "center",
        bgimage = true,
        bgcolor = "clear",
        borderWidth = 1,
        borderColor = "@fgMuted",

        gui.Panel{
            width = "100%-2",
            height = "100%-2",
            halign = "center",
            valign = "center",
            flow = "horizontal",
            bgimage = "panels/square.png",
            bgcolor = "clear",
            clip = true,
            clipHidden = true,
            children = stripes,
        },
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
    MM.SetAssetBreakable(wall, stamina > 0, stamina)

    --Openable (door) types: engine-build gated, so this quietly does nothing
    --on a stale engine and the type behaves as a plain wall.
    SetAssetOpenable(wall, fields.openable == true)
end

--Creates a game wall asset by duplicating the invisible base and applying
--the given name + gameplay fields. color is the optional markup color
--("#rrggbb", nil = the engine's stock grey). Returns the new guid, or nil on
--failure.
local function CreateMarkupWallAsset(name, fields, color)
    if assets.walls[K.BASE_INVISIBLE_WALL_ID] == nil then
        dmhub.Debug("MARKUP:: base invisible wall asset is not available in this game")
        return nil
    end

    local guid = assets:DuplicateWall(K.BASE_INVISIBLE_WALL_ID)
    if guid == nil then
        return nil
    end

    local wall = assets.walls[guid]
    wall.description = name
    ApplyFieldsToWall(wall, fields)
    --engine-gated exactly like m_wallColor: WallAsset.markupColor does not
    --exist on stale builds, where the type just draws in the stock grey.
    if color ~= nil then
        pcall(function()
            wall.markupColor = color
        end)
    end
    --new markup walls are private to the map they were created on until
    --promoted from Edit Wall's "Make Available to All Maps".
    m.mapScope.StampWall(wall)
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
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.ApplyFieldsToWall = ApplyFieldsToWall
MM.AssetFields = AssetFields
MM.AssetIsOpenable = AssetIsOpenable
MM.CreateDoorLinePreview = CreateDoorLinePreview
MM.CreateMarkupWallAsset = CreateMarkupWallAsset
MM.CreateSolidBlockPreview = CreateSolidBlockPreview
MM.CreateWallLinePreview = CreateWallLinePreview
MM.EntryDisplayName = EntryDisplayName
MM.EntryFields = EntryFields
MM.EntryIsOpenable = EntryIsOpenable
MM.EntryWallAsset = EntryWallAsset
MM.GetWallHeightSetting = GetWallHeightSetting
MM.OpenableWallsSupported = OpenableWallsSupported
MM.ParsePalette = ParsePalette
MM.PresetForEntry = PresetForEntry
MM.SavePalette = SavePalette
MM.SerializePalette = SerializePalette
MM.SetAssetOpenable = SetAssetOpenable
MM.SetWallHeightSetting = SetWallHeightSetting
MM.SummarizeEntry = SummarizeEntry
MM.SummarizeFields = SummarizeFields
