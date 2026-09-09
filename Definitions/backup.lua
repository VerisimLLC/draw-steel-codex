---@meta

--- Provides backup and restore functionality for game and map data, including automatic periodic backups.
--- @class backup
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

--- Creates a full backup of the current game state and writes it to disk.
function backup.BackupGame() end

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
