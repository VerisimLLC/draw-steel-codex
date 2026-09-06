---@meta

--- The content of another game the user belongs to, fetched for browsing and importing into the current game. Create with lobby:FetchGameContent.
--- @class LuaRemoteGameContent
--- @field gameid string The id of the source game this content was fetched from.
--- @field ready boolean True once the source game's content has been fetched.
LuaRemoteGameContent = {}

--- Fetches the content of another game the user belongs to. Returns a LuaRemoteGameContent immediately; the options table may contain 'ready' (called with the content object when the fetch completes) and 'error' (called with an error message string).
--- @param gameid string The id of the source game.
--- @param options table Options with optional 'ready' and 'error' callback fields.
--- @return LuaRemoteGameContent
function LuaRemoteGameContent.Fetch(gameid, options) end

--- Fetches a single character from the source game by id. The callback receives a table with id, name, ownerId, partyid, and portrait fields, or nil if the character could not be fetched. Once fetched, the character participates in dependency searches and can be installed.
--- @param charid string The character id (e.g. from the game's characterIndex).
--- @param callback function Called with the character summary table, or nil on failure.
function LuaRemoteGameContent:FetchCharacter(charid, callback) end

--- Makes an image asset from the source game renderable in the current context (without installing it). Returns true if the image record was found in the source game.
--- @param imageid string The image asset id.
--- @return boolean
function LuaRemoteGameContent:RegisterImage(imageid) end

--- Returns summaries of the characters available from the source game, keyed by character id: {id, name, portrait}. Portraits are registered so they can be used as bgimages. For snapshot-backed games (Durable Objects, Local) this covers every important character; for Firebase games it covers characters fetched so far.
--- @return table
function LuaRemoteGameContent:GetCharacterSummaries() end

--- Returns the item summaries for a single compendium table in the source game, as a list of {id, name, hidden}.
--- @param tableName string
--- @return table
function LuaRemoteGameContent:GetTableItems(tableName) end

--- Returns the source game's compendium tables as a table keyed by table id. Each entry is a list of {id, name, hidden} item summaries.
--- @return table
function LuaRemoteGameContent:GetObjectTables() end

--- Returns the source game's bestiary as {monsters = { {id, name, folder, hidden} }, folders = { {id, name, parentFolder, hidden} }}.
--- @return table
function LuaRemoteGameContent:GetBestiary() end

--- Describes an asset guid from the source game for display purposes. Returns {name, kind, table} where kind is one of character, monster, monsterFolder, tableitem, image, audio, audioFolder, object, objectFolder, imageLibrary, tilesheet, wall, or unsupported; table is set for tableitem entries. Returns nil if the guid is unknown.
--- @param guid string
--- @return nil|table
function LuaRemoteGameContent:DescribeAsset(guid) end

--- Computes the dependency closure of the given selection within the source game. Takes a table whose keys are selected guids; returns a table mapping each required dependency guid to a list of the guids that need it (same shape as ModuleDependencySearcher:Search). Characters must have been fetched with FetchCharacter to contribute their dependencies.
--- @param selectedGuids table Keys are the selected guid strings.
--- @return table
function LuaRemoteGameContent:ComputeClosure(selectedGuids) end

--- Estimated upload cost in kilobytes of installing the given guids, using the same cost model as the import framework.
--- @param guids table A list or set of guid strings.
--- @return integer
function LuaRemoteGameContent:GetInstallCostKB(guids) end

--- Installs the given guids from the source game into the current game as permanent copies, preserving their ids so re-imports update rather than duplicate. Options: guids (list or set of guid strings), progress (function(status, done, total)), complete (function(success, errorOrNil, skippedList)). Characters are installed unplaced; their ownership is preserved when the owning player is also in the current game, otherwise they become party-owned.
--- @param options table
function LuaRemoteGameContent:Install(options) end
