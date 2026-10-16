---@meta

--- Captures a snapshot of the current combat state, including initiative, characters, documents, and objects, for later restoration.
--- @class CombatCheckpoint
--- @field captureStats {totalMs: number, initiativeMs: number, characterMs: number, characterCount: number, characterBytes: number, characterCacheHits: number, documentMs: number, documentCount: number, documentMsById: table<string, number>, objectMs: number, objectCount: number, objectBytes: number, objectCacheHits: number} Diagnostics: how long creating this checkpoint took, in milliseconds, broken down by what was captured, with the number and serialized size of the characters and map objects, and how many of them were reused from the checkpoint record cache instead of serialized.
--- @field restoreStats nil|{totalMs: number, characterMs: number, documentMs: number, objectMs: number, commandMs: number, charactersRestored: number, charactersDeleted: number, charactersSkipped: number, documentsRestored: number, objectsRestored: number, objectsDeleted: number, objectsSkipped: number} Diagnostics: timings of the most recent Restore of this checkpoint in milliseconds -- comparing characters, documents and objects with the live game, and building and sending the restore commands -- and how many records it restored, deleted, or skipped without comparing because no game update had touched them since the capture. nil until Restore has run.
CombatCheckpoint = {}

--- Restores the game state to the snapshot captured when this checkpoint was created. Returns nil on success, or a message saying why nothing was restored. Tokens the restore moves slide back to their restored positions on every client. Every client then gets the 'restoreFromBackup' event with a table {quiet = boolean}; pass options.quiet = true for a follow-up restore that should not replay rewind effects (sound, screen effect).
--- @param options nil|{quiet: nil|boolean}
--- @return string|nil
function CombatCheckpoint:Restore(options) end
