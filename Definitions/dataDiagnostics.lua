--- @class dataDiagnostics Provides diagnostic utilities for measuring and archiving game and map data sizes.
dataDiagnostics = {}

--- GetGameSize: Asynchronously retrieves the size of the current game data in bytes and passes it to the callback.
--- @param callback function Called with the game data size as an integer.
function dataDiagnostics.GetGameSize(callback)
	-- dummy implementation for documentation purposes only
end

--- GetMapSize: Asynchronously retrieves the size of the current map data in bytes and passes it to the callback.
--- @param callback function Called with the map data size as an integer.
function dataDiagnostics.GetMapSize(callback)
	-- dummy implementation for documentation purposes only
end

--- GetGameArchiveSize: Returns the size of the current game archive basis in bytes, or nil if no archive exists.
--- @return nil|number
function dataDiagnostics.GetGameArchiveSize()
	-- dummy implementation for documentation purposes only
end

--- GetMapArchiveSize: Returns the size of the current map archive basis in bytes, or nil if no archive exists.
--- @return nil|number
function dataDiagnostics.GetMapArchiveSize()
	-- dummy implementation for documentation purposes only
end

--- ArchiveGame: Archives the current game data to a blob. Calls the callback on success.
--- @param callback function Called with no arguments when archiving completes successfully.
function dataDiagnostics.ArchiveGame(callback)
	-- dummy implementation for documentation purposes only
end

--- ArchiveMap: Archives the current map data to a blob. Calls the callback on success.
--- @param callback function Called with no arguments when archiving completes successfully.
function dataDiagnostics.ArchiveMap(callback)
	-- dummy implementation for documentation purposes only
end
