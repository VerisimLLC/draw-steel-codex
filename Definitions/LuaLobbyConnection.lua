---@meta

--- A connection to one Lobby. Read the document with GetDoc/GetPath (server-maintained; never write it), watch it with MonitorChanges/MonitorStatus, and mutate lobby state with Request. Dispose with Disconnect when the owning UI closes.
--- @class LuaLobbyConnection
--- @field lobbyid string The lobby id this connection targets.
--- @field connected boolean True when the connection is open and authenticated -- requests will succeed only in this state.
--- @field status string Connection state: 'connecting', 'authenticating', 'connected', or 'closed'.
--- @field revision number Revision counter bumped on every document change; cheap to poll from a think handler.
LuaLobbyConnection = {}

--- The whole lobby document as a table: { chat = {msgid -> {userid,name,text,ts}}, presence = {userid -> {name,since}}, state = {games = {...}, reservations = {...}} }. A fresh copy each call -- do not mutate, mutations never reach the server.
--- @return any
function LuaLobbyConnection:GetDoc() end

--- The value at a /-separated path in the lobby document (e.g. '/state/games'), or nil if absent.
--- @param path string Document path such as '/presence' or '/state/games'.
--- @return any
function LuaLobbyConnection:GetPath(path) end

--- Send a typed request the lobby server arbitrates. Options: 'action' (string, required -- e.g. 'chat', 'create-game', 'confirm-game', 'join-game', 'leave-game', 'heartbeat'), 'args' (table -- per-action arguments), 'success' (function(result)), 'error' (function(message)). The server validates the request against your identity; state changes arrive via the monitored document.
--- @param options table Options with 'action' and optional 'args', 'success', 'error'.
function LuaLobbyConnection:Request(options) end

--- Register a function(path) called whenever the lobby document changes ('/' means a full snapshot replaced it). Handlers live until Disconnect.
--- @param callback function Called with the changed document path.
function LuaLobbyConnection:MonitorChanges(callback) end

--- Register a function(status) called whenever the connection state changes.
--- @param callback function Called with the new status string.
function LuaLobbyConnection:MonitorStatus(callback) end

--- Close the underlying connection and drop all handlers. The next lobbies.Connect for this lobby opens a fresh connection.
function LuaLobbyConnection:Disconnect() end
