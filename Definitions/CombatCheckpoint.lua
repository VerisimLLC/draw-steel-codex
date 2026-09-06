---@meta

--- Captures a snapshot of the current combat state, including initiative, characters, documents, and objects, for later restoration.
--- @class CombatCheckpoint
CombatCheckpoint = {}

--- Restores the game state to the snapshot captured when this checkpoint was created.
function CombatCheckpoint:Restore() end
