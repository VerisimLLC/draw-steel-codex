--- @class editor Deprecated Lua interface for DM sheet HUD operations. Use LuaInterface instead.
--- @field currentTerrainFill nil|string Gets the current terrain fill asset name for the active floor, or nil if no fill is set.
--- @field mouseEditSurfacePoint Vector3 The mouse position converted onto the current floor's edit surface: floor-space coordinates on the terrain the map-editing tools draw on, accounting for parallax from raised/lowered ground (the same projection wall rendering uses). Use this instead of the maphover/mappress point when comparing against wall or map geometry coordinates.
--- @field markupDoorDebug string Diagnostic dump of the markup door (openable wall) system: controller liveness, registered doors, icon pool state, and a raw per-operation filter trace. For debugging only.
--- @field supportsObjectPlacementPreview boolean True when this build supports the object placement preview for the markup object-editing filter: the object tool shows its placement ghost but does NOT place on click while the filter is active (the Map Markup panel owns placement), and the ghost's position is readable via objectPlacementPreviewPos.
--- @field objectPlacementPreviewPos nil|Vector2 The (snapped) map position of the object tool's placement preview ('ghost'), or nil when no preview is showing. While the markup object-editing filter is active, place at exactly this position so the placed object lands under the ghost.
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
--- Fields of toolInfo: tool (string: "rectangle", "shape", "free", ...), closed (boolean, default true),
--- expires (number of seconds, default 1 -- re-register from a think loop to keep the tool alive),
--- stabilization (integer, free draw only), wallSkeletons (boolean: keep the wall skeleton overlay and
--- invisible map tiles visible while the tool is active), snapToGrid (boolean: snap like the building
--- tools -- editor:snaptogrid + ctrl-to-invert -- instead of the object snap setting), editorCursor
--- (boolean: show the editor cursor dot at the snapped point where a stroke would start, like the
--- building tools do), erase (boolean: draw the stroke preview in the erase colour -- red -- rather
--- than white; display only, since a custom tool's stroke never sets building:erase).
--- @param toolInfo table Configuration table for the custom map tool.
--- @return nil|EventSourceLua
function editor:SetMapTool(toolInfo)
	-- dummy implementation for documentation purposes only
end
