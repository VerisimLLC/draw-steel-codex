---@meta

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
--- @field searchTerms string[] the words Search matches against
--- @field description string
--- @field footstep string recommended default footstep surface name (" if none)
--- @field tier integer Patreon pledge in cents needed to unlock this appearance; 0 when free
--- @field org string creator organization whose Patreon the tier is measured against
--- @field owned boolean whether the current account can use this appearance
--- @field matchScore integer how well the entry matched a Search; 0 for an empty search
---
--- @class MapPackInfo One synced map pack.
--- @field id string module fullid
--- @field versionid string
--- @field count integer variant entries in the pack
--- @field maps integer distinct maps in the pack
--- @field blob string
--- @field org string creator organization whose Patreon unlocks tiered appearances
--- @field premium boolean whether the pack module is premium

--- The map pack index: every published map pack's searchable list of maps and appearance variants, synced from the cloud, cached locally and searched in memory. Individual maps are added to the current game with AddMapToGame without installing the pack's module.
--- @class mappacks
--- @field synced boolean Whether the index has been synced at least once this session. (Read-only)
--- @field syncing boolean Whether a sync is currently in progress. (Read-only)
--- @field count number The number of variant entries across every synced pack. (Read-only)
--- @field packs MapPackInfo[] The synced packs: one record per /MapPackIndex pointer, with the module fullid as id. org is the creator organization whose Patreon unlocks tiered appearances; premium says the pack module is premium. (Read-only)
mappacks = {}

--- Reads /MapPackIndex, downloads any pack index blob that changed since the local cache was written, and rebuilds the in-memory index. Calls options.success when done, or options.error with a message if the pointer node could not be read or some pack failed to load (the packs that did load are still searchable).
--- @param options {success: nil|fun(), error: nil|fun(message: string)}
function mappacks.Sync(options) end

--- Searches the synced index. Every space-separated term in options.text must match a word of the entry's name, scene, variant, description or a keyword, either whole or as the start of the word ("cave" finds "cavern"). matchScore sums each term's match quality: 4 whole keyword, 3 whole word elsewhere, 2 keyword prefix, 1 prefix elsewhere; 0 for an empty search. Results are in index order, rank them by matchScore yourself. options.pack restricts to one module fullid. Empty text returns every entry up to maxResults (default 200). Entries are per appearance variant: variantIndex 0 is the map's base image, n is its n-th alternate appearance. tier is the minimum monthly Patreon pledge in cents to the creator organization `org` that unlocks the appearance (0 = free); owned is whether this account may add it right now, evaluated live against the account's pledges.
--- @param options {text: nil|string, pack: nil|string, maxResults: nil|integer}
--- @return MapPackIndexEntry[]
function mappacks.Search(options) end

--- How this account stands with a pack's Patreon gating: org is the creator organization the pack's tiers are measured against; cents the account's current monthly pledge to it (0 if none or lapsed); linked whether a Patreon account is attached at all; entitled whether the org grants this account anything; full whether the whole pack is unlocked regardless of tiers (bought in the store, or included with the org's membership). Evaluated live, so poll it to notice a pledge landing.
--- @param pack string The pack's module fullid.
--- @return {org: string, cents: integer, linked: boolean, entitled: boolean, full: boolean}
function mappacks.GetPackAccess(pack) end

--- Adds one map from a map pack to the current game without installing the pack's module: the map's manifest, floors and rasters plus the object and image asset records it references are copied into the game, and the appearance variant at options.variantIndex (default 0) is armed. options.name, when given, becomes the added map's name instead of the pack's. options.markupId, when given, is the id of a shared markup set (see ListMarkup) whose walls, zones, footstep regions, props and markup settings are laid over the map before it is written. Requires access to the chosen appearance (free, unlocked by the account's Patreon pledge to the pack's creator, or the whole pack owned); appearances of the map the account is NOT entitled to are left out of the added map. If the map is already in the game a fresh copy with new ids is added. Calls options.success with the new map id, or options.error with a message.
--- @param options {pack: string, mapid: string, variantIndex: nil|integer, name: nil|string, markupId: nil|string, success: nil|fun(result: string), error: nil|fun(message: string)}
function mappacks.AddMapToGame(options) end

--- Compares the given map in the current game with the map pack it was added from and reports what markup the game has added on top: wall segments (and the game-local wall types they use), zones, footstep regions (and whether a default footstep setting is set), props, and painted elevation (heightmap zones, each a 4x4-tile area). The map must be the current map so its floors are loaded. options.error fires with a message when the map did not come from a map pack or the pack could not be loaded. The comparison is kept for UploadMarkup.
--- @param options {mapid: string, success: nil|fun(summary: {pack: string, mapid: string, walls: integer, wallTypes: integer, zones: integer, footsteps: integer, footstepDefault: boolean, props: integer, elevation: integer}), error: nil|fun(message: string)}
function mappacks.GetMarkupSummary(options) end

--- Shares the markup the current game added to a map-pack map with everyone who adds that map: the parts flagged true (walls, zones, footsteps, props, elevation; each defaults to true) of the comparison GetMarkupSummary made are uploaded as one shared markup set with the given description and author name. Any signed-in user may upload. Calls options.success with the new markup id, or options.error with a message.
--- @param options {mapid: string, walls: nil|boolean, zones: nil|boolean, footsteps: nil|boolean, props: nil|boolean, elevation: nil|boolean, description: nil|string, author: nil|string, success: nil|fun(result: string), error: nil|fun(message: string)}
function mappacks.UploadMarkup(options) end

--- Lists the markup sets users have shared for one map of a map pack, newest first. mine is true on the sets the current user uploaded (which DeleteMarkup can remove). Pass an entry's id as AddMapToGame's markupId to add the map with that markup.
--- @param options {pack: string, mapid: string, success: nil|fun(entries: {id: string, pack: string, mapid: string, userid: string, author: string, description: string, mtime: number, walls: integer, wallTypes: integer, zones: integer, footsteps: integer, footstepDefault: boolean, props: integer, elevation: integer, mine: boolean}[]), error: nil|fun(message: string)}
function mappacks.ListMarkup(options) end

--- Lists the ids of the maps in a map pack that have at least one shared markup set (Codex Enhancements), so a browser can badge them without asking ListMarkup per map. Calls options.success with the map ids, or options.error with a message.
--- @param options {pack: string, success: nil|fun(mapids: string[]), error: nil|fun(message: string)}
function mappacks.ListMarkupMaps(options) end

--- Removes a shared markup set. Only the user who uploaded it may delete it (the cloud rejects anyone else).
--- @param options {pack: string, mapid: string, id: string, success: nil|fun(), error: nil|fun(message: string)}
function mappacks.DeleteMarkup(options) end
