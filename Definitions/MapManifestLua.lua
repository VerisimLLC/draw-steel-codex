---@meta

--- @class MapManifestLua
--- @field id string
--- @field valid boolean
--- @field mapManifest any
--- @field dimensions any
--- @field loadingScreenImage string
--- @field thumbnailImage string|nil Asset id of this map's thumbnail: a ~512px picture of its default floor, lit, with no tokens, usable as a bgimage. nil until the Director captures one. See MAP_THUMBNAILS.md. (Read-only)
--- @field thumbnailStale boolean True when the map has been edited since its thumbnail was captured; the Director's next visit recaptures it. (Read-only)
--- @field packSource nil|{pack: string, mapid: string} The map pack this map was added from, or nil for a map that did not come from a map pack. pack is the pack's module fullid and mapid the map's id inside the pack. Maps added before provenance was recorded are recognised by their id when it is in the synced map pack index. (Read-only)
--- @field water nil|{floor: string, level: number, zone: string, visual: {mode: string, tilesheet: string, shallowColor: string, deepColor: string, minOpacity: number, maxOpacity: number, fullDepth: number, foam: boolean, depthLines: boolean, layers: number, artLevel: number|nil}} The map's water level (WATER_LEVEL_REFERENCE.md), or nil when the map has none. A table {floor = floor id ('' = the ground-level floor), level = surface altitude in tiles (a multiple of 0.5), visual = {mode = 'surface'|'none', tilesheet = terrain tilesheet id ('' = built-in Water), shallowColor, deepColor (html color strings), minOpacity, maxOpacity, fullDepth, foam, depthLines, layers (0-4), artLevel (nil, or the level the map art already shows)}}. Ground lower than the level by 1 or more is deep water (swimming; creatures float at the surface and may dive to the bed); by less than 1 is shallow water (difficult terrain, keyword 'Shallow Water', for creatures without a swim speed). zone = an environmental keyword (zone type) id, or '' -- when set, only squares inside zones of that type can be under water. Assigning a table replaces the record (fields it leaves out keep their current values) as one undoable change; assigning nil removes the water. Creatures move with a changed level automatically (MapWaterLevel.FloatTokensAfterLevelChange).
--- @field defaultFloorId any
--- @field groundLevel any
--- @field description any
--- @field floorsWithoutLayers any
--- @field floors any
--- @field parentFolder any
--- @field ord number
--- @field playerViewable boolean (Read-only) True if this map is 'Player Viewable' for the local user: on for all players, or for this user among the chosen players. Player-viewable maps grant full vision and always appear in the player-facing Maps panel. A Director is never one of the chosen players, so for them this is true only when it is on for all players.
--- @field playerViewableAll boolean (Read-only) True if this map's 'Player Viewable' setting is on for every player (including players who join later).
--- @field playerViewableUsers nil|table<string, boolean> (Read-only) The players this map is 'Player Viewable' for when it is not on for every player: {userid = true}, or nil when there are none.
--- @field mapid string
MapManifestLua = {}

--- MarkUndo
function MapManifestLua:MarkUndo() end

--- Upload
--- @param description? string
function MapManifestLua:Upload(description) end

--- Delete
function MapManifestLua:Delete() end

--- Sizes this map's dimensions to the grid cells its map images cover -- every object with a Map component, on every floor and layer. A cell is covered when its center lies on an image; this works for square and hex grids and is exact however the image was calibrated. With expandOnly the dimensions only grow to include those cells; otherwise they are set to exactly those cells. Does not upload: call Upload afterwards. Returns "fitted" when the dimensions were set, "pending" while an image is still loading or has not yet been placed with its current calibration and position (poll again next frame), "none" when the map has no map images, or "notcurrent" when this is not the current map (only the current map's images are loaded).
--- @param expandOnly? boolean
--- @return string
function MapManifestLua:FitDimensionsToMapImages(expandOnly) end

