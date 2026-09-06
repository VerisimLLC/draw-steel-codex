local mod = dmhub.GetModLoading()

--Map Markup: shared namespace, constants and settings.
--
--Map Markup marks up an imported map image with the gameplay layer (walls,
--doors, zones, footstep surfaces, elevation, props) without touching the
--map's art. Design brief: docs/superpowers/specs/2026-07-22-map-markup-panel-design.md
--
--The module is split across the MapMarkup* files, loaded in this order:
--  Core         this file: MapMarkupImpl, K/m/gs, wall presets, break materials
--  WallData     wall palette, wall asset helpers and previews, wall height
--  ZoneTypes    zone presets, stripe colors, zone palette, entire-map
--               keywords, dynamic light thresholds, zone height, summaries
--  Surfaces     footstep surface registry, settings, storage, variations
--  ZoneRuntime  zone/surface caches, aura builders, the GetMapAuras and
--               GetMarkupZones engine hooks, dynamic light sampling
--  ZoneStorage  zone records, CreateZone, splitting, calculated zones,
--               normalization, flash/jump
--  Hooks        panel state, arming, selection helpers, engine hook chaining
--  Props        markup prop assets, teleporter links, teleporter arrows
--  WallDialog   the wall type dialog and the map-pack sharing dialog
--  *Mode        one builder per panel tab (Walls, Zones, Footsteps,
--               Elevation, Props)
--  Panel        tool/mode tables, styles, delete geometry, CreateMarkupEditor
--
--Everything above the Mode files runs on every client whether or not the
--panel is open; the Mode files and Panel only run for the Director.
--
--How wall drawing works: the engine polls dmhub.GetSelectedWall every frame
--(DMSheetHud.selectedWallId). The Building editor publishes its selection
--when it has focus; we chain onto the same hook (MapMarkupHooks.lua) and
--publish our selected markup wall when this panel has focus instead. Since
--we never publish a floor, the engine is in walls-only mode, where the shape
--tool draws open polylines - which is exactly the markup "Line" tool.

--============================================================================
--Shared namespaces. MapMarkupImpl is the module-private table every
--MapMarkup* file reads at load (`local MM = MapMarkupImpl`); it is created
--fresh here on every load, exactly as the old single-file locals were. Each
--file exports its top-level functions onto MM at its end and calls other
--files' functions THROUGH MM at call time (MM.Foo(...)), never capturing
--them, so load order only matters for code that runs at load.
--
--  K  -- immutable constants           (was the UPPER_CASE file locals)
--  m  -- mutable module state          (was the m_* file locals)
--  gs -- settings + chained-hook prevs (was the g_* file locals)
--
--Do NOT declare a local named MM, K, m or gs anywhere in these files: it
--would shadow a namespace and silently break every reference inside that
--scope. (The old reason for the tables - the 200-locals-per-chunk ceiling -
--no longer binds now that the module is split, but the tables stay: they
--are what the files share.)
--============================================================================
MapMarkupImpl = {}
local MM = MapMarkupImpl
local K = {}
local m = {}
local gs = {}
MM.K, MM.m, MM.gs = K, m, gs

--per-mode panel records ({panel, toolPanel, prime}) filled in by
--CreateMarkupEditor from the Build*Mode builders; nil while no panel exists.
m.modePanels = nil

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

