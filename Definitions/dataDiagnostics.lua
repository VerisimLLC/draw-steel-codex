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

--- DumpRasterState: Diagnostic: Dump the raster state for the current floor (or specified floor) so we can investigate why intensity-zero terrain is still rendering.
--- @param floorid nil|string Optional floor ID; defaults to current floor.
--- @return string A human-readable summary of the raster state.
function dataDiagnostics.DumpRasterState(floorid)
	-- dummy implementation for documentation purposes only
end

--- DumpMipChain: Diagnostic: Sample mip levels 0..N of every MapRasterMesh's _MainTex at the flat-color-4 UV (13.5/w, 1.5/h). Reveals whether mip-map garbage is leaking into the sample.
--- @return string Per-mesh per-mip pixel values.
function dataDiagnostics.DumpMipChain()
	-- dummy implementation for documentation purposes only
end

--- ToggleRasterMeshes: Diagnostic: Toggle the MeshRenderer of all MapRasterMesh objects in the scene to confirm whether they are drawing the visible water texture.
--- @param enabled boolean Whether MapRasterMesh renderers should be enabled.
--- @return number Count of renderers toggled.
function dataDiagnostics.ToggleRasterMeshes(enabled)
	-- dummy implementation for documentation purposes only
end

--- ToggleRenderersByName: Diagnostic: Toggle every visible MeshRenderer in the scene whose name matches a substring, to identify which game-object draws the surprising visual.
--- @param substring string Substring of GameObject.name to match (case-sensitive).
--- @param enabled boolean Whether matching renderers should be enabled.
--- @return number Count of renderers toggled.
function dataDiagnostics.ToggleRenderersByName(substring, enabled)
	-- dummy implementation for documentation purposes only
end

--- ArchiveMap: Archives the current map data to a blob. Calls the callback on success.
--- @param callback function Called with no arguments when archiving completes successfully.
function dataDiagnostics.ArchiveMap(callback)
	-- dummy implementation for documentation purposes only
end
