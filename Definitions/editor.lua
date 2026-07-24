--- @class editor Deprecated Lua interface for DM sheet HUD operations. Use LuaInterface instead.
--- @field currentTerrainFill nil|string Gets the current terrain fill asset name for the active floor, or nil if no fill is set.
--- @field mouseEditSurfacePoint Vector3 The mouse position converted onto the current floor's edit surface: floor-space coordinates on the terrain the map-editing tools draw on, accounting for parallax from raised/lowered ground (the same projection wall rendering uses). Use this instead of the maphover/mappress point when comparing against wall or map geometry coordinates.
editor = {}

--- FillTerrain: Fills the current map floor with the given terrain type. Pass nil to clear the terrain fill.
--- @param val nil|string The terrain asset name, or nil to clear.
function editor:FillTerrain(val)
	-- dummy implementation for documentation purposes only
end

--- ShowModSettingsDialog: Opens the mod settings dialog.
--- @return nil
function editor:ShowModSettingsDialog()
	-- dummy implementation for documentation purposes only
end

--- SetMapTool: Sets a custom map tool to be used temporarily. Returns an event source that fires a 'tool' event with the MapPath created by the tool, or nil if the HUD is unavailable. toolInfo fields: tool ('free', 'rectangle', 'shape', 'objectpoints', ...), expires (seconds; keep re-calling to keep the tool alive), closed (boolean), stabilization (free draw assist), wallSkeletons (boolean; keep the wall skeleton overlay visible while this tool is active).
--- @param toolInfo table Configuration table for the custom map tool.
--- @return nil|EventSourceLua
function editor:SetMapTool(toolInfo)
	-- dummy implementation for documentation purposes only
end
