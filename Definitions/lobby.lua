--- @class lobby Provides Lua access to the game lobby, allowing listing, creating, joining, and managing multiplayer games.
--- @field maxGameDetailsLength number The maximum allowed length for game description details.
--- @field maxGameTitleLength number The maximum allowed length for a game title.
--- @field maxGamePasswordLength number The maximum allowed length for a game password.
--- @field gamesRevision number A revision counter that increments whenever the games list is updated.
--- @field games LuaGameInfo[] Returns a list of LuaGameInfo objects for all non-deleted games the current user belongs to.
--- @field createdGameId nil|string The ID of the most recently created game, or nil if none has been created.
--- @field createdGameIdAge number The time in seconds since the last game was created or joined.
--- @field deletedGameId nil|string The ID of the most recently deleted game, or nil if none has been deleted.
lobby = {}

--- EnterLobbyGame: Enters the lobby game, executing the given callback when complete.
--- @param callback function The callback to invoke after entering the lobby.
function lobby:EnterLobbyGame(callback)
	-- dummy implementation for documentation purposes only
end

--- SetVisibleGames: Declares the set of games currently shown on screen. The engine keeps a live metadata subscription open only for these games (plus always-on games such as the lobby); games scrolled off-screen keep their last-fetched snapshot but stop receiving live updates. Pass a Lua array of game id strings. All of the user's games are still loaded once at startup, so the full lobby list, search, and pagination keep working regardless of what is reported here.
--- @param gameids string[] Array of game id strings currently visible on screen.
function lobby:SetVisibleGames(gameids)
	-- dummy implementation for documentation purposes only
end

--- MigrateGameToDurableObjects: Migrate an existing Firebase-backed game to Cloudflare Durable Objects. Options table can contain 'progress' (function called with status and progress 0-1) and 'complete' (function called with success bool and optional error string).
--- @param gameid string The id of the game to migrate.
--- @param options table Options with optional 'progress' and 'complete' callback fields.
function lobby:MigrateGameToDurableObjects(gameid, options)
	-- dummy implementation for documentation purposes only
end

--- MigrateGameToStagingDurableObjects: Migrate an existing Firebase-backed game to the staging Cloudflare Durable Object. Same semantics as MigrateGameToDurableObjects, but targets the staging Worker rather than release. Options table can contain 'progress' (function called with status and progress 0-1) and 'complete' (function called with success bool and optional error string).
--- @param gameid string The id of the game to migrate.
--- @param options table Options with optional 'progress' and 'complete' callback fields.
function lobby:MigrateGameToStagingDurableObjects(gameid, options)
	-- dummy implementation for documentation purposes only
end

--- CloneFirebaseGameToStagingDO: Clone a Firebase-backed game into a new game backed by the staging Durable Object. The source game is left untouched. Options table can contain 'progress' (function called with status and progress 0-1) and 'complete' (function called with success bool, new gameid string, and optional error string).
--- @param gameid string The id of the source Firebase game to clone.
--- @param options table Options with optional 'progress' and 'complete' callback fields.
function lobby:CloneFirebaseGameToStagingDO(gameid, options)
	-- dummy implementation for documentation purposes only
end

--- CloneDOGameToOtherEnvironment: Clone a Durable-Object-backed game (release or staging) into a new game backed by the OTHER DO environment. The source game is left untouched. Options table can contain 'progress' (function called with status and progress 0-1) and 'complete' (function called with success bool, new gameid string, and optional error string).
--- @param gameid string The id of the source DO game to clone.
--- @param options table Options with optional 'progress' and 'complete' callback fields.
function lobby:CloneDOGameToOtherEnvironment(gameid, options)
	-- dummy implementation for documentation purposes only
end

--- CloneGameToLocal: Clone a game (Firebase or Durable-Object-backed) into a new offline (Local) game hosted by the bundled local-game-server. The source game is left untouched. Options table can contain 'progress' (function called with status and progress 0-1) and 'complete' (function called with success bool, new gameid string, and optional error string).
--- @param gameid string The id of the source game to clone.
--- @param options table Options with optional 'progress' and 'complete' callback fields.
function lobby:CloneGameToLocal(gameid, options)
	-- dummy implementation for documentation purposes only
end

