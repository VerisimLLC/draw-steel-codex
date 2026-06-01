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
--- Recognized option keys include: description, descriptionDetails, coverart, startingModule (starter-map module id; "" for none), backend ("local"|"durableobjects"|"durableobjects-staging"|"firebase"), and noSystemModule (boolean; when true the game is created with no auto-injected system/rules module).
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
