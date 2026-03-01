--- @class backup Provides backup and restore functionality for game and map data, including automatic periodic backups.
--- @field autoBackupInterval number The interval in minutes between automatic backups. Defaults to 20.
--- @field backupPath string The file system path where backups are stored for the current game.
--- @field manifest table The game backup manifest containing all backup entries with filenames and timestamps.
--- @field mapManifest table The map backup manifest containing all backup entries for the current map.
backup = {}

--- GetMergedMapManifest: Returns a merged manifest of the most recent backup entry for each map.
--- @return any
function backup.GetMergedMapManifest()
	-- dummy implementation for documentation purposes only
end

--- Update: Called every frame to track elapsed time and trigger automatic backups at the configured interval.
--- @return nil
function backup.Update()
	-- dummy implementation for documentation purposes only
end

--- GetEntryInfo: Returns information about a backup entry, including its size in bytes. Returns nil if the entry does not exist.
--- @param fname string The filename of the backup entry.
--- @return table|nil
function backup.GetEntryInfo(fname)
	-- dummy implementation for documentation purposes only
end

--- BackupGame: Creates a full backup of the current game state and writes it to disk.
--- @return nil
function backup.BackupGame()
	-- dummy implementation for documentation purposes only
end

--- CreateCombatCheckpoint: Creates a combat checkpoint that captures the current combat state for later restoration.
--- @return CombatCheckpoint
function backup.CreateCombatCheckpoint()
	-- dummy implementation for documentation purposes only
end

--- BackupMap: Creates a backup of the current map's info and details and writes it to disk.
--- @return nil
function backup.BackupMap()
	-- dummy implementation for documentation purposes only
end

--- DeleteBackup: Deletes a backup file by filename and removes it from both game and map manifests.
--- @param fname string
--- @return nil
function backup.DeleteBackup(fname)
	-- dummy implementation for documentation purposes only
end

--- Restore: Restores a game or map from a backup file. The args table must contain 'type' ("game" or "map"), 'fname', and optional 'error'/'success' callbacks.
--- @param args table The restore options with keys: type, fname, error, success.
--- @return boolean
function backup.Restore(args)
	-- dummy implementation for documentation purposes only
end
