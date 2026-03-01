--- @class CombatCheckpoint Captures a snapshot of the current combat state, including initiative, characters, documents, and objects, for later restoration.
CombatCheckpoint = {}

--- Restore: Restores the game state to the snapshot captured when this checkpoint was created.
--- @return nil
function CombatCheckpoint:Restore()
	-- dummy implementation for documentation purposes only
end