--- CreateGame: Creates a new game with the given options table. The options table may contain 'create' and 'error' callback functions. Rate-limited to one creation every 3 seconds.
--- @param options table Options with optional 'create' and 'error' callback fields.
function lobby:CreateGame(options)
	-- dummy implementation for documentation purposes only
end

--- PromoteLocalGame: Promote a local game to Durable Objects. Generates a new game id, copies all data to the cloud, verifies it, and then deletes the local copy. Options: 'gameid' (string, required - the local game's id), 'staging' (bool, optional - target the staging DO server instead of release), 'progress' (function(status, pct)), 'complete' (function(success, newGameid, error)).
--- @param options table Options table with 'gameid', optional 'staging', 'progress', and 'complete' fields.
function lobby:PromoteLocalGame(options)
	-- dummy implementation for documentation purposes only
end

--- ListRollbackBookmarks: List rollback bookmarks for a Durable-Object-backed game (storage=DurableObjects or DurableObjectsStaging). The callback receives (bookmarks, error). On success, bookmarks is a list of {id, name, bookmark, createdAt, kind, note, createdBy} tables; on failure bookmarks is nil and error is a string. The bookmarks table lives inside the DO's SQLite and shares its PITR window -- entries from before the most recent rollback may not be present.
--- @param gameid string The id of the game.
--- @param callback function Callback receiving (bookmarks, error).
function lobby:ListRollbackBookmarks(gameid, callback)
	-- dummy implementation for documentation purposes only
end

--- PerformRollback: Roll back a Durable-Object-backed game to a prior point in time using Cloudflare's SQLite Point-in-Time Recovery. The DO is aborted after scheduling the restore; the live WebSocket reconnects automatically and clients receive the full restored state. Options must include exactly one rollback target: 'name' (string -- most recent bookmark with this name), 'bookmarkId' (number -- a row id from lobby:ListRollbackBookmarks), 'bookmark' (string -- raw Cloudflare bookmark token), or 'timestampMs' (number -- ms since epoch, snapped to nearest internal snapshot). Optional fields: 'note' (string), 'progress' (function(status, pct)), 'complete' (function(success, errorOrUndoBookmark)). On success the captured pre-rollback bookmark is recorded as kind='auto-undo' in the bookmarks table.
--- @param gameid string The id of the game.
--- @param options table Target + callbacks.
function lobby:PerformRollback(gameid, options)
	-- dummy implementation for documentation purposes only
end

--- EnterGame: Enters the game with the given ID, optionally executing a Lua function after entering.
--- @param gameid string The ID of the game to enter.
--- @param executeFunction nil|function Optional function to execute after entering the game.
function lobby:EnterGame(gameid, executeFunction)
	-- dummy implementation for documentation purposes only
end

--- LookupGame: Looks up a game by its ID asynchronously. Calls the callback with a LuaGameInfo if found, or with no arguments if not found.
--- @param gameid string The ID of the game to look up.
--- @param callback function Callback receiving a LuaGameInfo on success or no arguments on failure.
function lobby:LookupGame(gameid, callback)
	-- dummy implementation for documentation purposes only
end

--- JoinGame: Joins an existing game by ID, adding the current user to the game's player list. Rate-limited to one join every 3 seconds.
--- @param gameid string
--- @return nil
function lobby:JoinGame(gameid)
	-- dummy implementation for documentation purposes only
end

--- FetchGameContent: Fetches the content (compendium tables and, on demand, characters) of another game the user belongs to, for browsing and importing into the current game. Returns a LuaRemoteGameContent immediately; options may contain 'ready' (called with the content object once fetched) and 'error' (called with an error message string). Works on Firebase, Durable Objects, and Local backends; a Local game created on another computer cannot be fetched.
--- @param gameid string The id of the source game.
--- @param options {ready: nil|fun(content: LuaRemoteGameContent), error: nil|fun(message: string)}
--- @return LuaRemoteGameContent
function lobby:FetchGameContent(gameid, options)
	-- dummy implementation for documentation purposes only
end

--- @class LuaRemoteGameContent The content of another game the user belongs to, fetched for browsing and importing into the current game. Create with lobby:FetchGameContent.
--- @field ready boolean True once the source game's asset tables have been fetched.
--- @field gameid string The id of the source game this content was fetched from.
LuaRemoteGameContent = {}

--- FetchCharacter: Fetches a single character from the source game by id (e.g. from the game's characterIndex). The callback receives a table with id, name, ownerId, partyid, and portrait fields, or nil if the character could not be fetched. Once fetched, the character participates in dependency searches and can be installed.
--- @param charid string
--- @param callback fun(info: nil|{id: string, name: string, ownerId: nil|string, partyid: nil|string, portrait: nil|string})
function LuaRemoteGameContent:FetchCharacter(charid, callback)
	-- dummy implementation for documentation purposes only
end

--- RegisterImage: Makes an image asset from the source game renderable in the current context (without installing it). Returns true if the image record was found in the source game.
--- @param imageid string
--- @return boolean
function LuaRemoteGameContent:RegisterImage(imageid)
	-- dummy implementation for documentation purposes only
end

--- GetObjectTables: Returns the source game's compendium tables as a table keyed by table id. Each entry is a list of {id, name, hidden} item summaries.
--- @return table<string,{id: string, name: string, hidden: boolean}[]>
function LuaRemoteGameContent:GetObjectTables()
	-- dummy implementation for documentation purposes only
end

--- GetTableItems: Returns the item summaries for a single compendium table in the source game, as a list of {id, name, hidden}. Cheaper than GetObjectTables when only one table is needed.
--- @param tableName string
--- @return {id: string, name: string, hidden: boolean}[]
function LuaRemoteGameContent:GetTableItems(tableName)
	-- dummy implementation for documentation purposes only
end

--- GetCharacterSummaries: Returns summaries of the characters available from the source game, keyed by character id: {id, name, portrait}. Portraits are registered so they can be used as bgimages. For snapshot-backed games (Durable Objects, Local) this covers every important character; for Firebase games it covers characters fetched so far.
--- @return table<string,{id: string, name: string, portrait: nil|string}>
function LuaRemoteGameContent:GetCharacterSummaries()
	-- dummy implementation for documentation purposes only
end

--- GetBestiary: Returns the source game's bestiary.
--- @return {monsters: {id: string, name: string, folder: nil|string, hidden: boolean}[], folders: {id: string, name: string, parentFolder: nil|string, hidden: boolean}[]}
function LuaRemoteGameContent:GetBestiary()
	-- dummy implementation for documentation purposes only
end

--- DescribeAsset: Describes an asset guid from the source game for display purposes. kind is one of character, monster, monsterFolder, tableitem, image, audio, audioFolder, object, objectFolder, imageLibrary, tilesheet, wall, or unsupported; table is set for tableitem entries. Returns nil if the guid is unknown.
--- @param guid string
--- @return nil|{name: string, kind: string, table: nil|string}
function LuaRemoteGameContent:DescribeAsset(guid)
	-- dummy implementation for documentation purposes only
end

--- ComputeClosure: Computes the dependency closure of the given selection within the source game. Takes a table whose keys are selected guids; returns a table mapping each required dependency guid to a list of the guids that need it. Characters must have been fetched with FetchCharacter to contribute their dependencies.
--- @param selectedGuids table<string,any>
--- @return table<string,string[]>
function LuaRemoteGameContent:ComputeClosure(selectedGuids)
	-- dummy implementation for documentation purposes only
end

--- GetInstallCostKB: Estimated upload cost in kilobytes of installing the given guids, using the same cost model as the import framework.
--- @param guids string[]|table<string,any>
--- @return number
function LuaRemoteGameContent:GetInstallCostKB(guids)
	-- dummy implementation for documentation purposes only
end

--- Install: Installs the given guids from the source game into the current game as permanent copies, preserving their ids so re-imports update rather than duplicate. Characters are installed unplaced; their ownership is preserved when the owning player is also in the current game, otherwise they become party-owned. The skipped list passed to complete contains guids of unsupported asset kinds (e.g. map floors) that were not installed.
--- @param options {guids: string[]|table<string,any>, progress: nil|fun(status: string, done: number, total: number), complete: nil|fun(success: boolean, error: nil|string, skipped: string[])}
function LuaRemoteGameContent:Install(options)
	-- dummy implementation for documentation purposes only
end
