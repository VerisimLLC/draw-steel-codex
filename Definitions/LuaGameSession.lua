---@meta

--- Represents an active player session in the game, providing access to connection info, display name, and performance data.
--- @class LuaGameSession
--- @field version nil|string (Read-only) the version of the engine the user is using.
--- @field perf {min: number, max: number, mean: number, median: number, screenWidth: number, screenHeight: number, meanCPU: number, meanGPU: number, memMono: number, memUnity: number, memWorkingSet: number} Performance information from the user. The mem* values are in MB; memWorkingSet is the whole process's resident memory and is -1 if the platform doesn't report it.
--- @field loggedOut boolean True if this player has logged out of the session.
--- @field displayName string The player's display name.
--- @field displayColor Color The player's display color.
--- @field richStatus nil|string The player's rich status text, or nil if none is set.
--- @field timeSinceLastContact number Time in seconds since the last contact from this player. When @see lastContactKnown is false this is not a real age -- it is measured from the epoch, so it comes out as tens of thousands of days. It still compares correctly against any 'are they offline?' threshold; only use it to render a 'last seen' time when lastContactKnown is true.
--- @field lastContactKnown boolean True if we actually know when this player was last in contact. False when the session record carries no timestamp, in which case @see timeSinceLastContact is meaningless (see the note there).
--- @field dm boolean True if this player is the Dungeon Master.
--- @field primaryCharacter string The identifier of this player's primary character.
--- @field ping number The ping latency to this player in milliseconds.
--- @field p2pheartbeat number The peer-to-peer heartbeat timestamp.
--- @field p2pconnection nil|string The peer-to-peer connection type: 'direct' for hole-punched connection, 'relay' for proxied connection, or nil if no P2P connection.
LuaGameSession = {}
