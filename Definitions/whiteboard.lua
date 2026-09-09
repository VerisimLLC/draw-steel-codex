---@meta

--- Provides whiteboard drawing management for the current map.
--- @class whiteboard
whiteboard = {}

--- Clears all whiteboard strokes drawn by other users on the current map.
function whiteboard:ClearOthers() end

--- Clears all whiteboard strokes drawn by the current user on the current map.
function whiteboard:ClearMine() end

--- Clears all whiteboard strokes from all users on the current map.
function whiteboard:ClearAll() end
