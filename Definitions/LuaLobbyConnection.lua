--- @class LuaLobbyConnection A connection to one Lobby. Read the document with GetDoc/GetPath (server-maintained; never write it), watch it with MonitorChanges/MonitorStatus, and mutate lobby state with Request. Dispose with Disconnect when the owning UI closes.
--- @field lobbyid string The lobby id this connection targets.
--- @field connected boolean True when the connection is open and authenticated -- requests will succeed only in this state.
--- @field status string Connection state: 'connecting', 'authenticating', 'connected', or 'closed'.
--- @field revision number Revision counter bumped on every document change; cheap to poll from a think handler.
LuaLobbyConnection = {}

--- GetDoc: The whole lobby document as a table: { chat = {msgid -> {userid,name,text,ts}}, presence = {userid -> {name,since}}, state = {games = {...}, reservations = {...}} }. A fresh copy each call -- do not mutate, mutations never reach the server.
--- @return any
function LuaLobbyConnection:GetDoc()
	-- dummy implementation for documentation purposes only
end

--- GetPath: The value at a /-separated path in the lobby document (e.g. '/state/games'), or nil if absent.
--- @param path string Document path such as '/presence' or '/state/games'.
function LuaLobbyConnection:GetPath(path)
	-- dummy implementation for documentation purposes only
end

--- Request: Send a typed request the lobby server arbitrates. Options: 'action' (string, required -- e.g. 'chat', 'create-game', 'confirm-game', 'join-game', 'leave-game', 'heartbeat'), 'args' (table -- per-action arguments), 'success' (function(result)), 'error' (function(message)). The server validates the request against your identity; state changes arrive via the monitored document.
--- @param options table Options with 'action' and optional 'args', 'success', 'error'.
function LuaLobbyConnection:Request(options)
	-- dummy implementation for documentation purposes only
end

--- MonitorChanges: Register a function(path) called whenever the lobby document changes ('/' means a full snapshot replaced it). Handlers live until Disconnect.
--- @param callback function Called with the changed document path.
function LuaLobbyConnection:MonitorChanges(callback)
	-- dummy implementation for documentation purposes only
end

--- MonitorStatus: Register a function(status) called whenever the connection state changes.
--- @param callback function Called with the new status string.
function LuaLobbyConnection:MonitorStatus(callback)
	-- dummy implementation for documentation purposes only
end

--- Disconnect: Close the underlying connection and drop all handlers. The next lobbies.Connect for this lobby opens a fresh connection.
--- @return nil
function LuaLobbyConnection:Disconnect()
	-- dummy implementation for documentation purposes only
end
