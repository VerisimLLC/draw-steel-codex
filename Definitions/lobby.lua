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

--- CreateGame: Creates a new game with the given options table. The options table may contain 'create' and 'error' callback functions. Rate-limited to one creation every 3 seconds.
--- @param options table Options with optional 'create' and 'error' callback fields.
function lobby:CreateGame(options)
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
