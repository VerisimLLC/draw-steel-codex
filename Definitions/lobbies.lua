---@meta

--- Connects to Lobby servers: server-arbitrated chat/presence/roster spaces that are not games (e.g. the "eotw" Encounter of the Week lobby). Clients read the lobby document and send typed requests; all state is written server-side.
--- @class lobbies
lobbies = {}

--- Connect to the lobby with the given id (e.g. "eotw"), or return the existing shared connection to it. Options: 'staging' (bool -- use the staging server), 'displayName' (string -- self-reported name for presence and chat; defaults to the account's display name), 'route' (string -- 'lobby' (the default) or 'city': a City is a lobby that also stores every account's heroes, e.g. "blackbottom"). Returns a LuaLobbyConnection.
--- @param lobbyid string The well-known lobby or city id.
--- @param options table|nil Options: staging, displayName, route.
--- @return any
function lobbies:Connect(lobbyid, options) end