--============================================================================
--"Fade Map": dims the whole map so the markup being drawn stands out instead
--of competing with busy map art. Purely a local viewing aid - not map data,
--and never seen by players.
--
--The engine reads this setting DIRECTLY (SettingsManager.GetFloatOptional in
--TileHeightOverlay.Update), so there is nothing to feed through
--dmhub.GetMarkupZones and no revision to bump; the slider's live
--PreviewSettingValue during a drag is picked up on the very next frame.
--MapFadeOverlay.cs applies it, gated on the panel actually being open, so a
--value left on the slider cannot follow the Director back to the table.
--
--`transient`, deliberately, NOT a preference: a fade left near the top blacks
--the map out with no on-screen explanation, and the only control that undoes
--it is the last row of a panel that can run off the bottom of the screen.
--Bug 327JQQFP was exactly that - a value set in some earlier session made the
--map render as an unexplained void every time the panel was opened, session
--after session. Runtime-only means the worst case now lasts until restart,
--and every fresh launch starts unfaded.
--
--No `section`, so it stays out of the global Settings screen - it does
--nothing with this panel closed, and CreateSettingsEditorsForSection only
--picks up settings that declare one.
--============================================================================
setting{
    id = "markup:fade",
    description = "Fade Map",
    help = "Dims the map - terrain, walls, objects, tokens and all - so the markup you are drawing stands out. Only applies while this panel is open.",
    storage = "transient",
    editor = "slider",
    default = 0,
    min = 0,
    max = 1,
    percent = true,
}

--The Core invisible ("see-thru") wall asset markup wall types are duplicated
--from. Wall assets require an image (ImageAsset.ValidationCheck), so presets
--cannot be created from scratch; we duplicate this invisible base and set
--gameplay fields on the copy. Same asset MapImport uses for invisible walls.
K.BASE_INVISIBLE_WALL_ID = "eae7f3fe-d278-455c-853a-ac43f948c743"

--The Core "Invisible Floor" tilesheet (invisible=true, Building layer): the
--shared TOP face of every markup solid block. The top face of an invisible
--tilesheet never renders on player clients (and only faintly for the DM while
--an editing tool is open), so one shared sheet serves every solid type - the
--per-type differences live entirely in the wall asset.
K.INVISIBLE_TILESHEET_ID = "-MGAVDxkFE-ZzzNYBV0D"

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
K.DOOR_OPEN_SOUND_ID = "f6bc62cc-7225-48cf-b719-b86280ea198d"
K.DOOR_CLOSE_SOUND_ID = "e9950541-0c22-41d3-baba-f7f307b3e81a"

--Gameplay fields stamped on the wall asset backing a new openable type: a
--closed door blocks like a stone wall; opening it disables all of this.
K.DOOR_TYPE_FIELDS = {
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
--
--color is the markup color the preset's wall asset is stamped with when it
--materializes, drawn from the eight-swatch palette in m_wallColor.COLORS, so
--a fresh map's wall types read apart at a glance instead of every type
--drawing in the same grey. Stone deliberately has NONE: it is the ordinary
--wall, and no color means the engine's stock skeleton styling - which is also
--what the Default swatch restores. The user can recolor any type from the
--chip's color square, and that write lands on the asset and wins from then on.
K.WALL_PRESETS = {
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
        color = "#00a2c7",
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
        color = "#f76b15",
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
        color = "#ffc53d",
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
        color = "#ab4aba",
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
        color = "#e5484d",
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

K.WALL_PRESETS_BY_KEY = {}
for _,preset in ipairs(K.WALL_PRESETS) do
    K.WALL_PRESETS_BY_KEY[preset.key] = preset
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

K.BREAK_MATERIALS = {
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

K.DEFAULT_BREAK_STAMINA = 3

local function BreakMaterialForStamina(stamina)
    for _,material in ipairs(K.BREAK_MATERIALS) do
        if material.stamina ~= nil and material.stamina == stamina then
            return material.id
        end
    end
    return "custom"
end

local function BreakMaterialById(id)
    for _,material in ipairs(K.BREAK_MATERIALS) do
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
        asset.breakStamina = math.max(1, math.floor((stamina or K.DEFAULT_BREAK_STAMINA) + 0.5))
    else
        asset.solidity = "Unbreakable"
        asset.breakStamina = 0
    end
    asset.rubbleKeyword = ""
    asset.rubbleTerrainId = ""
end


--============================================================================
--Exports: the other MapMarkup files call these through MM.
--============================================================================
MM.AssetIsBreakable = AssetIsBreakable
MM.BreakMaterialById = BreakMaterialById
MM.BreakMaterialForStamina = BreakMaterialForStamina
MM.SetAssetBreakable = SetAssetBreakable
MM.track = track
