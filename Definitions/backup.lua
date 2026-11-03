---@meta

--- Provides backup and restore functionality for game and map data, including automatic periodic backups.
--- @class backup
--- @field checkpointCacheVerify boolean Diagnostics: when true, combat checkpoints check every record they reuse from the checkpoint record cache (and every record Restore skips as unchanged) against a fresh serialization, logging an error for any change that did not come through a game update. Slower; for testing.
--- @field checkpointCacheMismatches number Diagnostics: how many checkpoint cache verify mismatches have been found since the app started (see checkpointCacheVerify).
--- @field autoBackupInterval number The interval in minutes between automatic backups. Defaults to 20.
--- @field backupPath string The file system path where backups are stored for the current game.
--- @field manifest table The game backup manifest containing all backup entries with filenames and timestamps.
--- @field mapManifest table The map backup manifest containing all backup entries for the current map.
backup = {}

--- Returns a merged manifest of the most recent backup entry for each map.
--- @return table<string, any>
function backup.GetMergedMapManifest() end

--- Called every frame to track elapsed time and trigger automatic backups at the configured interval.
function backup.Update() end

--- Returns information about a backup entry, including its size in bytes. Returns nil if the entry does not exist.
--- @param fname string The filename of the backup entry.
--- @return table|nil
function backup.GetEntryInfo(fname) end

--- Creates a full backup of the current game state and writes it to disk. With no options the backup is taken and written before this returns, which stalls that frame in a large game (about 300 ms for 4 MB of game data). With options.background = true it is taken the way the automatic backup is: a few milliseconds of serializing per frame and the files written on a worker thread, so no frame stalls; the file is identical to the one a synchronous backup would write at the moment it finishes. options.complete, if given, is called once the game and map backups are on disk, with the game backup's file name, or with nil and an error message.
--- @param options nil|{background: nil|boolean, complete: nil|fun(fname: string|nil, error: string|nil)}
function backup.BackupGame(options) end

--- Creates a combat checkpoint that captures the current combat state for later restoration.
--- @return CombatCheckpoint
function backup.CreateCombatCheckpoint() end

--- Creates a backup of the current map's info and details and writes it to disk.
--- @param timestampOverride? number
function backup.BackupMap(timestampOverride) end

--- Deletes a backup file by filename and removes it from both game and map manifests.
--- @param fname? string
function backup.DeleteBackup(fname) end

--- Restores a game from a backup file. The args table must contain 'type' ("game"), 'fname', and optional 'error'/'success' callbacks. Game restores also restore all locally-known map backups.
--- @param args table The restore options with keys: type, fname, error, success.
--- @return boolean
function backup.Restore(args) end
