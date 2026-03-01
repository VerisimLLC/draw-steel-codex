--- @class editor Deprecated Lua interface for DM sheet HUD operations. Use LuaInterface instead.
--- @field currentTerrainFill nil|string Gets the current terrain fill asset name for the active floor, or nil if no fill is set.
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

--- SetMapTool: Sets a custom map tool to be used temporarily. Returns an event source that fires a 'tool' event with the MapPath created by the tool, or nil if the HUD is unavailable.
--- @param toolInfo table Configuration table for the custom map tool.
--- @return nil|EventSourceLua
function editor:SetMapTool(toolInfo)
	-- dummy implementation for documentation purposes only
end
