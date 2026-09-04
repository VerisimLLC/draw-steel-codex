--- @class lobbies Connects to Lobby servers: server-arbitrated chat/presence/roster spaces that are not games (e.g. the "eotw" Encounter of the Week lobby). Clients read the lobby document and send typed requests; all state is written server-side.
lobbies = {}

--- Connect: Connect to the lobby with the given id (e.g. "eotw"), or return the existing shared connection to it. Options: 'staging' (bool -- use the staging server), 'displayName' (string -- self-reported name for presence and chat; defaults to the account's display name). Returns a LuaLobbyConnection.
--- @param lobbyid string The well-known lobby id.
--- @param options table|nil Options: staging, displayName.
function lobbies:Connect(lobbyid, options)
	-- dummy implementation for documentation purposes only
end
