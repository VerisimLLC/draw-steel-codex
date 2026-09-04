--- @class MapPackIndexEntry One appearance variant of one map in a map pack.
--- @field id string map guid inside the pack
--- @field pack string module fullid of the pack
--- @field versionid string dataid of the pack version holding the map
--- @field scene string
--- @field sceneName string
--- @field variant string
--- @field variantIndex integer 0 = the map's base image, n = its n-th alternate appearance
--- @field name string
--- @field thumb string image id of the 512px preview (usable as a bgimage)
--- @field image string image id of the full map image
--- @field tilesW integer
--- @field tilesH integer
--- @field tileType string
--- @field keywords string[]
--- @field description string
MapPackIndexEntry = {}

--- @class MapPackInfo
--- @field id string module fullid
--- @field versionid string
--- @field count integer variant entries in the pack
--- @field maps integer distinct maps in the pack
--- @field blob string
MapPackInfo = {}

--- The map pack index: every published map pack's searchable list of maps and
--- appearance variants, synced from the cloud, cached locally and searched in
--- memory. Individual maps are added to the current game with AddMapToGame
--- without installing the pack's module.
--- @class MapPackIndexLua
--- @field synced boolean Whether the index has been synced at least once this session. (Read-only)
--- @field syncing boolean Whether a sync is currently in progress. (Read-only)
--- @field count integer The number of variant entries across every synced pack. (Read-only)
--- @field packs MapPackInfo[] The synced packs. (Read-only)
MapPackIndexLua = {}

--- Reads /MapPackIndex, downloads any pack index blob that changed since the
--- local cache was written, and rebuilds the in-memory index.
--- @param options {success: nil|fun(), error: nil|fun(msg: string)}
--- @return nil
function MapPackIndexLua.Sync(options)
	-- dummy implementation for documentation purposes only
end

--- Searches the synced index. Every space-separated term in options.text must
--- match the entry's name, scene, variant, description or a keyword as a
--- substring. options.pack restricts to one module fullid. Empty text returns
--- every entry up to maxResults (default 200).
--- @param options {text: nil|string, pack: nil|string, maxResults: nil|integer}
--- @return MapPackIndexEntry[]
function MapPackIndexLua.Search(options)
	-- dummy implementation for documentation purposes only
end

--- Adds one map from a map pack to the current game without installing the
--- pack's module, arming the appearance at options.variantIndex (default 0).
--- options.name, when given, becomes the added map's name instead of the pack's.
--- If the map is already in the game a fresh copy with new ids is added.
--- @param options {pack: string, mapid: string, variantIndex: nil|integer, name: nil|string, success: nil|fun(mapid: string), error: nil|fun(msg: string)}
--- @return nil
function MapPackIndexLua.AddMapToGame(options)
	-- dummy implementation for documentation purposes only
end

--- @type MapPackIndexLua
mappacks = nil