--- Capture this map's thumbnail now, upload it and store it on the map (thumbnailImage). Only the current map can be captured, and only by the Director. The screen freezes for a moment while the map is rendered. Asynchronous: complete(assetid) when the thumbnail is stored, error(message) if it could not be made.
--- @param options {complete: (fun(assetid: string): nil)|nil, error: (fun(message: string): nil)|nil}|nil
function MapManifestLua:CaptureThumbnail(options) end

--- Sets this map's water level (a multiple of 0.5; other values are rounded), creating the water record with the default appearance if the map has none. nil removes the water level. options.floor picks the floor (default: the record's floor, else the ground-level floor). Creatures settle with the new level automatically.
--- @param level number|nil
--- @param options nil|{floor: nil|string}
function MapManifestLua:SetWaterLevel(level, options) end

--- This map's water level in tiles, or nil when it has none.
--- @return number|nil
function MapManifestLua:GetWaterLevel() end

--- Counts the building operations across all of this map's floors (every terrain layer) that draw with the given wall asset id. Erase operations do not count. The Map Markup panel uses this to tell whether removing a wall type from its palette orphans the asset. Probe inside pcall: older engine builds lack this method.
--- @param wallid string
--- @return number
function MapManifestLua:GetWallOperationCount(wallid) end

--- Rewrites every non-erase building operation on this map that draws with oldWallid so it draws with newWallid instead, across all floors and terrain layers, as one undoable command. Each rewritten operation keeps its timestamp (a fresh timestamp would re-order it after later erases on rebuilds) but gets a NEW id - the key change is what makes every client's terrain layers roll the old op back and apply the new one (the door-toggle swap pattern). Returns the number of operations rewritten. The Map Markup panel uses this to retype a map's walls when forking a shared wall type. Probe inside pcall: older engine builds lack this method.
--- @param oldWallid string
--- @param newWallid string
--- @return number
function MapManifestLua:ReplaceWallOperations(oldWallid, newWallid) end

--- GetFloorFromLoc
--- @param loc? any
--- @return any
function MapManifestLua:GetFloorFromLoc(loc) end

--- GetLayersForFloor
--- @param parentFloorId? any
--- @return any
function MapManifestLua:GetLayersForFloor(parentFloorId) end

--- CreateFloor
--- @param options? any
function MapManifestLua:CreateFloor(options) end

--- CreatePreviewFloor
--- @param floorBasis? string
--- @return any
function MapManifestLua:CreatePreviewFloor(floorBasis) end

--- DestroyPreviewFloor
--- @param floorInfo? any
function MapManifestLua:DestroyPreviewFloor(floorInfo) end

--- Travel
function MapManifestLua:Travel() end

--- Tabletop mode: Travel() because the user pressed on this map's frozen window with the given mouse button (0 left, the default; 1 right; 2 middle), and once the map is live the press lands on it as if the window had been live when pressed: a left press selects the token under it (when the user may select it), a right press opens the map's context menu there, a middle press still held starts panning. The map ignores the mouse until a left press is released. Outside tabletop mode it is just Travel().
--- @param button nil|integer
function MapManifestLua:TravelFromPress(button) end

--- Start syncing this map in the background so a later Travel() to it skips the loading screen. Cheap to call repeatedly (e.g. on hover). Does nothing in Firebase-backed games or the lobby.
function MapManifestLua:Prefetch() end

--- True if this map is 'Player Viewable' for the given user: on for all players, or that user is one of the chosen players.
--- @param userid? string
--- @return boolean
function MapManifestLua:IsPlayerViewableFor(userid) end

--- Director only. Sets who this map is 'Player Viewable' for: all = true for every player (including players who join later), otherwise users = {userid = true} for just those players (nil or empty for nobody). Uploads at once, as one undoable change, and works on any map, not just the current one.
--- @param all boolean
--- @param users nil|table<string, boolean>
function MapManifestLua:SetPlayerViewable(all, users) end
