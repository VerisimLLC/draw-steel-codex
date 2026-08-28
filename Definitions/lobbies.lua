--- @meta lobbies

--- @class lobbies Connects to Lobby servers: server-arbitrated chat/presence/roster spaces that are not games (e.g. the "eotw" Encounter of the Week lobby). Clients read the lobby document and send typed requests; all state is written server-side by the lobby's Durable Object.
lobbies = {}

--- Connect: Connect to the lobby with the given id (e.g. "eotw"), or return the existing shared connection to it. Call with colon syntax: lobbies:Connect(...). Options: staging (use the staging server), displayName (self-reported name for presence and chat; defaults to the account's display name). Returns immediately; watch .connected / MonitorStatus for readiness.
--- @param lobbyid string
--- @param options nil|{staging: nil|boolean, displayName: nil|string}
--- @return LuaLobbyConnection
function lobbies:Connect(lobbyid, options)
	-- dummy implementation for documentation purposes only
end

--- @class LuaLobbyConnection A connection to one Lobby. Read the document with GetDoc/GetPath (server-maintained; never write it), watch it with MonitorChanges/MonitorStatus, and mutate lobby state with Request. Dispose with Disconnect when the owning UI closes.
--- @field lobbyid string (Read-only) The lobby id this connection targets.
--- @field connected boolean (Read-only) True when the connection is open and authenticated -- requests succeed only in this state.
--- @field status string (Read-only) 'connecting', 'authenticating', 'connected', or 'closed'.
--- @field revision number (Read-only) Bumped on every document change; cheap to poll from a think handler.
LuaLobbyConnection = {}

--- GetDoc: The whole lobby document as a table: { chat = {msgid -> {userid,name,text,ts}}, presence = {userid -> {name,since}}, state = {games = {gameid -> record}, reservations = {userid -> reservation}} }. A game record is { gameid, hostUserid, hostName, name, public, status, players = {userid -> {name, slots}}, slotsFilled, slotsTotal, createdAt, lastHeartbeat }. A fresh copy each call -- do not mutate; mutations never reach the server.
--- @return table
function LuaLobbyConnection:GetDoc()
	-- dummy implementation for documentation purposes only
end

--- GetPath: The value at a /-separated path in the lobby document (e.g. '/state/games'), or nil if absent.
--- @param path string
--- @return any
function LuaLobbyConnection:GetPath(path)
	-- dummy implementation for documentation purposes only
end

--- Request: Send a typed request the lobby server arbitrates. Actions: 'chat' {text, gameid?} (with gameid: that game's member-only chat); 'create-game' {name, public} (one hosted game per user; grants a reservation -- follow with confirm-game); 'confirm-game' {gameid}; 'join-game' {gameid, heroes?}; 'set-heroes' {gameid, heroes} (replace the caller's hero-slot claim; members only); 'leave-game' {gameid} (the host leaving drops the whole record); 'kick-player' {gameid, userid} (host only); 'launch-game' {gameid} (host only, needs 3+ filled slots; record status -> 'launched'); 'ready-game' {gameid} (host only, sent from inside the game once setup is done; 'launched' -> 'ready', which is what waiting members enter on); 'heartbeat' {gameid} (send every ~60s while in a game; records expire after 5 quiet minutes); 'ping' (liveness no-op, sent automatically). success receives the ack's result table (e.g. {msgid} for chat, {expiresAt} for create-game); error receives a message string. State changes arrive via MonitorChanges, not the success callback.
--- @param options {action: string, args: nil|table, success: nil|fun(result: table|nil), error: nil|fun(message: string)}
--- @return nil
function LuaLobbyConnection:Request(options)
	-- dummy implementation for documentation purposes only
end

--- MonitorChanges: Register a function(path) called whenever the lobby document changes ('/' means a full snapshot replaced it). Handlers live until Disconnect.
--- @param callback fun(path: string)
--- @return nil
function LuaLobbyConnection:MonitorChanges(callback)
	-- dummy implementation for documentation purposes only
end

--- MonitorStatus: Register a function(status) called whenever the connection state changes.
--- @param callback fun(status: string)
--- @return nil
function LuaLobbyConnection:MonitorStatus(callback)
	-- dummy implementation for documentation purposes only
end

--- Disconnect: Close the underlying connection and drop all handlers. The next lobbies.Connect for this lobby opens a fresh connection.
--- @return nil
function LuaLobbyConnection:Disconnect()
	-- dummy implementation for documentation purposes only
end
