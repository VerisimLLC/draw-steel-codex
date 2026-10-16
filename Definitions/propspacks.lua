---@meta

--- @class PropsPackInfo One synced props pack.
--- @field id string module fullid of the pack ("tomcartos-props")
--- @field name string
--- @field org string creator organization whose Patreon pledge unlocks it
--- @field premium boolean
--- @field prelaunch boolean the pack is hidden pre-launch; only admins see it
--- @field count integer objects across every bundle
--- @field folderid string guid of the pack's object folder
--- @field access boolean whether any bundle is unlocked for this account
--- @field tier integer the pack's pledge in cents (bundles may have their own); 0 = free
--- @field tierName string the creator's name for that pledge level
--- @field bundles PropsPackBundleInfo[]
---
--- @class PropsPackBundleInfo One bundle of a props pack: a top-level folder of its library.
--- @field key string stable id of the bundle inside the pack ("TC32")
--- @field name string
--- @field count integer objects
--- @field looks integer images, appearances included
--- @field folderid string guid of the bundle's object folder
--- @field cover string image URL of a representative prop
--- @field tier integer pledge in cents this bundle needs; 0 = free
--- @field tierName string
--- @field access boolean whether this account may use the bundle
--- @field status "unloaded"|"loading"|"loaded"|"error"|"locked"
--- @field error string why loading failed (status "error")
---
--- @class PropsPackFolder What a pack or bundle folder is, from propspacks.GetFolder.
--- @field pack string
--- @field bundle string|nil the bundle key; nil for the pack's own folder
---
--- @class PropsPackSearchHit One object of a props pack matched by propspacks.Search.
--- @field id string the object asset's guid
--- @field pack string
--- @field bundle string bundle key
--- @field name string
--- @field image string image URL of its base look
--- @field width number footprint in squares
--- @field height number footprint in squares
--- @field looks integer 1 + its Appearance variants
--- @field keywords string[]
--- @field matchScore integer

--- Props packs: creators' prop libraries (Tom Cartos' asset bundles), unlocked by a Patreon pledge and shown in the Director's Object Library in every game without installing anything. Each pack is a folder at the library root with a folder per bundle; a bundle's objects are loaded on demand with LoadBundle. Placing one copies it into the game. See PROPS_PACKS_PLAN.md.
--- @class propspacks
--- @field synced boolean Whether the props pack index has been synced this session. It syncs by itself the first time this client is the Director in a game. (Read-only)
--- @field syncing boolean Whether a sync is in progress. (Read-only)
--- @field packs PropsPackInfo[] The synced props packs with their bundles, access and load status, evaluated live (a pledge landing shows on the next read). (Read-only)
propspacks = {}

--- One synced props pack, or nil.
--- @param pack string module fullid
--- @return PropsPackInfo|nil
function propspacks.GetPack(pack) end

--- Says whether an object folder is a props pack's folder (bundle nil) or one of its bundle folders, or neither (nil). Sub-folders inside a bundle come from the bundle itself and are not reported.
--- @param folderid string an object folder guid
--- @return PropsPackFolder|nil
function propspacks.GetFolder(folderid) end

--- Loads one bundle's objects into the asset tree (downloaded once, then cached on disk), so its folder fills in. Returns false when the bundle cannot be loaded: not in a game as the Director, unknown, or locked for this account. Watch the bundle's status in packs/GetPack; the objects category refreshes when it lands.
--- @param pack string module fullid
--- @param bundle string bundle key
--- @return boolean
function propspacks.LoadBundle(pack, bundle) end

--- Searches every synced pack's index, loaded bundles or not: each space-separated term must match the start of a word of the object's name or one of its keywords. matchScore sums 2 per whole-word match and 1 per prefix match. Results are in index order (default at most 200).
--- @param options {text: string, pack: nil|string, maxResults: nil|integer}
--- @return PropsPackSearchHit[]
function propspacks.Search(options) end

--- Reads /PropsPackIndex again and downloads any pack index that changed. Calls options.success, or options.error with a message.
--- @param options nil|{success: nil|fun(), error: nil|fun(message: string)}
function propspacks.Sync(options) end
